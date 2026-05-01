//
//  ActiveChallengeWidgetSnapshot.swift
//  RunningActivityWidget
//
//  Widget-side mirror of `Fit33/ActiveChallengeWidgetBridge.swift`.
//  Reads the slim payload the main app publishes whenever active
//  challenges change so the widget can render the in-app challenge
//  card without round-tripping through Supabase.
//

import Foundation
import SwiftUI
import UIKit

enum ActiveChallengeWidgetSnapshot {
    static let appGroupID = "group.com.fit33.app"
    static let challengeKey = "fit33.widget.activeChallenge.v1"
    static let challengesListKey = "fit33.widget.activeChallenges.list.v1"
    static let updatedAtKey = "fit33.widget.activeChallenge.updatedAt"
    static let userPhotoFilename = "widget_user_photo.jpg"
    static let opponentPhotoPrefix = "widget_opponent_"
    /// Smack-talk shout-bubble payload. Written by the main app's
    /// `SmackTalkWidgetBridge.publish` whenever an opponent fires off
    /// a trash-talk reaction while the app is closed; cleared on
    /// next foreground (`Fit33App` scenePhase `.active`).
    static let smackTalkKey = "fit33.widget.smackTalk.v1"
    /// Sidecar filename under the App Group container for smack
    /// payloads. Mirrored byte-for-byte by
    /// `Fit33/SmackTalkWidgetBridge.smackFileName` — the file is the
    /// canonical wire (we abandoned `UserDefaults` for smack on
    /// 2026-04-29 because cfprefsd's per-process cache served stale
    /// reads to the widget extension despite `synchronize()` on both
    /// sides). When this filename changes, mirror the iOS side in the
    /// SAME edit pass.
    static let smackFileName = "smackTalk.v1.json"

    static func opponentPhotoFilename(opponentId: String) -> String {
        "\(opponentPhotoPrefix)\(opponentId).jpg"
    }

    struct WidgetActiveChallenge: Codable, Hashable {
        let challengeId: String
        let challengeType: String
        let displayTitle: String
        let mode: String
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
        // New fields (added 2026-04-25). Decoded with defaults so older
        // payloads written before the upgrade still parse cleanly.
        let myDisplayName: String?
        let hasUserPhoto: Bool
        let hasOpponentPhoto: Bool
        // New fields (added 2026-04-26, Realtime Widget Server Pull
        // Phase 2b). NULL when (a) the payload was written by an older
        // build OR (b) the participant has no `challenge_daily_progress`
        // rows yet — both signals are "we don't know how stale this is",
        // which `Shared/ProgressFreshness.swift` (Phase 6) will surface
        // as `— · just now` (treat unknown == fresh, not stale).
        let myLastProgressAt: Date?
        let opponentLastProgressAt: Date?

        enum CodingKeys: String, CodingKey {
            case challengeId, challengeType, displayTitle, mode, targetUnit
            case dailyTarget, daysRemaining, durationDays
            case myTodayProgress, opponentTodayProgress
            case opponentId, opponentName, opponentPhotoUrl
            case opponentIsVerified, opponentIsGoldVerified
            case myCurrentStreak, amWinningToday
            case myDisplayName, hasUserPhoto, hasOpponentPhoto
            case myLastProgressAt, opponentLastProgressAt
        }

        init(challengeId: String, challengeType: String, displayTitle: String, mode: String,
             targetUnit: String, dailyTarget: Int?, daysRemaining: Int, durationDays: Int,
             myTodayProgress: Int, opponentTodayProgress: Int, opponentId: String,
             opponentName: String?, opponentPhotoUrl: String?, opponentIsVerified: Bool,
             opponentIsGoldVerified: Bool, myCurrentStreak: Int, amWinningToday: Bool,
             myDisplayName: String? = nil, hasUserPhoto: Bool = false, hasOpponentPhoto: Bool = false,
             myLastProgressAt: Date? = nil, opponentLastProgressAt: Date? = nil) {
            self.challengeId = challengeId
            self.challengeType = challengeType
            self.displayTitle = displayTitle
            self.mode = mode
            self.targetUnit = targetUnit
            self.dailyTarget = dailyTarget
            self.daysRemaining = daysRemaining
            self.durationDays = durationDays
            self.myTodayProgress = myTodayProgress
            self.opponentTodayProgress = opponentTodayProgress
            self.opponentId = opponentId
            self.opponentName = opponentName
            self.opponentPhotoUrl = opponentPhotoUrl
            self.opponentIsVerified = opponentIsVerified
            self.opponentIsGoldVerified = opponentIsGoldVerified
            self.myCurrentStreak = myCurrentStreak
            self.amWinningToday = amWinningToday
            self.myDisplayName = myDisplayName
            self.hasUserPhoto = hasUserPhoto
            self.hasOpponentPhoto = hasOpponentPhoto
            self.myLastProgressAt = myLastProgressAt
            self.opponentLastProgressAt = opponentLastProgressAt
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            challengeId = try c.decode(String.self, forKey: .challengeId)
            challengeType = try c.decode(String.self, forKey: .challengeType)
            displayTitle = try c.decode(String.self, forKey: .displayTitle)
            mode = try c.decode(String.self, forKey: .mode)
            targetUnit = try c.decode(String.self, forKey: .targetUnit)
            dailyTarget = try c.decodeIfPresent(Int.self, forKey: .dailyTarget)
            daysRemaining = try c.decode(Int.self, forKey: .daysRemaining)
            durationDays = try c.decode(Int.self, forKey: .durationDays)
            myTodayProgress = try c.decode(Int.self, forKey: .myTodayProgress)
            opponentTodayProgress = try c.decode(Int.self, forKey: .opponentTodayProgress)
            opponentId = try c.decode(String.self, forKey: .opponentId)
            opponentName = try c.decodeIfPresent(String.self, forKey: .opponentName)
            opponentPhotoUrl = try c.decodeIfPresent(String.self, forKey: .opponentPhotoUrl)
            opponentIsVerified = try c.decode(Bool.self, forKey: .opponentIsVerified)
            opponentIsGoldVerified = try c.decode(Bool.self, forKey: .opponentIsGoldVerified)
            myCurrentStreak = try c.decode(Int.self, forKey: .myCurrentStreak)
            amWinningToday = try c.decode(Bool.self, forKey: .amWinningToday)
            myDisplayName = try c.decodeIfPresent(String.self, forKey: .myDisplayName)
            hasUserPhoto = try c.decodeIfPresent(Bool.self, forKey: .hasUserPhoto) ?? false
            hasOpponentPhoto = try c.decodeIfPresent(Bool.self, forKey: .hasOpponentPhoto) ?? false
            myLastProgressAt = try c.decodeIfPresent(Date.self, forKey: .myLastProgressAt)
            opponentLastProgressAt = try c.decodeIfPresent(Date.self, forKey: .opponentLastProgressAt)
        }

        var isAccountability: Bool { mode == "accountability" }
        var opponentFirstName: String {
            (opponentName?.components(separatedBy: " ").first).flatMap { $0.isEmpty ? nil : $0 } ?? "Friend"
        }
        var myFirstName: String {
            (myDisplayName?.components(separatedBy: " ").first).flatMap { $0.isEmpty ? nil : $0 } ?? "You"
        }
        var myDailyProgress: Double {
            guard let target = dailyTarget, target > 0 else { return 0 }
            return min(1, Double(myTodayProgress) / Double(target))
        }
        var opponentDailyProgress: Double {
            guard let target = dailyTarget, target > 0 else { return 0 }
            return min(1, Double(opponentTodayProgress) / Double(target))
        }
        var bothDoneToday: Bool {
            guard let target = dailyTarget, target > 0 else { return false }
            return myTodayProgress >= target && opponentTodayProgress >= target
        }
    }

    // MARK: - Smack Talk (shout bubble)
    //
    // Mirrors `Fit33/SmackTalkWidgetBridge.WidgetSmackTalk` byte-for-byte
    // (same JSON CodingKeys + same `iso8601` date strategy). When the
    // main-app struct changes, mirror it here in the SAME edit pass.
    struct WidgetSmackTalk: Codable, Hashable {
        let challengeId: String
        let senderFirstName: String
        let reactionEmoji: String
        let reactionText: String
        let reactionCategory: String
        let receivedAt: Date

        var isCompetition: Bool { reactionCategory == "trash_talk" }
    }

    /// Reads the most recent unread smack-talk payload, or `nil` when
    /// none is pending. Filtered to the resolved challenge by the
    /// caller — `entry(for:)` only paints the shout bubble when the
    /// payload's `challengeId` matches the challenge currently being
    /// rendered, so a smack on challenge B doesn't yell out of a
    /// widget pinned to challenge A.
    ///
    /// Bug-intel 2026-04-29: originally read via `UserDefaults` but the
    /// widget extension's cached `UserDefaults(suiteName:)` instance
    /// served STALE data to the widget process even after the iOS app
    /// successfully wrote + synchronized the new value. Symptom: silent
    /// push received → bridge logged "smack published" → widget
    /// reload requested → widget read NIL → no bubble. Switched to a
    /// sidecar JSON file under the App Group container; file reads go
    /// through the sandbox-extension'd container path which is
    /// fully-consistent across processes (no cfprefsd cache).
    static func readSmackTalk() -> WidgetSmackTalk? {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupID
        ) else {
            return nil
        }
        let url = container.appendingPathComponent(smackFileName)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        do {
            let data = try Data(contentsOf: url, options: [.uncached])
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(WidgetSmackTalk.self, from: data)
        } catch {
            return nil
        }
    }

    /// Reads the auto-pick / fallback challenge from the App Group.
    /// Returns nil when the user has no active challenges OR the App
    /// Group isn't configured yet.
    static func read() -> WidgetActiveChallenge? {
        guard let defaults = UserDefaults(suiteName: appGroupID),
              let data = defaults.data(forKey: challengeKey) else {
            return nil
        }
        return try? JSONDecoder().decode(WidgetActiveChallenge.self, from: data)
    }

    /// Reads the full list of active 1v1 challenges. Powers the widget
    /// configuration picker (so the user can choose Abbie over Paul).
    static func readAll() -> [WidgetActiveChallenge] {
        guard let defaults = UserDefaults(suiteName: appGroupID),
              let data = defaults.data(forKey: challengesListKey),
              let list = try? JSONDecoder().decode([WidgetActiveChallenge].self, from: data) else {
            return []
        }
        return list
    }

    /// Resolves the challenge the widget should render given the user's
    /// configuration choice. Falls back to the auto-pick when no id is
    /// provided OR when the chosen one no longer exists (e.g. challenge
    /// just ended).
    ///
    /// Lookup is case-insensitive (2026-04-28 picker-flip fix): Apple's
    /// `Foundation.UUID.uuidString` returns UPPERCASE while the widget
    /// extension's direct Postgres pull writes lowercase. When the two
    /// writers (bridge ↔ widget pull) raced, the cache flipped case
    /// between ticks, the picker's stored `configuration.challenge.id`
    /// stopped matching, and the widget snapped to the bridge's
    /// best-pick fallback — visibly resetting the user's selection
    /// every cache rotation. Bridge writes are now lowercase
    /// (`ActiveChallengeWidgetBridge.publish`), but already-persisted
    /// `configuration.challenge.id` values from before the fix may
    /// still be uppercase, so we normalize at the lookup edge to make
    /// the migration invisible. Once the user re-saves the widget
    /// configuration after this ships, the stored ID will be lowercase
    /// and the case-fold here is a no-op.
    static func resolve(challengeId: String?) -> WidgetActiveChallenge? {
        if let id = challengeId?.lowercased(),
           let match = readAll().first(where: { $0.challengeId.lowercased() == id }) {
            return match
        }
        return read()
    }

    // MARK: - Shared photos
    //
    // The main app's `ActiveChallengeWidgetBridge` mirrors the user's and
    // opponent's avatars into the App Group container at publish time so
    // the widget process can render real photos without any networking.

    static func userPhoto() -> UIImage? {
        loadSharedPhoto(named: userPhotoFilename)
    }

    static func opponentPhoto(opponentId: String) -> UIImage? {
        loadSharedPhoto(named: opponentPhotoFilename(opponentId: opponentId))
    }

    private static func loadSharedPhoto(named filename: String) -> UIImage? {
        guard let url = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent(filename),
              FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return UIImage(data: data)
    }

    /// Sample placeholder used by the timeline `placeholder(in:)` callback
    /// and SwiftUI previews so the widget gallery shows real-looking
    /// content before the user installs.
    static let placeholder = WidgetActiveChallenge(
        challengeId: UUID().uuidString,
        challengeType: "steps",
        displayTitle: "10K Step Showdown",
        mode: "competition",
        targetUnit: "steps",
        dailyTarget: 10_000,
        daysRemaining: 5,
        durationDays: 7,
        myTodayProgress: 7_842,
        opponentTodayProgress: 6_510,
        opponentId: UUID().uuidString,
        opponentName: "Alex Park",
        opponentPhotoUrl: nil,
        opponentIsVerified: false,
        opponentIsGoldVerified: false,
        myCurrentStreak: 3,
        amWinningToday: true,
        myDisplayName: "You",
        hasUserPhoto: false,
        hasOpponentPhoto: false,
        myLastProgressAt: Date(),
        opponentLastProgressAt: Date().addingTimeInterval(-15 * 60)
    )
}

// MARK: - Type Palette (mirrors `ChallengeType` in the main app)

enum ChallengeWidgetPalette {
    static func emoji(for type: String) -> String {
        switch type {
        case "steps":             return "👟"
        case "walk":              return "🚶"
        case "run":               return "🏃"
        case "lift":              return "🏋️"
        case "workout_streak":    return "🔥"
        case "active_minutes":    return "⏱️"
        case "hydrate":           return "💧"
        case "calories":          return "🔥"
        case "protein":           return "🥩"
        case "sleep_hours":       return "😴"
        case "readiness_average": return "💚"
        case "strain_budget":     return "⚡"
        default:                  return "🏆"
        }
    }

    static func color(for type: String) -> Color {
        switch type {
        case "steps":             return .green
        case "walk":              return .blue
        case "run":               return .orange
        case "lift":              return .purple
        case "workout_streak":    return .red
        case "active_minutes":    return .cyan
        case "hydrate":           return .cyan
        case "calories":          return .orange
        case "protein":           return .pink
        case "sleep_hours":       return .indigo
        case "readiness_average": return .green
        case "strain_budget":     return .yellow
        default:                  return .accentColor
        }
    }

    static func gradient(for type: String) -> [Color] {
        switch type {
        case "steps":             return [.green, .mint]
        case "walk":              return [.blue, .cyan]
        case "run":               return [.orange, .yellow]
        case "lift":              return [.purple, .pink]
        case "workout_streak":    return [.red, .orange]
        case "active_minutes":    return [.cyan, .blue]
        case "hydrate":           return [.cyan, .blue]
        case "calories":          return [.orange, .red]
        case "protein":           return [.pink, .purple]
        case "sleep_hours":       return [.indigo, .purple]
        case "readiness_average": return [.green, .teal]
        case "strain_budget":     return [.yellow, .orange]
        default:                  return [.accentColor, .accentColor]
        }
    }

    /// Compact, locale-aware value formatter. Mirrors what
    /// `ChallengeProgressResolver.formatValue` does for steps / minutes.
    static func formattedProgress(_ value: Int, unit: String) -> String {
        "\(formattedValue(value)) \(formattedUnit(unit))"
    }

    /// Just the numeric portion ("4,496" or "12.3K") so the widget can
    /// stack the value and unit on separate lines when horizontal space
    /// is tight (e.g. medium widget competition row).
    static func formattedValue(_ value: Int) -> String {
        if value >= 10_000 {
            let k = Double(value) / 1_000.0
            return String(format: k.truncatingRemainder(dividingBy: 1) == 0 ? "%.0fK" : "%.1fK", k)
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    /// Just the abbreviated unit string ("steps", "min", "cal", …).
    static func formattedUnit(_ unit: String) -> String {
        switch unit.lowercased() {
        case "steps":   return "steps"
        case "min":     return "min"
        case "minutes": return "min"
        case "reps":    return "reps"
        case "ml":      return "ml"
        case "cal", "calories", "kcal": return "cal"
        case "g", "grams": return "g"
        case "days":    return "d"
        default:        return unit.lowercased()
        }
    }

}
