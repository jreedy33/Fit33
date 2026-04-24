import Foundation

// MARK: - Screen → Source Files Map
//
// When a user rage-shakes, we capture the current screen name via
// `SessionLogManager.shared.getCurrentScreenInfo()`. This map translates
// that name into the Swift source files most likely to contain the bug.
// The Admin CMS passes those paths to Claude so the generated
// bug_intelligence_report.file_path / code_diff start from a real file
// instead of a best-guess symbolicated stack trace.
//
// Keep this map pragmatic:
//   - Focus on top-used screens. Unknown screens return an empty list.
//   - Order matters: first file = "most likely owner". Claude uses #1 as
//     the starting `file_path` candidate.
//   - When a view is a simple wrapper (e.g. DashboardView calls
//     DashboardWorkoutCards + DashboardWorkoutHistory), list the wrappers
//     AFTER the primary — they're more likely bug sources.
//
// When you add a new top-level view, ADD IT HERE. Rule of thumb: if the
// screen is in SessionLogManager.Screen, it deserves a row here.

enum ScreenCodeMap {

    /// Keyed by `SessionLogManager.Screen.displayName` (case-insensitive).
    /// Also matches on the canonical tab names ("Dashboard", "Workout",
    /// "Meals", "Stats", "Profile") regardless of localisation.
    private static let table: [String: [String]] = [

        // ── Main tabs ────────────────────────────────────────────────
        "dashboard": [
            "Fit33/DashboardView.swift",
            "Fit33/DashboardView+Helpers.swift",
            "Fit33/DashboardWorkoutCards.swift",
            "Fit33/DashboardWorkoutHistory.swift",
        ],
        "exercise library": [
            "Fit33/ExerciseLibraryView.swift",
            "Fit33/ExerciseLibraryService.swift",
            "Fit33/ExerciseCardRow.swift",
            "Fit33/SmartExerciseSearchService.swift",
        ],
        "workout tab": [
            "Fit33/WorkoutTabView.swift",
            "Fit33/WorkoutManager.swift",
            "Fit33/TrainingHubView.swift",
        ],
        "meals tab": [
            "Fit33/MealPlanView.swift",
            "Fit33/SimpleMealPlanView.swift",
            "Fit33/MealPlanComponents.swift",
        ],
        "stats tab": [
            "Fit33/WorkoutStatsView.swift",
            "Fit33/HealthInsightsView.swift",
            "Fit33/HealthDataService.swift",
        ],

        // ── Auth & onboarding ────────────────────────────────────────
        "auth screen": [
            "Fit33/NewOnboardingView.swift",
            "Fit33/SupabaseManager.swift",
        ],
        "onboarding basics": ["Fit33/NewOnboardingView.swift", "Fit33/OnboardingComponents.swift"],
        "onboarding body": ["Fit33/NewOnboardingView.swift", "Fit33/OnboardingComponents.swift"],
        "onboarding goal": ["Fit33/NewOnboardingView.swift", "Fit33/OnboardingComponents.swift"],
        "onboarding experience": ["Fit33/NewOnboardingView.swift", "Fit33/OnboardingComponents.swift"],
        "onboarding strength": ["Fit33/NewOnboardingView.swift", "Fit33/OnboardingComponents.swift"],
        "onboarding location": ["Fit33/NewOnboardingView.swift", "Fit33/LocationEquipmentSelectionView.swift"],
        "onboarding equipment": ["Fit33/NewOnboardingView.swift", "Fit33/LocationEquipmentSelectionView.swift"],
        "onboarding limitations": ["Fit33/NewOnboardingView.swift", "Fit33/LimitationsSettingsView.swift"],
        "onboarding schedule": ["Fit33/NewOnboardingView.swift"],
        "onboarding confirmation": ["Fit33/OnboardingConfirmationViews.swift", "Fit33/NewOnboardingView.swift"],
        "onboarding complete": ["Fit33/OnboardingConfirmationViews.swift"],
        "onboarding verification": ["Fit33/NewOnboardingView+Verification.swift"],

        // ── Workout flows ────────────────────────────────────────────
        "workout generator selection": ["Fit33/AutoWorkoutPreviewView.swift", "Fit33/WorkoutTabView.swift"],
        "workout muscle selection":    ["Fit33/AutoWorkoutPreviewView.swift", "Fit33/WorkoutTabView.swift"],
        "workout equipment selection": ["Fit33/LocationEquipmentSelectionView.swift"],
        "workout duration selection":  ["Fit33/AutoWorkoutPreviewView.swift"],
        "workout preview":             ["Fit33/AutoWorkoutPreviewView.swift"],
        "active workout": [
            "Fit33/WorkoutProgressView.swift",
            "Fit33/WorkoutManager.swift",
            "Fit33/RestTimerViews.swift",
            "Fit33/ExerciseDetailView.swift",
        ],
        "cardio active workout": [
            "Fit33/CardioActiveWorkoutView.swift",
            "Fit33/RunningManager.swift",
            "Fit33/BluetoothFitnessManager.swift",
        ],
        "cardio landing":        ["Fit33/CardioLandingView.swift"],
        "cardio workout detail": ["Fit33/CardioWorkoutDetailView.swift"],
        "workout completion":    ["Fit33/WorkoutCompletionView.swift"],
        "workout summary":       ["Fit33/WorkoutCompletionView.swift"],
        "custom workout builder":["Fit33/WorkoutTabView.swift"],
        "exercise swap":         ["Fit33/WorkoutManager.swift", "Fit33/ExerciseLibraryService.swift"],
        "rest timer":            ["Fit33/RestTimerViews.swift"],
        "stretch mode":          ["Fit33/StretchModeView.swift"],
        "workout replay":        ["Fit33/WorkoutReplayView.swift", "Fit33/WorkoutReplayEngine.swift"],
        "workout history":       ["Fit33/DashboardWorkoutHistory.swift", "Fit33/WorkoutManager.swift"],
        "workout history detail":["Fit33/DashboardWorkoutHistory.swift"],

        // ── Exercises ────────────────────────────────────────────────
        "exercise detail": [
            "Fit33/ExerciseDetailView.swift",
            "Fit33/ExerciseLibraryService.swift",
            "Fit33/VideoPlaybackEngine.swift",
        ],
        "exercise video":    ["Fit33/VideoPlaybackEngine.swift", "Fit33/VideoPreloadManager.swift"],
        "exercise history":  ["Fit33/ExerciseDetailView.swift"],
        "exercise search":   ["Fit33/SmartExerciseSearchService.swift", "Fit33/ExerciseLibraryView.swift"],
        "exercise filter":   ["Fit33/ExerciseLibraryView.swift"],
        "rename exercise":   ["Fit33/RenameExerciseView.swift", "Fit33/ExerciseNicknameService.swift"],

        // ── Meals ────────────────────────────────────────────────────
        "meal plan":         ["Fit33/MealPlanView.swift", "Fit33/MealPlanComponents.swift"],
        "food search":       ["Fit33/SimpleMealPlanView.swift"],
        "food detail":       ["Fit33/MealPlanComponents.swift"],
        "meal log":          ["Fit33/MealPlanView.swift"],
        "recipe import":     ["Fit33/RecipeImportView.swift"],
        "nutrition summary": ["Fit33/MealPlanView.swift"],

        // ── Health / hydration ───────────────────────────────────────
        "step tracker":      ["Fit33/StepTrackerView.swift", "Fit33/HealthKitManager.swift"],
        "hydration":         ["Fit33/HydrationWidget.swift"],
        "health insights":   ["Fit33/HealthInsightsView.swift", "Fit33/HealthDataService.swift"],

        // ── Social ───────────────────────────────────────────────────
        "friends list":         ["Fit33/FriendsListView.swift", "Fit33/FriendService.swift"],
        "friend profile":       ["Fit33/FriendProfileView.swift", "Fit33/FriendService.swift"],
        "friend requests":      ["Fit33/FriendRequestPreviewWidget.swift", "Fit33/FriendService.swift"],
        "received workouts":    ["Fit33/ReceivedWorkoutsView.swift", "Fit33/WorkoutSharingService.swift"],
        "workout sharing":      ["Fit33/WorkoutSharingService.swift"],
        "blocked users":        ["Fit33/BlockedUsersView.swift"],
        "favorite routines":    ["Fit33/FavoriteRoutinesView.swift"],

        // ── Challenges ───────────────────────────────────────────────
        // Phase 12 rage-shake fix (2026-04-24): added these entries +
        // matching `.trackScreen()` on each view's body so a shake from
        // a challenge detail page routes Claude to the actual challenge
        // file instead of whatever was tracked last (historically
        // ProfileView.swift). Order matters — the view file comes
        // first so Claude starts its analysis there, service files
        // second so it can trace state changes.
        "private challenge detail": [
            "Fit33/PrivateChallengeDetailView.swift",
            "Fit33/PrivateChallengeService.swift",
            "Fit33/ChallengeReactionsView.swift",
        ],
        "private challenge list": [
            "Fit33/DashboardView+Challenges.swift",
            "Fit33/PrivateChallengeService.swift",
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
        ],
        "community challenge list": [
            "Fit33/CommunityChallengeViews.swift",
            "Fit33/CommunityChallengeService.swift",
        ],
        "community challenge detail": [
            "Fit33/CommunityChallengeViews.swift",
            "Fit33/CommunityChallengeService.swift",
        ],
        "group challenge detail": [
            "Fit33/GroupChallengeDetailView.swift",
            "Fit33/ChallengeService.swift",
            "Fit33/ChallengeOpponentWakeService.swift",
        ],
        "challenge detail": [
            "Fit33/ChallengeDetailView.swift",
            "Fit33/ChallengeService.swift",
        ],
        "challenge creation": [
            "Fit33/ChallengeCreationFlow.swift",
            "Fit33/ChallengeSetupView.swift",
            "Fit33/ChallengeService.swift",
        ],
        "challenge flow start": [
            "Fit33/ChallengeFlowStartView.swift",
            "Fit33/ChallengeService.swift",
        ],

        // ── Profile / settings ───────────────────────────────────────
        "profile":         ["Fit33/ProfileView.swift", "Fit33/UserManager.swift"],
        "edit profile":    ["Fit33/ProfileView.swift", "Fit33/UserManager.swift"],
        "settings":        ["Fit33/SettingsView.swift"],
        "equipment":       ["Fit33/LocationEquipmentSelectionView.swift"],
        "limitations":     ["Fit33/LimitationsSettingsView.swift"],
        "notifications":   ["Fit33/NotificationManager.swift"],
        "appearance":      ["Fit33/AdaptiveColors.swift"],
        "premium":         ["Fit33/PremiumView.swift"],

        // ── Bug report self-references ───────────────────────────────
        "bug report":  ["Fit33/BugReportView.swift", "Fit33/BugReportService.swift"],
        "log preview": ["Fit33/SessionLogManager.swift", "Fit33/BugReportView.swift"],

        // ── Misc ─────────────────────────────────────────────────────
        "now playing":          ["Fit33/NowPlayingBar.swift"],
        "training hub":         ["Fit33/TrainingHubView.swift"],
    ]

    /// Returns up to `maxFiles` source files most likely associated with the
    /// given screen name. Matching is case/space-insensitive and also tries
    /// a few common aliases (e.g. "Dashboard" vs "Home Dashboard"). Returns
    /// an empty array if no match is found.
    static func filesForScreen(_ screenName: String?, maxFiles: Int = 4) -> [String] {
        guard let raw = screenName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return [] }

        let key = normalize(raw)

        if let exact = table[key] {
            return Array(exact.prefix(maxFiles))
        }

        // Partial-match fallback: return the first entry whose key is a
        // substring of the screen name or vice versa. Lets future screens
        // like "Dashboard Quests Wrapper" still resolve to Dashboard files.
        for (candidate, files) in table {
            if key.contains(candidate) || candidate.contains(key) {
                return Array(files.prefix(maxFiles))
            }
        }

        return []
    }

    /// Convenience: returns a comma-separated string for logging/UI badges.
    static func describeFiles(_ files: [String]) -> String {
        if files.isEmpty { return "no match" }
        return files.map { ($0 as NSString).lastPathComponent }.joined(separator: ", ")
    }

    private static func normalize(_ s: String) -> String {
        s.lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
    }
}
