-- ============================================================================
-- 20260424 — EXERCISES "MANUALLY UPDATED" FLAG
-- ============================================================================
-- Adds two columns to `public.exercises` so the admin CMS can track which
-- rows have been hand-edited (and when). The CMS detail page auto-sets
-- `manually_updated = TRUE` + `manually_updated_at = now()` whenever an
-- admin saves a change, and surfaces both values in a top-right checkbox.
--
-- Idempotent — safe to re-run.
-- ============================================================================

BEGIN;

-- ───────────────────────────────────────────────────────────────────────────
-- 1. Columns
-- ───────────────────────────────────────────────────────────────────────────

ALTER TABLE public.exercises
    ADD COLUMN IF NOT EXISTS manually_updated    BOOLEAN     NOT NULL DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS manually_updated_at TIMESTAMPTZ;

COMMENT ON COLUMN public.exercises.manually_updated IS
    'TRUE when the row has been hand-edited in the admin CMS. Flipped automatically by the CMS update_exercise handler on every save.';
COMMENT ON COLUMN public.exercises.manually_updated_at IS
    'Timestamp of the most recent manual edit from the admin CMS. NULL for rows that have only been touched by bulk imports / seeds.';

-- ───────────────────────────────────────────────────────────────────────────
-- 2. Supporting index
-- ───────────────────────────────────────────────────────────────────────────
-- Partial index: only the (small) set of manually-edited rows is indexed, so
-- the CMS can filter "show me what I've curated" without a full table scan.

CREATE INDEX IF NOT EXISTS idx_exercises_manually_updated_at
    ON public.exercises (manually_updated_at DESC)
    WHERE manually_updated = TRUE;

-- ───────────────────────────────────────────────────────────────────────────
-- 3. Verification
-- ───────────────────────────────────────────────────────────────────────────

DO $$
DECLARE
    has_flag  BOOLEAN;
    has_ts    BOOLEAN;
    has_idx   BOOLEAN;
BEGIN
    SELECT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'exercises' AND column_name = 'manually_updated'
    ) INTO has_flag;

    SELECT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'exercises' AND column_name = 'manually_updated_at'
    ) INTO has_ts;

    SELECT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname = 'public' AND indexname = 'idx_exercises_manually_updated_at'
    ) INTO has_idx;

    RAISE NOTICE '';
    RAISE NOTICE '═══════════════════════════════════════════════════════';
    RAISE NOTICE 'Exercises manually_updated columns:';
    RAISE NOTICE '  exercises.manually_updated        : %', has_flag;
    RAISE NOTICE '  exercises.manually_updated_at     : %', has_ts;
    RAISE NOTICE '  idx_exercises_manually_updated_at : %', has_idx;
    RAISE NOTICE '═══════════════════════════════════════════════════════';
END $$;

COMMIT;
