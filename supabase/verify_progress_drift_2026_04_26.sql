-- =============================================================================
-- verify_progress_drift_2026_04_26.sql — READ-ONLY diagnostic
-- =============================================================================
-- Why this file exists:
--   On 2026-04-26 ~13:49 UTC-4, Joe observed Abbie at 603 steps in the
--   Community "10K Steps Daily" leaderboard but at 0 in the 1v1 widget
--   ("Step Showdown" / "10K steps Daily Steps") — both in-app AND on the home
--   screen. Per Data invariant #48, those three surfaces must always agree
--   for `steps` / `active_minutes` / `calories`. The fanout trigger that
--   guarantees this lives in `supabase/20260521_challenge_progress_fanout.sql`
--   (#87 in MIGRATION_INDEX.md) and was marked "🆕 Ready" — i.e. NOT yet
--   deployed to prod. This script proves the diagnosis BEFORE deployment and
--   confirms it AFTER.
--
-- Pattern of use:
--   1. Run BEFORE deploying #87/#88. Expect Section A to return a non-empty
--      list of (user_id, progress_date) pairs with drift > 0 across the three
--      tables — Abbie's row should be one of them.
--   2. Apply `supabase/20260521_challenge_progress_fanout.sql` then
--      `supabase/20260522_fanout_backfill_fix.sql` (in that order — #88 is
--      idempotent on top of a healthy #87 install).
--   3. Run AFTER. Section A should return ZERO rows for today/yesterday
--      (the included backfill in #87 + the trigger handle anything new).
--
-- This file is a `verify_*.sql` ad-hoc script per the MIGRATION_INDEX.md
-- §"Out of scope" rule, NOT a migration — it MUST NOT alter schema or data.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- SECTION A — Cross-table drift detector (today + yesterday, all users)
-- -----------------------------------------------------------------------------
-- For every (user, progress_date) where the same `steps` / `active_minutes`
-- / `calories` value should have been written to multiple tables, find the
-- min/max across the three daily-progress tables and flag any drift > 0.
-- Each `*_max` column is computed as a per-(user, date) max over rows
-- belonging to a parent challenge of the relevant cumulative type. NULL
-- means "user has no membership / row in that surface for that day".
-- -----------------------------------------------------------------------------
WITH today_window AS (
    SELECT generate_series(
        (NOW() AT TIME ZONE 'UTC')::DATE - 1,
        (NOW() AT TIME ZONE 'UTC')::DATE,
        '1 day'::INTERVAL
    )::DATE AS d
),
group_max AS (
    SELECT cdp.user_id, cdp.progress_date, MAX(cdp.progress_value) AS v
    FROM challenge_daily_progress cdp
    JOIN group_challenges gc ON gc.id = cdp.challenge_id
    WHERE cdp.progress_date IN (SELECT d FROM today_window)
      AND gc.challenge_type IN ('steps','active_minutes','calories')
    GROUP BY cdp.user_id, cdp.progress_date
),
private_max AS (
    SELECT pcdp.user_id, pcdp.progress_date, MAX(pcdp.progress_value) AS v
    FROM private_challenge_daily_progress pcdp
    JOIN private_challenges pc ON pc.id = pcdp.challenge_id
    WHERE pcdp.progress_date IN (SELECT d FROM today_window)
      AND pc.challenge_type IN ('steps','active_minutes','calories')
    GROUP BY pcdp.user_id, pcdp.progress_date
),
community_max AS (
    SELECT ccdp.user_id, ccdp.progress_date, MAX(ccdp.progress_value) AS v
    FROM community_challenge_daily_progress ccdp
    JOIN community_challenges cc ON cc.id = ccdp.challenge_id
    WHERE ccdp.progress_date IN (SELECT d FROM today_window)
      AND cc.challenge_type IN ('steps','active_minutes','calories')
    GROUP BY ccdp.user_id, ccdp.progress_date
),
-- Outer-union all (user, date) pairs that appear in any source so we don't
-- miss users who exist in only one table.
all_pairs AS (
    SELECT user_id, progress_date FROM group_max
    UNION
    SELECT user_id, progress_date FROM private_max
    UNION
    SELECT user_id, progress_date FROM community_max
)
SELECT
    ap.progress_date,
    ap.user_id,
    up.name        AS display_name,
    up.username    AS username,
    g.v            AS group_steps,
    p.v            AS private_steps,
    c.v            AS community_steps,
    -- Highest value across the three (the "truth" — fanout converges to this)
    GREATEST(COALESCE(g.v, 0), COALESCE(p.v, 0), COALESCE(c.v, 0)) AS max_seen,
    -- Smallest non-null value (so a user only in community isn't flagged)
    LEAST(
        COALESCE(g.v, 'infinity'::FLOAT8),
        COALESCE(p.v, 'infinity'::FLOAT8),
        COALESCE(c.v, 'infinity'::FLOAT8)
    )::INT AS min_seen,
    GREATEST(COALESCE(g.v, 0), COALESCE(p.v, 0), COALESCE(c.v, 0))
        - LEAST(
            COALESCE(g.v, 'infinity'::FLOAT8),
            COALESCE(p.v, 'infinity'::FLOAT8),
            COALESCE(c.v, 'infinity'::FLOAT8)
          )::INT AS drift
FROM all_pairs ap
LEFT JOIN group_max     g ON g.user_id = ap.user_id AND g.progress_date = ap.progress_date
LEFT JOIN private_max   p ON p.user_id = ap.user_id AND p.progress_date = ap.progress_date
LEFT JOIN community_max c ON c.user_id = ap.user_id AND c.progress_date = ap.progress_date
LEFT JOIN user_profiles up ON up.id    = ap.user_id
-- Only show pairs where at least one surface has a row in MORE THAN ONE table
-- AND those tables disagree. (User in only one surface = no drift, skip.)
WHERE (
    (g.v IS NOT NULL AND p.v IS NOT NULL AND g.v <> p.v)
 OR (g.v IS NOT NULL AND c.v IS NOT NULL AND g.v <> c.v)
 OR (p.v IS NOT NULL AND c.v IS NOT NULL AND p.v <> c.v)
)
ORDER BY drift DESC NULLS LAST, ap.progress_date DESC, up.name;

-- -----------------------------------------------------------------------------
-- SECTION B — Single-user spotlight (replace with the user_id you care about)
-- -----------------------------------------------------------------------------
-- After Section A identifies the drifted user, paste their UUID below to see
-- every row across all three tables for the last 2 days, including the
-- challenge_id / source / updated_at — useful for confirming WHICH challenge
-- got the write, what `source` it was tagged with (e.g. `auto_sync` vs
-- `fanout:community_challenge_daily_progress`), and the wall-clock skew.
-- -----------------------------------------------------------------------------
-- Replace this UUID with Abbie's user_id (find via Section A or
-- challenge_participants → user_profiles JOIN).
WITH params AS (
    SELECT '00000000-0000-0000-0000-000000000000'::UUID AS uid
)
SELECT '1v1/group' AS surface,
       cdp.challenge_id, gc.title, gc.challenge_type,
       cdp.progress_date, cdp.progress_value,
       cdp.target_hit, cdp.source, cdp.updated_at
FROM challenge_daily_progress cdp
JOIN group_challenges gc ON gc.id = cdp.challenge_id, params
WHERE cdp.user_id = params.uid
  AND cdp.progress_date >= (NOW() AT TIME ZONE 'UTC')::DATE - 1
UNION ALL
SELECT 'private',
       pcdp.challenge_id, pc.title, pc.challenge_type,
       pcdp.progress_date, pcdp.progress_value,
       pcdp.target_hit, pcdp.source, pcdp.updated_at
FROM private_challenge_daily_progress pcdp
JOIN private_challenges pc ON pc.id = pcdp.challenge_id, params
WHERE pcdp.user_id = params.uid
  AND pcdp.progress_date >= (NOW() AT TIME ZONE 'UTC')::DATE - 1
UNION ALL
SELECT 'community',
       ccdp.challenge_id, cc.title, cc.challenge_type,
       ccdp.progress_date, ccdp.progress_value,
       ccdp.target_hit, ccdp.source, ccdp.updated_at
FROM community_challenge_daily_progress ccdp
JOIN community_challenges cc ON cc.id = ccdp.challenge_id, params
WHERE ccdp.user_id = params.uid
  AND ccdp.progress_date >= (NOW() AT TIME ZONE 'UTC')::DATE - 1
ORDER BY 5 DESC, 4, 1;

-- -----------------------------------------------------------------------------
-- SECTION C — Trigger health-check
-- -----------------------------------------------------------------------------
-- Confirm whether the three fanout triggers from #87 are actually installed.
-- Expected after deploy: 3 rows. Before deploy: 0 rows (this is the smoking
-- gun confirming Section A's drift is the unfanned-out tables).
-- -----------------------------------------------------------------------------
SELECT
    t.tgname             AS trigger_name,
    c.relname            AS table_name,
    pg_get_triggerdef(t.oid) AS definition
FROM pg_trigger t
JOIN pg_class   c ON c.oid = t.tgrelid
WHERE t.tgname IN (
    'trg_fanout_challenge_progress',
    'trg_fanout_private_challenge_progress',
    'trg_fanout_community_challenge_progress'
)
ORDER BY c.relname;
