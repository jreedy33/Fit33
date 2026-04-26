//
//  RunningActivityWidget.swift
//  RunningActivityWidget
//
//  Daily Goals home-screen widget — shows the user's three daily quests
//  pulled from the App Group store written by the main app's
//  `DailyGoalsWidgetBridge` whenever `DailyQuestService` updates.
//

import WidgetKit
import SwiftUI

// MARK: - Timeline Provider

struct DailyGoalsProvider: TimelineProvider {
    func placeholder(in context: Context) -> DailyGoalsEntry {
        DailyGoalsEntry(date: Date(), snapshot: DailyGoalsWidgetSnapshot.Snapshot.placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (DailyGoalsEntry) -> Void) {
        let snapshot = DailyGoalsWidgetSnapshot.read()
        completion(DailyGoalsEntry(date: Date(), snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DailyGoalsEntry>) -> Void) {
        let snapshot = DailyGoalsWidgetSnapshot.read()
        let entry = DailyGoalsEntry(date: Date(), snapshot: snapshot)

        // Refresh every 30 minutes — the main app also pings
        // `WidgetCenter.shared.reloadAllTimelines()` on every quest update,
        // so this is just a safety net for when the app hasn't run.
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date().addingTimeInterval(1800)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }
}

struct DailyGoalsEntry: TimelineEntry {
    let date: Date
    let snapshot: DailyGoalsWidgetSnapshot.Snapshot
}

// MARK: - Entry Views

struct DailyGoalsWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    var entry: DailyGoalsProvider.Entry

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                SmallDailyGoalsView(snapshot: entry.snapshot)
            default:
                MediumDailyGoalsView(snapshot: entry.snapshot)
            }
        }
        .padding(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(for: .widget) {
            LinearGradient(
                colors: [Color(white: 0.13), Color(white: 0.07)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        // Lock the widget to dark mode so it always renders the dark
        // styling regardless of the device's appearance.
        .environment(\.colorScheme, .dark)
    }
}

private struct MediumDailyGoalsView: View {
    let snapshot: DailyGoalsWidgetSnapshot.Snapshot

    private var completedCount: Int {
        snapshot.goals.filter(\.isCompleted).count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "checklist")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                Text("Daily Goals")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(completedCount)/\(snapshot.goals.count)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 6) {
                ForEach(snapshot.goals.prefix(3), id: \.title) { goal in
                    GoalRow(goal: goal)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }
}

private struct SmallDailyGoalsView: View {
    let snapshot: DailyGoalsWidgetSnapshot.Snapshot

    private var completedCount: Int {
        snapshot.goals.filter(\.isCompleted).count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "checklist")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                Text("Daily Goals")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(completedCount)/\(snapshot.goals.count)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 4) {
                ForEach(snapshot.goals.prefix(3), id: \.title) { goal in
                    CompactGoalRow(goal: goal)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Row Components

private struct GoalRow: View {
    let goal: DailyGoalsWidgetSnapshot.WidgetDailyGoal

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(categoryColor.opacity(goal.isCompleted ? 1 : 0.18))
                    .frame(width: 22, height: 22)
                Image(systemName: goal.isCompleted ? "checkmark" : goal.icon)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(goal.isCompleted ? Color.white : categoryColor)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(goal.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .strikethrough(goal.isCompleted, color: .secondary)
                    .opacity(goal.isCompleted ? 0.55 : 1)

                ProgressView(value: goal.progress)
                    .progressViewStyle(.linear)
                    .tint(categoryColor)
                    .frame(height: 3)
            }

            Text(goal.isCompleted ? "✓" : "\(Int(goal.progress * 100))%")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(goal.isCompleted ? categoryColor : .secondary)
                .frame(minWidth: 28, alignment: .trailing)
                .monospacedDigit()
        }
    }

    private var categoryColor: Color {
        DailyGoalCategoryPalette.color(for: goal.category)
    }
}

private struct CompactGoalRow: View {
    let goal: DailyGoalsWidgetSnapshot.WidgetDailyGoal

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: goal.isCompleted ? "checkmark.circle.fill" : goal.icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(goal.isCompleted ? .green : categoryColor)
                .frame(width: 14)

            Text(goal.title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(goal.isCompleted ? .secondary : .primary)
                .lineLimit(1)
                .strikethrough(goal.isCompleted, color: .secondary)

            Spacer(minLength: 0)
        }
    }

    private var categoryColor: Color {
        DailyGoalCategoryPalette.color(for: goal.category)
    }
}

private enum DailyGoalCategoryPalette {
    static func color(for category: String) -> Color {
        switch category {
        case "workout":   return .blue
        case "nutrition": return .green
        case "social":    return .purple
        case "steps":     return .cyan
        case "tracking":  return .indigo
        case "wildcard":  return .orange
        case "reward":    return .yellow
        default:          return .accentColor
        }
    }
}

// MARK: - Widget Configuration

struct RunningActivityWidget: Widget {
    let kind: String = "RunningActivityWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DailyGoalsProvider()) { entry in
            DailyGoalsWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Daily Goals")
        .description("Track your three daily goals at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

// MARK: - Previews

#Preview(as: .systemMedium) {
    RunningActivityWidget()
} timeline: {
    DailyGoalsEntry(date: .now, snapshot: DailyGoalsWidgetSnapshot.Snapshot.placeholder)
}

#Preview(as: .systemSmall) {
    RunningActivityWidget()
} timeline: {
    DailyGoalsEntry(date: .now, snapshot: DailyGoalsWidgetSnapshot.Snapshot.placeholder)
}
