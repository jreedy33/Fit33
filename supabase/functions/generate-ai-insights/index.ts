// ============================================================================
// AI INSIGHTS GENERATOR - Supabase Edge Function
// ============================================================================
// Queries platform analytics data and sends to Claude for product insights.
//
// Deploy: supabase functions deploy generate-ai-insights
// Secrets: supabase secrets set ANTHROPIC_API_KEY=sk-ant-...
// ============================================================================

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const ANTHROPIC_API_KEY = Deno.env.get("ANTHROPIC_API_KEY");
const ANTHROPIC_API_URL = "https://api.anthropic.com/v1/messages";
const MODEL = "claude-sonnet-4-20250514";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

function getSupabase() {
  return createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? ""
  );
}

// ═══════════════════════════════════════════════════
// DATA COLLECTION QUERIES
// ═══════════════════════════════════════════════════

async function safeQuery<T>(fn: () => Promise<{ data: T | null; error: unknown }>): Promise<T | null> {
  try {
    const { data } = await fn();
    return data;
  } catch {
    return null;
  }
}

async function safeCount(fn: () => Promise<{ count: number | null; error: unknown }>): Promise<number> {
  try {
    const { count } = await fn();
    return count ?? 0;
  } catch {
    return 0;
  }
}

async function collectPlatformData(supabase: ReturnType<typeof createClient>) {
  const now = new Date();
  const d7 = new Date(now.getTime() - 7 * 86400000).toISOString();
  const d14 = new Date(now.getTime() - 14 * 86400000).toISOString();
  const d30 = new Date(now.getTime() - 30 * 86400000).toISOString();
  const d90 = new Date(now.getTime() - 90 * 86400000).toISOString();

  const results: Record<string, unknown> = {};

  // ── Users & Demographics ──
  const [totalUsers, newUsers7d, newUsers30d, activeUsers7d, activeUsers30d] = await Promise.all([
    safeCount(() => supabase.from("user_profiles").select("id", { count: "exact", head: true })),
    safeCount(() => supabase.from("user_profiles").select("id", { count: "exact", head: true }).gte("created_at", d7)),
    safeCount(() => supabase.from("user_profiles").select("id", { count: "exact", head: true }).gte("created_at", d30)),
    safeCount(() => supabase.from("user_profiles").select("id", { count: "exact", head: true }).gte("last_workout_date", d7)),
    safeCount(() => supabase.from("user_profiles").select("id", { count: "exact", head: true }).gte("last_workout_date", d30)),
  ]);

  results.users = { total: totalUsers, new_7d: newUsers7d, new_30d: newUsers30d, active_7d: activeUsers7d, active_30d: activeUsers30d };

  const profiles = await safeQuery(() =>
    supabase.from("user_profiles")
      .select("fitness_goal, experience_level, gender, age, workout_environment, has_completed_onboarding, current_streak, longest_streak, total_workouts, xp, created_at, last_workout_date")
  );

  if (profiles && Array.isArray(profiles)) {
    const goals: Record<string, number> = {};
    const levels: Record<string, number> = {};
    const genders: Record<string, number> = {};
    let onboarded = 0;
    let totalXp = 0;
    let totalWorkoutsSum = 0;
    const activeProfiles = (profiles as Array<Record<string, unknown>>).filter((p) => ((p.total_workouts as number) || 0) > 0);

    for (const p of profiles as Array<Record<string, unknown>>) {
      if (p.fitness_goal) goals[p.fitness_goal as string] = (goals[p.fitness_goal as string] || 0) + 1;
      if (p.experience_level) levels[p.experience_level as string] = (levels[p.experience_level as string] || 0) + 1;
      if (p.gender) genders[p.gender as string] = (genders[p.gender as string] || 0) + 1;
      if (p.has_completed_onboarding) onboarded++;
      totalXp += (p.xp as number) || 0;
      totalWorkoutsSum += (p.total_workouts as number) || 0;
    }

    results.demographics = { fitness_goals: goals, experience_levels: levels, genders, onboarding_completion_rate: profiles.length > 0 ? Math.round((onboarded / profiles.length) * 100) : 0 };
    results.user_engagement = {
      users_with_workouts: activeProfiles.length,
      total_workouts_all_users: totalWorkoutsSum,
      avg_workouts_per_active_user: activeProfiles.length > 0 ? Math.round(totalWorkoutsSum / activeProfiles.length * 10) / 10 : 0,
      avg_current_streak: activeProfiles.length > 0 ? Math.round(activeProfiles.reduce((a, b) => a + ((b.current_streak as number) || 0), 0) / activeProfiles.length * 10) / 10 : 0,
      best_streak_ever: activeProfiles.length > 0 ? Math.max(...activeProfiles.map((p) => (p.longest_streak as number) || 0)) : 0,
      total_platform_xp: totalXp,
    };
  }

  // ── Workouts ──
  const [totalWorkouts, workouts7d, workouts30d] = await Promise.all([
    safeCount(() => supabase.from("workouts").select("id", { count: "exact", head: true })),
    safeCount(() => supabase.from("workouts").select("id", { count: "exact", head: true }).gte("created_at", d7)),
    safeCount(() => supabase.from("workouts").select("id", { count: "exact", head: true }).gte("created_at", d30)),
  ]);

  results.workouts = { total: totalWorkouts, last_7d: workouts7d, last_30d: workouts30d };

  const recentWorkouts = await safeQuery(() =>
    supabase.from("workouts")
      .select("date, duration_seconds, xp_earned, user_id, name")
      .order("date", { ascending: false })
      .limit(200)
  );

  if (recentWorkouts && Array.isArray(recentWorkouts)) {
    const avgDuration = recentWorkouts.length > 0
      ? Math.round(recentWorkouts.reduce((a, b) => a + ((b as Record<string, unknown>).duration_seconds as number || 0), 0) / recentWorkouts.length / 60)
      : 0;
    const uniqueUsers = new Set(recentWorkouts.map((w) => (w as Record<string, unknown>).user_id)).size;
    results.workout_details = { avg_duration_minutes: avgDuration, unique_users_recent_200: uniqueUsers };
  }

  // ── Exercise Performance ──
  const exercisePerf = await safeQuery(() =>
    supabase.from("exercise_performance_history")
      .select("exercise_name, exercise_category, user_id, workout_date, total_volume, max_weight, total_sets, total_reps")
      .order("workout_date", { ascending: false })
      .limit(500)
  );

  if (exercisePerf && Array.isArray(exercisePerf)) {
    const exCounts: Record<string, number> = {};
    const catCounts: Record<string, number> = {};
    for (const e of exercisePerf as Array<Record<string, unknown>>) {
      if (e.exercise_name) exCounts[e.exercise_name as string] = (exCounts[e.exercise_name as string] || 0) + 1;
      if (e.exercise_category) catCounts[e.exercise_category as string] = (catCounts[e.exercise_category as string] || 0) + 1;
    }
    results.popular_exercises = Object.entries(exCounts).sort((a, b) => b[1] - a[1]).slice(0, 25).map(([name, count]) => ({ name, count }));
    results.muscle_group_distribution = Object.entries(catCounts).sort((a, b) => b[1] - a[1]).map(([category, count]) => ({ category, count }));
  }

  // ── Challenges ──
  const challenges = await safeQuery(() =>
    supabase.from("group_challenges")
      .select("id, challenge_type, mode, status, duration_days, created_at")
      .order("created_at", { ascending: false })
      .limit(100)
  );

  const challengeParticipants = await safeQuery(() =>
    supabase.from("challenge_participants")
      .select("challenge_id, status")
      .limit(500)
  );

  if (challenges && Array.isArray(challenges)) {
    const statusCounts: Record<string, number> = {};
    const typeCounts: Record<string, number> = {};
    for (const c of challenges as Array<Record<string, unknown>>) {
      statusCounts[c.status as string] = (statusCounts[c.status as string] || 0) + 1;
      typeCounts[c.challenge_type as string] = (typeCounts[c.challenge_type as string] || 0) + 1;
    }
    results.challenges = { total: challenges.length, by_status: statusCounts, by_type: typeCounts, total_participants: challengeParticipants ? (challengeParticipants as unknown[]).length : 0 };
  }

  // ── Social ──
  const friendships = await safeQuery(() =>
    supabase.from("friendships")
      .select("status, created_at")
      .order("created_at", { ascending: false })
      .limit(500)
  );

  if (friendships && Array.isArray(friendships)) {
    const fStatusCounts: Record<string, number> = {};
    let recent30d = 0;
    for (const f of friendships as Array<Record<string, unknown>>) {
      fStatusCounts[f.status as string] = (fStatusCounts[f.status as string] || 0) + 1;
      if (f.created_at && (f.created_at as string) >= d30) recent30d++;
    }
    results.social = { total_friendships: friendships.length, by_status: fStatusCounts, new_last_30d: recent30d };
  }

  const [sharedWorkoutsCount, sharedWorkouts30d] = await Promise.all([
    safeCount(() => supabase.from("shared_workouts").select("id", { count: "exact", head: true })),
    safeCount(() => supabase.from("shared_workouts").select("id", { count: "exact", head: true }).gte("created_at", d30)),
  ]);
  results.shared_workouts = { total: sharedWorkoutsCount, last_30d: sharedWorkouts30d };

  // ── Nutrition ──
  const meals = await safeQuery(() =>
    supabase.from("meal_logs")
      .select("meal_type, calories, protein, carbs, fat, date")
      .order("date", { ascending: false })
      .limit(300)
  );

  if (meals && Array.isArray(meals)) {
    const mealTypes: Record<string, number> = {};
    let totalCal = 0;
    for (const m of meals as Array<Record<string, unknown>>) {
      if (m.meal_type) mealTypes[m.meal_type as string] = (mealTypes[m.meal_type as string] || 0) + 1;
      totalCal += (m.calories as number) || 0;
    }
    results.nutrition = { total_meals_logged: meals.length, by_meal_type: mealTypes, avg_calories: meals.length > 0 ? Math.round(totalCal / meals.length) : 0 };
  }

  // ── Programs ──
  const [activePrograms, programHistory] = await Promise.all([
    safeQuery(() => supabase.from("user_active_programs").select("program_id, status, current_day, completed_days, total_workouts_completed").limit(200)),
    safeQuery(() => supabase.from("program_history").select("program_name, status, days_completed, total_workouts, completion_percentage").order("start_date", { ascending: false }).limit(100)),
  ]);

  if (activePrograms && Array.isArray(activePrograms)) {
    results.programs = {
      active_enrollments: activePrograms.length,
      history: programHistory ? (programHistory as unknown[]).length : 0,
    };
  }

  // ── Health (steps, weight, cardio) ──
  const [stepsData, weightData, cardioData] = await Promise.all([
    safeQuery(() => supabase.from("step_tracking").select("steps, date, user_id").gte("date", d30).order("date", { ascending: false }).limit(300)),
    safeQuery(() => supabase.from("weight_logs").select("weight_lbs, date, user_id").order("date", { ascending: false }).limit(200)),
    safeQuery(() => supabase.from("cardio_workouts").select("activity_type, duration_seconds, distance_meters, calories_burned, source").gte("date", d30).limit(200)),
  ]);

  if (stepsData && Array.isArray(stepsData) && stepsData.length > 0) {
    const avgSteps = Math.round(stepsData.reduce((a, s) => a + ((s as Record<string, unknown>).steps as number || 0), 0) / stepsData.length);
    const stepUsers = new Set(stepsData.map((s) => (s as Record<string, unknown>).user_id)).size;
    results.health_steps = { entries_30d: stepsData.length, avg_steps_per_entry: avgSteps, unique_users: stepUsers };
  }

  if (cardioData && Array.isArray(cardioData) && cardioData.length > 0) {
    const activityTypes: Record<string, number> = {};
    for (const c of cardioData as Array<Record<string, unknown>>) {
      if (c.activity_type) activityTypes[c.activity_type as string] = (activityTypes[c.activity_type as string] || 0) + 1;
    }
    results.cardio = { sessions_30d: cardioData.length, by_activity: activityTypes };
  }

  // ── Onboarding ──
  const onboardingData = await safeQuery(() =>
    supabase.from("onboarding_analytics").select("step_name, completed, drop_off").gte("created_at", d90)
  );

  if (onboardingData && Array.isArray(onboardingData) && onboardingData.length > 0) {
    const stepStats: Record<string, { total: number; completed: number; dropped: number }> = {};
    for (const row of onboardingData as Array<Record<string, unknown>>) {
      const step = row.step_name as string;
      if (!stepStats[step]) stepStats[step] = { total: 0, completed: 0, dropped: 0 };
      stepStats[step].total++;
      if (row.completed) stepStats[step].completed++;
      if (row.drop_off) stepStats[step].dropped++;
    }
    results.onboarding = stepStats;
  }

  // ── Retention ──
  try {
    const [activeThisWeek, activeLastWeek] = await Promise.all([
      supabase.from("workouts").select("user_id").gte("created_at", d7),
      supabase.from("workouts").select("user_id").gte("created_at", d14).lt("created_at", d7),
    ]);
    const w1 = new Set((activeThisWeek.data || []).map((r: { user_id: string }) => r.user_id));
    const w2 = new Set((activeLastWeek.data || []).map((r: { user_id: string }) => r.user_id));
    const retained = [...w2].filter(id => w1.has(id));
    results.retention = {
      active_this_week: w1.size, active_last_week: w2.size, retained_both_weeks: retained.length,
      retention_rate_pct: w2.size > 0 ? Math.round((retained.length / w2.size) * 100) : null,
    };
  } catch { results.retention = null; }

  // ── Streaks & XP Leaderboard ──
  const topUsers = await safeQuery(() =>
    supabase.from("user_profiles")
      .select("name, username, current_streak, longest_streak, total_workouts, xp, last_workout_date")
      .order("xp", { ascending: false })
      .limit(10)
  );
  if (topUsers) results.top_users_by_xp = topUsers;

  // ── Bug & Crash Reports ──
  const [bugCount, crashCount] = await Promise.all([
    safeCount(() => supabase.from("bug_reports").select("id", { count: "exact", head: true }).eq("status", "open")),
    safeCount(() => supabase.from("crash_reports").select("id", { count: "exact", head: true }).eq("status", "new")),
  ]);
  results.open_issues = { open_bugs: bugCount, new_crashes: crashCount };

  return results;
}

// ═══════════════════════════════════════════════════
// CLAUDE API CALL
// ═══════════════════════════════════════════════════

async function generateInsightsWithClaude(dataSnapshot: Record<string, unknown>) {
  if (!ANTHROPIC_API_KEY) {
    throw new Error("ANTHROPIC_API_KEY not set. Run: supabase secrets set ANTHROPIC_API_KEY=sk-ant-...");
  }

  const systemPrompt = `You are a senior product analyst for Fit33, a premium iOS fitness app. Your job is to analyze platform data and produce actionable insights for the product team.

For each insight you generate, provide:
- A clear, specific title (not generic)
- A detailed body explaining the finding, why it matters, and what action to take
- A category: retention, exercises, onboarding, engagement, workouts, social, or general
- A priority: high (needs immediate attention), medium (should address this sprint), low (nice to know)
- An insight_type: weekly_summary (broad overview), trend_alert (something changed significantly), or recommendation (specific action to take)

Focus on:
1. Anomalies and significant changes from expected patterns
2. User behavior that suggests friction or delight
3. Specific, actionable recommendations (not vague "improve retention")
4. Connecting data points to tell a story

Return ONLY valid JSON in this exact format:
{
  "insights": [
    {
      "title": "...",
      "body": "...",
      "category": "...",
      "priority": "high|medium|low",
      "insight_type": "weekly_summary|trend_alert|recommendation"
    }
  ]
}

Generate 4-8 insights. Be specific and data-driven.`;

  const response = await fetch(ANTHROPIC_API_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-api-key": ANTHROPIC_API_KEY,
      "anthropic-version": "2023-06-01",
    },
    body: JSON.stringify({
      model: MODEL,
      max_tokens: 4096,
      system: systemPrompt,
      messages: [
        {
          role: "user",
          content: `Here is the current Fit33 platform data snapshot (collected ${new Date().toISOString()}):\n\n${JSON.stringify(dataSnapshot, null, 2)}\n\nAnalyze this data and generate product insights.`,
        },
      ],
    }),
  });

  if (!response.ok) {
    const errBody = await response.text();
    throw new Error(`Anthropic API error ${response.status}: ${errBody}`);
  }

  const result = await response.json();
  const content = result.content?.[0]?.text;
  if (!content) throw new Error("Empty response from Claude");

  const jsonMatch = content.match(/\{[\s\S]*\}/);
  if (!jsonMatch) throw new Error("Could not parse JSON from Claude response");

  return JSON.parse(jsonMatch[0]);
}

// ═══════════════════════════════════════════════════
// STORE INSIGHTS
// ═══════════════════════════════════════════════════

async function storeInsights(
  supabase: ReturnType<typeof createClient>,
  insights: Array<{
    title: string;
    body: string;
    category: string;
    priority: string;
    insight_type: string;
  }>,
  dataSnapshot: Record<string, unknown>
) {
  const rows = insights.map((insight) => ({
    insight_type: insight.insight_type,
    category: insight.category,
    title: insight.title,
    body: insight.body,
    priority: insight.priority,
    data_snapshot: dataSnapshot,
    model_used: MODEL,
    status: "new",
  }));

  const { error } = await supabase.from("ai_insights").insert(rows);
  if (error) throw new Error(`Failed to store insights: ${error.message}`);

  return rows.length;
}

// ═══════════════════════════════════════════════════
// MAIN HANDLER
// ═══════════════════════════════════════════════════

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const { action, ...params } = await req.json();
    const supabase = getSupabase();

    switch (action) {
      case "generate_weekly": {
        const dataSnapshot = await collectPlatformData(supabase);
        const result = await generateInsightsWithClaude(dataSnapshot);
        const count = await storeInsights(supabase, result.insights, dataSnapshot);

        return new Response(
          JSON.stringify({ success: true, insights_generated: count }),
          { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 200 }
        );
      }

      case "generate_single": {
        const category = params.category || "general";
        const dataSnapshot = await collectPlatformData(supabase);
        const result = await generateInsightsWithClaude(dataSnapshot);
        const filtered = result.insights.filter(
          (i: { category: string }) => i.category === category
        );
        const toStore = filtered.length > 0 ? filtered : result.insights.slice(0, 2);
        const count = await storeInsights(supabase, toStore, dataSnapshot);

        return new Response(
          JSON.stringify({ success: true, insights_generated: count }),
          { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 200 }
        );
      }

      case "get_data_context": {
        const dataSnapshot = await collectPlatformData(supabase);
        return new Response(
          JSON.stringify(dataSnapshot),
          { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 200 }
        );
      }

      default:
        return new Response(
          JSON.stringify({ error: `Unknown action: ${action}` }),
          { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 400 }
        );
    }
  } catch (err) {
    const message = err instanceof Error ? err.message : "Unknown error";
    console.error("[generate-ai-insights] Error:", message);
    return new Response(
      JSON.stringify({ error: message }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 500 }
    );
  }
});
