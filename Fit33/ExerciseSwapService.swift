//
//  ExerciseSwapService.swift
//  GoFit
//
//  Intelligent exercise swap service using database-powered family classifications
//  Provides smart alternatives based on equipment variants and complementary exercises
//

import Foundation
import CoreData

// MARK: - Swap Suggestion Model

struct SwapSuggestion: Identifiable {
    let id = UUID()
    let exercise: Exercise
    let swapType: SwapType
    let reason: String
    let priorityScore: Int
    
    enum SwapType: String {
        case equipmentVariant = "Same Movement"      // Same family, different equipment
        case adjacentFamily = "Same Muscle"           // Different family, shares primary muscle
        case complementary = "Complementary"          // Antagonist / pairing partner from complementaryFamilies
        case similar = "Similar"                      // Fallback algorithmic match
        
        var icon: String {
            switch self {
            case .equipmentVariant: return "arrow.triangle.swap"
            case .adjacentFamily: return "figure.strengthtraining.traditional"
            case .complementary: return "sparkles"
            case .similar: return "arrow.triangle.2.circlepath"
            }
        }
        
        var color: String {
            switch self {
            case .equipmentVariant: return "blue"
            case .adjacentFamily: return "indigo"
            case .complementary: return "purple"
            case .similar: return "gray"
            }
        }
    }
}

// MARK: - Swap Section for UI

struct SwapSection: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let icon: String
    let suggestions: [SwapSuggestion]
}

// MARK: - Exercise Swap Service

@MainActor
final class ExerciseSwapService: ObservableObject {
    static let shared = ExerciseSwapService()
    
    /// Pre-computed swap graph: exerciseId -> (equipmentVariants, complementary, fallback)
    private var swapCache: [UUID: CachedSwaps] = [:]
    private var cacheUserGoal: String = ""
    private var cacheUserEquipment: [String] = []
    
    struct CachedSwaps {
        let equipmentVariants: [SwapSuggestion]
        let complementary: [SwapSuggestion]
        let fallback: [SwapSuggestion]
    }
    
    // MARK: - Cohort Ranking Constants
    //
    // Equipment-cohort biasing for swap ranking. Per Fitness Expert ruling
    // 2026-05-04 — when the user picks a Machine variant they're picking
    // for stability/joint feel; surfacing a Barbell variant of the same
    // family violates that intent. Bias values are additive on the same
    // priority axis as `priority<Goal>` (0-100 scale), so a same-cohort
    // candidate at priority 70 outranks a cross-cohort candidate at 85.
    //
    // Tunable: `sameCohortBonus` flips a 70-priority cable past an
    // 85-priority barbell while still letting two user-rejections
    // (swapPenalty grows ~20 per rejection) push the cable below.
    private static let sameCohortBonus: Double = 25
    private static let adjacentCohortBonus: Double = 8   // closeness >= 60
    private static let crossCohortBonus: Double = 0
    private static let olympicLiftBlock: Double = 1000   // hard-block when source isolation

    /// Olympic-lift family tokens (snake_case `exerciseFamily` values).
    /// Per FE invariant (beginner safety + appropriateness): never surface
    /// these as a swap for an isolation source. The user's reported case
    /// included "Olympic (Barbell) Hammer Curl" being suggested for
    /// Bicep Curl (Machine) — that's the literal anti-pattern.
    private static let olympicFamilies: Set<String> = [
        "clean", "snatch", "jerk",
        "clean_and_jerk", "hang_clean", "power_clean", "power_snatch",
        "muscle_snatch", "split_jerk", "push_jerk",
    ]

    /// Olympic-lift name keywords (catch catalog rows whose `exerciseFamily`
    /// isn't tagged — a Bicep Curl row whose `name` starts with "Olympic"
    /// must still be blocked when source is isolation).
    private static let olympicNameKeywords: Set<String> = [
        "olympic", "snatch", "clean and jerk", "hang clean", "power clean",
        "power snatch", "muscle snatch", "split jerk", "push jerk",
    ]

    private init() {
        AppLogger.debug("🔄 [SWAP SERVICE] Initialized", category: .workout)
    }

    /// Cohort bonus magnitude for a candidate against a source.
    /// Hard-block via large negative when candidate is an Olympic-lift
    /// family AND source is isolation (`is_compound = FALSE`).
    private func cohortAdjustment(
        for candidate: Exercise,
        source: Exercise,
        sourceCohort: ExerciseFilterService.EquipmentCohort,
        sourceIsCompound: Bool
    ) -> Double {
        // Olympic-lift hard-block against isolation source.
        if !sourceIsCompound {
            let candidateFamily = ((candidate.value(forKey: "exerciseFamily") as? String) ?? "").lowercased()
            if Self.olympicFamilies.contains(candidateFamily) {
                return -Self.olympicLiftBlock
            }
            let candidateName = (candidate.name ?? "").lowercased()
            if Self.olympicNameKeywords.contains(where: { candidateName.contains($0) }) {
                return -Self.olympicLiftBlock
            }
        }

        let candidateCategory = (candidate.value(forKey: "equipmentCategory") as? String)
            ?? candidate.equipment
        let candidateCohort = ExerciseFilterService.equipmentCohort(forCategory: candidateCategory)
        let closeness = ExerciseFilterService.cohortCloseness(sourceCohort, candidateCohort)
        if closeness >= 100 { return Self.sameCohortBonus }
        if closeness >= 60  { return Self.adjacentCohortBonus }
        return Self.crossCohortBonus
    }
    
    /// Pre-compute swap candidates for all exercises in a workout (call at workout start)
    func precomputeSwapGraph(
        for exercises: [Exercise],
        userGoal: String = "Build Muscle",
        userLocation: String = "gym",
        userEquipment: [String] = []
    ) {
        let startTime = CFAbsoluteTimeGetCurrent()
        swapCache.removeAll()
        cacheUserGoal = userGoal
        cacheUserEquipment = userEquipment
        
        for exercise in exercises {
            guard let exerciseId = exercise.id else { continue }
            let family = exercise.value(forKey: "exerciseFamily") as? String ?? ""
            let complementaryFamilies = exercise.value(forKey: "complementaryFamilies") as? String ?? ""
            
            let variants = getEquipmentVariants(
                for: exercise, family: family,
                userGoal: userGoal, userLocation: userLocation,
                userEquipment: userEquipment, excludeIds: [], limit: 5
            )
            let comps = getComplementaryExercises(
                for: exercise, complementaryFamilies: complementaryFamilies,
                userGoal: userGoal, userLocation: userLocation,
                userEquipment: userEquipment, excludeIds: [], limit: 5
            )
            let falls = getFallbackSuggestions(
                for: exercise, userEquipment: userEquipment,
                excludeIds: [], limit: 5
            )
            
            swapCache[exerciseId] = CachedSwaps(
                equipmentVariants: variants,
                complementary: comps,
                fallback: falls
            )
        }
        
        let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        AppLogger.debug("🔄 [SWAP SERVICE] Pre-computed swap graph for \(exercises.count) exercises in \(String(format: "%.0f", elapsed))ms", category: .workout)
    }
    
    /// Clear the cache (call on workout end)
    func clearSwapCache() {
        swapCache.removeAll()
    }
    
    // MARK: - Main Swap API
    
    /// Get organized swap suggestions for an exercise
    /// Returns sections: Equipment Variants (2) + Complementary (3)
    func getSwapSuggestions(
        for exercise: Exercise,
        userGoal: String = "Build Muscle",
        userLocation: String = "gym",
        userEquipment: [String] = [],
        excludeIds: Set<UUID> = []
    ) -> [SwapSection] {
        var sections: [SwapSection] = []
        
        // Get the exercise's family
        let family = exercise.value(forKey: "exerciseFamily") as? String ?? ""
        let complementaryFamiliesString = exercise.value(forKey: "complementaryFamilies") as? String ?? ""
        
        AppLogger.debug("🔄 [SWAP] Getting suggestions for: \(exercise.name ?? "Unknown")", category: .workout)
        AppLogger.debug("   Family: \(family)", category: .workout)
        AppLogger.debug("   Complementary: \(complementaryFamiliesString)", category: .workout)
        
        // Section 1: Equipment Variants (same movement, different equipment)
        let equipmentVariants = getEquipmentVariants(
            for: exercise,
            family: family,
            userGoal: userGoal,
            userLocation: userLocation,
            userEquipment: userEquipment,
            excludeIds: excludeIds,
            limit: 3
        )
        
        if !equipmentVariants.isEmpty {
            sections.append(SwapSection(
                title: "Same Exercise",
                subtitle: "Different equipment variation",
                icon: "arrow.triangle.swap",
                suggestions: equipmentVariants
            ))
        }

        // Section 2: Adjacent-Family Variations (different family, same primary muscle).
        // The "Reverse Curl / Hammer Curl / Preacher Curl" slot when source is
        // Bicep Curl — a different movement family that hits the same target.
        let adjacent = getAdjacentFamilyVariations(
            for: exercise,
            sourceFamily: family,
            userGoal: userGoal,
            userLocation: userLocation,
            userEquipment: userEquipment,
            excludeIds: excludeIds,
            limit: 4
        )

        if !adjacent.isEmpty {
            sections.append(SwapSection(
                title: "Same Muscle",
                subtitle: "Different exercise variation",
                icon: "figure.strengthtraining.traditional",
                suggestions: adjacent
            ))
        }

        // Section 3: Complementary Exercises (different movement, works well together)
        let complementary = getComplementaryExercises(
            for: exercise,
            complementaryFamilies: complementaryFamiliesString,
            userGoal: userGoal,
            userLocation: userLocation,
            userEquipment: userEquipment,
            excludeIds: excludeIds,
            limit: 4
        )
        
        if !complementary.isEmpty {
            sections.append(SwapSection(
                title: "Different Exercise",
                subtitle: "Complementary movements",
                icon: "sparkles",
                suggestions: complementary
            ))
        }
        
        // Fallback: If no suggestions found, use algorithmic matching
        if sections.isEmpty {
            let fallback = getFallbackSuggestions(
                for: exercise,
                userEquipment: userEquipment,
                excludeIds: excludeIds,
                limit: 5
            )
            
            if !fallback.isEmpty {
                sections.append(SwapSection(
                    title: "Similar Exercises",
                    subtitle: "Based on movement pattern",
                    icon: "arrow.triangle.2.circlepath",
                    suggestions: fallback
                ))
            }
        }
        
        AppLogger.debug("🔄 [SWAP] Found \(sections.count) sections with \(sections.reduce(0) { $0 + $1.suggestions.count }) total suggestions", category: .workout)
        
        return sections
    }
    
    /// Get a single best swap (for quick shuffle button)
    /// Uses pre-computed cache when available for instant results
    func getQuickSwap(
        for exercise: Exercise,
        swapCount: Int,
        userGoal: String = "Build Muscle",
        userLocation: String = "gym",
        userEquipment: [String] = [],
        previousSwapIds: Set<UUID> = []
    ) -> Exercise? {
        var excludeIds = previousSwapIds
        if let id = exercise.id {
            excludeIds.insert(id)
        }
        
        // Try cache first for instant results
        if let exerciseId = exercise.id, let cached = swapCache[exerciseId] {
            return getQuickSwapFromCache(cached, swapCount: swapCount, excludeIds: excludeIds)
        }
        
        // Cache miss: compute on-demand (original behavior)
        let family = exercise.value(forKey: "exerciseFamily") as? String ?? ""
        let complementaryFamiliesString = exercise.value(forKey: "complementaryFamilies") as? String ?? ""
        
        // Swap 1-2: Equipment variants
        if swapCount < 3 {
            let variants = getEquipmentVariants(
                for: exercise,
                family: family,
                userGoal: userGoal,
                userLocation: userLocation,
                userEquipment: userEquipment,
                excludeIds: excludeIds,
                limit: 1
            )
            
            if let first = variants.first {
                AppLogger.debug("🔄 [QUICK SWAP] Swap #\(swapCount): Equipment variant - \(first.exercise.name ?? "")", category: .workout)
                return first.exercise
            }
        }
        
        // Swap 3+: Complementary exercise (user doesn't want this movement)
        let complementary = getComplementaryExercises(
            for: exercise,
            complementaryFamilies: complementaryFamiliesString,
            userGoal: userGoal,
            userLocation: userLocation,
            userEquipment: userEquipment,
            excludeIds: excludeIds,
            limit: 1
        )
        
        if let first = complementary.first {
            AppLogger.debug("🔄 [QUICK SWAP] Swap #\(swapCount): Complementary - \(first.exercise.name ?? "")", category: .workout)
            return first.exercise
        }
        
        // Fallback to algorithmic
        let fallback = getFallbackSuggestions(
            for: exercise,
            userEquipment: userEquipment,
            excludeIds: excludeIds,
            limit: 1
        )
        
        return fallback.first?.exercise
    }
    
    /// Select best swap from pre-computed cache, respecting tier logic and exclusions
    private func getQuickSwapFromCache(_ cached: CachedSwaps, swapCount: Int, excludeIds: Set<UUID>) -> Exercise? {
        let filterExcluded: (SwapSuggestion) -> Bool = { suggestion in
            guard let id = suggestion.exercise.id else { return false }
            return !excludeIds.contains(id)
        }
        
        // Swap 1-2: prefer equipment variants
        if swapCount < 3 {
            if let match = cached.equipmentVariants.first(where: filterExcluded) {
                AppLogger.debug("🔄 [QUICK SWAP] Cache hit - Swap #\(swapCount): Equipment variant - \(match.exercise.name ?? "")", category: .workout)
                return match.exercise
            }
        }
        
        // Swap 3+: prefer complementary
        if let match = cached.complementary.first(where: filterExcluded) {
            AppLogger.debug("🔄 [QUICK SWAP] Cache hit - Swap #\(swapCount): Complementary - \(match.exercise.name ?? "")", category: .workout)
            return match.exercise
        }
        
        // Fallback from cache
        if let match = cached.fallback.first(where: filterExcluded) {
            AppLogger.debug("🔄 [QUICK SWAP] Cache hit - Swap #\(swapCount): Fallback - \(match.exercise.name ?? "")", category: .workout)
            return match.exercise
        }
        
        return nil
    }
    
    // MARK: - Private Methods
    
    /// Get equipment variants (same family, different equipment).
    ///
    /// Cohort-biased ranking (FE ruling 2026-05-04): same-cohort candidates
    /// get +25 priority, adjacent-cohort +8, cross-cohort 0. Olympic-lift
    /// families are hard-blocked when source is isolation. Effect: a Machine
    /// source surfaces Cable variants before Barbell variants of the same
    /// family, even when the Barbell entries score higher on the catalog
    /// `priority<Goal>` column. Tunable via `sameCohortBonus` constant.
    private func getEquipmentVariants(
        for exercise: Exercise,
        family: String,
        userGoal: String,
        userLocation: String,
        userEquipment: [String],
        excludeIds: Set<UUID>,
        limit: Int
    ) -> [SwapSuggestion] {
        guard !family.isEmpty else { return [] }
        
        let allExercises = ExerciseLibraryService.shared.getAllExercises()
        
        let priorityKey = getPriorityKey(userGoal: userGoal, userLocation: userLocation)
        let sourceCategory = (exercise.value(forKey: "equipmentCategory") as? String) ?? exercise.equipment
        let sourceCohort = ExerciseFilterService.equipmentCohort(forCategory: sourceCategory)
        let sourceIsCompound = (exercise.value(forKey: "isCompound") as? Bool) ?? true
        
        var variants = allExercises.filter { candidate in
            guard let candidateId = candidate.id,
                  candidateId != exercise.id,
                  !excludeIds.contains(candidateId) else { return false }
            
            let candidateFamily = candidate.value(forKey: "exerciseFamily") as? String ?? ""
            return candidateFamily == family
        }
        
        if !userEquipment.isEmpty {
            // Bug-intel `bb7d7da0` (FE invariant 25 — equipment must match user
            // inventory). The previous filter compared the snake_case
            // `equipmentCategory` field against the user's display-name
            // selection list ("Dumbbells", "Cables") and silently bypassed
            // missing-category rows by defaulting to "bodyweight" — which
            // let Barbell-only exercises with a NULL `equipmentCategory`
            // leak through as if they were bodyweight. Route through the
            // canonical `userHasRequiredEquipment` filter (same one the
            // auto-gen path uses) so plural/singular, snake_case → display,
            // and "bench-implied-by-machines" cases resolve identically.
            variants = variants.filter { candidate in
                ExerciseFilterService.userHasRequiredEquipment(
                    exerciseEquipment: candidate.equipment,
                    exerciseName: candidate.name,
                    userEquipment: userEquipment
                )
            }
        }
        
        let scored: [(Exercise, Double)] = variants.map { candidate in
            let priority = Double((candidate.value(forKey: priorityKey) as? Int) ?? 70)
            let penalty = UserBehaviorLearningEngine.swapPenalty(for: candidate.name ?? "")
            let cohortBonus = cohortAdjustment(
                for: candidate,
                source: exercise,
                sourceCohort: sourceCohort,
                sourceIsCompound: sourceIsCompound
            )
            return (candidate, priority - penalty + cohortBonus)
        }
        // Drop hard-blocked candidates entirely (negative cohortBonus pushes
        // their score below zero — there's no realistic priority/penalty
        // combo that recovers a -1000 hit).
        .filter { $0.1 > -500 }
        .sorted { $0.1 > $1.1 }
        
        return scored.prefix(limit).map { (candidate, score) in
            let equipCat = candidate.value(forKey: "equipmentCategory") as? String ?? "bodyweight"
            return SwapSuggestion(
                exercise: candidate,
                swapType: .equipmentVariant,
                reason: "\(equipCat.capitalized) variation",
                priorityScore: Int(score)
            )
        }
    }
    
    /// Get complementary exercises (different family)
    private func getComplementaryExercises(
        for exercise: Exercise,
        complementaryFamilies: String,
        userGoal: String,
        userLocation: String,
        userEquipment: [String],
        excludeIds: Set<UUID>,
        limit: Int
    ) -> [SwapSuggestion] {
        guard !complementaryFamilies.isEmpty else { return [] }
        
        // Parse complementary families
        let families = complementaryFamilies
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        
        guard !families.isEmpty else { return [] }
        
        let allExercises = ExerciseLibraryService.shared.getAllExercises()
        let priorityKey = getPriorityKey(userGoal: userGoal, userLocation: userLocation)
        
        // Get exercises from complementary families
        var complementary = allExercises.filter { candidate in
            guard let candidateId = candidate.id,
                  candidateId != exercise.id,
                  !excludeIds.contains(candidateId) else { return false }
            
            let candidateFamily = (candidate.value(forKey: "exerciseFamily") as? String ?? "").lowercased()
            return families.contains(candidateFamily)
        }
        
        // Filter by user equipment via the canonical
        // `userHasRequiredEquipment` filter (bug-intel `bb7d7da0`, see note
        // in `getEquipmentVariants`). Reads the actual `equipment` field
        // (which carries the full requirement string, e.g.
        // "Barbell, Bench") — unlike `equipmentCategory` which can be NULL
        // for legacy rows and was silently treated as "bodyweight".
        if !userEquipment.isEmpty {
            complementary = complementary.filter { candidate in
                ExerciseFilterService.userHasRequiredEquipment(
                    exerciseEquipment: candidate.equipment,
                    exerciseName: candidate.name,
                    userEquipment: userEquipment
                )
            }
        }
        
        // Prefer primary variants of each family
        var seenFamilies: Set<String> = []
        var primaryFirst: [Exercise] = []
        var others: [Exercise] = []
        
        for candidate in complementary {
            let family = (candidate.value(forKey: "exerciseFamily") as? String ?? "").lowercased()
            let isPrimary = (candidate.value(forKey: "isEquipmentPrimary") as? Bool) ?? false
            
            if isPrimary && !seenFamilies.contains(family) {
                primaryFirst.append(candidate)
                seenFamilies.insert(family)
            } else {
                others.append(candidate)
            }
        }
        
        // Combine and sort (priority + swap penalty + cohort bonus reduced
        // by half — cohort matters less for "totally different exercise"
        // rows than for equipment variants per FE ruling).
        let sourceCategory = (exercise.value(forKey: "equipmentCategory") as? String) ?? exercise.equipment
        let sourceCohort = ExerciseFilterService.equipmentCohort(forCategory: sourceCategory)
        let sourceIsCompound = (exercise.value(forKey: "isCompound") as? Bool) ?? true

        let combined = primaryFirst + others
        let scored: [(Exercise, Double)] = combined.map { candidate in
            let priority = Double((candidate.value(forKey: priorityKey) as? Int) ?? 70)
            let penalty = UserBehaviorLearningEngine.swapPenalty(for: candidate.name ?? "")
            let cohortBonus = cohortAdjustment(
                for: candidate,
                source: exercise,
                sourceCohort: sourceCohort,
                sourceIsCompound: sourceIsCompound
            ) * 0.4   // half-strength bias for complementary slot
            return (candidate, priority - penalty + cohortBonus)
        }
        .filter { $0.1 > -500 }
        .sorted { $0.1 > $1.1 }

        return scored.prefix(limit).map { (candidate, score) in
            let baseName = candidate.value(forKey: "baseExerciseName") as? String ?? candidate.name ?? ""
            return SwapSuggestion(
                exercise: candidate,
                swapType: .complementary,
                reason: baseName,
                priorityScore: Int(score)
            )
        }
    }

    /// Get adjacent-family variations: exercises in a DIFFERENT
    /// `exerciseFamily` that share the source's #1 primary muscle.
    /// This is the "Reverse Curl / Hammer Curl / Preacher Curl" slot when
    /// the source is `Bicep Curl (Machine)` — same target muscle, different
    /// movement family, NOT a complementary pairing.
    ///
    /// Excludes families already listed in source's `complementaryFamilies`
    /// so the slate's Row 2 and Row 3 don't collide. Same cohort bias as
    /// equipment variants (preferred but not required).
    private func getAdjacentFamilyVariations(
        for exercise: Exercise,
        sourceFamily: String,
        userGoal: String,
        userLocation: String,
        userEquipment: [String],
        excludeIds: Set<UUID>,
        limit: Int
    ) -> [SwapSuggestion] {
        // The Core Data `Exercise` entity attribute is `muscleGroups`
        // (Transformable NSArray of String) — there is NO `primaryMuscles`
        // KVC key. The previous `value(forKey: "primaryMuscles")` raised
        // NSUnknownKeyException → SIGABRT every time the user opened the
        // Custom Workout Builder's overdue suggestions sheet (bug-intel
        // `1a0c9263`, REGRESSED on build 1.39 (68) after a fix that
        // didn't hold). Read via the typed accessor like the rest of the
        // codebase (`WorkoutGeneratorService`, `ProgramGenerationAudit`,
        // `ActiveWorkoutView+Persistence`).
        let primaryMuscles = ((exercise.muscleGroups as? [String]) ?? [])
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }
        guard let topMuscle = primaryMuscles.first else { return [] }

        // Exclude families that are already in the complementaryFamilies CSV
        // (they belong on Row 3 — don't surface them twice).
        let complementaryFamiliesString = (exercise.value(forKey: "complementaryFamilies") as? String) ?? ""
        let complementarySet: Set<String> = Set(
            complementaryFamiliesString
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
                .filter { !$0.isEmpty }
        )

        let sourceFamilyLower = sourceFamily.lowercased()
        let priorityKey = getPriorityKey(userGoal: userGoal, userLocation: userLocation)
        let sourceCategory = (exercise.value(forKey: "equipmentCategory") as? String) ?? exercise.equipment
        let sourceCohort = ExerciseFilterService.equipmentCohort(forCategory: sourceCategory)
        let sourceIsCompound = (exercise.value(forKey: "isCompound") as? Bool) ?? true

        let allExercises = ExerciseLibraryService.shared.getAllExercises()

        var candidates = allExercises.filter { candidate in
            guard let candidateId = candidate.id,
                  candidateId != exercise.id,
                  !excludeIds.contains(candidateId) else { return false }
            let candidateFamily = ((candidate.value(forKey: "exerciseFamily") as? String) ?? "").lowercased()
            if candidateFamily.isEmpty { return false }
            if candidateFamily == sourceFamilyLower { return false }
            if complementarySet.contains(candidateFamily) { return false }
            // Same fix as the source-side read above — typed accessor on
            // the canonical `muscleGroups` attribute, NOT KVC on a non-
            // existent `primaryMuscles` key. (bug-intel `1a0c9263`)
            let candidateMuscles = ((candidate.muscleGroups as? [String]) ?? [])
                .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            return candidateMuscles.contains(topMuscle)
        }

        if !userEquipment.isEmpty {
            // Bug-intel `bb7d7da0` — same canonical `userHasRequiredEquipment`
            // gate as `getEquipmentVariants` / `getComplementaryExercises`.
            candidates = candidates.filter { candidate in
                ExerciseFilterService.userHasRequiredEquipment(
                    exerciseEquipment: candidate.equipment,
                    exerciseName: candidate.name,
                    userEquipment: userEquipment
                )
            }
        }

        // Prefer one entry per (different) family — primary variant first.
        var seenFamilies: Set<String> = []
        var primaryFirst: [Exercise] = []
        var others: [Exercise] = []
        for candidate in candidates {
            let family = ((candidate.value(forKey: "exerciseFamily") as? String) ?? "").lowercased()
            let isPrimary = (candidate.value(forKey: "isEquipmentPrimary") as? Bool) ?? false
            if isPrimary && !seenFamilies.contains(family) {
                primaryFirst.append(candidate)
                seenFamilies.insert(family)
            } else {
                others.append(candidate)
            }
        }

        let combined = primaryFirst + others
        let scored: [(Exercise, Double)] = combined.map { candidate in
            let priority = Double((candidate.value(forKey: priorityKey) as? Int) ?? 70)
            let penalty = UserBehaviorLearningEngine.swapPenalty(for: candidate.name ?? "")
            let cohortBonus = cohortAdjustment(
                for: candidate,
                source: exercise,
                sourceCohort: sourceCohort,
                sourceIsCompound: sourceIsCompound
            )
            return (candidate, priority - penalty + cohortBonus)
        }
        .filter { $0.1 > -500 }
        .sorted { $0.1 > $1.1 }

        return scored.prefix(limit).map { (candidate, score) in
            let baseName = candidate.value(forKey: "baseExerciseName") as? String ?? candidate.name ?? ""
            return SwapSuggestion(
                exercise: candidate,
                swapType: .adjacentFamily,
                reason: baseName,
                priorityScore: Int(score)
            )
        }
    }
    
    /// Fallback to algorithmic matching (adjusted by swap history)
    private func getFallbackSuggestions(
        for exercise: Exercise,
        userEquipment: [String],
        excludeIds: Set<UUID>,
        limit: Int
    ) -> [SwapSuggestion] {
        let alternatives = SmartExercisePairingEngine.shared.getAlternatives(
            for: exercise,
            userEquipment: userEquipment,
            excludeIds: excludeIds,
            maxResults: limit + 3
        )
        
        return alternatives.map { alt in
            let penalty = UserBehaviorLearningEngine.swapPenalty(for: alt.exercise.name ?? "")
            return SwapSuggestion(
                exercise: alt.exercise,
                swapType: .similar,
                reason: alt.reasonsSummary,
                priorityScore: alt.score - Int(penalty)
            )
        }
        .sorted { $0.priorityScore > $1.priorityScore }
        .prefix(limit)
        .map { $0 }
    }
    
    /// Get the priority key based on user context
    private func getPriorityKey(userGoal: String, userLocation: String) -> String {
        if userLocation.lowercased() == "home" {
            return "priorityHome"
        }
        
        switch userGoal.lowercased() {
        case "get lean", "fat loss", "lose weight":
            return "priorityGetLean"
        case "build muscle", "hypertrophy", "muscle":
            return "priorityBuildMuscle"
        default:
            return "priorityGym"
        }
    }
}
