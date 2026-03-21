-- Migration: Fix missing columns blocking cloud sync
-- Date: 2026-03-20
-- Agent: Data & Backend (primary), Infra & Security (RLS review)
-- Reason: WorkoutManager.swift writes best_set_reps to exercise_performance_history,
--         CollaborativeLearningEngine.swift writes program_id to collaborative_workout_data.
--         Both columns are missing, causing silent insert failures.

BEGIN;

-- ═══════════════════════════════════════════════════
-- 1. exercise_performance_history: add best_set_reps
-- Written by WorkoutManager.swift:1361
-- ═══════════════════════════════════════════════════

ALTER TABLE exercise_performance_history
    ADD COLUMN IF NOT EXISTS best_set_reps INTEGER;

-- Also ensure best_set_weight exists (written by WorkoutManager.swift:1360)
ALTER TABLE exercise_performance_history
    ADD COLUMN IF NOT EXISTS best_set_weight DOUBLE PRECISION;

-- And one_rep_max_estimate (written by WorkoutManager.swift:1364)
ALTER TABLE exercise_performance_history
    ADD COLUMN IF NOT EXISTS one_rep_max_estimate DOUBLE PRECISION;

-- And equipment_used (written by WorkoutManager.swift:1365)
ALTER TABLE exercise_performance_history
    ADD COLUMN IF NOT EXISTS equipment_used TEXT;

-- ═══════════════════════════════════════════════════
-- 2. collaborative_workout_data: add program_id
-- Written by CollaborativeLearningEngine.swift:144
-- ═══════════════════════════════════════════════════

ALTER TABLE collaborative_workout_data
    ADD COLUMN IF NOT EXISTS program_id TEXT;

COMMIT;

-- ROLLBACK:
-- ALTER TABLE exercise_performance_history DROP COLUMN IF EXISTS best_set_reps;
-- ALTER TABLE exercise_performance_history DROP COLUMN IF EXISTS best_set_weight;
-- ALTER TABLE exercise_performance_history DROP COLUMN IF EXISTS one_rep_max_estimate;
-- ALTER TABLE exercise_performance_history DROP COLUMN IF EXISTS equipment_used;
-- ALTER TABLE collaborative_workout_data DROP COLUMN IF EXISTS program_id;
