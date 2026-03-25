'use client'

import { useEffect, useState, useCallback } from 'react'
import AdminShell from '@/components/AdminShell'

type DevUser = { id: string; user_id: string; enabled: boolean; enabled_by: string; user_profiles: { name: string; email: string; username: string } | null }
type Session = { session_id: string; user_id: string; device_info: Record<string, string>; started_at: string; batch_count: number }
type LogEntry = { ts: number; type: string; detail: string; screen?: string; duration_ms?: number; error?: string; api_endpoint?: string; api_status?: number; memory_available_mb?: number }
type Suggestion = { id: string; session_id: string; title: string; description: string; file_path: string; code_diff: string; severity: string; status: string; pr_url: string | null }

async function adminAction(action: string, params: Record<string, unknown> = {}) {
  const res = await fetch('/api/admin', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ action, ...params }),
  })
  return res.json()
}

const typeColors: Record<string, string> = {
  screen: '#22c55e', tap: '#3b82f6', api: '#a855f7', error: '#ef4444',
  state: '#6b7280', perf: '#f59e0b', log: '#6b7280', warning: '#f59e0b',
  system: '#06b6d4',
}

export default function DevLogsPage() {
  const [devUsers, setDevUsers] = useState<DevUser[]>([])
  const [sessions, setSessions] = useState<Session[]>([])
  const [selectedSession, setSelectedSession] = useState<string | null>(null)
  const [entries, setEntries] = useState<LogEntry[]>([])
  const [suggestions, setSuggestions] = useState<Suggestion[]>([])
  const [filter, setFilter] = useState<string>('all')
  const [loading, setLoading] = useState(true)
  const [analyzing, setAnalyzing] = useState(false)
  const [searchUserId, setSearchUserId] = useState('')
  const [enableUserId, setEnableUserId] = useState('')
  const [autoRefresh, setAutoRefresh] = useState(false)
  const [batchingPR, setBatchingPR] = useState(false)
  const [activeTab, setActiveTab] = useState<'sessions' | 'unified'>('sessions')
  const [unifiedEntries, setUnifiedEntries] = useState<(LogEntry & { user_id?: string; session_id?: string })[]>([])
  const [analyzingTrends, setAnalyzingTrends] = useState(false)
  const [downloaded, setDownloaded] = useState(false)

  // Multi-user comparison
  const [checkedUserIds, setCheckedUserIds] = useState<Set<string>>(new Set())
  const [comparingUsers, setComparingUsers] = useState(false)
  const [comparisonDownloaded, setComparisonDownloaded] = useState(false)

  const loadDevUsers = useCallback(async () => {
    const data = await adminAction('get_dev_logging_users')
    setDevUsers(data.users || [])
  }, [])

  const loadSessions = useCallback(async () => {
    const data = await adminAction('get_dev_sessions')
    setSessions(data.sessions || [])
    setLoading(false)
  }, [])

  useEffect(() => { loadDevUsers(); loadSessions() }, [loadDevUsers, loadSessions])

  useEffect(() => {
    if (!autoRefresh || !selectedSession) return
    const interval = setInterval(async () => {
      const data = await adminAction('get_dev_session_entries', { session_id: selectedSession })
      const allEntries = (data.batches || []).flatMap((b: { entries: string | LogEntry[] }) => {
        try { return typeof b.entries === 'string' ? JSON.parse(b.entries) : b.entries }
        catch { return [] }
      })
      setEntries(allEntries)
    }, 3000)
    return () => clearInterval(interval)
  }, [autoRefresh, selectedSession])

  async function toggleLogging(userId: string, enabled: boolean) {
    await adminAction('toggle_dev_logging', { user_id: userId, enabled })
    loadDevUsers()
  }

  async function enableForUser() {
    if (!enableUserId.trim()) return
    await adminAction('toggle_dev_logging', { user_id: enableUserId.trim(), enabled: true })
    setEnableUserId('')
    loadDevUsers()
  }

  async function openSession(sessionId: string) {
    setSelectedSession(sessionId)
    setDownloaded(false)
    const data = await adminAction('get_dev_session_entries', { session_id: sessionId })
    const allEntries = (data.batches || []).flatMap((b: { entries: string | LogEntry[] }) => {
      try { return typeof b.entries === 'string' ? JSON.parse(b.entries) : b.entries }
      catch { return [] }
    })
    setEntries(allEntries)

    const sugData = await adminAction('get_dev_suggestions', { session_id: sessionId })
    setSuggestions(sugData.suggestions || [])
  }

  async function analyzeSession() {
    if (!selectedSession) return
    setAnalyzing(true)
    try {
      const res = await fetch('/api/dev-log-analysis', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ session_id: selectedSession }),
      })
      const data = await res.json()
      if (data.error) alert(`Analysis failed: ${data.error}`)
      else {
        alert(`Analysis complete: ${data.suggestions_count} suggestions (${data.session_health})`)
        const sugData = await adminAction('get_dev_suggestions', { session_id: selectedSession })
        setSuggestions(sugData.suggestions || [])
      }
    } catch (e) { alert(`Error: ${e}`) }
    setAnalyzing(false)
  }

  async function createPR(suggestion: Suggestion) {
    setSuggestions(prev => prev.map(s => s.id === suggestion.id ? { ...s, status: 'creating_pr' } : s))
    try {
      const res = await fetch('/api/github-pr', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          suggestion_id: suggestion.id,
          title: suggestion.title,
          description: suggestion.description,
          file_path: suggestion.file_path,
          code_diff: suggestion.code_diff,
          session_id: suggestion.session_id,
        }),
      })
      const data = await res.json()
      if (data.error) {
        alert(`PR failed: ${data.error}`)
        setSuggestions(prev => prev.map(s => s.id === suggestion.id ? { ...s, status: 'new' } : s))
        return
      }

      await adminAction('update_suggestion_status', {
        suggestion_id: suggestion.id,
        status: 'pr_created',
        pr_url: data.pr_url,
        pr_branch: data.branch,
      })
      setSuggestions(prev => prev.map(s => s.id === suggestion.id ? { ...s, status: 'pr_created', pr_url: data.pr_url } : s))
    } catch (e) {
      alert(`Error: ${e}`)
      setSuggestions(prev => prev.map(s => s.id === suggestion.id ? { ...s, status: 'new' } : s))
    }
  }

  async function createBatchPR() {
    const newSuggestions = suggestions.filter(s => s.status === 'new' && s.file_path && s.code_diff)
    if (newSuggestions.length === 0) { alert('No actionable suggestions to create PR for'); return }

    setBatchingPR(true)
    try {
      const res = await fetch('/api/github-pr', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          batch: true,
          session_id: selectedSession,
          suggestions: newSuggestions.map(s => ({
            suggestion_id: s.id,
            title: s.title,
            description: s.description,
            file_path: s.file_path,
            code_diff: s.code_diff,
          })),
        }),
      })
      const data = await res.json()
      if (data.error) { alert(`Batch PR failed: ${data.error}`); setBatchingPR(false); return }

      for (const s of newSuggestions) {
        await adminAction('update_suggestion_status', {
          suggestion_id: s.id,
          status: 'pr_created',
          pr_url: data.pr_url,
          pr_branch: data.branch,
        })
      }

      alert(`Draft PR created with ${data.applied} of ${newSuggestions.length} fixes: ${data.pr_url}`)
      setSuggestions(prev => prev.map(s =>
        newSuggestions.some(ns => ns.id === s.id) ? { ...s, status: 'pr_created', pr_url: data.pr_url } : s
      ))
    } catch (e) { alert(`Error: ${e}`) }
    setBatchingPR(false)
  }

  function downloadSuggestionsAsMD() {
    const sessionInfo = sessions.find(s => s.session_id === selectedSession)
    const sessionUser = sessionInfo ? devUsers.find(u => u.user_id === sessionInfo.user_id) : null
    const di = sessionInfo?.device_info ? (typeof sessionInfo.device_info === 'string' ? (() => { try { return JSON.parse(sessionInfo.device_info as unknown as string) } catch { return sessionInfo.device_info } })() : sessionInfo.device_info) : {}
    const lines = [
      '# Dev Session Log — Claude Analysis Report',
      '',
      `**Session:** ${selectedSession}`,
      `**Date:** ${new Date().toISOString().split('T')[0]}`,
      '',
      '## User Profile',
      '',
      `- **Name:** ${sessionUser?.user_profiles?.name || 'Unknown'}`,
      `- **Username:** ${sessionUser?.user_profiles?.username || 'Unknown'}`,
      `- **Email:** ${sessionUser?.user_profiles?.email || 'Unknown'}`,
      `- **User ID:** ${sessionInfo?.user_id || 'Unknown'}`,
      '',
      '## Device Details',
      '',
      `- **Model:** ${di.model || di.name || 'Unknown'}`,
      `- **iOS Version:** ${di.systemVersion || 'Unknown'}`,
      `- **App Version:** ${di.appVersion || 'Unknown'} (Build ${di.buildNumber || '?'})`,
      `- **Screen:** ${di.screenBounds || 'Unknown'} @${di.screenScale || '?'}x`,
      '',
      `**Total suggestions:** ${suggestions.length}`,
      '',
      '---',
      '',
      '## Instructions',
      '',
      'Drag this file into Cursor and ask: "Fix all the issues in this report."',
      'Each issue below includes the severity, description, suggested file, and code diff.',
      '',
      '---',
      '',
    ]

    for (let i = 0; i < suggestions.length; i++) {
      const s = suggestions[i]
      lines.push(`## ${i + 1}. ${s.title}`)
      lines.push('')
      lines.push(`**Severity:** ${s.severity}`)
      if (s.file_path) lines.push(`**Suggested file:** \`${s.file_path}\``)
      lines.push('')
      lines.push(s.description)
      lines.push('')
      if (s.code_diff) {
        lines.push('**Suggested fix:**')
        lines.push('')
        lines.push('```diff')
        lines.push(s.code_diff)
        lines.push('```')
        lines.push('')
      }

      // Find related log entries and show before/during/after context
      const keywords = [
        ...(s.title || '').toLowerCase().split(/\s+/).filter((w: string) => w.length > 4),
        ...(s.file_path || '').split('/').pop()?.replace('.swift', '').split(/(?=[A-Z])/).map((w: string) => w.toLowerCase()) || [],
      ]
      const relatedEntries = entries.filter(e => {
        const detail = (e.detail || '').toLowerCase()
        return e.type === 'error' && keywords.some((k: string) => detail.includes(k))
      })

      if (relatedEntries.length > 0) {
        lines.push('**Log context (before / during / after):**')
        lines.push('')
        lines.push('```')
        for (const re of relatedEntries.slice(0, 5)) {
          const reIdx = entries.indexOf(re)
          const contextStart = Math.max(0, reIdx - 3)
          const contextEnd = Math.min(entries.length, reIdx + 4)
          for (let ci = contextStart; ci < contextEnd; ci++) {
            const ce = entries[ci]
            const marker = ci === reIdx ? '>>>' : '   '
            const time = new Date(ce.ts).toLocaleTimeString()
            lines.push(`${marker} ${time} [${ce.type.toUpperCase()}] ${ce.screen ? `[${ce.screen}] ` : ''}${ce.detail}${ce.duration_ms ? ` (${ce.duration_ms}ms)` : ''}`)
          }
          lines.push('   ...')
        }
        lines.push('```')
        lines.push('')
      }

      lines.push('---')
      lines.push('')
    }

    // Full session error summary
    const errors = entries.filter(e => e.type === 'error')
    if (errors.length > 0) {
      lines.push('## All Errors from Session Log')
      lines.push('')
      for (const e of errors.slice(0, 50)) {
        lines.push(`- \`${new Date(e.ts).toLocaleTimeString()}\` ${e.screen ? `[${e.screen}]` : ''} ${e.detail}`)
      }
      lines.push('')
    }

    // Full session timeline summary
    lines.push('## Session Timeline Summary')
    lines.push('')
    lines.push(`- **Total log entries:** ${entries.length}`)
    lines.push(`- **Screens visited:** ${new Set(entries.filter(e => e.type === 'screen').map(e => e.detail)).size}`)
    lines.push(`- **Errors:** ${errors.length}`)
    lines.push(`- **Slow operations (>500ms):** ${entries.filter(e => e.duration_ms && e.duration_ms > 500).length}`)
    const duration = entries.length > 1 ? Math.round((entries[entries.length - 1].ts - entries[0].ts) / 1000) : 0
    lines.push(`- **Session duration:** ${duration}s`)
    lines.push('')

    const content = lines.join('\n')
    const blob = new Blob([content], { type: 'text/markdown' })
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url
    a.download = `dev-session-report-${(selectedSession || 'unknown').slice(0, 8)}-${new Date().toISOString().split('T')[0]}.md`
    document.body.appendChild(a)
    a.click()
    document.body.removeChild(a)
    URL.revokeObjectURL(url)
  }

  async function loadUnifiedFeed() {
    const data = await adminAction('get_dev_sessions')
    const allSessions = data.sessions || []
    const allEntries: (LogEntry & { user_id?: string; session_id?: string })[] = []
    for (const s of allSessions.slice(0, 20)) {
      const batchData = await adminAction('get_dev_session_entries', { session_id: s.session_id })
      const sessionEntries = (batchData.batches || []).flatMap((b: { entries: string | LogEntry[] }) => {
        try { return typeof b.entries === 'string' ? JSON.parse(b.entries) : b.entries }
        catch { return [] }
      })
      for (const e of sessionEntries) {
        allEntries.push({ ...e, user_id: s.user_id, session_id: s.session_id })
      }
    }
    allEntries.sort((a, b) => (b.ts || 0) - (a.ts || 0))
    setUnifiedEntries(allEntries.slice(0, 1000))
  }

  async function analyzeTrends() {
    setAnalyzingTrends(true)
    try {
      const errors = unifiedEntries.filter(e => e.type === 'error')
      const slowOps = unifiedEntries.filter(e => e.type === 'perf' && e.duration_ms && e.duration_ms > 500)
      const screens = unifiedEntries.filter(e => e.type === 'screen')
      const userCount = new Set(unifiedEntries.map(e => e.user_id)).size
      const sessionCount = new Set(unifiedEntries.map(e => e.session_id)).size

      const res = await fetch('/api/dev-log-analysis', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          session_id: `trend-analysis-${Date.now()}`,
          trend_mode: true,
          summary: {
            total_entries: unifiedEntries.length,
            users: userCount,
            sessions: sessionCount,
            errors: errors.length,
            slow_operations: slowOps.length,
            unique_screens: [...new Set(screens.map(e => e.detail))].length,
          },
          errors: errors.slice(0, 50),
          slow_ops: slowOps.slice(0, 30),
          recent_entries: unifiedEntries.slice(0, 200),
        }),
      })
      const data = await res.json()
      if (data.error) alert(`Trend analysis failed: ${data.error}`)
      else alert(`Trend analysis complete: ${data.suggestions_count} insights (${data.session_health})`)
    } catch (e) { alert(`Error: ${e}`) }
    setAnalyzingTrends(false)
  }

  function toggleUserCheck(userId: string) {
    setCheckedUserIds(prev => {
      const next = new Set(prev)
      if (next.has(userId)) next.delete(userId)
      else next.add(userId)
      return next
    })
    setComparisonDownloaded(false)
  }

  async function compareCheckedUsers() {
    if (checkedUserIds.size < 1) return
    setComparingUsers(true)

    try {
      const userSessionData: Array<{
        userId: string
        userName: string
        userEmail: string
        sessions: Array<{
          sessionId: string
          deviceInfo: Record<string, string>
          startedAt: string
          entries: LogEntry[]
        }>
      }> = []

      for (const userId of checkedUserIds) {
        const user = devUsers.find(u => u.user_id === userId)
        const userSessions = sessions.filter(s => s.user_id === userId)

        const sessionsWithEntries: Array<{
          sessionId: string
          deviceInfo: Record<string, string>
          startedAt: string
          entries: LogEntry[]
        }> = []

        for (const s of userSessions.slice(0, 5)) {
          const data = await adminAction('get_dev_session_entries', { session_id: s.session_id })
          const allEntries = (data.batches || []).flatMap((b: { entries: string | LogEntry[] }) => {
            try { return typeof b.entries === 'string' ? JSON.parse(b.entries) : b.entries }
            catch { return [] }
          })
          sessionsWithEntries.push({
            sessionId: s.session_id,
            deviceInfo: typeof s.device_info === 'string' ? (() => { try { return JSON.parse(s.device_info) } catch { return {} } })() : s.device_info || {},
            startedAt: s.started_at,
            entries: allEntries,
          })
        }

        userSessionData.push({
          userId,
          userName: user?.user_profiles?.name || user?.user_profiles?.username || userId.slice(0, 8),
          userEmail: user?.user_profiles?.email || '',
          sessions: sessionsWithEntries,
        })
      }

      const userSummaries = userSessionData.map(u => {
        const allEntries = u.sessions.flatMap(s => s.entries)
        const errors = allEntries.filter(e => e.type === 'error')
        const slowOps = allEntries.filter(e => e.duration_ms && e.duration_ms > 500)
        return {
          name: u.userName,
          email: u.userEmail,
          session_count: u.sessions.length,
          total_entries: allEntries.length,
          error_count: errors.length,
          slow_ops: slowOps.length,
          screens_visited: [...new Set(allEntries.filter(e => e.type === 'screen').map(e => e.detail))],
          errors: errors.slice(0, 20).map(e => ({ detail: e.detail, screen: e.screen, ts: e.ts })),
          slow_operations: slowOps.slice(0, 10).map(e => ({ detail: e.detail, duration_ms: e.duration_ms, screen: e.screen })),
          device_info: u.sessions[0]?.deviceInfo || {},
        }
      })

      const prompt = `You are analyzing dev session logs from the Fit33 iOS fitness app for ${userSummaries.length} users. Compare their experiences and identify issues.

For each user, here is their session summary:
${JSON.stringify(userSummaries, null, 2)}

Please provide:
1. **Shared Issues**: Errors or problems that appear across multiple users (these are likely app-level bugs, not user-specific)
2. **User-Specific Issues**: Unique problems for each user
3. **Comparison Trends**: Differences in app behavior between users (different screens, performance, error rates)
4. **Priority Recommendations**: Ranked list of fixes with estimated impact
5. **Device/Version Correlation**: Note if issues correlate with specific devices or app versions

Format your response as a structured analysis with clear sections. For shared issues, show which users are affected. For unique issues, clearly label each user.`

      const res = await fetch('/api/ai-chat', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ messages: [{ role: 'user', content: prompt }], fetchData: false }),
      })

      let analysisText = ''
      const reader = res.body?.getReader()
      const decoder = new TextDecoder()
      if (reader) {
        while (true) {
          const { done, value } = await reader.read()
          if (done) break
          const chunk = decoder.decode(value)
          for (const line of chunk.split('\n')) {
            if (line.startsWith('data: ')) {
              try {
                const parsed = JSON.parse(line.slice(6))
                if (parsed.text) analysisText += parsed.text
              } catch { /* skip */ }
            }
          }
        }
      }

      // Build .md report
      const lines: string[] = [
        '# Multi-User Comparison Analysis',
        '',
        `**Date:** ${new Date().toISOString().split('T')[0]}`,
        `**Users analyzed:** ${userSummaries.length}`,
        '',
        '---',
        '',
        '## Users Included',
        '',
      ]

      for (const u of userSummaries) {
        const di = u.device_info as Record<string, string>
        lines.push(`### ${u.name}`)
        lines.push(`- **Email:** ${u.email || '—'}`)
        lines.push(`- **Device:** ${di.model || di.name || '?'} · iOS ${di.systemVersion || '?'} · v${di.appVersion || '?'}`)
        lines.push(`- **Sessions:** ${u.session_count} · **Entries:** ${u.total_entries} · **Errors:** ${u.error_count} · **Slow ops:** ${u.slow_ops}`)
        lines.push('')
      }

      lines.push('---', '', '## Claude Analysis', '', analysisText, '', '---', '')

      // Per-user raw error data
      lines.push('## Raw Error Data by User', '')

      const allErrorDetails = new Map<string, Array<{ user: string; screen?: string; ts: number }>>()

      for (const u of userSummaries) {
        lines.push(`### ${u.name} — Errors (${u.error_count})`, '')
        if (u.errors.length === 0) {
          lines.push('*No errors recorded*', '')
        } else {
          for (const e of u.errors) {
            lines.push(`- \`${new Date(e.ts).toLocaleTimeString()}\` ${e.screen ? `[${e.screen}] ` : ''}${e.detail}`)

            const normalized = e.detail.replace(/\b[0-9a-f]{8,}\b/gi, '<id>').replace(/\d+(\.\d+)?/g, '<n>')
            if (!allErrorDetails.has(normalized)) allErrorDetails.set(normalized, [])
            allErrorDetails.get(normalized)!.push({ user: u.name, screen: e.screen, ts: e.ts })
          }
          lines.push('')
        }
      }

      // Paired similar errors
      const sharedErrors = [...allErrorDetails.entries()].filter(([, occurrences]) => {
        const uniqueUsers = new Set(occurrences.map(o => o.user))
        return uniqueUsers.size > 1
      })

      if (sharedErrors.length > 0) {
        lines.push('---', '', '## Shared / Similar Errors Across Users', '')
        for (const [pattern, occurrences] of sharedErrors) {
          const users = [...new Set(occurrences.map(o => o.user))]
          lines.push(`### ${pattern}`)
          lines.push(`**Affects:** ${users.join(', ')}`)
          lines.push('')
          for (const o of occurrences) {
            lines.push(`- **${o.user}** at \`${new Date(o.ts).toLocaleTimeString()}\` ${o.screen ? `[${o.screen}]` : ''}`)
          }
          lines.push('')
        }
      }

      lines.push('---', '')
      lines.push('## Instructions', '', 'Drag this file into Cursor and ask: "Fix all the issues in this report."', '')

      const content = lines.join('\n')
      const blob = new Blob([content], { type: 'text/markdown' })
      const url = URL.createObjectURL(blob)
      const a = document.createElement('a')
      a.href = url
      a.download = `user-comparison-report-${new Date().toISOString().split('T')[0]}.md`
      document.body.appendChild(a)
      a.click()
      document.body.removeChild(a)
      URL.revokeObjectURL(url)
      setComparisonDownloaded(true)
    } catch (e) {
      alert(`Comparison analysis failed: ${e}`)
    }
    setComparingUsers(false)
  }

  const filteredEntries = filter === 'all' ? entries : entries.filter(e => e.type === filter)
  const errorCount = entries.filter(e => e.type === 'error').length
  const screenCount = new Set(entries.filter(e => e.type === 'screen').map(e => e.detail)).size

  return (
    <AdminShell>
      <div style={{ padding: 32, maxWidth: 1400, margin: '0 auto' }}>
        <h1 style={{ fontSize: 24, fontWeight: 700, marginBottom: 8 }}>Dev Session Logs</h1>
        <p style={{ color: 'var(--text-muted)', marginBottom: 16, fontSize: 14 }}>
          Toggle advanced logging for specific users. Watch sessions live. Analyze with Claude.
        </p>

        {/* Tabs */}
        <div style={{ display: 'flex', gap: 4, marginBottom: 20 }}>
          <button onClick={() => setActiveTab('sessions')} style={{ padding: '8px 20px', borderRadius: 8, fontWeight: 600, fontSize: 13, border: 'none', cursor: 'pointer', background: activeTab === 'sessions' ? 'var(--accent)' : 'var(--bg-secondary)', color: activeTab === 'sessions' ? 'white' : 'var(--text-muted)' }}>
            Sessions
          </button>
          <button onClick={() => { setActiveTab('unified'); loadUnifiedFeed() }} style={{ padding: '8px 20px', borderRadius: 8, fontWeight: 600, fontSize: 13, border: 'none', cursor: 'pointer', background: activeTab === 'unified' ? 'var(--accent)' : 'var(--bg-secondary)', color: activeTab === 'unified' ? 'white' : 'var(--text-muted)' }}>
            Unified Feed
          </button>
        </div>

        {/* Enabled Users */}
        <div style={{ background: 'var(--bg-secondary)', borderRadius: 12, padding: 20, marginBottom: 24, border: '1px solid var(--border)' }}>
          <h2 style={{ fontSize: 16, fontWeight: 600, marginBottom: 12 }}>Logging-Enabled Users</h2>
          <div style={{ display: 'flex', gap: 8, marginBottom: 12 }}>
            <input
              value={enableUserId}
              onChange={e => setEnableUserId(e.target.value)}
              placeholder="Paste user UUID to enable logging..."
              style={{ flex: 1, padding: '8px 12px', borderRadius: 8, border: '1px solid var(--border)', background: 'var(--bg-primary)', color: 'var(--text-primary)', fontSize: 13 }}
            />
            <button onClick={enableForUser} style={{ padding: '8px 16px', borderRadius: 8, background: 'var(--accent)', color: 'white', fontWeight: 600, fontSize: 13, border: 'none', cursor: 'pointer' }}>
              Enable
            </button>
          </div>
          {devUsers.length === 0 ? (
            <p style={{ color: 'var(--text-muted)', fontSize: 13 }}>No users have logging enabled yet.</p>
          ) : (
            <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
              {devUsers.map(u => (
                <div key={u.id} style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '8px 12px', borderRadius: 8, background: 'var(--bg-primary)' }}>
                  <div>
                    <span style={{ fontWeight: 600, fontSize: 13 }}>{u.user_profiles?.name || u.user_profiles?.username || u.user_id.slice(0, 8)}</span>
                    <span style={{ color: 'var(--text-muted)', fontSize: 12, marginLeft: 8 }}>{u.user_profiles?.email}</span>
                  </div>
                  <button
                    onClick={() => toggleLogging(u.user_id, !u.enabled)}
                    style={{ padding: '4px 12px', borderRadius: 6, border: '1px solid var(--border)', background: u.enabled ? '#22c55e22' : 'transparent', color: u.enabled ? '#22c55e' : 'var(--text-muted)', fontSize: 12, fontWeight: 600, cursor: 'pointer' }}
                  >
                    {u.enabled ? 'ON' : 'OFF'}
                  </button>
                </div>
              ))}
            </div>
          )}
        </div>

        {/* Unified Feed Tab */}
        {activeTab === 'unified' && (
          <div style={{ background: 'var(--bg-secondary)', borderRadius: 12, padding: 20, border: '1px solid var(--border)', marginBottom: 24 }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 12 }}>
              <h2 style={{ fontSize: 16, fontWeight: 600 }}>All Users — Rolling Log Feed ({unifiedEntries.length} entries)</h2>
              <button onClick={analyzeTrends} disabled={analyzingTrends || unifiedEntries.length === 0} style={{ padding: '8px 20px', borderRadius: 8, background: '#7c3aed', color: 'white', fontWeight: 600, fontSize: 13, border: 'none', cursor: 'pointer', opacity: analyzingTrends ? 0.5 : 1 }}>
                {analyzingTrends ? 'Analyzing Trends...' : 'Analyze Trends with Claude'}
              </button>
            </div>
            <div style={{ display: 'flex', gap: 8, marginBottom: 12 }}>
              <span style={{ background: 'var(--bg-primary)', padding: '4px 10px', borderRadius: 6, fontSize: 12 }}>
                {new Set(unifiedEntries.map(e => e.user_id)).size} users
              </span>
              <span style={{ background: 'var(--bg-primary)', padding: '4px 10px', borderRadius: 6, fontSize: 12 }}>
                {new Set(unifiedEntries.map(e => e.session_id)).size} sessions
              </span>
              <span style={{ background: '#ef444422', color: '#ef4444', padding: '4px 10px', borderRadius: 6, fontSize: 12 }}>
                {unifiedEntries.filter(e => e.type === 'error').length} errors
              </span>
            </div>
            <div style={{ maxHeight: '60vh', overflow: 'auto', fontFamily: 'monospace', fontSize: 12 }}>
              {unifiedEntries.slice(0, 500).map((entry, i) => (
                <div key={i} style={{ display: 'flex', gap: 8, padding: '3px 0', borderBottom: '1px solid var(--border)' }}>
                  <span style={{ color: 'var(--text-muted)', minWidth: 70, fontSize: 11 }}>{new Date(entry.ts).toLocaleTimeString()}</span>
                  <span style={{ color: '#06b6d4', minWidth: 60, fontSize: 11 }}>{(entry.session_id || '').slice(0, 8)}</span>
                  <span style={{ color: typeColors[entry.type] || '#6b7280', fontWeight: 700, minWidth: 50, fontSize: 11, textTransform: 'uppercase' }}>{entry.type}</span>
                  {entry.screen && <span style={{ color: '#22c55e', fontSize: 11 }}>[{entry.screen}]</span>}
                  <span style={{ color: entry.type === 'error' ? '#ef4444' : 'var(--text-primary)', flex: 1 }}>{entry.detail}</span>
                  {entry.duration_ms != null && <span style={{ color: entry.duration_ms > 500 ? '#ef4444' : '#f59e0b', fontSize: 11 }}>{entry.duration_ms}ms</span>}
                </div>
              ))}
              {unifiedEntries.length === 0 && <p style={{ color: 'var(--text-muted)', padding: 20, textAlign: 'center' }}>No entries yet. Enable logging for users and wait for sessions.</p>}
            </div>
          </div>
        )}

        {/* Sessions List + Detail */}
        {activeTab === 'sessions' && <div style={{ display: 'grid', gridTemplateColumns: selectedSession ? '320px 1fr' : '1fr', gap: 20 }}>
          {/* Sessions List */}
          <div style={{ background: 'var(--bg-secondary)', borderRadius: 12, padding: 16, border: '1px solid var(--border)', maxHeight: '70vh', overflow: 'auto' }}>
            <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 12 }}>
              <h2 style={{ fontSize: 14, fontWeight: 600 }}>Recent Sessions</h2>
              {checkedUserIds.size > 0 && (
                <span style={{ fontSize: 11, color: 'var(--accent)', fontWeight: 600 }}>
                  {checkedUserIds.size} selected
                </span>
              )}
            </div>

            {/* Compare button */}
            {checkedUserIds.size >= 1 && (
              <button
                onClick={compareCheckedUsers}
                disabled={comparingUsers}
                style={{
                  display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 6,
                  width: '100%', padding: '8px 12px', borderRadius: 8, marginBottom: 12,
                  background: comparisonDownloaded ? '#4b5563' : '#7c3aed', color: 'white',
                  fontWeight: 600, fontSize: 12, border: 'none', cursor: comparingUsers ? 'wait' : 'pointer',
                  opacity: comparingUsers ? 0.6 : 1,
                }}
              >
                {comparingUsers ? '⏳ Analyzing...' : comparisonDownloaded ? '✓ Report Downloaded' : `🧠 Compare ${checkedUserIds.size} User${checkedUserIds.size > 1 ? 's' : ''} with Claude`}
              </button>
            )}

            {loading ? <p style={{ color: 'var(--text-muted)', fontSize: 13 }}>Loading...</p> : sessions.length === 0 ? (
              <p style={{ color: 'var(--text-muted)', fontSize: 13 }}>No sessions recorded yet.</p>
            ) : (() => {
              const uniqueUserIds = [...new Set(sessions.map(s => s.user_id))]
              return uniqueUserIds.map(userId => {
                const userSessions = sessions.filter(s => s.user_id === userId)
                const sessionUser = devUsers.find(u => u.user_id === userId)
                const userName = sessionUser?.user_profiles?.name || sessionUser?.user_profiles?.username || null
                const isChecked = checkedUserIds.has(userId)

                return (
                  <div key={userId} style={{ marginBottom: 8 }}>
                    {/* User header with checkbox */}
                    <div
                      style={{
                        display: 'flex', alignItems: 'center', gap: 8, padding: '6px 8px', borderRadius: 8, marginBottom: 2,
                        background: isChecked ? 'rgba(124, 58, 237, 0.08)' : 'transparent',
                        border: isChecked ? '1px solid rgba(124, 58, 237, 0.2)' : '1px solid transparent',
                      }}
                    >
                      <input
                        type="checkbox"
                        checked={isChecked}
                        onChange={() => toggleUserCheck(userId)}
                        style={{ width: 14, height: 14, cursor: 'pointer', accentColor: '#7c3aed' }}
                        title={`Select ${userName || userId.slice(0, 8)} for comparison`}
                      />
                      <span style={{ fontSize: 12, fontWeight: 700, color: isChecked ? '#7c3aed' : 'var(--text-primary)' }}>
                        {userName || userId.slice(0, 8)}
                      </span>
                      <span style={{ fontSize: 10, color: 'var(--text-muted)', marginLeft: 'auto' }}>
                        {userSessions.length} session{userSessions.length !== 1 ? 's' : ''}
                      </span>
                    </div>

                    {/* Session buttons */}
                    {userSessions.map(s => {
                      const di = (typeof s.device_info === 'string' ? (() => { try { return JSON.parse(s.device_info) } catch { return {} } })() : s.device_info) || {}
                      const deviceModel = di.model || di.name || ''
                      const deviceOS = di.systemVersion ? `iOS ${di.systemVersion}` : ''
                      const appVer = di.appVersion ? `v${di.appVersion}` : ''
                      const deviceLabel = [deviceModel, deviceOS, appVer].filter(Boolean).join(' · ')
                      return (
                        <button
                          key={s.session_id}
                          onClick={() => openSession(s.session_id)}
                          style={{
                            display: 'block', width: '100%', textAlign: 'left', padding: '8px 12px 8px 30px', borderRadius: 8, marginBottom: 2, border: 'none', cursor: 'pointer',
                            background: selectedSession === s.session_id ? 'rgba(37, 99, 235, 0.12)' : 'transparent',
                            color: 'var(--text-primary)',
                          }}
                        >
                          <div style={{ display: 'flex', alignItems: 'center', gap: 6, marginBottom: 1 }}>
                            <span style={{ fontSize: 10, color: 'var(--text-muted)', fontFamily: 'monospace' }}>{s.session_id.slice(0, 8)}</span>
                          </div>
                          {deviceLabel && (
                            <div style={{ fontSize: 11, color: 'var(--text-muted)', marginBottom: 1 }}>
                              {deviceLabel}
                            </div>
                          )}
                          <div style={{ fontSize: 11, color: 'var(--text-muted)' }}>
                            {new Date(s.started_at).toLocaleString()} · {s.batch_count} batches
                          </div>
                        </button>
                      )
                    })}
                  </div>
                )
              })
            })()}
          </div>

          {/* Session Detail */}
          {selectedSession && (
            <div style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
              {/* Summary Bar */}
              <div style={{ display: 'flex', gap: 12, alignItems: 'center', flexWrap: 'wrap' }}>
                <span style={{ background: 'var(--bg-secondary)', padding: '6px 12px', borderRadius: 8, fontSize: 13 }}>
                  {entries.length} entries
                </span>
                <span style={{ background: '#22c55e22', color: '#22c55e', padding: '6px 12px', borderRadius: 8, fontSize: 13 }}>
                  {screenCount} screens
                </span>
                {errorCount > 0 && (
                  <span style={{ background: '#ef444422', color: '#ef4444', padding: '6px 12px', borderRadius: 8, fontSize: 13 }}>
                    {errorCount} errors
                  </span>
                )}
                <label style={{ display: 'flex', alignItems: 'center', gap: 4, fontSize: 12, color: 'var(--text-muted)', cursor: 'pointer' }}>
                  <input type="checkbox" checked={autoRefresh} onChange={e => setAutoRefresh(e.target.checked)} />
                  Live refresh
                </label>
                <button
                  onClick={analyzeSession}
                  disabled={analyzing}
                  style={{ marginLeft: 'auto', padding: '6px 16px', borderRadius: 8, background: '#7c3aed', color: 'white', fontWeight: 600, fontSize: 13, border: 'none', cursor: 'pointer', opacity: analyzing ? 0.5 : 1 }}
                >
                  {analyzing ? 'Analyzing...' : 'Analyze with Claude'}
                </button>
              </div>

              {/* Filters */}
              <div style={{ display: 'flex', gap: 4 }}>
                {['all', 'screen', 'tap', 'api', 'error', 'perf', 'state', 'log'].map(f => (
                  <button
                    key={f}
                    onClick={() => setFilter(f)}
                    style={{
                      padding: '4px 10px', borderRadius: 6, fontSize: 11, fontWeight: 600, border: 'none', cursor: 'pointer',
                      background: filter === f ? 'var(--accent)' : 'var(--bg-secondary)',
                      color: filter === f ? 'white' : 'var(--text-muted)',
                    }}
                  >
                    {f.toUpperCase()}
                  </button>
                ))}
              </div>

              {/* Timeline */}
              <div style={{ background: 'var(--bg-secondary)', borderRadius: 12, padding: 16, border: '1px solid var(--border)', maxHeight: '50vh', overflow: 'auto', fontFamily: 'monospace', fontSize: 12 }}>
                {filteredEntries.map((entry, i) => (
                  <div key={i} style={{ display: 'flex', gap: 8, padding: '3px 0', borderBottom: '1px solid var(--border)', alignItems: 'flex-start' }}>
                    <span style={{ color: 'var(--text-muted)', minWidth: 70, fontSize: 11 }}>
                      {new Date(entry.ts).toLocaleTimeString()}
                    </span>
                    <span style={{
                      color: typeColors[entry.type] || '#6b7280',
                      fontWeight: 700, minWidth: 50, fontSize: 11, textTransform: 'uppercase',
                    }}>
                      {entry.type}
                    </span>
                    {entry.screen && <span style={{ color: '#22c55e', fontSize: 11 }}>[{entry.screen}]</span>}
                    <span style={{ color: entry.type === 'error' ? '#ef4444' : 'var(--text-primary)', flex: 1 }}>
                      {entry.detail}
                    </span>
                    {entry.duration_ms != null && (
                      <span style={{ color: entry.duration_ms > 500 ? '#ef4444' : '#f59e0b', fontSize: 11 }}>
                        {entry.duration_ms}ms
                      </span>
                    )}
                  </div>
                ))}
              </div>

              {/* Suggestions */}
              {suggestions.length > 0 && (
                <div>
                  <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 8 }}>
                    <h3 style={{ fontSize: 14, fontWeight: 600 }}>Claude Suggestions ({suggestions.length})</h3>
                    <div style={{ display: 'flex', gap: 8 }}>
                      <button
                        onClick={() => { downloadSuggestionsAsMD(); setDownloaded(true) }}
                        disabled={downloaded}
                        style={{ padding: '6px 16px', borderRadius: 8, background: downloaded ? '#4b5563' : '#7c3aed', color: 'white', fontWeight: 600, fontSize: 13, border: 'none', cursor: downloaded ? 'default' : 'pointer', opacity: downloaded ? 0.6 : 1 }}
                      >
                        {downloaded ? 'Report Downloaded' : 'Download .md Report'}
                      </button>
                      {suggestions.some(s => s.status === 'new' && s.file_path && s.code_diff) && (
                        <button
                          onClick={createBatchPR}
                          disabled={batchingPR}
                          style={{ padding: '6px 16px', borderRadius: 8, background: '#22c55e', color: 'white', fontWeight: 600, fontSize: 13, border: 'none', cursor: 'pointer', opacity: batchingPR ? 0.5 : 1 }}
                        >
                          {batchingPR ? 'Creating...' : `Create PR for All (${suggestions.filter(s => s.status === 'new' && s.file_path && s.code_diff).length})`}
                        </button>
                      )}
                    </div>
                  </div>
                  {suggestions.map(s => (
                    <div key={s.id} style={{ background: 'var(--bg-secondary)', borderRadius: 10, padding: 16, marginBottom: 8, border: `1px solid ${s.severity === 'critical' ? '#ef4444' : s.severity === 'high' ? '#f59e0b' : 'var(--border)'}` }}>
                      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: 6 }}>
                        <div>
                          <span style={{ fontWeight: 700, fontSize: 14 }}>{s.title}</span>
                          <span style={{ marginLeft: 8, fontSize: 11, padding: '2px 6px', borderRadius: 4, background: s.severity === 'critical' ? '#ef444422' : s.severity === 'high' ? '#f59e0b22' : '#3b82f622', color: s.severity === 'critical' ? '#ef4444' : s.severity === 'high' ? '#f59e0b' : '#3b82f6' }}>
                            {s.severity}
                          </span>
                        </div>
                        {s.pr_url ? (
                          <a href={s.pr_url} target="_blank" rel="noreferrer" style={{ fontSize: 12, color: '#22c55e', fontWeight: 600, display: 'flex', alignItems: 'center', gap: 4 }}>
                            <span style={{ width: 8, height: 8, borderRadius: '50%', background: '#22c55e', display: 'inline-block' }} />
                            View PR
                          </a>
                        ) : s.status === 'creating_pr' ? (
                          <span style={{ fontSize: 12, color: 'var(--text-muted)' }}>Creating PR...</span>
                        ) : s.status === 'new' && s.file_path && s.code_diff ? (
                          <button onClick={() => createPR(s)} style={{ padding: '4px 12px', borderRadius: 6, background: '#22c55e', color: 'white', fontWeight: 600, fontSize: 12, border: 'none', cursor: 'pointer' }}>
                            Create PR
                          </button>
                        ) : s.status === 'new' ? (
                          <span style={{ fontSize: 11, color: 'var(--text-muted)' }}>No auto-fix available</span>
                        ) : null}
                      </div>
                      <p style={{ fontSize: 13, color: 'var(--text-secondary)', marginBottom: 6 }}>{s.description}</p>
                      {s.file_path && <p style={{ fontSize: 11, color: 'var(--text-muted)', fontFamily: 'monospace' }}>{s.file_path}</p>}
                      {s.code_diff && (
                        <pre style={{ fontSize: 11, background: 'var(--bg-primary)', padding: 10, borderRadius: 6, overflow: 'auto', marginTop: 6, maxHeight: 200 }}>
                          {s.code_diff}
                        </pre>
                      )}
                    </div>
                  ))}
                </div>
              )}
            </div>
          )}
        </div>}
      </div>
    </AdminShell>
  )
}
