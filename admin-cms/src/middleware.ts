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

  // For page routes, check that the auth cookie exists.
  // The actual token validation happens in AdminShell via /api/auth/session,
  // but this prevents unauthenticated users from even loading the page shell.
  const hasToken = request.cookies.get('admin_access_token')?.value
  if (!hasToken) {
    return NextResponse.redirect(new URL('/login', request.url))
  }

  return NextResponse.next()
}

export const config = {
  matcher: ['/((?!_next/static|_next/image|favicon.ico).*)'],
}
