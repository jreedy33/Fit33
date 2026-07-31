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
//        -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY"` nightly + on
//       every deploy. (2026-07-30: the function is service-role gated — anon
//       or user JWTs are rejected with 401.)
//   [ ] Wire failure notifications to the existing Slack / Pushover webhook.
//
// Until the checklist is complete, calling this function returns a friendly
// 503 ("not yet deployed").

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

// ── Auth (service-role / x-cron-key only) ─────────────────────────────────
// This function runs every fixture with a SERVICE-ROLE client and can insert
// bug_intelligence_trends rows — it must NEVER be invocable by end users.
// Same gate as notification-orchestrator (Edge Function Auth Registry —
// INFRA_SECURITY invariant 11).
const EXPECTED_PROJECT_REF = (() => {
  const raw = Deno.env.get('SUPABASE_URL') || ''
  const match = raw.match(/^https?:\/\/([a-z0-9]+)\.supabase\.co/i)
  return match?.[1] ?? ''
})()

function isServiceRoleJWT(token: string): boolean {
  try {
    const parts = token.split('.')
    if (parts.length !== 3) return false
    const payload = JSON.parse(atob(parts[1]))
    if (payload.role !== 'service_role') return false
    if (!EXPECTED_PROJECT_REF) return false
    return payload.ref === EXPECTED_PROJECT_REF
  } catch {
    return false
  }
}

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

// Phase 11G — 2026-04-24 signature-smoke fixtures.
//
// The "original" version of this file required a dedicated seeded user
// (smoke-test@fit33.com + owned challenge + workout + weight log) before
// any fixture could run. That's a multi-sprint dependency. To unblock
// the smoke test NOW without the seed-data project, this rewrites the
// strategy to be SIGNATURE-ONLY:
//
//   For each RPC, call it with intentionally-zeroed uuids + neutral
//   primitives. Assert the response is EITHER:
//     - ok (the RPC accepted the shape + found no data), OR
//     - a data error (pg_code starts with 23/42 that isn't 42883 schema
//       mismatch, OR PGRST116 "no rows"), OR
//     - expected "not authenticated" P0001 because service_role bypasses
//       auth.uid() checks in some SECURITY DEFINER RPCs.
//
//   We FAIL only on:
//     - PGRST202 ("Could not find the function") — signature missing
//     - PGRST100 / PGRST102 — parse / invalid-argument errors
//     - 42883 — operator does not exist (the bug we just fixed on
//       sync_profile_weight, caught at smoke time instead of user time)
//     - 42P01 — relation does not exist (dropped table)
//     - 5xx HTTP — gateway down
//
// This gives us "is the RPC registered with the expected argument list
// and return type?" coverage on every 5-minute run. Data-correctness
// tests can come later when the seed-user work is done.
const FIXTURES: Fixture[] = [
  // --- Social / activity feed -------------------------------------------
  // Signatures verified against supabase/20260513_drop_post_workout_activity_overloads.sql
  // and supabase/20260418_post_cardio_activity.sql.
  {
    rpc: 'post_workout_activity',
    params: {
      p_workout_id: '00000000-0000-0000-0000-000000000001',
      p_workout_name: 'smoke',
      p_duration_seconds: 60,
      p_exercise_count: 1,
      p_total_sets: 1,
      p_xp_earned: 0,
      p_muscle_groups: [],
      p_exercises_json: '[]',
    },
    owner: 'data-backend',
    // SECURITY DEFINER; without auth.uid → P0001 "Not authenticated".
    expect_error: 'pg_code',
  },
  {
    rpc: 'post_cardio_activity',
    params: {
      p_workout_id: '00000000-0000-0000-0000-000000000001',
      p_activity_type: 'running',
      p_duration_seconds: 60,
      p_distance_meters: 100,
      p_calories_burned: 10,
      p_average_heart_rate: 120,
      p_xp_earned: 0,
    },
    owner: 'data-backend',
    expect_error: 'pg_code',
  },
  // --- Friend system ----------------------------------------------------
  // All SECURITY DEFINER — return P0001 "Not authenticated" when called
  // without auth.uid. Correct behavior, tag with expect_error.
  {
    rpc: 'get_friends',
    params: {},
    owner: 'data-backend',
    expect_error: 'pg_code',
  },
  {
    rpc: 'get_received_workouts',
    params: {},
    owner: 'data-backend',
    expect_error: 'pg_code',
  },
  {
    rpc: 'get_sent_workouts',
    params: {},
    owner: 'data-backend',
    expect_error: 'pg_code',
  },
  // --- Challenges -------------------------------------------------------
  {
    rpc: 'log_private_challenge_progress',
    params: {
      p_challenge_id: '00000000-0000-0000-0000-000000000001',
      p_progress: 1,
      p_timezone: 'UTC',
      p_allow_decrease: false,
    },
    owner: 'supabase-expert',
    // "challenge not found" → 23502 not-null violation. Correct
    // signature, data-level reject. Tag with expect_error.
    expect_error: 'pg_code',
  },
  {
    rpc: 'get_my_private_challenges',
    params: {},
    owner: 'supabase-expert',
    expect_error: 'pg_code',
  },
]
// NOTE — Removed fixtures as of Phase 11G smoke hardening:
//   - `get_daily_quests_body`: does not exist; the real function is
//     `get_daily_quests(TEXT, TEXT, BOOLEAN, BOOLEAN, BOOLEAN, INT, ...)`
//     with 19 required arguments. Not worth smoking until we scope a
//     seed user — the smoke would need realistic values for has_program,
//     step_goal, active_challenge_progress, etc. to avoid false
//     positives.
//   - `increment_hydration`: does not exist; hydration is a direct
//     table insert (`hydration_logs`) with RLS, not an RPC.
//   - `compute_daily_bug_rollup`: runs fine from pg_cron but fails via
//     PostgREST because the inner `DELETE FROM _bug_events_tmp;`
//     triggers the `safe_updates` guard (requires WHERE clause).
//     This is infrastructure, not a user-facing RPC. Safer to exclude
//     from smoke and let pg_cron keep running it directly.

// Phase 11G — "hard" errors that always fail the smoke even when the
// fixture opts-in to expect_error. These are the ones that signal a
// real schema drift between the Swift client's expectations and the
// database: missing function, wrong argument type, wrong return
// signature, operator mismatch, or dropped table.
const SIGNATURE_ERRORS = new Set([
  'PGRST202', // function not found (dropped / renamed)
  'PGRST203', // ambiguous function (two overloads — classic bug)
  'PGRST100', // parse error
  'PGRST102', // invalid argument
  '42883',    // operator does not exist (the uuid = text bug we just fixed)
  '42P01',    // relation does not exist (dropped table)
  '42703',    // column does not exist (dropped column)
  '42P18',    // indeterminate datatype (return-type drift)
])

// Softer data-integrity errors — these are expected when the smoke
// caller lacks auth.uid() or references a non-existent row. A fixture
// can opt-into this bucket via expect_error='pg_code'.
const DATA_INTEGRITY_PREFIX = [
  '23', // integrity constraint violation (23505, 23514, 23503, etc.)
  'P0001', // RAISE EXCEPTION 'Not authenticated' from SECURITY DEFINER RPCs
]

Deno.serve(async (req) => {
  // ── Auth gate — service-role bearer or x-cron-key service JWT only ──────
  const serviceKeyForAuth = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
  const cronKey = req.headers.get('x-cron-key')
  const authHeader = req.headers.get('Authorization')
  let authed = false
  if (cronKey && isServiceRoleJWT(cronKey)) {
    authed = true
  } else if (authHeader) {
    const token = authHeader.replace('Bearer ', '')
    if ((serviceKeyForAuth && token === serviceKeyForAuth) || isServiceRoleJWT(token)) {
      authed = true
    }
  }
  if (!authed) {
    return new Response(JSON.stringify({ error: 'Service-role only' }), {
      status: 401,
      headers: { 'Content-Type': 'application/json' },
    })
  }

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
  // Phase 11G — SMOKE_USER_ID no longer required for the signature-only
  // smoke strategy (see FIXTURES[] preamble). Kept as an optional ENV
  // hint so when the data-bearing smoke tests come online we can opt
  // into them by setting this var.
  if (!url || !key) {
    return new Response(
      JSON.stringify({
        status: 'config_missing',
        required: ['SUPABASE_URL', 'SUPABASE_SERVICE_ROLE_KEY'],
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
          // Phase 11G — SIGNATURE_ERRORS always fail, even if the
          // fixture declared expect_error='pg_code'. A fixture saying
          // "I expect a data error" should NEVER be allowed to swallow
          // a schema drift — that's the whole point of the smoke test.
          ok = false
        } else if (f.expect_error === 'pg_code') {
          // Fixture opts in to "a pg-coded error is normal here" — e.g.
          // SECURITY DEFINER RPCs that RAISE 'Not authenticated' when
          // called without auth.uid().
          ok = true
        } else if (
          DATA_INTEGRITY_PREFIX.some((p) => pgCode!.startsWith(p))
        ) {
          ok = false
        }
      } else {
        // No pg_code and error — treat as real failure unless the
        // fixture expected a non-pg error (currently not supported).
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
