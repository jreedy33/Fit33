-- ════════════════════════════════════════════════════════════════════
-- BUNDLE: C — Smart Adaptive Daily Goals (8 files; #20260610 supersedes 20260606)
-- Concatenated 2026-04-25 14:34 EDT from individual migrations
-- on disk under supabase/. Each source file keeps its own
-- BEGIN; ... COMMIT; — paste this whole file into the SQL editor
-- and Postgres will run them serially as separate transactions.
-- All idempotent: safe to re-run.
-- ════════════════════════════════════════════════════════════════════


-- ════════════════════════════════════════════════════════════════════
-- SOURCE: supabase/20260601_user_quest_personalization_schema.sql
-- ════════════════════════════════════════════════════════════════════

-- ============================================================================
-- 20260601 — Smart Adaptive Daily Goals: per-user learning schema
--
-- Phase 1 of the daily-goals personalization upgrade. Adds three per-user
-- tables that the nightly cron (migration 20260602) populates and that the
-- new `get_daily_quests` body (migration 20260605) reads from to bias goal
-- selection toward what the user actually does + suppress categories the
-- user keeps skipping ("if they keep ignoring meals, stop showing meals").
--
-- Tables:
--   * user_quest_personalization (user_id, category, …)
--       28-day completion stats + skip_streak + suppression window
--       per CATEGORY (workout / nutrition / steps / social / tracking / …).
--   * user_quest_key_stats (user_id, quest_key, …)
--       Same but at quest_key grain, so individual unloved quests
--       (e.g. weekly_weigh_in) decay independently of their category.
--   * user_activity_mix (user_id, …)
--       28-day shares of strength / cardio / walk / stretch sessions —
--       drives the "lean into your dominant + sneak in opposite" rule.
--
-- Plus quest_templates.tier ('free' | 'pro') so monetization migration
-- 20260607 can paywall extra-slot / Pro-only templates without breaking
-- existing rows (default 'free').
--
-- Idempotent / safe to re-run.
-- ============================================================================

BEGIN;

-- ── 1. user_quest_personalization ──────────────────────────────────────
CREATE TABLE IF NOT EXISTS user_quest_personalization (
    user_id                UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
    category               TEXT NOT NULL,
    total_assigned_28d     INT NOT NULL DEFAULT 0,
    total_completed_28d    INT NOT NULL DEFAULT 0,
    completion_rate_28d    NUMERIC(5,4) NOT NULL DEFAULT 0,
    skip_streak            INT NOT NULL DEFAULT 0,
    last_completed_at      TIMESTAMPTZ,
    suppressed_until       DATE,
    created_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, category)
);

CREATE INDEX IF NOT EXISTS idx_user_quest_personalization_user
    ON user_quest_personalization(user_id);
CREATE INDEX IF NOT EXISTS idx_user_quest_personalization_suppressed
    ON user_quest_personalization(user_id, suppressed_until)
    WHERE suppressed_until IS NOT NULL;

ALTER TABLE user_quest_personalization ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "uqp_select_own"   ON user_quest_personalization;
DROP POLICY IF EXISTS "uqp_insert_own"   ON user_quest_personalization;
DROP POLICY IF EXISTS "uqp_update_own"   ON user_quest_personalization;
DROP POLICY IF EXISTS "uqp_delete_own"   ON user_quest_personalization;

CREATE POLICY "uqp_select_own" ON user_quest_personalization
    FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "uqp_insert_own" ON user_quest_personalization
    FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "uqp_update_own" ON user_quest_personalization
    FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "uqp_delete_own" ON user_quest_personalization
    FOR DELETE USING (auth.uid() = user_id);


-- ── 2. user_quest_key_stats ────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS user_quest_key_stats (
    user_id                UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
    quest_key              TEXT NOT NULL,
    total_assigned_28d     INT NOT NULL DEFAULT 0,
    total_completed_28d    INT NOT NULL DEFAULT 0,
    completion_rate_28d    NUMERIC(5,4) NOT NULL DEFAULT 0,
    last_completed_at      TIMESTAMPTZ,
    suppressed_until       DATE,
    created_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, quest_key)
);

CREATE INDEX IF NOT EXISTS idx_user_quest_key_stats_user
    ON user_quest_key_stats(user_id);
CREATE INDEX IF NOT EXISTS idx_user_quest_key_stats_top
    ON user_quest_key_stats(user_id, completion_rate_28d DESC)
    WHERE total_assigned_28d >= 3;

ALTER TABLE user_quest_key_stats ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "uqks_select_own"   ON user_quest_key_stats;
DROP POLICY IF EXISTS "uqks_insert_own"   ON user_quest_key_stats;
DROP POLICY IF EXISTS "uqks_update_own"   ON user_quest_key_stats;
DROP POLICY IF EXISTS "uqks_delete_own"   ON user_quest_key_stats;

CREATE POLICY "uqks_select_own" ON user_quest_key_stats
    FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "uqks_insert_own" ON user_quest_key_stats
    FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "uqks_update_own" ON user_quest_key_stats
    FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "uqks_delete_own" ON user_quest_key_stats
    FOR DELETE USING (auth.uid() = user_id);


-- ── 3. user_activity_mix ───────────────────────────────────────────────
-- One row per user. Shares sum to ~1.0 (when total_sessions_28d > 0). Cron
-- recomputes nightly. The RPC reads this once per call to bias category
-- selection toward the user's dominant share and gently surface the
-- opposite ("sneak in cardio if they only lift").
CREATE TABLE IF NOT EXISTS user_activity_mix (
    user_id                UUID PRIMARY KEY REFERENCES user_profiles(id) ON DELETE CASCADE,
    computed_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
    total_sessions_28d     INT NOT NULL DEFAULT 0,
    strength_share         NUMERIC(5,4) NOT NULL DEFAULT 0,
    cardio_share           NUMERIC(5,4) NOT NULL DEFAULT 0,
    walk_share             NUMERIC(5,4) NOT NULL DEFAULT 0,
    stretch_share          NUMERIC(5,4) NOT NULL DEFAULT 0,
    dominant_category      TEXT,            -- 'strength' | 'cardio' | 'walk' | 'stretch' | NULL
    least_category         TEXT
);

ALTER TABLE user_activity_mix ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "uam_select_own"   ON user_activity_mix;
DROP POLICY IF EXISTS "uam_insert_own"   ON user_activity_mix;
DROP POLICY IF EXISTS "uam_update_own"   ON user_activity_mix;
DROP POLICY IF EXISTS "uam_delete_own"   ON user_activity_mix;

CREATE POLICY "uam_select_own" ON user_activity_mix
    FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "uam_insert_own" ON user_activity_mix
    FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "uam_update_own" ON user_activity_mix
    FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "uam_delete_own" ON user_activity_mix
    FOR DELETE USING (auth.uid() = user_id);


-- ── 4. quest_templates.tier ────────────────────────────────────────────
-- Default 'free' so every existing row stays free-tier (no accidental
-- paywall on legacy templates). Pro templates land in migration 20260607.
ALTER TABLE quest_templates
    ADD COLUMN IF NOT EXISTS tier TEXT NOT NULL DEFAULT 'free'
        CHECK (tier IN ('free', 'pro'));

CREATE INDEX IF NOT EXISTS idx_quest_templates_tier
    ON quest_templates(tier, is_active);


-- ── 5. delete_user_account — explicit cleanup of new tables ────────────
-- ON DELETE CASCADE on user_profiles(id) handles this implicitly, but we
-- match the existing canonical pattern in `complete_account_deletion.sql`
-- of explicitly deleting major tables before the user_profiles row drops.
-- The RPC is wrapped in DO block so a missing legacy version doesn't fail
-- the migration. We patch the function in-place via CREATE OR REPLACE in
-- the same shape as the canonical owner.
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM pg_proc
        WHERE proname = 'delete_user_account'
          AND pronamespace = 'public'::regnamespace
    ) THEN
        -- The canonical body already CASCADEs from user_profiles. We add
        -- explicit DELETEs as a defense-in-depth measure (Supabase
        -- invariant 3) without rewriting the whole function: a tiny
        -- wrapper trigger on user_profiles BEFORE DELETE handles the new
        -- tables. CASCADE handles them anyway, but a trigger fires even
        -- if the FK constraint is later relaxed.
        NULL;
    END IF;
END $$;

-- Defensive cleanup trigger — fires before user_profiles row deletion.
CREATE OR REPLACE FUNCTION cleanup_user_quest_personalization()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    DELETE FROM user_quest_personalization WHERE user_id = OLD.id;
    DELETE FROM user_quest_key_stats        WHERE user_id = OLD.id;
    DELETE FROM user_activity_mix           WHERE user_id = OLD.id;
    RETURN OLD;
END;
$$;

DROP TRIGGER IF EXISTS trg_cleanup_user_quest_personalization ON user_profiles;
CREATE TRIGGER trg_cleanup_user_quest_personalization
    BEFORE DELETE ON user_profiles
    FOR EACH ROW
    EXECUTE FUNCTION cleanup_user_quest_personalization();


-- ── 6. Comments for the next engineer ──────────────────────────────────
COMMENT ON TABLE  user_quest_personalization IS
    'Smart Adaptive Daily Goals: 28-day completion stats + suppression window per (user, category). Populated nightly by compute_user_quest_personalization() (20260602). Read by get_daily_quests v3 (20260605).';
COMMENT ON TABLE  user_quest_key_stats IS
    'Smart Adaptive Daily Goals: 28-day completion stats per (user, quest_key). Finer grain than user_quest_personalization so individual unloved keys can decay without dragging their whole category.';
COMMENT ON TABLE  user_activity_mix IS
    'Smart Adaptive Daily Goals: 28-day strength / cardio / walk / stretch shares per user. Drives the "lean into dominant + sneak-in opposite" bias in get_daily_quests v3.';
COMMENT ON COLUMN user_quest_personalization.suppressed_until IS
    'When set, the RPC excludes this category from the eligibility pool until this date. Set when skip_streak >= 3 AND completion_rate_28d < 0.20. Auto-cleared by any completion in this category.';
COMMENT ON COLUMN quest_templates.tier IS
    'Smart Adaptive Daily Goals: free templates available to all users; pro templates only returned when get_daily_quests is called with p_quest_tier=''pro'' (Pro subscriber).';

DO $$
BEGIN
    RAISE NOTICE '✅ 20260601: Smart Adaptive Daily Goals schema ready. Run 20260602 to populate the new tables, 20260605 to flip the RPC.';
END $$;

COMMIT;

-- ─── Verification ──────────────────────────────────────────────────────
-- SELECT table_name
--   FROM information_schema.tables
--  WHERE table_schema = 'public'
--    AND table_name IN ('user_quest_personalization', 'user_quest_key_stats', 'user_activity_mix');
--
-- SELECT column_name, data_type
--   FROM information_schema.columns
--  WHERE table_name = 'quest_templates' AND column_name = 'tier';


-- ════════════════════════════════════════════════════════════════════
-- SOURCE: supabase/20260602_compute_user_quest_personalization.sql
-- ════════════════════════════════════════════════════════════════════

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


-- ════════════════════════════════════════════════════════════════════
-- SOURCE: supabase/20260603_quest_templates_xp_tier_rebalance.sql
-- ════════════════════════════════════════════════════════════════════

-- ============================================================================
-- 20260603 — Smart Adaptive Daily Goals: XP rebalance by verification type
--
-- Phase 3 of the personalization upgrade. The user's direction was:
--   "auto-tracked goals from all sources should have more xp points cause
--    we can prove verify. input goals should typically be less as they are
--    honor system."
--
-- One-shot UPDATE on quest_templates.xp_reward + league_points using:
--   * auto    × 1.5  (auto-verifiable: HealthKit / Strava / WHOOP / Oura /
--                    Fitbit / completed-workout flag from the app)
--   * social  × 1.0  (in-app action with server-side proof: react, comment,
--                    challenge join)
--   * manual  × 0.7  (honor-system manual logging: meals, hydration,
--                    self-reported weight)
--
-- Idempotent: tracked via internal_config row 'quest_xp_rebalance_20260603'
-- so re-running this migration is a no-op.
-- ============================================================================

BEGIN;

DO $$
DECLARE
    v_already_run TEXT;
    v_auto_rows   INT := 0;
    v_social_rows INT := 0;
    v_manual_rows INT := 0;
BEGIN
    SELECT value INTO v_already_run
      FROM internal_config
     WHERE key = 'quest_xp_rebalance_20260603';

    IF v_already_run IS NOT NULL THEN
        RAISE NOTICE 'Skipping XP rebalance — already applied at %', v_already_run;
        RETURN;
    END IF;

    -- ── auto ×1.5 ──────────────────────────────────────────────────────
    UPDATE quest_templates
       SET xp_reward     = GREATEST(5, ROUND(xp_reward     * 1.5)::INT),
           league_points = GREATEST(5, ROUND(league_points * 1.5)::INT)
     WHERE verification_type = 'auto'
       AND is_active = TRUE;
    GET DIAGNOSTICS v_auto_rows = ROW_COUNT;

    -- ── social ×1.0 (no change, but recorded for audit) ────────────────
    -- Intentionally a no-op pass — keeps XP unchanged but verifies the
    -- branch is hit. Skip if you want; recorded as 0 rows.
    SELECT 0 INTO v_social_rows;

    -- ── manual ×0.7 ────────────────────────────────────────────────────
    UPDATE quest_templates
       SET xp_reward     = GREATEST(5, ROUND(xp_reward     * 0.7)::INT),
           league_points = GREATEST(5, ROUND(league_points * 0.7)::INT)
     WHERE verification_type = 'manual'
       AND is_active = TRUE;
    GET DIAGNOSTICS v_manual_rows = ROW_COUNT;

    -- ── Idempotency marker ────────────────────────────────────────────
    -- internal_config schema is (key TEXT PRIMARY KEY, value TEXT) only
    -- (see 20260324_push_notification_cron.sql line 20). No updated_at
    -- column — the timestamp is embedded in `value` for audit.
    INSERT INTO internal_config (key, value)
    VALUES ('quest_xp_rebalance_20260603', now()::TEXT)
    ON CONFLICT (key) DO UPDATE SET
        value = EXCLUDED.value;

    RAISE NOTICE '✅ 20260603: rebalanced quest_templates XP — auto=% rows ×1.5, manual=% rows ×0.7 (social unchanged)',
        v_auto_rows, v_manual_rows;
END $$;

COMMIT;

-- ─── Verification ──────────────────────────────────────────────────────
-- SELECT verification_type, COUNT(*), AVG(xp_reward)::INT, AVG(league_points)::INT
--   FROM quest_templates
--  WHERE is_active = TRUE
--  GROUP BY verification_type
--  ORDER BY verification_type;
--
-- Expected after rebalance: auto avg ≈ 30-50, social ≈ 20, manual ≈ 15.


-- ════════════════════════════════════════════════════════════════════
-- SOURCE: supabase/20260604_strava_pr_and_friend_quest_templates.sql
-- ════════════════════════════════════════════════════════════════════

-- ============================================================================
-- 20260604 — Smart Adaptive Daily Goals: new fun + Strava PR + friend templates
--
-- Phase 4 of the personalization upgrade. Adds three buckets of new
-- quest templates the v3 RPC will surface:
--
--   1. Strava PR / outdoor (auto, premium-XP, requires_context = 'has_strava'):
--        beat_your_5k_pr, negative_split_run, run_outside_8km,
--        cycle_outside_30km, complete_strava_segment
--
--   2. Wearable additions (auto, requires_context per device):
--        match_yesterday_strain (has_whoop)
--        walk_when_red          (has_wearable)
--
--   3. Friend-named fun quests (social, drives delight + retention):
--        do_friend_workout              (NEW key — server replaces title
--                                        with split-aware copy in v3 RPC)
--        comment_on_friends_workout     (NEW)
--        start_1v1_with_top_friend      (NEW)
--        react_to_3_workouts            (NEW companion to react_to_workout)
--
-- requires_context values used here. The v3 RPC (20260605) gates eligibility:
--   * 'has_strava'   — only when p_strava_connected = TRUE
--   * 'has_whoop'    — only when p_whoop_connected = TRUE
--   * 'has_wearable' — union OR of all 4 (kept for legacy templates)
--
-- Idempotent. ON CONFLICT preserves admin overrides on existing rows.
-- XP values are POST-rebalance (auto×1.5 / social×1.0 already applied) so
-- they do NOT get re-multiplied — migration 20260603's idempotency marker
-- ensures it doesn't re-run.
-- ============================================================================

BEGIN;

-- ── 1. Strava PR / outdoor templates (has_strava) ──────────────────────
INSERT INTO quest_templates (
    quest_key, title, description, icon, category,
    target_value, target_unit, xp_reward, league_points,
    difficulty, weight, requires_context, fun_label,
    verification_type, min_workouts
) VALUES
    ('beat_your_5k_pr',
        'Beat Your 5K PR',
        'Set a new 5K personal record',
        'flag.checkered',
        'workout', 1, 'run',
        75, 40, 'hard', 4, 'has_strava',
        '🏆 Chase the PR',
        'auto', 14),

    ('negative_split_run',
        'Negative Split',
        'Run faster on the back half today',
        'arrow.up.right',
        'workout', 1, 'run',
        60, 30, 'hard', 5, 'has_strava',
        '⚡ Strong finish',
        'auto', 10),

    ('run_outside_8km',
        'Long Run',
        'Run 8K outside today',
        'figure.run',
        'workout', 8000, 'meters',
        55, 28, 'hard', 5, 'has_strava',
        '🛣️ Time on feet',
        'auto', 10),

    ('cycle_outside_30km',
        'Big Ride',
        'Cycle 30K outside today',
        'figure.outdoor.cycle',
        'workout', 30000, 'meters',
        60, 30, 'hard', 5, 'has_strava',
        '🚴 Send the long road',
        'auto', 10),

    ('complete_strava_segment',
        'Segment Hunter',
        'Finish a Strava segment today',
        'mappin.and.ellipse',
        'workout', 1, 'segment',
        40, 20, 'medium', 6, 'has_strava',
        '📍 Bag a segment',
        'auto', 4)

ON CONFLICT (quest_key) DO UPDATE SET
    title              = EXCLUDED.title,
    description        = EXCLUDED.description,
    icon               = EXCLUDED.icon,
    category           = EXCLUDED.category,
    target_value       = EXCLUDED.target_value,
    target_unit        = EXCLUDED.target_unit,
    xp_reward          = EXCLUDED.xp_reward,
    league_points      = EXCLUDED.league_points,
    difficulty         = EXCLUDED.difficulty,
    weight             = EXCLUDED.weight,
    requires_context   = EXCLUDED.requires_context,
    fun_label          = EXCLUDED.fun_label,
    verification_type  = EXCLUDED.verification_type,
    min_workouts       = EXCLUDED.min_workouts;


-- ── 2. Wearable additions ──────────────────────────────────────────────
INSERT INTO quest_templates (
    quest_key, title, description, icon, category,
    target_value, target_unit, xp_reward, league_points,
    difficulty, weight, requires_context, fun_label,
    verification_type, min_workouts
) VALUES
    ('match_yesterday_strain',
        'Match the Strain',
        'Match yesterday''s WHOOP strain',
        'bolt.fill',
        'workout', 1, 'day',
        35, 20, 'medium', 5, 'has_whoop',
        '🔥 Repeat the effort',
        'auto', 7),

    ('walk_when_red',
        'Walk on Red',
        'Walk 20+ min on a red recovery day',
        'figure.walk',
        'workout', 20, 'minutes',
        25, 15, 'easy', 6, 'has_wearable',
        '🟥 Active recovery',
        'auto', 0)

ON CONFLICT (quest_key) DO UPDATE SET
    title              = EXCLUDED.title,
    description        = EXCLUDED.description,
    icon               = EXCLUDED.icon,
    category           = EXCLUDED.category,
    target_value       = EXCLUDED.target_value,
    target_unit        = EXCLUDED.target_unit,
    xp_reward          = EXCLUDED.xp_reward,
    league_points      = EXCLUDED.league_points,
    difficulty         = EXCLUDED.difficulty,
    weight             = EXCLUDED.weight,
    requires_context   = EXCLUDED.requires_context,
    fun_label          = EXCLUDED.fun_label,
    verification_type  = EXCLUDED.verification_type,
    min_workouts       = EXCLUDED.min_workouts;


-- ── 3. Friend-named fun quests ─────────────────────────────────────────
-- The v3 RPC (20260605) rewrites these titles with friend names + split
-- recommendation when seeds are passed. Default copy below is the
-- fallback when no friend seeds are present.
INSERT INTO quest_templates (
    quest_key, title, description, icon, category,
    target_value, target_unit, xp_reward, league_points,
    difficulty, weight, requires_context, fun_label,
    verification_type, min_workouts
) VALUES
    ('do_friend_workout',
        'Do a Friend''s Workout',
        'Run a workout shared by a friend',
        'figure.2',
        'workout', 1, 'workout',
        35, 20, 'medium', 7, 'has_friends',
        '🤝 Train with the crew',
        'social', 4),

    ('comment_on_friends_workout',
        'Hype a Friend',
        'Comment on a friend''s workout',
        'bubble.left.fill',
        'social', 1, 'comment',
        15, 10, 'easy', 8, 'has_friends',
        '💬 Show some love',
        'social', 0),

    ('start_1v1_with_top_friend',
        'Start a 1v1',
        'Challenge your top friend today',
        'flag.2.crossed.fill',
        'social', 1, 'challenge',
        30, 20, 'medium', 6, 'has_friends_no_challenge',
        '⚔️ Bring the heat',
        'social', 2),

    ('react_to_3_workouts',
        'Spread the Hype',
        'React to 3 friends'' workouts',
        'hands.clap.fill',
        'social', 3, 'reactions',
        20, 12, 'easy', 7, 'has_friends',
        '👏 Hype train',
        'social', 0)

ON CONFLICT (quest_key) DO UPDATE SET
    title              = EXCLUDED.title,
    description        = EXCLUDED.description,
    icon               = EXCLUDED.icon,
    category           = EXCLUDED.category,
    target_value       = EXCLUDED.target_value,
    target_unit        = EXCLUDED.target_unit,
    xp_reward          = EXCLUDED.xp_reward,
    league_points      = EXCLUDED.league_points,
    difficulty         = EXCLUDED.difficulty,
    weight             = EXCLUDED.weight,
    requires_context   = EXCLUDED.requires_context,
    fun_label          = EXCLUDED.fun_label,
    verification_type  = EXCLUDED.verification_type,
    min_workouts       = EXCLUDED.min_workouts;


DO $$
DECLARE
    v_strava_count   INT;
    v_wearable_count INT;
    v_friend_count   INT;
BEGIN
    SELECT COUNT(*) INTO v_strava_count
      FROM quest_templates
     WHERE quest_key IN (
        'beat_your_5k_pr','negative_split_run','run_outside_8km',
        'cycle_outside_30km','complete_strava_segment'
     );
    SELECT COUNT(*) INTO v_wearable_count
      FROM quest_templates
     WHERE quest_key IN ('match_yesterday_strain', 'walk_when_red');
    SELECT COUNT(*) INTO v_friend_count
      FROM quest_templates
     WHERE quest_key IN (
        'do_friend_workout','comment_on_friends_workout',
        'start_1v1_with_top_friend','react_to_3_workouts'
     );
    RAISE NOTICE '✅ 20260604 templates: strava_pr=% / wearable_add=% / friend=% (gated requires_context — surfaced by v3 RPC 20260605)',
        v_strava_count, v_wearable_count, v_friend_count;
END $$;

COMMIT;

-- ─── Verification ──────────────────────────────────────────────────────
-- SELECT quest_key, requires_context, verification_type, xp_reward, difficulty
--   FROM quest_templates
--  WHERE quest_key IN (
--     'beat_your_5k_pr','negative_split_run','run_outside_8km',
--     'cycle_outside_30km','complete_strava_segment',
--     'match_yesterday_strain','walk_when_red',
--     'do_friend_workout','comment_on_friends_workout',
--     'start_1v1_with_top_friend','react_to_3_workouts'
--  )
--  ORDER BY requires_context, quest_key;


-- ════════════════════════════════════════════════════════════════════
-- SOURCE: supabase/20260605_get_daily_quests_personalized.sql
-- ════════════════════════════════════════════════════════════════════

-- ============================================================================
-- 20260605 — Smart Adaptive Daily Goals: get_daily_quests v3 (6 layers)
--
-- Resolves: e656ad7a4fb1323db476cd8f2cf6ac39 — get_daily_quests PGRST202 (Report 5 / 04-25 audit)
-- Resolves: 486b89c025c019b7f2b6c427a437811e — same PGRST202, log variant (Report 20 / 04-25 audit)
--
-- Phase 5 of the personalization upgrade. New body keeps every existing
-- contract from 20260423 (slot 1 workout, redundancy matrix, challenge
-- override, category diversity) and adds three new layers:
--
--   Layer 4: ACTIVITY-MIX BIAS + PER-USER WEIGHTING
--     +30% selection score when quest activity-bucket aligns with the
--           user's dominant share in p_activity_mix (cardio user → cardio).
--     +25% when quest_key has user_quest_key_stats.completion_rate_28d ≥ 0.75
--           (the user keeps finishing this — surface it again).
--     +10% gentle "exploration" bump on the user's least-touched bucket
--           (sneak in cardio for a strength-heavy user, etc.) — only when
--           the category is NOT suppressed.
--     −90% when (user_id, quest_key) or (user_id, category) is suppressed
--           (effectively excluded — "stop showing it if they keep skipping").
--
--   Layer 5: SKIP-STREAK FLOOR
--     If after layer 4 a slot still wins with a suppressed quest (because
--     the pool is too thin), fall back to the next-best non-suppressed
--     category from the existing diversity ladder.
--
--   Layer 6: FRIEND-NAMED COPY + PRO EXTRA SLOTS
--     * Step quests rewritten to "Beat <FriendName>: 8.4K" when
--       p_friend_step_target > 0.
--     * do_friend_workout preferred over complete_workout for slot 1 when
--       p_friend_top_workout_title is set, with split-recommendation-aware
--       copy:
--         matches_recommendation = TRUE  → "Due for <split> — do <Friend>'s"
--         matches_recommendation = FALSE → "Do <Friend>'s <Title>"
--     * p_quest_tier = 'pro' → 5 slots (slot 4 exploration, slot 5 hard wildcard).
--
-- New eligibility predicates added to the requires_context branch (this
-- also retires the stub at the bottom of 20260509_wearable_quests.sql):
--   has_wearable / has_strava / has_whoop / has_oura / has_fitbit /
--   has_friends_no_challenge.
--
-- New params (all nullable / default-safe — old clients don't break):
--   p_strava_connected, p_whoop_connected, p_oura_connected,
--   p_fitbit_connected, p_activity_mix JSONB, p_friend_step_target,
--   p_friend_name, p_friend_top_workout_id, p_friend_top_workout_title,
--   p_friend_top_workout_split, p_friend_top_workout_matches_recommendation,
--   p_quest_tier.
--
-- Idempotent: drops every existing overload via the canonical pg_proc loop
-- before CREATE OR REPLACE (Supabase invariant 12).
-- ============================================================================

BEGIN;

DO $$
DECLARE
    v_sig TEXT;
BEGIN
    FOR v_sig IN
        SELECT oid::regprocedure::text
        FROM pg_proc
        WHERE proname = 'get_daily_quests'
          AND pronamespace = 'public'::regnamespace
    LOOP
        EXECUTE 'DROP FUNCTION IF EXISTS ' || v_sig || ' CASCADE';
    END LOOP;
END $$;

CREATE OR REPLACE FUNCTION get_daily_quests(
    p_user_id                                       TEXT,
    p_timezone                                      TEXT DEFAULT 'America/New_York',
    p_has_program                                   BOOLEAN DEFAULT FALSE,
    p_has_friends                                   BOOLEAN DEFAULT FALSE,
    p_has_challenge                                 BOOLEAN DEFAULT FALSE,
    p_step_goal                                     INT DEFAULT 10000,
    p_fitness_goal                                  TEXT DEFAULT 'general',
    p_is_subscriber                                 BOOLEAN DEFAULT FALSE,
    p_workout_streak                                INT DEFAULT 0,
    p_total_workouts                                INT DEFAULT 0,
    p_preferred_time                                TEXT DEFAULT 'any',
    p_avg_duration                                  INT DEFAULT 45,
    p_has_weight_log                                BOOLEAN DEFAULT FALSE,
    p_hydration_active                              BOOLEAN DEFAULT FALSE,
    p_league_rank                                   INT DEFAULT 0,
    p_active_step_challenge_target                  INT DEFAULT 0,
    p_suggested_split                               TEXT DEFAULT NULL,
    p_fatigued_regions                              TEXT[] DEFAULT '{}',
    p_active_challenge_types                        TEXT[] DEFAULT '{}',
    p_has_connected_wearable                        BOOLEAN DEFAULT FALSE,
    -- Smart Adaptive Daily Goals (20260605) ───────────────────────────
    p_strava_connected                              BOOLEAN DEFAULT FALSE,
    p_whoop_connected                               BOOLEAN DEFAULT FALSE,
    p_oura_connected                                BOOLEAN DEFAULT FALSE,
    p_fitbit_connected                              BOOLEAN DEFAULT FALSE,
    p_activity_mix                                  JSONB   DEFAULT '{}'::jsonb,
    p_friend_step_target                            INT     DEFAULT 0,
    p_friend_name                                   TEXT    DEFAULT NULL,
    p_friend_top_workout_id                         UUID    DEFAULT NULL,
    p_friend_top_workout_title                      TEXT    DEFAULT NULL,
    p_friend_top_workout_split                      TEXT    DEFAULT NULL,
    p_friend_top_workout_matches_recommendation     BOOLEAN DEFAULT FALSE,
    p_quest_tier                                    TEXT    DEFAULT 'free'
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id                UUID := p_user_id::UUID;
    v_caller_id              UUID := auth.uid();
    v_today                  DATE;
    v_quest_count            INT;
    v_streak                 RECORD;
    v_bonus_claimed          BOOLEAN := FALSE;
    v_all_complete           BOOLEAN := FALSE;
    v_day_seed               INT;
    v_difficulty_profile     TEXT;
    v_quest_keys             TEXT[] := '{}';
    v_pool_easy              TEXT[];
    v_pool_medium            TEXT[];
    v_pool_hard              TEXT[];
    v_recent_keys            TEXT[];
    v_total_wk               INT  := COALESCE(p_total_workouts, 0);
    v_wk_streak              INT  := COALESCE(p_workout_streak, 0);
    v_preferred_workout_key  TEXT;
    v_step_keys              TEXT[] := ARRAY[
        'walk_3k_steps', 'walk_5k_steps', 'walk_7500_steps',
        'walk_10k_steps', 'hit_step_goal'
    ];
    v_redundant_with_workout TEXT[] := ARRAY[
        'active_minutes_30', 'burn_300_calories', 'workout_30_min',
        'exercise_sets_15', 'exercise_sets_25', 'beat_volume_pr',
        'stretch_session', 'maintain_streak', 'league_3_workouts',
        'complete_2_workouts', 'early_bird_workout'
    ];
    v_redundant_with_steps   TEXT[] := ARRAY[
        'active_minutes_30', 'burn_300_calories'
    ];
    v_slot1_is_workout       BOOLEAN;
    v_slot1_is_steps         BOOLEAN;
    v_challenge_quest_keys   TEXT[] := '{}';
    v_distinct_cats          INT;
    v_category_ladder        TEXT[];
    v_swap_candidate         TEXT;
    v_i                      INT;
    v_pro                    BOOLEAN := (LOWER(COALESCE(p_quest_tier, 'free')) = 'pro');
    v_target_slots           INT := CASE WHEN v_pro THEN 5 ELSE 3 END;
    v_dominant_bucket        TEXT;
    v_least_bucket           TEXT;
    v_friend_step_label      TEXT;
    v_friend_workout_copy    TEXT;
    v_friend_workout_short   TEXT;
BEGIN
    -- IDOR guard (Data invariant 7). The RPC is SECURITY DEFINER; we
    -- never trust p_user_id when an authenticated caller is present.
    -- Service-role + cron contexts (auth.uid() IS NULL) are allowed
    -- through unchanged so backfills + admin tools still work.
    IF v_caller_id IS NOT NULL AND v_caller_id <> v_user_id THEN
        RAISE EXCEPTION 'get_daily_quests IDOR: caller % does not match p_user_id %', v_caller_id, v_user_id
            USING ERRCODE = '42501';
    END IF;

    v_today := (now() AT TIME ZONE p_timezone)::DATE;
    v_day_seed := abs(hashtext(v_user_id::TEXT || v_today::TEXT));

    -- ── Slot 1 preferred key (unchanged) ───────────────────────────────
    IF p_has_program THEN
        v_preferred_workout_key := 'complete_program_day';
    ELSE
        v_preferred_workout_key := 'complete_workout';
    END IF;
    v_slot1_is_workout := v_preferred_workout_key IN (
        'complete_workout', 'complete_program_day', 'complete_2_workouts'
    );

    -- ── Difficulty profile (unchanged) ─────────────────────────────────
    IF v_wk_streak >= 7 OR v_total_wk >= 100 THEN
        v_difficulty_profile := CASE
            WHEN v_day_seed % 5 = 0 THEN 'easy_day'
            WHEN v_day_seed % 3 = 0 THEN 'hard_day'
            ELSE 'mixed_day'
        END;
    ELSIF v_total_wk >= 20 THEN
        v_difficulty_profile := CASE
            WHEN v_day_seed % 4 = 0 THEN 'hard_day'
            ELSE 'mixed_day'
        END;
    ELSE
        v_difficulty_profile := CASE
            WHEN v_day_seed % 3 = 0 THEN 'mixed_day'
            ELSE 'easy_day'
        END;
    END IF;

    -- ── Activity-mix dominant / least bucket (Layer 4 inputs) ──────────
    -- Read from p_activity_mix JSONB OR fall back to user_activity_mix table.
    SELECT
        COALESCE(
            p_activity_mix->>'dominant',
            (SELECT dominant_category FROM user_activity_mix WHERE user_id = v_user_id)
        ),
        COALESCE(
            p_activity_mix->>'least',
            (SELECT least_category FROM user_activity_mix WHERE user_id = v_user_id)
        )
    INTO v_dominant_bucket, v_least_bucket;

    SELECT COUNT(*) INTO v_quest_count
    FROM user_daily_quests
    WHERE user_id = v_user_id AND quest_date = v_today;

    -- ───────────────────────────────────────────────────────────────────
    -- Only build/insert when today's slate hasn't been generated yet.
    -- ───────────────────────────────────────────────────────────────────
    IF v_quest_count = 0 THEN
        SELECT COALESCE(ARRAY_AGG(DISTINCT quest_key), '{}') INTO v_recent_keys
        FROM user_daily_quests
        WHERE user_id = v_user_id
          AND quest_date >= v_today - INTERVAL '3 days'
          AND quest_date < v_today;

        -- ── Challenge override list ────────────────────────────────────
        IF 'active_minutes' = ANY(p_active_challenge_types) THEN
            v_challenge_quest_keys := array_append(v_challenge_quest_keys, 'active_minutes_30');
        END IF;
        IF 'calories' = ANY(p_active_challenge_types) THEN
            v_challenge_quest_keys := array_append(v_challenge_quest_keys, 'burn_300_calories');
        END IF;
        IF 'hydrate' = ANY(p_active_challenge_types) THEN
            v_challenge_quest_keys := array_append(v_challenge_quest_keys, 'log_water_8');
        END IF;
        IF 'protein' = ANY(p_active_challenge_types) THEN
            v_challenge_quest_keys := array_append(v_challenge_quest_keys, 'hit_protein_goal');
        END IF;
        IF 'workout_streak' = ANY(p_active_challenge_types) THEN
            v_challenge_quest_keys := array_append(v_challenge_quest_keys, 'maintain_streak');
        END IF;
        IF 'lift' = ANY(p_active_challenge_types) THEN
            v_challenge_quest_keys := array_append(v_challenge_quest_keys, 'exercise_sets_15');
        END IF;

        -- ── Eligibility pool (with NEW context predicates + Pro tier) ──
        DROP TABLE IF EXISTS _eligible_quests;
        CREATE TEMP TABLE _eligible_quests ON COMMIT DROP AS
        SELECT qt.quest_key, qt.category, qt.difficulty, qt.verification_type, qt.tier,
               qt.weight,
               -- Activity bucket per quest (mapped from quest_key for granularity).
               CASE
                   WHEN qt.quest_key IN (
                       'walk_3k_steps','walk_5k_steps','walk_7500_steps',
                       'walk_10k_steps','hit_step_goal','walk_when_red'
                   ) THEN 'walk'
                   WHEN qt.quest_key IN (
                       'run_outside_3km','run_outside_5km','run_outside_8km',
                       'cycle_outside_15km','cycle_outside_30km','beat_your_5k_pr',
                       'negative_split_run','complete_strava_segment',
                       'active_minutes_30','burn_300_calories'
                   ) THEN 'cardio'
                   WHEN qt.quest_key IN ('stretch_session') THEN 'stretch'
                   WHEN qt.category = 'workout' THEN 'strength'
                   ELSE NULL
               END AS activity_bucket
        FROM quest_templates qt
        WHERE qt.is_active = TRUE
          AND qt.is_premium = FALSE
          AND COALESCE(qt.min_workouts, 0) <= v_total_wk
          AND qt.quest_key != ALL(v_recent_keys)
          AND qt.quest_key NOT IN ('upper_body_workout', 'lower_body_workout')
          -- Tier gating: free tier excludes 'pro' templates.
          AND (v_pro OR qt.tier = 'free')
          AND NOT (
                v_slot1_is_workout
                AND qt.quest_key = ANY(v_redundant_with_workout)
                AND qt.quest_key <> ALL(v_challenge_quest_keys)
          )
          AND (
                qt.requires_context IS NULL
             OR (qt.requires_context = 'has_program'              AND p_has_program)
             OR (qt.requires_context = 'has_friends'              AND p_has_friends)
             OR (qt.requires_context = 'has_challenge'            AND p_has_challenge)
             OR (qt.requires_context = 'no_friends'               AND NOT p_has_friends)
             OR (qt.requires_context = 'no_challenge'             AND NOT p_has_challenge)
             OR (qt.requires_context = 'free_user'                AND NOT p_is_subscriber)
             OR (qt.requires_context = 'has_wearable'             AND (p_has_connected_wearable
                                                                    OR p_strava_connected
                                                                    OR p_whoop_connected
                                                                    OR p_oura_connected
                                                                    OR p_fitbit_connected))
             OR (qt.requires_context = 'has_strava'               AND p_strava_connected)
             OR (qt.requires_context = 'has_whoop'                AND p_whoop_connected)
             OR (qt.requires_context = 'has_oura'                 AND p_oura_connected)
             OR (qt.requires_context = 'has_fitbit'               AND p_fitbit_connected)
             OR (qt.requires_context = 'has_friends_no_challenge' AND p_has_friends AND NOT p_has_challenge)
          );

        -- Suppression filter (Layer 4 / "stop showing it if they keep
        -- skipping it"). Removes any quest_key whose (user, key) has an
        -- active suppressed_until OR whose (user, category) is suppressed.
        -- Challenge-override keys are NEVER suppressed — challenges always
        -- win the floor.
        DELETE FROM _eligible_quests eq
        WHERE eq.quest_key <> ALL(v_challenge_quest_keys)
          AND (
                EXISTS (
                    SELECT 1 FROM user_quest_key_stats s
                    WHERE s.user_id = v_user_id
                      AND s.quest_key = eq.quest_key
                      AND s.suppressed_until IS NOT NULL
                      AND s.suppressed_until > v_today
                )
             OR EXISTS (
                    SELECT 1 FROM user_quest_personalization p
                    WHERE p.user_id = v_user_id
                      AND p.category = eq.category
                      AND p.suppressed_until IS NOT NULL
                      AND p.suppressed_until > v_today
                )
          );

        -- ── Layer 4: scored pool ──────────────────────────────────────
        -- Score = base weight × (1 + dominant_bias + favorite_bias + explore_bias)
        -- Suppression already removed above (effectively −∞), so we don't
        -- recompute the −90% term — it's enforced by exclusion.
        DROP TABLE IF EXISTS _scored_quests;
        CREATE TEMP TABLE _scored_quests ON COMMIT DROP AS
        SELECT
            eq.*,
            (
                eq.weight::NUMERIC
                * (1.0
                    + CASE WHEN v_dominant_bucket IS NOT NULL
                              AND eq.activity_bucket = v_dominant_bucket
                           THEN 0.30 ELSE 0.0 END
                    + CASE WHEN EXISTS (
                              SELECT 1 FROM user_quest_key_stats s
                              WHERE s.user_id = v_user_id
                                AND s.quest_key = eq.quest_key
                                AND s.total_assigned_28d >= 3
                                AND s.completion_rate_28d >= 0.75
                          ) THEN 0.25 ELSE 0.0 END
                    + CASE WHEN v_least_bucket IS NOT NULL
                              AND eq.activity_bucket = v_least_bucket
                           THEN 0.10 ELSE 0.0 END
                  )
            ) AS selection_score
        FROM _eligible_quests eq;

        -- Snap pool buckets from scored set so the existing ARRAY index
        -- math still works.
        SELECT ARRAY_AGG(quest_key ORDER BY selection_score DESC, (abs(hashtext(quest_key)) + v_day_seed) % 11)
          INTO v_pool_easy   FROM _scored_quests WHERE difficulty = 'easy';
        SELECT ARRAY_AGG(quest_key ORDER BY selection_score DESC, (abs(hashtext(quest_key)) + v_day_seed) % 11)
          INTO v_pool_medium FROM _scored_quests WHERE difficulty = 'medium';
        SELECT ARRAY_AGG(quest_key ORDER BY selection_score DESC, (abs(hashtext(quest_key)) + v_day_seed) % 11)
          INTO v_pool_hard   FROM _scored_quests WHERE difficulty = 'hard';

        -- Fallback seeds if a bucket came up empty (e.g. brand new user
        -- with thin templates after suppression).
        v_pool_easy   := COALESCE(v_pool_easy,   ARRAY['complete_workout', 'walk_5k_steps', 'log_breakfast']);
        v_pool_medium := COALESCE(v_pool_medium, ARRAY['log_3_meals', 'walk_7500_steps', 'log_water_8']);
        v_pool_hard   := COALESCE(v_pool_hard,   ARRAY['hit_step_goal', 'log_water_8', 'hit_protein_goal']);

        IF v_difficulty_profile = 'easy_day' THEN
            v_quest_keys := ARRAY[
                v_pool_easy[1 + (v_day_seed       % array_length(v_pool_easy,   1))],
                v_pool_easy[1 + ((v_day_seed + 1) % array_length(v_pool_easy,   1))],
                v_pool_medium[1 + (v_day_seed     % array_length(v_pool_medium, 1))]
            ];
        ELSIF v_difficulty_profile = 'hard_day' THEN
            v_quest_keys := ARRAY[
                v_pool_medium[1 + (v_day_seed       % array_length(v_pool_medium, 1))],
                v_pool_hard[1 + (v_day_seed         % array_length(v_pool_hard,   1))],
                v_pool_medium[1 + ((v_day_seed + 2) % array_length(v_pool_medium, 1))]
            ];
        ELSE
            v_quest_keys := ARRAY[
                v_pool_easy[1 + (v_day_seed   % array_length(v_pool_easy,   1))],
                v_pool_medium[1 + (v_day_seed % array_length(v_pool_medium, 1))],
                v_pool_hard[1 + (v_day_seed   % array_length(v_pool_hard,   1))]
            ];
        END IF;

        -- Force slot 1 to the preferred workout key.
        IF v_preferred_workout_key IS NOT NULL
           AND EXISTS (SELECT 1 FROM quest_templates WHERE quest_key = v_preferred_workout_key AND is_active)
           AND v_preferred_workout_key <> ALL(v_quest_keys) THEN
            v_quest_keys[1] := v_preferred_workout_key;
        END IF;

        v_slot1_is_steps := v_quest_keys[1] IN ('hit_step_goal', 'walk_10k_steps');

        -- ── Layer 6a: friend-named slot 1 swap ────────────────────────
        -- When the user has a recent shared friend workout AND
        -- do_friend_workout is in the eligibility pool, prefer it over
        -- the generic workout slot. The Swift caller has already done
        -- the muscle-recovery-aware ranking; here we just honor the seed.
        IF p_friend_top_workout_title IS NOT NULL
           AND p_friend_name IS NOT NULL
           AND EXISTS (SELECT 1 FROM _scored_quests WHERE quest_key = 'do_friend_workout') THEN
            v_quest_keys[1] := 'do_friend_workout';
            v_slot1_is_workout := TRUE;  -- still anchors as workout for diversity ladder
        END IF;

        -- ── Challenge override (unchanged 20260423 behavior) ──────────
        IF array_length(v_challenge_quest_keys, 1) > 0 THEN
            FOR v_i IN 1..array_length(v_challenge_quest_keys, 1) LOOP
                IF v_challenge_quest_keys[v_i] = ANY(v_quest_keys) THEN
                    CONTINUE;
                END IF;
                IF EXISTS (SELECT 1 FROM quest_templates WHERE quest_key = v_challenge_quest_keys[v_i] AND is_active) THEN
                    IF v_i = 1 THEN
                        v_quest_keys[2] := v_challenge_quest_keys[v_i];
                    ELSE
                        v_quest_keys[3] := v_challenge_quest_keys[v_i];
                        EXIT;
                    END IF;
                END IF;
            END LOOP;
        END IF;

        -- Redundancy sweep with steps slot 1 (unchanged).
        IF v_slot1_is_steps THEN
            FOR v_i IN 2..3 LOOP
                IF v_quest_keys[v_i] = ANY(v_redundant_with_steps)
                   AND v_quest_keys[v_i] <> ALL(v_challenge_quest_keys) THEN
                    SELECT quest_key INTO v_swap_candidate
                    FROM _scored_quests
                    WHERE category IN ('nutrition', 'tracking')
                      AND quest_key <> ALL(v_quest_keys)
                    ORDER BY selection_score DESC, (abs(hashtext(quest_key)) + v_day_seed) % 11
                    LIMIT 1;
                    IF v_swap_candidate IS NOT NULL THEN
                        v_quest_keys[v_i] := v_swap_candidate;
                    END IF;
                END IF;
            END LOOP;
        END IF;

        -- ── Category diversity (unchanged) ────────────────────────────
        SELECT COUNT(DISTINCT qt.category)
          INTO v_distinct_cats
        FROM quest_templates qt
        WHERE qt.quest_key = ANY(v_quest_keys);

        IF v_distinct_cats < 2 THEN
            IF v_slot1_is_workout THEN
                v_category_ladder := ARRAY['nutrition', 'steps', 'tracking', 'social'];
            ELSIF v_slot1_is_steps THEN
                v_category_ladder := ARRAY['nutrition', 'workout', 'tracking', 'social'];
            ELSE
                v_category_ladder := ARRAY['nutrition', 'workout', 'steps', 'tracking'];
            END IF;

            FOR v_i IN 1..array_length(v_category_ladder, 1) LOOP
                IF NOT EXISTS (
                    SELECT 1 FROM quest_templates
                    WHERE quest_key = ANY(v_quest_keys)
                      AND category = v_category_ladder[v_i]
                ) THEN
                    SELECT quest_key INTO v_swap_candidate
                    FROM _scored_quests
                    WHERE category = v_category_ladder[v_i]
                      AND quest_key <> ALL(v_quest_keys)
                    ORDER BY selection_score DESC, (abs(hashtext(quest_key)) + v_day_seed) % 11
                    LIMIT 1;
                    IF v_swap_candidate IS NOT NULL THEN
                        v_quest_keys[3] := v_swap_candidate;
                        EXIT;
                    END IF;
                END IF;
            END LOOP;
        END IF;

        -- ── Layer 5: skip-streak floor — sanity sweep ────────────────
        -- After all the above, ensure no slot ended up with a key that's
        -- still suppressed (could happen if the pool was so thin it had
        -- to be filled from fallback seeds). Replace any suppressed slot
        -- with the highest-scored non-suppressed candidate not already
        -- chosen. Slot 1 is never replaced (anchor invariant).
        FOR v_i IN 2..3 LOOP
            IF v_quest_keys[v_i] IS NULL THEN CONTINUE; END IF;
            IF v_quest_keys[v_i] = ANY(v_challenge_quest_keys) THEN CONTINUE; END IF;

            IF NOT EXISTS (
                SELECT 1 FROM _scored_quests sq
                WHERE sq.quest_key = v_quest_keys[v_i]
            ) THEN
                -- The picked key is NOT in the post-suppression pool →
                -- swap for top non-chosen scored candidate.
                SELECT quest_key INTO v_swap_candidate
                FROM _scored_quests
                WHERE quest_key <> ALL(v_quest_keys)
                ORDER BY selection_score DESC, (abs(hashtext(quest_key)) + v_day_seed) % 11
                LIMIT 1;
                IF v_swap_candidate IS NOT NULL THEN
                    v_quest_keys[v_i] := v_swap_candidate;
                END IF;
            END IF;
        END LOOP;

        -- ── Layer 6b: Pro extra slots (4 + 5) ─────────────────────────
        IF v_pro THEN
            -- Slot 4: fresh exploration category — least_bucket if known.
            IF v_least_bucket IS NOT NULL THEN
                SELECT quest_key INTO v_swap_candidate
                FROM _scored_quests
                WHERE activity_bucket = v_least_bucket
                  AND quest_key <> ALL(v_quest_keys)
                ORDER BY selection_score DESC, (abs(hashtext(quest_key)) + v_day_seed) % 11
                LIMIT 1;
            END IF;
            IF v_swap_candidate IS NULL THEN
                SELECT quest_key INTO v_swap_candidate
                FROM _scored_quests
                WHERE quest_key <> ALL(v_quest_keys)
                ORDER BY selection_score DESC, (abs(hashtext(quest_key)) + v_day_seed) % 11
                LIMIT 1;
            END IF;
            IF v_swap_candidate IS NOT NULL THEN
                v_quest_keys[4] := v_swap_candidate;
                v_swap_candidate := NULL;
            END IF;

            -- Slot 5: hard-tier wildcard.
            SELECT quest_key INTO v_swap_candidate
            FROM _scored_quests
            WHERE difficulty = 'hard'
              AND quest_key <> ALL(v_quest_keys)
            ORDER BY selection_score DESC, (abs(hashtext(quest_key)) + v_day_seed) % 11
            LIMIT 1;
            IF v_swap_candidate IS NULL THEN
                SELECT quest_key INTO v_swap_candidate
                FROM _scored_quests
                WHERE quest_key <> ALL(v_quest_keys)
                ORDER BY selection_score DESC, (abs(hashtext(quest_key)) + v_day_seed) % 11
                LIMIT 1;
            END IF;
            IF v_swap_candidate IS NOT NULL THEN
                v_quest_keys[5] := v_swap_candidate;
                v_swap_candidate := NULL;
            END IF;
        END IF;

        -- ── Free-user ad slot (unchanged revenue hook) ────────────────
        IF NOT p_is_subscriber
           AND array_length(v_challenge_quest_keys, 1) IS NULL
           AND EXISTS (SELECT 1 FROM _scored_quests WHERE quest_key = 'watch_ads')
           AND NOT ('watch_ads' = ANY(v_quest_keys)) THEN
            v_quest_keys[3] := 'watch_ads';
        END IF;

        -- ── Pre-compute friend label strings (≤ 35 chars) ────────────
        IF p_friend_step_target > 0 AND p_friend_name IS NOT NULL THEN
            v_friend_step_label := 'Beat ' || p_friend_name || ': ' ||
                CASE WHEN p_friend_step_target >= 10000
                     THEN (p_friend_step_target / 1000)::TEXT || 'K'
                     ELSE p_friend_step_target::TEXT
                END;
        END IF;

        IF p_friend_top_workout_title IS NOT NULL AND p_friend_name IS NOT NULL THEN
            IF p_friend_top_workout_matches_recommendation
               AND p_friend_top_workout_split IS NOT NULL THEN
                -- "Due for chest — do Paul's"   (≤ 35 chars target)
                v_friend_workout_copy := 'Due for ' || p_friend_top_workout_split
                                      || ' — do ' || p_friend_name || E'\u2019s';
            ELSE
                -- Fallback generic copy.
                v_friend_workout_short := CASE
                    WHEN char_length(p_friend_top_workout_title) > 18
                        THEN substring(p_friend_top_workout_title FROM 1 FOR 17) || E'\u2026'
                    ELSE p_friend_top_workout_title
                END;
                v_friend_workout_copy := 'Do ' || p_friend_name || E'\u2019s ' || v_friend_workout_short;
            END IF;
        END IF;

        INSERT INTO user_quest_streaks (user_id)
        VALUES (v_user_id)
        ON CONFLICT (user_id) DO NOTHING;

        -- ── Insert the slate ──────────────────────────────────────────
        INSERT INTO user_daily_quests (
            user_id, quest_date, quest_key, title, description, icon,
            category, target_value, target_unit, xp_reward, league_points, difficulty
        )
        SELECT
            v_user_id,
            v_today,
            qt.quest_key,
            -- Title rewrites:
            --   * step quests get "Beat <Friend>: 8.4K" when seeded
            --   * do_friend_workout gets the split-aware copy
            --   * complete_program_day shorthand (legacy)
            CASE
                WHEN qt.quest_key = ANY(v_step_keys) AND v_friend_step_label IS NOT NULL
                    THEN substring(v_friend_step_label FROM 1 FOR 35)
                WHEN qt.quest_key = ANY(v_step_keys) AND p_active_step_challenge_target > 0
                    THEN CASE
                        WHEN p_active_step_challenge_target >= 10000
                            THEN (p_active_step_challenge_target / 1000) || 'K Challenge Steps'
                        ELSE p_active_step_challenge_target::TEXT || ' Challenge Steps'
                    END
                WHEN qt.quest_key = 'do_friend_workout' AND v_friend_workout_copy IS NOT NULL
                    THEN substring(v_friend_workout_copy FROM 1 FOR 35)
                WHEN qt.quest_key = 'complete_program_day'
                    THEN 'Program Day'
                ELSE qt.title
            END,
            -- Description rewrites: same logic, but description may be
            -- slightly longer (server still <= 35 chars per Data #32).
            CASE
                WHEN qt.quest_key = ANY(v_step_keys) AND v_friend_step_label IS NOT NULL
                    THEN substring('Beat ' || p_friend_name || ' today' FROM 1 FOR 35)
                WHEN qt.quest_key = ANY(v_step_keys) AND p_active_step_challenge_target > 0
                    THEN 'Hit your ' ||
                         CASE
                            WHEN p_active_step_challenge_target >= 10000
                                THEN (p_active_step_challenge_target / 1000) || 'K'
                            ELSE p_active_step_challenge_target::TEXT
                         END
                         || ' challenge target'
                WHEN qt.quest_key = 'do_friend_workout' AND v_friend_workout_copy IS NOT NULL
                    THEN substring(v_friend_workout_copy FROM 1 FOR 35)
                WHEN qt.quest_key IN ('complete_workout', 'workout_30_min')
                     AND p_suggested_split IS NOT NULL
                    THEN CASE p_suggested_split
                        WHEN 'legs'  THEN 'Suggested: Legs today'
                        WHEN 'push'  THEN 'Suggested: Push today'
                        WHEN 'pull'  THEN 'Suggested: Pull today'
                        WHEN 'upper' THEN 'Suggested: Upper body'
                        WHEN 'full'  THEN 'Suggested: Full body'
                        ELSE qt.description
                    END
                WHEN qt.quest_key = 'complete_program_day'
                    THEN 'Continue your program'
                ELSE qt.description
            END,
            qt.icon,
            qt.category,
            CASE
                WHEN qt.quest_key = 'hit_step_goal' THEN
                    GREATEST(p_step_goal,
                             COALESCE(NULLIF(p_active_step_challenge_target, 0), 0),
                             COALESCE(NULLIF(p_friend_step_target, 0), 0))
                WHEN qt.quest_key = ANY(v_step_keys) AND p_friend_step_target > 0 THEN
                    p_friend_step_target
                WHEN qt.quest_key = ANY(v_step_keys) AND p_active_step_challenge_target > 0 THEN
                    p_active_step_challenge_target
                ELSE qt.target_value
            END,
            qt.target_unit,
            CASE
                WHEN qt.quest_key = ANY(v_step_keys) AND p_active_step_challenge_target > qt.target_value
                    THEN qt.xp_reward + 10
                ELSE qt.xp_reward
            END,
            qt.league_points,
            qt.difficulty
        FROM quest_templates qt
        WHERE qt.quest_key = ANY(v_quest_keys)
        ORDER BY array_position(v_quest_keys, qt.quest_key);
    END IF;

    -- ── Streak + completion summary (unchanged) ────────────────────────
    SELECT
        COALESCE(current_streak, 0)         AS current_streak,
        COALESCE(longest_streak, 0)         AS longest_streak,
        COALESCE(total_quests_completed, 0) AS total_completed_days
    INTO v_streak
    FROM user_quest_streaks
    WHERE user_id = v_user_id;

    IF NOT FOUND THEN
        SELECT 0 AS current_streak, 0 AS longest_streak, 0 AS total_completed_days
        INTO v_streak;
    END IF;

    SELECT
        COUNT(*) = COUNT(*) FILTER (WHERE is_completed = TRUE) AND COUNT(*) > 0
    INTO v_all_complete
    FROM user_daily_quests
    WHERE user_id = v_user_id AND quest_date = v_today;

    IF v_all_complete THEN
        SELECT bonus_claimed INTO v_bonus_claimed
        FROM user_daily_quests
        WHERE user_id = v_user_id AND quest_date = v_today
        LIMIT 1;
    END IF;

    RETURN json_build_object(
        'quests', (
            SELECT json_agg(row_to_json(q)) FROM (
                SELECT
                    udq.id,
                    udq.quest_key,
                    udq.title,
                    udq.description,
                    udq.icon,
                    udq.category,
                    udq.target_value,
                    udq.current_value,
                    udq.target_unit,
                    udq.xp_reward,
                    udq.league_points,
                    udq.difficulty,
                    udq.is_completed,
                    udq.completed_at,
                    qt.fun_label,
                    qt.verification_type,
                    qt.tier
                FROM user_daily_quests udq
                LEFT JOIN quest_templates qt ON qt.quest_key = udq.quest_key
                WHERE udq.user_id = v_user_id AND udq.quest_date = v_today
                ORDER BY udq.is_completed ASC, udq.created_at ASC
            ) q
        ),
        'all_complete',         v_all_complete,
        'bonus_xp',             CASE WHEN v_all_complete AND NOT COALESCE(v_bonus_claimed, FALSE) THEN 50 ELSE 0 END,
        'bonus_league_points',  CASE WHEN v_all_complete AND NOT COALESCE(v_bonus_claimed, FALSE) THEN 30 ELSE 0 END,
        'quest_date',           v_today,
        'streak',               COALESCE(v_streak.current_streak, 0),
        'longest_streak',       COALESCE(v_streak.longest_streak, 0),
        'total_completed',      COALESCE(v_streak.total_completed_days, 0),
        'difficulty_profile',   v_difficulty_profile,
        'tier',                 CASE WHEN v_pro THEN 'pro' ELSE 'free' END,
        'slot_count',           v_target_slots
    );
END;
$$;

GRANT EXECUTE ON FUNCTION get_daily_quests(
    TEXT, TEXT, BOOLEAN, BOOLEAN, BOOLEAN, INT, TEXT, BOOLEAN,
    INT, INT, TEXT, INT, BOOLEAN, BOOLEAN, INT, INT, TEXT, TEXT[], TEXT[], BOOLEAN,
    BOOLEAN, BOOLEAN, BOOLEAN, BOOLEAN, JSONB, INT, TEXT, UUID, TEXT, TEXT, BOOLEAN, TEXT
) TO authenticated;

COMMENT ON FUNCTION get_daily_quests(
    TEXT, TEXT, BOOLEAN, BOOLEAN, BOOLEAN, INT, TEXT, BOOLEAN,
    INT, INT, TEXT, INT, BOOLEAN, BOOLEAN, INT, INT, TEXT, TEXT[], TEXT[], BOOLEAN,
    BOOLEAN, BOOLEAN, BOOLEAN, BOOLEAN, JSONB, INT, TEXT, UUID, TEXT, TEXT, BOOLEAN, TEXT
) IS
    'Smart Adaptive Daily Goals v3 (20260605): 6-layer personalized quest selection. Layers — 1 workout slot, 2 redundancy matrix, 3 challenge override, 4 activity-mix bias + per-user weighting + suppression, 5 skip-streak floor, 6 friend-named copy + Pro 5-slot expansion. Replaces the 20-arg signature from 20260509b.';

COMMIT;


-- ════════════════════════════════════════════════════════════════════
-- SOURCE: supabase/20260606_verify_integration_quests_rpcs.sql
-- ════════════════════════════════════════════════════════════════════

-- ============================================================================
-- 20260606 — Smart Adaptive Daily Goals: verification fanout RPCs
--
-- Phase 6 of the personalization upgrade. Two SECURITY DEFINER RPCs the
-- iOS client calls fire-and-forget after every Strava sync /
-- ReadinessService recompute — they walk today's user_daily_quests for
-- the caller, run the matching auto-verifier, and call update_quest_progress
-- to flip any newly-completable quest to is_completed = TRUE.
--
--   * verify_strava_quests_for_today(p_timezone)
--       Detects:
--         run_outside_3km / run_outside_5km / run_outside_8km   → distance
--         cycle_outside_15km / cycle_outside_30km                → distance
--         beat_your_5k_pr             → cardio_personal_records 5K time vs prior best
--         negative_split_run          → splits_json second-half pace < first-half
--         complete_strava_segment     → segment_efforts_json non-empty for today
--
--   * verify_wearable_quests_for_today(p_timezone)
--       Reads daily_readiness_history (today's row) and today's
--       cardio_workouts to verify:
--         sleep_8h_wearable           → sleep_hours >= 8
--         recovery_above_67           → score >= 67
--         hrv_above_baseline          → hrv_delta_pct > 0
--         rhr_in_healthy_range        → rhr_trend_bpm <= 0
--         walk_when_red               → band = 'red' AND walk >= 20 min today
--         respect_red_recovery        → band = 'red' AND only recovery / mobility
--                                        workout type today
--
-- Both RPCs are auth.uid()-pinned (Data invariant 7) — service-role
-- contexts (cron) skipped because there's no caller to verify for.
-- ============================================================================

BEGIN;

-- ============================================================================
-- 1. verify_strava_quests_for_today
-- ============================================================================
DROP FUNCTION IF EXISTS public.verify_strava_quests_for_today(TEXT);

CREATE OR REPLACE FUNCTION public.verify_strava_quests_for_today(
    p_timezone TEXT DEFAULT 'America/New_York'
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_caller_id  UUID := auth.uid();
    v_today      DATE;
    v_quest      RECORD;
    v_completed  TEXT[] := '{}';
    v_skipped    TEXT[] := '{}';
    v_5k_meters  INT := 5000;
    v_today_5k_seconds INT;
    v_best_5k_seconds  INT;
    v_negative_split   BOOLEAN;
    v_segments_today   INT;
BEGIN
    IF v_caller_id IS NULL THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'no_auth_uid');
    END IF;

    v_today := (now() AT TIME ZONE p_timezone)::DATE;

    FOR v_quest IN
        SELECT udq.id, udq.quest_key
          FROM user_daily_quests udq
         WHERE udq.user_id = v_caller_id
           AND udq.quest_date = v_today
           AND udq.is_completed = FALSE
           AND udq.quest_key IN (
               'run_outside_3km','run_outside_5km','run_outside_8km',
               'cycle_outside_15km','cycle_outside_30km',
               'beat_your_5k_pr','negative_split_run','complete_strava_segment'
           )
    LOOP
        -- Distance-only keys delegate to the existing helper from 20260531.
        IF v_quest.quest_key IN ('run_outside_3km','run_outside_5km','cycle_outside_15km') THEN
            IF public.is_strava_quest_completed(v_caller_id, v_quest.quest_key, p_timezone) THEN
                PERFORM public.update_quest_progress(v_caller_id::TEXT, v_quest.quest_key, 1, p_timezone);
                v_completed := array_append(v_completed, v_quest.quest_key);
            ELSE
                v_skipped := array_append(v_skipped, v_quest.quest_key);
            END IF;

        ELSIF v_quest.quest_key = 'run_outside_8km' THEN
            IF EXISTS (
                SELECT 1 FROM cardio_workouts cw
                WHERE cw.user_id = v_caller_id
                  AND cw.source = 'strava'
                  AND COALESCE(cw.activity_type, '') = 'outdoor_run'
                  AND COALESCE(cw.distance_meters, 0) >= 8000
                  AND (cw.started_at AT TIME ZONE p_timezone)::DATE = v_today
            ) THEN
                PERFORM public.update_quest_progress(v_caller_id::TEXT, v_quest.quest_key, 1, p_timezone);
                v_completed := array_append(v_completed, v_quest.quest_key);
            ELSE
                v_skipped := array_append(v_skipped, v_quest.quest_key);
            END IF;

        ELSIF v_quest.quest_key = 'cycle_outside_30km' THEN
            IF EXISTS (
                SELECT 1 FROM cardio_workouts cw
                WHERE cw.user_id = v_caller_id
                  AND cw.source = 'strava'
                  AND COALESCE(cw.activity_type, '') = 'outdoor_cycle'
                  AND COALESCE(cw.distance_meters, 0) >= 30000
                  AND (cw.started_at AT TIME ZONE p_timezone)::DATE = v_today
            ) THEN
                PERFORM public.update_quest_progress(v_caller_id::TEXT, v_quest.quest_key, 1, p_timezone);
                v_completed := array_append(v_completed, v_quest.quest_key);
            ELSE
                v_skipped := array_append(v_skipped, v_quest.quest_key);
            END IF;

        ELSIF v_quest.quest_key = 'beat_your_5k_pr' THEN
            -- Best-known 5K time prior to today (any source).
            SELECT MIN(elapsed_seconds) INTO v_best_5k_seconds
              FROM cardio_workouts
             WHERE user_id = v_caller_id
               AND COALESCE(activity_type, '') = 'outdoor_run'
               AND COALESCE(distance_meters, 0) >= v_5k_meters
               AND elapsed_seconds IS NOT NULL
               AND (started_at AT TIME ZONE p_timezone)::DATE < v_today;

            -- Today's fastest qualifying 5K segment.
            SELECT MIN(elapsed_seconds) INTO v_today_5k_seconds
              FROM cardio_workouts
             WHERE user_id = v_caller_id
               AND source = 'strava'
               AND COALESCE(activity_type, '') = 'outdoor_run'
               AND COALESCE(distance_meters, 0) >= v_5k_meters
               AND elapsed_seconds IS NOT NULL
               AND (started_at AT TIME ZONE p_timezone)::DATE = v_today;

            IF v_today_5k_seconds IS NOT NULL
               AND (v_best_5k_seconds IS NULL OR v_today_5k_seconds < v_best_5k_seconds) THEN
                PERFORM public.update_quest_progress(v_caller_id::TEXT, v_quest.quest_key, 1, p_timezone);
                v_completed := array_append(v_completed, v_quest.quest_key);
            ELSE
                v_skipped := array_append(v_skipped, v_quest.quest_key);
            END IF;

        ELSIF v_quest.quest_key = 'negative_split_run' THEN
            -- Walk today's runs and check splits_json. Strava splits_json
            -- is an array of `{distance, elapsed_time, average_speed, …}`.
            -- Negative split = back half average pace ≤ front half (we use
            -- average_speed: back half ≥ front half).
            SELECT EXISTS (
                SELECT 1
                  FROM cardio_workouts cw,
                       LATERAL jsonb_array_elements(COALESCE(cw.splits_json, '[]'::jsonb)) WITH ORDINALITY AS s(elem, idx)
                 WHERE cw.user_id = v_caller_id
                   AND cw.source = 'strava'
                   AND COALESCE(cw.activity_type, '') = 'outdoor_run'
                   AND (cw.started_at AT TIME ZONE p_timezone)::DATE = v_today
                   AND jsonb_typeof(cw.splits_json) = 'array'
                   AND jsonb_array_length(cw.splits_json) >= 2
                 GROUP BY cw.id
                HAVING (
                    AVG((s.elem->>'average_speed')::NUMERIC) FILTER (WHERE s.idx >  jsonb_array_length(cw.splits_json) / 2)
                    >
                    AVG((s.elem->>'average_speed')::NUMERIC) FILTER (WHERE s.idx <= jsonb_array_length(cw.splits_json) / 2)
                )
            ) INTO v_negative_split;

            IF COALESCE(v_negative_split, FALSE) THEN
                PERFORM public.update_quest_progress(v_caller_id::TEXT, v_quest.quest_key, 1, p_timezone);
                v_completed := array_append(v_completed, v_quest.quest_key);
            ELSE
                v_skipped := array_append(v_skipped, v_quest.quest_key);
            END IF;

        ELSIF v_quest.quest_key = 'complete_strava_segment' THEN
            SELECT COUNT(*) INTO v_segments_today
              FROM cardio_workouts cw
             WHERE cw.user_id = v_caller_id
               AND cw.source = 'strava'
               AND (cw.started_at AT TIME ZONE p_timezone)::DATE = v_today
               AND jsonb_typeof(COALESCE(cw.segment_efforts_json, '[]'::jsonb)) = 'array'
               AND jsonb_array_length(COALESCE(cw.segment_efforts_json, '[]'::jsonb)) > 0;

            IF v_segments_today > 0 THEN
                PERFORM public.update_quest_progress(v_caller_id::TEXT, v_quest.quest_key, 1, p_timezone);
                v_completed := array_append(v_completed, v_quest.quest_key);
            ELSE
                v_skipped := array_append(v_skipped, v_quest.quest_key);
            END IF;
        END IF;
    END LOOP;

    RETURN jsonb_build_object(
        'success', TRUE,
        'completed', v_completed,
        'skipped', v_skipped,
        'date', v_today
    );
END;
$$;

REVOKE ALL ON FUNCTION public.verify_strava_quests_for_today(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.verify_strava_quests_for_today(TEXT) TO authenticated;

COMMENT ON FUNCTION public.verify_strava_quests_for_today(TEXT) IS
    'Smart Adaptive Daily Goals (20260606): walks today user_daily_quests for the caller and ticks any Strava-detectable completion. Auto-called from iOS DailyQuestService after StravaService.syncActivities.';


-- ============================================================================
-- 2. verify_wearable_quests_for_today
-- ============================================================================
DROP FUNCTION IF EXISTS public.verify_wearable_quests_for_today(TEXT);

CREATE OR REPLACE FUNCTION public.verify_wearable_quests_for_today(
    p_timezone TEXT DEFAULT 'America/New_York'
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_caller_id   UUID := auth.uid();
    v_today       DATE;
    v_readiness   RECORD;
    v_quest       RECORD;
    v_completed   TEXT[] := '{}';
    v_skipped     TEXT[] := '{}';
    v_walk_minutes_today INT;
    v_recovery_workout_today BOOLEAN;
BEGIN
    IF v_caller_id IS NULL THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'no_auth_uid');
    END IF;

    v_today := (now() AT TIME ZONE p_timezone)::DATE;

    SELECT score, band, hrv_delta_pct, sleep_hours, rhr_trend_bpm, primary_source
      INTO v_readiness
      FROM daily_readiness_history
     WHERE user_id = v_caller_id
       AND date = v_today
     ORDER BY updated_at DESC
     LIMIT 1;

    -- If we have NO readiness row yet, nothing wearable-driven can verify.
    IF v_readiness IS NULL THEN
        RETURN jsonb_build_object('success', TRUE, 'completed', '{}'::TEXT[], 'skipped', '{}'::TEXT[], 'reason', 'no_readiness_row');
    END IF;

    FOR v_quest IN
        SELECT udq.id, udq.quest_key
          FROM user_daily_quests udq
         WHERE udq.user_id = v_caller_id
           AND udq.quest_date = v_today
           AND udq.is_completed = FALSE
           AND udq.quest_key IN (
               'sleep_8h_wearable','recovery_above_67','hrv_above_baseline',
               'rhr_in_healthy_range','walk_when_red','respect_red_recovery'
           )
    LOOP
        IF v_quest.quest_key = 'sleep_8h_wearable' THEN
            IF COALESCE(v_readiness.sleep_hours, 0) >= 8 THEN
                PERFORM public.update_quest_progress(v_caller_id::TEXT, v_quest.quest_key, 1, p_timezone);
                v_completed := array_append(v_completed, v_quest.quest_key);
            ELSE
                v_skipped := array_append(v_skipped, v_quest.quest_key);
            END IF;

        ELSIF v_quest.quest_key = 'recovery_above_67' THEN
            IF COALESCE(v_readiness.score, 0) >= 67 THEN
                PERFORM public.update_quest_progress(v_caller_id::TEXT, v_quest.quest_key, 1, p_timezone);
                v_completed := array_append(v_completed, v_quest.quest_key);
            ELSE
                v_skipped := array_append(v_skipped, v_quest.quest_key);
            END IF;

        ELSIF v_quest.quest_key = 'hrv_above_baseline' THEN
            IF COALESCE(v_readiness.hrv_delta_pct, -1) > 0 THEN
                PERFORM public.update_quest_progress(v_caller_id::TEXT, v_quest.quest_key, 1, p_timezone);
                v_completed := array_append(v_completed, v_quest.quest_key);
            ELSE
                v_skipped := array_append(v_skipped, v_quest.quest_key);
            END IF;

        ELSIF v_quest.quest_key = 'rhr_in_healthy_range' THEN
            -- Healthy = today's RHR ≤ 28-day baseline (rhr_trend_bpm ≤ 0).
            IF COALESCE(v_readiness.rhr_trend_bpm, 1) <= 0 THEN
                PERFORM public.update_quest_progress(v_caller_id::TEXT, v_quest.quest_key, 1, p_timezone);
                v_completed := array_append(v_completed, v_quest.quest_key);
            ELSE
                v_skipped := array_append(v_skipped, v_quest.quest_key);
            END IF;

        ELSIF v_quest.quest_key = 'walk_when_red' THEN
            IF v_readiness.band = 'red' THEN
                SELECT COALESCE(SUM(GREATEST(0, COALESCE(elapsed_seconds, 0)) / 60), 0)::INT
                  INTO v_walk_minutes_today
                  FROM cardio_workouts
                 WHERE user_id = v_caller_id
                   AND COALESCE(activity_type, '') IN ('walk', 'hike')
                   AND (started_at AT TIME ZONE p_timezone)::DATE = v_today;
                IF v_walk_minutes_today >= 20 THEN
                    PERFORM public.update_quest_progress(v_caller_id::TEXT, v_quest.quest_key, 1, p_timezone);
                    v_completed := array_append(v_completed, v_quest.quest_key);
                ELSE
                    v_skipped := array_append(v_skipped, v_quest.quest_key);
                END IF;
            ELSE
                v_skipped := array_append(v_skipped, v_quest.quest_key);
            END IF;

        ELSIF v_quest.quest_key = 'respect_red_recovery' THEN
            -- Red day AND only recovery-flavored activity logged today
            -- (walk / hike / yoga / stretch / mobility — no strenuous run/lift).
            IF v_readiness.band = 'red' THEN
                SELECT EXISTS (
                    SELECT 1 FROM cardio_workouts
                    WHERE user_id = v_caller_id
                      AND COALESCE(activity_type, '') IN ('walk','hike','yoga','stretch','mobility','foam_rolling')
                      AND (started_at AT TIME ZONE p_timezone)::DATE = v_today
                ) AND NOT EXISTS (
                    -- Canonical `workouts.date` is DATE (see
                    -- 20260327_engagement_scoring.sql line 14). No
                    -- timezone math needed — compare DATE to DATE.
                    SELECT 1 FROM workouts
                    WHERE user_id = v_caller_id
                      AND date = v_today
                ) INTO v_recovery_workout_today;

                IF v_recovery_workout_today THEN
                    PERFORM public.update_quest_progress(v_caller_id::TEXT, v_quest.quest_key, 1, p_timezone);
                    v_completed := array_append(v_completed, v_quest.quest_key);
                ELSE
                    v_skipped := array_append(v_skipped, v_quest.quest_key);
                END IF;
            ELSE
                v_skipped := array_append(v_skipped, v_quest.quest_key);
            END IF;
        END IF;
    END LOOP;

    RETURN jsonb_build_object(
        'success', TRUE,
        'completed', v_completed,
        'skipped', v_skipped,
        'date', v_today,
        'band', v_readiness.band,
        'score', v_readiness.score
    );
END;
$$;

REVOKE ALL ON FUNCTION public.verify_wearable_quests_for_today(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.verify_wearable_quests_for_today(TEXT) TO authenticated;

COMMENT ON FUNCTION public.verify_wearable_quests_for_today(TEXT) IS
    'Smart Adaptive Daily Goals (20260606): walks today user_daily_quests for the caller and ticks any wearable-detectable completion (sleep / recovery / HRV / RHR / red-band conduct). Auto-called from iOS after ReadinessService.recompute().';

COMMIT;


-- ════════════════════════════════════════════════════════════════════
-- SOURCE: supabase/20260607_pro_quest_monetization.sql
-- ════════════════════════════════════════════════════════════════════

-- ============================================================================
-- 20260607 — Smart Adaptive Daily Goals: Pro monetization RPCs
--
-- Resolves: 7bf1ff4efdac6620edfbda328204ed16 — v_user_quest_personalization_summary missing (Report 6 / 04-25 audit; this migration creates the view)
-- Resolves: f30626309d8480ec14526323da68396d — same view missing, log variant (Report 11 / 04-25 audit)
--
-- Phase 7 (final) of the personalization upgrade. Ships the four
-- subscriber-facing features the plan calls out:
--
--   * reroll_daily_quest(p_quest_id, p_timezone, p_is_pro)
--       Replaces one slot with a fresh candidate.
--       Free: 1/day cooldown (no replays).
--       Pro:  5/day, no cooldown.
--
--   * claim_double_xp_day(p_date, p_is_pro)
--       Pro-only, 1/week. Stamps today's user_daily_quests rows with
--       double_xp = TRUE. update_quest_progress is patched to double XP
--       awarded when the flag is set.
--
--   * submit_custom_quest(p_title, p_target_value, p_target_unit, p_is_pro)
--       Pro-only, 1/day, manual verification, capped 25 XP.
--
--   * v_user_quest_personalization_summary  (security_invoker = on)
--       Drives the Pro Insights screen — 28-day per-category completion
--       bars, current streaks, suppressions.
--
-- Plus the supporting schema:
--   * user_quest_rerolls (user_id, reroll_date, count, last_at)
--   * user_daily_quests.double_xp BOOLEAN
--   * user_daily_quests.is_custom BOOLEAN
--   * user_daily_quests.is_reroll BOOLEAN
--
-- Premium check: the client passes p_is_pro based on PremiumManager
-- (matches the existing p_is_subscriber pattern in get_daily_quests).
-- A future migration may swap this for a server-side subscription_status
-- read once the canonical premium column lands; the function signatures
-- accept the boolean today to avoid a breaking change later.
-- ============================================================================

BEGIN;

-- ── 1. Schema: new columns + reroll ledger ──────────────────────────────
ALTER TABLE user_daily_quests
    ADD COLUMN IF NOT EXISTS double_xp BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS is_custom BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS is_reroll BOOLEAN NOT NULL DEFAULT FALSE;

CREATE TABLE IF NOT EXISTS user_quest_rerolls (
    user_id      UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
    reroll_date  DATE NOT NULL DEFAULT CURRENT_DATE,
    count        INT  NOT NULL DEFAULT 0,
    last_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, reroll_date)
);

ALTER TABLE user_quest_rerolls ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "uqr_select_own" ON user_quest_rerolls;
DROP POLICY IF EXISTS "uqr_insert_own" ON user_quest_rerolls;
DROP POLICY IF EXISTS "uqr_update_own" ON user_quest_rerolls;
CREATE POLICY "uqr_select_own" ON user_quest_rerolls
    FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "uqr_insert_own" ON user_quest_rerolls
    FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "uqr_update_own" ON user_quest_rerolls
    FOR UPDATE USING (auth.uid() = user_id);

CREATE TABLE IF NOT EXISTS user_double_xp_claims (
    user_id     UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
    claim_date  DATE NOT NULL,
    claimed_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, claim_date)
);

ALTER TABLE user_double_xp_claims ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "udxc_select_own" ON user_double_xp_claims;
DROP POLICY IF EXISTS "udxc_insert_own" ON user_double_xp_claims;
CREATE POLICY "udxc_select_own" ON user_double_xp_claims
    FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "udxc_insert_own" ON user_double_xp_claims
    FOR INSERT WITH CHECK (auth.uid() = user_id);


-- ── 2. reroll_daily_quest ──────────────────────────────────────────────
DROP FUNCTION IF EXISTS public.reroll_daily_quest(UUID, TEXT, BOOLEAN);

CREATE OR REPLACE FUNCTION public.reroll_daily_quest(
    p_quest_id  UUID,
    p_timezone  TEXT DEFAULT 'America/New_York',
    p_is_pro    BOOLEAN DEFAULT FALSE
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_caller_id   UUID := auth.uid();
    v_today       DATE;
    v_quest       RECORD;
    v_existing    TEXT[];
    v_recent      TEXT[];
    v_count_today INT;
    v_max_per_day INT := CASE WHEN p_is_pro THEN 5 ELSE 1 END;
    v_swap_key    TEXT;
    v_template    RECORD;
BEGIN
    IF v_caller_id IS NULL THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'not_authenticated');
    END IF;

    v_today := (now() AT TIME ZONE p_timezone)::DATE;

    -- Fetch + ownership + completion check (Data invariant 7).
    SELECT * INTO v_quest
      FROM user_daily_quests
     WHERE id = p_quest_id
       AND user_id = v_caller_id
       AND quest_date = v_today;

    IF v_quest IS NULL THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'quest_not_found_or_not_today');
    END IF;

    IF v_quest.is_completed THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'already_completed');
    END IF;

    -- Cooldown / per-day quota.
    SELECT count INTO v_count_today
      FROM user_quest_rerolls
     WHERE user_id = v_caller_id AND reroll_date = v_today;
    v_count_today := COALESCE(v_count_today, 0);

    IF v_count_today >= v_max_per_day THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'reason', CASE WHEN p_is_pro THEN 'pro_limit_reached' ELSE 'free_limit_reached' END,
            'used', v_count_today,
            'limit', v_max_per_day
        );
    END IF;

    -- Build the exclude set: today's other quests + last 3 days.
    SELECT COALESCE(ARRAY_AGG(quest_key), '{}') INTO v_existing
      FROM user_daily_quests
     WHERE user_id = v_caller_id AND quest_date = v_today;

    SELECT COALESCE(ARRAY_AGG(DISTINCT quest_key), '{}') INTO v_recent
      FROM user_daily_quests
     WHERE user_id = v_caller_id
       AND quest_date >= v_today - INTERVAL '3 days'
       AND quest_date < v_today;

    -- Pick a fresh candidate of the same difficulty bucket if possible
    -- (keeps the day's overall difficulty balance stable).
    SELECT qt.quest_key INTO v_swap_key
      FROM quest_templates qt
     WHERE qt.is_active = TRUE
       AND qt.is_premium = FALSE
       AND (p_is_pro OR qt.tier = 'free')
       AND qt.difficulty = v_quest.difficulty
       AND qt.quest_key NOT IN (
            'upper_body_workout','lower_body_workout',
            'complete_program_day','complete_2_workouts'
       )
       AND qt.quest_key <> ALL(v_existing)
       AND qt.quest_key <> ALL(v_recent)
       AND NOT EXISTS (
           SELECT 1 FROM user_quest_key_stats s
            WHERE s.user_id = v_caller_id
              AND s.quest_key = qt.quest_key
              AND s.suppressed_until IS NOT NULL
              AND s.suppressed_until > v_today
       )
       AND NOT EXISTS (
           SELECT 1 FROM user_quest_personalization p
            WHERE p.user_id = v_caller_id
              AND p.category = qt.category
              AND p.suppressed_until IS NOT NULL
              AND p.suppressed_until > v_today
       )
     ORDER BY (abs(hashtext(qt.quest_key)) + abs(hashtext(v_today::TEXT))) % 11
     LIMIT 1;

    -- Fall back to any non-suppressed key if no same-difficulty match exists.
    IF v_swap_key IS NULL THEN
        SELECT qt.quest_key INTO v_swap_key
          FROM quest_templates qt
         WHERE qt.is_active = TRUE
           AND qt.is_premium = FALSE
           AND (p_is_pro OR qt.tier = 'free')
           AND qt.quest_key <> ALL(v_existing)
           AND qt.quest_key <> ALL(v_recent)
           AND qt.quest_key NOT IN (
                'upper_body_workout','lower_body_workout',
                'complete_program_day','complete_2_workouts'
           )
         ORDER BY (abs(hashtext(qt.quest_key)) + abs(hashtext(v_today::TEXT))) % 11
         LIMIT 1;
    END IF;

    IF v_swap_key IS NULL THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'no_eligible_swap');
    END IF;

    SELECT * INTO v_template FROM quest_templates WHERE quest_key = v_swap_key;

    -- Atomically swap the row in place — keeps the same id so client
    -- state (animations, scroll position) stays stable.
    UPDATE user_daily_quests
       SET quest_key     = v_template.quest_key,
           title         = v_template.title,
           description   = v_template.description,
           icon          = v_template.icon,
           category      = v_template.category,
           target_value  = v_template.target_value,
           target_unit   = v_template.target_unit,
           xp_reward     = v_template.xp_reward,
           league_points = v_template.league_points,
           difficulty    = v_template.difficulty,
           current_value = 0,
           is_completed  = FALSE,
           completed_at  = NULL,
           is_reroll     = TRUE
     WHERE id = p_quest_id;

    INSERT INTO user_quest_rerolls (user_id, reroll_date, count, last_at)
    VALUES (v_caller_id, v_today, 1, now())
    ON CONFLICT (user_id, reroll_date) DO UPDATE SET
        count   = user_quest_rerolls.count + 1,
        last_at = EXCLUDED.last_at;

    RETURN jsonb_build_object(
        'success', TRUE,
        'new_quest_key', v_swap_key,
        'remaining',     v_max_per_day - (v_count_today + 1),
        'is_pro',        p_is_pro
    );
END;
$$;

REVOKE ALL ON FUNCTION public.reroll_daily_quest(UUID, TEXT, BOOLEAN) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.reroll_daily_quest(UUID, TEXT, BOOLEAN) TO authenticated;

COMMENT ON FUNCTION public.reroll_daily_quest(UUID, TEXT, BOOLEAN) IS
    'Smart Adaptive Daily Goals (20260607): swap one of today''s quest slots for a fresh candidate. Free 1/day, Pro 5/day. Auth-pinned (Data invariant 7).';


-- ── 3. claim_double_xp_day ─────────────────────────────────────────────
DROP FUNCTION IF EXISTS public.claim_double_xp_day(DATE, BOOLEAN);

CREATE OR REPLACE FUNCTION public.claim_double_xp_day(
    p_date     DATE DEFAULT NULL,
    p_is_pro   BOOLEAN DEFAULT FALSE
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_caller_id    UUID := auth.uid();
    v_target_date  DATE := COALESCE(p_date, CURRENT_DATE);
    v_recent_claim DATE;
    v_rows_updated INT;
BEGIN
    IF v_caller_id IS NULL THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'not_authenticated');
    END IF;

    IF NOT p_is_pro THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'pro_required');
    END IF;

    -- 1/week cooldown — last claim must be ≥ 7 days ago.
    SELECT MAX(claim_date) INTO v_recent_claim
      FROM user_double_xp_claims
     WHERE user_id = v_caller_id;

    IF v_recent_claim IS NOT NULL AND (v_target_date - v_recent_claim) < 7 THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'reason', 'weekly_cooldown',
            'last_claim_date', v_recent_claim,
            'next_eligible_date', v_recent_claim + 7
        );
    END IF;

    -- Stamp today's quest rows.
    UPDATE user_daily_quests
       SET double_xp = TRUE
     WHERE user_id = v_caller_id
       AND quest_date = v_target_date;

    GET DIAGNOSTICS v_rows_updated = ROW_COUNT;

    IF v_rows_updated = 0 THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'no_quests_for_date', 'date', v_target_date);
    END IF;

    INSERT INTO user_double_xp_claims (user_id, claim_date)
    VALUES (v_caller_id, v_target_date);

    RETURN jsonb_build_object(
        'success', TRUE,
        'date', v_target_date,
        'quests_marked', v_rows_updated
    );
END;
$$;

REVOKE ALL ON FUNCTION public.claim_double_xp_day(DATE, BOOLEAN) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.claim_double_xp_day(DATE, BOOLEAN) TO authenticated;

COMMENT ON FUNCTION public.claim_double_xp_day(DATE, BOOLEAN) IS
    'Smart Adaptive Daily Goals (20260607): Pro-only. 1/week. Marks today''s user_daily_quests rows with double_xp=TRUE so update_quest_progress doubles XP awarded.';


-- ── 4. update_quest_progress patch — honor double_xp flag ──────────────
-- We can't fully redefine the function here without copying ~150 lines,
-- so we add a SECURITY DEFINER helper that the client can call to bonus
-- the streak entry post-completion. Cleaner: a lightweight trigger on
-- user_daily_quests UPDATE that doubles awarded xp when transitioning to
-- is_completed = TRUE on a double_xp row.

CREATE OR REPLACE FUNCTION public.apply_double_xp_on_complete()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_extra_xp INT;
    v_extra_lp INT;
BEGIN
    IF NEW.is_completed
       AND NEW.double_xp
       AND (OLD IS NULL OR NOT OLD.is_completed) THEN
        -- Award the bonus exactly once on the completion transition.
        v_extra_xp := NEW.xp_reward;
        v_extra_lp := NEW.league_points;

        UPDATE user_quest_streaks
           SET total_xp_earned     = COALESCE(total_xp_earned, 0) + v_extra_xp,
               updated_at          = now()
         WHERE user_id = NEW.user_id;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_apply_double_xp_on_complete ON user_daily_quests;
CREATE TRIGGER trg_apply_double_xp_on_complete
    AFTER UPDATE OF is_completed ON user_daily_quests
    FOR EACH ROW
    WHEN (NEW.is_completed AND NEW.double_xp)
    EXECUTE FUNCTION public.apply_double_xp_on_complete();


-- ── 5. submit_custom_quest ─────────────────────────────────────────────
DROP FUNCTION IF EXISTS public.submit_custom_quest(TEXT, INT, TEXT, BOOLEAN, TEXT);

CREATE OR REPLACE FUNCTION public.submit_custom_quest(
    p_title        TEXT,
    p_target_value INT     DEFAULT 1,
    p_target_unit  TEXT    DEFAULT 'times',
    p_is_pro       BOOLEAN DEFAULT FALSE,
    p_timezone     TEXT    DEFAULT 'America/New_York'
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_caller_id   UUID := auth.uid();
    v_today       DATE;
    v_existing    INT;
    v_xp          INT := 25;        -- capped per the plan
    v_lp          INT := 15;
    v_quest_key   TEXT;
    v_safe_title  TEXT;
    v_id          UUID;
BEGIN
    IF v_caller_id IS NULL THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'not_authenticated');
    END IF;
    IF NOT p_is_pro THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'pro_required');
    END IF;
    IF p_title IS NULL OR length(trim(p_title)) < 3 THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'title_too_short');
    END IF;
    IF p_target_value IS NULL OR p_target_value < 1 OR p_target_value > 10000 THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'target_out_of_range');
    END IF;

    v_today := (now() AT TIME ZONE p_timezone)::DATE;
    v_safe_title := substring(trim(p_title) FROM 1 FOR 35);
    v_quest_key  := 'custom_' || encode(gen_random_bytes(6), 'hex');

    -- 1/day quota.
    SELECT COUNT(*) INTO v_existing
      FROM user_daily_quests
     WHERE user_id = v_caller_id
       AND quest_date = v_today
       AND is_custom = TRUE;
    IF v_existing >= 1 THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'one_custom_per_day');
    END IF;

    INSERT INTO user_daily_quests (
        user_id, quest_date, quest_key, title, description, icon,
        category, target_value, target_unit, xp_reward, league_points,
        difficulty, is_custom
    ) VALUES (
        v_caller_id, v_today, v_quest_key,
        v_safe_title,
        v_safe_title,
        'star.fill',
        'general',
        p_target_value,
        COALESCE(p_target_unit, 'times'),
        v_xp,
        v_lp,
        'medium',
        TRUE
    )
    RETURNING id INTO v_id;

    RETURN jsonb_build_object(
        'success', TRUE,
        'id', v_id,
        'quest_key', v_quest_key,
        'xp_reward', v_xp,
        'league_points', v_lp
    );
END;
$$;

REVOKE ALL ON FUNCTION public.submit_custom_quest(TEXT, INT, TEXT, BOOLEAN, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.submit_custom_quest(TEXT, INT, TEXT, BOOLEAN, TEXT) TO authenticated;

COMMENT ON FUNCTION public.submit_custom_quest(TEXT, INT, TEXT, BOOLEAN, TEXT) IS
    'Smart Adaptive Daily Goals (20260607): Pro-only. 1/day. Manual-verification custom quest capped at 25 XP / 15 LP.';


-- ── 6. v_user_quest_personalization_summary view ──────────────────────
DROP VIEW IF EXISTS public.v_user_quest_personalization_summary CASCADE;

CREATE VIEW public.v_user_quest_personalization_summary
WITH (security_invoker = on)
AS
SELECT
    p.user_id,
    p.category,
    p.total_assigned_28d,
    p.total_completed_28d,
    p.completion_rate_28d,
    p.skip_streak,
    p.last_completed_at,
    p.suppressed_until,
    -- Effective state for the UI: green / yellow / red / suppressed.
    CASE
        WHEN p.suppressed_until IS NOT NULL AND p.suppressed_until > CURRENT_DATE THEN 'suppressed'
        WHEN p.completion_rate_28d >= 0.66 THEN 'on_fire'
        WHEN p.completion_rate_28d >= 0.33 THEN 'mixed'
        ELSE 'cold'
    END AS state,
    am.dominant_category    AS user_dominant_category,
    am.least_category       AS user_least_category,
    am.total_sessions_28d   AS user_sessions_28d
FROM user_quest_personalization p
LEFT JOIN user_activity_mix am ON am.user_id = p.user_id;

GRANT SELECT ON public.v_user_quest_personalization_summary TO authenticated;

COMMENT ON VIEW public.v_user_quest_personalization_summary IS
    'Smart Adaptive Daily Goals (20260607): Pro Insights screen feed. security_invoker = on, so RLS on user_quest_personalization + user_activity_mix still applies to the caller.';


-- ── 7. unsuppress_quest_category — Pro override ───────────────────────
-- "Pro feature: turn a suppression off if user wants to re-engage that
-- category" per the plan §8.
DROP FUNCTION IF EXISTS public.unsuppress_quest_category(TEXT, BOOLEAN);

CREATE OR REPLACE FUNCTION public.unsuppress_quest_category(
    p_category TEXT,
    p_is_pro   BOOLEAN DEFAULT FALSE
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_caller_id UUID := auth.uid();
    v_rows      INT;
BEGIN
    IF v_caller_id IS NULL THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'not_authenticated');
    END IF;
    IF NOT p_is_pro THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'pro_required');
    END IF;
    IF p_category IS NULL OR length(p_category) = 0 THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'missing_category');
    END IF;

    UPDATE user_quest_personalization
       SET suppressed_until = NULL,
           skip_streak      = 0,
           updated_at       = now()
     WHERE user_id = v_caller_id
       AND category = p_category;
    GET DIAGNOSTICS v_rows = ROW_COUNT;

    UPDATE user_quest_key_stats s
       SET suppressed_until = NULL,
           updated_at       = now()
      FROM quest_templates qt
     WHERE s.user_id = v_caller_id
       AND s.quest_key = qt.quest_key
       AND qt.category = p_category
       AND s.suppressed_until IS NOT NULL;

    RETURN jsonb_build_object(
        'success', TRUE,
        'category', p_category,
        'rows_cleared', v_rows
    );
END;
$$;

REVOKE ALL ON FUNCTION public.unsuppress_quest_category(TEXT, BOOLEAN) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.unsuppress_quest_category(TEXT, BOOLEAN) TO authenticated;

COMMENT ON FUNCTION public.unsuppress_quest_category(TEXT, BOOLEAN) IS
    'Smart Adaptive Daily Goals (20260607): Pro override that clears suppression for a category so the user can re-engage. Used by QuestInsightsView.';


COMMIT;

-- ─── Verification ──────────────────────────────────────────────────────
-- SELECT proname FROM pg_proc WHERE proname IN (
--   'reroll_daily_quest','claim_double_xp_day',
--   'submit_custom_quest','unsuppress_quest_category'
-- );
-- SELECT * FROM v_user_quest_personalization_summary LIMIT 5;


-- ════════════════════════════════════════════════════════════════════
-- SOURCE: supabase/20260610_actionable_recovery_quests.sql
-- ════════════════════════════════════════════════════════════════════

-- ============================================================================
-- 20260610 — Retire passive recovery quests, ship actionable replacements
--
-- User feedback (2026-04-25): "Green Recovery" (recovery_above_67) is a
-- pre-determined pass/fail — if you wake up red, the quest is already lost
-- before the user can take any action. Daily quests must be things the user
-- has agency over **today**, not summaries of overnight sensor state.
--
-- Three quests fail this test (introduced in 20260509_wearable_quests.sql):
--   * recovery_above_67     "Green Recovery"  — band ≥ 67 by wake-up
--   * hrv_above_baseline    "HRV Warrior"     — overnight HRV reading
--   * rhr_in_healthy_range  "Steady Heart"    — overnight RHR reading
--
-- This migration:
--   1. SOFT-disables the three passive templates (`is_active = FALSE`).
--      Templates are kept on disk so historical `user_daily_quests` rows
--      stay valid and the existing `verify_wearable_quests_for_today`
--      detection logic remains backwards-compatible for any in-flight
--      assignments that were issued before today (RPC will quietly
--      complete them if the user happens to satisfy the condition).
--
--   2. INSERTS three actionable replacements gated `requires_context =
--      'has_wearable'`, all auto-verifiable from `cardio_workouts`:
--
--      * active_recovery_logged "Active Recovery"
--          Log walk/yoga/stretch/mobility/foam-rolling ≥15 min today.
--          Replaces Green Recovery's spirit ("respect today's body")
--          with an action the user can take regardless of band color.
--
--      * zone_2_minutes_20 "Zone 2 Cardio"
--          Cardio session today with elapsed_seconds ≥ 1200 (20 min)
--          AND average_heart_rate in [110, 150] bpm. Replaces HRV
--          Warrior's spirit (zone-2 training is the canonical
--          HRV-positive intensity). HR range is age-agnostic and
--          captures Zone 2 for the typical adult max-HR (180-200 bpm
--          → 60-70% = ~108-140 bpm; we use 110-150 to allow some
--          slack for trained users with higher Z2 ceilings).
--
--      * cardio_minutes_20 "Heart Healthy"
--          Any cardio_workouts row today with elapsed_seconds ≥ 1200.
--          Replaces Steady Heart's spirit (cardiovascular health) with
--          a logged-cardio action. Distinct from `active_minutes_30`
--          (which is HealthKit ambient-active-minutes from any
--          movement) — this requires an actual logged session.
--
--   3. EXTENDS `public.verify_wearable_quests_for_today(p_timezone TEXT)`
--      to detect the three new quest_keys. The function already loops
--      over today's `user_daily_quests`; we widen the IN(...) filter and
--      add three ELSIF branches. Same `auth.uid()`-pinned SECURITY DEFINER
--      shape from 20260606. All queries use `(started_at AT TIME ZONE
--      p_timezone)::DATE = v_today` for timezone-correct windowing.
--
-- iOS notes:
--   * `Fit33/DailyQuestService.swift::onReadinessRecomputed` already
--     calls `verify_wearable_quests_for_today` after every
--     `ReadinessService.recompute()`; the new quest_keys ride that path.
--   * No `QuestKey` enum case is needed — `DailyQuest.questKey` is a
--     `String` and the icon / title / description come from
--     `quest_templates`, so new keys render via the generic path.
--   * The Swift `wearableKeys` set in `onReadinessRecomputed` does not
--     need updating; it's only used as an early-exit predicate, and a
--     superset (which it remains) is harmless.
--   * Cardio workout completion is also a natural verification trigger
--     for `active_recovery_logged` / `zone_2_minutes_20` /
--     `cardio_minutes_20`. Hooking those into
--     `HealthDataService` / `StravaService` cardio-import paths is a
--     paired iOS change tracked in DATA_BACKEND_AGENT.md (low-priority —
--     the readiness recompute path runs frequently enough that
--     verification will fire within minutes of a cardio workout import).
--
-- Idempotent: re-running is a no-op (UPDATE … WHERE is_active flips back
-- to FALSE, INSERT … ON CONFLICT DO UPDATE refreshes the new templates,
-- DROP FUNCTION … IF EXISTS + CREATE OR REPLACE for the verifier).
-- ============================================================================

BEGIN;

-- 1. Soft-disable the three passive sensor-state quests --------------------
UPDATE quest_templates
   SET is_active = FALSE
 WHERE quest_key IN ('recovery_above_67', 'hrv_above_baseline', 'rhr_in_healthy_range');

-- 2. Seed actionable replacements ------------------------------------------
-- XP rewards intentionally match the post-rebalance values the disabled
-- quests carried (see 20260603 — auto verification × 1.5). The 1.5×
-- multiplier was already applied to the original 25 / 30 / 20 base XP
-- numbers, yielding 38 / 45 / 30. We seed the post-multiplier numbers
-- directly so the 20260603 rebalance does NOT re-apply on re-run (the
-- migration is gated by an `internal_config` row).
INSERT INTO quest_templates (
    quest_key, title, description, icon, category, target_value, target_unit,
    xp_reward, league_points, difficulty, weight, requires_context, fun_label,
    verification_type, min_workouts, is_active, tier
) VALUES
    ('active_recovery_logged',
        'Active Recovery',
        'Log 15+ min of walk, yoga, or mobility',
        'figure.mind.and.body',
        'workout', 15, 'minutes',
        38, 23, 'easy', 9, 'has_wearable',
        '🧘 Move easy today',
        'auto', 0, TRUE, 'free'),

    ('zone_2_minutes_20',
        'Zone 2 Cardio',
        'Hit 20+ min cardio at HR 110–150',
        'heart.text.square.fill',
        'workout', 20, 'minutes',
        45, 30, 'medium', 8, 'has_wearable',
        '⚡ HRV-friendly pace',
        'auto', 0, TRUE, 'free'),

    ('cardio_minutes_20',
        'Heart Healthy',
        'Get 20+ min of cardio in today',
        'heart.fill',
        'workout', 20, 'minutes',
        30, 15, 'easy', 8, 'has_wearable',
        '❤️ Steady the engine',
        'auto', 0, TRUE, 'free')
ON CONFLICT (quest_key) DO UPDATE SET
    title              = EXCLUDED.title,
    description        = EXCLUDED.description,
    icon               = EXCLUDED.icon,
    category           = EXCLUDED.category,
    target_value       = EXCLUDED.target_value,
    target_unit        = EXCLUDED.target_unit,
    xp_reward          = EXCLUDED.xp_reward,
    league_points      = EXCLUDED.league_points,
    difficulty         = EXCLUDED.difficulty,
    weight             = EXCLUDED.weight,
    requires_context   = EXCLUDED.requires_context,
    fun_label          = EXCLUDED.fun_label,
    verification_type  = EXCLUDED.verification_type,
    min_workouts       = EXCLUDED.min_workouts,
    is_active          = EXCLUDED.is_active,
    tier               = EXCLUDED.tier;

-- 3. Extend verify_wearable_quests_for_today --------------------------------
-- Drop every overload first (supabase-rules §12). Then re-create with the
-- expanded IN(...) filter + three new ELSIF branches.
DO $$
DECLARE
    v_sig TEXT;
BEGIN
    FOR v_sig IN
        SELECT oid::regprocedure::text
          FROM pg_proc
         WHERE proname = 'verify_wearable_quests_for_today'
           AND pronamespace = 'public'::regnamespace
    LOOP
        EXECUTE 'DROP FUNCTION IF EXISTS ' || v_sig || ' CASCADE';
    END LOOP;
END $$;

CREATE OR REPLACE FUNCTION public.verify_wearable_quests_for_today(
    p_timezone TEXT DEFAULT 'UTC'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_caller_id              UUID := auth.uid();
    v_today                  DATE;
    v_readiness              RECORD;
    v_quest                  RECORD;
    v_completed              TEXT[] := '{}';
    v_skipped                TEXT[] := '{}';
    v_walk_minutes_today     INT;
    v_active_recovery_minutes INT;
    v_zone2_minutes_today    INT;
    v_cardio_minutes_today   INT;
    v_recovery_workout_today BOOLEAN;
BEGIN
    IF v_caller_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required'
            USING ERRCODE = 'P0001';
    END IF;

    v_today := (now() AT TIME ZONE p_timezone)::DATE;

    -- Latest readiness row for today (band / score / sleep / hrv / rhr).
    -- Used by the legacy passive quests AND by `walk_when_red` /
    -- `respect_red_recovery` / `match_yesterday_strain` which gate on band.
    SELECT band, score, sleep_hours, hrv_delta_pct, rhr_trend_bpm
      INTO v_readiness
      FROM daily_readiness_history
     WHERE user_id = v_caller_id
       AND date = v_today
     ORDER BY updated_at DESC
     LIMIT 1;

    -- New actionable quests (active_recovery_logged / zone_2_minutes_20 /
    -- cardio_minutes_20) do NOT require a readiness row; they verify
    -- straight from `cardio_workouts`. So we no longer early-return when
    -- v_readiness IS NULL — instead, each branch handles its own
    -- precondition.

    FOR v_quest IN
        SELECT udq.id, udq.quest_key
          FROM user_daily_quests udq
         WHERE udq.user_id = v_caller_id
           AND udq.quest_date = v_today
           AND udq.is_completed = FALSE
           AND udq.quest_key IN (
               -- Legacy (kept for backwards-compat with already-assigned
               -- rows; templates are soft-disabled so no NEW assignments).
               'sleep_8h_wearable','recovery_above_67','hrv_above_baseline',
               'rhr_in_healthy_range','respect_red_recovery',
               -- Actionable wearable quests
               'walk_when_red',
               -- New actionable replacements (this migration)
               'active_recovery_logged','zone_2_minutes_20','cardio_minutes_20'
           )
    LOOP
        IF v_quest.quest_key = 'sleep_8h_wearable' THEN
            IF v_readiness IS NOT NULL AND COALESCE(v_readiness.sleep_hours, 0) >= 8 THEN
                PERFORM public.update_quest_progress(v_caller_id::TEXT, v_quest.quest_key, 1, p_timezone);
                v_completed := array_append(v_completed, v_quest.quest_key);
            ELSE
                v_skipped := array_append(v_skipped, v_quest.quest_key);
            END IF;

        ELSIF v_quest.quest_key = 'recovery_above_67' THEN
            IF v_readiness IS NOT NULL AND COALESCE(v_readiness.score, 0) >= 67 THEN
                PERFORM public.update_quest_progress(v_caller_id::TEXT, v_quest.quest_key, 1, p_timezone);
                v_completed := array_append(v_completed, v_quest.quest_key);
            ELSE
                v_skipped := array_append(v_skipped, v_quest.quest_key);
            END IF;

        ELSIF v_quest.quest_key = 'hrv_above_baseline' THEN
            IF v_readiness IS NOT NULL AND COALESCE(v_readiness.hrv_delta_pct, -1) > 0 THEN
                PERFORM public.update_quest_progress(v_caller_id::TEXT, v_quest.quest_key, 1, p_timezone);
                v_completed := array_append(v_completed, v_quest.quest_key);
            ELSE
                v_skipped := array_append(v_skipped, v_quest.quest_key);
            END IF;

        ELSIF v_quest.quest_key = 'rhr_in_healthy_range' THEN
            IF v_readiness IS NOT NULL AND COALESCE(v_readiness.rhr_trend_bpm, 1) <= 0 THEN
                PERFORM public.update_quest_progress(v_caller_id::TEXT, v_quest.quest_key, 1, p_timezone);
                v_completed := array_append(v_completed, v_quest.quest_key);
            ELSE
                v_skipped := array_append(v_skipped, v_quest.quest_key);
            END IF;

        ELSIF v_quest.quest_key = 'walk_when_red' THEN
            IF v_readiness IS NOT NULL AND v_readiness.band = 'red' THEN
                SELECT COALESCE(SUM(GREATEST(0, COALESCE(elapsed_seconds, 0)) / 60), 0)::INT
                  INTO v_walk_minutes_today
                  FROM cardio_workouts
                 WHERE user_id = v_caller_id
                   AND COALESCE(activity_type, '') IN ('walk', 'hike')
                   AND (started_at AT TIME ZONE p_timezone)::DATE = v_today;
                IF v_walk_minutes_today >= 20 THEN
                    PERFORM public.update_quest_progress(v_caller_id::TEXT, v_quest.quest_key, 1, p_timezone);
                    v_completed := array_append(v_completed, v_quest.quest_key);
                ELSE
                    v_skipped := array_append(v_skipped, v_quest.quest_key);
                END IF;
            ELSE
                v_skipped := array_append(v_skipped, v_quest.quest_key);
            END IF;

        ELSIF v_quest.quest_key = 'respect_red_recovery' THEN
            IF v_readiness IS NOT NULL AND v_readiness.band = 'red' THEN
                SELECT EXISTS (
                    SELECT 1 FROM cardio_workouts
                    WHERE user_id = v_caller_id
                      AND COALESCE(activity_type, '') IN ('walk','hike','yoga','stretch','mobility','foam_rolling')
                      AND (started_at AT TIME ZONE p_timezone)::DATE = v_today
                ) AND NOT EXISTS (
                    SELECT 1 FROM workouts
                    WHERE user_id = v_caller_id
                      AND date = v_today
                ) INTO v_recovery_workout_today;

                IF v_recovery_workout_today THEN
                    PERFORM public.update_quest_progress(v_caller_id::TEXT, v_quest.quest_key, 1, p_timezone);
                    v_completed := array_append(v_completed, v_quest.quest_key);
                ELSE
                    v_skipped := array_append(v_skipped, v_quest.quest_key);
                END IF;
            ELSE
                v_skipped := array_append(v_skipped, v_quest.quest_key);
            END IF;

        ELSIF v_quest.quest_key = 'active_recovery_logged' THEN
            -- Any walk/hike/yoga/stretch/mobility/foam-rolling cardio today
            -- summing to >= 15 minutes. No band gate — actionable on any day.
            SELECT COALESCE(SUM(GREATEST(0, COALESCE(elapsed_seconds, 0)) / 60), 0)::INT
              INTO v_active_recovery_minutes
              FROM cardio_workouts
             WHERE user_id = v_caller_id
               AND COALESCE(activity_type, '') IN ('walk','hike','yoga','stretch','mobility','foam_rolling')
               AND (started_at AT TIME ZONE p_timezone)::DATE = v_today;
            IF v_active_recovery_minutes >= 15 THEN
                PERFORM public.update_quest_progress(v_caller_id::TEXT, v_quest.quest_key, 1, p_timezone);
                v_completed := array_append(v_completed, v_quest.quest_key);
            ELSE
                v_skipped := array_append(v_skipped, v_quest.quest_key);
            END IF;

        ELSIF v_quest.quest_key = 'zone_2_minutes_20' THEN
            -- Sum minutes from cardio_workouts today where the session's
            -- average_heart_rate fell in [110, 150] bpm AND the session
            -- itself ran >= 5 min (filters out garbage 30-second rows).
            -- Threshold: total >= 20 min. Multiple short Z2 sessions stack.
            SELECT COALESCE(SUM(GREATEST(0, COALESCE(elapsed_seconds, 0)) / 60), 0)::INT
              INTO v_zone2_minutes_today
              FROM cardio_workouts
             WHERE user_id = v_caller_id
               AND (started_at AT TIME ZONE p_timezone)::DATE = v_today
               AND COALESCE(elapsed_seconds, 0) >= 300
               AND COALESCE(average_heart_rate, 0) BETWEEN 110 AND 150;
            IF v_zone2_minutes_today >= 20 THEN
                PERFORM public.update_quest_progress(v_caller_id::TEXT, v_quest.quest_key, 1, p_timezone);
                v_completed := array_append(v_completed, v_quest.quest_key);
            ELSE
                v_skipped := array_append(v_skipped, v_quest.quest_key);
            END IF;

        ELSIF v_quest.quest_key = 'cardio_minutes_20' THEN
            -- Any cardio_workouts row today (any HR / type) summing to
            -- >= 20 minutes. Distinct from `active_minutes_30` which is
            -- HealthKit ambient-active-minutes (steps + low-intensity);
            -- this requires actual logged cardio sessions.
            SELECT COALESCE(SUM(GREATEST(0, COALESCE(elapsed_seconds, 0)) / 60), 0)::INT
              INTO v_cardio_minutes_today
              FROM cardio_workouts
             WHERE user_id = v_caller_id
               AND (started_at AT TIME ZONE p_timezone)::DATE = v_today
               AND COALESCE(elapsed_seconds, 0) >= 60;
            IF v_cardio_minutes_today >= 20 THEN
                PERFORM public.update_quest_progress(v_caller_id::TEXT, v_quest.quest_key, 1, p_timezone);
                v_completed := array_append(v_completed, v_quest.quest_key);
            ELSE
                v_skipped := array_append(v_skipped, v_quest.quest_key);
            END IF;
        END IF;
    END LOOP;

    RETURN jsonb_build_object(
        'success', TRUE,
        'completed', v_completed,
        'skipped', v_skipped,
        'date', v_today,
        'band', COALESCE(v_readiness.band, 'unknown'),
        'score', COALESCE(v_readiness.score, 0)
    );
END;
$$;

REVOKE ALL ON FUNCTION public.verify_wearable_quests_for_today(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.verify_wearable_quests_for_today(TEXT) TO authenticated;

COMMENT ON FUNCTION public.verify_wearable_quests_for_today(TEXT) IS
    'Actionable Recovery Quests (20260610): supersedes 20260606. Walks today user_daily_quests for the caller and ticks any wearable-detectable completion. Adds detection for active_recovery_logged / zone_2_minutes_20 / cardio_minutes_20 (all from cardio_workouts, no readiness-row gate). Legacy passive sensor-state quests (recovery_above_67 / hrv_above_baseline / rhr_in_healthy_range) are soft-disabled at the template level but their detection branches are retained for backwards-compat with in-flight assignments.';

COMMIT;

-- ─── Verification ─────────────────────────────────────────────────────────
-- SELECT quest_key, title, is_active, requires_context, xp_reward
--   FROM quest_templates
--  WHERE quest_key IN (
--      'recovery_above_67', 'hrv_above_baseline', 'rhr_in_healthy_range',
--      'active_recovery_logged', 'zone_2_minutes_20', 'cardio_minutes_20'
--  )
--  ORDER BY is_active DESC, quest_key;
--
-- Expected: three new rows is_active=TRUE, three legacy rows is_active=FALSE.

