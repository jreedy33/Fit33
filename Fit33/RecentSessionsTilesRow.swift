//
//  RecentSessionsTilesRow.swift
//  Fit33
//
//  Condensed "last N sessions" tile row shown under the exercise title in
//  ExerciseCard. Each tile = one prior workout session: avg weight + short date.
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
                ForEach(sessions.prefix(3)) { session in
                    tile(for: session)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.bottom, Spacing.xs)
        }
    }

    private func tile(for session: ExerciseSessionSummary) -> some View {
        let displayWeight = useKg ? session.avgWeight * 0.453592 : session.avgWeight
        let weightString: String = {
            guard displayWeight > 0 else { return "—" }
            return displayWeight.truncatingRemainder(dividingBy: 1) == 0
                ? "\(Int(displayWeight))"
                : String(format: "%.1f", displayWeight)
        }()
        let unit = useKg ? "kg" : "lb"
        let dateString = Self.dateFormatter.string(from: session.workoutDate)
        let a11y = displayWeight > 0
            ? "Previous session \(dateString): \(weightString) \(unit) average"
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
