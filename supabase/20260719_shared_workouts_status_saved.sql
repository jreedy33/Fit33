-- 20260719_shared_workouts_status_saved.sql
-- Hotfix — drains bug-intel clusters `69b01dea` (crash) + `eb041521` (log):
-- pg:23514 "new row for relation 'shared_workouts' violates check
-- constraint 'shared_workouts_status_check'".
--
-- ROOT CAUSE
-- ----------
-- `Fit33/FriendService.swift::saveSharedWorkout` (line 1099) writes
-- `status = "saved"` when the user taps "Save to favorites" on an
-- inbound shared workout. The other status mutation paths in the same
-- file already use the canonical enum:
--   - `accepted`  (acceptWorkout)
--   - `declined`  (declineWorkout)
--   - `started`   (markWorkoutStarted)
--   - `completed` (markWorkoutCompleted)
--
-- The on-prod `shared_workouts_status_check` CHECK constraint was
-- created without `'saved'` in the allowed-values list — likely a
-- regression from the original 1v1 challenge migration where the
-- enum was tightened. Result: every "Save to favorites" tap on a
-- received workout emits a 23514, the optimistic UI removes the row
-- locally, but the server-side row stays in `accepted` / `pending` —
-- and on the next `fetchReceivedWorkouts` it pops back into the
-- inbox unless `addressedWorkoutIds` (in-memory only) still has it.
--
-- FIX
-- ---
-- Widen the CHECK constraint to include `'saved'`. We DROP-then-CREATE
-- so the new allowlist replaces the old one cleanly, with a guard that
-- skips the migration when the table doesn't exist (staging clones).
--
-- `'saved'` is the canonical end-state for a workout the user wanted
-- to keep but hasn't started yet. The companion column
-- `saved_to_favorites BOOLEAN` is set in the same UPDATE — they're
-- redundant by design (status is the lifecycle state machine,
-- saved_to_favorites is the user-action breadcrumb).
--
-- INVARIANTS
-- ----------
--   * Idempotent — DROP / CREATE.
--   * Backwards-compatible — every prior allowed value (pending,
--     accepted, declined, started, completed) is preserved.
--   * No call-site changes — the existing
--     `SaveWorkoutUpdate(status: "saved", saved_to_favorites: true)`
--     payload now passes the constraint.
-- Resolves: 69b01dea71a762f9bad04de646cfd120, eb041521…

BEGIN;

DO $$
BEGIN
    IF to_regclass('public.shared_workouts') IS NULL THEN
        RAISE NOTICE '[20260719] shared_workouts not present — skipping.';
        RETURN;
    END IF;

    -- 1. Drop the existing CHECK constraint (any name variant). The
    --    constraint may also exist under the legacy `valid_status`
    --    label from a hand-applied dashboard fix.
    EXECUTE 'ALTER TABLE public.shared_workouts
                 DROP CONSTRAINT IF EXISTS shared_workouts_status_check';
    EXECUTE 'ALTER TABLE public.shared_workouts
                 DROP CONSTRAINT IF EXISTS valid_status';

    -- 2. Re-create with the full allowlist including 'saved'.
    --    NULL is not allowed — every row must have a status set on
    --    INSERT (default 'pending' is enforced by the column default
    --    on prod).
    EXECUTE $sql$
        ALTER TABLE public.shared_workouts
            ADD CONSTRAINT shared_workouts_status_check
            CHECK (status IN (
                'pending',
                'accepted',
                'declined',
                'started',
                'completed',
                'saved'
            ))
    $sql$;

    RAISE NOTICE '[20260719] shared_workouts_status_check widened to include ''saved''.';
END $$;

-- Audit — confirm the new constraint exists with the expected definition.
DO $$
DECLARE
    v_def TEXT;
BEGIN
    IF to_regclass('public.shared_workouts') IS NULL THEN
        RAISE NOTICE '[20260719] shared_workouts not present — audit skipped.';
        RETURN;
    END IF;

    SELECT pg_get_constraintdef(c.oid) INTO v_def
      FROM pg_constraint c
      JOIN pg_class cl ON cl.oid = c.conrelid
      JOIN pg_namespace n ON n.oid = cl.relnamespace
     WHERE n.nspname = 'public'
       AND cl.relname = 'shared_workouts'
       AND c.conname = 'shared_workouts_status_check';

    IF v_def IS NULL THEN
        RAISE EXCEPTION
            '[20260719] shared_workouts_status_check missing after migration';
    END IF;

    IF position('saved' IN v_def) = 0 THEN
        RAISE EXCEPTION
            '[20260719] shared_workouts_status_check does not include ''saved'' (def: %)',
            v_def;
    END IF;

    RAISE NOTICE '✅ shared_workouts_status_check: %', v_def;
END $$;

COMMIT;
