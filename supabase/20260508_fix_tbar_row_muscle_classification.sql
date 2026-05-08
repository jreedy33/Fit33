-- ============================================================================
-- 20260508 — FIX T-BAR ROW MUSCLE CLASSIFICATION
-- ============================================================================
-- Audit Round 3 (`scripts/output/autogen_audit_20260508_124852.md`, fix #7)
-- found 2 instances of T-Bar Row variants surfacing as a CORE / OBLIQUE
-- PRIMARY exercise in autogen workouts. Specifically the live `exercises` row
-- "T-Bar Row - Reverse Grip (Machine)" (id `12ebdef1-0a68-4a3c-973f-02be17e2528c`)
-- has `primary_muscles = '{"Obliques"}'` in production today, even though the
-- earlier bulk update (`update_exercises_final_fixed.sql`, row [189/309]) set
-- it to `'{"Upper Back"}'`. Either that bulk file was never re-applied after a
-- CMS edit clobbered the field, or a downstream import re-introduced the
-- "Obliques" classification — either way, the live row is wrong RIGHT NOW.
--
-- FIX: Defensively re-classify EVERY T-Bar Row variant currently in the
-- catalog so that:
--   1. `category` is `'Back'` (not `'Core'`).
--   2. `primary_muscles` is `'{"Upper Back"}'` (matching the canonical
--      T-Bar Row variant + every other Row movement in the catalog).
--   3. `secondary_muscles` is `'{"Lats","Biceps","Rear Delts"}'` with any
--      "Obliques" / "Core" / "Abs" entry filtered out (rowing rotates the
--      torso slightly, but it's a tertiary stimulus — never a secondary).
--   4. `exercise_family` is `'t_bar_row'` (so the WorkoutGeneratorService
--      `tbarRowCount` cap actually catches it).
--
-- Defensive: the WHERE clause is name-based (any row whose name contains
-- "T-Bar Row" / "T Bar Row" / "TBar Row" — case-insensitive) so the migration
-- self-heals even if the same wrong primary_muscles re-appears via CMS edit
-- on a different row id in the future.
--
-- Idempotent — safe to re-run. Body is wrapped in `BEGIN; ... COMMIT;` per
-- supabase-rules. Trailing audit `DO $$` block fails loud if any T-Bar Row
-- variant still has `Obliques`/`Core`/`Abs` as PRIMARY muscle after the
-- update.
--
-- Companion changes in the same PR:
--   - `Fit33/SmartExerciseSelectionEngine.swift::validateTargetMuscleCoverage`
--     (defends future autogen runs from the inverse class of bug — promised
--     calves but delivered no calf exercises).
--   - `Fit33/SmartExerciseSelectionEngine.swift::assessExercisePracticality`
--     adds a technique-equipment mismatch check that excludes Pendlay /
--     Jefferson / Zercher / Clean Grip / Snatch Grip on non-barbell
--     equipment.
--
-- MUST be followed by `NOTIFY pgrst, 'reload schema'` (issued at the bottom
-- of this file) so the schema cache picks up the column-data change
-- immediately and live workouts no longer surface a T-Bar Row as a core
-- exercise.
-- ============================================================================

BEGIN;

-- ───────────────────────────────────────────────────────────────────────────
-- 1. Pre-update audit — log how many bad rows we're about to fix
-- ───────────────────────────────────────────────────────────────────────────

DO $$
DECLARE
    v_bad_primary_count INT;
    v_total_tbar_count  INT;
    r                   RECORD;
BEGIN
    SELECT COUNT(*) INTO v_total_tbar_count
    FROM public.exercises
    WHERE LOWER(name) LIKE '%t-bar row%'
       OR LOWER(name) LIKE '%t bar row%'
       OR LOWER(name) LIKE '%tbar row%';

    SELECT COUNT(*) INTO v_bad_primary_count
    FROM public.exercises
    WHERE (LOWER(name) LIKE '%t-bar row%'
        OR LOWER(name) LIKE '%t bar row%'
        OR LOWER(name) LIKE '%tbar row%')
      AND (
              'Obliques' = ANY (primary_muscles)
           OR 'obliques' = ANY (primary_muscles)
           OR 'Core'     = ANY (primary_muscles)
           OR 'core'     = ANY (primary_muscles)
           OR 'Abs'      = ANY (primary_muscles)
           OR 'abs'      = ANY (primary_muscles)
          );

    RAISE NOTICE '═══════════════════════════════════════════════════════';
    RAISE NOTICE 'T-Bar Row classification audit (BEFORE fix):';
    RAISE NOTICE '  Total T-Bar Row variants in catalog : %', v_total_tbar_count;
    RAISE NOTICE '  Variants with Obliques/Core/Abs as PRIMARY muscle: %', v_bad_primary_count;
    RAISE NOTICE '═══════════════════════════════════════════════════════';

    FOR r IN
        SELECT id, name, primary_muscles, secondary_muscles, category
        FROM public.exercises
        WHERE LOWER(name) LIKE '%t-bar row%'
           OR LOWER(name) LIKE '%t bar row%'
           OR LOWER(name) LIKE '%tbar row%'
        ORDER BY name
    LOOP
        RAISE NOTICE '  [%] name=% | primary=% | secondary=% | category=%',
            r.id, r.name, r.primary_muscles, r.secondary_muscles, r.category;
    END LOOP;
END $$;

-- ───────────────────────────────────────────────────────────────────────────
-- 2. The fix — re-classify ALL T-Bar Row variants
-- ───────────────────────────────────────────────────────────────────────────
-- Strategy: name-based match so we self-heal regardless of row id. For each
-- T-Bar Row variant:
--   - PRIMARY = '{"Upper Back"}' (drops any Obliques/Core/Abs misclassification)
--   - SECONDARY = '{"Lats","Biceps","Rear Delts"}' (filters out Obliques/Core/Abs
--     even from the secondary list — rowing is not a core exercise)
--   - category = 'Back'
--   - exercise_family = 't_bar_row' (so the row-cap in WorkoutGeneratorService
--     applies; otherwise the variant could slip past horizontalRow + tbar caps)

UPDATE public.exercises
SET
    category          = 'Back',
    primary_muscles   = ARRAY['Upper Back']::TEXT[],
    secondary_muscles = ARRAY['Lats', 'Biceps', 'Rear Delts']::TEXT[],
    exercise_family   = 't_bar_row',
    manually_updated  = TRUE,
    manually_updated_at = NOW()
WHERE LOWER(name) LIKE '%t-bar row%'
   OR LOWER(name) LIKE '%t bar row%'
   OR LOWER(name) LIKE '%tbar row%';

-- ───────────────────────────────────────────────────────────────────────────
-- 3. Post-update verification — fail loud if any T-Bar Row still misclassified
-- ───────────────────────────────────────────────────────────────────────────

DO $$
DECLARE
    v_bad_primary_after   INT;
    v_bad_secondary_after INT;
    v_total_after         INT;
    r                     RECORD;
BEGIN
    SELECT COUNT(*) INTO v_total_after
    FROM public.exercises
    WHERE LOWER(name) LIKE '%t-bar row%'
       OR LOWER(name) LIKE '%t bar row%'
       OR LOWER(name) LIKE '%tbar row%';

    SELECT COUNT(*) INTO v_bad_primary_after
    FROM public.exercises
    WHERE (LOWER(name) LIKE '%t-bar row%'
        OR LOWER(name) LIKE '%t bar row%'
        OR LOWER(name) LIKE '%tbar row%')
      AND (
              'Obliques' = ANY (primary_muscles)
           OR 'obliques' = ANY (primary_muscles)
           OR 'Core'     = ANY (primary_muscles)
           OR 'core'     = ANY (primary_muscles)
           OR 'Abs'      = ANY (primary_muscles)
           OR 'abs'      = ANY (primary_muscles)
          );

    SELECT COUNT(*) INTO v_bad_secondary_after
    FROM public.exercises
    WHERE (LOWER(name) LIKE '%t-bar row%'
        OR LOWER(name) LIKE '%t bar row%'
        OR LOWER(name) LIKE '%tbar row%')
      AND (
              'Obliques' = ANY (secondary_muscles)
           OR 'obliques' = ANY (secondary_muscles)
           OR 'Core'     = ANY (secondary_muscles)
           OR 'core'     = ANY (secondary_muscles)
           OR 'Abs'      = ANY (secondary_muscles)
           OR 'abs'      = ANY (secondary_muscles)
          );

    RAISE NOTICE '';
    RAISE NOTICE '═══════════════════════════════════════════════════════';
    RAISE NOTICE 'T-Bar Row classification audit (AFTER fix):';
    RAISE NOTICE '  Total T-Bar Row variants in catalog          : %', v_total_after;
    RAISE NOTICE '  Variants with bad PRIMARY (Obliques/Core/Abs): %', v_bad_primary_after;
    RAISE NOTICE '  Variants with bad SECONDARY (Obliques/Core/Abs): %', v_bad_secondary_after;
    RAISE NOTICE '═══════════════════════════════════════════════════════';

    FOR r IN
        SELECT name, primary_muscles, secondary_muscles, category, exercise_family
        FROM public.exercises
        WHERE LOWER(name) LIKE '%t-bar row%'
           OR LOWER(name) LIKE '%t bar row%'
           OR LOWER(name) LIKE '%tbar row%'
        ORDER BY name
    LOOP
        RAISE NOTICE '  ✓ % | primary=% | secondary=% | category=% | family=%',
            r.name, r.primary_muscles, r.secondary_muscles, r.category, r.exercise_family;
    END LOOP;

    IF v_bad_primary_after > 0 OR v_bad_secondary_after > 0 THEN
        RAISE EXCEPTION 'T-Bar Row classification fix INCOMPLETE: % primary + % secondary still misclassified',
            v_bad_primary_after, v_bad_secondary_after;
    END IF;
END $$;

COMMIT;

-- ───────────────────────────────────────────────────────────────────────────
-- 4. Schema-cache reload (SUPABASE invariant 30 — every column-data change
--    that the live iOS exercise library reads MUST end with this so the
--    realtime exercise sync (`RealtimeService.subscribeExercises`) and the
--    bulk fetch (`SupabaseManager.fetchExercises`) both see the corrected
--    classification within the next replication tick.)
-- ───────────────────────────────────────────────────────────────────────────

NOTIFY pgrst, 'reload schema';
