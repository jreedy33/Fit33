import Foundation
import SwiftUI
import CoreData

// MARK: - Program Start Service
// Converts ExtendedProgram to WorkoutProgram and generates days

class ProgramStartService: ObservableObject {
    static let shared = ProgramStartService()
    
    @Published var isStarting = false
    @Published var currentProgram: ExtendedProgram?
    @Published var generatedDays: [GeneratedProgramDay] = []
    
    private init() {}
    
    // MARK: - Convert ExtendedProgram to WorkoutProgram
    
    func convertToWorkoutProgram(_ program: ExtendedProgram, customizations: ProgramCustomization? = nil) -> WorkoutProgram {
        let duration = customizations?.duration ?? program.duration
        let frequency = customizations?.frequency ?? program.frequency.rawValue
        let equipment = customizations?.equipment ?? Set(program.equipment)
        
        // Generate schedule based on program type
        let schedule = generateSchedule(
            for: program,
            duration: duration.days,
            frequency: frequency,
            equipment: Array(equipment)
        )
        
        // Determine rest days
        let restDays = calculateRestDays(duration: duration.days, frequency: frequency)
        
        return WorkoutProgram(
            id: program.id,
            name: program.name,
            description: program.description,
            duration: duration.days,
            difficulty: program.difficulty,
            focus: mapGoalToFocus(program.primaryGoal),
            schedule: schedule,
            restDays: restDays,
            icon: program.icon,
            color: program.gradientColors.first ?? "#6366f1",
            workoutsPerWeek: frequency,
            estimatedTimePerWorkout: customizations?.workoutLength ?? program.avgWorkoutMinutes,
            equipment: Array(equipment),
            benefits: program.benefits,
            preview: program.preview
        )
    }
    
    // MARK: - Generate Schedule
    
    private func generateSchedule(
        for program: ExtendedProgram,
        duration: Int,
        frequency: Int,
        equipment: [String]
    ) -> [Int: ProgramDay] {
        var schedule: [Int: ProgramDay] = [:]
        
        // Get the split type to determine daily focus
        let dailyFocusPattern = getDailyFocusPattern(for: program.split, frequency: frequency)
        
        var workoutDayIndex = 0
        for day in 1...duration {
            // Check if this is a workout day or rest day
            let isRestDay = isRestDayForSchedule(day: day, frequency: frequency, duration: duration)
            
            if !isRestDay && workoutDayIndex < dailyFocusPattern.count {
                let focusInfo = dailyFocusPattern[workoutDayIndex % dailyFocusPattern.count]
                
                let programDay = ProgramDay(
                    dayNumber: day,
                    name: focusInfo.name,
                    focus: focusInfo.muscles,
                    exerciseCount: calculateExerciseCount(for: focusInfo, duration: program.avgWorkoutMinutes),
                    intensity: getIntensityForDay(workoutDayIndex, totalDays: duration),
                    workoutTemplate: WorkoutTemplate(name: focusInfo.name, exercises: []),
                    equipment: equipment
                )
                
                schedule[day] = programDay
                workoutDayIndex += 1
            }
        }
        
        return schedule
    }
    
    // MARK: - Daily Focus Patterns Based on Split
    
    private func getDailyFocusPattern(for split: TrainingSplit, frequency: Int) -> [DayFocusInfo] {
        switch split {
        case .fullBody:
            return [
                DayFocusInfo(name: "Full Body A", muscles: ["Chest", "Back", "Legs", "Shoulders"]),
                DayFocusInfo(name: "Full Body B", muscles: ["Back", "Chest", "Legs", "Arms"]),
                DayFocusInfo(name: "Full Body C", muscles: ["Legs", "Back", "Chest", "Core"])
            ]
            
        case .upperLower:
            return [
                DayFocusInfo(name: "Upper Body", muscles: ["Chest", "Back", "Shoulders", "Arms"]),
                DayFocusInfo(name: "Lower Body", muscles: ["Quadriceps", "Hamstrings", "Glutes", "Calves"]),
                DayFocusInfo(name: "Upper Body", muscles: ["Back", "Chest", "Shoulders", "Triceps"]),
                DayFocusInfo(name: "Lower Body", muscles: ["Glutes", "Hamstrings", "Quadriceps", "Core"])
            ]
            
        case .pushPullLegs:
            return [
                DayFocusInfo(name: "Push Day", muscles: ["Chest", "Shoulders", "Triceps"]),
                DayFocusInfo(name: "Pull Day", muscles: ["Back", "Biceps", "Rear Delts"]),
                DayFocusInfo(name: "Leg Day", muscles: ["Quadriceps", "Hamstrings", "Glutes", "Calves"]),
                DayFocusInfo(name: "Push Day", muscles: ["Shoulders", "Chest", "Triceps"]),
                DayFocusInfo(name: "Pull Day", muscles: ["Lats", "Traps", "Biceps"]),
                DayFocusInfo(name: "Leg Day", muscles: ["Hamstrings", "Glutes", "Quadriceps", "Core"])
            ]
            
        case .bro:
            return [
                DayFocusInfo(name: "Chest Day", muscles: ["Chest"]),
                DayFocusInfo(name: "Back Day", muscles: ["Back", "Lats", "Traps"]),
                DayFocusInfo(name: "Shoulder Day", muscles: ["Shoulders", "Rear Delts"]),
                DayFocusInfo(name: "Arm Day", muscles: ["Biceps", "Triceps", "Forearms"]),
                DayFocusInfo(name: "Leg Day", muscles: ["Quadriceps", "Hamstrings", "Glutes", "Calves"])
            ]
            
        case .arnoldSplit:
            return [
                DayFocusInfo(name: "Chest & Back", muscles: ["Chest", "Back"]),
                DayFocusInfo(name: "Shoulders & Arms", muscles: ["Shoulders", "Biceps", "Triceps"]),
                DayFocusInfo(name: "Legs", muscles: ["Quadriceps", "Hamstrings", "Glutes", "Calves"]),
                DayFocusInfo(name: "Chest & Back", muscles: ["Back", "Chest"]),
                DayFocusInfo(name: "Shoulders & Arms", muscles: ["Shoulders", "Triceps", "Biceps"]),
                DayFocusInfo(name: "Legs", muscles: ["Glutes", "Hamstrings", "Quadriceps"])
            ]
            
        case .phat, .phul:
            return [
                DayFocusInfo(name: "Upper Power", muscles: ["Chest", "Back", "Shoulders"]),
                DayFocusInfo(name: "Lower Power", muscles: ["Quadriceps", "Hamstrings", "Glutes"]),
                DayFocusInfo(name: "Back & Shoulders", muscles: ["Back", "Shoulders", "Rear Delts"]),
                DayFocusInfo(name: "Lower Hypertrophy", muscles: ["Quadriceps", "Hamstrings", "Glutes", "Calves"]),
                DayFocusInfo(name: "Chest & Arms", muscles: ["Chest", "Triceps", "Biceps"])
            ]
            
        case .custom:
            // For custom splits, use a general approach based on frequency
            return generateCustomSplitPattern(frequency: frequency)
        }
    }
    
    private func generateCustomSplitPattern(frequency: Int) -> [DayFocusInfo] {
        switch frequency {
        case 2:
            return [
                DayFocusInfo(name: "Full Body A", muscles: ["Chest", "Back", "Legs"]),
                DayFocusInfo(name: "Full Body B", muscles: ["Shoulders", "Arms", "Core"])
            ]
        case 3:
            return [
                DayFocusInfo(name: "Push", muscles: ["Chest", "Shoulders", "Triceps"]),
                DayFocusInfo(name: "Pull", muscles: ["Back", "Biceps"]),
                DayFocusInfo(name: "Legs", muscles: ["Quadriceps", "Hamstrings", "Glutes"])
            ]
        case 4:
            return [
                DayFocusInfo(name: "Upper Body", muscles: ["Chest", "Back", "Shoulders"]),
                DayFocusInfo(name: "Lower Body", muscles: ["Quadriceps", "Hamstrings", "Glutes"]),
                DayFocusInfo(name: "Push", muscles: ["Chest", "Shoulders", "Triceps"]),
                DayFocusInfo(name: "Pull & Legs", muscles: ["Back", "Biceps", "Hamstrings"])
            ]
        default:
            return [
                DayFocusInfo(name: "Chest & Triceps", muscles: ["Chest", "Triceps"]),
                DayFocusInfo(name: "Back & Biceps", muscles: ["Back", "Biceps"]),
                DayFocusInfo(name: "Legs", muscles: ["Quadriceps", "Hamstrings", "Glutes"]),
                DayFocusInfo(name: "Shoulders", muscles: ["Shoulders", "Rear Delts"]),
                DayFocusInfo(name: "Arms & Core", muscles: ["Biceps", "Triceps", "Core"])
            ]
        }
    }
    
    // MARK: - Helpers
    
    private func isRestDayForSchedule(day: Int, frequency: Int, duration: Int) -> Bool {
        // Distribute rest days evenly throughout the week
        let daysPerWeek = 7
        let restDaysPerWeek = daysPerWeek - frequency
        
        if restDaysPerWeek <= 0 { return false }
        
        let dayOfWeek = ((day - 1) % daysPerWeek) + 1
        
        // Common rest day patterns
        switch frequency {
        case 3: return [2, 4, 7].contains(dayOfWeek) // Rest on Tue, Thu, Sun
        case 4: return [3, 5, 7].contains(dayOfWeek) // Rest on Wed, Fri, Sun
        case 5: return [4, 7].contains(dayOfWeek) // Rest on Thu, Sun
        case 6: return [7].contains(dayOfWeek) // Rest on Sun only
        default: return false
        }
    }
    
    private func calculateRestDays(duration: Int, frequency: Int) -> Set<Int> {
        var restDays: Set<Int> = []
        for day in 1...duration {
            if isRestDayForSchedule(day: day, frequency: frequency, duration: duration) {
                restDays.insert(day)
            }
        }
        return restDays
    }
    
    private func calculateExerciseCount(for focus: DayFocusInfo, duration: Int) -> Int {
        // Estimate exercise count based on workout duration
        let exercisesPerMinute = 0.15 // ~6-7 exercises per 45 min workout
        let baseCount = Int(Double(duration) * exercisesPerMinute)
        return max(4, min(8, baseCount))
    }
    
    private func getIntensityForDay(_ dayIndex: Int, totalDays: Int) -> DayIntensity {
        // Every 4th week is a deload
        let weekNumber = (dayIndex / 7) + 1
        if weekNumber % 4 == 0 {
            return .deload
        }
        
        // Alternate between moderate and heavy
        return dayIndex % 3 == 0 ? .heavy : .moderate
    }
    
    private func mapGoalToFocus(_ goal: ProgramGoal) -> ProgramFocus {
        switch goal {
        case .buildMuscle, .bodybuilding: return .hypertrophy
        case .gainStrength, .powerlifting: return .strength
        case .loseWeight, .toneUp: return .endurance
        case .improveEndurance: return .endurance
        case .athletic: return .athletic
        case .flexibility: return .bodyweight
        case .generalFitness: return .fullBody
        }
    }
    
    // MARK: - Start Program
    
    func startProgram(_ program: ExtendedProgram, customizations: ProgramCustomization? = nil, workoutManager: WorkoutManager) {
        isStarting = true
        currentProgram = program
        
        // Convert to WorkoutProgram
        let workoutProgram = convertToWorkoutProgram(program, customizations: customizations)
        
        // Start the program using existing WorkoutManager
        workoutManager.startProgram(workoutProgram)
        
        isStarting = false
    }
}

// MARK: - Supporting Types

struct DayFocusInfo {
    let name: String
    let muscles: [String]
}

struct GeneratedProgramDay: Identifiable {
    let id = UUID()
    let dayNumber: Int
    let name: String
    let focus: [String]
    let exercises: [ExerciseData]
    let isRestDay: Bool
    let intensity: DayIntensity
}

struct ProgramCustomization {
    var duration: ProgramDuration
    var frequency: Int
    var location: ProgramLocation
    var workoutLength: Int
    var equipment: Set<String>
    var includeDeloadWeeks: Bool
}


