// Supabase Edge Function: compute-strava-insights
// -----------------------------------------------------------------------------
// Phase 3 of the Strava Integration Upgrade.
//
// Nightly worker that scans each user's last 60 days of Strava activities
// (`cardio_workouts` where source='strava') and surfaces personalized
// insights into `user_personalized_insights` for the Smart Welcome card +
// AdvancedIntelligenceService consumers.
//
// Insights computed:
//   1. strava_weekly_mileage_delta   "+18% mileage vs last week."
//   2. strava_pace_trend_4w          "Easy-run pace improved 12 s / km this month."
//   3. strava_hr_zone_drift          "Avg HR is up 6 bpm at the same pace — fatigue."
//   4. strava_segment_pr             Only when the latest activity has
//                                    achievement_count > 0 (a PR / KOM).
//   5. strava_recovery_pairing       Joins daily_readiness_history with
//                                    same-day suffer_score: "high-effort
//                                    runs cost you ~22% next-day recovery."
//
// All inserts go through `user_personalized_insights` with
// onConflict: "user_id,insight_key" (Data invariant #36) so re-runs
// overwrite stale copies cleanly.
//
// Auth: x-cron-key header OR direct service-role bearer.
//
// Deploy: `supabase functions deploy compute-strava-insights`
// -----------------------------------------------------------------------------

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { buildCorsHeaders } from "../_shared/cors.ts";

// ── Config ────────────────────────────────────────────────────────────────
const LOOKBACK_DAYS = 60;
const MIN_RUNS_4W = 6;
const MIN_RUNS_THIS_WEEK = 1;
const MAX_USERS_PER_RUN = 500;

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

// ── Types ─────────────────────────────────────────────────────────────────
interface RequestBody {
  source?: "cron" | "manual" | "foreground";
  userId?: string;
}

interface CardioRow {
  user_id: string;
  activity_type: string;
  distance_meters: number | null;
  duration_seconds: number | null;
  average_speed: number | null; // km/h
  average_heart_rate: number | null;
  suffer_score: number | null;
  achievement_count: number | null;
  started_at: string;
}

interface ReadinessRow {
  date: string;
  score: number | null;
}

interface InsightUpsert {
  user_id: string;
  insight_key: string;
  insight_type: string;
  insight_category: string;
  title: string;
  message: string;
  detail_message: string | null;
  priority: number;
  icon: string;
  accent_color: string;
  correlation_type: string;
  r_squared: number;
  p_value: number;
  sample_size: number;
  wearable_source: "whoop" | "oura" | "fitbit" | "healthkit" | "derived";
}

// ── User selection ───────────────────────────────────────────────────────
// deno-lint-ignore no-explicit-any
async function pickActiveStravaUsers(supabase: any, manualUserId?: string): Promise<string[]> {
  if (manualUserId) return [manualUserId];

  const since = new Date();
  since.setDate(since.getDate() - LOOKBACK_DAYS);
  const sinceISO = since.toISOString();

  const { data, error } = await supabase
    .from("cardio_workouts")
    .select("user_id")
    .eq("source", "strava")
    .gte("started_at", sinceISO);

  if (error || !data?.length) return [];

  const set = new Set<string>(
    data.map((r: { user_id: string }) => r.user_id).filter(Boolean),
  );
  return Array.from(set).slice(0, MAX_USERS_PER_RUN);
}

// ── Per-user computation ─────────────────────────────────────────────────
async function computeUserInsights(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  userId: string,
): Promise<InsightUpsert[]> {
  const since = new Date();
  since.setDate(since.getDate() - LOOKBACK_DAYS);
  const sinceISO = since.toISOString();

  const [stravaRes, readinessRes] = await Promise.all([
    supabase
      .from("cardio_workouts")
      .select(
        "user_id, activity_type, distance_meters, duration_seconds, average_speed, average_heart_rate, suffer_score, achievement_count, started_at",
      )
      .eq("user_id", userId)
      .eq("source", "strava")
      .gte("started_at", sinceISO)
      .order("started_at", { ascending: true }),
    supabase
      .from("daily_readiness_history")
      .select("date, score")
      .eq("user_id", userId)
      .gte("date", since.toISOString().slice(0, 10)),
  ]);

  const rows: CardioRow[] = stravaRes.data ?? [];
  if (rows.length === 0) return [];

  const insights: InsightUpsert[] = [];

  // ── Helper buckets ────────────────────────────────────────────────────
  const now = new Date();
  const weekAgo = new Date(now); weekAgo.setDate(weekAgo.getDate() - 7);
  const twoWeeksAgo = new Date(now); twoWeeksAgo.setDate(twoWeeksAgo.getDate() - 14);
  const fourWeeksAgo = new Date(now); fourWeeksAgo.setDate(fourWeeksAgo.getDate() - 28);

  const mileageBetween = (start: Date, end: Date): number => {
    let m = 0;
    for (const r of rows) {
      const ts = new Date(r.started_at).getTime();
      if (ts >= start.getTime() && ts < end.getTime()) {
        m += r.distance_meters ?? 0;
      }
    }
    return m;
  };

  // ── 1. Weekly mileage delta ───────────────────────────────────────────
  const thisWeekRuns = rows.filter(
    (r) => r.activity_type === "outdoor_run" && new Date(r.started_at) >= weekAgo,
  );
  if (thisWeekRuns.length >= MIN_RUNS_THIS_WEEK) {
    const thisWeekKm = mileageBetween(weekAgo, now) / 1000;
    const lastWeekKm = mileageBetween(twoWeeksAgo, weekAgo) / 1000;
    if (lastWeekKm > 1 && thisWeekKm > 0) {
      const deltaPct = ((thisWeekKm - lastWeekKm) / lastWeekKm) * 100;
      if (Math.abs(deltaPct) >= 10) {
        const sign = deltaPct >= 0 ? "+" : "";
        insights.push({
          user_id: userId,
          insight_key: "strava_weekly_mileage_delta",
          insight_type: "trend",
          insight_category: "workout",
          title: deltaPct >= 0 ? "Mileage on the rise" : "Lighter week",
          message: `${sign}${deltaPct.toFixed(0)}% running mileage vs last week (${thisWeekKm.toFixed(1)} km).`,
          detail_message: deltaPct >= 25
            ? "Big jumps over 10% / week raise injury risk — keep one easy run truly easy."
            : null,
          priority: 5,
          icon: "figure.run",
          accent_color: "orange",
          correlation_type: "strava_weekly_mileage",
          r_squared: 0,
          p_value: 0,
          sample_size: thisWeekRuns.length,
          wearable_source: "derived",
        });
      }
    }
  }

  // ── 2. 4-week pace trend (easy runs only) ────────────────────────────
  const easyRuns = rows.filter(
    (r) =>
      r.activity_type === "outdoor_run" &&
      r.average_speed != null &&
      r.average_speed > 0 &&
      // "Easy" = below 12 km/h ≈ 8:00/mi. Filters out tempo / interval runs.
      r.average_speed < 12 &&
      new Date(r.started_at) >= fourWeeksAgo,
  );
  if (easyRuns.length >= MIN_RUNS_4W) {
    // Compare first half vs second half of the 4-week window — small-N
    // safe (no Spearman needed) and robust to a single fast workout.
    const mid = Math.floor(easyRuns.length / 2);
    const earlyAvg = avg(easyRuns.slice(0, mid).map((r) => r.average_speed!));
    const lateAvg = avg(easyRuns.slice(mid).map((r) => r.average_speed!));
    const earlyPaceSecPerKm = 3600 / earlyAvg;
    const latePaceSecPerKm = 3600 / lateAvg;
    const paceDelta = earlyPaceSecPerKm - latePaceSecPerKm; // positive = improved
    if (Math.abs(paceDelta) >= 5) {
      const improved = paceDelta > 0;
      insights.push({
        user_id: userId,
        insight_key: "strava_pace_trend_4w",
        insight_type: "trend",
        insight_category: "workout",
        title: improved ? "Your easy-run pace is dropping" : "Your easy-run pace is slipping",
        message: improved
          ? `Easy-run pace improved ~${paceDelta.toFixed(0)} s/km over the last month.`
          : `Easy-run pace slowed ~${Math.abs(paceDelta).toFixed(0)} s/km this month — fatigue or fitness loss?`,
        detail_message: improved
          ? "Fitness is climbing — your aerobic base is getting more efficient at the same effort."
          : "Pull back intensity for a week and re-test. If it lingers, consider a deload.",
        priority: improved ? 5 : 6,
        icon: "speedometer",
        accent_color: improved ? "green" : "orange",
        correlation_type: "strava_pace_trend",
        r_squared: 0,
        p_value: 0,
        sample_size: easyRuns.length,
        wearable_source: "derived",
      });
    }
  }

  // ── 3. HR zone drift (same-pace HR creep over 4 weeks) ───────────────
  const hrRuns = rows.filter(
    (r) =>
      r.activity_type === "outdoor_run" &&
      r.average_heart_rate != null &&
      r.average_speed != null &&
      r.average_speed > 0 &&
      new Date(r.started_at) >= fourWeeksAgo,
  );
  if (hrRuns.length >= MIN_RUNS_4W) {
    const mid = Math.floor(hrRuns.length / 2);
    const early = hrRuns.slice(0, mid);
    const late = hrRuns.slice(mid);
    const earlyHrPerSpeed = avg(
      early.map((r) => (r.average_heart_rate! / r.average_speed!)),
    );
    const lateHrPerSpeed = avg(
      late.map((r) => (r.average_heart_rate! / r.average_speed!)),
    );
    if (earlyHrPerSpeed > 0) {
      const driftPct = ((lateHrPerSpeed - earlyHrPerSpeed) / earlyHrPerSpeed) * 100;
      if (Math.abs(driftPct) >= 4) {
        const fatiguing = driftPct > 0;
        insights.push({
          user_id: userId,
          insight_key: "strava_hr_zone_drift",
          insight_type: "trend",
          insight_category: "recovery",
          title: fatiguing ? "HR climbing at the same pace" : "Aerobic efficiency improving",
          message: fatiguing
            ? `Your average HR is up ${driftPct.toFixed(0)}% at the same pace — fatigue creeping in.`
            : `Your average HR is down ${Math.abs(driftPct).toFixed(0)}% at the same pace — aerobic gains.`,
          detail_message: fatiguing
            ? "Add a true Z2 day or shorten your next long run."
            : "Endurance base is building — keep stacking easy miles.",
          priority: fatiguing ? 7 : 5,
          icon: fatiguing ? "exclamationmark.triangle.fill" : "heart.text.square.fill",
          accent_color: fatiguing ? "orange" : "green",
          correlation_type: "strava_hr_zone_drift",
          r_squared: 0,
          p_value: 0,
          sample_size: hrRuns.length,
          wearable_source: "derived",
        });
      }
    }
  }

  // ── 4. Segment PR (latest activity only) ─────────────────────────────
  const latest = rows[rows.length - 1];
  if (latest && (latest.achievement_count ?? 0) > 0) {
    insights.push({
      user_id: userId,
      insight_key: "strava_segment_pr",
      insight_type: "tip",
      insight_category: "workout",
      title: "🏆 You bagged a Strava PR",
      message: `Your last ${latest.activity_type.replace("_", " ")} hit ${latest.achievement_count} PR${(latest.achievement_count ?? 0) > 1 ? "s" : ""} or KOM/QOM segment${(latest.achievement_count ?? 0) > 1 ? "s" : ""}.`,
      detail_message: "Open the activity in Strava to see which segments you crushed.",
      priority: 8,
      icon: "trophy.fill",
      accent_color: "orange",
      correlation_type: "strava_segment_pr",
      r_squared: 0,
      p_value: 0,
      sample_size: 1,
      wearable_source: "derived",
    });
  }

  // ── 5. Recovery pairing (suffer_score → next-day readiness) ──────────
  const readinessByDate = new Map<string, number>();
  for (const r of (readinessRes.data ?? []) as ReadinessRow[]) {
    if (r.date && r.score != null) readinessByDate.set(r.date, r.score);
  }
  if (readinessByDate.size >= 14) {
    const pairs: { suffer: number; nextScore: number; baseScore: number }[] = [];
    for (const r of rows) {
      if ((r.suffer_score ?? 0) <= 0) continue;
      const day = r.started_at.slice(0, 10);
      const next = addDaysStr(day, 1);
      const baseScore = readinessByDate.get(day);
      const nextScore = readinessByDate.get(next);
      if (baseScore != null && nextScore != null) {
        pairs.push({ suffer: r.suffer_score!, nextScore, baseScore });
      }
    }
    if (pairs.length >= 6) {
      const high = pairs.filter((p) => p.suffer >= 100);
      const low = pairs.filter((p) => p.suffer < 50);
      if (high.length >= 3 && low.length >= 3) {
        const highDelta = avg(high.map((p) => p.nextScore - p.baseScore));
        const lowDelta = avg(low.map((p) => p.nextScore - p.baseScore));
        const cost = lowDelta - highDelta; // bigger = high-effort costs more
        if (cost >= 5) {
          insights.push({
            user_id: userId,
            insight_key: "strava_recovery_pairing",
            insight_type: "correlation",
            insight_category: "recovery",
            title: "High-effort runs hit your recovery hard",
            message: `Days after suffer scores ≥ 100 your readiness drops ~${cost.toFixed(0)} points more than after easy runs.`,
            detail_message: "Schedule recovery (sleep, mobility, easy day) the day after high-effort sessions.",
            priority: 7,
            icon: "bolt.heart.fill",
            accent_color: "orange",
            correlation_type: "strava_suffer_vs_recovery",
            r_squared: 0,
            p_value: 0,
            sample_size: pairs.length,
            wearable_source: "derived",
          });
        }
      }
    }
  }

  return insights;
}

function avg(xs: number[]): number {
  if (xs.length === 0) return 0;
  return xs.reduce((a, b) => a + b, 0) / xs.length;
}

function addDaysStr(dateStr: string, days: number): string {
  const d = new Date(dateStr);
  d.setDate(d.getDate() + days);
  return d.toISOString().slice(0, 10);
}

// ── Entry point ──────────────────────────────────────────────────────────
serve(async (req) => {
  const corsHeaders = buildCorsHeaders(req);
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    const cronKey = req.headers.get("x-cron-key");
    const authHeader = req.headers.get("Authorization") || "";

    let authorized = false;
    if (cronKey && isServiceRoleJWT(cronKey)) authorized = true;
    if (!authorized && authHeader.startsWith("Bearer ")) {
      const token = authHeader.replace("Bearer ", "");
      if (token === supabaseServiceKey || isServiceRoleJWT(token)) {
        authorized = true;
      }
    }
    if (!authorized) {
      return new Response(
        JSON.stringify({ error: "Unauthorized", code: "E_AUTH" }),
        {
          status: 401,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    let body: RequestBody = {};
    if (req.method === "POST") {
      try {
        body = (await req.json()) as RequestBody;
      } catch {
        body = {};
      }
    }

    const userIds = await pickActiveStravaUsers(
      supabase,
      body.source === "manual" ? body.userId : undefined,
    );

    if (!userIds.length) {
      return new Response(
        JSON.stringify({
          ok: true,
          source: body.source ?? "cron",
          usersProcessed: 0,
          insightsWritten: 0,
        }),
        {
          status: 200,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    let totalWritten = 0;
    let errorsCount = 0;
    for (const uid of userIds) {
      try {
        const insights = await computeUserInsights(supabase, uid);
        if (insights.length === 0) continue;

        const { error } = await supabase
          .from("user_personalized_insights")
          .upsert(insights, { onConflict: "user_id,insight_key" });
        if (error) {
          errorsCount++;
          console.warn(
            `[strava-insights] upsert failed for ${uid}:`,
            error.message,
          );
          continue;
        }
        totalWritten += insights.length;
      } catch (e) {
        errorsCount++;
        console.warn(
          `[strava-insights] compute failed for ${uid}:`,
          (e as Error).message,
        );
      }
    }

    return new Response(
      JSON.stringify({
        ok: true,
        source: body.source ?? "cron",
        usersProcessed: userIds.length,
        insightsWritten: totalWritten,
        errors: errorsCount,
      }),
      {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  } catch (e) {
    console.error("[strava-insights] fatal:", e);
    return new Response(
      JSON.stringify({
        error: (e as Error).message,
        code: "E_UNHANDLED",
      }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});
