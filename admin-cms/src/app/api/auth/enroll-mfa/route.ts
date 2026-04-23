import { NextRequest, NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'
import { isAdminEmail } from '@/lib/auth'
import { parseJson } from '@/lib/validation'
import { z } from 'zod'

// Q2-87 (Sprint 9 2026-04-28): MFA enrollment flow for admins who have no
// verified TOTP factor yet. The client calls this AFTER a successful login
// that returned `mfa_enrollment_required: true`.
//
// Why this is a separate route (vs. doing enrollment inside login):
//   - Login's temp_token is short-lived (the same access token Supabase
//     issues on signInWithPassword). The enroll step needs the same token
//     in the Authorization header to call `supabase.auth.mfa.enroll`.
//   - Returning QR + secret from /login would baloon that response for the
//     common case (already-enrolled admin). Splitting keeps /login tiny.
//   - Clients can retry enrollment independently from the password step —
//     e.g. if the user dismisses the QR sheet and reopens it — without
//     forcing them to re-enter the password.

const enrollSchema = z.object({
    temp_token: z.string().min(1, 'Required'),
    pending_factor_id: z.string().uuid().nullable().optional(),
})

export async function POST(req: NextRequest) {
    try {
        const parsed = await parseJson(req, enrollSchema)
        if (!parsed.ok) return parsed.response
        const { temp_token, pending_factor_id } = parsed.data

        const supabase = createClient(
            process.env.NEXT_PUBLIC_SUPABASE_URL!,
            process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
            { global: { headers: { Authorization: `Bearer ${temp_token}` } } },
        )

        const { data: userResult } = await supabase.auth.getUser(temp_token)
        if (!userResult.user?.email || !isAdminEmail(userResult.user.email)) {
            return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
        }

        // If login discovered a half-enrolled factor, unenroll it before
        // starting over — Supabase rejects a second `enroll` call while a
        // pending factor exists, and we'd otherwise leak orphan factors every
        // time the admin bails out mid-flow.
        if (pending_factor_id) {
            await supabase.auth.mfa.unenroll({ factorId: pending_factor_id })
        }

        const friendlyName = `Fit33 Admin (${new Date().toISOString().slice(0, 10)})`
        const { data: enrolled, error: enrollErr } = await supabase.auth.mfa.enroll({
            factorType: 'totp',
            friendlyName,
        })

        if (enrollErr || !enrolled) {
            return NextResponse.json(
                { error: enrollErr?.message || 'Failed to start MFA enrollment' },
                { status: 500 },
            )
        }

        return NextResponse.json({
            factor_id: enrolled.id,
            qr_code: enrolled.totp.qr_code,
            secret: enrolled.totp.secret,
            uri: enrolled.totp.uri,
        })
    } catch {
        return NextResponse.json({ error: 'Internal server error' }, { status: 500 })
    }
}
