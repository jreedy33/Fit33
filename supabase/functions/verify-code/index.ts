// =====================================================
// VERIFY SMS CODE
// Supabase Edge Function + Twilio Verify
// =====================================================
// This edge function verifies the code entered by the user.
//
// Sprint 2 (2026-04-18) — migrated off `Access-Control-Allow-Origin: *`
// onto the shared buildCorsHeaders allowlist. Also now requires the caller
// to authenticate (user JWT or service role). The platform already applies
// verify_jwt=true, so this is defense in depth.
//
// Deploy with: supabase functions deploy verify-code
// =====================================================

import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"
import { buildCorsHeaders, requireUserAuth } from "../_shared/cors.ts"

const verifyRateLimitMap = new Map<string, { count: number; resetAt: number }>()
const VERIFY_RATE_LIMIT_MAX = 15
const VERIFY_RATE_LIMIT_WINDOW_MS = 900_000 // 15 minutes

function checkVerifyRateLimit(phone: string): boolean {
  const now = Date.now()
  const entry = verifyRateLimitMap.get(phone)
  if (!entry || now >= entry.resetAt) {
    verifyRateLimitMap.set(phone, { count: 1, resetAt: now + VERIFY_RATE_LIMIT_WINDOW_MS })
    return true
  }
  entry.count++
  return entry.count <= VERIFY_RATE_LIMIT_MAX
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

    // Require a valid caller (user JWT or service role). No anonymous verifies.
    const authResult = await requireUserAuth(req, supabase, corsHeaders)
    if (!authResult.ok) return authResult.response

    const { phone_number, code } = await req.json()

    if (!phone_number || !code) {
      return new Response(
        JSON.stringify({ success: false, error: 'Phone number and code are required' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 400 }
      )
    }

    if (!checkVerifyRateLimit(phone_number)) {
      return new Response(
        JSON.stringify({ success: false, error: 'Too many verification attempts. Please try again later.' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 429 }
      )
    }

    // Format phone number (ensure it starts with +1 for US)
    let formattedPhone = phone_number.replace(/\D/g, '') // Remove non-digits
    if (formattedPhone.length === 10) {
      formattedPhone = '+1' + formattedPhone // Add US country code
    } else if (!formattedPhone.startsWith('+')) {
      formattedPhone = '+' + formattedPhone
    }

    const redacted = formattedPhone.slice(0, -4).replace(/\d/g, '*') + formattedPhone.slice(-4)
    console.log(`Verifying code for: ${redacted}`)

    // Verify code via Twilio Verify API
    const twilioUrl = `https://verify.twilio.com/v2/Services/${twilioVerifyServiceSid}/VerificationCheck`

    const twilioResponse = await fetch(twilioUrl, {
      method: 'POST',
      headers: {
        'Authorization': 'Basic ' + btoa(`${twilioAccountSid}:${twilioAuthToken}`),
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: new URLSearchParams({
        'To': formattedPhone,
        'Code': code,
      }),
    })

    const twilioData = await twilioResponse.json()

    if (!twilioResponse.ok) {
      // Don't leak Twilio's error payload to clients.
      console.error('Twilio error status=', twilioResponse.status)
      throw new Error('Verification failed')
    }

    console.log(`Verification status: ${twilioData.status}`)

    if (twilioData.status !== 'approved') {
      return new Response(
        JSON.stringify({
          success: false,
          status: twilioData.status,
          error: 'Invalid verification code'
        }),
        {
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          status: 400,
        }
      )
    }

    // Update database with verified status (only if called with a user JWT).
    if (!authResult.auth.isServiceRole && authResult.auth.userId) {
      const authHeader = req.headers.get('Authorization')!
      const token = authHeader.replace('Bearer ', '')
      const { data: { user } } = await supabase.auth.getUser(token)

      if (user) {
        const { error: rpcError } = await supabase.rpc('confirm_phone_verification', {
          p_phone_number: formattedPhone
        })
        if (rpcError) {
          console.error('RPC confirm_phone_verification failed:', rpcError.message)
        } else {
          console.log(`Phone verified for user: ${user.id}`)
        }
      }
    }

    return new Response(
      JSON.stringify({
        success: true,
        status: 'approved',
        message: 'Phone number verified successfully'
      }),
      {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 200,
      }
    )

  } catch (error) {
    const message = error instanceof Error ? error.message : 'Unknown error'
    console.error('verify-code error:', message)
    const isClientError = message === 'Verification failed' || message.includes('Invalid')
    return new Response(
      JSON.stringify({
        success: false,
        error: isClientError ? message : 'Verification failed'
      }),
      {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: isClientError ? 400 : 500,
      }
    )
  }
})
