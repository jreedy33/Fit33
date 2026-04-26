//
//  Fit33ChallengeRingComplication.swift
//  Fit33WatchComplications
//
//  Watch UI Phase 1 (2026-04-26).
//
//  GraphicCircular watchOS complication. Shows the progress ring
//  for the user's top active 1v1 challenge: filled portion =
//  myTodayProgress / dailyTarget, with the streak count in the
//  center.
//
//  Data source:
//    Reads the App Group snapshot the watch app wrote in
//    `WatchTodayStore.writeSnapshot()`. We deliberately DO NOT
//    pull Supabase from the complication process — complications
//    have an even tighter memory budget than widgets and the
//    timeline runs many times per day. The watch app's foreground
//    + headless writer keep the snapshot fresh.
//
//  Tap behaviour:
//    Tapping the complication launches the watch app to the
//    Today screen. No `AppIntent` for v1 (the snapshot read is
//    cheap enough to be a passive timeline).
//

import SwiftUI
import WidgetKit

// MARK: - Snapshot reader (App Group)

/// Local mirror of the snapshot shape `WatchTodayStore.Snapshot`
/// owned by the watch app. We can't reference the watch app's type
/// directly (different target), but the JSON layout MUST stay in
/// lockstep — if you add a column on one side, add it here too.
private struct Fit33ChallengeSnapshot: Codable {
    let updatedAt: Date
    let topChallengeId: String?
    let topChallengeTitle: String?
    let topChallengeMyProgress: Int
    let topChallengeDailyTarget: Int?
    let topChallengeDaysRemaining: Int
    let myCurrentStreak: Int
    let stepsToday: Int
}

private enum Fit33ComplicationDataSource {
    private static let appGroupID = "group.com.fit33.app"
    private static let snapshotKey = "fit33.watch.today_snapshot.v1"

    static func read() -> Fit33ChallengeSnapshot? {
        guard let defaults = UserDefaults(suiteName: appGroupID),
              let data = defaults.data(forKey: snapshotKey)
        else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Fit33ChallengeSnapshot.self, from: data)
    }
}

// MARK: - TimelineEntry

struct ChallengeRingEntry: TimelineEntry {
    let date: Date
    let title: String
    let progress: Double         // 0.0 – 1.0
    let myProgress: Int
    let dailyTarget: Int?
    let streak: Int
    let isPlaceholder: Bool
}

// MARK: - Provider

struct ChallengeRingProvider: TimelineProvider {
    func placeholder(in context: Context) -> ChallengeRingEntry {
        ChallengeRingEntry(
            date: Date(),
            title: "Steps",
            progress: 0.4,
            myProgress: 4_000,
            dailyTarget: 10_000,
            streak: 3,
            isPlaceholder: true
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (ChallengeRingEntry) -> Void) {
        completion(makeEntry(now: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ChallengeRingEntry>) -> Void) {
        let now = Date()
        let entry = makeEntry(now: now)
        // Refresh every 15 minutes — the watch app's foreground +
        // headless writer keep the snapshot moving, so we don't need
        // sub-minute timeline resolution. WidgetKit will reload us
        // sooner when the snapshot blob changes.
        let nextRefresh = now.addingTimeInterval(15 * 60)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }

    private func makeEntry(now: Date) -> ChallengeRingEntry {
        guard let snapshot = Fit33ComplicationDataSource.read() else {
            return ChallengeRingEntry(
                date: now,
                title: "Fit33",
                progress: 0,
                myProgress: 0,
                dailyTarget: nil,
                streak: 0,
                isPlaceholder: false
            )
        }
        let target = snapshot.topChallengeDailyTarget ?? 0
        let progress: Double = target > 0
            ? min(1.0, Double(snapshot.topChallengeMyProgress) / Double(target))
            : 0
        return ChallengeRingEntry(
            date: now,
            title: snapshot.topChallengeTitle ?? "Fit33",
            progress: progress,
            myProgress: snapshot.topChallengeMyProgress,
            dailyTarget: snapshot.topChallengeDailyTarget,
            streak: snapshot.myCurrentStreak,
            isPlaceholder: false
        )
    }
}

// MARK: - Widget definition

struct Fit33ChallengeRingComplication: Widget {
    let kind: String = "Fit33ChallengeRingComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ChallengeRingProvider()) { entry in
            ChallengeRingView(entry: entry)
        }
        .configurationDisplayName("Top Challenge")
        .description("Progress ring for your most urgent 1v1 challenge.")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryCorner,
            .accessoryInline
        ])
    }
}

// MARK: - View

struct ChallengeRingView: View {
    let entry: ChallengeRingEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            circularBody
        case .accessoryCorner:
            cornerBody
        case .accessoryInline:
            inlineBody
        default:
            circularBody
        }
    }

    private var circularBody: some View {
        Gauge(value: entry.progress) {
            // Center label: streak count if known, else the progress %.
            if entry.streak > 0 {
                Text("\(entry.streak)d")
            } else {
                Text("\(Int(entry.progress * 100))%")
            }
        } currentValueLabel: {
            Text("\(entry.myProgress)")
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .gaugeStyle(.accessoryCircular)
        .tint(entry.progress >= 1.0 ? .green : .orange)
        .widgetAccentable()
    }

    private var cornerBody: some View {
        Text("\(entry.myProgress)")
            .font(.system(.title3, design: .rounded).weight(.semibold))
            .widgetAccentable()
            .widgetLabel(entry.title)
    }

    private var inlineBody: some View {
        if let target = entry.dailyTarget, target > 0 {
            Text("\(entry.myProgress) / \(target)")
        } else {
            Text("\(entry.myProgress)")
        }
    }
}
