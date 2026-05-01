// Supabase Edge Function: wake-challenge-opponents
// -----------------------------------------------------------------------------
// Sends silent APNs pushes (content-available: 1) to wake opponent devices so
// their HealthKit / meal / hydration data gets pushed to Supabase as close to
// realtime as iOS allows — even when the opponent hasn't opened the app.
//
// Two invocation modes:
//   1. `source: "foreground"` — called by the iOS client when a user opens
//      the app or completes a background sync. Wakes each opponent found
//      across the caller's active 1v1, group, and private challenges.
//   2. `source: "cron"` — invoked by pg_cron every 30 min via
//      `trigger_challenge_opponent_wake()`. Wakes every participant in
//      any active challenge.
//
// Rate-limiting: per-source throttle via `silent_push_wake_log`. Apple's
// silent-push budget is ~2-3/hr per device.
//
// 2026-08-01: APNs JWT + send moved to _shared/apns.ts. Silent send results
// are now written to push_notification_delivery_log so the CMS Failed
// Deliveries tab surfaces background-push failures alongside visible ones.
//
// Deploy: supabase functions deploy wake-challenge-opponents
// Secrets required: APNS_KEY_ID, APNS_TEAM_ID, APNS_BUNDLE_ID, APNS_PRIVATE_KEY
// -----------------------------------------------------------------------------

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { buildCorsHeaders } from "../_shared/cors.ts";
import {
  sendApnsSilent,
  pushDeliveryLog,
  eventNameFor,
} from "../_shared/apns.ts";

// Per-source throttle windows (see INFRA_SECURITY invariant 17b).
const THROTTLE_WINDOWS_MS_BY_SOURCE: Record<string, number> = {
    foreground: 15 * 60 * 1000,
    background_sync: 15 * 60 * 1000,
    cron: 15 * 60 * 1000,
    progress_update: 20 * 1000,
};
const DEFAULT_THROTTLE_WINDOW_MS = 15 * 60 * 1000;

const MAX_RECIPIENTS_PER_RUN = 500;

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

interface RequestBody {
    source?: "foreground" | "cron" | "background_sync" | "progress_update";
    recipient_ids?: string[];
    writer_id?: string;
    challenge_id?: string;
    source_table?: string;
}

serve(async (req) => {
    const corsHeaders = buildCorsHeaders(req);
    if (req.method === "OPTIONS") {
        return new Response("ok", { headers: corsHeaders });
    }

    try {
        const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
        const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
        const supabase = createClient(supabaseUrl, supabaseServiceKey);

        // ── Auth: accept user JWT OR service role OR x-cron-key ────────────
        const cronKey = req.headers.get("x-cron-key");
        const authHeader = req.headers.get("Authorization");

        let callerUserId: string | null = null;
        let isServiceRole = false;

        if (cronKey && isServiceRoleJWT(cronKey)) {
            isServiceRole = true;
        } else if (!authHeader) {
            return json({ error: "Missing authorization" }, 401, corsHeaders);
        } else {
            const token = authHeader.replace("Bearer ", "");
            if (token === supabaseServiceKey || isServiceRoleJWT(token)) {
                isServiceRole = true;
            } else {
                const { data: { user }, error: authError } = await supabase.auth.getUser(token);
                if (authError || !user) {
                    return json({ error: "Unauthorized" }, 401, corsHeaders);
                }
                callerUserId = user.id;
            }
        }

        let body: RequestBody = {};
        try {
            body = await req.json();
        } catch {
            // empty body = defaults
        }

        const source = body.source ?? (isServiceRole ? "cron" : "foreground");

        // ── Resolve candidate recipient user IDs ──────────────────────────
        let candidateIds: string[] = [];

        if (source === "progress_update") {
            if (!isServiceRole) {
                return json({ error: "progress_update requires service role" }, 403, corsHeaders);
            }
            const provided = Array.isArray(body.recipient_ids) ? body.recipient_ids : [];
            candidateIds = provided
                .filter((s): s is string => typeof s === "string" && s.length === 36);
            if (candidateIds.length === 0) {
                return json({ message: "No recipient_ids", sent: 0, throttled: 0 }, 200, corsHeaders);
            }
        } else if (source === "cron") {
            candidateIds = await resolveAllActiveChallengeParticipants(supabase);
        } else {
            if (!callerUserId) {
                return json({ error: "Foreground wake requires a user session" }, 401, corsHeaders);
            }
            candidateIds = await resolveOpponentsFor(supabase, callerUserId);
        }

        if (candidateIds.length === 0) {
            return json({ message: "No candidates", sent: 0, throttled: 0 }, 200, corsHeaders);
        }

        const uniqueIds = Array.from(new Set(candidateIds)).slice(0, MAX_RECIPIENTS_PER_RUN);

        // ── Per-source throttle via silent_push_wake_log ──────────────────
        const throttleWindowMs = THROTTLE_WINDOWS_MS_BY_SOURCE[source] ?? DEFAULT_THROTTLE_WINDOW_MS;
        const cutoff = new Date(Date.now() - throttleWindowMs).toISOString();
        const { data: recentRows, error: logErr } = await supabase
            .from("silent_push_wake_log")
            .select("user_id")
            .in("user_id", uniqueIds)
            .eq("triggered_by", source)
            .gte("sent_at", cutoff);

        if (logErr) {
            console.log(JSON.stringify({ event: "throttle_lookup_failed", error: logErr.message }));
        }

        const throttled = new Set<string>((recentRows ?? []).map((r: { user_id: string }) => r.user_id));
        const eligible = uniqueIds.filter((id) => !throttled.has(id));

        if (eligible.length === 0) {
            return json({
                message: "All candidates throttled",
                sent: 0,
                throttled: throttled.size,
                candidates: uniqueIds.length,
            }, 200, corsHeaders);
        }

        // ── Fetch device tokens + send silent pushes ──────────────────────

        const { data: tokenRows, error: tokErr } = await supabase
            .from("user_push_tokens")
            .select("user_id, device_token, apns_environment, is_valid")
            .in("user_id", eligible)
            .eq("is_valid", true);

        if (tokErr) {
            console.log(JSON.stringify({ event: "token_fetch_failed", error: tokErr.message }));
            return json({ error: "Token fetch failed" }, 500, corsHeaders);
        }

        const rows = tokenRows ?? [];
        let sent = 0;
        let apnsFailed = 0;

        for (const row of rows) {
            const result = await sendApnsSilent(
                row.device_token,
                {
                    type: "challenge_wake",
                    data: { source, ...(body.writer_id ? { writer_id: body.writer_id } : {}), ...(body.challenge_id ? { challenge_id: body.challenge_id } : {}) },
                    expirationSeconds: 3600,
                },
                row.apns_environment,
            );

            // Silent pushes still write to delivery log (notificationId=null
            // because they don't go through push_notification_queue). The
            // CMS Failed Deliveries tab includes notification_id IS NULL
            // rows scoped to event = silent_apns_*.
            await pushDeliveryLog(supabase, {
                notificationId: null,
                userId: row.user_id,
                event: result.success ? "silent_apns_success" : `silent_${eventNameFor(result)}`,
                detail: {
                    source,
                    type: "challenge_wake",
                    token_prefix: row.device_token.substring(0, 12),
                    apns_env: row.apns_environment,
                    status: result.status ?? null,
                    reason: result.reason ?? null,
                    duration_ms: result.durationMs ?? null,
                    error: result.error ?? null,
                    writer_id: body.writer_id ?? null,
                    challenge_id: body.challenge_id ?? null,
                },
            });

            if (result.success) {
                sent++;
            } else {
                apnsFailed++;
                if (result.invalidateToken) {
                    await supabase
                        .from("user_push_tokens")
                        .update({ is_valid: false })
                        .eq("user_id", row.user_id)
                        .eq("device_token", row.device_token);
                    await pushDeliveryLog(supabase, {
                        notificationId: null,
                        userId: row.user_id,
                        event: "token_invalid",
                        detail: { token_prefix: row.device_token.substring(0, 12), reason: result.reason ?? "apple_410ish", source },
                    });
                    console.log(JSON.stringify({
                        event: "token_invalidated",
                        user_id: row.user_id,
                        token_prefix: row.device_token.substring(0, 12),
                    }));
                }
            }
        }

        // Log wake events (one row per eligible user, regardless of token success).
        const wakeLogRows = eligible.map((id) => ({
            user_id: id,
            triggered_by: source,
        }));
        if (wakeLogRows.length > 0) {
            await supabase.from("silent_push_wake_log").insert(wakeLogRows);
        }

        console.log(JSON.stringify({
            event: "wake_complete",
            source,
            candidates: uniqueIds.length,
            throttled: throttled.size,
            eligible: eligible.length,
            token_rows: rows.length,
            sent,
            apns_failed: apnsFailed,
        }));

        return json({
            message: "Wake dispatched",
            source,
            candidates: uniqueIds.length,
            throttled: throttled.size,
            eligible: eligible.length,
            sent,
            apns_failed: apnsFailed,
        }, 200, corsHeaders);

    } catch (error) {
        console.error("wake-challenge-opponents error:", error);
        return json({ error: String(error) }, 500, buildCorsHeaders(req));
    }
});

// =============================================================================
// Recipient resolution
// =============================================================================

async function resolveOpponentsFor(
    // deno-lint-ignore no-explicit-any
    supabase: any,
    userId: string,
): Promise<string[]> {
    const ids = new Set<string>();

    const { data: myChallenges } = await supabase
        .from("challenge_participants")
        .select("challenge_id, group_challenges!inner(status)")
        .eq("user_id", userId)
        .eq("status", "accepted");

    const activeChallengeIds = (myChallenges ?? [])
        // deno-lint-ignore no-explicit-any
        .filter((r: any) => r.group_challenges?.status === "active")
        // deno-lint-ignore no-explicit-any
        .map((r: any) => r.challenge_id);

    if (activeChallengeIds.length > 0) {
        const { data: opponents } = await supabase
            .from("challenge_participants")
            .select("user_id")
            .in("challenge_id", activeChallengeIds)
            .eq("status", "accepted")
            .neq("user_id", userId);
        // deno-lint-ignore no-explicit-any
        (opponents ?? []).forEach((r: any) => ids.add(r.user_id));
    }

    const { data: myPrivate } = await supabase
        .from("private_challenge_members")
        .select("challenge_id, private_challenges!inner(end_date)")
        .eq("user_id", userId);

    const today = new Date().toISOString().slice(0, 10);
    const activePrivateIds = (myPrivate ?? [])
        // deno-lint-ignore no-explicit-any
        .filter((r: any) => {
            const end = r.private_challenges?.end_date;
            return !end || end >= today;
        })
        // deno-lint-ignore no-explicit-any
        .map((r: any) => r.challenge_id);

    if (activePrivateIds.length > 0) {
        const { data: privOpp } = await supabase
            .from("private_challenge_members")
            .select("user_id")
            .in("challenge_id", activePrivateIds)
            .neq("user_id", userId);
        // deno-lint-ignore no-explicit-any
        (privOpp ?? []).forEach((r: any) => ids.add(r.user_id));
    }

    return Array.from(ids);
}

async function resolveAllActiveChallengeParticipants(
    // deno-lint-ignore no-explicit-any
    supabase: any,
): Promise<string[]> {
    const ids = new Set<string>();

    const { data: activeGroups } = await supabase
        .from("group_challenges")
        .select("id")
        .eq("status", "active");
    const activeIds = (activeGroups ?? []).map((r: { id: string }) => r.id);

    if (activeIds.length > 0) {
        const { data: participants } = await supabase
            .from("challenge_participants")
            .select("user_id")
            .in("challenge_id", activeIds)
            .eq("status", "accepted");
        (participants ?? []).forEach((r: { user_id: string }) => ids.add(r.user_id));
    }

    const today = new Date().toISOString().slice(0, 10);
    const { data: activePrivate } = await supabase
        .from("private_challenges")
        .select("id, end_date");
    const activePrivateIds = (activePrivate ?? [])
        .filter((r: { end_date: string | null }) => !r.end_date || r.end_date >= today)
        .map((r: { id: string }) => r.id);

    if (activePrivateIds.length > 0) {
        const { data: privMembers } = await supabase
            .from("private_challenge_members")
            .select("user_id")
            .in("challenge_id", activePrivateIds);
        (privMembers ?? []).forEach((r: { user_id: string }) => ids.add(r.user_id));
    }

    return Array.from(ids);
}

// =============================================================================
// JSON helper
// =============================================================================

function json(body: unknown, status: number, corsHeaders: Record<string, string>): Response {
    return new Response(JSON.stringify(body), {
        status,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
}
