// Supabase Edge Function: generate-new-user-report
// -----------------------------------------------------------------------------
// "Mark Zuckerberg-mode" per-user behavioral report generator.
//
// For every new-user enrollment whose checkpoint is due (D1, D2, D3, FINAL),
// pulls the full event ledger via `get_new_user_journey_report_data(user_id)`,
// builds a Claude-ready Markdown report (5 sections + verbatim event tail),
// optionally pipes the report to Claude for narrative analysis, and writes
// the result to `new_user_journey_reports`.
//
// INVOCATION
//   - source: "cron"   → service-role invocation from pg_cron
//                        (`5 * * * *` via `trigger_generate_new_user_reports()`)
//   - source: "manual" → admin CMS /api/admin action `generate_new_user_report`
//   - POST body { user_id: string, checkpoint?: 'D1'|'D2'|'D3'|'FINAL'|'MANUAL', dispatch_to_claude?: boolean }
//     → triages a specific user (manual override path)
//
// AUTH
//   Service role (Bearer service-role JWT) OR x-cron-key header validated
//   against `internal_config.cron_key`. No user JWT path — admin only.
//
// SECRETS
//   ANTHROPIC_API_KEY        — optional; when set, Claude analysis is run
//   SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY — standard
//
// PRIVACY
//   The Markdown report contains: user_id (UUID), event timestamps, event types,
//   product-search terms (food/exercise names, all non-PII domain data), screen
//   names, error messages. NO email, NO phone, NO full name, NO IP, NO payment
//   token, NO bug-report free-text body. Same posture as `triage-bugs`.
//
// Deploy: supabase functions deploy generate-new-user-report
// -----------------------------------------------------------------------------

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { buildCorsHeaders } from "../_shared/cors.ts";

const ANTHROPIC_API_URL = "https://api.anthropic.com/v1/messages";
const ANTHROPIC_VERSION = "2023-06-01";
const CLAUDE_MODEL = "claude-sonnet-4-20250514";
const CLAUDE_MAX_TOKENS = 8192;

// Hard caps to bound cost / per-run latency
const MAX_USERS_PER_CRON_RUN = 25;
const MAX_EVENTS_IN_REPORT_TAIL = 200;

const EXPECTED_PROJECT_REF = (() => {
    const raw = Deno.env.get("SUPABASE_URL") || "";
    const m = raw.match(/^https?:\/\/([a-z0-9]+)\.supabase\.co/i);
    return m?.[1] ?? "";
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
// Types
// -----------------------------------------------------------------------------

type Checkpoint = "D1" | "D2" | "D3" | "FINAL" | "MANUAL";

interface EnrollmentRow {
    user_id: string;
    enrolled_at: string;
    journey_started_at: string;
    journey_ends_at: string;
    auth_provider: string | null;
    install_app_version: string | null;
    install_build_number: string | null;
    install_device_model: string | null;
    install_ios_version: string | null;
    install_locale: string | null;
    install_timezone: string | null;
    referral_source: string | null;
    d1_report_due_at: string;
    d1_report_generated: boolean;
    d2_report_due_at: string;
    d2_report_generated: boolean;
    d3_report_due_at: string;
    d3_report_generated: boolean;
    final_report_due_at: string;
    final_report_generated: boolean;
    total_events: number;
    total_sessions: number;
    total_errors: number;
    total_crashes: number;
    last_event_at: string | null;
    last_screen: string | null;
    completed_onboarding: boolean;
    completed_first_workout: boolean;
    logged_first_meal: boolean;
    added_first_friend: boolean;
    connected_wearable: boolean;
    saw_paywall: boolean;
    converted_paywall: boolean;
}

interface SessionRow {
    id: string;
    session_id: string;
    started_at: string;
    ended_at: string | null;
    duration_seconds: number | null;
    app_version: string | null;
    build_number: string | null;
    device_model: string | null;
    ios_version: string | null;
    network_type: string | null;
    entry_screen: string | null;
    last_screen: string | null;
    error_count: number;
    crash_count: number;
    screen_view_count: number;
    tap_count: number;
}

interface EventRow {
    id: string;
    session_id: string | null;
    occurred_at: string;
    event_type: string;
    screen: string | null;
    detail: string | null;
    payload: Record<string, unknown>;
    is_error: boolean;
    severity: string | null;
}

interface FunnelRow {
    occurred_at: string;
    funnel: string;
    step: string;
    step_index: string | null;
    payload: Record<string, unknown>;
}

interface ErrorRow {
    detail: string;
    cnt: number;
    last_seen: string;
    first_seen: string;
    screens: string[] | null;
}

interface ReportData {
    success: boolean;
    enrollment: EnrollmentRow;
    window_start: string;
    window_end: string;
    events: EventRow[];
    sessions: SessionRow[];
    funnel: FunnelRow[];
    screens: Record<string, number>;
    errors: ErrorRow[];
    behavior: {
        workouts_logged: number;
        meals_logged: number;
        friends_added: number;
        paywall_views: number;
    };
}

// -----------------------------------------------------------------------------
// Markdown report builder — the Claude-ready surface
// -----------------------------------------------------------------------------

function buildMarkdownReport(data: ReportData, checkpoint: Checkpoint): string {
    const e = data.enrollment;
    const winStart = new Date(data.window_start);
    const winEnd = new Date(data.window_end);
    const journeyStart = new Date(e.journey_started_at);
    const minutesElapsed = Math.round((winEnd.getTime() - journeyStart.getTime()) / 60000);
    const hoursElapsed = (minutesElapsed / 60).toFixed(1);

    const lines: string[] = [];

    // ───── Header ─────
    lines.push(`# New User Journey Report — \`${e.user_id}\``);
    lines.push("");
    lines.push(`**Checkpoint:** ${checkpoint}`);
    lines.push(`**Window:** ${data.window_start} → ${data.window_end}  (≈${hoursElapsed}h since journey start)`);
    lines.push(`**Generated:** ${new Date().toISOString()}`);
    lines.push("");

    // ───── 1. User snapshot ─────
    lines.push("## 1. User snapshot");
    lines.push("");
    lines.push("| Field | Value |");
    lines.push("|---|---|");
    lines.push(`| Auth provider | ${e.auth_provider ?? "(unknown)"} |`);
    lines.push(`| Install version | ${e.install_app_version ?? "?"} (${e.install_build_number ?? "?"}) |`);
    lines.push(`| Device | ${e.install_device_model ?? "?"} · iOS ${e.install_ios_version ?? "?"} |`);
    lines.push(`| Locale / TZ | ${e.install_locale ?? "?"} / ${e.install_timezone ?? "?"} |`);
    lines.push(`| Referral | ${e.referral_source ?? "(none)"} |`);
    lines.push(`| Journey started | ${e.journey_started_at} |`);
    lines.push(`| Journey ends | ${e.journey_ends_at} |`);
    lines.push("");

    // ───── 2. Headline counters ─────
    lines.push("## 2. Headline counters");
    lines.push("");
    lines.push("| Metric | Value |");
    lines.push("|---|---|");
    lines.push(`| Total events | ${e.total_events} |`);
    lines.push(`| Total sessions | ${e.total_sessions} |`);
    lines.push(`| Total errors | ${e.total_errors} |`);
    lines.push(`| Total crashes | ${e.total_crashes} |`);
    lines.push(`| Workouts logged | ${data.behavior.workouts_logged} |`);
    lines.push(`| Meals logged | ${data.behavior.meals_logged} |`);
    lines.push(`| Friends added | ${data.behavior.friends_added} |`);
    lines.push(`| Paywall views | ${data.behavior.paywall_views} |`);
    lines.push("");

    // ───── 3. Activation funnel ─────
    lines.push("## 3. Activation funnel");
    lines.push("");
    const funnelChecks: Array<[string, boolean]> = [
        ["Completed onboarding",   e.completed_onboarding],
        ["First workout completed", e.completed_first_workout],
        ["First meal logged",       e.logged_first_meal],
        ["First friend added",      e.added_first_friend],
        ["Wearable connected",      e.connected_wearable],
        ["Saw paywall",             e.saw_paywall],
        ["Converted on paywall",    e.converted_paywall],
    ];
    for (const [label, hit] of funnelChecks) {
        lines.push(`- [${hit ? "x" : " "}] ${label}`);
    }
    lines.push("");

    // ───── 4. Onboarding step timeline ─────
    lines.push("## 4. Onboarding step timeline");
    lines.push("");
    const onboardingSteps = data.funnel.filter(f => f.funnel === "onboarding");
    if (onboardingSteps.length === 0) {
        lines.push("_No onboarding funnel events captured._");
    } else {
        lines.push("| Δ from start | Step | Index | Editing? |");
        lines.push("|---|---|---|---|");
        const ftStart = new Date(onboardingSteps[0].occurred_at).getTime();
        for (const f of onboardingSteps) {
            const dt = Math.round((new Date(f.occurred_at).getTime() - ftStart) / 1000);
            const editing = (f.payload?.is_editing as boolean) ? "✓" : "";
            lines.push(`| +${dt}s | ${f.step} | ${f.step_index ?? "?"} | ${editing} |`);
        }
    }
    lines.push("");

    // ───── 5. Sessions ─────
    lines.push("## 5. Sessions");
    lines.push("");
    if (data.sessions.length === 0) {
        lines.push("_No sessions captured in window._");
    } else {
        lines.push("| Started | Duration | Network | Entry → Exit | Screens | Taps | Errors | Crashes |");
        lines.push("|---|---|---|---|---|---|---|---|");
        for (const s of data.sessions) {
            const dur = s.duration_seconds != null ? `${s.duration_seconds}s` : "(open)";
            const flow = `${s.entry_screen ?? "?"} → ${s.last_screen ?? "?"}`;
            lines.push(`| ${s.started_at} | ${dur} | ${s.network_type ?? "?"} | ${flow} | ${s.screen_view_count} | ${s.tap_count} | ${s.error_count} | ${s.crash_count} |`);
        }
    }
    lines.push("");

    // ───── 6. Top screens visited ─────
    lines.push("## 6. Top screens (visit count)");
    lines.push("");
    const screenEntries = Object.entries(data.screens).sort((a, b) => b[1] - a[1]).slice(0, 25);
    if (screenEntries.length === 0) {
        lines.push("_No screen views captured._");
    } else {
        lines.push("| Screen | Visits |");
        lines.push("|---|---|");
        for (const [name, count] of screenEntries) {
            lines.push(`| ${name} | ${count} |`);
        }
    }
    lines.push("");

    // ───── 7. Friction signals (errors) ─────
    lines.push("## 7. Friction signals (errors)");
    lines.push("");
    if (data.errors.length === 0) {
        lines.push("_No errors captured. Smooth session._");
    } else {
        lines.push("| Count | First → Last | Detail | Screens |");
        lines.push("|---|---|---|---|");
        for (const er of data.errors.slice(0, 15)) {
            const screens = (er.screens ?? []).slice(0, 4).join(", ") || "—";
            const detail = (er.detail ?? "").replace(/\|/g, "\\|").slice(0, 140);
            lines.push(`| ${er.cnt} | ${er.first_seen} → ${er.last_seen} | ${detail} | ${screens} |`);
        }
    }
    lines.push("");

    // ───── 8. Verbatim event tail (last N) ─────
    lines.push(`## 8. Verbatim event tail (last ${Math.min(MAX_EVENTS_IN_REPORT_TAIL, data.events.length)})`);
    lines.push("");
    lines.push("```jsonl");
    const tail = data.events.slice(0, MAX_EVENTS_IN_REPORT_TAIL);
    for (const ev of tail) {
        const trimmed = {
            ts: ev.occurred_at,
            type: ev.event_type,
            screen: ev.screen,
            detail: ev.detail,
            payload: ev.payload,
            severity: ev.severity,
        };
        lines.push(JSON.stringify(trimmed));
    }
    lines.push("```");
    lines.push("");

    // ───── 9. Analysis prompt for Claude ─────
    lines.push("## 9. Analysis brief (for Claude)");
    lines.push("");
    lines.push(
        "You are reviewing the **first 72 hours** of a new Fit33 user. " +
        "Identify: (a) where the user got stuck (drop-off points in the funnel), " +
        "(b) which errors are likely user-blocking vs noise, " +
        "(c) which features the user discovered vs missed (workout / meal / friends / wearable / paywall), " +
        "(d) cohort comparison signals — does this user look like a power user, a casual, or an at-risk churner? " +
        "(e) one specific product change that would have made this user's first 3 days smoother. " +
        "Cite event timestamps as evidence. Be concise — 6-10 bullet points max."
    );
    lines.push("");

    return lines.join("\n");
}

// -----------------------------------------------------------------------------
// Optional Claude pass — narrative analysis layered on top of the structured
// report. Mirrors the `triage-bugs` integration shape for consistency.
// -----------------------------------------------------------------------------

async function callClaudeForAnalysis(reportMd: string): Promise<{ analysis: string; tokensIn: number; tokensOut: number; model: string } | null> {
    const apiKey = Deno.env.get("ANTHROPIC_API_KEY");
    if (!apiKey) return null;

    const systemPrompt = "You are the Fit33 New-User Journey Analyst. You review a structured " +
        "Markdown report describing a single new user's first 72 hours in the app. " +
        "Output ONLY the analysis described in §9 of the report — no preamble, no " +
        "restating of the data. Use Markdown bullets. 6-10 bullets max. Cite event " +
        "timestamps from §8 as your evidence trail.";

    const body = {
        model: CLAUDE_MODEL,
        max_tokens: CLAUDE_MAX_TOKENS,
        system: systemPrompt,
        messages: [{ role: "user", content: reportMd }],
    };

    try {
        const res = await fetch(ANTHROPIC_API_URL, {
            method: "POST",
            headers: {
                "Content-Type": "application/json",
                "x-api-key": apiKey,
                "anthropic-version": ANTHROPIC_VERSION,
            },
            body: JSON.stringify(body),
        });
        if (!res.ok) {
            const errBody = await res.text();
            console.warn(`[generate-new-user-report] Claude HTTP ${res.status}: ${errBody.slice(0, 400)}`);
            return null;
        }
        const data = await res.json();
        const text = (data?.content?.[0]?.text ?? "").trim();
        return {
            analysis: text,
            tokensIn: data?.usage?.input_tokens ?? 0,
            tokensOut: data?.usage?.output_tokens ?? 0,
            model: CLAUDE_MODEL,
        };
    } catch (err) {
        console.warn(`[generate-new-user-report] Claude call failed: ${(err as Error).message}`);
        return null;
    }
}

// -----------------------------------------------------------------------------
// Pick which checkpoint a user is due for
// -----------------------------------------------------------------------------

function pickDueCheckpoint(e: EnrollmentRow): Checkpoint | null {
    const now = Date.now();
    if (!e.final_report_generated && new Date(e.final_report_due_at).getTime() <= now) return "FINAL";
    if (!e.d3_report_generated    && new Date(e.d3_report_due_at).getTime() <= now)    return "D3";
    if (!e.d2_report_generated    && new Date(e.d2_report_due_at).getTime() <= now)    return "D2";
    if (!e.d1_report_generated    && new Date(e.d1_report_due_at).getTime() <= now)    return "D1";
    return null;
}

function checkpointWindow(e: EnrollmentRow, checkpoint: Checkpoint): { start: string; end: string } {
    const start = e.journey_started_at;
    const journeyStart = new Date(e.journey_started_at).getTime();
    const offsetHours = checkpoint === "D1" ? 24 : checkpoint === "D2" ? 48 : checkpoint === "D3" ? 72 : 78;
    const end = new Date(journeyStart + offsetHours * 3600_000).toISOString();
    return { start, end };
}

// -----------------------------------------------------------------------------
// Main handler
// -----------------------------------------------------------------------------

serve(async (req) => {
    const corsHeaders = buildCorsHeaders(req);
    if (req.method === "OPTIONS") {
        return new Response("ok", { headers: corsHeaders });
    }

    // ───── Auth ─────
    const authHeader = req.headers.get("Authorization") ?? "";
    const cronKey = req.headers.get("x-cron-key") ?? "";
    const expectedCronKey = Deno.env.get("CRON_KEY") ?? "";
    let isAuthorized = false;

    if (authHeader.startsWith("Bearer ")) {
        const token = authHeader.slice(7);
        if (token === Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")) isAuthorized = true;
        else if (isServiceRoleJWT(token)) isAuthorized = true;
    }
    if (!isAuthorized && expectedCronKey && cronKey === expectedCronKey) {
        isAuthorized = true;
    }

    if (!isAuthorized) {
        return new Response(JSON.stringify({ error: "Unauthorized" }), {
            status: 401,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
    }

    const supabase = createClient(
        Deno.env.get("SUPABASE_URL") ?? "",
        Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    );

    // ───── Parse request body ─────
    let body: { source?: string; user_id?: string; checkpoint?: Checkpoint; dispatch_to_claude?: boolean } = {};
    try {
        if (req.body) body = await req.json();
    } catch {
        // No body / invalid JSON — treat as cron-style empty invocation.
    }

    const dispatchToClaude = body.dispatch_to_claude !== false; // default ON

    // ───── Resolve user list ─────
    let userIds: string[] = [];
    let perUserCheckpoint: Checkpoint | null = null;

    if (body.user_id) {
        userIds = [body.user_id];
        perUserCheckpoint = body.checkpoint ?? "MANUAL";
    } else {
        const { data: dueRows, error } = await supabase
            .from("new_user_journey_enrollment")
            .select("*")
            .or([
                "and(d1_report_generated.eq.false,d1_report_due_at.lte.now())",
                "and(d2_report_generated.eq.false,d2_report_due_at.lte.now())",
                "and(d3_report_generated.eq.false,d3_report_due_at.lte.now())",
                "and(final_report_generated.eq.false,final_report_due_at.lte.now())",
            ].join(","))
            .limit(MAX_USERS_PER_CRON_RUN);

        if (error) {
            return new Response(JSON.stringify({ error: error.message }), {
                status: 500,
                headers: { ...corsHeaders, "Content-Type": "application/json" },
            });
        }
        userIds = (dueRows ?? []).map((r: { user_id: string }) => r.user_id);
    }

    if (userIds.length === 0) {
        return new Response(JSON.stringify({ ok: true, processed: 0, reason: "no_due_enrollments" }), {
            headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
    }

    // ───── Process each user ─────
    const results: Array<{ user_id: string; checkpoint: Checkpoint | "skipped"; ok: boolean; reason?: string }> = [];

    for (const userId of userIds) {
        // Re-fetch enrollment per user for freshness
        const { data: enrollmentRow } = await supabase
            .from("new_user_journey_enrollment")
            .select("*")
            .eq("user_id", userId)
            .maybeSingle();

        if (!enrollmentRow) {
            results.push({ user_id: userId, checkpoint: "skipped", ok: false, reason: "not_enrolled" });
            continue;
        }
        const enrollment = enrollmentRow as EnrollmentRow;

        // Decide checkpoint
        const checkpoint: Checkpoint = perUserCheckpoint ?? pickDueCheckpoint(enrollment) ?? "MANUAL";
        const window = checkpointWindow(enrollment, checkpoint);

        // Pull report data
        const { data: rpcData, error: rpcErr } = await supabase
            .rpc("get_new_user_journey_report_data", {
                p_user_id: userId,
                p_window_start: window.start,
                p_window_end: window.end,
            });

        if (rpcErr || !rpcData?.success) {
            results.push({ user_id: userId, checkpoint, ok: false, reason: rpcErr?.message ?? rpcData?.reason ?? "rpc_failed" });
            continue;
        }

        const reportData = rpcData as ReportData;
        const reportMd = buildMarkdownReport(reportData, checkpoint);

        // Optional Claude pass
        let claudeAnalysis: string | null = null;
        let claudeMeta: { model: string; tokensIn: number; tokensOut: number } | null = null;
        if (dispatchToClaude) {
            const claudeRes = await callClaudeForAnalysis(reportMd);
            if (claudeRes) {
                claudeAnalysis = claudeRes.analysis;
                claudeMeta = { model: claudeRes.model, tokensIn: claudeRes.tokensIn, tokensOut: claudeRes.tokensOut };
            }
        }

        // Persist report
        const { error: insertErr } = await supabase
            .from("new_user_journey_reports")
            .insert({
                user_id: userId,
                checkpoint,
                window_started_at: window.start,
                window_ended_at: window.end,
                structured_data: {
                    enrollment: reportData.enrollment,
                    behavior: reportData.behavior,
                    funnel_count: reportData.funnel.length,
                    sessions_count: reportData.sessions.length,
                    events_count: reportData.events.length,
                    errors_count: reportData.errors.length,
                    screens: reportData.screens,
                },
                report_md: reportMd,
                claude_analysis_md: claudeAnalysis,
                claude_model: claudeMeta?.model ?? null,
                claude_tokens_in: claudeMeta?.tokensIn ?? null,
                claude_tokens_out: claudeMeta?.tokensOut ?? null,
            });

        if (insertErr) {
            results.push({ user_id: userId, checkpoint, ok: false, reason: insertErr.message });
            continue;
        }

        // Mark the checkpoint as generated on the enrollment row
        const updateField =
            checkpoint === "D1" ? "d1_report_generated"
            : checkpoint === "D2" ? "d2_report_generated"
            : checkpoint === "D3" ? "d3_report_generated"
            : checkpoint === "FINAL" ? "final_report_generated"
            : null;

        if (updateField) {
            await supabase
                .from("new_user_journey_enrollment")
                .update({ [updateField]: true })
                .eq("user_id", userId);
        }

        results.push({ user_id: userId, checkpoint, ok: true });
    }

    return new Response(
        JSON.stringify({ ok: true, processed: results.length, results }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
});
