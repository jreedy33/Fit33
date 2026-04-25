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
        memoryCache[id] = name
        lock.unlock()

        // Debounce disk writes. saveToDisk() takes the lock itself to snapshot
        // memoryCache before serializing to UserDefaults — previously this was
        // a data race (lock released here, dict mutated concurrently while
        // saveToDisk read it unlocked) which could produce torn dictionaries
        // and crash CFPreferences with "non-property list object" (bug-intel
        // fingerprint 3896c649).
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
        for (id, name) in names {
            memoryCache[id] = name
        }
        lock.unlock()

        saveToDisk()
    }
    
    private func loadFromDisk() {
        if let data = UserDefaults.standard.dictionary(forKey: cacheKey) as? [String: String] {
            memoryCache = data
            #if DEBUG
            AppLogger.debug("📦 [ExerciseNameCache] Loaded \(memoryCache.count) cached names", category: .workout)
            #endif
        }
    }

    private func saveToDisk() {
        // Snapshot under lock so we never hand CFPreferences a dictionary that
        // is being mutated on another thread. Defensive type filter: only
        // String→String pairs survive, so a programming error elsewhere in the
        // app can never produce the "non-property list object" crash again —
        // it becomes a log line instead.
        lock.lock()
        let rawSnapshot = memoryCache
        lock.unlock()

        var safeSnapshot: [String: String] = [:]
        safeSnapshot.reserveCapacity(rawSnapshot.count)
        var droppedCount = 0
        for (key, value) in rawSnapshot {
            // `memoryCache` is typed `[String: String]` but Swift dictionaries
            // can carry bridged NSObject values when populated via ObjC bridge
            // paths; reject anything non-plist just in case.
            guard !key.isEmpty, !value.isEmpty else {
                droppedCount += 1
                continue
            }
            safeSnapshot[key] = value
        }
        if droppedCount > 0 {
            AppLogger.error(
                "[ExerciseNameCache] Dropped \(droppedCount) invalid entries before disk write",
                category: .workout
            )
        }

        UserDefaults.standard.set(safeSnapshot, forKey: cacheKey)
    }
    
    /// Clear the cache (e.g., on logout)
    func clearCache() {
        lock.lock()
        defer { lock.unlock() }
        
        memoryCache.removeAll()
        UserDefaults.standard.removeObject(forKey: cacheKey)
    }
}
