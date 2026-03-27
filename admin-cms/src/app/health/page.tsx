'use client'

import { useEffect, useRef, useState } from 'react'
import AdminShell from '@/components/AdminShell'
import { adminApi } from '@/lib/api'

interface TableSize {
  table_name: string
  row_estimate: number
  total_bytes: number
  index_bytes: number
  toast_bytes: number
  table_bytes: number
}

interface IndexEntry {
  table_name: string
  index_name: string
  index_size: number
  idx_scan: number
  idx_tup_read: number
  idx_tup_fetch: number
}

interface RpcStat {
  function_name: string
  calls: number
  total_time_ms: number
  self_time_ms: number
  avg_time_ms: number
}

function formatBytes(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`
  if (bytes < 1024 * 1024 * 1024) return `${(bytes / 1024 / 1024).toFixed(1)} MB`
  return `${(bytes / 1024 / 1024 / 1024).toFixed(2)} GB`
}

export default function HealthPage() {
  const [tables, setTables] = useState<TableSize[]>([])
  const [connections, setConnections] = useState<Record<string, unknown> | null>(null)
  const [indexes, setIndexes] = useState<IndexEntry[]>([])
  const [rpcStats, setRpcStats] = useState<RpcStat[]>([])
  const [pushPipeline, setPushPipeline] = useState<Record<string, unknown> | null>(null)
  const [errorRates, setErrorRates] = useState<{ crashes_30d: number; bugs_30d: number; daily_crashes: Record<string, number>; daily_bugs: Record<string, number> } | null>(null)
  const [loading, setLoading] = useState(true)
  const [autoRefresh, setAutoRefresh] = useState(false)
  const [activeSection, setActiveSection] = useState<'overview' | 'tables' | 'push' | 'rpc' | 'indexes' | 'errors'>('overview')
  const [tableSortKey, setTableSortKey] = useState<'total_bytes' | 'row_estimate' | 'table_name'>('total_bytes')
  const [tableSortAsc, setTableSortAsc] = useState(false)
  const intervalRef = useRef<NodeJS.Timeout | null>(null)

  useEffect(() => {
    loadAll()
    return () => { if (intervalRef.current) clearInterval(intervalRef.current) }
  }, [])

  useEffect(() => {
    if (intervalRef.current) clearInterval(intervalRef.current)
    if (autoRefresh) {
      intervalRef.current = setInterval(loadAll, 30000)
    }
  }, [autoRefresh])

  async function loadAll() {
    setLoading(true)
    try {
      const [tablesData, connData, idxData, rpcData, pushData, errData] = await Promise.all([
        adminApi('health_table_sizes').catch(() => ({ tables: [] })),
        adminApi('health_connections').catch(() => null),
        adminApi('health_index_usage').catch(() => ({ indexes: [] })),
        adminApi('health_rpc_stats').catch(() => ({ functions: [] })),
        adminApi('health_push_pipeline').catch(() => null),
        adminApi('health_error_rates').catch(() => null),
      ])
      setTables(tablesData.tables || [])
      setConnections(connData)
      setIndexes(idxData.indexes || [])
      setRpcStats(rpcData.functions || [])
      setPushPipeline(pushData)
      setErrorRates(errData)
    } catch (err) { console.error('Health load error:', err) }
    finally { setLoading(false) }
  }

  const totalDbSize = tables.reduce((a, t) => a + (t.total_bytes || 0), 0)
  const totalRows = tables.reduce((a, t) => a + (t.row_estimate || 0), 0)
  const activeConns = (connections?.active as number) || 0
  const maxConns = (connections?.max_connections as number) || 0
  const queue = (pushPipeline as Record<string, unknown>)?.queue as Record<string, unknown> | undefined
  const queuePending = (queue?.pending as number) || 0
  const queueFailed = (queue?.failed_24h as number) || 0
  const unusedIndexes = indexes.filter(i => i.idx_scan === 0)

  const sortedTables = [...tables].sort((a, b) => {
    const key = tableSortKey
    if (key === 'table_name') return tableSortAsc ? a.table_name.localeCompare(b.table_name) : b.table_name.localeCompare(a.table_name)
    return tableSortAsc ? (a[key] || 0) - (b[key] || 0) : (b[key] || 0) - (a[key] || 0)
  })

  const sections = [
    { key: 'overview' as const, label: 'Overview' },
    { key: 'tables' as const, label: `Tables (${tables.length})` },
    { key: 'push' as const, label: 'Push Pipeline' },
    { key: 'rpc' as const, label: `RPCs (${rpcStats.length})` },
    { key: 'indexes' as const, label: `Indexes (${unusedIndexes.length} unused)` },
    { key: 'errors' as const, label: 'Error Rates' },
  ]

  return (
    <AdminShell>
      <div className="p-6 max-w-7xl mx-auto">
        <div className="flex items-center justify-between mb-6">
          <div>
            <h1 className="text-2xl font-bold" style={{ color: 'var(--text-primary)' }}>System Health</h1>
            <p className="text-sm mt-1" style={{ color: 'var(--text-secondary)' }}>Database, connections, push pipeline, RPC performance</p>
          </div>
          <div className="flex items-center gap-3">
            <label className="flex items-center gap-2 text-xs cursor-pointer" style={{ color: 'var(--text-muted)' }}>
              <input type="checkbox" checked={autoRefresh} onChange={e => setAutoRefresh(e.target.checked)} />
              Auto-refresh (30s)
            </label>
            <button onClick={loadAll} className="btn btn-ghost text-sm">Refresh</button>
          </div>
        </div>

        {/* Section Nav */}
        <div className="flex gap-1 mb-6 p-1 rounded-lg flex-wrap" style={{ background: 'var(--bg-tertiary)' }}>
          {sections.map(s => (
            <button key={s.key} onClick={() => setActiveSection(s.key)}
              className="px-4 py-2 rounded-md text-sm font-medium whitespace-nowrap"
              style={{ background: activeSection === s.key ? 'var(--bg-secondary)' : 'transparent', color: activeSection === s.key ? 'var(--text-primary)' : 'var(--text-muted)' }}>
              {s.label}
            </button>
          ))}
        </div>

        {loading && tables.length === 0 ? (
          <div className="flex justify-center py-20"><div className="spinner" style={{ width: 32, height: 32 }} /></div>
        ) : (
          <>
            {activeSection === 'overview' && (
              <>
                <div className="grid grid-cols-2 lg:grid-cols-4 gap-4 mb-6">
                  <StatCard label="Total DB Size" value={formatBytes(totalDbSize)} color="var(--accent)" />
                  <StatCard label="Total Rows" value={totalRows.toLocaleString()} color="var(--info)" />
                  <StatCard label="Active Connections" value={`${activeConns} / ${maxConns}`} color={activeConns > maxConns * 0.8 ? 'var(--danger)' : 'var(--success)'} />
                  <StatCard label="Push Queue Pending" value={String(queuePending)} color={queuePending > 100 ? 'var(--warning)' : 'var(--success)'} />
                </div>
                <div className="grid grid-cols-2 lg:grid-cols-4 gap-4 mb-6">
                  <StatCard label="Push Failed (24h)" value={String(queueFailed)} color={queueFailed > 0 ? 'var(--danger)' : 'var(--success)'} />
                  <StatCard label="Crashes (30d)" value={String(errorRates?.crashes_30d || 0)} color="var(--warning)" />
                  <StatCard label="Bug Reports (30d)" value={String(errorRates?.bugs_30d || 0)} color="var(--warning)" />
                  <StatCard label="Unused Indexes" value={String(unusedIndexes.length)} color={unusedIndexes.length > 10 ? 'var(--warning)' : 'var(--success)'} />
                </div>

                {/* Connection Breakdown */}
                {connections && (
                  <div className="card mb-6">
                    <h3 className="text-sm font-semibold mb-3" style={{ color: 'var(--text-primary)' }}>Connection Pool</h3>
                    <div className="flex gap-6 flex-wrap">
                      {['active', 'idle', 'idle_in_transaction', 'waiting'].map(key => (
                        <div key={key} className="text-center">
                          <div className="text-xl font-bold" style={{ color: key === 'active' ? 'var(--success)' : key === 'waiting' ? 'var(--danger)' : 'var(--text-primary)' }}>
                            {String(connections[key] || 0)}
                          </div>
                          <div className="text-xs" style={{ color: 'var(--text-muted)' }}>{key.replace(/_/g, ' ')}</div>
                        </div>
                      ))}
                    </div>
                    {/* Bar gauge */}
                    <div className="mt-3 h-4 rounded-full overflow-hidden" style={{ background: 'var(--bg-tertiary)' }}>
                      <div className="h-full rounded-full" style={{
                        width: `${maxConns ? Math.min(100, (activeConns / maxConns) * 100) : 0}%`,
                        background: activeConns > maxConns * 0.8 ? 'var(--danger)' : activeConns > maxConns * 0.5 ? 'var(--warning)' : 'var(--success)',
                      }} />
                    </div>
                    <div className="text-xs mt-1" style={{ color: 'var(--text-muted)' }}>
                      {activeConns} of {maxConns} connections used ({maxConns ? Math.round((activeConns / maxConns) * 100) : 0}%)
                    </div>
                  </div>
                )}

                {/* Top 10 tables */}
                <div className="card">
                  <h3 className="text-sm font-semibold mb-3" style={{ color: 'var(--text-primary)' }}>Top 10 Tables by Size</h3>
                  <div className="space-y-2">
                    {tables.slice(0, 10).map(t => (
                      <div key={t.table_name} className="flex items-center gap-3">
                        <span className="text-xs font-mono w-48 truncate" style={{ color: 'var(--text-primary)' }}>{t.table_name}</span>
                        <div className="flex-1 h-3 rounded-full overflow-hidden" style={{ background: 'var(--bg-tertiary)' }}>
                          <div className="h-full rounded-full" style={{
                            width: `${totalDbSize ? Math.max(2, (t.total_bytes / totalDbSize) * 100) : 0}%`,
                            background: 'var(--accent)',
                          }} />
                        </div>
                        <span className="text-xs font-mono w-20 text-right" style={{ color: 'var(--text-secondary)' }}>{formatBytes(t.total_bytes)}</span>
                        <span className="text-xs w-20 text-right" style={{ color: 'var(--text-muted)' }}>{t.row_estimate.toLocaleString()} rows</span>
                      </div>
                    ))}
                  </div>
                </div>
              </>
            )}

            {activeSection === 'tables' && (
              <div className="card">
                <div className="flex items-center justify-between mb-4">
                  <h3 className="text-sm font-semibold" style={{ color: 'var(--text-primary)' }}>All Tables ({tables.length})</h3>
                  <div className="flex gap-2">
                    {[
                      { key: 'total_bytes' as const, label: 'Size' },
                      { key: 'row_estimate' as const, label: 'Rows' },
                      { key: 'table_name' as const, label: 'Name' },
                    ].map(s => (
                      <button key={s.key} onClick={() => { if (tableSortKey === s.key) setTableSortAsc(!tableSortAsc); else { setTableSortKey(s.key); setTableSortAsc(false) } }}
                        className="text-xs px-2 py-1 rounded" style={{ background: tableSortKey === s.key ? 'var(--accent)' : 'var(--bg-tertiary)', color: tableSortKey === s.key ? 'white' : 'var(--text-muted)' }}>
                        {s.label} {tableSortKey === s.key ? (tableSortAsc ? '↑' : '↓') : ''}
                      </button>
                    ))}
                  </div>
                </div>
                <div className="overflow-x-auto">
                  <table>
                    <thead>
                      <tr>
                        <th>Table</th>
                        <th className="text-right">Rows</th>
                        <th className="text-right">Total Size</th>
                        <th className="text-right">Data</th>
                        <th className="text-right">Indexes</th>
                        <th className="text-right">TOAST</th>
                      </tr>
                    </thead>
                    <tbody>
                      {sortedTables.map(t => (
                        <tr key={t.table_name}>
                          <td className="font-mono text-xs">{t.table_name}</td>
                          <td className="text-right text-sm">{t.row_estimate.toLocaleString()}</td>
                          <td className="text-right text-sm font-medium">{formatBytes(t.total_bytes)}</td>
                          <td className="text-right text-sm" style={{ color: 'var(--text-muted)' }}>{formatBytes(t.table_bytes)}</td>
                          <td className="text-right text-sm" style={{ color: 'var(--text-muted)' }}>{formatBytes(t.index_bytes)}</td>
                          <td className="text-right text-sm" style={{ color: 'var(--text-muted)' }}>{formatBytes(t.toast_bytes)}</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              </div>
            )}

            {activeSection === 'push' && (
              <>
                {pushPipeline ? (
                  <>
                    <div className="grid grid-cols-2 lg:grid-cols-4 gap-4 mb-6">
                      <StatCard label="Queue Total" value={String((queue?.total as number) || 0)} color="var(--info)" />
                      <StatCard label="Pending" value={String((queue?.pending as number) || 0)} color="var(--warning)" />
                      <StatCard label="Sent (24h)" value={String((queue?.sent_24h as number) || 0)} color="var(--success)" />
                      <StatCard label="Failed (24h)" value={String((queue?.failed_24h as number) || 0)} color={(queue?.failed_24h as number) > 0 ? 'var(--danger)' : 'var(--success)'} />
                    </div>

                    {/* Delivery breakdown */}
                    {(pushPipeline as Record<string, unknown>)?.delivery_24h && (
                      <div className="card mb-6">
                        <h3 className="text-sm font-semibold mb-3" style={{ color: 'var(--text-primary)' }}>Delivery Events (24h)</h3>
                        <div className="grid grid-cols-2 md:grid-cols-5 gap-4">
                          {Object.entries((pushPipeline as Record<string, unknown>).delivery_24h as Record<string, number>).map(([key, val]) => (
                            <div key={key} className="text-center p-3 rounded-lg" style={{ background: 'var(--bg-tertiary)' }}>
                              <div className="text-lg font-bold" style={{ color: 'var(--text-primary)' }}>{val}</div>
                              <div className="text-xs" style={{ color: 'var(--text-muted)' }}>{key.replace(/_/g, ' ')}</div>
                            </div>
                          ))}
                        </div>
                      </div>
                    )}

                    {/* Hourly trend */}
                    {Array.isArray((pushPipeline as Record<string, unknown>)?.hourly_trend) && (
                      <div className="card">
                        <h3 className="text-sm font-semibold mb-3" style={{ color: 'var(--text-primary)' }}>Hourly Send Volume (24h)</h3>
                        <div className="flex items-end gap-1 h-32">
                          {((pushPipeline as Record<string, unknown>).hourly_trend as { hour: string; sent: number; failed: number }[]).map((h, i) => {
                            const maxVal = Math.max(1, ...((pushPipeline as Record<string, unknown>).hourly_trend as { sent: number }[]).map(x => x.sent))
                            return (
                              <div key={i} className="flex-1 flex flex-col items-center gap-0.5">
                                <div className="w-full rounded-t" style={{ height: `${(h.sent / maxVal) * 100}%`, background: 'var(--success)', minHeight: 2 }} />
                                {h.failed > 0 && <div className="w-full rounded-t" style={{ height: `${(h.failed / maxVal) * 100}%`, background: 'var(--danger)', minHeight: 2 }} />}
                              </div>
                            )
                          })}
                        </div>
                        <div className="flex justify-between mt-1">
                          <span className="text-xs" style={{ color: 'var(--text-muted)' }}>24h ago</span>
                          <span className="text-xs" style={{ color: 'var(--text-muted)' }}>Now</span>
                        </div>
                      </div>
                    )}
                  </>
                ) : (
                  <div className="card text-center py-12">
                    <p style={{ color: 'var(--text-muted)' }}>Push pipeline data unavailable. The admin_get_push_pipeline_stats() RPC may not be deployed yet.</p>
                  </div>
                )}
              </>
            )}

            {activeSection === 'rpc' && (
              <div className="card">
                <h3 className="text-sm font-semibold mb-4" style={{ color: 'var(--text-primary)' }}>RPC / Function Performance</h3>
                {rpcStats.length === 0 ? (
                  <p className="text-sm py-8 text-center" style={{ color: 'var(--text-muted)' }}>No RPC stats available. pg_stat_user_functions may need tracking enabled.</p>
                ) : (
                  <div className="overflow-x-auto">
                    <table>
                      <thead>
                        <tr>
                          <th>Function</th>
                          <th className="text-right">Calls</th>
                          <th className="text-right">Total (ms)</th>
                          <th className="text-right">Avg (ms)</th>
                          <th className="text-right">Self (ms)</th>
                        </tr>
                      </thead>
                      <tbody>
                        {rpcStats.map(f => (
                          <tr key={f.function_name}>
                            <td className="font-mono text-xs">{f.function_name}</td>
                            <td className="text-right text-sm">{f.calls.toLocaleString()}</td>
                            <td className="text-right text-sm">{f.total_time_ms.toLocaleString()}</td>
                            <td className="text-right text-sm font-medium" style={{ color: f.avg_time_ms > 100 ? 'var(--danger)' : f.avg_time_ms > 20 ? 'var(--warning)' : 'var(--text-primary)' }}>
                              {f.avg_time_ms}
                            </td>
                            <td className="text-right text-sm" style={{ color: 'var(--text-muted)' }}>{f.self_time_ms}</td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </div>
                )}
              </div>
            )}

            {activeSection === 'indexes' && (
              <>
                {unusedIndexes.length > 0 && (
                  <div className="card mb-6" style={{ borderColor: 'var(--warning)' }}>
                    <h3 className="text-sm font-semibold mb-3" style={{ color: 'var(--warning)' }}>Unused Indexes ({unusedIndexes.length})</h3>
                    <p className="text-xs mb-3" style={{ color: 'var(--text-muted)' }}>These indexes have 0 scans since last stats reset. Consider removing to save space.</p>
                    <div className="overflow-x-auto">
                      <table>
                        <thead><tr><th>Index</th><th>Table</th><th className="text-right">Size</th></tr></thead>
                        <tbody>
                          {unusedIndexes.map(i => (
                            <tr key={i.index_name}>
                              <td className="font-mono text-xs">{i.index_name}</td>
                              <td className="text-xs">{i.table_name}</td>
                              <td className="text-right text-sm">{formatBytes(i.index_size)}</td>
                            </tr>
                          ))}
                        </tbody>
                      </table>
                    </div>
                  </div>
                )}

                <div className="card">
                  <h3 className="text-sm font-semibold mb-4" style={{ color: 'var(--text-primary)' }}>All Indexes ({indexes.length})</h3>
                  <div className="overflow-x-auto">
                    <table>
                      <thead>
                        <tr><th>Index</th><th>Table</th><th className="text-right">Size</th><th className="text-right">Scans</th><th className="text-right">Tuples Read</th></tr>
                      </thead>
                      <tbody>
                        {indexes.map(i => (
                          <tr key={i.index_name}>
                            <td className="font-mono text-xs">{i.index_name}</td>
                            <td className="text-xs">{i.table_name}</td>
                            <td className="text-right text-sm">{formatBytes(i.index_size)}</td>
                            <td className="text-right text-sm" style={{ color: i.idx_scan === 0 ? 'var(--danger)' : 'var(--text-primary)' }}>{i.idx_scan.toLocaleString()}</td>
                            <td className="text-right text-sm" style={{ color: 'var(--text-muted)' }}>{i.idx_tup_read.toLocaleString()}</td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </div>
                </div>
              </>
            )}

            {activeSection === 'errors' && errorRates && (
              <>
                <div className="grid grid-cols-2 gap-4 mb-6">
                  <StatCard label="Crash Reports (30d)" value={String(errorRates.crashes_30d)} color="var(--danger)" />
                  <StatCard label="Bug Reports (30d)" value={String(errorRates.bugs_30d)} color="var(--warning)" />
                </div>
                <div className="card">
                  <h3 className="text-sm font-semibold mb-3" style={{ color: 'var(--text-primary)' }}>Daily Crashes (30d)</h3>
                  <div className="flex items-end gap-1 h-32">
                    {Object.entries(errorRates.daily_crashes).sort(([a], [b]) => a.localeCompare(b)).map(([day, count]) => {
                      const maxVal = Math.max(1, ...Object.values(errorRates.daily_crashes))
                      return (
                        <div key={day} className="flex-1 group relative">
                          <div className="w-full rounded-t" style={{ height: `${(count / maxVal) * 100}%`, background: 'var(--danger)', minHeight: 2 }} />
                          <div className="absolute bottom-full mb-1 left-1/2 -translate-x-1/2 hidden group-hover:block text-xs px-2 py-1 rounded whitespace-nowrap"
                            style={{ background: 'var(--bg-secondary)', border: '1px solid var(--border)', color: 'var(--text-primary)' }}>
                            {day}: {count}
                          </div>
                        </div>
                      )
                    })}
                  </div>
                </div>
              </>
            )}
          </>
        )}
      </div>
    </AdminShell>
  )
}

function StatCard({ label, value, color }: { label: string; value: string; color: string }) {
  return (
    <div className="card">
      <div className="text-2xl font-bold" style={{ color }}>{value}</div>
      <div className="text-xs font-medium mt-1" style={{ color: 'var(--text-secondary)' }}>{label}</div>
    </div>
  )
}
