'use client'

import { useEffect, useState, useCallback, useMemo } from 'react'
import AdminShell from '@/components/AdminShell'

// ─── Types ────────────────────────────────────────────────────────────────

type UserProfileSummary = { name?: string | null; email?: string | null; username?: string | null } | null

type Enrollment = {
  user_id: string
  enrolled_at: string
  journey_started_at: string
  journey_ends_at: string
  auth_provider: string | null
  install_app_version: string | null
  install_build_number: string | null
  install_device_model: string | null
  install_ios_version: string | null
  install_locale: string | null
  install_timezone: string | null
  referral_source: string | null
  total_events: number
  total_sessions: number
  total_errors: number
  total_crashes: number
  last_event_at: string | null
  last_screen: string | null
  d1_report_generated: boolean
  d2_report_generated: boolean
  d3_report_generated: boolean
  final_report_generated: boolean
  completed_onboarding: boolean
  completed_first_workout: boolean
  logged_first_meal: boolean
  added_first_friend: boolean
  connected_wearable: boolean
  saw_paywall: boolean
  converted_paywall: boolean
  user_profiles?: UserProfileSummary
}

type Session = {
  id: string
  session_id: string
  started_at: string
  ended_at: string | null
  duration_seconds: number | null
  network_type: string | null
  entry_screen: string | null
  last_screen: string | null
  app_version: string | null
  device_model: string | null
  ios_version: string | null
  error_count: number
  crash_count: number
  screen_view_count: number
  tap_count: number
}

type ReportListItem = {
  id: string
  checkpoint: string
  generated_at: string
  window_started_at: string
  window_ended_at: string
  review_status: string
  claude_model: string | null
  claude_tokens_in: number | null
  claude_tokens_out: number | null
  reviewed_by: string | null
  reviewed_at: string | null
  notes: string | null
}

type EventRow = {
  id: string
  session_id: string | null
  occurred_at: string
  event_type: string
  screen: string | null
  detail: string | null
  payload: Record<string, unknown>
  is_error: boolean
  severity: string | null
}

type ReportFull = {
  id: string
  user_id: string
  checkpoint: string
  generated_at: string
  window_started_at: string
  window_ended_at: string
  structured_data: Record<string, unknown>
  report_md: string
  claude_analysis_md: string | null
  claude_model: string | null
  claude_tokens_in: number | null
  claude_tokens_out: number | null
  review_status: string
  reviewed_by: string | null
  reviewed_at: string | null
  notes: string | null
  user_profiles?: UserProfileSummary
}

type CohortSummary = {
  total_enrollments: number
  completed_onboarding_pct: number
  completed_first_workout_pct: number
  logged_first_meal_pct: number
  added_first_friend_pct: number
  connected_wearable_pct: number
  saw_paywall_pct: number
  converted_paywall_pct: number
  avg_events_per_user: number
  avg_sessions_per_user: number
  avg_errors_per_user: number
  avg_crashes_per_user: number
}

const eventTypeColors: Record<string, string> = {
  screen: '#22c55e', tap: '#3b82f6', funnel: '#a855f7',
  state: '#6b7280', api: '#06b6d4', error: '#ef4444',
  crash: '#dc2626', workout: '#f59e0b', meal: '#84cc16',
  social: '#ec4899', paywall: '#eab308', integration: '#0ea5e9',
  permission: '#8b5cf6', notification: '#10b981', background: '#94a3b8',
  performance: '#fb923c', system: '#64748b',
}

async function adminAction<T = unknown>(action: string, params: Record<string, unknown> = {}): Promise<T> {
  const res = await fetch('/api/admin', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ action, ...params }),
  })
  return res.json() as Promise<T>
}

// ─── Component ────────────────────────────────────────────────────────────

export default function NewUserReportsPage() {
  const [enrollments, setEnrollments] = useState<Enrollment[]>([])
  const [onlyActive, setOnlyActive] = useState(true)
  const [loading, setLoading] = useState(true)
  const [selectedUserId, setSelectedUserId] = useState<string | null>(null)
  const [userDetail, setUserDetail] = useState<{
    enrollment: Enrollment | null
    sessions: Session[]
    reports: ReportListItem[]
    recent_events: EventRow[]
  } | null>(null)
  const [selectedReportId, setSelectedReportId] = useState<string | null>(null)
  const [reportFull, setReportFull] = useState<ReportFull | null>(null)
  const [generating, setGenerating] = useState(false)
  const [cohort, setCohort] = useState<CohortSummary | null>(null)
  const [cohortDays, setCohortDays] = useState(7)
  const [eventFilter, setEventFilter] = useState<string>('all')

  const loadEnrollments = useCallback(async () => {
    setLoading(true)
    const data = await adminAction<{ enrollments: Enrollment[] }>('get_nuj_enrollments', { limit: 100, only_active: onlyActive })
    setEnrollments(data.enrollments ?? [])
    setLoading(false)
  }, [onlyActive])

  const loadCohort = useCallback(async () => {
    const data = await adminAction<{ summary: CohortSummary }>('get_nuj_cohort_summary', { days: cohortDays })
    setCohort(data.summary)
  }, [cohortDays])

  const loadUserDetail = useCallback(async (userId: string) => {
    const data = await adminAction<{
      enrollment: Enrollment
      sessions: Session[]
      reports: ReportListItem[]
      recent_events: EventRow[]
    }>('get_nuj_user_detail', { user_id: userId })
    setUserDetail(data)
  }, [])

  const loadReport = useCallback(async (reportId: string) => {
    const data = await adminAction<{ report: ReportFull }>('get_nuj_report', { report_id: reportId })
    setReportFull(data.report)
  }, [])

  useEffect(() => { loadEnrollments() }, [loadEnrollments])
  useEffect(() => { loadCohort() }, [loadCohort])
  useEffect(() => {
    if (selectedUserId) loadUserDetail(selectedUserId)
    else { setUserDetail(null); setSelectedReportId(null); setReportFull(null) }
  }, [selectedUserId, loadUserDetail])
  useEffect(() => {
    if (selectedReportId) loadReport(selectedReportId)
    else setReportFull(null)
  }, [selectedReportId, loadReport])

  async function generateReport(userId: string, checkpoint: string) {
    setGenerating(true)
    try {
      const data = await adminAction<{ ok?: boolean; error?: string }>('generate_new_user_report', {
        user_id: userId,
        checkpoint,
        dispatch_to_claude: true,
      })
      if (data.error) alert(`Report failed: ${data.error}`)
      else {
        alert(`Report ${checkpoint} generated. Refreshing…`)
        await loadUserDetail(userId)
      }
    } catch (e) {
      alert(`Error: ${e}`)
    } finally {
      setGenerating(false)
    }
  }

  async function copyReportForClaude() {
    if (!reportFull) return
    const text = reportFull.report_md
    try {
      await navigator.clipboard.writeText(text)
      alert('Report Markdown copied — paste into Claude.')
    } catch {
      alert('Clipboard unavailable. Select the report and copy manually.')
    }
  }

  async function updateReviewStatus(status: string) {
    if (!reportFull) return
    const notes = status === 'actioned' ? prompt('Notes (optional):') ?? undefined : undefined
    await adminAction('update_nuj_report_status', { report_id: reportFull.id, status, notes })
    await loadReport(reportFull.id)
    if (selectedUserId) await loadUserDetail(selectedUserId)
  }

  const filteredEvents = useMemo(() => {
    if (!userDetail) return []
    if (eventFilter === 'all') return userDetail.recent_events
    if (eventFilter === 'errors') return userDetail.recent_events.filter(e => e.is_error)
    return userDetail.recent_events.filter(e => e.event_type === eventFilter)
  }, [userDetail, eventFilter])

  const uniqueEventTypes = useMemo(() => {
    if (!userDetail) return []
    return Array.from(new Set(userDetail.recent_events.map(e => e.event_type)))
  }, [userDetail])

  // ─── Render ────────────────────────────────────────────────────────────

  return (
    <AdminShell>
      <div style={{ padding: 24 }}>
        <div className="flex items-center justify-between mb-4">
          <div>
            <h1 style={{ fontSize: 24, fontWeight: 700, marginBottom: 4 }}>New User Reports</h1>
            <div style={{ color: 'var(--text-muted)', fontSize: 13 }}>
              First-72-hour high-resolution behavioral telemetry. Auto-enrolled by tenure; auto-deactivates at 72h.
            </div>
          </div>
          <div className="flex gap-2 items-center">
            <label className="flex items-center gap-2 text-sm">
              <input type="checkbox" checked={onlyActive} onChange={e => setOnlyActive(e.target.checked)} />
              Only active (within 72h window)
            </label>
            <button onClick={loadEnrollments} className="px-3 py-1.5 rounded text-sm" style={{ background: 'var(--accent)', color: 'white' }}>
              Refresh
            </button>
          </div>
        </div>

        {/* ─── Cohort summary ─── */}
        <CohortSummaryCard summary={cohort} days={cohortDays} setDays={setCohortDays} />

        <div style={{ display: 'grid', gridTemplateColumns: '320px 1fr', gap: 16, marginTop: 16 }}>
          {/* ─── Enrollments list ─── */}
          <div style={{ background: 'var(--bg-secondary)', borderRadius: 8, padding: 12, maxHeight: '70vh', overflowY: 'auto' }}>
            <div style={{ fontSize: 12, fontWeight: 600, marginBottom: 8, color: 'var(--text-muted)' }}>
              {loading ? 'Loading…' : `${enrollments.length} enrollments`}
            </div>
            {enrollments.map(en => (
              <button
                key={en.user_id}
                onClick={() => { setSelectedUserId(en.user_id); setSelectedReportId(null) }}
                style={{
                  display: 'block',
                  width: '100%',
                  textAlign: 'left',
                  padding: 10,
                  borderRadius: 6,
                  marginBottom: 4,
                  background: selectedUserId === en.user_id ? 'rgba(37,99,235,0.18)' : 'transparent',
                  borderLeft: en.total_crashes > 0 ? '3px solid #dc2626'
                              : en.total_errors > 5 ? '3px solid #f59e0b'
                              : '3px solid transparent',
                }}
              >
                <div style={{ fontWeight: 600, fontSize: 13 }}>
                  {en.user_profiles?.name || en.user_profiles?.username || en.user_id.slice(0, 8)}
                </div>
                <div style={{ fontSize: 11, color: 'var(--text-muted)', marginTop: 2 }}>
                  {en.user_profiles?.email ?? '(no email)'}
                </div>
                <div style={{ fontSize: 11, color: 'var(--text-muted)', marginTop: 2, display: 'flex', gap: 8, flexWrap: 'wrap' }}>
                  <span>📊 {en.total_events}</span>
                  <span>🪟 {en.total_sessions}</span>
                  <span style={{ color: en.total_errors > 0 ? '#f59e0b' : 'var(--text-muted)' }}>⚠️ {en.total_errors}</span>
                  <span style={{ color: en.total_crashes > 0 ? '#dc2626' : 'var(--text-muted)' }}>💥 {en.total_crashes}</span>
                </div>
                <div style={{ fontSize: 10, color: 'var(--text-muted)', marginTop: 4 }}>
                  {checkpointBadges(en)}
                </div>
              </button>
            ))}
          </div>

          {/* ─── Right pane: user detail ─── */}
          <div>
            {!selectedUserId && (
              <div style={{ padding: 32, textAlign: 'center', color: 'var(--text-muted)' }}>
                Select a user to see their full journey.
              </div>
            )}

            {selectedUserId && userDetail && (
              <>
                <UserDetailHeader
                  detail={userDetail}
                  generating={generating}
                  onGenerate={(checkpoint) => generateReport(selectedUserId, checkpoint)}
                />

                {/* Reports list */}
                <ReportsList
                  reports={userDetail.reports}
                  selectedReportId={selectedReportId}
                  onSelect={setSelectedReportId}
                />

                {/* Selected report viewer */}
                {reportFull && (
                  <ReportViewer
                    report={reportFull}
                    onCopy={copyReportForClaude}
                    onUpdateStatus={updateReviewStatus}
                  />
                )}

                {/* Sessions */}
                <SectionCard title={`Sessions (${userDetail.sessions.length})`}>
                  <SessionsTable sessions={userDetail.sessions} />
                </SectionCard>

                {/* Recent events */}
                <SectionCard title={`Recent events (${filteredEvents.length} of ${userDetail.recent_events.length})`}>
                  <div className="flex gap-2 mb-2 flex-wrap">
                    <FilterChip label="all" active={eventFilter === 'all'} onClick={() => setEventFilter('all')} />
                    <FilterChip label="errors" active={eventFilter === 'errors'} onClick={() => setEventFilter('errors')} color="#ef4444" />
                    {uniqueEventTypes.map(t => (
                      <FilterChip key={t} label={t} active={eventFilter === t} onClick={() => setEventFilter(t)} color={eventTypeColors[t]} />
                    ))}
                  </div>
                  <EventsTable events={filteredEvents} />
                </SectionCard>
              </>
            )}
          </div>
        </div>
      </div>
    </AdminShell>
  )
}

// ─── Subcomponents ───────────────────────────────────────────────────────

function checkpointBadges(en: Enrollment): string {
  const checks = [
    en.d1_report_generated ? 'D1✓' : 'D1·',
    en.d2_report_generated ? 'D2✓' : 'D2·',
    en.d3_report_generated ? 'D3✓' : 'D3·',
    en.final_report_generated ? 'F✓' : 'F·',
  ]
  return checks.join(' ')
}

function SectionCard({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div style={{ background: 'var(--bg-secondary)', borderRadius: 8, padding: 16, marginTop: 16 }}>
      <h3 style={{ fontSize: 14, fontWeight: 600, marginBottom: 12 }}>{title}</h3>
      {children}
    </div>
  )
}

function FilterChip({ label, active, onClick, color }: { label: string; active: boolean; onClick: () => void; color?: string }) {
  return (
    <button
      onClick={onClick}
      style={{
        padding: '4px 10px',
        borderRadius: 999,
        fontSize: 11,
        background: active ? (color ?? 'var(--accent)') : 'transparent',
        color: active ? 'white' : (color ?? 'var(--text-muted)'),
        border: `1px solid ${color ?? 'var(--border)'}`,
      }}
    >
      {label}
    </button>
  )
}

function CohortSummaryCard({ summary, days, setDays }: { summary: CohortSummary | null; days: number; setDays: (d: number) => void }) {
  return (
    <div style={{ background: 'var(--bg-secondary)', borderRadius: 8, padding: 16 }}>
      <div className="flex items-center justify-between mb-3">
        <h3 style={{ fontSize: 14, fontWeight: 600 }}>Cohort summary — last {days} days</h3>
        <div className="flex gap-1">
          {[1, 7, 14, 30].map(d => (
            <button
              key={d}
              onClick={() => setDays(d)}
              className="px-2 py-0.5 rounded text-xs"
              style={{ background: days === d ? 'var(--accent)' : 'transparent', color: days === d ? 'white' : 'var(--text-muted)', border: '1px solid var(--border)' }}
            >
              {d}d
            </button>
          ))}
        </div>
      </div>
      {!summary && <div style={{ color: 'var(--text-muted)', fontSize: 12 }}>Loading…</div>}
      {summary && (
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(140px, 1fr))', gap: 12 }}>
          <CohortStat label="Enrollments" value={summary.total_enrollments.toString()} />
          <CohortStat label="Onboarding %" value={`${summary.completed_onboarding_pct}%`} />
          <CohortStat label="First workout %" value={`${summary.completed_first_workout_pct}%`} />
          <CohortStat label="First meal %" value={`${summary.logged_first_meal_pct}%`} />
          <CohortStat label="First friend %" value={`${summary.added_first_friend_pct}%`} />
          <CohortStat label="Wearable connect %" value={`${summary.connected_wearable_pct}%`} />
          <CohortStat label="Saw paywall %" value={`${summary.saw_paywall_pct}%`} />
          <CohortStat label="Converted %" value={`${summary.converted_paywall_pct}%`} accent />
          <CohortStat label="Avg events/user" value={summary.avg_events_per_user.toString()} />
          <CohortStat label="Avg sessions/user" value={summary.avg_sessions_per_user.toString()} />
          <CohortStat label="Avg errors/user" value={summary.avg_errors_per_user.toString()} />
          <CohortStat label="Avg crashes/user" value={summary.avg_crashes_per_user.toString()} />
        </div>
      )}
    </div>
  )
}

function CohortStat({ label, value, accent }: { label: string; value: string; accent?: boolean }) {
  return (
    <div>
      <div style={{ fontSize: 10, color: 'var(--text-muted)', textTransform: 'uppercase', letterSpacing: 0.5 }}>{label}</div>
      <div style={{ fontSize: 20, fontWeight: 700, color: accent ? 'var(--accent)' : 'var(--text-primary)' }}>{value}</div>
    </div>
  )
}

function UserDetailHeader({
  detail, generating, onGenerate,
}: {
  detail: { enrollment: Enrollment | null; sessions: Session[]; reports: ReportListItem[]; recent_events: EventRow[] }
  generating: boolean
  onGenerate: (checkpoint: string) => void
}) {
  const en = detail.enrollment
  if (!en) return <div>(no enrollment)</div>

  const journeyEnd = new Date(en.journey_ends_at).getTime()
  const now = Date.now()
  const isActive = journeyEnd > now
  const hoursLeft = Math.max(0, Math.round((journeyEnd - now) / 3600_000))

  return (
    <div style={{ background: 'var(--bg-secondary)', borderRadius: 8, padding: 16 }}>
      <div className="flex items-start justify-between gap-4">
        <div>
          <div style={{ fontSize: 18, fontWeight: 700 }}>
            {en.user_profiles?.name || en.user_profiles?.username || en.user_id}
          </div>
          <div style={{ color: 'var(--text-muted)', fontSize: 12, marginTop: 2 }}>
            {en.user_profiles?.email ?? '(no email)'} · <code style={{ fontSize: 11 }}>{en.user_id}</code>
          </div>
          <div style={{ fontSize: 12, marginTop: 8, display: 'flex', gap: 12, flexWrap: 'wrap' }}>
            <span><b>Provider:</b> {en.auth_provider ?? '?'}</span>
            <span><b>App:</b> {en.install_app_version ?? '?'} ({en.install_build_number ?? '?'})</span>
            <span><b>Device:</b> {en.install_device_model ?? '?'}</span>
            <span><b>iOS:</b> {en.install_ios_version ?? '?'}</span>
            <span><b>TZ:</b> {en.install_timezone ?? '?'}</span>
            <span><b>Locale:</b> {en.install_locale ?? '?'}</span>
            <span style={{ color: isActive ? '#22c55e' : 'var(--text-muted)' }}>
              <b>{isActive ? `Active · ${hoursLeft}h left` : 'Journey ended'}</b>
            </span>
          </div>
          <div style={{ marginTop: 10, display: 'flex', gap: 6, flexWrap: 'wrap' }}>
            <FunnelBadge label="Onboarding" hit={en.completed_onboarding} />
            <FunnelBadge label="First workout" hit={en.completed_first_workout} />
            <FunnelBadge label="First meal" hit={en.logged_first_meal} />
            <FunnelBadge label="First friend" hit={en.added_first_friend} />
            <FunnelBadge label="Wearable" hit={en.connected_wearable} />
            <FunnelBadge label="Saw paywall" hit={en.saw_paywall} />
            <FunnelBadge label="Converted" hit={en.converted_paywall} />
          </div>
        </div>
        <div className="flex flex-col gap-1">
          {(['D1', 'D2', 'D3', 'FINAL', 'MANUAL'] as const).map(cp => (
            <button
              key={cp}
              disabled={generating}
              onClick={() => onGenerate(cp)}
              className="px-3 py-1.5 rounded text-xs"
              style={{ background: 'var(--accent)', color: 'white', opacity: generating ? 0.5 : 1 }}
            >
              Generate {cp}
            </button>
          ))}
        </div>
      </div>
    </div>
  )
}

function FunnelBadge({ label, hit }: { label: string; hit: boolean }) {
  return (
    <span
      style={{
        padding: '2px 8px',
        borderRadius: 999,
        fontSize: 11,
        background: hit ? 'rgba(34,197,94,0.15)' : 'rgba(107,114,128,0.10)',
        color: hit ? '#22c55e' : 'var(--text-muted)',
        border: `1px solid ${hit ? '#22c55e' : 'var(--border)'}`,
      }}
    >
      {hit ? '✓' : '○'} {label}
    </span>
  )
}

function ReportsList({ reports, selectedReportId, onSelect }: {
  reports: ReportListItem[]
  selectedReportId: string | null
  onSelect: (id: string | null) => void
}) {
  if (reports.length === 0) {
    return (
      <SectionCard title="Reports">
        <div style={{ color: 'var(--text-muted)', fontSize: 12 }}>
          No reports yet. Click a Generate button above to create one on-demand.
        </div>
      </SectionCard>
    )
  }
  return (
    <SectionCard title={`Reports (${reports.length})`}>
      <table style={{ width: '100%', fontSize: 12 }}>
        <thead>
          <tr style={{ textAlign: 'left', color: 'var(--text-muted)' }}>
            <th style={{ padding: 6 }}>Checkpoint</th>
            <th>Generated</th>
            <th>Window</th>
            <th>Claude</th>
            <th>Status</th>
            <th></th>
          </tr>
        </thead>
        <tbody>
          {reports.map(r => (
            <tr
              key={r.id}
              style={{ background: selectedReportId === r.id ? 'rgba(37,99,235,0.10)' : 'transparent', cursor: 'pointer' }}
              onClick={() => onSelect(r.id === selectedReportId ? null : r.id)}
            >
              <td style={{ padding: 6, fontWeight: 600 }}>{r.checkpoint}</td>
              <td>{new Date(r.generated_at).toLocaleString()}</td>
              <td>{new Date(r.window_started_at).toLocaleString()} → {new Date(r.window_ended_at).toLocaleString()}</td>
              <td>{r.claude_model ? `${r.claude_model} · ${r.claude_tokens_in ?? '?'}→${r.claude_tokens_out ?? '?'} tok` : '—'}</td>
              <td><span style={{ fontSize: 11, padding: '2px 8px', borderRadius: 999, background: 'rgba(107,114,128,0.10)' }}>{r.review_status}</span></td>
              <td>{selectedReportId === r.id ? '▼' : '▶'}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </SectionCard>
  )
}

function ReportViewer({
  report, onCopy, onUpdateStatus,
}: {
  report: ReportFull
  onCopy: () => void
  onUpdateStatus: (status: string) => void
}) {
  return (
    <div style={{ background: 'var(--bg-secondary)', borderRadius: 8, padding: 16, marginTop: 16 }}>
      <div className="flex items-center justify-between mb-3">
        <h3 style={{ fontSize: 14, fontWeight: 600 }}>
          Report · {report.checkpoint} · generated {new Date(report.generated_at).toLocaleString()}
        </h3>
        <div className="flex gap-2">
          <button onClick={onCopy} className="px-3 py-1.5 rounded text-xs" style={{ background: 'var(--accent)', color: 'white' }}>
            Copy Markdown
          </button>
          {(['reviewed', 'actioned', 'archived'] as const).map(s => (
            <button
              key={s}
              onClick={() => onUpdateStatus(s)}
              className="px-3 py-1.5 rounded text-xs"
              style={{ background: 'transparent', color: 'var(--text-secondary)', border: '1px solid var(--border)' }}
            >
              Mark {s}
            </button>
          ))}
        </div>
      </div>

      {report.claude_analysis_md && (
        <div style={{ background: 'rgba(168,85,247,0.08)', borderRadius: 6, padding: 12, marginBottom: 12, border: '1px solid rgba(168,85,247,0.3)' }}>
          <div style={{ fontSize: 11, fontWeight: 600, color: '#a855f7', marginBottom: 8, textTransform: 'uppercase', letterSpacing: 0.5 }}>
            Claude analysis
          </div>
          <pre style={{ whiteSpace: 'pre-wrap', fontSize: 12, fontFamily: 'inherit', margin: 0 }}>
            {report.claude_analysis_md}
          </pre>
        </div>
      )}

      <details>
        <summary style={{ cursor: 'pointer', fontSize: 12, color: 'var(--text-muted)', marginBottom: 8 }}>
          Full report Markdown ({report.report_md.length.toLocaleString()} chars)
        </summary>
        <pre style={{
          whiteSpace: 'pre-wrap',
          fontSize: 11,
          fontFamily: 'ui-monospace, SFMono-Regular, monospace',
          background: 'var(--bg-primary)',
          padding: 12,
          borderRadius: 4,
          maxHeight: 500,
          overflowY: 'auto',
        }}>
          {report.report_md}
        </pre>
      </details>
    </div>
  )
}

function SessionsTable({ sessions }: { sessions: Session[] }) {
  if (sessions.length === 0) return <div style={{ color: 'var(--text-muted)', fontSize: 12 }}>No sessions yet.</div>
  return (
    <div style={{ overflowX: 'auto' }}>
      <table style={{ width: '100%', fontSize: 11 }}>
        <thead>
          <tr style={{ textAlign: 'left', color: 'var(--text-muted)' }}>
            <th style={{ padding: 4 }}>Started</th>
            <th>Duration</th>
            <th>Network</th>
            <th>Entry → Exit</th>
            <th>Screens</th>
            <th>Taps</th>
            <th>Errors</th>
            <th>Crashes</th>
          </tr>
        </thead>
        <tbody>
          {sessions.map(s => (
            <tr key={s.id}>
              <td style={{ padding: 4 }}>{new Date(s.started_at).toLocaleString()}</td>
              <td>{s.duration_seconds != null ? `${s.duration_seconds}s` : '(open)'}</td>
              <td>{s.network_type ?? '?'}</td>
              <td>{s.entry_screen ?? '?'} → {s.last_screen ?? '?'}</td>
              <td>{s.screen_view_count}</td>
              <td>{s.tap_count}</td>
              <td style={{ color: s.error_count > 0 ? '#f59e0b' : undefined }}>{s.error_count}</td>
              <td style={{ color: s.crash_count > 0 ? '#dc2626' : undefined }}>{s.crash_count}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}

function EventsTable({ events }: { events: EventRow[] }) {
  if (events.length === 0) return <div style={{ color: 'var(--text-muted)', fontSize: 12 }}>No events.</div>
  return (
    <div style={{ maxHeight: 400, overflowY: 'auto', fontSize: 11, fontFamily: 'ui-monospace, SFMono-Regular, monospace' }}>
      {events.map(e => (
        <div key={e.id} style={{ display: 'flex', gap: 8, padding: '3px 0', borderBottom: '1px dotted var(--border)' }}>
          <span style={{ color: 'var(--text-muted)', minWidth: 170 }}>{new Date(e.occurred_at).toLocaleString()}</span>
          <span style={{ color: eventTypeColors[e.event_type] ?? 'var(--text-muted)', minWidth: 95, fontWeight: 600 }}>{e.event_type}</span>
          <span style={{ color: 'var(--text-muted)', minWidth: 130 }}>{e.screen ?? '—'}</span>
          <span style={{ flex: 1 }}>{e.detail ?? '(no detail)'}</span>
          {e.is_error && <span style={{ color: '#ef4444' }}>⚠️</span>}
        </div>
      ))}
    </div>
  )
}
