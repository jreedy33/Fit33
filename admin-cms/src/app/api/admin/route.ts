import { NextRequest, NextResponse } from 'next/server'
import { createAdminClient } from '@/lib/supabase-admin'
import { createClient } from '@supabase/supabase-js'
import { isAdminEmail } from '@/lib/auth'
import { getAccessToken } from '@/lib/auth-cookies'
import { parseJson, adminEnvelopeSchema } from '@/lib/validation'

// ═══════════════════════════════════════════════════
// RATE LIMITING (per-IP, per-endpoint)
// ═══════════════════════════════════════════════════

const RATE_LIMITS: Record<string, { max: number; windowMs: number }> = {
  read:  { max: 100, windowMs: 60_000 },
  write: { max: 30,  windowMs: 60_000 },
  bulk:  { max: 5,   windowMs: 60_000 },
}

// Any mutating action MUST appear in one of these sets so that:
//   (1) it is rate-limited under the stricter `write` / `bulk` tier, and
//   (2) `logAdminAction()` runs for it (tier !== 'read' in POST handler).
// Missing actions get classified as `read` and silently skip the audit log —
// a compliance + forensics gap. Per INFRA_SECURITY invariant #5 + auditor
// findings (2026-04-22). `delete_user` has no handler and was removed.
const WRITE_ACTIONS = new Set([
  'update_user', 'update_bug_report', 'delete_bug_report',
  'update_crash_report', 'delete_crash_report',
  'create_faq_entry', 'update_faq_entry', 'delete_faq_entry', 'publish_faq_entry',
  'create_faq_category', 'update_faq_category', 'delete_faq_category',
  'update_exercise', 'delete_exercise',
  'create_feature_flag', 'update_feature_flag', 'delete_feature_flag',
  'update_report_status', 'suspend_user', 'lift_suspension',
  'review_flagged_content',
  'create_push_campaign', 'update_push_campaign',
  // AI insights / dev-logging mutations — previously untracked.
  'update_insight_status', 'trigger_insights_generation',
  'save_chat_conversation', 'delete_chat_conversation',
  'toggle_dev_logging', 'update_suggestion_status',
  // Bug intelligence (Phase 2) mutations
  'update_bug_fingerprint', 'update_bug_report_review', 'trigger_bug_triage',
])
const BULK_ACTIONS = new Set([
  'bulk_update_bug_reports', 'bulk_update_crash_reports',
  'bulk_publish_faq_entries',
  'send_push_campaign',
  // Bulk crash-report deletion paths — previously untracked.
  'bulk_delete_crash_reports', 'delete_resolved_crash_reports',
])

function getActionTier(action: string): 'read' | 'write' | 'bulk' {
  if (BULK_ACTIONS.has(action)) return 'bulk'
  if (WRITE_ACTIONS.has(action)) return 'write'
  return 'read'
}

const rateBuckets = new Map<string, { count: number; resetAt: number }>()

function checkAdminRateLimit(ip: string, action: string): { allowed: boolean; retryAfter?: number } {
  const tier = getActionTier(action)
  const limit = RATE_LIMITS[tier]
  const key = `${ip}:${tier}`
  const now = Date.now()

  const bucket = rateBuckets.get(key)
  if (!bucket || now > bucket.resetAt) {
    rateBuckets.set(key, { count: 1, resetAt: now + limit.windowMs })
    return { allowed: true }
  }

  if (bucket.count >= limit.max) {
    return { allowed: false, retryAfter: Math.ceil((bucket.resetAt - now) / 1000) }
  }

  bucket.count++
  return { allowed: true }
}

setInterval(() => {
  const now = Date.now()
  for (const [key, bucket] of rateBuckets) {
    if (now > bucket.resetAt) rateBuckets.delete(key)
  }
}, 5 * 60_000)

// ═══════════════════════════════════════════════════
// AUDIT LOGGING
// ═══════════════════════════════════════════════════

async function logAdminAction(
  adminUserId: string,
  action: string,
  target: string | null,
  ip: string,
  adminEmail?: string,
  details?: Record<string, unknown>,
) {
  try {
    const admin = createAdminClient()
    await admin.from('admin_audit_log').insert({
      admin_user_id: adminUserId,
      action,
      target_id: target,
      ip_address: ip,
      admin_email: adminEmail || null,
      details: details || {},
      created_at: new Date().toISOString(),
    })
  } catch {
    console.error('[AUDIT] Failed to log admin action:', action)
  }
}

// ═══════════════════════════════════════════════════
// SECURITY HELPERS
// ═══════════════════════════════════════════════════

function sanitizeSearch(input: string): string {
  return input
    .replace(/\\/g, '\\\\')
    .replace(/%/g, '\\%')
    .replace(/_/g, '\\_')
    .trim()
    .substring(0, 200)
}

function safeLimit(limit: number | undefined, max: number = 100): number {
  const n = Number(limit) || 50
  return Math.min(Math.max(1, n), max)
}

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

export async function POST(req: NextRequest) {
  const ip = req.headers.get('x-forwarded-for')?.split(',')[0]?.trim()
    || req.headers.get('x-real-ip')
    || 'unknown'

  // Verify admin access
  const adminAuth = await verifyAdmin(req)
  if (!adminAuth.valid) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  }

  try {
    const parsed = await parseJson(req, adminEnvelopeSchema)
    if (!parsed.ok) return parsed.response
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const { action, ...params } = parsed.data as any

    // Rate limit check
    const rateCheck = checkAdminRateLimit(ip, action)
    if (!rateCheck.allowed) {
      return NextResponse.json(
        { error: `Rate limit exceeded. Retry in ${rateCheck.retryAfter}s.` },
        { status: 429, headers: { 'Retry-After': String(rateCheck.retryAfter) } },
      )
    }

    // Audit write/bulk actions
    const tier = getActionTier(action)
    if (tier !== 'read') {
      const targetId = params.userId || params.id || params.reportId || params.campaign_id || params.flag_id || null
      await logAdminAction(adminAuth.userId!, action, targetId, ip, adminAuth.email, params.details)
    }

    const admin = createAdminClient()

    switch (action) {
      // ═══════════════════════════════════════════════════
      // DASHBOARD STATS
      // ═══════════════════════════════════════════════════
      case 'get_dashboard_stats': {
        const [usersResult, recentUsersResult, workoutsResult, activeUsersResult] = await Promise.all([
          admin.from('user_profiles').select('id', { count: 'exact', head: true }),
          admin.from('user_profiles').select('id', { count: 'exact', head: true })
            .gte('created_at', new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString()),
          admin.from('workouts').select('id', { count: 'exact', head: true }),
          admin.from('user_profiles').select('id', { count: 'exact', head: true })
            .gte('last_workout_date', new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString()),
        ])

        return NextResponse.json({
          total_users: usersResult.count || 0,
          new_users_7d: recentUsersResult.count || 0,
          total_workouts: workoutsResult.count || 0,
          active_users_30d: activeUsersResult.count || 0,
        })
      }

      // ═══════════════════════════════════════════════════
      // SEARCH USERS
      // ═══════════════════════════════════════════════════
      case 'search_users': {
        const { query, page = 0 } = params
        const lim = safeLimit(params.limit, 100)
        const pg = Math.max(0, Number(page) || 0)
        let dbQuery = admin.from('user_profiles')
          .select('id, name, email, username, phone_number, gender, age, fitness_goal, experience_level, current_streak, longest_streak, total_workouts, xp, profile_photo_url, has_completed_onboarding, created_at, updated_at, last_workout_date')
          .order('created_at', { ascending: false })
          .range(pg * lim, (pg + 1) * lim - 1)

        if (query && query.trim()) {
          const q = sanitizeSearch(query)
          // Search across email, username, name, phone
          dbQuery = dbQuery.or(`email.ilike.%${q}%,username.ilike.%${q}%,name.ilike.%${q}%,phone_number.ilike.%${q}%`)
        }

        const { data, error, count } = await dbQuery

        if (error) {
          return NextResponse.json({ error: error.message }, { status: 500 })
        }

        return NextResponse.json({ users: data || [], total: count })
      }

      // ═══════════════════════════════════════════════════
      // GET FULL USER PROFILE
      // ═══════════════════════════════════════════════════
      case 'get_user': {
        const { user_id } = params

        const { data: profile, error } = await admin.from('user_profiles')
          .select('*')
          .eq('id', user_id)
          .single()

        if (error) {
          return NextResponse.json({ error: error.message }, { status: 404 })
        }

        return NextResponse.json({ profile })
      }

      // ═══════════════════════════════════════════════════
      // UPDATE USER PROFILE
      // ═══════════════════════════════════════════════════
      case 'update_user': {
        const { user_id, updates } = params

        // Whitelist of editable fields
        const allowedFields = [
          'name', 'email', 'username', 'phone_number', 'birthday', 'age', 'gender',
          'height_cm', 'height_inches', 'weight_kg', 'weight_lbs',
          'fitness_goal', 'experience_level', 'strength_level',
          'workout_environment', 'equipment', 'available_days',
          'current_streak', 'longest_streak', 'total_workouts', 'xp',
          'last_workout_date', 'has_completed_onboarding', 'is_verified', 'is_gold_verified',
          'weight_unit', 'height_unit', 'distance_unit', 'week_start_day',
          'daily_calorie_goal', 'daily_protein_goal', 'daily_carbs_goal', 'daily_fat_goal',
          'bmr', 'tdee', 'protein_goal_g', 'carbs_goal_g', 'fat_goal_g',
        ]

        const sanitized: Record<string, unknown> = {}
        for (const [key, value] of Object.entries(updates)) {
          if (allowedFields.includes(key)) {
            sanitized[key] = value
          }
        }
        sanitized.updated_at = new Date().toISOString()

        const { data, error } = await admin.from('user_profiles')
          .update(sanitized)
          .eq('id', user_id)
          .select()
          .single()

        if (error) {
          return NextResponse.json({ error: error.message }, { status: 500 })
        }

        return NextResponse.json({ profile: data })
      }

      // ═══════════════════════════════════════════════════
      // GET USER FRIENDS
      // ═══════════════════════════════════════════════════
      case 'get_user_friends': {
        const { user_id } = params

        // Get all friendships where user is either requester or addressee
        const { data: friendships, error } = await admin.from('friendships')
          .select('id, requester_id, addressee_id, status, created_at, updated_at')
          .or(`requester_id.eq.${user_id},addressee_id.eq.${user_id}`)
          .order('created_at', { ascending: false })

        if (error) {
          return NextResponse.json({ error: error.message }, { status: 500 })
        }

        // Get friend profile details
        const friendIds = (friendships || []).map(f =>
          f.requester_id === user_id ? f.addressee_id : f.requester_id
        )

        let friends: Record<string, unknown>[] = []
        if (friendIds.length > 0) {
          const { data: profiles } = await admin.from('user_profiles')
            .select('id, name, username, email, profile_photo_url')
            .in('id', friendIds)

          friends = profiles || []
        }

        // Combine friendship data with profiles
        const enriched = (friendships || []).map(f => {
          const friendId = f.requester_id === user_id ? f.addressee_id : f.requester_id
          const profile = friends.find((p: Record<string, unknown>) => p.id === friendId) || {}
          return { ...f, friend_id: friendId, friend_profile: profile }
        })

        return NextResponse.json({ friends: enriched })
      }

      // ═══════════════════════════════════════════════════
      // GET USER CHALLENGES
      // ═══════════════════════════════════════════════════
      case 'get_user_challenges': {
        const { user_id } = params

        const { data: participations, error: pError } = await admin.from('challenge_participants')
          .select('challenge_id, status, total_progress, days_completed, current_streak, joined_at')
          .eq('user_id', user_id)
          .order('joined_at', { ascending: false })

        if (pError) {
          return NextResponse.json({ error: pError.message }, { status: 500 })
        }

        const challengeIds = (participations || []).map(p => p.challenge_id)
        let challenges: Record<string, unknown>[] = []
        let allParticipants: Record<string, unknown>[] = []

        if (challengeIds.length > 0) {
          const [cRes, pRes] = await Promise.all([
            admin.from('group_challenges')
              .select('id, title, description, challenge_type, mode, daily_target, total_target, target_unit, start_date, end_date, duration_days, status, created_by, created_at')
              .in('id', challengeIds),
            admin.from('challenge_participants')
              .select('challenge_id, user_id, status, total_progress, days_completed, current_streak')
              .in('challenge_id', challengeIds),
          ])

          challenges = cRes.data || []
          allParticipants = pRes.data || []

          const memberUserIds = [...new Set(
            allParticipants
              .map((p: Record<string, unknown>) => p.user_id as string)
              .filter(id => id !== user_id)
          )]

          let memberProfiles: Record<string, unknown>[] = []
          if (memberUserIds.length > 0) {
            const { data: profiles } = await admin.from('user_profiles')
              .select('id, name, username, email, profile_photo_url')
              .in('id', memberUserIds)
            memberProfiles = profiles || []
          }

          allParticipants = allParticipants.map((p: Record<string, unknown>) => ({
            ...p,
            profile: p.user_id === user_id
              ? null
              : memberProfiles.find((mp: Record<string, unknown>) => mp.id === p.user_id) || null,
          }))
        }

        const enriched = (participations || []).map(p => {
          const challenge = challenges.find((c: Record<string, unknown>) => c.id === p.challenge_id) || {}
          const members = allParticipants
            .filter((ap: Record<string, unknown>) => ap.challenge_id === p.challenge_id && ap.user_id !== user_id)
          return { ...p, challenge, members }
        })

        return NextResponse.json({ challenges: enriched })
      }

      // ═══════════════════════════════════════════════════
      // GET USER WORKOUTS
      // ═══════════════════════════════════════════════════
      case 'get_user_workouts': {
        const { user_id, page = 0, limit = 20 } = params

        const { data, error } = await admin.from('workouts')
          .select('id, name, date, duration_seconds, xp_earned, program_id, program_day, created_at')
          .eq('user_id', user_id)
          .order('date', { ascending: false })
          .range(page * limit, (page + 1) * limit - 1)

        if (error) {
          return NextResponse.json({ error: error.message }, { status: 500 })
        }

        return NextResponse.json({ workouts: data || [] })
      }

      // ═══════════════════════════════════════════════════
      // GET USER WORKOUT DETAILS (with exercises + sets)
      // ═══════════════════════════════════════════════════
      case 'get_workout_detail': {
        const { workout_id } = params

        const [workoutRes, exercisesRes] = await Promise.all([
          admin.from('workouts').select('*').eq('id', workout_id).single(),
          admin.from('workout_exercises')
            .select('id, exercise_name, exercise_order, workout_sets(id, set_number, reps, weight, is_completed, set_type)')
            .eq('workout_id', workout_id)
            .order('exercise_order', { ascending: true }),
        ])

        return NextResponse.json({
          workout: workoutRes.data,
          exercises: exercisesRes.data || [],
        })
      }

      // ═══════════════════════════════════════════════════
      // GET USER STREAKS
      // ═══════════════════════════════════════════════════
      case 'get_user_streaks': {
        const { user_id } = params

        const { data, error } = await admin.from('user_streak_tracking')
          .select('*')
          .eq('user_id', user_id)

        if (error) {
          return NextResponse.json({ error: error.message }, { status: 500 })
        }

        return NextResponse.json({ streaks: data || [] })
      }

      // ═══════════════════════════════════════════════════
      // GET USER WEIGHT LOGS
      // ═══════════════════════════════════════════════════
      case 'get_user_weight_logs': {
        const { user_id, limit = 30 } = params

        const { data, error } = await admin.from('weight_logs')
          .select('*')
          .eq('user_id', user_id)
          .order('logged_at', { ascending: false })
          .limit(limit)

        if (error) {
          return NextResponse.json({ error: error.message }, { status: 500 })
        }

        return NextResponse.json({ weight_logs: data || [] })
      }

      // ═══════════════════════════════════════════════════
      // GET USER NUTRITION / MEAL LOGS
      // ═══════════════════════════════════════════════════
      case 'get_user_meals': {
        const { user_id, limit = 50 } = params

        const { data, error } = await admin.from('meal_logs')
          .select('*')
          .eq('user_id', user_id)
          .order('date', { ascending: false })
          .limit(limit)

        if (error) {
          return NextResponse.json({ error: error.message }, { status: 500 })
        }

        return NextResponse.json({ meals: data || [] })
      }

      // ═══════════════════════════════════════════════════
      // GET USER HYDRATION LOGS
      // ═══════════════════════════════════════════════════
      case 'get_user_hydration': {
        const { user_id, limit = 30 } = params

        const { data, error } = await admin.from('hydration_logs')
          .select('*')
          .eq('user_id', user_id)
          .order('logged_at', { ascending: false })
          .limit(limit)

        if (error) {
          return NextResponse.json({ error: error.message }, { status: 500 })
        }

        return NextResponse.json({ hydration: data || [] })
      }

      // ═══════════════════════════════════════════════════
      // GET USER STEP DATA
      // ═══════════════════════════════════════════════════
      case 'get_user_steps': {
        const { user_id, limit = 30 } = params

        const { data, error } = await admin.from('step_tracking')
          .select('*')
          .eq('user_id', user_id)
          .order('date', { ascending: false })
          .limit(limit)

        if (error) {
          return NextResponse.json({ error: error.message }, { status: 500 })
        }

        return NextResponse.json({ steps: data || [] })
      }

      // ═══════════════════════════════════════════════════
      // GET USER CARDIO WORKOUTS
      // ═══════════════════════════════════════════════════
      case 'get_user_cardio': {
        const { user_id, limit = 20 } = params

        const { data, error } = await admin.from('cardio_workouts')
          .select('*')
          .eq('user_id', user_id)
          .order('started_at', { ascending: false })
          .limit(limit)

        if (error) {
          return NextResponse.json({ error: error.message }, { status: 500 })
        }

        return NextResponse.json({ cardio: data || [] })
      }

      // ═══════════════════════════════════════════════════
      // GET USER NOTIFICATIONS
      // ═══════════════════════════════════════════════════
      case 'get_user_notifications': {
        const { user_id, limit = 50 } = params

        const { data, error } = await admin.from('app_notifications')
          .select('*')
          .eq('user_id', user_id)
          .order('created_at', { ascending: false })
          .limit(limit)

        if (error) {
          return NextResponse.json({ error: error.message }, { status: 500 })
        }

        return NextResponse.json({ notifications: data || [] })
      }

      // ═══════════════════════════════════════════════════
      // GET USER BUG REPORTS
      // ═══════════════════════════════════════════════════
      case 'get_user_bug_reports': {
        const { user_id } = params

        const { data, error } = await admin.from('bug_reports')
          .select('*')
          .eq('user_id', user_id)
          .order('created_at', { ascending: false })

        if (error) {
          return NextResponse.json({ error: error.message }, { status: 500 })
        }

        return NextResponse.json({ bug_reports: data || [] })
      }

      // ═══════════════════════════════════════════════════
      // GET ALL BUG REPORTS (global view)
      // ═══════════════════════════════════════════════════
      case 'get_all_bug_reports': {
        const { page = 0, limit = 50 } = params

        const { data, error } = await admin.from('bug_reports')
          .select('*, user_profiles!bug_reports_user_id_fkey(name, email, username)')
          .order('created_at', { ascending: false })
          .range(page * limit, (page + 1) * limit - 1)

        if (error) {
          // Fallback without join if FK doesn't exist
          const { data: fallback } = await admin.from('bug_reports')
            .select('*')
            .order('created_at', { ascending: false })
            .range(page * limit, (page + 1) * limit - 1)

          return NextResponse.json({ bug_reports: fallback || [] })
        }

        return NextResponse.json({ bug_reports: data || [] })
      }

      // ═══════════════════════════════════════════════════
      // GET USER PROGRESS DATA
      // ═══════════════════════════════════════════════════
      case 'get_user_progress': {
        const { user_id } = params

        const { data, error } = await admin.from('user_progress')
          .select('*')
          .eq('user_id', user_id)
          .single()

        if (error && error.code !== 'PGRST116') { // PGRST116 = no rows
          return NextResponse.json({ error: error.message }, { status: 500 })
        }

        return NextResponse.json({ progress: data })
      }

      // ═══════════════════════════════════════════════════
      // GET USER EXERCISE FAVORITES
      // ═══════════════════════════════════════════════════
      case 'get_user_favorites': {
        const { user_id } = params

        const { data, error } = await admin.from('user_favorites')
          .select('*')
          .eq('user_id', user_id)

        if (error) {
          return NextResponse.json({ error: error.message }, { status: 500 })
        }

        return NextResponse.json({ favorites: data || [] })
      }

      // ═══════════════════════════════════════════════════
      // GET RECENT SIGNUPS
      // ═══════════════════════════════════════════════════
      case 'get_recent_users': {
        const { limit = 20 } = params

        const { data, error } = await admin.from('user_profiles')
          .select('id, name, email, username, profile_photo_url, fitness_goal, experience_level, has_completed_onboarding, created_at')
          .order('created_at', { ascending: false })
          .limit(limit)

        if (error) {
          return NextResponse.json({ error: error.message }, { status: 500 })
        }

        return NextResponse.json({ users: data || [] })
      }

      // ═══════════════════════════════════════════════════
      // METRICS: OVERVIEW STATS
      // ═══════════════════════════════════════════════════
      case 'metrics_overview': {
        const now = new Date()
        const d7 = new Date(now.getTime() - 7 * 86400000).toISOString()
        const d30 = new Date(now.getTime() - 30 * 86400000).toISOString()
        const d90 = new Date(now.getTime() - 90 * 86400000).toISOString()

        const [
          totalUsers, newUsers7d, newUsers30d,
          totalWorkouts, workouts7d, workouts30d,
          activeUsers7d, activeUsers30d,
          totalChallenges, activeChallenges,
          totalFriendships, totalMeals,
        ] = await Promise.all([
          admin.from('user_profiles').select('id', { count: 'exact', head: true }),
          admin.from('user_profiles').select('id', { count: 'exact', head: true }).gte('created_at', d7),
          admin.from('user_profiles').select('id', { count: 'exact', head: true }).gte('created_at', d30),
          admin.from('workouts').select('id', { count: 'exact', head: true }),
          admin.from('workouts').select('id', { count: 'exact', head: true }).gte('created_at', d7),
          admin.from('workouts').select('id', { count: 'exact', head: true }).gte('created_at', d30),
          admin.from('user_profiles').select('id', { count: 'exact', head: true }).gte('last_workout_date', d7),
          admin.from('user_profiles').select('id', { count: 'exact', head: true }).gte('last_workout_date', d30),
          admin.from('group_challenges').select('id', { count: 'exact', head: true }),
          admin.from('group_challenges').select('id', { count: 'exact', head: true }).eq('status', 'active'),
          admin.from('friendships').select('id', { count: 'exact', head: true }).eq('status', 'accepted'),
          admin.from('meal_logs').select('id', { count: 'exact', head: true }),
        ])

        // Average streak
        const { data: streakData } = await admin.from('user_profiles')
          .select('current_streak, longest_streak, total_workouts, xp')
          .gt('total_workouts', 0)

        const avgStreak = streakData && streakData.length > 0
          ? streakData.reduce((a: number, b: { current_streak: number }) => a + (b.current_streak || 0), 0) / streakData.length
          : 0
        const avgLongestStreak = streakData && streakData.length > 0
          ? streakData.reduce((a: number, b: { longest_streak: number }) => a + (b.longest_streak || 0), 0) / streakData.length
          : 0
        const avgWorkoutsPerUser = streakData && streakData.length > 0
          ? streakData.reduce((a: number, b: { total_workouts: number }) => a + (b.total_workouts || 0), 0) / streakData.length
          : 0

        // Retention: users who signed up 30+ days ago and were active in last 30 days
        const { data: oldUsers } = await admin.from('user_profiles')
          .select('id, last_workout_date')
          .lt('created_at', d30)
        const retained = oldUsers ? oldUsers.filter((u: { last_workout_date: string | null }) =>
          u.last_workout_date && new Date(u.last_workout_date) > new Date(d30)
        ).length : 0
        const retentionRate = oldUsers && oldUsers.length > 0 ? (retained / oldUsers.length) * 100 : 0

        return NextResponse.json({
          total_users: totalUsers.count || 0,
          new_users_7d: newUsers7d.count || 0,
          new_users_30d: newUsers30d.count || 0,
          total_workouts: totalWorkouts.count || 0,
          workouts_7d: workouts7d.count || 0,
          workouts_30d: workouts30d.count || 0,
          active_users_7d: activeUsers7d.count || 0,
          active_users_30d: activeUsers30d.count || 0,
          total_challenges: totalChallenges.count || 0,
          active_challenges: activeChallenges.count || 0,
          total_friendships: totalFriendships.count || 0,
          total_meals_logged: totalMeals.count || 0,
          avg_current_streak: Math.round(avgStreak * 10) / 10,
          avg_longest_streak: Math.round(avgLongestStreak * 10) / 10,
          avg_workouts_per_user: Math.round(avgWorkoutsPerUser * 10) / 10,
          retention_30d: Math.round(retentionRate * 10) / 10,
        })
      }

      // ═══════════════════════════════════════════════════
      // METRICS: USER GROWTH OVER TIME
      // ═══════════════════════════════════════════════════
      case 'metrics_user_growth': {
        const { data: users } = await admin.from('user_profiles')
          .select('created_at')
          .order('created_at', { ascending: true })

        return NextResponse.json({ users: users || [] })
      }

      // ═══════════════════════════════════════════════════
      // METRICS: WORKOUT ACTIVITY OVER TIME
      // ═══════════════════════════════════════════════════
      case 'metrics_workout_activity': {
        const { data: workouts } = await admin.from('workouts')
          .select('date, duration_seconds, xp_earned, user_id, name')
          .order('date', { ascending: true })

        return NextResponse.json({ workouts: workouts || [] })
      }

      // ═══════════════════════════════════════════════════
      // METRICS: CHALLENGE ANALYTICS
      // ═══════════════════════════════════════════════════
      case 'metrics_challenges': {
        const [challengesRes, participantsRes] = await Promise.all([
          admin.from('group_challenges')
            .select('id, title, challenge_type, mode, status, duration_days, created_at, start_date, end_date')
            .order('created_at', { ascending: false }),
          admin.from('challenge_participants')
            .select('challenge_id, user_id, status, total_progress, days_completed, current_streak')
        ])

        return NextResponse.json({
          challenges: challengesRes.data || [],
          participants: participantsRes.data || [],
        })
      }

      // ═══════════════════════════════════════════════════
      // METRICS: TOP EXERCISES
      // ═══════════════════════════════════════════════════
      case 'metrics_exercises': {
        const { data: exercises } = await admin.from('exercise_performance_history')
          .select('exercise_name, exercise_category, user_id, workout_date, total_volume, max_weight, total_sets, total_reps')
          .order('workout_date', { ascending: false })
          .limit(5000)

        return NextResponse.json({ exercises: exercises || [] })
      }

      // ═══════════════════════════════════════════════════
      // METRICS: FITNESS GOALS & LEVELS DISTRIBUTION
      // ═══════════════════════════════════════════════════
      case 'metrics_user_demographics': {
        const { data: profiles } = await admin.from('user_profiles')
          .select('fitness_goal, experience_level, gender, age, workout_environment, has_completed_onboarding, current_streak, longest_streak, total_workouts, xp, created_at, last_workout_date')

        return NextResponse.json({ profiles: profiles || [] })
      }

      // ═══════════════════════════════════════════════════
      // METRICS: NUTRITION / FOOD ANALYTICS
      // ═══════════════════════════════════════════════════
      case 'metrics_nutrition': {
        const [mealsRes, foodHistRes, foodFreqRes] = await Promise.all([
          admin.from('meal_logs')
            .select('food_name, meal_type, calories, protein, carbs, fat, date, user_id')
            .order('date', { ascending: false })
            .limit(5000),
          admin.from('user_food_history')
            .select('food_name, fdc_id, logged_at')
            .order('logged_at', { ascending: false })
            .limit(2000),
          admin.from('user_food_frequency')
            .select('food_name, log_count, last_logged_at')
            .order('log_count', { ascending: false })
            .limit(200),
        ])

        return NextResponse.json({
          meals: mealsRes.data || [],
          food_history: foodHistRes.data || [],
          food_frequency: foodFreqRes.data || [],
        })
      }

      // ═══════════════════════════════════════════════════
      // METRICS: PROGRAMS
      // ═══════════════════════════════════════════════════
      case 'metrics_programs': {
        const [activeRes, historyRes] = await Promise.all([
          admin.from('user_active_programs')
            .select('program_id, user_id, status, current_day, completed_days, total_workouts_completed, total_xp_earned'),
          admin.from('program_history')
            .select('program_id, program_name, status, days_completed, total_workouts, completion_percentage, start_date, end_date')
            .order('start_date', { ascending: false })
            .limit(500),
        ])

        return NextResponse.json({
          active_programs: activeRes.data || [],
          program_history: historyRes.data || [],
        })
      }

      // ═══════════════════════════════════════════════════
      // METRICS: SOCIAL / FRIENDSHIPS
      // ═══════════════════════════════════════════════════
      case 'metrics_social': {
        const { data: friendships } = await admin.from('friendships')
          .select('requester_id, addressee_id, status, created_at')
          .order('created_at', { ascending: true })

        const { data: sharedWorkouts } = await admin.from('shared_workouts')
          .select('id, created_at')
          .order('created_at', { ascending: false })
          .limit(1000)

        return NextResponse.json({
          friendships: friendships || [],
          shared_workouts: sharedWorkouts || [],
        })
      }

      // ═══════════════════════════════════════════════════
      // METRICS: HEALTH DATA (steps, weight, hydration)
      // ═══════════════════════════════════════════════════
      case 'metrics_health': {
        const [stepsRes, weightRes, hydrationRes, cardioRes] = await Promise.all([
          admin.from('step_tracking')
            .select('steps, date, user_id')
            .order('date', { ascending: false })
            .limit(3000),
          admin.from('weight_logs')
            .select('weight_lbs, weight_kg, logged_at, user_id')
            .order('logged_at', { ascending: false })
            .limit(2000),
          admin.from('hydration_logs')
            .select('amount_ml, logged_at, user_id')
            .order('logged_at', { ascending: false })
            .limit(2000),
          admin.from('cardio_workouts')
            .select('activity_type, duration_seconds, distance_meters, calories_burned, started_at, user_id')
            .order('started_at', { ascending: false })
            .limit(1000),
        ])

        return NextResponse.json({
          steps: stepsRes.data || [],
          weight_logs: weightRes.data || [],
          hydration: hydrationRes.data || [],
          cardio: cardioRes.data || [],
        })
      }

      // ═══════════════════════════════════════════════════
      // METRICS: STREAKS DISTRIBUTION
      // ═══════════════════════════════════════════════════
      case 'metrics_streaks': {
        const { data: profiles } = await admin.from('user_profiles')
          .select('id, name, username, current_streak, longest_streak, total_workouts, xp, last_workout_date')
          .order('current_streak', { ascending: false })

        const { data: streakTracking } = await admin.from('user_streak_tracking')
          .select('user_id, streak_type, current_streak, longest_streak, last_activity_date')

        return NextResponse.json({
          profiles: profiles || [],
          streak_tracking: streakTracking || [],
        })
      }

      // ═══════════════════════════════════════════════════
      // CRASH REPORTS: LIST (with filtering/pagination)
      // ═══════════════════════════════════════════════════
      case 'get_crash_reports': {
        const {
          status: filterStatus,
          severity: filterSeverity,
          report_type: filterType,
          search,
          offset = 0,
          app_version: filterVersion,
          fingerprint: filterFingerprint,
        } = params
        const crashLimit = safeLimit(params.limit, 200)
        const crashOffset = Math.max(0, Number(offset) || 0)

        let query = admin.from('crash_reports')
          .select('*')
          .order('created_at', { ascending: false })
          .range(crashOffset, crashOffset + crashLimit - 1)

        if (filterStatus) query = query.eq('status', filterStatus)
        if (filterSeverity) query = query.eq('severity', filterSeverity)
        if (filterType) query = query.eq('report_type', filterType)
        if (filterVersion) query = query.eq('app_version', filterVersion)
        if (filterFingerprint) query = query.eq('fingerprint', filterFingerprint)
        if (search) {
          const s = sanitizeSearch(search)
          query = query.or(`error_message.ilike.%${s}%,user_email.ilike.%${s}%,user_name.ilike.%${s}%,error_domain.ilike.%${s}%`)
        }

        const { data, error, count } = await query

        if (error) {
          return NextResponse.json({ error: error.message }, { status: 500 })
        }

        return NextResponse.json({ crash_reports: data || [], total: count })
      }

      // ═══════════════════════════════════════════════════
      // CRASH REPORTS: SINGLE DETAIL
      // ═══════════════════════════════════════════════════
      case 'get_crash_report_detail': {
        const { id } = params

        const { data, error } = await admin.from('crash_reports')
          .select('*')
          .eq('id', id)
          .single()

        if (error) {
          return NextResponse.json({ error: error.message }, { status: 500 })
        }

        return NextResponse.json({ crash_report: data })
      }

      // ═══════════════════════════════════════════════════
      // CRASH REPORTS: UPDATE STATUS / NOTES
      // ═══════════════════════════════════════════════════
      case 'update_crash_report': {
        const { id, status: newStatus, admin_notes, resolved_by } = params

        const updates: Record<string, unknown> = {}
        if (newStatus) {
          updates.status = newStatus
          if (newStatus === 'resolved') {
            updates.resolved_at = new Date().toISOString()
            updates.resolved_by = resolved_by || 'admin'
          }
        }
        if (admin_notes !== undefined) updates.admin_notes = admin_notes

        const { error } = await admin.from('crash_reports')
          .update(updates)
          .eq('id', id)

        if (error) {
          return NextResponse.json({ error: error.message }, { status: 500 })
        }

        return NextResponse.json({ success: true })
      }

      // ═══════════════════════════════════════════════════
      // CRASH REPORTS: BULK UPDATE STATUS
      // ═══════════════════════════════════════════════════
      case 'bulk_update_crash_reports': {
        const { ids, status: bulkStatus } = params

        const updates: Record<string, unknown> = { status: bulkStatus }
        if (bulkStatus === 'resolved') {
          updates.resolved_at = new Date().toISOString()
          updates.resolved_by = 'admin'
        }

        const { error } = await admin.from('crash_reports')
          .update(updates)
          .in('id', ids)

        if (error) {
          return NextResponse.json({ error: error.message }, { status: 500 })
        }

        return NextResponse.json({ success: true })
      }

      // ═══════════════════════════════════════════════════
      // CRASH REPORTS: AGGREGATED OVERVIEW / STATS
      // ═══════════════════════════════════════════════════
      case 'get_crash_overview': {
        // Fetch all crash reports for aggregation
        const [allRes, recentRes, bugRes] = await Promise.all([
          admin.from('crash_reports')
            .select('id, report_type, severity, status, fingerprint, error_domain, app_version, created_at, error_message, user_id')
            .order('created_at', { ascending: false })
            .limit(5000),
          admin.from('crash_reports')
            .select('id, report_type, severity, status, fingerprint, error_domain, app_version, created_at, error_message, user_id, user_email, user_name, device_model')
            .order('created_at', { ascending: false })
            .limit(50),
          admin.from('bug_reports')
            .select('*')
            .order('created_at', { ascending: false })
            .limit(200),
        ])

        const all = allRes.data || []
        const recent = recentRes.data || []
        const bugs = bugRes.data || []

        // Status breakdown
        const statusCounts: Record<string, number> = {}
        const severityCounts: Record<string, number> = {}
        const typeCounts: Record<string, number> = {}
        const domainCounts: Record<string, number> = {}
        const versionCounts: Record<string, number> = {}
        const fingerprintGroups: Record<string, { count: number; message: string; severity: string; domain: string; latest: string; status: string }> = {}
        const uniqueUsers = new Set<string>()

        // Daily trend (last 30 days)
        const now = new Date()
        const thirtyDaysAgo = new Date(now.getTime() - 30 * 24 * 60 * 60 * 1000)
        const dailyCounts: Record<string, number> = {}

        for (const r of all) {
          statusCounts[r.status] = (statusCounts[r.status] || 0) + 1
          severityCounts[r.severity] = (severityCounts[r.severity] || 0) + 1
          typeCounts[r.report_type] = (typeCounts[r.report_type] || 0) + 1
          if (r.error_domain) domainCounts[r.error_domain] = (domainCounts[r.error_domain] || 0) + 1
          if (r.app_version) versionCounts[r.app_version] = (versionCounts[r.app_version] || 0) + 1
          if (r.user_id) uniqueUsers.add(r.user_id)

          // Fingerprint grouping
          if (!fingerprintGroups[r.fingerprint]) {
            fingerprintGroups[r.fingerprint] = {
              count: 0,
              message: r.error_message?.substring(0, 200) || 'Unknown',
              severity: r.severity,
              domain: r.error_domain || 'Unknown',
              latest: r.created_at,
              status: r.status,
            }
          }
          fingerprintGroups[r.fingerprint].count++
          if (r.created_at > fingerprintGroups[r.fingerprint].latest) {
            fingerprintGroups[r.fingerprint].latest = r.created_at
            fingerprintGroups[r.fingerprint].status = r.status
          }

          // Daily trend
          const created = new Date(r.created_at)
          if (created >= thirtyDaysAgo) {
            const day = r.created_at.substring(0, 10)
            dailyCounts[day] = (dailyCounts[day] || 0) + 1
          }
        }

        // Sort fingerprint groups by count
        const topIssues = Object.entries(fingerprintGroups)
          .map(([fp, data]) => ({ fingerprint: fp, ...data }))
          .sort((a, b) => b.count - a.count)
          .slice(0, 20)

        // Build daily trend array
        const dailyTrend = []
        for (let d = new Date(thirtyDaysAgo); d <= now; d.setDate(d.getDate() + 1)) {
          const key = d.toISOString().substring(0, 10)
          dailyTrend.push({ date: key, count: dailyCounts[key] || 0 })
        }

        return NextResponse.json({
          total_crash_reports: all.length,
          total_bug_reports: bugs.length,
          affected_users: uniqueUsers.size,
          status_counts: statusCounts,
          severity_counts: severityCounts,
          type_counts: typeCounts,
          domain_counts: domainCounts,
          version_counts: versionCounts,
          top_issues: topIssues,
          daily_trend: dailyTrend,
          recent_reports: recent,
          bug_reports: bugs,
        })
      }

      // ═══════════════════════════════════════════════════
      // BUG REPORTS: LIST (user-submitted via rage shake)
      // ═══════════════════════════════════════════════════
      case 'get_bug_reports': {
        const { status: bugStatus, limit: bugLimit = 100 } = params

        let query = admin.from('bug_reports')
          .select('*')
          .order('created_at', { ascending: false })
          .limit(bugLimit)

        if (bugStatus) query = query.eq('status', bugStatus)

        const { data, error } = await query

        if (error) {
          return NextResponse.json({ error: error.message }, { status: 500 })
        }

        return NextResponse.json({ bug_reports: data || [] })
      }

      // ═══════════════════════════════════════════════════
      // BUG REPORTS: UPDATE STATUS
      // ═══════════════════════════════════════════════════
      case 'update_bug_report': {
        const { id, status: newBugStatus } = params

        const { error } = await admin.from('bug_reports')
          .update({ status: newBugStatus })
          .eq('id', id)

        if (error) {
          return NextResponse.json({ error: error.message }, { status: 500 })
        }

        return NextResponse.json({ success: true })
      }

      // ═══════════════════════════════════════════════════
      // CRASH REPORTS: DELETE SINGLE
      // ═══════════════════════════════════════════════════
      case 'delete_crash_report': {
        const { id } = params

        const { error } = await admin.from('crash_reports')
          .delete()
          .eq('id', id)

        if (error) {
          return NextResponse.json({ error: error.message }, { status: 500 })
        }

        return NextResponse.json({ success: true })
      }

      // ═══════════════════════════════════════════════════
      // CRASH REPORTS: BULK DELETE
      // ═══════════════════════════════════════════════════
      case 'bulk_delete_crash_reports': {
        const { ids } = params

        const { error } = await admin.from('crash_reports')
          .delete()
          .in('id', ids)

        if (error) {
          return NextResponse.json({ error: error.message }, { status: 500 })
        }

        return NextResponse.json({ success: true, deleted: ids.length })
      }

      // ═══════════════════════════════════════════════════
      // BUG REPORTS: DELETE
      // ═══════════════════════════════════════════════════
      case 'delete_bug_report': {
        const { id } = params

        const { error } = await admin.from('bug_reports')
          .delete()
          .eq('id', id)

        if (error) {
          return NextResponse.json({ error: error.message }, { status: 500 })
        }

        return NextResponse.json({ success: true })
      }

      // ═══════════════════════════════════════════════════
      // CRASH REPORTS: DELETE ALL RESOLVED
      // ═══════════════════════════════════════════════════
      case 'delete_resolved_crash_reports': {
        const { error } = await admin.from('crash_reports')
          .delete()
          .in('status', ['resolved', 'wont_fix', 'duplicate'])

        if (error) {
          return NextResponse.json({ error: error.message }, { status: 500 })
        }

        return NextResponse.json({ success: true })
      }

      // ═══════════════════════════════════════════════════
      // AI INSIGHTS
      // ═══════════════════════════════════════════════════
      case 'get_ai_insights': {
        const limit = safeLimit(params.limit, 50)
        const category = params.category as string | undefined
        const status = params.status as string | undefined

        let query = admin.from('ai_insights')
          .select('*')
          .order('generated_at', { ascending: false })
          .limit(limit)

        if (category) query = query.eq('category', category)
        if (status) query = query.eq('status', status)

        const { data, error } = await query
        if (error) return NextResponse.json({ error: error.message }, { status: 500 })
        return NextResponse.json({ insights: data })
      }

      case 'update_insight_status': {
        const { id, newStatus } = params as { id: string; newStatus: string }
        if (!id || !newStatus) {
          return NextResponse.json({ error: 'Missing id or newStatus' }, { status: 400 })
        }
        const validStatuses = ['new', 'read', 'archived']
        if (!validStatuses.includes(newStatus)) {
          return NextResponse.json({ error: 'Invalid status' }, { status: 400 })
        }

        const { error } = await admin.from('ai_insights')
          .update({ status: newStatus })
          .eq('id', id)

        if (error) return NextResponse.json({ error: error.message }, { status: 500 })
        return NextResponse.json({ success: true })
      }

      case 'trigger_insights_generation': {
        const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL!
        const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY!

        const res = await fetch(`${supabaseUrl}/functions/v1/generate-ai-insights`, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${serviceKey}`,
          },
          body: JSON.stringify({ action: 'generate_weekly' }),
        })

        if (!res.ok) {
          const errText = await res.text()
          return NextResponse.json({ error: `Edge function failed: ${errText}` }, { status: 500 })
        }

        const result = await res.json()
        return NextResponse.json(result)
      }

      // ═══════════════════════════════════════════════════
      // AI CHAT HISTORY
      // ═══════════════════════════════════════════════════
      case 'get_chat_history': {
        const { data, error } = await admin.from('ai_chat_history')
          .select('id, title, created_at, updated_at')
          .eq('admin_user_id', adminAuth.userId!)
          .order('updated_at', { ascending: false })
          .limit(20)

        if (error) return NextResponse.json({ error: error.message }, { status: 500 })
        return NextResponse.json({ conversations: data })
      }

      case 'get_chat_conversation': {
        const { conversationId } = params as { conversationId: string }
        if (!conversationId) {
          return NextResponse.json({ error: 'Missing conversationId' }, { status: 400 })
        }

        const { data, error } = await admin.from('ai_chat_history')
          .select('*')
          .eq('id', conversationId)
          .eq('admin_user_id', adminAuth.userId!)
          .single()

        if (error) return NextResponse.json({ error: error.message }, { status: 500 })
        return NextResponse.json({ conversation: data })
      }

      case 'save_chat_conversation': {
        const { conversationId, title, messages } = params as {
          conversationId?: string; title: string; messages: unknown[]
        }

        if (conversationId) {
          const { error } = await admin.from('ai_chat_history')
            .update({ messages, title, updated_at: new Date().toISOString() })
            .eq('id', conversationId)
            .eq('admin_user_id', adminAuth.userId!)
          if (error) return NextResponse.json({ error: error.message }, { status: 500 })
          return NextResponse.json({ id: conversationId })
        } else {
          const { data, error } = await admin.from('ai_chat_history')
            .insert({
              admin_user_id: adminAuth.userId!,
              title,
              messages,
            })
            .select('id')
            .single()
          if (error) return NextResponse.json({ error: error.message }, { status: 500 })
          return NextResponse.json({ id: data.id })
        }
      }

      case 'delete_chat_conversation': {
        const { conversationId } = params as { conversationId: string }
        if (!conversationId) {
          return NextResponse.json({ error: 'Missing conversationId' }, { status: 400 })
        }
        const { error } = await admin.from('ai_chat_history')
          .delete()
          .eq('id', conversationId)
          .eq('admin_user_id', adminAuth.userId!)

        if (error) return NextResponse.json({ error: error.message }, { status: 500 })
        return NextResponse.json({ success: true })
      }

      // ═══════════════════════════════════════════════════
      // DEV LOGGING ACTIONS
      // ═══════════════════════════════════════════════════

      case 'get_dev_logging_users': {
        const { data, error } = await admin.from('dev_logging_users')
          .select('*, user_profiles(name, email, username)')
          .order('created_at', { ascending: false })
        if (error) return NextResponse.json({ error: error.message }, { status: 500 })
        return NextResponse.json({ users: data })
      }

      case 'toggle_dev_logging': {
        const { user_id, enabled } = params as { user_id: string; enabled: boolean }
        if (!user_id) return NextResponse.json({ error: 'Missing user_id' }, { status: 400 })

        if (enabled) {
          const { error } = await admin.from('dev_logging_users')
            .upsert({ user_id, enabled: true, enabled_by: adminAuth.email, updated_at: new Date().toISOString() }, { onConflict: 'user_id' })
          if (error) return NextResponse.json({ error: error.message }, { status: 500 })
        } else {
          const { error } = await admin.from('dev_logging_users')
            .update({ enabled: false, updated_at: new Date().toISOString() })
            .eq('user_id', user_id)
          if (error) return NextResponse.json({ error: error.message }, { status: 500 })
        }
        return NextResponse.json({ success: true })
      }

      case 'get_dev_sessions': {
        const { user_id } = params as { user_id?: string }
        let query = admin.from('dev_session_logs')
          .select('session_id, user_id, device_info, created_at, batch_index')
          .order('created_at', { ascending: false })
          .limit(100)
        if (user_id) query = query.eq('user_id', user_id)

        const { data, error } = await query
        if (error) return NextResponse.json({ error: error.message }, { status: 500 })

        const sessions = new Map<string, { session_id: string; user_id: string; device_info: unknown; started_at: string; batch_count: number }>()
        for (const row of (data || [])) {
          if (!sessions.has(row.session_id)) {
            sessions.set(row.session_id, {
              session_id: row.session_id,
              user_id: row.user_id,
              device_info: row.device_info,
              started_at: row.created_at,
              batch_count: 1,
            })
          } else {
            sessions.get(row.session_id)!.batch_count++
          }
        }
        return NextResponse.json({ sessions: Array.from(sessions.values()) })
      }

      case 'get_dev_session_entries': {
        const { session_id } = params as { session_id: string }
        if (!session_id) return NextResponse.json({ error: 'Missing session_id' }, { status: 400 })

        const { data, error } = await admin.from('dev_session_logs')
          .select('*')
          .eq('session_id', session_id)
          .order('batch_index', { ascending: true })
        if (error) return NextResponse.json({ error: error.message }, { status: 500 })
        return NextResponse.json({ batches: data })
      }

      case 'get_dev_suggestions': {
        const { session_id } = params as { session_id?: string }
        let query = admin.from('dev_log_suggestions')
          .select('*')
          .order('created_at', { ascending: false })
        if (session_id) query = query.eq('session_id', session_id)

        const { data, error } = await query
        if (error) return NextResponse.json({ error: error.message }, { status: 500 })
        return NextResponse.json({ suggestions: data })
      }

      case 'update_suggestion_status': {
        const { suggestion_id, status: newStatus, pr_url, pr_branch } = params as {
          suggestion_id: string; status: string; pr_url?: string; pr_branch?: string
        }
        const update: Record<string, unknown> = { status: newStatus }
        if (pr_url) update.pr_url = pr_url
        if (pr_branch) update.pr_branch = pr_branch

        const { error } = await admin.from('dev_log_suggestions')
          .update(update)
          .eq('id', suggestion_id)
        if (error) return NextResponse.json({ error: error.message }, { status: 500 })
        return NextResponse.json({ success: true })
      }

      // ═══════════════════════════════════════════════════
      // BUG INTELLIGENCE (Phase 2)
      // Driven by supabase/functions/triage-bugs + bug_intelligence_* tables.
      // All actions below are read-only except `update_bug_fingerprint`,
      // `update_bug_report_review`, and `trigger_bug_triage` which mutate.
      // ═══════════════════════════════════════════════════

      case 'get_bug_intelligence_overview': {
        const since24h = new Date(Date.now() - 24 * 3600_000).toISOString()
        const since7d  = new Date(Date.now() - 7 * 24 * 3600_000).toISOString()

        const [
          { data: statusCounts },
          { data: severityCounts },
          { data: recentTrends },
          { data: pendingReports },
          { data: sourceCounts },
        ] = await Promise.all([
          admin.from('bug_intelligence_fingerprints').select('status'),
          admin.from('bug_intelligence_reports').select('severity').gte('created_at', since7d),
          admin.from('bug_intelligence_trends').select('id, trend_type, detected_at, reviewed_at')
            .gte('detected_at', since24h)
            .order('detected_at', { ascending: false }),
          admin.from('bug_intelligence_reports').select('id').eq('review_status', 'pending'),
          // Phase 6: split the inbox by origin so the CMS can show a
          // tri-category breakdown (crash / log / shake).
          admin.from('bug_intelligence_fingerprints').select('source'),
        ])

        const statusMap: Record<string, number> = {}
        for (const r of (statusCounts || []) as Array<{ status: string }>) {
          statusMap[r.status] = (statusMap[r.status] || 0) + 1
        }
        const severityMap: Record<string, number> = {}
        for (const r of (severityCounts || []) as Array<{ severity: string }>) {
          severityMap[r.severity] = (severityMap[r.severity] || 0) + 1
        }
        const sourceMap: Record<string, number> = {}
        for (const r of (sourceCounts || []) as Array<{ source: string }>) {
          sourceMap[r.source] = (sourceMap[r.source] || 0) + 1
        }

        return NextResponse.json({
          overview: {
            fingerprints_by_status: statusMap,
            fingerprints_by_source: sourceMap,
            reports_last_7d_by_severity: severityMap,
            trends_last_24h: recentTrends || [],
            pending_reports_count: (pendingReports || []).length,
          },
        })
      }

      case 'get_bug_intelligence_metrics': {
        const { data, error } = await admin
          .from('v_bug_intelligence_metrics')
          .select('*')
        if (error) return NextResponse.json({ error: error.message }, { status: 500 })
        return NextResponse.json({ metrics: data || [] })
      }

      case 'get_bug_intelligence_fingerprints': {
        const { status: filterStatus, agent, severity_min, search, source, limit: pageLimit } = params as {
          status?: string; agent?: string; severity_min?: string; search?: string; source?: string; limit?: number
        }
        let query = admin.from('bug_intelligence_fingerprints')
          .select('*')
          .order('last_seen_at', { ascending: false })
          .limit(Math.min(pageLimit ?? 200, 500))
        if (filterStatus && filterStatus !== 'all') query = query.eq('status', filterStatus)
        if (agent && agent !== 'all') query = query.eq('assigned_agent', agent)
        if (search) query = query.ilike('sample_message', `%${search}%`)
        // Source filter: 'log' | 'crash' | 'shake' (new Phase 6 shake bugs).
        // `bug_intelligence_fingerprints.source` is free-text, so we just pass through.
        if (source && source !== 'all') query = query.eq('source', source)

        const { data, error } = await query
        if (error) return NextResponse.json({ error: error.message }, { status: 500 })

        // Attach latest report summary per fingerprint for the list view.
        const fingerprints = (data || []) as Array<{ fingerprint: string }>
        if (fingerprints.length === 0) return NextResponse.json({ fingerprints: [] })

        const { data: latestReports } = await admin
          .from('bug_intelligence_reports')
          .select('fingerprint, severity, confidence, agent_owner, title, review_status, created_at, id')
          .in('fingerprint', fingerprints.map(f => f.fingerprint))
          .order('created_at', { ascending: false })

        const latestByFp = new Map<string, unknown>()
        for (const r of (latestReports || []) as Array<{ fingerprint: string }>) {
          if (!latestByFp.has(r.fingerprint)) latestByFp.set(r.fingerprint, r)
        }

        const enriched = (data || []).map((fp: Record<string, unknown>) => ({
          ...fp,
          latest_report: latestByFp.get(fp.fingerprint as string) ?? null,
        }))

        if (severity_min) {
          const severityOrder: Record<string, number> = { critical: 1, high: 2, medium: 3, low: 4 }
          const cutoff = severityOrder[severity_min] ?? 4
          const filtered = enriched.filter(fp => {
            const sev = (fp.latest_report as { severity?: string } | null)?.severity
            return sev ? (severityOrder[sev] ?? 5) <= cutoff : false
          })
          return NextResponse.json({ fingerprints: filtered })
        }

        return NextResponse.json({ fingerprints: enriched })
      }

      case 'get_bug_intelligence_reports': {
        const { fingerprint } = params as { fingerprint: string }
        if (!fingerprint) return NextResponse.json({ error: 'Missing fingerprint' }, { status: 400 })

        const { data, error } = await admin.from('bug_intelligence_reports')
          .select('*')
          .eq('fingerprint', fingerprint)
          .order('created_at', { ascending: false })
        if (error) return NextResponse.json({ error: error.message }, { status: 500 })
        return NextResponse.json({ reports: data || [] })
      }

      // Cursor handoff export — bundles every report matching the filter
      // alongside its fingerprint context (occurrence counts, affected
      // screens, versions, etc.) AND a single representative crash row
      // (stack_trace / symbolicated_stack_trace / breadcrumbs /
      // session_log_snippet) when the fingerprint is crash-sourced. The
      // resulting markdown is meant to be pasted into a Cursor chat to
      // ask the assistant to execute Claude's proposed fixes with real
      // repo context. Keep the shape stable — the client-side formatter
      // depends on it.
      case 'get_bug_intelligence_export': {
        const {
          review_status: reviewFilter,
          severity_min,
          agent,
          include_merged,
        } = params as {
          review_status?: string   // default 'pending'
          severity_min?: string    // 'critical' / 'high' / 'medium' / 'low'
          agent?: string           // valid agent_owner or 'all'
          include_merged?: boolean // default false (noise after they've landed)
        }

        // 1. Fetch reports matching the filter. Default: all pending.
        let repQuery = admin.from('bug_intelligence_reports')
          .select('*')
          .order('severity', { ascending: true })
          .order('confidence', { ascending: false })
          .order('created_at', { ascending: false })
          .limit(200)

        if (reviewFilter && reviewFilter !== 'all') {
          repQuery = repQuery.eq('review_status', reviewFilter)
        } else if (!include_merged) {
          repQuery = repQuery.in('review_status', ['pending', 'approved'])
        }
        if (agent && agent !== 'all') repQuery = repQuery.eq('agent_owner', agent)
        if (severity_min) {
          const ORDER: Record<string, string[]> = {
            critical: ['critical'],
            high: ['critical', 'high'],
            medium: ['critical', 'high', 'medium'],
            low: ['critical', 'high', 'medium', 'low'],
          }
          const allowed = ORDER[severity_min] ?? ORDER.medium
          repQuery = repQuery.in('severity', allowed)
        }

        const { data: reports, error: repErr } = await repQuery
        if (repErr) return NextResponse.json({ error: repErr.message }, { status: 500 })
        const reportRows = (reports || []) as Array<{
          fingerprint: string
          id: string
          [k: string]: unknown
        }>
        if (reportRows.length === 0) {
          return NextResponse.json({
            export: {
              generated_at: new Date().toISOString(),
              bundle_count: 0,
              bundles: [],
            },
          })
        }

        // 2. Pull their fingerprint context in a single IN query.
        const fps = Array.from(new Set(reportRows.map(r => r.fingerprint)))
        const { data: fpRows, error: fpErr } = await admin
          .from('bug_intelligence_fingerprints')
          .select('*')
          .in('fingerprint', fps)
        if (fpErr) return NextResponse.json({ error: fpErr.message }, { status: 500 })
        const fpById = new Map<string, Record<string, unknown>>()
        for (const f of (fpRows || [])) {
          fpById.set((f as { fingerprint: string }).fingerprint, f as Record<string, unknown>)
        }

        // 3. For every crash-sourced fingerprint, pull ONE representative
        // crash row so Cursor gets real stack_trace / symbolicated_stack_trace
        // / breadcrumbs / session_log_snippet evidence. We pick the most
        // recent crash for each fingerprint so the snippet reflects
        // current app state.
        const crashFps = fps.filter(fp => {
          const row = fpById.get(fp) as { source?: string } | undefined
          return row?.source === 'crash'
        })
        const crashExample = new Map<string, Record<string, unknown>>()
        if (crashFps.length > 0) {
          // Single query, distinct-on-style is awkward in PostgREST — pull
          // recent crashes ordered desc, take first per fingerprint
          // client-side. Bounded to 5x fingerprint count which is plenty
          // for this use — pending queues stay small.
          const { data: crashes } = await admin
            .from('crash_reports')
            .select(
              'id, bi_fingerprint, error_message, error_domain, stack_trace, ' +
              'symbolicated_stack_trace, symbolication_status, breadcrumbs, ' +
              'session_log_snippet, current_screen, app_version, build_number, ' +
              'device_model, os_version, occurred_at, session_id',
            )
            .in('bi_fingerprint', crashFps)
            .order('created_at', { ascending: false })
            .limit(crashFps.length * 5)

          for (const c of ((crashes ?? []) as unknown as Array<{ bi_fingerprint: string }>)) {
            if (!crashExample.has(c.bi_fingerprint)) {
              crashExample.set(c.bi_fingerprint, c as unknown as Record<string, unknown>)
            }
          }
        }

        // 4. For every SHAKE-sourced fingerprint, pull the original
        // bug_reports row (user description, expected behavior, screen,
        // likely_source_files, severity the user picked) PLUS a PII-stripped
        // user_profile snapshot so Cursor has the same context Claude had.
        // Triage-only fields: we deliberately DROP user_id / user_email /
        // display_name / screenshot_base64 from the export (the .md lands in
        // GitHub PR bodies and MASTER_TODO so it must stay PII-free).
        const shakeFps = fps.filter(fp => {
          const row = fpById.get(fp) as { source?: string } | undefined
          return row?.source === 'shake'
        })
        const shakeExample = new Map<string, Record<string, unknown>>()
        if (shakeFps.length > 0) {
          const shakeReportIds = reportRows
            .filter(r => {
              const fp = fpById.get(r.fingerprint) as { source?: string } | undefined
              return fp?.source === 'shake'
            })
            .map(r => r.id as string)

          if (shakeReportIds.length > 0) {
            const { data: shakes } = await admin
              .from('bug_reports')
              .select(
                'id, user_id, triage_report_id, description, expected_behavior, ' +
                'additional_info, reproduces_every_time, screen_name, ' +
                'likely_source_files, severity, bug_category, screenshot_base64, ' +
                'device_model, os_version, app_version, created_at',
              )
              .in('triage_report_id', shakeReportIds)

            const shakeRows = (shakes ?? []) as Array<{
              id: string
              user_id: string | null
              triage_report_id: string | null
              screenshot_base64: string | null
              description: string
              expected_behavior: string | null
              additional_info: string | null
              reproduces_every_time: boolean
              screen_name: string | null
              likely_source_files: string[] | null
              severity: string
              bug_category: string | null
              device_model: string | null
              os_version: string | null
              app_version: string | null
              created_at: string
            }>

            // Re-fetch minimal, PII-stripped user_profiles for context —
            // same fields the edge function sends to Claude, minus email/name.
            const userIds = Array.from(new Set(
              shakeRows.map(s => s.user_id).filter((x): x is string => !!x),
            ))
            const profileById = new Map<string, Record<string, unknown>>()
            if (userIds.length > 0) {
              const { data: profiles } = await admin
                .from('user_profiles')
                .select(
                  'id, created_at, has_completed_onboarding, experience_level, ' +
                  'strength_level, fitness_goal, available_days, equipment, ' +
                  'total_workouts, current_streak, is_verified, is_gold_verified, ' +
                  'weight_unit, height_unit, distance_unit',
                )
                .in('id', userIds)
              for (const p of ((profiles ?? []) as Array<Record<string, unknown>>)) {
                profileById.set(String(p.id), p)
              }
            }

            for (const s of shakeRows) {
              if (!s.triage_report_id) continue
              const p = s.user_id ? profileById.get(s.user_id) ?? null : null
              let accountAgeDays: number | null = null
              if (p && typeof p.created_at === 'string') {
                const ts = Date.parse(p.created_at)
                if (!Number.isNaN(ts)) {
                  accountAgeDays = Math.max(0, Math.floor((Date.now() - ts) / 86_400_000))
                }
              }
              const userContext = p ? {
                account_age_days: accountAgeDays,
                has_completed_onboarding: p.has_completed_onboarding ?? null,
                experience_level: p.experience_level ?? null,
                strength_level: p.strength_level ?? null,
                fitness_goal: p.fitness_goal ?? null,
                available_days: p.available_days ?? null,
                equipment_count: Array.isArray(p.equipment) ? p.equipment.length : null,
                total_workouts: p.total_workouts ?? null,
                current_streak: p.current_streak ?? null,
                is_verified: p.is_verified ?? null,
                is_gold_verified: p.is_gold_verified ?? null,
                weight_unit: p.weight_unit ?? null,
                height_unit: p.height_unit ?? null,
                distance_unit: p.distance_unit ?? null,
              } : null

              shakeExample.set(s.triage_report_id, {
                description: s.description,
                expected_behavior: s.expected_behavior,
                additional_info: s.additional_info,
                reproduces_every_time: s.reproduces_every_time,
                screen_name: s.screen_name,
                likely_source_files: s.likely_source_files ?? [],
                user_severity: s.severity,
                bug_category: s.bug_category,
                screenshot_attached: !!(s.screenshot_base64 && s.screenshot_base64.length > 0),
                device_model: s.device_model,
                os_version: s.os_version,
                app_version: s.app_version,
                submitted_at: s.created_at,
                user_context: userContext,
              })
            }
          }
        }

        // 5. Assemble bundles in the same order the reports came back
        // (severity asc, confidence desc, created_at desc).
        const bundles = reportRows.map((r) => ({
          fingerprint: fpById.get(r.fingerprint) || null,
          report: r,
          example_crash: crashExample.get(r.fingerprint) || null,
          example_shake: shakeExample.get(r.id as string) || null,
        }))

        return NextResponse.json({
          export: {
            generated_at: new Date().toISOString(),
            filters: {
              review_status: reviewFilter ?? 'pending',
              severity_min: severity_min ?? null,
              agent: agent ?? 'all',
              include_merged: !!include_merged,
            },
            bundle_count: bundles.length,
            bundles,
          },
        })
      }

      case 'get_bug_intelligence_trends': {
        const { fingerprint } = params as { fingerprint?: string }
        let query = admin.from('bug_intelligence_trends')
          .select('*')
          .order('detected_at', { ascending: false })
          .limit(200)
        if (fingerprint) query = query.eq('fingerprint', fingerprint)
        const { data, error } = await query
        if (error) return NextResponse.json({ error: error.message }, { status: 500 })
        return NextResponse.json({ trends: data || [] })
      }

      case 'update_bug_fingerprint': {
        const { fingerprint, status: newStatus, assigned_agent, resolution_pr_url, pain_point_id } = params as {
          fingerprint: string
          status?: string
          assigned_agent?: string
          resolution_pr_url?: string
          pain_point_id?: string
        }
        if (!fingerprint) return NextResponse.json({ error: 'Missing fingerprint' }, { status: 400 })

        const update: Record<string, unknown> = { updated_at: new Date().toISOString() }
        if (newStatus) update.status = newStatus
        if (assigned_agent !== undefined) update.assigned_agent = assigned_agent || null
        if (resolution_pr_url !== undefined) update.resolution_pr_url = resolution_pr_url || null
        if (pain_point_id !== undefined) update.pain_point_id = pain_point_id || null
        if (newStatus === 'resolved') update.resolved_at = new Date().toISOString()

        const { error } = await admin.from('bug_intelligence_fingerprints')
          .update(update)
          .eq('fingerprint', fingerprint)
        if (error) return NextResponse.json({ error: error.message }, { status: 500 })
        return NextResponse.json({ success: true })
      }

      case 'update_bug_report_review': {
        const { report_id, review_status: newReview, pr_url, pr_branch } = params as {
          report_id: string; review_status: string; pr_url?: string; pr_branch?: string
        }
        if (!report_id || !newReview) {
          return NextResponse.json({ error: 'Missing report_id or review_status' }, { status: 400 })
        }
        const update: Record<string, unknown> = {
          review_status: newReview,
          reviewed_by: adminAuth.userId,
          reviewed_at: new Date().toISOString(),
        }
        if (pr_url) update.pr_url = pr_url
        if (pr_branch) update.pr_branch = pr_branch

        const { error } = await admin.from('bug_intelligence_reports')
          .update(update)
          .eq('id', report_id)
        if (error) return NextResponse.json({ error: error.message }, { status: 500 })
        return NextResponse.json({ success: true })
      }

      case 'trigger_bug_triage': {
        const { fingerprints } = params as { fingerprints?: string[] }
        const url = process.env.NEXT_PUBLIC_SUPABASE_URL
        const key = process.env.SUPABASE_SERVICE_ROLE_KEY
        if (!url || !key) return NextResponse.json({ error: 'Supabase config missing' }, { status: 500 })

        const res = await fetch(`${url}/functions/v1/triage-bugs`, {
          method: 'POST',
          headers: {
            'Authorization': `Bearer ${key}`,
            'x-cron-key': key,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({ source: 'manual', fingerprints: fingerprints || undefined }),
        })
        const text = await res.text()
        let parsed: unknown = text
        try { parsed = JSON.parse(text) } catch {}
        return NextResponse.json({ ok: res.ok, status: res.status, result: parsed })
      }

      // Manual "Triage shake reports now" — same shape as trigger_bug_triage
      // but calls the Phase 6 edge function for rage-shake rows.
      // `report_ids` is optional; if omitted the edge function drains the
      // `triage_status='pending'` queue (up to MAX_REPORTS_PER_RUN).
      case 'trigger_shake_triage': {
        const { report_ids } = params as { report_ids?: string[] }
        const url = process.env.NEXT_PUBLIC_SUPABASE_URL
        const key = process.env.SUPABASE_SERVICE_ROLE_KEY
        if (!url || !key) return NextResponse.json({ error: 'Supabase config missing' }, { status: 500 })

        const res = await fetch(`${url}/functions/v1/triage-shake-reports`, {
          method: 'POST',
          headers: {
            'Authorization': `Bearer ${key}`,
            'x-cron-key': key,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({ source: 'manual', report_ids: report_ids || undefined }),
        })
        const text = await res.text()
        let parsed: unknown = text
        try { parsed = JSON.parse(text) } catch {}
        return NextResponse.json({ ok: res.ok, status: res.status, result: parsed })
      }

      // Rage-shake inbox for the CMS. Returns all bug_reports with their
      // linked Claude report (if any). Used by /bug-intelligence so shake
      // submissions show up alongside fingerprinted crash/log bugs.
      case 'get_shake_inbox': {
        const { status } = params as { status?: string }
        let q = admin.from('bug_reports')
          .select(
            'id, user_id, user_name, user_email, description, expected_behavior, ' +
            'reproduces_every_time, additional_info, screen_name, ' +
            'severity, bug_category, likely_source_files, ' +
            'triage_status, triage_report_id, triaged_at, triage_error, ' +
            'device_model, os_version, app_version, status, created_at',
          )
          .order('created_at', { ascending: false })
          .limit(100)
        if (status && status !== 'all') {
          q = q.eq('triage_status', status)
        }
        const { data: shake, error: shakeErr } = await q
        if (shakeErr) return NextResponse.json({ error: shakeErr.message }, { status: 500 })
        const shakeRows = (shake ?? []) as unknown as Array<{ triage_report_id: string | null }>

        // Fetch linked Claude reports in one roundtrip.
        const reportIds = shakeRows
          .map((s) => s.triage_report_id)
          .filter((x): x is string => !!x)
        const reportsById: Record<string, Record<string, unknown>> = {}
        if (reportIds.length > 0) {
          const { data: reps } = await admin.from('bug_intelligence_reports')
            .select('id, agent_owner, severity, confidence, title, summary, file_path, code_diff, review_status, pr_url')
            .in('id', reportIds)
          for (const r of ((reps || []) as Array<Record<string, unknown>>)) {
            reportsById[String(r.id)] = r
          }
        }
        return NextResponse.json({
          inbox: shakeRows.map((s) => ({
            ...s,
            linked_report: s.triage_report_id
              ? (reportsById[s.triage_report_id] || null)
              : null,
          })),
        })
      }

      // ═══════════════════════════════════════════════════
      // FAQ MANAGEMENT
      // ═══════════════════════════════════════════════════

      case 'get_faq_categories': {
        const { data, error } = await admin.from('faq_categories')
          .select('*, faq_entries(count)')
          .order('display_order')
        if (error) return NextResponse.json({ error: error.message }, { status: 500 })
        const categories = (data || []).map((c: Record<string, unknown>) => ({
          ...c,
          entry_count: Array.isArray(c.faq_entries) && c.faq_entries.length > 0
            ? (c.faq_entries[0] as { count: number }).count
            : 0,
        }))
        return NextResponse.json({ categories })
      }

      case 'get_faq_entries': {
        const { category_id, status: filterStatus, search } = params as {
          category_id?: string; status?: string; search?: string
        }
        let query = admin.from('faq_entries')
          .select('*, faq_categories(slug, name)')
          .order('display_order')
        if (category_id) query = query.eq('category_id', category_id)
        if (filterStatus && filterStatus !== 'all') query = query.eq('status', filterStatus)
        if (search) query = query.or(`question.ilike.%${search}%,answer.ilike.%${search}%`)
        const { data, error } = await query
        if (error) return NextResponse.json({ error: error.message }, { status: 500 })
        return NextResponse.json({ entries: data || [] })
      }

      case 'create_faq_entry': {
        const { entry_id, category_id, question, answer, keywords, channel, status: entryStatus } = params as {
          entry_id: string; category_id: string; question: string; answer: string
          keywords?: string[]; channel?: string; status?: string
        }
        const { data, error } = await admin.from('faq_entries').insert({
          entry_id, category_id, question, answer,
          keywords: keywords || [],
          channel: channel || 'both',
          status: entryStatus || 'draft',
        }).select().single()
        if (error) return NextResponse.json({ error: error.message }, { status: 500 })
        return NextResponse.json({ entry: data })
      }

      case 'update_faq_entry': {
        const { id: faqId, ...updates } = params as {
          id: string; question?: string; answer?: string; status?: string
          display_order?: number; keywords?: string[]; channel?: string; entry_id?: string
        }
        const { error } = await admin.from('faq_entries')
          .update({ ...updates, updated_at: new Date().toISOString() })
          .eq('id', faqId)
        if (error) return NextResponse.json({ error: error.message }, { status: 500 })
        return NextResponse.json({ success: true })
      }

      case 'delete_faq_entry': {
        const { id: delId } = params as { id: string }
        const { error } = await admin.from('faq_entries').delete().eq('id', delId)
        if (error) return NextResponse.json({ error: error.message }, { status: 500 })
        return NextResponse.json({ success: true })
      }

      case 'publish_faq_entry': {
        const { id: pubId } = params as { id: string }
        const { error } = await admin.from('faq_entries')
          .update({ status: 'published', updated_at: new Date().toISOString() })
          .eq('id', pubId)
        if (error) return NextResponse.json({ error: error.message }, { status: 500 })
        return NextResponse.json({ success: true })
      }

      case 'bulk_publish_faq_entries': {
        const { error } = await admin.from('faq_entries')
          .update({ status: 'published', updated_at: new Date().toISOString() })
          .eq('status', 'draft')
        if (error) return NextResponse.json({ error: error.message }, { status: 500 })
        return NextResponse.json({ success: true })
      }

      case 'create_faq_category': {
        const { slug, name: catName, icon, display_order: catOrder } = params as {
          slug: string; name: string; icon?: string; display_order?: number
        }
        const { data, error } = await admin.from('faq_categories').insert({
          slug, name: catName, icon: icon || '', display_order: catOrder || 0,
        }).select().single()
        if (error) return NextResponse.json({ error: error.message }, { status: 500 })
        return NextResponse.json({ category: data })
      }

      case 'update_faq_category': {
        const { id: catId, ...catUpdates } = params as {
          id: string; name?: string; slug?: string; icon?: string; display_order?: number
        }
        const { error } = await admin.from('faq_categories').update(catUpdates).eq('id', catId)
        if (error) return NextResponse.json({ error: error.message }, { status: 500 })
        return NextResponse.json({ success: true })
      }

      case 'delete_faq_category': {
        const { id: delCatId } = params as { id: string }
        const entryCheck = await admin.from('faq_entries').select('id').eq('category_id', delCatId).limit(1)
        if (entryCheck.data && entryCheck.data.length > 0) {
          return NextResponse.json({ error: 'Cannot delete category with existing entries' }, { status: 400 })
        }
        const { error } = await admin.from('faq_categories').delete().eq('id', delCatId)
        if (error) return NextResponse.json({ error: error.message }, { status: 500 })
        return NextResponse.json({ success: true })
      }

      // ═══════════════════════════════════════════════════
      // EXERCISE LIBRARY MANAGEMENT
      // ═══════════════════════════════════════════════════

      case 'get_exercises': {
        const { workout_type, category, equipment, search, page = 0 } = params
        const lim = safeLimit(params.limit, 100)
        const pg = Math.max(0, Number(page) || 0)

        let query = admin.from('exercises')
          .select('id, name, category, equipment, workout_type, primary_muscles, secondary_muscles, video_filename, video_code, gender, difficulty_level, is_custom, movement_pattern, force_type, equipment_category, home_gym_friendly, exercise_family, is_compound, duration_based, manually_updated, manually_updated_at', { count: 'exact' })
          .eq('is_custom', false)
          .order('name', { ascending: true })
          .range(pg * lim, (pg + 1) * lim - 1)

        if (workout_type && workout_type !== 'all') {
          query = query.ilike('workout_type', `%${workout_type}%`)
        }
        if (category && category !== 'all') {
          query = query.ilike('category', `%${sanitizeSearch(category)}%`)
        }
        if (equipment && equipment !== 'all') {
          query = query.ilike('equipment', `%${sanitizeSearch(equipment)}%`)
        }
        if (search && search.trim()) {
          const q = sanitizeSearch(search)
          query = query.or(`name.ilike.%${q}%,category.ilike.%${q}%,primary_muscles.ilike.%${q}%,equipment.ilike.%${q}%,exercise_family.ilike.%${q}%`)
        }

        const { data, error, count } = await query

        if (error) {
          return NextResponse.json({ error: error.message }, { status: 500 })
        }

        return NextResponse.json({ exercises: data || [], total: count || 0 })
      }

      case 'get_exercise_filters': {
        const [catRes, equipRes, typeRes] = await Promise.all([
          admin.from('exercises').select('category').eq('is_custom', false).not('category', 'is', null),
          admin.from('exercises').select('equipment').eq('is_custom', false).not('equipment', 'is', null),
          admin.from('exercises').select('workout_type').eq('is_custom', false).not('workout_type', 'is', null),
        ])

        const unique = (arr: Record<string, unknown>[] | null, field: string) => {
          const vals = new Set<string>()
          for (const row of arr || []) {
            const v = row[field] as string
            if (v && v.trim()) vals.add(v.trim())
          }
          return Array.from(vals).sort()
        }

        return NextResponse.json({
          categories: unique(catRes.data, 'category'),
          equipment: unique(equipRes.data, 'equipment'),
          workout_types: unique(typeRes.data, 'workout_type'),
        })
      }

      case 'get_exercise': {
        const { exercise_id } = params

        const { data, error } = await admin.from('exercises')
          .select('*')
          .eq('id', exercise_id)
          .single()

        if (error) {
          return NextResponse.json({ error: error.message }, { status: 404 })
        }

        return NextResponse.json({ exercise: data })
      }

      case 'update_exercise': {
        const { exercise_id, updates } = params

        const allowedFields = [
          'name', 'category', 'equipment', 'primary_muscles', 'secondary_muscles',
          'description', 'instructions', 'steps_to_perform', 'video_code', 'video_filename',
          'gender', 'workout_type', 'movement_pattern', 'force_type', 'movement_type',
          'laterality', 'plane_of_motion', 'difficulty_level', 'complexity_score',
          'strength_rating', 'hypertrophy_rating', 'power_rating', 'endurance_rating',
          'body_position', 'bench_angle', 'grip_type', 'grip_width',
          'optimal_rep_range_min', 'optimal_rep_range_max', 'placement_in_workout',
          'fatigability', 'popularity_score', 'home_gym_friendly', 'practicality_score',
          'fat_loss_rating', 'general_fitness_rating', 'is_compound', 'supersetable',
          'exercise_family', 'base_exercise_name', 'complementary_families',
          'is_equipment_primary', 'equipment_category', 'duration_based',
          'recommended_sets', 'rest_seconds', 'muscles_worked_count',
          'priority_build_muscle', 'priority_get_lean', 'priority_home', 'priority_gym',
          'manually_updated',
        ]

        const sanitized: Record<string, unknown> = {}
        for (const [key, value] of Object.entries(updates)) {
          if (allowedFields.includes(key)) {
            sanitized[key] = value
          }
        }

        if (Object.keys(sanitized).length === 0) {
          return NextResponse.json({ error: 'No valid fields to update' }, { status: 400 })
        }

        // Auto-stamp the manual-edit marker on every admin save. The detail
        // page can explicitly send `manually_updated: false` to clear it
        // (in which case we also clear the timestamp).
        if (sanitized.manually_updated === false) {
          sanitized.manually_updated_at = null
        } else {
          sanitized.manually_updated = true
          sanitized.manually_updated_at = new Date().toISOString()
        }

        const { data, error } = await admin.from('exercises')
          .update(sanitized)
          .eq('id', exercise_id)
          .select()
          .single()

        if (error) {
          return NextResponse.json({ error: error.message }, { status: 500 })
        }

        // Refresh the mv_public_exercises materialized view so cold-start
        // app launches see the change. Fire-and-forget — the iOS app also
        // receives a Supabase Realtime event directly from the `exercises`
        // table update, so the UI updates instantly even if this lags.
        admin.rpc('refresh_mv_public_exercises').then(({ error: rpcErr }) => {
          if (rpcErr) console.error('[update_exercise] mv refresh failed:', rpcErr.message)
        })

        return NextResponse.json({ exercise: data })
      }

      case 'delete_exercise': {
        const { exercise_id } = params

        const { error } = await admin.from('exercises')
          .delete()
          .eq('id', exercise_id)

        if (error) {
          return NextResponse.json({ error: error.message }, { status: 500 })
        }

        admin.rpc('refresh_mv_public_exercises').then(({ error: rpcErr }) => {
          if (rpcErr) console.error('[delete_exercise] mv refresh failed:', rpcErr.message)
        })

        return NextResponse.json({ success: true })
      }

      case 'get_exercise_suggestions': {
        const [muscleRes, catRes, equipRes, eqCatRes, moveRes, forceRes, moveTypeRes, latRes, planeRes, bodyPosRes, benchRes, gripRes, gripWRes, familyRes, placementRes] = await Promise.all([
          admin.from('exercises').select('primary_muscles, secondary_muscles').eq('is_custom', false).not('primary_muscles', 'is', null).limit(4000),
          admin.from('exercises').select('category').eq('is_custom', false).not('category', 'is', null),
          admin.from('exercises').select('equipment').eq('is_custom', false).not('equipment', 'is', null),
          admin.from('exercises').select('equipment_category').eq('is_custom', false).not('equipment_category', 'is', null),
          admin.from('exercises').select('movement_pattern').eq('is_custom', false).not('movement_pattern', 'is', null),
          admin.from('exercises').select('force_type').eq('is_custom', false).not('force_type', 'is', null),
          admin.from('exercises').select('movement_type').eq('is_custom', false).not('movement_type', 'is', null),
          admin.from('exercises').select('laterality').eq('is_custom', false).not('laterality', 'is', null),
          admin.from('exercises').select('plane_of_motion').eq('is_custom', false).not('plane_of_motion', 'is', null),
          admin.from('exercises').select('body_position').eq('is_custom', false).not('body_position', 'is', null),
          admin.from('exercises').select('bench_angle').eq('is_custom', false).not('bench_angle', 'is', null),
          admin.from('exercises').select('grip_type').eq('is_custom', false).not('grip_type', 'is', null),
          admin.from('exercises').select('grip_width').eq('is_custom', false).not('grip_width', 'is', null),
          admin.from('exercises').select('exercise_family').eq('is_custom', false).not('exercise_family', 'is', null),
          admin.from('exercises').select('placement_in_workout').eq('is_custom', false).not('placement_in_workout', 'is', null),
        ])

        const unique = (arr: Record<string, unknown>[] | null, field: string) => {
          const vals = new Set<string>()
          for (const row of arr || []) {
            const v = row[field] as string
            if (v && v.trim()) vals.add(v.trim())
          }
          return Array.from(vals).sort()
        }

        const muscles = new Set<string>()
        for (const row of muscleRes.data || []) {
          for (const field of ['primary_muscles', 'secondary_muscles'] as const) {
            const val = (row as Record<string, unknown>)[field]
            if (Array.isArray(val)) {
              for (const m of val) { if (m && typeof m === 'string' && m.trim()) muscles.add(m.trim()) }
            } else if (typeof val === 'string') {
              try {
                const parsed = JSON.parse(val)
                if (Array.isArray(parsed)) {
                  for (const m of parsed) { if (m && typeof m === 'string' && m.trim()) muscles.add(m.trim()) }
                } else if (val.trim()) {
                  muscles.add(val.trim())
                }
              } catch {
                if (val.trim()) muscles.add(val.trim())
              }
            }
          }
        }

        return NextResponse.json({
          muscles: Array.from(muscles).sort(),
          categories: unique(catRes.data, 'category'),
          equipment: unique(equipRes.data, 'equipment'),
          equipment_categories: unique(eqCatRes.data, 'equipment_category'),
          movement_patterns: unique(moveRes.data, 'movement_pattern'),
          force_types: unique(forceRes.data, 'force_type'),
          movement_types: unique(moveTypeRes.data, 'movement_type'),
          lateralities: unique(latRes.data, 'laterality'),
          planes_of_motion: unique(planeRes.data, 'plane_of_motion'),
          body_positions: unique(bodyPosRes.data, 'body_position'),
          bench_angles: unique(benchRes.data, 'bench_angle'),
          grip_types: unique(gripRes.data, 'grip_type'),
          grip_widths: unique(gripWRes.data, 'grip_width'),
          exercise_families: unique(familyRes.data, 'exercise_family'),
          placements: unique(placementRes.data, 'placement_in_workout'),
        })
      }

      // ═══════════════════════════════════════════════════
      // VERSION CHANGELOGS
      // ═══════════════════════════════════════════════════

      case 'get_version_changelogs': {
        const { version: filterVersion } = params
        let query = admin.from('version_changelogs')
          .select('*')
          .order('created_at', { ascending: false })

        if (filterVersion) {
          query = query.eq('version', filterVersion)
        }

        const { data, error: clError } = await query.limit(100)
        if (clError) throw clError

        return NextResponse.json({ changelogs: data || [] })
      }

      // ═══════════════════════════════════════════════════
      // AUDIT LOG VIEWER
      // ═══════════════════════════════════════════════════

      case 'get_audit_logs': {
        const { admin_email: filterEmail, action: filterAction, target_id: filterTarget, date_from, date_to, page = 0 } = params
        const lim = safeLimit(params.limit, 200)
        const pg = Math.max(0, Number(page) || 0)

        let query = admin.from('admin_audit_log')
          .select('*', { count: 'exact' })
          .order('created_at', { ascending: false })
          .range(pg * lim, (pg + 1) * lim - 1)

        if (filterEmail) query = query.ilike('admin_email', `%${sanitizeSearch(filterEmail)}%`)
        if (filterAction) query = query.eq('action', filterAction)
        if (filterTarget) query = query.ilike('target_id', `%${sanitizeSearch(filterTarget)}%`)
        if (date_from) query = query.gte('created_at', date_from)
        if (date_to) query = query.lte('created_at', date_to)

        const { data, error, count } = await query
        if (error) return NextResponse.json({ error: error.message }, { status: 500 })
        return NextResponse.json({ logs: data || [], total: count || 0 })
      }

      case 'get_audit_stats': {
        const { data: allLogs, error } = await admin.from('admin_audit_log')
          .select('action, admin_email, created_at')
          .gte('created_at', new Date(Date.now() - 30 * 86400000).toISOString())
          .order('created_at', { ascending: false })
          .limit(5000)

        if (error) return NextResponse.json({ error: error.message }, { status: 500 })

        const actionCounts: Record<string, number> = {}
        const adminCounts: Record<string, number> = {}
        const dailyCounts: Record<string, number> = {}

        for (const log of allLogs || []) {
          actionCounts[log.action] = (actionCounts[log.action] || 0) + 1
          if (log.admin_email) adminCounts[log.admin_email] = (adminCounts[log.admin_email] || 0) + 1
          const day = log.created_at?.substring(0, 10)
          if (day) dailyCounts[day] = (dailyCounts[day] || 0) + 1
        }

        return NextResponse.json({
          total_actions_30d: (allLogs || []).length,
          action_counts: actionCounts,
          admin_counts: adminCounts,
          daily_counts: dailyCounts,
        })
      }

      case 'export_audit_logs': {
        const { date_from, date_to } = params
        let query = admin.from('admin_audit_log')
          .select('*')
          .order('created_at', { ascending: false })
          .limit(5000)

        if (date_from) query = query.gte('created_at', date_from)
        if (date_to) query = query.lte('created_at', date_to)

        const { data, error } = await query
        if (error) return NextResponse.json({ error: error.message }, { status: 500 })

        const rows = (data || []).map(r => ({
          timestamp: r.created_at,
          admin_email: r.admin_email || 'unknown',
          action: r.action,
          target_id: r.target_id || '',
          ip_address: r.ip_address || '',
          details: JSON.stringify(r.details || {}),
        }))

        return NextResponse.json({ rows })
      }

      // ═══════════════════════════════════════════════════
      // FEATURE FLAGS
      // ═══════════════════════════════════════════════════

      case 'get_feature_flags': {
        const { data, error } = await admin.from('feature_flags')
          .select('*')
          .order('created_at', { ascending: false })

        if (error) return NextResponse.json({ error: error.message }, { status: 500 })
        return NextResponse.json({ flags: data || [] })
      }

      case 'create_feature_flag': {
        const { key, description: flagDesc, enabled, rollout_percentage, platform: flagPlatform, min_app_version, metadata: flagMeta } = params
        if (!key) return NextResponse.json({ error: 'Missing key' }, { status: 400 })

        const { data, error } = await admin.from('feature_flags').insert({
          key: key.toLowerCase().replace(/[^a-z0-9_]/g, '_'),
          description: flagDesc || '',
          enabled: enabled || false,
          rollout_percentage: rollout_percentage ?? 100,
          platform: flagPlatform || 'all',
          min_app_version: min_app_version || null,
          metadata: flagMeta || {},
          created_by: adminAuth.email,
          updated_by: adminAuth.email,
        }).select().single()

        if (error) return NextResponse.json({ error: error.message }, { status: 500 })
        return NextResponse.json({ flag: data })
      }

      case 'update_feature_flag': {
        const { flag_id, ...flagUpdates } = params
        if (!flag_id) return NextResponse.json({ error: 'Missing flag_id' }, { status: 400 })

        const allowed = ['enabled', 'description', 'rollout_percentage', 'platform', 'min_app_version', 'metadata']
        const sanitized: Record<string, unknown> = { updated_by: adminAuth.email, updated_at: new Date().toISOString() }
        for (const [k, v] of Object.entries(flagUpdates)) {
          if (allowed.includes(k)) sanitized[k] = v
        }

        const { data, error } = await admin.from('feature_flags')
          .update(sanitized)
          .eq('id', flag_id)
          .select()
          .single()

        if (error) return NextResponse.json({ error: error.message }, { status: 500 })
        return NextResponse.json({ flag: data })
      }

      case 'delete_feature_flag': {
        const { flag_id } = params
        if (!flag_id) return NextResponse.json({ error: 'Missing flag_id' }, { status: 400 })

        const { error } = await admin.from('feature_flags').delete().eq('id', flag_id)
        if (error) return NextResponse.json({ error: error.message }, { status: 500 })
        return NextResponse.json({ success: true })
      }

      case 'get_feature_flag_history': {
        const { flag_id } = params
        let query = admin.from('admin_audit_log')
          .select('*')
          .in('action', ['create_feature_flag', 'update_feature_flag', 'delete_feature_flag'])
          .order('created_at', { ascending: false })
          .limit(50)

        if (flag_id) query = query.eq('target_id', flag_id)

        const { data, error } = await query
        if (error) return NextResponse.json({ error: error.message }, { status: 500 })
        return NextResponse.json({ history: data || [] })
      }

      // ═══════════════════════════════════════════════════
      // SYSTEM HEALTH
      // ═══════════════════════════════════════════════════

      case 'health_table_sizes': {
        const { data, error } = await admin.rpc('admin_get_table_sizes')
        if (error) return NextResponse.json({ error: error.message }, { status: 500 })
        return NextResponse.json({ tables: data || [] })
      }

      case 'health_connections': {
        const { data, error } = await admin.rpc('admin_get_connection_stats')
        if (error) return NextResponse.json({ error: error.message }, { status: 500 })
        return NextResponse.json(data || {})
      }

      case 'health_index_usage': {
        const { data, error } = await admin.rpc('admin_get_index_health')
        if (error) return NextResponse.json({ error: error.message }, { status: 500 })
        return NextResponse.json({ indexes: data || [] })
      }

      case 'health_rpc_stats': {
        const { data, error } = await admin.rpc('admin_get_rpc_stats')
        if (error) return NextResponse.json({ error: error.message }, { status: 500 })
        return NextResponse.json({ functions: data || [] })
      }

      case 'health_push_pipeline': {
        const { data, error } = await admin.rpc('admin_get_push_pipeline_stats')
        if (error) return NextResponse.json({ error: error.message }, { status: 500 })
        return NextResponse.json(data || {})
      }

      case 'health_error_rates': {
        const d30 = new Date(Date.now() - 30 * 86400000).toISOString()

        const [crashRes, bugRes] = await Promise.all([
          admin.from('crash_reports').select('created_at, severity').gte('created_at', d30),
          admin.from('bug_reports').select('created_at').gte('created_at', d30),
        ])

        const dailyCrashes: Record<string, number> = {}
        const dailyBugs: Record<string, number> = {}

        for (const r of crashRes.data || []) {
          const day = r.created_at?.substring(0, 10)
          if (day) dailyCrashes[day] = (dailyCrashes[day] || 0) + 1
        }
        for (const r of bugRes.data || []) {
          const day = r.created_at?.substring(0, 10)
          if (day) dailyBugs[day] = (dailyBugs[day] || 0) + 1
        }

        return NextResponse.json({
          crashes_30d: (crashRes.data || []).length,
          bugs_30d: (bugRes.data || []).length,
          daily_crashes: dailyCrashes,
          daily_bugs: dailyBugs,
        })
      }

      // ═══════════════════════════════════════════════════
      // MODERATION
      // ═══════════════════════════════════════════════════

      case 'get_moderation_queue': {
        const { status: modStatus, page = 0 } = params
        const lim = safeLimit(params.limit, 100)
        const pg = Math.max(0, Number(page) || 0)

        let query = admin.from('user_reports')
          .select('*')
          .order('created_at', { ascending: false })
          .range(pg * lim, (pg + 1) * lim - 1)

        if (modStatus) query = query.eq('status', modStatus)

        const { data: reports, error } = await query
        if (error) return NextResponse.json({ error: error.message }, { status: 500 })

        const userIds = new Set<string>()
        for (const r of reports || []) {
          userIds.add(r.reporter_id)
          userIds.add(r.reported_user_id)
        }

        let profiles: Record<string, unknown>[] = []
        if (userIds.size > 0) {
          const { data: p } = await admin.from('user_profiles')
            .select('id, name, username, email, profile_photo_url')
            .in('id', Array.from(userIds))
          profiles = p || []
        }

        const profileMap = new Map(profiles.map(p => [(p as { id: string }).id, p]))
        const enriched = (reports || []).map(r => ({
          ...r,
          reporter_profile: profileMap.get(r.reporter_id) || null,
          reported_profile: profileMap.get(r.reported_user_id) || null,
        }))

        return NextResponse.json({ reports: enriched })
      }

      case 'get_moderation_stats': {
        const [reportsRes, blocksRes] = await Promise.all([
          admin.from('user_reports').select('reason, status, created_at, resolved_at, reported_user_id'),
          admin.from('user_blocks').select('blocker_id, blocked_id, created_at'),
        ])

        const reports = reportsRes.data || []
        const reasonCounts: Record<string, number> = {}
        const statusCounts: Record<string, number> = {}
        let totalResolutionMs = 0
        let resolvedCount = 0
        const repeatOffenders: Record<string, number> = {}

        for (const r of reports) {
          reasonCounts[r.reason] = (reasonCounts[r.reason] || 0) + 1
          statusCounts[r.status] = (statusCounts[r.status] || 0) + 1
          repeatOffenders[r.reported_user_id] = (repeatOffenders[r.reported_user_id] || 0) + 1
          if (r.resolved_at && r.created_at) {
            totalResolutionMs += new Date(r.resolved_at).getTime() - new Date(r.created_at).getTime()
            resolvedCount++
          }
        }

        const topOffenders = Object.entries(repeatOffenders)
          .filter(([, c]) => c >= 2)
          .sort((a, b) => b[1] - a[1])
          .slice(0, 20)
          .map(([id, count]) => ({ user_id: id, report_count: count }))

        return NextResponse.json({
          total_reports: reports.length,
          reason_counts: reasonCounts,
          status_counts: statusCounts,
          avg_resolution_hours: resolvedCount > 0 ? Math.round(totalResolutionMs / resolvedCount / 3600000 * 10) / 10 : null,
          total_blocks: (blocksRes.data || []).length,
          repeat_offenders: topOffenders,
        })
      }

      case 'update_report_status': {
        const { report_id, status: newReportStatus, resolution_notes } = params
        if (!report_id) return NextResponse.json({ error: 'Missing report_id' }, { status: 400 })

        const updates: Record<string, unknown> = { status: newReportStatus }
        if (resolution_notes !== undefined) updates.resolution_notes = resolution_notes
        if (newReportStatus === 'resolved' || newReportStatus === 'dismissed') {
          updates.resolved_at = new Date().toISOString()
          updates.resolved_by = adminAuth.email
        }

        const { error } = await admin.from('user_reports').update(updates).eq('id', report_id)
        if (error) return NextResponse.json({ error: error.message }, { status: 500 })
        return NextResponse.json({ success: true })
      }

      case 'get_user_reports': {
        const { user_id } = params
        if (!user_id) return NextResponse.json({ error: 'Missing user_id' }, { status: 400 })

        const { data, error } = await admin.from('user_reports')
          .select('*')
          .or(`reporter_id.eq.${user_id},reported_user_id.eq.${user_id}`)
          .order('created_at', { ascending: false })

        if (error) return NextResponse.json({ error: error.message }, { status: 500 })
        return NextResponse.json({ reports: data || [] })
      }

      case 'suspend_user': {
        const { user_id, reason: suspendReason, expires_at } = params
        if (!user_id || !suspendReason) return NextResponse.json({ error: 'Missing user_id or reason' }, { status: 400 })

        const { data, error } = await admin.from('user_suspensions').insert({
          user_id,
          reason: suspendReason,
          suspended_by: adminAuth.email || 'admin',
          expires_at: expires_at || null,
        }).select().single()

        if (error) return NextResponse.json({ error: error.message }, { status: 500 })
        return NextResponse.json({ suspension: data })
      }

      case 'lift_suspension': {
        const { suspension_id } = params
        if (!suspension_id) return NextResponse.json({ error: 'Missing suspension_id' }, { status: 400 })

        const { error } = await admin.from('user_suspensions')
          .update({ lifted_at: new Date().toISOString(), lifted_by: adminAuth.email })
          .eq('id', suspension_id)

        if (error) return NextResponse.json({ error: error.message }, { status: 500 })
        return NextResponse.json({ success: true })
      }

      case 'get_user_suspensions': {
        const { user_id } = params
        let query = admin.from('user_suspensions')
          .select('*')
          .order('suspended_at', { ascending: false })

        if (user_id) query = query.eq('user_id', user_id)

        const { data, error } = await query.limit(100)
        if (error) return NextResponse.json({ error: error.message }, { status: 500 })
        return NextResponse.json({ suspensions: data || [] })
      }

      case 'get_block_relationships': {
        const { data: blocks, error } = await admin.from('user_blocks')
          .select('blocker_id, blocked_id, created_at')
          .order('created_at', { ascending: false })
          .limit(1000)

        if (error) return NextResponse.json({ error: error.message }, { status: 500 })

        const blockedCounts: Record<string, number> = {}
        for (const b of blocks || []) {
          blockedCounts[b.blocked_id] = (blockedCounts[b.blocked_id] || 0) + 1
        }

        const mostBlocked = Object.entries(blockedCounts)
          .sort((a, b) => b[1] - a[1])
          .slice(0, 20)
          .map(([id, count]) => ({ user_id: id, block_count: count }))

        let mostBlockedProfiles: Record<string, unknown>[] = []
        if (mostBlocked.length > 0) {
          const { data: p } = await admin.from('user_profiles')
            .select('id, name, username, email')
            .in('id', mostBlocked.map(m => m.user_id))
          mostBlockedProfiles = p || []
        }

        const profileMap = new Map(mostBlockedProfiles.map(p => [(p as { id: string }).id, p]))
        const enrichedBlocked = mostBlocked.map(m => ({
          ...m,
          profile: profileMap.get(m.user_id) || null,
        }))

        return NextResponse.json({
          total_blocks: (blocks || []).length,
          most_blocked_users: enrichedBlocked,
          blocks: blocks || [],
        })
      }

      case 'get_moderation_overview': {
        const { data: pendingRes } = await admin.from('user_reports')
          .select('id', { count: 'exact', head: true })
          .eq('status', 'pending')

        const { data: activeSuspensions } = await admin.from('user_suspensions')
          .select('id', { count: 'exact', head: true })
          .is('lifted_at', null)

        return NextResponse.json({
          pending_reports: pendingRes,
          active_suspensions: activeSuspensions,
        })
      }

      // ═══════════════════════════════════════════════════
      // CONTENT MODERATION (Flagged Content)
      // ═══════════════════════════════════════════════════

      case 'get_flagged_content': {
        const { status: flagStatus = 'unreviewed', page: flagPage = 0 } = params
        const flagLimit = safeLimit(params.limit, 50)
        const flagOffset = Math.max(0, Number(flagPage) || 0) * flagLimit

        let query = admin.from('content_moderation_log')
          .select('*, user:user_profiles!content_moderation_log_user_id_fkey(id, name, username, email, profile_photo_url)')
          .order('created_at', { ascending: false })
          .range(flagOffset, flagOffset + flagLimit - 1)

        if (flagStatus === 'unreviewed') {
          query = query.eq('admin_reviewed', false)
        }

        const { data: flagged, error: flagErr } = await query
        if (flagErr) return NextResponse.json({ error: flagErr.message }, { status: 500 })

        const { count: totalUnreviewed } = await admin.from('content_moderation_log')
          .select('id', { count: 'exact', head: true })
          .eq('admin_reviewed', false)

        return NextResponse.json({
          flagged_content: flagged || [],
          total_unreviewed: totalUnreviewed || 0,
        })
      }

      case 'get_content_moderation_stats': {
        const [totalRes, unreviewedRes, todayRes] = await Promise.all([
          admin.from('content_moderation_log').select('id', { count: 'exact', head: true }),
          admin.from('content_moderation_log').select('id', { count: 'exact', head: true }).eq('admin_reviewed', false),
          admin.from('content_moderation_log').select('id', { count: 'exact', head: true }).gte('created_at', new Date().toISOString().split('T')[0]),
        ])

        const { data: topOffenders } = await admin.from('content_moderation_log')
          .select('user_id')
          .not('user_id', 'is', null)

        const offenderCounts: Record<string, number> = {}
        for (const row of topOffenders || []) {
          if (row.user_id) {
            offenderCounts[row.user_id] = (offenderCounts[row.user_id] || 0) + 1
          }
        }

        const topOffenderIds = Object.entries(offenderCounts)
          .sort((a, b) => b[1] - a[1])
          .slice(0, 10)

        let offenderProfiles: { id: string; name: string; username: string }[] = []
        if (topOffenderIds.length > 0) {
          const { data: profiles } = await admin.from('user_profiles')
            .select('id, name, username')
            .in('id', topOffenderIds.map(([id]) => id))
          offenderProfiles = (profiles || []) as { id: string; name: string; username: string }[]
        }

        const profileMap = new Map(offenderProfiles.map(p => [p.id, p]))

        return NextResponse.json({
          total_flagged: totalRes.count || 0,
          unreviewed: unreviewedRes.count || 0,
          flagged_today: todayRes.count || 0,
          top_offenders: topOffenderIds.map(([id, count]) => ({
            user_id: id,
            flag_count: count,
            profile: profileMap.get(id) || null,
          })),
        })
      }

      case 'review_flagged_content': {
        const { log_id, review_action, notes: reviewNotes } = params
        if (!log_id || !review_action) {
          return NextResponse.json({ error: 'Missing log_id or review_action' }, { status: 400 })
        }

        const { data: logEntry, error: logErr } = await admin.from('content_moderation_log')
          .select('*')
          .eq('id', log_id)
          .single()

        if (logErr || !logEntry) {
          return NextResponse.json({ error: 'Log entry not found' }, { status: 404 })
        }

        await admin.from('content_moderation_log')
          .update({
            admin_reviewed: true,
            action_taken: review_action,
            admin_notes: reviewNotes || null,
            reviewed_at: new Date().toISOString(),
          })
          .eq('id', log_id)

        if (review_action === 'approved' && logEntry.record_id && logEntry.table_name) {
          await admin.from(logEntry.table_name)
            .update({ is_hidden: false })
            .eq('id', logEntry.record_id)
        }

        return NextResponse.json({ success: true })
      }

      // ═══════════════════════════════════════════════════
      // PUSH NOTIFICATION MANAGER
      // ═══════════════════════════════════════════════════

      case 'get_push_overview': {
        const { data: pipeline, error: pipeErr } = await admin.rpc('admin_get_push_pipeline_stats')

        const { data: campaigns } = await admin.from('push_campaigns')
          .select('*')
          .order('created_at', { ascending: false })
          .limit(10)

        if (pipeErr) return NextResponse.json({ error: pipeErr.message }, { status: 500 })
        return NextResponse.json({ pipeline: pipeline || {}, recent_campaigns: campaigns || [] })
      }

      case 'get_push_campaigns': {
        const { status: campStatus } = params
        let query = admin.from('push_campaigns')
          .select('*')
          .order('created_at', { ascending: false })

        if (campStatus) query = query.eq('status', campStatus)

        const { data, error } = await query.limit(100)
        if (error) return NextResponse.json({ error: error.message }, { status: 500 })
        return NextResponse.json({ campaigns: data || [] })
      }

      case 'create_push_campaign': {
        const { title: campTitle, body: campBody, segment, notification_type, custom_filter, scheduled_at: campSchedule, data: campData } = params
        if (!campTitle || !campBody || !segment) {
          return NextResponse.json({ error: 'Missing title, body, or segment' }, { status: 400 })
        }

        const { data, error } = await admin.from('push_campaigns').insert({
          title: campTitle,
          body: campBody,
          segment,
          notification_type: notification_type || 'campaign',
          custom_filter: custom_filter || null,
          scheduled_at: campSchedule || null,
          data: campData || {},
          status: campSchedule ? 'scheduled' : 'draft',
          created_by: adminAuth.email || 'admin',
        }).select().single()

        if (error) return NextResponse.json({ error: error.message }, { status: 500 })
        return NextResponse.json({ campaign: data })
      }

      case 'update_push_campaign': {
        const { campaign_id, ...campUpdates } = params
        if (!campaign_id) return NextResponse.json({ error: 'Missing campaign_id' }, { status: 400 })

        const allowed = ['title', 'body', 'segment', 'notification_type', 'custom_filter', 'scheduled_at', 'status', 'data']
        const sanitized: Record<string, unknown> = {}
        for (const [k, v] of Object.entries(campUpdates)) {
          if (allowed.includes(k)) sanitized[k] = v
        }

        const { data, error } = await admin.from('push_campaigns')
          .update(sanitized)
          .eq('id', campaign_id)
          .select()
          .single()

        if (error) return NextResponse.json({ error: error.message }, { status: 500 })
        return NextResponse.json({ campaign: data })
      }

      case 'send_push_campaign': {
        const { campaign_id } = params
        if (!campaign_id) return NextResponse.json({ error: 'Missing campaign_id' }, { status: 400 })

        const { data, error } = await admin.rpc('execute_push_campaign', { p_campaign_id: campaign_id })
        if (error) return NextResponse.json({ error: error.message }, { status: 500 })
        return NextResponse.json(data || { success: true })
      }

      case 'get_push_delivery_stats': {
        const { data, error } = await admin.from('push_notification_delivery_log')
          .select('event, created_at')
          .gte('created_at', new Date(Date.now() - 7 * 86400000).toISOString())
          .order('created_at', { ascending: false })
          .limit(10000)

        if (error) return NextResponse.json({ error: error.message }, { status: 500 })

        const eventCounts: Record<string, number> = {}
        const dailyEvents: Record<string, Record<string, number>> = {}

        for (const r of data || []) {
          eventCounts[r.event] = (eventCounts[r.event] || 0) + 1
          const day = r.created_at?.substring(0, 10)
          if (day) {
            if (!dailyEvents[day]) dailyEvents[day] = {}
            dailyEvents[day][r.event] = (dailyEvents[day][r.event] || 0) + 1
          }
        }

        return NextResponse.json({ event_counts: eventCounts, daily_events: dailyEvents })
      }

      case 'get_push_queue_status': {
        const { data, error } = await admin.from('push_notification_queue')
          .select('id, recipient_user_id, notification_type, title, body, status, error_message, retry_count, created_at, sent_at')
          .in('status', ['pending', 'processing', 'failed'])
          .order('created_at', { ascending: false })
          .limit(500)

        if (error) return NextResponse.json({ error: error.message }, { status: 500 })

        const statusCounts: Record<string, number> = {}
        for (const r of data || []) {
          statusCounts[r.status] = (statusCounts[r.status] || 0) + 1
        }

        const userIds = [...new Set((data || []).map((r: { recipient_user_id: string }) => r.recipient_user_id).filter(Boolean))]
        let profiles: Record<string, unknown>[] = []
        if (userIds.length > 0) {
          const { data: p } = await admin.from('user_profiles')
            .select('id, name, username, email, profile_photo_url')
            .in('id', userIds.slice(0, 200))
          profiles = p || []
        }

        const profileMap: Record<string, unknown> = {}
        for (const p of profiles) {
          profileMap[(p as { id: string }).id] = p
        }

        const notifIds = (data || []).map((r: { id: string }) => r.id).filter(Boolean)
        const logsMap: Record<string, { event: string; detail: unknown; created_at: string }[]> = {}
        if (notifIds.length > 0) {
          const { data: logs } = await admin.from('push_notification_delivery_log')
            .select('notification_id, event, detail, created_at')
            .in('notification_id', notifIds.slice(0, 200))
            .order('created_at', { ascending: true })
          for (const l of logs || []) {
            const nid = (l as { notification_id: string }).notification_id
            if (!logsMap[nid]) logsMap[nid] = []
            logsMap[nid].push({ event: l.event, detail: l.detail, created_at: l.created_at })
          }
        }

        const enriched = (data || []).map((r: Record<string, unknown>) => ({
          ...r,
          recipient_profile: profileMap[r.recipient_user_id as string] || null,
          delivery_logs: logsMap[r.id as string] || [],
        }))

        return NextResponse.json({ status_counts: statusCounts, items: enriched })
      }

      case 'get_push_user_debug': {
        const { user_id } = params
        if (!user_id) return NextResponse.json({ error: 'Missing user_id' }, { status: 400 })

        const [tokensRes, prefsRes, queueRes, logsRes] = await Promise.all([
          admin.from('user_push_tokens').select('*').eq('user_id', user_id),
          admin.from('user_notification_preferences').select('*').eq('user_id', user_id).maybeSingle(),
          admin.from('push_notification_queue')
            .select('id, notification_type, title, status, error_message, retry_count, created_at, sent_at')
            .eq('recipient_user_id', user_id)
            .order('created_at', { ascending: false })
            .limit(25),
          admin.from('push_notification_delivery_log')
            .select('event, detail, notification_id, created_at')
            .eq('user_id', user_id)
            .order('created_at', { ascending: false })
            .limit(50),
        ])

        return NextResponse.json({
          tokens: tokensRes.data || [],
          preferences: prefsRes.data || null,
          recent_queue: queueRes.data || [],
          delivery_logs: logsRes.data || [],
        })
      }

      case 'estimate_campaign_reach': {
        const { segment } = params
        if (!segment) return NextResponse.json({ error: 'Missing segment' }, { status: 400 })

        const { data, error } = await admin.rpc('estimate_campaign_reach', { p_segment: segment })
        if (error) return NextResponse.json({ error: error.message }, { status: 500 })
        return NextResponse.json({ reach: data || 0 })
      }

      // ═══════════════════════════════════════════════════
      // ENGAGEMENT / CHURN RISK
      // ═══════════════════════════════════════════════════

      case 'engagement_overview': {
        const { data: scores, error } = await admin.from('mv_user_engagement_scores')
          .select('engagement_score, engagement_bucket')

        if (error) return NextResponse.json({ error: error.message }, { status: 500 })

        const bucketCounts: Record<string, number> = {}
        let totalScore = 0

        for (const s of scores || []) {
          bucketCounts[s.engagement_bucket] = (bucketCounts[s.engagement_bucket] || 0) + 1
          totalScore += s.engagement_score
        }

        return NextResponse.json({
          total_users: (scores || []).length,
          avg_score: (scores || []).length > 0 ? Math.round(totalScore / (scores || []).length * 10) / 10 : 0,
          bucket_counts: bucketCounts,
        })
      }

      case 'engagement_at_risk_users': {
        const lim = safeLimit(params.limit, 100)
        const { data, error } = await admin.from('mv_user_engagement_scores')
          .select('*')
          .in('engagement_bucket', ['at_risk', 'churned'])
          .order('engagement_score', { ascending: true })
          .limit(lim)

        if (error) return NextResponse.json({ error: error.message }, { status: 500 })
        return NextResponse.json({ users: data || [] })
      }

      case 'engagement_power_users': {
        const lim = safeLimit(params.limit, 50)
        const { data, error } = await admin.from('mv_user_engagement_scores')
          .select('*')
          .eq('engagement_bucket', 'power_user')
          .order('engagement_score', { ascending: false })
          .limit(lim)

        if (error) return NextResponse.json({ error: error.message }, { status: 500 })
        return NextResponse.json({ users: data || [] })
      }

      case 'engagement_cohort_matrix': {
        const { data, error } = await admin.from('mv_retention_cohorts')
          .select('*')
          .order('cohort_week', { ascending: false })
          .limit(24)

        if (error) return NextResponse.json({ error: error.message }, { status: 500 })
        return NextResponse.json({ cohorts: data || [] })
      }

      case 'engagement_onboarding_funnel': {
        const { data, error } = await admin.from('mv_onboarding_funnel')
          .select('*')
          .limit(1)

        if (error) return NextResponse.json({ error: error.message }, { status: 500 })
        return NextResponse.json(data?.[0] || {})
      }

      case 'engagement_user_detail': {
        const { user_id } = params
        if (!user_id) return NextResponse.json({ error: 'Missing user_id' }, { status: 400 })

        const { data, error } = await admin.from('mv_user_engagement_scores')
          .select('*')
          .eq('user_id', user_id)
          .maybeSingle()

        if (error) return NextResponse.json({ error: error.message }, { status: 500 })
        return NextResponse.json({ engagement: data })
      }

      case 'engagement_geo_heatmap': {
        const { data: prefs, error: prefsErr } = await admin.from('user_notification_preferences')
          .select('timezone')
          .not('timezone', 'is', null)

        if (prefsErr) return NextResponse.json({ error: prefsErr.message }, { status: 500 })

        const tzCounts: Record<string, number> = {}
        for (const p of prefs || []) {
          if (p.timezone) tzCounts[p.timezone] = (tzCounts[p.timezone] || 0) + 1
        }

        const regionCounts: Record<string, number> = {}
        const cityData: { timezone: string; count: number; region: string }[] = []

        for (const [tz, count] of Object.entries(tzCounts)) {
          const parts = tz.split('/')
          const region = parts[0] || 'Unknown'
          regionCounts[region] = (regionCounts[region] || 0) + count
          cityData.push({ timezone: tz, count, region })
        }

        cityData.sort((a, b) => b.count - a.count)

        return NextResponse.json({
          total_with_tz: (prefs || []).length,
          region_counts: regionCounts,
          timezone_counts: tzCounts,
          top_timezones: cityData.slice(0, 30),
        })
      }

      default:
        return NextResponse.json({ error: `Unknown action: ${action}` }, { status: 400 })
    }
  } catch (err) {
    console.error('Admin API error:', err)
    return NextResponse.json(
      { error: err instanceof Error ? err.message : 'Internal server error' },
      { status: 500 },
    )
  }
}
