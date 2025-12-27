import Foundation

// MARK: - Exercise Mapping Service
/// Pre-computed exercise relationships for fast lookup
/// Maps: substitutions, pairings, progressions, variations

final class ExerciseMappingService {
    static let shared = ExerciseMappingService()
    
    // MARK: - Pre-computed Maps
    
    /// Exercise name → Similar exercises with different equipment
    private var substitutionMap: [String: [SubstitutionEntry]] = [:]
    
    /// Exercise name → Complementary exercises that pair well
    private var pairingMap: [String: [PairingEntry]] = [:]
    
    /// Exercise name → Easier/harder variations
    private var progressionMap: [String: ProgressionChain] = [:]
    
    /// Movement pattern → All exercises in that pattern
    private var patternMap: [String: Set<String>] = [:]
    
    /// Muscle → Best exercises ranked by effectiveness
    private var muscleEffectivenessMap: [String: [RankedExercise]] = [:]
    
    private var isInitialized = false
    private let buildQueue = DispatchQueue(label: "exercise.mapping.build", qos: .utility)
    
    // MARK: - Types
    
    struct SubstitutionEntry {
        let exerciseName: String
        let equipment: String
        let similarityScore: Double // 0-1, how similar the movement is
        let reason: String
    }
    
    struct PairingEntry {
        let exerciseName: String
        let pairingType: PairingType
        let synergyScore: Double // 0-1, how well they work together
        let reason: String
        
        enum PairingType: String {
            case superset = "Superset"       // Antagonist pairing
            case compound = "Compound Set"   // Same muscle group
            case circuit = "Circuit"         // Different patterns
            case postExhaust = "Post-Exhaust" // Compound → Isolation
            case preExhaust = "Pre-Exhaust"   // Isolation → Compound
        }
    }
    
    struct ProgressionChain {
        let easierVariations: [String]  // Progressively easier
        let harderVariations: [String]  // Progressively harder
    }
    
    struct RankedExercise {
        let name: String
        let effectivenessScore: Double // 0-100
        let isCompound: Bool
        let equipment: String
    }
    
    // MARK: - Initialization
    
    private init() {}
    
    /// Build all maps from exercise database (call once on app launch)
    /// OPTIMIZED: Builds maps incrementally to prevent blocking
    func buildMaps() async {
        guard !isInitialized else {
            #if DEBUG
            print("🗺️ ExerciseMappingService: Already initialized, skipping")
            #endif
            return
        }
        
        #if DEBUG
        let startTime = Date()
        print("🗺️ [MAPPING] Starting to build exercise maps...")
        #endif
        
        do {
            // Limit initial fetch for faster startup
            let exercises = try await SupabaseManager.shared.fetchAllExercises()
            
            #if DEBUG
            print("🗺️ [MAPPING] Fetched \(exercises.count) exercises, building maps...")
            #endif
            
            // Build maps in chunks with yields to prevent blocking
            await Task.yield()
            
            buildQueue.async { [weak self] in
                guard let self = self else { return }
                
                // Build only essential maps first
                self.buildPatternMap(from: exercises)
                
                #if DEBUG
                print("🗺️ [MAPPING] Pattern map built")
                #endif
                
                // Build other maps with lower priority
                self.buildMuscleEffectivenessMap(from: exercises)
                
                #if DEBUG
                print("🗺️ [MAPPING] Effectiveness map built")
                #endif
                
                // These are expensive - build only first 1000 exercises
                let limitedExercises = Array(exercises.prefix(1000))
                self.buildSubstitutionMap(from: limitedExercises)
                self.buildPairingMap(from: limitedExercises)
                self.buildProgressionMap(from: limitedExercises)
                
                self.isInitialized = true
                
                #if DEBUG
                let elapsed = Date().timeIntervalSince(startTime)
                print("🗺️ [MAPPING] ✅ All maps built in \(String(format: "%.2f", elapsed))s")
                print("   Substitutions: \(self.substitutionMap.count)")
                print("   Pairings: \(self.pairingMap.count)")
                print("   Progressions: \(self.progressionMap.count)")
                print("   Patterns: \(self.patternMap.count)")
                print("   Muscle rankings: \(self.muscleEffectivenessMap.count)")
                #endif
            }
        } catch {
            print("❌ ExerciseMappingService: Failed to build maps: \(error)")
        }
    }
    
    // MARK: - Public API
    
    /// Get substitutes for an exercise with available equipment
    func getSubstitutes(for exerciseName: String, availableEquipment: [String]) -> [SubstitutionEntry] {
        let normalized = exerciseName.lowercased()
        guard let substitutes = substitutionMap[normalized] else { return [] }
        
        let normalizedEquipment = Set(availableEquipment.map { ExerciseFilterService.normalizeEquipment($0) })
        
        return substitutes
            .filter { normalizedEquipment.contains($0.equipment) }
            .sorted { $0.similarityScore > $1.similarityScore }
    }
    
    /// Get best exercise pairings for supersets/circuits
    func getPairings(for exerciseName: String, type: PairingEntry.PairingType? = nil) -> [PairingEntry] {
        let normalized = exerciseName.lowercased()
        guard let pairings = pairingMap[normalized] else { return [] }
        
        if let specificType = type {
            return pairings.filter { $0.pairingType == specificType }
        }
        
        return pairings.sorted { $0.synergyScore > $1.synergyScore }
    }
    
    /// Get easier/harder progressions of an exercise
    func getProgressions(for exerciseName: String) -> ProgressionChain? {
        return progressionMap[exerciseName.lowercased()]
    }
    
    /// Get all exercises for a movement pattern
    func getExercisesForPattern(_ pattern: String) -> [String] {
        return Array(patternMap[pattern.lowercased()] ?? [])
    }
    
    /// Get best exercises for a muscle ranked by effectiveness
    func getBestExercisesForMuscle(_ muscle: String, limit: Int = 10) -> [RankedExercise] {
        let normalized = muscle.lowercased()
        guard let ranked = muscleEffectivenessMap[normalized] else { return [] }
        return Array(ranked.prefix(limit))
    }
    
    /// Quick lookup: Can we substitute exercise A with B?
    func canSubstitute(_ original: String, with substitute: String) -> Bool {
        let normalized = original.lowercased()
        return substitutionMap[normalized]?.contains { $0.exerciseName.lowercased() == substitute.lowercased() } ?? false
    }
    
    /// Quick lookup: Do exercises A and B pair well?
    func pairsWellWith(_ exerciseA: String, _ exerciseB: String) -> Bool {
        let normalized = exerciseA.lowercased()
        return pairingMap[normalized]?.contains { $0.exerciseName.lowercased() == exerciseB.lowercased() } ?? false
    }
    
    // MARK: - Map Building
    
    private func buildSubstitutionMap(from exercises: [ExerciseDTO]) {
        // Group exercises by primary muscle + movement pattern
        var musclePatternGroups: [String: [ExerciseDTO]] = [:]
        
        for exercise in exercises {
            for muscle in exercise.primaryMusclesArray {
                let pattern = inferMovementPattern(exercise.name)
                let key = "\(muscle.lowercased())_\(pattern)"
                
                if musclePatternGroups[key] == nil {
                    musclePatternGroups[key] = []
                }
                musclePatternGroups[key]?.append(exercise)
            }
        }
        
        // For each exercise, find substitutes from same muscle+pattern group
        for exercise in exercises {
            let normalizedName = exercise.name.lowercased()
            var substitutes: [SubstitutionEntry] = []
            
            for muscle in exercise.primaryMusclesArray {
                let pattern = inferMovementPattern(exercise.name)
                let key = "\(muscle.lowercased())_\(pattern)"
                
                guard let group = musclePatternGroups[key] else { continue }
                
                for candidate in group {
                    guard candidate.name.lowercased() != normalizedName else { continue }
                    
                    let similarity = calculateSimilarity(exercise, candidate)
                    let equipment = ExerciseFilterService.normalizeEquipment(candidate.equipment)
                    
                    let entry = SubstitutionEntry(
                        exerciseName: candidate.name,
                        equipment: equipment,
                        similarityScore: similarity,
                        reason: "Same \(muscle) \(pattern) movement"
                    )
                    substitutes.append(entry)
                }
            }
            
            // Keep top 10 substitutes per exercise
            substitutionMap[normalizedName] = Array(substitutes
                .sorted { $0.similarityScore > $1.similarityScore }
                .prefix(10))
        }
    }
    
    private func buildPairingMap(from exercises: [ExerciseDTO]) {
        for exercise in exercises {
            let normalizedName = exercise.name.lowercased()
            var pairings: [PairingEntry] = []
            
            // Find antagonist pairings (push/pull, etc.)
            let antagonistMuscles = getAntagonistMuscles(for: exercise.primaryMusclesArray)
            
            for candidate in exercises {
                guard candidate.name.lowercased() != normalizedName else { continue }
                
                let candidateMuscles = Set(candidate.primaryMusclesArray.map { $0.lowercased() })
                
                // Check for antagonist pairing (superset potential)
                if !antagonistMuscles.isDisjoint(with: candidateMuscles) {
                    let entry = PairingEntry(
                        exerciseName: candidate.name,
                        pairingType: .superset,
                        synergyScore: 0.9,
                        reason: "Antagonist muscles - great for supersets"
                    )
                    pairings.append(entry)
                }
                
                // Check for same muscle group (compound set)
                let exerciseMuscles = Set(exercise.primaryMusclesArray.map { $0.lowercased() })
                if !exerciseMuscles.isDisjoint(with: candidateMuscles) {
                    let isPostExhaust = isCompound(exercise.name) && !isCompound(candidate.name)
                    let isPreExhaust = !isCompound(exercise.name) && isCompound(candidate.name)
                    
                    let type: PairingEntry.PairingType
                    let score: Double
                    let reason: String
                    
                    if isPostExhaust {
                        type = .postExhaust
                        score = 0.85
                        reason = "Compound → Isolation for muscle fatigue"
                    } else if isPreExhaust {
                        type = .preExhaust
                        score = 0.8
                        reason = "Isolation → Compound pre-exhaust"
                    } else {
                        type = .compound
                        score = 0.7
                        reason = "Same muscle group compound set"
                    }
                    
                    let entry = PairingEntry(
                        exerciseName: candidate.name,
                        pairingType: type,
                        synergyScore: score,
                        reason: reason
                    )
                    pairings.append(entry)
                }
            }
            
            // Keep top 15 pairings per exercise
            pairingMap[normalizedName] = Array(pairings
                .sorted { $0.synergyScore > $1.synergyScore }
                .prefix(15))
        }
    }
    
    private func buildProgressionMap(from exercises: [ExerciseDTO]) {
        // Group exercises by base name (without equipment/variation modifiers)
        var baseNameGroups: [String: [ExerciseDTO]] = [:]
        
        for exercise in exercises {
            let baseName = extractBaseName(exercise.name)
            if baseNameGroups[baseName] == nil {
                baseNameGroups[baseName] = []
            }
            baseNameGroups[baseName]?.append(exercise)
        }
        
        // For each exercise, find easier/harder variations
        for exercise in exercises {
            let baseName = extractBaseName(exercise.name)
            guard let group = baseNameGroups[baseName], group.count > 1 else { continue }
            
            let difficulty = estimateDifficulty(exercise.name)
            var easier: [String] = []
            var harder: [String] = []
            
            for variant in group {
                guard variant.name != exercise.name else { continue }
                
                let variantDifficulty = estimateDifficulty(variant.name)
                if variantDifficulty < difficulty {
                    easier.append(variant.name)
                } else if variantDifficulty > difficulty {
                    harder.append(variant.name)
                }
            }
            
            let normalizedName = exercise.name.lowercased()
            progressionMap[normalizedName] = ProgressionChain(
                easierVariations: easier,
                harderVariations: harder
            )
        }
    }
    
    private func buildPatternMap(from exercises: [ExerciseDTO]) {
        for exercise in exercises {
            let pattern = inferMovementPattern(exercise.name)
            
            if patternMap[pattern] == nil {
                patternMap[pattern] = []
            }
            patternMap[pattern]?.insert(exercise.name.lowercased())
        }
    }
    
    private func buildMuscleEffectivenessMap(from exercises: [ExerciseDTO]) {
        var muscleExercises: [String: [ExerciseDTO]] = [:]
        
        for exercise in exercises {
            for muscle in exercise.primaryMusclesArray {
                let normalized = muscle.lowercased()
                if muscleExercises[normalized] == nil {
                    muscleExercises[normalized] = []
                }
                muscleExercises[normalized]?.append(exercise)
            }
        }
        
        for (muscle, exerciseList) in muscleExercises {
            let ranked = exerciseList.map { exercise -> RankedExercise in
                let effectiveness = calculateEffectiveness(exercise, for: muscle)
                return RankedExercise(
                    name: exercise.name,
                    effectivenessScore: effectiveness,
                    isCompound: isCompound(exercise.name),
                    equipment: ExerciseFilterService.normalizeEquipment(exercise.equipment)
                )
            }
            .sorted { $0.effectivenessScore > $1.effectivenessScore }
            
            muscleEffectivenessMap[muscle] = ranked
        }
    }
    
    // MARK: - Helper Functions
    
    private func inferMovementPattern(_ name: String) -> String {
        let lowercased = name.lowercased()
        
        if lowercased.contains("press") || lowercased.contains("push") { return "push" }
        if lowercased.contains("row") || lowercased.contains("pull") { return "pull" }
        if lowercased.contains("squat") || lowercased.contains("lunge") { return "squat" }
        if lowercased.contains("deadlift") || lowercased.contains("hip") { return "hinge" }
        if lowercased.contains("curl") { return "curl" }
        if lowercased.contains("extension") || lowercased.contains("extend") { return "extension" }
        if lowercased.contains("raise") { return "raise" }
        if lowercased.contains("fly") || lowercased.contains("flye") { return "fly" }
        if lowercased.contains("crunch") || lowercased.contains("plank") { return "core" }
        
        return "other"
    }
    
    private func calculateSimilarity(_ a: ExerciseDTO, _ b: ExerciseDTO) -> Double {
        var score = 0.0
        
        // ═══════════════════════════════════════════════════════════════
        // PRIMARY MUSCLE OVERLAP (Most Important - 0.35)
        // ═══════════════════════════════════════════════════════════════
        let aMuscles = Set(a.primaryMusclesArray.map { $0.lowercased() })
        let bMuscles = Set(b.primaryMusclesArray.map { $0.lowercased() })
        let muscleOverlap = Double(aMuscles.intersection(bMuscles).count) / Double(max(aMuscles.count, 1))
        score += muscleOverlap * 0.35
        
        // ═══════════════════════════════════════════════════════════════
        // MOVEMENT PATTERN MATCH (Very Important - 0.25)
        // ═══════════════════════════════════════════════════════════════
        let patternA = inferMovementPattern(a.name)
        let patternB = inferMovementPattern(b.name)
        if patternA == patternB && patternA != "other" {
            score += 0.25
        }
        
        // ═══════════════════════════════════════════════════════════════
        // EQUIPMENT CATEGORY MATCH (Important - 0.15)
        // ═══════════════════════════════════════════════════════════════
        let aEquip = a.equipment ?? ""
        let bEquip = b.equipment ?? ""
        let aEquipCat = getEquipmentCategory(aEquip)
        let bEquipCat = getEquipmentCategory(bEquip)
        if aEquipCat == bEquipCat {
            score += 0.15
        } else if aEquip.lowercased() == bEquip.lowercased() {
            score += 0.15 // Exact equipment match
        }
        
        // ═══════════════════════════════════════════════════════════════
        // SAME CATEGORY (0.1)
        // ═══════════════════════════════════════════════════════════════
        if a.category.lowercased() == b.category.lowercased() {
            score += 0.1
        }
        
        // ═══════════════════════════════════════════════════════════════
        // FORCE TYPE MATCH (Push/Pull - 0.1)
        // ═══════════════════════════════════════════════════════════════
        if let aForce = a.forceType, let bForce = b.forceType,
           !aForce.isEmpty && !bForce.isEmpty {
            if aForce.lowercased() == bForce.lowercased() {
                score += 0.1
            }
        }
        
        // ═══════════════════════════════════════════════════════════════
        // NAME KEYWORD SIMILARITY (0.05)
        // ═══════════════════════════════════════════════════════════════
        let movementKeywords = ["press", "curl", "row", "fly", "raise", "extension", "squat", "deadlift", "lunge"]
        for keyword in movementKeywords {
            if a.name.lowercased().contains(keyword) && b.name.lowercased().contains(keyword) {
                score += 0.05
                break
            }
        }
        
        return min(score, 1.0)
    }
    
    /// Get equipment category for similarity matching
    private func getEquipmentCategory(_ equipment: String) -> String {
        let lowered = equipment.lowercased()
        if lowered.contains("dumbbell") || lowered.contains("barbell") || lowered.contains("kettlebell") || lowered.contains("ez") {
            return "free_weights"
        }
        if lowered.contains("cable") {
            return "cables"
        }
        if lowered.contains("machine") || lowered.contains("lever") || lowered.contains("smith") || lowered.contains("sled") {
            return "machines"
        }
        if lowered.contains("body") || lowered == "none" || lowered.isEmpty {
            return "bodyweight"
        }
        if lowered.contains("band") || lowered.contains("resistance") {
            return "resistance"
        }
        return "other"
    }
    
    private func getAntagonistMuscles(for muscles: [String]) -> Set<String> {
        var antagonists: Set<String> = []
        
        let antagonistPairs: [String: [String]] = [
            "chest": ["back", "lats", "upper back"],
            "back": ["chest"],
            "lats": ["chest", "front delts"],
            "biceps": ["triceps"],
            "triceps": ["biceps"],
            "quads": ["hamstrings"],
            "hamstrings": ["quads"],
            "front delts": ["rear delts"],
            "rear delts": ["front delts", "chest"],
            "abs": ["lower back"],
            "lower back": ["abs"]
        ]
        
        for muscle in muscles {
            if let pairs = antagonistPairs[muscle.lowercased()] {
                antagonists.formUnion(pairs)
            }
        }
        
        return antagonists
    }
    
    private func isCompound(_ name: String) -> Bool {
        let compoundKeywords = ["press", "row", "squat", "deadlift", "pull-up", "pullup", "chin-up", "dip", "lunge", "clean", "snatch"]
        let lowercased = name.lowercased()
        return compoundKeywords.contains { lowercased.contains($0) }
    }
    
    private func extractBaseName(_ name: String) -> String {
        // Remove equipment and variation modifiers
        var baseName = name.lowercased()
        
        let modifiers = ["dumbbell", "barbell", "cable", "machine", "smith", "kettlebell", "band", "resistance",
                        "incline", "decline", "seated", "standing", "lying", "single arm", "single leg",
                        "wide grip", "close grip", "neutral grip", "underhand", "overhand"]
        
        for modifier in modifiers {
            baseName = baseName.replacingOccurrences(of: modifier, with: "").trimmingCharacters(in: .whitespaces)
        }
        
        return baseName
    }
    
    private func estimateDifficulty(_ name: String) -> Int {
        let lowercased = name.lowercased()
        var difficulty = 5
        
        // Easier variations
        if lowercased.contains("assisted") { difficulty -= 2 }
        if lowercased.contains("machine") { difficulty -= 1 }
        if lowercased.contains("seated") { difficulty -= 1 }
        if lowercased.contains("band") { difficulty -= 1 }
        
        // Harder variations
        if lowercased.contains("single") || lowercased.contains("one arm") || lowercased.contains("one leg") { difficulty += 2 }
        if lowercased.contains("weighted") { difficulty += 1 }
        if lowercased.contains("deficit") { difficulty += 1 }
        if lowercased.contains("pause") { difficulty += 1 }
        if lowercased.contains("explosive") || lowercased.contains("jump") { difficulty += 1 }
        
        return max(1, min(10, difficulty))
    }
    
    private func calculateEffectiveness(_ exercise: ExerciseDTO, for muscle: String) -> Double {
        var score = 50.0
        
        // Compound exercises more effective
        if isCompound(exercise.name) { score += 20 }
        
        // Primary target vs secondary
        if exercise.primaryMusclesArray.map({ $0.lowercased() }).contains(muscle.lowercased()) {
            score += 15
        }
        
        // Free weights generally more effective for strength
        let equipment = ExerciseFilterService.normalizeEquipment(exercise.equipment)
        switch equipment {
        case "Barbell": score += 10
        case "Dumbbells": score += 8
        case "Kettlebell": score += 6
        case "Cables": score += 4
        case "Bodyweight": score += 5
        case "Machines": score += 2
        default: break
        }
        
        return min(score, 100)
    }
}

