import { NextRequest } from 'next/server'
import { createClient } from '@supabase/supabase-js'
import { createAdminClient } from '@/lib/supabase-admin'
import { isAdminEmail } from '@/lib/auth'
import { getAccessToken } from '@/lib/auth-cookies'
import Anthropic from '@anthropic-ai/sdk'

const SYSTEM_PROMPT = `You are Fit33's AI Product Analyst. You help the admin team understand user behavior, identify trends, and make data-driven decisions for the Fit33 iOS fitness app.

About Fit33:
- Premium iOS fitness app with workout tracking, exercise library (6500+ exercises with video), meal planning, social features (friends, challenges), and gamification (XP, levels, streaks)
- Backend: Supabase (Postgres), Edge Functions, Core Data for offline
- Key tables: user_profiles, workout_history, exercise_usage_logs, onboarding_analytics, friendships, shared_workouts, group_challenges, meal_logs, step_tracking

When the admin asks a question, you will receive live platform data as context. Use this data to provide specific, actionable insights. Always cite actual numbers from the data. If the data doesn't cover what they're asking, say so clearly and suggest what data would be needed.

Format your responses clearly with headers, bullet points, and bold for key metrics. Be concise but thorough. Think like a product manager who owns growth and engagement metrics.`

async function verifyAdmin(req: NextRequest): Promise<{ valid: boolean; userId?: string; email?: string }> {
  const token = getAccessToken(req)
  if (!token || token.length < 10) return { valid: false }

  const supabase = createClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
  )

  const { data: { user }, error } = await supabase.auth.getUser(token)
  if (error || !user?.email) return { valid: false }
  if (!isAdminEmail(user.email)) return { valid: false }

  return { valid: true, userId: user.id, email: user.email }
}

async function fetchLiveDataContext(): Promise<string> {
  const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL!
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY!

  try {
    const res = await fetch(`${supabaseUrl}/functions/v1/generate-ai-insights`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${serviceKey}`,
      },
      body: JSON.stringify({ action: 'get_data_context' }),
    })

    if (res.ok) {
      const data = await res.json()
      return `\n\n--- LIVE PLATFORM DATA (${new Date().toISOString()}) ---\n${JSON.stringify(data, null, 2)}\n--- END DATA ---`
    }
  } catch (e) {
    console.error('[ai-chat] Failed to fetch live data context:', e)
  }

  return '\n\n(Live data context unavailable - answering based on conversation context only)'
}

export async function POST(req: NextRequest) {
  const adminAuth = await verifyAdmin(req)
  if (!adminAuth.valid) {
    return new Response(JSON.stringify({ error: 'Unauthorized' }), {
      status: 401,
      headers: { 'Content-Type': 'application/json' },
    })
  }

  const apiKey = process.env.ANTHROPIC_API_KEY
  if (!apiKey) {
    return new Response(JSON.stringify({ error: 'ANTHROPIC_API_KEY not configured' }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    })
  }

  try {
    const body = await req.json()
    const { messages, conversationId, fetchData } = body as {
      messages: Array<{ role: 'user' | 'assistant'; content: string }>
      conversationId?: string
      fetchData?: boolean
    }

    if (!messages || !Array.isArray(messages) || messages.length === 0) {
      return new Response(JSON.stringify({ error: 'Messages array required' }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' },
      })
    }

    let dataContext = ''
    if (fetchData !== false) {
      dataContext = await fetchLiveDataContext()
    }

    const systemWithData = SYSTEM_PROMPT + dataContext

    const anthropic = new Anthropic({ apiKey })

    const stream = anthropic.messages.stream({
      model: 'claude-sonnet-4-20250514',
      max_tokens: 4096,
      system: systemWithData,
      messages: messages.map(m => ({ role: m.role, content: m.content })),
    })

    const encoder = new TextEncoder()
    let fullResponse = ''

    const readable = new ReadableStream({
      async start(controller) {
        try {
          for await (const event of stream) {
            if (event.type === 'content_block_delta' && 'delta' in event && 'text' in (event.delta as Record<string, unknown>)) {
              const text = (event.delta as { text: string }).text
              fullResponse += text
              controller.enqueue(encoder.encode(`data: ${JSON.stringify({ text })}\n\n`))
            }
          }

          controller.enqueue(encoder.encode(`data: ${JSON.stringify({ done: true })}\n\n`))

          // Auto-save conversation after streaming completes
          if (conversationId || messages.length >= 1) {
            try {
              const admin = createAdminClient()
              const allMessages = [...messages, { role: 'assistant', content: fullResponse }]
              const title = messages[0]?.content?.substring(0, 80) || 'New Conversation'

              if (conversationId) {
                await admin.from('ai_chat_history')
                  .update({
                    messages: allMessages,
                    title,
                    updated_at: new Date().toISOString(),
                  })
                  .eq('id', conversationId)
              } else {
                const { data } = await admin.from('ai_chat_history')
                  .insert({
                    admin_user_id: adminAuth.userId!,
                    title,
                    messages: allMessages,
                  })
                  .select('id')
                  .single()

                if (data) {
                  controller.enqueue(
                    encoder.encode(`data: ${JSON.stringify({ conversationId: data.id })}\n\n`)
                  )
                }
              }
            } catch (saveErr) {
              console.error('[ai-chat] Failed to save conversation:', saveErr)
            }
          }

          controller.close()
        } catch (streamErr) {
          console.error('[ai-chat] Stream error:', streamErr)
          controller.enqueue(
            encoder.encode(`data: ${JSON.stringify({ error: 'Stream interrupted' })}\n\n`)
          )
          controller.close()
        }
      },
    })

    return new Response(readable, {
      headers: {
        'Content-Type': 'text/event-stream',
        'Cache-Control': 'no-cache',
        'Connection': 'keep-alive',
      },
    })
  } catch (err) {
    console.error('[ai-chat] Error:', err)
    return new Response(
      JSON.stringify({ error: err instanceof Error ? err.message : 'Internal error' }),
      { status: 500, headers: { 'Content-Type': 'application/json' } },
    )
  }
}
