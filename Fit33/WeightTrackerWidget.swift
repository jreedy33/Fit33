import SwiftUI
import CoreData

// MARK: - Weight Tracker Widget (Carousel with Graph)

struct WeightTrackerWidget: View {
    @StateObject private var weightService = WeightTrackingService.shared
    @StateObject private var premiumManager = PremiumManager.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var showingAddSheet = false
    @State private var showingDetailView = false
    @State private var currentPage = 0
    @State private var showingPremiumUpgrade = false
    
    // Theme colors
    private let primaryColor = Color.orange
    private let gradient: [Color] = [.orange, .yellow]
    
    var body: some View {
        Group {
            if premiumManager.isPremiumUser {
                // Premium user - show full widget
                actualWidget
            } else {
                // Free user - show locked state with visible preview
                lockedWidget
            }
        }
        .sheet(isPresented: $showingPremiumUpgrade) {
            PremiumUpgradeView(triggeringFeature: .weightTracking)
        }
        .sheet(isPresented: $showingAddSheet) {
            LogWeightSheet(weightService: weightService)
        }
        .sheet(isPresented: $showingDetailView) {
            WeightDetailView(weightService: weightService)
        }
    }
    
    // MARK: - Actual Widget Content
    private var actualWidget: some View {
        VStack(spacing: 0) {
            // Header row
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "scalemass.fill")
                        .font(.title3)
                        .foregroundStyle(
                            LinearGradient(colors: gradient, startPoint: .top, endPoint: .bottom)
                        )
                    
                    Text("Weight Tracker")
                        .font(.headline)
                        .fontWeight(.bold)
                }
                
                Spacer()
                
                Button(action: { HapticManager.selectionChanged(); showingDetailView = true }) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.subheadline)
                        .foregroundColor(primaryColor.opacity(0.8))
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 12)
            
            // Swipeable carousel
            TabView(selection: $currentPage) {
                // Page 1: Weight Entry Card
                weightEntryCard
                    .tag(0)
                
                // Page 2: Line Graph Card
                weightGraphCard
                    .tag(1)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 165)
            
            // Page indicators
            HStack(spacing: 8) {
                ForEach(0..<2, id: \.self) { index in
                    Circle()
                        .fill(currentPage == index ? Color.orange : Color.gray.opacity(0.3))
                        .frame(width: 8, height: 8)
                        .animation(.easeInOut(duration: 0.2), value: currentPage)
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(colorScheme == .dark ? Color(white: 0.12) : Color(white: 0.97))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            primaryColor.opacity(colorScheme == .dark ? 0.4 : 0.25),
                            primaryColor.opacity(colorScheme == .dark ? 0.2 : 0.1)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
        )
    }
    
    // MARK: - Locked Widget for Free Users
    private var lockedWidget: some View {
        ZStack {
            // Show the actual widget content (non-interactive)
            VStack(spacing: 0) {
                // Header row
                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: "scalemass.fill")
                            .font(.title3)
                            .foregroundStyle(
                                LinearGradient(colors: gradient, startPoint: .top, endPoint: .bottom)
                            )
                        
                        Text("Weight Tracker")
                            .font(.headline)
                            .fontWeight(.bold)
                    }
                    
                    Spacer()
                    
                    // PRO badge
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 10))
                        Text("PRO")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(LinearGradient(
                                colors: [Color.blue, Color.purple],
                                startPoint: .leading,
                                endPoint: .trailing
                            ))
                    )
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 12)
                
                // Show preview of actual content (slightly blurred)
                TabView(selection: .constant(0)) {
                    weightEntryCard
                        .tag(0)
                        .allowsHitTesting(false) // Disable interaction
                    
                    weightGraphCard
                        .tag(1)
                        .allowsHitTesting(false) // Disable interaction
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(height: 165)
                .blur(radius: 2) // Subtle blur
                .opacity(0.6) // Dimmed
                
                // Page indicators
                HStack(spacing: 8) {
                    ForEach(0..<2, id: \.self) { index in
                        Circle()
                            .fill(index == 0 ? Color.orange : Color.gray.opacity(0.3))
                            .frame(width: 8, height: 8)
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 16)
            }
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(colorScheme == .dark ? Color(white: 0.12) : Color(white: 0.97))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.blue.opacity(0.4),
                                Color.purple.opacity(0.3)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 2
                    )
            )
            
            // Lock overlay on top
            Button(action: {
                HapticManager.tap()
                showingPremiumUpgrade = true
            }) {
                ZStack {
                    // Semi-transparent overlay
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color.black.opacity(0.3))
                    
                    // Lock icon and message
                    VStack(spacing: 12) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.blue, .purple],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        
                        Text("Tap to Unlock")
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                    }
                }
            }
            .buttonStyle(PlainButtonStyle())
        }
    }
    
    // MARK: - Weight Entry Card
    private var weightEntryCard: some View {
        VStack(spacing: 16) {
            // Main content row
            HStack(alignment: .center, spacing: 16) {
                // Weight display
                VStack(alignment: .leading, spacing: 6) {
                    if weightService.hasLoggedToday {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(formatWeight(weightService.currentWeight))
                                .font(.system(size: 42, weight: .bold, design: .rounded))
                                .foregroundStyle(
                                    LinearGradient(colors: gradient, startPoint: .leading, endPoint: .trailing)
                                )
                            
                            Text(weightService.weightUnitSuffix)
                                .font(.title3)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)
                        }
                        
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.green)
                            Text("Logged today")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.green)
                        }
                    } else {
                        Text("Log Today's Weight")
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                        
                        if weightService.currentWeight > 0 {
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text("Last:")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Text("\(formatWeight(weightService.currentWeight))")
                                    .font(.system(size: 24, weight: .bold, design: .rounded))
                                    .foregroundStyle(
                                        LinearGradient(colors: gradient, startPoint: .leading, endPoint: .trailing)
                                    )
                                Text(weightService.weightUnitSuffix)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                
                Spacer()
                
                // Log button - bigger
                Button(action: { HapticManager.impact(.medium); showingAddSheet = true }) {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 56, height: 56)
                            .shadow(color: .orange.opacity(0.4), radius: 8, y: 4)
                        
                        Image(systemName: weightService.hasLoggedToday ? "pencil" : "plus")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                .buttonStyle(ScaleButtonStyle())
            }
            .padding(.horizontal, 20)
            
            // Stats row - bigger
            HStack(spacing: 0) {
                // Weekly change
                HStack(spacing: 6) {
                    Image(systemName: weightService.weeklyChange >= 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(weeklyChangeColor)
                    
                    Text(formatWeightChange(weightService.weeklyChange))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(weeklyChangeColor)
                }
                .frame(maxWidth: .infinity)
                
                Rectangle()
                    .fill(Color.gray.opacity(0.25))
                    .frame(width: 1, height: 28)
                
                // Streak
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.orange)
                    
                    Text("\(weightService.statistics?.streakDays ?? 0) days")
                        .font(.system(size: 15, weight: .bold))
                }
                .frame(maxWidth: .infinity)
                
                // Goal (if set)
                if let goal = weightService.weightGoal {
                    Rectangle()
                        .fill(Color.gray.opacity(0.25))
                        .frame(width: 1, height: 28)
                    
                    HStack(spacing: 6) {
                        Image(systemName: "target")
                            .font(.system(size: 14))
                            .foregroundColor(goal.goalType.color)
                        
                        Text("\(formatWeight(goal.targetWeight))")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(goal.goalType.color)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 20)
        }
    }
    
    // MARK: - Weight Graph Card
    private var weightGraphCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Graph header
            HStack {
                Text("7-Day Trend")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if !weightService.monthlyTrend.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: weightService.weeklyChange >= 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(.caption)
                        Text(formatWeightChange(weightService.weeklyChange))
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(weeklyChangeColor)
                }
            }
            .padding(.horizontal, 20)
            
            // Mini chart
            if weightService.monthlyTrend.count >= 2 {
                MiniWeightChart(
                    data: Array(weightService.monthlyTrend.suffix(7)),
                    usesLbs: weightService.usesLbs
                )
                .frame(height: 100)
                .padding(.horizontal, 16)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary.opacity(0.4))
                    
                    Text("Log more weights to see your trend")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 100)
            }
            
            // Quick stats below chart
            if !weightService.monthlyTrend.isEmpty {
                HStack(spacing: 16) {
                    Spacer()
                    MiniStatBadge(
                        title: "Low",
                        value: String(format: "%.1f", weightService.monthlyTrend.suffix(7).map { $0.weight }.min() ?? 0),
                        color: .green
                    )
                    MiniStatBadge(
                        title: "High",
                        value: String(format: "%.1f", weightService.monthlyTrend.suffix(7).map { $0.weight }.max() ?? 0),
                        color: .orange
                    )
                    MiniStatBadge(
                        title: "Avg",
                        value: String(format: "%.1f", weightService.monthlyTrend.suffix(7).map { $0.weight }.reduce(0, +) / Double(min(7, weightService.monthlyTrend.count))),
                        color: .blue
                    )
                    Spacer()
                }
                .padding(.horizontal, 20)
            }
        }
        .padding(.top, 4)
    }
    
    // MARK: - Helpers
    
    private var weeklyChangeColor: Color {
        guard let goal = weightService.weightGoal else {
            return weightService.weeklyChange >= 0 ? .orange : .green
        }
        
        switch goal.goalType {
        case .lose:
            return weightService.weeklyChange <= 0 ? .green : .orange
        case .gain:
            return weightService.weeklyChange >= 0 ? .green : .orange
        case .maintain:
            return abs(weightService.weeklyChange) < 1 ? .green : .orange
        }
    }
    
    private func formatWeight(_ weight: Double) -> String {
        if weight == 0 { return "--" }
        return String(format: "%.1f", weight)
    }
    
    private func formatWeightChange(_ change: Double) -> String {
        let sign = change >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.1f", change)) \(weightService.weightUnitSuffix)"
    }
}

// MARK: - Mini Weight Chart (for carousel)

struct MiniWeightChart: View {
    let data: [WeightTrendPoint]
    let usesLbs: Bool
    
    @State private var animateChart = false
    
    var body: some View {
        GeometryReader { geometry in
            let weights = data.map { $0.weight }
            let minWeight = (weights.min() ?? 0) - 1
            let maxWeight = (weights.max() ?? 0) + 1
            let range = max(maxWeight - minWeight, 1)
            
            ZStack {
                // Area fill
                if data.count > 1 {
                    Path { path in
                        let chartWidth = geometry.size.width
                        
                        path.move(to: CGPoint(x: 0, y: geometry.size.height))
                        
                        for (index, point) in data.enumerated() {
                            let x = chartWidth * CGFloat(index) / CGFloat(data.count - 1)
                            let y = geometry.size.height * (1 - CGFloat((point.weight - minWeight) / range))
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                        
                        path.addLine(to: CGPoint(x: geometry.size.width, y: geometry.size.height))
                        path.closeSubpath()
                    }
                    .fill(
                        LinearGradient(
                            colors: [Color.orange.opacity(0.35), Color.orange.opacity(0.05)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    
                    // Line
                    Path { path in
                        for (index, point) in data.enumerated() {
                            let x = geometry.size.width * CGFloat(index) / CGFloat(data.count - 1)
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
                    
                    // Data points
                    ForEach(Array(data.enumerated()), id: \.offset) { index, point in
                        let x = geometry.size.width * CGFloat(index) / CGFloat(data.count - 1)
                        let y = geometry.size.height * (1 - CGFloat((point.weight - minWeight) / range))
                        
                        let isLast = index == data.count - 1
                        
                        Circle()
                            .fill(Color.white)
                            .frame(width: isLast ? 12 : 8, height: isLast ? 12 : 8)
                            .overlay(
                                Circle()
                                    .fill(
                                        LinearGradient(colors: [.orange, .yellow], startPoint: .topLeading, endPoint: .bottomTrailing)
                                    )
                                    .frame(width: isLast ? 8 : 5, height: isLast ? 8 : 5)
                            )
                            .shadow(color: .orange.opacity(0.4), radius: isLast ? 4 : 2)
                            .position(x: x, y: y)
                            .opacity(animateChart ? 1 : 0)
                    }
                }
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.8)) {
                animateChart = true
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
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(color)
            Text(title)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Trend Stat Badge

struct TrendStatBadge: View {
    let icon: String
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(color)
            
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .rounded))
            
            Text(title)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Log Weight Sheet

struct LogWeightSheet: View {
    @ObservedObject var weightService: WeightTrackingService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var weightInput: String = ""
    @State private var notes: String = ""
    @State private var isLogging = false
    @FocusState private var isWeightFocused: Bool
    
    private let gradient: [Color] = [.orange, .yellow]
    
    // Parse weight handling both period and comma as decimal separator
    private var parsedWeight: Double? {
        // Replace comma with period to handle European locales
        let normalized = weightInput.replacingOccurrences(of: ",", with: ".")
        return Double(normalized)
    }
    
    var body: some View {
        NavigationView {
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
                    .cornerRadius(16)
                    
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
                    .cornerRadius(12)
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
                                .fontWeight(.semibold)
                        }
                    }
                    .foregroundColor(.orange)
                    .disabled(weightInput.isEmpty || parsedWeight == nil || isLogging)
                }
            }
        }
        .onAppear {
            isWeightFocused = true
            // Pre-fill with the most recent logged weight
            // This ensures tomorrow's default is today's input
            if let mostRecentLog = weightService.recentLogs.first {
                let recentWeight = UnitSettingsManager.shared.weightUnit == .imperial 
                    ? mostRecentLog.weightLbs 
                    : mostRecentLog.weightKg
                weightInput = String(format: "%.1f", recentWeight)
            } else if weightService.currentWeight > 0 {
                // Fallback to current weight from service
                weightInput = String(format: "%.1f", weightService.currentWeight)
            }
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
                    
                    // Small delay to ensure UI updates before dismiss
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
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
                .cornerRadius(8)
        }
    }
}

// MARK: - Weight Detail View

struct WeightDetailView: View {
    @ObservedObject var weightService: WeightTrackingService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var showingGoalSheet = false
    
    private let gradient: [Color] = [.orange, .yellow]
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Progress summary card
                    progressSummaryCard
                    
                    // Goal card
                    goalCard
                    
                    // Statistics grid
                    statisticsGrid
                    
                    // Full chart
                    fullChartSection
                    
                    // Recent entries
                    recentEntriesSection
                }
                .padding()
            }
            .background(
                LinearGradient(
                    colors: colorScheme == .dark
                        ? [Color.orange.opacity(0.1), Color.yellow.opacity(0.05)]
                        : [Color.orange.opacity(0.15), Color.yellow.opacity(0.08)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            )
            .navigationTitle("Weight Tracker")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingGoalSheet) {
                SetWeightGoalSheet(weightService: weightService)
            }
        }
    }
    
    // MARK: - Progress Summary Card
    private var progressSummaryCard: some View {
        VStack(spacing: 16) {
            // Current weight large display
            VStack(spacing: 4) {
                Text("Current Weight")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(String(format: "%.1f", weightService.currentWeight))
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                    
                    Text(weightService.weightUnitSuffix)
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
            }
            
            // Change indicators
            HStack(spacing: 24) {
                ChangeIndicator(
                    title: "This Week",
                    change: weightService.weeklyChange,
                    suffix: weightService.weightUnitSuffix
                )
                
                Divider()
                    .frame(height: 40)
                
                ChangeIndicator(
                    title: "This Month",
                    change: weightService.monthlyChange,
                    suffix: weightService.weightUnitSuffix
                )
                
                if let stats = weightService.statistics {
                    Divider()
                        .frame(height: 40)
                    
                    ChangeIndicator(
                        title: "Total",
                        change: stats.totalChange,
                        suffix: weightService.weightUnitSuffix
                    )
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(20)
    }
    
    // MARK: - Goal Card
    private var goalCard: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Your Goal")
                    .font(.headline)
                    .fontWeight(.bold)
                
                Spacer()
                
                Button(action: { showingGoalSheet = true }) {
                    Text(weightService.weightGoal == nil ? "Set Goal" : "Edit")
                        .font(.subheadline)
                        .foregroundColor(.orange)
                }
            }
            
            if let goal = weightService.weightGoal {
                HStack(spacing: 16) {
                    // Goal type icon
                    ZStack {
                        Circle()
                            .fill(goal.goalType.color.opacity(0.15))
                            .frame(width: 50, height: 50)
                        
                        Image(systemName: goal.goalType.icon)
                            .font(.title2)
                            .foregroundColor(goal.goalType.color)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(goal.goalType.displayName)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Text("\(String(format: "%.1f", goal.targetWeight)) \(weightService.weightUnitSuffix)")
                            .font(.title3)
                            .fontWeight(.bold)
                    }
                    
                    Spacer()
                    
                    // Progress ring
                    ZStack {
                        Circle()
                            .stroke(Color.gray.opacity(0.2), lineWidth: 6)
                        
                        Circle()
                            .trim(from: 0, to: weightService.goalProgress)
                            .stroke(
                                LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing),
                                style: StrokeStyle(lineWidth: 6, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                        
                        Text("\(Int(weightService.goalProgress * 100))%")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                    }
                    .frame(width: 50, height: 50)
                }
            } else {
                HStack {
                    Image(systemName: "target")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    
                    Text("Set a weight goal to track your progress")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(20)
    }
    
    // MARK: - Statistics Grid
    private var statisticsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            WeightStatBox(
                title: "Starting",
                value: String(format: "%.1f", weightService.statistics?.startingWeight ?? 0),
                unit: weightService.weightUnitSuffix,
                icon: "flag.fill",
                color: .blue
            )
            
            WeightStatBox(
                title: "Lowest",
                value: String(format: "%.1f", weightService.statistics?.lowestWeight ?? 0),
                unit: weightService.weightUnitSuffix,
                icon: "arrow.down.circle.fill",
                color: .green
            )
            
            WeightStatBox(
                title: "Highest",
                value: String(format: "%.1f", weightService.statistics?.highestWeight ?? 0),
                unit: weightService.weightUnitSuffix,
                icon: "arrow.up.circle.fill",
                color: .red
            )
            
            WeightStatBox(
                title: "Entries",
                value: "\(weightService.statistics?.totalEntries ?? 0)",
                unit: "logs",
                icon: "list.bullet",
                color: .purple
            )
        }
    }
    
    // MARK: - Full Chart Section
    private var fullChartSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("30-Day Trend")
                .font(.headline)
                .fontWeight(.bold)
            
            if weightService.monthlyTrend.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary.opacity(0.5))
                    
                    Text("Start logging to see your trend")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 200)
                .background(Color(.tertiarySystemBackground))
                .cornerRadius(16)
            } else {
                DetailedWeightChart(
                    data: weightService.monthlyTrend,
                    usesLbs: weightService.usesLbs
                )
                .frame(height: 200)
                .padding()
                .background(Color(.tertiarySystemBackground))
                .cornerRadius(16)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(20)
    }
    
    // MARK: - Recent Entries Section
    private var recentEntriesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Entries")
                .font(.headline)
                .fontWeight(.bold)
            
            if weightService.recentLogs.isEmpty {
                Text("No entries yet")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
            } else {
                ForEach(weightService.recentLogs.prefix(10)) { log in
                    WeightEntryRow(
                        log: log,
                        usesLbs: weightService.usesLbs,
                        onDelete: {
                            Task { await weightService.deleteLog(log) }
                        }
                    )
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(20)
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
                // Y-axis labels
                VStack {
                    Text(String(format: "%.0f", maxWeight))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(String(format: "%.0f", (maxWeight + minWeight) / 2))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(String(format: "%.0f", minWeight))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .frame(width: 35)
                .frame(maxWidth: .infinity, alignment: .leading)
                
                // Chart area
                HStack(spacing: 0) {
                    Spacer()
                        .frame(width: 40)
                    
                    ZStack {
                        // Grid
                        VStack(spacing: 0) {
                            ForEach(0..<5, id: \.self) { _ in
                                Divider().opacity(0.2)
                                Spacer()
                            }
                            Divider().opacity(0.2)
                        }
                        
                        // Area fill
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
                            
                            // Line
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
                            
                            // Data points
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
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
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
        NavigationView {
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
