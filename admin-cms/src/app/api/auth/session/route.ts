import { NextRequest, NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'
import { getAccessToken } from '@/lib/auth-cookies'
import { isAdminEmail } from '@/lib/auth'

export async function GET(req: NextRequest) {
  const token = getAccessToken(req)
  if (!token) {
    return NextResponse.json({ authenticated: false }, { status: 401 })
  }

  const supabase = createClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
  )

  const { data: { user }, error } = await supabase.auth.getUser(token)
  if (error || !user?.email || !isAdminEmail(user.email)) {
    return NextResponse.json({ authenticated: false }, { status: 401 })
  }

  return NextResponse.json({
    authenticated: true,
    user: { id: user.id, email: user.email },
  })
}
