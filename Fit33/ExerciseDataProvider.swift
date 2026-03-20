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
    
    private init() {}
    
    // MARK: - Primary Access (lazy-loaded)
    
    /// All exercises from the database. Loaded from JSON on first access, cached thereafter.
    var exercises: [ExerciseData] {
        if let cached = _exercises { return cached }
        let loaded = loadExercisesFromBundle()
        _exercises = loaded
        return loaded
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
