'use client'

// Revenue tab — Overview (root /revenue route).
// Owner: MONETIZATION_AGENT.md (invariants 27 + 30).
//
// Renders the agent's roadmap when the subscriptions schema isn't deployed
// (Phase pre-1a). When `get_revenue_overview` returns `schema_deployed:true`
// the same components light up with real MRR / ARR / active / trial / churn
// from `revenue_daily_rollup`.
//
// Sub-tabs (Subscribers, Transactions, Grants, Experiments) are now full
// Next.js routes under /revenue/<sub>. The shared nav lives in
// components/RevenueTabNav so all five pages render the same chrome.

import { useEffect, useState } from 'react'
import AdminShell from '@/components/AdminShell'
import { RevenueHeader } from '@/components/RevenueTabNav'
import { KpiCard, SignalCard, formatCents } from '@/components/RevenueCards'
import { adminApi } from '@/lib/api'

type RoadmapItem = { phase: string; deliverable: string }

interface PreSchemaOverview {
  schema_deployed: false
  phase: 'pre-1a'
  message: string
  live_signals_available: {
    ad_session_log_rows_7d: number
  }
  roadmap: RoadmapItem[]
}

interface RollupRow {
  snapshot_date: string
  active_subscribers: number
  trial_active: number
  mrr_cents: number
  arr_cents: number
  new_subscribers: number
  churned_subscribers: number
  trial_started: number
  trial_converted: number
  refunds_count: number
  refunds_cents: number
}

interface DeployedOverview {
  schema_deployed: true
  phase: string
  today_iso: string
  rollup_30d: RollupRow[]
}

type OverviewResponse = PreSchemaOverview | DeployedOverview

export default function RevenuePage() {
  const [overview, setOverview] = useState<OverviewResponse | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    let cancelled = false
    setLoading(true)
    adminApi('get_revenue_overview')
      .then((data: OverviewResponse) => {
        if (!cancelled) setOverview(data)
      })
      .catch((err: Error) => {
        if (!cancelled) setError(err.message || 'Failed to load revenue overview')
      })
      .finally(() => {
        if (!cancelled) setLoading(false)
      })
    return () => {
      cancelled = true
    }
  }, [])

  return (
    <AdminShell>
      <div className="p-6 max-w-7xl mx-auto">
        <RevenueHeader />

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

        {!loading && !error && overview && (
          overview.schema_deployed
            ? <DeployedOverviewView overview={overview} />
            : <PreSchemaOverviewView overview={overview} />
        )}
      </div>
    </AdminShell>
  )
}

function PreSchemaOverviewView({ overview }: { overview: PreSchemaOverview }) {
  return (
    <div className="space-y-6">
      <div
        className="card"
        style={{
          background: 'rgba(245, 158, 11, 0.08)',
          borderColor: 'rgba(245, 158, 11, 0.4)',
        }}
      >
        <div className="flex items-start gap-3">
          <div className="text-2xl">⚠️</div>
          <div>
            <div className="text-sm font-semibold" style={{ color: '#f59e0b' }}>
              Subscription schema not yet deployed
            </div>
            <div className="text-sm mt-1" style={{ color: 'var(--text-secondary)' }}>
              {overview.message}
            </div>
            <div className="text-xs mt-2" style={{ color: 'var(--text-muted)' }}>
              The Revenue tab will light up automatically when Phase 1a ships. Until then, this
              page renders the canonical roadmap so the build sequence stays visible.
            </div>
          </div>
        </div>
      </div>

      <section>
        <h2 className="text-lg font-semibold mb-3" style={{ color: 'var(--text-primary)' }}>
          Live signals available today
        </h2>
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
          <SignalCard
            label="Ad session log rows (7d)"
            value={overview.live_signals_available.ad_session_log_rows_7d}
            note="dev_session_logs — feeds AdMob impression / load / click history"
          />
          <SignalCard
            label="StoreKit Manager"
            value="wired (iOS)"
            note="Fit33/StoreKitManager.swift — purchase + restore + listener live"
          />
          <SignalCard
            label="PremiumManager"
            value="server-aware"
            note="UserManager.swift — refreshFromServer() observability live; flip in Phase 2"
          />
          <SignalCard
            label="AdMob"
            value="prod-wired"
            note="AdManager.swift — interstitial + rewarded + ATT + COPPA gates"
          />
        </div>
      </section>

      <section>
        <h2 className="text-lg font-semibold mb-3" style={{ color: 'var(--text-primary)' }}>
          Phased rollout
        </h2>
        <div className="card p-0 overflow-hidden">
          <table>
            <thead>
              <tr>
                <th style={{ width: 80 }}>Phase</th>
                <th>Deliverable</th>
              </tr>
            </thead>
            <tbody>
              {overview.roadmap.map((item) => (
                <tr key={item.phase}>
                  <td>
                    <span className="badge badge-info">{item.phase}</span>
                  </td>
                  <td className="text-sm" style={{ color: 'var(--text-secondary)' }}>
                    {item.deliverable}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </section>

      <section>
        <h2 className="text-lg font-semibold mb-3" style={{ color: 'var(--text-primary)' }}>
          Pricing strategy (current target)
        </h2>
        <div className="card p-0 overflow-hidden">
          <table>
            <thead>
              <tr>
                <th>Tier</th>
                <th>Price</th>
                <th>Annualized</th>
                <th>Trial</th>
                <th>Notes</th>
              </tr>
            </thead>
            <tbody>
              <tr>
                <td><strong>Pro Monthly</strong></td>
                <td>$9.99/mo</td>
                <td>$119.88</td>
                <td>—</td>
                <td className="text-sm" style={{ color: 'var(--text-secondary)' }}>
                  Discovery channel — lower-friction &ldquo;try it&rdquo;
                </td>
              </tr>
              <tr>
                <td><strong>Pro Yearly</strong></td>
                <td>$59.99/yr</td>
                <td>$59.99</td>
                <td>7 days</td>
                <td className="text-sm" style={{ color: 'var(--text-secondary)' }}>
                  Anchor &ldquo;Best Value&rdquo; — 50% off vs monthly annualized
                </td>
              </tr>
              <tr>
                <td><strong>Pro Lifetime</strong></td>
                <td>$199 once</td>
                <td>—</td>
                <td>—</td>
                <td className="text-sm" style={{ color: 'var(--text-secondary)' }}>
                  Future tier; conversion lever for high-LTV signal users
                </td>
              </tr>
              <tr>
                <td><strong>Free</strong></td>
                <td>$0</td>
                <td>$0</td>
                <td>—</td>
                <td className="text-sm" style={{ color: 'var(--text-secondary)' }}>
                  Core workouts + dashboard + history (last 30 days)
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>
    </div>
  )
}

function DeployedOverviewView({ overview }: { overview: DeployedOverview }) {
  const today = overview.rollup_30d[0]
  const yesterday = overview.rollup_30d[1]

  function delta(a?: number, b?: number) {
    if (a === undefined || b === undefined) return null
    return a - b
  }

  return (
    <div className="space-y-6">
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-5 gap-4">
        <KpiCard
          label="MRR"
          value={formatCents(today?.mrr_cents)}
          delta={delta(today?.mrr_cents, yesterday?.mrr_cents)}
          deltaFormat="cents"
          color="#22c55e"
        />
        <KpiCard
          label="ARR"
          value={formatCents(today?.arr_cents)}
          color="#3b82f6"
        />
        <KpiCard
          label="Active Subscribers"
          value={today?.active_subscribers ?? '—'}
          delta={delta(today?.active_subscribers, yesterday?.active_subscribers)}
          color="#6366f1"
        />
        <KpiCard
          label="Trial Active"
          value={today?.trial_active ?? '—'}
          color="#f59e0b"
        />
        <KpiCard
          label="Refunds (30d)"
          value={overview.rollup_30d.reduce((a, r) => a + (r.refunds_count || 0), 0)}
          color="#ef4444"
        />
      </div>

      <section>
        <h2 className="text-lg font-semibold mb-3" style={{ color: 'var(--text-primary)' }}>
          Daily rollup (last 30 days)
        </h2>
        <div className="card p-0 overflow-hidden">
          <table>
            <thead>
              <tr>
                <th>Date</th>
                <th>Active</th>
                <th>Trial</th>
                <th>New</th>
                <th>Churned</th>
                <th>Trial → Paid</th>
                <th>Refunds</th>
                <th>MRR</th>
              </tr>
            </thead>
            <tbody>
              {overview.rollup_30d.length === 0 && (
                <tr>
                  <td colSpan={8} className="text-center text-sm py-8" style={{ color: 'var(--text-muted)' }}>
                    No rollup rows yet. The pg_cron job runs nightly at 03:00 UTC; rows will appear after the first scheduled run with real subscription data.
                  </td>
                </tr>
              )}
              {overview.rollup_30d.map((row) => (
                <tr key={row.snapshot_date}>
                  <td className="text-sm">{row.snapshot_date}</td>
                  <td>{row.active_subscribers}</td>
                  <td>{row.trial_active}</td>
                  <td>{row.new_subscribers}</td>
                  <td>{row.churned_subscribers}</td>
                  <td>
                    {row.trial_converted}/{row.trial_started}
                  </td>
                  <td>
                    {row.refunds_count > 0 ? (
                      <span className="badge badge-warning">{row.refunds_count}</span>
                    ) : (
                      <span style={{ color: 'var(--text-muted)' }}>—</span>
                    )}
                  </td>
                  <td>{formatCents(row.mrr_cents)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </section>
    </div>
  )
}
