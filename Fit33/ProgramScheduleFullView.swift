import SwiftUI
import CoreData

// MARK: - Program Schedule Full View
// Shows program days in a grid, similar to CloudProgramScheduleView

struct ProgramScheduleFullView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var workoutManager: WorkoutManager
    
    let program: ExtendedProgram
    
    @State private var showingCancelAlert = false
    
    private var programColor: Color {
        program.gradientSwiftUIColors.first ?? .blue
    }
    
    private var activeProgram: WorkoutProgram? {
        workoutManager.activeProgram
    }
    
    private var completedDays: Set<Int> {
        workoutManager.programCompletedDays
    }
    
    private var currentDay: Int {
        guard let startDate = workoutManager.programStartDate else { return 1 }
        let daysSinceStart = Calendar.current.dateComponents([.day], from: startDate, to: Date()).day ?? 0
        return min(daysSinceStart + 1, program.durationDays)
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Progress header
                progressHeader
                
                // Days grid
                daysGridSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 100)
        }
        .background(
            LinearGradient(
                gradient: Gradient(colors: colorScheme == .dark 
                    ? [programColor.opacity(0.2), programColor.opacity(0.05), Color(red: 0.05, green: 0.05, blue: 0.07)]
                    : [programColor.opacity(0.3), programColor.opacity(0.1), Color.white]),
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
                        showingCancelAlert = true
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
                workoutManager.activeProgram = nil
                workoutManager.programStartDate = nil
                workoutManager.programCompletedDays = []
                dismiss()
            }
        } message: {
            Text("Are you sure you want to cancel this program? Your progress will be lost.")
        }
    }
    
    // MARK: - Progress Header
    
    private var progressHeader: some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                // Icon
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: program.gradientSwiftUIColors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 50, height: 50)
                        .shadow(color: programColor.opacity(0.3), radius: 4, x: 0, y: 2)
                    
                    Image(systemName: program.icon)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.white)
                }
                
                // Info
                VStack(alignment: .leading, spacing: 4) {
                    Text("Day \(currentDay) of \(program.durationDays)")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(programColor)
                    
                    Text("\(completedDays.count) workouts completed")
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
                    
                    let progressWidth = CGFloat(completedDays.count) / CGFloat(program.durationDays)
                    RoundedRectangle(cornerRadius: 6)
                        .fill(
                            LinearGradient(
                                colors: program.gradientSwiftUIColors,
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geometry.size.width * progressWidth, height: 8)
                        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: completedDays.count)
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
    
    // MARK: - Days Grid Section
    
    private var daysGridSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Workout Schedule")
                    .font(.headline)
                    .fontWeight(.bold)
                
                Spacer()
            }
            .padding(.horizontal, 4)
            
            // Grid layout for day tiles
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ], spacing: 12) {
                ForEach(1...program.durationDays, id: \.self) { day in
                    let isRestDay = isRestDay(day)
                    let isCompleted = completedDays.contains(day)
                    let isUnlocked = day <= currentDay
                    let dayName = getDayName(day)
                    
                    if isUnlocked && !isRestDay {
                        NavigationLink(destination: ProgramDayPreviewView(
                            program: program,
                            dayNumber: day,
                            programColor: programColor
                        ).environmentObject(workoutManager)) {
                            ProgramDayTile(
                                day: day,
                                dayName: dayName,
                                isRestDay: isRestDay,
                                isCompleted: isCompleted,
                                isUnlocked: isUnlocked,
                                programColor: programColor
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    } else {
                        ProgramDayTile(
                            day: day,
                            dayName: isRestDay ? "Rest" : dayName,
                            isRestDay: isRestDay,
                            isCompleted: isCompleted,
                            isUnlocked: isUnlocked,
                            programColor: programColor
                        )
                    }
                }
            }
        }
    }
    
    // MARK: - Helpers
    
    private func isRestDay(_ day: Int) -> Bool {
        guard let activeProgram = activeProgram else { return false }
        return activeProgram.restDays.contains(day)
    }
    
    private func getDayName(_ day: Int) -> String {
        guard let activeProgram = activeProgram,
              let programDay = activeProgram.schedule[day] else {
            return "Workout"
        }
        return programDay.name
    }
}

// MARK: - Program Day Tile

struct ProgramDayTile: View {
    let day: Int
    let dayName: String
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
            Text(dayName)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(isRestDay ? .secondary : .primary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
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

// MARK: - Program Day Preview View (Shows exercises with GO! button)

struct ProgramDayPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var workoutManager: WorkoutManager
    
    let program: ExtendedProgram
    let dayNumber: Int
    let programColor: Color
    
    @State private var generatedExercises: [ExerciseData] = []
    @State private var isGenerating = true
    @State private var showingExerciseSwap = false
    @State private var selectedExerciseIndex: Int? = nil
    @State private var selectedCoreDataExercise: Exercise? = nil
    @State private var showingExerciseDetail = false
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                gradient: Gradient(colors: colorScheme == .dark 
                    ? [programColor.opacity(0.2), programColor.opacity(0.05), Color(red: 0.05, green: 0.05, blue: 0.07)]
                    : [programColor.opacity(0.3), programColor.opacity(0.1), Color.white]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            if isGenerating {
                loadingView
            } else if generatedExercises.isEmpty {
                emptyStateView
            } else {
                exerciseList
            }
        }
        .navigationTitle("Day \(dayNumber)")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await generateExercises()
        }
        .sheet(isPresented: $showingExerciseSwap) {
            if let index = selectedExerciseIndex, index < generatedExercises.count {
                ProgramExerciseSwapView(
                    currentExercise: generatedExercises[index],
                    programColor: programColor
                ) { newExercise in
                    generatedExercises[index] = newExercise
                }
            }
        }
        .sheet(isPresented: $showingExerciseDetail) {
            if let exercise = selectedCoreDataExercise {
                NavigationStack {
                    ExerciseDetailView(exercise: exercise)
                        .toolbar {
                            ToolbarItem(placement: .navigationBarTrailing) {
                                Button("Done") {
                                    showingExerciseDetail = false
                                }
                            }
                        }
                }
            }
        }
        .onAppear {
            if !generatedExercises.isEmpty {
                showGoButton()
            }
        }
        .onChange(of: isGenerating) { _, stillGenerating in
            if !stillGenerating && !generatedExercises.isEmpty {
                showGoButton()
            }
        }
        .onDisappear {
            GoButtonState.shared.hide()
        }
    }
    
    private func showGoButton() {
        let color = programColor
        GoButtonState.shared.show(
            primaryColor: color,
            secondaryColor: color.opacity(0.7)
        ) {
            self.startWorkout()
        }
    }
    
    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(programColor)
            
            Text("Generating your workout...")
                .font(.headline)
                .foregroundColor(.secondary)
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 50))
                .foregroundColor(.orange)
            
            Text("Could not generate exercises")
                .font(.headline)
                .foregroundColor(.primary)
            
            Button("Retry") {
                Task { await generateExercises() }
            }
            .buttonStyle(.borderedProminent)
            .tint(programColor)
        }
        .padding()
    }
    
    private var exerciseList: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Day header
                dayHeader
                
                // Exercise list section
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Today's Exercises")
                            .font(.headline)
                            .fontWeight(.bold)
                        
                        Spacer()
                        
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.triangle.swap")
                                .font(.caption2)
                            Text("to swap")
                                .font(.caption)
                        }
                        .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 4)
                    
                    VStack(spacing: 10) {
                        ForEach(Array(generatedExercises.enumerated()), id: \.offset) { index, exercise in
                            ProgramExerciseCard(
                                number: index + 1,
                                exercise: exercise,
                                programColor: programColor,
                                onTapCard: {
                                    // Find matching Exercise from Core Data for full detail view with user stats
                                    if let coreDataExercise = ExerciseLibraryService.shared.getExercise(byName: exercise.name) {
                                        selectedCoreDataExercise = coreDataExercise
                                        showingExerciseDetail = true
                                    }
                                },
                                onTapSwap: {
                                    selectedExerciseIndex = index
                                    showingExerciseSwap = true
                                }
                            )
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.top, 8)
            .padding(.bottom, 120)
        }
    }
    
    private var dayHeader: some View {
        VStack(spacing: 8) {
            HStack {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: program.gradientSwiftUIColors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 44, height: 44)
                    
                    Text("\(dayNumber)")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(getDayName())
                        .font(.headline)
                        .fontWeight(.bold)
                    
                    Text("\(generatedExercises.count) exercises • ~\(program.avgWorkoutMinutes) min")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
    }
    
    // MARK: - Generate Exercises
    
    private func generateExercises() async {
        isGenerating = true
        
        guard let activeProgram = workoutManager.activeProgram,
              let programDay = activeProgram.schedule[dayNumber] else {
            isGenerating = false
            return
        }
        
        // Use the intelligent generator with the day's focus
        let focusAreas = Set(programDay.focus.map { $0.lowercased() })
        let equipment = Set(programDay.equipment.map { $0.lowercased() })
        
        let difficulty: IntelligentWorkoutGenerator.ExerciseComplexity
        switch programDay.intensity {
        case .light, .deload: difficulty = .beginner
        case .moderate: difficulty = .intermediate
        case .heavy: difficulty = .advanced
        }
        
        let generated = IntelligentWorkoutGenerator.shared.generateIntelligentWorkout(
            targetBodyParts: focusAreas,
            availableEquipment: equipment,
            difficulty: difficulty,
            exerciseCount: programDay.exerciseCount,
            avoidRecentExercises: true,
            balanceMovementPatterns: true
        )
        
        await MainActor.run {
            generatedExercises = generated
            isGenerating = false
        }
    }
    
    private func getDayName() -> String {
        guard let activeProgram = workoutManager.activeProgram,
              let programDay = activeProgram.schedule[dayNumber] else {
            return "Workout"
        }
        return programDay.name
    }
    
    // MARK: - Start Workout
    
    private func startWorkout() {
        guard let activeProgram = workoutManager.activeProgram,
              let programDay = activeProgram.schedule[dayNumber] else {
            return
        }
        
        // Generate workout using program engine
        let (workout, exercises) = WorkoutProgramEngine.shared.generateWorkoutFromProgramDay(
            programDay,
            context: viewContext
        )
        
        // Start the workout
        workoutManager.currentProgramDayNumber = dayNumber
        workoutManager.currentProgramDayFocus = programDay.name
        workoutManager.startWorkout(workout: workout, exercises: exercises, insights: nil)
        
        // Navigate to workout tab
        workoutManager.shouldNavigateToWorkoutTab = true
    }
}

// MARK: - Program Exercise Card

struct ProgramExerciseCard: View {
    let number: Int
    let exercise: ExerciseData
    let programColor: Color
    let onTapCard: () -> Void
    let onTapSwap: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Number badge
            ZStack {
                Circle()
                    .fill(programColor.opacity(0.15))
                    .frame(width: 32, height: 32)
                
                Text("\(number)")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(programColor)
            }
            
            // Exercise info
            VStack(alignment: .leading, spacing: 4) {
                Text(exercise.name)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                HStack(spacing: 8) {
                    Text(exercise.category)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("•")
                        .foregroundColor(.secondary)
                    
                    Text(exercise.equipment)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Swap button
            Button(action: onTapSwap) {
                Image(systemName: "arrow.triangle.swap")
                    .font(.system(size: 14))
                    .foregroundColor(programColor)
                    .padding(8)
                    .background(programColor.opacity(0.1))
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
        .onTapGesture(perform: onTapCard)
    }
}

// MARK: - Exercise Swap View

struct ProgramExerciseSwapView: View {
    @Environment(\.dismiss) private var dismiss
    
    let currentExercise: ExerciseData
    let programColor: Color
    let onSwap: (ExerciseData) -> Void
    
    @State private var alternatives: [ExerciseData] = []
    @State private var isLoading = true
    
    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Finding alternatives...")
                } else if alternatives.isEmpty {
                    Text("No alternative exercises found")
                        .foregroundColor(.secondary)
                } else {
                    List(alternatives, id: \.name) { exercise in
                        Button {
                            onSwap(exercise)
                            dismiss()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(exercise.name)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundColor(.primary)
                                    
                                    Text("\(exercise.equipment) • \(exercise.category)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                Image(systemName: "arrow.right.circle.fill")
                                    .foregroundColor(programColor)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("Swap Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .task {
            await loadAlternatives()
        }
    }
    
    private func loadAlternatives() async {
        // Find exercises that target the same muscles
        let targetMuscles = Set(currentExercise.muscleGroups.map { $0.lowercased() })
        
        let allExercises = ExerciseDataProvider.shared.exercises
        let filtered = allExercises.filter { exercise in
            let exerciseMuscles = Set(exercise.muscleGroups.map { $0.lowercased() })
            let hasOverlap = !targetMuscles.isDisjoint(with: exerciseMuscles)
            return hasOverlap && exercise.name != currentExercise.name
        }
        
        await MainActor.run {
            alternatives = Array(filtered.prefix(10))
            isLoading = false
        }
    }
}


