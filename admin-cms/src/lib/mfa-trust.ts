import { NextResponse } from 'next/server'
import type { NextRequest } from 'next/server'
import { createHmac, timingSafeEqual } from 'crypto'

// "Trust this device" cookie for admin TOTP. After a successful MFA
// verification we issue a signed cookie tying the browser to the verified
// admin's Supabase user ID for 30 days. On subsequent logins, if the password
// succeeds AND a valid trust cookie for the SAME user is present, we skip the
// 6-digit TOTP step. This is the same pattern GitHub / Google / 1Password use
// to keep MFA from being a chore on personal hardware.
//
// Threat model + why this is safe:
//   - The cookie is httpOnly + Secure + SameSite=Strict, so JS can't read it
//     and it's never sent on cross-site navigations.
//   - The cookie value is HMAC-SHA256(payload, SUPABASE_SERVICE_ROLE_KEY).
//     We verify with timing-safe equality. An attacker without the service
//     role key cannot forge a trust cookie.
//   - The cookie is bound to a specific `user_id`. Stealing it doesn't help
//     unless the attacker also knows the matching admin's password.
//   - If the service role key is rotated, every trust cookie immediately
//     becomes invalid — admins re-MFA once and the new cookies are signed
//     with the new key. This is the desired behavior on key rotation.

export const TRUST_COOKIE_NAME = 'admin_mfa_trust'
const TRUST_TTL_SECONDS = 60 * 60 * 24 * 30  // 30 days

const COOKIE_OPTIONS = {
  httpOnly: true,
  secure: process.env.NODE_ENV === 'production',
  sameSite: 'strict' as const,
  path: '/',
}

function getSecret(): string {
  const secret = process.env.SUPABASE_SERVICE_ROLE_KEY
  if (!secret) {
    throw new Error('SUPABASE_SERVICE_ROLE_KEY is required for MFA trust cookie signing')
  }
  return secret
}

function b64urlEncode(buf: Buffer): string {
  return buf.toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')
}

function b64urlDecode(s: string): Buffer {
  const pad = s.length % 4 === 0 ? '' : '='.repeat(4 - (s.length % 4))
  return Buffer.from(s.replace(/-/g, '+').replace(/_/g, '/') + pad, 'base64')
}

type TrustPayload = {
  user_id: string
  expires_at: number
}

function sign(payloadB64: string): string {
  const mac = createHmac('sha256', getSecret()).update(payloadB64).digest()
  return b64urlEncode(mac)
}

function buildToken(payload: TrustPayload): string {
  const payloadB64 = b64urlEncode(Buffer.from(JSON.stringify(payload)))
  const sig = sign(payloadB64)
  return `${payloadB64}.${sig}`
}

function parseToken(token: string): TrustPayload | null {
  const dot = token.indexOf('.')
  if (dot < 0) return null
  const payloadB64 = token.slice(0, dot)
  const sig = token.slice(dot + 1)
  const expectedSig = sign(payloadB64)

  const sigBuf = Buffer.from(sig, 'utf8')
  const expectedBuf = Buffer.from(expectedSig, 'utf8')
  if (sigBuf.length !== expectedBuf.length) return null
  if (!timingSafeEqual(sigBuf, expectedBuf)) return null

  try {
    const decoded = JSON.parse(b64urlDecode(payloadB64).toString('utf8')) as TrustPayload
    if (typeof decoded.user_id !== 'string' || typeof decoded.expires_at !== 'number') return null
    return decoded
  } catch {
    return null
  }
}

export function setMfaTrustCookie(response: NextResponse, userId: string) {
  const payload: TrustPayload = {
    user_id: userId,
    expires_at: Math.floor(Date.now() / 1000) + TRUST_TTL_SECONDS,
  }
  response.cookies.set(TRUST_COOKIE_NAME, buildToken(payload), {
    ...COOKIE_OPTIONS,
    maxAge: TRUST_TTL_SECONDS,
  })
}

export function clearMfaTrustCookie(response: NextResponse) {
  response.cookies.set(TRUST_COOKIE_NAME, '', { ...COOKIE_OPTIONS, maxAge: 0 })
}

// Returns true if the request carries a valid, unexpired trust cookie for
// this exact user. Any tampering, expiration, or user-id mismatch returns
// false (and the caller should fall through to the normal TOTP prompt).
export function isMfaTrustedForUser(req: NextRequest, userId: string): boolean {
  const token = req.cookies.get(TRUST_COOKIE_NAME)?.value
  if (!token) return false

  const payload = parseToken(token)
  if (!payload) return false
  if (payload.user_id !== userId) return false
  if (payload.expires_at <= Math.floor(Date.now() / 1000)) return false

  return true
}
