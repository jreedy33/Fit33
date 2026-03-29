import SwiftUI
import HealthKit

// MARK: - Step Tracker Card View
/// Beautiful, modern step tracker card for the dashboard
struct StepTrackerCard: View {
    @ObservedObject var healthKitManager = HealthKitManager.shared
    @State private var showingDetailView = false
    @State private var isAnimating = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Section header (matches Recent Activity / Your Progress style)
            HStack(spacing: 10) {
                Image(systemName: "figure.walk")
                    .foregroundStyle(
                        LinearGradient(colors: [.green, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .font(.title3)
                Text("Daily Steps")
                    .font(.title3)
                    .fontWeight(.bold)
                
                Spacer()
                
                if healthKitManager.isGoalAchieved() {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.green)
                        .scaleEffect(isAnimating ? 1.15 : 1.0)
                }
                
                if healthKitManager.isAuthorized {
                    HStack(spacing: 4) {
                        Text("View Details")
                            .font(.caption)
                            .fontWeight(.medium)
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                    }
                    .foregroundColor(.blue)
                }
            }
            
            // Card body
            Button(action: {
                showingDetailView = true
            }) {
                VStack(spacing: 0) {
                    // Main content
                    VStack(spacing: 12) {
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
                                Circle()
                                    .stroke(Color.gray.opacity(0.15), lineWidth: 12)
                                    .frame(width: 140, height: 140)
                                
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
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Spacing.xs)
                            
                            // Goal info - floating stats
                            HStack(spacing: 12) {
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
                                
                                VStack(spacing: 4) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "calendar")
                                            .font(.caption)
                                            .foregroundColor(.orange)
                                        
                                        Text("\(healthKitManager.formattedSteps(healthKitManager.monthlyAverage))")
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                            .foregroundColor(.primary)
                                    }
                                    
                                    Text("month avg")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                .frame(maxWidth: .infinity)
                                
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
                    .padding(.horizontal, Spacing.xs)
                    
                }
            }
            .buttonStyle(PlainButtonStyle())
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(Color.teal.opacity(colorScheme == .dark ? 0.15 : 0.08))
                        .offset(y: 8)
                        .blur(radius: 4)
                    
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(Color.black.opacity(colorScheme == .dark ? 0.2 : 0.04))
                        .offset(y: 4)
                    
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
        }
        .sheet(isPresented: $showingDetailView) {
            StepTrackerDetailView()
        }
        .onAppear {
            if healthKitManager.isGoalAchieved() {
                withAnimation(Animation.spring(response: 0.3, dampingFraction: 0.5).repeatForever(autoreverses: true)) {
                    isAnimating = true
                }
            }
            
            Task {
                await refreshSteps()
            }
        }
        .task {
            if !healthKitManager.isAuthorized {
                try? await healthKitManager.requestAuthorization()
            }
            await healthKitManager.loadStepGoal()
            await refreshSteps()
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if newPhase == .active {
                Task {
                    await refreshSteps()
                }
            }
        }
    }
    
    private func refreshSteps() async {
        await healthKitManager.fetchTodaySteps()
        await healthKitManager.fetchWeeklySteps()
        await healthKitManager.fetchMonthlyAverage()
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
    @State private var cardsAppeared = false

    enum TimeRange: String, CaseIterable {
        case week = "Week"
        case month = "Month"
    }

    // MARK: - Computed helpers

    private var weeklyTotal: Int {
        healthKitManager.weeklySteps.reduce(0) { $0 + $1.steps }
    }

    private var daysGoalMet: Int {
        healthKitManager.weeklySteps.filter { $0.steps >= healthKitManager.stepGoal }.count
    }

    private var weeklyDailyAverage: Int {
        let count = healthKitManager.weeklySteps.count
        guard count > 0 else { return 0 }
        return weeklyTotal / count
    }

    private var bestDay: HealthKitManager.DailySteps? {
        healthKitManager.weeklySteps.max(by: { $0.steps < $1.steps })
    }

    private var trendPercentage: Double? {
        guard healthKitManager.monthlyAverage > 0 else { return nil }
        let diff = Double(healthKitManager.todaySteps) - Double(healthKitManager.monthlyAverage)
        return (diff / Double(healthKitManager.monthlyAverage)) * 100
    }

    private func bestDayName(_ day: HealthKitManager.DailySteps) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter.string(from: day.date)
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                AnimatedOrbBackground.stats(colorScheme: colorScheme)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: Spacing.lg) {
                        todayProgressCard
                            .padding(.horizontal, 20)
                            .padding(.top, 20)
                            .offset(y: cardsAppeared ? 0 : 30)
                            .opacity(cardsAppeared ? 1 : 0)
                            .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.05), value: cardsAppeared)

                        if let best = bestDay, !healthKitManager.weeklySteps.isEmpty {
                            bestDayCard(best)
                                .padding(.horizontal, 20)
                                .offset(y: cardsAppeared ? 0 : 30)
                                .opacity(cardsAppeared ? 1 : 0)
                                .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.12), value: cardsAppeared)
                        }

                        weeklySummaryRow
                            .padding(.horizontal, 20)
                            .offset(y: cardsAppeared ? 0 : 30)
                            .opacity(cardsAppeared ? 1 : 0)
                            .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.19), value: cardsAppeared)

                        weeklyChartCard
                            .padding(.horizontal, 20)
                            .offset(y: cardsAppeared ? 0 : 30)
                            .opacity(cardsAppeared ? 1 : 0)
                            .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.26), value: cardsAppeared)

                        statisticsCard
                            .padding(.horizontal, 20)
                            .padding(.bottom, 40)
                            .offset(y: cardsAppeared ? 0 : 30)
                            .opacity(cardsAppeared ? 1 : 0)
                            .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.33), value: cardsAppeared)
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
                    .accessibilityLabel("Close")
                    .accessibilityHint("Dismisses the step tracking detail view")
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingGoalEditor = true
                    } label: {
                        Image(systemName: "target")
                            .foregroundColor(.blue)
                    }
                    .accessibilityLabel("Edit Step Goal")
                    .accessibilityHint("Opens the step goal editor")
                }
            }
            .sheet(isPresented: $showingGoalEditor) {
                StepGoalEditorView()
            }
            .onAppear {
                cardsAppeared = true
            }
        }
    }

    // MARK: - Today's Progress Card
    private var todayProgressCard: some View {
        VStack(spacing: Spacing.md) {
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.25), lineWidth: 20)
                    .frame(width: 220, height: 220)

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

                VStack(spacing: 8) {
                    Text(healthKitManager.formattedSteps(healthKitManager.todaySteps))
                        .font(.ds_displayMedium).fontDesign(.rounded)
                        .foregroundColor(.white)
                        .contentTransition(.numericText())

                    Text("steps today")
                        .font(.ds_labelLarge)
                        .foregroundColor(.gray)

                    if healthKitManager.isGoalAchieved() {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Goal achieved!")
                                .font(.ds_caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.green)
                        }
                        .padding(.top, 4)
                    }
                }
            }

            if let trend = trendPercentage {
                let isAbove = trend >= 0
                HStack(spacing: 4) {
                    Image(systemName: isAbove ? "arrow.up.right" : "arrow.down.right")
                        .font(.ds_caption)
                    Text("\(abs(Int(trend)))% \(isAbove ? "above" : "below") your monthly average")
                        .font(.ds_caption)
                }
                .foregroundColor(isAbove ? .green : .orange)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, 6)
                .background((isAbove ? Color.green : Color.orange).opacity(0.15))
                .clipShape(Capsule())
                .accessibilityLabel("Trend: \(abs(Int(trend))) percent \(isAbove ? "above" : "below") your monthly average")
                .accessibilityHidden(false)
            }

            HStack {
                Image(systemName: "target")
                    .foregroundColor(.blue)
                Text("Goal: \(healthKitManager.formattedSteps(healthKitManager.stepGoal)) steps")
                    .font(.ds_labelLarge)
                    .foregroundColor(.gray)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, 10)
            .background(Color.blue.opacity(0.15))
            .cornerRadius(10)
        }
        .padding(Spacing.lg)
        .background(Color.cardBackground)
        .cornerRadius(CornerRadius.xl)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Today's step progress")
    }

    // MARK: - Best Day Card
    private func bestDayCard(_ day: HealthKitManager.DailySteps) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "trophy.fill")
                .font(.ds_heading3)
                .foregroundStyle(
                    LinearGradient(colors: [.yellow, .orange], startPoint: .top, endPoint: .bottom)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text("Best Day This Week")
                    .font(.ds_caption)
                    .foregroundColor(.gray)
                HStack(spacing: 6) {
                    Text(bestDayName(day))
                        .font(.ds_heading3)
                        .foregroundColor(.white)
                    Text("·")
                        .foregroundColor(.gray)
                    Text("\(healthKitManager.formattedSteps(day.steps)) steps")
                        .font(.ds_labelLarge)
                        .foregroundColor(.cyan)
                }
            }

            Spacer()
        }
        .padding(Spacing.lg)
        .background(
            LinearGradient(
                colors: [Color.orange.opacity(0.12), Color.yellow.opacity(0.06)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .background(Color.cardBackground)
        .cornerRadius(CornerRadius.xl)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Best day this week: \(bestDayName(day)) with \(day.steps) steps")
    }

    // MARK: - Weekly Summary Row
    private var weeklySummaryRow: some View {
        HStack(spacing: Spacing.sm) {
            summaryBadge(
                icon: "sum",
                label: "Weekly Total",
                value: healthKitManager.formattedSteps(weeklyTotal),
                tint: .cyan
            )
            summaryBadge(
                icon: "checkmark.seal.fill",
                label: "Days Goal Met",
                value: "\(daysGoalMet)",
                tint: .green
            )
            summaryBadge(
                icon: "chart.bar.fill",
                label: "Daily Avg",
                value: healthKitManager.formattedSteps(weeklyDailyAverage),
                tint: .purple
            )
        }
    }

    private func summaryBadge(icon: String, label: String, value: String, tint: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.ds_labelLarge)
                .foregroundColor(tint)
            Text(value)
                .font(.ds_heading3)
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.ds_caption)
                .foregroundColor(.gray)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.sm)
        .padding(.horizontal, Spacing.xs)
        .background(Color.cardBackground)
        .cornerRadius(CornerRadius.xl)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }

    // MARK: - Weekly Chart Card
    private var weeklyChartCard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("This Week")
                .font(.ds_heading3)
                .fontWeight(.bold)
                .foregroundColor(.white)

            if healthKitManager.weeklySteps.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 12) {
                        ProgressView()
                            .tint(.white)
                        Text("Loading step data...")
                            .font(.ds_caption)
                            .foregroundColor(.gray)
                    }
                    .padding(.vertical, 40)
                    Spacer()
                }
            } else {
                WeeklyStepChart(weeklyData: healthKitManager.weeklySteps, goal: healthKitManager.stepGoal)
            }
        }
        .padding(Spacing.lg)
        .background(Color.cardBackground)
        .cornerRadius(CornerRadius.xl)
    }

    // MARK: - Statistics Card (2×3 Grid)
    private var statisticsCard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Statistics")
                .font(.ds_heading3)
                .fontWeight(.bold)
                .foregroundColor(.white)

            let columns = [
                GridItem(.flexible(), spacing: Spacing.sm),
                GridItem(.flexible(), spacing: Spacing.sm)
            ]

            LazyVGrid(columns: columns, spacing: Spacing.sm) {
                DetailStatCard(
                    icon: "calendar",
                    title: "Monthly Average",
                    value: healthKitManager.formattedSteps(healthKitManager.monthlyAverage),
                    tint: .orange
                )
                DetailStatCard(
                    icon: "flame.fill",
                    title: "Today's Progress",
                    value: "\(Int(healthKitManager.progressPercentage() * 100))%",
                    tint: .red
                )
                DetailStatCard(
                    icon: "arrow.up.circle.fill",
                    title: "Steps to Goal",
                    value: healthKitManager.formattedSteps(max(0, healthKitManager.stepGoal - healthKitManager.todaySteps)),
                    tint: .blue
                )
                DetailStatCard(
                    icon: "figure.walk",
                    title: "Weekly Total",
                    value: healthKitManager.formattedSteps(weeklyTotal),
                    tint: .cyan
                )
                DetailStatCard(
                    icon: "trophy.fill",
                    title: "Best Day",
                    value: bestDay.map { healthKitManager.formattedSteps($0.steps) } ?? "—",
                    tint: .yellow
                )
                DetailStatCard(
                    icon: "checkmark.seal.fill",
                    title: "Days Goal Met",
                    value: "\(daysGoalMet) / \(healthKitManager.weeklySteps.count)",
                    tint: .green
                )
            }
        }
        .padding(Spacing.lg)
        .background(Color.cardBackground)
        .cornerRadius(CornerRadius.xl)
    }
}

// MARK: - Detail Stat Card (grid item)
private struct DetailStatCard: View {
    let icon: String
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.ds_heading3)
                .foregroundColor(tint)

            Text(value)
                .font(.ds_heading3)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(title)
                .font(.ds_caption)
                .foregroundColor(.gray)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.md)
        .background(Color.white.opacity(0.05))
        .cornerRadius(CornerRadius.lg)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value)")
    }
}

// MARK: - Weekly Step Chart
struct WeeklyStepChart: View {
    let weeklyData: [HealthKitManager.DailySteps]
    let goal: Int

    private var maxSteps: Int {
        max(weeklyData.map { $0.steps }.max() ?? goal, goal)
    }

    private let chartHeight: CGFloat = 140

    var body: some View {
        ZStack(alignment: .leading) {
            // Dashed goal line
            GeometryReader { geo in
                let goalY = chartHeight - (CGFloat(goal) / CGFloat(maxSteps) * chartHeight)
                Path { path in
                    path.move(to: CGPoint(x: 0, y: goalY))
                    path.addLine(to: CGPoint(x: geo.size.width, y: goalY))
                }
                .stroke(Color.green.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [6, 4]))

                Text("Goal")
                    .font(.ds_caption)
                    .foregroundColor(.green.opacity(0.7))
                    .position(x: geo.size.width - 20, y: goalY - 10)
            }
            .frame(height: chartHeight)
            .padding(.bottom, 40)

            // Bars
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(weeklyData) { day in
                    VStack(spacing: 4) {
                        Text(shortStepLabel(day.steps))
                            .font(.ds_caption)
                            .foregroundColor(.gray)

                        VStack {
                            Spacer()

                            RoundedRectangle(cornerRadius: 6)
                                .fill(
                                    LinearGradient(
                                        colors: day.steps >= goal
                                            ? [.green, .cyan] : [.blue.opacity(0.8), .blue.opacity(0.5)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .frame(height: max(4, CGFloat(day.steps) / CGFloat(maxSteps) * chartHeight))
                        }
                        .frame(height: chartHeight)

                        Text(dayLabel(for: day.date))
                            .font(.ds_caption)
                            .fontWeight(day.isToday ? .bold : .regular)
                            .foregroundColor(day.isToday ? .blue : .gray)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(dayLabel(for: day.date)): \(day.steps) steps")
                }
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
