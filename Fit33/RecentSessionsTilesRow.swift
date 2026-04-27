//
//  RecentSessionsTilesRow.swift
//  Fit33
//
//  Condensed "Previous Max" tile row shown under the exercise title in
//  ExerciseCard. Each tile = one prior workout session: top-set weight +
//  short date. Capped at 2 tiles so the row stays single-line on narrow
//  devices — adding a 3rd tile wraps "Apr 26" → two lines on iPhone SE / 13 mini.
//
//  Renders the heaviest single set per session (`maxWeight`) prefixed with a
//  "Previous Max:" label so users read it as their PR-trend snapshot, not a
//  session average. Switched 2026-04-27 — historical avg-weight rendering was
//  visually similar but conceptually misleading (a 70 lb top-set workout
//  reported as "67 lb" was confusing alongside the suggested-weight column).
//
//  Owner: Product Engineer (per ENGINEERING_TEAM.md). Data source: invariant
//  driven — `ExerciseHistoryService.shared.fetchRecentSessions(for:limit:)`.
//  See PRODUCT_ENGINEER_AGENT.md for the isolation pattern (no @ObservedObject
//  on the service from inside ExerciseCard — pass-through @State only).
//

import SwiftUI

struct RecentSessionsTilesRow: View {
    let sessions: [ExerciseSessionSummary]
    let useKg: Bool

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("MMM d")
        return f
    }()

    var body: some View {
        if sessions.isEmpty {
            EmptyView()
        } else {
            HStack(spacing: Spacing.xs) {
                Text("Previous Max:")
                    .font(.ds_labelSmall)
                    .foregroundColor(.secondary)
                ForEach(sessions.prefix(2)) { session in
                    tile(for: session)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.bottom, Spacing.xs)
        }
    }

    private func tile(for session: ExerciseSessionSummary) -> some View {
        let rawWeight = session.maxWeight > 0 ? session.maxWeight : session.avgWeight
        let displayWeight = useKg ? rawWeight * 0.453592 : rawWeight
        let weightString: String = {
            guard displayWeight > 0 else { return "—" }
            return displayWeight.truncatingRemainder(dividingBy: 1) == 0
                ? "\(Int(displayWeight))"
                : String(format: "%.1f", displayWeight)
        }()
        let unit = useKg ? "kg" : "lb"
        let dateString = Self.dateFormatter.string(from: session.workoutDate)
        let a11y = displayWeight > 0
            ? "Previous max \(dateString): \(weightString) \(unit)"
            : "Previous session \(dateString)"

        return HStack(spacing: 4) {
            Text(weightString)
                .font(.ds_labelMedium)
                .foregroundColor(.adaptiveText)
            Text(unit)
                .font(.ds_labelSmall)
                .foregroundColor(.secondary)
            Text("·")
                .font(.ds_labelSmall)
                .foregroundColor(.secondary)
            Text(dateString)
                .font(.ds_labelSmall)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, Spacing.xs)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous)
                .fill(Color.cardBackgroundSecondary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous)
                .strokeBorder(Color.adaptiveDivider.opacity(0.6), lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(a11y)
    }
}
