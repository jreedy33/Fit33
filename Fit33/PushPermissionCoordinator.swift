import Foundation
import UIKit
import UserNotifications

// =============================================================================
// PushPermissionCoordinator — single source of truth for the iOS notification
// permission ask (2026-08-01).
// =============================================================================
//
// Before this coordinator existed, three independent code paths could each
// trigger the system permission dialog:
//   1. `NewOnboardingView+Completion.completeOnboarding()` — fired immediately
//      on the user's last onboarding tap.
//   2. `MainTabView.task { ... }` — 1.5s after first MainTabView appearance.
//   3. `PushNotificationService.registerForPushNotifications()` — sometimes
//      called on auth-ready before the MainTabView ask resolved.
//
// Apple only shows the system dialog ONCE per install. Whichever path won
// the race ate the dialog and the others received "already-granted" /
// "already-denied" responses with no UI surface for the user. Worse: the
// onboarding ask preceded any soft-prompt context, so users got the cold
// system dialog with no explanation of WHY the app wanted to send pushes.
//
// Consolidation rules:
//   - There is exactly ONE place in the codebase that calls
//     `UNUserNotificationCenter.requestAuthorization`: this file's
//     `requestSystemPermission()`.
//   - All other callers route through `PushPermissionCoordinator.shared`.
//   - The coordinator REQUIRES a soft-prompt sheet to appear before the
//     system dialog (Phase 4 — `NotificationPrimerSheet`). Until that
//     sheet ships, the coordinator falls back to the "ask immediately"
//     behavior so we don't regress the current cold-dialog UX.
//   - Idempotent: calling `ensureAskedOnce()` from both `MainTabView` and
//     `Fit33App.didAuthenticate` is safe — the second call no-ops.
// =============================================================================

@MainActor
final class PushPermissionCoordinator: ObservableObject {

    static let shared = PushPermissionCoordinator()

    // MARK: - Published state for primer sheet binding

    /// True when the soft-prompt sheet should be presented. Bound by the
    /// MainTabView wrapper. Set by `requestPermissionWithPrimer()`.
    @Published var showPrimerSheet = false

    /// User's last-known authorization status (mirror of
    /// UNUserNotificationCenter.notificationSettings().authorizationStatus).
    /// Updated by `refreshAuthStatus()`.
    @Published var lastAuthStatus: UNAuthorizationStatus = .notDetermined

    // MARK: - State

    private static let primerShownKey = "push_primer_sheet_shown_v1"
    private static let postDenyPromptShownKey = "push_post_deny_prompt_shown_v1"

    /// Set true after the FIRST call to `ensureAskedOnce()` so duplicate
    /// callers no-op for the lifetime of the process. UserDefaults-backed
    /// `primerShownKey` provides cross-launch idempotency.
    private var didAskThisSession = false

    private init() {}

    // MARK: - Public API

    /// Idempotent permission ask. Safe to call from any post-auth path
    /// (MainTabView .task, Fit33App didAuthenticate, etc.). Decides which
    /// flow to run based on current iOS authorization status.
    ///
    /// Returns one of:
    ///   - `.granted` / `.denied` / `.provisional` immediately if the system
    ///     dialog has already been resolved this install.
    ///   - `.notDetermined` AFTER triggering either the primer-sheet flow
    ///     (if `useSoftPrompt: true`) or the system dialog directly.
    @discardableResult
    func ensureAskedOnce(useSoftPrompt: Bool = true) async -> UNAuthorizationStatus {
        if didAskThisSession {
            return await refreshAuthStatus()
        }
        didAskThisSession = true

        let current = await refreshAuthStatus()
        switch current {
        case .notDetermined:
            if useSoftPrompt && !UserDefaults.standard.bool(forKey: Self.primerShownKey) {
                // Show primer sheet — the sheet's "Continue" action calls
                // `requestSystemPermission()` directly. We return the
                // current status (notDetermined) to the caller; the actual
                // grant-result lands on `lastAuthStatus` after the user
                // resolves the sheet + system dialog.
                showPrimerSheet = true
                return .notDetermined
            }
            // No soft-prompt available (e.g. early in app lifecycle before
            // SwiftUI sheets can present) — go straight to system dialog.
            return await requestSystemPermission()

        case .denied:
            // Don't re-ask the system (Apple won't show the dialog anyway).
            // The caller (MainTabView) decides whether to show the
            // "open Settings" alert.
            return .denied

        case .authorized, .provisional, .ephemeral:
            // Already granted in some form — register for remote notifications
            // and return.
            UIApplication.shared.registerForRemoteNotifications()
            return current

        @unknown default:
            return current
        }
    }

    /// Called by the primer sheet's "Continue" / "Sounds good" action. Marks
    /// the primer as shown, then triggers the system dialog. The primer sheet
    /// dismisses itself before this fires.
    @discardableResult
    func requestSystemPermission() async -> UNAuthorizationStatus {
        UserDefaults.standard.set(true, forKey: Self.primerShownKey)
        showPrimerSheet = false

        let granted = await NotificationManager.shared.requestAuthorization()
        let status = await refreshAuthStatus()

        if granted || status == .authorized || status == .provisional {
            UIApplication.shared.registerForRemoteNotifications()
            AppLogger.info("[PUSH] Permission granted; registered for APNs", category: .network)
        } else {
            AppLogger.info("[PUSH] User denied notification permission at primer→system flow", category: .network)
        }
        return status
    }

    /// Called by the primer sheet's "Not now" action. Persists "primer was
    /// shown" so we don't re-show on next launch, but does NOT trigger the
    /// system dialog (saves the one-shot Apple budget for a later
    /// settings-driven re-ask).
    func declinePrimer() {
        UserDefaults.standard.set(true, forKey: Self.primerShownKey)
        showPrimerSheet = false
        AppLogger.info("[PUSH] User declined primer; deferring system dialog", category: .network)
    }

    /// Pull current iOS auth status into `lastAuthStatus`.
    @discardableResult
    func refreshAuthStatus() async -> UNAuthorizationStatus {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        let status = settings.authorizationStatus
        lastAuthStatus = status
        return status
    }

    /// True if the user has been hard-denied AND we haven't shown the
    /// "open Settings" prompt yet. MainTabView consults this once per
    /// install to surface the alert one time.
    func shouldShowPostDenyPrompt() -> Bool {
        guard lastAuthStatus == .denied else { return false }
        return !UserDefaults.standard.bool(forKey: Self.postDenyPromptShownKey)
    }

    func markPostDenyPromptShown() {
        UserDefaults.standard.set(true, forKey: Self.postDenyPromptShownKey)
    }
}
