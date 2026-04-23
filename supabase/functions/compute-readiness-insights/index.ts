// Supabase Edge Function: compute-readiness-insights
// -----------------------------------------------------------------------------
// Wearable Personalization Platform — Phase 2a
//
// Nightly worker that computes correlation-backed insights from each
// active user's last 60 days of wearable + workout + nutrition data,
// writes them to `user_personalized_insights` with upserts, and
// surfaces the highest-priority one to the Dashboard Smart Welcome
// card via `v_user_wearable_insights`.
//
// Correlations computed per user (wearable-agnostic — reads the
// unified `daily_readiness_history` table):
//
//   1. sleep_hours_vs_pr_rate       Sleep ≥ 7h predicts PR success?
//   2. hrv_delta_vs_pr_success      HRV above baseline predicts PRs?
//   3. readiness_band_vs_adherence  Green days → more workouts?
//   4. strain_avg_vs_rhr_trend      Overtraining early-warning.
//   5. protein_x_sleep_vs_recovery  Compound recovery factor.
//
// Stats method: Spearman rank correlation (tolerates non-linear
// monotonic relationships better than Pearson for fitness data where
// responses saturate). Significance via approximate z-test with
// Fisher transform — good enough for n >= 10.
//
// Users selected: anyone with ≥ 10 readiness-history rows AND ≥ 1
// workout in the last 60 days. Everyone else gets NO rows written so
// the Dashboard shows the legacy rule-based insight fallback.
//
// Invocation:
//   - `{source: "cron"}` from pg_cron at 03:30 UTC nightly.
//   - `{source: "manual", userId}` from admin CMS for a single user.
//
// Auth: service_role via `x-cron-key` header OR direct service-role
// bearer. No user-facing invocation path.
//
// Deploy: `supabase functions deploy compute-readiness-insights`
// -----------------------------------------------------------------------------

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { buildCorsHeaders } from "../_shared/cors.ts";

// ── Config ────────────────────────────────────────────────────────────────
const LOOKBACK_DAYS = 60;
const MIN_SAMPLE_SIZE = 10;
const MIN_WORKOUTS_LAST_60D = 1;
const P_VALUE_THRESHOLD = 0.15;
// Hard cap on user-count per invocation to avoid cron-run blow-ups.
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
  userId?: string; // only honored for `source: "manual"`
}

interface ReadinessRow {
  user_id: string;
  date: string;
  score: number;
  band: "red" | "yellow" | "green";
  hrv_delta_pct: number | null;
  sleep_hours: number | null;
  rhr_trend_bpm: number | null;
  strain_prev: number | null;
}

interface WorkoutRow {
  user_id: string;
  completed_at: string;
  // Pre-aggregated PR flag written by `exercise_personal_records` upsert trigger,
  // or client-side flag on the workout itself. We approximate "PR day" as
  // "any PR row was created on this workout's day for this user".
}

interface MealRow {
  user_id: string;
  date: string;
  protein: number | null;
}

// Mirrors `public.user_personalized_insights` column names. Enum
// values must stay in sync with `PersonalizedInsightsService.swift`
// InsightType / InsightCategory (we use `correlation` as the type
// tag and `recovery` as the category, since wearable signals feed
// the recovery story). `priority` uses the InsightPriority.medium=5
// / high=8 convention.
interface InsightUpsert {
  user_id: string;
  insight_key: string;
  insight_type: string;       // InsightType enum (correlation/trend/warning/tip)
  insight_category: string;   // InsightCategory enum (recovery/workout/sleep/nutrition)
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

// ── Spearman rank correlation ────────────────────────────────────────────
function rank(values: number[]): number[] {
  const sorted = values
    .map((v, i) => ({ v, i }))
    .sort((a, b) => a.v - b.v);
  const ranks = new Array(values.length).fill(0);
  // Average ties.
  let i = 0;
  while (i < sorted.length) {
    let j = i;
    while (j + 1 < sorted.length && sorted[j + 1].v === sorted[i].v) j++;
    const avgRank = (i + j) / 2 + 1; // 1-indexed
    for (let k = i; k <= j; k++) {
      ranks[sorted[k].i] = avgRank;
    }
    i = j + 1;
  }
  return ranks;
}

function pearson(x: number[], y: number[]): number {
  const n = x.length;
  if (n < 2) return 0;
  const mx = x.reduce((a, b) => a + b, 0) / n;
  const my = y.reduce((a, b) => a + b, 0) / n;
  let num = 0, dx = 0, dy = 0;
  for (let i = 0; i < n; i++) {
    const xi = x[i] - mx;
    const yi = y[i] - my;
    num += xi * yi;
    dx += xi * xi;
    dy += yi * yi;
  }
  const denom = Math.sqrt(dx * dy);
  return denom === 0 ? 0 : num / denom;
}

function spearman(x: number[], y: number[]): number {
  if (x.length !== y.length || x.length < 2) return 0;
  return pearson(rank(x), rank(y));
}

// Fisher Z transform → two-tailed approx p-value.
function pValueForCorrelation(r: number, n: number): number {
  if (n < 4 || Math.abs(r) >= 0.9999) return 1;
  const z = 0.5 * Math.log((1 + r) / (1 - r)); // Fisher z
  const se = 1 / Math.sqrt(n - 3);
  const zStat = Math.abs(z / se);
  // Two-tailed p from standard normal.
  return 2 * (1 - normalCdf(zStat));
}

function normalCdf(z: number): number {
  // Abramowitz & Stegun 26.2.17 — adequate precision for our gate.
  const b1 = 0.319381530;
  const b2 = -0.356563782;
  const b3 = 1.781477937;
  const b4 = -1.821255978;
  const b5 = 1.330274429;
  const p = 0.2316419;
  const c = 0.39894228;
  if (z < 0) return 1 - normalCdf(-z);
  const t = 1 / (1 + p * z);
  const n =
    c *
    Math.exp((-z * z) / 2) *
    (t * (b1 + t * (b2 + t * (b3 + t * (b4 + t * b5)))));
  return 1 - n;
}

// ── User selection ───────────────────────────────────────────────────────
// deno-lint-ignore no-explicit-any
async function pickActiveUsers(supabase: any, manualUserId?: string): Promise<string[]> {
  if (manualUserId) return [manualUserId];

  const since = new Date();
  since.setDate(since.getDate() - LOOKBACK_DAYS);
  const sinceStr = since.toISOString().slice(0, 10);

  // Users with at least one readiness row AND one workout in the window.
  // Two queries + intersect — avoids a complex join.
  const { data: readinessUsers } = await supabase
    .from("daily_readiness_history")
    .select("user_id")
    .gte("date", sinceStr);

  if (!readinessUsers?.length) return [];

  const readinessSet = new Set<string>(
    readinessUsers.map((r: { user_id: string }) => r.user_id),
  );

  const { data: workoutUsers } = await supabase
    .from("workouts")
    .select("user_id")
    .gte("date", sinceStr);

  const workoutSet = new Set<string>(
    (workoutUsers ?? []).map((r: { user_id: string }) => r.user_id),
  );

  const active: string[] = [];
  for (const uid of readinessSet) {
    if (workoutSet.has(uid)) active.push(uid);
  }
  return active.slice(0, MAX_USERS_PER_RUN);
}

// ── Correlations per user ────────────────────────────────────────────────
async function computeUserInsights(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  userId: string,
): Promise<InsightUpsert[]> {
  const since = new Date();
  since.setDate(since.getDate() - LOOKBACK_DAYS);
  const sinceStr = since.toISOString().slice(0, 10);

  const [readinessRes, workoutsRes, mealsRes, prsRes] = await Promise.all([
    supabase
      .from("daily_readiness_history")
      .select(
        "user_id, date, score, band, hrv_delta_pct, sleep_hours, rhr_trend_bpm, strain_prev",
      )
      .eq("user_id", userId)
      .gte("date", sinceStr)
      .order("date", { ascending: true }),
    supabase
      .from("workouts")
      .select("user_id, date")
      .eq("user_id", userId)
      .gte("date", sinceStr),
    supabase
      .from("meal_logs")
      .select("user_id, date, protein")
      .eq("user_id", userId)
      .gte("date", sinceStr),
    supabase
      .from("exercise_personal_records")
      .select("user_id, created_at")
      .eq("user_id", userId)
      .gte("created_at", since.toISOString()),
  ]);

  const readinessRows: ReadinessRow[] = readinessRes.data ?? [];
  if (readinessRows.length < MIN_SAMPLE_SIZE) return [];

  const workoutDays = new Set<string>(
    (workoutsRes.data ?? []).map((r: { date: string }) => r.date?.slice(0, 10)).filter(Boolean),
  );
  const prDays = new Set<string>(
    (prsRes.data ?? [])
      .map((r: { created_at: string }) => r.created_at?.slice(0, 10))
      .filter(Boolean),
  );

  // Aggregate protein per day.
  const proteinByDay: Record<string, number> = {};
  for (const m of (mealsRes.data ?? []) as MealRow[]) {
    if (!m.date) continue;
    const d = m.date.slice(0, 10);
    proteinByDay[d] = (proteinByDay[d] ?? 0) + (m.protein ?? 0);
  }

  const insights: InsightUpsert[] = [];

  // ── Correlation 1: sleep_hours → PR rate (next day) ────────────────
  {
    const xs: number[] = [], ys: number[] = [];
    for (const r of readinessRows) {
      if (r.sleep_hours == null) continue;
      const next = addDaysStr(r.date, 1);
      const yFlag = prDays.has(next) ? 1 : 0;
      xs.push(r.sleep_hours);
      ys.push(yFlag);
    }
    pushCorrelation(
      insights,
      userId,
      xs,
      ys,
      {
        key: "insight_sleep_pr",
        correlationType: "sleep_hours_vs_pr_rate",
        positiveTitle: "Sleep 7h+ → your PR days",
        positiveMessage:
          "When you sleep 7+ hours, you hit personal records significantly more often. Tonight, aim for at least 7h.",
        negativeMessage: null,
        category: "sleep",
        icon: "bed.double.fill",
      },
    );
  }

  // ── Correlation 2: HRV delta → PR success same day ────────────────
  {
    const xs: number[] = [], ys: number[] = [];
    for (const r of readinessRows) {
      if (r.hrv_delta_pct == null) continue;
      const yFlag = prDays.has(r.date) ? 1 : 0;
      xs.push(r.hrv_delta_pct);
      ys.push(yFlag);
    }
    pushCorrelation(
      insights,
      userId,
      xs,
      ys,
      {
        key: "insight_hrv_pr",
        correlationType: "hrv_delta_vs_pr_success",
        positiveTitle: "HRV predicts your PRs",
        positiveMessage:
          "Your PRs cluster on days when HRV is above your baseline. Check your HRV in the morning — it's a strong green light.",
        negativeMessage: null,
        category: "recovery",
        icon: "waveform.path.ecg",
      },
    );
  }

  // ── Correlation 3: readiness band → workout-attendance ────────────
  {
    const xs: number[] = [], ys: number[] = [];
    for (const r of readinessRows) {
      const score = r.band === "green" ? 2 : r.band === "yellow" ? 1 : 0;
      const didWorkout = workoutDays.has(r.date) ? 1 : 0;
      xs.push(score);
      ys.push(didWorkout);
    }
    pushCorrelation(
      insights,
      userId,
      xs,
      ys,
      {
        key: "insight_readiness_adherence",
        correlationType: "readiness_band_vs_adherence",
        positiveTitle: "Green days = training days",
        positiveMessage:
          "You train far more consistently on green days. When red, shift to mobility — don't skip.",
        negativeMessage:
          "You train hardest on red days — your body may be crying for a real recovery cycle. Try swapping 1 red day / week to mobility.",
        category: "workout",
        icon: "heart.text.square.fill",
      },
    );
  }

  // ── Correlation 4: strain avg (3d) → RHR trend (overtraining) ─────
  {
    const strains = readinessRows.map((r) => r.strain_prev ?? 0);
    const rhrs = readinessRows.map((r) => r.rhr_trend_bpm ?? 0);
    if (strains.length >= MIN_SAMPLE_SIZE) {
      // Rolling 3-day strain avg shifted vs same-day RHR trend.
      const rollStrain: number[] = [];
      const rhrOut: number[] = [];
      for (let i = 2; i < strains.length; i++) {
        const avg = (strains[i] + strains[i - 1] + strains[i - 2]) / 3;
        if (avg === 0) continue;
        rollStrain.push(avg);
        rhrOut.push(rhrs[i]);
      }
      pushCorrelation(
        insights,
        userId,
        rollStrain,
        rhrOut,
        {
          key: "insight_strain_rhr",
          correlationType: "strain_avg_vs_rhr_trend",
          positiveTitle: "Strain is creeping into your RHR",
          positiveMessage:
            "Higher 3-day strain is lifting your resting HR — classic overtraining signal. Consider a deload next week.",
          negativeMessage: null,
          category: "recovery",
          icon: "exclamationmark.triangle.fill",
          priorityOk: 8,
        },
      );
    }
  }

  // ── Correlation 5: protein × sleep → readiness recovery speed ─────
  {
    // "Recovery speed" ≈ how quickly the band climbs after a red day.
    // Score change from day T-1 to T, scored against protein × sleep on T-1.
    const xs: number[] = [], ys: number[] = [];
    for (let i = 1; i < readinessRows.length; i++) {
      const prev = readinessRows[i - 1];
      const today = readinessRows[i];
      if (prev.sleep_hours == null) continue;
      const protein = proteinByDay[prev.date] ?? 0;
      if (protein === 0) continue;
      const factor = protein * prev.sleep_hours;
      const delta = today.score - prev.score;
      xs.push(factor);
      ys.push(delta);
    }
    pushCorrelation(
      insights,
      userId,
      xs,
      ys,
      {
        key: "insight_protein_sleep_recovery",
        correlationType: "protein_x_sleep_vs_recovery",
        positiveTitle: "Protein + sleep fuel your bounce-back",
        positiveMessage:
          "Your readiness climbs faster on days after high-protein meals + long sleep. Stack both for the fastest recovery.",
        negativeMessage: null,
        category: "nutrition",
        icon: "leaf.fill",
      },
    );
  }

  return insights;
}

// Helper: push a correlation insight if sample + significance gates pass.
function pushCorrelation(
  out: InsightUpsert[],
  userId: string,
  xs: number[],
  ys: number[],
  opts: {
    key: string;
    correlationType: string;
    positiveTitle: string;
    positiveMessage: string;
    negativeMessage: string | null;
    category?: string;     // InsightCategory enum (default: recovery)
    icon?: string;         // SF Symbol name
    priorityWarn?: number; // priority when negative message fires
    priorityOk?: number;   // priority when positive message fires
  },
) {
  const n = xs.length;
  if (n < MIN_SAMPLE_SIZE) return;
  const r = spearman(xs, ys);
  const p = pValueForCorrelation(r, n);
  if (!Number.isFinite(r) || p > P_VALUE_THRESHOLD) return;

  // Only write if the effect has a direction we care about.
  let title = opts.positiveTitle;
  let message = opts.positiveMessage;
  let priority = opts.priorityOk ?? 5;
  if (r < -0.2 && opts.negativeMessage) {
    message = opts.negativeMessage;
    priority = opts.priorityWarn ?? 8;
  } else if (r > 0.2) {
    // positive direction — keep positive copy
  } else {
    return; // correlation too weak to surface
  }

  out.push({
    user_id: userId,
    insight_key: opts.key,
    insight_type: "correlation",
    insight_category: opts.category ?? "recovery",
    title,
    message,
    detail_message: null,
    priority,
    icon: opts.icon ?? "heart.text.square.fill",
    accent_color: "green",
    correlation_type: opts.correlationType,
    r_squared: Math.round(r * r * 1000) / 1000,
    p_value: Math.round(p * 1000) / 1000,
    sample_size: n,
    wearable_source: "derived",
  });
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

    // ── Auth: cron key OR direct service role ────────────────────────
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

    // ── Parse body ───────────────────────────────────────────────────
    let body: RequestBody = {};
    if (req.method === "POST") {
      try {
        body = (await req.json()) as RequestBody;
      } catch {
        body = {};
      }
    }

    // Manual single-user runs accept a userId; cron ignores.
    const userIds = await pickActiveUsers(
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
          console.warn(`[readiness-insights] upsert failed for ${uid}:`, error.message);
          continue;
        }
        totalWritten += insights.length;
      } catch (e) {
        errorsCount++;
        console.warn(
          `[readiness-insights] compute failed for ${uid}:`,
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
    console.error("[readiness-insights] fatal:", e);
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
