//
//  AdaptiveGoalNudgeCard.swift
//  Fit33
//
//  Wearable Personalization Platform — Phase 3 (Adaptive Goals)
//
//  Dashboard "tune this week's goals?" card. Shows pending proposals
//  from `AdaptiveGoalService` with per-row accept/decline. Nothing
//  auto-applies. Feature-flagged via
//  `AppConfig.FeatureFlags.adaptiveGoals`.
//

import SwiftUI

struct AdaptiveGoalNudgeCard: View {
    @StateObject private var service = AdaptiveGoalService.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if shouldRender {
            VStack(alignment: .leading, spacing: Spacing.md) {
                header

                VStack(spacing: Spacing.sm) {
                    ForEach(service.pendingProposals) { proposal in
                        proposalRow(proposal)
                    }
                }

                footerActions
            }
            .padding(Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
                    .fill(Color.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
                    .stroke(Color.accentColor.opacity(0.4), lineWidth: 1)
            )
            .task {
                await service.refreshPendingProposals()
            }
        }
    }

    // MARK: - Render gate

    private var shouldRender: Bool {
        AppConfig.FeatureFlags.adaptiveGoals && !service.pendingProposals.isEmpty
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "sparkles")
                    .foregroundStyle(Color.accentColor)
                Text("Tune This Week's Goals")
                    .font(.ds_heading3)
                    .foregroundStyle(Color.adaptiveText)
            }
            Text("From your last 28 days of wearable data.")
                .font(.ds_caption)
                .foregroundStyle(Color.adaptiveText.opacity(0.7))
        }
    }

    @ViewBuilder
    private func proposalRow(_ proposal: AdaptiveGoalProposal) -> some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            Image(systemName: proposal.metric.sfSymbol)
                .font(.ds_heading3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(proposal.metric.displayName)
                        .font(.ds_labelLarge)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.adaptiveText)
                    if let pct = proposal.percentChange {
                        Text(pct >= 0 ? String(format: "+%.0f%%", pct) : String(format: "%.0f%%", pct))
                            .font(.ds_caption)
                            .foregroundStyle(pct >= 0 ? Color.green : Color.red)
                    }
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if let current = proposal.currentValue {
                        Text(Self.formatValue(current, metric: proposal.metric))
                            .strikethrough()
                            .foregroundStyle(Color.adaptiveText.opacity(0.55))
                    }
                    Text("→")
                        .foregroundStyle(Color.adaptiveText.opacity(0.55))
                    Text("\(proposal.formattedValue()) \(proposal.metric.unitLabel)")
                        .font(.ds_heading3)
                        .foregroundStyle(Color.adaptiveText)
                }
                Text(proposal.rationale)
                    .font(.ds_caption)
                    .foregroundStyle(Color.adaptiveText.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                Button {
                    Task { await service.resolveProposal(proposal, accepted: false) }
                } label: {
                    Image(systemName: "xmark")
                        .font(.ds_labelLarge)
                        .foregroundStyle(Color.adaptiveText.opacity(0.7))
                        .frame(width: 32, height: 32)
                        .background(
                            Circle().fill(Color.adaptiveText.opacity(0.08))
                        )
                }
                .accessibilityLabel("Decline \(proposal.metric.displayName) change")

                Button {
                    Task { await service.resolveProposal(proposal, accepted: true) }
                } label: {
                    Image(systemName: "checkmark")
                        .font(.ds_labelLarge)
                        .foregroundStyle(Color.white)
                        .frame(width: 32, height: 32)
                        .background(
                            Circle().fill(Color.accentColor)
                        )
                }
                .accessibilityLabel("Accept \(proposal.metric.displayName) change")
            }
            .buttonStyle(.plain)
        }
        .padding(Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                .fill(Color.cardBackground.opacity(0.5))
        )
    }

    private var footerActions: some View {
        HStack {
            Spacer()
            Button {
                Task {
                    for p in service.pendingProposals {
                        await service.resolveProposal(p, accepted: false)
                    }
                }
            } label: {
                Text("Skip this week")
                    .font(.ds_caption)
                    .foregroundStyle(Color.adaptiveText.opacity(0.6))
            }
            .buttonStyle(.plain)
        }
    }

    private static func formatValue(_ v: Double, metric: AdaptiveGoalMetric) -> String {
        switch metric {
        case .calorieGoal, .stepGoal, .proteinGoal:
            return "\(Int(v.rounded()))"
        case .sleepGoal:
            return String(format: "%.1fh", v)
        case .weightPace:
            return String(format: "%.2flb", v)
        }
    }
}
