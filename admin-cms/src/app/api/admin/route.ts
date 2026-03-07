import { NextRequest, NextResponse } from 'next/server'
import { createAdminClient } from '@/lib/supabase-admin'
import { createClient } from '@supabase/supabase-js'
import { isAdminEmail } from '@/lib/auth'
import { getAccessToken } from '@/lib/auth-cookies'

// ═══════════════════════════════════════════════════
// RATE LIMITING (per-IP, per-endpoint)
// ═══════════════════════════════════════════════════

const RATE_LIMITS: Record<string, { max: number; windowMs: number }> = {
  read:  { max: 100, windowMs: 60_000 },
  write: { max: 30,  windowMs: 60_000 },
  bulk:  { max: 5,   windowMs: 60_000 },
}

const WRITE_ACTIONS = new Set([
  'update_user', 'delete_user', 'update_bug_report', 'delete_bug_report',
  'update_crash_report', 'delete_crash_report',
])
const BULK_ACTIONS = new Set([
  'bulk_update_bug_reports', 'bulk_update_crash_reports',
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
) {
  try {
    const admin = createAdminClient()
    await admin.from('admin_audit_log').insert({
      admin_user_id: adminUserId,
      action,
      target_id: target,
      ip_address: ip,
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
    const body = await req.json()
    const { action, ...params } = body

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
      const targetId = params.userId || params.id || params.reportId || null
      await logAdminAction(adminAuth.userId!, action, targetId, ip)
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
          'last_workout_date', 'has_completed_onboarding',
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

        // Get challenge details
        const challengeIds = (participations || []).map(p => p.challenge_id)
        let challenges: Record<string, unknown>[] = []

        if (challengeIds.length > 0) {
          const { data: cData } = await admin.from('group_challenges')
            .select('id, title, description, challenge_type, mode, daily_target, total_target, target_unit, start_date, end_date, duration_days, status, created_by, created_at')
            .in('id', challengeIds)

          challenges = cData || []
        }

        const enriched = (participations || []).map(p => {
          const challenge = challenges.find((c: Record<string, unknown>) => c.id === p.challenge_id) || {}
          return { ...p, challenge }
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
