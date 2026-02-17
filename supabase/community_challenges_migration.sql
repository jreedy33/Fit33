-- ============================================================================
-- COMMUNITY CHALLENGES MIGRATION
-- ============================================================================
-- Adds the "Community Challenge" system — open challenges anyone can join,
-- with real-time leaderboards, shareable invite links, and unlimited participants.
--
-- TABLES CREATED:
--   1. community_challenges        — the challenge definition
--   2. community_challenge_participants — who has joined
--   (daily progress reuses existing challenge_daily_progress with a flag)
--
-- RPC FUNCTIONS CREATED:
--   1. create_community_challenge  — creator makes a public challenge
--   2. join_community_challenge    — anyone joins via code/slug
--   3. leave_community_challenge   — participant opts out
--   4. log_community_challenge_progress — daily progress upsert
--   5. get_community_challenge_leaderboard — top N + my rank
--   6. get_my_community_challenges — challenges I've joined
--   7. get_featured_community_challenges — discover popular challenges
--   8. get_community_challenge_by_code — lookup by join code or slug
-- ============================================================================

-- ============================================================================
-- TABLE 1: community_challenges
-- ============================================================================
CREATE TABLE IF NOT EXISTS community_challenges (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    created_by      UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
    
    -- Challenge definition
    challenge_type  TEXT NOT NULL DEFAULT 'steps',  -- steps, walk, run, lift, hydrate, calories, protein, active_minutes, workout_streak, sleep
    title           TEXT NOT NULL,
    description     TEXT,
    emoji           TEXT DEFAULT '🌍',
    
    -- Targets
    daily_target    INT NOT NULL,
    target_unit     TEXT NOT NULL DEFAULT 'steps',
    
    -- Joining / sharing
    join_code       TEXT NOT NULL UNIQUE,            -- 6-char uppercase alphanumeric (e.g. "FIT33X")
    invite_slug     TEXT NOT NULL UNIQUE,            -- URL-friendly slug (e.g. "10k-steps-daily")
    
    -- Timing
    is_recurring    BOOLEAN NOT NULL DEFAULT TRUE,   -- TRUE = ongoing (daily reset), FALSE = has end date
    start_date      DATE NOT NULL DEFAULT CURRENT_DATE,
    end_date        DATE,                            -- NULL = open-ended / recurring
    
    -- Limits
    max_participants INT,                            -- NULL = unlimited
    
    -- Visibility & Discovery
    visibility      TEXT NOT NULL DEFAULT 'public',  -- 'public', 'unlisted' (link-only), 'local'
    is_featured     BOOLEAN NOT NULL DEFAULT FALSE,  -- Admin-curated featured challenges
    is_official     BOOLEAN NOT NULL DEFAULT FALSE,  -- Created by Fit33 team
    category        TEXT DEFAULT 'fitness',           -- fitness, nutrition, wellness, social
    
    -- Stats (denormalized for fast queries)
    participant_count INT NOT NULL DEFAULT 0,
    total_completions INT NOT NULL DEFAULT 0,        -- how many daily targets hit across all participants
    
    -- Metadata
    status          TEXT NOT NULL DEFAULT 'active',  -- active, paused, ended, cancelled
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Indexes for fast lookups
CREATE INDEX IF NOT EXISTS idx_community_challenges_join_code ON community_challenges(join_code);
CREATE INDEX IF NOT EXISTS idx_community_challenges_invite_slug ON community_challenges(invite_slug);
CREATE INDEX IF NOT EXISTS idx_community_challenges_status ON community_challenges(status);
CREATE INDEX IF NOT EXISTS idx_community_challenges_visibility ON community_challenges(visibility, status);
CREATE INDEX IF NOT EXISTS idx_community_challenges_featured ON community_challenges(is_featured, status) WHERE is_featured = TRUE;
CREATE INDEX IF NOT EXISTS idx_community_challenges_type ON community_challenges(challenge_type, status);
CREATE INDEX IF NOT EXISTS idx_community_challenges_created_by ON community_challenges(created_by);
CREATE INDEX IF NOT EXISTS idx_community_challenges_participant_count ON community_challenges(participant_count DESC);

-- ============================================================================
-- TABLE 2: community_challenge_participants
-- ============================================================================
CREATE TABLE IF NOT EXISTS community_challenge_participants (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    challenge_id    UUID NOT NULL REFERENCES community_challenges(id) ON DELETE CASCADE,
    user_id         UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
    
    -- Progress aggregates (updated on each log)
    total_progress  INT NOT NULL DEFAULT 0,
    days_completed  INT NOT NULL DEFAULT 0,          -- days where daily_target was met
    current_streak  INT NOT NULL DEFAULT 0,
    best_streak     INT NOT NULL DEFAULT 0,
    today_progress  INT NOT NULL DEFAULT 0,          -- denormalized for leaderboard speed
    
    -- Participation metadata
    joined_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_active_at  TIMESTAMPTZ DEFAULT NOW(),
    is_active       BOOLEAN NOT NULL DEFAULT TRUE,   -- FALSE = left the challenge
    
    -- Referral tracking (who invited this person)
    referred_by     UUID REFERENCES user_profiles(id),
    
    UNIQUE(challenge_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_ccp_challenge_user ON community_challenge_participants(challenge_id, user_id);
CREATE INDEX IF NOT EXISTS idx_ccp_challenge_active ON community_challenge_participants(challenge_id, is_active);
CREATE INDEX IF NOT EXISTS idx_ccp_challenge_leaderboard ON community_challenge_participants(challenge_id, today_progress DESC) WHERE is_active = TRUE;
CREATE INDEX IF NOT EXISTS idx_ccp_user_active ON community_challenge_participants(user_id, is_active);

-- ============================================================================
-- TABLE 3: community_challenge_daily_progress
-- ============================================================================
CREATE TABLE IF NOT EXISTS community_challenge_daily_progress (
    challenge_id    UUID NOT NULL REFERENCES community_challenges(id) ON DELETE CASCADE,
    user_id         UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
    progress_date   DATE NOT NULL,
    progress_value  INT NOT NULL DEFAULT 0,
    target_hit      BOOLEAN NOT NULL DEFAULT FALSE,
    source          TEXT NOT NULL DEFAULT 'auto_sync',
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    
    PRIMARY KEY (challenge_id, user_id, progress_date)
);

CREATE INDEX IF NOT EXISTS idx_ccdp_date ON community_challenge_daily_progress(challenge_id, progress_date);
CREATE INDEX IF NOT EXISTS idx_ccdp_user ON community_challenge_daily_progress(user_id, progress_date);

-- ============================================================================
-- HELPER: Generate unique join code
-- ============================================================================
CREATE OR REPLACE FUNCTION generate_join_code()
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
    chars TEXT := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; -- No I/O/0/1 to avoid confusion
    code TEXT := '';
    i INT;
BEGIN
    FOR i IN 1..6 LOOP
        code := code || substr(chars, floor(random() * length(chars) + 1)::INT, 1);
    END LOOP;
    RETURN code;
END;
$$;

-- ============================================================================
-- HELPER: Generate URL-friendly slug from title
-- ============================================================================
CREATE OR REPLACE FUNCTION generate_challenge_slug(p_title TEXT)
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
    base_slug TEXT;
    final_slug TEXT;
    counter INT := 0;
BEGIN
    -- Convert to lowercase, replace non-alphanumeric with hyphens, trim
    base_slug := lower(regexp_replace(p_title, '[^a-zA-Z0-9]+', '-', 'g'));
    base_slug := trim(both '-' from base_slug);
    -- Truncate to 50 chars
    base_slug := left(base_slug, 50);
    
    final_slug := base_slug;
    
    -- Ensure uniqueness
    WHILE EXISTS (SELECT 1 FROM community_challenges WHERE invite_slug = final_slug) LOOP
        counter := counter + 1;
        final_slug := base_slug || '-' || counter;
    END LOOP;
    
    RETURN final_slug;
END;
$$;


-- ============================================================================
-- RPC 1: create_community_challenge
-- ============================================================================
CREATE OR REPLACE FUNCTION create_community_challenge(
    p_challenge_type TEXT,
    p_title TEXT,
    p_description TEXT DEFAULT NULL,
    p_emoji TEXT DEFAULT '🌍',
    p_daily_target INT DEFAULT 10000,
    p_target_unit TEXT DEFAULT 'steps',
    p_is_recurring BOOLEAN DEFAULT TRUE,
    p_end_date TEXT DEFAULT NULL,
    p_max_participants INT DEFAULT NULL,
    p_visibility TEXT DEFAULT 'public',
    p_category TEXT DEFAULT 'fitness'
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    current_user_uuid UUID;
    new_id UUID;
    v_join_code TEXT;
    v_slug TEXT;
    v_end_date DATE;
BEGIN
    current_user_uuid := auth.uid();
    IF current_user_uuid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    -- Generate unique join code (retry if collision)
    LOOP
        v_join_code := generate_join_code();
        EXIT WHEN NOT EXISTS (SELECT 1 FROM community_challenges WHERE join_code = v_join_code);
    END LOOP;

    -- Generate slug
    v_slug := generate_challenge_slug(p_title);

    -- Parse end date
    IF p_end_date IS NOT NULL AND p_end_date != '' THEN
        v_end_date := p_end_date::DATE;
    ELSE
        v_end_date := NULL;
    END IF;

    -- Insert the community challenge
    INSERT INTO community_challenges (
        created_by, challenge_type, title, description, emoji,
        daily_target, target_unit, join_code, invite_slug,
        is_recurring, start_date, end_date, max_participants,
        visibility, category, participant_count, status
    ) VALUES (
        current_user_uuid, p_challenge_type, p_title, p_description, COALESCE(p_emoji, '🌍'),
        p_daily_target, p_target_unit, v_join_code, v_slug,
        COALESCE(p_is_recurring, TRUE), CURRENT_DATE, v_end_date, p_max_participants,
        COALESCE(p_visibility, 'public'), COALESCE(p_category, 'fitness'), 1, 'active'
    )
    RETURNING id INTO new_id;

    -- Auto-join the creator
    INSERT INTO community_challenge_participants (
        challenge_id, user_id, is_active
    ) VALUES (
        new_id, current_user_uuid, TRUE
    );

    RETURN new_id;
END;
$$;

GRANT EXECUTE ON FUNCTION create_community_challenge(TEXT, TEXT, TEXT, TEXT, INT, TEXT, BOOLEAN, TEXT, INT, TEXT, TEXT) TO authenticated;


-- ============================================================================
-- RPC 2: join_community_challenge
-- Joins by either join_code or invite_slug. Returns challenge ID.
-- ============================================================================
CREATE OR REPLACE FUNCTION join_community_challenge(
    p_join_code TEXT DEFAULT NULL,
    p_invite_slug TEXT DEFAULT NULL,
    p_referred_by TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    current_user_uuid UUID;
    v_challenge RECORD;
    v_referred_by_uuid UUID;
BEGIN
    current_user_uuid := auth.uid();
    IF current_user_uuid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    -- Find the challenge by code or slug
    IF p_join_code IS NOT NULL AND p_join_code != '' THEN
        SELECT * INTO v_challenge FROM community_challenges 
        WHERE join_code = upper(trim(p_join_code)) AND status = 'active';
    ELSIF p_invite_slug IS NOT NULL AND p_invite_slug != '' THEN
        SELECT * INTO v_challenge FROM community_challenges 
        WHERE invite_slug = lower(trim(p_invite_slug)) AND status = 'active';
    ELSE
        RAISE EXCEPTION 'Must provide join_code or invite_slug';
    END IF;

    IF v_challenge IS NULL THEN
        RAISE EXCEPTION 'Challenge not found or no longer active';
    END IF;

    -- Check max participants
    IF v_challenge.max_participants IS NOT NULL AND v_challenge.participant_count >= v_challenge.max_participants THEN
        RAISE EXCEPTION 'This challenge is full';
    END IF;

    -- Check if already joined (reactivate if left)
    IF EXISTS (
        SELECT 1 FROM community_challenge_participants 
        WHERE challenge_id = v_challenge.id AND user_id = current_user_uuid
    ) THEN
        UPDATE community_challenge_participants
        SET is_active = TRUE, last_active_at = NOW()
        WHERE challenge_id = v_challenge.id AND user_id = current_user_uuid AND is_active = FALSE;
        
        -- If already active, just return the ID
        RETURN v_challenge.id;
    END IF;

    -- Parse referrer
    IF p_referred_by IS NOT NULL AND p_referred_by != '' THEN
        v_referred_by_uuid := p_referred_by::UUID;
    END IF;

    -- Join the challenge
    INSERT INTO community_challenge_participants (
        challenge_id, user_id, referred_by, is_active
    ) VALUES (
        v_challenge.id, current_user_uuid, v_referred_by_uuid, TRUE
    );

    -- Update participant count
    UPDATE community_challenges 
    SET participant_count = participant_count + 1,
        updated_at = NOW()
    WHERE id = v_challenge.id;

    RETURN v_challenge.id;
END;
$$;

GRANT EXECUTE ON FUNCTION join_community_challenge(TEXT, TEXT, TEXT) TO authenticated;


-- ============================================================================
-- RPC 3: leave_community_challenge
-- ============================================================================
CREATE OR REPLACE FUNCTION leave_community_challenge(
    p_challenge_id TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    current_user_uuid UUID;
    v_challenge_id UUID;
BEGIN
    current_user_uuid := auth.uid();
    v_challenge_id := p_challenge_id::UUID;

    UPDATE community_challenge_participants
    SET is_active = FALSE
    WHERE challenge_id = v_challenge_id AND user_id = current_user_uuid;

    -- Decrement participant count
    UPDATE community_challenges 
    SET participant_count = GREATEST(0, participant_count - 1),
        updated_at = NOW()
    WHERE id = v_challenge_id;

    RETURN TRUE;
END;
$$;

GRANT EXECUTE ON FUNCTION leave_community_challenge(TEXT) TO authenticated;


-- ============================================================================
-- RPC 4: log_community_challenge_progress
-- ============================================================================
CREATE OR REPLACE FUNCTION log_community_challenge_progress(
    p_challenge_id TEXT,
    p_progress INT,
    p_timezone TEXT DEFAULT 'UTC'
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    current_user_uuid UUID;
    v_challenge_id UUID;
    today_date DATE;
    v_daily_target INT;
    v_target_hit BOOLEAN;
    v_prev_target_hit BOOLEAN;
BEGIN
    current_user_uuid := auth.uid();
    v_challenge_id := p_challenge_id::UUID;
    today_date := (NOW() AT TIME ZONE COALESCE(p_timezone, 'UTC'))::DATE;

    -- Get daily target
    SELECT daily_target INTO v_daily_target
    FROM community_challenges WHERE id = v_challenge_id;

    v_target_hit := (v_daily_target IS NOT NULL AND p_progress >= v_daily_target);

    -- Check if target was already hit (for completion counting)
    SELECT target_hit INTO v_prev_target_hit
    FROM community_challenge_daily_progress
    WHERE challenge_id = v_challenge_id AND user_id = current_user_uuid AND progress_date = today_date;

    -- Upsert daily progress
    INSERT INTO community_challenge_daily_progress (
        challenge_id, user_id, progress_date, progress_value, target_hit, source, updated_at
    ) VALUES (
        v_challenge_id, current_user_uuid, today_date, p_progress, v_target_hit, 'auto_sync', NOW()
    )
    ON CONFLICT (challenge_id, user_id, progress_date)
    DO UPDATE SET
        progress_value = GREATEST(community_challenge_daily_progress.progress_value, EXCLUDED.progress_value),
        target_hit = CASE 
            WHEN EXCLUDED.progress_value > community_challenge_daily_progress.progress_value 
            THEN EXCLUDED.target_hit
            ELSE community_challenge_daily_progress.target_hit
        END,
        updated_at = NOW()
    WHERE EXCLUDED.progress_value > community_challenge_daily_progress.progress_value;

    -- Update participant aggregates
    UPDATE community_challenge_participants
    SET 
        today_progress = p_progress,
        total_progress = (
            SELECT COALESCE(SUM(progress_value), 0)
            FROM community_challenge_daily_progress
            WHERE challenge_id = v_challenge_id AND user_id = current_user_uuid
        ),
        days_completed = (
            SELECT COUNT(*)
            FROM community_challenge_daily_progress
            WHERE challenge_id = v_challenge_id AND user_id = current_user_uuid AND target_hit = TRUE
        ),
        last_active_at = NOW()
    WHERE challenge_id = v_challenge_id AND user_id = current_user_uuid;

    -- If this is a NEW completion (target just hit), increment global completions counter
    IF v_target_hit AND (v_prev_target_hit IS NULL OR v_prev_target_hit = FALSE) THEN
        UPDATE community_challenges
        SET total_completions = total_completions + 1
        WHERE id = v_challenge_id;
    END IF;

    RETURN TRUE;
END;
$$;

GRANT EXECUTE ON FUNCTION log_community_challenge_progress(TEXT, INT, TEXT) TO authenticated;


-- ============================================================================
-- RPC 5: get_community_challenge_leaderboard
-- Returns top N participants + the current user's rank and progress
-- ============================================================================
CREATE OR REPLACE FUNCTION get_community_challenge_leaderboard(
    p_challenge_id TEXT,
    p_limit INT DEFAULT 20,
    p_timezone TEXT DEFAULT 'UTC'
)
RETURNS TABLE (
    challenge_id UUID,
    challenge_title TEXT,
    challenge_emoji TEXT,
    challenge_type TEXT,
    daily_target INT,
    target_unit TEXT,
    participant_count INT,
    join_code TEXT,
    invite_slug TEXT,
    -- Leaderboard entries
    leaderboard JSONB,
    -- Current user's position
    my_rank INT,
    my_today_progress INT,
    my_days_completed INT,
    my_current_streak INT,
    my_best_streak INT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    current_user_uuid UUID;
    v_challenge_id UUID;
    today_date DATE;
    v_my_rank INT;
    v_my_today INT;
    v_my_days INT;
    v_my_streak INT;
    v_my_best INT;
BEGIN
    current_user_uuid := auth.uid();
    v_challenge_id := p_challenge_id::UUID;
    today_date := (NOW() AT TIME ZONE COALESCE(p_timezone, 'UTC'))::DATE;

    -- Calculate my rank (based on today's progress)
    SELECT ranked.rank, ranked.today_progress, ranked.days_completed, ranked.current_streak, ranked.best_streak
    INTO v_my_rank, v_my_today, v_my_days, v_my_streak, v_my_best
    FROM (
        SELECT 
            ccp.user_id,
            COALESCE(cdp.progress_value, 0) AS today_progress,
            ccp.days_completed,
            ccp.current_streak,
            ccp.best_streak,
            ROW_NUMBER() OVER (ORDER BY COALESCE(cdp.progress_value, 0) DESC, ccp.days_completed DESC) AS rank
        FROM community_challenge_participants ccp
        LEFT JOIN community_challenge_daily_progress cdp 
            ON cdp.challenge_id = ccp.challenge_id 
            AND cdp.user_id = ccp.user_id 
            AND cdp.progress_date = today_date
        WHERE ccp.challenge_id = v_challenge_id AND ccp.is_active = TRUE
    ) ranked
    WHERE ranked.user_id = current_user_uuid;

    RETURN QUERY
    SELECT
        cc.id AS challenge_id,
        cc.title AS challenge_title,
        cc.emoji AS challenge_emoji,
        cc.challenge_type,
        cc.daily_target,
        cc.target_unit,
        cc.participant_count,
        cc.join_code,
        cc.invite_slug,
        -- Top N leaderboard
        (
            SELECT jsonb_agg(entry ORDER BY entry->>'rank')
            FROM (
                SELECT jsonb_build_object(
                    'rank', ROW_NUMBER() OVER (ORDER BY COALESCE(cdp.progress_value, 0) DESC, ccp.days_completed DESC),
                    'user_id', ccp.user_id,
                    'name', up.name,
                    'username', up.username,
                    'profile_photo_url', up.profile_photo_url,
                    'today_progress', COALESCE(cdp.progress_value, 0),
                    'days_completed', ccp.days_completed,
                    'current_streak', ccp.current_streak,
                    'target_hit_today', COALESCE(cdp.target_hit, FALSE)
                ) AS entry
                FROM community_challenge_participants ccp
                JOIN user_profiles up ON up.id = ccp.user_id
                LEFT JOIN community_challenge_daily_progress cdp 
                    ON cdp.challenge_id = ccp.challenge_id 
                    AND cdp.user_id = ccp.user_id 
                    AND cdp.progress_date = today_date
                WHERE ccp.challenge_id = v_challenge_id AND ccp.is_active = TRUE
                ORDER BY COALESCE(cdp.progress_value, 0) DESC, ccp.days_completed DESC
                LIMIT p_limit
            ) sub
        ) AS leaderboard,
        COALESCE(v_my_rank, 0)::INT AS my_rank,
        COALESCE(v_my_today, 0)::INT AS my_today_progress,
        COALESCE(v_my_days, 0)::INT AS my_days_completed,
        COALESCE(v_my_streak, 0)::INT AS my_current_streak,
        COALESCE(v_my_best, 0)::INT AS my_best_streak
    FROM community_challenges cc
    WHERE cc.id = v_challenge_id;
END;
$$;

GRANT EXECUTE ON FUNCTION get_community_challenge_leaderboard(TEXT, INT, TEXT) TO authenticated;


-- ============================================================================
-- RPC 6: get_my_community_challenges
-- ============================================================================
CREATE OR REPLACE FUNCTION get_my_community_challenges(
    p_timezone TEXT DEFAULT 'UTC'
)
RETURNS TABLE (
    challenge_id UUID,
    title TEXT,
    description TEXT,
    emoji TEXT,
    challenge_type TEXT,
    daily_target INT,
    target_unit TEXT,
    participant_count INT,
    join_code TEXT,
    invite_slug TEXT,
    is_recurring BOOLEAN,
    is_featured BOOLEAN,
    is_official BOOLEAN,
    my_today_progress INT,
    my_days_completed INT,
    my_current_streak INT,
    my_rank INT,
    created_by UUID,
    creator_name TEXT,
    creator_username TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    current_user_uuid UUID;
    today_date DATE;
BEGIN
    current_user_uuid := auth.uid();
    IF current_user_uuid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    today_date := (NOW() AT TIME ZONE COALESCE(p_timezone, 'UTC'))::DATE;

    RETURN QUERY
    SELECT
        cc.id AS challenge_id,
        cc.title,
        cc.description,
        cc.emoji,
        cc.challenge_type,
        cc.daily_target,
        cc.target_unit,
        cc.participant_count,
        cc.join_code,
        cc.invite_slug,
        cc.is_recurring,
        cc.is_featured,
        cc.is_official,
        COALESCE(cdp.progress_value, 0)::INT AS my_today_progress,
        ccp.days_completed::INT AS my_days_completed,
        ccp.current_streak::INT AS my_current_streak,
        (
            SELECT COUNT(*)::INT + 1
            FROM community_challenge_participants other_ccp
            LEFT JOIN community_challenge_daily_progress other_cdp 
                ON other_cdp.challenge_id = other_ccp.challenge_id 
                AND other_cdp.user_id = other_ccp.user_id 
                AND other_cdp.progress_date = today_date
            WHERE other_ccp.challenge_id = cc.id 
            AND other_ccp.is_active = TRUE
            AND other_ccp.user_id != current_user_uuid
            AND COALESCE(other_cdp.progress_value, 0) > COALESCE(cdp.progress_value, 0)
        )::INT AS my_rank,
        cc.created_by,
        creator_up.name AS creator_name,
        creator_up.username AS creator_username
    FROM community_challenge_participants ccp
    JOIN community_challenges cc ON cc.id = ccp.challenge_id
    JOIN user_profiles creator_up ON creator_up.id = cc.created_by
    LEFT JOIN community_challenge_daily_progress cdp 
        ON cdp.challenge_id = cc.id 
        AND cdp.user_id = current_user_uuid 
        AND cdp.progress_date = today_date
    WHERE ccp.user_id = current_user_uuid
    AND ccp.is_active = TRUE
    AND cc.status = 'active'
    ORDER BY cc.is_featured DESC, cc.participant_count DESC;
END;
$$;

GRANT EXECUTE ON FUNCTION get_my_community_challenges(TEXT) TO authenticated;


-- ============================================================================
-- RPC 7: get_featured_community_challenges
-- Discover popular/featured community challenges to join
-- ============================================================================
CREATE OR REPLACE FUNCTION get_featured_community_challenges(
    p_limit INT DEFAULT 20,
    p_category TEXT DEFAULT NULL
)
RETURNS TABLE (
    challenge_id UUID,
    title TEXT,
    description TEXT,
    emoji TEXT,
    challenge_type TEXT,
    daily_target INT,
    target_unit TEXT,
    participant_count INT,
    total_completions INT,
    join_code TEXT,
    invite_slug TEXT,
    is_featured BOOLEAN,
    is_official BOOLEAN,
    is_recurring BOOLEAN,
    category TEXT,
    created_by UUID,
    creator_name TEXT,
    creator_username TEXT,
    already_joined BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    current_user_uuid UUID;
BEGIN
    current_user_uuid := auth.uid();

    RETURN QUERY
    SELECT
        cc.id AS challenge_id,
        cc.title,
        cc.description,
        cc.emoji,
        cc.challenge_type,
        cc.daily_target,
        cc.target_unit,
        cc.participant_count,
        cc.total_completions,
        cc.join_code,
        cc.invite_slug,
        cc.is_featured,
        cc.is_official,
        cc.is_recurring,
        cc.category,
        cc.created_by,
        up.name AS creator_name,
        up.username AS creator_username,
        EXISTS (
            SELECT 1 FROM community_challenge_participants ccp
            WHERE ccp.challenge_id = cc.id AND ccp.user_id = current_user_uuid AND ccp.is_active = TRUE
        ) AS already_joined
    FROM community_challenges cc
    JOIN user_profiles up ON up.id = cc.created_by
    WHERE cc.status = 'active'
    AND cc.visibility = 'public'
    AND (p_category IS NULL OR cc.category = p_category)
    ORDER BY 
        cc.is_official DESC,
        cc.is_featured DESC, 
        cc.participant_count DESC,
        cc.total_completions DESC
    LIMIT COALESCE(p_limit, 20);
END;
$$;

GRANT EXECUTE ON FUNCTION get_featured_community_challenges(INT, TEXT) TO authenticated;


-- ============================================================================
-- RPC 8: get_community_challenge_by_code
-- Lookup a challenge by join code or slug (for the join flow)
-- ============================================================================
CREATE OR REPLACE FUNCTION get_community_challenge_by_code(
    p_code TEXT
)
RETURNS TABLE (
    challenge_id UUID,
    title TEXT,
    description TEXT,
    emoji TEXT,
    challenge_type TEXT,
    daily_target INT,
    target_unit TEXT,
    participant_count INT,
    join_code TEXT,
    invite_slug TEXT,
    is_recurring BOOLEAN,
    is_featured BOOLEAN,
    is_official BOOLEAN,
    creator_name TEXT,
    creator_username TEXT,
    creator_photo_url TEXT,
    already_joined BOOLEAN,
    status TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    current_user_uuid UUID;
    v_code TEXT;
BEGIN
    current_user_uuid := auth.uid();
    v_code := trim(p_code);

    RETURN QUERY
    SELECT
        cc.id AS challenge_id,
        cc.title,
        cc.description,
        cc.emoji,
        cc.challenge_type,
        cc.daily_target,
        cc.target_unit,
        cc.participant_count,
        cc.join_code,
        cc.invite_slug,
        cc.is_recurring,
        cc.is_featured,
        cc.is_official,
        up.name AS creator_name,
        up.username AS creator_username,
        up.profile_photo_url AS creator_photo_url,
        EXISTS (
            SELECT 1 FROM community_challenge_participants ccp
            WHERE ccp.challenge_id = cc.id AND ccp.user_id = current_user_uuid AND ccp.is_active = TRUE
        ) AS already_joined,
        cc.status
    FROM community_challenges cc
    JOIN user_profiles up ON up.id = cc.created_by
    WHERE cc.join_code = upper(v_code)
       OR cc.invite_slug = lower(v_code);
END;
$$;

GRANT EXECUTE ON FUNCTION get_community_challenge_by_code(TEXT) TO authenticated;


-- ============================================================================
-- RLS Policies
-- ============================================================================
ALTER TABLE community_challenges ENABLE ROW LEVEL SECURITY;
ALTER TABLE community_challenge_participants ENABLE ROW LEVEL SECURITY;
ALTER TABLE community_challenge_daily_progress ENABLE ROW LEVEL SECURITY;

-- Community challenges: anyone can read public/active, creator can update
CREATE POLICY "Anyone can view active public community challenges"
    ON community_challenges FOR SELECT
    USING (status = 'active' AND visibility = 'public');

CREATE POLICY "Participants can view their challenges"
    ON community_challenges FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM community_challenge_participants ccp
            WHERE ccp.challenge_id = id AND ccp.user_id = auth.uid() AND ccp.is_active = TRUE
        )
    );

CREATE POLICY "Creator can update their challenges"
    ON community_challenges FOR UPDATE
    USING (created_by = auth.uid());

-- Participants: users can read all participants in challenges they've joined
CREATE POLICY "Participants can view other participants"
    ON community_challenge_participants FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM community_challenge_participants my_ccp
            WHERE my_ccp.challenge_id = challenge_id AND my_ccp.user_id = auth.uid()
        )
    );

-- Daily progress: users can read progress in challenges they've joined
CREATE POLICY "Participants can view daily progress"
    ON community_challenge_daily_progress FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM community_challenge_participants ccp
            WHERE ccp.challenge_id = challenge_id AND ccp.user_id = auth.uid()
        )
    );


-- ============================================================================
-- SEED: Official Fit33 Community Challenges
-- ============================================================================
INSERT INTO community_challenges (
    created_by, challenge_type, title, description, emoji,
    daily_target, target_unit, join_code, invite_slug,
    is_recurring, visibility, is_featured, is_official, category,
    participant_count, status
) VALUES
-- Steps challenges
((SELECT id FROM user_profiles LIMIT 1), 'steps', '10K Steps Daily', 
 'The classic — hit 10,000 steps every single day. Join thousands of Fit33 users crushing this goal together.', '👟',
 10000, 'steps', 'FIT10K', '10k-steps-daily',
 TRUE, 'public', TRUE, TRUE, 'fitness', 0, 'active'),

((SELECT id FROM user_profiles LIMIT 1), 'steps', '5K Morning Walk', 
 'Start every morning with 5,000 steps before noon. A gentle way to build the walking habit.', '🌅',
 5000, 'steps', 'MORN5K', '5k-morning-walk',
 TRUE, 'public', TRUE, TRUE, 'fitness', 0, 'active'),

-- Hydration challenges
((SELECT id FROM user_profiles LIMIT 1), 'hydrate', 'Hydro Homies', 
 'Drink at least 2 liters of water every day. Your body will thank you.', '💧',
 2000, 'ml', 'HYDRO2', 'hydro-homies-2l',
 TRUE, 'public', TRUE, TRUE, 'wellness', 0, 'active'),

-- Protein challenges  
((SELECT id FROM user_profiles LIMIT 1), 'protein', 'Protein Club 150', 
 'Hit 150g of protein daily. Essential for muscle building and recovery.', '🥩',
 150, 'grams', 'PRO150', 'protein-club-150',
 TRUE, 'public', TRUE, TRUE, 'nutrition', 0, 'active'),

-- Calorie challenges
((SELECT id FROM user_profiles LIMIT 1), 'calories', 'Burn 500 Club', 
 'Burn at least 500 active calories every day through exercise.', '🔥',
 500, 'calories', 'BURN5H', 'burn-500-club',
 TRUE, 'public', TRUE, TRUE, 'fitness', 0, 'active'),

-- Workout challenges
((SELECT id FROM user_profiles LIMIT 1), 'workout_streak', 'No Rest Day', 
 'Complete at least one workout every single day. Any workout counts — weights, cardio, yoga, you name it.', '💪',
 1, 'workouts', 'NORST1', 'no-rest-day',
 TRUE, 'public', TRUE, TRUE, 'fitness', 0, 'active'),

-- Active minutes
((SELECT id FROM user_profiles LIMIT 1), 'active_minutes', '30 Min Movement', 
 'Be active for at least 30 minutes every day. Walking, running, lifting — it all counts.', '⏱️',
 30, 'minutes', 'ACT30M', '30-min-movement',
 TRUE, 'public', TRUE, TRUE, 'fitness', 0, 'active'),

-- Walking challenge
((SELECT id FROM user_profiles LIMIT 1), 'walk', 'Lunchtime Walkers', 
 'Take a 30-minute walk during your lunch break every day. Great for productivity and health.', '🚶',
 30, 'minutes', 'LUNCH3', 'lunchtime-walkers',
 TRUE, 'public', TRUE, TRUE, 'wellness', 0, 'active')

ON CONFLICT (join_code) DO NOTHING;


-- ============================================================================
-- SUMMARY
-- ============================================================================
DO $$
BEGIN
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
    RAISE NOTICE '✅ COMMUNITY CHALLENGES MIGRATION COMPLETE';
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
    RAISE NOTICE '';
    RAISE NOTICE '📌 Tables created:';
    RAISE NOTICE '   1. community_challenges';
    RAISE NOTICE '   2. community_challenge_participants';
    RAISE NOTICE '   3. community_challenge_daily_progress';
    RAISE NOTICE '';
    RAISE NOTICE '📌 RPC Functions:';
    RAISE NOTICE '   1. create_community_challenge';
    RAISE NOTICE '   2. join_community_challenge';
    RAISE NOTICE '   3. leave_community_challenge';
    RAISE NOTICE '   4. log_community_challenge_progress';
    RAISE NOTICE '   5. get_community_challenge_leaderboard';
    RAISE NOTICE '   6. get_my_community_challenges';
    RAISE NOTICE '   7. get_featured_community_challenges';
    RAISE NOTICE '   8. get_community_challenge_by_code';
    RAISE NOTICE '';
    RAISE NOTICE '🌍 8 Official seed challenges created';
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
END $$;
