import { NextResponse } from 'next/server'
import type { NextRequest } from 'next/server'

export function middleware(request: NextRequest) {
  const { pathname } = request.nextUrl

  if (
    pathname === '/login' ||
    pathname.startsWith('/api/auth') ||
    pathname.startsWith('/_next') ||
    pathname.startsWith('/favicon') ||
    pathname === '/'
  ) {
    return NextResponse.next()
  }

  // API routes validate the httpOnly cookie in their own handler
  if (pathname.startsWith('/api/')) {
    return NextResponse.next()
  }

  const hasToken = request.cookies.get('admin_access_token')?.value
  if (!hasToken) {
    return NextResponse.redirect(new URL('/login', request.url))
  }

  const response = NextResponse.next()

  response.headers.set('X-Frame-Options', 'DENY')
  response.headers.set('X-Content-Type-Options', 'nosniff')
  response.headers.set('Referrer-Policy', 'strict-origin-when-cross-origin')
  response.headers.set('X-XSS-Protection', '1; mode=block')
  response.headers.set(
    'Content-Security-Policy',
    "default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:; media-src 'self' https://pub-7838a3e2cbc24d59a6c4d2b2d6239bea.r2.dev; connect-src 'self' https://*.supabase.co wss://*.supabase.co https://pub-7838a3e2cbc24d59a6c4d2b2d6239bea.r2.dev; font-src 'self' data:; frame-ancestors 'none'"
  )

  return response
}

export const config = {
  matcher: ['/((?!_next/static|_next/image|favicon.ico).*)'],
}
