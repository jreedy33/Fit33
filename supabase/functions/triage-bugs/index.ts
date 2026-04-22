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
}

async function enrichFingerprint(
    // deno-lint-ignore no-explicit-any
    supabase: any,
    fp: FingerprintRow,
): Promise<EnrichedFingerprint> {
    const example_errors: Array<Record<string, unknown>> = [];
    const example_crashes: Array<Record<string, unknown>> = [];
    const example_entry_ids: string[] = [];

    // Pull matching crashes. crash_reports.fingerprint is a DIFFERENT hash
    // (computed client-side over stack frames) than the bug_intelligence
    // fingerprint (md5 of normalized_message+source+domain). So we re-derive
    // by filtering recent crashes whose normalized error_message matches.
    if (fp.source === "crash") {
        const { data: crashes } = await supabase
            .from("crash_reports")
            .select("id, user_id, report_type, error_message, error_domain, file, line_number, os_version, device_model, app_version, current_screen, created_at, occurred_at")
            .gte("created_at", new Date(Date.now() - 5 * 24 * 3600 * 1000).toISOString())
            .order("created_at", { ascending: false })
            .limit(200);

        const targetMsg = fp.normalized_message;
        const targetDomain = fp.error_domain ?? null;
        for (const c of ((crashes ?? []) as Array<Record<string, unknown>>)) {
            const norm = normalizeMessage(String(c.error_message ?? ""));
            const domainMatch = targetDomain
                ? (String(c.error_domain ?? "") === targetDomain)
                : true;
            if (norm === targetMsg && domainMatch) {
                example_crashes.push(c);
                example_entry_ids.push(`crash:${c.id}`);
                if (example_crashes.length >= MAX_EXAMPLE_ENTRIES) break;
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

    return { fp, example_errors, example_crashes, example_entry_ids };
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
    const inputs = items.map((x) => ({
        fingerprint: x.fp.fingerprint,
        source: x.fp.source,
        error_domain: x.fp.error_domain,
        normalized_message: x.fp.normalized_message,
        sample_message: x.fp.sample_message,
        occurrence_count: x.fp.occurrence_count,
        unique_user_count: x.fp.unique_user_count,
        first_seen_app_version: x.fp.first_seen_app_version,
        last_seen_app_version: x.fp.last_seen_app_version,
        affected_screens: x.fp.affected_screens,
        first_seen_at: x.fp.first_seen_at,
        last_seen_at: x.fp.last_seen_at,
        example_errors: x.example_errors.slice(0, MAX_EXAMPLE_ENTRIES),
        example_crashes: x.example_crashes.slice(0, MAX_EXAMPLE_ENTRIES),
    }));

    return `Triage the following ${inputs.length} Fit33 bug fingerprint(s). ` +
        `Return a single JSON object { "reports": [...] } with exactly one report per input fingerprint. ` +
        `Fingerprints must be echoed back unchanged.\n\n` +
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
