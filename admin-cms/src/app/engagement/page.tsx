'use client'

import { useEffect, useState } from 'react'
import AdminShell from '@/components/AdminShell'
import { adminApi } from '@/lib/api'

interface EngagementUser {
  user_id: string
  name: string | null
  username: string | null
  email: string | null
  engagement_score: number
  engagement_bucket: string
  workouts_7d: number
  workouts_30d: number
  friend_count: number
  challenges_joined: number
  current_streak: number
  total_workouts: number
  last_workout_date: string | null
  created_at: string
}

interface CohortRow {
  cohort_week: string
  cohort_size: number
  retained_w1: number
  retained_w2: number
  retained_w4: number
  retained_w8: number
  retained_w12: number
}

interface GeoData {
  total_with_tz: number
  region_counts: Record<string, number>
  timezone_counts: Record<string, number>
  top_timezones: { timezone: string; count: number; region: string }[]
}

const BUCKET_COLORS: Record<string, string> = {
  power_user: '#22c55e',
  engaged: '#3b82f6',
  casual: '#f59e0b',
  at_risk: '#f97316',
  churned: '#ef4444',
}

const BUCKET_LABELS: Record<string, string> = {
  power_user: 'Power Users',
  engaged: 'Engaged',
  casual: 'Casual',
  at_risk: 'At Risk',
  churned: 'Churned',
}

const REGION_COLORS: Record<string, string> = {
  America: '#3b82f6',
  Europe: '#22c55e',
  Asia: '#f59e0b',
  Pacific: '#8b5cf6',
  Australia: '#ec4899',
  Africa: '#f97316',
  Atlantic: '#06b6d4',
  Indian: '#84cc16',
  Arctic: '#64748b',
  Antarctica: '#94a3b8',
  Unknown: '#6b7280',
}

export default function EngagementPage() {
  const [activeTab, setActiveTab] = useState<'overview' | 'at_risk' | 'power' | 'cohorts' | 'funnel' | 'geo'>('overview')
  const [overview, setOverview] = useState<{ total_users: number; avg_score: number; bucket_counts: Record<string, number> } | null>(null)
  const [atRiskUsers, setAtRiskUsers] = useState<EngagementUser[]>([])
  const [powerUsers, setPowerUsers] = useState<EngagementUser[]>([])
  const [cohorts, setCohorts] = useState<CohortRow[]>([])
  const [funnel, setFunnel] = useState<Record<string, number> | null>(null)
  const [geoData, setGeoData] = useState<GeoData | null>(null)
  const [loading, setLoading] = useState(true)

  useEffect(() => { loadOverview() }, [])

  async function loadOverview() {
    setLoading(true)
    try {
      const data = await adminApi('engagement_overview')
      setOverview(data)
    } catch (err) { console.error('Engagement load error:', err) }
    finally { setLoading(false) }
  }

  async function loadAtRisk() {
    try {
      const data = await adminApi('engagement_at_risk_users', { limit: 100 })
      setAtRiskUsers(data.users || [])
    } catch (err) { console.error(err) }
  }

  async function loadPower() {
    try {
      const data = await adminApi('engagement_power_users', { limit: 50 })
      setPowerUsers(data.users || [])
    } catch (err) { console.error(err) }
  }

  async function loadCohorts() {
    try {
      const data = await adminApi('engagement_cohort_matrix')
      setCohorts(data.cohorts || [])
    } catch (err) { console.error(err) }
  }

  async function loadFunnel() {
    try {
      const data = await adminApi('engagement_onboarding_funnel')
      setFunnel(data)
    } catch (err) { console.error(err) }
  }

  async function loadGeo() {
    try {
      const data = await adminApi('engagement_geo_heatmap')
      setGeoData(data)
    } catch (err) { console.error(err) }
  }

  function onTabChange(tab: typeof activeTab) {
    setActiveTab(tab)
    if (tab === 'at_risk' && atRiskUsers.length === 0) loadAtRisk()
    if (tab === 'power' && powerUsers.length === 0) loadPower()
    if (tab === 'cohorts' && cohorts.length === 0) loadCohorts()
    if (tab === 'funnel' && !funnel) loadFunnel()
    if (tab === 'geo' && !geoData) loadGeo()
  }

  function timeAgo(iso: string | null) {
    if (!iso) return 'Never'
    const diff = Date.now() - new Date(iso).getTime()
    const d = Math.floor(diff / 86400000)
    if (d === 0) return 'Today'
    if (d === 1) return 'Yesterday'
    if (d < 7) return `${d}d ago`
    if (d < 30) return `${Math.floor(d / 7)}w ago`
    return `${Math.floor(d / 30)}mo ago`
  }

  const tabs = [
    { key: 'overview' as const, label: 'Overview' },
    { key: 'at_risk' as const, label: 'At Risk' },
    { key: 'power' as const, label: 'Power Users' },
    { key: 'cohorts' as const, label: 'Retention Cohorts' },
    { key: 'funnel' as const, label: 'Onboarding Funnel' },
    { key: 'geo' as const, label: 'Geo Heatmap' },
  ]

  return (
    <AdminShell>
      <div className="p-6 max-w-7xl mx-auto">
        <div className="flex items-center justify-between mb-6">
          <div>
            <h1 className="text-2xl font-bold" style={{ color: 'var(--text-primary)' }}>Engagement & Retention</h1>
            <p className="text-sm mt-1" style={{ color: 'var(--text-secondary)' }}>User health scoring, churn risk, retention cohorts, geographic distribution</p>
          </div>
          <button onClick={loadOverview} className="btn btn-ghost text-sm">Refresh</button>
        </div>

        {/* Tabs */}
        <div className="flex gap-1 mb-6 p-1 rounded-lg flex-wrap" style={{ background: 'var(--bg-tertiary)' }}>
          {tabs.map(t => (
            <button key={t.key} onClick={() => onTabChange(t.key)}
              className="px-4 py-2 rounded-md text-sm font-medium whitespace-nowrap"
              style={{ background: activeTab === t.key ? 'var(--bg-secondary)' : 'transparent', color: activeTab === t.key ? 'var(--text-primary)' : 'var(--text-muted)' }}>
              {t.label}
            </button>
          ))}
        </div>

        {loading && !overview ? (
          <div className="flex justify-center py-20"><div className="spinner" style={{ width: 32, height: 32 }} /></div>
        ) : (
          <>
            {/* OVERVIEW */}
            {activeTab === 'overview' && overview && (
              <>
                <div className="grid grid-cols-2 lg:grid-cols-4 gap-4 mb-6">
                  <div className="card">
                    <div className="text-2xl font-bold" style={{ color: 'var(--accent)' }}>{overview.total_users}</div>
                    <div className="text-xs mt-1" style={{ color: 'var(--text-secondary)' }}>Scored Users</div>
                  </div>
                  <div className="card">
                    <div className="text-2xl font-bold" style={{ color: 'var(--text-primary)' }}>{overview.avg_score}</div>
                    <div className="text-xs mt-1" style={{ color: 'var(--text-secondary)' }}>Avg Engagement Score</div>
                  </div>
                  <div className="card">
                    <div className="text-2xl font-bold" style={{ color: 'var(--success)' }}>{overview.bucket_counts?.power_user || 0}</div>
                    <div className="text-xs mt-1" style={{ color: 'var(--text-secondary)' }}>Power Users</div>
                  </div>
                  <div className="card">
                    <div className="text-2xl font-bold" style={{ color: 'var(--danger)' }}>
                      {(overview.bucket_counts?.at_risk || 0) + (overview.bucket_counts?.churned || 0)}
                    </div>
                    <div className="text-xs mt-1" style={{ color: 'var(--text-secondary)' }}>At Risk + Churned</div>
                  </div>
                </div>

                {/* Score Distribution */}
                <div className="card mb-6">
                  <h3 className="text-sm font-semibold mb-4" style={{ color: 'var(--text-primary)' }}>Score Distribution</h3>
                  <div className="space-y-3">
                    {['power_user', 'engaged', 'casual', 'at_risk', 'churned'].map(bucket => {
                      const count = overview.bucket_counts?.[bucket] || 0
                      const pct = overview.total_users > 0 ? (count / overview.total_users) * 100 : 0
                      return (
                        <div key={bucket} className="flex items-center gap-3">
                          <span className="text-xs font-medium w-28" style={{ color: BUCKET_COLORS[bucket] }}>{BUCKET_LABELS[bucket]}</span>
                          <div className="flex-1 h-6 rounded-full overflow-hidden" style={{ background: 'var(--bg-tertiary)' }}>
                            <div className="h-full rounded-full flex items-center pl-2" style={{ width: `${Math.max(pct, 2)}%`, background: BUCKET_COLORS[bucket] }}>
                              {pct > 8 && <span className="text-xs text-white font-medium">{count}</span>}
                            </div>
                          </div>
                          <span className="text-xs font-mono w-16 text-right" style={{ color: 'var(--text-secondary)' }}>{pct.toFixed(1)}%</span>
                        </div>
                      )
                    })}
                  </div>
                </div>

                {/* Score Range Legend */}
                <div className="card">
                  <h3 className="text-sm font-semibold mb-3" style={{ color: 'var(--text-primary)' }}>Scoring Guide</h3>
                  <div className="grid grid-cols-2 md:grid-cols-5 gap-3">
                    {[
                      { bucket: 'power_user', range: '80-100', desc: 'Daily users, social, multi-feature' },
                      { bucket: 'engaged', range: '50-79', desc: 'Regular workouts, some social' },
                      { bucket: 'casual', range: '25-49', desc: 'Occasional activity' },
                      { bucket: 'at_risk', range: '10-24', desc: 'Declining, 2+ weeks inactive' },
                      { bucket: 'churned', range: '0-9', desc: '30+ days inactive' },
                    ].map(s => (
                      <div key={s.bucket} className="p-3 rounded-lg" style={{ background: 'var(--bg-tertiary)', borderLeft: `3px solid ${BUCKET_COLORS[s.bucket]}` }}>
                        <div className="text-xs font-semibold" style={{ color: BUCKET_COLORS[s.bucket] }}>{BUCKET_LABELS[s.bucket]}</div>
                        <div className="text-xs font-mono" style={{ color: 'var(--text-primary)' }}>{s.range}</div>
                        <div className="text-xs mt-1" style={{ color: 'var(--text-muted)' }}>{s.desc}</div>
                      </div>
                    ))}
                  </div>
                </div>
              </>
            )}

            {/* AT RISK */}
            {activeTab === 'at_risk' && (
              <div className="card">
                <h3 className="text-sm font-semibold mb-4" style={{ color: 'var(--text-primary)' }}>At Risk & Churned Users ({atRiskUsers.length})</h3>
                {atRiskUsers.length === 0 ? (
                  <p className="text-sm py-8 text-center" style={{ color: 'var(--text-muted)' }}>Loading or no at-risk users found...</p>
                ) : (
                  <div className="overflow-x-auto">
                    <table>
                      <thead>
                        <tr>
                          <th>User</th><th>Score</th><th>Bucket</th><th>Last Workout</th>
                          <th>Workouts (30d)</th><th>Streak</th><th>Friends</th><th>Total</th>
                        </tr>
                      </thead>
                      <tbody>
                        {atRiskUsers.map(u => (
                          <tr key={u.user_id}>
                            <td>
                              <div className="font-medium text-sm">{u.name || u.username || 'Unknown'}</div>
                              <div className="text-xs" style={{ color: 'var(--text-muted)' }}>{u.email || ''}</div>
                            </td>
                            <td><span className="text-sm font-bold" style={{ color: BUCKET_COLORS[u.engagement_bucket] }}>{u.engagement_score}</span></td>
                            <td><span className="badge" style={{ background: `${BUCKET_COLORS[u.engagement_bucket]}20`, color: BUCKET_COLORS[u.engagement_bucket] }}>{BUCKET_LABELS[u.engagement_bucket]}</span></td>
                            <td className="text-sm" style={{ color: 'var(--text-muted)' }}>{timeAgo(u.last_workout_date)}</td>
                            <td className="text-sm text-center">{u.workouts_30d}</td>
                            <td className="text-sm text-center">{u.current_streak}</td>
                            <td className="text-sm text-center">{u.friend_count}</td>
                            <td className="text-sm text-center">{u.total_workouts}</td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </div>
                )}
              </div>
            )}

            {/* POWER USERS */}
            {activeTab === 'power' && (
              <div className="card">
                <h3 className="text-sm font-semibold mb-4" style={{ color: 'var(--text-primary)' }}>Power Users ({powerUsers.length})</h3>
                {powerUsers.length === 0 ? (
                  <p className="text-sm py-8 text-center" style={{ color: 'var(--text-muted)' }}>Loading...</p>
                ) : (
                  <div className="overflow-x-auto">
                    <table>
                      <thead>
                        <tr>
                          <th>#</th><th>User</th><th>Score</th><th>Workouts (7d)</th>
                          <th>Workouts (30d)</th><th>Streak</th><th>Friends</th><th>Challenges</th><th>Total</th>
                        </tr>
                      </thead>
                      <tbody>
                        {powerUsers.map((u, i) => (
                          <tr key={u.user_id}>
                            <td className="text-sm font-bold" style={{ color: 'var(--text-muted)' }}>{i + 1}</td>
                            <td>
                              <div className="font-medium text-sm">{u.name || u.username || 'Unknown'}</div>
                              <div className="text-xs" style={{ color: 'var(--text-muted)' }}>{u.email || ''}</div>
                            </td>
                            <td><span className="text-sm font-bold" style={{ color: 'var(--success)' }}>{u.engagement_score}</span></td>
                            <td className="text-sm text-center">{u.workouts_7d}</td>
                            <td className="text-sm text-center">{u.workouts_30d}</td>
                            <td className="text-sm text-center">{u.current_streak}</td>
                            <td className="text-sm text-center">{u.friend_count}</td>
                            <td className="text-sm text-center">{u.challenges_joined}</td>
                            <td className="text-sm text-center font-medium">{u.total_workouts}</td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </div>
                )}
              </div>
            )}

            {/* RETENTION COHORTS */}
            {activeTab === 'cohorts' && (
              <div className="card">
                <h3 className="text-sm font-semibold mb-2" style={{ color: 'var(--text-primary)' }}>Weekly Retention Cohorts</h3>
                <p className="text-xs mb-4" style={{ color: 'var(--text-muted)' }}>% of each signup cohort still active at week N (based on workout activity)</p>
                {cohorts.length === 0 ? (
                  <p className="text-sm py-8 text-center" style={{ color: 'var(--text-muted)' }}>Loading or no cohort data...</p>
                ) : (
                  <div className="overflow-x-auto">
                    <table>
                      <thead>
                        <tr>
                          <th>Cohort Week</th><th className="text-center">Size</th>
                          <th className="text-center">W1</th><th className="text-center">W2</th>
                          <th className="text-center">W4</th><th className="text-center">W8</th>
                          <th className="text-center">W12</th>
                        </tr>
                      </thead>
                      <tbody>
                        {cohorts.map(c => {
                          const pcts = [c.retained_w1, c.retained_w2, c.retained_w4, c.retained_w8, c.retained_w12]
                            .map(v => c.cohort_size > 0 ? Math.round((v / c.cohort_size) * 100) : 0)
                          return (
                            <tr key={c.cohort_week}>
                              <td className="text-xs font-mono">{c.cohort_week}</td>
                              <td className="text-center text-sm">{c.cohort_size}</td>
                              {pcts.map((pct, i) => (
                                <td key={i} className="text-center">
                                  <span className="inline-block px-2 py-1 rounded text-xs font-medium" style={{
                                    background: pct > 40 ? 'rgba(34,197,94,0.2)' : pct > 20 ? 'rgba(59,130,246,0.2)' : pct > 10 ? 'rgba(245,158,11,0.2)' : 'rgba(239,68,68,0.15)',
                                    color: pct > 40 ? '#22c55e' : pct > 20 ? '#3b82f6' : pct > 10 ? '#f59e0b' : '#ef4444',
                                  }}>
                                    {pct}%
                                  </span>
                                </td>
                              ))}
                            </tr>
                          )
                        })}
                      </tbody>
                    </table>
                  </div>
                )}
              </div>
            )}

            {/* ONBOARDING FUNNEL */}
            {activeTab === 'funnel' && funnel && (
              <div className="card">
                <h3 className="text-sm font-semibold mb-4" style={{ color: 'var(--text-primary)' }}>Onboarding Funnel</h3>
                {(() => {
                  const steps = [
                    { label: 'Signed Up', value: funnel.total_signups || 0 },
                    { label: 'Completed Onboarding', value: funnel.completed_onboarding || 0 },
                    { label: 'First Workout', value: funnel.first_workout || 0 },
                    { label: '3rd Workout', value: funnel.third_workout || 0 },
                    { label: '5th Workout', value: funnel.fifth_workout || 0 },
                    { label: 'Active Week 1', value: funnel.active_week_1 || 0 },
                    { label: 'Active Month 1', value: funnel.active_month_1 || 0 },
                  ]
                  const maxVal = steps[0].value || 1
                  return (
                    <div className="space-y-3">
                      {steps.map((step, i) => {
                        const pct = maxVal > 0 ? (step.value / maxVal) * 100 : 0
                        const dropoff = i > 0 && steps[i - 1].value > 0 ? Math.round((1 - step.value / steps[i - 1].value) * 100) : 0
                        return (
                          <div key={step.label}>
                            <div className="flex items-center justify-between mb-1">
                              <span className="text-sm font-medium" style={{ color: 'var(--text-primary)' }}>{step.label}</span>
                              <div className="flex items-center gap-3">
                                <span className="text-sm font-bold" style={{ color: 'var(--text-primary)' }}>{step.value.toLocaleString()}</span>
                                <span className="text-xs font-mono" style={{ color: 'var(--text-muted)' }}>{pct.toFixed(1)}%</span>
                                {i > 0 && dropoff > 0 && (
                                  <span className="text-xs" style={{ color: 'var(--danger)' }}>-{dropoff}%</span>
                                )}
                              </div>
                            </div>
                            <div className="h-5 rounded-full overflow-hidden" style={{ background: 'var(--bg-tertiary)' }}>
                              <div className="h-full rounded-full" style={{
                                width: `${Math.max(pct, 1)}%`,
                                background: `linear-gradient(90deg, var(--accent), ${pct > 50 ? 'var(--success)' : pct > 20 ? 'var(--warning)' : 'var(--danger)'})`,
                              }} />
                            </div>
                          </div>
                        )
                      })}
                    </div>
                  )
                })()}
              </div>
            )}

            {/* GEO HEATMAP */}
            {activeTab === 'geo' && (
              <>
                {!geoData ? (
                  <div className="flex justify-center py-20"><div className="spinner" style={{ width: 32, height: 32 }} /></div>
                ) : (
                  <>
                    <div className="grid grid-cols-2 lg:grid-cols-4 gap-4 mb-6">
                      <div className="card">
                        <div className="text-2xl font-bold" style={{ color: 'var(--accent)' }}>{geoData.total_with_tz}</div>
                        <div className="text-xs mt-1" style={{ color: 'var(--text-secondary)' }}>Users with Timezone</div>
                      </div>
                      <div className="card">
                        <div className="text-2xl font-bold" style={{ color: 'var(--text-primary)' }}>{Object.keys(geoData.region_counts).length}</div>
                        <div className="text-xs mt-1" style={{ color: 'var(--text-secondary)' }}>Regions</div>
                      </div>
                      <div className="card">
                        <div className="text-2xl font-bold" style={{ color: 'var(--text-primary)' }}>{Object.keys(geoData.timezone_counts).length}</div>
                        <div className="text-xs mt-1" style={{ color: 'var(--text-secondary)' }}>Unique Timezones</div>
                      </div>
                      <div className="card">
                        <div className="text-2xl font-bold" style={{ color: 'var(--success)' }}>{geoData.top_timezones[0]?.timezone.split('/')[1]?.replace(/_/g, ' ') || '-'}</div>
                        <div className="text-xs mt-1" style={{ color: 'var(--text-secondary)' }}>Top City</div>
                      </div>
                    </div>

                    {/* Region Breakdown */}
                    <div className="card mb-6">
                      <h3 className="text-sm font-semibold mb-4" style={{ color: 'var(--text-primary)' }}>Users by Region</h3>
                      <div className="space-y-3">
                        {Object.entries(geoData.region_counts)
                          .sort(([, a], [, b]) => b - a)
                          .map(([region, count]) => {
                            const pct = geoData.total_with_tz > 0 ? (count / geoData.total_with_tz) * 100 : 0
                            return (
                              <div key={region} className="flex items-center gap-3">
                                <span className="text-xs font-medium w-24" style={{ color: REGION_COLORS[region] || 'var(--text-primary)' }}>{region}</span>
                                <div className="flex-1 h-6 rounded-full overflow-hidden" style={{ background: 'var(--bg-tertiary)' }}>
                                  <div className="h-full rounded-full flex items-center pl-2" style={{
                                    width: `${Math.max(pct, 2)}%`, background: REGION_COLORS[region] || 'var(--accent)',
                                  }}>
                                    {pct > 10 && <span className="text-xs text-white font-medium">{count}</span>}
                                  </div>
                                </div>
                                <span className="text-xs font-mono w-16 text-right" style={{ color: 'var(--text-secondary)' }}>{pct.toFixed(1)}%</span>
                              </div>
                            )
                          })}
                      </div>
                    </div>

                    {/* Timezone Grid (Heatmap style) */}
                    <div className="card mb-6">
                      <h3 className="text-sm font-semibold mb-4" style={{ color: 'var(--text-primary)' }}>Timezone Heatmap</h3>
                      <div className="grid grid-cols-3 md:grid-cols-5 lg:grid-cols-6 gap-2">
                        {geoData.top_timezones.map(tz => {
                          const maxCount = geoData.top_timezones[0]?.count || 1
                          const intensity = Math.max(0.15, tz.count / maxCount)
                          const cityName = tz.timezone.split('/').pop()?.replace(/_/g, ' ') || tz.timezone
                          return (
                            <div key={tz.timezone} className="p-3 rounded-lg text-center" style={{
                              background: `rgba(37, 99, 235, ${intensity})`,
                              border: '1px solid var(--border)',
                            }}>
                              <div className="text-sm font-bold" style={{ color: 'white' }}>{tz.count}</div>
                              <div className="text-xs truncate" style={{ color: 'rgba(255,255,255,0.8)' }}>{cityName}</div>
                              <div className="text-xs" style={{ color: 'rgba(255,255,255,0.5)' }}>{tz.region}</div>
                            </div>
                          )
                        })}
                      </div>
                    </div>

                    {/* Full Timezone Table */}
                    <div className="card">
                      <h3 className="text-sm font-semibold mb-4" style={{ color: 'var(--text-primary)' }}>All Timezones</h3>
                      <div className="overflow-x-auto">
                        <table>
                          <thead>
                            <tr><th>Timezone</th><th>Region</th><th className="text-right">Users</th><th className="text-right">% of Total</th></tr>
                          </thead>
                          <tbody>
                            {geoData.top_timezones.map(tz => (
                              <tr key={tz.timezone}>
                                <td className="font-mono text-xs">{tz.timezone}</td>
                                <td><span className="badge" style={{ background: `${REGION_COLORS[tz.region] || 'var(--accent)'}20`, color: REGION_COLORS[tz.region] || 'var(--accent)' }}>{tz.region}</span></td>
                                <td className="text-right text-sm font-medium">{tz.count}</td>
                                <td className="text-right text-sm" style={{ color: 'var(--text-muted)' }}>
                                  {geoData.total_with_tz > 0 ? ((tz.count / geoData.total_with_tz) * 100).toFixed(1) : 0}%
                                </td>
                              </tr>
                            ))}
                          </tbody>
                        </table>
                      </div>
                    </div>
                  </>
                )}
              </>
            )}
          </>
        )}
      </div>
    </AdminShell>
  )
}
