//
//  CoreDataExtensions.swift
//  BuiltSimple
//
//  Helper extensions to work with Transformable array properties
//

import Foundation
import CoreData

// MARK: - Exercise Extension
extension Exercise {
    // Helper to get muscleGroups as [String]
    func getMuscleGroups() -> [String]? {
        return self.muscleGroups as? [String]
    }
    
    // Helper to set muscleGroups from [String]
    func setMuscleGroups(_ groups: [String]) {
        self.muscleGroups = groups as NSObject
    }
}

// MARK: - User Extension  
extension User {
    // Helper to get equipment as [String]
    func getEquipment() -> [String]? {
        return self.equipment as? [String]
    }
    
    // Helper to set equipment from [String]
    func setEquipment(_ items: [String]) {
        self.equipment = items as NSObject
    }
}

// MARK: - WorkoutExercise Extension
extension WorkoutExercise {
    /// Safe display name that uses multiple fallbacks to never show "Unknown Exercise"
    /// Priority: 1. Cached nickname 2. Exercise relationship 3. Cached name 4. "Loading..."
    var safeDisplayName: String {
        // 1. Try the exercise relationship (most common case)
        if let exerciseName = exercise?.displayName, !exerciseName.isEmpty {
            return exerciseName
        }
        
        // 2. Try looking up from cached exercise names
        if let workoutExerciseId = id?.uuidString,
           let cachedName = ExerciseNameCache.shared.getName(forWorkoutExerciseId: workoutExerciseId),
           !cachedName.isEmpty {
            return cachedName
        }
        
        // 3. If exercises are still loading, show a loading state instead of "Unknown"
        if !ExerciseLibraryService.shared.isExercisesReady {
            return "Loading..."
        }
        
        // 4. Fallback for truly unknown (rare edge case)
        return "Exercise"
    }
    
    /// Safe category that uses the exercise relationship or returns a default
    var safeCategory: String {
        exercise?.category ?? "Strength"
    }
    
    /// Safe muscle groups that uses the exercise relationship or returns empty array
    var safeMuscleGroups: [String] {
        (exercise?.muscleGroups as? [String]) ?? []
    }
}
