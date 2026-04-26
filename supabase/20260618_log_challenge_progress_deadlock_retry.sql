-- ═══════════════════════════════════════════════════════════════════════════
-- 20260618_log_challenge_progress_deadlock_retry.sql
-- Fix 40P01 deadlock in `log_challenge_progress` (1v1) by ordering the row
-- locks deterministically and adding an in-function deadlock retry.
--
-- Resolves: 281382dab90b… (Report 21 of 2026-04-26 bug-intel export)
--           "Challenge progress deadlock in log_challenge_progress"
--           op=challenge.progress_sync, endpoint=rpc/log_challenge_progress,
--           class=pg:40P01.
-- Drains:   bb8962ac8f2dd3ef51f12bddb04cabde — "Failed to sync progress for
--           '⚔️ 👣 …'" (cascade noise from same root; the iOS-side
--           ChallengeService.swift:2235 log was also downgraded to .warning
--           in the paired Swift change).
--           0d1100defe… — same cascade string under product-engineer triage.
-- ═══════════════════════════════════════════════════════════════════════════
--
-- Bug reports (2026-04-26 Cursor export, fingerprint 281382da):
--
--   [Social] [CHALLENGE] logProgress failed (attempt 1/3, source: healthkit):
--       deadlock detected
--       [op=challenge.progress_sync
--        ep=rpc/log_challenge_progress
--        pg=40P01]
--
-- Root cause:
--   The current `log_challenge_progress` definition (shipped in
--   `20260520_challenge_daily_reset_caller_tz.sql`) does its writes in this
--   order:
--     1. INSERT … ON CONFLICT on `challenge_daily_progress`
--     2. UPDATE  `challenge_participants` (total_progress / days_completed /
--                 current_streak / best_streak)
--   Two concurrent invocations of this RPC for the same (challenge_id,
--   user_id) — e.g. the foreground `logProgress` call from
--   `ChallengeService.syncHealthKitDataToChallenges()` racing the fan-out
--   from `BackgroundChallengeSyncService` after a HealthKit observer fires —
--   can acquire those row-level locks in opposite orders and deadlock.
--   PostgreSQL aborts one of them with SQLSTATE 40P01 and the iOS client
--   logs the error (which then ALSO triggers the cascade
--   "Failed to sync progress for …" log at ChallengeService.swift:2235).
--
--   This is the EXACT same shape as the previously-fixed
--   `log_private_challenge_progress` deadlock (see migration
--   `20260524_private_challenge_deadlock_retry.sql`). The 1v1 RPC was missed
--   in that sweep; this migration applies the identical fix recipe.
--
-- Fix (two parts, both server-side):
--   1. Deterministic lock order. Take a `FOR UPDATE` row-lock on the
--      `challenge_participants` row (the one we always end up updating)
--      BEFORE touching `challenge_daily_progress`. Concurrent invocations
--      that target the same (challenge_id, user_id) now queue on that row
--      instead of interleaving lock acquisition on the two tables.
--   2. In-function deadlock retry. Wrap the body in a loop that catches
--      `deadlock_detected` (SQLSTATE 40P01) and retries up to 2 more times
--      with a short jittered `pg_sleep` backoff. This absorbs any cross-
--      user deadlock we didn't anticipate (e.g. a trigger on one of the
--      tables that holds additional locks) without the client ever seeing
--      it.
--
-- Invariants preserved (supabase-rules):
--   - `SECURITY DEFINER` + `SET search_path = public`.
--   - Uses `auth.uid()` — no `p_user_id` parameter.
--   - 7-arg signature unchanged: callers (Fit33/ChallengeService.swift) do
--     not need to recompile.
--   - All existing semantics preserved verbatim:
--       • caller-tz progress_date logic
--       • participant-membership pre-check (raises 'You are not a
--         participant in this challenge')
--       • GREATEST() merge unless p_allow_decrease=TRUE
--       • streak / total / days_completed / best_streak recompute
--   - Idempotent: `DROP FUNCTION IF EXISTS` for all known overloads
--     (5/6/7-arg) before `CREATE OR REPLACE` (supabase-rules invariant 12).
--   - Wrapped in `BEGIN; … COMMIT;`.
--   - Trailing `DO $$ RAISE NOTICE` audit block verifying signature exists
--     and prosrc contains `FOR UPDATE` + `WHEN deadlock_detected`
--     (SUPABASE_AGENT invariant 28+29).
--
-- Paired Swift changes (shipped in same commit):
--   - Fit33/ChallengeService.swift:2235 — outer `AppLogger.error("Failed to
--     sync progress for …")` downgraded to `.warning` (the underlying
--     `logProgress` already routes the real failure through
--     `NetworkErrorClassifier.log` with op + endpoint + pg_code, so the
--     outer `.error` was duplicate noise that created the bb8962ac /
--     0d1100de cascade fingerprints).
--   - Fit33/WorkoutManager.swift:1199 — unrelated classifier-bypass cleanup
--     (50e7a9a7 / cf3a4a8b), included in the same commit for traceability.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

-- Drop every known overload before CREATE OR REPLACE to avoid PGRST202
-- "could not choose best candidate" (supabase-rules invariant 12).
DROP FUNCTION IF EXISTS log_challenge_progress(TEXT, INT, TEXT, TEXT, TEXT);
DROP FUNCTION IF EXISTS log_challenge_progress(TEXT, INT, TEXT, TEXT, TEXT, TEXT);
DROP FUNCTION IF EXISTS log_challenge_progress(TEXT, INT, TEXT, TEXT, TEXT, TEXT, BOOLEAN);

CREATE OR REPLACE FUNCTION log_challenge_progress(
    p_challenge_id   TEXT,
    p_progress_value INT,
    p_progress_date  TEXT DEFAULT NULL,
    p_source         TEXT DEFAULT 'manual',
    p_workout_id     TEXT DEFAULT NULL,
    p_timezone       TEXT DEFAULT 'UTC',
    p_allow_decrease BOOLEAN DEFAULT FALSE
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    current_user_uuid UUID;
    challenge_uuid    UUID;
    v_progress_date   DATE;
    v_daily_target    INT;
    v_target_hit      BOOLEAN;
    v_caller_tz       TEXT;
    v_current_streak  INT := 0;
    v_best_streak     INT := 0;
    v_check_date      DATE;
    v_attempt         INT := 0;
    v_max_attempts    CONSTANT INT := 3;
BEGIN
    current_user_uuid := auth.uid();
    IF current_user_uuid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    challenge_uuid := p_challenge_id::UUID;
    v_caller_tz    := COALESCE(NULLIF(p_timezone, ''), 'UTC');

    -- Read challenge metadata once (no lock — read-committed is fine).
    SELECT daily_target INTO v_daily_target
      FROM group_challenges
     WHERE id = challenge_uuid;

    IF p_progress_date IS NOT NULL AND p_progress_date != '' THEN
        v_progress_date := p_progress_date::DATE;
    ELSE
        v_progress_date := (NOW() AT TIME ZONE v_caller_tz)::DATE;
    END IF;

    -- Membership pre-check (preserved from original — keeps the 'You are
    -- not a participant in this challenge' error message stable for clients).
    IF NOT EXISTS (
        SELECT 1
          FROM challenge_participants
         WHERE challenge_id = challenge_uuid
           AND user_id      = current_user_uuid
    ) THEN
        RAISE EXCEPTION 'You are not a participant in this challenge';
    END IF;

    v_target_hit := (v_daily_target IS NOT NULL AND p_progress_value >= v_daily_target);

    -- In-function deadlock retry. Each iteration is its own subtransaction
    -- so we can catch 40P01 and try again without rolling back the caller.
    LOOP
        v_attempt := v_attempt + 1;
        BEGIN
            -- Step 1: DETERMINISTIC LOCK ORDER. Acquire the row-lock on
            -- `challenge_participants` FIRST — this is the row we will
            -- always end up updating with the recomputed total / streak.
            -- Concurrent callers targeting the same (challenge_id, user_id)
            -- now queue here instead of interleaving lock acquisition
            -- across challenge_daily_progress + challenge_participants and
            -- deadlocking.
            PERFORM 1
              FROM challenge_participants
             WHERE challenge_id = challenge_uuid
               AND user_id      = current_user_uuid
             FOR UPDATE;

            -- Step 2: upsert today's daily progress.
            INSERT INTO challenge_daily_progress (
                challenge_id, user_id, progress_date, progress_value,
                target_hit, source, workout_id, updated_at
            ) VALUES (
                challenge_uuid, current_user_uuid, v_progress_date, p_progress_value,
                v_target_hit, p_source,
                CASE WHEN p_workout_id IS NOT NULL AND p_workout_id != '' THEN p_workout_id::UUID ELSE NULL END,
                NOW()
            )
            ON CONFLICT (challenge_id, user_id, progress_date)
            DO UPDATE SET
                progress_value = CASE
                    WHEN p_allow_decrease THEN EXCLUDED.progress_value
                    ELSE GREATEST(challenge_daily_progress.progress_value, EXCLUDED.progress_value)
                END,
                target_hit = CASE
                    WHEN p_allow_decrease THEN EXCLUDED.target_hit
                    WHEN EXCLUDED.progress_value > challenge_daily_progress.progress_value
                        THEN EXCLUDED.target_hit
                    ELSE challenge_daily_progress.target_hit
                END,
                source     = EXCLUDED.source,
                updated_at = NOW();

            -- Step 3: recompute current_streak walking back from progress_date.
            v_check_date     := v_progress_date;
            v_current_streak := 0;
            LOOP
                IF EXISTS (
                    SELECT 1
                      FROM challenge_daily_progress
                     WHERE challenge_id = challenge_uuid
                       AND user_id      = current_user_uuid
                       AND challenge_daily_progress.progress_date = v_check_date
                       AND (target_hit = TRUE OR progress_value >= COALESCE(v_daily_target, 0))
                ) THEN
                    v_current_streak := v_current_streak + 1;
                    v_check_date     := v_check_date - INTERVAL '1 day';
                ELSE
                    EXIT;
                END IF;
                IF v_current_streak > 365 THEN EXIT; END IF;
            END LOOP;

            SELECT COALESCE(best_streak, 0)
              INTO v_best_streak
              FROM challenge_participants
             WHERE challenge_id = challenge_uuid
               AND user_id      = current_user_uuid;

            v_best_streak := GREATEST(v_best_streak, v_current_streak);

            -- Step 4: update participants row (lock already held from Step 1).
            UPDATE challenge_participants
               SET total_progress = (
                       SELECT COALESCE(SUM(progress_value), 0)
                         FROM challenge_daily_progress
                        WHERE challenge_id = challenge_uuid
                          AND user_id      = current_user_uuid
                   ),
                   days_completed = (
                       SELECT COUNT(*)
                         FROM challenge_daily_progress cdp
                         JOIN group_challenges gc ON gc.id = cdp.challenge_id
                        WHERE cdp.challenge_id = challenge_uuid
                          AND cdp.user_id      = current_user_uuid
                          AND (cdp.target_hit = TRUE OR cdp.progress_value >= COALESCE(gc.daily_target, 0))
                   ),
                   current_streak = v_current_streak,
                   best_streak    = v_best_streak
             WHERE challenge_id = challenge_uuid
               AND user_id      = current_user_uuid;

            RETURN TRUE;
        EXCEPTION
            WHEN deadlock_detected THEN
                IF v_attempt >= v_max_attempts THEN
                    RAISE; -- give up, let the client see 40P01
                END IF;
                -- Short jittered backoff, then retry. 50–150ms is enough for
                -- the competing transaction to finish or retry.
                PERFORM pg_sleep(0.05 + (random() * 0.1));
                -- fall through to next LOOP iteration
        END;
    END LOOP;
END;
$$;

GRANT EXECUTE ON FUNCTION log_challenge_progress(TEXT, INT, TEXT, TEXT, TEXT, TEXT, BOOLEAN) TO authenticated;

COMMENT ON FUNCTION log_challenge_progress(TEXT, INT, TEXT, TEXT, TEXT, TEXT, BOOLEAN) IS
'1v1/group challenge progress writer. Uses caller-tz progress_date (per
20260520_challenge_daily_reset_caller_tz). Hardened 2026-04-26 with
deterministic lock order on challenge_participants + 40P01 deadlock retry
(see 20260618_log_challenge_progress_deadlock_retry.sql).';

-- Fail-loud audit (SUPABASE_AGENT invariants 28 + 29). Verify the function
-- exists with the expected 7-arg signature and that the body actually
-- contains the lock + retry primitives we just added.
DO $$
DECLARE
    fn_count    INT;
    has_for_upd BOOLEAN;
    has_retry   BOOLEAN;
BEGIN
    SELECT COUNT(*)
      INTO fn_count
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public'
       AND p.proname = 'log_challenge_progress';

    IF fn_count <> 1 THEN
        RAISE EXCEPTION
            '[20260618] expected exactly 1 log_challenge_progress overload after migration, found %',
            fn_count;
    END IF;

    SELECT
        prosrc ILIKE '%FOR UPDATE%',
        prosrc ILIKE '%deadlock_detected%'
      INTO has_for_upd, has_retry
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public'
       AND p.proname = 'log_challenge_progress';

    IF NOT has_for_upd OR NOT has_retry THEN
        RAISE EXCEPTION
            '[20260618] log_challenge_progress missing hardening (FOR UPDATE=%, deadlock_detected=%)',
            has_for_upd, has_retry;
    END IF;

    RAISE NOTICE '[20260618] log_challenge_progress hardened — deterministic lock order on challenge_participants + 40P01 retry (max 3 attempts, 50–150ms jitter)';
END $$;

COMMIT;

-- Verify (run after deploy):
--   SELECT prosrc FROM pg_proc WHERE proname = 'log_challenge_progress';
--   -- should include `FOR UPDATE` on challenge_participants
--   -- should include `WHEN deadlock_detected`
