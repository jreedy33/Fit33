import { NextRequest, NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'
import Anthropic from '@anthropic-ai/sdk'
import { verifyAdmin } from '@/lib/verify-admin'
import { parseJson, devLogAnalysisSchema } from '@/lib/validation'

export async function POST(req: NextRequest) {
  try {
    const adminAuth = await verifyAdmin(req)
    if (!adminAuth.valid) {
      return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
    }

    const parsed = await parseJson(req, devLogAnalysisSchema)
    if (!parsed.ok) return parsed.response
    const { session_id } = parsed.data

    const admin = createClient(
      process.env.NEXT_PUBLIC_SUPABASE_URL!,
      process.env.SUPABASE_SERVICE_ROLE_KEY!,
    )

    const { data: batches, error } = await admin.from('dev_session_logs')
      .select('*')
      .eq('session_id', session_id)
      .order('batch_index', { ascending: true })

    if (error || !batches?.length) {
      return NextResponse.json({ error: 'No logs found for session' }, { status: 404 })
    }

    const allEntries = batches.flatMap(b => {
      try { return typeof b.entries === 'string' ? JSON.parse(b.entries) : b.entries }
      catch { return [] }
    })

    const errors = allEntries.filter((e: { type: string }) => e.type === 'error')
    const slowOps = allEntries.filter((e: { type: string; duration_ms?: number }) =>
      e.type === 'perf' && e.duration_ms && e.duration_ms > 500
    )
    const screens = allEntries.filter((e: { type: string }) => e.type === 'screen')

    const sessionSummary = {
      total_entries: allEntries.length,
      duration_seconds: allEntries.length > 1
        ? Math.round(((allEntries[allEntries.length - 1] as { ts: number }).ts - (allEntries[0] as { ts: number }).ts) / 1000)
        : 0,
      screens_visited: screens.length,
      unique_screens: [...new Set(screens.map((e: { detail: string }) => e.detail))],
      error_count: errors.length,
      slow_operations: slowOps.length,
      device: batches[0]?.device_info,
    }

    const anthropic = new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY })

    const response = await anthropic.messages.create({
      model: 'claude-sonnet-4-20250514',
      max_tokens: 4096,
      system: `You are a senior iOS engineer reviewing a real user session log from the Fit33 fitness app (SwiftUI + Supabase).

Analyze the session data and identify:
1. Bugs: errors, crashes, unexpected behavior
2. UX friction: slow screens, confusing navigation patterns, dead ends
3. Performance issues: slow API calls, high memory usage, laggy transitions

For each issue, provide:
- title: concise description
- description: what happened and why it matters
- file_path: the specific Swift file to fix (e.g., "Fit33/DashboardView.swift")
- code_diff: the exact code change as a unified diff (--- old / +++ new format)
- severity: "critical", "high", "medium", or "low"

Return ONLY valid JSON:
{
  "suggestions": [
    { "title": "...", "description": "...", "file_path": "...", "code_diff": "...", "severity": "..." }
  ],
  "session_health": "good|warning|critical",
  "summary": "1-2 sentence overall assessment"
}

If the session looks clean with no issues, return an empty suggestions array with session_health "good".`,
      messages: [{
        role: 'user',
        content: `Session Summary:\n${JSON.stringify(sessionSummary, null, 2)}\n\nErrors:\n${JSON.stringify(errors.slice(0, 50), null, 2)}\n\nSlow Operations:\n${JSON.stringify(slowOps.slice(0, 30), null, 2)}\n\nFull Session Timeline (last 200 entries):\n${JSON.stringify(allEntries.slice(-200), null, 2)}`,
      }],
    })

    const content = response.content?.[0]
    const text = content && 'text' in content ? content.text : ''
    const jsonMatch = text.match(/\{[\s\S]*\}/)
    if (!jsonMatch) {
      return NextResponse.json({ error: 'Could not parse Claude response' }, { status: 500 })
    }

    const analysis = JSON.parse(jsonMatch[0])

    if (analysis.suggestions?.length > 0) {
      const rows = analysis.suggestions.map((s: { title: string; description: string; file_path: string; code_diff: string; severity: string }) => ({
        session_id,
        user_id: batches[0].user_id,
        title: s.title,
        description: s.description,
        file_path: s.file_path || null,
        code_diff: s.code_diff || null,
        severity: s.severity || 'medium',
        status: 'new',
        analysis_model: 'claude-sonnet-4-20250514',
      }))

      await admin.from('dev_log_suggestions').insert(rows)
    }

    return NextResponse.json({
      session_health: analysis.session_health,
      summary: analysis.summary,
      suggestions_count: analysis.suggestions?.length || 0,
    })
  } catch (err) {
    console.error('Dev log analysis error:', err)
    return NextResponse.json(
      { error: err instanceof Error ? err.message : 'Analysis failed' },
      { status: 500 },
    )
  }
}
