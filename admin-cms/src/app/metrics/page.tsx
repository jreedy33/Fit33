'use client'

import { useEffect, useState, useCallback } from 'react'
import AdminShell from '@/components/AdminShell'
import { adminApi } from '@/lib/api'
import {
  LineChart, Line, BarChart, Bar, PieChart, Pie, Cell, AreaChart, Area,
  XAxis, YAxis, CartesianGrid, Tooltip, Legend, ResponsiveContainer,
  RadarChart, Radar, PolarGrid, PolarAngleAxis, PolarRadiusAxis,
} from 'recharts'
import type { PieLabelRenderProps } from 'recharts'
import { format, parseISO, startOfWeek, startOfMonth, subDays } from 'date-fns'

// ─── Color palette ───
const BLUE = '#2563eb'
const BLUE_LIGHT = '#3b82f6'
const GREEN = '#22c55e'
const AMBER = '#f59e0b'
const RED = '#ef4444'
const CYAN = '#06b6d4'
const PURPLE = '#8b5cf6'
const PINK = '#ec4899'
const TEAL = '#14b8a6'
const INDIGO = '#6366f1'
const CHART_COLORS = [BLUE, GREEN, AMBER, CYAN, PURPLE, PINK, RED, TEAL, INDIGO, BLUE_LIGHT]

// ─── Types ───
interface Overview {
  total_users: number; new_users_7d: number; new_users_30d: number
  total_workouts: number; workouts_7d: number; workouts_30d: number
  active_users_7d: number; active_users_30d: number
  total_challenges: number; active_challenges: number
  total_friendships: number; total_meals_logged: number
  avg_current_streak: number; avg_longest_streak: number
  avg_workouts_per_user: number; retention_30d: number
}

type TimeRange = '7d' | '30d' | '90d' | 'all'

// ─── Helper: group records by date bucket ───
function groupByDate(
  records: { date?: string; created_at?: string; logged_at?: string; started_at?: string; workout_date?: string }[],
  range: TimeRange,
  dateField = 'date'
): { date: string; count: number }[] {
  const now = new Date()
  const cutoff = range === '7d' ? subDays(now, 7)
    : range === '30d' ? subDays(now, 30)
    : range === '90d' ? subDays(now, 90)
    : null

  const buckets: Record<string, number> = {}

  for (const r of records) {
    const raw = (r as Record<string, unknown>)[dateField] as string | undefined
    if (!raw) continue
    const d = parseISO(raw)
    if (cutoff && d < cutoff) continue

    const key = range === '7d'
      ? format(d, 'EEE MM/dd')
      : range === '30d'
        ? format(d, 'MM/dd')
        : range === '90d'
          ? format(startOfWeek(d), 'MM/dd')
          : format(startOfMonth(d), 'MMM yyyy')

    buckets[key] = (buckets[key] || 0) + 1
  }

  return Object.entries(buckets).map(([date, count]) => ({ date, count }))
}

// ─── Stat card ───
function StatCard({ label, value, sub, color }: { label: string; value: string | number; sub?: string; color?: string }) {
  return (
    <div className="card flex flex-col gap-1">
      <span className="text-xs font-semibold uppercase tracking-wide" style={{ color: 'var(--text-muted)' }}>{label}</span>
      <span className="text-2xl font-bold" style={{ color: color || 'var(--text-primary)' }}>{value}</span>
      {sub && <span className="text-xs" style={{ color: 'var(--text-secondary)' }}>{sub}</span>}
    </div>
  )
}

// ─── Section wrapper ───
function Section({ title, children, id }: { title: string; children: React.ReactNode; id?: string }) {
  return (
    <div id={id} className="space-y-4">
      <h2 className="text-lg font-bold" style={{ color: 'var(--text-primary)' }}>{title}</h2>
      {children}
    </div>
  )
}

// ─── Time range selector ───
function TimeRangeSelector({ value, onChange }: { value: TimeRange; onChange: (v: TimeRange) => void }) {
  const options: { value: TimeRange; label: string }[] = [
    { value: '7d', label: '7 Days' },
    { value: '30d', label: '30 Days' },
    { value: '90d', label: '90 Days' },
    { value: 'all', label: 'All Time' },
  ]
  return (
    <div className="flex gap-1 rounded-lg p-1" style={{ background: 'var(--bg-tertiary)' }}>
      {options.map(o => (
        <button
          key={o.value}
          onClick={() => onChange(o.value)}
          className="px-3 py-1.5 rounded-md text-xs font-medium transition-all"
          style={{
            background: value === o.value ? 'var(--accent)' : 'transparent',
            color: value === o.value ? '#fff' : 'var(--text-secondary)',
          }}
        >
          {o.label}
        </button>
      ))}
    </div>
  )
}

// ─── Custom tooltip ───
const CustomTooltip = ({ active, payload, label }: { active?: boolean; payload?: Array<{ name: string; value: number; color: string }>; label?: string }) => {
  if (!active || !payload) return null
  return (
    <div className="rounded-lg p-3 text-xs shadow-xl" style={{ background: '#1a1a2e', border: '1px solid #2a2a3a' }}>
      <p className="font-semibold mb-1" style={{ color: '#f0f0f5' }}>{label}</p>
      {payload.map((p, i) => (
        <p key={i} style={{ color: p.color }}>{p.name}: <strong>{typeof p.value === 'number' ? p.value.toLocaleString() : p.value}</strong></p>
      ))}
    </div>
  )
}

// ═══════════════════════════════════════════════════
// MAIN PAGE
// ═══════════════════════════════════════════════════
export default function MetricsPage() {
  const [loading, setLoading] = useState(true)
  const [range, setRange] = useState<TimeRange>('30d')
  const [activeSection, setActiveSection] = useState('overview')

  // Data stores
  const [overview, setOverview] = useState<Overview | null>(null)
  const [userGrowth, setUserGrowth] = useState<{ created_at: string }[]>([])
  const [workoutActivity, setWorkoutActivity] = useState<{ date: string; duration_seconds: number; xp_earned: number; user_id: string; name: string }[]>([])
  const [challengeData, setChallengeData] = useState<{ challenges: Array<Record<string, unknown>>; participants: Array<Record<string, unknown>> }>({ challenges: [], participants: [] })
  const [exerciseData, setExerciseData] = useState<Array<Record<string, unknown>>>([])
  const [demographics, setDemographics] = useState<Array<Record<string, unknown>>>([])
  const [nutritionData, setNutritionData] = useState<{ meals: Array<Record<string, unknown>>; food_frequency: Array<Record<string, unknown>> }>({ meals: [], food_frequency: [] })
  const [programData, setProgramData] = useState<{ active_programs: Array<Record<string, unknown>>; program_history: Array<Record<string, unknown>> }>({ active_programs: [], program_history: [] })
  const [socialData, setSocialData] = useState<{ friendships: Array<Record<string, unknown>>; shared_workouts: Array<Record<string, unknown>> }>({ friendships: [], shared_workouts: [] })
  const [healthData, setHealthData] = useState<{ steps: Array<Record<string, unknown>>; hydration: Array<Record<string, unknown>>; cardio: Array<Record<string, unknown>> }>({ steps: [], hydration: [], cardio: [] })
  const [streakData, setStreakData] = useState<{ profiles: Array<Record<string, unknown>>; streak_tracking: Array<Record<string, unknown>> }>({ profiles: [], streak_tracking: [] })

  const loadData = useCallback(async () => {
    setLoading(true)
    try {
      const [ov, ug, wa, ch, ex, dem, nut, prog, soc, health, streaks] = await Promise.all([
        adminApi('metrics_overview'),
        adminApi('metrics_user_growth'),
        adminApi('metrics_workout_activity'),
        adminApi('metrics_challenges'),
        adminApi('metrics_exercises'),
        adminApi('metrics_user_demographics'),
        adminApi('metrics_nutrition'),
        adminApi('metrics_programs'),
        adminApi('metrics_social'),
        adminApi('metrics_health'),
        adminApi('metrics_streaks'),
      ])
      setOverview(ov)
      setUserGrowth(ug.users || [])
      setWorkoutActivity(wa.workouts || [])
      setChallengeData(ch)
      setExerciseData(ex.exercises || [])
      setDemographics(dem.profiles || [])
      setNutritionData(nut)
      setProgramData(prog)
      setSocialData(soc)
      setHealthData(health)
      setStreakData(streaks)
    } catch (e) {
      console.error('Failed to load metrics:', e)
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => { loadData() }, [loadData])

  // ─── Derived data ───

  // User growth chart
  const userGrowthChart = (() => {
    const sorted = [...userGrowth].sort((a, b) => a.created_at.localeCompare(b.created_at))
    const buckets: Record<string, number> = {}
    for (const u of sorted) {
      if (!u.created_at) continue
      const d = parseISO(u.created_at)
      const now = new Date()
      const cutoff = range === '7d' ? subDays(now, 7) : range === '30d' ? subDays(now, 30) : range === '90d' ? subDays(now, 90) : null
      if (cutoff && d < cutoff) continue
      const key = range === '7d' ? format(d, 'EEE') : range === '30d' ? format(d, 'MM/dd') : range === '90d' ? format(startOfWeek(d), 'MM/dd') : format(startOfMonth(d), 'MMM yyyy')
      buckets[key] = (buckets[key] || 0) + 1
    }
    // Cumulative
    let cum = 0
    const cutoff = range === '7d' ? subDays(new Date(), 7) : range === '30d' ? subDays(new Date(), 30) : range === '90d' ? subDays(new Date(), 90) : null
    if (cutoff) {
      cum = sorted.filter(u => parseISO(u.created_at) < cutoff).length
    }
    return Object.entries(buckets).map(([date, count]) => {
      cum += count
      return { date, new_users: count, total_users: cum }
    })
  })()

  // Workout activity chart
  const workoutChart = groupByDate(workoutActivity, range)

  // Workouts by day of week
  const workoutsByDOW = (() => {
    const days = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']
    const counts = new Array(7).fill(0)
    for (const w of workoutActivity) {
      if (!w.date) continue
      const d = parseISO(w.date)
      counts[d.getDay()]++
    }
    return days.map((d, i) => ({ day: d, workouts: counts[i] }))
  })()

  // Unique daily active users from workouts
  const dauChart = (() => {
    const buckets: Record<string, Set<string>> = {}
    const now = new Date()
    const cutoff = range === '7d' ? subDays(now, 7) : range === '30d' ? subDays(now, 30) : range === '90d' ? subDays(now, 90) : null
    for (const w of workoutActivity) {
      if (!w.date) continue
      const d = parseISO(w.date)
      if (cutoff && d < cutoff) continue
      const key = format(d, 'MM/dd')
      if (!buckets[key]) buckets[key] = new Set()
      buckets[key].add(w.user_id)
    }
    return Object.entries(buckets).map(([date, users]) => ({ date, active_users: users.size }))
  })()

  // Fitness goal distribution
  const goalDistribution = (() => {
    const counts: Record<string, number> = {}
    for (const p of demographics) {
      const goal = (p.fitness_goal as string) || 'Not Set'
      counts[goal] = (counts[goal] || 0) + 1
    }
    return Object.entries(counts)
      .map(([name, value]) => ({ name: name.replace(/_/g, ' '), value }))
      .sort((a, b) => b.value - a.value)
  })()

  // Experience level distribution
  const levelDistribution = (() => {
    const counts: Record<string, number> = {}
    for (const p of demographics) {
      const level = (p.experience_level as string) || 'Not Set'
      counts[level] = (counts[level] || 0) + 1
    }
    return Object.entries(counts)
      .map(([name, value]) => ({ name, value }))
      .sort((a, b) => b.value - a.value)
  })()

  // Gender distribution
  const genderDistribution = (() => {
    const counts: Record<string, number> = {}
    for (const p of demographics) {
      const g = (p.gender as string) || 'Not Set'
      counts[g] = (counts[g] || 0) + 1
    }
    return Object.entries(counts).map(([name, value]) => ({ name, value })).sort((a, b) => b.value - a.value)
  })()

  // Workout environment
  const envDistribution = (() => {
    const counts: Record<string, number> = {}
    for (const p of demographics) {
      const env = (p.workout_environment as string) || 'Not Set'
      counts[env] = (counts[env] || 0) + 1
    }
    return Object.entries(counts).map(([name, value]) => ({ name, value })).sort((a, b) => b.value - a.value)
  })()

  // Onboarding completion
  const onboardingRate = (() => {
    const completed = demographics.filter(p => p.has_completed_onboarding === true).length
    const total = demographics.length
    return total > 0 ? Math.round((completed / total) * 100) : 0
  })()

  // Challenge type distribution
  const challengeTypes = (() => {
    const counts: Record<string, number> = {}
    for (const c of challengeData.challenges) {
      const t = (c.challenge_type as string) || 'unknown'
      counts[t] = (counts[t] || 0) + 1
    }
    return Object.entries(counts).map(([name, value]) => ({ name, value })).sort((a, b) => b.value - a.value)
  })()

  // Challenge status breakdown
  const challengeStatus = (() => {
    const counts: Record<string, number> = {}
    for (const c of challengeData.challenges) {
      const s = (c.status as string) || 'unknown'
      counts[s] = (counts[s] || 0) + 1
    }
    return Object.entries(counts).map(([name, value]) => ({ name, value }))
  })()

  // Most popular challenges (by participant count)
  const topChallenges = (() => {
    const challengeParticipantCount: Record<string, number> = {}
    for (const p of challengeData.participants) {
      const id = p.challenge_id as string
      challengeParticipantCount[id] = (challengeParticipantCount[id] || 0) + 1
    }
    return challengeData.challenges
      .map(c => ({
        title: (c.title as string) || 'Untitled',
        type: c.challenge_type as string,
        participants: challengeParticipantCount[c.id as string] || 0,
        status: c.status as string,
      }))
      .sort((a, b) => b.participants - a.participants)
      .slice(0, 10)
  })()

  // Top exercises by frequency
  const topExercises = (() => {
    const counts: Record<string, number> = {}
    for (const e of exerciseData) {
      const name = e.exercise_name as string
      if (!name) continue
      counts[name] = (counts[name] || 0) + 1
    }
    return Object.entries(counts)
      .map(([name, count]) => ({ name, count }))
      .sort((a, b) => b.count - a.count)
      .slice(0, 15)
  })()

  // Top exercises by volume
  const topExercisesByVolume = (() => {
    const volumes: Record<string, number> = {}
    for (const e of exerciseData) {
      const name = e.exercise_name as string
      if (!name) continue
      volumes[name] = (volumes[name] || 0) + (e.total_volume as number || 0)
    }
    return Object.entries(volumes)
      .map(([name, volume]) => ({ name, volume: Math.round(volume) }))
      .sort((a, b) => b.volume - a.volume)
      .slice(0, 15)
  })()

  // Exercise category distribution
  const exerciseCategories = (() => {
    const counts: Record<string, number> = {}
    for (const e of exerciseData) {
      const cat = (e.exercise_category as string) || 'Other'
      counts[cat] = (counts[cat] || 0) + 1
    }
    return Object.entries(counts).map(([name, value]) => ({ name, value })).sort((a, b) => b.value - a.value)
  })()

  // Top logged foods
  const topFoods = (() => {
    const counts: Record<string, number> = {}
    for (const m of nutritionData.meals) {
      const name = m.food_name as string
      if (!name) continue
      const clean = name.trim().substring(0, 40)
      counts[clean] = (counts[clean] || 0) + 1
    }
    return Object.entries(counts)
      .map(([name, count]) => ({ name, count }))
      .sort((a, b) => b.count - a.count)
      .slice(0, 15)
  })()

  // Meals by type (breakfast, lunch, dinner, snacks)
  const mealTypeDistribution = (() => {
    const counts: Record<string, number> = {}
    for (const m of nutritionData.meals) {
      const t = (m.meal_type as string) || 'Other'
      counts[t] = (counts[t] || 0) + 1
    }
    return Object.entries(counts).map(([name, value]) => ({ name: name.charAt(0).toUpperCase() + name.slice(1), value })).sort((a, b) => b.value - a.value)
  })()

  // Average macros per meal
  const avgMacros = (() => {
    if (nutritionData.meals.length === 0) return { calories: 0, protein: 0, carbs: 0, fat: 0 }
    const sum = { calories: 0, protein: 0, carbs: 0, fat: 0 }
    let count = 0
    for (const m of nutritionData.meals) {
      if (m.calories || m.protein) {
        sum.calories += (m.calories as number) || 0
        sum.protein += (m.protein as number) || 0
        sum.carbs += (m.carbs as number) || 0
        sum.fat += (m.fat as number) || 0
        count++
      }
    }
    if (count === 0) return sum
    return {
      calories: Math.round(sum.calories / count),
      protein: Math.round(sum.protein / count),
      carbs: Math.round(sum.carbs / count),
      fat: Math.round(sum.fat / count),
    }
  })()

  // Program completion stats
  const programStats = (() => {
    const nameCount: Record<string, number> = {}
    const nameCompletion: Record<string, number[]> = {}
    for (const p of programData.program_history) {
      const name = (p.program_name as string) || 'Unknown'
      nameCount[name] = (nameCount[name] || 0) + 1
      if (!nameCompletion[name]) nameCompletion[name] = []
      nameCompletion[name].push((p.completion_percentage as number) || 0)
    }
    return Object.entries(nameCount)
      .map(([name, count]) => ({
        name: name.length > 30 ? name.slice(0, 30) + '…' : name,
        users: count,
        avg_completion: Math.round(nameCompletion[name].reduce((a, b) => a + b, 0) / nameCompletion[name].length),
      }))
      .sort((a, b) => b.users - a.users)
      .slice(0, 10)
  })()

  // Friendship growth
  const friendshipGrowth = groupByDate(
    socialData.friendships.map(f => ({ date: f.created_at as string })),
    range,
    'date'
  )

  // Streak distribution
  const streakDistribution = (() => {
    const brackets = [
      { label: '0', min: 0, max: 0 },
      { label: '1-3', min: 1, max: 3 },
      { label: '4-7', min: 4, max: 7 },
      { label: '8-14', min: 8, max: 14 },
      { label: '15-30', min: 15, max: 30 },
      { label: '30+', min: 31, max: 99999 },
    ]
    return brackets.map(b => ({
      range: b.label,
      count: streakData.profiles.filter(p => {
        const s = (p.current_streak as number) || 0
        return s >= b.min && s <= b.max
      }).length,
    }))
  })()

  // Top streak holders
  const topStreakers = streakData.profiles
    .filter(p => (p.current_streak as number) > 0)
    .sort((a, b) => (b.current_streak as number) - (a.current_streak as number))
    .slice(0, 10)

  // XP distribution
  const xpDistribution = (() => {
    const brackets = [
      { label: '0', min: 0, max: 0 },
      { label: '1-100', min: 1, max: 100 },
      { label: '101-500', min: 101, max: 500 },
      { label: '501-1K', min: 501, max: 1000 },
      { label: '1K-5K', min: 1001, max: 5000 },
      { label: '5K+', min: 5001, max: 9999999 },
    ]
    return brackets.map(b => ({
      range: b.label,
      count: demographics.filter(p => {
        const x = (p.xp as number) || 0
        return x >= b.min && x <= b.max
      }).length,
    }))
  })()

  // Average steps per day
  const avgSteps = (() => {
    if (healthData.steps.length === 0) return 0
    const total = healthData.steps.reduce((a, s) => a + ((s.steps as number) || 0), 0)
    return Math.round(total / healthData.steps.length)
  })()

  // Cardio activity types
  const cardioTypes = (() => {
    const counts: Record<string, number> = {}
    for (const c of healthData.cardio) {
      const t = (c.activity_type as string) || 'Other'
      counts[t] = (counts[t] || 0) + 1
    }
    return Object.entries(counts).map(([name, value]) => ({ name, value })).sort((a, b) => b.value - a.value)
  })()

  // ─── Navigation sections ───
  const sections = [
    { id: 'overview', label: 'Overview', icon: '📊' },
    { id: 'growth', label: 'User Growth', icon: '📈' },
    { id: 'activity', label: 'Workout Activity', icon: '🏋️' },
    { id: 'retention', label: 'Retention & DAU', icon: '🔄' },
    { id: 'demographics', label: 'Demographics', icon: '👥' },
    { id: 'challenges', label: 'Challenges', icon: '⚔️' },
    { id: 'exercises', label: 'Top Exercises', icon: '💪' },
    { id: 'nutrition', label: 'Nutrition', icon: '🍎' },
    { id: 'programs', label: 'Programs', icon: '📋' },
    { id: 'social', label: 'Social', icon: '🤝' },
    { id: 'streaks', label: 'Streaks & XP', icon: '🔥' },
    { id: 'health', label: 'Health Data', icon: '❤️' },
  ]

  if (loading) {
    return (
      <AdminShell>
        <div className="flex items-center justify-center min-h-screen">
          <div className="text-center space-y-4">
            <div className="spinner mx-auto" style={{ width: 40, height: 40 }} />
            <p style={{ color: 'var(--text-secondary)' }}>Loading metrics…</p>
          </div>
        </div>
      </AdminShell>
    )
  }

  return (
    <AdminShell>
      <div className="flex">
        {/* Sticky section nav */}
        <div className="hidden lg:block w-48 shrink-0 border-r sticky top-0 h-screen overflow-y-auto py-4 px-2" style={{ borderColor: 'var(--border)', background: 'var(--bg-primary)' }}>
          {sections.map(s => (
            <button
              key={s.id}
              onClick={() => {
                setActiveSection(s.id)
                document.getElementById(`section-${s.id}`)?.scrollIntoView({ behavior: 'smooth', block: 'start' })
              }}
              className="flex items-center gap-2 w-full px-3 py-2 rounded-lg text-xs font-medium text-left"
              style={{
                background: activeSection === s.id ? 'rgba(37, 99, 235, 0.12)' : 'transparent',
                color: activeSection === s.id ? BLUE : 'var(--text-secondary)',
              }}
            >
              <span>{s.icon}</span> {s.label}
            </button>
          ))}
        </div>

        {/* Main content */}
        <div className="flex-1 p-6 lg:p-8 space-y-10 max-w-[1400px]">
          {/* Header */}
          <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
            <div>
              <h1 className="text-2xl font-bold" style={{ color: 'var(--text-primary)' }}>Metrics & Analytics</h1>
              <p className="text-sm mt-1" style={{ color: 'var(--text-secondary)' }}>Comprehensive in-app trends across all users</p>
            </div>
            <div className="flex items-center gap-3">
              <TimeRangeSelector value={range} onChange={setRange} />
              <button onClick={loadData} className="btn btn-ghost text-xs">↻ Refresh</button>
            </div>
          </div>

          {/* ═══ OVERVIEW ═══ */}
          <Section title="📊 Overview" id="section-overview">
            {overview && (
              <div className="grid grid-cols-2 md:grid-cols-4 lg:grid-cols-4 gap-3">
                <StatCard label="Total Users" value={overview.total_users.toLocaleString()} sub={`+${overview.new_users_7d} this week`} color={BLUE} />
                <StatCard label="Active Users (7d)" value={overview.active_users_7d} sub={`${overview.active_users_30d} in 30d`} color={GREEN} />
                <StatCard label="Total Workouts" value={overview.total_workouts.toLocaleString()} sub={`${overview.workouts_7d} this week`} color={CYAN} />
                <StatCard label="30-Day Retention" value={`${overview.retention_30d}%`} sub="Users active after 30d" color={overview.retention_30d > 50 ? GREEN : AMBER} />
                <StatCard label="Avg Workouts/User" value={overview.avg_workouts_per_user} color={PURPLE} />
                <StatCard label="Avg Current Streak" value={overview.avg_current_streak} sub={`Longest avg: ${overview.avg_longest_streak}`} color={AMBER} />
                <StatCard label="Active Challenges" value={overview.active_challenges} sub={`${overview.total_challenges} total`} color={RED} />
                <StatCard label="Total Friendships" value={overview.total_friendships.toLocaleString()} color={PINK} />
                <StatCard label="New Users (30d)" value={overview.new_users_30d} color={BLUE_LIGHT} />
                <StatCard label="Workouts (30d)" value={overview.workouts_30d.toLocaleString()} color={TEAL} />
                <StatCard label="Meals Logged" value={overview.total_meals_logged.toLocaleString()} color={INDIGO} />
                <StatCard label="Onboarding Rate" value={`${onboardingRate}%`} sub="Completed onboarding" color={onboardingRate > 70 ? GREEN : AMBER} />
              </div>
            )}
          </Section>

          {/* ═══ USER GROWTH ═══ */}
          <Section title="📈 User Growth" id="section-growth">
            <div className="card">
              <div className="flex items-center justify-between mb-4">
                <span className="text-sm font-semibold" style={{ color: 'var(--text-primary)' }}>New Signups & Total Users</span>
              </div>
              <ResponsiveContainer width="100%" height={320}>
                <AreaChart data={userGrowthChart}>
                  <CartesianGrid strokeDasharray="3 3" stroke="#2a2a3a" />
                  <XAxis dataKey="date" tick={{ fontSize: 11, fill: '#8888aa' }} />
                  <YAxis tick={{ fontSize: 11, fill: '#8888aa' }} />
                  <Tooltip content={<CustomTooltip />} />
                  <Legend />
                  <Area type="monotone" dataKey="total_users" name="Total Users" stroke={BLUE} fill={BLUE} fillOpacity={0.15} strokeWidth={2} />
                  <Area type="monotone" dataKey="new_users" name="New Users" stroke={GREEN} fill={GREEN} fillOpacity={0.2} strokeWidth={2} />
                </AreaChart>
              </ResponsiveContainer>
            </div>
          </Section>

          {/* ═══ WORKOUT ACTIVITY ═══ */}
          <Section title="🏋️ Workout Activity" id="section-activity">
            <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
              <div className="card">
                <span className="text-sm font-semibold block mb-4" style={{ color: 'var(--text-primary)' }}>Workouts Over Time</span>
                <ResponsiveContainer width="100%" height={280}>
                  <BarChart data={workoutChart}>
                    <CartesianGrid strokeDasharray="3 3" stroke="#2a2a3a" />
                    <XAxis dataKey="date" tick={{ fontSize: 10, fill: '#8888aa' }} />
                    <YAxis tick={{ fontSize: 11, fill: '#8888aa' }} />
                    <Tooltip content={<CustomTooltip />} />
                    <Bar dataKey="count" name="Workouts" fill={BLUE} radius={[4, 4, 0, 0]} />
                  </BarChart>
                </ResponsiveContainer>
              </div>
              <div className="card">
                <span className="text-sm font-semibold block mb-4" style={{ color: 'var(--text-primary)' }}>Workouts by Day of Week</span>
                <ResponsiveContainer width="100%" height={280}>
                  <BarChart data={workoutsByDOW}>
                    <CartesianGrid strokeDasharray="3 3" stroke="#2a2a3a" />
                    <XAxis dataKey="day" tick={{ fontSize: 11, fill: '#8888aa' }} />
                    <YAxis tick={{ fontSize: 11, fill: '#8888aa' }} />
                    <Tooltip content={<CustomTooltip />} />
                    <Bar dataKey="workouts" name="Workouts" fill={CYAN} radius={[4, 4, 0, 0]} />
                  </BarChart>
                </ResponsiveContainer>
              </div>
            </div>
          </Section>

          {/* ═══ RETENTION & DAU ═══ */}
          <Section title="🔄 Retention & Daily Active Users" id="section-retention">
            <div className="card">
              <span className="text-sm font-semibold block mb-4" style={{ color: 'var(--text-primary)' }}>Daily Active Users (unique users who completed a workout)</span>
              <ResponsiveContainer width="100%" height={300}>
                <LineChart data={dauChart}>
                  <CartesianGrid strokeDasharray="3 3" stroke="#2a2a3a" />
                  <XAxis dataKey="date" tick={{ fontSize: 10, fill: '#8888aa' }} />
                  <YAxis tick={{ fontSize: 11, fill: '#8888aa' }} />
                  <Tooltip content={<CustomTooltip />} />
                  <Line type="monotone" dataKey="active_users" name="Active Users" stroke={GREEN} strokeWidth={2} dot={{ r: 3, fill: GREEN }} />
                </LineChart>
              </ResponsiveContainer>
            </div>
          </Section>

          {/* ═══ DEMOGRAPHICS ═══ */}
          <Section title="👥 User Demographics" id="section-demographics">
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              {/* Fitness goals */}
              <div className="card">
                <span className="text-sm font-semibold block mb-4" style={{ color: 'var(--text-primary)' }}>Fitness Goals</span>
                <ResponsiveContainer width="100%" height={280}>
                  <PieChart>
                    <Pie data={goalDistribution} dataKey="value" nameKey="name" cx="50%" cy="50%" outerRadius={100} label={(props: PieLabelRenderProps) => `${props.name || ''} (${(((props.percent as number) || 0) * 100).toFixed(0)}%)`}>
                      {goalDistribution.map((_, i) => <Cell key={i} fill={CHART_COLORS[i % CHART_COLORS.length]} />)}
                    </Pie>
                    <Tooltip />
                  </PieChart>
                </ResponsiveContainer>
              </div>
              {/* Experience level */}
              <div className="card">
                <span className="text-sm font-semibold block mb-4" style={{ color: 'var(--text-primary)' }}>Experience Level</span>
                <ResponsiveContainer width="100%" height={280}>
                  <BarChart data={levelDistribution} layout="vertical">
                    <CartesianGrid strokeDasharray="3 3" stroke="#2a2a3a" />
                    <XAxis type="number" tick={{ fontSize: 11, fill: '#8888aa' }} />
                    <YAxis dataKey="name" type="category" tick={{ fontSize: 11, fill: '#8888aa' }} width={100} />
                    <Tooltip content={<CustomTooltip />} />
                    <Bar dataKey="value" name="Users" fill={PURPLE} radius={[0, 4, 4, 0]} />
                  </BarChart>
                </ResponsiveContainer>
              </div>
              {/* Gender */}
              <div className="card">
                <span className="text-sm font-semibold block mb-4" style={{ color: 'var(--text-primary)' }}>Gender Distribution</span>
                <ResponsiveContainer width="100%" height={250}>
                  <PieChart>
                    <Pie data={genderDistribution} dataKey="value" nameKey="name" cx="50%" cy="50%" outerRadius={85} label={(props: PieLabelRenderProps) => `${props.name || ''} (${(((props.percent as number) || 0) * 100).toFixed(0)}%)`}>
                      {genderDistribution.map((_, i) => <Cell key={i} fill={CHART_COLORS[i % CHART_COLORS.length]} />)}
                    </Pie>
                    <Tooltip />
                  </PieChart>
                </ResponsiveContainer>
              </div>
              {/* Workout environment */}
              <div className="card">
                <span className="text-sm font-semibold block mb-4" style={{ color: 'var(--text-primary)' }}>Workout Environment</span>
                <ResponsiveContainer width="100%" height={250}>
                  <PieChart>
                    <Pie data={envDistribution} dataKey="value" nameKey="name" cx="50%" cy="50%" outerRadius={85} label={(props: PieLabelRenderProps) => `${props.name || ''} (${(((props.percent as number) || 0) * 100).toFixed(0)}%)`}>
                      {envDistribution.map((_, i) => <Cell key={i} fill={CHART_COLORS[i % CHART_COLORS.length]} />)}
                    </Pie>
                    <Tooltip />
                  </PieChart>
                </ResponsiveContainer>
              </div>
            </div>
          </Section>

          {/* ═══ CHALLENGES ═══ */}
          <Section title="⚔️ Challenge Analytics" id="section-challenges">
            <div className="grid grid-cols-2 md:grid-cols-4 gap-3 mb-4">
              <StatCard label="Total Challenges" value={challengeData.challenges.length} color={RED} />
              <StatCard label="Active Now" value={challengeData.challenges.filter(c => c.status === 'active').length} color={GREEN} />
              <StatCard label="Total Participations" value={challengeData.participants.length} color={BLUE} />
              <StatCard label="Avg Participants" value={challengeData.challenges.length > 0 ? Math.round(challengeData.participants.length / challengeData.challenges.length * 10) / 10 : 0} color={AMBER} />
            </div>
            <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
              {/* Challenge types */}
              <div className="card">
                <span className="text-sm font-semibold block mb-4" style={{ color: 'var(--text-primary)' }}>Challenge Types</span>
                <ResponsiveContainer width="100%" height={280}>
                  <PieChart>
                    <Pie data={challengeTypes} dataKey="value" nameKey="name" cx="50%" cy="50%" outerRadius={100} label={(props: PieLabelRenderProps) => `${props.name || ''} (${(((props.percent as number) || 0) * 100).toFixed(0)}%)`}>
                      {challengeTypes.map((_, i) => <Cell key={i} fill={CHART_COLORS[i % CHART_COLORS.length]} />)}
                    </Pie>
                    <Tooltip />
                  </PieChart>
                </ResponsiveContainer>
              </div>
              {/* Challenge status */}
              <div className="card">
                <span className="text-sm font-semibold block mb-4" style={{ color: 'var(--text-primary)' }}>Challenge Status Breakdown</span>
                <ResponsiveContainer width="100%" height={280}>
                  <BarChart data={challengeStatus}>
                    <CartesianGrid strokeDasharray="3 3" stroke="#2a2a3a" />
                    <XAxis dataKey="name" tick={{ fontSize: 11, fill: '#8888aa' }} />
                    <YAxis tick={{ fontSize: 11, fill: '#8888aa' }} />
                    <Tooltip content={<CustomTooltip />} />
                    <Bar dataKey="value" name="Challenges" fill={AMBER} radius={[4, 4, 0, 0]} />
                  </BarChart>
                </ResponsiveContainer>
              </div>
            </div>
            {/* Top challenges table */}
            <div className="card">
              <span className="text-sm font-semibold block mb-4" style={{ color: 'var(--text-primary)' }}>Top Challenges by Participation</span>
              <table>
                <thead>
                  <tr>
                    <th>#</th>
                    <th>Challenge</th>
                    <th>Type</th>
                    <th>Participants</th>
                    <th>Status</th>
                  </tr>
                </thead>
                <tbody>
                  {topChallenges.map((c, i) => (
                    <tr key={i}>
                      <td style={{ color: 'var(--text-muted)' }}>{i + 1}</td>
                      <td className="font-medium" style={{ color: 'var(--text-primary)' }}>{c.title}</td>
                      <td><span className="badge badge-info">{c.type}</span></td>
                      <td className="font-semibold" style={{ color: BLUE }}>{c.participants}</td>
                      <td><span className={`badge ${c.status === 'active' ? 'badge-success' : c.status === 'completed' ? 'badge-neutral' : 'badge-warning'}`}>{c.status}</span></td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </Section>

          {/* ═══ TOP EXERCISES ═══ */}
          <Section title="💪 Exercise Analytics" id="section-exercises">
            <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
              <div className="card">
                <span className="text-sm font-semibold block mb-4" style={{ color: 'var(--text-primary)' }}>Most Performed Exercises</span>
                <ResponsiveContainer width="100%" height={400}>
                  <BarChart data={topExercises} layout="vertical">
                    <CartesianGrid strokeDasharray="3 3" stroke="#2a2a3a" />
                    <XAxis type="number" tick={{ fontSize: 11, fill: '#8888aa' }} />
                    <YAxis dataKey="name" type="category" tick={{ fontSize: 10, fill: '#8888aa' }} width={140} />
                    <Tooltip content={<CustomTooltip />} />
                    <Bar dataKey="count" name="Times Performed" fill={BLUE} radius={[0, 4, 4, 0]} />
                  </BarChart>
                </ResponsiveContainer>
              </div>
              <div className="card">
                <span className="text-sm font-semibold block mb-4" style={{ color: 'var(--text-primary)' }}>Top Exercises by Volume (lbs)</span>
                <ResponsiveContainer width="100%" height={400}>
                  <BarChart data={topExercisesByVolume} layout="vertical">
                    <CartesianGrid strokeDasharray="3 3" stroke="#2a2a3a" />
                    <XAxis type="number" tick={{ fontSize: 11, fill: '#8888aa' }} tickFormatter={(v) => v >= 1000 ? `${(v / 1000).toFixed(0)}K` : v} />
                    <YAxis dataKey="name" type="category" tick={{ fontSize: 10, fill: '#8888aa' }} width={140} />
                    <Tooltip content={<CustomTooltip />} />
                    <Bar dataKey="volume" name="Total Volume" fill={CYAN} radius={[0, 4, 4, 0]} />
                  </BarChart>
                </ResponsiveContainer>
              </div>
            </div>
            {/* Exercise categories */}
            <div className="card">
              <span className="text-sm font-semibold block mb-4" style={{ color: 'var(--text-primary)' }}>Exercise Categories (muscle group distribution)</span>
              <ResponsiveContainer width="100%" height={300}>
                <RadarChart cx="50%" cy="50%" outerRadius="80%" data={exerciseCategories.slice(0, 8)}>
                  <PolarGrid stroke="#2a2a3a" />
                  <PolarAngleAxis dataKey="name" tick={{ fontSize: 10, fill: '#8888aa' }} />
                  <PolarRadiusAxis tick={{ fontSize: 10, fill: '#555' }} />
                  <Radar name="Count" dataKey="value" stroke={BLUE} fill={BLUE} fillOpacity={0.3} />
                  <Tooltip />
                </RadarChart>
              </ResponsiveContainer>
            </div>
          </Section>

          {/* ═══ NUTRITION ═══ */}
          <Section title="🍎 Nutrition Analytics" id="section-nutrition">
            <div className="grid grid-cols-2 md:grid-cols-4 gap-3 mb-4">
              <StatCard label="Total Meals Logged" value={nutritionData.meals.length.toLocaleString()} color={GREEN} />
              <StatCard label="Avg Calories/Meal" value={avgMacros.calories} color={AMBER} />
              <StatCard label="Avg Protein/Meal" value={`${avgMacros.protein}g`} color={RED} />
              <StatCard label="Avg Carbs/Meal" value={`${avgMacros.carbs}g`} color={BLUE} />
            </div>
            <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
              <div className="card">
                <span className="text-sm font-semibold block mb-4" style={{ color: 'var(--text-primary)' }}>Most Logged Foods</span>
                <ResponsiveContainer width="100%" height={400}>
                  <BarChart data={topFoods} layout="vertical">
                    <CartesianGrid strokeDasharray="3 3" stroke="#2a2a3a" />
                    <XAxis type="number" tick={{ fontSize: 11, fill: '#8888aa' }} />
                    <YAxis dataKey="name" type="category" tick={{ fontSize: 10, fill: '#8888aa' }} width={150} />
                    <Tooltip content={<CustomTooltip />} />
                    <Bar dataKey="count" name="Times Logged" fill={GREEN} radius={[0, 4, 4, 0]} />
                  </BarChart>
                </ResponsiveContainer>
              </div>
              <div className="card">
                <span className="text-sm font-semibold block mb-4" style={{ color: 'var(--text-primary)' }}>Meal Type Distribution</span>
                <ResponsiveContainer width="100%" height={280}>
                  <PieChart>
                    <Pie data={mealTypeDistribution} dataKey="value" nameKey="name" cx="50%" cy="50%" outerRadius={100} label={(props: PieLabelRenderProps) => `${props.name || ''} (${(((props.percent as number) || 0) * 100).toFixed(0)}%)`}>
                      {mealTypeDistribution.map((_, i) => <Cell key={i} fill={CHART_COLORS[i % CHART_COLORS.length]} />)}
                    </Pie>
                    <Tooltip />
                  </PieChart>
                </ResponsiveContainer>
                {/* Avg macros radar */}
                <span className="text-sm font-semibold block mb-3 mt-4" style={{ color: 'var(--text-primary)' }}>Average Macro Split per Meal</span>
                <ResponsiveContainer width="100%" height={200}>
                  <RadarChart data={[
                    { metric: 'Protein', value: avgMacros.protein },
                    { metric: 'Carbs', value: avgMacros.carbs },
                    { metric: 'Fat', value: avgMacros.fat },
                  ]}>
                    <PolarGrid stroke="#2a2a3a" />
                    <PolarAngleAxis dataKey="metric" tick={{ fontSize: 11, fill: '#8888aa' }} />
                    <Radar dataKey="value" stroke={AMBER} fill={AMBER} fillOpacity={0.3} />
                    <Tooltip />
                  </RadarChart>
                </ResponsiveContainer>
              </div>
            </div>
          </Section>

          {/* ═══ PROGRAMS ═══ */}
          <Section title="📋 Program Analytics" id="section-programs">
            <div className="grid grid-cols-2 md:grid-cols-3 gap-3 mb-4">
              <StatCard label="Active Programs" value={programData.active_programs.length} color={BLUE} />
              <StatCard label="Programs Completed" value={programData.program_history.filter(p => p.status === 'completed').length} color={GREEN} />
              <StatCard label="Programs Abandoned" value={programData.program_history.filter(p => p.status === 'abandoned' || p.status === 'quit').length} color={RED} />
            </div>
            {programStats.length > 0 && (
              <div className="card">
                <span className="text-sm font-semibold block mb-4" style={{ color: 'var(--text-primary)' }}>Top Programs by Enrollment</span>
                <ResponsiveContainer width="100%" height={300}>
                  <BarChart data={programStats}>
                    <CartesianGrid strokeDasharray="3 3" stroke="#2a2a3a" />
                    <XAxis dataKey="name" tick={{ fontSize: 9, fill: '#8888aa' }} angle={-20} textAnchor="end" height={60} />
                    <YAxis tick={{ fontSize: 11, fill: '#8888aa' }} />
                    <Tooltip content={<CustomTooltip />} />
                    <Legend />
                    <Bar dataKey="users" name="Users" fill={BLUE} radius={[4, 4, 0, 0]} />
                    <Bar dataKey="avg_completion" name="Avg Completion %" fill={GREEN} radius={[4, 4, 0, 0]} />
                  </BarChart>
                </ResponsiveContainer>
              </div>
            )}
          </Section>

          {/* ═══ SOCIAL ═══ */}
          <Section title="🤝 Social & Friendships" id="section-social">
            <div className="grid grid-cols-2 md:grid-cols-3 gap-3 mb-4">
              <StatCard label="Total Friendships" value={socialData.friendships.filter(f => f.status === 'accepted').length} color={PINK} />
              <StatCard label="Pending Requests" value={socialData.friendships.filter(f => f.status === 'pending').length} color={AMBER} />
              <StatCard label="Shared Workouts" value={socialData.shared_workouts.length} color={BLUE} />
            </div>
            <div className="card">
              <span className="text-sm font-semibold block mb-4" style={{ color: 'var(--text-primary)' }}>New Friendships Over Time</span>
              <ResponsiveContainer width="100%" height={280}>
                <AreaChart data={friendshipGrowth}>
                  <CartesianGrid strokeDasharray="3 3" stroke="#2a2a3a" />
                  <XAxis dataKey="date" tick={{ fontSize: 10, fill: '#8888aa' }} />
                  <YAxis tick={{ fontSize: 11, fill: '#8888aa' }} />
                  <Tooltip content={<CustomTooltip />} />
                  <Area type="monotone" dataKey="count" name="New Friendships" stroke={PINK} fill={PINK} fillOpacity={0.2} strokeWidth={2} />
                </AreaChart>
              </ResponsiveContainer>
            </div>
          </Section>

          {/* ═══ STREAKS & XP ═══ */}
          <Section title="🔥 Streaks & XP" id="section-streaks">
            <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
              <div className="card">
                <span className="text-sm font-semibold block mb-4" style={{ color: 'var(--text-primary)' }}>Streak Distribution (current)</span>
                <ResponsiveContainer width="100%" height={280}>
                  <BarChart data={streakDistribution}>
                    <CartesianGrid strokeDasharray="3 3" stroke="#2a2a3a" />
                    <XAxis dataKey="range" tick={{ fontSize: 11, fill: '#8888aa' }} />
                    <YAxis tick={{ fontSize: 11, fill: '#8888aa' }} />
                    <Tooltip content={<CustomTooltip />} />
                    <Bar dataKey="count" name="Users" fill={AMBER} radius={[4, 4, 0, 0]} />
                  </BarChart>
                </ResponsiveContainer>
              </div>
              <div className="card">
                <span className="text-sm font-semibold block mb-4" style={{ color: 'var(--text-primary)' }}>XP Distribution</span>
                <ResponsiveContainer width="100%" height={280}>
                  <BarChart data={xpDistribution}>
                    <CartesianGrid strokeDasharray="3 3" stroke="#2a2a3a" />
                    <XAxis dataKey="range" tick={{ fontSize: 11, fill: '#8888aa' }} />
                    <YAxis tick={{ fontSize: 11, fill: '#8888aa' }} />
                    <Tooltip content={<CustomTooltip />} />
                    <Bar dataKey="count" name="Users" fill={INDIGO} radius={[4, 4, 0, 0]} />
                  </BarChart>
                </ResponsiveContainer>
              </div>
            </div>
            {/* Top streak holders */}
            <div className="card">
              <span className="text-sm font-semibold block mb-4" style={{ color: 'var(--text-primary)' }}>Top Streak Holders</span>
              <table>
                <thead>
                  <tr>
                    <th>#</th>
                    <th>User</th>
                    <th>Current Streak</th>
                    <th>Longest Streak</th>
                    <th>Total Workouts</th>
                    <th>XP</th>
                  </tr>
                </thead>
                <tbody>
                  {topStreakers.map((u, i) => (
                    <tr key={i}>
                      <td style={{ color: 'var(--text-muted)' }}>{i + 1}</td>
                      <td className="font-medium" style={{ color: 'var(--text-primary)' }}>
                        {String(u.name || u.username || 'Unknown')}
                        {u.username ? <span className="ml-1 text-xs" style={{ color: 'var(--text-muted)' }}>@{String(u.username)}</span> : null}
                      </td>
                      <td className="font-semibold" style={{ color: AMBER }}>🔥 {u.current_streak as number}</td>
                      <td>{u.longest_streak as number}</td>
                      <td>{u.total_workouts as number}</td>
                      <td style={{ color: BLUE }}>{((u.xp as number) || 0).toLocaleString()}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </Section>

          {/* ═══ HEALTH DATA ═══ */}
          <Section title="❤️ Health Data" id="section-health">
            <div className="grid grid-cols-2 md:grid-cols-4 gap-3 mb-4">
              <StatCard label="Avg Daily Steps" value={avgSteps.toLocaleString()} color={GREEN} />
              <StatCard label="Step Logs" value={healthData.steps.length.toLocaleString()} color={BLUE} />
              <StatCard label="Hydration Logs" value={healthData.hydration.length.toLocaleString()} color={CYAN} />
              <StatCard label="Cardio Sessions" value={healthData.cardio.length.toLocaleString()} color={RED} />
            </div>
            {cardioTypes.length > 0 && (
              <div className="card">
                <span className="text-sm font-semibold block mb-4" style={{ color: 'var(--text-primary)' }}>Cardio Activity Types</span>
                <ResponsiveContainer width="100%" height={280}>
                  <PieChart>
                    <Pie data={cardioTypes} dataKey="value" nameKey="name" cx="50%" cy="50%" outerRadius={100} label={(props: PieLabelRenderProps) => `${props.name || ''} (${(((props.percent as number) || 0) * 100).toFixed(0)}%)`}>
                      {cardioTypes.map((_, i) => <Cell key={i} fill={CHART_COLORS[i % CHART_COLORS.length]} />)}
                    </Pie>
                    <Tooltip />
                  </PieChart>
                </ResponsiveContainer>
              </div>
            )}
          </Section>

          {/* Footer spacer */}
          <div className="h-16" />
        </div>
      </div>
    </AdminShell>
  )
}
