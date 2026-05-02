//
//  StravaActivityRecapSheet.swift
//  Fit33
//
//  Detail sheet shown when a user taps the Dashboard Strava widget or the
//  Strava recap notification card. Phase 1 surfaces the metrics already
//  available in the list response (distance, time, pace, HR, elevation,
//  effort, calories). Phase 2 will plug in splits, segments, and HR/pace
//  streams via `StravaActivityEnricher` once the corresponding columns
//  land on `cardio_workouts`.
//

import SwiftUI

struct StravaActivityRecapSheet: View {
    let activity: StravaActivity

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var unitSettings = UnitSettingsManager.shared

    var body: some View {
        NavigationStack {
            ZStack {
                AnimatedOrbBackground.home(colorScheme: colorScheme)
                    .ignoresSafeArea()
                    .accessibilityHidden(true)

                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        header

                        primaryStatsGrid

                        secondaryStatsGrid

                        if let url = stravaActivityURL {
                            openInStravaButton(url: url)
                        }

                        Text("Splits, segments, and HR / pace streams unlock once Strava sync enriches this activity (usually within a minute).")
                            .font(.ds_bodySmall)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, Spacing.xs)
                    }
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.md)
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Strava Recap")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: activity.activityIcon)
                    .font(.title2)
                    .foregroundColor(Color.stravaOrange)
                    .frame(width: 40, height: 40)
                    .background(Color.stravaOrange.opacity(colorScheme == .dark ? 0.18 : 0.12))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(activity.name)
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                        .lineLimit(2)
                    Text("\(activity.type) • \(formattedStartDate)")
                        .font(.ds_bodySmall)
                        .foregroundColor(.secondary)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var formattedStartDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: activity.startDate)
    }

    // MARK: - Grids

    private var primaryStatsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            recapStatCard(
                title: "Distance",
                value: activity.distanceFormatted,
                icon: "ruler",
                color: Color.stravaOrange
            )
            recapStatCard(
                title: "Moving Time",
                value: activity.durationFormatted,
                icon: "clock.fill",
                color: .blue
            )
            recapStatCard(
                title: "Pace",
                value: activity.paceFormatted ?? "--",
                icon: "speedometer",
                color: .green
            )
            recapStatCard(
                title: "Calories",
                value: activity.calories.map { "\($0)" } ?? "--",
                icon: "flame.fill",
                color: .orange
            )
        }
    }

    private var secondaryStatsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            recapStatCard(
                title: "Avg Heart Rate",
                value: activity.averageHeartrate.map { "\(Int($0)) bpm" } ?? "--",
                icon: "heart.fill",
                color: .red
            )
            recapStatCard(
                title: "Max Heart Rate",
                value: activity.maxHeartrate.map { "\(Int($0)) bpm" } ?? "--",
                icon: "heart.text.square.fill",
                color: .pink
            )
            recapStatCard(
                title: "Elevation Gain",
                value: activity.totalElevationGain.map { unitSettings.formatStravaElevation(meters: $0) } ?? "--",
                icon: "mountain.2.fill",
                color: .brown
            )
            recapStatCard(
                title: "Effort",
                value: activity.sufferScore.map { "\($0)" } ?? "--",
                icon: "bolt.heart.fill",
                color: .purple
            )
        }
    }

    private func recapStatCard(title: String, value: String, icon: String, color: Color) -> some View {
        let hasValue = value != "--"
        return VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundColor(color)
                Text(title)
                    .font(.ds_labelSmall)
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
            }
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(hasValue ? .primary : .primary.opacity(0.4))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(color.opacity(colorScheme == .dark ? 0.18 : 0.12), lineWidth: 1)
        )
    }

    // MARK: - Strava deep-link

    private var stravaActivityURL: URL? {
        URL(string: "https://www.strava.com/activities/\(activity.id)")
    }

    private func openInStravaButton(url: URL) -> some View {
        // Strava Brand Guidelines §3 (Linking to Strava Data): the
        // canonical text MUST be "View on Strava" (any other label is
        // a brand-guideline violation). Bold weight + Strava brand
        // orange (#FC5200) satisfy the link-affordance rule.
        Link(destination: url) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "arrow.up.right.square.fill")
                Text("View on Strava")
                    .fontWeight(.semibold)
            }
            .font(.subheadline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.md)
            .background(
                LinearGradient(
                    colors: [Color.stravaOrange, Color.stravaOrange.opacity(0.85)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }
}
