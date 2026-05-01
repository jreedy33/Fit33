//
//  ChallengeCreationCards.swift
//  Fit33
//
//  Restored 2026-05-01 from `ChallengeCreationFlow.swift` (deleted earlier
//  in the same sprint). Seven SwiftUI subview structs that were originally
//  defined alongside `ChallengeCreationFlow` but are still used by the LIVE
//  views `ChallengeFlowStartView` (1v1 / group friend challenge) and
//  `PrivateChallengeCreationFlow` (group chat challenge):
//
//    • `ModeSelectionCard` — Accountability vs Competition picker
//    • `ActivityTypeCard` — activity tile (Steps / Run / Lift / …) in the picker
//    • `CustomTargetCard` — custom-target stepper (with HydrationUnit picker)
//    • `ChallengeOptionCard` — preset option row (e.g. "10K Steps Daily")
//    • `ChallengeDurationCard` — duration picker (1d / 3d / 7d / 14d / 30d)
//    • `ReviewRow` — labeled key/value row in the final review step
//    • `GradientButton` — primary CTA with gradient + loading state
//
//  Sprint 20260811 patch: `ActivityTypeCard` now shows a "Powered by Strava"
//  pill in the bottom-right corner when `activity == .run` AND the user has
//  Strava connected — same UX pattern as the template-card pill in
//  `ChallengeSetupView.TemplateCard`. The pill is purely informational; runs
//  still log via HealthKit even without Strava (Strava is the auto-sync
//  enrichment path, not the only path).
//

import SwiftUI


struct ModeSelectionCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let mode: ChallengeMode
    let isSelected: Bool
    let onSelect: () -> Void
    
    private var bulletPoints: [String] {
        switch mode {
        case .accountability:
            return [
                "Both commit to the same daily goal",
                "Build a shared streak together 🔥",
                "No scores — just consistency",
                "Get nudged if your buddy misses a day"
            ]
        case .competition:
            return [
                "Real-time scoreboard tracks everything",
                "Crown 👑 goes to whoever's ahead",
                "Daily winner & overall winner",
                "Bragging rights on the line"
            ]
        }
    }
    
    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(mode.emoji)
                            .font(.system(size: 36))
                        
                        Text(mode.title)
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        
                        Text(mode.subtitle)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(LinearGradient(colors: mode.gradientColors, startPoint: .leading, endPoint: .trailing))
                    }
                    
                    Spacer()
                    
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.ds_heading2)
                            .foregroundStyle(LinearGradient(colors: mode.gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing))
                    }
                }
                
                // Bullet points
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(bulletPoints, id: \.self) { point in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(LinearGradient(colors: mode.gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 5, height: 5)
                            Text(point)
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.75))
                        }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                ZStack {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(mode.gradientColors[0].opacity(colorScheme == .dark ? 0.15 : 0.08))
                            .offset(y: 8)
                            .blur(radius: 4)
                    }
                    
                    RoundedRectangle(cornerRadius: 21, style: .continuous)
                        .fill(Color.black.opacity(colorScheme == .dark ? 0.2 : 0.04))
                        .offset(y: 4)
                    
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: colorScheme == .dark
                                    ? [Color(white: 0.18), Color.cardBackground]
                                    : [Color.white, Color.white.opacity(0.95)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: colorScheme == .dark
                                    ? [Color.white.opacity(0.1), Color.white.opacity(0.02), Color.clear]
                                    : [Color.white, Color.white.opacity(0.5), Color.clear],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1.5
                        )
                    
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: isSelected ? mode.gradientColors : [mode.gradientColors[0].opacity(0.3), mode.gradientColors[1].opacity(0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: isSelected ? 2 : 1
                        )
                }
            )
            .shadow(color: isSelected ? mode.gradientColors[0].opacity(0.3) : .clear, radius: 12, x: 0, y: 6)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct ActivityTypeCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let activity: ChallengeActivityType
    let isSelected: Bool
    let onSelect: () -> Void

    // Sprint 20260811 — observe Strava so the "Powered by Strava" pill on
    // the Run tile updates live when the user toggles Strava in Settings.
    @ObservedObject private var strava = StravaService.shared

    /// True only for the Run tile when Strava is connected. Strava
    /// auto-syncs runs into the challenge progress pipeline; users without
    /// Strava still get HealthKit-sourced runs, so the pill is purely
    /// informational ("we'll grab this from Strava the moment you finish").
    private var showStravaPill: Bool {
        activity == .run && strava.isConnected
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 8) {
                Text(activity.emoji)
                    .font(.system(size: 36))

                Text(activity.rawValue)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .bold : .semibold)
                    .foregroundColor(.white)

                if showStravaPill {
                    Text("Powered by Strava")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.orange.opacity(0.18)))
                        .foregroundColor(.orange)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: showStravaPill ? 115 : 95)
            .background(
                ZStack {
                    // Bottom shadow layer (deepest) - colored glow for selected
                    if isSelected {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(activity.gradientColors[0].opacity(colorScheme == .dark ? 0.15 : 0.08))
                            .offset(y: 8)
                            .blur(radius: 4)
                    }
                    
                    // Middle shadow layer
                    RoundedRectangle(cornerRadius: 21, style: .continuous)
                        .fill(Color.black.opacity(colorScheme == .dark ? 0.2 : 0.04))
                        .offset(y: 4)
                    
                    // Main card background
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: colorScheme == .dark
                                    ? [Color(white: 0.18), Color.cardBackground]
                                    : [Color.white, Color.white.opacity(0.95)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    
                    // Inner highlight (top edge glow)
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: colorScheme == .dark
                                    ? [Color.white.opacity(0.1), Color.white.opacity(0.02), Color.clear]
                                    : [Color.white, Color.white.opacity(0.5), Color.clear],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1.5
                        )
                    
                    // Colored accent border (subtle when unselected, bold when selected)
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: isSelected ? activity.gradientColors : [activity.gradientColors[0].opacity(0.3), activity.gradientColors[1].opacity(0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: isSelected ? 2 : 1
                        )
                }
            )
            .scaleEffect(isSelected ? 1.03 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct CustomTargetCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let activity: ChallengeActivityType
    @Binding var customTarget: Int
    @Binding var hydrationUnit: HydrationUnit
    let isSelected: Bool
    let gradientColors: [Color]
    let onSelect: () -> Void
    
    @State private var editText: String = ""
    @State private var isEditingText: Bool = false
    @FocusState private var textFieldFocused: Bool
    
    private var stepAmount: Int {
        switch activity {
        case .walk, .run: return 5 // minutes
        case .lift: return 1 // workouts
        case .hydrate: return 250 // ml or oz
        case .steps: return 500 // steps
        case .calories: return 50 // calories
        case .protein: return 10 // grams
        case .activeMinutes: return 5 // minutes
        case .workoutStreak: return 1 // workouts
        case .sleep: return 1 // hours
        }
    }
    
    private var minValue: Int {
        switch activity {
        case .walk, .run: return 5
        case .lift: return 1
        case .hydrate: return 250
        case .steps: return 1000
        case .calories: return 100
        case .protein: return 50
        case .activeMinutes: return 5
        case .workoutStreak: return 1
        case .sleep: return 4
        }
    }
    
    private var maxValue: Int {
        switch activity {
        case .walk, .run: return 120
        case .lift: return 7
        case .hydrate: return 5000
        case .steps: return 30000
        case .calories: return 2000
        case .protein: return 400
        case .activeMinutes: return 180
        case .workoutStreak: return 5
        case .sleep: return 12
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            Button(action: {
                AppLogger.debug("🎯 [CUSTOM TARGET] Card tapped - selecting custom option", category: .social)
                onSelect()
            }) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("✏️ Custom Goal")
                            .font(.headline)
                            .fontWeight(isSelected ? .bold : .semibold)
                            .foregroundColor(.white)
                        
                        Spacer()
                        
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.ds_heading2)
                                .foregroundStyle(LinearGradient(colors: gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing))
                        }
                    }
                    
                    Text("Set your own daily target")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                
                // Stepper / Counter
                HStack(spacing: 16) {
                    // Minus button
                    Button(action: {
                        if customTarget > minValue {
                            AppLogger.debug("➖ [CUSTOM TARGET] Decreased to \(customTarget - stepAmount)", category: .social)
                            HapticManager.impact(.light)
                            customTarget -= stepAmount
                        }
                    }) {
                        Image(systemName: "minus.circle.fill")
                            .font(.ds_heading1)
                            .foregroundColor(customTarget > minValue ? .white : .white.opacity(0.3))
                    }
                    .disabled(customTarget <= minValue)
                    .buttonStyle(.plain)
                    
                    // Value display — tappable to type
                    VStack(spacing: 4) {
                        if isEditingText {
                            TextField("", text: $editText)
                                .font(.ds_stat)
                                .foregroundColor(.white)
                                .multilineTextAlignment(.center)
                                .keyboardType(.numberPad)
                                .focused($textFieldFocused)
                                .onSubmit { commitEdit() }
                                .onChange(of: textFieldFocused) { _, focused in
                                    if !focused { commitEdit() }
                                }
                        } else {
                            Text("\(customTarget)")
                                .font(.ds_stat)
                                .foregroundColor(.white)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    editText = "\(customTarget)"
                                    isEditingText = true
                                    textFieldFocused = true
                                    onSelect()
                                }
                        }
                        
                        if activity == .hydrate {
                            // Unit picker for hydration
                            HStack(spacing: 4) {
                                ForEach(HydrationUnit.allCases, id: \.self) { unit in
                                    Button(action: {
                                        HapticManager.impact(.light)
                                        hydrationUnit = unit
                                    }) {
                                        Text(unit.rawValue)
                                            .font(.caption)
                                            .fontWeight(hydrationUnit == unit ? .bold : .regular)
                                            .foregroundColor(hydrationUnit == unit ? .white : .white.opacity(0.5))
                                            .padding(.horizontal, Spacing.xs)
                                            .padding(.vertical, Spacing.xxs)
                                            .background(
                                                Capsule()
                                                    .fill(hydrationUnit == unit ? Color.white.opacity(0.2) : Color.clear)
                                            )
                                    }
                                }
                            }
                        } else {
                            Text(getUnitText())
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                    .frame(minWidth: 120)
                    
                    // Plus button
                    Button(action: {
                        if customTarget < maxValue {
                            AppLogger.debug("➕ [CUSTOM TARGET] Increased to \(customTarget + stepAmount)", category: .social)
                            HapticManager.impact(.light)
                            customTarget += stepAmount
                        }
                    }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.ds_heading1)
                            .foregroundColor(customTarget < maxValue ? .white : .white.opacity(0.3))
                    }
                    .disabled(customTarget >= maxValue)
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(Spacing.md)
            .background(
                ZStack {
                    // Bottom shadow layer (deepest) - colored glow for selected
                    if isSelected {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(gradientColors[0].opacity(0.15))
                            .offset(y: 8)
                            .blur(radius: 4)
                    }
                    
                    // Middle shadow layer
                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                        .fill(Color.black.opacity(colorScheme == .dark ? 0.2 : 0.04))
                        .offset(y: 4)
                    
                    // Main card background
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: colorScheme == .dark
                                    ? [Color(white: 0.18), Color.cardBackground]
                                    : [Color.white, Color.white.opacity(0.95)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    
                    // Inner highlight (top edge glow)
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: colorScheme == .dark
                                    ? [Color.white.opacity(0.1), Color.white.opacity(0.02), Color.clear]
                                    : [Color.white, Color.white.opacity(0.5), Color.clear],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1.5
                        )
                    
                    // Colored accent border (subtle when unselected, bold when selected)
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: isSelected ? gradientColors : [gradientColors[0].opacity(0.3), gradientColors[1].opacity(0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: isSelected ? 2 : 1
                        )
                }
            )
            .scaleEffect(isSelected ? 1.02 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
            }
            .buttonStyle(PlainButtonStyle())
        }
    }
    
    private func commitEdit() {
        isEditingText = false
        if let value = Int(editText) {
            customTarget = min(maxValue, max(minValue, value))
        }
        editText = ""
    }
    
    private func getUnitText() -> String {
        switch activity {
        case .walk, .run: return "minutes per day"
        case .lift: return "workouts per week"
        case .hydrate: return hydrationUnit.rawValue + " per day"
        case .steps: return "steps per day"
        case .calories: return "calories per day"
        case .protein: return "grams per day"
        case .activeMinutes: return "minutes per day"
        case .workoutStreak: return "workouts per day"
        case .sleep: return "hours per night"
        }
    }
    
    private func getUnitForActivity(_ activity: ChallengeActivityType) -> String {
        switch activity {
        case .walk, .run: return "minutes"
        case .lift: return "workouts"
        case .hydrate: return "ml"
        case .steps: return "steps"
        case .calories: return "calories"
        case .protein: return "grams"
        case .activeMinutes: return "minutes"
        case .workoutStreak: return "workouts"
        case .sleep: return "hours"
        }
    }
}

struct ChallengeOptionCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let option: ChallengeOption
    let isSelected: Bool
    let gradientColors: [Color]
    let onSelect: () -> Void
    
    /// Extract the leading emoji from the title (if any)
    private var titleEmoji: String {
        let title = option.title
        if let first = title.unicodeScalars.first, first.properties.isEmoji && first.value > 0x238C {
            // Find where the emoji ends
            let idx = title.index(after: title.startIndex)
            // Skip any variation selectors or joiners
            var end = idx
            while end < title.endIndex {
                let scalar = title.unicodeScalars[title.unicodeScalars.index(title.unicodeScalars.startIndex, offsetBy: title.distance(from: title.startIndex, to: end))]
                if scalar.properties.isEmoji || scalar.value == 0xFE0F || scalar.value == 0x200D {
                    end = title.index(after: end)
                } else {
                    break
                }
            }
            return String(title[title.startIndex..<end]).trimmingCharacters(in: .whitespaces)
        }
        return ""
    }
    
    private var titleText: String {
        let emoji = titleEmoji
        if emoji.isEmpty { return option.title }
        return option.title.dropFirst(emoji.count).trimmingCharacters(in: .whitespaces)
    }
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 14) {
                // Gradient emoji circle (exercise library style)
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: gradientColors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 46, height: 46)
                        .shadow(color: isSelected ? gradientColors[0].opacity(0.3) : .clear, radius: 6, x: 0, y: 3)
                    
                    Text(titleEmoji.isEmpty ? "🎯" : titleEmoji)
                        .font(.ds_heading2)
                }
                
                // Title + description
                VStack(alignment: .leading, spacing: 4) {
                    Text(titleText)
                        .font(.body)
                        .fontWeight(isSelected ? .bold : .semibold)
                        .foregroundColor(.white)
                        .lineLimit(1)
                    
                    HStack(spacing: 6) {
                        Text(option.description)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.6))
                            .lineLimit(1)
                        
                        Text("•")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.4))
                        
                        Text("\(option.dailyTarget) \(option.unit)")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(isSelected ? gradientColors[0] : .white.opacity(0.8))
                    }
                }
                
                Spacer(minLength: 4)
                
                // Checkmark
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.ds_heading2)
                        .foregroundStyle(LinearGradient(colors: gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing))
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, 14)
            .background(
                ZStack {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(gradientColors[0].opacity(colorScheme == .dark ? 0.15 : 0.08))
                            .offset(y: 8)
                            .blur(radius: 4)
                    }
                    
                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                        .fill(Color.black.opacity(colorScheme == .dark ? 0.2 : 0.04))
                        .offset(y: 4)
                    
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: colorScheme == .dark
                                    ? [Color(white: 0.18), Color.cardBackground]
                                    : [Color.white, Color.white.opacity(0.95)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: colorScheme == .dark
                                    ? [Color.white.opacity(0.1), Color.white.opacity(0.02), Color.clear]
                                    : [Color.white, Color.white.opacity(0.5), Color.clear],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1.5
                        )
                    
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: isSelected ? gradientColors : [gradientColors[0].opacity(0.3), gradientColors[1].opacity(0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: isSelected ? 2 : 1
                        )
                }
            )
            .shadow(color: isSelected ? gradientColors[0].opacity(0.3) : .clear, radius: 12, x: 0, y: 6)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct ChallengeDurationCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let days: Int
    let isSelected: Bool
    let onSelect: () -> Void
    
    var durationText: String {
        switch days {
        case 3: return "3 Days\nQuick Sprint"
        case 7: return "1 Week\nStandard"
        case 14: return "2 Weeks\nCommitment"
        case 30: return "1 Month\nLong Term"
        default: return "\(days) Days"
        }
    }
    
    var body: some View {
        Button(action: onSelect) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(durationText.components(separatedBy: "\n").first ?? "")
                        .font(.title3)
                        .fontWeight(isSelected ? .bold : .semibold)
                        .foregroundColor(.white)
                    
                    Text(durationText.components(separatedBy: "\n").last ?? "")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.7))
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.ds_heading2)
                        .foregroundStyle(LinearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing))
                }
            }
            .padding(20)
            .background(
                ZStack {
                    // Bottom shadow layer (deepest) - colored glow for selected
                    if isSelected {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.blue.opacity(0.15))
                            .offset(y: 8)
                            .blur(radius: 4)
                    }
                    
                    // Middle shadow layer
                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                        .fill(Color.black.opacity(colorScheme == .dark ? 0.2 : 0.04))
                        .offset(y: 4)
                    
                    // Main card background
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: colorScheme == .dark
                                    ? [Color(white: 0.18), Color.cardBackground]
                                    : [Color.white, Color.white.opacity(0.95)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    
                    // Inner highlight (top edge glow)
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: colorScheme == .dark
                                    ? [Color.white.opacity(0.1), Color.white.opacity(0.02), Color.clear]
                                    : [Color.white, Color.white.opacity(0.5), Color.clear],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1.5
                        )
                    
                    // Colored accent border (subtle when unselected, bold when selected)
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: isSelected ? [.blue, .cyan] : [Color.blue.opacity(0.3), Color.cyan.opacity(0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: isSelected ? 2 : 1
                        )
                }
            )
            .scaleEffect(isSelected ? 1.02 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct ReviewRow: View {
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.7))
            Spacer()
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.white)
        }
    }
}

struct GradientButton: View {
    let title: String
    let icon: String
    let gradientColors: [Color]
    let isEnabled: Bool
    let isLoading: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: gradientColors[0]))
                        .scaleEffect(0.9)
                } else {
                    Image(systemName: icon)
                        .font(.ds_labelLarge)
                    
                    Text(title)
                        .font(.headline)
                        .fontWeight(.semibold)
                }
            }
            .foregroundStyle(
                isEnabled ?
                LinearGradient(colors: gradientColors, startPoint: .leading, endPoint: .trailing)
                :
                LinearGradient(colors: [.gray], startPoint: .leading, endPoint: .trailing)
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.md)
            .overlay(
                Capsule()
                    .stroke(
                        isEnabled ?
                        LinearGradient(colors: gradientColors, startPoint: .leading, endPoint: .trailing)
                        :
                        LinearGradient(colors: [.gray.opacity(0.3)], startPoint: .leading, endPoint: .trailing),
                        lineWidth: 2
                    )
            )
            .shadow(color: isEnabled ? gradientColors[0].opacity(0.4) : .clear, radius: 12, x: 0, y: 6)
            .shadow(color: isEnabled ? gradientColors[1].opacity(0.3) : .clear, radius: 16, x: 0, y: 8)
            .opacity(isEnabled ? 1 : 0.6)
        }
        .disabled(!isEnabled || isLoading)
        .buttonStyle(PlainButtonStyle())
    }
}
