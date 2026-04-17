//
//  NotificationAllowlistTests.swift
//  Fit33Tests
//
//  Sprint 2 Q2-36 — Guard against server drift. Every `NotificationType`
//  raw value (shipped to servers + edge functions) must appear in
//  `NotificationManager.knownNotificationTypes`. When a new notification
//  type is added to the enum, this test fails until the allowlist is
//  updated — preventing the default case from silently no-opping.
//

import Testing
@testable import Fit33

struct NotificationAllowlistTests {

    @Test func everyEnumCaseIsAllowed() {
        for caseValue in NotificationType.allCases {
            #expect(
                NotificationManager.knownNotificationTypes.contains(caseValue.rawValue),
                "NotificationType.\(caseValue) (rawValue=\(caseValue.rawValue)) is missing from NotificationManager.knownNotificationTypes"
            )
        }
    }

    /// Aliases + server-only types the client routes but that don't have a
    /// one-to-one match in `NotificationType` (kept as string constants). If
    /// the server stops sending one of these, remove it here AND in
    /// `NotificationManager.handleNotificationType`.
    @Test func knownServerAliasesAreAllowed() {
        let aliases: Set<String> = [
            "friend_accepted",               // alias of friend_request_accepted
            "friend_request_accepted",
            "group_challenge_started",
            "challenge_accepted",
            "challenge_completed",
            "private_challenge_member_joined",
            "private_challenge_progress"
        ]
        for alias in aliases {
            #expect(
                NotificationManager.knownNotificationTypes.contains(alias),
                "Server alias \(alias) missing from NotificationManager.knownNotificationTypes"
            )
        }
    }
}
