import SwiftUI

// MARK: - Dashboard Weight Widget
struct DashboardWeightWidget: View {
    let isCompact: Bool
    
    @ObservedObject private var weightService = WeightTrackingService.shared
    @StateObject private var premiumManager = PremiumManager.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var showingInput = false
    @State private var showingPremiumUpgrade = false
    @State private var weightInput = ""
    @FocusState private var isInputFocused: Bool
    
    // Match the WeightTrackerWidget color scheme (orange/yellow)
    private let gradientColors: [Color] = [.orange, .yellow]
    
    var body: some View {
        Button(action: {
            HapticManager.tap()
            if premiumManager.isPremiumUser {
                showingInput = true
            } else {
                showingPremiumUpgrade = true
            }
        }) {
            widgetContentWithPremiumBadge
        }
        .buttonStyle(PlainButtonStyle())
        .sheet(isPresented: $showingInput) {
            WeightInputSheet(weightService: weightService, autoFocus: $showingInput)
                .presentationDetents([.height(280)])
                .presentationDragIndicator(.visible)
                .presentationBackgroundInteraction(.enabled)
                .interactiveDismissDisabled(false)
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
                
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.cardBackground)
                
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
                Text("Weight")
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
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(
                        LinearGradient(colors: gradientColors, startPoint: .leading, endPoint: .trailing)
                    )
            }
        }
    }
    
    @ViewBuilder
    private var expandedTrendLabel: some View {
        if weightService.todayLog == nil {
            Text("Log today's weight")
                .font(.caption)
                .foregroundColor(.secondary)
        } else {
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
            
            // Main card background with gradient
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    Color.cardBackground
                )
            
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

// MARK: - Weight Input Sheet
struct WeightInputSheet: View {
    @ObservedObject var weightService: WeightTrackingService
    @Binding var autoFocus: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var weightInput = ""
    @FocusState private var isInputFocused: Bool
    
    // Match the WeightTrackerWidget color scheme (orange/yellow)
    private let gradientColors: [Color] = [.orange, .yellow]
    
    init(weightService: WeightTrackingService, autoFocus: Binding<Bool>) {
        self.weightService = weightService
        self._autoFocus = autoFocus
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Text("Log Weight")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            
            // Weight input
            HStack(spacing: 8) {
                TextField("0.0", text: $weightInput)
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.center)
                    .focused($isInputFocused)
                    .frame(maxWidth: 200)
                    .onAppear {
                        // Focus immediately on appear
                        DispatchQueue.main.async {
                            isInputFocused = true
                        }
                    }
                
                Text(weightService.usesLbs ? "lbs" : "kg")
                    .font(.title)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 10)
            
            // Save button
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
            .padding(.horizontal, 20)
            
            Spacer()
        }
        .onAppear {
            // Pre-fill with current weight if logged today
            if weightService.hasLoggedToday, let todayWeight = weightService.todayLog {
                let displayWeight = weightService.usesLbs ? todayWeight.weightLbs : todayWeight.weightKg
                weightInput = String(format: "%.1f", displayWeight)
            }
            // Focus immediately - no delay
            isInputFocused = true
        }
    }
    
    private func saveWeight() {
        guard let weight = Double(weightInput) else {
            AppLogger.error("[Widget] Invalid weight input: '\(weightInput)'", category: .ui)
            return
        }
        
        AppLogger.debug("[Widget] Saving weight: \(weight) \(weightService.usesLbs ? "lbs" : "kg")", category: .ui)
        HapticManager.success()
        
        Task {
            let success = await weightService.logWeight(weight)
            if success {
                AppLogger.info("[Widget] Weight saved successfully, todayLog: \(weightService.todayLog != nil ? "SET" : "NIL"), hasLoggedToday: \(weightService.hasLoggedToday)", category: .ui)
                // Small delay to ensure UI updates propagate
                try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
            } else {
                AppLogger.error("[Widget] Failed to save weight to cloud", category: .ui)
            }
            await MainActor.run {
                AppLogger.debug("[Widget] Dismissing sheet, todayLog still: \(weightService.todayLog != nil ? "SET" : "NIL")", category: .ui)
                dismiss()
            }
        }
    }
}
