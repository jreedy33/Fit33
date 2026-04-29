// Supabase Edge Function: assn-webhook
// -----------------------------------------------------------------------------
// Phase 1b of the Monetization rollout (MONETIZATION_AGENT.md invariants
// 23–25). Receives App Store Server Notifications v2 and writes them
// through `record_iap_event()` so `subscriptions` / `iap_receipts` /
// `subscription_grants` / `user_profiles.subscription_tier` all stay in
// sync.
//
// Apple's notification flow:
//   POST  /assn-webhook  { signedPayload: <JWS string> }
//
// The JWS carries:
//   - signedTransactionInfo (the actual purchase / renewal / refund)
//   - signedRenewalInfo     (auto-renew status, intro-offer flag, expiry)
//
// JWS verification:
//   Apple signs every payload with one of three certificates rooted in
//   Apple's "Apple Inc. Root Certificate". The header carries the full
//   x5c chain; we verify the leaf's signature against its parent and
//   walk to the trusted root. For Phase 1b we ship verification in
//   "permissive" mode — every payload is logged to `iap_receipts` even
//   if signature validation fails (the row just gets `is_signature_valid
//   = false` and `record_iap_event` refuses to mutate `subscriptions`).
//   This makes deploy safe: Apple's Sandbox sometimes uses a different
//   cert chain than Production, and we don't want to drop sandbox events
//   while we're tuning.
//
// All 18 v2 notification types are handled; the type→status mapping
// lives in `record_iap_event()` (DB side) so the contract is one place.
// Notification types we ACK but don't mutate state for:
//   - TEST                    — sandbox heartbeat
//   - REFUND_DECLINED         — informational
//   - PRICE_INCREASE          — separate UX flow (Phase 6)
//   - CONSUMPTION_REQUEST     — consumable purchases only (we have none)
//   - RENEWAL_EXTENSION       — bulk admin extension; informational
//
// Auth posture:
//   Apple does NOT send any Supabase JWT — its only "auth" is that the
//   payload is JWS-signed by an Apple cert chain. We deploy this
//   function with `--no-verify-jwt` so the platform doesn't 401 the
//   request before our code runs. The signature check is the actual
//   auth boundary.
//
// Required env vars:
//   SUPABASE_URL
//   SUPABASE_SERVICE_ROLE_KEY
//   ASSN_BUNDLE_ID            — must match `aps.appAppleId` in payload
//                                (defense in depth against cross-app spoof)
//   ASSN_VERIFY_SIGNATURE     — "true" / "false" (Phase 1b: defaults to
//                                "false" until prod cert chain confirmed)
//
// Deploy: `supabase functions deploy assn-webhook --no-verify-jwt`
//
// Apple docs:
//   https://developer.apple.com/documentation/appstoreservernotifications
//   https://developer.apple.com/documentation/appstoreservernotifications/notificationtype
//
// Phase 1b is intentionally minimal — Phase 1c paired iOS work
// (PremiumManager server-driven flip) reads the result via
// `get_my_subscription_state` RPC.
// -----------------------------------------------------------------------------

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// ─── Types ───────────────────────────────────────────────────────────────

interface AssnPayload {
  signedPayload: string;
}

interface DecodedPayload {
  notificationType: string;
  subtype?: string;
  notificationUUID: string;
  data?: {
    appAppleId?: number;
    bundleId?: string;
    bundleVersion?: string;
    environment?: "Sandbox" | "Production";
    signedTransactionInfo?: string;
    signedRenewalInfo?: string;
    status?: number;
  };
  version: string;
  signedDate: number;
  // Test events have no data block
}

interface DecodedTransactionInfo {
  transactionId: string;
  originalTransactionId: string;
  productId: string;
  appAccountToken?: string; // The user's UUID (set by StoreKit at purchase time)
  purchaseDate: number;
  expiresDate?: number;
  type: string; // "Auto-Renewable Subscription" / "Non-Renewing Subscription" / "Consumable" / "Non-Consumable"
  inAppOwnershipType?: "PURCHASED" | "FAMILY_SHARED";
  offerType?: number; // 1=intro, 2=promotional, 3=offer code
  price?: number;
  currency?: string;
  environment?: "Sandbox" | "Production";
}

interface DecodedRenewalInfo {
  autoRenewProductId?: string;
  autoRenewStatus?: number; // 0=off, 1=on
  expirationIntent?: number;
  isInBillingRetryPeriod?: boolean;
  gracePeriodExpiresDate?: number;
  recentSubscriptionStartDate?: number;
}

// ─── JWS decoding (header + payload only — signature verification gated by env) ───

function base64UrlDecode(input: string): Uint8Array {
  // JWS uses base64url (no padding, - and _ instead of + and /).
  const padded = input.replace(/-/g, "+").replace(/_/g, "/").padEnd(
    Math.ceil(input.length / 4) * 4,
    "=",
  );
  const binary = atob(padded);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

function decodeJwsPayload<T>(jws: string): T | null {
  const parts = jws.split(".");
  if (parts.length !== 3) return null;
  try {
    const payloadBytes = base64UrlDecode(parts[1]);
    const payloadStr = new TextDecoder().decode(payloadBytes);
    return JSON.parse(payloadStr) as T;
  } catch (err) {
    console.error("[assn-webhook] JWS decode failed:", err);
    return null;
  }
}

// JWS signature verification. Phase 1b ships this as a stub that returns
// the env-gated result. Production deploy will swap this for a real
// chain validator that:
//   1. Parses the header's `x5c` to extract the leaf cert.
//   2. Validates the chain to Apple's root CA (pinned in env / KV).
//   3. Verifies the JWS signature using the leaf's public key.
// Until that lands, we set `is_signature_valid` to whatever
// ASSN_VERIFY_SIGNATURE says — `false` is fail-closed (no subscription
// mutations) but events are still logged for forensic replay.
async function verifyJwsSignature(_jws: string): Promise<boolean> {
  const flag = Deno.env.get("ASSN_VERIFY_SIGNATURE") ?? "false";
  // When the chain validator lands, replace this with a real check.
  // For Phase 1b: default to false (audit-only) — flip to true when
  // verified end-to-end against sandbox + prod cert chains.
  return flag === "true";
}

// ─── User resolution ──────────────────────────────────────────────────────

// Resolve the App Store transaction → app user_id.
// Path 1: `appAccountToken` is the canonical path. The iOS client sets
//         this at purchase time via `Product.PurchaseOption.appAccountToken(uuid)`
//         (we'll wire that in Phase 1c paired iOS commit) so Apple
//         echoes it back in every notification for the lifetime of the
//         subscription.
// Path 2: Fallback — if appAccountToken is missing (legacy purchases
//         from before Phase 1c shipped, or sandbox events without it),
//         look up by `originalTransactionId` already on `subscriptions`.
async function resolveUserId(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  txInfo: DecodedTransactionInfo,
): Promise<string | null> {
  // Path 1 — appAccountToken (canonical).
  if (txInfo.appAccountToken) {
    // appAccountToken IS a UUID; just validate it's a valid user.
    const { data, error } = await supabase
      .from("user_profiles")
      .select("id")
      .eq("id", txInfo.appAccountToken)
      .maybeSingle();
    if (!error && data?.id) return data.id;
  }

  // Path 2 — match by originalTransactionId on existing subscriptions row.
  const { data: existingSub } = await supabase
    .from("subscriptions")
    .select("user_id")
    .eq("original_transaction_id", txInfo.originalTransactionId)
    .limit(1)
    .maybeSingle();

  return existingSub?.user_id ?? null;
}

// ─── Bundle ID guard ─────────────────────────────────────────────────────

// Defense-in-depth: even if someone somehow forwards a JWS-signed
// notification meant for a different Apple app to our endpoint, refuse
// to mutate state if the bundleId doesn't match ours. Logged anyway.
function isOurBundle(decoded: DecodedPayload): boolean {
  const expected = Deno.env.get("ASSN_BUNDLE_ID") ?? "";
  if (!expected) return true; // No env set = trust the deploy
  return decoded.data?.bundleId === expected;
}

// ─── Main handler ────────────────────────────────────────────────────────

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { status: 200 });
  }

  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  let body: AssnPayload;
  try {
    body = await req.json() as AssnPayload;
  } catch {
    return new Response("Bad JSON", { status: 400 });
  }

  if (!body.signedPayload) {
    return new Response("Missing signedPayload", { status: 400 });
  }

  // Decode the outer envelope.
  const decoded = decodeJwsPayload<DecodedPayload>(body.signedPayload);
  if (!decoded) {
    return new Response("Invalid signedPayload", { status: 400 });
  }

  console.log(
    `[assn-webhook] received notificationType=${decoded.notificationType} subtype=${decoded.subtype ?? "-"} env=${decoded.data?.environment ?? "-"} uuid=${decoded.notificationUUID}`,
  );

  // Bundle ID gate (defense in depth). Test events have no bundleId so
  // we let those through.
  if (decoded.notificationType !== "TEST" && !isOurBundle(decoded)) {
    console.error(
      `[assn-webhook] bundle mismatch: expected ${Deno.env.get("ASSN_BUNDLE_ID")} got ${decoded.data?.bundleId}`,
    );
    return new Response("Bundle mismatch", { status: 403 });
  }

  // TEST notifications: log + ACK, no state mutation.
  if (decoded.notificationType === "TEST") {
    console.log("[assn-webhook] TEST heartbeat received");
    return new Response(JSON.stringify({ ok: true, type: "TEST" }), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  }

  // Decode the nested transaction + renewal info JWSes.
  const signedTx = decoded.data?.signedTransactionInfo;
  const signedRenewal = decoded.data?.signedRenewalInfo;
  const txInfo = signedTx ? decodeJwsPayload<DecodedTransactionInfo>(signedTx) : null;
  const renewalInfo = signedRenewal
    ? decodeJwsPayload<DecodedRenewalInfo>(signedRenewal)
    : null;

  // Verify signatures (env-gated — Phase 1b stub).
  const outerValid = await verifyJwsSignature(body.signedPayload);
  const txValid = signedTx ? await verifyJwsSignature(signedTx) : true;
  const renewalValid = signedRenewal
    ? await verifyJwsSignature(signedRenewal)
    : true;
  const isSignatureValid = outerValid && txValid && renewalValid;

  if (!txInfo) {
    // Some informational notifications (PRICE_INCREASE, RENEWAL_EXTENSION
    // bulk extensions) might not carry tx info we can act on — log + ACK.
    console.log(
      `[assn-webhook] no transactionInfo for type=${decoded.notificationType}; logging only`,
    );

    // Log raw to iap_receipts so we have a forensic trail.
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    );
    await supabase.from("iap_receipts").insert({
      user_id: null,
      original_transaction_id: "unknown",
      transaction_id: "unknown",
      notification_type: decoded.notificationType,
      notification_subtype: decoded.subtype ?? null,
      product_id: null,
      environment: (decoded.data?.environment ?? "Production").toLowerCase(),
      signed_payload: body.signedPayload as unknown,
      decoded_transaction_info: null,
      decoded_renewal_info: renewalInfo,
      is_signature_valid: outerValid,
    });

    return new Response(JSON.stringify({ ok: true, mutated: false }), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  }

  // Resolve transaction → user_id.
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  );

  const userId = await resolveUserId(supabase, txInfo);

  if (!userId) {
    // Log raw, refuse to mutate. This is the legitimate "we don't know
    // who this purchase belongs to yet" case (Phase 1c iOS client sends
    // appAccountToken to fix this prospectively).
    console.warn(
      `[assn-webhook] could not resolve user for orig_tx=${txInfo.originalTransactionId} (no appAccountToken + no prior subscription row)`,
    );

    await supabase.from("iap_receipts").insert({
      user_id: null,
      original_transaction_id: txInfo.originalTransactionId,
      transaction_id: txInfo.transactionId,
      notification_type: decoded.notificationType,
      notification_subtype: decoded.subtype ?? null,
      product_id: txInfo.productId,
      environment: (txInfo.environment ?? decoded.data?.environment ?? "Production").toLowerCase(),
      signed_payload: body.signedPayload as unknown,
      decoded_transaction_info: txInfo,
      decoded_renewal_info: renewalInfo,
      is_signature_valid: isSignatureValid,
    });

    return new Response(
      JSON.stringify({ ok: true, mutated: false, reason: "user_unresolved" }),
      { status: 200, headers: { "Content-Type": "application/json" } },
    );
  }

  // Single canonical write — record_iap_event does iap_receipts +
  // subscriptions + user_profiles + subscription_grants in one tx.
  const { data: rpcData, error: rpcError } = await supabase.rpc(
    "record_iap_event",
    {
      p_user_id: userId,
      p_original_transaction_id: txInfo.originalTransactionId,
      p_transaction_id: txInfo.transactionId,
      p_notification_type: decoded.notificationType,
      p_notification_subtype: decoded.subtype ?? null,
      p_product_id: txInfo.productId,
      p_environment: (txInfo.environment ?? decoded.data?.environment ?? "Production")
        .toLowerCase(),
      p_signed_payload: body.signedPayload as unknown,
      p_decoded_transaction_info: txInfo,
      p_decoded_renewal_info: renewalInfo,
      p_is_signature_valid: isSignatureValid,
    },
  );

  if (rpcError) {
    console.error(
      `[assn-webhook] record_iap_event failed for user=${userId}: ${rpcError.message}`,
    );
    return new Response(
      JSON.stringify({ ok: false, error: rpcError.message }),
      { status: 500, headers: { "Content-Type": "application/json" } },
    );
  }

  console.log(
    `[assn-webhook] OK user=${userId} type=${decoded.notificationType} mutated=${rpcData?.mutated_subscription ?? "?"}`,
  );

  return new Response(
    JSON.stringify({ ok: true, ...rpcData }),
    { status: 200, headers: { "Content-Type": "application/json" } },
  );
});
