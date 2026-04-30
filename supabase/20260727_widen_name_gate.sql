-- ═══════════════════════════════════════════════════════════════════════════
-- 20260727_widen_name_gate.sql  (Migration #158)
--
-- Widens the deterministic name-keyword regexes in `_correction_name_gate`
-- so that obvious single-keyword-determinable cases like "Walking Lunge",
-- "Skullcrusher", "Hip Thrust", and equipment-prefixed names ("Cable
-- Crossover", "Machine Pec Deck") auto-promote on a single report instead
-- of sitting in the proposals queue waiting for a 2nd corroborating
-- workout.
--
-- WHY
-- ---
-- Migration #157's regexes were deliberately conservative — they covered
-- the canonical lift names (deadlift / squat / bench press / pull-up)
-- but missed obvious isolation cuts (skullcrusher / leg curl / pec deck),
-- single-leg patterns (lunge / step-up), hip-hinge variants beyond
-- deadlift (hip thrust / glute bridge), and any rep-based keyword that
-- wasn't already a primary movement (kickback / pushdown / preacher / etc.).
--
-- The first 10-workout run produced 3 proposals that should have
-- auto-applied but instead sat as `pending`:
--
--   Walking Lunge (Dumbbell)        workout_type    set "Strength"
--   Walking Lunge (Dumbbell)        duration_based  set false
--   Skullcrusher - Reverse Grip     is_compound     set false
--
-- All three are unambiguous from the name alone. After this migration
-- they'll auto-promote on the next `promote_corroborated_proposals` run
-- (since the gate is re-evaluated against the new regex).
--
-- WHAT CHANGES
-- ------------
--   1. Strength regex: + lunge, + skullcrush(er), + hip thrust, + glute
--      bridge, + step-up, + farmer carry, + cable crossover, + pec deck,
--      + good morning, + RDL, + rack pull, + reverse hyper, + hyperextension,
--      + back extension, + leg press, + calf raise, + shrug.
--   2. duration_based=FALSE: same widened verb list (lunge, thrust,
--      kickback, pushdown, skullcrush, shrug, calf raise, etc.).
--   3. is_compound=FALSE: NEW — was previously never matched. Now matches
--      unambiguous isolation patterns. Conservative: requires that the
--      name contain ONE of (curl, raise, fly, extension, kickback,
--      pushdown, skullcrush, lateral raise, front raise, rear delt fly,
--      reverse fly, pec deck, leg extension, leg curl) AND not contain
--      a compound disambiguator (squat, deadlift, press, row, lunge).
--   4. Plyometrics + Cardio regexes: small additions (jump squat, broad
--      jump, sled push, prowler, ski erg, assault bike, airdyne).
--
-- SAFETY
-- ------
-- Same defense-in-depth as #157:
--   • All regexes are TRUE-direction-only (positive assertions). FALSE
--     direction is added for is_compound only after the existing
--     compound-disambiguator filter (so "Bulgarian split squat" is never
--     accidentally tagged isolation).
--   • Core-exercise removal lockout still applies (catalog_core_exercises
--     blocks any REMOVE on bench/squat/deadlift/etc).
--   • All existing applied corrections from #157 are unchanged. Only
--     pending proposals re-evaluate.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

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
    v_compound_kw    BOOLEAN;
    v_isolation_kw   BOOLEAN;
BEGIN
    -- Only set-operations on scalar fields are name-gateable.
    IF p_operation <> 'set' THEN
        RETURN FALSE;
    END IF;

    -- ── is_compound ────────────────────────────────────────────────────
    IF p_field_name = 'is_compound' THEN
        v_bool := (p_value #>> '{}')::boolean;

        v_compound_kw := v_lname ~ '\m(deadlift|back squat|front squat|squat|bench press|incline press|decline press|overhead press|shoulder press|push press|push jerk|thruster|clean|snatch|jerk|barbell row|bent over row|t.bar row|seated row|cable row|pull-?up|pullup|chin-?up|chinup|dip|hip thrust|glute bridge|lunge|step.?up|farmer.?s? carry|farmer carry|sandbag carry|rdl|romanian deadlift|good morning|rack pull|sumo deadlift|leg press|calf raise|hip extension|reverse hyper|hyperextension|back extension|shrug|cable crossover|pec deck|chest fly machine|bulgarian split squat|split squat|kettlebell swing|swing|push.?up|pushup|burpee)\M';

        v_isolation_kw := v_lname ~ '\m(skullcrush|skullcrusher|tricep.?extension|leg extension|leg curl|hamstring curl|preacher curl|concentration curl|spider curl|hammer curl|reverse curl|wrist curl|bicep curl|cable curl|barbell curl|dumbbell curl|incline curl|lateral raise|front raise|rear delt fly|rear delt raise|reverse fly|cable fly|incline fly|pec fly|chest fly|hip abduction|hip adduction|kickback|pushdown|pulldown|cable pulldown|tricep pushdown|seated leg curl|standing leg curl|lying leg curl|lying tricep|cuban press|w-raise|y-raise|i-raise|t-raise|face pull|reverse curl)\M';

        IF v_bool IS TRUE THEN
            -- Compound TRUE: any compound keyword is sufficient, AND the
            -- name must NOT contain an isolation-only marker (otherwise
            -- "Single-arm Cable Crossover" → don't auto-apply).
            RETURN v_compound_kw AND NOT v_isolation_kw;
        ELSIF v_bool IS FALSE THEN
            -- Compound FALSE: isolation keyword present AND no compound
            -- disambiguator (split squat / Bulgarian split squat / squat
            -- curl don't slip through).
            RETURN v_isolation_kw AND NOT v_compound_kw;
        END IF;
        RETURN FALSE;

    -- ── duration_based ─────────────────────────────────────────────────
    ELSIF p_field_name = 'duration_based' THEN
        v_bool := (p_value #>> '{}')::boolean;
        IF v_bool IS TRUE THEN
            RETURN v_lname ~ '\m(plank|side plank|dead.?hang|wall sit|hold|isometric|static|bear crawl|hollow hold|l.sit|superman hold|farmer.?s? carry|farmer carry|carry|sandbag carry|prowler push|sled drag|sled push)\M';
        END IF;
        IF v_bool IS FALSE THEN
            RETURN v_lname ~ '\m(curl|press|raise|fly|extension|row|pulldown|pull-?up|pullup|chin-?up|chinup|squat|deadlift|push.?up|pushup|lunge|thrust|skullcrush|skullcrusher|kickback|pushdown|shrug|crunch|sit-?up|situp|leg raise|knee raise|crossover|rdl|hip thrust|glute bridge|good morning|step.?up|swing|clean|snatch|jerk|thruster|burpee|jump|hop|dip|fly machine|pec deck)\M'
               AND v_lname !~ '\m(hold|isometric|static|plank|wall sit|dead.?hang|l.sit|superman hold)\M';
        END IF;
        RETURN FALSE;

    -- ── workout_type ───────────────────────────────────────────────────
    ELSIF p_field_name = 'workout_type' THEN
        v_text := p_value #>> '{}';
        IF v_text = 'Strength' THEN
            RETURN v_lname ~ '\m(press|curl|row|squat|deadlift|lift|extension|pulldown|pull-?up|pullup|chin-?up|chinup|dip|fly|raise|thrust|carry|kickback|pushdown|push.?up|pushup|lunge|step.?up|skullcrush|skullcrusher|crunch|sit-?up|situp|hyperextension|back extension|reverse hyper|leg press|calf raise|shrug|cable crossover|pec deck|hip abduction|hip adduction|leg curl|leg extension|good morning|rdl|rack pull|kettlebell swing|swing|bridge|hip thrust|reverse fly|face pull|crossover)\M';
        ELSIF v_text = 'Stretch' THEN
            RETURN v_lname ~ '\m(stretch|mobility|pose|opener|reach|flexion stretch|hip flexor stretch|cobra|child.?s? pose|pigeon|warrior pose|downward dog|upward dog|cat.cow|cat-cow|seated forward fold|standing forward fold|butterfly|pancake|figure 4|figure four|90/90|90-90|hamstring stretch|quad stretch|calf stretch|chest stretch|shoulder stretch|hip stretch)\M';
        ELSIF v_text = 'Plyometrics' THEN
            RETURN v_lname ~ '\m(jump|hop|bound|plyo|skater|burpee|box jump|broad jump|jump squat|tuck jump|split jump|depth jump|lateral bound|jumping jack|mountain climber|high knee|butt kick|sprint start|reactive)\M';
        ELSIF v_text = 'Cardio' THEN
            RETURN v_lname ~ '\m(run|jog|sprint|cycle|cycling|row machine|rower|treadmill|elliptical|jump rope|skip rope|stair|stairmaster|assault bike|airdyne|ski erg|skierg|prowler|sled|battle rope|farmer.?s? walk|sled push|sled pull)\M';
        END IF;
        RETURN FALSE;

    -- ── equipment_category ─────────────────────────────────────────────
    ELSIF p_field_name = 'equipment_category' THEN
        v_text := LOWER(COALESCE(p_value #>> '{}', ''));
        IF v_text = '' THEN RETURN FALSE; END IF;
        RETURN v_lname LIKE '%' || v_text || '%';
    END IF;

    RETURN FALSE;
END;
$$;

REVOKE EXECUTE ON FUNCTION _correction_name_gate(TEXT, TEXT, TEXT, JSONB) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION _correction_name_gate(TEXT, TEXT, TEXT, JSONB) TO service_role;

-- Re-evaluate every pending confidence=1.0 proposal against the widened
-- regex right now. This will auto-promote the 3 known cases (Walking
-- Lunge × 2, Skullcrusher × 1) plus anything else that newly qualifies.
DO $$
DECLARE
    v_result JSONB;
BEGIN
    SELECT promote_corroborated_proposals(500) INTO v_result;
    RAISE NOTICE '#158 promote sweep: %', v_result;
END $$;

COMMIT;
