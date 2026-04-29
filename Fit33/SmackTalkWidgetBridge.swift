//
//  SmackTalkWidgetBridge.swift
//  Fit33
//
//  Bridges incoming "smack talk" reactions (the trash-talk side of
//  `challenge_reactions`) into the home-screen Active Challenge widget
//  via the shared App Group. The widget paints a comic-book shout
//  bubble yelling out of its type-emoji icon ("Do better!") whenever
//  there's an unread incoming smack — the bubble disappears the moment
//  the user opens the app (cleared by `Fit33App`'s scenePhase `.active`
//  observer; see `SmackTalkWidgetBridge.clear()`).
//
//  Wire-format contract:
//    • Lives in App Group `group.com.fit33.app` under key
//      `fit33.widget.smackTalk.v1`.
//    • Mirrored byte-for-byte by the widget extension's
//      `ActiveChallengeWidgetSnapshot.WidgetSmackTalk` (same JSON
//      coding keys). When this struct's shape changes, mirror the
//      widget side in the SAME edit pass.
//    • Reload-budget aware — we coalesce overlapping writes (e.g. a
//      foreground willPresent + silent-push double-fire) by skipping
//      the encode + reload when the new payload's hash matches the
//      one we just wrote. Mirrors the dedup pattern in
//      `ActiveChallengeWidgetBridge.requestReloadIfNeeded`.
//
//  Created 2026-04-29 alongside the "shout out of the icon" widget
//  effect (smack appears on home-screen widget until the user opens
//  the app).
//

import Foundation
import WidgetKit

enum SmackTalkWidgetBridge {
    static let appGroupID = "group.com.fit33.app"
    /// JSON-encoded `WidgetSmackTalk` payload. Single-slot — the widget
    /// always shows the latest unread smack, not a queue.
    static let smackTalkKey = "fit33.widget.smackTalk.v1"

    /// Slim widget-only model. Mirror byte-for-byte in
    /// `RunningActivityWidget/ActiveChallengeWidgetSnapshot.swift`.
    struct WidgetSmackTalk: Codable, Hashable {
        /// Lowercased UUID — same canonical form the active-challenge
        /// bridge writes (see `ActiveChallengeWidgetBridge.publish`).
        /// The widget filters smack to "matches the currently-displayed
        /// challenge" so users with multiple 1v1s in flight don't see a
        /// shout from challenge B on the widget pinned to challenge A.
        let challengeId: String
        let senderFirstName: String
        let reactionEmoji: String
        let reactionText: String
        /// "trash_talk" or "cheer". Both lands in this slot — accountability
        /// "Power Up" cheers ride the same shout-bubble path as competition
        /// trash talk; the widget tints differently per category.
        let reactionCategory: String
        let receivedAt: Date

        var isCompetition: Bool { reactionCategory == "trash_talk" }
    }

    nonisolated(unsafe) private static var lastPayloadHash: Int?
    nonisolated(unsafe) private static let writeLock = NSLock()

    /// Persists `payload` for the home-screen widget to render and
    /// reloads `ActiveChallengeWidget` timelines. No-op if the App
    /// Group is unavailable (extension entitlement missing).
    ///
    /// `decideShouldWrite` is checked just before the App Group write —
    /// callers pass the application state predicate so we can skip the
    /// write when the user is already in the foreground (we only want
    /// the widget shout when the app ISN'T open). The check happens
    /// here rather than at the call site so the gating policy lives in
    /// one place.
    static func publish(_ payload: WidgetSmackTalk, shouldWrite: () -> Bool = { true }) {
        guard shouldWrite() else {
            AppLogger.debug("📣 [WIDGET] Smack write skipped — app is foregrounded", category: .social)
            return
        }
        guard let defaults = UserDefaults(suiteName: appGroupID) else {
            AppLogger.warning("📣 [WIDGET] App Group \(appGroupID) unavailable — skipping smack publish", category: .social)
            return
        }

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(payload)

            writeLock.lock()
            var hasher = Hasher()
            hasher.combine(data)
            let hash = hasher.finalize()
            if lastPayloadHash == hash {
                writeLock.unlock()
                return
            }
            lastPayloadHash = hash
            writeLock.unlock()

            defaults.set(data, forKey: smackTalkKey)
            WidgetCenter.shared.reloadTimelines(ofKind: "ActiveChallengeWidget")
            AppLogger.info("📣 [WIDGET] Published smack: \(payload.reactionEmoji) \"\(payload.reactionText)\" from \(payload.senderFirstName)", category: .social)
        } catch {
            AppLogger.warning("📣 [WIDGET] Failed to encode smack payload: \(error)", category: .social)
        }
    }

    /// Wipes the smack slot and reloads the widget so the shout bubble
    /// disappears. Called from `Fit33App`'s `scenePhase == .active`
    /// observer so the bubble vanishes the instant the user opens the
    /// app — that's the "until the user opens the app" half of the
    /// product contract.
    static func clear() {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return }
        let hadValue = defaults.object(forKey: smackTalkKey) != nil
        writeLock.lock()
        lastPayloadHash = nil
        writeLock.unlock()
        defaults.removeObject(forKey: smackTalkKey)
        if hadValue {
            WidgetCenter.shared.reloadTimelines(ofKind: "ActiveChallengeWidget")
            AppLogger.debug("📣 [WIDGET] Smack cleared on app open", category: .social)
        }
    }
}
