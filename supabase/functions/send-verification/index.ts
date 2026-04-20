// =====================================================
// SEND SMS VERIFICATION CODE
// Supabase Edge Function + Twilio Verify
// =====================================================
// This edge function sends a verification code via Twilio Verify
//
// SECURITY:
//   - Requires a valid Supabase user JWT (signed-in user).
//   - Rate limit is enforced via a DB-backed UPSERT so it survives
//     Edge Function cold starts. Falls back to in-memory if the RPC fails.
//
// SETUP REQUIRED:
// 1. Create Twilio account at https://twilio.com
// 2. Create a Verify Service in Twilio Console
// 3. Add these secrets to Supabase:
//    - TWILIO_ACCOUNT_SID
//    - TWILIO_AUTH_TOKEN
//    - TWILIO_VERIFY_SERVICE_SID
// 4. Run migration 20260417_phone_verification_rate_limit.sql
//
// Deploy with: supabase functions deploy send-verification
// =====================================================

import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"
import { buildCorsHeaders, requireUserAuth } from "../_shared/cors.ts"
import { redactPhone } from "../_shared/log.ts"

// Fallback in-memory limiter — only used if the DB RPC is unavailable.
const sendRateLimitMap = new Map<string, { count: number; resetAt: number }>()
const SEND_RATE_LIMIT_MAX = 10
const SEND_RATE_LIMIT_WINDOW_MS = 3600_000 // 1 hour

function checkInMemoryRateLimit(phone: string): boolean {
  const now = Date.now()
  const entry = sendRateLimitMap.get(phone)
  if (!entry || now >= entry.resetAt) {
    sendRateLimitMap.set(phone, { count: 1, resetAt: now + SEND_RATE_LIMIT_WINDOW_MS })
    return true
  }
  entry.count++
  return entry.count <= SEND_RATE_LIMIT_MAX
}

// deno-lint-ignore no-explicit-any
async function checkDbRateLimit(supabase: any, phone: string): Promise<boolean> {
  try {
    const { data, error } = await supabase.rpc('check_phone_verification_rate_limit', {
      p_phone_number: phone,
      p_max_attempts: SEND_RATE_LIMIT_MAX,
      p_window_seconds: Math.floor(SEND_RATE_LIMIT_WINDOW_MS / 1000),
    })
    if (error) {
      console.warn('DB rate limit RPC failed, falling back to in-memory:', error.message)
      return checkInMemoryRateLimit(phone)
    }
    // RPC returns true if allowed, false if over the limit.
    return data === true
  } catch (e) {
    console.warn('DB rate limit RPC threw, falling back to in-memory:', e)
    return checkInMemoryRateLimit(phone)
  }
}

serve(async (req) => {
  const corsHeaders = buildCorsHeaders(req)

  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const twilioAccountSid = Deno.env.get('TWILIO_ACCOUNT_SID')
    const twilioAuthToken = Deno.env.get('TWILIO_AUTH_TOKEN')
    const twilioVerifyServiceSid = Deno.env.get('TWILIO_VERIFY_SERVICE_SID')

    if (!twilioAccountSid || !twilioAuthToken || !twilioVerifyServiceSid) {
      return new Response(
        JSON.stringify({ success: false, error: 'Server configuration error' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 500 }
      )
    }

    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const supabase = createClient(supabaseUrl, supabaseKey)

    // Require a valid user JWT (or service-role). Anonymous callers were
    // previously able to burn Twilio credit via this endpoint.
    const authResult = await requireUserAuth(req, supabase, corsHeaders)
    if (!authResult.ok) return authResult.response

    const { phone_number } = await req.json()

    if (!phone_number) {
      return new Response(
        JSON.stringify({ success: false, error: 'Phone number is required' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 400 }
      )
    }

    // Format phone number (ensure it starts with +1 for US)
    let formattedPhone = phone_number.replace(/\D/g, '') // Remove non-digits
    if (formattedPhone.length === 10) {
      formattedPhone = '+1' + formattedPhone // Add US country code
    } else if (!formattedPhone.startsWith('+')) {
      formattedPhone = '+' + formattedPhone
    }

    // DB-backed rate limit keyed on normalized phone number.
    const allowed = await checkDbRateLimit(supabase, formattedPhone)
    if (!allowed) {
      return new Response(
        JSON.stringify({ success: false, error: 'Too many verification attempts. Please try again later.' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 429 }
      )
    }

    // Sprint 3 (M-10): shared redactor for consistent masking across
    // every edge function that touches a phone number.
    console.log(`Sending verification to: ${redactPhone(formattedPhone)}`)

    // Send verification via Twilio Verify API
    const twilioUrl = `https://verify.twilio.com/v2/Services/${twilioVerifyServiceSid}/Verifications`

    const twilioResponse = await fetch(twilioUrl, {
      method: 'POST',
      headers: {
        'Authorization': 'Basic ' + btoa(`${twilioAccountSid}:${twilioAuthToken}`),
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: new URLSearchParams({
        'To': formattedPhone,
        'Channel': 'sms',
      }),
    })

    const twilioData = await twilioResponse.json()

    if (!twilioResponse.ok) {
      console.error('Twilio error:', twilioData)
      throw new Error(twilioData.message || 'Failed to send verification')
    }

    console.log(`Verification sent successfully. Status: ${twilioData.status}`)

    // Record the RPC-side bookkeeping for the verified user (if we have one).
    if (authResult.auth.userId) {
      const { error: rpcError } = await supabase.rpc('start_phone_verification', {
        p_phone_number: formattedPhone
      })
      if (rpcError) {
        console.error('RPC start_phone_verification failed:', rpcError.message)
      }
    }

    return new Response(
      JSON.stringify({
        success: true,
        status: twilioData.status,
        message: 'Verification code sent'
      }),
      {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 200,
      }
    )

  } catch (error) {
    console.error('Error:', error.message)
    const isClientError = error.message === 'Failed to send verification' || error.message?.includes('Invalid')
    return new Response(
      JSON.stringify({
        success: false,
        error: error.message
      }),
      {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: isClientError ? 400 : 500,
      }
    )
  }
})
