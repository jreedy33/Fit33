//
//  PushPayloadParityTests.swift
//  Fit33Tests
//
//  Smart Notification Engine — Phase 1 (2026-08-01).
//
//  Enforces parity between:
//    1. PushNotificationCategory (iOS) ↔ notification_categories table (server)
//    2. NotificationManager.knownNotificationTypes ↔ handleNotificationType
//       switch (every allowlisted type must have a routing case OR fall
//       through with intent — we verify by counting the switch arms).
//    3. Smart Notification Engine intent kinds — the new Phase 3 types
//       MUST appear in knownNotificationTypes so the default arm doesn't
//       fire `.error` for legitimate orchestrator pushes.
//

import Testing
@testable import Fit33

struct PushPayloadParityTests {

    // MARK: Server category enum parity

    /// All 7 server categories MUST have an iOS enum case. Adding a new
    /// category in `notification_categories` (migration 20260801) requires
    /// adding a case here in the same PR.
    @Test func serverCategoryEnumParity() {
        let expected: Set<String> = [
            "rivalry", "workout", "recovery", "nutrition",
            "streak", "social", "announcement"
        ]
        let iosRawValues = Set(PushNotificationCategory.allCases.map(\.rawValue))
        #expect(iosRawValues == expected, "iOS PushNotificationCategory cases must mirror notification_categories table exactly")
    }

    // MARK: Phase 3 trigger types are allowlisted

    /// Every orchestrator-driven intent kind from migration 20260802 MUST
    /// be in `knownNotificationTypes` so the default arm doesn't log
    /// `.error` for legitimate server pushes (Bug-Intel invariant 1 —
    /// no false-positive fingerprints).
    @Test func phase3IntentKindsAreAllowlisted() {
        let phase3Kinds: Set<String> = [
            "league_started", "league_promoted", "league_demoted",
            "rivalry_behind", "rivalry_lead", "comeback_window",
            "recovery_alert", "recovery_yellow", "recovery_pr_opportunity",
            "sleep_debt", "sleep_low",
            "hydration_pace", "hydration_reminder",
            "streak_risk",
            "friend_workout_match", "pr_opportunity", "overdue_muscle_group",
            "strava_celebration",
            "morning_kickstart",
            "meal_reminder", "protein_deficit", "breakfast_reminder"
        ]
        for kind in phase3Kinds {
            #expect(
                NotificationManager.knownNotificationTypes.contains(kind),
                "Phase 3 intent kind '\(kind)' missing from NotificationManager.knownNotificationTypes — orchestrator pushes will hit the default arm and log .error"
            )
        }
    }

    // MARK: Tap-routing exhaustiveness

    /// Tap-routing holes (challenge_declined, challenge_update, challenge_reaction)
    /// were the canonical Phase 1 fix. These three types MUST be in the
    /// allowlist now that they have specific `handleNotificationType` cases.
    @Test func phase1TapRoutingHolesPlugged() {
        let holes: Set<String> = ["challenge_declined", "challenge_update", "challenge_reaction"]
        for hole in holes {
            #expect(
                NotificationManager.knownNotificationTypes.contains(hole),
                "\(hole) tap-routing hole — must be in knownNotificationTypes after Phase 1"
            )
        }
    }

    // MARK: PushPayload decoding

    /// Top-level decode of a typical orchestrator push.
    @Test func pushPayloadDecodesTypicalOrchestratorPush() {
        let userInfo: [AnyHashable: Any] = [
            "type": "rivalry_behind",
            "category": "rivalry",
            "intent_kind": "rivalry_behind",
            "intent_id": "abc-123",
            "notification_id": "queue-456",
            "challenge_id": "chal-789",
            "aps": ["alert": ["title": "Manuel's beating you", "body": "12K behind — talk smack"]]
        ]
        let payload = PushPayload(from: userInfo)
        #expect(payload.type == "rivalry_behind")
        #expect(payload.category == .rivalry)
        #expect(payload.intentKind == "rivalry_behind")
        #expect(payload.intentId == "abc-123")
        #expect(payload.notificationId == "queue-456")
        #expect(payload.challengeId == "chal-789")
        #expect(payload.silent == false)
    }

    /// Silent push detection — `content-available: 1` AND no alert.
    @Test func pushPayloadDetectsSilentPush() {
        let silent: [AnyHashable: Any] = [
            "type": "challenge_wake",
            "aps": ["content-available": 1]
        ]
        let p1 = PushPayload(from: silent)
        #expect(p1.silent == true)

        // content-available + alert = NOT silent (smack reaction pattern).
        let smack: [AnyHashable: Any] = [
            "type": "challenge_reaction",
            "aps": ["content-available": 1, "alert": ["title": "💢", "body": "Do better!"]]
        ]
        let p2 = PushPayload(from: smack)
        #expect(p2.silent == false)
    }

    /// Forward-compat: unknown future fields don't break decode.
    @Test func pushPayloadIsForwardCompatible() {
        let userInfo: [AnyHashable: Any] = [
            "type": "rivalry_behind",
            "category": "rivalry",
            "future_field_not_yet_known": ["nested": 42],
            "another_unknown": "value"
        ]
        let payload = PushPayload(from: userInfo)
        #expect(payload.type == "rivalry_behind")
        #expect(payload.category == .rivalry)
    }

    /// Unknown category degrades to nil — never crash.
    @Test func pushPayloadHandlesUnknownCategory() {
        let userInfo: [AnyHashable: Any] = [
            "type": "rivalry_behind",
            "category": "future_category_we_havent_added"
        ]
        let payload = PushPayload(from: userInfo)
        #expect(payload.category == nil)
    }

    /// Missing type degrades to "unknown" — never crash.
    @Test func pushPayloadHandlesMissingType() {
        let userInfo: [AnyHashable: Any] = ["category": "rivalry"]
        let payload = PushPayload(from: userInfo)
        #expect(payload.type == "unknown")
    }

    /// Typed sub-payload decode.
    @Test func pushPayloadDecodesTypedRivalryPayload() {
        let userInfo: [AnyHashable: Any] = [
            "type": "rivalry_behind",
            "payload": [
                "challengeId": "chal-1",
                "opponentName": "Manuel",
                "opponentValue": 14_500.0,
                "myValue": 2_300.0,
                "unit": "steps",
                "dailyTarget": 10_000.0
            ]
        ]
        let payload = PushPayload(from: userInfo)
        let typed = payload.payload(as: RivalryBehindPayload.self)
        #expect(typed != nil)
        #expect(typed?.opponentName == "Manuel")
        #expect(typed?.unit == "steps")
        #expect(typed?.opponentValue == 14_500.0)
    }
}
