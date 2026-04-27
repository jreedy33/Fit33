-- ============================================================================
-- Migration: Dedupe exercise_performance_history (remove legacy WorkoutManager rows)
-- Date: 2026-04-27
-- Agent: Data & Backend
--
-- WHY:
--   Until this migration, two separate iOS code paths inserted into
--   `exercise_performance_history` on every workout completion:
--
--     1. ExerciseHistoryService.saveExercisePerformance() — CANONICAL.
--        Populates `total_reps`, `max_weight`, `max_reps`, `avg_weight`,
--        `avg_reps`, `total_volume`, etc. Also writes the matching
--        `exercise_set_history` rows and updates `exercise_personal_records`.
--        This is the writer the agent doc has called canonical
--        ("columns are max_weight / max_reps, NOT best_set_*"
--         — DATA_BACKEND_AGENT.md line 159).
--
--     2. WorkoutManager.recordExercisePerformance() — LEGACY.
--        Only populated `best_set_weight`, `best_set_reps`,
--        `one_rep_max_estimate`, `equipment_used`, `total_sets`,
--        `total_volume`. Left `total_reps=0`, `max_weight=0`,
--        `avg_weight=NULL`, `avg_reps=NULL` (column defaults).
--
--   Both fired from `WorkoutManager.completeWorkout()` (legacy via Task,
--   canonical via ActiveWorkoutView+Persistence.saveExercisePerformanceHistoryWithData),
--   so every completed workout produced TWO rows per exercise. The
--   "Recent sessions" tile row in the active workout (`RecentSessionsTilesRow`,
--   sourced from `ExerciseHistoryService.fetchRecentSessions`) reads
--   `avg_weight`, so the legacy duplicate rendered as `— lb · <date>`
--   ghost chip alongside the real `<avg> lb · <date>` chip — making
--   users think they had logged the same workout twice.
--
--   The legacy writer was removed from `Fit33/WorkoutManager.swift` in
--   the same PR as this migration. This migration cleans up the
--   accumulated duplicate rows.
--
-- WHAT:
--   Deletes ONLY rows that satisfy ALL of:
--     - `avg_weight IS NULL`           — written without canonical aggregates
--     - `best_set_weight IS NOT NULL`  — written by the legacy path
--     - `max_weight = 0`               — column-default left untouched
--     - A canonical sibling row exists for the same
--       `(user_id, exercise_name, workout_id)` (i.e. avg_weight populated).
--
--   That last EXISTS clause is the safety belt: historical rows that
--   pre-date `ExerciseHistoryService.saveExercisePerformance` (so legacy
--   was the only writer) are KEPT — deleting them would lose the user's
--   only record of those workouts. We only delete genuine duplicates
--   that have a known-good canonical sibling.
--
-- IDEMPOTENT: Yes. Re-running the DELETE matches an empty set.
-- REVERSIBLE: No (rows are deleted), but they were duplicate noise — the
--   sibling rows preserve the canonical record of every affected workout.
-- ============================================================================

BEGIN;

-- Snapshot the count for the audit log.
DO $$
DECLARE
    v_phantom_count BIGINT;
BEGIN
    SELECT COUNT(*) INTO v_phantom_count
    FROM exercise_performance_history old
    WHERE old.avg_weight IS NULL
      AND old.best_set_weight IS NOT NULL
      AND old.max_weight = 0
      AND EXISTS (
          SELECT 1
          FROM exercise_performance_history newer
          WHERE newer.user_id = old.user_id
            AND newer.exercise_name = old.exercise_name
            AND newer.workout_id = old.workout_id
            AND newer.id <> old.id
            AND newer.avg_weight IS NOT NULL
      );

    RAISE NOTICE 'Deduping exercise_performance_history: % phantom rows match cleanup predicate', v_phantom_count;
END;
$$;

DELETE FROM exercise_performance_history old
WHERE old.avg_weight IS NULL
  AND old.best_set_weight IS NOT NULL
  AND old.max_weight = 0
  AND EXISTS (
      SELECT 1
      FROM exercise_performance_history newer
      WHERE newer.user_id = old.user_id
        AND newer.exercise_name = old.exercise_name
        AND newer.workout_id = old.workout_id
        AND newer.id <> old.id
        AND newer.avg_weight IS NOT NULL
  );

-- Post-condition: zero rows should match the predicate.
DO $$
DECLARE
    v_remaining BIGINT;
BEGIN
    SELECT COUNT(*) INTO v_remaining
    FROM exercise_performance_history old
    WHERE old.avg_weight IS NULL
      AND old.best_set_weight IS NOT NULL
      AND old.max_weight = 0
      AND EXISTS (
          SELECT 1
          FROM exercise_performance_history newer
          WHERE newer.user_id = old.user_id
            AND newer.exercise_name = old.exercise_name
            AND newer.workout_id = old.workout_id
            AND newer.id <> old.id
            AND newer.avg_weight IS NOT NULL
      );

    IF v_remaining > 0 THEN
        RAISE EXCEPTION 'Cleanup post-condition failed: % phantom rows still match predicate after DELETE', v_remaining;
    END IF;

    RAISE NOTICE '✅ exercise_performance_history dedupe complete';
END;
$$;

COMMIT;
