//
//  ActiveChallengeWidgetBridge.swift
//  Fit33
//
//  Bridge for the home-screen Active Challenge widget. Publishes a slim
//  snapshot of the user's top 1v1 active challenge to the App Group so
//  the widget extension can render the in-app challenge card without
//  reaching for the network.
//
//  Keep `WidgetActiveChallenge` in sync with the widget-side copy in
//  `RunningActivityWidget/ActiveChallengeWidgetSnapshot.swift`.
//

import Foundation
import UIKit
import WidgetKit

enum ActiveChallengeWidgetBridge {
    static let appGroupID = "group.com.fit33.app"
    /// Single "best pick" payload — the widget falls back to this when the
    /// user hasn't selected a specific challenge in the widget config UI.
    static let challengeKey = "fit33.widget.activeChallenge.v1"
    /// Full list of active 1v1 challenges, used to populate the
    /// configurable widget's "Challenge" dropdown.
    static let challengesListKey = "fit33.widget.activeChallenges.list.v1"
    static let updatedAtKey = "fit33.widget.activeChallenge.updatedAt"

    /// Darwin notification name posted by the widget extension after a
    /// successful direct-Supabase pull writes fresh data into the App
    /// Group (see `ActiveChallengeProvider.writeIfChanged`). The main
    /// app subscribes via `startWidgetPullListener()` and re-runs its
    /// own canonical fetch so `ChallengeService.activeChallenges` lines
    /// up with what the widget just rendered. Realtime Widget Server
    /// Pull, Phase 5 (2026-04-26).
    static let widgetPullNotificationName = "com.fit33.app.widgetActiveChallengePayloadChanged"

    /// Bridged NSNotification name used inside the main app to fan
    /// the Darwin event out to Swift listeners. CFNotificationCenter
    /// callbacks are static C functions and can't capture context, so
    /// we bounce through `NotificationCenter.default` to land in a
    /// proper closure.
    private static let bridgedNotificationName = Notification.Name("ActiveChallengeWidgetBridge.WidgetPullCompleted")

    // MARK: - Reload-budget gate
    //
    // iOS gives every widget extension a finite reload "budget" per day.
    // `WidgetCenter.shared.reloadAllTimelines()` is the expensive call —
    // hammering it on every progress tick (HK observers + Supabase
    // realtime + scenePhase + push) burns the budget and iOS silently
    // starts ignoring reloads, which is exactly the "stale widget"
    // symptom we're trying to avoid. We coalesce by:
    //   1. Hashing the encoded payload — if it matches the last publish,
    //      skip the reload entirely (data didn't change).
    //   2. Throttling reloads to at most one every `minReloadInterval`
    //      seconds — if a reload was requested inside that window, we
    //      still write the fresh App Group data so the next scheduled
    //      timeline tick picks it up, but skip the explicit reload.
    /// Hash of the most recently encoded payload (`payloads` JSON +
    /// chosen ID). Compared per-publish to skip identical-data reloads.
    private static var lastPayloadHash: Int?
    /// Wall-clock time of the most recent successful
    /// `reloadAllTimelines()` call. Used by the throttle.
    private static var lastReloadAt: Date?
    /// Pending coalesced reload kicked off when a publish is throttled —
    /// fires once at the end of the throttle window so we don't lose the
    /// "newest" progress update.
    nonisolated(unsafe) private static var pendingReloadTask: Task<Void, Never>?
    /// Lock guarding `lastPayloadHash`, `lastReloadAt`, and
    /// `pendingReloadTask`. The bridge is called from `@MainActor`
    /// (`ChallengeService.cacheActiveChallenges`) AND background paths
    /// (HK observer optimistic updates), so the state needs an explicit
    /// lock.
    nonisolated(unsafe) private static let reloadLock = NSLock()
    /// Min seconds between consecutive `reloadAllTimelines()` calls.
    /// Phase 7e (2026-04-27): drops 8s → 4s after field reports of
    /// opponent-progress lag. The 8s coalesce window was sized for HK
    /// observer bursts (steps + active_energy + distance firing in the
    /// same millisecond) — those still coalesce inside 4s on real
    /// hardware (sub-100ms typical), and the silent-push reception path
    /// (one event, no burst) gets visibly faster paint. iOS itself has
    /// an internal coalesce on `reloadAllTimelines()` so dropping below
    /// 4s starts hitting diminishing returns.
    private static let minReloadInterval: TimeInterval = 4.0

    // Photo files mirrored into the App Group container so the widget
    // process can render real avatars without network access.
    static let userPhotoFilename = "widget_user_photo.jpg"
    /// Per-opponent photo prefix. Files end up as
    /// `widget_opponent_<opponentId>.jpg` in the shared container.
    static let opponentPhotoPrefix = "widget_opponent_"
    /// Side length the bridge resizes avatars down to before writing the
    /// JPEG. 240px @ 80% quality keeps each file < 30KB while still looking
    /// crisp on the largest medium-widget avatar (38pt @3x = 114px).
    private static let photoMaxSide: CGFloat = 240

    static func opponentPhotoFilename(opponentId: String) -> String {
        "\(opponentPhotoPrefix)\(opponentId).jpg"
    }

    /// Slim widget-only model. Mirrors only the fields the widget UI uses
    /// (header title + mode + opponent + today progress + streak).
    ///
    /// Realtime Widget Server Pull, Phase 2b (2026-04-26):
    ///   `myLastProgressAt` / `opponentLastProgressAt` are populated either
    ///   by the main app's `cacheActiveChallenges` path (this file) or by
    ///   the widget-side direct Supabase pull
    ///   (`RunningActivityWidget/WidgetSupabaseFetcher.swift`). They drive
    ///   the freshness-aware UI in `Shared/ProgressFreshness.swift`
    ///   (Phase 6) so a stale opponent renders as `— · 8h ago` instead of
    ///   a confidently-wrong `0 steps`.
    struct WidgetActiveChallenge: Codable {
        let challengeId: String
        let challengeType: String
        let displayTitle: String
        let mode: String              // "competition" | "accountability"
        let targetUnit: String
        let dailyTarget: Int?
        let daysRemaining: Int
        let durationDays: Int
        let myTodayProgress: Int
        let opponentTodayProgress: Int
        let opponentId: String
        let opponentName: String?
        let opponentPhotoUrl: String?
        let opponentIsVerified: Bool
        let opponentIsGoldVerified: Bool
        let myCurrentStreak: Int
        let amWinningToday: Bool
        let myDisplayName: String?
        let hasUserPhoto: Bool
        let hasOpponentPhoto: Bool
        /// Server-side `MAX(updated_at)` from `challenge_daily_progress`
        /// for the caller in this challenge. NULL when no rows exist
        /// (e.g. a brand-new challenge before the first sync).
        let myLastProgressAt: Date?
        /// Same shape, opponent side. NULL is the dominant signal we
        /// surface in the freshness pill — "we have no idea when their
        /// phone last reported in".
        let opponentLastProgressAt: Date?
    }

    /// Publishes the full list of active 1v1 challenges plus a "best pick"
    /// fallback for users who haven't chosen one in the widget config.
    /// Heuristic for the fallback: shortest `daysRemaining` first
    /// (urgency), then highest combined progress today.
    static func publish(activeChallenges: [ActiveChallenge]) {
        guard let defaults = UserDefaults(suiteName: appGroupID) else {
            AppLogger.warning("📱 [WIDGET] App Group \(appGroupID) unavailable — skipping challenge publish", category: .social)
            return
        }

        let active = activeChallenges
            .filter { $0.status.lowercased() == "active" || $0.status.isEmpty }
            .sorted { lhs, rhs in
                if lhs.daysRemaining != rhs.daysRemaining {
                    return lhs.daysRemaining < rhs.daysRemaining
                }
                let lhsToday = (lhs.myTodayProgress ?? 0) + (lhs.opponentTodayProgress ?? 0)
                let rhsToday = (rhs.myTodayProgress ?? 0) + (rhs.opponentTodayProgress ?? 0)
                return lhsToday > rhsToday
            }

        guard let chosen = active.first else {
            defaults.removeObject(forKey: challengeKey)
            defaults.removeObject(forKey: challengesListKey)
            defaults.set(Date(), forKey: updatedAtKey)
            removeSharedPhoto(named: userPhotoFilename)
            cleanStaleOpponentPhotos(keepingOpponentIds: [])
            WidgetCenter.shared.reloadAllTimelines()
            return
        }

        // Mirror the user's profile photo + every opponent's photo into
        // the App Group so the widget can render any selected challenge.
        let userPhotoWritten = writeSharedPhoto(
            ProfilePhotoCache.shared.cachedImage,
            named: userPhotoFilename
        )
        var hasOpponentPhotoById: [String: Bool] = [:]
        let validOpponentIds: [String] = active.map { $0.opponentId.uuidString }
        for challenge in active {
            let id = challenge.opponentId.uuidString
            let written = writeSharedPhoto(
                FriendPhotoCache.shared.getImage(for: id),
                named: opponentPhotoFilename(opponentId: id)
            )
            hasOpponentPhotoById[id] = written
        }
        cleanStaleOpponentPhotos(keepingOpponentIds: validOpponentIds)

        let myName = UserManager.shared.currentUser?.name
        let payloads: [WidgetActiveChallenge] = active.map { challenge in
            let oppId = challenge.opponentId.uuidString
            return WidgetActiveChallenge(
                challengeId: challenge.challengeId.uuidString,
                challengeType: challenge.challengeType,
                displayTitle: challenge.displayTitle,
                mode: challenge.mode == .accountability ? "accountability" : "competition",
                targetUnit: challenge.targetUnit,
                dailyTarget: challenge.dailyTarget,
                daysRemaining: challenge.daysRemaining,
                durationDays: challenge.durationDays,
                myTodayProgress: challenge.myTodayProgress ?? 0,
                opponentTodayProgress: challenge.opponentTodayProgress ?? 0,
                opponentId: oppId,
                opponentName: challenge.opponentName,
                opponentPhotoUrl: challenge.opponentPhotoUrl,
                opponentIsVerified: challenge.opponentIsVerified ?? false,
                opponentIsGoldVerified: challenge.opponentIsGoldVerified ?? false,
                myCurrentStreak: challenge.myCurrentStreak,
                amWinningToday: challenge.amWinningToday ?? challenge.amWinning,
                myDisplayName: myName,
                hasUserPhoto: userPhotoWritten,
                hasOpponentPhoto: hasOpponentPhotoById[oppId] ?? false,
                myLastProgressAt: challenge.myLastProgressAt,
                opponentLastProgressAt: challenge.opponentLastProgressAt
            )
        }
        let chosenPayload = payloads.first { $0.challengeId == chosen.challengeId.uuidString } ?? payloads[0]

        do {
            let encoder = JSONEncoder()
            let chosenData = try encoder.encode(chosenPayload)
            let listData = try encoder.encode(payloads)
            defaults.set(chosenData, forKey: challengeKey)
            defaults.set(listData, forKey: challengesListKey)
            defaults.set(Date(), forKey: updatedAtKey)

            // Hash the canonical payload (chosen + full list). Identical
            // hash = no UI-visible change → skip the reload even though
            // we already refreshed the App Group bytes.
            var hasher = Hasher()
            hasher.combine(chosenData)
            hasher.combine(listData)
            let payloadHash = hasher.finalize()
            requestReloadIfNeeded(payloadHash: payloadHash, reason: "publish")
        } catch {
            AppLogger.warning("📱 [WIDGET] Failed to encode active challenge: \(error)", category: .social)
            return
        }
    }

    // MARK: - Optimistic local progress update
    //
    // Called from `BackgroundChallengeSyncService` the moment HealthKit
    // delivers a fresh observer event, BEFORE the heavy Supabase round
    // trip lands. We re-read the App Group's existing payload and patch
    // each challenge's `myTodayProgress` with the freshest local value
    // sourced from `ChallengeProgressResolver` (which already knows how
    // to resolve steps / distance / active minutes / hydration / etc.
    // per challenge type). The widget then redraws within ~1s of the
    // user moving, instead of waiting 5-30s for the full sync pipeline.
    //
    // Cheap path: if every patched value already matches the stored
    // value (most ticks), we skip the encode + reload entirely.
    @MainActor
    static func publishOptimisticLocalProgress() {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return }
        guard
            let listData = defaults.data(forKey: challengesListKey),
            let chosenData = defaults.data(forKey: challengeKey)
        else {
            return
        }

        let decoder = JSONDecoder()
        guard
            let existingList = try? decoder.decode([WidgetActiveChallenge].self, from: listData),
            let existingChosen = try? decoder.decode(WidgetActiveChallenge.self, from: chosenData),
            !existingList.isEmpty
        else {
            return
        }

        var changed = false
        let patchedList: [WidgetActiveChallenge] = existingList.map { stored in
            guard let type = ChallengeType(rawValue: stored.challengeType) else { return stored }
            let live = ChallengeProgressResolver.resolveProgress(
                challengeType: type,
                targetUnit: stored.targetUnit,
                serverValue: stored.myTodayProgress
            )
            // Live can only RAISE the displayed progress optimistically —
            // never regress below what the server most recently confirmed.
            // Otherwise a transient HK read (e.g. midnight rollover edge)
            // could flicker the widget downward.
            let nextMine = max(stored.myTodayProgress, live)
            guard nextMine != stored.myTodayProgress else { return stored }
            changed = true
            let opponent = stored.opponentTodayProgress
            return WidgetActiveChallenge(
                challengeId: stored.challengeId,
                challengeType: stored.challengeType,
                displayTitle: stored.displayTitle,
                mode: stored.mode,
                targetUnit: stored.targetUnit,
                dailyTarget: stored.dailyTarget,
                daysRemaining: stored.daysRemaining,
                durationDays: stored.durationDays,
                myTodayProgress: nextMine,
                opponentTodayProgress: opponent,
                opponentId: stored.opponentId,
                opponentName: stored.opponentName,
                opponentPhotoUrl: stored.opponentPhotoUrl,
                opponentIsVerified: stored.opponentIsVerified,
                opponentIsGoldVerified: stored.opponentIsGoldVerified,
                myCurrentStreak: stored.myCurrentStreak,
                amWinningToday: nextMine > opponent,
                myDisplayName: stored.myDisplayName,
                hasUserPhoto: stored.hasUserPhoto,
                hasOpponentPhoto: stored.hasOpponentPhoto,
                // The optimistic path patches our own progress upward
                // from a fresh HK observer event — by definition that's
                // a "now" datapoint, so stamp `myLastProgressAt` to now.
                // Opponent's timestamp is preserved verbatim — only the
                // server-side pull (Phase 3) updates that field.
                myLastProgressAt: Date(),
                opponentLastProgressAt: stored.opponentLastProgressAt
            )
        }

        guard changed else { return }

        let nextChosen = patchedList.first { $0.challengeId == existingChosen.challengeId } ?? patchedList[0]

        do {
            let encoder = JSONEncoder()
            let chosenOut = try encoder.encode(nextChosen)
            let listOut = try encoder.encode(patchedList)
            defaults.set(chosenOut, forKey: challengeKey)
            defaults.set(listOut, forKey: challengesListKey)
            defaults.set(Date(), forKey: updatedAtKey)

            var hasher = Hasher()
            hasher.combine(chosenOut)
            hasher.combine(listOut)
            requestReloadIfNeeded(payloadHash: hasher.finalize(), reason: "optimistic")
        } catch {
            AppLogger.warning("📱 [WIDGET] Failed to encode optimistic challenge progress: \(error)", category: .social)
        }
    }

    // MARK: - Reload gating

    /// Dedupes + throttles `WidgetCenter.shared.reloadAllTimelines()`.
    /// Skips entirely when the payload hash matches the last publish.
    /// Coalesces bursts inside `minReloadInterval` into a single trailing
    /// reload so the user always ends up with the freshest data.
    private static func requestReloadIfNeeded(payloadHash: Int, reason: String) {
        reloadLock.lock()
        if lastPayloadHash == payloadHash {
            reloadLock.unlock()
            return
        }
        lastPayloadHash = payloadHash

        let now = Date()
        if let last = lastReloadAt, now.timeIntervalSince(last) < minReloadInterval {
            // Inside throttle window — schedule a trailing reload that
            // fires once at the end of the window. If one is already
            // pending, leave it; the data on disk is already fresh.
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
            AppLogger.debug("📱 [WIDGET] Throttled challenge reload (\(reason)) — coalescing", category: .social)
            return
        }

        lastReloadAt = now
        // If a trailing task was scheduled, cancel it — we're firing now.
        pendingReloadTask?.cancel()
        pendingReloadTask = nil
        reloadLock.unlock()
        WidgetCenter.shared.reloadAllTimelines()
    }

    private static func cleanStaleOpponentPhotos(keepingOpponentIds: [String]) {
        guard let url = sharedContainerURL() else { return }
        let valid = Set(keepingOpponentIds.map { opponentPhotoFilename(opponentId: $0) })
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(atPath: url.path) else { return }
        for name in contents where name.hasPrefix(opponentPhotoPrefix) && !valid.contains(name) {
            try? fm.removeItem(at: url.appendingPathComponent(name))
        }
    }

    // MARK: - Shared photo helpers

    /// Resizes `image` to a small JPEG and writes it into the App Group
    /// container so the widget process can read it via UIImage. Removes
    /// the file when `image` is nil. Returns true when a fresh photo is
    /// available on disk after this call.
    @discardableResult
    private static func writeSharedPhoto(_ image: UIImage?, named filename: String) -> Bool {
        guard let image else {
            removeSharedPhoto(named: filename)
            return false
        }
        guard let url = sharedContainerURL()?.appendingPathComponent(filename) else {
            return false
        }
        let resized = resize(image, maxSide: photoMaxSide)
        guard let data = resized.jpegData(compressionQuality: 0.8) else {
            return false
        }
        do {
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            AppLogger.warning("📱 [WIDGET] Failed to write \(filename): \(error)", category: .social)
            return false
        }
    }

    private static func removeSharedPhoto(named filename: String) {
        guard let url = sharedContainerURL()?.appendingPathComponent(filename) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private static func sharedContainerURL() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }

    private static func resize(_ image: UIImage, maxSide: CGFloat) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxSide, longest > 0 else { return image }
        let scale = maxSide / longest
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    // MARK: - Widget → Main app pull bridge (Phase 5, 2026-04-26)
    //
    // When the widget extension finishes a direct Supabase pull and
    // writes fresh data to the App Group, it posts the Darwin
    // notification named `widgetPullNotificationName`. The main app
    // listens here and re-runs its OWN canonical fetch so the in-app
    // Active Challenges card stays in lockstep with what the widget
    // just rendered. We deliberately ignore the App Group payload
    // here and round-trip back to Supabase for two reasons:
    //
    //   1. The widget's `WidgetActiveChallenge` is a slim subset —
    //      no `myTotalProgress`, no `description`, no `start_date`,
    //      etc. — so reconstructing a full `ActiveChallenge` would
    //      lose information. Hitting `get_active_challenges` again
    //      gives us the canonical wire shape.
    //   2. `ChallengeService.fetchActiveChallenges` is already
    //      throttled (5s + RequestCoalescer) and triggers all the
    //      downstream side effects (photo preloading, audit logs,
    //      cache writes) in one pass. Reusing it keeps the data flow
    //      audit-clean.

    /// Tracks the registered observer so we don't double-register on
    /// auth-state changes. CFNotificationCenter accepts duplicate
    /// observer pointers silently and would fire the callback N times
    /// per post; the flag short-circuits.
    nonisolated(unsafe) private static var pullListenerRegistered = false
    nonisolated(unsafe) private static let listenerLock = NSLock()

    /// Wires up the widget-pull Darwin notification so a successful
    /// widget-side direct Supabase pull triggers a main-app
    /// `ChallengeService.fetchActiveChallenges()` round-trip. Idempotent
    /// — repeated calls during the lifetime of the process are no-ops.
    /// Safe to call from `Fit33App`'s startup `.task` after auth has
    /// been verified.
    @MainActor
    static func startWidgetPullListener() {
        listenerLock.lock()
        let already = pullListenerRegistered
        pullListenerRegistered = true
        listenerLock.unlock()
        guard !already else { return }

        // Step 1: Darwin → bridged NSNotification. The Darwin
        // callback MUST be a `@convention(c)` function pointer with
        // zero captures (Swift closures that capture context cannot
        // be coerced to C function pointers). We route to the
        // top-level `widgetPullDarwinCallback` below, which posts to
        // the main-process `NotificationCenter` where regular Swift
        // closures can land.
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let cfName = widgetPullNotificationName as CFString
        CFNotificationCenterAddObserver(
            center,
            nil,
            widgetPullDarwinCallback,
            cfName,
            nil,
            .deliverImmediately
        )

        // Step 2: NSNotification → main-actor work. We use a strong
        // reference to ChallengeService.shared since it's a singleton
        // — no retain-cycle risk.
        NotificationCenter.default.addObserver(
            forName: bridgedNotificationName,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                await ChallengeService.shared.fetchActiveChallenges()
                AppLogger.debug("📱 [WIDGET] Main app re-fetched active challenges after widget pull", category: .social)
            }
        }

        AppLogger.info("📱 [WIDGET] Started Darwin notification listener for widget-side Supabase pulls", category: .social)
    }

    /// Posts the Darwin notification used in the OPPOSITE direction —
    /// when the main app's `publish` writes fresh data, signal the
    /// widget process to re-render. Currently unused (the bridge
    /// already calls `WidgetCenter.shared.reloadAllTimelines()` which
    /// is the canonical "redraw the widget" trigger), but exposed here
    /// so future widget-only paths can subscribe without adding a new
    /// notification namespace. NOT currently invoked by `publish()` —
    /// reload via WidgetCenter is the source of truth.
    static func postWidgetPullNotification() {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let cfName = widgetPullNotificationName as CFString
        CFNotificationCenterPostNotification(center, CFNotificationName(cfName), nil, nil, true)
    }
}

// Top-level `@convention(c)` callback for `CFNotificationCenterAddObserver`.
// MUST live at file scope (not inside the enum) AND capture nothing —
// CFNotificationCallback is a C function pointer and Swift closures with
// captures cannot be coerced to it. Posts onto the main-process
// NotificationCenter so the Swift-side observer in `startWidgetPullListener`
// can do the actual main-actor `ChallengeService` refetch.
private func widgetPullDarwinCallback(
    _ center: CFNotificationCenter?,
    _ observer: UnsafeMutableRawPointer?,
    _ name: CFNotificationName?,
    _ object: UnsafeRawPointer?,
    _ userInfo: CFDictionary?
) {
    NotificationCenter.default.post(
        name: Notification.Name("ActiveChallengeWidgetBridge.WidgetPullCompleted"),
        object: nil
    )
}
