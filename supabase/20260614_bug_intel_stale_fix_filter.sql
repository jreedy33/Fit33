-- ============================================================================
-- Bug Intelligence — `last_seen_after_fix_deployed` Stale-Fix Filter
-- Date: 2026-06-14 (migration order), authored 2026-04-25
-- Sprint 12 follow-up to the 2026-04-25 19:07 audit (close-out #113).
--
-- PROBLEM
-- -------
-- The 2026-04-25 19:07 audit surfaced 13 fingerprints. 4 of them (R1, R3, R5,
-- R7) were already resolved upstream — their fix migrations (#106, #108) had
-- shipped earlier that day — but the fingerprints stayed in the export
-- because:
--   (a) `mark_fingerprints_resolved_by_migration` was never invoked when those
--       migrations deployed (the CI hook from Phase-12 Tier-2 #1 is still a
--       follow-up), and
--   (b) some clients on stale builds + the PostgREST schema cache reload
--       window kept producing occurrences for ~24h after the migration ran,
--       so the post-deploy `last_seen_at` looked like fresh activity.
--
-- The audit response had to manually write a #113 close-out migration to flip
-- the four already-resolved fingerprints. That's busywork the export pipeline
-- should have done itself.
--
-- FIX
-- ---
-- Two-part change that lets the export *automatically* hide fingerprints
-- whose fix has already shipped, without losing genuine regressions:
--
--   1. Add `latest_resolving_migration_at` + `latest_resolving_migration_id`
--      columns to `bug_intelligence_fingerprints`. Stamped whenever a
--      migration with a `-- Resolves: <fp>` directive deploys, REGARDLESS
--      of whether the fingerprint flips to `resolved` (we want to track the
--      deploy moment even on legacy fingerprints we don't auto-flip).
--
--   2. Add `bug_intel_register_migration_deploy(migration_id, fingerprints)`
--      service-role RPC that stamps the columns above. Designed to be called
--      by future CI hook OR by close-out migrations themselves (via the new
--      header `-- Resolves:` directives, which already exist post-#113).
--
--   3. Update `mark_fingerprints_resolved_by_migration` to ALSO stamp the
--      new columns so the existing close-out path stays in lock-step.
--
--   4. Backfill the new columns from existing data: any fingerprint whose
--      `auto_resolved_reason` matches `migration_(resolved|pending_deploy):<id>`
--      gets its `latest_resolving_migration_at` set to
--      `COALESCE(auto_resolved_at, resolved_at)` and the parsed migration id.
--
-- The admin export pipeline (`get_bug_intelligence_export` in
-- `admin-cms/src/app/api/admin/route.ts`) reads these columns and applies the
-- new filter:
--
--     hide IF mode != 'all'
--          AND latest_resolving_migration_at IS NOT NULL
--          AND last_seen_at <= latest_resolving_migration_at + 48h grace
--          AND regressed_after_fix IS NOT TRUE
--
-- That hides "ghost" reports where the server fix shipped and the only
-- post-deploy occurrences are the 24-48h tail of stale clients / PostgREST
-- schema-cache reload. Genuine regressions (`regressed_after_fix = TRUE` OR
-- last_seen_at > deploy + 48h) still surface. `mode='all'` (full audit) is
-- always exempt — it's the manual escape hatch for inbox-zero sweeps.
--
-- BACKWARD COMPAT
-- ---------------
-- Pure additive on the schema. `mark_fingerprints_resolved_by_migration` is
-- recompiled in place (signature unchanged) so existing callers keep working.
-- Older server builds that don't read the new columns simply see them as
-- NULL.
--
-- ROLLBACK
-- --------
--   ALTER TABLE bug_intelligence_fingerprints
--     DROP COLUMN IF EXISTS latest_resolving_migration_at,
--     DROP COLUMN IF EXISTS latest_resolving_migration_id;
--   DROP FUNCTION IF EXISTS bug_intel_register_migration_deploy(TEXT, TEXT[]);
--   -- mark_fingerprints_resolved_by_migration revert: redeploy #93's body.
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- 1. Schema — add the two columns + an index for the export filter hot path.
-- ----------------------------------------------------------------------------

ALTER TABLE bug_intelligence_fingerprints
  ADD COLUMN IF NOT EXISTS latest_resolving_migration_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS latest_resolving_migration_id TEXT;

COMMENT ON COLUMN bug_intelligence_fingerprints.latest_resolving_migration_at IS
  'Phase 13 (2026-06-14) — Timestamp of the most recent deploy of a migration '
  'that declared `-- Resolves: <this-fingerprint>` in its header. Stamped by '
  'bug_intel_register_migration_deploy() and by mark_fingerprints_resolved_by_migration(). '
  'The admin export filter (`get_bug_intelligence_export`) uses this to hide '
  'fingerprints whose fix has already shipped and whose only post-deploy '
  'activity is the 24-48h stale-client tail (last_seen_at <= '
  'latest_resolving_migration_at + 48h AND NOT regressed_after_fix → hidden). '
  'NULL until first deploy registration; NULL means "no fix shipped yet".';

COMMENT ON COLUMN bug_intelligence_fingerprints.latest_resolving_migration_id IS
  'Phase 13 (2026-06-14) — Migration id (e.g. `20260605_get_daily_quests_personalized`) '
  'whose deploy stamped latest_resolving_migration_at. Surfaced in the CMS '
  'so admins can see at-a-glance which fix shipped without re-deriving from '
  'auto_resolved_reason. NULL when no fix has been registered yet.';

-- Hot-path index for the export filter: cheap predicate evaluation when the
-- admin route walks fpById and checks whether each open fingerprint should
-- be filtered out by the stale-fix grace window.
CREATE INDEX IF NOT EXISTS idx_bug_fingerprints_latest_resolving
  ON bug_intelligence_fingerprints(latest_resolving_migration_at DESC NULLS LAST)
  WHERE status NOT IN ('resolved', 'wont_fix', 'duplicate');

-- ----------------------------------------------------------------------------
-- 2. RPC: bug_intel_register_migration_deploy(migration_id, fingerprints)
--    Service-role only. Stamps latest_resolving_migration_at = now() on each
--    fingerprint without flipping status. Distinct from
--    mark_fingerprints_resolved_by_migration which ALSO flips status — this
--    one is the "fix deployed but we want to keep watching for regression"
--    primitive.
-- ----------------------------------------------------------------------------

DROP FUNCTION IF EXISTS bug_intel_register_migration_deploy(TEXT, TEXT[]);

CREATE OR REPLACE FUNCTION bug_intel_register_migration_deploy(
  p_migration_id TEXT,
  p_resolves     TEXT[]
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_stamped INT := 0;
  v_known   INT := 0;
BEGIN
  IF auth.role() IS NOT NULL AND auth.role() <> 'service_role' THEN
    RAISE EXCEPTION 'bug_intel_register_migration_deploy is service-role only'
      USING ERRCODE = '42501';
  END IF;

  IF p_migration_id IS NULL OR length(p_migration_id) = 0 THEN
    RAISE EXCEPTION 'p_migration_id is required';
  END IF;

  IF p_resolves IS NULL OR array_length(p_resolves, 1) IS NULL THEN
    RETURN jsonb_build_object(
      'migration_id',  p_migration_id,
      'stamped',       0,
      'known_in_db',   0,
      'registered_at', now()
    );
  END IF;

  SELECT COUNT(*)::INT INTO v_known
  FROM bug_intelligence_fingerprints
  WHERE fingerprint = ANY(p_resolves);

  WITH upd AS (
    UPDATE bug_intelligence_fingerprints
    SET latest_resolving_migration_at = now(),
        latest_resolving_migration_id = p_migration_id,
        updated_at                    = now()
    WHERE fingerprint = ANY(p_resolves)
    RETURNING fingerprint
  )
  SELECT COUNT(*)::INT INTO v_stamped FROM upd;

  RAISE NOTICE 'bug_intel_register_migration_deploy(%): stamped %/% fingerprint(s)',
               p_migration_id, v_stamped, COALESCE(array_length(p_resolves, 1), 0);

  RETURN jsonb_build_object(
    'migration_id',  p_migration_id,
    'stamped',       v_stamped,
    'known_in_db',   v_known,
    'requested',     COALESCE(array_length(p_resolves, 1), 0),
    'registered_at', now()
  );
END;
$$;

COMMENT ON FUNCTION bug_intel_register_migration_deploy(TEXT, TEXT[]) IS
  'Phase 13 (2026-06-14) — service-role RPC. Stamps latest_resolving_migration_at '
  '+ latest_resolving_migration_id on every supplied fingerprint without changing '
  'status. Use this when a fix-bearing migration deploys but you do NOT want to '
  'pre-emptively flip fingerprints to resolved (regression-watch mode). The '
  'admin export filter uses these columns to hide already-shipped fixes from '
  'Cursor handoffs while still surfacing genuine regressions. Companion to '
  'mark_fingerprints_resolved_by_migration() which DOES flip status.';

REVOKE ALL ON FUNCTION bug_intel_register_migration_deploy(TEXT, TEXT[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION bug_intel_register_migration_deploy(TEXT, TEXT[]) TO service_role;

-- ----------------------------------------------------------------------------
-- 3. Re-create mark_fingerprints_resolved_by_migration so the resolved path
--    ALSO stamps the new columns (so dashboards stay consistent regardless
--    of which RPC the deploy hook calls).
--
--    Signature is unchanged from #93 — only the body adds two columns to
--    the UPDATE list. Drop-and-recreate (rather than CREATE OR REPLACE) is
--    required by codingrules: drop all overloads first.
-- ----------------------------------------------------------------------------

DROP FUNCTION IF EXISTS mark_fingerprints_resolved_by_migration(TEXT, TEXT[], TEXT);

CREATE OR REPLACE FUNCTION mark_fingerprints_resolved_by_migration(
    p_migration_id     TEXT,
    p_fingerprints     TEXT[],
    p_resolution_note  TEXT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_resolved_count INTEGER;
    v_resolution_pr  TEXT;
    v_skipped        TEXT[];
BEGIN
    IF auth.role() IS NOT NULL AND auth.role() <> 'service_role' THEN
        RAISE EXCEPTION 'mark_fingerprints_resolved_by_migration is service-role only'
            USING ERRCODE = '42501';
    END IF;

    IF p_migration_id IS NULL OR length(p_migration_id) = 0 THEN
        RAISE EXCEPTION 'p_migration_id is required';
    END IF;

    IF p_fingerprints IS NULL OR array_length(p_fingerprints, 1) IS NULL THEN
        RAISE EXCEPTION 'p_fingerprints must contain at least one fingerprint';
    END IF;

    v_resolution_pr := 'supabase/' || p_migration_id || '.sql';

    SELECT ARRAY_AGG(fp) INTO v_skipped
    FROM UNNEST(p_fingerprints) AS fp
    WHERE NOT EXISTS (
        SELECT 1 FROM bug_intelligence_fingerprints
        WHERE fingerprint = fp
    );

    -- Phase 13 addition: latest_resolving_migration_at + _id stamped on every
    -- touched row, even ones that flip status. This keeps the export filter
    -- consistent regardless of which RPC the CI hook uses.
    WITH flipped AS (
        UPDATE bug_intelligence_fingerprints f
        SET
            status                          = 'resolved',
            auto_resolved_at                = now(),
            auto_resolved_reason            = 'migration_resolved:' || p_migration_id,
            resolved_at                     = COALESCE(f.resolved_at, now()),
            resolution_pr_url               = COALESCE(f.resolution_pr_url, v_resolution_pr),
            latest_resolving_migration_at   = now(),
            latest_resolving_migration_id   = p_migration_id,
            updated_at                      = now()
        WHERE f.fingerprint = ANY (p_fingerprints)
          AND f.status NOT IN ('resolved', 'wont_fix', 'duplicate')
        RETURNING f.fingerprint
    )
    SELECT COUNT(*) INTO v_resolved_count FROM flipped;

    UPDATE bug_intelligence_reports r
    SET
        review_status = 'merged',
        pr_url        = COALESCE(r.pr_url, v_resolution_pr),
        review_notes  = COALESCE(r.review_notes || E'\n', '')
                        || format(
                            '[%s] Auto-merged by migration %s%s',
                            to_char(now(), 'YYYY-MM-DD HH24:MI UTC'),
                            p_migration_id,
                            CASE WHEN p_resolution_note IS NOT NULL
                                 THEN ' — ' || p_resolution_note
                                 ELSE ''
                            END
                           ),
        reviewed_at   = COALESCE(r.reviewed_at, now())
    WHERE r.fingerprint = ANY (p_fingerprints)
      AND r.review_status NOT IN ('merged', 'rejected', 'stale');

    RAISE NOTICE 'mark_fingerprints_resolved_by_migration(%): resolved % fingerprints, skipped % unknown',
                 p_migration_id, v_resolved_count, COALESCE(array_length(v_skipped, 1), 0);

    RETURN jsonb_build_object(
        'migration_id',    p_migration_id,
        'resolution_url',  v_resolution_pr,
        'resolved_count',  v_resolved_count,
        'skipped_unknown', COALESCE(v_skipped, '{}'::TEXT[]),
        'note',            p_resolution_note,
        'completed_at',    now()
    );
END;
$$;

COMMENT ON FUNCTION mark_fingerprints_resolved_by_migration(TEXT, TEXT[], TEXT) IS
    'Phase 12 (Tier 2 #1, 2026-04-25) + Phase 13 (2026-06-14) — service-role RPC '
    'that flips a list of fingerprints to status=resolved with reason='
    'migration_resolved:<id>, links resolution_pr_url to the migration file, '
    'AND stamps latest_resolving_migration_at + _id (Phase 13 addition for '
    'export-filter consistency). Called by the CMS deploy pipeline (or '
    'manually) after a fix-bearing migration is run. Convention: migration '
    'headers include `-- Resolves: <fp> <reason>` lines that the CI hook '
    'parses and feeds into this RPC. Closes the bug-intel loop end-to-end.';

REVOKE ALL ON FUNCTION mark_fingerprints_resolved_by_migration(TEXT, TEXT[], TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION mark_fingerprints_resolved_by_migration(TEXT, TEXT[], TEXT) TO service_role;

-- ----------------------------------------------------------------------------
-- 4. Backfill — populate the new columns from existing close-out data so the
--    filter starts working immediately without waiting for the next deploy.
--
--    Source of truth: `auto_resolved_reason` matches one of:
--      `migration_resolved:<migration_id>`
--      `migration_pending_deploy:<migration_id>`
--      `migration_resolved:<id1>+<id2>+<id3>` (e.g. close-out #113 bucket A)
--
--    For multi-migration reasons we take the LAST id (the most recent
--    fix). For pending_deploy, we still record the migration id but
--    set latest_resolving_migration_at to NULL since the fix hasn't
--    actually shipped yet — the export filter then correctly continues to
--    show those fingerprints.
-- ----------------------------------------------------------------------------

UPDATE bug_intelligence_fingerprints f
SET latest_resolving_migration_at = COALESCE(f.auto_resolved_at, f.resolved_at, f.updated_at),
    latest_resolving_migration_id = COALESCE(
        SUBSTRING(f.auto_resolved_reason FROM 'migration_resolved:([^,;[:space:]+]+)'),
        SUBSTRING(f.auto_resolved_reason FROM 'migration_resolved:[^+]*\+([^,;[:space:]+]+)$')
    )
WHERE f.auto_resolved_reason LIKE 'migration_resolved:%'
  AND f.latest_resolving_migration_at IS NULL;

-- For pending_deploy: record the migration id but leave the timestamp NULL
-- so the filter does NOT hide them yet (fix isn't actually live).
UPDATE bug_intelligence_fingerprints f
SET latest_resolving_migration_id = COALESCE(
        f.latest_resolving_migration_id,
        SUBSTRING(f.auto_resolved_reason FROM 'migration_pending_deploy:([^,;[:space:]+]+)')
    )
WHERE f.auto_resolved_reason LIKE 'migration_pending_deploy:%'
  AND f.latest_resolving_migration_id IS NULL;

-- ----------------------------------------------------------------------------
-- 5. Self-register: this migration's `Resolves:` directives stamp the
--    new columns for the 4 fingerprints from the 2026-04-25 19:07 audit
--    that #113 marked as `migration_resolved` (R1, R3, R5, R7). #113
--    pre-dated this column so we backfill in line with reality.
-- ----------------------------------------------------------------------------

DO $$
DECLARE
  v_result JSONB;
BEGIN
  v_result := bug_intel_register_migration_deploy(
    '20260614_bug_intel_stale_fix_filter',
    ARRAY[
      'e656ad7a4fb1323db476cd8f2cf6ac39', -- R1: get_daily_quests PGRST202 (#106)
      'ec1a155414f492486213a5b740f215a6', -- R3: same cluster, log variant
      '7bf1ff4efdac6620edfbda328204ed16', -- R5: v_user_quest_personalization_summary missing (#108)
      'f30626309d8480ec14526323da68396d'  -- R7: same view cluster, log variant
    ]
  );
  RAISE NOTICE 'Self-register stamped 4 audit fingerprints: %', v_result;
END $$;

-- ----------------------------------------------------------------------------
-- 6. Smoke test — confirm RPC + columns + backfill all wired up.
-- ----------------------------------------------------------------------------

DO $$
DECLARE
  v_col_count INT;
  v_idx_count INT;
  v_rpc_count INT;
  v_backfilled INT;
BEGIN
  SELECT COUNT(*) INTO v_col_count
  FROM information_schema.columns
  WHERE table_name = 'bug_intelligence_fingerprints'
    AND column_name IN ('latest_resolving_migration_at', 'latest_resolving_migration_id');
  IF v_col_count <> 2 THEN
    RAISE EXCEPTION '[Phase 13 audit] expected 2 new columns, got %', v_col_count;
  END IF;

  SELECT COUNT(*) INTO v_idx_count
  FROM pg_indexes
  WHERE indexname = 'idx_bug_fingerprints_latest_resolving';
  IF v_idx_count <> 1 THEN
    RAISE EXCEPTION '[Phase 13 audit] index idx_bug_fingerprints_latest_resolving missing';
  END IF;

  SELECT COUNT(*) INTO v_rpc_count
  FROM pg_proc
  WHERE proname = 'bug_intel_register_migration_deploy';
  IF v_rpc_count < 1 THEN
    RAISE EXCEPTION '[Phase 13 audit] RPC bug_intel_register_migration_deploy missing';
  END IF;

  SELECT COUNT(*) INTO v_backfilled
  FROM bug_intelligence_fingerprints
  WHERE latest_resolving_migration_at IS NOT NULL;
  RAISE NOTICE '[Phase 13 audit] backfill stamped % fingerprints with a deploy timestamp', v_backfilled;

  RAISE NOTICE '✅ Phase 13 stale-fix filter installed: latest_resolving_migration_(at|id) columns + bug_intel_register_migration_deploy() RPC + index. Admin export now hides fingerprints whose Resolves: migration deployed >48h before last_seen_at unless regressed_after_fix=TRUE.';
END $$;

COMMIT;

-- Resolves: e656ad7a4fb1323db476cd8f2cf6ac39 — get_daily_quests PGRST202 (R1, audit 2026-04-25 19:07)
-- Resolves: ec1a155414f492486213a5b740f215a6 — same PGRST202, log variant (R3)
-- Resolves: 7bf1ff4efdac6620edfbda328204ed16 — v_user_quest_personalization_summary missing (R5)
-- Resolves: f30626309d8480ec14526323da68396d — same view cluster, log variant (R7)
