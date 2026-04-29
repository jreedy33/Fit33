'use client'

import { useEffect, useState } from 'react'
import { useRouter, usePathname } from 'next/navigation'
import { logout } from '@/lib/api'

const navItems = [
  { href: '/dashboard', label: 'Dashboard', icon: '📊' },
  { href: '/users', label: 'Users', icon: '👥' },
  { href: '/exercises', label: 'Exercises', icon: '💪' },
  { href: '/metrics', label: 'Metrics', icon: '📈' },
  { href: '/engagement', label: 'Engagement', icon: '🎯' },
  { href: '/health', label: 'System Health', icon: '🔧' },
  { href: '/notifications', label: 'Push Manager', icon: '🔔' },
  { href: '/flags', label: 'Feature Flags', icon: '🚩' },
  { href: '/moderation', label: 'Moderation', icon: '🛡️' },
  { href: '/audit', label: 'Audit Log', icon: '📋' },
  { href: '/insights', label: 'AI Insights', icon: '🧠' },
  { href: '/dev-logs', label: 'Dev Logs', icon: '🔬' },
  { href: '/bug-intelligence', label: 'Bug Intelligence', icon: '🧬' },
  { href: '/crashes', label: 'Crashes & Bugs', icon: '🐛' },
  { href: '/revenue', label: 'Revenue', icon: '💰' },
  { href: '/faq', label: 'FAQ Manager', icon: '❓' },
]

export default function AdminShell({ children }: { children: React.ReactNode }) {
  const router = useRouter()
  const pathname = usePathname()
  const [adminEmail, setAdminEmail] = useState('')
  const [sidebarCollapsed, setSidebarCollapsed] = useState(false)
  const [authChecked, setAuthChecked] = useState(false)

  useEffect(() => {
    // Sprint 4 (Q2-21): the `document.cookie.includes('admin_logged_in')`
    // precheck is gone — the auth cookie is now httpOnly and middleware
    // already gates every route AdminShell mounts on. This fetch is the
    // single source of truth: it returns the admin email on 200 and drives
    // the /login redirect on any non-200.
    fetch('/api/auth/session')
      .then(res => res.ok ? res.json() : Promise.reject())
      .then(data => {
        setAdminEmail(data.user?.email || '')
        setAuthChecked(true)
      })
      .catch(() => router.replace('/login'))
  }, [router])

  if (!authChecked) return null

  return (
    <div className="flex min-h-screen">
      {/* Sidebar */}
      <aside
        className="flex flex-col border-r shrink-0"
        style={{
          width: sidebarCollapsed ? 60 : 240,
          background: 'var(--bg-secondary)',
          borderColor: 'var(--border)',
          transition: 'width 0.2s ease',
        }}
      >
        {/* Logo */}
        <div className="flex items-center gap-3 p-4 border-b" style={{ borderColor: 'var(--border)' }}>
          <div
            className="flex items-center justify-center rounded-lg shrink-0"
            style={{ width: 32, height: 32, background: 'var(--accent)', fontSize: 12, fontWeight: 700, color: 'white' }}
          >
            F33
          </div>
          {!sidebarCollapsed && (
            <div>
              <div className="font-semibold text-sm" style={{ color: 'var(--text-primary)' }}>Fit33 Admin</div>
              <div className="text-xs" style={{ color: 'var(--text-muted)' }}>CMS</div>
            </div>
          )}
        </div>

        {/* Navigation */}
        <nav className="flex-1 py-3 px-2 space-y-1">
          {navItems.map((item) => {
            const isActive = pathname.startsWith(item.href)
            return (
              <button
                key={item.href}
                onClick={() => router.push(item.href)}
                className="flex items-center gap-3 w-full px-3 py-2.5 rounded-lg text-sm font-medium"
                style={{
                  background: isActive ? 'rgba(37, 99, 235, 0.12)' : 'transparent',
                  color: isActive ? 'var(--accent)' : 'var(--text-secondary)',
                }}
              >
                <span className="text-lg">{item.icon}</span>
                {!sidebarCollapsed && item.label}
              </button>
            )
          })}
        </nav>

        {/* Footer */}
        <div className="border-t p-3 space-y-2" style={{ borderColor: 'var(--border)' }}>
          <button
            onClick={() => setSidebarCollapsed(!sidebarCollapsed)}
            className="flex items-center justify-center w-full p-2 rounded-lg text-xs"
            style={{ color: 'var(--text-muted)' }}
          >
            {sidebarCollapsed ? '→' : '← Collapse'}
          </button>
          {!sidebarCollapsed && (
            <>
              <div className="text-xs truncate px-2" style={{ color: 'var(--text-muted)' }}>{adminEmail}</div>
              <button
                onClick={logout}
                className="btn btn-ghost w-full text-xs justify-center"
              >
                Sign Out
              </button>
            </>
          )}
        </div>
      </aside>

      {/* Main content */}
      <main className="flex-1 overflow-auto">
        {children}
      </main>
    </div>
  )
}
