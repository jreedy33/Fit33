// Supabase Edge Function: triage-shake-reports
// -----------------------------------------------------------------------------
// Phase 6 (Rage-shake v2). Runs on-demand (admin CMS "Triage shake reports"
// button) and via pg_cron every 15 minutes to turn fresh `bug_reports`
// rows — which carry rich user-authored context (description, expected
// behavior, screenshot base64, current screen, session_log, likely source
// files) — into actionable `bug_intelligence_reports` owned by the right
// agent, with a file_path + code_diff when obvious.
//
// WHY A SEPARATE FUNCTION FROM triage-bugs:
//   triage-bugs walks `bug_intelligence_fingerprints` (auto-harvested from
//   dev_session_logs and crash_reports — no human input). Shake reports
//   carry ~10x the context per row because the user literally took a
//   screenshot and described the problem. Putting them through the same
//   batch triage would (a) bury them behind log noise, and (b) waste the
//   screenshot context because triage-bugs doesn't send images to Claude.
//   This function sends the screenshot as a base64 image part so Claude
//   can actually see the bug.
//
// INVOCATION
//   - source: "cron"   → service-role invocation from pg_cron (every 15m)
//   - source: "manual" → admin CMS /api/admin action
//   - body may include { report_ids: ["<uuid>", ...] } to triage a
//     specific subset.
//
// AUTH
//   Accepts only service-role (x-cron-key) or Authorization: Bearer <service
//   role JWT>.
//
// SECRETS required
//   ANTHROPIC_API_KEY  — Claude key
//   SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY — standard edge runtime
//
// Deploy: supabase functions deploy triage-shake-reports
// -----------------------------------------------------------------------------

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { buildCorsHeaders } from "../_shared/cors.ts";

const ANTHROPIC_API_URL = "https://api.anthropic.com/v1/messages";
const ANTHROPIC_VERSION = "2023-06-01";

const MODEL = "claude-sonnet-4-20250514";
const MAX_REPORTS_PER_RUN = 10;        // bounded Claude spend
const MAX_SESSION_LOG_CHARS = 12_000;  // cap prompt budget
// Sonnet 4 supports up to 64K output tokens. With MAX_REPORTS_PER_RUN=10 and
// per-report code_diff blocks, 4096 was too tight and could truncate JSON
// mid-string, causing "Could not parse Claude response" errors. 16384 gives
// ~4x headroom while still bounding spend.
const CLAUDE_MAX_TOKENS = 16384;

const EXPECTED_PROJECT_REF = (() => {
    const raw = Deno.env.get("SUPABASE_URL") || "";
    const match = raw.match(/^https?:\/\/([a-z0-9]+)\.supabase\.co/i);
    return match?.[1] ?? "";
})();

function isServiceRoleJWT(token: string): boolean {
    try {
        const parts = token.split(".");
        if (parts.length !== 3) return false;
        const payload = JSON.parse(atob(parts[1]));
        if (payload.role !== "service_role") return false;
        if (!EXPECTED_PROJECT_REF) return false;
        return payload.ref === EXPECTED_PROJECT_REF;
    } catch {
        return false;
    }
}

// Shares the agent roster / severity / confidence scheme with triage-bugs
// on purpose — reports from both pipelines feed the same admin UI and
// MASTER_TODO.md. If you edit one of these prompts, mirror the change in
// the other so the leaderboard stays coherent.
const SYSTEM_PROMPT = `You are the Fit33 Rage-Shake Triage Agent. You receive bug reports that the \
user filed by shaking the phone OR via Settings → Report Bug. Each report carries: \
a user description, an expected behavior, a screenshot (image), the screen the user \
was on when it happened, a severity the user self-assigned, a session log (~100 \
recent events: screen transitions, taps, api calls, errors), a PRE-COMPUTED \
list of likely source files for that screen (see "likely_source_files"), AND — \
the Phase 7 "Cheat Code" — a STRUCTURED RUNTIME STATE SNAPSHOT captured at the exact \
moment the user shook, showing the @Published values of every major ObservableObject \
singleton (see "state_snapshot"). \
Your job: produce ONE actionable agent-owned report per shake report.

# STATE SNAPSHOT (Phase 7 — this is the most important single input)

When "state_snapshot" is present, treat it as the smoking gun for silent-logic bugs.
Each top-level key is a singleton service (e.g. "WeightTrackingService"); the inner
object lists published values + computed properties at the moment of shake. The
"__captured_at" ISO timestamp sits alongside and lets you reason about the age
of cached values (e.g. "lastLoadAgeSeconds: 45" = data is 45s stale).

Typical divergences and how to read them:
 - "todayLog.id" ≠ "recentLogs.first.id"  →  optimistic insert got wiped by a
    stale SELECT / read-after-write race (see reports 40 / 66, fixed 3f0156d).
 - "hasLoggedToday: true" but "todayLog: null"  →  cached flag drift.
 - "pendingNavigationFlags: ['toWorkoutTab', 'toAutoGen']"  →  navigation flag
    stuck true — classic cause of "tab won't dismiss" / ghost redirects.
 - "currentWorkout.isNil: true" + "isWorkoutActive: true"  →  workout manager
    out of sync after background resume.

If the state snapshot reveals a concrete divergence, your confidence should rise
to 0.85-0.90 and your summary should QUOTE the divergent values ("todayLog.weightLbs=199
vs recentLogs.first.weightLbs=190"). Never reference "state_snapshot" by key name in
the user-facing title — translate it into a human sentence.

# AGENT ROSTER (pick exactly one agent_owner per report)

- quality-performance: crashes, memory leaks, perf, accessibility, HealthKit observer
  ownership, video prefetch, AVAudioSession, reduce-motion, sync Core Data in init(),
  DispatchQueue.main.asyncAfter instead of Task.sleep, print() calls, force unwraps.
- product-engineer: navigation bugs, new UI screen issues, widget state, offline queue,
  StoreKit, blocking/reporting UI, admin CMS cookie wiring.
- data-backend: DTO / RPC issues, realtime breakage, Core Data context misuse,
  API endpoint contract mismatches, iOS<->Supabase sync.
- infra-security: secrets leakage, auth flow bugs, edge function access control,
  CSP mismatches, non-httpOnly cookies, content moderation pipeline.
- supabase-expert: schema / migration, missing RLS, SECURITY DEFINER without auth.uid(),
  missing REPLICA IDENTITY FULL, view missing security_invoker=on, dead tables.
- design-system: hardcoded .system(size:), hardcoded padding/radius, missing ds_* tokens.
- design: pure visual regressions where the token value is wrong.
- fitness-expert: exercise pairing, program split, workout validation, auto-gen
  workout correctness, exercise DB data issues.
- device-compatibility: iPad layout, responsive spacing, cross-device regressions.
- support: FAQ gaps, pain-point tracking, bug-to-feature mapping.
- unknown: only when the evidence genuinely doesn't map.

# HOW TO PICK A FILE (use likely_source_files as the primary hint)

The shake form auto-computes \`likely_source_files\` from the current screen via
a static map (ScreenCodeMap.swift). Example: screen "Dashboard" → ["Fit33/DashboardView.swift",
"Fit33/DashboardView+Helpers.swift", "Fit33/DashboardWorkoutCards.swift", ...].

1. If the description + screenshot + session log clearly point to ONE file in
   \`likely_source_files\`, emit that as \`file_path\`.
2. If the session_log contains an error entry tagged with a component
   (e.g. "[WorkoutManager]", "[CrashReporter]"), prefer the tagged file even
   if it's NOT in \`likely_source_files\`.
3. If you can't choose a single file with >=0.6 confidence, set file_path=null
   and leave code_diff=null. DO NOT guess.

# CODE DIFF GUIDANCE

- If the bug is a visible UX regression (e.g. "add to cart button does nothing")
  AND you can identify the handler in one of the likely_source_files, emit a
  unified diff. Mark confidence 0.7-0.85 (you haven't read the file, only
  inferred).
- If the bug is a crash / data issue / anything requiring the file contents to
  fix responsibly, leave code_diff=null and describe the fix in \`summary\`
  instead. Mark confidence 0.5-0.7.
- Never emit a code_diff with confidence > 0.9 — there are no crash traces in
  shake reports, so 0.9+ would be overconfident.

# SEVERITY (respect user's self-reported severity as the floor)

The user picked a severity. You may UPGRADE it (e.g. user said "medium" but the
screenshot shows a clear crash / data-loss UI) but never DOWNGRADE — user pain
is the source of truth for shake reports.

- critical: crash / data-loss / blocks a core flow (workout, auth).
- high: reliably visible malfunction.
- medium: intermittent / workaround exists.
- low: cosmetic / polish.

# CONFIDENCE

- 0.8+: clear text + screenshot + log evidence pointing to one file.
- 0.6-0.8: plausible file + plausible fix.
- 0.4-0.6: know the owner but not the file.
- <0.4: genuinely ambiguous — use agent_owner="unknown".

# USER_CONTEXT (use it, never echo it verbatim)

Each report includes a \`user_context\` block we server-side-joined from
\`user_profiles\` (email, display name, account age, onboarding state, experience
level, total workouts, streak, verified flags, unit preferences). USE IT TO:

1. Distinguish onboarding bugs (\`has_completed_onboarding=false\`) from
   steady-state bugs — a beginner hitting an advanced-only code path is a
   different bug from an advanced user seeing the same error.
2. Recognize unit-mismatch bugs — if the screenshot shows lbs but the user has
   \`weight_unit=kg\` (or vice versa), flag it explicitly in \`summary\`.
3. Detect empty-state bugs — \`total_workouts=0\` + crash on stats screen is
   almost certainly "missing empty state", not a general bug.
4. Confirm support can reach the user — if \`email\` is null, note in
   \`suggested_todo\` that follow-up will need an in-app ping.

DO NOT paste the email / user_id into \`summary\`, \`title\`, or \`code_diff\`.
These land in MASTER_TODO.md and GitHub PRs — they must stay PII-free.
Refer to the reporter as "the user" or "an advanced user on <os_version>".

# PAIN_POINT_CANDIDATE

If the shake suggests a repeated pain point (e.g. "timer keeps resetting"),
propose one 1-line entry for SUPPORT_AGENT pain registry. Otherwise null.

# SUGGESTED_TODO

One line for MASTER_TODO.md (owner + action + why). Null if not actionable.

# OUTPUT (JSON only — no markdown, no prose, no code fences)

{
  "reports": [
    {
      "bug_report_id": "<uuid>",
      "agent_owner": "quality-performance",
      "invariant_violated": "no force unwraps (swiftui-rules #2)",
      "severity": "high",
      "confidence": 0.75,
      "title": "...",
      "summary": "...",
      "file_path": "Fit33/Dashboard.swift",
      "code_diff": "--- a/...\\n+++ b/...\\n@@ ...",
      "pain_point_candidate": "...",
      "suggested_todo": "..."
    }
  ]
}

Produce ONE report per input bug_report. \`bug_report_id\` must match the input uuid exactly.`;

// -----------------------------------------------------------------------------
// Types
// -----------------------------------------------------------------------------

interface BugReportRow {
    id: string;
    user_id: string | null;
    user_name: string | null;
    user_email: string | null;
    description: string;
    expected_behavior: string | null;
    reproduces_every_time: boolean;
    additional_info: string | null;
    screenshot_base64: string | null;
    screen_name: string | null;
    likely_source_files: string[];
    severity: string;
    bug_category: string | null;
    session_log: string | null;
    // Phase 7 Cheat Code — structured runtime state at shake time.
    // Keyed by service name (e.g. "WeightTrackingService"); values are
    // shallow dicts of scalar @Published fields. See
    // Fit33/BugReportStateSnapshot.swift + Providers.swift for the
    // producing side. Always an object; default '{}' from the DB.
    state_snapshot: Record<string, unknown>;
    device_model: string | null;
    os_version: string | null;
    app_version: string | null;
    triage_status: string;
    created_at: string;
}

// Shape of the per-user context we compose from user_profiles + auth metadata.
// Keep to fields that help Claude reason about the bug without leaking PII
// beyond what's already in bug_reports (name / email). Claude is told NEVER
// to echo this block verbatim.
interface UserContext {
    user_id: string | null;
    email: string | null;
    display_name: string | null;
    account_age_days: number | null;
    has_completed_onboarding: boolean | null;
    experience_level: string | null;       // beginner / intermediate / advanced
    strength_level: string | null;
    fitness_goal: string | null;
    available_days: number | null;
    equipment_count: number | null;
    total_workouts: number | null;
    current_streak: number | null;
    is_verified: boolean | null;
    is_gold_verified: boolean | null;
    weight_unit: string | null;
    height_unit: string | null;
    distance_unit: string | null;
}

interface ClaudeReport {
    bug_report_id: string;
    agent_owner: string;
    invariant_violated: string | null;
    severity: "critical" | "high" | "medium" | "low";
    confidence: number;
    title: string;
    summary: string;
    file_path: string | null;
    code_diff: string | null;
    pain_point_candidate: string | null;
    suggested_todo: string | null;
}

const VALID_AGENTS = new Set([
    "quality-performance",
    "product-engineer",
    "data-backend",
    "infra-security",
    "supabase-expert",
    "design-system",
    "design",
    "fitness-expert",
    "device-compatibility",
    "support",
    "unknown",
]);

// -----------------------------------------------------------------------------
// Entry point
// -----------------------------------------------------------------------------

serve(async (req) => {
    const corsHeaders = buildCorsHeaders(req);
    if (req.method === "OPTIONS") {
        return new Response("ok", { headers: corsHeaders });
    }

    try {
        const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
        const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
        const anthropicKey = Deno.env.get("ANTHROPIC_API_KEY");

        if (!anthropicKey) {
            return json({ error: "ANTHROPIC_API_KEY not configured" }, 500, corsHeaders);
        }

        const supabase = createClient(supabaseUrl, supabaseServiceKey);

        // ── Auth: service-role only ──────────────────────────────────────
        const cronKey = req.headers.get("x-cron-key");
        const authHeader = req.headers.get("Authorization");
        let authorized = false;
        if (cronKey && isServiceRoleJWT(cronKey)) authorized = true;
        else if (authHeader) {
            const token = authHeader.replace("Bearer ", "");
            if (token === supabaseServiceKey || isServiceRoleJWT(token)) authorized = true;
        }
        if (!authorized) {
            return json({ error: "Unauthorized (service role required)" }, 401, corsHeaders);
        }

        let body: { source?: string; report_ids?: string[] } = {};
        try { body = await req.json(); } catch { /* empty body ok */ }
        const source = body.source ?? "cron";
        const explicitIds = Array.isArray(body.report_ids)
            ? body.report_ids.filter((x) => typeof x === "string")
            : null;

        // ── 1. Select pending bug_reports via view ──────────────────────
        let q = supabase
            .from("v_bug_reports_for_triage")
            .select(
                "id, user_id, user_name, user_email, description, expected_behavior, " +
                "reproduces_every_time, additional_info, screenshot_base64, " +
                "screen_name, likely_source_files, severity, bug_category, " +
                "session_log, state_snapshot, device_model, os_version, app_version, " +
                "triage_status, created_at",
            )
            .eq("triage_status", "pending")
            .order("created_at", { ascending: false })
            .limit(MAX_REPORTS_PER_RUN);

        if (explicitIds && explicitIds.length > 0) {
            q = q.in("id", explicitIds);
        }

        const { data: reports, error: selErr } = await q;
        if (selErr) {
            console.error("triage-shake-reports: select error", selErr);
            return json({ error: selErr.message }, 500, corsHeaders);
        }

        const rows = ((reports ?? []) as BugReportRow[]);
        if (rows.length === 0) {
            return json({ message: "No pending shake reports", source, triaged: 0 }, 200, corsHeaders);
        }

        // Mark 'analyzing' so a concurrent cron run skips them.
        await Promise.all(rows.map((r) =>
            supabase.rpc("mark_shake_report_triaged", {
                p_bug_report_id: r.id,
                p_triage_report_id: null,
                p_status: "analyzing",
                p_error: null,
            })
        ));

        // ── 2. Enrich with user_profiles (so Claude can reason about the
        //       reporter: experience level, onboarding state, unit prefs).
        //       Done server-side on purpose — keeps the iOS payload small
        //       and lets us change the shape without a client rebuild.
        const userContexts = await loadUserContexts(supabase, rows);

        // ── 3. Build user prompt per report (multimodal if screenshot) ──
        const contentParts = buildUserPrompt(rows, userContexts);

        // ── 4. Call Claude ──────────────────────────────────────────────
        const response = await fetch(ANTHROPIC_API_URL, {
            method: "POST",
            headers: {
                "content-type": "application/json",
                "x-api-key": anthropicKey,
                "anthropic-version": ANTHROPIC_VERSION,
            },
            body: JSON.stringify({
                model: MODEL,
                max_tokens: CLAUDE_MAX_TOKENS,
                system: SYSTEM_PROMPT,
                messages: [{ role: "user", content: contentParts }],
            }),
        });

        if (!response.ok) {
            const errBody = await response.text();
            console.error("triage-shake-reports: Anthropic API error", response.status, errBody);
            // Unstick the rows so a later run can retry.
            await Promise.all(rows.map((r) =>
                supabase.rpc("mark_shake_report_triaged", {
                    p_bug_report_id: r.id,
                    p_triage_report_id: null,
                    p_status: "failed",
                    p_error: `Anthropic ${response.status}: ${errBody.slice(0, 300)}`,
                })
            ));
            return json({
                error: `Anthropic API ${response.status}`,
                body: errBody.slice(0, 500),
            }, 502, corsHeaders);
        }

        const completion = await response.json() as {
            content?: Array<{ type: string; text?: string }>;
            stop_reason?: string;
            usage?: { input_tokens?: number; output_tokens?: number };
        };
        const block = completion.content?.find((b) => b.type === "text");
        const text = block?.text ?? "";
        const stopReason = completion.stop_reason ?? "unknown";
        const usage = completion.usage ?? {};
        console.log(
            `triage-shake-reports: Claude completed stop_reason=${stopReason} ` +
            `input_tokens=${usage.input_tokens ?? "?"} ` +
            `output_tokens=${usage.output_tokens ?? "?"} ` +
            `text_chars=${text.length}`,
        );
        if (stopReason === "max_tokens") {
            console.warn(
                "triage-shake-reports: Claude hit max_tokens — response was truncated. " +
                "Will attempt to salvage complete reports.",
            );
        }
        const parsed = parseClaudeJson(text);

        if (!parsed || parsed.reports.length === 0) {
            console.error("triage-shake-reports: failed to parse Claude response");
            await Promise.all(rows.map((r) =>
                supabase.rpc("mark_shake_report_triaged", {
                    p_bug_report_id: r.id,
                    p_triage_report_id: null,
                    p_status: "failed",
                    p_error: "Could not parse Claude JSON response",
                })
            ));
            return json({
                error: "Could not parse Claude response",
                stop_reason: stopReason,
                output_tokens: usage.output_tokens ?? null,
                raw_sample: text.slice(0, 500),
                raw_tail: text.slice(-500),
            }, 500, corsHeaders);
        }

        // ── 5. Create synthetic fingerprint + report, link back ────────
        const results = await writeReports(supabase, parsed.reports, rows, source);

        return json({
            message: "Shake triage complete",
            source,
            candidates: rows.length,
            reports_written: results.written,
            reports_skipped: results.skipped,
        }, 200, corsHeaders);

    } catch (error) {
        console.error("triage-shake-reports error:", error);
        return json(
            { error: error instanceof Error ? error.message : String(error) },
            500,
            buildCorsHeaders(req),
        );
    }
});

// -----------------------------------------------------------------------------
// Prompt assembly
// -----------------------------------------------------------------------------

// Anthropic messages API content array. Mixes text + base64 images so Claude
// can literally look at the screenshot. Screenshots live in
// bug_reports.screenshot_base64 as raw base64 (no "data:image/png;base64,"
// prefix); we pass them as image blocks. When a report has no screenshot we
// just skip that block.
type ContentPart =
    | { type: "text"; text: string }
    | { type: "image"; source: { type: "base64"; media_type: string; data: string } };

// Shape of the row we pull from user_profiles. Subset picked to balance
// usefulness-to-Claude vs PII blast radius. `equipment` is reduced to a count
// so Claude can reason about "user has no equipment configured" without
// memorizing the array.
interface UserProfileRow {
    id: string;
    email: string | null;
    name: string | null;
    created_at: string | null;
    has_completed_onboarding: boolean | null;
    experience_level: string | null;
    strength_level: string | null;
    fitness_goal: string | null;
    available_days: number | null;
    equipment: string[] | null;
    total_workouts: number | null;
    current_streak: number | null;
    is_verified: boolean | null;
    is_gold_verified: boolean | null;
    weight_unit: string | null;
    height_unit: string | null;
    distance_unit: string | null;
}

// Fetch user_profiles for every report in `rows`, keyed by bug_report.id so
// buildUserPrompt can look it up without rethreading user_id. Falls back to
// a skeleton context built from bug_reports columns when we can't find a
// profile (anonymous shake, deleted user, pre-migration row).
async function loadUserContexts(
    // deno-lint-ignore no-explicit-any
    supabase: any,
    rows: BugReportRow[],
): Promise<Map<string, UserContext>> {
    const result = new Map<string, UserContext>();

    const userIds = Array.from(
        new Set(rows.map((r) => r.user_id).filter((x): x is string => !!x)),
    );
    const profilesById = new Map<string, UserProfileRow>();

    if (userIds.length > 0) {
        const { data, error } = await supabase
            .from("user_profiles")
            .select(
                "id, email, name, created_at, has_completed_onboarding, " +
                "experience_level, strength_level, fitness_goal, available_days, " +
                "equipment, total_workouts, current_streak, is_verified, " +
                "is_gold_verified, weight_unit, height_unit, distance_unit",
            )
            .in("id", userIds);
        if (error) {
            // Don't fail triage just because enrichment failed — Claude can
            // still triage without the profile block. Log loudly so the next
            // run surfaces the issue via the admin inbox.
            console.error("triage-shake-reports: user_profiles lookup error", error);
        } else {
            for (const p of (data ?? []) as UserProfileRow[]) {
                profilesById.set(p.id, p);
            }
        }
    }

    for (const r of rows) {
        const p = r.user_id ? profilesById.get(r.user_id) ?? null : null;
        result.set(r.id, {
            user_id: r.user_id,
            email: p?.email ?? r.user_email ?? null,
            display_name: p?.name ?? r.user_name ?? null,
            account_age_days: accountAgeDays(p?.created_at ?? null),
            has_completed_onboarding: p?.has_completed_onboarding ?? null,
            experience_level: p?.experience_level ?? null,
            strength_level: p?.strength_level ?? null,
            fitness_goal: p?.fitness_goal ?? null,
            available_days: p?.available_days ?? null,
            equipment_count: Array.isArray(p?.equipment) ? p!.equipment!.length : null,
            total_workouts: p?.total_workouts ?? null,
            current_streak: p?.current_streak ?? null,
            is_verified: p?.is_verified ?? null,
            is_gold_verified: p?.is_gold_verified ?? null,
            weight_unit: p?.weight_unit ?? null,
            height_unit: p?.height_unit ?? null,
            distance_unit: p?.distance_unit ?? null,
        });
    }

    return result;
}

// iOS sometimes sends JPEG (smaller on the wire) and sometimes PNG. Anthropic
// rejects the request with 400 if the declared media_type doesn't match the
// bytes. We sniff the base64 header: JPEG base64 starts with "/9j/" (the
// 0xFF 0xD8 0xFF... SOI marker); PNG base64 starts with "iVBOR" (the 0x89
// 'PNG' magic). Default to PNG only if it's clearly not JPEG — safest fallback
// since most server-rendered PNGs lack a recognizable base64 prefix beyond
// "iVBOR".
function sniffImageMediaType(b64: string): "image/jpeg" | "image/png" {
    const head = b64.slice(0, 12);
    if (head.startsWith("/9j/")) return "image/jpeg";
    if (head.startsWith("iVBOR")) return "image/png";
    // Unknown header → prefer jpeg since iOS default screenshot path in
    // BugReportView uses .jpegData(compressionQuality:) for payload size.
    return "image/jpeg";
}

function accountAgeDays(createdAt: string | null): number | null {
    if (!createdAt) return null;
    const ts = Date.parse(createdAt);
    if (Number.isNaN(ts)) return null;
    return Math.max(0, Math.floor((Date.now() - ts) / 86_400_000));
}

function buildUserPrompt(
    rows: BugReportRow[],
    userContexts: Map<string, UserContext>,
): ContentPart[] {
    const parts: ContentPart[] = [{
        type: "text",
        text: `Triage the following ${rows.length} Fit33 shake bug report(s). ` +
            `Return a single JSON object { "reports": [...] } with exactly one report per input. ` +
            `\`bug_report_id\` must be echoed back unchanged.`,
    }];

    for (const r of rows) {
        const sessionLog = (r.session_log ?? "").slice(-MAX_SESSION_LOG_CHARS);
        const userCtx = userContexts.get(r.id) ?? null;
        // Phase 7 — state snapshot lifted OUT of the giant JSON blob and
        // formatted as its own labeled block so Claude reads it first.
        // Empty dicts / nulls become null so the prompt stays compact.
        const stateSnap = compactStateSnapshot(r.state_snapshot);
        const textBlock = JSON.stringify({
            bug_report_id: r.id,
            reporter: r.user_name ?? "anonymous",
            created_at: r.created_at,
            device: {
                model: r.device_model,
                os: r.os_version,
                app_version: r.app_version,
            },
            screen_name: r.screen_name,
            user_severity: r.severity,
            user_bug_category: r.bug_category,
            description: r.description,
            expected_behavior: r.expected_behavior,
            reproduces_every_time: r.reproduces_every_time,
            additional_info: r.additional_info,
            likely_source_files: r.likely_source_files ?? [],
            user_context: userCtx,
            state_snapshot: stateSnap,
            session_log_tail: sessionLog,
        }, null, 2);
        parts.push({ type: "text", text: `\n---\n${textBlock}` });

        if (r.screenshot_base64 && r.screenshot_base64.length > 0) {
            parts.push({
                type: "image",
                source: {
                    type: "base64",
                    media_type: sniffImageMediaType(r.screenshot_base64),
                    data: r.screenshot_base64,
                },
            });
        }
    }

    return parts;
}

// Phase 7 — filter + compact the runtime state dict before embedding it
// in the Claude prompt. Keeps the payload small and the block scannable:
//   - Drops empty service dicts (post-registration, a service may exist
//     but have no publishable state).
//   - Preserves __captured_at at the top so Claude can reason about age.
//   - Returns null rather than {} so the JSON above shows `null`, not
//     visual noise, when no snapshot shipped (pre-Phase 7 clients).
function compactStateSnapshot(
    raw: Record<string, unknown> | null | undefined,
): Record<string, unknown> | null {
    if (!raw || typeof raw !== "object") return null;
    const keys = Object.keys(raw);
    if (keys.length === 0) return null;
    const out: Record<string, unknown> = {};
    for (const k of keys) {
        const v = raw[k];
        // Preserve scalar top-level metadata (e.g. __captured_at).
        if (v === null || typeof v !== "object") {
            out[k] = v;
            continue;
        }
        // Drop empty service blocks so the prompt stays compact.
        if (Array.isArray(v) && v.length === 0) continue;
        if (!Array.isArray(v) && Object.keys(v as Record<string, unknown>).length === 0) continue;
        out[k] = v;
    }
    return Object.keys(out).length > 0 ? out : null;
}

function parseClaudeJson(text: string): { reports: ClaudeReport[] } | null {
    const match = text.match(/\{[\s\S]*\}/);
    if (match) {
        try {
            const obj = JSON.parse(match[0]);
            if (obj && Array.isArray(obj.reports)) {
                return obj as { reports: ClaudeReport[] };
            }
        } catch {
            // fall through to salvage path
        }
    }
    // Salvage path — Claude truncated mid-JSON (usually max_tokens). Recover
    // whatever complete report objects we can.
    const reports = salvageReports(text);
    if (reports.length === 0) return null;
    console.warn(`triage-shake-reports: salvaged ${reports.length} report(s) from truncated Claude output`);
    return { reports };
}

function salvageReports(text: string): ClaudeReport[] {
    const arrStart = text.search(/"reports"\s*:\s*\[/);
    if (arrStart < 0) return [];
    const bracketIdx = text.indexOf("[", arrStart);
    if (bracketIdx < 0) return [];

    const out: ClaudeReport[] = [];
    let i = bracketIdx + 1;

    while (i < text.length) {
        while (i < text.length && (text[i] === "," || /\s/.test(text[i]))) i++;
        if (i >= text.length) break;
        if (text[i] === "]") break;
        if (text[i] !== "{") break;

        const start = i;
        let depth = 0;
        let inString = false;
        let escape = false;
        let end = -1;
        for (let j = start; j < text.length; j++) {
            const ch = text[j];
            if (escape) { escape = false; continue; }
            if (ch === "\\") { escape = true; continue; }
            if (ch === '"') { inString = !inString; continue; }
            if (inString) continue;
            if (ch === "{") depth++;
            else if (ch === "}") {
                depth--;
                if (depth === 0) { end = j; break; }
            }
        }
        if (end < 0) break;

        const objText = text.slice(start, end + 1);
        try {
            const obj = JSON.parse(objText);
            if (obj && typeof obj === "object") {
                out.push(obj as ClaudeReport);
            }
        } catch {
            break;
        }
        i = end + 1;
    }
    return out;
}

// -----------------------------------------------------------------------------
// Write-back
//   Each shake report gets:
//     (a) a synthetic `bug_intelligence_fingerprints` row with source='shake'
//         (unique per bug_report id — 'shake:<uuid>' md5 keeps the FK happy
//         without polluting trend signal for log/crash fingerprints)
//     (b) a `bug_intelligence_reports` row pointing at that fingerprint
//     (c) bug_reports.triage_report_id updated to (b).id
// -----------------------------------------------------------------------------

interface WriteResult {
    written: number;
    skipped: number;
}

async function writeReports(
    // deno-lint-ignore no-explicit-any
    supabase: any,
    reports: ClaudeReport[],
    rows: BugReportRow[],
    source: string,
): Promise<WriteResult> {
    const byId = new Map(rows.map((r) => [r.id, r]));
    let written = 0;
    let skipped = 0;

    for (const r of reports) {
        const row = byId.get(r.bug_report_id);
        if (!row) { skipped++; continue; }

        const agent = VALID_AGENTS.has(r.agent_owner) ? r.agent_owner : "unknown";
        // Respect user severity as the floor (never downgrade).
        const severity = upgradeOnly(row.severity, r.severity);
        const confidence = typeof r.confidence === "number"
            ? Math.max(0, Math.min(0.9, r.confidence)) // cap at 0.9 for shake
            : 0.55;

        // (a) synthetic fingerprint — stable per bug_report id
        const fingerprint = await digestShakeId(row.id);
        const { error: fpErr } = await supabase
            .from("bug_intelligence_fingerprints")
            .upsert({
                fingerprint,
                source: "shake",
                normalized_message: (row.description || "shake report").slice(0, 500),
                sample_message: (row.description || "shake report").slice(0, 1000),
                error_domain: null,
                first_seen_at: row.created_at,
                last_seen_at: row.created_at,
                first_seen_app_version: row.app_version,
                last_seen_app_version: row.app_version,
                occurrence_count: 1,
                unique_user_count: row.user_id ? 1 : 0,
                affected_screens: row.screen_name ? [row.screen_name] : [],
                assigned_agent: agent,
                status: "triaged",
            }, { onConflict: "fingerprint" });

        if (fpErr) {
            console.error("triage-shake-reports: fingerprint upsert error", fpErr);
            await supabase.rpc("mark_shake_report_triaged", {
                p_bug_report_id: row.id,
                p_triage_report_id: null,
                p_status: "failed",
                p_error: `Fingerprint upsert: ${fpErr.message}`,
            });
            skipped++;
            continue;
        }

        // (b) bug_intelligence_reports row
        const { data: inserted, error: repErr } = await supabase
            .from("bug_intelligence_reports")
            .insert({
                fingerprint,
                trigger_trend_id: null,
                trigger_reason: source === "manual" ? "manual" : "scheduled",
                agent_owner: agent,
                invariant_violated: r.invariant_violated ?? null,
                severity,
                confidence,
                title: String(r.title ?? row.description).slice(0, 300),
                summary: String(r.summary ?? "").slice(0, 2000),
                file_path: r.file_path ?? null,
                code_diff: r.code_diff ?? null,
                pain_point_candidate: r.pain_point_candidate ?? null,
                suggested_todo: r.suggested_todo ?? null,
                analysis_model: MODEL,
                raw_response: r as unknown as Record<string, unknown>,
                example_entry_ids: [`shake:${row.id}`],
            })
            .select("id")
            .single();

        if (repErr || !inserted) {
            console.error("triage-shake-reports: report insert error", repErr);
            await supabase.rpc("mark_shake_report_triaged", {
                p_bug_report_id: row.id,
                p_triage_report_id: null,
                p_status: "failed",
                p_error: `Report insert: ${repErr?.message ?? "unknown"}`,
            });
            skipped++;
            continue;
        }

        // (c) link back
        const { error: linkErr } = await supabase.rpc("mark_shake_report_triaged", {
            p_bug_report_id: row.id,
            p_triage_report_id: inserted.id,
            p_status: "analyzed",
            p_error: null,
        });
        if (linkErr) {
            console.error("triage-shake-reports: link error", linkErr);
            // Row was still triaged successfully from Claude's POV; log and move on.
        }
        written++;
    }

    return { written, skipped };
}

// User picks severity; Claude may only upgrade. Maps string → int to make
// max() trivial then back.
function upgradeOnly(user: string, claude: string): "critical" | "high" | "medium" | "low" {
    const rank: Record<string, number> = { low: 0, medium: 1, high: 2, critical: 3 };
    const u = rank[user] ?? 1;
    const c = rank[claude] ?? 1;
    const max = Math.max(u, c);
    return (["low", "medium", "high", "critical"] as const)[max];
}

// MD5 not available natively in Deno; use Web Crypto SHA-256 and truncate
// to 32 hex chars so the fingerprint matches the length of the MD5 ones
// produced by the SQL bug_intelligence_fingerprint() helper. Stable per
// bug_report id, which is what we need for the FK to hold.
async function digestShakeId(reportId: string): Promise<string> {
    const buf = new TextEncoder().encode(`shake:${reportId}`);
    const hash = await crypto.subtle.digest("SHA-256", buf);
    const hex = Array.from(new Uint8Array(hash))
        .map((b) => b.toString(16).padStart(2, "0"))
        .join("");
    return hex.slice(0, 32);
}

// -----------------------------------------------------------------------------
// JSON helper
// -----------------------------------------------------------------------------

function json(body: unknown, status: number, corsHeaders: Record<string, string>): Response {
    return new Response(JSON.stringify(body), {
        status,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
}
