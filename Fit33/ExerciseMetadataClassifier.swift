//
//  ExerciseMetadataClassifier.swift
//  Fit33
//
//  Intelligent classification system that derives ExerciseRiskMetadata
//  from exercise properties WITHOUT hardcoding specific exercise names.
//  
//  Uses pattern matching on:
//  - Exercise name keywords
//  - Primary/secondary muscle groups
//  - Equipment type
//  - Movement category
//  - Existing difficulty tier
//
//  This allows the system to classify ANY exercise, including new ones.
//
//  Created by Cursor AI
//

import Foundation

// MARK: - Exercise Metadata Classifier

/// Derives risk metadata from exercise properties using pattern matching
/// NO hardcoded exercise name lists - uses keyword patterns instead
class ExerciseMetadataClassifier {
    
    // MARK: - Singleton
    
    static let shared = ExerciseMetadataClassifier()
    private init() {}
    
    // MARK: - Main Classification
    
    /// Classify an exercise and return its risk metadata
    func classify(exercise: Exercise) -> ExerciseRiskMetadata {
        let name = exercise.name.lowercased()
        let equipment = exercise.equipment?.lowercased() ?? ""
        let primaryMuscle = exercise.primaryMuscle?.lowercased() ?? ""
        let secondaryMuscles = exercise.secondaryMuscles?.joined(separator: " ").lowercased() ?? ""
        let allMuscles = "\(primaryMuscle) \(secondaryMuscles)"
        
        return ExerciseRiskMetadata(
            movementPatterns: classifyMovementPatterns(name: name, muscle: primaryMuscle),
            spinalLoad: classifySpinalLoad(name: name, equipment: equipment, muscle: primaryMuscle),
            axialLoading: classifyAxialLoading(name: name, equipment: equipment),
            unsupportedTorso: isUnsupportedTorso(name: name, equipment: equipment),
            overheadWork: classifyOverheadWork(name: name, equipment: equipment),
            kneeFlexionDepth: classifyKneeFlexion(name: name),
            shoulderStressFlags: classifyShoulderStress(name: name, equipment: equipment),
            wristExtensionDemand: classifyWristDemand(name: name, equipment: equipment),
            hipHingeDemand: isHipHinge(name: name),
            neckStress: hasNeckStress(name: name),
            elbowStress: hasElbowStress(name: name),
            impactLevel: classifyImpact(name: name),
            balanceDemand: classifyBalance(name: name, equipment: equipment),
            isMachineSupported: isMachine(name: name, equipment: equipment),
            isStretchOrMobility: isStretchOrMobility(name: name),
            isChestSupported: isChestSupported(name: name, equipment: equipment),
            isSeated: isSeated(name: name),
            isLying: isLying(name: name),
            difficultyTier: classifyDifficulty(name: name, exercise: exercise)
        )
    }
    
    // MARK: - Movement Patterns
    
    private func classifyMovementPatterns(name: String, muscle: String) -> Set<MovementPattern> {
        var patterns: Set<MovementPattern> = []
        
        // Push patterns
        if containsAny(name, ["press", "pushup", "push-up", "push up", "dip", "fly", "flye"]) {
            patterns.insert(.push)
        }
        
        // Pull patterns
        if containsAny(name, ["row", "pull", "pulldown", "lat pull", "chin", "curl"]) {
            patterns.insert(.pull)
        }
        
        // Squat patterns
        if containsAny(name, ["squat", "leg press", "hack", "goblet"]) {
            patterns.insert(.squat)
        }
        
        // Hinge patterns
        if containsAny(name, ["deadlift", "rdl", "romanian", "hip hinge", "good morning", "stiff leg", "swing"]) {
            patterns.insert(.hinge)
        }
        
        // Lunge patterns
        if containsAny(name, ["lunge", "split squat", "step up", "step-up", "bulgarian"]) {
            patterns.insert(.lunge)
        }
        
        // Carry patterns
        if containsAny(name, ["carry", "walk", "farmer"]) {
            patterns.insert(.carry)
        }
        
        // Rotation patterns
        if containsAny(name, ["rotation", "twist", "russian twist", "woodchop"]) {
            patterns.insert(.rotation)
        }
        
        // Anti-rotation
        if containsAny(name, ["pallof", "anti-rotation", "plank with"]) {
            patterns.insert(.antiRotation)
        }
        
        // Anti-extension
        if containsAny(name, ["plank", "ab wheel", "rollout", "dead bug", "hollow"]) {
            patterns.insert(.antiExtension)
        }
        
        // Isolation
        if containsAny(name, ["curl", "extension", "raise", "fly", "kickback", "isolation"]) {
            patterns.insert(.isolation)
        }
        
        // Stretch/mobility
        if containsAny(name, ["stretch", "mobility", "foam roll", "flexibility"]) {
            patterns.insert(.stretch)
        }
        
        return patterns
    }
    
    // MARK: - Spinal Load
    
    private func classifySpinalLoad(name: String, equipment: String, muscle: String) -> SpinalLoad {
        // High spinal load
        if containsAny(name, ["deadlift", "good morning", "back squat", "front squat", "barbell row", "bent over row", "barbell bent", "renegade", "atlas"]) {
            return .high
        }
        
        // Moderate spinal load
        if containsAny(name, ["squat", "rdl", "romanian", "row", "lunge", "overhead press", "military press"]) {
            // But reduce if supported
            if containsAny(name, ["machine", "seated", "lying", "chest supported", "incline"]) {
                return .low
            }
            return .moderate
        }
        
        // Low spinal load
        if containsAny(name, ["seated", "lying", "machine", "cable", "incline", "chest supported"]) {
            return .low
        }
        
        // Check equipment
        if containsAny(equipment, ["machine", "cable", "smith"]) {
            return .low
        }
        
        // Default based on muscle
        if containsAny(muscle, ["back", "erector", "lower back"]) {
            return .moderate
        }
        
        return .none
    }
    
    // MARK: - Axial Loading
    
    private func classifyAxialLoading(name: String, equipment: String) -> AxialLoading {
        // High axial - bar on back/shoulders
        if containsAny(name, ["back squat", "front squat", "barbell squat", "overhead squat", "barbell lunge", "walking lunge with barbell", "barbell shoulder press standing"]) {
            return .high
        }
        
        // Low axial
        if containsAny(name, ["dumbbell squat", "goblet", "dumbbell lunge"]) {
            return .low
        }
        
        // Check equipment type
        if containsAny(equipment, ["barbell"]) && containsAny(name, ["squat", "lunge", "standing press"]) {
            return .high
        }
        
        return .none
    }
    
    // MARK: - Unsupported Torso
    
    private func isUnsupportedTorso(name: String, equipment: String) -> Bool {
        // Bent-over positions without support
        if containsAny(name, ["bent over", "bent-over", "renegade", "pendlay", "barbell row"]) {
            // But not if chest supported
            if containsAny(name, ["chest supported", "seal row", "incline bench row"]) {
                return false
            }
            return true
        }
        
        // Standing hinges
        if containsAny(name, ["good morning", "stiff leg", "romanian"]) && !containsAny(name, ["machine"]) {
            return true
        }
        
        return false
    }
    
    // MARK: - Overhead Work
    
    private func classifyOverheadWork(name: String, equipment: String) -> OverheadWork {
        // Full overhead
        if containsAny(name, ["overhead press", "military press", "shoulder press", "push press", "jerk", "snatch", "pull-up", "pullup", "chin-up", "chinup", "lat pulldown", "overhead tricep", "skull"]) {
            // But not if it's machine pulldown - that's not full overhead stress
            if containsAny(name, ["pulldown", "lat pull"]) {
                return .partial
            }
            return .full
        }
        
        // Partial overhead
        if containsAny(name, ["incline press", "high incline", "arnold"]) {
            return .partial
        }
        
        return .none
    }
    
    // MARK: - Knee Flexion
    
    private func classifyKneeFlexion(name: String) -> KneeFlexionDepth {
        // High flexion (deep squat)
        if containsAny(name, ["deep squat", "atg", "ass to grass", "full squat", "pistol", "sissy squat"]) {
            return .high
        }
        
        // Moderate flexion
        if containsAny(name, ["squat", "lunge", "leg press", "hack squat", "split squat"]) {
            return .moderate
        }
        
        // Low flexion
        if containsAny(name, ["leg extension", "leg curl", "hip thrust", "glute bridge", "calf"]) {
            return .low
        }
        
        return .low
    }
    
    // MARK: - Shoulder Stress
    
    private func classifyShoulderStress(name: String, equipment: String) -> ShoulderStressFlags {
        var flags: ShoulderStressFlags = []
        
        // Upright row pattern
        if containsAny(name, ["upright row", "high pull", "face pull to external"]) {
            flags.insert(.uprightRowLike)
        }
        
        // Behind neck
        if containsAny(name, ["behind neck", "behind-neck", "btn"]) {
            flags.insert(.behindNeck)
        }
        
        // Guillotine press (neck press)
        if containsAny(name, ["guillotine", "neck press"]) {
            flags.insert(.guillotine)
        }
        
        // Heavy dip
        if containsAny(name, ["dip", "chest dip"]) && !containsAny(name, ["tricep dip machine"]) {
            flags.insert(.heavyDip)
        }
        
        // Internal rotation under load
        if containsAny(name, ["internal rotation", "behind back", "behind the back"]) {
            flags.insert(.internalRotationLoaded)
        }
        
        // Extreme ROM
        if containsAny(name, ["deep stretch", "extreme", "full range fly"]) {
            flags.insert(.extremeROM)
        }
        
        return flags
    }
    
    // MARK: - Wrist Demand
    
    private func classifyWristDemand(name: String, equipment: String) -> WristExtensionDemand {
        // High wrist extension
        if containsAny(name, ["front squat clean grip", "push-up", "pushup", "handstand", "planche"]) {
            return .high
        }
        
        // Moderate
        if containsAny(name, ["curl", "bench press", "row"]) {
            return .moderate
        }
        
        return .low
    }
    
    // MARK: - Hip Hinge
    
    private func isHipHinge(name: String) -> Bool {
        return containsAny(name, ["deadlift", "rdl", "romanian", "good morning", "hip hinge", "swing", "bent over", "bent-over", "stiff leg", "pull through"])
    }
    
    // MARK: - Neck Stress
    
    private func hasNeckStress(name: String) -> Bool {
        return containsAny(name, ["shrug", "neck", "wrestler bridge", "neck curl"])
    }
    
    // MARK: - Elbow Stress
    
    private func hasElbowStress(name: String) -> Bool {
        return containsAny(name, ["skullcrusher", "skull crusher", "jm press", "close grip bench", "tricep extension"])
    }
    
    // MARK: - Impact Level
    
    private func classifyImpact(name: String) -> ImpactLevel {
        // High impact
        if containsAny(name, ["jump", "plyo", "box jump", "burpee", "clap pushup", "clap push-up", "depth jump", "bound"]) {
            return .high
        }
        
        // Moderate impact
        if containsAny(name, ["step up", "split jump", "lunge jump", "skater"]) {
            return .moderate
        }
        
        return .none
    }
    
    // MARK: - Balance Demand
    
    private func classifyBalance(name: String, equipment: String) -> BalanceDemand {
        // High balance
        if containsAny(name, ["single leg", "pistol", "one leg", "bulgarian", "bosu", "stability ball", "single-leg"]) {
            return .high
        }
        
        // Low balance - machines, seated, lying
        if containsAny(name, ["machine", "seated", "lying", "bench"]) || containsAny(equipment, ["machine", "cable"]) {
            return .low
        }
        
        // Standing bilateral = moderate
        if containsAny(name, ["standing", "squat", "lunge"]) && !containsAny(name, ["single"]) {
            return .moderate
        }
        
        return .low
    }
    
    // MARK: - Machine Support
    
    private func isMachine(name: String, equipment: String) -> Bool {
        return containsAny(name, ["machine", "cable", "smith", "assisted"]) ||
               containsAny(equipment, ["machine", "cable", "smith"])
    }
    
    // MARK: - Stretch/Mobility
    
    private func isStretchOrMobility(name: String) -> Bool {
        return containsAny(name, ["stretch", "mobility", "foam roll", "flexibility", "yoga", "static stretch", "dynamic stretch"])
    }
    
    // MARK: - Chest Supported
    
    private func isChestSupported(name: String, equipment: String) -> Bool {
        return containsAny(name, ["chest supported", "chest-supported", "seal row", "prone row", "incline bench row", "t-bar row chest"])
    }
    
    // MARK: - Seated
    
    private func isSeated(name: String) -> Bool {
        return containsAny(name, ["seated", "sitting"])
    }
    
    // MARK: - Lying
    
    private func isLying(name: String) -> Bool {
        return containsAny(name, ["lying", "prone", "supine", "bench press", "floor press", "lying tricep", "leg curl machine", "leg extension"])
    }
    
    // MARK: - Difficulty Tier
    
    private func classifyDifficulty(name: String, exercise: Exercise) -> DifficultyTier {
        // Check existing tier if available
        if let tier = exercise.difficultyTier {
            if tier == "advanced" { return .advanced }
            if tier == "intermediate" { return .intermediate }
            return .foundational
        }
        
        // Advanced patterns
        if containsAny(name, ["olympic", "snatch", "clean", "jerk", "pistol", "muscle up", "planche", "front lever", "handstand"]) {
            return .advanced
        }
        
        // Intermediate
        if containsAny(name, ["barbell", "weighted", "deficit", "pause rep", "tempo"]) {
            return .intermediate
        }
        
        // Machine exercises tend to be foundational
        if containsAny(name, ["machine", "cable"]) {
            return .foundational
        }
        
        return .foundational
    }
    
    // MARK: - Helper
    
    private func containsAny(_ text: String, _ keywords: [String]) -> Bool {
        return keywords.contains { text.contains($0) }
    }
}

// MARK: - Exercise Extension

extension Exercise {
    /// Get risk metadata for this exercise
    var riskMetadata: ExerciseRiskMetadata {
        return ExerciseMetadataClassifier.shared.classify(exercise: self)
    }
    
    /// Check if this exercise is safe for a specific limitation
    func isSafeFor(limitation: Limitation) -> Bool {
        let (exercises, _) = LimitationFilterEngine.applyLimitations(
            exercises: [self],
            limitations: [limitation],
            targetMuscles: [],
            metadataProvider: { $0.riskMetadata }
        )
        
        guard let result = exercises.first else { return true }
        return !result.isExcluded && result.penaltyScore < 100
    }
}

// MARK: - Convenience Metadata Provider

/// Provides metadata for exercises using the classifier
func defaultMetadataProvider(_ exercise: Exercise) -> ExerciseRiskMetadata {
    return ExerciseMetadataClassifier.shared.classify(exercise: exercise)
}
