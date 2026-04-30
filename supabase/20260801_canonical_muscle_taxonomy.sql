-- ═══════════════════════════════════════════════════════════════════════════
-- 20260801_canonical_muscle_taxonomy.sql  (Migration #163)
--
-- Fixes a real taxonomy drift in `exercises.primary_muscles` /
-- `exercises.secondary_muscles` where the same anatomical muscle is
-- stored under both a long anatomical name and a canonical short
-- name across different rows. The drift caused #157's sister-corroboration
-- gate to fire on a REMOVE proposal for "Latissimus Dorsi" on the
-- Bent Over Row (Smith Machine) variants — Claude correctly noticed
-- 13 other rows in `bent_over_row` family use ["Back","Lats"] while
-- 3 Smith Machine rows use ["Latissimus Dorsi"], and proposed
-- removing the outlier. The proposal was technically valid but the
-- right answer is a RENAME, not a DELETE — clicking "Override" on
-- it would have left primary_muscles=[] (no back tag at all).
--
-- ─── Drift map (verified 2026-04-29 against prod catalog) ──────────────
--   "Latissimus Dorsi"  →  "Lats"        (3 rows in primary_muscles)
--   "Pectorals"         →  "Chest"       (10 rows in primary_muscles)
--   "Quadriceps"        →  "Quads"       (12 rows in primary_muscles)
--   "Trapezius"         →  "Traps"       (2 rows in primary_muscles)
-- ─────────────────────────────────────────────────────────────────────────
-- Total: 27 row updates, all in primary_muscles, none in secondary_muscles.
-- ═══════════════════════════════════════════════════════════════════════════
--
-- This migration does THREE things:
--
-- 1.  DATA CLEANUP  — swaps each long form for its canonical short form
--     in every `exercises` row. Idempotent (re-running is a no-op).
--
-- 2.  REJECT THE NOW-INVALID PROPOSALS — the 2 Bent Over Row +1 Pull-Up
--     `remove` proposals that fired on the drift are auto-rejected with
--     a clear `rejected_reason` so the queue is clean. The Pull-Up case
--     is a separate real issue (legacy v1 #156 append-only bug) and is
--     LEFT pending so the admin can override it through the new UI.
--     Actually — reading carefully, the Pull-Up proposal is removing
--     "Front Delts" + "Triceps", which is unrelated to the taxonomy
--     drift, so it stays. Only the 2 Bent Over Row "Latissimus Dorsi"
--     proposals get auto-rejected.
--
-- 3.  GUARDRAIL  — `apply_exercise_correction` is rewritten to normalize
--     incoming muscle names through the canonical map BEFORE applying
--     them. Future Claude proposals using long-form names (e.g. someone
--     adds "Pectorals" to a chest exercise) silently land as their short
--     form, so the catalog can never drift back.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

-- ───────────────────────────────────────────────────────────────────────────
-- 1. DATA CLEANUP — replace long forms with canonical short forms in
--    every existing row. Uses a single UPDATE per column, with
--    array_replace semantics implemented via unnest+array_agg so we
--    handle the case where both the long and short form already
--    coexist in the same array (e.g. ["Lats", "Latissimus Dorsi"]
--    → ["Lats"] without dupes).
-- ───────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION _normalize_muscle_array(p_arr TEXT[])
RETURNS TEXT[]
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT ARRAY(
        SELECT DISTINCT
            CASE m
                WHEN 'Latissimus Dorsi' THEN 'Lats'
                WHEN 'Pectorals'        THEN 'Chest'
                WHEN 'Quadriceps'       THEN 'Quads'
                WHEN 'Trapezius'        THEN 'Traps'
                ELSE m
            END AS m_norm
        FROM unnest(COALESCE(p_arr, ARRAY[]::TEXT[])) AS m
    );
$$;

COMMENT ON FUNCTION _normalize_muscle_array(TEXT[]) IS
    'Internal helper: maps known long-form anatomical muscle names to their canonical short forms. DISTINCT-ed so that an array containing both forms collapses without dupes. Used by both the one-shot data cleanup in #163 and the apply_exercise_correction guardrail.';

-- Cleanup primary_muscles
UPDATE exercises
   SET primary_muscles = _normalize_muscle_array(primary_muscles)
 WHERE primary_muscles && ARRAY['Latissimus Dorsi','Pectorals','Quadriceps','Trapezius']::TEXT[];

-- Cleanup secondary_muscles (verified 0 rows currently, but keep for safety)
UPDATE exercises
   SET secondary_muscles = _normalize_muscle_array(secondary_muscles)
 WHERE secondary_muscles && ARRAY['Latissimus Dorsi','Pectorals','Quadriceps','Trapezius']::TEXT[];

-- ───────────────────────────────────────────────────────────────────────────
-- 2. AUTO-REJECT the 2 Bent Over Row proposals that fired on this drift.
--    Match on (exercise_name LIKE 'Bent Over Row%' AND field_name LIKE
--    '%_muscles' AND operation='remove' AND proposed_value @>
--    '["Latissimus Dorsi"]') so we don't accidentally reject anything else.
--    The Pull-Up proposal stays pending — it's a real legacy issue.
-- ───────────────────────────────────────────────────────────────────────────

UPDATE exercise_correction_proposals
   SET status = 'rejected',
       rejected_reason = 'taxonomy_drift_fixed_by_migration_163: target was a long-form muscle name that has been renamed to its canonical short form across the catalog; the remove proposal is now moot.',
       decided_at = NOW()
 WHERE status IN ('pending','blocked_core_exercise')
   AND exercise_name LIKE 'Bent Over Row%'
   AND field_name IN ('primary_muscles','secondary_muscles')
   AND operation = 'remove'
   AND proposed_value @> '["Latissimus Dorsi"]'::jsonb;

-- ───────────────────────────────────────────────────────────────────────────
-- 3. GUARDRAIL — rewrite apply_exercise_correction to normalize muscle
--    arrays through the canonical map before union/diff. Same signature
--    and same corroboration-gate semantics as #162; only the muscle
--    branch is touched. (Scalar-field corrections — workout_type,
--    equipment_category, is_compound, duration_based — are unchanged.)
-- ───────────────────────────────────────────────────────────────────────────

DROP FUNCTION IF EXISTS apply_exercise_correction(UUID, TEXT, TEXT, JSONB, NUMERIC, TEXT, UUID, TEXT);

CREATE OR REPLACE FUNCTION apply_exercise_correction(
    p_exercise_id      UUID,
    p_field_name       TEXT,
    p_operation        TEXT,
    p_new_value        JSONB,
    p_confidence       NUMERIC,
    p_evidence         TEXT,
    p_source_report_id UUID DEFAULT NULL,
    p_corroboration_kind TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_exercise_name   TEXT;
    v_previous_value  JSONB;
    v_post_value      JSONB;
    v_corrected       BOOLEAN := FALSE;
    v_new_text        TEXT;
    v_new_bool        BOOLEAN;
    v_new_text_array  TEXT[];
    v_existing_array  TEXT[];
    v_remove_array    TEXT[];
    v_input_array     TEXT[];
    v_correction_id   UUID;
BEGIN
    IF auth.uid() IS NOT NULL THEN
        RAISE EXCEPTION 'apply_exercise_correction is service-role only'
            USING ERRCODE = '42501';
    END IF;

    IF p_confidence IS NULL OR p_confidence < 1.00 THEN
        RAISE EXCEPTION 'Correction confidence below threshold (got %, require 1.00)', p_confidence
            USING ERRCODE = '23514';
    END IF;

    IF p_field_name NOT IN (
        'primary_muscles','secondary_muscles',
        'workout_type','equipment_category',
        'is_compound','duration_based'
    ) THEN
        RAISE EXCEPTION 'Field % not on whitelist', p_field_name USING ERRCODE = '23514';
    END IF;

    IF p_operation NOT IN ('add','set','remove') THEN
        RAISE EXCEPTION 'Operation % not allowed', p_operation USING ERRCODE = '23514';
    END IF;

    IF p_field_name IN ('primary_muscles','secondary_muscles') AND p_operation = 'set' THEN
        RAISE EXCEPTION 'set on muscle arrays is not auto-appliable; use add/remove' USING ERRCODE = '23514';
    END IF;
    IF p_field_name NOT IN ('primary_muscles','secondary_muscles') AND p_operation <> 'set' THEN
        RAISE EXCEPTION 'scalar field % only supports operation=set', p_field_name USING ERRCODE = '23514';
    END IF;

    IF p_corroboration_kind IS NULL OR
       p_corroboration_kind NOT IN ('sister','name','multi_report','admin_override') THEN
        RAISE EXCEPTION 'No corroboration gate (sister/name/multi_report/admin_override) supplied — refusing to apply'
            USING ERRCODE = '42501';
    END IF;

    SELECT name INTO v_exercise_name FROM exercises WHERE id = p_exercise_id;
    IF v_exercise_name IS NULL THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'exercise_not_found');
    END IF;

    IF p_operation = 'remove'
       AND p_corroboration_kind <> 'admin_override'
       AND _correction_is_core_exercise(v_exercise_name) THEN
        RAISE EXCEPTION 'Removal corrections are blocked for core canonical exercises (matched: %). Manual approval required.', v_exercise_name
            USING ERRCODE = '42501';
    END IF;

    -- ── Apply per-field/operation. ─────────────────────────────────────
    IF p_field_name IN ('primary_muscles','secondary_muscles') THEN
        EXECUTE format('SELECT to_jsonb(%I) FROM exercises WHERE id = $1', p_field_name)
            INTO v_previous_value USING p_exercise_id;
        v_existing_array := ARRAY(
            SELECT jsonb_array_elements_text(COALESCE(v_previous_value, '[]'::jsonb))
        );

        v_input_array := _normalize_muscle_array(
            ARRAY(SELECT jsonb_array_elements_text(p_new_value))
        );

        IF p_operation = 'add' THEN
            v_new_text_array := _normalize_muscle_array(
                v_existing_array || v_input_array
            );
        ELSIF p_operation = 'remove' THEN
            v_remove_array := v_input_array;
            v_new_text_array := ARRAY(
                SELECT muscle FROM unnest(v_existing_array) AS muscle
                 WHERE muscle <> ALL(v_remove_array)
            );
        END IF;

        EXECUTE format('UPDATE exercises SET %I = $1 WHERE id = $2', p_field_name)
            USING v_new_text_array, p_exercise_id;
        v_post_value := to_jsonb(v_new_text_array);
        v_corrected := TRUE;

    ELSIF p_field_name = 'workout_type' THEN
        v_new_text := p_new_value #>> '{}';
        IF v_new_text NOT IN ('Strength','Stretch','Plyometrics','Cardio') THEN
            RAISE EXCEPTION 'Invalid workout_type: %', v_new_text USING ERRCODE = '23514';
        END IF;
        SELECT to_jsonb(workout_type) INTO v_previous_value FROM exercises WHERE id = p_exercise_id;
        UPDATE exercises SET workout_type = v_new_text WHERE id = p_exercise_id;
        v_post_value := to_jsonb(v_new_text);
        v_corrected := TRUE;

    ELSIF p_field_name = 'equipment_category' THEN
        v_new_text := p_new_value #>> '{}';
        SELECT to_jsonb(equipment_category) INTO v_previous_value FROM exercises WHERE id = p_exercise_id;
        UPDATE exercises SET equipment_category = v_new_text WHERE id = p_exercise_id;
        v_post_value := to_jsonb(v_new_text);
        v_corrected := TRUE;

    ELSIF p_field_name = 'is_compound' THEN
        v_new_bool := (p_new_value #>> '{}')::boolean;
        SELECT to_jsonb(is_compound) INTO v_previous_value FROM exercises WHERE id = p_exercise_id;
        UPDATE exercises SET is_compound = v_new_bool WHERE id = p_exercise_id;
        v_post_value := to_jsonb(v_new_bool);
        v_corrected := TRUE;

    ELSIF p_field_name = 'duration_based' THEN
        v_new_bool := (p_new_value #>> '{}')::boolean;
        SELECT to_jsonb(duration_based) INTO v_previous_value FROM exercises WHERE id = p_exercise_id;
        UPDATE exercises SET duration_based = v_new_bool WHERE id = p_exercise_id;
        v_post_value := to_jsonb(v_new_bool);
        v_corrected := TRUE;
    END IF;

    IF v_corrected THEN
        INSERT INTO exercise_corrections (
            exercise_id, exercise_name, field_name,
            previous_value, new_value, evidence, confidence, source_report_id
        ) VALUES (
            p_exercise_id, v_exercise_name, p_field_name,
            v_previous_value, v_post_value, p_evidence || ' [' || p_corroboration_kind || ']',
            p_confidence, p_source_report_id
        )
        RETURNING id INTO v_correction_id;
    END IF;

    RETURN jsonb_build_object(
        'success', v_corrected,
        'exercise_id', p_exercise_id,
        'field', p_field_name,
        'operation', p_operation,
        'corroboration_kind', p_corroboration_kind,
        'previous_value', v_previous_value,
        'new_value', v_post_value,
        'correction_id', v_correction_id
    );
END;
$$;

REVOKE EXECUTE ON FUNCTION apply_exercise_correction(UUID, TEXT, TEXT, JSONB, NUMERIC, TEXT, UUID, TEXT) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION apply_exercise_correction(UUID, TEXT, TEXT, JSONB, NUMERIC, TEXT, UUID, TEXT) TO service_role;

COMMENT ON FUNCTION apply_exercise_correction(UUID, TEXT, TEXT, JSONB, NUMERIC, TEXT, UUID, TEXT) IS
    'Service-role only. Requires p_corroboration_kind ∈ {sister,name,multi_report,admin_override}. Stores POST-state in exercise_corrections.new_value. Removals against catalog_core_exercises are blocked unless corroboration_kind = admin_override. Muscle inputs are normalized through _normalize_muscle_array() so long-form anatomical names (Latissimus Dorsi, Pectorals, Quadriceps, Trapezius) are silently mapped to canonical short forms (Lats, Chest, Quads, Traps).';

-- ───────────────────────────────────────────────────────────────────────────
-- 4. AUDIT — fail-loud verification.
-- ───────────────────────────────────────────────────────────────────────────

DO $$
DECLARE
    v_drift_remaining INT;
    v_rejected_count  INT;
BEGIN
    SELECT COUNT(*)
      INTO v_drift_remaining
      FROM exercises
     WHERE primary_muscles   && ARRAY['Latissimus Dorsi','Pectorals','Quadriceps','Trapezius']::TEXT[]
        OR secondary_muscles && ARRAY['Latissimus Dorsi','Pectorals','Quadriceps','Trapezius']::TEXT[];

    IF v_drift_remaining > 0 THEN
        RAISE EXCEPTION 'Migration #163 audit FAILED: % rows still contain long-form muscle names after cleanup', v_drift_remaining;
    END IF;

    SELECT COUNT(*)
      INTO v_rejected_count
      FROM exercise_correction_proposals
     WHERE status = 'rejected'
       AND rejected_reason LIKE 'taxonomy_drift_fixed_by_migration_163%';

    RAISE NOTICE 'Migration #163 audit OK — 0 drift rows remain, % stale proposals auto-rejected', v_rejected_count;
END;
$$;

COMMIT;
