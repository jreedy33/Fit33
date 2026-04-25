// Supabase Edge Function: triage-bugs
// -----------------------------------------------------------------------------
// Phase 2 of the Bug Intelligence Pipeline. Runs every 4h via pg_cron
// (trigger_triage_bugs). Reads the top open fingerprints + recent trend
// signals, enriches each with example log/crash evidence, calls Claude to
// produce an assigned, agent-owned, fixable report, and writes the result
// into `bug_intelligence_reports`.
//
// INVOCATION
//   - source: "cron"   → service-role invocation from pg_cron
//   - source: "manual" → admin CMS /api/admin action
//   - POST body may include { fingerprints: ["<md5>", ...] } to triage a
//     specific subset. If omitted, selects the top N by:
//       1. new/regression trends in last 24h (unreviewed)
//       2. open fingerprints with highest recent occurrences not triaged in 24h
//
// AUTH
//   Accepts only service-role (x-cron-key) or Authorization: Bearer <service
//   role JWT>. No user sessions — this edge function is admin-only.
//
// SECRETS required
//   ANTHROPIC_API_KEY — Claude key (same key used by the admin CMS)
//   SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY — standard edge runtime
//
// Deploy: supabase functions deploy triage-bugs
// -----------------------------------------------------------------------------

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { buildCorsHeaders } from "../_shared/cors.ts";

// We call Anthropic directly via fetch() (same pattern as generate-ai-insights).
// Importing the SDK from esm.sh inside Deno has historically been flaky.
const ANTHROPIC_API_URL = "https://api.anthropic.com/v1/messages";
const ANTHROPIC_VERSION = "2023-06-01";

// -----------------------------------------------------------------------------
// Config
// -----------------------------------------------------------------------------

const MODEL = "claude-sonnet-4-20250514";
const MAX_FINGERPRINTS_PER_RUN = 12;      // hard cap — bounds Claude cost / run
const MAX_EXAMPLE_ENTRIES = 8;            // per fingerprint, for prompt budget
const RECENT_TREND_WINDOW_HOURS = 24;
const RE_TRIAGE_COOLDOWN_HOURS = 24;      // don't re-triage the same fp twice a day
const CLAUDE_MAX_TOKENS = 4096;

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

// -----------------------------------------------------------------------------
// Agent routing prompt (compressed summary of ENGINEERING_TEAM.md + *_AGENT.md)
// Keep this DRY with those docs — if the ownership matrix in
// ENGINEERING_TEAM.md changes, update this block.
// -----------------------------------------------------------------------------

const SYSTEM_PROMPT = `You are the Fit33 Bug Intelligence Triage Agent. You sit between raw error \
fingerprints and the Fit33 engineering team of specialized agents. Your job: \
for each bug fingerprint + evidence, pick the correct owning agent, the severity, \
a confidence score (0-1), a 1-2 sentence summary, and — when the fix is obvious \
from the evidence — a file_path and a unified-diff code_diff that the owning \
agent can ship.

# AGENT ROSTER (pick exactly one agent_owner per report)

- quality-performance: crashes, memory leaks, perf, accessibility, HealthKit observer
  ownership, video prefetch gating, AVAudioSession refcounting, reduce-motion
  enforcement, sync Core Data in init()/.task, DispatchQueue.main.asyncAfter
  instead of Task.sleep, missing accessibility, print() calls, force unwraps,
  notification type allowlist, stability + crash-rate regressions.
- product-engineer: navigation bugs, new UI screen issues, widget state, offline
  retry queue, StoreKit, blocking/reporting UI, component-reuse violations,
  cardio XP parity, admin CMS cookie UI wiring.
- data-backend: DTO / RPC issues, realtime subscription breakage, Core Data
  context misuse (bgContext/mergePolicy), API endpoint contract mismatches,
  sync issues between iOS and Supabase.
- infra-security: secrets leakage, auth flow bugs, edge function access control,
  CSP mismatches (next.config.ts vs middleware.ts), non-httpOnly cookies,
  content moderation pipeline breakage.
- supabase-expert: schema / migration issues, missing RLS, SECURITY DEFINER
  without auth.uid() guard, missing REPLICA IDENTITY FULL for realtime tables,
  view missing security_invoker=on, FK/constraint bugs, dead tables.
- design-system: hardcoded .system(size:), hardcoded padding/radius, missing
  ds_* tokens, haptics inconsistency.
- design: pure visual regressions where token value itself is wrong.
- fitness-expert: exercise pairing logic, program split, workout validation,
  auto-gen workout correctness, exercise DB data issues, Apple Watch planning.
- device-compatibility: iPad layout breakage, responsive spacing, cross-device
  layout regressions.
- support: FAQ content gaps, pain-point tracking, bug-to-feature mapping.
- unknown: only when the evidence genuinely doesn't map to any agent.

# INVARIANT HINTS (use to narrow the owner + invariant_violated field)

- "fatal error: unexpectedly found nil" / force-unwrap crash → quality-performance;
  invariant_violated = "no force unwraps (swiftui-rules #2)"
- print() usage → quality-performance; invariant_violated = "AppLogger only (swiftui-rules #1)"
- DispatchQueue.main.asyncAfter → quality-performance; invariant_violated = "structured concurrency (swiftui-rules #4)"
- Missing accessibility label → quality-performance; invariant_violated = "accessibility on every interactive element (swiftui-rules #5)"
- Main-thread AVFoundation work → quality-performance; invariant_violated = "AVFoundation off main thread (swiftui-rules #10)"
- PostgreSQL "row-level security" error → supabase-expert; invariant_violated = "RLS on every user-data table (supabase-rules #1)"
- Realtime subscription receives no updates → supabase-expert; invariant_violated = "REPLICA IDENTITY FULL + publication (supabase-rules)"
- 401/403 from admin CMS API → infra-security
- JSONSerialization crash → quality-performance; invariant_violated = "isValidJSONObject first (swiftui-rules #9)"
- Hardcoded .system(size: N) / .padding(N) → design-system
- Navigation stack divergence / NavigationLink destination mismatch → product-engineer

# SEVERITY

- critical: crash-level, affects >= 5 users or >= 50 occurrences in the last 24h,
  or blocks a core flow (workout / auth / payment).
- high: reliably reproducible error visible to users, single-user crashes.
- medium: intermittent errors with workarounds, non-crashing UX friction.
- low: warnings / log noise / cosmetic.

# CONFIDENCE

- 0.9–1.0: evidence is a known invariant violation with a clear file + diff.
- 0.7–0.9: strong signal on the owner + file, diff may be approximate.
- 0.4–0.7: plausible owner, more context needed.
- 0.0–0.4: genuinely ambiguous — prefer agent_owner = "unknown".

# PAIN_POINT_CANDIDATE

If the fingerprint represents a user-facing repeated pain (e.g. "timer keeps
resetting", "workout autosave failed"), propose a 1-line entry for
SUPPORT_AGENT pain registry. Otherwise null.

# SUGGESTED_TODO

One line suitable for MASTER_TODO.md (owner + action + why). Null if the
fingerprint isn't actionable (e.g. transient network errors).

# USING AUTHORITATIVE CALLSITE (Phase 12 Tier 0 #1 — 2026-04-25)

When the input includes \`authoritative_callsite: { file, line, function }\`,
that is the EXACT source location where the error logged — captured by the
iOS client's \`#file:#line:#function\` macros and threaded through
\`dev_session_logs.entries[].x_file/x_line/x_function\` (logs) or
\`crash_reports.additional_context.file/line/function\` (crashes). Rules:

  1. \`file_path\` MUST equal \`Fit33/<file>\` (or \`supabase/...\` /
     \`admin-cms/...\` if the captured file is in those subtrees) when
     \`authoritative_callsite\` is non-null. Do NOT guess a different file.
  2. Your \`code_diff\` should target a line within ±5 of \`authoritative_callsite.line\`.
     The exact line may shift between builds; ±5 keeps the diff applicable.
  3. Confidence ≥ 0.85 when authoritative_callsite is present + you propose a diff.
     The callsite eliminates the largest source of triage uncertainty.
  4. The \`function\` field tells you which function logged the error — use it
     to disambiguate when one file has multiple methods that could have raised.

When \`authoritative_callsite\` is null, fall back to stack-trace inference
(below). The callsite will always be present for fingerprints from iOS Phase 12+
client builds (1.39+); legacy fingerprints from older builds carry no callsite.

# USING SIMILAR_PAST_FIXES (Phase 12 Tier 5 #1 — 2026-04-25)

When the input includes \`similar_past_fixes: [...]\`, those are real past
resolutions that pattern-match this fingerprint by:

  - \`match_strength: 3\` → SAME structural_fingerprint (op + error_class +
    pg_code/http_status). This is the *same root cause* shipping again.
  - \`match_strength: 2\` → same (op, error_class) pair. Same kind of bug
    in the same operation — strong family resemblance.
  - \`match_strength: 1\` → same op alone, OR same error_class alone.
    Weaker but still informative.

Rules:

  1. If a match_strength=3 fix exists and the new fingerprint's evidence is
     consistent with it, REUSE its diagnosis: same \`agent_owner\`, same
     \`file_path\` (unless authoritative_callsite contradicts it), same
     \`invariant_violated\`, similar \`severity\`. Bump confidence to ≥ 0.9.
     This is a regression of a known issue — your job is to recognize it,
     not re-derive the fix from scratch.
  2. For match_strength=2 fixes, treat them as *strong priors*. Default to
     the same owner unless the new evidence clearly points elsewhere. The
     \`fix_file\` field hints at where the bug pattern lives — use it as a
     candidate when authoritative_callsite is null.
  3. For match_strength=1 fixes, treat them as *informative context* —
     don't blindly copy the owner, but they're useful for picking
     \`invariant_violated\` and \`pain_point_candidate\`.
  4. ALWAYS mention the similar past fix in your \`summary\` when match_strength
     ≥ 2 — e.g. "Same root cause as PR-1234 (resolved 2026-03-12)". This
     shows your reasoning to the human reviewer and tells Cursor "the
     fix recipe already exists, apply it again".
  5. NEVER copy the past fix's diff verbatim. Write a fresh \`code_diff\`
     against the current authoritative_callsite — past diffs are stale
     references; the file may have moved.

If no similar_past_fixes are returned, this is genuinely novel territory —
proceed with normal triage and don't pretend a precedent exists.

# USING SEVERITY_SCORE

\`severity_score\` is the empirical priority — occurrences × sqrt(users) ×
visibility × build_freshness × source_severity × regression_amplifier. It's
already computed; you don't need to recompute. Treat it as a tiebreaker when
choosing between competing diagnoses for the same evidence: a fingerprint with
severity_score = 250 deserves a more careful diff than one with score = 12.

# USING STACK TRACES

Each crash in \`example_crashes\` carries TWO stack-trace fields. Prefer
\`symbolicated_stack_trace\` when non-null — it's the ground truth from
Apple's \`atos\` against the real dSYM. Fall back to \`stack_trace\` only
when \`symbolication_status\` is \`legacy\` / \`no_dsym\` / \`failed\`
(i.e. symbolicated_stack_trace is null).

## SYMBOLICATED (symbolication_status = 'done') — AUTHORITATIVE

Each line is "<hex_addr> → <function_sig> (<File.swift>:<line>)", e.g.:
    0x104d3b0d8 → Fit33.WorkoutManager.startWorkout(_:) (WorkoutManager.swift:87)
    0x104d3799c → closure #1 in Fit33.DashboardView.body.getter (DashboardView.swift:142)
Only Fit33-owned frames are included (UIKit / Foundation / libswiftCore
are stripped by the symbolicator). Action:
  1. Pick the FIRST line — that's the failure site.
  2. Extract the file name from the trailing "(File.swift:NNN)".
  3. Normalize to "Fit33/<File>.swift" — we don't use subfolders in the
     Swift target, every file lives directly under Fit33/.
  4. Emit a real unified \`code_diff\` that changes the exact line.
  5. Confidence 0.85–0.95. This is the happy path post-Phase-5.

## UNSYMBOLICATED (symbolication_status ∈ 'legacy' / 'no_dsym' / 'failed' / 'pending')

\`symbolicated_stack_trace\` is null. \`stack_trace\` is raw hex:
    "0   Fit33   0x0000000104d3b0d8 Fit33 + 7418072"
    "1   Foundation   0x000000019bbbd804 F87E3667-... + 583684"
Do NOT hallucinate file names from hex offsets. Fall back to:

  (a) The \`error_message\` string itself. Many of our errors are tagged
      with the source component in brackets — \`[CrashReporter] Upload
      failed\` → \`Fit33/CrashReporter.swift\`, \`[WATCHDOG] Main thread
      frozen\` → \`Fit33/MainThreadWatchdog.swift\`, \`HealthKit Data RLS
      violation\` → \`Fit33/HealthDataService.swift\`. Map the bracket /
      keyword to the most likely file in the Fit33 codebase.

  (b) \`current_screen\` + \`session_log_snippet\`. If the last screen
      shown was "Dashboard" → \`Fit33/DashboardView.swift\`; "Workout" →
      \`Fit33/WorkoutActiveView.swift\`; "Onboarding" →
      \`Fit33/NewOnboardingView.swift\`. Only if confident.

  (c) If neither (a) nor (b) yields a plausible file, leave \`file_path\`
      and \`code_diff\` null — don't guess.

Cap confidence at 0.70 for unsymbolicated inferences, because the file
is a candidate, not a certainty. The admin CMS surfaces these as
"investigative leads" rather than 1-click merges.

Note on \`symbolication_status = 'pending'\`: the symbolicator runs every
15 min. If you see a pending crash and no other recent evidence, prefer
to return a low-confidence report — the next triage run will have the
real file.

# USING SESSION_LOG_SNIPPET

The snippet is a chronological list of the user's last ~100 events:
  [screen] DashboardView: entered
  [tap] WorkoutCard: Chest Day
  [api] GET /workouts/123: 200
  [error] -: Fatal error: Index out of range
  ...
Cite specific screens / taps in your summary to make it actionable.

# OUTPUT (JSON only — no markdown, no prose, no code fences)

{
  "reports": [
    {
      "fingerprint": "<md5>",
      "agent_owner": "quality-performance",
      "invariant_violated": "no force unwraps (swiftui-rules #2)",
      "severity": "high",
      "confidence": 0.85,
      "title": "...",
      "summary": "...",
      "file_path": "Fit33/Foo.swift",   // or null
      "code_diff": "--- a/...\\n+++ b/...\\n@@ ...",   // or null
      "pain_point_candidate": "...",   // or null
      "suggested_todo": "..."           // or null
    }
  ]
}

Only produce ONE report per input fingerprint. The \`fingerprint\` field must
match the fingerprint in the input exactly.`;

// -----------------------------------------------------------------------------
// Types
// -----------------------------------------------------------------------------

interface FingerprintRow {
    fingerprint: string;
    source: string;
    normalized_message: string;
    sample_message: string;
    error_domain: string | null;
    first_seen_app_version: string | null;
    last_seen_app_version: string | null;
    occurrence_count: number;
    unique_user_count: number;
    affected_screens: string[] | null;
    first_seen_at: string;
    last_seen_at: string;
    status: string;
    assigned_agent: string | null;
    // Phase 12 Tier 0 #1 (20260526_bug_intel_callsite_capture) — call-site
    // captured from `dev_session_logs.entries[].x_file/x_line/x_function` and
    // `crash_reports.additional_context->>file/line/function`. When present,
    // this is the AUTHORITATIVE file path for the report — not heuristic.
    last_seen_file: string | null;
    last_seen_function: string | null;
    last_seen_line: number | null;
    // Phase 12 Tier 2 #2 (20260528_bug_intel_severity_score) — empirical
    // priority score = occ × sqrt(users) × visibility × build_freshness × source × regression.
    severity_score: number | null;
    // Phase 9 / 20260516 — structural classification
    op: string | null;
    error_class: string | null;
    pg_code: string | null;
    http_status: number | null;
    endpoint: string | null;
    structural_fingerprint: string | null;
}

// Phase 12 Tier 2 #3 (2026-04-25) — previous unmerged Claude report for this
// fingerprint. We feed it back so Claude can SEE what it last said and either
// (a) iterate / refine when new evidence arrives, or (b) stop drifting on
// re-triage rounds where nothing materially changed.
interface PreviousReport {
    title: string;
    summary: string;
    agent_owner: string;
    severity: string;
    confidence: number;
    file_path: string | null;
    review_status: string;
    review_notes: string | null;
    created_at: string;
}

// Phase 12 Tier 5 #1 (2026-04-25) — past resolution that pattern-matches the
// current fingerprint. Surfaced via the bug_intel_find_similar_resolutions
// RPC (see 20260530_bug_intel_resolved_history.sql). Lets Claude reuse a
// known-good diagnosis instead of cold-starting on every similar bug.
interface SimilarPastFix {
    match_strength: number;          // 3 = exact structural · 2 = op+class · 1 = op or class
    fingerprint: string;
    structural_fingerprint: string | null;
    op: string | null;
    error_class: string | null;
    title: string | null;
    summary: string | null;
    agent_owner: string | null;
    last_seen_file: string | null;
    last_seen_line: number | null;
    resolution_pr_url: string | null;
    auto_resolved_reason: string | null;
    resolved_at: string;
}

interface ClaudeReport {
    fingerprint: string;
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

// Valid agent_owner values (matches CHECK constraint on bug_intelligence_reports)
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

        // ── Auth: service-role only (cron or admin CMS) ──────────────────
        const cronKey = req.headers.get("x-cron-key");
        const authHeader = req.headers.get("Authorization");

        let authorized = false;
        if (cronKey && isServiceRoleJWT(cronKey)) {
            authorized = true;
        } else if (authHeader) {
            const token = authHeader.replace("Bearer ", "");
            if (token === supabaseServiceKey || isServiceRoleJWT(token)) {
                authorized = true;
            }
        }
        if (!authorized) {
            return json({ error: "Unauthorized (service role required)" }, 401, corsHeaders);
        }

        let body: { source?: string; fingerprints?: string[] } = {};
        try {
            body = await req.json();
        } catch {
            // empty body ok
        }
        const source = body.source ?? "cron";
        const explicitFingerprints = Array.isArray(body.fingerprints)
            ? body.fingerprints.filter((f) => typeof f === "string")
            : null;

        // ── 1. Select fingerprints to triage ──────────────────────────────
        const {
            fingerprintsToTriage,
            triggerMap,
        } = await selectFingerprints(supabase, explicitFingerprints, source);

        if (fingerprintsToTriage.length === 0) {
            return json({
                message: "No fingerprints eligible for triage",
                source,
                triaged: 0,
            }, 200, corsHeaders);
        }

        // ── 2. Enrich each fingerprint with evidence ──────────────────────
        const enriched = await Promise.all(
            fingerprintsToTriage.map((fp) => enrichFingerprint(supabase, fp)),
        );

        // ── 3. Call Claude ────────────────────────────────────────────────
        const userPrompt = buildUserPrompt(enriched);

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
                messages: [{ role: "user", content: userPrompt }],
            }),
        });

        if (!response.ok) {
            const errBody = await response.text();
            console.error("triage-bugs: Anthropic API error", response.status, errBody);
            return json({
                error: `Anthropic API ${response.status}`,
                body: errBody.slice(0, 500),
            }, 502, corsHeaders);
        }

        const completion = await response.json() as {
            content?: Array<{ type: string; text?: string }>;
        };
        const block = completion.content?.find((b) => b.type === "text");
        const text = block?.text ?? "";
        const parsed = parseClaudeJson(text);

        if (!parsed) {
            console.error("triage-bugs: failed to parse Claude response");
            return json({
                error: "Could not parse Claude response",
                raw_sample: text.slice(0, 500),
            }, 500, corsHeaders);
        }

        // ── 4. Write reports + mark fingerprints/trends processed ────────
        const results = await writeReports(
            supabase,
            parsed.reports,
            enriched,
            triggerMap,
            source,
        );

        return json({
            message: "Triage complete",
            source,
            candidates: fingerprintsToTriage.length,
            reports_written: results.written,
            reports_skipped: results.skipped,
            fingerprints_updated: results.fingerprintsUpdated,
            trends_marked_reviewed: results.trendsMarked,
        }, 200, corsHeaders);

    } catch (error) {
        console.error("triage-bugs error:", error);
        return json(
            { error: error instanceof Error ? error.message : String(error) },
            500,
            buildCorsHeaders(req),
        );
    }
});

// -----------------------------------------------------------------------------
// Fingerprint selection
// -----------------------------------------------------------------------------

async function selectFingerprints(
    // deno-lint-ignore no-explicit-any
    supabase: any,
    explicit: string[] | null,
    source: string,
): Promise<{ fingerprintsToTriage: FingerprintRow[]; triggerMap: Map<string, { trendId: string | null; reason: string }> }> {
    const triggerMap = new Map<string, { trendId: string | null; reason: string }>();

    if (explicit && explicit.length > 0) {
        const { data } = await supabase
            .from("bug_intelligence_fingerprints")
            .select("*")
            .in("fingerprint", explicit.slice(0, MAX_FINGERPRINTS_PER_RUN));
        const rows = (data ?? []) as FingerprintRow[];
        for (const r of rows) {
            triggerMap.set(r.fingerprint, {
                trendId: null,
                reason: source === "manual" ? "manual" : "scheduled",
            });
        }
        return { fingerprintsToTriage: rows, triggerMap };
    }

    // 1. Unreviewed trend signals in last RECENT_TREND_WINDOW_HOURS
    const cutoff = new Date(Date.now() - RECENT_TREND_WINDOW_HOURS * 3600 * 1000).toISOString();
    const { data: trends } = await supabase
        .from("bug_intelligence_trends")
        .select("id, fingerprint, trend_type, detected_at")
        .is("reviewed_at", null)
        .gte("detected_at", cutoff)
        .order("detected_at", { ascending: false });

    const seen = new Set<string>();
    const prioritizedFingerprints: string[] = [];
    for (const t of (trends ?? []) as Array<{ id: string; fingerprint: string; trend_type: string }>) {
        if (seen.has(t.fingerprint)) continue;
        seen.add(t.fingerprint);
        triggerMap.set(t.fingerprint, { trendId: t.id, reason: t.trend_type });
        prioritizedFingerprints.push(t.fingerprint);
        if (prioritizedFingerprints.length >= MAX_FINGERPRINTS_PER_RUN) break;
    }

    // 2. Fill remaining budget with open fingerprints not triaged recently
    const remaining = MAX_FINGERPRINTS_PER_RUN - prioritizedFingerprints.length;
    if (remaining > 0) {
        const recentTriageCutoff = new Date(Date.now() - RE_TRIAGE_COOLDOWN_HOURS * 3600 * 1000).toISOString();

        const { data: recentReports } = await supabase
            .from("bug_intelligence_reports")
            .select("fingerprint")
            .gte("created_at", recentTriageCutoff);

        const recentlyTriaged = new Set(
            (recentReports ?? []).map((r: { fingerprint: string }) => r.fingerprint),
        );

        // Re-triage allowed on 'new' and 'triaged' (the report cooldown above
        // prevents re-asking Claude within 24h). 'in_progress' means a human
        // is already on it; 'resolved' / 'wont_fix' / 'duplicate' stay out.
        const { data: openFps } = await supabase
            .from("bug_intelligence_fingerprints")
            .select("fingerprint, last_seen_at, occurrence_count")
            .in("status", ["new", "triaged"])
            .gte("last_seen_at", new Date(Date.now() - 3 * 24 * 3600 * 1000).toISOString())
            .order("occurrence_count", { ascending: false })
            .limit(remaining * 5);

        for (const fp of ((openFps ?? []) as Array<{ fingerprint: string }>)) {
            if (seen.has(fp.fingerprint)) continue;
            if (recentlyTriaged.has(fp.fingerprint)) continue;
            seen.add(fp.fingerprint);
            triggerMap.set(fp.fingerprint, { trendId: null, reason: "scheduled" });
            prioritizedFingerprints.push(fp.fingerprint);
            if (prioritizedFingerprints.length >= MAX_FINGERPRINTS_PER_RUN) break;
        }
    }

    if (prioritizedFingerprints.length === 0) {
        return { fingerprintsToTriage: [], triggerMap };
    }

    const { data: rows } = await supabase
        .from("bug_intelligence_fingerprints")
        .select("*")
        .in("fingerprint", prioritizedFingerprints);

    return { fingerprintsToTriage: (rows ?? []) as FingerprintRow[], triggerMap };
}

// -----------------------------------------------------------------------------
// Per-fingerprint enrichment
// -----------------------------------------------------------------------------

interface EnrichedFingerprint {
    fp: FingerprintRow;
    example_errors: Array<Record<string, unknown>>;
    example_crashes: Array<Record<string, unknown>>;
    example_entry_ids: string[];
    // Phase 12 Tier 2 #3 — most recent unmerged Claude report (if any).
    // Lets Claude see what it previously concluded so it can refine vs reset.
    previous_report: PreviousReport | null;
    // Phase 12 Tier 5 #1 — top 3 past fixes that pattern-match this fingerprint.
    // Drives cross-fingerprint learning: similar bugs reuse known-good answers.
    similar_past_fixes: SimilarPastFix[];
}

async function enrichFingerprint(
    // deno-lint-ignore no-explicit-any
    supabase: any,
    fp: FingerprintRow,
): Promise<EnrichedFingerprint> {
    const example_errors: Array<Record<string, unknown>> = [];
    const example_crashes: Array<Record<string, unknown>> = [];
    const example_entry_ids: string[] = [];

    // Crash enrichment — uses Phase 3 generated column `bi_fingerprint`
    // (20260429_bug_intelligence_crash_enrichment.sql) for O(1) JOIN, and
    // pulls the fields Claude actually needs to propose a real diff:
    //   - stack_trace (top frame → file_path)
    //   - breadcrumbs (user actions leading up to the crash)
    //   - session_log_snippet (session timeline — auto-backfilled by trigger
    //     fn_backfill_crash_session_snippet when iOS client didn't include it)
    if (fp.source === "crash") {
        const { data: crashes } = await supabase
            .from("crash_reports")
            .select(
                "id, user_id, report_type, severity, error_message, error_domain, error_code, " +
                // Phase 5.6: symbolicated_stack_trace is the authoritative
                // source when present; stack_trace stays available as a
                // fallback for legacy / no_dsym / failed / pending rows.
                "stack_trace, symbolicated_stack_trace, symbolication_status, " +
                "breadcrumbs, session_log_snippet, session_id, " +
                "current_screen, os_version, device_model, app_version, build_number, " +
                "memory_usage_mb, free_memory_mb, network_type, " +
                "occurred_at, created_at",
            )
            .eq("bi_fingerprint", fp.fingerprint)
            .order("created_at", { ascending: false })
            .limit(MAX_EXAMPLE_ENTRIES);

        for (const c of ((crashes ?? []) as Array<Record<string, unknown>>)) {
            example_crashes.push(preferSymbolicated(c));
            example_entry_ids.push(`crash:${c.id}`);
        }
    }

    // Cross-source correlation: when the fingerprint is log-sourced, also
    // look for crashes whose *normalized message* matches — they carry
    // stack traces that massively improve Claude's diff accuracy. Uses the
    // same `bi_fingerprint` index, just with source='crash' applied to
    // this fingerprint's normalized_message.
    if (fp.source === "log") {
        const crashFpForThisMessage = await computeCrashFingerprint(
            supabase,
            fp.normalized_message,
            null,
        );
        if (crashFpForThisMessage) {
            const { data: crashes } = await supabase
                .from("crash_reports")
                .select(
                    "id, error_message, error_domain, stack_trace, " +
                    "symbolicated_stack_trace, symbolication_status, " +
                    "breadcrumbs, session_log_snippet, current_screen, " +
                    "app_version, build_number, occurred_at",
                )
                .eq("bi_fingerprint", crashFpForThisMessage)
                .order("created_at", { ascending: false })
                .limit(3);

            for (const c of ((crashes ?? []) as Array<Record<string, unknown>>)) {
                example_crashes.push(preferSymbolicated({ ...c, _cross_source: "log->crash" }));
                example_entry_ids.push(`crash:${c.id}`);
            }
        }
    }

    // Pull example error entries from dev_session_logs (last 3 days window)
    if (fp.source === "log") {
        const { data: batches } = await supabase
            .from("dev_session_logs")
            .select("id, user_id, session_id, entries, created_at, device_info")
            .gte("created_at", new Date(Date.now() - 3 * 24 * 3600 * 1000).toISOString())
            .order("created_at", { ascending: false })
            .limit(200);

        for (const b of (batches ?? []) as Array<Record<string, unknown>>) {
            const raw = b.entries;
            const entries = coerceArray(raw);
            if (!Array.isArray(entries)) continue;
            for (const e of entries) {
                if (!e || typeof e !== "object") continue;
                const ee = e as Record<string, unknown>;
                if (ee.type !== "error") continue;
                const detail = String(ee.detail ?? "");
                const normalized = normalizeMessage(detail);
                // Exact match — both use the same normalize() shape as the SQL
                // function bug_intelligence_normalize() so this is reliable.
                if (!normalized || normalized !== fp.normalized_message) continue;
                example_errors.push({
                    ...ee,
                    _session_id: b.session_id,
                    _batch_id: b.id,
                    _user_id: b.user_id,
                    _device: b.device_info,
                    _batch_created_at: b.created_at,
                });
                example_entry_ids.push(`log:${b.id}`);
                if (example_errors.length >= MAX_EXAMPLE_ENTRIES) break;
            }
            if (example_errors.length >= MAX_EXAMPLE_ENTRIES) break;
        }
    }

    // Phase 12 Tier 2 #3 — most recent NON-MERGED non-rejected report so
    // Claude has continuity with its previous diagnosis. Skip merged/rejected
    // (those are decisive prior outcomes — re-feeding them would override the
    // human's review). Skip stale (irrelevant context). Limit to 1 row.
    let previous_report: PreviousReport | null = null;
    try {
        const { data: prev } = await supabase
            .from("bug_intelligence_reports")
            .select(
                "title, summary, agent_owner, severity, confidence, file_path, " +
                "review_status, review_notes, created_at",
            )
            .eq("fingerprint", fp.fingerprint)
            .in("review_status", ["pending", "approved"])
            .order("created_at", { ascending: false })
            .limit(1)
            .maybeSingle();
        if (prev) previous_report = prev as PreviousReport;
    } catch {
        // best-effort — previous_report is optional context
    }

    // Phase 12 Tier 5 #1 — pattern-match against past resolutions. Top 3
    // most similar fixes by (structural_fingerprint, op, error_class).
    // Drives the SYSTEM_PROMPT "USING SIMILAR_PAST_FIXES" rules — when a
    // strong match exists, Claude reuses the known-good owner / file_path
    // instead of cold-starting.
    let similar_past_fixes: SimilarPastFix[] = [];
    try {
        const { data: similar } = await supabase.rpc(
            "bug_intel_find_similar_resolutions",
            {
                p_structural_fingerprint: fp.structural_fingerprint,
                p_op: fp.op,
                p_error_class: fp.error_class,
                p_exclude_fingerprint: fp.fingerprint,
                p_limit: 3,
            },
        );
        if (Array.isArray(similar)) {
            similar_past_fixes = similar as SimilarPastFix[];
        }
    } catch {
        // best-effort — RPC missing on older deploys is non-fatal
    }

    return {
        fp,
        example_errors,
        example_crashes,
        example_entry_ids,
        previous_report,
        similar_past_fixes,
    };
}

// Computes what the bug_intelligence fingerprint would be for the given
// (normalized_message, 'crash', domain) triple — delegates to the SQL
// helper so there's no drift between client + server hashing. Returns
// null if the RPC is unavailable.
async function computeCrashFingerprint(
    // deno-lint-ignore no-explicit-any
    supabase: any,
    normalizedMessage: string,
    domain: string | null,
): Promise<string | null> {
    try {
        const { data, error } = await supabase.rpc("bug_intelligence_fingerprint", {
            p_normalized: normalizedMessage,
            p_source: "crash",
            p_domain: domain,
        });
        if (error) return null;
        return typeof data === "string" ? data : null;
    } catch {
        return null;
    }
}

// Matches the SQL bug_intelligence_normalize() EXACTLY — keep in sync.
// SQL: regexp_replace(regexp_replace(msg, '\m[0-9a-fA-F]{8,}\M', '<id>', 'g'),
//                     '\d+(\.\d+)?', '<n>', 'g')
// PCRE \m = start-of-word, \M = end-of-word. JS has no direct analog; \b
// is equivalent for ASCII-only alphanumerics which is what these patterns
// use (hex chars + digits). Case preserved (SQL doesn't lowercase).
function normalizeMessage(msg: string): string {
    if (!msg) return "";
    return msg
        .replace(/\b[0-9a-fA-F]{8,}\b/g, "<id>")
        .replace(/\d+(\.\d+)?/g, "<n>");
}

// Phase 5.6: if a crash row has a non-empty symbolicated_stack_trace, we
// drop the raw hex `stack_trace` from the prompt payload — it's redundant
// noise and costs prompt budget. If the symbolicated trace is null (legacy
// / no_dsym / failed / pending), we keep the raw one so Claude can still
// do the Phase 3.1 tag-based inference. Keep `symbolication_status` in
// both branches so Claude can self-check which code path applies.
function preferSymbolicated(row: Record<string, unknown>): Record<string, unknown> {
    const symb = row.symbolicated_stack_trace;
    if (typeof symb === "string" && symb.trim().length > 0) {
        const clone = { ...row };
        delete clone.stack_trace;
        return clone;
    }
    return row;
}

function coerceArray(v: unknown): unknown[] {
    if (v == null) return [];
    if (Array.isArray(v)) return v;
    if (typeof v === "string") {
        try {
            const parsed = JSON.parse(v);
            return Array.isArray(parsed) ? parsed : [];
        } catch {
            return [];
        }
    }
    return [];
}

// -----------------------------------------------------------------------------
// Prompt assembly
// -----------------------------------------------------------------------------

function buildUserPrompt(items: EnrichedFingerprint[]): string {
    const inputs = items.map((x) => {
        // Phase 12 Tier 0 #1 — synthesize an `authoritative_callsite` field
        // when the iOS client captured #file:#line. Claude's SYSTEM_PROMPT
        // has a rule that this overrides every heuristic the prompt teaches
        // for guessing file_path from message text or stack traces.
        const callsite = (x.fp.last_seen_file && x.fp.last_seen_line)
            ? {
                file: x.fp.last_seen_file,
                line: x.fp.last_seen_line,
                function: x.fp.last_seen_function ?? null,
            }
            : null;

        return {
            fingerprint: x.fp.fingerprint,
            source: x.fp.source,
            error_domain: x.fp.error_domain,
            normalized_message: x.fp.normalized_message,
            sample_message: x.fp.sample_message,
            occurrence_count: x.fp.occurrence_count,
            unique_user_count: x.fp.unique_user_count,
            severity_score: x.fp.severity_score,           // Phase 12 Tier 2 #2
            first_seen_app_version: x.fp.first_seen_app_version,
            last_seen_app_version: x.fp.last_seen_app_version,
            affected_screens: x.fp.affected_screens,
            first_seen_at: x.fp.first_seen_at,
            last_seen_at: x.fp.last_seen_at,
            // Phase 9 / 20260516 — structural classification
            op: x.fp.op,
            error_class: x.fp.error_class,
            pg_code: x.fp.pg_code,
            http_status: x.fp.http_status,
            endpoint: x.fp.endpoint,
            structural_fingerprint: x.fp.structural_fingerprint,
            // Phase 12 Tier 0 #1 — authoritative call-site (if captured).
            // When non-null, file_path in your output MUST be this file.
            authoritative_callsite: callsite,
            // Phase 12 Tier 2 #3 — diff context: what you said last time.
            previous_triage: x.previous_report
                ? {
                    when: x.previous_report.created_at,
                    last_title: x.previous_report.title,
                    last_summary: x.previous_report.summary,
                    last_owner: x.previous_report.agent_owner,
                    last_severity: x.previous_report.severity,
                    last_confidence: x.previous_report.confidence,
                    last_file_path: x.previous_report.file_path,
                    review_status: x.previous_report.review_status,
                    reviewer_notes: x.previous_report.review_notes,
                    instruction:
                        "If the new evidence is consistent with this prior triage, " +
                        "REFINE it (raise confidence, tighten file_path with the new " +
                        "callsite, link the structural classification). If the evidence " +
                        "contradicts it, REPLACE the diagnosis and explain in summary " +
                        "why the prior was incomplete or wrong. Don't drift to a " +
                        "completely different owner without justification — review " +
                        "continuity matters.",
                }
                : null,
            // Phase 12 Tier 5 #1 — cross-fingerprint memory. Top 3 past fixes
            // that pattern-match this fingerprint, ranked by match_strength
            // (3 = exact structural · 2 = op+class · 1 = op or class).
            similar_past_fixes: x.similar_past_fixes.map((s) => ({
                match_strength: s.match_strength,
                fingerprint: s.fingerprint,
                op: s.op,
                error_class: s.error_class,
                title: s.title,
                summary: s.summary,
                agent_owner: s.agent_owner,
                fix_file: s.last_seen_file,
                fix_line: s.last_seen_line,
                resolution_pr_url: s.resolution_pr_url,
                resolved_at: s.resolved_at,
            })),
            example_errors: x.example_errors.slice(0, MAX_EXAMPLE_ENTRIES),
            example_crashes: x.example_crashes.slice(0, MAX_EXAMPLE_ENTRIES),
        };
    });

    return `Triage the following ${inputs.length} Fit33 bug fingerprint(s). ` +
        `Return a single JSON object { "reports": [...] } with exactly one report per input fingerprint. ` +
        `Fingerprints must be echoed back unchanged.\n\n` +
        `IMPORTANT: When \`authoritative_callsite\` is non-null, the \`file_path\` in your ` +
        `output MUST be \`Fit33/<file>\` (or \`supabase/...\` / \`admin-cms/...\` for non-iOS), ` +
        `and your code_diff (when proposed) should reference the line within ±5 of \`authoritative_callsite.line\`. ` +
        `Authoritative callsites are NOT heuristics — they're the exact #file:#line where the error logged. ` +
        `Confidence MUST be ≥ 0.85 when authoritative_callsite is present and you propose a diff.\n\n` +
        JSON.stringify(inputs, null, 2);
}

function parseClaudeJson(text: string): { reports: ClaudeReport[] } | null {
    // Strip possible code fences / prose
    const match = text.match(/\{[\s\S]*\}/);
    if (!match) return null;
    try {
        const obj = JSON.parse(match[0]);
        if (!obj || !Array.isArray(obj.reports)) return null;
        return obj as { reports: ClaudeReport[] };
    } catch {
        return null;
    }
}

// -----------------------------------------------------------------------------
// Write-back
// -----------------------------------------------------------------------------

interface WriteResult {
    written: number;
    skipped: number;
    fingerprintsUpdated: number;
    trendsMarked: number;
}

async function writeReports(
    // deno-lint-ignore no-explicit-any
    supabase: any,
    reports: ClaudeReport[],
    enriched: EnrichedFingerprint[],
    triggerMap: Map<string, { trendId: string | null; reason: string }>,
    source: string,
): Promise<WriteResult> {
    const enrichedByFp = new Map(enriched.map((e) => [e.fp.fingerprint, e]));
    let written = 0;
    let skipped = 0;

    const reportRows: Record<string, unknown>[] = [];
    const trendIdsToMark = new Set<string>();
    const fingerprintUpdates: Map<string, { agent_owner: string; severity: string }> = new Map();

    for (const r of reports) {
        const enrichedFp = enrichedByFp.get(r.fingerprint);
        if (!enrichedFp) { skipped++; continue; }

        const agent = VALID_AGENTS.has(r.agent_owner) ? r.agent_owner : "unknown";
        const severity = ["critical", "high", "medium", "low"].includes(r.severity)
            ? r.severity
            : "medium";
        const confidence = typeof r.confidence === "number"
            ? Math.max(0, Math.min(1, r.confidence))
            : 0.5;

        const trigger = triggerMap.get(r.fingerprint) ?? { trendId: null, reason: "scheduled" };
        const reason = source === "manual" ? "manual" : trigger.reason;
        const validReasons = ["new", "regression", "scheduled", "manual"];
        const triggerReason = validReasons.includes(reason) ? reason : "scheduled";

        reportRows.push({
            fingerprint: r.fingerprint,
            trigger_trend_id: trigger.trendId,
            trigger_reason: triggerReason,
            agent_owner: agent,
            invariant_violated: r.invariant_violated ?? null,
            severity,
            confidence,
            title: String(r.title ?? "Untitled").slice(0, 300),
            summary: String(r.summary ?? "").slice(0, 2000),
            file_path: r.file_path ?? null,
            code_diff: r.code_diff ?? null,
            pain_point_candidate: r.pain_point_candidate ?? null,
            suggested_todo: r.suggested_todo ?? null,
            analysis_model: MODEL,
            raw_response: r as unknown as Record<string, unknown>,
            example_entry_ids: enrichedFp.example_entry_ids,
        });

        fingerprintUpdates.set(r.fingerprint, { agent_owner: agent, severity });
        if (trigger.trendId) trendIdsToMark.add(trigger.trendId);
        written++;
    }

    if (reportRows.length > 0) {
        const { error } = await supabase.from("bug_intelligence_reports").insert(reportRows);
        if (error) {
            console.error("triage-bugs: insert reports error", error);
            return { written: 0, skipped: reports.length, fingerprintsUpdated: 0, trendsMarked: 0 };
        }
    }

    // Update fingerprints: set status=triaged + assigned_agent (preserve if human already assigned)
    let fingerprintsUpdated = 0;
    for (const [fingerprint, update] of fingerprintUpdates) {
        const { data: existing } = await supabase
            .from("bug_intelligence_fingerprints")
            .select("status, assigned_agent")
            .eq("fingerprint", fingerprint)
            .maybeSingle();

        const nextStatus = (existing?.status === "resolved" || existing?.status === "wont_fix")
            ? existing.status
            : "triaged";
        const nextAgent = existing?.assigned_agent ?? update.agent_owner;

        const { error } = await supabase
            .from("bug_intelligence_fingerprints")
            .update({
                status: nextStatus,
                assigned_agent: nextAgent,
                updated_at: new Date().toISOString(),
            })
            .eq("fingerprint", fingerprint);
        if (!error) fingerprintsUpdated++;
    }

    // Mark source trends reviewed
    let trendsMarked = 0;
    if (trendIdsToMark.size > 0) {
        const { error } = await supabase
            .from("bug_intelligence_trends")
            .update({ reviewed_at: new Date().toISOString(), reviewed_by: "triage-bugs-v1" })
            .in("id", Array.from(trendIdsToMark));
        if (!error) trendsMarked = trendIdsToMark.size;
    }

    return { written, skipped, fingerprintsUpdated, trendsMarked };
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
