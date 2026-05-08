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
  const [deleteTarget, setDeleteTarget] = useState<UserRow | null>(null)
  const [deleteConfirmText, setDeleteConfirmText] = useState('')
  const [deleting, setDeleting] = useState(false)
  const [deleteError, setDeleteError] = useState<string | null>(null)
  const [toast, setToast] = useState<string | null>(null)
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

  // Typed-confirmation gate. We require the admin to type the user's email
  // (or username if email is missing, or ID if both are missing) before the
  // delete is enabled — same paranoia GitHub / Stripe use for destructive
  // ops. Prevents fat-finger deletes when scanning a long user list.
  function confirmTokenFor(u: UserRow): string {
    return u.email || u.username || u.id
  }

  function openDeleteDialog(user: UserRow, e: React.MouseEvent) {
    e.stopPropagation()
    setDeleteTarget(user)
    setDeleteConfirmText('')
    setDeleteError(null)
  }

  function closeDeleteDialog() {
    if (deleting) return
    setDeleteTarget(null)
    setDeleteConfirmText('')
    setDeleteError(null)
  }

  async function executeDelete() {
    if (!deleteTarget) return
    if (deleteConfirmText.trim().toLowerCase() !== confirmTokenFor(deleteTarget).toLowerCase()) {
      setDeleteError('Confirmation text does not match.')
      return
    }
    setDeleting(true)
    setDeleteError(null)
    try {
      await adminApi('delete_user', { user_id: deleteTarget.id })
      const label = deleteTarget.name || deleteTarget.email || deleteTarget.username || deleteTarget.id.slice(0, 8)
      setToast(`Deleted ${label}`)
      setDeleteTarget(null)
      setDeleteConfirmText('')
      // Optimistic remove from current list so the row disappears
      // immediately even before the server-side reload completes.
      setUsers(prev => prev.filter(u => u.id !== deleteTarget.id))
      // Then reload from server to pick up the canonical post-delete state.
      loadUsers(query, page)
      setTimeout(() => setToast(null), 4000)
    } catch (err) {
      const msg = err instanceof Error ? err.message : 'Delete failed'
      setDeleteError(msg)
    } finally {
      setDeleting(false)
    }
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

        {/* Toast */}
        {toast && (
          <div
            className="mb-4 px-4 py-3 rounded-lg text-sm font-medium"
            style={{
              background: 'rgba(34, 197, 94, 0.12)',
              color: 'var(--success)',
              border: '1px solid rgba(34, 197, 94, 0.3)',
            }}
          >
            ✓ {toast}
          </div>
        )}

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
                      <th>Actions</th>
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
                        <td>
                          <button
                            onClick={(e) => openDeleteDialog(user, e)}
                            className="px-2 py-1 rounded text-xs font-medium transition-colors"
                            style={{
                              background: 'rgba(239, 68, 68, 0.08)',
                              color: 'var(--danger)',
                              border: '1px solid rgba(239, 68, 68, 0.25)',
                            }}
                            onMouseEnter={(e) => {
                              e.currentTarget.style.background = 'rgba(239, 68, 68, 0.18)'
                            }}
                            onMouseLeave={(e) => {
                              e.currentTarget.style.background = 'rgba(239, 68, 68, 0.08)'
                            }}
                            title="Delete user (permanent)"
                          >
                            🗑️ Delete
                          </button>
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

        {/* ═══════════════════════════════════════════════════
            DELETE CONFIRM MODAL
            Backdrop click + Esc both call closeDeleteDialog().
            Type-to-confirm matches the user's email (or fallback
            identifier) — disabled CTA until the typed text matches.
            ═══════════════════════════════════════════════════ */}
        {deleteTarget && (
          <DeleteUserModal
            user={deleteTarget}
            confirmText={deleteConfirmText}
            confirmToken={confirmTokenFor(deleteTarget)}
            onChangeText={setDeleteConfirmText}
            onCancel={closeDeleteDialog}
            onConfirm={executeDelete}
            deleting={deleting}
            error={deleteError}
          />
        )}
      </div>
    </AdminShell>
  )
}

// ═══════════════════════════════════════════════════════════════════════════
// DeleteUserModal
//
// Type-to-confirm pattern (GitHub / Stripe / Supabase Studio standard).
// Avoids the "muscle-memory click-through" failure mode of a plain confirm
// dialog. The token to type is the user's email when present, falling back
// to username, then UUID. All comparisons are case-insensitive.
// ═══════════════════════════════════════════════════════════════════════════
function DeleteUserModal({
  user,
  confirmText,
  confirmToken,
  onChangeText,
  onCancel,
  onConfirm,
  deleting,
  error,
}: {
  user: UserRow
  confirmText: string
  confirmToken: string
  onChangeText: (s: string) => void
  onCancel: () => void
  onConfirm: () => void
  deleting: boolean
  error: string | null
}) {
  const matches = confirmText.trim().toLowerCase() === confirmToken.toLowerCase()

  // Esc-to-cancel + click-outside-to-cancel.
  useEffect(() => {
    function onKey(e: KeyboardEvent) {
      if (e.key === 'Escape') onCancel()
      if (e.key === 'Enter' && matches && !deleting) onConfirm()
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [matches, deleting, onCancel, onConfirm])

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center p-4"
      style={{ background: 'rgba(0, 0, 0, 0.6)' }}
      onClick={onCancel}
    >
      <div
        className="card max-w-md w-full"
        style={{ borderColor: 'rgba(239, 68, 68, 0.4)' }}
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex items-start gap-3 mb-4">
          <div
            className="w-10 h-10 rounded-lg flex items-center justify-center shrink-0 text-lg"
            style={{ background: 'rgba(239, 68, 68, 0.12)' }}
          >
            ⚠️
          </div>
          <div className="flex-1">
            <h2 className="text-lg font-bold" style={{ color: 'var(--danger)' }}>Permanently delete user?</h2>
            <p className="text-sm mt-1" style={{ color: 'var(--text-secondary)' }}>
              This deletes the account, all friendships, workouts, meals, streaks, push tokens, notifications, daily quests, and the underlying auth.users record. <strong>This cannot be undone.</strong>
            </p>
          </div>
        </div>

        <div
          className="p-3 rounded-lg mb-4"
          style={{ background: 'var(--bg-tertiary)', border: '1px solid var(--border)' }}
        >
          <div className="flex items-center gap-3">
            <div
              className="w-9 h-9 rounded-full flex items-center justify-center text-xs font-bold shrink-0"
              style={{
                background: user.profile_photo_url ? 'transparent' : 'var(--bg-primary)',
                color: 'var(--text-secondary)',
                backgroundImage: user.profile_photo_url ? `url(${user.profile_photo_url})` : undefined,
                backgroundSize: 'cover',
              }}
            >
              {!user.profile_photo_url && (user.name?.[0] || '?')}
            </div>
            <div className="flex-1 min-w-0">
              <div className="font-medium text-sm truncate">{user.name || 'Unnamed'}</div>
              <div className="text-xs truncate" style={{ color: 'var(--text-muted)' }}>
                {user.email || `@${user.username || user.id.slice(0, 8)}`}
              </div>
            </div>
          </div>
        </div>

        <label className="block text-xs font-medium mb-1" style={{ color: 'var(--text-muted)' }}>
          To confirm, type <code style={{ color: 'var(--danger)', fontFamily: 'monospace' }}>{confirmToken}</code>
        </label>
        <input
          type="text"
          value={confirmText}
          onChange={(e) => onChangeText(e.target.value)}
          placeholder={confirmToken}
          autoFocus
          disabled={deleting}
          className="w-full text-sm"
          style={{
            fontFamily: 'monospace',
            borderColor: matches ? 'var(--success)' : undefined,
          }}
        />

        {error && (
          <div
            className="mt-3 p-2 rounded text-xs"
            style={{
              background: 'rgba(239, 68, 68, 0.1)',
              color: 'var(--danger)',
              border: '1px solid rgba(239, 68, 68, 0.25)',
            }}
          >
            {error}
          </div>
        )}

        <div className="flex justify-end gap-2 mt-5">
          <button
            onClick={onCancel}
            disabled={deleting}
            className="btn btn-ghost text-sm"
          >
            Cancel
          </button>
          <button
            onClick={onConfirm}
            disabled={!matches || deleting}
            className="btn text-sm"
            style={{
              background: matches && !deleting ? 'var(--danger)' : 'var(--bg-tertiary)',
              color: matches && !deleting ? '#fff' : 'var(--text-muted)',
              cursor: matches && !deleting ? 'pointer' : 'not-allowed',
            }}
          >
            {deleting ? <><span className="spinner" /> Deleting...</> : '🗑️ Delete user'}
          </button>
        </div>
      </div>
    </div>
  )
}
