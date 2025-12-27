//
//  AlternativeExerciseEngine.swift
//  GoFit
//
//  Smart alternative exercise matching engine
//  Provides intelligent suggestions when users want to swap exercises
//

import Foundation
import CoreData

/// Engine for finding smart alternative exercises based on the original exercise's characteristics
@MainActor
class AlternativeExerciseEngine {
    
    static let shared = AlternativeExerciseEngine()
    
    // MARK: - Muscle Group Expansions (for matching)
    
    private let muscleGroupExpansion: [String: Set<String>] = [
        "chest": ["chest", "pectorals", "pecs", "upper chest", "lower chest", "inner chest", "outer chest"],
        "back": ["back", "lats", "latissimus dorsi", "upper back", "lower back", "rhomboids", "traps", "trapezius", "mid back"],
        "shoulders": ["shoulders", "delts", "deltoids", "front delts", "rear delts", "side delts", "lateral delts"],
        "arms": ["arms", "biceps", "triceps", "forearms", "brachialis"],
        "biceps": ["biceps", "brachialis"],
        "triceps": ["triceps"],
        "forearms": ["forearms", "wrist flexors", "wrist extensors"],
        "legs": ["legs", "quads", "quadriceps", "hamstrings", "glutes", "calves", "adductors", "abductors"],
        "quads": ["quads", "quadriceps"],
        "hamstrings": ["hamstrings"],
        "glutes": ["glutes", "gluteus maximus", "gluteus medius"],
        "calves": ["calves", "gastrocnemius", "soleus"],
        "core": ["core", "abs", "abdominals", "obliques", "transverse abdominis"],
        "abs": ["abs", "abdominals", "rectus abdominis", "obliques"],
        "full body": ["full body", "compound"],
        "hips": ["hips", "hip flexors", "hip extensors", "glutes"]
    ]
    
    // MARK: - Equipment Categories
    
    private let equipmentCategories: [String: String] = [
        "barbell": "free_weights",
        "dumbbell": "free_weights",
        "dumbbells": "free_weights",
        "kettlebell": "free_weights",
        "ez bar": "free_weights",
        "ez-bar": "free_weights",
        "cable": "cables",
        "cables": "cables",
        "machine": "machines",
        "smith machine": "machines",
        "lever": "machines",
        "sled": "machines",
        "bodyweight": "bodyweight",
        "body weight": "bodyweight",
        "none": "bodyweight",
        "band": "resistance",
        "resistance band": "resistance",
        "suspension": "suspension",
        "trx": "suspension",
        "bench": "free_weights",
        "pull-up bar": "bodyweight"
    ]
    
    // MARK: - Public API
    
    /// Get smart alternative suggestions for an exercise
    /// - Parameters:
    ///   - exercise: The original exercise to find alternatives for
    ///   - userEquipment: Equipment available to the user
    ///   - excludeIds: Set of exercise IDs to exclude (already in workout or already shuffled)
    ///   - maxResults: Maximum number of alternatives to return
    /// - Returns: Array of scored alternative exercises, sorted by score (best first)
    func getAlternatives(
        for exercise: Exercise,
        userEquipment: [String],
        excludeIds: Set<UUID> = [],
        maxResults: Int = 5
    ) -> [ScoredAlternative] {
        let allExercises = ExerciseLibraryService.shared.getAllExercises()
        
        guard let originalName = exercise.name else { return [] }
        let originalId = exercise.id
        
        // Extract original exercise characteristics
        let originalMuscles = normalizeMuscles(exercise.getMuscleGroups() ?? [])
        let originalCategory = (exercise.category ?? "").lowercased()
        let originalEquipment = (exercise.equipment ?? "").lowercased()
        let originalMovementPattern = inferMovementPattern(originalName)
        let originalWorkoutType = (exercise.workoutType ?? "strength").lowercased()
        let originalForceType = (exercise.forceType ?? "").lowercased()
        let originalPlaneOfMotion = (exercise.planeOfMotion ?? "").lowercased()
        let originalBodyPosition = (exercise.bodyPosition ?? "").lowercased()
        let originalDifficulty = exercise.difficultyLevel
        
        // Normalize user equipment
        let normalizedUserEquipment = Set(userEquipment.map { $0.lowercased() })
        let userEquipmentCategories = Set(userEquipment.compactMap { getEquipmentCategory($0.lowercased()) })
        
        var scoredAlternatives: [ScoredAlternative] = []
        
        for candidate in allExercises {
            guard let candidateId = candidate.id,
                  let candidateName = candidate.name else { continue }
            
            // Skip original exercise and excluded ones
            if candidateId == originalId || excludeIds.contains(candidateId) { continue }
            
            // Skip if same exact exercise name
            if candidateName.lowercased() == originalName.lowercased() { continue }
            
            // Calculate score
            let (score, reasons) = calculateAlternativeScore(
                candidate: candidate,
                originalMuscles: originalMuscles,
                originalCategory: originalCategory,
                originalEquipment: originalEquipment,
                originalMovementPattern: originalMovementPattern,
                originalWorkoutType: originalWorkoutType,
                originalForceType: originalForceType,
                originalPlaneOfMotion: originalPlaneOfMotion,
                originalBodyPosition: originalBodyPosition,
                originalDifficulty: originalDifficulty,
                userEquipment: normalizedUserEquipment,
                userEquipmentCategories: userEquipmentCategories
            )
            
            // Only include if score is above threshold
            if score >= 30 {
                scoredAlternatives.append(ScoredAlternative(
                    exercise: candidate,
                    score: score,
                    reasons: reasons
                ))
            }
        }
        
        // Sort by score and take top results
        let sorted = scoredAlternatives.sorted { $0.score > $1.score }
        return Array(sorted.prefix(maxResults))
    }
    
    /// Get a single best alternative (for quick shuffle)
    func getBestAlternative(
        for exercise: Exercise,
        userEquipment: [String],
        excludeIds: Set<UUID> = []
    ) -> Exercise? {
        let alternatives = getAlternatives(
            for: exercise,
            userEquipment: userEquipment,
            excludeIds: excludeIds,
            maxResults: 3
        )
        
        // Add some randomness among top choices
        if alternatives.isEmpty { return nil }
        
        // Weight selection towards higher scores but allow variety
        let topCandidates = Array(alternatives.prefix(3))
        let weights = topCandidates.map { Double($0.score) }
        let totalWeight = weights.reduce(0, +)
        
        if totalWeight == 0 { return alternatives.first?.exercise }
        
        let randomValue = Double.random(in: 0..<totalWeight)
        var cumulative = 0.0
        
        for (index, weight) in weights.enumerated() {
            cumulative += weight
            if randomValue < cumulative {
                return topCandidates[index].exercise
            }
        }
        
        return alternatives.first?.exercise
    }
    
    // MARK: - Scoring Logic
    
    private func calculateAlternativeScore(
        candidate: Exercise,
        originalMuscles: Set<String>,
        originalCategory: String,
        originalEquipment: String,
        originalMovementPattern: String,
        originalWorkoutType: String,
        originalForceType: String,
        originalPlaneOfMotion: String,
        originalBodyPosition: String,
        originalDifficulty: Int16,
        userEquipment: Set<String>,
        userEquipmentCategories: Set<String>
    ) -> (Int, [String]) {
        
        var score = 50 // Base score
        var reasons: [String] = []
        
        let candidateName = (candidate.name ?? "").lowercased()
        let candidateEquipment = (candidate.equipment ?? "").lowercased()
        let candidateMuscles = normalizeMuscles(candidate.getMuscleGroups() ?? [])
        let candidateCategory = (candidate.category ?? "").lowercased()
        let candidateMovementPattern = inferMovementPattern(candidateName)
        let candidateWorkoutType = (candidate.workoutType ?? "strength").lowercased()
        let candidateForceType = (candidate.forceType ?? "").lowercased()
        let candidatePlaneOfMotion = (candidate.planeOfMotion ?? "").lowercased()
        let candidateBodyPosition = (candidate.bodyPosition ?? "").lowercased()
        let candidateDifficulty = candidate.difficultyLevel
        
        // ═══════════════════════════════════════════════════════════════
        // EQUIPMENT COMPATIBILITY (Critical - can disqualify)
        // ═══════════════════════════════════════════════════════════════
        
        let candidateEquipmentCategory = getEquipmentCategory(candidateEquipment)
        
        // If user has specific equipment, candidate must be compatible
        if !userEquipment.isEmpty {
            let equipmentMatch = userEquipment.contains(candidateEquipment) ||
                                 candidateEquipment == "bodyweight" ||
                                 candidateEquipment == "none" ||
                                 candidateEquipment.isEmpty
            
            // Also check equipment category match
            let categoryMatch = candidateEquipmentCategory.map { userEquipmentCategories.contains($0) } ?? false
            
            if !equipmentMatch && !categoryMatch {
                // Major penalty for equipment mismatch
                score -= 60
                reasons.append("⚠️ Equipment not available")
            } else if equipmentMatch {
                score += 25
                reasons.append("✅ Equipment available")
            } else if categoryMatch {
                score += 15
                reasons.append("✅ Similar equipment category")
            }
        }
        
        // Bonus for matching original equipment (same experience)
        // Use equipment family-aware scoring for smarter substitutions
        if candidateEquipment == originalEquipment {
            score += 20
            reasons.append("🎯 Same equipment")
        } else {
            // Use EquipmentHierarchyService for family-aware scoring
            let familyScore = getEquipmentFamilyScore(original: originalEquipment, candidate: candidateEquipment)
            if familyScore.score != 0 {
                score += familyScore.score
                if !familyScore.reason.isEmpty {
                    reasons.append(familyScore.reason)
                }
            }
        }
        
        // ═══════════════════════════════════════════════════════════════
        // MOVEMENT PATTERN (Very Important)
        // ═══════════════════════════════════════════════════════════════
        
        if candidateMovementPattern == originalMovementPattern && originalMovementPattern != "other" {
            score += 35
            reasons.append("🎯 Same movement pattern (\(originalMovementPattern))")
        }
        
        // ═══════════════════════════════════════════════════════════════
        // PRIMARY MUSCLE TARGETING (Very Important)
        // ═══════════════════════════════════════════════════════════════
        
        let muscleOverlap = originalMuscles.intersection(candidateMuscles)
        if !muscleOverlap.isEmpty {
            let overlapRatio = Double(muscleOverlap.count) / Double(max(originalMuscles.count, 1))
            let muscleScore = Int(overlapRatio * 40)
            score += muscleScore
            reasons.append("💪 Targets same muscles (\(muscleOverlap.prefix(2).joined(separator: ", ")))")
        } else if originalCategory == candidateCategory {
            // Fallback to category match
            score += 15
            reasons.append("📂 Same category (\(originalCategory))")
        } else {
            // Penalty for different muscle group entirely
            score -= 20
            reasons.append("⚠️ Different muscle group")
        }
        
        // ═══════════════════════════════════════════════════════════════
        // WORKOUT TYPE (Important - strength vs cardio vs stretch)
        // ═══════════════════════════════════════════════════════════════
        
        if candidateWorkoutType != originalWorkoutType {
            // Significant penalty for type mismatch
            if originalWorkoutType == "strength" && (candidateWorkoutType == "cardio" || candidateWorkoutType == "plyometrics") {
                score -= 40
                reasons.append("⛔ Different workout type")
            } else if originalWorkoutType == "cardio" && candidateWorkoutType == "strength" {
                score -= 30
                reasons.append("⚠️ Strength vs cardio mismatch")
            }
        } else {
            score += 10
        }
        
        // ═══════════════════════════════════════════════════════════════
        // FORCE TYPE MATCH (Push vs Pull)
        // ═══════════════════════════════════════════════════════════════
        
        if !originalForceType.isEmpty && !candidateForceType.isEmpty {
            if candidateForceType == originalForceType {
                score += 15
                reasons.append("⚡ Same force type (\(originalForceType))")
            }
        }
        
        // ═══════════════════════════════════════════════════════════════
        // PLANE OF MOTION MATCH
        // ═══════════════════════════════════════════════════════════════
        
        if !originalPlaneOfMotion.isEmpty && !candidatePlaneOfMotion.isEmpty {
            if candidatePlaneOfMotion == originalPlaneOfMotion {
                score += 10
            }
        }
        
        // ═══════════════════════════════════════════════════════════════
        // BODY POSITION MATCH
        // ═══════════════════════════════════════════════════════════════
        
        if !originalBodyPosition.isEmpty && !candidateBodyPosition.isEmpty {
            if candidateBodyPosition == originalBodyPosition {
                score += 10
                reasons.append("🧍 Same body position")
            }
        }
        
        // ═══════════════════════════════════════════════════════════════
        // DIFFICULTY LEVEL MATCH
        // ═══════════════════════════════════════════════════════════════
        
        let difficultyDiff = abs(Int(candidateDifficulty) - Int(originalDifficulty))
        if difficultyDiff == 0 {
            score += 10
        } else if difficultyDiff <= 1 {
            score += 5
        } else if difficultyDiff >= 3 {
            score -= 10
            reasons.append("📊 Difficulty mismatch")
        }
        
        // ═══════════════════════════════════════════════════════════════
        // NAME SIMILARITY BONUS (variations of same exercise)
        // ═══════════════════════════════════════════════════════════════
        
        let originalWords = Set(originalEquipment.split(separator: " ").map { String($0).lowercased() })
        let candidateWords = Set(candidateName.split(separator: " ").map { String($0).lowercased() })
        let commonWords = originalWords.intersection(candidateWords)
        
        // Bonus for shared movement words (press, curl, row, etc.)
        let movementWords = ["press", "curl", "row", "fly", "raise", "extension", "squat", "deadlift", "lunge", "pulldown", "pushdown"]
        for word in movementWords {
            let origName = (candidate.name ?? "").lowercased()
            let candName = candidateName
            if origName.contains(word) && candName.contains(word) {
                score += 15
                break
            }
        }
        
        return (max(0, score), reasons)
    }
    
    // MARK: - Helper Functions
    
    private func normalizeMuscles(_ muscles: [String]) -> Set<String> {
        var normalized: Set<String> = []
        
        for muscle in muscles {
            let lower = muscle.lowercased()
            normalized.insert(lower)
            
            // Expand muscle groups
            for (group, expansions) in muscleGroupExpansion {
                if expansions.contains(lower) || lower.contains(group) || group.contains(lower) {
                    normalized.formUnion(expansions)
                }
            }
        }
        
        return normalized
    }
    
    private func inferMovementPattern(_ name: String) -> String {
        let lowered = name.lowercased()
        
        if lowered.contains("press") || lowered.contains("push") { return "press" }
        if lowered.contains("row") { return "row" }
        if lowered.contains("pull") && !lowered.contains("pullover") { return "pull" }
        if lowered.contains("pullover") { return "pullover" }
        if lowered.contains("curl") { return "curl" }
        if lowered.contains("fly") || lowered.contains("flye") { return "fly" }
        if lowered.contains("raise") { return "raise" }
        if lowered.contains("extension") || lowered.contains("pushdown") || lowered.contains("kickback") { return "extension" }
        if lowered.contains("squat") { return "squat" }
        if lowered.contains("deadlift") || lowered.contains("rdl") || lowered.contains("hip hinge") { return "hinge" }
        if lowered.contains("lunge") || lowered.contains("split") { return "lunge" }
        if lowered.contains("crunch") || lowered.contains("sit-up") || lowered.contains("plank") { return "core" }
        if lowered.contains("pulldown") || lowered.contains("lat pull") { return "pulldown" }
        if lowered.contains("dip") { return "dip" }
        if lowered.contains("shrug") { return "shrug" }
        
        return "other"
    }
    
    private func getEquipmentCategory(_ equipment: String) -> String? {
        let lowered = equipment.lowercased()
        
        // Use centralized EquipmentHierarchyService for consistent categorization
        if let family = EquipmentHierarchyService.shared.getFamily(for: lowered) {
            return family.rawValue
        }
        
        // Fallback to legacy mapping
        if let category = equipmentCategories[lowered] {
            return category
        }
        
        // Partial match
        for (key, category) in equipmentCategories {
            if lowered.contains(key) || key.contains(lowered) {
                return category
            }
        }
        
        return nil
    }
    
    /// Get equipment family-aware substitution score
    /// Uses EquipmentHierarchyService for intelligent swap recommendations
    private func getEquipmentFamilyScore(original: String, candidate: String) -> (score: Int, reason: String) {
        let hierarchyService = EquipmentHierarchyService.shared
        
        // Same family = best substitution
        if hierarchyService.areSameFamily(original, candidate) {
            return (score: 25, reason: "🔄 Same equipment family")
        }
        
        // Reasonable substitution (e.g., barbell → dumbbell)
        if hierarchyService.isReasonableSubstitution(from: original, to: candidate) {
            return (score: 12, reason: "✅ Compatible equipment type")
        }
        
        // Different family - check if it's a complexity change
        if let originalFamily = hierarchyService.getFamily(for: original),
           let candidateFamily = hierarchyService.getFamily(for: candidate) {
            
            // Upgrading complexity (e.g., machine → barbell) - slight penalty
            if candidateFamily.complexity > originalFamily.complexity {
                return (score: -5, reason: "⬆️ More complex equipment")
            }
            
            // Downgrading complexity (e.g., barbell → machine) - neutral
            if candidateFamily.complexity < originalFamily.complexity {
                return (score: 5, reason: "⬇️ Simpler equipment")
            }
        }
        
        return (score: 0, reason: "")
    }
}

// MARK: - Supporting Types

struct ScoredAlternative {
    let exercise: Exercise
    let score: Int
    let reasons: [String]
    
    var reasonsSummary: String {
        reasons.prefix(3).joined(separator: " | ")
    }
}

