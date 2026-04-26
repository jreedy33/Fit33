-- =============================================================================
-- 20260619_wake_diagnostics_progress_drift.sql
-- =============================================================================
-- Extends `get_my_wake_diagnostics` (originally shipped in
-- `20260618_wake_diagnostics_rpc.sql`, MIGRATION_INDEX #118) with cross-table
-- progress-drift columns so the in-app `WakeDiagnosticsView` automatically
-- surfaces the bug we hit on 2026-04-26: Abbie at 603 in Community but 0 in
-- 1v1 — Data invariant #48 violated because the fanout trigger from
-- `20260521_challenge_progress_fanout.sql` (#87) hasn't been deployed yet.
--
-- New return columns (per related user, today in caller tz):
--   • steps_today_1v1        — max progress_value across `challenge_daily_progress`
--                              rows where parent challenge_type = 'steps'.
--                              NULL = caller's counterpart has no row /
--                              membership in any 1v1 or group steps challenge
--                              for today.
--   • steps_today_private    — same shape from `private_challenge_daily_progress`.
--   • steps_today_community  — same shape from `community_challenge_daily_progress`.
--   • progress_drift_detected — TRUE iff the user has rows in MORE THAN ONE of
--                              the three tables today AND those values disagree.
--                              FALSE if only one table has data (legitimate —
--                              the user is only in one challenge surface), or
--                              all present values match. This is the same
--                              predicate as Section A in
--                              `verify_progress_drift_2026_04_26.sql`.
--
-- Why steps-only (not active_minutes / calories): steps is the only fanout
-- type observed drifting on 2026-04-26 and the only one with home-screen
-- widget visibility. Extending to other metrics is a column-count vs. signal
-- trade-off — easy to add later by repeating the three CTEs with a different
-- challenge_type.
--
-- Signature change:
--   Old: get_my_wake_diagnostics(p_lookback_hours INT)
--   New: get_my_wake_diagnostics(p_lookback_hours INT, p_timezone TEXT)
--   `p_timezone` defaults to 'UTC' so the iOS call site that only passes
--   `p_lookback_hours` keeps working (PostgREST resolves to the 2-arg
--   signature with the DEFAULT). All known iOS call sites pass `p_timezone`
--   in this migration's paired Swift change.
--
-- Idempotency:
--   Drops both the 1-arg and the 2-arg overloads before CREATE OR REPLACE
--   per supabase-rules invariant 12 (no overload drift → no PGRST202
--   "could not choose best candidate"). Safe to re-run.
--
-- Resolves: (no bug-intel fingerprints — this is observability, not a fix)
-- =============================================================================

BEGIN;

-- Drop every known overload.
DROP FUNCTION IF EXISTS get_my_wake_diagnostics(INT);
DROP FUNCTION IF EXISTS get_my_wake_diagnostics(INT, TEXT);

CREATE OR REPLACE FUNCTION get_my_wake_diagnostics(
    p_lookback_hours INT  DEFAULT 24,
    p_timezone       TEXT DEFAULT 'UTC'
)
RETURNS TABLE (
    user_id                  UUID,
    display_name             TEXT,
    username                 TEXT,
    profile_photo_url        TEXT,
    relationship             TEXT,           -- 'self' | '1v1_or_group' | 'private'
    last_wake_at             TIMESTAMPTZ,
    last_wake_trigger        TEXT,
    wake_count_24h           INT,
    has_valid_token          BOOLEAN,
    token_count              INT,            -- number of registered tokens (any validity)
    apns_environment         TEXT,           -- 'production' | 'development' | NULL
    token_prefix             TEXT,           -- first 12 chars of newest valid token; NULL if none
    last_progress_at         TIMESTAMPTZ,    -- newest *_daily_progress.updated_at across any challenge
    last_progress_value      INT,            -- progress_value for that newest row
    -- NEW (2026-04-26) — cross-table drift fields:
    steps_today_1v1          INT,
    steps_today_private      INT,
    steps_today_community    INT,
    progress_drift_detected  BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_caller         UUID;
    v_lookback_hours INT;
    v_cutoff         TIMESTAMPTZ;
    v_caller_tz      TEXT;
    v_today          DATE;
BEGIN
    v_caller := auth.uid();
    IF v_caller IS NULL THEN
        RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '42501';
    END IF;

    -- Clamp lookback so callers can't ask for unbounded history.
    v_lookback_hours := GREATEST(1, LEAST(COALESCE(p_lookback_hours, 24), 168));
    v_cutoff         := NOW() - make_interval(hours => v_lookback_hours);

    v_caller_tz := COALESCE(NULLIF(p_timezone, ''), 'UTC');
    v_today     := (NOW() AT TIME ZONE v_caller_tz)::DATE;

    RETURN QUERY
    WITH related AS (
        -- 1. Caller themselves — useful to confirm OUR wake/token/progress state
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
            (ARRAY_AGG(upt.apns_environment ORDER BY upt.is_valid DESC, upt.updated_at DESC))[1] AS apns_environment,
            (ARRAY_AGG(SUBSTRING(upt.device_token FROM 1 FOR 12)
                       ORDER BY upt.is_valid DESC, upt.updated_at DESC))[1] AS token_prefix
        FROM user_push_tokens upt
        WHERE upt.user_id IN (SELECT uid FROM related_dedup)
        GROUP BY upt.user_id
    ),
    -- Progress union for the existing `last_progress_at` / `last_progress_value`
    -- columns. Walks all three daily-progress tables — see #118 header for why.
    progress_union AS (
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
    ),
    -- ── NEW: per-table TODAY max for `steps`-typed challenges ────────────────
    -- These three CTEs MIRROR the same shape as Section A in
    -- `verify_progress_drift_2026_04_26.sql` so the trigger-not-deployed
    -- diagnosis surfaces the same way in both ad-hoc SQL and the in-app view.
    steps_1v1 AS (
        SELECT cdp.user_id, MAX(cdp.progress_value) AS v
        FROM challenge_daily_progress cdp
        JOIN group_challenges gc ON gc.id = cdp.challenge_id
        WHERE cdp.user_id IN (SELECT uid FROM related_dedup)
          AND cdp.progress_date = v_today
          AND gc.challenge_type = 'steps'
        GROUP BY cdp.user_id
    ),
    steps_private AS (
        SELECT pcdp.user_id, MAX(pcdp.progress_value) AS v
        FROM private_challenge_daily_progress pcdp
        JOIN private_challenges pc ON pc.id = pcdp.challenge_id
        WHERE pcdp.user_id IN (SELECT uid FROM related_dedup)
          AND pcdp.progress_date = v_today
          AND pc.challenge_type = 'steps'
        GROUP BY pcdp.user_id
    ),
    steps_community AS (
        SELECT ccdp.user_id, MAX(ccdp.progress_value) AS v
        FROM community_challenge_daily_progress ccdp
        JOIN community_challenges cc ON cc.id = ccdp.challenge_id
        WHERE ccdp.user_id IN (SELECT uid FROM related_dedup)
          AND ccdp.progress_date = v_today
          AND cc.challenge_type = 'steps'
        GROUP BY ccdp.user_id
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
        ps.last_progress_value,
        s1.v AS steps_today_1v1,
        sp.v AS steps_today_private,
        sc.v AS steps_today_community,
        -- Drift: at least two non-null values disagree.
        (
            (s1.v IS NOT NULL AND sp.v IS NOT NULL AND s1.v <> sp.v)
         OR (s1.v IS NOT NULL AND sc.v IS NOT NULL AND s1.v <> sc.v)
         OR (sp.v IS NOT NULL AND sc.v IS NOT NULL AND sp.v <> sc.v)
        ) AS progress_drift_detected
    FROM related_dedup rd
    LEFT JOIN user_profiles    up ON up.id      = rd.uid
    LEFT JOIN wake_summary     ws ON ws.user_id = rd.uid
    LEFT JOIN token_summary    ts ON ts.user_id = rd.uid
    LEFT JOIN progress_summary ps ON ps.user_id = rd.uid
    LEFT JOIN steps_1v1        s1 ON s1.user_id = rd.uid
    LEFT JOIN steps_private    sp ON sp.user_id = rd.uid
    LEFT JOIN steps_community  sc ON sc.user_id = rd.uid
    ORDER BY rd.rel = 'self' DESC,
             COALESCE(ws.last_wake_at, '-infinity'::TIMESTAMPTZ) DESC,
             COALESCE(up.name, '');
END;
$$;

REVOKE ALL ON FUNCTION get_my_wake_diagnostics(INT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION get_my_wake_diagnostics(INT, TEXT) TO authenticated, service_role;

COMMENT ON FUNCTION get_my_wake_diagnostics(INT, TEXT) IS
    'Wake-log + token + cross-table progress-drift state for caller + their active-challenge counterparts. SECURITY DEFINER, pinned to auth.uid(). p_lookback_hours clamped to [1, 168]. p_timezone is the caller-tz used to resolve "today" for the new steps_today_* drift columns. Drift detection mirrors verify_progress_drift_2026_04_26.sql Section A — used by the in-app DEBUG WakeDiagnosticsView to flag Data invariant #48 violations.';

DO $$
DECLARE
    fn_count    INT;
    has_drift   BOOLEAN;
BEGIN
    SELECT COUNT(*) INTO fn_count
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public'
       AND p.proname = 'get_my_wake_diagnostics';

    IF fn_count <> 1 THEN
        RAISE EXCEPTION
            '[20260619] expected exactly 1 get_my_wake_diagnostics overload after migration, found %',
            fn_count;
    END IF;

    SELECT prosrc ILIKE '%progress_drift_detected%'
      INTO has_drift
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.proname = 'get_my_wake_diagnostics';

    IF NOT has_drift THEN
        RAISE EXCEPTION
            '[20260619] get_my_wake_diagnostics body missing progress_drift_detected — wrong overload landed?';
    END IF;

    RAISE NOTICE '✅ get_my_wake_diagnostics(INT, TEXT) deployed with cross-table steps drift columns';
END $$;

COMMIT;
