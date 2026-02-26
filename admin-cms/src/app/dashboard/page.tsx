'use client'

import { useEffect, useState } from 'react'
import { useRouter } from 'next/navigation'
import AdminShell from '@/components/AdminShell'
import { adminApi } from '@/lib/api'

interface DashboardStats {
  total_users: number
  new_users_7d: number
  total_workouts: number
  active_users_30d: number
}

interface RecentUser {
  id: string
  name: string | null
  email: string | null
  username: string | null
  profile_photo_url: string | null
  fitness_goal: string | null
  experience_level: string | null
  has_completed_onboarding: boolean
  created_at: string
}

export default function DashboardPage() {
  const [stats, setStats] = useState<DashboardStats | null>(null)
  const [recentUsers, setRecentUsers] = useState<RecentUser[]>([])
  const [loading, setLoading] = useState(true)
  const router = useRouter()

  useEffect(() => {
    loadDashboard()
  }, [])

  async function loadDashboard() {
    try {
      const [statsData, usersData] = await Promise.all([
        adminApi('get_dashboard_stats'),
        adminApi('get_recent_users', { limit: 15 }),
      ])
      setStats(statsData)
      setRecentUsers(usersData.users)
    } catch (err) {
      console.error('Dashboard load error:', err)
    } finally {
      setLoading(false)
    }
  }

  function formatDate(iso: string) {
    return new Date(iso).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' })
  }

  function timeAgo(iso: string) {
    const diff = Date.now() - new Date(iso).getTime()
    const minutes = Math.floor(diff / 60000)
    if (minutes < 60) return `${minutes}m ago`
    const hours = Math.floor(minutes / 60)
    if (hours < 24) return `${hours}h ago`
    const days = Math.floor(hours / 24)
    return `${days}d ago`
  }

  return (
    <AdminShell>
      <div className="p-6 max-w-7xl mx-auto">
        <div className="flex items-center justify-between mb-8">
          <div>
            <h1 className="text-2xl font-bold" style={{ color: 'var(--text-primary)' }}>Dashboard</h1>
            <p className="text-sm mt-1" style={{ color: 'var(--text-secondary)' }}>Fit33 platform overview</p>
          </div>
          <button onClick={loadDashboard} className="btn btn-ghost text-sm">
            ↻ Refresh
          </button>
        </div>

        {loading ? (
          <div className="flex justify-center py-20"><div className="spinner" style={{ width: 32, height: 32 }} /></div>
        ) : (
          <>
            {/* Stats Grid */}
            <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4 mb-8">
              <StatCard label="Total Users" value={stats?.total_users ?? '—'} icon="👥" color="#6366f1" />
              <StatCard label="New (7 days)" value={stats?.new_users_7d ?? '—'} icon="🆕" color="#22c55e" />
              <StatCard label="Active (30 days)" value={stats?.active_users_30d ?? '—'} icon="🔥" color="#f59e0b" />
              <StatCard label="Total Workouts" value={stats?.total_workouts ?? '—'} icon="💪" color="#3b82f6" />
            </div>

            {/* Recent Users */}
            <div className="card">
              <div className="flex items-center justify-between mb-4">
                <h2 className="text-lg font-semibold" style={{ color: 'var(--text-primary)' }}>Recent Signups</h2>
                <button onClick={() => router.push('/users')} className="btn btn-ghost text-xs">
                  View All →
                </button>
              </div>

              <div className="overflow-x-auto">
                <table>
                  <thead>
                    <tr>
                      <th>User</th>
                      <th>Email</th>
                      <th>Goal</th>
                      <th>Level</th>
                      <th>Onboarded</th>
                      <th>Joined</th>
                    </tr>
                  </thead>
                  <tbody>
                    {recentUsers.map((user) => (
                      <tr
                        key={user.id}
                        className="cursor-pointer"
                        onClick={() => router.push(`/users/${user.id}`)}
                      >
                        <td>
                          <div className="flex items-center gap-3">
                            <div
                              className="w-8 h-8 rounded-full flex items-center justify-center text-xs font-bold shrink-0"
                              style={{
                                background: user.profile_photo_url ? 'transparent' : 'var(--bg-tertiary)',
                                color: 'var(--text-secondary)',
                                backgroundImage: user.profile_photo_url ? `url(${user.profile_photo_url})` : undefined,
                                backgroundSize: 'cover',
                              }}
                            >
                              {!user.profile_photo_url && (user.name?.[0] || user.username?.[0] || '?')}
                            </div>
                            <div>
                              <div className="font-medium text-sm">{user.name || '—'}</div>
                              <div className="text-xs" style={{ color: 'var(--text-muted)' }}>@{user.username || '—'}</div>
                            </div>
                          </div>
                        </td>
                        <td className="text-sm" style={{ color: 'var(--text-secondary)' }}>{user.email || '—'}</td>
                        <td><span className="badge badge-info">{user.fitness_goal || '—'}</span></td>
                        <td><span className="badge badge-neutral">{user.experience_level || '—'}</span></td>
                        <td>
                          <span className={`badge ${user.has_completed_onboarding ? 'badge-success' : 'badge-warning'}`}>
                            {user.has_completed_onboarding ? 'Yes' : 'No'}
                          </span>
                        </td>
                        <td className="text-sm" style={{ color: 'var(--text-muted)' }}>{user.created_at ? timeAgo(user.created_at) : '—'}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </div>
          </>
        )}
      </div>
    </AdminShell>
  )
}

function StatCard({ label, value, icon, color }: { label: string; value: number | string; icon: string; color: string }) {
  return (
    <div className="card flex items-center gap-4">
      <div
        className="w-12 h-12 rounded-xl flex items-center justify-center text-xl shrink-0"
        style={{ background: `${color}18` }}
      >
        {icon}
      </div>
      <div>
        <div className="text-2xl font-bold" style={{ color: 'var(--text-primary)' }}>
          {typeof value === 'number' ? value.toLocaleString() : value}
        </div>
        <div className="text-xs font-medium" style={{ color: 'var(--text-secondary)' }}>{label}</div>
      </div>
    </div>
  )
}
