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
        case complementary = "Complementary"          // Different family, works well together
        case similar = "Similar"                      // Fallback algorithmic match
        
        var icon: String {
            switch self {
            case .equipmentVariant: return "arrow.triangle.swap"
            case .complementary: return "sparkles"
            case .similar: return "arrow.triangle.2.circlepath"
            }
        }
        
        var color: String {
            switch self {
            case .equipmentVariant: return "blue"
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
    
    private init() {
        print("🔄 [SWAP SERVICE] Initialized")
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
        print("🔄 [SWAP SERVICE] Pre-computed swap graph for \(exercises.count) exercises in \(String(format: "%.0f", elapsed))ms")
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
        
        print("🔄 [SWAP] Getting suggestions for: \(exercise.name ?? "Unknown")")
        print("   Family: \(family)")
        print("   Complementary: \(complementaryFamiliesString)")
        
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
        
        // Section 2: Complementary Exercises (different movement, works well together)
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
        
        print("🔄 [SWAP] Found \(sections.count) sections with \(sections.reduce(0) { $0 + $1.suggestions.count }) total suggestions")
        
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
                print("🔄 [QUICK SWAP] Swap #\(swapCount): Equipment variant - \(first.exercise.name ?? "")")
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
            print("🔄 [QUICK SWAP] Swap #\(swapCount): Complementary - \(first.exercise.name ?? "")")
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
                print("🔄 [QUICK SWAP] Cache hit - Swap #\(swapCount): Equipment variant - \(match.exercise.name ?? "")")
                return match.exercise
            }
        }
        
        // Swap 3+: prefer complementary
        if let match = cached.complementary.first(where: filterExcluded) {
            print("🔄 [QUICK SWAP] Cache hit - Swap #\(swapCount): Complementary - \(match.exercise.name ?? "")")
            return match.exercise
        }
        
        // Fallback from cache
        if let match = cached.fallback.first(where: filterExcluded) {
            print("🔄 [QUICK SWAP] Cache hit - Swap #\(swapCount): Fallback - \(match.exercise.name ?? "")")
            return match.exercise
        }
        
        return nil
    }
    
    // MARK: - Private Methods
    
    /// Get equipment variants (same family, different equipment)
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
        
        // Get priority column based on context
        let priorityKey = getPriorityKey(userGoal: userGoal, userLocation: userLocation)
        
        // Filter to same family, different exercise
        var variants = allExercises.filter { candidate in
            guard let candidateId = candidate.id,
                  candidateId != exercise.id,
                  !excludeIds.contains(candidateId) else { return false }
            
            let candidateFamily = candidate.value(forKey: "exerciseFamily") as? String ?? ""
            return candidateFamily == family
        }
        
        // Filter by user equipment if provided
        if !userEquipment.isEmpty {
            let userEquipLower = Set(userEquipment.map { $0.lowercased() })
            variants = variants.filter { candidate in
                let equipCat = (candidate.value(forKey: "equipmentCategory") as? String ?? "bodyweight").lowercased()
                return userEquipLower.contains(equipCat) || equipCat == "bodyweight"
            }
        }
        
        // Sort by priority score adjusted by swap history penalty
        variants.sort { a, b in
            let aPriority = Double((a.value(forKey: priorityKey) as? Int) ?? 70)
            let bPriority = Double((b.value(forKey: priorityKey) as? Int) ?? 70)
            let aPenalty = UserBehaviorLearningEngine.swapPenalty(for: a.name ?? "")
            let bPenalty = UserBehaviorLearningEngine.swapPenalty(for: b.name ?? "")
            return (aPriority - aPenalty) > (bPriority - bPenalty)
        }
        
        // Convert to SwapSuggestions
        return variants.prefix(limit).map { candidate in
            let equipCat = candidate.value(forKey: "equipmentCategory") as? String ?? "bodyweight"
            let basePriority = Double((candidate.value(forKey: priorityKey) as? Int) ?? 70)
            let penalty = UserBehaviorLearningEngine.swapPenalty(for: candidate.name ?? "")
            
            return SwapSuggestion(
                exercise: candidate,
                swapType: .equipmentVariant,
                reason: "\(equipCat.capitalized) variation",
                priorityScore: Int(basePriority - penalty)
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
        
        // Filter by user equipment
        if !userEquipment.isEmpty {
            let userEquipLower = Set(userEquipment.map { $0.lowercased() })
            complementary = complementary.filter { candidate in
                let equipCat = (candidate.value(forKey: "equipmentCategory") as? String ?? "bodyweight").lowercased()
                return userEquipLower.contains(equipCat) || equipCat == "bodyweight"
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
        
        // Combine and sort (factoring in swap history penalty)
        let combined = primaryFirst + others
        let sorted = combined.sorted { a, b in
            let aPriority = Double((a.value(forKey: priorityKey) as? Int) ?? 70)
            let bPriority = Double((b.value(forKey: priorityKey) as? Int) ?? 70)
            let aPenalty = UserBehaviorLearningEngine.swapPenalty(for: a.name ?? "")
            let bPenalty = UserBehaviorLearningEngine.swapPenalty(for: b.name ?? "")
            return (aPriority - aPenalty) > (bPriority - bPenalty)
        }
        
        // Convert to SwapSuggestions
        return sorted.prefix(limit).map { candidate in
            let baseName = candidate.value(forKey: "baseExerciseName") as? String ?? candidate.name ?? ""
            let basePriority = Double((candidate.value(forKey: priorityKey) as? Int) ?? 70)
            let penalty = UserBehaviorLearningEngine.swapPenalty(for: candidate.name ?? "")
            
            return SwapSuggestion(
                exercise: candidate,
                swapType: .complementary,
                reason: baseName,
                priorityScore: Int(basePriority - penalty)
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
