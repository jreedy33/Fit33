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

async function collectPlatformData(supabase: ReturnType<typeof createClient>) {
  const now = new Date();
  const sevenDaysAgo = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000).toISOString();
  const thirtyDaysAgo = new Date(now.getTime() - 30 * 24 * 60 * 60 * 1000).toISOString();

  const results: Record<string, unknown> = {};

  // 1. User Growth
  const [totalUsers, newUsers7d, newUsers30d] = await Promise.all([
    supabase.from("user_profiles").select("id", { count: "exact", head: true }),
    supabase.from("user_profiles").select("id", { count: "exact", head: true })
      .gte("created_at", sevenDaysAgo),
    supabase.from("user_profiles").select("id", { count: "exact", head: true })
      .gte("created_at", thirtyDaysAgo),
  ]);

  results.users = {
    total: totalUsers.count ?? 0,
    new_7d: newUsers7d.count ?? 0,
    new_30d: newUsers30d.count ?? 0,
  };

  // 2. Workout Activity
  const [totalWorkouts, workouts7d, workouts30d] = await Promise.all([
    supabase.from("workout_history").select("id", { count: "exact", head: true }),
    supabase.from("workout_history").select("id", { count: "exact", head: true })
      .gte("completed_at", sevenDaysAgo),
    supabase.from("workout_history").select("id", { count: "exact", head: true })
      .gte("completed_at", thirtyDaysAgo),
  ]);

  results.workouts = {
    total: totalWorkouts.count ?? 0,
    last_7d: workouts7d.count ?? 0,
    last_30d: workouts30d.count ?? 0,
  };

  // 3. Popular Exercises (from exercise_usage_logs if it exists)
  try {
    const { data: popularExercises } = await supabase
      .from("exercise_usage_logs")
      .select("exercise_name")
      .order("created_at", { ascending: false })
      .limit(500);

    if (popularExercises && popularExercises.length > 0) {
      const counts: Record<string, number> = {};
      for (const row of popularExercises) {
        counts[row.exercise_name] = (counts[row.exercise_name] || 0) + 1;
      }
      const sorted = Object.entries(counts).sort((a, b) => b[1] - a[1]).slice(0, 20);
      results.popular_exercises = sorted.map(([name, count]) => ({ name, count }));
    }
  } catch {
    results.popular_exercises = [];
  }

  // 4. Onboarding Analytics
  try {
    const { data: onboardingData } = await supabase
      .from("onboarding_analytics")
      .select("step_name, completed, drop_off")
      .gte("created_at", thirtyDaysAgo);

    if (onboardingData && onboardingData.length > 0) {
      const stepStats: Record<string, { total: number; completed: number; dropped: number }> = {};
      for (const row of onboardingData) {
        if (!stepStats[row.step_name]) {
          stepStats[row.step_name] = { total: 0, completed: 0, dropped: 0 };
        }
        stepStats[row.step_name].total++;
        if (row.completed) stepStats[row.step_name].completed++;
        if (row.drop_off) stepStats[row.step_name].dropped++;
      }
      results.onboarding = stepStats;
    }
  } catch {
    results.onboarding = null;
  }

  // 5. Social Activity
  const [friendships, sharedWorkouts, challenges] = await Promise.all([
    supabase.from("friendships").select("id", { count: "exact", head: true })
      .gte("created_at", thirtyDaysAgo),
    supabase.from("shared_workouts").select("id", { count: "exact", head: true })
      .gte("created_at", thirtyDaysAgo),
    supabase.from("group_challenges").select("id", { count: "exact", head: true })
      .gte("created_at", thirtyDaysAgo),
  ]);

  results.social = {
    new_friendships_30d: friendships.count ?? 0,
    workouts_shared_30d: sharedWorkouts.count ?? 0,
    challenges_created_30d: challenges.count ?? 0,
  };

  // 6. Retention proxy: users with workouts in different time windows
  try {
    const fourteenDaysAgo = new Date(now.getTime() - 14 * 24 * 60 * 60 * 1000).toISOString();
    const [activeWeek1, activeWeek2] = await Promise.all([
      supabase.from("workout_history")
        .select("user_id")
        .gte("completed_at", sevenDaysAgo),
      supabase.from("workout_history")
        .select("user_id")
        .gte("completed_at", fourteenDaysAgo)
        .lt("completed_at", sevenDaysAgo),
    ]);

    const week1Users = new Set((activeWeek1.data || []).map((r: { user_id: string }) => r.user_id));
    const week2Users = new Set((activeWeek2.data || []).map((r: { user_id: string }) => r.user_id));
    const retained = [...week2Users].filter(id => week1Users.has(id));

    results.retention = {
      active_this_week: week1Users.size,
      active_last_week: week2Users.size,
      retained_both_weeks: retained.length,
      retention_rate: week2Users.size > 0
        ? Math.round((retained.length / week2Users.size) * 100)
        : null,
    };
  } catch {
    results.retention = null;
  }

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
