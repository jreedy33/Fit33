import SwiftUI
import CoreData

// MARK: - Dashboard Navigation Destinations (extracted to help type checker)

struct DashboardNavigationDestinations: ViewModifier {
    @ObservedObject var userManager: UserManager
    @ObservedObject var workoutManager: WorkoutManager
    @ObservedObject var generatedProgramService: GeneratedProgramService
    @ObservedObject var smartProgramEngine: SmartProgramEngine
    
    func body(content: Content) -> some View {
        content
            .navigationDestination(for: DashboardRoute.self) { route in
                dashboardRouteDestination(route)
            }
            .navigationDestination(for: ActiveChallenge.self) { challenge in
                ChallengeDetailView(challenge: challenge)
            }
            .navigationDestination(for: ActiveGroupChallenge.self) { challenge in
                GroupChallengeDetailView(challenge: challenge)
                    .environmentObject(userManager)
            }
            .navigationDestination(for: Workout.self) { workout in
                WorkoutHistoryDetailView(workout: workout)
            }
            .navigationDestination(for: CardioWorkoutDTO.self) { cardioWorkout in
                // 2026-05-02 — Strava-origin rows reuse the existing
                // "Powered by Strava" full-page screen
                // (`StravaSettingsView`) as the activity recap target,
                // with the tapped activity passed as `focusedActivity`
                // so the top "This Period" card swaps "This Week" for
                // "This Run". This keeps a single brand-attributed
                // surface for every Strava render path (settings tap,
                // dashboard widget tap, recent-activity row tap) and
                // means we never have to maintain a parallel detail
                // screen for Strava data.
                //
                // Lookup is by `external_id` against the in-memory
                // StravaService caches (recent + monthly). If the cache
                // is cold (e.g., first-launch race or activity older
                // than the 30d window), we gracefully fall back to the
                // generic `CardioWorkoutDetailView` so the row never
                // becomes a dead tap.
                if cardioWorkout.resolvedOrigin == .strava,
                   let externalId = cardioWorkout.externalId,
                   let activity = stravaActivity(forExternalId: externalId) {
                    StravaSettingsView(focusedActivity: activity)
                } else {
                    CardioWorkoutDetailView(cardioWorkout: cardioWorkout)
                }
            }
    }
    
    @ViewBuilder
    private func dashboardRouteDestination(_ route: DashboardRoute) -> some View {
        switch route {
        case .profile:
            ProfileView()
        case .mealPlan:
            SimpleMealPlanView()
        case .workoutHistory:
            WorkoutHistoryFullView()
        case .programDetailsPlaceholder:
            Text("Program Details - Coming Soon")
        case .generatedProgramsList:
            GeneratedProgramsListView()
        case .personalizedPrograms:
            PersonalizedProgramsView()
                .environmentObject(userManager)
        case .smartWorkoutPreview:
            if let program = generatedProgramService.activeProgram,
               let day = generatedProgramService.currentDay {
                SmartWorkoutPreviewView(day: day, program: program)
                    .environmentObject(generatedProgramService)
            }
        case .smartProgramOverview(let programId):
            if let program = smartProgramEngine.userPrograms.first(where: { $0.id == programId }) {
                let template = smartProgramEngine.getPersonalizedPrograms(for: userManager.currentUser)
                    .first(where: { $0.template.id == program.templateId })?.template
                SmartProgramOverviewView(program: program, template: template)
                    .environmentObject(workoutManager)
                    .environmentObject(userManager)
            }
        case .smartProgramDayPreview(let programId, let dayNumber):
            if let program = smartProgramEngine.userPrograms.first(where: { $0.id == programId }),
               let day = program.generatedDays.first(where: { $0.dayNumber == dayNumber }) {
                let template = smartProgramEngine.getPersonalizedPrograms(for: userManager.currentUser)
                    .first(where: { $0.template.id == program.templateId })?.template
                let totalDays = template?.totalDays ?? program.generatedDays.count
                SmartProgramDayPreviewView(
                    program: program,
                    day: day,
                    programName: program.personalizedName,
                    totalDays: totalDays
                )
                .environmentObject(workoutManager)
                .environmentObject(userManager)
            }
        case .stravaSettings:
            StravaSettingsView()
        case .whoopSettings:
            WhoopSettingsView()
        case .weeklyLeague:
            // Mirrors the FriendsTab `LeagueDetail` push (same view,
            // same NavigationStack-aware behavior). The view sets its
            // own `.navigationBarHidden(true)` so it draws its own
            // header inside the dashboard's stack — no nested
            // NavigationStack (PE invariant 6).
            WeeklyLeagueDetailView()
        case .olympianPath:
            // 2026-05-04 — Path to 33 (annual Olympian track) detail
            // screen. Pushed by the dashboard Olympian widget and the
            // `fit33://olympian` deep link.
            OlympianPathView()
        }
    }

    /// 2026-05-02 — resolves a `CardioWorkoutDTO.externalId` to the
    /// matching `StravaActivity` from the live `StravaService` caches
    /// so the recent-activity tap can push the recap-mode
    /// `StravaSettingsView`. Searches `recentActivities` first (the
    /// 30d hot cache) and falls through to `monthlyActivities`. Uses
    /// string comparison because Strava activity IDs are stored as
    /// strings on the cardio row but as `Int64` on `StravaActivity`.
    private func stravaActivity(forExternalId externalId: String) -> StravaActivity? {
        let service = StravaService.shared
        if let hit = service.recentActivities.first(where: { String($0.id) == externalId }) {
            return hit
        }
        return service.monthlyActivities.first(where: { String($0.id) == externalId })
    }
}
