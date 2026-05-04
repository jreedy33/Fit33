// Supabase Edge Function: sunday-pro-recap
// -----------------------------------------------------------------------------
// Phase 5 monetization (cheat-code retention loop) — locked 2026-05-03.
//
// Sends every active user (Pro tier and free tier alike) a personalized
// "weekly recap" push on Sunday morning. The push deep-links to the
// in-app `/profile/pro-recap` route which renders a celebratory weekly
// summary. Two modes by tier:
//
//   - PRO members: full recap with workout count + WoW delta + streak
//     reinforcement. Pure retention play (Strong + Hevy + MyFitnessPal
//     all do a variation of this; ~15-20% of Pro DAU comes from this push).
//
//   - FREE members: teaser variant — surfaces ONE high-level stat
//     ("Your workouts up 25% week-over-week!") plus the upsell hook
//     ("Pro members see PR breakdown — try Pro free →"). Conversion
//     pressure on a high-attention surface.
//
// Schedule: pg_cron triggers this at :05 every hour Sunday (UTC). The
// function then filters per-user by timezone-local-Sunday-10am so each
// recipient only fires once at 10am LOCAL — anywhere in the world.
//
// Auth model: x-cron-key header carries service-role JWT (mirrors
// `wake-challenge-opponents` + `notification-orchestrator`).
//
// Deploy: `supabase functions deploy sunday-pro-recap`
// Secrets: APNS_KEY_ID, APNS_TEAM_ID, APNS_BUNDLE_ID, APNS_PRIVATE_KEY
// -----------------------------------------------------------------------------

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { buildCorsHeaders } from "../_shared/cors.ts";
import {
  sendApnsAlert,
  pushDeliveryLog,
  eventNameFor,
} from "../_shared/apns.ts";

const MAX_RECIPIENTS_PER_RUN = 1000;
const NOTIFICATION_CATEGORY = "pro_recap";
const NOTIFICATION_TYPE_PRO = "weekly_pro_recap";
const NOTIFICATION_TYPE_FREE = "weekly_recap_teaser";
const DEEP_LINK = "fit33://profile/pro-recap";

interface RequestBody {
  source?: "cron" | "manual";
  user_ids?: string[];
  /** Override target hour for testing (1-23). Default 10am local. */
  target_hour?: number;
  /** Skip the timezone gate (fire to everyone now). Manual mode only. */
  force_send?: boolean;
}

interface UserRecapData {
  user_id: string;
  display_name: string | null;
  is_pro: boolean;
  workouts_this_week: number;
  workouts_last_week: number;
  push_token: string | null;
  apns_environment: string | null;
  timezone: string | null;
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

serve(async (req) => {
  const corsHeaders = buildCorsHeaders(req);
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    // ── Auth: cron key or service role JWT ──────────────────────────────
    const cronKey = req.headers.get("x-cron-key");
    const authHeader = req.headers.get("Authorization");
    let isServiceRole = false;

    if (cronKey && (cronKey === supabaseServiceKey || isServiceRoleJWT(cronKey))) {
      isServiceRole = true;
    } else if (authHeader) {
      const token = authHeader.replace("Bearer ", "");
      if (token === supabaseServiceKey || isServiceRoleJWT(token)) {
        isServiceRole = true;
      }
    }

    if (!isServiceRole) {
      return json({ error: "Unauthorized — service role only" }, 401, corsHeaders);
    }

    let body: RequestBody = {};
    try {
      body = await req.json();
    } catch {
      // Empty body OK for cron invocations.
    }

    const source = body.source ?? "cron";
    const targetHour = body.target_hour ?? 10;
    const forceSend = body.force_send === true && source === "manual";

    // ── Resolve candidate recipients ─────────────────────────────────────
    const recipientIds = body.user_ids ?? null;

    const { data: users, error: usersError } = await supabase.rpc(
      "get_sunday_recap_candidates",
      { p_user_ids: recipientIds },
    );

    if (usersError) {
      console.error("Failed to resolve recap candidates:", usersError);
      return json({ error: "Could not resolve candidates" }, 500, corsHeaders);
    }

    const candidates = (users ?? []) as UserRecapData[];
    if (candidates.length === 0) {
      return json(
        { ok: true, sent: 0, skipped: 0, reason: "no_candidates" },
        200,
        corsHeaders,
      );
    }

    // ── Filter by local Sunday@targetHour gate ───────────────────────────
    const eligible = forceSend
      ? candidates
      : candidates.filter((u) => isLocalSundayAt(u.timezone, targetHour));

    if (eligible.length === 0) {
      return json(
        { ok: true, sent: 0, skipped: candidates.length, reason: "outside_window" },
        200,
        corsHeaders,
      );
    }

    // ── Send loop (capped) ───────────────────────────────────────────────
    const queue = eligible.slice(0, MAX_RECIPIENTS_PER_RUN);
    let sent = 0;
    let failed = 0;

    for (const user of queue) {
      if (!user.push_token) {
        failed++;
        continue;
      }

      const payload = buildPayload(user);
      const notificationType = user.is_pro
        ? NOTIFICATION_TYPE_PRO
        : NOTIFICATION_TYPE_FREE;

      try {
        const result = await sendApnsAlert(
          user.push_token,
          {
            title: payload.title,
            body: payload.body,
            data: {
              deep_link: DEEP_LINK,
              type: notificationType,
              category: NOTIFICATION_CATEGORY,
              week_start: payload.week_start,
              is_pro: user.is_pro,
            },
            badge: 0,
            category: NOTIFICATION_CATEGORY,
            threadId: NOTIFICATION_CATEGORY,
          },
          user.apns_environment,
        );

        await pushDeliveryLog(supabase, {
          userId: user.user_id,
          event: result.success ? "apns_success" : eventNameFor(result),
          detail: {
            source,
            type: notificationType,
            category: NOTIFICATION_CATEGORY,
            apns_env: user.apns_environment,
            status: result.status ?? null,
            reason: result.reason ?? null,
            duration_ms: result.durationMs ?? null,
            error: result.error ?? null,
            week_start: payload.week_start,
          },
        });

        if (result.success) {
          sent++;
        } else {
          failed++;
          if (result.invalidateToken) {
            await supabase
              .from("user_push_tokens")
              .update({ is_valid: false })
              .eq("user_id", user.user_id)
              .eq("device_token", user.push_token);
          }
        }
      } catch (err) {
        console.error(`Recap send failed for user ${user.user_id}:`, err);
        failed++;
      }
    }

    return json(
      {
        ok: true,
        candidates: candidates.length,
        eligible: eligible.length,
        sent,
        failed,
        source,
      },
      200,
      corsHeaders,
    );
  } catch (err) {
    console.error("sunday-pro-recap fatal:", err);
    return json({ error: String(err) }, 500, buildCorsHeaders(req));
  }
});

// ── Helpers ───────────────────────────────────────────────────────────────

function isLocalSundayAt(timezone: string | null, hour: number): boolean {
  const tz = timezone || "America/New_York";
  try {
    const formatter = new Intl.DateTimeFormat("en-US", {
      timeZone: tz,
      weekday: "short",
      hour: "numeric",
      hour12: false,
    });
    const parts = formatter.formatToParts(new Date());
    const weekday = parts.find((p) => p.type === "weekday")?.value;
    const localHour = parseInt(parts.find((p) => p.type === "hour")?.value || "0", 10);
    return weekday === "Sun" && localHour === hour;
  } catch {
    return false;
  }
}

interface RecapPayload {
  title: string;
  body: string;
  week_start: string;
}

function buildPayload(user: UserRecapData): RecapPayload {
  const weekStart = new Date();
  weekStart.setDate(weekStart.getDate() - 7);
  const weekStartIso = weekStart.toISOString().slice(0, 10);

  // Workout-count delta drives the "more / fewer / same" framing.
  const workoutDelta = user.workouts_this_week - user.workouts_last_week;
  const firstName = (user.display_name || "").trim().split(/\s+/)[0] || "Friend";

  if (user.is_pro) {
    // Full Pro recap. Tone: celebratory, factual, "open for the breakdown".
    const title = `${firstName}, your week is in 📊`;
    let body: string;
    if (user.workouts_this_week === 0 && user.workouts_last_week > 0) {
      body =
        "0 workouts this week — your last 4 weeks are in your Pro dashboard. Tap to plan Monday.";
    } else if (user.workouts_this_week === 0) {
      body = "Your week is open. Tap for your Pro dashboard + smart workout suggestions.";
    } else {
      const wkText = `${user.workouts_this_week} workout${user.workouts_this_week === 1 ? "" : "s"}`;
      let deltaText = "";
      if (workoutDelta > 0) deltaText = ` · ${workoutDelta} more than last week ⬆️`;
      else if (workoutDelta < 0) {
        deltaText = ` · ${Math.abs(workoutDelta)} fewer than last week`;
      }
      body = `${wkText}${deltaText} — open for the full breakdown.`;
    }
    return { title, body, week_start: weekStartIso };
  }

  // Free teaser: ONE stat + Pro upsell. Keep it punchy and aspirational.
  const title = `${firstName}, your week in numbers`;
  let body: string;
  if (user.workouts_this_week === 0 && user.workouts_last_week === 0) {
    body =
      "Quiet week. Pro shows weekly insights + a smart Monday workout picked for you — try free →";
  } else if (user.workouts_this_week === 0) {
    body =
      "0 workouts this week — bounce back Monday. Pro members get a weekly recap + smart suggestions.";
  } else if (workoutDelta > 0) {
    body =
      `${user.workouts_this_week} workouts (${workoutDelta} more than last week!) — Pro shows the full breakdown. Try free →`;
  } else if (user.workouts_this_week >= 4) {
    body =
      `${user.workouts_this_week} workouts this week — that's Pro-tier consistency. Unlock weekly insights free →`;
  } else {
    body =
      `${user.workouts_this_week} workout${user.workouts_this_week === 1 ? "" : "s"} this week. Pro shows weekly trends + PR breakdown — try free →`;
  }
  return { title, body, week_start: weekStartIso };
}

function json(payload: unknown, status: number, corsHeaders: HeadersInit): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: {
      "Content-Type": "application/json",
      ...corsHeaders,
    },
  });
}
