-- ============================================================================
-- Bug Intelligence — Resolved History + Similar-Past-Fixes Lookup
--   (Phase 12 — Tier 5 #1 — "agents constantly getting smarter")
-- Date: 2026-05-30 (migration order), authored 2026-04-25
--
-- PROBLEM
-- -------
-- Every Cursor handoff today is a cold-start. When fingerprint X resolves,
-- the fix lives in a PR / migration / commit message — there's no
-- structured trail Claude can read on the *next* fingerprint to ask
-- "have we fixed something like this before, and what was the answer?".
--
-- That means the system never gets smarter at the cross-bug level — it
-- can only get smarter inside one fingerprint (Phase 12 PR-D), which is
-- a per-bug memory, not a pattern memory.
--
-- FIX (Tier 5 #1)
-- ---------------
-- Add an append-only `bug_intel_resolved_history` table that snapshots the
-- key signals at the moment of resolution:
--   - structural_fingerprint, op, error_class, pg_code, http_status, endpoint
--   - last_seen_file / last_seen_function / last_seen_line   (Phase 12 PR-A)
--   - title (from the latest non-rejected report) and summary (one paragraph)
--   - resolution_pr_url, auto_resolved_reason, resolved_at, severity_score
--
-- Snapshotting happens via a row-level AFTER UPDATE trigger on
-- `bug_intelligence_fingerprints`: when status flips into a terminal state
-- (`resolved` / `wont_fix` / `duplicate`), we INSERT a row with the
-- accompanying report context. Idempotent — repeated transitions don't
-- duplicate-insert thanks to the (fingerprint, resolved_at) unique pair.
--
-- An RPC `bug_intel_find_similar_resolutions(...)` returns the top N most-
-- similar past fixes by:
--   1. Same structural_fingerprint  (exact match — strongest signal).
--   2. Same op + error_class        (root-cause pattern match).
--   3. Same op alone                (generic op-level lessons).
--   4. Same error_class alone       (cross-op error class lessons).
--
-- The Edge Function `triage-bugs` calls this RPC for each fingerprint it
-- triages and feeds the top 3 results to Claude as `similar_past_fixes`,
-- and the CMS markdown export adds a "## Similar past fixes" block per
-- report so Cursor walks in already pattern-matched.
--
-- BACKFILL
-- --------
-- 90 days of already-resolved fingerprints get a one-shot snapshot at
-- migration apply time so the system has Day-1 context — the trigger
-- only catches NEW resolutions going forward.
--
-- ROLLBACK
-- --------
--   DROP FUNCTION IF EXISTS bug_intel_find_similar_resolutions(
--       TEXT, TEXT, TEXT, TEXT, INTEGER
--   );
--   DROP FUNCTION IF EXISTS bug_intel_snapshot_resolution() CASCADE;
--   DROP TRIGGER IF EXISTS trg_bug_intel_snapshot_resolution
--       ON bug_intelligence_fingerprints;
--   DROP TABLE IF EXISTS bug_intel_resolved_history;
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- 1. Schema: bug_intel_resolved_history (append-only)
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS bug_intel_resolved_history (
    id                       UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    fingerprint              TEXT         NOT NULL,
    structural_fingerprint   TEXT,
    op                       TEXT,
    error_class              TEXT,
    pg_code                  TEXT,
    http_status              INTEGER,
    endpoint                 TEXT,
    -- Authoritative call-site (Phase 12 PR-A). When the iOS client
    -- captured #file:#line, this is the exact source location.
    last_seen_file           TEXT,
    last_seen_function       TEXT,
    last_seen_line           INTEGER,
    -- Triage context — copied off the latest non-rejected
    -- bug_intelligence_reports row at the moment of resolution.
    title                    TEXT,
    summary                  TEXT,
    agent_owner              TEXT,
    severity                 TEXT,
    -- Resolution provenance.
    severity_score           NUMERIC(12, 2),
    resolution_pr_url        TEXT,
    auto_resolved_reason     TEXT,
    resolved_status          TEXT         NOT NULL,
    resolved_at              TIMESTAMPTZ  NOT NULL,
    -- When this snapshot was taken (= when the trigger fired). Differs
    -- from `resolved_at` only when a backfill runs.
    snapshotted_at           TIMESTAMPTZ  NOT NULL DEFAULT now(),
    UNIQUE (fingerprint, resolved_at)
);

COMMENT ON TABLE bug_intel_resolved_history IS
    'Phase 12 Tier 5 #1 (2026-04-25) — append-only snapshot of every '
    'fingerprint that ever transitioned into a terminal state (resolved / '
    'wont_fix / duplicate). Drives bug_intel_find_similar_resolutions() and '
    'the "Similar past fixes" block in the CMS markdown export. Lets the '
    'next fingerprint that walks through triage learn from past resolutions.';

CREATE INDEX IF NOT EXISTS idx_bug_intel_resolved_history_struct_fp
    ON bug_intel_resolved_history (structural_fingerprint)
    WHERE structural_fingerprint IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_bug_intel_resolved_history_op_class
    ON bug_intel_resolved_history (op, error_class)
    WHERE op IS NOT NULL OR error_class IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_bug_intel_resolved_history_resolved_at
    ON bug_intel_resolved_history (resolved_at DESC);

-- RLS: the table holds production debugging history with file paths and
-- triage notes. Service-role-only writes; admin/authenticated reads via
-- the API helper view (none exposed yet — the CMS reads through the
-- service-role admin route).
ALTER TABLE bug_intel_resolved_history ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS bug_intel_resolved_history_service_all ON bug_intel_resolved_history;
CREATE POLICY bug_intel_resolved_history_service_all
    ON bug_intel_resolved_history
    FOR ALL
    TO public
    USING (auth.role() = 'service_role')
    WITH CHECK (auth.role() = 'service_role');

-- ----------------------------------------------------------------------------
-- 2. Trigger function: snapshot on terminal transition
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION bug_intel_snapshot_resolution()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_terminal CONSTANT TEXT[] := ARRAY['resolved', 'wont_fix', 'duplicate'];
    v_was_terminal     BOOLEAN := COALESCE(OLD.status, '') = ANY (v_terminal);
    v_now_terminal     BOOLEAN := COALESCE(NEW.status, '') = ANY (v_terminal);
    v_resolved_at      TIMESTAMPTZ;
    v_report           RECORD;
BEGIN
    -- Only snapshot when transitioning INTO a terminal state. Repeated
    -- updates within terminal (e.g. status='resolved' → 'resolved') no-op.
    IF v_was_terminal OR NOT v_now_terminal THEN
        RETURN NEW;
    END IF;

    -- Pick the resolution timestamp. Prefer auto_resolved_at (set by the
    -- single-incident drain / migration RPC), else resolved_at, else now.
    v_resolved_at := COALESCE(NEW.auto_resolved_at, NEW.resolved_at, now());

    -- Pick the latest non-rejected, non-stale report on this fingerprint
    -- as the canonical context. Rejected/stale reports were already
    -- thrown out by a human; merged/approved/pending-with-no-replacement
    -- carries the actual diagnosis.
    SELECT
        r.title,
        r.summary,
        r.agent_owner,
        r.severity,
        r.pr_url
    INTO v_report
    FROM bug_intelligence_reports r
    WHERE r.fingerprint = NEW.fingerprint
      AND r.review_status NOT IN ('rejected', 'stale')
    ORDER BY
        CASE r.review_status
            WHEN 'merged'   THEN 0
            WHEN 'approved' THEN 1
            WHEN 'pending'  THEN 2
            ELSE 3
        END,
        r.created_at DESC
    LIMIT 1;

    INSERT INTO bug_intel_resolved_history (
        fingerprint,
        structural_fingerprint,
        op,
        error_class,
        pg_code,
        http_status,
        endpoint,
        last_seen_file,
        last_seen_function,
        last_seen_line,
        title,
        summary,
        agent_owner,
        severity,
        severity_score,
        resolution_pr_url,
        auto_resolved_reason,
        resolved_status,
        resolved_at
    ) VALUES (
        NEW.fingerprint,
        NEW.structural_fingerprint,
        NEW.op,
        NEW.error_class,
        NEW.pg_code,
        NEW.http_status,
        NEW.endpoint,
        NEW.last_seen_file,
        NEW.last_seen_function,
        NEW.last_seen_line,
        v_report.title,
        v_report.summary,
        v_report.agent_owner,
        v_report.severity,
        NEW.severity_score,
        COALESCE(NEW.resolution_pr_url, v_report.pr_url),
        NEW.auto_resolved_reason,
        NEW.status,
        v_resolved_at
    )
    -- Idempotent: a duplicate (fingerprint, resolved_at) means the trigger
    -- ran twice for the same transition (e.g. status flipped resolved →
    -- pending → resolved). Don't double-insert.
    ON CONFLICT (fingerprint, resolved_at) DO NOTHING;

    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION bug_intel_snapshot_resolution() IS
    'Phase 12 Tier 5 #1 — AFTER UPDATE row-level trigger on '
    'bug_intelligence_fingerprints. Snapshots the fingerprint + latest '
    'non-rejected report into bug_intel_resolved_history when status flips '
    'into a terminal state. Idempotent on (fingerprint, resolved_at).';

DROP TRIGGER IF EXISTS trg_bug_intel_snapshot_resolution
    ON bug_intelligence_fingerprints;

CREATE TRIGGER trg_bug_intel_snapshot_resolution
    AFTER UPDATE OF status
    ON bug_intelligence_fingerprints
    FOR EACH ROW
    EXECUTE FUNCTION bug_intel_snapshot_resolution();

-- ----------------------------------------------------------------------------
-- 3. RPC: bug_intel_find_similar_resolutions
-- ----------------------------------------------------------------------------
--
-- Returns the top N most-similar past resolutions, ranked by how strong the
-- match is. The "match_strength" output field lets the caller render a
-- visual hint (★★★ exact / ★★ pattern / ★ generic).
--
--   match_strength = 3  : same structural_fingerprint
--   match_strength = 2  : same (op, error_class) tuple
--   match_strength = 1  : same op (any error_class)
--   match_strength = 1  : same error_class (any op)
--
-- Within the same match_strength tier, sort by resolved_at DESC so the
-- most-recent fix is shown first.
--
-- NULL inputs are tolerated — the function will only match on the fields
-- the caller actually has.

DROP FUNCTION IF EXISTS bug_intel_find_similar_resolutions(
    TEXT, TEXT, TEXT, TEXT, INTEGER
);

CREATE OR REPLACE FUNCTION bug_intel_find_similar_resolutions(
    p_structural_fingerprint TEXT,
    p_op                     TEXT,
    p_error_class            TEXT,
    p_exclude_fingerprint    TEXT DEFAULT NULL,
    p_limit                  INTEGER DEFAULT 5
)
RETURNS TABLE (
    match_strength       INTEGER,
    fingerprint          TEXT,
    structural_fingerprint TEXT,
    op                   TEXT,
    error_class          TEXT,
    title                TEXT,
    summary              TEXT,
    agent_owner          TEXT,
    last_seen_file       TEXT,
    last_seen_line       INTEGER,
    resolution_pr_url    TEXT,
    auto_resolved_reason TEXT,
    resolved_at          TIMESTAMPTZ
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    WITH candidates AS (
        SELECT
            CASE
                WHEN p_structural_fingerprint IS NOT NULL
                     AND h.structural_fingerprint IS NOT NULL
                     AND h.structural_fingerprint = p_structural_fingerprint
                    THEN 3
                WHEN p_op IS NOT NULL
                     AND p_error_class IS NOT NULL
                     AND h.op = p_op
                     AND h.error_class = p_error_class
                    THEN 2
                WHEN p_op IS NOT NULL AND h.op = p_op
                    THEN 1
                WHEN p_error_class IS NOT NULL AND h.error_class = p_error_class
                    THEN 1
                ELSE 0
            END AS match_strength,
            h.fingerprint,
            h.structural_fingerprint,
            h.op,
            h.error_class,
            h.title,
            h.summary,
            h.agent_owner,
            h.last_seen_file,
            h.last_seen_line,
            h.resolution_pr_url,
            h.auto_resolved_reason,
            h.resolved_at
        FROM bug_intel_resolved_history h
        WHERE
            (p_exclude_fingerprint IS NULL OR h.fingerprint <> p_exclude_fingerprint)
            -- Only meaningful resolutions — exclude noise-filter sweeps and
            -- single-incident transients from the "lessons" stream because
            -- those weren't really fixes, they were just drains.
            AND COALESCE(h.auto_resolved_reason, '') NOT IN (
                'transient_single_incident',
                'noise_filter_expanded'
            )
    )
    SELECT
        match_strength,
        fingerprint,
        structural_fingerprint,
        op,
        error_class,
        title,
        summary,
        agent_owner,
        last_seen_file,
        last_seen_line,
        resolution_pr_url,
        auto_resolved_reason,
        resolved_at
    FROM candidates
    WHERE match_strength > 0
    ORDER BY match_strength DESC, resolved_at DESC
    LIMIT GREATEST(COALESCE(p_limit, 5), 1);
$$;

COMMENT ON FUNCTION bug_intel_find_similar_resolutions(
    TEXT, TEXT, TEXT, TEXT, INTEGER
) IS
    'Phase 12 Tier 5 #1 — returns top N past resolutions most similar to '
    'the given (structural_fingerprint, op, error_class). Match strength '
    '3 = exact structural match · 2 = op+class match · 1 = op-only or '
    'class-only match. Used by the triage-bugs Edge Function and the CMS '
    'markdown export. SECURITY DEFINER + STABLE — service-role / admin '
    'callers only via the admin API.';

GRANT EXECUTE ON FUNCTION bug_intel_find_similar_resolutions(
    TEXT, TEXT, TEXT, TEXT, INTEGER
) TO service_role;

-- ----------------------------------------------------------------------------
-- 4. Backfill — last 90 days of already-resolved fingerprints
-- ----------------------------------------------------------------------------
--
-- One-shot at migration time so Day-1 of the new system has real lessons,
-- not an empty table. Bypasses the trigger (we INSERT directly) and uses
-- the same report-picking logic the trigger uses. Idempotent via
-- ON CONFLICT (fingerprint, resolved_at) DO NOTHING.

INSERT INTO bug_intel_resolved_history (
    fingerprint,
    structural_fingerprint,
    op,
    error_class,
    pg_code,
    http_status,
    endpoint,
    last_seen_file,
    last_seen_function,
    last_seen_line,
    title,
    summary,
    agent_owner,
    severity,
    severity_score,
    resolution_pr_url,
    auto_resolved_reason,
    resolved_status,
    resolved_at
)
SELECT
    f.fingerprint,
    f.structural_fingerprint,
    f.op,
    f.error_class,
    f.pg_code,
    f.http_status,
    f.endpoint,
    f.last_seen_file,
    f.last_seen_function,
    f.last_seen_line,
    r.title,
    r.summary,
    r.agent_owner,
    r.severity,
    f.severity_score,
    COALESCE(f.resolution_pr_url, r.pr_url),
    f.auto_resolved_reason,
    f.status,
    COALESCE(f.auto_resolved_at, f.resolved_at, f.updated_at)
FROM bug_intelligence_fingerprints f
LEFT JOIN LATERAL (
    SELECT
        rep.title,
        rep.summary,
        rep.agent_owner,
        rep.severity,
        rep.pr_url
    FROM bug_intelligence_reports rep
    WHERE rep.fingerprint = f.fingerprint
      AND rep.review_status NOT IN ('rejected', 'stale')
    ORDER BY
        CASE rep.review_status
            WHEN 'merged'   THEN 0
            WHEN 'approved' THEN 1
            WHEN 'pending'  THEN 2
            ELSE 3
        END,
        rep.created_at DESC
    LIMIT 1
) r ON TRUE
WHERE f.status IN ('resolved', 'wont_fix', 'duplicate')
  AND COALESCE(f.auto_resolved_at, f.resolved_at, f.updated_at)
       >= now() - INTERVAL '90 days'
ON CONFLICT (fingerprint, resolved_at) DO NOTHING;

-- ----------------------------------------------------------------------------
-- 5. Audit: confirm install + report backfill counts
-- ----------------------------------------------------------------------------

DO $$
DECLARE
    v_count    INTEGER;
    v_unique_struct INTEGER;
BEGIN
    SELECT COUNT(*), COUNT(DISTINCT structural_fingerprint)
    INTO v_count, v_unique_struct
    FROM bug_intel_resolved_history;

    RAISE NOTICE '20260530_bug_intel_resolved_history: trigger installed, RPC ready, '
                 'backfill loaded % rows across % distinct structural_fingerprints',
                 v_count, v_unique_struct;

    IF v_count = 0 THEN
        RAISE NOTICE 'No backfill rows — bug_intel_resolved_history starts empty. '
                     'Trigger will populate it as fingerprints transition into terminal states.';
    END IF;
END $$;

COMMIT;
