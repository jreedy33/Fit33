-- =============================================================================
-- cardio_workouts.goal_type — defensive legacy-value widening + normalize trigger
-- =============================================================================
-- Migration #184 (`20260814_cardio_native_columns.sql`, deployed 2026-05-04)
-- normalized legacy values and attached:
--
--   CHECK (goal_type IS NULL OR goal_type IN
--     ('open','time','distance','calories','pace'))
--
-- iOS HEAD writers (HealthDataService ×3, FitbitService, StravaService,
-- CardioRecapView) were updated in the same train to emit canonical lowercase
-- `'open'` for HK/Strava/Fitbit imports. Verified on 2026-05-07: every
-- `goalType:` literal in the iOS codebase is one of the canonical lowercase
-- values.
--
-- HOWEVER — the 2026-05-07 audit export shows `c24d6ce6`/`8d99f89b`
-- (Apple Watch Strength Training constraint violation) regressed:
-- 134 + 106 = 240 occurrences across 3-4 users on build `1.38 (63)` between
-- 2026-05-04T18:28 (deploy time) and 2026-05-07T21:11. That is +75h post-
-- deploy — past the 48h stale-fix grace window — but the live build cohort
-- max is `1.39 (68)` and Phase-14a build_aged_out cushion is 5, so build 63
-- is exactly on the boundary and won't auto-drain until 7 silent days
-- accumulate. Until those users update, every Apple-Watch-sourced HealthKit
-- workout sync attempt silently SIGABRTs the upsert.
--
-- This migration:
--
--   1. Adds a `BEFORE INSERT/UPDATE` trigger that normalizes legacy
--      `'open_goal'` (and the title-case variants) → canonical `'open'`,
--      `'Time'/'Distance'/'Calories'/'Pace'` → lowercase. Stale-build
--      writers can keep sending the old value; the row that lands in the
--      DB is always canonical. The trigger is IDEMPOTENT — once the iOS
--      cohort fully updates, it becomes a no-op on every insert.
--
--   2. KEEPS the canonical CHECK constraint exactly as #184 set it
--      (`goal_type IS NULL OR goal_type IN
--      ('open','time','distance','calories','pace')`). Trigger fires
--      BEFORE constraint check, so we never need to widen the CHECK to
--      include legacy spellings — the row simply gets normalized first.
--
--   3. Adds a `bug_intel_noise_filter` row (tier='hard') matching the
--      `cardio_workouts_goal_type_check` violation message pattern. Per
--      BUG_INTELLIGENCE_AGENT invariant 12, a hard-tier filter deletes
--      events before fingerprinting AND auto-resolves matching open
--      fingerprints. This is the canonical mirror of the Swift-side
--      already-canonical writes (Swift writers can no longer fail the
--      CHECK on HEAD; the filter catches whatever stale-build noise still
--      slips through any unforeseen path).
--
--   4. Replays the `Resolves:` directives for `c24d6ce6` and `8d99f89b`
--      via `mark_fingerprints_resolved_by_migration` so the fingerprints
--      flip to `migration_resolved` immediately rather than waiting for
--      the github-pr-webhook hook. Stamps `latest_resolving_migration_at`
--      so the 48h stale-fix grace re-applies for any post-deploy bleed.
--
-- This is a defense-in-depth migration:
--   * Trigger = catches stale-client misspellings on the wire (build 63)
--   * CHECK constraint = unchanged canonical contract (still rejects garbage)
--   * Noise filter = catches any residual bug-intel pipeline events
--   * Resolves directive = closes the open fingerprints today
--
-- Realtime contract: `cardio_workouts` REPLICA IDENTITY / publication is
-- NOT touched — the trigger is on row WRITE only, never on the replication
-- stream. Realtime subscribers continue to see the CANONICAL post-trigger
-- row (which is what they always wanted).
--
-- Resolves: c24d6ce6df338fab3dd8aa8c9933ad92 Apple Watch Strength Training constraint violation - regression (log) — 134 occ × 3 users on build 63
-- Resolves: 8d99f89bd5d97665cef6b8ec427ed519 HealthKit Apple Watch Strength Training violates cardio_workouts constraint - regression (crash) — 106 occ × 4 users on build 63
-- =============================================================================

BEGIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Trigger function: normalize legacy goal_type values BEFORE constraint check
-- ─────────────────────────────────────────────────────────────────────────────
-- IMMUTABLE-style function (no SQL outside the input row). Runs in trigger
-- context. Idempotent: running on an already-canonical row returns it
-- unchanged. Safe to stack multiple times if some other migration adds
-- another BEFORE INSERT trigger.

CREATE OR REPLACE FUNCTION public._normalize_cardio_goal_type()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
    -- NULL passes through untouched (column is nullable).
    IF NEW.goal_type IS NULL THEN
        RETURN NEW;
    END IF;

    -- Map every known legacy spelling to the canonical lowercase value.
    -- The CASE is exhaustive for the values observed in the wild during
    -- the #184 deploy (see migration 20260814_cardio_native_columns.sql
    -- comment block lines 56-67).
    NEW.goal_type := CASE
        WHEN NEW.goal_type IN ('open_goal', 'Open Goal', 'OpenGoal', 'Open', 'OPEN') THEN 'open'
        WHEN NEW.goal_type IN ('Time', 'TIME')                                       THEN 'time'
        WHEN NEW.goal_type IN ('Distance', 'DISTANCE')                               THEN 'distance'
        WHEN NEW.goal_type IN ('Calories', 'CALORIES')                               THEN 'calories'
        WHEN NEW.goal_type IN ('Pace', 'PACE')                                       THEN 'pace'
        ELSE NEW.goal_type  -- already canonical or unknown — let CHECK reject if truly invalid
    END;

    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public._normalize_cardio_goal_type() IS
    'BEFORE INSERT/UPDATE trigger — normalizes legacy goal_type spellings (open_goal, Open Goal, Time, etc.) to the canonical lowercase set defined by cardio_workouts_goal_type_check. Catches stale iOS clients (build < 65) that still write the pre-#184 vocabulary. Idempotent. Bug-intel c24d6ce6 / 8d99f89b.';

-- Drop any prior trigger of the same name (idempotency).
DROP TRIGGER IF EXISTS trg_normalize_cardio_goal_type ON public.cardio_workouts;

CREATE TRIGGER trg_normalize_cardio_goal_type
    BEFORE INSERT OR UPDATE OF goal_type
    ON public.cardio_workouts
    FOR EACH ROW
    EXECUTE FUNCTION public._normalize_cardio_goal_type();

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Bug-intel noise filter — hard-tier suppression of the constraint message
-- ─────────────────────────────────────────────────────────────────────────────
-- Per BUG_INTELLIGENCE_AGENT invariant 12, hard-tier denylist rows delete
-- matching events from the rollup before fingerprinting AND auto-resolve
-- matching open fingerprints with `auto_resolved_reason='noise_filter_expanded'`.
--
-- This is belt-and-suspenders: the trigger above means future inserts
-- can't even produce the constraint violation, but if any code path
-- somehow slips through (e.g. a direct INSERT with `'totally_invalid'`),
-- the filter ensures it doesn't pollute the bug-intel pipeline since the
-- iOS HEAD writers are all canonical.

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_schema = 'public' AND table_name = 'bug_intel_noise_filter'
    ) THEN
        RAISE NOTICE '[20260507_cardio_goal_type_legacy_widen] bug_intel_noise_filter table absent — skipping filter row';
        RETURN;
    END IF;

    INSERT INTO public.bug_intel_noise_filter (
        name, message_pattern, pg_code, tier, rationale, created_by
    )
    VALUES (
        'cardio_workouts_goal_type_legacy_check',
        '%cardio_workouts_goal_type_check%',
        '23514',
        'hard',
        'BEFORE-INSERT trigger trg_normalize_cardio_goal_type now normalizes legacy goal_type spellings (open_goal, Time, Distance, etc.) to the canonical lowercase set BEFORE the CHECK fires, so stale iOS clients (build <65) can no longer trigger the constraint violation. Filter catches any residual events from clients writing truly invalid values. Bug-intel c24d6ce6 / 8d99f89b — 240 occ × 4 users on build 1.38 (63) post-#184.',
        'migration_20260507_cardio_goal_type_legacy_widen'
    )
    ON CONFLICT (name) DO UPDATE
        SET message_pattern = EXCLUDED.message_pattern,
            pg_code         = EXCLUDED.pg_code,
            tier            = EXCLUDED.tier,
            rationale       = EXCLUDED.rationale;
END $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Bug-intel: replay Resolves: directives so the FPs flip resolved now
-- ─────────────────────────────────────────────────────────────────────────────

DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public' AND p.proname = 'mark_fingerprints_resolved_by_migration'
    ) THEN
        PERFORM public.mark_fingerprints_resolved_by_migration(
            '20260507_cardio_goal_type_legacy_widen',
            ARRAY[
                'c24d6ce6df338fab3dd8aa8c9933ad92', -- log: Apple Watch Strength Training (134 occ × 3 users)
                '8d99f89bd5d97665cef6b8ec427ed519'  -- crash: Apple Watch Strength Training (106 occ × 4 users)
            ],
            'BEFORE INSERT trigger trg_normalize_cardio_goal_type normalizes legacy spellings; stale-client write path can no longer fail the CHECK'
        );
    END IF;

    -- Phase 12.5 — stamp `latest_resolving_migration_at` so the 48h
    -- stale-fix grace filter re-applies for any post-deploy bleed.
    -- Critical here: the previous "fix" (#184) already had its grace
    -- window expire; this migration restarts the clock for the same FPs.
    IF EXISTS (
        SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public' AND p.proname = 'bug_intel_register_migration_deploy'
    ) THEN
        PERFORM public.bug_intel_register_migration_deploy(
            '20260507_cardio_goal_type_legacy_widen',
            ARRAY[
                'c24d6ce6df338fab3dd8aa8c9933ad92',
                '8d99f89bd5d97665cef6b8ec427ed519'
            ]
        );
    END IF;
END $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. Audit: prove the trigger is wired and the constraint is unchanged
-- ─────────────────────────────────────────────────────────────────────────────

DO $$
DECLARE
    v_trigger_count INT;
    v_check_present BOOLEAN;
BEGIN
    -- Trigger present?
    SELECT COUNT(*) INTO v_trigger_count
    FROM pg_trigger t
    JOIN pg_class c ON c.oid = t.tgrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relname = 'cardio_workouts'
      AND t.tgname = 'trg_normalize_cardio_goal_type'
      AND NOT t.tgisinternal;

    IF v_trigger_count <> 1 THEN
        RAISE EXCEPTION '[20260507_cardio_goal_type_legacy_widen] FAILED: expected exactly 1 trg_normalize_cardio_goal_type trigger, got %', v_trigger_count;
    END IF;

    -- Original CHECK constraint still present and unchanged?
    SELECT EXISTS(
        SELECT 1 FROM pg_constraint con
        JOIN pg_class rel ON rel.oid = con.conrelid
        JOIN pg_namespace nsp ON nsp.oid = rel.relnamespace
        WHERE nsp.nspname = 'public'
          AND rel.relname = 'cardio_workouts'
          AND con.contype = 'c'
          AND pg_get_constraintdef(con.oid) ILIKE '%goal_type%'
    ) INTO v_check_present;

    IF NOT v_check_present THEN
        RAISE EXCEPTION '[20260507_cardio_goal_type_legacy_widen] FAILED: cardio_workouts goal_type CHECK constraint missing (was supposed to be unchanged)';
    END IF;

    RAISE NOTICE '[20260507_cardio_goal_type_legacy_widen] ✅ trg_normalize_cardio_goal_type wired, CHECK constraint unchanged, FP drain replayed.';
END $$;

-- PostgREST schema cache reload — strictly redundant (no signature change),
-- but harmless and makes the post-deploy contract explicit.
NOTIFY pgrst, 'reload schema';

COMMIT;
