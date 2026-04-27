//
//  ReadinessDrillDownSheet.swift
//  Fit33
//
//  Phase 5 (2026-04-27 — Daily Mission Unification). The sheet
//  presented when the user taps a Daily Brief whose CTA is
//  `.openReadiness`. Answers the question "why is today red /
//  yellow / green?" by showing:
//
//   1. Big capacity-band pill (color + score + source label)
//   2. Per-signal breakdown from `DailyReadinessSnapshot.signals`
//      (HRV delta, sleep hours, sleep debt, RHR trend, strain prev)
//      each colored by `ReadinessSignal.Severity`
//   3. "Today's Mission steps influenced by this band" — the quests
//      Layer 7 of the v4 RPC pulled in because of the wearable
//      signal (recovery quests on red, PR quests on green)
//   4. Plain-English coaching copy that explains the action the
//      brief recommended ("Skip heavy lifts today — your nervous
//      system needs the recovery").
//
//  Sheet contract:
//    * Presented from `DashboardWelcomeBriefWrapper` via
//      `.sheet(isPresented: $showReadinessSheet)`. The wrapper, not
//      the row, owns the sheet binding so the presentation context
//      is the welcome card itself (avoids the nested-NavigationStack
//      bounce that bit `SimpleMealPlanView` — PE invariant 6).
//    * Pure presentation. Reads from `ReadinessService.shared` and
//      `DailyQuestService.shared` directly (both `@MainActor`); no
//      writes, no side effects.
//

import SwiftUI

struct ReadinessDrillDownSheet: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var readiness = ReadinessService.shared
    @ObservedObject private var quests = DailyQuestService.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    bandHero
                    if !signalRows.isEmpty {
                        signalsSection
                    }
                    if !influencedQuests.isEmpty {
                        missionSteps
                    }
                    coachingCopy
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(
                AnimatedOrbBackground.home(colorScheme: colorScheme)
                    .ignoresSafeArea()
            )
            .navigationTitle("Today's Readiness")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Hero band

    private var bandHero: some View {
        let snapshot = readiness.todayReadiness
        return HStack(alignment: .center, spacing: Spacing.md) {
            ZStack {
                Circle()
                    .fill(snapshot.band.accentColor.opacity(0.18))
                    .frame(width: 76, height: 76)
                Image(systemName: snapshot.band.sfSymbol)
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(snapshot.band.accentColor)
            }
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(snapshot.band.title)
                    .font(.ds_heading2)
                    .foregroundColor(.primary)
                Text(snapshot.hasWearableSignal
                     ? "\(snapshot.score) · from \(snapshot.primarySource.displayName)"
                     : "No wearable connected"
                )
                    .font(.ds_bodySmall)
                    .foregroundColor(.secondary)
                Text(snapshot.band.coachingCopy)
                    .font(.ds_bodySmall)
                    .foregroundColor(.secondary.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Spacing.md)
        .sleekCard(cornerRadius: CornerRadius.xl, accentColor: snapshot.band.accentColor)
    }

    // MARK: - Signals breakdown

    /// Pre-formatted rows. Empty when no signals were captured (e.g.
    /// the placeholder snapshot from a no-wearable user) so the
    /// section can collapse cleanly.
    private var signalRows: [SignalRow] {
        readiness.todayReadiness.signals.map { signal in
            SignalRow(
                kind: signal.kind,
                label: signal.label,
                value: formatValue(signal.value, kind: signal.kind),
                severity: signal.severity
            )
        }
    }

    private var signalsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader(
                title: "Why this band",
                icon: "waveform.path.ecg",
                iconColor: readiness.todayReadiness.band.accentColor
            )
            VStack(spacing: Spacing.xs) {
                ForEach(signalRows) { row in
                    HStack(spacing: Spacing.sm) {
                        Circle()
                            .fill(row.color.opacity(0.85))
                            .frame(width: 8, height: 8)
                        Text(row.label)
                            .font(.ds_bodyMedium)
                            .foregroundColor(.primary)
                        Spacer(minLength: 0)
                        Text(row.value)
                            .font(.ds_labelMedium)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.xs)
                    .background(Color.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous))
                }
            }
        }
    }

    // MARK: - Mission steps influenced by the band

    private var influencedQuests: [DailyQuest] {
        let linked = Set(DailyBriefStore.shared.linkedQuestKeys)
        return quests.quests.filter { q in
            (q.isBriefInfluenced == true) || linked.contains(q.questKey)
        }
    }

    private var missionSteps: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader(
                title: "Mission steps from this band",
                icon: "sparkles",
                iconColor: .blue
            )
            VStack(spacing: Spacing.xs) {
                ForEach(influencedQuests, id: \.id) { quest in
                    HStack(spacing: Spacing.sm) {
                        Text(quest.categoryEmoji)
                            .font(.ds_bodyMedium)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(quest.title)
                                .font(.ds_labelMedium)
                                .foregroundColor(.primary)
                                .lineLimit(1)
                            Text(quest.description)
                                .font(.ds_labelSmall)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        if quest.isCompleted {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        }
                    }
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.sm)
                    .background(Color.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                            .stroke(Color.blue.opacity(0.35), lineWidth: 0.5)
                    )
                }
            }
        }
    }

    // MARK: - Coaching copy

    private var coachingCopy: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            SectionHeader(
                title: "What this means today",
                icon: "info.circle.fill",
                iconColor: .secondary
            )
            Text(coachingText)
                .font(.ds_bodyMedium)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous))
        }
    }

    /// Plain-English advice keyed off the band. Mirrors the brief's
    /// engine-driven framing so the user sees consistent copy on
    /// the welcome card AND in this drill-down.
    private var coachingText: String {
        let snapshot = readiness.todayReadiness
        guard snapshot.hasWearableSignal else {
            return "Connect a WHOOP / Oura / Fitbit / Apple Watch in Settings to unlock readiness-aware Mission steps. Without a wearable, your slate falls back to the standard rotation."
        }
        switch snapshot.band {
        case .red:
            return "Your nervous system needs the day. Today's Mission steps were swapped to mobility / walk / recovery so you can come back fresh tomorrow. Heavy compounds and hard intervals can wait."
        case .yellow:
            return "Steady day — train, but keep one rep in the tank. Mission steps stayed at moderate intensity. If today's headline mentions a debt, closing that one will set you up for a stronger green day."
        case .green:
            return "You're primed. Mission steps may include PR-flag work or higher-volume sets. If you've got a personal record on the line, today's the day to chase it."
        }
    }

    // MARK: - Format helpers

    private struct SignalRow: Identifiable {
        let kind: String
        let label: String
        let value: String
        let severity: ReadinessSignal.Severity
        var id: String { kind }
        var color: Color {
            switch severity {
            case .positive: return .green
            case .neutral:  return .secondary
            case .warning:  return .yellow
            case .negative: return .red
            }
        }
    }

    /// Format the raw `value` based on the signal `kind`. Kept
    /// flexible so the `signals` JSONB schema can grow without
    /// breaking the sheet — unknown kinds render the raw number.
    private func formatValue(_ v: Double, kind: String) -> String {
        switch kind {
        case "hrv_delta", "hrv_delta_pct":
            let sign = v >= 0 ? "+" : ""
            return "\(sign)\(Int(v))%"
        case "sleep_hours":
            return String(format: "%.1fh", v)
        case "sleep_debt", "sleep_debt_min":
            return "\(Int(v))m"
        case "rhr_trend", "rhr_trend_bpm":
            let sign = v >= 0 ? "+" : ""
            return "\(sign)\(Int(v)) bpm"
        case "strain_prev":
            return String(format: "%.1f", v)
        default:
            return String(format: "%.0f", v)
        }
    }
}
