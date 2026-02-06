// =====================================================
// SEND SMS VERIFICATION CODE
// Supabase Edge Function + Twilio Verify
// =====================================================
// This edge function sends a verification code via Twilio Verify
// 
// SETUP REQUIRED:
// 1. Create Twilio account at https://twilio.com
// 2. Create a Verify Service in Twilio Console
// 3. Add these secrets to Supabase:
//    - TWILIO_ACCOUNT_SID
//    - TWILIO_AUTH_TOKEN
//    - TWILIO_VERIFY_SERVICE_SID
//
// Deploy with: supabase functions deploy send-verification
// =====================================================

import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    // Get Twilio credentials from environment
    const twilioAccountSid = Deno.env.get('TWILIO_ACCOUNT_SID')
    const twilioAuthToken = Deno.env.get('TWILIO_AUTH_TOKEN')
    const twilioVerifyServiceSid = Deno.env.get('TWILIO_VERIFY_SERVICE_SID')

    if (!twilioAccountSid || !twilioAuthToken || !twilioVerifyServiceSid) {
      throw new Error('Twilio credentials not configured')
    }

    // Parse request
    const { phone_number } = await req.json()

    if (!phone_number) {
      throw new Error('Phone number is required')
    }

    // Format phone number (ensure it starts with +1 for US)
    let formattedPhone = phone_number.replace(/\D/g, '') // Remove non-digits
    if (formattedPhone.length === 10) {
      formattedPhone = '+1' + formattedPhone // Add US country code
    } else if (!formattedPhone.startsWith('+')) {
      formattedPhone = '+' + formattedPhone
    }

    console.log(`📱 Sending verification to: ${formattedPhone}`)

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

    console.log(`✅ Verification sent successfully. Status: ${twilioData.status}`)

    // Log verification attempt in database
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const supabase = createClient(supabaseUrl, supabaseKey)

    // Get user from auth header
    const authHeader = req.headers.get('Authorization')
    if (authHeader) {
      const token = authHeader.replace('Bearer ', '')
      const { data: { user } } = await supabase.auth.getUser(token)
      
      if (user) {
        await supabase.rpc('start_phone_verification', {
          p_phone_number: formattedPhone
        })
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
    return new Response(
      JSON.stringify({
        success: false,
        error: error.message
      }),
      {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 400,
      }
    )
  }
})
