import SwiftUI
import CoreData

// MARK: - Weight Tracker Widget

struct WeightTrackerWidget: View {
    @ObservedObject private var weightService = WeightTrackingService.shared
    @ObservedObject private var premiumManager = PremiumManager.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var showingAddSheet = false
    @State private var showingDetailView = false
    @State private var showingPremiumUpgrade = false

    private let primaryColor = Color.orange
    private let gradient: [Color] = [.orange, .yellow]
    
    var body: some View {
        Group {
            if premiumManager.isPremiumUser {
                actualWidget
            } else {
                lockedWidget
            }
        }
        .fullScreenCover(isPresented: $showingPremiumUpgrade) {
            PremiumUpgradeView(triggeringFeature: .weightTracking)
        }
        .sheet(isPresented: $showingAddSheet) {
            LogWeightSheet(weightService: weightService, autoFocus: $showingAddSheet)
                .presentationBackgroundInteraction(.enabled)
                .interactiveDismissDisabled(false)
        }
        .sheet(isPresented: $showingDetailView) {
            WeightDetailView(weightService: weightService)
        }
        .onAppear {
            Task { await weightService.loadAllData() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .weightDidUpdate)) { _ in
            Task { await weightService.loadAllData() }
        }
    }
    
    // MARK: - Compact Widget (Premium)
    private var actualWidget: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: 10) {
                Image(systemName: "scalemass.fill")
                    .font(.title3)
                    .foregroundStyle(
                        LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
                    )

                Text("Weight Tracker")
                    .font(.title3)
                    .fontWeight(.bold)
                
                Spacer()
                
                Button(action: { HapticManager.selectionChanged(); showingDetailView = true }) {
                    HStack(spacing: Spacing.xxs) {
                        Text("Details")
                            .font(.ds_labelMedium)
                        Image(systemName: "chevron.right")
                            .font(.ds_caption)
                    }
                    .foregroundColor(.orange)
                }
                .accessibilityLabel("Weight details")
                .accessibilityHint("Opens detailed weight history")
            }
            .padding(.horizontal, Spacing.xxs)
            
            // Card body
            VStack(spacing: 0) {
                // Top: insight or action replacing the old header
                HStack(spacing: 8) {
                    if !weightService.hasLoggedToday {
                        Image(systemName: "plus.circle.fill")
                            .font(.ds_bodySmall)
                            .foregroundColor(.orange)
                        Text("Tap to log today's weight")
                            .font(.ds_bodySmall)
                            .foregroundColor(.secondary)
                    } else if weightService.monthlyTrend.count >= 2 {
                        Image(systemName: weightService.weeklyChange >= 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(.ds_bodySmall)
                            .foregroundColor(weeklyChangeColor)
                        Text(weightInsightText)
                            .font(.ds_bodySmall)
                            .foregroundColor(.secondary)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.ds_bodySmall)
                            .foregroundColor(.green)
                        Text("Logged today")
                            .font(.ds_bodySmall)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 8)
                
                // Content row
                HStack(spacing: 12) {
                    // Weight number with orange/yellow gradient
                    VStack(spacing: 2) {
                        Text(formatWeight(weightService.currentWeight))
                            .font(.ds_stat)
                            .foregroundStyle(
                                LinearGradient(colors: gradient, startPoint: .leading, endPoint: .trailing)
                            )
                        Text(weightService.weightUnitSuffix)
                            .font(.ds_caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(width: 75)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        if let goal = weightService.weightGoal {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: Spacing.xxs) {
                                    Image(systemName: goal.goalType.icon)
                                        .font(.system(size: 9))
                                        .foregroundColor(goal.goalType.color)
                                    Text("\(goal.goalType.displayName) • \(formatWeight(goal.targetWeight))")
                                        .font(.ds_caption)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Text("\(Int(weightService.goalProgress * 100))%")
                                        .font(.ds_labelSmall)
                                        .foregroundColor(primaryColor)
                                }
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        Capsule().fill(Color.gray.opacity(0.12)).frame(height: 6)
                                        Capsule()
                                            .fill(LinearGradient(colors: gradient, startPoint: .leading, endPoint: .trailing))
                                            .frame(width: geo.size.width * min(weightService.goalProgress, 1.0), height: 6)
                                    }
                                }
                                .frame(height: 6)
                            }
                        }
                        
                        HStack(spacing: 0) {
                            VStack(spacing: 1) {
                                HStack(spacing: 2) {
                                    Image(systemName: "flame.fill").font(.system(size: 9)).foregroundColor(.orange)
                                    Text("\(weightService.statistics?.streakDays ?? 0)").font(.ds_labelSmall)
                                }
                                Text("streak").font(.ds_caption).foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            
                            VStack(spacing: 1) {
                                Text(weeklyRange(from: Array(weightService.monthlyTrend.suffix(7)))).font(.ds_labelSmall)
                                Text("7d range").font(.ds_caption).foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            
                            VStack(spacing: 1) {
                                Text(weeklyAverage(from: Array(weightService.monthlyTrend.suffix(7)))).font(.ds_labelSmall)
                                Text("7d avg").font(.ds_caption).foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    
                    Button(action: { HapticManager.impact(.medium); showingAddSheet = true }) {
                        ZStack {
                            Circle()
                                .fill(LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 36, height: 36)
                            Image(systemName: weightService.hasLoggedToday ? "pencil" : "plus")
                                .font(.ds_bodySmall).fontWeight(.semibold)
                                .foregroundColor(.white)
                        }
                    }
                    .scaleButtonStyle(.standard, withHaptic: true)
                    .accessibilityLabel(weightService.hasLoggedToday ? "Edit weight" : "Log weight")
                    .accessibilityHint("Opens weight entry sheet")
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
            }
            .background(compactCardBackground)
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.4 : 0.08), radius: 16, x: 0, y: 8)
            .shadow(color: primaryColor.opacity(colorScheme == .dark ? 0.2 : 0.12), radius: 16, x: 0, y: 0)
        }
    }
    
    private var weightInsightText: String {
        let change = weightService.weeklyChange
        if abs(change) < 0.1 {
            return "Maintaining weight this week"
        } else if change < 0 {
            return "\(formatWeightChangeShort(change)) \(weightService.weightUnitSuffix) this week"
        } else {
            return "+\(formatWeightChangeShort(change)) \(weightService.weightUnitSuffix) this week"
        }
    }
    
    private var compactCardBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: CornerRadius.xl)
                .fill(
                    LinearGradient(
                        colors: colorScheme == .dark
                            ? [Color(white: 0.18), Color.cardBackground]
                            : [Color.white, Color.white.opacity(0.95)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
            RoundedRectangle(cornerRadius: CornerRadius.xl)
                .stroke(
                    LinearGradient(
                        colors: colorScheme == .dark
                            ? [Color.white.opacity(0.12), Color.white.opacity(0.02), Color.clear]
                            : [Color.white, Color.white.opacity(0.5), Color.clear],
                        startPoint: .top, endPoint: .bottom
                    ),
                    lineWidth: 1.5
                )
            RoundedRectangle(cornerRadius: CornerRadius.xl)
                .stroke(
                    LinearGradient(
                        colors: [primaryColor.opacity(0.3), primaryColor.opacity(0.15)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ),
                    lineWidth: 2
                )
        }
    }
    
    // MARK: - Locked Widget (Free Users)
    private var lockedWidget: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: 10) {
                Image(systemName: "scalemass.fill")
                    .font(.title3)
                    .foregroundStyle(
                        LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
                    )

                Text("Weight Tracker")
                    .font(.title3)
                    .fontWeight(.bold)
                
                Spacer()
                
                HStack(spacing: 3) {
                    Image(systemName: "crown.fill").font(.system(size: 9, weight: .bold))
                    Text("PRO").font(.system(size: 9, weight: .bold)).tracking(0.5)
                }
                .foregroundColor(.black.opacity(0.8))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    Capsule().fill(
                        LinearGradient(colors: [Color(red: 1.0, green: 0.84, blue: 0), Color(red: 1.0, green: 0.75, blue: 0.3)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                )
            }
            .padding(.horizontal, Spacing.xxs)
            
            Button(action: { HapticManager.tap(); showingPremiumUpgrade = true }) {
                HStack(spacing: 8) {
                    Image(systemName: "lock.fill").font(.ds_heading3).foregroundColor(.yellow)
                    Text("Tap to Unlock").font(.ds_labelLarge).foregroundColor(.primary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.lg)
            }
            .buttonStyle(PlainButtonStyle())
            .background(compactCardBackground)
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.4 : 0.08), radius: 16, x: 0, y: 8)
            .accessibilityLabel("Unlock weight tracker")
            .accessibilityHint("Opens premium upgrade")
        }
    }
    
    // MARK: - Helpers
    private var weeklyChangeColor: Color {
        guard let goal = weightService.weightGoal else {
            return weightService.weeklyChange >= 0 ? .orange : .green
        }
        switch goal.goalType {
        case .lose: return weightService.weeklyChange <= 0 ? .green : .orange
        case .gain: return weightService.weeklyChange >= 0 ? .green : .orange
        case .maintain: return abs(weightService.weeklyChange) < 1 ? .green : .orange
        }
    }
    
    private func formatWeight(_ weight: Double) -> String {
        if weight == 0 { return "--" }
        return String(format: "%.1f", weight)
    }
    
    private func formatWeightChangeShort(_ change: Double) -> String {
        let sign = change >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.1f", change))"
    }
    
    private func weeklyRange(from data: [WeightTrendPoint]) -> String {
        guard !data.isEmpty else { return "--" }
        let lo = data.map { $0.weight }.min() ?? 0
        let hi = data.map { $0.weight }.max() ?? 0
        return String(format: "%.1f", hi - lo)
    }
    
    private func weeklyAverage(from data: [WeightTrendPoint]) -> String {
        guard !data.isEmpty else { return "--" }
        let avg = data.map { $0.weight }.reduce(0, +) / Double(data.count)
        return String(format: "%.1f", avg)
    }
}

// MARK: - Weight Bar Chart (for carousel slide 2)

struct WeightBarChart: View {
    let data: [WeightTrendPoint]
    let accentColors: [Color]
    
    @State private var animateBars = false
    
    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "E"
        return f
    }()
    
    var body: some View {
        let weights = data.map { $0.weight }
        let minWeight = (weights.min() ?? 0)
        let maxWeight = (weights.max() ?? 0)
        let padding = max((maxWeight - minWeight) * 0.15, 0.5)
        let chartMin = minWeight - padding
        let chartMax = maxWeight + padding
        let chartRange = max(chartMax - chartMin, 1)
        
        HStack(alignment: .bottom, spacing: Spacing.xxs) {
            VStack(alignment: .trailing, spacing: 0) {
                Text(String(format: "%.0f", chartMax))
                    .font(.ds_caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text(String(format: "%.0f", chartMin))
                    .font(.ds_caption)
                    .foregroundColor(.secondary)
            }
            .frame(width: 30)
            .padding(.bottom, 18)
            
            HStack(alignment: .bottom, spacing: Spacing.xxs) {
                ForEach(Array(data.enumerated()), id: \.offset) { index, point in
                    let isLast = index == data.count - 1
                    let normalizedHeight = CGFloat((point.weight - chartMin) / chartRange)
                    
                    VStack(spacing: Spacing.xxxs) {
                        Text(String(format: "%.0f", point.weight))
                            .font(.system(size: 8, weight: .semibold, design: .rounded))
                            .foregroundColor(isLast ? accentColors[0] : .secondary)
                            .opacity(animateBars ? 1 : 0)
                        
                        RoundedRectangle(cornerRadius: 4)
                            .fill(
                                isLast
                                    ? LinearGradient(colors: accentColors, startPoint: .bottom, endPoint: .top)
                                    : LinearGradient(colors: [accentColors[0].opacity(0.4), accentColors[1].opacity(0.25)], startPoint: .bottom, endPoint: .top)
                            )
                            .frame(height: animateBars ? max(8, 60 * normalizedHeight) : 4)
                        
                        Text(Self.dayFormatter.string(from: point.date).prefix(1))
                            .font(.system(size: 9, weight: isLast ? .bold : .medium))
                            .foregroundColor(isLast ? accentColors[0] : .secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) {
                animateBars = true
            }
        }
    }
}

// MARK: - Mini Stat Badge

struct MiniStatBadge: View {
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.ds_bodySmall).fontWeight(.bold).fontDesign(.rounded)
                .foregroundColor(color)
            Text(title)
                .font(.ds_caption)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Weight Stat Pill

struct WeightStatPill: View {
    let icon: String
    let value: String
    let label: String
    let color: Color
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        HStack(spacing: Spacing.xxs) {
            Image(systemName: icon)
                .font(.ds_labelMedium)
                .foregroundColor(color)
            
            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.ds_labelMedium).fontDesign(.rounded)
                    .foregroundColor(.primary)
                
                Text(label)
                    .font(.ds_caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous)
                .fill(color.opacity(colorScheme == .dark ? 0.15 : 0.1))
        )
    }
}

// MARK: - Trend Stat Badge

struct TrendStatBadge: View {
    let icon: String
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: Spacing.xxs) {
            Image(systemName: icon)
                .font(.ds_caption)
                .foregroundColor(color)
            
            Text(value)
                .font(.ds_labelMedium).fontDesign(.rounded)
            
            Text(title)
                .font(.ds_caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Log Weight Sheet

struct LogWeightSheet: View {
    @ObservedObject var weightService: WeightTrackingService
    @Binding var autoFocus: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var weightInput: String = ""
    @State private var notes: String = ""
    @State private var isLogging = false
    @FocusState private var isWeightFocused: Bool
    
    private let gradient: [Color] = [.orange, .yellow]
    
    init(weightService: WeightTrackingService, autoFocus: Binding<Bool>) {
        self.weightService = weightService
        self._autoFocus = autoFocus
    }
    
    // Parse weight handling both period and comma as decimal separator
    private var parsedWeight: Double? {
        // Replace comma with period to handle European locales
        let normalized = weightInput.replacingOccurrences(of: ",", with: ".")
        return Double(normalized)
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Weight input
                    VStack(spacing: 16) {
                        Text("Enter Your Weight")
                            .font(.headline)
                        
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            TextField("0.0", text: $weightInput)
                                .keyboardType(.decimalPad)
                                .font(.system(size: 56, weight: .bold, design: .rounded))
                                .multilineTextAlignment(.center)
                                .focused($isWeightFocused)
                                .frame(maxWidth: 180)
                                .onAppear {
                                    // Focus immediately on appear
                                    DispatchQueue.main.async {
                                        isWeightFocused = true
                                    }
                                }
                            
                            Text(weightService.weightUnitSuffix)
                                .font(.title)
                                .foregroundColor(.secondary)
                        }
                        
                        // Quick adjust buttons
                        HStack(spacing: 12) {
                            QuickAdjustButton(label: "-1", action: { adjustWeight(-1) })
                            QuickAdjustButton(label: "-0.5", action: { adjustWeight(-0.5) })
                            QuickAdjustButton(label: "+0.5", action: { adjustWeight(0.5) })
                            QuickAdjustButton(label: "+1", action: { adjustWeight(1) })
                        }
                        
                        // Last weight reference
                        if weightService.currentWeight > 0 && !weightService.hasLoggedToday {
                            Button(action: {
                                weightInput = String(format: "%.1f", weightService.currentWeight)
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "clock.arrow.circlepath")
                                        .font(.caption)
                                    Text("Use last weight: \(String(format: "%.1f", weightService.currentWeight)) \(weightService.weightUnitSuffix)")
                                        .font(.subheadline)
                                }
                                .foregroundColor(.orange)
                            }
                        }
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(CornerRadius.xl)
                    
                    // Optional notes
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Notes (optional)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        TextField("Morning weigh-in, after workout, etc.", text: $notes)
                            .textFieldStyle(.roundedBorder)
                    }
                    .padding(.horizontal)
                    
                    // Tips
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "lightbulb.fill")
                                .foregroundColor(.yellow)
                            Text("Pro Tips")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                        }
                        
                        Text("• Weigh yourself at the same time daily\n• Morning, before eating, is most consistent\n• Don't stress over daily fluctuations")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.yellow.opacity(0.1))
                    .cornerRadius(CornerRadius.md)
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
            .navigationTitle("Log Weight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        saveWeight()
                    } label: {
                        if isLogging {
                            ProgressView()
                                .tint(.orange)
                        } else {
                            Text("Save")
                                .fontWeight(.bold)
                                .foregroundStyle(
                                    LinearGradient(colors: gradient, startPoint: .leading, endPoint: .trailing)
                                )
                        }
                    }
                    .disabled(weightInput.isEmpty || parsedWeight == nil || isLogging)
                }
            }
        }
        .onChange(of: autoFocus) { _, newValue in
            // Focus immediately when sheet opens
            if newValue {
                Task { @MainActor in
                    isWeightFocused = true
                }
            }
        }
        .onAppear {
            // Pre-fill with the most recent logged weight FIRST
            if let mostRecentLog = weightService.recentLogs.first {
                let recentWeight = UnitSettingsManager.shared.weightUnit == .imperial 
                    ? mostRecentLog.weightLbs 
                    : mostRecentLog.weightKg
                weightInput = String(format: "%.1f", recentWeight)
            } else if weightService.currentWeight > 0 {
                weightInput = String(format: "%.1f", weightService.currentWeight)
            }
            // Focus immediately - keyboard appears during sheet animation
            isWeightFocused = true
        }
    }
    
    private func adjustWeight(_ amount: Double) {
        HapticManager.impact(.light)
        let current = parsedWeight ?? weightService.currentWeight
        let newWeight = max(0, current + amount)
        weightInput = String(format: "%.1f", newWeight)
    }
    
    private func saveWeight() {
        guard let weight = parsedWeight, weight > 0 else { return }
        
        // Dismiss keyboard first
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        
        isLogging = true
        Task {
            let success = await weightService.logWeight(weight, notes: notes.isEmpty ? nil : notes)
            
            await MainActor.run {
                isLogging = false
                
                if success {
                    // Success feedback
                    HapticManager.notification(.success)
                    
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(0.15))
                        dismiss()
                    }
                } else {
                    // Error feedback - could add an alert here
                    HapticManager.notification(.error)
                }
            }
        }
    }
}

// MARK: - Quick Adjust Button

struct QuickAdjustButton: View {
    let label: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.orange)
                .frame(width: 56, height: 36)
                .background(Color.orange.opacity(0.15))
                .cornerRadius(CornerRadius.sm)
        }
    }
}

// MARK: - Weight Detail Chart Range

private enum ChartRange: String, CaseIterable {
    case week = "7 Days"
    case month = "30 Days"
}

// MARK: - Weight Detail View

struct WeightDetailView: View {
    @ObservedObject var weightService: WeightTrackingService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var showingGoalSheet = false
    @State private var selectedChartRange: ChartRange = .month
    @State private var cardsAppeared = false
    
    private let gradient: [Color] = [.orange, .yellow]
    
    private var insightText: String {
        let (trend, change, isOnTrack) = weightService.getWeightTrendForRecommendations()
        if let suggestion = weightService.getWorkoutAdjustmentSuggestion() {
            return suggestion
        }
        let suffix = weightService.weightUnitSuffix
        switch trend {
        case "losing":
            return "You're losing \(String(format: "%.1f", abs(change))) \(suffix)/week\(isOnTrack ? " — on track!" : "")"
        case "gaining":
            return "You're gaining \(String(format: "%.1f", abs(change))) \(suffix)/week\(isOnTrack ? " — on track!" : "")"
        default:
            return "Your weight is holding steady"
        }
    }
    
    private var insightIsPositive: Bool {
        weightService.getWeightTrendForRecommendations().isOnTrack
    }
    
    private var chartData: [WeightTrendPoint] {
        selectedChartRange == .week ? weightService.weeklyTrend : weightService.monthlyTrend
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                AnimatedOrbBackground.stats(colorScheme: colorScheme)
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: Spacing.lg) {
                        insightBanner
                            .padding(.horizontal, 20)
                            .padding(.top, 20)
                            .opacity(cardsAppeared ? 1 : 0)
                            .offset(y: cardsAppeared ? 0 : 20)
                            .animation(.easeOut(duration: 0.4), value: cardsAppeared)
                        
                        progressSummaryCard
                            .padding(.horizontal, 20)
                            .opacity(cardsAppeared ? 1 : 0)
                            .offset(y: cardsAppeared ? 0 : 20)
                            .animation(.easeOut(duration: 0.4).delay(0.1), value: cardsAppeared)
                        
                        goalCard
                            .padding(.horizontal, 20)
                            .opacity(cardsAppeared ? 1 : 0)
                            .offset(y: cardsAppeared ? 0 : 20)
                            .animation(.easeOut(duration: 0.4).delay(0.2), value: cardsAppeared)
                        
                        statisticsGrid
                            .padding(.horizontal, 20)
                            .opacity(cardsAppeared ? 1 : 0)
                            .offset(y: cardsAppeared ? 0 : 20)
                            .animation(.easeOut(duration: 0.4).delay(0.3), value: cardsAppeared)
                        
                        fullChartSection
                            .padding(.horizontal, 20)
                            .opacity(cardsAppeared ? 1 : 0)
                            .offset(y: cardsAppeared ? 0 : 20)
                            .animation(.easeOut(duration: 0.4).delay(0.4), value: cardsAppeared)
                        
                        recentEntriesSection
                            .padding(.horizontal, 20)
                            .padding(.bottom, 40)
                            .opacity(cardsAppeared ? 1 : 0)
                            .offset(y: cardsAppeared ? 0 : 20)
                            .animation(.easeOut(duration: 0.4).delay(0.5), value: cardsAppeared)
                    }
                }
            }
            .navigationTitle("Weight Tracker")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.orange)
                    .accessibilityLabel("Done")
                    .accessibilityHint("Dismiss weight tracker detail")
                }
            }
            .sheet(isPresented: $showingGoalSheet) {
                SetWeightGoalSheet(weightService: weightService)
            }
            .onAppear {
                Task {
                    try? await Task.sleep(for: .milliseconds(100))
                    cardsAppeared = true
                }
            }
        }
    }
    
    // MARK: - Insight Banner
    private var insightBanner: some View {
        HStack(spacing: Spacing.sm) {
            let accentColor: Color = insightIsPositive ? .green : .orange
            let iconName = insightIsPositive ? "brain.head.profile" : "lightbulb.fill"
            
            ZStack {
                Circle()
                    .fill(accentColor.opacity(0.15))
                    .frame(width: 40, height: 40)
                
                Image(systemName: iconName)
                    .font(.ds_labelLarge)
                    .foregroundColor(accentColor)
            }
            .accessibilityHidden(true)
            
            Text(insightText)
                .font(.ds_labelLarge)
                .foregroundColor(.white)
                .lineLimit(2)
            
            Spacer()
        }
        .padding(Spacing.lg)
        .background(Color.cardBackground)
        .cornerRadius(CornerRadius.xl)
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.xl)
                .stroke(
                    (insightIsPositive ? Color.green : Color.orange).opacity(0.25),
                    lineWidth: 1
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Weight insight: \(insightText)")
    }
    
    // MARK: - Progress Summary Card
    private var progressSummaryCard: some View {
        VStack(spacing: 16) {
            VStack(spacing: 4) {
                Text("Current Weight")
                    .font(.ds_labelLarge)
                    .foregroundColor(.gray)
                
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(String(format: "%.1f", weightService.currentWeight))
                        .font(.ds_displayMedium)
                        .fontDesign(.rounded)
                        .foregroundColor(.white)
                    
                    Text(weightService.weightUnitSuffix)
                        .font(.ds_heading2)
                        .foregroundColor(.gray)
                }
            }
            
            HStack(spacing: 24) {
                DarkChangeIndicator(
                    title: "This Week",
                    change: weightService.weeklyChange,
                    suffix: weightService.weightUnitSuffix
                )
                
                Divider()
                    .frame(height: 40)
                    .background(Color.gray.opacity(0.3))
                
                DarkChangeIndicator(
                    title: "This Month",
                    change: weightService.monthlyChange,
                    suffix: weightService.weightUnitSuffix
                )
                
                if let stats = weightService.statistics {
                    Divider()
                        .frame(height: 40)
                        .background(Color.gray.opacity(0.3))
                    
                    DarkChangeIndicator(
                        title: "Total",
                        change: stats.totalChange,
                        suffix: weightService.weightUnitSuffix
                    )
                }
            }
        }
        .padding(Spacing.lg)
        .background(Color.cardBackground)
        .cornerRadius(CornerRadius.xl)
    }
    
    // MARK: - Goal Card
    private var goalCard: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Your Goal")
                    .font(.ds_heading3)
                    .foregroundColor(.white)
                
                Spacer()
                
                Button(action: { showingGoalSheet = true }) {
                    Text(weightService.weightGoal == nil ? "Set Goal" : "Edit")
                        .font(.ds_labelLarge)
                        .foregroundColor(.orange)
                }
                .accessibilityLabel(weightService.weightGoal == nil ? "Set Goal" : "Edit Goal")
                .accessibilityHint("Opens goal configuration")
            }
            
            if let goal = weightService.weightGoal {
                HStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(goal.goalType.color.opacity(0.2))
                            .frame(width: 50, height: 50)
                        
                        Image(systemName: goal.goalType.icon)
                            .font(.ds_heading2)
                            .foregroundColor(goal.goalType.color)
                    }
                    .accessibilityHidden(true)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(goal.goalType.displayName)
                            .font(.ds_labelLarge)
                            .foregroundColor(.gray)
                        
                        Text("\(String(format: "%.1f", goal.targetWeight)) \(weightService.weightUnitSuffix)")
                            .font(.ds_heading3)
                            .foregroundColor(.white)
                        
                        if let estDate = weightService.estimatedGoalDate {
                            Text("Est. arrival: \(estDate, format: .dateTime.month(.abbreviated).day().year())")
                                .font(.ds_caption)
                                .foregroundColor(.orange)
                        }
                    }
                    
                    Spacer()
                    
                    ZStack {
                        Circle()
                            .stroke(Color.gray.opacity(0.3), lineWidth: 6)
                        
                        Circle()
                            .trim(from: 0, to: weightService.goalProgress)
                            .stroke(
                                LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing),
                                style: StrokeStyle(lineWidth: 6, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                        
                        Text("\(Int(weightService.goalProgress * 100))%")
                            .font(.ds_caption)
                            .fontWeight(.bold)
                            .fontDesign(.rounded)
                            .foregroundColor(.white)
                    }
                    .frame(width: 50, height: 50)
                    .accessibilityLabel("\(Int(weightService.goalProgress * 100)) percent complete")
                }
            } else {
                HStack {
                    Image(systemName: "target")
                        .font(.ds_heading2)
                        .foregroundColor(.gray)
                        .accessibilityHidden(true)
                    
                    Text("Set a weight goal to track your progress")
                        .font(.ds_labelLarge)
                        .foregroundColor(.gray)
                    
                    Spacer()
                }
            }
        }
        .padding(Spacing.lg)
        .background(Color.cardBackground)
        .cornerRadius(CornerRadius.xl)
    }
    
    // MARK: - Statistics Grid
    private var statisticsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Spacing.sm) {
            DarkWeightStatBox(
                title: "Starting",
                value: String(format: "%.1f", weightService.statistics?.startingWeight ?? 0),
                unit: weightService.weightUnitSuffix,
                icon: "flag.fill",
                color: .blue
            )
            
            DarkWeightStatBox(
                title: "Lowest",
                value: String(format: "%.1f", weightService.statistics?.lowestWeight ?? 0),
                unit: weightService.weightUnitSuffix,
                icon: "arrow.down.circle.fill",
                color: .green
            )
            
            DarkWeightStatBox(
                title: "Highest",
                value: String(format: "%.1f", weightService.statistics?.highestWeight ?? 0),
                unit: weightService.weightUnitSuffix,
                icon: "arrow.up.circle.fill",
                color: .red
            )
            
            DarkWeightStatBox(
                title: "Entries",
                value: "\(weightService.statistics?.totalEntries ?? 0)",
                unit: "logs",
                icon: "list.bullet",
                color: .purple
            )
            
            DarkWeightStatBox(
                title: "Streak",
                value: "\(weightService.statistics?.streakDays ?? 0)",
                unit: "days",
                icon: "flame.fill",
                color: .orange
            )
            
            DarkWeightStatBox(
                title: "Average",
                value: String(format: "%.1f", weightService.statistics?.averageWeight ?? 0),
                unit: weightService.weightUnitSuffix,
                icon: "chart.bar.fill",
                color: .cyan
            )
        }
    }
    
    // MARK: - Full Chart Section
    private var fullChartSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(selectedChartRange == .week ? "7-Day Trend" : "30-Day Trend")
                    .font(.ds_heading3)
                    .foregroundColor(.white)
                
                Spacer()
                
                Picker("Chart Range", selection: $selectedChartRange) {
                    ForEach(ChartRange.allCases, id: \.self) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 160)
                .accessibilityLabel("Chart time range")
                .accessibilityHint("Switch between 7-day and 30-day views")
            }
            
            if chartData.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.ds_displayMedium)
                        .foregroundColor(.gray.opacity(0.5))
                        .accessibilityHidden(true)
                    
                    Text("Start logging to see your trend")
                        .font(.ds_labelLarge)
                        .foregroundColor(.gray)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 200)
            } else {
                DetailedWeightChart(
                    data: chartData,
                    usesLbs: weightService.usesLbs
                )
                .frame(height: 200)
            }
        }
        .padding(Spacing.lg)
        .background(Color.cardBackground)
        .cornerRadius(CornerRadius.xl)
    }
    
    // MARK: - Recent Entries Section
    private var recentEntriesSection: some View {
        let logs = Array(weightService.recentLogs.prefix(10))
        return VStack(alignment: .leading, spacing: 16) {
            Text("Recent Entries")
                .font(.ds_heading3)
                .foregroundColor(.white)
            
            if logs.isEmpty {
                Text("No entries yet")
                    .font(.ds_labelLarge)
                    .foregroundColor(.gray)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else {
                VStack(spacing: 12) {
                    ForEach(Array(logs.enumerated()), id: \.element.id) { index, log in
                        let previousLog = index + 1 < logs.count ? logs[index + 1] : nil
                        DarkWeightEntryRow(
                            log: log,
                            usesLbs: weightService.usesLbs,
                            previousLog: previousLog,
                            onDelete: {
                                Task { await weightService.deleteLog(log) }
                            }
                        )
                        
                        if index < logs.count - 1 {
                            Divider()
                                .background(Color.gray.opacity(0.3))
                        }
                    }
                }
            }
        }
        .padding(Spacing.lg)
        .background(Color.cardBackground)
        .cornerRadius(CornerRadius.xl)
    }
}

// MARK: - Change Indicator

struct ChangeIndicator: View {
    let title: String
    let change: Double
    let suffix: String
    
    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            
            HStack(spacing: 4) {
                Image(systemName: change >= 0 ? "arrow.up" : "arrow.down")
                    .font(.caption)
                
                Text(String(format: "%+.1f %@", change, suffix))
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            .foregroundColor(change >= 0 ? .orange : .green)
        }
    }
}

// MARK: - Dark Change Indicator (for dark detail view)

struct DarkChangeIndicator: View {
    let title: String
    let change: Double
    let suffix: String
    
    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.ds_caption)
                .foregroundColor(.gray)
            
            HStack(spacing: 4) {
                Image(systemName: change >= 0 ? "arrow.up" : "arrow.down")
                    .font(.ds_caption)
                
                Text(String(format: "%+.1f %@", change, suffix))
                    .font(.ds_labelLarge)
            }
            .foregroundColor(change >= 0 ? .orange : .green)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(String(format: "%+.1f", change)) \(suffix)")
    }
}

// MARK: - Dark Weight Stat Box (for dark detail view)

struct DarkWeightStatBox: View {
    let title: String
    let value: String
    let unit: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.ds_heading2)
                .foregroundColor(color)
                .accessibilityHidden(true)
            
            Text(value)
                .font(.ds_heading2)
                .foregroundColor(.white)
            
            Text(unit)
                .font(.ds_caption)
                .foregroundColor(.gray)
            
            Text(title)
                .font(.ds_caption)
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.cardBackground)
        .cornerRadius(CornerRadius.md)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value) \(unit)")
    }
}

// MARK: - Dark Weight Entry Row (for dark detail view)

struct DarkWeightEntryRow: View {
    let log: WeightLog
    let usesLbs: Bool
    let previousLog: WeightLog?
    let onDelete: () -> Void
    
    private var weight: Double {
        usesLbs ? log.weightLbs : log.weightKg
    }
    
    private var suffix: String {
        usesLbs ? "lbs" : "kg"
    }
    
    private var delta: Double? {
        guard let prev = previousLog else { return nil }
        let prevWeight = usesLbs ? prev.weightLbs : prev.weightKg
        let diff = weight - prevWeight
        return diff == 0 ? nil : diff
    }
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(formatDate(log.loggedAt))
                    .font(.ds_labelLarge)
                    .foregroundColor(.white)
                
                if let notes = log.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.ds_caption)
                        .foregroundColor(.gray)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            if let delta = delta {
                HStack(spacing: 2) {
                    Image(systemName: delta > 0 ? "arrow.up" : "arrow.down")
                        .font(.ds_caption)
                    Text(String(format: "%.1f", abs(delta)))
                        .font(.ds_caption)
                        .fontWeight(.semibold)
                }
                .foregroundColor(delta > 0 ? .orange : .green)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background((delta > 0 ? Color.orange : Color.green).opacity(0.15))
                .cornerRadius(CornerRadius.sm)
                .accessibilityLabel(delta > 0 ? "Up \(String(format: "%.1f", abs(delta)))" : "Down \(String(format: "%.1f", abs(delta)))")
            }
            
            Text("\(String(format: "%.1f", weight)) \(suffix)")
                .font(.ds_heading3)
                .foregroundColor(.orange)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(formatDate(log.loggedAt)): \(String(format: "%.1f", weight)) \(suffix)")
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Weight Stat Box

struct WeightStatBox: View {
    let title: String
    let value: String
    let unit: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
            
            Text(unit)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.tertiarySystemBackground))
        .cornerRadius(14)
    }
}

// MARK: - Detailed Weight Chart

struct DetailedWeightChart: View {
    let data: [WeightTrendPoint]
    let usesLbs: Bool
    
    @State private var animateChart = false
    
    var body: some View {
        GeometryReader { geometry in
            let weights = data.map { $0.weight }
            let minWeight = (weights.min() ?? 0) - 2
            let maxWeight = (weights.max() ?? 0) + 2
            let range = max(maxWeight - minWeight, 1)
            
            ZStack {
                VStack {
                    Text(String(format: "%.0f", maxWeight))
                        .font(.ds_caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(String(format: "%.0f", (maxWeight + minWeight) / 2))
                        .font(.ds_caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(String(format: "%.0f", minWeight))
                        .font(.ds_caption)
                        .foregroundColor(.secondary)
                }
                .frame(width: 35)
                .frame(maxWidth: .infinity, alignment: .leading)
                
                HStack(spacing: 0) {
                    Spacer()
                        .frame(width: 40)
                    
                    ZStack {
                        VStack(spacing: 0) {
                            ForEach(0..<5, id: \.self) { _ in
                                Divider().opacity(0.2)
                                Spacer()
                            }
                            Divider().opacity(0.2)
                        }
                        
                        if data.count > 1 {
                            Path { path in
                                let chartWidth = geometry.size.width - 40
                                path.move(to: CGPoint(x: 0, y: geometry.size.height))
                                for (index, point) in data.enumerated() {
                                    let x = chartWidth * CGFloat(index) / CGFloat(data.count - 1)
                                    let y = geometry.size.height * (1 - CGFloat((point.weight - minWeight) / range))
                                    path.addLine(to: CGPoint(x: x, y: y))
                                }
                                path.addLine(to: CGPoint(x: geometry.size.width - 40, y: geometry.size.height))
                                path.closeSubpath()
                            }
                            .fill(
                                LinearGradient(
                                    colors: [Color.orange.opacity(0.4), Color.orange.opacity(0.1)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            
                            Path { path in
                                let chartWidth = geometry.size.width - 40
                                for (index, point) in data.enumerated() {
                                    let x = chartWidth * CGFloat(index) / CGFloat(data.count - 1)
                                    let y = geometry.size.height * (1 - CGFloat((point.weight - minWeight) / range))
                                    if index == 0 {
                                        path.move(to: CGPoint(x: x, y: y))
                                    } else {
                                        path.addLine(to: CGPoint(x: x, y: y))
                                    }
                                }
                            }
                            .trim(from: 0, to: animateChart ? 1 : 0)
                            .stroke(
                                LinearGradient(colors: [.orange, .yellow], startPoint: .leading, endPoint: .trailing),
                                style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
                            )
                            
                            ForEach(Array(data.enumerated()), id: \.offset) { index, point in
                                let chartWidth = geometry.size.width - 40
                                let x = chartWidth * CGFloat(index) / CGFloat(data.count - 1)
                                let y = geometry.size.height * (1 - CGFloat((point.weight - minWeight) / range))
                                
                                Circle()
                                    .fill(Color.white)
                                    .frame(width: 8, height: 8)
                                    .overlay(
                                        Circle()
                                            .fill(Color.orange)
                                            .frame(width: 5, height: 5)
                                    )
                                    .shadow(color: .orange.opacity(0.3), radius: 2)
                                    .position(x: x, y: y)
                                    .opacity(animateChart ? 1 : 0)
                            }
                        }
                    }
                }
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.0)) {
                animateChart = true
            }
        }
        .accessibilityLabel("Weight trend chart with \(data.count) data points")
    }
}

// MARK: - Weight Entry Row

struct WeightEntryRow: View {
    let log: WeightLog
    let usesLbs: Bool
    let onDelete: () -> Void
    
    private var weight: Double {
        usesLbs ? log.weightLbs : log.weightKg
    }
    
    private var suffix: String {
        usesLbs ? "lbs" : "kg"
    }
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(formatDate(log.loggedAt))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                if let notes = log.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            Text("\(String(format: "%.1f", weight)) \(suffix)")
                .font(.headline)
                .fontWeight(.semibold)
        }
        .padding(.vertical, Spacing.xs)
        .padding(.horizontal, Spacing.sm)
        .background(Color(.tertiarySystemBackground))
        .cornerRadius(10)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Set Weight Goal Sheet

struct SetWeightGoalSheet: View {
    @ObservedObject var weightService: WeightTrackingService
    @Environment(\.dismiss) private var dismiss
    
    @State private var targetWeight: String = ""
    @State private var goalType: WeightGoal.GoalType = .lose
    @State private var hasTargetDate = false
    @State private var targetDate = Date().addingTimeInterval(30 * 24 * 60 * 60) // 30 days
    
    // Parse weight handling both period and comma as decimal separator
    private var parsedTargetWeight: Double? {
        let normalized = targetWeight.replacingOccurrences(of: ",", with: ".")
        return Double(normalized)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Goal Type") {
                    Picker("I want to", selection: $goalType) {
                        ForEach(WeightGoal.GoalType.allCases, id: \.self) { type in
                            HStack {
                                Image(systemName: type.icon)
                                    .foregroundColor(type.color)
                                Text(type.displayName)
                            }
                            .tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                
                Section("Target Weight") {
                    HStack {
                        TextField("Target", text: $targetWeight)
                            .keyboardType(.decimalPad)
                            .font(.title2)
                        
                        Text(weightService.weightUnitSuffix)
                            .foregroundColor(.secondary)
                    }
                    
                    if weightService.currentWeight > 0 {
                        Text("Current: \(String(format: "%.1f", weightService.currentWeight)) \(weightService.weightUnitSuffix)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Section("Target Date (Optional)") {
                    Toggle("Set target date", isOn: $hasTargetDate)
                    
                    if hasTargetDate {
                        DatePicker("Reach goal by", selection: $targetDate, displayedComponents: .date)
                    }
                }
            }
            .navigationTitle("Set Weight Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveGoal()
                    }
                    .fontWeight(.semibold)
                    .disabled(targetWeight.isEmpty || parsedTargetWeight == nil)
                }
            }
            .onAppear {
                if let goal = weightService.weightGoal {
                    targetWeight = String(format: "%.1f", goal.targetWeight)
                    goalType = goal.goalType
                    if let date = goal.targetDate {
                        hasTargetDate = true
                        targetDate = date
                    }
                }
            }
        }
    }
    
    private func saveGoal() {
        guard let weight = parsedTargetWeight else { return }
        
        Task {
            await weightService.setWeightGoal(
                targetWeight: weight,
                targetDate: hasTargetDate ? targetDate : nil,
                goalType: goalType
            )
            dismiss()
        }
    }
}

// MARK: - Preview

#Preview {
    WeightTrackerWidget()
        .padding()
}
