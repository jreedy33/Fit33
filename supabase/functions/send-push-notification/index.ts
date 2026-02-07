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

serve(async (req) => {
  try {
    // Parse request body for optional specific queue_id
    let requestBody: { queue_id?: string; batch?: boolean } = {}
    try {
      requestBody = await req.json()
    } catch {
      // No body or invalid JSON - process batch
    }

    // Create Supabase client with service role for full access
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    
    const supabase = createClient(supabaseUrl, supabaseServiceKey)

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
        headers: { 'Content-Type': 'application/json' }
      })
    }

    if (!pendingNotifications || pendingNotifications.length === 0) {
      return new Response(JSON.stringify({ 
        message: 'No pending notifications',
        processed: 0 
      }), { 
        status: 200,
        headers: { 'Content-Type': 'application/json' }
      })
    }

    console.log(`Processing ${pendingNotifications.length} notifications`)

    // Generate APNs JWT token
    const apnsToken = await generateAPNsToken()
    
    let successCount = 0
    let failCount = 0

    // Process each notification
    for (const notification of pendingNotifications) {
      try {
        // Get device token and APNs environment for this user
        const { data: tokenData, error: tokenError } = await supabase
          .from('user_push_tokens')
          .select('device_token, apns_environment, is_valid, updated_at')
          .eq('user_id', notification.recipient_user_id)
          .single()

        if (tokenError || !tokenData?.device_token) {
          console.log(`No device token for user ${notification.recipient_user_id}`)
          await markNotificationFailed(supabase, notification.id, 'No device token registered')
          failCount++
          continue
        }

        // Only skip invalid tokens if they haven't been refreshed recently
        // When a user opens the app, is_valid is reset to true and updated_at is refreshed
        // Give a 5-minute grace period after invalidation before skipping
        if (tokenData.is_valid === false) {
          const tokenAge = Date.now() - new Date(tokenData.updated_at).getTime()
          const fiveMinutes = 5 * 60 * 1000
          if (tokenAge > fiveMinutes) {
            console.log(`Token invalid for user ${notification.recipient_user_id} (stale ${Math.round(tokenAge/60000)}min) - skipping`)
            await markNotificationFailed(supabase, notification.id, 'Device token invalid - user needs to re-open app')
            failCount++
            continue
          }
          // Token was recently updated — user may have just reopened the app
          // Try sending anyway and let APNs decide
          console.log(`Token was invalid but recently refreshed (${Math.round(tokenAge/1000)}s ago) - attempting delivery`)
        }

        // Determine which APNs host to use based on token's environment
        const apnsHost = getAPNsHost(tokenData.apns_environment)
        console.log(`Using APNs host: ${apnsHost} for user ${notification.recipient_user_id}`)

        // Send to APNs
        const apnsResponse = await sendToAPNs(
          tokenData.device_token,
          {
            title: notification.title,
            body: notification.body,
            data: notification.data || {}
          },
          apnsToken,
          apnsHost
        )

        if (apnsResponse.success) {
          await markNotificationSent(supabase, notification.id)
          successCount++
          console.log(`✅ Notification sent to user ${notification.recipient_user_id}`)
        } else {
          const retryCount = notification.retry_count || 0
          await markNotificationFailed(supabase, notification.id, apnsResponse.error || 'APNs error', retryCount)
          failCount++
          console.log(`❌ Failed for user ${notification.recipient_user_id}: ${apnsResponse.error}`)
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
      processed: pendingNotifications.length,
      success: successCount,
      failed: failCount
    }), { 
      status: 200,
      headers: { 'Content-Type': 'application/json' }
    })

  } catch (error) {
    console.error('Edge function error:', error)
    return new Response(JSON.stringify({ error: String(error) }), { 
      status: 500,
      headers: { 'Content-Type': 'application/json' }
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
  apnsHost: string = APNS_HOST_PRODUCTION
): Promise<{ success: boolean; error?: string }> {
  
  const apnsPayload = {
    aps: {
      alert: {
        title: payload.title,
        body: payload.body,
      },
      sound: 'default',
      badge: 1,
      'mutable-content': 1,
    },
    // Include custom data at the root level
    ...payload.data
  }

  try {
    const response = await fetch(
      `https://${apnsHost}/3/device/${deviceToken}`,
      {
        method: 'POST',
        headers: {
          'authorization': `bearer ${apnsToken}`,
          'apns-topic': APNS_BUNDLE_ID,
          'apns-push-type': 'alert',
          'apns-priority': '10',
          'apns-expiration': '0',
        },
        body: JSON.stringify(apnsPayload)
      }
    )

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
    errorMessage.includes('InvalidProviderToken')
  
  // Don't invalidate tokens for transient/network errors
  const shouldInvalidateToken = 
    errorMessage.includes('BadDeviceToken') ||
    errorMessage.includes('Unregistered')

  if (isPermanentFailure || retryCount >= MAX_RETRIES) {
    // Permanent failure - mark as failed
    await supabase
      .from('push_notification_queue')
      .update({ 
        status: 'failed', 
        error_message: errorMessage,
        last_attempt_at: new Date().toISOString()
      })
      .eq('id', id)
    
    // Only invalidate token for confirmed bad/unregistered tokens (not network errors)
    if (shouldInvalidateToken) {
      const { data: notification } = await supabase
        .from('push_notification_queue')
        .select('recipient_user_id')
        .eq('id', id)
        .single()
      
      if (notification?.recipient_user_id) {
        await supabase
          .from('user_push_tokens')
          .update({ is_valid: false })
          .eq('user_id', notification.recipient_user_id)
        
        console.log(`Marked device token as invalid for user ${notification.recipient_user_id}`)
      }
    }
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
    
    console.log(`Scheduled retry ${retryCount + 1} for notification ${id} at ${nextRetryAt.toISOString()}`)
  }
}

// Helper to check if APNs error is retriable
function isRetriableAPNsError(status: number): boolean {
  // 5xx errors are retriable server errors
  // 429 is rate limiting - retriable
  return status >= 500 || status === 429
}
