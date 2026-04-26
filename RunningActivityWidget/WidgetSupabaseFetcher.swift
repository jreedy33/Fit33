//
//  WidgetSupabaseFetcher.swift
//  RunningActivityWidget
//
//  Realtime Widget Server Pull — Phase 2b (2026-04-26).
//
//  Direct Supabase pull from inside the widget extension process so the
//  home-screen widget stays fresh even when the iPhone foreground app
//  hasn't run in hours (silent-push budget exhausted, opponent app force-
//  killed, etc.). Bypasses the main app entirely:
//
//      iOS schedules timeline tick
//          ↓
//      ActiveChallengeProvider.timeline (Phase 3)
//          ↓
//      WidgetSupabaseFetcher.fetchActiveChallenges()
//          ↓ (POST <url>/rest/v1/rpc/get_active_challenges)
//      Supabase Postgres → JSON
//          ↓
//      Decode → [WidgetActiveChallenge] → write to App Group
//          ↓
//      WidgetCenter renders fresh data
//
//  Why URLSession instead of the supabase-swift SDK:
//
//  1. **Extension memory budget** — widget extensions are killed past
//     ~30MB. Linking the full SDK pulls in Auth + PostgREST + Realtime
//     + Storage + Functions, plus the Realtime websocket runtime. We
//     only need a single REST POST per timeline tick, so URLSession is
//     ~5MB lighter and never opens a websocket the extension can't
//     close cleanly when iOS terminates it mid-fetch.
//  2. **Frameworks build phase stability** — adding new
//     XCSwiftPackageProductDependency entries to the widget target
//     means surgery on the .pbxproj that's easy to corrupt; URLSession
//     is built into Foundation and needs no project changes.
//  3. **Auth simplicity** — refresh-token rotation logic (background
//     dispatch + Keychain re-write) is a foot-gun inside a transient
//     extension process. We read whatever JWT the main app last wrote
//     into the App Group session blob; if it's expired the call 401s
//     and we fall back to whatever the widget already cached. The main
//     app refreshes on its next foreground tick and re-publishes — this
//     "best effort" semantic is exactly what timeline pulls want.
//
//  Companion files:
//   • `Fit33/SupabaseAppGroupStorage.swift` — main-app side that writes
//     the session blob this fetcher reads.
//   • `Fit33/Secrets.swift` (constants mirrored below — anon key is
//     public by design, URL is the project subdomain). When `Secrets`
//     gets rotated, mirror the values here in the SAME commit.
//

import Foundation
import OSLog

/// Public URL + anon key. Mirror of `Fit33/Secrets.swift::AppConfig`.
/// Both values are public-facing by design — the anon key has no
/// privileges beyond what RLS allows for the bearer JWT, and the URL
/// is just the project subdomain. Keep in sync if those rotate.
private enum WidgetSupabaseConfig {
    /// Static project URL. Wrapped in a force-unwrap on a literal that
    /// is verified-good at compile time — the only way this can fail
    /// is if someone edits the literal incorrectly, which would also
    /// fail the matching string in `Fit33/Secrets.swift`.
    static let url: URL = {
        guard let u = URL(string: "https://ehooeghabzefgoqzugrc.supabase.co") else {
            preconditionFailure("WidgetSupabaseConfig.url is malformed — keep in sync with Fit33/Secrets.swift")
        }
        return u
    }()
    static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVob29lZ2hhYnplZmdvcXp1Z3JjIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjM4NDc4NjQsImV4cCI6MjA3OTQyMzg2NH0.6-QWDr5B279hybtu9MbPVhmBKlyzFq1GK9P7zlDXuY0"
}

/// App Group session storage layout — verbatim mirror of constants in
/// `Fit33/SupabaseAppGroupStorage.swift`. The widget reads, never writes.
private enum WidgetSessionStorage {
    static let appGroupID = "group.com.fit33.app"
    static let storageKey = "fit33.supabase.session.v1"
    /// Final UserDefaults key the main-app side parks the session blob
    /// under. Matches `SupabaseAppGroupStorage.appGroupKey(for:)`'s
    /// "supabase.session.<storageKey>" prefix.
    static let userDefaultsKey = "supabase.session.fit33.supabase.session.v1"
}

/// Errors the fetcher can surface back to the timeline provider. The
/// provider doesn't show these to the user — it falls back to whatever's
/// already in the App Group cache and lets the freshness pill
/// (Phase 6) communicate "we're showing stale data".
enum WidgetSupabaseFetcherError: Error {
    /// `App Group UserDefaults` couldn't be opened — entitlement missing
    /// or `appGroupID` mismatch. Hard config problem, not a transient.
    case appGroupUnavailable
    /// No session JWT in the App Group — user is signed out OR the
    /// main app hasn't run a build new enough to publish via App
    /// Group storage yet. Treat as "no data, show empty state".
    case notAuthenticated
    /// Token decode failed. Indicates a corrupted session blob — log
    /// and fall through to App Group cache.
    case malformedSession
    /// HTTP layer failure (network down, DNS, TLS). Transient.
    case transport(Error)
    /// PostgREST returned non-2xx. `status` is the HTTP code; 401 means
    /// the JWT expired and the next main-app launch will refresh.
    case http(status: Int, body: String?)
    /// JSON parse failed on the response body. Indicates an API drift
    /// between this widget build and the deployed RPC — ship a new
    /// widget build to recover.
    case decode(Error)
}

/// Top-level fetcher used by `ActiveChallengeProvider.timeline` (Phase 3)
/// and by the widget's interactive refresh button (Phase 4).
enum WidgetSupabaseFetcher {

    /// Logger scoped to the widget extension. AppLogger isn't available
    /// in this target — `os.Logger` is the canonical replacement and
    /// surfaces in Console.app filtered to the widget process.
    private static let log = Logger(subsystem: "com.fit33.app.RunningActivityWidget", category: "supabase-fetch")

    // MARK: - Public API

    /// Single round-trip pull of the caller's active 1v1 challenges,
    /// returning the slim widget payload directly (already mapped from
    /// the `get_active_challenges` RPC response).
    ///
    /// - Parameters:
    ///   - timezone: IANA tz id, e.g. `"America/New_York"`. Drives the
    ///     RPC's `today` window. Default uses the device's current zone.
    ///   - timeout: Hard ceiling on the HTTP call. iOS gives the widget
    ///     extension ~30s of wall time per timeline tick; default 8s
    ///     leaves plenty of headroom for the rest of the provider work.
    ///     Phase 3's caller passes 3s for snappier first-paint.
    ///   - userDisplayName: Optional override for `myDisplayName`. The
    ///     widget process can't read `UserManager.currentUser` (it
    ///     lives in the main-app process), so the timeline provider
    ///     pulls the last-known name out of the App Group snapshot
    ///     and threads it through here. Falls back to nil.
    /// - Returns: One payload per active 1v1 challenge, already in the
    ///   "best pick first" order the widget UI expects (matches the
    ///   sort `ActiveChallengeWidgetBridge.publish` uses).
    static func fetchActiveChallenges(
        timezone: String = TimeZone.current.identifier,
        timeout: TimeInterval = 8.0,
        userDisplayName: String? = nil
    ) async throws -> [ActiveChallengeWidgetSnapshot.WidgetActiveChallenge] {
        let token = try readSessionAccessToken()
        let rows = try await postRPC(
            name: "get_active_challenges",
            body: ["p_timezone": timezone],
            jwt: token,
            timeout: timeout
        )
        // Explicit `sorted(by:)` (closure) instead of trailing-closure
        // `sorted` — Swift 6 picks up the new `sorted(using:)` overload
        // that takes a `SortComparator` and the trailing closure can't
        // be inferred as a comparator, so we pin the closure-based
        // overload explicitly.
        let sorted: [GetActiveChallengesRow] = rows.sorted(by: { (lhs: GetActiveChallengesRow, rhs: GetActiveChallengesRow) -> Bool in
            if lhs.days_remaining != rhs.days_remaining {
                return lhs.days_remaining < rhs.days_remaining
            }
            return (lhs.my_today_progress + lhs.opponent_today_progress)
                > (rhs.my_today_progress + rhs.opponent_today_progress)
        })
        return sorted.map { $0.toWidgetActiveChallenge(userDisplayName: userDisplayName) }
    }

    // MARK: - Session token reader

    /// Reads the access-token JWT out of the main-app-published session
    /// blob in App Group UserDefaults. Returns the raw JWT string ready
    /// to drop into `Authorization: Bearer <token>`.
    ///
    /// We deliberately decode only `access_token` from the blob —
    /// supabase-swift's full `Session` type has 8+ fields including
    /// nested `User`, all of which can drift across SDK versions. This
    /// minimal decoder is forward-compatible with any session shape
    /// that keeps `access_token` at the top level (true since 2.x).
    static func readSessionAccessToken() throws -> String {
        guard let defaults = UserDefaults(suiteName: WidgetSessionStorage.appGroupID) else {
            throw WidgetSupabaseFetcherError.appGroupUnavailable
        }
        guard let blob = defaults.data(forKey: WidgetSessionStorage.userDefaultsKey) else {
            throw WidgetSupabaseFetcherError.notAuthenticated
        }
        // snake_case property name matches supabase-swift's serialised
        // session blob shape — `Codable` synthesizes the right CodingKey.
        struct MinimalSession: Decodable {
            let access_token: String
        }
        do {
            let session = try JSONDecoder().decode(MinimalSession.self, from: blob)
            guard !session.access_token.isEmpty else {
                throw WidgetSupabaseFetcherError.malformedSession
            }
            return session.access_token
        } catch WidgetSupabaseFetcherError.malformedSession {
            throw WidgetSupabaseFetcherError.malformedSession
        } catch {
            log.error("Session blob decode failed: \(String(describing: error), privacy: .public)")
            throw WidgetSupabaseFetcherError.malformedSession
        }
    }

    // MARK: - RPC plumbing

    private static func postRPC(
        name: String,
        body: [String: String],
        jwt: String,
        timeout: TimeInterval
    ) async throws -> [GetActiveChallengesRow] {
        let url = WidgetSupabaseConfig.url
            .appendingPathComponent("rest/v1/rpc/\(name)")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = timeout
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(WidgetSupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
        // PostgREST returns RECORD-typed RPCs as a JSON array even when
        // there's a single row; no special header needed.
        do {
            req.httpBody = try JSONEncoder().encode(body)
        } catch {
            throw WidgetSupabaseFetcherError.transport(error)
        }

        // Per-call session — extension processes are short-lived; the
        // overhead of a fresh URLSession is negligible and avoids
        // sharing connection pools with anything that might outlive
        // the widget render.
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        config.waitsForConnectivity = false
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw WidgetSupabaseFetcherError.transport(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw WidgetSupabaseFetcherError.http(status: -1, body: nil)
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8)
            log.error("RPC \(name, privacy: .public) failed: HTTP \(http.statusCode) body=\(body ?? "<empty>", privacy: .public)")
            throw WidgetSupabaseFetcherError.http(status: http.statusCode, body: body)
        }

        do {
            let decoder = JSONDecoder()
            // Postgres returns ISO-8601 timestamps with optional
            // fractional seconds. Custom strategy handles both shapes.
            decoder.dateDecodingStrategy = .custom { d in
                let container = try d.singleValueContainer()
                let raw = try container.decode(String.self)
                if let parsed = isoFractionalFormatter.date(from: raw) { return parsed }
                if let parsed = isoFormatter.date(from: raw) { return parsed }
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Unrecognised TIMESTAMPTZ shape: \(raw)"
                )
            }
            return try decoder.decode([GetActiveChallengesRow].self, from: data)
        } catch {
            throw WidgetSupabaseFetcherError.decode(error)
        }
    }

    // MARK: - Date parsing

    private static let isoFractionalFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}

// MARK: - RPC row → widget model

/// Wire-format mirror of the `get_active_challenges` RPC's RETURNS
/// TABLE shape (post-migration #122 / 2026-04-26). Snake_case property
/// names match Postgres column output verbatim — Codable's synthesized
/// keys map 1:1, so adding a new column is just adding a new property
/// here. We deliberately decode only the subset the widget UI consumes;
/// the RPC returns ~28 columns and decoding all of them on every
/// timeline tick would waste extension CPU. Forward-compatible: extra
/// columns flowing through the wire are ignored, missing columns
/// surface as decode errors that fall through to the App Group cache.
private struct GetActiveChallengesRow: Decodable {
    let challenge_id: String
    let challenge_type: String
    let title: String
    let daily_target: Int?
    let target_unit: String
    let days_remaining: Int
    let duration_days: Int
    let my_today_progress: Int
    let my_current_streak: Int
    let opponent_id: String?
    let opponent_name: String?
    let opponent_photo_url: String?
    let opponent_today_progress: Int
    let am_winning_today: Bool
    let opponent_is_verified: Bool?
    let opponent_is_gold_verified: Bool?
    let my_last_progress_at: Date?
    let opponent_last_progress_at: Date?

    /// `WidgetActiveChallenge.displayTitle` does the emoji stripping +
    /// "10000 → 10K" formatting in the main app. Mirrors that here so
    /// the widget renders identically when the value flows from this
    /// fetcher path vs. the main-app `publish()` path.
    private var displayTitle: String {
        var t = title
        let modePrefixes = ["🤝 ", "⚔️ "]
        for prefix in modePrefixes where t.hasPrefix(prefix) {
            t = String(t.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        }
        // Strip a single leading emoji scalar (activity emoji like 🚶 / 🏃).
        while let first = t.unicodeScalars.first,
              first.properties.isEmoji && first.value > 0x238C {
            t = String(t.dropFirst()).trimmingCharacters(in: .whitespaces)
            if let next = t.unicodeScalars.first, next.value == 0xFE0F {
                t = String(t.dropFirst()).trimmingCharacters(in: .whitespaces)
            }
        }
        // 10000 → 10K, 25000 → 25K (matches the main app's regex).
        return t.replacingOccurrences(
            of: #"\b(\d{1,})(000)\b"#,
            with: "$1K",
            options: .regularExpression
        )
    }

    /// Mode is encoded into the title prefix in the main-app data model
    /// (see `ChallengeMode.from(title:)`). Mirror just enough of that
    /// here to set the widget's `"competition" / "accountability"` flag.
    private var inferredMode: String {
        title.hasPrefix("🤝 ") ? "accountability" : "competition"
    }

    func toWidgetActiveChallenge(userDisplayName: String?) -> ActiveChallengeWidgetSnapshot.WidgetActiveChallenge {
        ActiveChallengeWidgetSnapshot.WidgetActiveChallenge(
            challengeId: challenge_id,
            challengeType: challenge_type,
            displayTitle: displayTitle,
            mode: inferredMode,
            targetUnit: target_unit,
            dailyTarget: daily_target,
            daysRemaining: days_remaining,
            durationDays: duration_days,
            myTodayProgress: my_today_progress,
            opponentTodayProgress: opponent_today_progress,
            opponentId: opponent_id ?? "",
            opponentName: opponent_name,
            opponentPhotoUrl: opponent_photo_url,
            opponentIsVerified: opponent_is_verified ?? false,
            opponentIsGoldVerified: opponent_is_gold_verified ?? false,
            myCurrentStreak: my_current_streak,
            amWinningToday: am_winning_today,
            myDisplayName: userDisplayName,
            // Photos come from the App Group filesystem (see
            // `ActiveChallengeWidgetBridge.publish`'s photo mirroring).
            // The fetcher path doesn't write photos — leave the flags
            // FALSE; the widget UI falls back to initials, and the
            // next main-app launch re-publishes with `hasOpponentPhoto:
            // true`. Acceptable degradation while we're pulling fresh.
            hasUserPhoto: false,
            hasOpponentPhoto: false,
            myLastProgressAt: my_last_progress_at,
            opponentLastProgressAt: opponent_last_progress_at
        )
    }
}
