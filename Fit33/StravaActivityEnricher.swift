//
//  StravaActivityEnricher.swift
//  Fit33
//
//  Phase 2 of the Strava Integration Upgrade. After `StravaService.syncActivities`
//  writes the list-endpoint payload to `cardio_workouts`, this enricher
//  fetches richer per-activity data via:
//
//    GET /activities/{id}                  — splits, segment efforts, gear,
//                                            kudos, suffer score, polyline.
//    GET /activities/{id}/streams          — HR / pace / cadence / power /
//                                            altitude time-series.
//
//  …and writes the JSON straight into the matching `cardio_workouts` row
//  (columns added in `supabase/20260530_cardio_workouts_strava_detail.sql`).
//
//  Strava's API rate limits are 200 requests / 15 minutes and 2000 / day for
//  a single token (per https://developers.strava.com/docs/rate-limits/). The
//  enricher therefore uses a simple sliding-window throttle so a user with
//  a backlog of activities (e.g. just-connected account) doesn't burn the
//  entire daily budget in one sync pass.
//

import Foundation

@MainActor
final class StravaActivityEnricher {
    static let shared = StravaActivityEnricher()

    /// Maximum API calls (detail + streams) we allow per 15-min window.
    /// Each enrichment pass costs **two** API calls (detail + streams), so
    /// 30 here = 60 requests / 15min, well under Strava's 200 / 15min ceiling
    /// and leaves headroom for token refresh + foreground sync calls.
    private static let maxRequestsPerWindow = 30

    /// Sliding window length (seconds).
    private static let windowSeconds: TimeInterval = 15 * 60

    /// Per-activity timestamps of recently issued requests. Trimmed in-place.
    private var recentRequestTimestamps: [Date] = []

    /// Set of activity ids currently being enriched, to dedupe overlapping
    /// triggers (e.g. dashboard refresh racing with foreground sync).
    private var inFlight: Set<Int64> = []

    private init() {}

    // MARK: - Public entry points

    /// Enrich every activity in `activities` that is currently missing detail
    /// data. Skips already-in-flight ids and short-circuits when the rate
    /// limit is exhausted. Safe to call from `StravaService.syncActivities`.
    func enrichIfNeeded(activities: [StravaActivity]) async {
        guard !activities.isEmpty else { return }
        guard let userId = SupabaseManager.shared.currentUser?.id else { return }

        // Find the activity ids that haven't been enriched yet so we don't
        // burn the rate budget re-fetching every detail on every sync.
        let pendingIds = await fetchPendingActivityIds(
            userId: userId.uuidString,
            candidateIds: activities.map { String($0.id) }
        )
        guard !pendingIds.isEmpty else { return }

        for activity in activities where pendingIds.contains(String(activity.id)) {
            // Bail out if we've exhausted the window — the next sync will
            // pick up where we left off (the partial-index migration only
            // matches `detail_synced_at IS NULL` rows).
            guard hasBudget(forCalls: 2) else {
                AppLogger.debug("⏳ [STRAVA-ENRICH] Rate-limit window exhausted, deferring \(pendingIds.count - 1) more activities", category: .health)
                return
            }
            guard !inFlight.contains(activity.id) else { continue }
            await enrich(activity: activity, userId: userId.uuidString)
        }
    }

    // MARK: - Per-activity enrichment

    private func enrich(activity: StravaActivity, userId: String) async {
        inFlight.insert(activity.id)
        defer { inFlight.remove(activity.id) }

        do {
            consume(calls: 1)
            let detail = try await StravaService.shared.getActivityDetailJSON(id: activity.id)

            // Streams are best-effort — manually logged activities have none.
            consume(calls: 1)
            let streams: [String: Any]
            do {
                streams = try await StravaService.shared.getActivityStreamsJSON(id: activity.id)
            } catch {
                AppLogger.debug("ℹ️ [STRAVA-ENRICH] No streams for \(activity.id): \(error.localizedDescription)", category: .health)
                streams = [:]
            }

            try await persist(
                userId: userId,
                activityId: activity.id,
                detail: detail,
                streams: streams
            )

            AppLogger.debug("✨ [STRAVA-ENRICH] Enriched activity \(activity.id) (\(activity.type))", category: .health)
        } catch {
            // Don't fingerprint — Strava 401s during token rotation and 429
            // rate-limit hits are operational, not bugs.
            AppLogger.debug("⚠️ [STRAVA-ENRICH] Failed to enrich \(activity.id): \(error.localizedDescription)", category: .health)
        }
    }

    // MARK: - Persistence

    private func persist(
        userId: String,
        activityId: Int64,
        detail: [String: Any],
        streams: [String: Any]
    ) async throws {
        let polyline = (detail["map"] as? [String: Any]).flatMap { $0["summary_polyline"] as? String }
        let gear = (detail["gear"] as? [String: Any])?["name"] as? String
        let suffer = detail["suffer_score"] as? Int
        let kudos = detail["kudos_count"] as? Int
        let achievements = detail["achievement_count"] as? Int
        let splitsArray = detail["splits_metric"] as? [[String: Any]]
        let segmentEfforts = detail["segment_efforts"] as? [[String: Any]]

        let update = StravaCardioWorkoutDetailUpdate(
            sufferScore: suffer,
            kudosCount: kudos,
            achievementCount: achievements,
            polylineSummary: polyline,
            gearName: gear,
            splitsJson: JSONAnyValue.fromArrayOfDicts(splitsArray),
            segmentEffortsJson: JSONAnyValue.fromArrayOfDicts(segmentEfforts),
            streamsJson: streams.isEmpty ? nil : JSONAnyValue.from(streams),
            detailSyncedAt: ISO8601DateFormatter().string(from: Date())
        )

        try await SupabaseManager.shared.supabaseClient
            .from("cardio_workouts")
            .update(update)
            .eq("user_id", value: userId)
            .eq("source", value: "strava")
            .eq("external_id", value: String(activityId))
            .execute()
    }

    // MARK: - Pending-id discovery

    private func fetchPendingActivityIds(userId: String, candidateIds: [String]) async -> Set<String> {
        guard !candidateIds.isEmpty else { return [] }
        do {
            // Pull only `external_id` for this user's already-enriched Strava
            // rows (those with non-null `detail_synced_at`). Anything in
            // `candidateIds` not present in that response is pending.
            let enriched: [PendingExternalIDRow] = try await SupabaseManager.shared.supabaseClient
                .from("cardio_workouts")
                .select("external_id")
                .eq("user_id", value: userId)
                .eq("source", value: "strava")
                .in("external_id", values: candidateIds)
                .not("detail_synced_at", operator: .is, value: "null")
                .execute()
                .value

            let alreadyEnriched = Set(enriched.compactMap { $0.external_id })
            return Set(candidateIds).subtracting(alreadyEnriched)
        } catch {
            AppLogger.debug("ℹ️ [STRAVA-ENRICH] Pending-id query failed (\(error.localizedDescription)) — assuming all candidates need enrichment", category: .health)
            return Set(candidateIds)
        }
    }

    // MARK: - Rate-limit accounting

    private func trimWindow() {
        let cutoff = Date().addingTimeInterval(-Self.windowSeconds)
        recentRequestTimestamps.removeAll { $0 < cutoff }
    }

    private func hasBudget(forCalls count: Int) -> Bool {
        trimWindow()
        return recentRequestTimestamps.count + count <= Self.maxRequestsPerWindow
    }

    private func consume(calls: Int) {
        let now = Date()
        for _ in 0..<calls { recentRequestTimestamps.append(now) }
    }
}

// MARK: - DTOs

private struct PendingExternalIDRow: Decodable {
    let external_id: String?
}

/// Update payload — only the fields we want to overwrite. Snake-case keys
/// declared explicitly to stay consistent with the rest of the Supabase DTOs
/// in this codebase.
private struct StravaCardioWorkoutDetailUpdate: Encodable {
    let sufferScore: Int?
    let kudosCount: Int?
    let achievementCount: Int?
    let polylineSummary: String?
    let gearName: String?
    let splitsJson: JSONAnyValue?
    let segmentEffortsJson: JSONAnyValue?
    let streamsJson: JSONAnyValue?
    let detailSyncedAt: String

    enum CodingKeys: String, CodingKey {
        case sufferScore = "suffer_score"
        case kudosCount = "kudos_count"
        case achievementCount = "achievement_count"
        case polylineSummary = "polyline_summary"
        case gearName = "gear_name"
        case splitsJson = "splits_json"
        case segmentEffortsJson = "segment_efforts_json"
        case streamsJson = "streams_json"
        case detailSyncedAt = "detail_synced_at"
    }
}

/// Recursive JSON value used to forward Strava JSON straight to a Postgres
/// JSONB column. We don't need to decode these on the Swift side — the
/// recap sheet, insights computer, and future RPCs consume the JSONB in
/// SQL — so this is encoder-only.
indirect enum JSONAnyValue: Encodable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([JSONAnyValue])
    case object([String: JSONAnyValue])
    case null

    static func from(_ any: Any?) -> JSONAnyValue {
        guard let any else { return .null }
        if any is NSNull { return .null }
        if let s = any as? String { return .string(s) }
        // NSNumber covers Int, Double, and Bool when bridged from
        // JSONSerialization. Disambiguate Bool first via CFBooleanGetTypeID.
        if let n = any as? NSNumber {
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return .bool(n.boolValue) }
            let objCType = String(cString: n.objCType)
            if ["c", "i", "s", "l", "q", "C", "I", "S", "L", "Q"].contains(objCType) {
                return .int(n.intValue)
            }
            return .double(n.doubleValue)
        }
        if let arr = any as? [Any] { return .array(arr.map { JSONAnyValue.from($0) }) }
        if let dict = any as? [String: Any] {
            return .object(dict.mapValues { JSONAnyValue.from($0) })
        }
        return .null
    }

    static func fromArrayOfDicts(_ arr: [[String: Any]]?) -> JSONAnyValue? {
        guard let arr, !arr.isEmpty else { return nil }
        return .array(arr.map { JSONAnyValue.from($0) })
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let v): try container.encode(v)
        case .int(let v): try container.encode(v)
        case .double(let v): try container.encode(v)
        case .bool(let v): try container.encode(v)
        case .array(let v): try container.encode(v)
        case .object(let v): try container.encode(v)
        case .null: try container.encodeNil()
        }
    }
}
