import SwiftUI
import CoreData

struct ProgramScheduleView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var workoutManager: WorkoutManager
    
    let program: WorkoutProgram
    @State private var selectedDay: Int? = nil
    @State private var showingWorkoutPreview = false
    @State private var showingCancelAlert = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Compact program header
                compactProgramHeader
                
                // Days grid
                daysGridSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 60)
        }
        .background(
            LinearGradient(
                gradient: Gradient(colors: [programColor.opacity(0.3), programColor.opacity(0.1), Color.white]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(.all, edges: .all)
        )
        .navigationTitle(program.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button(role: .destructive) {
                        showCancelProgramAlert()
                    } label: {
                        Label("Cancel Program", systemImage: "xmark.circle")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .foregroundColor(programColor)
                }
            }
        }
        .alert("Cancel Program", isPresented: $showingCancelAlert) {
            Button("Cancel", role: .cancel) {}
            Button("End Program", role: .destructive) {
                cancelProgram()
            }
        } message: {
            Text("Are you sure you want to cancel this program? Your progress will be lost.")
        }
    }
    
    private var compactProgramHeader: some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                // Icon
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [programColor, programColor.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 50, height: 50)
                        .shadow(color: programColor.opacity(0.2), radius: 4, x: 0, y: 2)
                    
                    Image(systemName: program.icon)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.white)
                }
                
                // Info
                VStack(alignment: .leading, spacing: 4) {
                    Text("Day \(workoutManager.currentProgramDay) of \(program.duration)")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(programColor)
                    
                    Text("\(workoutManager.programCompletedDays.count) workouts completed")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            
            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.gray.opacity(0.15))
                        .frame(height: 8)
                    
                    RoundedRectangle(cornerRadius: 6)
                        .fill(
                            LinearGradient(
                                colors: [programColor, programColor.opacity(0.7)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geometry.size.width * workoutManager.programProgress, height: 8)
                        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: workoutManager.programProgress)
                }
            }
            .frame(height: 8)
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
    }
    
    private var daysGridSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Workout Schedule")
                .font(.headline)
                .fontWeight(.bold)
                .padding(.horizontal, 4)
            
            // Grid layout for day tiles
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ], spacing: 12) {
                ForEach(1...program.duration, id: \.self) { day in
                    if day <= workoutManager.currentProgramDay && !program.restDays.contains(day) {
                        NavigationLink(destination: WorkoutPreviewView(
                            program: program,
                            day: day,
                            programColor: programColor
                        ).environmentObject(workoutManager)) {
                            DayTileContent(
                                day: day,
                                programDay: program.schedule[day],
                                isRestDay: program.restDays.contains(day),
                                isCompleted: workoutManager.programCompletedDays.contains(day),
                                isUnlocked: day <= workoutManager.currentProgramDay,
                                programColor: programColor
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    } else {
                        DayTile(
                            day: day,
                            programDay: program.schedule[day],
                            isRestDay: program.restDays.contains(day),
                            isCompleted: workoutManager.programCompletedDays.contains(day),
                            isUnlocked: day <= workoutManager.currentProgramDay,
                            programColor: programColor
                        ) {
                            // No action for locked/rest days
                        }
                    }
                }
            }
        }
    }
    
    private var programColor: Color {
        switch program.color {
        case "blue": return .blue
        case "purple": return .purple
        case "orange": return .orange
        case "red": return .red
        case "green": return .green
        case "cyan": return .cyan
        case "indigo": return .indigo
        case "pink": return .pink
        default: return .blue
        }
    }
    
    private func handleDayTap(_ day: Int) {
        guard day <= workoutManager.currentProgramDay else { return }
        guard !program.restDays.contains(day) else { return }
        selectedDay = day
    }
    
    private func startWorkoutForDay(_ day: Int) {
        selectedDay = nil
        workoutManager.startProgramWorkout(day: day, context: viewContext)
        dismiss()
    }
    
    private func showCancelProgramAlert() {
        showingCancelAlert = true
    }
    
    private func cancelProgram() {
        workoutManager.cancelProgram()
        dismiss()
    }
}

// MARK: - Day Tile Component
struct DayTile: View {
    let day: Int
    let programDay: ProgramDay?
    let isRestDay: Bool
    let isCompleted: Bool
    let isUnlocked: Bool
    let programColor: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: {
            if isUnlocked && !isRestDay {
                action()
            }
        }) {
            DayTileContent(
                day: day,
                programDay: programDay,
                isRestDay: isRestDay,
                isCompleted: isCompleted,
                isUnlocked: isUnlocked,
                programColor: programColor
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct DayTileContent: View {
    let day: Int
    let programDay: ProgramDay?
    let isRestDay: Bool
    let isCompleted: Bool
    let isUnlocked: Bool
    let programColor: Color
    
    var body: some View {
            VStack(spacing: 6) {
                // Day badge
                ZStack {
                    Circle()
                        .fill(badgeColor)
                        .frame(width: 50, height: 50)
                    
                    if isCompleted {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundColor(.white)
                    } else if !isUnlocked {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.white)
                    } else if isRestDay {
                        Image(systemName: "moon.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.white)
                    } else {
                        VStack(spacing: 1) {
                            Text("Day")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(.white.opacity(0.9))
                            Text("\(day)")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }
                }
                
                // Day label
                if isRestDay {
                    Text("Rest")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                } else if let programDay = programDay {
                    Text(programDay.name)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                } else {
                    Text("Day \(day)")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                }
            }
            .frame(height: 95)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(cardBackgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(borderColor, lineWidth: 1.5)
            )
            .opacity(isUnlocked ? 1.0 : 0.6)
    }
    
    private var badgeColor: Color {
        if isCompleted {
            return programColor
        } else if !isUnlocked {
            return Color.gray.opacity(0.3)
        } else if isRestDay {
            return Color.gray.opacity(0.5)
        } else {
            return programColor.opacity(0.85)
        }
    }
    
    private var cardBackgroundColor: Color {
        if isRestDay {
            return Color.gray.opacity(0.05)
        } else if isCompleted {
            return programColor.opacity(0.08)
        } else {
            return Color.white
        }
    }
    
    private var borderColor: Color {
        if isRestDay {
            return Color.gray.opacity(0.2)
        } else if isCompleted {
            return programColor.opacity(0.4)
        } else if !isUnlocked {
            return Color.gray.opacity(0.2)
        } else {
            return programColor.opacity(0.3)
        }
    }
}

// MARK: - Workout Preview View
struct WorkoutPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject var workoutManager: WorkoutManager
    
    let program: WorkoutProgram
    let day: Int
    let programColor: Color
    
    @State private var generatedExercises: [ExerciseData] = []
    @State private var isGenerating = true
    
    private var programDay: ProgramDay? {
        program.schedule[day]
    }
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                gradient: Gradient(colors: [programColor.opacity(0.3), programColor.opacity(0.1), Color.white]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            if isGenerating {
                // Loading state
                VStack(spacing: 20) {
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(programColor)
                    
                    Text("Generating your workout...")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        // Compact Header
                        compactHeaderSection
                        
                        // Exercise list
                        if let programDay = programDay {
                            exerciseListSection(programDay: programDay)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 80) // Space for tab bar
                }
            }
        }
        .navigationTitle("Day \(day)")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            print("🎬 WORKOUT PREVIEW VIEW APPEARED - Day \(day)")
            generateWorkoutExercises()
            workoutManager.isOnWorkoutPreviewScreen = true
            workoutManager.previewProgram = program
            workoutManager.previewDay = day
        }
        .onDisappear {
            workoutManager.isOnWorkoutPreviewScreen = false
            workoutManager.previewProgram = nil
            workoutManager.previewDay = nil
            workoutManager.previewExercises = []
        }
        .onChange(of: workoutManager.shouldStartPreviewWorkout) { shouldStart in
            if shouldStart {
                startWorkoutWithGeneratedExercises()
                workoutManager.shouldStartPreviewWorkout = false
            }
        }
        .onAppear {
            if !generatedExercises.isEmpty {
                GoButtonState.shared.show(
                    primaryColor: programColor,
                    secondaryColor: programColor.opacity(0.7)
                ) { [self] in
                    startWorkoutWithGeneratedExercises()
                }
            }
        }
        .onChange(of: isGenerating) { stillGenerating in
            if !stillGenerating && !generatedExercises.isEmpty {
                GoButtonState.shared.show(
                    primaryColor: programColor,
                    secondaryColor: programColor.opacity(0.7)
                ) { [self] in
                    startWorkoutWithGeneratedExercises()
                }
            }
        }
        .onDisappear {
            GoButtonState.shared.hide()
        }
    }
    
    private var compactHeaderSection: some View {
        HStack(spacing: 14) {
            // Day badge
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [programColor, programColor.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 46, height: 46)
                
                VStack(spacing: 0) {
                    Text("Day")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundColor(.white.opacity(0.9))
                    Text("\(day)")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                }
            }
            
            if let programDay = programDay {
                VStack(alignment: .leading, spacing: 3) {
                    Text(programDay.name)
                        .font(.body)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    HStack(spacing: 10) {
                        HStack(spacing: 4) {
                            Image(systemName: "figure.strengthtraining.traditional")
                                .font(.system(size: 11))
                            Text("\(programDay.exerciseCount) exercises")
                                .font(.caption2)
                        }
                        
                        HStack(spacing: 4) {
                            Image(systemName: "flame.fill")
                                .font(.system(size: 11))
                            Text(programDay.intensity.rawValue)
                                .font(.caption2)
                        }
                    }
                    .foregroundColor(.secondary)
                }
            }
            
            Spacer()
        }
        .padding(14)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 3)
    }
    
    private func exerciseListSection(programDay: ProgramDay) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Today's Exercises")
                .font(.headline)
                .fontWeight(.bold)
                .padding(.horizontal, 4)
            
            VStack(spacing: 10) {
                ForEach(Array(generatedExercises.enumerated()), id: \.offset) { index, exercise in
                    ZStack {
                        NavigationLink(destination: exerciseDetailView(for: exercise)) {
                            EmptyView()
                        }
                        .opacity(0) // Hide the NavigationLink's default chevron
                        
                        CompactPillExerciseCard(
                            number: index + 1,
                            exercise: exercise,
                            programColor: programColor
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
    }
    
    @ViewBuilder
    private func exerciseDetailView(for exerciseData: ExerciseData) -> some View {
        // Find the Exercise entity from the exercise library
        let allExercises = ExerciseLibraryService.shared.getAllExercises()
        if let exercise = allExercises.first(where: { $0.name == exerciseData.name }) {
            ExerciseDetailWrapper(exercise: exercise)
        } else {
            Text("Exercise not found")
                .foregroundColor(.secondary)
        }
    }
    
    private func generateWorkoutExercises() {
        guard let programDay = programDay else {
            isGenerating = false
            return
        }
        
        print("🎯 Generating exercises for Day \(day): \(programDay.name)")
        print("   Focus: \(programDay.focus)")
        
        // Use intelligent generator with the day's focus
        let focusAreas = Set(programDay.focus.map { $0.lowercased() })
        let equipment = Set(programDay.equipment.map { $0.lowercased() })
        
        // Map intensity to difficulty
        let difficulty: IntelligentWorkoutGenerator.ExerciseComplexity
        switch programDay.intensity {
        case .light, .deload:
            difficulty = .beginner
        case .moderate:
            difficulty = .intermediate
        case .heavy:
            difficulty = .advanced
        }
        
        let intelligentGenerator = IntelligentWorkoutGenerator.shared
        generatedExercises = intelligentGenerator.generateIntelligentWorkout(
            targetBodyParts: focusAreas,
            availableEquipment: equipment,
            difficulty: difficulty,
            exerciseCount: programDay.exerciseCount,
            avoidRecentExercises: true,
            balanceMovementPatterns: true
        )
        
        // Store exercises in WorkoutManager for tab bar GO! button
        workoutManager.previewExercises = generatedExercises
        
        print("✅ Generated \(generatedExercises.count) exercises")
        isGenerating = false
    }
    
    private func startWorkoutWithGeneratedExercises() {
        guard let programDay = programDay else { return }
        
        print("🚀 Starting workout with generated exercises from WorkoutPreviewView")
        
        // Create workout
        let workout = Workout(context: viewContext)
        workout.id = UUID()
        workout.name = programDay.name
        workout.date = Date()
        workout.duration = 0
        workout.isCompleted = false
        
        // Convert generated ExerciseData to Core Data Exercise objects
        let allExercises = ExerciseLibraryService.shared.getAllExercises()
        let exercises = generatedExercises.compactMap { exerciseData in
            allExercises.first { $0.name == exerciseData.name }
        }
        
        print("   Starting with \(exercises.count) exercises")
        
        // Start the workout - this sets shouldNavigateToWorkoutTab = true AND isWorkoutActive = true
        workoutManager.startWorkout(
            workout: workout,
            exercises: exercises,
            insights: nil,
            programDay: self.day,
            programDayFocus: programDay.name
        )
        
        print("✅ Workout started")
        print("   - shouldNavigateToWorkoutTab: \(workoutManager.shouldNavigateToWorkoutTab)")
        print("   - isWorkoutActive: \(workoutManager.isWorkoutActive)")
        
        // DO NOT dismiss - the tab switch will handle the navigation
        // The onChange in MainTabView will switch to tab 2
        // The WorkoutTabView will automatically show ActiveWorkoutView because isWorkoutActive = true
    }
}

// MARK: - Exercise Detail Wrapper
struct ExerciseDetailWrapper: View {
    let exercise: Exercise
    
    var body: some View {
        ExerciseDetailView(exercise: exercise)
    }
}

// MARK: - Generated Exercise Preview Card
struct CompactPillExerciseCard: View {
    let number: Int
    let exercise: ExerciseData
    let programColor: Color
    
    private var categoryColor: Color {
        switch exercise.category.lowercased() {
        case "chest": return .red
        case "back": return .blue
        case "legs": return .green
        case "shoulders": return .orange
        case "arms": return .purple
        case "core": return .yellow
        case "neck": return .indigo
        default: return .cyan
        }
    }
    
    private var categoryIcon: String {
        switch exercise.category.lowercased() {
        case "chest": return "figure.strengthtraining.traditional"
        case "back": return "figure.rowing"
        case "legs": return "figure.run"
        case "shoulders": return "figure.arms.open"
        case "arms": return "dumbbell.fill"
        case "core": return "figure.core.training"
        default: return "dumbbell.fill"
        }
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Category icon (matching exercise library style)
            ZStack {
                Circle()
                    .fill(categoryColor.opacity(0.15))
                    .frame(width: 36, height: 36)
                
                Image(systemName: categoryIcon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(categoryColor)
            }
            
            // Exercise details
            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.name)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                HStack(spacing: 8) {
                    Text(exercise.category)
                        .font(.caption)
                        .foregroundColor(categoryColor)
                        .fontWeight(.medium)
                    
                    Text("•")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Text(exercise.equipment)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                }
            }
            
            Spacer()
            
            // Chevron (matching exercise library style)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 25)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
        )
    }
}

// MARK: - Exercise Preview Card (Legacy - for template-based)
struct ExercisePreviewCard: View {
    let number: Int
    let exercise: ExerciseTemplate
    let programColor: Color
    
    var body: some View {
        HStack(spacing: 16) {
            // Exercise number
            ZStack {
                Circle()
                    .fill(programColor.opacity(0.15))
                    .frame(width: 44, height: 44)
                
                Text("\(number)")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(programColor)
            }
            
            // Exercise info
            VStack(alignment: .leading, spacing: 6) {
                Text(exercise.exerciseName)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                HStack(spacing: 12) {
                    Label("\(exercise.sets) sets", systemImage: "repeat")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Label("\(exercise.reps) reps", systemImage: "number")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if exercise.restSeconds > 0 {
                        Label("\(exercise.restSeconds)s rest", systemImage: "timer")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(programColor.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
    }
}

// Extension to make Int identifiable for sheet
extension Int: Identifiable {
    public var id: Int { self }
}

#Preview {
    ProgramScheduleView(program: WorkoutProgramEngine.shared.getAllPrograms()[0])
        .environmentObject(WorkoutManager.shared)
}

