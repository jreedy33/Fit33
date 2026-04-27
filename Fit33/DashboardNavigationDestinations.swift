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
                CardioWorkoutDetailView(cardioWorkout: cardioWorkout)
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
        }
    }
}
