-- ═══════════════════════════════════════════════════════════════════════════
-- 20260523_fix_activity_recovery_check_constraint.sql
-- Widen `activity_recovery_correlation_activity_level_check` so the 8 values
-- the iOS client actually writes are all accepted.
-- ═══════════════════════════════════════════════════════════════════════════
--
-- Bug report (from 1.38 (53) session logs, fingerprint fires EVERY session):
--
--   ⚠️ [INTELLIGENCE] Failed to track activity:
--      PostgrestError code "23514"
--      "new row for relation \"activity_recovery_correlation\"
--       violates check constraint
--       \"activity_recovery_correlation_activity_level_check\""
--
-- Root cause: the original check constraint (written when only steps-based
-- levels existed) does not include the WHOOP recovery-level strings added
-- later. `Fit33/AdvancedIntelligenceService.swift::trackActivityForRecovery`
-- writes one of these 8 strings today:
--
--   Steps-based (getActivityLevel):
--     - "sedentary"    (<3000 steps)
--     - "light"        (3000-4999)
--     - "normal"       (5000-9999)
--     - "active"       (10000-14999)
--     - "very_active"  (15000+)
--
--   WHOOP recovery-based (when WhoopService.isConnected):
--     - "fatigued"     (red)
--     - "moderate"     (yellow)
--     - "well_rested"  (green)
--
-- Fix: drop the old CHECK constraint if it exists, replace with one that
-- covers all 8 values. Idempotent — safe to re-run.
--
-- Impact on client:
-- - Two spurious `AppLogger.warning` per session stop firing.
-- - `advanced_recovery_views` views that JOIN on `activity_recovery_correlation`
--   actually see today's data instead of the last successful pre-regression
--   upsert.
-- - Recovery recommendations (fatigued / moderate / well_rested) become
--   queryable for the Welcome card nudges.
--
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

DO $$
DECLARE
  constraint_exists boolean;
BEGIN
  -- Is there an existing check on activity_level? Drop whatever it is —
  -- constraint name pattern depends on how the column was added originally
  -- (could be *_activity_level_check OR a user-named one).
  SELECT EXISTS (
    SELECT 1
    FROM pg_constraint c
    JOIN pg_class t ON t.oid = c.conrelid
    WHERE t.relname = 'activity_recovery_correlation'
      AND c.contype = 'c'
      AND pg_get_constraintdef(c.oid) ILIKE '%activity_level%'
  ) INTO constraint_exists;

  IF constraint_exists THEN
    -- Drop every activity_level-mentioning check on this table
    EXECUTE (
      SELECT string_agg(
        format('ALTER TABLE public.activity_recovery_correlation DROP CONSTRAINT %I;',
               c.conname),
        E'\n'
      )
      FROM pg_constraint c
      JOIN pg_class t ON t.oid = c.conrelid
      WHERE t.relname = 'activity_recovery_correlation'
        AND c.contype = 'c'
        AND pg_get_constraintdef(c.oid) ILIKE '%activity_level%'
    );
    RAISE NOTICE '✅ Dropped existing activity_level check constraint(s)';
  ELSE
    RAISE NOTICE 'ℹ️  No existing activity_level check constraint found';
  END IF;
END $$;

-- Recreate with the canonical 8-value allowlist. NOTE: the iOS client is the
-- single writer — if you add a new enum string there, add it here in the same
-- PR or upserts start 23514-ing again. See
-- `Fit33/AdvancedIntelligenceService.swift::getActivityLevel` for the
-- steps-based tiers and the WHOOP switch in `trackActivityForRecovery`.
ALTER TABLE public.activity_recovery_correlation
  ADD CONSTRAINT activity_recovery_correlation_activity_level_check
  CHECK (activity_level IN (
    -- Steps-based
    'sedentary',
    'light',
    'normal',
    'active',
    'very_active',
    -- WHOOP recovery-based
    'fatigued',
    'moderate',
    'well_rested'
  ));

COMMIT;

-- Verify (run after deploy):
--   SELECT pg_get_constraintdef(c.oid)
--   FROM pg_constraint c
--   JOIN pg_class t ON t.oid = c.conrelid
--   WHERE t.relname = 'activity_recovery_correlation'
--     AND c.contype = 'c';
