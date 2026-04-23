// supabase/functions/bug-intel-rpc-smoke
//
// SCAFFOLD — not wired into CI yet (see BUG_INTEL_BACKLOG.md T2.3 rollout).
//
// PURPOSE
// -------
// Synthetic RPC smoke test. Calls every registered Supabase RPC with a
// pre-seeded test user's fixture payload and asserts the response does NOT
// surface any of:
//   - PGRST202 ("Could not find the function")
//   - PGRST116 ("JSON object requested but multiple/0 rows returned")  — ambiguous
//   - 23xxx / 42xxx SQLSTATEs (data-integrity and schema violations)
//   - 5xx HTTP from the gateway
//
// The goal is catch-before-ship: a broken RPC signature today shows up as a
// bug_intelligence fingerprint tomorrow. Running this against preview
// environments (or nightly against production with a dedicated synthetic
// user) means the broken function is caught in minutes with a clear
// attribution (function name + params + error code) instead of waiting for
// real users to trigger it.
//
// DEPLOYMENT CHECKLIST (do before wiring into CI)
// ----------------------------------------------
//   [ ] Create a dedicated service account `smoke-test@fit33.com` in
//       user_profiles with:
//         - auth.uid() distinct from any real user
//         - realistic onboarding_completed=true, fitness_goal, etc.
//         - owned private challenge, one friendship, one workout, one weight log
//   [ ] Set SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY + SMOKE_USER_ID env vars
//       in the Supabase secrets store for this function.
//   [ ] Extend FIXTURES[] below with every RPC in supabase/functions/_shared
//       + every RPC you find via `rg -n 'CREATE .* FUNCTION' supabase/*.sql`.
//   [ ] Add a GH Actions workflow `.github/workflows/rpc-smoke.yml` that runs
//       `curl -X POST $SUPABASE_URL/functions/v1/bug-intel-rpc-smoke
//        -H "Authorization: Bearer $ANON_KEY"` nightly + on every deploy.
//   [ ] Wire failure notifications to the existing Slack / Pushover webhook.
//
// Until the checklist is complete, calling this function returns a friendly
// 503 ("not yet deployed").

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

type Fixture = {
  rpc: string
  params: Record<string, unknown>
  // `expect_error` lets us add known-error RPCs (e.g. dry-run that throws)
  // without flagging them. Default: no error expected.
  expect_error?: 'pg_code' | 'row_count' | 'none'
  // Human-readable owner — mirrors bug_intelligence_reports.agent_owner.
  owner:
    | 'data-backend'
    | 'supabase-expert'
    | 'product-engineer'
    | 'quality-performance'
}

// TODO(scaffold): Fill this in from supabase/MIGRATION_INDEX.md +
// supabase/functions/_shared/rpc_registry.ts (doesn't exist yet — create
// when unblocking this).
const FIXTURES: Fixture[] = [
  // Examples below — replace with the real registered set.
  // {
  //   rpc: 'post_cardio_activity',
  //   params: {
  //     p_workout_id: '00000000-0000-0000-0000-000000000000',
  //     p_activity_type: 'running',
  //     p_duration_seconds: 600,
  //     p_distance_meters: 2000,
  //     p_calories_burned: 200,
  //     p_average_heart_rate: 140,
  //     p_xp_earned: 10,
  //   },
  //   owner: 'data-backend',
  // },
  // {
  //   rpc: 'log_private_challenge_progress',
  //   params: {
  //     p_challenge_id: '00000000-0000-0000-0000-000000000000',
  //     p_progress: 1,
  //     p_timezone: 'UTC',
  //     p_allow_decrease: false,
  //   },
  //   owner: 'supabase-expert',
  // },
]

const SIGNATURE_ERRORS = new Set([
  'PGRST202', // function not found
  'PGRST100', // parse error
  'PGRST102', // invalid argument
])

const DATA_INTEGRITY_PREFIX = [
  '23', // integrity constraint violation (23505, 23514, 23503, etc.)
  '42', // syntax error / access rule violation (42P01, 42883, 42703, etc.)
]

Deno.serve(async (_req) => {
  if (FIXTURES.length === 0) {
    return new Response(
      JSON.stringify({
        status: 'not_deployed',
        message:
          'bug-intel-rpc-smoke is a scaffold — populate FIXTURES[] and complete the DEPLOYMENT CHECKLIST before wiring into CI.',
      }),
      { status: 503, headers: { 'Content-Type': 'application/json' } },
    )
  }

  const url = Deno.env.get('SUPABASE_URL')
  const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
  const smokeUserId = Deno.env.get('SMOKE_USER_ID')
  if (!url || !key || !smokeUserId) {
    return new Response(
      JSON.stringify({
        status: 'config_missing',
        required: ['SUPABASE_URL', 'SUPABASE_SERVICE_ROLE_KEY', 'SMOKE_USER_ID'],
      }),
      { status: 500, headers: { 'Content-Type': 'application/json' } },
    )
  }

  const admin = createClient(url, key, {
    auth: { persistSession: false },
  })

  type Result = {
    rpc: string
    owner: string
    ok: boolean
    pg_code: string | null
    http_status: number | null
    error_message: string | null
    duration_ms: number
  }

  const results: Result[] = []
  const startedAt = Date.now()

  for (const f of FIXTURES) {
    const t0 = Date.now()
    const { error, status } = await admin.rpc(f.rpc, f.params)
    const dt = Date.now() - t0

    // Classify. SIGNATURE_ERRORS are always failures. DATA_INTEGRITY_PREFIX
    // are failures unless the fixture explicitly opts-in via expect_error.
    let ok = !error
    let pgCode: string | null = null
    let msg: string | null = null

    if (error) {
      msg = error.message
      pgCode = (error as unknown as { code?: string }).code ?? null
      if (pgCode) {
        if (SIGNATURE_ERRORS.has(pgCode)) {
          ok = false
        } else if (
          DATA_INTEGRITY_PREFIX.some((p) => pgCode!.startsWith(p)) &&
          f.expect_error !== 'pg_code'
        ) {
          ok = false
        } else if (f.expect_error === 'pg_code') {
          ok = true
        }
      } else {
        ok = false
      }
    }

    results.push({
      rpc: f.rpc,
      owner: f.owner,
      ok,
      pg_code: pgCode,
      http_status: status ?? null,
      error_message: msg,
      duration_ms: dt,
    })
  }

  const failed = results.filter((r) => !r.ok)
  const summary = {
    ran_at: new Date().toISOString(),
    duration_ms: Date.now() - startedAt,
    total: results.length,
    failed: failed.length,
    failures: failed,
    results,
  }

  // If anything failed, write a bug_intel signal so the admin CMS inbox
  // shows it alongside user-triggered fingerprints. Intentionally low-noise
  // (one row per failing RPC per day), not one-per-call.
  if (failed.length > 0) {
    await admin.from('bug_intelligence_trends').insert(
      failed.map((r) => ({
        fingerprint: `smoke:${r.rpc}:${r.pg_code ?? 'unknown'}`,
        trend_type: 'smoke_failure',
        today_count: 1,
        affected_users: 0,
        sample_window: '1d',
        notes: `RPC smoke: ${r.rpc} (${r.owner}) failed with ${r.pg_code ?? 'unknown'}: ${r.error_message ?? 'no message'}`,
      })),
    )
  }

  return new Response(JSON.stringify(summary), {
    status: failed.length > 0 ? 500 : 200,
    headers: { 'Content-Type': 'application/json' },
  })
})
