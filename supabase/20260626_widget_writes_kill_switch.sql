-- ============================================================================
-- 20260626_widget_writes_kill_switch.sql
-- Widget Freshness Sprint — Phase 7d (2026-04-26)
--
-- Server-side kill switch for widget-extension writes to
-- `log_challenge_progress`. The widget extension (Phase 7d) calls the
-- RPC with `p_source = 'widget'` to keep step counts pushed to the
-- server even when the user hasn't opened the main Fit33 app for a
-- while. Adding this flag means we can disable that path instantly
-- from the dashboard if it ever misbehaves in production — without
-- needing an iOS rebuild.
--
-- Default value: TRUE (widget writes ENABLED). The migration is a
-- pure no-op for live behaviour; it just adds the dial.
--
-- Operational use:
--   -- disable widget writes (silent server-side reject, no error to client)
--   UPDATE internal_config SET value = 'false' WHERE key = 'widget_writes_enabled';
--
--   -- re-enable
--   UPDATE internal_config SET value = 'true'  WHERE key = 'widget_writes_enabled';
--
-- DESIGN NOTES
--
-- 1. The check sits at the TOP of `log_challenge_progress` and returns
--    `TRUE` (no error) so a disabled flag looks identical to a
--    successful write from the widget's perspective. The widget can't
--    refresh JWTs, so a noisy 4xx would just spam our logs without
--    user-visible benefit. The widget already accepts "fail closed to
--    server data" semantics for every other failure mode (Phase 6a /
--    7c) so the silent-success path here is consistent.
--
-- 2. The check ONLY fires when `p_source = 'widget'`. Every other
--    caller (main app, BGAppRefresh, silent-push wake, manual UI
--    button) passes `p_source = 'manual' / 'healthkit' / 'workout' /
--    'background' / etc.` and is unaffected.
--
-- 3. Reading `internal_config` per call adds one cheap PK lookup
--    (~0.1ms in benchmark). `log_challenge_progress` is on the hot
--    path for every challenge push, so we deliberately do NOT cache
--    the flag in a function-local — flipping the kill switch needs
--    to take effect on the very next call.
--
-- IDEMPOTENCY
--   Migration is idempotent (`INSERT … ON CONFLICT DO NOTHING` for
--   the row, full DROP + CREATE OR REPLACE for the function).
-- ============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- 1) Kill-switch row in internal_config
-- ---------------------------------------------------------------------------
-- internal_config schema is `(key TEXT PRIMARY KEY, value TEXT)`.
-- We store the boolean as a lowercase text literal so the existing
-- `value::TEXT` reads in other migrations work unchanged.
INSERT INTO internal_config (key, value)
VALUES ('widget_writes_enabled', 'true')
ON CONFLICT (key) DO NOTHING;

-- ---------------------------------------------------------------------------
-- 2) Patch log_challenge_progress with the kill-switch early-return
-- ---------------------------------------------------------------------------
-- Mirrors the canonical 20260618_log_challenge_progress_deadlock_retry.sql
-- definition (deterministic-lock-order + 40P01 retry preserved verbatim);
-- the only delta is the `widget_writes_enabled` early-return at the top.
-- Drops every overload first per Supabase invariant 12.

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
    current_user_uuid    UUID;
    challenge_uuid       UUID;
    v_progress_date      DATE;
    v_daily_target       INT;
    v_target_hit         BOOLEAN;
    v_caller_tz          TEXT;
    v_current_streak     INT := 0;
    v_best_streak        INT := 0;
    v_check_date         DATE;
    v_attempt            INT := 0;
    v_max_attempts       CONSTANT INT := 3;
    v_widget_writes_text TEXT;
BEGIN
    current_user_uuid := auth.uid();
    IF current_user_uuid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    -- Phase 7d kill switch. Silent success when widget writes are
    -- disabled — see migration header for rationale.
    IF p_source = 'widget' THEN
        SELECT value INTO v_widget_writes_text
          FROM internal_config
         WHERE key = 'widget_writes_enabled';

        IF v_widget_writes_text IS NULL OR LOWER(v_widget_writes_text) <> 'true' THEN
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

    IF NOT EXISTS (
        SELECT 1
          FROM challenge_participants
         WHERE challenge_id = challenge_uuid
           AND user_id      = current_user_uuid
    ) THEN
        RAISE EXCEPTION 'You are not a participant in this challenge';
    END IF;

    v_target_hit := (v_daily_target IS NOT NULL AND p_progress_value >= v_daily_target);

    LOOP
        v_attempt := v_attempt + 1;
        BEGIN
            PERFORM 1
              FROM challenge_participants
             WHERE challenge_id = challenge_uuid
               AND user_id      = current_user_uuid
             FOR UPDATE;

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

            UPDATE challenge_participants
               SET total_progress  = (
                       SELECT COALESCE(SUM(progress_value), 0)
                         FROM challenge_daily_progress
                        WHERE challenge_id = challenge_uuid
                          AND user_id      = current_user_uuid
                   ),
                   current_streak  = v_current_streak,
                   best_streak     = GREATEST(COALESCE(best_streak, 0), v_current_streak),
                   last_progress_at = NOW()
             WHERE challenge_id = challenge_uuid
               AND user_id      = current_user_uuid;

            EXIT;
        EXCEPTION
            WHEN deadlock_detected THEN
                IF v_attempt >= v_max_attempts THEN
                    RAISE;
                END IF;
                PERFORM pg_sleep((50 + floor(random() * 100))::INT / 1000.0);
        END;
    END LOOP;

    RETURN TRUE;
END;
$$;

GRANT EXECUTE ON FUNCTION log_challenge_progress(TEXT, INT, TEXT, TEXT, TEXT, TEXT, BOOLEAN) TO authenticated;

COMMENT ON FUNCTION log_challenge_progress(TEXT, INT, TEXT, TEXT, TEXT, TEXT, BOOLEAN) IS
'Upserts challenge_daily_progress for caller, recomputes total + streak.
Deterministic lock order on challenge_participants + 40P01 deadlock retry
(20260618_log_challenge_progress_deadlock_retry.sql). Phase 7d kill switch
silent-success no-ops widget-source writes when internal_config
widget_writes_enabled = false.';

-- ---------------------------------------------------------------------------
-- 3) Audit
-- ---------------------------------------------------------------------------
DO $audit$
DECLARE
    v_count INT;
    v_flag TEXT;
BEGIN
    SELECT COUNT(*) INTO v_count
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public'
       AND p.proname = 'log_challenge_progress';

    IF v_count <> 1 THEN
        RAISE EXCEPTION
            '[20260626] expected exactly 1 log_challenge_progress overload after migration, found %', v_count;
    END IF;

    SELECT value INTO v_flag FROM internal_config WHERE key = 'widget_writes_enabled';
    IF v_flag IS NULL THEN
        RAISE EXCEPTION '[20260626] widget_writes_enabled flag missing from internal_config';
    END IF;

    RAISE NOTICE '[20260626] widget writes kill switch installed (flag=%)', v_flag;
END $audit$;

COMMIT;

-- ============================================================================
-- DEPLOY NOTES
--
-- 1. Apply this migration before shipping the iOS Phase 7d build. With the
--    flag default TRUE, server is ready; widget calls will succeed.
-- 2. To disable widget writes in an emergency:
--      UPDATE internal_config SET value = 'false' WHERE key = 'widget_writes_enabled';
--    Effect is instant on the next RPC call. Widget extensions don't
--    receive an error — the call returns TRUE silently. The user-visible
--    behaviour reverts to "widget shows server-side numbers only" which
--    is exactly the Phase 7c (post-Phase 7d-disable) experience.
-- 3. To re-enable:
--      UPDATE internal_config SET value = 'true'  WHERE key = 'widget_writes_enabled';
-- 4. To revert: re-apply 20260618_log_challenge_progress_deadlock_retry.sql.
--    The kill-switch row in internal_config is harmless to leave in place.
-- ============================================================================
