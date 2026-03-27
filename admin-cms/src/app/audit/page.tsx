'use client'

import { Fragment, useCallback, useEffect, useMemo, useState } from 'react'
import AdminShell from '@/components/AdminShell'
import { adminApi } from '@/lib/api'

// Mirrors admin API route.ts tier classification for badge colors
const WRITE_ACTIONS = new Set([
  'update_user',
  'delete_user',
  'update_bug_report',
  'delete_bug_report',
  'update_crash_report',
  'delete_crash_report',
  'create_faq_entry',
  'update_faq_entry',
  'delete_faq_entry',
  'publish_faq_entry',
  'create_faq_category',
  'update_faq_category',
  'delete_faq_category',
  'update_exercise',
  'delete_exercise',
  'create_feature_flag',
  'update_feature_flag',
  'delete_feature_flag',
  'update_report_status',
  'suspend_user',
  'lift_suspension',
  'create_push_campaign',
  'update_push_campaign',
])
const BULK_ACTIONS = new Set([
  'bulk_update_bug_reports',
  'bulk_update_crash_reports',
  'bulk_publish_faq_entries',
  'send_push_campaign',
])

function getActionTier(action: string): 'write' | 'bulk' | 'read' {
  if (BULK_ACTIONS.has(action)) return 'bulk'
  if (WRITE_ACTIONS.has(action)) return 'write'
  return 'read'
}

function actionBadgeClass(action: string): string {
  const tier = getActionTier(action)
  if (tier === 'bulk') return 'badge badge-danger'
  if (tier === 'write') return 'badge badge-warning'
  return 'badge badge-info'
}

export function timeAgo(iso: string): string {
  const t = new Date(iso).getTime()
  if (Number.isNaN(t)) return '—'
  const diff = Date.now() - t
  if (diff < 0) return 'just now'
  const sec = Math.floor(diff / 1000)
  if (sec < 60) return sec <= 5 ? 'just now' : `${sec}s ago`
  const minutes = Math.floor(sec / 60)
  if (minutes < 60) return `${minutes}m ago`
  const hours = Math.floor(minutes / 60)
  if (hours < 24) return `${hours}h ago`
  const days = Math.floor(hours / 24)
  if (days < 30) return `${days}d ago`
  const months = Math.floor(days / 30)
  if (months < 12) return `${months}mo ago`
  return `${Math.floor(days / 365)}y ago`
}

function formatTimestamp(iso: string): string {
  try {
    return new Date(iso).toLocaleString(undefined, {
      year: 'numeric',
      month: 'short',
      day: 'numeric',
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit',
    })
  } catch {
    return iso
  }
}

interface AuditLogRow {
  id: string
  admin_user_id: string
  admin_email: string | null
  action: string
  target_id: string | null
  ip_address: string | null
  details: Record<string, unknown> | null
  created_at: string
}

interface AuditStats {
  total_actions_30d: number
  action_counts: Record<string, number>
  admin_counts: Record<string, number>
  daily_counts: Record<string, number>
}

function escapeCsvCell(value: string): string {
  if (/[",\n\r]/.test(value)) return `"${value.replace(/"/g, '""')}"`
  return value
}

function buildCsv(rows: Array<Record<string, string>>): string {
  if (rows.length === 0) return ''
  const headers = Object.keys(rows[0])
  const lines = [
    headers.join(','),
    ...rows.map((row) => headers.map((h) => escapeCsvCell(row[h] ?? '')).join(',')),
  ]
  return lines.join('\r\n')
}

function downloadTextFile(filename: string, text: string, mime: string) {
  const blob = new Blob([text], { type: mime })
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = filename
  a.click()
  URL.revokeObjectURL(url)
}

const PAGE_SIZE = 50

export default function AuditPage() {
  const [tab, setTab] = useState<'timeline' | 'stats'>('timeline')

  const [dateFrom, setDateFrom] = useState('')
  const [dateTo, setDateTo] = useState('')
  const [actionFilter, setActionFilter] = useState('')
  const [adminEmailFilter, setAdminEmailFilter] = useState('')
  const [targetIdFilter, setTargetIdFilter] = useState('')

  const [applied, setApplied] = useState({
    dateFrom: '',
    dateTo: '',
    action: '',
    adminEmail: '',
    targetId: '',
  })

  const [page, setPage] = useState(0)

  const [logs, setLogs] = useState<AuditLogRow[]>([])
  const [total, setTotal] = useState(0)
  const [loading, setLoading] = useState(true)
  const [loadError, setLoadError] = useState<string | null>(null)
  const [expandedId, setExpandedId] = useState<string | null>(null)

  const [stats, setStats] = useState<AuditStats | null>(null)
  const [statsLoading, setStatsLoading] = useState(false)
  const [statsError, setStatsError] = useState<string | null>(null)
  const [actionOptions, setActionOptions] = useState<string[]>([])

  const isoDateFrom = applied.dateFrom ? `${applied.dateFrom}T00:00:00.000Z` : undefined
  const isoDateTo = applied.dateTo ? `${applied.dateTo}T23:59:59.999Z` : undefined

  const loadLogs = useCallback(async () => {
    setLoading(true)
    setLoadError(null)
    try {
      const data = await adminApi('get_audit_logs', {
        admin_email: applied.adminEmail.trim() || undefined,
        action: applied.action || undefined,
        target_id: applied.targetId.trim() || undefined,
        date_from: isoDateFrom,
        date_to: isoDateTo,
        page,
        limit: PAGE_SIZE,
      })
      setLogs((data.logs as AuditLogRow[]) || [])
      setTotal(typeof data.total === 'number' ? data.total : 0)
    } catch (e) {
      setLoadError(e instanceof Error ? e.message : 'Failed to load audit logs')
      setLogs([])
      setTotal(0)
    } finally {
      setLoading(false)
    }
  }, [applied, isoDateFrom, isoDateTo, page])

  useEffect(() => {
    if (tab !== 'timeline') return
    void loadLogs()
  }, [tab, applied, page, loadLogs])

  const loadStatsBundle = useCallback(async () => {
    setStatsLoading(true)
    setStatsError(null)
    try {
      const s = await adminApi('get_audit_stats')
      setStats(s as AuditStats)
      const keys = Object.keys((s as AuditStats).action_counts || {}).sort((a, b) =>
        a.localeCompare(b),
      )
      setActionOptions(keys)
    } catch (e) {
      setStatsError(e instanceof Error ? e.message : 'Failed to load stats')
      setStats(null)
    } finally {
      setStatsLoading(false)
    }
  }, [])

  useEffect(() => {
    void loadStatsBundle()
  }, [loadStatsBundle])

  const sortedActions = useMemo(() => {
    if (!stats) return []
    return Object.entries(stats.action_counts)
      .sort((a, b) => b[1] - a[1])
      .map(([name, count]) => ({ name, count }))
  }, [stats])

  const maxActionCount = useMemo(() => {
    if (!sortedActions.length) return 1
    return Math.max(...sortedActions.map((a) => a.count), 1)
  }, [sortedActions])

  const sortedAdmins = useMemo(() => {
    if (!stats) return []
    return Object.entries(stats.admin_counts)
      .sort((a, b) => b[1] - a[1])
      .map(([email, count]) => ({ email, count }))
  }, [stats])

  const maxAdminCount = useMemo(() => {
    if (!sortedAdmins.length) return 1
    return Math.max(...sortedAdmins.map((a) => a.count), 1)
  }, [sortedAdmins])

  const sortedDays = useMemo(() => {
    if (!stats) return []
    return Object.keys(stats.daily_counts)
      .sort()
      .map((day) => ({ day, count: stats.daily_counts[day] || 0 }))
  }, [stats])

  const maxDaily = useMemo(() => {
    if (!sortedDays.length) return 1
    return Math.max(...sortedDays.map((d) => d.count), 1)
  }, [sortedDays])

  const totalPages = Math.max(1, Math.ceil(total / PAGE_SIZE))
  const canPrev = page > 0
  const canNext = (page + 1) * PAGE_SIZE < total

  function applyFilters() {
    setApplied({
      dateFrom,
      dateTo,
      action: actionFilter,
      adminEmail: adminEmailFilter,
      targetId: targetIdFilter,
    })
    setPage(0)
  }

  function resetFilters() {
    setDateFrom('')
    setDateTo('')
    setActionFilter('')
    setAdminEmailFilter('')
    setTargetIdFilter('')
    setApplied({
      dateFrom: '',
      dateTo: '',
      action: '',
      adminEmail: '',
      targetId: '',
    })
    setPage(0)
  }

  async function handleExportCsv() {
    try {
      const exportFrom = applied.dateFrom ? `${applied.dateFrom}T00:00:00.000Z` : undefined
      const exportTo = applied.dateTo ? `${applied.dateTo}T23:59:59.999Z` : undefined
      const { rows } = await adminApi('export_audit_logs', {
        date_from: exportFrom,
        date_to: exportTo,
      })
      const raw = (rows || []) as Array<{
        timestamp: string
        admin_email: string
        action: string
        target_id: string
        ip_address: string
        details: string
      }>
      let filtered = raw
      if (applied.action) filtered = filtered.filter((r) => r.action === applied.action)
      if (applied.adminEmail.trim()) {
        const q = applied.adminEmail.trim().toLowerCase()
        filtered = filtered.filter((r) => r.admin_email?.toLowerCase().includes(q))
      }
      if (applied.targetId.trim()) {
        const q = applied.targetId.trim()
        filtered = filtered.filter((r) => (r.target_id || '').includes(q))
      }
      const csvRows = filtered.map((r) => ({
        timestamp: r.timestamp,
        admin_email: r.admin_email,
        action: r.action,
        target_id: r.target_id,
        ip_address: r.ip_address,
        details: r.details,
      }))
      const csv = buildCsv(csvRows)
      const stamp = new Date().toISOString().slice(0, 19).replace(/[:T]/g, '-')
      downloadTextFile(`audit-export-${stamp}.csv`, csv, 'text/csv;charset=utf-8')
    } catch (e) {
      alert(e instanceof Error ? e.message : 'Export failed')
    }
  }

  return (
    <AdminShell>
      <div className="p-6 max-w-7xl mx-auto">
        <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4 mb-8">
          <div>
            <h1 className="text-2xl font-bold" style={{ color: 'var(--text-primary)' }}>
              Audit Log
            </h1>
            <p className="text-sm mt-1" style={{ color: 'var(--text-secondary)' }}>
              Admin actions, IP addresses, and change details
            </p>
          </div>
          <div className="flex gap-2 flex-wrap">
            <button
              type="button"
              className="btn btn-ghost text-sm"
              onClick={() => {
                void loadStatsBundle()
                if (tab === 'timeline') void loadLogs()
              }}
              aria-label="Refresh audit data"
            >
              ↻ Refresh
            </button>
          </div>
        </div>

        {/* Tabs */}
        <div
          className="flex gap-1 p-1 rounded-lg mb-6 w-fit"
          style={{ background: 'var(--bg-tertiary)', border: '1px solid var(--border)' }}
        >
          <button
            type="button"
            className={`btn text-sm px-4 py-2 rounded-md ${tab === 'timeline' ? 'btn-primary' : 'btn-ghost'}`}
            onClick={() => setTab('timeline')}
            aria-pressed={tab === 'timeline'}
            aria-label="Timeline tab"
          >
            Timeline
          </button>
          <button
            type="button"
            className={`btn text-sm px-4 py-2 rounded-md ${tab === 'stats' ? 'btn-primary' : 'btn-ghost'}`}
            onClick={() => setTab('stats')}
            aria-pressed={tab === 'stats'}
            aria-label="Statistics tab"
          >
            Stats
          </button>
        </div>

        {tab === 'timeline' && (
          <>
            <div className="card mb-6">
              <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 xl:grid-cols-6 gap-4">
                <label className="flex flex-col gap-1 text-xs" style={{ color: 'var(--text-muted)' }}>
                  From
                  <input
                    type="date"
                    className="rounded-md px-3 py-2 text-sm border"
                    style={{
                      background: 'var(--bg-secondary)',
                      borderColor: 'var(--border)',
                      color: 'var(--text-primary)',
                    }}
                    value={dateFrom}
                    onChange={(e) => setDateFrom(e.target.value)}
                    aria-label="Filter from date"
                  />
                </label>
                <label className="flex flex-col gap-1 text-xs" style={{ color: 'var(--text-muted)' }}>
                  To
                  <input
                    type="date"
                    className="rounded-md px-3 py-2 text-sm border"
                    style={{
                      background: 'var(--bg-secondary)',
                      borderColor: 'var(--border)',
                      color: 'var(--text-primary)',
                    }}
                    value={dateTo}
                    onChange={(e) => setDateTo(e.target.value)}
                    aria-label="Filter to date"
                  />
                </label>
                <label className="flex flex-col gap-1 text-xs" style={{ color: 'var(--text-muted)' }}>
                  Action
                  <select
                    className="rounded-md px-3 py-2 text-sm border"
                    style={{
                      background: 'var(--bg-secondary)',
                      borderColor: 'var(--border)',
                      color: 'var(--text-primary)',
                    }}
                    value={actionFilter}
                    onChange={(e) => setActionFilter(e.target.value)}
                    aria-label="Filter by action type"
                  >
                    <option value="">All actions</option>
                    {actionOptions.map((a) => (
                      <option key={a} value={a}>
                        {a}
                      </option>
                    ))}
                  </select>
                </label>
                <label className="flex flex-col gap-1 text-xs" style={{ color: 'var(--text-muted)' }}>
                  Admin email
                  <input
                    type="search"
                    placeholder="Contains…"
                    className="rounded-md px-3 py-2 text-sm border"
                    style={{
                      background: 'var(--bg-secondary)',
                      borderColor: 'var(--border)',
                      color: 'var(--text-primary)',
                    }}
                    value={adminEmailFilter}
                    onChange={(e) => setAdminEmailFilter(e.target.value)}
                    aria-label="Filter by admin email"
                  />
                </label>
                <label className="flex flex-col gap-1 text-xs md:col-span-2" style={{ color: 'var(--text-muted)' }}>
                  Target ID
                  <input
                    type="search"
                    placeholder="Search target…"
                    className="rounded-md px-3 py-2 text-sm border"
                    style={{
                      background: 'var(--bg-secondary)',
                      borderColor: 'var(--border)',
                      color: 'var(--text-primary)',
                    }}
                    value={targetIdFilter}
                    onChange={(e) => setTargetIdFilter(e.target.value)}
                    aria-label="Filter by target id"
                  />
                </label>
              </div>
              <div className="flex flex-wrap gap-2 mt-4">
                <button type="button" className="btn btn-primary text-sm" onClick={applyFilters}>
                  Apply filters
                </button>
                <button type="button" className="btn btn-ghost text-sm" onClick={resetFilters}>
                  Clear
                </button>
                <button
                  type="button"
                  className="btn btn-ghost text-sm"
                  onClick={() => void handleExportCsv()}
                  aria-label="Export filtered audit log to CSV"
                >
                  Export CSV
                </button>
              </div>
            </div>

            {loadError && (
              <div
                className="mb-4 px-4 py-3 rounded-lg text-sm"
                style={{ background: 'var(--bg-tertiary)', color: 'var(--danger)', border: '1px solid var(--border)' }}
              >
                {loadError}
              </div>
            )}

            <div className="card overflow-hidden p-0">
              {loading ? (
                <div className="flex justify-center py-20">
                  <div className="spinner" style={{ width: 32, height: 32 }} />
                </div>
              ) : (
                <div className="overflow-x-auto">
                  <table className="w-full">
                    <thead>
                      <tr style={{ borderBottom: '1px solid var(--border)' }}>
                        <th className="text-left px-4 py-3 text-xs font-semibold" style={{ color: 'var(--text-muted)' }}>
                          Timestamp
                        </th>
                        <th className="text-left px-4 py-3 text-xs font-semibold" style={{ color: 'var(--text-muted)' }}>
                          Admin
                        </th>
                        <th className="text-left px-4 py-3 text-xs font-semibold" style={{ color: 'var(--text-muted)' }}>
                          Action
                        </th>
                        <th className="text-left px-4 py-3 text-xs font-semibold" style={{ color: 'var(--text-muted)' }}>
                          Target
                        </th>
                        <th className="text-left px-4 py-3 text-xs font-semibold" style={{ color: 'var(--text-muted)' }}>
                          IP
                        </th>
                      </tr>
                    </thead>
                    <tbody>
                      {logs.length === 0 ? (
                        <tr>
                          <td colSpan={5} className="px-4 py-12 text-center text-sm" style={{ color: 'var(--text-muted)' }}>
                            No audit entries match your filters.
                          </td>
                        </tr>
                      ) : (
                        logs.map((log) => {
                          const open = expandedId === log.id
                          return (
                            <Fragment key={log.id}>
                              <tr
                                className="cursor-pointer transition-colors"
                                style={{
                                  borderBottom: '1px solid var(--border)',
                                  background: open ? 'var(--bg-hover)' : 'transparent',
                                }}
                                onClick={() => setExpandedId(open ? null : log.id)}
                                onKeyDown={(e) => {
                                  if (e.key === 'Enter' || e.key === ' ') {
                                    e.preventDefault()
                                    setExpandedId(open ? null : log.id)
                                  }
                                }}
                                tabIndex={0}
                                role="button"
                                aria-expanded={open}
                                aria-label={`Audit entry ${log.action} at ${formatTimestamp(log.created_at)}. ${open ? 'Collapse' : 'Expand'} details.`}
                              >
                                <td className="px-4 py-3 align-top text-sm" style={{ color: 'var(--text-primary)' }}>
                                  <div className="font-medium">{formatTimestamp(log.created_at)}</div>
                                  <div className="text-xs mt-0.5" style={{ color: 'var(--text-muted)' }}>
                                    {timeAgo(log.created_at)}
                                  </div>
                                </td>
                                <td className="px-4 py-3 align-top text-sm break-all max-w-[200px]" style={{ color: 'var(--text-secondary)' }}>
                                  {log.admin_email || '—'}
                                </td>
                                <td className="px-4 py-3 align-top">
                                  <span className={actionBadgeClass(log.action)}>{log.action}</span>
                                </td>
                                <td className="px-4 py-3 align-top text-sm font-mono break-all max-w-[220px]" style={{ color: 'var(--text-secondary)' }}>
                                  {log.target_id || '—'}
                                </td>
                                <td className="px-4 py-3 align-top text-sm font-mono" style={{ color: 'var(--text-muted)' }}>
                                  {log.ip_address || '—'}
                                </td>
                              </tr>
                              {open && (
                                <tr style={{ background: 'var(--bg-secondary)' }}>
                                  <td colSpan={5} className="px-4 py-4">
                                    <div className="text-xs font-semibold mb-2" style={{ color: 'var(--text-muted)' }}>
                                      Details (JSON)
                                    </div>
                                    <pre
                                      className="text-xs p-4 rounded-lg overflow-x-auto max-h-80 overflow-y-auto border"
                                      style={{
                                        background: 'var(--bg-tertiary)',
                                        borderColor: 'var(--border)',
                                        color: 'var(--text-primary)',
                                      }}
                                    >
                                      {JSON.stringify(log.details ?? {}, null, 2)}
                                    </pre>
                                  </td>
                                </tr>
                              )}
                            </Fragment>
                          )
                        })
                      )}
                    </tbody>
                  </table>
                </div>
              )}
            </div>

            <div className="flex flex-wrap items-center justify-between gap-4 mt-6">
              <p className="text-sm" style={{ color: 'var(--text-muted)' }}>
                Showing {logs.length ? page * PAGE_SIZE + 1 : 0}–{page * PAGE_SIZE + logs.length} of {total}
              </p>
              <div className="flex gap-2">
                <button
                  type="button"
                  className="btn btn-ghost text-sm"
                  disabled={!canPrev || loading}
                  onClick={() => setPage((p) => Math.max(0, p - 1))}
                  aria-label="Previous page"
                >
                  ← Prev
                </button>
                <button
                  type="button"
                  className="btn btn-ghost text-sm"
                  disabled={!canNext || loading}
                  onClick={() => setPage((p) => p + 1)}
                  aria-label="Next page"
                >
                  Next →
                </button>
              </div>
            </div>
          </>
        )}

        {tab === 'stats' && (
          <div className="space-y-6">
            {statsError && (
              <div
                className="px-4 py-3 rounded-lg text-sm"
                style={{ background: 'var(--bg-tertiary)', color: 'var(--danger)', border: '1px solid var(--border)' }}
              >
                {statsError}
              </div>
            )}

            {statsLoading && !stats ? (
              <div className="flex justify-center py-20">
                <div className="spinner" style={{ width: 32, height: 32 }} />
              </div>
            ) : stats ? (
              <>
                <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
                  <div className="card">
                    <div className="text-xs font-medium uppercase tracking-wide" style={{ color: 'var(--text-muted)' }}>
                      Last 30 days
                    </div>
                    <div className="text-3xl font-bold mt-2" style={{ color: 'var(--accent)' }}>
                      {stats.total_actions_30d.toLocaleString()}
                    </div>
                    <div className="text-sm mt-1" style={{ color: 'var(--text-secondary)' }}>
                      Total admin actions recorded
                    </div>
                  </div>
                </div>

                <div className="card">
                  <h2 className="text-lg font-semibold mb-4" style={{ color: 'var(--text-primary)' }}>
                    Actions by type
                  </h2>
                  <div className="space-y-3">
                    {sortedActions.length === 0 ? (
                      <p className="text-sm" style={{ color: 'var(--text-muted)' }}>
                        No actions in the last 30 days.
                      </p>
                    ) : (
                      sortedActions.map(({ name, count }) => (
                        <div key={name}>
                          <div className="flex justify-between text-xs mb-1" style={{ color: 'var(--text-secondary)' }}>
                            <span className="font-mono truncate pr-2">{name}</span>
                            <span className="shrink-0">{count}</span>
                          </div>
                          <div
                            className="h-2 rounded-full overflow-hidden"
                            style={{ background: 'var(--bg-tertiary)' }}
                          >
                            <div
                              className="h-full rounded-full transition-all"
                              style={{
                                width: `${(count / maxActionCount) * 100}%`,
                                background: 'var(--info)',
                              }}
                            />
                          </div>
                        </div>
                      ))
                    )}
                  </div>
                </div>

                <div className="card">
                  <h2 className="text-lg font-semibold mb-4" style={{ color: 'var(--text-primary)' }}>
                    Actions by admin
                  </h2>
                  <div className="space-y-3">
                    {sortedAdmins.length === 0 ? (
                      <p className="text-sm" style={{ color: 'var(--text-muted)' }}>
                        No admin email metadata for this period.
                      </p>
                    ) : (
                      sortedAdmins.map(({ email, count }) => (
                        <div key={email}>
                          <div className="flex justify-between text-xs mb-1" style={{ color: 'var(--text-secondary)' }}>
                            <span className="truncate pr-2">{email}</span>
                            <span className="shrink-0">{count}</span>
                          </div>
                          <div
                            className="h-2 rounded-full overflow-hidden"
                            style={{ background: 'var(--bg-tertiary)' }}
                          >
                            <div
                              className="h-full rounded-full"
                              style={{
                                width: `${(count / maxAdminCount) * 100}%`,
                                background: 'var(--success)',
                              }}
                            />
                          </div>
                        </div>
                      ))
                    )}
                  </div>
                </div>

                <div className="card">
                  <h2 className="text-lg font-semibold mb-4" style={{ color: 'var(--text-primary)' }}>
                    Daily activity (30d window)
                  </h2>
                  {sortedDays.length === 0 ? (
                    <p className="text-sm" style={{ color: 'var(--text-muted)' }}>
                      No daily buckets yet.
                    </p>
                  ) : (
                    <div className="flex gap-1 h-44 pt-2" style={{ color: 'var(--text-muted)' }}>
                      {sortedDays.map(({ day, count }) => {
                        const barPx = Math.max(4, Math.round((count / maxDaily) * 120))
                        return (
                          <div
                            key={day}
                            className="flex-1 flex flex-col items-center justify-end gap-1 min-w-0 h-full"
                            title={`${day}: ${count}`}
                          >
                            <div
                              className="w-full rounded-t transition-all"
                              style={{
                                height: barPx,
                                background: 'var(--warning)',
                                opacity: 0.85,
                              }}
                            />
                            <span className="text-[10px] font-mono truncate w-full text-center" style={{ color: 'var(--text-muted)' }}>
                              {day.slice(5)}
                            </span>
                          </div>
                        )
                      })}
                    </div>
                  )}
                </div>
              </>
            ) : null}
          </div>
        )}
      </div>
    </AdminShell>
  )
}
