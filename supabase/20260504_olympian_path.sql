-- Migration: Path to 33 — Annual Olympian Track
-- Date: 2026-05-04
-- Reason: Personalized 33-goal annual track that ties the brand "33" to a
--         stackable yearly "Olympian YYYY" badge. Built on top of the
--         existing achievements engine (no new event bus). Each user gets
--         33 goals personalized to their onboarding fitness goal
--         (strength / endurance / weightLoss / general / athletic),
--         100% free-achievable in 12 months.
--
-- Architecture:
--   1. Extend `achievements` with season_year + goal_tier + applicable_archetypes + free_achievable_in_year
--   2. New table `user_olympian_assignments` — per-user ordered 33 (frozen for the year)
--   3. New table `user_olympian_seasons` — stackable badge log
--   4. RPC `assign_olympian_path(p_year, p_archetype)` — idempotent first-open assignment
--   5. RPC `complete_olympian_season_if_done(p_year)` — mints the badge when 33/33 unlocked
--   6. Patch `unlock_achievement` to call (5) at tail when an olympian goal unlocks
--   7. Seed ~50 pool rows for season_year=2026
--
-- Free-achievability gate (CI-enforced):
--   - All seeded rows have free_achievable_in_year = true
--   - Audit block at end RAISEs EXCEPTION if any olympian_path row violates the gate
--
-- Fitness Expert review (FE 18 / 20a / 20b / 20a-relative — 2026-05-04):
--   - FE 18 ("no 2 full workouts/day"): All workout-count goals are
--     LIFETIME totals (5/25/50/100/150 workouts). None require a same-day
--     pair. No ROW prescribes 2 workouts on a single day.
--   - FE 20a (passive overnight-sensor goals retired): Zero olympian_path
--     rows reference HRV / RHR / sleep_score / recovery_score / overnight
--     biometrics. All goals reward a same-day USER ACTION (workout, meal,
--     hydration, friend, challenge, quest streak, distance, PR).
--   - FE 20a-relative (no goal gated on another user's behavior): Goals
--     are absolute personal targets (count of workouts, days of streak,
--     meals logged). The two competitive-surface goals
--     (`tier_gold` / `tier_diamond` / `won_challenge`) are explicitly
--     approved by the plan — they target the legitimate competitive
--     surfaces (Weekly League / Challenges) where competition belongs.
--     This mirrors the existing achievement precedent (`tier_gold`,
--     `tier_diamond` are already shipped achievements).
--   - FE 20b: Activity-mix bias would only matter if Olympian goals
--     interacted with Daily Quests' v3 slot allocation — they don't.
--     Olympian completion is event-driven (any time the underlying
--     achievement key thresholds), not slate-allocated.
--   - FE 4 (no muscle group neglected): The strength `all_muscles` goal
--     enforces 8-major-muscle coverage at the season level; the path
--     does not gate on muscle-specific volume that could create avoidance.

BEGIN;

-- ============================================================================
-- 1. EXTEND `achievements` SCHEMA
-- ============================================================================

-- Widen category CHECK to include 'olympian_path'
ALTER TABLE achievements DROP CONSTRAINT IF EXISTS achievements_category_check;
ALTER TABLE achievements ADD CONSTRAINT achievements_category_check
    CHECK (category IN ('workout', 'streak', 'social', 'nutrition', 'level', 'special', 'olympian_path'));

-- Additive columns (nullable for existing rows; populated for olympian_path rows)
ALTER TABLE achievements ADD COLUMN IF NOT EXISTS season_year INT;
ALTER TABLE achievements ADD COLUMN IF NOT EXISTS goal_tier SMALLINT
    CHECK (goal_tier IS NULL OR goal_tier BETWEEN 1 AND 5);
ALTER TABLE achievements ADD COLUMN IF NOT EXISTS applicable_archetypes TEXT[];
ALTER TABLE achievements ADD COLUMN IF NOT EXISTS free_achievable_in_year BOOLEAN NOT NULL DEFAULT TRUE;

-- Index for efficient assignment queries (filter by season + tier)
CREATE INDEX IF NOT EXISTS idx_achievements_olympian_pool
    ON achievements (season_year, goal_tier)
    WHERE category = 'olympian_path';

-- ============================================================================
-- 2. NEW TABLE: user_olympian_assignments
-- ============================================================================

CREATE TABLE IF NOT EXISTS user_olympian_assignments (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
    season_year INT NOT NULL,
    achievement_id UUID NOT NULL REFERENCES achievements(id) ON DELETE CASCADE,
    goal_number SMALLINT NOT NULL CHECK (goal_number BETWEEN 1 AND 33),
    goal_tier SMALLINT NOT NULL CHECK (goal_tier BETWEEN 1 AND 5),
    archetype TEXT NOT NULL CHECK (archetype IN ('strength', 'endurance', 'weightLoss', 'general', 'athletic')),
    assigned_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (user_id, season_year, goal_number),
    UNIQUE (user_id, season_year, achievement_id)
);

ALTER TABLE user_olympian_assignments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "users_select_own_olympian_assignments" ON user_olympian_assignments;
CREATE POLICY "users_select_own_olympian_assignments" ON user_olympian_assignments
    FOR SELECT USING (user_id = auth.uid());

DROP POLICY IF EXISTS "users_insert_own_olympian_assignments" ON user_olympian_assignments;
CREATE POLICY "users_insert_own_olympian_assignments" ON user_olympian_assignments
    FOR INSERT WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "users_delete_own_olympian_assignments" ON user_olympian_assignments;
CREATE POLICY "users_delete_own_olympian_assignments" ON user_olympian_assignments
    FOR DELETE USING (user_id = auth.uid());

CREATE INDEX IF NOT EXISTS idx_user_olympian_assignments_user_year
    ON user_olympian_assignments (user_id, season_year);

-- ============================================================================
-- 3. NEW TABLE: user_olympian_seasons (stackable badge)
-- ============================================================================

CREATE TABLE IF NOT EXISTS user_olympian_seasons (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
    season_year INT NOT NULL,
    archetype TEXT NOT NULL CHECK (archetype IN ('strength', 'endurance', 'weightLoss', 'general', 'athletic')),
    completed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (user_id, season_year)
);

ALTER TABLE user_olympian_seasons ENABLE ROW LEVEL SECURITY;

-- Read own
DROP POLICY IF EXISTS "users_select_own_olympian_seasons" ON user_olympian_seasons;
CREATE POLICY "users_select_own_olympian_seasons" ON user_olympian_seasons
    FOR SELECT USING (user_id = auth.uid());

-- Read accepted-friends' badges (mirrors user_achievements social-visibility pattern)
DROP POLICY IF EXISTS "users_select_friend_olympian_seasons" ON user_olympian_seasons;
CREATE POLICY "users_select_friend_olympian_seasons" ON user_olympian_seasons
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM friendships
            WHERE status = 'accepted'
              AND ((requester_id = auth.uid() AND addressee_id = user_olympian_seasons.user_id)
                OR (requester_id = user_olympian_seasons.user_id AND addressee_id = auth.uid()))
        )
    );

CREATE INDEX IF NOT EXISTS idx_user_olympian_seasons_user
    ON user_olympian_seasons (user_id);

-- ============================================================================
-- 4. ASSIGN OLYMPIAN PATH RPC
-- ============================================================================
--
-- Drops every overload of `assign_olympian_path` to keep PostgREST resolution
-- unambiguous (Supabase invariant 12).
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN (
        SELECT n.nspname, p.proname, oidvectortypes(p.proargtypes) AS args
          FROM pg_proc p
          JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname = 'public'
           AND p.proname = 'assign_olympian_path'
    ) LOOP
        EXECUTE format('DROP FUNCTION IF EXISTS %I.%I(%s)', r.nspname, r.proname, r.args);
    END LOOP;
END$$;

CREATE FUNCTION assign_olympian_path(p_year INT, p_archetype TEXT)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    current_user_uuid UUID;
    v_archetype TEXT;
    v_existing_count INT;
    v_assignments jsonb;
    v_meta_id UUID;
    v_goal_number SMALLINT;
    v_tier SMALLINT;
    v_universal_per_tier INT[5] := ARRAY[4, 3, 3, 2, 3]; -- T1..T5
    v_archetype_per_tier INT[5] := ARRAY[3, 4, 4, 5, 1]; -- T1..T5
    v_tier_offsets INT[5]      := ARRAY[0, 7, 14, 21, 28]; -- starting goal_number for each tier
BEGIN
    current_user_uuid := auth.uid();
    IF current_user_uuid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    -- Validate archetype (reject unknown values but never crash; default to general)
    v_archetype := CASE
        WHEN p_archetype IN ('strength', 'endurance', 'weightLoss', 'general', 'athletic')
        THEN p_archetype
        ELSE 'general'
    END;

    -- Idempotency: if 33 assignments already exist for this user/year, return them as-is
    SELECT COUNT(*) INTO v_existing_count
    FROM user_olympian_assignments
    WHERE user_id = current_user_uuid AND season_year = p_year;

    IF v_existing_count = 33 THEN
        SELECT jsonb_agg(jsonb_build_object(
            'goal_number', goal_number,
            'goal_tier', goal_tier,
            'achievement_id', achievement_id,
            'achievement_key', a.key,
            'archetype', archetype
        ) ORDER BY goal_number)
        INTO v_assignments
        FROM user_olympian_assignments uoa
        JOIN achievements a ON a.id = uoa.achievement_id
        WHERE uoa.user_id = current_user_uuid AND uoa.season_year = p_year;

        RETURN jsonb_build_object(
            'created', false,
            'archetype', (SELECT archetype FROM user_olympian_assignments
                          WHERE user_id = current_user_uuid AND season_year = p_year LIMIT 1),
            'assignments', COALESCE(v_assignments, '[]'::jsonb)
        );
    END IF;

    -- If a partial assignment exists (e.g. failed mid-flight), wipe and re-assign
    -- to keep the 33 invariant intact.
    IF v_existing_count > 0 AND v_existing_count < 33 THEN
        DELETE FROM user_olympian_assignments
        WHERE user_id = current_user_uuid AND season_year = p_year;
    END IF;

    -- Locate the meta goal (key olympian_<year>_complete_path) — always #33
    SELECT id INTO v_meta_id
    FROM achievements
    WHERE key = 'olympian_' || p_year || '_complete_path' AND season_year = p_year
    LIMIT 1;

    IF v_meta_id IS NULL THEN
        RAISE EXCEPTION 'Olympian meta goal not seeded for year %', p_year;
    END IF;

    -- Per-tier slot fill: top N universal + top M archetype-specific, ordered
    -- deterministically by (threshold ASC, key ASC).
    FOR v_tier IN 1..5 LOOP
        DECLARE
            v_universal_count INT := v_universal_per_tier[v_tier];
            v_archetype_count INT := v_archetype_per_tier[v_tier];
            v_tier_offset INT := v_tier_offsets[v_tier];
            v_slot INT := 0;
            r RECORD;
        BEGIN
            -- Universal slots first
            FOR r IN (
                SELECT id
                FROM achievements
                WHERE category = 'olympian_path'
                  AND season_year = p_year
                  AND goal_tier = v_tier
                  AND 'universal' = ANY(applicable_archetypes)
                  AND id <> v_meta_id
                ORDER BY threshold ASC, key ASC
                LIMIT v_universal_count
            ) LOOP
                v_slot := v_slot + 1;
                v_goal_number := v_tier_offset + v_slot;
                INSERT INTO user_olympian_assignments
                    (user_id, season_year, achievement_id, goal_number, goal_tier, archetype)
                VALUES
                    (current_user_uuid, p_year, r.id, v_goal_number, v_tier, v_archetype)
                ON CONFLICT (user_id, season_year, achievement_id) DO NOTHING;
            END LOOP;

            -- Archetype-specific slots
            FOR r IN (
                SELECT id
                FROM achievements
                WHERE category = 'olympian_path'
                  AND season_year = p_year
                  AND goal_tier = v_tier
                  AND v_archetype = ANY(applicable_archetypes)
                  AND NOT ('universal' = ANY(applicable_archetypes))
                  AND id <> v_meta_id
                  AND id NOT IN (
                      SELECT achievement_id FROM user_olympian_assignments
                      WHERE user_id = current_user_uuid AND season_year = p_year
                  )
                ORDER BY threshold ASC, key ASC
                LIMIT v_archetype_count
            ) LOOP
                v_slot := v_slot + 1;
                v_goal_number := v_tier_offset + v_slot;
                IF v_goal_number > v_tier_offset + v_universal_count + v_archetype_count THEN
                    EXIT;
                END IF;
                INSERT INTO user_olympian_assignments
                    (user_id, season_year, achievement_id, goal_number, goal_tier, archetype)
                VALUES
                    (current_user_uuid, p_year, r.id, v_goal_number, v_tier, v_archetype)
                ON CONFLICT (user_id, season_year, achievement_id) DO NOTHING;
            END LOOP;

            -- Backfill any tier 5 universal-eligible if archetype pool came up short
            IF v_tier = 5 THEN
                DECLARE
                    v_have INT;
                    v_need INT;
                BEGIN
                    SELECT COUNT(*) INTO v_have FROM user_olympian_assignments
                    WHERE user_id = current_user_uuid AND season_year = p_year AND goal_tier = 5;
                    -- Tier 5 holds 4 stretch slots + meta = 5 total; we'll insert meta separately.
                    v_need := 4 - v_have;
                    IF v_need > 0 THEN
                        FOR r IN (
                            SELECT id
                            FROM achievements
                            WHERE category = 'olympian_path'
                              AND season_year = p_year
                              AND goal_tier = 5
                              AND id <> v_meta_id
                              AND id NOT IN (
                                  SELECT achievement_id FROM user_olympian_assignments
                                  WHERE user_id = current_user_uuid AND season_year = p_year
                              )
                            ORDER BY threshold ASC, key ASC
                            LIMIT v_need
                        ) LOOP
                            v_have := v_have + 1;
                            INSERT INTO user_olympian_assignments
                                (user_id, season_year, achievement_id, goal_number, goal_tier, archetype)
                            VALUES
                                (current_user_uuid, p_year, r.id, 28 + v_have, 5, v_archetype)
                            ON CONFLICT (user_id, season_year, achievement_id) DO NOTHING;
                        END LOOP;
                    END IF;
                END;
            END IF;
        END;
    END LOOP;

    -- Always assign meta as #33
    INSERT INTO user_olympian_assignments
        (user_id, season_year, achievement_id, goal_number, goal_tier, archetype)
    VALUES
        (current_user_uuid, p_year, v_meta_id, 33, 5, v_archetype)
    ON CONFLICT (user_id, season_year, achievement_id) DO NOTHING;

    -- Final shape check — fail loud if anything came up short
    SELECT COUNT(*) INTO v_existing_count
    FROM user_olympian_assignments
    WHERE user_id = current_user_uuid AND season_year = p_year;

    IF v_existing_count <> 33 THEN
        RAISE EXCEPTION 'Olympian assignment short: got % rows, expected 33 (archetype=%, year=%)',
            v_existing_count, v_archetype, p_year;
    END IF;

    SELECT jsonb_agg(jsonb_build_object(
        'goal_number', goal_number,
        'goal_tier', goal_tier,
        'achievement_id', achievement_id,
        'achievement_key', a.key,
        'archetype', archetype
    ) ORDER BY goal_number)
    INTO v_assignments
    FROM user_olympian_assignments uoa
    JOIN achievements a ON a.id = uoa.achievement_id
    WHERE uoa.user_id = current_user_uuid AND uoa.season_year = p_year;

    RETURN jsonb_build_object(
        'created', true,
        'archetype', v_archetype,
        'assignments', v_assignments
    );
END;
$$;

GRANT EXECUTE ON FUNCTION assign_olympian_path(INT, TEXT) TO authenticated;

-- ============================================================================
-- 5. COMPLETE OLYMPIAN SEASON IF DONE
-- ============================================================================

DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN (
        SELECT n.nspname, p.proname, oidvectortypes(p.proargtypes) AS args
          FROM pg_proc p
          JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname = 'public'
           AND p.proname = 'complete_olympian_season_if_done'
    ) LOOP
        EXECUTE format('DROP FUNCTION IF EXISTS %I.%I(%s)', r.nspname, r.proname, r.args);
    END LOOP;
END$$;

CREATE FUNCTION complete_olympian_season_if_done(p_year INT)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    current_user_uuid UUID;
    v_unlocked_count INT;
    v_archetype TEXT;
    v_already_completed BOOLEAN;
BEGIN
    current_user_uuid := auth.uid();
    IF current_user_uuid IS NULL THEN
        RETURN jsonb_build_object('completed', false, 'reason', 'unauthenticated');
    END IF;

    -- Already minted? short-circuit
    SELECT EXISTS (
        SELECT 1 FROM user_olympian_seasons
        WHERE user_id = current_user_uuid AND season_year = p_year
    ) INTO v_already_completed;

    IF v_already_completed THEN
        RETURN jsonb_build_object('completed', true, 'newly_minted', false);
    END IF;

    -- Count unlocked olympian goals for this user/year via the assignments join
    SELECT COUNT(*)
    INTO v_unlocked_count
    FROM user_olympian_assignments uoa
    JOIN user_achievements ua
      ON ua.achievement_id = uoa.achievement_id
     AND ua.user_id = uoa.user_id
    WHERE uoa.user_id = current_user_uuid
      AND uoa.season_year = p_year
      AND ua.unlocked_at IS NOT NULL;

    IF v_unlocked_count >= 33 THEN
        SELECT archetype INTO v_archetype
        FROM user_olympian_assignments
        WHERE user_id = current_user_uuid AND season_year = p_year
        LIMIT 1;

        INSERT INTO user_olympian_seasons (user_id, season_year, archetype)
        VALUES (current_user_uuid, p_year, COALESCE(v_archetype, 'general'))
        ON CONFLICT (user_id, season_year) DO NOTHING;

        RETURN jsonb_build_object(
            'completed', true,
            'newly_minted', true,
            'archetype', v_archetype,
            'season_year', p_year
        );
    END IF;

    RETURN jsonb_build_object(
        'completed', false,
        'unlocked_count', v_unlocked_count,
        'total', 33
    );
END;
$$;

GRANT EXECUTE ON FUNCTION complete_olympian_season_if_done(INT) TO authenticated;

-- ============================================================================
-- 6. PATCH unlock_achievement TO TAIL-CALL complete_olympian_season_if_done
-- ============================================================================
--
-- We re-create the existing RPC (signature unchanged, return shape unchanged)
-- with one added side effect: if the achievement that was just unlocked has
-- season_year IS NOT NULL, call complete_olympian_season_if_done at the tail.
-- The recursive call is bounded (1 hop) and idempotent.

DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN (
        SELECT n.nspname, p.proname, oidvectortypes(p.proargtypes) AS args
          FROM pg_proc p
          JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname = 'public'
           AND p.proname = 'unlock_achievement'
    ) LOOP
        EXECUTE format('DROP FUNCTION IF EXISTS %I.%I(%s)', r.nspname, r.proname, r.args);
    END LOOP;
END$$;

CREATE FUNCTION unlock_achievement(p_achievement_key TEXT, p_progress INT DEFAULT 1)
RETURNS TABLE (
    unlocked BOOLEAN,
    achievement_title TEXT,
    achievement_icon TEXT,
    achievement_rarity TEXT,
    xp_reward INT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    current_user_uuid UUID;
    v_achievement RECORD;
    v_user_achievement RECORD;
    new_progress INT;
    v_just_unlocked BOOLEAN := FALSE;
BEGIN
    current_user_uuid := auth.uid();
    IF current_user_uuid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    SELECT * INTO v_achievement FROM achievements WHERE key = p_achievement_key;
    IF NOT FOUND THEN
        unlocked := FALSE;
        RETURN NEXT;
        RETURN;
    END IF;

    INSERT INTO user_achievements (user_id, achievement_id, progress)
    VALUES (current_user_uuid, v_achievement.id, p_progress)
    ON CONFLICT (user_id, achievement_id) DO UPDATE
        SET progress = GREATEST(user_achievements.progress, EXCLUDED.progress)
    RETURNING * INTO v_user_achievement;

    new_progress := v_user_achievement.progress;

    IF new_progress >= v_achievement.threshold AND v_user_achievement.unlocked_at IS NULL THEN
        UPDATE user_achievements
        SET unlocked_at = NOW()
        WHERE id = v_user_achievement.id;

        IF v_achievement.xp_reward > 0 THEN
            UPDATE user_profiles
            SET xp = COALESCE(xp, 0) + v_achievement.xp_reward
            WHERE id = current_user_uuid;
        END IF;

        v_just_unlocked := TRUE;

        unlocked := TRUE;
        achievement_title := v_achievement.title;
        achievement_icon := v_achievement.icon;
        achievement_rarity := v_achievement.rarity;
        xp_reward := v_achievement.xp_reward;
        RETURN NEXT;
    ELSE
        unlocked := FALSE;
        achievement_title := v_achievement.title;
        achievement_icon := v_achievement.icon;
        achievement_rarity := v_achievement.rarity;
        xp_reward := 0;
        RETURN NEXT;
    END IF;

    -- Tail call: only when an olympian goal just unlocked, mint the season badge
    -- if all 33 are now unlocked. PERFORM swallows the JSON result; client refreshes
    -- via OlympianPathService listener.
    IF v_just_unlocked AND v_achievement.season_year IS NOT NULL THEN
        PERFORM complete_olympian_season_if_done(v_achievement.season_year);
    END IF;

    RETURN;
END;
$$;

GRANT EXECUTE ON FUNCTION unlock_achievement(TEXT, INT) TO authenticated;

-- ============================================================================
-- 6b. INCREMENT ACHIEVEMENT PROGRESS (additive — reactions / meals / etc.)
-- ============================================================================
--
-- `unlock_achievement` uses GREATEST() upsert semantics so it expects the
-- caller to know the lifetime total. That works for workouts/streaks/friends
-- (server has counters), but breaks for events the iOS only sees as deltas:
-- reactions sent, meals logged, friend reactions, etc. This RPC does an
-- additive UPSERT — the user_achievements.progress is incremented by p_delta
-- atomically. Otherwise identical to `unlock_achievement` (same RETURNS
-- shape, same olympian-tail-call behavior, same XP reward + auth gating).

DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN (
        SELECT n.nspname, p.proname, oidvectortypes(p.proargtypes) AS args
          FROM pg_proc p
          JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname = 'public'
           AND p.proname = 'increment_achievement_progress'
    ) LOOP
        EXECUTE format('DROP FUNCTION IF EXISTS %I.%I(%s)', r.nspname, r.proname, r.args);
    END LOOP;
END$$;

CREATE FUNCTION increment_achievement_progress(p_achievement_key TEXT, p_delta INT DEFAULT 1)
RETURNS TABLE (
    unlocked BOOLEAN,
    achievement_title TEXT,
    achievement_icon TEXT,
    achievement_rarity TEXT,
    xp_reward INT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    current_user_uuid UUID;
    v_achievement RECORD;
    v_user_achievement RECORD;
    new_progress INT;
    v_just_unlocked BOOLEAN := FALSE;
BEGIN
    current_user_uuid := auth.uid();
    IF current_user_uuid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    IF p_delta <= 0 THEN
        RAISE EXCEPTION 'p_delta must be positive (got %)', p_delta;
    END IF;

    SELECT * INTO v_achievement FROM achievements WHERE key = p_achievement_key;
    IF NOT FOUND THEN
        unlocked := FALSE;
        RETURN NEXT;
        RETURN;
    END IF;

    INSERT INTO user_achievements (user_id, achievement_id, progress)
    VALUES (current_user_uuid, v_achievement.id, p_delta)
    ON CONFLICT (user_id, achievement_id) DO UPDATE
        SET progress = user_achievements.progress + EXCLUDED.progress
    RETURNING * INTO v_user_achievement;

    new_progress := v_user_achievement.progress;

    IF new_progress >= v_achievement.threshold AND v_user_achievement.unlocked_at IS NULL THEN
        UPDATE user_achievements
        SET unlocked_at = NOW()
        WHERE id = v_user_achievement.id;

        IF v_achievement.xp_reward > 0 THEN
            UPDATE user_profiles
            SET xp = COALESCE(xp, 0) + v_achievement.xp_reward
            WHERE id = current_user_uuid;
        END IF;

        v_just_unlocked := TRUE;

        unlocked := TRUE;
        achievement_title := v_achievement.title;
        achievement_icon := v_achievement.icon;
        achievement_rarity := v_achievement.rarity;
        xp_reward := v_achievement.xp_reward;
        RETURN NEXT;
    ELSE
        unlocked := FALSE;
        achievement_title := v_achievement.title;
        achievement_icon := v_achievement.icon;
        achievement_rarity := v_achievement.rarity;
        xp_reward := 0;
        RETURN NEXT;
    END IF;

    -- Tail call: olympian season completion check
    IF v_just_unlocked AND v_achievement.season_year IS NOT NULL THEN
        PERFORM complete_olympian_season_if_done(v_achievement.season_year);
    END IF;

    RETURN;
END;
$$;

GRANT EXECUTE ON FUNCTION increment_achievement_progress(TEXT, INT) TO authenticated;

-- ============================================================================
-- 7. PATCH delete_user_account TO COVER NEW TABLES
-- ============================================================================
--
-- Reuse the canonical signature from supabase/complete_account_deletion.sql.
-- Adds two cleanup steps for the new olympian tables. Trigger
-- delete_auth_user_on_profile_delete already cascades user_profiles → auth.users
-- so we don't re-add that body; we only widen the explicit deletes with the
-- new tables. ON DELETE CASCADE on user_olympian_* FKs to user_profiles makes
-- this defense-in-depth (matches the existing pattern in friendships).

CREATE OR REPLACE FUNCTION delete_user_account(user_id_to_delete UUID)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  friendships_deleted INTEGER := 0;
  friend_requests_deleted INTEGER := 0;
  contacts_deleted INTEGER := 0;
  workouts_deleted INTEGER := 0;
  push_tokens_deleted INTEGER := 0;
  notifications_deleted INTEGER := 0;
  olympian_assignments_deleted INTEGER := 0;
  olympian_seasons_deleted INTEGER := 0;
  result jsonb;
BEGIN
  DELETE FROM friendships
  WHERE requester_id = user_id_to_delete OR addressee_id = user_id_to_delete;
  GET DIAGNOSTICS friendships_deleted = ROW_COUNT;

  IF EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'friend_requests') THEN
    DELETE FROM friend_requests
    WHERE from_user_id = user_id_to_delete OR to_user_id = user_id_to_delete;
    GET DIAGNOSTICS friend_requests_deleted = ROW_COUNT;
  END IF;

  IF EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'user_contacts') THEN
    DELETE FROM user_contacts WHERE user_id = user_id_to_delete;
    GET DIAGNOSTICS contacts_deleted = ROW_COUNT;
  END IF;

  IF EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'workouts') THEN
    DELETE FROM workouts WHERE user_id = user_id_to_delete;
    GET DIAGNOSTICS workouts_deleted = ROW_COUNT;
  END IF;

  IF EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'user_push_tokens') THEN
    DELETE FROM user_push_tokens WHERE user_id = user_id_to_delete;
    GET DIAGNOSTICS push_tokens_deleted = ROW_COUNT;
  END IF;

  IF EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'push_notification_queue') THEN
    DELETE FROM push_notification_queue WHERE recipient_user_id = user_id_to_delete;
    GET DIAGNOSTICS notifications_deleted = ROW_COUNT;
  END IF;

  -- Olympian Path tables (defense-in-depth; FKs already cascade on user_profiles delete)
  IF EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'user_olympian_assignments') THEN
    DELETE FROM user_olympian_assignments WHERE user_id = user_id_to_delete;
    GET DIAGNOSTICS olympian_assignments_deleted = ROW_COUNT;
  END IF;

  IF EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'user_olympian_seasons') THEN
    DELETE FROM user_olympian_seasons WHERE user_id = user_id_to_delete;
    GET DIAGNOSTICS olympian_seasons_deleted = ROW_COUNT;
  END IF;

  DELETE FROM user_profiles WHERE id = user_id_to_delete;
  DELETE FROM auth.users WHERE id = user_id_to_delete;

  result := jsonb_build_object(
    'success', true,
    'user_id', user_id_to_delete,
    'deleted', jsonb_build_object(
      'friendships', friendships_deleted,
      'friend_requests', friend_requests_deleted,
      'contacts', contacts_deleted,
      'workouts', workouts_deleted,
      'push_tokens', push_tokens_deleted,
      'notifications', notifications_deleted,
      'olympian_assignments', olympian_assignments_deleted,
      'olympian_seasons', olympian_seasons_deleted
    )
  );

  RAISE NOTICE 'Account deleted: %', result;
  RETURN result;
END;
$$;

GRANT EXECUTE ON FUNCTION delete_user_account(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION delete_user_account(UUID) TO service_role;

-- ============================================================================
-- 8. SEED OLYMPIAN PATH POOL FOR 2026 (~50 rows)
-- ============================================================================
--
-- Naming: olympian_2026_<slug>
-- All rows: category='olympian_path', season_year=2026, free_achievable_in_year=true
-- archetype tags use 'universal' for everyone-pool, otherwise specific archetypes.

INSERT INTO achievements (key, title, description, icon, category, threshold, xp_reward, rarity, sort_order, season_year, goal_tier, applicable_archetypes, free_achievable_in_year) VALUES

-- ─── UNIVERSAL POOL (16 rows) ──────────────────────────────────────────────
-- Tier 1: Foundation (4 universal slots)
('olympian_2026_first_workout',     'First Step',         'Complete your first workout of 2026',                'figure.run',                  'olympian_path', 1,   25,  'common',    1010, 2026, 1, ARRAY['universal'], true),
('olympian_2026_first_meal',        'Fuel Up',            'Log your first meal',                                'fork.knife',                  'olympian_path', 1,   25,  'common',    1020, 2026, 1, ARRAY['universal'], true),
('olympian_2026_first_friend',      'Squad Up',           'Add your first friend',                              'person.2.fill',               'olympian_path', 1,   25,  'common',    1030, 2026, 1, ARRAY['universal'], true),
('olympian_2026_streak_7',          'Week One',           'Maintain a 7-day streak',                            'flame.fill',                  'olympian_path', 7,   50,  'common',    1040, 2026, 1, ARRAY['universal'], true),

-- Tier 2: Habits (3 universal slots)
('olympian_2026_first_pr',          'New Heights',        'Set your first personal record',                     'arrow.up.circle.fill',        'olympian_path', 1,   75,  'common',    2010, 2026, 2, ARRAY['universal'], true),
('olympian_2026_send_challenge',    'Throw Down',         'Send a challenge to a friend',                       'flag.checkered',              'olympian_path', 1,   50,  'common',    2020, 2026, 2, ARRAY['universal'], true),
('olympian_2026_streak_14',         'Two-Week Drive',     'Maintain a 14-day streak',                           'flame.fill',                  'olympian_path', 14,  100, 'uncommon',  2030, 2026, 2, ARRAY['universal'], true),

-- Tier 3: Strength (3 universal slots)
('olympian_2026_react_25',          'Hype Squad',         'Send 25 reactions to friends',                       'hands.clap.fill',             'olympian_path', 25,  100, 'uncommon',  3010, 2026, 3, ARRAY['universal'], true),
('olympian_2026_streak_30',         'Monthly Machine',    'Maintain a 30-day streak',                           'flame.fill',                  'olympian_path', 30,  200, 'uncommon',  3020, 2026, 3, ARRAY['universal'], true),
('olympian_2026_tier_gold',         'Gold Standard',      'Reach Gold tier in the Weekly League',               'trophy.fill',                 'olympian_path', 3,   200, 'rare',      3030, 2026, 3, ARRAY['universal'], true),

-- Tier 4: Mastery (2 universal slots)
('olympian_2026_streak_60',         'Two-Month Titan',    'Maintain a 60-day streak',                           'flame.fill',                  'olympian_path', 60,  400, 'rare',      4010, 2026, 4, ARRAY['universal'], true),
('olympian_2026_won_challenge',     'Champion',           'Win a challenge',                                    'trophy.fill',                 'olympian_path', 1,   200, 'rare',      4020, 2026, 4, ARRAY['universal'], true),

-- Tier 5: Olympian (3 universal stretch + 1 meta)
('olympian_2026_streak_100',        'Unstoppable',        'Maintain a 100-day streak',                          'flame.fill',                  'olympian_path', 100, 1000,'epic',      5010, 2026, 5, ARRAY['universal'], true),
('olympian_2026_workouts_100',      'Centurion',          'Complete 100 workouts',                              'star.fill',                   'olympian_path', 100, 750, 'epic',      5020, 2026, 5, ARRAY['universal'], true),
('olympian_2026_tier_diamond',      'Diamond',            'Reach Diamond tier in the Weekly League',            'diamond.fill',                'olympian_path', 5,   750, 'epic',      5030, 2026, 5, ARRAY['universal'], true),
-- Meta goal — always assigned as #33
('olympian_2026_complete_path',     'Olympian 2026',      'Complete all 32 prior goals',                        'crown.fill',                  'olympian_path', 32,  3300,'legendary', 5999, 2026, 5, ARRAY['universal'], true),

-- ─── STRENGTH POOL (12 rows, tagged {strength, athletic}) ──────────────────
-- Tier 1 (3 needed)
('olympian_2026_str_first_lift',    'First Set',          'Complete your first strength workout',               'dumbbell.fill',               'olympian_path', 1,   25,  'common',    1110, 2026, 1, ARRAY['strength','athletic'], true),
('olympian_2026_str_program_w1',    'Program Primer',     'Finish week 1 of a strength program',                'list.bullet.clipboard.fill',  'olympian_path', 1,   50,  'common',    1120, 2026, 1, ARRAY['strength','athletic'], true),
('olympian_2026_str_workouts_5',    'Habit Forming',      'Complete 5 strength workouts',                       'figure.strengthtraining.traditional','olympian_path',5,50,'common',    1130, 2026, 1, ARRAY['strength','athletic'], true),

-- Tier 2 (4 needed)
('olympian_2026_str_all_muscles',   'Full Body',          'Train all 8 major muscle groups',                    'figure.strengthtraining.traditional','olympian_path',8,200,'uncommon', 2110, 2026, 2, ARRAY['strength','athletic'], true),
('olympian_2026_str_workouts_25',   'Built In',           'Complete 25 strength workouts',                      'dumbbell.fill',               'olympian_path', 25,  150, 'uncommon',  2120, 2026, 2, ARRAY['strength','athletic'], true),
('olympian_2026_str_pr_5',          'Five PRs',           'Set 5 personal records',                             'arrow.up.right.circle.fill',  'olympian_path', 5,   200, 'uncommon',  2130, 2026, 2, ARRAY['strength','athletic'], true),
('olympian_2026_str_react_friend',  'Lift Buddies',       'React to 10 friend workouts',                        'hands.clap.fill',             'olympian_path', 10,  75,  'common',    2140, 2026, 2, ARRAY['strength','athletic'], true),

-- Tier 3 (4 needed)
('olympian_2026_str_workouts_50',   'Heavy Lifter',       'Complete 50 strength workouts',                      'dumbbell.fill',               'olympian_path', 50,  300, 'rare',      3110, 2026, 3, ARRAY['strength','athletic'], true),
('olympian_2026_str_pr_10',         'Ten PRs',            'Set 10 personal records',                            'arrow.up.right.circle.fill',  'olympian_path', 10,  300, 'rare',      3120, 2026, 3, ARRAY['strength','athletic'], true),
('olympian_2026_str_complete_prog', 'Program Finisher',   'Complete a strength program',                        'checkmark.seal.fill',         'olympian_path', 1,   300, 'rare',      3130, 2026, 3, ARRAY['strength','athletic'], true),
('olympian_2026_str_friends_10',    'Iron Network',       'Have 10 friends',                                    'person.3.fill',               'olympian_path', 10,  150, 'uncommon',  3140, 2026, 3, ARRAY['strength','athletic'], true),

-- Tier 4 (5 needed)
('olympian_2026_str_workouts_75',   'Steel Forged',       'Complete 75 strength workouts',                      'dumbbell.fill',               'olympian_path', 75,  500, 'rare',      4110, 2026, 4, ARRAY['strength','athletic'], true),
('olympian_2026_str_pr_20',         'PR Machine',         'Set 20 personal records',                            'arrow.up.right.circle.fill',  'olympian_path', 20,  500, 'epic',      4120, 2026, 4, ARRAY['strength','athletic'], true),
('olympian_2026_str_3_programs',    'Program Trio',       'Complete 3 programs',                                'list.bullet.clipboard.fill',  'olympian_path', 3,   500, 'rare',      4130, 2026, 4, ARRAY['strength','athletic'], true),
('olympian_2026_str_tier_platinum', 'Platinum Push',      'Reach Platinum tier in the Weekly League',           'star.circle.fill',            'olympian_path', 4,   500, 'rare',      4140, 2026, 4, ARRAY['strength','athletic'], true),
('olympian_2026_str_react_50',      'Hype Engine',        'Send 50 reactions to friends',                       'hands.clap.fill',             'olympian_path', 50,  250, 'uncommon',  4150, 2026, 4, ARRAY['strength','athletic'], true),

-- Tier 5 (1 archetype hardest)
('olympian_2026_str_workouts_150',  'Iron Olympian',      'Complete 150 strength workouts',                     'crown.fill',                  'olympian_path', 150, 1000,'legendary', 5110, 2026, 5, ARRAY['strength','athletic'], true),

-- ─── ENDURANCE POOL (12 rows, tagged {endurance, athletic}) ─────────────────
-- Tier 1 (3 needed)
('olympian_2026_end_first_cardio',  'First Mile',         'Log your first cardio session',                      'figure.run',                  'olympian_path', 1,   25,  'common',    1210, 2026, 1, ARRAY['endurance','athletic'], true),
('olympian_2026_end_connect',       'On the Map',         'Connect Strava or HealthKit running',                'externaldrive.connected.to.line.below','olympian_path',1,50,'common',   1220, 2026, 1, ARRAY['endurance','athletic'], true),
('olympian_2026_end_cardio_3',      'Three Down',         'Complete 3 cardio sessions',                         'figure.run',                  'olympian_path', 3,   50,  'common',    1230, 2026, 1, ARRAY['endurance','athletic'], true),

-- Tier 2 (4 needed)
('olympian_2026_end_cardio_10',     'Ten Sessions',       'Complete 10 cardio sessions',                        'figure.run',                  'olympian_path', 10,  150, 'uncommon',  2210, 2026, 2, ARRAY['endurance','athletic'], true),
('olympian_2026_end_distance_25',   'Twenty-Five Strong', 'Cover 25 km of cardio distance',                     'map.fill',                    'olympian_path', 25,  150, 'uncommon',  2220, 2026, 2, ARRAY['endurance','athletic'], true),
('olympian_2026_end_distance_50',   'Half-Century',       'Cover 50 km of cardio distance',                     'map.fill',                    'olympian_path', 50,  200, 'uncommon',  2230, 2026, 2, ARRAY['endurance','athletic'], true),
('olympian_2026_end_react_friend',  'Run Crew',           'React to 10 friend workouts',                        'hands.clap.fill',             'olympian_path', 10,  75,  'common',    2240, 2026, 2, ARRAY['endurance','athletic'], true),

-- Tier 3 (4 needed)
('olympian_2026_end_cardio_25',     'Quarter Hundred',    'Complete 25 cardio sessions',                        'figure.run',                  'olympian_path', 25,  300, 'rare',      3210, 2026, 3, ARRAY['endurance','athletic'], true),
('olympian_2026_end_distance_100',  'Century Club',       'Cover 100 km of cardio distance',                    'map.fill',                    'olympian_path', 100, 300, 'rare',      3220, 2026, 3, ARRAY['endurance','athletic'], true),
('olympian_2026_end_5k',            'First 5K',           'Complete a 5K (single session ≥5 km)',               'figure.run.circle.fill',      'olympian_path', 1,   250, 'rare',      3230, 2026, 3, ARRAY['endurance','athletic'], true),
('olympian_2026_end_friends_10',    'Pace Pack',          'Have 10 friends',                                    'person.3.fill',               'olympian_path', 10,  150, 'uncommon',  3240, 2026, 3, ARRAY['endurance','athletic'], true),

-- Tier 4 (5 needed)
('olympian_2026_end_cardio_50',     'Fifty Down',         'Complete 50 cardio sessions',                        'figure.run',                  'olympian_path', 50,  500, 'rare',      4210, 2026, 4, ARRAY['endurance','athletic'], true),
('olympian_2026_end_distance_200',  'Two Hundred Strong', 'Cover 200 km of cardio distance',                    'map.fill',                    'olympian_path', 200, 500, 'epic',      4220, 2026, 4, ARRAY['endurance','athletic'], true),
('olympian_2026_end_complete_prog', 'Cardio Plan Done',   'Complete a cardio program',                          'checkmark.seal.fill',         'olympian_path', 1,   400, 'rare',      4230, 2026, 4, ARRAY['endurance','athletic'], true),
('olympian_2026_end_tier_platinum', 'Platinum Stride',    'Reach Platinum tier in the Weekly League',           'star.circle.fill',            'olympian_path', 4,   500, 'rare',      4240, 2026, 4, ARRAY['endurance','athletic'], true),
('olympian_2026_end_react_50',      'Cheer Squad',        'Send 50 reactions to friends',                       'hands.clap.fill',             'olympian_path', 50,  250, 'uncommon',  4250, 2026, 4, ARRAY['endurance','athletic'], true),

-- Tier 5 (1 archetype hardest)
('olympian_2026_end_cardio_75',     'Endurance Olympian', 'Complete 75 cardio sessions',                        'crown.fill',                  'olympian_path', 75,  1000,'legendary', 5210, 2026, 5, ARRAY['endurance','athletic'], true),

-- ─── WEIGHT-LOSS POOL (12 rows, tagged {weightLoss, general}) ──────────────
-- Tier 1 (3 needed)
('olympian_2026_wl_log_weight',     'Step on the Scale',  'Log your weight',                                    'scalemass.fill',              'olympian_path', 1,   25,  'common',    1310, 2026, 1, ARRAY['weightLoss','general'], true),
('olympian_2026_wl_macros_first',   'Track One Day',      'Hit your macro target for one day',                  'chart.pie.fill',              'olympian_path', 1,   50,  'common',    1320, 2026, 1, ARRAY['weightLoss','general'], true),
('olympian_2026_wl_meals_5',        'Five Meals',         'Log 5 meals',                                        'fork.knife',                  'olympian_path', 5,   50,  'common',    1330, 2026, 1, ARRAY['weightLoss','general'], true),

-- Tier 2 (4 needed)
('olympian_2026_wl_calorie_7',      'Calorie Week',       'Hit calorie target 7 days',                          'flame.circle',                'olympian_path', 7,   150, 'uncommon',  2310, 2026, 2, ARRAY['weightLoss','general'], true),
('olympian_2026_wl_protein_7',      'Protein Week',       'Hit protein target 7 days',                          'fish.fill',                   'olympian_path', 7,   150, 'uncommon',  2320, 2026, 2, ARRAY['weightLoss','general'], true),
('olympian_2026_wl_meals_30',       'Thirty Meals',       'Log 30 meals',                                       'fork.knife',                  'olympian_path', 30,  150, 'uncommon',  2330, 2026, 2, ARRAY['weightLoss','general'], true),
('olympian_2026_wl_quest_streak_5', 'Daily Drive',        'Complete a daily quest 5 days in a row',             'checklist',                   'olympian_path', 5,   100, 'uncommon',  2340, 2026, 2, ARRAY['weightLoss','general'], true),

-- Tier 3 (4 needed)
('olympian_2026_wl_calorie_21',     'Calorie 21',         'Hit calorie target 21 days',                         'flame.circle',                'olympian_path', 21,  300, 'rare',      3310, 2026, 3, ARRAY['weightLoss','general'], true),
('olympian_2026_wl_protein_21',     'Protein 21',         'Hit protein target 21 days',                         'fish.fill',                   'olympian_path', 21,  300, 'rare',      3320, 2026, 3, ARRAY['weightLoss','general'], true),
('olympian_2026_wl_hydration_21',   'Hydration Habit',    'Hit hydration goal 21 days',                         'drop.fill',                   'olympian_path', 21,  300, 'rare',      3330, 2026, 3, ARRAY['weightLoss','general'], true),
('olympian_2026_wl_meals_50',       'Fifty Meals',        'Log 50 meals',                                       'fork.knife',                  'olympian_path', 50,  300, 'rare',      3340, 2026, 3, ARRAY['weightLoss','general'], true),

-- Tier 4 (5 needed)
('olympian_2026_wl_calorie_30',     'Calorie 30',         'Hit calorie target 30 days',                         'flame.circle',                'olympian_path', 30,  500, 'rare',      4310, 2026, 4, ARRAY['weightLoss','general'], true),
('olympian_2026_wl_protein_30',     'Protein 30',         'Hit protein target 30 days',                         'fish.fill',                   'olympian_path', 30,  500, 'rare',      4320, 2026, 4, ARRAY['weightLoss','general'], true),
('olympian_2026_wl_hydration_60',   'Hydration Veteran',  'Hit hydration goal 60 days',                         'drop.fill',                   'olympian_path', 60,  500, 'epic',      4330, 2026, 4, ARRAY['weightLoss','general'], true),
('olympian_2026_wl_meals_100',      'Hundred Meals',      'Log 100 meals',                                      'fork.knife',                  'olympian_path', 100, 500, 'rare',      4340, 2026, 4, ARRAY['weightLoss','general'], true),
('olympian_2026_wl_3_programs',     'Three Programs',     'Complete 3 programs',                                'list.bullet.clipboard.fill',  'olympian_path', 3,   500, 'rare',      4350, 2026, 4, ARRAY['weightLoss','general'], true),

-- Tier 5 (1 archetype hardest)
('olympian_2026_wl_meals_200',      'Nutrition Olympian', 'Log 200 meals',                                      'crown.fill',                  'olympian_path', 200, 1000,'legendary', 5310, 2026, 5, ARRAY['weightLoss','general'], true),

-- ─── GENERAL-ONLY POOL (3 rows, tagged {general}) ──────────────────────────
-- Slightly different cadence from weightLoss; general path leans on quest engagement.
('olympian_2026_gen_quest_streak_7','Quest Streak 7',     'Complete a daily quest 7 days in a row',             'checklist',                   'olympian_path', 7,   100, 'uncommon',  2410, 2026, 2, ARRAY['general'], true),
('olympian_2026_gen_quest_streak_14','Quest Streak 14',   'Complete a daily quest 14 days in a row',            'checklist',                   'olympian_path', 14,  300, 'rare',      3410, 2026, 3, ARRAY['general'], true),
('olympian_2026_gen_5_programs',    'Program Pentad',     'Complete 5 programs',                                'list.bullet.clipboard.fill',  'olympian_path', 5,   500, 'epic',      4410, 2026, 4, ARRAY['general'], true)

ON CONFLICT (key) DO NOTHING;

-- ============================================================================
-- 9. AUDIT BLOCK: free-achievability gate + pool sanity (fail-loud)
-- ============================================================================

DO $$
DECLARE
    v_total_pool INT;
    v_universal_pool INT;
    v_meta_count INT;
    v_premium_required INT;
    v_min_per_archetype RECORD;
    v_archetype_test TEXT;
    v_tier_test INT;
    v_archetype_pool_count INT;
BEGIN
    -- Total pool size
    SELECT COUNT(*) INTO v_total_pool FROM achievements
    WHERE category = 'olympian_path' AND season_year = 2026;

    SELECT COUNT(*) INTO v_universal_pool FROM achievements
    WHERE category = 'olympian_path' AND season_year = 2026
      AND 'universal' = ANY(applicable_archetypes);

    SELECT COUNT(*) INTO v_meta_count FROM achievements
    WHERE key = 'olympian_2026_complete_path';

    SELECT COUNT(*) INTO v_premium_required FROM achievements
    WHERE category = 'olympian_path' AND season_year = 2026 AND free_achievable_in_year = false;

    IF v_total_pool < 40 THEN
        RAISE EXCEPTION 'Olympian 2026 pool too small: % rows (expected 40+)', v_total_pool;
    END IF;

    IF v_universal_pool < 15 THEN
        RAISE EXCEPTION 'Olympian 2026 universal pool too small: % rows (expected 15+)', v_universal_pool;
    END IF;

    IF v_meta_count <> 1 THEN
        RAISE EXCEPTION 'Olympian 2026 meta goal missing or duplicated: % rows', v_meta_count;
    END IF;

    IF v_premium_required > 0 THEN
        RAISE EXCEPTION 'FREE-ACHIEVABILITY GATE VIOLATED: % goals require premium', v_premium_required;
    END IF;

    -- Per-archetype × per-tier pool minimums (universal + archetype-specific union must satisfy)
    -- Slot allocation: T1=4u+3a, T2=3u+4a, T3=3u+4a, T4=2u+5a, T5=3u-stretch+1a (+meta)
    -- Universal-by-tier counts:
    --   T1=4, T2=3, T3=3, T4=2, T5=4 (incl. meta — so 3 stretch + meta)
    -- Archetype-specific minimums:
    FOREACH v_archetype_test IN ARRAY ARRAY['strength','endurance','weightLoss','general','athletic'] LOOP
        FOR v_tier_test IN 1..5 LOOP
            SELECT COUNT(*) INTO v_archetype_pool_count
            FROM achievements
            WHERE category = 'olympian_path'
              AND season_year = 2026
              AND goal_tier = v_tier_test
              AND v_archetype_test = ANY(applicable_archetypes)
              AND NOT ('universal' = ANY(applicable_archetypes));

            -- Minimum archetype-specific rows we need at each tier
            -- (T1=3, T2=4, T3=4, T4=5, T5=1)
            DECLARE
                v_required INT := CASE v_tier_test
                    WHEN 1 THEN 3
                    WHEN 2 THEN 4
                    WHEN 3 THEN 4
                    WHEN 4 THEN 5
                    WHEN 5 THEN 1
                END;
            BEGIN
                IF v_archetype_pool_count < v_required THEN
                    RAISE WARNING 'Archetype % tier % pool low: % rows (expected %+) — assignment may fall back to universal',
                        v_archetype_test, v_tier_test, v_archetype_pool_count, v_required;
                END IF;
            END;
        END LOOP;
    END LOOP;

    RAISE NOTICE '✅ Olympian 2026 pool seeded: % total (% universal). Free-achievability gate clean.',
        v_total_pool, v_universal_pool;
END $$;

-- ============================================================================
-- 10. POSTGREST SCHEMA RELOAD (Supabase invariant 19b)
-- ============================================================================

NOTIFY pgrst, 'reload schema';

COMMIT;
