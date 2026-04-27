-- ═══════════════════════════════════════════════════════════════════════════
-- 20260629_fix_log_challenge_progress_drop_last_progress_at.sql
-- HOTFIX: drop the bogus `last_progress_at = NOW()` write from
-- `log_challenge_progress` that landed in #129
-- (`20260626_widget_writes_kill_switch.sql`).
--
-- Resolves: 3de7fbe4ab37b58eff4791554f64b791 challenge progress sync 42703 (crash)
-- Resolves: d441ebc808a595a2e049c15bb6dddd75 daily quests sig mismatch (1.37 cohort noise)
-- Resolves: 80234a6b3ec30cf26f88734f1f9ef1eb steps not resetting at midnight (paired iOS fix)
-- ═══════════════════════════════════════════════════════════════════════════
--
-- ROOT CAUSE
-- ----------
-- Migration #129 (Phase 7d widget kill-switch) recreated the
-- `log_challenge_progress` RPC and added a stray
--     last_progress_at = NOW()
-- to the UPDATE on `challenge_participants` (line 203 of #129). That column
-- has never existed on `challenge_participants` — the canonical "last
-- progress timestamp" is computed dynamically from
-- `challenge_daily_progress.updated_at` and surfaced via the appended
-- `my_last_progress_at` / `opponent_last_progress_at` columns on
-- `get_active_challenges` (migration #122 / 20260620).
--
-- Effect: every challenge progress sync on builds 1.38 (57) / (58) fails
-- with `42703 column "last_progress_at" of relation "challenge_participants"
-- does not exist`. The iOS retry loop then logs the failure as
-- `[CHALLENGE] logProgress failed (attempt 1/3, source: fit33)` →
-- crash-fingerprint `3de7fbe4`.
--
-- FIX
-- ---
-- Re-CREATE OR REPLACE `log_challenge_progress` from the #129 body MINUS
-- the bogus `last_progress_at = NOW()` line. Keep:
--   • Phase 7d widget kill-switch (silent-success when
--     widget_writes_enabled = false AND p_source = 'widget').
--   • Migration #119 (20260618) deterministic lock order +
--     deadlock retry recipe.
--   • Caller-tz progress_date logic (migration #76, 20260520).
--   • Membership pre-check (preserved error message).
--
-- Signature unchanged → no Swift recompile required.
--
-- Invariants preserved (supabase-rules):
--   • SECURITY DEFINER + search_path = public
--   • auth.uid() — no p_user_id
--   • DROP FUNCTION IF EXISTS for all known overloads (5/6/7-arg)
--     before CREATE OR REPLACE (invariant 12)
--   • BEGIN/COMMIT, idempotent
--   • Trailing audit DO $$ block fails if `last_progress_at` regex still
--     present in prosrc (catches re-introduction by future migrations)
--   • All Step ordering identical to #119 — deadlock fix unchanged
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
    v_check_date      DATE;
    v_attempt         INT := 0;
    v_max_attempts    CONSTANT INT := 3;
    v_widget_enabled  TEXT;
BEGIN
    current_user_uuid := auth.uid();
    IF current_user_uuid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    -- Phase 7d widget kill-switch (preserved from #129). Silent-success
    -- no-ops widget-source writes when the flag is FALSE so widget
    -- extensions (which can't refresh JWTs) don't spin on dead RPC calls.
    IF p_source = 'widget' THEN
        SELECT value INTO v_widget_enabled
          FROM internal_config
         WHERE key = 'widget_writes_enabled';
        IF v_widget_enabled IS DISTINCT FROM 'true' THEN
            RETURN TRUE;
        END IF;
    END IF;

    challenge_uuid := p_challenge_id::UUID;
    v_caller_tz    := COALESCE(NULLIF(p_timezone, ''), 'UTC');

    SELECT daily_target INTO v_daily_target
      FROM group_challenges
     WHERE id = challenge_uuid;

    IF p_progress_date IS NOT NULL AND p_progress_date != '' THEN
        v_progress_date := p_progress_date::DATE;
    ELSE
        v_progress_date := (NOW() AT TIME ZONE v_caller_tz)::DATE;
    END IF;

    -- Membership pre-check (preserved error message for clients).
    IF NOT EXISTS (
        SELECT 1
          FROM challenge_participants
         WHERE challenge_id = challenge_uuid
           AND user_id      = current_user_uuid
    ) THEN
        RAISE EXCEPTION 'You are not a participant in this challenge';
    END IF;

    v_target_hit := (v_daily_target IS NOT NULL AND p_progress_value >= v_daily_target);

    -- Deadlock retry loop (#119 recipe — preserved verbatim).
    LOOP
        v_attempt := v_attempt + 1;
        BEGIN
            -- Step 1: deterministic lock order on challenge_participants.
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

            -- Step 4: update participants row. NOTE: NO `last_progress_at`
            -- write — that column doesn't exist on challenge_participants.
            -- The freshness signal is computed from
            -- challenge_daily_progress.updated_at via
            -- get_active_challenges (#122).
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
                   best_streak    = GREATEST(COALESCE(best_streak, 0), v_current_streak)
             WHERE challenge_id = challenge_uuid
               AND user_id      = current_user_uuid;

            RETURN TRUE;
        EXCEPTION
            WHEN deadlock_detected THEN
                IF v_attempt >= v_max_attempts THEN
                    RAISE;
                END IF;
                PERFORM pg_sleep(0.05 + (random() * 0.1));
        END;
    END LOOP;
END;
$$;

GRANT EXECUTE ON FUNCTION log_challenge_progress(TEXT, INT, TEXT, TEXT, TEXT, TEXT, BOOLEAN) TO authenticated;

COMMENT ON FUNCTION log_challenge_progress(TEXT, INT, TEXT, TEXT, TEXT, TEXT, BOOLEAN) IS
'1v1/group challenge progress writer. Caller-tz progress_date.
Phase 7d widget kill-switch (silent-success on widget source when flag off).
Deterministic lock order + 40P01 retry (20260618 recipe). NO last_progress_at
write — that column does not exist on challenge_participants; freshness is
computed from challenge_daily_progress.updated_at via get_active_challenges
(20260620). Hotfixed 2026-04-27 after #129 introduced a 42703 regression.';

-- ═══════════════════════════════════════════════════════════════════════════
-- Audit — fail-loud if last_progress_at is reintroduced (SUPABASE_AGENT inv 29)
-- ═══════════════════════════════════════════════════════════════════════════

DO $$
DECLARE
    v_count INT;
    v_src   TEXT;
BEGIN
    SELECT COUNT(*), MAX(prosrc) INTO v_count, v_src
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public'
       AND p.proname = 'log_challenge_progress';

    IF v_count <> 1 THEN
        RAISE EXCEPTION '[20260629 audit] expected exactly 1 log_challenge_progress overload, got %', v_count;
    END IF;

    -- Look for the WRITE pattern, not just the string. The function body
    -- intentionally references `last_progress_at` in a comment to flag
    -- to future maintainers that the column doesn't exist on
    -- challenge_participants. The audit only fires if a real assignment
    -- (`last_progress_at = …` or `last_progress_at  := …`) reappears.
    IF v_src ~ '\mlast_progress_at\s*[:=]' THEN
        RAISE EXCEPTION '[20260629 audit] log_challenge_progress still ASSIGNS last_progress_at — hotfix did not land';
    END IF;

    IF position('FOR UPDATE'        in v_src) = 0 THEN
        RAISE EXCEPTION '[20260629 audit] FOR UPDATE missing — deadlock fix regressed';
    END IF;
    IF position('deadlock_detected' in v_src) = 0 THEN
        RAISE EXCEPTION '[20260629 audit] deadlock_detected handler missing — retry loop regressed';
    END IF;
    IF position('widget_writes_enabled' in v_src) = 0 THEN
        RAISE EXCEPTION '[20260629 audit] widget_writes_enabled kill-switch missing — Phase 7d regressed';
    END IF;

    RAISE NOTICE '[20260629] ✅ log_challenge_progress hotfix landed: 1 overload, no last_progress_at write, FOR UPDATE + deadlock retry + widget kill-switch all preserved.';
END $$;

COMMIT;

-- ───────────────────────────────────────────────────────────────────────
-- Resolves directives — feed bug-intel-resolves-deploy.yml on next push:
-- ───────────────────────────────────────────────────────────────────────
-- Resolves: 3de7fbe4ab37b58eff4791554f64b791 challenge progress sync 42703 (crash)
-- Resolves: d441ebc808a595a2e049c15bb6dddd75 daily quests sig mismatch (1.37 cohort noise)
-- Resolves: 80234a6b3ec30cf26f88734f1f9ef1eb steps not resetting at midnight (paired iOS fix in HealthKitManager)
