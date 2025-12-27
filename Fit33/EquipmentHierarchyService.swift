//
//  EquipmentHierarchyService.swift
//  GoFit
//
//  Centralized equipment hierarchy and relationships for intelligent recommendations.
//  Based on actual exercise database counts and equipment family relationships.
//

import Foundation

// MARK: - Equipment Family

/// Top-level equipment categories with their relationships
enum EquipmentFamily: String, CaseIterable, Sendable {
    case barbell      // Includes: Barbell, Smith Machine, EZ Bar, Trap Bar, Landmine
    case dumbbell     // Standalone category
    case cable        // Cable machine exercises
    case machine      // Lever machines, leg press, etc.
    case kettlebell   // Standalone category
    case band         // Resistance bands
    case bodyweight   // Includes: Pure BW, Chair, Wall, Pull-Up Bar, Stability Ball, etc.
    case suspension   // Includes: TRX, Gymnastic Rings
    case plate        // Weight plate exercises (standalone)
    
    /// Number of exercises available in this family
    var exerciseCount: Int {
        switch self {
        case .bodyweight: return 3988
        case .dumbbell: return 649
        case .barbell: return 419
        case .cable: return 394
        case .band: return 357
        case .machine: return 295
        case .suspension: return 230
        case .kettlebell: return 183
        case .plate: return 26
        }
    }
    
    /// Beginner-friendliness score (0-100)
    /// Higher = more beginner friendly
    var beginnerScore: Int {
        switch self {
        case .machine: return 95      // Guided movement, safest
        case .cable: return 85        // Guided, adjustable
        case .bodyweight: return 80   // Natural movements
        case .band: return 75         // Low risk, scalable
        case .dumbbell: return 60     // Requires form knowledge
        case .kettlebell: return 50   // Technique dependent
        case .suspension: return 45   // Requires core stability
        case .barbell: return 35      // Heavy, needs spotter
        case .plate: return 30        // Awkward grip, advanced
        }
    }
    
    /// Complexity for progression system
    var complexity: EquipmentComplexity {
        switch self {
        case .machine, .cable: return .guided
        case .bodyweight, .band: return .basic
        case .dumbbell: return .freeWeight
        case .kettlebell, .suspension: return .skillBased
        case .barbell, .plate: return .advanced
        }
    }
    
    /// Child equipment types in this family
    var childEquipment: [String] {
        switch self {
        case .barbell:
            return ["barbell", "smith machine", "ez bar", "trap bar", "landmine", "olympic barbell"]
        case .bodyweight:
            return ["bodyweight", "chair", "wall", "pull-up bar", "stability ball", 
                    "step platform", "medicine ball", "dip bars", "floor mat"]
        case .suspension:
            return ["trx", "gymnastic rings", "suspension trainer", "rings"]
        case .dumbbell:
            return ["dumbbell", "dumbbells"]
        case .cable:
            return ["cable", "cable machine", "cables"]
        case .machine:
            return ["machine", "lever machine", "leg press", "leg extension", 
                    "leg curl", "chest press machine", "lat pulldown machine",
                    "cable crossover", "pec deck", "hack squat machine"]
        case .kettlebell:
            return ["kettlebell", "kettlebells"]
        case .band:
            return ["band", "resistance band", "bands", "loop band", "mini band"]
        case .plate:
            return ["plate", "weight plate", "plates"]
        }
    }
}

enum EquipmentComplexity: Int, Comparable, Sendable {
    case guided = 1      // Machine, Cable - movement is guided
    case basic = 2       // Bodyweight, Band - simple movements
    case freeWeight = 3  // Dumbbell - requires stabilization
    case skillBased = 4  // Kettlebell, TRX - technique dependent
    case advanced = 5    // Barbell - heaviest, most complex
    
    static func < (lhs: EquipmentComplexity, rhs: EquipmentComplexity) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Equipment Hierarchy Service

final class EquipmentHierarchyService: @unchecked Sendable {
    static let shared = EquipmentHierarchyService()
    
    private init() {}
    
    // MARK: - Family Lookup
    
    /// Get the equipment family for a specific equipment string
    func getFamily(for equipment: String) -> EquipmentFamily? {
        let equipLower = equipment.lowercased().trimmingCharacters(in: .whitespaces)
        
        for family in EquipmentFamily.allCases {
            if family.childEquipment.contains(where: { equipLower.contains($0) || $0.contains(equipLower) }) {
                return family
            }
        }
        
        // Fallback pattern matching
        if equipLower.contains("machine") || equipLower.contains("lever") || 
           equipLower.contains("press machine") {
            return .machine
        }
        if equipLower.contains("cable") {
            return .cable
        }
        if equipLower.contains("dumbbell") {
            return .dumbbell
        }
        if equipLower.contains("barbell") || equipLower.contains("smith") {
            return .barbell
        }
        if equipLower.contains("band") {
            return .band
        }
        if equipLower.contains("kettle") {
            return .kettlebell
        }
        if equipLower.contains("trx") || equipLower.contains("ring") || equipLower.contains("suspension") {
            return .suspension
        }
        if equipLower.contains("plate") {
            return .plate
        }
        if equipLower.isEmpty || equipLower == "none" || equipLower == "bodyweight" {
            return .bodyweight
        }
        
        return nil
    }
    
    /// Check if two equipment types are in the same family
    func areSameFamily(_ equipment1: String, _ equipment2: String) -> Bool {
        guard let family1 = getFamily(for: equipment1),
              let family2 = getFamily(for: equipment2) else {
            return false
        }
        return family1 == family2
    }
    
    // MARK: - Recommendation Scoring
    
    /// Get beginner equipment boost for recommendation scoring
    /// Returns positive boost for beginner-friendly equipment
    func getBeginnerFriendlinessBoost(
        equipment: String,
        userWorkoutCount: Int,
        experienceLevel: String
    ) -> Double {
        guard let family = getFamily(for: equipment) else { return 0 }
        
        let level = experienceLevel.lowercased()
        let beginnerScore = Double(family.beginnerScore)
        
        // Advanced users don't need equipment guidance
        if level == "advanced" {
            return 0
        }
        
        // Intermediate users get minimal guidance
        if level == "intermediate" {
            guard userWorkoutCount < 3 else { return 0 }
            // Small boost for guided equipment on first few workouts
            if family.complexity == .guided {
                return 20
            }
            return 0
        }
        
        // Beginners get progressive equipment exposure
        // Phase out over 10 workouts
        let phaseOutFactor = max(0, 1.0 - (Double(userWorkoutCount) / 10.0))
        
        // Convert beginner score (0-100) to recommendation boost
        // Machines (95) get big boost, Barbells (35) get penalty
        let normalizedScore = (beginnerScore - 50) / 50.0  // -1 to +1 range
        let boost = normalizedScore * 100 * phaseOutFactor
        
        return boost
    }
    
    /// Get complexity penalty for beginners
    func getComplexityPenalty(
        equipment: String,
        userWorkoutCount: Int,
        experienceLevel: String
    ) -> Double {
        guard let family = getFamily(for: equipment) else { return 0 }
        
        let level = experienceLevel.lowercased()
        
        // No penalty for experienced users
        if level == "advanced" || level == "intermediate" {
            return 0
        }
        
        // Beginners get penalized for complex equipment early on
        guard userWorkoutCount < 5 else { return 0 }
        
        let complexityValue = Double(family.complexity.rawValue)
        
        // Penalty increases with complexity
        // guided (1) = 0, basic (2) = 0, freeWeight (3) = -15, skillBased (4) = -30, advanced (5) = -45
        if complexityValue <= 2 {
            return 0
        }
        
        let penalty = (complexityValue - 2) * 15
        let phaseOutFactor = max(0, 1.0 - (Double(userWorkoutCount) / 5.0))
        
        return -penalty * phaseOutFactor
    }
    
    // MARK: - Smart Substitutions
    
    /// Get equipment families that are good substitutes for the given equipment
    func getSimilarFamilies(for equipment: String) -> [EquipmentFamily] {
        guard let family = getFamily(for: equipment) else { return [] }
        
        switch family {
        case .barbell:
            return [.dumbbell, .machine, .cable]  // Can substitute with these
        case .dumbbell:
            return [.barbell, .kettlebell, .cable]
        case .cable:
            return [.machine, .band, .dumbbell]
        case .machine:
            return [.cable, .dumbbell]
        case .kettlebell:
            return [.dumbbell]
        case .band:
            return [.cable, .bodyweight]
        case .bodyweight:
            return [.band, .suspension]
        case .suspension:
            return [.bodyweight, .cable]
        case .plate:
            return [.dumbbell, .kettlebell]
        }
    }
    
    /// Check if substituting from equipment1 to equipment2 is a reasonable swap
    func isReasonableSubstitution(from equipment1: String, to equipment2: String) -> Bool {
        // Same family = always reasonable
        if areSameFamily(equipment1, equipment2) {
            return true
        }
        
        guard let family1 = getFamily(for: equipment1) else { return true }
        let similarFamilies = getSimilarFamilies(for: equipment1)
        
        if let family2 = getFamily(for: equipment2) {
            return similarFamilies.contains(family2)
        }
        
        return true  // Default to allowing if we can't determine
    }
    
    // MARK: - Workout Location Equipment
    
    /// Get auto-included equipment for a workout location
    func getAutoIncludedEquipment(for location: WorkoutLocation) -> [EquipmentFamily] {
        switch location {
        case .gym:
            return [.barbell, .dumbbell, .cable, .machine, .bodyweight]
        case .home:
            return [.bodyweight, .band]  // Others are optional
        case .outdoor:
            return [.bodyweight, .band]
        case .hybrid:
            return [.dumbbell, .bodyweight, .band, .cable, .machine]
        }
    }
    
    /// Get recommended equipment order for beginners at a location
    func getBeginnerEquipmentProgression(for location: WorkoutLocation) -> [EquipmentFamily] {
        switch location {
        case .gym:
            return [.machine, .cable, .dumbbell, .bodyweight, .barbell]
        case .home:
            return [.bodyweight, .band, .dumbbell, .kettlebell]
        case .outdoor:
            return [.bodyweight, .band]
        case .hybrid:
            return [.machine, .cable, .dumbbell, .bodyweight, .band]
        }
    }
    
    // MARK: - Variety Scoring
    
    /// Get variety score based on equipment exercise availability
    /// Higher score = more exercise options available
    func getVarietyScore(for equipment: String) -> Double {
        guard let family = getFamily(for: equipment) else { return 0.5 }
        
        // Normalize exercise count to 0-1 scale
        // Bodyweight has most (3988), Plate has least (26)
        let maxExercises = 3988.0
        let normalized = Double(family.exerciseCount) / maxExercises
        
        return normalized
    }
    
    /// Check if user has good equipment variety
    func hasGoodEquipmentVariety(userEquipment: [String]) -> Bool {
        var families: Set<EquipmentFamily> = []
        
        for equipment in userEquipment {
            if let family = getFamily(for: equipment) {
                families.insert(family)
            }
        }
        
        // Good variety = at least 3 different families
        return families.count >= 3
    }
}

// MARK: - Workout Location

enum WorkoutLocation: String, CaseIterable, Sendable {
    case gym
    case home
    case outdoor
    case hybrid
}

// MARK: - Integration with Recommendation System

extension EquipmentHierarchyService {
    
    /// Combined equipment score for the recommendation system
    /// Considers beginner-friendliness, complexity, and variety
    func getEquipmentRecommendationScore(
        equipment: String,
        userWorkoutCount: Int,
        experienceLevel: String,
        userEquipment: [String]
    ) -> Double {
        var score: Double = 0
        
        // 1. Beginner friendliness boost/penalty
        score += getBeginnerFriendlinessBoost(
            equipment: equipment,
            userWorkoutCount: userWorkoutCount,
            experienceLevel: experienceLevel
        )
        
        // 2. Complexity penalty for beginners
        score += getComplexityPenalty(
            equipment: equipment,
            userWorkoutCount: userWorkoutCount,
            experienceLevel: experienceLevel
        )
        
        // 3. Small boost for equipment user has (they selected it, so they want to use it)
        let equipLower = equipment.lowercased()
        let hasEquipment = userEquipment.contains { 
            $0.lowercased().contains(equipLower) || equipLower.contains($0.lowercased())
        }
        if hasEquipment {
            score += 10
        }
        
        return score
    }
    
    /// Get swap penalty based on equipment family relationship
    /// Swapping to similar equipment family = lower penalty
    func getSwapFamilyPenalty(from originalEquipment: String, to newEquipment: String) -> Double {
        // Same family = no penalty
        if areSameFamily(originalEquipment, newEquipment) {
            return 0
        }
        
        // Reasonable substitution = small penalty
        if isReasonableSubstitution(from: originalEquipment, to: newEquipment) {
            return -5
        }
        
        // Unusual substitution = moderate penalty
        return -15
    }
}
