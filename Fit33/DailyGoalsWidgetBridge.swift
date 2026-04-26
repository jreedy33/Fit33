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
    struct WidgetDailyGoal: Codable {
        let title: String
        let icon: String          // SF Symbol name
        let category: String
        let currentValue: Int
        let targetValue: Int
        let targetUnit: String
        let isCompleted: Bool
        let funLabel: String?
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
                funLabel: quest.funLabel
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
}
