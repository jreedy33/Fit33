import Foundation

// ═══════════════════════════════════════════════════════════════════════════════
// WORKOUT COMBO RULES ENGINE
// ═══════════════════════════════════════════════════════════════════════════════
// Explicit generator rules by muscle combo to prevent weird/risky/redundant workouts.
// These rules match the flow: Duration → Primary muscle(s) → Focus areas → Equipment → Generate
//
// UI Flow: Duration → Main Groups (Chest/Back/Shoulders/Arms/Legs/Core) → Focus Chips → Equipment → Generate
//
// Key Concepts:
// 1. Slot Allocation - How many exercises per selected group
// 2. Pattern Requirements - What a "good" workout for each group must contain
// 3. Focus-Area Mapping - What "Upper Chest" means in exercise selection
// 4. Anti-Weirdness Guardrails - No redundant presses, no low-back stacking, etc.
//
// SYNCED WITH: scripts/workout_combo_rules.py
// ═══════════════════════════════════════════════════════════════════════════════

// MARK: - UI Structure

/// Main groups in the UI
let uiMainGroups = ["chest", "back", "shoulders", "arms", "legs", "core"]

/// Focus chips by main group
let uiFocusChips: [String: [String]] = [
    "chest": ["upper_chest", "lower_chest", "inner_chest", "outer_chest"],
    "back": ["lats", "traps", "upper_back", "lower_back"],
    "shoulders": ["front_delts", "side_delts", "rear_delts"],
    "arms": ["biceps", "triceps", "forearms"],
    "legs": ["quadriceps", "hamstrings", "glutes", "calves", "hip_flexors"],
    "core": ["upper_abs", "lower_abs", "obliques"],
]

// MARK: - Slot Allocation

/// Calculate how many exercise slots each selected group gets
func calculateSlotAllocation(selectedGroups: [String], exerciseCount: Int) -> [String: Int] {
    var allocation: [String: Int] = [:]
    let numGroups = selectedGroups.count
    
    if numGroups == 0 {
        return allocation
    }
    
    if numGroups == 1 {
        // E-1 for the group, 1 for balance
        allocation[selectedGroups[0]] = exerciseCount - 1
        allocation["_balance"] = 1
    } else if numGroups == 2 {
        // Split evenly, extra goes to balance
        let basePerGroup = exerciseCount / 2
        let remainder = exerciseCount % 2
        
        allocation[selectedGroups[0]] = basePerGroup
        allocation[selectedGroups[1]] = basePerGroup
        
        if remainder > 0 {
            allocation["_balance"] = remainder
        }
    } else {
        // 3+ groups - full body quick hit
        // Guarantee 1 per group, fill remaining with compound staples
        for group in selectedGroups {
            allocation[group] = 1
        }
        
        let remaining = exerciseCount - numGroups
        if remaining > 0 {
            allocation["_compound_staples"] = remaining
        }
    }
    
    return allocation
}

// MARK: - Scoring Hints

struct ScoringHints {
    static let focusMatchBonus = 80
    static let primaryGroupMatchBonus = 60
    static let secondaryGroupMatchBonus = 30
    static let foundationalMachineBonus = 40
    static let supportedRowBonusWhenBackCaution = 60
    static let equipmentSwitchPenalty = -15
    /// Audit 2026-05-08 hardening: was -50, but the 20-user audit still showed
    /// "two plank variations" / "three pull-up variations" reaching the user.
    /// Bumped to -120 so that adding a 3rd same-pattern variant is effectively
    /// disqualifying. The diversity cap in `SmartExercisePairingEngine` provides
    /// the hard ceiling; this is the soft tiebreaker.
    static let redundancyPenaltyPerExtraVariant = -120

    /// Audit 2026-05-08 Round 3 hardening (50 users / 100 workouts —
    /// `scripts/output/autogen_audit_20260508_124852.md`):
    /// `redundant_movement_pattern` was the #1 issue category (100 hits) with
    /// multiple workouts shipping 4 decline-chest moves stacked together.
    /// Bigger than `redundancyPenaltyPerExtraVariant` because angle stacking
    /// (4 declines, 4 inclines, 3 horizontal pulls) is a worse defect than
    /// generic same-pattern repeats — it concentrates load on one shoulder-
    /// girdle position and skips the rest of the muscle. The hard ceiling is
    /// `WorkoutComboRules.maxPerAngle = 2`; this score penalty is the
    /// tiebreaker for cases where a higher-priority candidate sneaks past
    /// the cap (e.g. a focus-area pin overrides the filter).
    static let angleStackingPenalty = -300
}

// MARK: - Global Rules

/// Exercise count by duration - GLOBAL RULE #1
///
/// Audit 2026-05-08 (fix #14 — Increase exercise count for advanced muscle building):
/// Optional `experienceLevel` and `goal` parameters allow the autogen to bump the count
/// by 1 for Advanced + Build Muscle when duration >= 50 min — advanced lifters need
/// more total volume than 6 exercises to adequately stimulate hypertrophy. Defaults are
/// backwards-compatible: existing callers see identical behavior.
func getExerciseCountForDuration(
    _ durationMinutes: Int,
    equipmentIsMostlyMachines: Bool = false,
    experienceLevel: String = "",
    goal: String = ""
) -> Int {
    // - 20 min: 4 moves
    // - 30 min: 5 moves
    // - 40-50 min: 6 moves (7 max only if mostly machines/cables)

    let baseCount: Int
    if durationMinutes <= 20 {
        baseCount = 4
    } else if durationMinutes <= 30 {
        baseCount = 5
    } else if durationMinutes <= 50 {
        // 7 only if mostly machines/cables (faster transitions)
        baseCount = equipmentIsMostlyMachines ? 7 : 6
    } else {
        baseCount = 8  // Hard cap for 60+ min
    }

    // Advanced + Build Muscle bump (audit 2026-05-08).
    // Only trigger for sessions of 50+ min — shorter sessions don't have time
    // for an extra exercise without compromising rest periods.
    let levelLower = experienceLevel.lowercased()
    let goalLower = goal.lowercased()
    let isAdvanced = levelLower.contains("advanced")
    let isBuildMuscle = goalLower.contains("muscle") || goalLower.contains("hypertrophy")
    if durationMinutes >= 50 && isAdvanced && isBuildMuscle {
        // Add 1 but never exceed 9 total — past 9, programming becomes counterproductive.
        return min(baseCount + 1, 9)
    }

    return baseCount
}

/// Global redundancy caps
struct GlobalCaps {
    static let press = 2           // Max 2 presses per workout (unless chest only)
    static let row = 2             // Max 2 rows per workout (one should be supported if both)
    static let hinge = 1           // Max 1 hinge per workout (deadlift/RDL/back extension family)
    static let curl = 2            // Max 2 curls unless arms day
    static let tricepExtension = 2 // Max 2 tricep moves unless arms day
    static let shrug = 1           // Max 1 shrug variation
    static let backExtension = 1   // Only 1 back extension
}

// MARK: - Angle Stacking Cap (Audit 2026-05-08 fix #2 — angle stacking)
//
// Round 3 50-user/100-workout audit (`scripts/output/autogen_audit_20260508_124852.md`)
// flagged `redundant_movement_pattern` as the #1-frequency residual issue (100 hits).
// Multiple workouts had 4 decline-chest exercises stacked together (user-15, user-26).
// Same angle = same shoulder-girdle position = same fiber recruitment bias; stacking
// 4 of them is a programming defect — the angle cap (= 2) is the corrective hard
// ceiling. The granular `SmartExercisePairingEngine.movementPatternRepeatCap`
// catches generic same-pattern stacks; this catches angled-press/pull stacks where
// the underlying movement pattern differs but the angle (and BP/postural load) is
// identical.

// MARK: - Combo Rule Definition

/// Defines rules for a specific muscle combination
struct ComboRule {
    let comboName: String
    let mustInclude: [String]      // Exercise patterns that MUST be included
    let avoid: [String]            // Exercise patterns to AVOID
    let caps: [String: Int]        // Override global caps for this combo
    let balanceSlot: String?       // Auto-add this for balance
    let focusOverrides: [String: [String]]  // Focus area → preferred exercises
    let notes: String
    
    init(comboName: String,
         mustInclude: [String] = [],
         avoid: [String] = [],
         caps: [String: Int] = [:],
         balanceSlot: String? = nil,
         focusOverrides: [String: [String]] = [:],
         notes: String = "") {
        self.comboName = comboName
        self.mustInclude = mustInclude
        self.avoid = avoid
        self.caps = caps
        self.balanceSlot = balanceSlot
        self.focusOverrides = focusOverrides
        self.notes = notes
    }
}

// MARK: - Combo Rules Database

enum WorkoutComboRules {
    
    // MARK: - Combo Definitions
    
    static let chestShoulders = ComboRule(
        comboName: "Chest + Shoulders",
        mustInclude: ["chest_press", "shoulder_press", "lateral_raise", "chest_accessory"],
        avoid: ["front_raise", "upright_row", "high_pull"],
        caps: ["press": 2, "overhead_press": 1],
        balanceSlot: "rear_delt",
        focusOverrides: [
            "upper_chest": ["incline_press", "low_to_high_fly"],
            "lower_chest": ["decline_press", "dip", "high_to_low_fly"],
            "front_delts": ["shoulder_press"],
            "side_delts": ["lateral_raise"]
        ],
        notes: "If shoulder limitation → neutral grip presses + no dips"
    )
    
    static let chestTriceps = ComboRule(
        comboName: "Chest + Triceps",
        mustInclude: ["chest_press", "chest_secondary", "tricep_isolation"],
        avoid: ["dip_close_grip_heavy_bench_combo", "bench_dip"],
        caps: ["tricep_extension": 2, "dip": 1],
        focusOverrides: [
            "lower_chest": ["decline_press"]  // Dips or decline, not both
        ],
        notes: "If lower chest focus → dips OR decline press, not both"
    )
    
    static let shouldersTriceps = ComboRule(
        comboName: "Shoulders + Triceps",
        mustInclude: ["shoulder_press", "lateral_raise", "rear_delt", "tricep_isolation"],
        avoid: ["upright_row"],
        caps: ["overhead_press": 1]
    )
    
    static let backBiceps = ComboRule(
        comboName: "Back + Biceps",
        mustInclude: ["vertical_pull", "horizontal_row", "bicep_curl", "rear_delt"],
        avoid: ["deadlift_row_extension_combo"],
        caps: ["curl": 2, "hinge": 1],
        balanceSlot: "rear_delt",
        notes: "If 6 moves: back gets 4, biceps gets 1-2. Rear delt (face pull/reverse fly) is MANDATORY for balance."
    )
    
    static let backRearDelts = ComboRule(
        comboName: "Back + Rear Delts",
        mustInclude: ["vertical_pull", "horizontal_row", "rear_delt"],
        avoid: ["multiple_spinal_extension"],
        caps: ["back_extension": 1, "hinge": 1],
        notes: "Don't turn into deadlift day unless user requested strength"
    )
    
    static let backTraps = ComboRule(
        comboName: "Back + Traps",
        mustInclude: ["horizontal_row", "vertical_pull", "shrug"],
        avoid: ["shrug_deadlift_extension_combo"],
        caps: ["shrug": 1, "hinge": 1, "back_extension": 1]
    )
    
    static let arms = ComboRule(
        comboName: "Arms (Biceps + Triceps)",
        mustInclude: ["bicep_supinated", "bicep_neutral", "tricep_pressdown", "tricep_overhead"],
        avoid: ["behind_back_dip"],
        caps: ["curl": 3, "tricep_extension": 3],
        notes: "If time is short: 4 moves total (B1, B2, T1, T2)"
    )
    
    static let legsQuadsGlutes = ComboRule(
        comboName: "Legs (Quads + Glutes)",
        mustInclude: ["squat_pattern", "unilateral_leg", "glute_accessory", "leg_curl"],
        avoid: ["upper_body_press", "plyo_default"],
        caps: ["press": 0],
        balanceSlot: "core_stability",
        notes: "Kickbacks live in 12-20 reps; leg curl ensures hamstring balance"
    )
    
    static let quadsHamstrings = ComboRule(
        comboName: "Quads + Hamstrings",
        mustInclude: ["quad_compound", "leg_curl"],  // Leg curl is MANDATORY
        avoid: ["quads_only", "heavy_compounds_plyo"],
        caps: ["hinge": 1],
        notes: "Leg curl is MANDATORY for hamstring work"
    )
    
    static let glutesHamstrings = ComboRule(
        comboName: "Glutes + Hamstrings",
        mustInclude: ["hinge_or_hip_thrust", "leg_curl", "glute_isolation"],
        avoid: ["squat_default"],
        caps: ["squat": 0]  // Avoid squats unless explicitly requested
    )
    
    static let legsCalves = ComboRule(
        comboName: "Legs + Calves",
        mustInclude: ["quad_movement", "posterior_leg", "calf_movement"],
        avoid: ["calves_only"]
    )
    
    static let coreAbs = ComboRule(
        comboName: "Core + Abs",
        mustInclude: ["anti_rotation", "anti_extension", "flexion"],
        avoid: ["hanging_pike_default", "plyo_core"],
        caps: ["exercise_count": 5],
        notes: "Optional carry if time allows"
    )
    
    // MARK: - NEW Combo Rules (from JSON spec)
    
    static let chestBack = ComboRule(
        comboName: "Chest + Back",
        mustInclude: ["chest_press", "chest_fly_or_secondary", "vertical_pull", "horizontal_row", "rear_delt_or_face_pull"],
        avoid: ["deadlift_unless_lower_back_focus"],
        caps: ["press": 2, "row": 2],
        notes: "Don't include deadlift unless user explicitly selected Lower Back focus (and has no back limitation)"
    )
    
    static let backShoulders = ComboRule(
        comboName: "Back + Shoulders",
        mustInclude: ["vertical_pull", "supported_row", "shoulder_press", "lateral_raise", "rear_delt_or_face_pull"],
        avoid: ["shrug_high_pull_stack", "unsupported_rows_if_back_caution"],
        caps: ["overhead_press": 1, "row": 2],
        notes: "Keep low back calm - supported rows > bent-over"
    )
    
    static let shouldersArms = ComboRule(
        comboName: "Shoulders + Arms",
        mustInclude: ["shoulder_press", "lateral_raise", "rear_delt_or_face_pull", "biceps_curl", "triceps_isolation"],
        avoid: ["upright_row", "two_overhead_presses"],
        caps: ["overhead_press": 1, "curl": 2, "tricep_extension": 2]
    )
    
    static let legsCore = ComboRule(
        comboName: "Legs + Core",
        mustInclude: ["quad_compound", "ham_or_glute", "unilateral_leg", "core_anti_rotation", "core_flexion_or_anti_extension"],
        avoid: ["plyo_defaults", "impact_core_defaults"],
        caps: ["press": 0],
        notes: "Core moves should not be 'impact' by default (no plank hops unless user is advanced)"
    )
    
    static let armsCore = ComboRule(
        comboName: "Arms + Core",
        mustInclude: ["biceps_1", "biceps_2", "triceps_1", "triceps_2", "core_stability"],
        avoid: ["combo_core_pushup_circus"],
        notes: "Core = stability, not combo push-up plank circus"
    )
    
    // MARK: - Standalone Single-Group Rules (Bro Split)
    
    static let shouldersOnly = ComboRule(
        comboName: "Shoulders",
        mustInclude: ["shoulder_press", "lateral_raise", "rear_delt"],
        avoid: ["front_raise"],
        caps: ["overhead_press": 1],
        balanceSlot: "rear_delt",
        notes: "Front delts hit enough from pressing; ensure rear delt coverage"
    )
    
    static let chestOnly = ComboRule(
        comboName: "Chest",
        mustInclude: ["horizontal_press", "incline_press", "chest_fly"],
        avoid: ["decline_press_default"],
        caps: ["flat_press": 2],
        balanceSlot: "rear_delt",
        notes: "Mix flat + incline presses with a fly for stretch"
    )
    
    static let backOnly = ComboRule(
        comboName: "Back",
        mustInclude: ["horizontal_pull", "vertical_pull", "rear_delt"],
        avoid: [],
        caps: ["row": 2, "pulldown": 2],
        balanceSlot: "rotator_cuff",
        notes: "Horizontal and vertical pull with rear delt finisher"
    )
    
    static let legsOnly = ComboRule(
        comboName: "Legs",
        mustInclude: ["squat_pattern", "leg_curl", "unilateral_leg", "calf_raise"],
        avoid: ["upper_body_press"],
        caps: ["press": 0],
        balanceSlot: "core_stability",
        notes: "Quad + hamstring + calf for full leg coverage"
    )
    
    static let fullBody = ComboRule(
        comboName: "Full Body",
        mustInclude: ["lower_squat_press", "hinge_or_ham_curl", "push", "pull", "core"],
        avoid: ["legs_only_full_body", "novelty_combos", "advanced_plyo_default"]
    )
    
    // MARK: - Combo Detection
    
    /// Detect which combo rule applies based on target muscles
    static func detectWorkoutCombo(_ targetMuscles: [String]) -> String? {
        let targetsLower = Set(targetMuscles.map { $0.lowercased() })
        
        let hasChest = targetsLower.contains { $0.contains("chest") || $0.contains("pec") }
        let hasShoulders = targetsLower.contains { $0.contains("shoulder") || $0.contains("delt") }
        let hasTriceps = targetsLower.contains { $0.contains("tricep") }
        let hasBiceps = targetsLower.contains { $0.contains("bicep") }
        let hasBack = targetsLower.contains { $0.contains("back") || $0.contains("lat") }
        let hasTraps = targetsLower.contains { $0.contains("trap") }
        let hasRearDelts = targetsLower.contains { $0.contains("rear delt") || $0.contains("rear_delt") }
        let hasQuads = targetsLower.contains { $0.contains("quad") || $0.contains("leg") }
        let hasHamstrings = targetsLower.contains { $0.contains("ham") }
        let hasGlutes = targetsLower.contains { $0.contains("glute") }
        let hasCalves = targetsLower.contains { $0.contains("calf") || $0.contains("calves") }
        let hasCore = targetsLower.contains { $0.contains("core") || $0.contains("abs") }
        let hasArms = targetsLower.contains { $0.contains("arm") }
        let hasLegs = hasQuads || hasHamstrings || hasGlutes
        
        // Match combos in priority order (more specific combos first)
        
        // Two-group combinations
        if hasChest && hasShoulders { return "chest_shoulders" }
        if hasChest && hasBack { return "chest_back" }
        if hasChest && hasTriceps { return "chest_triceps" }
        if hasBack && hasShoulders { return "back_shoulders" }
        if hasBack && hasBiceps { return "back_biceps" }
        if hasShoulders && hasTriceps { return "shoulders_triceps" }
        if hasShoulders && (hasArms || (hasBiceps && hasTriceps)) { return "shoulders_arms" }
        if hasBack && hasRearDelts { return "back_rear_delts" }
        if hasBack && hasTraps { return "back_traps" }
        
        // Legs + Core
        if hasLegs && hasCore { return "legs_core" }
        
        // Arms + Core
        if (hasArms || (hasBiceps && hasTriceps)) && hasCore { return "arms_core" }
        
        // Pure arms
        if (hasBiceps && hasTriceps) || hasArms { return "arms" }
        
        // Leg combos
        if hasQuads && hasGlutes { return "legs_quads_glutes" }
        if hasQuads && hasHamstrings { return "quads_hamstrings" }
        if hasGlutes && hasHamstrings { return "glutes_hamstrings" }
        if hasLegs && hasCalves { return "legs_calves" }
        
        // Pure core
        if hasCore { return "core_abs" }
        
        // Check for full body (3+ groups)
        let hasUpper = hasChest || hasShoulders || hasBack
        let hasLower = hasQuads || hasHamstrings || hasGlutes
        if hasUpper && hasLower { return "full_body" }
        
        // Standalone single-group rules (Bro Split days)
        if hasChest { return "chest_only" }
        if hasBack { return "back_only" }
        if hasShoulders { return "shoulders_only" }
        if hasLegs { return "legs_only" }
        
        return nil
    }
    
    /// Get the combo rule for target muscles
    static func getComboRule(_ targetMuscles: [String]) -> ComboRule? {
        guard let comboKey = detectWorkoutCombo(targetMuscles) else { return nil }
        
        switch comboKey {
        case "chest_shoulders": return chestShoulders
        case "chest_back": return chestBack
        case "chest_triceps": return chestTriceps
        case "back_shoulders": return backShoulders
        case "back_biceps": return backBiceps
        case "back_rear_delts": return backRearDelts
        case "back_traps": return backTraps
        case "shoulders_triceps": return shouldersTriceps
        case "shoulders_arms": return shouldersArms
        case "arms": return arms
        case "legs_quads_glutes": return legsQuadsGlutes
        case "quads_hamstrings": return quadsHamstrings
        case "glutes_hamstrings": return glutesHamstrings
        case "legs_calves": return legsCalves
        case "legs_core": return legsCore
        case "arms_core": return armsCore
        case "core_abs": return coreAbs
        case "full_body": return fullBody
        case "shoulders_only": return shouldersOnly
        case "chest_only": return chestOnly
        case "back_only": return backOnly
        case "legs_only": return legsOnly
        default: return nil
        }
    }
    
    /// Get balance slot recommendation
    static func getBalanceSlot(_ targetMuscles: [String]) -> String? {
        let targetsLower = targetMuscles.map { $0.lowercased() }
        
        let isPush = targetsLower.contains { ["chest", "shoulders", "triceps"].contains(where: $0.contains) }
        let isPull = targetsLower.contains { ["back", "biceps", "lats"].contains(where: $0.contains) }
        let isLegs = targetsLower.contains { ["legs", "quads", "hamstrings", "glutes"].contains(where: $0.contains) }
        
        if isPush { return "rear_delt" }
        if isPull { return "rotator_cuff" }
        if isLegs { return "core_stability" }
        
        return nil
    }
    
    /// Detect exercise pattern for combo rule matching
    /// CRITICAL: Combo exercises (X to Y) return "combo" and do NOT satisfy any pattern requirement
    static func detectExercisePattern(_ exerciseName: String, equipment: String = "") -> String {
        let name = exerciseName.lowercased()
        
        // ═══════════════════════════════════════════════════════════════════════════
        // 🚫 CRITICAL: Combo exercises do NOT satisfy pattern requirements
        // "Reverse Fly to Hammer Curl" should NOT count as rear_delt OR bicep_curl
        // They're too complex to load/progress effectively for hypertrophy
        // ═══════════════════════════════════════════════════════════════════════════
        if name.contains(" to ") {
            let allowedToPatterns = ["low to high", "high to low", "low-to-high", "high-to-low"]
            let isAllowedPattern = allowedToPatterns.contains { name.contains($0) }
            if !isAllowedPattern {
                return "combo"  // Does NOT satisfy any pattern requirement
            }
        }
        
        // ═══════════════════════════════════════════════════════════════════════════
        // 🚨 CRITICAL: Check rear_delt patterns FIRST (before generic "fly" check!)
        // "Reverse Fly" must be detected as rear_delt, not chest_fly
        // ═══════════════════════════════════════════════════════════════════════════
        if name.contains("rear delt") || name.contains("reverse fly") || name.contains("reverse flye") || name.contains("face pull") {
            return "rear_delt"
        }
        
        // Chest patterns
        if name.contains("bench press") || name.contains("chest press") {
            if name.contains("incline") { return "incline_press" }
            if name.contains("decline") { return "decline_press" }
            return "chest_press"
        }
        
        // Generic fly check (AFTER rear_delt check to avoid misclassification)
        if name.contains("fly") || name.contains("flye") {
            if name.contains("low to high") || name.contains("low-to-high") { return "cable_fly_low_to_high" }
            if name.contains("high to low") || name.contains("high-to-low") { return "cable_fly_high_to_low" }
            return "chest_fly"
        }
        
        // Shoulder patterns
        if name.contains("shoulder press") || name.contains("overhead press") || name.contains("military press") {
            return "shoulder_press"
        }
        if name.contains("lateral raise") || name.contains("side raise") {
            return "lateral_raise"
        }
        if name.contains("front raise") {
            return "front_raise"
        }
        if name.contains("upright row") {
            return "upright_row"
        }
        
        // Back patterns
        // Check straight-arm pulldown FIRST (it's lat isolation, not vertical pull)
        if name.contains("straight arm") && name.contains("pulldown") {
            return "lat_isolation"
        }
        if name.contains("pulldown") || name.contains("pull down") || name.contains("lat pull") ||
           name.contains("pull up") || name.contains("pullup") || name.contains("chin up") {
            return "vertical_pull"
        }
        if (name.contains(" row") || name.hasPrefix("row")) && !name.contains("upright") {
            if name.contains("chest supported") || name.contains("chest-supported") {
                return "chest_supported_row"
            }
            return "horizontal_row"
        }
        if name.contains("shrug") {
            return "shrug"
        }
        if name.contains("pullover") {
            return "lat_isolation"
        }
        // NOTE: rear_delt patterns (face pull, reverse fly) are checked at the TOP of this function
        // to prevent them being misclassified as chest_fly
        
        // Arm patterns
        if name.contains("curl") && !name.contains("leg") && !name.contains("ham") {
            if name.contains("hammer") { return "bicep_neutral" }
            if name.contains("preacher") { return "bicep_preacher" }
            return "bicep_curl"
        }
        if name.contains("pushdown") || name.contains("press down") || name.contains("pressdown") {
            return "tricep_pressdown"
        }
        if name.contains("tricep") && (name.contains("extension") || name.contains("overhead")) {
            return "tricep_overhead"
        }
        if name.contains("skull crusher") {
            return "tricep_extension"
        }
        
        // Leg patterns
        if name.contains("squat") || name.contains("leg press") || name.contains("hack") {
            return "squat_pattern"
        }
        if name.contains("split squat") || name.contains("lunge") || name.contains("step up") {
            return "unilateral_leg"
        }
        if name.contains("hip thrust") || name.contains("glute bridge") {
            return "hip_thrust"
        }
        if name.contains("kickback") && (name.contains("glute") || name.contains("leg")) {
            return "glute_kickback"
        }
        if name.contains("leg curl") || name.contains("hamstring curl") {
            return "leg_curl"
        }
        if name.contains("leg extension") {
            return "leg_extension"
        }
        if name.contains("deadlift") || name.contains("rdl") || name.contains("romanian") {
            return "hinge"
        }
        if name.contains("back extension") || name.contains("hyperextension") {
            return "back_extension"
        }
        if name.contains("calf") {
            return "calf_raise"
        }
        
        // Core patterns
        if name.contains("pallof") {
            return "anti_rotation"
        }
        if name.contains("plank") || name.contains("dead bug") {
            return "anti_extension"
        }
        if name.contains("crunch") || name.contains("sit up") || name.contains("situp") {
            return "flexion"
        }
        
        // Dips
        if name.contains("dip") {
            if name.contains("bench") { return "bench_dip" }
            return "dip"
        }
        
        // Press fallback
        if name.contains("press") && !name.contains("leg press") {
            return "press"
        }
        
        return "other"
    }
    
    /// Check if exercise should be avoided based on combo rules
    static func shouldAvoidExercise(_ exerciseName: String, comboRule: ComboRule?, focusAreas: [String]? = nil) -> (shouldAvoid: Bool, reason: String) {
        let nameLower = exerciseName.lowercased()
        
        guard let rule = comboRule else { return (false, "") }
        
        // Check combo rule avoid list
        if rule.avoid.contains("front_raise") && nameLower.contains("front raise") {
            return (true, "Front raises avoided - front delts already worked from pressing")
        }
        
        if rule.avoid.contains("upright_row") && (nameLower.contains("upright row") || nameLower.contains("high pull")) {
            return (true, "Upright row/high pull avoided - risky as default")
        }
        
        if rule.avoid.contains("bench_dip") && nameLower.contains("bench dip") {
            return (true, "Bench dips avoided - risky for shoulders")
        }
        
        if rule.avoid.contains("behind_back_dip") && nameLower.contains("behind") && nameLower.contains("dip") {
            return (true, "Behind back dip avoided - risky as default")
        }
        
        return (false, "")
    }
    
    /// Check if a pattern is satisfied by the selected exercises
    static func hasRequiredPattern(_ pattern: String, in exercises: [(name: String, equipment: String)]) -> Bool {
        for (name, equipment) in exercises {
            let detected = detectExercisePattern(name, equipment: equipment)
            
            // Handle pattern matching with OR logic
            switch pattern {
            case "vertical_pull":
                if detected == "vertical_pull" { return true }
            case "horizontal_row":
                if detected == "horizontal_row" || detected == "chest_supported_row" { return true }
            case "bicep_curl":
                if detected == "bicep_curl" || detected == "bicep_neutral" || detected == "bicep_preacher" { return true }
            case "chest_press":
                if detected == "chest_press" || detected == "incline_press" || detected == "decline_press" { return true }
            case "shoulder_press":
                if detected == "shoulder_press" { return true }
            case "lateral_raise":
                if detected == "lateral_raise" { return true }
            case "rear_delt":
                if detected == "rear_delt" { return true }
            case "tricep_isolation":
                if detected == "tricep_pressdown" || detected == "tricep_overhead" { return true }
            case "leg_curl":
                if detected == "leg_curl" { return true }
            case "squat_pattern":
                if detected == "squat_pattern" { return true }
            default:
                if detected == pattern { return true }
            }
        }
        return false
    }
    
    /// Validate workout against combo rules - returns missing requirements
    static func getMissingRequirements(_ comboRule: ComboRule?, exercises: [(name: String, equipment: String)]) -> [String] {
        guard let rule = comboRule else { return [] }
        
        var missing: [String] = []
        for required in rule.mustInclude {
            if !hasRequiredPattern(required, in: exercises) {
                missing.append(required)
            }
        }
        return missing
    }
    
    /// Get effective caps, merging global caps with combo-specific overrides
    static func getEffectiveCaps(_ comboRule: ComboRule?, isArmsDay: Bool = false) -> [String: Int] {
        var caps: [String: Int] = [
            "press": GlobalCaps.press,
            "row": GlobalCaps.row,
            "hinge": GlobalCaps.hinge,
            "curl": GlobalCaps.curl,
            "tricep_extension": GlobalCaps.tricepExtension,
            "shrug": GlobalCaps.shrug,
            "back_extension": GlobalCaps.backExtension
        ]
        
        // Apply combo-specific overrides
        if let rule = comboRule {
            for (key, value) in rule.caps {
                caps[key] = value
            }
        }
        
        // If arms day, allow more curls/extensions
        if isArmsDay {
            caps["curl"] = 3
            caps["tricep_extension"] = 3
        }
        
        return caps
    }
    
    /// Check if required patterns are present in selected exercises
    static func validateRequiredPatterns(
        selectedExercises: [(name: String, equipment: String)],
        comboRule: ComboRule
    ) -> [String] {
        var missingPatterns: [String] = []
        var patternsPresent = Set<String>()
        
        // Detect all patterns in selected exercises
        for (name, equipment) in selectedExercises {
            let pattern = detectExercisePattern(name, equipment: equipment)
            patternsPresent.insert(pattern)
        }
        
        // Check each required pattern
        for required in comboRule.mustInclude {
            switch required {
            case "vertical_pull":
                if !patternsPresent.contains("vertical_pull") {
                    missingPatterns.append("vertical_pull")
                }
            case "horizontal_row":
                if !patternsPresent.contains("horizontal_row") && !patternsPresent.contains("chest_supported_row") {
                    missingPatterns.append("horizontal_row")
                }
            case "bicep_curl":
                if !patternsPresent.contains("bicep_curl") && !patternsPresent.contains("bicep_neutral") && !patternsPresent.contains("bicep_preacher") {
                    missingPatterns.append("bicep_curl")
                }
            case "chest_press":
                if !patternsPresent.contains("chest_press") && !patternsPresent.contains("incline_press") && !patternsPresent.contains("decline_press") {
                    missingPatterns.append("chest_press")
                }
            case "rear_delt":
                if !patternsPresent.contains("rear_delt") {
                    missingPatterns.append("rear_delt")
                }
            case "lateral_raise":
                if !patternsPresent.contains("lateral_raise") {
                    missingPatterns.append("lateral_raise")
                }
            case "shoulder_press":
                if !patternsPresent.contains("shoulder_press") {
                    missingPatterns.append("shoulder_press")
                }
            case "leg_curl":
                if !patternsPresent.contains("leg_curl") {
                    missingPatterns.append("leg_curl")
                }
            default:
                break
            }
        }
        
        return missingPatterns
    }

    // MARK: - Angle Stacking Cap (Audit 2026-05-08 fix #2)

    /// Maximum number of exercises sharing the same press/pull ANGLE that may
    /// appear in a single workout. Two is intentionally low — three+ same-angle
    /// movements on one day is almost always a programming defect (saw 4×
    /// decline chest in user-15 / user-26 of the Round 3 audit).
    ///
    /// Authority: this is the canonical cap. The angle classification + wouldExceedAngleCap
    /// helpers below are consulted by SmartExerciseSelectionEngine in its
    /// scoring loop. Mirror in scripts/comprehensive_autogen_audit.py.
    static let maxPerAngle: Int = 2

    /// Classify an exercise by its dominant press/pull ANGLE for stacking-cap
    /// enforcement. Returns "decline" / "flat" / "incline" / "vertical" / nil.
    /// nil = "not an angled press/pull" → angle cap doesn't apply.
    ///
    /// Keep classification deliberately keyword-driven and case-insensitive so
    /// it stays in lockstep with the Python mirror.
    static func angleClassification(for exerciseName: String) -> String? {
        let n = exerciseName.lowercased()

        // Decline takes priority — "decline bench press" must NOT classify as flat.
        if n.contains("decline") {
            return "decline"
        }
        // Incline next — "incline dumbbell press" must NOT classify as flat.
        if n.contains("incline") {
            return "incline"
        }
        // Vertical (overhead/military/shoulder press) — head-up, totally different
        // shoulder position. Must check BEFORE the "flat" press fallback so that
        // "shoulder press" doesn't get caught by the bare-"bench press" branch
        // (it won't — but explicit ordering matches the Python mirror).
        if n.contains("overhead") || n.contains("shoulder press") || n.contains("military press") {
            return "vertical"
        }
        // Flat: "flat bench" or generic "bench press" / "chest press" without an
        // incline/decline modifier (those were already returned above).
        if n.contains("flat bench") {
            return "flat"
        }
        if n.contains("bench press") || n.contains("chest press") {
            return "flat"
        }

        return nil
    }

    /// Returns true if adding `exerciseName` to a workout that already contains
    /// `existing` exercise names would push the same-angle count over `maxPerAngle`.
    /// Callers should treat this as a hard reject in the selection loop.
    ///
    /// Both arguments are matched case-insensitively via `angleClassification`.
    static func wouldExceedAngleCap(adding exerciseName: String, to existing: [String]) -> Bool {
        guard let candidateAngle = angleClassification(for: exerciseName) else {
            return false
        }
        let sameAngleCount = existing.reduce(into: 0) { acc, name in
            if angleClassification(for: name) == candidateAngle { acc += 1 }
        }
        return sameAngleCount >= maxPerAngle
    }
}

// MARK: - Focus Area Overrides

struct FocusAreaOverride {
    let prefer: [String]
    let avoid: [String]
    let boostPatterns: [String]
    let rule: String?
    let note: String?
    let repRange: (min: Int, max: Int)?
    
    init(prefer: [String] = [],
         avoid: [String] = [],
         boostPatterns: [String] = [],
         rule: String? = nil,
         note: String? = nil,
         repRange: (Int, Int)? = nil) {
        self.prefer = prefer
        self.avoid = avoid
        self.boostPatterns = boostPatterns
        self.rule = rule
        self.note = note
        self.repRange = repRange
    }
}

enum FocusAreaOverrides {
    static let overrides: [String: FocusAreaOverride] = [
        "upper_chest": FocusAreaOverride(
            prefer: ["incline press", "incline bench", "low to high", "low-to-high"],
            avoid: ["decline", "flat bench"],
            boostPatterns: ["incline_press", "cable_fly_low_to_high"]
        ),
        "lower_chest": FocusAreaOverride(
            prefer: ["decline press", "dip", "high to low", "high-to-low"],
            avoid: ["incline"],
            boostPatterns: ["decline_press", "dip", "cable_fly_high_to_low"],
            rule: "dips OR decline, not both"
        ),
        "front_delts": FocusAreaOverride(
            prefer: ["shoulder press", "overhead press"],
            avoid: ["front raise"],
            note: "Don't add front raises - front delts already worked from pressing"
        ),
        "side_delts": FocusAreaOverride(
            prefer: ["lateral raise", "side raise", "cable lateral"],
            boostPatterns: ["lateral_raise"]
        ),
        "rear_delts": FocusAreaOverride(
            prefer: ["rear delt", "reverse fly", "face pull"],
            boostPatterns: ["rear_delt", "face_pull"]
        ),
        "lats": FocusAreaOverride(
            prefer: ["pulldown", "lat pulldown", "straight arm pulldown"],
            boostPatterns: ["lat_pulldown", "straight_arm_pulldown"]
        ),
        "mid_back": FocusAreaOverride(
            prefer: ["chest supported row", "chest-supported", "t-bar row"],
            boostPatterns: ["chest_supported_row", "horizontal_row"]
        ),
        "glutes": FocusAreaOverride(
            prefer: ["hip thrust", "glute bridge", "kickback"],
            boostPatterns: ["hip_thrust", "glute_kickback"],
            repRange: (12, 20)
        ),
        "hamstrings": FocusAreaOverride(
            prefer: ["leg curl", "lying leg curl", "seated leg curl"],
            boostPatterns: ["leg_curl"],
            note: "Hinge is optional, leg curl is mandatory"
        ),
        "quads": FocusAreaOverride(
            prefer: ["leg press", "squat", "hack squat", "leg extension"],
            boostPatterns: ["squat", "leg_press", "leg_extension"]
        ),
        "calves": FocusAreaOverride(
            prefer: ["standing calf raise", "seated calf raise"]
        )
    ]
    
    static func getOverride(for focusArea: String) -> FocusAreaOverride? {
        let focusLower = focusArea.lowercased().replacingOccurrences(of: " ", with: "_")
        
        // Try exact match first
        if let override = overrides[focusLower] {
            return override
        }
        
        // Try partial match
        for (key, value) in overrides {
            if key.contains(focusLower) || focusLower.contains(key) {
                return value
            }
        }
        
        return nil
    }
}

// MARK: - Audit 2026-05-08 Round 3 Hardening
//
// Two reusable hardening helpers added in response to the 100-workout audit
// (`scripts/output/autogen_audit_20260508_124852.md`). Both target the two
// dominant residual issues:
//
//   1. `compound_after_isolation` — 42 instances. Isolation movements (curls,
//      kickbacks, lateral raises, leg extensions, leg curls) appearing BEFORE
//      compound movements in the final sequence. Critical training principle:
//      compounds first when the lifter is fresh.
//   2. `redundant_movement_pattern` — 100 instances. Workouts with 4 decline
//      chest moves in a row, or 3+ incline movements stacked. Per-angle cap
//      of 2 enforced via `wouldExceedAngleStackingCap` + score-side penalty
//      via `ScoringHints.angleStackingPenalty`.
//
// Authority: Fitness Expert + Product Engineer agents (PE invariant — workout
// quality enforcement). Public API only — never remove.

extension WorkoutComboRules {

    /// Final-pass compound-before-isolation sort. Apply this AFTER the
    /// selection engine has chosen exercises but BEFORE returning the final
    /// array to the caller. Compounds come first (when the lifter is fresh),
    /// isolation last.
    ///
    /// Stability: relative order of two compounds (or two isolations) is
    /// preserved — only the compound/isolation grouping is enforced.
    ///
    /// Authority: Fitness Expert + Product Engineer agents. Audit 2026-05-08
    /// flagged 42 instances of compound-after-isolation across the Round 3
    /// report. Classification source of truth is
    /// `FoundationalExerciseDatabase.isSingleJointIsolation(name:)`.
    static func compoundFirstSort<T>(
        _ exercises: [T],
        nameOf: (T) -> String
    ) -> [T] {
        var compounds: [T] = []
        var isolations: [T] = []
        for ex in exercises {
            if FoundationalExerciseDatabase.isSingleJointIsolation(name: nameOf(ex)) {
                isolations.append(ex)
            } else {
                compounds.append(ex)
            }
        }
        return compounds + isolations
    }

    // MARK: - Angle Stacking Cap
    //
    // `maxPerAngle` is declared on the main type (around line 826) — the
    // canonical source. The Round 3 audit fix added these helpers in this
    // extension and (incorrectly) re-declared the constant; removed to
    // resolve "Invalid redeclaration of 'maxPerAngle'". Reference the
    // canonical `WorkoutComboRules.maxPerAngle` (= 2) directly.

    /// Returns true if adding `candidateName` to `selectedNames` would push
    /// any detected angle bucket past `maxPerAngle`. Caller should skip the
    /// candidate when true. Buckets:
    ///
    /// • Chest angles — `decline`, `incline`, `flat` (substring match in
    ///   the exercise name; "Decline Push Up" + "Decline Bench Press DB" +
    ///   "Decline Chest Fly" together would all bucket as `decline`).
    /// • Back vertical pulls — `pulldown`, `pull up`, `pull-up`, `pullup`,
    ///   `chin up`, `chin-up`.
    /// • Back horizontal pulls — `row`, `bent over`, `bent-over`,
    ///   `seated row`.
    ///
    /// The candidate is bucketed by which keyword set it matches; counts
    /// against `selectedNames` use the same keyword set so the comparison
    /// is symmetric.
    ///
    /// Audit 2026-05-08 (Round 3, 100 workouts): user-15 + user-26 each
    /// shipped 4 decline-chest moves stacked. Same shoulder-girdle position
    /// = same fiber recruitment bias; stacking 4 of them is a programming
    /// defect — `maxPerAngle = 2` is the corrective hard ceiling.
    static func wouldExceedAngleStackingCap(
        candidateName: String,
        selectedNames: [String]
    ) -> Bool {
        let lc = candidateName.lowercased()
        let selectedLower = selectedNames.map { $0.lowercased() }

        // Chest angles — independent buckets per angle keyword.
        let chestAngles = ["decline", "incline", "flat"]
        for angle in chestAngles where lc.contains(angle) {
            // Don't bucket "flat" inside "platform"/"flatten"; require word boundary.
            // Lightweight heuristic: require the keyword to appear next to a space
            // OR at the start. Good-enough for the exercise catalog vocabulary.
            let candidateMatches = matchesAngleKeyword(angle, in: lc)
            if !candidateMatches { continue }
            let count = selectedLower.filter { matchesAngleKeyword(angle, in: $0) }.count
            if count >= Self.maxPerAngle { return true }
        }

        // Back vertical pulls — bucket the candidate, then count vertical pulls
        // already selected.
        let verticalPullKeys = ["pulldown", "pull up", "pull-up", "pullup", "chin up", "chin-up"]
        let horizontalPullKeys = ["row", "bent over", "bent-over", "seated row"]

        let candidateIsVertical = verticalPullKeys.contains(where: { lc.contains($0) })
        let candidateIsHorizontal = horizontalPullKeys.contains(where: { lc.contains($0) })
            // Disambiguate "seated row" / "bent-over row" — they're horizontal
            // even though `row` is the canonical key.
            && !candidateIsVertical

        if candidateIsVertical {
            let n = selectedLower.filter { name in
                verticalPullKeys.contains(where: { name.contains($0) })
            }.count
            if n >= Self.maxPerAngle { return true }
        }
        if candidateIsHorizontal {
            let n = selectedLower.filter { name in
                let nameIsVertical = verticalPullKeys.contains(where: { name.contains($0) })
                let nameIsHorizontal = horizontalPullKeys.contains(where: { name.contains($0) })
                return nameIsHorizontal && !nameIsVertical
            }.count
            if n >= Self.maxPerAngle { return true }
        }

        return false
    }

    /// Counts the per-angle stacking burden of an already-selected exercise
    /// list. Returns the largest bucket size found across chest angles +
    /// vertical/horizontal pulls. Caller can use this to apply the
    /// `ScoringHints.angleStackingPenalty` when the bucket is `>= 3` (the
    /// soft penalty fires even when the hard cap was bypassed by a
    /// higher-priority candidate).
    static func maxAngleStackingDepth(in selectedNames: [String]) -> Int {
        let lc = selectedNames.map { $0.lowercased() }

        var depths: [Int] = []
        for angle in ["decline", "incline", "flat"] {
            depths.append(lc.filter { matchesAngleKeyword(angle, in: $0) }.count)
        }

        let verticalPullKeys = ["pulldown", "pull up", "pull-up", "pullup", "chin up", "chin-up"]
        let horizontalPullKeys = ["row", "bent over", "bent-over", "seated row"]
        depths.append(lc.filter { name in
            verticalPullKeys.contains(where: { name.contains($0) })
        }.count)
        depths.append(lc.filter { name in
            let nameIsVertical = verticalPullKeys.contains(where: { name.contains($0) })
            let nameIsHorizontal = horizontalPullKeys.contains(where: { name.contains($0) })
            return nameIsHorizontal && !nameIsVertical
        }.count)

        return depths.max() ?? 0
    }

    /// Word-boundary-aware substring match for angle keywords. Prevents
    /// "flat" from matching "platform" / "flatten". The exercise catalog is
    /// lowercase + space-separated so a quick boundary check is sufficient.
    private static func matchesAngleKeyword(_ keyword: String, in name: String) -> Bool {
        // Whole-word match: keyword must be preceded by start-of-string or
        // whitespace AND followed by end-of-string, whitespace, or hyphen.
        guard let range = name.range(of: keyword) else { return false }
        let beforeOK: Bool = {
            if range.lowerBound == name.startIndex { return true }
            let prev = name[name.index(before: range.lowerBound)]
            return prev == " " || prev == "-"
        }()
        let afterOK: Bool = {
            if range.upperBound == name.endIndex { return true }
            let next = name[range.upperBound]
            return next == " " || next == "-"
        }()
        return beforeOK && afterOK
    }
}

// MARK: - Scoring Adjustments

extension WorkoutComboRules {
    /// Get score adjustments based on combo rules and focus areas
    static func getScoringAdjustment(
        exerciseName: String,
        equipment: String,
        targetMuscles: [String],
        focusAreas: [String]? = nil
    ) -> Int {
        var adjustment = 0
        let nameLower = exerciseName.lowercased()
        
        let comboRule = getComboRule(targetMuscles)
        
        // Check focus area preferences
        if let focusAreas = focusAreas {
            for focus in focusAreas {
                if let override = FocusAreaOverrides.getOverride(for: focus) {
                    // Boost preferred exercises
                    for pref in override.prefer {
                        if nameLower.contains(pref.lowercased()) {
                            adjustment += 100
                            break
                        }
                    }
                    
                    // Penalize avoided exercises
                    for avoid in override.avoid {
                        if nameLower.contains(avoid.lowercased()) {
                            adjustment -= 200
                            break
                        }
                    }
                }
            }
        }
        
        // Check combo rule avoids
        if let rule = comboRule {
            let (shouldAvoid, _) = shouldAvoidExercise(exerciseName, comboRule: rule, focusAreas: focusAreas)
            if shouldAvoid {
                adjustment -= 300
            }
        }
        
        // Boost balance slot exercises
        if let balance = getBalanceSlot(targetMuscles) {
            if balance == "rear_delt" && (nameLower.contains("face pull") || nameLower.contains("rear delt") || nameLower.contains("reverse fly")) {
                adjustment += 50
            }
            if balance == "core_stability" && (nameLower.contains("pallof") || nameLower.contains("dead bug") || nameLower.contains("plank")) {
                adjustment += 50
            }
        }
        
        return adjustment
    }
}
