import { NextRequest } from 'next/server'
import { createClient } from '@supabase/supabase-js'
import { createAdminClient } from '@/lib/supabase-admin'
import { isAdminEmail } from '@/lib/auth'
import { getAccessToken } from '@/lib/auth-cookies'
import Anthropic from '@anthropic-ai/sdk'

const SYSTEM_PROMPT = `You are Fit33's AI Product Analyst. You help the admin team understand user behavior, identify trends, and make data-driven decisions for the Fit33 iOS fitness app.

## About Fit33
Premium iOS fitness app. Workout tracking, 6500+ exercises with video, meal planning, social (friends, challenges, leagues), gamification (XP, levels, streaks, daily quests, achievements). Backend: Supabase (Postgres) + Edge Functions. iOS: SwiftUI + Core Data for offline.

## COMPLETE DATABASE SCHEMA (these tables ALL exist — never suggest creating them)
- user_profiles: id, name, username, email, gender, age, fitness_goal, experience_level, strength_level, workout_environment, equipment, available_days, current_streak, longest_streak, total_workouts, xp, has_completed_onboarding, created_at, last_workout_date, weight_unit, height_unit, daily_calorie_goal, daily_protein_goal, daily_carbs_goal, daily_fat_goal, profile_photo_url
- workouts: id, date, duration_seconds, xp_earned, user_id, name, created_at
- workout_exercises: id, exercise_name, exercise_order, workout_id, created_at (each has related workout_sets with set_number, reps, weight, is_completed, set_type)
- exercise_performance_history: exercise_name, exercise_category, user_id, workout_date, total_volume, max_weight, total_sets, total_reps
- group_challenges: id, title, challenge_type, mode (competition/accountability), status, duration_days, created_at, start_date, end_date
- challenge_participants: challenge_id, user_id, status
- challenge_daily_progress: challenge_id, user_id, progress_value, progress_date
- challenge_reactions: reaction_type, created_at
- community_challenges: id, title, challenge_type, status
- community_challenge_participants: challenge_id, status
- community_challenge_daily_progress: challenge_id, user_id, progress_value
- private_challenges: id, status, challenge_type
- private_challenge_members, private_challenge_invites, private_challenge_daily_progress, private_challenge_chat
- friendships: requester_id, addressee_id, status, created_at
- shared_workouts: id, recipient_id, created_at, is_read
- friend_activity_feed: activity_type, user_id, created_at
- activity_reactions: emoji, created_at
- user_blocks: blocker_id, blocked_id
- meal_logs: food_name, meal_type, calories, protein, carbs, fat, date, user_id
- user_food_history, user_food_frequency: food_name, times_logged
- user_active_programs: program_id, user_id, status, current_day, completed_days, total_workouts_completed, total_xp_earned
- program_history: program_name, status, days_completed, total_workouts, completion_percentage, start_date, end_date
- program_templates: id, name, duration_weeks, difficulty, focus
- program_day_history: program_id, day_number, completed_at
- exercise_bundles: exercise group templates
- step_tracking: steps, date, user_id
- weight_logs: weight_lbs, date, user_id
- hydration_logs: amount_ml, date, user_id
- cardio_workouts: activity_type, duration_seconds, distance_meters, calories_burned, source, date
- user_streak_tracking: user_id, streak_date, workout_completed, rest_day
- user_favorites: exercise_id, user_id, created_at
- achievements: id, name, description, criteria
- user_achievements: user_id, achievement_id, unlocked_at
- progress_photos: id, user_id, photo_url, created_at
- league_tiers, league_groups, league_members, league_history, user_league_tier
- quest_templates: quest definitions
- user_daily_quests: quest_type, status, xp_reward, completed_at
- user_quest_streaks: current_streak, longest_streak, total_quests_completed
- onboarding_analytics: step_name, step_index, completed, drop_off, duration_seconds, session_id
- app_notifications: type, is_read, user_id, created_at
- bug_reports: status, description, created_at
- crash_reports: status, error_message, severity, created_at
- admin_audit_log: admin_user_id, action, target_id

## PRE-COMPUTED CROSS-TABLE ANALYTICS (included in every data snapshot)
The data snapshot already contains these JOIN results — USE THEM, don't suggest recreating them:
- cross_social_vs_workout: avg workouts & streaks for users WITH friends vs WITHOUT friends
- cross_goal_vs_performance: avg workouts & streaks broken down by fitness_goal
- cross_level_vs_engagement: workouts & XP broken down by experience_level
- cross_challenge_vs_retention: challenge participants vs non-participants (workouts, streaks)
- cross_nutrition_vs_workout: nutrition trackers vs non-trackers (workout frequency)
- user_lifecycle_stages: new_inactive, beginner, developing, established, power_user counts

## DATA ACCESS — You have LIVE access to:
1. **Platform analytics** — user growth, workout activity, social engagement, nutrition, streaks, cross-table correlations
2. **Crash reports** — error messages, severity, device/iOS/app version, screen name, stack traces, occurrence counts, status
3. **Bug reports** — user descriptions, priority, category, device info, session logs
4. **Dev session logs** — real-time session data from dogfooding users, including errors, screen flows, API calls, performance data

When analyzing crashes or bugs:
- Cross-reference crash error messages with bug report descriptions to find patterns
- Map crash screen names to user-reported bug locations
- Check dev session error logs for related issues
- Note device/iOS version patterns across crashes
- Prioritize by: severity × occurrence_count × user impact

## CRITICAL RULES
1. NEVER suggest creating tables, columns, views, indexes, or SQL. The schema is complete and all relationships exist via user_id joins. The cross-table data is ALREADY in the snapshot.
2. NEVER say "missing relationship" or "missing link" — every table can be joined via user_id. The pre-computed analytics above already do these joins for you.
3. USE THE ACTUAL NUMBERS from the data snapshot. Every response must cite specific metrics. If a cross-table stat shows "avg_workouts_social_users: 15.2" then SAY "Social users average 15.2 workouts."
4. Focus ONLY on actionable product decisions: what feature to build next, what to fix, what user segment to target, what content to create.
5. NEVER output SQL code blocks. The admin is a product owner, not a database engineer.
6. If asked "what data is missing" — nothing is missing. Suggest what PRODUCT FEATURES or EXPERIMENTS would improve metrics instead.
7. When asked about crashes or bugs, ALWAYS reference the actual crash/bug data provided. Cite specific error messages, severity, and occurrence counts. Map crashes to likely user-facing symptoms.

Format: headers, bullet points, bold metrics. Be a senior product manager, not a database consultant.`

async function verifyAdmin(req: NextRequest): Promise<{ valid: boolean; userId?: string; email?: string }> {
  const token = getAccessToken(req)
  if (!token || token.length < 10) return { valid: false }

  const supabase = createClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
  )

  const { data: { user }, error } = await supabase.auth.getUser(token)
  if (error || !user?.email) return { valid: false }
  if (!isAdminEmail(user.email)) return { valid: false }

  return { valid: true, userId: user.id, email: user.email }
}

async function fetchLiveDataContext(): Promise<string> {
  const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL!
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY!
  const parts: string[] = []

  // 1. Platform analytics from Edge Function
  try {
    const res = await fetch(`${supabaseUrl}/functions/v1/generate-ai-insights`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${serviceKey}`,
      },
      body: JSON.stringify({ action: 'get_data_context' }),
    })

    if (res.ok) {
      const data = await res.json()
      parts.push(`--- LIVE PLATFORM DATA (${new Date().toISOString()}) ---\n${JSON.stringify(data, null, 2)}\n--- END PLATFORM DATA ---`)
    }
  } catch (e) {
    console.error('[ai-chat] Failed to fetch live data context:', e)
  }

  // 2. Crash reports, bug reports, and dev session logs (direct queries)
  try {
    const admin = createAdminClient()

    const [crashRes, bugRes, devSessionRes] = await Promise.all([
      admin.from('crash_reports')
        .select('id, error_message, severity, status, device_model, ios_version, app_version, screen_name, stack_trace, steps_to_reproduce, occurrence_count, first_seen, last_seen, created_at, additional_context')
        .order('created_at', { ascending: false })
        .limit(30),
      admin.from('bug_reports')
        .select('id, description, status, priority, category, device_info, app_version, created_at, session_log')
        .order('created_at', { ascending: false })
        .limit(30),
      admin.from('dev_session_logs')
        .select('session_id, user_id, device_info, created_at, entries')
        .order('created_at', { ascending: false })
        .limit(10),
    ])

    if (crashRes.data && crashRes.data.length > 0) {
      const crashSummary = {
        total: crashRes.data.length,
        by_severity: crashRes.data.reduce((acc: Record<string, number>, c) => {
          const sev = (c.severity as string) || 'unknown'
          acc[sev] = (acc[sev] || 0) + 1
          return acc
        }, {}),
        by_status: crashRes.data.reduce((acc: Record<string, number>, c) => {
          const st = (c.status as string) || 'new'
          acc[st] = (acc[st] || 0) + 1
          return acc
        }, {}),
        by_thermal: crashRes.data.reduce((acc: Record<string, number>, c) => {
          const ctx = c.additional_context as Record<string, string> | null
          const thermal = ctx?.thermal_state || 'unknown'
          acc[thermal] = (acc[thermal] || 0) + 1
          return acc
        }, {}),
        recent_crashes: crashRes.data.slice(0, 15).map(c => {
          const ctx = c.additional_context as Record<string, string> | null
          return {
            id: (c.id as string).slice(0, 8),
            error: c.error_message,
            severity: c.severity,
            status: c.status,
            device: c.device_model,
            ios: c.ios_version,
            app_version: c.app_version,
            screen: c.screen_name,
            occurrences: c.occurrence_count,
            first_seen: c.first_seen,
            last_seen: c.last_seen,
            thermal_state: ctx?.thermal_state || null,
            stack_trace_preview: typeof c.stack_trace === 'string' ? (c.stack_trace as string).slice(0, 300) : null,
          }
        }),
      }
      parts.push(`--- CRASH REPORTS (${crashRes.data.length} recent) ---\n${JSON.stringify(crashSummary, null, 2)}\n--- END CRASH REPORTS ---`)
    }

    if (bugRes.data && bugRes.data.length > 0) {
      const bugSummary = {
        total: bugRes.data.length,
        by_status: bugRes.data.reduce((acc: Record<string, number>, b) => {
          const st = (b.status as string) || 'new'
          acc[st] = (acc[st] || 0) + 1
          return acc
        }, {}),
        by_category: bugRes.data.reduce((acc: Record<string, number>, b) => {
          const cat = (b.category as string) || 'uncategorized'
          acc[cat] = (acc[cat] || 0) + 1
          return acc
        }, {}),
        recent_bugs: bugRes.data.slice(0, 15).map(b => ({
          id: (b.id as string).slice(0, 8),
          description: typeof b.description === 'string' ? (b.description as string).slice(0, 200) : b.description,
          status: b.status,
          priority: b.priority,
          category: b.category,
          device: b.device_info,
          app_version: b.app_version,
          created_at: b.created_at,
          has_session_log: !!b.session_log,
        })),
      }
      parts.push(`--- BUG REPORTS (${bugRes.data.length} recent) ---\n${JSON.stringify(bugSummary, null, 2)}\n--- END BUG REPORTS ---`)
    }

    if (devSessionRes.data && devSessionRes.data.length > 0) {
      const sessionSummary = devSessionRes.data.map(s => {
        let errorCount = 0
        let perfCount = 0
        let entries: Array<{ type?: string; detail?: string; ts?: number; duration_ms?: number }> = []
        try {
          entries = typeof s.entries === 'string' ? JSON.parse(s.entries as string) : (s.entries as typeof entries) || []
          errorCount = entries.filter((e: { type?: string }) => e.type === 'error').length
          perfCount = entries.filter((e: { type?: string }) => e.type === 'perf').length
        } catch { /* skip parse errors */ }
        const errors = entries.filter((e: { type?: string }) => e.type === 'error').slice(0, 5)
        const perfEvents = entries.filter((e: { type?: string }) => e.type === 'perf').slice(0, 10)
        const fpsDrops = perfEvents.filter(e => (e.detail || '').includes('FPS_DROP'))
        const hangs = perfEvents.filter(e => (e.detail || '').includes('METRICKIT_HANG'))
        const slowOps = entries.filter(e => e.duration_ms && e.duration_ms > 500)
        return {
          session_id: (s.session_id as string).slice(0, 8),
          user_id: (s.user_id as string).slice(0, 8),
          device: s.device_info,
          created_at: s.created_at,
          entry_count: entries.length,
          error_count: errorCount,
          perf_event_count: perfCount,
          fps_drops: fpsDrops.length,
          metrickit_hangs: hangs.length,
          slow_operations: slowOps.length,
          recent_errors: errors.map((e: { detail?: string; ts?: number }) => ({
            detail: e.detail,
            time: e.ts ? new Date(e.ts).toISOString() : null,
          })),
          recent_perf_issues: [...fpsDrops, ...hangs, ...slowOps].slice(0, 5).map(e => ({
            detail: e.detail,
            duration_ms: e.duration_ms,
            time: e.ts ? new Date(e.ts).toISOString() : null,
          })),
        }
      })
      parts.push(`--- DEV SESSION LOGS (${devSessionRes.data.length} recent sessions) ---\n${JSON.stringify(sessionSummary, null, 2)}\n--- END DEV SESSION LOGS ---`)
    }
  } catch (e) {
    console.error('[ai-chat] Failed to fetch crash/bug/session data:', e)
  }

  if (parts.length > 0) {
    return '\n\n' + parts.join('\n\n')
  }
  return '\n\n(Live data context unavailable - answering based on conversation context only)'
}

export async function POST(req: NextRequest) {
  const adminAuth = await verifyAdmin(req)
  if (!adminAuth.valid) {
    return new Response(JSON.stringify({ error: 'Unauthorized' }), {
      status: 401,
      headers: { 'Content-Type': 'application/json' },
    })
  }

  const apiKey = process.env.ANTHROPIC_API_KEY
  if (!apiKey) {
    console.error('[ai-chat] ANTHROPIC_API_KEY missing from environment')
    return new Response(JSON.stringify({ error: 'ANTHROPIC_API_KEY not configured. Add it in Vercel > Settings > Environment Variables and redeploy.' }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    })
  }

  try {
    const body = await req.json()
    const { messages, conversationId, fetchData } = body as {
      messages: Array<{ role: 'user' | 'assistant'; content: string }>
      conversationId?: string
      fetchData?: boolean
    }

    if (!messages || !Array.isArray(messages) || messages.length === 0) {
      return new Response(JSON.stringify({ error: 'Messages array required' }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' },
      })
    }

    let dataContext = ''
    if (fetchData !== false) {
      dataContext = await fetchLiveDataContext()
    }

    const systemWithData = SYSTEM_PROMPT + dataContext

    const anthropic = new Anthropic({ apiKey })

    const stream = anthropic.messages.stream({
      model: 'claude-sonnet-4-20250514',
      max_tokens: 4096,
      system: systemWithData,
      messages: messages.map(m => ({ role: m.role, content: m.content })),
    })

    const encoder = new TextEncoder()
    let fullResponse = ''

    const readable = new ReadableStream({
      async start(controller) {
        try {
          stream.on('text', (text) => {
            fullResponse += text
            controller.enqueue(encoder.encode(`data: ${JSON.stringify({ text })}\n\n`))
          })

          await stream.finalMessage()

          controller.enqueue(encoder.encode(`data: ${JSON.stringify({ done: true })}\n\n`))

          // Auto-save conversation after streaming completes
          if (conversationId || messages.length >= 1) {
            try {
              const admin = createAdminClient()
              const allMessages = [...messages, { role: 'assistant', content: fullResponse }]
              const title = messages[0]?.content?.substring(0, 80) || 'New Conversation'

              if (conversationId) {
                await admin.from('ai_chat_history')
                  .update({
                    messages: allMessages,
                    title,
                    updated_at: new Date().toISOString(),
                  })
                  .eq('id', conversationId)
              } else {
                const { data } = await admin.from('ai_chat_history')
                  .insert({
                    admin_user_id: adminAuth.userId!,
                    title,
                    messages: allMessages,
                  })
                  .select('id')
                  .single()

                if (data) {
                  controller.enqueue(
                    encoder.encode(`data: ${JSON.stringify({ conversationId: data.id })}\n\n`)
                  )
                }
              }
            } catch (saveErr) {
              console.error('[ai-chat] Failed to save conversation:', saveErr)
            }
          }

          controller.close()
        } catch (streamErr) {
          console.error('[ai-chat] Stream error:', streamErr)
          controller.enqueue(
            encoder.encode(`data: ${JSON.stringify({ error: 'Stream interrupted' })}\n\n`)
          )
          controller.close()
        }
      },
    })

    return new Response(readable, {
      headers: {
        'Content-Type': 'text/event-stream',
        'Cache-Control': 'no-cache',
        'Connection': 'keep-alive',
      },
    })
  } catch (err) {
    console.error('[ai-chat] Error:', err)
    return new Response(
      JSON.stringify({ error: err instanceof Error ? err.message : 'Internal error' }),
      { status: 500, headers: { 'Content-Type': 'application/json' } },
    )
  }
}
