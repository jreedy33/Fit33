-- ============================================================================
-- MIGRATION #176 — challenge_templates table + curated seed catalog (~40 rows)
-- ============================================================================
--
-- The `challenge_templates` table was referenced by `get_challenge_templates()`
-- (defined in `challenge_rpc_functions.sql:1518+`) but never actually created.
-- The function fell back to a hardcoded 5-row VALUES block, leaving every
-- 1v1-challenge user picking from {10K Steps Daily, 5K Runner, Gym Warrior,
-- 30 Min Active, Daily Walker} — three of which are duplicates of community
-- seed challenges, one of which (Gym Warrior, lift-every-day) is an over-
-- training anti-pattern.
--
-- This migration:
--   1. Creates the `challenge_templates` table with the columns the RPC
--      already returns PLUS a target_cadence / tier / requires_* / slug
--      surface needed by the cadence-aware UX shipping in #177.
--   2. RLS-enables the table: globally readable by `authenticated` (templates
--      are a public catalog, not user data); writes via service-role / CMS.
--   3. Seeds ~40 curated templates spanning all 14 ChallengeType values, with
--      beginner / intermediate / advanced tiers for every primary type.
--      Includes 3 Strava-gated templates (`requires_strava=TRUE`) that the
--      iOS UI surfaces only to Strava-connected users.
--   4. Replaces `get_challenge_templates()` with a widened RETURNS that
--      includes the new columns; drops the hardcoded fallback (the table
--      is now the single source of truth).
--
-- Pairs with: #177 (target_cadence column + cadence-aware progress RPCs).
-- Apply order: #176 → #177. #176 is standalone; #177 references the cadence
-- column that #176's seeds populate.
-- ============================================================================

BEGIN;

-- ============================================================================
-- 1. TABLE
-- ============================================================================

CREATE TABLE IF NOT EXISTS challenge_templates (
    id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    slug                        TEXT NOT NULL UNIQUE,

    -- Challenge definition
    challenge_type              TEXT NOT NULL,
    target_cadence              TEXT NOT NULL DEFAULT 'daily'
                                CHECK (target_cadence IN ('daily','weekly','total','per_session')),
    default_target              INT  NOT NULL,
    default_duration_days       INT  NOT NULL DEFAULT 7,
    target_unit                 TEXT NOT NULL,

    -- Display
    title                       TEXT NOT NULL,
    description                 TEXT,
    emoji                       TEXT NOT NULL DEFAULT '🏆',

    -- Discovery / curation
    is_featured                 BOOLEAN NOT NULL DEFAULT FALSE,
    is_official                 BOOLEAN NOT NULL DEFAULT TRUE,
    sort_order                  INT     NOT NULL DEFAULT 1000,
    category                    TEXT    NOT NULL DEFAULT 'fitness',
    tier                        TEXT    NOT NULL DEFAULT 'intermediate'
                                CHECK (tier IN ('beginner','intermediate','advanced')),

    -- Capability gates (iOS uses these to filter the catalog by user's
    -- connected wearables / integrations — Strava-required templates are
    -- only surfaced to users with `StravaService.shared.isConnected`).
    requires_wearable           BOOLEAN NOT NULL DEFAULT FALSE,
    requires_strava             BOOLEAN NOT NULL DEFAULT FALSE,
    requires_apple_watch        BOOLEAN NOT NULL DEFAULT FALSE,
    requires_health_kit         BOOLEAN NOT NULL DEFAULT FALSE,

    -- Soft-delete (preferred over hard delete so admin CMS can hide a
    -- template without orphaning any future `created_from_template_id` FK).
    retired_at                  TIMESTAMPTZ,
    created_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ─────────────────────────────────────────────────────────────────────────────
-- Defensive widening: a stub `challenge_templates` table may already exist on
-- some envs (CMS scaffolding, prior dev experiment, partial migration). The
-- `CREATE TABLE IF NOT EXISTS` above no-ops in that case, leaving an
-- older shape behind. Bring any pre-existing table up to the full spec
-- with idempotent ADD COLUMN calls. Each column is safe to re-add — no
-- DROP DEFAULT / NOT NULL flips, so re-running this migration on a
-- fully-migrated env is a no-op.
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE challenge_templates ADD COLUMN IF NOT EXISTS slug                  TEXT;
ALTER TABLE challenge_templates ADD COLUMN IF NOT EXISTS challenge_type        TEXT;
ALTER TABLE challenge_templates ADD COLUMN IF NOT EXISTS target_cadence        TEXT NOT NULL DEFAULT 'daily';
ALTER TABLE challenge_templates ADD COLUMN IF NOT EXISTS default_target        INT;
ALTER TABLE challenge_templates ADD COLUMN IF NOT EXISTS default_duration_days INT  NOT NULL DEFAULT 7;
ALTER TABLE challenge_templates ADD COLUMN IF NOT EXISTS target_unit           TEXT;
ALTER TABLE challenge_templates ADD COLUMN IF NOT EXISTS title                 TEXT;
ALTER TABLE challenge_templates ADD COLUMN IF NOT EXISTS description           TEXT;
ALTER TABLE challenge_templates ADD COLUMN IF NOT EXISTS emoji                 TEXT NOT NULL DEFAULT '🏆';
ALTER TABLE challenge_templates ADD COLUMN IF NOT EXISTS is_featured           BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE challenge_templates ADD COLUMN IF NOT EXISTS is_official           BOOLEAN NOT NULL DEFAULT TRUE;
ALTER TABLE challenge_templates ADD COLUMN IF NOT EXISTS sort_order            INT     NOT NULL DEFAULT 1000;
ALTER TABLE challenge_templates ADD COLUMN IF NOT EXISTS category              TEXT    NOT NULL DEFAULT 'fitness';
ALTER TABLE challenge_templates ADD COLUMN IF NOT EXISTS tier                  TEXT    NOT NULL DEFAULT 'intermediate';
ALTER TABLE challenge_templates ADD COLUMN IF NOT EXISTS requires_wearable     BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE challenge_templates ADD COLUMN IF NOT EXISTS requires_strava       BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE challenge_templates ADD COLUMN IF NOT EXISTS requires_apple_watch  BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE challenge_templates ADD COLUMN IF NOT EXISTS requires_health_kit   BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE challenge_templates ADD COLUMN IF NOT EXISTS retired_at            TIMESTAMPTZ;
ALTER TABLE challenge_templates ADD COLUMN IF NOT EXISTS created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW();
ALTER TABLE challenge_templates ADD COLUMN IF NOT EXISTS updated_at            TIMESTAMPTZ NOT NULL DEFAULT NOW();

-- Add the cadence CHECK constraint defensively (only if missing — DROP+CREATE
-- so re-running is a no-op without raising on the first add).
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
         WHERE conname = 'challenge_templates_target_cadence_check'
           AND conrelid = 'challenge_templates'::regclass
    ) THEN
        ALTER TABLE challenge_templates
            ADD CONSTRAINT challenge_templates_target_cadence_check
            CHECK (target_cadence IN ('daily','weekly','total','per_session'));
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
         WHERE conname = 'challenge_templates_tier_check'
           AND conrelid = 'challenge_templates'::regclass
    ) THEN
        ALTER TABLE challenge_templates
            ADD CONSTRAINT challenge_templates_tier_check
            CHECK (tier IN ('beginner','intermediate','advanced'));
    END IF;

    -- slug UNIQUE — may already exist from CREATE TABLE; only add if missing.
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
         WHERE conname = 'challenge_templates_slug_key'
           AND conrelid = 'challenge_templates'::regclass
    ) AND NOT EXISTS (
        SELECT 1 FROM pg_indexes
         WHERE schemaname = 'public'
           AND tablename = 'challenge_templates'
           AND indexname = 'challenge_templates_slug_key'
    ) THEN
        ALTER TABLE challenge_templates
            ADD CONSTRAINT challenge_templates_slug_key UNIQUE (slug);
    END IF;
END $$;

-- Hot path: featured catalog ordered for the picker.
CREATE INDEX IF NOT EXISTS idx_challenge_templates_active_featured
  ON challenge_templates (is_featured DESC, sort_order)
  WHERE retired_at IS NULL;

-- Filter by activity (chip-filter UI in ChallengeSetupView).
CREATE INDEX IF NOT EXISTS idx_challenge_templates_type
  ON challenge_templates (challenge_type)
  WHERE retired_at IS NULL;

-- Filter by cadence (rare path; most rows are 'daily'). Partial keeps it cheap.
CREATE INDEX IF NOT EXISTS idx_challenge_templates_cadence
  ON challenge_templates (target_cadence, challenge_type)
  WHERE retired_at IS NULL AND target_cadence <> 'daily';

-- ============================================================================
-- 2. RLS
-- ============================================================================
-- Templates are a public catalog — every authenticated user reads them. No
-- INSERT/UPDATE/DELETE policies for clients; CMS writes via service_role.
-- Note: `delete_user_account()` does NOT need to touch this table — there's
-- no per-user data here.

ALTER TABLE challenge_templates ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "challenge_templates_read_all" ON challenge_templates;
CREATE POLICY "challenge_templates_read_all"
    ON challenge_templates FOR SELECT
    TO authenticated
    USING (retired_at IS NULL);

-- ============================================================================
-- 3. SEED CATALOG (~40 templates)
-- ============================================================================
-- Naming convention: lowercase slug with underscores; titles are the
-- user-facing strings exactly as they appear in the picker.
-- ON CONFLICT (slug) DO NOTHING means re-running this migration on a deployed
-- env preserves any CMS edits to existing rows.

INSERT INTO challenge_templates (
    slug, challenge_type, target_cadence, default_target, default_duration_days,
    target_unit, title, description, emoji,
    is_featured, sort_order, category, tier,
    requires_wearable, requires_strava, requires_apple_watch, requires_health_kit
) VALUES
-- ─── STEPS — beginner → advanced tiers ──────────────────────────────────────
('step_starter_5k', 'steps', 'daily', 5000, 7,
 'steps', '5K Step Starter', 'A gentle daily step goal — perfect for building the walking habit.', '👟',
 FALSE, 110, 'fitness', 'beginner',
 FALSE, FALSE, FALSE, TRUE),

('steady_walker_7k', 'steps', 'daily', 7500, 7,
 'steps', '7K Steady Walker', 'Moderate daily steps — a comfortable middle ground above sedentary.', '👣',
 FALSE, 120, 'fitness', 'intermediate',
 FALSE, FALSE, FALSE, TRUE),

('ten_k_steps_daily', 'steps', 'daily', 10000, 7,
 'steps', '10K Steps Daily', 'The classic — hit 10,000 steps every single day.', '👟',
 TRUE, 100, 'fitness', 'intermediate',
 FALSE, FALSE, FALSE, TRUE),

('mover_15k', 'steps', 'daily', 15000, 7,
 'steps', '15K Mover', 'For active days — 15,000 steps daily means real movement.', '🚶‍♂️',
 FALSE, 130, 'fitness', 'advanced',
 FALSE, FALSE, FALSE, TRUE),

('beast_mode_20k', 'steps', 'daily', 20000, 7,
 'steps', '20K Beast Mode', 'Elite-level daily volume — only attempt if you''re already crushing 15K.', '🔥',
 FALSE, 140, 'fitness', 'advanced',
 FALSE, FALSE, FALSE, TRUE),

-- ─── RUN cadence (daily / weekly / per-session / total) ─────────────────────
('one_run_per_week', 'run', 'weekly', 1, 7,
 'workouts', 'One Run This Week', 'Just get one run in. Build the habit before the volume.', '🏃',
 FALSE, 210, 'fitness', 'beginner',
 FALSE, FALSE, FALSE, TRUE),

('twice_week_5k', 'run', 'weekly', 2, 7,
 'workouts', 'Twice-a-Week 5K', 'Two 5K-or-longer runs this week. Cardio with breathing room to recover.', '🏃‍♀️',
 TRUE, 200, 'fitness', 'intermediate',
 FALSE, FALSE, FALSE, TRUE),

('five_runs_in_seven_days', 'run', 'weekly', 5, 7,
 'workouts', '5 Runs in 7 Days', 'Five runs in seven days — building a real running rhythm.', '🏃',
 TRUE, 220, 'fitness', 'intermediate',
 FALSE, FALSE, FALSE, TRUE),

('weekly_25k_run', 'run', 'weekly', 25, 7,
 'km', '25 km Weekly Volume', 'Hit 25 km of running this week — a solid intermediate aerobic base.', '🛣️',
 FALSE, 230, 'fitness', 'intermediate',
 FALSE, FALSE, FALSE, TRUE),

('marathon_month', 'run', 'total', 100, 30,
 'km', 'Marathon Month', '100 km of running over 30 days. Equivalent to ~25 km/week — marathon-builder volume.', '🏅',
 FALSE, 240, 'fitness', 'advanced',
 FALSE, FALSE, FALSE, TRUE),

-- ─── WALK cadence ───────────────────────────────────────────────────────────
('lunch_walk_30', 'walk', 'daily', 30, 7,
 'minutes', '30 Min Lunchtime Walk', 'Walk 30 minutes during your lunch break every day.', '🚶',
 FALSE, 310, 'wellness', 'intermediate',
 FALSE, FALSE, FALSE, TRUE),

('five_walks_this_week', 'walk', 'weekly', 5, 7,
 'workouts', '5 Walks This Week', 'Get five outdoor walks in this week. Great for low-stress cardio.', '🌳',
 FALSE, 320, 'wellness', 'beginner',
 FALSE, FALSE, FALSE, TRUE),

('walk_50k_volume', 'walk', 'total', 50, 14,
 'km', '50 km Walk Volume', 'Cumulative 50 km of walking over two weeks — pace yourself.', '🥾',
 FALSE, 330, 'fitness', 'intermediate',
 FALSE, FALSE, FALSE, TRUE),

-- ─── LIFT / STRENGTH (no daily lift — recovery science) ─────────────────────
('three_day_lifter', 'lift', 'weekly', 3, 7,
 'workouts', '3-Day Lifter', 'Three strength sessions this week. Honors recovery — every major muscle group rests.', '🏋️',
 TRUE, 400, 'fitness', 'intermediate',
 FALSE, FALSE, FALSE, FALSE),

('four_day_lifter', 'lift', 'weekly', 4, 7,
 'workouts', '4-Day Lifter', 'Four strength workouts this week. Upper/lower or push/pull/legs/upper splits.', '💪',
 FALSE, 410, 'fitness', 'intermediate',
 FALSE, FALSE, FALSE, FALSE),

('volume_100k_lbs', 'total_volume_lifted', 'total', 100000, 7,
 'lbs', '100K Volume Quest', 'Move 100,000 pounds total this week (working sets only — warmups don''t count).', '⚙️',
 FALSE, 420, 'fitness', 'intermediate',
 FALSE, FALSE, FALSE, FALSE),

('iron_beast_200k', 'total_volume_lifted', 'total', 200000, 7,
 'lbs', '200K Iron Beast', '200,000 pounds in one week. Advanced volume — only attempt with prior tonnage data.', '🦾',
 FALSE, 430, 'fitness', 'advanced',
 FALSE, FALSE, FALSE, FALSE),

-- ─── CYCLING (HealthKit cycling workouts) ───────────────────────────────────
('first_ride_week', 'cycling', 'weekly', 1, 7,
 'workouts', 'First Ride Week', 'Just one ride this week. Get rolling.', '🚴',
 FALSE, 510, 'fitness', 'beginner',
 FALSE, FALSE, FALSE, TRUE),

('cycling_100km_week', 'cycling', 'weekly', 100, 7,
 'km', 'Cycling 100 km Week', '100 km on the bike this week — solid intermediate volume.', '🚴‍♀️',
 FALSE, 520, 'fitness', 'intermediate',
 FALSE, FALSE, FALSE, TRUE),

-- ─── SWIM ───────────────────────────────────────────────────────────────────
('three_swims_week', 'swim', 'weekly', 3, 7,
 'workouts', '3 Swims This Week', 'Three swim sessions this week. Joint-friendly cardio.', '🏊',
 FALSE, 600, 'fitness', 'intermediate',
 FALSE, FALSE, FALSE, TRUE),

-- ─── STAIRS (HealthKit flightsClimbed) ──────────────────────────────────────
('ten_floors_daily', 'stairs_climbed', 'daily', 10, 7,
 'flights', '10 Floors Daily', 'Ten flights of stairs every day. Compound lower-body cardio.', '🪜',
 FALSE, 710, 'fitness', 'beginner',
 FALSE, FALSE, FALSE, TRUE),

('thirty_floors_daily', 'stairs_climbed', 'daily', 30, 7,
 'flights', '30 Floors Daily', 'Thirty flights of stairs every day. Take the stairs at every chance.', '🏗️',
 FALSE, 720, 'fitness', 'intermediate',
 FALSE, FALSE, FALSE, TRUE),

-- ─── MIND & BODY (yoga / mobility / flexibility / coreTraining workouts) ────
('yoga_30min_week', 'mind_body_minutes', 'weekly', 30, 7,
 'minutes', '30 Min Yoga / Mobility', '30 total minutes of yoga, stretching, or mobility this week. Recovery counts.', '🧘',
 FALSE, 810, 'wellness', 'beginner',
 FALSE, FALSE, FALSE, TRUE),

('yoga_60min_week', 'mind_body_minutes', 'weekly', 60, 7,
 'minutes', '60 Min Yoga / Mobility', '60 total minutes of mind-body work this week. Roughly 2-3 sessions.', '🧘‍♀️',
 FALSE, 820, 'wellness', 'intermediate',
 FALSE, FALSE, FALSE, TRUE),

-- ─── ACTIVE MINUTES (HealthKit active energy minutes) ───────────────────────
('fifteen_min_movement', 'active_minutes', 'daily', 15, 7,
 'minutes', '15 Min Movement', 'Fifteen active minutes every day. The smallest meaningful daily goal.', '⏱️',
 FALSE, 910, 'fitness', 'beginner',
 FALSE, FALSE, FALSE, TRUE),

('thirty_min_movement', 'active_minutes', 'daily', 30, 7,
 'minutes', '30 Min Movement', 'Be active 30 minutes every day — walking, lifting, anything counts.', '⌚',
 TRUE, 900, 'fitness', 'intermediate',
 FALSE, FALSE, FALSE, TRUE),

('power_hour_60', 'active_minutes', 'daily', 60, 7,
 'minutes', '60 Min Power Hour', 'A full hour of active movement every day. Real volume.', '⚡',
 FALSE, 920, 'fitness', 'advanced',
 FALSE, FALSE, FALSE, TRUE),

-- ─── CALORIES (HealthKit active energy burned) ──────────────────────────────
('slow_burn_300', 'calories', 'daily', 300, 7,
 'calories', '300 Cal Slow Burn', 'Burn 300 active calories every day. Beginner cardio target.', '🔥',
 FALSE, 1010, 'fitness', 'beginner',
 FALSE, FALSE, FALSE, TRUE),

('burn_500_club', 'calories', 'daily', 500, 7,
 'calories', '500 Cal Burn Club', 'Burn 500 active calories every day through exercise.', '🔥',
 TRUE, 1000, 'fitness', 'intermediate',
 FALSE, FALSE, FALSE, TRUE),

('cal_crusher_800', 'calories', 'daily', 800, 7,
 'calories', '800 Cal Crusher', 'Burn 800 active calories daily — high-output athlete territory.', '💥',
 FALSE, 1020, 'fitness', 'advanced',
 FALSE, FALSE, FALSE, TRUE),

-- ─── HYDRATION (HydrationService — manual logs) ─────────────────────────────
('hydrate_starter_15l', 'hydrate', 'daily', 1500, 7,
 'ml', '1.5L Hydrate Starter', 'Drink 1.5L of water every day. Simple, foundational.', '💧',
 FALSE, 1110, 'wellness', 'beginner',
 FALSE, FALSE, FALSE, FALSE),

('hydro_homies_2l', 'hydrate', 'daily', 2000, 7,
 'ml', '2L Hydro Homies', 'Two liters of water daily. Your body will thank you.', '💧',
 TRUE, 1100, 'wellness', 'intermediate',
 FALSE, FALSE, FALSE, FALSE),

('water_warrior_3l', 'hydrate', 'daily', 3000, 7,
 'ml', '3L Water Warrior', '3L of water daily — well above standard hydration recs.', '🚰',
 FALSE, 1120, 'wellness', 'advanced',
 FALSE, FALSE, FALSE, FALSE),

-- ─── PROTEIN (MealService — manual logs) ────────────────────────────────────
('protein_starter_100', 'protein', 'daily', 100, 7,
 'grams', '100g Protein Starter', '100 grams of protein daily — solid baseline for recovery.', '🍗',
 FALSE, 1210, 'nutrition', 'beginner',
 FALSE, FALSE, FALSE, FALSE),

('protein_club_150', 'protein', 'daily', 150, 7,
 'grams', '150g Protein Club', '150g of protein daily. Essential for muscle building and recovery.', '🥩',
 TRUE, 1200, 'nutrition', 'intermediate',
 FALSE, FALSE, FALSE, FALSE),

('protein_builder_200', 'protein', 'daily', 200, 7,
 'grams', '200g Protein Builder', '200g of protein daily — for serious lifters in a building phase.', '🥚',
 FALSE, 1220, 'nutrition', 'advanced',
 FALSE, FALSE, FALSE, FALSE),

-- ─── WORKOUT STREAK ─────────────────────────────────────────────────────────
('five_workouts_this_week', 'workout_streak', 'weekly', 5, 7,
 'workouts', '5 Workouts This Week', 'Five workouts in seven days. Any type counts — find your rhythm.', '📅',
 FALSE, 1310, 'fitness', 'intermediate',
 FALSE, FALSE, FALSE, FALSE),

('no_rest_day_streak', 'workout_streak', 'daily', 1, 7,
 'workouts', 'No Rest Day', 'One workout every single day. Yoga / walks count — recovery-respecting.', '💪',
 FALSE, 1320, 'fitness', 'advanced',
 FALSE, FALSE, FALSE, FALSE),

-- ─── SLEEP / RECOVERY (wearable-required — only surface to wearable users) ──
('sleep_champion_7h', 'sleep_hours', 'daily', 7, 7,
 'hours', '7h Sleep Champion', 'Sleep 7 hours every night. Wearable required to track.', '😴',
 FALSE, 1410, 'wellness', 'beginner',
 TRUE, FALSE, FALSE, FALSE),

('sleep_master_8h', 'sleep_hours', 'daily', 8, 7,
 'hours', '8h Sleep Master', 'Sleep 8 hours every night. The recovery foundation.', '🌙',
 FALSE, 1420, 'wellness', 'intermediate',
 TRUE, FALSE, FALSE, FALSE),

-- ─── STRAVA-GATED (only surface to users with StravaService.isConnected) ────
('strava_streak_5_runs', 'run', 'weekly', 5, 7,
 'workouts', 'Strava Streak — 5 Runs / 7 Days', 'Five runs in seven days, tracked by Strava. Auto-syncs the moment you finish.', '🟧',
 TRUE, 250, 'fitness', 'intermediate',
 FALSE, TRUE, FALSE, TRUE),

('strava_cycling_century', 'cycling', 'total', 100, 7,
 'km', 'Strava Cycling Century', 'Ride 100 km this week, tracked by Strava. Long ride or split across the week.', '🟧',
 FALSE, 530, 'fitness', 'intermediate',
 FALSE, TRUE, FALSE, TRUE),

('strava_long_run_builder', 'run', 'per_session', 10, 14,
 'km', 'Strava Long Run Builder', 'Complete one run of 10 km or longer in the next two weeks. Powered by Strava.', '🟧',
 FALSE, 260, 'fitness', 'intermediate',
 FALSE, TRUE, FALSE, TRUE)

ON CONFLICT (slug) DO NOTHING;

-- ============================================================================
-- 4. RPC: get_challenge_templates() — widened RETURNS
-- ============================================================================
-- Replaces the version in `challenge_rpc_functions.sql:1518+` whose RETURNS
-- only had 9 columns and whose body fell back to a hardcoded VALUES block
-- when the table didn't exist. The table now ALWAYS exists (this migration),
-- so the fallback branch is removed entirely.
-- Drop ALL overloads first per supabase-rules invariant 12 (drop-all-before-
-- create-or-replace) — this RPC has historically had only one signature, but
-- the defensive DROP keeps the migration self-healing.

DROP FUNCTION IF EXISTS get_challenge_templates();

CREATE OR REPLACE FUNCTION get_challenge_templates()
RETURNS TABLE (
    id                          UUID,
    slug                        TEXT,
    challenge_type              TEXT,
    target_cadence              TEXT,
    title                       TEXT,
    description                 TEXT,
    emoji                       TEXT,
    default_daily_target        INT,    -- aliased from default_target for backward-compat with the existing iOS DTO
    default_duration_days       INT,
    target_unit                 TEXT,
    is_featured                 BOOLEAN,
    is_official                 BOOLEAN,
    sort_order                  INT,
    category                    TEXT,
    tier                        TEXT,
    requires_wearable           BOOLEAN,
    requires_strava             BOOLEAN,
    requires_apple_watch        BOOLEAN,
    requires_health_kit         BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN QUERY
    SELECT
        ct.id,
        ct.slug,
        ct.challenge_type,
        ct.target_cadence,
        ct.title,
        ct.description,
        ct.emoji,
        ct.default_target  AS default_daily_target,
        ct.default_duration_days,
        ct.target_unit,
        ct.is_featured,
        ct.is_official,
        ct.sort_order,
        ct.category,
        ct.tier,
        ct.requires_wearable,
        ct.requires_strava,
        ct.requires_apple_watch,
        ct.requires_health_kit
    FROM challenge_templates ct
    WHERE ct.retired_at IS NULL
    ORDER BY
        ct.is_featured DESC,
        ct.sort_order ASC,
        ct.title ASC;
END;
$$;

GRANT EXECUTE ON FUNCTION get_challenge_templates() TO authenticated;

-- ============================================================================
-- 5. AUDIT — fail-loud verification
-- ============================================================================

DO $$
DECLARE
    v_row_count           INT;
    v_cadence_count       INT;
    v_featured_count      INT;
    v_strava_gated_count  INT;
    v_function_count      INT;
BEGIN
    -- Table exists with seeded rows?
    SELECT COUNT(*) INTO v_row_count
      FROM challenge_templates
     WHERE retired_at IS NULL;

    IF v_row_count < 30 THEN
        RAISE EXCEPTION
            'challenge_templates seed underseeded: % rows (expected ≥ 30)', v_row_count;
    END IF;

    -- All 4 cadences represented?
    SELECT COUNT(DISTINCT target_cadence) INTO v_cadence_count
      FROM challenge_templates
     WHERE retired_at IS NULL;

    IF v_cadence_count < 4 THEN
        RAISE EXCEPTION
            'challenge_templates seed missing cadence diversity: % distinct cadences (expected 4 = daily|weekly|total|per_session)',
            v_cadence_count;
    END IF;

    -- At least one featured row per major activity?
    SELECT COUNT(*) INTO v_featured_count
      FROM challenge_templates
     WHERE is_featured = TRUE AND retired_at IS NULL;

    IF v_featured_count < 6 THEN
        RAISE EXCEPTION
            'challenge_templates seed missing featured anchors: % featured (expected ≥ 6 across activity types)',
            v_featured_count;
    END IF;

    -- At least one Strava-required template (user explicit ask)?
    SELECT COUNT(*) INTO v_strava_gated_count
      FROM challenge_templates
     WHERE requires_strava = TRUE AND retired_at IS NULL;

    IF v_strava_gated_count < 1 THEN
        RAISE EXCEPTION
            'challenge_templates seed missing Strava-gated templates (expected ≥ 1)';
    END IF;

    -- Exactly one get_challenge_templates() function (no overload drift)?
    SELECT COUNT(*) INTO v_function_count
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.proname = 'get_challenge_templates';

    IF v_function_count <> 1 THEN
        RAISE EXCEPTION
            'get_challenge_templates() should have exactly 1 overload, found %', v_function_count;
    END IF;

    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
    RAISE NOTICE '✅ MIGRATION #176 COMPLETE — challenge_templates';
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
    RAISE NOTICE '   • % active templates seeded', v_row_count;
    RAISE NOTICE '   • % distinct cadences (daily/weekly/total/per_session)', v_cadence_count;
    RAISE NOTICE '   • % featured templates', v_featured_count;
    RAISE NOTICE '   • % Strava-gated templates', v_strava_gated_count;
    RAISE NOTICE '   • get_challenge_templates() returns 19 columns (was 9)';
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
END $$;

COMMIT;
