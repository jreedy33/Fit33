'use client'

import { useEffect, useState, useCallback } from 'react'
import { useRouter } from 'next/navigation'
import AdminShell from '@/components/AdminShell'
import { adminApi } from '@/lib/api'

interface UserRow {
  id: string
  name: string | null
  email: string | null
  username: string | null
  phone_number: string | null
  gender: string | null
  age: number | null
  fitness_goal: string | null
  experience_level: string | null
  current_streak: number | null
  longest_streak: number | null
  total_workouts: number | null
  xp: number | null
  profile_photo_url: string | null
  has_completed_onboarding: boolean
  created_at: string
  updated_at: string | null
  last_workout_date: string | null
}

export default function UsersPage() {
  const [users, setUsers] = useState<UserRow[]>([])
  const [query, setQuery] = useState('')
  const [page, setPage] = useState(0)
  const [loading, setLoading] = useState(true)
  const router = useRouter()

  const loadUsers = useCallback(async (searchQuery: string, pageNum: number) => {
    setLoading(true)
    try {
      const data = await adminApi('search_users', { query: searchQuery, page: pageNum, limit: 50 })
      setUsers(data.users)
    } catch (err) {
      console.error('Load users error:', err)
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => {
    loadUsers('', 0)
  }, [loadUsers])

  // Debounced search
  useEffect(() => {
    const timer = setTimeout(() => {
      setPage(0)
      loadUsers(query, 0)
    }, 300)
    return () => clearTimeout(timer)
  }, [query, loadUsers])

  function formatDate(iso: string | null) {
    if (!iso) return '—'
    return new Date(iso).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' })
  }

  return (
    <AdminShell>
      <div className="p-6 max-w-7xl mx-auto">
        <div className="flex items-center justify-between mb-6">
          <div>
            <h1 className="text-2xl font-bold" style={{ color: 'var(--text-primary)' }}>Users</h1>
            <p className="text-sm mt-1" style={{ color: 'var(--text-secondary)' }}>Search by email, username, name, or phone number</p>
          </div>
        </div>

        {/* Search Bar */}
        <div className="mb-6">
          <div className="relative max-w-xl">
            <span className="absolute left-3 top-1/2 -translate-y-1/2 text-lg">🔍</span>
            <input
              type="search"
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              placeholder="Search by email, phone, username, or name..."
              className="pl-10"
              style={{ fontSize: 15, padding: '12px 16px 12px 40px' }}
              autoFocus
            />
          </div>
        </div>

        {/* Results Table */}
        <div className="card overflow-hidden">
          {loading ? (
            <div className="flex justify-center py-12"><div className="spinner" style={{ width: 28, height: 28 }} /></div>
          ) : users.length === 0 ? (
            <div className="text-center py-12" style={{ color: 'var(--text-muted)' }}>
              {query ? `No users found for "${query}"` : 'No users yet'}
            </div>
          ) : (
            <>
              <div className="overflow-x-auto">
                <table>
                  <thead>
                    <tr>
                      <th>User</th>
                      <th>Contact</th>
                      <th>Goal</th>
                      <th>Level</th>
                      <th>Streak</th>
                      <th>Workouts</th>
                      <th>XP</th>
                      <th>Status</th>
                      <th>Last Active</th>
                      <th>Joined</th>
                    </tr>
                  </thead>
                  <tbody>
                    {users.map((user) => (
                      <tr
                        key={user.id}
                        className="cursor-pointer"
                        onClick={() => router.push(`/users/${user.id}`)}
                      >
                        <td>
                          <div className="flex items-center gap-3 min-w-[160px]">
                            <div
                              className="w-9 h-9 rounded-full flex items-center justify-center text-xs font-bold shrink-0"
                              style={{
                                background: user.profile_photo_url ? 'transparent' : 'var(--bg-tertiary)',
                                color: 'var(--text-secondary)',
                                backgroundImage: user.profile_photo_url ? `url(${user.profile_photo_url})` : undefined,
                                backgroundSize: 'cover',
                              }}
                            >
                              {!user.profile_photo_url && (user.name?.[0] || '?')}
                            </div>
                            <div>
                              <div className="font-medium text-sm">{user.name || '—'}</div>
                              <div className="text-xs" style={{ color: 'var(--text-muted)' }}>@{user.username || '—'}</div>
                            </div>
                          </div>
                        </td>
                        <td>
                          <div className="text-sm" style={{ color: 'var(--text-secondary)' }}>{user.email || '—'}</div>
                          {user.phone_number && (
                            <div className="text-xs" style={{ color: 'var(--text-muted)' }}>{user.phone_number}</div>
                          )}
                        </td>
                        <td><span className="badge badge-info">{user.fitness_goal || '—'}</span></td>
                        <td><span className="badge badge-neutral">{user.experience_level || '—'}</span></td>
                        <td className="text-sm font-medium" style={{ color: user.current_streak ? 'var(--warning)' : 'var(--text-muted)' }}>
                          {user.current_streak ? `🔥 ${user.current_streak}` : '—'}
                        </td>
                        <td className="text-sm" style={{ color: 'var(--text-secondary)' }}>
                          {user.total_workouts ?? '—'}
                        </td>
                        <td className="text-sm" style={{ color: 'var(--accent)' }}>
                          {user.xp ? user.xp.toLocaleString() : '—'}
                        </td>
                        <td>
                          <span className={`badge ${user.has_completed_onboarding ? 'badge-success' : 'badge-warning'}`}>
                            {user.has_completed_onboarding ? 'Active' : 'Onboarding'}
                          </span>
                        </td>
                        <td className="text-xs" style={{ color: 'var(--text-muted)' }}>
                          {formatDate(user.last_workout_date)}
                        </td>
                        <td className="text-xs" style={{ color: 'var(--text-muted)' }}>
                          {formatDate(user.created_at)}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>

              {/* Pagination */}
              <div className="flex items-center justify-between p-4 border-t" style={{ borderColor: 'var(--border)' }}>
                <div className="text-xs" style={{ color: 'var(--text-muted)' }}>
                  Showing {users.length} users {query && `matching "${query}"`}
                </div>
                <div className="flex gap-2">
                  <button
                    onClick={() => { setPage(p => Math.max(0, p - 1)); loadUsers(query, Math.max(0, page - 1)) }}
                    disabled={page === 0}
                    className="btn btn-ghost text-xs"
                  >
                    ← Previous
                  </button>
                  <span className="flex items-center text-xs px-3" style={{ color: 'var(--text-muted)' }}>Page {page + 1}</span>
                  <button
                    onClick={() => { setPage(p => p + 1); loadUsers(query, page + 1) }}
                    disabled={users.length < 50}
                    className="btn btn-ghost text-xs"
                  >
                    Next →
                  </button>
                </div>
              </div>
            </>
          )}
        </div>
      </div>
    </AdminShell>
  )
}
