import { createAdminClient } from './supabase-admin'

// Shared, cross-instance rate limiter (PR-38, 2026-07-30).
//
// Vercel runs this app across multiple serverless isolates, so the old
// per-module `Map` limiters only counted requests that happened to land on
// the same instance — an attacker spreading requests across isolates
// bypassed them entirely. This limiter is backed by the `check_rate_limit`
// Postgres RPC (migration #206): a sliding-window check-and-record on the
// service-role-only `rate_limit_events` table, shared by every instance
// (and by the send-push-notification edge function).
//
// If the RPC is unreachable (migration not yet deployed / transient DB
// error) we fall back to the legacy in-memory window so protection never
// drops below the pre-#206 status quo.

export type RateCheck = { allowed: boolean; retryAfter?: number }

const fallbackBuckets = new Map<string, { count: number; resetAt: number }>()

function fallbackCheck(scope: string, key: string, max: number, windowSeconds: number): RateCheck {
  const bucketKey = `${scope}:${key}`
  const now = Date.now()
  const bucket = fallbackBuckets.get(bucketKey)

  if (!bucket || now > bucket.resetAt) {
    fallbackBuckets.set(bucketKey, { count: 1, resetAt: now + windowSeconds * 1000 })
    return { allowed: true }
  }
  if (bucket.count >= max) {
    return { allowed: false, retryAfter: Math.ceil((bucket.resetAt - now) / 1000) }
  }
  bucket.count++
  return { allowed: true }
}

// Opportunistic sweep of expired fallback buckets (no setInterval — timers
// are unreliable in serverless; sweeping on access is enough for a fallback).
function sweepFallback() {
  if (fallbackBuckets.size < 1000) return
  const now = Date.now()
  for (const [key, bucket] of fallbackBuckets) {
    if (now > bucket.resetAt) fallbackBuckets.delete(key)
  }
}

/**
 * Check-and-record one event against the shared sliding window.
 * Returns `{ allowed: false, retryAfter }` when the caller is over budget.
 */
export async function checkSharedRateLimit(
  scope: string,
  key: string,
  max: number,
  windowSeconds: number,
): Promise<RateCheck> {
  sweepFallback()
  try {
    const admin = createAdminClient()
    const { data, error } = await admin.rpc('check_rate_limit', {
      p_scope: scope,
      p_key: key,
      p_max: max,
      p_window_seconds: windowSeconds,
    })
    if (error) throw error
    if (data === false) {
      return { allowed: false, retryAfter: windowSeconds }
    }
    return { allowed: true }
  } catch (err) {
    console.warn(
      `[rate-limit] shared store unavailable for scope=${scope} — using in-memory fallback:`,
      err instanceof Error ? err.message : err,
    )
    return fallbackCheck(scope, key, max, windowSeconds)
  }
}
