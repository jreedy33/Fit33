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

  // deno-lint-ignore no-explicit-any
  type R = Record<string, any>;
  const r: Record<string, unknown> = {};

  // Helper to aggregate a field into counts
  function countBy(rows: R[], field: string): Record<string, number> {
    const c: Record<string, number> = {};
    for (const row of rows) { if (row[field]) c[row[field]] = (c[row[field]] || 0) + 1; }
    return c;
  }

  // ══════════════════════════════════════════════════════════
  // 1. USER PROFILES (all columns)
  // ══════════════════════════════════════════════════════════
  const profiles = (await safeQuery(() => supabase.from("user_profiles")
    .select("id, name, username, email, gender, age, fitness_goal, experience_level, strength_level, workout_environment, equipment, available_days, current_streak, longest_streak, total_workouts, xp, has_completed_onboarding, created_at, last_workout_date, weight_unit, height_unit, daily_calorie_goal, daily_protein_goal")) || []) as R[];

  const active = profiles.filter(p => (p.total_workouts || 0) > 0);
  r.users = {
    total: profiles.length,
    new_7d: profiles.filter(p => p.created_at >= d7).length,
    new_30d: profiles.filter(p => p.created_at >= d30).length,
    active_7d: profiles.filter(p => p.last_workout_date && p.last_workout_date >= d7).length,
    active_30d: profiles.filter(p => p.last_workout_date && p.last_workout_date >= d30).length,
    onboarded: profiles.filter(p => p.has_completed_onboarding).length,
    onboarding_rate_pct: profiles.length > 0 ? Math.round(profiles.filter(p => p.has_completed_onboarding).length / profiles.length * 100) : 0,
  };
  r.demographics = {
    fitness_goals: countBy(profiles, "fitness_goal"),
    experience_levels: countBy(profiles, "experience_level"),
    genders: countBy(profiles, "gender"),
    workout_environments: countBy(profiles, "workout_environment"),
    strength_levels: countBy(profiles, "strength_level"),
    weight_units: countBy(profiles, "weight_unit"),
  };
  r.engagement = {
    users_with_workouts: active.length,
    total_workouts_all_users: active.reduce((a, p) => a + (p.total_workouts || 0), 0),
    avg_workouts_per_active_user: active.length > 0 ? Math.round(active.reduce((a, p) => a + (p.total_workouts || 0), 0) / active.length * 10) / 10 : 0,
    avg_current_streak: active.length > 0 ? Math.round(active.reduce((a, p) => a + (p.current_streak || 0), 0) / active.length * 10) / 10 : 0,
    best_streak_ever: active.length > 0 ? Math.max(...active.map(p => p.longest_streak || 0)) : 0,
    total_platform_xp: profiles.reduce((a, p) => a + (p.xp || 0), 0),
  };
  r.top_users_by_xp = profiles.sort((a, b) => (b.xp || 0) - (a.xp || 0)).slice(0, 10).map(p => ({
    name: p.name, username: p.username, xp: p.xp, total_workouts: p.total_workouts, current_streak: p.current_streak, longest_streak: p.longest_streak
  }));

  // ══════════════════════════════════════════════════════════
  // 2. WORKOUTS
  // ══════════════════════════════════════════════════════════
  const workouts = (await safeQuery(() => supabase.from("workouts")
    .select("id, date, duration_seconds, xp_earned, user_id, name, created_at").order("created_at", { ascending: false }).limit(500)) || []) as R[];
  r.workouts = {
    total: workouts.length,
    last_7d: workouts.filter(w => w.created_at >= d7).length,
    last_30d: workouts.filter(w => w.created_at >= d30).length,
    avg_duration_min: workouts.length > 0 ? Math.round(workouts.reduce((a, w) => a + (w.duration_seconds || 0), 0) / workouts.length / 60) : 0,
    unique_users: new Set(workouts.map(w => w.user_id)).size,
  };

  // ══════════════════════════════════════════════════════════
  // 3. WORKOUT EXERCISES & SETS
  // ══════════════════════════════════════════════════════════
  const wxRows = (await safeQuery(() => supabase.from("workout_exercises")
    .select("exercise_name, exercise_order, workout_id").order("created_at", { ascending: false }).limit(1000)) || []) as R[];
  r.popular_exercises = Object.entries(countBy(wxRows, "exercise_name")).sort((a, b) => b[1] - a[1]).slice(0, 30).map(([name, count]) => ({ name, count }));

  // ══════════════════════════════════════════════════════════
  // 4. EXERCISE PERFORMANCE HISTORY (progression data)
  // ══════════════════════════════════════════════════════════
  const perfRows = (await safeQuery(() => supabase.from("exercise_performance_history")
    .select("exercise_name, exercise_category, user_id, workout_date, total_volume, max_weight, total_sets, total_reps")
    .order("workout_date", { ascending: false }).limit(500)) || []) as R[];
  r.exercise_performance = {
    total_records: perfRows.length,
    by_category: countBy(perfRows, "exercise_category"),
    top_by_volume: Object.entries(
      perfRows.reduce((acc: Record<string, number>, e) => { acc[e.exercise_name] = (acc[e.exercise_name] || 0) + (e.total_volume || 0); return acc; }, {})
    ).sort((a, b) => b[1] - a[1]).slice(0, 15).map(([name, vol]) => ({ name, total_volume: vol })),
    unique_users: new Set(perfRows.map(e => e.user_id)).size,
  };

  // ══════════════════════════════════════════════════════════
  // 5. CHALLENGES (group + community + private + daily quests)
  // ══════════════════════════════════════════════════════════
  const groupChallenges = (await safeQuery(() => supabase.from("group_challenges")
    .select("id, challenge_type, mode, status, duration_days, created_at").order("created_at", { ascending: false }).limit(200)) || []) as R[];
  const challengeParts = (await safeQuery(() => supabase.from("challenge_participants")
    .select("challenge_id, status, user_id").limit(500)) || []) as R[];
  const challengeDaily = (await safeQuery(() => supabase.from("challenge_daily_progress")
    .select("challenge_id, user_id, progress_value, progress_date").order("progress_date", { ascending: false }).limit(500)) || []) as R[];
  r.group_challenges = {
    total: groupChallenges.length, by_status: countBy(groupChallenges, "status"),
    by_type: countBy(groupChallenges, "challenge_type"), by_mode: countBy(groupChallenges, "mode"),
    participants: challengeParts.length, participant_statuses: countBy(challengeParts, "status"),
    daily_progress_entries: challengeDaily.length,
  };

  const commChallenges = (await safeQuery(() => supabase.from("community_challenges")
    .select("id, title, challenge_type, status, created_at").limit(100)) || []) as R[];
  const commParts = (await safeQuery(() => supabase.from("community_challenge_participants")
    .select("challenge_id, status").limit(500)) || []) as R[];
  r.community_challenges = { total: commChallenges.length, by_status: countBy(commChallenges, "status"), participants: commParts.length };

  const privateChallenges = (await safeQuery(() => supabase.from("private_challenges")
    .select("id, status, challenge_type, created_at").limit(100)) || []) as R[];
  r.private_challenges = { total: privateChallenges.length, by_status: countBy(privateChallenges, "status") };

  // ══════════════════════════════════════════════════════════
  // 6. DAILY QUESTS
  // ══════════════════════════════════════════════════════════
  const quests = (await safeQuery(() => supabase.from("user_daily_quests")
    .select("quest_type, status, xp_reward, completed_at").order("created_at", { ascending: false }).limit(300)) || []) as R[];
  const questStreaks = (await safeQuery(() => supabase.from("user_quest_streaks")
    .select("current_streak, longest_streak, total_quests_completed").limit(100)) || []) as R[];
  r.daily_quests = {
    total_assigned: quests.length, by_status: countBy(quests, "status"), by_type: countBy(quests, "quest_type"),
    streaks: questStreaks.length > 0 ? {
      avg_current: Math.round(questStreaks.reduce((a, s) => a + (s.current_streak || 0), 0) / questStreaks.length * 10) / 10,
      best_ever: Math.max(...questStreaks.map(s => s.longest_streak || 0)),
    } : null,
  };

  // ══════════════════════════════════════════════════════════
  // 7. SOCIAL (friendships, shared workouts, activity feed, reactions)
  // ══════════════════════════════════════════════════════════
  const friendships = (await safeQuery(() => supabase.from("friendships")
    .select("status, created_at").order("created_at", { ascending: false }).limit(500)) || []) as R[];
  r.friendships = { total: friendships.length, by_status: countBy(friendships, "status"), new_30d: friendships.filter(f => f.created_at >= d30).length };

  const [sharedTotal, shared30d] = await Promise.all([
    safeCount(() => supabase.from("shared_workouts").select("id", { count: "exact", head: true })),
    safeCount(() => supabase.from("shared_workouts").select("id", { count: "exact", head: true }).gte("created_at", d30)),
  ]);
  r.shared_workouts = { total: sharedTotal, last_30d: shared30d };

  const activityFeed = (await safeQuery(() => supabase.from("friend_activity_feed")
    .select("activity_type, created_at").order("created_at", { ascending: false }).limit(200)) || []) as R[];
  r.activity_feed = { total_entries: activityFeed.length, by_type: countBy(activityFeed, "activity_type") };

  const reactions = (await safeQuery(() => supabase.from("activity_reactions")
    .select("emoji, created_at").limit(300)) || []) as R[];
  r.reactions = { total: reactions.length, by_emoji: countBy(reactions, "emoji") };

  // ══════════════════════════════════════════════════════════
  // 8. NUTRITION (meals, food history, food frequency)
  // ══════════════════════════════════════════════════════════
  const meals = (await safeQuery(() => supabase.from("meal_logs")
    .select("meal_type, calories, protein, carbs, fat, date, user_id").order("date", { ascending: false }).limit(500)) || []) as R[];
  r.nutrition = {
    total_meals: meals.length, by_type: countBy(meals, "meal_type"),
    avg_calories: meals.length > 0 ? Math.round(meals.reduce((a, m) => a + (m.calories || 0), 0) / meals.length) : 0,
    avg_protein: meals.length > 0 ? Math.round(meals.reduce((a, m) => a + (m.protein || 0), 0) / meals.length) : 0,
    unique_users: new Set(meals.map(m => m.user_id)).size,
  };

  const foodFreq = (await safeQuery(() => supabase.from("user_food_frequency")
    .select("food_name, times_logged").order("times_logged", { ascending: false }).limit(20)) || []) as R[];
  if (foodFreq.length > 0) r.top_foods = foodFreq.map(f => ({ name: f.food_name, times: f.times_logged }));

  // ══════════════════════════════════════════════════════════
  // 9. PROGRAMS
  // ══════════════════════════════════════════════════════════
  const activePrograms = (await safeQuery(() => supabase.from("user_active_programs")
    .select("program_id, status, current_day, completed_days, total_workouts_completed, total_xp_earned").limit(200)) || []) as R[];
  const progHistory = (await safeQuery(() => supabase.from("program_history")
    .select("program_name, status, days_completed, total_workouts, completion_percentage").order("start_date", { ascending: false }).limit(100)) || []) as R[];
  r.programs = {
    active: activePrograms.length, active_by_status: countBy(activePrograms, "status"),
    history_total: progHistory.length, history_by_status: countBy(progHistory, "status"),
    avg_completion_pct: progHistory.length > 0 ? Math.round(progHistory.reduce((a, p) => a + (p.completion_percentage || 0), 0) / progHistory.length) : 0,
  };

  // ══════════════════════════════════════════════════════════
  // 10. HEALTH (steps, weight, hydration, cardio)
  // ══════════════════════════════════════════════════════════
  const steps = (await safeQuery(() => supabase.from("step_tracking")
    .select("steps, date, user_id").gte("date", d30).order("date", { ascending: false }).limit(500)) || []) as R[];
  r.steps = {
    entries_30d: steps.length, unique_users: new Set(steps.map(s => s.user_id)).size,
    avg_daily: steps.length > 0 ? Math.round(steps.reduce((a, s) => a + (s.steps || 0), 0) / steps.length) : 0,
  };

  const weights = (await safeQuery(() => supabase.from("weight_logs")
    .select("weight_lbs, date, user_id").order("date", { ascending: false }).limit(200)) || []) as R[];
  r.weight_tracking = { entries: weights.length, unique_users: new Set(weights.map(w => w.user_id)).size };

  const hydration = (await safeQuery(() => supabase.from("hydration_logs")
    .select("amount_ml, date, user_id").order("date", { ascending: false }).limit(300)) || []) as R[];
  r.hydration = {
    entries: hydration.length, unique_users: new Set(hydration.map(h => h.user_id)).size,
    avg_daily_ml: hydration.length > 0 ? Math.round(hydration.reduce((a, h) => a + (h.amount_ml || 0), 0) / hydration.length) : 0,
  };

  const cardio = (await safeQuery(() => supabase.from("cardio_workouts")
    .select("activity_type, duration_seconds, distance_meters, calories_burned, source, date").gte("date", d30).limit(200)) || []) as R[];
  r.cardio = { sessions_30d: cardio.length, by_activity: countBy(cardio, "activity_type"), by_source: countBy(cardio, "source") };

  // ══════════════════════════════════════════════════════════
  // 11. STREAKS & STREAK TRACKING
  // ══════════════════════════════════════════════════════════
  const streakTracking = (await safeQuery(() => supabase.from("user_streak_tracking")
    .select("user_id, streak_date, workout_completed, rest_day").order("streak_date", { ascending: false }).limit(300)) || []) as R[];
  r.streak_tracking = {
    entries: streakTracking.length,
    workout_days: streakTracking.filter(s => s.workout_completed).length,
    rest_days: streakTracking.filter(s => s.rest_day).length,
  };

  // ══════════════════════════════════════════════════════════
  // 12. USER FAVORITES
  // ══════════════════════════════════════════════════════════
  const favorites = (await safeQuery(() => supabase.from("user_favorites")
    .select("exercise_id, created_at").limit(300)) || []) as R[];
  r.favorites = { total: favorites.length };

  // ══════════════════════════════════════════════════════════
  // 13. ACHIEVEMENTS
  // ══════════════════════════════════════════════════════════
  const userAchievements = (await safeQuery(() => supabase.from("user_achievements")
    .select("achievement_id, unlocked_at").limit(500)) || []) as R[];
  r.achievements = { total_unlocked: userAchievements.length };

  // ══════════════════════════════════════════════════════════
  // 14. PROGRESS PHOTOS
  // ══════════════════════════════════════════════════════════
  const photos = (await safeQuery(() => supabase.from("progress_photos")
    .select("id, user_id, created_at").limit(200)) || []) as R[];
  r.progress_photos = { total: photos.length, unique_users: new Set(photos.map(p => p.user_id)).size };

  // ══════════════════════════════════════════════════════════
  // 15. LEAGUES
  // ══════════════════════════════════════════════════════════
  const leagueMembers = (await safeQuery(() => supabase.from("league_members")
    .select("league_group_id, user_id, xp_earned").limit(200)) || []) as R[];
  r.leagues = { total_members: leagueMembers.length };

  // ══════════════════════════════════════════════════════════
  // 16. NOTIFICATIONS
  // ══════════════════════════════════════════════════════════
  const notifs = (await safeQuery(() => supabase.from("app_notifications")
    .select("type, is_read, created_at").order("created_at", { ascending: false }).limit(300)) || []) as R[];
  r.notifications = { total: notifs.length, by_type: countBy(notifs, "type"), unread: notifs.filter(n => !n.is_read).length };

  // ══════════════════════════════════════════════════════════
  // 17. ONBOARDING ANALYTICS
  // ══════════════════════════════════════════════════════════
  const onboarding = (await safeQuery(() => supabase.from("onboarding_analytics")
    .select("step_name, completed, drop_off").gte("created_at", d90)) || []) as R[];
  if (onboarding.length > 0) {
    const stepStats: Record<string, { total: number; completed: number; dropped: number }> = {};
    for (const row of onboarding) {
      if (!stepStats[row.step_name]) stepStats[row.step_name] = { total: 0, completed: 0, dropped: 0 };
      stepStats[row.step_name].total++;
      if (row.completed) stepStats[row.step_name].completed++;
      if (row.drop_off) stepStats[row.step_name].dropped++;
    }
    r.onboarding = stepStats;
  }

  // ══════════════════════════════════════════════════════════
  // 18. RETENTION (week over week)
  // ══════════════════════════════════════════════════════════
  try {
    const [w1Res, w2Res] = await Promise.all([
      supabase.from("workouts").select("user_id").gte("created_at", d7),
      supabase.from("workouts").select("user_id").gte("created_at", d14).lt("created_at", d7),
    ]);
    const w1 = new Set((w1Res.data || []).map((x: R) => x.user_id));
    const w2 = new Set((w2Res.data || []).map((x: R) => x.user_id));
    const retained = [...w2].filter(id => w1.has(id));
    r.retention = { active_this_week: w1.size, active_last_week: w2.size, retained: retained.length, rate_pct: w2.size > 0 ? Math.round(retained.length / w2.size * 100) : null };
  } catch { r.retention = null; }

  // ══════════════════════════════════════════════════════════
  // 19. BUGS & CRASHES
  // ══════════════════════════════════════════════════════════
  const [openBugs, newCrashes] = await Promise.all([
    safeCount(() => supabase.from("bug_reports").select("id", { count: "exact", head: true }).eq("status", "open")),
    safeCount(() => supabase.from("crash_reports").select("id", { count: "exact", head: true }).eq("status", "new")),
  ]);
  r.issues = { open_bugs: openBugs, new_crashes: newCrashes };

  // ══════════════════════════════════════════════════════════
  // 20. CHALLENGE REACTIONS
  // ══════════════════════════════════════════════════════════
  const challengeReactions = (await safeQuery(() => supabase.from("challenge_reactions")
    .select("reaction_type, created_at").limit(200)) || []) as R[];
  r.challenge_reactions = { total: challengeReactions.length, by_type: countBy(challengeReactions, "reaction_type") };

  // ══════════════════════════════════════════════════════════
  // 21. CROSS-TABLE ANALYTICS (pre-computed joins)
  // ══════════════════════════════════════════════════════════

  // Build user lookup maps from already-fetched data
  const profileMap = new Map<string, R>();
  for (const p of profiles) profileMap.set(p.id, p);

  // Social × Workout correlation
  const friendships_arr = (await safeQuery(() => supabase.from("friendships")
    .select("requester_id, addressee_id, status").eq("status", "accepted")) || []) as R[];
  const friendCountByUser: Record<string, number> = {};
  for (const f of friendships_arr) {
    friendCountByUser[f.requester_id] = (friendCountByUser[f.requester_id] || 0) + 1;
    friendCountByUser[f.addressee_id] = (friendCountByUser[f.addressee_id] || 0) + 1;
  }

  const socialUsers = profiles.filter(p => (friendCountByUser[p.id] || 0) > 0);
  const soloUsers = profiles.filter(p => (friendCountByUser[p.id] || 0) === 0 && (p.total_workouts || 0) > 0);
  r.cross_social_vs_workout = {
    users_with_friends: socialUsers.length,
    avg_workouts_social_users: socialUsers.length > 0 ? Math.round(socialUsers.reduce((a, p) => a + (p.total_workouts || 0), 0) / socialUsers.length * 10) / 10 : 0,
    avg_workouts_solo_users: soloUsers.length > 0 ? Math.round(soloUsers.reduce((a, p) => a + (p.total_workouts || 0), 0) / soloUsers.length * 10) / 10 : 0,
    avg_streak_social: socialUsers.length > 0 ? Math.round(socialUsers.reduce((a, p) => a + (p.current_streak || 0), 0) / socialUsers.length * 10) / 10 : 0,
    avg_streak_solo: soloUsers.length > 0 ? Math.round(soloUsers.reduce((a, p) => a + (p.current_streak || 0), 0) / soloUsers.length * 10) / 10 : 0,
  };

  // Demographics × Performance
  const goalPerformance: Record<string, { users: number; avg_workouts: number; avg_streak: number }> = {};
  for (const p of active) {
    const goal = (p.fitness_goal as string) || "unset";
    if (!goalPerformance[goal]) goalPerformance[goal] = { users: 0, avg_workouts: 0, avg_streak: 0 };
    goalPerformance[goal].users++;
    goalPerformance[goal].avg_workouts += (p.total_workouts || 0);
    goalPerformance[goal].avg_streak += (p.current_streak || 0);
  }
  for (const goal of Object.keys(goalPerformance)) {
    const g = goalPerformance[goal];
    g.avg_workouts = Math.round(g.avg_workouts / g.users * 10) / 10;
    g.avg_streak = Math.round(g.avg_streak / g.users * 10) / 10;
  }
  r.cross_goal_vs_performance = goalPerformance;

  // Experience Level × Engagement
  const levelEngagement: Record<string, { users: number; avg_workouts: number; avg_xp: number }> = {};
  for (const p of active) {
    const level = (p.experience_level as string) || "unset";
    if (!levelEngagement[level]) levelEngagement[level] = { users: 0, avg_workouts: 0, avg_xp: 0 };
    levelEngagement[level].users++;
    levelEngagement[level].avg_workouts += (p.total_workouts || 0);
    levelEngagement[level].avg_xp += (p.xp || 0);
  }
  for (const lv of Object.keys(levelEngagement)) {
    const l = levelEngagement[lv];
    l.avg_workouts = Math.round(l.avg_workouts / l.users * 10) / 10;
    l.avg_xp = Math.round(l.avg_xp / l.users);
  }
  r.cross_level_vs_engagement = levelEngagement;

  // Challenge completion × user demographics
  const challengeUserIds = new Set(challengeParts.map(cp => cp.user_id));
  const challengeUsers = profiles.filter(p => challengeUserIds.has(p.id));
  const nonChallengeActive = active.filter(p => !challengeUserIds.has(p.id));
  r.cross_challenge_vs_retention = {
    challenge_users: challengeUsers.length,
    non_challenge_active_users: nonChallengeActive.length,
    avg_workouts_challenge_users: challengeUsers.length > 0 ? Math.round(challengeUsers.reduce((a, p) => a + (p.total_workouts || 0), 0) / challengeUsers.length * 10) / 10 : 0,
    avg_workouts_non_challenge: nonChallengeActive.length > 0 ? Math.round(nonChallengeActive.reduce((a, p) => a + (p.total_workouts || 0), 0) / nonChallengeActive.length * 10) / 10 : 0,
    avg_streak_challenge: challengeUsers.length > 0 ? Math.round(challengeUsers.reduce((a, p) => a + (p.current_streak || 0), 0) / challengeUsers.length * 10) / 10 : 0,
    avg_streak_non_challenge: nonChallengeActive.length > 0 ? Math.round(nonChallengeActive.reduce((a, p) => a + (p.current_streak || 0), 0) / nonChallengeActive.length * 10) / 10 : 0,
  };

  // Nutrition × Workout correlation (by user)
  const mealUserIds = new Set(meals.map(m => m.user_id));
  const nutritionTrackers = active.filter(p => mealUserIds.has(p.id));
  const nonTrackers = active.filter(p => !mealUserIds.has(p.id));
  r.cross_nutrition_vs_workout = {
    users_tracking_nutrition: nutritionTrackers.length,
    users_not_tracking: nonTrackers.length,
    avg_workouts_nutrition_trackers: nutritionTrackers.length > 0 ? Math.round(nutritionTrackers.reduce((a, p) => a + (p.total_workouts || 0), 0) / nutritionTrackers.length * 10) / 10 : 0,
    avg_workouts_non_trackers: nonTrackers.length > 0 ? Math.round(nonTrackers.reduce((a, p) => a + (p.total_workouts || 0), 0) / nonTrackers.length * 10) / 10 : 0,
  };

  // User lifecycle stages
  const stages = { new_inactive: 0, beginner: 0, developing: 0, established: 0, power_user: 0 };
  for (const p of profiles) {
    const w = (p.total_workouts as number) || 0;
    if (w === 0) stages.new_inactive++;
    else if (w < 5) stages.beginner++;
    else if (w < 20) stages.developing++;
    else if (w < 50) stages.established++;
    else stages.power_user++;
  }
  r.user_lifecycle_stages = stages;

  return r;
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
