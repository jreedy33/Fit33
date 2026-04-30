-- ═══════════════════════════════════════════════════════════════════════════
-- 20260726_correction_corroboration.sql  (Migration #157)
--
-- Tightens the catalog-correction policy from "Claude says 1.0 → apply"
-- to "Claude says 1.0 AND a deterministic gate agrees → apply". Anything
-- that doesn't pass a gate goes to a corroboration queue (NOT a partial-
-- confidence review queue — it's still 1.0, just unconfirmed).
--
-- WHY
-- ---
-- Migration #156 trusted Claude's self-reported confidence as the only
-- gate. The first real run produced an "addition" correction that was
-- factually right (pull-ups DO use biceps + rear delts as secondary)
-- but exposed two structural weaknesses:
--   1. Self-asserted confidence is unverifiable.
--   2. The append-only union prevents data LOSS but creates a one-way
--      ratchet — every wrong tag accumulates forever, degrading catalog
--      quality over time.
-- This migration adds three deterministic corroboration gates and a
-- separate (stricter) path for REMOVALS so we can fix the existing
-- bad-tag problem without trusting Claude unilaterally.
--
-- THE THREE GATES (auto-apply requires confidence=1.0 AND ≥1 of these)
-- ---------------------------------------------------------------------
--   (a) sister  — for muscle additions: a sister exercise (same
--       exercise_family) already has the proposed muscle in the same
--       field. (Pull-up adding "Biceps" → chin-ups already have it.)
--   (b) name    — exercise name contains an unambiguous keyword for the
--       proposed value (TRUE-direction only — see name keyword maps in
--       `_correction_name_gate` below).
--   (c) multi   — same correction proposed by ≥2 different source
--       reports in the last 30 days.
--
-- If confidence=1.0 but NO gate passes → proposal lands in
-- `exercise_correction_proposals` with `status='pending'`. The CMS
-- surfaces it. A nightly cron `promote_corroborated_proposals()` rechecks
-- pending proposals — the moment gate (a)/(b)/(c) passes, the proposal
-- auto-applies via the same path. No human intervention required for
-- well-corroborated proposals.
--
-- REMOVAL PATH (stricter)
-- -----------------------
--   `operation='remove'` deletes one or more values from a muscle array.
--   Auto-apply requires:
--     confidence = 1.0
--     AND multi-report count ≥ 3 (NOT 2 — destructive op)
--     AND ≥ 2 sister exercises do NOT have the value being removed
--   Anything else → proposal queue.
--
-- WHITELIST (unchanged from #156)
-- -------------------------------
--   primary_muscles, secondary_muscles (add | remove)
--   workout_type, equipment_category   (set)
--   is_compound, duration_based         (set)
--
-- NEVER auto-applied: removal of a CORE canonical exercise's muscle tag
-- (bench, squat, deadlift, OHP, row family) — those go straight to queue
-- regardless of corroboration. Defense-in-depth against a systemic bug
-- that proposes "remove Pec from Bench Press". Even 3 corroborating
-- reports for that should be human-reviewed.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

-- ───────────────────────────────────────────────────────────────────────────
-- 1. exercise_correction_proposals — the corroboration queue
-- ───────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS exercise_correction_proposals (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    exercise_id     UUID NOT NULL,
    exercise_name   TEXT NOT NULL,
    field_name      TEXT NOT NULL CHECK (field_name IN (
        'primary_muscles','secondary_muscles',
        'workout_type','equipment_category',
        'is_compound','duration_based'
    )),
    operation       TEXT NOT NULL CHECK (operation IN ('add','set','remove')),
    proposed_value  JSONB NOT NULL,
    evidence        TEXT NOT NULL,
    confidence      NUMERIC(3,2) NOT NULL CHECK (confidence > 0 AND confidence <= 1),
    source_report_id UUID REFERENCES ai_workout_reports(id) ON DELETE SET NULL,

    -- Corroboration evidence (filled by propose_exercise_correction +
    -- promote_corroborated_proposals). Each is independently sufficient
    -- (subject to the operation-specific thresholds below). The cron
    -- recomputes these on every run.
    sister_corroborated  BOOLEAN NOT NULL DEFAULT FALSE,
    name_corroborated    BOOLEAN NOT NULL DEFAULT FALSE,
    multi_report_count   INTEGER NOT NULL DEFAULT 1,

    -- Lifecycle
    status          TEXT NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending','applied','rejected','superseded','blocked_core_exercise')),
    applied_correction_id UUID REFERENCES exercise_corrections(id) ON DELETE SET NULL,
    rejected_reason TEXT,
    rejected_by     UUID,                    -- admin user id when manually rejected
    proposed_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    decided_at      TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_correction_proposals_pending
    ON exercise_correction_proposals (proposed_at DESC) WHERE status = 'pending';
CREATE INDEX IF NOT EXISTS idx_correction_proposals_exercise
    ON exercise_correction_proposals (exercise_id, proposed_at DESC);
CREATE INDEX IF NOT EXISTS idx_correction_proposals_dedup
    ON exercise_correction_proposals (exercise_id, field_name, operation, proposed_value);

ALTER TABLE exercise_correction_proposals ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "proposals_authed_read" ON exercise_correction_proposals;
CREATE POLICY "proposals_authed_read" ON exercise_correction_proposals
    FOR SELECT USING (auth.role() = 'authenticated');

-- INSERT/UPDATE only via service role.
COMMENT ON TABLE exercise_correction_proposals IS
    'Append-only corroboration queue. Every Claude-proposed catalog change starts here. Auto-promotes to exercise_corrections (and the canonical exercises catalog) when a deterministic gate passes. Anything else sits for nightly cron review or one-click admin approval.';

-- ───────────────────────────────────────────────────────────────────────────
-- 2. Core-exercise blocklist (defense-in-depth)
--    Removals against canonical names are NEVER auto-applied, regardless
--    of corroboration count. Add to this list cautiously; it's a hard
--    safety net for the systemic-bug case ("remove Pec from Bench Press").
-- ───────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS catalog_core_exercises (
    name_pattern    TEXT PRIMARY KEY    -- ILIKE pattern, e.g. '%bench press%'
);

INSERT INTO catalog_core_exercises (name_pattern) VALUES
    ('%bench press%'),
    ('%back squat%'),
    ('%front squat%'),
    ('%deadlift%'),
    ('%overhead press%'),
    ('%shoulder press%'),
    ('%pull-up%'),
    ('%pull up%'),
    ('%pullup%'),
    ('%chin-up%'),
    ('%chin up%'),
    ('%chinup%'),
    ('%barbell row%'),
    ('%bent over row%'),
    ('%clean%'),
    ('%snatch%'),
    ('%jerk%')
ON CONFLICT (name_pattern) DO NOTHING;

ALTER TABLE catalog_core_exercises ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "core_exercises_read" ON catalog_core_exercises;
CREATE POLICY "core_exercises_read" ON catalog_core_exercises
    FOR SELECT USING (auth.role() = 'authenticated');

COMMENT ON TABLE catalog_core_exercises IS
    'Hard-list of canonical exercise name patterns. Removal corrections targeting these exercises are NEVER auto-applied regardless of corroboration count — they always queue for explicit human approval.';

-- ───────────────────────────────────────────────────────────────────────────
-- 3. Gate (a): sister-exercise corroboration
--    For muscle ADDITIONS: returns TRUE iff ≥1 other exercise in the same
--    `exercise_family` already has ALL of the proposed values in the
--    field. For muscle REMOVALS: returns TRUE iff ≥2 sisters do NOT have
--    the value being removed (sister-disagreement).
-- ───────────────────────────────────────────────────────────────────────────

DROP FUNCTION IF EXISTS _correction_sister_gate(UUID, TEXT, TEXT, JSONB);

CREATE OR REPLACE FUNCTION _correction_sister_gate(
    p_exercise_id UUID,
    p_field_name  TEXT,
    p_operation   TEXT,
    p_value       JSONB
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_family   TEXT;
    v_count    INTEGER;
    v_values   TEXT[];
BEGIN
    SELECT exercise_family INTO v_family
      FROM exercises WHERE id = p_exercise_id;
    IF v_family IS NULL OR v_family = '' THEN
        RETURN FALSE;
    END IF;

    -- Sister gate only applies to muscle fields.
    IF p_field_name NOT IN ('primary_muscles','secondary_muscles') THEN
        RETURN FALSE;
    END IF;

    v_values := ARRAY(SELECT jsonb_array_elements_text(p_value));

    IF p_operation = 'add' THEN
        -- ≥1 sister already has ALL of these values.
        EXECUTE format(
            'SELECT count(*) FROM exercises
              WHERE exercise_family = $1
                AND id <> $2
                AND %I @> $3',
            p_field_name
        )
        INTO v_count
        USING v_family, p_exercise_id, v_values;
        RETURN v_count >= 1;

    ELSIF p_operation = 'remove' THEN
        -- ≥2 sisters do NOT have the values being removed (sister-disagreement).
        EXECUTE format(
            'SELECT count(*) FROM exercises
              WHERE exercise_family = $1
                AND id <> $2
                AND NOT (COALESCE(%I, ARRAY[]::TEXT[]) && $3)',
            p_field_name
        )
        INTO v_count
        USING v_family, p_exercise_id, v_values;
        RETURN v_count >= 2;
    END IF;

    RETURN FALSE;
END;
$$;

REVOKE EXECUTE ON FUNCTION _correction_sister_gate(UUID, TEXT, TEXT, JSONB) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION _correction_sister_gate(UUID, TEXT, TEXT, JSONB) TO service_role;

-- ───────────────────────────────────────────────────────────────────────────
-- 4. Gate (b): name-based determinism
--    Conservative — only matches in the TRUE / Strength / Stretch
--    direction, never the negative direction. The reasoning: "this name
--    contains 'deadlift' so is_compound=TRUE" is unambiguous; "this name
--    has no compound keyword so is_compound=FALSE" is not.
-- ───────────────────────────────────────────────────────────────────────────

DROP FUNCTION IF EXISTS _correction_name_gate(TEXT, TEXT, TEXT, JSONB);

CREATE OR REPLACE FUNCTION _correction_name_gate(
    p_exercise_name TEXT,
    p_field_name    TEXT,
    p_operation     TEXT,
    p_value         JSONB
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_lname TEXT := LOWER(COALESCE(p_exercise_name, ''));
    v_text  TEXT;
    v_bool  BOOLEAN;
BEGIN
    -- Only set-operations on scalar fields are name-gateable.
    IF p_operation <> 'set' THEN
        RETURN FALSE;
    END IF;

    IF p_field_name = 'is_compound' THEN
        v_bool := (p_value #>> '{}')::boolean;
        IF v_bool IS TRUE THEN
            RETURN v_lname ~ '\m(deadlift|back squat|front squat|bench press|incline press|barbell row|bent over row|pull-up|pull up|pullup|chin-up|chin up|chinup|dip|overhead press|shoulder press|push press|push jerk|thruster|clean|snatch|jerk|hip thrust|lunge|step.up|stepup|farmer.s carry|romanian deadlift|rdl)\M';
        END IF;
        RETURN FALSE;

    ELSIF p_field_name = 'duration_based' THEN
        v_bool := (p_value #>> '{}')::boolean;
        IF v_bool IS TRUE THEN
            RETURN v_lname ~ '\m(plank|side plank|dead.?hang|wall sit|hold|isometric|static|bear crawl|hollow hold)\M';
        END IF;
        -- duration_based=FALSE is rep-counting — only auto via name when
        -- the name contains explicit rep / set verbs that exclude duration.
        IF v_bool IS FALSE THEN
            RETURN v_lname ~ '\m(curl|press|raise|fly|extension|row|pulldown|pullup|pull-up|squat|deadlift|push.up|pushup)\M'
               AND v_lname !~ '\m(hold|isometric|static|plank)\M';
        END IF;
        RETURN FALSE;

    ELSIF p_field_name = 'workout_type' THEN
        v_text := p_value #>> '{}';
        IF v_text = 'Strength' THEN
            RETURN v_lname ~ '\m(press|curl|row|squat|deadlift|lift|extension|pulldown|pullup|pull-up|chin.up|dip|fly|raise|thrust|carry|kickback|pushdown|push.up|pushup)\M';
        ELSIF v_text = 'Stretch' THEN
            RETURN v_lname ~ '\m(stretch|mobility|pose|opener|reach|flexion stretch|hip flexor stretch|cobra|childs pose|child.s pose|pigeon|warrior pose)\M';
        ELSIF v_text = 'Plyometrics' THEN
            RETURN v_lname ~ '\m(jump|hop|bound|plyo|skater|burpee|box jump|broad jump)\M';
        ELSIF v_text = 'Cardio' THEN
            RETURN v_lname ~ '\m(run|jog|sprint|cycle|cycling|row machine|treadmill|elliptical|jump rope|skip rope)\M';
        END IF;
        RETURN FALSE;

    ELSIF p_field_name = 'equipment_category' THEN
        v_text := LOWER(COALESCE(p_value #>> '{}', ''));
        -- Only auto-apply when the exercise name contains the exact
        -- equipment word — e.g. "Cable Lateral Raise" → "Cable".
        IF v_text = '' THEN RETURN FALSE; END IF;
        RETURN v_lname LIKE '%' || v_text || '%';
    END IF;

    RETURN FALSE;
END;
$$;

REVOKE EXECUTE ON FUNCTION _correction_name_gate(TEXT, TEXT, TEXT, JSONB) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION _correction_name_gate(TEXT, TEXT, TEXT, JSONB) TO service_role;

-- ───────────────────────────────────────────────────────────────────────────
-- 5. Gate (c): multi-report agreement
--    Counts DISTINCT source_report_id rows in exercise_correction_proposals
--    that propose the SAME (exercise_id, field_name, operation,
--    proposed_value) within the last 30 days. Includes the current
--    proposal in its own count.
-- ───────────────────────────────────────────────────────────────────────────

DROP FUNCTION IF EXISTS _correction_multi_report_count(UUID, TEXT, TEXT, JSONB);

CREATE OR REPLACE FUNCTION _correction_multi_report_count(
    p_exercise_id UUID,
    p_field_name  TEXT,
    p_operation   TEXT,
    p_value       JSONB
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_count INTEGER;
BEGIN
    SELECT COUNT(DISTINCT source_report_id)
      INTO v_count
      FROM exercise_correction_proposals
     WHERE exercise_id = p_exercise_id
       AND field_name  = p_field_name
       AND operation   = p_operation
       AND proposed_value = p_value
       AND proposed_at >= NOW() - INTERVAL '30 days';
    RETURN COALESCE(v_count, 0);
END;
$$;

REVOKE EXECUTE ON FUNCTION _correction_multi_report_count(UUID, TEXT, TEXT, JSONB) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION _correction_multi_report_count(UUID, TEXT, TEXT, JSONB) TO service_role;

-- ───────────────────────────────────────────────────────────────────────────
-- 6. Core-exercise blocklist check
-- ───────────────────────────────────────────────────────────────────────────

DROP FUNCTION IF EXISTS _correction_is_core_exercise(TEXT);

CREATE OR REPLACE FUNCTION _correction_is_core_exercise(p_exercise_name TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_lname TEXT := LOWER(COALESCE(p_exercise_name, ''));
    v_hit   INTEGER;
BEGIN
    SELECT count(*) INTO v_hit
      FROM catalog_core_exercises
     WHERE v_lname ILIKE name_pattern;
    RETURN v_hit > 0;
END;
$$;

REVOKE EXECUTE ON FUNCTION _correction_is_core_exercise(TEXT) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION _correction_is_core_exercise(TEXT) TO service_role;

-- ───────────────────────────────────────────────────────────────────────────
-- 7. Drop the old apply_exercise_correction RPC and rebuild with operation
--    + corroboration gates. The new contract: every correction MUST be
--    proposed via `propose_exercise_correction` (below). The internal
--    `apply_exercise_correction` is now SECURITY DEFINER service-role-only
--    AND requires a corroboration gate to pass before applying. There is
--    no "force apply" path. (If you need one, add a separate RPC with a
--    very explicit name like `admin_force_apply_correction` and a 2FA
--    audit. Do not weaken this one.)
-- ───────────────────────────────────────────────────────────────────────────

DROP FUNCTION IF EXISTS apply_exercise_correction(UUID, TEXT, JSONB, NUMERIC, TEXT, UUID);
DROP FUNCTION IF EXISTS apply_exercise_correction(UUID, TEXT, TEXT, JSONB, NUMERIC, TEXT, UUID);

CREATE OR REPLACE FUNCTION apply_exercise_correction(
    p_exercise_id      UUID,
    p_field_name       TEXT,
    p_operation        TEXT,
    p_new_value        JSONB,
    p_confidence       NUMERIC,
    p_evidence         TEXT,
    p_source_report_id UUID DEFAULT NULL,
    p_corroboration_kind TEXT DEFAULT NULL    -- 'sister'|'name'|'multi_report'
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
    v_existing_array  TEXT[];
    v_remove_array    TEXT[];
    v_correction_id   UUID;
BEGIN
    -- Service role only.
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

    -- Operation/field compatibility.
    IF p_field_name IN ('primary_muscles','secondary_muscles') AND p_operation = 'set' THEN
        RAISE EXCEPTION 'set on muscle arrays is not auto-appliable; use add/remove' USING ERRCODE = '23514';
    END IF;
    IF p_field_name NOT IN ('primary_muscles','secondary_muscles') AND p_operation <> 'set' THEN
        RAISE EXCEPTION 'scalar field % only supports operation=set', p_field_name USING ERRCODE = '23514';
    END IF;

    -- Corroboration gate is REQUIRED. The caller (propose_exercise_correction
    -- or admin force path) is responsible for confirming a gate passes
    -- BEFORE calling this function. We trust the marker but never apply
    -- without one.
    IF p_corroboration_kind IS NULL OR
       p_corroboration_kind NOT IN ('sister','name','multi_report') THEN
        RAISE EXCEPTION 'No corroboration gate (sister/name/multi_report) supplied — refusing to apply'
            USING ERRCODE = '42501';
    END IF;

    SELECT name INTO v_exercise_name FROM exercises WHERE id = p_exercise_id;
    IF v_exercise_name IS NULL THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'exercise_not_found');
    END IF;

    -- Core-exercise removal lockout (safety net).
    IF p_operation = 'remove' AND _correction_is_core_exercise(v_exercise_name) THEN
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

    -- Append-only audit row.
    IF v_corrected THEN
        INSERT INTO exercise_corrections (
            exercise_id, exercise_name, field_name,
            previous_value, new_value, evidence, confidence, source_report_id
        ) VALUES (
            p_exercise_id, v_exercise_name, p_field_name,
            v_previous_value, p_new_value, p_evidence || ' [' || p_corroboration_kind || ']',
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
        'new_value', p_new_value,
        'correction_id', v_correction_id
    );
END;
$$;

REVOKE EXECUTE ON FUNCTION apply_exercise_correction(UUID, TEXT, TEXT, JSONB, NUMERIC, TEXT, UUID, TEXT) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION apply_exercise_correction(UUID, TEXT, TEXT, JSONB, NUMERIC, TEXT, UUID, TEXT) TO service_role;

COMMENT ON FUNCTION apply_exercise_correction(UUID, TEXT, TEXT, JSONB, NUMERIC, TEXT, UUID, TEXT) IS
    'Service-role only. REQUIRES p_corroboration_kind ∈ {sister,name,multi_report} — refuses to apply without one. Callers MUST verify the gate passes before invoking; this function trusts the marker. Removals against core canonical exercises are blocked regardless of corroboration.';

-- ───────────────────────────────────────────────────────────────────────────
-- 8. propose_exercise_correction — public-facing RPC the edge function calls
--    Inserts a proposal row, runs all 3 gates, and auto-applies if any
--    gate passes (and confidence=1.0, and the destructive-operation
--    threshold for removals is met).
-- ───────────────────────────────────────────────────────────────────────────

DROP FUNCTION IF EXISTS propose_exercise_correction(UUID, TEXT, TEXT, JSONB, NUMERIC, TEXT, UUID);

CREATE OR REPLACE FUNCTION propose_exercise_correction(
    p_exercise_id      UUID,
    p_field_name       TEXT,
    p_operation        TEXT,
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
    v_exercise_name TEXT;
    v_proposal_id   UUID;
    v_sister        BOOLEAN;
    v_name          BOOLEAN;
    v_multi         INTEGER;
    v_kind          TEXT;
    v_apply_result  JSONB;
    v_required_multi INTEGER;
    v_is_core       BOOLEAN;
BEGIN
    -- Service role only.
    IF auth.uid() IS NOT NULL THEN
        RAISE EXCEPTION 'propose_exercise_correction is service-role only'
            USING ERRCODE = '42501';
    END IF;

    SELECT name INTO v_exercise_name FROM exercises WHERE id = p_exercise_id;
    IF v_exercise_name IS NULL THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'exercise_not_found');
    END IF;

    -- Sanity: confidence must be in (0,1].
    IF p_confidence IS NULL OR p_confidence <= 0 OR p_confidence > 1 THEN
        RAISE EXCEPTION 'confidence must be in (0,1] (got %)', p_confidence
            USING ERRCODE = '23514';
    END IF;

    -- 1. Insert the proposal row first (always — even if it'll auto-apply
    --    in the next breath. We want every Claude proposal in the audit
    --    trail).
    INSERT INTO exercise_correction_proposals (
        exercise_id, exercise_name, field_name, operation,
        proposed_value, evidence, confidence, source_report_id,
        multi_report_count   -- includes self
    ) VALUES (
        p_exercise_id, v_exercise_name, p_field_name, p_operation,
        p_new_value, p_evidence, p_confidence, p_source_report_id,
        1
    )
    RETURNING id INTO v_proposal_id;

    -- 2. Compute corroboration evidence (now that this proposal is in
    --    the table — multi_report counts include the row we just wrote).
    v_sister := _correction_sister_gate(p_exercise_id, p_field_name, p_operation, p_new_value);
    v_name   := _correction_name_gate(v_exercise_name, p_field_name, p_operation, p_new_value);
    v_multi  := _correction_multi_report_count(p_exercise_id, p_field_name, p_operation, p_new_value);
    v_is_core := _correction_is_core_exercise(v_exercise_name);

    UPDATE exercise_correction_proposals
       SET sister_corroborated = v_sister,
           name_corroborated   = v_name,
           multi_report_count  = v_multi
     WHERE id = v_proposal_id;

    -- 3. Decide whether to auto-apply.
    -- Confidence 1.0 is required for any auto-apply.
    IF p_confidence < 1.0 THEN
        RETURN jsonb_build_object(
            'success', TRUE,
            'proposal_id', v_proposal_id,
            'auto_applied', FALSE,
            'reason', 'confidence_below_1',
            'sister_corroborated', v_sister,
            'name_corroborated', v_name,
            'multi_report_count', v_multi
        );
    END IF;

    -- Removal needs ≥3 multi-report AND core-exercise lockout NOT hit.
    IF p_operation = 'remove' THEN
        v_required_multi := 3;
        IF v_is_core THEN
            UPDATE exercise_correction_proposals
               SET status = 'blocked_core_exercise',
                   rejected_reason = 'core_exercise_removal_blocked',
                   decided_at = NOW()
             WHERE id = v_proposal_id;
            RETURN jsonb_build_object(
                'success', TRUE,
                'proposal_id', v_proposal_id,
                'auto_applied', FALSE,
                'reason', 'core_exercise_removal_blocked'
            );
        END IF;
        IF v_multi < v_required_multi AND NOT v_sister THEN
            RETURN jsonb_build_object(
                'success', TRUE,
                'proposal_id', v_proposal_id,
                'auto_applied', FALSE,
                'reason', 'remove_needs_3_reports_or_sister_disagreement',
                'multi_report_count', v_multi,
                'sister_corroborated', v_sister
            );
        END IF;
    END IF;

    -- Pick the corroboration kind (priority: sister > name > multi).
    IF v_sister THEN
        v_kind := 'sister';
    ELSIF v_name THEN
        v_kind := 'name';
    ELSIF v_multi >= 2 OR (p_operation = 'remove' AND v_multi >= 3) THEN
        v_kind := 'multi_report';
    ELSE
        RETURN jsonb_build_object(
            'success', TRUE,
            'proposal_id', v_proposal_id,
            'auto_applied', FALSE,
            'reason', 'no_gate_passed',
            'sister_corroborated', v_sister,
            'name_corroborated', v_name,
            'multi_report_count', v_multi
        );
    END IF;

    -- 4. Auto-apply.
    BEGIN
        v_apply_result := apply_exercise_correction(
            p_exercise_id, p_field_name, p_operation, p_new_value,
            p_confidence, p_evidence, p_source_report_id, v_kind
        );

        UPDATE exercise_correction_proposals
           SET status = 'applied',
               applied_correction_id = (v_apply_result->>'correction_id')::UUID,
               decided_at = NOW()
         WHERE id = v_proposal_id;

        RETURN jsonb_build_object(
            'success', TRUE,
            'proposal_id', v_proposal_id,
            'auto_applied', TRUE,
            'corroboration_kind', v_kind,
            'apply_result', v_apply_result
        );
    EXCEPTION WHEN OTHERS THEN
        -- Apply failed for some unexpected reason. Mark proposal failed
        -- so it stays out of the queue for retry.
        UPDATE exercise_correction_proposals
           SET status = 'rejected',
               rejected_reason = 'apply_failed: ' || LEFT(SQLERRM, 200),
               decided_at = NOW()
         WHERE id = v_proposal_id;
        RETURN jsonb_build_object(
            'success', FALSE,
            'proposal_id', v_proposal_id,
            'auto_applied', FALSE,
            'error', SQLERRM
        );
    END;
END;
$$;

REVOKE EXECUTE ON FUNCTION propose_exercise_correction(UUID, TEXT, TEXT, JSONB, NUMERIC, TEXT, UUID) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION propose_exercise_correction(UUID, TEXT, TEXT, JSONB, NUMERIC, TEXT, UUID) TO service_role;

COMMENT ON FUNCTION propose_exercise_correction(UUID, TEXT, TEXT, JSONB, NUMERIC, TEXT, UUID) IS
    'Public-facing correction RPC. Always inserts a proposal row, then auto-applies if confidence=1.0 AND a deterministic gate passes (sister/name/multi_report). Removals require ≥3 multi-report AND not-a-core-exercise. Edge function calls this; never apply_exercise_correction directly.';

-- ───────────────────────────────────────────────────────────────────────────
-- 9. promote_corroborated_proposals — cron-callable sweep
--    Re-checks pending proposals (which may have been alone-in-the-table
--    when proposed but now have ≥2 sibling reports). Auto-promotes any
--    that newly pass a gate. Bounded per-run so a single cron tick can't
--    blow up.
-- ───────────────────────────────────────────────────────────────────────────

DROP FUNCTION IF EXISTS promote_corroborated_proposals(INTEGER);

CREATE OR REPLACE FUNCTION promote_corroborated_proposals(p_max INTEGER DEFAULT 100)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_promoted INTEGER := 0;
    v_skipped  INTEGER := 0;
    v_failed   INTEGER := 0;
    r RECORD;
    v_kind TEXT;
    v_required_multi INTEGER;
    v_apply_result JSONB;
BEGIN
    IF auth.uid() IS NOT NULL THEN
        RAISE EXCEPTION 'promote_corroborated_proposals is service-role / cron only'
            USING ERRCODE = '42501';
    END IF;

    FOR r IN
        SELECT *
          FROM exercise_correction_proposals
         WHERE status = 'pending'
           AND confidence = 1.0
         ORDER BY proposed_at ASC
         LIMIT p_max
    LOOP
        -- Re-evaluate gates.
        UPDATE exercise_correction_proposals
           SET sister_corroborated = _correction_sister_gate(r.exercise_id, r.field_name, r.operation, r.proposed_value),
               name_corroborated   = _correction_name_gate(r.exercise_name, r.field_name, r.operation, r.proposed_value),
               multi_report_count  = _correction_multi_report_count(r.exercise_id, r.field_name, r.operation, r.proposed_value)
         WHERE id = r.id
        RETURNING sister_corroborated, name_corroborated, multi_report_count INTO r.sister_corroborated, r.name_corroborated, r.multi_report_count;

        v_required_multi := CASE WHEN r.operation = 'remove' THEN 3 ELSE 2 END;

        -- Core-exercise lockout for removals.
        IF r.operation = 'remove' AND _correction_is_core_exercise(r.exercise_name) THEN
            UPDATE exercise_correction_proposals
               SET status = 'blocked_core_exercise',
                   rejected_reason = 'core_exercise_removal_blocked',
                   decided_at = NOW()
             WHERE id = r.id;
            v_skipped := v_skipped + 1;
            CONTINUE;
        END IF;

        IF r.sister_corroborated THEN
            v_kind := 'sister';
        ELSIF r.name_corroborated THEN
            v_kind := 'name';
        ELSIF r.multi_report_count >= v_required_multi THEN
            v_kind := 'multi_report';
        ELSE
            v_skipped := v_skipped + 1;
            CONTINUE;
        END IF;

        BEGIN
            v_apply_result := apply_exercise_correction(
                r.exercise_id, r.field_name, r.operation, r.proposed_value,
                r.confidence, r.evidence, r.source_report_id, v_kind
            );
            UPDATE exercise_correction_proposals
               SET status = 'applied',
                   applied_correction_id = (v_apply_result->>'correction_id')::UUID,
                   decided_at = NOW()
             WHERE id = r.id;
            v_promoted := v_promoted + 1;
        EXCEPTION WHEN OTHERS THEN
            UPDATE exercise_correction_proposals
               SET status = 'rejected',
                   rejected_reason = 'apply_failed: ' || LEFT(SQLERRM, 200),
                   decided_at = NOW()
             WHERE id = r.id;
            v_failed := v_failed + 1;
        END;
    END LOOP;

    RETURN jsonb_build_object(
        'promoted', v_promoted,
        'skipped',  v_skipped,
        'failed',   v_failed
    );
END;
$$;

REVOKE EXECUTE ON FUNCTION promote_corroborated_proposals(INTEGER) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION promote_corroborated_proposals(INTEGER) TO service_role;

COMMENT ON FUNCTION promote_corroborated_proposals(INTEGER) IS
    'Nightly cron entry point. Re-evaluates corroboration gates on every pending confidence=1.0 proposal and auto-applies any that newly pass. Bounded by p_max (default 100/run).';

-- ───────────────────────────────────────────────────────────────────────────
-- 10. Trailing fail-loud audit
-- ───────────────────────────────────────────────────────────────────────────

DO $$
BEGIN
    PERFORM 1 FROM information_schema.tables WHERE table_name = 'exercise_correction_proposals';
    IF NOT FOUND THEN RAISE EXCEPTION 'exercise_correction_proposals missing'; END IF;

    PERFORM 1 FROM information_schema.tables WHERE table_name = 'catalog_core_exercises';
    IF NOT FOUND THEN RAISE EXCEPTION 'catalog_core_exercises missing'; END IF;

    PERFORM 1 FROM pg_proc WHERE proname = '_correction_sister_gate';
    IF NOT FOUND THEN RAISE EXCEPTION '_correction_sister_gate missing'; END IF;
    PERFORM 1 FROM pg_proc WHERE proname = '_correction_name_gate';
    IF NOT FOUND THEN RAISE EXCEPTION '_correction_name_gate missing'; END IF;
    PERFORM 1 FROM pg_proc WHERE proname = '_correction_multi_report_count';
    IF NOT FOUND THEN RAISE EXCEPTION '_correction_multi_report_count missing'; END IF;
    PERFORM 1 FROM pg_proc WHERE proname = '_correction_is_core_exercise';
    IF NOT FOUND THEN RAISE EXCEPTION '_correction_is_core_exercise missing'; END IF;

    -- The new apply_exercise_correction must take 8 args (operation +
    -- corroboration_kind added). Refuse to deploy if the old 6-arg
    -- form is still around.
    IF EXISTS (
        SELECT 1 FROM pg_proc p
        JOIN pg_namespace n ON p.pronamespace = n.oid
        WHERE n.nspname = 'public'
          AND p.proname = 'apply_exercise_correction'
          AND pg_get_function_identity_arguments(p.oid) LIKE '%uuid, text, jsonb, numeric, text, uuid%'
          AND pg_get_function_identity_arguments(p.oid) NOT LIKE '%text, uuid, text%'
    ) THEN
        RAISE EXCEPTION 'OLD apply_exercise_correction signature still present — DROP did not take';
    END IF;

    PERFORM 1 FROM pg_proc WHERE proname = 'propose_exercise_correction';
    IF NOT FOUND THEN RAISE EXCEPTION 'propose_exercise_correction missing'; END IF;
    PERFORM 1 FROM pg_proc WHERE proname = 'promote_corroborated_proposals';
    IF NOT FOUND THEN RAISE EXCEPTION 'promote_corroborated_proposals missing'; END IF;

    RAISE NOTICE '✅ Migration #157 complete: corroboration ladder + removal path + proposals queue.';
END $$;

COMMIT;
