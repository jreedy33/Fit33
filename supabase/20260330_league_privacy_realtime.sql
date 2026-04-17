-- Privacy Realtime Signal — Immediate propagation for privacy changes
-- Same pattern as challenge_daily_progress: thin signal table + trigger.
-- Covers BOTH privacy_hide_league and privacy_hide_activity.
-- When a user toggles either setting, a row is inserted into the signal table.
-- Other users' apps subscribe via Supabase Realtime and refresh the relevant data.

BEGIN;

-- ============================================================================
-- 1. Unified privacy signal table
-- ============================================================================
CREATE TABLE IF NOT EXISTS privacy_change_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    change_type TEXT NOT NULL,   -- 'league' or 'activity'
    is_hidden BOOLEAN NOT NULL,
    group_id UUID,               -- only set for league changes
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_privacy_change_events_type
    ON privacy_change_events(change_type, created_at DESC);

ALTER TABLE privacy_change_events ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Authenticated users can read privacy events" ON privacy_change_events;
CREATE POLICY "Authenticated users can read privacy events" ON privacy_change_events
    FOR SELECT USING (auth.role() = 'authenticated');

-- Drop old table if it exists from previous migration
DROP TABLE IF EXISTS league_privacy_events;

-- ============================================================================
-- 2. Trigger function: emits events for BOTH league and activity privacy changes
-- ============================================================================
CREATE OR REPLACE FUNCTION emit_privacy_change_event()
RETURNS TRIGGER AS $$
BEGIN
    -- League privacy changed → one row per active league membership
    IF NEW.privacy_hide_league IS DISTINCT FROM OLD.privacy_hide_league THEN
        INSERT INTO privacy_change_events (user_id, change_type, is_hidden, group_id)
        SELECT NEW.id, 'league', COALESCE(NEW.privacy_hide_league, FALSE), lm.group_id
        FROM league_members lm
        JOIN league_groups lg ON lg.id = lm.group_id
        WHERE lm.user_id = NEW.id
          AND lg.week_start = get_current_week_monday()
          AND NOT lg.is_processed;
    END IF;

    -- Activity feed privacy changed → one row (no group_id needed)
    IF NEW.privacy_hide_activity IS DISTINCT FROM OLD.privacy_hide_activity THEN
        INSERT INTO privacy_change_events (user_id, change_type, is_hidden)
        VALUES (NEW.id, 'activity', COALESCE(NEW.privacy_hide_activity, FALSE));
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- 3. Single trigger on user_profiles for both columns
-- ============================================================================
DROP TRIGGER IF EXISTS trg_league_privacy_event ON user_profiles;
DROP TRIGGER IF EXISTS trg_privacy_change_event ON user_profiles;
CREATE TRIGGER trg_privacy_change_event
    AFTER UPDATE OF privacy_hide_league, privacy_hide_activity ON user_profiles
    FOR EACH ROW
    EXECUTE FUNCTION emit_privacy_change_event();

-- ============================================================================
-- 4. Cleanup function: purge signal rows older than 7 days
-- ============================================================================
CREATE OR REPLACE FUNCTION cleanup_privacy_change_events()
RETURNS void AS $$
BEGIN
    DELETE FROM privacy_change_events WHERE created_at < NOW() - INTERVAL '7 days';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- 5. Enable Realtime: publication + replica identity
-- ============================================================================
ALTER TABLE privacy_change_events REPLICA IDENTITY FULL;

DO $$
BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE privacy_change_events;
    RAISE NOTICE '✅ Added privacy_change_events to supabase_realtime publication';
EXCEPTION WHEN duplicate_object THEN
    RAISE NOTICE 'privacy_change_events already in realtime publication';
END;
$$;

COMMIT;
