'use client'

import { useState, FormEvent } from 'react'
import { useRouter } from 'next/navigation'

type MfaSession = {
    factor_id: string
    temp_token: string
    temp_refresh: string
    temp_expires: number
}

type EnrollmentPayload = {
    factor_id: string
    qr_code: string
    secret: string
    uri: string
}

type Step = 'credentials' | 'verify' | 'enroll'

export default function LoginPage() {
    const [email, setEmail] = useState('')
    const [password, setPassword] = useState('')
    const [mfaCode, setMfaCode] = useState('')
    const [error, setError] = useState('')
    const [loading, setLoading] = useState(false)
    const [mfaState, setMfaState] = useState<MfaSession | null>(null)
    const [enrollment, setEnrollment] = useState<EnrollmentPayload | null>(null)
    const [step, setStep] = useState<Step>('credentials')
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
                setStep('verify')
                setLoading(false)
                return
            }

            if (data.mfa_enrollment_required) {
                const enrollRes = await fetch('/api/auth/enroll-mfa', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({
                        temp_token: data.temp_token,
                        pending_factor_id: data.pending_factor_id,
                    }),
                })
                const enrollData = await enrollRes.json()
                if (!enrollRes.ok) {
                    setError(enrollData.error || 'MFA enrollment failed')
                    setLoading(false)
                    return
                }

                setEnrollment({
                    factor_id: enrollData.factor_id,
                    qr_code: enrollData.qr_code,
                    secret: enrollData.secret,
                    uri: enrollData.uri,
                })
                setMfaState({
                    factor_id: enrollData.factor_id,
                    temp_token: data.temp_token,
                    temp_refresh: data.temp_refresh,
                    temp_expires: data.temp_expires,
                })
                setStep('enroll')
                setLoading(false)
                return
            }

            // Pre-Sprint-9 the server used to set auth cookies here. Q2-87
            // removed that branch — the server always requires an MFA step.
            setError('Unexpected response from server')
            setLoading(false)
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

    function resetToCredentials() {
        setMfaState(null)
        setEnrollment(null)
        setMfaCode('')
        setError('')
        setStep('credentials')
    }

    return (
        <div className="min-h-screen flex flex-col items-center justify-center" style={{ background: '#000000' }}>
            <div className="w-full max-w-sm px-6 flex flex-col items-center gap-10">
                <img
                    src="/fit33-logo.png"
                    alt="Fit33"
                    style={{ width: 160, height: 'auto' }}
                />

                <div className="w-full rounded-2xl p-6" style={{ background: '#111118', border: '1px solid #1e1e2e' }}>
                    {step === 'credentials' && (
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
                    )}

                    {step === 'enroll' && enrollment && (
                        <form onSubmit={handleMfaVerify} className="flex flex-col gap-5">
                            <div className="flex flex-col gap-2">
                                <h2 className="text-base font-semibold" style={{ color: '#f0f0f5' }}>
                                    Enable Two-Factor Auth
                                </h2>
                                <p className="text-xs" style={{ color: '#8888aa' }}>
                                    All admin accounts require TOTP. Scan the QR code below with
                                    1Password, Authy, or Google Authenticator, then enter the 6-digit
                                    code to finish enrollment.
                                </p>
                            </div>

                            <div className="flex justify-center p-4 rounded-xl" style={{ background: '#ffffff' }}>
                                {/* Supabase returns the QR as an SVG data URI. */}
                                <img src={enrollment.qr_code} alt="TOTP QR code" style={{ width: 180, height: 180 }} />
                            </div>

                            <div className="flex flex-col gap-1">
                                <label className="text-xs font-semibold uppercase tracking-wide" style={{ color: '#8888aa' }}>
                                    Or enter this secret manually
                                </label>
                                <code
                                    className="text-xs p-2 rounded"
                                    style={{ background: '#0a0a12', color: '#f0f0f5', wordBreak: 'break-all', userSelect: 'all' }}
                                >
                                    {enrollment.secret}
                                </code>
                            </div>

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
                            >
                                {loading ? (
                                    <span className="flex items-center justify-center gap-2"><span className="spinner" /> Finishing enrollment...</span>
                                ) : (
                                    'Enable & Sign In'
                                )}
                            </button>

                            <button
                                type="button"
                                onClick={resetToCredentials}
                                className="text-sm cursor-pointer"
                                style={{ color: '#8888aa', background: 'none', border: 'none' }}
                            >
                                Back to login
                            </button>
                        </form>
                    )}

                    {step === 'verify' && (
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
                            >
                                {loading ? (
                                    <span className="flex items-center justify-center gap-2"><span className="spinner" /> Verifying...</span>
                                ) : (
                                    'Verify'
                                )}
                            </button>

                            <button
                                type="button"
                                onClick={resetToCredentials}
                                className="text-sm cursor-pointer"
                                style={{ color: '#8888aa', background: 'none', border: 'none' }}
                            >
                                Back to login
                            </button>
                        </form>
                    )}
                </div>

                <p className="text-xs" style={{ color: '#555566' }}>
                    🔒 Access restricted to authorized Fit33 team members
                </p>
            </div>
        </div>
    )
}
