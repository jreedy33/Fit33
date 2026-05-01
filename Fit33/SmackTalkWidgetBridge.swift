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
//    • Lives as a JSON sidecar file at
//      `<AppGroupContainer>/smackTalk.v1.json`.
//      File-based — NOT `UserDefaults` — to bypass `cfprefsd`'s
//      cross-process cache. See "Why a file" below.
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
//  Why a file (and not `UserDefaults` like the rest of the bridge):
//    `UserDefaults(suiteName: appGroup)` reads/writes are mediated by
//    `cfprefsd`, which keeps a per-process cache. iOS emits the
//    "Couldn't read values in CFPrefsPlistSource ... detaching from
//    cfprefsd" warning on App Group containers, after which the
//    widget extension's cached `UserDefaults` instance can serve
//    stale values for arbitrarily long even though the iOS app's
//    write hit disk. The widget needs the smack the INSTANT iOS
//    spawns it from `WidgetCenter.shared.reloadTimelines` — there's
//    no second chance — so we write a tiny JSON file the widget
//    reads on every `entry(for:)`. File reads always go through the
//    sandbox-extension'd App Group container path, which is
//    fully consistent across processes (no cfprefsd cache).
//    Confirmed root cause 2026-04-29 — silent push fires, bridge
//    encodes + writes + calls `reloadTimelines`, widget process
//    spawns and reads NIL from `UserDefaults`, no bubble paints.
//    Switching to a sidecar file fixed the read.
//
//  Created 2026-04-29 alongside the "shout out of the icon" widget
//  effect (smack appears on home-screen widget until the user opens
//  the app).
//

import Foundation
import WidgetKit

enum SmackTalkWidgetBridge {
    static let appGroupID = "group.com.fit33.app"
    /// Sidecar filename inside the App Group container. Single-slot —
    /// the widget always shows the latest unread smack, not a queue.
    /// `.v1` for forward-compat: if the wire format changes we add a
    /// `.v2.json` and have both readers fall through.
    static let smackFileName = "smackTalk.v1.json"

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

    /// Resolve the App Group container URL for the smack sidecar file.
    /// Returns `nil` only if the App Group entitlement is missing
    /// (release-blocking misconfig — surfaces via the warning log).
    private static func smackFileURL() -> URL? {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupID
        ) else {
            return nil
        }
        return container.appendingPathComponent(smackFileName)
    }

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
            AppLogger.info("📣 [WIDGET] Smack write SKIPPED — app is foregrounded (bubble suppressed by design)", category: .social)
            SessionLogManager.shared.log(.info, category: .pushNotification, message: "📣 [WIDGET] smack skipped — foreground")
            return
        }
        guard let url = smackFileURL() else {
            AppLogger.warning("📣 [WIDGET] App Group \(appGroupID) container UNAVAILABLE — extension entitlement missing!", category: .social)
            SessionLogManager.shared.log(.error, category: .pushNotification, message: "📣 [WIDGET] App Group container unavailable")
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

            // `.atomic` writes to a temp file in the same directory
            // and renames into place — readers either see the OLD
            // bytes or the NEW bytes, never a half-written file.
            // Crucial since the widget extension can spawn at any
            // moment after `reloadTimelines` and start reading.
            try data.write(to: url, options: [.atomic])
            WidgetCenter.shared.reloadTimelines(ofKind: "ActiveChallengeWidget")
            AppLogger.info("📣 [WIDGET] Published smack to file: \(payload.reactionEmoji) \"\(payload.reactionText)\" from \(payload.senderFirstName) (challenge=\(payload.challengeId))", category: .social)
            SessionLogManager.shared.log(.info, category: .pushNotification, message: "📣 [WIDGET] smack published (file) + timeline reloaded", metadata: [
                "challenge_id": payload.challengeId,
                "sender": payload.senderFirstName,
                "emoji": payload.reactionEmoji,
                "path": url.lastPathComponent
            ])
        } catch {
            AppLogger.warning("📣 [WIDGET] Failed to write smack file: \(error)", category: .social)
            SessionLogManager.shared.log(.error, category: .pushNotification, message: "📣 [WIDGET] smack file write failed", metadata: ["error": "\(error)"])
        }
    }

    /// Wipes the smack slot and reloads the widget so the shout bubble
    /// disappears. Called from `Fit33App`'s `scenePhase == .active`
    /// observer so the bubble vanishes the instant the user opens the
    /// app — that's the "until the user opens the app" half of the
    /// product contract.
    static func clear() {
        // Best-effort cleanup of the OLD UserDefaults wire format so
        // installs that came pre-2026-04-29 don't leave orphan keys
        // sitting in the App Group. Safe to call even when there's
        // nothing there.
        if let defaults = UserDefaults(suiteName: appGroupID) {
            defaults.removeObject(forKey: "fit33.widget.smackTalk.v1")
        }

        guard let url = smackFileURL() else { return }
        let fm = FileManager.default
        let hadValue = fm.fileExists(atPath: url.path)
        writeLock.lock()
        lastPayloadHash = nil
        writeLock.unlock()
        if hadValue {
            do {
                try fm.removeItem(at: url)
            } catch {
                AppLogger.warning("📣 [WIDGET] Failed to remove smack file on clear: \(error)", category: .social)
            }
            WidgetCenter.shared.reloadTimelines(ofKind: "ActiveChallengeWidget")
            AppLogger.debug("📣 [WIDGET] Smack cleared on app open", category: .social)
        }
    }
}
