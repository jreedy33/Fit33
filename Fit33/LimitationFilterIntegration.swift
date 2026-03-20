//
//  LimitationFilterIntegration.swift
//  Fit33
//
//  Integration layer that connects the metadata-driven LimitationFilterEngine
//  with the existing LimitationsService and WorkoutGeneratorService.
//
//  This provides the main API for exercise filtering based on user limitations.
//
//  Created by Cursor AI
//

import Foundation

// MARK: - Workout Limitation Filter

/// Main API for applying limitation-based filtering to workout generation
/// Integrates with existing LimitationsService and uses metadata-driven rules
class WorkoutLimitationFilter {
    
    static let shared = WorkoutLimitationFilter()
    private init() {}
    
    // MARK: - Main Filtering API
    
    /// Apply all active limitations to filter exercises for a workout
    /// - Parameters:
    ///   - exercises: All available exercises
    ///   - targetMuscles: User's selected muscle targets
    ///   - equipmentTypes: User's available equipment
    ///   - userWorkoutCount: For experience-based filtering
    /// - Returns: Filtered exercises with metadata and adjustment notes
    func filterForWorkout(
        exercises: [Exercise],
        targetMuscles: [String],
        equipmentTypes: [String],
        userWorkoutCount: Int
    ) -> LimitationFilterResult {
        
        // Get active limitations from existing service
        let limitations = convertToFilterLimitations()
        
        guard !limitations.isEmpty else {
            print("🛡️ [LIMITATION FILTER] No active limitations")
            return LimitationFilterResult(
                exercises: exercises,
                excludedCount: 0,
                adjustmentNotes: [],
                warningsPerExercise: [:]
            )
        }
        
        print("🛡️ [LIMITATION FILTER] Applying \(limitations.count) limitations:")
        for lim in limitations {
            print("   • \(lim.area.displayName): \(lim.severity.displayName)")
        }
        
        // Apply the metadata-driven filter engine
        let (filtered, summary) = LimitationFilterEngine.applyLimitations(
            exercises: exercises,
            limitations: limitations,
            targetMuscles: targetMuscles,
            metadataProvider: defaultMetadataProvider
        )
        
        // Convert results back to Exercise array
        var safeExercises: [Exercise] = []
        var warningsPerExercise: [String: [String]] = [:]
        
        for result in filtered {
            if !result.isExcluded {
                safeExercises.append(result.exercise)
                if !result.warningTags.isEmpty {
                    warningsPerExercise[result.exercise.name ?? ""] = result.warningTags
                }
            }
        }
        
        print("🛡️ [LIMITATION FILTER] Result: \(exercises.count) → \(safeExercises.count) exercises")
        if summary.exercisesExcluded > 0 {
            print("   Excluded: \(summary.exercisesExcluded) exercises")
        }
        if summary.exercisesPenalized > 0 {
            print("   Penalized: \(summary.exercisesPenalized) exercises")
        }
        
        return LimitationFilterResult(
            exercises: safeExercises,
            excludedCount: summary.exercisesExcluded,
            adjustmentNotes: summary.adjustmentNotes,
            warningsPerExercise: warningsPerExercise
        )
    }
    
    /// Score an exercise based on limitations (higher score = safer)
    /// Use this to rank exercises rather than just include/exclude
    func scoreSafety(
        exercise: Exercise,
        targetMuscles: [String]
    ) -> ExerciseSafetyScore {
        let limitations = convertToFilterLimitations()
        
        guard !limitations.isEmpty else {
            return ExerciseSafetyScore(
                exercise: exercise,
                safetyScore: 100,
                isExcluded: false,
                warnings: [],
                exclusionReason: nil
            )
        }
        
        let metadata = defaultMetadataProvider(exercise)
        var totalPenalty: Double = 0
        var warnings: [String] = []
        var isExcluded = false
        var exclusionReason: String?
        
        for limitation in limitations {
            let (shouldExclude, penalty, limitationWarnings, reason) = evaluateAgainstLimitation(
                metadata: metadata,
                limitation: limitation,
                targetMuscles: targetMuscles
            )
            
            if shouldExclude {
                isExcluded = true
                exclusionReason = reason
                break
            }
            
            totalPenalty += penalty
            warnings.append(contentsOf: limitationWarnings)
        }
        
        // Convert penalty to safety score (0-100, higher = safer)
        let safetyScore = max(0, 100 - totalPenalty)
        
        return ExerciseSafetyScore(
            exercise: exercise,
            safetyScore: safetyScore,
            isExcluded: isExcluded,
            warnings: warnings,
            exclusionReason: exclusionReason
        )
    }
    
    /// Get alternative exercises that are safer for user's limitations
    func getSaferAlternatives(
        for exercise: Exercise,
        from alternatives: [Exercise],
        targetMuscles: [String]
    ) -> [Exercise] {
        let originalScore = scoreSafety(exercise: exercise, targetMuscles: targetMuscles)
        
        // Only suggest alternatives if original is risky or excluded
        guard originalScore.isExcluded || originalScore.safetyScore < 50 else {
            return []
        }
        
        // Score all alternatives
        let scoredAlternatives = alternatives.map { alt -> (Exercise, Double) in
            let score = scoreSafety(exercise: alt, targetMuscles: targetMuscles)
            return (alt, score.safetyScore)
        }
        
        // Return alternatives that are safer (score > original)
        return scoredAlternatives
            .filter { $0.1 > originalScore.safetyScore && $0.1 >= 50 }
            .sorted { $0.1 > $1.1 }
            .prefix(5)
            .map { $0.0 }
    }
    
    // MARK: - Private Helpers
    
    /// Convert existing UserLimitation to our filter FilterLimitation model
    private func convertToFilterLimitations() -> [FilterLimitation] {
        let userLimitations = LimitationsService.shared.userLimitations
        
        return userLimitations.compactMap { userLim -> FilterLimitation? in
            guard userLim.isActive else { return nil }
            
            let area = mapAffectedArea(userLim.affectedArea)
            let severity = mapSeverity(userLim.severity)
            
            return FilterLimitation(
                id: userLim.id.uuidString,
                area: area,
                severity: severity,
                notes: userLim.notes,
                isActive: true
            )
        }
    }
    
    /// Map existing AffectedArea to our LimitationArea
    private func mapAffectedArea(_ area: AffectedArea) -> LimitationArea {
        switch area {
        case .lowerBack: return .lowerBack
        case .upperBack: return .upperBack
        case .neck: return .neck
        case .leftShoulder, .rightShoulder, .shoulders: return .shoulders
        case .leftKnee, .rightKnee, .knees: return .knees
        case .leftHip, .rightHip, .hips: return .hips
        case .leftWrist, .rightWrist, .wrists: return .wrists
        case .leftElbow, .rightElbow, .elbows: return .elbows
        case .leftAnkle, .rightAnkle, .ankles: return .ankles
        case .core, .chest, .other: return .other
        }
    }
    
    /// Map existing Severity/AccommodationLevel to our LimitationSeverity
    private func mapSeverity(_ severity: AccommodationLevel) -> LimitationSeverity {
        switch severity {
        case .avoidCompletely: return .skipCompletely
        case .lightOnly: return .lightWorkOnly
        case .stretchingOnly: return .stretchingOnly
        case .beCareful: return .beCareful
        }
    }
    
    /// Evaluate a single exercise against a limitation
    private func evaluateAgainstLimitation(
        metadata: ExerciseRiskMetadata,
        limitation: FilterLimitation,
        targetMuscles: [String]
    ) -> (shouldExclude: Bool, penalty: Double, warnings: [String], reason: String?) {
        
        let affectsArea = doesMetadataAffectArea(metadata: metadata, area: limitation.area)
        
        guard affectsArea else {
            return (false, 0, [], nil)
        }
        
        // Apply severity-specific evaluation
        switch limitation.severity {
        case .skipCompletely:
            return evaluateSkipCompletely(metadata: metadata, area: limitation.area)
        case .stretchingOnly:
            return evaluateStretchingOnly(metadata: metadata, area: limitation.area)
        case .lightWorkOnly:
            return evaluateLightWorkOnly(metadata: metadata, area: limitation.area)
        case .beCareful:
            return evaluateBeCareful(metadata: metadata, area: limitation.area)
        }
    }
    
    /// Check if metadata indicates the exercise affects a body area
    private func doesMetadataAffectArea(metadata: ExerciseRiskMetadata, area: LimitationArea) -> Bool {
        switch area {
        case .lowerBack:
            return metadata.spinalLoad >= .moderate ||
                   metadata.axialLoading >= .low ||
                   metadata.unsupportedTorso ||
                   metadata.hipHingeDemand
            
        case .upperBack:
            return metadata.movementPatterns.contains(RiskMovementPattern.pull)
            
        case .shoulders:
            return !metadata.shoulderStressFlags.isEmpty ||
                   metadata.overheadWork != .none ||
                   metadata.movementPatterns.contains(RiskMovementPattern.push)
            
        case .knees:
            return metadata.kneeFlexionDepth >= .moderate ||
                   metadata.impactLevel >= .moderate ||
                   metadata.movementPatterns.contains(RiskMovementPattern.squat) ||
                   metadata.movementPatterns.contains(RiskMovementPattern.lunge)
            
        case .hips:
            return metadata.hipHingeDemand ||
                   metadata.movementPatterns.contains(RiskMovementPattern.hinge) ||
                   metadata.movementPatterns.contains(RiskMovementPattern.squat)
            
        case .neck:
            return metadata.neckStress ||
                   metadata.axialLoading >= .high
            
        case .wrists:
            return metadata.wristExtensionDemand != .low
            
        case .elbows:
            return metadata.elbowStress
            
        case .ankles:
            return metadata.impactLevel >= .moderate ||
                   metadata.balanceDemand == .high
            
        case .other:
            return false
        }
    }
    
    // MARK: - Severity Evaluations (mirroring LimitationFilterEngine)
    
    private func evaluateSkipCompletely(metadata: ExerciseRiskMetadata, area: LimitationArea) -> (Bool, Double, [String], String?) {
        let rules = LimitationRuleTables.getSkipCompletelyRules(for: area)
        
        for rule in rules {
            if rule.matches(metadata) {
                return (true, 0, [], "Excluded: \(rule.reason)")
            }
        }
        
        return (false, 300, ["Exercise may stress \(area.displayName)"], nil)
    }
    
    private func evaluateStretchingOnly(metadata: ExerciseRiskMetadata, area: LimitationArea) -> (Bool, Double, [String], String?) {
        if metadata.isStretchOrMobility {
            return (false, 0, ["Mobility exercise"], nil)
        }
        return (true, 0, [], "Only stretching allowed for \(area.displayName)")
    }
    
    private func evaluateLightWorkOnly(metadata: ExerciseRiskMetadata, area: LimitationArea) -> (Bool, Double, [String], String?) {
        let exclusionRules = LimitationRuleTables.getLightWorkExclusionRules(for: area)
        
        for rule in exclusionRules {
            if rule.matches(metadata) {
                return (true, 0, [], "Too intense: \(rule.reason)")
            }
        }
        
        var penalty: Double = 0
        var warnings: [String] = []
        
        let preferenceRules = LimitationRuleTables.getLightWorkPreferenceRules(for: area)
        for rule in preferenceRules {
            if rule.matches(metadata) {
                if rule.isNegative {
                    penalty += rule.penalty
                    warnings.append(rule.reason)
                } else {
                    penalty -= rule.penalty
                    warnings.append(rule.reason)
                }
            }
        }
        
        return (false, max(0, penalty), warnings, nil)
    }
    
    private func evaluateBeCareful(metadata: ExerciseRiskMetadata, area: LimitationArea) -> (Bool, Double, [String], String?) {
        var penalty: Double = 0
        var warnings: [String] = []
        
        let rules = LimitationRuleTables.getBeCarefulRules(for: area)
        for rule in rules {
            if rule.matches(metadata) {
                if rule.isNegative {
                    penalty += rule.penalty
                    warnings.append("⚠️ \(rule.reason)")
                } else {
                    penalty -= rule.penalty
                    warnings.append("✅ \(rule.reason)")
                }
            }
        }
        
        return (false, max(0, penalty), warnings, nil)
    }
}

// MARK: - Result Types

/// Result of applying limitation filtering
struct LimitationFilterResult {
    let exercises: [Exercise]
    let excludedCount: Int
    let adjustmentNotes: [String]
    let warningsPerExercise: [String: [String]]
    
    var hasAdjustments: Bool {
        excludedCount > 0 || !warningsPerExercise.isEmpty
    }
    
    /// Get display message for UI
    var displayMessage: String? {
        guard hasAdjustments else { return nil }
        
        if adjustmentNotes.isEmpty {
            return "Adjusted workout for your limitations"
        }
        
        return adjustmentNotes.joined(separator: ". ")
    }
}

/// Safety score for a single exercise
struct ExerciseSafetyScore {
    let exercise: Exercise
    let safetyScore: Double  // 0-100, higher = safer
    let isExcluded: Bool
    let warnings: [String]
    let exclusionReason: String?
    
    var isSafe: Bool {
        !isExcluded && safetyScore >= 50
    }
    
    var riskLevel: RiskLevel {
        if isExcluded { return .excluded }
        if safetyScore >= 80 { return .safe }
        if safetyScore >= 50 { return .moderate }
        return .risky
    }
    
    enum RiskLevel {
        case safe
        case moderate
        case risky
        case excluded
        
        var displayName: String {
            switch self {
            case .safe: return "Safe"
            case .moderate: return "Use Caution"
            case .risky: return "Risky"
            case .excluded: return "Excluded"
            }
        }
    }
}

// MARK: - Equipment Diversity Cap

/// Caps equipment diversity to prevent excessive setup changes
struct EquipmentDiversityCap {
    let maxEquipmentTypes: Int
    let workoutDuration: Int
    let isFoundational: Bool
    
    /// Calculate max distinct equipment types allowed
    static func calculateMax(duration: Int, isFoundational: Bool) -> Int {
        // Shorter workouts = fewer equipment changes
        // Foundational users = prefer consistency
        
        if isFoundational {
            return min(2, duration / 15)  // At most 2 types for foundational
        }
        
        switch duration {
        case ..<20:
            return 2
        case 20..<35:
            return 3
        case 35..<50:
            return 4
        default:
            return 5
        }
    }
    
    /// Filter exercises to cap equipment diversity
    static func applyEquipmentCap(
        exercises: [Exercise],
        maxTypes: Int,
        preferredEquipment: [String]
    ) -> [Exercise] {
        // Group by equipment
        var byEquipment: [String: [Exercise]] = [:]
        for exercise in exercises {
            let equip = exercise.equipment ?? "Bodyweight"
            byEquipment[equip, default: []].append(exercise)
        }
        
        // Sort equipment by preference (preferred first, then by count)
        let sortedEquipment = byEquipment.keys.sorted { a, b in
            let aPreferred = preferredEquipment.contains { a.lowercased().contains($0.lowercased()) }
            let bPreferred = preferredEquipment.contains { b.lowercased().contains($0.lowercased()) }
            
            if aPreferred != bPreferred {
                return aPreferred
            }
            
            return byEquipment[a]!.count > byEquipment[b]!.count
        }
        
        // Take only top N equipment types
        let allowedEquipment = Set(sortedEquipment.prefix(maxTypes))
        
        return exercises.filter { exercise in
            let equip = exercise.equipment ?? "Bodyweight"
            return allowedEquipment.contains(equip)
        }
    }
}

// MARK: - LimitationsService Extension

extension LimitationsService {
    
    /// Filter exercises using the new metadata-driven system
    nonisolated func filterWithMetadata(
        _ exercises: [Exercise],
        targetMuscles: [String],
        userWorkoutCount: Int
    ) -> LimitationFilterResult {
        return WorkoutLimitationFilter.shared.filterForWorkout(
            exercises: exercises,
            targetMuscles: targetMuscles,
            equipmentTypes: [],
            userWorkoutCount: userWorkoutCount
        )
    }
    
    /// Get safety score for an exercise
    nonisolated func getSafetyScore(
        for exercise: Exercise,
        targetMuscles: [String]
    ) -> ExerciseSafetyScore {
        return WorkoutLimitationFilter.shared.scoreSafety(
            exercise: exercise,
            targetMuscles: targetMuscles
        )
    }
}
