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

