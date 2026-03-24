import SwiftUI
import CoreData
import Foundation

struct ActiveWorkoutView: View {
    @Environment(\.managedObjectContext) var viewContext
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.verticalSizeClass) var verticalSizeClass
    @EnvironmentObject var userManager: UserManager
    @EnvironmentObject var workoutManager: WorkoutManager
    // AdManager accessed lazily via .shared to avoid blocking view init
    @Binding var isPresented: Bool
    
    // 📱 Orientation tracking - ensures proper layout on rotation
    @StateObject var orientationManager = OrientationManager.shared
    
    // ⚡️ PERFORMANCE: Use centralized HapticManager (pre-warmed generators)
    
    let workout: Workout
    @State var exercises: [Exercise]
    
    // exerciseSets is now stored in workoutManager.exerciseSetsData to survive view rebuilds during ads
    @State var elapsedTime: TimeInterval = 0
    @State var timer: Timer?
    // ⚡️ PERFORMANCE: Use workoutManager.workoutStartTime instead of local state
    // This ensures accurate timing even if the view takes time to render
    // The timer calculation uses the ACTUAL start time (when GO was tapped)
    @State var showingCompletionView = false
    @State var isFinishingWorkout = false // Prevents duplicate workout saves
    @State var exerciseRestTimers: [String: TimeInterval] = [:]
    @State var lastInteractedExerciseId: String? = nil // Track which exercise was last interacted with
    @State var showingWorkoutInsights = false
    @State var previousExerciseSets: [String: [PreviousSetData]] = [:] // Store previous workout data
    @State var isShowingAd = false // Track if an ad is currently showing
    @State var isWorkoutFavorite = false // Track if workout is marked as favorite
    @State var showingExerciseSelection = false // For adding exercises during workout
    @State var initializationComplete = false // Guard against duplicate initialization
    @State var initTasks: [Task<Void, Never>] = [] // Track async tasks for cancellation
    
    // Drag reorder state
    @State var draggingIndex: Int? = nil
    @State var dragTargetIndex: Int? = nil
    
    // Active exercise tracking for highlight and auto-scroll
    @State var activeExerciseId: String? = nil
    
    // Track which exercise currently has an active rest timer (to stop when switching)
    @State var exerciseWithActiveTimer: String? = nil
    
    // Ad frequency tracking - only show ad every 3rd set
    @State var completedSetsCount: Int = 0
    
    // Shuffle ad tracking - show ad every 2nd shuffle
    @State var shuffleCount: Int = 0
    
    // Workout notes/journal
    @State var workoutNotes: String = ""
    @State var showingNotesField = false
    
    // Weight unit toggle (lb/kg) — persists across sessions
    @AppStorage("workoutWeightUnit") var useKg: Bool = false
    @AppStorage("workoutPerSideMode") var isPerSideGlobal: Bool = false
    @AppStorage("defaultRestSeconds") var defaultRestSeconds: Int = 90
    @AppStorage("autoStartRestTimer") var autoStartRestTimer: Bool = true
    @AppStorage("keepScreenOnDuringWorkout") var keepScreenOn: Bool = true
    @AppStorage("workoutSoundEffects") var soundEffects: Bool = true
    @AppStorage("showMusicPlayer") var showMusicPlayer: Bool = true
    
    // Settings panel
    @State var showingSettingsPanel = false
    @State var showingPremiumUpsell = false
    
    // ⚡️ PERFORMANCE: Two-phase rendering for instant load
    // MARK: - Ad Logic
    
    /// Determine if inline ads should show based on workout source
    var shouldShowInlineAds: Bool {
        // Show ads only for free users with ads enabled
        return !PremiumManager.shared.isPremiumUser && AdManager.shared.adsEnabled
    }
    
    init(isPresented: Binding<Bool>, workout: Workout, exercises: [Exercise]) {
        self._isPresented = isPresented
        self.workout = workout
        self._exercises = State(initialValue: exercises)
    }
    
    var workoutDuration: String {
        let minutes = Int(elapsedTime) / 60
        let seconds = Int(elapsedTime) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// Live workout name based on current exercises' muscle groups
    /// Stable sort: ties broken alphabetically so the name never flickers
    var liveWorkoutName: String {
        var muscleGroupCounts: [String: Int] = [:]
        for exercise in exercises {
            let groups = parseMuscleGroups(from: exercise)
            for group in groups {
                muscleGroupCounts[group, default: 0] += 1
            }
        }
        let sorted = muscleGroupCounts.sorted {
            if $0.value != $1.value { return $0.value > $1.value }
            return $0.key < $1.key
        }
        if sorted.count == 1 {
            return sorted[0].key
        } else if sorted.count >= 2 {
            let primary = sorted[0].key
            let secondary = sorted[1].key
            if sorted[0].value > sorted[1].value * 2 {
                return "\(primary) Focus"
            }
            return "\(primary) & \(secondary)"
        } else if exercises.count == 1 {
            return exercises[0].name ?? "Workout"
        }
        return "Workout"
    }

    var notesPlaceholder: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d/yy"
        let dateStr = formatter.string(from: Date())
        return "\(liveWorkoutName) - \(dateStr)"
    }
    
    var body: some View {
        mainWorkoutContent
    }
}

#Preview {
    let context = PersistenceController.preview.container.viewContext
    
    // Create sample workout and exercises
    let workout = Workout(context: context)
    workout.name = "Push Day"
    workout.date = Date()
    
    let exercise1 = Exercise(context: context)
    exercise1.name = "Bench Press (Barbell)"
    exercise1.category = "Chest"
    exercise1.equipment = "Barbell"
    
    let exercise2 = Exercise(context: context)
    exercise2.name = "Incline Bench Press (Dumbbell)"
    exercise2.category = "Chest"
    exercise2.equipment = "Dumbbells"
    
    return ActiveWorkoutView(
        isPresented: .constant(true),
        workout: workout,
        exercises: [exercise1, exercise2]
    )
    .environment(\.managedObjectContext, context)
    .environmentObject(UserManager())
}
