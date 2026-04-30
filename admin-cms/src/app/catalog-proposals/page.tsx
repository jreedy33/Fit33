'use client'

import { useCallback, useEffect, useMemo, useState } from 'react'
import AdminShell from '@/components/AdminShell'
import { adminApi } from '@/lib/api'

// ─── helpers ─────────────────────────────────────────────────────────────────

function timeAgo(iso: string | null | undefined): string {
  if (!iso) return '—'
  const t = new Date(iso).getTime()
  if (Number.isNaN(t)) return '—'
  const diff = Date.now() - t
  if (diff < 0) return 'just now'
  const sec = Math.floor(diff / 1000)
  if (sec < 60) return sec <= 5 ? 'just now' : `${sec}s ago`
  const m = Math.floor(sec / 60)
  if (m < 60) return `${m}m ago`
  const h = Math.floor(m / 60)
  if (h < 24) return `${h}h ago`
  const d = Math.floor(h / 24)
  return `${d}d ago`
}

function statusBadgeClass(status: string): string {
  switch (status) {
    case 'applied': return 'badge badge-success'
    case 'pending': return 'badge badge-info'
    case 'blocked_core_exercise': return 'badge badge-warning'
    case 'rejected': return 'badge badge-danger'
    case 'superseded': return 'badge badge-neutral'
    default: return 'badge badge-neutral'
  }
}

function operationBadgeClass(op: string): string {
  switch (op) {
    case 'add': return 'badge badge-info'
    case 'set': return 'badge badge-neutral'
    case 'remove': return 'badge badge-warning'
    default: return 'badge badge-neutral'
  }
}

// ─── types ───────────────────────────────────────────────────────────────────

type ProposalRow = {
  id: string
  exercise_id: string
  exercise_name: string
  field_name: string
  operation: string
  proposed_value: unknown
  evidence: string
  confidence: number
  sister_corroborated: boolean
  name_corroborated: boolean
  multi_report_count: number
  status: string
  applied_correction_id: string | null
  rejected_reason: string | null
  source_report_id: string | null
  proposed_at: string
  decided_at: string | null
}

type StatsResponse = {
  counts: Record<string, number>
  total: number
}

// ─── page ────────────────────────────────────────────────────────────────────

const PAGE_SIZE = 50

export default function CatalogProposalsPage() {
  const [statusFilter, setStatusFilter] = useState<string>('pending')
  const [proposals, setProposals] = useState<ProposalRow[]>([])
  const [total, setTotal] = useState(0)
  const [stats, setStats] = useState<StatsResponse | null>(null)
  const [page, setPage] = useState(0)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  const totalPages = Math.max(1, Math.ceil(total / PAGE_SIZE))

  const load = useCallback(async () => {
    setLoading(true)
    setError(null)
    try {
      const [proposalRes, statsRes] = await Promise.all([
        adminApi('list_correction_proposals', {
          status: statusFilter || undefined,
          limit: PAGE_SIZE,
          offset: page * PAGE_SIZE,
        }),
        adminApi('get_correction_proposal_stats', {}),
      ])
      setProposals(((proposalRes as { rows?: ProposalRow[] }).rows) || [])
      setTotal((proposalRes as { total?: number }).total || 0)
      setStats((statsRes as StatsResponse) || null)
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Failed to load proposals')
    } finally {
      setLoading(false)
    }
  }, [statusFilter, page])

  useEffect(() => { void load() }, [load])

  const handleStatusChange = (s: string) => {
    setPage(0)
    setStatusFilter(s)
  }

  const groupedByExercise = useMemo(() => {
    const m = new Map<string, ProposalRow[]>()
    for (const p of proposals) {
      const arr = m.get(p.exercise_id) || []
      arr.push(p)
      m.set(p.exercise_id, arr)
    }
    return m
  }, [proposals])

  return (
    <AdminShell>
      <div className="page-header">
        <div>
          <h1 className="text-2xl font-semibold">Catalog Proposals Queue</h1>
          <p className="text-sm text-neutral-400 mt-1">
            Every Claude-proposed catalog change lands here. The corroboration ladder
            (sister / name / multi-report) decides which auto-apply. The rest sit for review.
          </p>
        </div>
      </div>

      {/* ─── Stats strip ──────────────────────────────────────────────────── */}
      {stats && (
        <div className="grid grid-cols-2 md:grid-cols-5 gap-3 mb-6">
          {[
            { key: 'pending', label: 'Pending review' },
            { key: 'applied', label: 'Auto-applied' },
            { key: 'blocked_core_exercise', label: 'Blocked (core)' },
            { key: 'rejected', label: 'Rejected' },
            { key: 'superseded', label: 'Superseded' },
          ].map(({ key, label }) => (
            <button
              key={key}
              onClick={() => handleStatusChange(key)}
              className={`card text-left p-3 hover:bg-neutral-800/40 transition ${statusFilter === key ? 'ring-1 ring-blue-500' : ''}`}
            >
              <div className="text-xs text-neutral-400">{label}</div>
              <div className="text-2xl font-semibold mt-1">{stats.counts[key] || 0}</div>
            </button>
          ))}
        </div>
      )}

      {/* ─── Filter bar ──────────────────────────────────────────────────── */}
      <div className="flex items-center gap-3 mb-4">
        <label className="text-sm text-neutral-400">Filter by status:</label>
        <select
          value={statusFilter}
          onChange={(e) => handleStatusChange(e.target.value)}
          className="input input-sm"
        >
          <option value="">All</option>
          <option value="pending">Pending</option>
          <option value="applied">Applied</option>
          <option value="blocked_core_exercise">Blocked (core)</option>
          <option value="rejected">Rejected</option>
          <option value="superseded">Superseded</option>
        </select>
        <div className="text-sm text-neutral-500">
          {total} {total === 1 ? 'proposal' : 'proposals'} · page {page + 1} of {totalPages}
        </div>
      </div>

      {error && <div className="alert alert-error mb-4">{error}</div>}

      {/* ─── Proposals table ─────────────────────────────────────────────── */}
      {loading ? (
        <div className="text-neutral-500 py-8 text-center">Loading…</div>
      ) : proposals.length === 0 ? (
        <div className="text-neutral-500 py-12 text-center">
          No proposals match this filter.
        </div>
      ) : (
        <div className="space-y-3">
          {Array.from(groupedByExercise.entries()).map(([exerciseId, group]) => (
            <div key={exerciseId} className="card p-4">
              <div className="flex items-center justify-between mb-3">
                <a
                  href={`/exercises/${exerciseId}`}
                  className="text-base font-medium hover:underline"
                >
                  {group[0].exercise_name}
                </a>
                <span className="text-xs text-neutral-500">
                  {group.length} {group.length === 1 ? 'proposal' : 'proposals'}
                </span>
              </div>

              <div className="space-y-2">
                {group.map((p) => (
                  <ProposalCard key={p.id} p={p} onChanged={() => void load()} />
                ))}
              </div>
            </div>
          ))}
        </div>
      )}

      {/* ─── Pagination ──────────────────────────────────────────────────── */}
      {totalPages > 1 && (
        <div className="flex items-center justify-center gap-2 mt-6">
          <button
            className="btn btn-sm"
            disabled={page <= 0 || loading}
            onClick={() => setPage((p) => Math.max(0, p - 1))}
          >Previous</button>
          <span className="text-sm text-neutral-400 px-3">
            Page {page + 1} of {totalPages}
          </span>
          <button
            className="btn btn-sm"
            disabled={page >= totalPages - 1 || loading}
            onClick={() => setPage((p) => p + 1)}
          >Next</button>
        </div>
      )}
    </AdminShell>
  )
}

// ─── ProposalCard ─────────────────────────────────────────────────────────────

function ProposalCard({ p, onChanged }: { p: ProposalRow; onChanged: () => void }) {
  const [busy, setBusy] = useState(false)
  const [err, setErr] = useState<string | null>(null)

  const gates: string[] = []
  if (p.sister_corroborated) gates.push('SISTER')
  if (p.name_corroborated) gates.push('NAME')
  if (p.multi_report_count >= 2) gates.push(`MULTI×${p.multi_report_count}`)

  const decidable = p.status === 'pending' || p.status === 'blocked_core_exercise'
  const isCoreOverride = p.status === 'blocked_core_exercise' && p.operation === 'remove'

  const approve = async () => {
    if (!decidable) return
    if (isCoreOverride) {
      const ok = window.confirm(
        `OVERRIDE the core-exercise lockout for "${p.exercise_name}"?\n\n` +
        `Field:     ${p.field_name}\n` +
        `Operation: ${p.operation}\n` +
        `Value:     ${JSON.stringify(p.proposed_value)}\n\n` +
        `This will permanently change a canonical exercise.`,
      )
      if (!ok) return
    }
    setBusy(true); setErr(null)
    try {
      const res = await adminApi('admin_apply_correction_proposal', { proposalId: p.id }) as {
        result?: { success?: boolean; error?: string }
      }
      if (!res?.result?.success) {
        setErr(res?.result?.error || 'Apply failed')
      } else {
        onChanged()
      }
    } catch (e) {
      setErr(e instanceof Error ? e.message : 'Apply failed')
    } finally {
      setBusy(false)
    }
  }

  const reject = async () => {
    if (!decidable) return
    const reason = window.prompt(
      `Reject this proposal for "${p.exercise_name}"?\nOptional reason:`,
      'manual_admin_reject',
    )
    if (reason === null) return
    setBusy(true); setErr(null)
    try {
      await adminApi('admin_reject_correction_proposal', { proposalId: p.id, reason })
      onChanged()
    } catch (e) {
      setErr(e instanceof Error ? e.message : 'Reject failed')
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="border border-neutral-800 rounded-md p-3 bg-neutral-900/40">
      <div className="flex flex-wrap items-center gap-2 mb-2">
        <span className={statusBadgeClass(p.status)}>{p.status}</span>
        <span className={operationBadgeClass(p.operation)}>{p.operation}</span>
        <span className="badge badge-neutral">{p.field_name}</span>
        <span className="text-xs text-neutral-500">conf {p.confidence.toFixed(2)}</span>
        <span className="ml-auto text-xs text-neutral-500" title={p.proposed_at}>
          {timeAgo(p.proposed_at)}
        </span>
      </div>

      <div className="font-mono text-sm bg-neutral-950 rounded px-2 py-1 mb-2 break-words">
        {JSON.stringify(p.proposed_value)}
      </div>

      {p.evidence && (
        <div className="text-sm text-neutral-300 mb-2">
          <span className="text-neutral-500">Evidence: </span>
          {p.evidence}
        </div>
      )}

      <div className="flex flex-wrap items-center gap-2 text-xs">
        <span className="text-neutral-500">Gates:</span>
        {gates.length === 0 ? (
          <span className="text-neutral-600">none yet</span>
        ) : (
          gates.map((g) => (
            <span key={g} className="badge badge-info">{g}</span>
          ))
        )}
        {p.rejected_reason && (
          <span className="text-amber-400 ml-2">⚠ {p.rejected_reason}</span>
        )}
        {p.source_report_id && (
          <a
            href={`/workout-intelligence/${p.source_report_id}`}
            className="text-blue-400 hover:underline"
          >
            View source report →
          </a>
        )}

        {decidable && (
          <div className="ml-auto flex items-center gap-2">
            <button
              onClick={approve}
              disabled={busy}
              className={`btn btn-sm ${isCoreOverride ? 'btn-warning' : 'btn-success'}`}
              title={isCoreOverride ? 'Override core-exercise lockout' : 'Approve and apply'}
            >
              {busy ? '…' : isCoreOverride ? 'Override' : 'Approve'}
            </button>
            <button
              onClick={reject}
              disabled={busy}
              className="btn btn-sm btn-danger"
            >
              Reject
            </button>
          </div>
        )}
      </div>

      {err && <div className="alert alert-error mt-2 text-xs">{err}</div>}
    </div>
  )
}
