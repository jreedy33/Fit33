//
//  WatchTodayView.swift
//  Fit33Watch
//
//  Watch UI Phase 1 (2026-04-26).
//
//  The glanceable Today screen. Sized for Apple Watch Series SE 44mm
//  (the smallest device we support — see DEVICE_COMPATIBILITY_AGENT.md
//  matrix). Three stacked widgets:
//    1. Activity row — Steps · Active Cal · Exercise Min
//    2. Challenge card — you vs opponent (Digital Crown cycles through
//       active challenges)
//    3. Bottom row — current streak + Start Cardio button
//
//  When a strength workout is live on the iPhone, the Today screen
//  auto-presents `WatchLiveWorkoutView` over itself.
//

import SwiftUI
import WatchKit

struct WatchTodayView: View {
    @EnvironmentObject private var todayStore: WatchTodayStore
    @EnvironmentObject private var liveStore: WatchLiveWorkoutStore

    @State private var showCardioSheet = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                activityRow
                challengeSection
                streakRow
            }
            .padding(.horizontal, 4)
        }
        .focusable()
        .digitalCrownRotation(
            $todayStore.selectedChallengeIndex,
            from: 0,
            through: max(0, Double((todayStore.challenges.count - 1).clampedToZero())),
            by: 1,
            sensitivity: .low,
            isContinuous: false,
            isHapticFeedbackEnabled: true
        )
        .refreshable {
            await todayStore.refresh()
        }
        .task {
            // First-mount refresh. Subsequent updates come from
            // pull-to-refresh + the headless writer keeping server
            // state fresh in the background.
            if todayStore.lastRefreshAt == nil {
                await todayStore.refresh()
            }
        }
        .fullScreenCover(isPresented: Binding(
            get: { liveStore.isLive },
            set: { _ in /* live state is driven by phone push, never user-dismissable */ }
        )) {
            WatchLiveWorkoutView()
                .environmentObject(liveStore)
        }
        .sheet(isPresented: $showCardioSheet) {
            WatchActiveWorkoutView()
        }
    }

    // MARK: - Activity row

    private var activityRow: some View {
        HStack(spacing: 6) {
            metricTile(label: "Steps", value: formattedSteps, accent: .green)
            metricTile(label: "Cal", value: "\(todayStore.activeCaloriesToday)", accent: .red)
            metricTile(label: "Min", value: "\(todayStore.exerciseMinutesToday)", accent: .blue)
        }
    }

    private func metricTile(label: String, value: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .foregroundStyle(accent)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(Color.gray.opacity(0.18), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var formattedSteps: String {
        let s = todayStore.stepsToday
        if s >= 1000 {
            let k = Double(s) / 1000.0
            return String(format: "%.1fK", k)
        }
        return "\(s)"
    }

    // MARK: - Challenge section

    @ViewBuilder
    private var challengeSection: some View {
        if let ch = todayStore.selectedChallenge {
            challengeCard(ch)
        } else if todayStore.lastRefreshAt == nil && todayStore.lastError == nil {
            loadingPlaceholder
        } else if let err = todayStore.lastError {
            errorPlaceholder(message: err)
        } else {
            emptyPlaceholder
        }
    }

    private func challengeCard(_ ch: WatchActiveChallenge) -> some View {
        let oppShowsRaw = ProgressFreshnessKit.shouldShowRawValue(for: ch.opponentLastProgressAt)
        let oppDisplay: String = oppShowsRaw ? "\(ch.opponentTodayProgress)" : "—"
        let unit = ch.targetUnit.lowercased() == "steps" ? "steps" : ch.targetUnit
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text(ch.displayTitle)
                    .font(.system(.headline, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 0)
                if ch.amWinningToday && oppShowsRaw {
                    Image(systemName: "crown.fill")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                }
            }

            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("You")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("\(ch.myTodayProgress)")
                        .font(.system(.title3, design: .rounded).weight(.semibold))
                }
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 0) {
                    Text(ch.opponentName ?? "Opp.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(oppDisplay)
                        .font(.system(.title3, design: .rounded).weight(.semibold))
                        .foregroundStyle(oppShowsRaw ? .primary : .secondary)
                }
            }

            HStack(spacing: 6) {
                if let target = ch.dailyTarget, target > 0 {
                    ProgressView(value: Double(min(ch.myTodayProgress, target)), total: Double(target))
                        .progressViewStyle(.linear)
                        .tint(.green)
                }
                Text("\(ch.daysRemaining)d left · \(unit)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            challengePager
        }
        .padding(10)
        .background(Color.gray.opacity(0.18), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private var challengePager: some View {
        let count = todayStore.challenges.count
        if count > 1 {
            HStack(spacing: 4) {
                let idx = Int(todayStore.selectedChallengeIndex.rounded())
                ForEach(0..<count, id: \.self) { i in
                    Circle()
                        .fill(i == idx ? Color.white : Color.gray.opacity(0.4))
                        .frame(width: 4, height: 4)
                }
                Spacer(minLength: 0)
                Text("Crown")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var loadingPlaceholder: some View {
        HStack {
            ProgressView()
            Text("Loading…")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.gray.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var emptyPlaceholder: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("No active challenges")
                .font(.caption)
            Text("Start one on iPhone")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.gray.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func errorPlaceholder(message: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(message)
                .font(.caption)
            Text("Pull to retry")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.gray.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Streak row

    private var streakRow: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "flame.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
                Text("\(todayStore.streakDays)")
                    .font(.system(.body, design: .rounded).weight(.semibold))
                Text("day streak")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            Spacer(minLength: 6)

            Button {
                showCardioSheet = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "figure.run")
                        .font(.caption)
                    Text("Start")
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.green.opacity(0.85), in: Capsule())
                .foregroundStyle(.black)
            }
            .buttonStyle(.plain)
        }
    }
}

private extension Int {
    func clampedToZero() -> Int { Swift.max(0, self) }
}
