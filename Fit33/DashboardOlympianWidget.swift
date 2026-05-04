//
//  DashboardOlympianWidget.swift
//  Fit33
//
//  "Path to 33" — annual Olympian track widget.
//
//  Compact dashboard tile showing:
//   - Circular progress ring (X / 33 unlocked goals)
//   - Tier accent color (Foundation → Olympian)
//   - Next-goal preview row ("Next up: 14-day streak — 9/14")
//   - Tap → push DashboardRoute.olympianPath
//
//  Hosted via `DashboardOlympianWrapper` so the widget owns its own
//  `@StateObject OlympianPathService` (PE invariant 9: widget isolation —
//  the dashboard's parent state stays untouched, the widget's progress
//  ring re-renders independently of the rest of the dashboard).
//

import SwiftUI

// MARK: - Wrapper (always visible when widget enabled)

struct DashboardOlympianWrapper: View {
    @Binding var navigationPath: NavigationPath

    @StateObject private var service = OlympianPathService.shared
    @Environment(\.colorScheme) private var colorScheme

    @AppStorage("showOlympianWidget") private var showOlympianWidget = true

    var body: some View {
        Group {
            if showOlympianWidget {
                DashboardOlympianWidget(service: service)
                    .onTapGesture {
                        HapticManager.tap()
                        navigationPath.append(DashboardRoute.olympianPath)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(accessibilityLabel)
                    .accessibilityHint("Opens the Olympian Path detail screen with your 33 personalized goals.")
                    .task {
                        await service.loadCurrentSeason()
                    }
            }
        }
    }

    private var accessibilityLabel: String {
        let p = service.progress
        return "Path to Olympian — \(p.completed) of \(p.total) goals unlocked. \(service.archetype.displayName)."
    }
}

// MARK: - Widget body

struct DashboardOlympianWidget: View {
    @ObservedObject var service: OlympianPathService

    @Environment(\.colorScheme) private var colorScheme

    private var year: Int { OlympianPathService.currentSeasonYear }

    /// Year as plain digits — `Text("\(intYear)")` adds a thousands
    /// separator (renders `2,026`) because SwiftUI runs Int interpolation
    /// through the Locale number formatter. Years are identifiers, not
    /// quantities; always render via this stringified value.
    private var yearText: String { String(year) }

    private var ringProgress: Double {
        let p = service.progress
        guard p.total > 0 else { return 0 }
        return min(1.0, Double(p.completed) / Double(p.total))
    }

    /// Highest tier displayed in the accent. Once a tier is fully cleared we
    /// "lock in" its color; before then we show the tier color of the next
    /// goal so the widget previews where the user is heading.
    private var currentTier: Int {
        if service.highestClearedTier >= 5 { return 5 }
        return service.nextGoal?.tier ?? max(service.highestClearedTier, 1)
    }

    private var tierAccent: Color {
        OlympianPathBluePalette.color(for: currentTier)
    }

    private var tierName: String {
        switch currentTier {
        case 1: return "Foundation"
        case 2: return "Habits"
        case 3: return "Strength"
        case 4: return "Mastery"
        case 5: return "Olympian"
        default: return "Foundation"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            header
            ring
            nextGoalRow
        }
        .padding(.vertical, Spacing.md)
        .padding(.horizontal, Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .adaptiveSleekCard(cornerRadius: 24, accentColor: tierAccent)
        .contentShape(Rectangle())
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                tierAccent.opacity(colorScheme == .dark ? 0.30 : 0.20),
                                tierAccent.opacity(colorScheme == .dark ? 0.12 : 0.08)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 36, height: 36)

                Image(systemName: "crown.fill")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [tierAccent, tierAccent.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .shadow(color: tierAccent.opacity(colorScheme == .dark ? 0.4 : 0.3), radius: 8, x: 0, y: 4)

            VStack(alignment: .leading, spacing: 2) {
                Text("Path to Olympian")
                    .font(.ds_labelLarge)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)

                Text(service.path365Subtitle)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 6) {
                    Image(systemName: service.archetype.icon)
                        .font(.caption2)
                        .foregroundColor(service.archetype.accent)
                    Text(service.archetype.displayName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Text(tierName.uppercased())
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(tierAccent)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(tierAccent.opacity(0.15))
                .clipShape(Capsule())
        }
    }

    // MARK: - Ring

    private var ring: some View {
        HStack(spacing: Spacing.lg) {
            ZStack {
                Circle()
                    .stroke(tierAccent.opacity(0.18), lineWidth: 8)
                    .frame(width: 84, height: 84)

                Circle()
                    .trim(from: 0, to: ringProgress)
                    .stroke(
                        AngularGradient(
                            colors: OlympianPathBluePalette.ringAngularColors,
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: 84, height: 84)
                    .animation(.easeInOut(duration: 0.6), value: ringProgress)

                            VStack(spacing: 0) {
                                Text("\(service.progress.completed)")
                                    .font(.ds_stat)
                                    .fontWeight(.bold)
                                    .foregroundColor(.primary)
                                Text("/ 33")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                tierDots
                Text(service.seasonComplete
                     ? "Olympian \(yearText) — Complete"
                     : "\(33 - service.progress.completed) goals to Olympian")
                    .font(.ds_labelMedium)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }

            Spacer()
        }
    }

    /// Five small tier-cleared dots (one per tier 1..5). Lit when that tier
    /// is fully cleared.
    private var tierDots: some View {
        HStack(spacing: 4) {
            ForEach(1...5, id: \.self) { tier in
                Circle()
                    .fill(service.highestClearedTier >= tier ? tierColor(for: tier) : Color.gray.opacity(0.25))
                    .frame(width: 8, height: 8)
            }
        }
    }

    private func tierColor(for tier: Int) -> Color {
        OlympianPathBluePalette.color(for: tier)
    }

    // MARK: - Next-goal preview

    @ViewBuilder
    private var nextGoalRow: some View {
        if let next = service.nextGoal {
            HStack(spacing: 10) {
                Image(systemName: next.icon)
                    .font(.body)
                    .foregroundColor(next.tierColor)
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Next up: \(next.title)")
                        .font(.ds_labelMedium)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        ProgressView(value: next.progressPercent)
                            .progressViewStyle(.linear)
                            .tint(next.tierColor)
                            .frame(maxWidth: 120)

                        Text("\(next.progress)/\(next.threshold)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 4)
        } else if service.seasonComplete {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.body)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [tierAccent, .white.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                Text("All 33 unlocked — share the moment")
                    .font(.ds_labelMedium)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 4)
        } else if service.isLoading {
            ProgressView()
                .scaleEffect(0.8)
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
        }
    }
}
