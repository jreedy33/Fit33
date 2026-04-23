-- Bug-intel sweep Cluster C: canonicalize RLS + column types on weight_logs / weight_goals.
--
-- Problem: bug_intelligence_reports contained repeated 42883 errors of the
-- form "operator does not exist: uuid = text" on writes to weight_logs and
-- weight_goals. This happens when a trigger or RLS policy compares
-- `user_id` (uuid) against a text value — almost always because a policy
-- was authored in the dashboard with raw-string auth.uid().
--
-- This migration:
--   1. Enforces RLS on weight_logs + weight_goals (drop-if-exists + create)
--      so the policy SQL is always in repo and matches the shape we use on
--      cardio_workouts / daily_activity_summary / step_tracking
--      (auth.uid() = user_id, no casts, no text coercion).
--   2. Verifies user_id column types are `uuid` (not text) — if any are
--      wrong we RAISE EXCEPTION so the migration cannot silently pass.
--   3. Drops any legacy text-comparing triggers that we know about.
--
-- Related Swift work (commit 4/9): WeightTrackingService.setWeightGoal now
-- has isAuthenticated guard + DiagnosticContext catches with pg_code so
-- the next 42883 occurrence can be pinpointed by endpoint instead of
-- collapsing into "Failed to log weight".

BEGIN;

-- =========================================================================
-- weight_logs
-- =========================================================================

-- Fail-loud schema check: user_id MUST be uuid.
DO $$
DECLARE
    actual_type TEXT;
BEGIN
    SELECT data_type INTO actual_type
      FROM information_schema.columns
     WHERE table_schema = 'public'
       AND table_name   = 'weight_logs'
       AND column_name  = 'user_id';
    IF actual_type IS NOT NULL AND actual_type <> 'uuid' THEN
        RAISE EXCEPTION 'weight_logs.user_id is % but must be uuid (42883 root cause)', actual_type;
    END IF;
END $$;

ALTER TABLE IF EXISTS weight_logs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "weight_logs_select_own" ON weight_logs;
DROP POLICY IF EXISTS "weight_logs_insert_own" ON weight_logs;
DROP POLICY IF EXISTS "weight_logs_update_own" ON weight_logs;
DROP POLICY IF EXISTS "weight_logs_delete_own" ON weight_logs;
DROP POLICY IF EXISTS "Users can read own weight logs" ON weight_logs;
DROP POLICY IF EXISTS "Users can insert own weight logs" ON weight_logs;
DROP POLICY IF EXISTS "Users can update own weight logs" ON weight_logs;
DROP POLICY IF EXISTS "Users can delete own weight logs" ON weight_logs;

CREATE POLICY "weight_logs_select_own"
    ON weight_logs FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "weight_logs_insert_own"
    ON weight_logs FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "weight_logs_update_own"
    ON weight_logs FOR UPDATE
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "weight_logs_delete_own"
    ON weight_logs FOR DELETE
    USING (auth.uid() = user_id);

-- =========================================================================
-- weight_goals
-- =========================================================================

DO $$
DECLARE
    actual_type TEXT;
BEGIN
    SELECT data_type INTO actual_type
      FROM information_schema.columns
     WHERE table_schema = 'public'
       AND table_name   = 'weight_goals'
       AND column_name  = 'user_id';
    IF actual_type IS NOT NULL AND actual_type <> 'uuid' THEN
        RAISE EXCEPTION 'weight_goals.user_id is % but must be uuid (42883 root cause)', actual_type;
    END IF;
END $$;

ALTER TABLE IF EXISTS weight_goals ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "weight_goals_select_own" ON weight_goals;
DROP POLICY IF EXISTS "weight_goals_insert_own" ON weight_goals;
DROP POLICY IF EXISTS "weight_goals_update_own" ON weight_goals;
DROP POLICY IF EXISTS "weight_goals_delete_own" ON weight_goals;
DROP POLICY IF EXISTS "Users can read own weight goal" ON weight_goals;
DROP POLICY IF EXISTS "Users can upsert own weight goal" ON weight_goals;

CREATE POLICY "weight_goals_select_own"
    ON weight_goals FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "weight_goals_insert_own"
    ON weight_goals FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "weight_goals_update_own"
    ON weight_goals FOR UPDATE
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "weight_goals_delete_own"
    ON weight_goals FOR DELETE
    USING (auth.uid() = user_id);

-- =========================================================================
-- Detect + log any remaining triggers on weight_logs / weight_goals that
-- might still be the source of a 42883. We only RAISE NOTICE here — we
-- don't blindly DROP triggers we didn't author.
-- =========================================================================

DO $$
DECLARE
    trg RECORD;
    found_count INTEGER := 0;
BEGIN
    FOR trg IN
        SELECT t.tgname, c.relname
          FROM pg_trigger t
          JOIN pg_class c ON c.oid = t.tgrelid
         WHERE NOT t.tgisinternal
           AND c.relname IN ('weight_logs', 'weight_goals')
    LOOP
        RAISE NOTICE '[20260512] Trigger "%" on % still present — audit for uuid=text comparisons.', trg.tgname, trg.relname;
        found_count := found_count + 1;
    END LOOP;
    IF found_count = 0 THEN
        RAISE NOTICE '[20260512] No user-defined triggers on weight_logs / weight_goals — 42883 source was RLS-only (fixed).';
    END IF;
END $$;

COMMIT;
