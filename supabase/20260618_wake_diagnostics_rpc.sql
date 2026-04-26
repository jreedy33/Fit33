-- =============================================================================
-- Wake Diagnostics RPC — `get_my_wake_diagnostics(p_lookback_hours INT)`
-- =============================================================================
-- Why this exists:
--
-- Users hit a frustrating UX where opponents show "0 steps" mid-day even
-- though the opponent is presumably moving. The expected pipeline is:
--
--   wake-challenge-opponents (silent push) → opponent device wakes →
--   performLiteWakeSync → log_challenge_progress → realtime UPDATE →
--   our app shows fresh value
--
-- When the opponent is stuck at 0 the failure is upstream of the widget /
-- realtime layer, but until now we have had no way to *see* whether their
-- device was even pushed during the day, whether the push token was valid,
-- or whether a timeout / penalty has knocked them out of the silent-push
-- budget. The data exists in `silent_push_wake_log` and `user_push_tokens`
-- — both of which are service-role-only by design (Infra invariant #14)
-- so a client-readable RLS policy is OUT OF THE QUESTION.
--
-- This SECURITY DEFINER RPC bridges the gap: it returns wake history +
-- token state ONLY for users the caller is currently in an active
-- challenge with (1v1, group, or private), pinned to `auth.uid()`. No
-- access to log entries for arbitrary user_ids, no access to actual
-- device tokens (we return only the validity flag + apns environment +
-- prefix for visual matching).
--
-- Used by the in-app DEBUG-only `WakeDiagnosticsView` to answer
-- "did Abbie's phone get a wake push in the last 24h?" without poking
-- around in the SQL editor.
--
-- ROLLBACK:
--   DROP FUNCTION IF EXISTS get_my_wake_diagnostics(INT);
-- =============================================================================

BEGIN;

-- Drop any prior overloads before CREATE OR REPLACE per Supabase rules.
DROP FUNCTION IF EXISTS get_my_wake_diagnostics(INT);

CREATE OR REPLACE FUNCTION get_my_wake_diagnostics(p_lookback_hours INT DEFAULT 24)
RETURNS TABLE (
    user_id              UUID,
    display_name         TEXT,
    username             TEXT,
    profile_photo_url    TEXT,
    relationship         TEXT,           -- 'self' | '1v1_or_group' | 'private'
    last_wake_at         TIMESTAMPTZ,
    last_wake_trigger    TEXT,
    wake_count_24h       INT,
    has_valid_token      BOOLEAN,
    token_count          INT,            -- number of registered tokens (any validity)
    apns_environment     TEXT,           -- 'production' | 'development' | NULL
    token_prefix         TEXT,           -- first 12 chars of newest valid token; NULL if none
    last_progress_at     TIMESTAMPTZ,    -- newest challenge_daily_progress.updated_at across any challenge
    last_progress_value  INT             -- progress_value for that newest row
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_caller UUID;
    v_lookback_hours INT;
    v_cutoff TIMESTAMPTZ;
BEGIN
    v_caller := auth.uid();
    IF v_caller IS NULL THEN
        RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '42501';
    END IF;

    -- Clamp lookback so callers can't ask for unbounded history.
    v_lookback_hours := GREATEST(1, LEAST(COALESCE(p_lookback_hours, 24), 168));
    v_cutoff := NOW() - make_interval(hours => v_lookback_hours);

    RETURN QUERY
    WITH related AS (
        -- 1. Caller themselves — useful to confirm OUR wake/token state
        SELECT v_caller AS uid, 'self'::TEXT AS rel
        UNION
        -- 2. Opponents in active 1v1 / group challenges
        SELECT cp_other.user_id AS uid, '1v1_or_group'::TEXT AS rel
        FROM challenge_participants my_cp
        JOIN group_challenges gc ON gc.id = my_cp.challenge_id AND gc.status = 'active'
        JOIN challenge_participants cp_other
              ON cp_other.challenge_id = my_cp.challenge_id
             AND cp_other.user_id <> v_caller
             AND cp_other.status = 'accepted'
        WHERE my_cp.user_id = v_caller AND my_cp.status = 'accepted'
        UNION
        -- 3. Other members in active private challenges
        SELECT pcm_other.user_id AS uid, 'private'::TEXT AS rel
        FROM private_challenge_members my_pcm
        JOIN private_challenges pc ON pc.id = my_pcm.challenge_id
        JOIN private_challenge_members pcm_other
              ON pcm_other.challenge_id = my_pcm.challenge_id
             AND pcm_other.user_id <> v_caller
        WHERE my_pcm.user_id = v_caller
          AND (pc.end_date IS NULL OR pc.end_date >= CURRENT_DATE)
    ),
    -- Collapse duplicates: a user can be both a 1v1 opponent AND a private
    -- co-member. Prefer 'self' > '1v1_or_group' > 'private' for display.
    related_dedup AS (
        SELECT DISTINCT ON (uid) uid, rel
        FROM related
        ORDER BY uid,
                 CASE rel
                     WHEN 'self' THEN 1
                     WHEN '1v1_or_group' THEN 2
                     ELSE 3
                 END
    ),
    wake_summary AS (
        SELECT
            spwl.user_id,
            MAX(spwl.sent_at) AS last_wake_at,
            COUNT(*)::INT AS wake_count_24h,
            (ARRAY_AGG(spwl.triggered_by ORDER BY spwl.sent_at DESC))[1] AS last_wake_trigger
        FROM silent_push_wake_log spwl
        WHERE spwl.sent_at >= v_cutoff
          AND spwl.user_id IN (SELECT uid FROM related_dedup)
        GROUP BY spwl.user_id
    ),
    token_summary AS (
        SELECT
            upt.user_id,
            COUNT(*)::INT AS token_count,
            BOOL_OR(upt.is_valid) AS has_valid_token,
            -- Newest valid token wins for env + prefix; fallback to newest
            -- regardless of validity if every token is currently invalid.
            (ARRAY_AGG(upt.apns_environment ORDER BY upt.is_valid DESC, upt.updated_at DESC))[1] AS apns_environment,
            (ARRAY_AGG(SUBSTRING(upt.device_token FROM 1 FOR 12)
                       ORDER BY upt.is_valid DESC, upt.updated_at DESC))[1] AS token_prefix
        FROM user_push_tokens upt
        WHERE upt.user_id IN (SELECT uid FROM related_dedup)
        GROUP BY upt.user_id
    ),
    progress_union AS (
        -- Walk all three daily-progress tables. Even though Data invariant
        -- #48 fans writes across them, a user who is ONLY in private (or
        -- ONLY in community) challenges won't have rows in
        -- `challenge_daily_progress`. Coalescing across all three keeps
        -- "last progress" honest regardless of which surface initiated.
        SELECT user_id, updated_at, progress_value
            FROM challenge_daily_progress
            WHERE user_id IN (SELECT uid FROM related_dedup)
        UNION ALL
        SELECT user_id, updated_at, progress_value
            FROM private_challenge_daily_progress
            WHERE user_id IN (SELECT uid FROM related_dedup)
        UNION ALL
        SELECT user_id, updated_at, progress_value
            FROM community_challenge_daily_progress
            WHERE user_id IN (SELECT uid FROM related_dedup)
    ),
    progress_summary AS (
        SELECT DISTINCT ON (pu.user_id)
            pu.user_id,
            pu.updated_at AS last_progress_at,
            pu.progress_value AS last_progress_value
        FROM progress_union pu
        ORDER BY pu.user_id, pu.updated_at DESC
    )
    SELECT
        rd.uid,
        COALESCE(up.name, 'Unknown'),
        up.username,
        CASE WHEN COALESCE(up.privacy_hide_photo, FALSE)
             THEN NULL
             ELSE up.profile_photo_url
        END,
        rd.rel,
        ws.last_wake_at,
        ws.last_wake_trigger,
        COALESCE(ws.wake_count_24h, 0),
        COALESCE(ts.has_valid_token, FALSE),
        COALESCE(ts.token_count, 0),
        ts.apns_environment,
        ts.token_prefix,
        ps.last_progress_at,
        ps.last_progress_value
    FROM related_dedup rd
    LEFT JOIN user_profiles    up ON up.id = rd.uid
    LEFT JOIN wake_summary     ws ON ws.user_id = rd.uid
    LEFT JOIN token_summary    ts ON ts.user_id = rd.uid
    LEFT JOIN progress_summary ps ON ps.user_id = rd.uid
    ORDER BY rd.rel = 'self' DESC,
             COALESCE(ws.last_wake_at, '-infinity'::TIMESTAMPTZ) DESC,
             COALESCE(up.name, '');
END;
$$;

REVOKE ALL ON FUNCTION get_my_wake_diagnostics(INT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION get_my_wake_diagnostics(INT) TO authenticated, service_role;

COMMENT ON FUNCTION get_my_wake_diagnostics(INT) IS
    'Returns wake-log + token state for caller + their active-challenge counterparts. SECURITY DEFINER, pinned to auth.uid(). Bridges service-role-only `silent_push_wake_log` for the in-app DEBUG diagnostics view. Does NOT return device tokens (only first 12 chars). p_lookback_hours clamped to [1, 168].';

DO $$ BEGIN
    RAISE NOTICE '✅ get_my_wake_diagnostics(INT) deployed';
END $$;

COMMIT;
