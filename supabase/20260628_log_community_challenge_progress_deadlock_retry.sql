-- ═══════════════════════════════════════════════════════════════════════════
-- 20260628_log_community_challenge_progress_deadlock_retry.sql
-- Fix 40P01 deadlock in `log_community_challenge_progress` by ordering the
-- row locks deterministically and adding an in-function deadlock retry.
--
-- Resolves: e03ca9df006076e40cce10c7d4310ac6 community challenge deadlock (crash)
-- Resolves: d29ff85aff4e5b3fdb647667770c56a9 community challenge deadlock (log)
-- ═══════════════════════════════════════════════════════════════════════════
--
-- Bug reports (2026-04-27 02:25 + 02:49 Cursor exports):
--
--   [Social] Error logging community progress: deadlock detected
--   [op=community_challenge.progress_sync ep=rpc/log_community_challenge_progress
--    pg=40P01]
--
-- Root cause:
--   `log_community_challenge_progress` (current shape in
--   `supabase/fix_daily_progress_reset.sql`) does its writes in this order:
--     1. INSERT … ON CONFLICT on `community_challenge_daily_progress`
--     2. UPDATE  `community_challenge_participants`
--   Concurrent invocations for the same (challenge_id, user_id) — e.g. the
--   foreground `logProgress` call from `CommunityChallengeService.swift:1086`
--   racing the fan-out from `BackgroundChallengeSyncService` after a
--   HealthKit observer fires — can acquire those row-level locks in
--   opposite orders and deadlock with SQLSTATE 40P01.
--
--   This is the EXACT same shape as the previously-fixed `log_challenge_progress`
--   (1v1) deadlock in migration `20260618_log_challenge_progress_deadlock_retry.sql`
--   AND the `log_private_challenge_progress` deadlock in
--   `20260524_private_challenge_deadlock_retry.sql`. The community variant was
--   missed in those sweeps; this migration applies the identical fix recipe.
--
-- Fix (two parts, both server-side):
--   1. Deterministic lock order. Take a `FOR UPDATE` row-lock on the
--      `community_challenge_participants` row (the one we always end up
--      updating) BEFORE touching `community_challenge_daily_progress`.
--      Concurrent invocations targeting the same (challenge_id, user_id)
--      now queue on that row instead of interleaving lock acquisition
--      across the two tables.
--   2. In-function deadlock retry. Wrap the body in a loop that catches
--      `deadlock_detected` (SQLSTATE 40P01) and retries up to 2 more times
--      with a short jittered `pg_sleep` backoff. Absorbs cross-user
--      deadlocks (e.g. a trigger holding additional locks) without the
--      client ever seeing them.
--
-- Invariants preserved (supabase-rules):
--   - `SECURITY DEFINER` + `SET search_path = public`.
--   - Uses `auth.uid()` — no `p_user_id` parameter (Data invariant #7).
--   - 4-arg signature unchanged: callers (Fit33/CommunityChallengeService.swift)
--     do NOT need to recompile.
--   - All existing semantics preserved verbatim:
--       • caller-tz today_date logic
--       • daily_target / target_hit calculation
--       • prev_target_hit detection (drives days_completed bump)
--       • GREATEST() merge unless p_allow_decrease=TRUE
--       • today_progress + last_active_at always updated
--   - Idempotent: `DROP FUNCTION IF EXISTS` for all known overloads
--     (3-arg + 4-arg) before `CREATE OR REPLACE` (supabase-rules invariant 12).
--   - Wrapped in `BEGIN; … COMMIT;`.
--   - Trailing `DO $$ RAISE NOTICE` audit block verifying signature exists
--     and prosrc contains `FOR UPDATE` + `WHEN deadlock_detected`
--     (SUPABASE_AGENT invariant 28+29).
--
-- Paired Swift change (shipped in same commit):
--   - Fit33/CommunityChallengeService.swift:1086 — bare `AppLogger.error`
--     replaced with `NetworkErrorClassifier.log` so the residual 40P01 (if
--     it survives the retry loop) classifies correctly under the
--     QUALITY_PERFORMANCE_AGENT invariant 25a contract.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

-- Drop every known overload before CREATE OR REPLACE (supabase-rules invariant 12).
DROP FUNCTION IF EXISTS log_community_challenge_progress(TEXT, INT, TEXT);
DROP FUNCTION IF EXISTS log_community_challenge_progress(TEXT, INT, TEXT, BOOLEAN);

CREATE OR REPLACE FUNCTION log_community_challenge_progress(
    p_challenge_id   TEXT,
    p_progress       INT,
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
    v_challenge_id    UUID;
    today_date        DATE;
    v_daily_target    INT;
    v_target_hit      BOOLEAN;
    v_prev_target_hit BOOLEAN;
    v_attempt         INT := 0;
    v_max_attempts    CONSTANT INT := 3;
BEGIN
    current_user_uuid := auth.uid();
    IF current_user_uuid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    v_challenge_id := p_challenge_id::UUID;
    today_date     := (NOW() AT TIME ZONE COALESCE(NULLIF(p_timezone, ''), 'UTC'))::DATE;

    -- Read challenge metadata once (no lock — read-committed is fine).
    SELECT daily_target INTO v_daily_target
      FROM community_challenges
     WHERE id = v_challenge_id;

    v_target_hit := (v_daily_target IS NOT NULL AND p_progress >= v_daily_target);

    -- In-function deadlock retry. Each iteration is its own subtransaction
    -- so we can catch 40P01 and try again without rolling back the caller.
    LOOP
        v_attempt := v_attempt + 1;
        BEGIN
            -- Step 1: DETERMINISTIC LOCK ORDER. Acquire the row-lock on
            -- `community_challenge_participants` FIRST — this is the row we
            -- will always end up updating with today_progress / days_completed
            -- / last_active_at. Concurrent callers targeting the same
            -- (challenge_id, user_id) now queue here instead of interleaving
            -- lock acquisition across community_challenge_daily_progress +
            -- community_challenge_participants and deadlocking.
            PERFORM 1
              FROM community_challenge_participants
             WHERE challenge_id = v_challenge_id
               AND user_id      = current_user_uuid
             FOR UPDATE;

            -- Step 2: read the prior day's target_hit while we hold the lock —
            -- this drives the days_completed +1 bump only when the target
            -- transitions from missed → hit (not on every overwrite).
            SELECT target_hit INTO v_prev_target_hit
              FROM community_challenge_daily_progress
             WHERE challenge_id   = v_challenge_id
               AND user_id        = current_user_uuid
               AND progress_date  = today_date;

            -- Step 3: upsert today's daily progress.
            INSERT INTO community_challenge_daily_progress (
                challenge_id, user_id, progress_date, progress_value,
                target_hit, source, updated_at
            ) VALUES (
                v_challenge_id, current_user_uuid, today_date, p_progress,
                v_target_hit, 'auto_sync', NOW()
            )
            ON CONFLICT (challenge_id, user_id, progress_date)
            DO UPDATE SET
                progress_value = CASE
                    WHEN p_allow_decrease THEN EXCLUDED.progress_value
                    ELSE GREATEST(community_challenge_daily_progress.progress_value, EXCLUDED.progress_value)
                END,
                target_hit = CASE
                    WHEN p_allow_decrease THEN EXCLUDED.target_hit
                    WHEN EXCLUDED.progress_value > community_challenge_daily_progress.progress_value
                        THEN EXCLUDED.target_hit
                    ELSE community_challenge_daily_progress.target_hit
                END,
                source     = EXCLUDED.source,
                updated_at = NOW();

            -- Step 4: update participants row (lock already held from Step 1).
            UPDATE community_challenge_participants
               SET days_completed = CASE
                       WHEN v_target_hit AND (v_prev_target_hit IS NULL OR NOT v_prev_target_hit)
                            THEN COALESCE(days_completed, 0) + 1
                       ELSE days_completed
                   END,
                   today_progress = p_progress,
                   last_active_at = NOW()
             WHERE challenge_id = v_challenge_id
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

GRANT EXECUTE ON FUNCTION log_community_challenge_progress(TEXT, INT, TEXT, BOOLEAN) TO authenticated;

COMMENT ON FUNCTION log_community_challenge_progress(TEXT, INT, TEXT, BOOLEAN) IS
'Community challenge progress writer. Hardened 2026-04-27 with deterministic
lock order on community_challenge_participants + 40P01 deadlock retry — same
recipe as 20260618_log_challenge_progress_deadlock_retry.sql (1v1) and
20260524_private_challenge_deadlock_retry.sql (private). Caller-tz today_date.
Uses auth.uid(); no p_user_id parameter (Data invariant #7).';

-- ═══════════════════════════════════════════════════════════════════════════
-- Audit block — fail loud on schema regression (SUPABASE_AGENT invariant 29).
-- ═══════════════════════════════════════════════════════════════════════════

DO $$
DECLARE
    v_count       INT;
    v_prosrc      TEXT;
    v_has_lock    BOOLEAN;
    v_has_retry   BOOLEAN;
BEGIN
    SELECT COUNT(*), MAX(prosrc) INTO v_count, v_prosrc
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public'
       AND p.proname = 'log_community_challenge_progress';

    IF v_count <> 1 THEN
        RAISE EXCEPTION '[20260628 audit] expected exactly 1 log_community_challenge_progress overload, got %', v_count;
    END IF;

    v_has_lock  := position('FOR UPDATE'        in v_prosrc) > 0;
    v_has_retry := position('deadlock_detected' in v_prosrc) > 0;

    IF NOT v_has_lock THEN
        RAISE EXCEPTION '[20260628 audit] log_community_challenge_progress missing FOR UPDATE row-lock — deadlock fix did not land';
    END IF;
    IF NOT v_has_retry THEN
        RAISE EXCEPTION '[20260628 audit] log_community_challenge_progress missing deadlock_detected handler — retry loop did not land';
    END IF;

    RAISE NOTICE '[20260628] ✅ log_community_challenge_progress hardened: 1 overload, FOR UPDATE present, 40P01 retry present.';
END $$;

COMMIT;
