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
    if (data.error) { alert(`PR failed: ${data.error}`); return }

    await adminAction('update_suggestion_status', {
      suggestion_id: suggestion.id,
      status: 'pr_created',
      pr_url: data.pr_url,
      pr_branch: data.branch,
    })
    alert(`Draft PR created: ${data.pr_url}`)
    const sugData = await adminAction('get_dev_suggestions', { session_id: selectedSession })
    setSuggestions(sugData.suggestions || [])
  }

  const filteredEntries = filter === 'all' ? entries : entries.filter(e => e.type === filter)
  const errorCount = entries.filter(e => e.type === 'error').length
  const screenCount = new Set(entries.filter(e => e.type === 'screen').map(e => e.detail)).size

  return (
    <AdminShell>
      <div style={{ padding: 32, maxWidth: 1400, margin: '0 auto' }}>
        <h1 style={{ fontSize: 24, fontWeight: 700, marginBottom: 8 }}>Dev Session Logs</h1>
        <p style={{ color: 'var(--text-muted)', marginBottom: 24, fontSize: 14 }}>
          Toggle advanced logging for specific users. Watch sessions live. Analyze with Claude.
        </p>

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

        {/* Sessions List + Detail */}
        <div style={{ display: 'grid', gridTemplateColumns: selectedSession ? '320px 1fr' : '1fr', gap: 20 }}>
          {/* Sessions List */}
          <div style={{ background: 'var(--bg-secondary)', borderRadius: 12, padding: 16, border: '1px solid var(--border)', maxHeight: '70vh', overflow: 'auto' }}>
            <h2 style={{ fontSize: 14, fontWeight: 600, marginBottom: 12 }}>Recent Sessions</h2>
            {loading ? <p style={{ color: 'var(--text-muted)', fontSize: 13 }}>Loading...</p> : sessions.length === 0 ? (
              <p style={{ color: 'var(--text-muted)', fontSize: 13 }}>No sessions recorded yet.</p>
            ) : sessions.map(s => (
              <button
                key={s.session_id}
                onClick={() => openSession(s.session_id)}
                style={{
                  display: 'block', width: '100%', textAlign: 'left', padding: '10px 12px', borderRadius: 8, marginBottom: 4, border: 'none', cursor: 'pointer',
                  background: selectedSession === s.session_id ? 'rgba(37, 99, 235, 0.12)' : 'transparent',
                  color: 'var(--text-primary)',
                }}
              >
                <div style={{ fontSize: 13, fontWeight: 600 }}>{s.session_id.slice(0, 8)}</div>
                <div style={{ fontSize: 11, color: 'var(--text-muted)' }}>
                  {new Date(s.started_at).toLocaleString()} &middot; {s.batch_count} batches
                </div>
              </button>
            ))}
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
                  <h3 style={{ fontSize: 14, fontWeight: 600, marginBottom: 8 }}>Claude Suggestions</h3>
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
                          <a href={s.pr_url} target="_blank" rel="noreferrer" style={{ fontSize: 12, color: 'var(--accent)' }}>View PR</a>
                        ) : s.status === 'new' && s.file_path && s.code_diff ? (
                          <button onClick={() => createPR(s)} style={{ padding: '4px 12px', borderRadius: 6, background: '#22c55e', color: 'white', fontWeight: 600, fontSize: 12, border: 'none', cursor: 'pointer' }}>
                            Create PR
                          </button>
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
        </div>
      </div>
    </AdminShell>
  )
}
