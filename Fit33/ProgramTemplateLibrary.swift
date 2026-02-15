//
//  ProgramTemplateLibrary.swift
//  GoFit
//
//  Evidence-based program templates for 14/30/90 day programs.
//  Two goal tracks: GAIN (strength + hypertrophy) and LEAN (fat loss + muscle retention).
//  
//  Grounded in ACSM, NSCA, and Schoenfeld guidelines for frequency,
//  rep ranges, rest periods, and periodized loading.
//
//  Programs are stored in Supabase and cached locally. Only Day 1 is generated
//  upfront; subsequent days are generated lazily as the user completes each day.
//

import Foundation

// MARK: - Program Goal

enum ProgramGoalTrack: String, Codable, CaseIterable {
    case gain = "gain"      // Strength + Hypertrophy
    case lean = "lean"      // Fat Loss + Muscle Retention
    
    var displayName: String {
        switch self {
        case .gain: return "Gain (Strength & Size)"
        case .lean: return "Lean (Cut & Define)"
        }
    }
    
    var icon: String {
        switch self {
        case .gain: return "figure.strengthtraining.traditional"
        case .lean: return "flame.fill"
        }
    }
}

// MARK: - Program Duration

enum ProgramDurationLength: Int, Codable, CaseIterable {
    case twoWeeks = 14
    case oneMonth = 30
    case threeMonths = 90
    
    var displayName: String {
        switch self {
        case .twoWeeks: return "14-Day"
        case .oneMonth: return "30-Day"
        case .threeMonths: return "90-Day"
        }
    }
    
    var weekCount: Int {
        switch self {
        case .twoWeeks: return 2
        case .oneMonth: return 4
        case .threeMonths: return 12
        }
    }
}

// MARK: - Periodization Block

struct PeriodizationBlock: Codable {
    let blockNumber: Int          // 1, 2, 3
    let name: String              // "Hypertrophy Base", "Strength Emphasis", etc.
    let weekStart: Int            // Week number this block starts
    let weekEnd: Int              // Week number this block ends
    let emphasis: BlockEmphasis
    let primaryRepsMin: Int       // Main lift rep range
    let primaryRepsMax: Int
    let primarySets: Int
    let primaryRestSeconds: Int
    let accessoryRepsMin: Int     // Accessory rep range
    let accessoryRepsMax: Int
    let accessorySets: Int
    let accessoryRestSeconds: Int
    let deloadWeek: Int?          // Which week is deload (nil = no deload)
    let finishersPerWeek: Int     // Number of conditioning finishers
    let intensityTechniques: [String]  // e.g., "drop sets", "back-off sets"
    
    enum BlockEmphasis: String, Codable {
        case hypertrophy = "hypertrophy"
        case strength = "strength"
        case intensityTechniques = "intensity_techniques"
        case densityConditioning = "density_conditioning"
        case strengthAnchors = "strength_anchors"
        case peakLeanness = "peak_leanness"
    }
}

// MARK: - Day Split Template

struct DaySplitTemplate: Codable {
    let dayOfWeek: Int            // 1-7 within the week cycle
    let name: String              // "Upper Push", "Lower Squat", etc.
    let primaryMuscles: [String]
    let secondaryMuscles: [String]
    let isRestDay: Bool
    let exerciseSlots: [ExerciseSlot]
    let hasFinisher: Bool
    let supersetPairs: [[Int]]?   // Pairs of slot indices for supersets (LEAN programs)
    
    struct ExerciseSlot: Codable {
        let role: ExerciseRole     // compound, secondary, accessory, finisher
        let targetBundles: [String]  // Bundle IDs to pull from
        let targetMuscles: [String]  // Fallback muscle targeting
        let isAnchor: Bool          // Should stay consistent across weeks
        let setsOverride: Int?      // Override block defaults
        let repsMinOverride: Int?
        let repsMaxOverride: Int?
        let restOverride: Int?
        let notes: String?
        
        enum ExerciseRole: String, Codable {
            case primaryCompound = "primary_compound"
            case secondaryCompound = "secondary_compound"
            case accessory = "accessory"
            case isolation = "isolation"
            case finisher = "finisher"
            case warmup = "warmup"
        }
    }
}

// MARK: - Master Program Template

struct MasterProgramTemplate: Identifiable, Codable {
    let id: String
    let name: String
    let description: String
    let goal: ProgramGoalTrack
    let duration: ProgramDurationLength
    let daysPerWeek: Int
    let icon: String
    let color: String
    let difficulty: String              // "Beginner", "Intermediate", "Advanced"
    let blocks: [PeriodizationBlock]    // Periodization blocks
    let weeklySchedule: [DaySplitTemplate]  // Day templates for one week cycle
    let weeklyPatternCoverage: [String] // Required patterns per week
    let exerciseSwapPercentage: Double  // How much to change between weeks (0.7 = 70%)
    let benefits: [String]
    let warmupSuggestion: String
    let tags: [String]                  // For search/filter
    
    // Convenience accessors (used by SmartProgramEngine integration)
    var goalTrack: ProgramGoalTrack { goal }
    var durationDays: Int { duration.rawValue }
    var totalDays: Int { duration.rawValue }
    var weekCount: Int { duration.weekCount }
}

// MARK: - Program Template Library

class ProgramTemplateLibrary {
    static let shared = ProgramTemplateLibrary()
    
    /// Cached templates (built once)
    lazy var templates: [MasterProgramTemplate] = {
        return [
            build14DayGain(),
            build30DayGain(),
            build90DayGain(),
            build14DayLean(),
            build30DayLean(),
            build90DayLean()
        ]
    }()
    
    private init() {}
    
    /// Get all available program templates
    func getAllTemplates() -> [MasterProgramTemplate] {
        return templates
    }
    
    /// Get templates filtered by goal
    func getTemplates(for goal: ProgramGoalTrack) -> [MasterProgramTemplate] {
        return templates.filter { $0.goal == goal }
    }
    
    /// Get a specific template by ID
    func getTemplate(byId id: String) -> MasterProgramTemplate? {
        return templates.first { $0.id == id }
    }
    
    // MARK: - 14-Day GAIN (4 days/week)
    
    private func build14DayGain() -> MasterProgramTemplate {
        let block = PeriodizationBlock(
            blockNumber: 1,
            name: "Hypertrophy + Strength Intro",
            weekStart: 1, weekEnd: 2,
            emphasis: .hypertrophy,
            primaryRepsMin: 5, primaryRepsMax: 8, primarySets: 4, primaryRestSeconds: 150,
            accessoryRepsMin: 8, accessoryRepsMax: 12, accessorySets: 3, accessoryRestSeconds: 90,
            deloadWeek: nil,
            finishersPerWeek: 0,
            intensityTechniques: []
        )
        
        let schedule: [DaySplitTemplate] = [
            // Day 1: Upper Push
            DaySplitTemplate(dayOfWeek: 1, name: "Upper Push (Chest/Shoulders/Tris)",
                primaryMuscles: ["Chest", "Shoulders", "Triceps"], secondaryMuscles: ["Core"],
                isRestDay: false, exerciseSlots: [
                    .init(role: .primaryCompound, targetBundles: ["horizontal_press"], targetMuscles: ["Chest"], isAnchor: true, setsOverride: 4, repsMinOverride: 5, repsMaxOverride: 8, restOverride: 150, notes: "Primary press - barbell or DB"),
                    .init(role: .secondaryCompound, targetBundles: ["horizontal_press"], targetMuscles: ["Chest"], isAnchor: false, setsOverride: 3, repsMinOverride: 8, repsMaxOverride: 10, restOverride: 90, notes: "Different angle from primary"),
                    .init(role: .accessory, targetBundles: ["chest_isolation"], targetMuscles: ["Chest"], isAnchor: false, setsOverride: 3, repsMinOverride: 10, repsMaxOverride: 15, restOverride: 60, notes: nil),
                    .init(role: .accessory, targetBundles: ["tricep_extension_bundle"], targetMuscles: ["Triceps"], isAnchor: false, setsOverride: 3, repsMinOverride: 8, repsMaxOverride: 12, restOverride: 60, notes: "Dip or close-grip pattern"),
                    .init(role: .isolation, targetBundles: ["tricep_extension_bundle"], targetMuscles: ["Triceps"], isAnchor: false, setsOverride: 3, repsMinOverride: 12, repsMaxOverride: 15, restOverride: 60, notes: "Pushdown or overhead extension"),
                    .init(role: .isolation, targetBundles: ["lateral_raise_bundle"], targetMuscles: ["Shoulders"], isAnchor: false, setsOverride: 3, repsMinOverride: 12, repsMaxOverride: 15, restOverride: 60, notes: "Optional lateral raise"),
                ], hasFinisher: false, supersetPairs: nil),
            
            // Day 2: Lower (Squat emphasis)
            DaySplitTemplate(dayOfWeek: 2, name: "Lower Body (Squat Emphasis)",
                primaryMuscles: ["Quadriceps", "Glutes"], secondaryMuscles: ["Hamstrings", "Calves", "Core"],
                isRestDay: false, exerciseSlots: [
                    .init(role: .primaryCompound, targetBundles: ["squat_pattern"], targetMuscles: ["Quadriceps", "Glutes"], isAnchor: true, setsOverride: 4, repsMinOverride: 5, repsMaxOverride: 8, restOverride: 180, notes: "Squat or leg press"),
                    .init(role: .secondaryCompound, targetBundles: ["lunge_pattern"], targetMuscles: ["Quadriceps", "Glutes"], isAnchor: false, setsOverride: 3, repsMinOverride: 8, repsMaxOverride: 12, restOverride: 90, notes: nil),
                    .init(role: .accessory, targetBundles: ["hinge_pattern"], targetMuscles: ["Hamstrings"], isAnchor: false, setsOverride: 3, repsMinOverride: 8, repsMaxOverride: 12, restOverride: 90, notes: "RDL or leg curl"),
                    .init(role: .isolation, targetBundles: ["quad_isolation"], targetMuscles: ["Quadriceps"], isAnchor: false, setsOverride: 3, repsMinOverride: 10, repsMaxOverride: 15, restOverride: 60, notes: nil),
                    .init(role: .isolation, targetBundles: ["calf_bundle"], targetMuscles: ["Calves"], isAnchor: false, setsOverride: 3, repsMinOverride: 12, repsMaxOverride: 20, restOverride: 45, notes: nil),
                ], hasFinisher: false, supersetPairs: nil),
            
            // Day 3: Rest
            DaySplitTemplate(dayOfWeek: 3, name: "Rest / Light Cardio",
                primaryMuscles: [], secondaryMuscles: [],
                isRestDay: true, exerciseSlots: [], hasFinisher: false, supersetPairs: nil),
            
            // Day 4: Upper Pull
            DaySplitTemplate(dayOfWeek: 4, name: "Upper Pull (Back/Biceps)",
                primaryMuscles: ["Back", "Lats", "Biceps"], secondaryMuscles: ["Rear Delts", "Forearms"],
                isRestDay: false, exerciseSlots: [
                    .init(role: .primaryCompound, targetBundles: ["vertical_pull"], targetMuscles: ["Lats", "Back"], isAnchor: true, setsOverride: 4, repsMinOverride: 6, repsMaxOverride: 8, restOverride: 150, notes: "Weighted pull-up or lat pulldown"),
                    .init(role: .secondaryCompound, targetBundles: ["horizontal_pull"], targetMuscles: ["Back"], isAnchor: false, setsOverride: 3, repsMinOverride: 8, repsMaxOverride: 10, restOverride: 90, notes: "Chest-supported or DB row"),
                    .init(role: .accessory, targetBundles: ["horizontal_pull"], targetMuscles: ["Back"], isAnchor: false, setsOverride: 3, repsMinOverride: 10, repsMaxOverride: 12, restOverride: 60, notes: "Cable row, different grip"),
                    .init(role: .accessory, targetBundles: ["rear_delt_bundle"], targetMuscles: ["Rear Delts"], isAnchor: false, setsOverride: 3, repsMinOverride: 12, repsMaxOverride: 15, restOverride: 60, notes: "Face pull or reverse fly"),
                    .init(role: .isolation, targetBundles: ["bicep_curl_bundle"], targetMuscles: ["Biceps"], isAnchor: false, setsOverride: 3, repsMinOverride: 8, repsMaxOverride: 12, restOverride: 60, notes: "Incline curl or EZ curl"),
                    .init(role: .isolation, targetBundles: ["bicep_curl_bundle"], targetMuscles: ["Biceps"], isAnchor: false, setsOverride: 2, repsMinOverride: 12, repsMaxOverride: 15, restOverride: 45, notes: "Hammer curl or cable curl"),
                ], hasFinisher: false, supersetPairs: nil),
            
            // Day 5: Lower (Hinge emphasis)
            DaySplitTemplate(dayOfWeek: 5, name: "Lower Body (Hinge Emphasis + Glutes)",
                primaryMuscles: ["Hamstrings", "Glutes"], secondaryMuscles: ["Quadriceps", "Calves", "Core"],
                isRestDay: false, exerciseSlots: [
                    .init(role: .primaryCompound, targetBundles: ["hinge_pattern"], targetMuscles: ["Hamstrings", "Glutes"], isAnchor: true, setsOverride: 4, repsMinOverride: 5, repsMaxOverride: 8, restOverride: 180, notes: "RDL or conventional deadlift"),
                    .init(role: .secondaryCompound, targetBundles: ["hip_thrust_bundle"], targetMuscles: ["Glutes"], isAnchor: false, setsOverride: 3, repsMinOverride: 8, repsMaxOverride: 12, restOverride: 90, notes: nil),
                    .init(role: .accessory, targetBundles: ["lunge_pattern"], targetMuscles: ["Quadriceps", "Glutes"], isAnchor: false, setsOverride: 3, repsMinOverride: 8, repsMaxOverride: 12, restOverride: 90, notes: nil),
                    .init(role: .isolation, targetBundles: ["ham_isolation"], targetMuscles: ["Hamstrings"], isAnchor: false, setsOverride: 3, repsMinOverride: 10, repsMaxOverride: 15, restOverride: 60, notes: nil),
                    .init(role: .isolation, targetBundles: ["calf_bundle"], targetMuscles: ["Calves"], isAnchor: false, setsOverride: 3, repsMinOverride: 12, repsMaxOverride: 20, restOverride: 45, notes: nil),
                ], hasFinisher: false, supersetPairs: nil),
            
            // Days 6-7: Rest
            DaySplitTemplate(dayOfWeek: 6, name: "Rest / Mobility",
                primaryMuscles: [], secondaryMuscles: [],
                isRestDay: true, exerciseSlots: [], hasFinisher: false, supersetPairs: nil),
            DaySplitTemplate(dayOfWeek: 7, name: "Rest",
                primaryMuscles: [], secondaryMuscles: [],
                isRestDay: true, exerciseSlots: [], hasFinisher: false, supersetPairs: nil),
        ]
        
        return MasterProgramTemplate(
            id: "14_day_gain",
            name: "14-Day Gain",
            description: "2-week strength + hypertrophy kickstart. Upper/Lower split with heavy anchors and high-quality volume. Great pumps, smart pairings.",
            goal: .gain, duration: .twoWeeks, daysPerWeek: 4,
            icon: "figure.strengthtraining.traditional", color: "blue",
            difficulty: "Intermediate",
            blocks: [block],
            weeklySchedule: schedule,
            weeklyPatternCoverage: ["squat", "hinge", "horizontal_press", "vertical_press", "horizontal_pull", "vertical_pull"],
            exerciseSwapPercentage: 0.7,
            benefits: ["Build muscle fast", "Increase strength", "Smart muscle pairings", "Progressive overload"],
            warmupSuggestion: "5 min light cardio + 2 warm-up sets of first exercise at 50% and 75%",
            tags: ["gain", "14-day", "upper-lower", "strength", "hypertrophy"]
        )
    }
    
    // MARK: - 14-Day LEAN (5 days/week)
    
    private func build14DayLean() -> MasterProgramTemplate {
        let block = PeriodizationBlock(
            blockNumber: 1,
            name: "High Density Fat Burn",
            weekStart: 1, weekEnd: 2,
            emphasis: .densityConditioning,
            primaryRepsMin: 4, primaryRepsMax: 8, primarySets: 4, primaryRestSeconds: 120,
            accessoryRepsMin: 10, accessoryRepsMax: 15, accessorySets: 3, accessoryRestSeconds: 45,
            deloadWeek: nil,
            finishersPerWeek: 3,
            intensityTechniques: ["supersets", "short rest"]
        )
        
        let schedule: [DaySplitTemplate] = [
            // Day 1: Full Body A (push focus) + finisher
            DaySplitTemplate(dayOfWeek: 1, name: "Full Body A (Push Focus) + Finisher",
                primaryMuscles: ["Chest", "Quadriceps", "Shoulders"], secondaryMuscles: ["Triceps", "Core"],
                isRestDay: false, exerciseSlots: [
                    .init(role: .primaryCompound, targetBundles: ["horizontal_press"], targetMuscles: ["Chest"], isAnchor: true, setsOverride: 4, repsMinOverride: 5, repsMaxOverride: 8, restOverride: 120, notes: "Heavy anchor — keep strength"),
                    .init(role: .secondaryCompound, targetBundles: ["squat_pattern"], targetMuscles: ["Quadriceps"], isAnchor: false, setsOverride: 3, repsMinOverride: 8, repsMaxOverride: 12, restOverride: 60, notes: nil),
                    .init(role: .accessory, targetBundles: ["vertical_press"], targetMuscles: ["Shoulders"], isAnchor: false, setsOverride: 3, repsMinOverride: 10, repsMaxOverride: 12, restOverride: 45, notes: nil),
                    .init(role: .isolation, targetBundles: ["tricep_extension_bundle"], targetMuscles: ["Triceps"], isAnchor: false, setsOverride: 3, repsMinOverride: 12, repsMaxOverride: 15, restOverride: 30, notes: nil),
                    .init(role: .finisher, targetBundles: [], targetMuscles: ["Full Body"], isAnchor: false, setsOverride: nil, repsMinOverride: nil, repsMaxOverride: nil, restOverride: nil, notes: "8-12 min EMOM: sled/rower/bike OR 10 min incline walk intervals"),
                ], hasFinisher: true, supersetPairs: [[2, 3]]),  // Shoulders superset with Triceps
            
            // Day 2: Lower + Core
            DaySplitTemplate(dayOfWeek: 2, name: "Lower Body + Core",
                primaryMuscles: ["Quadriceps", "Hamstrings", "Glutes"], secondaryMuscles: ["Calves", "Core"],
                isRestDay: false, exerciseSlots: [
                    .init(role: .primaryCompound, targetBundles: ["squat_pattern"], targetMuscles: ["Quadriceps"], isAnchor: true, setsOverride: 4, repsMinOverride: 6, repsMaxOverride: 8, restOverride: 120, notes: nil),
                    .init(role: .secondaryCompound, targetBundles: ["hinge_pattern"], targetMuscles: ["Hamstrings"], isAnchor: false, setsOverride: 3, repsMinOverride: 8, repsMaxOverride: 12, restOverride: 60, notes: nil),
                    .init(role: .accessory, targetBundles: ["lunge_pattern"], targetMuscles: ["Glutes"], isAnchor: false, setsOverride: 3, repsMinOverride: 10, repsMaxOverride: 12, restOverride: 45, notes: nil),
                    .init(role: .isolation, targetBundles: ["core_stability_bundle", "core_flexion_bundle"], targetMuscles: ["Core"], isAnchor: false, setsOverride: 3, repsMinOverride: 12, repsMaxOverride: 20, restOverride: 30, notes: nil),
                ], hasFinisher: false, supersetPairs: [[1, 2]]),  // Hinge superset with Lunge
            
            // Day 3: Upper Pull + Finisher
            DaySplitTemplate(dayOfWeek: 3, name: "Upper Pull + Finisher",
                primaryMuscles: ["Back", "Biceps"], secondaryMuscles: ["Rear Delts", "Core"],
                isRestDay: false, exerciseSlots: [
                    .init(role: .primaryCompound, targetBundles: ["horizontal_pull"], targetMuscles: ["Back"], isAnchor: true, setsOverride: 4, repsMinOverride: 6, repsMaxOverride: 8, restOverride: 120, notes: nil),
                    .init(role: .secondaryCompound, targetBundles: ["vertical_pull"], targetMuscles: ["Lats"], isAnchor: false, setsOverride: 3, repsMinOverride: 8, repsMaxOverride: 12, restOverride: 60, notes: nil),
                    .init(role: .accessory, targetBundles: ["rear_delt_bundle"], targetMuscles: ["Rear Delts"], isAnchor: false, setsOverride: 3, repsMinOverride: 12, repsMaxOverride: 15, restOverride: 45, notes: nil),
                    .init(role: .isolation, targetBundles: ["bicep_curl_bundle"], targetMuscles: ["Biceps"], isAnchor: false, setsOverride: 3, repsMinOverride: 10, repsMaxOverride: 15, restOverride: 45, notes: nil),
                    .init(role: .finisher, targetBundles: [], targetMuscles: ["Full Body"], isAnchor: false, setsOverride: nil, repsMinOverride: nil, repsMaxOverride: nil, restOverride: nil, notes: "3 rounds: farmer carry 40m + plank 30s + KB swings x15"),
                ], hasFinisher: true, supersetPairs: [[2, 3]]),  // Rear delt superset with curls
            
            // Day 4: Rest / Zone 2
            DaySplitTemplate(dayOfWeek: 4, name: "Rest / Zone 2 Cardio",
                primaryMuscles: [], secondaryMuscles: [],
                isRestDay: true, exerciseSlots: [], hasFinisher: false, supersetPairs: nil),
            
            // Day 5: Full Body B (pull focus) + Finisher
            DaySplitTemplate(dayOfWeek: 5, name: "Full Body B (Pull Focus) + Finisher",
                primaryMuscles: ["Back", "Hamstrings", "Biceps"], secondaryMuscles: ["Shoulders", "Core"],
                isRestDay: false, exerciseSlots: [
                    .init(role: .primaryCompound, targetBundles: ["hinge_pattern"], targetMuscles: ["Hamstrings", "Back"], isAnchor: true, setsOverride: 4, repsMinOverride: 5, repsMaxOverride: 8, restOverride: 120, notes: nil),
                    .init(role: .secondaryCompound, targetBundles: ["horizontal_pull"], targetMuscles: ["Back"], isAnchor: false, setsOverride: 3, repsMinOverride: 8, repsMaxOverride: 12, restOverride: 60, notes: nil),
                    .init(role: .accessory, targetBundles: ["lateral_raise_bundle"], targetMuscles: ["Shoulders"], isAnchor: false, setsOverride: 3, repsMinOverride: 12, repsMaxOverride: 15, restOverride: 45, notes: nil),
                    .init(role: .isolation, targetBundles: ["bicep_curl_bundle"], targetMuscles: ["Biceps"], isAnchor: false, setsOverride: 3, repsMinOverride: 10, repsMaxOverride: 15, restOverride: 45, notes: nil),
                    .init(role: .finisher, targetBundles: [], targetMuscles: ["Full Body"], isAnchor: false, setsOverride: nil, repsMinOverride: nil, repsMaxOverride: nil, restOverride: nil, notes: "10 min incline treadmill intervals: 2 min walk / 1 min jog"),
                ], hasFinisher: true, supersetPairs: [[2, 3]]),
            
            // Day 6: Arms/Shoulders Metabolic
            DaySplitTemplate(dayOfWeek: 6, name: "Arms & Shoulders Metabolic",
                primaryMuscles: ["Biceps", "Triceps", "Shoulders"], secondaryMuscles: ["Core"],
                isRestDay: false, exerciseSlots: [
                    .init(role: .accessory, targetBundles: ["vertical_press"], targetMuscles: ["Shoulders"], isAnchor: false, setsOverride: 3, repsMinOverride: 10, repsMaxOverride: 12, restOverride: 45, notes: nil),
                    .init(role: .accessory, targetBundles: ["lateral_raise_bundle"], targetMuscles: ["Shoulders"], isAnchor: false, setsOverride: 3, repsMinOverride: 12, repsMaxOverride: 15, restOverride: 30, notes: nil),
                    .init(role: .isolation, targetBundles: ["bicep_curl_bundle"], targetMuscles: ["Biceps"], isAnchor: false, setsOverride: 3, repsMinOverride: 10, repsMaxOverride: 15, restOverride: 30, notes: nil),
                    .init(role: .isolation, targetBundles: ["tricep_extension_bundle"], targetMuscles: ["Triceps"], isAnchor: false, setsOverride: 3, repsMinOverride: 10, repsMaxOverride: 15, restOverride: 30, notes: nil),
                ], hasFinisher: false, supersetPairs: [[0, 1], [2, 3]]),  // All supersetted
            
            // Day 7: Rest
            DaySplitTemplate(dayOfWeek: 7, name: "Rest",
                primaryMuscles: [], secondaryMuscles: [],
                isRestDay: true, exerciseSlots: [], hasFinisher: false, supersetPairs: nil),
        ]
        
        return MasterProgramTemplate(
            id: "14_day_lean",
            name: "14-Day Lean",
            description: "2-week high-density fat-burning program. Keeps 1 heavy anchor per session to maintain muscle, supersets for work rate, conditioning finishers 3x/week.",
            goal: .lean, duration: .twoWeeks, daysPerWeek: 5,
            icon: "flame.fill", color: "orange",
            difficulty: "Intermediate",
            blocks: [block],
            weeklySchedule: schedule,
            weeklyPatternCoverage: ["squat", "hinge", "horizontal_press", "horizontal_pull", "vertical_pull"],
            exerciseSwapPercentage: 0.7,
            benefits: ["Burn fat while keeping muscle", "High workout density", "Conditioning finishers", "Superset efficiency"],
            warmupSuggestion: "3-5 min light cardio + dynamic stretching",
            tags: ["lean", "14-day", "fat-loss", "supersets", "finishers"]
        )
    }
    
    // MARK: - 30-Day GAIN (5 days/week, bodybuilding split)
    
    private func build30DayGain() -> MasterProgramTemplate {
        let block = PeriodizationBlock(
            blockNumber: 1,
            name: "Progressive Hypertrophy",
            weekStart: 1, weekEnd: 4,
            emphasis: .hypertrophy,
            primaryRepsMin: 6, primaryRepsMax: 10, primarySets: 4, primaryRestSeconds: 120,
            accessoryRepsMin: 8, accessoryRepsMax: 12, accessorySets: 3, accessoryRestSeconds: 90,
            deloadWeek: 4,  // Week 4 is deload
            finishersPerWeek: 0,
            intensityTechniques: []
        )
        
        let schedule: [DaySplitTemplate] = [
            // Day 1: Chest + Triceps
            DaySplitTemplate(dayOfWeek: 1, name: "Chest & Triceps",
                primaryMuscles: ["Chest", "Triceps"], secondaryMuscles: ["Shoulders"],
                isRestDay: false, exerciseSlots: [
                    .init(role: .primaryCompound, targetBundles: ["horizontal_press"], targetMuscles: ["Chest"], isAnchor: true, setsOverride: 4, repsMinOverride: 6, repsMaxOverride: 10, restOverride: 120, notes: "Flat or incline press"),
                    .init(role: .secondaryCompound, targetBundles: ["horizontal_press"], targetMuscles: ["Chest"], isAnchor: false, setsOverride: 3, repsMinOverride: 8, repsMaxOverride: 12, restOverride: 90, notes: "Alternate angle from primary"),
                    .init(role: .accessory, targetBundles: ["chest_isolation"], targetMuscles: ["Chest"], isAnchor: false, setsOverride: 3, repsMinOverride: 10, repsMaxOverride: 15, restOverride: 60, notes: "Fly pattern"),
                    .init(role: .accessory, targetBundles: ["tricep_extension_bundle"], targetMuscles: ["Triceps"], isAnchor: false, setsOverride: 3, repsMinOverride: 8, repsMaxOverride: 12, restOverride: 60, notes: "Overhead or lengthened position"),
                    .init(role: .isolation, targetBundles: ["tricep_extension_bundle"], targetMuscles: ["Triceps"], isAnchor: false, setsOverride: 3, repsMinOverride: 12, repsMaxOverride: 15, restOverride: 45, notes: "Pushdown or dip"),
                ], hasFinisher: false, supersetPairs: nil),
            
            // Day 2: Back + Biceps
            DaySplitTemplate(dayOfWeek: 2, name: "Back & Biceps",
                primaryMuscles: ["Back", "Lats", "Biceps"], secondaryMuscles: ["Rear Delts"],
                isRestDay: false, exerciseSlots: [
                    .init(role: .primaryCompound, targetBundles: ["horizontal_pull"], targetMuscles: ["Back"], isAnchor: true, setsOverride: 4, repsMinOverride: 6, repsMaxOverride: 10, restOverride: 120, notes: nil),
                    .init(role: .secondaryCompound, targetBundles: ["vertical_pull"], targetMuscles: ["Lats"], isAnchor: false, setsOverride: 3, repsMinOverride: 8, repsMaxOverride: 12, restOverride: 90, notes: nil),
                    .init(role: .accessory, targetBundles: ["horizontal_pull"], targetMuscles: ["Back"], isAnchor: false, setsOverride: 3, repsMinOverride: 10, repsMaxOverride: 12, restOverride: 60, notes: "Different grip/angle"),
                    .init(role: .accessory, targetBundles: ["rear_delt_bundle"], targetMuscles: ["Rear Delts"], isAnchor: false, setsOverride: 3, repsMinOverride: 12, repsMaxOverride: 15, restOverride: 60, notes: nil),
                    .init(role: .isolation, targetBundles: ["bicep_curl_bundle"], targetMuscles: ["Biceps"], isAnchor: false, setsOverride: 3, repsMinOverride: 8, repsMaxOverride: 12, restOverride: 60, notes: nil),
                    .init(role: .isolation, targetBundles: ["bicep_curl_bundle"], targetMuscles: ["Biceps"], isAnchor: false, setsOverride: 2, repsMinOverride: 12, repsMaxOverride: 15, restOverride: 45, notes: nil),
                ], hasFinisher: false, supersetPairs: nil),
            
            // Day 3: Legs (Quads)
            DaySplitTemplate(dayOfWeek: 3, name: "Legs (Quad Focus)",
                primaryMuscles: ["Quadriceps", "Glutes"], secondaryMuscles: ["Calves", "Core"],
                isRestDay: false, exerciseSlots: [
                    .init(role: .primaryCompound, targetBundles: ["squat_pattern"], targetMuscles: ["Quadriceps"], isAnchor: true, setsOverride: 4, repsMinOverride: 6, repsMaxOverride: 10, restOverride: 150, notes: nil),
                    .init(role: .secondaryCompound, targetBundles: ["squat_pattern"], targetMuscles: ["Quadriceps"], isAnchor: false, setsOverride: 3, repsMinOverride: 8, repsMaxOverride: 12, restOverride: 90, notes: "Different squat/press variant"),
                    .init(role: .accessory, targetBundles: ["lunge_pattern"], targetMuscles: ["Quadriceps", "Glutes"], isAnchor: false, setsOverride: 3, repsMinOverride: 8, repsMaxOverride: 12, restOverride: 90, notes: nil),
                    .init(role: .isolation, targetBundles: ["quad_isolation"], targetMuscles: ["Quadriceps"], isAnchor: false, setsOverride: 3, repsMinOverride: 10, repsMaxOverride: 15, restOverride: 60, notes: nil),
                    .init(role: .isolation, targetBundles: ["calf_bundle"], targetMuscles: ["Calves"], isAnchor: false, setsOverride: 4, repsMinOverride: 12, repsMaxOverride: 20, restOverride: 45, notes: nil),
                ], hasFinisher: false, supersetPairs: nil),
            
            // Day 4: Shoulders + Arms
            DaySplitTemplate(dayOfWeek: 4, name: "Shoulders & Arms",
                primaryMuscles: ["Shoulders", "Biceps", "Triceps"], secondaryMuscles: ["Traps"],
                isRestDay: false, exerciseSlots: [
                    .init(role: .primaryCompound, targetBundles: ["vertical_press"], targetMuscles: ["Shoulders"], isAnchor: true, setsOverride: 4, repsMinOverride: 6, repsMaxOverride: 10, restOverride: 120, notes: nil),
                    .init(role: .accessory, targetBundles: ["lateral_raise_bundle"], targetMuscles: ["Shoulders"], isAnchor: false, setsOverride: 3, repsMinOverride: 12, repsMaxOverride: 15, restOverride: 60, notes: nil),
                    .init(role: .accessory, targetBundles: ["rear_delt_bundle"], targetMuscles: ["Rear Delts"], isAnchor: false, setsOverride: 3, repsMinOverride: 12, repsMaxOverride: 15, restOverride: 60, notes: nil),
                    .init(role: .isolation, targetBundles: ["bicep_curl_bundle"], targetMuscles: ["Biceps"], isAnchor: false, setsOverride: 3, repsMinOverride: 8, repsMaxOverride: 12, restOverride: 60, notes: nil),
                    .init(role: .isolation, targetBundles: ["tricep_extension_bundle"], targetMuscles: ["Triceps"], isAnchor: false, setsOverride: 3, repsMinOverride: 8, repsMaxOverride: 12, restOverride: 60, notes: nil),
                ], hasFinisher: false, supersetPairs: nil),
            
            // Day 5: Legs (Ham/Glute) + Core
            DaySplitTemplate(dayOfWeek: 5, name: "Legs (Hamstring/Glute Focus) + Core",
                primaryMuscles: ["Hamstrings", "Glutes"], secondaryMuscles: ["Core", "Calves"],
                isRestDay: false, exerciseSlots: [
                    .init(role: .primaryCompound, targetBundles: ["hinge_pattern"], targetMuscles: ["Hamstrings", "Glutes"], isAnchor: true, setsOverride: 4, repsMinOverride: 6, repsMaxOverride: 10, restOverride: 150, notes: nil),
                    .init(role: .secondaryCompound, targetBundles: ["hip_thrust_bundle"], targetMuscles: ["Glutes"], isAnchor: false, setsOverride: 3, repsMinOverride: 8, repsMaxOverride: 12, restOverride: 90, notes: nil),
                    .init(role: .isolation, targetBundles: ["ham_isolation"], targetMuscles: ["Hamstrings"], isAnchor: false, setsOverride: 3, repsMinOverride: 10, repsMaxOverride: 15, restOverride: 60, notes: nil),
                    .init(role: .accessory, targetBundles: ["core_stability_bundle", "core_flexion_bundle"], targetMuscles: ["Core"], isAnchor: false, setsOverride: 3, repsMinOverride: 12, repsMaxOverride: 20, restOverride: 45, notes: nil),
                    .init(role: .isolation, targetBundles: ["calf_bundle"], targetMuscles: ["Calves"], isAnchor: false, setsOverride: 3, repsMinOverride: 12, repsMaxOverride: 20, restOverride: 45, notes: nil),
                ], hasFinisher: false, supersetPairs: nil),
            
            // Days 6-7: Rest
            DaySplitTemplate(dayOfWeek: 6, name: "Rest / Light Cardio",
                primaryMuscles: [], secondaryMuscles: [],
                isRestDay: true, exerciseSlots: [], hasFinisher: false, supersetPairs: nil),
            DaySplitTemplate(dayOfWeek: 7, name: "Rest",
                primaryMuscles: [], secondaryMuscles: [],
                isRestDay: true, exerciseSlots: [], hasFinisher: false, supersetPairs: nil),
        ]
        
        return MasterProgramTemplate(
            id: "30_day_gain",
            name: "30-Day Gain",
            description: "Classic 4-week bodybuilding split: Chest/Tris, Back/Bis, Legs-Quad, Shoulders/Arms, Legs-Ham/Glute. Progressive weekly overload with a deload in Week 4.",
            goal: .gain, duration: .oneMonth, daysPerWeek: 5,
            icon: "figure.strengthtraining.traditional", color: "purple",
            difficulty: "Intermediate",
            blocks: [block],
            weeklySchedule: schedule,
            weeklyPatternCoverage: ["squat", "hinge", "horizontal_press", "vertical_press", "horizontal_pull", "vertical_pull"],
            exerciseSwapPercentage: 0.3,  // Lower swap % — keep consistency for progression
            benefits: ["Maximum muscle growth", "Balanced physique", "Progressive overload", "Built-in deload"],
            warmupSuggestion: "5 min cardio + 2 warm-up sets at 50% and 75% for first compound",
            tags: ["gain", "30-day", "bodybuilding", "split", "hypertrophy"]
        )
    }
    
    // MARK: - 30-Day LEAN (4 days/week + optional metabolic)
    
    private func build30DayLean() -> MasterProgramTemplate {
        let block = PeriodizationBlock(
            blockNumber: 1,
            name: "Density Supersets",
            weekStart: 1, weekEnd: 4,
            emphasis: .densityConditioning,
            primaryRepsMin: 6, primaryRepsMax: 10, primarySets: 4, primaryRestSeconds: 90,
            accessoryRepsMin: 10, accessoryRepsMax: 15, accessorySets: 3, accessoryRestSeconds: 45,
            deloadWeek: nil,
            finishersPerWeek: 2,
            intensityTechniques: ["supersets", "short rest"]
        )
        
        let schedule: [DaySplitTemplate] = [
            // Day 1: Upper A (push/pull supersets)
            DaySplitTemplate(dayOfWeek: 1, name: "Upper A (Push/Pull Supersets)",
                primaryMuscles: ["Chest", "Back", "Shoulders"], secondaryMuscles: ["Biceps", "Triceps"],
                isRestDay: false, exerciseSlots: [
                    .init(role: .primaryCompound, targetBundles: ["horizontal_press"], targetMuscles: ["Chest"], isAnchor: true, setsOverride: 4, repsMinOverride: 6, repsMaxOverride: 8, restOverride: 90, notes: nil),
                    .init(role: .primaryCompound, targetBundles: ["horizontal_pull"], targetMuscles: ["Back"], isAnchor: true, setsOverride: 4, repsMinOverride: 6, repsMaxOverride: 8, restOverride: 90, notes: nil),
                    .init(role: .secondaryCompound, targetBundles: ["horizontal_press"], targetMuscles: ["Chest"], isAnchor: false, setsOverride: 3, repsMinOverride: 10, repsMaxOverride: 12, restOverride: 45, notes: nil),
                    .init(role: .secondaryCompound, targetBundles: ["vertical_pull"], targetMuscles: ["Lats"], isAnchor: false, setsOverride: 3, repsMinOverride: 10, repsMaxOverride: 12, restOverride: 45, notes: nil),
                    .init(role: .isolation, targetBundles: ["lateral_raise_bundle"], targetMuscles: ["Shoulders"], isAnchor: false, setsOverride: 3, repsMinOverride: 12, repsMaxOverride: 15, restOverride: 30, notes: nil),
                    .init(role: .isolation, targetBundles: ["rear_delt_bundle"], targetMuscles: ["Rear Delts"], isAnchor: false, setsOverride: 3, repsMinOverride: 12, repsMaxOverride: 15, restOverride: 30, notes: nil),
                ], hasFinisher: false, supersetPairs: [[0, 1], [2, 3], [4, 5]]),
            
            // Day 2: Lower A (squat focus + core)
            DaySplitTemplate(dayOfWeek: 2, name: "Lower A (Squat Focus + Core)",
                primaryMuscles: ["Quadriceps", "Glutes", "Core"], secondaryMuscles: ["Hamstrings", "Calves"],
                isRestDay: false, exerciseSlots: [
                    .init(role: .primaryCompound, targetBundles: ["squat_pattern"], targetMuscles: ["Quadriceps"], isAnchor: true, setsOverride: 4, repsMinOverride: 6, repsMaxOverride: 8, restOverride: 120, notes: nil),
                    .init(role: .secondaryCompound, targetBundles: ["lunge_pattern"], targetMuscles: ["Quadriceps", "Glutes"], isAnchor: false, setsOverride: 3, repsMinOverride: 10, repsMaxOverride: 12, restOverride: 60, notes: nil),
                    .init(role: .accessory, targetBundles: ["ham_isolation"], targetMuscles: ["Hamstrings"], isAnchor: false, setsOverride: 3, repsMinOverride: 10, repsMaxOverride: 15, restOverride: 45, notes: nil),
                    .init(role: .accessory, targetBundles: ["core_stability_bundle"], targetMuscles: ["Core"], isAnchor: false, setsOverride: 3, repsMinOverride: 12, repsMaxOverride: 20, restOverride: 30, notes: nil),
                    .init(role: .finisher, targetBundles: [], targetMuscles: ["Full Body"], isAnchor: false, setsOverride: nil, repsMinOverride: nil, repsMaxOverride: nil, restOverride: nil, notes: "8 min EMOM: 10 KB swings + 30s plank"),
                ], hasFinisher: true, supersetPairs: [[2, 3]]),
            
            // Day 3: Rest
            DaySplitTemplate(dayOfWeek: 3, name: "Rest / Active Recovery",
                primaryMuscles: [], secondaryMuscles: [],
                isRestDay: true, exerciseSlots: [], hasFinisher: false, supersetPairs: nil),
            
            // Day 4: Upper B
            DaySplitTemplate(dayOfWeek: 4, name: "Upper B (Push/Pull Supersets)",
                primaryMuscles: ["Chest", "Back", "Arms"], secondaryMuscles: ["Shoulders"],
                isRestDay: false, exerciseSlots: [
                    .init(role: .primaryCompound, targetBundles: ["vertical_press"], targetMuscles: ["Shoulders"], isAnchor: true, setsOverride: 4, repsMinOverride: 6, repsMaxOverride: 8, restOverride: 90, notes: nil),
                    .init(role: .primaryCompound, targetBundles: ["vertical_pull"], targetMuscles: ["Lats"], isAnchor: true, setsOverride: 4, repsMinOverride: 6, repsMaxOverride: 8, restOverride: 90, notes: nil),
                    .init(role: .accessory, targetBundles: ["chest_isolation"], targetMuscles: ["Chest"], isAnchor: false, setsOverride: 3, repsMinOverride: 10, repsMaxOverride: 15, restOverride: 45, notes: nil),
                    .init(role: .accessory, targetBundles: ["horizontal_pull"], targetMuscles: ["Back"], isAnchor: false, setsOverride: 3, repsMinOverride: 10, repsMaxOverride: 12, restOverride: 45, notes: nil),
                    .init(role: .isolation, targetBundles: ["bicep_curl_bundle"], targetMuscles: ["Biceps"], isAnchor: false, setsOverride: 3, repsMinOverride: 10, repsMaxOverride: 15, restOverride: 30, notes: nil),
                    .init(role: .isolation, targetBundles: ["tricep_extension_bundle"], targetMuscles: ["Triceps"], isAnchor: false, setsOverride: 3, repsMinOverride: 10, repsMaxOverride: 15, restOverride: 30, notes: nil),
                ], hasFinisher: false, supersetPairs: [[0, 1], [2, 3], [4, 5]]),
            
            // Day 5: Lower B (hinge focus + core)
            DaySplitTemplate(dayOfWeek: 5, name: "Lower B (Hinge Focus + Core)",
                primaryMuscles: ["Hamstrings", "Glutes", "Core"], secondaryMuscles: ["Quadriceps", "Calves"],
                isRestDay: false, exerciseSlots: [
                    .init(role: .primaryCompound, targetBundles: ["hinge_pattern"], targetMuscles: ["Hamstrings"], isAnchor: true, setsOverride: 4, repsMinOverride: 6, repsMaxOverride: 8, restOverride: 120, notes: nil),
                    .init(role: .secondaryCompound, targetBundles: ["hip_thrust_bundle"], targetMuscles: ["Glutes"], isAnchor: false, setsOverride: 3, repsMinOverride: 8, repsMaxOverride: 12, restOverride: 60, notes: nil),
                    .init(role: .accessory, targetBundles: ["quad_isolation"], targetMuscles: ["Quadriceps"], isAnchor: false, setsOverride: 3, repsMinOverride: 10, repsMaxOverride: 15, restOverride: 45, notes: nil),
                    .init(role: .accessory, targetBundles: ["core_rotation_bundle"], targetMuscles: ["Core"], isAnchor: false, setsOverride: 3, repsMinOverride: 12, repsMaxOverride: 20, restOverride: 30, notes: nil),
                    .init(role: .finisher, targetBundles: [], targetMuscles: ["Full Body"], isAnchor: false, setsOverride: nil, repsMinOverride: nil, repsMaxOverride: nil, restOverride: nil, notes: "10 min: incline walk intervals"),
                ], hasFinisher: true, supersetPairs: [[2, 3]]),
            
            // Days 6-7: Rest
            DaySplitTemplate(dayOfWeek: 6, name: "Optional: Conditioning + Weak Points",
                primaryMuscles: [], secondaryMuscles: [],
                isRestDay: true, exerciseSlots: [], hasFinisher: false, supersetPairs: nil),
            DaySplitTemplate(dayOfWeek: 7, name: "Rest / Long Walk (Zone 2)",
                primaryMuscles: [], secondaryMuscles: [],
                isRestDay: true, exerciseSlots: [], hasFinisher: false, supersetPairs: nil),
        ]
        
        return MasterProgramTemplate(
            id: "30_day_lean",
            name: "30-Day Lean",
            description: "4-week upper/lower split with non-conflicting supersets for maximum work density. Push↔Pull, Curl↔Tricep, Lat Raise↔Face Pull. Finishers 2x/week.",
            goal: .lean, duration: .oneMonth, daysPerWeek: 4,
            icon: "flame.fill", color: "pink",
            difficulty: "Intermediate",
            blocks: [block],
            weeklySchedule: schedule,
            weeklyPatternCoverage: ["squat", "hinge", "horizontal_press", "vertical_press", "horizontal_pull", "vertical_pull"],
            exerciseSwapPercentage: 0.4,
            benefits: ["Efficient supersets", "High calorie burn", "Muscle retention", "Conditioning progression"],
            warmupSuggestion: "3-5 min jump rope or cycling + dynamic stretching",
            tags: ["lean", "30-day", "upper-lower", "supersets", "fat-loss"]
        )
    }
    
    // MARK: - 90-Day GAIN (5 days/week, 3 periodized blocks)
    
    private func build90DayGain() -> MasterProgramTemplate {
        let blocks: [PeriodizationBlock] = [
            // Block 1 (Weeks 1-4): Hypertrophy base
            PeriodizationBlock(
                blockNumber: 1, name: "Hypertrophy Base",
                weekStart: 1, weekEnd: 4,
                emphasis: .hypertrophy,
                primaryRepsMin: 6, primaryRepsMax: 12, primarySets: 4, primaryRestSeconds: 90,
                accessoryRepsMin: 8, accessoryRepsMax: 15, accessorySets: 3, accessoryRestSeconds: 60,
                deloadWeek: nil,
                finishersPerWeek: 0,
                intensityTechniques: []
            ),
            // Block 2 (Weeks 5-8): Strength emphasis
            PeriodizationBlock(
                blockNumber: 2, name: "Strength Emphasis",
                weekStart: 5, weekEnd: 8,
                emphasis: .strength,
                primaryRepsMin: 3, primaryRepsMax: 6, primarySets: 5, primaryRestSeconds: 180,
                accessoryRepsMin: 6, accessoryRepsMax: 12, accessorySets: 3, accessoryRestSeconds: 90,
                deloadWeek: 8,
                finishersPerWeek: 0,
                intensityTechniques: []
            ),
            // Block 3 (Weeks 9-12): Hypertrophy + intensity techniques
            PeriodizationBlock(
                blockNumber: 3, name: "Hypertrophy + Intensity",
                weekStart: 9, weekEnd: 12,
                emphasis: .intensityTechniques,
                primaryRepsMin: 8, primaryRepsMax: 12, primarySets: 4, primaryRestSeconds: 90,
                accessoryRepsMin: 10, accessoryRepsMax: 15, accessorySets: 3, accessoryRestSeconds: 60,
                deloadWeek: 12,
                finishersPerWeek: 1,
                intensityTechniques: ["lengthened partials", "back-off sets", "pump finishers"]
            ),
        ]
        
        // Upper/Lower/Rest/Upper/Lower/Arms+Delts/Rest
        let schedule: [DaySplitTemplate] = [
            // Day 1: Upper 1 (heavy press + back volume)
            DaySplitTemplate(dayOfWeek: 1, name: "Upper 1 (Heavy Press + Back Volume)",
                primaryMuscles: ["Chest", "Back", "Shoulders"], secondaryMuscles: ["Biceps", "Triceps"],
                isRestDay: false, exerciseSlots: [
                    .init(role: .primaryCompound, targetBundles: ["horizontal_press"], targetMuscles: ["Chest"], isAnchor: true, setsOverride: nil, repsMinOverride: nil, repsMaxOverride: nil, restOverride: nil, notes: "Block determines sets/reps"),
                    .init(role: .secondaryCompound, targetBundles: ["horizontal_press"], targetMuscles: ["Chest"], isAnchor: false, setsOverride: nil, repsMinOverride: nil, repsMaxOverride: nil, restOverride: nil, notes: nil),
                    .init(role: .accessory, targetBundles: ["horizontal_pull"], targetMuscles: ["Back"], isAnchor: false, setsOverride: nil, repsMinOverride: nil, repsMaxOverride: nil, restOverride: nil, notes: nil),
                    .init(role: .accessory, targetBundles: ["vertical_pull"], targetMuscles: ["Lats"], isAnchor: false, setsOverride: nil, repsMinOverride: nil, repsMaxOverride: nil, restOverride: nil, notes: nil),
                    .init(role: .isolation, targetBundles: ["rear_delt_bundle"], targetMuscles: ["Rear Delts"], isAnchor: false, setsOverride: nil, repsMinOverride: nil, repsMaxOverride: nil, restOverride: nil, notes: nil),
                    .init(role: .isolation, targetBundles: ["tricep_extension_bundle"], targetMuscles: ["Triceps"], isAnchor: false, setsOverride: nil, repsMinOverride: nil, repsMaxOverride: nil, restOverride: nil, notes: nil),
                ], hasFinisher: false, supersetPairs: nil),
            
            // Day 2: Lower 1 (heavy squat + posterior accessories)
            DaySplitTemplate(dayOfWeek: 2, name: "Lower 1 (Heavy Squat + Posterior)",
                primaryMuscles: ["Quadriceps", "Glutes", "Hamstrings"], secondaryMuscles: ["Calves", "Core"],
                isRestDay: false, exerciseSlots: [
                    .init(role: .primaryCompound, targetBundles: ["squat_pattern"], targetMuscles: ["Quadriceps"], isAnchor: true, setsOverride: nil, repsMinOverride: nil, repsMaxOverride: nil, restOverride: nil, notes: nil),
                    .init(role: .secondaryCompound, targetBundles: ["hinge_pattern"], targetMuscles: ["Hamstrings"], isAnchor: false, setsOverride: nil, repsMinOverride: nil, repsMaxOverride: nil, restOverride: nil, notes: nil),
                    .init(role: .accessory, targetBundles: ["lunge_pattern"], targetMuscles: ["Quadriceps", "Glutes"], isAnchor: false, setsOverride: nil, repsMinOverride: nil, repsMaxOverride: nil, restOverride: nil, notes: nil),
                    .init(role: .isolation, targetBundles: ["ham_isolation"], targetMuscles: ["Hamstrings"], isAnchor: false, setsOverride: nil, repsMinOverride: nil, repsMaxOverride: nil, restOverride: nil, notes: nil),
                    .init(role: .isolation, targetBundles: ["calf_bundle"], targetMuscles: ["Calves"], isAnchor: false, setsOverride: nil, repsMinOverride: nil, repsMaxOverride: nil, restOverride: nil, notes: nil),
                ], hasFinisher: false, supersetPairs: nil),
            
            // Day 3: Rest
            DaySplitTemplate(dayOfWeek: 3, name: "Rest",
                primaryMuscles: [], secondaryMuscles: [],
                isRestDay: true, exerciseSlots: [], hasFinisher: false, supersetPairs: nil),
            
            // Day 4: Upper 2 (heavy pull + chest volume)
            DaySplitTemplate(dayOfWeek: 4, name: "Upper 2 (Heavy Pull + Chest Volume)",
                primaryMuscles: ["Back", "Chest", "Shoulders"], secondaryMuscles: ["Biceps", "Triceps"],
                isRestDay: false, exerciseSlots: [
                    .init(role: .primaryCompound, targetBundles: ["horizontal_pull"], targetMuscles: ["Back"], isAnchor: true, setsOverride: nil, repsMinOverride: nil, repsMaxOverride: nil, restOverride: nil, notes: nil),
                    .init(role: .secondaryCompound, targetBundles: ["vertical_pull"], targetMuscles: ["Lats"], isAnchor: false, setsOverride: nil, repsMinOverride: nil, repsMaxOverride: nil, restOverride: nil, notes: nil),
                    .init(role: .accessory, targetBundles: ["horizontal_press"], targetMuscles: ["Chest"], isAnchor: false, setsOverride: nil, repsMinOverride: nil, repsMaxOverride: nil, restOverride: nil, notes: "Volume press - lighter"),
                    .init(role: .accessory, targetBundles: ["chest_isolation"], targetMuscles: ["Chest"], isAnchor: false, setsOverride: nil, repsMinOverride: nil, repsMaxOverride: nil, restOverride: nil, notes: nil),
                    .init(role: .isolation, targetBundles: ["lateral_raise_bundle"], targetMuscles: ["Shoulders"], isAnchor: false, setsOverride: nil, repsMinOverride: nil, repsMaxOverride: nil, restOverride: nil, notes: nil),
                    .init(role: .isolation, targetBundles: ["bicep_curl_bundle"], targetMuscles: ["Biceps"], isAnchor: false, setsOverride: nil, repsMinOverride: nil, repsMaxOverride: nil, restOverride: nil, notes: nil),
                ], hasFinisher: false, supersetPairs: nil),
            
            // Day 5: Lower 2 (heavy hinge + quad accessories)
            DaySplitTemplate(dayOfWeek: 5, name: "Lower 2 (Heavy Hinge + Quad Accessories)",
                primaryMuscles: ["Hamstrings", "Glutes", "Quadriceps"], secondaryMuscles: ["Calves", "Core"],
                isRestDay: false, exerciseSlots: [
                    .init(role: .primaryCompound, targetBundles: ["hinge_pattern"], targetMuscles: ["Hamstrings", "Glutes"], isAnchor: true, setsOverride: nil, repsMinOverride: nil, repsMaxOverride: nil, restOverride: nil, notes: nil),
                    .init(role: .secondaryCompound, targetBundles: ["hip_thrust_bundle"], targetMuscles: ["Glutes"], isAnchor: false, setsOverride: nil, repsMinOverride: nil, repsMaxOverride: nil, restOverride: nil, notes: nil),
                    .init(role: .accessory, targetBundles: ["squat_pattern"], targetMuscles: ["Quadriceps"], isAnchor: false, setsOverride: nil, repsMinOverride: nil, repsMaxOverride: nil, restOverride: nil, notes: "Quad accessory - lighter"),
                    .init(role: .isolation, targetBundles: ["quad_isolation"], targetMuscles: ["Quadriceps"], isAnchor: false, setsOverride: nil, repsMinOverride: nil, repsMaxOverride: nil, restOverride: nil, notes: nil),
                    .init(role: .isolation, targetBundles: ["calf_bundle"], targetMuscles: ["Calves"], isAnchor: false, setsOverride: nil, repsMinOverride: nil, repsMaxOverride: nil, restOverride: nil, notes: nil),
                ], hasFinisher: false, supersetPairs: nil),
            
            // Day 6: Arms + Delts (high variety, shorter rests)
            DaySplitTemplate(dayOfWeek: 6, name: "Arms & Delts (Pump Day)",
                primaryMuscles: ["Biceps", "Triceps", "Shoulders"], secondaryMuscles: ["Forearms"],
                isRestDay: false, exerciseSlots: [
                    .init(role: .accessory, targetBundles: ["vertical_press"], targetMuscles: ["Shoulders"], isAnchor: false, setsOverride: 3, repsMinOverride: 10, repsMaxOverride: 12, restOverride: 60, notes: nil),
                    .init(role: .accessory, targetBundles: ["lateral_raise_bundle"], targetMuscles: ["Shoulders"], isAnchor: false, setsOverride: 3, repsMinOverride: 12, repsMaxOverride: 15, restOverride: 45, notes: nil),
                    .init(role: .isolation, targetBundles: ["bicep_curl_bundle"], targetMuscles: ["Biceps"], isAnchor: false, setsOverride: 3, repsMinOverride: 10, repsMaxOverride: 12, restOverride: 45, notes: nil),
                    .init(role: .isolation, targetBundles: ["bicep_curl_bundle"], targetMuscles: ["Biceps"], isAnchor: false, setsOverride: 2, repsMinOverride: 12, repsMaxOverride: 15, restOverride: 30, notes: "Different curl variant"),
                    .init(role: .isolation, targetBundles: ["tricep_extension_bundle"], targetMuscles: ["Triceps"], isAnchor: false, setsOverride: 3, repsMinOverride: 10, repsMaxOverride: 12, restOverride: 45, notes: nil),
                    .init(role: .isolation, targetBundles: ["tricep_extension_bundle"], targetMuscles: ["Triceps"], isAnchor: false, setsOverride: 2, repsMinOverride: 12, repsMaxOverride: 15, restOverride: 30, notes: "Different extension variant"),
                ], hasFinisher: false, supersetPairs: [[2, 4], [3, 5]]),  // Curl ↔ Extension supersets
            
            // Day 7: Rest
            DaySplitTemplate(dayOfWeek: 7, name: "Rest",
                primaryMuscles: [], secondaryMuscles: [],
                isRestDay: true, exerciseSlots: [], hasFinisher: false, supersetPairs: nil),
        ]
        
        return MasterProgramTemplate(
            id: "90_day_gain",
            name: "90-Day Gain (Strength & Size)",
            description: "Premium 3-block periodized program. Block 1: hypertrophy base (6-12 reps). Block 2: strength emphasis (3-6 reps). Block 3: hypertrophy + intensity techniques. Feels like having a real S&C coach.",
            goal: .gain, duration: .threeMonths, daysPerWeek: 5,
            icon: "bolt.fill", color: "red",
            difficulty: "Intermediate",
            blocks: blocks,
            weeklySchedule: schedule,
            weeklyPatternCoverage: ["squat", "hinge", "horizontal_press", "vertical_press", "horizontal_pull", "vertical_pull"],
            exerciseSwapPercentage: 0.5,
            benefits: ["Periodized progression", "Maximum strength + size", "3 distinct training phases", "Built-in deloads", "Intensity techniques in Block 3"],
            warmupSuggestion: "5 min light cardio + 2-3 warm-up sets ramping to working weight",
            tags: ["gain", "90-day", "periodized", "blocks", "premium"]
        )
    }
    
    // MARK: - 90-Day LEAN (5 days/week, 3 periodized blocks)
    
    private func build90DayLean() -> MasterProgramTemplate {
        let blocks: [PeriodizationBlock] = [
            // Block 1 (Weeks 1-4): Strength anchors + conditioning habit
            PeriodizationBlock(
                blockNumber: 1, name: "Strength Anchors + Conditioning",
                weekStart: 1, weekEnd: 4,
                emphasis: .strengthAnchors,
                primaryRepsMin: 4, primaryRepsMax: 8, primarySets: 4, primaryRestSeconds: 120,
                accessoryRepsMin: 8, accessoryRepsMax: 15, accessorySets: 3, accessoryRestSeconds: 60,
                deloadWeek: nil,
                finishersPerWeek: 2,
                intensityTechniques: []
            ),
            // Block 2 (Weeks 5-8): Volume density
            PeriodizationBlock(
                blockNumber: 2, name: "Volume Density",
                weekStart: 5, weekEnd: 8,
                emphasis: .densityConditioning,
                primaryRepsMin: 6, primaryRepsMax: 10, primarySets: 4, primaryRestSeconds: 90,
                accessoryRepsMin: 8, accessoryRepsMax: 15, accessorySets: 3, accessoryRestSeconds: 45,
                deloadWeek: nil,
                finishersPerWeek: 3,
                intensityTechniques: ["supersets", "short rest"]
            ),
            // Block 3 (Weeks 9-12): Peak leanness
            PeriodizationBlock(
                blockNumber: 3, name: "Peak Leanness",
                weekStart: 9, weekEnd: 12,
                emphasis: .peakLeanness,
                primaryRepsMin: 4, primaryRepsMax: 8, primarySets: 4, primaryRestSeconds: 120,
                accessoryRepsMin: 10, accessoryRepsMax: 15, accessorySets: 3, accessoryRestSeconds: 30,
                deloadWeek: 12,
                finishersPerWeek: 3,
                intensityTechniques: ["supersets", "circuits", "zone 2"]
            ),
        ]
        
        // Same base schedule as 30-day lean but with density progression across blocks
        let schedule: [DaySplitTemplate] = [
            DaySplitTemplate(dayOfWeek: 1, name: "Upper Push + Pull Density",
                primaryMuscles: ["Chest", "Back", "Shoulders"], secondaryMuscles: ["Biceps", "Triceps"],
                isRestDay: false, exerciseSlots: [
                    .init(role: .primaryCompound, targetBundles: ["horizontal_press"], targetMuscles: ["Chest"], isAnchor: true, setsOverride: nil, repsMinOverride: nil, repsMaxOverride: nil, restOverride: nil, notes: nil),
                    .init(role: .primaryCompound, targetBundles: ["horizontal_pull"], targetMuscles: ["Back"], isAnchor: true, setsOverride: nil, repsMinOverride: nil, repsMaxOverride: nil, restOverride: nil, notes: nil),
                    .init(role: .accessory, targetBundles: ["vertical_pull"], targetMuscles: ["Lats"], isAnchor: false, setsOverride: nil, repsMinOverride: nil, repsMaxOverride: nil, restOverride: nil, notes: nil),
                    .init(role: .isolation, targetBundles: ["lateral_raise_bundle"], targetMuscles: ["Shoulders"], isAnchor: false, setsOverride: nil, repsMinOverride: nil, repsMaxOverride: nil, restOverride: nil, notes: nil),
                    .init(role: .isolation, targetBundles: ["rear_delt_bundle"], targetMuscles: ["Rear Delts"], isAnchor: false, setsOverride: nil, repsMinOverride: nil, repsMaxOverride: nil, restOverride: nil, notes: nil),
                ], hasFinisher: false, supersetPairs: [[0, 1], [3, 4]]),
            
            DaySplitTemplate(dayOfWeek: 2, name: "Lower Density + Core",
                primaryMuscles: ["Quadriceps", "Hamstrings", "Glutes"], secondaryMuscles: ["Core", "Calves"],
                isRestDay: false, exerciseSlots: [
                    .init(role: .primaryCompound, targetBundles: ["squat_pattern"], targetMuscles: ["Quadriceps"], isAnchor: true, setsOverride: nil, repsMinOverride: nil, repsMaxOverride: nil, restOverride: nil, notes: nil),
                    .init(role: .secondaryCompound, targetBundles: ["hinge_pattern"], targetMuscles: ["Hamstrings"], isAnchor: false, setsOverride: nil, repsMinOverride: nil, repsMaxOverride: nil, restOverride: nil, notes: nil),
                    .init(role: .accessory, targetBundles: ["hip_thrust_bundle"], targetMuscles: ["Glutes"], isAnchor: false, setsOverride: nil, repsMinOverride: nil, repsMaxOverride: nil, restOverride: nil, notes: nil),
                    .init(role: .isolation, targetBundles: ["core_stability_bundle"], targetMuscles: ["Core"], isAnchor: false, setsOverride: nil, repsMinOverride: nil, repsMaxOverride: nil, restOverride: nil, notes: nil),
                    .init(role: .finisher, targetBundles: [], targetMuscles: ["Full Body"], isAnchor: false, setsOverride: nil, repsMinOverride: nil, repsMaxOverride: nil, restOverride: nil, notes: "8-12 min conditioning circuit"),
                ], hasFinisher: true, supersetPairs: nil),
            
            DaySplitTemplate(dayOfWeek: 3, name: "Upper Pull + Arms Density",
                primaryMuscles: ["Back", "Biceps", "Triceps"], secondaryMuscles: ["Shoulders"],
                isRestDay: false, exerciseSlots: [
                    .init(role: .primaryCompound, targetBundles: ["vertical_pull"], targetMuscles: ["Lats"], isAnchor: true, setsOverride: nil, repsMinOverride: nil, repsMaxOverride: nil, restOverride: nil, notes: nil),
                    .init(role: .secondaryCompound, targetBundles: ["horizontal_pull"], targetMuscles: ["Back"], isAnchor: false, setsOverride: nil, repsMinOverride: nil, repsMaxOverride: nil, restOverride: nil, notes: nil),
                    .init(role: .isolation, targetBundles: ["bicep_curl_bundle"], targetMuscles: ["Biceps"], isAnchor: false, setsOverride: nil, repsMinOverride: nil, repsMaxOverride: nil, restOverride: nil, notes: nil),
                    .init(role: .isolation, targetBundles: ["tricep_extension_bundle"], targetMuscles: ["Triceps"], isAnchor: false, setsOverride: nil, repsMinOverride: nil, repsMaxOverride: nil, restOverride: nil, notes: nil),
                    .init(role: .finisher, targetBundles: [], targetMuscles: ["Full Body"], isAnchor: false, setsOverride: nil, repsMinOverride: nil, repsMaxOverride: nil, restOverride: nil, notes: "Farmer carry + KB swings circuit"),
                ], hasFinisher: true, supersetPairs: [[2, 3]]),
            
            DaySplitTemplate(dayOfWeek: 4, name: "Rest / Zone 2",
                primaryMuscles: [], secondaryMuscles: [],
                isRestDay: true, exerciseSlots: [], hasFinisher: false, supersetPairs: nil),
            
            DaySplitTemplate(dayOfWeek: 5, name: "Lower Hinge + Conditioning",
                primaryMuscles: ["Hamstrings", "Glutes", "Quadriceps"], secondaryMuscles: ["Core"],
                isRestDay: false, exerciseSlots: [
                    .init(role: .primaryCompound, targetBundles: ["hinge_pattern"], targetMuscles: ["Hamstrings"], isAnchor: true, setsOverride: nil, repsMinOverride: nil, repsMaxOverride: nil, restOverride: nil, notes: nil),
                    .init(role: .secondaryCompound, targetBundles: ["lunge_pattern"], targetMuscles: ["Quadriceps", "Glutes"], isAnchor: false, setsOverride: nil, repsMinOverride: nil, repsMaxOverride: nil, restOverride: nil, notes: nil),
                    .init(role: .isolation, targetBundles: ["quad_isolation"], targetMuscles: ["Quadriceps"], isAnchor: false, setsOverride: nil, repsMinOverride: nil, repsMaxOverride: nil, restOverride: nil, notes: nil),
                    .init(role: .isolation, targetBundles: ["ham_isolation"], targetMuscles: ["Hamstrings"], isAnchor: false, setsOverride: nil, repsMinOverride: nil, repsMaxOverride: nil, restOverride: nil, notes: nil),
                    .init(role: .finisher, targetBundles: [], targetMuscles: ["Full Body"], isAnchor: false, setsOverride: nil, repsMinOverride: nil, repsMaxOverride: nil, restOverride: nil, notes: "10 min incline walk or rower intervals"),
                ], hasFinisher: true, supersetPairs: [[2, 3]]),
            
            DaySplitTemplate(dayOfWeek: 6, name: "Full Body Metabolic (Optional)",
                primaryMuscles: ["Full Body"], secondaryMuscles: ["Core"],
                isRestDay: false, exerciseSlots: [
                    .init(role: .accessory, targetBundles: ["horizontal_press"], targetMuscles: ["Chest"], isAnchor: false, setsOverride: 3, repsMinOverride: 10, repsMaxOverride: 12, restOverride: 45, notes: nil),
                    .init(role: .accessory, targetBundles: ["squat_pattern"], targetMuscles: ["Quadriceps"], isAnchor: false, setsOverride: 3, repsMinOverride: 10, repsMaxOverride: 12, restOverride: 45, notes: nil),
                    .init(role: .accessory, targetBundles: ["horizontal_pull"], targetMuscles: ["Back"], isAnchor: false, setsOverride: 3, repsMinOverride: 10, repsMaxOverride: 12, restOverride: 45, notes: nil),
                    .init(role: .accessory, targetBundles: ["core_flexion_bundle"], targetMuscles: ["Core"], isAnchor: false, setsOverride: 3, repsMinOverride: 15, repsMaxOverride: 20, restOverride: 30, notes: nil),
                ], hasFinisher: false, supersetPairs: [[0, 2]]),
            
            DaySplitTemplate(dayOfWeek: 7, name: "Rest / Long Walk",
                primaryMuscles: [], secondaryMuscles: [],
                isRestDay: true, exerciseSlots: [], hasFinisher: false, supersetPairs: nil),
        ]
        
        return MasterProgramTemplate(
            id: "90_day_lean",
            name: "90-Day Lean (Recomp)",
            description: "Premium 3-block recomposition program. Block 1: strength anchors + conditioning habit. Block 2: volume density with more supersets. Block 3: peak leanness—maintain strength, raise output. Your transformation program.",
            goal: .lean, duration: .threeMonths, daysPerWeek: 5,
            icon: "flame.fill", color: "red",
            difficulty: "Intermediate",
            blocks: blocks,
            weeklySchedule: schedule,
            weeklyPatternCoverage: ["squat", "hinge", "horizontal_press", "horizontal_pull", "vertical_pull"],
            exerciseSwapPercentage: 0.5,
            benefits: ["3-phase transformation", "Keep strength while leaning", "Progressive conditioning", "Evidence-based periodization", "Real trainer feel"],
            warmupSuggestion: "5 min light cardio + movement prep",
            tags: ["lean", "90-day", "periodized", "recomp", "premium"]
        )
    }
    
    // MARK: - Helpers
    
    /// Get the active periodization block for a given week number
    func getActiveBlock(for weekNumber: Int, in template: MasterProgramTemplate) -> PeriodizationBlock? {
        return template.blocks.first { weekNumber >= $0.weekStart && weekNumber <= $0.weekEnd }
    }
    
    /// Check if a given week is a deload week
    func isDeloadWeek(_ weekNumber: Int, in template: MasterProgramTemplate) -> Bool {
        guard let block = getActiveBlock(for: weekNumber, in: template) else { return false }
        return block.deloadWeek == weekNumber
    }
    
    /// Get sets/reps for a given exercise slot based on the active block
    func getPrescription(
        for slot: DaySplitTemplate.ExerciseSlot,
        block: PeriodizationBlock,
        isDeload: Bool
    ) -> (sets: Int, repsMin: Int, repsMax: Int, rest: Int) {
        let isCompound = slot.role == .primaryCompound || slot.role == .secondaryCompound
        
        var sets = slot.setsOverride ?? (isCompound ? block.primarySets : block.accessorySets)
        var repsMin = slot.repsMinOverride ?? (isCompound ? block.primaryRepsMin : block.accessoryRepsMin)
        var repsMax = slot.repsMaxOverride ?? (isCompound ? block.primaryRepsMax : block.accessoryRepsMax)
        var rest = slot.restOverride ?? (isCompound ? block.primaryRestSeconds : block.accessoryRestSeconds)
        
        // Deload adjustments: reduce sets 30-40%, keep movement patterns
        if isDeload {
            sets = max(2, Int(Double(sets) * 0.65))
            rest = max(60, rest - 30)
        }
        
        return (sets, repsMin, repsMax, rest)
    }
}

// MARK: - Warm-Up Suggestions

struct WarmUpSuggestion {
    let name: String
    let description: String
    let durationMinutes: Int
    
    /// Generate a warm-up suggestion based on the day's focus muscles
    static func forDay(_ dayTemplate: DaySplitTemplate) -> WarmUpSuggestion {
        let muscles = dayTemplate.primaryMuscles.map { $0.lowercased() }
        
        let hasLower = muscles.contains { $0.contains("quad") || $0.contains("ham") || $0.contains("glute") || $0.contains("leg") || $0.contains("calf") }
        let hasUpper = muscles.contains { $0.contains("chest") || $0.contains("back") || $0.contains("shoulder") || $0.contains("lat") || $0.contains("bicep") || $0.contains("tricep") }
        
        if hasLower && hasUpper {
            return WarmUpSuggestion(
                name: "Full Body Warm-Up",
                description: "5 min light cardio → arm circles × 10 each → leg swings × 10 each → bodyweight squats × 10 → push-ups × 5 → hip circles × 10",
                durationMinutes: 5
            )
        } else if hasLower {
            return WarmUpSuggestion(
                name: "Lower Body Warm-Up",
                description: "5 min incline walk or bike → hip circles × 10 → leg swings × 10 each → bodyweight squats × 10 → walking lunges × 5 each → glute bridges × 10",
                durationMinutes: 5
            )
        } else {
            return WarmUpSuggestion(
                name: "Upper Body Warm-Up",
                description: "3-5 min light cardio → arm circles × 10 each → band pull-aparts × 15 → push-ups × 5-10 → light set of first exercise",
                durationMinutes: 5
            )
        }
    }
}
