//
//  WatchSupabaseClient.swift
//  Fit33Watch
//
//  Realtime Widget Server Pull — Phase 8c (2026-04-26).
//
//  URLSession-based PostgREST client for the watch process. Same
//  shape as `RunningActivityWidget/WidgetSupabaseFetcher.swift` —
//  no supabase-swift SDK, no Realtime websocket, just one POST per
//  RPC call. Watch extensions have an even tighter memory budget
//  than the widget (~30MB) AND have to survive being woken
//  briefly via background-refresh tasks, so a lean fetch path is
//  doubly important here.
//
//  Public API surface:
//    • `logChallengeProgress(challengeId:progress:)` — wraps the
//      `log_challenge_progress` RPC the iPhone app calls from
//      `ChallengeService.logProgress`.
//
//  Anti-patterns deliberately NOT supported (intentional gaps):
//    • No Realtime subscriptions. The watch is a writer, not a
//      reader.
//    • No batch RPC. We post one progress row per (challenge,
//      activity) per observer fire — the RPC dedups via upsert.
//    • No retry / backoff. If a call fails, we drop it and rely on
//      the next observer fire to repost. The iPhone widget pull is
//      our consistency layer.

import Foundation
import OSLog

enum WatchSupabaseConfig {
    static let url: URL = {
        guard let u = URL(string: "https://ehooeghabzefgoqzugrc.supabase.co") else {
            preconditionFailure("WatchSupabaseConfig.url malformed — keep in sync with Fit33/Secrets.swift")
        }
        return u
    }()
    /// Anon key — matches `Fit33/Secrets.swift` and
    /// `RunningActivityWidget/WidgetSupabaseFetcher.swift`. Public by
    /// design; RLS bounds what the bearer JWT can do.
    static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVob29lZ2hhYnplZmdvcXp1Z3JjIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjM4NDc4NjQsImV4cCI6MjA3OTQyMzg2NH0.6-QWDr5B279hybtu9MbPVhmBKlyzFq1GK9P7zlDXuY0"
}

enum WatchSupabaseError: Error {
    case notAuthenticated
    case http(status: Int, body: String?)
    case transport(Error)
    case encoding(Error)
    case decode(Error)
}

enum WatchSupabaseClient {
    private static let log = Logger(subsystem: "com.fit33.app.watchapp", category: "supabase")

    /// Posts a `log_challenge_progress` RPC. The signature mirrors the
    /// 1v1/group RPC that `ChallengeService.swift::logProgress` invokes
    /// on iPhone. We deliberately don't model the response — the
    /// iPhone app reads progress separately via its own polling, and
    /// the watch only cares whether the write landed.
    ///
    /// - Parameters:
    ///   - challengeId: UUID of the challenge.
    ///   - progress: integer count value (steps, active minutes, calories…).
    ///   - timezone: caller IANA tz, defaults to wrist's current tz.
    static func logChallengeProgress(
        challengeId: String,
        progress: Int,
        timezone: String = TimeZone.current.identifier
    ) async throws {
        let token: String
        do {
            token = try WatchAppGroupSession.readAccessToken()
        } catch {
            throw WatchSupabaseError.notAuthenticated
        }

        struct Body: Encodable {
            let p_challenge_id: String
            let p_progress_value: Int
            let p_timezone: String
        }
        let body = Body(p_challenge_id: challengeId, p_progress_value: progress, p_timezone: timezone)

        let url = WatchSupabaseConfig.url.appendingPathComponent("rest/v1/rpc/log_challenge_progress")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 10
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(WatchSupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        do {
            req.httpBody = try JSONEncoder().encode(body)
        } catch {
            throw WatchSupabaseError.encoding(error)
        }

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        config.waitsForConnectivity = false
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw WatchSupabaseError.transport(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw WatchSupabaseError.http(status: -1, body: nil)
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8)
            log.error("log_challenge_progress \(http.statusCode) \(body ?? "<empty>", privacy: .public)")
            throw WatchSupabaseError.http(status: http.statusCode, body: body)
        }
        log.debug("log_challenge_progress OK challenge=\(challengeId, privacy: .public) progress=\(progress)")
    }

    /// Pulls the caller's active 1v1 challenges via `get_active_challenges`.
    /// Mirrors `RunningActivityWidget/WidgetSupabaseFetcher.fetchActiveChallenges`
    /// but slimmer — the watch only needs the columns the Today screen
    /// renders. Best-effort: on failure, callers fall back to whatever
    /// the App Group cache last saw.
    static func fetchActiveChallenges(
        timezone: String = TimeZone.current.identifier,
        timeout: TimeInterval = 8.0
    ) async throws -> [WatchActiveChallenge] {
        let token: String
        do {
            token = try WatchAppGroupSession.readAccessToken()
        } catch {
            throw WatchSupabaseError.notAuthenticated
        }

        let url = WatchSupabaseConfig.url
            .appendingPathComponent("rest/v1/rpc/get_active_challenges")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = timeout
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(WatchSupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        struct Body: Encodable { let p_timezone: String }
        do {
            req.httpBody = try JSONEncoder().encode(Body(p_timezone: timezone))
        } catch {
            throw WatchSupabaseError.encoding(error)
        }

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
            throw WatchSupabaseError.transport(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw WatchSupabaseError.http(status: -1, body: nil)
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8)
            log.error("get_active_challenges \(http.statusCode) \(body ?? "<empty>", privacy: .public)")
            throw WatchSupabaseError.http(status: http.statusCode, body: body)
        }

        do {
            let decoder = JSONDecoder()
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
            let rows = try decoder.decode([GetActiveChallengesRow].self, from: data)
            // Best-pick first: closest deadline, then most-active today.
            // Mirror of `WidgetSupabaseFetcher`'s sort to keep the
            // widget + watch + main app showing the same "top" challenge.
            let sorted = rows.sorted { lhs, rhs in
                if lhs.days_remaining != rhs.days_remaining {
                    return lhs.days_remaining < rhs.days_remaining
                }
                return (lhs.my_today_progress + lhs.opponent_today_progress)
                    > (rhs.my_today_progress + rhs.opponent_today_progress)
            }
            return sorted.map { $0.toWatchActiveChallenge() }
        } catch {
            throw WatchSupabaseError.decode(error)
        }
    }

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

// MARK: - RPC row → watch model

/// Wire-format mirror of the subset of `get_active_challenges` columns
/// the watch UI consumes. snake_case property names match Postgres
/// output verbatim — Codable's synthesised CodingKeys map 1:1.
private struct GetActiveChallengesRow: Decodable {
    let challenge_id: String
    let challenge_type: String
    let title: String
    let daily_target: Int?
    let target_unit: String
    let days_remaining: Int
    let my_today_progress: Int
    let my_current_streak: Int
    let opponent_name: String?
    let opponent_today_progress: Int
    let am_winning_today: Bool
    let my_last_progress_at: Date?
    let opponent_last_progress_at: Date?

    func toWatchActiveChallenge() -> WatchActiveChallenge {
        WatchActiveChallenge(
            id: challenge_id,
            title: title,
            challengeType: challenge_type,
            dailyTarget: daily_target,
            targetUnit: target_unit,
            daysRemaining: days_remaining,
            myTodayProgress: my_today_progress,
            myCurrentStreak: my_current_streak,
            opponentName: opponent_name,
            opponentTodayProgress: opponent_today_progress,
            amWinningToday: am_winning_today,
            myLastProgressAt: my_last_progress_at,
            opponentLastProgressAt: opponent_last_progress_at
        )
    }
}
