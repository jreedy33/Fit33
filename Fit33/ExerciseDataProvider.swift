import Foundation

// MARK: - ExerciseDataProvider
// Replaces ComprehensiveExerciseDatabase — loads exercise data from a JSON file
// instead of 7,795 lines of hardcoded Swift. This reduces compile time and
// makes exercise data editable without recompiling.

/// Provides exercise data loaded from the bundled exercises.json file.
/// Lazy-loads and caches the parsed result on first access.
final class ExerciseDataProvider {
    static let shared = ExerciseDataProvider()
    
    // MARK: - Cached Data
    private var _exercises: [ExerciseData]?
    private var _byMuscleGroup: [String: [ExerciseData]]?
    private var _byEquipment: [String: [ExerciseData]]?
    private var _byCategory: [String: [ExerciseData]]?
    private var _byName: [String: ExerciseData]?
    
    private init() {}
    
    // MARK: - Primary Access (lazy-loaded)
    
    /// All exercises from the database. Loaded from JSON on first access, cached thereafter.
    var exercises: [ExerciseData] {
        if let cached = _exercises { return cached }
        let loaded = loadExercisesFromBundle()
        _exercises = loaded
        return loaded
    }
    
    // MARK: - Query Methods
    
    /// Get all exercises.
    func getAllExercises() -> [ExerciseData] {
        return exercises
    }
    
    /// Get exercises for a specific muscle group (case-insensitive).
    func getExercises(forMuscleGroup muscleGroup: String) -> [ExerciseData] {
        if _byMuscleGroup == nil { buildMuscleGroupIndex() }
        return _byMuscleGroup?[muscleGroup.lowercased()] ?? []
    }
    
    /// Get exercises for a specific equipment type (case-insensitive).
    func getExercises(forEquipment equipment: String) -> [ExerciseData] {
        if _byEquipment == nil { buildEquipmentIndex() }
        return _byEquipment?[equipment.lowercased()] ?? []
    }
    
    /// Get exercises for a specific category (case-insensitive).
    func getExercises(forCategory category: String) -> [ExerciseData] {
        if _byCategory == nil { buildCategoryIndex() }
        return _byCategory?[category.lowercased()] ?? []
    }
    
    /// Find a specific exercise by exact name (case-insensitive).
    func getExercise(byName name: String) -> ExerciseData? {
        if _byName == nil { buildNameIndex() }
        return _byName?[name.lowercased()]
    }
    
    /// Search exercises by query string. Matches against name, category,
    /// muscle groups, and equipment (case-insensitive).
    func searchExercises(query: String) -> [ExerciseData] {
        let q = query.lowercased()
        return exercises.filter { exercise in
            exercise.name.lowercased().contains(q) ||
            exercise.category.lowercased().contains(q) ||
            exercise.equipment.lowercased().contains(q) ||
            exercise.primaryMuscle.lowercased().contains(q) ||
            exercise.muscleGroups.contains(where: { $0.lowercased().contains(q) })
        }
    }
    
    // MARK: - Index Building (on-demand)
    
    private func buildMuscleGroupIndex() {
        var index: [String: [ExerciseData]] = [:]
        for exercise in exercises {
            for muscle in exercise.muscleGroups {
                index[muscle.lowercased(), default: []].append(exercise)
            }
        }
        _byMuscleGroup = index
    }
    
    private func buildEquipmentIndex() {
        var index: [String: [ExerciseData]] = [:]
        for exercise in exercises {
            index[exercise.equipment.lowercased(), default: []].append(exercise)
        }
        _byEquipment = index
    }
    
    private func buildCategoryIndex() {
        var index: [String: [ExerciseData]] = [:]
        for exercise in exercises {
            index[exercise.category.lowercased(), default: []].append(exercise)
        }
        _byCategory = index
    }
    
    private func buildNameIndex() {
        var index: [String: ExerciseData] = [:]
        for exercise in exercises {
            index[exercise.name.lowercased()] = exercise
        }
        _byName = index
    }
    
    // MARK: - JSON Loading
    
    private func loadExercisesFromBundle() -> [ExerciseData] {
        let startTime = CFAbsoluteTimeGetCurrent()
        
        guard let url = Bundle.main.url(forResource: "exercises", withExtension: "json") else {
            print("❌ [ExerciseDataProvider] exercises.json not found in bundle!")
            return []
        }
        
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            let exercises = try decoder.decode([ExerciseData].self, from: data)
            
            let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            print("📦 [ExerciseDataProvider] Loaded \(exercises.count) exercises from JSON in \(String(format: "%.1f", elapsed))ms")
            
            return exercises
        } catch {
            print("❌ [ExerciseDataProvider] Failed to decode exercises.json: \(error)")
            return []
        }
    }
}
