-- Bug-intel sweep Cluster I: measurement layer.
--
-- "How do we know this sweep actually fixed things?" — we need to measure.
-- This migration creates:
--   1. `performance_metrics` table — one row per signpost end.
--   2. Daily rollup view `performance_metrics_daily` with p50/p95/p99 by op.
--   3. `snapshot_bug_intel_baseline()` RPC — captures fingerprint counts
--      per cluster so we can compare "before sweep" vs "after sweep".
--   4. `bug_intel_improvement_tracker` view — reads the baseline snapshot
--      alongside current counts and exposes deltas (absolute + %).
--
-- All RLS'd (security_invoker on views, owner-filtered policies).

BEGIN;

-- =========================================================================
-- 1. performance_metrics
-- =========================================================================

CREATE TABLE IF NOT EXISTS performance_metrics (
    id           BIGSERIAL PRIMARY KEY,
    user_id      UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    op           TEXT NOT NULL,
    elapsed_ms   INTEGER NOT NULL,
    started_at   TIMESTAMPTZ NOT NULL,
    endpoint     TEXT,
    extra        JSONB,
    app_version  TEXT,
    os_version   TEXT,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- The `(op, started_at)` index carries the daily rollup query.
-- The GIN index on `extra` supports filtering by arbitrary signpost tags.
CREATE INDEX IF NOT EXISTS idx_perf_metrics_op_started
    ON performance_metrics (op, started_at DESC);
CREATE INDEX IF NOT EXISTS idx_perf_metrics_user_op
    ON performance_metrics (user_id, op, started_at DESC);
CREATE INDEX IF NOT EXISTS idx_perf_metrics_extra
    ON performance_metrics USING GIN (extra);

ALTER TABLE performance_metrics ENABLE ROW LEVEL SECURITY;

-- Users can insert their own rows.
DROP POLICY IF EXISTS "performance_metrics_insert_own" ON performance_metrics;
CREATE POLICY "performance_metrics_insert_own"
    ON performance_metrics FOR INSERT
    WITH CHECK (auth.uid() = user_id OR user_id IS NULL);

-- Users can read their own rows (admin dashboards read via service role).
DROP POLICY IF EXISTS "performance_metrics_select_own" ON performance_metrics;
CREATE POLICY "performance_metrics_select_own"
    ON performance_metrics FOR SELECT
    USING (auth.uid() = user_id OR user_id IS NULL);

-- No UPDATE / DELETE policies — metrics are write-once.

-- =========================================================================
-- 2. Daily rollup view — performance_metrics_daily
-- =========================================================================
-- security_invoker=on so RLS is evaluated against the querying user,
-- matching supabase-rules §2 for views over RLS'd tables.

CREATE OR REPLACE VIEW performance_metrics_daily
    WITH (security_invoker = on)
    AS
SELECT
    date_trunc('day', started_at AT TIME ZONE 'UTC') AS day,
    op,
    COUNT(*) AS sample_count,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY elapsed_ms) AS p50_ms,
    PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY elapsed_ms) AS p95_ms,
    PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY elapsed_ms) AS p99_ms,
    MIN(elapsed_ms) AS min_ms,
    MAX(elapsed_ms) AS max_ms
FROM performance_metrics
GROUP BY 1, 2;

-- =========================================================================
-- 3. Bug-intel baseline snapshot
-- =========================================================================
-- Stores a point-in-time "before sweep" fingerprint count per cluster so
-- we can prove the fixes worked. Rows are keyed by (label, captured_at).
-- The RPC is SECURITY DEFINER because it needs to read across all users'
-- bug_intelligence_fingerprints.

CREATE TABLE IF NOT EXISTS bug_intel_baseline_snapshots (
    id               BIGSERIAL PRIMARY KEY,
    label            TEXT NOT NULL,
    captured_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    cluster_code     TEXT NOT NULL,
    open_fingerprint_count INTEGER NOT NULL,
    total_occurrences       INTEGER NOT NULL,
    note             TEXT
);

CREATE INDEX IF NOT EXISTS idx_bug_intel_baseline_label
    ON bug_intel_baseline_snapshots (label, captured_at DESC);

ALTER TABLE bug_intel_baseline_snapshots ENABLE ROW LEVEL SECURITY;

-- Service role only — baselines are admin-only data.
DROP POLICY IF EXISTS "bug_intel_baseline_service_only" ON bug_intel_baseline_snapshots;
CREATE POLICY "bug_intel_baseline_service_only"
    ON bug_intel_baseline_snapshots FOR ALL
    USING (auth.role() = 'service_role')
    WITH CHECK (auth.role() = 'service_role');

-- =========================================================================
-- 4. snapshot_bug_intel_baseline(label TEXT)
-- =========================================================================
-- Captures the current count of bug_intelligence_fingerprints bucketed
-- into our 7 known clusters. Call once "before sweep", then again
-- "one week after sweep". Diff is surfaced in `bug_intel_improvement_tracker`.
--
-- Cluster bucketing rules (best-effort text match over fingerprint
-- `sample_message` + `normalized_message` + `error_domain`). New
-- fingerprints that don't match any cluster go to bucket `uncategorized`.
--
-- NOTE: `bug_intelligence_fingerprints` does NOT have a `title` column —
-- that lives on `bug_intelligence_reports`. Fingerprints carry the raw
-- `sample_message` + normalized variant + an `error_domain` string, which
-- are what we pattern-match against here.
--
-- Status filter: fingerprints don't have an `open` status — the values
-- are `new` / `triaged` / `in_progress` / `resolved` / `wont_fix` /
-- `duplicate`. "Open" here means anything NOT in the terminal trio.

DROP FUNCTION IF EXISTS snapshot_bug_intel_baseline(TEXT);
CREATE OR REPLACE FUNCTION snapshot_bug_intel_baseline(p_label TEXT)
RETURNS TABLE (cluster_code TEXT, open_fingerprint_count INT, total_occurrences INT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    r RECORD;
BEGIN
    IF auth.role() <> 'service_role' THEN
        RAISE EXCEPTION 'snapshot_bug_intel_baseline is service-role only';
    END IF;

    FOR r IN
        WITH src AS (
            SELECT
                LOWER(COALESCE(f.sample_message, '') || ' '
                   || COALESCE(f.normalized_message, '') || ' '
                   || COALESCE(f.error_domain, '')) AS hay,
                COALESCE(f.occurrence_count, 1) AS occ
              FROM bug_intelligence_fingerprints f
             WHERE f.status NOT IN ('resolved', 'wont_fix', 'duplicate')
        ),
        classified AS (
            SELECT
                CASE
                    WHEN hay LIKE '%main thread%' OR hay LIKE '%freeze%' OR hay LIKE '%watchdog%' THEN 'A_main_thread'
                    WHEN hay LIKE '%42501%' OR hay LIKE '%row-level security%' OR hay LIKE '% rls %' THEN 'B_rls'
                    WHEN hay LIKE '%42883%' OR hay LIKE '%uuid = text%' OR hay LIKE '%operator does not exist%' THEN 'C_uuid'
                    WHEN hay LIKE '%401%' OR hay LIKE '%unauthorized%' OR hay LIKE '%jwt%' THEN 'D_startup_timeout'
                    WHEN hay LIKE '%sigsegv%' OR hay LIKE '%cfstring%' OR hay LIKE '%coredata%' OR hay LIKE '%core data%' THEN 'E_crashes'
                    WHEN hay LIKE '%pgrst202%' OR hay LIKE '%post_workout_activity%' OR hay LIKE '%could not choose%' THEN 'F_overloads'
                    WHEN hay LIKE '%friend%' OR hay LIKE '%challenge%' OR hay LIKE '%activity_feed%' OR hay LIKE '%activity feed%' THEN 'G_social'
                    ELSE 'uncategorized'
                END AS bucket,
                occ
              FROM src
        )
        SELECT bucket, COUNT(*)::INT AS fp_count, SUM(occ)::INT AS occ_total
          FROM classified
         GROUP BY bucket
    LOOP
        INSERT INTO bug_intel_baseline_snapshots (label, cluster_code, open_fingerprint_count, total_occurrences, note)
        VALUES (p_label, r.bucket, r.fp_count, r.occ_total,
                'snapshot_bug_intel_baseline (' || to_char(now(), 'YYYY-MM-DD HH24:MI UTC') || ')');
        cluster_code := r.bucket;
        open_fingerprint_count := r.fp_count;
        total_occurrences := r.occ_total;
        RETURN NEXT;
    END LOOP;
END;
$$;

GRANT EXECUTE ON FUNCTION snapshot_bug_intel_baseline(TEXT) TO service_role;

-- =========================================================================
-- 5. bug_intel_improvement_tracker — view
-- =========================================================================
-- Joins the most recent two snapshots per cluster and exposes deltas.
-- The admin CMS queries this view to render the Improvement Tracker tile.

CREATE OR REPLACE VIEW bug_intel_improvement_tracker
    WITH (security_invoker = on)
    AS
WITH ranked AS (
    SELECT s.*,
           ROW_NUMBER() OVER (PARTITION BY cluster_code ORDER BY captured_at DESC) AS rn
      FROM bug_intel_baseline_snapshots s
),
latest AS (SELECT * FROM ranked WHERE rn = 1),
prev   AS (SELECT * FROM ranked WHERE rn = 2)
SELECT
    latest.cluster_code,
    latest.captured_at                            AS latest_captured_at,
    latest.open_fingerprint_count                 AS latest_open_count,
    latest.total_occurrences                      AS latest_occurrence_total,
    prev.captured_at                              AS prev_captured_at,
    prev.open_fingerprint_count                   AS prev_open_count,
    prev.total_occurrences                        AS prev_occurrence_total,
    (latest.open_fingerprint_count - COALESCE(prev.open_fingerprint_count, 0))                     AS open_delta,
    (latest.total_occurrences       - COALESCE(prev.total_occurrences, 0))                         AS occurrence_delta,
    CASE WHEN COALESCE(prev.open_fingerprint_count, 0) = 0 THEN NULL
         ELSE ROUND(100.0 * (latest.open_fingerprint_count - prev.open_fingerprint_count)
                          / prev.open_fingerprint_count, 1)
    END                                                                                           AS open_delta_pct
FROM latest
LEFT JOIN prev USING (cluster_code);

COMMIT;

-- =========================================================================
-- 6. Prime baseline ("before sweep") snapshot. Re-run once "after sweep"
-- to populate the improvement tracker view.
-- =========================================================================

DO $$
DECLARE
    row_count INT;
BEGIN
    SELECT COUNT(*) INTO row_count FROM snapshot_bug_intel_baseline('before_sweep_2026_04_23');
    RAISE NOTICE '[20260514] Primed before-sweep baseline with % cluster rows.', row_count;
END $$;
