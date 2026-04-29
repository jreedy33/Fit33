'use client'

// Revenue tab — owner: MONETIZATION_AGENT.md.
// Today this page renders the agent's roadmap when the subscriptions
// schema isn't deployed yet (Phase pre-1a). When `get_revenue_overview`
// returns `schema_deployed: true`, the same components light up with real
// MRR / ARR / active / trial / churn from `revenue_daily_rollup`.
//
// The 5 sub-views (Overview, Subscribers, Transactions, Grants,
// Experiments) per MONETIZATION_AGENT invariant 27 will each get their
// own page under `/revenue/<sub>` as Phase 2+ ships. Today only Overview
// exists; the other tabs render a "coming in Phase N" placeholder so the
// nav contract is established without faking data.

import { useEffect, useState } from 'react'
import AdminShell from '@/components/AdminShell'
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

type SubTab = 'overview' | 'subscribers' | 'transactions' | 'grants' | 'experiments'

const SUB_TABS: Array<{ id: SubTab; label: string; icon: string; phaseGate: string }> = [
  { id: 'overview',     label: 'Overview',     icon: '💰', phaseGate: 'Phase 2'  },
  { id: 'subscribers',  label: 'Subscribers',  icon: '👥', phaseGate: 'Phase 3'  },
  { id: 'transactions', label: 'Transactions', icon: '🧾', phaseGate: 'Phase 3'  },
  { id: 'grants',       label: 'Grants',       icon: '🎁', phaseGate: 'Phase 4'  },
  { id: 'experiments',  label: 'Experiments',  icon: '🧪', phaseGate: 'Phase 5'  },
]

export default function RevenuePage() {
  const [overview, setOverview] = useState<OverviewResponse | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [activeTab, setActiveTab] = useState<SubTab>('overview')

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
        <header className="mb-6">
          <div className="flex items-center justify-between mb-2">
            <div>
              <h1 className="text-2xl font-bold" style={{ color: 'var(--text-primary)' }}>Revenue</h1>
              <p className="text-sm mt-1" style={{ color: 'var(--text-secondary)' }}>
                Subscriptions, IAP, ad revenue, comp grants. Owner:{' '}
                <code style={{ color: 'var(--accent)' }}>MONETIZATION_AGENT.md</code>
              </p>
            </div>
          </div>

          <nav className="flex gap-2 border-b mt-4" style={{ borderColor: 'var(--border)' }}>
            {SUB_TABS.map((tab) => {
              const isActive = activeTab === tab.id
              return (
                <button
                  key={tab.id}
                  onClick={() => setActiveTab(tab.id)}
                  className="px-4 py-2.5 text-sm font-medium border-b-2 transition-colors"
                  style={{
                    borderColor: isActive ? 'var(--accent)' : 'transparent',
                    color: isActive ? 'var(--accent)' : 'var(--text-secondary)',
                  }}
                >
                  <span className="mr-2">{tab.icon}</span>
                  {tab.label}
                </button>
              )
            })}
          </nav>
        </header>

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
          <>
            {activeTab === 'overview' && <OverviewTab overview={overview} />}
            {activeTab !== 'overview' && (
              <SubTabPlaceholder
                tab={SUB_TABS.find((t) => t.id === activeTab)!}
                schemaDeployed={overview.schema_deployed}
              />
            )}
          </>
        )}
      </div>
    </AdminShell>
  )
}

function OverviewTab({ overview }: { overview: OverviewResponse }) {
  if (!overview.schema_deployed) {
    return <PreSchemaOverviewView overview={overview} />
  }
  return <DeployedOverviewView overview={overview} />
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
            value="always-premium"
            note="UserManager.swift — flips to server-driven in Phase 1c"
          />
          <SignalCard
            label="AdMob"
            value="prod-wired"
            note="AdManager.swift — interstitial + rewarded + ATT + #if DEBUG guard"
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

  function formatCents(cents: number | undefined) {
    if (cents === undefined) return '—'
    return `$${(cents / 100).toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`
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

function SubTabPlaceholder({
  tab,
  schemaDeployed,
}: {
  tab: { id: SubTab; label: string; icon: string; phaseGate: string }
  schemaDeployed: boolean
}) {
  return (
    <div className="card text-center py-16">
      <div className="text-5xl mb-4">{tab.icon}</div>
      <div className="text-lg font-semibold mb-1" style={{ color: 'var(--text-primary)' }}>
        {tab.label}
      </div>
      <div className="text-sm mb-3" style={{ color: 'var(--text-secondary)' }}>
        {schemaDeployed
          ? `${tab.label} ships in ${tab.phaseGate}.`
          : `${tab.label} ships in ${tab.phaseGate} (after Phase 1 schema deploy).`}
      </div>
      <div className="text-xs" style={{ color: 'var(--text-muted)' }}>
        See <code style={{ color: 'var(--accent)' }}>MONETIZATION_AGENT.md</code> § Phased Rollout.
      </div>
    </div>
  )
}

function SignalCard({ label, value, note }: { label: string; value: number | string; note: string }) {
  return (
    <div className="card">
      <div className="text-xs font-medium mb-1" style={{ color: 'var(--text-secondary)' }}>
        {label}
      </div>
      <div className="text-xl font-bold mb-2" style={{ color: 'var(--text-primary)' }}>
        {typeof value === 'number' ? value.toLocaleString() : value}
      </div>
      <div className="text-xs" style={{ color: 'var(--text-muted)' }}>
        {note}
      </div>
    </div>
  )
}

function KpiCard({
  label,
  value,
  delta,
  deltaFormat,
  color,
}: {
  label: string
  value: number | string
  delta?: number | null
  deltaFormat?: 'cents' | 'count'
  color: string
}) {
  const showDelta = delta !== null && delta !== undefined && delta !== 0
  const deltaPositive = (delta ?? 0) > 0
  const deltaLabel = showDelta
    ? deltaFormat === 'cents'
      ? `${deltaPositive ? '+' : ''}$${((delta ?? 0) / 100).toFixed(2)}`
      : `${deltaPositive ? '+' : ''}${delta}`
    : null

  return (
    <div className="card">
      <div className="flex items-center gap-3">
        <div
          className="w-10 h-10 rounded-xl flex items-center justify-center text-lg shrink-0"
          style={{ background: `${color}18`, color }}
        >
          ●
        </div>
        <div className="flex-1 min-w-0">
          <div className="text-xs font-medium" style={{ color: 'var(--text-secondary)' }}>
            {label}
          </div>
          <div className="text-xl font-bold truncate" style={{ color: 'var(--text-primary)' }}>
            {typeof value === 'number' ? value.toLocaleString() : value}
          </div>
          {deltaLabel && (
            <div
              className="text-xs font-medium mt-0.5"
              style={{ color: deltaPositive ? '#22c55e' : '#ef4444' }}
            >
              {deltaLabel} vs yesterday
            </div>
          )}
        </div>
      </div>
    </div>
  )
}
