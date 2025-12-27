//
//  SmartVariantRotationEngine.swift
//  GoFit
//
//  Lightweight engine that adds VARIANT ROTATION logic on top of existing data.
//  
//  DOES NOT STORE ITS OWN DATA - Uses existing sources:
//  - UserBehaviorLearningEngine: swaps, favorites, completions, recently done
//  - Core Data: workout history, exercise families
//  - ProgressiveExerciseUnlockService: user maturity
//
//  ONLY ADDS:
//  - Variant rotation tracking (which variant of a favorite family to show next)
//  - Session memory for workout-to-workout cohesion
//

import Foundation
import CoreData

// MARK: - Variant Rotation Tracking (NEW - not duplicated elsewhere)

/// Tracks which variants have been shown for a favorite family
/// So we can rotate through them instead of showing the same exercise
struct FamilyVariantRotation: Codable {
    var familyName: String
    var variantsShown: [String] = []  // Ordered list of variants we've shown
    var nextIndex: Int = 0            // Which variant to show next
}

// MARK: - Smart Variant Rotation Engine

@MainActor
class SmartVariantRotationEngine: ObservableObject {
    static let shared = SmartVariantRotationEngine()
    
    // MARK: - Only Store Variant Rotation (everything else from existing sources)
    @Published private(set) var familyRotations: [String: FamilyVariantRotation] = [:]
    
    // MARK: - References to Existing Data Sources
    private var learningEngine: UserBehaviorLearningEngine { UserBehaviorLearningEngine.shared }
    private var learningCache: LearningCacheStorage { LearningCacheStorage.shared }
    
    private init() {
        loadRotations()
    }
    
    // MARK: - Minimal Storage (just variant rotation)
    
    private func loadRotations() {
        if let data = UserDefaults.standard.data(forKey: "familyVariantRotations"),
           let rotations = try? JSONDecoder().decode([String: FamilyVariantRotation].self, from: data) {
            self.familyRotations = rotations
        }
        print("🔄 [VARIANT ENGINE] Loaded \(familyRotations.count) family rotations")
    }
    
    private func saveRotations() {
        if let data = try? JSONEncoder().encode(familyRotations) {
            UserDefaults.standard.set(data, forKey: "familyVariantRotations")
        }
    }
    
    // MARK: - Pull Data from Existing Sources
    
    /// Get swap data from UserBehaviorLearningEngine (already stored there)
    private func getSwapData(for exerciseName: String) -> ExerciseSwapData? {
        return learningCache.userPreferences?.swapHistory[exerciseName.lowercased()]
    }
    
    /// Check if exercise is favorited (from existing profile)
    private func isFavorited(_ exerciseName: String) -> Bool {
        return learningCache.userPreferences?.favoritedExerciseNames.contains(exerciseName.lowercased()) ?? false
    }
    
    /// Check if exercise was recently done (from existing profile)
    private func wasRecentlyDone(_ exerciseName: String) -> Bool {
        return learningCache.userPreferences?.recentlyDoneExercises.contains(exerciseName.lowercased()) ?? false
    }
    
    /// Check if user has done full sets of this exercise (from existing profile)
    private func hasCompletedFullSets(_ exerciseName: String) -> Bool {
        return learningCache.userPreferences?.fullSetExercises.contains(exerciseName.lowercased()) ?? false
    }
    
    /// Get completion count (from existing profile)
    private func getCompletionCount(_ exerciseName: String) -> Int {
        return learningCache.userPreferences?.exerciseCompletionCounts[exerciseName.lowercased()] ?? 0
    }
    
    // MARK: - Variant Rotation Logic (NEW functionality)
    
    /// Get the NEXT variant to show for a favorite exercise family
    /// This is the key new feature - rotate through variants instead of repeating
    func getNextVariantForFamily(
        family: String,
        availableVariants: [String],
        excludeRecent: Bool = true
    ) -> String? {
        guard !availableVariants.isEmpty else { return nil }
        
        let familyKey = family.lowercased()
        
        // Filter out recently done exercises if requested
        let candidates: [String]
        if excludeRecent {
            let recentlyDone = learningCache.userPreferences?.recentlyDoneExercises ?? []
            candidates = availableVariants.filter { !recentlyDone.contains($0.lowercased()) }
        } else {
            candidates = availableVariants
        }
        
        // If all filtered out, use original list
        let finalCandidates = candidates.isEmpty ? availableVariants : candidates
        
        // Get or create rotation tracking for this family
        var rotation = familyRotations[familyKey] ?? FamilyVariantRotation(familyName: familyKey)
        
        // Pick next variant in rotation
        let index = rotation.nextIndex % finalCandidates.count
        let nextVariant = finalCandidates[index]
        
        // Update rotation
        rotation.nextIndex = (index + 1) % finalCandidates.count
        if !rotation.variantsShown.contains(nextVariant.lowercased()) {
            rotation.variantsShown.append(nextVariant.lowercased())
        }
        familyRotations[familyKey] = rotation
        saveRotations()
        
        print("🔄 [VARIANT] Family '\(family)': showing '\(nextVariant)' (rotation index \(index))")
        return nextVariant
    }
    
    /// Record that we showed a specific variant (for tracking)
    func recordVariantShown(exerciseName: String, family: String) {
        let familyKey = family.lowercased()
        var rotation = familyRotations[familyKey] ?? FamilyVariantRotation(familyName: familyKey)
        
        if !rotation.variantsShown.contains(exerciseName.lowercased()) {
            rotation.variantsShown.append(exerciseName.lowercased())
        }
        familyRotations[familyKey] = rotation
        saveRotations()
    }
    
    // MARK: - Smart Scoring (Uses Existing Data)
    
    /// Calculate score boost/penalty based on user behavior
    /// Pulls from EXISTING data sources - no duplication
    func getSmartVariantScore(
        exerciseName: String,
        exerciseFamily: String,
        isFavorited: Bool = false
    ) -> Double {
        var score: Double = 0
        let exerciseKey = exerciseName.lowercased()
        let familyKey = exerciseFamily.lowercased()
        
        // ═══════════════════════════════════════════════════════════════
        // 1. SWAP BEHAVIOR (from UserBehaviorLearningEngine)
        // Only penalize after 3+ swaps - equipment might be busy!
        // ═══════════════════════════════════════════════════════════════
        if let swapData = getSwapData(for: exerciseKey) {
            // Penalty only after 3+ swaps FROM this exercise
            if swapData.swapCount >= 3 {
                let penalty = Double(swapData.swapCount - 2) * 15  // -15 per swap after 2nd
                score -= min(60, penalty)
                print("   ⚠️ [VARIANT] '\(exerciseName)': -\(Int(min(60, penalty))) (swapped \(swapData.swapCount)x)")
            }
            // No penalty for 1-2 swaps (equipment busy, broken, etc.)
            
            // Boost for exercises user swaps TO
            let swappedToCount = swapData.swappedTo.values.reduce(0, +)
            if swappedToCount > 0 {
                // This exercise is what others get swapped TO - user prefers it!
                score += min(40, Double(swappedToCount) * 15)
            }
        }
        
        // Also check if this exercise is frequently swapped TO from OTHER exercises
        let allSwapHistory = learningCache.userPreferences?.swapHistory ?? [:]
        var timesChosenAsReplacement = 0
        for (_, data) in allSwapHistory {
            timesChosenAsReplacement += data.swappedTo[exerciseKey] ?? 0
        }
        if timesChosenAsReplacement > 0 {
            score += min(50, Double(timesChosenAsReplacement) * 15)
            print("   ✅ [VARIANT] '\(exerciseName)': +\(Int(min(50, Double(timesChosenAsReplacement) * 15))) (chosen \(timesChosenAsReplacement)x as replacement)")
        }
        
        // ═══════════════════════════════════════════════════════════════
        // 2. FAVORITE FAMILY VARIANT ROTATION
        // If user favorites an exercise, show VARIANTS next time
        // ═══════════════════════════════════════════════════════════════
        let isInFavoriteFamily = self.isFavorited(exerciseKey) || isFavorited
        
        if isInFavoriteFamily || !familyKey.isEmpty {
            // Check if any exercise in this family is favorited
            let favoritedNames = learningCache.userPreferences?.favoritedExerciseNames ?? []
            let familyIsFavorited = isInFavoriteFamily // Could expand to check family
            
            if familyIsFavorited {
                if wasRecentlyDone(exerciseKey) {
                    // Same exercise used recently - penalize to encourage variants
                    score -= 40
                    print("   🔄 [VARIANT] '\(exerciseName)': -40 (favorite but used recently, show variant)")
                } else {
                    // Fresh variant of favorite family - boost!
                    score += 50
                    print("   ⭐ [VARIANT] '\(exerciseName)': +50 (fresh variant of favorite)")
                }
            }
        }
        
        // ═══════════════════════════════════════════════════════════════
        // 3. ENGAGEMENT HISTORY (from existing fullSetExercises)
        // ═══════════════════════════════════════════════════════════════
        if hasCompletedFullSets(exerciseKey) {
            // User has done full sets of this - they engage with it
            score += 20
        }
        
        // ═══════════════════════════════════════════════════════════════
        // 4. FRESHNESS (from existing recentlyDoneExercises)
        // ═══════════════════════════════════════════════════════════════
        if wasRecentlyDone(exerciseKey) && !isFavorited {
            // Recently done + not a favorite = reduce to add variety
            score -= 25
        }
        
        return score
    }
    
    // MARK: - Recording (Delegate to Existing Systems)
    
    /// Record favorite - delegates to existing systems, just tracks family rotation
    func recordFavorite(exerciseName: String, family: String) {
        // UserBehaviorLearningEngine already handles favorite tracking
        // We just ensure the family rotation is initialized
        let familyKey = family.lowercased()
        if familyRotations[familyKey] == nil {
            familyRotations[familyKey] = FamilyVariantRotation(familyName: familyKey)
            saveRotations()
        }
        print("⭐ [VARIANT] Initialized rotation for favorite family: \(family)")
    }
    
    /// Record unfavorite - no additional action needed, existing systems handle it
    func recordUnfavorite(exerciseName: String, family: String) {
        // UserBehaviorLearningEngine handles this
        print("⭐ [VARIANT] Unfavorite recorded for: \(exerciseName)")
    }
    
    /// Record swap - delegates to UserBehaviorLearningEngine (already handles this)
    func recordSwapFrom(exerciseName: String, toExercise: String) {
        // UserBehaviorLearningEngine.recordExerciseSwap already handles this!
        // This method exists just for API consistency
        print("🔄 [VARIANT] Swap tracked (via UserBehaviorLearningEngine)")
    }
    
    /// Record workout completion - for variant rotation tracking only
    func recordWorkoutCompletion(
        exercises: [(name: String, family: String, setsCompleted: Int, equipment: String)],
        musclesTrained: [String]
    ) {
        // UserBehaviorLearningEngine already tracks completions
        // We just update variant rotation for any exercises from favorite families
        for exercise in exercises {
            let familyKey = exercise.family.lowercased()
            if !familyKey.isEmpty {
                recordVariantShown(exerciseName: exercise.name, family: exercise.family)
            }
        }
        print("🔄 [VARIANT] Recorded \(exercises.count) exercises for variant rotation")
    }
    
    // MARK: - Debug
    
    func printDebugSummary() {
        let profile = learningCache.userPreferences
        print("""
        ╔══════════════════════════════════════════════════════════════╗
        ║         🔄 SMART VARIANT ROTATION ENGINE                     ║
        ╠══════════════════════════════════════════════════════════════╣
        ║ DATA FROM EXISTING SOURCES (not duplicated):
        ║   • Favorites: \(profile?.favoritedExerciseNames.count ?? 0)
        ║   • Swap History: \(profile?.swapHistory.count ?? 0) exercises
        ║   • Recently Done: \(profile?.recentlyDoneExercises.count ?? 0)
        ║   • Full Set Completions: \(profile?.fullSetExercises.count ?? 0)
        ║
        ║ NEW DATA (variant rotation only):
        ║   • Family Rotations: \(familyRotations.count)
        ╚══════════════════════════════════════════════════════════════╝
        """)
    }
    
    func reset() {
        familyRotations = [:]
        UserDefaults.standard.removeObject(forKey: "familyVariantRotations")
        print("🔄 [VARIANT ENGINE] Reset variant rotations (existing data preserved)")
    }
}
