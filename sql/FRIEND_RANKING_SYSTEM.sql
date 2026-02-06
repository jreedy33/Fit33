-- =====================================================
-- FRIEND RANKING SYSTEM
-- Tracks interactions between friends for better recommendations
-- Run this in Supabase SQL Editor
-- =====================================================

-- 1. CREATE FRIEND INTERACTIONS TABLE
-- Tracks all meaningful interactions between friends
-- =====================================================
CREATE TABLE IF NOT EXISTS friend_interactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    
    -- The two users involved (always store smaller UUID first for consistency)
    user_a_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    user_b_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    
    -- Interaction type
    interaction_type TEXT NOT NULL CHECK (interaction_type IN (
        'workout_shared',       -- One shared a workout with the other
        'workout_completed',    -- Recipient completed a shared workout
        'challenge_created',    -- Started a challenge together
        'challenge_completed',  -- Completed a challenge together
        'challenge_won',        -- One won a challenge against the other
        'profile_viewed',       -- Viewed friend's profile
        'workout_liked'         -- Liked/saved a shared workout (future)
    )),
    
    -- Who initiated the interaction
    initiator_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    
    -- Reference to the related entity (workout, challenge, etc.)
    reference_id UUID,
    reference_type TEXT, -- 'shared_workout', 'challenge', etc.
    
    -- Interaction weight (different interactions have different values)
    -- This allows some interactions to count more than others
    weight INTEGER NOT NULL DEFAULT 1,
    
    -- Timestamp
    created_at TIMESTAMPTZ DEFAULT NOW(),
    
    -- Ensure user_a_id < user_b_id for consistency in queries
    CONSTRAINT user_order_check CHECK (user_a_id < user_b_id)
);

-- Indexes for fast queries
CREATE INDEX IF NOT EXISTS idx_friend_interactions_users ON friend_interactions(user_a_id, user_b_id);
CREATE INDEX IF NOT EXISTS idx_friend_interactions_type ON friend_interactions(interaction_type);
CREATE INDEX IF NOT EXISTS idx_friend_interactions_created ON friend_interactions(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_friend_interactions_initiator ON friend_interactions(initiator_id);

-- Row Level Security
ALTER TABLE friend_interactions ENABLE ROW LEVEL SECURITY;

-- Users can view interactions they're part of
DROP POLICY IF EXISTS "Users can view their interactions" ON friend_interactions;
CREATE POLICY "Users can view their interactions" ON friend_interactions
    FOR SELECT USING (auth.uid() = user_a_id OR auth.uid() = user_b_id);

-- Only system can insert (via functions)
DROP POLICY IF EXISTS "System can insert interactions" ON friend_interactions;
CREATE POLICY "System can insert interactions" ON friend_interactions
    FOR INSERT WITH CHECK (auth.uid() = initiator_id);


-- 2. FRIEND SCORES VIEW (Materialized for performance)
-- Calculates relationship strength scores between friends
-- =====================================================
DROP MATERIALIZED VIEW IF EXISTS friend_scores CASCADE;

CREATE MATERIALIZED VIEW friend_scores AS
WITH interaction_scores AS (
    SELECT 
        user_a_id,
        user_b_id,
        SUM(CASE 
            WHEN interaction_type = 'workout_shared' THEN 10
            WHEN interaction_type = 'workout_completed' THEN 25
            WHEN interaction_type = 'challenge_created' THEN 20
            WHEN interaction_type = 'challenge_completed' THEN 30
            WHEN interaction_type = 'challenge_won' THEN 15
            WHEN interaction_type = 'profile_viewed' THEN 2
            WHEN interaction_type = 'workout_liked' THEN 5
            ELSE weight
        END) as total_score,
        COUNT(*) as interaction_count,
        MAX(created_at) as last_interaction,
        
        -- Count by type for detailed breakdown
        COUNT(*) FILTER (WHERE interaction_type = 'workout_shared') as workouts_shared,
        COUNT(*) FILTER (WHERE interaction_type = 'workout_completed') as workouts_completed,
        COUNT(*) FILTER (WHERE interaction_type = 'challenge_created') as challenges_created,
        COUNT(*) FILTER (WHERE interaction_type = 'challenge_completed') as challenges_completed
    FROM friend_interactions
    -- Only count recent interactions (last 90 days matter most)
    WHERE created_at > NOW() - INTERVAL '90 days'
    GROUP BY user_a_id, user_b_id
),
-- Add recency bonus (more recent = higher score)
recency_adjusted AS (
    SELECT 
        *,
        -- Recency multiplier: 1.5x for activity in last week, 1.2x for last month
        total_score * (
            CASE 
                WHEN last_interaction > NOW() - INTERVAL '7 days' THEN 1.5
                WHEN last_interaction > NOW() - INTERVAL '30 days' THEN 1.2
                ELSE 1.0
            END
        ) as adjusted_score
    FROM interaction_scores
)
SELECT * FROM recency_adjusted;

-- Create unique index for fast refresh
CREATE UNIQUE INDEX IF NOT EXISTS idx_friend_scores_pk ON friend_scores(user_a_id, user_b_id);

-- Index for querying by user
CREATE INDEX IF NOT EXISTS idx_friend_scores_user_a ON friend_scores(user_a_id);
CREATE INDEX IF NOT EXISTS idx_friend_scores_user_b ON friend_scores(user_b_id);


-- 3. FUNCTION: Log Friend Interaction
-- Call this whenever an interaction happens
-- =====================================================
CREATE OR REPLACE FUNCTION log_friend_interaction(
    p_other_user_id UUID,
    p_interaction_type TEXT,
    p_reference_id UUID DEFAULT NULL,
    p_reference_type TEXT DEFAULT NULL,
    p_weight INTEGER DEFAULT 1
) RETURNS UUID AS $$
DECLARE
    v_user_a UUID;
    v_user_b UUID;
    v_interaction_id UUID;
BEGIN
    -- Order users consistently (smaller UUID first)
    IF auth.uid() < p_other_user_id THEN
        v_user_a := auth.uid();
        v_user_b := p_other_user_id;
    ELSE
        v_user_a := p_other_user_id;
        v_user_b := auth.uid();
    END IF;
    
    -- Insert the interaction
    INSERT INTO friend_interactions (
        user_a_id, user_b_id, interaction_type, initiator_id,
        reference_id, reference_type, weight
    ) VALUES (
        v_user_a, v_user_b, p_interaction_type, auth.uid(),
        p_reference_id, p_reference_type, p_weight
    )
    RETURNING id INTO v_interaction_id;
    
    RETURN v_interaction_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- 4. FUNCTION: Get Ranked Friends
-- Returns friends sorted by relationship strength
-- =====================================================
CREATE OR REPLACE FUNCTION get_ranked_friends()
RETURNS TABLE (
    friend_id UUID,
    friend_name TEXT,
    friend_username TEXT,
    profile_photo_url TEXT,
    fitness_goal TEXT,
    relationship_score NUMERIC,
    interaction_count BIGINT,
    workouts_shared BIGINT,
    workouts_completed BIGINT,
    challenges_together BIGINT,
    last_interaction TIMESTAMPTZ,
    friendship_started TIMESTAMPTZ,
    rank INTEGER
) AS $$
BEGIN
    RETURN QUERY
    WITH my_friends AS (
        SELECT 
            CASE 
                WHEN f.requester_id = auth.uid() THEN f.addressee_id
                ELSE f.requester_id
            END as friend_user_id,
            f.created_at as friendship_date
        FROM friendships f
        WHERE (f.requester_id = auth.uid() OR f.addressee_id = auth.uid())
        AND f.status = 'accepted'
    ),
    friend_with_scores AS (
        SELECT 
            mf.friend_user_id,
            mf.friendship_date,
            COALESCE(
                CASE 
                    WHEN mf.friend_user_id > auth.uid() THEN fs_a.adjusted_score
                    ELSE fs_b.adjusted_score
                END, 
                0
            ) as score,
            COALESCE(
                CASE 
                    WHEN mf.friend_user_id > auth.uid() THEN fs_a.interaction_count
                    ELSE fs_b.interaction_count
                END, 
                0
            ) as interactions,
            COALESCE(
                CASE 
                    WHEN mf.friend_user_id > auth.uid() THEN fs_a.workouts_shared
                    ELSE fs_b.workouts_shared
                END, 
                0
            ) as ws_count,
            COALESCE(
                CASE 
                    WHEN mf.friend_user_id > auth.uid() THEN fs_a.workouts_completed
                    ELSE fs_b.workouts_completed
                END, 
                0
            ) as wc_count,
            COALESCE(
                CASE 
                    WHEN mf.friend_user_id > auth.uid() THEN fs_a.challenges_created + fs_a.challenges_completed
                    ELSE fs_b.challenges_created + fs_b.challenges_completed
                END, 
                0
            ) as ch_count,
            COALESCE(
                CASE 
                    WHEN mf.friend_user_id > auth.uid() THEN fs_a.last_interaction
                    ELSE fs_b.last_interaction
                END, 
                mf.friendship_date
            ) as last_int
        FROM my_friends mf
        LEFT JOIN friend_scores fs_a ON fs_a.user_a_id = auth.uid() AND fs_a.user_b_id = mf.friend_user_id
        LEFT JOIN friend_scores fs_b ON fs_b.user_a_id = mf.friend_user_id AND fs_b.user_b_id = auth.uid()
    )
    SELECT 
        fws.friend_user_id as friend_id,
        up.name as friend_name,
        up.username as friend_username,
        up.profile_photo_url,
        up.fitness_goal,
        fws.score as relationship_score,
        fws.interactions as interaction_count,
        fws.ws_count as workouts_shared,
        fws.wc_count as workouts_completed,
        fws.ch_count as challenges_together,
        fws.last_int as last_interaction,
        fws.friendship_date as friendship_started,
        ROW_NUMBER() OVER (ORDER BY fws.score DESC, fws.last_int DESC NULLS LAST)::INTEGER as rank
    FROM friend_with_scores fws
    JOIN user_profiles up ON up.id = fws.friend_user_id
    ORDER BY fws.score DESC, fws.last_int DESC NULLS LAST;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- 5. FUNCTION: Get Top Friends (Quick lookup for sharing suggestions)
-- Returns just the top N friends by relationship score
-- =====================================================
CREATE OR REPLACE FUNCTION get_top_friends(p_limit INTEGER DEFAULT 5)
RETURNS TABLE (
    friend_id UUID,
    friend_name TEXT,
    friend_username TEXT,
    profile_photo_url TEXT,
    relationship_score NUMERIC
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        rf.friend_id,
        rf.friend_name,
        rf.friend_username,
        rf.profile_photo_url,
        rf.relationship_score
    FROM get_ranked_friends() rf
    LIMIT p_limit;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- 6. FUNCTION: Get Friends From Contacts
-- Returns friends who are also in the user's synced contacts
-- =====================================================
CREATE OR REPLACE FUNCTION get_friends_from_contacts()
RETURNS TABLE (
    friend_id UUID,
    friend_name TEXT,
    friend_username TEXT,
    profile_photo_url TEXT,
    fitness_goal TEXT,
    relationship_score NUMERIC,
    contact_name TEXT
) AS $$
BEGIN
    RETURN QUERY
    WITH my_friends AS (
        SELECT 
            CASE 
                WHEN f.requester_id = auth.uid() THEN f.addressee_id
                ELSE f.requester_id
            END as friend_user_id
        FROM friendships f
        WHERE (f.requester_id = auth.uid() OR f.addressee_id = auth.uid())
        AND f.status = 'accepted'
    ),
    contacts_on_fit33 AS (
        SELECT DISTINCT usc.matched_user_id, usc.contact_name
        FROM user_synced_contacts usc
        WHERE usc.user_id = auth.uid()
        AND usc.matched_user_id IS NOT NULL
    )
    SELECT 
        mf.friend_user_id as friend_id,
        up.name as friend_name,
        up.username as friend_username,
        up.profile_photo_url,
        up.fitness_goal,
        COALESCE(
            (SELECT rf.relationship_score FROM get_ranked_friends() rf WHERE rf.friend_id = mf.friend_user_id),
            0
        ) as relationship_score,
        cof.contact_name
    FROM my_friends mf
    INNER JOIN contacts_on_fit33 cof ON cof.matched_user_id = mf.friend_user_id
    JOIN user_profiles up ON up.id = mf.friend_user_id
    ORDER BY relationship_score DESC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- 7. TRIGGER: Auto-log interactions when workouts are shared
-- =====================================================
CREATE OR REPLACE FUNCTION log_workout_share_interaction()
RETURNS TRIGGER AS $$
BEGIN
    -- Log the workout share interaction
    PERFORM log_friend_interaction(
        NEW.recipient_id,
        'workout_shared',
        NEW.id,
        'shared_workout'
    );
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trigger_log_workout_share ON shared_workouts;
CREATE TRIGGER trigger_log_workout_share
    AFTER INSERT ON shared_workouts
    FOR EACH ROW
    EXECUTE FUNCTION log_workout_share_interaction();


-- 8. TRIGGER: Auto-log when shared workout is completed
-- =====================================================
CREATE OR REPLACE FUNCTION log_workout_completion_interaction()
RETURNS TRIGGER AS $$
BEGIN
    -- Only log when status changes to 'completed'
    IF NEW.status = 'completed' AND (OLD.status IS NULL OR OLD.status != 'completed') THEN
        PERFORM log_friend_interaction(
            NEW.sender_id,
            'workout_completed',
            NEW.id,
            'shared_workout'
        );
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trigger_log_workout_completion ON shared_workouts;
CREATE TRIGGER trigger_log_workout_completion
    AFTER UPDATE ON shared_workouts
    FOR EACH ROW
    EXECUTE FUNCTION log_workout_completion_interaction();


-- 9. FUNCTION: Refresh friend scores (call periodically)
-- =====================================================
CREATE OR REPLACE FUNCTION refresh_friend_scores()
RETURNS VOID AS $$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY friend_scores;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- 10. BACKFILL: Populate interactions from existing data
-- =====================================================

-- Backfill from shared_workouts
INSERT INTO friend_interactions (user_a_id, user_b_id, interaction_type, initiator_id, reference_id, reference_type, created_at, weight)
SELECT 
    CASE WHEN sender_id < recipient_id THEN sender_id ELSE recipient_id END,
    CASE WHEN sender_id < recipient_id THEN recipient_id ELSE sender_id END,
    'workout_shared',
    sender_id,
    id,
    'shared_workout',
    created_at,
    10
FROM shared_workouts
WHERE NOT EXISTS (
    SELECT 1 FROM friend_interactions fi 
    WHERE fi.reference_id = shared_workouts.id 
    AND fi.interaction_type = 'workout_shared'
);

-- Backfill completed workouts
INSERT INTO friend_interactions (user_a_id, user_b_id, interaction_type, initiator_id, reference_id, reference_type, created_at, weight)
SELECT 
    CASE WHEN sender_id < recipient_id THEN sender_id ELSE recipient_id END,
    CASE WHEN sender_id < recipient_id THEN recipient_id ELSE sender_id END,
    'workout_completed',
    recipient_id,
    id,
    'shared_workout',
    COALESCE(completed_at, created_at),
    25
FROM shared_workouts
WHERE status = 'completed'
AND NOT EXISTS (
    SELECT 1 FROM friend_interactions fi 
    WHERE fi.reference_id = shared_workouts.id 
    AND fi.interaction_type = 'workout_completed'
);

-- Backfill from challenges (if table exists)
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'challenges') THEN
        INSERT INTO friend_interactions (user_a_id, user_b_id, interaction_type, initiator_id, reference_id, reference_type, created_at, weight)
        SELECT 
            CASE WHEN cp1.user_id < cp2.user_id THEN cp1.user_id ELSE cp2.user_id END,
            CASE WHEN cp1.user_id < cp2.user_id THEN cp2.user_id ELSE cp1.user_id END,
            'challenge_created',
            c.creator_id,
            c.id,
            'challenge',
            c.created_at,
            20
        FROM challenges c
        JOIN challenge_participants cp1 ON cp1.challenge_id = c.id
        JOIN challenge_participants cp2 ON cp2.challenge_id = c.id AND cp2.user_id != cp1.user_id
        WHERE cp1.user_id < cp2.user_id -- Only insert once per challenge pair
        AND NOT EXISTS (
            SELECT 1 FROM friend_interactions fi 
            WHERE fi.reference_id = c.id 
            AND fi.interaction_type = 'challenge_created'
        );
    END IF;
END $$;

-- Initial refresh of the materialized view
REFRESH MATERIALIZED VIEW friend_scores;

-- Grant permissions
GRANT EXECUTE ON FUNCTION log_friend_interaction TO authenticated;
GRANT EXECUTE ON FUNCTION get_ranked_friends TO authenticated;
GRANT EXECUTE ON FUNCTION get_top_friends TO authenticated;
GRANT EXECUTE ON FUNCTION get_friends_from_contacts TO authenticated;
GRANT EXECUTE ON FUNCTION refresh_friend_scores TO authenticated;

-- =====================================================
-- COMPLETE! 
-- The friend ranking system is now set up.
-- 
-- Key functions:
-- - log_friend_interaction(): Manually log an interaction
-- - get_ranked_friends(): Get all friends sorted by relationship strength
-- - get_top_friends(n): Get top N friends for quick suggestions
-- - get_friends_from_contacts(): Get friends who are also in contacts
-- - refresh_friend_scores(): Refresh the scores (run daily via cron)
-- =====================================================
