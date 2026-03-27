'use client'

import { Fragment, useCallback, useEffect, useMemo, useState } from 'react'
import { useRouter } from 'next/navigation'
import AdminShell from '@/components/AdminShell'
import { adminApi } from '@/lib/api'

type TabId = 'dashboard' | 'campaigns' | 'queue' | 'debug'

const SEGMENTS = [
  { value: 'all', label: 'All users' },
  { value: 'at_risk', label: 'At risk' },
  { value: 'inactive_7d', label: 'Inactive 7d' },
  { value: 'inactive_30d', label: 'Inactive 30d' },
  { value: 'new_users', label: 'New users (7d)' },
  { value: 'power_users', label: 'Power users' },
] as const

type SegmentValue = (typeof SEGMENTS)[number]['value']

interface QueueStats {
  total?: number
  pending?: number
  processing?: number
  sent?: number
  failed?: number
  sent_24h?: number
  failed_24h?: number
  oldest_pending?: string | null
}

interface Delivery24h {
  total_events?: number
  apns_success?: number
  apns_failed?: number
  prefs_blocked?: number
  token_found?: number
}

interface HourlyPoint {
  hour: string
  sent: number
  failed: number
}

interface PipelineOverview {
  queue?: QueueStats
  delivery_24h?: Delivery24h
  hourly_trend?: HourlyPoint[]
}

interface PushCampaign {
  id: string
  title: string
  body: string
  segment: string
  notification_type?: string
  status: string
  scheduled_at?: string | null
  sent_at?: string | null
  sent_count?: number
  failed_count?: number
  created_at?: string
  created_by?: string
  data?: Record<string, unknown>
}

interface DeliveryLog {
  event: string
  detail: Record<string, unknown> | null
  created_at: string
}

interface QueueRow {
  id: string
  recipient_user_id: string
  notification_type: string
  title: string | null
  body: string | null
  status: string
  error_message: string | null
  retry_count: number
  created_at: string
  sent_at: string | null
  recipient_profile: {
    id: string
    name: string | null
    username: string | null
    email: string | null
    profile_photo_url: string | null
  } | null
  delivery_logs: DeliveryLog[]
}

interface UserDebugPayload {
  tokens: Record<string, unknown>[]
  preferences: Record<string, unknown> | null
  recent_queue: Record<string, unknown>[]
  delivery_logs: Record<string, unknown>[]
}

function campaignStatusBadge(status: string) {
  switch (status) {
    case 'draft':
      return 'badge-neutral'
    case 'scheduled':
      return 'badge-info'
    case 'sending':
      return 'badge-warning'
    case 'sent':
      return 'badge-success'
    case 'cancelled':
      return 'badge-danger'
    default:
      return 'badge-neutral'
  }
}

function maskToken(raw: string | undefined): string {
  if (!raw || raw.length < 12) return '••••••••'
  return `${raw.slice(0, 6)}…${raw.slice(-4)}`
}

export default function PushNotificationsPage() {
  const router = useRouter()
  const [tab, setTab] = useState<TabId>('dashboard')
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  const [pipeline, setPipeline] = useState<PipelineOverview | null>(null)
  const [recentCampaigns, setRecentCampaigns] = useState<PushCampaign[]>([])
  const [campaigns, setCampaigns] = useState<PushCampaign[]>([])
  const [queueItems, setQueueItems] = useState<QueueRow[]>([])
  const [queueStatusCounts, setQueueStatusCounts] = useState<Record<string, number>>({})
  const [expandedQueueRow, setExpandedQueueRow] = useState<string | null>(null)

  const [campaignsLoading, setCampaignsLoading] = useState(false)
  const [queueLoading, setQueueLoading] = useState(false)

  const [autoRefreshQueue, setAutoRefreshQueue] = useState(false)

  const [showCreateModal, setShowCreateModal] = useState(false)
  const [createTitle, setCreateTitle] = useState('')
  const [createBody, setCreateBody] = useState('')
  const [createSegment, setCreateSegment] = useState<SegmentValue>('all')
  const [createNotifyType, setCreateNotifyType] = useState('campaign')
  const [createSchedule, setCreateSchedule] = useState('')
  const [sendNow, setSendNow] = useState(false)
  const [estimatedReach, setEstimatedReach] = useState<number | null>(null)
  const [reachLoading, setReachLoading] = useState(false)
  const [savingCampaign, setSavingCampaign] = useState(false)

  const [editingCampaign, setEditingCampaign] = useState<PushCampaign | null>(null)
  const [editTitle, setEditTitle] = useState('')
  const [editBody, setEditBody] = useState('')
  const [editSegment, setEditSegment] = useState<SegmentValue>('all')
  const [editSchedule, setEditSchedule] = useState('')
  const [editSaving, setEditSaving] = useState(false)

  const [confirmSend, setConfirmSend] = useState<{ id: string; title: string } | null>(null)
  const [sendingId, setSendingId] = useState<string | null>(null)

  const [userIdInput, setUserIdInput] = useState('')
  const [userDebug, setUserDebug] = useState<UserDebugPayload | null>(null)
  const [userDebugLoading, setUserDebugLoading] = useState(false)

  const loadOverview = useCallback(async () => {
    setError(null)
    const data = await adminApi('get_push_overview')
    setPipeline((data.pipeline as PipelineOverview) || null)
    setRecentCampaigns((data.recent_campaigns as PushCampaign[]) || [])
  }, [])

  const loadCampaigns = useCallback(async () => {
    setCampaignsLoading(true)
    setError(null)
    try {
      const data = await adminApi('get_push_campaigns')
      setCampaigns((data.campaigns as PushCampaign[]) || [])
    } finally {
      setCampaignsLoading(false)
    }
  }, [])

  const loadQueue = useCallback(async () => {
    setQueueLoading(true)
    setError(null)
    try {
      const [overviewData, queueData] = await Promise.all([
        adminApi('get_push_overview'),
        adminApi('get_push_queue_status'),
      ])
      setPipeline((overviewData.pipeline as PipelineOverview) || null)
      setQueueItems((queueData.items as QueueRow[]) || [])
      setQueueStatusCounts((queueData.status_counts as Record<string, number>) || {})
    } finally {
      setQueueLoading(false)
    }
  }, [])

  useEffect(() => {
    let cancelled = false
    ;(async () => {
      setLoading(true)
      try {
        await loadOverview()
      } catch (e) {
        if (!cancelled) setError(e instanceof Error ? e.message : 'Failed to load')
      } finally {
        if (!cancelled) setLoading(false)
      }
    })()
    return () => {
      cancelled = true
    }
  }, [loadOverview])

  useEffect(() => {
    if (tab === 'campaigns') loadCampaigns()
  }, [tab, loadCampaigns])

  useEffect(() => {
    if (tab === 'queue') loadQueue()
  }, [tab, loadQueue])

  useEffect(() => {
    if (!autoRefreshQueue || tab !== 'queue') return
    const t = setInterval(() => {
      loadQueue()
    }, 10_000)
    return () => clearInterval(t)
  }, [autoRefreshQueue, tab, loadQueue])

  useEffect(() => {
    let cancelled = false
    ;(async () => {
      setReachLoading(true)
      setEstimatedReach(null)
      try {
        const data = await adminApi('estimate_campaign_reach', { segment: createSegment })
        if (!cancelled) setEstimatedReach(Number(data.reach) || 0)
      } catch {
        if (!cancelled) setEstimatedReach(null)
      } finally {
        if (!cancelled) setReachLoading(false)
      }
    })()
    return () => {
      cancelled = true
    }
  }, [createSegment, showCreateModal])

  const deliveryRate = useMemo(() => {
    const d = pipeline?.delivery_24h
    if (!d) return null
    const ok = d.apns_success ?? 0
    const bad = d.apns_failed ?? 0
    const denom = ok + bad
    if (denom === 0) return null
    return Math.round((ok / denom) * 1000) / 10
  }, [pipeline])

  const hourlyBars = useMemo(() => {
    const trend = pipeline?.hourly_trend
    if (!Array.isArray(trend) || trend.length === 0) return []
    const maxSent = Math.max(...trend.map((h) => Number(h.sent) || 0), 1)
    return trend.map((h) => ({
      ...h,
      pct: ((Number(h.sent) || 0) / maxSent) * 100,
    }))
  }, [pipeline])

  function openCreateModal() {
    setCreateTitle('')
    setCreateBody('')
    setCreateSegment('all')
    setCreateNotifyType('campaign')
    setCreateSchedule('')
    setSendNow(false)
    setShowCreateModal(true)
  }

  function localDateTimeToISO(local: string): string | null {
    if (!local) return null
    const d = new Date(local)
    if (Number.isNaN(d.getTime())) return null
    return d.toISOString()
  }

  function isoToLocalDateTime(iso: string | null | undefined): string {
    if (!iso) return ''
    const d = new Date(iso)
    if (Number.isNaN(d.getTime())) return ''
    const pad = (n: number) => String(n).padStart(2, '0')
    return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`
  }

  async function submitCreate() {
    if (!createTitle.trim() || !createBody.trim()) {
      setError('Title and body are required')
      return
    }
    setSavingCampaign(true)
    setError(null)
    try {
      const scheduledAt = sendNow ? null : localDateTimeToISO(createSchedule)
      const payload: Record<string, unknown> = {
        title: createTitle.trim(),
        body: createBody.trim(),
        segment: createSegment,
        notification_type: createNotifyType || 'campaign',
      }
      if (scheduledAt) payload.scheduled_at = scheduledAt

      const { campaign } = await adminApi('create_push_campaign', payload)
      const created = campaign as PushCampaign
      setShowCreateModal(false)
      await loadCampaigns()
      await loadOverview()

      if (sendNow && created?.id) {
        setConfirmSend({ id: created.id, title: created.title })
      }
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Create failed')
    } finally {
      setSavingCampaign(false)
    }
  }

  function openEdit(c: PushCampaign) {
    setEditingCampaign(c)
    setEditTitle(c.title)
    setEditBody(c.body)
    setEditSegment((c.segment as SegmentValue) || 'all')
    setEditSchedule(isoToLocalDateTime(c.scheduled_at))
  }

  async function submitEdit() {
    if (!editingCampaign) return
    setEditSaving(true)
    setError(null)
    try {
      const scheduledAt = editSchedule ? localDateTimeToISO(editSchedule) : null
      const updates: Record<string, unknown> = {
        campaign_id: editingCampaign.id,
        title: editTitle.trim(),
        body: editBody.trim(),
        segment: editSegment,
        scheduled_at: scheduledAt,
      }
      if (!scheduledAt) {
        updates.status = 'draft'
      } else {
        updates.status = 'scheduled'
      }
      await adminApi('update_push_campaign', updates)
      setEditingCampaign(null)
      await loadCampaigns()
      await loadOverview()
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Update failed')
    } finally {
      setEditSaving(false)
    }
  }

  async function runSendCampaign(campaignId: string) {
    setSendingId(campaignId)
    setError(null)
    try {
      await adminApi('send_push_campaign', { campaign_id: campaignId })
      setConfirmSend(null)
      await loadCampaigns()
      await loadOverview()
      if (tab === 'queue') await loadQueue()
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Send failed')
    } finally {
      setSendingId(null)
    }
  }

  async function runUserDebug() {
    const uid = userIdInput.trim()
    if (!uid) {
      setError('Enter a user UUID')
      return
    }
    setUserDebugLoading(true)
    setUserDebug(null)
    setError(null)
    try {
      const data = await adminApi('get_push_user_debug', { user_id: uid })
      setUserDebug({
        tokens: (data.tokens as Record<string, unknown>[]) || [],
        preferences: (data.preferences as Record<string, unknown> | null) || null,
        recent_queue: (data.recent_queue as Record<string, unknown>[]) || [],
        delivery_logs: (data.delivery_logs as Record<string, unknown>[]) || [],
      })
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Lookup failed')
    } finally {
      setUserDebugLoading(false)
    }
  }

  const q = pipeline?.queue

  return (
    <AdminShell>
      <div className="p-6 max-w-7xl mx-auto">
        <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4 mb-6">
          <div>
            <h1 className="text-2xl font-bold" style={{ color: 'var(--text-primary)' }}>
              Push Notification Manager
            </h1>
            <p className="text-sm mt-1" style={{ color: 'var(--text-secondary)' }}>
              Pipeline health, campaigns, queue, and per-user diagnostics
            </p>
          </div>
          <div className="flex flex-wrap gap-2">
            <button type="button" className="btn btn-ghost text-sm" onClick={() => loadOverview()}>
              ↻ Refresh overview
            </button>
          </div>
        </div>

        {error && (
          <div
            className="mb-4 px-4 py-3 rounded-lg text-sm"
            style={{ background: 'rgba(239, 68, 68, 0.12)', color: 'var(--danger)', border: '1px solid rgba(239,68,68,0.35)' }}
          >
            {error}
          </div>
        )}

        {/* Tabs */}
        <div className="flex flex-wrap gap-1 mb-6 border-b" style={{ borderColor: 'var(--border)' }}>
          {(
            [
              ['dashboard', 'Dashboard'],
              ['campaigns', 'Campaigns'],
              ['queue', 'Queue Monitor'],
              ['debug', 'User Debug'],
            ] as const
          ).map(([id, label]) => (
            <button
              key={id}
              type="button"
              className={`tab ${tab === id ? 'tab-active' : ''}`}
              onClick={() => setTab(id)}
            >
              {label}
            </button>
          ))}
        </div>

        {loading && tab === 'dashboard' ? (
          <div className="flex justify-center py-20">
            <div className="spinner" style={{ width: 36, height: 36 }} />
          </div>
        ) : (
          <>
            {tab === 'dashboard' && (
              <div className="space-y-6">
                <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
                  <div className="card">
                    <div className="text-xs font-semibold uppercase tracking-wide mb-1" style={{ color: 'var(--text-muted)' }}>
                      Queue depth
                    </div>
                    <div className="text-3xl font-bold" style={{ color: 'var(--text-primary)' }}>
                      {q?.total?.toLocaleString() ?? '—'}
                    </div>
                    <div className="text-xs mt-2" style={{ color: 'var(--text-secondary)' }}>
                      Pending {q?.pending ?? '—'} · Processing {q?.processing ?? '—'}
                    </div>
                  </div>
                  <div className="card">
                    <div className="text-xs font-semibold uppercase tracking-wide mb-1" style={{ color: 'var(--text-muted)' }}>
                      Sent (24h)
                    </div>
                    <div className="text-3xl font-bold" style={{ color: 'var(--success)' }}>
                      {q?.sent_24h?.toLocaleString() ?? '—'}
                    </div>
                    <div className="text-xs mt-2" style={{ color: 'var(--text-secondary)' }}>
                      Queue rows marked sent in 24h
                    </div>
                  </div>
                  <div className="card">
                    <div className="text-xs font-semibold uppercase tracking-wide mb-1" style={{ color: 'var(--text-muted)' }}>
                      Failed (24h)
                    </div>
                    <div className="text-3xl font-bold" style={{ color: 'var(--danger)' }}>
                      {q?.failed_24h?.toLocaleString() ?? '—'}
                    </div>
                    <div className="text-xs mt-2" style={{ color: 'var(--text-secondary)' }}>
                      Failed attempts (24h window)
                    </div>
                  </div>
                  <div className="card">
                    <div className="text-xs font-semibold uppercase tracking-wide mb-1" style={{ color: 'var(--text-muted)' }}>
                      Delivery rate (24h)
                    </div>
                    <div className="text-3xl font-bold" style={{ color: 'var(--accent)' }}>
                      {deliveryRate != null ? `${deliveryRate}%` : '—'}
                    </div>
                    <div className="text-xs mt-2" style={{ color: 'var(--text-secondary)' }}>
                      APNS success / (success + failure)
                    </div>
                  </div>
                </div>

                <div className="card">
                  <h2 className="text-lg font-semibold mb-4" style={{ color: 'var(--text-primary)' }}>
                    Hourly send volume (24h)
                  </h2>
                  {hourlyBars.length === 0 ? (
                    <p className="text-sm" style={{ color: 'var(--text-muted)' }}>
                      No delivery events in the last 24 hours.
                    </p>
                  ) : (
                    <div className="flex items-end gap-1 h-40 px-1">
                      {hourlyBars.map((h, i) => {
                        const label = h.hour
                          ? new Date(h.hour).toLocaleTimeString(undefined, { hour: 'numeric', hour12: true })
                          : `${i}`
                        return (
                          <div key={`${h.hour}-${i}`} className="flex-1 flex flex-col items-center gap-1 min-w-0">
                            <div
                              className="w-full rounded-t"
                              style={{
                                height: `${Math.max(8, h.pct)}%`,
                                background: 'linear-gradient(180deg, var(--accent), rgba(37,99,235,0.35))',
                                minHeight: 4,
                              }}
                              title={`${label}: ${h.sent} sent`}
                            />
                            <span
                              className="text-[9px] truncate w-full text-center leading-tight"
                              style={{ color: 'var(--text-muted)' }}
                            >
                              {label}
                            </span>
                          </div>
                        )
                      })}
                    </div>
                  )}
                </div>

                <div className="card">
                  <div className="flex items-center justify-between mb-4">
                    <h2 className="text-lg font-semibold" style={{ color: 'var(--text-primary)' }}>
                      Recent campaigns
                    </h2>
                    <button type="button" className="btn btn-ghost text-xs" onClick={() => setTab('campaigns')}>
                      Open Campaigns →
                    </button>
                  </div>
                  <div className="overflow-x-auto">
                    <table>
                      <thead>
                        <tr>
                          <th>Title</th>
                          <th>Segment</th>
                          <th>Status</th>
                          <th>Created</th>
                        </tr>
                      </thead>
                      <tbody>
                        {recentCampaigns.map((c) => (
                          <tr key={c.id}>
                            <td className="font-medium">{c.title}</td>
                            <td>
                              <span className="badge badge-neutral">{c.segment}</span>
                            </td>
                            <td>
                              <span className={`badge ${campaignStatusBadge(c.status)}`}>{c.status}</span>
                            </td>
                            <td className="text-sm" style={{ color: 'var(--text-muted)' }}>
                              {c.created_at ? new Date(c.created_at).toLocaleString() : '—'}
                            </td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                    {recentCampaigns.length === 0 && (
                      <p className="text-sm py-6 text-center" style={{ color: 'var(--text-muted)' }}>
                        No campaigns yet.
                      </p>
                    )}
                  </div>
                </div>
              </div>
            )}

            {tab === 'campaigns' && (
              <div className="space-y-4">
                <div className="flex justify-end">
                  <button type="button" className="btn btn-primary" onClick={openCreateModal}>
                    + New Campaign
                  </button>
                </div>

                {campaignsLoading ? (
                  <div className="flex justify-center py-16">
                    <div className="spinner" style={{ width: 32, height: 32 }} />
                  </div>
                ) : (
                  <div className="card overflow-x-auto">
                    <table>
                      <thead>
                        <tr>
                          <th>Title</th>
                          <th>Segment</th>
                          <th>Status</th>
                          <th>Scheduled</th>
                          <th>Counts</th>
                          <th style={{ minWidth: 200 }}>Actions</th>
                        </tr>
                      </thead>
                      <tbody>
                        {campaigns.map((c) => (
                          <tr key={c.id}>
                            <td>
                              <div className="font-medium" style={{ color: 'var(--text-primary)' }}>
                                {c.title}
                              </div>
                              <div className="text-xs line-clamp-2 mt-0.5" style={{ color: 'var(--text-muted)' }}>
                                {c.body}
                              </div>
                            </td>
                            <td>
                              <span className="badge badge-neutral">{c.segment}</span>
                            </td>
                            <td>
                              <span className={`badge ${campaignStatusBadge(c.status)}`}>{c.status}</span>
                            </td>
                            <td className="text-sm" style={{ color: 'var(--text-secondary)' }}>
                              {c.scheduled_at ? new Date(c.scheduled_at).toLocaleString() : '—'}
                            </td>
                            <td className="text-sm" style={{ color: 'var(--text-secondary)' }}>
                              {c.status === 'sent' ? (
                                <>
                                  Sent {c.sent_count ?? 0} · Failed {c.failed_count ?? 0}
                                </>
                              ) : (
                                '—'
                              )}
                            </td>
                            <td>
                              <div className="flex flex-wrap gap-2">
                                {(c.status === 'draft' || c.status === 'scheduled') && (
                                  <>
                                    <button type="button" className="btn btn-ghost text-xs py-1 px-2" onClick={() => openEdit(c)}>
                                      Edit
                                    </button>
                                    <button
                                      type="button"
                                      className="btn btn-primary text-xs py-1 px-2"
                                      onClick={() => setConfirmSend({ id: c.id, title: c.title })}
                                      disabled={sendingId === c.id}
                                    >
                                      Send
                                    </button>
                                  </>
                                )}
                              </div>
                            </td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                    {campaigns.length === 0 && (
                      <p className="text-sm py-8 text-center" style={{ color: 'var(--text-muted)' }}>
                        No campaigns. Create one to get started.
                      </p>
                    )}
                  </div>
                )}
              </div>
            )}

            {tab === 'queue' && (
              <div className="space-y-6">
                <div className="flex flex-wrap items-center justify-between gap-3">
                  <label className="flex items-center gap-2 text-sm cursor-pointer" style={{ color: 'var(--text-secondary)' }}>
                    <input
                      type="checkbox"
                      checked={autoRefreshQueue}
                      onChange={(e) => setAutoRefreshQueue(e.target.checked)}
                      className="rounded"
                    />
                    Auto-refresh every 10s
                  </label>
                  <button
                    type="button"
                    className="btn btn-ghost text-sm"
                    onClick={() => loadQueue()}
                    disabled={queueLoading}
                  >
                    ↻ Refresh now
                  </button>
                </div>

                {queueLoading && !pipeline ? (
                  <div className="flex justify-center py-16">
                    <div className="spinner" style={{ width: 32, height: 32 }} />
                  </div>
                ) : (
                  <>
                    <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
                      <div className="card text-center py-6">
                        <div className="text-4xl font-bold" style={{ color: 'var(--warning)' }}>
                          {q?.pending?.toLocaleString() ?? '—'}
                        </div>
                        <div className="text-sm mt-2 font-medium" style={{ color: 'var(--text-secondary)' }}>
                          Pending
                        </div>
                      </div>
                      <div className="card text-center py-6">
                        <div className="text-4xl font-bold" style={{ color: 'var(--info)' }}>
                          {q?.processing?.toLocaleString() ?? '—'}
                        </div>
                        <div className="text-sm mt-2 font-medium" style={{ color: 'var(--text-secondary)' }}>
                          Processing
                        </div>
                      </div>
                      <div className="card text-center py-6">
                        <div className="text-4xl font-bold" style={{ color: 'var(--danger)' }}>
                          {q?.failed?.toLocaleString() ?? '—'}
                        </div>
                        <div className="text-sm mt-2 font-medium" style={{ color: 'var(--text-secondary)' }}>
                          Failed (total)
                        </div>
                      </div>
                    </div>

                    <div className="card">
                      <h2 className="text-lg font-semibold mb-2" style={{ color: 'var(--text-primary)' }}>
                        Sample queue rows (pending / processing / failed)
                      </h2>
                      <p className="text-xs mb-4" style={{ color: 'var(--text-muted)' }}>
                        Status counts from last fetch:{' '}
                        {Object.entries(queueStatusCounts)
                          .map(([k, v]) => `${k}: ${v}`)
                          .join(' · ') || '—'}
                      </p>
                      <div className="overflow-x-auto">
                        <table>
                          <thead>
                            <tr>
                              <th>Status</th>
                              <th>Recipient</th>
                              <th>Notification</th>
                              <th>Type</th>
                              <th>Created</th>
                              <th>Age</th>
                              <th>Logs</th>
                            </tr>
                          </thead>
                          <tbody>
                            {queueItems.map((row, idx) => {
                              const ageMs = Date.now() - new Date(row.created_at).getTime()
                              const ageMin = Math.floor(ageMs / 60000)
                              const stuck = row.status === 'pending' && ageMin > 30
                              const rp = row.recipient_profile
                              const rowKey = row.id || `${row.status}-${row.created_at}-${idx}`
                              return (
                                <Fragment key={rowKey}>
                                <tr>
                                  <td>
                                    <span
                                      className={`badge ${
                                        row.status === 'failed'
                                          ? 'badge-danger'
                                          : row.status === 'processing'
                                            ? 'badge-warning'
                                            : stuck
                                              ? 'badge-warning'
                                              : 'badge-neutral'
                                      }`}
                                    >
                                      {row.status}
                                    </span>
                                    {row.error_message && (
                                      <div className="text-xs mt-1 max-w-[160px] truncate" style={{ color: 'var(--danger)' }} title={row.error_message}>
                                        {row.error_message}
                                      </div>
                                    )}
                                  </td>
                                  <td>
                                    {rp ? (
                                      <button
                                        onClick={() => router.push(`/users/${rp.id}`)}
                                        className="flex items-center gap-2 hover:opacity-80"
                                        style={{ background: 'none', border: 'none', cursor: 'pointer', padding: 0 }}
                                      >
                                        <div
                                          className="w-7 h-7 rounded-full flex items-center justify-center text-xs font-bold shrink-0"
                                          style={{
                                            background: rp.profile_photo_url ? 'transparent' : 'var(--bg-tertiary)',
                                            color: 'var(--text-secondary)',
                                            backgroundImage: rp.profile_photo_url ? `url(${rp.profile_photo_url})` : undefined,
                                            backgroundSize: 'cover',
                                          }}
                                        >
                                          {!rp.profile_photo_url && (rp.name?.[0] || rp.username?.[0] || '?')}
                                        </div>
                                        <div className="text-left">
                                          <div className="text-sm font-medium" style={{ color: 'var(--accent)' }}>
                                            {rp.name || rp.username || 'Unknown'}
                                          </div>
                                          <div className="text-xs" style={{ color: 'var(--text-muted)' }}>
                                            {rp.email || `@${rp.username || '—'}`}
                                          </div>
                                        </div>
                                      </button>
                                    ) : (
                                      <span className="text-xs font-mono" style={{ color: 'var(--text-muted)' }}>
                                        {row.recipient_user_id?.substring(0, 8)}...
                                      </span>
                                    )}
                                  </td>
                                  <td style={{ maxWidth: 280 }}>
                                    {row.title && (
                                      <div className="text-sm font-medium truncate" style={{ color: 'var(--text-primary)' }}>
                                        {row.title}
                                      </div>
                                    )}
                                    {row.body && (
                                      <div className="text-xs truncate" style={{ color: 'var(--text-muted)', maxWidth: 280 }}>
                                        {row.body}
                                      </div>
                                    )}
                                    {!row.title && !row.body && (
                                      <span className="text-xs" style={{ color: 'var(--text-muted)' }}>—</span>
                                    )}
                                  </td>
                                  <td>
                                    <span className="badge badge-info">{row.notification_type || '—'}</span>
                                  </td>
                                  <td className="text-sm whitespace-nowrap" style={{ color: 'var(--text-secondary)' }}>
                                    {new Date(row.created_at).toLocaleString()}
                                  </td>
                                  <td className="text-sm whitespace-nowrap" style={{ color: 'var(--text-muted)' }}>
                                    {ageMin < 60 ? `${ageMin}m` : `${Math.floor(ageMin / 60)}h ${ageMin % 60}m`}
                                    {stuck && ' · possibly stuck'}
                                  </td>
                                  <td>
                                    <button
                                      onClick={() => setExpandedQueueRow(expandedQueueRow === row.id ? null : row.id)}
                                      className="text-xs px-2 py-1 rounded"
                                      style={{
                                        background: expandedQueueRow === row.id ? 'var(--accent)' : 'var(--bg-tertiary)',
                                        color: expandedQueueRow === row.id ? 'white' : 'var(--text-muted)',
                                        border: 'none', cursor: 'pointer',
                                      }}
                                    >
                                      {row.delivery_logs?.length || 0} logs {expandedQueueRow === row.id ? '▲' : '▼'}
                                    </button>
                                  </td>
                                </tr>
                                {expandedQueueRow === row.id && (
                                  <tr>
                                    <td colSpan={7} style={{ padding: 0, border: 'none' }}>
                                      <div className="px-4 py-3 mb-1 rounded-b-lg" style={{ background: 'var(--bg-tertiary)' }}>
                                        <div className="text-xs font-semibold mb-2" style={{ color: 'var(--text-secondary)' }}>
                                          Delivery Pipeline Logs
                                        </div>
                                        {(!row.delivery_logs || row.delivery_logs.length === 0) ? (
                                          <p className="text-xs" style={{ color: 'var(--text-muted)' }}>No delivery logs recorded for this notification.</p>
                                        ) : (
                                          <div className="space-y-1.5">
                                            {row.delivery_logs.map((log, li) => {
                                              const isSuccess = log.event.includes('success')
                                              const isFail = log.event.includes('failed') || log.event.includes('blocked')
                                              return (
                                                <div key={li} className="flex items-start gap-2">
                                                  <div className="w-1.5 h-1.5 rounded-full mt-1.5 shrink-0" style={{
                                                    background: isSuccess ? 'var(--success)' : isFail ? 'var(--danger)' : 'var(--text-muted)',
                                                  }} />
                                                  <div className="flex-1 min-w-0">
                                                    <div className="flex items-center gap-2">
                                                      <span className="text-xs font-mono font-medium" style={{
                                                        color: isSuccess ? 'var(--success)' : isFail ? 'var(--danger)' : 'var(--text-primary)',
                                                      }}>
                                                        {log.event}
                                                      </span>
                                                      <span className="text-xs" style={{ color: 'var(--text-muted)' }}>
                                                        {new Date(log.created_at).toLocaleTimeString()}
                                                      </span>
                                                    </div>
                                                    {log.detail && Object.keys(log.detail).length > 0 && (
                                                      <pre className="text-xs mt-0.5 overflow-x-auto" style={{ color: 'var(--text-muted)', margin: 0 }}>
                                                        {JSON.stringify(log.detail, null, 2)}
                                                      </pre>
                                                    )}
                                                  </div>
                                                </div>
                                              )
                                            })}
                                          </div>
                                        )}
                                      </div>
                                    </td>
                                  </tr>
                                )}
                              </Fragment>
                              )
                            })}
                          </tbody>
                        </table>
                        {queueItems.length === 0 && (
                          <p className="text-sm py-6 text-center" style={{ color: 'var(--text-muted)' }}>
                            No pending, processing, or failed rows in the current sample.
                          </p>
                        )}
                      </div>
                    </div>
                  </>
                )}
              </div>
            )}

            {tab === 'debug' && (
              <div className="card space-y-6">
                <div className="flex flex-col sm:flex-row gap-3 sm:items-end">
                  <div className="flex-1">
                    <label className="block text-xs font-semibold uppercase mb-2" style={{ color: 'var(--text-muted)' }}>
                      User ID (UUID)
                    </label>
                    <input
                      type="text"
                      value={userIdInput}
                      onChange={(e) => setUserIdInput(e.target.value)}
                      placeholder="00000000-0000-0000-0000-000000000000"
                      className="w-full"
                    />
                  </div>
                  <button
                    type="button"
                    className="btn btn-primary shrink-0"
                    onClick={runUserDebug}
                    disabled={userDebugLoading}
                  >
                    {userDebugLoading ? 'Loading…' : 'Lookup'}
                  </button>
                </div>

                {userDebug && (
                  <div className="space-y-6 pt-2 border-t" style={{ borderColor: 'var(--border)' }}>
                    <section>
                      <h3 className="text-md font-semibold mb-3" style={{ color: 'var(--text-primary)' }}>
                        Device tokens
                      </h3>
                      {userDebug.tokens.length === 0 ? (
                        <p className="text-sm" style={{ color: 'var(--text-muted)' }}>
                          No tokens on file.
                        </p>
                      ) : (
                        <div className="space-y-2">
                          {userDebug.tokens.map((t, i) => {
                            const tokenStr = typeof t.token === 'string' ? t.token : typeof t.device_token === 'string' ? t.device_token : ''
                            return (
                              <div
                                key={i}
                                className="p-3 rounded-lg text-sm font-mono"
                                style={{ background: 'var(--bg-tertiary)', color: 'var(--text-secondary)' }}
                              >
                                {maskToken(tokenStr)} · valid: {String(t.is_valid ?? '—')}
                              </div>
                            )
                          })}
                        </div>
                      )}
                    </section>

                    <section>
                      <h3 className="text-md font-semibold mb-3" style={{ color: 'var(--text-primary)' }}>
                        Notification preferences
                      </h3>
                      {userDebug.preferences == null ? (
                        <p className="text-sm" style={{ color: 'var(--text-muted)' }}>
                          No preference row (defaults may apply).
                        </p>
                      ) : (
                        <pre
                          className="p-4 rounded-lg text-xs overflow-x-auto"
                          style={{ background: 'var(--bg-tertiary)', color: 'var(--text-secondary)', border: '1px solid var(--border)' }}
                        >
                          {JSON.stringify(userDebug.preferences, null, 2)}
                        </pre>
                      )}
                    </section>

                    <section>
                      <h3 className="text-md font-semibold mb-3" style={{ color: 'var(--text-primary)' }}>
                        Recent queue items
                      </h3>
                      <div className="overflow-x-auto">
                        <table>
                          <thead>
                            <tr>
                              <th>Type</th>
                              <th>Title</th>
                              <th>Status</th>
                              <th>Created</th>
                            </tr>
                          </thead>
                          <tbody>
                            {userDebug.recent_queue.map((row, i) => (
                              <tr key={i}>
                                <td className="text-sm">{String(row.notification_type ?? '—')}</td>
                                <td className="text-sm">{String(row.title ?? '—')}</td>
                                <td>
                                  <span className="badge badge-neutral">{String(row.status ?? '—')}</span>
                                </td>
                                <td className="text-sm" style={{ color: 'var(--text-muted)' }}>
                                  {row.created_at ? new Date(String(row.created_at)).toLocaleString() : '—'}
                                </td>
                              </tr>
                            ))}
                          </tbody>
                        </table>
                        {userDebug.recent_queue.length === 0 && (
                          <p className="text-sm py-4" style={{ color: 'var(--text-muted)' }}>
                            No queue rows for this user.
                          </p>
                        )}
                      </div>
                    </section>

                    <section>
                      <h3 className="text-md font-semibold mb-3" style={{ color: 'var(--text-primary)' }}>
                        Delivery log timeline
                      </h3>
                      <div className="space-y-3">
                        {userDebug.delivery_logs.map((log, i) => (
                          <div
                            key={i}
                            className="flex gap-4 border-l-2 pl-4 py-1"
                            style={{ borderColor: 'var(--accent)' }}
                          >
                            <div className="text-xs shrink-0 w-40" style={{ color: 'var(--text-muted)' }}>
                              {log.created_at ? new Date(String(log.created_at)).toLocaleString() : '—'}
                            </div>
                            <div className="flex-1 min-w-0">
                              <span className="badge badge-info">{String(log.event ?? 'event')}</span>
                              <div className="text-xs mt-1 break-all" style={{ color: 'var(--text-secondary)' }}>
                                {log.detail != null ? JSON.stringify(log.detail) : '—'}
                              </div>
                            </div>
                          </div>
                        ))}
                        {userDebug.delivery_logs.length === 0 && (
                          <p className="text-sm" style={{ color: 'var(--text-muted)' }}>
                            No delivery events.
                          </p>
                        )}
                      </div>
                    </section>
                  </div>
                )}
              </div>
            )}
          </>
        )}

        {/* Create campaign modal */}
        {showCreateModal && (
          <div
            className="fixed inset-0 z-50 flex items-center justify-center p-4"
            style={{ background: 'rgba(0,0,0,0.65)' }}
            role="dialog"
            aria-modal="true"
            aria-labelledby="create-campaign-title"
          >
            <div className="card max-w-lg w-full max-h-[90vh] overflow-y-auto" style={{ background: 'var(--bg-secondary)' }}>
              <h2 id="create-campaign-title" className="text-lg font-semibold mb-4" style={{ color: 'var(--text-primary)' }}>
                New campaign
              </h2>
              <div className="space-y-4">
                <div>
                  <label className="block text-xs font-semibold uppercase mb-1" style={{ color: 'var(--text-muted)' }}>
                    Title
                  </label>
                  <input value={createTitle} onChange={(e) => setCreateTitle(e.target.value)} />
                </div>
                <div>
                  <label className="block text-xs font-semibold uppercase mb-1" style={{ color: 'var(--text-muted)' }}>
                    Body
                  </label>
                  <textarea rows={4} value={createBody} onChange={(e) => setCreateBody(e.target.value)} />
                </div>
                <div>
                  <label className="block text-xs font-semibold uppercase mb-1" style={{ color: 'var(--text-muted)' }}>
                    Segment
                  </label>
                  <select value={createSegment} onChange={(e) => setCreateSegment(e.target.value as SegmentValue)}>
                    {SEGMENTS.map((s) => (
                      <option key={s.value} value={s.value}>
                        {s.label}
                      </option>
                    ))}
                  </select>
                  <div className="text-sm mt-2" style={{ color: 'var(--text-secondary)' }}>
                    Estimated reach:{' '}
                    {reachLoading ? (
                      <span style={{ color: 'var(--text-muted)' }}>calculating…</span>
                    ) : estimatedReach != null ? (
                      <strong style={{ color: 'var(--accent)' }}>{estimatedReach.toLocaleString()}</strong>
                    ) : (
                      '—'
                    )}
                  </div>
                </div>
                <div>
                  <label className="block text-xs font-semibold uppercase mb-1" style={{ color: 'var(--text-muted)' }}>
                    Notification type
                  </label>
                  <input
                    value={createNotifyType}
                    onChange={(e) => setCreateNotifyType(e.target.value)}
                    placeholder="campaign"
                  />
                </div>
                <label className="flex items-center gap-2 text-sm cursor-pointer" style={{ color: 'var(--text-secondary)' }}>
                  <input type="checkbox" checked={sendNow} onChange={(e) => setSendNow(e.target.checked)} />
                  Send immediately after create (opens confirmation)
                </label>
                {!sendNow && (
                  <div>
                    <label className="block text-xs font-semibold uppercase mb-1" style={{ color: 'var(--text-muted)' }}>
                      Schedule at (local)
                    </label>
                    <input
                      type="datetime-local"
                      value={createSchedule}
                      onChange={(e) => setCreateSchedule(e.target.value)}
                      style={{
                        background: 'var(--bg-tertiary)',
                        border: '1px solid var(--border)',
                        color: 'var(--text-primary)',
                        borderRadius: 8,
                        padding: '8px 12px',
                        width: '100%',
                      }}
                    />
                  </div>
                )}
              </div>
              <div className="flex justify-end gap-2 mt-6">
                <button type="button" className="btn btn-ghost" onClick={() => setShowCreateModal(false)} disabled={savingCampaign}>
                  Cancel
                </button>
                <button type="button" className="btn btn-primary" onClick={submitCreate} disabled={savingCampaign}>
                  {savingCampaign ? 'Saving…' : sendNow ? 'Create' : 'Create campaign'}
                </button>
              </div>
            </div>
          </div>
        )}

        {/* Edit campaign modal */}
        {editingCampaign && (
          <div
            className="fixed inset-0 z-50 flex items-center justify-center p-4"
            style={{ background: 'rgba(0,0,0,0.65)' }}
            role="dialog"
            aria-modal="true"
          >
            <div className="card max-w-lg w-full max-h-[90vh] overflow-y-auto" style={{ background: 'var(--bg-secondary)' }}>
              <h2 className="text-lg font-semibold mb-4" style={{ color: 'var(--text-primary)' }}>
                Edit campaign
              </h2>
              <div className="space-y-4">
                <div>
                  <label className="block text-xs font-semibold uppercase mb-1" style={{ color: 'var(--text-muted)' }}>
                    Title
                  </label>
                  <input value={editTitle} onChange={(e) => setEditTitle(e.target.value)} />
                </div>
                <div>
                  <label className="block text-xs font-semibold uppercase mb-1" style={{ color: 'var(--text-muted)' }}>
                    Body
                  </label>
                  <textarea rows={4} value={editBody} onChange={(e) => setEditBody(e.target.value)} />
                </div>
                <div>
                  <label className="block text-xs font-semibold uppercase mb-1" style={{ color: 'var(--text-muted)' }}>
                    Segment
                  </label>
                  <select value={editSegment} onChange={(e) => setEditSegment(e.target.value as SegmentValue)}>
                    {SEGMENTS.map((s) => (
                      <option key={s.value} value={s.value}>
                        {s.label}
                      </option>
                    ))}
                  </select>
                </div>
                <div>
                  <label className="block text-xs font-semibold uppercase mb-1" style={{ color: 'var(--text-muted)' }}>
                    Schedule at (local, optional)
                  </label>
                  <input
                    type="datetime-local"
                    value={editSchedule}
                    onChange={(e) => setEditSchedule(e.target.value)}
                    style={{
                      background: 'var(--bg-tertiary)',
                      border: '1px solid var(--border)',
                      color: 'var(--text-primary)',
                      borderRadius: 8,
                      padding: '8px 12px',
                      width: '100%',
                    }}
                  />
                  <p className="text-xs mt-1" style={{ color: 'var(--text-muted)' }}>
                    Clear the schedule field and save to keep as draft.
                  </p>
                </div>
              </div>
              <div className="flex justify-end gap-2 mt-6">
                <button type="button" className="btn btn-ghost" onClick={() => setEditingCampaign(null)} disabled={editSaving}>
                  Cancel
                </button>
                <button type="button" className="btn btn-primary" onClick={submitEdit} disabled={editSaving}>
                  {editSaving ? 'Saving…' : 'Save changes'}
                </button>
              </div>
            </div>
          </div>
        )}

        {/* Confirm send */}
        {confirmSend && (
          <div
            className="fixed inset-0 z-[60] flex items-center justify-center p-4"
            style={{ background: 'rgba(0,0,0,0.7)' }}
            role="alertdialog"
            aria-modal="true"
            aria-labelledby="confirm-send-title"
          >
            <div className="card max-w-md w-full" style={{ background: 'var(--bg-secondary)', borderColor: 'var(--warning)' }}>
              <h2 id="confirm-send-title" className="text-lg font-semibold mb-2" style={{ color: 'var(--text-primary)' }}>
                Send push campaign?
              </h2>
              <p className="text-sm mb-4" style={{ color: 'var(--text-secondary)' }}>
                This will enqueue notifications for all users matching the campaign segment. Campaign:{' '}
                <strong style={{ color: 'var(--text-primary)' }}>{confirmSend.title}</strong>
              </p>
              <p className="text-xs mb-6" style={{ color: 'var(--danger)' }}>
                This action cannot be undone. Confirm before sending.
              </p>
              <div className="flex justify-end gap-2">
                <button
                  type="button"
                  className="btn btn-ghost"
                  onClick={() => setConfirmSend(null)}
                  disabled={!!sendingId}
                >
                  Cancel
                </button>
                <button
                  type="button"
                  className="btn btn-danger"
                  onClick={() => runSendCampaign(confirmSend.id)}
                  disabled={!!sendingId}
                >
                  {sendingId ? 'Sending…' : 'Send now'}
                </button>
              </div>
            </div>
          </div>
        )}
      </div>
    </AdminShell>
  )
}
