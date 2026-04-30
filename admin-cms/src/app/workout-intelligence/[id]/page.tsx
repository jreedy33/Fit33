'use client'

import { useCallback, useEffect, useState } from 'react'
import { useRouter, useParams } from 'next/navigation'
import AdminShell from '@/components/AdminShell'
import { adminApi } from '@/lib/api'

// ─── helpers ────────────────────────────────────────────────────────

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
  if (d < 30) return `${d}d ago`
  return `${Math.floor(d / 30)}mo ago`
}

function severityBadgeClass(sev: string | null | undefined): string {
  switch (sev) {
    case 'block': return 'badge badge-danger'
    case 'warn': return 'badge badge-warning'
    case 'info':
    default: return 'badge badge-neutral'
  }
}

function statusBadgeClass(status: string | null | undefined): string {
  switch (status) {
    case 'complete': return 'badge badge-success'
    case 'pending':
    case 'analyzing': return 'badge badge-info'
    case 'failed': return 'badge badge-danger'
    default: return 'badge badge-neutral'
  }
}

function qualityBandBadgeClass(band: string | null | undefined): string {
  switch (band) {
    case 'high': return 'badge badge-success'
    case 'medium': return 'badge badge-warning'
    default: return 'badge badge-neutral'
  }
}

// ─── types ──────────────────────────────────────────────────────────

type PairingFinding = { type?: string; exercises?: string[]; code?: string; note?: string }
type PacingProfile = {
  avgRestPerExerciseSec?: number
  restBuckets?: Record<string, number>
  inferredIntent?: string
  intentMatchesGoal?: boolean
  perExercise?: Array<{ exerciseName: string; avgRestSec?: number; setCount?: number }>
}
type ProgressionEntry = { exerciseName?: string; kind?: string; delta?: string | number; triggerMet?: boolean; progressionSafe?: boolean }
type SwapEntry = { swapEventId?: string; swapClass?: string; swapIntent?: string; completedReplacement?: boolean; original?: string; replacement?: string }
type RedFlag = { code?: string; severity?: string; evidence?: string }
type CorrectionInline = { exerciseName?: string; field?: string; newValue?: unknown; confidence?: number; evidence?: string }
type ProgrammedVsExecuted = { weightDelta?: string | number; repsDelta?: string | number; setCountDelta?: string | number; summary?: string }
type VolumeBalance = Record<string, number>

type ReportJson = {
  splitFamily?: string
  primaryGoalInferred?: string
  orderingScore?: number
  pairingQuality?: number
  volumeBalance?: VolumeBalance
  pressDistribution?: Record<string, number>
  pairingFindings?: PairingFinding[]
  pacingProfile?: PacingProfile
  progressionEvidence?: ProgressionEntry[]
  swapInsights?: SwapEntry[]
  redFlags?: RedFlag[]
  exerciseCorrections?: CorrectionInline[]
  programmedVsExecuted?: ProgrammedVsExecuted
  recommenderSignals?: unknown
  summaryMd?: string
}

type CorrectionRow = {
  id: string
  exercise_id: string | null
  exercise_name: string | null
  field_name: string
  previous_value: unknown
  new_value: unknown
  evidence: string | null
  confidence: number | null
  applied_at: string
}

type WorkoutCtx = { id: string; name: string | null; date: string | null }
type UserCtx = { id: string; name?: string | null; email?: string | null; username?: string | null }

type FullReport = {
  report: {
    id: string
    user_id: string
    workout_id: string
    quality_score: number | null
    quality_band: string | null
    status: string
    is_suspicious: boolean
    is_lost_session: boolean
    enqueued_at: string
    analyzed_at: string | null
    summary_md: string | null
    error_message: string | null
    model_used: string | null
    prompt_hash: string | null
    report_jsonb: ReportJson | null
  }
  workout: WorkoutCtx | null
  user: UserCtx | null
  corrections: CorrectionRow[]
}

// ─── page ───────────────────────────────────────────────────────────

export default function WorkoutIntelDetailPage() {
  const router = useRouter()
  const params = useParams()
  const id = params.id as string

  const [data, setData] = useState<FullReport | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  const load = useCallback(async () => {
    setLoading(true)
    setError(null)
    try {
      const res = await adminApi('get_workout_intel_report', { id })
      setData(res as FullReport)
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Failed to load report')
    } finally {
      setLoading(false)
    }
  }, [id])

  useEffect(() => { void load() }, [load])

  if (loading) {
    return (
      <AdminShell>
        <div className="flex items-center justify-center" style={{ padding: 80 }}>
          <div className="spinner" style={{ width: 32, height: 32 }} />
        </div>
      </AdminShell>
    )
  }

  if (error || !data) {
    return (
      <AdminShell>
        <div className="p-6">
          <button className="btn btn-ghost text-sm mb-4" onClick={() => router.push('/workout-intelligence')}>← Back</button>
          <div className="card" style={{ color: 'var(--danger)' }}>{error || 'Report not found'}</div>
        </div>
      </AdminShell>
    )
  }

  const { report, workout, user, corrections } = data
  const j = report.report_jsonb || {}

  return (
    <AdminShell>
      <div className="p-6 max-w-7xl mx-auto space-y-6">
        {/* Top */}
        <div>
          <button className="btn btn-ghost text-sm mb-3" onClick={() => router.push('/workout-intelligence')}>← Back</button>
          <div className="card">
            <div className="flex flex-wrap items-start justify-between gap-3">
              <div>
                <h1 className="text-2xl font-bold" style={{ color: 'var(--text-primary)' }}>
                  {workout?.name || '(unnamed workout)'}
                </h1>
                <div className="text-sm mt-1" style={{ color: 'var(--text-secondary)' }}>
                  {user?.name || user?.email || user?.id}
                  {workout?.date && <> · {new Date(workout.date).toLocaleString()}</>}
                  <> · enqueued {timeAgo(report.enqueued_at)}</>
                  {report.analyzed_at && <> · analyzed {timeAgo(report.analyzed_at)}</>}
                </div>
              </div>
              <div className="flex items-center gap-2 flex-wrap">
                <span className="text-sm font-semibold" style={{ color: 'var(--text-primary)' }}>
                  Quality {report.quality_score ?? '—'}
                </span>
                {report.quality_band && <span className={qualityBandBadgeClass(report.quality_band)}>{report.quality_band}</span>}
                <span className={statusBadgeClass(report.status)}>{report.status}</span>
                {report.is_suspicious && <span className="badge badge-danger">suspicious</span>}
                {report.is_lost_session && <span className="badge badge-warning">lost session</span>}
              </div>
            </div>
            {report.error_message && (
              <div
                className="mt-3 p-3 rounded text-xs"
                style={{ background: 'rgba(239,68,68,0.08)', color: 'var(--danger)' }}
              >
                {report.error_message}
              </div>
            )}
            {report.summary_md && (
              <pre
                className="text-sm p-4 rounded-lg overflow-x-auto whitespace-pre-wrap mt-4"
                style={{ background: 'var(--bg-tertiary)', border: '1px solid var(--border)', color: 'var(--text-primary)' }}
              >
                {report.summary_md}
              </pre>
            )}
          </div>
        </div>

        {/* Top-line stats from json */}
        <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
          <KV label="Split" value={j.splitFamily || '—'} />
          <KV label="Primary goal" value={j.primaryGoalInferred || '—'} />
          <KV label="Ordering score" value={fmtScore(j.orderingScore)} />
          <KV label="Pairing quality" value={fmtScore(j.pairingQuality)} />
        </div>

        {/* Volume balance */}
        <Section title="Volume Balance">
          <VolumeBalanceBars data={j.volumeBalance} />
        </Section>

        {/* Press distribution (small) */}
        {j.pressDistribution && Object.keys(j.pressDistribution).length > 0 && (
          <Section title="Press Distribution">
            <VolumeBalanceBars data={j.pressDistribution} />
          </Section>
        )}

        {/* Pairing */}
        <Section title="Pairing Quality">
          <div className="text-sm mb-3" style={{ color: 'var(--text-secondary)' }}>
            Score: <span className="font-semibold" style={{ color: 'var(--text-primary)' }}>{fmtScore(j.pairingQuality)}</span>
          </div>
          {(j.pairingFindings || []).length === 0 ? (
            <Empty>No pairing findings.</Empty>
          ) : (
            <ul className="space-y-2">
              {(j.pairingFindings || []).map((p, i) => (
                <li key={i} className="text-sm p-3 rounded" style={{ background: 'var(--bg-tertiary)', border: '1px solid var(--border)' }}>
                  <div className="flex items-center gap-2 mb-1">
                    <span className={p.type === 'negative' ? 'badge badge-danger' : 'badge badge-success'}>
                      {p.type || 'pair'}
                    </span>
                    {p.code && <span className="badge badge-neutral">{p.code}</span>}
                  </div>
                  <div style={{ color: 'var(--text-primary)' }}>{(p.exercises || []).join(' + ') || '—'}</div>
                  {p.note && <div className="text-xs mt-1" style={{ color: 'var(--text-muted)' }}>{p.note}</div>}
                </li>
              ))}
            </ul>
          )}
        </Section>

        {/* Pacing */}
        <Section title="Pacing">
          <PacingBlock pacing={j.pacingProfile} primaryGoal={j.primaryGoalInferred} />
        </Section>

        {/* Progression Evidence */}
        <Section title="Progression Evidence">
          {(j.progressionEvidence || []).length === 0 ? (
            <Empty>No progression evidence captured.</Empty>
          ) : (
            <SimpleTable
              headers={['Exercise', 'Kind', 'Delta', 'Trigger met', 'Safe']}
              rows={(j.progressionEvidence || []).map(p => [
                p.exerciseName || '—',
                p.kind || '—',
                String(p.delta ?? '—'),
                p.triggerMet ? '✅' : '❌',
                p.progressionSafe ? '✅' : '❌',
              ])}
            />
          )}
        </Section>

        {/* Swap Insights */}
        <Section title="Swap Insights">
          {(j.swapInsights || []).length === 0 ? (
            <Empty>No swaps in this workout.</Empty>
          ) : (
            <SimpleTable
              headers={['Event', 'Class', 'Intent', 'Original → Replacement', 'Completed']}
              rows={(j.swapInsights || []).map(s => [
                s.swapEventId ? s.swapEventId.slice(0, 8) : '—',
                s.swapClass || '—',
                s.swapIntent || '—',
                `${s.original || '?'} → ${s.replacement || '?'}`,
                s.completedReplacement === true ? '✅' : s.completedReplacement === false ? '❌' : '—',
              ])}
            />
          )}
        </Section>

        {/* Red Flags */}
        <Section title="Red Flags">
          {(j.redFlags || []).length === 0 ? (
            <Empty>No red flags.</Empty>
          ) : (
            <div className="space-y-2">
              {(j.redFlags || []).map((f, i) => (
                <div
                  key={i}
                  className="p-3 rounded"
                  style={{
                    background: f.severity === 'block'
                      ? 'rgba(239,68,68,0.08)'
                      : f.severity === 'warn'
                        ? 'rgba(245,158,11,0.08)'
                        : 'var(--bg-tertiary)',
                    border: '1px solid var(--border)',
                  }}
                >
                  <div className="flex items-center gap-2 mb-1">
                    <span className={severityBadgeClass(f.severity)}>{f.severity || 'info'}</span>
                    {f.code && <span className="badge badge-neutral">{f.code}</span>}
                  </div>
                  <div className="text-sm" style={{ color: 'var(--text-primary)' }}>{f.evidence || '—'}</div>
                </div>
              ))}
            </div>
          )}
        </Section>

        {/* Programmed vs Executed */}
        <Section title="Programmed vs Executed">
          {!j.programmedVsExecuted ? (
            <Empty>Not analyzed (likely a custom-origin workout).</Empty>
          ) : (
            <>
              <div className="grid grid-cols-3 gap-3 mb-3">
                <KV label="Weight Δ" value={String(j.programmedVsExecuted.weightDelta ?? '—')} />
                <KV label="Reps Δ" value={String(j.programmedVsExecuted.repsDelta ?? '—')} />
                <KV label="Sets Δ" value={String(j.programmedVsExecuted.setCountDelta ?? '—')} />
              </div>
              {j.programmedVsExecuted.summary && (
                <p className="text-sm" style={{ color: 'var(--text-secondary)' }}>{j.programmedVsExecuted.summary}</p>
              )}
            </>
          )}
        </Section>

        {/* Exercise Corrections Applied (linked rows from the table) */}
        <Section title="Exercise Corrections Applied">
          {corrections.length === 0 ? (
            <Empty>No corrections applied from this report.</Empty>
          ) : (
            <SimpleTable
              headers={['When', 'Exercise', 'Field', 'Previous → New', 'Evidence', '']}
              rows={corrections.map(c => [
                timeAgo(c.applied_at),
                c.exercise_name || (c.exercise_id ? c.exercise_id.slice(0, 8) : '—'),
                c.field_name,
                `${formatJsonValue(c.previous_value)} → ${formatJsonValue(c.new_value)}`,
                truncate(c.evidence || '—', 80),
                c.exercise_id ? (
                  <a className="btn btn-ghost text-xs" href={`/exercises/${c.exercise_id}`}>View →</a>
                ) : '',
              ])}
            />
          )}
        </Section>

        {/* Recommender Signals (raw JSON) */}
        <Section title="Recommender Signals">
          <pre
            className="text-xs p-3 rounded-lg overflow-x-auto"
            style={{
              background: 'var(--bg-tertiary)', border: '1px solid var(--border)',
              color: 'var(--text-primary)', maxHeight: 400, overflowY: 'auto',
            }}
          >
            {JSON.stringify(j.recommenderSignals ?? {}, null, 2)}
          </pre>
        </Section>

        {/* Provenance */}
        <Section title="Provenance">
          <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
            <KV label="Model" value={report.model_used || '—'} />
            <KV label="Prompt hash" value={report.prompt_hash ? report.prompt_hash.slice(0, 12) + '…' : '—'} />
            <KV label="Workout id" value={(workout?.id || report.workout_id).slice(0, 8) + '…'} />
            <KV label="User id" value={(user?.id || report.user_id).slice(0, 8) + '…'} />
          </div>
        </Section>
      </div>
    </AdminShell>
  )
}

// ─── helpers / sub-components ───────────────────────────────────────

function fmtScore(n: number | undefined | null): string {
  if (n === null || n === undefined) return '—'
  return typeof n === 'number' ? (n <= 1 ? `${(n * 100).toFixed(0)}%` : n.toFixed(1)) : String(n)
}

function formatJsonValue(v: unknown): string {
  if (v === null || v === undefined) return '∅'
  if (typeof v === 'boolean') return v ? '✅' : '❌'
  if (Array.isArray(v)) return v.length ? v.map(x => String(x)).join(', ') : '[]'
  if (typeof v === 'object') {
    try { return JSON.stringify(v) } catch { return String(v) }
  }
  return String(v)
}

function truncate(s: string, n: number): string {
  if (s.length <= n) return s
  return s.slice(0, n) + '…'
}

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div className="card">
      <h2 className="text-base font-semibold mb-3" style={{ color: 'var(--text-primary)' }}>{title}</h2>
      {children}
    </div>
  )
}

function Empty({ children }: { children: React.ReactNode }) {
  return <p className="text-sm" style={{ color: 'var(--text-muted)' }}>{children}</p>
}

function KV({ label, value }: { label: string; value: string }) {
  return (
    <div className="card" style={{ padding: 12 }}>
      <div className="text-xs uppercase tracking-wide" style={{ color: 'var(--text-muted)' }}>{label}</div>
      <div className="text-sm font-semibold mt-1 truncate" style={{ color: 'var(--text-primary)' }}>{value}</div>
    </div>
  )
}

function VolumeBalanceBars({ data }: { data: VolumeBalance | undefined }) {
  if (!data || Object.keys(data).length === 0) return <Empty>No volume data.</Empty>
  const entries = Object.entries(data).sort((a, b) => Number(b[1]) - Number(a[1]))
  const max = Math.max(1, ...entries.map(([, v]) => Number(v) || 0))
  return (
    <div className="space-y-2">
      {entries.map(([key, raw]) => {
        const v = Number(raw) || 0
        const pct = (v / max) * 100
        return (
          <div key={key}>
            <div className="flex justify-between text-xs mb-1" style={{ color: 'var(--text-secondary)' }}>
              <span className="capitalize">{key}</span>
              <span>{v}</span>
            </div>
            <div className="h-2 rounded-full overflow-hidden" style={{ background: 'var(--bg-tertiary)' }}>
              <div className="h-full rounded-full" style={{ width: `${pct}%`, background: 'var(--info)' }} />
            </div>
          </div>
        )
      })}
    </div>
  )
}

function PacingBlock({ pacing, primaryGoal }: { pacing: PacingProfile | undefined; primaryGoal: string | undefined }) {
  if (!pacing) return <Empty>Pacing data not available.</Empty>
  return (
    <div className="space-y-3">
      <div className="flex flex-wrap items-center gap-2">
        {pacing.inferredIntent && (
          <span className="badge badge-info">intent: {pacing.inferredIntent}</span>
        )}
        {primaryGoal && (
          <span className="badge badge-neutral">goal: {primaryGoal}</span>
        )}
        {pacing.intentMatchesGoal !== undefined && (
          <span className={pacing.intentMatchesGoal ? 'badge badge-success' : 'badge badge-warning'}>
            {pacing.intentMatchesGoal ? '✅ matches goal' : '⚠️ mismatch'}
          </span>
        )}
        {pacing.avgRestPerExerciseSec !== undefined && (
          <span className="text-sm" style={{ color: 'var(--text-secondary)' }}>
            Avg rest: <span style={{ color: 'var(--text-primary)' }}>{pacing.avgRestPerExerciseSec}s</span>
          </span>
        )}
      </div>
      {pacing.restBuckets && Object.keys(pacing.restBuckets).length > 0 && (
        <div>
          <div className="text-xs uppercase tracking-wide mb-2" style={{ color: 'var(--text-muted)' }}>Rest buckets</div>
          <VolumeBalanceBars data={pacing.restBuckets} />
        </div>
      )}
      {pacing.perExercise && pacing.perExercise.length > 0 && (
        <SimpleTable
          headers={['Exercise', 'Avg rest', 'Sets']}
          rows={pacing.perExercise.map(p => [p.exerciseName, p.avgRestSec ? `${p.avgRestSec}s` : '—', String(p.setCount ?? '—')])}
        />
      )}
    </div>
  )
}

function SimpleTable({ headers, rows }: { headers: string[]; rows: Array<Array<React.ReactNode>> }) {
  return (
    <div className="overflow-x-auto">
      <table>
        <thead>
          <tr>{headers.map((h, i) => <th key={i}>{h}</th>)}</tr>
        </thead>
        <tbody>
          {rows.map((row, i) => (
            <tr key={i}>
              {row.map((c, j) => (
                <td key={j} className="text-sm align-top" style={{ color: 'var(--text-secondary)' }}>{c}</td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}
