import Foundation

// =============================================================================
// PushPayload — Typed Codable for APNs payloads (2026-08-01).
// =============================================================================
//
// Single source of truth for parsing inbound push payloads on iOS. Replaces
// stringly-typed `userInfo[anyKey] as? String` access scattered across
// `NotificationManager.handleNotificationType` and `SilentPushHandler.handle`.
//
// Server enum is in `supabase/functions/_shared/apns.ts` and the
// `notification_categories` table (migration 20260801). Parity is enforced
// by `Fit33Tests/PushPayloadParityTests.swift`.
//
// Two-phase decode strategy:
//   1. Top-level decode pulls `type` (REQUIRED) + `category` + `intent_kind`.
//   2. Per-type decoded payloads (e.g. `RivalryBehindPayload`) are fetched
//      lazily via `payload(as:)` so unknown future fields don't break old
//      clients (forward-compat).
//
// All decode methods return `nil` instead of throwing — push payloads MUST
// fail-safe and always degrade to "unknown — route to dashboard" rather
// than crash the receiver.
// =============================================================================

// MARK: - Notification Category (mirror of server enum)

/// Mirror of the 7-category enum in `notification_categories` table
/// (migration 20260801). Adding a new server category MUST add a case here
/// in the same PR — `PushPayloadParityTests` enforces this.
enum PushNotificationCategory: String, Codable, CaseIterable {
    case rivalry
    case workout
    case recovery
    case nutrition
    case streak
    case social
    case announcement

    /// SF Symbol surfaced in the in-app notification audit feed.
    var icon: String {
        switch self {
        case .rivalry:      return "shield.lefthalf.filled"
        case .workout:      return "dumbbell.fill"
        case .recovery:     return "heart.text.square.fill"
        case .nutrition:    return "fork.knife"
        case .streak:       return "flame.fill"
        case .social:       return "person.2.fill"
        case .announcement: return "megaphone.fill"
        }
    }

    var emoji: String {
        switch self {
        case .rivalry:      return "⚔️"
        case .workout:      return "💪"
        case .recovery:     return "❤️"
        case .nutrition:    return "🥗"
        case .streak:       return "🔥"
        case .social:       return "👋"
        case .announcement: return "📣"
        }
    }
}

// MARK: - Top-Level PushPayload

/// Canonical parsed shape of every inbound APNs payload.
///
/// We do NOT enumerate every payload field at this level — the wire format
/// must stay forward-compatible. `data` exposes the raw `[String: Any]`
/// for type-specific helpers (`payload(as:)`).
struct PushPayload {

    /// Routing key. Always present in well-formed pushes; falls back to
    /// `"unknown"` when the server omits `type` (legacy / drift).
    let type: String

    /// One of the 7 categories from `notification_categories`. NIL for
    /// pre-categorized legacy pushes — UI defaults to `.social`.
    let category: PushNotificationCategory?

    /// Orchestrator intent kind (Phase 2+). NIL for pre-orchestrator pushes.
    /// Examples: `league_started`, `rivalry_behind`, `recovery_alert`,
    /// `hydration_pace`, `streak_risk`.
    let intentKind: String?

    /// `notification_intents.id` — set by the orchestrator so the
    /// `record-push-event` edge fn can correlate `delivered`/`opened`
    /// callbacks back to a single intent for engagement learning.
    let intentId: String?

    /// `push_notification_queue.id` — used by the same correlation path.
    let notificationId: String?

    /// Raw payload bag. Use `payload(as:)` for typed decoding instead of
    /// reaching in directly.
    let data: [String: Any]

    /// Foreground-time presentation hint. When `silent == true`, the iOS
    /// receiver MUST NOT call the foreground completion handler with
    /// `.banner` (silent pushes are background-only). The shared APNs
    /// helper sets `aps.content-available = 1` and OMITS `aps.alert`
    /// for these.
    let silent: Bool

    // MARK: Construction

    /// Parse from a raw `userInfo: [AnyHashable: Any]` (the shape iOS
    /// hands us in `userNotificationCenter` and
    /// `application(_:didReceiveRemoteNotification:)`).
    init(from userInfo: [AnyHashable: Any]) {
        var data: [String: Any] = [:]
        for (key, value) in userInfo {
            if let stringKey = key as? String {
                data[stringKey] = value
            }
        }

        self.type = (data["type"] as? String) ?? "unknown"

        if let categoryRaw = data["category"] as? String,
           let parsed = PushNotificationCategory(rawValue: categoryRaw) {
            self.category = parsed
        } else {
            self.category = nil
        }

        self.intentKind = data["intent_kind"] as? String
        self.intentId = data["intent_id"] as? String
        self.notificationId = data["notification_id"] as? String

        // `aps.content-available == 1` AND no alert payload = silent.
        if let aps = data["aps"] as? [String: Any] {
            let hasContentAvailable = (aps["content-available"] as? Int) == 1
            let hasAlert = aps["alert"] != nil
            self.silent = hasContentAvailable && !hasAlert
        } else {
            self.silent = false
        }

        self.data = data
    }

    // MARK: Convenience accessors

    /// Common UUID-shaped fields the iOS routers consult.
    var challengeId: String? { data["challenge_id"] as? String }
    var workoutId: String? { data["workout_id"] as? String }
    var friendId: String? { data["friend_id"] as? String }
    var inviteSlug: String? { data["invite_slug"] as? String }

    /// Deep-link override hint set by the orchestrator. When present, the
    /// receiver routes to the named `DeepLinkManager.Destination` even if
    /// the type's normal handler would land somewhere else (lets product
    /// tweak destinations without an iOS ship). Examples:
    ///   `"leagues"`, `"smack_talk:<challengeId>"`, `"readiness_detail"`.
    var deepLinkOverride: String? { data["deep_link"] as? String }

    /// Decode an embedded typed payload from the `payload` JSON object.
    /// Returns nil when the field is absent or doesn't match `T`'s shape —
    /// the caller MUST fall back to a degrade-gracefully default.
    func payload<T: Decodable>(as _: T.Type) -> T? {
        guard let nested = data["payload"] else { return nil }
        do {
            let json = try JSONSerialization.data(withJSONObject: nested, options: [])
            return try JSONDecoder().decode(T.self, from: json)
        } catch {
            return nil
        }
    }
}

// MARK: - Per-intent typed payloads
//
// These mirror the `payload` JSONB written by intent producers (Phase 3
// SQL functions). Each is loose-typed (everything optional except the
// universally-present fields) so a server addition can't break receive.

/// `intent_kind = "league_started"` — Monday 8am league rollover push.
struct LeagueStartedPayload: Decodable {
    let tier: String?              // bronze / silver / gold / platinum / diamond
    let weekStart: String?         // YYYY-MM-DD
    let xpToFirst: Int?            // XP gap to first place
    let opponentCount: Int?        // members in user's tier
}

/// `intent_kind = "rivalry_behind"` — opponent is leading mid-day.
struct RivalryBehindPayload: Decodable {
    let challengeId: String?
    let opponentName: String?
    let opponentValue: Double?     // their progress today
    let myValue: Double?           // your progress today
    let unit: String?              // steps / minutes / workouts / calories
    let dailyTarget: Double?       // shared target
}

/// `intent_kind = "recovery_alert"` — WHOOP/Oura red-band morning.
struct RecoveryAlertPayload: Decodable {
    let recoveryScore: Int?        // 0-100
    let band: String?              // green / yellow / red
    let primarySource: String?     // whoop / oura / appleHealth
    let suggestedWorkout: String?  // mobility / yoga / light_cardio
    let hrvDeltaPct: Double?       // -18 = HRV down 18%
}

/// `intent_kind = "sleep_debt"` — 9pm bedtime nudge.
struct SleepDebtPayload: Decodable {
    let neededHours: Double?       // 6.4
    let tonightDeadline: String?   // ISO8601 — when they need to be in bed
    let projectedHours: Double?    // current pace
    let sleepNeed: Double?         // baseline
}

/// `intent_kind = "hydration_pace"` — pace-aware water reminder.
struct HydrationPacePayload: Decodable {
    let consumedOz: Int?
    let goalOz: Int?
    let deficitOz: Int?
    let timeOfDay: String?         // "morning" / "midday" / "afternoon" / "evening"
}

/// `intent_kind = "streak_risk"` — after-6pm streak protection.
struct StreakRiskPayload: Decodable {
    let streakDays: Int?
    let questsCompleted: Int?
    let questsRemaining: Int?
    let suggestedQuestKey: String? // which quest to focus
}

/// `intent_kind = "friend_workout_match"` — friend just hit a muscle group
/// you're overdue on.
struct FriendWorkoutMatchPayload: Decodable {
    let friendName: String?
    let muscleGroup: String?       // chest / back / legs / etc.
    let daysSinceYouTrainedIt: Int?
    let workoutId: String?         // their just-completed workout for cloning
}

/// `intent_kind = "strava_celebration"` — post-Strava-import celebration.
struct StravaCelebrationPayload: Decodable {
    let activityType: String?      // run / ride / swim / hike
    let distanceMeters: Int?
    let durationSeconds: Int?
    let elevationGainM: Int?
    let activityId: String?
}

// MARK: - Silent push payloads (ride the same wire format)

/// `type = "challenge_wake"` — wake-challenge-opponents silent push.
struct ChallengeWakePayload: Decodable {
    let source: String?            // foreground / cron / progress_update
    let writerId: String?
    let challengeId: String?
}

/// `type = "strava_activity_new"` — strava-webhook silent push.
struct StravaSilentPayload: Decodable {
    let activityId: String?
}

/// `type = "challenge_reaction"` — smack-talk visible-alert push that ALSO
/// rides `content-available: 1` so SmackTalkWidgetBridge can paint before
/// the user opens.
struct SmackReactionPayload: Decodable {
    let challengeId: String?
    let reactionEmoji: String?
    let reactionText: String?
    let reactionCategory: String?
    let fromUserName: String?
}
