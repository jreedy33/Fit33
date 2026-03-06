-- ============================================================================
-- WEEKLY LEAGUES MIGRATION
-- Duolingo-style competitive leagues that reset every Monday
-- Users are grouped into pools of ~30, compete for weekly points,
-- and get promoted/relegated between tiers based on performance.
-- ============================================================================

-- ============================================================================
-- 1. TABLES
-- ============================================================================

-- League tiers (static reference — Bronze through Elite)
CREATE TABLE IF NOT EXISTS league_tiers (
    tier_rank INTEGER PRIMARY KEY,
    name TEXT NOT NULL,
    emoji TEXT NOT NULL,
    color_hex TEXT NOT NULL,
    promotion_count INTEGER DEFAULT 5,
    relegation_count INTEGER DEFAULT 5,
    max_group_size INTEGER DEFAULT 30
);

INSERT INTO league_tiers (tier_rank, name, emoji, color_hex, promotion_count, relegation_count, max_group_size) VALUES
    (1, 'Bronze',   '🥉', '#CD7F32', 5, 0, 30),   -- No relegation from Bronze (bottom tier)
    (2, 'Silver',   '🥈', '#C0C0C0', 5, 5, 30),
    (3, 'Gold',     '🥇', '#FFD700', 5, 5, 30),
    (4, 'Platinum', '💎', '#A8A8C8', 5, 5, 30),
    (5, 'Diamond',  '💠', '#00BFFF', 3, 5, 25),
    (6, 'Elite',    '👑', '#FF6B35', 0, 5, 20)      -- No promotion from Elite (top tier)
ON CONFLICT (tier_rank) DO UPDATE SET
    name = EXCLUDED.name,
    emoji = EXCLUDED.emoji,
    color_hex = EXCLUDED.color_hex,
    promotion_count = EXCLUDED.promotion_count,
    relegation_count = EXCLUDED.relegation_count,
    max_group_size = EXCLUDED.max_group_size;

-- User's persistent league tier (survives between weeks)
CREATE TABLE IF NOT EXISTS user_league_tier (
    user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    current_tier INTEGER DEFAULT 1 REFERENCES league_tiers(tier_rank),
    total_weeks_played INTEGER DEFAULT 0,
    highest_tier_reached INTEGER DEFAULT 1,
    total_promotions INTEGER DEFAULT 0,
    total_relegations INTEGER DEFAULT 0,
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- League groups (a cohort of ~30 users competing in a specific week/tier)
CREATE TABLE IF NOT EXISTS league_groups (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tier_rank INTEGER NOT NULL REFERENCES league_tiers(tier_rank),
    week_start DATE NOT NULL,
    member_count INTEGER DEFAULT 0,
    is_processed BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_league_groups_week_tier
    ON league_groups(week_start, tier_rank);
CREATE INDEX IF NOT EXISTS idx_league_groups_unprocessed
    ON league_groups(week_start) WHERE NOT is_processed;

-- League members (a user's membership in a specific group/week)
CREATE TABLE IF NOT EXISTS league_members (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    group_id UUID NOT NULL REFERENCES league_groups(id) ON DELETE CASCADE,
    points INTEGER DEFAULT 0,
    workouts_completed INTEGER DEFAULT 0,
    joined_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(user_id, group_id)
);

CREATE INDEX IF NOT EXISTS idx_league_members_user
    ON league_members(user_id);
CREATE INDEX IF NOT EXISTS idx_league_members_group_points
    ON league_members(group_id, points DESC);

-- League history (archived weekly results for each user)
CREATE TABLE IF NOT EXISTS league_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    week_start DATE NOT NULL,
    tier_name TEXT NOT NULL,
    tier_rank INTEGER NOT NULL,
    final_rank INTEGER NOT NULL,
    final_points INTEGER NOT NULL,
    group_size INTEGER NOT NULL,
    was_promoted BOOLEAN DEFAULT FALSE,
    was_relegated BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_league_history_user_week
    ON league_history(user_id, week_start DESC);

-- ============================================================================
-- 2. HELPER FUNCTIONS
-- ============================================================================

-- Get the Monday of the current ISO week
CREATE OR REPLACE FUNCTION get_current_week_monday()
RETURNS DATE
LANGUAGE sql STABLE
AS $$
    SELECT date_trunc('week', CURRENT_DATE)::date;
$$;

-- ============================================================================
-- 3. CORE RPC FUNCTIONS
-- ============================================================================

-- Process all unprocessed league weeks (promotions/relegations)
-- Safe to call multiple times (idempotent — skips already-processed groups)
CREATE OR REPLACE FUNCTION process_past_league_weeks()
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_current_week DATE;
    v_group RECORD;
    v_member RECORD;
    v_group_size INTEGER;
    v_tier_info RECORD;
    v_promoted BOOLEAN;
    v_relegated BOOLEAN;
    v_new_tier INTEGER;
    v_processed_count INTEGER := 0;
BEGIN
    v_current_week := get_current_week_monday();

    -- Loop through every unprocessed group from past weeks
    FOR v_group IN
        SELECT lg.id, lg.tier_rank, lg.week_start, lg.member_count,
               lt.promotion_count, lt.relegation_count, lt.name as tier_name
        FROM league_groups lg
        JOIN league_tiers lt ON lt.tier_rank = lg.tier_rank
        WHERE lg.week_start < v_current_week
          AND NOT lg.is_processed
        ORDER BY lg.week_start ASC
    LOOP
        v_group_size := v_group.member_count;

        -- Skip tiny groups (not meaningful to rank)
        IF v_group_size < 2 THEN
            UPDATE league_groups SET is_processed = TRUE WHERE id = v_group.id;
            CONTINUE;
        END IF;

        -- Rank all members and apply promotions/relegations
        FOR v_member IN
            SELECT user_id, points,
                   ROW_NUMBER() OVER (ORDER BY points DESC, joined_at ASC) as final_rank
            FROM league_members
            WHERE group_id = v_group.id
        LOOP
            v_promoted := FALSE;
            v_relegated := FALSE;
            v_new_tier := v_group.tier_rank;

            -- Promotion: top N (if not at max tier 6)
            IF v_member.final_rank <= v_group.promotion_count AND v_group.tier_rank < 6 THEN
                v_promoted := TRUE;
                v_new_tier := v_group.tier_rank + 1;
            END IF;

            -- Relegation: bottom N (if not at min tier 1)
            IF v_member.final_rank > (v_group_size - v_group.relegation_count)
               AND v_group.tier_rank > 1 THEN
                v_relegated := TRUE;
                v_new_tier := v_group.tier_rank - 1;
            END IF;

            -- Archive result
            INSERT INTO league_history
                (user_id, week_start, tier_name, tier_rank, final_rank,
                 final_points, group_size, was_promoted, was_relegated)
            VALUES
                (v_member.user_id, v_group.week_start, v_group.tier_name,
                 v_group.tier_rank, v_member.final_rank, v_member.points,
                 v_group_size, v_promoted, v_relegated);

            -- Update user's persistent tier
            UPDATE user_league_tier
            SET current_tier = v_new_tier,
                total_weeks_played = total_weeks_played + 1,
                highest_tier_reached = GREATEST(highest_tier_reached, v_new_tier),
                total_promotions = total_promotions + CASE WHEN v_promoted THEN 1 ELSE 0 END,
                total_relegations = total_relegations + CASE WHEN v_relegated THEN 1 ELSE 0 END,
                updated_at = now()
            WHERE user_id = v_member.user_id;
        END LOOP;

        -- Mark group done
        UPDATE league_groups SET is_processed = TRUE WHERE id = v_group.id;
        v_processed_count := v_processed_count + 1;
    END LOOP;

    RETURN json_build_object(
        'success', true,
        'groups_processed', v_processed_count
    );
END;
$$;

-- Main entry point: get or create the user's league membership for this week
-- Also lazily processes any past unprocessed weeks first
CREATE OR REPLACE FUNCTION get_or_join_weekly_league(p_user_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_week_start DATE;
    v_user_tier INTEGER;
    v_group_id UUID;
    v_membership_id UUID;
    v_tier_info RECORD;
    v_days_remaining INTEGER;
    v_result JSON;
BEGIN
    -- Step 0: Lazily process any past unprocessed weeks
    PERFORM process_past_league_weeks();

    -- Step 1: Current week
    v_week_start := get_current_week_monday();
    v_days_remaining := 6 - (CURRENT_DATE - v_week_start);
    IF v_days_remaining < 0 THEN v_days_remaining := 0; END IF;

    -- Step 2: Ensure user has a tier record (default Bronze)
    INSERT INTO user_league_tier (user_id, current_tier)
    VALUES (p_user_id, 1)
    ON CONFLICT (user_id) DO NOTHING;

    SELECT current_tier INTO v_user_tier
    FROM user_league_tier WHERE user_id = p_user_id;

    -- Step 3: Check if user already has a membership this week
    SELECT lm.id, lm.group_id
    INTO v_membership_id, v_group_id
    FROM league_members lm
    JOIN league_groups lg ON lg.id = lm.group_id
    WHERE lm.user_id = p_user_id
      AND lg.week_start = v_week_start;

    -- Step 4: If no membership, find or create a group and join
    IF v_membership_id IS NULL THEN
        -- Find an existing group with space
        SELECT id INTO v_group_id
        FROM league_groups
        WHERE tier_rank = v_user_tier
          AND week_start = v_week_start
          AND member_count < (SELECT max_group_size FROM league_tiers WHERE tier_rank = v_user_tier)
          AND NOT is_processed
        ORDER BY member_count DESC   -- fill fuller groups first for better competition
        LIMIT 1
        FOR UPDATE SKIP LOCKED;

        -- No open group → create one
        IF v_group_id IS NULL THEN
            INSERT INTO league_groups (tier_rank, week_start, member_count)
            VALUES (v_user_tier, v_week_start, 0)
            RETURNING id INTO v_group_id;
        END IF;

        -- Join the group
        INSERT INTO league_members (user_id, group_id, points)
        VALUES (p_user_id, v_group_id, 0)
        ON CONFLICT (user_id, group_id) DO NOTHING;

        UPDATE league_groups
        SET member_count = member_count + 1
        WHERE id = v_group_id;
    END IF;

    -- Step 5: Get tier metadata
    SELECT * INTO v_tier_info FROM league_tiers WHERE tier_rank = v_user_tier;

    -- Step 6: Build response with full leaderboard
    SELECT json_build_object(
        'group_id', v_group_id,
        'tier_rank', v_user_tier,
        'tier_name', v_tier_info.name,
        'tier_emoji', v_tier_info.emoji,
        'tier_color', v_tier_info.color_hex,
        'promotion_count', v_tier_info.promotion_count,
        'relegation_count', v_tier_info.relegation_count,
        'week_start', v_week_start,
        'days_remaining', v_days_remaining,
        'my_points', COALESCE(
            (SELECT points FROM league_members
             WHERE user_id = p_user_id AND group_id = v_group_id), 0),
        'my_rank', COALESCE((
            SELECT rk FROM (
                SELECT user_id,
                       ROW_NUMBER() OVER (ORDER BY points DESC, joined_at ASC) AS rk
                FROM league_members WHERE group_id = v_group_id
            ) sub WHERE user_id = p_user_id
        ), 1),
        'group_size', (SELECT member_count FROM league_groups WHERE id = v_group_id),
        'leaderboard', COALESCE((
            SELECT json_agg(row_to_json(sub) ORDER BY sub.rank)
            FROM (
                SELECT
                    lm.user_id,
                    up.name,
                    up.username,
                    up.profile_photo_url,
                    lm.points,
                    lm.workouts_completed,
                    ROW_NUMBER() OVER (ORDER BY lm.points DESC, lm.joined_at ASC) AS rank,
                    (lm.user_id = p_user_id) AS is_current_user
                FROM league_members lm
                LEFT JOIN user_profiles up ON up.id = lm.user_id
                WHERE lm.group_id = v_group_id
            ) sub
        ), '[]'::json)
    ) INTO v_result;

    RETURN v_result;
END;
$$;

-- Add league points for a user (called after workouts, challenges, etc.)
CREATE OR REPLACE FUNCTION add_league_points(
    p_user_id UUID,
    p_points INTEGER,
    p_source TEXT DEFAULT 'workout'
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_week_start DATE;
    v_group_id UUID;
    v_new_points INTEGER;
BEGIN
    v_week_start := get_current_week_monday();

    -- Find user's current-week membership
    SELECT lm.group_id INTO v_group_id
    FROM league_members lm
    JOIN league_groups lg ON lg.id = lm.group_id
    WHERE lm.user_id = p_user_id
      AND lg.week_start = v_week_start;

    IF v_group_id IS NULL THEN
        RETURN json_build_object('success', false, 'reason', 'no_membership');
    END IF;

    -- Add points
    UPDATE league_members
    SET points = points + p_points,
        workouts_completed = CASE
            WHEN p_source = 'workout' THEN workouts_completed + 1
            ELSE workouts_completed
        END
    WHERE user_id = p_user_id AND group_id = v_group_id
    RETURNING points INTO v_new_points;

    RETURN json_build_object(
        'success', true,
        'new_points', v_new_points,
        'points_added', p_points,
        'source', p_source
    );
END;
$$;

-- Get full leaderboard for a specific group
CREATE OR REPLACE FUNCTION get_league_leaderboard(p_user_id UUID, p_group_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER STABLE
AS $$
DECLARE
    v_group RECORD;
    v_tier_info RECORD;
    v_days_remaining INTEGER;
    v_result JSON;
BEGIN
    SELECT * INTO v_group FROM league_groups WHERE id = p_group_id;
    IF v_group IS NULL THEN
        RETURN json_build_object('error', 'group_not_found');
    END IF;

    SELECT * INTO v_tier_info FROM league_tiers WHERE tier_rank = v_group.tier_rank;

    v_days_remaining := 6 - (CURRENT_DATE - v_group.week_start);
    IF v_days_remaining < 0 THEN v_days_remaining := 0; END IF;

    SELECT json_build_object(
        'group_id', v_group.id,
        'tier_rank', v_group.tier_rank,
        'tier_name', v_tier_info.name,
        'tier_emoji', v_tier_info.emoji,
        'tier_color', v_tier_info.color_hex,
        'promotion_count', v_tier_info.promotion_count,
        'relegation_count', v_tier_info.relegation_count,
        'week_start', v_group.week_start,
        'days_remaining', v_days_remaining,
        'group_size', v_group.member_count,
        'my_points', COALESCE(
            (SELECT points FROM league_members
             WHERE user_id = p_user_id AND group_id = p_group_id), 0),
        'my_rank', COALESCE((
            SELECT rk FROM (
                SELECT user_id,
                       ROW_NUMBER() OVER (ORDER BY points DESC, joined_at ASC) AS rk
                FROM league_members WHERE group_id = p_group_id
            ) sub WHERE user_id = p_user_id
        ), 1),
        'leaderboard', COALESCE((
            SELECT json_agg(row_to_json(sub) ORDER BY sub.rank)
            FROM (
                SELECT
                    lm.user_id,
                    up.name,
                    up.username,
                    up.profile_photo_url,
                    lm.points,
                    lm.workouts_completed,
                    ROW_NUMBER() OVER (ORDER BY lm.points DESC, lm.joined_at ASC) AS rank,
                    (lm.user_id = p_user_id) AS is_current_user
                FROM league_members lm
                LEFT JOIN user_profiles up ON up.id = lm.user_id
                WHERE lm.group_id = p_group_id
            ) sub
        ), '[]'::json)
    ) INTO v_result;

    RETURN v_result;
END;
$$;

-- Get a user's league history
CREATE OR REPLACE FUNCTION get_league_history(p_user_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER STABLE
AS $$
BEGIN
    RETURN COALESCE((
        SELECT json_agg(json_build_object(
            'week_start', week_start,
            'tier_name', tier_name,
            'tier_rank', tier_rank,
            'final_rank', final_rank,
            'final_points', final_points,
            'group_size', group_size,
            'was_promoted', was_promoted,
            'was_relegated', was_relegated
        ) ORDER BY week_start DESC)
        FROM league_history
        WHERE user_id = p_user_id
    ), '[]'::json);
END;
$$;

-- ============================================================================
-- 4. ROW LEVEL SECURITY
-- ============================================================================

ALTER TABLE league_tiers ENABLE ROW LEVEL SECURITY;
ALTER TABLE league_groups ENABLE ROW LEVEL SECURITY;
ALTER TABLE league_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE league_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_league_tier ENABLE ROW LEVEL SECURITY;

-- league_tiers: readable by everyone
DROP POLICY IF EXISTS "Anyone can read league tiers" ON league_tiers;
CREATE POLICY "Anyone can read league tiers" ON league_tiers
    FOR SELECT USING (true);

-- league_groups: readable if user is a member of the group
DROP POLICY IF EXISTS "Read groups user belongs to" ON league_groups;
CREATE POLICY "Read groups user belongs to" ON league_groups
    FOR SELECT USING (
        id IN (SELECT group_id FROM league_members WHERE user_id = auth.uid())
    );

-- league_members: readable if same group as user
DROP POLICY IF EXISTS "Read members in same group" ON league_members;
CREATE POLICY "Read members in same group" ON league_members
    FOR SELECT USING (
        group_id IN (SELECT group_id FROM league_members WHERE user_id = auth.uid())
    );

-- league_history: own rows only
DROP POLICY IF EXISTS "Read own league history" ON league_history;
CREATE POLICY "Read own league history" ON league_history
    FOR SELECT USING (user_id = auth.uid());

-- user_league_tier: own row only
DROP POLICY IF EXISTS "Read own league tier" ON user_league_tier;
CREATE POLICY "Read own league tier" ON user_league_tier
    FOR SELECT USING (user_id = auth.uid());

-- ============================================================================
-- 5. POINT VALUES REFERENCE (for documentation — enforced in app code)
-- ============================================================================
-- Complete a workout:        +50 pts
-- Hit challenge daily target: +25 pts
-- Personal record (PR):      +30 pts
-- Log a meal:                 +10 pts
-- Daily app open (1x/day):   +5 pts
-- ============================================================================

-- Done! Run get_or_join_weekly_league(user_id) to join a user into the league.
-- Points are added via add_league_points(user_id, points, source).
-- Past weeks are automatically processed (promotions/relegations) on next join.
