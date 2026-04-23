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

// Shape returned by the `get_bug_intelligence_export` admin action. Kept
// minimal + defensive — the formatter below reads every field optionally
// so an older server response never throws at render time.
type ExportFingerprint = {
    fingerprint: string
    source: string
    sample_message?: string
    normalized_message?: string
    error_domain?: string | null
    occurrence_count?: number
    unique_user_count?: number
    affected_screens?: string[] | null
    first_seen_at?: string
    last_seen_at?: string
    first_seen_app_version?: string | null
    last_seen_app_version?: string | null
    status?: string
    assigned_agent?: string | null
}
type ExportReport = {
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
    review_status: string
    created_at: string
}
type ExportCrash = {
    id: string
    error_message?: string
    error_domain?: string
    stack_trace?: string | null
    symbolicated_stack_trace?: string | null
    symbolication_status?: string
    breadcrumbs?: unknown
    session_log_snippet?: string | null
    current_screen?: string | null
    app_version?: string
    build_number?: string
    device_model?: string
    os_version?: string
    occurred_at?: string
    session_id?: string | null
}
type BugIntelExportBundle = {
    fingerprint: ExportFingerprint | null
    report: ExportReport
    example_crash: ExportCrash | null
}
type BugIntelExport = {
    generated_at: string
    filters: Record<string, unknown>
    bundle_count: number
    bundles: BugIntelExportBundle[]
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

// Solid colors used inside Pills (white text on solid backgrounds reads well on
// both light and dark surfaces, so these stay as literal hex).
const STATUS_COLORS: Record<string, string> = {
    new: '#3b82f6', triaged: '#a855f7', in_progress: '#f59e0b',
    resolved: '#22c55e', wont_fix: '#6b7280', duplicate: '#6b7280',
    pending: '#f59e0b', approved: '#3b82f6', merged: '#22c55e',
    rejected: '#ef4444', stale: '#6b7280',
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

// Builds the Cursor handoff markdown. The format is designed so an AI
// assistant can read the file top-to-bottom and know exactly what to do
// with each report — treat Claude's code_diff as a hypothesis, verify
// against the real file, and apply (or replace) the fix. Keep sections
// short + scannable; richer evidence (stack traces, session snippets)
// lives under <details> so the file doesn't explode in chat UIs.
function formatExportAsMarkdown(ex: BugIntelExport): string {
    const L: string[] = []
    const total = ex.bundle_count
    const severityCounts: Record<string, number> = { critical: 0, high: 0, medium: 0, low: 0 }
    const ownerCounts: Record<string, number> = {}
    for (const b of ex.bundles) {
        severityCounts[b.report.severity] = (severityCounts[b.report.severity] ?? 0) + 1
        ownerCounts[b.report.agent_owner] = (ownerCounts[b.report.agent_owner] ?? 0) + 1
    }

    L.push(`# Fit33 Bug Intelligence — Cursor Handoff`)
    L.push('')
    L.push(`Generated: \`${ex.generated_at}\``)
    L.push(`Source: \`/bug-intelligence\` · Filters: \`${JSON.stringify(ex.filters)}\``)
    L.push(`Reports: **${total}**`)
    L.push('')
    L.push(`## Instructions for the Cursor assistant`)
    L.push('')
    L.push(`You are receiving ${total} bug intelligence report(s) produced by the Fit33 triage pipeline (Claude Sonnet 4 + symbolicated stack traces). Each report has a suggested \`file_path\` and \`code_diff\` — treat these as **hypotheses**, not facts:`)
    L.push('')
    L.push(`1. Read the suggested \`file_path\`. Verify the failing code actually exists there.`)
    L.push(`2. If Claude's diff is correct → apply it with any needed refinements.`)
    L.push(`3. If Claude's diff is wrong or off-target → explain why and write a better one.`)
    L.push(`4. If you cannot locate the failure site → flag the report and move on.`)
    L.push(`5. Work in priority order: **critical → high → medium → low**. Within a tier, highest confidence first.`)
    L.push(`6. Share your plan before making changes (which reports you'll tackle, which you'll skip and why).`)
    L.push(`7. After fixing each report, note the fingerprint so the user can mark it resolved in \`/bug-intelligence\`.`)
    L.push('')
    L.push(`Respect the repo rules in \`.cursor/rules/codingrules.mdc\` and the scoped \`swiftui-rules.mdc\` / \`supabase-rules.mdc\` / \`admin-cms-rules.mdc\`. Consult the matching \`*_AGENT.md\` file for each report's \`agent_owner\` before making changes.`)
    L.push('')
    L.push(`## Summary`)
    L.push('')
    L.push(`| Severity | Count |`)
    L.push(`|---|---|`)
    for (const s of ['critical', 'high', 'medium', 'low']) {
        L.push(`| ${s} | ${severityCounts[s] ?? 0} |`)
    }
    L.push('')
    L.push(`**By agent owner:**`)
    for (const [owner, n] of Object.entries(ownerCounts).sort((a, b) => b[1] - a[1])) {
        L.push(`- \`${owner}\`: ${n}`)
    }
    L.push('')
    L.push(`---`)
    L.push('')

    ex.bundles.forEach((b, i) => {
        const r = b.report
        const f = b.fingerprint
        const c = b.example_crash
        const idx = i + 1

        L.push(`## Report ${idx}: [${r.severity.toUpperCase()}] ${r.title}`)
        L.push('')
        L.push(`- **Fingerprint**: \`${r.fingerprint}\``)
        L.push(`- **Owner**: \`${r.agent_owner}\` · **Severity**: \`${r.severity}\` · **Confidence**: \`${r.confidence.toFixed(2)}\``)
        if (r.invariant_violated) L.push(`- **Invariant violated**: ${r.invariant_violated}`)
        if (r.file_path) L.push(`- **Suggested file**: \`${r.file_path}\``)
        if (f?.status) L.push(`- **Fingerprint status**: \`${f.status}\``)
        L.push(`- **Report created**: \`${r.created_at}\``)
        L.push('')

        if (f) {
            L.push(`### Fingerprint context`)
            L.push('')
            if (typeof f.occurrence_count === 'number') {
                const users = typeof f.unique_user_count === 'number' ? ` across ${f.unique_user_count} user${f.unique_user_count === 1 ? '' : 's'}` : ''
                L.push(`- Occurrences: ${f.occurrence_count}${users}`)
            }
            if (f.affected_screens && f.affected_screens.length > 0) {
                L.push(`- Affected screens: ${f.affected_screens.map(s => `\`${s}\``).join(', ')}`)
            }
            if (f.first_seen_at || f.last_seen_at) {
                const firstV = f.first_seen_app_version ? ` (${f.first_seen_app_version})` : ''
                const lastV = f.last_seen_app_version ? ` (${f.last_seen_app_version})` : ''
                L.push(`- First seen: \`${f.first_seen_at ?? '?'}\`${firstV} · Last seen: \`${f.last_seen_at ?? '?'}\`${lastV}`)
            }
            L.push(`- Source: \`${f.source}\`${f.error_domain ? ` · Domain: \`${f.error_domain}\`` : ''}`)
            if (f.sample_message) {
                L.push(`- Sample message:`)
                L.push('')
                L.push('  ```')
                L.push(`  ${f.sample_message.slice(0, 800).replace(/\n/g, '\n  ')}`)
                L.push('  ```')
            }
            L.push('')
        }

        L.push(`### Claude's summary`)
        L.push('')
        L.push(r.summary || '_(no summary)_')
        L.push('')

        if (r.file_path && r.code_diff) {
            L.push(`### Claude's proposed fix`)
            L.push('')
            L.push(`File: \`${r.file_path}\``)
            L.push('')
            L.push('```diff')
            L.push(r.code_diff)
            L.push('```')
            L.push('')
        } else if (r.file_path) {
            L.push(`### Claude's lead`)
            L.push('')
            L.push(`File: \`${r.file_path}\` — no diff suggested. Investigate in this file first.`)
            L.push('')
        } else {
            L.push(`### Claude's lead`)
            L.push('')
            L.push(`_(no file_path — Claude couldn't narrow this down. Use the error message / session evidence below to locate it.)_`)
            L.push('')
        }

        if (r.pain_point_candidate) {
            L.push(`### Pain point candidate`)
            L.push('')
            L.push(r.pain_point_candidate)
            L.push('')
        }
        if (r.suggested_todo) {
            L.push(`### Suggested TODO`)
            L.push('')
            L.push(r.suggested_todo)
            L.push('')
        }

        if (c) {
            L.push(`### Evidence — representative crash`)
            L.push('')
            L.push(`- Build: \`${c.app_version ?? '?'}\` (\`${c.build_number ?? '?'}\`) on \`${c.device_model ?? '?'}\` / \`${c.os_version ?? '?'}\``)
            if (c.current_screen) L.push(`- Current screen at crash: \`${c.current_screen}\``)
            if (c.session_id) L.push(`- Session: \`${c.session_id}\``)
            if (c.symbolication_status) L.push(`- Symbolication: \`${c.symbolication_status}\``)
            L.push(`- Occurred: \`${c.occurred_at ?? '?'}\``)
            L.push('')
            const stack = (typeof c.symbolicated_stack_trace === 'string' && c.symbolicated_stack_trace.trim().length > 0)
                ? c.symbolicated_stack_trace
                : c.stack_trace
            if (stack) {
                L.push(`<details>`)
                L.push(`<summary>Stack trace</summary>`)
                L.push('')
                L.push('```')
                L.push(String(stack).slice(0, 4000))
                L.push('```')
                L.push('')
                L.push(`</details>`)
                L.push('')
            }
            if (c.session_log_snippet) {
                L.push(`<details>`)
                L.push(`<summary>Session log snippet</summary>`)
                L.push('')
                L.push('```')
                L.push(String(c.session_log_snippet).slice(0, 3000))
                L.push('```')
                L.push('')
                L.push(`</details>`)
                L.push('')
            }
            if (c.breadcrumbs) {
                L.push(`<details>`)
                L.push(`<summary>Breadcrumbs</summary>`)
                L.push('')
                L.push('```json')
                try {
                    L.push(JSON.stringify(c.breadcrumbs, null, 2).slice(0, 3000))
                } catch {
                    L.push(String(c.breadcrumbs).slice(0, 3000))
                }
                L.push('```')
                L.push('')
                L.push(`</details>`)
                L.push('')
            }
        }

        L.push(`---`)
        L.push('')
    })

    L.push(`## After fixing`)
    L.push('')
    L.push(`For each report you resolved, ask the user to go to \`/bug-intelligence\` in the admin CMS, click the fingerprint, and update the status to \`resolved\` (once the fix merges to main, the GitHub webhook will auto-flip it anyway — but manual marking is fine for local fixes).`)
    L.push('')

    return L.join('\n')
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

    // Cursor handoff export — pulls every pending/approved report bundled
    // with its fingerprint context + one representative crash (stack trace +
    // breadcrumbs + session_log_snippet). Formats as a single .md file
    // designed for pasting into a Cursor chat to drive real-repo fixes.
    const [exporting, setExporting] = useState(false)
    async function exportPendingAsMarkdown() {
        setExporting(true)
        try {
            const res = await adminAction('get_bug_intelligence_export', {
                review_status: 'pending',
            })
            const ex = res.export as BugIntelExport | undefined
            if (!ex || ex.bundle_count === 0) {
                alert('Nothing pending to export.')
                return
            }
            const md = formatExportAsMarkdown(ex)
            const blob = new Blob([md], { type: 'text/markdown;charset=utf-8' })
            const stamp = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19)
            const url = URL.createObjectURL(blob)
            const a = document.createElement('a')
            a.href = url
            a.download = `bug-intelligence-${stamp}.md`
            document.body.appendChild(a)
            a.click()
            document.body.removeChild(a)
            URL.revokeObjectURL(url)
        } catch (err) {
            alert(`Export failed: ${err instanceof Error ? err.message : String(err)}`)
        } finally {
            setExporting(false)
        }
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
                        <h1 style={{ fontSize: 28, fontWeight: 700, margin: 0, color: 'var(--text-primary)' }}>Bug Intelligence</h1>
                        <p style={{ color: 'var(--text-secondary)', margin: '4px 0 0' }}>
                            Fingerprinted bugs from logs + crashes. Claude triage runs every 4 hours.
                        </p>
                    </div>
                    <div style={{ display: 'flex', gap: 8 }}>
                        <button
                            onClick={exportPendingAsMarkdown}
                            disabled={exporting}
                            className="btn btn-ghost"
                            title="Download all pending reports as a single .md file, formatted for pasting into a Cursor chat to drive real-repo fixes."
                            style={{ opacity: exporting ? 0.6 : 1, cursor: exporting ? 'wait' : 'pointer' }}
                        >
                            {exporting ? 'Exporting…' : 'Export for Cursor (.md)'}
                        </button>
                        <button
                            onClick={() => triggerTriage()}
                            disabled={triggering}
                            className="btn btn-primary"
                            style={{ opacity: triggering ? 0.6 : 1, cursor: triggering ? 'wait' : 'pointer' }}
                        >
                            {triggering ? 'Triaging…' : 'Run triage now'}
                        </button>
                    </div>
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

const cardStyle: React.CSSProperties = {
    background: 'var(--bg-secondary)',
    border: '1px solid var(--border)',
    borderRadius: 12,
}

function OverviewRow({ overview }: { overview: Overview }) {
    const total = Object.values(overview.fingerprints_by_status).reduce((a, b) => a + b, 0)
    const critical = overview.reports_last_7d_by_severity.critical ?? 0
    const high = overview.reports_last_7d_by_severity.high ?? 0
    const newTrends = overview.trends_last_24h.filter(t => t.trend_type === 'new').length
    const regressions = overview.trends_last_24h.filter(t => t.trend_type === 'regression').length

    const cards = [
        { label: 'Total fingerprints', value: total, sub: `${overview.fingerprints_by_status.new ?? 0} new, ${overview.fingerprints_by_status.triaged ?? 0} triaged` },
        { label: 'Critical + high (7d)', value: critical + high, sub: `${critical} crit / ${high} high`, color: 'var(--danger)' },
        { label: 'Trends (24h)', value: overview.trends_last_24h.length, sub: `${newTrends} new / ${regressions} regression`, color: 'var(--warning)' },
        { label: 'Pending review', value: overview.pending_reports_count, sub: 'Reports awaiting action', color: 'var(--accent)' },
    ]

    return (
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: 12 }}>
            {cards.map(c => (
                <div key={c.label} style={{ ...cardStyle, padding: 16 }}>
                    <div style={{ fontSize: 12, fontWeight: 600, color: 'var(--text-secondary)', textTransform: 'uppercase', letterSpacing: 0.5 }}>{c.label}</div>
                    <div style={{ fontSize: 32, fontWeight: 700, color: c.color ?? 'var(--text-primary)', margin: '6px 0' }}>{c.value}</div>
                    <div style={{ fontSize: 13, color: 'var(--text-secondary)' }}>{c.sub}</div>
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
        <section style={{ ...cardStyle, marginTop: 16, padding: 16 }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', marginBottom: 10 }}>
                <h2 style={{ fontSize: 15, fontWeight: 700, margin: 0, color: 'var(--text-primary)' }}>Agent leaderboard (last 30 days)</h2>
                <span style={{ fontSize: 11, color: 'var(--text-muted)' }}>Merged PRs close the loop automatically via github-pr-webhook</span>
            </div>
            <div style={{ overflow: 'auto' }}>
                <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: 13 }}>
                    <thead>
                        <tr style={{ background: 'var(--bg-tertiary)', textAlign: 'left' }}>
                            {['Agent', 'Reports', 'Pending', 'Merged', 'Fix rate', 'Median TTF', 'Occ.', 'Users', 'Avg conf'].map(h => (
                                <th key={h} style={{ padding: '8px 10px', fontSize: 11, fontWeight: 600, color: 'var(--text-secondary)', textTransform: 'uppercase', letterSpacing: 0.5, borderBottom: '1px solid var(--border)' }}>{h}</th>
                            ))}
                        </tr>
                    </thead>
                    <tbody>
                        {sorted.map(m => (
                            <tr key={m.agent_owner} style={{ borderBottom: '1px solid var(--border)' }}>
                                <td style={{ padding: '8px 10px', fontWeight: 600, color: 'var(--text-primary)' }}>{m.agent_owner}</td>
                                <td style={{ padding: '8px 10px', color: 'var(--text-primary)' }}>{m.reports_total}</td>
                                <td style={{ padding: '8px 10px', color: m.reports_pending > 0 ? 'var(--warning)' : 'var(--text-muted)' }}>{m.reports_pending}</td>
                                <td style={{ padding: '8px 10px', color: 'var(--success)', fontWeight: m.reports_merged > 0 ? 600 : 400 }}>{m.reports_merged}</td>
                                <td style={{ padding: '8px 10px', color: 'var(--text-primary)' }}>{m.fix_rate_pct != null ? `${m.fix_rate_pct}%` : '—'}</td>
                                <td style={{ padding: '8px 10px', color: 'var(--text-primary)' }}>{m.median_time_to_fix_hours != null ? `${m.median_time_to_fix_hours}h` : '—'}</td>
                                <td style={{ padding: '8px 10px', color: 'var(--text-secondary)' }}>{m.total_occurrences_affected.toLocaleString()}</td>
                                <td style={{ padding: '8px 10px', color: 'var(--text-secondary)' }}>{m.total_users_affected}</td>
                                <td style={{ padding: '8px 10px', color: 'var(--text-secondary)' }}>{m.avg_confidence != null ? m.avg_confidence.toFixed(2) : '—'}</td>
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
        <section style={{ ...cardStyle, overflow: 'hidden' }}>
            <div style={{ padding: '12px 16px', borderBottom: '1px solid var(--border)', display: 'flex', gap: 8, alignItems: 'center', flexWrap: 'wrap' }}>
                <input
                    placeholder="Search sample message…"
                    value={filters.search}
                    onChange={e => setFilters({ ...filters, search: e.target.value })}
                    style={{ flex: 1, minWidth: 220 }}
                />
                <select value={filters.status} onChange={e => setFilters({ ...filters, status: e.target.value })} style={{ maxWidth: 180 }}>
                    <option value="all">All statuses</option>
                    <option value="new">New</option>
                    <option value="triaged">Triaged</option>
                    <option value="in_progress">In progress</option>
                    <option value="resolved">Resolved</option>
                    <option value="wont_fix">Won&apos;t fix</option>
                    <option value="duplicate">Duplicate</option>
                </select>
                <select value={filters.agent} onChange={e => setFilters({ ...filters, agent: e.target.value })} style={{ maxWidth: 200 }}>
                    <option value="all">All agents</option>
                    {AGENTS.map(a => <option key={a} value={a}>{a}</option>)}
                </select>
                <select value={filters.severity_min} onChange={e => setFilters({ ...filters, severity_min: e.target.value })} style={{ maxWidth: 180 }}>
                    <option value="">All severities</option>
                    <option value="critical">Critical only</option>
                    <option value="high">High+</option>
                    <option value="medium">Medium+</option>
                </select>
            </div>

            {loading ? (
                <div style={{ padding: 40, textAlign: 'center', color: 'var(--text-secondary)' }}>Loading fingerprints…</div>
            ) : fingerprints.length === 0 ? (
                <div style={{ padding: 40, textAlign: 'center', color: 'var(--text-secondary)' }}>
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

function FingerprintRow({ fp, selected, onSelect, onTriage }: {
    fp: Fingerprint; selected: boolean; onSelect: () => void; onTriage: () => void
}) {
    const rep = fp.latest_report
    return (
        <div
            onClick={onSelect}
            style={{
                padding: '12px 16px',
                borderBottom: '1px solid var(--border)',
                cursor: 'pointer',
                background: selected ? 'rgba(37, 99, 235, 0.12)' : 'transparent',
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
                    {rep && <Pill label={rep.agent_owner} color="#475569" />}
                    {fp.resolution_pr_url && <Pill label="PR" color="#22c55e" />}
                </div>
                <div style={{ fontFamily: 'ui-monospace, monospace', fontSize: 13, color: 'var(--text-primary)', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                    {fp.sample_message || fp.normalized_message}
                </div>
                {rep && (
                    <div style={{ fontSize: 12, color: 'var(--text-secondary)', marginTop: 4, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                        {rep.title}
                    </div>
                )}
                <div style={{ fontSize: 11, color: 'var(--text-muted)', marginTop: 4 }}>
                    {fp.occurrence_count} occurrences · {fp.unique_user_count} user{fp.unique_user_count === 1 ? '' : 's'} · last seen {timeAgo(fp.last_seen_at)}
                    {fp.affected_screens && fp.affected_screens.length > 0 && ` · ${fp.affected_screens.slice(0, 3).join(', ')}${fp.affected_screens.length > 3 ? '…' : ''}`}
                </div>
            </div>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
                <button
                    onClick={(e) => { e.stopPropagation(); onTriage() }}
                    className="btn btn-ghost"
                    style={{ padding: '4px 12px', fontSize: 12 }}
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
        <aside style={{ ...cardStyle, padding: 16, alignSelf: 'start', maxHeight: '85vh', overflowY: 'auto' }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: 12 }}>
                <h2 style={{ fontSize: 16, fontWeight: 700, margin: 0, color: 'var(--text-primary)' }}>Fingerprint detail</h2>
                <button onClick={onClose} style={{ background: 'none', border: 'none', fontSize: 18, cursor: 'pointer', color: 'var(--text-secondary)' }}>×</button>
            </div>

            <div style={{ fontFamily: 'ui-monospace, monospace', fontSize: 11, color: 'var(--text-muted)', wordBreak: 'break-all', marginBottom: 8 }}>
                {fp.fingerprint}
            </div>

            <div style={{ fontFamily: 'ui-monospace, monospace', fontSize: 12, background: 'var(--bg-tertiary)', padding: 10, borderRadius: 6, marginBottom: 12, border: '1px solid var(--border)', maxHeight: 120, overflowY: 'auto', color: 'var(--text-primary)' }}>
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
                <label style={{ fontSize: 12, fontWeight: 600, color: 'var(--text-secondary)' }}>
                    Status
                    <select
                        value={fp.status}
                        onChange={e => onUpdateFingerprint({ status: e.target.value })}
                        style={{ marginTop: 4 }}
                    >
                        {['new', 'triaged', 'in_progress', 'resolved', 'wont_fix', 'duplicate'].map(s => (
                            <option key={s} value={s}>{s}</option>
                        ))}
                    </select>
                </label>
                <label style={{ fontSize: 12, fontWeight: 600, color: 'var(--text-secondary)' }}>
                    Assigned agent
                    <select
                        value={fp.assigned_agent ?? ''}
                        onChange={e => onUpdateFingerprint({ assigned_agent: e.target.value })}
                        style={{ marginTop: 4 }}
                    >
                        <option value="">— unassigned —</option>
                        {AGENTS.map(a => <option key={a} value={a}>{a}</option>)}
                    </select>
                </label>
            </div>

            <button
                onClick={onRetriage}
                disabled={triggering}
                className="btn btn-ghost"
                style={{ width: '100%', marginBottom: 16, justifyContent: 'center' }}
            >
                {triggering ? 'Running…' : 'Re-run Claude triage'}
            </button>

            {trends.length > 0 && (
                <section style={{ marginBottom: 16 }}>
                    <h3 style={{ fontSize: 13, fontWeight: 700, margin: '0 0 8px', color: 'var(--text-primary)' }}>Trend signals ({trends.length})</h3>
                    {trends.slice(0, 5).map(t => (
                        <div key={t.id} style={{ fontSize: 12, padding: '6px 8px', background: 'rgba(245, 158, 11, 0.1)', borderRadius: 6, marginBottom: 4, border: '1px solid rgba(245, 158, 11, 0.3)', color: 'var(--text-primary)' }}>
                            <strong>{t.trend_type}</strong> · {t.today_count} today vs baseline {t.baseline_mean?.toFixed(1) ?? '—'} · {timeAgo(t.detected_at)}
                            {t.spike_ratio && ` · ${t.spike_ratio.toFixed(1)}×`}
                        </div>
                    ))}
                </section>
            )}

            <section>
                <h3 style={{ fontSize: 13, fontWeight: 700, margin: '0 0 8px', color: 'var(--text-primary)' }}>
                    Claude reports ({reports.length})
                </h3>
                {reports.length === 0 ? (
                    <div style={{ fontSize: 12, color: 'var(--text-secondary)' }}>
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
            <div style={{ fontSize: 10, fontWeight: 600, color: 'var(--text-muted)', textTransform: 'uppercase' }}>{label}</div>
            <div style={{ color: 'var(--text-primary)' }}>{value}</div>
        </div>
    )
}

function ReportCard({ r, onReview, onCreatePr }: {
    r: Report; onReview: (id: string, status: string) => void; onCreatePr: () => void
}) {
    return (
        <div style={{
            padding: 12,
            border: '1px solid var(--border)',
            borderRadius: 8,
            marginBottom: 10,
            // Pending reports get a subtle amber wash; reviewed ones use the
            // deeper tertiary surface so they recede.
            background: r.review_status === 'pending'
                ? 'rgba(245, 158, 11, 0.08)'
                : 'var(--bg-tertiary)',
        }}>
            <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap', marginBottom: 6 }}>
                <Pill label={r.severity} color={SEVERITY_COLORS[r.severity] ?? '#6b7280'} />
                <Pill label={r.agent_owner} color="#475569" />
                <Pill label={r.review_status} color={STATUS_COLORS[r.review_status] ?? '#6b7280'} />
                <span style={{ fontSize: 11, color: 'var(--text-muted)', alignSelf: 'center' }}>
                    conf {r.confidence.toFixed(2)} · {r.trigger_reason} · {timeAgo(r.created_at)}
                </span>
            </div>

            <div style={{ fontWeight: 600, fontSize: 13, marginBottom: 4, color: 'var(--text-primary)' }}>{r.title}</div>
            <div style={{ fontSize: 12, color: 'var(--text-secondary)', marginBottom: 8, whiteSpace: 'pre-wrap' }}>{r.summary}</div>

            {r.invariant_violated && (
                <div style={{ fontSize: 11, color: 'var(--warning)', background: 'rgba(245, 158, 11, 0.12)', padding: '4px 8px', borderRadius: 4, marginBottom: 8 }}>
                    Invariant: {r.invariant_violated}
                </div>
            )}

            {r.file_path && (
                <div style={{ fontFamily: 'ui-monospace, monospace', fontSize: 11, color: 'var(--accent)', marginBottom: 4 }}>
                    → {r.file_path}
                </div>
            )}

            {r.code_diff && (
                <details style={{ fontSize: 11, marginBottom: 8 }}>
                    <summary style={{ cursor: 'pointer', color: 'var(--accent)' }}>View diff</summary>
                    <pre style={{ background: '#0a0a0f', color: '#e2e8f0', padding: 10, borderRadius: 6, overflow: 'auto', maxHeight: 300, marginTop: 6, fontSize: 11, border: '1px solid var(--border)' }}>
                        {r.code_diff}
                    </pre>
                </details>
            )}

            {r.pr_url ? (
                <a href={r.pr_url} target="_blank" rel="noreferrer" style={{ fontSize: 12, color: 'var(--success)', fontWeight: 600 }}>
                    ✓ PR open: {r.pr_url}
                </a>
            ) : (
                <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap' }}>
                    {r.file_path && r.code_diff && (
                        <button onClick={onCreatePr} className="btn btn-primary" style={{ padding: '4px 12px', fontSize: 12 }}>
                            Create PR
                        </button>
                    )}
                    {r.review_status === 'pending' && (
                        <>
                            <button onClick={() => onReview(r.id, 'approved')} className="btn btn-ghost" style={{ padding: '4px 12px', fontSize: 12 }}>Approve</button>
                            <button onClick={() => onReview(r.id, 'rejected')} className="btn btn-ghost" style={{ padding: '4px 12px', fontSize: 12 }}>Reject</button>
                        </>
                    )}
                </div>
            )}
        </div>
    )
}
