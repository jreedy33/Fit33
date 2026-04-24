import Foundation

// MARK: - Screen → Source Files Map
//
// When a user rage-shakes, `BugReportView` calls
// `SessionLogManager.shared.getCurrentScreenInfo()` and passes the
// display name to `ScreenCodeMap.filesForScreen(...)`. The result is
// the list of Swift source files Claude opens when triaging the
// report — this is what makes the difference between "generic bug
// analysis" and "Claude already knows which file to edit."
//
// Phase 12b redesign (2026-04-24):
//
//   Before:
//     - 37 entries covering ~60% of Screen enum cases
//     - 2-4 files per entry ("just the view")
//     - No universal context (Claude had no idea which services backed
//       a given screen unless manually listed)
//     - No enforcement — new Screen enum cases had no coverage guard
//
//   After:
//     - Complete coverage (every Screen enum case has ≥1 entry; every
//       known top-level View has an entry)
//     - 5-10 files per entry: primary view + nearby view helpers +
//       domain services + shared models
//     - Foundational-files list ALWAYS appended (SupabaseManager,
//       NetworkErrorClassifier, AppLogger, UserManager,
//       AppPerformanceSystem, DiagnosticContext). Claude always has
//       auth + logging + perf context no matter which screen was
//       captured.
//     - `Fit33Tests/ScreenCodeMapCoverageTests.swift` fails the build
//       if any Screen case lacks a map entry, catching "forgot to add
//       the screen" regressions at PR time.
//
// RULE (enforced by test + swiftui-rules.mdc):
//   Adding a new top-level View struct that becomes a navigation
//   destination (pushed onto a NavigationStack OR presented as a sheet
//   / fullScreenCover) requires, IN THE SAME PR:
//     1. A new case on `SessionLogManager.Screen` with a stable
//        S-prefixed id.
//     2. A `.trackScreen(.<case>)` modifier on the view's body.
//     3. A `ScreenCodeMap` entry keyed by the display name, listing
//        the view file + its direct service dependencies + relevant
//        shared models.
//
// File ordering matters within an entry:
//   1. Primary view file (Claude opens this first)
//   2. Nearby helper views / extensions that back the primary view
//   3. Direct service dependencies (the RPC callers)
//   4. Shared models / types the view reads
//   5. Widgets or components rendered inline
// Claude does breadth-first analysis, so #1 is "most likely owner".

enum ScreenCodeMap {

    // MARK: - Foundational context
    //
    // These files are ALWAYS included (append-only) in the Claude
    // context, regardless of which screen was captured. They cover
    // cross-cutting concerns that are involved in nearly every user
    // action: authentication, Supabase access, logging, performance
    // instrumentation, and error classification. Having them attached
    // to every rage-shake means Claude can always correlate a screen
    // bug with "was the user logged in?" / "did this RPC fail with a
    // known pattern?" / "was the main thread stalling here?".
    //
    // Keep this list small and stable — if every rage-shake reports
    // 40 files, Claude's context window dilutes. Aim for the 5 files
    // every bug SHOULD at least scan.
    private static let foundationalFiles: [String] = [
        "Fit33/SupabaseManager.swift",
        "Fit33/UserManager.swift",
        "Fit33/NetworkErrorClassifier.swift",
        "Fit33/Logger.swift",                // AppLogger definition
        "Fit33/DiagnosticContext.swift",     // op / pg_code / http_status metadata
    ]

    // MARK: - Screen → Files table
    //
    // Keyed by `SessionLogManager.Screen.displayName` (case-insensitive).
    // Also matches via substring fallback so "Dashboard Home" still
    // resolves to the "dashboard" entry.
    private static let table: [String: [String]] = [

        // ═══════════════════════════════════════════════════════════
        // MAIN TABS
        // ═══════════════════════════════════════════════════════════
        "dashboard": [
            "Fit33/DashboardView.swift",
            "Fit33/DashboardView+Helpers.swift",
            "Fit33/DashboardView+Challenges.swift",
            "Fit33/DashboardView+Programs.swift",
            "Fit33/DashboardView+Activity.swift",
            "Fit33/DashboardView+Header.swift",
            "Fit33/DashboardWorkoutCards.swift",
            "Fit33/DashboardWorkoutHistory.swift",
            "Fit33/DashboardNavigationDestinations.swift",
        ],
        "exercise library": [
            "Fit33/ExerciseLibraryView.swift",
            "Fit33/ExerciseLibraryService.swift",
            "Fit33/ExerciseCardRow.swift",
            "Fit33/ExerciseCard.swift",
            "Fit33/SmartExerciseSearchService.swift",
            "Fit33/ExerciseFilterService.swift",
            "Fit33/ExerciseDataProvider.swift",
            "Fit33/ExerciseTypes.swift",
        ],
        "workout tab": [
            "Fit33/WorkoutTabView.swift",
            "Fit33/WorkoutManager.swift",
            "Fit33/TrainingHubView.swift",
            "Fit33/SmartProgramMiniCard.swift",
            "Fit33/WorkoutGeneratorService.swift",
            "Fit33/WorkoutSuggestionEngine.swift",
        ],
        "meals tab": [
            "Fit33/MealPlanView.swift",
            "Fit33/SimpleMealPlanView.swift",
            "Fit33/MealPlanComponents.swift",
            "Fit33/MealService.swift",
            "Fit33/HydrationService.swift",
            "Fit33/DashboardHydrationWidget.swift",
        ],
        "stats tab": [
            "Fit33/WorkoutStatsView.swift",
            "Fit33/HealthInsightsView.swift",
            "Fit33/HealthInsightsView+Readiness.swift",
            "Fit33/HealthDataService.swift",
            "Fit33/HealthKitManager.swift",
            "Fit33/WorkoutInsightsView.swift",
        ],

        // ═══════════════════════════════════════════════════════════
        // AUTH & ONBOARDING
        // ═══════════════════════════════════════════════════════════
        "auth screen": [
            "Fit33/AuthView.swift",
            "Fit33/SocialAuthService.swift",
            "Fit33/ExistingUserPhonePrompt.swift",
        ],
        "onboarding basics":      ["Fit33/NewOnboardingView.swift", "Fit33/OnboardingComponents.swift"],
        "onboarding body":        ["Fit33/NewOnboardingView.swift", "Fit33/OnboardingComponents.swift", "Fit33/WeightTrackingService.swift"],
        "onboarding goal":        ["Fit33/NewOnboardingView.swift", "Fit33/OnboardingComponents.swift"],
        "onboarding experience":  ["Fit33/NewOnboardingView.swift", "Fit33/OnboardingComponents.swift"],
        "onboarding strength":    ["Fit33/NewOnboardingView.swift", "Fit33/OnboardingComponents.swift", "Fit33/StrengthProfileRecommendationEngine.swift"],
        "onboarding location":    ["Fit33/NewOnboardingView.swift", "Fit33/LocationEquipmentSelectionView.swift"],
        "onboarding equipment":   ["Fit33/NewOnboardingView.swift", "Fit33/LocationEquipmentSelectionView.swift"],
        "onboarding limitations": ["Fit33/NewOnboardingView.swift", "Fit33/LimitationsSettingsView.swift"],
        "onboarding schedule":    ["Fit33/NewOnboardingView.swift"],
        "onboarding confirmation":["Fit33/OnboardingConfirmationViews.swift", "Fit33/NewOnboardingView.swift"],
        "onboarding complete":    ["Fit33/OnboardingConfirmationViews.swift", "Fit33/NewOnboardingView.swift"],
        "onboarding verification":["Fit33/NewOnboardingView+Verification.swift"],

        // ═══════════════════════════════════════════════════════════
        // WORKOUT FLOWS — Generator
        // ═══════════════════════════════════════════════════════════
        "workout generator":            ["Fit33/WorkoutGeneratorSelectionView.swift", "Fit33/WorkoutGeneratorService.swift", "Fit33/WorkoutTabView.swift"],
        "workout generator selection":  ["Fit33/WorkoutGeneratorSelectionView.swift", "Fit33/AutoWorkoutPreviewView.swift", "Fit33/WorkoutTabView.swift"],
        "workout muscle selection":     ["Fit33/AutoWorkoutPreviewView.swift", "Fit33/WorkoutTabView.swift"],
        "muscle selection":             ["Fit33/AutoWorkoutPreviewView.swift", "Fit33/WorkoutTabView.swift"],
        "workout equipment selection":  ["Fit33/LocationEquipmentSelectionView.swift"],
        "equipment selection":          ["Fit33/LocationEquipmentSelectionView.swift"],
        "workout duration selection":   ["Fit33/AutoWorkoutPreviewView.swift"],
        "duration selection":           ["Fit33/AutoWorkoutPreviewView.swift"],
        "workout preview":              ["Fit33/AutoWorkoutPreviewView.swift", "Fit33/SmartWorkoutPreviewView.swift", "Fit33/WorkoutGeneratorService.swift"],
        "generator: welcome":    ["Fit33/WorkoutGeneratorSelectionView.swift", "Fit33/WorkoutGeneratorService.swift"],
        "generator: duration":   ["Fit33/WorkoutGeneratorSelectionView.swift", "Fit33/WorkoutGeneratorService.swift"],
        "generator: muscles":    ["Fit33/WorkoutGeneratorSelectionView.swift", "Fit33/WorkoutGeneratorService.swift"],
        "generator: location":   ["Fit33/WorkoutGeneratorSelectionView.swift", "Fit33/LocationEquipmentSelectionView.swift"],
        "generator: equipment":  ["Fit33/WorkoutGeneratorSelectionView.swift", "Fit33/LocationEquipmentSelectionView.swift"],
        "generator: intensity":  ["Fit33/WorkoutGeneratorSelectionView.swift", "Fit33/WorkoutGeneratorService.swift"],
        "generator: generating": ["Fit33/WorkoutGeneratorSelectionView.swift", "Fit33/WorkoutGeneratorService.swift", "Fit33/SmartExerciseSelectionEngine.swift"],

        // ═══════════════════════════════════════════════════════════
        // WORKOUT FLOWS — Active / Completion
        // ═══════════════════════════════════════════════════════════
        "active workout": [
            "Fit33/ActiveWorkoutView.swift",
            "Fit33/ActiveWorkoutView+Actions.swift",
            "Fit33/ActiveWorkoutView+Layout.swift",
            "Fit33/ActiveWorkoutView+Persistence.swift",
            "Fit33/ActiveWorkoutView+Init.swift",
            "Fit33/WorkoutProgressView.swift",
            "Fit33/WorkoutManager.swift",
            "Fit33/RestTimerViews.swift",
            "Fit33/ExerciseDetailView.swift",
            "Fit33/WorkoutSetViews.swift",
        ],
        "cardio active workout": [
            "Fit33/CardioActiveWorkoutView.swift",
            "Fit33/RunningManager.swift",
            "Fit33/RunningWorkoutView.swift",
            "Fit33/BluetoothFitnessManager.swift",
        ],
        "cardio landing":        ["Fit33/CardioLandingView.swift", "Fit33/CardioGoalSetupView.swift"],
        "cardio workout detail": ["Fit33/CardioWorkoutDetailView.swift", "Fit33/CardioActiveWorkoutView.swift"],
        "workout completion":    ["Fit33/WorkoutCompletionView.swift", "Fit33/WorkoutManager.swift", "Fit33/ShareWorkoutSheet.swift"],
        "workout complete":      ["Fit33/WorkoutCompletionView.swift", "Fit33/WorkoutManager.swift"],
        "workout rating":        ["Fit33/WorkoutCompletionView.swift"],
        "workout share":         ["Fit33/ShareWorkoutSheet.swift", "Fit33/WorkoutSharingService.swift"],
        "workout summary":       ["Fit33/WorkoutCompletionView.swift", "Fit33/WorkoutInsightsView.swift"],
        "custom workout builder":["Fit33/CustomWorkoutBuilderView.swift", "Fit33/WorkoutCreationView.swift", "Fit33/WorkoutTabView.swift"],
        "exercise swap":         ["Fit33/ExerciseSubstitutionView.swift", "Fit33/ExerciseSwapService.swift", "Fit33/SmartExerciseSwapView.swift", "Fit33/ExerciseReplacementView.swift"],
        "rest timer":            ["Fit33/RestTimerViews.swift", "Fit33/ActiveWorkoutView.swift"],
        "stretch mode":          ["Fit33/StretchModeView.swift"],
        "workout replay":        ["Fit33/WorkoutReplayView.swift", "Fit33/WorkoutReplayEngine.swift"],
        "workout history":       ["Fit33/DashboardWorkoutHistory.swift", "Fit33/WorkoutManager.swift", "Fit33/WorkoutHistoryDetailView.swift"],
        "workout history detail":["Fit33/WorkoutHistoryDetailView.swift", "Fit33/DashboardWorkoutHistory.swift"],
        "workout repeat preview":["Fit33/WorkoutHistoryDetailView.swift", "Fit33/WorkoutManager.swift", "Fit33/AutoWorkoutPreviewView.swift"],
        "add exercise during workout": ["Fit33/AddExerciseDuringWorkoutView.swift", "Fit33/ExerciseLibraryService.swift"],

        // ═══════════════════════════════════════════════════════════
        // EXERCISES
        // ═══════════════════════════════════════════════════════════
        "exercise detail": [
            "Fit33/ExerciseDetailView.swift",
            "Fit33/ExerciseLibraryService.swift",
            "Fit33/ExerciseHistoryService.swift",
            "Fit33/VideoPlaybackEngine.swift",
            "Fit33/ExerciseIntelligenceService.swift",
        ],
        "exercise video":    ["Fit33/VideoPlaybackEngine.swift", "Fit33/VideoPreloadManager.swift", "Fit33/VideoStreamingService.swift"],
        "exercise history":  ["Fit33/ExerciseDetailView.swift", "Fit33/ExerciseHistoryService.swift"],
        "exercise selection":["Fit33/ExerciseSelectionView.swift", "Fit33/ExerciseLibraryService.swift", "Fit33/SmartExerciseSelectionEngine.swift"],
        "exercise search":   ["Fit33/SmartExerciseSearchService.swift", "Fit33/ExerciseLibraryView.swift"],
        "exercise filter":   ["Fit33/ExerciseLibraryView.swift", "Fit33/ExerciseFilterService.swift"],
        "rename exercise":   ["Fit33/RenameExerciseView.swift", "Fit33/ExerciseNicknameService.swift"],

        // ═══════════════════════════════════════════════════════════
        // PROGRAMS
        // ═══════════════════════════════════════════════════════════
        "programs list":           ["Fit33/ProgramLibraryView.swift", "Fit33/CloudProgramLibraryView.swift", "Fit33/ProgramLibraryService.swift", "Fit33/CloudProgramService.swift"],
        "program detail":          ["Fit33/ProgramDetailView.swift", "Fit33/CloudProgramService.swift", "Fit33/ProgramStartService.swift"],
        "program schedule":        ["Fit33/ProgramScheduleView.swift", "Fit33/CloudProgramScheduleView.swift", "Fit33/ProgramScheduleFullView.swift"],
        "program day detail":      ["Fit33/ProgramDayPreviewView.swift", "Fit33/CloudProgramService.swift"],
        "program explorer":        ["Fit33/ProgramExplorerView.swift", "Fit33/CloudProgramService.swift"],
        "generated programs":      ["Fit33/GeneratedProgramService.swift", "Fit33/WorkoutProgramEngine.swift", "Fit33/ProgramLibraryView.swift"],
        "program customization":   ["Fit33/ProgramCustomizationView.swift", "Fit33/ProgramCustomizationService.swift"],
        "seven day program detail":["Fit33/SevenDayProgramDetailView.swift", "Fit33/ProgramLibraryService.swift"],

        // ═══════════════════════════════════════════════════════════
        // MEALS & NUTRITION
        // ═══════════════════════════════════════════════════════════
        "meal plan":         ["Fit33/MealPlanView.swift", "Fit33/MealPlanComponents.swift", "Fit33/MealService.swift", "Fit33/SmartMealPlannerView.swift"],
        "food search":       ["Fit33/FoodSearchView.swift", "Fit33/FoodDatabaseService.swift", "Fit33/USDAFoodSearch.swift", "Fit33/USDAFoodService.swift"],
        "food detail":       ["Fit33/FoodDetailsView.swift", "Fit33/FoodDatabaseService.swift"],
        "meal log":          ["Fit33/MealPlanView.swift", "Fit33/MealService.swift", "Fit33/SavedMealsService.swift"],
        "recipe import":     ["Fit33/RecipeImportView.swift", "Fit33/RecipeModels.swift"],
        "recipe browser":    ["Fit33/RecipeBrowserView.swift", "Fit33/RecipeDetailView.swift", "Fit33/RecipeModels.swift", "Fit33/HealthyRecipesCarousel.swift"],
        "recipe detail":     ["Fit33/RecipeDetailView.swift", "Fit33/RecipeModels.swift"],
        "recipe preferences":["Fit33/RecipePreferencesView.swift", "Fit33/RecipePreferenceService.swift"],
        "nutrition summary": ["Fit33/MealPlanView.swift", "Fit33/HealthDataService.swift"],

        // ═══════════════════════════════════════════════════════════
        // HEALTH / HYDRATION / WEIGHT
        // ═══════════════════════════════════════════════════════════
        "step tracker":      ["Fit33/StepTrackerView.swift", "Fit33/HealthKitManager.swift", "Fit33/HealthDataService.swift"],
        "hydration":         ["Fit33/DashboardHydrationWidget.swift", "Fit33/HydrationService.swift"],
        "health insights":   ["Fit33/HealthInsightsView.swift", "Fit33/HealthInsightsView+Readiness.swift", "Fit33/HealthDataService.swift", "Fit33/ReadinessWorkoutAdjuster.swift"],
        "weight tracker":    ["Fit33/DashboardWeightWidget.swift", "Fit33/WeightTrackerWidget.swift", "Fit33/WeightTrackingService.swift"],
        "app health diagnostics": ["Fit33/AppHealthDiagnosticsView.swift", "Fit33/AppHealthDiagnostics.swift"],

        // ═══════════════════════════════════════════════════════════
        // SOCIAL / FRIENDS
        // ═══════════════════════════════════════════════════════════
        "friends tab":       ["Fit33/FriendsTabView.swift", "Fit33/FriendsListView.swift", "Fit33/FriendService.swift", "Fit33/FriendActivityFeedView.swift", "Fit33/FriendRankingService.swift"],
        "friends list":      ["Fit33/FriendsListView.swift", "Fit33/FriendService.swift", "Fit33/FriendPhotoCache.swift"],
        "friend profile":    ["Fit33/FriendProfileView.swift", "Fit33/FriendService.swift", "Fit33/FriendRankingService.swift", "Fit33/FriendWorkoutPreviewView.swift"],
        "friend requests":   ["Fit33/FriendRequestPreviewWidget.swift", "Fit33/FriendService.swift"],
        "received workouts": ["Fit33/ReceivedWorkoutsView.swift", "Fit33/ReceivedWorkoutPreviewWidget.swift", "Fit33/WorkoutSharingService.swift"],
        "workout sharing":   ["Fit33/WorkoutSharingService.swift", "Fit33/ShareWorkoutSheet.swift", "Fit33/FriendSelectionSheet.swift"],
        "shared workout":    ["Fit33/SharedWorkoutView.swift", "Fit33/SharedWorkoutPreviewView.swift", "Fit33/WorkoutSharingService.swift"],
        "blocked users":     ["Fit33/BlockedUsersView.swift", "Fit33/FriendService.swift"],
        "favorite routines": ["Fit33/FavoriteRoutinesView.swift"],

        // ═══════════════════════════════════════════════════════════
        // CHALLENGES (Phase 12, 2026-04-24)
        // ═══════════════════════════════════════════════════════════
        "private challenge detail": [
            "Fit33/PrivateChallengeDetailView.swift",
            "Fit33/PrivateChallengeService.swift",
            "Fit33/ChallengeReactionsView.swift",
            "Fit33/DashboardView+Challenges.swift",
        ],
        "private challenge list": [
            "Fit33/DashboardView+Challenges.swift",
            "Fit33/PrivateChallengeService.swift",
            "Fit33/ChallengePreviewWidget.swift",
        ],
        "private challenge invite": [
            "Fit33/PrivateChallengeInviteView.swift",
            "Fit33/PrivateChallengeService.swift",
            "Fit33/FriendService.swift",
        ],
        "private challenge admin": [
            "Fit33/PrivateChallengeAdminSettingsView.swift",
            "Fit33/PrivateChallengeService.swift",
        ],
        "private challenge creation": [
            "Fit33/PrivateChallengeCreationFlow.swift",
            "Fit33/PrivateChallengeService.swift",
            "Fit33/ChallengeSetupView.swift",
        ],
        "community challenge list": [
            "Fit33/CommunityChallengeViews.swift",
            "Fit33/CommunityChallengeService.swift",
        ],
        "community challenge detail": [
            "Fit33/CommunityChallengeViews.swift",
            "Fit33/CommunityChallengeService.swift",
            "Fit33/ChallengeReactionsView.swift",
        ],
        "group challenge detail": [
            "Fit33/GroupChallengeDetailView.swift",
            "Fit33/ChallengeService.swift",
            "Fit33/ChallengeOpponentWakeService.swift",
            "Fit33/BackgroundChallengeSyncService.swift",
        ],
        "challenge detail": [
            "Fit33/ChallengeDetailView.swift",
            "Fit33/ChallengeService.swift",
            "Fit33/BackgroundChallengeSyncService.swift",
        ],
        "challenge creation": [
            "Fit33/ChallengeCreationFlow.swift",
            "Fit33/ChallengeSetupView.swift",
            "Fit33/ChallengeService.swift",
        ],
        "challenge flow start": [
            "Fit33/ChallengeFlowStartView.swift",
            "Fit33/ChallengeService.swift",
            "Fit33/ChallengeCreationFlow.swift",
        ],

        // ═══════════════════════════════════════════════════════════
        // PROFILE / SETTINGS
        // ═══════════════════════════════════════════════════════════
        "profile":         ["Fit33/ProfileView.swift", "Fit33/ProfilePhotoCache.swift"],
        "settings":        ["Fit33/SettingsView.swift", "Fit33/UnitSettingsManager.swift", "Fit33/UnitSettingsView.swift"],
        "edit profile":    ["Fit33/ProfileView.swift"],
        "equipment":       ["Fit33/LocationEquipmentSelectionView.swift"],
        "limitations":     ["Fit33/LimitationsSettingsView.swift"],
        "notifications":   ["Fit33/NotificationManager.swift", "Fit33/PushNotificationService.swift", "Fit33/PushNotificationDebugView.swift"],
        "appearance":      ["Fit33/AdaptiveColors.swift", "Fit33/SettingsView.swift"],
        "premium":         ["Fit33/PremiumUpgradeView.swift"],
        "privacy policy":  ["Fit33/SettingsView.swift"],
        "terms of service":["Fit33/SettingsView.swift"],
        "unit settings":   ["Fit33/UnitSettingsView.swift", "Fit33/UnitSettingsManager.swift"],

        // ═══════════════════════════════════════════════════════════
        // STATS / PROGRESS
        // ═══════════════════════════════════════════════════════════
        "progress charts":  ["Fit33/WorkoutStatsView.swift", "Fit33/WorkoutInsightsView.swift"],
        "achievements":     ["Fit33/DashboardStreakViews.swift"],
        "streaks":          ["Fit33/DashboardStreakViews.swift", "Fit33/StreakShieldService.swift"],
        "body metrics":     ["Fit33/WeightTrackingService.swift", "Fit33/DashboardWeightWidget.swift"],

        // ═══════════════════════════════════════════════════════════
        // WEARABLE SETTINGS
        // ═══════════════════════════════════════════════════════════
        "healthkit settings": ["Fit33/HealthKitSettingsView.swift", "Fit33/HealthKitManager.swift", "Fit33/HealthKitService.swift"],
        "whoop settings":     ["Fit33/WhoopSettingsView.swift", "Fit33/WhoopService.swift", "Fit33/DashboardWhoopWidget.swift"],
        "oura settings":      ["Fit33/OuraSettingsView.swift", "Fit33/OuraService.swift", "Fit33/DashboardOuraWidget.swift"],
        "fitbit settings":    ["Fit33/FitbitSettingsView.swift", "Fit33/FitbitService.swift"],
        "strava settings":    ["Fit33/StravaSettingsView.swift", "Fit33/StravaService.swift"],

        // ═══════════════════════════════════════════════════════════
        // BUG / DIAGNOSTICS / DEV
        // ═══════════════════════════════════════════════════════════
        "bug report":        ["Fit33/BugReportView.swift", "Fit33/BugReportService.swift", "Fit33/BugReportStateSnapshot.swift", "Fit33/BugReportStateSnapshot+Providers.swift", "Fit33/ScreenCodeMap.swift"],
        "log preview":       ["Fit33/SessionLogManager.swift", "Fit33/BugReportView.swift"],
        "welcome tutorial":  ["Fit33/WelcomeTutorialView.swift"],

        // ═══════════════════════════════════════════════════════════
        // MODALS / SHEETS (generic — often transient)
        // ═══════════════════════════════════════════════════════════
        "share sheet":   ["Fit33/ShareWorkoutSheet.swift", "Fit33/WorkoutSharingService.swift"],
        "image picker":  ["Fit33/ProfileView.swift"],
        "date picker":   ["Fit33/SettingsView.swift"],
        "alert":         ["Fit33/ContentView.swift"],
        "action sheet":  ["Fit33/ContentView.swift"],
        "go button":     ["Fit33/WorkoutTabView.swift", "Fit33/TrainingHubView.swift"],
        "terms & conditions": ["Fit33/SettingsView.swift"],
        "terms sheet":   ["Fit33/SettingsView.swift"],

        // ═══════════════════════════════════════════════════════════
        // MISC
        // ═══════════════════════════════════════════════════════════
        "now playing":       ["Fit33/NowPlayingBar.swift"],
        "training hub":      ["Fit33/TrainingHubView.swift", "Fit33/WorkoutTabView.swift"],
    ]

    /// Returns source files most likely associated with the given
    /// screen name, always appended with `foundationalFiles` so Claude
    /// has auth + logging + perf context on every bug report.
    ///
    /// - Parameters:
    ///   - screenName: Display name from `SessionLogManager.Screen.displayName`.
    ///   - maxFiles:   Hard cap on returned files (Phase 12b default 12,
    ///                 up from the previous 4). Applies to the combined
    ///                 primary + foundational list; foundational files
    ///                 always take priority when trimming.
    static func filesForScreen(_ screenName: String?, maxFiles: Int = 12) -> [String] {
        let primary = primaryFiles(for: screenName)
        return dedupe(primary, foundationalFiles, cap: maxFiles)
    }

    /// Same lookup as `filesForScreen` but excludes the foundational-files
    /// list — useful when you want to display ONLY the screen-specific
    /// file candidates (e.g. in a dev-menu debugger). Regular bug-report
    /// flow should always use `filesForScreen` so Claude gets the
    /// universal context.
    static func screenSpecificFiles(_ screenName: String?, maxFiles: Int = 12) -> [String] {
        let primary = primaryFiles(for: screenName)
        return Array(primary.prefix(maxFiles))
    }

    /// The canonical foundational file list — exposed for
    /// `Fit33Tests/ScreenCodeMapCoverageTests.swift` + anyone who wants
    /// to know "what files are ALWAYS loaded regardless of screen".
    static var foundationalFilesList: [String] { foundationalFiles }

    /// Every mapped display-name key. Used by the coverage test to
    /// confirm every `SessionLogManager.Screen.displayName` has an
    /// entry in the map (or a substring match).
    static var mappedDisplayNameKeys: [String] { Array(table.keys) }

    /// Convenience: returns a comma-separated string for logging/UI badges.
    static func describeFiles(_ files: [String]) -> String {
        if files.isEmpty { return "no match" }
        return files.map { ($0 as NSString).lastPathComponent }.joined(separator: ", ")
    }

    // MARK: - Private

    private static func primaryFiles(for screenName: String?) -> [String] {
        guard let raw = screenName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return [] }

        let key = normalize(raw)

        if let exact = table[key] {
            return exact
        }

        // Partial-match fallback: return the first entry whose key is a
        // substring of the screen name or vice versa. Lets future
        // screens like "Dashboard Quests Wrapper" still resolve to
        // Dashboard files.
        for (candidate, files) in table {
            if key.contains(candidate) || candidate.contains(key) {
                return files
            }
        }

        return []
    }

    private static func dedupe(_ primary: [String], _ secondary: [String], cap: Int) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for f in primary + secondary {
            if seen.insert(f).inserted {
                out.append(f)
                if out.count >= cap { break }
            }
        }
        return out
    }

    private static func normalize(_ s: String) -> String {
        s.lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
    }
}
