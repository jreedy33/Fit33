//
//  DailyGoalsWidgetBridge.swift
//  Fit33
//
//  Bridge between the main app's `DailyQuestService` and the home-screen
//  Daily Goals widget (RunningActivityWidget target). The widget runs in
//  a separate process and can't import the main app's models, so we
//  serialize a slim snapshot to App Group `UserDefaults` and ping
//  `WidgetCenter` to reload its timeline.
//
//  Keep this file's `WidgetDailyGoal` schema in sync with the widget-side
//  copy in `RunningActivityWidget/DailyGoalsWidgetSnapshot.swift`.
//

import Foundation
import WidgetKit

enum DailyGoalsWidgetBridge {
    /// App Group identifier — must match `com.apple.security.application-groups`
    /// in BOTH `Fit33/GoFit.entitlements` and
    /// `RunningActivityWidget/RunningActivityWidget.entitlements`.
    static let appGroupID = "group.com.fit33.app"

    /// JSON-encoded `[WidgetDailyGoal]` payload key.
    static let goalsKey = "fit33.widget.dailyGoals.v1"
    /// ISO-8601 timestamp of last write — widget can show "stale" if needed.
    static let updatedAtKey = "fit33.widget.dailyGoals.updatedAt"
    /// Bonus XP value for completing all goals (0 = no bonus available).
    static let bonusXpKey = "fit33.widget.dailyGoals.bonusXp"
    /// Whether all goals are complete (drives the celebration state).
    static let allCompleteKey = "fit33.widget.dailyGoals.allComplete"

    // MARK: - Reload-budget gate (mirrors `ActiveChallengeWidgetBridge`)
    private static var lastPayloadHash: Int?
    private static var lastReloadAt: Date?
    nonisolated(unsafe) private static var pendingReloadTask: Task<Void, Never>?
    nonisolated(unsafe) private static let reloadLock = NSLock()
    /// 8s coalescing window matches the active challenge bridge so a
    /// single HK observer burst that updates BOTH widgets only fires
    /// one `reloadAllTimelines()` per widget extension.
    private static let minReloadInterval: TimeInterval = 8.0

    /// Slim widget-only model. Mirrors only what the widget UI needs so
    /// the encoded payload stays small (well under the 4KB UserDefaults
    /// preference soft cap).
    ///
    /// 2026-04-27 — schema v2: added `description`, `xpReward`, and
    /// `difficulty` so the medium / large home-screen widget can render
    /// a near-exact replica of the in-app `compactQuestRow` (subheader
    /// description + "+XP" pill + difficulty chip). Schema is intentionally
    /// flat / additive — the widget side decodes new fields as Optional so
    /// a stale payload from a previous app version still decodes cleanly.
    struct WidgetDailyGoal: Codable {
        let title: String
        let icon: String          // SF Symbol name
        let category: String
        let currentValue: Int
        let targetValue: Int
        let targetUnit: String
        let isCompleted: Bool
        let funLabel: String?
        let description: String?
        let xpReward: Int?
        let difficulty: String?
    }

    /// Writes the latest 3 daily goals to App Group `UserDefaults` and
    /// triggers `WidgetCenter.shared.reloadAllTimelines()`. Best-effort —
    /// silently no-ops if the App Group isn't configured (e.g. local dev
    /// without the entitlement profile yet).
    static func publish(quests: [DailyQuest], allComplete: Bool, bonusXp: Int) {
        guard let defaults = UserDefaults(suiteName: appGroupID) else {
            AppLogger.warning("📱 [WIDGET] App Group \(appGroupID) unavailable — skipping publish", category: .general)
            return
        }

        let topThree = Array(quests.prefix(3)).map { quest in
            WidgetDailyGoal(
                title: quest.title,
                icon: quest.icon,
                category: quest.category,
                currentValue: quest.currentValue,
                targetValue: quest.targetValue,
                targetUnit: quest.targetUnit,
                isCompleted: quest.isCompleted,
                funLabel: quest.funLabel,
                description: quest.description,
                xpReward: quest.xpReward,
                difficulty: quest.difficulty
            )
        }

        do {
            let data = try JSONEncoder().encode(topThree)
            defaults.set(data, forKey: goalsKey)
            defaults.set(Date(), forKey: updatedAtKey)
            defaults.set(bonusXp, forKey: bonusXpKey)
            defaults.set(allComplete, forKey: allCompleteKey)

            var hasher = Hasher()
            hasher.combine(data)
            hasher.combine(bonusXp)
            hasher.combine(allComplete)
            requestReloadIfNeeded(payloadHash: hasher.finalize())
        } catch {
            AppLogger.warning("📱 [WIDGET] Failed to encode daily goals: \(error)", category: .general)
            return
        }
    }

    /// See `ActiveChallengeWidgetBridge.requestReloadIfNeeded` for the
    /// rationale. Same hash + throttle pattern: skip identical-data
    /// reloads, coalesce bursts inside `minReloadInterval` into a
    /// single trailing reload.
    private static func requestReloadIfNeeded(payloadHash: Int) {
        reloadLock.lock()
        if lastPayloadHash == payloadHash {
            reloadLock.unlock()
            return
        }
        lastPayloadHash = payloadHash

        let now = Date()
        if let last = lastReloadAt, now.timeIntervalSince(last) < minReloadInterval {
            if pendingReloadTask == nil {
                let delay = minReloadInterval - now.timeIntervalSince(last)
                pendingReloadTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: UInt64(max(0.1, delay) * 1_000_000_000))
                    reloadLock.lock()
                    pendingReloadTask = nil
                    lastReloadAt = Date()
                    reloadLock.unlock()
                    WidgetCenter.shared.reloadAllTimelines()
                }
            }
            reloadLock.unlock()
            AppLogger.debug("📱 [WIDGET] Throttled daily goals reload — coalescing", category: .general)
            return
        }

        lastReloadAt = now
        pendingReloadTask?.cancel()
        pendingReloadTask = nil
        reloadLock.unlock()
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Midnight reset

    /// Audit follow-up (2026-04-27 #14): `HealthKitManager.resetDailyCountersIfNeeded`
    /// previously called `WidgetCenter.shared.reloadAllTimelines()` directly,
    /// bypassing the same hash + throttle gates that `publish(...)` enforces.
    /// At midnight, every active HK observer can fire near-simultaneously
    /// across a multi-extension widget surface; an unguarded direct reload
    /// can spend WidgetKit's daily reload budget on duplicate ticks.
    ///
    /// This entry point is intentionally NOT payload-hash gated — at the
    /// day rollover the widget MUST regenerate timelines (yesterday's
    /// progress disappears, today's day-1 row hasn't been written yet),
    /// and the App Group payload may not have changed yet. We bypass the
    /// hash skip but still respect a 60s coalescing window so back-to-back
    /// midnight ticks (e.g. multiple HK observers settling) only fire one
    /// reload.
    static func requestMidnightReset() {
        reloadLock.lock()
        let now = Date()
        // Force the next `publish` to also reload by invalidating the
        // remembered hash — yesterday's payload should not look "fresh".
        lastPayloadHash = nil
        if let last = lastReloadAt, now.timeIntervalSince(last) < 60 {
            reloadLock.unlock()
            AppLogger.debug("📱 [WIDGET] Midnight reset throttled — already reloaded within 60s", category: .general)
            return
        }
        lastReloadAt = now
        pendingReloadTask?.cancel()
        pendingReloadTask = nil
        reloadLock.unlock()
        AppLogger.debug("📱 [WIDGET] Midnight reset — reloading all timelines", category: .general)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
