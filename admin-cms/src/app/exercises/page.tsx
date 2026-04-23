'use client'

import { useEffect, useState, useCallback } from 'react'
import { useRouter } from 'next/navigation'
import AdminShell from '@/components/AdminShell'

const R2_BASE = 'https://pub-7838a3e2cbc24d59a6c4d2b2d6239bea.r2.dev'

type Exercise = {
  id: string
  name: string
  category: string
  equipment: string | null
  workout_type: string | null
  primary_muscles: string | string[] | null
  secondary_muscles: string | string[] | null
  video_filename: string | null
  video_code: string | null
  gender: string | null
  difficulty_level: number | null
  is_custom: boolean
  movement_pattern: string | null
  force_type: string | null
  equipment_category: string | null
  home_gym_friendly: boolean | null
  exercise_family: string | null
  is_compound: boolean | null
  duration_based: boolean | null
}

type Filters = {
  categories: string[]
  equipment: string[]
  workout_types: string[]
}

async function adminAction(action: string, params: Record<string, unknown> = {}) {
  const res = await fetch('/api/admin', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ action, ...params }),
  })
  return res.json()
}

function parseMuscles(val: string | string[] | null): string {
  if (!val) return '—'
  if (Array.isArray(val)) return val.join(', ')
  try {
    const parsed = JSON.parse(val)
    if (Array.isArray(parsed)) return parsed.join(', ')
  } catch { /* not JSON */ }
  return val
}

function difficultyBadge(level: number | null) {
  if (!level) return null
  const colors: Record<number, { bg: string; text: string; label: string }> = {
    1: { bg: '#22c55e22', text: '#22c55e', label: 'Beginner' },
    2: { bg: '#3b82f622', text: '#3b82f6', label: 'Intermediate' },
    3: { bg: '#f59e0b22', text: '#f59e0b', label: 'Advanced' },
    4: { bg: '#ef444422', text: '#ef4444', label: 'Expert' },
    5: { bg: '#a855f722', text: '#a855f7', label: 'Elite' },
  }
  const c = colors[level] || colors[2]
  return (
    <span className="badge" style={{ background: c.bg, color: c.text }}>
      {c.label}
    </span>
  )
}

function workoutTypeBadge(type: string | null) {
  if (!type) return null
  const t = type.toLowerCase()
  const colors: Record<string, { bg: string; text: string }> = {
    strength: { bg: '#ef444422', text: '#ef4444' },
    cardio: { bg: '#22c55e22', text: '#22c55e' },
    stretch: { bg: '#a855f722', text: '#a855f7' },
    warmup: { bg: '#f59e0b22', text: '#f59e0b' },
  }
  const c = colors[t] || { bg: '#3b82f622', text: '#3b82f6' }
  return (
    <span className="badge" style={{ background: c.bg, color: c.text }}>
      {type}
    </span>
  )
}

export default function ExercisesPage() {
  const router = useRouter()
  const [exercises, setExercises] = useState<Exercise[]>([])
  const [total, setTotal] = useState(0)
  const [filters, setFilters] = useState<Filters>({ categories: [], equipment: [], workout_types: [] })
  const [loading, setLoading] = useState(true)
  const [page, setPage] = useState(0)
  const [pageInput, setPageInput] = useState('')
  const [search, setSearch] = useState('')
  const [workoutType, setWorkoutType] = useState('all')
  const [category, setCategory] = useState('all')
  const [equipmentFilter, setEquipmentFilter] = useState('all')
  const limit = 100

  const loadFilters = useCallback(async () => {
    const data = await adminAction('get_exercise_filters')
    if (data.categories) setFilters(data)
  }, [])

  const loadExercises = useCallback(async () => {
    setLoading(true)
    const data = await adminAction('get_exercises', {
      workout_type: workoutType,
      category,
      equipment: equipmentFilter,
      search,
      page,
      limit,
    })
    setExercises(data.exercises || [])
    setTotal(data.total || 0)
    setLoading(false)
  }, [workoutType, category, equipmentFilter, search, page])

  useEffect(() => { loadFilters() }, [loadFilters])
  useEffect(() => { loadExercises() }, [loadExercises])

  const totalPages = Math.ceil(total / limit)

  // Jump to a specific page. Accepts "6" or "6/69" (the second part is ignored
  // so users can retype what they see in the label). Clamps to [1, totalPages].
  const handleGotoPage = () => {
    const raw = pageInput.trim().split('/')[0]
    const n = parseInt(raw, 10)
    if (!Number.isFinite(n) || n < 1) return
    const clamped = Math.min(Math.max(n, 1), Math.max(totalPages, 1))
    setPage(clamped - 1)
    setPageInput('')
  }

  return (
    <AdminShell>
      <div style={{ padding: 32, maxWidth: 1400 }}>
        <div className="flex items-center justify-between" style={{ marginBottom: 24 }}>
          <div>
            <h1 style={{ fontSize: 24, fontWeight: 700 }}>Exercise Library</h1>
            <p style={{ color: 'var(--text-secondary)', fontSize: 14, marginTop: 4 }}>
              {total.toLocaleString()} exercises in database
            </p>
          </div>
        </div>

        {/* Filters */}
        <div className="card" style={{ marginBottom: 20, display: 'flex', gap: 12, flexWrap: 'wrap', alignItems: 'center' }}>
          <div style={{ flex: '1 1 260px' }}>
            <input
              type="search"
              placeholder="Search exercises..."
              value={search}
              onChange={(e) => { setSearch(e.target.value); setPage(0) }}
              style={{ width: '100%' }}
            />
          </div>

          <div style={{ minWidth: 160 }}>
            <select value={workoutType} onChange={(e) => { setWorkoutType(e.target.value); setPage(0) }}>
              <option value="all">All Types</option>
              {filters.workout_types.map(t => (
                <option key={t} value={t}>{t}</option>
              ))}
            </select>
          </div>

          <div style={{ minWidth: 160 }}>
            <select value={category} onChange={(e) => { setCategory(e.target.value); setPage(0) }}>
              <option value="all">All Categories</option>
              {filters.categories.map(c => (
                <option key={c} value={c}>{c}</option>
              ))}
            </select>
          </div>

          <div style={{ minWidth: 160 }}>
            <select value={equipmentFilter} onChange={(e) => { setEquipmentFilter(e.target.value); setPage(0) }}>
              <option value="all">All Equipment</option>
              {filters.equipment.map(e => (
                <option key={e} value={e}>{e}</option>
              ))}
            </select>
          </div>
        </div>

        {/* Table */}
        {loading ? (
          <div className="flex items-center justify-center" style={{ padding: 60 }}>
            <div className="spinner" />
          </div>
        ) : exercises.length === 0 ? (
          <div className="card" style={{ textAlign: 'center', padding: 60, color: 'var(--text-muted)' }}>
            No exercises found matching your filters.
          </div>
        ) : (
          <>
            <div className="card" style={{ padding: 0, overflow: 'hidden' }}>
              <table>
                <thead>
                  <tr>
                    <th style={{ width: 60 }}>Video</th>
                    <th>Name</th>
                    <th>Type</th>
                    <th>Category</th>
                    <th>Equipment</th>
                    <th>Primary Muscles</th>
                    <th>Difficulty</th>
                    <th>Gender</th>
                  </tr>
                </thead>
                <tbody>
                  {exercises.map((ex) => (
                    <tr
                      key={ex.id}
                      onClick={() => {
                        sessionStorage.setItem('exerciseIds', JSON.stringify(exercises.map(e => e.id)))
                        router.push(`/exercises/${ex.id}`)
                      }}
                      style={{ cursor: 'pointer' }}
                    >
                      <td>
                        {ex.video_filename ? (
                          <div style={{
                            width: 44, height: 44, borderRadius: 8, overflow: 'hidden',
                            background: 'var(--bg-tertiary)', position: 'relative',
                          }}>
                            <video
                              src={`${R2_BASE}/${ex.video_filename}`}
                              muted
                              autoPlay
                              loop
                              playsInline
                              style={{ width: '100%', height: '100%', objectFit: 'cover' }}
                            />
                          </div>
                        ) : (
                          <div style={{
                            width: 44, height: 44, borderRadius: 8,
                            background: 'var(--bg-tertiary)',
                            display: 'flex', alignItems: 'center', justifyContent: 'center',
                            color: 'var(--text-muted)', fontSize: 18,
                          }}>
                            🏋️
                          </div>
                        )}
                      </td>
                      <td style={{ fontWeight: 600 }}>{ex.name}</td>
                      <td>{workoutTypeBadge(ex.workout_type)}</td>
                      <td style={{ color: 'var(--text-secondary)' }}>{ex.category}</td>
                      <td style={{ color: 'var(--text-secondary)' }}>{ex.equipment || '—'}</td>
                      <td style={{ color: 'var(--text-secondary)', maxWidth: 200, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                        {parseMuscles(ex.primary_muscles)}
                      </td>
                      <td>{difficultyBadge(ex.difficulty_level)}</td>
                      <td style={{ color: 'var(--text-secondary)' }}>{ex.gender || '—'}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>

            {/* Pagination */}
            {totalPages > 1 && (
              <div className="flex items-center justify-between" style={{ marginTop: 16, padding: '0 4px' }}>
                <span style={{ fontSize: 13, color: 'var(--text-muted)' }}>
                  Page {page + 1} of {totalPages} ({total.toLocaleString()} exercises)
                </span>
                <div className="flex gap-2" style={{ alignItems: 'center' }}>
                  <div className="flex gap-1" style={{ alignItems: 'center', marginRight: 4 }}>
                    <label htmlFor="goto-page" style={{ fontSize: 13, color: 'var(--text-muted)' }}>
                      Go to
                    </label>
                    <input
                      id="goto-page"
                      type="text"
                      inputMode="numeric"
                      placeholder={`1–${totalPages}`}
                      value={pageInput}
                      onChange={(e) => setPageInput(e.target.value)}
                      onKeyDown={(e) => {
                        if (e.key === 'Enter') {
                          e.preventDefault()
                          handleGotoPage()
                        }
                      }}
                      aria-label={`Jump to page, 1 through ${totalPages}`}
                      style={{
                        width: 84,
                        fontSize: 13,
                        padding: '6px 8px',
                        borderRadius: 6,
                        border: '1px solid var(--border)',
                        background: 'var(--input-bg, transparent)',
                        color: 'var(--text-primary)',
                      }}
                    />
                    <button
                      className="btn btn-ghost"
                      disabled={!pageInput.trim()}
                      onClick={handleGotoPage}
                      style={{ fontSize: 13 }}
                    >
                      Go
                    </button>
                  </div>
                  <button
                    className="btn btn-ghost"
                    disabled={page === 0}
                    onClick={() => setPage(p => p - 1)}
                    style={{ fontSize: 13 }}
                  >
                    ← Previous
                  </button>
                  <button
                    className="btn btn-ghost"
                    disabled={page >= totalPages - 1}
                    onClick={() => setPage(p => p + 1)}
                    style={{ fontSize: 13 }}
                  >
                    Next →
                  </button>
                </div>
              </div>
            )}
          </>
        )}
      </div>
    </AdminShell>
  )
}
