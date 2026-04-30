-- ═══════════════════════════════════════════════════════════════════════════
-- 20260725_workout_intelligence.sql
--
-- Workout Intelligence — every quality workout (score >= 70) gets a Claude
-- analysis report. The report extracts pairings, pacing, swap events,
-- progression evidence, red flags, and "100%-confident" exercise corrections
-- that feed back into auto-gen recommender + the canonical exercise catalog.
--
-- WHY
-- ---
-- Migrations #154 + #155 set up the quality-gated training corpus and the
-- atomic delete RPC. This one closes the loop: turn each quality workout into
-- structured intelligence the recommender + the fitness expert agent can
-- learn from. Everything Claude is uncertain about → left as-is. Only fields
-- where Claude is 100% confident (missing canonical muscle groups, grossly
-- miscategorized workout_type / equipment / is_compound / duration_based)
-- get auto-applied to the `exercises` table. Subjective fields are NEVER
-- touched.
--
-- WHAT THIS MIGRATION DOES
-- ------------------------
-- 1. ALTER `workout_history` — adds `workout_type TEXT` (origin: auto_gen /
--    custom / program / friend_workout / cardio) so reports can condition
--    on session type.
-- 2. ALTER `exercise_set_history` — adds `completed_at TIMESTAMPTZ`
--    (nullable) so set pacing can be derived from real wall-clock deltas
--    instead of "duration / completed_sets" proxy. Backfilled by future
--    iOS code; existing rows stay NULL and the report falls back to proxy.
-- 3. CREATE `workout_swap_events` table — proper audit of every exercise
--    swap with `workout_id`, `picked_rank` (which menu position the user
--    chose; 0 = top suggestion), and the original/replacement exercise IDs.
--    Replaces the workout-id-less `exercise_swap_analytics` aggregate
--    (kept for backwards-compat; not referenced by intelligence pipeline).
-- 4. CREATE `ai_workout_reports` table — one row per quality workout.
--    `report_jsonb` carries the full structured analysis (sections A-H from
--    FE spec); `summary_md` is the human-readable rolling-log entry.
-- 5. CREATE `exercise_corrections` table — audit log of every correction
--    auto-applied by the pipeline. Append-only.
-- 6. CREATE `pairing_signals` table — auto-discovered synergistic +
--    negative pairings derived from quality-workout co-occurrence + the
--    explicit `pairingFindings[]` Claude emits. Feeds
--    `SmartExercisePairingEngine`.
-- 7. CREATE `user_training_profile` table — rolling per-user style
--    profile (hypertrophy-focused, prefers DB > BB, etc.) refreshed every
--    4 quality workouts. One row per user.
-- 8. CREATE `apply_exercise_correction(...)` SECURITY DEFINER RPC. ONLY
--    accepts the conservative whitelist of fields. Refuses any correction
--    with `confidence < 1.0`. Service-role / cron only.
-- 9. CREATE `enqueue_quality_workout_for_analysis(...)` SECURITY DEFINER
--    RPC. Called by iOS post-quality-score so the edge function knows
--    which workouts to pick up.
-- 10. Trailing fail-loud `DO $$` audit block.
--
-- WHITELIST (the ONLY fields auto-correction can touch)
-- -----------------------------------------------------
--   • `primary_muscles` — append missing canonical entries only. Never
--     remove or replace; never reorder.
--   • `secondary_muscles` — same: append-only.
--   • `workout_type` — fix grossly miscategorized rows ("Barbell Press"
--     tagged as "Stretch"). Allowed values: 'Strength', 'Stretch',
--     'Plyometrics', 'Cardio'.
--   • `equipment_category` — fix only when the exercise NAME unambiguously
--     specifies equipment (e.g. "Cable Front Raise" with NULL category).
--   • `is_compound` — fix only obvious cases (deadlift / squat / bench /
--     row / OHP / pull-up tagged FALSE).
--   • `duration_based` — fix only obvious cases (a 30s plank tagged FALSE,
--     a barbell press tagged TRUE).
--
-- INVARIANTS PRESERVED
-- --------------------
--   • All four new tables have `auth.uid()`-pinned read policies for the
--     row-owner; service-role / cron writes only (mirrors `ai_insights`).
--   • `apply_exercise_correction` REJECTS confidence < 1.0 with
--     `RAISE EXCEPTION 'Correction confidence below threshold'`. The
--     edge function MUST send confidence = 1.0 (never 0.95 / 0.99).
--   • `apply_exercise_correction` REJECTS field names not on the whitelist
--     above. Any future expansion of the whitelist requires a migration.
--   • Idempotent re-run safe — `IF NOT EXISTS` everywhere, drop+recreate
--     functions per supabase-rules invariant 12.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

-- ───────────────────────────────────────────────────────────────────────────
-- 1. workout_history.workout_type — origin classification
-- ───────────────────────────────────────────────────────────────────────────

ALTER TABLE workout_history
    ADD COLUMN IF NOT EXISTS workout_type TEXT;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
         WHERE conname = 'workout_history_workout_type_check'
           AND conrelid = 'workout_history'::regclass
    ) THEN
        ALTER TABLE workout_history
            ADD CONSTRAINT workout_history_workout_type_check
            CHECK (workout_type IS NULL OR workout_type IN (
                'auto_gen', 'custom', 'program', 'friend_workout', 'cardio'
            ));
    END IF;
END $$;

COMMENT ON COLUMN workout_history.workout_type IS
    'Origin of the workout. NULL for legacy rows. iOS sets at insert time. Conditioned on by ai_workout_reports analysis (auto_gen workouts get the programmed-vs-executed diff; custom workouts skip it).';

-- ───────────────────────────────────────────────────────────────────────────
-- 2. exercise_set_history.completed_at — wall-clock per-set timestamp
-- ───────────────────────────────────────────────────────────────────────────

ALTER TABLE exercise_set_history
    ADD COLUMN IF NOT EXISTS completed_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_exercise_set_history_completed_at
    ON exercise_set_history (performance_id, completed_at)
 WHERE completed_at IS NOT NULL;

COMMENT ON COLUMN exercise_set_history.completed_at IS
    'Wall-clock time the user marked the set complete. NULL for legacy rows; intelligence pipeline falls back to (workout.duration / completed_sets) proxy when null. iOS sets this in the same Task that inserts the row.';

-- ───────────────────────────────────────────────────────────────────────────
-- 3. workout_swap_events — proper audit (replaces aggregate-only swap data)
-- ───────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS workout_swap_events (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    workout_id      UUID NOT NULL REFERENCES workout_history(id) ON DELETE CASCADE,
    swap_index      INTEGER NOT NULL,                       -- 1, 2, 3+ (tier per FE invariant 25)
    original_exercise_id  UUID,
    original_exercise_name TEXT NOT NULL,
    replacement_exercise_id UUID,
    replacement_exercise_name TEXT NOT NULL,
    picked_rank     INTEGER,                                 -- 0 = top suggestion; NULL = unknown / typed
    swap_source     TEXT NOT NULL CHECK (swap_source IN ('quick_swap','smart_swap','search','random')),
    completed_replacement BOOLEAN,                           -- NULL until workout finishes
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_workout_swap_events_workout
    ON workout_swap_events (workout_id, created_at);
CREATE INDEX IF NOT EXISTS idx_workout_swap_events_user_created
    ON workout_swap_events (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_workout_swap_events_picked_rank
    ON workout_swap_events (picked_rank) WHERE picked_rank IS NOT NULL;

ALTER TABLE workout_swap_events ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "swap_events_owner_read" ON workout_swap_events;
CREATE POLICY "swap_events_owner_read" ON workout_swap_events
    FOR SELECT USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "swap_events_owner_insert" ON workout_swap_events;
CREATE POLICY "swap_events_owner_insert" ON workout_swap_events
    FOR INSERT WITH CHECK (auth.uid() = user_id);

-- Service role bypasses RLS for the analysis pipeline.
COMMENT ON TABLE workout_swap_events IS
    'One row per exercise swap during an active workout. picked_rank = 0 means user picked the top suggestion (good signal — our scoring is right). picked_rank > 0 = our scoring is wrong. swap_index per FE invariant 25 (tier 1-2 = equipment variant, 3+ = complementary).';

-- ───────────────────────────────────────────────────────────────────────────
-- 4. ai_workout_reports — per-quality-workout Claude analysis
-- ───────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS ai_workout_reports (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    workout_id      UUID NOT NULL REFERENCES workout_history(id) ON DELETE CASCADE,
    quality_score   INTEGER NOT NULL,
    quality_band    TEXT NOT NULL,
    -- Status pipeline: pending -> analyzing -> complete | failed.
    -- Edge function flips pending -> analyzing on pickup, then writes the
    -- final result. Failures stay 'failed' with `error_message` for retry.
    status          TEXT NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending','analyzing','complete','failed','skipped')),
    -- Full structured report (sections A–H from FE spec). schema_version
    -- inside report_jsonb lets us evolve the shape without a column change.
    report_jsonb    JSONB,
    -- Human-readable rolling-log entry shown in CMS.
    summary_md      TEXT,
    -- Provenance
    model_used      TEXT,
    prompt_hash     TEXT,
    error_message   TEXT,
    -- The pre-flight suspicious-pattern check writes here. When true, the
    -- workout is excluded from corpus + auto-gen feedback regardless of
    -- the original quality_score. See `redFlags[]` section H in the
    -- report_jsonb.
    is_suspicious   BOOLEAN NOT NULL DEFAULT FALSE,
    -- Recovery flag — workout scored 60-69, flagged as "lost session"
    -- (probably real, user just stopped logging midway). Surfaces in CMS
    -- with a Promote / Discard control. Defaults FALSE.
    is_lost_session BOOLEAN NOT NULL DEFAULT FALSE,
    enqueued_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    analyzed_at     TIMESTAMPTZ,
    -- Idempotency guard — one report per workout.
    UNIQUE (workout_id)
);

CREATE INDEX IF NOT EXISTS idx_ai_workout_reports_status
    ON ai_workout_reports (status, enqueued_at) WHERE status IN ('pending','analyzing');
CREATE INDEX IF NOT EXISTS idx_ai_workout_reports_user_analyzed
    ON ai_workout_reports (user_id, analyzed_at DESC);
CREATE INDEX IF NOT EXISTS idx_ai_workout_reports_analyzed_at
    ON ai_workout_reports (analyzed_at DESC) WHERE status = 'complete';

ALTER TABLE ai_workout_reports ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "ai_reports_owner_read" ON ai_workout_reports;
CREATE POLICY "ai_reports_owner_read" ON ai_workout_reports
    FOR SELECT USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "ai_reports_owner_enqueue" ON ai_workout_reports;
CREATE POLICY "ai_reports_owner_enqueue" ON ai_workout_reports
    FOR INSERT WITH CHECK (
        auth.uid() = user_id
        AND status = 'pending'
        AND report_jsonb IS NULL
        AND analyzed_at IS NULL
    );

-- Updates only via service role (edge function). No UPDATE policy = denied.
COMMENT ON TABLE ai_workout_reports IS
    'Claude-generated analysis of every quality workout. Owner can read; only the analysis edge function (service role) can update report_jsonb / status. Idempotent per workout via UNIQUE(workout_id).';

-- ───────────────────────────────────────────────────────────────────────────
-- 5. exercise_corrections — append-only audit of auto-applied fixes
-- ───────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS exercise_corrections (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    exercise_id     UUID NOT NULL,
    exercise_name   TEXT NOT NULL,
    -- Field that was corrected. ENFORCED in apply_exercise_correction.
    field_name      TEXT NOT NULL CHECK (field_name IN (
        'primary_muscles', 'secondary_muscles',
        'workout_type', 'equipment_category',
        'is_compound', 'duration_based'
    )),
    previous_value  JSONB,
    new_value       JSONB NOT NULL,
    -- Why we were certain. Required.
    evidence        TEXT NOT NULL,
    confidence      NUMERIC(3,2) NOT NULL CHECK (confidence = 1.00),
    -- Provenance: which workout report triggered this correction.
    source_report_id UUID REFERENCES ai_workout_reports(id) ON DELETE SET NULL,
    applied_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_exercise_corrections_exercise
    ON exercise_corrections (exercise_id, applied_at DESC);
CREATE INDEX IF NOT EXISTS idx_exercise_corrections_recent
    ON exercise_corrections (applied_at DESC);

ALTER TABLE exercise_corrections ENABLE ROW LEVEL SECURITY;

-- Authenticated read (CMS surface). No INSERT/UPDATE/DELETE policies =
-- service-role only.
DROP POLICY IF EXISTS "exercise_corrections_authed_read" ON exercise_corrections;
CREATE POLICY "exercise_corrections_authed_read" ON exercise_corrections
    FOR SELECT USING (auth.role() = 'authenticated');

COMMENT ON TABLE exercise_corrections IS
    'Append-only audit of auto-applied corrections to the exercises catalog. Confidence MUST be 1.00 (enforced via CHECK constraint AND apply_exercise_correction RPC). Anything Claude is unsure about NEVER lands here.';

-- ───────────────────────────────────────────────────────────────────────────
-- 6. pairing_signals — auto-discovered exercise pairing intelligence
-- ───────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS pairing_signals (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    exercise_a_id   UUID NOT NULL,
    exercise_a_name TEXT NOT NULL,
    exercise_b_id   UUID NOT NULL,
    exercise_b_name TEXT NOT NULL,
    -- Normalize order so (A,B) and (B,A) collapse into a single row.
    -- Guarded by the unique index below + a trigger on insert.
    signal_type     TEXT NOT NULL CHECK (signal_type IN ('synergistic','negative')),
    -- How many quality workouts contained both. Goes up monotonically.
    co_occurrence_count INTEGER NOT NULL DEFAULT 1,
    -- Avg pairing-quality contribution from reports that evaluated this pair.
    avg_pairing_quality NUMERIC(4,3),
    -- Reasons aggregated from `pairingFindings[]` (e.g.
    -- ["bench_triceps_synergy", "row_biceps_synergy"]).
    reason_codes    TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
    last_seen_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS uniq_pairing_signals_pair
    ON pairing_signals (exercise_a_id, exercise_b_id, signal_type);
CREATE INDEX IF NOT EXISTS idx_pairing_signals_high_synergy
    ON pairing_signals (co_occurrence_count DESC, avg_pairing_quality DESC)
 WHERE signal_type = 'synergistic';

ALTER TABLE pairing_signals ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "pairing_signals_authed_read" ON pairing_signals;
CREATE POLICY "pairing_signals_authed_read" ON pairing_signals
    FOR SELECT USING (auth.role() = 'authenticated');

COMMENT ON TABLE pairing_signals IS
    'Aggregated pairing intelligence harvested from ai_workout_reports.pairingFindings. Auto-promoted by the analysis pipeline. SmartExercisePairingEngine reads from this table to bias future auto-gen toward pairings that real users complete well together.';

-- ───────────────────────────────────────────────────────────────────────────
-- 7. user_training_profile — rolling per-user style profile
-- ───────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS user_training_profile (
    user_id         UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    -- Inferred style: e.g. "hypertrophy", "strength", "endurance", "mixed".
    inferred_intent TEXT,
    -- Rolling stats.
    median_rest_sec INTEGER,
    preferred_equipment TEXT[],
    weak_movement_patterns TEXT[],         -- e.g. ['hinge','vertical_push']
    strong_movement_patterns TEXT[],
    avg_session_duration_min INTEGER,
    avg_working_sets_per_session INTEGER,
    -- The full profile JSONB (extensible — add fields without a migration).
    profile_jsonb   JSONB NOT NULL DEFAULT '{}'::jsonb,
    -- Refresh control. Updated every 4 quality workouts OR nightly cron.
    quality_workouts_at_refresh INTEGER NOT NULL DEFAULT 0,
    refreshed_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE user_training_profile ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "training_profile_owner_read" ON user_training_profile;
CREATE POLICY "training_profile_owner_read" ON user_training_profile
    FOR SELECT USING (auth.uid() = user_id);

COMMENT ON TABLE user_training_profile IS
    'Per-user rolling training-style profile. Refreshed by the analysis pipeline every 4 quality workouts. Drives personalization in WorkoutSuggestionEngine + SmartExerciseSelectionEngine.';

-- ───────────────────────────────────────────────────────────────────────────
-- 8. apply_exercise_correction — strict whitelist + 100%-confidence gate
-- ───────────────────────────────────────────────────────────────────────────

DROP FUNCTION IF EXISTS apply_exercise_correction(UUID, TEXT, TEXT, JSONB, NUMERIC, TEXT, UUID);
DROP FUNCTION IF EXISTS apply_exercise_correction(UUID, TEXT, JSONB, JSONB, NUMERIC, TEXT, UUID);

CREATE OR REPLACE FUNCTION apply_exercise_correction(
    p_exercise_id      UUID,
    p_field_name       TEXT,
    p_new_value        JSONB,
    p_confidence       NUMERIC,
    p_evidence         TEXT,
    p_source_report_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_exercise_name   TEXT;
    v_previous_value  JSONB;
    v_corrected       BOOLEAN := FALSE;
    v_new_text        TEXT;
    v_new_bool        BOOLEAN;
    v_new_text_array  TEXT[];
BEGIN
    -- Service-role / cron only. auth.uid() IS NULL → service role.
    IF auth.uid() IS NOT NULL THEN
        RAISE EXCEPTION 'apply_exercise_correction is service-role only'
            USING ERRCODE = '42501';
    END IF;

    -- 100%-confidence gate. The CHECK constraint on exercise_corrections
    -- also enforces this; explicit check here gives a clearer error.
    IF p_confidence IS NULL OR p_confidence < 1.00 THEN
        RAISE EXCEPTION 'Correction confidence below threshold (got %, require 1.00). Anything Claude is unsure about MUST be left alone.', p_confidence
            USING ERRCODE = '23514';
    END IF;

    -- Field whitelist.
    IF p_field_name NOT IN (
        'primary_muscles','secondary_muscles',
        'workout_type','equipment_category',
        'is_compound','duration_based'
    ) THEN
        RAISE EXCEPTION 'Field % is not on the auto-correction whitelist', p_field_name
            USING ERRCODE = '23514';
    END IF;

    -- Look up current row.
    SELECT name INTO v_exercise_name FROM exercises WHERE id = p_exercise_id;
    IF v_exercise_name IS NULL THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'exercise_not_found');
    END IF;

    -- Apply per-field. Each branch reads previous, validates new, writes.
    IF p_field_name IN ('primary_muscles','secondary_muscles') THEN
        EXECUTE format('SELECT to_jsonb(%I) FROM exercises WHERE id = $1', p_field_name)
            INTO v_previous_value USING p_exercise_id;
        -- Append-only union — never remove or reorder existing entries.
        v_new_text_array := ARRAY(
            SELECT DISTINCT muscle FROM (
                SELECT jsonb_array_elements_text(COALESCE(v_previous_value, '[]'::jsonb)) AS muscle
                UNION
                SELECT jsonb_array_elements_text(p_new_value) AS muscle
            ) s
        );
        EXECUTE format('UPDATE exercises SET %I = $1 WHERE id = $2', p_field_name)
            USING v_new_text_array, p_exercise_id;
        v_corrected := TRUE;

    ELSIF p_field_name = 'workout_type' THEN
        v_new_text := p_new_value #>> '{}';
        IF v_new_text NOT IN ('Strength','Stretch','Plyometrics','Cardio') THEN
            RAISE EXCEPTION 'Invalid workout_type: %', v_new_text USING ERRCODE = '23514';
        END IF;
        SELECT to_jsonb(workout_type) INTO v_previous_value FROM exercises WHERE id = p_exercise_id;
        UPDATE exercises SET workout_type = v_new_text WHERE id = p_exercise_id;
        v_corrected := TRUE;

    ELSIF p_field_name = 'equipment_category' THEN
        v_new_text := p_new_value #>> '{}';
        SELECT to_jsonb(equipment_category) INTO v_previous_value FROM exercises WHERE id = p_exercise_id;
        UPDATE exercises SET equipment_category = v_new_text WHERE id = p_exercise_id;
        v_corrected := TRUE;

    ELSIF p_field_name = 'is_compound' THEN
        v_new_bool := (p_new_value #>> '{}')::boolean;
        SELECT to_jsonb(is_compound) INTO v_previous_value FROM exercises WHERE id = p_exercise_id;
        UPDATE exercises SET is_compound = v_new_bool WHERE id = p_exercise_id;
        v_corrected := TRUE;

    ELSIF p_field_name = 'duration_based' THEN
        v_new_bool := (p_new_value #>> '{}')::boolean;
        SELECT to_jsonb(duration_based) INTO v_previous_value FROM exercises WHERE id = p_exercise_id;
        UPDATE exercises SET duration_based = v_new_bool WHERE id = p_exercise_id;
        v_corrected := TRUE;
    END IF;

    -- Audit row (append-only).
    IF v_corrected THEN
        INSERT INTO exercise_corrections (
            exercise_id, exercise_name, field_name,
            previous_value, new_value, evidence, confidence, source_report_id
        ) VALUES (
            p_exercise_id, v_exercise_name, p_field_name,
            v_previous_value, p_new_value, p_evidence, p_confidence, p_source_report_id
        );
    END IF;

    RETURN jsonb_build_object(
        'success', v_corrected,
        'exercise_id', p_exercise_id,
        'field', p_field_name,
        'previous_value', v_previous_value,
        'new_value', p_new_value
    );
END;
$$;

REVOKE EXECUTE ON FUNCTION apply_exercise_correction(UUID, TEXT, JSONB, NUMERIC, TEXT, UUID) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION apply_exercise_correction(UUID, TEXT, JSONB, NUMERIC, TEXT, UUID) TO service_role;

COMMENT ON FUNCTION apply_exercise_correction(UUID, TEXT, JSONB, NUMERIC, TEXT, UUID) IS
    'Service-role only. Applies a corrections to the exercises catalog only when confidence = 1.00 AND field_name is on the whitelist. Append-only audit row. Anything below confidence 1.00 MUST be left alone — never queue partial confidence.';

-- ───────────────────────────────────────────────────────────────────────────
-- 9. enqueue_quality_workout_for_analysis — iOS calls after upload
-- ───────────────────────────────────────────────────────────────────────────

DROP FUNCTION IF EXISTS enqueue_quality_workout_for_analysis(UUID);

CREATE OR REPLACE FUNCTION enqueue_quality_workout_for_analysis(p_workout_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id    UUID;
    v_score      INTEGER;
    v_band       TEXT;
    v_qualifies  BOOLEAN;
BEGIN
    SELECT user_id, quality_score, quality_band, qualifies_for_corpus
      INTO v_user_id, v_score, v_band, v_qualifies
      FROM workout_history
     WHERE id = p_workout_id;

    IF v_user_id IS NULL THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'workout_not_found');
    END IF;

    -- IDOR gate. Service role passes through.
    IF auth.uid() IS NOT NULL AND v_user_id <> auth.uid() THEN
        RAISE EXCEPTION 'Forbidden: cannot enqueue another user''s workout'
            USING ERRCODE = '42501';
    END IF;

    -- Only enqueue qualifying workouts. Below-70 sub-quality workouts may
    -- still be enqueued as `is_lost_session = TRUE` if score >= 60 — these
    -- are surfaced in the CMS as "recoverable signal" and don't feed the
    -- corpus unless a human promotes them.
    IF v_score IS NULL THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'workout_not_scored');
    END IF;

    INSERT INTO ai_workout_reports (user_id, workout_id, quality_score, quality_band, status, is_lost_session)
    VALUES (
        v_user_id, p_workout_id, v_score, v_band, 'pending',
        (NOT v_qualifies AND v_score >= 60)
    )
    ON CONFLICT (workout_id) DO NOTHING;

    RETURN jsonb_build_object(
        'success', TRUE,
        'workout_id', p_workout_id,
        'quality_score', v_score,
        'queued', v_qualifies OR v_score >= 60
    );
END;
$$;

REVOKE EXECUTE ON FUNCTION enqueue_quality_workout_for_analysis(UUID) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION enqueue_quality_workout_for_analysis(UUID) TO authenticated, service_role;

COMMENT ON FUNCTION enqueue_quality_workout_for_analysis(UUID) IS
    'iOS calls this after `score_workout_quality` returns. Enqueues the workout for Claude analysis. Idempotent via UNIQUE(workout_id) on ai_workout_reports.';

-- ───────────────────────────────────────────────────────────────────────────
-- 10. Trailing fail-loud audit
-- ───────────────────────────────────────────────────────────────────────────

DO $$
DECLARE
    v_missing TEXT;
BEGIN
    -- Tables
    PERFORM 1 FROM information_schema.tables WHERE table_name = 'ai_workout_reports';
    IF NOT FOUND THEN RAISE EXCEPTION 'ai_workout_reports missing'; END IF;

    PERFORM 1 FROM information_schema.tables WHERE table_name = 'workout_swap_events';
    IF NOT FOUND THEN RAISE EXCEPTION 'workout_swap_events missing'; END IF;

    PERFORM 1 FROM information_schema.tables WHERE table_name = 'exercise_corrections';
    IF NOT FOUND THEN RAISE EXCEPTION 'exercise_corrections missing'; END IF;

    PERFORM 1 FROM information_schema.tables WHERE table_name = 'pairing_signals';
    IF NOT FOUND THEN RAISE EXCEPTION 'pairing_signals missing'; END IF;

    PERFORM 1 FROM information_schema.tables WHERE table_name = 'user_training_profile';
    IF NOT FOUND THEN RAISE EXCEPTION 'user_training_profile missing'; END IF;

    -- New columns
    PERFORM 1 FROM information_schema.columns
     WHERE table_name = 'workout_history' AND column_name = 'workout_type';
    IF NOT FOUND THEN RAISE EXCEPTION 'workout_history.workout_type missing'; END IF;

    PERFORM 1 FROM information_schema.columns
     WHERE table_name = 'exercise_set_history' AND column_name = 'completed_at';
    IF NOT FOUND THEN RAISE EXCEPTION 'exercise_set_history.completed_at missing'; END IF;

    -- RPCs
    PERFORM 1 FROM pg_proc WHERE proname = 'apply_exercise_correction';
    IF NOT FOUND THEN RAISE EXCEPTION 'apply_exercise_correction RPC missing'; END IF;

    PERFORM 1 FROM pg_proc WHERE proname = 'enqueue_quality_workout_for_analysis';
    IF NOT FOUND THEN RAISE EXCEPTION 'enqueue_quality_workout_for_analysis RPC missing'; END IF;

    -- Confidence-gate enforcement: the exercise_corrections.confidence
    -- CHECK MUST be the strict equality form. Any future migration that
    -- relaxes this must explicitly drop+recreate the CHECK and document
    -- why in the migration header.
    SELECT pg_get_constraintdef(oid) INTO v_missing
      FROM pg_constraint
     WHERE conname = 'exercise_corrections_confidence_check';
    IF v_missing IS NULL OR v_missing NOT LIKE '%confidence = 1.00%' THEN
        RAISE EXCEPTION 'exercise_corrections.confidence CHECK must enforce confidence = 1.00 exactly. Got: %', v_missing;
    END IF;

    RAISE NOTICE '✅ Workout Intelligence migration complete (#156): ai_workout_reports, workout_swap_events, exercise_corrections, pairing_signals, user_training_profile + 2 columns + 2 RPCs.';
END $$;

COMMIT;
