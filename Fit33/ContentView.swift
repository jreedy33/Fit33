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

    // Session-sticky latch: once we've entered the post-onboarding app this
    // session, never bounce back to NewOnboardingView even if a transient
    // cloud-profile pull resets `hasCompletedOnboarding` to false in Core Data
    // (UserManager.syncProfileToCloud's "pull from cloud" branch can clobber
    // the freshly-completed local profile with a stale row created mid-flow
    // for contact matching). Latch flips true on the false→true transition AND
    // when the app launches with onboarding already complete.
    @State private var hasEnteredMainAppThisSession = false

    private var shouldShowMainApp: Bool {
        userManager.hasCompletedOnboarding || hasEnteredMainAppThisSession
    }

    var body: some View {
        ZStack {
            // ⚡️ Cold-start UX fix (2026-04-26):
            // Instant launch-color fallback BEFORE any subview renders. Without
            // this, between iOS dismissing the LaunchScreen.storyboard and
            // SwiftUI laying out `MainTabView`'s `AnimatedOrbBackground`, the
            // bare UIWindow can briefly show through as solid white — the
            // "white screen flash" complaint. By painting the matching
            // `LaunchBackground` color asset as the first ZStack child, the
            // visual transition from launch screen to dashboard is seamless:
            // dark color throughout (or pale-blue in light mode), no white.
            Color("LaunchBackground")
                .ignoresSafeArea()

            Group {
                if shouldShowMainApp {
                    MainTabView()
                } else {
                    NewOnboardingView()
                }
            }
            .environmentObject(userManager)
            .environmentObject(workoutManager)
        }
        .onAppear {
            // ⚡️ Cold-start Phase 3.10 — close the user-visible first-frame
            // signpost the moment SwiftUI commits the root view.
            Fit33App.markFirstFrameIfNeeded()
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
                
                // Latch: stay in MainTabView for the rest of the session even if
                // a background cloud-profile pull races and resets
                // hasCompletedOnboarding to false in Core Data.
                hasEnteredMainAppThisSession = true

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

            if !newValue && hasEnteredMainAppThisSession {
                AppLogger.warning("[TUTORIAL] Ignoring transient hasCompletedOnboarding=false (latched in MainTabView for this session — likely cloud-profile pull race)", category: .ui)
            }
            
            // Update our tracking state
            lastKnownOnboardingState = newValue
        }
        // The latch above is "session-sticky" against a transient cloud-pull race
        // that nulls out hasCompletedOnboarding. But sign-out is NOT transient —
        // resetForSignOut() sets currentUser = nil + hasCompletedOnboarding = false
        // and the user MUST be returned to the auth screen. The cloud-pull race
        // never nulls currentUser (syncUserProfileToCoreData only updates fields
        // on an existing row), so currentUser == nil is a reliable sign-out signal.
        .onChange(of: userManager.currentUser == nil) { _, isSignedOut in
            if isSignedOut && hasEnteredMainAppThisSession {
                AppLogger.info("[TUTORIAL] currentUser cleared (sign-out) — releasing MainTabView latch so login screen can render", category: .ui)
                hasEnteredMainAppThisSession = false
                hasShownTutorialThisSession = false
                lastKnownOnboardingState = false
            }
        }
        .task {
            // Wait briefly for UserManager init (reduced from 500ms)
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            
            await MainActor.run {
                AppLogger.debug("[TUTORIAL] Initial state captured: hasCompletedOnboarding = \(userManager.hasCompletedOnboarding)", category: .ui)
                lastKnownOnboardingState = userManager.hasCompletedOnboarding
                if userManager.hasCompletedOnboarding {
                    hasEnteredMainAppThisSession = true
                }
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
