import SwiftUI
import HealthKit

// MARK: - Step Tracker Card View
/// Beautiful, modern step tracker card for the dashboard
struct StepTrackerCard: View {
    @ObservedObject var healthKitManager = HealthKitManager.shared
    @State private var showingDetailView = false
    @State private var isAnimating = false
    @State private var isRefreshing = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        Button(action: {
            showingDetailView = true
        }) {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Image(systemName: "figure.walk")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.green, .cyan],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    Text("Daily Steps")
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    if isRefreshing {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else if healthKitManager.isGoalAchieved() {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.green)
                            .scaleEffect(isAnimating ? 1.2 : 1.0)
                    } else {
                        Button(action: {
                            Task {
                                await refreshSteps()
                            }
                        }) {
                            Image(systemName: "arrow.clockwise")
                                .font(.title3)
                                .foregroundColor(.blue)
                        }
                    }
                }
                .padding(.horizontal, Spacing.md)
                .padding(.top, 16)
                .padding(.bottom, 12)
                
                Divider()
                    .padding(.horizontal, Spacing.md)
                
                // Main content
                VStack(spacing: 12) {
                    // Permission prompt if not authorized
                    if !healthKitManager.isAuthorized {
                        VStack(spacing: 12) {
                            Image(systemName: "heart.text.square.fill")
                                .font(.system(size: 50))
                                .foregroundColor(.red)
                            
                            Text("Enable HealthKit")
                                .font(.headline)
                                .fontWeight(.bold)
                            
                            Text("Allow access to your step data to start tracking your daily activity")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                            
                            Button {
                                Task {
                                    try? await healthKitManager.requestAuthorization()
                                }
                            } label: {
                                Text("Enable HealthKit Access")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, Spacing.sm)
                                    .background(
                                        LinearGradient(
                                            colors: [.green, .cyan],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .cornerRadius(10)
                            }
                        }
                        .padding(.vertical, 20)
                    } else {
                        // Step count with circular progress
                        ZStack {
                            // Background circle
                            Circle()
                                .stroke(Color.gray.opacity(0.15), lineWidth: 12)
                                .frame(width: 140, height: 140)
                            
                            // Progress circle
                            Circle()
                                .trim(from: 0, to: healthKitManager.progressPercentage())
                                .stroke(
                                    LinearGradient(
                                        colors: [.green, .cyan, .blue],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    style: StrokeStyle(lineWidth: 12, lineCap: .round)
                                )
                                .frame(width: 140, height: 140)
                                .rotationEffect(.degrees(-90))
                                .animation(.spring(response: 0.6, dampingFraction: 0.7), value: healthKitManager.todaySteps)
                            
                            // Step count in center
                            VStack(spacing: 4) {
                                Text(healthKitManager.formattedSteps(healthKitManager.todaySteps))
                                    .font(.system(size: 32, weight: .bold, design: .rounded))
                                    .foregroundColor(.primary)
                                    .contentTransition(.numericText())
                                
                                Text("steps")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, Spacing.xs)
                        
                        // Goal info - floating stats
                        HStack(spacing: 16) {
                            // Remaining steps
                            VStack(spacing: 4) {
                                HStack(spacing: 4) {
                                    Image(systemName: "target")
                                        .font(.caption)
                                        .foregroundColor(.blue)
                                    
                                    Text("\(max(0, healthKitManager.stepGoal - healthKitManager.todaySteps))")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.primary)
                                }
                                
                                Text("to goal")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            
                            // Progress percentage
                            VStack(spacing: 4) {
                                HStack(spacing: 4) {
                                    Image(systemName: "chart.line.uptrend.xyaxis")
                                        .font(.caption)
                                        .foregroundColor(.green)
                                    
                                    Text("\(Int(healthKitManager.progressPercentage() * 100))%")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.primary)
                                }
                                
                                Text("complete")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .padding(.horizontal, Spacing.md)
                    }
                }
                .padding(.vertical, Spacing.sm)
                
                // Quick stats footer (only show if authorized)
                if healthKitManager.isAuthorized {
                    HStack(spacing: 16) {
                        // Monthly average
                        HStack(spacing: 6) {
                            Image(systemName: "calendar")
                                .font(.caption2)
                                .foregroundColor(.orange)
                            
                            VStack(alignment: .leading, spacing: 1) {
                                Text("\(healthKitManager.formattedSteps(healthKitManager.monthlyAverage))")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.primary)
                                
                                Text("monthly avg")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Spacer()
                        
                        // View details arrow
                        HStack(spacing: 4) {
                            Text("View Details")
                                .font(.caption)
                                .fontWeight(.medium)
                            
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                        }
                        .foregroundColor(.blue)
                    }
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.sm)
                    .background(Color(.systemGray6))
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .background(
            ZStack {
                // Bottom shadow layer (deepest) - teal colored
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color.teal.opacity(colorScheme == .dark ? 0.15 : 0.08))
                    .offset(y: 8)
                    .blur(radius: 4)
                
                // Middle shadow layer
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Color.black.opacity(colorScheme == .dark ? 0.2 : 0.04))
                    .offset(y: 4)
                
                // Main card background with gradient
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: colorScheme == .dark 
                                ? [Color(white: 0.15), Color(white: 0.10)]
                                : [Color.white, Color.white.opacity(0.95)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
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
                
                // Colored accent border - teal/cyan gradient
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.teal.opacity(colorScheme == .dark ? 0.4 : 0.3),
                                Color.cyan.opacity(colorScheme == .dark ? 0.3 : 0.2)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.08), radius: 12, x: 0, y: 6)
        .shadow(color: Color.teal.opacity(colorScheme == .dark ? 0.2 : 0.12), radius: 20, x: 0, y: 10)
        .sheet(isPresented: $showingDetailView) {
            StepTrackerDetailView()
        }
        .onAppear {
            // Animate checkmark if goal achieved
            if healthKitManager.isGoalAchieved() {
                withAnimation(Animation.spring(response: 0.3, dampingFraction: 0.5).repeatForever(autoreverses: true)) {
                    isAnimating = true
                }
            }
            
            // Refresh steps every time view appears (tab navigation)
            Task {
                await refreshSteps()
            }
        }
        .task {
            // Request authorization and load data (first time only)
            if !healthKitManager.isAuthorized {
                try? await healthKitManager.requestAuthorization()
            }
            await healthKitManager.loadStepGoal()
            await refreshSteps()
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            // Refresh when app comes to foreground
            if newPhase == .active {
                Task {
                    await refreshSteps()
                }
            }
        }
    }
    
    // Manual refresh function
    private func refreshSteps() async {
        isRefreshing = true
        await healthKitManager.fetchTodaySteps()
        await healthKitManager.fetchWeeklySteps()
        await healthKitManager.fetchMonthlyAverage()
        try? await Task.sleep(nanoseconds: 500_000_000)
        isRefreshing = false
    }
}

// MARK: - Step Tracker Detail View
/// Full-screen detailed view for step tracking
struct StepTrackerDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var healthKitManager = HealthKitManager.shared
    @State private var showingGoalEditor = false
    @State private var selectedTimeRange: TimeRange = .week
    
    enum TimeRange: String, CaseIterable {
        case week = "Week"
        case month = "Month"
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Animated orb background (consistent with other screens)
                AnimatedOrbBackground.stats(colorScheme: colorScheme)
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Today's progress card
                        todayProgressCard
                            .padding(.horizontal, 20)
                            .padding(.top, 20)
                        
                        // Weekly chart
                        weeklyChartCard
                            .padding(.horizontal, 20)
                        
                        // Statistics
                        statisticsCard
                            .padding(.horizontal, 20)
                            .padding(.bottom, 40)
                    }
                }
            }
            .navigationTitle("Step Tracking")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                    .foregroundColor(.blue)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingGoalEditor = true
                    } label: {
                        Image(systemName: "target")
                            .foregroundColor(.blue)
                    }
                }
            }
            .sheet(isPresented: $showingGoalEditor) {
                StepGoalEditorView()
            }
        }
    }
    
    // MARK: - Today's Progress Card
    private var todayProgressCard: some View {
        VStack(spacing: 16) {
            // Large circular progress
            ZStack {
                // Background circle
                Circle()
                    .stroke(Color.gray.opacity(0.25), lineWidth: 20)
                    .frame(width: 220, height: 220)
                
                // Progress circle
                Circle()
                    .trim(from: 0, to: healthKitManager.progressPercentage())
                    .stroke(
                        LinearGradient(
                            colors: [.green, .cyan, .blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 20, lineCap: .round)
                    )
                    .frame(width: 220, height: 220)
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(response: 0.6, dampingFraction: 0.7), value: healthKitManager.todaySteps)
                
                // Center content
                VStack(spacing: 8) {
                    Text(healthKitManager.formattedSteps(healthKitManager.todaySteps))
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .contentTransition(.numericText())
                    
                    Text("steps today")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                    
                    if healthKitManager.isGoalAchieved() {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Goal achieved!")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.green)
                        }
                        .padding(.top, 4)
                    }
                }
            }
            
            // Goal display
            HStack {
                Image(systemName: "target")
                    .foregroundColor(.blue)
                Text("Goal: \(healthKitManager.formattedSteps(healthKitManager.stepGoal)) steps")
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, 10)
            .background(Color.blue.opacity(0.15))
            .cornerRadius(10)
        }
        .padding(24)
        .background(Color.cardBackground)
        .cornerRadius(20)
    }
    
    // MARK: - Weekly Chart Card
    private var weeklyChartCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("This Week")
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            if healthKitManager.weeklySteps.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 12) {
                        ProgressView()
                            .tint(.white)
                        Text("Loading step data...")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    .padding(.vertical, 40)
                    Spacer()
                }
            } else {
                WeeklyStepChart(weeklyData: healthKitManager.weeklySteps, goal: healthKitManager.stepGoal)
            }
        }
        .padding(20)
        .background(Color.cardBackground)
        .cornerRadius(20)
    }
    
    // MARK: - Statistics Card
    private var statisticsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Statistics")
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            VStack(spacing: 12) {
                StatRow(
                    icon: "calendar",
                    title: "Monthly Average",
                    value: "\(healthKitManager.formattedSteps(healthKitManager.monthlyAverage))",
                    color: .orange
                )
                
                Divider()
                    .background(Color.gray.opacity(0.3))
                
                StatRow(
                    icon: "flame.fill",
                    title: "Today's Progress",
                    value: "\(Int(healthKitManager.progressPercentage() * 100))%",
                    color: .red
                )
                
                Divider()
                    .background(Color.gray.opacity(0.3))
                
                StatRow(
                    icon: "arrow.up.circle.fill",
                    title: "Steps to Goal",
                    value: "\(healthKitManager.formattedSteps(max(0, healthKitManager.stepGoal - healthKitManager.todaySteps)))",
                    color: .blue
                )
            }
        }
        .padding(20)
        .background(Color.cardBackground)
        .cornerRadius(20)
    }
}

// MARK: - Weekly Step Chart
struct WeeklyStepChart: View {
    let weeklyData: [HealthKitManager.DailySteps]
    let goal: Int
    
    private var maxSteps: Int {
        max(weeklyData.map { $0.steps }.max() ?? goal, goal)
    }
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            ForEach(weeklyData) { day in
                VStack(spacing: 8) {
                    // Bar
                    VStack {
                        Spacer()
                        
                        RoundedRectangle(cornerRadius: 6)
                            .fill(
                                LinearGradient(
                                    colors: day.steps >= goal ? 
                                        [.green, .cyan] : [.blue.opacity(0.8), .blue.opacity(0.5)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(height: CGFloat(day.steps) / CGFloat(maxSteps) * 120)
                            .overlay(
                                day.steps >= goal ?
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.caption2)
                                        .foregroundColor(.white)
                                        .offset(y: -15)
                                    : nil
                            )
                    }
                    .frame(height: 120)
                    
                    // Day label
                    Text(dayLabel(for: day.date))
                        .font(.caption2)
                        .fontWeight(day.isToday ? .bold : .regular)
                        .foregroundColor(day.isToday ? .blue : .gray)
                    
                    // Step count
                    Text(shortStepLabel(day.steps))
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, Spacing.xs)
    }
    
    private func dayLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }
    
    private func shortStepLabel(_ steps: Int) -> String {
        if steps >= 1000 {
            return String(format: "%.1fK", Double(steps) / 1000.0)
        }
        return "\(steps)"
    }
}

// MARK: - Stat Row
struct StatRow: View {
    let icon: String
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(.gray)
                
                Text(value)
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
            }
            
            Spacer()
        }
    }
}

// MARK: - Step Goal Editor View
struct StepGoalEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var healthKitManager = HealthKitManager.shared
    @State private var goalInput: String = ""
    @State private var selectedPreset: Int? = nil
    
    let presetGoals = [5000, 8000, 10000, 12000, 15000, 20000]
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Set your daily step goal")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    HStack {
                        Image(systemName: "target")
                            .foregroundColor(.blue)
                        
                        TextField("Enter goal", text: $goalInput)
                            .keyboardType(.numberPad)
                            .font(.title3)
                            .fontWeight(.semibold)
                        
                        Text("steps")
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("Custom Goal")
                }
                
                Section {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(presetGoals, id: \.self) { goal in
                            Button {
                                selectedPreset = goal
                                goalInput = "\(goal)"
                            } label: {
                                VStack(spacing: 8) {
                                    Text("\(goal)")
                                        .font(.title3)
                                        .fontWeight(.bold)
                                    
                                    Text("steps")
                                        .font(.caption)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, Spacing.md)
                                .background(
                                    RoundedRectangle(cornerRadius: CornerRadius.md)
                                        .fill(selectedPreset == goal ? Color.blue.opacity(0.15) : Color(.systemGray6))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: CornerRadius.md)
                                        .stroke(selectedPreset == goal ? Color.blue : Color.clear, lineWidth: 2)
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                } header: {
                    Text("Quick Presets")
                }
                
                Section {
                    Button {
                        if let goal = Int(goalInput), goal > 0 {
                            Task {
                                await healthKitManager.updateStepGoal(goal)
                                dismiss()
                            }
                        }
                    } label: {
                        HStack {
                            Spacer()
                            Text("Save Goal")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                    .disabled(goalInput.isEmpty || Int(goalInput) ?? 0 <= 0)
                }
            }
            .navigationTitle("Step Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                goalInput = "\(healthKitManager.stepGoal)"
                selectedPreset = presetGoals.contains(healthKitManager.stepGoal) ? healthKitManager.stepGoal : nil
            }
        }
    }
}

// MARK: - Preview
#Preview {
    StepTrackerCard()
}

#Preview("Detail View") {
    StepTrackerDetailView()
}
