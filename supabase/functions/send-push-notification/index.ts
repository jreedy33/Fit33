// Supabase Edge Function: Send Push Notifications via APNs
// Deploy with: supabase functions deploy send-push-notification
//
// 2026-08-01 overhaul (Smart Notification Engine — Phase 1):
//   - APNs JWT signing + payload building moved to _shared/apns.ts
//   - End-to-end push_notification_delivery_log writes for every state
//     transition (Bug-Intel forensic invariant — every catch path classifies)
//   - daily_cap from user_notification_preferences is now ENFORCED
//   - per-category caps via category_caps JSONB also enforced (Phase 2-ready)
//   - Per-token send results logged with apns_error_<status> events so the
//     CMS Health & Funnel tab can render the drop-off histogram

import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"
import { buildCorsHeaders } from "../_shared/cors.ts"
import {
  sendApnsAlert,
  pushDeliveryLog,
  eventNameFor,
  type SendResult,
} from "../_shared/apns.ts"

// Configuration
const MAX_RETRIES = 3
const BATCH_SIZE = 100

// ── Preference cache (per-invocation) ────────────────────────────────────
type Prefs = {
  master_enabled: boolean
  disabled_types: string[]
  quiet_hours_enabled: boolean
  quiet_hours_start: string | null
  quiet_hours_end: string | null
  timezone: string | null
  daily_cap: number
  /// Per-category caps as { category: max_per_day }. JSONB; absent = uncapped.
  category_caps: Record<string, number> | null
  /// Per-category disable list (mirrors category-level master toggle).
  category_disabled: string[] | null
}

const prefsCache = new Map<string, Prefs | null>()

async function getUserPreferences(supabase: ReturnType<typeof createClient>, userId: string): Promise<Prefs | null> {
  if (prefsCache.has(userId)) return prefsCache.get(userId)!

  const { data, error } = await supabase
    .from('user_notification_preferences')
    .select('master_enabled, disabled_types, quiet_hours_enabled, quiet_hours_start, quiet_hours_end, timezone, daily_cap, category_caps, category_disabled')
    .eq('user_id', userId)
    .single()

  let prefs: Prefs | null
  if (error || !data) {
    prefs = null
  } else {
    prefs = {
      master_enabled: data.master_enabled ?? true,
      disabled_types: Array.isArray(data.disabled_types) ? data.disabled_types : [],
      quiet_hours_enabled: data.quiet_hours_enabled ?? false,
      quiet_hours_start: data.quiet_hours_start ?? null,
      quiet_hours_end: data.quiet_hours_end ?? null,
      timezone: data.timezone ?? null,
      daily_cap: typeof data.daily_cap === 'number' ? data.daily_cap : 8,
      category_caps: data.category_caps && typeof data.category_caps === 'object' ? data.category_caps : null,
      category_disabled: Array.isArray(data.category_disabled) ? data.category_disabled : null,
    }
  }
  prefsCache.set(userId, prefs)
  return prefs
}

function isInQuietHours(prefs: Prefs): boolean {
  if (!prefs.quiet_hours_enabled || !prefs.quiet_hours_start || !prefs.quiet_hours_end) return false

  const tz = prefs.timezone || 'America/New_York'
  const now = new Date()
  const formatter = new Intl.DateTimeFormat('en-US', { timeZone: tz, hour: 'numeric', minute: 'numeric', hour12: false })
  const parts = formatter.formatToParts(now)
  const nowHour = parseInt(parts.find(p => p.type === 'hour')?.value || '0')
  const nowMin = parseInt(parts.find(p => p.type === 'minute')?.value || '0')
  const nowMinutes = nowHour * 60 + nowMin

  const [startH, startM] = prefs.quiet_hours_start.split(':').map(Number)
  const [endH, endM] = prefs.quiet_hours_end.split(':').map(Number)
  const startMinutes = startH * 60 + startM
  const endMinutes = endH * 60 + endM

  if (startMinutes < endMinutes) {
    return nowMinutes >= startMinutes && nowMinutes < endMinutes
  }
  // Overnight range (e.g., 22:00 to 07:00)
  return nowMinutes >= startMinutes || nowMinutes < endMinutes
}

function computeQuietHoursEndUTC(prefs: Prefs): Date {
  if (!prefs.quiet_hours_end) return new Date(Date.now() + 60 * 60 * 1000)

  const tz = prefs.timezone || 'America/New_York'
  const [endH, endM] = prefs.quiet_hours_end.split(':').map(Number)

  const now = new Date()
  const formatter = new Intl.DateTimeFormat('en-US', { timeZone: tz, year: 'numeric', month: '2-digit', day: '2-digit', hour: 'numeric', minute: 'numeric', hour12: false })
  const parts = formatter.formatToParts(now)
  const nowHour = parseInt(parts.find(p => p.type === 'hour')?.value || '0')

  const addDay = (nowHour >= endH) ? 1 : 0
  const target = new Date(now.getTime() + addDay * 24 * 60 * 60 * 1000)
  const targetDate = new Intl.DateTimeFormat('en-CA', { timeZone: tz, year: 'numeric', month: '2-digit', day: '2-digit' }).format(target)
  const endStr = `${targetDate}T${String(endH).padStart(2, '0')}:${String(endM).padStart(2, '0')}:00`
  const utcGuess = new Date(endStr + 'Z')
  const localFormatter = new Intl.DateTimeFormat('en-US', { timeZone: tz, hour: 'numeric', minute: 'numeric', hour12: false })
  const localParts = localFormatter.formatToParts(utcGuess)
  const localH = parseInt(localParts.find(p => p.type === 'hour')?.value || '0')
  const offsetHours = localH - endH
  return new Date(utcGuess.getTime() - offsetHours * 60 * 60 * 1000)
}

// Compute "midnight in user's local TZ" as a UTC ISO string. Used to set
// next_retry_at when daily_cap is hit — the row sleeps until the user's
// local day rolls over, then re-enters the queue.
//
// 2026-05-02 fix (jreedy stuck-queue incident): for west-of-UTC zones the
// previous implementation returned YESTERDAY's local midnight (24h in the
// past). Cause: `tomorrowUtcGuess` was Date.UTC(y, m-1, d+1, 0, 0, 0) —
// which in NY (UTC-4) viewed locally is 8 PM the previous day, giving
// localH=20. Subtracting 20h from `tomorrowUtcGuess` lands on TODAY's
// local midnight (already passed), not tomorrow's. The fix wraps the
// offset across the 24h boundary: if localH > 12, treat as localH - 24
// (negative offset, west of UTC).
function computeNextLocalMidnightUTC(timezone: string | null): Date {
  const tz = timezone || 'America/New_York'
  const now = new Date()
  const dateFmt = new Intl.DateTimeFormat('en-CA', {
    timeZone: tz, year: 'numeric', month: '2-digit', day: '2-digit',
  })
  const todayParts = dateFmt.formatToParts(now)
  const y = parseInt(todayParts.find(p => p.type === 'year')?.value || '2026')
  const m = parseInt(todayParts.find(p => p.type === 'month')?.value || '1')
  const d = parseInt(todayParts.find(p => p.type === 'day')?.value || '1')
  const tomorrowUtcGuess = new Date(Date.UTC(y, m - 1, d + 1, 0, 0, 0))
  const localFmt = new Intl.DateTimeFormat('en-US', {
    timeZone: tz, hour: 'numeric', minute: 'numeric', hour12: false,
  })
  const localParts = localFmt.formatToParts(tomorrowUtcGuess)
  const rawLocalH = parseInt(localParts.find(p => p.type === 'hour')?.value || '0')
  // Wrap: localH in [13, 24) means west-of-UTC (e.g. NY localH=20 → -4h).
  const offsetHours = rawLocalH > 12 ? rawLocalH - 24 : rawLocalH
  return new Date(tomorrowUtcGuess.getTime() - offsetHours * 60 * 60 * 1000)
}

// Notification types that BYPASS daily_cap and category_cap entirely.
// These are reactive social pushes — fired because another user
// explicitly took an action targeting this recipient (sent a battle
// cry, sent a friend request, invited them to a challenge, sent a
// workout, etc.). Capping them silently breaks the social loop and
// makes the app feel broken (see 2026-05-02 jreedy incident: hit cap
// at 8 sends, every subsequent battle cry / friend interaction
// deferred indefinitely).
//
// Caps still apply to engagement nudges (comeback_reminder, streak_*,
// daily_workout_reminder, challenge_nudge, morning_motivation,
// weekly_progress, *_goal, *_reminder) — those are app-initiated and
// should respect the user's noise budget.
const INTERACTIVE_BYPASS_TYPES = new Set<string>([
  'friend_request',
  'friend_request_received',
  'friend_request_accepted',
  'shared_workout',
  'workout_received',
  'contact_joined',
  'challenge_invite',
  'challenge_accepted',
  'challenge_declined',
  'challenge_completed',
  'challenge_won',
  'challenge_cancelled',
  'challenge_update',
  'challenge_reaction',
  'activity_reaction',
  'group_challenge_invite',
  'group_challenge_accepted',
  'group_challenge_started',
  'community_friend_joined',
  'private_challenge_invite',
  'private_challenge_message',
  'private_challenge_member_joined',
])

// ── daily_cap + category_cap enforcement ─────────────────────────────────
//
// Both caps key off COMPLETED sends (apns_success) since the user's local
// midnight. We use push_notification_delivery_log as the source of truth —
// no separate counter table needed. For users on a not-yet-categorized
// notification (Phase 1 cutover window), category_used remains 0.
async function countTodaysSends(
  supabase: ReturnType<typeof createClient>,
  userId: string,
  timezone: string | null,
  category: string | null,
): Promise<{ totalToday: number; categoryToday: number }> {
  // "Today" = since the most-recent local midnight, expressed in UTC.
  const next = computeNextLocalMidnightUTC(timezone)
  const startToday = new Date(next.getTime() - 24 * 60 * 60 * 1000)

  const { data, error } = await supabase
    .from('push_notification_delivery_log')
    .select('detail, created_at')
    .eq('user_id', userId)
    .eq('event', 'apns_success')
    .gte('created_at', startToday.toISOString())

  if (error || !data) {
    return { totalToday: 0, categoryToday: 0 }
  }

  const totalToday = data.length
  let categoryToday = 0
  if (category) {
    for (const row of data as Array<{ detail: Record<string, unknown> | null }>) {
      const c = row.detail?.['category']
      if (typeof c === 'string' && c === category) categoryToday++
    }
  }
  return { totalToday, categoryToday }
}

// Derive the project ref from auto-provisioned SUPABASE_URL (https://<ref>.supabase.co)
const EXPECTED_SUPABASE_PROJECT_REF = (() => {
  const raw = Deno.env.get('SUPABASE_URL') || ''
  const match = raw.match(/^https?:\/\/([a-z0-9]+)\.supabase\.co/i)
  return match?.[1] ?? ''
})()

function isServiceRoleJWT(token: string): boolean {
  try {
    const parts = token.split('.')
    if (parts.length !== 3) return false
    const payload = JSON.parse(atob(parts[1]))
    if (payload.role !== 'service_role') return false
    if (!EXPECTED_SUPABASE_PROJECT_REF) return false
    return payload.ref === EXPECTED_SUPABASE_PROJECT_REF
  } catch {
    return false
  }
}

serve(async (req) => {
  const corsHeaders = buildCorsHeaders(req)
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

    const cronKey = req.headers.get('x-cron-key')
    const authHeader = req.headers.get('Authorization')

    const supabase = createClient(supabaseUrl, supabaseServiceKey)

    // Non-null when the caller authenticated with a USER JWT (client queue
    // flush, Q2-35). Service-role / cron callers stay null and bypass the
    // per-user rate limit below.
    let callerUserId: string | null = null

    if (cronKey && isServiceRoleJWT(cronKey)) {
      // pg_cron bypass: verified service_role JWT via custom header
    } else if (!authHeader) {
      return new Response(JSON.stringify({ error: 'Missing authorization' }), {
        status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      })
    } else {
      const token = authHeader.replace('Bearer ', '')
      if (token === supabaseServiceKey || isServiceRoleJWT(token)) {
        // Authenticated via service role key
      } else {
        const { data: { user }, error: authError } = await supabase.auth.getUser(token)
        if (authError || !user) {
          return new Response(JSON.stringify({ error: 'Unauthorized' }), {
            status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' }
          })
        }
        callerUserId = user.id
      }
    }

    // ── Per-user flush rate limit (PR-31 residual, 2026-07-30) ────────────
    // User-JWT access is by design (client queue flush) but the batch path is
    // not user-scoped, so a hostile client could hammer the global queue.
    // 10 invocations/user/minute is ~30x a legitimate flush cadence.
    // Fails OPEN if the check_rate_limit RPC isn't deployed yet (migration
    // #206) — never brick the queue flush over missing infra.
    if (callerUserId) {
      const { data: allowed, error: rlError } = await supabase.rpc('check_rate_limit', {
        p_scope: 'push_flush',
        p_key: callerUserId,
        p_max: 10,
        p_window_seconds: 60,
      })
      if (rlError) {
        console.warn(JSON.stringify({ event: 'rate_limit_check_unavailable', detail: rlError.message }))
      } else if (allowed === false) {
        console.warn(JSON.stringify({ event: 'push_flush_rate_limited', user_id: callerUserId }))
        return new Response(JSON.stringify({ error: 'Too many requests', retry_after_seconds: 60 }), {
          status: 429,
          headers: { ...corsHeaders, 'Content-Type': 'application/json', 'Retry-After': '60' }
        })
      }
    }

    // Recover rows stuck in 'processing' for >5 minutes (edge fn crash/timeout)
    const { data: unstuck } = await supabase
      .from('push_notification_queue')
      .update({ status: 'pending', error_message: 'Recovered from stuck processing state' })
      .eq('status', 'processing')
      .lt('last_attempt_at', new Date(Date.now() - 5 * 60 * 1000).toISOString())
      .select('id')
    if (unstuck && unstuck.length > 0) {
      console.log(JSON.stringify({ event: 'stuck_processing_recovered', count: unstuck.length, ids: unstuck.map((r: { id: string }) => r.id) }))
    }

    const { data: unstuckNoAttempt } = await supabase
      .from('push_notification_queue')
      .update({ status: 'pending', error_message: 'Recovered from stuck processing state (no attempt timestamp)' })
      .eq('status', 'processing')
      .is('last_attempt_at', null)
      .lt('created_at', new Date(Date.now() - 5 * 60 * 1000).toISOString())
      .select('id')
    if (unstuckNoAttempt && unstuckNoAttempt.length > 0) {
      console.log(JSON.stringify({ event: 'stuck_processing_recovered_no_attempt', count: unstuckNoAttempt.length }))
    }

    let requestBody: { queue_id?: string; batch?: boolean } = {}
    try {
      requestBody = await req.json()
    } catch {
      // No body or invalid JSON - process batch
    }

    let query = supabase
      .from('push_notification_queue')
      .select(`
        id,
        recipient_user_id,
        notification_type,
        title,
        body,
        data,
        category,
        created_at,
        retry_count
      `)

    if (requestBody.queue_id) {
      // Status filter is NOT optional here: without it any authenticated
      // caller could replay an already-sent/failed queue row by id
      // (duplicate pushes). Only pending rows are ever eligible.
      query = query.eq('id', requestBody.queue_id).eq('status', 'pending')
    } else {
      query = query
        .eq('status', 'pending')
        .or('next_retry_at.is.null,next_retry_at.lte.' + new Date().toISOString())
        .order('created_at', { ascending: true })
        .limit(BATCH_SIZE)
    }

    const { data: pendingNotifications, error: fetchError } = await query

    if (fetchError) {
      console.error('Error fetching notifications:', fetchError)
      return new Response(JSON.stringify({ error: fetchError.message }), {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      })
    }

    if (!pendingNotifications || pendingNotifications.length === 0) {
      return new Response(JSON.stringify({
        message: 'No pending notifications',
        processed: 0
      }), {
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      })
    }

    console.log(JSON.stringify({ event: 'batch_start', pending_count: pendingNotifications.length }))

    // Atomic claim: prevent duplicate sends from concurrent invocations
    const claimedIds = pendingNotifications.map((n: { id: string }) => n.id)
    const { data: claimed } = await supabase
      .from('push_notification_queue')
      .update({ status: 'processing' })
      .in('id', claimedIds)
      .eq('status', 'pending')
      .select('id')

    const claimedIdSet = new Set((claimed || []).map((c: { id: string }) => c.id))
    const actualNotifications = pendingNotifications.filter(
      (n: { id: string }) => claimedIdSet.has(n.id)
    )

    if (actualNotifications.length === 0) {
      return new Response(JSON.stringify({
        message: 'All notifications already claimed by another invocation',
        processed: 0
      }), {
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      })
    }

    console.log(JSON.stringify({ event: 'batch_claimed', claimed: actualNotifications.length, total: pendingNotifications.length }))

    let successCount = 0
    let failCount = 0

    for (const notification of actualNotifications) {
      const userId = notification.recipient_user_id
      const category: string | null = (notification.category as string | null) ??
        (typeof notification.data?.category === 'string' ? notification.data.category : null)

      try {
        const prefs = await getUserPreferences(supabase, userId)

        // ── Master toggle ─────────────────────────────────────────────
        if (prefs && !prefs.master_enabled) {
          await pushDeliveryLog(supabase, {
            notificationId: notification.id, userId,
            event: 'prefs_blocked',
            detail: { reason: 'master_disabled', category, type: notification.notification_type },
          })
          await markNotificationFailed(supabase, notification.id, 'User disabled all notifications')
          failCount++
          continue
        }

        // ── Per-type opt-out ──────────────────────────────────────────
        const notifType = notification.data?.type || notification.notification_type || ''
        if (prefs && prefs.disabled_types?.includes(notifType)) {
          await pushDeliveryLog(supabase, {
            notificationId: notification.id, userId,
            event: 'prefs_blocked',
            detail: { reason: 'type_disabled', type: notifType, category },
          })
          await markNotificationFailed(supabase, notification.id, `User disabled ${notifType} notifications`)
          failCount++
          continue
        }

        // ── Per-category disable ──────────────────────────────────────
        if (prefs && category && prefs.category_disabled?.includes(category)) {
          await pushDeliveryLog(supabase, {
            notificationId: notification.id, userId,
            event: 'prefs_blocked',
            detail: { reason: 'category_disabled', category, type: notifType },
          })
          await markNotificationFailed(supabase, notification.id, `User disabled ${category} category`)
          failCount++
          continue
        }

        // ── Quiet hours ───────────────────────────────────────────────
        if (prefs && isInQuietHours(prefs)) {
          const retryAt = computeQuietHoursEndUTC(prefs)
          await pushDeliveryLog(supabase, {
            notificationId: notification.id, userId,
            event: 'quiet_hours_deferred',
            detail: { retry_at: retryAt.toISOString(), category, type: notifType },
          })
          await supabase
            .from('push_notification_queue')
            .update({ status: 'pending', next_retry_at: retryAt.toISOString(), error_message: 'Deferred: quiet hours active' })
            .eq('id', notification.id)
          continue
        }

        // ── Daily / category caps ─────────────────────────────────────
        // Interactive social pushes (friend request, battle cry, challenge
        // invite, workout share, etc.) bypass caps entirely. See
        // INTERACTIVE_BYPASS_TYPES rationale above.
        const bypassCaps = INTERACTIVE_BYPASS_TYPES.has(notifType)
        if (prefs && !bypassCaps) {
          const counts = await countTodaysSends(supabase, userId, prefs.timezone, category)
          const dailyCap = prefs.daily_cap
          const categoryCap = (category && prefs.category_caps && typeof prefs.category_caps[category] === 'number')
            ? prefs.category_caps[category]
            : null

          if (dailyCap > 0 && counts.totalToday >= dailyCap) {
            const retryAt = computeNextLocalMidnightUTC(prefs.timezone)
            await pushDeliveryLog(supabase, {
              notificationId: notification.id, userId,
              event: 'cap_exceeded',
              detail: { reason: 'daily_cap', cap: dailyCap, sent_today: counts.totalToday, retry_at: retryAt.toISOString(), category, type: notifType },
            })
            await supabase
              .from('push_notification_queue')
              .update({ status: 'pending', next_retry_at: retryAt.toISOString(), error_message: 'Deferred: daily cap reached' })
              .eq('id', notification.id)
            continue
          }
          if (categoryCap !== null && categoryCap > 0 && counts.categoryToday >= categoryCap) {
            const retryAt = computeNextLocalMidnightUTC(prefs.timezone)
            await pushDeliveryLog(supabase, {
              notificationId: notification.id, userId,
              event: 'cap_exceeded',
              detail: { reason: 'category_cap', category, cap: categoryCap, sent_today: counts.categoryToday, retry_at: retryAt.toISOString(), type: notifType },
            })
            await supabase
              .from('push_notification_queue')
              .update({ status: 'pending', next_retry_at: retryAt.toISOString(), error_message: `Deferred: ${category} cap reached` })
              .eq('id', notification.id)
            continue
          }
        } else if (prefs && bypassCaps) {
          // One-line audit trail so you can grep for "interactive bypassed
          // the cap" in delivery logs if a user later complains about noise.
          await pushDeliveryLog(supabase, {
            notificationId: notification.id, userId,
            event: 'cap_bypass',
            detail: { reason: 'interactive_type', type: notifType, category },
          })
        }

        // ── Resolve device tokens ─────────────────────────────────────
        const { data: allTokens, error: tokenError } = await supabase
          .from('user_push_tokens')
          .select('device_token, apns_environment, is_valid, updated_at')
          .eq('user_id', userId)

        const validTokens = (allTokens || []).filter((t: { device_token: string; is_valid: boolean; updated_at: string }) => {
          if (t.is_valid !== false) return true
          const tokenAge = Date.now() - new Date(t.updated_at).getTime()
          if (tokenAge <= 5 * 60 * 1000) {
            pushDeliveryLog(supabase, {
              notificationId: notification.id, userId,
              event: 'token_grace_period',
              detail: { token_prefix: t.device_token.substring(0, 12), age_sec: Math.round(tokenAge / 1000) },
            })
            return true
          }
          return false
        })

        if (tokenError || validTokens.length === 0) {
          await pushDeliveryLog(supabase, {
            notificationId: notification.id, userId,
            event: 'no_valid_token',
            detail: { token_error: tokenError?.message || null, total_tokens: allTokens?.length || 0 },
          })
          await markNotificationFailed(supabase, notification.id, 'No valid device token registered')
          failCount++
          continue
        }

        await pushDeliveryLog(supabase, {
          notificationId: notification.id, userId,
          event: 'token_found',
          detail: { token_count: validTokens.length, category, type: notifType },
        })

        const badgeCount = await computeBadgeCount(supabase, userId)

        // `challenge_reaction` ("smack talk") rides the visible-alert
        // queue but ALSO needs to wake the recipient's app in the
        // background so the home-screen widget can paint the comic-
        // book shout bubble before the user opens the app.
        const wakeAppForBackgroundPaint = (notification.notification_type === 'challenge_reaction')

        let anySent = false
        const perTokenResults: SendResult[] = []
        for (const tokenData of validTokens) {
          await pushDeliveryLog(supabase, {
            notificationId: notification.id, userId,
            event: 'apns_send_attempt',
            detail: { token_prefix: tokenData.device_token.substring(0, 12), apns_env: tokenData.apns_environment, category, type: notifType },
          })

          const result = await sendApnsAlert(
            tokenData.device_token,
            {
              title: notification.title,
              body: notification.body,
              data: notification.data || {},
              badge: badgeCount,
              wakeAppForBackgroundPaint,
            },
            tokenData.apns_environment,
          )
          perTokenResults.push(result)

          await pushDeliveryLog(supabase, {
            notificationId: notification.id, userId,
            event: eventNameFor(result),
            detail: {
              token_prefix: tokenData.device_token.substring(0, 12),
              apns_env: tokenData.apns_environment,
              status: result.status ?? null,
              reason: result.reason ?? null,
              duration_ms: result.durationMs ?? null,
              error: result.error ?? null,
              category,
              type: notifType,
            },
          })

          console.log(JSON.stringify({
            event: result.success ? 'apns_success' : 'apns_failed',
            notification_id: notification.id,
            user_id: userId,
            token_prefix: tokenData.device_token.substring(0, 12),
            apns_env: tokenData.apns_environment,
            duration_ms: result.durationMs,
            status: result.status,
            reason: result.reason,
            error: result.error || null,
          }))

          if (result.success) {
            anySent = true
          } else if (result.invalidateToken) {
            await supabase
              .from('user_push_tokens')
              .update({ is_valid: false })
              .eq('user_id', userId)
              .eq('device_token', tokenData.device_token)
            await pushDeliveryLog(supabase, {
              notificationId: notification.id, userId,
              event: 'token_invalid',
              detail: { token_prefix: tokenData.device_token.substring(0, 12), reason: result.reason ?? 'apple_410ish' },
            })
          }
        }

        if (anySent) {
          await markNotificationSent(supabase, notification.id)
          successCount++
        } else {
          // Use the most-recent error for retry classification
          const last = perTokenResults[perTokenResults.length - 1]
          const errorMessage = last?.error ?? 'All device tokens failed'
          const retryCount = notification.retry_count || 0
          await markNotificationFailed(supabase, notification.id, errorMessage, retryCount)
          failCount++
        }

      } catch (error) {
        console.error(`Error processing notification ${notification.id}:`, error)
        await pushDeliveryLog(supabase, {
          notificationId: notification.id, userId,
          event: 'send_threw',
          detail: { error: String(error) },
        })
        const retryCount = notification.retry_count || 0
        await markNotificationFailed(supabase, notification.id, String(error), retryCount)
        failCount++
      }
    }

    return new Response(JSON.stringify({
      message: 'Notifications processed',
      processed: actualNotifications.length,
      success: successCount,
      failed: failCount
    }), {
      status: 200,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })

  } catch (error) {
    console.error('Edge function error:', error)
    return new Response(JSON.stringify({ error: String(error) }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  }
})

async function markNotificationSent(supabase: ReturnType<typeof createClient>, id: string) {
  await supabase
    .from('push_notification_queue')
    .update({
      status: 'sent',
      sent_at: new Date().toISOString()
    })
    .eq('id', id)
}

async function markNotificationFailed(
  supabase: ReturnType<typeof createClient>,
  id: string,
  errorMessage: string,
  retryCount: number = 0
) {
  const isPermanentFailure =
    errorMessage.includes('BadDeviceToken') ||
    errorMessage.includes('Unregistered') ||
    errorMessage.includes('TopicDisallowed') ||
    errorMessage.includes('DeviceTokenNotForTopic') ||
    errorMessage.includes('ExpiredProviderToken') ||
    errorMessage.includes('InvalidProviderToken') ||
    errorMessage.includes('No valid device token') ||
    errorMessage.includes('User disabled') ||
    errorMessage.includes('type disabled') ||
    errorMessage.includes('All device tokens failed')

  if (isPermanentFailure || retryCount >= MAX_RETRIES) {
    await supabase
      .from('push_notification_queue')
      .update({
        status: 'failed',
        error_message: errorMessage,
        last_attempt_at: new Date().toISOString()
      })
      .eq('id', id)

    console.log(JSON.stringify({ event: 'notification_failed_permanent', notification_id: id, error: errorMessage, retry_count: retryCount }))
  } else {
    const nextRetryAt = new Date(Date.now() + Math.pow(2, retryCount + 1) * 60 * 1000)

    await supabase
      .from('push_notification_queue')
      .update({
        status: 'pending',
        retry_count: retryCount + 1,
        error_message: errorMessage,
        last_attempt_at: new Date().toISOString(),
        next_retry_at: nextRetryAt.toISOString()
      })
      .eq('id', id)

    console.log(JSON.stringify({ event: 'notification_retry_scheduled', notification_id: id, retry_count: retryCount + 1, next_retry_at: nextRetryAt.toISOString(), error: errorMessage }))
  }
}

async function computeBadgeCount(
  supabase: ReturnType<typeof createClient>,
  userId: string
): Promise<number> {
  try {
    const { count: friendRequests } = await supabase
      .from('friendships')
      .select('*', { count: 'exact', head: true })
      .eq('addressee_id', userId)
      .eq('status', 'pending')

    const { count: challengeInvites } = await supabase
      .from('challenge_participants')
      .select('*', { count: 'exact', head: true })
      .eq('user_id', userId)
      .eq('status', 'pending')

    const { count: unreadWorkouts } = await supabase
      .from('shared_workouts')
      .select('*', { count: 'exact', head: true })
      .eq('recipient_id', userId)
      .is('viewed_at', null)
      .eq('status', 'pending')

    const { count: privateChallengeInvites } = await supabase
      .from('private_challenge_invites')
      .select('*', { count: 'exact', head: true })
      .eq('invited_user_id', userId)
      .eq('status', 'pending')

    const total = (friendRequests || 0) + (challengeInvites || 0) + (unreadWorkouts || 0) + (privateChallengeInvites || 0)
    console.log(JSON.stringify({ event: 'badge_count', user_id: userId, total, friends: friendRequests || 0, challenges: challengeInvites || 0, workouts: unreadWorkouts || 0, private_invites: privateChallengeInvites || 0 }))
    return total
  } catch (error) {
    console.error(`Error computing badge count for user ${userId}:`, error)
    return 0
  }
}
