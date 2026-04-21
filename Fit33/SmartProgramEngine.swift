//
//  SmartProgramEngine.swift
//  GoFit
//
//  Smart Program Engine - Generates 10 personalized training programs
//  with progressive series, lazy day generation, and AI-powered recommendations
//

import Foundation
import CoreData
import SwiftUI
import Supabase

// MARK: - Cloud Sync DTOs

struct UserProgramDTO: Codable {
    let id: String
    let user_id: String
    let template_id: String
    let program_name: String
    let current_day: Int
    let total_days: Int
    let completed_days: Int
    let is_active: Bool
    let started_date: String
    let program_data: String
    let last_updated: String
}

// MARK: - Program Template Definitions

enum ProgramCategory: String, CaseIterable, Codable {
    case foundation = "Foundation"
    case pushPullLegs = "Push/Pull/Legs"
    case upperLower = "Upper/Lower"
    case strength = "Strength"
    case shred = "Shred & Cut"
    case fullBody = "Full Body"
    case athletic = "Athletic"
    case core = "Core"
    case muscle = "Muscle Building"
    case custom = "Your Goal"
    
    var icon: String {
        switch self {
        case .foundation: return "figure.walk"
        case .pushPullLegs: return "arrow.left.arrow.right"
        case .upperLower: return "arrow.up.arrow.down"
        case .strength: return "dumbbell.fill"
        case .shred: return "flame.fill"
        case .fullBody: return "figure.strengthtraining.traditional"
        case .athletic: return "figure.run"
        case .core: return "figure.core.training"
        case .muscle: return "figure.arms.open"
        case .custom: return "star.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .foundation: return .blue
        case .pushPullLegs: return .purple
        case .upperLower: return .orange
        case .strength: return .red
        case .shred: return .pink
        case .fullBody: return .green
        case .athletic: return .cyan
        case .core: return .yellow
        case .muscle: return .indigo
        case .custom: return .mint
        }
    }
}

enum ProgramDifficultyLevel: Int, Codable, Comparable {
    case beginner = 1
    case intermediate = 2
    case advanced = 3
    case elite = 4
    
    var displayName: String {
        switch self {
        case .beginner: return "Beginner"
        case .intermediate: return "Intermediate"
        case .advanced: return "Advanced"
        case .elite: return "Elite"
        }
    }
    
    static func < (lhs: ProgramDifficultyLevel, rhs: ProgramDifficultyLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Smart Program Template

struct SmartProgramTemplate: Identifiable, Codable, Hashable {
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: SmartProgramTemplate, rhs: SmartProgramTemplate) -> Bool { lhs.id == rhs.id }
    let id: String
    let category: ProgramCategory
    let baseName: String
    let description: String
    let totalDays: Int
    let daysPerWeek: Int
    let difficulty: ProgramDifficultyLevel
    let isProgressive: Bool  // Part of a series (1 → 2 → 3)
    let seriesOrder: Int?    // 1, 2, or 3 in series
    let seriesId: String?    // Links programs in same series
    let prerequisiteId: String?  // Must complete this first
    let targetMuscleGroups: [String]  // Primary focus
    let estimatedMinutesPerDay: Int
    let restDayPattern: [Int]  // Which days are rest (e.g., [4, 7] = day 4 and 7 are rest)
    let dayTemplates: [ProgramDayTemplate]  // Templates for each day type
    
    // Personalization keys
    let goalAlignment: [String]  // "Build Muscle", "Lose Weight", etc.
    let equipmentRequirements: [String]  // Minimum equipment needed
    let minExperienceLevel: String  // "Beginner", "Intermediate", "Advanced"
}

struct ProgramDayTemplate: Codable {
    let dayNumber: Int
    let name: String  // "Push Day", "Pull Day", "Legs", etc.
    let focusMuscles: [String]
    let exerciseCount: Int
    let isRestDay: Bool
    let intensity: Double  // 0.7 = 70% intensity, 1.0 = max
    let notes: String?
}

// MARK: - User's Active Program (Smart Engine)

struct SmartActiveProgram: Codable, Identifiable, Hashable {
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: SmartActiveProgram, rhs: SmartActiveProgram) -> Bool { lhs.id == rhs.id }
    let id: String
    let templateId: String
    let userId: String
    let personalizedName: String  // "Joe's Strength Journey"
    let startDate: Date
    var currentDay: Int
    var completedDays: [Int]
    var generatedDays: [SmartProgramDay]
    var isCompleted: Bool
    var completedDate: Date?
    
    // Progress tracking
    var totalVolume: Double  // Total weight lifted
    var averageIntensity: Double
    var consistencyScore: Double  // How consistent user has been
}

struct SmartProgramDay: Codable, Identifiable, Hashable {
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: SmartProgramDay, rhs: SmartProgramDay) -> Bool { lhs.id == rhs.id }
    let id: String
    let dayNumber: Int
    let name: String
    let exercises: [SmartProgramExercise]
    let targetDuration: Int
    let restBetweenSets: Int
    var isCompleted: Bool
    var completedDate: Date?
    var actualDuration: Int?
    var totalVolume: Double?
}

struct SmartProgramExercise: Codable, Identifiable {
    let id: String
    let exerciseName: String
    let exerciseId: UUID?
    let sets: Int
    let reps: Int
    let suggestedWeight: Double?
    let restSeconds: Int
    let notes: String?
    let isSuperset: Bool
    let supersetWith: String?
}

// MARK: - Smart Program Engine

class SmartProgramEngine: ObservableObject {
    static let shared = SmartProgramEngine()
    
    @Published var userPrograms: [SmartActiveProgram] = []
    @Published var availablePrograms: [PersonalizedProgram] = []
    @Published var isLoading = false
    
    private let defaults = UserDefaults.standard
    private let programsKey = "smart_user_programs"
    
    // MARK: - Program Templates (10 Programs)
    
    private let programTemplates: [SmartProgramTemplate] = [
        // 1. FOUNDATION SERIES - Progressive (1 → 2 → 3)
        SmartProgramTemplate(
            id: "foundation-1",
            category: .foundation,
            baseName: "Foundation Builder",
            description: "Master the basics with fundamental movements. Perfect starting point for beginners or those returning to fitness.",
            totalDays: 21,
            daysPerWeek: 4,
            difficulty: .beginner,
            isProgressive: true,
            seriesOrder: 1,
            seriesId: "foundation-series",
            prerequisiteId: nil,
            targetMuscleGroups: ["Full Body"],
            estimatedMinutesPerDay: 30,
            restDayPattern: [3, 6, 7],
            dayTemplates: [
                ProgramDayTemplate(dayNumber: 1, name: "Full Body A", focusMuscles: ["Chest", "Back", "Legs"], exerciseCount: 4, isRestDay: false, intensity: 0.6, notes: "Focus on form"),
                ProgramDayTemplate(dayNumber: 2, name: "Full Body B", focusMuscles: ["Shoulders", "Arms", "Core"], exerciseCount: 4, isRestDay: false, intensity: 0.6, notes: nil),
                ProgramDayTemplate(dayNumber: 3, name: "Active Recovery", focusMuscles: ["Stretch"], exerciseCount: 0, isRestDay: true, intensity: 0.3, notes: "Light stretching or walk"),
                ProgramDayTemplate(dayNumber: 4, name: "Full Body A+", focusMuscles: ["Chest", "Back", "Legs"], exerciseCount: 5, isRestDay: false, intensity: 0.65, notes: "Slight progression"),
                ProgramDayTemplate(dayNumber: 5, name: "Full Body B+", focusMuscles: ["Shoulders", "Arms", "Core"], exerciseCount: 5, isRestDay: false, intensity: 0.65, notes: nil),
                ProgramDayTemplate(dayNumber: 6, name: "Rest", focusMuscles: [], exerciseCount: 0, isRestDay: true, intensity: 0, notes: nil),
                ProgramDayTemplate(dayNumber: 7, name: "Rest", focusMuscles: [], exerciseCount: 0, isRestDay: true, intensity: 0, notes: nil)
            ],
            goalAlignment: ["Build Muscle", "Get Stronger", "Lose Weight", "Get Fit"],
            equipmentRequirements: ["Bodyweight"],
            minExperienceLevel: "Beginner"
        ),
        
        SmartProgramTemplate(
            id: "foundation-2",
            category: .foundation,
            baseName: "Foundation Plus",
            description: "Build on your foundation with increased volume and more challenging exercises. Unlocked after completing Foundation Builder.",
            totalDays: 28,
            daysPerWeek: 5,
            difficulty: .intermediate,
            isProgressive: true,
            seriesOrder: 2,
            seriesId: "foundation-series",
            prerequisiteId: "foundation-1",
            targetMuscleGroups: ["Full Body"],
            estimatedMinutesPerDay: 40,
            restDayPattern: [3, 7],
            dayTemplates: [
                ProgramDayTemplate(dayNumber: 1, name: "Upper Body", focusMuscles: ["Chest", "Back", "Shoulders"], exerciseCount: 5, isRestDay: false, intensity: 0.7, notes: nil),
                ProgramDayTemplate(dayNumber: 2, name: "Lower Body", focusMuscles: ["Legs", "Glutes", "Core"], exerciseCount: 5, isRestDay: false, intensity: 0.7, notes: nil),
                ProgramDayTemplate(dayNumber: 3, name: "Active Recovery", focusMuscles: ["Stretch"], exerciseCount: 0, isRestDay: true, intensity: 0.3, notes: nil),
                ProgramDayTemplate(dayNumber: 4, name: "Push Focus", focusMuscles: ["Chest", "Shoulders", "Triceps"], exerciseCount: 5, isRestDay: false, intensity: 0.75, notes: nil),
                ProgramDayTemplate(dayNumber: 5, name: "Pull Focus", focusMuscles: ["Back", "Biceps", "Core"], exerciseCount: 5, isRestDay: false, intensity: 0.75, notes: nil),
                ProgramDayTemplate(dayNumber: 6, name: "Legs & Core", focusMuscles: ["Legs", "Core"], exerciseCount: 5, isRestDay: false, intensity: 0.7, notes: nil),
                ProgramDayTemplate(dayNumber: 7, name: "Rest", focusMuscles: [], exerciseCount: 0, isRestDay: true, intensity: 0, notes: nil)
            ],
            goalAlignment: ["Build Muscle", "Get Stronger"],
            equipmentRequirements: ["Dumbbells"],
            minExperienceLevel: "Beginner"
        ),
        
        SmartProgramTemplate(
            id: "foundation-3",
            category: .foundation,
            baseName: "Foundation Elite",
            description: "The ultimate foundation program. Advanced techniques, higher intensity, and serious gains. Complete mastery.",
            totalDays: 42,
            daysPerWeek: 5,
            difficulty: .advanced,
            isProgressive: true,
            seriesOrder: 3,
            seriesId: "foundation-series",
            prerequisiteId: "foundation-2",
            targetMuscleGroups: ["Full Body"],
            estimatedMinutesPerDay: 50,
            restDayPattern: [4, 7],
            dayTemplates: [
                ProgramDayTemplate(dayNumber: 1, name: "Heavy Upper", focusMuscles: ["Chest", "Back"], exerciseCount: 6, isRestDay: false, intensity: 0.85, notes: "Progressive overload focus"),
                ProgramDayTemplate(dayNumber: 2, name: "Heavy Lower", focusMuscles: ["Legs", "Glutes"], exerciseCount: 6, isRestDay: false, intensity: 0.85, notes: nil),
                ProgramDayTemplate(dayNumber: 3, name: "Arms & Shoulders", focusMuscles: ["Arms", "Shoulders"], exerciseCount: 6, isRestDay: false, intensity: 0.8, notes: nil),
                ProgramDayTemplate(dayNumber: 4, name: "Active Recovery", focusMuscles: ["Stretch"], exerciseCount: 0, isRestDay: true, intensity: 0.3, notes: nil),
                ProgramDayTemplate(dayNumber: 5, name: "Power Day", focusMuscles: ["Full Body"], exerciseCount: 5, isRestDay: false, intensity: 0.9, notes: "Compound movements"),
                ProgramDayTemplate(dayNumber: 6, name: "Volume Day", focusMuscles: ["Full Body"], exerciseCount: 7, isRestDay: false, intensity: 0.7, notes: "Higher reps"),
                ProgramDayTemplate(dayNumber: 7, name: "Rest", focusMuscles: [], exerciseCount: 0, isRestDay: true, intensity: 0, notes: nil)
            ],
            goalAlignment: ["Build Muscle", "Get Stronger"],
            equipmentRequirements: ["Barbell", "Dumbbells"],
            minExperienceLevel: "Intermediate"
        ),
        
        // 2. PUSH/PULL/LEGS - Classic Split
        SmartProgramTemplate(
            id: "ppl-classic",
            category: .pushPullLegs,
            baseName: "Classic PPL",
            description: "The gold standard of training splits. Push, Pull, Legs rotation for balanced development and optimal recovery.",
            totalDays: 42,
            daysPerWeek: 6,
            difficulty: .intermediate,
            isProgressive: false,
            seriesOrder: nil,
            seriesId: nil,
            prerequisiteId: nil,
            targetMuscleGroups: ["Chest", "Back", "Legs", "Shoulders", "Arms"],
            estimatedMinutesPerDay: 50,
            restDayPattern: [7],
            dayTemplates: [
                ProgramDayTemplate(dayNumber: 1, name: "Push A", focusMuscles: ["Chest", "Shoulders", "Triceps"], exerciseCount: 5, isRestDay: false, intensity: 0.8, notes: "Heavy compound focus"),
                ProgramDayTemplate(dayNumber: 2, name: "Pull A", focusMuscles: ["Back", "Biceps", "Rear Delts"], exerciseCount: 5, isRestDay: false, intensity: 0.8, notes: nil),
                ProgramDayTemplate(dayNumber: 3, name: "Legs A", focusMuscles: ["Quads", "Glutes", "Calves"], exerciseCount: 5, isRestDay: false, intensity: 0.8, notes: nil),
                ProgramDayTemplate(dayNumber: 4, name: "Push B", focusMuscles: ["Chest", "Shoulders", "Triceps"], exerciseCount: 5, isRestDay: false, intensity: 0.75, notes: "Volume focus"),
                ProgramDayTemplate(dayNumber: 5, name: "Pull B", focusMuscles: ["Back", "Biceps"], exerciseCount: 5, isRestDay: false, intensity: 0.75, notes: nil),
                ProgramDayTemplate(dayNumber: 6, name: "Legs B", focusMuscles: ["Hamstrings", "Glutes", "Calves"], exerciseCount: 5, isRestDay: false, intensity: 0.75, notes: nil),
                ProgramDayTemplate(dayNumber: 7, name: "Rest", focusMuscles: [], exerciseCount: 0, isRestDay: true, intensity: 0, notes: nil)
            ],
            goalAlignment: ["Build Muscle", "Get Stronger"],
            equipmentRequirements: ["Dumbbells", "Barbell"],
            minExperienceLevel: "Intermediate"
        ),
        
        // 3. UPPER/LOWER - Efficient Split
        SmartProgramTemplate(
            id: "upper-lower",
            category: .upperLower,
            baseName: "Upper/Lower Power",
            description: "Efficient 4-day split perfect for busy schedules. Hit everything twice per week with optimal recovery.",
            totalDays: 28,
            daysPerWeek: 4,
            difficulty: .intermediate,
            isProgressive: false,
            seriesOrder: nil,
            seriesId: nil,
            prerequisiteId: nil,
            targetMuscleGroups: ["Upper Body", "Lower Body"],
            estimatedMinutesPerDay: 45,
            restDayPattern: [3, 6, 7],
            dayTemplates: [
                ProgramDayTemplate(dayNumber: 1, name: "Upper Strength", focusMuscles: ["Chest", "Back", "Shoulders"], exerciseCount: 6, isRestDay: false, intensity: 0.85, notes: "Heavy compounds"),
                ProgramDayTemplate(dayNumber: 2, name: "Lower Strength", focusMuscles: ["Quads", "Hamstrings", "Glutes"], exerciseCount: 5, isRestDay: false, intensity: 0.85, notes: nil),
                ProgramDayTemplate(dayNumber: 3, name: "Rest", focusMuscles: [], exerciseCount: 0, isRestDay: true, intensity: 0, notes: nil),
                ProgramDayTemplate(dayNumber: 4, name: "Upper Hypertrophy", focusMuscles: ["Chest", "Back", "Arms"], exerciseCount: 6, isRestDay: false, intensity: 0.7, notes: "Higher reps, more isolation"),
                ProgramDayTemplate(dayNumber: 5, name: "Lower Hypertrophy", focusMuscles: ["Legs", "Calves", "Core"], exerciseCount: 5, isRestDay: false, intensity: 0.7, notes: nil),
                ProgramDayTemplate(dayNumber: 6, name: "Rest", focusMuscles: [], exerciseCount: 0, isRestDay: true, intensity: 0, notes: nil),
                ProgramDayTemplate(dayNumber: 7, name: "Rest", focusMuscles: [], exerciseCount: 0, isRestDay: true, intensity: 0, notes: nil)
            ],
            goalAlignment: ["Build Muscle", "Get Stronger", "Get Fit"],
            equipmentRequirements: ["Dumbbells"],
            minExperienceLevel: "Beginner"
        ),
        
        // 4. STRENGTH SERIES - Progressive (1 → 2)
        SmartProgramTemplate(
            id: "strength-1",
            category: .strength,
            baseName: "Strength Foundations",
            description: "Build raw strength with the big lifts. Focus on progressive overload and compound movements.",
            totalDays: 28,
            daysPerWeek: 4,
            difficulty: .intermediate,
            isProgressive: true,
            seriesOrder: 1,
            seriesId: "strength-series",
            prerequisiteId: nil,
            targetMuscleGroups: ["Full Body"],
            estimatedMinutesPerDay: 50,
            restDayPattern: [3, 6, 7],
            dayTemplates: [
                ProgramDayTemplate(dayNumber: 1, name: "Squat Focus", focusMuscles: ["Legs", "Core"], exerciseCount: 4, isRestDay: false, intensity: 0.85, notes: "5x5 main lift"),
                ProgramDayTemplate(dayNumber: 2, name: "Bench Focus", focusMuscles: ["Chest", "Triceps"], exerciseCount: 4, isRestDay: false, intensity: 0.85, notes: "5x5 main lift"),
                ProgramDayTemplate(dayNumber: 3, name: "Rest", focusMuscles: [], exerciseCount: 0, isRestDay: true, intensity: 0, notes: nil),
                ProgramDayTemplate(dayNumber: 4, name: "Deadlift Focus", focusMuscles: ["Back", "Legs"], exerciseCount: 4, isRestDay: false, intensity: 0.85, notes: "5x5 main lift"),
                ProgramDayTemplate(dayNumber: 5, name: "Press Focus", focusMuscles: ["Shoulders", "Core"], exerciseCount: 4, isRestDay: false, intensity: 0.85, notes: "5x5 main lift"),
                ProgramDayTemplate(dayNumber: 6, name: "Rest", focusMuscles: [], exerciseCount: 0, isRestDay: true, intensity: 0, notes: nil),
                ProgramDayTemplate(dayNumber: 7, name: "Rest", focusMuscles: [], exerciseCount: 0, isRestDay: true, intensity: 0, notes: nil)
            ],
            goalAlignment: ["Get Stronger"],
            equipmentRequirements: ["Barbell", "Dumbbells"],
            minExperienceLevel: "Intermediate"
        ),
        
        SmartProgramTemplate(
            id: "strength-2",
            category: .strength,
            baseName: "Strength Advanced",
            description: "Take your strength to the next level. Periodized training with intensity cycling for maximum gains.",
            totalDays: 42,
            daysPerWeek: 5,
            difficulty: .advanced,
            isProgressive: true,
            seriesOrder: 2,
            seriesId: "strength-series",
            prerequisiteId: "strength-1",
            targetMuscleGroups: ["Full Body"],
            estimatedMinutesPerDay: 60,
            restDayPattern: [4, 7],
            dayTemplates: [
                ProgramDayTemplate(dayNumber: 1, name: "Heavy Squat", focusMuscles: ["Legs"], exerciseCount: 5, isRestDay: false, intensity: 0.9, notes: "Working to 3RM"),
                ProgramDayTemplate(dayNumber: 2, name: "Heavy Bench", focusMuscles: ["Chest", "Triceps"], exerciseCount: 5, isRestDay: false, intensity: 0.9, notes: nil),
                ProgramDayTemplate(dayNumber: 3, name: "Accessories", focusMuscles: ["Arms", "Shoulders"], exerciseCount: 6, isRestDay: false, intensity: 0.7, notes: nil),
                ProgramDayTemplate(dayNumber: 4, name: "Rest", focusMuscles: [], exerciseCount: 0, isRestDay: true, intensity: 0, notes: nil),
                ProgramDayTemplate(dayNumber: 5, name: "Heavy Deadlift", focusMuscles: ["Back", "Legs"], exerciseCount: 5, isRestDay: false, intensity: 0.9, notes: nil),
                ProgramDayTemplate(dayNumber: 6, name: "Heavy Press", focusMuscles: ["Shoulders"], exerciseCount: 5, isRestDay: false, intensity: 0.9, notes: nil),
                ProgramDayTemplate(dayNumber: 7, name: "Rest", focusMuscles: [], exerciseCount: 0, isRestDay: true, intensity: 0, notes: nil)
            ],
            goalAlignment: ["Get Stronger"],
            equipmentRequirements: ["Barbell", "Dumbbells", "Machines"],
            minExperienceLevel: "Intermediate"
        ),
        
        // 5. SHRED & CUT
        SmartProgramTemplate(
            id: "shred",
            category: .shred,
            baseName: "30-Day Shred",
            description: "High-intensity fat-burning program. Combines strength training with metabolic conditioning for maximum calorie burn.",
            totalDays: 30,
            daysPerWeek: 5,
            difficulty: .intermediate,
            isProgressive: false,
            seriesOrder: nil,
            seriesId: nil,
            prerequisiteId: nil,
            targetMuscleGroups: ["Full Body"],
            estimatedMinutesPerDay: 40,
            restDayPattern: [3, 7],
            dayTemplates: [
                ProgramDayTemplate(dayNumber: 1, name: "HIIT Upper", focusMuscles: ["Chest", "Back", "Arms"], exerciseCount: 6, isRestDay: false, intensity: 0.8, notes: "30s work, 15s rest"),
                ProgramDayTemplate(dayNumber: 2, name: "HIIT Lower", focusMuscles: ["Legs", "Glutes"], exerciseCount: 6, isRestDay: false, intensity: 0.8, notes: nil),
                ProgramDayTemplate(dayNumber: 3, name: "Active Recovery", focusMuscles: ["Stretch", "Core"], exerciseCount: 0, isRestDay: true, intensity: 0.3, notes: "Light cardio OK"),
                ProgramDayTemplate(dayNumber: 4, name: "Full Body Burn", focusMuscles: ["Full Body"], exerciseCount: 7, isRestDay: false, intensity: 0.85, notes: "Circuit style"),
                ProgramDayTemplate(dayNumber: 5, name: "Metabolic Conditioning", focusMuscles: ["Full Body", "Core"], exerciseCount: 6, isRestDay: false, intensity: 0.9, notes: nil),
                ProgramDayTemplate(dayNumber: 6, name: "Strength + Cardio", focusMuscles: ["Full Body"], exerciseCount: 5, isRestDay: false, intensity: 0.75, notes: nil),
                ProgramDayTemplate(dayNumber: 7, name: "Rest", focusMuscles: [], exerciseCount: 0, isRestDay: true, intensity: 0, notes: nil)
            ],
            goalAlignment: ["Lose Weight", "Get Fit"],
            equipmentRequirements: ["Bodyweight", "Dumbbells"],
            minExperienceLevel: "Beginner"
        ),
        
        // 6. FULL BODY BLAST
        SmartProgramTemplate(
            id: "fullbody",
            category: .fullBody,
            baseName: "Full Body 3x",
            description: "Train your entire body 3 times per week. Perfect for beginners or those with limited time. Maximum efficiency.",
            totalDays: 28,
            daysPerWeek: 3,
            difficulty: .beginner,
            isProgressive: false,
            seriesOrder: nil,
            seriesId: nil,
            prerequisiteId: nil,
            targetMuscleGroups: ["Full Body"],
            estimatedMinutesPerDay: 45,
            restDayPattern: [2, 4, 6, 7],
            dayTemplates: [
                ProgramDayTemplate(dayNumber: 1, name: "Full Body A", focusMuscles: ["Chest", "Back", "Legs", "Core"], exerciseCount: 5, isRestDay: false, intensity: 0.75, notes: nil),
                ProgramDayTemplate(dayNumber: 2, name: "Rest", focusMuscles: [], exerciseCount: 0, isRestDay: true, intensity: 0, notes: nil),
                ProgramDayTemplate(dayNumber: 3, name: "Full Body B", focusMuscles: ["Shoulders", "Arms", "Legs", "Core"], exerciseCount: 5, isRestDay: false, intensity: 0.75, notes: nil),
                ProgramDayTemplate(dayNumber: 4, name: "Rest", focusMuscles: [], exerciseCount: 0, isRestDay: true, intensity: 0, notes: nil),
                ProgramDayTemplate(dayNumber: 5, name: "Full Body C", focusMuscles: ["Full Body"], exerciseCount: 6, isRestDay: false, intensity: 0.8, notes: "Compound focus"),
                ProgramDayTemplate(dayNumber: 6, name: "Rest", focusMuscles: [], exerciseCount: 0, isRestDay: true, intensity: 0, notes: nil),
                ProgramDayTemplate(dayNumber: 7, name: "Rest", focusMuscles: [], exerciseCount: 0, isRestDay: true, intensity: 0, notes: nil)
            ],
            goalAlignment: ["Build Muscle", "Get Fit", "Lose Weight"],
            equipmentRequirements: ["Bodyweight"],
            minExperienceLevel: "Beginner"
        ),
        
        // 7. ATHLETIC PERFORMANCE
        SmartProgramTemplate(
            id: "athletic",
            category: .athletic,
            baseName: "Athletic Performance",
            description: "Train like an athlete. Combines strength, power, agility, and conditioning for total athletic development.",
            totalDays: 35,
            daysPerWeek: 5,
            difficulty: .intermediate,
            isProgressive: false,
            seriesOrder: nil,
            seriesId: nil,
            prerequisiteId: nil,
            targetMuscleGroups: ["Full Body"],
            estimatedMinutesPerDay: 50,
            restDayPattern: [4, 7],
            dayTemplates: [
                ProgramDayTemplate(dayNumber: 1, name: "Power Development", focusMuscles: ["Legs", "Core"], exerciseCount: 5, isRestDay: false, intensity: 0.85, notes: "Explosive movements"),
                ProgramDayTemplate(dayNumber: 2, name: "Upper Strength", focusMuscles: ["Chest", "Back", "Shoulders"], exerciseCount: 5, isRestDay: false, intensity: 0.8, notes: nil),
                ProgramDayTemplate(dayNumber: 3, name: "Speed & Agility", focusMuscles: ["Legs", "Core"], exerciseCount: 6, isRestDay: false, intensity: 0.75, notes: "Plyometrics"),
                ProgramDayTemplate(dayNumber: 4, name: "Rest", focusMuscles: [], exerciseCount: 0, isRestDay: true, intensity: 0, notes: nil),
                ProgramDayTemplate(dayNumber: 5, name: "Total Body Power", focusMuscles: ["Full Body"], exerciseCount: 6, isRestDay: false, intensity: 0.85, notes: nil),
                ProgramDayTemplate(dayNumber: 6, name: "Conditioning", focusMuscles: ["Full Body", "Core"], exerciseCount: 5, isRestDay: false, intensity: 0.9, notes: "High intensity"),
                ProgramDayTemplate(dayNumber: 7, name: "Rest", focusMuscles: [], exerciseCount: 0, isRestDay: true, intensity: 0, notes: nil)
            ],
            goalAlignment: ["Get Fit", "Get Stronger"],
            equipmentRequirements: ["Dumbbells", "Bodyweight"],
            minExperienceLevel: "Intermediate"
        ),
        
        // 8. CORE SERIES - Progressive (1 → 2)
        SmartProgramTemplate(
            id: "core-1",
            category: .core,
            baseName: "Core Foundations",
            description: "Build a bulletproof core. Essential for injury prevention and total body strength.",
            totalDays: 21,
            daysPerWeek: 4,
            difficulty: .beginner,
            isProgressive: true,
            seriesOrder: 1,
            seriesId: "core-series",
            prerequisiteId: nil,
            targetMuscleGroups: ["Core", "Abs", "Lower Back"],
            estimatedMinutesPerDay: 25,
            restDayPattern: [3, 6, 7],
            dayTemplates: [
                ProgramDayTemplate(dayNumber: 1, name: "Core Stability", focusMuscles: ["Core", "Abs"], exerciseCount: 4, isRestDay: false, intensity: 0.7, notes: "Plank variations"),
                ProgramDayTemplate(dayNumber: 2, name: "Anti-Rotation", focusMuscles: ["Core", "Obliques"], exerciseCount: 4, isRestDay: false, intensity: 0.7, notes: nil),
                ProgramDayTemplate(dayNumber: 3, name: "Rest", focusMuscles: [], exerciseCount: 0, isRestDay: true, intensity: 0, notes: nil),
                ProgramDayTemplate(dayNumber: 4, name: "Core Strength", focusMuscles: ["Core", "Lower Back"], exerciseCount: 5, isRestDay: false, intensity: 0.75, notes: nil),
                ProgramDayTemplate(dayNumber: 5, name: "Dynamic Core", focusMuscles: ["Core", "Abs"], exerciseCount: 5, isRestDay: false, intensity: 0.8, notes: nil),
                ProgramDayTemplate(dayNumber: 6, name: "Rest", focusMuscles: [], exerciseCount: 0, isRestDay: true, intensity: 0, notes: nil),
                ProgramDayTemplate(dayNumber: 7, name: "Rest", focusMuscles: [], exerciseCount: 0, isRestDay: true, intensity: 0, notes: nil)
            ],
            goalAlignment: ["Get Fit", "Get Stronger", "Lose Weight"],
            equipmentRequirements: ["Bodyweight"],
            minExperienceLevel: "Beginner"
        ),
        
        SmartProgramTemplate(
            id: "core-2",
            category: .core,
            baseName: "Core Crusher",
            description: "Advanced core training for six-pack abs and functional strength. Builds on Core Foundations.",
            totalDays: 28,
            daysPerWeek: 5,
            difficulty: .intermediate,
            isProgressive: true,
            seriesOrder: 2,
            seriesId: "core-series",
            prerequisiteId: "core-1",
            targetMuscleGroups: ["Core", "Abs", "Obliques"],
            estimatedMinutesPerDay: 30,
            restDayPattern: [4, 7],
            dayTemplates: [
                ProgramDayTemplate(dayNumber: 1, name: "Heavy Core", focusMuscles: ["Core"], exerciseCount: 5, isRestDay: false, intensity: 0.85, notes: "Weighted exercises"),
                ProgramDayTemplate(dayNumber: 2, name: "Ab Sculpt", focusMuscles: ["Abs", "Obliques"], exerciseCount: 6, isRestDay: false, intensity: 0.8, notes: nil),
                ProgramDayTemplate(dayNumber: 3, name: "Functional Core", focusMuscles: ["Core", "Lower Back"], exerciseCount: 5, isRestDay: false, intensity: 0.75, notes: nil),
                ProgramDayTemplate(dayNumber: 4, name: "Rest", focusMuscles: [], exerciseCount: 0, isRestDay: true, intensity: 0, notes: nil),
                ProgramDayTemplate(dayNumber: 5, name: "Core HIIT", focusMuscles: ["Core", "Abs"], exerciseCount: 6, isRestDay: false, intensity: 0.9, notes: "Circuit style"),
                ProgramDayTemplate(dayNumber: 6, name: "Core + Cardio", focusMuscles: ["Core"], exerciseCount: 5, isRestDay: false, intensity: 0.8, notes: nil),
                ProgramDayTemplate(dayNumber: 7, name: "Rest", focusMuscles: [], exerciseCount: 0, isRestDay: true, intensity: 0, notes: nil)
            ],
            goalAlignment: ["Get Fit", "Lose Weight"],
            equipmentRequirements: ["Bodyweight", "Dumbbells"],
            minExperienceLevel: "Beginner"
        ),
        
        // 9. MUSCLE BUILDING
        SmartProgramTemplate(
            id: "muscle",
            category: .muscle,
            baseName: "Mass Builder",
            description: "Serious muscle building program. High volume training designed for maximum hypertrophy.",
            totalDays: 42,
            daysPerWeek: 5,
            difficulty: .intermediate,
            isProgressive: false,
            seriesOrder: nil,
            seriesId: nil,
            prerequisiteId: nil,
            targetMuscleGroups: ["Full Body"],
            estimatedMinutesPerDay: 55,
            restDayPattern: [4, 7],
            dayTemplates: [
                ProgramDayTemplate(dayNumber: 1, name: "Chest & Triceps", focusMuscles: ["Chest", "Triceps"], exerciseCount: 6, isRestDay: false, intensity: 0.8, notes: "High volume"),
                ProgramDayTemplate(dayNumber: 2, name: "Back & Biceps", focusMuscles: ["Back", "Biceps"], exerciseCount: 6, isRestDay: false, intensity: 0.8, notes: nil),
                ProgramDayTemplate(dayNumber: 3, name: "Legs", focusMuscles: ["Quads", "Hamstrings", "Glutes"], exerciseCount: 6, isRestDay: false, intensity: 0.8, notes: nil),
                ProgramDayTemplate(dayNumber: 4, name: "Rest", focusMuscles: [], exerciseCount: 0, isRestDay: true, intensity: 0, notes: nil),
                ProgramDayTemplate(dayNumber: 5, name: "Shoulders & Arms", focusMuscles: ["Shoulders", "Biceps", "Triceps"], exerciseCount: 6, isRestDay: false, intensity: 0.8, notes: nil),
                ProgramDayTemplate(dayNumber: 6, name: "Full Body Pump", focusMuscles: ["Full Body"], exerciseCount: 6, isRestDay: false, intensity: 0.75, notes: "Metabolic stress"),
                ProgramDayTemplate(dayNumber: 7, name: "Rest", focusMuscles: [], exerciseCount: 0, isRestDay: true, intensity: 0, notes: nil)
            ],
            goalAlignment: ["Build Muscle"],
            equipmentRequirements: ["Dumbbells", "Barbell", "Cables"],
            minExperienceLevel: "Intermediate"
        ),
        
        // 10. CUSTOM GOAL - AI Generated based on user
        SmartProgramTemplate(
            id: "custom-goal",
            category: .custom,
            baseName: "Your Personal Plan",
            description: "AI-generated program tailored specifically to your goals, equipment, and schedule. Updated weekly based on your progress.",
            totalDays: 28,
            daysPerWeek: 0,  // Determined by user
            difficulty: .intermediate,  // Adapts to user
            isProgressive: false,
            seriesOrder: nil,
            seriesId: nil,
            prerequisiteId: nil,
            targetMuscleGroups: [],  // Determined by user goals
            estimatedMinutesPerDay: 0,  // Determined by user
            restDayPattern: [],  // Determined by user
            dayTemplates: [],  // Generated dynamically
            goalAlignment: [],  // Matches any goal
            equipmentRequirements: [],  // Any equipment
            minExperienceLevel: "Beginner"
        )
    ]
    
    private init() {
        Task { [self] in
            AppLogger.debug("[SmartProgramEngine] Cache load started (off-main: \(!Thread.isMainThread))", category: .performance)
            await loadUserPrograms()
        }
    }
    
    // MARK: - Public API
    
    /// Get personalized programs for the user
    /// Returns the 6 GAIN/LEAN templates (14/30/90) plus any legacy templates that match well
    func getPersonalizedPrograms(for user: User?) -> [PersonalizedProgram] {
        guard let user = user else {
            return programTemplates.prefix(10).map { template in
                PersonalizedProgram(
                    template: template,
                    personalizedName: template.baseName,
                    isUnlocked: !template.isProgressive || template.seriesOrder == 1,
                    isCompleted: false,
                    matchScore: 0.5,
                    personalizedDescription: template.description
                )
            }
        }
        
        // ═══════════════════════════════════════════════════════════════════
        // PHASE 1: Generate the 6 core GAIN/LEAN templates from the library
        // These are the primary, evidence-based templates
        // ═══════════════════════════════════════════════════════════════════
        var programs: [PersonalizedProgram] = []
        let completedProgramIds = getCompletedProgramIds(for: user)
        let userGoal = user.fitnessGoal?.lowercased() ?? ""
        let userLevel = user.experienceLevel?.lowercased() ?? "intermediate"
        
        for newTemplate in ProgramTemplateLibrary.shared.templates {
            let converted = convertToSmartTemplate(newTemplate, user: user)
            let personalizedName = generatePersonalizedName(template: converted, user: user)
            let isCompleted = completedProgramIds.contains(converted.id)
            
            // Calculate match score based on user's goal alignment
            var matchScore = 0.5
            
            // Goal alignment with expanded keyword matching
            let gainKeywords = ["muscle", "strong", "strength", "mass", "size", "bulk", "gain", "build", "power", "hypertrophy"]
            let leanKeywords = ["lose", "lean", "cut", "fat", "tone", "slim", "shred", "weight loss", "deficit", "burn"]
            if (newTemplate.goalTrack == .gain && gainKeywords.contains(where: { userGoal.contains($0) })) ||
               (newTemplate.goalTrack == .lean && leanKeywords.contains(where: { userGoal.contains($0) })) {
                matchScore += 0.35
            }
            
            // Duration alignment (beginners -> shorter, advanced -> longer)
            if (userLevel == "beginner" && newTemplate.durationDays == 14) ||
               (userLevel == "intermediate" && newTemplate.durationDays == 30) ||
               (userLevel == "advanced" && newTemplate.durationDays == 90) {
                matchScore += 0.15
            }
            
            let personalizedDesc = "\(newTemplate.description) Personalized for your \(user.fitnessGoal ?? "fitness") goals."
            
            programs.append(PersonalizedProgram(
                template: converted,
                personalizedName: personalizedName,
                isUnlocked: true,  // All GAIN/LEAN templates are unlocked
                isCompleted: isCompleted,
                matchScore: min(1.0, matchScore),
                personalizedDescription: personalizedDesc
            ))
        }
        
        // ═══════════════════════════════════════════════════════════════════
        // PHASE 2: Add any legacy templates that fill gaps
        // (Foundation series, core, athletic - keep for variety)
        // ═══════════════════════════════════════════════════════════════════
        for template in programTemplates {
            // Skip the custom-goal template (replaced by GAIN/LEAN)
            if template.id == "custom-goal" { continue }
            
            let personalizedName = generatePersonalizedName(template: template, user: user)
            let isUnlocked = checkIfUnlocked(template: template, completedIds: completedProgramIds)
            let isCompleted = completedProgramIds.contains(template.id)
            let matchScore = calculateMatchScore(template: template, user: user) * 0.8 // Slightly deprioritize legacy
            let personalizedDesc = generatePersonalizedDescription(template: template, user: user)
            
            programs.append(PersonalizedProgram(
                template: template,
                personalizedName: personalizedName,
                isUnlocked: isUnlocked,
                isCompleted: isCompleted,
                matchScore: matchScore,
                personalizedDescription: personalizedDesc
            ))
        }
        
        // Sort by match score (best matches first), keep series together
        return programs.sorted { a, b in
            if let aSeriesId = a.template.seriesId, let bSeriesId = b.template.seriesId,
               aSeriesId == bSeriesId {
                return (a.template.seriesOrder ?? 0) < (b.template.seriesOrder ?? 0)
            }
            return a.matchScore > b.matchScore
        }
    }
    
    // MARK: - Convert MasterProgramTemplate → SmartProgramTemplate
    
    /// Bridges the new ProgramTemplateLibrary format to the existing SmartProgramTemplate format
    /// so the UI and existing flow work without changes
    private func convertToSmartTemplate(_ template: MasterProgramTemplate, user: User) -> SmartProgramTemplate {
        let dayTemplates = template.weeklySchedule.enumerated().map { index, day in
            ProgramDayTemplate(
                dayNumber: index + 1,
                name: day.name,
                focusMuscles: day.primaryMuscles + day.secondaryMuscles,
                exerciseCount: day.exerciseSlots.count,
                isRestDay: day.isRestDay,
                intensity: day.exerciseSlots.first?.isAnchor == true ? 0.85 : 0.75,
                notes: template.blocks.first?.name
            )
        }
        
        let goalAlignment: [String]
        switch template.goal {
        case .gain: goalAlignment = ["Build Muscle", "Get Stronger"]
        case .lean: goalAlignment = ["Lose Weight", "Get Fit", "Tone & Define"]
        }
        
        let category: ProgramCategory
        switch template.goal {
        case .gain:
            category = template.durationDays >= 90 ? .strength : .muscle
        case .lean:
            category = .shred
        }
        
        // Calculate total training days (non-rest days × weeks)
        let trainingDaysPerWeek = template.weeklySchedule.filter { !$0.isRestDay }.count
        let totalTrainingDays = trainingDaysPerWeek * template.weekCount
        
        return SmartProgramTemplate(
            id: template.id,
            category: category,
            baseName: template.name,
            description: template.description,
            totalDays: totalTrainingDays,
            daysPerWeek: template.daysPerWeek,
            difficulty: template.difficulty.lowercased() == "beginner" ? .beginner : (template.difficulty.lowercased() == "advanced" ? .advanced : .intermediate),
            isProgressive: template.blocks.count > 1,
            seriesOrder: nil,
            seriesId: nil,
            prerequisiteId: nil,
            targetMuscleGroups: Array(Set(template.weeklySchedule.flatMap { $0.primaryMuscles })),
            estimatedMinutesPerDay: template.goal == .lean ? 45 : 55,
            restDayPattern: template.weeklySchedule.enumerated().compactMap { $0.element.isRestDay ? $0.offset + 1 : nil },
            dayTemplates: dayTemplates,
            goalAlignment: goalAlignment,
            equipmentRequirements: inferEquipmentRequirements(from: template),
            minExperienceLevel: template.difficulty
        )
    }
    
    /// Internal: Start a program with a pre-converted SmartProgramTemplate
    private func startProgramWithTemplate(_ template: SmartProgramTemplate, user: User) -> SmartActiveProgram? {
        // Mark all existing active programs as completed
        for (index, oldProgram) in userPrograms.enumerated() where !oldProgram.isCompleted {
            var updatedProgram = oldProgram
            updatedProgram.isCompleted = true
            updatedProgram.completedDate = Date()
            userPrograms[index] = updatedProgram
            AppLogger.info("✅ Marked previous program '\(oldProgram.personalizedName)' as completed when starting new program", category: .workout)
        }
        
        let personalizedName = generatePersonalizedName(template: template, user: user)
        let firstDay = generateDay(dayNumber: 1, template: template, user: user, previousDays: [])
        
        let program = SmartActiveProgram(
            id: UUID().uuidString,
            templateId: template.id,
            userId: user.id?.uuidString ?? "",
            personalizedName: personalizedName,
            startDate: Date(),
            currentDay: 1,
            completedDays: [],
            generatedDays: [firstDay],
            isCompleted: false,
            completedDate: nil,
            totalVolume: 0,
            averageIntensity: 0,
            consistencyScore: 1.0
        )
        
        var activePrograms = userPrograms
        activePrograms.append(program)
        userPrograms = activePrograms
        saveUserPrograms()
        
        DispatchQueue.main.async { [weak self] in
            self?.objectWillChange.send()
        }
        
        AppLogger.debug("🚀 Started new GAIN/LEAN program: '\(personalizedName)' (ID: \(program.id))", category: .workout)
        return program
    }
    
    /// Start a program for the user
    func startProgram(templateId: String, for user: User) -> SmartActiveProgram? {
        // First check the new GAIN/LEAN templates from ProgramTemplateLibrary
        if let masterTemplate = ProgramTemplateLibrary.shared.getTemplate(byId: templateId) {
            let converted = convertToSmartTemplate(masterTemplate, user: user)
            // Use the converted template as the base
            return startProgramWithTemplate(converted, user: user)
        }
        
        // Fall back to legacy templates
        guard let baseTemplate = programTemplates.first(where: { $0.id == templateId }) else {
            return nil
        }
        
        // For custom programs with empty dayTemplates, generate them dynamically
        let template: SmartProgramTemplate
        if baseTemplate.dayTemplates.isEmpty {
            template = generateCustomTemplateForUser(baseTemplate: baseTemplate, user: user)
            AppLogger.debug("🎨 Generated custom day templates for user: \(template.dayTemplates.count) days", category: .workout)
        } else {
            template = baseTemplate
        }
        
        // Mark all existing active programs as completed when starting a new one
        // This ensures only one program is active at a time
        for (index, oldProgram) in userPrograms.enumerated() where !oldProgram.isCompleted {
            var updatedProgram = oldProgram
            updatedProgram.isCompleted = true
            updatedProgram.completedDate = Date()
            userPrograms[index] = updatedProgram
            AppLogger.info("✅ Marked previous program '\(oldProgram.personalizedName)' as completed when starting new program", category: .workout)
        }
        
        let personalizedName = generatePersonalizedName(template: template, user: user)
        
        // Generate first day
        let firstDay = generateDay(dayNumber: 1, template: template, user: user, previousDays: [])
        
        let program = SmartActiveProgram(
            id: UUID().uuidString,
            templateId: templateId,
            userId: user.id?.uuidString ?? "",
            personalizedName: personalizedName,
            startDate: Date(),
            currentDay: 1,
            completedDays: [],
            generatedDays: [firstDay],
            isCompleted: false,
            completedDate: nil,
            totalVolume: 0,
            averageIntensity: 0,
            consistencyScore: 1.0
        )
        
        // Save
        var activePrograms = userPrograms
        activePrograms.append(program)
        userPrograms = activePrograms
        saveUserPrograms()
        
        // Force UI refresh
        DispatchQueue.main.async { [weak self] in
            self?.objectWillChange.send()
        }
        
        AppLogger.debug("🚀 Started new program: '\(personalizedName)' (ID: \(program.id))", category: .workout)
        
        return program
    }
    
    /// Complete a day and generate the next one
    /// Next day is ONLY generated after the current day is completed — this is our
    /// lazy generation strategy that saves storage for long programs (90 days).
    func completeDay(programId: String, dayNumber: Int, actualDuration: Int, totalVolume: Double) {
        guard var program = userPrograms.first(where: { $0.id == programId }),
              let user = UserManager.shared.currentUser else {
            return
        }
        
        // Look up template — check new GAIN/LEAN templates first, then legacy
        let template: SmartProgramTemplate
        if let masterTemplate = ProgramTemplateLibrary.shared.getTemplate(byId: program.templateId) {
            template = convertToSmartTemplate(masterTemplate, user: user)
        } else if let baseTemplate = programTemplates.first(where: { $0.id == program.templateId }) {
            if baseTemplate.dayTemplates.isEmpty {
                template = generateCustomTemplateForUser(baseTemplate: baseTemplate, user: user)
            } else {
                template = baseTemplate
            }
        } else {
            AppLogger.error("❌ [PROGRAMS] Could not find template for program \(programId)", category: .workout)
            return
        }
        
        // Mark day as completed
        var completedDay: SmartProgramDay?
        if let dayIndex = program.generatedDays.firstIndex(where: { $0.dayNumber == dayNumber }) {
            program.generatedDays[dayIndex].isCompleted = true
            program.generatedDays[dayIndex].completedDate = Date()
            program.generatedDays[dayIndex].actualDuration = actualDuration
            program.generatedDays[dayIndex].totalVolume = totalVolume
            completedDay = program.generatedDays[dayIndex]
            
            // ═══════════════════════════════════════════════════════════════
            // 📦 Record exercises to cooldown tracker for anti-repeat variety
            // This ensures the same exercise won't appear again within its
            // bundle's cooldown window (typically 3-7 days)
            // ═══════════════════════════════════════════════════════════════
            let exerciseNames = program.generatedDays[dayIndex].exercises.map { $0.exerciseName }
            ExerciseCooldownTracker.shared.recordWorkoutExercises(exerciseNames)
        }
        
        program.completedDays.append(dayNumber)
        program.totalVolume += totalVolume
        program.currentDay = dayNumber + 1
        
        // Check if program is complete
        if dayNumber >= template.totalDays {
            program.isCompleted = true
            program.completedDate = Date()
            markProgramCompleted(templateId: template.id, userId: user.id?.uuidString ?? "")
            
            // Record to Collaborative Learning Engine for cross-user intelligence
            Task {
                let userProfile = UserProfileSnapshot(from: user)
                await CollaborativeLearningEngine.shared.recordProgramCompletion(
                    userId: user.id?.uuidString ?? "",
                    programId: program.id,
                    programName: program.personalizedName,
                    templateId: template.id,
                    totalDays: template.totalDays,
                    completedDays: program.completedDays.count,
                    userProfile: userProfile
                )
            }
        } else {
            // Generate next day (lazy generation)
            let nextDay = generateDay(
                dayNumber: dayNumber + 1,
                template: template,
                user: user,
                previousDays: program.generatedDays
            )
            program.generatedDays.append(nextDay)
        }
        
        // Update stored programs - ensure main thread and explicit publish
        if let index = userPrograms.firstIndex(where: { $0.id == programId }) {
            DispatchQueue.main.async { [self] in
                objectWillChange.send()
                userPrograms[index] = program
                saveUserPrograms()
            }
        }
        
        // Save completed day to cloud for learning engine (async)
        if let day = completedDay {
            Task {
                await saveDayCompletionToCloud(program: program, day: day)
            }
        }
        
        AppLogger.info("✅ [PROGRAMS] Day \(dayNumber) completed - Next day generated and synced to cloud", category: .workout)
    }
    
    /// Get preview of all days in a program (without generating exercises)
    func getDayPreviews(for template: SmartProgramTemplate) -> [DayPreview] {
        var previews: [DayPreview] = []
        
        // Guard against empty dayTemplates (custom programs)
        guard !template.dayTemplates.isEmpty else {
            // Return a simple preview for custom programs
            for dayNum in 1...max(1, template.totalDays) {
                previews.append(DayPreview(
                    dayNumber: dayNum,
                    name: "Day \(dayNum)",
                    isRestDay: false,
                    focusMuscles: ["Full Body"],
                    estimatedMinutes: template.estimatedMinutesPerDay,
                    exerciseCount: 5
                ))
            }
            return previews
        }
        
        for dayNum in 1...template.totalDays {
            let templateIndex = (dayNum - 1) % template.dayTemplates.count
            let dayTemplate = template.dayTemplates[templateIndex]
            
            previews.append(DayPreview(
                dayNumber: dayNum,
                name: dayTemplate.name,
                isRestDay: dayTemplate.isRestDay,
                focusMuscles: dayTemplate.focusMuscles,
                estimatedMinutes: dayTemplate.isRestDay ? 0 : template.estimatedMinutesPerDay,
                exerciseCount: dayTemplate.exerciseCount
            ))
        }
        
        return previews
    }
    
    // MARK: - Day Generation (Lazy)
    
    private func generateDay(dayNumber: Int, template: SmartProgramTemplate, user: User, previousDays: [SmartProgramDay]) -> SmartProgramDay {
        
        // ═══════════════════════════════════════════════════════════════════
        // CHECK: Is this a new GAIN/LEAN template from ProgramTemplateLibrary?
        // If so, use the advanced block-based generation
        // ═══════════════════════════════════════════════════════════════════
        if let programTemplate = ProgramTemplateLibrary.shared.getTemplate(byId: template.id) {
            return generateBlockAwareDay(
                dayNumber: dayNumber,
                programTemplate: programTemplate,
                user: user,
                previousDays: previousDays
            )
        }
        
        // ═══════════════════════════════════════════════════════════════════
        // LEGACY PATH: Original template-based generation
        // ═══════════════════════════════════════════════════════════════════
        
        // Safety guard: if dayTemplates is empty, create a default full body workout
        guard !template.dayTemplates.isEmpty else {
            AppLogger.warning("⚠️ [PROGRAMS] Warning: dayTemplates is empty, generating default day", category: .workout)
            return generateDefaultDay(dayNumber: dayNumber, user: user)
        }
        
        // Find the day template
        let templateIndex = (dayNumber - 1) % template.dayTemplates.count
        let dayTemplate = template.dayTemplates[templateIndex]
        
        // If rest day, return empty
        if dayTemplate.isRestDay {
            return SmartProgramDay(
                id: UUID().uuidString,
                dayNumber: dayNumber,
                name: dayTemplate.name,
                exercises: [],
                targetDuration: 0,
                restBetweenSets: 0,
                isCompleted: false,
                completedDate: nil,
                actualDuration: nil,
                totalVolume: nil
            )
        }
        
        // Generate exercises using WorkoutGeneratorService
        let exercises = generateExercisesForDay(
            dayTemplate: dayTemplate,
            template: template,
            user: user,
            dayNumber: dayNumber,
            previousDays: previousDays
        )
        
        return SmartProgramDay(
            id: UUID().uuidString,
            dayNumber: dayNumber,
            name: dayTemplate.name,
            exercises: exercises,
            targetDuration: template.estimatedMinutesPerDay,
            restBetweenSets: calculateRestTime(intensity: dayTemplate.intensity, userLevel: user.experienceLevel ?? "Intermediate"),
            isCompleted: false,
            completedDate: nil,
            actualDuration: nil,
            totalVolume: nil
        )
    }
    
    // MARK: - Block-Aware Day Generation (New GAIN/LEAN Templates)
    
    /// Generates a workout day using the ProgramTemplate's exercise slots, periodization blocks,
    /// and exercise cooldown tracking. This is the "real trainer" path.
    private func generateBlockAwareDay(
        dayNumber: Int,
        programTemplate: MasterProgramTemplate,
        user: User,
        previousDays: [SmartProgramDay]
    ) -> SmartProgramDay {
        
        // 1. Determine which day template to use (cycling through training days)
        let trainingDays = programTemplate.weeklySchedule.filter { !$0.isRestDay }
        guard !trainingDays.isEmpty else {
            AppLogger.warning("⚠️ [PROGRAMS] No training day templates, generating default", category: .workout)
            return generateDefaultDay(dayNumber: dayNumber, user: user)
        }
        let dayIndex = (dayNumber - 1) % trainingDays.count
        let dayTemplate = trainingDays[dayIndex]
        
        // 2. Determine which periodization block we're in
        let trainingDaysPerWeek = trainingDays.count
        let weekNumber = max(1, ((dayNumber - 1) / trainingDaysPerWeek) + 1)
        let currentBlock = ProgramTemplateLibrary.shared.getActiveBlock(for: weekNumber, in: programTemplate)
        
        #if DEBUG
        AppLogger.debug("🎯 [BLOCK-GEN] Day \(dayNumber) | Week \(weekNumber) | Block: \(currentBlock?.name ?? "default")", category: .workout)
        AppLogger.debug("   Template: \(dayTemplate.name) | Muscles: \(dayTemplate.primaryMuscles.joined(separator: ", "))", category: .workout)
        #endif
        
        // 3. Get user equipment and preferences
        let userEquipment = parseEquipment(user.equipment)
        let isGymUser = user.workoutEnvironment == "Gym" || userEquipment.contains {
            ["Barbell", "Cables", "Machines", "Cable", "Machine"].contains($0)
        }
        
        // 4. Get previously used exercise names for cooldown enforcement
        let previousExerciseNames = Set(previousDays.flatMap { $0.exercises.map { $0.exerciseName.lowercased() } })
        
        // 5. Generate exercises slot-by-slot using the recipe
        var exercises: [SmartProgramExercise] = []
        let cooldownTracker = ExerciseCooldownTracker.shared
        
        for (slotIndex, slot) in dayTemplate.exerciseSlots.enumerated() {
            // Skip finisher slots — handled separately below
            if slot.role == .finisher { continue }
            
            // Determine the target movement pattern from the slot's bundle targets
            let targetPattern = slot.targetBundles.first ?? ""
            let isCompound = slot.role == .primaryCompound || slot.role == .secondaryCompound
            
            // Determine adjusted sets/reps based on block + slot overrides
            // Slot overrides > block defaults > fallback
            var adjustedSets: Int
            var adjustedRepsMin: Int
            var adjustedRepsMax: Int
            var adjustedRest: Int
            
            if let block = currentBlock {
                // Use slot override if present, otherwise block defaults
                adjustedSets = slot.setsOverride ?? (isCompound ? block.primarySets : block.accessorySets)
                adjustedRepsMin = slot.repsMinOverride ?? (isCompound ? block.primaryRepsMin : block.accessoryRepsMin)
                adjustedRepsMax = slot.repsMaxOverride ?? (isCompound ? block.primaryRepsMax : block.accessoryRepsMax)
                adjustedRest = slot.restOverride ?? (isCompound ? block.primaryRestSeconds : block.accessoryRestSeconds)
                
                // Deload check: if this week is a deload, reduce sets 30-40%
                if ProgramTemplateLibrary.shared.isDeloadWeek(weekNumber, in: programTemplate) {
                    adjustedSets = max(2, Int(Double(adjustedSets) * 0.65))
                    adjustedRest = max(60, adjustedRest - 30)
                }
                
                // Strength block adjustments for primary lifts
                if block.emphasis == .strength && isCompound {
                    adjustedRest = max(adjustedRest, 150) // Ensure long rest for heavy work
                }
                
                // Density/conditioning block: shorter rest on accessories
                if (block.emphasis == .densityConditioning || block.emphasis == .peakLeanness) && !isCompound {
                    adjustedRest = max(30, adjustedRest - 15)
                }
            } else {
                // No block found — use slot overrides or sensible defaults
                adjustedSets = slot.setsOverride ?? (isCompound ? 4 : 3)
                adjustedRepsMin = slot.repsMinOverride ?? (isCompound ? 6 : 10)
                adjustedRepsMax = slot.repsMaxOverride ?? (isCompound ? 10 : 15)
                adjustedRest = slot.restOverride ?? (isCompound ? 120 : 60)
            }
            
            // Use SmartExerciseSelectionEngine to find the right exercise for this slot
            let slotMuscles = !slot.targetMuscles.isEmpty ? slot.targetMuscles : dayTemplate.primaryMuscles
            let selectedExercises = SmartExerciseSelectionEngine.shared.selectExercisesForWorkout(
                targetMuscles: slotMuscles,
                exerciseCount: 3,  // Get candidates
                userEquipment: userEquipment,
                isGymUser: isGymUser,
                previousDayExercises: previousExerciseNames,
                userGoal: user.fitnessGoal ?? "Build Muscle",
                experienceLevel: user.experienceLevel ?? "Intermediate"
            )
            
            // Find the best match for this slot's movement pattern
            let matchingExercise = selectedExercises.first { exercise in
                let pattern = exercise.movementPattern.rawValue
                let exerciseName = exercise.name.lowercased()
                
                // Check pattern match against target bundles
                let patternMatches = targetPattern.isEmpty ||
                    pattern.contains(targetPattern.lowercased()) ||
                    targetPattern.lowercased().contains(pattern)
                
                // Check cooldown (skip if on cooldown, unless it's an anchor)
                if !slot.isAnchor {
                    if cooldownTracker.isOnCooldown(exerciseName, isAnchor: false) {
                        return false
                    }
                }
                
                // Check not already selected in this workout
                let alreadySelected = exercises.contains { $0.exerciseName.lowercased() == exerciseName }
                
                return patternMatches && !alreadySelected
            } ?? selectedExercises.first { exercise in
                // Fallback: just avoid duplicates
                !exercises.contains { $0.exerciseName.lowercased() == exercise.name.lowercased() }
            }
            
            guard let selected = matchingExercise else { continue }
            
            // Build notes based on slot, block, and superset info
            var notes: String? = slot.notes
            if let block = currentBlock {
                if block.emphasis == .strength && isCompound {
                    notes = (notes ?? "") + " Focus on progressive overload. RPE 8-9."
                } else if block.emphasis == .intensityTechniques {
                    notes = (notes ?? "") + " Squeeze at contraction, control the negative."
                }
                // Deload note
                if ProgramTemplateLibrary.shared.isDeloadWeek(weekNumber, in: programTemplate) {
                    notes = "DELOAD: Lighter weight, perfect form. RPE 5-6."
                }
            }
            
            exercises.append(SmartProgramExercise(
                id: UUID().uuidString,
                exerciseName: selected.name,
                exerciseId: selected.exercise.id,
                sets: adjustedSets,
                reps: (adjustedRepsMin + adjustedRepsMax) / 2,  // Use midpoint
                suggestedWeight: nil,
                restSeconds: adjustedRest,
                notes: notes?.trimmingCharacters(in: .whitespaces),
                isSuperset: false,
                supersetWith: nil
            ))
        }
        
        // 6. Add warm-up suggestion as a note on the first exercise
        let warmUp = WarmUpSuggestion.forDay(dayTemplate)
        if var firstExercise = exercises.first {
            let warmUpNote = "🔥 Warm-up (\(warmUp.durationMinutes) min): \(warmUp.description)"
            exercises[0] = SmartProgramExercise(
                id: firstExercise.id,
                exerciseName: firstExercise.exerciseName,
                exerciseId: firstExercise.exerciseId,
                sets: firstExercise.sets,
                reps: firstExercise.reps,
                suggestedWeight: firstExercise.suggestedWeight,
                restSeconds: firstExercise.restSeconds,
                notes: warmUpNote,
                isSuperset: firstExercise.isSuperset,
                supersetWith: firstExercise.supersetWith
            )
        }
        
        // 7. Add finisher if this day template has one and the block calls for it
        // Finisher info is stored in the last slot with role .finisher
        if dayTemplate.hasFinisher, let block = currentBlock, block.finishersPerWeek > 0 {
            if let finisherSlot = dayTemplate.exerciseSlots.first(where: { $0.role == .finisher }),
               let finisherNotes = finisherSlot.notes {
                exercises.append(SmartProgramExercise(
                    id: UUID().uuidString,
                    exerciseName: "🔥 Finisher",
                    exerciseId: nil,
                    sets: 1,
                    reps: 1,
                    suggestedWeight: nil,
                    restSeconds: 0,
                    notes: finisherNotes,
                    isSuperset: false,
                    supersetWith: nil
                ))
            }
        }
        
        let estimatedDuration = programTemplate.goalTrack == .lean ? 45 : 55
        
        return SmartProgramDay(
            id: UUID().uuidString,
            dayNumber: dayNumber,
            name: dayTemplate.name,
            exercises: exercises,
            targetDuration: estimatedDuration,
            restBetweenSets: exercises.first?.restSeconds ?? 90,
            isCompleted: false,
            completedDate: nil,
            actualDuration: nil,
            totalVolume: nil
        )
    }
    
    private func generateExercisesForDay(dayTemplate: ProgramDayTemplate, template: SmartProgramTemplate, user: User, dayNumber: Int, previousDays: [SmartProgramDay]) -> [SmartProgramExercise] {
        // ═══════════════════════════════════════════════════════════════════════
        // USE SMART EXERCISE SELECTION ENGINE
        // This integrates:
        //   - User preference learning (exercises they've enjoyed)
        //   - Movement pattern variety (no 3 bench presses!)
        //   - Compound + Isolation balance
        //   - Equipment prioritization for gym users
        // ═══════════════════════════════════════════════════════════════════════
        
        let userEquipment = parseEquipment(user.equipment)
        let isGymUser = user.workoutEnvironment == "Gym" || userEquipment.contains { 
            ["Barbell", "Cables", "Machines", "Cable", "Machine"].contains($0) 
        }
        
        // Get previously used exercise names for variety
        let previousExerciseNames = Set(previousDays.flatMap { $0.exercises.map { $0.exerciseName.lowercased() } })
        
        // Use the Smart Exercise Selection Engine
        let selectedExercises = SmartExerciseSelectionEngine.shared.selectExercisesForWorkout(
            targetMuscles: dayTemplate.focusMuscles,
            exerciseCount: dayTemplate.exerciseCount,
            userEquipment: userEquipment,
            isGymUser: isGymUser,
            previousDayExercises: previousExerciseNames,
            userGoal: user.fitnessGoal ?? "Build Muscle",
            experienceLevel: user.experienceLevel ?? "Intermediate"
        )
        
        // Convert to SmartProgramExercise with progressive weights and proper prescription
        var exercises: [SmartProgramExercise] = []
        
        for (index, selected) in selectedExercises.enumerated() {
            // Calculate progression based on previous days
            let progressionMultiplier = calculateProgression(
                exerciseName: selected.name,
                dayNumber: dayNumber,
                previousDays: previousDays,
                template: template
            )
            
            // Calculate base weight and reps based on user profile, exercise type, and goal
            let baseRecommendation = calculateBaseRecommendation(
                category: selected.exercise.category ?? "General",
                user: user,
                intensity: dayTemplate.intensity
            )
            
            // Adjust sets/reps based on exercise type (compound vs isolation)
            let isCompound = selected.exerciseType == .compound
            let sets = calculateSetsForExercise(
                intensity: dayTemplate.intensity, 
                isCompound: isCompound, 
                userGoal: user.fitnessGoal ?? "Build Muscle",
                exerciseOrder: index
            )
            
            let reps = calculateRepsForExercise(
                baseReps: baseRecommendation.reps,
                isCompound: isCompound,
                userGoal: user.fitnessGoal ?? "Build Muscle"
            )
            
            let suggestedWeight = baseRecommendation.weight * progressionMultiplier
            
            // Generate exercise-specific notes based on movement pattern
            let notes = generateExerciseNotes(
                pattern: selected.movementPattern,
                exerciseType: selected.exerciseType,
                exerciseOrder: index,
                dayNotes: dayTemplate.notes
            )
            
            exercises.append(SmartProgramExercise(
                id: UUID().uuidString,
                exerciseName: selected.name,
                exerciseId: selected.exercise.id,
                sets: sets,
                reps: reps,
                suggestedWeight: suggestedWeight > 0 ? suggestedWeight : nil,
                restSeconds: calculateRestTime(intensity: dayTemplate.intensity, userLevel: user.experienceLevel ?? "Intermediate"),
                notes: notes,
                isSuperset: false,
                supersetWith: nil
            ))
        }
        
        return exercises
    }
    
    // MARK: - Enhanced Prescription Calculations
    
    private func calculateSetsForExercise(intensity: Double, isCompound: Bool, userGoal: String, exerciseOrder: Int) -> Int {
        let goalLower = userGoal.lowercased()
        var baseSets: Int
        
        switch goalLower {
        case "get stronger", "strength":
            baseSets = isCompound ? 5 : 4
        case "build muscle", "hypertrophy", "muscle gain":
            baseSets = 4
        case "lose weight", "fat loss", "weight loss":
            baseSets = 3
        case "tone & define", "toning":
            baseSets = 3
        default:
            baseSets = isCompound ? 4 : 3
        }
        
        // First exercise gets more volume
        if exerciseOrder == 0 && isCompound {
            baseSets = min(baseSets + 1, 6)
        }
        
        // Adjust for intensity
        if intensity > 0.85 {
            baseSets += 1
        } else if intensity < 0.6 {
            baseSets = max(2, baseSets - 1)
        }
        
        return baseSets
    }
    
    private func calculateRepsForExercise(baseReps: Int, isCompound: Bool, userGoal: String) -> Int {
        let goalLower = userGoal.lowercased()
        
        switch goalLower {
        case "get stronger", "strength":
            return isCompound ? min(baseReps, 6) : 8
        case "build muscle", "hypertrophy", "muscle gain":
            return isCompound ? min(baseReps, 10) : 12
        case "lose weight", "fat loss", "weight loss":
            return isCompound ? 12 : 15
        case "tone & define", "toning":
            return 15
        default:
            return baseReps
        }
    }
    
    private func generateExerciseNotes(pattern: SelectionMovementPattern, exerciseType: ExerciseType, exerciseOrder: Int, dayNotes: String?) -> String? {
        // Primary exercise gets special notes
        if exerciseOrder == 0 && exerciseType == .compound {
            return "Primary compound - focus on progressive overload"
        }
        
        // Pattern-specific notes
        switch pattern {
        case .horizontalPress, .verticalPress:
            if exerciseOrder > 0 {
                return "Control the negative, squeeze at the top"
            }
        case .chestFly:
            return "Focus on stretch at the bottom"
        case .horizontalPull, .verticalPull:
            if exerciseOrder == 0 {
                return "Drive with your elbows, squeeze shoulder blades"
            }
        case .squat, .hinge:
            return "Full range of motion, brace your core"
        case .bicepCurl, .tricepExtension:
            return "Isolation focus - squeeze and control"
        case .lateralRaise:
            return "Light weight, high control"
        default:
            break
        }
        
        return dayNotes
    }
    
    // MARK: - Progression Calculations
    
    private func calculateProgression(exerciseName: String, dayNumber: Int, previousDays: [SmartProgramDay], template: SmartProgramTemplate) -> Double {
        // Base progression: 2.5% per week
        let weeksIn = Double(dayNumber) / 7.0
        let baseProgression = 1.0 + (weeksIn * 0.025)
        
        // Check if user did this exercise before and how they performed
        var lastWeight: Double?
        for day in previousDays.reversed() {
            if let exercise = day.exercises.first(where: { $0.exerciseName == exerciseName }),
               let weight = exercise.suggestedWeight {
                lastWeight = weight
                break
            }
        }
        
        // If they've done it before, progress from that
        if lastWeight != nil {
            return baseProgression
        }
        
        // For progressive series, increase difficulty based on series order
        if template.isProgressive, let order = template.seriesOrder {
            let seriesBonus = 1.0 + (Double(order - 1) * 0.15) // 15% harder per series level
            return baseProgression * seriesBonus
        }
        
        return baseProgression
    }
    
    // MARK: - Base Recommendation Calculator
    
    private struct BaseRecommendation {
        let weight: Double
        let reps: Int
    }
    
    private func calculateBaseRecommendation(category: String, user: User, intensity: Double) -> BaseRecommendation {
        // Get user stats
        let userWeight = Double(user.weight)
        let userLevel = user.experienceLevel?.lowercased() ?? "intermediate"
        let userGender = user.gender?.lowercased() ?? "neutral"
        let userStrength = user.strengthLevel?.lowercased() ?? "moderate"
        let userGoal = user.fitnessGoal?.lowercased() ?? ""
        
        // Base weight multipliers by category
        var baseMultiplier: Double
        switch category.lowercased() {
        case let c where c.contains("chest"):
            baseMultiplier = 0.5  // 50% of body weight
        case let c where c.contains("back"):
            baseMultiplier = 0.45
        case let c where c.contains("shoulder"):
            baseMultiplier = 0.25
        case let c where c.contains("leg") || c.contains("quad") || c.contains("glute"):
            baseMultiplier = 0.6
        case let c where c.contains("bicep") || c.contains("arm"):
            baseMultiplier = 0.15
        case let c where c.contains("tricep"):
            baseMultiplier = 0.15
        case let c where c.contains("core") || c.contains("ab"):
            baseMultiplier = 0.0  // Bodyweight typically
        default:
            baseMultiplier = 0.3
        }
        
        // Adjust for strength level
        switch userStrength {
        case "very light": baseMultiplier *= 0.5
        case "light": baseMultiplier *= 0.7
        case "moderate": baseMultiplier *= 1.0
        case "strong": baseMultiplier *= 1.2
        case "very strong": baseMultiplier *= 1.4
        default: break
        }
        
        // Adjust for experience
        switch userLevel {
        case "beginner": baseMultiplier *= 0.7
        case "advanced": baseMultiplier *= 1.15
        default: break
        }
        
        // Adjust for gender
        if userGender == "female" {
            baseMultiplier *= 0.7
        }
        
        // Calculate weight
        var weight = userWeight * baseMultiplier
        weight = (weight / 2.5).rounded() * 2.5  // Round to nearest 2.5
        weight = max(5, min(weight, 500))  // Clamp
        
        // Calculate reps based on goal and intensity
        var reps: Int
        if userGoal.contains("strength") || userGoal.contains("strong") {
            reps = Int(5.0 + (1.0 - intensity) * 3.0)  // 5-8 reps
        } else if userGoal.contains("muscle") || userGoal.contains("bulk") {
            reps = Int(8.0 + (1.0 - intensity) * 4.0)  // 8-12 reps
        } else if userGoal.contains("weight") || userGoal.contains("cut") || userGoal.contains("fat") {
            reps = Int(12.0 + (1.0 - intensity) * 5.0)  // 12-17 reps
        } else {
            reps = Int(10.0 + (1.0 - intensity) * 4.0)  // 10-14 reps
        }
        
        // Clamp reps
        reps = max(5, min(reps, 20))
        
        return BaseRecommendation(weight: weight, reps: reps)
    }
    
    private func calculateSets(intensity: Double, isCompound: Bool) -> Int {
        if intensity >= 0.85 {
            return isCompound ? 5 : 4
        } else if intensity >= 0.7 {
            return isCompound ? 4 : 3
        } else {
            return 3
        }
    }
    
    private func calculateRestTime(intensity: Double, userLevel: String) -> Int {
        var baseRest: Int
        
        if intensity >= 0.85 {
            baseRest = 120  // Heavy work needs more rest
        } else if intensity >= 0.7 {
            baseRest = 90
        } else {
            baseRest = 60
        }
        
        // Adjust for experience
        switch userLevel.lowercased() {
        case "beginner": return baseRest + 30
        case "advanced": return max(45, baseRest - 15)
        default: return baseRest
        }
    }
    
    // MARK: - Custom Program Generation
    
    /// Generates a template with populated dayTemplates for custom programs
    private func generateCustomTemplateForUser(baseTemplate: SmartProgramTemplate, user: User) -> SmartProgramTemplate {
        let userDays = max(2, min(7, Int(user.availableDays)))
        let goal = user.fitnessGoal?.lowercased() ?? "general fitness"
        let level = user.experienceLevel?.lowercased() ?? "intermediate"
        
        // Determine intensity based on experience
        let baseIntensity: Double
        switch level {
        case "beginner": baseIntensity = 0.6
        case "advanced": baseIntensity = 0.8
        default: baseIntensity = 0.7
        }
        
        // Determine exercise count based on experience
        let baseExerciseCount: Int
        switch level {
        case "beginner": baseExerciseCount = 4
        case "advanced": baseExerciseCount = 6
        default: baseExerciseCount = 5
        }
        
        // Generate day templates based on user's available days and goals
        var dayTemplates: [ProgramDayTemplate] = []
        
        switch userDays {
        case 2:
            // 2 days: Full body workouts
            dayTemplates = [
                ProgramDayTemplate(dayNumber: 1, name: "Full Body A", focusMuscles: ["Chest", "Back", "Legs", "Shoulders"], exerciseCount: baseExerciseCount, isRestDay: false, intensity: baseIntensity, notes: nil),
                ProgramDayTemplate(dayNumber: 2, name: "Full Body B", focusMuscles: ["Back", "Legs", "Arms", "Core"], exerciseCount: baseExerciseCount, isRestDay: false, intensity: baseIntensity, notes: nil)
            ]
        case 3:
            // 3 days: Push/Pull/Legs or Full Body
            if goal.contains("muscle") || goal.contains("strong") {
                dayTemplates = [
                    ProgramDayTemplate(dayNumber: 1, name: "Push Day", focusMuscles: ["Chest", "Shoulders", "Triceps"], exerciseCount: baseExerciseCount, isRestDay: false, intensity: baseIntensity, notes: nil),
                    ProgramDayTemplate(dayNumber: 2, name: "Pull Day", focusMuscles: ["Back", "Biceps", "Rear Delts"], exerciseCount: baseExerciseCount, isRestDay: false, intensity: baseIntensity, notes: nil),
                    ProgramDayTemplate(dayNumber: 3, name: "Legs Day", focusMuscles: ["Legs", "Glutes", "Core"], exerciseCount: baseExerciseCount, isRestDay: false, intensity: baseIntensity, notes: nil)
                ]
            } else {
                dayTemplates = [
                    ProgramDayTemplate(dayNumber: 1, name: "Full Body A", focusMuscles: ["Chest", "Back", "Legs"], exerciseCount: baseExerciseCount, isRestDay: false, intensity: baseIntensity, notes: nil),
                    ProgramDayTemplate(dayNumber: 2, name: "Full Body B", focusMuscles: ["Shoulders", "Arms", "Core"], exerciseCount: baseExerciseCount, isRestDay: false, intensity: baseIntensity, notes: nil),
                    ProgramDayTemplate(dayNumber: 3, name: "Full Body C", focusMuscles: ["Legs", "Back", "Core"], exerciseCount: baseExerciseCount, isRestDay: false, intensity: baseIntensity, notes: nil)
                ]
            }
        case 4:
            // 4 days: Upper/Lower split
            dayTemplates = [
                ProgramDayTemplate(dayNumber: 1, name: "Upper Body A", focusMuscles: ["Chest", "Back", "Shoulders"], exerciseCount: baseExerciseCount, isRestDay: false, intensity: baseIntensity, notes: nil),
                ProgramDayTemplate(dayNumber: 2, name: "Lower Body A", focusMuscles: ["Legs", "Glutes", "Core"], exerciseCount: baseExerciseCount, isRestDay: false, intensity: baseIntensity, notes: nil),
                ProgramDayTemplate(dayNumber: 3, name: "Upper Body B", focusMuscles: ["Back", "Shoulders", "Arms"], exerciseCount: baseExerciseCount, isRestDay: false, intensity: baseIntensity + 0.05, notes: nil),
                ProgramDayTemplate(dayNumber: 4, name: "Lower Body B", focusMuscles: ["Legs", "Glutes", "Hamstrings"], exerciseCount: baseExerciseCount, isRestDay: false, intensity: baseIntensity + 0.05, notes: nil)
            ]
        case 5:
            // 5 days: Push/Pull/Legs/Upper/Lower hybrid
            dayTemplates = [
                ProgramDayTemplate(dayNumber: 1, name: "Push Day", focusMuscles: ["Chest", "Shoulders", "Triceps"], exerciseCount: baseExerciseCount, isRestDay: false, intensity: baseIntensity, notes: nil),
                ProgramDayTemplate(dayNumber: 2, name: "Pull Day", focusMuscles: ["Back", "Biceps", "Rear Delts"], exerciseCount: baseExerciseCount, isRestDay: false, intensity: baseIntensity, notes: nil),
                ProgramDayTemplate(dayNumber: 3, name: "Legs Day", focusMuscles: ["Legs", "Glutes", "Core"], exerciseCount: baseExerciseCount, isRestDay: false, intensity: baseIntensity, notes: nil),
                ProgramDayTemplate(dayNumber: 4, name: "Upper Body", focusMuscles: ["Chest", "Back", "Arms"], exerciseCount: baseExerciseCount, isRestDay: false, intensity: baseIntensity + 0.05, notes: nil),
                ProgramDayTemplate(dayNumber: 5, name: "Lower Body", focusMuscles: ["Legs", "Glutes", "Hamstrings"], exerciseCount: baseExerciseCount, isRestDay: false, intensity: baseIntensity + 0.05, notes: nil)
            ]
        case 6:
            // 6 days: PPL x 2
            dayTemplates = [
                ProgramDayTemplate(dayNumber: 1, name: "Push A", focusMuscles: ["Chest", "Shoulders", "Triceps"], exerciseCount: baseExerciseCount, isRestDay: false, intensity: baseIntensity, notes: nil),
                ProgramDayTemplate(dayNumber: 2, name: "Pull A", focusMuscles: ["Back", "Biceps"], exerciseCount: baseExerciseCount, isRestDay: false, intensity: baseIntensity, notes: nil),
                ProgramDayTemplate(dayNumber: 3, name: "Legs A", focusMuscles: ["Legs", "Glutes"], exerciseCount: baseExerciseCount, isRestDay: false, intensity: baseIntensity, notes: nil),
                ProgramDayTemplate(dayNumber: 4, name: "Push B", focusMuscles: ["Chest", "Shoulders", "Triceps"], exerciseCount: baseExerciseCount, isRestDay: false, intensity: baseIntensity + 0.05, notes: nil),
                ProgramDayTemplate(dayNumber: 5, name: "Pull B", focusMuscles: ["Back", "Biceps", "Core"], exerciseCount: baseExerciseCount, isRestDay: false, intensity: baseIntensity + 0.05, notes: nil),
                ProgramDayTemplate(dayNumber: 6, name: "Legs B", focusMuscles: ["Legs", "Glutes", "Core"], exerciseCount: baseExerciseCount, isRestDay: false, intensity: baseIntensity + 0.05, notes: nil)
            ]
        default: // 7 days
            // 7 days: PPL + Upper/Lower + Arms + Active Recovery
            dayTemplates = [
                ProgramDayTemplate(dayNumber: 1, name: "Push Day", focusMuscles: ["Chest", "Shoulders", "Triceps"], exerciseCount: baseExerciseCount, isRestDay: false, intensity: baseIntensity, notes: nil),
                ProgramDayTemplate(dayNumber: 2, name: "Pull Day", focusMuscles: ["Back", "Biceps"], exerciseCount: baseExerciseCount, isRestDay: false, intensity: baseIntensity, notes: nil),
                ProgramDayTemplate(dayNumber: 3, name: "Legs Day", focusMuscles: ["Legs", "Glutes"], exerciseCount: baseExerciseCount, isRestDay: false, intensity: baseIntensity, notes: nil),
                ProgramDayTemplate(dayNumber: 4, name: "Upper Body", focusMuscles: ["Chest", "Back", "Shoulders"], exerciseCount: baseExerciseCount, isRestDay: false, intensity: baseIntensity + 0.05, notes: nil),
                ProgramDayTemplate(dayNumber: 5, name: "Lower Body", focusMuscles: ["Legs", "Glutes", "Core"], exerciseCount: baseExerciseCount, isRestDay: false, intensity: baseIntensity + 0.05, notes: nil),
                ProgramDayTemplate(dayNumber: 6, name: "Arms & Shoulders", focusMuscles: ["Arms", "Shoulders", "Core"], exerciseCount: baseExerciseCount - 1, isRestDay: false, intensity: baseIntensity, notes: nil),
                ProgramDayTemplate(dayNumber: 7, name: "Active Recovery", focusMuscles: ["Stretch"], exerciseCount: 0, isRestDay: true, intensity: 0.3, notes: "Light stretching or walk")
            ]
        }
        
        // Return a new template with the generated day templates
        return SmartProgramTemplate(
            id: baseTemplate.id,
            category: baseTemplate.category,
            baseName: baseTemplate.baseName,
            description: baseTemplate.description,
            totalDays: 28, // 4 weeks
            daysPerWeek: userDays,
            difficulty: baseTemplate.difficulty,
            isProgressive: baseTemplate.isProgressive,
            seriesOrder: baseTemplate.seriesOrder,
            seriesId: baseTemplate.seriesId,
            prerequisiteId: baseTemplate.prerequisiteId,
            targetMuscleGroups: baseTemplate.targetMuscleGroups,
            estimatedMinutesPerDay: level == "beginner" ? 30 : (level == "advanced" ? 50 : 40),
            restDayPattern: baseTemplate.restDayPattern,
            dayTemplates: dayTemplates,
            goalAlignment: baseTemplate.goalAlignment,
            equipmentRequirements: baseTemplate.equipmentRequirements,
            minExperienceLevel: baseTemplate.minExperienceLevel
        )
    }
    
    /// Generates a default full body workout day as fallback
    private func generateDefaultDay(dayNumber: Int, user: User) -> SmartProgramDay {
        let userEquipment = parseEquipment(user.equipment)
        let isGymUser = user.workoutEnvironment == "Gym" || userEquipment.contains { 
            ["Barbell", "Cables", "Machines", "Cable", "Machine"].contains($0) 
        }
        
        // Create a basic full body day template
        let dayTemplate = ProgramDayTemplate(
            dayNumber: dayNumber,
            name: "Full Body Workout",
            focusMuscles: ["Chest", "Back", "Legs", "Shoulders"],
            exerciseCount: 5,
            isRestDay: false,
            intensity: 0.7,
            notes: nil
        )
        
        // Generate exercises using the smart selection engine
        let selectedExercises = SmartExerciseSelectionEngine.shared.selectExercisesForWorkout(
            targetMuscles: dayTemplate.focusMuscles,
            exerciseCount: dayTemplate.exerciseCount,
            userEquipment: userEquipment,
            isGymUser: isGymUser,
            previousDayExercises: [],
            userGoal: user.fitnessGoal ?? "Build Muscle",
            experienceLevel: user.experienceLevel ?? "Intermediate"
        )
        
        // Convert to SmartProgramExercise
        var exercises: [SmartProgramExercise] = []
        for (index, exerciseInfo) in selectedExercises.enumerated() {
            let isCompound = index < 2 // First 2 are typically compounds
            let sets = calculateSetsForExercise(
                intensity: dayTemplate.intensity,
                isCompound: isCompound,
                userGoal: user.fitnessGoal ?? "Build Muscle",
                exerciseOrder: index
            )
            let reps = calculateRepsForExercise(
                baseReps: isCompound ? 8 : 12,
                isCompound: isCompound,
                userGoal: user.fitnessGoal ?? "Build Muscle"
            )
            
            exercises.append(SmartProgramExercise(
                id: UUID().uuidString,
                exerciseName: exerciseInfo.name,
                exerciseId: nil,
                sets: sets,
                reps: reps,
                suggestedWeight: nil,
                restSeconds: 60,
                notes: nil,
                isSuperset: false,
                supersetWith: nil
            ))
        }
        
        return SmartProgramDay(
            id: UUID().uuidString,
            dayNumber: dayNumber,
            name: dayTemplate.name,
            exercises: exercises,
            targetDuration: 40,
            restBetweenSets: 60,
            isCompleted: false,
            completedDate: nil,
            actualDuration: nil,
            totalVolume: nil
        )
    }
    
    // MARK: - Personalization
    
    private func generatePersonalizedName(template: SmartProgramTemplate, user: User) -> String {
        let firstName = user.name?.components(separatedBy: " ").first ?? "Your"
        let goal = user.fitnessGoal ?? ""
        
        // Special handling for custom program
        if template.category == .custom {
            switch goal.lowercased() {
            case let g where g.contains("muscle"): return "\(firstName)'s Muscle Blueprint"
            case let g where g.contains("strong"): return "\(firstName)'s Strength Plan"
            case let g where g.contains("weight") || g.contains("fat"): return "\(firstName)'s Transformation"
            case let g where g.contains("fit"): return "\(firstName)'s Fitness Journey"
            default: return "\(firstName)'s Custom Plan"
            }
        }
        
        // For progressive series, add level indicator
        if template.isProgressive, let order = template.seriesOrder {
            let levelName = order == 1 ? "Beginner" : (order == 2 ? "Intermediate" : "Advanced")
            return "\(template.baseName) - \(levelName)"
        }
        
        return template.baseName
    }
    
    private func generatePersonalizedDescription(template: SmartProgramTemplate, user: User) -> String {
        let goal = user.fitnessGoal ?? "fitness"
        let days = Int(user.availableDays)
        
        if template.category == .custom {
            return "A \(template.totalDays)-day program designed specifically for your \(goal.lowercased()) goals. Trains \(days > 0 ? days : 4) days per week with exercises matched to your equipment and experience level."
        }
        
        return template.description
    }
    
    private func calculateMatchScore(template: SmartProgramTemplate, user: User) -> Double {
        var score = 0.5  // Base score
        
        let userGoal = user.fitnessGoal?.lowercased() ?? ""
        let userLevel = user.experienceLevel?.lowercased() ?? "intermediate"
        let userEquipment = parseEquipment(user.equipment)
        let userDays = Int(user.availableDays)
        
        // Goal alignment (0-0.3)
        if template.goalAlignment.isEmpty || template.goalAlignment.contains(where: { userGoal.contains($0.lowercased()) }) {
            score += 0.3
        }
        
        // Experience level match (0-0.2)
        let templateLevel = template.minExperienceLevel.lowercased()
        if templateLevel == userLevel {
            score += 0.2
        } else if (templateLevel == "beginner" && userLevel != "beginner") ||
                  (templateLevel == "intermediate" && userLevel == "advanced") {
            score += 0.1  // Slightly easier is OK
        }
        
        // Equipment match (0-0.15)
        let requiredEquipment = Set(template.equipmentRequirements.map { $0.lowercased() })
        let hasEquipment = Set(userEquipment.map { $0.lowercased() })
        if requiredEquipment.isEmpty || requiredEquipment.isSubset(of: hasEquipment) {
            score += 0.15
        } else if !requiredEquipment.isDisjoint(with: hasEquipment) {
            score += 0.05
        }
        
        // Days per week match (0-0.1)
        let daysDiff = abs(template.daysPerWeek - userDays)
        if daysDiff == 0 {
            score += 0.1
        } else if daysDiff == 1 {
            score += 0.05
        }
        
        // Boost custom program for perfect personalization
        if template.category == .custom {
            score = min(1.0, score + 0.1)
        }
        
        return min(1.0, score)
    }
    
    private func checkIfUnlocked(template: SmartProgramTemplate, completedIds: Set<String>) -> Bool {
        // Non-progressive programs are always unlocked
        if !template.isProgressive {
            return true
        }
        
        // First in series is always unlocked
        if template.seriesOrder == 1 {
            return true
        }
        
        // Check if prerequisite is completed
        if let prereq = template.prerequisiteId {
            return completedIds.contains(prereq)
        }
        
        return true
    }
    
    // MARK: - Persistence (Local + Cloud)
    
    private func loadUserPrograms() async {
        if let data = defaults.data(forKey: programsKey),
           let programs = try? JSONDecoder().decode([SmartActiveProgram].self, from: data) {
            await MainActor.run {
                userPrograms = programs
            }
            AppLogger.debug("📦 [PROGRAMS] Loaded \(programs.count) programs from local cache", category: .workout)
        }
        
        await loadProgramsFromCloud()
    }
    
    private func saveUserPrograms() {
        // Save locally (immediate)
        if let data = try? JSONEncoder().encode(userPrograms) {
            defaults.set(data, forKey: programsKey)
            AppLogger.debug("💾 [PROGRAMS] Saved \(userPrograms.count) programs to local cache", category: .workout)
        }
        
        // Sync to cloud (async)
        Task {
            await saveProgramsToCloud()
        }
    }
    
    /// Cancel / delete a single program. Removes it from in-memory state,
    /// local cache, AND deletes the matching row from Supabase
    /// `user_programs`. Without the cloud delete, `loadProgramsFromCloud()`
    /// would re-append the program on next launch (bug: cancel > force
    /// quit > reopen resurrected the program). Callers: ProgramDetailView's
    /// "Cancel Program" action.
    func cancelProgram(id: String) async {
        await MainActor.run {
            userPrograms.removeAll { $0.id == id }
            // Persist the cleared local list immediately so a fast
            // relaunch before the cloud delete finishes still sees the
            // program gone (cloud will then catch up on next sync).
            if let data = try? JSONEncoder().encode(userPrograms) {
                defaults.set(data, forKey: programsKey)
            }
            objectWillChange.send()
        }

        guard let userId = SupabaseManager.shared.currentUser?.id else {
            AppLogger.warning("⚠️ [PROGRAMS] Not authenticated, skipping cloud delete for \(id)", category: .workout)
            return
        }

        do {
            try await SupabaseManager.shared.supabaseClient
                .from("user_programs")
                .delete()
                .eq("id", value: id)
                .eq("user_id", value: userId.uuidString)
                .execute()
            AppLogger.info("🗑️ [PROGRAMS] Deleted program \(id) from cloud", category: .workout)
        } catch {
            AppLogger.error("❌ [PROGRAMS] Failed to delete program \(id) from cloud: \(error)", category: .workout)
        }
    }

    /// Clear all user program data - called on logout/account deletion
    /// This ensures no data from one user is visible to another
    func clearAllData() {
        AppLogger.debug("🗑️ [PROGRAMS] Clearing all SmartProgramEngine data...", category: .workout)
        
        // Clear in-memory state
        userPrograms = []
        availablePrograms = []
        
        // Clear local storage
        defaults.removeObject(forKey: programsKey)
        
        // Notify observers of the change
        DispatchQueue.main.async { [weak self] in
            self?.objectWillChange.send()
        }
        
        AppLogger.info("✅ [PROGRAMS] SmartProgramEngine data cleared", category: .workout)
    }
    
    // MARK: - Cloud Sync (Supabase)
    
    private func loadProgramsFromCloud() async {
        guard let userId = SupabaseManager.shared.currentUser?.id else {
            AppLogger.warning("⚠️ [PROGRAMS] Not authenticated, skipping cloud load", category: .workout)
            return
        }
        
        do {
            let response: [UserProgramDTO] = try await SupabaseManager.shared.supabaseClient
                .from("user_programs")
                .select()
                .eq("user_id", value: userId.uuidString)
                .execute()
                .value
            
            if !response.isEmpty {
                // Convert DTOs to SmartActiveProgram
                let cloudPrograms = response.compactMap { dto -> SmartActiveProgram? in
                    guard let programData = dto.program_data.data(using: .utf8),
                          let program = try? JSONDecoder().decode(SmartActiveProgram.self, from: programData) else {
                        return nil
                    }
                    return program
                }
                
                // Merge with local (cloud wins for newer data)
                await MainActor.run {
                    for cloudProgram in cloudPrograms {
                        if let localIndex = userPrograms.firstIndex(where: { $0.id == cloudProgram.id }) {
                            // Cloud version exists locally - keep the one with more completed days
                            let localCompletedDays = userPrograms[localIndex].generatedDays.filter { $0.isCompleted }.count
                            let cloudCompletedDays = cloudProgram.generatedDays.filter { $0.isCompleted }.count
                            if cloudCompletedDays > localCompletedDays {
                                userPrograms[localIndex] = cloudProgram
                            }
                        } else {
                            // New program from cloud
                            userPrograms.append(cloudProgram)
                        }
                    }
                }
                AppLogger.debug("☁️ [PROGRAMS] Synced \(cloudPrograms.count) programs from cloud", category: .workout)
            }
        } catch {
            AppLogger.error("❌ [PROGRAMS] Failed to load from cloud: \(error)", category: .workout)
        }
    }
    
    private func saveProgramsToCloud() async {
        guard let userId = SupabaseManager.shared.currentUser?.id else {
            AppLogger.warning("⚠️ [PROGRAMS] Not authenticated, skipping cloud save", category: .workout)
            return
        }
        
        for program in userPrograms {
            do {
                guard let programData = try? JSONEncoder().encode(program),
                      let programJson = String(data: programData, encoding: .utf8) else {
                    continue
                }
                
                let dto: [String: AnyJSON] = [
                    "id": .string(program.id),
                    "user_id": .string(userId.uuidString),
                    "template_id": .string(program.templateId),
                    "program_name": .string(program.personalizedName),
                    "current_day": .integer(program.currentDay),
                    "total_days": .integer(program.generatedDays.count),
                    "completed_days": .integer(program.generatedDays.filter { $0.isCompleted }.count),
                    "is_active": .bool(!program.isCompleted),
                    "started_date": .string(ISO8601DateFormatter().string(from: program.startDate)),
                    "program_data": .string(programJson),
                    "last_updated": .string(ISO8601DateFormatter().string(from: Date()))
                ]
                
                try await SupabaseManager.shared.supabaseClient
                    .from("user_programs")
                    .upsert(dto, onConflict: "id")
                    .execute()
                
            } catch {
                AppLogger.error("❌ [PROGRAMS] Failed to save program \(program.id) to cloud: \(error)", category: .workout)
            }
        }
        AppLogger.debug("☁️ [PROGRAMS] Saved \(userPrograms.count) programs to cloud", category: .workout)
    }
    
    /// Saves completed day data for learning engine
    func saveDayCompletionToCloud(program: SmartActiveProgram, day: SmartProgramDay) async {
        guard let userId = SupabaseManager.shared.currentUser?.id else { return }
        
        do {
            let exerciseNames = day.exercises.map { $0.exerciseName }
            
            // Extract muscle groups from exercise names (infer from day name)
            let focusMuscles: [String]
            let dayNameLower = day.name.lowercased()
            if dayNameLower.contains("push") {
                focusMuscles = ["Chest", "Shoulders", "Triceps"]
            } else if dayNameLower.contains("pull") {
                focusMuscles = ["Back", "Biceps"]
            } else if dayNameLower.contains("leg") {
                focusMuscles = ["Quads", "Hamstrings", "Glutes"]
            } else if dayNameLower.contains("upper") {
                focusMuscles = ["Chest", "Back", "Shoulders", "Arms"]
            } else if dayNameLower.contains("lower") {
                focusMuscles = ["Legs", "Glutes", "Core"]
            } else if dayNameLower.contains("full body") {
                focusMuscles = ["Full Body"]
            } else if dayNameLower.contains("chest") {
                focusMuscles = ["Chest", "Triceps"]
            } else if dayNameLower.contains("back") {
                focusMuscles = ["Back", "Biceps"]
            } else if dayNameLower.contains("shoulder") {
                focusMuscles = ["Shoulders", "Core"]
            } else if dayNameLower.contains("arm") {
                focusMuscles = ["Biceps", "Triceps"]
            } else if dayNameLower.contains("core") {
                focusMuscles = ["Core", "Abs"]
            } else {
                focusMuscles = ["Full Body"]
            }
            
            let dto: [String: AnyJSON] = [
                "id": .string(UUID().uuidString),
                "user_id": .string(userId.uuidString),
                "program_id": .string(program.id),
                "program_name": .string(program.personalizedName),
                "day_number": .integer(day.dayNumber),
                "day_name": .string(day.name),
                "focus_muscles": .array(focusMuscles.map { .string($0) }),
                "exercises_completed": .array(exerciseNames.map { .string($0) }),
                "completed_at": .string(ISO8601DateFormatter().string(from: day.completedDate ?? Date())),
                "duration_seconds": .integer(day.actualDuration ?? 0)
            ]
            
            try await SupabaseManager.shared.supabaseClient
                .from("program_day_completions")
                .insert(dto)
                .execute()
            
            AppLogger.debug("☁️ [PROGRAMS] Saved day \(day.dayNumber) completion for learning engine", category: .workout)
        } catch {
            AppLogger.error("❌ [PROGRAMS] Failed to save day completion: \(error)", category: .workout)
        }
    }
    
    private func getCompletedProgramIds(for user: User) -> Set<String> {
        let key = "completed_programs_\(user.id?.uuidString ?? "")"
        if let ids = defaults.array(forKey: key) as? [String] {
            return Set(ids)
        }
        return []
    }
    
    private func markProgramCompleted(templateId: String, userId: String) {
        let key = "completed_programs_\(userId)"
        var ids = defaults.array(forKey: key) as? [String] ?? []
        if !ids.contains(templateId) {
            ids.append(templateId)
            defaults.set(ids, forKey: key)
        }
        
        // Also save to cloud
        Task {
            await saveCompletedProgramToCloud(templateId: templateId, userId: userId)
        }
    }
    
    private func saveCompletedProgramToCloud(templateId: String, userId: String) async {
        do {
            let dto: [String: AnyJSON] = [
                "id": .string(UUID().uuidString),
                "user_id": .string(userId),
                "template_id": .string(templateId),
                "completed_at": .string(ISO8601DateFormatter().string(from: Date()))
            ]
            
            try await SupabaseManager.shared.supabaseClient
                .from("completed_programs")
                .insert(dto)
                .execute()
            
            AppLogger.debug("☁️ [PROGRAMS] Marked program \(templateId) as completed in cloud", category: .workout)
        } catch {
            AppLogger.error("❌ [PROGRAMS] Failed to save completed program: \(error)", category: .workout)
        }
    }
    
    // MARK: - Helpers
    
    private func inferEquipmentRequirements(from template: MasterProgramTemplate) -> [String] {
        let tags = Set(template.tags.map { $0.lowercased() })
        var equipment: [String] = ["Dumbbells"]
        
        if tags.contains("strength") || tags.contains("hypertrophy") || tags.contains("bodybuilding") {
            equipment.append(contentsOf: ["Barbell", "Bench"])
        }
        if tags.contains("supersets") || template.daysPerWeek >= 4 {
            equipment.append("Cables")
        }
        if tags.contains("periodized") || tags.contains("premium") {
            equipment.append(contentsOf: ["Machines", "Barbell", "Bench"])
        }
        
        return Array(Set(equipment))
    }
    
    private func parseEquipment(_ equipment: NSObject?) -> [String] {
        if let array = equipment as? [String], !array.isEmpty {
            return array
        }
        if let string = equipment as? String, !string.isEmpty {
            return string.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        }
        return []
    }
}

// MARK: - Supporting Types

struct PersonalizedProgram: Identifiable {
    var id: String { template.id }
    let template: SmartProgramTemplate
    let personalizedName: String
    let isUnlocked: Bool
    let isCompleted: Bool
    let matchScore: Double
    let personalizedDescription: String
    
    var matchPercentage: Int {
        Int(matchScore * 100)
    }
}

struct DayPreview: Identifiable {
    let id = UUID()
    let dayNumber: Int
    let name: String
    let isRestDay: Bool
    let focusMuscles: [String]
    let estimatedMinutes: Int
    let exerciseCount: Int
}

