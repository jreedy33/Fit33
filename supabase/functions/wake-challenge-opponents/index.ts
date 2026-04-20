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
//      any active challenge (so each device nudges its own HealthKit
//      data to the server; everyone else then sees fresh numbers via
//      the existing RealtimeService subscription).
//
// Rate-limiting: per-user 15-min throttle via `silent_push_wake_log`. Apple's
// silent-push budget is ~2-3/hr per device — 15 min keeps us safely under.
//
// Deploy: supabase functions deploy wake-challenge-opponents
// Secrets required: APNS_KEY_ID, APNS_TEAM_ID, APNS_BUNDLE_ID, APNS_PRIVATE_KEY
// -----------------------------------------------------------------------------

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { SignJWT, importPKCS8 } from "https://deno.land/x/jose@v4.14.4/index.ts";
import { buildCorsHeaders } from "../_shared/cors.ts";

// APNs config (same secret set as send-push-notification)
const APNS_KEY_ID = Deno.env.get("APNS_KEY_ID") || "";
const APNS_TEAM_ID = Deno.env.get("APNS_TEAM_ID") || "";
const APNS_BUNDLE_ID = Deno.env.get("APNS_BUNDLE_ID") || "";
const APNS_PRIVATE_KEY = (Deno.env.get("APNS_PRIVATE_KEY") || "").replace(/\\n/g, "\n");

const APNS_HOST_PRODUCTION = "api.push.apple.com";
const APNS_HOST_SANDBOX = "api.sandbox.push.apple.com";

// Per-user throttle window (must be >= send-push-notification's silent cap).
const THROTTLE_WINDOW_MS = 15 * 60 * 1000;

// Hard cap on recipients per invocation — defense-in-depth against a runaway
// query. 500 is more than enough for the entire active-challenge population.
const MAX_RECIPIENTS_PER_RUN = 500;

function getAPNsHost(apnsEnvironment: string | null): string {
    return apnsEnvironment === "development" ? APNS_HOST_SANDBOX : APNS_HOST_PRODUCTION;
}

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
    source?: "foreground" | "cron" | "background_sync";
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

        if (source === "cron") {
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

        // Cap + dedupe (dedupe already done by resolve*, but belt & braces)
        const uniqueIds = Array.from(new Set(candidateIds)).slice(0, MAX_RECIPIENTS_PER_RUN);

        // ── Apply 15-min throttle via silent_push_wake_log ────────────────
        const cutoff = new Date(Date.now() - THROTTLE_WINDOW_MS).toISOString();
        const { data: recentRows, error: logErr } = await supabase
            .from("silent_push_wake_log")
            .select("user_id")
            .in("user_id", uniqueIds)
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
        const apnsToken = await generateAPNsToken();

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
            const apnsHost = getAPNsHost(row.apns_environment);
            const result = await sendSilentPush(row.device_token, apnsToken, apnsHost);

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
                    console.log(JSON.stringify({
                        event: "token_invalidated",
                        user_id: row.user_id,
                        token_prefix: row.device_token.substring(0, 12),
                    }));
                }
            }
        }

        // Log wake events (one row per eligible user, regardless of token
        // success — this is the rate-limit record, not a delivery receipt).
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

/**
 * Foreground / background_sync mode: find the caller's opponents across
 * 1v1 + group challenges (via `challenge_participants`) and private
 * challenges (via `private_challenge_members`).
 */
async function resolveOpponentsFor(
    // deno-lint-ignore no-explicit-any
    supabase: any,
    userId: string,
): Promise<string[]> {
    const ids = new Set<string>();

    // 1v1 + group: caller's accepted participations → opponents in those
    // challenges where gc.status = 'active'.
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

    // Private challenges: caller's memberships → other members in the same
    // challenges (private_challenges.end_date is nullable; treat NULL or
    // future as active).
    const { data: myPrivate } = await supabase
        .from("private_challenge_members")
        .select("challenge_id, private_challenges!inner(end_date)")
        .eq("user_id", userId);

    const today = new Date().toISOString().slice(0, 10); // YYYY-MM-DD
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

/**
 * Cron mode: every distinct user who is currently in any active challenge.
 * We send the wake to the user themselves — their device will then sync
 * HealthKit and push `challenge_daily_progress`, which reaches every
 * opponent via the existing realtime subscription.
 */
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
// APNs helpers (silent push — no alert, no sound, no badge)
// =============================================================================

async function generateAPNsToken(): Promise<string> {
    const privateKey = await importPKCS8(APNS_PRIVATE_KEY, "ES256");
    return await new SignJWT({})
        .setProtectedHeader({ alg: "ES256", kid: APNS_KEY_ID })
        .setIssuer(APNS_TEAM_ID)
        .setIssuedAt()
        .sign(privateKey);
}

/**
 * Silent push: aps.content-available = 1 only. No alert / sound / badge.
 * Custom `type: "challenge_wake"` lets the iOS handler route correctly.
 * APNs requires:
 *   - apns-push-type: background
 *   - apns-priority: 5  (never 10 for silent pushes; Apple will drop them)
 *   - apns-topic: <bundle id>
 */
async function sendSilentPush(
    deviceToken: string,
    apnsToken: string,
    apnsHost: string,
): Promise<{ success: boolean; error?: string; invalidateToken?: boolean }> {
    const payload = {
        aps: {
            "content-available": 1,
        },
        type: "challenge_wake",
    };

    try {
        const controller = new AbortController();
        const timeoutId = setTimeout(() => controller.abort(), 10000);

        const response = await fetch(
            `https://${apnsHost}/3/device/${deviceToken}`,
            {
                method: "POST",
                headers: {
                    "authorization": `bearer ${apnsToken}`,
                    "apns-topic": APNS_BUNDLE_ID,
                    "apns-push-type": "background",
                    "apns-priority": "5",
                    "apns-expiration": String(Math.floor(Date.now() / 1000) + 3600),
                },
                body: JSON.stringify(payload),
                signal: controller.signal,
            },
        );
        clearTimeout(timeoutId);

        if (response.ok) return { success: true };

        const errorBody = await response.text();
        const invalidateToken =
            errorBody.includes("BadDeviceToken") ||
            errorBody.includes("Unregistered") ||
            errorBody.includes("DeviceTokenNotForTopic");

        return {
            success: false,
            error: `APNs ${response.status}: ${errorBody}`,
            invalidateToken,
        };
    } catch (error) {
        return { success: false, error: `Network error: ${String(error)}` };
    }
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
