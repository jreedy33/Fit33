// Supabase Edge Function: Send Push Notifications via APNs
// Deploy with: supabase functions deploy send-push-notification

import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"
import { SignJWT, importPKCS8 } from "https://deno.land/x/jose@v4.14.4/index.ts"

// APNs Configuration - loaded from Supabase Edge Function secrets
// Set via: supabase secrets set APNS_KEY_ID=xxx APNS_TEAM_ID=xxx APNS_BUNDLE_ID=xxx APNS_PRIVATE_KEY="xxx"
const APNS_KEY_ID = Deno.env.get('APNS_KEY_ID') || ''
const APNS_TEAM_ID = Deno.env.get('APNS_TEAM_ID') || ''
const APNS_BUNDLE_ID = Deno.env.get('APNS_BUNDLE_ID') || ''
const APNS_PRIVATE_KEY = (Deno.env.get('APNS_PRIVATE_KEY') || '').replace(/\\n/g, '\n')

// APNs environment - defaults to sandbox for safety
const APNS_ENVIRONMENT = Deno.env.get('APNS_ENVIRONMENT') || 'development'
const APNS_HOST = APNS_ENVIRONMENT === 'production' 
  ? 'api.push.apple.com' 
  : 'api.sandbox.push.apple.com'

serve(async (req) => {
  try {
    // Create Supabase client with service role for full access
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    
    const supabase = createClient(supabaseUrl, supabaseServiceKey)

    // Get pending notifications with device tokens
    const { data: pendingNotifications, error: fetchError } = await supabase
      .from('push_notification_queue')
      .select(`
        id,
        recipient_user_id,
        notification_type,
        title,
        body,
        data,
        created_at
      `)
      .eq('status', 'pending')
      .order('created_at', { ascending: true })
      .limit(100)

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
        // Get device token for this user
        const { data: tokenData, error: tokenError } = await supabase
          .from('user_push_tokens')
          .select('device_token')
          .eq('user_id', notification.recipient_user_id)
          .single()

        if (tokenError || !tokenData?.device_token) {
          console.log(`No device token for user ${notification.recipient_user_id}`)
          await markNotificationFailed(supabase, notification.id, 'No device token registered')
          failCount++
          continue
        }

        // Send to APNs
        const apnsResponse = await sendToAPNs(
          tokenData.device_token,
          {
            title: notification.title,
            body: notification.body,
            data: notification.data || {}
          },
          apnsToken
        )

        if (apnsResponse.success) {
          await markNotificationSent(supabase, notification.id)
          successCount++
          console.log(`✅ Notification sent to user ${notification.recipient_user_id}`)
        } else {
          await markNotificationFailed(supabase, notification.id, apnsResponse.error || 'APNs error')
          failCount++
          console.log(`❌ Failed for user ${notification.recipient_user_id}: ${apnsResponse.error}`)
        }

      } catch (error) {
        console.error(`Error processing notification ${notification.id}:`, error)
        await markNotificationFailed(supabase, notification.id, String(error))
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
  apnsToken: string
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
      `https://${APNS_HOST}/3/device/${deviceToken}`,
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

async function markNotificationFailed(supabase: ReturnType<typeof createClient>, id: string, errorMessage: string) {
  await supabase
    .from('push_notification_queue')
    .update({ 
      status: 'failed', 
      error_message: errorMessage 
    })
    .eq('id', id)
}
