// =====================================================
// VERIFY SMS CODE
// Supabase Edge Function + Twilio Verify
// =====================================================
// This edge function verifies the code entered by the user
// 
// Deploy with: supabase functions deploy verify-code
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
    const { phone_number, code } = await req.json()

    if (!phone_number || !code) {
      throw new Error('Phone number and code are required')
    }

    // Format phone number (ensure it starts with +1 for US)
    let formattedPhone = phone_number.replace(/\D/g, '') // Remove non-digits
    if (formattedPhone.length === 10) {
      formattedPhone = '+1' + formattedPhone // Add US country code
    } else if (!formattedPhone.startsWith('+')) {
      formattedPhone = '+' + formattedPhone
    }

    console.log(`🔐 Verifying code for: ${formattedPhone}`)

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
      console.error('Twilio error:', twilioData)
      throw new Error(twilioData.message || 'Verification failed')
    }

    console.log(`📱 Verification status: ${twilioData.status}`)

    // Check if verification was successful
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

    // Update database with verified status
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const supabase = createClient(supabaseUrl, supabaseKey)

    // Get user from auth header
    const authHeader = req.headers.get('Authorization')
    if (authHeader) {
      const token = authHeader.replace('Bearer ', '')
      const { data: { user } } = await supabase.auth.getUser(token)
      
      if (user) {
        // Mark phone as verified in database
        await supabase.rpc('confirm_phone_verification', {
          p_phone_number: formattedPhone
        })
        
        console.log(`✅ Phone verified for user: ${user.id}`)
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
