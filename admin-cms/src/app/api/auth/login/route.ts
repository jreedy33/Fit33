import { NextRequest, NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'
import { isAdminEmail } from '@/lib/auth'
import { parseJson, loginSchema } from '@/lib/validation'
import { setAuthCookies } from '@/lib/auth-cookies'
import { isMfaTrustedForUser } from '@/lib/mfa-trust'
import { checkSharedRateLimit } from '@/lib/rate-limit'
import { createAdminClient } from '@/lib/supabase-admin'

// PR-38 (2026-07-30): rate limiting moved to the shared cross-instance store
// (`@/lib/rate-limit`, Postgres-backed via migration #206). The old
// per-module Map only counted requests landing on the same Vercel isolate.
//
// Two layers, preserving the original semantics ("5 FAILED attempts per
// 15 min per IP" — successful logins never consume budget):
//   1. Flood cap: 30 total attempts / 15 min / IP (records every request).
//   2. Failure lockout: 5 recorded `cms_login_fail` events / 15 min / IP,
//      counted with a read-only peek so the pre-check itself records nothing.
const MAX_FAILED_ATTEMPTS = 5
const WINDOW_SECONDS = 15 * 60
const FLOOD_MAX_ATTEMPTS = 30

// Records one failed attempt in the shared store. Fire-and-forget — the
// return value is irrelevant here, we only want the event row.
async function recordFailedAttempt(ip: string) {
  await checkSharedRateLimit('cms_login_fail', ip, Number.MAX_SAFE_INTEGER, WINDOW_SECONDS)
}

// Read-only count of recent failures (no event recorded). Falls back to
// "not locked" if the store is unreachable — the flood cap still applies.
async function isLockedOut(ip: string): Promise<boolean> {
  try {
    const admin = createAdminClient()
    const { count, error } = await admin
      .from('rate_limit_events')
      .select('id', { count: 'exact', head: true })
      .eq('scope', 'cms_login_fail')
      .eq('key', ip)
      .gte('created_at', new Date(Date.now() - WINDOW_SECONDS * 1000).toISOString())
    if (error) throw error
    return (count ?? 0) >= MAX_FAILED_ATTEMPTS
  } catch {
    return false
  }
}

export async function POST(req: NextRequest) {
  try {
    const ip = req.headers.get('x-forwarded-for')?.split(',')[0]?.trim()
      || req.headers.get('x-real-ip')
      || 'unknown'

    const floodCheck = await checkSharedRateLimit('cms_login', ip, FLOOD_MAX_ATTEMPTS, WINDOW_SECONDS)
    if (!floodCheck.allowed || await isLockedOut(ip)) {
      const retryAfter = floodCheck.retryAfter ?? WINDOW_SECONDS
      return NextResponse.json(
        { error: `Too many login attempts. Try again in ${retryAfter} seconds.` },
        { status: 429, headers: { 'Retry-After': String(retryAfter) } },
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
      await recordFailedAttempt(ip)
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
      await recordFailedAttempt(ip)
      return NextResponse.json({ error: 'Invalid credentials' }, { status: 401 })
    }

    // (Legacy `clearAttempts(ip)` removed — failures age out of the shared
    // sliding window on their own; success doesn't need to reset anything.)

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
