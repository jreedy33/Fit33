-- ═══════════════════════════════════════════════════════════════════════════
-- 20260730_correction_audit_fix.sql  (Migration #161)
--
-- Two fixes for the catalog-correction audit trail (#157):
--
-- 1. AUDIT NEW_VALUE BUG
--    For ADD / REMOVE muscle operations, `apply_exercise_correction` was
--    writing `p_new_value` (the INPUT — items to add/remove) into
--    `exercise_corrections.new_value` instead of the resulting array
--    state. Display showed `["Chest","Shoulders"] -> ["Chest","Shoulders"]`
--    on a removal, looking like a no-op even though the catalog row WAS
--    correctly updated. This migration rewrites the function to store
--    the post-state in `new_value`. Existing audit rows are not modified
--    (they're append-only history); only future corrections get the
--    correct display.
--
-- 2. ADMIN OVERRIDE PATH FOR BLOCKED PROPOSALS
--    The pull-up case (Triceps + Front Delts incorrectly tagged as
--    secondary muscles, sister-corroborated removal blocked because
--    pull-ups are on `catalog_core_exercises`) needs a way for a human
--    admin to explicitly approve the removal. This migration adds
--    `admin_apply_correction_proposal(p_proposal_id UUID)` SECURITY
--    DEFINER RPC. Service-role only; called from the CMS proposals
--    page when an admin clicks "Approve". Bypasses the core-exercise
--    lockout BUT only for the specific proposal — fresh corrections
--    against the same exercise still go through the lockout.
--    The override is logged with corroboration_kind='admin_override'
--    so the audit trail makes the bypass visible.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

-- ───────────────────────────────────────────────────────────────────────────
-- 1. Replace apply_exercise_correction so the audit row records the
--    POST-state, not the input. Same signature; pure body change.
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

    -- Corroboration gate marker required. 'admin_override' is now an
    -- accepted kind (only callable via admin_apply_correction_proposal).
    IF p_corroboration_kind IS NULL OR
       p_corroboration_kind NOT IN ('sister','name','multi_report','admin_override') THEN
        RAISE EXCEPTION 'No corroboration gate (sister/name/multi_report/admin_override) supplied — refusing to apply'
            USING ERRCODE = '42501';
    END IF;

    SELECT name INTO v_exercise_name FROM exercises WHERE id = p_exercise_id;
    IF v_exercise_name IS NULL THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'exercise_not_found');
    END IF;

    -- Core-exercise lockout — bypassed ONLY by admin_override.
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

        IF p_operation = 'add' THEN
            v_new_text_array := ARRAY(
                SELECT DISTINCT muscle FROM (
                    SELECT unnest(v_existing_array) AS muscle
                    UNION
                    SELECT jsonb_array_elements_text(p_new_value) AS muscle
                ) s
            );
        ELSIF p_operation = 'remove' THEN
            v_remove_array := ARRAY(SELECT jsonb_array_elements_text(p_new_value));
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

    -- Audit row — store POST-state in new_value (the bug-fix).
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
    'Service-role only. Requires p_corroboration_kind ∈ {sister,name,multi_report,admin_override}. Stores the POST-update state in exercise_corrections.new_value (not the input items). Removals against catalog_core_exercises are blocked unless corroboration_kind = admin_override.';

-- ───────────────────────────────────────────────────────────────────────────
-- 2. New: admin_apply_correction_proposal — explicit human override path.
--    Takes a proposal_id, flips it to applied via apply_exercise_correction
--    with corroboration_kind='admin_override'. Always succeeds for
--    pending / blocked_core_exercise rows; rejects already-applied or
--    rejected proposals.
-- ───────────────────────────────────────────────────────────────────────────

DROP FUNCTION IF EXISTS admin_apply_correction_proposal(UUID);

CREATE OR REPLACE FUNCTION admin_apply_correction_proposal(p_proposal_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    p RECORD;
    v_apply_result JSONB;
BEGIN
    -- Service role only — no user-JWT path.
    IF auth.uid() IS NOT NULL THEN
        RAISE EXCEPTION 'admin_apply_correction_proposal is service-role only'
            USING ERRCODE = '42501';
    END IF;

    SELECT * INTO p
      FROM exercise_correction_proposals
     WHERE id = p_proposal_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'proposal_not_found');
    END IF;

    IF p.status NOT IN ('pending', 'blocked_core_exercise') THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'reason', 'invalid_status_for_apply',
            'current_status', p.status
        );
    END IF;

    BEGIN
        v_apply_result := apply_exercise_correction(
            p.exercise_id, p.field_name, p.operation, p.proposed_value,
            p.confidence, p.evidence, p.source_report_id, 'admin_override'
        );

        UPDATE exercise_correction_proposals
           SET status = 'applied',
               applied_correction_id = (v_apply_result->>'correction_id')::UUID,
               decided_at = NOW()
         WHERE id = p_proposal_id;

        RETURN jsonb_build_object(
            'success', TRUE,
            'proposal_id', p_proposal_id,
            'corroboration_kind', 'admin_override',
            'apply_result', v_apply_result
        );
    EXCEPTION WHEN OTHERS THEN
        UPDATE exercise_correction_proposals
           SET status = 'rejected',
               rejected_reason = 'admin_apply_failed: ' || LEFT(SQLERRM, 200),
               decided_at = NOW()
         WHERE id = p_proposal_id;
        RETURN jsonb_build_object(
            'success', FALSE,
            'proposal_id', p_proposal_id,
            'error', SQLERRM
        );
    END;
END;
$$;

REVOKE EXECUTE ON FUNCTION admin_apply_correction_proposal(UUID) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION admin_apply_correction_proposal(UUID) TO service_role;

COMMENT ON FUNCTION admin_apply_correction_proposal(UUID) IS
    'Admin override: forcibly applies a pending or blocked_core_exercise proposal, bypassing the corroboration ladder and the canonical-exercise lockout. corroboration_kind=admin_override in the audit trail. Service-role only — CMS calls this when an admin clicks "Approve" on a queued proposal.';

-- ───────────────────────────────────────────────────────────────────────────
-- 3. Convenience: admin_reject_correction_proposal
-- ───────────────────────────────────────────────────────────────────────────

DROP FUNCTION IF EXISTS admin_reject_correction_proposal(UUID, TEXT);

CREATE OR REPLACE FUNCTION admin_reject_correction_proposal(p_proposal_id UUID, p_reason TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_status TEXT;
BEGIN
    IF auth.uid() IS NOT NULL THEN
        RAISE EXCEPTION 'admin_reject_correction_proposal is service-role only'
            USING ERRCODE = '42501';
    END IF;

    SELECT status INTO v_status
      FROM exercise_correction_proposals
     WHERE id = p_proposal_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'proposal_not_found');
    END IF;

    IF v_status NOT IN ('pending', 'blocked_core_exercise') THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'reason', 'invalid_status_for_reject',
            'current_status', v_status
        );
    END IF;

    UPDATE exercise_correction_proposals
       SET status = 'rejected',
           rejected_reason = COALESCE(NULLIF(p_reason, ''), 'manual_admin_reject'),
           decided_at = NOW()
     WHERE id = p_proposal_id;

    RETURN jsonb_build_object('success', TRUE, 'proposal_id', p_proposal_id);
END;
$$;

REVOKE EXECUTE ON FUNCTION admin_reject_correction_proposal(UUID, TEXT) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION admin_reject_correction_proposal(UUID, TEXT) TO service_role;

COMMENT ON FUNCTION admin_reject_correction_proposal(UUID, TEXT) IS
    'Admin reject: marks a pending or blocked_core_exercise proposal as rejected with a reason string. Service-role only.';

COMMIT;
