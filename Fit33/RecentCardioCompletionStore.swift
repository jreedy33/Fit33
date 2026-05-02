//
//  RecentCardioCompletionStore.swift
//  Fit33
//
//  Tracks the most-recent cardio (run / walk / cycle / hike) the user
//  finished TODAY, regardless of source (in-app cardio, Strava import,
//  HealthKit observer). Drives the `complete_workout` daily-goal card's
//  completion sub-text so the card reads naturally:
//
//    • Native run    → "Evening 5K Run ✓"
//    • Strava run    → "Evening 5K with Strava ✓"
//    • Walk → "Afternoon 1.2 mi Walk ✓"
//
//  Architecture notes (PE invariant 9 — widget isolation):
//    • `@MainActor`, single-source-of-truth singleton. Any path that
//      finishes a cardio (CardioRecapView fanout, RunningWorkoutView
//      legacy fanout, Strava `saveActivitiesToCloud`) calls
//      `record(...)` AFTER its own quest fanout. Read by
//      `DailyQuestsWidget.workoutCompletionSummary()` and the daily
//      brief refreshes via the existing `DailyQuestService` quest
//      change subscription.
//    • Persisted in `UserDefaults` (calendar-day-scoped) so the dashboard
//      paints the right copy on cold launch BEFORE the next sync runs.
//    • Stale entries (different calendar day) are ignored at read
//      time — we never bleed yesterday's "Evening 5K Run" into today.
//

import Foundation
import SwiftUI

/// Origin of the cardio session — mirrors the `cardio_workouts.origin_app`
/// vocabulary but kept narrow on purpose. The store only cares enough
/// to render the right "with Strava" / "in-app" suffix on the daily
/// goal completion summary.
enum RecentCardioCompletionOrigin: String, Codable {
    case fit33      // native CardioRecapView / legacy RunCompletionView
    case strava
    case healthkit
    case other
}

struct RecentCardioCompletionRecord: Codable, Equatable {
    let activityType: String          // "run" | "walk" | "outdoor_cycle" | "hike" | …
    let workoutName: String?          // Strava activity name, if any
    let distanceMeters: Double
    let durationSeconds: Int
    let completedAt: Date
    let origin: RecentCardioCompletionOrigin

    /// "Run" / "Walk" / "Cycle" / "Hike" — short label that reads well
    /// inside a sentence. Falls back to the raw activity type capitalized
    /// when we can't pattern-match.
    var displayActivityWord: String {
        switch activityType.lowercased().replacingOccurrences(of: "_", with: " ") {
        case "outdoor run", "run", "virtualrun", "treadmill":
            return "Run"
        case "walk":
            return "Walk"
        case "hike":
            return "Hike"
        case "outdoor cycle", "outdoor_cycle", "indoor cycle", "indoor_cycle",
             "ride", "virtualride":
            return "Ride"
        case "swim", "swimming":
            return "Swim"
        case "row", "rowing":
            return "Row"
        case "elliptical":
            return "Elliptical"
        case "stair climber", "stair_climber":
            return "Stair Climber"
        case "hiit":
            return "HIIT"
        default:
            return activityType.capitalized
        }
    }
}

@MainActor
final class RecentCardioCompletionStore: ObservableObject {
    static let shared = RecentCardioCompletionStore()

    @Published private(set) var latest: RecentCardioCompletionRecord?

    private let userDefaults = UserDefaults.standard
    private let storageKey = "fit33.recentCardioCompletion.v1"

    private init() {
        loadFromDisk()
    }

    /// Record a freshly-completed cardio session. The store keeps only
    /// the latest one for the current calendar day — the "most-recent
    /// today" wins because that's what the daily goal completion sub-text
    /// describes.
    ///
    /// Idempotent on equal payloads — calling twice with the same record
    /// is a no-op so dashboard refresh races don't churn the publisher.
    func record(
        activityType: String,
        workoutName: String? = nil,
        distanceMeters: Double,
        durationSeconds: Int,
        completedAt: Date = Date(),
        origin: RecentCardioCompletionOrigin
    ) {
        let candidate = RecentCardioCompletionRecord(
            activityType: activityType,
            workoutName: workoutName,
            distanceMeters: max(0, distanceMeters),
            durationSeconds: max(0, durationSeconds),
            completedAt: completedAt,
            origin: origin
        )

        // Only persist if it's strictly newer than what we already hold
        // for today. Same-second writes (Strava webhook sync racing the
        // recap fanout) keep the existing record.
        if let existing = currentRecordForToday(), existing.completedAt >= candidate.completedAt {
            return
        }

        latest = candidate
        persistToDisk(candidate)
    }

    /// Read the current record IF it belongs to today's calendar day.
    /// Returns `nil` for stale (yesterday-or-older) records so the UI
    /// never paints "Evening 5K with Strava" on a fresh morning.
    func currentRecordForToday() -> RecentCardioCompletionRecord? {
        guard let record = latest else { return nil }
        return Calendar.current.isDateInToday(record.completedAt) ? record : nil
    }

    /// Renders the daily-goal completion sub-text for the most-recent
    /// today's cardio. Returns `nil` when no record exists for today —
    /// the caller should fall back to the strength-workout copy or
    /// the generic "Workout completed ✓" string.
    func completionSummaryText() -> String? {
        guard let record = currentRecordForToday() else { return nil }

        let timeOfDay = timeOfDayLabel(for: record.completedAt)
        let distance = formatDistance(meters: record.distanceMeters)

        switch record.origin {
        case .strava:
            // "Evening 5K with Strava ✓" — per dashboard tweak (2026-05-02
            // user request). Distance leads, brand follows.
            if !distance.isEmpty {
                return "\(timeOfDay) \(distance) with Strava ✓"
            }
            return "\(timeOfDay) \(record.displayActivityWord) with Strava ✓"
        case .fit33:
            // "Evening 5K Run ✓" — native runs lead with distance + verb.
            if !distance.isEmpty {
                return "\(timeOfDay) \(distance) \(record.displayActivityWord) ✓"
            }
            return "\(timeOfDay) \(record.displayActivityWord) ✓"
        case .healthkit:
            if !distance.isEmpty {
                return "\(timeOfDay) \(distance) \(record.displayActivityWord) ✓"
            }
            return "\(timeOfDay) \(record.displayActivityWord) ✓"
        case .other:
            if !distance.isEmpty {
                return "\(timeOfDay) \(distance) \(record.displayActivityWord) ✓"
            }
            return "\(timeOfDay) \(record.displayActivityWord) ✓"
        }
    }

    // MARK: - Private helpers

    private func timeOfDayLabel(for date: Date) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        switch hour {
        case 5..<12:  return "Morning"
        case 12..<17: return "Afternoon"
        case 17..<21: return "Evening"
        default:      return "Late night"
        }
    }

    /// Locale-aware distance string, matching the rest of the app's
    /// dashboard cardio cards (`RecentCardioWorkoutCard.formatDistance`).
    /// Returns the empty string for sub-meaningful distances so the
    /// caller can omit the distance fragment entirely.
    private func formatDistance(meters: Double) -> String {
        guard meters >= 50 else { return "" }
        let usesMetric = Locale.current.measurementSystem == .metric
        if usesMetric {
            let km = meters / 1000.0
            if km < 1 {
                return String(format: "%.0f m", meters)
            }
            // "5.0 km" reads slightly better than "5 km" once you cross
            // a threshold; the Strava-style ask is "Evening 5k" so use
            // a 1-decimal print and trim trailing ".0" for nice copy.
            let formatted = String(format: "%.1f", km)
            let trimmed = formatted.hasSuffix(".0")
                ? String(formatted.dropLast(2))
                : formatted
            return "\(trimmed)K"
        } else {
            let miles = meters / 1609.344
            if miles < 0.1 {
                let feet = meters * 3.28084
                return String(format: "%.0f ft", feet)
            }
            // Mile distances render to one decimal; "5.2 mi" / "1 mi".
            let formatted = String(format: "%.1f", miles)
            let trimmed = formatted.hasSuffix(".0")
                ? String(formatted.dropLast(2))
                : formatted
            return "\(trimmed) mi"
        }
    }

    // MARK: - Persistence

    private func persistToDisk(_ record: RecentCardioCompletionRecord) {
        guard let data = try? JSONEncoder().encode(record) else { return }
        userDefaults.set(data, forKey: storageKey)
    }

    private func loadFromDisk() {
        guard let data = userDefaults.data(forKey: storageKey),
              let record = try? JSONDecoder().decode(RecentCardioCompletionRecord.self, from: data)
        else { return }
        // Drop stale records on launch so a yesterday entry doesn't
        // briefly paint a stale completion sub-text.
        if Calendar.current.isDateInToday(record.completedAt) {
            latest = record
        } else {
            userDefaults.removeObject(forKey: storageKey)
        }
    }
}
