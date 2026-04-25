-- ═══════════════════════════════════════════════════════════════════════════
-- 20260524_private_challenge_deadlock_retry.sql
-- Fix 40P01 deadlock in `log_private_challenge_progress` by ordering the row
-- locks deterministically and adding an in-function deadlock retry.
--
-- Resolves: 3d7ac331e9011e75e363f217b5827006 — Private challenge progress deadlock (Report 8 / 04-25 audit)
-- Resolves: 23ac878010450752bb1b1ca994edb56b — Same deadlock, log-source variant (Report 22 / 04-25 audit)
-- ═══════════════════════════════════════════════════════════════════════════
--
-- Bug reports (2026-04-24 Cursor export, fingerprints 3d7ac331 + 23ac8780):
--
--   [Social] Error logging private challenge progress:
--       deadlock detected
--       [op=challenges.log_private_progress
--        ep=rpc/log_private_challenge_progress
--        pg=40P01 ms=1224 try=1]
--
-- Root cause:
--   The previous definition (see `supabase/fix_daily_progress_reset.sql`
--   FIX 3) does its writes in this order:
--     1. INSERT … ON CONFLICT on `private_challenge_daily_progress`
--     2. UPDATE `private_challenge_members`
--   Two concurrent invocations of this RPC for the same user_id on the same
--   challenge (e.g. a foreground `logProgress` call racing the fan-out
--   background sync from `BackgroundChallengeSyncService`) can acquire those
--   row-level locks in opposite orders and deadlock. PostgreSQL aborts one
--   of them with SQLSTATE 40P01 and the iOS client logs the error.
--
-- Fix (two parts, both server-side):
--   1. Deterministic lock order. Take a `FOR UPDATE` row-lock on the
--      `private_challenge_members` row (the one we always end up writing)
--      BEFORE touching `private_challenge_daily_progress`. Concurrent
--      invocations that target the same (challenge_id, user_id) now queue on
--      that row instead of interleaving lock acquisition on the two tables.
--   2. In-function deadlock retry. Wrap the body in a loop that catches
--      `deadlock_detected` (SQLSTATE 40P01) and retries up to 2 more times
--      with a short `pg_sleep` backoff. This absorbs any cross-user deadlock
--      we didn't anticipate (e.g. a trigger on one of the tables that holds
--      additional locks) without the client ever seeing it.
--
-- Invariants preserved (supabase-rules):
--   - `SECURITY DEFINER` + `SET search_path = public`.
--   - Uses `auth.uid()` — no `user_id` parameter.
--   - Idempotent: `DROP FUNCTION IF EXISTS` for all known overloads before
--     `CREATE OR REPLACE`.
--   - `p_allow_decrease` default preserved; callers unchanged.
--   - Wrapped in `BEGIN; … COMMIT;`.
--   - Trailing `DO $$ RAISE NOTICE` audit block.
--
-- Paired Swift change: [Fit33/PrivateChallengeService.swift] — the
-- `logProgress` retry loop now also handles 40P01 as a retryable pg_code,
-- which provides a second line of defense if the server-side retry is
-- exhausted.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

-- Drop every known overload before CREATE OR REPLACE to avoid PGRST202
-- "could not choose best candidate" (supabase-rules §12).
DROP FUNCTION IF EXISTS log_private_challenge_progress(TEXT, INT, TEXT);
DROP FUNCTION IF EXISTS log_private_challenge_progress(TEXT, INT, TEXT, BOOLEAN);

CREATE OR REPLACE FUNCTION log_private_challenge_progress(
    p_challenge_id TEXT,
    p_progress INT,
    p_timezone TEXT DEFAULT 'UTC',
    p_allow_decrease BOOLEAN DEFAULT FALSE
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    current_user_uuid UUID;
    v_challenge_id UUID;
    today_date DATE;
    v_daily_target INT;
    v_target_hit BOOLEAN;
    v_prev_target_hit BOOLEAN;
    v_attempt INT := 0;
    v_max_attempts CONSTANT INT := 3;
BEGIN
    current_user_uuid := auth.uid();
    IF current_user_uuid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'P0001';
    END IF;

    v_challenge_id := p_challenge_id::UUID;
    today_date := (NOW() AT TIME ZONE COALESCE(NULLIF(p_timezone, ''), 'UTC'))::DATE;

    -- In-function deadlock retry. Each iteration is its own subtransaction
    -- so we can catch 40P01 and try again without rolling back the caller.
    LOOP
        v_attempt := v_attempt + 1;
        BEGIN
            -- Step 1: read challenge metadata (no lock — read-committed is fine).
            SELECT daily_target
              INTO v_daily_target
              FROM private_challenges
             WHERE id = v_challenge_id;

            v_target_hit := (v_daily_target IS NOT NULL AND p_progress >= v_daily_target);

            -- Step 2: DETERMINISTIC LOCK ORDER. Acquire the row-lock on
            -- `private_challenge_members` FIRST — this is the row we will
            -- always end up updating. Concurrent callers targeting the same
            -- (challenge_id, user_id) now queue here instead of interleaving
            -- lock acquisition across tables and deadlocking.
            PERFORM 1
              FROM private_challenge_members
             WHERE challenge_id = v_challenge_id
               AND user_id = current_user_uuid
             FOR UPDATE;
            -- Note: may return 0 rows if the caller isn't a member; the
            -- subsequent UPDATE will simply touch 0 rows which mirrors the
            -- previous behavior.

            -- Step 3: read prior target_hit (still safe — we hold the parent lock).
            SELECT target_hit
              INTO v_prev_target_hit
              FROM private_challenge_daily_progress
             WHERE challenge_id = v_challenge_id
               AND user_id = current_user_uuid
               AND progress_date = today_date;

            -- Step 4: upsert today's progress.
            INSERT INTO private_challenge_daily_progress (
                challenge_id, user_id, progress_date, progress_value, target_hit, source, updated_at
            ) VALUES (
                v_challenge_id, current_user_uuid, today_date, p_progress, v_target_hit, 'auto_sync', NOW()
            )
            ON CONFLICT (challenge_id, user_id, progress_date)
            DO UPDATE SET
                progress_value = CASE
                    WHEN p_allow_decrease THEN EXCLUDED.progress_value
                    ELSE GREATEST(private_challenge_daily_progress.progress_value, EXCLUDED.progress_value)
                END,
                target_hit = CASE
                    WHEN p_allow_decrease THEN EXCLUDED.target_hit
                    WHEN EXCLUDED.progress_value > private_challenge_daily_progress.progress_value
                        THEN EXCLUDED.target_hit
                    ELSE private_challenge_daily_progress.target_hit
                END,
                source = EXCLUDED.source,
                updated_at = NOW();

            -- Step 5: update members row (lock already held from step 2).
            UPDATE private_challenge_members
               SET days_completed = CASE
                        WHEN v_target_hit AND (v_prev_target_hit IS NULL OR NOT v_prev_target_hit)
                        THEN COALESCE(days_completed, 0) + 1
                        ELSE days_completed
                    END,
                   today_progress = p_progress,
                   last_active_at = NOW()
             WHERE challenge_id = v_challenge_id
               AND user_id = current_user_uuid;

            RETURN TRUE;
        EXCEPTION
            WHEN deadlock_detected THEN
                IF v_attempt >= v_max_attempts THEN
                    RAISE; -- give up, let the client see 40P01
                END IF;
                -- Short jittered backoff, then retry. 50-150ms is enough for
                -- the competing transaction to finish or retry.
                PERFORM pg_sleep(0.05 + (random() * 0.1));
                -- fall through to next LOOP iteration
        END;
    END LOOP;
END;
$$;

GRANT EXECUTE ON FUNCTION log_private_challenge_progress(TEXT, INT, TEXT, BOOLEAN) TO authenticated;

-- Fail-loud audit (SUPABASE_AGENT invariant #29). Verify the function exists
-- with the expected signature after commit.
DO $$
DECLARE
  fn_exists BOOLEAN;
BEGIN
  SELECT EXISTS (
    SELECT 1
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public'
       AND p.proname = 'log_private_challenge_progress'
       AND pg_get_function_identity_arguments(p.oid) =
           'p_challenge_id text, p_progress integer, p_timezone text, p_allow_decrease boolean'
  ) INTO fn_exists;

  IF NOT fn_exists THEN
    RAISE EXCEPTION '[20260524] log_private_challenge_progress(TEXT,INT,TEXT,BOOLEAN) missing after migration';
  END IF;

  RAISE NOTICE '[20260524] log_private_challenge_progress hardened — deterministic lock order + 40P01 retry';
END $$;

COMMIT;

-- Verify (run after deploy):
--   SELECT prosrc FROM pg_proc WHERE proname = 'log_private_challenge_progress';
--   -- should include `FOR UPDATE` on private_challenge_members
--   -- should include `WHEN deadlock_detected`
