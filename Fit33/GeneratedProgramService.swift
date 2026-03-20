import Foundation
import CoreData
import SwiftUI

// MARK: - Generated Program Service
/// Manages dynamically generated programs - creation, storage, and progression

class GeneratedProgramService: ObservableObject {
    static let shared = GeneratedProgramService()
    
    private let storageKey = "generatedPrograms"
    private let activeKey = "activeGeneratedProgram"
    
    @Published private(set) var generatedPrograms: [DynamicProgramGenerator.GeneratedProgram] = []
    @Published private(set) var activeProgram: DynamicProgramGenerator.GeneratedProgram?
    @Published private(set) var currentDay: DynamicProgramGenerator.GeneratedProgramDay?
    @Published private(set) var isGenerating = false
    
    private init() {
        loadPrograms()
    }
    
    // MARK: - Program Generation
    
    /// Generate programs for a user after onboarding
    func generateProgramsForUser(_ user: User) async -> [DynamicProgramGenerator.GeneratedProgram] {
        await MainActor.run { isGenerating = true }
        
        let profile = DynamicProgramGenerator.shared.createProfileFromUser(user)
        let programs = DynamicProgramGenerator.shared.generatePersonalizedPrograms(for: profile)
        
        await MainActor.run {
            self.generatedPrograms = programs
            self.isGenerating = false
            self.savePrograms()
        }
        
        print("✅ Generated \(programs.count) programs for user")
        return programs
    }
    
    /// Regenerate programs (if user changes profile)
    func regeneratePrograms(for user: User) async {
        _ = await generateProgramsForUser(user)
    }
    
    // MARK: - Program Activation
    
    /// Start a program
    func startProgram(_ program: DynamicProgramGenerator.GeneratedProgram) {
        if let currentActive = activeProgram,
           let index = generatedPrograms.firstIndex(where: { $0.id == currentActive.id }) {
            var updated = generatedPrograms[index]
            updated.isActive = false
            generatedPrograms[index] = updated
        }
        
        // Activate new program
        activeProgram = program
        
        // Set current day to first available
        if let firstDay = program.generatedDays.first(where: { !$0.isCompleted }) {
            currentDay = firstDay
        } else {
            currentDay = program.generatedDays.first
        }
        
        savePrograms()
        saveActiveProgram()
        
        print("🏋️ Started program: \(program.name)")
    }
    
    /// Stop current program
    func stopCurrentProgram() {
        activeProgram = nil
        currentDay = nil
        UserDefaults.standard.removeObject(forKey: activeKey)
        
        print("⏹️ Stopped current program")
    }
    
    // MARK: - Day Progression
    
    /// Get today's workout
    func getTodaysWorkout() -> DynamicProgramGenerator.GeneratedProgramDay? {
        guard let program = activeProgram else { return nil }
        
        // Find first incomplete day
        return program.generatedDays.first { !$0.isCompleted }
    }
    
    /// Complete a day and generate the next
    func completeDay(_ day: DynamicProgramGenerator.GeneratedProgramDay, completedExercises: [String]) {
        guard var program = activeProgram else { return }
        guard let user = UserManager.shared.currentUser else { return }
        
        // Mark day as completed
        if let index = program.generatedDays.firstIndex(where: { $0.id == day.id }) {
            var completedDay = program.generatedDays[index]
            // Create new day with completed status (structs are immutable)
            let updatedDay = DynamicProgramGenerator.GeneratedProgramDay(
                id: completedDay.id,
                dayNumber: completedDay.dayNumber,
                weekNumber: completedDay.weekNumber,
                name: completedDay.name,
                focusMuscles: completedDay.focusMuscles,
                exercises: completedDay.exercises,
                estimatedDuration: completedDay.estimatedDuration,
                intensity: completedDay.intensity,
                isCompleted: true,
                completedAt: Date(),
                notes: completedDay.notes
            )
            program.generatedDays[index] = updatedDay
        }
        
        // Record workout for recovery tracking
        ProgramMuscleRecoveryTracker.shared.recordWorkoutFromExercises(day.exercises)
        
        // Update daily quest progress for program day completion
        Task { @MainActor in
            await DailyQuestService.shared.onProgramDayCompleted()
        }
        
        // Check if program is complete
        let totalDays = program.durationWeeks * program.daysPerWeek
        let completedDays = program.generatedDays.filter { $0.isCompleted }.count
        let isProgramComplete = completedDays >= totalDays
        
        if isProgramComplete {
            print("🎉 Program '\(program.name)' COMPLETED!")
            // Generate sequel/continuation program
            Task {
                await generateSequelProgram(for: program, user: user)
            }
        } else {
            // Generate next day
            let profile = DynamicProgramGenerator.shared.createProfileFromUser(user)
            if let nextDay = DynamicProgramGenerator.shared.generateNextDay(
                for: &program,
                profile: profile,
                completedExercises: completedExercises
            ) {
                currentDay = nextDay
                print("✅ Generated Day \(nextDay.dayNumber): \(nextDay.name)")
            }
        }
        
        // Update stored program
        activeProgram = program
        if let index = generatedPrograms.firstIndex(where: { $0.id == program.id }) {
            generatedPrograms[index] = program
        }
        
        savePrograms()
        saveActiveProgram()
    }
    
    /// Skip to a specific day
    func skipToDay(_ dayNumber: Int) {
        guard let program = activeProgram else { return }
        
        if let day = program.generatedDays.first(where: { $0.dayNumber == dayNumber }) {
            currentDay = day
        }
    }
    
    // MARK: - Sequel Program Generation
    
    /// Generate a sequel/continuation program when user completes one
    /// Creates a progression program that builds on completed work
    private func generateSequelProgram(for completedProgram: DynamicProgramGenerator.GeneratedProgram, user: User) async {
        print("🎬 Generating sequel program for '\(completedProgram.name)'")
        
        let profile = DynamicProgramGenerator.shared.createProfileFromUser(user)
        
        // Create sequel name (e.g., "Muscle Builder II", "Advanced Mass Maker")
        let sequelName = generateSequelName(from: completedProgram.name)
        
        // Generate new program with increased difficulty or focus
        if let newProgram = DynamicProgramGenerator.shared.generateSequelProgram(
            previousProgram: completedProgram,
            profile: profile,
            sequelName: sequelName
        ) {
            await MainActor.run {
                generatedPrograms.append(newProgram)
                savePrograms()
                print("✅ Created sequel: '\(newProgram.name)'")
            }
        }
    }
    
    private func generateSequelName(from originalName: String) -> String {
        // Remove existing progression markers
        var baseName = originalName
            .replacingOccurrences(of: " II", with: "")
            .replacingOccurrences(of: " III", with: "")
            .replacingOccurrences(of: " IV", with: "")
            .replacingOccurrences(of: "Advanced ", with: "")
            .replacingOccurrences(of: "Intermediate ", with: "")
        
        // Add progression marker
        let progressionNames = [
            "Advanced \(baseName)",
            "\(baseName) II",
            "\(baseName) - Next Level",
            "\(baseName) Pro",
            "\(baseName) Evolution"
        ]
        
        return progressionNames.randomElement() ?? "\(baseName) II"
    }
    
    // MARK: - Program Progress
    
    /// Get completion percentage
    func getCompletionPercentage() -> Double {
        guard let program = activeProgram else { return 0 }
        
        let completed = program.generatedDays.filter { $0.isCompleted }.count
        let total = program.durationWeeks * program.daysPerWeek
        
        return Double(completed) / Double(total) * 100
    }
    
    /// Get days remaining
    func getDaysRemaining() -> Int {
        guard let program = activeProgram else { return 0 }
        
        let total = program.durationWeeks * program.daysPerWeek
        let completed = program.generatedDays.filter { $0.isCompleted }.count
        
        return total - completed
    }
    
    /// Get current week number
    func getCurrentWeek() -> Int {
        guard let current = currentDay else { return 1 }
        return current.weekNumber
    }
    
    // MARK: - Exercise Management
    
    /// Swap an exercise in a day
    func swapExercise(
        in day: DynamicProgramGenerator.GeneratedProgramDay,
        exerciseId: String,
        with newExercise: Exercise
    ) {
        guard var program = activeProgram else { return }
        guard let dayIndex = program.generatedDays.firstIndex(where: { $0.id == day.id }) else { return }
        
        var exercises = program.generatedDays[dayIndex].exercises
        if let exerciseIndex = exercises.firstIndex(where: { $0.id == exerciseId }) {
            let oldExercise = exercises[exerciseIndex]
            
            let swapped = DynamicProgramGenerator.GeneratedExercise(
                id: UUID().uuidString,
                exerciseName: newExercise.name ?? "Exercise",
                exerciseId: newExercise.id,
                order: oldExercise.order,
                sets: oldExercise.sets,
                repsMin: oldExercise.repsMin,
                repsMax: oldExercise.repsMax,
                restSeconds: oldExercise.restSeconds,
                targetRPE: oldExercise.targetRPE,
                notes: nil,
                isWarmup: oldExercise.isWarmup,
                supersetGroup: oldExercise.supersetGroup,
                isAnchor: oldExercise.isAnchor,
                movementPattern: oldExercise.movementPattern
            )
            
            exercises[exerciseIndex] = swapped
            
            // Recreate day with updated exercises
            let updatedDay = DynamicProgramGenerator.GeneratedProgramDay(
                id: day.id,
                dayNumber: day.dayNumber,
                weekNumber: day.weekNumber,
                name: day.name,
                focusMuscles: day.focusMuscles,
                exercises: exercises,
                estimatedDuration: day.estimatedDuration,
                intensity: day.intensity,
                isCompleted: day.isCompleted,
                completedAt: day.completedAt,
                notes: day.notes
            )
            
            program.generatedDays[dayIndex] = updatedDay
            activeProgram = program
            currentDay = updatedDay
            
            // Update in array
            if let programIndex = generatedPrograms.firstIndex(where: { $0.id == program.id }) {
                generatedPrograms[programIndex] = program
            }
            
            savePrograms()
            saveActiveProgram()
        }
    }
    
    // MARK: - Convert to Core Data Workout
    
    /// Convert generated day to Core Data workout for active workout screen
    func createWorkout(from day: DynamicProgramGenerator.GeneratedProgramDay, context: NSManagedObjectContext) -> (Workout, [Exercise]) {
        let workout = Workout(context: context)
        workout.id = UUID()
        workout.name = day.name
        workout.date = Date()
        workout.duration = 0
        workout.isCompleted = false
        
        // Find matching Core Data exercises
        let allExercises = ExerciseLibraryService.shared.getAllExercises()
        var workoutExercises: [Exercise] = []
        
        for genExercise in day.exercises {
            // Try to find by ID first, then by name
            if let exerciseId = genExercise.exerciseId,
               let exercise = allExercises.first(where: { $0.id == exerciseId }) {
                workoutExercises.append(exercise)
            } else if let exercise = allExercises.first(where: { 
                $0.name?.lowercased() == genExercise.exerciseName.lowercased() 
            }) {
                workoutExercises.append(exercise)
            } else {
                // Create a temporary exercise if not found
                let tempExercise = Exercise(context: context)
                tempExercise.id = UUID()
                tempExercise.name = genExercise.exerciseName
                tempExercise.category = "Generated"
                workoutExercises.append(tempExercise)
            }
        }
        
        return (workout, workoutExercises)
    }
    
    // MARK: - Persistence
    
    private func savePrograms() {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(generatedPrograms) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
    
    private func loadPrograms() {
        let decoder = JSONDecoder()
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let programs = try? decoder.decode([DynamicProgramGenerator.GeneratedProgram].self, from: data) {
            generatedPrograms = programs
        }
        
        loadActiveProgram()
    }
    
    private func saveActiveProgram() {
        guard let program = activeProgram else { return }
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(program) {
            UserDefaults.standard.set(data, forKey: activeKey)
        }
        if let day = currentDay, let dayData = try? encoder.encode(day) {
            UserDefaults.standard.set(dayData, forKey: "\(activeKey)_currentDay")
        }
    }
    
    private func loadActiveProgram() {
        let decoder = JSONDecoder()
        if let data = UserDefaults.standard.data(forKey: activeKey),
           let program = try? decoder.decode(DynamicProgramGenerator.GeneratedProgram.self, from: data) {
            activeProgram = program
        }
        if let dayData = UserDefaults.standard.data(forKey: "\(activeKey)_currentDay"),
           let day = try? decoder.decode(DynamicProgramGenerator.GeneratedProgramDay.self, from: dayData) {
            currentDay = day
        }
    }
    
    /// Clear all generated programs
    func clearAllPrograms() {
        generatedPrograms = []
        activeProgram = nil
        currentDay = nil
        UserDefaults.standard.removeObject(forKey: storageKey)
        UserDefaults.standard.removeObject(forKey: activeKey)
        UserDefaults.standard.removeObject(forKey: "\(activeKey)_currentDay")
        print("🗑️ Cleared all generated programs")
    }
    
    /// Delete a specific program
    func deleteProgram(_ program: DynamicProgramGenerator.GeneratedProgram) {
        generatedPrograms.removeAll { $0.id == program.id }
        
        if activeProgram?.id == program.id {
            activeProgram = nil
            currentDay = nil
        }
        
        savePrograms()
    }
}

// MARK: - Program Card View Model

extension GeneratedProgramService {
    
    struct ProgramDisplayInfo {
        let program: DynamicProgramGenerator.GeneratedProgram
        let completedDays: Int
        let totalDays: Int
        let currentWeek: Int
        let isActive: Bool
        let nextWorkoutName: String?
        
        var progressPercentage: Double {
            guard totalDays > 0 else { return 0 }
            return Double(completedDays) / Double(totalDays) * 100
        }
        
        var progressText: String {
            "\(completedDays) / \(totalDays) days"
        }
    }
    
    func getDisplayInfo(for program: DynamicProgramGenerator.GeneratedProgram) -> ProgramDisplayInfo {
        let completed = program.generatedDays.filter { $0.isCompleted }.count
        let total = program.durationWeeks * program.daysPerWeek
        let currentWeek = ((completed / max(1, program.daysPerWeek)) + 1)
        let isActive = activeProgram?.id == program.id
        let nextWorkout = program.generatedDays.first { !$0.isCompleted }?.name
        
        return ProgramDisplayInfo(
            program: program,
            completedDays: completed,
            totalDays: total,
            currentWeek: currentWeek,
            isActive: isActive,
            nextWorkoutName: nextWorkout
        )
    }
}

// MARK: - SwiftUI Views for Generated Programs

struct GeneratedProgramCard: View {
    let displayInfo: GeneratedProgramService.ProgramDisplayInfo
    let onStart: () -> Void
    @Environment(\.colorScheme) var colorScheme
    
    private var programColor: Color {
        switch displayInfo.program.color {
        case "blue": return .blue
        case "red": return .red
        case "orange": return .orange
        case "purple": return .purple
        case "green": return .green
        case "yellow": return .yellow
        default: return .blue
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: displayInfo.program.icon)
                    .font(.title2)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [programColor, programColor.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(displayInfo.program.name)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text(displayInfo.program.splitType.rawValue)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if displayInfo.isActive {
                    Text("ACTIVE")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.horizontal, Spacing.xs)
                        .padding(.vertical, Spacing.xxs)
                        .background(programColor)
                        .clipShape(Capsule())
                }
            }
            
            // Description
            Text(displayInfo.program.description)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)
            
            // Stats
            HStack(spacing: 16) {
                ProgramStatBadge(icon: "calendar", text: "\(displayInfo.program.daysPerWeek)x/week")
                ProgramStatBadge(icon: "clock", text: "\(displayInfo.program.durationWeeks) weeks")
                ProgramStatBadge(icon: "flame", text: displayInfo.program.difficulty)
            }
            
            // Progress (if active)
            if displayInfo.isActive {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Progress")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(displayInfo.progressText)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.gray.opacity(0.2))
                                .frame(height: 6)
                            
                            RoundedRectangle(cornerRadius: 4)
                                .fill(
                                    LinearGradient(
                                        colors: [programColor, programColor.opacity(0.7)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: geo.size.width * displayInfo.progressPercentage / 100, height: 6)
                        }
                    }
                    .frame(height: 6)
                }
                
                if let nextWorkout = displayInfo.nextWorkoutName {
                    Text("Next: \(nextWorkout)")
                        .font(.caption)
                        .foregroundColor(programColor)
                }
            }
            
            // Start button
            if !displayInfo.isActive {
                Button(action: onStart) {
                    Text("Start Program")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            LinearGradient(
                                colors: [programColor, programColor.opacity(0.8)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.lg)
                .fill(Color.cardBackground)
                .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
        )
    }
}

struct ProgramStatBadge: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text(text)
                .font(.caption)
        }
        .foregroundColor(.secondary)
    }
}

// MARK: - Generated Programs List View

struct GeneratedProgramsListView: View {
    @ObservedObject var service = GeneratedProgramService.shared
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                if service.isGenerating {
                    ProgressView("Generating your personalized programs...")
                        .padding()
                } else if service.generatedPrograms.isEmpty {
                    EmptyProgramsView()
                } else {
                    ForEach(service.generatedPrograms) { program in
                        GeneratedProgramCard(
                            displayInfo: service.getDisplayInfo(for: program),
                            onStart: {
                                service.startProgram(program)
                            }
                        )
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Your Programs")
    }
}

struct EmptyProgramsView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.system(size: 50))
                .foregroundColor(.blue)
            
            Text("No Programs Yet")
                .font(.headline)
            
            Text("Complete onboarding to get personalized workout programs tailored just for you!")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(Spacing.xl)
    }
}

// Preview provider
#if DEBUG
struct GeneratedProgramsListView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            GeneratedProgramsListView()
        }
    }
}
#endif

