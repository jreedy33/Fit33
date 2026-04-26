//
//  WatchAppGroupSession.swift
//  Fit33Watch
//
//  Realtime Widget Server Pull — Phase 8b (2026-04-26).
//
//  Reads the supabase-swift session blob the iPhone main app writes
//  into App Group `group.com.fit33.app` (see
//  `Fit33/SupabaseAppGroupStorage.swift`). The watch is a READER —
//  it never writes a session, never refreshes a token, never logs
//  the user in. If the JWT is missing or expired, the watch goes
//  silent and the user is expected to open the iPhone app, which
//  will refresh the token and re-publish the session blob.
//
//  Same minimal-decoder shape as `WidgetSupabaseFetcher` —
//  forward-compatible with whatever supabase-swift's `Session`
//  serialisation looks like, as long as `access_token` stays
//  top-level (true since 2.x).

import Foundation
import OSLog

enum WatchAppGroupSession {
    static let appGroupID = "group.com.fit33.app"
    static let storageKey = "fit33.supabase.session.v1"
    static let userDefaultsKey = "supabase.session.fit33.supabase.session.v1"

    private static let log = Logger(subsystem: "com.fit33.app.watchapp", category: "session")

    enum AccessTokenError: Error {
        case appGroupUnavailable
        case notAuthenticated
        case malformedSession
    }

    /// Returns the access-token JWT ready for `Authorization: Bearer …`.
    /// Throws the matching error case so the caller can decide whether
    /// to no-op (`notAuthenticated`) or surface a diagnostic.
    static func readAccessToken() throws -> String {
        guard let defaults = UserDefaults(suiteName: appGroupID) else {
            throw AccessTokenError.appGroupUnavailable
        }
        guard let blob = defaults.data(forKey: userDefaultsKey) else {
            throw AccessTokenError.notAuthenticated
        }
        struct MinimalSession: Decodable { let access_token: String }
        do {
            let session = try JSONDecoder().decode(MinimalSession.self, from: blob)
            guard !session.access_token.isEmpty else { throw AccessTokenError.malformedSession }
            return session.access_token
        } catch {
            log.error("Watch session decode failed: \(String(describing: error), privacy: .public)")
            throw AccessTokenError.malformedSession
        }
    }

    /// Pulls the user_id out of the JWT payload so the watch can
    /// identify itself locally without a network round-trip. We DON'T
    /// trust this for security — every RPC call is RLS-pinned to
    /// `auth.uid()` server-side. We just use it for log lines and to
    /// bail early if the user signed out and back in as someone else.
    static func cachedUserId() -> String? {
        guard let token = try? readAccessToken() else { return nil }
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var payload = String(parts[1])
        // JWT base64-url → base64 padding fixup.
        payload = payload
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let mod = payload.count % 4
        if mod != 0 { payload += String(repeating: "=", count: 4 - mod) }
        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sub = json["sub"] as? String
        else { return nil }
        return sub
    }
}
