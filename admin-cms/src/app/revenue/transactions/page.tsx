'use client'

// /revenue/transactions — admin list of IAP receipt events from the
// assn-webhook (App Store Server Notifications v2).
// Owner: MONETIZATION_AGENT.md (invariant 27 — Transactions tab; invariant 30
// — every event is persisted for forensic replay).

import { useEffect, useState, useCallback } from 'react'
import AdminShell from '@/components/AdminShell'
import { RevenueHeader } from '@/components/RevenueTabNav'
import { formatRelative } from '@/components/RevenueCards'
import { adminApi } from '@/lib/api'

interface UserMini {
  email?: string | null
  name?: string | null
  username?: string | null
}

interface TransactionRow {
  id: string
  user_id: string | null
  original_transaction_id: string
  transaction_id: string
  notification_type: string
  notification_subtype: string | null
  product_id: string | null
  environment: string
  is_signature_valid: boolean
  received_at: string
  user_profiles: UserMini | null
}

interface ListResponse {
  schema_deployed: boolean
  transactions: TransactionRow[]
  total: number
}

// Apple's canonical ASSN v2 notificationType vocabulary.
// Source: developer.apple.com/documentation/appstoreservernotifications/notificationtype
const NOTIFICATION_TYPES = [
  'SUBSCRIBED', 'DID_RENEW', 'DID_FAIL_TO_RENEW', 'DID_CHANGE_RENEWAL_PREF',
  'DID_CHANGE_RENEWAL_STATUS', 'EXPIRED', 'GRACE_PERIOD_EXPIRED', 'OFFER_REDEEMED',
  'PRICE_INCREASE', 'REFUND', 'REFUND_DECLINED', 'REFUND_REVERSED', 'RENEWAL_EXTENDED',
  'RENEWAL_EXTENSION', 'REVOKE', 'TEST', 'CONSUMPTION_REQUEST',
]

function notificationColor(type: string): string {
  if (type === 'SUBSCRIBED' || type === 'DID_RENEW' || type === 'OFFER_REDEEMED') return '#22c55e'
  if (type === 'REFUND' || type === 'REVOKE' || type === 'EXPIRED') return '#ef4444'
  if (type === 'DID_FAIL_TO_RENEW' || type === 'GRACE_PERIOD_EXPIRED' || type === 'PRICE_INCREASE') return '#f59e0b'
  if (type === 'TEST') return '#a855f7'
  return '#6b7280'
}

export default function TransactionsPage() {
  const [data, setData] = useState<ListResponse | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [filterType, setFilterType] = useState<string>('')
  const [filterEnv, setFilterEnv] = useState<string>('')
  const [page, setPage] = useState(0)

  const load = useCallback(async () => {
    setLoading(true)
    setError(null)
    try {
      const res: ListResponse = await adminApi('list_iap_receipts', {
        notification_type: filterType || undefined,
        environment: filterEnv || undefined,
        page,
        limit: 50,
      })
      setData(res)
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load transactions')
    } finally {
      setLoading(false)
    }
  }, [filterType, filterEnv, page])

  useEffect(() => {
    load()
  }, [load])

  const showRoadmap = data && !data.schema_deployed
  const showEmpty = data && data.schema_deployed && data.transactions.length === 0
  const total = data?.total ?? 0

  return (
    <AdminShell>
      <div className="p-6 max-w-7xl mx-auto">
        <RevenueHeader subtitle="App Store Server Notifications v2 events. Forensic-grade — every JWS payload is persisted (audit-only, never trusted to mutate without signature verification once Phase 1d ASSN_VERIFY_SIGNATURE flip lands)." />

        {showRoadmap && (
          <div
            className="card mb-6"
            style={{ background: 'rgba(245, 158, 11, 0.08)', borderColor: 'rgba(245, 158, 11, 0.4)' }}
          >
            <div className="text-sm font-semibold" style={{ color: '#f59e0b' }}>
              Subscription schema not yet deployed
            </div>
            <div className="text-sm mt-1" style={{ color: 'var(--text-secondary)' }}>
              Transactions populate after the assn-webhook starts receiving sandbox / production events.
            </div>
          </div>
        )}

        <div className="flex flex-wrap gap-3 mb-4 items-end">
          <div>
            <label className="block text-xs font-medium mb-1" style={{ color: 'var(--text-secondary)' }}>
              Notification type
            </label>
            <select
              className="input"
              value={filterType}
              onChange={(e) => { setFilterType(e.target.value); setPage(0) }}
            >
              <option value="">Any type</option>
              {NOTIFICATION_TYPES.map((t) => (
                <option key={t} value={t}>{t}</option>
              ))}
            </select>
          </div>

          <div>
            <label className="block text-xs font-medium mb-1" style={{ color: 'var(--text-secondary)' }}>
              Environment
            </label>
            <select
              className="input"
              value={filterEnv}
              onChange={(e) => { setFilterEnv(e.target.value); setPage(0) }}
            >
              <option value="">Any env</option>
              <option value="sandbox">Sandbox</option>
              <option value="production">Production</option>
            </select>
          </div>

          {(filterType || filterEnv) && (
            <button
              type="button"
              className="btn"
              onClick={() => { setFilterType(''); setFilterEnv(''); setPage(0) }}
            >
              Clear
            </button>
          )}
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
              Showing {data.transactions.length} of {total} {total === 1 ? 'event' : 'events'}
            </div>

            {showEmpty && (
              <div className="card text-center py-12">
                <div className="text-4xl mb-3">🧾</div>
                <div className="text-base font-medium mb-1" style={{ color: 'var(--text-primary)' }}>
                  No transactions yet
                </div>
                <div className="text-sm" style={{ color: 'var(--text-secondary)' }}>
                  Perform a sandbox purchase from a TestFlight build to see the first SUBSCRIBED event land here.
                </div>
              </div>
            )}

            {!showEmpty && (
              <div className="card p-0 overflow-hidden">
                <table>
                  <thead>
                    <tr>
                      <th>Received</th>
                      <th>Type</th>
                      <th>Subtype</th>
                      <th>Product</th>
                      <th>User</th>
                      <th>Original Tx ID</th>
                      <th>Env</th>
                      <th>Sig</th>
                    </tr>
                  </thead>
                  <tbody>
                    {data.transactions.map((row) => {
                      const color = notificationColor(row.notification_type)
                      return (
                        <tr key={row.id}>
                          <td className="text-sm" title={row.received_at}>{formatRelative(row.received_at)}</td>
                          <td>
                            <span
                              className="badge"
                              style={{ background: `${color}22`, color, borderColor: `${color}88`, fontSize: 11 }}
                            >
                              {row.notification_type}
                            </span>
                          </td>
                          <td className="text-xs" style={{ color: 'var(--text-muted)' }}>
                            {row.notification_subtype || '—'}
                          </td>
                          <td className="text-xs">{row.product_id || '—'}</td>
                          <td>
                            <div className="text-sm">
                              {row.user_profiles?.email || (
                                <span style={{ color: 'var(--text-muted)' }}>
                                  {row.user_id ? row.user_id.slice(0, 8) + '…' : 'unresolved'}
                                </span>
                              )}
                            </div>
                          </td>
                          <td className="text-xs font-mono" style={{ color: 'var(--text-muted)' }}>
                            {row.original_transaction_id ? row.original_transaction_id.slice(0, 14) + '…' : '—'}
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
                          <td>
                            {row.is_signature_valid ? (
                              <span className="badge" style={{ background: '#22c55e22', color: '#22c55e', fontSize: 10 }}>
                                ✓
                              </span>
                            ) : (
                              <span
                                className="badge"
                                style={{ background: 'transparent', color: 'var(--text-muted)', fontSize: 10 }}
                                title="Signature verification disabled (ASSN_VERIFY_SIGNATURE=false). Phase 1b audit-only mode."
                              >
                                audit
                              </span>
                            )}
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
      </div>
    </AdminShell>
  )
}
