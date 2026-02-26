import { NextResponse } from 'next/server'
import type { NextRequest } from 'next/server'

// Middleware runs on every request to protect routes
export function middleware(request: NextRequest) {
  const { pathname } = request.nextUrl

  // Allow public routes
  if (
    pathname === '/login' ||
    pathname.startsWith('/api/auth') ||
    pathname.startsWith('/_next') ||
    pathname.startsWith('/favicon') ||
    pathname === '/'
  ) {
    return NextResponse.next()
  }

  // API routes check their own auth via Bearer token
  if (pathname.startsWith('/api/')) {
    return NextResponse.next()
  }

  // For page routes, we rely on client-side auth check (sessionStorage)
  // since middleware can't access sessionStorage.
  // The AdminShell component handles the redirect if no token.
  return NextResponse.next()
}

export const config = {
  matcher: ['/((?!_next/static|_next/image|favicon.ico).*)'],
}
