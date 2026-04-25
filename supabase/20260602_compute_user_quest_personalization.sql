-- ============================================================================
-- 20260602 — Smart Adaptive Daily Goals: nightly personalization compute
--
-- Phase 2 of the personalization upgrade. Populates the three tables created
-- in 20260601 from a 28-day rolling window over user_daily_quests + workouts
-- + cardio_workouts. Runs nightly at 03:50 UTC (staggered between
-- compute-readiness-insights at 03:30 and bug-intel sweeps at 04:15) and is
-- backfilled once at install time so the RPC has data on day one.
--
-- Function:  compute_user_quest_personalization()  SECURITY DEFINER
-- Schedule:  pg_cron 'compute-user-quest-personalization-nightly'  '50 3 * * *'
--
-- All math is plain SQL — no edge function call needed (unlike Strava /
-- readiness insights which need Claude / network).
-- ============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.compute_user_quest_personalization()
RETURNS TABLE (
    users_processed     INT,
    cat_rows_upserted   INT,
    key_rows_upserted   INT,
    mix_rows_upserted   INT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_users_processed   INT := 0;
    v_cat_rows          INT := 0;
    v_key_rows          INT := 0;
    v_mix_rows          INT := 0;
    v_today             DATE := CURRENT_DATE;
    v_window_start      DATE := CURRENT_DATE - INTERVAL '28 days';
BEGIN
    -- ── 1. Per-(user, category) 28-day completion stats ────────────────
    -- We compute total_assigned and total_completed in one pass over
    -- user_daily_quests, then derive completion_rate.
    WITH cat_window AS (
        SELECT
            udq.user_id,
            udq.category,
            COUNT(*)::INT                                            AS total_assigned,
            COUNT(*) FILTER (WHERE udq.is_completed)::INT             AS total_completed,
            MAX(udq.completed_at) FILTER (WHERE udq.is_completed)     AS last_completed_at
        FROM user_daily_quests udq
        WHERE udq.quest_date >= v_window_start
          AND udq.quest_date <= v_today
        GROUP BY udq.user_id, udq.category
    ),
    -- Skip-streak: count consecutive days from today backward where this
    -- (user, category) had ≥1 assignment but ZERO completions. We walk
    -- distinct quest_dates per (user, category) and stop at the first day
    -- with a completion.
    daily_status AS (
        SELECT
            udq.user_id,
            udq.category,
            udq.quest_date,
            BOOL_OR(udq.is_completed) AS any_completed_that_day
        FROM user_daily_quests udq
        WHERE udq.quest_date >= v_window_start
          AND udq.quest_date <= v_today
        GROUP BY udq.user_id, udq.category, udq.quest_date
    ),
    skip_streaks AS (
        SELECT
            user_id,
            category,
            COUNT(*) FILTER (
                WHERE NOT any_completed_that_day
                  AND quest_date > COALESCE(
                      (SELECT MAX(d2.quest_date)
                         FROM daily_status d2
                        WHERE d2.user_id = ds.user_id
                          AND d2.category = ds.category
                          AND d2.any_completed_that_day),
                      v_window_start - INTERVAL '1 day'
                  )
            )::INT AS skip_streak
        FROM daily_status ds
        GROUP BY user_id, category
    )
    INSERT INTO user_quest_personalization (
        user_id, category,
        total_assigned_28d, total_completed_28d, completion_rate_28d,
        skip_streak, last_completed_at, suppressed_until,
        created_at, updated_at
    )
    SELECT
        cw.user_id,
        cw.category,
        cw.total_assigned,
        cw.total_completed,
        CASE WHEN cw.total_assigned > 0
             THEN ROUND((cw.total_completed::NUMERIC / cw.total_assigned)::NUMERIC, 4)
             ELSE 0
        END,
        COALESCE(ss.skip_streak, 0),
        cw.last_completed_at,
        -- Suppression rule: ≥3-day skip streak AND <20% completion → 14-day cooldown
        CASE
            WHEN COALESCE(ss.skip_streak, 0) >= 3
             AND cw.total_assigned >= 3
             AND (cw.total_completed::NUMERIC / NULLIF(cw.total_assigned, 0)) < 0.20
            THEN v_today + INTERVAL '14 days'
            ELSE NULL
        END,
        now(), now()
    FROM cat_window cw
    LEFT JOIN skip_streaks ss
        ON ss.user_id = cw.user_id AND ss.category = cw.category
    ON CONFLICT (user_id, category) DO UPDATE SET
        total_assigned_28d  = EXCLUDED.total_assigned_28d,
        total_completed_28d = EXCLUDED.total_completed_28d,
        completion_rate_28d = EXCLUDED.completion_rate_28d,
        skip_streak         = EXCLUDED.skip_streak,
        last_completed_at   = COALESCE(EXCLUDED.last_completed_at, user_quest_personalization.last_completed_at),
        -- Auto-decay: if the existing suppression has expired OR a new
        -- completion landed since the last compute, clear the window.
        suppressed_until    = CASE
            WHEN EXCLUDED.suppressed_until IS NOT NULL
              THEN EXCLUDED.suppressed_until
            WHEN user_quest_personalization.suppressed_until IS NOT NULL
             AND user_quest_personalization.suppressed_until <= v_today
              THEN NULL
            WHEN EXCLUDED.last_completed_at IS NOT NULL
             AND EXCLUDED.last_completed_at > COALESCE(user_quest_personalization.last_completed_at, '-infinity')
              THEN NULL
            ELSE user_quest_personalization.suppressed_until
        END,
        updated_at          = now();

    GET DIAGNOSTICS v_cat_rows = ROW_COUNT;

    -- ── 2. Per-(user, quest_key) 28-day stats ──────────────────────────
    WITH key_window AS (
        SELECT
            udq.user_id,
            udq.quest_key,
            COUNT(*)::INT                                            AS total_assigned,
            COUNT(*) FILTER (WHERE udq.is_completed)::INT             AS total_completed,
            MAX(udq.completed_at) FILTER (WHERE udq.is_completed)     AS last_completed_at
        FROM user_daily_quests udq
        WHERE udq.quest_date >= v_window_start
          AND udq.quest_date <= v_today
        GROUP BY udq.user_id, udq.quest_key
    )
    INSERT INTO user_quest_key_stats (
        user_id, quest_key,
        total_assigned_28d, total_completed_28d, completion_rate_28d,
        last_completed_at, suppressed_until,
        created_at, updated_at
    )
    SELECT
        kw.user_id,
        kw.quest_key,
        kw.total_assigned,
        kw.total_completed,
        CASE WHEN kw.total_assigned > 0
             THEN ROUND((kw.total_completed::NUMERIC / kw.total_assigned)::NUMERIC, 4)
             ELSE 0
        END,
        kw.last_completed_at,
        -- Per-key suppression is stricter: 4 assignments + <15% rate.
        CASE
            WHEN kw.total_assigned >= 4
             AND (kw.total_completed::NUMERIC / NULLIF(kw.total_assigned, 0)) < 0.15
            THEN v_today + INTERVAL '14 days'
            ELSE NULL
        END,
        now(), now()
    FROM key_window kw
    ON CONFLICT (user_id, quest_key) DO UPDATE SET
        total_assigned_28d  = EXCLUDED.total_assigned_28d,
        total_completed_28d = EXCLUDED.total_completed_28d,
        completion_rate_28d = EXCLUDED.completion_rate_28d,
        last_completed_at   = COALESCE(EXCLUDED.last_completed_at, user_quest_key_stats.last_completed_at),
        suppressed_until    = CASE
            WHEN EXCLUDED.suppressed_until IS NOT NULL
              THEN EXCLUDED.suppressed_until
            WHEN user_quest_key_stats.suppressed_until IS NOT NULL
             AND user_quest_key_stats.suppressed_until <= v_today
              THEN NULL
            WHEN EXCLUDED.last_completed_at IS NOT NULL
             AND EXCLUDED.last_completed_at > COALESCE(user_quest_key_stats.last_completed_at, '-infinity')
              THEN NULL
            ELSE user_quest_key_stats.suppressed_until
        END,
        updated_at          = now();

    GET DIAGNOSTICS v_key_rows = ROW_COUNT;

    -- ── 3. user_activity_mix from workouts + cardio_workouts ───────────
    -- workouts → strength
    -- cardio_workouts.activity_type 'walk' / 'hike' → walk
    -- cardio_workouts.activity_type 'yoga' / 'stretch' / 'mobility' / 'foam_rolling' → stretch
    -- everything else in cardio_workouts → cardio
    WITH strength AS (
        -- The canonical `workouts` table uses a DATE column named `date`
        -- (see 20260327_engagement_scoring.sql line 14 — `MAX(date) AS
        -- last_workout`). It is NOT a TIMESTAMPTZ. v_window_start /
        -- v_today are both DATE so the comparison is straightforward.
        SELECT user_id, COUNT(*)::INT AS n
          FROM workouts
         WHERE date >= v_window_start
           AND date <= v_today
         GROUP BY user_id
    ),
    cardio_buckets AS (
        SELECT
            user_id,
            COUNT(*) FILTER (WHERE activity_type IN ('walk', 'hike'))::INT                                  AS walk_n,
            COUNT(*) FILTER (WHERE activity_type IN ('yoga', 'stretch', 'mobility', 'foam_rolling'))::INT   AS stretch_n,
            COUNT(*) FILTER (WHERE activity_type NOT IN ('walk', 'hike', 'yoga', 'stretch', 'mobility', 'foam_rolling'))::INT AS cardio_n
        FROM cardio_workouts
        WHERE started_at >= v_window_start
          AND started_at <= v_today + INTERVAL '1 day'
        GROUP BY user_id
    ),
    combined AS (
        SELECT
            COALESCE(s.user_id, c.user_id) AS user_id,
            COALESCE(s.n, 0)               AS strength_n,
            COALESCE(c.cardio_n, 0)        AS cardio_n,
            COALESCE(c.walk_n, 0)          AS walk_n,
            COALESCE(c.stretch_n, 0)       AS stretch_n
        FROM strength s
        FULL OUTER JOIN cardio_buckets c ON c.user_id = s.user_id
    ),
    shares AS (
        SELECT
            user_id,
            (strength_n + cardio_n + walk_n + stretch_n) AS total_n,
            strength_n, cardio_n, walk_n, stretch_n
        FROM combined
    )
    INSERT INTO user_activity_mix (
        user_id, computed_at, total_sessions_28d,
        strength_share, cardio_share, walk_share, stretch_share,
        dominant_category, least_category
    )
    SELECT
        user_id,
        now(),
        total_n,
        CASE WHEN total_n > 0 THEN ROUND((strength_n::NUMERIC / total_n)::NUMERIC, 4) ELSE 0 END,
        CASE WHEN total_n > 0 THEN ROUND((cardio_n  ::NUMERIC / total_n)::NUMERIC, 4) ELSE 0 END,
        CASE WHEN total_n > 0 THEN ROUND((walk_n    ::NUMERIC / total_n)::NUMERIC, 4) ELSE 0 END,
        CASE WHEN total_n > 0 THEN ROUND((stretch_n ::NUMERIC / total_n)::NUMERIC, 4) ELSE 0 END,
        -- Dominant: max of the four (only if total_n >= 3 to avoid noise).
        CASE
            WHEN total_n < 3 THEN NULL
            WHEN strength_n >= GREATEST(cardio_n, walk_n, stretch_n) THEN 'strength'
            WHEN cardio_n   >= GREATEST(strength_n, walk_n, stretch_n) THEN 'cardio'
            WHEN walk_n     >= GREATEST(strength_n, cardio_n, stretch_n) THEN 'walk'
            ELSE 'stretch'
        END,
        -- Least: min non-zero, or NULL when nothing else logged
        CASE
            WHEN total_n < 3 THEN NULL
            WHEN strength_n <= LEAST(cardio_n, walk_n, stretch_n) AND strength_n < total_n THEN 'strength'
            WHEN cardio_n   <= LEAST(strength_n, walk_n, stretch_n) AND cardio_n < total_n THEN 'cardio'
            WHEN walk_n     <= LEAST(strength_n, cardio_n, stretch_n) AND walk_n < total_n THEN 'walk'
            ELSE 'stretch'
        END
    FROM shares
    WHERE total_n > 0
    ON CONFLICT (user_id) DO UPDATE SET
        computed_at         = EXCLUDED.computed_at,
        total_sessions_28d  = EXCLUDED.total_sessions_28d,
        strength_share      = EXCLUDED.strength_share,
        cardio_share        = EXCLUDED.cardio_share,
        walk_share          = EXCLUDED.walk_share,
        stretch_share       = EXCLUDED.stretch_share,
        dominant_category   = EXCLUDED.dominant_category,
        least_category      = EXCLUDED.least_category;

    GET DIAGNOSTICS v_mix_rows = ROW_COUNT;

    -- ── 4. users_processed: distinct users we touched ──────────────────
    SELECT COUNT(DISTINCT user_id)::INT INTO v_users_processed
      FROM (
          SELECT user_id FROM user_quest_personalization
          UNION
          SELECT user_id FROM user_quest_key_stats
          UNION
          SELECT user_id FROM user_activity_mix
      ) all_users;

    RETURN QUERY SELECT v_users_processed, v_cat_rows, v_key_rows, v_mix_rows;
END;
$$;

REVOKE ALL ON FUNCTION public.compute_user_quest_personalization() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.compute_user_quest_personalization() TO service_role;

COMMENT ON FUNCTION public.compute_user_quest_personalization() IS
    'Smart Adaptive Daily Goals: nightly compute that populates user_quest_personalization, user_quest_key_stats, user_activity_mix from a 28-day window over user_daily_quests + workouts + cardio_workouts. Service-role only.';

-- ── Schedule ──────────────────────────────────────────────────────────
-- 03:50 UTC — between compute-strava-insights (03:40) and bug-intel
-- sweeps (04:00 / 04:15 / 04:30). Per Supabase invariant 25 stagger rule.
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
        IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'compute-user-quest-personalization-nightly') THEN
            PERFORM cron.unschedule('compute-user-quest-personalization-nightly');
        END IF;

        PERFORM cron.schedule(
            'compute-user-quest-personalization-nightly',
            '50 3 * * *',
            $cron$ SELECT public.compute_user_quest_personalization() $cron$
        );
        RAISE NOTICE '✅ Scheduled compute-user-quest-personalization-nightly (03:50 UTC daily)';
    ELSE
        RAISE NOTICE 'pg_cron not installed — compute_user_quest_personalization() must be invoked manually';
    END IF;
END $$;

-- ── Initial backfill so day-one users have data ───────────────────────
DO $$
DECLARE
    v_result RECORD;
BEGIN
    SELECT * INTO v_result FROM public.compute_user_quest_personalization();
    RAISE NOTICE '✅ 20260602 backfill: users=%, cat_rows=%, key_rows=%, mix_rows=%',
        v_result.users_processed, v_result.cat_rows_upserted,
        v_result.key_rows_upserted, v_result.mix_rows_upserted;
END $$;

COMMIT;

-- ─── Verification ──────────────────────────────────────────────────────
-- SELECT * FROM public.compute_user_quest_personalization();
-- SELECT user_id, dominant_category, least_category, total_sessions_28d
--   FROM user_activity_mix ORDER BY total_sessions_28d DESC LIMIT 10;
-- SELECT user_id, category, completion_rate_28d, skip_streak, suppressed_until
--   FROM user_quest_personalization
--  WHERE suppressed_until IS NOT NULL;
