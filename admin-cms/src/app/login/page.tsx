'use client'

import { useState, FormEvent } from 'react'
import { useRouter } from 'next/navigation'

export default function LoginPage() {
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [error, setError] = useState('')
  const [loading, setLoading] = useState(false)
  const router = useRouter()

  async function handleLogin(e: FormEvent) {
    e.preventDefault()
    setError('')
    setLoading(true)

    try {
      const res = await fetch('/api/auth/login', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email, password }),
      })

      const data = await res.json()

      if (!res.ok) {
        setError(data.error || 'Login failed')
        setLoading(false)
        return
      }

      // Tokens are now in httpOnly cookies (set by the server)
      router.push('/dashboard')
    } catch {
      setError('Network error. Please try again.')
      setLoading(false)
    }
  }

  return (
    <div className="min-h-screen flex flex-col items-center justify-center" style={{ background: '#000000' }}>
      <div className="w-full max-w-sm px-6 flex flex-col items-center gap-10">
        {/* Logo */}
        <img
          src="/fit33-logo.png"
          alt="Fit33"
          style={{ width: 160, height: 'auto' }}
        />

        {/* Login Card */}
        <div className="w-full rounded-2xl p-6" style={{ background: '#111118', border: '1px solid #1e1e2e' }}>
          <form onSubmit={handleLogin} className="flex flex-col gap-5">
            <div>
              <label className="block text-xs font-semibold uppercase tracking-wide mb-2" style={{ color: '#8888aa' }}>
                Email
              </label>
              <input
                type="email"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                placeholder="Email"
                required
                autoComplete="email"
                style={{ background: '#0a0a12', border: '1px solid #2a2a3a', color: '#f0f0f5', padding: '12px 14px', borderRadius: '10px', fontSize: '14px', width: '100%', outline: 'none' }}
              />
            </div>

            <div>
              <label className="block text-xs font-semibold uppercase tracking-wide mb-2" style={{ color: '#8888aa' }}>
                Password
              </label>
              <input
                type="password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                placeholder="••••••••"
                required
                autoComplete="current-password"
                style={{ background: '#0a0a12', border: '1px solid #2a2a3a', color: '#f0f0f5', padding: '12px 14px', borderRadius: '10px', fontSize: '14px', width: '100%', outline: 'none' }}
              />
            </div>

            {error && (
              <div className="p-3 rounded-lg text-sm font-medium" style={{ background: 'rgba(239, 68, 68, 0.1)', color: '#ef4444' }}>
                ⚠️ {error}
              </div>
            )}

            <button
              type="submit"
              disabled={loading}
              className="w-full font-semibold text-white text-sm py-3 rounded-xl cursor-pointer disabled:opacity-50 disabled:cursor-not-allowed"
              style={{ background: '#2563eb', marginTop: '4px' }}
              onMouseEnter={(e) => { if (!loading) (e.target as HTMLButtonElement).style.background = '#3b82f6' }}
              onMouseLeave={(e) => { (e.target as HTMLButtonElement).style.background = '#2563eb' }}
            >
              {loading ? (
                <span className="flex items-center justify-center gap-2"><span className="spinner" /> Authenticating...</span>
              ) : (
                'Sign In'
              )}
            </button>
          </form>
        </div>

        {/* Footer */}
        <p className="text-xs" style={{ color: '#555566' }}>
          🔒 Access restricted to authorized Fit33 team members
        </p>
      </div>
    </div>
  )
}
