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
