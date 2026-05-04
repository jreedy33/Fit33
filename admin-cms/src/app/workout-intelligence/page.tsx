'use client'

import { Fragment, useCallback, useEffect, useState } from 'react'
import { useRouter } from 'next/navigation'
import AdminShell from '@/components/AdminShell'
import { adminApi } from '@/lib/api'

// ─── shared helpers (mirrors audit/page.tsx style) ────────────────────────────

function timeAgo(iso: string | null | undefined): string {
  if (!iso) return '—'
  const t = new Date(iso).getTime()
  if (Number.isNaN(t)) return '—'
  const diff = Date.now() - t
  if (diff < 0) return 'just now'
  const sec = Math.floor(diff / 1000)
  if (sec < 60) return sec <= 5 ? 'just now' : `${sec}s ago`
  const m = Math.floor(sec / 60)
  if (m < 60) return `${m}m ago`
  const h = Math.floor(m / 60)
  if (h < 24) return `${h}h ago`
  const d = Math.floor(h / 24)
  if (d < 30) return `${d}d ago`
  const mo = Math.floor(d / 30)
  if (mo < 12) return `${mo}mo ago`
  return `${Math.floor(d / 365)}y ago`
}

function statusBadgeClass(status: string | null | undefined): string {
  switch (status) {
    case 'complete': return 'badge badge-success'
    case 'pending':
    case 'analyzing': return 'badge badge-info'
    case 'failed': return 'badge badge-danger'
    case 'skipped':
    default: return 'badge badge-neutral'
  }
}

function qualityBandBadgeClass(band: string | null | undefined): string {
  switch (band) {
    case 'high': return 'badge badge-success'
    case 'medium': return 'badge badge-warning'
    default: return 'badge badge-neutral'
  }
}

// ─── types ────────────────────────────────────────────────────────────────────

type ReportRow = {
  id: string
  user_id: string
  workout_id: string
  quality_score: number | null
  quality_band: string | null
  status: string
  is_suspicious: boolean
  is_lost_session: boolean
  enqueued_at: string
  analyzed_at: string | null
  summary_md: string | null
  error_message: string | null
  // joined / derived
  workout_name?: string | null
  workout_date?: string | null
  user_name?: string | null
  user_email?: string | null
  red_flag_counts?: { info: number; warn: number; block: number }
  correction_count?: number
  split_family?: string | null
}

type Stats = {
  total: number
  last7d: number
  last24hCount: number
  completePct: number
  suspiciousPct: number
  lostSessionPct: number
}

const PAGE_SIZE = 50

const STATUS_OPTIONS = [
  { value: '', label: 'All statuses' },
  { value: 'complete', label: 'Complete' },
  { value: 'failed', label: 'Failed' },
  { value: 'skipped', label: 'Skipped' },
  { value: 'pending', label: 'Pending' },
  { value: 'analyzing', label: 'Analyzing' },
  { value: 'suspicious', label: 'Suspicious' },
  { value: 'lost_session', label: 'Lost session' },
]

export default function WorkoutIntelligencePage() {
  const router = useRouter()

  // filters (draft) + applied
  const [statusFilter, setStatusFilter] = useState('')
  const [userFilter, setUserFilter] = useState('')
  const [dateFrom, setDateFrom] = useState('')
  const [dateTo, setDateTo] = useState('')
  const [applied, setApplied] = useState({ status: '', user: '', dateFrom: '', dateTo: '' })

  const [page, setPage] = useState(0)
  const [rows, setRows] = useState<ReportRow[]>([])
  const [total, setTotal] = useState(0)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [expandedId, setExpandedId] = useState<string | null>(null)

  const [stats, setStats] = useState<Stats | null>(null)
  const [statsErr, setStatsErr] = useState<string | null>(null)

  const [backfilling, setBackfilling] = useState(false)
  const [backfillMsg, setBackfillMsg] = useState<string | null>(null)

  const isoFrom = applied.dateFrom ? `${applied.dateFrom}T00:00:00.000Z` : undefined
  const isoTo = applied.dateTo ? `${applied.dateTo}T23:59:59.999Z` : undefined

  const loadStats = useCallback(async () => {
    try {
      const data = await adminApi('get_workout_intel_stats')
      setStats(data as Stats)
    } catch (e) {
      setStatsErr(e instanceof Error ? e.message : 'Failed to load stats')
    }
  }, [])

  const loadRows = useCallback(async () => {
    setLoading(true)
    setError(null)
    try {
      const data = await adminApi('list_workout_intel_reports', {
        page,
        limit: PAGE_SIZE,
        status: applied.status || undefined,
        userId: applied.user.trim() || undefined,
        dateFrom: isoFrom,
        dateTo: isoTo,
      })
      setRows((data.rows as ReportRow[]) || [])
      setTotal(typeof data.total === 'number' ? data.total : 0)
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Failed to load reports')
      setRows([])
      setTotal(0)
    } finally {
      setLoading(false)
    }
  }, [applied, page, isoFrom, isoTo])

  useEffect(() => { void loadStats() }, [loadStats])
  useEffect(() => { void loadRows() }, [loadRows])

  function applyFilters() {
    setApplied({ status: statusFilter, user: userFilter, dateFrom, dateTo })
    setPage(0)
  }
  function resetFilters() {
    setStatusFilter(''); setUserFilter(''); setDateFrom(''); setDateTo('')
    setApplied({ status: '', user: '', dateFrom: '', dateTo: '' })
    setPage(0)
  }

  // Manual backfill — re-enqueues completed workouts that the iOS app
  // never enqueued (TestFlight builds < 1.38(64), Migration #156). Honors
  // the User filter input — leave blank to backfill across all users.
  // The cron drains the resulting `pending` rows within 10 minutes.
  async function runBackfill() {
    const scope = userFilter.trim()
      ? `user "${userFilter.trim()}"`
      : 'all users'
    if (!confirm(
      `Backfill missing workout-intel rows for ${scope}?\n\n`
      + 'Up to 200 most-recent completed workouts will be enqueued. '
      + 'The cron will analyze them within 10 minutes.\n\n'
      + 'Idempotent — safe to run repeatedly.',
    )) return

    setBackfilling(true)
    setBackfillMsg(null)
    try {
      const res = await adminApi('backfill_workout_intel', {
        userId: userFilter.trim() || undefined,
        limit: 200,
      })
      const m = res as {
        scanned?: number; scored?: number; enqueued?: number;
        skipped?: number; errors?: number; message?: string;
        errorSamples?: string[];
      }
      const parts = [
        `${m.enqueued ?? 0} enqueued`,
        `${m.scored ?? 0} newly scored`,
        `${m.skipped ?? 0} skipped (low quality)`,
      ]
      if ((m.errors ?? 0) > 0) parts.push(`${m.errors} error${m.errors === 1 ? '' : 's'}`)
      setBackfillMsg(`${m.message || 'Done.'} (${parts.join(' · ')})`)
      // Give the user a moment to see the message, then refresh the table
      // so any new `pending` rows show up. Stats refresh too so the
      // "Total reports" tile bumps.
      await Promise.all([loadRows(), loadStats()])
    } catch (e) {
      setBackfillMsg(e instanceof Error ? e.message : 'Backfill failed')
    } finally {
      setBackfilling(false)
    }
  }

  const canPrev = page > 0
  const canNext = (page + 1) * PAGE_SIZE < total

  return (
    <AdminShell>
      <div className="p-6 max-w-7xl mx-auto">
        {/* Header */}
        <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4 mb-6">
          <div>
            <h1 className="text-2xl font-bold" style={{ color: 'var(--text-primary)' }}>
              Workout Intelligence
            </h1>
            <p className="text-sm mt-1" style={{ color: 'var(--text-secondary)' }}>
              Claude-generated post-workout analysis (one row per quality workout)
            </p>
          </div>
          <div className="flex flex-col items-end gap-2">
            <button
              className="btn btn-ghost text-sm"
              disabled={backfilling}
              onClick={() => void runBackfill()}
              title="Re-enqueue completed workouts that pre-date build 1.38(64) or were finished on an older TestFlight."
            >
              {backfilling ? 'Backfilling…' : 'Backfill missing workouts'}
            </button>
            {backfillMsg && (
              <p className="text-xs max-w-[420px] text-right" style={{ color: 'var(--text-muted)' }}>
                {backfillMsg}
              </p>
            )}
          </div>
        </div>

        {/* Stats */}
        {statsErr && (
          <div className="card mb-4" style={{ color: 'var(--danger)' }}>{statsErr}</div>
        )}
        <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-6 gap-3 mb-6">
          <StatCard label="Total reports" value={stats ? stats.total.toLocaleString() : '—'} accent="var(--accent)" />
          <StatCard label="Last 7d" value={stats ? stats.last7d.toLocaleString() : '—'} accent="var(--info)" />
          <StatCard label="Last 24h" value={stats ? stats.last24hCount.toLocaleString() : '—'} accent="var(--info)" />
          <StatCard label="% Complete (7d)" value={stats ? `${stats.completePct.toFixed(0)}%` : '—'} accent="var(--success)" />
          <StatCard label="% Suspicious (7d)" value={stats ? `${stats.suspiciousPct.toFixed(0)}%` : '—'} accent="var(--danger)" />
          <StatCard label="% Lost Session (7d)" value={stats ? `${stats.lostSessionPct.toFixed(0)}%` : '—'} accent="var(--warning)" />
        </div>

        {/* Filters */}
        <div className="card mb-4">
          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-5 gap-3 items-end">
            <div>
              <label className="text-xs font-semibold mb-1 block" style={{ color: 'var(--text-muted)' }}>Status</label>
              <select value={statusFilter} onChange={e => setStatusFilter(e.target.value)} style={{ fontSize: 13 }}>
                {STATUS_OPTIONS.map(o => <option key={o.value} value={o.value}>{o.label}</option>)}
              </select>
            </div>
            <div>
              <label className="text-xs font-semibold mb-1 block" style={{ color: 'var(--text-muted)' }}>User (id or email)</label>
              <input type="text" value={userFilter} onChange={e => setUserFilter(e.target.value)} placeholder="uuid or email…" style={{ fontSize: 13 }} />
            </div>
            <div>
              <label className="text-xs font-semibold mb-1 block" style={{ color: 'var(--text-muted)' }}>From</label>
              <input type="date" value={dateFrom} onChange={e => setDateFrom(e.target.value)} style={{ fontSize: 13 }} />
            </div>
            <div>
              <label className="text-xs font-semibold mb-1 block" style={{ color: 'var(--text-muted)' }}>To</label>
              <input type="date" value={dateTo} onChange={e => setDateTo(e.target.value)} style={{ fontSize: 13 }} />
            </div>
            <div className="flex gap-2">
              <button className="btn btn-primary text-sm" onClick={applyFilters}>Apply</button>
              <button className="btn btn-ghost text-sm" onClick={resetFilters}>Reset</button>
            </div>
          </div>
        </div>

        {/* Table */}
        <div className="card" style={{ padding: 0, overflow: 'hidden' }}>
          {error && (
            <div className="px-4 py-3 text-sm" style={{ color: 'var(--danger)' }}>{error}</div>
          )}
          {loading && rows.length === 0 ? (
            <div className="flex justify-center py-16">
              <div className="spinner" style={{ width: 32, height: 32 }} />
            </div>
          ) : rows.length === 0 ? (
            <div className="px-6 py-12 text-center text-sm" style={{ color: 'var(--text-muted)' }}>
              No reports match the current filters.
            </div>
          ) : (
            <div className="overflow-x-auto">
              <table>
                <thead>
                  <tr>
                    <th>When</th>
                    <th>User</th>
                    <th>Workout</th>
                    <th>Quality</th>
                    <th>Status</th>
                    <th>Split</th>
                    <th>Red flags</th>
                    <th>Corrections</th>
                    <th></th>
                  </tr>
                </thead>
                <tbody>
                  {rows.map(r => {
                    const isOpen = expandedId === r.id
                    return (
                      <Fragment key={r.id}>
                        <tr style={{ cursor: 'pointer' }} onClick={() => setExpandedId(isOpen ? null : r.id)}>
                          <td className="align-top text-sm" style={{ color: 'var(--text-secondary)' }}>
                            <div>{timeAgo(r.enqueued_at)}</div>
                            <div className="text-xs mt-0.5" style={{ color: 'var(--text-muted)' }}>
                              {new Date(r.enqueued_at).toLocaleDateString()}
                            </div>
                          </td>
                          <td className="align-top text-sm break-all max-w-[200px]" style={{ color: 'var(--text-secondary)' }}>
                            <div>{r.user_name || r.user_email || '—'}</div>
                            <div className="text-xs font-mono mt-0.5" style={{ color: 'var(--text-muted)' }}>
                              {r.user_id?.slice(0, 8) || ''}
                            </div>
                          </td>
                          <td className="align-top text-sm max-w-[260px]" style={{ color: 'var(--text-primary)' }}>
                            {r.workout_name || '—'}
                          </td>
                          <td className="align-top">
                            <div className="flex items-center gap-2">
                              <span className="text-sm font-semibold" style={{ color: 'var(--text-primary)' }}>
                                {r.quality_score ?? '—'}
                              </span>
                              {r.quality_band && (
                                <span className={qualityBandBadgeClass(r.quality_band)}>{r.quality_band}</span>
                              )}
                            </div>
                          </td>
                          <td className="align-top">
                            <div className="flex items-center gap-2">
                              <span className={statusBadgeClass(r.status)}>
                                {r.status === 'analyzing' && (
                                  <span
                                    aria-hidden
                                    style={{
                                      display: 'inline-block', width: 8, height: 8, marginRight: 4,
                                      borderRadius: '50%', border: '2px solid currentColor',
                                      borderTopColor: 'transparent', animation: 'spin 0.6s linear infinite',
                                    }}
                                  />
                                )}
                                {r.status}
                              </span>
                              {r.is_suspicious && <span className="badge badge-danger">suspicious</span>}
                              {r.is_lost_session && <span className="badge badge-warning">lost</span>}
                            </div>
                          </td>
                          <td className="align-top text-sm" style={{ color: 'var(--text-secondary)' }}>
                            {r.split_family || '—'}
                          </td>
                          <td className="align-top">
                            {r.red_flag_counts ? (
                              <div className="flex gap-1">
                                {r.red_flag_counts.block > 0 && <span className="badge badge-danger">{r.red_flag_counts.block}</span>}
                                {r.red_flag_counts.warn > 0 && <span className="badge badge-warning">{r.red_flag_counts.warn}</span>}
                                {r.red_flag_counts.info > 0 && <span className="badge badge-neutral">{r.red_flag_counts.info}</span>}
                                {(!r.red_flag_counts.block && !r.red_flag_counts.warn && !r.red_flag_counts.info) && (
                                  <span className="text-xs" style={{ color: 'var(--text-muted)' }}>—</span>
                                )}
                              </div>
                            ) : <span className="text-xs" style={{ color: 'var(--text-muted)' }}>—</span>}
                          </td>
                          <td className="align-top text-sm" style={{ color: 'var(--text-secondary)' }}>
                            {r.correction_count ?? 0}
                          </td>
                          <td className="align-top">
                            <button
                              className="btn btn-ghost text-xs"
                              onClick={(e) => { e.stopPropagation(); router.push(`/workout-intelligence/${r.id}`) }}
                            >
                              View →
                            </button>
                          </td>
                        </tr>
                        {isOpen && (
                          <tr style={{ background: 'var(--bg-secondary)' }}>
                            <td colSpan={9} className="px-4 py-4">
                              {r.error_message && (
                                <div
                                  className="text-xs mb-2 p-2 rounded"
                                  style={{ background: 'rgba(239,68,68,0.08)', color: 'var(--danger)' }}
                                >
                                  Error: {r.error_message}
                                </div>
                              )}
                              <pre
                                className="text-xs p-3 rounded-lg overflow-x-auto whitespace-pre-wrap"
                                style={{
                                  background: 'var(--bg-tertiary)',
                                  border: '1px solid var(--border)',
                                  color: 'var(--text-primary)',
                                  maxHeight: 360,
                                  overflowY: 'auto',
                                }}
                              >
                                {r.summary_md || '(no summary)'}
                              </pre>
                              <div className="mt-2">
                                <button
                                  className="btn btn-primary text-xs"
                                  onClick={() => router.push(`/workout-intelligence/${r.id}`)}
                                >
                                  Full Report →
                                </button>
                              </div>
                            </td>
                          </tr>
                        )}
                      </Fragment>
                    )
                  })}
                </tbody>
              </table>
            </div>
          )}
        </div>

        {/* Pagination */}
        <div className="flex flex-wrap items-center justify-between gap-4 mt-6">
          <p className="text-sm" style={{ color: 'var(--text-muted)' }}>
            Showing {rows.length ? page * PAGE_SIZE + 1 : 0}–{page * PAGE_SIZE + rows.length} of {total}
          </p>
          <div className="flex gap-2">
            <button className="btn btn-ghost text-sm" disabled={!canPrev || loading} onClick={() => setPage(p => Math.max(0, p - 1))}>← Prev</button>
            <button className="btn btn-ghost text-sm" disabled={!canNext || loading} onClick={() => setPage(p => p + 1)}>Next →</button>
          </div>
        </div>
      </div>
    </AdminShell>
  )
}

function StatCard({ label, value, accent }: { label: string; value: string; accent: string }) {
  return (
    <div className="card" style={{ padding: 14 }}>
      <div className="text-xs font-medium uppercase tracking-wide" style={{ color: 'var(--text-muted)' }}>{label}</div>
      <div className="text-2xl font-bold mt-1" style={{ color: accent }}>{value}</div>
    </div>
  )
}
