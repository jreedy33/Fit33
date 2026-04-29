'use client'

// /revenue/grants — admin audit log of subscription_grants rows.
// Owner: MONETIZATION_AGENT.md (invariant 27 — Grants tab; invariant 30
// — every grant is audit-logged with the issuing admin's identity).
//
// This is the read-only history view. New grants are issued from
// /revenue/subscribers via the per-row "Manage" modal — that flow lands
// rows here automatically.

import { useEffect, useState, useCallback } from 'react'
import AdminShell from '@/components/AdminShell'
import { RevenueHeader } from '@/components/RevenueTabNav'
import { formatDateTime, formatRelative, grantKindBadge } from '@/components/RevenueCards'
import { adminApi } from '@/lib/api'

interface UserMini {
  email?: string | null
  name?: string | null
  username?: string | null
}

interface GrantRow {
  id: string
  user_id: string
  kind: string
  reason: string | null
  expires_at: string | null
  trial_extra_days: number | null
  iap_receipt_id: string | null
  admin_user_id: string | null
  admin_email: string | null
  created_at: string
  user_profiles: UserMini | null
}

interface ListResponse {
  schema_deployed: boolean
  grants: GrantRow[]
  total: number
}

const KIND_OPTIONS = ['comp_grant', 'comp_revoke', 'trial_extension', 'refund', 'refund_ack', 'note']

export default function GrantsPage() {
  const [data, setData] = useState<ListResponse | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [filterKind, setFilterKind] = useState<string>('')
  const [page, setPage] = useState(0)

  const load = useCallback(async () => {
    setLoading(true)
    setError(null)
    try {
      const res: ListResponse = await adminApi('list_grants', {
        kind: filterKind || undefined,
        page,
        limit: 50,
      })
      setData(res)
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load grants')
    } finally {
      setLoading(false)
    }
  }, [filterKind, page])

  useEffect(() => {
    load()
  }, [load])

  const showRoadmap = data && !data.schema_deployed
  const showEmpty = data && data.schema_deployed && data.grants.length === 0
  const total = data?.total ?? 0

  return (
    <AdminShell>
      <div className="p-6 max-w-7xl mx-auto">
        <RevenueHeader subtitle="Audit log of comps, trial extensions, refund acknowledgments, and admin notes. Issue new grants from /revenue/subscribers → Manage." />

        {showRoadmap && (
          <div
            className="card mb-6"
            style={{ background: 'rgba(245, 158, 11, 0.08)', borderColor: 'rgba(245, 158, 11, 0.4)' }}
          >
            <div className="text-sm font-semibold" style={{ color: '#f59e0b' }}>
              Subscription schema not yet deployed
            </div>
            <div className="text-sm mt-1" style={{ color: 'var(--text-secondary)' }}>
              Grants populate after the first admin action runs against a user with subscription state.
            </div>
          </div>
        )}

        <div className="flex flex-wrap gap-3 mb-4 items-end">
          <div>
            <label className="block text-xs font-medium mb-1" style={{ color: 'var(--text-secondary)' }}>
              Kind
            </label>
            <select
              className="input"
              value={filterKind}
              onChange={(e) => { setFilterKind(e.target.value); setPage(0) }}
            >
              <option value="">Any kind</option>
              {KIND_OPTIONS.map((k) => (
                <option key={k} value={k}>{grantKindBadge(k).label}</option>
              ))}
            </select>
          </div>

          {filterKind && (
            <button
              type="button"
              className="btn"
              onClick={() => { setFilterKind(''); setPage(0) }}
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
              Showing {data.grants.length} of {total} {total === 1 ? 'grant' : 'grants'}
            </div>

            {showEmpty && (
              <div className="card text-center py-12">
                <div className="text-4xl mb-3">🎁</div>
                <div className="text-base font-medium mb-1" style={{ color: 'var(--text-primary)' }}>
                  No grants yet
                </div>
                <div className="text-sm" style={{ color: 'var(--text-secondary)' }}>
                  Issue a comp / trial extension / refund-ack from a subscriber row to populate this log.
                </div>
              </div>
            )}

            {!showEmpty && (
              <div className="card p-0 overflow-hidden">
                <table>
                  <thead>
                    <tr>
                      <th>When</th>
                      <th>Kind</th>
                      <th>User</th>
                      <th>Issued by</th>
                      <th>Detail</th>
                      <th>Reason</th>
                    </tr>
                  </thead>
                  <tbody>
                    {data.grants.map((row) => {
                      const kb = grantKindBadge(row.kind)
                      return (
                        <tr key={row.id}>
                          <td className="text-sm" title={row.created_at}>
                            {formatRelative(row.created_at)}
                          </td>
                          <td>
                            <span
                              className="badge"
                              style={{ background: `${kb.color}22`, color: kb.color, borderColor: `${kb.color}88` }}
                            >
                              {kb.label}
                            </span>
                          </td>
                          <td>
                            <div className="text-sm">
                              {row.user_profiles?.email || row.user_id.slice(0, 8) + '…'}
                            </div>
                            {row.user_profiles?.name && (
                              <div className="text-xs" style={{ color: 'var(--text-muted)' }}>
                                {row.user_profiles.name}
                              </div>
                            )}
                          </td>
                          <td className="text-sm">
                            {row.admin_email || (
                              <span style={{ color: 'var(--text-muted)' }} title="Written by webhook (refund auto-flow)">
                                system
                              </span>
                            )}
                          </td>
                          <td className="text-xs">
                            {row.expires_at && (
                              <div>expires: {formatDateTime(row.expires_at)}</div>
                            )}
                            {row.trial_extra_days !== null && (
                              <div>+{row.trial_extra_days} day{row.trial_extra_days === 1 ? '' : 's'}</div>
                            )}
                            {row.iap_receipt_id && (
                              <div style={{ color: 'var(--text-muted)' }}>
                                receipt: {row.iap_receipt_id.slice(0, 8)}…
                              </div>
                            )}
                            {!row.expires_at && row.trial_extra_days === null && !row.iap_receipt_id && (
                              <span style={{ color: 'var(--text-muted)' }}>—</span>
                            )}
                          </td>
                          <td className="text-sm" style={{ maxWidth: 360 }}>
                            <div style={{
                              whiteSpace: 'normal',
                              overflow: 'hidden',
                              display: '-webkit-box',
                              WebkitLineClamp: 2,
                              WebkitBoxOrient: 'vertical',
                            }}>
                              {row.reason || <span style={{ color: 'var(--text-muted)' }}>—</span>}
                            </div>
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
