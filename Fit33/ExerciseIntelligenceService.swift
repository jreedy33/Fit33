import Foundation
import CoreData

struct ExerciseIntelligenceProfile: Equatable {
    let exerciseName: String
    let primaryMuscles: [String]
    let secondaryMuscles: [String]
    let movementPattern: String
    let forceVector: String
    let planeOfMotion: String
    let movementType: String
    let laterality: String
    let difficultyLevel: Int
    let complexityScore: Int
    let strengthRating: Int
    let hypertrophyRating: Int
    let powerRating: Int
    let enduranceRating: Int
    let bodyPosition: String
    let benchAngle: Int?
    let gripType: String?
    let gripWidth: String?
    let optimalRepRange: ClosedRange<Int>
    let placementInWorkout: String
    let fatigability: String
    let popularityScore: Int
    let homeGymFriendly: Bool
}

struct EquipmentSubstitutionProfile: Equatable {
    let sourceEquipment: String
    let substituteEquipment: String
    let qualityScore: Double
    let cues: String?
    let notes: String?
}

struct ExercisePairingProfile: Equatable, Identifiable {
    let id = UUID()
    let primaryExercise: String
    let secondaryExercise: String
    let pairingFocus: [String]
    let rationale: String?
    let intensityBalance: String?
    let recommendedTempos: [String]
    let equipmentContext: [String: String]
    let synergyScore: Double
}

final class ExerciseIntelligenceService: ObservableObject {
    static let shared = ExerciseIntelligenceService()
    
    @Published private(set) var profiles: [String: ExerciseIntelligenceProfile] = [:]
    @Published private(set) var equipmentSubstitutions: [String: [EquipmentSubstitutionProfile]] = [:]
    @Published private(set) var exercisePairings: [ExercisePairingProfile] = []
    
    private init() {}
    
    func resetProfiles() {
        profiles.removeAll()
    }
    
    func updateProfile(_ profile: ExerciseIntelligenceProfile) {
        profiles[normalizedKey(for: profile.exerciseName)] = profile
    }
    
    func updateProfiles(_ profiles: [ExerciseIntelligenceProfile]) {
        for profile in profiles {
            updateProfile(profile)
        }
    }
    
    func profile(for exercise: Exercise) -> ExerciseIntelligenceProfile? {
        guard let name = exercise.name else { return nil }
        return profiles[normalizedKey(for: name)]
    }
    
    func normalizedKey(for name: String) -> String {
        return name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
    
    func refreshSupplementalData() async {
        do {
            // Fetch equipment substitutions (if table exists)
            let substitutionDTOs = try await SupabaseManager.shared.fetchEquipmentSubstitutions()
            
            let subs = Dictionary(grouping: substitutionDTOs.map { dto in
                EquipmentSubstitutionProfile(
                    sourceEquipment: dto.sourceEquipment,
                    substituteEquipment: dto.substituteEquipment,
                    qualityScore: dto.qualityScore ?? 0.4,
                    cues: dto.cues,
                    notes: dto.notes
                )
            }, by: { $0.sourceEquipment.lowercased() })
            
            await MainActor.run {
                self.equipmentSubstitutions = subs
                // Note: Exercise pairings are now handled by SmartExercisePairingEngine locally
                // The exercise_pairings table was deprecated and data moved to exercises table
            }
        } catch {
            print("⚠️ Failed to refresh exercise intelligence supplemental data: \(error)")
        }
    }
    
    func equipmentMatchScore(for exercise: Exercise, availableEquipment: Set<String>) -> Int {
        let normalizedAvailable = Set(availableEquipment.map { normalizedKey(for: $0) })
        let required = normalizedKey(for: exercise.equipment ?? "Bodyweight")
        
        if normalizedAvailable.contains(required) || required == "bodyweight" {
            return 10
        }
        
        guard let options = equipmentSubstitutions[required] else {
            return normalizedAvailable.isEmpty ? 0 : -25
        }
        
        if let best = options.first(where: { normalizedAvailable.contains(normalizedKey(for: $0.substituteEquipment)) }) {
            return max(Int(best.qualityScore * 10), 2)
        }
        
        return -25
    }
    
    func bestPairings(for exercise: Exercise) -> [ExercisePairingProfile] {
        guard let name = exercise.name else { return [] }
        let key = normalizedKey(for: name)
        return exercisePairings.filter { pairing in
            normalizedKey(for: pairing.primaryExercise) == key ||
            normalizedKey(for: pairing.secondaryExercise) == key
        }
    }
}

