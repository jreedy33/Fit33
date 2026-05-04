import SwiftUI
import CoreData
import Combine
import Charts
import UserNotifications

struct ContentView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject private var userManager = UserManager.shared
    @StateObject private var workoutManager = WorkoutManager.shared
    // 2026-04-29 — League Redesign Plan §B2. ContentView observes the
    // weekly-league singleton so the tier-promotion overlay re-renders the
    // moment `pendingTierPromotion` changes (set by detection in
    // `fetchOrJoinLeague`, cleared by the overlay's onDismiss).
    @StateObject private var weeklyLeagueService = WeeklyLeagueService.shared

    // 2026-05-04 — Path to 33 (annual Olympian track) celebration host.
    // Fires once when the user completes all 33 goals of the season; cleared
    // by the overlay's onDismiss. The badge is minted server-side by
    // `complete_olympian_season_if_done` (called at the tail of
    // `unlock_achievement` for any olympian-tagged row), and surfaced here
    // via `OlympianPathService.pendingSeasonCompletion`.
    @StateObject private var olympianPathService = OlympianPathService.shared

    // Bridge state for the celebration share button — when set, presents
    // the share sheet via standard `ShareLink` plumbing.
    @State private var olympianShareItem: OlympianShareItem?

    // Welcome tutorial state - shown once per session when user completes onboarding
    @State private var showWelcomeTutorial = false
    @State private var hasShownTutorialThisSession = false

    // First-screen paywall (post-activation soft-sell). Auto-presented
    // ONCE after the user completes their 3rd workout. Per
    // MONETIZATION_AGENT invariant 7 — never present during onboarding
    // or first 3 workouts. Throttled by `MonetizationState.shared.shouldPresentFirstScreenPaywall`.
    @State private var showFirstScreenPaywall = false

    // Pro Preview expiry modal — fires once when the 7-day Pro
    // Preview window has just lapsed (within 48h grace). Drives the
    // warm cohort to the real paywall (Headspace/Calm pattern).
    @State private var showProPreviewExpiryModal = false

    // Sunday Pro Recap (Phase 5) — set true by the deep-link router
    // (`MainTabView.handleDeepLinkDestination(.proRecap)` →
    // `MonetizationState.requestProRecapPresentation()`). Observed
    // here so the recap cover presents from the root regardless of
    // which tab the user lands on.
    @ObservedObject private var monetizationState = MonetizationState.shared

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Workout.date, ascending: false)],
        predicate: NSPredicate(format: "isCompleted == true")
    ) private var allCompletedWorkouts: FetchedResults<Workout>

    // 2026-04-29 — League Redesign Plan §B1 ship gate.
    // One-time "Your level is now your tier" framing card. Triggered for
    // any existing user with non-zero XP who hasn't seen it yet. Stored
    // separately from `showWelcomeTutorial` because it's an *upgrade*
    // surface (existing users only) — new users never see it.
    @State private var showLevelToTierMigration = false
    @State private var migrationLegacyLevel: Int = 1
    @State private var migrationLegacyTitle: String = ""
    
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

            // 2026-04-29 — League Redesign Plan §B1 ship gate.
            // First-launch-after-update one-time migration card. Triggers
            // once per install for any user with prior XP. Skipped on the
            // onboarding flow (we only want to nudge users already in the
            // main app).
            if shouldShowMainApp, LevelToTierMigrationGate.shouldShow() {
                migrationLegacyLevel = userManager.getLevel()
                migrationLegacyTitle = userManager.getLevelTitle()
                showLevelToTierMigration = true
            }
        }
        .fullScreenCover(isPresented: $showWelcomeTutorial) {
            WelcomeTutorialView(isPresented: $showWelcomeTutorial)
        }
        // First-Screen Paywall (post-activation soft-sell). Wraps in
        // its own fullScreenCover so it composes cleanly with the
        // welcome tutorial above (only presents AFTER tutorial dismiss).
        .fullScreenCover(isPresented: $showFirstScreenPaywall, onDismiss: {
            MonetizationState.shared.markFirstScreenPaywallSeen()
        }) {
            PaywallFirstScreenView(
                onPurchased: { showFirstScreenPaywall = false },
                onContinueFree: { showFirstScreenPaywall = false }
            )
        }
        // Pro Preview Expiry Modal — fires once when the silent
        // 7-day in-app preview lapses. Same fullScreenCover pattern.
        .fullScreenCover(isPresented: $showProPreviewExpiryModal, onDismiss: {
            MonetizationState.shared.markProPreviewExpiryModalShown()
        }) {
            PremiumUpgradeView(triggeringFeature: .lifetime)
        }
        // Sunday Pro Recap (Phase 5) — landing surface for the
        // `fit33://profile/pro-recap` deep-link push. Routed here from
        // `MainTabView.handleDeepLinkDestination(.proRecap)` via the
        // shared `MonetizationState.pendingProRecapPresentation` flag.
        // Pro and free both present the same view; content branches
        // internally on premium status.
        .fullScreenCover(
            isPresented: Binding(
                get: { monetizationState.pendingProRecapPresentation },
                set: { newValue in
                    if !newValue { monetizationState.clearProRecapPresentation() }
                }
            )
        ) {
            ProRecapView()
                .environment(\.managedObjectContext, viewContext)
        }
        // Re-evaluate auto-presentation any time the completed-workout
        // count changes. Cheap (read-only check on UserDefaults) so
        // no debounce needed.
        .onChange(of: allCompletedWorkouts.count) { _, newCount in
            evaluateAutoPaywallPresentation(completedWorkouts: newCount)
        }
        .sheet(isPresented: $showLevelToTierMigration, onDismiss: {
            LevelToTierMigrationGate.markShown()
        }) {
            LevelToTierMigrationCard(
                legacyLevel: migrationLegacyLevel,
                legacyTitle: migrationLegacyTitle,
                onDismiss: {
                    showLevelToTierMigration = false
                }
            )
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
        // 2026-04-29 — League Redesign Plan §B2.
        // Replaces the legacy `LevelUpCelebrationOverlay` (every 100 XP) with
        // `TierPromotionOverlay` (Monday-rollup tier increase only). Fires at
        // most once per week per user. Driven by
        // `WeeklyLeagueService.shared.pendingTierPromotion`.
        .overlay {
            if let event = weeklyLeagueService.pendingTierPromotion {
                TierPromotionOverlay(event: event) {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        weeklyLeagueService.clearPendingTierPromotion()
                    }
                }
                .transition(.opacity.combined(with: .scale))
                .zIndex(999)
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: weeklyLeagueService.pendingTierPromotion)
        // 2026-05-04 — Path to 33 (annual Olympian track) season-completion
        // overlay. Sits at the same zIndex band as the tier-promotion overlay
        // (the two are mutually exclusive in practice — tier promotion fires
        // weekly, Olympian fires once a year on goal #33).
        .overlay {
            if let badge = olympianPathService.pendingSeasonCompletion {
                OlympianCelebrationOverlay(
                    badge: badge,
                    onDismiss: {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            olympianPathService.clearPendingCompletion()
                        }
                    },
                    onShare: {
                        olympianShareItem = OlympianShareItem(badge: badge)
                    }
                )
                .transition(.opacity.combined(with: .scale))
                .zIndex(1000)
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: olympianPathService.pendingSeasonCompletion)
        .sheet(item: $olympianShareItem) { item in
            ShareSheet(items: [item.shareText])
        }
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

            // First-Screen Paywall + Pro Preview Expiry — initial check.
            // Done inside the existing `.task` so we share the same
            // 100ms UserManager-init wait. Both surfaces are throttled
            // to never-spam (each fires at most once per device until
            // explicitly reset).
            await MainActor.run {
                MonetizationState.shared.recomputeProPreview()
                evaluateAutoPaywallPresentation(completedWorkouts: allCompletedWorkouts.count)
                evaluateProPreviewExpiry()
            }
        }
    }

    /// Decides whether to surface `PaywallFirstScreenView` automatically.
    /// Driven by `MonetizationState.shouldPresentFirstScreenPaywall`,
    /// which gates on workout count + premium status + cooldown.
    /// Never presents over the tutorial or the Pro Preview expiry modal.
    @MainActor
    private func evaluateAutoPaywallPresentation(completedWorkouts: Int) {
        guard shouldShowMainApp else { return }
        guard !showWelcomeTutorial,
              !showLevelToTierMigration,
              !showProPreviewExpiryModal else { return }
        guard !showFirstScreenPaywall else { return }
        guard MonetizationState.shared.shouldPresentFirstScreenPaywall(
            completedWorkouts: completedWorkouts
        ) else { return }

        // Tiny delay so we don't fight a tab-switch animation if the
        // user just landed back on the dashboard from Active Workout.
        Task {
            try? await Task.sleep(nanoseconds: 600_000_000)
            await MainActor.run {
                AppLogger.info("Auto-presenting PaywallFirstScreenView (workout #\(completedWorkouts))", category: .general)
                showFirstScreenPaywall = true
            }
        }
    }

    /// Surfaces the Pro Preview expiry modal once, in the 48h grace
    /// window after the silent 7-day in-app preview lapses.
    @MainActor
    private func evaluateProPreviewExpiry() {
        guard shouldShowMainApp else { return }
        guard !showWelcomeTutorial, !showFirstScreenPaywall else { return }
        guard MonetizationState.shared.shouldShowProPreviewExpiryModal else { return }
        AppLogger.info("Auto-presenting Pro Preview expiry modal", category: .general)
        showProPreviewExpiryModal = true
    }
}

#Preview {
    ContentView()
}
