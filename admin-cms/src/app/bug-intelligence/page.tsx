'use client'

import { useCallback, useEffect, useMemo, useState } from 'react'
import AdminShell from '@/components/AdminShell'

// ── Types ─────────────────────────────────────────────────────────────────

type Fingerprint = {
    fingerprint: string
    source: 'log' | 'crash'
    normalized_message: string
    sample_message: string
    error_domain: string | null
    first_seen_at: string
    last_seen_at: string
    first_seen_app_version: string | null
    last_seen_app_version: string | null
    occurrence_count: number
    unique_user_count: number
    affected_screens: string[] | null
    assigned_agent: string | null
    status: string
    resolution_pr_url: string | null
    pain_point_id: string | null
    latest_report: Report | null
}

type Report = {
    id: string
    fingerprint: string
    agent_owner: string
    invariant_violated: string | null
    severity: 'critical' | 'high' | 'medium' | 'low'
    confidence: number
    title: string
    summary: string
    file_path: string | null
    code_diff: string | null
    pain_point_candidate: string | null
    suggested_todo: string | null
    review_status: 'pending' | 'approved' | 'rejected' | 'merged' | 'stale'
    pr_url: string | null
    pr_branch: string | null
    created_at: string
    trigger_reason: string
}

type Trend = {
    id: string
    fingerprint: string
    trend_type: 'new' | 'regression' | 'resolved'
    detected_at: string
    today_count: number
    baseline_mean: number | null
    spike_ratio: number | null
    affected_users: number
    reviewed_at: string | null
}

type Overview = {
    fingerprints_by_status: Record<string, number>
    reports_last_7d_by_severity: Record<string, number>
    trends_last_24h: Trend[]
    pending_reports_count: number
}

type AgentMetric = {
    agent_owner: string
    reports_total: number
    unique_fingerprints: number
    reports_pending: number
    reports_approved: number
    reports_rejected: number
    reports_merged: number
    reports_critical: number
    reports_high: number
    avg_confidence: number | null
    fix_rate_pct: number | null
    median_time_to_fix_hours: number | null
    total_occurrences_affected: number
    total_users_affected: number
}

const AGENTS = [
    'quality-performance', 'product-engineer', 'data-backend', 'infra-security',
    'supabase-expert', 'design-system', 'design', 'fitness-expert',
    'device-compatibility', 'support', 'unknown',
] as const

const STATUS_COLORS: Record<string, string> = {
    new: '#3b82f6', triaged: '#a855f7', in_progress: '#f59e0b',
    resolved: '#22c55e', wont_fix: '#6b7280', duplicate: '#6b7280',
}

const SEVERITY_COLORS: Record<string, string> = {
    critical: '#dc2626', high: '#f97316', medium: '#f59e0b', low: '#3b82f6',
}

// ── Helpers ────────────────────────────────────────────────────────────────

async function adminAction(action: string, params: Record<string, unknown> = {}) {
    const res = await fetch('/api/admin', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ action, ...params }),
    })
    return res.json()
}

function timeAgo(iso: string): string {
    const ms = Date.now() - new Date(iso).getTime()
    const m = Math.floor(ms / 60_000)
    if (m < 1) return 'just now'
    if (m < 60) return `${m}m ago`
    const h = Math.floor(m / 60)
    if (h < 24) return `${h}h ago`
    const d = Math.floor(h / 24)
    return `${d}d ago`
}

// ── Page ───────────────────────────────────────────────────────────────────

export default function BugIntelligencePage() {
    const [overview, setOverview] = useState<Overview | null>(null)
    const [metrics, setMetrics] = useState<AgentMetric[]>([])
    const [fingerprints, setFingerprints] = useState<Fingerprint[]>([])
    const [selectedFp, setSelectedFp] = useState<string | null>(null)
    const [reports, setReports] = useState<Report[]>([])
    const [trends, setTrends] = useState<Trend[]>([])
    const [loading, setLoading] = useState(true)
    const [triggering, setTriggering] = useState(false)
    const [filters, setFilters] = useState({
        status: 'all',
        agent: 'all',
        severity_min: '',
        search: '',
    })

    const loadOverview = useCallback(async () => {
        const [ovRes, mRes] = await Promise.all([
            adminAction('get_bug_intelligence_overview'),
            adminAction('get_bug_intelligence_metrics'),
        ])
        setOverview(ovRes.overview || null)
        setMetrics(mRes.metrics || [])
    }, [])

    const loadFingerprints = useCallback(async () => {
        setLoading(true)
        const data = await adminAction('get_bug_intelligence_fingerprints', {
            status: filters.status,
            agent: filters.agent,
            severity_min: filters.severity_min || undefined,
            search: filters.search || undefined,
            limit: 150,
        })
        setFingerprints(data.fingerprints || [])
        setLoading(false)
    }, [filters])

    const loadDetail = useCallback(async (fp: string) => {
        const [rRes, tRes] = await Promise.all([
            adminAction('get_bug_intelligence_reports', { fingerprint: fp }),
            adminAction('get_bug_intelligence_trends', { fingerprint: fp }),
        ])
        setReports(rRes.reports || [])
        setTrends(tRes.trends || [])
    }, [])

    useEffect(() => { loadOverview() }, [loadOverview])
    useEffect(() => { loadFingerprints() }, [loadFingerprints])
    useEffect(() => {
        if (selectedFp) loadDetail(selectedFp)
        else { setReports([]); setTrends([]) }
    }, [selectedFp, loadDetail])

    const sortedFingerprints = useMemo(() => {
        return [...fingerprints].sort((a, b) => {
            const aSev = a.latest_report?.severity
                ? (SEVERITY_ORDER[a.latest_report.severity] ?? 5)
                : 5
            const bSev = b.latest_report?.severity
                ? (SEVERITY_ORDER[b.latest_report.severity] ?? 5)
                : 5
            if (aSev !== bSev) return aSev - bSev
            return b.occurrence_count - a.occurrence_count
        })
    }, [fingerprints])

    const selected = fingerprints.find(f => f.fingerprint === selectedFp)

    async function triggerTriage(fps?: string[]) {
        setTriggering(true)
        try {
            const result = await adminAction('trigger_bug_triage', { fingerprints: fps })
            if (!result.ok) {
                alert(`Triage failed: ${JSON.stringify(result.result)}`)
            } else {
                const r = result.result as { reports_written?: number; candidates?: number }
                alert(`Triage complete — ${r?.reports_written ?? 0} report(s) written across ${r?.candidates ?? 0} fingerprint(s).`)
                await Promise.all([loadOverview(), loadFingerprints()])
                if (selectedFp) await loadDetail(selectedFp)
            }
        } finally {
            setTriggering(false)
        }
    }

    async function updateFingerprint(fp: string, patch: Partial<Fingerprint>) {
        await adminAction('update_bug_fingerprint', { fingerprint: fp, ...patch })
        await loadFingerprints()
        if (selectedFp === fp) await loadDetail(fp)
    }

    async function updateReportReview(reportId: string, review_status: string) {
        await adminAction('update_bug_report_review', { report_id: reportId, review_status })
        if (selectedFp) await loadDetail(selectedFp)
    }

    async function createPrFromReport(r: Report) {
        if (!r.file_path || !r.code_diff) {
            alert('Report is missing file_path or code_diff — cannot create PR.')
            return
        }
        const res = await fetch('/api/github-pr', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                suggestion_id: r.id,
                title: `[BugIntel] ${r.title}`,
                description: `${r.summary}\n\n— Auto-generated by the Fit33 Bug Intelligence triage agent.\nAgent owner: ${r.agent_owner}\nInvariant: ${r.invariant_violated ?? 'n/a'}\nSeverity: ${r.severity} (confidence ${r.confidence})\nFingerprint: ${r.fingerprint}`,
                file_path: r.file_path,
                code_diff: r.code_diff,
            }),
        })
        const json = await res.json()
        if (res.ok && json.pr_url) {
            await adminAction('update_bug_report_review', {
                report_id: r.id,
                review_status: 'approved',
                pr_url: json.pr_url,
                pr_branch: json.branch,
            })
            if (selectedFp) await loadDetail(selectedFp)
        } else {
            alert(`PR creation failed: ${json.error || 'unknown'}`)
        }
    }

    return (
        <AdminShell>
            <div style={{ padding: 24, maxWidth: 1800, margin: '0 auto' }}>
                <header style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: 24 }}>
                    <div>
                        <h1 style={{ fontSize: 28, fontWeight: 700, margin: 0 }}>Bug Intelligence</h1>
                        <p style={{ color: '#6b7280', margin: '4px 0 0' }}>
                            Fingerprinted bugs from logs + crashes. Claude triage runs every 4 hours.
                        </p>
                    </div>
                    <button
                        onClick={() => triggerTriage()}
                        disabled={triggering}
                        style={{
                            padding: '10px 20px', borderRadius: 8, border: 'none',
                            background: triggering ? '#6b7280' : '#6366f1', color: '#fff',
                            fontWeight: 600, cursor: triggering ? 'wait' : 'pointer',
                        }}
                    >
                        {triggering ? 'Triaging…' : 'Run triage now'}
                    </button>
                </header>

                        {overview && <OverviewRow overview={overview} />}

                        {metrics.length > 0 && <AgentLeaderboard metrics={metrics} />}

                        <div style={{ display: 'grid', gridTemplateColumns: selectedFp ? '1fr 560px' : '1fr', gap: 24, marginTop: 24 }}>
                    <FingerprintList
                        fingerprints={sortedFingerprints}
                        loading={loading}
                        filters={filters}
                        setFilters={setFilters}
                        selectedFp={selectedFp}
                        setSelectedFp={setSelectedFp}
                        onTriage={(fp) => triggerTriage([fp])}
                    />

                    {selectedFp && selected && (
                        <DetailPanel
                            fp={selected}
                            reports={reports}
                            trends={trends}
                            onClose={() => setSelectedFp(null)}
                            onUpdateFingerprint={(patch) => updateFingerprint(selected.fingerprint, patch)}
                            onReviewReport={updateReportReview}
                            onCreatePr={createPrFromReport}
                            onRetriage={() => triggerTriage([selected.fingerprint])}
                            triggering={triggering}
                        />
                    )}
                </div>
            </div>
        </AdminShell>
    )
}

// ── Subcomponents ─────────────────────────────────────────────────────────

const SEVERITY_ORDER: Record<string, number> = { critical: 1, high: 2, medium: 3, low: 4 }

function OverviewRow({ overview }: { overview: Overview }) {
    const total = Object.values(overview.fingerprints_by_status).reduce((a, b) => a + b, 0)
    const critical = overview.reports_last_7d_by_severity.critical ?? 0
    const high = overview.reports_last_7d_by_severity.high ?? 0
    const newTrends = overview.trends_last_24h.filter(t => t.trend_type === 'new').length
    const regressions = overview.trends_last_24h.filter(t => t.trend_type === 'regression').length

    const cards = [
        { label: 'Total fingerprints', value: total, sub: `${overview.fingerprints_by_status.new ?? 0} new, ${overview.fingerprints_by_status.triaged ?? 0} triaged` },
        { label: 'Critical + high (7d)', value: critical + high, sub: `${critical} crit / ${high} high`, color: '#dc2626' },
        { label: 'Trends (24h)', value: overview.trends_last_24h.length, sub: `${newTrends} new / ${regressions} regression`, color: '#f97316' },
        { label: 'Pending review', value: overview.pending_reports_count, sub: 'Reports awaiting action', color: '#6366f1' },
    ]

    return (
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: 12 }}>
            {cards.map(c => (
                <div key={c.label} style={{ background: '#fff', padding: 16, borderRadius: 12, boxShadow: '0 1px 2px rgba(0,0,0,0.05)', border: '1px solid #e5e7eb' }}>
                    <div style={{ fontSize: 12, fontWeight: 600, color: '#6b7280', textTransform: 'uppercase', letterSpacing: 0.5 }}>{c.label}</div>
                    <div style={{ fontSize: 32, fontWeight: 700, color: c.color ?? '#111827', margin: '6px 0' }}>{c.value}</div>
                    <div style={{ fontSize: 13, color: '#6b7280' }}>{c.sub}</div>
                </div>
            ))}
        </div>
    )
}

function AgentLeaderboard({ metrics }: { metrics: AgentMetric[] }) {
    const sorted = [...metrics].sort((a, b) => {
        const aFixRate = a.fix_rate_pct ?? -1
        const bFixRate = b.fix_rate_pct ?? -1
        if (aFixRate !== bFixRate) return bFixRate - aFixRate
        return b.reports_merged - a.reports_merged
    })
    return (
        <section style={{ background: '#fff', borderRadius: 12, border: '1px solid #e5e7eb', marginTop: 16, padding: 16 }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', marginBottom: 10 }}>
                <h2 style={{ fontSize: 15, fontWeight: 700, margin: 0 }}>Agent leaderboard (last 30 days)</h2>
                <span style={{ fontSize: 11, color: '#6b7280' }}>Merged PRs close the loop automatically via github-pr-webhook</span>
            </div>
            <div style={{ overflow: 'auto' }}>
                <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: 13 }}>
                    <thead>
                        <tr style={{ background: '#f9fafb', textAlign: 'left' }}>
                            {['Agent', 'Reports', 'Pending', 'Merged', 'Fix rate', 'Median TTF', 'Occ.', 'Users', 'Avg conf'].map(h => (
                                <th key={h} style={{ padding: '8px 10px', fontSize: 11, fontWeight: 600, color: '#6b7280', textTransform: 'uppercase', letterSpacing: 0.5, borderBottom: '1px solid #e5e7eb' }}>{h}</th>
                            ))}
                        </tr>
                    </thead>
                    <tbody>
                        {sorted.map(m => (
                            <tr key={m.agent_owner} style={{ borderBottom: '1px solid #f3f4f6' }}>
                                <td style={{ padding: '8px 10px', fontWeight: 600 }}>{m.agent_owner}</td>
                                <td style={{ padding: '8px 10px' }}>{m.reports_total}</td>
                                <td style={{ padding: '8px 10px', color: m.reports_pending > 0 ? '#b45309' : '#6b7280' }}>{m.reports_pending}</td>
                                <td style={{ padding: '8px 10px', color: '#16a34a', fontWeight: m.reports_merged > 0 ? 600 : 400 }}>{m.reports_merged}</td>
                                <td style={{ padding: '8px 10px' }}>{m.fix_rate_pct != null ? `${m.fix_rate_pct}%` : '—'}</td>
                                <td style={{ padding: '8px 10px' }}>{m.median_time_to_fix_hours != null ? `${m.median_time_to_fix_hours}h` : '—'}</td>
                                <td style={{ padding: '8px 10px', color: '#6b7280' }}>{m.total_occurrences_affected.toLocaleString()}</td>
                                <td style={{ padding: '8px 10px', color: '#6b7280' }}>{m.total_users_affected}</td>
                                <td style={{ padding: '8px 10px', color: '#6b7280' }}>{m.avg_confidence != null ? m.avg_confidence.toFixed(2) : '—'}</td>
                            </tr>
                        ))}
                    </tbody>
                </table>
            </div>
        </section>
    )
}

function FingerprintList({
    fingerprints, loading, filters, setFilters, selectedFp, setSelectedFp, onTriage,
}: {
    fingerprints: Fingerprint[]
    loading: boolean
    filters: { status: string; agent: string; severity_min: string; search: string }
    setFilters: (next: { status: string; agent: string; severity_min: string; search: string }) => void
    selectedFp: string | null
    setSelectedFp: (fp: string | null) => void
    onTriage: (fp: string) => void
}) {
    return (
        <section style={{ background: '#fff', borderRadius: 12, border: '1px solid #e5e7eb', overflow: 'hidden' }}>
            <div style={{ padding: '12px 16px', borderBottom: '1px solid #e5e7eb', display: 'flex', gap: 8, alignItems: 'center', flexWrap: 'wrap' }}>
                <input
                    placeholder="Search sample message…"
                    value={filters.search}
                    onChange={e => setFilters({ ...filters, search: e.target.value })}
                    style={{ flex: 1, minWidth: 220, padding: '6px 10px', border: '1px solid #d1d5db', borderRadius: 6, fontSize: 13 }}
                />
                <select value={filters.status} onChange={e => setFilters({ ...filters, status: e.target.value })} style={selectStyle}>
                    <option value="all">All statuses</option>
                    <option value="new">New</option>
                    <option value="triaged">Triaged</option>
                    <option value="in_progress">In progress</option>
                    <option value="resolved">Resolved</option>
                    <option value="wont_fix">Won&apos;t fix</option>
                    <option value="duplicate">Duplicate</option>
                </select>
                <select value={filters.agent} onChange={e => setFilters({ ...filters, agent: e.target.value })} style={selectStyle}>
                    <option value="all">All agents</option>
                    {AGENTS.map(a => <option key={a} value={a}>{a}</option>)}
                </select>
                <select value={filters.severity_min} onChange={e => setFilters({ ...filters, severity_min: e.target.value })} style={selectStyle}>
                    <option value="">All severities</option>
                    <option value="critical">Critical only</option>
                    <option value="high">High+</option>
                    <option value="medium">Medium+</option>
                </select>
            </div>

            {loading ? (
                <div style={{ padding: 40, textAlign: 'center', color: '#6b7280' }}>Loading fingerprints…</div>
            ) : fingerprints.length === 0 ? (
                <div style={{ padding: 40, textAlign: 'center', color: '#6b7280' }}>
                    No fingerprints match these filters.
                </div>
            ) : (
                <div style={{ overflowY: 'auto', maxHeight: '70vh' }}>
                    {fingerprints.map(fp => (
                        <FingerprintRow
                            key={fp.fingerprint}
                            fp={fp}
                            selected={fp.fingerprint === selectedFp}
                            onSelect={() => setSelectedFp(fp.fingerprint === selectedFp ? null : fp.fingerprint)}
                            onTriage={() => onTriage(fp.fingerprint)}
                        />
                    ))}
                </div>
            )}
        </section>
    )
}

const selectStyle: React.CSSProperties = {
    padding: '6px 10px', border: '1px solid #d1d5db', borderRadius: 6, fontSize: 13, background: '#fff',
}

function FingerprintRow({ fp, selected, onSelect, onTriage }: {
    fp: Fingerprint; selected: boolean; onSelect: () => void; onTriage: () => void
}) {
    const rep = fp.latest_report
    return (
        <div
            onClick={onSelect}
            style={{
                padding: '12px 16px',
                borderBottom: '1px solid #f3f4f6',
                cursor: 'pointer',
                background: selected ? '#eef2ff' : '#fff',
                display: 'grid',
                gridTemplateColumns: '1fr auto',
                gap: 12,
                alignItems: 'start',
            }}
        >
            <div style={{ minWidth: 0 }}>
                <div style={{ display: 'flex', gap: 8, alignItems: 'center', flexWrap: 'wrap', marginBottom: 4 }}>
                    <Pill label={fp.source} color={fp.source === 'crash' ? '#dc2626' : '#6366f1'} />
                    <Pill label={fp.status} color={STATUS_COLORS[fp.status] ?? '#6b7280'} />
                    {rep && <Pill label={rep.severity} color={SEVERITY_COLORS[rep.severity] ?? '#6b7280'} />}
                    {rep && <Pill label={rep.agent_owner} color="#374151" />}
                    {fp.resolution_pr_url && <Pill label="PR" color="#16a34a" />}
                </div>
                <div style={{ fontFamily: 'ui-monospace, monospace', fontSize: 13, color: '#111827', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                    {fp.sample_message || fp.normalized_message}
                </div>
                {rep && (
                    <div style={{ fontSize: 12, color: '#6b7280', marginTop: 4, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                        {rep.title}
                    </div>
                )}
                <div style={{ fontSize: 11, color: '#9ca3af', marginTop: 4 }}>
                    {fp.occurrence_count} occurrences · {fp.unique_user_count} user{fp.unique_user_count === 1 ? '' : 's'} · last seen {timeAgo(fp.last_seen_at)}
                    {fp.affected_screens && fp.affected_screens.length > 0 && ` · ${fp.affected_screens.slice(0, 3).join(', ')}${fp.affected_screens.length > 3 ? '…' : ''}`}
                </div>
            </div>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
                <button
                    onClick={(e) => { e.stopPropagation(); onTriage() }}
                    style={smallButton}
                    title="Re-run Claude triage on this fingerprint"
                >
                    Triage
                </button>
            </div>
        </div>
    )
}

function Pill({ label, color }: { label: string; color: string }) {
    return (
        <span style={{
            display: 'inline-block', padding: '2px 8px', fontSize: 11, fontWeight: 600,
            background: color, color: '#fff', borderRadius: 999, textTransform: 'uppercase',
            letterSpacing: 0.3,
        }}>
            {label}
        </span>
    )
}

const smallButton: React.CSSProperties = {
    fontSize: 12, padding: '4px 10px', borderRadius: 6, border: '1px solid #d1d5db',
    background: '#fff', cursor: 'pointer', color: '#111827',
}

function DetailPanel({
    fp, reports, trends, onClose, onUpdateFingerprint, onReviewReport, onCreatePr, onRetriage, triggering,
}: {
    fp: Fingerprint
    reports: Report[]
    trends: Trend[]
    onClose: () => void
    onUpdateFingerprint: (patch: Partial<Fingerprint>) => void
    onReviewReport: (reportId: string, review_status: string) => void
    onCreatePr: (r: Report) => void
    onRetriage: () => void
    triggering: boolean
}) {
    return (
        <aside style={{ background: '#fff', borderRadius: 12, border: '1px solid #e5e7eb', padding: 16, alignSelf: 'start', maxHeight: '85vh', overflowY: 'auto' }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: 12 }}>
                <h2 style={{ fontSize: 16, fontWeight: 700, margin: 0 }}>Fingerprint detail</h2>
                <button onClick={onClose} style={{ background: 'none', border: 'none', fontSize: 18, cursor: 'pointer', color: '#6b7280' }}>×</button>
            </div>

            <div style={{ fontFamily: 'ui-monospace, monospace', fontSize: 11, color: '#6b7280', wordBreak: 'break-all', marginBottom: 8 }}>
                {fp.fingerprint}
            </div>

            <div style={{ fontFamily: 'ui-monospace, monospace', fontSize: 12, background: '#f9fafb', padding: 10, borderRadius: 6, marginBottom: 12, border: '1px solid #e5e7eb', maxHeight: 120, overflowY: 'auto' }}>
                {fp.sample_message}
            </div>

            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 8, fontSize: 12, marginBottom: 12 }}>
                <MetaItem label="Source" value={fp.source} />
                <MetaItem label="Domain" value={fp.error_domain ?? '—'} />
                <MetaItem label="Occurrences" value={String(fp.occurrence_count)} />
                <MetaItem label="Users" value={String(fp.unique_user_count)} />
                <MetaItem label="First seen" value={timeAgo(fp.first_seen_at)} />
                <MetaItem label="Last seen" value={timeAgo(fp.last_seen_at)} />
                <MetaItem label="First app ver" value={fp.first_seen_app_version ?? '—'} />
                <MetaItem label="Last app ver" value={fp.last_seen_app_version ?? '—'} />
            </div>

            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 8, marginBottom: 16 }}>
                <label style={{ fontSize: 12, fontWeight: 600, color: '#374151' }}>
                    Status
                    <select
                        value={fp.status}
                        onChange={e => onUpdateFingerprint({ status: e.target.value })}
                        style={{ ...selectStyle, width: '100%', marginTop: 4 }}
                    >
                        {['new', 'triaged', 'in_progress', 'resolved', 'wont_fix', 'duplicate'].map(s => (
                            <option key={s} value={s}>{s}</option>
                        ))}
                    </select>
                </label>
                <label style={{ fontSize: 12, fontWeight: 600, color: '#374151' }}>
                    Assigned agent
                    <select
                        value={fp.assigned_agent ?? ''}
                        onChange={e => onUpdateFingerprint({ assigned_agent: e.target.value })}
                        style={{ ...selectStyle, width: '100%', marginTop: 4 }}
                    >
                        <option value="">— unassigned —</option>
                        {AGENTS.map(a => <option key={a} value={a}>{a}</option>)}
                    </select>
                </label>
            </div>

            <button onClick={onRetriage} disabled={triggering} style={{ ...smallButton, width: '100%', marginBottom: 16 }}>
                {triggering ? 'Running…' : 'Re-run Claude triage'}
            </button>

            {trends.length > 0 && (
                <section style={{ marginBottom: 16 }}>
                    <h3 style={{ fontSize: 13, fontWeight: 700, margin: '0 0 8px' }}>Trend signals ({trends.length})</h3>
                    {trends.slice(0, 5).map(t => (
                        <div key={t.id} style={{ fontSize: 12, padding: '6px 8px', background: '#fff7ed', borderRadius: 6, marginBottom: 4, border: '1px solid #fed7aa' }}>
                            <strong>{t.trend_type}</strong> · {t.today_count} today vs baseline {t.baseline_mean?.toFixed(1) ?? '—'} · {timeAgo(t.detected_at)}
                            {t.spike_ratio && ` · ${t.spike_ratio.toFixed(1)}×`}
                        </div>
                    ))}
                </section>
            )}

            <section>
                <h3 style={{ fontSize: 13, fontWeight: 700, margin: '0 0 8px' }}>
                    Claude reports ({reports.length})
                </h3>
                {reports.length === 0 ? (
                    <div style={{ fontSize: 12, color: '#6b7280' }}>
                        No triage reports yet. Click &quot;Re-run Claude triage&quot; above.
                    </div>
                ) : reports.map(r => (
                    <ReportCard key={r.id} r={r} onReview={onReviewReport} onCreatePr={() => onCreatePr(r)} />
                ))}
            </section>
        </aside>
    )
}

function MetaItem({ label, value }: { label: string; value: string }) {
    return (
        <div>
            <div style={{ fontSize: 10, fontWeight: 600, color: '#9ca3af', textTransform: 'uppercase' }}>{label}</div>
            <div style={{ color: '#111827' }}>{value}</div>
        </div>
    )
}

function ReportCard({ r, onReview, onCreatePr }: {
    r: Report; onReview: (id: string, status: string) => void; onCreatePr: () => void
}) {
    return (
        <div style={{
            padding: 12, border: '1px solid #e5e7eb', borderRadius: 8, marginBottom: 10,
            background: r.review_status === 'pending' ? '#fefce8' : '#fff',
        }}>
            <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap', marginBottom: 6 }}>
                <Pill label={r.severity} color={SEVERITY_COLORS[r.severity] ?? '#6b7280'} />
                <Pill label={r.agent_owner} color="#374151" />
                <Pill label={r.review_status} color={STATUS_COLORS[r.review_status] ?? '#6b7280'} />
                <span style={{ fontSize: 11, color: '#6b7280', alignSelf: 'center' }}>
                    conf {r.confidence.toFixed(2)} · {r.trigger_reason} · {timeAgo(r.created_at)}
                </span>
            </div>

            <div style={{ fontWeight: 600, fontSize: 13, marginBottom: 4 }}>{r.title}</div>
            <div style={{ fontSize: 12, color: '#374151', marginBottom: 8, whiteSpace: 'pre-wrap' }}>{r.summary}</div>

            {r.invariant_violated && (
                <div style={{ fontSize: 11, color: '#92400e', background: '#fef3c7', padding: '4px 8px', borderRadius: 4, marginBottom: 8 }}>
                    Invariant: {r.invariant_violated}
                </div>
            )}

            {r.file_path && (
                <div style={{ fontFamily: 'ui-monospace, monospace', fontSize: 11, color: '#6366f1', marginBottom: 4 }}>
                    → {r.file_path}
                </div>
            )}

            {r.code_diff && (
                <details style={{ fontSize: 11, marginBottom: 8 }}>
                    <summary style={{ cursor: 'pointer', color: '#6366f1' }}>View diff</summary>
                    <pre style={{ background: '#0f172a', color: '#e2e8f0', padding: 10, borderRadius: 6, overflow: 'auto', maxHeight: 300, marginTop: 6, fontSize: 11 }}>
                        {r.code_diff}
                    </pre>
                </details>
            )}

            {r.pr_url ? (
                <a href={r.pr_url} target="_blank" rel="noreferrer" style={{ fontSize: 12, color: '#16a34a', fontWeight: 600 }}>
                    ✓ PR open: {r.pr_url}
                </a>
            ) : (
                <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap' }}>
                    {r.file_path && r.code_diff && (
                        <button onClick={onCreatePr} style={{ ...smallButton, background: '#6366f1', color: '#fff', border: 'none' }}>
                            Create PR
                        </button>
                    )}
                    {r.review_status === 'pending' && (
                        <>
                            <button onClick={() => onReview(r.id, 'approved')} style={smallButton}>Approve</button>
                            <button onClick={() => onReview(r.id, 'rejected')} style={smallButton}>Reject</button>
                        </>
                    )}
                </div>
            )}
        </div>
    )
}
