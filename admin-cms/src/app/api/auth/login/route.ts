import { NextRequest, NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'
import { isAdminEmail } from '@/lib/auth'
import { setAuthCookies } from '@/lib/auth-cookies'

const loginAttempts = new Map<string, { count: number; firstAttempt: number; lockedUntil: number }>()
const MAX_ATTEMPTS = 5
const WINDOW_MS = 15 * 60_000
const LOCKOUT_MS = 30 * 60_000

function checkRateLimit(ip: string): { allowed: boolean; retryAfter?: number } {
  const now = Date.now()
  const record = loginAttempts.get(ip)

  if (!record) return { allowed: true }

  if (record.lockedUntil > now) {
    return { allowed: false, retryAfter: Math.ceil((record.lockedUntil - now) / 1000) }
  }

  if (now - record.firstAttempt > WINDOW_MS) {
    loginAttempts.delete(ip)
    return { allowed: true }
  }

  if (record.count >= MAX_ATTEMPTS) {
    record.lockedUntil = now + LOCKOUT_MS
    return { allowed: false, retryAfter: Math.ceil(LOCKOUT_MS / 1000) }
  }

  return { allowed: true }
}

function recordFailedAttempt(ip: string) {
  const now = Date.now()
  const record = loginAttempts.get(ip)
  if (!record) {
    loginAttempts.set(ip, { count: 1, firstAttempt: now, lockedUntil: 0 })
  } else {
    record.count++
  }
}

function clearAttempts(ip: string) {
  loginAttempts.delete(ip)
}

setInterval(() => {
  const now = Date.now()
  for (const [ip, record] of loginAttempts) {
    if (now - record.firstAttempt > WINDOW_MS && record.lockedUntil < now) {
      loginAttempts.delete(ip)
    }
  }
}, 10 * 60_000)

export async function POST(req: NextRequest) {
  try {
    const ip = req.headers.get('x-forwarded-for')?.split(',')[0]?.trim()
      || req.headers.get('x-real-ip')
      || 'unknown'

    const rateCheck = checkRateLimit(ip)
    if (!rateCheck.allowed) {
      return NextResponse.json(
        { error: `Too many login attempts. Try again in ${rateCheck.retryAfter} seconds.` },
        { status: 429, headers: { 'Retry-After': String(rateCheck.retryAfter) } },
      )
    }

    const { email, password } = await req.json()

    if (!email || !password) {
      return NextResponse.json({ error: 'Email and password required' }, { status: 400 })
    }

    if (!isAdminEmail(email)) {
      recordFailedAttempt(ip)
      return NextResponse.json({ error: 'Invalid credentials' }, { status: 401 })
    }

    const supabase = createClient(
      process.env.NEXT_PUBLIC_SUPABASE_URL!,
      process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    )

    const { data, error } = await supabase.auth.signInWithPassword({ email, password })

    if (error || !data.session) {
      recordFailedAttempt(ip)
      return NextResponse.json({ error: 'Invalid credentials' }, { status: 401 })
    }

    clearAttempts(ip)

    const authedClient = createClient(
      process.env.NEXT_PUBLIC_SUPABASE_URL!,
      process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
      { global: { headers: { Authorization: `Bearer ${data.session.access_token}` } } },
    )

    const { data: aal } = await authedClient.auth.mfa.getAuthenticatorAssuranceLevel()
    if (aal && aal.nextLevel === 'aal2' && aal.currentLevel === 'aal1') {
      const { data: factors } = await authedClient.auth.mfa.listFactors()
      const totpFactor = factors?.totp?.[0]
      if (totpFactor) {
        return NextResponse.json({
          mfa_required: true,
          factor_id: totpFactor.id,
          temp_token: data.session.access_token,
          temp_refresh: data.session.refresh_token,
          temp_expires: data.session.expires_at ?? 0,
        })
      }
    }

    const response = NextResponse.json({
      user: {
        id: data.user?.id,
        email: data.user?.email,
      },
    })

    setAuthCookies(response, {
      accessToken: data.session.access_token,
      refreshToken: data.session.refresh_token,
      expiresAt: data.session.expires_at ?? 0,
    })

    return response
  } catch {
    return NextResponse.json({ error: 'Internal server error' }, { status: 500 })
  }
}
