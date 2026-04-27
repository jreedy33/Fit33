//
//  DailyBriefStore.swift
//  Fit33
//
//  `@MainActor` ObservableObject that owns today's `DailyBrief` and
//  recomposes it whenever any source service updates. Drives the
//  Daily Brief row inside `DashboardWelcomeBriefWrapper` (PE
//  invariant 9 — widget isolation).
//
//  Caching contract (mirrors `RecommendationCache`):
//    * Cold-start: hydrates from `UserDefaults` synchronously in
//      `init()` so the welcome card paints the last known brief
//      with no flicker on cold launch.
//    * Cache scope: same calendar day only — yesterday's "5k steps
//      to go" must never bleed into today's brief.
//    * Recompose throttle: 30s in-process; bypassable via
//      `refresh(force: true)`.
//
//  Subscriptions (Combine):
//    * `ReadinessService` — band/score changes redraw the chips.
//    * `DailyQuestService` `quests` change — covers PE invariant
//      25b (welcome card recomposes when a quest ticks complete).
//    * `MealService.todaysMeals` — protein deficit can flip to
//      `.allClear` when the user logs a meal.
//    * `HydrationService.todaySummary` — same shape.
//    * `WhoopService.todayRecovery` / `OuraService.todayReadiness`
//      — drive the Capacity facet.
//
//  All subs route through one debounced sink so a burst of changes
//  produces one recompute.
//

import Foundation
import SwiftUI
import Combine

@MainActor
final class DailyBriefStore: ObservableObject {
    static let shared = DailyBriefStore()

    @Published private(set) var brief: DailyBrief?
    @Published private(set) var isComputing = false
    /// Phase 2 (2026-04-27): quest keys on today's slate that the
    /// brief considers "matching" its debt + capacity. Published
    /// separately from `brief` so quest cards can highlight without
    /// recomposing the whole brief view tree (PE invariant 9 —
    /// widget isolation; the brief view tree is heavier than the
    /// quest cards). Always in sync with `brief?.decision?.linkedQuestKeys`
    /// — read this from a quest-card wrapper, read the brief itself
    /// from the welcome card.
    @Published private(set) var linkedQuestKeys: [String] = []
    /// Phase 3 (2026-04-27): set by `DashboardBriefRouter` when the
    /// user taps a brief whose CTA is `.focusQuest`. The
    /// `DashboardQuestsWrapper` observes this, scrolls to the
    /// matching card, applies a glow ring for ~1.2s, then nils it
    /// back. `@Published` so SwiftUI subscribers fire on every set,
    /// including identical key (re-tap re-fires the glow).
    @Published var pendingQuestFocus: String?

    /// Phase 6 (2026-04-27): impression id of the currently-surfaced
    /// brief, written by `DashboardWelcomeBriefWrapper` after a
    /// successful `BriefTelemetry.logImpression` insert. Used by
    /// the quest-completion observer below to attach the conversion
    /// to the right impression row in `daily_brief_impressions`.
    /// Not Codable — lives only in memory.
    var currentImpressionId: UUID?
    /// Phase 6: tracks which linked quest keys we've already logged
    /// as completed for the current impression so we don't double-
    /// fire the RPC if the quest list re-publishes (server fanout
    /// can flip is_completed multiple times within a session).
    private var loggedCompletionsForImpression: Set<String> = []

    private var cancellables: Set<AnyCancellable> = []
    private var inflightTask: Task<Void, Never>?
    private var lastComposedAt: Date?
    private static let throttleInterval: TimeInterval = 30
    private static let cacheKey = "fit33.dailyBrief.v1"

    private init() {
        // Cold-start hydration. Same-day-only.
        if let cached = Self.readCache() {
            self.brief = cached
            self.linkedQuestKeys = cached.decision?.linkedQuestKeys ?? []
        }
        wireUpSubscriptions()
    }

    // MARK: - Public API

    /// Recompose the brief. Throttled to once per 30s unless `force`.
    /// Multiple in-flight calls coalesce — the last `force` wins.
    func refresh(force: Bool = false) {
        if !force, let last = lastComposedAt,
           Date().timeIntervalSince(last) < Self.throttleInterval {
            return
        }
        // Cancel a stale compute so we don't write an older brief on
        // top of a newer one.
        inflightTask?.cancel()
        inflightTask = Task { [weak self] in
            guard let self else { return }
            await self.composeNow()
        }
    }

    // MARK: - Compose

    private func composeNow() async {
        guard !isComputing else { return }
        isComputing = true
        defer { isComputing = false }

        let streak = Int(UserManager.shared.currentUser?.currentStreak ?? 0)
        let new = await DailyBriefEngine.shared.compose(streak: streak)
        guard !Task.isCancelled else { return }
        self.brief = new
        self.linkedQuestKeys = new.decision?.linkedQuestKeys ?? []
        self.lastComposedAt = Date()
        Self.writeCache(new)
        AppLogger.debug("[DailyBrief] composed: \(new.headline) — trace=\(new.sourceTrace.joined(separator: ",")) linked=\(self.linkedQuestKeys)", category: .ui)
    }

    // MARK: - Subscriptions

    private func wireUpSubscriptions() {
        // Single debounced trigger so a burst of `@Published` changes
        // (e.g. quest progress + step update + readiness recompute all
        // landing in the same second) produces one recompute, not three.
        let trigger = PassthroughSubject<Void, Never>()
        trigger
            .debounce(for: .seconds(1.0), scheduler: DispatchQueue.main)
            .sink { [weak self] in self?.refresh(force: false) }
            .store(in: &cancellables)

        // Readiness band/score.
        ReadinessService.shared.$todayReadiness
            .removeDuplicates()
            .sink { _ in trigger.send() }
            .store(in: &cancellables)

        // Quest list.
        DailyQuestService.shared.$quests
            .map { $0.map(\.isCompleted) }
            .removeDuplicates()
            .sink { _ in trigger.send() }
            .store(in: &cancellables)

        // Phase 6 (2026-04-27 — Daily Mission Unification): observe
        // quest completions and log a conversion against the current
        // brief impression when the completed quest's key is in
        // `linkedQuestKeys`. Fire-and-forget — never blocks the
        // user's completion celebration. Idempotent via
        // `loggedCompletionsForImpression`.
        DailyQuestService.shared.$quests
            .sink { [weak self] quests in
                self?.logCompletionsForLinkedQuests(quests)
            }
            .store(in: &cancellables)

        // Today's meals (protein deficit pivot).
        MealService.shared.$todaysMeals
            .map { $0.count }
            .removeDuplicates()
            .sink { _ in trigger.send() }
            .store(in: &cancellables)

        // Hydration.
        HydrationService.shared.$todaySummary
            .removeDuplicates(by: { $0?.totalMl == $1?.totalMl })
            .sink { _ in trigger.send() }
            .store(in: &cancellables)

        // WHOOP capacity.
        WhoopService.shared.$todayRecovery
            .removeDuplicates(by: { $0?.recoveryScore == $1?.recoveryScore })
            .sink { _ in trigger.send() }
            .store(in: &cancellables)

        // Oura capacity.
        OuraService.shared.$todayReadiness
            .removeDuplicates(by: { $0?.score == $1?.score })
            .sink { _ in trigger.send() }
            .store(in: &cancellables)
    }

    // MARK: - Phase 6 — Quest completion telemetry

    /// Find any linked quest that just ticked complete and log the
    /// conversion against the current brief impression. Caller is
    /// the Combine sub on `DailyQuestService.$quests`.
    private func logCompletionsForLinkedQuests(_ quests: [DailyQuest]) {
        guard let impressionId = currentImpressionId, !linkedQuestKeys.isEmpty else { return }
        let linkedSet = Set(linkedQuestKeys)
        for q in quests {
            guard q.isCompleted,
                  linkedSet.contains(q.questKey),
                  !loggedCompletionsForImpression.contains(q.questKey)
            else { continue }
            loggedCompletionsForImpression.insert(q.questKey)
            let key = q.questKey
            Task {
                await BriefTelemetry.logQuestCompletion(impressionId: impressionId, questKey: key)
            }
        }
    }

    /// Reset the completion-dedup set when a NEW impression lands.
    /// Wrapper calls this from its `onChange(of: store.brief?.composedAt)`
    /// after writing the impression id back.
    func resetCompletionTrackingForNewImpression(_ id: UUID?) {
        currentImpressionId = id
        loggedCompletionsForImpression.removeAll(keepingCapacity: true)
    }

    // MARK: - Disk cache

    private struct Cached: Codable {
        let brief: DailyBrief
    }

    private static func readCache() -> DailyBrief? {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let entry = try? JSONDecoder().decode(Cached.self, from: data) else { return nil }
        // Same-day only.
        guard Calendar.current.isDate(entry.brief.composedAt, inSameDayAs: Date()) else { return nil }
        return entry.brief
    }

    private static func writeCache(_ brief: DailyBrief) {
        let entry = Cached(brief: brief)
        if let data = try? JSONEncoder().encode(entry) {
            UserDefaults.standard.set(data, forKey: cacheKey)
        }
    }
}
