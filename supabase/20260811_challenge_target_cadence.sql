-- ============================================================================
-- MIGRATION #177 — target_cadence column + cadence-aware progress / leaderboards
-- ============================================================================
--
-- Adds the missing `target_cadence` discriminator to all three challenge
-- parent tables, then teaches the progress writers and leaderboards what
-- "hit the target" means for each cadence:
--
--    daily       → progress >= daily_target (existing behavior; default)
--    weekly      → SUM(progress in current ISO week) >= daily_target
--                  (e.g. "5 runs in a week" → daily_target=5, iOS logs 1 per
--                  qualifying run on the day; server checks the week sum)
--    total       → cumulative SUM across all challenge days >= daily_target
--                  (e.g. "Marathon Month" → daily_target=100, target_unit='km')
--    per_session → THIS row's progress_value >= daily_target (single-session
--                  goal, e.g. "complete one 10K run in the next 14 days")
--
-- Streak loops are SUPPRESSED for non-daily cadences (weekly/total/per_session
-- have no daily-streak concept). `current_streak` is set to 0 for those rows;
-- `days_completed` is reused as a "qualifying days in window" counter.
--
-- The per-row `target_hit` column on `challenge_daily_progress` continues to
-- carry daily-cadence semantics (progress_value >= daily_target). For
-- non-daily cadences it stays FALSE on every row — the meaningful
-- "did the participant hit the target?" answer comes from the leaderboard
-- RPC's aggregation over the cadence window.
--
-- Pairs with: #176 (challenge_templates table that populates target_cadence
-- on every newly-created challenge from a template).
-- Apply order: #176 → #177.
-- ============================================================================

BEGIN;

-- ============================================================================
-- 1. ADD COLUMN target_cadence TO ALL 3 CHALLENGE PARENT TABLES
-- ============================================================================

ALTER TABLE group_challenges
    ADD COLUMN IF NOT EXISTS target_cadence TEXT NOT NULL DEFAULT 'daily'
    CHECK (target_cadence IN ('daily','weekly','total','per_session'));

ALTER TABLE community_challenges
    ADD COLUMN IF NOT EXISTS target_cadence TEXT NOT NULL DEFAULT 'daily'
    CHECK (target_cadence IN ('daily','weekly','total','per_session'));

ALTER TABLE private_challenges
    ADD COLUMN IF NOT EXISTS target_cadence TEXT NOT NULL DEFAULT 'daily'
    CHECK (target_cadence IN ('daily','weekly','total','per_session'));

-- Partial indexes — 99% of rows are 'daily', so we only index the rare path.
CREATE INDEX IF NOT EXISTS idx_group_challenges_cadence
    ON group_challenges (target_cadence)
    WHERE target_cadence <> 'daily';

CREATE INDEX IF NOT EXISTS idx_community_challenges_cadence
    ON community_challenges (target_cadence)
    WHERE target_cadence <> 'daily';

CREATE INDEX IF NOT EXISTS idx_private_challenges_cadence
    ON private_challenges (target_cadence)
    WHERE target_cadence <> 'daily';

-- ============================================================================
-- 2. log_challenge_progress (1v1/group) — cadence-aware
-- ============================================================================
-- Preserves the entire transient-HK-zero guard from #146 (20260720) verbatim.
-- The only additions are:
--   (a) read v_target_cadence from group_challenges
--   (b) compute v_target_hit per cadence (only meaningful for 'daily';
--       FALSE-by-default for the others)
--   (c) skip the daily-streak loop when cadence != 'daily'
--
-- Drop every known overload (supabase-rules invariant 12).

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
    v_target_cadence  TEXT;
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

    -- Phase 7d widget kill-switch (preserved from #129).
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

    -- Read both daily_target AND target_cadence from the challenge row.
    SELECT daily_target, COALESCE(target_cadence, 'daily')
      INTO v_daily_target, v_target_cadence
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

    -- target_hit semantics by cadence. Per-row target_hit is only meaningful
    -- for 'daily' — for the other cadences the leaderboard RPC computes
    -- "hit the target for THIS PERIOD" by aggregating over the window.
    IF v_target_cadence = 'daily' THEN
        v_target_hit := (v_daily_target IS NOT NULL AND p_progress_value >= v_daily_target);
    ELSIF v_target_cadence = 'per_session' THEN
        -- Single-session goal — this row alone qualifies if it clears the bar.
        v_target_hit := (v_daily_target IS NOT NULL AND p_progress_value >= v_daily_target);
    ELSE
        -- weekly / total — single row can't "hit" the aggregate target by itself.
        v_target_hit := FALSE;
    END IF;

    -- Deadlock retry loop (#119 recipe — preserved verbatim).
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
                    -- Transient-HK-zero guard from #146 (20260720) — preserved.
                    WHEN p_allow_decrease
                         AND EXCLUDED.progress_value = 0
                         AND challenge_daily_progress.progress_value > 0
                        THEN challenge_daily_progress.progress_value
                    WHEN p_allow_decrease THEN EXCLUDED.progress_value
                    ELSE GREATEST(challenge_daily_progress.progress_value, EXCLUDED.progress_value)
                END,
                target_hit = CASE
                    WHEN p_allow_decrease
                         AND EXCLUDED.progress_value = 0
                         AND challenge_daily_progress.progress_value > 0
                        THEN challenge_daily_progress.target_hit
                    WHEN p_allow_decrease THEN EXCLUDED.target_hit
                    WHEN EXCLUDED.progress_value > challenge_daily_progress.progress_value
                        THEN EXCLUDED.target_hit
                    ELSE challenge_daily_progress.target_hit
                END,
                source     = EXCLUDED.source,
                updated_at = NOW();

            -- Daily streak loop — only applies to 'daily' cadence. For
            -- weekly/total/per_session there's no day-by-day streak concept.
            IF v_target_cadence = 'daily' THEN
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
            ELSE
                -- Non-daily cadences: zero out the daily streak.
                v_current_streak := 0;
            END IF;

            -- Aggregate update on challenge_participants.
            -- For non-daily cadences, days_completed is repurposed as
            -- "qualifying days in window" — same SQL works (count of rows
            -- where progress_value >= effective threshold).
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
                          AND cdp.progress_value > 0
                          AND (
                              gc.target_cadence <> 'daily'
                              OR cdp.target_hit = TRUE
                              OR cdp.progress_value >= COALESCE(gc.daily_target, 0)
                          )
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
'1v1/group challenge progress writer. Cadence-aware (daily/weekly/total/per_session)
since 20260811. Caller-tz progress_date. Phase 7d widget kill-switch + deterministic
lock order + 40P01 retry. Preserves the transient-HK-zero guard from 20260720.';

-- ============================================================================
-- 3. log_private_challenge_progress — cadence-aware
-- ============================================================================
DROP FUNCTION IF EXISTS log_private_challenge_progress(TEXT, INT, TEXT);
DROP FUNCTION IF EXISTS log_private_challenge_progress(TEXT, INT, TEXT, BOOLEAN);

CREATE OR REPLACE FUNCTION log_private_challenge_progress(
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
    v_target_cadence  TEXT;
    v_target_hit      BOOLEAN;
    v_prev_target_hit BOOLEAN;
    v_attempt         INT := 0;
    v_max_attempts    CONSTANT INT := 3;
BEGIN
    current_user_uuid := auth.uid();
    IF current_user_uuid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'P0001';
    END IF;

    v_challenge_id := p_challenge_id::UUID;
    today_date     := (NOW() AT TIME ZONE COALESCE(NULLIF(p_timezone, ''), 'UTC'))::DATE;

    LOOP
        v_attempt := v_attempt + 1;
        BEGIN
            SELECT daily_target, COALESCE(target_cadence, 'daily')
              INTO v_daily_target, v_target_cadence
              FROM private_challenges
             WHERE id = v_challenge_id;

            IF v_target_cadence IN ('daily','per_session') THEN
                v_target_hit := (v_daily_target IS NOT NULL AND p_progress >= v_daily_target);
            ELSE
                v_target_hit := FALSE;
            END IF;

            PERFORM 1
              FROM private_challenge_members
             WHERE challenge_id = v_challenge_id
               AND user_id      = current_user_uuid
             FOR UPDATE;

            SELECT target_hit
              INTO v_prev_target_hit
              FROM private_challenge_daily_progress
             WHERE challenge_id  = v_challenge_id
               AND user_id       = current_user_uuid
               AND progress_date = today_date;

            INSERT INTO private_challenge_daily_progress (
                challenge_id, user_id, progress_date, progress_value, target_hit, source, updated_at
            ) VALUES (
                v_challenge_id, current_user_uuid, today_date, p_progress, v_target_hit, 'auto_sync', NOW()
            )
            ON CONFLICT (challenge_id, user_id, progress_date)
            DO UPDATE SET
                progress_value = CASE
                    -- Transient-HK-zero guard preserved from #146 (20260720).
                    WHEN p_allow_decrease
                         AND EXCLUDED.progress_value = 0
                         AND private_challenge_daily_progress.progress_value > 0
                        THEN private_challenge_daily_progress.progress_value
                    WHEN p_allow_decrease THEN EXCLUDED.progress_value
                    ELSE GREATEST(private_challenge_daily_progress.progress_value, EXCLUDED.progress_value)
                END,
                target_hit = CASE
                    WHEN p_allow_decrease
                         AND EXCLUDED.progress_value = 0
                         AND private_challenge_daily_progress.progress_value > 0
                        THEN private_challenge_daily_progress.target_hit
                    WHEN p_allow_decrease THEN EXCLUDED.target_hit
                    WHEN EXCLUDED.progress_value > private_challenge_daily_progress.progress_value
                        THEN EXCLUDED.target_hit
                    ELSE private_challenge_daily_progress.target_hit
                END,
                source     = EXCLUDED.source,
                updated_at = NOW();

            UPDATE private_challenge_members
               SET days_completed = CASE
                        -- For daily cadence: increment when target newly hit.
                        -- For non-daily cadences: count is rebuilt from
                        -- distinct days with progress_value > 0 (next branch).
                        WHEN v_target_cadence = 'daily'
                             AND v_target_hit
                             AND (v_prev_target_hit IS NULL OR NOT v_prev_target_hit)
                            THEN COALESCE(days_completed, 0) + 1
                        WHEN v_target_cadence <> 'daily'
                            THEN (
                                SELECT COUNT(*)
                                  FROM private_challenge_daily_progress pdp
                                 WHERE pdp.challenge_id = v_challenge_id
                                   AND pdp.user_id      = current_user_uuid
                                   AND pdp.progress_value > 0
                            )
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
                    RAISE;
                END IF;
                PERFORM pg_sleep(0.05 + (random() * 0.1));
        END;
    END LOOP;
END;
$$;

GRANT EXECUTE ON FUNCTION log_private_challenge_progress(TEXT, INT, TEXT, BOOLEAN) TO authenticated;

COMMENT ON FUNCTION log_private_challenge_progress(TEXT, INT, TEXT, BOOLEAN) IS
'Private group challenge progress writer. Cadence-aware since 20260811.
Preserves the transient-HK-zero guard from 20260720.';

-- ============================================================================
-- 4. log_community_challenge_progress — cadence-aware
-- ============================================================================
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
    v_target_cadence  TEXT;
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

    SELECT daily_target, COALESCE(target_cadence, 'daily')
      INTO v_daily_target, v_target_cadence
      FROM community_challenges
     WHERE id = v_challenge_id;

    IF v_target_cadence IN ('daily','per_session') THEN
        v_target_hit := (v_daily_target IS NOT NULL AND p_progress >= v_daily_target);
    ELSE
        v_target_hit := FALSE;
    END IF;

    LOOP
        v_attempt := v_attempt + 1;
        BEGIN
            PERFORM 1
              FROM community_challenge_participants
             WHERE challenge_id = v_challenge_id
               AND user_id      = current_user_uuid
             FOR UPDATE;

            SELECT target_hit INTO v_prev_target_hit
              FROM community_challenge_daily_progress
             WHERE challenge_id  = v_challenge_id
               AND user_id       = current_user_uuid
               AND progress_date = today_date;

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
                    -- Transient-HK-zero guard preserved from #146 (20260720).
                    WHEN p_allow_decrease
                         AND EXCLUDED.progress_value = 0
                         AND community_challenge_daily_progress.progress_value > 0
                        THEN community_challenge_daily_progress.progress_value
                    WHEN p_allow_decrease THEN EXCLUDED.progress_value
                    ELSE GREATEST(community_challenge_daily_progress.progress_value, EXCLUDED.progress_value)
                END,
                target_hit = CASE
                    WHEN p_allow_decrease
                         AND EXCLUDED.progress_value = 0
                         AND community_challenge_daily_progress.progress_value > 0
                        THEN community_challenge_daily_progress.target_hit
                    WHEN p_allow_decrease THEN EXCLUDED.target_hit
                    WHEN EXCLUDED.progress_value > community_challenge_daily_progress.progress_value
                        THEN EXCLUDED.target_hit
                    ELSE community_challenge_daily_progress.target_hit
                END,
                source     = EXCLUDED.source,
                updated_at = NOW();

            UPDATE community_challenge_participants
               SET days_completed = CASE
                       WHEN v_target_cadence = 'daily'
                            AND v_target_hit
                            AND (v_prev_target_hit IS NULL OR NOT v_prev_target_hit)
                           THEN COALESCE(days_completed, 0) + 1
                       WHEN v_target_cadence <> 'daily'
                           THEN (
                               SELECT COUNT(*)
                                 FROM community_challenge_daily_progress ccdp
                                WHERE ccdp.challenge_id = v_challenge_id
                                  AND ccdp.user_id      = current_user_uuid
                                  AND ccdp.progress_value > 0
                           )
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
                    RAISE;
                END IF;
                PERFORM pg_sleep(0.05 + (random() * 0.1));
        END;
    END LOOP;
END;
$$;

GRANT EXECUTE ON FUNCTION log_community_challenge_progress(TEXT, INT, TEXT, BOOLEAN) TO authenticated;

COMMENT ON FUNCTION log_community_challenge_progress(TEXT, INT, TEXT, BOOLEAN) IS
'Community challenge progress writer. Cadence-aware since 20260811.
Preserves the transient-HK-zero guard from 20260720.';

-- ============================================================================
-- 5. challenge_progress_summary view — surface target_cadence
-- ============================================================================
-- Re-creates the view to expose target_cadence + period_progress (the cadence-
-- aware "what to display" value). CRITICAL: re-apply security_invoker = on
-- after CREATE OR REPLACE because that command resets WITH options
-- (supabase-rules invariant 6).

CREATE OR REPLACE VIEW challenge_progress_summary AS
SELECT
    cp.challenge_id,
    cp.user_id,
    gc.challenge_type,
    gc.target_cadence,
    gc.title,
    gc.daily_target,
    gc.target_unit,
    gc.status AS challenge_status,
    gc.start_date,
    gc.end_date,
    cp.total_progress,
    cp.days_completed,
    cp.current_streak,
    cp.best_streak,
    -- Today's row (always populated regardless of cadence — used by widgets).
    COALESCE(
        (SELECT cdp.progress_value
           FROM challenge_daily_progress cdp
          WHERE cdp.challenge_id = cp.challenge_id
            AND cdp.user_id      = cp.user_id
            AND cdp.progress_date = CURRENT_DATE),
        0
    ) AS today_progress,
    COALESCE(
        (SELECT cdp.target_hit
           FROM challenge_daily_progress cdp
          WHERE cdp.challenge_id = cp.challenge_id
            AND cdp.user_id      = cp.user_id
            AND cdp.progress_date = CURRENT_DATE),
        FALSE
    ) AS today_target_hit,
    -- Period progress: what to display for the current cadence window.
    -- daily       → today's progress
    -- weekly      → SUM of progress_value in current ISO week
    -- total       → total_progress (all challenge days)
    -- per_session → MAX progress_value across challenge (best single session)
    CASE gc.target_cadence
        WHEN 'weekly' THEN COALESCE(
            (SELECT SUM(cdp.progress_value)::INT
               FROM challenge_daily_progress cdp
              WHERE cdp.challenge_id = cp.challenge_id
                AND cdp.user_id      = cp.user_id
                AND date_trunc('week', cdp.progress_date)
                  = date_trunc('week', CURRENT_DATE)),
            0
        )
        WHEN 'total' THEN cp.total_progress
        WHEN 'per_session' THEN COALESCE(
            (SELECT MAX(cdp.progress_value)::INT
               FROM challenge_daily_progress cdp
              WHERE cdp.challenge_id = cp.challenge_id
                AND cdp.user_id      = cp.user_id),
            0
        )
        ELSE COALESCE(
            (SELECT cdp.progress_value
               FROM challenge_daily_progress cdp
              WHERE cdp.challenge_id = cp.challenge_id
                AND cdp.user_id      = cp.user_id
                AND cdp.progress_date = CURRENT_DATE),
            0
        )
    END AS period_progress,
    up.name AS user_name,
    up.username AS user_username,
    up.profile_photo_url
FROM challenge_participants cp
JOIN group_challenges gc ON gc.id = cp.challenge_id
LEFT JOIN user_profiles up ON up.id = cp.user_id
WHERE cp.status = 'accepted';

-- Re-apply (or apply for the first time) security_invoker = on. Required
-- by supabase-rules invariant 6 — every public-schema view must invoke
-- with the calling user's permissions, not the view-owner's, so RLS on
-- the underlying tables is enforced.
ALTER VIEW challenge_progress_summary SET (security_invoker = on);

-- ============================================================================
-- 6. get_challenge_leaderboard — cadence-aware ranking + period_progress field
-- ============================================================================
-- Adds `period_progress` to the RETURNS TABLE (cadence-aware "what to display
-- for ranking purposes") and switches the rank ORDER BY to use it. Tie-break
-- ladder per supabase-expert: total_progress DESC → days_completed DESC →
-- current_streak DESC → joined_at ASC (deterministic).

DROP FUNCTION IF EXISTS get_challenge_leaderboard(TEXT);

CREATE OR REPLACE FUNCTION get_challenge_leaderboard(p_challenge_id TEXT)
RETURNS TABLE (
    user_id           UUID,
    user_name         TEXT,
    username          TEXT,
    profile_photo_url TEXT,
    total_progress    INT,
    today_progress    INT,
    period_progress   INT,
    days_completed    INT,
    current_streak    INT,
    best_streak       INT,
    target_cadence    TEXT,
    rank              INT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    challenge_uuid UUID;
    v_cadence      TEXT;
BEGIN
    challenge_uuid := p_challenge_id::UUID;

    -- Caller-must-be-participant guard (preserved from existing version).
    IF NOT EXISTS (
        SELECT 1 FROM challenge_participants
         WHERE challenge_id = challenge_uuid AND user_id = auth.uid()
    ) THEN
        RAISE EXCEPTION 'You are not a participant in this challenge';
    END IF;

    SELECT COALESCE(target_cadence, 'daily') INTO v_cadence
      FROM group_challenges WHERE id = challenge_uuid;

    RETURN QUERY
    WITH per_user AS (
        SELECT
            cp.user_id,
            up.name AS user_name,
            up.username,
            CASE WHEN COALESCE(up.privacy_hide_photo, FALSE) THEN NULL ELSE up.profile_photo_url END
                AS profile_photo_url,
            cp.total_progress,
            COALESCE(
                (SELECT cdp.progress_value
                   FROM challenge_daily_progress cdp
                  WHERE cdp.challenge_id = challenge_uuid
                    AND cdp.user_id = cp.user_id
                    AND cdp.progress_date = CURRENT_DATE),
                0
            )::INT AS today_progress,
            -- Cadence-aware ranking value:
            CASE v_cadence
                WHEN 'weekly' THEN COALESCE(
                    (SELECT SUM(cdp.progress_value)::INT
                       FROM challenge_daily_progress cdp
                      WHERE cdp.challenge_id = challenge_uuid
                        AND cdp.user_id = cp.user_id
                        AND date_trunc('week', cdp.progress_date)
                          = date_trunc('week', CURRENT_DATE)),
                    0
                )
                WHEN 'total' THEN cp.total_progress
                WHEN 'per_session' THEN COALESCE(
                    (SELECT MAX(cdp.progress_value)::INT
                       FROM challenge_daily_progress cdp
                      WHERE cdp.challenge_id = challenge_uuid
                        AND cdp.user_id = cp.user_id),
                    0
                )
                ELSE cp.total_progress
            END AS period_progress,
            cp.days_completed,
            cp.current_streak,
            COALESCE(cp.best_streak, 0)::INT AS best_streak,
            cp.joined_at
        FROM challenge_participants cp
        LEFT JOIN user_profiles up ON up.id = cp.user_id
        WHERE cp.challenge_id = challenge_uuid
          AND cp.status = 'accepted'
    )
    SELECT
        per_user.user_id,
        per_user.user_name,
        per_user.username,
        per_user.profile_photo_url,
        per_user.total_progress,
        per_user.today_progress,
        per_user.period_progress,
        per_user.days_completed,
        per_user.current_streak,
        per_user.best_streak,
        v_cadence AS target_cadence,
        ROW_NUMBER() OVER (ORDER BY
            per_user.period_progress DESC,
            per_user.total_progress DESC,
            per_user.days_completed DESC,
            per_user.current_streak DESC,
            per_user.joined_at ASC
        )::INT AS rank
    FROM per_user
    ORDER BY rank;
END;
$$;

GRANT EXECUTE ON FUNCTION get_challenge_leaderboard(TEXT) TO authenticated;

COMMENT ON FUNCTION get_challenge_leaderboard(TEXT) IS
'1v1/group leaderboard. Cadence-aware ranking since 20260811: ranks by
period_progress (today for daily, ISO-week SUM for weekly, total for total,
MAX session for per_session). Deterministic tie-break ladder.';

-- ============================================================================
-- 7. get_community_challenge_leaderboard — cadence-aware + period_progress
-- ============================================================================
-- Mirrors the 1v1 leaderboard's cadence-aware shape. Preserves photo-privacy
-- masking and user_blocks filtering from 20260330_privacy_photo_all_rpcs.

DROP FUNCTION IF EXISTS get_community_challenge_leaderboard(TEXT, INT, TEXT);

CREATE OR REPLACE FUNCTION get_community_challenge_leaderboard(
    p_challenge_id TEXT,
    p_limit        INT DEFAULT 20,
    p_timezone     TEXT DEFAULT 'UTC'
)
RETURNS TABLE (
    challenge_id      UUID,
    challenge_title   TEXT,
    challenge_emoji   TEXT,
    challenge_type    TEXT,
    target_cadence    TEXT,
    daily_target      INT,
    target_unit       TEXT,
    participant_count INT,
    join_code         TEXT,
    invite_slug       TEXT,
    leaderboard       JSONB,
    my_rank           INT,
    my_today_progress INT,
    my_period_progress INT,
    my_days_completed INT,
    my_current_streak INT,
    my_best_streak    INT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    current_user_uuid  UUID;
    v_challenge_id     UUID;
    today_date         DATE;
    v_cadence          TEXT;
    v_my_rank          INT;
    v_my_today         INT;
    v_my_period        INT;
    v_my_days          INT;
    v_my_streak        INT;
    v_my_best          INT;
BEGIN
    current_user_uuid := auth.uid();
    v_challenge_id := p_challenge_id::UUID;
    today_date := (NOW() AT TIME ZONE COALESCE(p_timezone, 'UTC'))::DATE;

    SELECT COALESCE(target_cadence, 'daily') INTO v_cadence
      FROM community_challenges WHERE id = v_challenge_id;

    -- My row + rank.
    WITH per_user AS (
        SELECT
            ccp.user_id,
            COALESCE(cdp.progress_value, 0) AS today_progress,
            CASE v_cadence
                WHEN 'weekly' THEN COALESCE(
                    (SELECT SUM(c2.progress_value)::INT
                       FROM community_challenge_daily_progress c2
                      WHERE c2.challenge_id = v_challenge_id
                        AND c2.user_id = ccp.user_id
                        AND date_trunc('week', c2.progress_date)
                          = date_trunc('week', today_date)),
                    0
                )
                WHEN 'total' THEN ccp.total_progress
                WHEN 'per_session' THEN COALESCE(
                    (SELECT MAX(c2.progress_value)::INT
                       FROM community_challenge_daily_progress c2
                      WHERE c2.challenge_id = v_challenge_id
                        AND c2.user_id = ccp.user_id),
                    0
                )
                ELSE COALESCE(cdp.progress_value, 0)
            END AS period_progress,
            ccp.days_completed,
            ccp.current_streak,
            ccp.best_streak,
            ccp.total_progress,
            ccp.joined_at,
            ROW_NUMBER() OVER (
                ORDER BY (
                    CASE v_cadence
                        WHEN 'weekly' THEN COALESCE(
                            (SELECT SUM(c2.progress_value)::INT
                               FROM community_challenge_daily_progress c2
                              WHERE c2.challenge_id = v_challenge_id
                                AND c2.user_id = ccp.user_id
                                AND date_trunc('week', c2.progress_date)
                                  = date_trunc('week', today_date)),
                            0
                        )
                        WHEN 'total' THEN ccp.total_progress
                        WHEN 'per_session' THEN COALESCE(
                            (SELECT MAX(c2.progress_value)::INT
                               FROM community_challenge_daily_progress c2
                              WHERE c2.challenge_id = v_challenge_id
                                AND c2.user_id = ccp.user_id),
                            0
                        )
                        ELSE COALESCE(cdp.progress_value, 0)
                    END
                ) DESC,
                ccp.total_progress DESC,
                ccp.days_completed DESC,
                ccp.current_streak DESC,
                ccp.joined_at ASC
            ) AS rank
        FROM community_challenge_participants ccp
        LEFT JOIN community_challenge_daily_progress cdp
          ON cdp.challenge_id = ccp.challenge_id
         AND cdp.user_id = ccp.user_id
         AND cdp.progress_date = today_date
        WHERE ccp.challenge_id = v_challenge_id
          AND ccp.is_active = TRUE
    )
    SELECT rank, today_progress, period_progress, days_completed, current_streak, best_streak
      INTO v_my_rank, v_my_today, v_my_period, v_my_days, v_my_streak, v_my_best
      FROM per_user
     WHERE user_id = current_user_uuid;

    RETURN QUERY
    SELECT
        cc.id,
        cc.title,
        cc.emoji,
        cc.challenge_type,
        v_cadence,
        cc.daily_target,
        cc.target_unit,
        cc.participant_count,
        cc.join_code,
        cc.invite_slug,
        (SELECT jsonb_agg(entry ORDER BY (entry->>'rank')::INT) FROM (
            SELECT jsonb_build_object(
                'rank', ROW_NUMBER() OVER (
                    ORDER BY (
                        CASE v_cadence
                            WHEN 'weekly' THEN COALESCE(
                                (SELECT SUM(c2.progress_value)::INT
                                   FROM community_challenge_daily_progress c2
                                  WHERE c2.challenge_id = v_challenge_id
                                    AND c2.user_id = ccp.user_id
                                    AND date_trunc('week', c2.progress_date)
                                      = date_trunc('week', today_date)),
                                0
                            )
                            WHEN 'total' THEN ccp.total_progress
                            WHEN 'per_session' THEN COALESCE(
                                (SELECT MAX(c2.progress_value)::INT
                                   FROM community_challenge_daily_progress c2
                                  WHERE c2.challenge_id = v_challenge_id
                                    AND c2.user_id = ccp.user_id),
                                0
                            )
                            ELSE COALESCE(cdp.progress_value, 0)
                        END
                    ) DESC,
                    ccp.total_progress DESC,
                    ccp.days_completed DESC,
                    ccp.joined_at ASC
                ),
                'user_id', ccp.user_id,
                'name', up.name,
                'username', up.username,
                'profile_photo_url', CASE WHEN COALESCE(up.privacy_hide_photo, FALSE) THEN NULL ELSE up.profile_photo_url END,
                'today_progress', COALESCE(cdp.progress_value, 0),
                'period_progress', CASE v_cadence
                    WHEN 'weekly' THEN COALESCE(
                        (SELECT SUM(c2.progress_value)::INT
                           FROM community_challenge_daily_progress c2
                          WHERE c2.challenge_id = v_challenge_id
                            AND c2.user_id = ccp.user_id
                            AND date_trunc('week', c2.progress_date)
                              = date_trunc('week', today_date)),
                        0
                    )
                    WHEN 'total' THEN ccp.total_progress
                    WHEN 'per_session' THEN COALESCE(
                        (SELECT MAX(c2.progress_value)::INT
                           FROM community_challenge_daily_progress c2
                          WHERE c2.challenge_id = v_challenge_id
                            AND c2.user_id = ccp.user_id),
                        0
                    )
                    ELSE COALESCE(cdp.progress_value, 0)
                END,
                'days_completed', ccp.days_completed,
                'current_streak', ccp.current_streak,
                'target_hit_today', COALESCE(cdp.target_hit, FALSE),
                'total_progress', COALESCE(ccp.total_progress, 0),
                'is_current_user', (ccp.user_id = current_user_uuid),
                'is_verified', COALESCE(up.is_verified, FALSE),
                'is_gold_verified', COALESCE(up.is_gold_verified, FALSE)
            ) AS entry
            FROM community_challenge_participants ccp
            JOIN user_profiles up ON up.id = ccp.user_id
            LEFT JOIN community_challenge_daily_progress cdp
              ON cdp.challenge_id = ccp.challenge_id
             AND cdp.user_id = ccp.user_id
             AND cdp.progress_date = today_date
            WHERE ccp.challenge_id = v_challenge_id
              AND ccp.is_active = TRUE
              AND NOT EXISTS (SELECT 1 FROM user_blocks ub
                  WHERE (ub.blocker_id = current_user_uuid AND ub.blocked_id = ccp.user_id)
                     OR (ub.blocker_id = ccp.user_id AND ub.blocked_id = current_user_uuid))
            ORDER BY (
                CASE v_cadence
                    WHEN 'weekly' THEN COALESCE(
                        (SELECT SUM(c2.progress_value)::INT
                           FROM community_challenge_daily_progress c2
                          WHERE c2.challenge_id = v_challenge_id
                            AND c2.user_id = ccp.user_id
                            AND date_trunc('week', c2.progress_date)
                              = date_trunc('week', today_date)),
                        0
                    )
                    WHEN 'total' THEN ccp.total_progress
                    WHEN 'per_session' THEN COALESCE(
                        (SELECT MAX(c2.progress_value)::INT
                           FROM community_challenge_daily_progress c2
                          WHERE c2.challenge_id = v_challenge_id
                            AND c2.user_id = ccp.user_id),
                        0
                    )
                    ELSE COALESCE(cdp.progress_value, 0)
                END
            ) DESC, ccp.total_progress DESC, ccp.days_completed DESC, ccp.joined_at ASC
            LIMIT p_limit
        ) sub),
        COALESCE(v_my_rank, 0)::INT,
        COALESCE(v_my_today, 0)::INT,
        COALESCE(v_my_period, 0)::INT,
        COALESCE(v_my_days, 0)::INT,
        COALESCE(v_my_streak, 0)::INT,
        COALESCE(v_my_best, 0)::INT
    FROM community_challenges cc
    WHERE cc.id = v_challenge_id;
END;
$$;

GRANT EXECUTE ON FUNCTION get_community_challenge_leaderboard(TEXT, INT, TEXT) TO authenticated;

COMMENT ON FUNCTION get_community_challenge_leaderboard(TEXT, INT, TEXT) IS
'Community leaderboard. Cadence-aware ranking since 20260811. Preserves
photo-privacy masking + user_blocks filtering from 20260330.';

-- ============================================================================
-- 8. AUDIT — fail-loud verification
-- ============================================================================

DO $$
DECLARE
    v_fn      TEXT;
    v_funcs   TEXT[] := ARRAY[
        'log_challenge_progress',
        'log_private_challenge_progress',
        'log_community_challenge_progress',
        'get_challenge_leaderboard',
        'get_community_challenge_leaderboard'
    ];
    v_count   INT;
    v_src     TEXT;
    v_invoker BOOLEAN;
BEGIN
    -- Each RPC must exist with exactly one overload (no drift).
    FOREACH v_fn IN ARRAY v_funcs LOOP
        SELECT COUNT(*), MAX(prosrc) INTO v_count, v_src
          FROM pg_proc p
          JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname = 'public' AND p.proname = v_fn;

        IF v_count <> 1 THEN
            RAISE EXCEPTION
                '[20260811 audit] expected exactly 1 % overload, got %', v_fn, v_count;
        END IF;
    END LOOP;

    -- The 3 progress writers MUST reference target_cadence (proves the
    -- new branch landed and we didn't accidentally restore the old body).
    FOREACH v_fn IN ARRAY ARRAY[
        'log_challenge_progress',
        'log_private_challenge_progress',
        'log_community_challenge_progress'
    ] LOOP
        SELECT prosrc INTO v_src
          FROM pg_proc p
          JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname = 'public' AND p.proname = v_fn;

        IF v_src !~ 'target_cadence' THEN
            RAISE EXCEPTION
                '[20260811 audit] %: cadence branch missing — function did not get re-created',
                v_fn;
        END IF;

        -- Zero-clobber guard from #146 must STILL be present (regression
        -- guard — preserves Manuel d10d5d03 fix while we were in here).
        IF v_src !~ 'EXCLUDED\.progress_value\s*=\s*0' THEN
            RAISE EXCEPTION
                '[20260811 audit] %: zero-clobber guard regressed — refusing to ship',
                v_fn;
        END IF;
    END LOOP;

    -- Both leaderboard RPCs must return period_progress.
    FOREACH v_fn IN ARRAY ARRAY[
        'get_challenge_leaderboard',
        'get_community_challenge_leaderboard'
    ] LOOP
        SELECT prosrc INTO v_src
          FROM pg_proc p
          JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname = 'public' AND p.proname = v_fn;

        IF v_src !~ 'period_progress' THEN
            RAISE EXCEPTION
                '[20260811 audit] %: period_progress field missing from RETURNS',
                v_fn;
        END IF;
    END LOOP;

    -- The view must have security_invoker = on (supabase-rules invariant 6).
    SELECT (SELECT (option_value::boolean)
              FROM unnest(c.reloptions) AS opt
              CROSS JOIN LATERAL (
                  SELECT split_part(opt, '=', 1) AS option_name,
                         split_part(opt, '=', 2) AS option_value
              ) o
             WHERE o.option_name = 'security_invoker'
             LIMIT 1)
      INTO v_invoker
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE n.nspname = 'public'
       AND c.relname = 'challenge_progress_summary';

    IF v_invoker IS DISTINCT FROM TRUE THEN
        RAISE EXCEPTION
            '[20260811 audit] challenge_progress_summary view is missing security_invoker = on (RLS bypass risk)';
    END IF;

    -- All 3 challenge tables must have target_cadence column.
    PERFORM 1 FROM information_schema.columns
     WHERE table_schema = 'public'
       AND table_name = 'group_challenges'
       AND column_name = 'target_cadence';
    IF NOT FOUND THEN
        RAISE EXCEPTION '[20260811 audit] group_challenges.target_cadence missing';
    END IF;

    PERFORM 1 FROM information_schema.columns
     WHERE table_schema = 'public'
       AND table_name = 'community_challenges'
       AND column_name = 'target_cadence';
    IF NOT FOUND THEN
        RAISE EXCEPTION '[20260811 audit] community_challenges.target_cadence missing';
    END IF;

    PERFORM 1 FROM information_schema.columns
     WHERE table_schema = 'public'
       AND table_name = 'private_challenges'
       AND column_name = 'target_cadence';
    IF NOT FOUND THEN
        RAISE EXCEPTION '[20260811 audit] private_challenges.target_cadence missing';
    END IF;

    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
    RAISE NOTICE '✅ MIGRATION #177 COMPLETE — target_cadence wired';
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
    RAISE NOTICE '   • target_cadence column on group/community/private challenges';
    RAISE NOTICE '   • 3 progress writers cadence-aware (zero-clobber guard preserved)';
    RAISE NOTICE '   • 2 leaderboards rank on period_progress with deterministic tie-break';
    RAISE NOTICE '   • challenge_progress_summary view exposes period_progress';
    RAISE NOTICE '   • security_invoker = on re-applied to view';
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
END $$;

COMMIT;
