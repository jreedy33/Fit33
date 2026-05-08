'use client'

import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
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

// Apply every proposal in `ps` sequentially to `ex`. Used to compute the
// combined post-approval state when one card represents multiple proposals
// for the same exercise (e.g. "add Hip Flexors" + "set workout_type=Strength"
// landing at once). Order doesn't matter for disjoint fields; for proposals
// on the same field, order matches the array order (which mirrors the queue).
function previewAfterAllProposals(ex: ExerciseFull, ps: ProposalRow[]): ExerciseFull {
  let state = ex
  for (const p of ps) state = previewAfterProposal(state, p)
  return state
}

function asMuscleList(val: unknown): string[] {
  if (Array.isArray(val)) return val.filter((x): x is string => typeof x === 'string')
  return []
}

// One card per exercise. The operator sees every Claude-proposed diff for
// that exercise stacked in a single editor and approves them all in one go.
type ProposalGroup = {
  exerciseId: string
  exerciseName: string
  proposals: ProposalRow[]
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

  // Optimistic-update bookkeeping. When the operator clicks Approve/Reject we
  // remove the card from `proposals` immediately and fire the actual save in
  // the background; `inFlightSaves` powers the "saving N…" ribbon and
  // `failedSaves` surfaces any background errors so the operator can retry.
  const [inFlightSaves, setInFlightSaves] = useState(0)
  const [failedSaves, setFailedSaves] = useState<
    Array<{ key: string; proposalId: string; exerciseName: string; action: 'approve' | 'reject'; error: string }>
  >([])
  // Guards against repeated auto-loads when a load returns no new rows. Reset
  // any time `total` changes (i.e. server has fresher data to pull).
  const autoLoadAttemptedRef = useRef(false)

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

  // Reset the auto-load guard whenever a load updates `total` so a follow-up
  // empty page can trigger one fetch. Without this the operator gets stuck on
  // "No proposals match this filter" after exhausting a page even though more
  // exist on the server.
  useEffect(() => {
    autoLoadAttemptedRef.current = false
  }, [total])

  // When a page is fully approved/rejected away (proposals.length === 0) but
  // the server still has more pending, auto-pull the next batch so the
  // operator never hits a manual "Refresh" wall mid-flow.
  useEffect(() => {
    if (loading) return
    if (proposals.length > 0) return
    if (total <= 0) return
    if (autoLoadAttemptedRef.current) return
    autoLoadAttemptedRef.current = true
    void load()
  }, [proposals.length, total, loading, load])

  // ─── Optimistic helpers (passed down to ExerciseProposalCard) ────────────
  // Cards now represent a GROUP of proposals (one per exercise), so the
  // helpers operate on arrays of proposals to keep the bookkeeping atomic
  // for an exercise — partial state is hard to reason about visually.
  const removeProposalsOptimistic = useCallback((ids: string[]) => {
    if (ids.length === 0) return
    const idSet = new Set(ids)
    setProposals((prev) => prev.filter((p) => !idSet.has(p.id)))
    setTotal((t) => Math.max(0, t - ids.length))
  }, [])

  const noteSaveStart = useCallback(() => {
    setInFlightSaves((n) => n + 1)
  }, [])

  const noteSaveSuccess = useCallback((counts: { applied: number; rejected: number }) => {
    setInFlightSaves((n) => Math.max(0, n - 1))
    // Optimistically nudge the matching stats counters so the strip stays
    // honest without a full refetch. The operator can hit Refresh if they
    // care about exact counts (e.g. blocked_core_exercise transitions).
    setStats((prev) => {
      if (!prev) return prev
      const c = { ...prev.counts }
      c.pending = Math.max(0, (c.pending || 0) - counts.applied - counts.rejected)
      c.applied = (c.applied || 0) + counts.applied
      c.rejected = (c.rejected || 0) + counts.rejected
      return { ...prev, counts: c }
    })
  }, [])

  const noteSaveFailure = useCallback((args: {
    failedProposals: ProposalRow[]
    exerciseName: string
    action: 'approve' | 'reject'
    error: string
    successCounts?: { applied: number; rejected: number }
  }) => {
    setInFlightSaves((n) => Math.max(0, n - 1))
    setFailedSaves((prev) => [
      ...prev,
      {
        key: `${args.failedProposals[0]?.id ?? 'group'}-${Date.now()}`,
        proposalId: args.failedProposals[0]?.id ?? 'group',
        exerciseName: args.exerciseName,
        action: args.action,
        error: args.error,
      },
    ])
    // Re-inject failed proposals at the top of the list so the operator can
    // retry without paginating. Some proposals in the same group may have
    // succeeded — those stay removed and we credit them to the stats.
    if (args.failedProposals.length > 0) {
      setProposals((prev) => {
        const have = new Set(prev.map((x) => x.id))
        const toAdd = args.failedProposals.filter((p) => !have.has(p.id))
        return toAdd.length > 0 ? [...toAdd, ...prev] : prev
      })
      setTotal((t) => t + args.failedProposals.length)
    }
    if (args.successCounts && (args.successCounts.applied > 0 || args.successCounts.rejected > 0)) {
      setStats((prev) => {
        if (!prev) return prev
        const c = { ...prev.counts }
        c.pending = Math.max(0, (c.pending || 0) - args.successCounts!.applied - args.successCounts!.rejected)
        c.applied = (c.applied || 0) + args.successCounts!.applied
        c.rejected = (c.rejected || 0) + args.successCounts!.rejected
        return { ...prev, counts: c }
      })
    }
  }, [])

  const dismissFailure = useCallback((key: string) => {
    setFailedSaves((prev) => prev.filter((f) => f.key !== key))
  }, [])

  // Group the flat `proposals` array by exercise so we render one card per
  // exercise. Insertion order is preserved (first proposal's index defines
  // the group's position), which matches the operator's queue intuition.
  const groupedProposals: ProposalGroup[] = useMemo(() => {
    const map = new Map<string, ProposalGroup>()
    const order: string[] = []
    for (const p of proposals) {
      let g = map.get(p.exercise_id)
      if (!g) {
        g = { exerciseId: p.exercise_id, exerciseName: p.exercise_name, proposals: [] }
        map.set(p.exercise_id, g)
        order.push(p.exercise_id)
      }
      g.proposals.push(p)
    }
    return order.map((id) => map.get(id)!)
  }, [proposals])

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
          {total} {total === 1 ? 'proposal' : 'proposals'} across {groupedProposals.length}{' '}
          {groupedProposals.length === 1 ? 'exercise' : 'exercises'} · page {page + 1} of {totalPages}
        </div>
        <button
          onClick={() => void load()}
          disabled={loading}
          className="btn btn-sm btn-ghost ml-auto"
          title="Reload proposals + stats from the server"
        >
          {loading ? 'Refreshing…' : 'Refresh'}
        </button>
      </div>

      {error && <div className="alert alert-error mb-4">{error}</div>}

      {/* ─── Background-save status ──────────────────────────────────────── */}
      {(inFlightSaves > 0 || failedSaves.length > 0) && (
        <div className="mb-4 space-y-2">
          {inFlightSaves > 0 && (
            <div className="flex items-center gap-2 text-xs text-neutral-400 bg-neutral-900/60 border border-neutral-800 rounded px-3 py-2">
              <span className="inline-block w-2 h-2 rounded-full bg-blue-500 animate-pulse" />
              Saving {inFlightSaves} {inFlightSaves === 1 ? 'change' : 'changes'} in the background…
            </div>
          )}
          {failedSaves.map((f) => (
            <div
              key={f.key}
              className="flex items-start justify-between gap-3 text-xs bg-rose-950/50 border border-rose-800 rounded px-3 py-2"
            >
              <div className="min-w-0 flex-1">
                <div className="text-rose-300 font-medium">
                  Failed to {f.action === 'approve' ? 'approve' : 'reject'}: {f.exerciseName}
                </div>
                <div className="text-rose-400 mt-0.5 break-words">{f.error}</div>
                <div className="text-rose-500 mt-0.5">
                  Proposal restored to the top of the list — review and retry, or click Refresh to reload from server.
                </div>
              </div>
              <button
                onClick={() => dismissFailure(f.key)}
                className="text-rose-300 hover:text-rose-100 flex-shrink-0"
                aria-label="Dismiss"
              >
                ✕
              </button>
            </div>
          ))}
        </div>
      )}

      {/* ─── Proposals list ──────────────────────────────────────────────── */}
      {loading ? (
        <div className="text-neutral-500 py-8 text-center">Loading…</div>
      ) : groupedProposals.length === 0 ? (
        <div className="text-neutral-500 py-12 text-center">
          No proposals match this filter.
        </div>
      ) : (
        <div className="space-y-3">
          {groupedProposals.map((g) => (
            <ExerciseProposalCard
              key={g.exerciseId}
              group={g}
              exercise={exerciseMap[g.exerciseId] || null}
              suggestions={suggestions}
              onOptimisticRemove={removeProposalsOptimistic}
              onSaveStart={noteSaveStart}
              onSaveSuccess={noteSaveSuccess}
              onSaveFailure={noteSaveFailure}
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

// ─── ExerciseProposalCard ────────────────────────────────────────────────────
//
// One card per exercise. Stacks every Claude-proposed diff for that exercise
// into a single editor so the operator approves them all at once. Layout:
//
//   ┌─────────────┬────────────────────────────────────────────────────┐
//   │             │ Bench Press (Cable)            [Approve]  [Reject]  │
//   │   [video]   │ [add primary_muscles] [set workout_type] [...]      │
//   │             │ "sister Bench Press (DB) lists Triceps as ..."      │
//   │             ├────────────────────────────────────────────────────┤
//   │             │ Primary    Secondary       Workout type             │
//   │             │ Chest      Triceps (added) Strength                 │
//   │             │ ...                                                 │
//   └─────────────┴────────────────────────────────────────────────────┘
//
// `exercise` is the current catalog row. We render the combined post-approval
// state by replaying every proposal in the group through `previewAfterProposal`.
// If `exercise` is null (admin-fetch failed) we fall back to a terse JSON dump.

function ExerciseProposalCard({
  group,
  exercise,
  suggestions,
  onOptimisticRemove,
  onSaveStart,
  onSaveSuccess,
  onSaveFailure,
}: {
  group: ProposalGroup
  exercise: ExerciseFull | null
  suggestions: Suggestions
  onOptimisticRemove: (ids: string[]) => void
  onSaveStart: () => void
  onSaveSuccess: (counts: { applied: number; rejected: number }) => void
  onSaveFailure: (args: {
    failedProposals: ProposalRow[]
    exerciseName: string
    action: 'approve' | 'reject'
    error: string
    successCounts?: { applied: number; rejected: number }
  }) => void
}) {
  const [busy, setBusy] = useState(false)
  const [videoFailed, setVideoFailed] = useState(false)

  // Combined post-approval edit state. Walks every proposal in the group
  // through `previewAfterProposal` so the editor lands on the final intent.
  const buildInitialEdit = useCallback((): EditableState | null => {
    if (!exercise) return null
    const after = previewAfterAllProposals(exercise, group.proposals)
    return exerciseToEditState(exercise, after)
  }, [exercise, group])

  const [edit, setEdit] = useState<EditableState | null>(buildInitialEdit)

  useEffect(() => {
    setEdit(buildInitialEdit())
  }, [buildInitialEdit])

  // All fields touched by AT LEAST ONE proposal in this group. Drives the
  // emerald-ring highlight so the operator can spot Claude's affected fields
  // when the group has many proposals on the same exercise.
  const touchedFields = useMemo(() => {
    const s = new Set<string>()
    for (const p of group.proposals) s.add(p.field_name)
    return s
  }, [group.proposals])

  // Decidable iff every proposal in the group is in a decidable status.
  // (In practice they're all 'pending' from the same audit, but be safe.)
  const decidable = group.proposals.every((p) => p.status === 'pending' || p.status === 'blocked_core_exercise')
  const blockedProposals = group.proposals.filter((p) => p.status === 'blocked_core_exercise')

  // Aggregate gates across proposals — show union so the operator sees every
  // corroboration signal at a glance.
  const gates: string[] = []
  if (group.proposals.some((p) => p.sister_corroborated)) gates.push('SISTER')
  if (group.proposals.some((p) => p.name_corroborated)) gates.push('NAME')
  const maxMulti = Math.max(...group.proposals.map((p) => p.multi_report_count))
  if (maxMulti >= 2) gates.push(`MULTI×${maxMulti}`)

  // Compute the diff between the operator's chosen state and the current
  // catalog row. The approve handler consumes this to drive a single
  // `update_exercise` call.
  const computeUpdates = useCallback((): Record<string, unknown> => {
    if (!exercise || !edit) return {}
    const updates: Record<string, unknown> = {}
    for (const f of EDITABLE_FIELDS) {
      const current = (exercise as Record<string, unknown>)[f]
      const next = (edit as Record<string, unknown>)[f]
      const normCurrent = current === '' ? null : current
      const normNext = next === '' ? null : next
      if (!deepEqual(normCurrent, normNext)) {
        updates[f] = normNext
      }
    }
    return updates
  }, [exercise, edit])

  const approve = () => {
    if (!decidable || busy) return
    if (blockedProposals.length > 0) {
      const summary = blockedProposals
        .map((bp) => `  • ${bp.operation} ${bp.field_name} = ${JSON.stringify(bp.proposed_value)}`)
        .join('\n')
      const ok = window.confirm(
        `OVERRIDE the core-exercise lockout for "${group.exerciseName}"?\n\n` +
        `${blockedProposals.length} blocked proposal${blockedProposals.length === 1 ? '' : 's'}:\n` +
        `${summary}\n\n` +
        `This will permanently change a canonical exercise.`,
      )
      if (!ok) return
    }

    // Per-field disposition: did the operator KEEP Claude's combined intent
    // for this field, or OVERRIDE it? Drives apply vs reject for each
    // proposal touching that field.
    const dispositionByField = new Map<string, 'kept' | 'overrode'>()
    if (exercise && edit) {
      // Group proposals by field so multi-proposal-on-same-field is handled.
      const byField = new Map<string, ProposalRow[]>()
      for (const p of group.proposals) {
        const arr = byField.get(p.field_name) ?? []
        arr.push(p)
        byField.set(p.field_name, arr)
      }
      for (const [field, fieldProposals] of byField) {
        const intent = previewAfterAllProposals(exercise, fieldProposals)
        const claudeValue = (intent as Record<string, unknown>)[field]
        const userValue = (edit as Record<string, unknown>)[field]
        dispositionByField.set(field, deepEqual(claudeValue, userValue) ? 'kept' : 'overrode')
      }
    }

    // Build the update_exercise payload. Drop any field whose disposition is
    // 'kept' — admin_apply_correction_proposal will write it. Keep all
    // 'overrode' fields and any inline-only edits (name, gender, etc.).
    const allUpdates = computeUpdates()
    const updatesToSend: Record<string, unknown> = { ...allUpdates }
    for (const [field, disp] of dispositionByField) {
      if (disp === 'kept' && field in updatesToSend) {
        delete updatesToSend[field]
      }
    }

    // 1. Optimistic UI: remove every card-proposal pair immediately.
    setBusy(true)
    onSaveStart()
    onOptimisticRemove(group.proposals.map((p) => p.id))

    // 2. Background save. Errors per-proposal are collected; we report a
    //    single failure banner with the count so the operator knows what
    //    didn't land. update_exercise failure aborts the whole group
    //    (we don't want to mark proposals applied if the catalog never
    //    received the operator's overrides).
    const exerciseId = group.exerciseId
    const exerciseName = group.exerciseName
    const proposalsCopy = [...group.proposals]

    void (async () => {
      try {
        if (Object.keys(updatesToSend).length > 0) {
          const res = await adminApi('update_exercise', {
            exercise_id: exerciseId,
            updates: updatesToSend,
          }) as { error?: string; result?: { success?: boolean; error?: string } }
          if (res?.error || res?.result?.error || res?.result?.success === false) {
            throw new Error(res?.error || res?.result?.error || 'update_exercise failed')
          }
        }

        const failed: ProposalRow[] = []
        let appliedCount = 0
        let rejectedCount = 0
        for (const p of proposalsCopy) {
          const disp = dispositionByField.get(p.field_name) ?? 'kept'
          try {
            if (disp === 'overrode') {
              await adminApi('admin_reject_correction_proposal', {
                proposalId: p.id,
                reason: 'manual_override_via_inline_edit',
              })
              rejectedCount++
            } else {
              const res = await adminApi('admin_apply_correction_proposal', {
                proposalId: p.id,
              }) as { result?: { success?: boolean; error?: string } }
              if (!res?.result?.success) {
                throw new Error(res?.result?.error || 'admin_apply_correction_proposal failed')
              }
              appliedCount++
            }
          } catch (e) {
            failed.push(p)
            void e
          }
        }

        if (failed.length === 0) {
          onSaveSuccess({ applied: appliedCount, rejected: rejectedCount })
        } else {
          onSaveFailure({
            failedProposals: failed,
            exerciseName,
            action: 'approve',
            error: `${failed.length} of ${proposalsCopy.length} proposal updates failed`,
            successCounts: { applied: appliedCount, rejected: rejectedCount },
          })
        }
      } catch (e) {
        // update_exercise failed — none of the proposals are resolved.
        onSaveFailure({
          failedProposals: proposalsCopy,
          exerciseName,
          action: 'approve',
          error: e instanceof Error ? e.message : 'Apply failed',
        })
      }
    })()
  }

  const reject = () => {
    if (!decidable || busy) return
    const reason = window.prompt(
      `Reject ALL ${group.proposals.length} proposal${group.proposals.length === 1 ? '' : 's'} for "${group.exerciseName}"?\nOptional reason:`,
      'manual_admin_reject',
    )
    if (reason === null) return

    setBusy(true)
    onSaveStart()
    onOptimisticRemove(group.proposals.map((p) => p.id))

    const exerciseName = group.exerciseName
    const proposalsCopy = [...group.proposals]
    void (async () => {
      const failed: ProposalRow[] = []
      let rejectedCount = 0
      for (const p of proposalsCopy) {
        try {
          await adminApi('admin_reject_correction_proposal', { proposalId: p.id, reason })
          rejectedCount++
        } catch (e) {
          failed.push(p)
          void e
        }
      }
      if (failed.length === 0) {
        onSaveSuccess({ applied: 0, rejected: rejectedCount })
      } else {
        onSaveFailure({
          failedProposals: failed,
          exerciseName,
          action: 'reject',
          error: `${failed.length} of ${proposalsCopy.length} reject calls failed`,
          successCounts: { applied: 0, rejected: rejectedCount },
        })
      }
    })()
  }

  const videoFilename = exercise?.video_filename || null
  const videoUrl = videoFilename && !videoFailed ? `${R2_BASE}/${videoFilename}` : null

  // Pull the highest confidence + earliest proposed-at across the group for
  // the header summary. Each proposal still gets its own pill chip below.
  const maxConfidence = Math.max(...group.proposals.map((p) => p.confidence))
  const earliestProposedAt = group.proposals
    .map((p) => p.proposed_at)
    .sort()[0]

  // Combined evidence — keep distinct, comma-joined, max ~3 to avoid a wall
  // of text when an exercise has many proposals.
  const evidenceItems = Array.from(
    new Set(group.proposals.map((p) => p.evidence).filter((e) => !!e)),
  ).slice(0, 3)

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
              className="w-full md:h-full md:max-h-[28rem] object-cover bg-black"
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
                  href={`/exercises/${group.exerciseId}`}
                  className="text-base font-medium hover:underline block truncate"
                >
                  {group.exerciseName}
                </a>
              )}
              {/* Per-proposal pills — one chip per Claude diff */}
              <div className="flex flex-wrap items-center gap-1 mt-1.5">
                {group.proposals.map((p) => (
                  <span
                    key={p.id}
                    className="inline-flex items-center gap-1 text-[10px] uppercase tracking-wide bg-neutral-900 border border-neutral-700 rounded px-1.5 py-0.5"
                    title={p.evidence || ''}
                  >
                    <span className={operationBadgeClass(p.operation).replace('badge', 'inline-block px-1 rounded')}>
                      {p.operation}
                    </span>
                    <span className="text-neutral-300">{p.field_name}</span>
                  </span>
                ))}
                <span className="text-xs text-neutral-500 ml-1">
                  · {group.proposals.length} proposal{group.proposals.length === 1 ? '' : 's'} · max conf {maxConfidence.toFixed(2)}
                </span>
                <span className="text-xs text-neutral-500" title={earliestProposedAt}>
                  · {timeAgo(earliestProposedAt)}
                </span>
                <a
                  href={`/exercises/${group.exerciseId}`}
                  className="text-xs text-blue-400 hover:underline ml-1"
                  title="Open full exercise editor"
                >
                  full editor →
                </a>
              </div>
              {evidenceItems.length > 0 && (
                <div className="text-xs text-neutral-400 mt-2 italic leading-snug space-y-1">
                  {evidenceItems.map((ev, i) => (
                    <div key={i}>&ldquo;{ev}&rdquo;</div>
                  ))}
                </div>
              )}
            </div>

            {decidable && (
              <div className="flex flex-col gap-1.5 flex-shrink-0">
                <button
                  onClick={approve}
                  disabled={busy}
                  className={`btn btn-sm ${blockedProposals.length > 0 ? 'btn-warning' : 'btn-success'}`}
                  title={blockedProposals.length > 0 ? 'Override core-exercise lockout + save edits' : 'Save edits and apply all proposals'}
                >
                  {busy ? '…' : blockedProposals.length > 0 ? 'Override' : 'Approve'}
                </button>
                <button
                  onClick={reject}
                  disabled={busy}
                  className="btn btn-sm btn-danger"
                  title="Reject ALL proposals for this exercise"
                >
                  Reject all
                </button>
              </div>
            )}
          </div>

          {/* Gates + source report (union across proposals) */}
          <div className="flex flex-wrap items-center gap-1.5 text-xs mb-3">
            <span className="text-neutral-500">Gates:</span>
            {gates.length === 0 ? (
              <span className="text-neutral-600">none yet</span>
            ) : (
              gates.map((g) => (
                <span key={g} className="badge badge-info">{g}</span>
              ))
            )}
            {group.proposals.some((p) => p.rejected_reason) && (
              <span className="text-amber-400 ml-2">
                ⚠ {group.proposals.find((p) => p.rejected_reason)?.rejected_reason}
              </span>
            )}
          </div>

          {/* Editor — what the exercise WILL look like after Approve */}
          {edit && exercise ? (
            <InlineExerciseEditor
              edit={edit}
              setEdit={setEdit}
              touchedFields={touchedFields}
              before={exercise}
              suggestions={suggestions}
              proposals={group.proposals}
            />
          ) : (
            <div className="font-mono text-xs bg-neutral-950 rounded px-2 py-1.5 break-words text-neutral-400">
              {group.proposals.length} proposal{group.proposals.length === 1 ? '' : 's'} pending — full exercise data unavailable. Open the full editor to review.
            </div>
          )}

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
  touchedFields,
  before,
  suggestions,
  proposals,
}: {
  edit: EditableState
  setEdit: (updater: (s: EditableState | null) => EditableState | null) => void
  touchedFields: Set<string>
  before: ExerciseFull
  suggestions: Suggestions
  proposals: ProposalRow[]
}) {
  const beforePM = asMuscleList(before.primary_muscles)
  const beforeSM = asMuscleList(before.secondary_muscles)

  const fieldRing = (field: string): string =>
    touchedFields.has(field)
      ? 'ring-1 ring-emerald-500/40 bg-emerald-600/5 rounded'
      : ''

  // For muscle-array fields, find any 'remove' proposal targeting that field
  // so we can render the struck-through removed chips below the editor.
  const removedForField = (field: 'primary_muscles' | 'secondary_muscles'): string[] => {
    const removed: string[] = []
    for (const p of proposals) {
      if (p.field_name === field && p.operation === 'remove' && Array.isArray(p.proposed_value)) {
        for (const v of p.proposed_value as unknown[]) {
          if (typeof v === 'string') removed.push(v)
        }
      }
    }
    return Array.from(new Set(removed))
  }

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
        {/* Show what was removed (by ANY remove proposal targeting this
            field) so the operator sees the diff. */}
        {(() => {
          const removedHints = removedForField(field)
          const stillRemoved = removedHints.filter((m) => !arr.includes(m))
          if (stillRemoved.length === 0) return null
          return (
            <div className="mt-1 flex flex-wrap gap-1">
              {stillRemoved.map((m) => (
                <span
                  key={`rm-${m}`}
                  className="px-1.5 py-0.5 rounded text-[10px] bg-rose-600/15 text-rose-300 ring-1 ring-rose-500/40 line-through"
                >
                  {m}
                </span>
              ))}
            </div>
          )
        })()}
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
