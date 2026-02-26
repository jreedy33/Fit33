import { NextRequest, NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'
import { isAdminEmail } from '@/lib/auth'

// ═══════════════════════════════════════════════════
// RATE LIMITING — Brute force protection
// ═══════════════════════════════════════════════════
const loginAttempts = new Map<string, { count: number; firstAttempt: number; lockedUntil: number }>()
const MAX_ATTEMPTS = 5          // max failed attempts before lockout
const WINDOW_MS = 15 * 60_000   // 15 minute window
const LOCKOUT_MS = 30 * 60_000  // 30 minute lockout after too many failures

function checkRateLimit(ip: string): { allowed: boolean; retryAfter?: number } {
  const now = Date.now()
  const record = loginAttempts.get(ip)

  if (!record) return { allowed: true }

  // Currently locked out?
  if (record.lockedUntil > now) {
    return { allowed: false, retryAfter: Math.ceil((record.lockedUntil - now) / 1000) }
  }

  // Window expired — reset
  if (now - record.firstAttempt > WINDOW_MS) {
    loginAttempts.delete(ip)
    return { allowed: true }
  }

  // Too many attempts — lock
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

// Clean up stale entries every 10 minutes
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
    // Get client IP for rate limiting
    const ip = req.headers.get('x-forwarded-for')?.split(',')[0]?.trim()
      || req.headers.get('x-real-ip')
      || 'unknown'

    // Check rate limit
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

    // Check admin whitelist FIRST before even trying auth
    // Use generic error to avoid revealing which emails are admins
    if (!isAdminEmail(email)) {
      recordFailedAttempt(ip)
      return NextResponse.json({ error: 'Invalid credentials' }, { status: 401 })
    }

    // Sign in with Supabase Auth
    const supabase = createClient(
      process.env.NEXT_PUBLIC_SUPABASE_URL!,
      process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    )

    const { data, error } = await supabase.auth.signInWithPassword({ email, password })

    if (error) {
      recordFailedAttempt(ip)
      return NextResponse.json({ error: 'Invalid credentials' }, { status: 401 })
    }

    // Success — clear rate limit record
    clearAttempts(ip)

    return NextResponse.json({
      session: {
        access_token: data.session?.access_token,
        refresh_token: data.session?.refresh_token,
        expires_at: data.session?.expires_at,
        user: {
          id: data.user?.id,
          email: data.user?.email,
        },
      },
    })
  } catch {
    return NextResponse.json({ error: 'Internal server error' }, { status: 500 })
  }
}
