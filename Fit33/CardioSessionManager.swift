import Foundation
import SwiftUI
import Combine

// MARK: - CardioSessionPhase
//
// Cardio Redesign Phase 1 — Wave 4a.
// State machine for an outdoor cardio session lifecycle. The phase drives
// which UI surface is on screen:
//   • `.idle`        — landing page is showing; no active session
//   • `.goalSetup`   — `CardioGoalSetupView` sheet is up
//   • `.preStart`    — countdown overlay is animating (3 → 2 → 1 → GO)
//   • `.active`      — `OutdoorCardioActiveView` running; GPS engine on
//   • `.paused`      — same view, controls reflect pause state
//   • `.ended`       — pre-recap brief moment between End tap + recap fade
//   • `.recap`       — `CardioRecapView` (Wave 5a) showing route + splits
//   • `.saved`       — recap dismissed; back to idle on next idle()
//
// The phase is a CLIENT concern — the persistent state machine on the
// server side is just `cardio_workouts` row creation + the LP / quest
// fanout fired by the `record_cardio_workout` RPC.
enum CardioSessionPhase: String, Equatable, Codable {
    case idle
    case goalSetup
    case preStart
    case active
    case paused
    case ended
    case recap
    case saved
}

// MARK: - CardioSessionSnapshot
//
// On-disk shape used for cold-launch recovery. Only persisted while a
// session is in `.active` / `.paused` / `.ended`. Cleared on `.saved`
// or on explicit user discard.
//
// Intentionally small — we DO NOT persist the route polyline / splits
// here because `RunningManager` already keeps those in memory and a true
// cold-launch recovery (the user actually killed the app mid-run) is
// best-effort: we recover the metadata + offer to save what HealthKit
// captured for that window.
struct CardioSessionSnapshot: Codable {
    let phase: CardioSessionPhase
    let activityRaw: String          // CardioActivity.rawValue
    let goalTypeKey: String          // RunGoalType.rawKey
    let goalValue: Double
    let externalId: String           // SHA-256 stable id (matches the RPC's idempotency key)
    let startedAt: Date
    let savedAt: Date                // when this snapshot was last written
}

// MARK: - CardioSessionManager
//
// Singleton orchestrator for the cardio session lifecycle. This DOES
// NOT replace `RunningManager` (the GPS engine) — it sits on top of it
// and exposes a clean phase + countdown + recovery surface to the new
// `OutdoorCardioActiveView`.
//
// Single source of truth for "is there a cardio workout in progress?".
// The legacy `RunningManager.isRunning` boolean is still used internally
// by the engine, but external callers (Dashboard widget, MainTabView
// gate, etc.) should prefer `CardioSessionManager.shared.phase`.
@MainActor
final class CardioSessionManager: ObservableObject {
    static let shared = CardioSessionManager()

    // MARK: - Published surface
    @Published private(set) var phase: CardioSessionPhase = .idle
    /// Activity selected from the goal-setup sheet. Populated on
    /// `prepare(...)` and read by the active view to drive the GPS
    /// engine + UI accents.
    @Published private(set) var pendingActivity: CardioActivity = .run
    /// Goal selected from the goal-setup sheet (or none).
    @Published private(set) var pendingGoal: RunGoalType = .none
    @Published private(set) var pendingGoalValue: Double = 0

    /// Live countdown value (3 → 2 → 1 → nil). When non-nil the active
    /// view overlays the cinematic countdown card. nil during normal
    /// `.active` / `.paused` / `.recap` phases.
    @Published private(set) var countdownValue: Int? = nil

    /// Result snapshot captured at `.ended`. Read by the recap view.
    @Published private(set) var endedResult: RunWorkoutResult? = nil

    /// `true` when a snapshot was loaded from disk on launch and the
    /// user hasn't yet decided whether to recover or discard. Used by
    /// `Fit33App` to surface the recovery prompt.
    @Published private(set) var hasPendingRecovery: Bool = false
    @Published private(set) var pendingRecoverySnapshot: CardioSessionSnapshot? = nil

    // MARK: - Minimize / Restore (2026-05-02 per-user request)
    //
    // The active outdoor-cardio screen is presented via a GLOBAL
    // `.fullScreenCover` mounted on `MainTabView`. The user can tap a
    // "return to app" chevron in the top-left of the active screen to
    // hide the cover WITHOUT ending the workout — the GPS engine, splits,
    // pace, calories, Live Activity all keep running. Tapping the (red)
    // Workout tab while a session is minimized restores it.
    //
    // `isMinimized` is the ONLY thing that flips to hide / restore the
    // overlay; the phase machine is unchanged. `isPresentingActive`
    // computed below combines phase + minimized into the binding the
    // `MainTabView` cover observes.
    @Published var isMinimized: Bool = false

    /// `true` when there's a session in flight that the global active
    /// cover should be presenting. Computed off `phase` + `isMinimized`.
    /// `MainTabView` binds its global `.fullScreenCover` to this.
    var isPresentingActive: Bool {
        guard !isMinimized else { return false }
        switch phase {
        case .preStart, .active, .paused, .ended, .recap: return true
        case .idle, .goalSetup, .saved:                   return false
        }
    }

    /// `true` when there's a live workout (regardless of minimized state).
    /// `MainTabView` reads this to drive the red "Workout" tab indicator
    /// and re-route taps to `restore()` instead of switching tabs.
    var hasLiveSession: Bool {
        switch phase {
        case .preStart, .active, .paused: return true
        default:                          return false
        }
    }

    // MARK: - Private state
    private let userDefaults = UserDefaults.standard
    private let snapshotKey = "fit33.cardioSession.snapshot.v1"
    /// Recovery window: we only auto-offer to recover snapshots saved
    /// in the last 4h. Older snapshots are stale (user moved on, the
    /// HealthKit reconciliation will pick up anything actually tracked).
    private let recoveryMaxAge: TimeInterval = 4 * 60 * 60
    /// Pinned external_id used by the current session. Matches the
    /// SHA-256 stable id that `SupabaseManager.saveCardioWorkout`
    /// derives, so the RPC's idempotency check fires on retry.
    private(set) var currentExternalId: String? = nil

    /// Tracked locally because `RunningManager.startTime` is `private`.
    /// Set when we transition into `.active`; cleared on dismissToIdle().
    private var sessionStartedAt: Date? = nil

    private var cancellables = Set<AnyCancellable>()

    private init() {
        // On singleton init, load any pending snapshot so the launch
        // prompt can surface. We DO NOT auto-resume — the user has to
        // explicitly opt in via the prompt.
        loadSnapshotForRecovery()

        // Reflect engine pause/resume state into our phase. The user
        // might tap Pause from the active view OR from the Lock Screen
        // Live Activity; both routes flip `RunningManager.isPaused`.
        RunningManager.shared.$isPaused
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isPaused in
                guard let self else { return }
                if isPaused, self.phase == .active {
                    self.phase = .paused
                    self.persistSnapshotIfNeeded()
                } else if !isPaused, self.phase == .paused {
                    self.phase = .active
                    self.persistSnapshotIfNeeded()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Public lifecycle

    /// Step 1 — open the goal-setup sheet for a given activity. The new
    /// `CardioLandingView` calls this when a hero tile / preset chip is
    /// tapped. Idempotent — calling twice with the same activity just
    /// re-opens the sheet.
    func prepare(activity: CardioActivity) {
        pendingActivity = activity
        pendingGoal = .none
        pendingGoalValue = 0
        phase = .goalSetup
    }

    /// Step 2 — set the goal selection from the goal-setup sheet. Called
    /// when the user taps a chip (Open / Time / Distance / Calories) +
    /// dials in the value, then taps Start.
    func setGoal(_ goal: RunGoalType, value: Double = 0) {
        pendingGoal = goal
        pendingGoalValue = value
    }

    /// Step 3 — kick off the cinematic 3-2-1 countdown, then start the
    /// engine. Transitions: goalSetup → preStart → active.
    /// The countdown runs for 3s; on tap-anywhere users can skip via
    /// `skipCountdown()`.
    func start() {
        guard phase == .goalSetup || phase == .idle else { return }

        // Apply goal to the engine BEFORE start so the goalRing renders
        // the right denominator on first frame.
        RunningManager.shared.setGoal(type: pendingGoal, value: pendingGoalValue)

        // Fresh session — make sure we're not still minimized from a
        // previous run that ended before the cover was restored.
        isMinimized = false

        phase = .preStart
        countdownValue = 3
        Task { @MainActor in
            await runCountdown()
        }
    }

    /// Bail out of the countdown and start immediately. Wired to a tap
    /// gesture on the countdown overlay. Plays a haptic.
    func skipCountdown() {
        guard phase == .preStart else { return }
        countdownValue = nil
        beginActive()
    }

    /// Hide the active-cardio cover without ending the workout — the GPS
    /// engine + Live Activity + audio cues keep running so the user can
    /// browse other tabs. Wired to the chevron-down "return" button in
    /// the top-left of `OutdoorCardioActiveView`.
    func minimize() {
        guard hasLiveSession else { return }
        isMinimized = true
        // Tiny haptic so the user feels the "tucked away" gesture.
        HapticManager.impact(.soft)
        AppLogger.debug("📥 [CARDIO] Session minimized — workout continues in background", category: .ui)
    }

    /// Re-present the active-cardio cover. Called when the user taps the
    /// (red) Workout tab while a session is minimized.
    func restore() {
        // Even safe to call when not minimized — no-ops.
        guard isMinimized else { return }
        isMinimized = false
        AppLogger.debug("📤 [CARDIO] Session restored — re-presenting active cover", category: .ui)
    }

    /// Pause the running session. Mirrors `RunningManager.pauseRun` but
    /// also flips our phase. Safe to call from any UI surface.
    func pause() {
        guard phase == .active else { return }
        RunningManager.shared.pauseRun()
        phase = .paused
        persistSnapshotIfNeeded()
    }

    /// Resume from pause.
    func resume() {
        guard phase == .paused else { return }
        RunningManager.shared.resumeRun()
        phase = .active
        persistSnapshotIfNeeded()
    }

    /// End the session — captures the final `RunWorkoutResult` snapshot
    /// from the engine, transitions to `.ended` then `.recap`. The recap
    /// view does the actual save fanout via its onAppear handler.
    func end() {
        guard phase == .active || phase == .paused else { return }
        // `stopRun()` returns nil only if the engine wasn't running.
        // Guard locally so we don't push a half-empty recap if the
        // engine was somehow torn down between phase + call.
        guard let result = RunningManager.shared.stopRun() else {
            phase = .idle
            clearSnapshot()
            return
        }
        // If the session was minimized when it ended (e.g. Live Activity
        // "End" tap from outside the cover), un-minimize so the recap
        // surfaces — otherwise the user has no way to see it.
        isMinimized = false
        endedResult = result
        phase = .ended
        // Brief 250ms beat so the active screen can do a quick fade
        // before the recap appears. Keeps the transition cinematic.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            phase = .recap
        }
    }

    /// Mark the session as fully saved. Called by `CardioRecapView`
    /// once the Supabase RPC + UserManager fanout completes. Clears
    /// the recovery snapshot so cold-launch doesn't re-prompt.
    func markSaved() {
        phase = .saved
        clearSnapshot()
        endedResult = nil
        currentExternalId = nil
        // Cover dismisses naturally because `isPresentingActive` returns
        // false for `.saved`. Clear minimize so the next session starts
        // with a clean slate.
        isMinimized = false
        // Belt-and-suspenders: `RunningManager.stopRun()` already ended
        // the Live Activity inside `end()`. If anything raced (cold-launch
        // recovery, manual `markSaved()` after a force-quit, etc.) the
        // surviving activity is dismissed here.
        RunningManager.shared.forceEndAnyLiveActivity()
    }

    /// Dismiss the recap and return to idle. Called on the recap's
    /// "Done" button or sheet swipe-down.
    func dismissToIdle() {
        phase = .idle
        clearSnapshot()
        endedResult = nil
        currentExternalId = nil
        sessionStartedAt = nil
        isMinimized = false
        // Same belt-and-suspenders as `markSaved()` — guarantees the
        // lock-screen widget can never outlive the in-app session.
        RunningManager.shared.forceEndAnyLiveActivity()
    }

    // MARK: - Cold-launch recovery

    /// Apply the recovered snapshot — the user tapped "Resume" on the
    /// launch prompt. We can't actually re-attach to a now-dead GPS
    /// session, so this just routes to the recap with the metadata
    /// snapshot so the user can decide to save what they have OR
    /// discard.
    func acceptRecovery() {
        guard let snap = pendingRecoverySnapshot else { return }
        // Build a partial result the recap can render. Distance / route
        // are 0 / empty — we only kept metadata. The recap will offer
        // a "Save what we have" or "Discard" choice.
        let now = Date()
        let result = RunWorkoutResult(
            startTime: snap.startedAt,
            endTime: now,
            duration: now.timeIntervalSince(snap.startedAt),
            distance: 0,
            averagePace: 0,
            calories: 0,
            routeCoordinates: [],
            simplifiedRouteCoordinates: [],
            splits: [],
            activityType: CardioActivity(rawValue: snap.activityRaw) ?? .run,
            goalType: .none,
            goalValue: snap.goalValue,
            goalAchieved: false,
            averageHeartRate: nil,
            elevationGain: 0,
            gpsAvgAccuracyMeters: 0
        )
        endedResult = result
        currentExternalId = snap.externalId
        pendingActivity = result.activityType
        phase = .recap
        hasPendingRecovery = false
        pendingRecoverySnapshot = nil
    }

    /// User dismissed the recovery prompt. Drop the snapshot.
    func discardRecovery() {
        clearSnapshot()
        hasPendingRecovery = false
        pendingRecoverySnapshot = nil
        // The user is explicitly walking away from a recovered session;
        // the lock-screen Live Activity must follow. Without this the
        // widget would persist on the lock screen until iOS's stale-after
        // timer expired.
        RunningManager.shared.forceEndAnyLiveActivity()
    }

    // MARK: - Internals

    private func runCountdown() async {
        for i in stride(from: 3, through: 1, by: -1) {
            countdownValue = i
            HapticManager.impact(.medium)
            try? await Task.sleep(for: .seconds(1))
            // If user skipped or aborted mid-countdown, bail.
            if phase != .preStart { return }
        }
        countdownValue = nil
        beginActive()
    }

    private func beginActive() {
        guard phase == .preStart else { return }
        // Generate a stable external_id NOW so any retry uses the same.
        // The same id will flow into RecordCardioPayload at save time.
        currentExternalId = UUID().uuidString
        sessionStartedAt = Date()
        RunningManager.shared.startRun(
            activityType: pendingActivity,
            goal: pendingGoal,
            goalValue: pendingGoalValue
        )
        phase = .active
        persistSnapshotIfNeeded()
        HapticManager.notification(.success)
    }

    // MARK: - Persistence

    private func persistSnapshotIfNeeded() {
        guard phase == .active || phase == .paused else { return }
        guard let externalId = currentExternalId else { return }
        let snap = CardioSessionSnapshot(
            phase: phase,
            activityRaw: pendingActivity.rawValue,
            goalTypeKey: pendingGoal.rawKey,
            goalValue: pendingGoalValue,
            externalId: externalId,
            startedAt: sessionStartedAt ?? Date(),
            savedAt: Date()
        )
        if let data = try? JSONEncoder().encode(snap) {
            userDefaults.set(data, forKey: snapshotKey)
        }
    }

    private func loadSnapshotForRecovery() {
        guard let data = userDefaults.data(forKey: snapshotKey) else { return }
        guard let snap = try? JSONDecoder().decode(CardioSessionSnapshot.self, from: data) else {
            // Corrupt blob — drop it.
            userDefaults.removeObject(forKey: snapshotKey)
            return
        }
        // Stale snapshots (>4h since last save) are ignored. The user
        // moved on; HealthKit reconciliation handles anything actually
        // tracked during that window.
        if Date().timeIntervalSince(snap.savedAt) > recoveryMaxAge {
            userDefaults.removeObject(forKey: snapshotKey)
            return
        }
        pendingRecoverySnapshot = snap
        hasPendingRecovery = true
    }

    private func clearSnapshot() {
        userDefaults.removeObject(forKey: snapshotKey)
    }
}

