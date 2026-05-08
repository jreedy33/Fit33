'use client'

import { useCallback, useEffect, useState } from 'react'
import AdminShell from '@/components/AdminShell'
import { adminApi } from '@/lib/api'

// ─── constants ───────────────────────────────────────────────────────────────

// Exercise videos live on Cloudflare R2 under `${R2_BASE}/${video_filename}`.
// Same pattern used by `admin-cms/src/app/exercises/[id]/page.tsx` — keep in sync
// if that base ever changes. Don't `encodeURIComponent` the filename: filenames
// contain parentheses like `(Dumbbell)` and the bucket serves them raw
// (admin-cms-rules.mdc invariant 24).
const R2_BASE = 'https://pub-7838a3e2cbc24d59a6c4d2b2d6239bea.r2.dev'

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

// Slim exercise shape we need to render the per-proposal preview.
// We pull `select(*)` via the existing `get_exercise` admin action and only
// touch these fields, but we keep it `Record<string, unknown>` permissive so
// future schema additions don't break the type.
type ExerciseFull = {
  id: string
  name: string
  primary_muscles: string[] | null
  secondary_muscles: string[] | null
  workout_type: string | null
  equipment_category: string | null
  equipment: string | null
  is_compound: boolean | null
  duration_based: boolean | null
  video_filename: string | null
} & Record<string, unknown>

// Apply a single proposal's diff to the current exercise state and return
// what the exercise WOULD look like if the operator approves this proposal
// alone. Pure — does not mutate. Used for the per-proposal preview card.
function previewAfterProposal(ex: ExerciseFull, p: ProposalRow): ExerciseFull {
  const next: ExerciseFull = { ...ex }
  const val = p.proposed_value
  const field = p.field_name as keyof ExerciseFull
  switch (p.operation) {
    case 'add': {
      if (!Array.isArray(val)) return next
      const existing = (next[field] as string[] | null) || []
      const merged = Array.from(new Set([...existing, ...(val as string[])]))
      ;(next as Record<string, unknown>)[p.field_name] = merged
      return next
    }
    case 'remove': {
      if (!Array.isArray(val)) return next
      const existing = (next[field] as string[] | null) || []
      const removed = new Set(val as string[])
      ;(next as Record<string, unknown>)[p.field_name] = existing.filter((m) => !removed.has(m))
      return next
    }
    case 'set': {
      ;(next as Record<string, unknown>)[p.field_name] = val
      return next
    }
    default:
      return next
  }
}

function asMuscleList(val: unknown): string[] {
  if (Array.isArray(val)) return val.filter((x): x is string => typeof x === 'string')
  return []
}

function fmtBool(v: unknown): string {
  if (v === true) return 'Yes'
  if (v === false) return 'No'
  return '—'
}

function fmtScalar(v: unknown): string {
  if (v === null || v === undefined || v === '') return '—'
  return String(v)
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
  // Per-exercise full row cache for video + preview. Keyed by exercise_id.
  // We refetch ONLY the ids we don't have, plus the ids whose proposal status
  // just changed (since approving a proposal may have applied its diff to the
  // catalog row, which affects future preview computations on sibling proposals
  // for the same exercise).
  const [exerciseMap, setExerciseMap] = useState<Record<string, ExerciseFull>>({})

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
      const rows = (proposalRes as { rows?: ProposalRow[] }).rows || []
      setProposals(rows)
      setTotal((proposalRes as { total?: number }).total || 0)
      setStats((statsRes as StatsResponse) || null)

      // Always re-fetch every exercise visible on this page. The set is small
      // (≤PAGE_SIZE unique ids) and re-fetching is cheaper than tracking which
      // ids need invalidation across approve/reject cycles.
      const uniqIds = Array.from(new Set(rows.map((r) => r.exercise_id)))
      if (uniqIds.length > 0) {
        const fetched = await Promise.all(
          uniqIds.map(async (id) => {
            try {
              const r = await adminApi('get_exercise', { exercise_id: id }) as { exercise?: ExerciseFull }
              return r.exercise || null
            } catch { return null }
          }),
        )
        const next: Record<string, ExerciseFull> = {}
        for (const ex of fetched) {
          if (ex && typeof ex.id === 'string') next[ex.id] = ex
        }
        setExerciseMap(next)
      } else {
        setExerciseMap({})
      }
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

      {/* ─── Proposals list ──────────────────────────────────────────────── */}
      {loading ? (
        <div className="text-neutral-500 py-8 text-center">Loading…</div>
      ) : proposals.length === 0 ? (
        <div className="text-neutral-500 py-12 text-center">
          No proposals match this filter.
        </div>
      ) : (
        <div className="space-y-3">
          {proposals.map((p) => (
            <ProposalCard
              key={p.id}
              p={p}
              exercise={exerciseMap[p.exercise_id] || null}
              onChanged={() => void load()}
            />
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
//
// Layout:
//
//   ┌─────────────┬────────────────────────────────────────────────────┐
//   │             │ Bench Press (Cable)         [pending] [add] [...]  │
//   │   [video]   │ "sister Bench Press (DB) lists Triceps as ..."     │
//   │             │                              [Approve]  [Reject]   │
//   │             ├────────────────────────────────────────────────────┤
//   │             │ Primary    Secondary       Workout type            │
//   │             │ Chest      Triceps (added) Strength                │
//   │             │ ...                                                │
//   └─────────────┴────────────────────────────────────────────────────┘
//
// `exercise` is the current catalog row (as live in `exercises` table). We
// render the post-approval state by passing it through `previewAfterProposal`.
// If `exercise` is null (admin-fetch failed for some reason), we fall back to
// the pre-2026-05 terse JSON view so the operator can still decide.

function ProposalCard({
  p,
  exercise,
  onChanged,
}: {
  p: ProposalRow
  exercise: ExerciseFull | null
  onChanged: () => void
}) {
  const [busy, setBusy] = useState(false)
  const [err, setErr] = useState<string | null>(null)
  const [videoFailed, setVideoFailed] = useState(false)

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

  const videoFilename = exercise?.video_filename || null
  const videoUrl = videoFilename && !videoFailed ? `${R2_BASE}/${videoFilename}` : null

  // Compute post-state preview if we have the exercise; null otherwise.
  const after = exercise ? previewAfterProposal(exercise, p) : null

  return (
    <div className="card p-0 overflow-hidden">
      <div className="flex flex-col md:flex-row gap-0">
        {/* ─── Left: video ─────────────────────────────────────────────── */}
        <div className="md:w-72 md:flex-shrink-0 bg-neutral-950 grid place-items-center">
          {videoUrl ? (
            <video
              key={videoUrl}
              src={videoUrl}
              autoPlay
              muted
              loop
              playsInline
              onError={() => setVideoFailed(true)}
              className="w-full md:h-full md:max-h-72 object-cover bg-black"
            />
          ) : (
            <div className="w-full aspect-square grid place-items-center text-neutral-600 text-xs">
              {videoFilename ? 'video unavailable' : 'no video'}
            </div>
          )}
        </div>

        {/* ─── Right: header + preview ────────────────────────────────── */}
        <div className="flex-1 p-4 min-w-0">
          {/* Header row — exercise name + Claude details + actions */}
          <div className="flex items-start justify-between gap-3 mb-3">
            <div className="min-w-0 flex-1">
              <a
                href={`/exercises/${p.exercise_id}`}
                className="text-base font-medium hover:underline block truncate"
              >
                {p.exercise_name}
              </a>
              <div className="flex flex-wrap items-center gap-1.5 mt-1.5">
                <span className={statusBadgeClass(p.status)}>{p.status}</span>
                <span className={operationBadgeClass(p.operation)}>{p.operation}</span>
                <span className="badge badge-neutral">{p.field_name}</span>
                <span className="text-xs text-neutral-500">conf {p.confidence.toFixed(2)}</span>
                <span className="text-xs text-neutral-500" title={p.proposed_at}>
                  · {timeAgo(p.proposed_at)}
                </span>
              </div>
              {p.evidence && (
                <div className="text-xs text-neutral-400 mt-2 italic leading-snug">
                  &ldquo;{p.evidence}&rdquo;
                </div>
              )}
            </div>

            {decidable && (
              <div className="flex flex-col gap-1.5 flex-shrink-0">
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

          {/* Gates + source report */}
          <div className="flex flex-wrap items-center gap-1.5 text-xs mb-3">
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
                className="text-blue-400 hover:underline ml-2"
              >
                source report →
              </a>
            )}
          </div>

          {/* Preview state — what the exercise WOULD look like after this proposal */}
          {after && exercise ? (
            <PreviewState before={exercise} after={after} proposal={p} />
          ) : (
            <div className="font-mono text-xs bg-neutral-950 rounded px-2 py-1.5 break-words text-neutral-400">
              proposed: {JSON.stringify(p.proposed_value)}
            </div>
          )}

          {err && <div className="alert alert-error mt-2 text-xs">{err}</div>}
        </div>
      </div>
    </div>
  )
}

// ─── PreviewState ────────────────────────────────────────────────────────────
//
// Renders the would-be-after state of the exercise as a compact key→value grid.
// The field that this proposal mutates is highlighted: green for adds, red
// strikethrough for removes, ring for sets. All other fields render plain.

function PreviewState({
  before,
  after,
  proposal,
}: {
  before: ExerciseFull
  after: ExerciseFull
  proposal: ProposalRow
}) {
  const changing = proposal.field_name
  const op = proposal.operation
  const beforePM = asMuscleList(before.primary_muscles)
  const beforeSM = asMuscleList(before.secondary_muscles)
  const afterPM = asMuscleList(after.primary_muscles)
  const afterSM = asMuscleList(after.secondary_muscles)

  // Compute per-row diff for muscle arrays so we can paint each chip.
  const renderMuscleChips = (afterArr: string[], beforeArr: string[], thisField: string) => {
    if (afterArr.length === 0 && beforeArr.length === 0) {
      return <span className="text-neutral-600 text-xs">—</span>
    }
    const isThisField = thisField === changing
    const removed = beforeArr.filter((m) => !afterArr.includes(m))
    return (
      <div className="flex flex-wrap gap-1">
        {afterArr.map((m) => {
          const wasPresent = beforeArr.includes(m)
          const isAdded = isThisField && op === 'add' && !wasPresent
          return (
            <span
              key={m}
              className={
                isAdded
                  ? 'px-1.5 py-0.5 rounded text-xs bg-emerald-600/30 text-emerald-300 ring-1 ring-emerald-500/60'
                  : 'px-1.5 py-0.5 rounded text-xs bg-neutral-800 text-neutral-200'
              }
            >
              {m}{isAdded ? ' (+)' : ''}
            </span>
          )
        })}
        {/* If this is the field being mutated AND op is remove, show the removed
            chip(s) struck through so the operator sees what's leaving. */}
        {isThisField && op === 'remove' && removed.map((m) => (
          <span
            key={`rm-${m}`}
            className="px-1.5 py-0.5 rounded text-xs bg-rose-600/20 text-rose-300 ring-1 ring-rose-500/50 line-through"
          >
            {m}
          </span>
        ))}
      </div>
    )
  }

  // Highlight ring class for the scalar field that's changing.
  const ringIfChanging = (field: string) =>
    field === changing && op === 'set'
      ? 'ring-1 ring-emerald-500/50 bg-emerald-600/10 rounded px-1.5 py-0.5'
      : ''

  const cellLabel = 'text-[10px] uppercase tracking-wide text-neutral-500 mb-1'
  const cellValue = 'text-sm text-neutral-200'

  return (
    <div className="border border-neutral-800 rounded-md p-3 bg-neutral-900/50">
      <div className="text-[10px] uppercase tracking-wide text-neutral-500 mb-2">
        After approval
      </div>
      {/* Top row: muscles */}
      <div className="grid grid-cols-1 sm:grid-cols-2 gap-3 mb-3">
        <div>
          <div className={cellLabel}>Primary muscles</div>
          {renderMuscleChips(afterPM, beforePM, 'primary_muscles')}
        </div>
        <div>
          <div className={cellLabel}>Secondary muscles</div>
          {renderMuscleChips(afterSM, beforeSM, 'secondary_muscles')}
        </div>
      </div>

      {/* Bottom row: scalar fields */}
      <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
        <div>
          <div className={cellLabel}>Workout type</div>
          <div className={`${cellValue} inline-block ${ringIfChanging('workout_type')}`}>
            {fmtScalar(after.workout_type)}
          </div>
        </div>
        <div>
          <div className={cellLabel}>Equipment</div>
          <div className={`${cellValue} inline-block ${ringIfChanging('equipment_category')}`}>
            {fmtScalar(after.equipment_category)}
          </div>
        </div>
        <div>
          <div className={cellLabel}>Compound</div>
          <div className={`${cellValue} inline-block ${ringIfChanging('is_compound')}`}>
            {fmtBool(after.is_compound)}
          </div>
        </div>
        <div>
          <div className={cellLabel}>Duration-based</div>
          <div className={`${cellValue} inline-block ${ringIfChanging('duration_based')}`}>
            {fmtBool(after.duration_based)}
          </div>
        </div>
      </div>
    </div>
  )
}
