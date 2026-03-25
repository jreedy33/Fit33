//
//  ExerciseBundleEngine.swift
//  GoFit
//
//  Groups similar exercises into "bundles" so the generator never picks
//  two exercises that are essentially the same movement.
//
//  Example: Barbell Bench Press, Dumbbell Chest Press, Smith Incline Press,
//           Lever Chest Press → all belong to the "horizontal_press" bundle.
//  Rule: max 1-2 exercises per bundle per workout.
//
//  Bundles sit ABOVE exercise families:
//    Family = "bench_press", "chest_press", "smith_chest_press"
//    Bundle = "horizontal_press" (contains all three families)
//
//  This engine is used by SmartExerciseSelectionEngine and SmartDayGenerator.
//

import Foundation

// MARK: - Exercise Bundle Definition

struct ExerciseBundle: Identifiable, Hashable {
    let id: String                     // e.g. "horizontal_press"
    let displayName: String            // e.g. "Horizontal Press"
    let families: Set<String>          // Exercise family IDs that belong to this bundle
    let movementPattern: String        // Primary movement pattern
    let maxPerWorkout: Int             // How many from this bundle in one workout (1-2)
    let maxPerWeek: Int                // Soft cap per week for variety
    let cooldownDays: Int              // Min days before repeating same exact exercise
    
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: ExerciseBundle, rhs: ExerciseBundle) -> Bool { lhs.id == rhs.id }
}

// MARK: - Exercise Bundle Engine

class ExerciseBundleEngine {
    static let shared = ExerciseBundleEngine()
    
    // MARK: - All Bundles
    
    /// Master list of exercise bundles — families within the same bundle are
    /// considered "essentially the same exercise" for selection purposes.
    let bundles: [ExerciseBundle] = [
        
        // ═══════════════════════════════════════════════════════════════════
        // CHEST — PRESSING
        // Bench press, chest press, smith press, push-ups → same horizontal push
        // ═══════════════════════════════════════════════════════════════════
        ExerciseBundle(
            id: "horizontal_press",
            displayName: "Horizontal Press (Chest)",
            families: ["bench_press", "chest_press", "smith_chest_press", "pushup", "dip"],
            movementPattern: "horizontal_press",
            maxPerWorkout: 1,   // 1 press per workout — second chest slot should be a fly/crossover
            maxPerWeek: 4,
            cooldownDays: 3
        ),
        
        // CHEST — FLYES / ISOLATION
        ExerciseBundle(
            id: "chest_isolation",
            displayName: "Chest Fly / Isolation",
            families: ["chest_fly", "cable_crossover", "pec_deck"],
            movementPattern: "chest_fly",
            maxPerWorkout: 1,
            maxPerWeek: 3,
            cooldownDays: 3
        ),
        
        // ═══════════════════════════════════════════════════════════════════
        // SHOULDERS — PRESSING
        // Overhead press, shoulder press, military press, arnold press → same vertical push
        // ═══════════════════════════════════════════════════════════════════
        ExerciseBundle(
            id: "vertical_press",
            displayName: "Vertical Press (Shoulders)",
            families: ["shoulder_press"],
            movementPattern: "vertical_press",
            maxPerWorkout: 1,
            maxPerWeek: 3,
            cooldownDays: 3
        ),
        
        // SHOULDERS — LATERAL
        ExerciseBundle(
            id: "lateral_raise_bundle",
            displayName: "Lateral Raise",
            families: ["lateral_raise"],
            movementPattern: "lateral_raise",
            maxPerWorkout: 1,
            maxPerWeek: 3,
            cooldownDays: 3
        ),
        
        // SHOULDERS — FRONT RAISE (separate from lateral to avoid bundling distinct movements)
        ExerciseBundle(
            id: "front_raise_bundle",
            displayName: "Front Raise",
            families: ["front_raise"],
            movementPattern: "front_raise",
            maxPerWorkout: 1,
            maxPerWeek: 2,
            cooldownDays: 3
        ),
        
        // SHOULDERS — REAR DELT
        ExerciseBundle(
            id: "rear_delt_bundle",
            displayName: "Rear Delt",
            families: ["rear_delt", "face_pull"],
            movementPattern: "rear_delt",
            maxPerWorkout: 1,
            maxPerWeek: 3,
            cooldownDays: 3
        ),
        
        // ═══════════════════════════════════════════════════════════════════
        // BACK — ROWING (Horizontal Pull)
        // Barbell row, cable row, machine row, dumbbell row, T-bar row → same row
        // ═══════════════════════════════════════════════════════════════════
        ExerciseBundle(
            id: "horizontal_pull",
            displayName: "Row (Horizontal Pull)",
            families: ["row"],
            movementPattern: "horizontal_pull",
            maxPerWorkout: 2,   // e.g., heavy barbell row + cable row
            maxPerWeek: 4,
            cooldownDays: 3
        ),
        
        // BACK — VERTICAL PULL
        // Pull-ups, chin-ups, lat pulldowns → same vertical pull
        ExerciseBundle(
            id: "vertical_pull",
            displayName: "Pulldown / Pull-up (Vertical Pull)",
            families: ["pulldown", "pullup", "chinup"],
            movementPattern: "vertical_pull",
            maxPerWorkout: 1,
            maxPerWeek: 3,
            cooldownDays: 3
        ),
        
        // BACK — SHRUGS
        ExerciseBundle(
            id: "shrug_bundle",
            displayName: "Shrug",
            families: ["shrug"],
            movementPattern: "shrug",
            maxPerWorkout: 1,
            maxPerWeek: 2,
            cooldownDays: 5
        ),
        
        // ═══════════════════════════════════════════════════════════════════
        // LEGS — SQUAT PATTERN
        // Back squat, front squat, goblet squat, hack squat, leg press → same quad compound
        // ═══════════════════════════════════════════════════════════════════
        ExerciseBundle(
            id: "squat_pattern",
            displayName: "Squat / Leg Press",
            families: ["squat", "leg_press"],
            movementPattern: "squat",
            maxPerWorkout: 2,   // e.g., squat + leg press
            maxPerWeek: 4,
            cooldownDays: 3
        ),
        
        // LEGS — HINGE PATTERN
        // Deadlift, RDL, stiff-leg deadlift → same hinge (back extension is spinal, not hinge)
        ExerciseBundle(
            id: "hinge_pattern",
            displayName: "Deadlift / RDL (Hinge)",
            families: ["deadlift", "good_morning"],
            movementPattern: "hinge",
            maxPerWorkout: 1,
            maxPerWeek: 3,
            cooldownDays: 4
        ),
        
        // BACK — SPINAL EXTENSION (separate from hinge to preserve heavy compound slot)
        ExerciseBundle(
            id: "spinal_extension_pattern",
            displayName: "Back Extension / Hyperextension",
            families: ["back_extension"],
            movementPattern: "spinal_extension",
            maxPerWorkout: 1,
            maxPerWeek: 3,
            cooldownDays: 2
        ),
        
        // LEGS — LUNGE PATTERN
        ExerciseBundle(
            id: "lunge_pattern",
            displayName: "Lunge / Split Squat",
            families: ["lunge", "step_up"],
            movementPattern: "lunge",
            maxPerWorkout: 1,
            maxPerWeek: 3,
            cooldownDays: 3
        ),
        
        // LEGS — HIP THRUST / GLUTE
        ExerciseBundle(
            id: "hip_thrust_bundle",
            displayName: "Hip Thrust / Glute Bridge",
            families: ["hip_thrust"],
            movementPattern: "hip_thrust",
            maxPerWorkout: 1,
            maxPerWeek: 3,
            cooldownDays: 3
        ),
        
        // LEGS — QUAD ISOLATION
        ExerciseBundle(
            id: "quad_isolation",
            displayName: "Leg Extension",
            families: ["leg_extension"],
            movementPattern: "leg_extension",
            maxPerWorkout: 1,
            maxPerWeek: 2,
            cooldownDays: 3
        ),
        
        // LEGS — HAMSTRING ISOLATION
        ExerciseBundle(
            id: "ham_isolation",
            displayName: "Leg Curl",
            families: ["leg_curl"],
            movementPattern: "leg_curl",
            maxPerWorkout: 1,
            maxPerWeek: 2,
            cooldownDays: 3
        ),
        
        // LEGS — CALF
        ExerciseBundle(
            id: "calf_bundle",
            displayName: "Calf Raise",
            families: ["calf_raise"],
            movementPattern: "calf_raise",
            maxPerWorkout: 1,
            maxPerWeek: 3,
            cooldownDays: 2
        ),
        
        // ═══════════════════════════════════════════════════════════════════
        // BICEPS
        // Barbell curl, dumbbell curl, EZ curl, preacher curl, cable curl → same curl bundle
        // ═══════════════════════════════════════════════════════════════════
        ExerciseBundle(
            id: "bicep_curl_bundle",
            displayName: "Bicep Curl",
            families: ["bicep_curl", "hammer_curl", "preacher_curl", "concentration_curl"],
            movementPattern: "bicep_curl",
            maxPerWorkout: 2,   // 1 heavy + 1 isolation variation
            maxPerWeek: 4,
            cooldownDays: 2
        ),
        
        // ═══════════════════════════════════════════════════════════════════
        // TRICEPS
        // Pushdown, extension, skull crusher, dip, close-grip bench → same tricep bundle
        // ═══════════════════════════════════════════════════════════════════
        ExerciseBundle(
            id: "tricep_extension_bundle",
            displayName: "Tricep Extension / Pushdown",
            families: ["tricep_pushdown", "tricep_extension", "skull_crusher", "kickback"],
            movementPattern: "tricep_extension",
            maxPerWorkout: 2,   // 1 overhead/lengthened + 1 pressdown
            maxPerWeek: 4,
            cooldownDays: 2
        ),
        
        // ═══════════════════════════════════════════════════════════════════
        // CORE
        // ═══════════════════════════════════════════════════════════════════
        ExerciseBundle(
            id: "core_flexion_bundle",
            displayName: "Core Flexion",
            families: ["crunch", "leg_raise"],
            movementPattern: "core_flexion",
            maxPerWorkout: 1,
            maxPerWeek: 4,
            cooldownDays: 1
        ),
        
        ExerciseBundle(
            id: "core_stability_bundle",
            displayName: "Core Stability",
            families: ["plank", "dead_bug", "hollow_hold", "ab_wheel"],
            movementPattern: "core_stability",
            maxPerWorkout: 1,
            maxPerWeek: 4,
            cooldownDays: 1
        ),
        
        ExerciseBundle(
            id: "core_rotation_bundle",
            displayName: "Core Rotation",
            families: ["woodchop", "russian_twist", "anti_rotation"],
            movementPattern: "core_rotation",
            maxPerWorkout: 1,
            maxPerWeek: 3,
            cooldownDays: 2
        ),
        
        // ═══════════════════════════════════════════════════════════════════
        // TRAPS / UPRIGHT ROW
        // ═══════════════════════════════════════════════════════════════════
        ExerciseBundle(
            id: "upright_row_bundle",
            displayName: "Upright Row",
            families: ["upright_row"],
            movementPattern: "shrug",
            maxPerWorkout: 1,
            maxPerWeek: 1,
            cooldownDays: 7
        ),
    ]
    
    // MARK: - Lookup Caches (built once)
    
    /// Family → Bundle mapping for O(1) lookups
    private lazy var familyToBundleMap: [String: ExerciseBundle] = {
        var map: [String: ExerciseBundle] = [:]
        for bundle in bundles {
            for family in bundle.families {
                map[family] = bundle
            }
        }
        return map
    }()
    
    /// Bundle ID → Bundle
    private lazy var bundleByIdMap: [String: ExerciseBundle] = {
        Dictionary(uniqueKeysWithValues: bundles.map { ($0.id, $0) })
    }()
    
    private init() {
        // Force lazy init
        _ = familyToBundleMap
        _ = bundleByIdMap
    }
    
    // MARK: - Public API
    
    /// Get the bundle for an exercise family. Returns nil if no bundle defined (rare exercise).
    func bundleForFamily(_ family: String) -> ExerciseBundle? {
        return familyToBundleMap[family]
    }
    
    /// Get the bundle for an exercise by name (uses family detection first).
    func bundleForExercise(named exerciseName: String) -> ExerciseBundle? {
        let family = detectExerciseFamily(exerciseName)
        return familyToBundleMap[family]
    }
    
    /// Get the bundle for an Exercise Core Data object.
    /// Prefers the stored exerciseFamily field, falls back to name detection.
    func bundleForExercise(_ exercise: Exercise) -> ExerciseBundle? {
        // First try stored family
        if let storedFamily = exercise.value(forKey: "exerciseFamily") as? String,
           !storedFamily.isEmpty {
            if let bundle = familyToBundleMap[storedFamily] {
                return bundle
            }
        }
        // Fallback to name-based detection
        let name = exercise.name ?? ""
        return bundleForExercise(named: name)
    }
    
    /// Get the bundle by its ID.
    func bundle(byId id: String) -> ExerciseBundle? {
        return bundleByIdMap[id]
    }
    
    /// Check if two exercises are in the same bundle (essentially the same movement).
    func areInSameBundle(_ exercise1Name: String, _ exercise2Name: String) -> Bool {
        guard let b1 = bundleForExercise(named: exercise1Name),
              let b2 = bundleForExercise(named: exercise2Name) else {
            return false
        }
        return b1.id == b2.id
    }
    
    /// Get the max exercises allowed from a bundle in one workout.
    func maxPerWorkout(for exerciseName: String) -> Int {
        return bundleForExercise(named: exerciseName)?.maxPerWorkout ?? 2
    }
    
    /// Get the cooldown days for a specific exercise's bundle.
    func cooldownDays(for exerciseName: String) -> Int {
        return bundleForExercise(named: exerciseName)?.cooldownDays ?? 7
    }
    
    // MARK: - Bundle-Aware Selection Helpers
    
    /// Given a set of already-selected exercises, check if we can add another from the same bundle.
    func canAddExercise(
        named exerciseName: String,
        toWorkoutWith existingExercises: [String],
        isProgram: Bool = false
    ) -> Bool {
        guard let bundle = bundleForExercise(named: exerciseName) else {
            return true // Unknown bundle = allow
        }
        
        let existingInBundle = existingExercises.filter { existing in
            bundleForExercise(named: existing)?.id == bundle.id
        }.count
        
        return existingInBundle < bundle.maxPerWorkout
    }
    
    /// Filter out exercises that would exceed bundle limits.
    /// Returns exercises that are still allowed.
    func filterByBundleLimits(
        candidates: [(name: String, score: Double)],
        existingSelections: [String]
    ) -> [(name: String, score: Double)] {
        var bundleCounts: [String: Int] = [:]
        
        // Count existing selections
        for name in existingSelections {
            if let bundle = bundleForExercise(named: name) {
                bundleCounts[bundle.id, default: 0] += 1
            }
        }
        
        return candidates.filter { candidate in
            guard let bundle = bundleForExercise(named: candidate.name) else {
                return true
            }
            return (bundleCounts[bundle.id] ?? 0) < bundle.maxPerWorkout
        }
    }
    
    /// Check if an exercise was done too recently (within cooldown window).
    /// `recentExercises` maps exercise names to days since last done.
    func isWithinCooldown(
        exerciseName: String,
        recentExercises: [String: Int],
        isAnchorLift: Bool = false
    ) -> Bool {
        // Anchor lifts in strength blocks can repeat more frequently
        if isAnchorLift { return false }
        
        let cooldown = cooldownDays(for: exerciseName)
        
        if let daysSinceDone = recentExercises[exerciseName.lowercased()] {
            return daysSinceDone < cooldown
        }
        
        return false
    }
    
    // MARK: - Weekly Coverage Validation
    
    /// Validates that a week's worth of workouts covers required movement patterns.
    /// Returns missing patterns that should be added.
    func validateWeeklyCoverage(weekExercises: [[String]]) -> [String] {
        let requiredPatterns: Set<String> = [
            "squat", "hinge", "horizontal_press", "vertical_press",
            "horizontal_pull", "vertical_pull"
        ]
        
        var coveredPatterns: Set<String> = []
        
        for dayExercises in weekExercises {
            for exerciseName in dayExercises {
                if let bundle = bundleForExercise(named: exerciseName) {
                    coveredPatterns.insert(bundle.movementPattern)
                }
            }
        }
        
        return Array(requiredPatterns.subtracting(coveredPatterns))
    }
    
    // MARK: - Superset Pairing (for LEAN programs)
    
    /// Returns bundles that pair well for supersets (non-conflicting muscle groups).
    /// Push ↔ Pull, Bicep ↔ Tricep, Lateral Raise ↔ Rear Delt, etc.
    static let supersetPairs: [(String, String)] = [
        ("horizontal_press", "horizontal_pull"),      // Bench ↔ Row
        ("horizontal_press", "vertical_pull"),         // Bench ↔ Pulldown
        ("vertical_press", "vertical_pull"),           // OHP ↔ Pulldown
        ("lateral_raise_bundle", "rear_delt_bundle"),  // Lat Raise ↔ Face Pull
        ("bicep_curl_bundle", "tricep_extension_bundle"), // Curl ↔ Pushdown
        ("quad_isolation", "ham_isolation"),            // Leg Ext ↔ Leg Curl
        ("squat_pattern", "hinge_pattern"),             // Squat ↔ RDL (advanced)
        ("chest_isolation", "horizontal_pull"),         // Fly ↔ Row
    ]
    
    /// Get the complementary bundle for superset pairing.
    func supersetPartner(for bundleId: String) -> String? {
        for (a, b) in Self.supersetPairs {
            if a == bundleId { return b }
            if b == bundleId { return a }
        }
        return nil
    }
    
    // MARK: - Family Detection (shared logic)
    
    /// Detects the exercise "family" from exercise name.
    /// This is the same logic as SmartExerciseSelectionEngine.detectExerciseFamily
    /// but exposed publicly so all systems use the same classification.
    func detectExerciseFamily(_ exerciseName: String) -> String {
        let name = exerciseName.lowercased()
        
        // ═══════════════════════════════════════════════════════════
        // SPECIAL CASES
        // ═══════════════════════════════════════════════════════════
        if name.contains("deadlift") && (name.contains("row") || name.contains("shrug")) {
            return "deadlift"
        }
        if name.contains("deadlift") && (name.contains("squat machine") || name.contains("squat cage")) {
            return "deadlift"
        }
        if name.contains("good morning") { return "good_morning" }
        if name.contains("back extension") || name.contains("hyperextension") { return "back_extension" }
        if name.contains("shrug") && !name.contains("deadlift") { return "shrug" }
        if name.contains("skull") { return "skull_crusher" }
        
        // Smith machine chest presses → same bundle as bench press
        if name.contains("smith") && (name.contains("decline") || name.contains("incline") || name.contains("flat") || name.contains("reverse grip") || name.contains("press")) {
            if !name.contains("shoulder") && !name.contains("squat") && !name.contains("row") {
                return "bench_press"  // ← Unified with bench press family
            }
        }
        
        // ═══════════════════════════════════════════════════════════
        // CHEST — All pressing variants go to same families
        // ═══════════════════════════════════════════════════════════
        if name.contains("bench press") { return "bench_press" }
        if name.contains("chest press") { return "chest_press" }
        if (name.contains("incline") || name.contains("decline") || name.contains("flat")) && name.contains("press") {
            if !name.contains("shoulder") && !name.contains("leg") {
                return "bench_press"
            }
        }
        if name.contains("fly") || name.contains("flye") { return "chest_fly" }
        if name.contains("push-up") || name.contains("pushup") || name.contains("push up") { return "pushup" }
        if name.contains("crossover") { return "cable_crossover" }
        if name.contains("pec deck") { return "pec_deck" }
        
        // ═══════════════════════════════════════════════════════════
        // LEGS
        // ═══════════════════════════════════════════════════════════
        if name.contains("leg press") || (name.contains("sled") && name.contains("press")) { return "leg_press" }
        if name.contains("squat") && !name.contains("squat machine") && !name.contains("squat cage") { return "squat" }
        if name.contains("deadlift") { return "deadlift" }
        if name.contains("lunge") { return "lunge" }
        if name.contains("split squat") || name.contains("bulgarian") { return "lunge" }
        if name.contains("step up") || name.contains("step-up") { return "step_up" }
        if name.contains("leg extension") || name.contains("knee extension") { return "leg_extension" }
        if name.contains("leg curl") || name.contains("hamstring curl") { return "leg_curl" }
        if name.contains("calf raise") || name.contains("calf press") { return "calf_raise" }
        if name.contains("hip thrust") || name.contains("glute bridge") { return "hip_thrust" }
        
        // ═══════════════════════════════════════════════════════════
        // BACK
        // ═══════════════════════════════════════════════════════════
        if name.contains("row") && !name.contains("upright") && !name.contains("deadlift") {
            if !name.contains(" arrow") && !name.hasPrefix("arrow") {
                return "row"
            }
        }
        if name.contains("pulldown") || name.contains("pull-down") || name.contains("pull down") { return "pulldown" }
        if name.contains("pull-up") || name.contains("pullup") || name.contains("pull up") { return "pullup" }
        if name.contains("chin-up") || name.contains("chinup") || name.contains("chin up") { return "chinup" }
        if name.contains("face pull") { return "face_pull" }
        
        // ═══════════════════════════════════════════════════════════
        // SHOULDERS
        // ═══════════════════════════════════════════════════════════
        if name.contains("overhead press") || name.contains("shoulder press") || name.contains("shoulders press") ||
           name.contains("military press") || name.contains("arnold press") || name.contains("neck press") {
            return "shoulder_press"
        }
        if name.contains("lateral raise") || name.contains("side raise") { return "lateral_raise" }
        if name.contains("front raise") { return "front_raise" }
        if name.contains("rear delt") || name.contains("reverse fly") || name.contains("reverse flye") { return "rear_delt" }
        if name.contains("upright row") { return "upright_row" }
        
        // ═══════════════════════════════════════════════════════════
        // ARMS
        // ═══════════════════════════════════════════════════════════
        if name.contains("hammer curl") { return "hammer_curl" }
        if name.contains("preacher curl") { return "preacher_curl" }
        if name.contains("concentration curl") { return "concentration_curl" }
        if name.contains("curl") && !name.contains("leg") && !name.contains("ham") { return "bicep_curl" }
        if name.contains("tricep pushdown") || name.contains("triceps pushdown") || name.contains("pushdown") || name.contains("press down") { return "tricep_pushdown" }
        if name.contains("tricep extension") || name.contains("triceps extension") || name.contains("overhead extension") { return "tricep_extension" }
        if name.contains("dip") && !name.contains("hip") { return "dip" }
        if name.contains("kickback") && name.contains("tricep") { return "kickback" }
        
        // ═══════════════════════════════════════════════════════════
        // CORE
        // ═══════════════════════════════════════════════════════════
        if name.contains("plank") { return "plank" }
        if name.contains("crunch") || name.contains("sit-up") || name.contains("sit up") { return "crunch" }
        if name.contains("leg raise") && !name.contains("lateral") { return "leg_raise" }
        if name.contains("pallof") || name.contains("anti-rotation") { return "anti_rotation" }
        if name.contains("woodchop") || name.contains("wood chop") { return "woodchop" }
        if name.contains("russian twist") { return "russian_twist" }
        if name.contains("dead bug") { return "dead_bug" }
        if name.contains("hollow") { return "hollow_hold" }
        if name.contains("ab wheel") || name.contains("rollout") { return "ab_wheel" }
        
        return "other"
    }
    
    // MARK: - Debug / Logging
    
    func logBundleInfo(for exerciseName: String) {
        let family = detectExerciseFamily(exerciseName)
        let bundle = familyToBundleMap[family]
        AppLogger.debug("📦 Exercise: \(exerciseName)", category: .workout)
        AppLogger.debug("   Family: \(family)", category: .workout)
        AppLogger.debug("   Bundle: \(bundle?.id ?? "none") (\(bundle?.displayName ?? "uncategorized"))", category: .workout)
        AppLogger.debug("   Max/workout: \(bundle?.maxPerWorkout ?? 0)", category: .workout)
        AppLogger.debug("   Cooldown: \(bundle?.cooldownDays ?? 0) days", category: .workout)
    }
}

// MARK: - Exercise Cooldown Tracker

/// Tracks recently used exercises to enforce cooldown windows.
/// Exercises in the same bundle shouldn't repeat for X days (unless anchor lifts).
class ExerciseCooldownTracker {
    static let shared = ExerciseCooldownTracker()
    
    private let storageKey = "exercise_cooldown_history"
    
    /// Maps exercise name (lowercased) → Date last performed
    private var exerciseHistory: [String: Date] = [:]
    
    private init() {
        loadHistory()
    }
    
    // MARK: - Public API
    
    /// Record that an exercise was performed today.
    func recordExercise(_ exerciseName: String, date: Date = Date()) {
        exerciseHistory[exerciseName.lowercased()] = date
        saveHistory()
    }
    
    /// Record a full workout's exercises.
    func recordWorkoutExercises(_ exerciseNames: [String], date: Date = Date()) {
        for name in exerciseNames {
            exerciseHistory[name.lowercased()] = date
        }
        saveHistory()
    }
    
    /// Get days since an exercise was last done. Returns nil if never done.
    func daysSinceLastDone(_ exerciseName: String) -> Int? {
        guard let lastDate = exerciseHistory[exerciseName.lowercased()] else {
            return nil
        }
        return Calendar.current.dateComponents([.day], from: lastDate, to: Date()).day
    }
    
    /// Check if an exercise is within its cooldown window.
    func isOnCooldown(_ exerciseName: String, isAnchor: Bool = false) -> Bool {
        if isAnchor { return false } // Anchors can repeat
        
        guard let days = daysSinceLastDone(exerciseName) else {
            return false // Never done = not on cooldown
        }
        
        let cooldown = ExerciseBundleEngine.shared.cooldownDays(for: exerciseName)
        return days < cooldown
    }
    
    /// Get all exercises on cooldown with their remaining days.
    func getExercisesOnCooldown() -> [(name: String, daysRemaining: Int)] {
        let bundleEngine = ExerciseBundleEngine.shared
        var result: [(name: String, daysRemaining: Int)] = []
        
        for (name, lastDate) in exerciseHistory {
            let daysSince = Calendar.current.dateComponents([.day], from: lastDate, to: Date()).day ?? 0
            let cooldown = bundleEngine.cooldownDays(for: name)
            if daysSince < cooldown {
                result.append((name: name, daysRemaining: cooldown - daysSince))
            }
        }
        
        return result.sorted { $0.daysRemaining > $1.daysRemaining }
    }
    
    /// Build the recentExercises map (name → daysSinceDone) for bundle engine use.
    func buildRecentExerciseMap() -> [String: Int] {
        var map: [String: Int] = [:]
        for (name, lastDate) in exerciseHistory {
            let days = Calendar.current.dateComponents([.day], from: lastDate, to: Date()).day ?? 0
            map[name] = days
        }
        return map
    }
    
    /// Clear all history.
    func clearHistory() {
        exerciseHistory = [:]
        saveHistory()
    }
    
    /// Prune entries older than 30 days to keep storage lean.
    func pruneOldEntries() {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        exerciseHistory = exerciseHistory.filter { $0.value > cutoff }
        saveHistory()
    }
    
    // MARK: - Persistence
    
    private func saveHistory() {
        let encoded = exerciseHistory.mapValues { $0.timeIntervalSince1970 }
        UserDefaults.standard.set(encoded, forKey: storageKey)
    }
    
    private func loadHistory() {
        guard let stored = UserDefaults.standard.dictionary(forKey: storageKey) as? [String: Double] else {
            return
        }
        exerciseHistory = stored.mapValues { Date(timeIntervalSince1970: $0) }
        
        // Auto-prune on load
        pruneOldEntries()
    }
}
