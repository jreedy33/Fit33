-- ═══════════════════════════════════════════════════════════════════════════
-- 20260802_exercise_performance_id_match.sql  (Migration #164)
--
-- Adds `exercise_id UUID` to `exercise_performance_history` and
-- `exercise_set_history` so the active-workout "Previous Max" tile row
-- (`RecentSessionsTilesRow`, fed by
-- `ExerciseHistoryService.fetchRecentSessions(...)`) can filter by EXACT
-- exercise identity instead of by `exercise_name` alone.
--
-- WHY
-- ---
-- Until now the tile row queried `exercise_performance_history` by
-- `(user_id, exercise_name)`. When the user's catalog contained two
-- distinct `Exercise` rows that happened to share a `.name` (a custom
-- exercise + a catalog exercise, two equipment variants merged under one
-- canonical name during a CMS catalog sync, a renamed exercise that
-- collided with a sibling, etc.), the tile row pulled history from a
-- DIFFERENT exercise and rendered it as "Previous Max: 185 lb" on a card
-- the user had genuinely never trained. User-visible bug filed
-- 2026-04-29: "some exercises are showing max performance on things i
-- haven't done — only show on exercises I've actually completed the set
-- for the exact exercise id".
--
-- WHAT
-- ----
--   1. ADD `exercise_id UUID NULL REFERENCES exercises(id) ON DELETE SET NULL`
--      to `exercise_performance_history` and `exercise_set_history`. Nullable
--      so the column can be added without a backfill blocking the migration;
--      legacy rows stay accessible until the backfill resolves them. FK with
--      `ON DELETE SET NULL` so a future catalog deletion doesn't cascade-wipe
--      the user's history (the row is still useful as a name-keyed record).
--
--   2. INDEX `(user_id, exercise_id, workout_date DESC)` on
--      `exercise_performance_history` — the tile-row read pattern.
--      `exercise_set_history` already indexes `performance_id`; we add
--      `(user_id, exercise_id)` so future per-set lookups by id are fast
--      without rescanning name-keyed paths.
--
--   3. BEST-EFFORT BACKFILL using `exercises` table. For each
--      `(user_id, exercise_name)` pair, resolve `exercises.id` ONLY when
--      the name maps unambiguously to a single catalog row. Ambiguous
--      names (the exact bug class above) intentionally stay NULL — the
--      tile row will hide for them, which is the desired UX.
--
--   4. NO CHANGE to existing RLS — both tables already filter by
--      `auth.uid() = user_id`, and the new column is co-located with that
--      filter. No new policies needed.
--
-- iOS COORDINATION (paired commits, NOT migrations)
-- -------------------------------------------------
--   * `ExerciseHistoryService.saveExercisePerformance(...)` accepts a new
--     `exerciseId: UUID?` param and writes it into both tables. Always
--     pass `exercise.id` from `Fit33/ActiveWorkoutView+Persistence.swift`.
--   * `ExerciseHistoryService.fetchRecentSessions(forExerciseId:limit:)` is
--     the new read entrypoint — strict `eq("exercise_id", value: …)` match.
--     Legacy rows where `exercise_id IS NULL` are NOT returned (per spec —
--     the user explicitly asked for id-only matching).
--   * `Fit33/ExerciseCard.swift::loadRecentSessionsIfNeeded()` passes
--     `exercise.id` to the new entrypoint. If `exercise.id` is nil
--     (shouldn't happen — Core Data UUID is always set) the row simply
--     hides instead of falling back to name lookup.
--
-- IDEMPOTENT: Yes. `ADD COLUMN IF NOT EXISTS`, `CREATE INDEX IF NOT EXISTS`,
-- and the backfill UPDATE is filtered to `exercise_id IS NULL` so re-runs
-- only touch rows still awaiting resolution.
-- REVERSIBLE: Drop the columns + indexes. Existing iOS callers fall back
-- to the name-keyed read path when the column is absent (we keep
-- backward-compat in the Swift code).
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

-- ───────────────────────────────────────────────────────────────────────────
-- 1. Schema additions
--
-- DEFENSIVE TYPE NORMALIZATION: an older script
-- (`docs/DATABASE_MIGRATIONS.sql`) declared `exercise_performance_history`
-- with `exercise_id TEXT` ("Core Data exercise ID"). That column was never
-- populated by the canonical writer (`ExerciseHistoryService.saveExercise
-- Performance` historically used `exercise_name` instead) but the column
-- can exist on prod schemas. A bare `ADD COLUMN IF NOT EXISTS … UUID`
-- against that schema is a no-op and leaves the column as TEXT, which
-- breaks the backfill UPDATE below with a `column "exercise_id" is of
-- type uuid but expression is of type text` error. The ALTER COLUMN …
-- USING block handles that case explicitly: it only fires when the column
-- is currently TEXT, and casts the data conditionally — valid UUID-format
-- strings convert; everything else (including bad legacy strings) becomes
-- NULL so the conversion never aborts on bad data. After this block the
-- column type is UUID on every shape of prod schema.
-- ───────────────────────────────────────────────────────────────────────────

DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name   = 'exercise_performance_history'
          AND column_name  = 'exercise_id'
          AND data_type    = 'text'
    ) THEN
        ALTER TABLE public.exercise_performance_history
            ALTER COLUMN exercise_id TYPE UUID USING (
                CASE
                    WHEN exercise_id IS NULL THEN NULL
                    WHEN exercise_id ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
                        THEN exercise_id::uuid
                    ELSE NULL
                END
            );
        RAISE NOTICE 'Converted exercise_performance_history.exercise_id from TEXT → UUID';
    END IF;

    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name   = 'exercise_set_history'
          AND column_name  = 'exercise_id'
          AND data_type    = 'text'
    ) THEN
        ALTER TABLE public.exercise_set_history
            ALTER COLUMN exercise_id TYPE UUID USING (
                CASE
                    WHEN exercise_id IS NULL THEN NULL
                    WHEN exercise_id ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
                        THEN exercise_id::uuid
                    ELSE NULL
                END
            );
        RAISE NOTICE 'Converted exercise_set_history.exercise_id from TEXT → UUID';
    END IF;
END;
$$;

ALTER TABLE public.exercise_performance_history
    ADD COLUMN IF NOT EXISTS exercise_id UUID;

ALTER TABLE public.exercise_set_history
    ADD COLUMN IF NOT EXISTS exercise_id UUID;

-- Add FK constraint separately so it doesn't conflict when the column was
-- already present (without an FK) from the legacy script. `IF NOT EXISTS`
-- on `ADD CONSTRAINT` was added in PG 16; for portability we guard via a
-- catalog lookup.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conrelid = 'public.exercise_performance_history'::regclass
          AND conname  = 'exercise_performance_history_exercise_id_fkey'
    ) THEN
        ALTER TABLE public.exercise_performance_history
            ADD CONSTRAINT exercise_performance_history_exercise_id_fkey
            FOREIGN KEY (exercise_id) REFERENCES public.exercises(id) ON DELETE SET NULL;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conrelid = 'public.exercise_set_history'::regclass
          AND conname  = 'exercise_set_history_exercise_id_fkey'
    ) THEN
        ALTER TABLE public.exercise_set_history
            ADD CONSTRAINT exercise_set_history_exercise_id_fkey
            FOREIGN KEY (exercise_id) REFERENCES public.exercises(id) ON DELETE SET NULL;
    END IF;
END;
$$;

-- ───────────────────────────────────────────────────────────────────────────
-- 2. Indexes — tile row reads `(user_id, exercise_id)` ordered by date desc
-- ───────────────────────────────────────────────────────────────────────────

CREATE INDEX IF NOT EXISTS idx_eph_user_exercise_date
    ON public.exercise_performance_history (user_id, exercise_id, workout_date DESC)
    WHERE exercise_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_esh_user_exercise
    ON public.exercise_set_history (user_id, exercise_id)
    WHERE exercise_id IS NOT NULL;

-- ───────────────────────────────────────────────────────────────────────────
-- 3. Best-effort backfill from canonical catalog
--
-- For each (user_id, exercise_name) tuple in `exercise_performance_history`
-- where exercise_id IS NULL, look up the canonical `exercises.id`. We only
-- backfill when the name resolves UNAMBIGUOUSLY (exactly one matching
-- catalog row). Ambiguous names — the exact bug class this migration
-- exists to fix — intentionally remain NULL: the tile row will then hide
-- for those exercises, prompting the user to log a fresh session against
-- the specific exercise.id they're now looking at.
-- ───────────────────────────────────────────────────────────────────────────

-- Postgres has no `min(uuid)` aggregate, so we use `array_agg` + `[1]` —
-- safe because `HAVING COUNT(*) = 1` guarantees a single-element array.
WITH unambiguous AS (
    SELECT
        e.name,
        (ARRAY_AGG(e.id))[1] AS exercise_id
    FROM public.exercises e
    GROUP BY e.name
    HAVING COUNT(*) = 1
)
UPDATE public.exercise_performance_history eph
SET exercise_id = u.exercise_id
FROM unambiguous u
WHERE eph.exercise_id IS NULL
  AND eph.exercise_name = u.name;

-- Mirror the backfill into exercise_set_history via performance_id join,
-- so per-set rows track the same canonical exercise_id as their parent.
UPDATE public.exercise_set_history esh
SET exercise_id = eph.exercise_id
FROM public.exercise_performance_history eph
WHERE esh.performance_id = eph.id
  AND esh.exercise_id IS NULL
  AND eph.exercise_id IS NOT NULL;

-- ───────────────────────────────────────────────────────────────────────────
-- 4. Trailing fail-loud audit
-- ───────────────────────────────────────────────────────────────────────────

DO $$
DECLARE
    v_eph_total       BIGINT;
    v_eph_resolved    BIGINT;
    v_eph_pending     BIGINT;
    v_esh_total       BIGINT;
    v_esh_resolved    BIGINT;
    v_eph_col_exists  BOOLEAN;
    v_esh_col_exists  BOOLEAN;
BEGIN
    SELECT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'exercise_performance_history'
          AND column_name = 'exercise_id'
    ) INTO v_eph_col_exists;

    SELECT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'exercise_set_history'
          AND column_name = 'exercise_id'
    ) INTO v_esh_col_exists;

    IF NOT v_eph_col_exists THEN
        RAISE EXCEPTION 'Migration failed — exercise_performance_history.exercise_id is missing';
    END IF;

    IF NOT v_esh_col_exists THEN
        RAISE EXCEPTION 'Migration failed — exercise_set_history.exercise_id is missing';
    END IF;

    SELECT
        COUNT(*),
        COUNT(*) FILTER (WHERE exercise_id IS NOT NULL),
        COUNT(*) FILTER (WHERE exercise_id IS NULL)
    INTO v_eph_total, v_eph_resolved, v_eph_pending
    FROM public.exercise_performance_history;

    SELECT
        COUNT(*),
        COUNT(*) FILTER (WHERE exercise_id IS NOT NULL)
    INTO v_esh_total, v_esh_resolved
    FROM public.exercise_set_history;

    RAISE NOTICE '✅ exercise_id columns + indexes added';
    RAISE NOTICE '   exercise_performance_history: % total / % resolved / % ambiguous (NULL)',
        v_eph_total, v_eph_resolved, v_eph_pending;
    RAISE NOTICE '   exercise_set_history:         % total / % resolved',
        v_esh_total, v_esh_resolved;
    RAISE NOTICE '   Ambiguous (NULL) rows will be filled in as users complete fresh sessions.';
END;
$$;

COMMIT;

-- ROLLBACK
-- DROP INDEX IF EXISTS idx_eph_user_exercise_date;
-- DROP INDEX IF EXISTS idx_esh_user_exercise;
-- ALTER TABLE public.exercise_performance_history DROP COLUMN IF EXISTS exercise_id;
-- ALTER TABLE public.exercise_set_history DROP COLUMN IF EXISTS exercise_id;
