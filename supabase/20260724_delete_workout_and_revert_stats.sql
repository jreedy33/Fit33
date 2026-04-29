-- ═══════════════════════════════════════════════════════════════════════════
-- 20260724_delete_workout_and_revert_stats.sql
--
-- Atomic "delete a completed workout AND reverse every server-side stat
-- side-effect" RPC. Powers the new Delete button on the workout completion
-- screen.
--
-- WHY
-- ---
-- `Fit33/WorkoutManager.swift::completeWorkout` and
-- `Fit33/ActiveWorkoutView+Actions.swift::finishWorkout` eagerly write to
-- six server-side surfaces BEFORE the user sees the completion screen:
--   1. `workout_history` (the main row)
--   2. `exercise_performance_history` (one row per exercise)
--   3. `exercise_set_history` (one row per completed set, FK
--      `performance_id → exercise_performance_history.id`)
--   4. `collaborative_workout_data` (training corpus row)
--   5. `user_progress` (total_xp + total_workouts ticks up)
--   6. `user_daily_quests` (complete_workout slot ticks up)
--   7. `league_point_awards` (ledger row from #148, source = 'workout',
--       awarded_points credited to either `league_members.points` for
--       the placed week OR `user_league_tier.pending_league_points`
--       for pre-placement users)
--
-- If the user looks at the completion screen and decides "nope, that
-- doesn't count", they need a way to atomically REVERSE all of that. This
-- RPC is that atomic reversal.
--
-- WHAT THIS MIGRATION DOES
-- ------------------------
-- Creates `delete_workout_and_revert_stats(p_workout_id UUID) RETURNS JSONB`,
-- SECURITY DEFINER, IDOR-pinned per Supabase invariant 9. The function body
-- IS the transaction (Postgres functions run in a single statement-level
-- transaction by default). Steps in order:
--
--   (a) Look up the workout (id, user_id, xp_earned, duration, date).
--       Return {success:false, reason:'not_found'} if absent.
--   (b) Auth gate: workout user_id must equal auth.uid() (or service role).
--       Raises 42501 Forbidden otherwise.
--   (c) DELETE exercise_set_history WHERE performance_id IN
--       (SELECT id FROM exercise_performance_history WHERE workout_id = …).
--       Capture rowcount.
--   (d) DELETE exercise_performance_history WHERE workout_id = …
--       Capture rowcount.
--   (e) DELETE collaborative_workout_data WHERE workout_history_id = …
--       (defense-in-depth — the FK CASCADE from #154 also covers this).
--   (f) Reverse league points: SUM(awarded_points) for matching ledger
--       rows, DELETE them, then decrement either `league_members.points`
--       (placed case) or `user_league_tier.pending_league_points`
--       (pre-placement). Monday computed via the canonical ISODOW formula
--       `(d - EXTRACT(ISODOW FROM d)::int + 1)::date`.
--   (g) Reverse daily quest progress on `complete_workout` /
--       `complete_program_day` / `do_friend_workout` / `workout_30_min`
--       slot keys for the workout's date. Reset is_completed back to
--       FALSE only if the new value falls below target.
--   (h) Reverse user_progress.total_xp and total_workouts (clamped at 0).
--   (i) DELETE workout_history WHERE id = … (LAST — also CASCADEs the
--       new collaborative_workout_data.workout_history_id FK from #154,
--       but step (e) already cleared that path explicitly).
--
-- Streak reversal is NOT done server-side. Streak revert is conditional
-- ("only if THIS was the only workout today") and the server can't know
-- that without joining `cardio_workouts` and any other workout-history
-- rows for the same date. The iOS client owns the conditional streak
-- revert in `WorkoutManager.deleteCompletedWorkout` (paired commit). See
-- §"Streak revert is iOS-side" comment below.
--
-- INVARIANTS
-- ----------
--   • SECURITY DEFINER + auth.uid()-pinned (Supabase invariant 9).
--   • Function body is the transaction — every DELETE either commits as
--     a unit or all roll back if any error fires.
--   • RETURNS JSONB with structured fields so the iOS client can show
--     accurate "reverted +N XP, -M league points" feedback.
--   • Idempotent: running it twice on the same workout returns
--     {success:false, reason:'not_found'} on the second call.
--   • The new `collaborative_workout_data.workout_history_id` FK CASCADE
--     from migration #154 means the corpus row is purged automatically
--     even if step (e) hadn't run — defense-in-depth.
--
-- DEPENDS ON
-- ----------
--   • Migration #154 (20260723_quality_workout_corpus.sql) — adds
--     `collaborative_workout_data.workout_history_id` FK so the explicit
--     DELETE in step (e) actually has a column to filter on. If you ship
--     this without #154 the DELETE becomes a no-op (column doesn't
--     exist) and the migration fails. Run #154 FIRST.
--   • `league_point_awards` table from migration #148
--     (20260717_league_sprint3_caps_peak_day.sql).
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

-- Drop every known overload first (Supabase invariant 12). This RPC is
-- new, but defensive DROP keeps re-deploys idempotent.
DROP FUNCTION IF EXISTS delete_workout_and_revert_stats(UUID);
DROP FUNCTION IF EXISTS delete_workout_and_revert_stats(TEXT);
DROP FUNCTION IF EXISTS public.delete_workout_and_revert_stats(UUID);
DROP FUNCTION IF EXISTS public.delete_workout_and_revert_stats(TEXT);

CREATE OR REPLACE FUNCTION delete_workout_and_revert_stats(p_workout_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    -- Lookup
    v_user_id              UUID;
    v_xp_earned            INT;
    v_duration_sec         INT;
    v_workout_date_ts      TIMESTAMPTZ;
    v_workout_date         DATE;
    v_workout_monday       DATE;

    -- Counters
    v_set_rows_deleted     INT := 0;
    v_perf_rows_deleted    INT := 0;
    v_collab_rows_deleted  INT := 0;
    v_quest_rows_updated   INT := 0;
    v_workout_rows_deleted INT := 0;

    -- League reversal
    v_league_points_reverted    INT := 0;
    v_league_award_rows_deleted INT := 0;
    v_league_members_updated    INT := 0;
    v_pending_updated           INT := 0;
BEGIN
    -- (a) Look up the workout. We pull `date` as TIMESTAMPTZ (cast tolerates
    -- both TIMESTAMPTZ and TEXT-ISO8601 storage shapes — workout_history.date
    -- is a TIMESTAMPTZ string in Swift, stored as TIMESTAMPTZ in Postgres).
    SELECT user_id, COALESCE(xp_earned, 0), COALESCE(duration, 0), date::timestamptz
      INTO v_user_id, v_xp_earned, v_duration_sec, v_workout_date_ts
      FROM workout_history
     WHERE id = p_workout_id;

    IF v_user_id IS NULL THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'reason',  'not_found',
            'workout_id', p_workout_id
        );
    END IF;

    -- (b) Auth gate (Supabase invariant 9). Service role passes through.
    IF auth.uid() IS NOT NULL AND v_user_id <> auth.uid() THEN
        RAISE EXCEPTION 'Forbidden: cannot delete another user''s workout'
            USING ERRCODE = '42501';
    END IF;

    -- Derive the workout's date + Monday (canonical ISODOW formula —
    -- ISODOW: 1=Mon..7=Sun, so Mon - 1 + 1 = Mon, Sun - 7 + 1 = Mon).
    v_workout_date   := v_workout_date_ts::date;
    v_workout_monday := (v_workout_date - EXTRACT(ISODOW FROM v_workout_date)::int + 1)::date;

    -- (c) DELETE exercise_set_history via subquery on performance_id. MUST
    -- run BEFORE (d) — the subquery resolves while exercise_performance_history
    -- still has the parent rows.
    WITH del AS (
        DELETE FROM exercise_set_history
         WHERE performance_id IN (
             SELECT id FROM exercise_performance_history
              WHERE workout_id = p_workout_id
                AND user_id = v_user_id
         )
        RETURNING 1
    )
    SELECT COUNT(*) INTO v_set_rows_deleted FROM del;

    -- (d) DELETE exercise_performance_history rows tied to this workout.
    WITH del AS (
        DELETE FROM exercise_performance_history
         WHERE workout_id = p_workout_id
           AND user_id = v_user_id
        RETURNING 1
    )
    SELECT COUNT(*) INTO v_perf_rows_deleted FROM del;

    -- (e) DELETE collaborative_workout_data rows referencing this workout.
    -- The FK CASCADE from migration #154 also covers this when the
    -- workout_history row is deleted in step (i), but the explicit DELETE
    -- here is defense-in-depth and gives us an accurate count.
    WITH del AS (
        DELETE FROM collaborative_workout_data
         WHERE workout_history_id = p_workout_id
           AND user_id = v_user_id
        RETURNING 1
    )
    SELECT COUNT(*) INTO v_collab_rows_deleted FROM del;

    -- (f) Reverse league points.
    --
    -- Source-of-truth note: `league_point_awards.awarded_points` already
    -- has the Peak Day multiplier baked in (add_league_points stores
    -- v_effective_points = p_points * v_multiplier). So we sum
    -- awarded_points DIRECTLY — multiplying again would double-count.
    --
    -- Match scope: source='workout' AND awarded_date = v_workout_date.
    -- LIMIT 1 ORDER BY awarded_at DESC is intentional — a user could log
    -- multiple workouts in a day; we only reverse the most-recent
    -- workout-source award row, which by ordering corresponds to the
    -- workout being deleted (workouts complete in chronological order).
    -- See "Open question" in the migration index for the long-term fix
    -- (storing workout_id on the award row).
    WITH revertable AS (
        SELECT id, awarded_points
          FROM league_point_awards
         WHERE user_id = v_user_id
           AND source = 'workout'
           AND awarded_date = v_workout_date
         ORDER BY awarded_at DESC
         LIMIT 1
    ),
    deleted AS (
        DELETE FROM league_point_awards
         WHERE id IN (SELECT id FROM revertable)
        RETURNING awarded_points
    )
    SELECT COALESCE(SUM(awarded_points), 0)::int, COUNT(*)::int
      INTO v_league_points_reverted, v_league_award_rows_deleted
      FROM deleted;

    -- Decrement the placed-week membership row first (most common case).
    IF v_league_points_reverted > 0 THEN
        WITH upd AS (
            UPDATE league_members lm
               SET points = GREATEST(0, lm.points - v_league_points_reverted),
                   workouts_completed = GREATEST(0, lm.workouts_completed - 1)
              FROM league_groups lg
             WHERE lm.group_id = lg.id
               AND lm.user_id = v_user_id
               AND lg.week_start = v_workout_monday
            RETURNING 1
        )
        SELECT COUNT(*) INTO v_league_members_updated FROM upd;

        -- Pre-placement fallback: if no league_members row matched (the
        -- workout was logged before the user was placed), the points
        -- went into user_league_tier.pending_league_points. Decrement
        -- that bucket instead.
        IF v_league_members_updated = 0 THEN
            WITH upd AS (
                UPDATE user_league_tier
                   SET pending_league_points = GREATEST(0, COALESCE(pending_league_points, 0) - v_league_points_reverted),
                       updated_at = now()
                 WHERE user_id = v_user_id
                RETURNING 1
            )
            SELECT COUNT(*) INTO v_pending_updated FROM upd;
        END IF;
    END IF;

    -- (g) Reverse daily quest progress for workout-class quest_keys on the
    -- workout's date. We touch `current_value` (clamped at 0) and only
    -- flip is_completed back to FALSE if the new value falls below target.
    WITH upd AS (
        UPDATE user_daily_quests
           SET current_value = GREATEST(0, current_value - 1),
               is_completed  = CASE
                   WHEN GREATEST(0, current_value - 1) >= target_value
                   THEN is_completed
                   ELSE FALSE
               END,
               completed_at  = CASE
                   WHEN GREATEST(0, current_value - 1) >= target_value
                   THEN completed_at
                   ELSE NULL
               END
         WHERE user_id    = v_user_id
           AND quest_date = v_workout_date
           AND quest_key IN ('complete_workout', 'complete_program_day', 'do_friend_workout', 'workout_30_min')
           AND current_value > 0
        RETURNING 1
    )
    SELECT COUNT(*) INTO v_quest_rows_updated FROM upd;

    -- (h) Reverse user_progress totals. Clamped to 0 so a stat skew (XP
    -- already debited via something else) never produces negatives.
    UPDATE user_progress
       SET total_xp        = GREATEST(0, COALESCE(total_xp, 0) - v_xp_earned),
           total_workouts  = GREATEST(0, COALESCE(total_workouts, 0) - 1)
     WHERE user_id = v_user_id;

    -- (i) Finally, delete the workout_history row. Any cascading FKs (the
    -- new #154 collaborative_workout_data FK; legacy workout_exercises /
    -- workout_sets if they exist) fire here.
    WITH del AS (
        DELETE FROM workout_history
         WHERE id = p_workout_id
           AND user_id = v_user_id
        RETURNING 1
    )
    SELECT COUNT(*) INTO v_workout_rows_deleted FROM del;

    -- Streak revert is iOS-side (see header). Server returns the date so
    -- the client can run its conditional check ("was this the only
    -- workout today?") against local Core Data + cardio_workouts.

    RETURN jsonb_build_object(
        'success',                    TRUE,
        'workout_id',                 p_workout_id,
        'user_id',                    v_user_id,
        'workout_date',               v_workout_date,
        'xp_reverted',                v_xp_earned,
        'league_points_reverted',     v_league_points_reverted,
        'league_award_rows_deleted',  v_league_award_rows_deleted,
        'league_members_updated',     v_league_members_updated,
        'pending_updated',            v_pending_updated,
        'perf_rows_deleted',          v_perf_rows_deleted,
        'set_rows_deleted',           v_set_rows_deleted,
        'collab_rows_deleted',        v_collab_rows_deleted,
        'quest_rows_updated',         v_quest_rows_updated,
        'workout_rows_deleted',       v_workout_rows_deleted
    );
END;
$$;

COMMENT ON FUNCTION delete_workout_and_revert_stats(UUID) IS
    'Atomically delete a completed workout AND reverse every server-side stat side-effect: exercise_set_history, exercise_performance_history, collaborative_workout_data, league_point_awards (+ league_members.points OR user_league_tier.pending_league_points), user_daily_quests (workout-class slots only), user_progress.total_xp + total_workouts. SECURITY DEFINER, auth.uid()-pinned (Supabase invariant 9). RETURNS structured JSONB. Streak revert is iOS-side (conditional on "was this the only workout today" — server cannot know without joining cardio_workouts).';

REVOKE EXECUTE ON FUNCTION delete_workout_and_revert_stats(UUID) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION delete_workout_and_revert_stats(UUID) TO authenticated;

-- ───────────────────────────────────────────────────────────────────────────
-- Trailing fail-loud audit (supabase-rules invariant 29)
-- ───────────────────────────────────────────────────────────────────────────

DO $$
DECLARE
    v_func_count    INT;
    v_func_returns  TEXT;
    v_prosrc        TEXT;
BEGIN
    -- Function must exist exactly once.
    SELECT COUNT(*)
      INTO v_func_count
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public'
       AND p.proname = 'delete_workout_and_revert_stats';

    IF v_func_count = 0 THEN
        RAISE EXCEPTION 'Migration failed — delete_workout_and_revert_stats(UUID) function missing';
    END IF;

    IF v_func_count > 1 THEN
        RAISE EXCEPTION 'Migration failed — delete_workout_and_revert_stats has % overloads (expected 1). DROP all overloads then re-deploy.', v_func_count;
    END IF;

    -- Must return JSONB.
    SELECT pg_get_function_result(p.oid), p.prosrc
      INTO v_func_returns, v_prosrc
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public'
       AND p.proname = 'delete_workout_and_revert_stats';

    IF lower(v_func_returns) <> 'jsonb' THEN
        RAISE EXCEPTION 'Migration failed — delete_workout_and_revert_stats must RETURN jsonb (got %)', v_func_returns;
    END IF;

    -- IDOR guard must be present in prosrc. The canonical pattern is
    -- `auth.uid() IS NOT NULL AND <user_var> <> auth.uid()` followed by
    -- a 42501 RAISE. We check for both halves separately so a future
    -- refactor that splits the guard across lines still passes.
    IF v_prosrc !~ 'auth\.uid\(\)\s+IS\s+NOT\s+NULL' THEN
        RAISE EXCEPTION 'Migration failed — delete_workout_and_revert_stats prosrc lacks auth.uid() IS NOT NULL guard (Supabase invariant 9)';
    END IF;

    IF v_prosrc !~ '<>\s*auth\.uid\(\)' THEN
        RAISE EXCEPTION 'Migration failed — delete_workout_and_revert_stats prosrc lacks <> auth.uid() IDOR comparison (Supabase invariant 9)';
    END IF;

    IF v_prosrc !~ '42501' THEN
        RAISE EXCEPTION 'Migration failed — delete_workout_and_revert_stats prosrc lacks 42501 Forbidden ERRCODE (Supabase invariant 9)';
    END IF;

    -- Sanity: the body must touch every reversal target. If a future
    -- refactor accidentally drops one of the side-effect reversals, the
    -- audit catches it.
    IF v_prosrc !~ 'exercise_set_history' THEN
        RAISE EXCEPTION 'Migration failed — delete_workout_and_revert_stats prosrc missing exercise_set_history reversal';
    END IF;
    IF v_prosrc !~ 'exercise_performance_history' THEN
        RAISE EXCEPTION 'Migration failed — delete_workout_and_revert_stats prosrc missing exercise_performance_history reversal';
    END IF;
    IF v_prosrc !~ 'league_point_awards' THEN
        RAISE EXCEPTION 'Migration failed — delete_workout_and_revert_stats prosrc missing league_point_awards reversal';
    END IF;
    IF v_prosrc !~ 'user_daily_quests' THEN
        RAISE EXCEPTION 'Migration failed — delete_workout_and_revert_stats prosrc missing user_daily_quests reversal';
    END IF;
    IF v_prosrc !~ 'user_progress' THEN
        RAISE EXCEPTION 'Migration failed — delete_workout_and_revert_stats prosrc missing user_progress reversal';
    END IF;
    IF v_prosrc !~ 'workout_history' THEN
        RAISE EXCEPTION 'Migration failed — delete_workout_and_revert_stats prosrc missing workout_history DELETE';
    END IF;

    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
    RAISE NOTICE '✅ delete_workout_and_revert_stats DEPLOYED';
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
    RAISE NOTICE '   • RETURNS jsonb';
    RAISE NOTICE '   • SECURITY DEFINER + auth.uid()-pinned (42501 on cross-user)';
    RAISE NOTICE '   • Reverses: exercise_set_history, exercise_performance_history,';
    RAISE NOTICE '              collaborative_workout_data, league_point_awards,';
    RAISE NOTICE '              league_members.points OR pending_league_points,';
    RAISE NOTICE '              user_daily_quests (workout-class), user_progress totals,';
    RAISE NOTICE '              workout_history';
    RAISE NOTICE '   • Streak revert is iOS-side (conditional on "only workout today")';
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
END $$;

COMMIT;
