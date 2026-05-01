// =============================================================================
// Shared APNs helper for Fit33 edge functions.
// =============================================================================
//
// Single source of truth for:
//   - APNs JWT signing (ES256, .p8 key)
//   - Visible alert pushes (apns-push-type: alert, priority: 10)
//   - Silent background pushes (apns-push-type: background, priority: 5)
//   - Per-environment APNs host routing (sandbox vs production)
//   - Delivery log writes to push_notification_delivery_log
//
// Replaces the duplicated APNs code in:
//   - supabase/functions/send-push-notification/index.ts
//   - supabase/functions/wake-challenge-opponents/index.ts
//   - supabase/functions/strava-webhook/index.ts
//
// Required env vars (same set everywhere):
//   APNS_KEY_ID, APNS_TEAM_ID, APNS_BUNDLE_ID, APNS_PRIVATE_KEY
// -----------------------------------------------------------------------------

import { SignJWT, importPKCS8 } from "https://deno.land/x/jose@v4.14.4/index.ts";

// ── APNs hosts ───────────────────────────────────────────────────────────
export const APNS_HOST_PRODUCTION = "api.push.apple.com";
export const APNS_HOST_SANDBOX = "api.sandbox.push.apple.com";

export function getAPNsHost(apnsEnvironment: string | null | undefined): string {
  return apnsEnvironment === "development" ? APNS_HOST_SANDBOX : APNS_HOST_PRODUCTION;
}

// ── APNs JWT signing ─────────────────────────────────────────────────────
//
// APNs JWTs are valid for ~1 hour. We cache per-process to avoid re-signing
// on every notification within a batch. A new edge-function invocation gets
// a fresh module scope so the cache resets naturally; no cross-invocation
// cache to worry about.

let cachedToken: { token: string; signedAt: number } | null = null;
const TOKEN_TTL_MS = 50 * 60 * 1000; // 50 min — refresh before Apple's 60min limit

export async function signApnsToken(): Promise<string> {
  if (cachedToken && Date.now() - cachedToken.signedAt < TOKEN_TTL_MS) {
    return cachedToken.token;
  }

  const keyId = Deno.env.get("APNS_KEY_ID") ?? "";
  const teamId = Deno.env.get("APNS_TEAM_ID") ?? "";
  const privateKeyPem = (Deno.env.get("APNS_PRIVATE_KEY") ?? "").replace(/\\n/g, "\n");

  if (!keyId || !teamId || !privateKeyPem) {
    throw new Error("APNs config missing (APNS_KEY_ID / APNS_TEAM_ID / APNS_PRIVATE_KEY)");
  }

  const privateKey = await importPKCS8(privateKeyPem, "ES256");
  const token = await new SignJWT({})
    .setProtectedHeader({ alg: "ES256", kid: keyId })
    .setIssuer(teamId)
    .setIssuedAt()
    .sign(privateKey);

  cachedToken = { token, signedAt: Date.now() };
  return token;
}

// ── APNs payload types ───────────────────────────────────────────────────

export interface AlertPayload {
  title: string;
  body: string;
  /// Custom data merged at root level (e.g. `type`, `challenge_id`).
  data?: Record<string, unknown>;
  /// Real badge count (>0 shows; 0 clears).
  badge?: number;
  /// Adds `content-available: 1` ALONGSIDE the alert. Wakes the app in
  /// the background ~30s before the user opens it. Currently used by
  /// `challenge_reaction` so `SmackTalkWidgetBridge` can paint the
  /// shout bubble before the user taps.
  wakeAppForBackgroundPaint?: boolean;
  /// Optional category (for action buttons / grouping in iOS 12+ UI).
  category?: string;
  /// Optional `thread-id` so iOS groups related notifications in
  /// Notification Center (e.g. all rivalry pushes for one challenge).
  threadId?: string;
}

export interface SilentPayload {
  /// `type` field iOS handler routes on (e.g. `challenge_wake`,
  /// `strava_activity_new`, `progress_update`).
  type: string;
  /// Additional custom keys merged at root.
  data?: Record<string, unknown>;
  /// APNs expiration in seconds from now (default 1h).
  expirationSeconds?: number;
}

export interface SendResult {
  success: boolean;
  status?: number;
  /// Full APNs error body if !success.
  error?: string;
  /// Apple's `reason` field parsed from the body when JSON.
  reason?: string;
  /// True when the token should be marked is_valid = false.
  invalidateToken?: boolean;
  /// Round-trip duration of the APNs HTTP call.
  durationMs?: number;
}

// ── Visible alert push ───────────────────────────────────────────────────

export async function sendApnsAlert(
  deviceToken: string,
  payload: AlertPayload,
  apnsEnvironment: string | null | undefined,
): Promise<SendResult> {
  const apnsToken = await signApnsToken();
  const host = getAPNsHost(apnsEnvironment);
  const bundleId = Deno.env.get("APNS_BUNDLE_ID") ?? "";

  const aps: Record<string, unknown> = {
    alert: { title: payload.title, body: payload.body },
    sound: "default",
    badge: payload.badge ?? 0,
    "mutable-content": 1,
  };
  if (payload.wakeAppForBackgroundPaint) aps["content-available"] = 1;
  if (payload.category) aps["category"] = payload.category;
  if (payload.threadId) aps["thread-id"] = payload.threadId;

  const body = JSON.stringify({ aps, ...(payload.data ?? {}) });

  return await postToApns({
    deviceToken,
    apnsToken,
    host,
    body,
    headers: {
      "apns-topic": bundleId,
      "apns-push-type": "alert",
      "apns-priority": "10",
      "apns-expiration": String(Math.floor(Date.now() / 1000) + 86400),
    },
  });
}

// ── Silent background push ───────────────────────────────────────────────
//
// Apple REQUIRES `apns-priority: 5` for silent pushes. Priority 10 is
// silently dropped. (See INFRA_SECURITY_AGENT.md invariant 12.)

export async function sendApnsSilent(
  deviceToken: string,
  payload: SilentPayload,
  apnsEnvironment: string | null | undefined,
): Promise<SendResult> {
  const apnsToken = await signApnsToken();
  const host = getAPNsHost(apnsEnvironment);
  const bundleId = Deno.env.get("APNS_BUNDLE_ID") ?? "";

  const expSec = payload.expirationSeconds ?? 3600;
  const apnsBody = JSON.stringify({
    aps: { "content-available": 1 },
    type: payload.type,
    ...(payload.data ?? {}),
  });

  return await postToApns({
    deviceToken,
    apnsToken,
    host,
    body: apnsBody,
    headers: {
      "apns-topic": bundleId,
      "apns-push-type": "background",
      "apns-priority": "5",
      "apns-expiration": String(Math.floor(Date.now() / 1000) + expSec),
    },
  });
}

// ── Internal: HTTP POST to APNs with timeout + error parsing ─────────────

interface ApnsRequest {
  deviceToken: string;
  apnsToken: string;
  host: string;
  body: string;
  headers: Record<string, string>;
}

async function postToApns(req: ApnsRequest): Promise<SendResult> {
  const start = Date.now();
  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), 10_000);

  try {
    const response = await fetch(`https://${req.host}/3/device/${req.deviceToken}`, {
      method: "POST",
      headers: {
        "authorization": `bearer ${req.apnsToken}`,
        "content-type": "application/json",
        ...req.headers,
      },
      body: req.body,
      signal: controller.signal,
    });
    clearTimeout(timeoutId);

    const durationMs = Date.now() - start;

    if (response.ok) {
      return { success: true, status: response.status, durationMs };
    }

    const errorBody = await response.text();
    let reason: string | undefined;
    try {
      const parsed = JSON.parse(errorBody);
      reason = typeof parsed?.reason === "string" ? parsed.reason : undefined;
    } catch {
      // Not JSON; leave reason undefined.
    }

    const invalidateToken =
      reason === "BadDeviceToken" ||
      reason === "Unregistered" ||
      reason === "DeviceTokenNotForTopic" ||
      errorBody.includes("BadDeviceToken") ||
      errorBody.includes("Unregistered") ||
      errorBody.includes("DeviceTokenNotForTopic");

    return {
      success: false,
      status: response.status,
      error: `APNs ${response.status}: ${errorBody}`,
      reason,
      invalidateToken,
      durationMs,
    };
  } catch (error) {
    clearTimeout(timeoutId);
    const durationMs = Date.now() - start;
    const isAbort = (error as Error)?.name === "AbortError";
    return {
      success: false,
      error: isAbort ? "APNs timeout (10s)" : `Network error: ${String(error)}`,
      durationMs,
    };
  }
}

// =============================================================================
// Delivery log helper — writes one row per state transition to
// push_notification_delivery_log so the CMS Health & Funnel tab and the
// per-user diagnose RPC have full forensic history.
//
// Canonical event names (keep aligned with admin_get_push_funnel
// drop-off categories in CMS):
//
//   enqueued                  — row inserted into push_notification_queue
//   prefs_blocked             — master_enabled=false or type in disabled_types
//   quiet_hours_deferred      — pushed back to next_retry_at
//   cap_exceeded              — daily_cap reached for the day
//   token_found               — at least one valid device token resolved
//   no_valid_token            — zero valid tokens for user
//   token_grace_period        — invalid token within 5min grace
//   token_invalid             — token marked is_valid=false (Apple 410-ish)
//   apns_send_attempt         — about to fire HTTP POST to APNs
//   apns_success              — APNs accepted (HTTP 2xx)
//   apns_error_<status>       — APNs returned non-2xx (status code suffix)
//   retry_scheduled           — transient failure, next_retry_at set
//   notification_failed       — terminal failure (max retries / permanent)
//   delivered                 — service-extension reported handoff (Phase 2)
//   opened                    — user tapped notification (Phase 2)
//   action_taken              — user invoked an action button (Phase 2)
// =============================================================================

export async function pushDeliveryLog(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  args: {
    notificationId?: string | null;
    userId: string;
    event: string;
    detail?: Record<string, unknown>;
  },
): Promise<void> {
  try {
    const row = {
      notification_id: args.notificationId ?? null,
      user_id: args.userId,
      event: args.event,
      detail: args.detail ?? {},
    };
    const { error } = await supabase
      .from("push_notification_delivery_log")
      .insert(row);
    if (error) {
      // Never throw — logging must never break the send path.
      console.warn(JSON.stringify({
        event: "delivery_log_insert_failed",
        notification_id: args.notificationId ?? null,
        user_id: args.userId,
        log_event: args.event,
        error: error.message,
      }));
    }
  } catch (e) {
    console.warn(JSON.stringify({
      event: "delivery_log_threw",
      log_event: args.event,
      error: (e as Error).message,
    }));
  }
}

// Convenience: derive an `apns_error_<status>` event name from a SendResult.
// Returns `apns_error_network` when the call never reached Apple (no status).
export function eventNameFor(result: SendResult): string {
  if (result.success) return "apns_success";
  if (result.status && Number.isFinite(result.status)) return `apns_error_${result.status}`;
  return "apns_error_network";
}
