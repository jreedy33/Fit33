// Supabase Edge Function: Content Moderation via OpenAI Moderation API
// Deploy with: supabase functions deploy moderate-content
// Set secret: supabase secrets set OPENAI_API_KEY=sk-...
//
// Supports two modes:
//   1. Pre-check (Layer 1): iOS app calls before sending. Returns { flagged, categories }.
//      If flagged, the message is never stored.
//   2. Webhook (Layer 2): DB webhook calls after INSERT. If flagged, sets is_hidden = true.

import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

const OPENAI_API_KEY = Deno.env.get('OPENAI_API_KEY') || ''

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

interface ModerationResult {
  flagged: boolean
  categories: Record<string, boolean>
  category_scores: Record<string, number>
}

async function moderateText(content: string): Promise<ModerationResult & { error?: string }> {
  if (!OPENAI_API_KEY) {
    console.error('OPENAI_API_KEY is not set')
    return { flagged: false, categories: {}, category_scores: {}, error: 'OPENAI_API_KEY not configured' }
  }

  const response = await fetch('https://api.openai.com/v1/moderations', {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${OPENAI_API_KEY}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      input: content,
    }),
  })

  if (!response.ok) {
    const errorText = await response.text()
    console.error(`OpenAI Moderation API error ${response.status}: ${errorText}`)
    return { flagged: false, categories: {}, category_scores: {}, error: `OpenAI API ${response.status}: ${errorText}` }
  }

  const data = await response.json()
  const result = data.results?.[0]

  if (!result) {
    return { flagged: false, categories: {}, category_scores: {}, error: 'No results from OpenAI' }
  }

  return {
    flagged: result.flagged,
    categories: result.categories || {},
    category_scores: result.category_scores || {},
  }
}

function getFlaggedCategories(categories: Record<string, boolean>): string[] {
  return Object.entries(categories)
    .filter(([_, flagged]) => flagged)
    .map(([category]) => category)
}

// Map table names to their content and ID columns
const TABLE_CONFIG: Record<string, { contentColumn: string; idColumn: string }> = {
  'private_challenge_chat': { contentColumn: 'content', idColumn: 'id' },
  'challenge_reactions': { contentColumn: 'content', idColumn: 'id' },
  'shared_workouts': { contentColumn: 'personal_message', idColumn: 'id' },
  'group_challenges': { contentColumn: 'title', idColumn: 'id' },
  'private_challenges': { contentColumn: 'title', idColumn: 'id' },
  'community_challenges': { contentColumn: 'title', idColumn: 'id' },
  'friend_activity_feed': { contentColumn: 'content', idColumn: 'id' },
  'user_profiles': { contentColumn: 'name', idColumn: 'id' },
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const supabase = createClient(supabaseUrl, supabaseServiceKey)

    const body = await req.json()

    // MODE 1: Pre-check (called from iOS before sending)
    // Expects: { mode: "precheck", content: "message text", user_id: "uuid" }
    if (body.mode === 'precheck') {
      if (!body.content || typeof body.content !== 'string') {
        return new Response(JSON.stringify({ error: 'Missing content' }), {
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        })
      }

      const result = await moderateText(body.content)
      const flaggedCategories = getFlaggedCategories(result.categories)

      if (result.flagged) {
        console.log(JSON.stringify({
          event: 'precheck_flagged',
          user_id: body.user_id || 'unknown',
          categories: flaggedCategories,
          content_length: body.content.length,
        }))

        // Log the blocked attempt
        await supabase.from('content_moderation_log').insert({
          user_id: body.user_id || null,
          table_name: body.source || 'precheck',
          content_snippet: body.content.substring(0, 500),
          flagged_categories: flaggedCategories,
          category_scores: result.category_scores,
          action_taken: 'blocked',
        })
      }

      return new Response(JSON.stringify({
        flagged: result.flagged,
        categories: flaggedCategories,
        ...(result.error ? { debug_error: result.error } : {}),
      }), {
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // MODE 2: Webhook (called by DB webhook after INSERT)
    // Expects: { type: "INSERT", table: "private_challenge_chat", record: { ... } }
    if (body.type === 'INSERT' && body.table && body.record) {
      const tableName = body.table as string
      const record = body.record as Record<string, unknown>
      const config = TABLE_CONFIG[tableName]

      if (!config) {
        console.log(JSON.stringify({ event: 'webhook_unknown_table', table: tableName }))
        return new Response(JSON.stringify({ message: 'Unknown table' }), {
          status: 200,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        })
      }

      const content = record[config.contentColumn] as string
      const recordId = record[config.idColumn] as string
      const userId = (record.sender_id || record.user_id || record.created_by) as string

      if (!content || content.trim().length === 0) {
        return new Response(JSON.stringify({ message: 'No content to moderate' }), {
          status: 200,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        })
      }

      const result = await moderateText(content)

      if (result.flagged) {
        const flaggedCategories = getFlaggedCategories(result.categories)
        console.log(JSON.stringify({
          event: 'webhook_flagged',
          table: tableName,
          record_id: recordId,
          user_id: userId,
          categories: flaggedCategories,
        }))

        // Hide the content
        await supabase
          .from(tableName)
          .update({ is_hidden: true })
          .eq(config.idColumn, recordId)

        // Log the moderation action
        await supabase.from('content_moderation_log').insert({
          user_id: userId || null,
          table_name: tableName,
          record_id: recordId,
          content_snippet: content.substring(0, 500),
          flagged_categories: flaggedCategories,
          category_scores: result.category_scores,
          action_taken: 'hidden',
        })

        return new Response(JSON.stringify({ flagged: true, action: 'hidden' }), {
          status: 200,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        })
      }

      return new Response(JSON.stringify({ flagged: false }), {
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    return new Response(JSON.stringify({ error: 'Invalid request. Use mode=precheck or webhook payload.' }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })

  } catch (error) {
    console.error('Edge function error:', error)
    return new Response(JSON.stringify({ error: String(error) }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
})
