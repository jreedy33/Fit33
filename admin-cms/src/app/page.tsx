import { cookies } from 'next/headers'
import { redirect } from 'next/navigation'

// Sprint 4 (Q2-21): server component. Reads the httpOnly `admin_access_token`
// cookie directly so we never expose a client-visible login flag. Middleware
// skips `/`, so this is the only page that has to make its own auth decision.
export default async function Home() {
  const cookieStore = await cookies()
  const hasAccessToken = Boolean(cookieStore.get('admin_access_token')?.value)
  redirect(hasAccessToken ? '/dashboard' : '/login')
}
