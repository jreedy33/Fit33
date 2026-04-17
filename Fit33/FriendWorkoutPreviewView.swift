import SwiftUI
import CoreData

struct FriendWorkoutPreviewView: View {
    let workoutId: String
    let friendName: String
    let metadata: ActivityMetadata
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject var workoutManager: WorkoutManager
    
    @State private var exercises: [FriendExerciseDTO] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showNoExercisesAlert = false
    @State private var showingExerciseDetail = false
    @State private var selectedCoreDataExercise: Exercise? = nil
    @State private var showingSavedConfirmation = false
    @State private var isSaving = false
    @State private var isAddingExercise = false
    @State private var showingExercisePicker = false
    
    private let themeColor: Color = .cyan
    private let secondaryThemeColor: Color = .blue
    
    var body: some View {
        NavigationStack {
            ZStack {
                AnimatedOrbBackground.workout(colorScheme: colorScheme)
                
                ScrollView {
                    VStack(spacing: Spacing.lg) {
                        workoutHeader
                        
                        if isLoading {
                            ProgressView()
                                .padding(.top, Spacing.xl)
                        } else if let error = errorMessage {
                            errorView(error)
                        } else if exercises.isEmpty {
                            emptyExercisesList
                        } else {
                            exerciseListSection
                        }
                    }
                    .padding(.horizontal, Spacing.md)
                    .padding(.bottom, 160)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        GoButtonState.shared.hide(reason: "FriendWorkout_back")
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: saveToFavorites) {
                        HStack(spacing: 4) {
                            if isSaving {
                                ProgressView()
                                    .scaleEffect(0.7)
                            } else {
                                Image(systemName: showingSavedConfirmation ? "bookmark.fill" : "bookmark")
                                    .font(.ds_bodyRegular).fontWeight(.medium)
                                    .foregroundColor(showingSavedConfirmation ? .green : themeColor)
                            }
                        }
                    }
                    .disabled(exercises.isEmpty || isSaving)
                }
            }
        }
        .task {
            await loadExercises()
        }
        .onAppear {
            if !exercises.isEmpty {
                showGoButton()
            }
        }
        .onDisappear {
            GoButtonState.shared.hide(reason: "FriendWorkout_disappeared")
        }
        .onChange(of: workoutManager.isWorkoutActive) { _, isActive in
            if isActive { dismiss() }
        }
        .alert("Couldn't Start Workout", isPresented: $showNoExercisesAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("None of the exercises in this workout could be found in your exercise library.")
        }
        .sheet(isPresented: $showingExerciseDetail) {
            if let exercise = selectedCoreDataExercise {
                NavigationStack {
                    ExerciseDetailView(exercise: exercise)
                }
            }
        }
        .sheet(isPresented: $showingExercisePicker) {
            NavigationStack {
                CustomWorkoutBuilderView(onAddExercise: { exercise in
                    addExercise(exercise)
                    showingExercisePicker = false
                })
            }
        }
    }
    
    // MARK: - Header
    
    private var workoutHeader: some View {
        VStack(spacing: Spacing.xs) {
            Text(friendName + "'s Workout")
                .font(.ds_heading2)
                .foregroundColor(.primary)
            
            if let name = metadata.workoutName, !name.isEmpty {
                Text(name)
                    .font(.ds_heading3)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, Spacing.sm)
    }
    
    // MARK: - Exercise List
    
    private var exerciseListSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Exercises")
                    .font(.headline)
                    .fontWeight(.bold)
                
                Spacer()
                
                HStack(spacing: 4) {
                    Image(systemName: "hand.tap.fill")
                        .font(.caption2)
                    Text("tap for details")
                        .font(.caption)
                }
                .foregroundColor(.secondary)
            }
            .padding(.horizontal, Spacing.xxs)
            
            VStack(spacing: 10) {
                ForEach(Array(exercises.enumerated()), id: \.offset) { index, exercise in
                    FriendExerciseCard(
                        number: index + 1,
                        exerciseName: exercise.exerciseName,
                        setCount: exercise.setsCompleted,
                        topSetWeight: exercise.maxWeight,
                        topSetReps: exercise.maxReps,
                        themeColor: themeColor,
                        onTap: {
                            if let coreDataExercise = ExerciseLibraryService.shared.getExercise(byName: exercise.exerciseName) {
                                selectedCoreDataExercise = coreDataExercise
                                showingExerciseDetail = true
                            }
                        }
                    )
                }
            }
            
            // Add Exercise button
            if !isAddingExercise {
                Button(action: {
                    HapticManager.selectionChanged()
                    showingExercisePicker = true
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                            .font(.ds_heading3)
                        Text("Add Exercise")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(themeColor)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 25)
                            .stroke(themeColor.opacity(0.3), lineWidth: 2)
                            .background(RoundedRectangle(cornerRadius: 25).fill(Color.cardBackground))
                    )
                }
                .padding(.top, 8)
            }
        }
    }
    
    private var emptyExercisesList: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "dumbbell.fill")
                .font(.ds_heading1)
                .foregroundColor(.secondary)
            Text("Exercise details not available")
                .font(.ds_bodyMedium)
                .foregroundColor(.secondary)
            Text("This workout may have been recorded on an older version.")
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, Spacing.xl)
    }
    
    private func errorView(_ message: String) -> some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.ds_heading1)
                .foregroundColor(.orange)
            Text(message)
                .font(.ds_bodyMedium)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, Spacing.xl)
    }
    
    // MARK: - Data Loading
    
    private func loadExercises() async {
        // Primary source: exercises embedded in the activity metadata
        if let metadataExercises = metadata.exercises, !metadataExercises.isEmpty {
            let dtos = metadataExercises.enumerated().map { index, info in
                FriendExerciseDTO(
                    id: UUID().uuidString,
                    exerciseName: info.name,
                    order: index,
                    setsCompleted: info.sets,
                    maxWeight: info.maxWeight,
                    maxReps: info.maxReps,
                    totalVolume: nil
                )
            }
            await MainActor.run {
                self.exercises = dtos
                self.isLoading = false
                showGoButton()
                prefetchHistory()
            }
            return
        }
        
        // Fallback: try RPC for older posts that have a real workout_id
        do {
            struct Params: Encodable {
                let p_workout_id: String
            }
            
            let result: [FriendExerciseDTO] = try await SupabaseManager.shared.supabaseClient
                .rpc("get_friend_workout_exercises", params: Params(p_workout_id: workoutId))
                .execute()
                .value
            
            await MainActor.run {
                self.exercises = result.sorted(by: { $0.order < $1.order })
                self.isLoading = false
                if !result.isEmpty {
                    showGoButton()
                    prefetchHistory()
                }
            }
        } catch {
            AppLogger.error("Failed to load friend workout exercises: \(error.localizedDescription)", category: .social)
            
            await MainActor.run {
                self.exercises = []
                self.isLoading = false
            }
        }
    }
    
    private func showGoButton() {
        guard !exercises.isEmpty else { return }
        GoButtonState.shared.show(
            primaryColor: themeColor,
            secondaryColor: secondaryThemeColor,
            source: "FriendWorkoutPreview"
        ) {
            HapticManager.impact(.heavy)
            startWorkout()
        }
    }
    
    private func prefetchHistory() {
        let names = exercises.map { $0.exerciseName }
        Task {
            _ = await ExerciseHistoryService.shared.fetchPreviousSetsForExercises(names)
        }
    }
    
    // MARK: - Actions
    
    private func startWorkout() {
        var coreDataExercises: [Exercise] = []
        
        for dto in exercises {
            if let exercise = ExerciseLibraryService.shared.getExercise(byName: dto.exerciseName) {
                coreDataExercises.append(exercise)
            } else {
                AppLogger.warning("Could not resolve friend exercise: \(dto.exerciseName)", category: .workout)
            }
        }
        
        guard !coreDataExercises.isEmpty else {
            showNoExercisesAlert = true
            return
        }
        
        AppLogger.info("Starting friend workout with \(coreDataExercises.count)/\(exercises.count) exercises", category: .workout)
        
        let newWorkout = Workout(context: viewContext)
        newWorkout.id = UUID()
        newWorkout.name = metadata.workoutName ?? "\(friendName)'s Workout"
        newWorkout.date = Date()
        newWorkout.isCompleted = false
        
        workoutManager.startWorkout(workout: newWorkout, exercises: coreDataExercises)
        GoButtonState.shared.hide(reason: "FriendWorkout_started")
    }
    
    private func saveToFavorites() {
        guard !isSaving else { return }
        isSaving = true
        HapticManager.impact(.medium)
        
        let exerciseNames = exercises.map { $0.exerciseName }
        let workoutName = metadata.workoutName ?? "\(friendName)'s Workout"
        
        // Save as a local workout template
        var saved = UserDefaults.standard.array(forKey: "savedFriendWorkouts") as? [[String: Any]] ?? []
        saved.append([
            "id": workoutId,
            "name": workoutName,
            "exercises": exerciseNames,
            "savedAt": ISO8601DateFormatter().string(from: Date()),
            "fromFriend": friendName
        ])
        UserDefaults.standard.set(saved, forKey: "savedFriendWorkouts")
        
        isSaving = false
        showingSavedConfirmation = true
        HapticManager.notification(.success)
        AppLogger.info("Saved friend workout '\(workoutName)' with \(exerciseNames.count) exercises", category: .social)
    }
    
    private func addExercise(_ exercise: Exercise) {
        guard let name = exercise.name, !name.isEmpty else { return }
        let dto = FriendExerciseDTO(
            id: UUID().uuidString,
            exerciseName: name,
            order: exercises.count,
            setsCompleted: 3,
            maxWeight: nil,
            maxReps: nil,
            totalVolume: nil
        )
        exercises.append(dto)
        showGoButton()
    }
    
    private func formatDuration(_ seconds: Int) -> String {
        let mins = seconds / 60
        if mins < 60 { return "\(mins)m" }
        return "\(mins / 60)h \(mins % 60)m"
    }
}

// MARK: - Friend Exercise DTO (from RPC)

struct FriendExerciseDTO: Codable, Identifiable {
    let id: String
    let exerciseName: String
    let order: Int
    let setsCompleted: Int
    let maxWeight: Double?
    let maxReps: Int?
    let totalVolume: Double?
    
    enum CodingKeys: String, CodingKey {
        case id, order
        case exerciseName = "exercise_name"
        case setsCompleted = "sets_completed"
        case maxWeight = "max_weight"
        case maxReps = "max_reps"
        case totalVolume = "total_volume"
    }
}

// MARK: - Friend Exercise Card

private struct FriendExerciseCard: View {
    let number: Int
    let exerciseName: String
    let setCount: Int
    let topSetWeight: Double?
    let topSetReps: Int?
    let themeColor: Color
    let onTap: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    
    private var libraryExercise: Exercise? {
        ExerciseLibraryService.shared.getExercise(byName: exerciseName)
    }
    
    private var categoryGradient: [Color] {
        switch libraryExercise?.category?.lowercased() {
        case "chest": return [.purple, .pink]
        case "back": return [.blue, .cyan]
        case "legs": return [.green, .teal]
        case "shoulders": return [.orange, .yellow]
        case "arms": return [.purple, .indigo]
        case "core": return [.yellow, .orange]
        default: return [.cyan, .blue]
        }
    }
    
    private var categoryIcon: String {
        switch libraryExercise?.category?.lowercased() {
        case "chest": return "figure.strengthtraining.traditional"
        case "back": return "figure.strengthtraining.traditional"
        case "legs": return "figure.walk"
        case "shoulders": return "figure.arms.open"
        case "arms": return "figure.arms.open"
        case "core": return "figure.core.training"
        default: return "dumbbell.fill"
        }
    }
    
    private var weightString: String? {
        guard let w = topSetWeight, w > 0 else { return nil }
        let formatted = w.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(w))" : String(format: "%.1f", w)
        if let reps = topSetReps {
            return "\(formatted) lbs × \(reps)"
        }
        return "\(formatted) lbs"
    }
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: categoryGradient,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 40, height: 40)
                        .shadow(color: categoryGradient[0].opacity(0.25), radius: 4, x: 0, y: 2)
                    
                    Image(systemName: categoryIcon)
                        .font(.ds_labelLarge)
                        .foregroundColor(.white)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(exerciseName)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    HStack(spacing: 8) {
                        Text("\(setCount) sets")
                            .font(.caption)
                            .foregroundColor(categoryGradient[0])
                            .fontWeight(.medium)
                        
                        if let ws = weightString {
                            Text("·")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text(ws)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else if let category = libraryExercise?.category {
                            Text("·")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text(category)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.ds_bodySmall).fontWeight(.medium)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: CornerRadius.lg)
                        .fill(
                            LinearGradient(
                                colors: colorScheme == .dark
                                    ? [Color(white: 0.15), Color.cardBackground]
                                    : [Color.white, Color.white.opacity(0.98)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    
                    RoundedRectangle(cornerRadius: CornerRadius.lg)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    categoryGradient[0].opacity(colorScheme == .dark ? 0.2 : 0.12),
                                    categoryGradient[1].opacity(colorScheme == .dark ? 0.1 : 0.06)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
            )
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.12 : 0.05), radius: 6, x: 0, y: 3)
        }
        .buttonStyle(.plain)
    }
}
