'use client'

// /revenue/subscribers — admin list of active + recent subscriptions.
// Owner: MONETIZATION_AGENT.md (invariant 27 — Subscribers tab; invariant
// 28 — admin must be able to grant / revoke / extend trial without leaving
// the page; invariant 30 — every mutation lands in two audit logs).

import { useEffect, useState, useCallback } from 'react'
import AdminShell from '@/components/AdminShell'
import { RevenueHeader } from '@/components/RevenueTabNav'
import {
  formatCents,
  formatDateTime,
  formatRelative,
  statusBadge,
  tierLabel,
} from '@/components/RevenueCards'
import { adminApi } from '@/lib/api'

interface UserMini {
  email?: string | null
  name?: string | null
  username?: string | null
}

interface SubscriberRow {
  id: string
  user_id: string
  product_id: string
  tier: string
  status: string
  started_at: string
  expires_at: string | null
  will_auto_renew: boolean
  is_in_intro_offer: boolean
  ownership_type: string
  original_transaction_id: string | null
  environment: string
  last_assn_event_at: string | null
  last_assn_notification_type: string | null
  revenue_cents: number | null
  currency: string | null
  created_at: string
  updated_at: string
  user_profiles: UserMini | null
}

interface ListResponse {
  schema_deployed: boolean
  subscribers: SubscriberRow[]
  total: number
}

const STATUS_OPTIONS = ['active', 'in_trial', 'grace_period', 'expired', 'revoked', 'paused', 'pending']
const TIER_OPTIONS = ['pro_monthly', 'pro_yearly', 'pro_lifetime', 'comp']

export default function SubscribersPage() {
  const [data, setData] = useState<ListResponse | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [filterStatus, setFilterStatus] = useState<string>('')
  const [filterTier, setFilterTier] = useState<string>('')
  const [search, setSearch] = useState<string>('')
  const [pendingSearch, setPendingSearch] = useState<string>('')
  const [page, setPage] = useState(0)
  const [actionTarget, setActionTarget] = useState<SubscriberRow | null>(null)

  const load = useCallback(async () => {
    setLoading(true)
    setError(null)
    try {
      const res: ListResponse = await adminApi('list_subscribers', {
        status: filterStatus || undefined,
        tier: filterTier || undefined,
        q: search || undefined,
        page,
        limit: 50,
      })
      setData(res)
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load subscribers')
    } finally {
      setLoading(false)
    }
  }, [filterStatus, filterTier, search, page])

  useEffect(() => {
    load()
  }, [load])

  const showRoadmap = data && !data.schema_deployed
  const showEmpty = data && data.schema_deployed && data.subscribers.length === 0
  const total = data?.total ?? 0

  return (
    <AdminShell>
      <div className="p-6 max-w-7xl mx-auto">
        <RevenueHeader subtitle="Active and recent subscriptions. Search, filter, and apply admin actions per row." />

        {showRoadmap && (
          <div
            className="card mb-6"
            style={{ background: 'rgba(245, 158, 11, 0.08)', borderColor: 'rgba(245, 158, 11, 0.4)' }}
          >
            <div className="text-sm font-semibold" style={{ color: '#f59e0b' }}>
              Subscription schema not yet deployed
            </div>
            <div className="text-sm mt-1" style={{ color: 'var(--text-secondary)' }}>
              The Subscribers list will populate once the assn-webhook starts writing rows.
              Configure the Sandbox URL in App Store Connect → App Information → App Store Server
              Notifications, then perform a sandbox purchase to see the first row appear here.
            </div>
          </div>
        )}

        <div className="flex flex-wrap gap-3 mb-4 items-end">
          <div>
            <label className="block text-xs font-medium mb-1" style={{ color: 'var(--text-secondary)' }}>
              Status
            </label>
            <select
              className="input"
              value={filterStatus}
              onChange={(e) => { setFilterStatus(e.target.value); setPage(0) }}
            >
              <option value="">Any status</option>
              {STATUS_OPTIONS.map((s) => (
                <option key={s} value={s}>{statusBadge(s).label}</option>
              ))}
            </select>
          </div>

          <div>
            <label className="block text-xs font-medium mb-1" style={{ color: 'var(--text-secondary)' }}>
              Tier
            </label>
            <select
              className="input"
              value={filterTier}
              onChange={(e) => { setFilterTier(e.target.value); setPage(0) }}
            >
              <option value="">Any tier</option>
              {TIER_OPTIONS.map((t) => (
                <option key={t} value={t}>{tierLabel(t)}</option>
              ))}
            </select>
          </div>

          <form
            className="flex gap-2 items-end flex-1"
            onSubmit={(e) => { e.preventDefault(); setSearch(pendingSearch); setPage(0) }}
          >
            <div className="flex-1 min-w-[200px]">
              <label className="block text-xs font-medium mb-1" style={{ color: 'var(--text-secondary)' }}>
                Search by email / name / username
              </label>
              <input
                className="input w-full"
                value={pendingSearch}
                onChange={(e) => setPendingSearch(e.target.value)}
                placeholder="user@example.com"
              />
            </div>
            <button type="submit" className="btn btn-primary">Search</button>
            {(search || filterStatus || filterTier) && (
              <button
                type="button"
                className="btn"
                onClick={() => { setSearch(''); setPendingSearch(''); setFilterStatus(''); setFilterTier(''); setPage(0) }}
              >
                Clear
              </button>
            )}
          </form>
        </div>

        {loading && (
          <div className="flex justify-center py-20">
            <div className="spinner" style={{ width: 32, height: 32 }} />
          </div>
        )}

        {!loading && error && (
          <div className="card" style={{ background: 'rgba(239, 68, 68, 0.08)', borderColor: '#ef4444' }}>
            <div className="text-sm font-semibold" style={{ color: '#ef4444' }}>Error</div>
            <div className="text-sm mt-1" style={{ color: 'var(--text-secondary)' }}>{error}</div>
          </div>
        )}

        {!loading && !error && data && data.schema_deployed && (
          <>
            <div className="text-xs mb-2" style={{ color: 'var(--text-muted)' }}>
              Showing {data.subscribers.length} of {total} {total === 1 ? 'subscription' : 'subscriptions'}
            </div>

            {showEmpty && (
              <div className="card text-center py-12">
                <div className="text-4xl mb-3">📭</div>
                <div className="text-base font-medium mb-1" style={{ color: 'var(--text-primary)' }}>
                  No subscribers yet
                </div>
                <div className="text-sm" style={{ color: 'var(--text-secondary)' }}>
                  No rows match the current filters.
                </div>
              </div>
            )}

            {!showEmpty && (
              <div className="card p-0 overflow-hidden">
                <table>
                  <thead>
                    <tr>
                      <th>User</th>
                      <th>Tier</th>
                      <th>Status</th>
                      <th>Started</th>
                      <th>Expires</th>
                      <th>Renew</th>
                      <th>Env</th>
                      <th>Last event</th>
                      <th>Revenue</th>
                      <th style={{ width: 110 }}>Actions</th>
                    </tr>
                  </thead>
                  <tbody>
                    {data.subscribers.map((row) => {
                      const sb = statusBadge(row.status)
                      return (
                        <tr key={row.id}>
                          <td>
                            <div className="text-sm font-medium" style={{ color: 'var(--text-primary)' }}>
                              {row.user_profiles?.name || row.user_profiles?.username || '—'}
                            </div>
                            <div className="text-xs" style={{ color: 'var(--text-muted)' }}>
                              {row.user_profiles?.email || row.user_id}
                            </div>
                          </td>
                          <td>
                            <span className="text-sm">{tierLabel(row.tier)}</span>
                            {row.is_in_intro_offer && (
                              <div>
                                <span className="badge badge-info" style={{ fontSize: 10 }}>intro</span>
                              </div>
                            )}
                          </td>
                          <td>
                            <span
                              className="badge"
                              style={{ background: `${sb.color}22`, color: sb.color, borderColor: `${sb.color}88` }}
                            >
                              {sb.label}
                            </span>
                          </td>
                          <td className="text-sm">{formatDateTime(row.started_at)}</td>
                          <td className="text-sm">{formatDateTime(row.expires_at)}</td>
                          <td>
                            {row.will_auto_renew ? (
                              <span className="badge badge-info" style={{ fontSize: 10 }}>auto</span>
                            ) : (
                              <span style={{ color: 'var(--text-muted)' }}>—</span>
                            )}
                          </td>
                          <td>
                            <span
                              className="badge"
                              style={{
                                fontSize: 10,
                                background: row.environment === 'production' ? '#22c55e22' : '#f59e0b22',
                                color: row.environment === 'production' ? '#22c55e' : '#f59e0b',
                              }}
                            >
                              {row.environment}
                            </span>
                          </td>
                          <td className="text-sm" style={{ color: 'var(--text-muted)' }}>
                            {row.last_assn_notification_type || '—'}
                            <div className="text-xs">{formatRelative(row.last_assn_event_at)}</div>
                          </td>
                          <td className="text-sm">
                            {formatCents(row.revenue_cents)}
                            {row.currency && row.currency !== 'USD' && (
                              <span className="text-xs ml-1" style={{ color: 'var(--text-muted)' }}>{row.currency}</span>
                            )}
                          </td>
                          <td>
                            <button
                              className="btn btn-sm"
                              onClick={() => setActionTarget(row)}
                            >
                              Manage
                            </button>
                          </td>
                        </tr>
                      )
                    })}
                  </tbody>
                </table>
              </div>
            )}

            {total > 50 && (
              <div className="flex justify-between items-center mt-4">
                <button
                  className="btn"
                  disabled={page === 0}
                  onClick={() => setPage(Math.max(0, page - 1))}
                >
                  ← Prev
                </button>
                <span className="text-sm" style={{ color: 'var(--text-secondary)' }}>
                  Page {page + 1} of {Math.ceil(total / 50)}
                </span>
                <button
                  className="btn"
                  disabled={(page + 1) * 50 >= total}
                  onClick={() => setPage(page + 1)}
                >
                  Next →
                </button>
              </div>
            )}
          </>
        )}

        {actionTarget && (
          <SubscriberActionModal
            row={actionTarget}
            onClose={() => setActionTarget(null)}
            onMutated={() => { setActionTarget(null); load() }}
          />
        )}
      </div>
    </AdminShell>
  )
}

// Modal that surfaces the four mutating actions for one subscriber:
// grant_premium / revoke_premium / extend_trial / mark_refund_acknowledged
// + add a free-form note. Each action lands in subscription_grants AND
// admin_audit_log per MONETIZATION_AGENT invariant 30.
function SubscriberActionModal({
  row,
  onClose,
  onMutated,
}: {
  row: SubscriberRow
  onClose: () => void
  onMutated: () => void
}) {
  const [action, setAction] = useState<'grant' | 'revoke' | 'extend' | 'refund_ack' | 'note'>('note')
  const [reason, setReason] = useState('')
  const [extraDays, setExtraDays] = useState<number>(7)
  const [expiresAt, setExpiresAt] = useState<string>('')
  const [transactionId, setTransactionId] = useState<string>(row.original_transaction_id || '')
  const [submitting, setSubmitting] = useState(false)
  const [resultMsg, setResultMsg] = useState<string | null>(null)
  const [errorMsg, setErrorMsg] = useState<string | null>(null)

  async function submit() {
    setSubmitting(true)
    setResultMsg(null)
    setErrorMsg(null)
    try {
      let endpoint: string
      let payload: Record<string, unknown>

      switch (action) {
        case 'grant':
          endpoint = 'grant_premium_to_user'
          payload = {
            user_id: row.user_id,
            reason: reason.trim() || 'CMS comp grant',
            expires_at: expiresAt ? new Date(expiresAt).toISOString() : null,
          }
          break
        case 'revoke':
          endpoint = 'revoke_premium_from_user'
          payload = { user_id: row.user_id, reason: reason.trim() || 'CMS comp revoke' }
          break
        case 'extend':
          endpoint = 'extend_trial'
          payload = {
            user_id: row.user_id,
            extra_days: extraDays,
            reason: reason.trim() || 'CMS trial extension',
          }
          break
        case 'refund_ack':
          endpoint = 'mark_refund_acknowledged'
          payload = {
            user_id: row.user_id,
            transaction_id: transactionId.trim() || null,
            reason: reason.trim() || 'CMS refund ack',
          }
          break
        case 'note':
          endpoint = 'update_subscription_note'
          payload = { user_id: row.user_id, note: reason.trim() }
          break
      }

      const res = await adminApi(endpoint, payload)
      setResultMsg(`Action recorded${res?.note_id ? ` (note ${res.note_id.slice(0, 8)})` : ''}.`)
      setTimeout(onMutated, 700)
    } catch (err) {
      setErrorMsg(err instanceof Error ? err.message : 'Action failed')
    } finally {
      setSubmitting(false)
    }
  }

  return (
    <div
      style={{
        position: 'fixed', inset: 0, background: 'rgba(0,0,0,0.6)',
        display: 'flex', alignItems: 'center', justifyContent: 'center', zIndex: 100,
      }}
      onClick={onClose}
    >
      <div
        className="card"
        style={{ maxWidth: 540, width: '90%', maxHeight: '85vh', overflowY: 'auto' }}
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex justify-between items-start mb-4">
          <div>
            <h3 className="text-lg font-semibold" style={{ color: 'var(--text-primary)' }}>
              Manage subscription
            </h3>
            <div className="text-sm mt-1" style={{ color: 'var(--text-secondary)' }}>
              {row.user_profiles?.email || row.user_id}
            </div>
            <div className="text-xs mt-1" style={{ color: 'var(--text-muted)' }}>
              {tierLabel(row.tier)} · {statusBadge(row.status).label} · {row.environment}
            </div>
          </div>
          <button onClick={onClose} className="btn btn-sm">✕</button>
        </div>

        <div className="mb-4">
          <label className="block text-xs font-medium mb-2" style={{ color: 'var(--text-secondary)' }}>
            Action
          </label>
          <div className="flex flex-wrap gap-2">
            {[
              { id: 'note',       label: '📝 Add note' },
              { id: 'grant',      label: '🎁 Grant premium' },
              { id: 'revoke',     label: '🚫 Revoke premium' },
              { id: 'extend',     label: '⏳ Extend trial' },
              { id: 'refund_ack', label: '💸 Acknowledge refund' },
            ].map((opt) => (
              <button
                key={opt.id}
                type="button"
                className="btn btn-sm"
                style={{
                  background: action === opt.id ? 'var(--accent)' : undefined,
                  color: action === opt.id ? 'white' : undefined,
                }}
                onClick={() => setAction(opt.id as typeof action)}
              >
                {opt.label}
              </button>
            ))}
          </div>
        </div>

        {action === 'extend' && (
          <div className="mb-4">
            <label className="block text-xs font-medium mb-1" style={{ color: 'var(--text-secondary)' }}>
              Extra days (1–90)
            </label>
            <input
              type="number"
              min={1}
              max={90}
              className="input w-full"
              value={extraDays}
              onChange={(e) => setExtraDays(Math.max(1, Math.min(90, Number(e.target.value) || 1)))}
            />
          </div>
        )}

        {action === 'grant' && (
          <div className="mb-4">
            <label className="block text-xs font-medium mb-1" style={{ color: 'var(--text-secondary)' }}>
              Expires at (leave blank for lifetime)
            </label>
            <input
              type="datetime-local"
              className="input w-full"
              value={expiresAt}
              onChange={(e) => setExpiresAt(e.target.value)}
            />
          </div>
        )}

        {action === 'refund_ack' && (
          <div className="mb-4">
            <label className="block text-xs font-medium mb-1" style={{ color: 'var(--text-secondary)' }}>
              Transaction ID (Apple)
            </label>
            <input
              type="text"
              className="input w-full"
              value={transactionId}
              onChange={(e) => setTransactionId(e.target.value)}
              placeholder={row.original_transaction_id || 'e.g. 2000000123456789'}
            />
          </div>
        )}

        <div className="mb-4">
          <label className="block text-xs font-medium mb-1" style={{ color: 'var(--text-secondary)' }}>
            {action === 'note' ? 'Note' : 'Reason (optional)'}
          </label>
          <textarea
            className="input w-full"
            rows={3}
            value={reason}
            onChange={(e) => setReason(e.target.value)}
            placeholder={action === 'note' ? 'Free-form note for support history…' : 'e.g. App Review make-good, support escalation #1234'}
          />
        </div>

        {resultMsg && (
          <div
            className="card mb-4"
            style={{ background: 'rgba(34, 197, 94, 0.08)', borderColor: 'rgba(34, 197, 94, 0.4)' }}
          >
            <div className="text-sm font-semibold" style={{ color: '#22c55e' }}>{resultMsg}</div>
          </div>
        )}

        {errorMsg && (
          <div
            className="card mb-4"
            style={{ background: 'rgba(239, 68, 68, 0.08)', borderColor: '#ef4444' }}
          >
            <div className="text-sm font-semibold" style={{ color: '#ef4444' }}>{errorMsg}</div>
          </div>
        )}

        <div className="flex justify-end gap-2">
          <button onClick={onClose} className="btn">Cancel</button>
          <button
            onClick={submit}
            className="btn btn-primary"
            disabled={submitting || (action === 'note' && reason.trim().length === 0)}
          >
            {submitting ? 'Working…' : 'Submit'}
          </button>
        </div>
      </div>
    </div>
  )
}
