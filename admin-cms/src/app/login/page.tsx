'use client'

import { useState, FormEvent } from 'react'
import { useRouter } from 'next/navigation'

export default function LoginPage() {
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [mfaCode, setMfaCode] = useState('')
  const [error, setError] = useState('')
  const [loading, setLoading] = useState(false)
  const [mfaState, setMfaState] = useState<{ factor_id: string; temp_token: string; temp_refresh: string; temp_expires: number } | null>(null)
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

      if (data.mfa_required) {
        setMfaState({
          factor_id: data.factor_id,
          temp_token: data.temp_token,
          temp_refresh: data.temp_refresh,
          temp_expires: data.temp_expires,
        })
        setLoading(false)
        return
      }

      router.push('/dashboard')
    } catch {
      setError('Network error. Please try again.')
      setLoading(false)
    }
  }

  async function handleMfaVerify(e: FormEvent) {
    e.preventDefault()
    setError('')
    setLoading(true)

    try {
      const res = await fetch('/api/auth/verify-mfa', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          factor_id: mfaState?.factor_id,
          code: mfaCode,
          temp_token: mfaState?.temp_token,
          temp_refresh: mfaState?.temp_refresh,
          temp_expires: mfaState?.temp_expires,
        }),
      })

      const data = await res.json()

      if (!res.ok) {
        setError(data.error || 'Verification failed')
        setLoading(false)
        return
      }

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
          {!mfaState ? (
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
                  {error}
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
          ) : (
            <form onSubmit={handleMfaVerify} className="flex flex-col gap-5">
              <p className="text-sm text-center" style={{ color: '#8888aa' }}>
                Enter the 6-digit code from your authenticator app
              </p>

              <div>
                <label className="block text-xs font-semibold uppercase tracking-wide mb-2" style={{ color: '#8888aa' }}>
                  Verification Code
                </label>
                <input
                  type="text"
                  inputMode="numeric"
                  pattern="[0-9]*"
                  maxLength={6}
                  value={mfaCode}
                  onChange={(e) => setMfaCode(e.target.value.replace(/\D/g, ''))}
                  placeholder="000000"
                  required
                  autoFocus
                  autoComplete="one-time-code"
                  className="text-center tracking-[0.5em]"
                  style={{ background: '#0a0a12', border: '1px solid #2a2a3a', color: '#f0f0f5', padding: '14px', borderRadius: '10px', fontSize: '24px', width: '100%', outline: 'none', letterSpacing: '0.3em' }}
                />
              </div>

              {error && (
                <div className="p-3 rounded-lg text-sm font-medium" style={{ background: 'rgba(239, 68, 68, 0.1)', color: '#ef4444' }}>
                  {error}
                </div>
              )}

              <button
                type="submit"
                disabled={loading || mfaCode.length !== 6}
                className="w-full font-semibold text-white text-sm py-3 rounded-xl cursor-pointer disabled:opacity-50 disabled:cursor-not-allowed"
                style={{ background: '#2563eb', marginTop: '4px' }}
                onMouseEnter={(e) => { if (!loading) (e.target as HTMLButtonElement).style.background = '#3b82f6' }}
                onMouseLeave={(e) => { (e.target as HTMLButtonElement).style.background = '#2563eb' }}
              >
                {loading ? (
                  <span className="flex items-center justify-center gap-2"><span className="spinner" /> Verifying...</span>
                ) : (
                  'Verify'
                )}
              </button>

              <button
                type="button"
                onClick={() => { setMfaState(null); setMfaCode(''); setError('') }}
                className="text-sm cursor-pointer"
                style={{ color: '#8888aa', background: 'none', border: 'none' }}
              >
                Back to login
              </button>
            </form>
          )}
        </div>

        {/* Footer */}
        <p className="text-xs" style={{ color: '#555566' }}>
          🔒 Access restricted to authorized Fit33 team members
        </p>
      </div>
    </div>
  )
}
