'use client'

import { useEffect, useState, use } from 'react'
import { useRouter } from 'next/navigation'
import AdminShell from '@/components/AdminShell'
import { adminApi } from '@/lib/api'

type Tab = 'profile' | 'friends' | 'challenges' | 'workouts' | 'health' | 'notifications' | 'engagement' | 'moderation'

// eslint-disable-next-line @typescript-eslint/no-explicit-any
type AnyRecord = Record<string, any>

export default function UserDetailPage({ params }: { params: Promise<{ id: string }> }) {
  const { id: userId } = use(params)
  const router = useRouter()
  const [tab, setTab] = useState<Tab>('profile')
  const [profile, setProfile] = useState<AnyRecord | null>(null)
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [saveMsg, setSaveMsg] = useState('')

  // Tab data
  const [friends, setFriends] = useState<AnyRecord[]>([])
  const [challenges, setChallenges] = useState<AnyRecord[]>([])
  const [workouts, setWorkouts] = useState<AnyRecord[]>([])
  const [streaks, setStreaks] = useState<AnyRecord[]>([])
  const [weightLogs, setWeightLogs] = useState<AnyRecord[]>([])
  const [meals, setMeals] = useState<AnyRecord[]>([])
  const [hydration, setHydration] = useState<AnyRecord[]>([])
  const [steps, setSteps] = useState<AnyRecord[]>([])
  const [cardio, setCardio] = useState<AnyRecord[]>([])
  const [notifications, setNotifications] = useState<AnyRecord[]>([])
  const [bugReports, setBugReports] = useState<AnyRecord[]>([])
  const [engagement, setEngagement] = useState<AnyRecord | null>(null)
  const [userReports, setUserReports] = useState<AnyRecord[]>([])
  const [userSuspensions, setUserSuspensions] = useState<AnyRecord[]>([])
  const [tabLoading, setTabLoading] = useState(false)

  // Editable profile fields
  const [edits, setEdits] = useState<AnyRecord>({})

  useEffect(() => {
    loadUser()
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [userId])

  async function loadUser() {
    setLoading(true)
    try {
      const data = await adminApi('get_user', { user_id: userId })
      setProfile(data.profile)
      setEdits({})
    } catch (err) {
      console.error('Failed to load user:', err)
    } finally {
      setLoading(false)
    }
  }

  async function loadTabData(t: Tab) {
    if (t === 'profile') return
    setTabLoading(true)
    try {
      switch (t) {
        case 'friends': {
          const d = await adminApi('get_user_friends', { user_id: userId })
          setFriends(d.friends)
          break
        }
        case 'challenges': {
          const d = await adminApi('get_user_challenges', { user_id: userId })
          setChallenges(d.challenges)
          break
        }
        case 'workouts': {
          const [w, c] = await Promise.all([
            adminApi('get_user_workouts', { user_id: userId }),
            adminApi('get_user_cardio', { user_id: userId }),
          ])
          setWorkouts(w.workouts)
          setCardio(c.cardio)
          break
        }
        case 'health': {
          const [s, wl, m, h, st] = await Promise.all([
            adminApi('get_user_streaks', { user_id: userId }),
            adminApi('get_user_weight_logs', { user_id: userId }),
            adminApi('get_user_meals', { user_id: userId }),
            adminApi('get_user_hydration', { user_id: userId }),
            adminApi('get_user_steps', { user_id: userId }),
          ])
          setStreaks(s.streaks)
          setWeightLogs(wl.weight_logs)
          setMeals(m.meals)
          setHydration(h.hydration)
          setSteps(st.steps)
          break
        }
        case 'notifications': {
          const [n, b] = await Promise.all([
            adminApi('get_user_notifications', { user_id: userId }),
            adminApi('get_user_bug_reports', { user_id: userId }),
          ])
          setNotifications(n.notifications)
          setBugReports(b.bug_reports)
          break
        }
        case 'engagement': {
          const d = await adminApi('engagement_user_detail', { user_id: userId })
          setEngagement(d.engagement)
          break
        }
        case 'moderation': {
          const [r, s] = await Promise.all([
            adminApi('get_user_reports', { user_id: userId }),
            adminApi('get_user_suspensions', { user_id: userId }),
          ])
          setUserReports(r.reports || [])
          setUserSuspensions(s.suspensions || [])
          break
        }
      }
    } catch (err) {
      console.error(`Failed to load ${t}:`, err)
    } finally {
      setTabLoading(false)
    }
  }

  function switchTab(t: Tab) {
    setTab(t)
    loadTabData(t)
  }

  function editField(field: string, value: unknown) {
    setEdits(prev => ({ ...prev, [field]: value }))
  }

  async function saveChanges() {
    if (Object.keys(edits).length === 0) return
    setSaving(true)
    setSaveMsg('')
    try {
      const data = await adminApi('update_user', { user_id: userId, updates: edits })
      setProfile(data.profile)
      setEdits({})
      setSaveMsg('✅ Saved successfully')
      setTimeout(() => setSaveMsg(''), 3000)
    } catch (err) {
      setSaveMsg(`❌ ${err instanceof Error ? err.message : 'Save failed'}`)
    } finally {
      setSaving(false)
    }
  }

  function getVal(field: string) {
    return field in edits ? edits[field] : profile?.[field]
  }

  function formatDate(iso: string | null) {
    if (!iso) return '—'
    return new Date(iso).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric', hour: '2-digit', minute: '2-digit' })
  }

  function formatDuration(seconds: number) {
    const m = Math.floor(seconds / 60)
    const s = seconds % 60
    return m > 0 ? `${m}m ${s}s` : `${s}s`
  }

  if (loading) {
    return (
      <AdminShell>
        <div className="flex justify-center py-20"><div className="spinner" style={{ width: 32, height: 32 }} /></div>
      </AdminShell>
    )
  }

  if (!profile) {
    return (
      <AdminShell>
        <div className="p-6 text-center" style={{ color: 'var(--text-muted)' }}>
          User not found. <button onClick={() => router.push('/users')} className="btn btn-ghost ml-2">← Back to Users</button>
        </div>
      </AdminShell>
    )
  }

  const tabs: { key: Tab; label: string; icon: string }[] = [
    { key: 'profile', label: 'Profile', icon: '👤' },
    { key: 'friends', label: 'Friends', icon: '👫' },
    { key: 'challenges', label: 'Challenges', icon: '🏆' },
    { key: 'workouts', label: 'Workouts', icon: '💪' },
    { key: 'health', label: 'Health & Streaks', icon: '❤️' },
    { key: 'notifications', label: 'Notifications & Bugs', icon: '🔔' },
    { key: 'engagement', label: 'Engagement', icon: '🎯' },
    { key: 'moderation', label: 'Moderation', icon: '🛡️' },
  ]

  return (
    <AdminShell>
      <div className="p-6 max-w-7xl mx-auto">
        {/* Header */}
        <div className="flex items-center gap-4 mb-6">
          <button onClick={() => router.push('/users')} className="btn btn-ghost text-sm">← Back</button>
          <div className="flex items-center gap-4 flex-1">
            <div
              className="w-14 h-14 rounded-full flex items-center justify-center text-xl font-bold shrink-0"
              style={{
                background: profile.profile_photo_url ? 'transparent' : 'var(--bg-tertiary)',
                color: 'var(--text-secondary)',
                backgroundImage: profile.profile_photo_url ? `url(${profile.profile_photo_url})` : undefined,
                backgroundSize: 'cover',
              }}
            >
              {!profile.profile_photo_url && (profile.name?.[0] || '?')}
            </div>
            <div>
              <div className="flex items-center gap-2">
                <h1 className="text-xl font-bold">{profile.name || 'Unnamed User'}</h1>
                {getVal('is_gold_verified') ? (
                  <span title="Gold Verified" style={{ color: '#D4A017', fontSize: 18 }}>✓</span>
                ) : getVal('is_verified') ? (
                  <span title="Verified" style={{ color: '#1DA1F2', fontSize: 18 }}>✓</span>
                ) : null}
                <button
                  onClick={() => editField('is_verified', !getVal('is_verified'))}
                  className="ml-1 px-2 py-0.5 rounded-full text-xs font-semibold transition-colors"
                  style={{
                    background: getVal('is_verified') ? 'rgba(29, 161, 242, 0.15)' : 'var(--bg-tertiary)',
                    color: getVal('is_verified') ? '#1DA1F2' : 'var(--text-muted)',
                    border: `1px solid ${getVal('is_verified') ? '#1DA1F2' : 'var(--border)'}`,
                  }}
                >
                  {getVal('is_verified') ? '✓ Verified' : 'Set Verified'}
                </button>
                <button
                  onClick={() => editField('is_gold_verified', !getVal('is_gold_verified'))}
                  className="px-2 py-0.5 rounded-full text-xs font-semibold transition-colors"
                  style={{
                    background: getVal('is_gold_verified') ? 'rgba(212, 160, 23, 0.15)' : 'var(--bg-tertiary)',
                    color: getVal('is_gold_verified') ? '#D4A017' : 'var(--text-muted)',
                    border: `1px solid ${getVal('is_gold_verified') ? '#D4A017' : 'var(--border)'}`,
                  }}
                >
                  {getVal('is_gold_verified') ? '★ Gold Verified' : 'Set Gold'}
                </button>
              </div>
              <div className="flex items-center gap-3 mt-1 text-sm" style={{ color: 'var(--text-secondary)' }}>
                <span>@{profile.username || '—'}</span>
                <span>•</span>
                <span>{profile.email || '—'}</span>
                {profile.phone_number && <><span>•</span><span>{profile.phone_number}</span></>}
              </div>
            </div>
          </div>
          <div className="text-right text-xs" style={{ color: 'var(--text-muted)' }}>
            <div>ID: {userId.slice(0, 8)}...</div>
            <div>Joined {formatDate(profile.created_at)}</div>
            <div className="mt-1 flex items-center gap-1.5 justify-end">
              <span
                className="inline-block w-2 h-2 rounded-full"
                style={{
                  background: profile.last_active_at && (Date.now() - new Date(profile.last_active_at).getTime()) < 24 * 60 * 60 * 1000
                    ? 'var(--success)' : 'var(--text-muted)',
                }}
              />
              Last active {profile.last_active_at
                ? new Date(profile.last_active_at).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric', hour: '2-digit', minute: '2-digit', timeZoneName: 'short' })
                : '—'}
            </div>
          </div>
        </div>

        {/* Quick Stats */}
        <div className="grid grid-cols-2 sm:grid-cols-4 lg:grid-cols-6 gap-3 mb-6">
          <MiniStat label="Streak" value={`🔥 ${profile.current_streak || 0}`} />
          <MiniStat label="Longest" value={`${profile.longest_streak || 0} days`} />
          <MiniStat label="Workouts" value={profile.total_workouts || 0} />
          <MiniStat label="XP" value={(profile.xp || 0).toLocaleString()} />
          <MiniStat label="Goal" value={profile.fitness_goal || '—'} />
          <MiniStat label="Level" value={profile.experience_level || '—'} />
        </div>

        {/* Tabs */}
        <div className="flex border-b mb-6 overflow-x-auto" style={{ borderColor: 'var(--border)' }}>
          {tabs.map((t) => (
            <button
              key={t.key}
              onClick={() => switchTab(t.key)}
              className={`tab ${tab === t.key ? 'tab-active' : ''}`}
            >
              <span className="mr-1.5">{t.icon}</span>{t.label}
            </button>
          ))}
        </div>

        {/* Tab Content */}
        {tabLoading && tab !== 'profile' ? (
          <div className="flex justify-center py-12"><div className="spinner" style={{ width: 28, height: 28 }} /></div>
        ) : (
          <>
            {/* ═══════════════ PROFILE TAB ═══════════════ */}
            {tab === 'profile' && (
              <div className="space-y-6">
                {/* Save Bar */}
                {Object.keys(edits).length > 0 && (
                  <div className="flex items-center gap-3 p-3 rounded-lg" style={{ background: 'rgba(99, 102, 241, 0.1)', border: '1px solid var(--accent)' }}>
                    <span className="text-sm font-medium" style={{ color: 'var(--accent)' }}>
                      {Object.keys(edits).length} unsaved change{Object.keys(edits).length > 1 ? 's' : ''}
                    </span>
                    <div className="flex-1" />
                    <button onClick={() => setEdits({})} className="btn btn-ghost text-xs">Discard</button>
                    <button onClick={saveChanges} disabled={saving} className="btn btn-primary text-sm">
                      {saving ? <><span className="spinner" /> Saving...</> : '💾 Save Changes'}
                    </button>
                  </div>
                )}
                {saveMsg && (
                  <div className="text-sm font-medium p-2" style={{ color: saveMsg.startsWith('✅') ? 'var(--success)' : 'var(--danger)' }}>{saveMsg}</div>
                )}

                {/* Personal Info */}
                <Section title="Personal Information">
                  <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
                    <EditField label="Name" field="name" value={getVal('name')} onChange={editField} />
                    <EditField label="Email" field="email" value={getVal('email')} onChange={editField} />
                    <EditField label="Username" field="username" value={getVal('username')} onChange={editField} />
                    <EditField label="Phone" field="phone_number" value={getVal('phone_number')} onChange={editField} />
                    <EditField label="Birthday" field="birthday" value={getVal('birthday')} onChange={editField} />
                    <EditField label="Age" field="age" value={getVal('age')} onChange={editField} type="number" />
                    <SelectField label="Gender" field="gender" value={getVal('gender')} onChange={editField} options={['Male', 'Female', 'Other']} />
                  </div>
                </Section>

                {/* Body Measurements */}
                <Section title="Body Measurements">
                  <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
                    <EditField label="Height (cm)" field="height_cm" value={getVal('height_cm')} onChange={editField} type="number" />
                    <EditField label="Height (inches)" field="height_inches" value={getVal('height_inches')} onChange={editField} type="number" />
                    <EditField label="Weight (kg)" field="weight_kg" value={getVal('weight_kg')} onChange={editField} type="number" />
                    <EditField label="Weight (lbs)" field="weight_lbs" value={getVal('weight_lbs')} onChange={editField} type="number" />
                  </div>
                </Section>

                {/* Fitness Settings */}
                <Section title="Fitness Settings">
                  <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
                    <SelectField label="Fitness Goal" field="fitness_goal" value={getVal('fitness_goal')} onChange={editField}
                      options={['Build Muscle', 'Get Lean', 'General Fitness', 'Gain Strength', 'Improve Endurance']} />
                    <SelectField label="Experience Level" field="experience_level" value={getVal('experience_level')} onChange={editField}
                      options={['Beginner', 'Intermediate', 'Advanced']} />
                    <SelectField label="Strength Level" field="strength_level" value={getVal('strength_level')} onChange={editField}
                      options={['Novice', 'Beginner', 'Intermediate', 'Advanced', 'Elite']} />
                    <SelectField label="Workout Environment" field="workout_environment" value={getVal('workout_environment')} onChange={editField}
                      options={['Gym', 'Home', 'Outdoor', 'Hybrid']} />
                    <EditField label="Available Days/Week" field="available_days" value={getVal('available_days')} onChange={editField} type="number" />
                    <ReadonlyField label="Equipment" value={Array.isArray(profile.equipment) ? profile.equipment.join(', ') : profile.equipment || '—'} />
                  </div>
                </Section>

                {/* Stats & Streak */}
                <Section title="Stats & Streaks">
                  <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
                    <EditField label="Current Streak" field="current_streak" value={getVal('current_streak')} onChange={editField} type="number" />
                    <EditField label="Longest Streak" field="longest_streak" value={getVal('longest_streak')} onChange={editField} type="number" />
                    <EditField label="Total Workouts" field="total_workouts" value={getVal('total_workouts')} onChange={editField} type="number" />
                    <EditField label="XP" field="xp" value={getVal('xp')} onChange={editField} type="number" />
                    <EditField label="Last Workout Date" field="last_workout_date" value={getVal('last_workout_date')} onChange={editField} />
                    <SelectField label="Onboarding Complete" field="has_completed_onboarding" value={getVal('has_completed_onboarding')} onChange={editField}
                      options={[{ label: 'Yes', value: true }, { label: 'No', value: false }]} />
                  </div>
                </Section>

                {/* Nutrition Goals */}
                <Section title="Nutrition Goals">
                  <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
                    <EditField label="Daily Calorie Goal" field="daily_calorie_goal" value={getVal('daily_calorie_goal')} onChange={editField} type="number" />
                    <EditField label="Daily Protein (g)" field="daily_protein_goal" value={getVal('daily_protein_goal')} onChange={editField} type="number" />
                    <EditField label="Daily Carbs (g)" field="daily_carbs_goal" value={getVal('daily_carbs_goal')} onChange={editField} type="number" />
                    <EditField label="Daily Fat (g)" field="daily_fat_goal" value={getVal('daily_fat_goal')} onChange={editField} type="number" />
                    <ReadonlyField label="BMR" value={profile.bmr ?? '—'} />
                    <ReadonlyField label="TDEE" value={profile.tdee ?? '—'} />
                  </div>
                </Section>

                {/* Unit Preferences */}
                <Section title="Unit Preferences">
                  <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
                    <SelectField label="Weight Unit" field="weight_unit" value={getVal('weight_unit')} onChange={editField} options={['lbs', 'kg']} />
                    <SelectField label="Height Unit" field="height_unit" value={getVal('height_unit')} onChange={editField} options={['ft/in', 'cm']} />
                    <SelectField label="Distance Unit" field="distance_unit" value={getVal('distance_unit')} onChange={editField} options={['mi', 'km']} />
                    <SelectField label="Week Start Day" field="week_start_day" value={getVal('week_start_day')} onChange={editField} options={['monday', 'sunday']} />
                  </div>
                </Section>

                {/* Raw Metadata */}
                <Section title="Account Metadata">
                  <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                    <ReadonlyField label="User ID" value={profile.id} />
                    <ReadonlyField label="Created At" value={formatDate(profile.created_at)} />
                    <ReadonlyField label="Updated At" value={formatDate(profile.updated_at)} />
                    <ReadonlyField label="Phone Verified" value={profile.phone_verified ? 'Yes' : 'No'} />
                    <ReadonlyField label="Profile Photo URL" value={profile.profile_photo_url || 'None'} />
                  </div>
                </Section>
              </div>
            )}

            {/* ═══════════════ FRIENDS TAB ═══════════════ */}
            {tab === 'friends' && (
              <div className="card">
                <h2 className="text-lg font-semibold mb-4">Friends & Friend Requests ({friends.length})</h2>
                {friends.length === 0 ? (
                  <div className="text-center py-8" style={{ color: 'var(--text-muted)' }}>No friends or requests found</div>
                ) : (
                  <table>
                    <thead>
                      <tr>
                        <th>Friend</th>
                        <th>Status</th>
                        <th>Direction</th>
                        <th>Since</th>
                      </tr>
                    </thead>
                    <tbody>
                      {friends.map((f) => (
                        <tr key={f.id} className="cursor-pointer" onClick={() => router.push(`/users/${f.friend_id}`)}>
                          <td>
                            <div className="flex items-center gap-3">
                              <div className="w-8 h-8 rounded-full flex items-center justify-center text-xs font-bold"
                                style={{ background: 'var(--bg-tertiary)', color: 'var(--text-secondary)' }}>
                                {(f.friend_profile?.name?.[0] || f.friend_profile?.username?.[0] || '?')}
                              </div>
                              <div>
                                <div className="font-medium text-sm">{f.friend_profile?.name || '—'}</div>
                                <div className="text-xs" style={{ color: 'var(--text-muted)' }}>
                                  @{f.friend_profile?.username || '—'} · {f.friend_profile?.email || ''}
                                </div>
                              </div>
                            </div>
                          </td>
                          <td>
                            <span className={`badge ${f.status === 'accepted' ? 'badge-success' : f.status === 'pending' ? 'badge-warning' : 'badge-danger'}`}>
                              {f.status}
                            </span>
                          </td>
                          <td className="text-sm" style={{ color: 'var(--text-secondary)' }}>
                            {f.requester_id === userId ? '→ Sent' : '← Received'}
                          </td>
                          <td className="text-xs" style={{ color: 'var(--text-muted)' }}>{formatDate(f.created_at)}</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                )}
              </div>
            )}

            {/* ═══════════════ CHALLENGES TAB ═══════════════ */}
            {tab === 'challenges' && (
              <div className="card">
                <h2 className="text-lg font-semibold mb-4">Challenges ({challenges.length})</h2>
                {challenges.length === 0 ? (
                  <div className="text-center py-8" style={{ color: 'var(--text-muted)' }}>No challenges found</div>
                ) : (
                  <div className="space-y-3">
                    {challenges.map((c, i) => (
                      <div key={i} className="p-4 rounded-lg border" style={{ background: 'var(--bg-tertiary)', borderColor: 'var(--border)' }}>
                        <div className="flex items-center justify-between mb-2">
                          <div>
                            <div className="font-semibold text-sm">{c.challenge?.title || 'Untitled Challenge'}</div>
                            <div className="text-xs" style={{ color: 'var(--text-muted)' }}>
                              {c.challenge?.challenge_type} · {c.challenge?.mode || 'competition'}
                            </div>
                          </div>
                          <span className={`badge ${c.challenge?.status === 'active' ? 'badge-success' : c.challenge?.status === 'completed' ? 'badge-info' : 'badge-neutral'}`}>
                            {c.challenge?.status || c.status}
                          </span>
                        </div>
                        <div className="grid grid-cols-2 sm:grid-cols-4 gap-3 mt-3">
                          <div>
                            <div className="text-xs" style={{ color: 'var(--text-muted)' }}>Progress</div>
                            <div className="font-medium text-sm">{c.total_progress || 0}</div>
                          </div>
                          <div>
                            <div className="text-xs" style={{ color: 'var(--text-muted)' }}>Days Done</div>
                            <div className="font-medium text-sm">{c.days_completed || 0} / {c.challenge?.duration_days || '—'}</div>
                          </div>
                          <div>
                            <div className="text-xs" style={{ color: 'var(--text-muted)' }}>Streak</div>
                            <div className="font-medium text-sm">🔥 {c.current_streak || 0}</div>
                          </div>
                          <div>
                            <div className="text-xs" style={{ color: 'var(--text-muted)' }}>Dates</div>
                            <div className="font-medium text-sm text-xs">
                              {c.challenge?.start_date || '—'} → {c.challenge?.end_date || '—'}
                            </div>
                          </div>
                        </div>
                        {c.challenge?.description && (
                          <div className="mt-2 text-xs" style={{ color: 'var(--text-secondary)' }}>{c.challenge.description}</div>
                        )}
                        {/* Challenge Members */}
                        {c.members && c.members.length > 0 && (
                          <div className="mt-3 pt-3" style={{ borderTop: '1px solid var(--border)' }}>
                            <div className="text-xs font-medium mb-2" style={{ color: 'var(--text-muted)' }}>
                              Members ({c.members.length + 1})
                            </div>
                            <div className="flex flex-wrap gap-2">
                              {c.members.map((m: AnyRecord, mi: number) => (
                                <button
                                  key={mi}
                                  onClick={() => router.push(`/users/${m.user_id}`)}
                                  className="flex items-center gap-2 px-2.5 py-1.5 rounded-lg text-xs transition-colors"
                                  style={{ background: 'var(--bg-primary)', border: '1px solid var(--border)' }}
                                  onMouseEnter={(e) => { e.currentTarget.style.borderColor = 'var(--accent)' }}
                                  onMouseLeave={(e) => { e.currentTarget.style.borderColor = 'var(--border)' }}
                                >
                                  <div
                                    className="w-5 h-5 rounded-full flex items-center justify-center text-[10px] font-bold shrink-0"
                                    style={{
                                      background: m.profile?.profile_photo_url ? 'transparent' : 'var(--bg-tertiary)',
                                      color: 'var(--text-secondary)',
                                      backgroundImage: m.profile?.profile_photo_url ? `url(${m.profile.profile_photo_url})` : undefined,
                                      backgroundSize: 'cover',
                                    }}
                                  >
                                    {!m.profile?.profile_photo_url && (m.profile?.name?.[0] || m.profile?.username?.[0] || '?')}
                                  </div>
                                  <span className="font-medium" style={{ color: 'var(--text-primary)' }}>
                                    {m.profile?.name || m.profile?.username || 'Unknown'}
                                  </span>
                                  <span style={{ color: 'var(--text-muted)' }}>
                                    · {m.total_progress || 0} pts
                                  </span>
                                </button>
                              ))}
                            </div>
                          </div>
                        )}
                      </div>
                    ))}
                  </div>
                )}
              </div>
            )}

            {/* ═══════════════ WORKOUTS TAB ═══════════════ */}
            {tab === 'workouts' && (
              <div className="space-y-6">
                {/* Strength Workouts */}
                <div className="card">
                  <h2 className="text-lg font-semibold mb-4">Strength Workouts ({workouts.length})</h2>
                  {workouts.length === 0 ? (
                    <div className="text-center py-8" style={{ color: 'var(--text-muted)' }}>No workouts found</div>
                  ) : (
                    <table>
                      <thead>
                        <tr>
                          <th>Workout</th>
                          <th>Date</th>
                          <th>Duration</th>
                          <th>XP</th>
                          <th>Program</th>
                        </tr>
                      </thead>
                      <tbody>
                        {workouts.map((w) => (
                          <tr key={w.id}>
                            <td className="font-medium text-sm">{w.name || 'Workout'}</td>
                            <td className="text-sm" style={{ color: 'var(--text-secondary)' }}>{formatDate(w.date)}</td>
                            <td className="text-sm" style={{ color: 'var(--text-secondary)' }}>{w.duration_seconds ? formatDuration(w.duration_seconds) : '—'}</td>
                            <td className="text-sm" style={{ color: 'var(--accent)' }}>+{w.xp_earned || 0} XP</td>
                            <td className="text-xs" style={{ color: 'var(--text-muted)' }}>
                              {w.program_id ? `Day ${w.program_day}` : 'Custom'}
                            </td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  )}
                </div>

                {/* Cardio Workouts */}
                <div className="card">
                  <h2 className="text-lg font-semibold mb-4">Cardio Workouts ({cardio.length})</h2>
                  {cardio.length === 0 ? (
                    <div className="text-center py-8" style={{ color: 'var(--text-muted)' }}>No cardio workouts found</div>
                  ) : (
                    <table>
                      <thead>
                        <tr>
                          <th>Activity</th>
                          <th>Date</th>
                          <th>Duration</th>
                          <th>Distance</th>
                          <th>Calories</th>
                          <th>Source</th>
                        </tr>
                      </thead>
                      <tbody>
                        {cardio.map((c) => (
                          <tr key={c.id}>
                            <td className="font-medium text-sm">{c.activity_type} {c.workout_name ? `(${c.workout_name})` : ''}</td>
                            <td className="text-sm" style={{ color: 'var(--text-secondary)' }}>{formatDate(c.started_at)}</td>
                            <td className="text-sm" style={{ color: 'var(--text-secondary)' }}>{c.duration_seconds ? formatDuration(c.duration_seconds) : '—'}</td>
                            <td className="text-sm" style={{ color: 'var(--text-secondary)' }}>
                              {c.distance_meters ? `${(c.distance_meters / 1000).toFixed(2)} km` : '—'}
                            </td>
                            <td className="text-sm" style={{ color: 'var(--warning)' }}>{c.calories_burned ? `${Math.round(c.calories_burned)} cal` : '—'}</td>
                            <td><span className="badge badge-neutral">{c.source || 'manual'}</span></td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  )}
                </div>
              </div>
            )}

            {/* ═══════════════ HEALTH TAB ═══════════════ */}
            {tab === 'health' && (
              <div className="space-y-6">
                {/* Streak Tracking */}
                <div className="card">
                  <h2 className="text-lg font-semibold mb-4">Streak Tracking</h2>
                  {streaks.length === 0 ? (
                    <div className="text-center py-4" style={{ color: 'var(--text-muted)' }}>No streak data</div>
                  ) : (
                    <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3">
                      {streaks.map((s, i) => (
                        <div key={i} className="p-4 rounded-lg" style={{ background: 'var(--bg-tertiary)' }}>
                          <div className="text-xs font-semibold uppercase" style={{ color: 'var(--text-muted)' }}>{s.streak_type}</div>
                          <div className="flex items-baseline gap-2 mt-1">
                            <span className="text-2xl font-bold" style={{ color: 'var(--warning)' }}>🔥 {s.current_streak}</span>
                            <span className="text-xs" style={{ color: 'var(--text-muted)' }}>current</span>
                          </div>
                          <div className="text-xs mt-1" style={{ color: 'var(--text-secondary)' }}>
                            Longest: {s.longest_streak} · Total days: {s.total_days_achieved}
                          </div>
                        </div>
                      ))}
                    </div>
                  )}
                </div>

                {/* Weight Log */}
                <div className="card">
                  <h2 className="text-lg font-semibold mb-4">Weight Log (Last 30 entries)</h2>
                  {weightLogs.length === 0 ? (
                    <div className="text-center py-4" style={{ color: 'var(--text-muted)' }}>No weight logs</div>
                  ) : (
                    <table>
                      <thead><tr><th>Date</th><th>Weight (kg)</th><th>Weight (lbs)</th></tr></thead>
                      <tbody>
                        {weightLogs.map((w, i) => (
                          <tr key={i}>
                            <td className="text-sm">{w.date || formatDate(w.created_at)}</td>
                            <td className="text-sm">{w.weight_kg ?? '—'}</td>
                            <td className="text-sm">{w.weight_lbs ?? '—'}</td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  )}
                </div>

                {/* Steps */}
                <div className="card">
                  <h2 className="text-lg font-semibold mb-4">Step Tracking (Last 30 days)</h2>
                  {steps.length === 0 ? (
                    <div className="text-center py-4" style={{ color: 'var(--text-muted)' }}>No step data</div>
                  ) : (
                    <table>
                      <thead><tr><th>Date</th><th>Steps</th><th>Goal</th><th>Status</th></tr></thead>
                      <tbody>
                        {steps.map((s, i) => (
                          <tr key={i}>
                            <td className="text-sm">{s.date}</td>
                            <td className="text-sm font-medium">{(s.steps || 0).toLocaleString()}</td>
                            <td className="text-sm" style={{ color: 'var(--text-secondary)' }}>{(s.goal || 0).toLocaleString()}</td>
                            <td>
                              <span className={`badge ${s.steps >= s.goal ? 'badge-success' : 'badge-neutral'}`}>
                                {s.steps >= s.goal ? 'Goal Met' : 'In Progress'}
                              </span>
                            </td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  )}
                </div>

                {/* Hydration */}
                <div className="card">
                  <h2 className="text-lg font-semibold mb-4">Hydration Log (Last 30 days)</h2>
                  {hydration.length === 0 ? (
                    <div className="text-center py-4" style={{ color: 'var(--text-muted)' }}>No hydration data</div>
                  ) : (
                    <table>
                      <thead><tr><th>Date</th><th>Amount (ml)</th><th>Goal (ml)</th></tr></thead>
                      <tbody>
                        {hydration.map((h, i) => (
                          <tr key={i}>
                            <td className="text-sm">{h.date}</td>
                            <td className="text-sm font-medium">{h.amount_ml ?? h.total_ml ?? '—'}</td>
                            <td className="text-sm" style={{ color: 'var(--text-secondary)' }}>{h.goal_ml ?? '—'}</td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  )}
                </div>

                {/* Recent Meals */}
                <div className="card">
                  <h2 className="text-lg font-semibold mb-4">Recent Meals ({meals.length})</h2>
                  {meals.length === 0 ? (
                    <div className="text-center py-4" style={{ color: 'var(--text-muted)' }}>No meal logs</div>
                  ) : (
                    <table>
                      <thead><tr><th>Date</th><th>Meal</th><th>Food</th><th>Calories</th><th>Protein</th><th>Carbs</th><th>Fat</th></tr></thead>
                      <tbody>
                        {meals.slice(0, 30).map((m, i) => (
                          <tr key={i}>
                            <td className="text-sm">{m.date}</td>
                            <td className="text-sm" style={{ color: 'var(--text-secondary)' }}>{m.meal_type}</td>
                            <td className="font-medium text-sm">{m.food_name}</td>
                            <td className="text-sm">{m.calories}</td>
                            <td className="text-sm">{m.protein}g</td>
                            <td className="text-sm">{m.carbs}g</td>
                            <td className="text-sm">{m.fat}g</td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  )}
                </div>
              </div>
            )}

            {/* ═══════════════ NOTIFICATIONS TAB ═══════════════ */}
            {tab === 'notifications' && (
              <div className="space-y-6">
                {/* Bug Reports */}
                <div className="card">
                  <h2 className="text-lg font-semibold mb-4">Bug Reports ({bugReports.length})</h2>
                  {bugReports.length === 0 ? (
                    <div className="text-center py-4" style={{ color: 'var(--text-muted)' }}>No bug reports</div>
                  ) : (
                    <div className="space-y-3">
                      {bugReports.map((b, i) => (
                        <div key={i} className="p-4 rounded-lg border" style={{ background: 'var(--bg-tertiary)', borderColor: 'var(--border)' }}>
                          <div className="flex items-center justify-between mb-2">
                            <span className="badge badge-danger">{b.category || 'Bug'}</span>
                            <span className="text-xs" style={{ color: 'var(--text-muted)' }}>{formatDate(b.created_at)}</span>
                          </div>
                          <div className="text-sm font-medium mb-1">{b.title || b.subject || 'Untitled'}</div>
                          <div className="text-sm" style={{ color: 'var(--text-secondary)' }}>{b.description || b.body || b.message || '—'}</div>
                          {b.app_version && <div className="text-xs mt-2" style={{ color: 'var(--text-muted)' }}>App Version: {b.app_version}</div>}
                        </div>
                      ))}
                    </div>
                  )}
                </div>

                {/* Notifications */}
                <div className="card">
                  <h2 className="text-lg font-semibold mb-4">App Notifications ({notifications.length})</h2>
                  {notifications.length === 0 ? (
                    <div className="text-center py-4" style={{ color: 'var(--text-muted)' }}>No notifications</div>
                  ) : (
                    <table>
                      <thead><tr><th>Type</th><th>Title</th><th>Body</th><th>Read</th><th>Date</th></tr></thead>
                      <tbody>
                        {notifications.map((n, i) => (
                          <tr key={i}>
                            <td><span className="badge badge-info">{n.type || n.notification_type || '—'}</span></td>
                            <td className="font-medium text-sm">{n.title || '—'}</td>
                            <td className="text-sm" style={{ color: 'var(--text-secondary)', maxWidth: 300, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                              {n.body || n.message || '—'}
                            </td>
                            <td>
                              <span className={`badge ${n.is_read ? 'badge-neutral' : 'badge-warning'}`}>
                                {n.is_read ? 'Read' : 'Unread'}
                              </span>
                            </td>
                            <td className="text-xs" style={{ color: 'var(--text-muted)' }}>{formatDate(n.created_at)}</td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  )}
                </div>
              </div>
            )}

            {/* ═══════ ENGAGEMENT TAB ═══════ */}
            {tab === 'engagement' && (
              <div className="space-y-4">
                {!engagement ? (
                  <div className="card text-center py-8" style={{ color: 'var(--text-muted)' }}>
                    {tabLoading ? 'Loading engagement data...' : 'No engagement data available. The materialized view may not be populated yet.'}
                  </div>
                ) : (
                  <>
                    <div className="card">
                      <div className="flex items-center gap-4 mb-4">
                        <div className="text-center">
                          <div className="text-4xl font-bold" style={{
                            color: engagement.engagement_bucket === 'power_user' ? '#22c55e'
                              : engagement.engagement_bucket === 'engaged' ? '#3b82f6'
                              : engagement.engagement_bucket === 'casual' ? '#f59e0b'
                              : engagement.engagement_bucket === 'at_risk' ? '#f97316' : '#ef4444'
                          }}>
                            {engagement.engagement_score}
                          </div>
                          <div className="text-xs mt-1" style={{ color: 'var(--text-muted)' }}>Score</div>
                        </div>
                        <div>
                          <span className="badge text-sm px-3 py-1" style={{
                            background: engagement.engagement_bucket === 'power_user' ? 'rgba(34,197,94,0.15)'
                              : engagement.engagement_bucket === 'engaged' ? 'rgba(59,130,246,0.15)'
                              : engagement.engagement_bucket === 'casual' ? 'rgba(245,158,11,0.15)'
                              : engagement.engagement_bucket === 'at_risk' ? 'rgba(249,115,22,0.15)' : 'rgba(239,68,68,0.15)',
                            color: engagement.engagement_bucket === 'power_user' ? '#22c55e'
                              : engagement.engagement_bucket === 'engaged' ? '#3b82f6'
                              : engagement.engagement_bucket === 'casual' ? '#f59e0b'
                              : engagement.engagement_bucket === 'at_risk' ? '#f97316' : '#ef4444',
                          }}>
                            {engagement.engagement_bucket?.replace('_', ' ').toUpperCase()}
                          </span>
                        </div>
                      </div>
                      <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
                        <MiniStat label="Workouts (7d)" value={engagement.workouts_7d || 0} />
                        <MiniStat label="Workouts (30d)" value={engagement.workouts_30d || 0} />
                        <MiniStat label="Current Streak" value={engagement.current_streak || 0} />
                        <MiniStat label="Friends" value={engagement.friend_count || 0} />
                        <MiniStat label="Challenges Joined" value={engagement.challenges_joined || 0} />
                        <MiniStat label="Total Workouts" value={engagement.total_workouts || 0} />
                        <MiniStat label="Last Workout" value={engagement.last_workout_date ? new Date(engagement.last_workout_date).toLocaleDateString() : 'Never'} />
                        <MiniStat label="Joined" value={engagement.created_at ? new Date(engagement.created_at).toLocaleDateString() : '—'} />
                      </div>
                    </div>
                  </>
                )}
              </div>
            )}

            {/* ═══════ MODERATION TAB ═══════ */}
            {tab === 'moderation' && (
              <div className="space-y-4">
                {/* Reports */}
                <div className="card">
                  <h2 className="text-lg font-semibold mb-4">Reports ({userReports.length})</h2>
                  {userReports.length === 0 ? (
                    <div className="text-center py-4" style={{ color: 'var(--text-muted)' }}>No reports involving this user</div>
                  ) : (
                    <div className="space-y-3">
                      {userReports.map((r: AnyRecord) => (
                        <div key={r.id} className="p-3 rounded-lg" style={{ background: 'var(--bg-tertiary)' }}>
                          <div className="flex items-center gap-2 mb-1">
                            <span className={`badge ${r.status === 'pending' ? 'badge-warning' : r.status === 'resolved' ? 'badge-success' : 'badge-neutral'}`}>
                              {r.status}
                            </span>
                            <span className="badge badge-info">{r.reason}</span>
                            <span className="text-xs" style={{ color: 'var(--text-muted)' }}>
                              {r.reporter_id === userId ? 'Filed by this user' : 'Against this user'}
                            </span>
                          </div>
                          {r.description && <p className="text-sm mt-1" style={{ color: 'var(--text-secondary)' }}>{r.description}</p>}
                          <div className="text-xs mt-2" style={{ color: 'var(--text-muted)' }}>{formatDate(r.created_at)}</div>
                        </div>
                      ))}
                    </div>
                  )}
                </div>

                {/* Suspensions */}
                <div className="card">
                  <h2 className="text-lg font-semibold mb-4">Suspensions ({userSuspensions.length})</h2>
                  {userSuspensions.length === 0 ? (
                    <div className="text-center py-4" style={{ color: 'var(--text-muted)' }}>No suspension history</div>
                  ) : (
                    <table>
                      <thead><tr><th>Reason</th><th>Suspended By</th><th>Date</th><th>Expires</th><th>Status</th></tr></thead>
                      <tbody>
                        {userSuspensions.map((s: AnyRecord) => {
                          const isActive = !s.lifted_at && (!s.expires_at || new Date(s.expires_at) > new Date())
                          return (
                            <tr key={s.id}>
                              <td className="text-sm">{s.reason}</td>
                              <td className="text-xs" style={{ color: 'var(--text-muted)' }}>{s.suspended_by}</td>
                              <td className="text-xs" style={{ color: 'var(--text-muted)' }}>{formatDate(s.suspended_at)}</td>
                              <td className="text-xs" style={{ color: 'var(--text-muted)' }}>{s.expires_at ? formatDate(s.expires_at) : 'Permanent'}</td>
                              <td>
                                <span className={`badge ${isActive ? 'badge-danger' : s.lifted_at ? 'badge-success' : 'badge-neutral'}`}>
                                  {isActive ? 'Active' : s.lifted_at ? 'Lifted' : 'Expired'}
                                </span>
                              </td>
                            </tr>
                          )
                        })}
                      </tbody>
                    </table>
                  )}
                </div>
              </div>
            )}
          </>
        )}
      </div>
    </AdminShell>
  )
}

// ═══════════════ REUSABLE COMPONENTS ═══════════════

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div className="card">
      <h2 className="text-sm font-semibold uppercase tracking-wide mb-4" style={{ color: 'var(--text-secondary)' }}>{title}</h2>
      {children}
    </div>
  )
}

function EditField({ label, field, value, onChange, type = 'text' }: {
  label: string; field: string; value: unknown; onChange: (f: string, v: unknown) => void; type?: string
}) {
  return (
    <div>
      <label className="block text-xs font-medium mb-1" style={{ color: 'var(--text-muted)' }}>{label}</label>
      <input
        type={type}
        value={String(value ?? '')}
        onChange={(e) => onChange(field, type === 'number' ? (e.target.value ? Number(e.target.value) : null) : e.target.value)}
        className="text-sm"
      />
    </div>
  )
}

function SelectField({ label, field, value, onChange, options }: {
  label: string; field: string; value: unknown; onChange: (f: string, v: unknown) => void
  options: (string | { label: string; value: unknown })[]
}) {
  return (
    <div>
      <label className="block text-xs font-medium mb-1" style={{ color: 'var(--text-muted)' }}>{label}</label>
      <select
        value={String(value ?? '')}
        onChange={(e) => {
          const opt = options.find(o => String(typeof o === 'string' ? o : o.value) === e.target.value)
          onChange(field, typeof opt === 'string' ? opt : opt?.value ?? e.target.value)
        }}
        className="text-sm"
      >
        <option value="">— Select —</option>
        {options.map((o, i) => {
          const val = typeof o === 'string' ? o : String(o.value)
          const label = typeof o === 'string' ? o : o.label
          return <option key={i} value={val}>{label}</option>
        })}
      </select>
    </div>
  )
}

function ReadonlyField({ label, value }: { label: string; value: unknown }) {
  return (
    <div>
      <label className="block text-xs font-medium mb-1" style={{ color: 'var(--text-muted)' }}>{label}</label>
      <div className="text-sm p-2 rounded" style={{ background: 'var(--bg-primary)', color: 'var(--text-secondary)', wordBreak: 'break-all' }}>
        {String(value ?? '—')}
      </div>
    </div>
  )
}

function MiniStat({ label, value }: { label: string; value: string | number }) {
  return (
    <div className="p-3 rounded-lg" style={{ background: 'var(--bg-secondary)', border: '1px solid var(--border)' }}>
      <div className="text-xs" style={{ color: 'var(--text-muted)' }}>{label}</div>
      <div className="font-bold text-sm mt-0.5" style={{ color: 'var(--text-primary)' }}>{value}</div>
    </div>
  )
}
