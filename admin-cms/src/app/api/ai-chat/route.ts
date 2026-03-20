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

## CRITICAL RULES
1. NEVER suggest creating tables, columns, or relationships that already exist above. All of these tables are live and populated.
2. The data snapshot attached to each message contains REAL aggregated data from ALL these tables. Use the actual numbers.
3. When analyzing, cross-reference data across tables (e.g. correlate friend count with workout frequency from the data provided).
4. Focus on ACTIONABLE insights: what to build, what to fix, what to promote — not schema suggestions.
5. Be specific: cite exact numbers, percentages, and user counts from the data. No vague statements.
6. If asked about a specific user or specific data point not in the snapshot, say you'd need a targeted query for that.

Format responses with headers, bullet points, and bold for key metrics. Think like a senior product manager presenting to the CEO.`

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
      return `\n\n--- LIVE PLATFORM DATA (${new Date().toISOString()}) ---\n${JSON.stringify(data, null, 2)}\n--- END DATA ---`
    }
  } catch (e) {
    console.error('[ai-chat] Failed to fetch live data context:', e)
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
