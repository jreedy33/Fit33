import { NextRequest, NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'
import { isAdminEmail } from '@/lib/auth'
import { parseJson, loginSchema } from '@/lib/validation'
import { setAuthCookies } from '@/lib/auth-cookies'
import { isMfaTrustedForUser } from '@/lib/mfa-trust'

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

    const parsed = await parseJson(req, loginSchema)
    if (!parsed.ok) return parsed.response
    const { email, password } = parsed.data

    // 2026-04-29 lockout post-mortem: the client always sees a generic
    // "Invalid credentials" (intentional — prevents account enumeration), but
    // the server logs the exact reason so we can debug a stuck CEO without
    // having to resort to running `npm run admin:audit` blind. The two log
    // lines below are the ONLY place the failure mode is distinguished. Do
    // not surface either of these reasons in the API response.
    if (!isAdminEmail(email)) {
      console.warn(`[auth/login] reject reason=NOT_ALLOWLISTED email=${email} ip=${ip}`)
      recordFailedAttempt(ip)
      return NextResponse.json({ error: 'Invalid credentials' }, { status: 401 })
    }

    const supabase = createClient(
      process.env.NEXT_PUBLIC_SUPABASE_URL!,
      process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    )

    const { data, error } = await supabase.auth.signInWithPassword({ email, password })

    if (error || !data.session) {
      // Supabase deliberately returns the same error code for "user does not
      // exist" and "wrong password" — we just propagate the message it gave
      // us so /var/log shows e.g. "Invalid login credentials" vs
      // "Email not confirmed". Run `npm run admin:audit` if you need to know
      // whether the user row actually exists.
      console.warn(`[auth/login] reject reason=SUPABASE_AUTH_FAILED email=${email} ip=${ip} supabase_error=${error?.message ?? 'no_session_returned'}`)
      recordFailedAttempt(ip)
      return NextResponse.json({ error: 'Invalid credentials' }, { status: 401 })
    }

    clearAttempts(ip)

    const authedClient = createClient(
      process.env.NEXT_PUBLIC_SUPABASE_URL!,
      process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
      { global: { headers: { Authorization: `Bearer ${data.session.access_token}` } } },
    )

    // Q2-87 (Sprint 9 2026-04-28): Enforce MFA for all admins.
    //
    // Pre-Sprint-9 behavior:
    //   - If the account had a verified TOTP factor, we prompted for it.
    //   - If the account had NO factor, we authenticated the admin directly.
    //
    // The second branch meant any admin who never enrolled MFA could sign in
    // with just email + password — a hole the phishing / credential-stuffing
    // bar trivially clears. We now require every admin to either verify an
    // existing factor OR enroll a new one before we set auth cookies.
    const { data: factors } = await authedClient.auth.mfa.listFactors()
    const verifiedTotp = factors?.totp?.find(f => f.status === 'verified')
    const pendingTotp = factors?.totp?.find(f => f.status !== 'verified')

    if (verifiedTotp) {
      // Q2-92 (Sprint 9, 2026-04-29): "Trust this device for 30 days" — if the
      // browser presents a valid HMAC-signed `admin_mfa_trust` cookie tied to
      // THIS user's UUID, skip the TOTP prompt and set auth cookies directly.
      // The trust cookie is only ever issued by /api/auth/verify-mfa after a
      // successful 6-digit code entry, so the cookie's existence proves this
      // browser was once paired with a verified second factor for this admin.
      // Stealing the cookie alone doesn't help an attacker — they'd also need
      // the password (and the cookie is httpOnly + SameSite=Strict). This
      // matches GitHub / Google's "remember this device" UX.
      if (data.user?.id && isMfaTrustedForUser(req, data.user.id)) {
        const response = NextResponse.json({
          mfa_skipped: true,
          user: { id: data.user.id, email: data.user.email },
        })
        setAuthCookies(response, {
          accessToken: data.session.access_token,
          refreshToken: data.session.refresh_token,
          expiresAt: data.session.expires_at ?? 0,
        })
        return response
      }

      return NextResponse.json({
        mfa_required: true,
        factor_id: verifiedTotp.id,
        temp_token: data.session.access_token,
        temp_refresh: data.session.refresh_token,
        temp_expires: data.session.expires_at ?? 0,
      })
    }

    // No verified factor → force enrollment. We intentionally do NOT set auth
    // cookies here; the client has to round-trip through /api/auth/enroll-mfa
    // and /api/auth/verify-mfa before the session becomes usable.
    //
    // If a half-enrolled factor exists (status === 'unverified'), reuse it so
    // we don't pile up dangling TOTP factors on every retry.
    return NextResponse.json({
      mfa_enrollment_required: true,
      pending_factor_id: pendingTotp?.id ?? null,
      temp_token: data.session.access_token,
      temp_refresh: data.session.refresh_token,
      temp_expires: data.session.expires_at ?? 0,
      email: data.user?.email,
    })
  } catch {
    return NextResponse.json({ error: 'Internal server error' }, { status: 500 })
  }
}
