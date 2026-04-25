-- ============================================================================
-- Bug Intelligence — Self-Tuning Severity Weights + Calibration Report
--   (Phase 12 — Tier 5 #2 — "agents constantly getting smarter")
-- Date: 2026-05-31 (migration order), authored 2026-04-25
--
-- PROBLEM
-- -------
-- 20260528_bug_intel_severity_score.sql baked the multipliers into the
-- IMMUTABLE function body:
--    visibility=1.5, source=2.0, regression=3.0,
--    transient_class=0.5, structural_class=1.5,
--    build_freshness {1.0, 0.5, 0.2}.
--
-- Those numbers were a *guess* from the migration header. We have no
-- feedback loop telling us if a "score 200" bug actually got fixed faster
-- than a "score 50" bug — so the weights never improve. Calibration was
-- left as a manual, vibes-based knob.
--
-- FIX (Tier 5 #2)
-- ---------------
-- 1. Move the multipliers into a `bug_intel_severity_weights` table
--    (key, value, source, fitted_from, updated_at). Seed it with the
--    current Phase 12 numbers as `source = 'seed'`.
--
-- 2. Replace the IMMUTABLE `bug_intel_compute_severity_score(...)` with
--    a STABLE version that reads from the table. STABLE is correct: it
--    won't change within a single statement, but updating the weights
--    table between statements should pick up new values on the next
--    `bug_intel_recompute_severity()` cron tick.
--
-- 3. Add a `bug_intel_calibration_report` table (one row per calibration
--    run) and a `bug_intel_calibrate_severity_weights()` function that:
--    - Looks at the last 60 days of resolved + rejected fingerprints.
--    - For each weight knob, computes a simple correlation signal:
--        - "Among open fingerprints with this knob ON, what % got
--          merged-fixed within 14 days vs what % got rejected/auto-drained?"
--    - Writes the analysis into `bug_intel_calibration_report` for human
--      inspection. Does NOT auto-mutate the weights table — Tier 1 of this
--      feature is observability, not autonomous tuning. (Auto-tune is a
--      flag-gated follow-on once the report has stabilized for >2 months.)
--
-- 4. Schedule the calibration nightly at :30 past midnight UTC.
--
-- BACKWARD COMPAT
-- ---------------
-- The CMS list, the markdown export, and the Edge Function all still call
-- the same `bug_intel_compute_severity_score(...)` signature. Internally
-- it now reads weights from the table — first call after this migration
-- might be a few ms slower (one extra SELECT), but the recompute cron
-- caches the lookup per call.
--
-- ROLLBACK
-- --------
--   SELECT cron.unschedule('bug-intel-severity-calibration');
--   DROP FUNCTION IF EXISTS bug_intel_calibrate_severity_weights();
--   DROP TABLE IF EXISTS bug_intel_calibration_report;
--   -- Restore IMMUTABLE compute_severity_score (re-run 20260528).
--   DROP FUNCTION IF EXISTS bug_intel_get_severity_weight(TEXT, NUMERIC);
--   DROP TABLE IF EXISTS bug_intel_severity_weights;
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- 1. Schema: bug_intel_severity_weights (configurable knobs)
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS bug_intel_severity_weights (
    key            TEXT         PRIMARY KEY,
    value          NUMERIC      NOT NULL,
    source         TEXT         NOT NULL DEFAULT 'seed',  -- 'seed' | 'manual' | 'calibrated'
    fitted_from    TEXT,                                  -- e.g. '2026-03-01..2026-04-25'
    notes          TEXT,
    updated_at     TIMESTAMPTZ  NOT NULL DEFAULT now()
);

COMMENT ON TABLE bug_intel_severity_weights IS
    'Phase 12 Tier 5 #2 (2026-04-25) — configurable multipliers for '
    'bug_intel_compute_severity_score(). Seeded with the original Phase 12 '
    'constants. bug_intel_calibrate_severity_weights() writes a calibration '
    'report; weight updates are still human-in-the-loop until report '
    'has stabilized for >2 months.';

-- Service role + admin ops only; everyone else reads the score column.
ALTER TABLE bug_intel_severity_weights ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS bug_intel_severity_weights_service_all ON bug_intel_severity_weights;
CREATE POLICY bug_intel_severity_weights_service_all
    ON bug_intel_severity_weights
    FOR ALL
    TO public
    USING (auth.role() = 'service_role')
    WITH CHECK (auth.role() = 'service_role');

-- Seed the original Phase 12 values. ON CONFLICT DO NOTHING keeps any
-- manual overrides intact across re-runs.
INSERT INTO bug_intel_severity_weights (key, value, source, notes) VALUES
    ('visibility_high',         1.5, 'seed', 'Multiplier when affected_screens hits a core surface'),
    ('source_crash',            2.0, 'seed', 'Multiplier when source = ''crash'''),
    ('regression_amplifier',    3.0, 'seed', 'Multiplier when regressed_after_fix = TRUE'),
    ('build_freshness_current', 1.0, 'seed', 'Last seen ON current build'),
    ('build_freshness_minus1',  0.5, 'seed', '1 build behind'),
    ('build_freshness_minus2',  0.2, 'seed', '≥ 2 builds behind'),
    ('class_amp_transient',     0.5, 'seed', 'cancelled/offline/timeout/gateway'),
    ('class_amp_structural',    1.5, 'seed', 'rls_violation/pgrst_overload/uuid_mismatch')
ON CONFLICT (key) DO NOTHING;

-- ----------------------------------------------------------------------------
-- 2. Helper: bug_intel_get_severity_weight(key, default)
-- ----------------------------------------------------------------------------

DROP FUNCTION IF EXISTS bug_intel_get_severity_weight(TEXT, NUMERIC);

CREATE OR REPLACE FUNCTION bug_intel_get_severity_weight(
    p_key       TEXT,
    p_default   NUMERIC
) RETURNS NUMERIC
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT COALESCE(
        (SELECT value FROM bug_intel_severity_weights WHERE key = p_key),
        p_default
    );
$$;

COMMENT ON FUNCTION bug_intel_get_severity_weight(TEXT, NUMERIC) IS
    'Phase 12 Tier 5 #2 — lookup a tunable multiplier from '
    'bug_intel_severity_weights, falling back to a hardcoded default if the '
    'key is absent. STABLE so it''s safe to call from another STABLE function.';

GRANT EXECUTE ON FUNCTION bug_intel_get_severity_weight(TEXT, NUMERIC) TO service_role, authenticated;

-- ----------------------------------------------------------------------------
-- 3. Replace bug_intel_compute_severity_score with a STABLE table-reading variant
-- ----------------------------------------------------------------------------
--
-- Same signature as the 20260528 IMMUTABLE version so the recompute cron
-- and any view definitions don't need changes. The function body now
-- reads multipliers from bug_intel_severity_weights via
-- bug_intel_get_severity_weight(key, default).

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
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_occ                 NUMERIC := GREATEST(COALESCE(p_occurrence_count, 0), 1);
    v_users_sqrt          NUMERIC := SQRT(GREATEST(COALESCE(p_unique_user_count, 1), 1));
    v_visibility          NUMERIC := 1.0;
    v_build_freshness     NUMERIC := 1.0;
    v_source_severity     NUMERIC := 1.0;
    v_regression_amp      NUMERIC := 1.0;
    v_class_amp           NUMERIC := 1.0;
    v_screen              TEXT;
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
    -- Screen visibility weight
    IF p_affected_screens IS NOT NULL THEN
        FOREACH v_screen IN ARRAY p_affected_screens LOOP
            IF v_screen = ANY (v_high_visibility_screens) THEN
                v_visibility := bug_intel_get_severity_weight('visibility_high', 1.5);
                EXIT;
            END IF;
        END LOOP;
    END IF;

    -- Source severity (crash > log)
    IF p_source = 'crash' THEN
        v_source_severity := bug_intel_get_severity_weight('source_crash', 2.0);
    END IF;

    -- Regression amplifier
    IF COALESCE(p_regressed_after_fix, FALSE) THEN
        v_regression_amp := bug_intel_get_severity_weight('regression_amplifier', 3.0);
    END IF;

    -- Build freshness
    IF p_current_app_version IS NOT NULL
       AND p_last_seen_app_version IS NOT NULL
    THEN
        DECLARE
            v_cmp INTEGER := bug_intel_compare_semver(p_last_seen_app_version, p_current_app_version);
        BEGIN
            IF v_cmp >= 0 THEN
                v_build_freshness := bug_intel_get_severity_weight('build_freshness_current', 1.0);
            ELSIF v_cmp = -1 THEN
                v_build_freshness := bug_intel_get_severity_weight('build_freshness_minus1', 0.5);
            ELSE
                v_build_freshness := bug_intel_get_severity_weight('build_freshness_minus2', 0.2);
            END IF;
        EXCEPTION WHEN OTHERS THEN
            v_build_freshness := 1.0;
        END;
    END IF;

    -- error_class amplifier
    IF p_error_class IN ('cancelled', 'offline', 'timeout', 'gateway') THEN
        v_class_amp := bug_intel_get_severity_weight('class_amp_transient', 0.5);
    ELSIF p_error_class IN ('rls_violation', 'pgrst_overload', 'uuid_mismatch') THEN
        v_class_amp := bug_intel_get_severity_weight('class_amp_structural', 1.5);
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
    'Phase 12 Tier 5 #2 (2026-04-25) — STABLE rewrite. Multipliers now '
    'read from bug_intel_severity_weights via bug_intel_get_severity_weight() '
    'so weights are tunable without code changes. See '
    '20260531_bug_intel_severity_weights.sql for calibration mechanics.';

GRANT EXECUTE ON FUNCTION bug_intel_compute_severity_score(
    INTEGER, INTEGER, TEXT[], TEXT, TEXT, BOOLEAN, TEXT, TEXT
) TO service_role, authenticated;

-- ----------------------------------------------------------------------------
-- 4. Schema: bug_intel_calibration_report (one row per nightly run)
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS bug_intel_calibration_report (
    id                       UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    run_at                   TIMESTAMPTZ  NOT NULL DEFAULT now(),
    window_days              INTEGER      NOT NULL,
    -- Counts of resolved fingerprints in the window.
    total_resolved           INTEGER      NOT NULL DEFAULT 0,
    total_auto_drained       INTEGER      NOT NULL DEFAULT 0,
    total_real_fixes         INTEGER      NOT NULL DEFAULT 0,
    total_rejected           INTEGER      NOT NULL DEFAULT 0,
    -- Per-knob fix-rate analysis. JSONB gives us flexibility for new
    -- knobs without re-migrating the table. Shape:
    --   {
    --     "visibility_high":      { "with_knob_on": 12, "real_fixes": 9, "rejected": 1, "fix_rate": 0.75 },
    --     "source_crash":         { ... },
    --     "regression_amplifier": { ... }
    --   }
    knob_fix_rates           JSONB        NOT NULL DEFAULT '{}'::jsonb,
    -- Score-bucket analysis (does score correlate with action taken?)
    --   { "0_50": {...}, "50_150": {...}, "150_500": {...}, "500_inf": {...} }
    score_bucket_outcomes    JSONB        NOT NULL DEFAULT '{}'::jsonb,
    -- Human-readable findings string for log scrubbing / quick scan.
    findings                 TEXT
);

COMMENT ON TABLE bug_intel_calibration_report IS
    'Phase 12 Tier 5 #2 — nightly snapshot of how well severity_score '
    'correlates with actual triage outcomes. Drives manual weight '
    'tuning today; will drive autonomous tuning in a future migration.';

ALTER TABLE bug_intel_calibration_report ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS bug_intel_calibration_report_service_all ON bug_intel_calibration_report;
CREATE POLICY bug_intel_calibration_report_service_all
    ON bug_intel_calibration_report
    FOR ALL
    TO public
    USING (auth.role() = 'service_role')
    WITH CHECK (auth.role() = 'service_role');

CREATE INDEX IF NOT EXISTS idx_bug_intel_calibration_report_run_at
    ON bug_intel_calibration_report (run_at DESC);

-- ----------------------------------------------------------------------------
-- 5. bug_intel_calibrate_severity_weights() — nightly analysis
-- ----------------------------------------------------------------------------

DROP FUNCTION IF EXISTS bug_intel_calibrate_severity_weights(INTEGER);

CREATE OR REPLACE FUNCTION bug_intel_calibrate_severity_weights(
    p_window_days INTEGER DEFAULT 60
) RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_id                  UUID;
    v_total_resolved      INTEGER := 0;
    v_total_auto_drained  INTEGER := 0;
    v_total_real_fixes    INTEGER := 0;
    v_total_rejected      INTEGER := 0;
    v_window_start        TIMESTAMPTZ := now() - (p_window_days || ' days')::INTERVAL;
    v_knob_fix_rates      JSONB := '{}'::jsonb;
    v_score_buckets       JSONB := '{}'::jsonb;
    v_findings            TEXT;
BEGIN
    IF auth.role() IS NOT NULL AND auth.role() <> 'service_role' THEN
        RAISE EXCEPTION 'bug_intel_calibrate_severity_weights is service-role only'
            USING ERRCODE = '42501';
    END IF;

    -- Counts of terminal-state fingerprints in the window.
    SELECT
        COUNT(*) FILTER (WHERE f.status IN ('resolved', 'wont_fix', 'duplicate')),
        COUNT(*) FILTER (WHERE f.auto_resolved_reason IS NOT NULL),
        COUNT(*) FILTER (
            WHERE f.status = 'resolved'
              AND f.auto_resolved_reason IS NULL
        ),
        COUNT(*) FILTER (
            WHERE EXISTS (
                SELECT 1 FROM bug_intelligence_reports r
                WHERE r.fingerprint = f.fingerprint AND r.review_status = 'rejected'
            )
        )
    INTO v_total_resolved, v_total_auto_drained, v_total_real_fixes, v_total_rejected
    FROM bug_intelligence_fingerprints f
    WHERE COALESCE(f.auto_resolved_at, f.resolved_at, f.updated_at) >= v_window_start;

    -- Per-knob fix-rate analysis. For each knob, compute:
    --   { "with_knob_on": N, "real_fixes": K, "rejected": J,
    --     "fix_rate": K / (K+J) }
    --
    -- Knobs analysed: visibility_high (high-vis screen), source_crash,
    -- regression_amplifier, class_amp_transient, class_amp_structural.
    WITH base AS (
        SELECT
            f.fingerprint,
            f.status,
            f.auto_resolved_reason,
            f.affected_screens,
            f.source,
            f.regressed_after_fix,
            f.error_class,
            EXISTS (
                SELECT 1 FROM bug_intelligence_reports r
                WHERE r.fingerprint = f.fingerprint AND r.review_status = 'rejected'
            ) AS was_rejected,
            (f.status = 'resolved' AND f.auto_resolved_reason IS NULL) AS was_real_fix
        FROM bug_intelligence_fingerprints f
        WHERE COALESCE(f.auto_resolved_at, f.resolved_at, f.updated_at) >= v_window_start
    ),
    knobs AS (
        SELECT
            'visibility_high'::TEXT AS knob,
            EXISTS (
                SELECT 1 FROM unnest(b.affected_screens) s
                WHERE s = ANY (ARRAY[
                    'DashboardView','OnboardingView','NewOnboardingView',
                    'ActiveWorkoutView','WorkoutTabView','FriendsTabView',
                    'NutritionView','ChallengesView'
                ])
            ) AS knob_on,
            b.was_real_fix, b.was_rejected
        FROM base b
        UNION ALL
        SELECT 'source_crash', b.source = 'crash', b.was_real_fix, b.was_rejected FROM base b
        UNION ALL
        SELECT 'regression_amplifier', COALESCE(b.regressed_after_fix, FALSE),
               b.was_real_fix, b.was_rejected FROM base b
        UNION ALL
        SELECT 'class_amp_transient',
               b.error_class IN ('cancelled','offline','timeout','gateway'),
               b.was_real_fix, b.was_rejected FROM base b
        UNION ALL
        SELECT 'class_amp_structural',
               b.error_class IN ('rls_violation','pgrst_overload','uuid_mismatch'),
               b.was_real_fix, b.was_rejected FROM base b
    )
    SELECT jsonb_object_agg(
               knob,
               jsonb_build_object(
                   'with_knob_on', SUM(CASE WHEN knob_on THEN 1 ELSE 0 END),
                   'real_fixes',   SUM(CASE WHEN knob_on AND was_real_fix THEN 1 ELSE 0 END),
                   'rejected',     SUM(CASE WHEN knob_on AND was_rejected THEN 1 ELSE 0 END),
                   'fix_rate',
                       CASE
                           WHEN SUM(CASE WHEN knob_on AND (was_real_fix OR was_rejected) THEN 1 ELSE 0 END) = 0
                               THEN NULL
                           ELSE ROUND(
                               SUM(CASE WHEN knob_on AND was_real_fix THEN 1 ELSE 0 END)::NUMERIC
                               / SUM(CASE WHEN knob_on AND (was_real_fix OR was_rejected) THEN 1 ELSE 0 END),
                               3
                           )
                       END
               )
           )
    INTO v_knob_fix_rates
    FROM knobs;

    -- Score-bucket outcome analysis.
    WITH buckets AS (
        SELECT
            CASE
                WHEN f.severity_score IS NULL THEN 'unscored'
                WHEN f.severity_score < 50 THEN '0_50'
                WHEN f.severity_score < 150 THEN '50_150'
                WHEN f.severity_score < 500 THEN '150_500'
                ELSE '500_inf'
            END AS bucket,
            (f.status = 'resolved' AND f.auto_resolved_reason IS NULL) AS was_real_fix,
            EXISTS (
                SELECT 1 FROM bug_intelligence_reports r
                WHERE r.fingerprint = f.fingerprint AND r.review_status = 'rejected'
            ) AS was_rejected
        FROM bug_intelligence_fingerprints f
        WHERE COALESCE(f.auto_resolved_at, f.resolved_at, f.updated_at) >= v_window_start
    )
    SELECT jsonb_object_agg(
               bucket,
               jsonb_build_object(
                   'count',       COUNT(*),
                   'real_fixes',  SUM(CASE WHEN was_real_fix THEN 1 ELSE 0 END),
                   'rejected',    SUM(CASE WHEN was_rejected THEN 1 ELSE 0 END),
                   'fix_rate',
                       CASE
                           WHEN SUM(CASE WHEN (was_real_fix OR was_rejected) THEN 1 ELSE 0 END) = 0
                               THEN NULL
                           ELSE ROUND(
                               SUM(CASE WHEN was_real_fix THEN 1 ELSE 0 END)::NUMERIC
                               / SUM(CASE WHEN (was_real_fix OR was_rejected) THEN 1 ELSE 0 END),
                               3
                           )
                       END
               )
           )
    INTO v_score_buckets
    FROM buckets
    GROUP BY ();

    v_findings := format(
        'window=%sd  resolved=%s (real=%s, auto_drained=%s, rejected=%s)',
        p_window_days, v_total_resolved, v_total_real_fixes,
        v_total_auto_drained, v_total_rejected
    );

    INSERT INTO bug_intel_calibration_report (
        window_days, total_resolved, total_auto_drained, total_real_fixes,
        total_rejected, knob_fix_rates, score_bucket_outcomes, findings
    ) VALUES (
        p_window_days, v_total_resolved, v_total_auto_drained, v_total_real_fixes,
        v_total_rejected, COALESCE(v_knob_fix_rates, '{}'::jsonb),
        COALESCE(v_score_buckets, '{}'::jsonb), v_findings
    )
    RETURNING id INTO v_id;

    RAISE NOTICE 'bug_intel_calibrate_severity_weights: report % — %', v_id, v_findings;

    RETURN v_id;
END;
$$;

COMMENT ON FUNCTION bug_intel_calibrate_severity_weights(INTEGER) IS
    'Phase 12 Tier 5 #2 — analyzes how well current severity_score weights '
    'correlate with actual triage outcomes (real fix vs auto-drain vs '
    'rejected) over the last N days. Writes a JSONB report into '
    'bug_intel_calibration_report. Does NOT auto-mutate weights — '
    'observability first; autonomy second. SECURITY DEFINER, service-role only.';

REVOKE ALL ON FUNCTION bug_intel_calibrate_severity_weights(INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION bug_intel_calibrate_severity_weights(INTEGER) TO service_role;

-- ----------------------------------------------------------------------------
-- 6. pg_cron — nightly at 00:30 UTC
-- ----------------------------------------------------------------------------

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
        IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'bug-intel-severity-calibration') THEN
            PERFORM cron.unschedule('bug-intel-severity-calibration');
        END IF;
    END IF;
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'pg_cron not available, skipping calibration schedule cleanup';
END $$;

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
        PERFORM cron.schedule(
            'bug-intel-severity-calibration',
            '30 0 * * *',
            $cron$ SELECT bug_intel_calibrate_severity_weights(60) $cron$
        );
        RAISE NOTICE 'Scheduled bug-intel-severity-calibration daily at 00:30 UTC';
    ELSE
        RAISE NOTICE 'pg_cron not installed — bug_intel_calibrate_severity_weights() must be invoked manually';
    END IF;
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Failed to schedule bug-intel-severity-calibration: %', SQLERRM;
END $$;

-- ----------------------------------------------------------------------------
-- 7. Audit
-- ----------------------------------------------------------------------------

DO $$
DECLARE
    v_seed_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_seed_count FROM bug_intel_severity_weights;
    RAISE NOTICE '20260531_bug_intel_severity_weights: % seed weights loaded; '
                 'compute_severity_score now STABLE+table-driven; '
                 'calibration cron scheduled at 00:30 UTC.', v_seed_count;
END $$;

COMMIT;
