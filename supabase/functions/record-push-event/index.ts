// =============================================================================
// record-push-event — push delivery / open / action telemetry
// =============================================================================
//
// Smart Notification Engine — Phase 2.
//
// Endpoint receives lightweight POSTs from:
//   - The iOS Notification Service Extension when an APNs push arrives
//     and is about to be presented (`event: "delivered"`).
//   - The iOS NotificationManager `userNotificationCenter(_:didReceive:)`
//     handler when the user taps a notification (`event: "opened"`).
//   - Action-button taps (`event: "action_taken"` with `action_id`).
//
// All three write to push_notification_delivery_log so the funnel:
//   enqueued → apns_success → delivered → opened → action_taken
// is queryable in the CMS Health & Funnel tab.
//
// Auth: User JWT only. (Each user reports events for THEIR notifications;
// service-role is overkill and we don't want admin tokens leaking through
// the iOS app.) The endpoint enforces user_id == auth.uid() — never trusts
// the body's user_id.
//
// Idempotency: Apple may invoke the service extension twice for the same
// notification on flaky networks. We dedupe on (notification_id, event)
// so a duplicate `delivered` post no-ops.
//
// Deploy: supabase functions deploy record-push-event
// =============================================================================

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { buildCorsHeaders, requireUserAuth } from "../_shared/cors.ts";
import { pushDeliveryLog } from "../_shared/apns.ts";

interface RequestBody {
  event: "delivered" | "opened" | "action_taken" | "dismissed";
  notification_id?: string | null;   // queue.id when known (orchestrator pushes)
  intent_id?: string | null;          // intents.id (orchestrator pushes only)
  intent_kind?: string | null;
  category?: string | null;
  action_id?: string | null;          // for action_taken
  /// Time the event happened on-device (ISO8601). Server uses NOW() for
  /// ordering, but client_at lets us measure delivery latency.
  client_at?: string | null;
}

const ALLOWED_EVENTS = new Set(["delivered", "opened", "action_taken", "dismissed"]);

serve(async (req) => {
  const corsHeaders = buildCorsHeaders(req);
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405, corsHeaders);
  }

  try {
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    const auth = await requireUserAuth(req, supabase, corsHeaders);
    if (!auth.ok) return auth.response;
    const userId = auth.auth.userId;
    if (!userId) {
      return json({ error: "User session required (no service-role)" }, 401, corsHeaders);
    }

    let body: RequestBody;
    try {
      body = await req.json();
    } catch {
      return json({ error: "Bad JSON" }, 400, corsHeaders);
    }

    if (!body.event || !ALLOWED_EVENTS.has(body.event)) {
      return json({ error: "Unknown event" }, 400, corsHeaders);
    }

    // Idempotency check — silently no-op duplicate (notification_id, event).
    if (body.notification_id) {
      const { count } = await supabase
        .from("push_notification_delivery_log")
        .select("*", { count: "exact", head: true })
        .eq("notification_id", body.notification_id)
        .eq("user_id", userId)
        .eq("event", body.event);
      if ((count ?? 0) > 0) {
        return json({ message: "Already recorded", deduped: true }, 200, corsHeaders);
      }
    }

    await pushDeliveryLog(supabase, {
      notificationId: body.notification_id ?? null,
      userId,
      event: body.event,
      detail: {
        intent_id: body.intent_id ?? null,
        intent_kind: body.intent_kind ?? null,
        category: body.category ?? null,
        action_id: body.action_id ?? null,
        client_at: body.client_at ?? null,
        platform: "ios",
      },
    });

    // For 'opened' on an orchestrator-driven push, also bump engagement
    // history immediately so the next orchestration cycle benefits from
    // the signal without waiting for the nightly rollup.
    if (body.event === "opened" && body.category) {
      try {
        const hour = new Date().getUTCHours();
        await supabase
          .from("notification_engagement_history")
          .upsert({
            user_id: userId,
            category: body.category,
            hour_of_day: hour,
            // Generated open_rate column derives from these.
            delivered_count: 0,
            opened_count: 0,
            window_start: new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString(),
            window_end: new Date().toISOString(),
            refreshed_at: new Date().toISOString(),
          }, { onConflict: "user_id,category,hour_of_day", ignoreDuplicates: true });

        // Increment opened_count.
        const { data: existing } = await supabase
          .from("notification_engagement_history")
          .select("opened_count")
          .eq("user_id", userId)
          .eq("category", body.category)
          .eq("hour_of_day", hour)
          .maybeSingle();

        if (existing) {
          await supabase
            .from("notification_engagement_history")
            .update({ opened_count: (existing.opened_count as number) + 1, refreshed_at: new Date().toISOString() })
            .eq("user_id", userId)
            .eq("category", body.category)
            .eq("hour_of_day", hour);
        }
      } catch {
        // Engagement bump is opportunistic; nightly rollup will fix.
      }
    }

    return json({ message: "Recorded", event: body.event }, 200, corsHeaders);
  } catch (error) {
    console.error("record-push-event error:", error);
    return json({ error: String(error) }, 500, buildCorsHeaders(req));
  }
});

function json(body: unknown, status: number, corsHeaders: Record<string, string>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
