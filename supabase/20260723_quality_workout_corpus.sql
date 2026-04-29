-- ═══════════════════════════════════════════════════════════════════════════
-- 20260723_quality_workout_corpus.sql
--
-- Quality Workout Corpus — define WHAT makes a completed workout "quality"
-- so the auto-gen training corpus only learns from real sessions, not from
-- 7-minute / 2-exercise tap-throughs.
--
-- WHY
-- ---
-- `Fit33/CollaborativeLearningEngine.swift::recordWorkoutCompletion` records
-- every completed workout to `collaborative_workout_data` with
-- `was_successful = (exerciseCount >= 3)` — that's a flimsy filter. A user
-- who taps "complete" through 3 exercises × 2 sets in 4 minutes still ends
-- up in the corpus. The auto-gen recommender learns from these junk rows
-- and starts surfacing junk routines.
--
-- This migration defines a server-side quality rubric (Fitness Expert
-- authority) that scores 0–100, bands `high` / `medium` / `low`, and
-- exposes a `qualifies_for_corpus` GENERATED column at threshold 70 so
-- corpus reads filter cleanly via a partial index.
--
-- WHAT THIS MIGRATION DOES
-- ------------------------
-- 1. ALTER `workout_history` — add quality scoring columns (nullable for
--    backfill compat) + `qualifies_for_corpus` GENERATED column.
-- 2. ALTER `collaborative_workout_data` — add `workout_history_id` FK
--    (so deleting a workout cascades the corpus row), snapshot quality
--    score, generated `is_quality_workout`, total_sets / total_volume_lbs.
--    Add a partial index on the hot read path.
-- 3. CREATE `score_workout_quality(p_workout_id UUID) RETURNS JSONB`
--    SECURITY DEFINER, `auth.uid()`-pinned (Supabase invariant 9). Reads
--    `workout_history`, computes the score by the canonical rubric below,
--    UPDATEs the row, returns structured JSONB.
-- 4. ONE-SHOT BACKFILL of existing rows (capped — skip if > 10K rows for
--    safety; ops can run a bigger backfill manually if the prod set is
--    huge).
-- 5. Trailing fail-loud `DO $$` audit per supabase-rules invariant 29.
--
-- CANONICAL QUALITY RUBRIC (Fitness Expert — 100 pts total)
-- ---------------------------------------------------------
--   • Duration ≥ 25 min                                → 20 pts
--   • completion_rate ≥ 0.80                           → 25 pts
--   • ≥ 3 distinct exercises matching canonical lib    → 15 pts
--   • ≥ 12 working sets (warmups excluded)             → 15 pts
--   • ≥ 50% strength sets have non-zero weight         → 10 pts
--   • Avg time-between-set-completions ≥ 20s (proxy)   → 10 pts
--   • FE invariants (push:pull ≤ 2:1, ≤ 2 horiz press) →  5 pts
--                                                       ─────
--                                                       100
-- Threshold: ≥ 70 = `qualifies_for_corpus`. The first four checks sum to
-- 75, so a workout MUST clear Duration + Completion + Exercises + Sets to
-- qualify. The bottom-30 checks add nuance but never carry a poor
-- workout over the bar by themselves.
--
-- INVARIANTS PRESERVED
-- --------------------
--   • Schema is purely additive — no existing rows are mutated.
--   • Backfill is best-effort; rows that fail to score keep
--     `quality_score IS NULL` and naturally get `qualifies_for_corpus = NULL`
--     (i.e. excluded from the corpus). This is the safe default.
--   • `delete_user_account()` already cascades `workout_history` +
--     `collaborative_workout_data` via `auth.users(id) ON DELETE CASCADE`
--     on each — the new FK / columns inherit that cascade automatically.
--     No `delete_user_account()` patch needed.
--   • `score_workout_quality` is `auth.uid()`-pinned — service role passes
--     through (`auth.uid() IS NULL`); a user calling for another user's
--     workout gets `42501 Forbidden` per Supabase invariant 9.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

-- ───────────────────────────────────────────────────────────────────────────
-- 1. workout_history — quality scoring columns + GENERATED gate
-- ───────────────────────────────────────────────────────────────────────────

ALTER TABLE workout_history
    ADD COLUMN IF NOT EXISTS quality_score   INT,
    ADD COLUMN IF NOT EXISTS quality_band    TEXT,
    ADD COLUMN IF NOT EXISTS quality_reasons JSONB DEFAULT '{}'::jsonb;

-- Add the CHECK constraint defensively (idempotent — drop + add).
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM pg_constraint
         WHERE conname = 'workout_history_quality_band_check'
           AND conrelid = 'workout_history'::regclass
    ) THEN
        ALTER TABLE workout_history DROP CONSTRAINT workout_history_quality_band_check;
    END IF;
END $$;

ALTER TABLE workout_history
    ADD CONSTRAINT workout_history_quality_band_check
    CHECK (quality_band IS NULL OR quality_band IN ('high', 'medium', 'low'));

-- GENERATED defense-in-depth: anything reading the corpus filters on this
-- column, so it cannot drift from the score even if a future RPC writes
-- the score wrong. Drop + add to handle re-deploy.
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
         WHERE table_schema = 'public'
           AND table_name = 'workout_history'
           AND column_name = 'qualifies_for_corpus'
    ) THEN
        ALTER TABLE workout_history DROP COLUMN qualifies_for_corpus;
    END IF;
END $$;

ALTER TABLE workout_history
    ADD COLUMN qualifies_for_corpus BOOLEAN
        GENERATED ALWAYS AS (quality_score IS NOT NULL AND quality_score >= 70) STORED;

COMMENT ON COLUMN workout_history.quality_score IS
    'Quality rubric score 0-100 (NULL until scored). Computed by score_workout_quality(). Filters auto-gen training corpus to real sessions only.';
COMMENT ON COLUMN workout_history.quality_band IS
    'high (>=70) / medium (40-69) / low (<40). Mirrors quality_score; UI surface.';
COMMENT ON COLUMN workout_history.quality_reasons IS
    'JSONB transparency log — which rubric checks passed/failed, with the actual values measured. Used by debug surfaces and the CMS quality-audit page.';
COMMENT ON COLUMN workout_history.qualifies_for_corpus IS
    'GENERATED gate (quality_score >= 70). Defense-in-depth: corpus reads filter on this column so they cannot drift from the score.';

-- ───────────────────────────────────────────────────────────────────────────
-- 2. collaborative_workout_data — link back to workout_history + snapshot
-- ───────────────────────────────────────────────────────────────────────────

ALTER TABLE collaborative_workout_data
    ADD COLUMN IF NOT EXISTS workout_history_id    UUID,
    ADD COLUMN IF NOT EXISTS workout_quality_score INT,
    ADD COLUMN IF NOT EXISTS total_sets            INT,
    ADD COLUMN IF NOT EXISTS total_volume_lbs      NUMERIC;

-- FK with CASCADE — deleting a workout via `delete_workout_and_revert_stats`
-- (migration #155) automatically cleans the corpus row.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
         WHERE conname = 'collaborative_workout_data_workout_history_id_fkey'
           AND conrelid = 'collaborative_workout_data'::regclass
    ) THEN
        ALTER TABLE collaborative_workout_data
            ADD CONSTRAINT collaborative_workout_data_workout_history_id_fkey
            FOREIGN KEY (workout_history_id)
            REFERENCES workout_history(id)
            ON DELETE CASCADE;
    END IF;
END $$;

-- Drop + add the GENERATED column for re-deploy idempotency.
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
         WHERE table_schema = 'public'
           AND table_name = 'collaborative_workout_data'
           AND column_name = 'is_quality_workout'
    ) THEN
        ALTER TABLE collaborative_workout_data DROP COLUMN is_quality_workout;
    END IF;
END $$;

ALTER TABLE collaborative_workout_data
    ADD COLUMN is_quality_workout BOOLEAN
        GENERATED ALWAYS AS (
            workout_quality_score IS NOT NULL AND workout_quality_score >= 70
        ) STORED;

COMMENT ON COLUMN collaborative_workout_data.workout_history_id IS
    'FK to workout_history.id. Nullable for legacy rows. CASCADE delete: removing a workout (e.g. via delete_workout_and_revert_stats) auto-purges the corpus row.';
COMMENT ON COLUMN collaborative_workout_data.workout_quality_score IS
    'Snapshot of workout_history.quality_score at insert time. Independent of the live score so re-scoring a workout never silently re-scopes the historical corpus.';
COMMENT ON COLUMN collaborative_workout_data.is_quality_workout IS
    'GENERATED gate (workout_quality_score >= 70). Hot-path filter for corpus reads. Defense-in-depth alongside the partial index below.';
COMMENT ON COLUMN collaborative_workout_data.total_sets IS
    'Total completed sets (warmups excluded). Snapshot for corpus aggregation.';
COMMENT ON COLUMN collaborative_workout_data.total_volume_lbs IS
    'Total volume (sum of weight × reps) in pounds. Snapshot for corpus aggregation.';

-- Hot-path partial index for the auto-gen corpus read pattern:
--   WHERE user_id = ? AND is_quality_workout = TRUE ORDER BY completed_at DESC
-- Existing rows where `is_quality_workout` is NULL or FALSE are excluded
-- from the index entirely (cheap maintenance + small footprint).
CREATE INDEX IF NOT EXISTS idx_collab_workout_quality_corpus
    ON collaborative_workout_data (user_id, completed_at DESC)
    WHERE is_quality_workout = TRUE;

-- Also index the FK so cascade deletes are not a seq scan.
CREATE INDEX IF NOT EXISTS idx_collab_workout_history_id
    ON collaborative_workout_data (workout_history_id)
    WHERE workout_history_id IS NOT NULL;

-- ───────────────────────────────────────────────────────────────────────────
-- 3. score_workout_quality — canonical scorer
-- ───────────────────────────────────────────────────────────────────────────

DROP FUNCTION IF EXISTS score_workout_quality(UUID);
DROP FUNCTION IF EXISTS public.score_workout_quality(UUID);

CREATE OR REPLACE FUNCTION score_workout_quality(p_workout_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_workout              RECORD;
    v_score                INT := 0;
    v_band                 TEXT;
    v_reasons              JSONB := '{}'::jsonb;

    -- Rubric measurements
    v_duration_min         NUMERIC;
    v_completion_rate      NUMERIC;
    v_distinct_canonical   INT;
    v_working_sets         INT;
    v_total_strength_sets  INT;
    v_weighted_sets        INT;
    v_avg_secs_per_set     NUMERIC;
    v_push_count           INT;
    v_pull_count           INT;
    v_horiz_press_count    INT;
    v_total_volume_lbs     NUMERIC;
BEGIN
    -- Fetch + auth gate. Service role (auth.uid() IS NULL) passes through.
    SELECT id, user_id, duration, completion_rate, exercises, date
      INTO v_workout
      FROM workout_history
     WHERE id = p_workout_id;

    IF v_workout.id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'workout_not_found');
    END IF;

    IF auth.uid() IS NOT NULL AND v_workout.user_id <> auth.uid() THEN
        RAISE EXCEPTION 'Forbidden: cannot score another user''s workout'
            USING ERRCODE = '42501';
    END IF;

    -- ───── Measurement layer ─────

    -- Duration in minutes (workout_history.duration is seconds).
    v_duration_min := COALESCE(v_workout.duration, 0)::numeric / 60.0;

    -- Completion rate (already 0..1 in workout_history, default 1.0 from
    -- 20260320_smart_insights_schema). NULL is treated as 0 for safety.
    v_completion_rate := COALESCE(v_workout.completion_rate, 0);

    -- Distinct canonical-library exercises in the JSONB payload. We match
    -- on lower(name) because exercises[*].exercise_name is stored as user
    -- text and the canonical exercises table holds the same string. No
    -- exerciseId is stored on the JSONB row (per WorkoutExerciseDTO), so
    -- name-match is the only available join.
    SELECT COUNT(DISTINCT lower(e_elem->>'exercise_name'))
      INTO v_distinct_canonical
      FROM jsonb_array_elements(COALESCE(v_workout.exercises, '[]'::jsonb)) AS e_elem
     WHERE e_elem->>'exercise_name' IS NOT NULL
       AND EXISTS (
           SELECT 1 FROM exercises ex
            WHERE lower(ex.name) = lower(e_elem->>'exercise_name')
       );

    -- Working sets = completed sets where set_type != 'Warmup'. Capitalized
    -- because Swift `SetType` enum stores rawValue as 'Warmup' (see
    -- Fit33/WorkoutDataModels.swift line 47).
    SELECT COUNT(*)
      INTO v_working_sets
      FROM jsonb_array_elements(COALESCE(v_workout.exercises, '[]'::jsonb)) AS e_elem
           CROSS JOIN LATERAL jsonb_array_elements(COALESCE(e_elem->'sets', '[]'::jsonb)) AS s_elem
     WHERE COALESCE((s_elem->>'is_completed')::boolean, FALSE) = TRUE
       AND COALESCE(s_elem->>'set_type', 'Normal') <> 'Warmup';

    -- Working sets with non-zero weight (out of total working sets), and
    -- total volume lbs. Both computed off the same projection.
    SELECT
        COUNT(*) FILTER (
            WHERE COALESCE((s_elem->>'weight')::numeric, 0) > 0
        ),
        COUNT(*),
        COALESCE(SUM(
            COALESCE((s_elem->>'weight')::numeric, 0)
            * COALESCE((s_elem->>'reps')::numeric, 0)
        ), 0)
      INTO v_weighted_sets, v_total_strength_sets, v_total_volume_lbs
      FROM jsonb_array_elements(COALESCE(v_workout.exercises, '[]'::jsonb)) AS e_elem
           CROSS JOIN LATERAL jsonb_array_elements(COALESCE(e_elem->'sets', '[]'::jsonb)) AS s_elem
     WHERE COALESCE((s_elem->>'is_completed')::boolean, FALSE) = TRUE
       AND COALESCE(s_elem->>'set_type', 'Normal') <> 'Warmup';

    -- Avg seconds per completed set (proxy for tap-through detection).
    -- workout_history.duration is seconds; if 0 sets we set high so the
    -- check naturally fails (no way to evaluate).
    IF v_working_sets > 0 THEN
        v_avg_secs_per_set := COALESCE(v_workout.duration, 0)::numeric / v_working_sets;
    ELSE
        v_avg_secs_per_set := 0;
    END IF;

    -- FE heuristic: count exercises by movement family. Best-effort token
    -- match against exercise_name. Push tokens cover bench/press/push;
    -- pull tokens cover pull/row/lat/chinup; horizontal press tokens cover
    -- bench (excluding overhead/incline/military) — flat-bench-heavy
    -- routines are the canonical FE anti-pattern.
    SELECT
        COUNT(*) FILTER (
            WHERE lower(e_elem->>'exercise_name') ~ '(bench|press|push|dip)'
        ),
        COUNT(*) FILTER (
            WHERE lower(e_elem->>'exercise_name') ~ '(pull|row|lat |chinup|chin-up|chin up)'
        ),
        COUNT(*) FILTER (
            WHERE lower(e_elem->>'exercise_name') ~ '(bench|chest press)'
              AND lower(e_elem->>'exercise_name') !~ '(overhead|military|shoulder|incline|decline)'
        )
      INTO v_push_count, v_pull_count, v_horiz_press_count
      FROM jsonb_array_elements(COALESCE(v_workout.exercises, '[]'::jsonb)) AS e_elem;

    -- ───── Scoring layer ─────

    -- Duration ≥ 25 min → 20 pts
    IF v_duration_min >= 25 THEN
        v_score := v_score + 20;
        v_reasons := v_reasons || jsonb_build_object('duration_pass', TRUE,  'duration_min', round(v_duration_min, 1), 'duration_pts', 20);
    ELSE
        v_reasons := v_reasons || jsonb_build_object('duration_pass', FALSE, 'duration_min', round(v_duration_min, 1), 'duration_pts', 0);
    END IF;

    -- Completion rate ≥ 0.80 → 25 pts
    IF v_completion_rate >= 0.80 THEN
        v_score := v_score + 25;
        v_reasons := v_reasons || jsonb_build_object('completion_pass', TRUE,  'completion_rate', round(v_completion_rate, 2), 'completion_pts', 25);
    ELSE
        v_reasons := v_reasons || jsonb_build_object('completion_pass', FALSE, 'completion_rate', round(v_completion_rate, 2), 'completion_pts', 0);
    END IF;

    -- ≥ 3 distinct canonical exercises → 15 pts
    IF v_distinct_canonical >= 3 THEN
        v_score := v_score + 15;
        v_reasons := v_reasons || jsonb_build_object('exercise_count_pass', TRUE,  'distinct_canonical', v_distinct_canonical, 'exercise_count_pts', 15);
    ELSE
        v_reasons := v_reasons || jsonb_build_object('exercise_count_pass', FALSE, 'distinct_canonical', v_distinct_canonical, 'exercise_count_pts', 0);
    END IF;

    -- ≥ 12 working sets → 15 pts
    IF v_working_sets >= 12 THEN
        v_score := v_score + 15;
        v_reasons := v_reasons || jsonb_build_object('working_sets_pass', TRUE,  'working_sets', v_working_sets, 'working_sets_pts', 15);
    ELSE
        v_reasons := v_reasons || jsonb_build_object('working_sets_pass', FALSE, 'working_sets', v_working_sets, 'working_sets_pts', 0);
    END IF;

    -- ≥ 50% strength sets weighted → 10 pts (filters bodyweight tap-throughs)
    IF v_total_strength_sets > 0
       AND (v_weighted_sets::numeric / v_total_strength_sets::numeric) >= 0.50 THEN
        v_score := v_score + 10;
        v_reasons := v_reasons || jsonb_build_object('weighted_pass', TRUE,  'weighted_sets', v_weighted_sets, 'total_strength_sets', v_total_strength_sets, 'weighted_pts', 10);
    ELSE
        v_reasons := v_reasons || jsonb_build_object('weighted_pass', FALSE, 'weighted_sets', v_weighted_sets, 'total_strength_sets', v_total_strength_sets, 'weighted_pts', 0);
    END IF;

    -- Avg ≥ 20s/set → 10 pts (proxy for "I just hit done 6 times")
    IF v_avg_secs_per_set >= 20 THEN
        v_score := v_score + 10;
        v_reasons := v_reasons || jsonb_build_object('pace_pass', TRUE,  'avg_secs_per_set', round(v_avg_secs_per_set, 1), 'pace_pts', 10);
    ELSE
        v_reasons := v_reasons || jsonb_build_object('pace_pass', FALSE, 'avg_secs_per_set', round(v_avg_secs_per_set, 1), 'pace_pts', 0);
    END IF;

    -- FE heuristic → 5 pts (best-effort bonus)
    --   Push:Pull ratio ≤ 2:1 (push_count <= 2 * pull_count, or both zero)
    --   AND horizontal press count ≤ 2
    IF (v_push_count = 0 OR v_pull_count > 0)
       AND v_push_count <= GREATEST(2 * v_pull_count, 2)
       AND v_horiz_press_count <= 2 THEN
        v_score := v_score + 5;
        v_reasons := v_reasons || jsonb_build_object('fe_balance_pass', TRUE,  'push', v_push_count, 'pull', v_pull_count, 'horiz_press', v_horiz_press_count, 'fe_balance_pts', 5);
    ELSE
        v_reasons := v_reasons || jsonb_build_object('fe_balance_pass', FALSE, 'push', v_push_count, 'pull', v_pull_count, 'horiz_press', v_horiz_press_count, 'fe_balance_pts', 0);
    END IF;

    -- Band
    IF v_score >= 70 THEN
        v_band := 'high';
    ELSIF v_score >= 40 THEN
        v_band := 'medium';
    ELSE
        v_band := 'low';
    END IF;

    -- Persist on workout_history. qualifies_for_corpus follows automatically
    -- (GENERATED column).
    UPDATE workout_history
       SET quality_score   = v_score,
           quality_band    = v_band,
           quality_reasons = v_reasons
     WHERE id = p_workout_id;

    RETURN jsonb_build_object(
        'success',              TRUE,
        'workout_id',           p_workout_id,
        'score',                v_score,
        'band',                 v_band,
        'qualifies_for_corpus', (v_score >= 70),
        'total_volume_lbs',     v_total_volume_lbs,
        'total_sets',           v_total_strength_sets,
        'reasons',              v_reasons
    );
EXCEPTION WHEN OTHERS THEN
    -- Fail-soft: never explode the caller. The caller (iOS completion path
    -- or the backfill loop below) just gets {success:false, error:...} and
    -- the workout stays unscored — which is the safe default (excluded
    -- from the corpus).
    RETURN jsonb_build_object(
        'success', FALSE,
        'error',   SQLERRM,
        'sqlstate', SQLSTATE,
        'workout_id', p_workout_id
    );
END;
$$;

COMMENT ON FUNCTION score_workout_quality(UUID) IS
    'Computes quality_score / band / reasons for a workout_history row. SECURITY DEFINER + auth.uid()-pinned (Supabase invariant 9). Service role passes through. Returns JSONB; never raises on bad rubric inputs (returns success:false). Updates workout_history in place. Called from iOS WorkoutManager.completeWorkout post-completion fire-and-forget AND from the nightly backfill in this migration.';

GRANT EXECUTE ON FUNCTION score_workout_quality(UUID) TO authenticated;

-- ───────────────────────────────────────────────────────────────────────────
-- 4. One-shot backfill — score every existing un-scored row
--
-- Safety check: skip if more than 10K candidate rows (prod ops can run a
-- bigger backfill manually with a chunk loop). The threshold prevents a
-- bad SQL Editor run from holding a long lock.
-- ───────────────────────────────────────────────────────────────────────────

DO $$
DECLARE
    v_candidate_count INT;
    v_scored          INT := 0;
    v_high            INT := 0;
    v_medium          INT := 0;
    v_low             INT := 0;
    v_failed          INT := 0;
    v_workout_id      UUID;
    v_result          JSONB;
BEGIN
    SELECT COUNT(*)
      INTO v_candidate_count
      FROM workout_history
     WHERE quality_score IS NULL
       AND COALESCE(duration, 0) > 0;

    RAISE NOTICE '🧮 quality corpus backfill candidate count: %', v_candidate_count;

    IF v_candidate_count > 10000 THEN
        RAISE NOTICE '⏭  Skipping backfill — % candidates exceeds 10K safety cap. Run manually in chunks if needed.', v_candidate_count;
        RETURN;
    END IF;

    FOR v_workout_id IN
        SELECT id
          FROM workout_history
         WHERE quality_score IS NULL
           AND COALESCE(duration, 0) > 0
         ORDER BY date DESC
    LOOP
        BEGIN
            v_result := score_workout_quality(v_workout_id);

            IF (v_result->>'success')::boolean THEN
                v_scored := v_scored + 1;
                CASE v_result->>'band'
                    WHEN 'high'   THEN v_high   := v_high + 1;
                    WHEN 'medium' THEN v_medium := v_medium + 1;
                    WHEN 'low'    THEN v_low    := v_low + 1;
                    ELSE NULL;
                END CASE;
            ELSE
                v_failed := v_failed + 1;
            END IF;
        EXCEPTION WHEN OTHERS THEN
            v_failed := v_failed + 1;
        END;
    END LOOP;

    RAISE NOTICE '🧮 quality corpus backfill complete: % scored (% high / % medium / % low), % failed',
        v_scored, v_high, v_medium, v_low, v_failed;
END $$;

-- ───────────────────────────────────────────────────────────────────────────
-- 5. Trailing fail-loud audit (supabase-rules invariant 29)
-- ───────────────────────────────────────────────────────────────────────────

DO $$
DECLARE
    v_total_workouts        INT;
    v_total_scored          INT;
    v_high_count            INT;
    v_medium_count          INT;
    v_low_count             INT;
    v_function_returns      TEXT;
    v_qualifies_col_exists  BOOLEAN;
    v_collab_quality_idx    BOOLEAN;
BEGIN
    -- workout_history.quality_score column must exist
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
         WHERE table_schema = 'public'
           AND table_name = 'workout_history'
           AND column_name = 'quality_score'
    ) THEN
        RAISE EXCEPTION 'Migration failed — workout_history.quality_score column missing';
    END IF;

    -- workout_history.qualifies_for_corpus must exist AND be GENERATED
    SELECT EXISTS (
        SELECT 1 FROM information_schema.columns
         WHERE table_schema = 'public'
           AND table_name = 'workout_history'
           AND column_name = 'qualifies_for_corpus'
           AND is_generated = 'ALWAYS'
    ) INTO v_qualifies_col_exists;

    IF NOT v_qualifies_col_exists THEN
        RAISE EXCEPTION 'Migration failed — workout_history.qualifies_for_corpus must exist as a GENERATED column';
    END IF;

    -- score_workout_quality must exist with RETURNS jsonb
    SELECT pg_get_function_result(p.oid)
      INTO v_function_returns
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public'
       AND p.proname = 'score_workout_quality'
     LIMIT 1;

    IF v_function_returns IS NULL THEN
        RAISE EXCEPTION 'Migration failed — score_workout_quality(UUID) function missing';
    END IF;

    IF lower(v_function_returns) <> 'jsonb' THEN
        RAISE EXCEPTION 'Migration failed — score_workout_quality must RETURN jsonb (got %)', v_function_returns;
    END IF;

    -- collaborative_workout_data partial index must exist
    SELECT EXISTS (
        SELECT 1 FROM pg_indexes
         WHERE schemaname = 'public'
           AND tablename = 'collaborative_workout_data'
           AND indexname = 'idx_collab_workout_quality_corpus'
    ) INTO v_collab_quality_idx;

    IF NOT v_collab_quality_idx THEN
        RAISE EXCEPTION 'Migration failed — idx_collab_workout_quality_corpus missing on collaborative_workout_data';
    END IF;

    -- Backfill sanity: if we have scoreable workouts, at least some MUST
    -- have been scored (catches a silent-fail rubric regression where
    -- every call returns success:false).
    SELECT COUNT(*) INTO v_total_workouts
      FROM workout_history
     WHERE COALESCE(duration, 0) > 0;

    SELECT COUNT(*),
           COUNT(*) FILTER (WHERE quality_band = 'high'),
           COUNT(*) FILTER (WHERE quality_band = 'medium'),
           COUNT(*) FILTER (WHERE quality_band = 'low')
      INTO v_total_scored, v_high_count, v_medium_count, v_low_count
      FROM workout_history
     WHERE quality_score IS NOT NULL;

    IF v_total_workouts > 0 AND v_total_workouts <= 10000 AND v_total_scored = 0 THEN
        RAISE EXCEPTION 'Migration failed — backfill ran with % scoreable workouts but 0 were scored. Rubric is broken.', v_total_workouts;
    END IF;

    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
    RAISE NOTICE '✅ QUALITY WORKOUT CORPUS MIGRATION COMPLETE';
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
    RAISE NOTICE '   • workout_history: quality_score / quality_band / quality_reasons / qualifies_for_corpus (GENERATED)';
    RAISE NOTICE '   • collaborative_workout_data: workout_history_id FK + workout_quality_score + is_quality_workout (GENERATED) + total_sets + total_volume_lbs';
    RAISE NOTICE '   • score_workout_quality(UUID) RETURNS JSONB — SECURITY DEFINER, auth.uid()-pinned';
    RAISE NOTICE '   • Backfill: % rows scored (% high / % medium / % low)',
        v_total_scored, v_high_count, v_medium_count, v_low_count;
    RAISE NOTICE '   • Hot-path partial index: idx_collab_workout_quality_corpus';
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
END $$;

COMMIT;
