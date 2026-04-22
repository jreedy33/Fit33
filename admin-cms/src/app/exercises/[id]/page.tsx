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
  primary_muscles: 'muscles', secondary_muscles: 'muscles',
  category: 'categories', equipment: 'equipment',
  equipment_category: 'equipment_categories', movement_pattern: 'movement_patterns',
  force_type: 'force_types', movement_type: 'movement_types',
  laterality: 'lateralities', plane_of_motion: 'planes_of_motion',
  body_position: 'body_positions', bench_angle: 'bench_angles',
  grip_type: 'grip_types', grip_width: 'grip_widths',
  exercise_family: 'exercise_families', placement_in_workout: 'placements',
  base_exercise_name: 'exercise_families',
}

const ARRAY_FIELDS = new Set(['primary_muscles', 'secondary_muscles'])

type FieldDef = {
  key: string; label: string;
  type: 'text' | 'textarea' | 'number' | 'boolean' | 'select'
  options?: string[]; section: string
}

const FIELD_DEFS: FieldDef[] = [
  { key: 'name', label: 'Name', type: 'text', section: 'Basic Info' },
  { key: 'category', label: 'Category', type: 'text', section: 'Basic Info' },
  { key: 'workout_type', label: 'Workout Type', type: 'select', options: ['Strength', 'Cardio', 'Stretch', 'Warmup', 'Plyometrics', 'Olympic Weightlifting', 'Strongman', 'Powerlifting'], section: 'Basic Info' },
  { key: 'equipment', label: 'Equipment', type: 'text', section: 'Basic Info' },
  { key: 'equipment_category', label: 'Equipment Category', type: 'text', section: 'Basic Info' },
  { key: 'gender', label: 'Gender', type: 'select', options: ['Male', 'Female'], section: 'Basic Info' },
  { key: 'difficulty_level', label: 'Difficulty (1-5)', type: 'number', section: 'Basic Info' },
  { key: 'complexity_score', label: 'Complexity', type: 'number', section: 'Basic Info' },

  { key: 'primary_muscles', label: 'Primary Muscles', type: 'text', section: 'Muscles' },
  { key: 'secondary_muscles', label: 'Secondary Muscles', type: 'text', section: 'Muscles' },
  { key: 'muscles_worked_count', label: 'Muscles Count', type: 'number', section: 'Muscles' },

  { key: 'description', label: 'Description', type: 'textarea', section: 'Description' },
  { key: 'instructions', label: 'Instructions', type: 'textarea', section: 'Description' },
  { key: 'steps_to_perform', label: 'Steps to Perform', type: 'textarea', section: 'Description' },

  { key: 'movement_pattern', label: 'Movement Pattern', type: 'text', section: 'Movement' },
  { key: 'force_type', label: 'Force Type', type: 'text', section: 'Movement' },
  { key: 'movement_type', label: 'Movement Type', type: 'text', section: 'Movement' },
  { key: 'laterality', label: 'Laterality', type: 'text', section: 'Movement' },
  { key: 'plane_of_motion', label: 'Plane of Motion', type: 'text', section: 'Movement' },
  { key: 'is_compound', label: 'Compound', type: 'boolean', section: 'Movement' },
  { key: 'body_position', label: 'Body Position', type: 'text', section: 'Movement' },
  { key: 'bench_angle', label: 'Bench Angle', type: 'text', section: 'Movement' },
  { key: 'grip_type', label: 'Grip Type', type: 'text', section: 'Movement' },
  { key: 'grip_width', label: 'Grip Width', type: 'text', section: 'Movement' },

  { key: 'strength_rating', label: 'Strength', type: 'number', section: 'Ratings' },
  { key: 'hypertrophy_rating', label: 'Hypertrophy', type: 'number', section: 'Ratings' },
  { key: 'power_rating', label: 'Power', type: 'number', section: 'Ratings' },
  { key: 'endurance_rating', label: 'Endurance', type: 'number', section: 'Ratings' },
  { key: 'fat_loss_rating', label: 'Fat Loss', type: 'number', section: 'Ratings' },
  { key: 'general_fitness_rating', label: 'General Fitness', type: 'number', section: 'Ratings' },
  { key: 'popularity_score', label: 'Popularity', type: 'number', section: 'Ratings' },
  { key: 'practicality_score', label: 'Practicality', type: 'number', section: 'Ratings' },
  { key: 'fatigability', label: 'Fatigability', type: 'number', section: 'Ratings' },

  { key: 'optimal_rep_range_min', label: 'Rep Min', type: 'number', section: 'Programming' },
  { key: 'optimal_rep_range_max', label: 'Rep Max', type: 'number', section: 'Programming' },
  { key: 'recommended_sets', label: 'Sets', type: 'number', section: 'Programming' },
  { key: 'rest_seconds', label: 'Rest (s)', type: 'number', section: 'Programming' },
  { key: 'placement_in_workout', label: 'Placement', type: 'text', section: 'Programming' },
  { key: 'duration_based', label: 'Duration Based', type: 'boolean', section: 'Programming' },
  { key: 'supersetable', label: 'Supersetable', type: 'boolean', section: 'Programming' },
  { key: 'home_gym_friendly', label: 'Home Friendly', type: 'boolean', section: 'Programming' },

  { key: 'exercise_family', label: 'Family', type: 'text', section: 'Family & Priority' },
  { key: 'base_exercise_name', label: 'Base Name', type: 'text', section: 'Family & Priority' },
  { key: 'complementary_families', label: 'Complementary', type: 'text', section: 'Family & Priority' },
  { key: 'is_equipment_primary', label: 'Equipment Primary', type: 'boolean', section: 'Family & Priority' },
  { key: 'priority_build_muscle', label: 'P: Muscle', type: 'number', section: 'Family & Priority' },
  { key: 'priority_get_lean', label: 'P: Lean', type: 'number', section: 'Family & Priority' },
  { key: 'priority_home', label: 'P: Home', type: 'number', section: 'Family & Priority' },
  { key: 'priority_gym', label: 'P: Gym', type: 'number', section: 'Family & Priority' },

  { key: 'video_filename', label: 'Video Filename', type: 'text', section: 'Video' },
  { key: 'video_code', label: 'Video Code', type: 'text', section: 'Video' },
]

const SECTIONS = ['Basic Info', 'Muscles', 'Description', 'Movement', 'Ratings', 'Programming', 'Family & Priority', 'Video']

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
  const [suggestions, setSuggestions] = useState<Suggestions>({})
  const [navIds, setNavIds] = useState<string[]>([])

  const loadExercise = useCallback(async () => {
    setLoading(true)
    const data = await adminAction('get_exercise', { exercise_id: exerciseId })
    if (data.exercise) { setExercise(data.exercise); setEditedFields({}) }
    setLoading(false)
  }, [exerciseId])

  const loadSuggestions = useCallback(async () => {
    const data = await adminAction('get_exercise_suggestions')
    if (!data.error) setSuggestions(data)
  }, [])

  useEffect(() => { loadExercise() }, [loadExercise])
  useEffect(() => { loadSuggestions() }, [loadSuggestions])
  useEffect(() => {
    try { const ids = JSON.parse(sessionStorage.getItem('exerciseIds') || '[]'); setNavIds(ids) } catch { /* */ }
  }, [])

  const currentIdx = navIds.indexOf(exerciseId)
  const prevId = currentIdx > 0 ? navIds[currentIdx - 1] : null
  const nextId = currentIdx >= 0 && currentIdx < navIds.length - 1 ? navIds[currentIdx + 1] : null

  const getValue = (key: string): unknown => key in editedFields ? editedFields[key] : (exercise?.[key] ?? null)
  const getDisplayValue = (key: string): string => {
    const val = getValue(key)
    if (val === null || val === undefined) return ''
    if (ARRAY_FIELDS.has(key)) return parseMuscleDisplay(val)
    return String(val)
  }
  const setField = (key: string, value: unknown) => { setEditedFields(prev => ({ ...prev, [key]: value })); setSaveMsg(null) }
  const hasChanges = Object.keys(editedFields).length > 0

  // "Updated" marker: any unsaved content edit auto-checks the box; the
  // admin can still click it to explicitly clear the manual-edit flag.
  const rawManuallyUpdated = 'manually_updated' in editedFields
    ? Boolean(editedFields.manually_updated)
    : Boolean(exercise?.manually_updated)
  const contentEdits = Object.keys(editedFields).filter(k => k !== 'manually_updated').length > 0
  const manuallyUpdatedDisplay = rawManuallyUpdated || contentEdits
  const manuallyUpdatedAt = exercise?.manually_updated_at as string | null | undefined
  const toggleManuallyUpdated = () => {
    // If there are pending content edits we leave the box auto-checked —
    // the save payload will stamp it server-side. Otherwise clicking
    // toggles the explicit flag (letting the admin un-mark a row).
    if (contentEdits) return
    setField('manually_updated', !rawManuallyUpdated)
  }
  const formatUpdatedAt = (iso: string | null | undefined): string => {
    if (!iso) return ''
    const d = new Date(iso)
    if (isNaN(d.getTime())) return ''
    return d.toLocaleDateString(undefined, { month: 'short', day: 'numeric', year: 'numeric' })
  }

  const handleSave = async () => {
    if (!hasChanges) return
    setSaving(true); setSaveMsg(null)
    const updates: Record<string, unknown> = {}
    for (const [key, value] of Object.entries(editedFields)) {
      const def = FIELD_DEFS.find(f => f.key === key)
      if (def?.type === 'number') { updates[key] = value === '' || value === null ? null : Number(value) }
      else if (def?.type === 'boolean') { updates[key] = Boolean(value) }
      else if (ARRAY_FIELDS.has(key)) {
        if (typeof value === 'string') { const arr = value.split(',').map(s => s.trim()).filter(Boolean); updates[key] = arr.length > 0 ? arr : null }
        else { updates[key] = value }
      } else { updates[key] = value === '' ? null : value }
    }
    const result = await adminAction('update_exercise', { exercise_id: exerciseId, updates })
    if (result.error) { setSaveMsg({ type: 'error', text: result.error }) }
    else { setExercise(result.exercise); setEditedFields({}); setSaveMsg({ type: 'success', text: 'Saved' }) }
    setSaving(false)
  }

  const handleDelete = async () => {
    setDeleting(true)
    const result = await adminAction('delete_exercise', { exercise_id: exerciseId })
    if (result.error) { setSaveMsg({ type: 'error', text: result.error }); setDeleting(false); setShowDeleteConfirm(false) }
    else { router.push('/exercises') }
  }

  const videoFilename = getDisplayValue('video_filename')
  const videoUrl = videoFilename ? `${R2_BASE}/${videoFilename}` : null

  if (loading) return <AdminShell><div className="flex items-center justify-center" style={{ padding: 80 }}><div className="spinner" /></div></AdminShell>
  if (!exercise) return (
    <AdminShell><div style={{ padding: 32 }}>
      <p style={{ color: 'var(--text-muted)' }}>Exercise not found.</p>
      <button className="btn btn-ghost" style={{ marginTop: 12 }} onClick={() => router.push('/exercises')}>← Back</button>
    </div></AdminShell>
  )

  return (
    <AdminShell>
      <div style={{ padding: '20px 28px', paddingBottom: hasChanges ? 72 : 20 }}>
        {/* Top bar: back, name, nav arrows, actions */}
        <div className="flex items-center gap-2" style={{ marginBottom: 16 }}>
          <button className="btn btn-ghost" onClick={() => router.push('/exercises')} style={{ fontSize: 13, padding: '5px 10px' }}>← Back</button>

          {prevId && <button className="btn btn-ghost" onClick={() => router.push(`/exercises/${prevId}`)} style={{ fontSize: 13, padding: '5px 10px' }}>‹ Prev</button>}
          {nextId && <button className="btn btn-ghost" onClick={() => router.push(`/exercises/${nextId}`)} style={{ fontSize: 13, padding: '5px 10px' }}>Next ›</button>}

          {currentIdx >= 0 && (
            <span style={{ fontSize: 11, color: 'var(--text-muted)', marginLeft: 4 }}>
              {currentIdx + 1} / {navIds.length}
            </span>
          )}

          <div style={{ flex: 1 }}>
            <h1 style={{ fontSize: 20, fontWeight: 700, marginLeft: 8 }}>{exercise.name as string}</h1>
          </div>

          {saveMsg && <span style={{ fontSize: 12, color: saveMsg.type === 'success' ? 'var(--success)' : 'var(--danger)' }}>{saveMsg.text}</span>}

          <label
            onClick={e => { e.preventDefault(); toggleManuallyUpdated() }}
            title={contentEdits ? 'Will mark as manually updated when you save' : (rawManuallyUpdated ? 'Click to clear manual-edit flag' : 'Click to mark as manually updated')}
            style={{
              display: 'flex', alignItems: 'center', gap: 6,
              padding: '4px 10px', borderRadius: 6,
              background: 'var(--bg-tertiary)', border: '1px solid var(--border)',
              cursor: contentEdits ? 'default' : 'pointer',
              fontSize: 12, color: 'var(--text-primary)',
              opacity: contentEdits ? 0.95 : 1,
            }}
          >
            <input
              type="checkbox"
              checked={manuallyUpdatedDisplay}
              onChange={() => { /* handled by parent onClick */ }}
              readOnly
              style={{ width: 14, height: 14, accentColor: 'var(--accent)', cursor: contentEdits ? 'default' : 'pointer' }}
            />
            <span style={{ fontWeight: 600 }}>Updated</span>
            {manuallyUpdatedAt && (
              <span style={{ color: 'var(--text-muted)', fontWeight: 400 }}>
                {formatUpdatedAt(manuallyUpdatedAt)}
              </span>
            )}
          </label>

          <button className="btn btn-danger" onClick={() => setShowDeleteConfirm(true)} style={{ fontSize: 12, padding: '5px 12px' }}>Delete</button>
          <button className="btn btn-primary" disabled={!hasChanges || saving} onClick={handleSave} style={{ fontSize: 12, padding: '5px 14px' }}>
            {saving ? 'Saving...' : 'Save'}
          </button>
        </div>

        {/* Main layout: video left, all fields right */}
        <div style={{ display: 'flex', gap: 20, alignItems: 'flex-start' }}>
          {/* Left: video (sticky) */}
          <div style={{ width: 300, flexShrink: 0, position: 'sticky', top: 20 }}>
            {videoUrl ? (
              <video key={videoUrl} src={videoUrl} autoPlay loop muted playsInline
                style={{ width: '100%', borderRadius: 12, background: '#000' }}
              />
            ) : (
              <div style={{ width: '100%', aspectRatio: '3/4', background: 'var(--bg-tertiary)', borderRadius: 12, display: 'flex', alignItems: 'center', justifyContent: 'center', color: 'var(--text-muted)', fontSize: 40 }}>
                🏋️
              </div>
            )}
          </div>

          {/* Right: all editable sections */}
          <div style={{ flex: 1, minWidth: 0 }}>
            {SECTIONS.map(section => {
              const fields = FIELD_DEFS.filter(f => f.section === section)
              if (!fields.length) return null
              const hasTextareas = fields.some(f => f.type === 'textarea')
              return (
                <div key={section} style={{ marginBottom: 20 }}>
                  <div style={{ fontSize: 11, fontWeight: 700, textTransform: 'uppercase', letterSpacing: '0.06em', color: 'var(--text-muted)', marginBottom: 8, paddingLeft: 2 }}>
                    {section}
                  </div>
                  <div style={{
                    display: 'grid',
                    gridTemplateColumns: hasTextareas ? '1fr' : 'repeat(auto-fill, minmax(180px, 1fr))',
                    gap: 8,
                    background: 'var(--bg-secondary)', border: '1px solid var(--border)', borderRadius: 10, padding: 12,
                  }}>
                    {fields.map(field => (
                      <FieldEditor key={field.key} field={field} value={getValue(field.key)} displayValue={getDisplayValue(field.key)}
                        onChange={(val) => setField(field.key, val)} isEdited={field.key in editedFields} suggestions={suggestions} />
                    ))}
                  </div>
                </div>
              )
            })}
          </div>
        </div>

        {/* Unsaved bar */}
        {hasChanges && (
          <div style={{ position: 'fixed', bottom: 0, left: 0, right: 0, background: 'var(--bg-secondary)', borderTop: '1px solid var(--border)', padding: '10px 28px', display: 'flex', alignItems: 'center', justifyContent: 'flex-end', gap: 10, zIndex: 50 }}>
            <span style={{ fontSize: 12, color: 'var(--warning)' }}>{Object.keys(editedFields).length} unsaved</span>
            <button className="btn btn-ghost" onClick={() => { setEditedFields({}); setSaveMsg(null) }} style={{ fontSize: 12 }}>Discard</button>
            <button className="btn btn-primary" onClick={handleSave} disabled={saving} style={{ fontSize: 12 }}>{saving ? 'Saving...' : 'Save'}</button>
          </div>
        )}

        {/* Delete modal */}
        {showDeleteConfirm && (
          <div style={{ position: 'fixed', inset: 0, background: 'rgba(0,0,0,0.6)', display: 'flex', alignItems: 'center', justifyContent: 'center', zIndex: 100 }} onClick={() => !deleting && setShowDeleteConfirm(false)}>
            <div className="card" style={{ maxWidth: 420, width: '90%' }} onClick={e => e.stopPropagation()}>
              <h3 style={{ fontSize: 17, fontWeight: 700, marginBottom: 8 }}>Delete Exercise</h3>
              <p style={{ color: 'var(--text-secondary)', fontSize: 13, marginBottom: 6 }}>Permanently delete <strong>{exercise.name as string}</strong>?</p>
              <p style={{ color: 'var(--danger)', fontSize: 12, marginBottom: 16 }}>Removes from database and app. Cannot be undone.</p>
              <div className="flex gap-2" style={{ justifyContent: 'flex-end' }}>
                <button className="btn btn-ghost" onClick={() => setShowDeleteConfirm(false)} disabled={deleting} style={{ fontSize: 12 }}>Cancel</button>
                <button className="btn btn-danger" onClick={handleDelete} disabled={deleting} style={{ fontSize: 12 }}>{deleting ? 'Deleting...' : 'Delete'}</button>
              </div>
            </div>
          </div>
        )}
      </div>
    </AdminShell>
  )
}

function AutocompleteInput({ value, onChange, allSuggestions, isArrayField }: {
  value: string; onChange: (val: string) => void; allSuggestions: string[]; isArrayField: boolean
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
    setFiltered(allSuggestions.filter(s => s.toLowerCase().includes(lower) && s.toLowerCase() !== lower).slice(0, 8))
    setSelectedIdx(-1)
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [value, allSuggestions])

  useEffect(() => { if (focused) updateFiltered() }, [focused, updateFiltered])

  const applySuggestion = (suggestion: string) => {
    if (isArrayField) {
      const { before, after } = getActiveToken()
      onChange(`${before}${suggestion}${after}`.replace(/,\s*,/g, ',').replace(/^,\s*/, '').replace(/,\s*$/, ''))
    } else { onChange(suggestion) }
    setFiltered([]); setFocused(false)
  }

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (!filtered.length) return
    if (e.key === 'ArrowDown') { e.preventDefault(); setSelectedIdx(i => Math.min(i + 1, filtered.length - 1)) }
    else if (e.key === 'ArrowUp') { e.preventDefault(); setSelectedIdx(i => Math.max(i - 1, 0)) }
    else if (e.key === 'Enter' && selectedIdx >= 0) { e.preventDefault(); applySuggestion(filtered[selectedIdx]) }
    else if (e.key === 'Escape') { setFiltered([]) }
  }

  useEffect(() => {
    const h = (e: MouseEvent) => { if (wrapperRef.current && !wrapperRef.current.contains(e.target as Node)) { setFocused(false); setFiltered([]) } }
    document.addEventListener('mousedown', h); return () => document.removeEventListener('mousedown', h)
  }, [])

  return (
    <div ref={wrapperRef} style={{ position: 'relative' }}>
      <input ref={inputRef} type="text" value={value}
        onChange={e => { onChange(e.target.value); if (focused) updateFiltered() }}
        onFocus={() => { setFocused(true); updateFiltered() }} onKeyDown={handleKeyDown}
        style={{ fontSize: 13, padding: '6px 8px' }} />
      {focused && filtered.length > 0 && (
        <div style={{ position: 'absolute', top: '100%', left: 0, right: 0, zIndex: 60, background: 'var(--bg-secondary)', border: '1px solid var(--border)', borderRadius: 6, marginTop: 2, overflow: 'hidden', boxShadow: '0 6px 20px rgba(0,0,0,0.4)', maxHeight: 200, overflowY: 'auto' }}>
          {filtered.map((s, i) => {
            const { token } = getActiveToken()
            const mi = s.toLowerCase().indexOf(token.toLowerCase())
            return (
              <button key={s} onMouseDown={e => { e.preventDefault(); applySuggestion(s) }}
                style={{ display: 'block', width: '100%', textAlign: 'left', padding: '6px 10px', fontSize: 12, cursor: 'pointer', background: i === selectedIdx ? 'var(--bg-hover)' : 'transparent', color: 'var(--text-primary)', border: 'none', borderBottom: i < filtered.length - 1 ? '1px solid var(--border)' : 'none' }}>
                {mi >= 0 ? <>{s.slice(0, mi)}<strong style={{ color: 'var(--accent)' }}>{s.slice(mi, mi + token.length)}</strong>{s.slice(mi + token.length)}</> : s}
              </button>
            )
          })}
        </div>
      )}
    </div>
  )
}

function FieldEditor({ field, value, displayValue, onChange, isEdited, suggestions }: {
  field: FieldDef; value: unknown; displayValue: string; onChange: (val: unknown) => void; isEdited: boolean; suggestions: Suggestions
}) {
  const lbl: React.CSSProperties = { fontSize: 10, fontWeight: 600, color: isEdited ? 'var(--warning)' : 'var(--text-muted)', marginBottom: 3, display: 'flex', alignItems: 'center', gap: 4 }
  const sugKey = AUTOCOMPLETE_MAP[field.key]
  const fieldSugg = sugKey ? (suggestions[sugKey] || []) : []

  if (field.type === 'boolean') {
    const checked = Boolean(value)
    return (
      <div>
        <div style={lbl}>{field.label}{isEdited && '*'}</div>
        <button onClick={() => onChange(!checked)}
          style={{ display: 'flex', alignItems: 'center', gap: 6, background: 'var(--bg-tertiary)', border: '1px solid var(--border)', borderRadius: 6, padding: '5px 8px', cursor: 'pointer', color: 'var(--text-primary)', fontSize: 12, width: '100%' }}>
          <span style={{ width: 28, height: 16, borderRadius: 8, position: 'relative', background: checked ? 'var(--accent)' : 'var(--border)', transition: 'background 0.2s', flexShrink: 0 }}>
            <span style={{ position: 'absolute', top: 2, left: checked ? 14 : 2, width: 12, height: 12, borderRadius: '50%', background: 'white', transition: 'left 0.2s' }} />
          </span>
          {checked ? 'Yes' : 'No'}
        </button>
      </div>
    )
  }
  if (field.type === 'select') {
    return (
      <div>
        <div style={lbl}>{field.label}{isEdited && '*'}</div>
        <select value={displayValue} onChange={e => onChange(e.target.value)} style={{ fontSize: 13, padding: '6px 8px' }}>
          <option value="">—</option>
          {field.options?.map(o => <option key={o} value={o}>{o}</option>)}
        </select>
      </div>
    )
  }
  if (field.type === 'textarea') {
    return (
      <div>
        <div style={lbl}>{field.label}{isEdited && '*'}</div>
        <textarea value={displayValue} onChange={e => onChange(e.target.value)} rows={3} style={{ resize: 'vertical', minHeight: 60, fontSize: 13, padding: '6px 8px' }} />
      </div>
    )
  }
  if (field.type === 'number') {
    return (
      <div>
        <div style={lbl}>{field.label}{isEdited && '*'}</div>
        <input type="number" value={displayValue} onChange={e => onChange(e.target.value)} style={{ fontSize: 13, padding: '6px 8px' }} />
      </div>
    )
  }
  if (fieldSugg.length > 0) {
    const isArr = ARRAY_FIELDS.has(field.key)
    return (
      <div>
        <div style={lbl}>{field.label}{isEdited && '*'}{isArr && <span style={{ fontSize: 9, fontWeight: 400 }}>(comma-sep)</span>}</div>
        <AutocompleteInput value={displayValue} onChange={val => onChange(val)} allSuggestions={fieldSugg} isArrayField={isArr} />
      </div>
    )
  }
  return (
    <div>
      <div style={lbl}>{field.label}{isEdited && '*'}</div>
      <input type="text" value={displayValue} onChange={e => onChange(e.target.value)} style={{ fontSize: 13, padding: '6px 8px' }} />
    </div>
  )
}
