#!/usr/bin/env node
// Admin allowlist <-> Supabase user drift detector.
//
// Why this exists:
//   On 2026-04-29 the CEO got locked out of the production admin CMS because
//   his email was in ADMIN_EMAILS but no Supabase `auth.users` row existed at
//   that email. The login route returns a generic "Invalid credentials" for
//   both "email not allowlisted" AND "Supabase rejected password" (intentional
//   — prevents account enumeration), so the failure mode was opaque.
//
//   This script audits every email in ADMIN_EMAILS against the live Supabase
//   project and reports drift. Run it whenever you add an admin, rotate keys,
//   change projects, or hit a mysterious "Invalid credentials" loop.
//
// Usage (from admin-cms/):
//   npm run admin:audit
//
// Exit codes:
//   0  All allowlisted emails resolve to a Supabase user with verified MFA.
//   1  At least one drift / warning found (see report).
//   2  Setup error (missing env vars, network failure, etc.).
//
// Reads env from .env.local via Node's built-in `--env-file` flag (see the
// package.json script). No dotenv dependency.

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL
const SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY
const ADMIN_EMAILS_RAW = process.env.ADMIN_EMAILS || ''

function fail(code, msg) {
    console.error(`[admin-audit] ${msg}`)
    process.exit(code)
}

if (!SUPABASE_URL) fail(2, 'NEXT_PUBLIC_SUPABASE_URL is not set. Did you run via `npm run admin:audit` from admin-cms/?')
if (!SERVICE_KEY) fail(2, 'SUPABASE_SERVICE_ROLE_KEY is not set.')

const allowlist = ADMIN_EMAILS_RAW.split(',').map(s => s.trim().toLowerCase()).filter(Boolean)
if (allowlist.length === 0) fail(2, 'ADMIN_EMAILS is empty. No admins to audit.')

async function fetchAllUsers() {
    const out = []
    let page = 1
    const perPage = 1000
    for (;;) {
        const url = `${SUPABASE_URL}/auth/v1/admin/users?page=${page}&per_page=${perPage}`
        const res = await fetch(url, {
            headers: {
                apikey: SERVICE_KEY,
                Authorization: `Bearer ${SERVICE_KEY}`,
            },
        })
        if (!res.ok) {
            const body = await res.text().catch(() => '')
            fail(2, `Supabase admin API error ${res.status}: ${body.slice(0, 200)}`)
        }
        const data = await res.json()
        const batch = Array.isArray(data) ? data : (data.users || [])
        out.push(...batch)
        if (batch.length < perPage) break
        page += 1
        if (page > 50) break // safety: 50k users
    }
    return out
}

async function fetchFactorsForUser(userId) {
    const res = await fetch(`${SUPABASE_URL}/auth/v1/admin/users/${userId}/factors`, {
        headers: {
            apikey: SERVICE_KEY,
            Authorization: `Bearer ${SERVICE_KEY}`,
        },
    })
    if (!res.ok) return []
    const data = await res.json().catch(() => ({}))
    const factors = Array.isArray(data) ? data : (data.factors || [])
    return factors
}

const STATUS = {
    OK: { label: 'OK         ', color: '\x1b[32m' },
    NO_USER: { label: 'NO_USER    ', color: '\x1b[31m' },
    NO_MFA: { label: 'NO_MFA     ', color: '\x1b[33m' },
    UNVERIFIED: { label: 'UNVERIFIED ', color: '\x1b[33m' },
    BANNED: { label: 'BANNED     ', color: '\x1b[31m' },
    UNCONFIRMED: { label: 'UNCONFIRMED', color: '\x1b[33m' },
}
const RESET = '\x1b[0m'

function paint(s, color) {
    return process.stdout.isTTY ? `${color}${s}${RESET}` : s
}

console.log('')
console.log(`Project:   ${SUPABASE_URL}`)
console.log(`Allowlist: ADMIN_EMAILS = ${allowlist.length} entries`)
console.log('')

const users = await fetchAllUsers()
const byEmail = new Map()
for (const u of users) {
    if (u.email) byEmail.set(u.email.toLowerCase(), u)
}

let drift = 0
let warn = 0

const rows = []
for (const email of allowlist) {
    const u = byEmail.get(email)
    if (!u) {
        rows.push({ email, status: STATUS.NO_USER, detail: 'no Supabase auth.users row — login will always fail' })
        drift += 1
        continue
    }
    if (u.banned_until) {
        rows.push({ email, status: STATUS.BANNED, detail: `banned_until=${u.banned_until}` })
        drift += 1
        continue
    }
    if (!u.email_confirmed_at) {
        rows.push({ email, status: STATUS.UNCONFIRMED, detail: 'email_confirmed_at is null — Supabase will reject sign-in' })
        drift += 1
        continue
    }
    const factors = await fetchFactorsForUser(u.id)
    const verifiedTotp = factors.find(f => f.factor_type === 'totp' && f.status === 'verified')
    const pendingTotp = factors.find(f => f.factor_type === 'totp' && f.status !== 'verified')
    if (verifiedTotp) {
        rows.push({ email, status: STATUS.OK, detail: `id=${u.id} mfa=verified factors=${factors.length}` })
    } else if (pendingTotp) {
        rows.push({ email, status: STATUS.UNVERIFIED, detail: `id=${u.id} half-enrolled factor pending — finish QR flow on next login` })
        warn += 1
    } else {
        rows.push({ email, status: STATUS.NO_MFA, detail: `id=${u.id} — Sprint-9 enforcement will force enrollment on next login` })
        warn += 1
    }
}

const widthEmail = Math.max(...rows.map(r => r.email.length), 'EMAIL'.length)
console.log(`${'EMAIL'.padEnd(widthEmail)}  STATUS       DETAIL`)
console.log(`${'-'.repeat(widthEmail)}  -----------  ${'-'.repeat(60)}`)
for (const r of rows) {
    const status = paint(r.status.label, r.status.color)
    console.log(`${r.email.padEnd(widthEmail)}  ${status}  ${r.detail}`)
}

console.log('')
if (drift > 0) {
    console.error(paint(`DRIFT: ${drift} allowlist entr${drift === 1 ? 'y' : 'ies'} cannot log in. See admin-cms/RECOVERY.md.`, STATUS.NO_USER.color))
    process.exit(1)
}
if (warn > 0) {
    console.warn(paint(`WARN: ${warn} entr${warn === 1 ? 'y' : 'ies'} need MFA enrollment on next login. Not blocking.`, STATUS.NO_MFA.color))
    process.exit(1)
}
console.log(paint('All admin allowlist entries resolve to a Supabase user with verified MFA.', STATUS.OK.color))
process.exit(0)
