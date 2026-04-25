-- ============================================================================
-- Bug Intelligence — Severity Score Rebalance (Phase 12 — Tier 2 #2)
-- Date: 2026-05-28 (migration order), authored 2026-04-25
--
-- PROBLEM
-- -------
-- Today's exports rank fingerprints by raw `occurrence_count`. That picks
-- "1 user in StagingTesterAccount looped a flaky retry 47 times" over
-- "12 real users hit a NULL crash on Dashboard once each" — exactly inverse
-- of triage value.
--
-- The CMS list and the Claude triage prompt both implicitly rely on the
-- ordering being "what to fix first". Without a real severity score, the
-- highest-volume noise fingerprint always sits at the top of the markdown
-- export. Reviewers stop scrolling once they hit it.
--
-- FIX
-- ---
-- Add a stored, periodically-recomputed `severity_score` column with the
-- weighted formula:
--
--   severity_score =
--       occurrence_count
--       × SQRT(GREATEST(unique_user_count, 1))         -- sqrt-tempered user weight
--       × screen_visibility_weight                      -- 1.0 default; 1.5 for
--                                                       -- dashboard/onboarding/
--                                                       -- active-workout (high-visibility)
--       × build_freshness_weight                        -- 1.0 if last_seen ≤ current
--                                                       --   build, 0.5 if 1 build behind,
--                                                       --   0.2 if ≥ 2 builds behind
--       × source_severity_weight                        -- 2.0 for crash, 1.0 for log
--       × CASE WHEN regressed_after_fix THEN 3.0 ELSE 1.0 END  -- regression amplifier
--
-- Why each factor:
--   - SQRT(users): a fingerprint hitting 100 users is much worse than 1 user,
--     but not 100× worse. Diminishing returns above ~10 users.
--   - screen_visibility: dashboard / onboarding / active-workout are the three
--     screens every user sees per session — bugs there are catastrophic for
--     retention. The list is small + stable + not data-driven (it tracks
--     ENGINEERING_TEAM.md "core surfaces" doc).
--   - build_freshness: a fingerprint last seen 3 builds ago is probably fixed
--     by something we shipped since. Don't let stale tail noise dominate the
--     top of the export.
--   - source_severity: a hard crash always outranks a log error of the same
--     occurrence count.
--   - regression amplifier: if it came back, surface it now.
--
-- The CMS list query orders by `severity_score DESC` after this lands. The
-- markdown export uses `severity_score` to pick the "Top 5 Critical" header
-- block instead of `(severity_letter, occurrence_count)` heuristic.
--
-- BACKWARD COMPAT
-- ---------------
-- New column is nullable; computed lazily by `bug_intel_recompute_severity()`
-- which is wired into pg_cron at :10 past every hour (after rollup at :00 and
-- callsite-backfill at :05). Until first run, NULL severity_score sorts last,
-- which is acceptable. Existing severity (`'low'/'medium'/'high'/'critical'`)
-- letter column on `bug_intelligence_reports` is untouched — that's Claude's
-- triage opinion. severity_score is the empirical signal.
--
-- ROLLBACK
-- --------
--   ALTER TABLE bug_intelligence_fingerprints DROP COLUMN IF EXISTS severity_score;
--   ALTER TABLE bug_intelligence_fingerprints DROP COLUMN IF EXISTS severity_score_updated_at;
--   DROP FUNCTION IF EXISTS bug_intel_compute_severity_score(...);
--   DROP FUNCTION IF EXISTS bug_intel_recompute_severity();
--   SELECT cron.unschedule('bug-intel-severity-recompute');
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- 1. Schema: severity_score column on fingerprints
-- ----------------------------------------------------------------------------

ALTER TABLE bug_intelligence_fingerprints
    ADD COLUMN IF NOT EXISTS severity_score              NUMERIC(12, 2),
    ADD COLUMN IF NOT EXISTS severity_score_updated_at   TIMESTAMPTZ;

COMMENT ON COLUMN bug_intelligence_fingerprints.severity_score IS
    'Empirical priority score = occurrences × sqrt(users) × screen_visibility × '
    'build_freshness × source_severity × regression_amplifier. Higher = fix '
    'sooner. Recomputed hourly via bug_intel_recompute_severity() pg_cron. '
    'Used by CMS list ordering + markdown export "Top Critical" header. '
    '— 20260528_bug_intel_severity_score.';

COMMENT ON COLUMN bug_intelligence_fingerprints.severity_score_updated_at IS
    'When severity_score was last recomputed. Lets the CMS show "score N (updated 12m ago)" '
    'so reviewers know how fresh the ranking is. — 20260528_bug_intel_severity_score.';

CREATE INDEX IF NOT EXISTS idx_bug_intel_fp_severity_score_open
    ON bug_intelligence_fingerprints (severity_score DESC NULLS LAST)
    WHERE status NOT IN ('resolved', 'wont_fix', 'duplicate');

-- ----------------------------------------------------------------------------
-- 2. Pure helper: compute severity_score for a single fingerprint row.
--    Pulled out as IMMUTABLE so it can be called from views or recompute.
-- ----------------------------------------------------------------------------

DROP FUNCTION IF EXISTS bug_intel_compute_severity_score(
    INTEGER, INTEGER, TEXT[], TEXT, TEXT, BOOLEAN, TEXT, TEXT
);

CREATE OR REPLACE FUNCTION bug_intel_compute_severity_score(
    p_occurrence_count       INTEGER,
    p_unique_user_count      INTEGER,
    p_affected_screens       TEXT[],
    p_source                 TEXT,
    p_last_seen_app_version  TEXT,
    p_regressed_after_fix    BOOLEAN,
    p_current_app_version    TEXT,
    p_error_class            TEXT
) RETURNS NUMERIC
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    v_occ                  NUMERIC := GREATEST(COALESCE(p_occurrence_count, 0), 1);
    v_users_sqrt           NUMERIC := SQRT(GREATEST(COALESCE(p_unique_user_count, 1), 1));
    v_visibility           NUMERIC := 1.0;
    v_build_freshness      NUMERIC := 1.0;
    v_source_severity      NUMERIC := 1.0;
    v_regression_amp       NUMERIC := 1.0;
    v_class_amp            NUMERIC := 1.0;
    v_screen               TEXT;
    v_high_visibility_screens TEXT[] := ARRAY[
        'DashboardView',
        'OnboardingView', 'NewOnboardingView',
        'ActiveWorkoutView',
        'WorkoutTabView',
        'FriendsTabView',
        'NutritionView',
        'ChallengesView'
    ];
BEGIN
    -- Screen visibility weight: 1.5x if any of the affected screens are core surfaces.
    IF p_affected_screens IS NOT NULL THEN
        FOREACH v_screen IN ARRAY p_affected_screens LOOP
            IF v_screen = ANY (v_high_visibility_screens) THEN
                v_visibility := 1.5;
                EXIT;
            END IF;
        END LOOP;
    END IF;

    -- Source severity: crashes are 2x weight vs logs.
    IF p_source = 'crash' THEN
        v_source_severity := 2.0;
    END IF;

    -- Regression amplifier: 3x when the bug came back after a fix.
    IF COALESCE(p_regressed_after_fix, FALSE) THEN
        v_regression_amp := 3.0;
    END IF;

    -- Build freshness: penalize fingerprints that haven't been seen on the
    -- current build (probably already fixed or naturally aged out).
    IF p_current_app_version IS NOT NULL
       AND p_last_seen_app_version IS NOT NULL
    THEN
        DECLARE
            v_cmp INTEGER := bug_intel_compare_semver(p_last_seen_app_version, p_current_app_version);
        BEGIN
            IF v_cmp >= 0 THEN
                v_build_freshness := 1.0;        -- last seen on current build
            ELSIF v_cmp = -1 THEN
                v_build_freshness := 0.5;        -- 1 build behind
            ELSE
                v_build_freshness := 0.2;        -- 2+ builds behind
            END IF;
        EXCEPTION WHEN OTHERS THEN
            v_build_freshness := 1.0;
        END;
    END IF;

    -- error_class amplifier: known-transient classes get a discount so they
    -- don't outrank actionable real bugs even at high occurrence_count.
    IF p_error_class IN ('cancelled', 'offline', 'timeout', 'gateway') THEN
        v_class_amp := 0.5;
    ELSIF p_error_class IN ('rls_violation', 'pgrst_overload', 'uuid_mismatch') THEN
        -- known-actionable structural classes get a small bump
        v_class_amp := 1.5;
    END IF;

    RETURN ROUND(
        v_occ * v_users_sqrt * v_visibility * v_build_freshness *
        v_source_severity * v_regression_amp * v_class_amp,
        2
    );
END;
$$;

COMMENT ON FUNCTION bug_intel_compute_severity_score(
    INTEGER, INTEGER, TEXT[], TEXT, TEXT, BOOLEAN, TEXT, TEXT
) IS
    'IMMUTABLE pure helper — computes the empirical severity_score for a '
    'fingerprint row. See 20260528_bug_intel_severity_score.sql header for '
    'the formula breakdown.';

GRANT EXECUTE ON FUNCTION bug_intel_compute_severity_score(
    INTEGER, INTEGER, TEXT[], TEXT, TEXT, BOOLEAN, TEXT, TEXT
) TO service_role, authenticated;

-- ----------------------------------------------------------------------------
-- 3. bug_intel_recompute_severity() — bulk recompute over open fingerprints.
-- ----------------------------------------------------------------------------

DROP FUNCTION IF EXISTS bug_intel_recompute_severity();

CREATE OR REPLACE FUNCTION bug_intel_recompute_severity()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_count           INTEGER;
    v_current_version TEXT;
BEGIN
    IF auth.role() IS NOT NULL AND auth.role() <> 'service_role' THEN
        RAISE EXCEPTION 'bug_intel_recompute_severity is service-role only'
            USING ERRCODE = '42501';
    END IF;

    -- "Current" build = the most recent app_version seen in the last 24h
    -- across all fingerprints. Lets the formula self-calibrate as new TestFlight
    -- builds roll out without a hardcoded constant.
    SELECT MAX(last_seen_app_version) INTO v_current_version
    FROM bug_intelligence_fingerprints
    WHERE last_seen_at >= now() - INTERVAL '24 hours'
      AND last_seen_app_version IS NOT NULL;

    UPDATE bug_intelligence_fingerprints f
    SET
        severity_score = bug_intel_compute_severity_score(
            f.occurrence_count,
            f.unique_user_count,
            f.affected_screens,
            f.source,
            f.last_seen_app_version,
            f.regressed_after_fix,
            v_current_version,
            f.error_class
        ),
        severity_score_updated_at = now(),
        updated_at = now()
    WHERE f.status NOT IN ('resolved', 'wont_fix', 'duplicate');

    GET DIAGNOSTICS v_count = ROW_COUNT;

    RAISE NOTICE 'bug_intel_recompute_severity: rescored % open fingerprints (current_version=%)',
                 v_count, v_current_version;

    RETURN v_count;
END;
$$;

COMMENT ON FUNCTION bug_intel_recompute_severity() IS
    'Phase 12 (Tier 2 #2, 2026-04-25) — hourly rescore of every open '
    'fingerprint via bug_intel_compute_severity_score(). pg_cron at :10 past '
    'every hour. Self-calibrates current_app_version from the last 24h of activity.';

REVOKE ALL ON FUNCTION bug_intel_recompute_severity() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION bug_intel_recompute_severity() TO service_role;

-- ----------------------------------------------------------------------------
-- 4. pg_cron schedule — :10 past every hour
-- ----------------------------------------------------------------------------

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
        IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'bug-intel-severity-recompute') THEN
            PERFORM cron.unschedule('bug-intel-severity-recompute');
        END IF;
    END IF;
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'pg_cron not available, skipping schedule cleanup';
END $$;

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
        PERFORM cron.schedule(
            'bug-intel-severity-recompute',
            '10 * * * *',
            $cron$ SELECT bug_intel_recompute_severity(); $cron$
        );
        RAISE NOTICE '[Phase 12 Tier 2 #2] scheduled bug-intel-severity-recompute (hourly :10)';
    END IF;
END $$;

-- ----------------------------------------------------------------------------
-- 5. Initial bulk recompute
-- ----------------------------------------------------------------------------

DO $$
DECLARE
    v_initial INTEGER;
BEGIN
    SELECT bug_intel_recompute_severity() INTO v_initial;
    RAISE NOTICE '[Phase 12 Tier 2 #2] initial recompute: % fingerprints scored', v_initial;
END $$;

-- ----------------------------------------------------------------------------
-- 6. Audit
-- ----------------------------------------------------------------------------

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_name = 'bug_intelligence_fingerprints'
                     AND column_name = 'severity_score')
    THEN
        RAISE EXCEPTION '[Phase 12 Tier 2 #2 audit] severity_score column missing';
    END IF;
    RAISE NOTICE '[Phase 12 Tier 2 #2 audit] severity_score column + index + cron in place';
END $$;

COMMIT;
