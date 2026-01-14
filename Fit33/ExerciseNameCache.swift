//
//  ExerciseNameCache.swift
//  Fit33
//
//  Caches exercise names for WorkoutExercise objects to prevent "Unknown Exercise" issues
//

import Foundation

// MARK: - Exercise Name Cache
/// Caches exercise names for WorkoutExercise objects to prevent "Unknown Exercise" issues
/// when the exercise relationship is nil (e.g., during sync or when exercises haven't loaded)
class ExerciseNameCache {
    static let shared = ExerciseNameCache()
    
    private let cacheKey = "exerciseNameCache"
    private var memoryCache: [String: String] = [:]
    private let lock = NSLock()
    
    private init() {
        loadFromDisk()
    }
    
    /// Cache an exercise name for a WorkoutExercise ID
    func cacheName(_ name: String, forWorkoutExerciseId id: String) {
        lock.lock()
        defer { lock.unlock() }
        
        memoryCache[id] = name
        
        // Debounce disk writes
        DispatchQueue.main.async { [weak self] in
            self?.saveToDisk()
        }
    }
    
    /// Get cached name for a WorkoutExercise ID
    func getName(forWorkoutExerciseId id: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return memoryCache[id]
    }
    
    /// Cache multiple names at once (for bulk sync operations)
    func cacheNames(_ names: [String: String]) {
        lock.lock()
        defer { lock.unlock() }
        
        for (id, name) in names {
            memoryCache[id] = name
        }
        
        saveToDisk()
    }
    
    private func loadFromDisk() {
        if let data = UserDefaults.standard.dictionary(forKey: cacheKey) as? [String: String] {
            memoryCache = data
            #if DEBUG
            print("📦 [ExerciseNameCache] Loaded \(memoryCache.count) cached names")
            #endif
        }
    }
    
    private func saveToDisk() {
        // Limit cache size to prevent unbounded growth (keep last 500 entries)
        if memoryCache.count > 500 {
            let keysToRemove = Array(memoryCache.keys.prefix(memoryCache.count - 500))
            for key in keysToRemove {
                memoryCache.removeValue(forKey: key)
            }
        }
        
        UserDefaults.standard.set(memoryCache, forKey: cacheKey)
    }
    
    /// Clear the cache (e.g., on logout)
    func clearCache() {
        lock.lock()
        defer { lock.unlock() }
        
        memoryCache.removeAll()
        UserDefaults.standard.removeObject(forKey: cacheKey)
    }
}
