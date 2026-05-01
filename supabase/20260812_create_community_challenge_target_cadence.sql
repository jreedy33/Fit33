-- ============================================================================
-- MIGRATION #178 — create_community_challenge accepts p_target_cadence
-- ============================================================================
--
-- Pairs with #176 (challenge_templates with target_cadence column) and #177
-- (target_cadence column on community_challenges + cadence-aware progress
-- writers). Without this migration, every community challenge created from
-- a non-daily template (e.g. "5 Runs in 7 Days") would land in the DB with
-- the default `target_cadence = 'daily'` because the RPC swallows the
-- column on insert.
--
-- This is purely additive: callers who don't pass `p_target_cadence`
-- continue to get 'daily' (matches the column default + pre-#178 behavior).
-- ============================================================================

BEGIN;

-- Drop every known overload (supabase-rules invariant 12 — drop-all-before-
-- create-or-replace prevents overload drift).
DROP FUNCTION IF EXISTS create_community_challenge(TEXT, TEXT, TEXT, TEXT, INT, TEXT, BOOLEAN, TEXT, INT, TEXT, TEXT);
DROP FUNCTION IF EXISTS create_community_challenge(TEXT, TEXT, TEXT, TEXT, INT, TEXT, BOOLEAN, TEXT, INT, TEXT, TEXT, TEXT);

CREATE OR REPLACE FUNCTION create_community_challenge(
    p_challenge_type   TEXT,
    p_title            TEXT,
    p_description      TEXT,
    p_emoji            TEXT,
    p_daily_target     INT,
    p_target_unit      TEXT,
    p_is_recurring     BOOLEAN DEFAULT FALSE,
    p_end_date         TEXT DEFAULT NULL,
    p_max_participants INT DEFAULT NULL,
    p_visibility       TEXT DEFAULT 'public',
    p_category         TEXT DEFAULT 'fitness',
    p_target_cadence   TEXT DEFAULT 'daily'
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    current_user_uuid UUID;
    new_challenge_id  UUID;
    v_join_code       TEXT;
    v_invite_slug     TEXT;
    v_end_date        DATE;
BEGIN
    current_user_uuid := auth.uid();
    IF current_user_uuid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    -- Match the constraint on community_challenges.target_cadence — fail
    -- loud if a caller invents a new cadence the server doesn't know.
    IF p_target_cadence NOT IN ('daily','weekly','total','per_session') THEN
        RAISE EXCEPTION 'Invalid target_cadence: %', p_target_cadence;
    END IF;

    new_challenge_id := gen_random_uuid();
    v_join_code      := upper(substring(md5(random()::text || clock_timestamp()::text) FROM 1 FOR 8));
    v_invite_slug    := lower(regexp_replace(p_title, '[^a-zA-Z0-9]', '-', 'g'))
                        || '-' || substring(md5(new_challenge_id::text) FROM 1 FOR 6);

    IF p_end_date IS NOT NULL AND p_end_date != '' THEN
        v_end_date := p_end_date::DATE;
    ELSE
        v_end_date := (CURRENT_DATE + INTERVAL '7 days')::DATE;
    END IF;

    INSERT INTO community_challenges (
        id, created_by, challenge_type, title, description, emoji,
        daily_target, target_unit, is_recurring, end_date,
        max_participants, visibility, category,
        join_code, invite_slug, status, target_cadence
    ) VALUES (
        new_challenge_id, current_user_uuid, p_challenge_type, p_title, p_description, p_emoji,
        p_daily_target, p_target_unit, p_is_recurring, v_end_date,
        p_max_participants, p_visibility, p_category,
        v_join_code, v_invite_slug, 'active', p_target_cadence
    );

    -- Auto-join the creator (matches pre-#178 behavior).
    INSERT INTO community_challenge_participants (
        challenge_id, user_id, joined_at, is_active
    ) VALUES (
        new_challenge_id, current_user_uuid, NOW(), TRUE
    )
    ON CONFLICT (challenge_id, user_id) DO NOTHING;

    -- Bump participant_count to match the auto-join.
    UPDATE community_challenges
       SET participant_count = participant_count + 1
     WHERE id = new_challenge_id;

    RETURN new_challenge_id;
END;
$$;

GRANT EXECUTE ON FUNCTION create_community_challenge(
    TEXT, TEXT, TEXT, TEXT, INT, TEXT, BOOLEAN, TEXT, INT, TEXT, TEXT, TEXT
) TO authenticated;

COMMENT ON FUNCTION create_community_challenge(
    TEXT, TEXT, TEXT, TEXT, INT, TEXT, BOOLEAN, TEXT, INT, TEXT, TEXT, TEXT
) IS
'Creates a community challenge. Cadence-aware since 20260812 — accepts
p_target_cadence in (daily/weekly/total/per_session). Pre-#178 callers
that omit the param continue to get the daily default. Auto-joins the
creator as a participant.';

-- ============================================================================
-- Audit
-- ============================================================================

DO $$
DECLARE v_count INT;
BEGIN
    SELECT COUNT(*) INTO v_count
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.proname = 'create_community_challenge';

    IF v_count <> 1 THEN
        RAISE EXCEPTION
            '[20260812 audit] expected exactly 1 create_community_challenge overload, got %', v_count;
    END IF;

    RAISE NOTICE '✅ MIGRATION #178 — create_community_challenge cadence-aware';
END $$;

COMMIT;
