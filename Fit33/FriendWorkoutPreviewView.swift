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
    
    private let themeColor: Color = .cyan
    private let secondaryThemeColor: Color = .blue
    
    var body: some View {
        NavigationStack {
            ZStack {
                AnimatedOrbBackground.workout(colorScheme: colorScheme)
                
                ScrollView {
                    VStack(spacing: Spacing.sm) {
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
                                Image(systemName: showingSavedConfirmation ? "star.fill" : "star")
                                    .font(.ds_bodyRegular).fontWeight(.medium)
                                    .foregroundColor(showingSavedConfirmation ? .yellow : themeColor)
                            }
                        }
                    }
                    .disabled(exercises.isEmpty || isSaving)
                    .accessibilityLabel(showingSavedConfirmation ? "Added to favorites" : "Add to favorites")
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
    }
    
    // MARK: - Header
    
    private var workoutHeader: some View {
        VStack(spacing: 2) {
            Text(friendName + "'s Workout")
                .font(.ds_heading2)
                .foregroundColor(.primary)
            
            if let name = metadata.workoutName, !name.isEmpty {
                Text(name)
                    .font(.ds_heading3)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.top, 4)
    }
    
    // MARK: - Exercise List
    
    private var exerciseListSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
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
            
            VStack(spacing: Spacing.xs) {
                ForEach(Array(exercises.enumerated()), id: \.offset) { _, exercise in
                    FriendExerciseLibraryRow(
                        exerciseName: exercise.exerciseName,
                        themeColor: themeColor,
                        onTap: { coreDataExercise in
                            selectedCoreDataExercise = coreDataExercise
                            showingExerciseDetail = true
                        }
                    )
                }
            }
            
            // Start Workout primary button uses the dashboard's
            // `themeColor → secondaryThemeColor` gradient so it visually
            // echoes the floating GoButton — both routes do the same thing.
            VStack(spacing: Spacing.xs) {
                Button(action: {
                    HapticManager.impact(.heavy)
                    startWorkout()
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "play.fill")
                            .font(.ds_bodyRegular).fontWeight(.bold)
                        Text("Start Workout")
                            .font(.subheadline)
                            .fontWeight(.bold)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 25)
                            .fill(
                                LinearGradient(
                                    colors: [themeColor, secondaryThemeColor],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    )
                    .shadow(color: themeColor.opacity(0.35), radius: 10, x: 0, y: 4)
                }
                .accessibilityLabel("Start \(friendName)'s workout")
                .accessibilityHint("Begins a new active workout with these exercises")
            }
            .padding(.top, Spacing.xs)
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

        // Flag a +75 XP bonus for completing a friend's workout. Read +
        // applied (and cleared) by `UserManager.completeWorkout`. Set
        // BEFORE `startWorkout` so the value is in place by the time the
        // user finishes the session.
        workoutManager.friendWorkoutBonusXP = 75

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

// MARK: - Friend Exercise Library Row
//
// Renders the same card as the Exercises tab (`ExerciseCardRow`) when the
// friend's exercise resolves against `ExerciseLibraryService`. The friend's
// per-set metrics (sets, top weight × reps) are deliberately NOT shown here
// — this screen is a "preview before I do my own version", not a recap of
// the friend's session, so we hide their numbers and only show the canonical
// exercise identity (name + category + equipment + cached video still).
//
// When the exercise can't be resolved (custom / older posts), we fall back
// to a minimal name-only chip so the workout preview still lists every
// exercise the friend logged.
private struct FriendExerciseLibraryRow: View {
    let exerciseName: String
    let themeColor: Color
    let onTap: (Exercise) -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var libraryExercise: Exercise? {
        ExerciseLibraryService.shared.getExercise(byName: exerciseName)
    }

    var body: some View {
        if let exercise = libraryExercise {
            Button {
                HapticManager.selectionChanged()
                onTap(exercise)
            } label: {
                ExerciseCardRow(
                    exercise: exercise,
                    showChevron: true
                )
            }
            .buttonStyle(.plain)
        } else {
            unresolvedFallback
        }
    }

    private var unresolvedFallback: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "dumbbell.fill")
                .font(.ds_bodyRegular)
                .foregroundColor(.secondary)
                .frame(width: 56, height: 56)
                .background(
                    Circle().fill(Color.secondary.opacity(0.12))
                )

            Text(exerciseName)
                .font(.ds_bodyLarge)
                .fontWeight(.medium)
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer()
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .adaptiveSleekCardSubtle(cornerRadius: CornerRadius.lg)
    }
}
