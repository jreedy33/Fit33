//
//  WelcomeBriefRow.swift
//  Fit33
//
//  Replacement subtitle for the dashboard welcome card. Renders a
//  multi-line tappable Daily Brief composed by `DailyBriefEngine`
//  via `DailyBriefStore`. Lives inside `DashboardWelcomeBriefWrapper`
//  (PE invariant 9 — widget isolation; the wrapper owns the
//  `@StateObject` so quest/wearable updates don't recompute the
//  whole `DashboardView`).
//
//  Visual contract (Phase 7b — 2026-04-27):
//    Line 1 — `headline` (semibold, primary color, max 2 lines)
//    Line 2 — `body` (medium, secondary color, max 2 lines)
//
//  The third italic line ("rotatingInsight") was retired here and
//  the engine instead PROMOTES insight content INTO the body when
//  the user has no urgent debt to action — keeps the welcome card
//  to a clean two-line read while still surfacing trends + stats.
//  See `DailyBriefEngine.decideMode` + `buildInsightBody`.
//
//  Note (2026-04-27): the chip strip was removed from the welcome
//  card — text-only read is cleaner at this scale. `brief.chips`
//  is still populated by `DailyBriefEngine` for analytics / future
//  surfaces, but no longer rendered here.
//
//  Routing: row tap → `cta` dispatched via `DashboardBriefRouter`
//  to `dashboardNavPath` / `WorkoutManager.shouldNavigateToAutoGen`.
//

import SwiftUI

// MARK: - Wrapper (widget isolation)

/// Hosts the brief row + owns the store as `@StateObject`. Mounted
/// from `DashboardView+Header.headerView` in place of the old
/// single-line motivational subtitle.
struct DashboardWelcomeBriefWrapper: View {
    @Binding var navigationPath: NavigationPath
    @EnvironmentObject var workoutManager: WorkoutManager
    @StateObject private var store = DailyBriefStore.shared
    /// Tracks the impression id we last logged so we don't double-log
    /// the same brief — composedAt is the cheap dedup key.
    @State private var lastLoggedComposedAt: Date?
    /// Most recent impression id (returned by the telemetry insert).
    /// Tap log inserts reference it.
    @State private var currentImpressionId: UUID?
    /// Phase 5 (2026-04-27 — Daily Mission Unification): readiness
    /// drill-down sheet binding. Owned by the wrapper, not the
    /// router, so the sheet's presentation context is the welcome
    /// card itself — avoids the nested-NavigationStack bounce
    /// that bit `SimpleMealPlanView`.
    @State private var showReadinessSheet = false

    init(navigationPath: Binding<NavigationPath>) {
        self._navigationPath = navigationPath
    }

    var body: some View {
        WelcomeBriefRow(
            brief: store.brief,
            isComputing: store.isComputing,
            onTap: handleTap
        )
        .task {
            // First paint after dashboard mounts. Subsequent recomputes
            // come through the Combine subs in `DailyBriefStore`.
            store.refresh(force: false)
        }
        .onChange(of: store.brief?.composedAt) { _, newDate in
            guard let newDate, newDate != lastLoggedComposedAt,
                  let brief = store.brief else { return }
            lastLoggedComposedAt = newDate
            // Fire-and-forget impression log. Once the impression id
            // comes back, write it to the store so the quest-
            // completion observer in `DailyBriefStore` can attach
            // conversions to the right row (Phase 6).
            Task {
                let id = await BriefTelemetry.logImpression(brief: brief)
                await MainActor.run {
                    self.currentImpressionId = id
                    DailyBriefStore.shared.resetCompletionTrackingForNewImpression(id)
                }
            }
        }
        .sheet(isPresented: $showReadinessSheet) {
            ReadinessDrillDownSheet()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    private func handleTap() {
        guard let brief = store.brief else { return }
        HapticManager.impact(.light)
        // Phase 5 (2026-04-27): the .openReadiness CTA presents the
        // drill-down sheet locally instead of routing through the
        // dashboard nav path (which can't host a sheet from the
        // welcome row's depth without re-introducing the
        // nested-stack bounce).
        if case .openReadiness = brief.cta {
            showReadinessSheet = true
        } else {
            DashboardBriefRouter.route(
                cta: brief.cta,
                navigationPath: $navigationPath,
                workoutManager: workoutManager
            )
        }
        if let impressionId = currentImpressionId {
            Task { await BriefTelemetry.logTap(impressionId: impressionId) }
        }
    }
}

// MARK: - Row

struct WelcomeBriefRow: View {
    let brief: DailyBrief?
    let isComputing: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                if let brief {
                    // Mission micro-label moved to the parent header
                    // (2026-04-27 follow-up) — replaces the old
                    // "Welcome back," line at the very top of the
                    // welcome card so the narrative reads top-down:
                    // MISSION → user name → headline. The duplicate
                    // label inline here was redundant once the
                    // parent surface adopted the framing.
                    //
                    // Phase 7b (2026-04-27 — Insight Promotion): the
                    // separate italic `rotatingLine` was retired —
                    // the engine now blends trends + stats INTO the
                    // body itself when there's no urgent debt to
                    // action, so this view only renders the
                    // headline/body pair.
                    bodyAndChevron(brief)
                } else {
                    placeholder
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
    }

    // MARK: - Sub-views

    /// Headline + body stacked vertically. The trailing chevron was
    /// removed (2026-04-27) — the whole row is still tappable and the
    /// CTA is conveyed by the headline copy itself, so the affordance
    /// arrow read as visual noise at the welcome-card scale.
    ///
    /// Spacing (2026-04-27 follow-up): bumped from 2pt to `.xxs` (4pt)
    /// so the headline / body pair has a clean breath between them
    /// — the previous 2pt was reading as cramped, especially when
    /// the body wraps to two lines.
    private func bodyAndChevron(_ brief: DailyBrief) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(brief.headline)
                .font(.ds_heading3)
                .foregroundColor(.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)
            Text(brief.body)
                .font(.ds_bodySmall)
                .foregroundColor(.secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var placeholder: some View {
        HStack(spacing: Spacing.xs) {
            if isComputing {
                ProgressView()
                    .scaleEffect(0.7)
            }
            Text("Pulling today's brief…")
                .font(.ds_bodySmall)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Helpers

    private var accessibilityLabel: String {
        guard let brief else { return "Daily brief loading" }
        return "Daily brief: \(brief.headline). \(brief.body)"
    }

    private var accessibilityHint: String {
        guard let brief else { return "" }
        switch brief.cta {
        case .startAutoWorkout: return "Tap to start a recommended workout"
        case .startRecoveryDay: return "Tap to start your recovery routine"
        case .openMealLog: return "Tap to open your meal log"
        case .logWater: return "Tap to log water"
        case .openChallenge: return "Tap to open your challenge"
        case .openReadiness: return "Tap to view today's readiness"
        case .openWeightLog: return "Tap to log weight"
        case .focusQuest: return "Tap to highlight the matching daily goal"
        case .none: return ""
        }
    }
}

// MARK: - Telemetry

/// Fire-and-forget impression + tap logger. Backed by
/// `daily_brief_impressions` / `daily_brief_taps` (migration
/// `20260701`). Never blocks the UI; auth-guarded per Data
/// invariant 26 — silently skips when user isn't authenticated.
enum BriefTelemetry {
    private static func userId() -> UUID? {
        guard SupabaseManager.shared.isAuthenticated else { return nil }
        return SupabaseManager.shared.currentUser?.id
    }

    /// Inserts a new impression row and returns the inserted id, or
    /// nil if the write failed / user wasn't authenticated.
    static func logImpression(brief: DailyBrief) async -> UUID? {
        guard let userId = userId() else { return nil }

        struct ImpressionInsert: Encodable {
            let user_id: String
            let capacity_band: String
            let capacity_source: String
            let debt_kind: String
            let goal_family: String
            let has_booster: Bool
            let cta_code: String
            let source_trace: String?
            let client_timezone: String?
            // Phase 6 (2026-04-27): decision signature so analytics
            // can group impressions by Decision-shape, not just by
            // template-shape (template copy can iterate while the
            // underlying decision stays stable).
            let decision_signature: String?
        }

        // Best-effort parse of the trace breadcrumb for analytics.
        let band = brief.sourceTrace.first(where: { $0.hasPrefix("capacity:") })?
            .components(separatedBy: ":").dropFirst().first ?? "unknown"
        let source = brief.sourceTrace.first(where: { $0.hasPrefix("capacity:") })?
            .components(separatedBy: ":").dropFirst(2).first ?? "none"
        let debtKind = brief.sourceTrace.first(where: { $0.hasPrefix("debt:") })?
            .components(separatedBy: ":").dropFirst().first ?? "allClear"
        let goal = brief.sourceTrace.first(where: { $0.hasPrefix("goal:") })?
            .components(separatedBy: ":").dropFirst().first ?? "generalFitness"
        let booster = brief.sourceTrace.contains(where: { $0.hasPrefix("booster:") })

        let row = ImpressionInsert(
            user_id: userId.uuidString,
            capacity_band: String(band),
            capacity_source: String(source),
            debt_kind: String(debtKind),
            goal_family: String(goal),
            has_booster: booster,
            cta_code: BriefCTACoder.code(for: brief.cta),
            source_trace: brief.sourceTrace.joined(separator: ","),
            client_timezone: TimeZone.current.identifier,
            decision_signature: brief.decision?.signature
        )

        struct Inserted: Decodable { let id: UUID }
        do {
            let result: [Inserted] = try await SupabaseManager.shared.supabaseClient
                .from("daily_brief_impressions")
                .insert(row)
                .select("id")
                .execute()
                .value
            return result.first?.id
        } catch {
            AppLogger.debug("[BriefTelemetry] impression insert skipped: \(error)", category: .general)
            return nil
        }
    }

    static func logTap(impressionId: UUID) async {
        guard let userId = userId() else { return }
        struct TapInsert: Encodable {
            let impression_id: String
            let user_id: String
        }
        let row = TapInsert(impression_id: impressionId.uuidString, user_id: userId.uuidString)
        do {
            try await SupabaseManager.shared.supabaseClient
                .from("daily_brief_taps")
                .insert(row)
                .execute()
        } catch {
            AppLogger.debug("[BriefTelemetry] tap insert skipped: \(error)", category: .general)
        }
    }

    /// Phase 6 (2026-04-27 — Daily Mission Unification): append a
    /// completed quest_key to `daily_brief_impressions
    /// .completed_quest_keys` (and stamp `completed_at` on first
    /// append). Auth-pinned + idempotent server-side via the
    /// `append_brief_completed_quest` SECURITY DEFINER RPC. Fire-
    /// and-forget — never blocks quest completion celebration.
    static func logQuestCompletion(impressionId: UUID, questKey: String) async {
        guard userId() != nil else { return }
        struct AppendParams: Encodable {
            let p_impression_id: String
            let p_quest_key: String
        }
        let params = AppendParams(
            p_impression_id: impressionId.uuidString,
            p_quest_key: questKey
        )
        do {
            try await SupabaseManager.shared.supabaseClient
                .rpc("append_brief_completed_quest", params: params)
                .execute()
        } catch {
            AppLogger.debug("[BriefTelemetry] quest completion log skipped: \(error)", category: .general)
        }
    }
}

// MARK: - Router

/// Tap-handler. Translates a `BriefCTA` into either an append on the
/// dashboard's `NavigationPath` or a `WorkoutManager` flag flip — the
/// same routes a manual button tap would take, so deep-link state
/// stays canonical.
enum DashboardBriefRouter {
    @MainActor
    static func route(cta: BriefCTA, navigationPath: Binding<NavigationPath>, workoutManager: WorkoutManager) {
        switch cta {
        case .startAutoWorkout:
            // Mirror the dashboard "Auto Workout" button — the
            // generator picks the right split based on readiness +
            // recent muscles. Capacity-veto already happens upstream
            // so red day → auto-gen returns a recovery template
            // (FE invariant 23).
            workoutManager.shouldNavigateToAutoGen = true
        case .startRecoveryDay:
            workoutManager.shouldNavigateToAutoGen = true
        case .openMealLog, .openWeightLog, .logWater:
            // Hydration + weight live in the meal/macros surface
            // today. We jump tabs (Nutrition is `selectedTab == 3`)
            // rather than push `SimpleMealPlanView` onto the
            // dashboard's NavigationStack — that view nests its own
            // NavigationStack and auto-bounces back to root when
            // pushed (PE invariant 6). Cross-tab navigation flag
            // matches the existing `shouldNavigateToWorkoutTab`
            // pattern so MainTabView is the single source of truth
            // for which tab is active.
            workoutManager.shouldNavigateToMealsTab = true
        case .openChallenge(let id):
            if let challenge = ChallengeService.shared.activeChallenges.first(where: { $0.challengeId == id }) {
                navigationPath.wrappedValue.append(challenge)
            }
        case .focusQuest(let key):
            // Phase 3 (2026-04-27 — Daily Mission Unification):
            // signal to `DashboardQuestsWrapper` to scroll to + glow
            // the matching quest card. The wrapper owns the
            // `@StateObject DailyQuestService.shared` and
            // observes `DailyBriefStore.shared.pendingQuestFocus`.
            DailyBriefStore.shared.pendingQuestFocus = key
        case .openReadiness:
            // Phase 5 (2026-04-27): wired in `WelcomeBriefRow.body`
            // via a `.sheet(isPresented:)` modifier instead of from
            // the router so the sheet's presentation context is the
            // welcome row itself (avoids the same nested-stack
            // bounce that bit us with the meal-log path). Router is
            // a no-op here — the row sets a separate flag.
            break
        case .none:
            break
        }
    }
}
