// Supabase Edge Function: Notify contacts when a new user joins Fit33
// Deploy with: supabase functions deploy notify-contacts-user-joined
//
// Called after a new user completes onboarding (phone verified + contacts synced + account created).
// Finds all existing Fit33 users who have the new user's email or phone in their synced contacts,
// then queues push notifications: "Wayne joined Fit33! Send them a friend request!"

import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

    const authHeader = req.headers.get('Authorization')
    if (!authHeader) {
      return new Response(JSON.stringify({ error: 'Missing authorization' }), {
        status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      })
    }
    const token = authHeader.replace('Bearer ', '')
    const supabase = createClient(supabaseUrl, supabaseServiceKey)
    if (token !== supabaseServiceKey) {
      const { data: { user }, error: authError } = await supabase.auth.getUser(token)
      if (authError || !user) {
        return new Response(JSON.stringify({ error: 'Unauthorized' }), {
          status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' }
        })
      }
    }

    const { new_user_id } = await req.json()

    if (!new_user_id) {
      return new Response(JSON.stringify({ error: 'new_user_id is required' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      })
    }

    // Step 1: Fetch the new user's profile info (name, email, phone, username)
    const { data: newUser, error: userError } = await supabase
      .from('user_profiles')
      .select('id, name, email, phone_number, username')
      .eq('id', new_user_id)
      .single()

    if (userError || !newUser) {
      console.error('Error fetching new user profile:', userError)
      return new Response(JSON.stringify({ 
        error: 'Could not find user profile',
        details: userError?.message 
      }), {
        status: 404,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      })
    }

    console.log(`📬 Processing join notifications for: ${newUser.name || newUser.username || 'Unknown'} (${new_user_id})`)

    // Build display name for the notification
    const displayName = newUser.name || newUser.username || 'Someone'

    // Step 2: Find existing users who have this new user's email or phone in their synced contacts
    // The user_synced_contacts table stores contact_email for each user_id
    const matchConditions: string[] = []
    const matchValues: string[] = []

    if (newUser.email) {
      matchConditions.push('contact_email')
      matchValues.push(newUser.email.toLowerCase())
    }

    if (newUser.phone_number) {
      // Normalize phone: just last 10 digits for matching
      const phoneDigits = newUser.phone_number.replace(/\D/g, '')
      const normalizedPhone = phoneDigits.length >= 10 ? phoneDigits.slice(-10) : phoneDigits
      matchConditions.push('contact_phone')
      matchValues.push(normalizedPhone)
    }

    if (matchConditions.length === 0) {
      console.log('⚠️ New user has no email or phone - cannot match contacts')
      return new Response(JSON.stringify({ 
        message: 'No email or phone to match against contacts',
        notifications_queued: 0 
      }), {
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      })
    }

    // Query for users who have this email in their synced contacts
    let usersToNotify: Set<string> = new Set()

    if (newUser.email) {
      const { data: emailMatches, error: emailError } = await supabase
        .from('user_synced_contacts')
        .select('user_id')
        .eq('contact_email', newUser.email.toLowerCase())
        .neq('user_id', new_user_id) // Don't notify yourself

      if (!emailError && emailMatches) {
        for (const match of emailMatches) {
          usersToNotify.add(match.user_id)
        }
        console.log(`📧 Found ${emailMatches.length} users with email match`)
      }
    }

    // Also check phone number matches
    if (newUser.phone_number) {
      const phoneDigits = newUser.phone_number.replace(/\D/g, '')
      const normalizedPhone = phoneDigits.length >= 10 ? phoneDigits.slice(-10) : phoneDigits
      
      if (normalizedPhone.length >= 10) {
        const { data: phoneMatches, error: phoneError } = await supabase
          .from('user_synced_contacts')
          .select('user_id')
          .eq('contact_phone', normalizedPhone)
          .neq('user_id', new_user_id)

        if (!phoneError && phoneMatches) {
          for (const match of phoneMatches) {
            usersToNotify.add(match.user_id)
          }
          console.log(`📱 Found ${phoneMatches.length} users with phone match`)
        }
      }
    }

    if (usersToNotify.size === 0) {
      console.log('📭 No existing users have this new user in their contacts')
      return new Response(JSON.stringify({ 
        message: 'No contacts to notify',
        notifications_queued: 0 
      }), {
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      })
    }

    console.log(`🔔 Found ${usersToNotify.size} potential contacts to notify`)

    // Step 2.5: Exclude users who already received a friend request from this new user
    // If the new user sent them a friend request during onboarding, they don't need a "contact joined" notification
    const { data: friendRequests, error: frError } = await supabase
      .from('friendships')
      .select('addressee_id')
      .eq('requester_id', new_user_id)
      .eq('status', 'pending')

    if (!frError && friendRequests && friendRequests.length > 0) {
      const requestRecipients = new Set(friendRequests.map(fr => fr.addressee_id))
      console.log(`📤 New user sent ${requestRecipients.size} friend requests - excluding them from contact notifications`)
      
      // Remove users who received friend requests
      for (const recipientId of requestRecipients) {
        usersToNotify.delete(recipientId)
      }
      
      console.log(`📬 After excluding friend request recipients: ${usersToNotify.size} users will get contact joined notification`)
    }

    if (usersToNotify.size === 0) {
      console.log('📭 No users to notify (all received friend requests)')
      return new Response(JSON.stringify({ 
        message: 'All contacts received friend requests instead',
        notifications_queued: 0 
      }), {
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      })
    }

    console.log(`🔔 Queuing push notifications for ${usersToNotify.size} users`)

    // Step 3: Queue push notifications for each user
    const notifications = Array.from(usersToNotify).map(userId => ({
      recipient_user_id: userId,
      notification_type: 'contact_joined',
      title: `${displayName} joined Fit33!`,
      body: 'Send them a friend request!',
      data: {
        type: 'contact_joined',
        new_user_id: new_user_id,
        new_user_name: displayName
      },
      status: 'pending',
      created_at: new Date().toISOString()
    }))

    const { data: insertedNotifs, error: insertError } = await supabase
      .from('push_notification_queue')
      .insert(notifications)
      .select('id')

    if (insertError) {
      console.error('Error inserting notifications:', insertError)
      return new Response(JSON.stringify({ 
        error: 'Failed to queue notifications',
        details: insertError.message 
      }), {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      })
    }

    const queuedCount = insertedNotifs?.length || 0
    console.log(`✅ Queued ${queuedCount} push notifications`)

    // Step 4: Also create contact_joined_notifications entries for in-app display
    const contactNotifications = Array.from(usersToNotify).map(userId => ({
      notified_user_id: userId,
      new_user_id: new_user_id,
      sent: true, // Mark as sent since we're sending push notification now
      created_at: new Date().toISOString()
    }))

    try {
      await supabase
        .from('contact_joined_notifications')
        .insert(contactNotifications)
      console.log(`📝 Created ${contactNotifications.length} contact_joined_notification records`)
    } catch (notifError) {
      // Non-fatal - push notifications are already queued
      console.warn('Warning: Could not create contact_joined_notification records:', notifError)
    }

    // Step 5: Trigger the send-push-notification function to process the queue immediately
    try {
      const sendUrl = `${supabaseUrl}/functions/v1/send-push-notification`
      await fetch(sendUrl, {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${supabaseServiceKey}`,
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({ batch: true })
      })
      console.log('📤 Triggered send-push-notification to process queue')
    } catch (triggerError) {
      // Non-fatal - the batch processor will pick them up on its next run
      console.warn('Warning: Could not trigger immediate send:', triggerError)
    }

    return new Response(JSON.stringify({ 
      message: `Notifications queued for ${queuedCount} contacts`,
      notifications_queued: queuedCount,
      new_user_name: displayName
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
