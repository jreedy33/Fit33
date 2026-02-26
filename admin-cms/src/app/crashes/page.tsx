'use client'

import { useState, useEffect, useCallback, useRef } from 'react'
import AdminShell from '@/components/AdminShell'
import { adminApi } from '@/lib/api'

// ═══════════════════════════════════════════════════
// Types
// ═══════════════════════════════════════════════════

interface CrashReport {
  id: string
  user_id: string | null
  user_email: string | null
  user_name: string | null
  report_type: string
  severity: string
  error_message: string
  error_domain: string | null
  error_code: string | null
  stack_trace: string | null
  fingerprint: string
  breadcrumbs: Array<{ action: string; screen: string; timestamp: string }> | null
  device_model: string | null
  os_version: string | null
  app_version: string | null
  build_number: string | null
  current_screen: string | null
  memory_usage_mb: number | null
  free_memory_mb: number | null
  battery_level: number | null
  is_low_power_mode: boolean
  network_type: string | null
  session_id: string | null
  session_duration_seconds: number | null
  actions_before_crash: number | null
  additional_context: Record<string, string> | null
  session_log_snippet: string | null
  status: string
  admin_notes: string | null
  resolved_at: string | null
  resolved_by: string | null
  occurred_at: string
  uploaded_at: string
  created_at: string
}

interface BugReport {
  id: string
  user_id: string | null
  user_name: string | null
  user_email: string | null
  description: string
  expected_behavior: string | null
  reproduces_every_time: boolean
  screenshot_base64: string | null
  device_model: string | null
  os_version: string | null
  app_version: string | null
  screen_name: string | null
  additional_info: string | null
  session_log: string | null
  status: string
  created_at: string
}

interface TopIssue {
  fingerprint: string
  count: number
  message: string
  severity: string
  domain: string
  latest: string
  status: string
}

interface Overview {
  total_crash_reports: number
  total_bug_reports: number
  affected_users: number
  status_counts: Record<string, number>
  severity_counts: Record<string, number>
  type_counts: Record<string, number>
  domain_counts: Record<string, number>
  version_counts: Record<string, number>
  top_issues: TopIssue[]
  daily_trend: Array<{ date: string; count: number }>
  recent_reports: CrashReport[]
  bug_reports: BugReport[]
}

// Auto-refresh intervals
const REFRESH_INTERVALS: { label: string; ms: number }[] = [
  { label: 'Off', ms: 0 },
  { label: '30s', ms: 30000 },
  { label: '1m', ms: 60000 },
  { label: '5m', ms: 300000 },
]

// ═══════════════════════════════════════════════════
// Helpers
// ═══════════════════════════════════════════════════

const SEVERITY_COLORS: Record<string, string> = {
  fatal: '#ef4444',
  critical: '#f97316',
  high: '#eab308',
  medium: '#3b82f6',
  low: '#6b7280',
}

const STATUS_COLORS: Record<string, string> = {
  new: '#ef4444',
  investigating: '#f97316',
  identified: '#eab308',
  resolved: '#22c55e',
  wont_fix: '#6b7280',
  duplicate: '#8b5cf6',
}

const TYPE_ICONS: Record<string, string> = {
  fatal_signal: '💀',
  crash: '💥',
  critical: '🔥',
  error: '❌',
  warning: '⚠️',
}

function timeAgo(dateStr: string): string {
  const now = new Date()
  const date = new Date(dateStr)
  const seconds = Math.floor((now.getTime() - date.getTime()) / 1000)
  if (seconds < 60) return `${seconds}s ago`
  const minutes = Math.floor(seconds / 60)
  if (minutes < 60) return `${minutes}m ago`
  const hours = Math.floor(minutes / 60)
  if (hours < 24) return `${hours}h ago`
  const days = Math.floor(hours / 24)
  if (days < 30) return `${days}d ago`
  return date.toLocaleDateString()
}

function formatDuration(seconds: number | null): string {
  if (!seconds) return '—'
  if (seconds < 60) return `${seconds}s`
  const mins = Math.floor(seconds / 60)
  const secs = seconds % 60
  return `${mins}m ${secs}s`
}

// ═══════════════════════════════════════════════════
// Main Component
// ═══════════════════════════════════════════════════

export default function CrashesPage() {
  const [activeTab, setActiveTab] = useState<'overview' | 'crashes' | 'bugs'>('overview')
  const [overview, setOverview] = useState<Overview | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  // Crash list state
  const [crashReports, setCrashReports] = useState<CrashReport[]>([])
  const [crashFilter, setCrashFilter] = useState({
    status: '',
    severity: '',
    report_type: '',
    search: '',
  })
  const [crashLoading, setCrashLoading] = useState(false)

  // Bug report state
  const [bugReports, setBugReports] = useState<BugReport[]>([])

  // Detail view
  const [selectedCrash, setSelectedCrash] = useState<CrashReport | null>(null)
  const [selectedBug, setSelectedBug] = useState<BugReport | null>(null)

  // Selected crashes for bulk actions
  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set())

  // Auto-refresh
  const [refreshInterval, setRefreshInterval] = useState(0)
  const refreshTimerRef = useRef<ReturnType<typeof setInterval> | null>(null)
  const [lastRefreshed, setLastRefreshed] = useState<Date>(new Date())

  // Confirm dialog
  const [confirmDialog, setConfirmDialog] = useState<{
    message: string
    onConfirm: () => void
  } | null>(null)

  // ─── Data Loading ─────────────────────────────────────────

  const loadOverview = useCallback(async () => {
    try {
      setLoading(true)
      const data = await adminApi('get_crash_overview')
      setOverview(data)
      setBugReports(data.bug_reports || [])
      setError(null)
      setLastRefreshed(new Date())
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load overview')
    } finally {
      setLoading(false)
    }
  }, [])

  const loadCrashes = useCallback(async () => {
    try {
      setCrashLoading(true)
      const params: Record<string, unknown> = { limit: 200 }
      if (crashFilter.status) params.status = crashFilter.status
      if (crashFilter.severity) params.severity = crashFilter.severity
      if (crashFilter.report_type) params.report_type = crashFilter.report_type
      if (crashFilter.search) params.search = crashFilter.search
      const data = await adminApi('get_crash_reports', params)
      setCrashReports(data.crash_reports || [])
      setLastRefreshed(new Date())
    } catch (err) {
      console.error('Failed to load crashes:', err)
    } finally {
      setCrashLoading(false)
    }
  }, [crashFilter])

  const loadBugs = useCallback(async () => {
    try {
      const data = await adminApi('get_bug_reports', { limit: 200 })
      setBugReports(data.bug_reports || [])
    } catch (err) {
      console.error('Failed to load bug reports:', err)
    }
  }, [])

  useEffect(() => {
    loadOverview()
  }, [loadOverview])

  useEffect(() => {
    if (activeTab === 'crashes') loadCrashes()
    if (activeTab === 'bugs') loadBugs()
  }, [activeTab, loadCrashes, loadBugs])

  // Auto-refresh timer
  useEffect(() => {
    if (refreshTimerRef.current) clearInterval(refreshTimerRef.current)
    if (refreshInterval > 0) {
      refreshTimerRef.current = setInterval(() => {
        if (activeTab === 'overview') loadOverview()
        else if (activeTab === 'crashes') loadCrashes()
        else if (activeTab === 'bugs') loadBugs()
      }, refreshInterval)
    }
    return () => {
      if (refreshTimerRef.current) clearInterval(refreshTimerRef.current)
    }
  }, [refreshInterval, activeTab, loadOverview, loadCrashes, loadBugs])

  // ─── Actions ─────────────────────────────────────────

  const updateCrashStatus = async (id: string, status: string) => {
    try {
      await adminApi('update_crash_report', { id, status })
      if (activeTab === 'overview') await loadOverview()
      else await loadCrashes()
      if (selectedCrash?.id === id) {
        setSelectedCrash(prev => prev ? { ...prev, status } : null)
      }
    } catch (err) {
      console.error('Failed to update crash status:', err)
    }
  }

  const updateCrashNotes = async (id: string, notes: string) => {
    try {
      await adminApi('update_crash_report', { id, admin_notes: notes })
    } catch (err) {
      console.error('Failed to update notes:', err)
    }
  }

  const bulkUpdateStatus = async (status: string) => {
    if (selectedIds.size === 0) return
    try {
      await adminApi('bulk_update_crash_reports', { ids: Array.from(selectedIds), status })
      setSelectedIds(new Set())
      await loadCrashes()
    } catch (err) {
      console.error('Failed to bulk update:', err)
    }
  }

  const deleteCrashReport = async (id: string) => {
    try {
      await adminApi('delete_crash_report', { id })
      if (selectedCrash?.id === id) setSelectedCrash(null)
      if (activeTab === 'overview') await loadOverview()
      else await loadCrashes()
    } catch (err) {
      console.error('Failed to delete crash report:', err)
    }
  }

  const bulkDeleteCrashes = async () => {
    if (selectedIds.size === 0) return
    try {
      await adminApi('bulk_delete_crash_reports', { ids: Array.from(selectedIds) })
      setSelectedIds(new Set())
      await loadCrashes()
    } catch (err) {
      console.error('Failed to bulk delete:', err)
    }
  }

  const deleteResolvedCrashes = async () => {
    try {
      await adminApi('delete_resolved_crash_reports')
      await loadOverview()
      if (activeTab === 'crashes') await loadCrashes()
    } catch (err) {
      console.error('Failed to delete resolved:', err)
    }
  }

  const deleteBugReport = async (id: string) => {
    try {
      await adminApi('delete_bug_report', { id })
      if (selectedBug?.id === id) setSelectedBug(null)
      await loadBugs()
      if (activeTab === 'overview') await loadOverview()
    } catch (err) {
      console.error('Failed to delete bug report:', err)
    }
  }

  const updateBugStatus = async (id: string, status: string) => {
    try {
      await adminApi('update_bug_report', { id, status })
      await loadBugs()
      if (selectedBug?.id === id) {
        setSelectedBug(prev => prev ? { ...prev, status } : null)
      }
    } catch (err) {
      console.error('Failed to update bug status:', err)
    }
  }

  const loadCrashDetail = async (id: string) => {
    try {
      const data = await adminApi('get_crash_report_detail', { id })
      setSelectedCrash(data.crash_report)
    } catch (err) {
      console.error('Failed to load crash detail:', err)
    }
  }

  // ─── CSV Export ─────────────────────────────────────────

  const exportCrashesCSV = () => {
    const source = activeTab === 'crashes' ? crashReports : (overview?.recent_reports || [])
    if (source.length === 0) return

    const headers = ['ID', 'Type', 'Severity', 'Status', 'Error Message', 'Domain', 'User Email', 'Device', 'App Version', 'OS', 'Screen', 'Created At']
    const rows = source.map(r => [
      r.id,
      r.report_type,
      r.severity,
      r.status,
      `"${(r.error_message || '').replace(/"/g, '""')}"`,
      r.error_domain || '',
      r.user_email || '',
      r.device_model || '',
      r.app_version || '',
      r.os_version || '',
      r.current_screen || '',
      r.created_at,
    ])

    const csv = [headers.join(','), ...rows.map(r => r.join(','))].join('\n')
    const blob = new Blob([csv], { type: 'text/csv' })
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url
    a.download = `crash-reports-${new Date().toISOString().slice(0, 10)}.csv`
    a.click()
    URL.revokeObjectURL(url)
  }

  // ─── Render ─────────────────────────────────────────

  if (selectedCrash) {
    return (
      <AdminShell>
        <CrashDetailView
          crash={selectedCrash}
          onBack={() => setSelectedCrash(null)}
          onUpdateStatus={(status) => updateCrashStatus(selectedCrash.id, status)}
          onUpdateNotes={(notes) => updateCrashNotes(selectedCrash.id, notes)}
          onDelete={() => {
            setConfirmDialog({
              message: 'Delete this crash report? This cannot be undone.',
              onConfirm: () => { deleteCrashReport(selectedCrash.id); setConfirmDialog(null) }
            })
          }}
        />
      </AdminShell>
    )
  }

  if (selectedBug) {
    return (
      <AdminShell>
        <BugDetailView
          bug={selectedBug}
          onBack={() => setSelectedBug(null)}
          onUpdateStatus={(status) => updateBugStatus(selectedBug.id, status)}
          onDelete={() => {
            setConfirmDialog({
              message: 'Delete this bug report? This cannot be undone.',
              onConfirm: () => { deleteBugReport(selectedBug.id); setConfirmDialog(null) }
            })
          }}
        />
      </AdminShell>
    )
  }

  return (
    <AdminShell>
      <div style={{ padding: 32, maxWidth: 1400, margin: '0 auto' }}>
        {/* Confirm Dialog */}
        {confirmDialog && (
          <div className="fixed inset-0 z-50 flex items-center justify-center" style={{ background: 'rgba(0,0,0,0.5)' }}>
            <div className="rounded-xl p-6 max-w-sm w-full mx-4" style={{ background: 'var(--bg-secondary)', border: '1px solid var(--border)' }}>
              <p className="text-sm mb-4" style={{ color: 'var(--text-primary)' }}>{confirmDialog.message}</p>
              <div className="flex gap-2 justify-end">
                <button
                  onClick={() => setConfirmDialog(null)}
                  className="text-sm px-4 py-2 rounded-lg"
                  style={{ background: 'var(--bg-primary)', border: '1px solid var(--border)', color: 'var(--text-secondary)' }}
                >
                  Cancel
                </button>
                <button
                  onClick={confirmDialog.onConfirm}
                  className="text-sm px-4 py-2 rounded-lg"
                  style={{ background: '#ef4444', color: 'white' }}
                >
                  Delete
                </button>
              </div>
            </div>
          </div>
        )}

        {/* Header */}
        <div className="flex items-center justify-between mb-6">
          <div>
            <h1 className="text-2xl font-bold" style={{ color: 'var(--text-primary)' }}>
              🛡️ Crashes & Bug Reports
            </h1>
            <p className="text-sm mt-1" style={{ color: 'var(--text-muted)' }}>
              Real-time error monitoring, crash detection, and user-reported bugs
              {refreshInterval > 0 && (
                <span className="ml-2 inline-flex items-center gap-1">
                  <span className="inline-block w-1.5 h-1.5 rounded-full animate-pulse" style={{ background: '#22c55e' }} />
                  Auto-refreshing
                </span>
              )}
            </p>
          </div>
          <div className="flex items-center gap-2">
            {/* Auto-refresh dropdown */}
            <select
              value={refreshInterval}
              onChange={e => setRefreshInterval(Number(e.target.value))}
              className="text-xs rounded-lg px-2 py-2"
              style={{ background: 'var(--bg-secondary)', border: '1px solid var(--border)', color: 'var(--text-primary)' }}
              title="Auto-refresh interval"
            >
              {REFRESH_INTERVALS.map(opt => (
                <option key={opt.ms} value={opt.ms}>🔄 {opt.label}</option>
              ))}
            </select>
            {/* Export CSV */}
            <button
              onClick={exportCrashesCSV}
              className="text-sm px-3 py-2 rounded-lg"
              style={{ background: 'var(--bg-secondary)', border: '1px solid var(--border)', color: 'var(--text-secondary)' }}
              title="Export crash reports to CSV"
            >
              📥 Export
            </button>
            {/* Clean up resolved */}
            {overview && (overview.status_counts['resolved'] || 0) + (overview.status_counts['wont_fix'] || 0) + (overview.status_counts['duplicate'] || 0) > 0 && (
              <button
                onClick={() => setConfirmDialog({
                  message: `Delete all resolved/won't fix/duplicate crash reports? This cannot be undone.`,
                  onConfirm: () => { deleteResolvedCrashes(); setConfirmDialog(null) }
                })}
                className="text-sm px-3 py-2 rounded-lg"
                style={{ background: 'var(--bg-secondary)', border: '1px solid var(--border)', color: 'var(--text-muted)' }}
                title="Delete all resolved crash reports"
              >
                🗑️ Clean Up
              </button>
            )}
            <button
              onClick={() => { loadOverview(); if (activeTab === 'crashes') loadCrashes(); if (activeTab === 'bugs') loadBugs() }}
              className="text-sm px-4 py-2 rounded-lg"
              style={{ background: 'var(--accent)', color: 'white' }}
            >
              ↻ Refresh
            </button>
          </div>
        </div>

        {/* Last refreshed indicator */}
        <div className="text-xs mb-4" style={{ color: 'var(--text-muted)' }}>
          Last refreshed: {lastRefreshed.toLocaleTimeString()}
        </div>

        {/* Tabs */}
        <div className="flex gap-1 mb-6 p-1 rounded-lg" style={{ background: 'var(--bg-secondary)', display: 'inline-flex' }}>
          {(['overview', 'crashes', 'bugs'] as const).map(tab => (
            <button
              key={tab}
              onClick={() => setActiveTab(tab)}
              className="px-4 py-2 rounded-md text-sm font-medium transition-all"
              style={{
                background: activeTab === tab ? 'var(--accent)' : 'transparent',
                color: activeTab === tab ? 'white' : 'var(--text-secondary)',
              }}
            >
              {tab === 'overview' ? '📊 Overview' : tab === 'crashes' ? '💥 Crash Reports' : '🐛 Bug Reports'}
            </button>
          ))}
        </div>

        {loading && activeTab === 'overview' ? (
          <div className="text-center py-20" style={{ color: 'var(--text-muted)' }}>Loading...</div>
        ) : error ? (
          <div className="text-center py-20" style={{ color: '#ef4444' }}>{error}</div>
        ) : activeTab === 'overview' && overview ? (
          <OverviewTab
            overview={overview}
            onViewCrash={(id) => loadCrashDetail(id)}
            onViewBug={(bug) => setSelectedBug(bug)}
            onViewFingerprint={(fp) => {
              setCrashFilter(prev => ({ ...prev, search: '' }))
              setActiveTab('crashes')
              // Set fingerprint filter after switching tab
              setTimeout(() => {
                setCrashFilter(prev => ({ ...prev, search: fp }))
              }, 100)
            }}
          />
        ) : activeTab === 'crashes' ? (
          <CrashListTab
            crashes={crashReports}
            loading={crashLoading}
            filter={crashFilter}
            onFilterChange={setCrashFilter}
            onViewCrash={(id) => loadCrashDetail(id)}
            selectedIds={selectedIds}
            onToggleSelect={(id) => {
              setSelectedIds(prev => {
                const next = new Set(prev)
                if (next.has(id)) next.delete(id)
                else next.add(id)
                return next
              })
            }}
            onSelectAll={(ids) => setSelectedIds(new Set(ids))}
            onClearSelection={() => setSelectedIds(new Set())}
            onBulkUpdate={bulkUpdateStatus}
            onBulkDelete={() => setConfirmDialog({
              message: `Delete ${selectedIds.size} selected crash reports? This cannot be undone.`,
              onConfirm: () => { bulkDeleteCrashes(); setConfirmDialog(null) }
            })}
          />
        ) : activeTab === 'bugs' ? (
          <BugListTab
            bugs={bugReports}
            onViewBug={(bug) => setSelectedBug(bug)}
            onUpdateStatus={updateBugStatus}
            onDelete={(id) => setConfirmDialog({
              message: 'Delete this bug report? This cannot be undone.',
              onConfirm: () => { deleteBugReport(id); setConfirmDialog(null) }
            })}
          />
        ) : null}
      </div>
    </AdminShell>
  )
}

// ═══════════════════════════════════════════════════
// Overview Tab
// ═══════════════════════════════════════════════════

function OverviewTab({ overview, onViewCrash, onViewBug, onViewFingerprint }: {
  overview: Overview
  onViewCrash: (id: string) => void
  onViewBug: (bug: BugReport) => void
  onViewFingerprint: (fp: string) => void
}) {
  const hasData = overview.total_crash_reports > 0 || overview.total_bug_reports > 0

  // Compute crash-free rate (last 7 days)
  const last7Days = overview.daily_trend.slice(-7)
  const daysWithCrashes = last7Days.filter(d => d.count > 0).length
  const crashFreeRate = last7Days.length > 0 ? Math.round(((last7Days.length - daysWithCrashes) / last7Days.length) * 100) : 100

  // Compute MTTR (Mean Time To Resolution) from resolved reports
  const resolvedCount = overview.status_counts['resolved'] || 0

  // Unique crash types (fingerprints)
  const uniqueIssues = overview.top_issues.length

  // Open (unresolved) count
  const unresolvedCount = (overview.status_counts['new'] || 0) + (overview.status_counts['investigating'] || 0) + (overview.status_counts['identified'] || 0)

  // Crashes in last 24h
  const today = overview.daily_trend.length > 0 ? overview.daily_trend[overview.daily_trend.length - 1]?.count || 0 : 0

  return (
    <div className="space-y-6">
      {/* Stat Cards - Primary */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
        <StatCard
          label="Crash Reports"
          value={overview.total_crash_reports}
          icon="💥"
          color="#ef4444"
        />
        <StatCard
          label="Bug Reports"
          value={overview.total_bug_reports}
          icon="🐛"
          color="#f97316"
        />
        <StatCard
          label="Affected Users"
          value={overview.affected_users}
          icon="👥"
          color="#eab308"
        />
        <StatCard
          label="Unresolved"
          value={unresolvedCount}
          icon="🔴"
          color="#ef4444"
        />
      </div>

      {/* Stat Cards - Secondary (health metrics) */}
      {hasData && (
        <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
          <StatCard
            label="Crash-Free Days (7d)"
            value={crashFreeRate}
            icon="🟢"
            color="#22c55e"
            suffix="%"
          />
          <StatCard
            label="Today"
            value={today}
            icon="📅"
            color={today > 0 ? '#ef4444' : '#22c55e'}
          />
          <StatCard
            label="Unique Issues"
            value={uniqueIssues}
            icon="🔍"
            color="#8b5cf6"
          />
          <StatCard
            label="Resolved"
            value={resolvedCount}
            icon="✅"
            color="#22c55e"
          />
        </div>
      )}

      {!hasData ? (
        <div className="rounded-xl p-12 text-center" style={{ background: 'var(--bg-secondary)', border: '1px solid var(--border)' }}>
          <div className="text-4xl mb-4">🎉</div>
          <h3 className="text-lg font-semibold mb-2" style={{ color: 'var(--text-primary)' }}>No Issues Detected</h3>
          <p className="text-sm" style={{ color: 'var(--text-muted)' }}>
            Crash reports will appear here automatically when the iOS app&apos;s CrashReportingService detects errors.
            <br />
            User-submitted bug reports from the rage shake reporter will also appear here.
          </p>
        </div>
      ) : (
        <>
          {/* Severity + Status Breakdown */}
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div className="rounded-xl p-5" style={{ background: 'var(--bg-secondary)', border: '1px solid var(--border)' }}>
              <h3 className="text-sm font-semibold mb-3" style={{ color: 'var(--text-primary)' }}>Severity Breakdown</h3>
              <div className="space-y-2">
                {Object.entries(overview.severity_counts).sort((a, b) => {
                  const order = ['fatal', 'critical', 'high', 'medium', 'low']
                  return order.indexOf(a[0]) - order.indexOf(b[0])
                }).map(([severity, count]) => (
                  <div key={severity} className="flex items-center justify-between">
                    <div className="flex items-center gap-2">
                      <div className="w-2.5 h-2.5 rounded-full" style={{ background: SEVERITY_COLORS[severity] || '#6b7280' }} />
                      <span className="text-sm capitalize" style={{ color: 'var(--text-secondary)' }}>{severity}</span>
                    </div>
                    <span className="text-sm font-medium" style={{ color: 'var(--text-primary)' }}>{count}</span>
                  </div>
                ))}
              </div>
            </div>

            <div className="rounded-xl p-5" style={{ background: 'var(--bg-secondary)', border: '1px solid var(--border)' }}>
              <h3 className="text-sm font-semibold mb-3" style={{ color: 'var(--text-primary)' }}>Status Breakdown</h3>
              <div className="space-y-2">
                {Object.entries(overview.status_counts).map(([status, count]) => (
                  <div key={status} className="flex items-center justify-between">
                    <div className="flex items-center gap-2">
                      <div className="w-2.5 h-2.5 rounded-full" style={{ background: STATUS_COLORS[status] || '#6b7280' }} />
                      <span className="text-sm capitalize" style={{ color: 'var(--text-secondary)' }}>{status.replace('_', ' ')}</span>
                    </div>
                    <span className="text-sm font-medium" style={{ color: 'var(--text-primary)' }}>{count}</span>
                  </div>
                ))}
              </div>
            </div>
          </div>

          {/* Error Domain + App Version Breakdown */}
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            {Object.keys(overview.domain_counts).length > 0 && (
              <div className="rounded-xl p-5" style={{ background: 'var(--bg-secondary)', border: '1px solid var(--border)' }}>
                <h3 className="text-sm font-semibold mb-3" style={{ color: 'var(--text-primary)' }}>Errors by Domain</h3>
                <div className="space-y-2">
                  {Object.entries(overview.domain_counts).sort((a, b) => b[1] - a[1]).map(([domain, count]) => (
                    <div key={domain} className="flex items-center justify-between">
                      <span className="text-sm" style={{ color: 'var(--text-secondary)' }}>{domain}</span>
                      <span className="text-sm font-medium" style={{ color: 'var(--text-primary)' }}>{count}</span>
                    </div>
                  ))}
                </div>
              </div>
            )}

            {Object.keys(overview.version_counts).length > 0 && (
              <div className="rounded-xl p-5" style={{ background: 'var(--bg-secondary)', border: '1px solid var(--border)' }}>
                <h3 className="text-sm font-semibold mb-3" style={{ color: 'var(--text-primary)' }}>Errors by App Version</h3>
                <div className="space-y-2">
                  {Object.entries(overview.version_counts).sort((a, b) => b[1] - a[1]).map(([version, count]) => (
                    <div key={version} className="flex items-center justify-between">
                      <span className="text-sm font-mono" style={{ color: 'var(--text-secondary)' }}>v{version}</span>
                      <span className="text-sm font-medium" style={{ color: 'var(--text-primary)' }}>{count}</span>
                    </div>
                  ))}
                </div>
              </div>
            )}
          </div>

          {/* Daily Trend (simple bar viz) */}
          {overview.daily_trend.some(d => d.count > 0) && (
            <div className="rounded-xl p-5" style={{ background: 'var(--bg-secondary)', border: '1px solid var(--border)' }}>
              <h3 className="text-sm font-semibold mb-3" style={{ color: 'var(--text-primary)' }}>Crash Trend (Last 30 Days)</h3>
              <div className="flex items-end gap-px" style={{ height: 80 }}>
                {overview.daily_trend.map((d, i) => {
                  const max = Math.max(...overview.daily_trend.map(x => x.count), 1)
                  const height = (d.count / max) * 100
                  return (
                    <div
                      key={i}
                      className="flex-1 rounded-t relative group"
                      style={{
                        height: `${Math.max(height, d.count > 0 ? 4 : 0)}%`,
                        background: d.count > 0 ? '#ef4444' : 'var(--border)',
                        minWidth: 2,
                      }}
                      title={`${d.date}: ${d.count} reports`}
                    />
                  )
                })}
              </div>
              <div className="flex justify-between mt-1">
                <span className="text-xs" style={{ color: 'var(--text-muted)' }}>30 days ago</span>
                <span className="text-xs" style={{ color: 'var(--text-muted)' }}>Today</span>
              </div>
            </div>
          )}

          {/* Top Issues (grouped by fingerprint) */}
          {overview.top_issues.length > 0 && (
            <div className="rounded-xl p-5" style={{ background: 'var(--bg-secondary)', border: '1px solid var(--border)' }}>
              <h3 className="text-sm font-semibold mb-3" style={{ color: 'var(--text-primary)' }}>
                🔥 Top Issues (Grouped by Error Fingerprint)
              </h3>
              <div className="space-y-2">
                {overview.top_issues.map((issue) => (
                  <button
                    key={issue.fingerprint}
                    className="w-full text-left flex items-center gap-3 p-3 rounded-lg hover:opacity-80 transition-opacity"
                    style={{ background: 'var(--bg-primary)', border: '1px solid var(--border)' }}
                    onClick={() => onViewFingerprint(issue.fingerprint)}
                  >
                    <div className="flex items-center gap-2 shrink-0">
                      <div className="w-2.5 h-2.5 rounded-full" style={{ background: SEVERITY_COLORS[issue.severity] || '#6b7280' }} />
                      <span className="text-sm font-bold" style={{ color: 'var(--text-primary)' }}>×{issue.count}</span>
                    </div>
                    <div className="flex-1 min-w-0">
                      <div className="text-sm truncate" style={{ color: 'var(--text-primary)' }}>{issue.message}</div>
                      <div className="text-xs" style={{ color: 'var(--text-muted)' }}>
                        {issue.domain} · {timeAgo(issue.latest)}
                      </div>
                    </div>
                    <span
                      className="text-xs px-2 py-0.5 rounded-full shrink-0"
                      style={{ background: STATUS_COLORS[issue.status] + '22', color: STATUS_COLORS[issue.status] }}
                    >
                      {issue.status}
                    </span>
                  </button>
                ))}
              </div>
            </div>
          )}

          {/* Recent Reports */}
          <div className="rounded-xl p-5" style={{ background: 'var(--bg-secondary)', border: '1px solid var(--border)' }}>
            <h3 className="text-sm font-semibold mb-3" style={{ color: 'var(--text-primary)' }}>
              ⚡ Recent Crash Reports
            </h3>
            {overview.recent_reports.length === 0 ? (
              <p className="text-sm text-center py-4" style={{ color: 'var(--text-muted)' }}>No crash reports yet</p>
            ) : (
              <div className="space-y-1">
                {overview.recent_reports.slice(0, 15).map(r => (
                  <CrashRow key={r.id} crash={r} onClick={() => onViewCrash(r.id)} />
                ))}
              </div>
            )}
          </div>

          {/* Recent Bug Reports */}
          <div className="rounded-xl p-5" style={{ background: 'var(--bg-secondary)', border: '1px solid var(--border)' }}>
            <h3 className="text-sm font-semibold mb-3" style={{ color: 'var(--text-primary)' }}>
              🐛 Recent Bug Reports (User-Submitted)
            </h3>
            {overview.bug_reports.length === 0 ? (
              <p className="text-sm text-center py-4" style={{ color: 'var(--text-muted)' }}>No bug reports yet</p>
            ) : (
              <div className="space-y-1">
                {overview.bug_reports.slice(0, 10).map(bug => (
                  <BugRow key={bug.id} bug={bug} onClick={() => onViewBug(bug)} />
                ))}
              </div>
            )}
          </div>
        </>
      )}
    </div>
  )
}

// ═══════════════════════════════════════════════════
// Crash List Tab
// ═══════════════════════════════════════════════════

function CrashListTab({
  crashes, loading, filter, onFilterChange, onViewCrash,
  selectedIds, onToggleSelect, onSelectAll, onClearSelection, onBulkUpdate, onBulkDelete
}: {
  crashes: CrashReport[]
  loading: boolean
  filter: { status: string; severity: string; report_type: string; search: string }
  onFilterChange: (filter: { status: string; severity: string; report_type: string; search: string }) => void
  onViewCrash: (id: string) => void
  selectedIds: Set<string>
  onToggleSelect: (id: string) => void
  onSelectAll: (ids: string[]) => void
  onClearSelection: () => void
  onBulkUpdate: (status: string) => void
  onBulkDelete: () => void
}) {
  return (
    <div className="space-y-4">
      {/* Filters */}
      <div className="flex flex-wrap items-center gap-3">
        <input
          type="text"
          placeholder="Search errors, users, domains..."
          value={filter.search}
          onChange={e => onFilterChange({ ...filter, search: e.target.value })}
          className="input text-sm flex-1"
          style={{ minWidth: 200, maxWidth: 400, background: 'var(--bg-secondary)', border: '1px solid var(--border)', borderRadius: 8, padding: '8px 12px', color: 'var(--text-primary)' }}
        />
        <select
          value={filter.status}
          onChange={e => onFilterChange({ ...filter, status: e.target.value })}
          className="text-sm rounded-lg px-3 py-2"
          style={{ background: 'var(--bg-secondary)', border: '1px solid var(--border)', color: 'var(--text-primary)' }}
        >
          <option value="">All Status</option>
          <option value="new">New</option>
          <option value="investigating">Investigating</option>
          <option value="identified">Identified</option>
          <option value="resolved">Resolved</option>
          <option value="wont_fix">Won&apos;t Fix</option>
          <option value="duplicate">Duplicate</option>
        </select>
        <select
          value={filter.severity}
          onChange={e => onFilterChange({ ...filter, severity: e.target.value })}
          className="text-sm rounded-lg px-3 py-2"
          style={{ background: 'var(--bg-secondary)', border: '1px solid var(--border)', color: 'var(--text-primary)' }}
        >
          <option value="">All Severity</option>
          <option value="fatal">Fatal</option>
          <option value="critical">Critical</option>
          <option value="high">High</option>
          <option value="medium">Medium</option>
          <option value="low">Low</option>
        </select>
        <select
          value={filter.report_type}
          onChange={e => onFilterChange({ ...filter, report_type: e.target.value })}
          className="text-sm rounded-lg px-3 py-2"
          style={{ background: 'var(--bg-secondary)', border: '1px solid var(--border)', color: 'var(--text-primary)' }}
        >
          <option value="">All Types</option>
          <option value="fatal_signal">Fatal Signal</option>
          <option value="crash">Crash</option>
          <option value="critical">Critical</option>
          <option value="error">Error</option>
          <option value="warning">Warning</option>
        </select>
      </div>

      {/* Bulk Actions */}
      {selectedIds.size > 0 && (
        <div className="flex items-center gap-3 p-3 rounded-lg" style={{ background: 'var(--accent)' + '15', border: '1px solid var(--accent)' + '33' }}>
          <span className="text-sm font-medium" style={{ color: 'var(--accent)' }}>
            {selectedIds.size} selected
          </span>
          <button onClick={() => onBulkUpdate('resolved')} className="text-xs px-3 py-1 rounded-md" style={{ background: '#22c55e22', color: '#22c55e' }}>
            Mark Resolved
          </button>
          <button onClick={() => onBulkUpdate('investigating')} className="text-xs px-3 py-1 rounded-md" style={{ background: '#f9731622', color: '#f97316' }}>
            Investigating
          </button>
          <button onClick={() => onBulkUpdate('duplicate')} className="text-xs px-3 py-1 rounded-md" style={{ background: '#8b5cf622', color: '#8b5cf6' }}>
            Duplicate
          </button>
          <button onClick={onBulkDelete} className="text-xs px-3 py-1 rounded-md" style={{ background: '#ef444422', color: '#ef4444' }}>
            🗑️ Delete
          </button>
          <button onClick={onClearSelection} className="text-xs ml-auto" style={{ color: 'var(--text-muted)' }}>
            Clear Selection
          </button>
        </div>
      )}

      {/* List */}
      {loading ? (
        <div className="text-center py-12" style={{ color: 'var(--text-muted)' }}>Loading crash reports...</div>
      ) : crashes.length === 0 ? (
        <div className="text-center py-12 rounded-xl" style={{ background: 'var(--bg-secondary)', border: '1px solid var(--border)', color: 'var(--text-muted)' }}>
          <div className="text-3xl mb-2">🎉</div>
          No crash reports found{filter.search || filter.status || filter.severity || filter.report_type ? ' matching filters' : ''}
        </div>
      ) : (
        <div className="space-y-1">
          <div className="flex items-center gap-2 px-3 pb-2">
            <input
              type="checkbox"
              checked={selectedIds.size === crashes.length && crashes.length > 0}
              onChange={() => {
                if (selectedIds.size === crashes.length) onClearSelection()
                else onSelectAll(crashes.map(c => c.id))
              }}
              className="rounded"
            />
            <span className="text-xs" style={{ color: 'var(--text-muted)' }}>
              {crashes.length} reports
            </span>
          </div>
          {crashes.map(crash => (
            <div key={crash.id} className="flex items-center gap-2">
              <input
                type="checkbox"
                checked={selectedIds.has(crash.id)}
                onChange={() => onToggleSelect(crash.id)}
                className="ml-3 rounded"
              />
              <div className="flex-1">
                <CrashRow crash={crash} onClick={() => onViewCrash(crash.id)} />
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  )
}

// ═══════════════════════════════════════════════════
// Bug List Tab
// ═══════════════════════════════════════════════════

function BugListTab({ bugs, onViewBug, onUpdateStatus, onDelete }: {
  bugs: BugReport[]
  onViewBug: (bug: BugReport) => void
  onUpdateStatus: (id: string, status: string) => void
  onDelete: (id: string) => void
}) {
  return (
    <div className="space-y-4">
      {bugs.length === 0 ? (
        <div className="text-center py-12 rounded-xl" style={{ background: 'var(--bg-secondary)', border: '1px solid var(--border)', color: 'var(--text-muted)' }}>
          <div className="text-3xl mb-2">🐛</div>
          No user-submitted bug reports yet
        </div>
      ) : (
        <div className="space-y-1">
          <div className="text-xs px-3 pb-2" style={{ color: 'var(--text-muted)' }}>
            {bugs.length} bug report{bugs.length !== 1 ? 's' : ''}
          </div>
          {bugs.map(bug => (
            <div key={bug.id} className="flex items-center gap-2">
              <div className="flex-1">
                <BugRow bug={bug} onClick={() => onViewBug(bug)} />
              </div>
              <select
                value={bug.status}
                onChange={e => onUpdateStatus(bug.id, e.target.value)}
                className="text-xs rounded-md px-2 py-1 shrink-0"
                style={{ background: 'var(--bg-primary)', border: '1px solid var(--border)', color: 'var(--text-primary)' }}
              >
                <option value="new">New</option>
                <option value="in_progress">In Progress</option>
                <option value="resolved">Resolved</option>
                <option value="closed">Closed</option>
              </select>
              <button
                onClick={() => onDelete(bug.id)}
                className="text-xs px-2 py-1 rounded-md shrink-0 hover:opacity-70"
                style={{ color: '#ef4444' }}
                title="Delete bug report"
              >
                🗑️
              </button>
            </div>
          ))}
        </div>
      )}
    </div>
  )
}

// ═══════════════════════════════════════════════════
// Row Components
// ═══════════════════════════════════════════════════

function CrashRow({ crash, onClick }: { crash: CrashReport; onClick: () => void }) {
  return (
    <button
      onClick={onClick}
      className="w-full text-left flex items-center gap-3 p-3 rounded-lg hover:opacity-80 transition-opacity"
      style={{ background: 'var(--bg-secondary)', border: '1px solid var(--border)' }}
    >
      <span className="text-lg shrink-0">{TYPE_ICONS[crash.report_type] || '❌'}</span>
      <div
        className="w-2.5 h-2.5 rounded-full shrink-0"
        style={{ background: SEVERITY_COLORS[crash.severity] || '#6b7280' }}
        title={crash.severity}
      />
      <div className="flex-1 min-w-0">
        <div className="text-sm truncate" style={{ color: 'var(--text-primary)' }}>
          {crash.error_message}
        </div>
        <div className="text-xs flex items-center gap-2 flex-wrap" style={{ color: 'var(--text-muted)' }}>
          {crash.error_domain && <span className="font-medium">{crash.error_domain}</span>}
          {crash.user_email && <span>· {crash.user_email}</span>}
          {crash.device_model && <span>· {crash.device_model}</span>}
          {crash.app_version && <span>· v{crash.app_version}</span>}
          <span>· {timeAgo(crash.created_at)}</span>
        </div>
      </div>
      <span
        className="text-xs px-2 py-0.5 rounded-full shrink-0"
        style={{ background: STATUS_COLORS[crash.status] + '22', color: STATUS_COLORS[crash.status] }}
      >
        {crash.status}
      </span>
    </button>
  )
}

function BugRow({ bug, onClick }: { bug: BugReport; onClick: () => void }) {
  return (
    <button
      onClick={onClick}
      className="w-full text-left flex items-center gap-3 p-3 rounded-lg hover:opacity-80 transition-opacity"
      style={{ background: 'var(--bg-secondary)', border: '1px solid var(--border)' }}
    >
      <span className="text-lg shrink-0">🐛</span>
      <div className="flex-1 min-w-0">
        <div className="text-sm truncate" style={{ color: 'var(--text-primary)' }}>
          {bug.description}
        </div>
        <div className="text-xs flex items-center gap-2" style={{ color: 'var(--text-muted)' }}>
          {bug.user_name && <span>{bug.user_name}</span>}
          {bug.user_email && <span>· {bug.user_email}</span>}
          {bug.device_model && <span>· {bug.device_model}</span>}
          {bug.app_version && <span>· v{bug.app_version}</span>}
          <span>· {timeAgo(bug.created_at)}</span>
          {bug.screenshot_base64 && <span>📸</span>}
          {bug.session_log && <span>📋</span>}
        </div>
      </div>
      <span
        className="text-xs px-2 py-0.5 rounded-full shrink-0"
        style={{ background: STATUS_COLORS[bug.status] + '22', color: STATUS_COLORS[bug.status] || '#6b7280' }}
      >
        {bug.status}
      </span>
    </button>
  )
}

// ═══════════════════════════════════════════════════
// Stat Card
// ═══════════════════════════════════════════════════

function StatCard({ label, value, icon, color, suffix }: { label: string; value: number; icon: string; color: string; suffix?: string }) {
  return (
    <div className="rounded-xl p-4" style={{ background: 'var(--bg-secondary)', border: '1px solid var(--border)' }}>
      <div className="flex items-center justify-between mb-2">
        <span className="text-lg">{icon}</span>
        <span className="text-2xl font-bold" style={{ color }}>{value}{suffix || ''}</span>
      </div>
      <span className="text-xs" style={{ color: 'var(--text-muted)' }}>{label}</span>
    </div>
  )
}

// ═══════════════════════════════════════════════════
// Crash Detail View
// ═══════════════════════════════════════════════════

function CrashDetailView({ crash, onBack, onUpdateStatus, onUpdateNotes, onDelete }: {
  crash: CrashReport
  onBack: () => void
  onUpdateStatus: (status: string) => void
  onUpdateNotes: (notes: string) => void
  onDelete: () => void
}) {
  const [notes, setNotes] = useState(crash.admin_notes || '')
  const [expandedSections, setExpandedSections] = useState<Set<string>>(new Set(['details', 'context']))

  const toggleSection = (section: string) => {
    setExpandedSections(prev => {
      const next = new Set(prev)
      if (next.has(section)) next.delete(section)
      else next.add(section)
      return next
    })
  }

  return (
    <div style={{ padding: 32, maxWidth: 1000, margin: '0 auto' }}>
      {/* Back + Header */}
      <div className="flex items-center justify-between mb-4">
        <button
          onClick={onBack}
          className="flex items-center gap-2 text-sm hover:opacity-70"
          style={{ color: 'var(--accent)' }}
        >
          ← Back to list
        </button>
        <button
          onClick={onDelete}
          className="flex items-center gap-1 text-xs px-3 py-1.5 rounded-lg hover:opacity-70"
          style={{ color: '#ef4444', background: '#ef444412', border: '1px solid #ef444433' }}
        >
          🗑️ Delete
        </button>
      </div>

      <div className="flex items-start justify-between mb-6">
        <div>
          <div className="flex items-center gap-3 mb-1">
            <span className="text-2xl">{TYPE_ICONS[crash.report_type] || '❌'}</span>
            <h1 className="text-xl font-bold" style={{ color: 'var(--text-primary)' }}>
              {crash.report_type === 'fatal_signal' ? 'Fatal Signal' : crash.report_type === 'crash' ? 'App Crash' : 'Error Report'}
            </h1>
            <span
              className="text-xs px-2.5 py-1 rounded-full font-medium"
              style={{ background: SEVERITY_COLORS[crash.severity] + '22', color: SEVERITY_COLORS[crash.severity] }}
            >
              {crash.severity}
            </span>
          </div>
          <p className="text-sm" style={{ color: 'var(--text-muted)' }}>
            {new Date(crash.occurred_at).toLocaleString()} · ID: {crash.id.slice(0, 8)}
          </p>
        </div>

        {/* Status Selector */}
        <select
          value={crash.status}
          onChange={e => onUpdateStatus(e.target.value)}
          className="text-sm rounded-lg px-3 py-2 font-medium"
          style={{ background: STATUS_COLORS[crash.status] + '22', color: STATUS_COLORS[crash.status], border: '1px solid ' + STATUS_COLORS[crash.status] + '44' }}
        >
          <option value="new">🔴 New</option>
          <option value="investigating">🟠 Investigating</option>
          <option value="identified">🟡 Identified</option>
          <option value="resolved">🟢 Resolved</option>
          <option value="wont_fix">⚪ Won&apos;t Fix</option>
          <option value="duplicate">🟣 Duplicate</option>
        </select>
      </div>

      {/* Error Message */}
      <div className="rounded-xl p-4 mb-4" style={{ background: '#ef444415', border: '1px solid #ef444433' }}>
        <pre className="text-sm whitespace-pre-wrap break-words" style={{ color: '#ef4444', fontFamily: 'ui-monospace, monospace' }}>
          {crash.error_message}
        </pre>
      </div>

      {/* Details Section */}
      <CollapsibleSection title="📋 Details" id="details" expanded={expandedSections} onToggle={toggleSection}>
        <div className="grid grid-cols-2 gap-3 text-sm">
          <Detail label="Report Type" value={crash.report_type} />
          <Detail label="Error Domain" value={crash.error_domain || '—'} />
          <Detail label="Error Code" value={crash.error_code || '—'} />
          <Detail label="Fingerprint" value={crash.fingerprint.slice(0, 16)} mono />
          <Detail label="Current Screen" value={crash.current_screen || '—'} />
          <Detail label="Session Duration" value={formatDuration(crash.session_duration_seconds)} />
          <Detail label="Actions Before Crash" value={crash.actions_before_crash?.toString() || '—'} />
          <Detail label="Occurred At" value={new Date(crash.occurred_at).toLocaleString()} />
        </div>
      </CollapsibleSection>

      {/* Device Context */}
      <CollapsibleSection title="📱 Device Context" id="context" expanded={expandedSections} onToggle={toggleSection}>
        <div className="grid grid-cols-2 gap-3 text-sm">
          <Detail label="Device" value={crash.device_model || '—'} />
          <Detail label="OS" value={crash.os_version || '—'} />
          <Detail label="App Version" value={crash.app_version ? `v${crash.app_version} (${crash.build_number || '?'})` : '—'} />
          <Detail label="Memory Usage" value={crash.memory_usage_mb ? `${crash.memory_usage_mb.toFixed(1)} MB` : '—'} />
          <Detail label="Free Memory" value={crash.free_memory_mb ? `${crash.free_memory_mb.toFixed(1)} MB` : '—'} />
          <Detail label="Battery" value={crash.battery_level != null ? `${Math.round(crash.battery_level * 100)}%` : '—'} />
          <Detail label="Low Power Mode" value={crash.is_low_power_mode ? 'Yes' : 'No'} />
          <Detail label="Network" value={crash.network_type || '—'} />
        </div>
      </CollapsibleSection>

      {/* User Context */}
      <CollapsibleSection title="👤 User Context" id="user" expanded={expandedSections} onToggle={toggleSection}>
        <div className="grid grid-cols-2 gap-3 text-sm">
          <Detail label="User ID" value={crash.user_id || '—'} mono />
          <Detail label="Name" value={crash.user_name || '—'} />
          <Detail label="Email" value={crash.user_email || '—'} />
        </div>
      </CollapsibleSection>

      {/* Breadcrumbs */}
      {crash.breadcrumbs && crash.breadcrumbs.length > 0 && (
        <CollapsibleSection title={`🍞 Breadcrumbs (${crash.breadcrumbs.length} actions)`} id="breadcrumbs" expanded={expandedSections} onToggle={toggleSection}>
          <div className="space-y-1 max-h-64 overflow-y-auto">
            {crash.breadcrumbs.map((crumb, i) => (
              <div key={i} className="flex items-center gap-2 text-xs py-1" style={{ borderBottom: '1px solid var(--border)' }}>
                <span style={{ color: 'var(--text-muted)', minWidth: 40, textAlign: 'right' }}>#{i + 1}</span>
                <span className="font-medium" style={{ color: 'var(--text-primary)' }}>{crumb.action}</span>
                {crumb.screen && <span style={{ color: 'var(--text-muted)' }}>@ {crumb.screen}</span>}
                <span className="ml-auto" style={{ color: 'var(--text-muted)' }}>
                  {new Date(crumb.timestamp).toLocaleTimeString()}
                </span>
              </div>
            ))}
          </div>
        </CollapsibleSection>
      )}

      {/* Stack Trace */}
      {crash.stack_trace && (
        <CollapsibleSection title="📚 Stack Trace" id="stack" expanded={expandedSections} onToggle={toggleSection}>
          <pre
            className="text-xs whitespace-pre-wrap break-all p-3 rounded-lg overflow-x-auto max-h-96 overflow-y-auto"
            style={{ background: 'var(--bg-primary)', border: '1px solid var(--border)', color: 'var(--text-secondary)', fontFamily: 'ui-monospace, monospace' }}
          >
            {crash.stack_trace}
          </pre>
        </CollapsibleSection>
      )}

      {/* Additional Context */}
      {crash.additional_context && Object.keys(crash.additional_context).length > 0 && (
        <CollapsibleSection title="🔍 Additional Context" id="additional" expanded={expandedSections} onToggle={toggleSection}>
          <div className="grid grid-cols-2 gap-3 text-sm">
            {Object.entries(crash.additional_context).map(([key, val]) => (
              <Detail key={key} label={key} value={val} />
            ))}
          </div>
        </CollapsibleSection>
      )}

      {/* Session Log Snippet */}
      {crash.session_log_snippet && (
        <CollapsibleSection title="📋 Session Log Snippet" id="sessionlog" expanded={expandedSections} onToggle={toggleSection}>
          <pre
            className="text-xs whitespace-pre-wrap break-all p-3 rounded-lg overflow-x-auto max-h-96 overflow-y-auto"
            style={{ background: 'var(--bg-primary)', border: '1px solid var(--border)', color: 'var(--text-secondary)', fontFamily: 'ui-monospace, monospace' }}
          >
            {crash.session_log_snippet}
          </pre>
        </CollapsibleSection>
      )}

      {/* Admin Notes */}
      <div className="rounded-xl p-4 mt-4" style={{ background: 'var(--bg-secondary)', border: '1px solid var(--border)' }}>
        <h3 className="text-sm font-semibold mb-2" style={{ color: 'var(--text-primary)' }}>📝 Admin Notes</h3>
        <textarea
          value={notes}
          onChange={e => setNotes(e.target.value)}
          placeholder="Add investigation notes, root cause, fix details..."
          className="w-full rounded-lg p-3 text-sm"
          style={{ background: 'var(--bg-primary)', border: '1px solid var(--border)', color: 'var(--text-primary)', minHeight: 100, resize: 'vertical' }}
        />
        <button
          onClick={() => onUpdateNotes(notes)}
          className="mt-2 text-sm px-4 py-2 rounded-lg"
          style={{ background: 'var(--accent)', color: 'white' }}
        >
          Save Notes
        </button>
      </div>
    </div>
  )
}

// ═══════════════════════════════════════════════════
// Bug Detail View
// ═══════════════════════════════════════════════════

function BugDetailView({ bug, onBack, onUpdateStatus, onDelete }: {
  bug: BugReport
  onBack: () => void
  onUpdateStatus: (status: string) => void
  onDelete: () => void
}) {
  return (
    <div style={{ padding: 32, maxWidth: 1000, margin: '0 auto' }}>
      <div className="flex items-center justify-between mb-4">
        <button
          onClick={onBack}
          className="flex items-center gap-2 text-sm hover:opacity-70"
          style={{ color: 'var(--accent)' }}
        >
          ← Back to list
        </button>
        <button
          onClick={onDelete}
          className="flex items-center gap-1 text-xs px-3 py-1.5 rounded-lg hover:opacity-70"
          style={{ color: '#ef4444', background: '#ef444412', border: '1px solid #ef444433' }}
        >
          🗑️ Delete
        </button>
      </div>

      <div className="flex items-start justify-between mb-6">
        <div>
          <h1 className="text-xl font-bold flex items-center gap-3" style={{ color: 'var(--text-primary)' }}>
            🐛 Bug Report
          </h1>
          <p className="text-sm mt-1" style={{ color: 'var(--text-muted)' }}>
            Submitted {new Date(bug.created_at).toLocaleString()} by {bug.user_name || bug.user_email || 'Anonymous'}
          </p>
        </div>
        <select
          value={bug.status}
          onChange={e => onUpdateStatus(e.target.value)}
          className="text-sm rounded-lg px-3 py-2 font-medium"
          style={{ background: STATUS_COLORS[bug.status] + '22', color: STATUS_COLORS[bug.status] || '#6b7280', border: '1px solid ' + (STATUS_COLORS[bug.status] || '#6b7280') + '44' }}
        >
          <option value="new">🔴 New</option>
          <option value="in_progress">🟠 In Progress</option>
          <option value="resolved">🟢 Resolved</option>
          <option value="closed">⚪ Closed</option>
        </select>
      </div>

      {/* Description */}
      <div className="rounded-xl p-4 mb-4" style={{ background: 'var(--bg-secondary)', border: '1px solid var(--border)' }}>
        <h3 className="text-sm font-semibold mb-2" style={{ color: 'var(--text-primary)' }}>Description</h3>
        <p className="text-sm whitespace-pre-wrap" style={{ color: 'var(--text-secondary)' }}>{bug.description}</p>
      </div>

      {bug.expected_behavior && (
        <div className="rounded-xl p-4 mb-4" style={{ background: 'var(--bg-secondary)', border: '1px solid var(--border)' }}>
          <h3 className="text-sm font-semibold mb-2" style={{ color: 'var(--text-primary)' }}>Expected Behavior</h3>
          <p className="text-sm whitespace-pre-wrap" style={{ color: 'var(--text-secondary)' }}>{bug.expected_behavior}</p>
        </div>
      )}

      {bug.additional_info && (
        <div className="rounded-xl p-4 mb-4" style={{ background: 'var(--bg-secondary)', border: '1px solid var(--border)' }}>
          <h3 className="text-sm font-semibold mb-2" style={{ color: 'var(--text-primary)' }}>Additional Info</h3>
          <p className="text-sm whitespace-pre-wrap" style={{ color: 'var(--text-secondary)' }}>{bug.additional_info}</p>
        </div>
      )}

      {/* Device + User Info */}
      <div className="grid grid-cols-2 gap-3 mb-4">
        <div className="rounded-xl p-4" style={{ background: 'var(--bg-secondary)', border: '1px solid var(--border)' }}>
          <h3 className="text-sm font-semibold mb-2" style={{ color: 'var(--text-primary)' }}>📱 Device Info</h3>
          <div className="space-y-1 text-sm">
            <Detail label="Device" value={bug.device_model || '—'} />
            <Detail label="OS" value={bug.os_version || '—'} />
            <Detail label="App Version" value={bug.app_version || '—'} />
            <Detail label="Screen" value={bug.screen_name || '—'} />
            <Detail label="Reproduces" value={bug.reproduces_every_time ? 'Every time' : 'Sometimes'} />
          </div>
        </div>
        <div className="rounded-xl p-4" style={{ background: 'var(--bg-secondary)', border: '1px solid var(--border)' }}>
          <h3 className="text-sm font-semibold mb-2" style={{ color: 'var(--text-primary)' }}>👤 User</h3>
          <div className="space-y-1 text-sm">
            <Detail label="Name" value={bug.user_name || '—'} />
            <Detail label="Email" value={bug.user_email || '—'} />
            <Detail label="User ID" value={bug.user_id || '—'} mono />
          </div>
        </div>
      </div>

      {/* Screenshot */}
      {bug.screenshot_base64 && (
        <div className="rounded-xl p-4 mb-4" style={{ background: 'var(--bg-secondary)', border: '1px solid var(--border)' }}>
          <h3 className="text-sm font-semibold mb-2" style={{ color: 'var(--text-primary)' }}>📸 Screenshot</h3>
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img
            src={`data:image/jpeg;base64,${bug.screenshot_base64}`}
            alt="Bug screenshot"
            className="rounded-lg max-h-96 object-contain"
            style={{ border: '1px solid var(--border)' }}
          />
        </div>
      )}

      {/* Session Log */}
      {bug.session_log && (
        <div className="rounded-xl p-4 mb-4" style={{ background: 'var(--bg-secondary)', border: '1px solid var(--border)' }}>
          <h3 className="text-sm font-semibold mb-2" style={{ color: 'var(--text-primary)' }}>📋 Session Log</h3>
          <pre
            className="text-xs whitespace-pre-wrap break-all p-3 rounded-lg overflow-x-auto max-h-96 overflow-y-auto"
            style={{ background: 'var(--bg-primary)', border: '1px solid var(--border)', color: 'var(--text-secondary)', fontFamily: 'ui-monospace, monospace' }}
          >
            {bug.session_log}
          </pre>
        </div>
      )}
    </div>
  )
}

// ═══════════════════════════════════════════════════
// Shared UI Components
// ═══════════════════════════════════════════════════

function Detail({ label, value, mono }: { label: string; value: string; mono?: boolean }) {
  return (
    <div>
      <span className="text-xs block" style={{ color: 'var(--text-muted)' }}>{label}</span>
      <span className={`text-sm ${mono ? 'font-mono' : ''}`} style={{ color: 'var(--text-primary)' }}>{value}</span>
    </div>
  )
}

function CollapsibleSection({ title, id, expanded, onToggle, children }: {
  title: string
  id: string
  expanded: Set<string>
  onToggle: (id: string) => void
  children: React.ReactNode
}) {
  const isExpanded = expanded.has(id)
  return (
    <div className="rounded-xl mb-3 overflow-hidden" style={{ background: 'var(--bg-secondary)', border: '1px solid var(--border)' }}>
      <button
        onClick={() => onToggle(id)}
        className="w-full flex items-center justify-between p-4 text-sm font-semibold hover:opacity-80"
        style={{ color: 'var(--text-primary)' }}
      >
        {title}
        <span style={{ color: 'var(--text-muted)' }}>{isExpanded ? '▼' : '▶'}</span>
      </button>
      {isExpanded && (
        <div className="px-4 pb-4">
          {children}
        </div>
      )}
    </div>
  )
}
