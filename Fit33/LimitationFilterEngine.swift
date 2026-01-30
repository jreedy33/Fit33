//
//  LimitationFilterEngine.swift
//  Fit33
//
//  A comprehensive, metadata-driven limitation/injury filtering system.
//  
//  Design Principles:
//  1. NO HARDCODED EXERCISE NAMES - uses metadata tags for filtering
//  2. Pure functions for testability
//  3. Extensible rule tables per area
//  4. Severity-based logic (skip/light/stretch/careful)
//  5. Works with any limitation area, not just lower back
//
//  Created by Cursor AI
//

import Foundation

// MARK: - Core Enums

/// Body areas that can have limitations/injuries
enum LimitationArea: String, Codable, CaseIterable, Hashable {
    case lowerBack = "Lower Back"
    case shoulders = "Shoulders"
    case knees = "Knees"
    case hips = "Hips"
    case neck = "Neck"
    case wrists = "Wrists"
    case elbows = "Elbows"
    case ankles = "Ankles"
    case upperBack = "Upper Back"
    case pregnancy = "Pregnancy"
    case other = "Other"
    
    var displayName: String { rawValue }
    
    /// Maps from user-facing string to enum
    static func from(string: String) -> LimitationArea {
        let lower = string.lowercased()
        if lower.contains("lower back") || lower.contains("low back") { return .lowerBack }
        if lower.contains("upper back") { return .upperBack }
        if lower.contains("shoulder") { return .shoulders }
        if lower.contains("knee") { return .knees }
        if lower.contains("hip") { return .hips }
        if lower.contains("neck") { return .neck }
        if lower.contains("wrist") { return .wrists }
        if lower.contains("elbow") { return .elbows }
        if lower.contains("ankle") { return .ankles }
        if lower.contains("pregnan") { return .pregnancy }
        return .other
    }
}

/// Severity levels for limitations
enum LimitationSeverity: String, Codable, CaseIterable, Hashable {
    case skipCompletely = "Skip completely"
    case lightWorkOnly = "Light work only"
    case stretchingOnly = "Stretching only"
    case beCareful = "Be careful"
    
    var displayName: String { rawValue }
    
    /// Priority for filtering (higher = more restrictive)
    var restrictionLevel: Int {
        switch self {
        case .skipCompletely: return 4
        case .stretchingOnly: return 3
        case .lightWorkOnly: return 2
        case .beCareful: return 1
        }
    }
    
    /// Maps from user-facing string to enum
    static func from(string: String) -> LimitationSeverity {
        let lower = string.lowercased()
        if lower.contains("skip") { return .skipCompletely }
        if lower.contains("stretching") || lower.contains("stretch only") { return .stretchingOnly }
        if lower.contains("light") { return .lightWorkOnly }
        return .beCareful
    }
}

// NOTE: LimitationType is defined in LimitationsService.swift - using that one

// MARK: - Limitation Model (for filter engine use)

/// A lightweight limitation struct for the filter engine
/// Maps from UserLimitation used elsewhere in the app
struct FilterLimitation: Hashable, Identifiable {
    let id: String
    let area: LimitationArea
    let severity: LimitationSeverity
    let notes: String?
    var isActive: Bool
    
    init(
        id: String = UUID().uuidString,
        area: LimitationArea,
        severity: LimitationSeverity,
        notes: String? = nil,
        isActive: Bool = true
    ) {
        self.id = id
        self.area = area
        self.severity = severity
        self.notes = notes
        self.isActive = isActive
    }
    
    /// Create from UserLimitation
    init(from userLimitation: UserLimitation) {
        self.id = userLimitation.id.uuidString
        self.area = LimitationArea.from(string: userLimitation.affectedArea.rawValue)
        self.severity = LimitationSeverity.from(string: userLimitation.severity.rawValue)
        self.notes = userLimitation.notes
        self.isActive = userLimitation.isActive
    }
}

// MARK: - Exercise Risk Metadata Tags

/// Spinal loading level
enum SpinalLoad: String, Codable, Comparable {
    case none = "none"
    case low = "low"
    case moderate = "moderate"
    case high = "high"
    
    static func < (lhs: SpinalLoad, rhs: SpinalLoad) -> Bool {
        let order: [SpinalLoad] = [.none, .low, .moderate, .high]
        return order.firstIndex(of: lhs)! < order.firstIndex(of: rhs)!
    }
}

/// Axial loading (bar-on-back style compression)
enum AxialLoading: String, Codable, Comparable {
    case none = "none"
    case low = "low"
    case high = "high"
    
    static func < (lhs: AxialLoading, rhs: AxialLoading) -> Bool {
        let order: [AxialLoading] = [.none, .low, .high]
        return order.firstIndex(of: lhs)! < order.firstIndex(of: rhs)!
    }
}

/// Overhead work intensity
enum OverheadWork: String, Codable {
    case none = "none"
    case partial = "partial"  // e.g., incline press
    case full = "full"        // e.g., overhead press, pullups
}

/// Knee flexion depth
enum KneeFlexionDepth: String, Codable, Comparable {
    case low = "low"          // <90 degrees
    case moderate = "moderate" // ~90 degrees
    case high = "high"         // >90 degrees (deep squat)
    
    static func < (lhs: KneeFlexionDepth, rhs: KneeFlexionDepth) -> Bool {
        let order: [KneeFlexionDepth] = [.low, .moderate, .high]
        return order.firstIndex(of: lhs)! < order.firstIndex(of: rhs)!
    }
}

/// Impact level (jumping, plyometrics)
enum ImpactLevel: String, Codable, Comparable {
    case none = "none"
    case low = "low"
    case moderate = "moderate"
    case high = "high"
    
    static func < (lhs: ImpactLevel, rhs: ImpactLevel) -> Bool {
        let order: [ImpactLevel] = [.none, .low, .moderate, .high]
        return order.firstIndex(of: lhs)! < order.firstIndex(of: rhs)!
    }
}

/// Wrist extension demand
enum WristExtensionDemand: String, Codable {
    case low = "low"
    case moderate = "moderate"
    case high = "high"
}

/// Balance/stability demand
enum BalanceDemand: String, Codable {
    case low = "low"       // Machine, seated, lying
    case moderate = "moderate" // Standing bilateral
    case high = "high"     // Single-leg, unstable surface
}

/// Shoulder-specific stress flags
struct ShoulderStressFlags: OptionSet, Codable, Hashable {
    let rawValue: Int
    
    static let uprightRowLike = ShoulderStressFlags(rawValue: 1 << 0)
    static let behindNeck = ShoulderStressFlags(rawValue: 1 << 1)
    static let guillotine = ShoulderStressFlags(rawValue: 1 << 2)
    static let heavyDip = ShoulderStressFlags(rawValue: 1 << 3)
    static let internalRotationLoaded = ShoulderStressFlags(rawValue: 1 << 4)
    static let extremeROM = ShoulderStressFlags(rawValue: 1 << 5)
    
    static let none: ShoulderStressFlags = []
}

/// Complete exercise risk metadata
struct ExerciseRiskMetadata: Hashable {
    // Core movement classification
    let movementPatterns: Set<RiskMovementPattern>
    
    // Spinal stress
    let spinalLoad: SpinalLoad
    let axialLoading: AxialLoading
    let unsupportedTorso: Bool  // Bent-over without chest support
    
    // Joint-specific
    let overheadWork: OverheadWork
    let kneeFlexionDepth: KneeFlexionDepth
    let shoulderStressFlags: ShoulderStressFlags
    let wristExtensionDemand: WristExtensionDemand
    let hipHingeDemand: Bool
    let neckStress: Bool
    let elbowStress: Bool
    
    // Stability/Impact
    let impactLevel: ImpactLevel
    let balanceDemand: BalanceDemand
    
    // Safety characteristics
    let isMachineSupported: Bool
    let isStretchOrMobility: Bool
    let isChestSupported: Bool
    let isSeated: Bool
    let isLying: Bool
    
    // Difficulty
    let difficultyTier: DifficultyTier
    
    /// Convenience: is this a "safe" exercise (low risk profile)
    var isSafe: Bool {
        return spinalLoad <= .low &&
               impactLevel <= .low &&
               shoulderStressFlags.isEmpty &&
               (isMachineSupported || isSeated || isLying || isChestSupported)
    }
    
    /// Default safe metadata
    static let safe = ExerciseRiskMetadata(
        movementPatterns: [],
        spinalLoad: .none,
        axialLoading: .none,
        unsupportedTorso: false,
        overheadWork: .none,
        kneeFlexionDepth: .low,
        shoulderStressFlags: .none,
        wristExtensionDemand: .low,
        hipHingeDemand: false,
        neckStress: false,
        elbowStress: false,
        impactLevel: .none,
        balanceDemand: .low,
        isMachineSupported: true,
        isStretchOrMobility: false,
        isChestSupported: false,
        isSeated: true,
        isLying: false,
        difficultyTier: .foundational
    )
}

/// Movement pattern classification (for risk assessment)
/// Named distinctly to avoid conflicts with other MovementPattern enums in the codebase
enum RiskMovementPattern: String, Codable, CaseIterable, Hashable {
    case push = "push"
    case pull = "pull"
    case squat = "squat"
    case hinge = "hinge"
    case lunge = "lunge"
    case carry = "carry"
    case rotation = "rotation"
    case antiRotation = "anti_rotation"
    case antiExtension = "anti_extension"
    case isolation = "isolation"
    case stretch = "stretch"
}

/// Difficulty tier
enum DifficultyTier: String, Codable, Comparable {
    case foundational = "foundational"
    case intermediate = "intermediate"
    case advanced = "advanced"
    
    static func < (lhs: DifficultyTier, rhs: DifficultyTier) -> Bool {
        let order: [DifficultyTier] = [.foundational, .intermediate, .advanced]
        return order.firstIndex(of: lhs)! < order.firstIndex(of: rhs)!
    }
}

// MARK: - Filtering Result

/// Result of applying limitation filtering to an exercise
struct FilteredExercise {
    let exercise: Exercise
    let metadata: ExerciseRiskMetadata
    var penaltyScore: Double  // Higher = more risky
    var warningTags: [String]
    var isExcluded: Bool
    var exclusionReason: String?
    
    /// Final score (original score - penalty)
    func adjustedScore(originalScore: Double) -> Double {
        return originalScore - penaltyScore
    }
}

/// Summary of limitation filtering applied
struct LimitationFilterSummary {
    let exercisesExcluded: Int
    let exercisesPenalized: Int
    let areasAffected: Set<LimitationArea>
    let adjustmentNotes: [String]
}

// MARK: - Limitation Filter Engine

/// Pure function engine for applying limitation filtering
/// NO hardcoded exercise names - uses metadata tags only
class LimitationFilterEngine {
    
    // MARK: - Main Filtering Function
    
    /// Apply limitations to a list of exercises
    /// - Parameters:
    ///   - exercises: Source exercises to filter
    ///   - limitations: User's active limitations
    ///   - targetMuscles: Muscles the user wants to train
    ///   - metadataProvider: Function to get metadata for an exercise
    /// - Returns: Filtered and scored exercises
    static func applyLimitations(
        exercises: [Exercise],
        limitations: [FilterLimitation],
        targetMuscles: [String],
        metadataProvider: (Exercise) -> ExerciseRiskMetadata
    ) -> (exercises: [FilteredExercise], summary: LimitationFilterSummary) {
        
        guard !limitations.isEmpty else {
            // No limitations - return all exercises with default metadata
            let filtered = exercises.map { exercise in
                FilteredExercise(
                    exercise: exercise,
                    metadata: metadataProvider(exercise),
                    penaltyScore: 0,
                    warningTags: [],
                    isExcluded: false,
                    exclusionReason: nil
                )
            }
            return (filtered, LimitationFilterSummary(
                exercisesExcluded: 0,
                exercisesPenalized: 0,
                areasAffected: [],
                adjustmentNotes: []
            ))
        }
        
        var filteredExercises: [FilteredExercise] = []
        var excludedCount = 0
        var penalizedCount = 0
        var adjustmentNotes: [String] = []
        
        for exercise in exercises {
            let metadata = metadataProvider(exercise)
            var result = FilteredExercise(
                exercise: exercise,
                metadata: metadata,
                penaltyScore: 0,
                warningTags: [],
                isExcluded: false,
                exclusionReason: nil
            )
            
            // Apply each limitation
            for limitation in limitations where limitation.isActive {
                let (shouldExclude, penalty, warnings, reason) = evaluateExercise(
                    exercise: exercise,
                    metadata: metadata,
                    limitation: limitation,
                    targetMuscles: targetMuscles
                )
                
                if shouldExclude {
                    result.isExcluded = true
                    result.exclusionReason = reason
                    break  // Skip completely wins
                }
                
                result.penaltyScore += penalty
                result.warningTags.append(contentsOf: warnings)
            }
            
            if result.isExcluded {
                excludedCount += 1
            } else if result.penaltyScore > 0 {
                penalizedCount += 1
            }
            
            filteredExercises.append(result)
        }
        
        // Generate summary notes
        let areasAffected = Set(limitations.map { $0.area })
        for area in areasAffected {
            if let limitation = limitations.first(where: { $0.area == area }) {
                switch limitation.severity {
                case .skipCompletely:
                    adjustmentNotes.append("Skipping exercises that stress \(area.displayName)")
                case .stretchingOnly:
                    adjustmentNotes.append("Only stretching for \(area.displayName)")
                case .lightWorkOnly:
                    adjustmentNotes.append("Light work only for \(area.displayName)")
                case .beCareful:
                    adjustmentNotes.append("Preferring safer options for \(area.displayName)")
                }
            }
        }
        
        let summary = LimitationFilterSummary(
            exercisesExcluded: excludedCount,
            exercisesPenalized: penalizedCount,
            areasAffected: areasAffected,
            adjustmentNotes: adjustmentNotes
        )
        
        return (filteredExercises, summary)
    }
    
    // MARK: - Exercise Evaluation
    
    /// Evaluate a single exercise against a limitation
    /// Returns: (shouldExclude, penaltyScore, warnings, reason)
    private static func evaluateExercise(
        exercise: Exercise,
        metadata: ExerciseRiskMetadata,
        limitation: FilterLimitation,
        targetMuscles: [String]
    ) -> (shouldExclude: Bool, penalty: Double, warnings: [String], reason: String?) {
        
        // Check if this exercise affects the limitation area
        let affectsArea = doesExerciseAffectArea(
            exercise: exercise,
            metadata: metadata,
            area: limitation.area
        )
        
        guard affectsArea else {
            // Exercise doesn't affect this area - no filtering needed
            return (false, 0, [], nil)
        }
        
        // Apply severity-specific rules
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
    
    // MARK: - Area Detection
    
    /// Determine if an exercise affects a given limitation area
    private static func doesExerciseAffectArea(
        exercise: Exercise,
        metadata: ExerciseRiskMetadata,
        area: LimitationArea
    ) -> Bool {
        switch area {
        case .lowerBack:
            return metadata.spinalLoad >= .moderate ||
                   metadata.axialLoading >= .low ||
                   metadata.unsupportedTorso ||
                   metadata.hipHingeDemand ||
                   metadata.movementPatterns.contains(RiskMovementPattern.hinge)
            
        case .upperBack:
            return metadata.movementPatterns.contains(RiskMovementPattern.pull) ||
                   metadata.unsupportedTorso
            
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
                   metadata.kneeFlexionDepth >= .moderate ||
                   metadata.movementPatterns.contains(RiskMovementPattern.hinge) ||
                   metadata.movementPatterns.contains(RiskMovementPattern.squat)
            
        case .neck:
            return metadata.neckStress ||
                   metadata.axialLoading >= .high
            
        case .wrists:
            return metadata.wristExtensionDemand != .low
            
        case .elbows:
            return metadata.elbowStress ||
                   metadata.movementPatterns.contains(RiskMovementPattern.push) ||
                   metadata.movementPatterns.contains(RiskMovementPattern.pull)
            
        case .ankles:
            return metadata.impactLevel >= .moderate ||
                   metadata.balanceDemand == .high
            
        case .pregnancy:
            // Avoid exercises with high impact, spinal load, prone positions, or heavy overhead work
            return metadata.impactLevel >= .moderate ||
                   metadata.spinalLoad >= .moderate ||
                   metadata.axialLoading == .high ||
                   metadata.overheadWork == .full ||
                   metadata.balanceDemand == .high ||
                   metadata.unsupportedTorso
            
        case .other:
            return false  // No automatic detection for "other"
        }
    }
    
    // MARK: - Severity Evaluations
    
    /// Skip completely: exclude high-risk exercises for this area
    private static func evaluateSkipCompletely(
        metadata: ExerciseRiskMetadata,
        area: LimitationArea
    ) -> (Bool, Double, [String], String?) {
        
        let rules = LimitationRuleTables.getSkipCompletelyRules(for: area)
        
        for rule in rules {
            if rule.matches(metadata) {
                return (true, 0, [], "Excluded: \(rule.reason)")
            }
        }
        
        // If it affects the area but doesn't match exclusion rules, still penalize heavily
        return (false, 300, ["Exercise may stress \(area.displayName)"], nil)
    }
    
    /// Stretching only: only allow stretch/mobility exercises
    private static func evaluateStretchingOnly(
        metadata: ExerciseRiskMetadata,
        area: LimitationArea
    ) -> (Bool, Double, [String], String?) {
        
        if metadata.isStretchOrMobility {
            return (false, 0, ["Mobility exercise for \(area.displayName)"], nil)
        }
        
        return (true, 0, [], "Only stretching allowed for \(area.displayName)")
    }
    
    /// Light work only: allow safe variations, exclude heavy/compound
    private static func evaluateLightWorkOnly(
        metadata: ExerciseRiskMetadata,
        area: LimitationArea
    ) -> (Bool, Double, [String], String?) {
        
        let exclusionRules = LimitationRuleTables.getLightWorkExclusionRules(for: area)
        
        // Check for hard exclusions first
        for rule in exclusionRules {
            if rule.matches(metadata) {
                return (true, 0, [], "Too intense for light work: \(rule.reason)")
            }
        }
        
        // Calculate penalty based on risk factors
        var penalty: Double = 0
        var warnings: [String] = []
        
        let preferenceRules = LimitationRuleTables.getLightWorkPreferenceRules(for: area)
        
        for rule in preferenceRules {
            if rule.isNegative && rule.matches(metadata) {
                penalty += rule.penalty
                warnings.append(rule.reason)
            } else if !rule.isNegative && rule.matches(metadata) {
                penalty -= rule.penalty  // Boost for safe options
                warnings.append(rule.reason)
            }
        }
        
        return (false, penalty, warnings, nil)
    }
    
    /// Be careful: penalize risky options, prefer safer ones
    private static func evaluateBeCareful(
        metadata: ExerciseRiskMetadata,
        area: LimitationArea
    ) -> (Bool, Double, [String], String?) {
        
        var penalty: Double = 0
        var warnings: [String] = []
        
        let rules = LimitationRuleTables.getBeCarefulRules(for: area)
        
        for rule in rules {
            if rule.matches(metadata) {
                if rule.isNegative {
                    penalty += rule.penalty
                    warnings.append("⚠️ \(rule.reason)")
                } else {
                    penalty -= rule.penalty  // Boost
                    warnings.append("✅ \(rule.reason)")
                }
            }
        }
        
        return (false, penalty, warnings, nil)
    }
}

// MARK: - Rule Definition

/// A rule for evaluating exercise metadata
struct LimitationRule {
    let id: String
    let reason: String
    let penalty: Double
    let isNegative: Bool  // true = penalty, false = boost
    let matches: (ExerciseRiskMetadata) -> Bool
    
    init(
        id: String,
        reason: String,
        penalty: Double = 100,
        isNegative: Bool = true,
        matches: @escaping (ExerciseRiskMetadata) -> Bool
    ) {
        self.id = id
        self.reason = reason
        self.penalty = penalty
        self.isNegative = isNegative
        self.matches = matches
    }
}
