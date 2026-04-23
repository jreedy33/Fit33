import { NextResponse } from 'next/server'
import type { NextRequest } from 'next/server'

// Admin cookies are scoped tightly: httpOnly (no JS read), Secure in prod,
// SameSite=Strict so the session is never sent on cross-site navigations
// (anti-CSRF). Per INFRA_SECURITY invariant #22 + admin-cms-rules.
const COOKIE_OPTIONS = {
  httpOnly: true,
  secure: process.env.NODE_ENV === 'production',
  sameSite: 'strict' as const,
  path: '/',
}

const ACCESS_TOKEN_MAX_AGE = 60 * 60         // 1 hour
const REFRESH_TOKEN_MAX_AGE = 60 * 60 * 24 * 7  // 7 days

export function setAuthCookies(
  response: NextResponse,
  tokens: { accessToken: string; refreshToken: string; expiresAt: number },
) {
  response.cookies.set('admin_access_token', tokens.accessToken, {
    ...COOKIE_OPTIONS,
    maxAge: ACCESS_TOKEN_MAX_AGE,
  })
  response.cookies.set('admin_refresh_token', tokens.refreshToken, {
    ...COOKIE_OPTIONS,
    maxAge: REFRESH_TOKEN_MAX_AGE,
  })
  response.cookies.set('admin_expires_at', String(tokens.expiresAt), {
    ...COOKIE_OPTIONS,
    maxAge: ACCESS_TOKEN_MAX_AGE,
  })
  // Sprint 4 (Q2-21): `admin_logged_in` is now httpOnly. The middleware +
  // `/api/auth/session` already enforce auth on every protected route, and
  // `/` (the only path middleware skips) is now a server component that
  // reads cookies server-side via `next/headers`. No client-side JS reads
  // this cookie — it is retained only because `clearAuthCookies()` still
  // sweeps it on logout and some production browsers may still have the
  // non-httpOnly version set.
  response.cookies.set('admin_logged_in', '1', {
    httpOnly: true,
    secure: process.env.NODE_ENV === 'production',
    sameSite: 'strict',
    path: '/',
    maxAge: REFRESH_TOKEN_MAX_AGE,
  })
}

export function clearAuthCookies(response: NextResponse) {
  for (const name of ['admin_access_token', 'admin_refresh_token', 'admin_expires_at', 'admin_logged_in']) {
    response.cookies.set(name, '', { ...COOKIE_OPTIONS, maxAge: 0 })
  }
}

export function getAccessToken(req: NextRequest): string | undefined {
  return req.cookies.get('admin_access_token')?.value
}

export function getRefreshToken(req: NextRequest): string | undefined {
  return req.cookies.get('admin_refresh_token')?.value
}

export function getExpiresAt(req: NextRequest): number {
  return Number(req.cookies.get('admin_expires_at')?.value || '0')
}

export function isTokenExpiring(req: NextRequest): boolean {
  const expiresAt = getExpiresAt(req)
  if (!expiresAt) return false
  return Date.now() / 1000 > expiresAt - 300
}
