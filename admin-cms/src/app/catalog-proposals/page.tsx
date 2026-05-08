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

// Existing-value suggestions for inline edit dropdowns. Pulled once on
// page mount via the same `get_exercise_suggestions` action used by the
// exercise detail editor — keeps the operator's choices consistent with
// the canonical taxonomy already in the catalog.
type Suggestions = {
  muscles: string[]
  equipment_categories: string[]
  workout_types: string[]
  genders: string[]
}

const EMPTY_SUGGESTIONS: Suggestions = {
  muscles: [],
  equipment_categories: [],
  // Mirror the canonical list used by the per-exercise editor at
  // /exercises/[id] so the dropdown surface here doesn't drift from there.
  workout_types: ['Strength', 'Cardio', 'Stretch', 'Warmup', 'Plyometrics', 'Olympic Weightlifting', 'Strongman', 'Powerlifting'],
  genders: ['Male', 'Female'],
}

// Fields the operator may edit inline before approving a proposal. We stash
// them all on a single object so the approve handler can compute a single
// update_exercise call.
type EditableState = {
  name: string
  gender: string | null
  primary_muscles: string[]
  secondary_muscles: string[]
  workout_type: string | null
  equipment_category: string | null
  is_compound: boolean | null
  duration_based: boolean | null
}

const EDITABLE_FIELDS: ReadonlyArray<keyof EditableState> = [
  'name', 'gender', 'primary_muscles', 'secondary_muscles',
  'workout_type', 'equipment_category', 'is_compound', 'duration_based',
] as const

function deepEqual(a: unknown, b: unknown): boolean {
  if (a === b) return true
  if (Array.isArray(a) && Array.isArray(b)) {
    if (a.length !== b.length) return false
    for (let i = 0; i < a.length; i++) if (!deepEqual(a[i], b[i])) return false
    return true
  }
  return false
}

// Slim exercise shape we need to render the per-proposal preview.
// We pull `select(*)` via the existing `get_exercise` admin action and only
// touch these fields, but we keep it `Record<string, unknown>` permissive so
// future schema additions don't break the type.
type ExerciseFull = {
  id: string
  name: string
  gender: string | null
  primary_muscles: string[] | null
  secondary_muscles: string[] | null
  workout_type: string | null
  equipment_category: string | null
  equipment: string | null
  is_compound: boolean | null
  duration_based: boolean | null
  video_filename: string | null
} & Record<string, unknown>

function exerciseToEditState(ex: ExerciseFull, after: ExerciseFull): EditableState {
  // The "after" exercise has the proposal already applied; we want the editor
  // to default to the post-approval state so the operator only has to touch
  // values that need overriding. Other catalog fields fall back to current.
  return {
    name: String(after.name ?? ex.name ?? ''),
    gender: (after.gender ?? ex.gender ?? null) as string | null,
    primary_muscles: asMuscleList(after.primary_muscles ?? ex.primary_muscles),
    secondary_muscles: asMuscleList(after.secondary_muscles ?? ex.secondary_muscles),
    workout_type: (after.workout_type ?? ex.workout_type ?? null) as string | null,
    equipment_category: (after.equipment_category ?? ex.equipment_category ?? null) as string | null,
    is_compound: (after.is_compound ?? ex.is_compound ?? null) as boolean | null,
    duration_based: (after.duration_based ?? ex.duration_based ?? null) as boolean | null,
  }
}

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
  const [suggestions, setSuggestions] = useState<Suggestions>(EMPTY_SUGGESTIONS)

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

  // One-shot suggestion fetch on mount. Reuses the same admin action as the
  // exercise detail editor so muscle / equipment / etc. dropdowns stay in
  // sync with whatever taxonomy already lives in the catalog.
  useEffect(() => {
    let cancelled = false
    const run = async () => {
      try {
        const data = await adminApi('get_exercise_suggestions') as Record<string, string[]>
        if (cancelled) return
        setSuggestions({
          muscles: Array.isArray(data?.muscles) ? data.muscles : [],
          equipment_categories: Array.isArray(data?.equipment_categories) ? data.equipment_categories : [],
          // Workout-type & gender are tightly bounded enums; ship a stable default
          // even if the admin endpoint comes back empty (cold catalog, network blip).
          workout_types: Array.isArray(data?.workout_types) && data.workout_types.length > 0
            ? data.workout_types : EMPTY_SUGGESTIONS.workout_types,
          genders: Array.isArray(data?.genders) && data.genders.length > 0
            ? data.genders : EMPTY_SUGGESTIONS.genders,
        })
      } catch {
        // Non-fatal — editors will fall back to plain inputs without dropdowns.
      }
    }
    void run()
    return () => { cancelled = true }
  }, [])

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
              suggestions={suggestions}
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
  suggestions,
  onChanged,
}: {
  p: ProposalRow
  exercise: ExerciseFull | null
  suggestions: Suggestions
  onChanged: () => void
}) {
  const [busy, setBusy] = useState(false)
  const [err, setErr] = useState<string | null>(null)
  const [videoFailed, setVideoFailed] = useState(false)

  // Inline-edit state for ALL editable fields. Initialized to the
  // after-approval preview state so the operator only has to touch values
  // that need overriding. Resets whenever the underlying exercise or proposal
  // changes (e.g. after a sibling approval triggers a parent reload).
  const buildInitialEdit = useCallback((): EditableState | null => {
    if (!exercise) return null
    const after = previewAfterProposal(exercise, p)
    return exerciseToEditState(exercise, after)
  }, [exercise, p])

  const [edit, setEdit] = useState<EditableState | null>(buildInitialEdit)

  useEffect(() => {
    setEdit(buildInitialEdit())
  }, [buildInitialEdit])

  const gates: string[] = []
  if (p.sister_corroborated) gates.push('SISTER')
  if (p.name_corroborated) gates.push('NAME')
  if (p.multi_report_count >= 2) gates.push(`MULTI×${p.multi_report_count}`)

  const decidable = p.status === 'pending' || p.status === 'blocked_core_exercise'
  const isCoreOverride = p.status === 'blocked_core_exercise' && p.operation === 'remove'

  // Compute the diff between the operator's chosen state and the current
  // catalog row. The approve handler uses this to drive a single
  // `update_exercise` call (or skip the call if nothing changed).
  const computeUpdates = useCallback((): Record<string, unknown> => {
    if (!exercise || !edit) return {}
    const updates: Record<string, unknown> = {}
    for (const f of EDITABLE_FIELDS) {
      const current = (exercise as Record<string, unknown>)[f]
      const next = (edit as Record<string, unknown>)[f]
      // Treat null/empty-string equivalently for scalar fields.
      const normCurrent = current === '' ? null : current
      const normNext = next === '' ? null : next
      if (!deepEqual(normCurrent, normNext)) {
        updates[f] = normNext
      }
    }
    return updates
  }, [exercise, edit])

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
      const updates = computeUpdates()
      const proposalField = p.field_name as keyof EditableState

      // Did the operator change the proposal's own field to something other
      // than what Claude proposed? If so we apply the override via
      // update_exercise and tag the proposal as manually overridden so the
      // RPC's apply path doesn't overwrite the operator's value.
      const claudeAppliedValue = exercise
        ? (previewAfterProposal(exercise, p) as Record<string, unknown>)[p.field_name]
        : null
      const editedValue = edit
        ? (edit as Record<string, unknown>)[p.field_name]
        : null
      const overrodeProposalField = !deepEqual(claudeAppliedValue, editedValue)

      // Strip the proposal's own field from `updates` if the operator kept
      // Claude's value — admin_apply_correction_proposal will write it. We
      // still want to write OTHER edits (name / gender / unrelated muscles).
      let updatesToSend: Record<string, unknown> = updates
      if (!overrodeProposalField && proposalField in updates) {
        const { [proposalField]: _droppedProposalField, ...rest } = updates as Record<string, unknown> & Record<typeof proposalField, unknown>
        void _droppedProposalField
        updatesToSend = rest
      }

      // 1. Save inline edits (other fields, plus proposal field if overridden).
      if (Object.keys(updatesToSend).length > 0) {
        const res = await adminApi('update_exercise', {
          exercise_id: p.exercise_id,
          updates: updatesToSend,
        }) as { error?: string; result?: { success?: boolean; error?: string } }
        if (res?.error || res?.result?.error || res?.result?.success === false) {
          setErr(res?.error || res?.result?.error || 'Save failed')
          return
        }
      }

      // 2. Resolve the proposal.
      if (overrodeProposalField) {
        // Operator overrode Claude — proposal value is no longer applicable.
        // Mark as rejected with a clear, machine-readable reason so future
        // audits know this wasn't a "Claude was wrong, discard" reject —
        // it was "operator wrote a better value inline".
        await adminApi('admin_reject_correction_proposal', {
          proposalId: p.id,
          reason: 'manual_override_via_inline_edit',
        })
      } else {
        // Operator accepted Claude's value (possibly with edits to other
        // fields). Use the standard apply path so the proposal lands as
        // 'applied' with the corroboration_kind = sister/name/multi noted.
        const res = await adminApi('admin_apply_correction_proposal', {
          proposalId: p.id,
        }) as { result?: { success?: boolean; error?: string } }
        if (!res?.result?.success) {
          setErr(res?.result?.error || 'Apply failed')
          return
        }
      }

      onChanged()
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
              className="w-full md:h-full md:max-h-96 object-cover bg-black"
            />
          ) : (
            <div className="w-full aspect-square grid place-items-center text-neutral-600 text-xs">
              {videoFilename ? 'video unavailable' : 'no video'}
            </div>
          )}
        </div>

        {/* ─── Right: header + editor ─────────────────────────────────── */}
        <div className="flex-1 p-4 min-w-0">
          {/* Header row — exercise name (editable) + Claude details + actions */}
          <div className="flex items-start justify-between gap-3 mb-3">
            <div className="min-w-0 flex-1">
              {edit ? (
                <input
                  value={edit.name}
                  onChange={(e) => setEdit((s) => s ? { ...s, name: e.target.value } : s)}
                  className="input input-sm w-full font-medium bg-neutral-900/60"
                  spellCheck={false}
                />
              ) : (
                <a
                  href={`/exercises/${p.exercise_id}`}
                  className="text-base font-medium hover:underline block truncate"
                >
                  {p.exercise_name}
                </a>
              )}
              <div className="flex flex-wrap items-center gap-1.5 mt-1.5">
                <span className={statusBadgeClass(p.status)}>{p.status}</span>
                <span className={operationBadgeClass(p.operation)}>{p.operation}</span>
                <span className="badge badge-neutral">{p.field_name}</span>
                <span className="text-xs text-neutral-500">conf {p.confidence.toFixed(2)}</span>
                <span className="text-xs text-neutral-500" title={p.proposed_at}>
                  · {timeAgo(p.proposed_at)}
                </span>
                <a
                  href={`/exercises/${p.exercise_id}`}
                  className="text-xs text-blue-400 hover:underline ml-1"
                  title="Open full exercise editor"
                >
                  full editor →
                </a>
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
                  title={isCoreOverride ? 'Override core-exercise lockout + save edits' : 'Save edits and apply'}
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

          {/* Editor — what the exercise WILL look like after Approve */}
          {edit && exercise ? (
            <InlineExerciseEditor
              edit={edit}
              setEdit={setEdit}
              proposal={p}
              before={exercise}
              suggestions={suggestions}
            />
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

// ─── InlineExerciseEditor ────────────────────────────────────────────────────
//
// Editable form for the operator to massage the exercise's final state before
// approving the proposal. Initial values come from the after-approval preview
// (so muscle adds appear pre-checked, equipment_category set values pre-filled,
// etc.) but every field is overridable. Values from the canonical taxonomy are
// surfaced via dropdowns for consistency — e.g. if Claude proposed
// `equipment_category=Training Cored` the operator can pick `TRX` instead.

function InlineExerciseEditor({
  edit,
  setEdit,
  proposal,
  before,
  suggestions,
}: {
  edit: EditableState
  setEdit: (updater: (s: EditableState | null) => EditableState | null) => void
  proposal: ProposalRow
  before: ExerciseFull
  suggestions: Suggestions
}) {
  const proposalField = proposal.field_name
  const op = proposal.operation
  const beforePM = asMuscleList(before.primary_muscles)
  const beforeSM = asMuscleList(before.secondary_muscles)

  const fieldRing = (field: string): string =>
    field === proposalField
      ? 'ring-1 ring-emerald-500/40 bg-emerald-600/5 rounded'
      : ''

  const labelClass = 'text-[10px] uppercase tracking-wide text-neutral-500 mb-1'

  const setMuscles = (which: 'primary_muscles' | 'secondary_muscles', next: string[]) => {
    setEdit((s) => s ? { ...s, [which]: next } : s)
  }

  // Render an editable list of muscle chips. Each chip is a small select; the
  // first dropdown option per chip is "(remove)" for one-click delete. An
  // "+ Add" button appends a fresh empty select.
  const renderMuscleEditor = (
    field: 'primary_muscles' | 'secondary_muscles',
    label: string,
  ) => {
    const arr = edit[field]
    const before = field === 'primary_muscles' ? beforePM : beforeSM
    return (
      <div className={`p-2 ${fieldRing(field)}`}>
        <div className={labelClass}>{label}</div>
        <div className="flex flex-wrap gap-1.5 items-center">
          {arr.map((m, idx) => {
            const wasAdded = !before.includes(m)
            return (
              <div key={`${field}-${idx}`} className="flex items-center">
                <select
                  value={m}
                  onChange={(e) => {
                    const next = [...arr]
                    if (e.target.value === '__remove__') {
                      next.splice(idx, 1)
                    } else {
                      next[idx] = e.target.value
                    }
                    setMuscles(field, next)
                  }}
                  className={
                    'text-xs rounded px-1.5 py-0.5 bg-neutral-900 border ' +
                    (wasAdded
                      ? 'border-emerald-500/60 text-emerald-200'
                      : 'border-neutral-700 text-neutral-200')
                  }
                >
                  <option value="__remove__">(remove)</option>
                  {/* Always include the current value so it stays selected even
                      if the suggestions list lags. */}
                  {!suggestions.muscles.includes(m) && (
                    <option value={m}>{m}</option>
                  )}
                  {suggestions.muscles.map((s) => (
                    <option key={s} value={s}>{s}</option>
                  ))}
                </select>
              </div>
            )
          })}
          <button
            type="button"
            onClick={() => {
              const candidate = suggestions.muscles[0] || 'Chest'
              setMuscles(field, [...arr, candidate])
            }}
            className="text-xs px-1.5 py-0.5 rounded border border-dashed border-neutral-600 text-neutral-400 hover:border-neutral-400 hover:text-neutral-200"
          >
            + Add muscle
          </button>
        </div>
        {/* Show what was removed so the operator sees the diff. */}
        {op === 'remove' && proposalField === field && (
          <div className="mt-1 flex flex-wrap gap-1">
            {before.filter((m) => !arr.includes(m)).map((m) => (
              <span
                key={`rm-${m}`}
                className="px-1.5 py-0.5 rounded text-[10px] bg-rose-600/15 text-rose-300 ring-1 ring-rose-500/40 line-through"
              >
                {m}
              </span>
            ))}
          </div>
        )}
      </div>
    )
  }

  return (
    <div className="border border-neutral-800 rounded-md p-3 bg-neutral-900/50 space-y-3">
      <div className="text-[10px] uppercase tracking-wide text-neutral-500">
        Edit fields then click Approve to save + apply
      </div>

      {/* Muscle editors */}
      <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
        {renderMuscleEditor('primary_muscles', 'Primary muscles')}
        {renderMuscleEditor('secondary_muscles', 'Secondary muscles')}
      </div>

      {/* Scalar dropdowns */}
      <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-5 gap-3">
        <div className={`p-2 ${fieldRing('gender')}`}>
          <div className={labelClass}>Gender</div>
          <select
            value={edit.gender ?? ''}
            onChange={(e) => setEdit((s) => s ? { ...s, gender: e.target.value || null } : s)}
            className="input input-sm w-full bg-neutral-900"
          >
            <option value="">—</option>
            {suggestions.genders.map((g) => (
              <option key={g} value={g}>{g}</option>
            ))}
          </select>
        </div>
        <div className={`p-2 ${fieldRing('workout_type')}`}>
          <div className={labelClass}>Workout type</div>
          <select
            value={edit.workout_type ?? ''}
            onChange={(e) => setEdit((s) => s ? { ...s, workout_type: e.target.value || null } : s)}
            className="input input-sm w-full bg-neutral-900"
          >
            <option value="">—</option>
            {edit.workout_type && !suggestions.workout_types.includes(edit.workout_type) && (
              <option value={edit.workout_type}>{edit.workout_type}</option>
            )}
            {suggestions.workout_types.map((w) => (
              <option key={w} value={w}>{w}</option>
            ))}
          </select>
        </div>
        <div className={`p-2 ${fieldRing('equipment_category')}`}>
          <div className={labelClass}>Equipment</div>
          <select
            value={edit.equipment_category ?? ''}
            onChange={(e) => setEdit((s) => s ? { ...s, equipment_category: e.target.value || null } : s)}
            className="input input-sm w-full bg-neutral-900"
          >
            <option value="">—</option>
            {edit.equipment_category && !suggestions.equipment_categories.includes(edit.equipment_category) && (
              <option value={edit.equipment_category}>{edit.equipment_category}</option>
            )}
            {suggestions.equipment_categories.map((eq) => (
              <option key={eq} value={eq}>{eq}</option>
            ))}
          </select>
        </div>
        <div className={`p-2 ${fieldRing('is_compound')}`}>
          <div className={labelClass}>Compound</div>
          <select
            value={edit.is_compound === null ? '' : edit.is_compound ? 'true' : 'false'}
            onChange={(e) => {
              const v = e.target.value
              setEdit((s) => s ? { ...s, is_compound: v === '' ? null : v === 'true' } : s)
            }}
            className="input input-sm w-full bg-neutral-900"
          >
            <option value="">—</option>
            <option value="true">Yes</option>
            <option value="false">No</option>
          </select>
        </div>
        <div className={`p-2 ${fieldRing('duration_based')}`}>
          <div className={labelClass}>Duration-based</div>
          <select
            value={edit.duration_based === null ? '' : edit.duration_based ? 'true' : 'false'}
            onChange={(e) => {
              const v = e.target.value
              setEdit((s) => s ? { ...s, duration_based: v === '' ? null : v === 'true' } : s)
            }}
            className="input input-sm w-full bg-neutral-900"
          >
            <option value="">—</option>
            <option value="true">Yes</option>
            <option value="false">No</option>
          </select>
        </div>
      </div>
    </div>
  )
}
