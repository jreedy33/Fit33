import SwiftUI
import CoreData
import Combine
import Charts
import UserNotifications

struct ContentView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject private var userManager = UserManager.shared
    @StateObject private var workoutManager = WorkoutManager.shared
    
    // Welcome tutorial state - shown once per session when user completes onboarding
    @State private var showWelcomeTutorial = false
    @State private var hasShownTutorialThisSession = false
    
    // Track the last known onboarding state to detect transitions
    @State private var lastKnownOnboardingState: Bool? = nil
    
    var body: some View {
        ZStack {
            Group {
                if userManager.hasCompletedOnboarding {
                    MainTabView()
                } else {
                    NewOnboardingView()
                }
            }
            .environmentObject(userManager)
            .environmentObject(workoutManager)
        }
        .fullScreenCover(isPresented: $showWelcomeTutorial) {
            WelcomeTutorialView(isPresented: $showWelcomeTutorial)
        }
        .overlay(alignment: .top) {
            if BadgeService.shared.showUnlockToast,
               let achievement = BadgeService.shared.lastUnlockedAchievement {
                AchievementUnlockToast(achievement: achievement)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(998)
                    .padding(.top, 50)
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: BadgeService.shared.showUnlockToast)
        .overlay {
            if userManager.showLevelUpCelebration {
                LevelUpCelebrationOverlay(
                    level: userManager.newLevelReached,
                    levelTitle: userManager.getLevelTitle(),
                    levelIcon: userManager.getLevelIcon(),
                    levelColor: userManager.getLevelColor()
                ) {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        userManager.showLevelUpCelebration = false
                    }
                }
                .transition(.opacity.combined(with: .scale))
                .zIndex(999)
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: userManager.showLevelUpCelebration)
        .onChange(of: userManager.hasCompletedOnboarding) { oldValue, newValue in
            AppLogger.debug("[TUTORIAL] hasCompletedOnboarding changed: \(oldValue) → \(newValue), lastKnown: \(String(describing: lastKnownOnboardingState))", category: .ui)
            
            // Detect actual onboarding completion (user went from not-onboarded to onboarded)
            if newValue && !oldValue {
                AppLogger.debug("[TUTORIAL] Onboarding completed! lastKnown: \(String(describing: lastKnownOnboardingState)), shownThisSession: \(hasShownTutorialThisSession)", category: .ui)
                
                // Show tutorial if:
                // 1. Haven't shown it already this session, AND
                // 2. This is a real onboarding completion (not just app loading existing user)
                //    - lastKnownOnboardingState being nil means app just launched with existing user (skip)
                //    - lastKnownOnboardingState being false means user actually went through onboarding flow
                if !hasShownTutorialThisSession && lastKnownOnboardingState == false {
                    AppLogger.info("[TUTORIAL] Showing welcome tutorial!", category: .ui)
                    hasShownTutorialThisSession = true
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 1_200_000_000)
                        showWelcomeTutorial = true
                    }
                }
            }
            
            // Update our tracking state
            lastKnownOnboardingState = newValue
        }
        .task {
            // Wait briefly for UserManager init (reduced from 500ms)
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            
            await MainActor.run {
                AppLogger.debug("[TUTORIAL] Initial state captured: hasCompletedOnboarding = \(userManager.hasCompletedOnboarding)", category: .ui)
                lastKnownOnboardingState = userManager.hasCompletedOnboarding
            }
            
            // 🔄 ONE-TIME FORCE SYNC: Check if we need to refresh exercise data
            // This ensures users get the latest improved exercise data
            // Bump version when exercise DB schema/data changes (e.g., CSV updates)
            let currentExerciseVersion = "v2.1" // Bumped: exercise classification data update
            let needsRefresh = UserDefaults.standard.string(forKey: "exerciseDataVersion") != currentExerciseVersion
            
            if needsRefresh && SupabaseManager.shared.isAuthenticated {
                AppLogger.debug("Detected new exercise data version - forcing fresh sync...", category: .ui)
                await ExerciseLibraryService.shared.forceSyncExercises()
                UserDefaults.standard.set(currentExerciseVersion, forKey: "exerciseDataVersion")
                AppLogger.info("Exercise data updated to \(currentExerciseVersion)", category: .ui)
            }
        }
    }
}

#Preview {
    ContentView()
}
