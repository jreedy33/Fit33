'use client'

import { useCallback, useEffect, useMemo, useState } from 'react'
import Link from 'next/link'
import AdminShell from '@/components/AdminShell'
import { adminApi } from '@/lib/api'

// ═══════════════════════════════════════════════════════════════════════════
// Types
// ═══════════════════════════════════════════════════════════════════════════

interface ProfileSnippet {
  id: string
  name: string | null
  username: string | null
  email: string | null
  profile_photo_url?: string | null
}

interface ModerationReport {
  id: string
  reporter_id: string
  reported_user_id: string
  reason: string
  description: string | null
  status: string
  resolution_notes: string | null
  created_at: string
  resolved_at: string | null
  resolved_by: string | null
  reporter_profile: ProfileSnippet | null
  reported_profile: ProfileSnippet | null
}

interface ModerationStats {
  total_reports: number
  reason_counts: Record<string, number>
  status_counts: Record<string, number>
  avg_resolution_hours: number | null
  total_blocks: number
  repeat_offenders: Array<{ user_id: string; report_count: number }>
}

interface SuspensionRow {
  id: string
  user_id: string
  reason: string
  suspended_by: string
  suspended_at: string
  expires_at: string | null
  lifted_at: string | null
  lifted_by: string | null
}

interface BlockRelationship {
  blocker_id: string
  blocked_id: string
  created_at: string
}

interface MostBlockedUser {
  user_id: string
  block_count: number
  profile: ProfileSnippet | null
}

interface FlaggedContent {
  id: string
  user_id: string | null
  table_name: string
  record_id: string | null
  content_snippet: string
  flagged_categories: string[]
  category_scores: Record<string, number>
  action_taken: string
  admin_reviewed: boolean
  admin_notes: string | null
  reviewed_at: string | null
  created_at: string
  user: ProfileSnippet | null
}

type TabId = 'queue' | 'overview' | 'suspensions' | 'blocks' | 'flagged'
type QueueStatusFilter = '' | 'pending' | 'reviewing' | 'resolved' | 'dismissed'

const QUEUE_STATUSES: { value: QueueStatusFilter; label: string }[] = [
  { value: '', label: 'All' },
  { value: 'pending', label: 'Pending' },
  { value: 'reviewing', label: 'Reviewing' },
  { value: 'resolved', label: 'Resolved' },
  { value: 'dismissed', label: 'Dismissed' },
]

const REASON_BAR_COLORS = [
  '#2563eb',
  '#22c55e',
  '#f59e0b',
  '#ef4444',
  '#8b5cf6',
  '#ec4899',
  '#06b6d4',
  '#6366f1',
  '#14b8a6',
  '#f97316',
]

// ═══════════════════════════════════════════════════════════════════════════
// Helpers
// ═══════════════════════════════════════════════════════════════════════════

function displayName(p: ProfileSnippet | null, fallbackId: string): string {
  if (!p) return fallbackId.slice(0, 8) + '…'
  const n = p.name?.trim()
  if (n) return n
  const u = p.username?.trim()
  if (u) return `@${u}`
  return p.email?.split('@')[0] || fallbackId.slice(0, 8) + '…'
}

function formatDateTime(iso: string | null | undefined): string {
  if (!iso) return '—'
  try {
    return new Date(iso).toLocaleString('en-US', {
      month: 'short',
      day: 'numeric',
      year: 'numeric',
      hour: 'numeric',
      minute: '2-digit',
    })
  } catch {
    return '—'
  }
}

function statusBadgeClass(status: string): string {
  const s = status.toLowerCase()
  if (s === 'pending') return 'badge badge-warning'
  if (s === 'reviewing') return 'badge badge-info'
  if (s === 'resolved') return 'badge badge-success'
  if (s === 'dismissed') return 'badge badge-neutral'
  return 'badge badge-neutral'
}

function suspensionDisplayStatus(s: SuspensionRow): { label: string; cls: string } {
  if (s.lifted_at) return { label: 'Lifted', cls: 'badge badge-neutral' }
  if (s.expires_at) {
    const exp = new Date(s.expires_at).getTime()
    if (exp < Date.now()) return { label: 'Expired', cls: 'badge badge-warning' }
  }
  return { label: 'Active', cls: 'badge badge-danger' }
}

function blockHeatStyle(count: number): React.CSSProperties {
  if (count >= 10) return { color: 'var(--danger)', fontWeight: 700 }
  if (count >= 5) return { color: 'var(--warning)', fontWeight: 600 }
  if (count >= 3) return { color: 'var(--info)' }
  return { color: 'var(--text-secondary)' }
}

// ═══════════════════════════════════════════════════════════════════════════
// Subcomponents
// ═══════════════════════════════════════════════════════════════════════════

function TabButton({
  id,
  label,
  active,
  onClick,
}: {
  id: TabId
  label: string
  active: boolean
  onClick: (t: TabId) => void
}) {
  return (
    <button
      type="button"
      onClick={() => onClick(id)}
      className={`tab ${active ? 'tab-active' : ''}`}
      aria-selected={active}
      aria-controls={`panel-${id}`}
    >
      {label}
    </button>
  )
}

function StatCard({
  label,
  value,
  hint,
  accent,
}: {
  label: string
  value: string | number
  hint?: string
  accent?: string
}) {
  return (
    <div className="card flex flex-col gap-1 min-h-[100px]">
      <span className="text-xs font-semibold uppercase tracking-wide" style={{ color: 'var(--text-muted)' }}>
        {label}
      </span>
      <span className="text-2xl font-bold" style={{ color: accent || 'var(--text-primary)' }}>
        {value}
      </span>
      {hint && (
        <span className="text-xs mt-auto" style={{ color: 'var(--text-secondary)' }}>
          {hint}
        </span>
      )}
    </div>
  )
}

// ═══════════════════════════════════════════════════════════════════════════
// Page
// ═══════════════════════════════════════════════════════════════════════════

export default function ModerationPage() {
  const [tab, setTab] = useState<TabId>('queue')

  const [queueLoading, setQueueLoading] = useState(false)
  const [reports, setReports] = useState<ModerationReport[]>([])
  const [queuePage, setQueuePage] = useState(0)
  const [queueStatus, setQueueStatus] = useState<QueueStatusFilter>('')
  const [queueError, setQueueError] = useState<string | null>(null)

  const [expandedId, setExpandedId] = useState<string | null>(null)
  const [notesDraft, setNotesDraft] = useState<Record<string, string>>({})
  const [actionBusy, setActionBusy] = useState<string | null>(null)

  const [stats, setStats] = useState<ModerationStats | null>(null)
  const [statsLoading, setStatsLoading] = useState(false)
  const [statsError, setStatsError] = useState<string | null>(null)

  const [suspensions, setSuspensions] = useState<SuspensionRow[]>([])
  const [suspLoading, setSuspLoading] = useState(false)
  const [suspError, setSuspError] = useState<string | null>(null)

  const [blocksData, setBlocksData] = useState<{
    total_blocks: number
    most_blocked_users: MostBlockedUser[]
    blocks: BlockRelationship[]
  } | null>(null)
  const [blocksLoading, setBlocksLoading] = useState(false)
  const [blocksError, setBlocksError] = useState<string | null>(null)

  // Flagged content state
  const [flaggedContent, setFlaggedContent] = useState<FlaggedContent[]>([])
  const [flaggedLoading, setFlaggedLoading] = useState(false)
  const [flaggedError, setFlaggedError] = useState<string | null>(null)
  const [flaggedCount, setFlaggedCount] = useState(0)
  const [reviewBusy, setReviewBusy] = useState<string | null>(null)

  const [suspendOpen, setSuspendOpen] = useState(false)
  const [suspendUserId, setSuspendUserId] = useState('')
  const [suspendLabel, setSuspendLabel] = useState('')
  const [suspendReason, setSuspendReason] = useState('')
  const [suspendExpires, setSuspendExpires] = useState('')
  const [suspendBusy, setSuspendBusy] = useState(false)

  const loadQueue = useCallback(async () => {
    setQueueLoading(true)
    setQueueError(null)
    try {
      const params: Record<string, unknown> = { page: queuePage, limit: 50 }
      if (queueStatus) params.status = queueStatus
      const data = await adminApi('get_moderation_queue', params)
      setReports((data.reports as ModerationReport[]) || [])
    } catch (e) {
      setQueueError(e instanceof Error ? e.message : 'Failed to load queue')
      setReports([])
    } finally {
      setQueueLoading(false)
    }
  }, [queuePage, queueStatus])

  const loadStats = useCallback(async () => {
    setStatsLoading(true)
    setStatsError(null)
    try {
      const data = await adminApi('get_moderation_stats')
      setStats(data as ModerationStats)
    } catch (e) {
      setStatsError(e instanceof Error ? e.message : 'Failed to load stats')
      setStats(null)
    } finally {
      setStatsLoading(false)
    }
  }, [])

  const loadSuspensions = useCallback(async () => {
    setSuspLoading(true)
    setSuspError(null)
    try {
      const data = await adminApi('get_user_suspensions', {})
      setSuspensions((data.suspensions as SuspensionRow[]) || [])
    } catch (e) {
      setSuspError(e instanceof Error ? e.message : 'Failed to load suspensions')
      setSuspensions([])
    } finally {
      setSuspLoading(false)
    }
  }, [])

  const loadBlocks = useCallback(async () => {
    setBlocksLoading(true)
    setBlocksError(null)
    try {
      const data = await adminApi('get_block_relationships')
      setBlocksData({
        total_blocks: data.total_blocks ?? 0,
        most_blocked_users: data.most_blocked_users || [],
        blocks: data.blocks || [],
      })
    } catch (e) {
      setBlocksError(e instanceof Error ? e.message : 'Failed to load blocks')
      setBlocksData(null)
    } finally {
      setBlocksLoading(false)
    }
  }, [])

  useEffect(() => {
    if (tab !== 'queue') return
    loadQueue()
  }, [tab, loadQueue])

  useEffect(() => {
    if (tab !== 'overview') return
    loadStats()
  }, [tab, loadStats])

  useEffect(() => {
    if (tab !== 'suspensions') return
    loadSuspensions()
  }, [tab, loadSuspensions])

  useEffect(() => {
    if (tab !== 'blocks') return
    loadBlocks()
  }, [tab, loadBlocks])

  const loadFlagged = useCallback(async () => {
    setFlaggedLoading(true)
    setFlaggedError(null)
    try {
      const data = await adminApi('get_flagged_content', { status: 'unreviewed' })
      setFlaggedContent(data.flagged_content || [])
      setFlaggedCount(data.total_unreviewed || 0)
    } catch (e) {
      setFlaggedError(e instanceof Error ? e.message : 'Failed to load flagged content')
    } finally {
      setFlaggedLoading(false)
    }
  }, [])

  useEffect(() => {
    if (tab !== 'flagged') return
    loadFlagged()
  }, [tab, loadFlagged])

  const handleReview = useCallback(async (logId: string, action: 'approved' | 'confirmed') => {
    setReviewBusy(logId)
    try {
      await adminApi('review_flagged_content', { log_id: logId, review_action: action })
      setFlaggedContent(prev => prev.filter(f => f.id !== logId))
      setFlaggedCount(prev => Math.max(0, prev - 1))
    } catch (e) {
      console.error('Review failed:', e)
    } finally {
      setReviewBusy(null)
    }
  }, [])

  const reasonBreakdown = useMemo(() => {
    if (!stats?.reason_counts) return []
    const entries = Object.entries(stats.reason_counts).sort((a, b) => b[1] - a[1])
    const max = Math.max(1, ...entries.map(([, c]) => c))
    return entries.map(([reason, count], i) => ({
      reason,
      count,
      pct: Math.round((count / max) * 100),
      color: REASON_BAR_COLORS[i % REASON_BAR_COLORS.length],
    }))
  }, [stats])

  const pendingCount = stats?.status_counts?.pending ?? 0

  function openSuspendForReport(r: ModerationReport) {
    setSuspendUserId(r.reported_user_id)
    setSuspendLabel(displayName(r.reported_profile, r.reported_user_id))
    setSuspendReason('')
    setSuspendExpires('')
    setSuspendOpen(true)
    setExpandedId(r.id)
  }

  async function submitSuspend() {
    if (!suspendUserId.trim() || !suspendReason.trim()) return
    setSuspendBusy(true)
    try {
      const expires_at = suspendExpires.trim()
        ? new Date(suspendExpires).toISOString()
        : undefined
      await adminApi('suspend_user', {
        user_id: suspendUserId,
        reason: suspendReason.trim(),
        ...(expires_at ? { expires_at } : {}),
      })
      setSuspendOpen(false)
      await loadQueue()
      if (tab === 'suspensions') await loadSuspensions()
    } catch (e) {
      alert(e instanceof Error ? e.message : 'Suspend failed')
    } finally {
      setSuspendBusy(false)
    }
  }

  async function updateReport(
    reportId: string,
    status: string,
    reportedUserId?: string
  ) {
    setActionBusy(reportId + status)
    try {
      const notes = notesDraft[reportId]?.trim() || undefined
      await adminApi('update_report_status', {
        report_id: reportId,
        status,
        ...(notes !== undefined ? { resolution_notes: notes } : {}),
      })
      if (status === 'resolved' || status === 'dismissed') {
        setNotesDraft((prev) => {
          const n = { ...prev }
          delete n[reportId]
          return n
        })
      }
      await loadQueue()
      if (tab === 'overview') await loadStats()
    } catch (e) {
      alert(e instanceof Error ? e.message : 'Update failed')
    } finally {
      setActionBusy(null)
    }
    if (reportedUserId && status === 'resolved') {
      /* reserved for future hooks */
    }
  }

  async function liftSuspension(id: string) {
    if (!confirm('Lift this suspension? The user will regain full access.')) return
    setActionBusy(`lift-${id}`)
    try {
      await adminApi('lift_suspension', { suspension_id: id })
      await loadSuspensions()
      if (tab === 'overview') await loadStats()
    } catch (e) {
      alert(e instanceof Error ? e.message : 'Lift failed')
    } finally {
      setActionBusy(null)
    }
  }

  function refreshAll() {
    if (tab === 'flagged') loadFlagged()
    else if (tab === 'queue') loadQueue()
    else if (tab === 'overview') loadStats()
    else if (tab === 'suspensions') loadSuspensions()
    else loadBlocks()
  }

  // Load flagged count on mount so tab badge is always visible
  useEffect(() => {
    adminApi('get_flagged_content', { status: 'unreviewed', limit: 1 })
      .then(data => setFlaggedCount(data.total_unreviewed || 0))
      .catch(() => {})
  }, [])

  return (
    <AdminShell>
      <div className="p-6 max-w-7xl mx-auto pb-24">
        <div className="flex flex-wrap items-end justify-between gap-4 mb-6">
          <div>
            <h1 className="text-2xl font-bold" style={{ color: 'var(--text-primary)' }}>
              Moderation Tools
            </h1>
            <p className="text-sm mt-1" style={{ color: 'var(--text-secondary)' }}>
              Review reports, suspensions, and block relationships
            </p>
          </div>
          <button
            type="button"
            onClick={refreshAll}
            className="btn btn-ghost text-sm"
            aria-label="Refresh current tab"
          >
            ↻ Refresh
          </button>
        </div>

        {/* Tabs */}
        <div
          className="flex flex-wrap border-b mb-6 gap-1"
          style={{ borderColor: 'var(--border)' }}
          role="tablist"
        >
          <TabButton id="flagged" label={`Flagged${flaggedCount > 0 ? ` (${flaggedCount})` : ''}`} active={tab === 'flagged'} onClick={setTab} />
          <TabButton id="queue" label="Queue" active={tab === 'queue'} onClick={setTab} />
          <TabButton id="overview" label="Overview" active={tab === 'overview'} onClick={setTab} />
          <TabButton id="suspensions" label="Suspensions" active={tab === 'suspensions'} onClick={setTab} />
          <TabButton id="blocks" label="Blocks" active={tab === 'blocks'} onClick={setTab} />
        </div>

        {/* ─── Flagged Content ─── */}
        {tab === 'flagged' && (
          <div id="panel-flagged" role="tabpanel" className="space-y-4">
            {flaggedError && (
              <div className="card" style={{ color: 'var(--danger)' }}>{flaggedError}</div>
            )}

            {flaggedLoading ? (
              <div className="card text-center py-12" style={{ color: 'var(--text-muted)' }}>Loading flagged content...</div>
            ) : flaggedContent.length === 0 ? (
              <div className="card text-center py-12">
                <p className="text-lg font-semibold" style={{ color: 'var(--success)' }}>All clear</p>
                <p className="text-sm mt-1" style={{ color: 'var(--text-muted)' }}>No unreviewed flagged content</p>
              </div>
            ) : (
              <div className="space-y-3">
                {flaggedContent.map((item) => (
                  <div key={item.id} className="card" style={{ borderLeft: '3px solid var(--danger)' }}>
                    <div className="flex items-start justify-between gap-4">
                      <div className="flex-1 min-w-0">
                        <div className="flex items-center gap-2 mb-1 flex-wrap">
                          <span className="text-xs font-mono px-2 py-0.5 rounded" style={{ background: 'var(--bg-tertiary)', color: 'var(--text-muted)' }}>
                            {item.table_name}
                          </span>
                          {item.flagged_categories.map((cat: string) => (
                            <span key={cat} className="text-xs font-semibold px-2 py-0.5 rounded" style={{ background: 'rgba(239,68,68,0.15)', color: 'var(--danger)' }}>
                              {cat}
                            </span>
                          ))}
                          <span className="text-xs" style={{ color: 'var(--text-muted)' }}>
                            {new Date(item.created_at).toLocaleString()}
                          </span>
                        </div>
                        {item.user && (
                          <div className="flex items-center gap-2 mb-2">
                            <Link href={`/users/${item.user.id}`} className="text-sm font-medium hover:underline" style={{ color: 'var(--primary)' }}>
                              {item.user.name || item.user.username || 'Unknown user'}
                            </Link>
                            {item.user.username && (
                              <span className="text-xs" style={{ color: 'var(--text-muted)' }}>@{item.user.username}</span>
                            )}
                          </div>
                        )}
                        <div className="p-3 rounded text-sm" style={{ background: 'var(--bg-tertiary)', wordBreak: 'break-word' }}>
                          {item.content_snippet}
                        </div>
                      </div>
                      <div className="flex flex-col gap-2 flex-shrink-0">
                        <button
                          className="btn btn-ghost text-xs"
                          disabled={reviewBusy === item.id}
                          onClick={() => handleReview(item.id, 'approved')}
                          title="False positive — unhide this content"
                        >
                          {reviewBusy === item.id ? '...' : 'Approve'}
                        </button>
                        <button
                          className="btn btn-danger text-xs"
                          disabled={reviewBusy === item.id}
                          onClick={() => handleReview(item.id, 'confirmed')}
                          title="Confirm flag — content stays hidden"
                        >
                          {reviewBusy === item.id ? '...' : 'Confirm'}
                        </button>
                      </div>
                    </div>
                  </div>
                ))}
              </div>
            )}
          </div>
        )}

        {/* ─── Queue ─── */}
        {tab === 'queue' && (
          <div id="panel-queue" role="tabpanel" className="space-y-4">
            <div className="flex flex-wrap items-center gap-3">
              <label className="text-sm font-medium" style={{ color: 'var(--text-secondary)' }}>
                Status
              </label>
              <select
                value={queueStatus}
                onChange={(e) => {
                  setQueuePage(0)
                  setQueueStatus(e.target.value as QueueStatusFilter)
                }}
                className="max-w-[200px]"
                aria-label="Filter reports by status"
              >
                {QUEUE_STATUSES.map((o) => (
                  <option key={o.value || 'all'} value={o.value}>
                    {o.label}
                  </option>
                ))}
              </select>
              <span className="text-xs" style={{ color: 'var(--text-muted)' }}>
                Page {queuePage + 1}
              </span>
              <button
                type="button"
                className="btn btn-ghost text-xs"
                disabled={queuePage === 0}
                onClick={() => setQueuePage((p) => Math.max(0, p - 1))}
                aria-label="Previous page"
              >
                Prev
              </button>
              <button
                type="button"
                className="btn btn-ghost text-xs"
                disabled={reports.length < 50}
                onClick={() => setQueuePage((p) => p + 1)}
                aria-label="Next page"
              >
                Next
              </button>
            </div>

            {queueError && (
              <div className="card border" style={{ borderColor: 'var(--danger)', color: 'var(--danger)' }}>
                {queueError}
              </div>
            )}

            {queueLoading ? (
              <div className="flex justify-center py-20">
                <div className="spinner" style={{ width: 32, height: 32 }} />
              </div>
            ) : reports.length === 0 ? (
              <div className="card text-center py-8" style={{ color: 'var(--text-muted)' }}>
                No reports in this queue.
              </div>
            ) : (
              <div className="space-y-3">
                {reports.map((r) => {
                  const expanded = expandedId === r.id
                  const reporterName = displayName(r.reporter_profile, r.reporter_id)
                  const reportedName = displayName(r.reported_profile, r.reported_user_id)
                  return (
                    <div
                      key={r.id}
                      className="card p-0 overflow-hidden"
                      style={{ borderColor: 'var(--border)' }}
                    >
                      <button
                        type="button"
                        className="w-full text-left px-4 py-3 flex flex-wrap items-center gap-3 hover:bg-opacity-50"
                        style={{ background: expanded ? 'var(--bg-tertiary)' : 'transparent' }}
                        onClick={() => setExpandedId(expanded ? null : r.id)}
                        aria-expanded={expanded}
                        aria-controls={`detail-${r.id}`}
                      >
                        <span className="font-medium text-sm mr-auto" style={{ color: 'var(--text-primary)' }}>
                          {reporterName}
                          <span style={{ color: 'var(--text-muted)' }}> → </span>
                          {reportedName}
                        </span>
                        <span className="badge badge-neutral max-w-[140px] truncate" title={r.reason}>
                          {r.reason}
                        </span>
                        <span className={statusBadgeClass(r.status)}>{r.status}</span>
                        <span className="text-xs shrink-0" style={{ color: 'var(--text-muted)' }}>
                          {formatDateTime(r.created_at)}
                        </span>
                        <span className="text-xs" style={{ color: 'var(--text-muted)' }}>
                          {expanded ? '▼' : '▶'}
                        </span>
                      </button>

                      {expanded && (
                        <div
                          id={`detail-${r.id}`}
                          className="border-t px-4 py-4 space-y-4"
                          style={{ borderColor: 'var(--border)', background: 'var(--bg-primary)' }}
                        >
                          <div className="grid sm:grid-cols-2 gap-4 text-sm">
                            <div>
                              <div style={{ color: 'var(--text-muted)' }} className="text-xs uppercase mb-1">
                                Reporter
                              </div>
                              <Link
                                href={`/users/${r.reporter_id}`}
                                className="underline"
                                style={{ color: 'var(--accent)' }}
                              >
                                {reporterName}
                              </Link>
                            </div>
                            <div>
                              <div style={{ color: 'var(--text-muted)' }} className="text-xs uppercase mb-1">
                                Reported user
                              </div>
                              <Link
                                href={`/users/${r.reported_user_id}`}
                                className="underline"
                                style={{ color: 'var(--accent)' }}
                              >
                                {reportedName}
                              </Link>
                            </div>
                          </div>

                          <div>
                            <div style={{ color: 'var(--text-muted)' }} className="text-xs uppercase mb-1">
                              Description
                            </div>
                            <p style={{ color: 'var(--text-primary)' }} className="text-sm whitespace-pre-wrap">
                              {r.description?.trim() || '—'}
                            </p>
                          </div>

                          {r.resolution_notes && (
                            <div>
                              <div style={{ color: 'var(--text-muted)' }} className="text-xs uppercase mb-1">
                                Existing notes
                              </div>
                              <p style={{ color: 'var(--text-secondary)' }} className="text-sm whitespace-pre-wrap">
                                {r.resolution_notes}
                              </p>
                            </div>
                          )}

                          <div>
                            <label className="text-xs uppercase mb-1 block" style={{ color: 'var(--text-muted)' }}>
                              Resolution notes
                            </label>
                            <textarea
                              rows={3}
                              value={notesDraft[r.id] ?? ''}
                              onChange={(e) =>
                                setNotesDraft((prev) => ({ ...prev, [r.id]: e.target.value }))
                              }
                              placeholder="Notes for resolve / dismiss…"
                              className="w-full"
                            />
                          </div>

                          <div className="flex flex-wrap gap-2">
                            <button
                              type="button"
                              className="btn btn-ghost text-sm"
                              disabled={r.status === 'reviewing' || !!actionBusy}
                              onClick={() => updateReport(r.id, 'reviewing')}
                              aria-label="Mark as reviewing"
                            >
                              {actionBusy === r.id + 'reviewing' ? '…' : 'Mark Reviewing'}
                            </button>
                            <button
                              type="button"
                              className="btn btn-primary text-sm"
                              disabled={!!actionBusy}
                              onClick={() => updateReport(r.id, 'resolved')}
                              aria-label="Mark as resolved"
                            >
                              {actionBusy === r.id + 'resolved' ? '…' : 'Resolve'}
                            </button>
                            <button
                              type="button"
                              className="btn btn-ghost text-sm"
                              disabled={!!actionBusy}
                              onClick={() => updateReport(r.id, 'dismissed')}
                              aria-label="Dismiss report"
                            >
                              {actionBusy === r.id + 'dismissed' ? '…' : 'Dismiss'}
                            </button>
                            <button
                              type="button"
                              className="btn btn-danger text-sm"
                              disabled={!!actionBusy}
                              onClick={() => openSuspendForReport(r)}
                              aria-label="Suspend reported user"
                            >
                              Suspend User
                            </button>
                          </div>
                        </div>
                      )}
                    </div>
                  )
                })}
              </div>
            )}
          </div>
        )}

        {/* ─── Overview ─── */}
        {tab === 'overview' && (
          <div id="panel-overview" role="tabpanel" className="space-y-6">
            {statsError && (
              <div className="card" style={{ color: 'var(--danger)' }}>
                {statsError}
              </div>
            )}
            {statsLoading ? (
              <div className="flex justify-center py-20">
                <div className="spinner" style={{ width: 32, height: 32 }} />
              </div>
            ) : stats ? (
              <>
                <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
                  <StatCard
                    label="Total reports"
                    value={stats.total_reports}
                    accent="var(--text-primary)"
                  />
                  <StatCard
                    label="Pending"
                    value={pendingCount}
                    hint="Awaiting action"
                    accent="var(--warning)"
                  />
                  <StatCard
                    label="Avg resolution"
                    value={stats.avg_resolution_hours != null ? `${stats.avg_resolution_hours} h` : '—'}
                    hint="Hours across resolved reports"
                    accent="var(--info)"
                  />
                  <StatCard
                    label="Total blocks"
                    value={stats.total_blocks}
                    hint="User block relationships"
                    accent="var(--text-secondary)"
                  />
                </div>

                <div className="card">
                  <h2 className="text-lg font-semibold mb-4" style={{ color: 'var(--text-primary)' }}>
                    Reports by reason
                  </h2>
                  {reasonBreakdown.length === 0 ? (
                    <p style={{ color: 'var(--text-muted)' }}>No data.</p>
                  ) : (
                    <div className="space-y-3">
                      {reasonBreakdown.map((row) => (
                        <div key={row.reason}>
                          <div className="flex justify-between text-xs mb-1">
                            <span style={{ color: 'var(--text-primary)' }} className="truncate pr-2">
                              {row.reason}
                            </span>
                            <span style={{ color: 'var(--text-secondary)' }}>{row.count}</span>
                          </div>
                          <div
                            className="h-2 rounded-full overflow-hidden"
                            style={{ background: 'var(--bg-tertiary)' }}
                          >
                            <div
                              className="h-full rounded-full transition-all"
                              style={{ width: `${row.pct}%`, background: row.color }}
                            />
                          </div>
                        </div>
                      ))}
                    </div>
                  )}
                </div>

                <div className="card">
                  <h2 className="text-lg font-semibold mb-2" style={{ color: 'var(--text-primary)' }}>
                    Repeat offenders
                  </h2>
                  <p className="text-sm mb-4" style={{ color: 'var(--text-secondary)' }}>
                    Users reported 2+ times (most reports first).
                  </p>
                  {stats.repeat_offenders.length === 0 ? (
                    <p style={{ color: 'var(--text-muted)' }}>None flagged.</p>
                  ) : (
                    <div className="overflow-x-auto">
                      <table>
                        <thead>
                          <tr>
                            <th>User</th>
                            <th>Reports</th>
                            <th />
                          </tr>
                        </thead>
                        <tbody>
                          {stats.repeat_offenders.map((o) => (
                            <tr key={o.user_id}>
                              <td>
                                <code className="text-xs" style={{ color: 'var(--text-primary)' }}>
                                  {o.user_id.slice(0, 8)}…
                                </code>
                              </td>
                              <td>
                                <span className="badge badge-warning">{o.report_count}</span>
                              </td>
                              <td>
                                <Link
                                  href={`/users/${o.user_id}`}
                                  className="btn btn-ghost text-xs py-1"
                                  style={{ color: 'var(--accent)' }}
                                >
                                  Open profile
                                </Link>
                              </td>
                            </tr>
                          ))}
                        </tbody>
                      </table>
                    </div>
                  )}
                </div>
              </>
            ) : null}
          </div>
        )}

        {/* ─── Suspensions ─── */}
        {tab === 'suspensions' && (
          <div id="panel-suspensions" role="tabpanel">
            {suspError && (
              <div className="card mb-4" style={{ color: 'var(--danger)' }}>
                {suspError}
              </div>
            )}
            {suspLoading ? (
              <div className="flex justify-center py-20">
                <div className="spinner" style={{ width: 32, height: 32 }} />
              </div>
            ) : (
              <div className="overflow-x-auto card p-0">
                <table>
                  <thead>
                    <tr>
                      <th>User</th>
                      <th>Reason</th>
                      <th>By</th>
                      <th>Suspended</th>
                      <th>Expires</th>
                      <th>Status</th>
                      <th />
                    </tr>
                  </thead>
                  <tbody>
                    {suspensions.length === 0 ? (
                      <tr>
                        <td colSpan={7} style={{ color: 'var(--text-muted)' }}>
                          No suspensions.
                        </td>
                      </tr>
                    ) : (
                      suspensions.map((s) => {
                        const st = suspensionDisplayStatus(s)
                        const canLift = !s.lifted_at
                        return (
                          <tr key={s.id}>
                            <td>
                              <Link
                                href={`/users/${s.user_id}`}
                                className="text-sm underline"
                                style={{ color: 'var(--accent)' }}
                              >
                                {s.user_id.slice(0, 8)}…
                              </Link>
                            </td>
                            <td style={{ maxWidth: 220 }} className="truncate" title={s.reason}>
                              {s.reason}
                            </td>
                            <td className="text-sm" style={{ color: 'var(--text-secondary)' }}>
                              {s.suspended_by}
                            </td>
                            <td className="text-sm whitespace-nowrap">{formatDateTime(s.suspended_at)}</td>
                            <td className="text-sm whitespace-nowrap">
                              {s.expires_at ? formatDateTime(s.expires_at) : '—'}
                            </td>
                            <td>
                              <span className={st.cls}>{st.label}</span>
                            </td>
                            <td>
                              {canLift ? (
                                <button
                                  type="button"
                                  className="btn btn-ghost text-xs"
                                  disabled={!!actionBusy}
                                  onClick={() => liftSuspension(s.id)}
                                  aria-label="Lift suspension"
                                >
                                  {actionBusy === `lift-${s.id}` ? '…' : 'Lift Suspension'}
                                </button>
                              ) : (
                                <span className="text-xs" style={{ color: 'var(--text-muted)' }}>
                                  —
                                </span>
                              )}
                            </td>
                          </tr>
                        )
                      })
                    )}
                  </tbody>
                </table>
              </div>
            )}
          </div>
        )}

        {/* ─── Blocks ─── */}
        {tab === 'blocks' && (
          <div id="panel-blocks" role="tabpanel" className="space-y-6">
            {blocksError && (
              <div className="card" style={{ color: 'var(--danger)' }}>
                {blocksError}
              </div>
            )}
            {blocksLoading ? (
              <div className="flex justify-center py-20">
                <div className="spinner" style={{ width: 32, height: 32 }} />
              </div>
            ) : blocksData ? (
              <>
                <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                  <div className="card">
                    <span className="text-xs font-semibold uppercase" style={{ color: 'var(--text-muted)' }}>
                      Total blocks
                    </span>
                    <div className="text-3xl font-bold mt-2" style={{ color: 'var(--text-primary)' }}>
                      {blocksData.total_blocks}
                    </div>
                    <p className="text-xs mt-2" style={{ color: 'var(--text-secondary)' }}>
                      Block relationships recorded (sample up to 1000 in API).
                    </p>
                  </div>
                </div>

                <div className="card">
                  <h2 className="text-lg font-semibold mb-4" style={{ color: 'var(--text-primary)' }}>
                    Most blocked users
                  </h2>
                  {blocksData.most_blocked_users.length === 0 ? (
                    <p style={{ color: 'var(--text-muted)' }}>No data.</p>
                  ) : (
                    <div className="overflow-x-auto">
                      <table>
                        <thead>
                          <tr>
                            <th>User</th>
                            <th>Username</th>
                            <th>Block count</th>
                            <th />
                          </tr>
                        </thead>
                        <tbody>
                          {blocksData.most_blocked_users.map((m) => {
                            const p = m.profile
                            const name = p?.name || p?.username || m.user_id.slice(0, 8) + '…'
                            return (
                              <tr key={m.user_id}>
                                <td style={{ color: 'var(--text-primary)' }}>{name}</td>
                                <td style={{ color: 'var(--text-secondary)' }} className="text-sm">
                                  {p?.username ? `@${p.username}` : '—'}
                                </td>
                                <td>
                                  <span className="text-lg tabular-nums" style={blockHeatStyle(m.block_count)}>
                                    {m.block_count}
                                  </span>
                                  {m.block_count >= 10 && (
                                    <span className="badge badge-danger ml-2">High</span>
                                  )}
                                  {m.block_count >= 5 && m.block_count < 10 && (
                                    <span className="badge badge-warning ml-2">Elevated</span>
                                  )}
                                </td>
                                <td>
                                  <Link
                                    href={`/users/${m.user_id}`}
                                    className="btn btn-ghost text-xs py-1"
                                  >
                                    Profile
                                  </Link>
                                </td>
                              </tr>
                            )
                          })}
                        </tbody>
                      </table>
                    </div>
                  )}
                </div>

                <div className="card">
                  <h2 className="text-lg font-semibold mb-4" style={{ color: 'var(--text-primary)' }}>
                    Recent block events
                  </h2>
                  <div className="overflow-x-auto max-h-[320px] overflow-y-auto">
                    <table>
                      <thead>
                        <tr>
                          <th>Blocker</th>
                          <th>Blocked</th>
                          <th>When</th>
                        </tr>
                      </thead>
                      <tbody>
                        {blocksData.blocks.slice(0, 50).map((b, i) => (
                          <tr key={`${b.blocker_id}-${b.blocked_id}-${i}`}>
                            <td className="text-xs font-mono">{b.blocker_id.slice(0, 8)}…</td>
                            <td className="text-xs font-mono">{b.blocked_id.slice(0, 8)}…</td>
                            <td className="text-sm">{formatDateTime(b.created_at)}</td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </div>
                </div>
              </>
            ) : null}
          </div>
        )}

        {/* Suspend modal */}
        {suspendOpen && (
          <div
            className="fixed inset-0 z-50 flex items-center justify-center p-4"
            style={{ background: 'rgba(0,0,0,0.65)' }}
            role="dialog"
            aria-modal="true"
            aria-labelledby="suspend-title"
          >
            <div
              className="card max-w-md w-full space-y-4"
              style={{ background: 'var(--bg-secondary)', borderColor: 'var(--border)' }}
            >
              <h3 id="suspend-title" className="text-lg font-semibold" style={{ color: 'var(--text-primary)' }}>
                Suspend user
              </h3>
              <p className="text-sm" style={{ color: 'var(--text-secondary)' }}>
                {suspendLabel}
                <code className="block text-xs mt-1" style={{ color: 'var(--text-muted)' }}>
                  {suspendUserId}
                </code>
              </p>
              <div>
                <label className="text-xs uppercase block mb-1" style={{ color: 'var(--text-muted)' }}>
                  Reason (required)
                </label>
                <textarea
                  rows={3}
                  value={suspendReason}
                  onChange={(e) => setSuspendReason(e.target.value)}
                  className="w-full"
                />
              </div>
              <div>
                <label className="text-xs uppercase block mb-1" style={{ color: 'var(--text-muted)' }}>
                  Expires (optional)
                </label>
                <input
                  type="datetime-local"
                  value={suspendExpires}
                  onChange={(e) => setSuspendExpires(e.target.value)}
                  className="w-full"
                />
              </div>
              <div className="flex justify-end gap-2 pt-2">
                <button
                  type="button"
                  className="btn btn-ghost"
                  disabled={suspendBusy}
                  onClick={() => setSuspendOpen(false)}
                >
                  Cancel
                </button>
                <button
                  type="button"
                  className="btn btn-danger"
                  disabled={suspendBusy || !suspendReason.trim()}
                  onClick={submitSuspend}
                >
                  {suspendBusy ? '…' : 'Confirm suspension'}
                </button>
              </div>
            </div>
          </div>
        )}
      </div>
    </AdminShell>
  )
}
