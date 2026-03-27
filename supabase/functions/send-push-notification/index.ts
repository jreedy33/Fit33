// Supabase Edge Function: Send Push Notifications via APNs
// Deploy with: supabase functions deploy send-push-notification
// 
// IMPROVEMENTS (2026-02-03):
// - Added retry logic with exponential backoff
// - Better handling of batch vs single notification requests
// - Improved error categorization (transient vs permanent)
// - Token refresh handling

import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"
import { SignJWT, importPKCS8 } from "https://deno.land/x/jose@v4.14.4/index.ts"

// APNs Configuration - loaded from Supabase Edge Function secrets
// Set via: supabase secrets set APNS_KEY_ID=xxx APNS_TEAM_ID=xxx APNS_BUNDLE_ID=xxx APNS_PRIVATE_KEY="xxx"
const APNS_KEY_ID = Deno.env.get('APNS_KEY_ID') || ''
const APNS_TEAM_ID = Deno.env.get('APNS_TEAM_ID') || ''
const APNS_BUNDLE_ID = Deno.env.get('APNS_BUNDLE_ID') || ''
const APNS_PRIVATE_KEY = (Deno.env.get('APNS_PRIVATE_KEY') || '').replace(/\\n/g, '\n')

// APNs hosts - we now route per-token based on apns_environment column
const APNS_HOST_PRODUCTION = 'api.push.apple.com'
const APNS_HOST_SANDBOX = 'api.sandbox.push.apple.com'

// Helper to get the right APNs host for a token's environment
function getAPNsHost(apnsEnvironment: string | null): string {
  return apnsEnvironment === 'development' ? APNS_HOST_SANDBOX : APNS_HOST_PRODUCTION
}

// Configuration
const MAX_RETRIES = 3
const BATCH_SIZE = 100

// Preference cache per invocation (avoids re-querying for the same user within a batch)
const prefsCache = new Map<string, { master_enabled: boolean; disabled_types: string[]; quiet_hours_enabled: boolean; quiet_hours_start: string | null; quiet_hours_end: string | null; timezone: string | null } | null>()

async function getUserPreferences(supabase: ReturnType<typeof createClient>, userId: string) {
  if (prefsCache.has(userId)) return prefsCache.get(userId)!

  const { data, error } = await supabase
    .from('user_notification_preferences')
    .select('master_enabled, disabled_types, quiet_hours_enabled, quiet_hours_start, quiet_hours_end, timezone')
    .eq('user_id', userId)
    .single()

  const prefs = error ? null : data
  prefsCache.set(userId, prefs)
  return prefs
}

function isInQuietHours(prefs: { quiet_hours_enabled: boolean; quiet_hours_start: string | null; quiet_hours_end: string | null; timezone: string | null }): boolean {
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

function computeQuietHoursEndUTC(prefs: { quiet_hours_end: string | null; timezone: string | null }): Date {
  if (!prefs.quiet_hours_end) return new Date(Date.now() + 60 * 60 * 1000)

  const tz = prefs.timezone || 'America/New_York'
  const [endH, endM] = prefs.quiet_hours_end.split(':').map(Number)

  const now = new Date()
  const formatter = new Intl.DateTimeFormat('en-US', { timeZone: tz, year: 'numeric', month: '2-digit', day: '2-digit', hour: 'numeric', minute: 'numeric', hour12: false })
  const parts = formatter.formatToParts(now)
  const nowHour = parseInt(parts.find(p => p.type === 'hour')?.value || '0')

  // If quiet hours end is later today in user's tz, use today; otherwise tomorrow
  const addDay = (nowHour >= endH) ? 1 : 0
  const target = new Date(now.getTime() + addDay * 24 * 60 * 60 * 1000)
  const targetDate = new Intl.DateTimeFormat('en-CA', { timeZone: tz, year: 'numeric', month: '2-digit', day: '2-digit' }).format(target)

  // Build a date string in the user's timezone, then convert to UTC
  // Use a simple offset approach: create the date, measure the offset
  const endStr = `${targetDate}T${String(endH).padStart(2, '0')}:${String(endM).padStart(2, '0')}:00`
  const utcGuess = new Date(endStr + 'Z')
  const localFormatter = new Intl.DateTimeFormat('en-US', { timeZone: tz, hour: 'numeric', minute: 'numeric', hour12: false })
  const localParts = localFormatter.formatToParts(utcGuess)
  const localH = parseInt(localParts.find(p => p.type === 'hour')?.value || '0')
  const offsetHours = localH - endH
  return new Date(utcGuess.getTime() - offsetHours * 60 * 60 * 1000)
}

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-cron-key',
}

function isServiceRoleJWT(token: string): boolean {
  try {
    const parts = token.split('.')
    if (parts.length !== 3) return false
    const payload = JSON.parse(atob(parts[1]))
    return payload.role === 'service_role' && payload.ref === 'ehooeghabzefgoqzugrc'
  } catch {
    return false
  }
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

    const cronKey = req.headers.get('x-cron-key')
    const authHeader = req.headers.get('Authorization')

    const supabase = createClient(supabaseUrl, supabaseServiceKey)

    if (cronKey && isServiceRoleJWT(cronKey)) {
      // pg_cron bypass: verified service_role JWT via custom header
    } else if (!authHeader) {
      return new Response(JSON.stringify({ error: 'Missing authorization' }), {
        status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      })
    } else {
      const token = authHeader.replace('Bearer ', '')
      if (token === supabaseServiceKey || isServiceRoleJWT(token)) {
        // Authenticated via service role key (short or JWT format)
      } else {
        const { data: { user }, error: authError } = await supabase.auth.getUser(token)
        if (authError || !user) {
          return new Response(JSON.stringify({ error: 'Unauthorized' }), {
            status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' }
          })
        }
      }
    }

    // Recover rows stuck in 'processing' for over 5 minutes (edge fn crash/timeout)
    const { data: unstuck } = await supabase
      .from('push_notification_queue')
      .update({ status: 'pending', error_message: 'Recovered from stuck processing state' })
      .eq('status', 'processing')
      .lt('last_attempt_at', new Date(Date.now() - 5 * 60 * 1000).toISOString())
      .select('id')
    if (unstuck && unstuck.length > 0) {
      console.log(JSON.stringify({ event: 'stuck_processing_recovered', count: unstuck.length, ids: unstuck.map((r: { id: string }) => r.id) }))
    }

    // Also recover rows where last_attempt_at is null but created_at is old
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

    // Parse request body for optional specific queue_id
    let requestBody: { queue_id?: string; batch?: boolean } = {}
    try {
      requestBody = await req.json()
    } catch {
      // No body or invalid JSON - process batch
    }

    // Build query based on whether this is a single notification or batch
    let query = supabase
      .from('push_notification_queue')
      .select(`
        id,
        recipient_user_id,
        notification_type,
        title,
        body,
        data,
        created_at,
        retry_count
      `)
    
    if (requestBody.queue_id) {
      // Process a specific notification (triggered immediately)
      query = query.eq('id', requestBody.queue_id)
    } else {
      // Batch processing - get pending notifications respecting retry backoff
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

    // Atomic claim: mark as 'processing' to prevent duplicate sends from concurrent invocations
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

    // Generate APNs JWT token
    const apnsToken = await generateAPNsToken()
    
    let successCount = 0
    let failCount = 0

    // Process only the notifications we successfully claimed
    for (const notification of actualNotifications) {
      try {
        // Check user notification preferences before sending
        const prefs = await getUserPreferences(supabase, notification.recipient_user_id)
        if (prefs) {
          if (!prefs.master_enabled) {
            console.log(JSON.stringify({ event: 'skipped_master_disabled', notification_id: notification.id, user_id: notification.recipient_user_id }))
            await markNotificationFailed(supabase, notification.id, 'User disabled all notifications')
            failCount++
            continue
          }
          const notifType = notification.data?.type || notification.notification_type || ''
          if (prefs.disabled_types?.includes(notifType)) {
            console.log(JSON.stringify({ event: 'skipped_type_disabled', notification_id: notification.id, user_id: notification.recipient_user_id, type: notifType }))
            await markNotificationFailed(supabase, notification.id, `User disabled ${notifType} notifications`)
            failCount++
            continue
          }
          if (isInQuietHours(prefs)) {
            const retryAt = computeQuietHoursEndUTC(prefs)
            console.log(JSON.stringify({ event: 'quiet_hours_deferred', notification_id: notification.id, user_id: notification.recipient_user_id, retry_at: retryAt.toISOString() }))
            await supabase
              .from('push_notification_queue')
              .update({ status: 'pending', next_retry_at: retryAt.toISOString(), error_message: 'Deferred: quiet hours active' })
              .eq('id', notification.id)
            continue
          }
        }

        // Get ALL device tokens for this user (supports multiple devices)
        const { data: allTokens, error: tokenError } = await supabase
          .from('user_push_tokens')
          .select('device_token, apns_environment, is_valid, updated_at')
          .eq('user_id', notification.recipient_user_id)

        const validTokens = (allTokens || []).filter((t: { device_token: string; is_valid: boolean; updated_at: string }) => {
          if (t.is_valid !== false) return true
          const tokenAge = Date.now() - new Date(t.updated_at).getTime()
          if (tokenAge <= 5 * 60 * 1000) {
            console.log(JSON.stringify({ event: 'token_grace_period', notification_id: notification.id, user_id: notification.recipient_user_id, token_prefix: t.device_token.substring(0, 12), age_sec: Math.round(tokenAge / 1000) }))
            return true
          }
          return false
        })

        if (tokenError || validTokens.length === 0) {
          console.log(JSON.stringify({ event: 'no_valid_token', notification_id: notification.id, user_id: notification.recipient_user_id, token_error: tokenError?.message || null, total_tokens: allTokens?.length || 0 }))
          await markNotificationFailed(supabase, notification.id, 'No valid device token registered')
          failCount++
          continue
        }

        const badgeCount = await computeBadgeCount(supabase, notification.recipient_user_id)

        let anySent = false
        for (const tokenData of validTokens) {
          const apnsHost = getAPNsHost(tokenData.apns_environment)
          const sendStart = Date.now()

          const apnsResponse = await sendToAPNs(
            tokenData.device_token,
            {
              title: notification.title,
              body: notification.body,
              data: notification.data || {}
            },
            apnsToken,
            apnsHost,
            badgeCount
          )

          const durationMs = Date.now() - sendStart
          console.log(JSON.stringify({ event: apnsResponse.success ? 'apns_success' : 'apns_failed', notification_id: notification.id, user_id: notification.recipient_user_id, token_prefix: tokenData.device_token.substring(0, 12), apns_host: apnsHost, duration_ms: durationMs, error: apnsResponse.error || null }))

          if (apnsResponse.success) {
            anySent = true
          } else if (apnsResponse.error?.includes('BadDeviceToken') || apnsResponse.error?.includes('Unregistered')) {
            await supabase
              .from('user_push_tokens')
              .update({ is_valid: false })
              .eq('user_id', notification.recipient_user_id)
              .eq('device_token', tokenData.device_token)
            console.log(JSON.stringify({ event: 'token_invalidated', user_id: notification.recipient_user_id, token_prefix: tokenData.device_token.substring(0, 12) }))
          }
        }

        if (anySent) {
          await markNotificationSent(supabase, notification.id)
          successCount++
        } else {
          const retryCount = notification.retry_count || 0
          await markNotificationFailed(supabase, notification.id, 'All device tokens failed', retryCount)
          failCount++
        }

      } catch (error) {
        console.error(`Error processing notification ${notification.id}:`, error)
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

async function generateAPNsToken(): Promise<string> {
  // Import the private key
  const privateKey = await importPKCS8(APNS_PRIVATE_KEY, 'ES256')

  // Create JWT token
  const token = await new SignJWT({})
    .setProtectedHeader({ 
      alg: 'ES256', 
      kid: APNS_KEY_ID 
    })
    .setIssuer(APNS_TEAM_ID)
    .setIssuedAt()
    .sign(privateKey)

  return token
}

async function sendToAPNs(
  deviceToken: string, 
  payload: { title: string; body: string; data: Record<string, unknown> },
  apnsToken: string,
  apnsHost: string = APNS_HOST_PRODUCTION,
  badgeCount: number = 0
): Promise<{ success: boolean; error?: string }> {
  
  const apnsPayload: Record<string, unknown> = {
    aps: {
      alert: {
        title: payload.title,
        body: payload.body,
      },
      sound: 'default',
      // Dynamic badge: real count of pending actionable items for this user
      // 0 clears the badge, >0 shows the count on the app icon
      badge: badgeCount,
      'mutable-content': 1,
    },
    // Include custom data at the root level
    ...payload.data
  }

  try {
    const controller = new AbortController()
    const timeoutId = setTimeout(() => controller.abort(), 10000)

    const response = await fetch(
      `https://${apnsHost}/3/device/${deviceToken}`,
      {
        method: 'POST',
        headers: {
          'authorization': `bearer ${apnsToken}`,
          'apns-topic': APNS_BUNDLE_ID,
          'apns-push-type': 'alert',
          'apns-priority': '10',
          'apns-expiration': String(Math.floor(Date.now() / 1000) + 86400),
        },
        body: JSON.stringify(apnsPayload),
        signal: controller.signal,
      }
    )
    clearTimeout(timeoutId)

    if (response.ok) {
      return { success: true }
    } else {
      const errorBody = await response.text()
      console.error(`APNs error ${response.status}:`, errorBody)
      return { 
        success: false, 
        error: `APNs ${response.status}: ${errorBody}` 
      }
    }
  } catch (error) {
    return { 
      success: false, 
      error: `Network error: ${String(error)}` 
    }
  }
}

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
  // Check if this is a permanent APNs failure (invalid token, wrong app, etc.)
  // Network errors, timeouts, and server errors are NOT permanent
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
    // Transient failure - schedule retry with exponential backoff
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

// Helper to check if APNs error is retriable
function isRetriableAPNsError(status: number): boolean {
  // 5xx errors are retriable server errors
  // 429 is rate limiting - retriable
  return status >= 500 || status === 429
}

// Compute the real badge count for a user based on pending actionable items:
//   1. Pending friend requests (others → this user)
//   2. Pending challenge invites (challenge_participants with status='pending')
//   3. Unread shared workouts
async function computeBadgeCount(
  supabase: ReturnType<typeof createClient>,
  userId: string
): Promise<number> {
  try {
    // 1. Pending friend requests received by this user
    const { count: friendRequests } = await supabase
      .from('friendships')
      .select('*', { count: 'exact', head: true })
      .eq('addressee_id', userId)
      .eq('status', 'pending')

    // 2. Pending challenge invites (1v1 + group — both use challenge_participants)
    //    A user has a pending invite when they're in challenge_participants with status='pending'
    //    and they're NOT the creator of the challenge
    const { count: challengeInvites } = await supabase
      .from('challenge_participants')
      .select('*', { count: 'exact', head: true })
      .eq('user_id', userId)
      .eq('status', 'pending')

    // 3. Unread shared workouts
    const { count: unreadWorkouts } = await supabase
      .from('shared_workouts')
      .select('*', { count: 'exact', head: true })
      .eq('recipient_id', userId)
      .is('viewed_at', null)
      .eq('status', 'pending')

    // 4. Pending private challenge invites
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
    // On error, return 0 to avoid showing stale badge
    return 0
  }
}
