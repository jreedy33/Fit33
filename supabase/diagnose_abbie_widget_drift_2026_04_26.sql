-- ============================================================================
-- DIAGNOSE v5: Abbie's actual progress writes — no date filter
-- 2026-04-26
-- ============================================================================

WITH params AS (
    SELECT
        '509f7332-ed98-4247-a1e3-87aeecef80ee'::uuid AS abbie,
        'be5ba712-0b9b-43bf-a03a-4cba9b6329b8'::uuid AS challenge_1v1_with_abbie
),

-- All Abbie progress in the 1v1 table (any challenge, last 3 days)
abbie_1v1 AS (
    SELECT
        '1. 1v1 (challenge_daily_progress)' AS tbl,
        cdp.challenge_id::text AS challenge_id,
        cdp.progress_date::text AS progress_date,
        cdp.progress_value,
        cdp.updated_at,
        AGE(NOW(), cdp.updated_at)::text AS age,
        cdp.source
    FROM challenge_daily_progress cdp
    WHERE cdp.user_id = (SELECT abbie FROM params)
      AND cdp.progress_date >= (NOW() AT TIME ZONE 'UTC')::DATE - 3
),

abbie_comm AS (
    SELECT
        '2. Community (community_challenge_daily_progress)' AS tbl,
        ccdp.challenge_id::text,
        ccdp.progress_date::text,
        ccdp.progress_value,
        ccdp.updated_at,
        AGE(NOW(), ccdp.updated_at)::text AS age,
        ccdp.source
    FROM community_challenge_daily_progress ccdp
    WHERE ccdp.user_id = (SELECT abbie FROM params)
      AND ccdp.progress_date >= (NOW() AT TIME ZONE 'UTC')::DATE - 3
),

abbie_priv AS (
    SELECT
        '3. Private (private_challenge_daily_progress)' AS tbl,
        pcdp.challenge_id::text,
        pcdp.progress_date::text,
        pcdp.progress_value,
        pcdp.updated_at,
        AGE(NOW(), pcdp.updated_at)::text AS age,
        pcdp.source
    FROM private_challenge_daily_progress pcdp
    WHERE pcdp.user_id = (SELECT abbie FROM params)
      AND pcdp.progress_date >= (NOW() AT TIME ZONE 'UTC')::DATE - 3
)

-- Section A: today's date as Postgres sees it
SELECT
    'A. SERVER TIME' AS section,
    'NOW()'           AS field,
    NOW()::text       AS value,
    NULL::text        AS extra
UNION ALL
SELECT 'A. SERVER TIME','today UTC',(NOW() AT TIME ZONE 'UTC')::DATE::text, NULL
UNION ALL
SELECT 'A. SERVER TIME','today ET',(NOW() AT TIME ZONE 'America/New_York')::DATE::text, NULL

UNION ALL

-- Section B: Abbie's writes
SELECT 'B. ABBIE WRITES (last 3 days)', tbl,
       'date=' || progress_date || ', value=' || progress_value::text
            || ', source=' || COALESCE(source,'NULL') || ', cid=' || challenge_id,
       'updated_at=' || updated_at::text || '  age=' || age
FROM (
    SELECT * FROM abbie_1v1
    UNION ALL SELECT * FROM abbie_comm
    UNION ALL SELECT * FROM abbie_priv
) all_writes

UNION ALL

-- Section C: row counts
SELECT 'C. ROW COUNTS','1v1 rows (last 3 days)',     COUNT(*)::text, NULL FROM abbie_1v1
UNION ALL
SELECT 'C. ROW COUNTS','community rows (last 3 days)',COUNT(*)::text, NULL FROM abbie_comm
UNION ALL
SELECT 'C. ROW COUNTS','private rows (last 3 days)',  COUNT(*)::text, NULL FROM abbie_priv

ORDER BY section, field;
