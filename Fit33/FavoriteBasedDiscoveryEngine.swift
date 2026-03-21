//
//  FavoriteBasedDiscoveryEngine.swift
//  GoFit
//
//  Smart engine that uses favorites as seeds to recommend:
//  - The actual favorite (sometimes)
//  - Similar exercises for variety
//  - New exercises to discover based on patterns the user enjoys
//

import Foundation
import CoreData

class FavoriteBasedDiscoveryEngine {
    static let shared = FavoriteBasedDiscoveryEngine()
    
    private var recentlyUsedFavorites: [String: Date] = [:]
    private var recentlyUsedVariants: [String: Date] = [:]
    private var discoveredExercises: Set<String> = []
    
    private let actualFavoriteChance: Double = 0.35
    private let similarExerciseChance: Double = 0.40
    private let discoveryChance: Double = 0.25
    private let cooldownDays: Int = 3
    private let maxFavoritesPerWorkout: Int = 2
    
    private static let favoriteCooldownKey = "FavoriteDiscovery_favoriteCooldowns"
    private static let variantCooldownKey = "FavoriteDiscovery_variantCooldowns"
    private static let discoveredKey = "FavoriteDiscovery_discovered"
    
    private init() {
        loadState()
    }
    
    // MARK: - Main API
    
    struct FavoriteRecommendation {
        let exerciseName: String
        let type: RecommendationType
        let basedOnFavorite: String  // Which favorite this is based on
        let similarityScore: Double   // 0-1 how similar to the favorite
        let reason: String
    }
    
    enum RecommendationType {
        case actualFavorite      // The exact favorite exercise
        case similarVariant      // Same muscle, similar movement, maybe different equipment
        case equipmentVariant    // Same exercise concept, different equipment
        case progressionVariant  // Harder/easier version
        case discovery           // New exercise to try based on user's taste profile
    }
    
    /// Get smart recommendations based on user's favorites for a given muscle group
    func getSmartRecommendations(
        forMuscleGroups muscles: [String],
        availableEquipment: [String],
        maxRecommendations: Int = 3,
        userLevel: String = "Intermediate"
    ) -> [FavoriteRecommendation] {
        
        // Get user's favorites that match the target muscles
        let matchingFavorites = getMatchingFavorites(forMuscles: muscles)
        
        guard !matchingFavorites.isEmpty else {
            AppLogger.debug("🎯 [FAVORITES] No matching favorites for \(muscles)", category: .workout)
            return []
        }
        
        AppLogger.debug("🎯 [FAVORITES] Found \(matchingFavorites.count) matching favorites for \(muscles)", category: .workout)
        
        var recommendations: [FavoriteRecommendation] = []
        var usedExercises: Set<String> = []
        
        // Shuffle favorites for variety
        let shuffledFavorites = matchingFavorites.shuffled()
        
        for favorite in shuffledFavorites.prefix(maxFavoritesPerWorkout) {
            guard recommendations.count < maxRecommendations else { break }
            
            // Decide what type of recommendation to make
            let roll = Double.random(in: 0...1)
            
            if roll < actualFavoriteChance && !isOnCooldown(favorite.name ?? "") {
                // Use the actual favorite
                if let name = favorite.name, !usedExercises.contains(name) {
                    recommendations.append(FavoriteRecommendation(
                        exerciseName: name,
                        type: .actualFavorite,
                        basedOnFavorite: name,
                        similarityScore: 1.0,
                        reason: "Your favorite! ⭐"
                    ))
                    usedExercises.insert(name)
                    markAsUsed(name, isFavorite: true)
                }
            } else if roll < actualFavoriteChance + similarExerciseChance {
                // Find a similar exercise
                if let similar = findSimilarExercise(
                    to: favorite,
                    availableEquipment: availableEquipment,
                    excluding: usedExercises,
                    userLevel: userLevel
                ) {
                    recommendations.append(similar)
                    usedExercises.insert(similar.exerciseName)
                    markAsUsed(similar.exerciseName, isFavorite: false)
                }
            } else {
                // Discovery - find something new but related
                if let discovery = findDiscoveryExercise(
                    basedOn: favorite,
                    availableEquipment: availableEquipment,
                    excluding: usedExercises,
                    userLevel: userLevel
                ) {
                    recommendations.append(discovery)
                    usedExercises.insert(discovery.exerciseName)
                    discoveredExercises.insert(discovery.exerciseName)
                    saveState()
                }
            }
        }
        
        AppLogger.debug("🎯 [FAVORITES] Generated \(recommendations.count) smart recommendations", category: .workout)
        for rec in recommendations {
            AppLogger.debug("   - \(rec.exerciseName) (\(rec.type)) based on '\(rec.basedOnFavorite)'", category: .workout)
        }
        
        return recommendations
    }
    
    /// Get a score boost for an exercise based on favorites
    /// Returns 0 if not related to favorites, higher scores for favorites/variants
    func getFavoriteBasedScore(for exerciseName: String, targetMuscles: [String]) -> Double {
        let matchingFavorites = getMatchingFavorites(forMuscles: targetMuscles)
        
        // Check if this IS a favorite
        if matchingFavorites.contains(where: { $0.name?.lowercased() == exerciseName.lowercased() }) {
            // Actual favorite - but reduce score if used recently
            if isOnCooldown(exerciseName) {
                return 50 // Reduced score when on cooldown
            }
            return 180 // High score but not guaranteed
        }
        
        // Check if this is similar to any favorites
        for favorite in matchingFavorites {
            guard let favName = favorite.name else { continue }
            
            let substitutes = ExerciseMappingService.shared.getSubstitutes(
                for: favName,
                availableEquipment: [] // Get all substitutes
            )
            
            if let match = substitutes.first(where: { 
                $0.exerciseName.lowercased() == exerciseName.lowercased() 
            }) {
                // Similar to a favorite
                let baseScore = 100.0 * match.similarityScore
                
                // Boost if this is a new discovery for the user
                if !discoveredExercises.contains(exerciseName.lowercased()) {
                    return baseScore + 30 // Discovery bonus
                }
                
                return baseScore
            }
        }
        
        return 0
    }
    
    // MARK: - Private Helpers
    
    private func getMatchingFavorites(forMuscles muscles: [String]) -> [Exercise] {
        let allExercises = ExerciseLibraryService.shared.getAllExercises()
        let normalizedMuscles = muscles.map { $0.lowercased() }
        
        return allExercises.filter { exercise in
            guard exercise.isFavorite else { return false }
            
            // Check if exercise targets any of the requested muscles
            // muscleGroups is a Transformable (NSObject) - use helper or cast
            let muscleGroupsArray = exercise.getMuscleGroups() ?? []
            let exerciseMuscles = muscleGroupsArray.joined(separator: ",").lowercased()
            let category = (exercise.category ?? "").lowercased()
            
            return normalizedMuscles.contains { muscle in
                exerciseMuscles.contains(muscle) || category.contains(muscle) ||
                muscle.contains(category)
            }
        }
    }
    
    private func findSimilarExercise(
        to favorite: Exercise,
        availableEquipment: [String],
        excluding: Set<String>,
        userLevel: String
    ) -> FavoriteRecommendation? {
        guard let favName = favorite.name else { return nil }
        
        // Get substitutes from the mapping service
        let substitutes = ExerciseMappingService.shared.getSubstitutes(
            for: favName,
            availableEquipment: availableEquipment
        )
        
        // Filter out excluded and recently used
        let validSubstitutes = substitutes.filter { sub in
            !excluding.contains(sub.exerciseName) &&
            !isOnCooldown(sub.exerciseName)
        }
        
        // Prefer substitutes with different equipment for variety
        let differentEquipment = validSubstitutes.filter { sub in
            sub.equipment.lowercased() != (favorite.equipment ?? "").lowercased()
        }
        
        // Pick one - prefer different equipment for variety
        let candidates = differentEquipment.isEmpty ? validSubstitutes : differentEquipment
        
        // Weight by similarity score with some randomness
        guard let chosen = weightedRandomSelection(from: candidates) else { return nil }
        
        let type: RecommendationType = {
            if chosen.equipment.lowercased() != (favorite.equipment ?? "").lowercased() {
                return .equipmentVariant
            }
            return .similarVariant
        }()
        
        return FavoriteRecommendation(
            exerciseName: chosen.exerciseName,
            type: type,
            basedOnFavorite: favName,
            similarityScore: chosen.similarityScore,
            reason: "Similar to \(favName) 🔄"
        )
    }
    
    private func findDiscoveryExercise(
        basedOn favorite: Exercise,
        availableEquipment: [String],
        excluding: Set<String>,
        userLevel: String
    ) -> FavoriteRecommendation? {
        guard let favName = favorite.name else { return nil }
        
        // Get all exercises from the library
        let allExercises = ExerciseLibraryService.shared.getAllExercises()
        
        // Find exercises with same primary muscle but different movement pattern
        let favMuscleGroups = favorite.getMuscleGroups() ?? []
        let favCategory = (favorite.category ?? "").lowercased()
        let primaryMuscle = favMuscleGroups.first?.lowercased() ?? favCategory
        
        let candidates = allExercises.filter { ex in
            guard let name = ex.name else { return false }
            
            // Must not be excluded
            guard !excluding.contains(name) else { return false }
            
            // Must not be the favorite itself
            guard name.lowercased() != favName.lowercased() else { return false }
            
            // Must not be on cooldown
            guard !isOnCooldown(name) else { return false }
            
            // Prefer exercises user hasn't seen yet
            if discoveredExercises.contains(name.lowercased()) { return false }
            
            // Must match equipment
            let exEquipment = (ex.equipment ?? "").lowercased()
            let equipmentMatch = availableEquipment.isEmpty || 
                availableEquipment.contains { $0.lowercased() == exEquipment || exEquipment.contains($0.lowercased()) }
            guard equipmentMatch else { return false }
            
            // Must target same muscle group
            let exMuscleGroups = ex.getMuscleGroups() ?? []
            let exCategory = (ex.category ?? "").lowercased()
            let exMuscle = exMuscleGroups.first?.lowercased() ?? exCategory
            return exMuscle.contains(primaryMuscle) || primaryMuscle.contains(exMuscle) || exCategory == favCategory
        }
        
        // Prefer exercises that are NOT similar to any favorites (true discovery)
        let trulyNew = candidates.filter { ex in
            let substitutes = ExerciseMappingService.shared.getSubstitutes(
                for: favName,
                availableEquipment: []
            )
            return !substitutes.contains { $0.exerciseName.lowercased() == (ex.name ?? "").lowercased() }
        }
        
        let pool = trulyNew.isEmpty ? candidates : trulyNew
        guard let chosen = pool.randomElement(), let chosenName = chosen.name else { return nil }
        
        return FavoriteRecommendation(
            exerciseName: chosenName,
            type: .discovery,
            basedOnFavorite: favName,
            similarityScore: 0.5, // Medium similarity since it's the same muscle
            reason: "Try something new! ✨"
        )
    }
    
    private func weightedRandomSelection(from substitutes: [ExerciseMappingService.SubstitutionEntry]) -> ExerciseMappingService.SubstitutionEntry? {
        guard !substitutes.isEmpty else { return nil }
        
        // Create weighted probabilities based on similarity score
        let totalWeight = substitutes.reduce(0) { $0 + $1.similarityScore }
        let randomValue = Double.random(in: 0..<totalWeight)
        
        var cumulative = 0.0
        for sub in substitutes {
            cumulative += sub.similarityScore
            if randomValue < cumulative {
                return sub
            }
        }
        
        return substitutes.last
    }
    
    private func isOnCooldown(_ exerciseName: String) -> Bool {
        let normalized = exerciseName.lowercased()
        
        // Check favorites cooldown
        if let lastUsed = recentlyUsedFavorites[normalized] {
            let daysSinceUsed = Calendar.current.dateComponents([.day], from: lastUsed, to: Date()).day ?? 0
            if daysSinceUsed < cooldownDays {
                return true
            }
        }
        
        // Check variants cooldown
        if let lastUsed = recentlyUsedVariants[normalized] {
            let daysSinceUsed = Calendar.current.dateComponents([.day], from: lastUsed, to: Date()).day ?? 0
            if daysSinceUsed < cooldownDays {
                return true
            }
        }
        
        return false
    }
    
    private func markAsUsed(_ exerciseName: String, isFavorite: Bool) {
        let normalized = exerciseName.lowercased()
        
        if isFavorite {
            recentlyUsedFavorites[normalized] = Date()
        } else {
            recentlyUsedVariants[normalized] = Date()
        }
        saveState()
    }
    
    // MARK: - Persistence
    
    private func loadState() {
        let defaults = UserDefaults.standard
        if let dict = defaults.dictionary(forKey: Self.favoriteCooldownKey) as? [String: Date] {
            recentlyUsedFavorites = dict
        }
        if let dict = defaults.dictionary(forKey: Self.variantCooldownKey) as? [String: Date] {
            recentlyUsedVariants = dict
        }
        if let arr = defaults.stringArray(forKey: Self.discoveredKey) {
            discoveredExercises = Set(arr)
        }
    }
    
    private func saveState() {
        let defaults = UserDefaults.standard
        defaults.set(recentlyUsedFavorites as NSDictionary, forKey: Self.favoriteCooldownKey)
        defaults.set(recentlyUsedVariants as NSDictionary, forKey: Self.variantCooldownKey)
        defaults.set(Array(discoveredExercises), forKey: Self.discoveredKey)
    }
    
    func clearCooldowns() {
        recentlyUsedFavorites.removeAll()
        recentlyUsedVariants.removeAll()
        saveState()
        AppLogger.debug("🔄 [FAVORITES] Cooldowns cleared", category: .workout)
    }
    
    func getDiscoveredExercisesCount() -> Int {
        return discoveredExercises.count
    }
}

