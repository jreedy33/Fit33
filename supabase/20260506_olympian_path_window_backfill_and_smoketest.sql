-- Migration: Backfill + smoketest — user_olympian_path_window
-- Date: 2026-05-06
--
-- Purpose:
--   (1) **Backfill / reconcile** every user who already has rows in
--       `user_olympian_assignments` so `user_olympian_path_window` exists and
--       matches assignment-derived truth:
--         • `pool_year` = MAX(season_year) for that user's assignments
--         • `started_at` = MIN(assigned_at)  (earliest assignment row)
--       On conflict, merge with **GREATEST(pool_year)** and **LEAST(started_at)** so
--       we never move `started_at` forward and we pick up newer pool years when
--       multi-season data exists.
--   (2) **Smoketests** (fail loud): no assignment-holding user lacks a window row;
--       `assign_olympian_path` exists; `user_olympian_path_window` table exists.
--       Informational NOTICE for orphan window rows (window without assignments).
--
-- Prerequisites: `20260505_olympian_path_365_window.sql` (table + RPC).
--
-- Safe to re-run (idempotent upsert + idempotent checks).

BEGIN;

-- ============================================================================
-- 1. BACKFILL / RECONCILE (all users with Olympian assignments)
-- ============================================================================

INSERT INTO user_olympian_path_window (user_id, pool_year, started_at)
SELECT
    a.user_id,
    MAX(a.season_year)::INT AS pool_year,
    MIN(a.assigned_at) AS started_at
FROM user_olympian_assignments a
INNER JOIN user_profiles p ON p.id = a.user_id
GROUP BY a.user_id
ON CONFLICT (user_id) DO UPDATE SET
    pool_year = GREATEST(
        user_olympian_path_window.pool_year,
        EXCLUDED.pool_year
    ),
    started_at = LEAST(
        user_olympian_path_window.started_at,
        EXCLUDED.started_at
    );

-- ============================================================================
-- 2. SMOKETESTS
-- ============================================================================

DO $$
DECLARE
    v_fn_count        INT;
    v_tbl_ok          BOOLEAN;
    v_missing         INT;
    v_orphan          INT;
    v_window_rows     INT;
    v_assignment_users INT;
BEGIN
    SELECT EXISTS (
        SELECT 1
        FROM information_schema.tables
        WHERE table_schema = 'public'
          AND table_name = 'user_olympian_path_window'
    ) INTO v_tbl_ok;

    IF NOT v_tbl_ok THEN
        RAISE EXCEPTION 'Smoketest failed: public.user_olympian_path_window missing';
    END IF;

    SELECT COUNT(*) INTO v_fn_count
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname = 'assign_olympian_path';

    IF v_fn_count < 1 THEN
        RAISE EXCEPTION 'Smoketest failed: public.assign_olympian_path(...) not found';
    END IF;

    SELECT COUNT(*) INTO v_missing
    FROM (
        SELECT user_id
        FROM user_olympian_assignments
        GROUP BY user_id
    ) u
    WHERE NOT EXISTS (
        SELECT 1
        FROM user_olympian_path_window w
        WHERE w.user_id = u.user_id
    );

    IF v_missing > 0 THEN
        RAISE EXCEPTION
            'Smoketest failed: % user(s) have user_olympian_assignments but no user_olympian_path_window row (check FK / orphan user_ids)',
            v_missing;
    END IF;

    SELECT COUNT(*) INTO v_orphan
    FROM user_olympian_path_window w
    WHERE NOT EXISTS (
        SELECT 1
        FROM user_olympian_assignments a
        WHERE a.user_id = w.user_id
    );

    SELECT COUNT(*) INTO v_window_rows FROM user_olympian_path_window;
    SELECT COUNT(DISTINCT user_id) INTO v_assignment_users FROM user_olympian_assignments;

    RAISE NOTICE
        'olympian_path_window smoketest: OK — window_rows=%, distinct_assignment_users=%, orphan_window_rows=% (windows with no assignments; investigate if non-zero)',
        v_window_rows,
        v_assignment_users,
        v_orphan;
END $$;

COMMIT;
