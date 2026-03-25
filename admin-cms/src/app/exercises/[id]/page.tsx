'use client'

import { useEffect, useState, useCallback, useRef } from 'react'
import { useRouter, useParams } from 'next/navigation'
import AdminShell from '@/components/AdminShell'

const R2_BASE = 'https://pub-7838a3e2cbc24d59a6c4d2b2d6239bea.r2.dev'

type Exercise = Record<string, unknown>
type Suggestions = Record<string, string[]>

async function adminAction(action: string, params: Record<string, unknown> = {}) {
  const res = await fetch('/api/admin', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ action, ...params }),
  })
  return res.json()
}

function parseMuscleDisplay(val: unknown): string {
  if (!val) return ''
  if (Array.isArray(val)) return val.join(', ')
  if (typeof val === 'string') {
    try {
      const parsed = JSON.parse(val)
      if (Array.isArray(parsed)) return parsed.join(', ')
    } catch { /* not JSON */ }
    return val
  }
  return String(val)
}

const AUTOCOMPLETE_MAP: Record<string, string> = {
  primary_muscles: 'muscles',
  secondary_muscles: 'muscles',
  category: 'categories',
  equipment: 'equipment',
  equipment_category: 'equipment_categories',
  movement_pattern: 'movement_patterns',
  force_type: 'force_types',
  movement_type: 'movement_types',
  laterality: 'lateralities',
  plane_of_motion: 'planes_of_motion',
  body_position: 'body_positions',
  bench_angle: 'bench_angles',
  grip_type: 'grip_types',
  grip_width: 'grip_widths',
  exercise_family: 'exercise_families',
  placement_in_workout: 'placements',
  base_exercise_name: 'exercise_families',
}

const ARRAY_FIELDS = new Set(['primary_muscles', 'secondary_muscles'])

type FieldDef = {
  key: string
  label: string
  type: 'text' | 'textarea' | 'number' | 'boolean' | 'select'
  options?: string[]
  section: string
}

const FIELD_DEFS: FieldDef[] = [
  { key: 'name', label: 'Name', type: 'text', section: 'Basic Info' },
  { key: 'category', label: 'Category', type: 'text', section: 'Basic Info' },
  { key: 'workout_type', label: 'Workout Type', type: 'select', options: ['Strength', 'Cardio', 'Stretch', 'Warmup', 'Plyometrics', 'Olympic Weightlifting', 'Strongman', 'Powerlifting'], section: 'Basic Info' },
  { key: 'equipment', label: 'Equipment', type: 'text', section: 'Basic Info' },
  { key: 'equipment_category', label: 'Equipment Category', type: 'text', section: 'Basic Info' },
  { key: 'gender', label: 'Gender', type: 'select', options: ['Male', 'Female'], section: 'Basic Info' },
  { key: 'difficulty_level', label: 'Difficulty Level (1-5)', type: 'number', section: 'Basic Info' },
  { key: 'complexity_score', label: 'Complexity Score', type: 'number', section: 'Basic Info' },

  { key: 'primary_muscles', label: 'Primary Muscles', type: 'text', section: 'Muscles' },
  { key: 'secondary_muscles', label: 'Secondary Muscles', type: 'text', section: 'Muscles' },
  { key: 'muscles_worked_count', label: 'Muscles Worked Count', type: 'number', section: 'Muscles' },

  { key: 'description', label: 'Description', type: 'textarea', section: 'Description' },
  { key: 'instructions', label: 'Instructions', type: 'textarea', section: 'Description' },
  { key: 'steps_to_perform', label: 'Steps to Perform', type: 'textarea', section: 'Description' },

  { key: 'movement_pattern', label: 'Movement Pattern', type: 'text', section: 'Movement' },
  { key: 'force_type', label: 'Force Type', type: 'text', section: 'Movement' },
  { key: 'movement_type', label: 'Movement Type', type: 'text', section: 'Movement' },
  { key: 'laterality', label: 'Laterality', type: 'text', section: 'Movement' },
  { key: 'plane_of_motion', label: 'Plane of Motion', type: 'text', section: 'Movement' },
  { key: 'is_compound', label: 'Compound Movement', type: 'boolean', section: 'Movement' },
  { key: 'body_position', label: 'Body Position', type: 'text', section: 'Movement' },
  { key: 'bench_angle', label: 'Bench Angle', type: 'text', section: 'Movement' },
  { key: 'grip_type', label: 'Grip Type', type: 'text', section: 'Movement' },
  { key: 'grip_width', label: 'Grip Width', type: 'text', section: 'Movement' },

  { key: 'strength_rating', label: 'Strength Rating', type: 'number', section: 'Ratings' },
  { key: 'hypertrophy_rating', label: 'Hypertrophy Rating', type: 'number', section: 'Ratings' },
  { key: 'power_rating', label: 'Power Rating', type: 'number', section: 'Ratings' },
  { key: 'endurance_rating', label: 'Endurance Rating', type: 'number', section: 'Ratings' },
  { key: 'fat_loss_rating', label: 'Fat Loss Rating', type: 'number', section: 'Ratings' },
  { key: 'general_fitness_rating', label: 'General Fitness Rating', type: 'number', section: 'Ratings' },
  { key: 'popularity_score', label: 'Popularity Score', type: 'number', section: 'Ratings' },
  { key: 'practicality_score', label: 'Practicality Score', type: 'number', section: 'Ratings' },
  { key: 'fatigability', label: 'Fatigability', type: 'number', section: 'Ratings' },

  { key: 'optimal_rep_range_min', label: 'Optimal Rep Range Min', type: 'number', section: 'Programming' },
  { key: 'optimal_rep_range_max', label: 'Optimal Rep Range Max', type: 'number', section: 'Programming' },
  { key: 'recommended_sets', label: 'Recommended Sets', type: 'number', section: 'Programming' },
  { key: 'rest_seconds', label: 'Rest Seconds', type: 'number', section: 'Programming' },
  { key: 'placement_in_workout', label: 'Placement in Workout', type: 'text', section: 'Programming' },
  { key: 'duration_based', label: 'Duration Based', type: 'boolean', section: 'Programming' },
  { key: 'supersetable', label: 'Supersetable', type: 'boolean', section: 'Programming' },
  { key: 'home_gym_friendly', label: 'Home Gym Friendly', type: 'boolean', section: 'Programming' },

  { key: 'exercise_family', label: 'Exercise Family', type: 'text', section: 'Family' },
  { key: 'base_exercise_name', label: 'Base Exercise Name', type: 'text', section: 'Family' },
  { key: 'complementary_families', label: 'Complementary Families', type: 'text', section: 'Family' },
  { key: 'is_equipment_primary', label: 'Equipment Primary Variant', type: 'boolean', section: 'Family' },
  { key: 'priority_build_muscle', label: 'Priority: Build Muscle', type: 'number', section: 'Family' },
  { key: 'priority_get_lean', label: 'Priority: Get Lean', type: 'number', section: 'Family' },
  { key: 'priority_home', label: 'Priority: Home', type: 'number', section: 'Family' },
  { key: 'priority_gym', label: 'Priority: Gym', type: 'number', section: 'Family' },

  { key: 'video_filename', label: 'Video Filename', type: 'text', section: 'Video' },
  { key: 'video_code', label: 'Video Code', type: 'text', section: 'Video' },
]

const SECTIONS = ['Basic Info', 'Muscles', 'Description', 'Movement', 'Ratings', 'Programming', 'Family', 'Video']

export default function ExerciseDetailPage() {
  const router = useRouter()
  const params = useParams()
  const exerciseId = params.id as string

  const [exercise, setExercise] = useState<Exercise | null>(null)
  const [editedFields, setEditedFields] = useState<Record<string, unknown>>({})
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [deleting, setDeleting] = useState(false)
  const [showDeleteConfirm, setShowDeleteConfirm] = useState(false)
  const [saveMsg, setSaveMsg] = useState<{ type: 'success' | 'error'; text: string } | null>(null)
  const [activeSection, setActiveSection] = useState('Basic Info')
  const [suggestions, setSuggestions] = useState<Suggestions>({})

  const loadExercise = useCallback(async () => {
    setLoading(true)
    const data = await adminAction('get_exercise', { exercise_id: exerciseId })
    if (data.exercise) {
      setExercise(data.exercise)
      setEditedFields({})
    }
    setLoading(false)
  }, [exerciseId])

  const loadSuggestions = useCallback(async () => {
    const data = await adminAction('get_exercise_suggestions')
    if (!data.error) setSuggestions(data)
  }, [])

  useEffect(() => { loadExercise() }, [loadExercise])
  useEffect(() => { loadSuggestions() }, [loadSuggestions])

  const getValue = (key: string): unknown => {
    if (key in editedFields) return editedFields[key]
    return exercise?.[key] ?? null
  }

  const getDisplayValue = (key: string): string => {
    const val = getValue(key)
    if (val === null || val === undefined) return ''
    if (ARRAY_FIELDS.has(key)) return parseMuscleDisplay(val)
    return String(val)
  }

  const setField = (key: string, value: unknown) => {
    setEditedFields(prev => ({ ...prev, [key]: value }))
    setSaveMsg(null)
  }

  const hasChanges = Object.keys(editedFields).length > 0

  const handleSave = async () => {
    if (!hasChanges) return
    setSaving(true)
    setSaveMsg(null)

    const updates: Record<string, unknown> = {}
    for (const [key, value] of Object.entries(editedFields)) {
      const def = FIELD_DEFS.find(f => f.key === key)
      if (def?.type === 'number') {
        updates[key] = value === '' || value === null ? null : Number(value)
      } else if (def?.type === 'boolean') {
        updates[key] = Boolean(value)
      } else if (ARRAY_FIELDS.has(key)) {
        if (typeof value === 'string') {
          const arr = value.split(',').map(s => s.trim()).filter(Boolean)
          updates[key] = arr.length > 0 ? arr : null
        } else {
          updates[key] = value
        }
      } else {
        updates[key] = value === '' ? null : value
      }
    }

    const result = await adminAction('update_exercise', { exercise_id: exerciseId, updates })

    if (result.error) {
      setSaveMsg({ type: 'error', text: result.error })
    } else {
      setExercise(result.exercise)
      setEditedFields({})
      setSaveMsg({ type: 'success', text: 'Exercise updated successfully' })
    }
    setSaving(false)
  }

  const handleDelete = async () => {
    setDeleting(true)
    const result = await adminAction('delete_exercise', { exercise_id: exerciseId })
    if (result.error) {
      setSaveMsg({ type: 'error', text: result.error })
      setDeleting(false)
      setShowDeleteConfirm(false)
    } else {
      router.push('/exercises')
    }
  }

  const videoFilename = getDisplayValue('video_filename')
  const videoUrl = videoFilename ? `${R2_BASE}/${encodeURIComponent(videoFilename)}` : null

  if (loading) {
    return (
      <AdminShell>
        <div className="flex items-center justify-center" style={{ padding: 80 }}>
          <div className="spinner" />
        </div>
      </AdminShell>
    )
  }

  if (!exercise) {
    return (
      <AdminShell>
        <div style={{ padding: 32 }}>
          <p style={{ color: 'var(--text-muted)' }}>Exercise not found.</p>
          <button className="btn btn-ghost" style={{ marginTop: 12 }} onClick={() => router.push('/exercises')}>
            ← Back to Exercises
          </button>
        </div>
      </AdminShell>
    )
  }

  return (
    <AdminShell>
      <div style={{ padding: 32, maxWidth: 1200, paddingBottom: hasChanges ? 80 : 32 }}>
        {/* Header */}
        <div className="flex items-center gap-3" style={{ marginBottom: 24 }}>
          <button
            className="btn btn-ghost"
            onClick={() => router.push('/exercises')}
            style={{ fontSize: 13, padding: '6px 12px' }}
          >
            ← Back
          </button>
          <div style={{ flex: 1 }}>
            <h1 style={{ fontSize: 22, fontWeight: 700 }}>{exercise.name as string}</h1>
            <div className="flex items-center gap-2" style={{ marginTop: 4 }}>
              <span className="badge" style={{ background: '#3b82f622', color: '#3b82f6' }}>
                {exercise.category as string}
              </span>
              {exercise.workout_type ? (
                <span className="badge" style={{ background: '#22c55e22', color: '#22c55e' }}>
                  {exercise.workout_type as string}
                </span>
              ) : null}
              {exercise.gender ? (
                <span className="badge badge-neutral">
                  {exercise.gender as string}
                </span>
              ) : null}
            </div>
          </div>
          <div className="flex items-center gap-2">
            {saveMsg && (
              <span style={{
                fontSize: 13,
                color: saveMsg.type === 'success' ? 'var(--success)' : 'var(--danger)',
                marginRight: 8,
              }}>
                {saveMsg.text}
              </span>
            )}
            <button
              className="btn btn-danger"
              onClick={() => setShowDeleteConfirm(true)}
              style={{ fontSize: 13 }}
            >
              Delete Exercise
            </button>
            <button
              className="btn btn-primary"
              disabled={!hasChanges || saving}
              onClick={handleSave}
              style={{ fontSize: 14 }}
            >
              {saving ? 'Saving...' : 'Save Changes'}
            </button>
          </div>
        </div>

        {/* Video + Quick Info */}
        <div style={{ display: 'grid', gridTemplateColumns: videoUrl ? '340px 1fr' : '1fr', gap: 20, marginBottom: 24 }}>
          {videoUrl && (
            <div className="card" style={{ padding: 0, overflow: 'hidden' }}>
              <video
                key={videoUrl}
                src={videoUrl}
                autoPlay
                loop
                muted
                playsInline
                style={{
                  width: '100%',
                  aspectRatio: '9/16',
                  objectFit: 'cover',
                  background: '#000',
                  borderRadius: 12,
                }}
              />
            </div>
          )}

          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(180px, 1fr))', gap: 12, alignContent: 'start' }}>
            <InfoCard label="Equipment" value={exercise.equipment as string} />
            <InfoCard label="Difficulty" value={exercise.difficulty_level ? `Level ${exercise.difficulty_level}` : null} />
            <InfoCard label="Movement" value={exercise.movement_pattern as string} />
            <InfoCard label="Force" value={exercise.force_type as string} />
            <InfoCard label="Family" value={exercise.exercise_family as string} />
            <InfoCard label="Compound" value={exercise.is_compound ? 'Yes' : 'No'} />
            <InfoCard label="Home Friendly" value={exercise.home_gym_friendly ? 'Yes' : 'No'} />
            <InfoCard label="Duration Based" value={exercise.duration_based ? 'Yes' : 'No'} />
            <InfoCard label="Rep Range" value={
              exercise.optimal_rep_range_min && exercise.optimal_rep_range_max
                ? `${exercise.optimal_rep_range_min}–${exercise.optimal_rep_range_max}`
                : null
            } />
            <InfoCard label="Sets" value={exercise.recommended_sets ? `${exercise.recommended_sets}` : null} />
            <InfoCard label="Rest" value={exercise.rest_seconds ? `${exercise.rest_seconds}s` : null} />
            <InfoCard label="Primary Muscles" value={parseMuscleDisplay(exercise.primary_muscles)} />
          </div>
        </div>

        {/* Section Tabs */}
        <div className="flex" style={{ borderBottom: '1px solid var(--border)', marginBottom: 20, gap: 0, overflowX: 'auto' }}>
          {SECTIONS.map(s => (
            <button
              key={s}
              className={`tab ${activeSection === s ? 'tab-active' : ''}`}
              onClick={() => setActiveSection(s)}
              style={{ whiteSpace: 'nowrap' }}
            >
              {s}
            </button>
          ))}
        </div>

        {/* Fields */}
        <div className="card">
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(320px, 1fr))', gap: 16 }}>
            {FIELD_DEFS.filter(f => f.section === activeSection).map(field => (
              <FieldEditor
                key={field.key}
                field={field}
                value={getValue(field.key)}
                displayValue={getDisplayValue(field.key)}
                onChange={(val) => setField(field.key, val)}
                isEdited={field.key in editedFields}
                suggestions={suggestions}
              />
            ))}
          </div>
        </div>

        {/* Unsaved Changes Bar */}
        {hasChanges && (
          <div style={{
            position: 'fixed', bottom: 0, left: 0, right: 0,
            background: 'var(--bg-secondary)', borderTop: '1px solid var(--border)',
            padding: '12px 32px',
            display: 'flex', alignItems: 'center', justifyContent: 'flex-end', gap: 12,
            zIndex: 50,
          }}>
            <span style={{ fontSize: 13, color: 'var(--warning)' }}>
              {Object.keys(editedFields).length} unsaved change{Object.keys(editedFields).length > 1 ? 's' : ''}
            </span>
            <button className="btn btn-ghost" onClick={() => { setEditedFields({}); setSaveMsg(null) }} style={{ fontSize: 13 }}>
              Discard
            </button>
            <button className="btn btn-primary" onClick={handleSave} disabled={saving} style={{ fontSize: 13 }}>
              {saving ? 'Saving...' : 'Save Changes'}
            </button>
          </div>
        )}

        {/* Delete Confirmation Modal */}
        {showDeleteConfirm && (
          <div
            style={{
              position: 'fixed', inset: 0, background: 'rgba(0,0,0,0.6)',
              display: 'flex', alignItems: 'center', justifyContent: 'center', zIndex: 100,
            }}
            onClick={() => !deleting && setShowDeleteConfirm(false)}
          >
            <div
              className="card"
              style={{ maxWidth: 440, width: '90%' }}
              onClick={(e) => e.stopPropagation()}
            >
              <h3 style={{ fontSize: 18, fontWeight: 700, marginBottom: 8 }}>Delete Exercise</h3>
              <p style={{ color: 'var(--text-secondary)', fontSize: 14, marginBottom: 8 }}>
                Are you sure you want to permanently delete <strong>{exercise.name as string}</strong>?
              </p>
              <p style={{ color: 'var(--danger)', fontSize: 13, marginBottom: 20 }}>
                This removes it from the database and the app. This action cannot be undone.
              </p>
              <div className="flex gap-2" style={{ justifyContent: 'flex-end' }}>
                <button
                  className="btn btn-ghost"
                  onClick={() => setShowDeleteConfirm(false)}
                  disabled={deleting}
                  style={{ fontSize: 13 }}
                >
                  Cancel
                </button>
                <button
                  className="btn btn-danger"
                  onClick={handleDelete}
                  disabled={deleting}
                  style={{ fontSize: 13 }}
                >
                  {deleting ? 'Deleting...' : 'Yes, Delete'}
                </button>
              </div>
            </div>
          </div>
        )}
      </div>
    </AdminShell>
  )
}

function InfoCard({ label, value }: { label: string; value: string | null | undefined }) {
  return (
    <div style={{
      background: 'var(--bg-tertiary)', borderRadius: 10, padding: '12px 14px',
      border: '1px solid var(--border)',
    }}>
      <div style={{ fontSize: 11, color: 'var(--text-muted)', textTransform: 'uppercase', letterSpacing: '0.05em', marginBottom: 4 }}>
        {label}
      </div>
      <div style={{ fontSize: 14, fontWeight: 600, color: value ? 'var(--text-primary)' : 'var(--text-muted)' }}>
        {value || '—'}
      </div>
    </div>
  )
}

function AutocompleteInput({ value, onChange, allSuggestions, isArrayField, placeholder }: {
  value: string
  onChange: (val: string) => void
  allSuggestions: string[]
  isArrayField: boolean
  placeholder?: string
}) {
  const [focused, setFocused] = useState(false)
  const [filtered, setFiltered] = useState<string[]>([])
  const [selectedIdx, setSelectedIdx] = useState(-1)
  const wrapperRef = useRef<HTMLDivElement>(null)
  const inputRef = useRef<HTMLInputElement>(null)

  const getActiveToken = (): { token: string; before: string; after: string } => {
    if (!isArrayField) return { token: value, before: '', after: '' }
    const cursorPos = inputRef.current?.selectionStart ?? value.length
    const parts = value.split(',')
    let charCount = 0
    for (let i = 0; i < parts.length; i++) {
      const partLen = parts[i].length + (i < parts.length - 1 ? 1 : 0)
      if (charCount + partLen >= cursorPos || i === parts.length - 1) {
        const before = parts.slice(0, i).join(',') + (i > 0 ? ', ' : '')
        const after = (i < parts.length - 1 ? ', ' : '') + parts.slice(i + 1).join(',')
        return { token: parts[i].trim(), before, after }
      }
      charCount += partLen
    }
    return { token: value, before: '', after: '' }
  }

  const updateFiltered = useCallback(() => {
    if (!allSuggestions.length) { setFiltered([]); return }
    const { token } = getActiveToken()
    if (!token) { setFiltered([]); return }
    const lower = token.toLowerCase()
    const matches = allSuggestions
      .filter(s => s.toLowerCase().includes(lower) && s.toLowerCase() !== lower)
      .slice(0, 8)
    setFiltered(matches)
    setSelectedIdx(-1)
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [value, allSuggestions])

  useEffect(() => {
    if (focused) updateFiltered()
  }, [focused, updateFiltered])

  const applySuggestion = (suggestion: string) => {
    if (isArrayField) {
      const { before, after } = getActiveToken()
      const newVal = `${before}${suggestion}${after}`.replace(/,\s*,/g, ',').replace(/^,\s*/, '').replace(/,\s*$/, '')
      onChange(newVal)
    } else {
      onChange(suggestion)
    }
    setFiltered([])
    setFocused(false)
  }

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (!filtered.length) return
    if (e.key === 'ArrowDown') {
      e.preventDefault()
      setSelectedIdx(i => Math.min(i + 1, filtered.length - 1))
    } else if (e.key === 'ArrowUp') {
      e.preventDefault()
      setSelectedIdx(i => Math.max(i - 1, 0))
    } else if (e.key === 'Enter' && selectedIdx >= 0) {
      e.preventDefault()
      applySuggestion(filtered[selectedIdx])
    } else if (e.key === 'Escape') {
      setFiltered([])
    }
  }

  useEffect(() => {
    const handleClickOutside = (e: MouseEvent) => {
      if (wrapperRef.current && !wrapperRef.current.contains(e.target as Node)) {
        setFocused(false)
        setFiltered([])
      }
    }
    document.addEventListener('mousedown', handleClickOutside)
    return () => document.removeEventListener('mousedown', handleClickOutside)
  }, [])

  return (
    <div ref={wrapperRef} style={{ position: 'relative' }}>
      <input
        ref={inputRef}
        type="text"
        value={value}
        placeholder={placeholder}
        onChange={(e) => { onChange(e.target.value); if (focused) updateFiltered() }}
        onFocus={() => { setFocused(true); updateFiltered() }}
        onKeyDown={handleKeyDown}
      />
      {focused && filtered.length > 0 && (
        <div style={{
          position: 'absolute', top: '100%', left: 0, right: 0, zIndex: 60,
          background: 'var(--bg-secondary)', border: '1px solid var(--border)',
          borderRadius: 8, marginTop: 4, overflow: 'hidden',
          boxShadow: '0 8px 24px rgba(0,0,0,0.4)',
          maxHeight: 240, overflowY: 'auto',
        }}>
          {filtered.map((s, i) => {
            const { token } = getActiveToken()
            const matchIdx = s.toLowerCase().indexOf(token.toLowerCase())
            return (
              <button
                key={s}
                onMouseDown={(e) => { e.preventDefault(); applySuggestion(s) }}
                style={{
                  display: 'block', width: '100%', textAlign: 'left',
                  padding: '8px 12px', fontSize: 13, cursor: 'pointer',
                  background: i === selectedIdx ? 'var(--bg-hover)' : 'transparent',
                  color: 'var(--text-primary)', border: 'none',
                  borderBottom: i < filtered.length - 1 ? '1px solid var(--border)' : 'none',
                }}
              >
                {matchIdx >= 0 ? (
                  <>
                    {s.slice(0, matchIdx)}
                    <strong style={{ color: 'var(--accent)' }}>{s.slice(matchIdx, matchIdx + token.length)}</strong>
                    {s.slice(matchIdx + token.length)}
                  </>
                ) : s}
              </button>
            )
          })}
        </div>
      )}
    </div>
  )
}

function FieldEditor({ field, value, displayValue, onChange, isEdited, suggestions }: {
  field: FieldDef
  value: unknown
  displayValue: string
  onChange: (val: unknown) => void
  isEdited: boolean
  suggestions: Suggestions
}) {
  const labelStyle: React.CSSProperties = {
    fontSize: 12, fontWeight: 600, color: isEdited ? 'var(--warning)' : 'var(--text-secondary)',
    marginBottom: 4, display: 'flex', alignItems: 'center', gap: 6,
  }

  const suggestionsKey = AUTOCOMPLETE_MAP[field.key]
  const fieldSuggestions = suggestionsKey ? (suggestions[suggestionsKey] || []) : []
  const hasAutocomplete = fieldSuggestions.length > 0

  if (field.type === 'boolean') {
    const checked = Boolean(value)
    return (
      <div>
        <div style={labelStyle}>
          {field.label}
          {isEdited && <span style={{ fontSize: 10 }}>*</span>}
        </div>
        <button
          onClick={() => onChange(!checked)}
          style={{
            display: 'flex', alignItems: 'center', gap: 8,
            background: 'var(--bg-tertiary)', border: '1px solid var(--border)',
            borderRadius: 8, padding: '8px 12px', cursor: 'pointer',
            color: 'var(--text-primary)', fontSize: 14,
          }}
        >
          <span style={{
            width: 36, height: 20, borderRadius: 10, position: 'relative',
            background: checked ? 'var(--accent)' : 'var(--border)',
            transition: 'background 0.2s',
          }}>
            <span style={{
              position: 'absolute', top: 2, left: checked ? 18 : 2,
              width: 16, height: 16, borderRadius: '50%', background: 'white',
              transition: 'left 0.2s',
            }} />
          </span>
          {checked ? 'Yes' : 'No'}
        </button>
      </div>
    )
  }

  if (field.type === 'select') {
    return (
      <div>
        <div style={labelStyle}>
          {field.label}
          {isEdited && <span style={{ fontSize: 10 }}>*</span>}
        </div>
        <select value={displayValue} onChange={(e) => onChange(e.target.value)}>
          <option value="">— Not set —</option>
          {field.options?.map(o => <option key={o} value={o}>{o}</option>)}
        </select>
      </div>
    )
  }

  if (field.type === 'textarea') {
    return (
      <div style={{ gridColumn: 'span 2' }}>
        <div style={labelStyle}>
          {field.label}
          {isEdited && <span style={{ fontSize: 10 }}>*</span>}
        </div>
        <textarea
          value={displayValue}
          onChange={(e) => onChange(e.target.value)}
          rows={4}
          style={{ resize: 'vertical', minHeight: 80 }}
        />
      </div>
    )
  }

  if (field.type === 'number') {
    return (
      <div>
        <div style={labelStyle}>
          {field.label}
          {isEdited && <span style={{ fontSize: 10 }}>*</span>}
        </div>
        <input type="number" value={displayValue} onChange={(e) => onChange(e.target.value)} />
      </div>
    )
  }

  if (hasAutocomplete) {
    const isArray = ARRAY_FIELDS.has(field.key)
    return (
      <div>
        <div style={labelStyle}>
          {field.label}
          {isEdited && <span style={{ fontSize: 10 }}>*</span>}
          {isArray && <span style={{ fontSize: 10, color: 'var(--text-muted)', fontWeight: 400 }}>(comma-separated)</span>}
        </div>
        <AutocompleteInput
          value={displayValue}
          onChange={(val) => onChange(val)}
          allSuggestions={fieldSuggestions}
          isArrayField={isArray}
        />
      </div>
    )
  }

  return (
    <div>
      <div style={labelStyle}>
        {field.label}
        {isEdited && <span style={{ fontSize: 10 }}>*</span>}
      </div>
      <input type="text" value={displayValue} onChange={(e) => onChange(e.target.value)} />
    </div>
  )
}
