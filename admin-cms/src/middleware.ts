import { NextResponse } from 'next/server'
import type { NextRequest } from 'next/server'

// Sprint 5 (Q2-20): nonce-based CSP. Every request gets a fresh 128-bit nonce
// exposed to Next via the `x-nonce` request header; Next automatically attaches
// `nonce={nonce}` to its hydration <script> tags. The response CSP then trusts
// `'nonce-{nonce}'` + `'strict-dynamic'` instead of the old `'unsafe-inline'`
// + `'unsafe-eval'` blanket allow. Dev keeps `'unsafe-eval'` because Next HMR
// uses `eval()`; production drops it entirely. `style-src` still needs
// `'unsafe-inline'` (Tailwind JIT + Next/React inline styles) — a separate
// follow-up will migrate styles to nonces.
function buildCsp(nonce: string): string {
  const isDev = process.env.NODE_ENV !== 'production'

  const scriptSrc = [
    "'self'",
    `'nonce-${nonce}'`,
    "'strict-dynamic'",
    isDev ? "'unsafe-eval'" : null,
  ]
    .filter(Boolean)
    .join(' ')

  return [
    "default-src 'self'",
    `script-src ${scriptSrc}`,
    "style-src 'self' 'unsafe-inline'",
    "img-src 'self' data: https:",
    "font-src 'self' data:",
    "media-src 'self' https://pub-7838a3e2cbc24d59a6c4d2b2d6239bea.r2.dev",
    "connect-src 'self' https://*.supabase.co wss://*.supabase.co https://pub-7838a3e2cbc24d59a6c4d2b2d6239bea.r2.dev",
    "frame-ancestors 'none'",
    "base-uri 'self'",
    "form-action 'self'",
    "upgrade-insecure-requests",
  ].join('; ')
}

function applySecurityHeaders(response: NextResponse, csp: string): NextResponse {
  response.headers.set('Content-Security-Policy', csp)
  response.headers.set('X-Frame-Options', 'DENY')
  response.headers.set('X-Content-Type-Options', 'nosniff')
  response.headers.set('Referrer-Policy', 'strict-origin-when-cross-origin')
  response.headers.set('X-XSS-Protection', '1; mode=block')
  return response
}

export function middleware(request: NextRequest) {
  const { pathname } = request.nextUrl

  const nonceBytes = new Uint8Array(16)
  crypto.getRandomValues(nonceBytes)
  const nonce = Buffer.from(nonceBytes).toString('base64')
  const csp = buildCsp(nonce)

  const requestHeaders = new Headers(request.headers)
  requestHeaders.set('x-nonce', nonce)
  requestHeaders.set('content-security-policy', csp)

  const passthrough = () =>
    applySecurityHeaders(
      NextResponse.next({ request: { headers: requestHeaders } }),
      csp,
    )

  if (
    pathname === '/login' ||
    pathname.startsWith('/api/auth') ||
    pathname.startsWith('/_next') ||
    pathname.startsWith('/favicon') ||
    pathname === '/'
  ) {
    return passthrough()
  }

  if (pathname.startsWith('/api/')) {
    return passthrough()
  }

  const hasToken = request.cookies.get('admin_access_token')?.value
  if (!hasToken) {
    return applySecurityHeaders(
      NextResponse.redirect(new URL('/login', request.url)),
      csp,
    )
  }

  return passthrough()
}

export const config = {
  matcher: ['/((?!_next/static|_next/image|favicon.ico).*)'],
}
