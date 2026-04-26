//
//  StartupCachePreloader.swift
//  Fit33
//
//  Pre-decodes UserDefaults JSON caches on background threads BEFORE the
//  @MainActor singletons that own those caches run their init on main.
//
//  Cold-start chain in Fit33App: ContentView → MainTabView → DashboardView's
//  body evaluation triggers ~5 @MainActor singletons (FriendService,
//  PrivateChallengeService, ContactsService, FriendRankingService) and a
//  couple of `final class` ones (ProfilePhotoCache, FriendPhotoCache). Each
//  of those `private init()`s synchronously decodes its own JSON cache from
//  UserDefaults on main, accumulating ~600-900ms of main-thread work BEFORE
//  the first frame can paint (observed `app.first_frame ≥ 2833ms` in
//  1.38(55) cold-start logs).
//
//  This module fires N parallel JSON decodes onto the global concurrent
//  queue immediately upon process boot (called from `Fit33App.init()`'s
//  very first statement). When the singleton's `init()` later runs on
//  main, it picks up the pre-decoded result via `consume…()` instead of
//  re-running the slow decode path.
//
//  Race semantics:
//    - If pre-decode finishes BEFORE singleton.init() runs (the common
//      path — bg has 50-200ms head start over the SwiftUI view body
//      evaluation), init() consumes the pre-decoded value in O(1) and
//      the heavy work is removed from the main-thread cold-start
//      critical path.
//    - If pre-decode is still running when init() runs (rare — happens
//      only if the user's device is severely starved of bg threads),
//      `consume…()` returns nil, the singleton falls back to its
//      existing synchronous decode, and behavior is identical to the
//      pre-StartupCachePreloader code path. Worst-case == today.
//
//  This preserves the user-facing invariant "no flicker": the singleton
//  always emits its first @Published update with the cached value (either
//  pre-decoded or sync-decoded) BEFORE any view subscribes — same as
//  before the preloader. We never publish empty-then-populated.
//
//  Sprint 2026-04-25 (cold-start speedup Phase 4 — parallel cache decode).
//

import Foundation
import UIKit

@MainActor
enum StartupCachePreloader {
    // MARK: - One-shot kickoff guard
    //
    // `Fit33App` declares a `let _coldStartKickoff: Void = StartupCachePreloader.kickoff()`
    // as its FIRST stored property so the kickoff runs BEFORE any @StateObject
    // property initializer (each of which lazily forces a singleton's
    // `static let shared`). `kickoff()` is idempotent — `hasKickedOff` ensures
    // that even if SwiftUI re-instantiates the App struct (rare in practice
    // but legal), we don't fire two parallel waves of decodes and double-
    // count telemetry.
    nonisolated(unsafe) private static var hasKickedOff = false

    /// Idempotent entry point used by `Fit33App._coldStartKickoff`.
    /// Returns `Void` so it can be the default value of a `let` property
    /// (`let _coldStartKickoff: Void = StartupCachePreloader.kickoff()`).
    nonisolated static func kickoff() {
        guard !hasKickedOff else { return }
        hasKickedOff = true
        preloadAll()
    }

    // MARK: - Pre-decoded storage
    //
    // `nonisolated(unsafe)` is required because we set these from background
    // queues and read them from `@MainActor`-isolated singleton inits on main.
    // Writes happen exactly once (the bg decode), reads happen exactly once
    // (the consume during init), so there is no concurrent read/write — the
    // unsafe annotation is honest about the lack of a lock but the access
    // pattern is safe.

    nonisolated(unsafe) static var preDecodedFriends: [Friend]?
    nonisolated(unsafe) static var preDecodedBlockedFriendIds: Set<UUID>?
    nonisolated(unsafe) static var preDecodedPrivateChallenges: [PrivateChallenge]?
    nonisolated(unsafe) static var preDecodedPrivateInvites: [PrivateChallengeInvite]?
    nonisolated(unsafe) static var preDecodedSuggestedFriends: [SuggestedFriend]?
    nonisolated(unsafe) static var preDecodedPYMK: [SuggestedFriend]?
    nonisolated(unsafe) static var preDecodedRankedFriends: [RankedFriend]?
    nonisolated(unsafe) static var preDecodedProfilePhoto: UIImage?

    // MARK: - Telemetry
    nonisolated(unsafe) private static var startTime: CFAbsoluteTime = 0
    nonisolated(unsafe) static var totalElapsedMs: Int = 0

    // MARK: - Public entry point

    /// Fires N parallel pre-decodes on the global concurrent queue.
    /// MUST be called from the FIRST statement of `Fit33App.init()` so that
    /// bg threads have maximum head-start over the SwiftUI view body
    /// evaluation that triggers each singleton's `.shared` access.
    nonisolated static func preloadAll() {
        startTime = CFAbsoluteTimeGetCurrent()

        let queue = DispatchQueue.global(qos: .userInitiated)
        let group = DispatchGroup()

        // Slot 1 — FriendService
        group.enter()
        queue.async {
            defer { group.leave() }
            let defaults = UserDefaults.standard
            if let data = defaults.data(forKey: "fit33_cached_friends") {
                preDecodedFriends = try? JSONDecoder().decode([Friend].self, from: data)
            }
            let blockedStrings = defaults.stringArray(forKey: "fit33_blocked_user_ids") ?? []
            preDecodedBlockedFriendIds = Set(blockedStrings.compactMap { UUID(uuidString: $0) })
        }

        // Slot 2 — PrivateChallengeService
        group.enter()
        queue.async {
            defer { group.leave() }
            let defaults = UserDefaults.standard
            if let data = defaults.data(forKey: "private_challenges_cache") {
                if var cached = try? JSONDecoder().decode([PrivateChallenge].self, from: data) {
                    let cacheDate = defaults.double(forKey: "private_challenges_cache_date")
                    let isCacheFromToday: Bool = cacheDate > 0
                        ? Calendar.current.isDateInToday(Date(timeIntervalSince1970: cacheDate))
                        : false
                    if !isCacheFromToday && !cached.isEmpty {
                        // Mirror the today-rollover zero in `loadFromCache`.
                        for i in cached.indices { cached[i].myTodayProgress = 0 }
                    }
                    preDecodedPrivateChallenges = cached
                }
            }
            if let data = defaults.data(forKey: "private_challenge_invites_cache") {
                preDecodedPrivateInvites = try? JSONDecoder().decode([PrivateChallengeInvite].self, from: data)
            }
        }

        // Slot 3 — ContactsService
        group.enter()
        queue.async {
            defer { group.leave() }
            let defaults = UserDefaults.standard
            if let data = defaults.data(forKey: "cached_suggested_friends_v1") {
                preDecodedSuggestedFriends = try? JSONDecoder().decode([SuggestedFriend].self, from: data)
            }
            if let data = defaults.data(forKey: "cached_pymk_v1") {
                preDecodedPYMK = try? JSONDecoder().decode([SuggestedFriend].self, from: data)
            }
        }

        // Slot 4 — FriendRankingService
        group.enter()
        queue.async {
            defer { group.leave() }
            if let data = UserDefaults.standard.data(forKey: "fit33_cached_ranked_friends") {
                preDecodedRankedFriends = try? JSONDecoder().decode([RankedFriend].self, from: data)
            }
        }

        // Slot 5 — ProfilePhotoCache (file read + UIImage decode is heavy
        // — moving off main is a clear cold-start win).
        group.enter()
        queue.async {
            defer { group.leave() }
            guard let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
                .appendingPathComponent("profile_photo.jpg") else { return }
            guard FileManager.default.fileExists(atPath: cacheURL.path) else { return }
            guard let data = try? Data(contentsOf: cacheURL) else { return }
            guard let image = UIImage(data: data) else { return }
            // Force-decode the image now (off-main) so the first time UIKit
            // displays it on main, there's no decode-on-render hitch.
            UIGraphicsBeginImageContext(CGSize(width: 1, height: 1))
            image.draw(in: CGRect(x: 0, y: 0, width: 1, height: 1))
            UIGraphicsEndImageContext()
            preDecodedProfilePhoto = image
        }

        // Telemetry — fires when ALL slots above have left the group.
        group.notify(queue: queue) {
            totalElapsedMs = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)
            AppLogger.info("⚡️ [STARTUP PRELOAD] Pre-decoded all caches in \(totalElapsedMs)ms (parallel bg)", category: .performance)
        }
    }

    // MARK: - Consumption helpers (called from singleton inits on main)
    //
    // Each `consume…` returns the pre-decoded value (if bg pre-decode won
    // the race) and clears the static slot so the memory is reclaimed
    // promptly. A nil return signals the singleton to fall back to its
    // existing synchronous load path. All consume helpers are `nonisolated`
    // because they only touch `nonisolated(unsafe)` storage — this lets
    // both `@MainActor`-isolated singletons (FriendService, ContactsService,
    // FriendRankingService, PrivateChallengeService) and unisolated
    // `final class` ones (ProfilePhotoCache) call them without an
    // isolation hop. The single-write / single-read pattern means there
    // is no concurrent access in practice.

    nonisolated static func consumeFriends() -> (friends: [Friend]?, blocked: Set<UUID>?) {
        let f = preDecodedFriends
        let b = preDecodedBlockedFriendIds
        preDecodedFriends = nil
        preDecodedBlockedFriendIds = nil
        return (f, b)
    }

    nonisolated static func consumePrivateChallenges() -> (challenges: [PrivateChallenge]?, invites: [PrivateChallengeInvite]?) {
        let c = preDecodedPrivateChallenges
        let i = preDecodedPrivateInvites
        preDecodedPrivateChallenges = nil
        preDecodedPrivateInvites = nil
        return (c, i)
    }

    nonisolated static func consumeContactsSuggestions() -> (contacts: [SuggestedFriend]?, pymk: [SuggestedFriend]?) {
        let c = preDecodedSuggestedFriends
        let p = preDecodedPYMK
        preDecodedSuggestedFriends = nil
        preDecodedPYMK = nil
        return (c, p)
    }

    nonisolated static func consumeRankedFriends() -> [RankedFriend]? {
        let r = preDecodedRankedFriends
        preDecodedRankedFriends = nil
        return r
    }

    nonisolated static func consumeProfilePhoto() -> UIImage? {
        let p = preDecodedProfilePhoto
        preDecodedProfilePhoto = nil
        return p
    }
}
