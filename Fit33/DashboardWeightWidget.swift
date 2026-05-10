import SwiftUI

// MARK: - Dashboard Weight Widget
struct DashboardWeightWidget: View {
    let isCompact: Bool
    
    @ObservedObject private var weightService = WeightTrackingService.shared
    @StateObject private var premiumManager = PremiumManager.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var showingInput = false
    @State private var showingPremiumUpgrade = false

    // Match the WeightTrackerWidget color scheme (orange/yellow)
    private let gradientColors: [Color] = [.orange, .yellow]
    
    var body: some View {
        Button(action: {
            HapticManager.tap()
            if premiumManager.isPremiumUser {
                // Disable the system fullScreenCover slide-up animation —
                // our inner ZStack drives the popup with its own snappy spring
                // so the card "pops" instantly instead of waiting on the
                // standard ~350ms sheet animation + sequential keyboard slide.
                var t = Transaction()
                t.disablesAnimations = true
                withTransaction(t) {
                    showingInput = true
                }
            } else {
                showingPremiumUpgrade = true
            }
        }) {
            widgetContentWithPremiumBadge
        }
        .buttonStyle(PlainButtonStyle())
        .fullScreenCover(isPresented: $showingInput) {
            WeightInputPopupCard(weightService: weightService) {
                var t = Transaction()
                t.disablesAnimations = true
                withTransaction(t) { showingInput = false }
            }
            .presentationBackground(.clear)
        }
        .fullScreenCover(isPresented: $showingPremiumUpgrade) {
            PremiumUpgradeView(triggeringFeature: .weightTracking)
        }
        .onAppear {
            // Refresh weight data when widget appears
            Task {
                await weightService.loadAllData()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .weightDidUpdate)) { _ in
            // Weight was updated elsewhere (e.g., nutrition tab) - force reload to stay
            // in sync. MUST pass force: true to bypass the 10s loadAllData throttle,
            // otherwise a user-initiated weight entry from another widget is silently
            // dropped here. Root cause of shake reports 40 / 66.
            Task {
                await weightService.loadAllData(force: true)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .dailyResetCompleted)) { _ in
            // 🌙 Daily reset completed - refresh all dashboard data
            AppLogger.debug("[DASHBOARD] Daily reset notification received - refreshing data", category: .ui)
            Task {
                await ChallengeService.shared.fetchActiveChallenges()
                await HydrationService.shared.loadTodayData()
                await weightService.loadAllData()
                MealService.shared.loadTodaysMeals()
            }
        }
    }
    
    @ViewBuilder
    private var widgetContentWithPremiumBadge: some View {
        ZStack(alignment: .topTrailing) {
            widgetContent
            
            // Premium badge for free users
            if !premiumManager.isPremiumUser {
                HStack(spacing: 4) {
                    Image(systemName: "crown.fill")
                        .font(.ds_caption)
                    Text("PRO")
                        .font(.ds_caption)
                        .tracking(1)
                }
                .foregroundColor(.black.opacity(0.8))
                .padding(.horizontal, Spacing.xs)
                .padding(.vertical, Spacing.xxs)
                .background(
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 1.0, green: 0.84, blue: 0), Color(red: 1.0, green: 0.75, blue: 0.3)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .shadow(color: .blue.opacity(0.4), radius: 4, x: 0, y: 2)
                )
                .offset(x: -8, y: 8)
            }
        }
    }
    
    @ViewBuilder
    private var widgetContent: some View {
        Group {
            if isCompact {
                compactLayout
            } else {
                expandedLayout
            }
        }
        .frame(width: isCompact ? 160 : nil, height: isCompact ? 140 : 80)
        .frame(maxWidth: isCompact ? nil : .infinity)
        .padding(.horizontal, isCompact ? 0 : 20)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(gradientColors[0].opacity(colorScheme == .dark ? 0.08 : 0.04))
                    .offset(y: 6)
                    .blur(radius: 3)
                
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Color.black.opacity(colorScheme == .dark ? 0.2 : 0.04))
                    .offset(y: 4)
                
                AdaptiveCardSurface(cornerRadius: 24)
                
                RoundedRectangle(cornerRadius: 24, style: .continuous)
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
                
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [gradientColors[0].opacity(colorScheme == .dark ? 0.25 : 0.18), gradientColors[0].opacity(colorScheme == .dark ? 0.15 : 0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
        .shadow(color: gradientColors[0].opacity(colorScheme == .dark ? 0.1 : 0.06), radius: 12, x: 0, y: 3)
    }
    
    private var compactLayout: some View {
        VStack(spacing: 10) {
            // Icon
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: gradientColors),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 50, height: 50)
                    .shadow(color: gradientColors[0].opacity(0.4), radius: 8, x: 0, y: 4)
                
                Image(systemName: "scalemass.fill")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
            }
            
            // Weight display
            VStack(spacing: 4) {
                if let todayWeight = weightService.todayLog {
                    let displayWeight = weightService.usesLbs ? todayWeight.weightLbs : todayWeight.weightKg
                    let unit = weightService.usesLbs ? "lbs" : "kg"
                    
                    Text("\(String(format: "%.1f", displayWeight)) \(unit)")
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                        .id(todayWeight.id) // Force refresh when weight changes
                    
                    // 7-day trend
                    trendLabel
                } else {
                    Text("Tap to add")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundStyle(
                            LinearGradient(colors: gradientColors, startPoint: .leading, endPoint: .trailing)
                        )
                }
            }
        }
    }
    
    @ViewBuilder
    private var trendLabel: some View {
        let weeklyChange = weightService.weeklyChange
        
        if abs(weeklyChange) < 0.1 {
            // Essentially no change
            Text("7-day: maintaining")
                .font(.caption2)
                .foregroundColor(.secondary)
        } else if weeklyChange < 0 {
            // Losing weight
            HStack(spacing: 2) {
                Image(systemName: "arrow.down.right")
                    .font(.system(size: 9, weight: .bold))
                Text("7-day: losing")
                    .font(.caption2)
            }
            .foregroundColor(.green)
        } else {
            // Gaining weight
            HStack(spacing: 2) {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9, weight: .bold))
                Text("7-day: gaining")
                    .font(.caption2)
            }
            .foregroundColor(.orange)
        }
    }
    
    private var expandedLayout: some View {
        HStack(spacing: 16) {
            // Icon
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: gradientColors),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 50, height: 50)
                    .shadow(color: gradientColors[0].opacity(0.4), radius: 8, x: 0, y: 4)
                
                Image(systemName: "scalemass.fill")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Today's Weight")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                // 7-day trend for expanded view
                expandedTrendLabel
            }
            
            Spacer()
            
            // Show weight or placeholder
            if let todayWeight = weightService.todayLog {
                let displayWeight = weightService.usesLbs ? todayWeight.weightLbs : todayWeight.weightKg
                let unit = weightService.usesLbs ? "lbs" : "kg"
                Text("\(String(format: "%.1f", displayWeight)) \(unit)")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(
                        LinearGradient(colors: gradientColors, startPoint: .leading, endPoint: .trailing)
                    )
                    .id(todayWeight.id) // Force refresh when weight changes
            } else {
                Text("Tap to add")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundStyle(
                        LinearGradient(colors: gradientColors, startPoint: .leading, endPoint: .trailing)
                    )
            }
        }
    }
    
    /// Empty state shows nothing under the title — the "Tap to add"
    /// affordance on the right carries the call-to-action on its own.
    @ViewBuilder
    private var expandedTrendLabel: some View {
        if weightService.todayLog != nil {
            let weeklyChange = weightService.weeklyChange
            
            if abs(weeklyChange) < 0.1 {
                Text("7-day: maintaining")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else if weeklyChange < 0 {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.down.right")
                        .font(.ds_caption)
                    Text("7-day: losing weight")
                        .font(.caption)
                }
                .foregroundColor(.green)
            } else {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.up.right")
                        .font(.ds_caption)
                    Text("7-day: gaining weight")
                        .font(.caption)
                }
                .foregroundColor(.orange)
            }
        }
    }
    
    private var widgetBackground: some View {
        ZStack {
            // Bottom shadow layer (deepest) - color glow
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(gradientColors[0].opacity(colorScheme == .dark ? 0.15 : 0.08))
                .offset(y: 8)
                .blur(radius: 4)
            
            // Middle shadow layer
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color.black.opacity(colorScheme == .dark ? 0.2 : 0.04))
                .offset(y: 4)
            
            // Main card background — adaptive (frosted ↔ solid via setting)
            AdaptiveCardSurface(cornerRadius: 24)
            
            // Inner highlight (top edge glow)
            RoundedRectangle(cornerRadius: 24, style: .continuous)
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
            
            // Colored accent border
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [gradientColors[0].opacity(colorScheme == .dark ? 0.4 : 0.3), gradientColors[1].opacity(colorScheme == .dark ? 0.3 : 0.2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
    }
}

// MARK: - Weight Input Popup Card
//
// Custom popup card replacing the old `.sheet` modal. The iOS sheet's fixed
// ~350ms slide-up animation + sequential keyboard slide produced a visible
// "delay" before the user could type (especially in Low Power Mode). This
// card drives its own spring (response: 0.32, damping: 0.85) and requests
// keyboard focus on appear, so the card scales/fades in WHILE the keyboard
// slides up — the two animations overlap instead of stacking.
struct WeightInputPopupCard: View {
    @ObservedObject var weightService: WeightTrackingService
    let onDismiss: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var weightInput = ""
    @State private var animateIn = false
    @FocusState private var isInputFocused: Bool

    private let gradientColors: [Color] = [.orange, .yellow]

    var body: some View {
        ZStack {
            // Tappable dim backdrop
            Color.black
                .opacity(animateIn ? 0.5 : 0)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { close() }
                .accessibilityHidden(true)

            // Centered popup card
            cardBody
                .scaleEffect(animateIn ? 1 : 0.92)
                .opacity(animateIn ? 1 : 0)
                .padding(.horizontal, 20)
        }
        .onAppear {
            if weightService.hasLoggedToday, let todayWeight = weightService.todayLog {
                let displayWeight = weightService.usesLbs ? todayWeight.weightLbs : todayWeight.weightKg
                weightInput = String(format: "%.1f", displayWeight)
            }
            withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                animateIn = true
            }
            isInputFocused = true
        }
    }

    private var cardBody: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Log Weight")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)

                Spacer()

                Button(action: close) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                .accessibilityLabel("Close")
                .accessibilityHint("Dismiss weight entry")
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                TextField("0.0", text: $weightInput)
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.center)
                    .focused($isInputFocused)
                    .frame(maxWidth: 200)

                Text(weightService.usesLbs ? "lbs" : "kg")
                    .font(.title3)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 4)

            Button(action: saveWeight) {
                Text("Save")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.md)
                    .background(
                        LinearGradient(
                            colors: gradientColors,
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(14)
            }
            .disabled(weightInput.isEmpty)
            .opacity(weightInput.isEmpty ? 0.5 : 1)
            .accessibilityLabel("Save weight")
            .accessibilityHint("Logs the entered weight")
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [gradientColors[0].opacity(0.3), gradientColors[1].opacity(0.15)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.4 : 0.18), radius: 24, x: 0, y: 12)
        .shadow(color: gradientColors[0].opacity(colorScheme == .dark ? 0.18 : 0.10), radius: 20, x: 0, y: 6)
    }

    private func close() {
        isInputFocused = false
        withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
            animateIn = false
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            onDismiss()
        }
    }

    private func saveWeight() {
        guard let weight = Double(weightInput) else {
            // Invalid user input is a UX event, not a bug. Invariant 25.
            AppLogger.warning("[Widget] Invalid weight input: '\(weightInput)'", category: .ui)
            return
        }

        AppLogger.debug("[Widget] Saving weight: \(weight) \(weightService.usesLbs ? "lbs" : "kg")", category: .ui)
        HapticManager.success()
        isInputFocused = false

        // Animate the card out immediately for a snappy feel — the network
        // write continues in the background and the .weightDidUpdate
        // notification keeps the dashboard widget in sync.
        withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
            animateIn = false
        }

        Task {
            let success = await weightService.logWeight(weight)
            if success {
                AppLogger.info("[Widget] Weight saved successfully, todayLog: \(weightService.todayLog != nil ? "SET" : "NIL"), hasLoggedToday: \(weightService.hasLoggedToday)", category: .ui)
            } else {
                // WeightTrackingService.logWeight already routed the real error
                // through NetworkErrorClassifier with op/endpoint/startedAt/userId/pg_code
                // (fingerprints like 95b0b27b / 51cc11dc). Re-logging here at .error
                // manufactured a second fingerprint (0559291e) per invariant 25a.
                // Keep the breadcrumb but at .warning so it doesn't fingerprint.
                AppLogger.warning("[Widget] logWeight returned false — surface already reported by WeightTrackingService", category: .ui)
            }
            await MainActor.run {
                AppLogger.debug("[Widget] Dismissing popup, todayLog still: \(weightService.todayLog != nil ? "SET" : "NIL")", category: .ui)
                onDismiss()
            }
        }
    }
}
