import { NextRequest, NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'
import { isAdminEmail } from '@/lib/auth'
import { getRefreshToken, setAuthCookies, clearAuthCookies } from '@/lib/auth-cookies'

export async function POST(req: NextRequest) {
  const refreshToken = getRefreshToken(req)
  if (!refreshToken) {
    const res = NextResponse.json({ error: 'No refresh token' }, { status: 401 })
    clearAuthCookies(res)
    return res
  }

  const supabase = createClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
  )

  const { data, error } = await supabase.auth.refreshSession({ refresh_token: refreshToken })
  if (error || !data.session) {
    const res = NextResponse.json({ error: 'Refresh failed' }, { status: 401 })
    clearAuthCookies(res)
    return res
  }

  // 2026-07-30: re-check the allowlist on every refresh. Without this, an
  // admin removed from ADMIN_EMAILS keeps a working session for up to the
  // 7-day refresh-token lifetime — login is the only other place the
  // allowlist was consulted.
  const refreshedEmail = data.user?.email ?? data.session.user?.email
  if (!refreshedEmail || !isAdminEmail(refreshedEmail)) {
    console.warn(`[auth/refresh] reject reason=NOT_ALLOWLISTED email=${refreshedEmail ?? 'unknown'}`)
    const res = NextResponse.json({ error: 'Refresh failed' }, { status: 401 })
    clearAuthCookies(res)
    return res
  }

  const response = NextResponse.json({ ok: true })
  setAuthCookies(response, {
    accessToken: data.session.access_token,
    refreshToken: data.session.refresh_token,
    expiresAt: data.session.expires_at ?? 0,
  })
  return response
}
