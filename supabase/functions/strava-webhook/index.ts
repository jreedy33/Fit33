// Supabase Edge Function: strava-webhook
// -----------------------------------------------------------------------------
// Phase 5 of the Strava Integration Upgrade.
//
// Endpoint that Strava calls when a user creates / updates / deletes an
// activity. Strava's webhook spec:
//   GET  /strava-webhook  → subscription handshake; echo `hub.challenge`.
//   POST /strava-webhook  → JSON body { aspect_type, object_type, object_id,
//                                        owner_id, event_time, ... }
//
// On `object_type=activity` + `aspect_type=create|update`:
//   1. Resolve owner_id → app user_id via get_user_id_for_strava_athlete().
//   2. Read the user's stored access_token from user_strava_tokens
//      (refresh if expired using refresh_token).
//   3. Fetch /activities/{object_id} and upsert into cardio_workouts with
//      origin_app='strava'. Same shape the iOS client uses (Phase 2 cols).
//   4. Send a silent push (type='strava_activity_new') to the user's
//      device tokens so the dashboard recap card refreshes within seconds.
//
// On `aspect_type=delete`:
//   • Soft-delete the matching cardio_workouts row (or leave as-is — Strava
//     deletions are rare and we don't currently surface them).
//
// Auth: Strava itself signs nothing — the only "auth" is the
// STRAVA_VERIFY_TOKEN that we returned during the GET handshake. We
// re-verify by checking that the POST body's owner_id maps to a known user.
//
// Required env vars:
//   STRAVA_CLIENT_ID
//   STRAVA_CLIENT_SECRET
//   STRAVA_VERIFY_TOKEN
//   SUPABASE_URL
//   SUPABASE_SERVICE_ROLE_KEY
//
// Deploy: `supabase functions deploy strava-webhook --no-verify-jwt`
// (no-verify-jwt because Strava's POST has no Supabase auth header)
// -----------------------------------------------------------------------------

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { sendApnsSilent, pushDeliveryLog, eventNameFor } from "../_shared/apns.ts";

const STRAVA_API_BASE = "https://www.strava.com/api/v3";
const STRAVA_OAUTH_URL = "https://www.strava.com/oauth/token";

interface StravaWebhookEvent {
  aspect_type: "create" | "update" | "delete";
  object_type: "activity" | "athlete";
  object_id: number;
  owner_id: number;
  subscription_id: number;
  event_time: number;
  updates?: Record<string, unknown>;
}

interface StoredToken {
  user_id: string;
  access_token: string;
  refresh_token: string;
  expires_at: string;
}

// ── Strava HTTP helpers ──────────────────────────────────────────────────

async function refreshStravaToken(
  refreshToken: string,
): Promise<{ access: string; refresh: string; expiresAt: number } | null> {
  const clientId = Deno.env.get("STRAVA_CLIENT_ID") ?? "";
  const clientSecret = Deno.env.get("STRAVA_CLIENT_SECRET") ?? "";
  if (!clientId || !clientSecret) {
    console.error("[strava-webhook] Missing STRAVA_CLIENT_ID/SECRET");
    return null;
  }

  const body = new URLSearchParams({
    client_id: clientId,
    client_secret: clientSecret,
    grant_type: "refresh_token",
    refresh_token: refreshToken,
  });

  const res = await fetch(STRAVA_OAUTH_URL, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: body.toString(),
  });

  if (!res.ok) {
    console.error(`[strava-webhook] Token refresh failed: ${res.status} ${await res.text()}`);
    return null;
  }

  const json = await res.json();
  return {
    access: json.access_token,
    refresh: json.refresh_token,
    expiresAt: json.expires_at,
  };
}

async function getValidAccessToken(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  token: StoredToken,
): Promise<string | null> {
  const expiresAtMs = new Date(token.expires_at).getTime();
  // Refresh 5 min before actual expiry to avoid mid-request 401s.
  if (expiresAtMs > Date.now() + 5 * 60_000) {
    return token.access_token;
  }

  const refreshed = await refreshStravaToken(token.refresh_token);
  if (!refreshed) return null;

  const newExpiresIso = new Date(refreshed.expiresAt * 1000).toISOString();
  const { error } = await supabase
    .from("user_strava_tokens")
    .update({
      access_token: refreshed.access,
      refresh_token: refreshed.refresh,
      expires_at: newExpiresIso,
      last_rotated_at: new Date().toISOString(),
    })
    .eq("user_id", token.user_id);

  if (error) {
    console.error(`[strava-webhook] Failed to persist refreshed tokens: ${error.message}`);
    return null;
  }

  return refreshed.access;
}

async function fetchStravaActivity(
  accessToken: string,
  activityId: number,
  // deno-lint-ignore no-explicit-any
): Promise<any | null> {
  const res = await fetch(`${STRAVA_API_BASE}/activities/${activityId}?include_all_efforts=true`, {
    headers: { Authorization: `Bearer ${accessToken}` },
  });
  if (!res.ok) {
    console.error(`[strava-webhook] Fetch activity ${activityId} failed: ${res.status}`);
    return null;
  }
  return await res.json();
}

// ── cardio_workouts mapping ──────────────────────────────────────────────

function mapStravaActivityType(stravaType: string): string {
  switch (stravaType) {
    case "Run": return "outdoor_run";
    case "VirtualRun": return "treadmill";
    case "Ride": return "outdoor_cycle";
    case "VirtualRide": return "indoor_cycle";
    case "Walk":
    case "Hike": return "walk";
    case "Swim": return "swimming";
    case "Rowing": return "rowing";
    case "Elliptical": return "elliptical";
    case "StairStepper": return "stair_climber";
    case "Crossfit":
    case "Workout": return "hiit";
    default: return "outdoor_run";
  }
}

async function upsertCardioFromActivity(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  userId: string,
  // deno-lint-ignore no-explicit-any
  activity: any,
): Promise<boolean> {
  const startedAt: string = activity.start_date ?? new Date().toISOString();
  const completedAt = new Date(
    new Date(startedAt).getTime() + (activity.moving_time ?? 0) * 1000,
  ).toISOString();
  const avgSpeedKmh = activity.average_speed != null
    ? activity.average_speed * 3.6
    : null;
  const maxSpeedKmh = activity.max_speed != null
    ? activity.max_speed * 3.6
    : null;

  const row = {
    user_id: userId,
    activity_type: mapStravaActivityType(activity.type ?? activity.sport_type ?? ""),
    workout_name: activity.name ?? null,
    goal_type: "open_goal",
    goal_achieved: true,
    duration_seconds: activity.moving_time ?? 0,
    distance_meters: activity.distance ?? 0,
    calories_burned: activity.calories ?? 0,
    average_speed: avgSpeedKmh,
    max_speed: maxSpeedKmh,
    average_heart_rate: activity.average_heartrate != null
      ? Math.round(activity.average_heartrate)
      : null,
    max_heart_rate: activity.max_heartrate != null
      ? Math.round(activity.max_heartrate)
      : null,
    total_elevation_gain: activity.total_elevation_gain ?? null,
    started_at: startedAt,
    completed_at: completedAt,
    source: "strava",
    external_id: String(activity.id),
    external_url: `https://www.strava.com/activities/${activity.id}`,
    origin_app: "strava",
    suffer_score: activity.suffer_score ?? null,
    kudos_count: activity.kudos_count ?? null,
    achievement_count: activity.achievement_count ?? null,
    polyline_summary: activity.map?.summary_polyline ?? null,
    splits_json: activity.splits_metric ?? null,
    segment_efforts_json: activity.segment_efforts ?? null,
    gear_name: activity.gear?.name ?? null,
    detail_synced_at: new Date().toISOString(),
  };

  const { error } = await supabase
    .from("cardio_workouts")
    .upsert(row, { onConflict: "user_id,external_id" });

  if (error) {
    console.error(`[strava-webhook] cardio_workouts upsert failed: ${error.message}`);
    return false;
  }
  return true;
}

// ── Silent push helper ───────────────────────────────────────────────────
//
// Sends APNs silent pushes (aps.content-available = 1) via the shared
// _shared/apns.ts helper. On the iOS side, `Fit33/SilentPushHandler.swift`
// routes `type: "strava_activity_new"` → a 1-day Strava sync.
//
// 2026-08-01: Migrated to shared helper. Pre-fix bug: this function read
// from the non-existent `push_tokens` table (everywhere else the canonical
// table is `user_push_tokens`), so Strava silent pushes silently no-op'd
// in production. Fixed.
async function sendStravaSilentPush(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  userId: string,
  activityId: number,
): Promise<void> {
  // Read ALL valid tokens (multi-device users own multiple iPhones / iPads).
  const { data: tokens, error } = await supabase
    .from("user_push_tokens")
    .select("device_token, apns_environment, is_valid, updated_at")
    .eq("user_id", userId)
    .eq("is_valid", true)
    .order("updated_at", { ascending: false });

  if (error || !tokens?.length) {
    console.log(`[strava-webhook] No valid push token for user ${userId} — silent push skipped`);
    await pushDeliveryLog(supabase, {
      notificationId: null,
      userId,
      event: "no_valid_token",
      detail: { source: "strava_webhook", token_error: error?.message ?? null, activity_id: activityId },
    });
    return;
  }

  for (const token of tokens) {
    const result = await sendApnsSilent(
      token.device_token,
      {
        type: "strava_activity_new",
        data: { activity_id: String(activityId) },
        expirationSeconds: 3600,
      },
      token.apns_environment,
    );

    await pushDeliveryLog(supabase, {
      notificationId: null,
      userId,
      event: result.success ? "silent_apns_success" : `silent_${eventNameFor(result)}`,
      detail: {
        source: "strava_webhook",
        type: "strava_activity_new",
        activity_id: activityId,
        token_prefix: token.device_token.substring(0, 12),
        apns_env: token.apns_environment,
        status: result.status ?? null,
        reason: result.reason ?? null,
        duration_ms: result.durationMs ?? null,
        error: result.error ?? null,
      },
    });

    if (!result.success) {
      console.warn(`[strava-webhook] APNs ${result.status ?? "?"}: ${result.error ?? "unknown"}`);
      if (result.invalidateToken) {
        await supabase
          .from("user_push_tokens")
          .update({ is_valid: false })
          .eq("user_id", userId)
          .eq("device_token", token.device_token);
        await pushDeliveryLog(supabase, {
          notificationId: null,
          userId,
          event: "token_invalid",
          detail: {
            source: "strava_webhook",
            token_prefix: token.device_token.substring(0, 12),
            reason: result.reason ?? "apple_410ish",
          },
        });
      }
    }
  }
}

// ── Server ───────────────────────────────────────────────────────────────

serve(async (req) => {
  const url = new URL(req.url);

  // 1. Subscription handshake — Strava issues a GET with hub.* params.
  //    We must echo hub.challenge and verify hub.verify_token matches
  //    our stored value.
  if (req.method === "GET") {
    const mode = url.searchParams.get("hub.mode");
    const challenge = url.searchParams.get("hub.challenge");
    const verifyToken = url.searchParams.get("hub.verify_token");
    const expectedToken = Deno.env.get("STRAVA_VERIFY_TOKEN") ?? "";

    if (mode === "subscribe" && verifyToken === expectedToken && challenge) {
      return new Response(
        JSON.stringify({ "hub.challenge": challenge }),
        { status: 200, headers: { "Content-Type": "application/json" } },
      );
    }
    return new Response(JSON.stringify({ error: "Invalid handshake" }), {
      status: 403,
      headers: { "Content-Type": "application/json" },
    });
  }

  // 2. Event delivery.
  if (req.method !== "POST") {
    return new Response("Method Not Allowed", { status: 405 });
  }

  let event: StravaWebhookEvent;
  try {
    event = await req.json();
  } catch {
    return new Response("Bad JSON", { status: 400 });
  }

  // Strava expects a 200 ack within ~2s. Do the heavy work in the
  // background after returning.
  const ack = new Response("ok", { status: 200 });

  // We pass a closure to a fire-and-forget Promise so Deno keeps the
  // handler alive past the response. The `EdgeRuntime.waitUntil` API is
  // not always available in self-hosted Supabase; the simple async
  // pattern below works for both environments.
  (async () => {
    try {
      await processEvent(event);
    } catch (err) {
      console.error(`[strava-webhook] processEvent threw: ${(err as Error).message}`);
    }
  })();

  return ack;
});

async function processEvent(event: StravaWebhookEvent): Promise<void> {
  if (event.object_type !== "activity") return;
  if (event.aspect_type === "delete") {
    // We currently leave deleted activities in cardio_workouts. If we
    // ever want to soft-delete, do it here. Returning early for now.
    return;
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  if (!supabaseUrl || !serviceKey) {
    console.error("[strava-webhook] Missing SUPABASE_URL/SERVICE_ROLE_KEY");
    return;
  }
  const supabase = createClient(supabaseUrl, serviceKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  // Resolve owner_id → user_id via service-role RPC.
  const { data: userIdRow, error: rpcErr } = await supabase.rpc(
    "get_user_id_for_strava_athlete",
    { p_athlete_id: event.owner_id },
  );
  if (rpcErr || !userIdRow) {
    console.warn(
      `[strava-webhook] No user mapped for athlete ${event.owner_id} (rpcErr=${rpcErr?.message ?? "none"})`,
    );
    return;
  }
  const userId = userIdRow as string;

  // Read tokens.
  const { data: tokenRow, error: tokenErr } = await supabase
    .from("user_strava_tokens")
    .select("user_id, access_token, refresh_token, expires_at")
    .eq("user_id", userId)
    .maybeSingle();
  if (tokenErr || !tokenRow) {
    console.warn(`[strava-webhook] No tokens for user ${userId} (err=${tokenErr?.message ?? "none"})`);
    return;
  }

  const accessToken = await getValidAccessToken(supabase, tokenRow as StoredToken);
  if (!accessToken) return;

  const activity = await fetchStravaActivity(accessToken, event.object_id);
  if (!activity) return;

  const ok = await upsertCardioFromActivity(supabase, userId, activity);
  if (!ok) return;

  // Only fire silent push on `create` — `update` events are noisy
  // (kudos count changes) and would spam the carousel.
  if (event.aspect_type === "create") {
    await sendStravaSilentPush(supabase, userId, event.object_id);
  }
}
