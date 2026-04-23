import { NextRequest, NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'
import { isAdminEmail } from '@/lib/auth'
import { setAuthCookies } from '@/lib/auth-cookies'
import { parseJson, verifyMfaSchema } from '@/lib/validation'

export async function POST(req: NextRequest) {
  try {
    const parsed = await parseJson(req, verifyMfaSchema)
    if (!parsed.ok) return parsed.response
    const { factor_id, code, temp_token, temp_refresh, temp_expires } = parsed.data

    const supabase = createClient(
      process.env.NEXT_PUBLIC_SUPABASE_URL!,
      process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
      { global: { headers: { Authorization: `Bearer ${temp_token}` } } },
    )

    const { data: user } = await supabase.auth.getUser(temp_token)
    if (!user.user?.email || !isAdminEmail(user.user.email)) {
      return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
    }

    const { data: challenge, error: challengeError } = await supabase.auth.mfa.challenge({ factorId: factor_id })
    if (challengeError || !challenge) {
      return NextResponse.json({ error: 'MFA challenge failed' }, { status: 400 })
    }

    const { data: verify, error: verifyError } = await supabase.auth.mfa.verify({
      factorId: factor_id,
      challengeId: challenge.id,
      code,
    })

    if (verifyError || !verify) {
      return NextResponse.json({ error: 'Invalid verification code' }, { status: 401 })
    }

    const response = NextResponse.json({
      user: { id: user.user.id, email: user.user.email },
    })

    setAuthCookies(response, {
      accessToken: verify.access_token ?? temp_token,
      refreshToken: verify.refresh_token ?? temp_refresh,
      expiresAt: temp_expires ?? 0,
    })

    return response
  } catch {
    return NextResponse.json({ error: 'Internal server error' }, { status: 500 })
  }
}
