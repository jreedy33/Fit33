import { NextRequest, NextResponse } from 'next/server'
import { verifyAdmin } from '@/lib/verify-admin'
import { createAdminClient } from '@/lib/supabase-admin'

// Admin allowlist <-> Supabase user drift report.
//
// Why this exists: see scripts/admin-audit.mjs and admin-cms/RECOVERY.md.
// The CLI script handles the "I am locked out" case (run from your laptop
// against the .env.local service-role key). This endpoint handles the
// "I am logged in and want to make sure my COWORKERS aren't about to be
// locked out" case — same audit, surfaced in the CMS so you can wire it
// into a dashboard widget if you ever want to.
//
// Hard requirements:
//   - Admin-gated. The audit reveals every email in ADMIN_EMAILS plus the
//     existence and MFA state of each Supabase auth.users row. That is
//     PII-grade information. verifyAdmin() rejects unauthenticated requests
//     and rejects cookies whose user is not in ADMIN_EMAILS.
//   - Service-role-only inside. We use createAdminClient() rather than the
//     anon client so we can enumerate users and their MFA factors without
//     RLS getting in the way. The service key never leaves the server.
//   - Read-only. No mutations. If you need a mutating endpoint (clear MFA,
//     reset password), wire that explicitly with a confirmation prompt;
//     don't bury it inside /health.

export const dynamic = 'force-dynamic'

type AdminUserRow = {
    id: string
    email?: string
    email_confirmed_at?: string | null
    banned_until?: string | null
}

type FactorRow = {
    id: string
    factor_type?: string
    status?: string
}

type AuditRow = {
    email: string
    status: 'OK' | 'NO_USER' | 'NO_MFA' | 'UNVERIFIED' | 'BANNED' | 'UNCONFIRMED'
    detail: string
    user_id?: string
}

export async function GET(req: NextRequest) {
    const auth = await verifyAdmin(req)
    if (!auth.valid) {
        return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
    }

    try {
        const allowlist = (process.env.ADMIN_EMAILS || '')
            .split(',')
            .map(s => s.trim().toLowerCase())
            .filter(Boolean)

        if (allowlist.length === 0) {
            return NextResponse.json({
                ok: false,
                drift: 1,
                warn: 0,
                rows: [{ email: '(none)', status: 'NO_USER', detail: 'ADMIN_EMAILS env var is empty' }],
            })
        }

        const admin = createAdminClient()
        // Pull all users in a single page — Sprint-9 era, the project has ~40
        // users so per_page=1000 covers us comfortably. If we ever cross 1000,
        // upgrade to paginated. (Same caveat as the CLI script.)
        const { data, error } = await admin.auth.admin.listUsers({ page: 1, perPage: 1000 })
        if (error) {
            console.error('[admin/health] listUsers failed:', error.message)
            return NextResponse.json({ error: 'Audit failed' }, { status: 500 })
        }

        const byEmail = new Map<string, AdminUserRow>()
        for (const u of data.users as AdminUserRow[]) {
            if (u.email) byEmail.set(u.email.toLowerCase(), u)
        }

        const rows: AuditRow[] = []
        let drift = 0
        let warn = 0

        for (const email of allowlist) {
            const u = byEmail.get(email)
            if (!u) {
                rows.push({ email, status: 'NO_USER', detail: 'no Supabase auth.users row — login will always fail' })
                drift += 1
                continue
            }
            if (u.banned_until) {
                rows.push({ email, status: 'BANNED', detail: `banned_until=${u.banned_until}`, user_id: u.id })
                drift += 1
                continue
            }
            if (!u.email_confirmed_at) {
                rows.push({ email, status: 'UNCONFIRMED', detail: 'email_confirmed_at is null', user_id: u.id })
                drift += 1
                continue
            }
            // Service-role admin client lets us list factors directly per user.
            // The supabase-js typing for `mfa.listFactors` on the admin client
            // is `{ userId }`-shaped in v2.x.
            const { data: factorData } = await admin.auth.admin.mfa.listFactors({ userId: u.id })
            const factors = (factorData?.factors || []) as FactorRow[]
            const verifiedTotp = factors.find(f => f.factor_type === 'totp' && f.status === 'verified')
            const pendingTotp = factors.find(f => f.factor_type === 'totp' && f.status !== 'verified')
            if (verifiedTotp) {
                rows.push({ email, status: 'OK', detail: `mfa=verified factors=${factors.length}`, user_id: u.id })
            } else if (pendingTotp) {
                rows.push({ email, status: 'UNVERIFIED', detail: 'half-enrolled factor pending — finish QR flow on next login', user_id: u.id })
                warn += 1
            } else {
                rows.push({ email, status: 'NO_MFA', detail: 'Sprint-9 enforcement will force enrollment on next login', user_id: u.id })
                warn += 1
            }
        }

        return NextResponse.json({
            ok: drift === 0 && warn === 0,
            project: process.env.NEXT_PUBLIC_SUPABASE_URL,
            drift,
            warn,
            rows,
            checked_at: new Date().toISOString(),
        })
    } catch (err) {
        console.error('[admin/health] error:', err)
        return NextResponse.json({ error: 'Internal server error' }, { status: 500 })
    }
}
