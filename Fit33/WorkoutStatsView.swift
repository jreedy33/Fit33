import SwiftUI
import Charts
import CoreData

// MARK: - Stats Timeframe

enum StatsTimeframe: String, CaseIterable {
    case week = "Week"
    case month = "Month"
    case threeMonths = "3M"
    case year = "Year"
    case all = "All"

    var days: Int {
        switch self {
        case .week: return 7
        case .month: return 30
        case .threeMonths: return 90
        case .year: return 365
        case .all: return 3650
        }
    }

    var startDate: Date {
        Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
    }

    var calendarComponent: Calendar.Component {
        switch self {
        case .week, .month: return .day
        case .threeMonths: return .weekOfYear
        case .year, .all: return .month
        }
    }
}

// MARK: - Chart Data Points

struct VolumeDataPoint: Identifiable {
    let id = UUID()
    let date: Date
    let volume: Double
    let isPreviousPeriod: Bool
}

struct FrequencyDataPoint: Identifiable {
    let id = UUID()
    let date: Date
    let count: Int
    let workoutType: String
}

struct StrengthDataPoint: Identifiable {
    let id = UUID()
    let date: Date
    let maxWeight: Double
    let exerciseName: String
}

struct CalorieDurationPoint: Identifiable {
    let id = UUID()
    let date: Date
    let calories: Double
    let duration: Int
}

struct MuscleGroupSlice: Identifiable {
    let id = UUID()
    let category: String
    let count: Int
    let color: Color
}

struct NutritionDayPoint: Identifiable {
    let id = UUID()
    let date: Date
    let calories: Double
    let protein: Double
    let carbs: Double
    let fat: Double
}

struct MacroLinePoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
    let macro: String
}

// MARK: - WorkoutStatsSection (Container)

struct WorkoutStatsSection: View {
    var body: some View {
        // Use VStack (not LazyVStack) so all widget heights stabilize on first layout.
        // LazyVStack deferred `.task` loads until scroll-into-view, which caused the
        // bottom of the section to rubber-band as placeholders (180pt) were replaced
        // with taller/shorter real charts mid-scroll.
        VStack(spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text("My Stats")
                    .font(.ds_heading1)
                    .foregroundColor(.adaptiveText)
                Text("Your personal insights — only visible to you.")
                    .font(.ds_bodySmall)
                    .foregroundColor(.adaptiveSecondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, Spacing.lg)

            ComprehensiveStatsGridWidget()
            NutritionTrendsChartWidget()
            CalorieBalanceChartWidget()
            WorkoutVolumeChartWidget()
            WorkoutFrequencyChartWidget()
            StrengthProgressChartWidget()
            PersonalRecordsWidget()
            BodyWeightTrendWidget()
            WorkoutDurationChartWidget()
            MuscleGroupDistributionWidget()
        }
    }
}

// MARK: - 9. Comprehensive Stats Grid

struct ComprehensiveStatsGridWidget: View {
    @EnvironmentObject var userManager: UserManager

    @State private var totalVolume: String = "--"
    @State private var avgDuration: String = "--"
    @State private var heaviestLift: String = "--"
    @State private var totalCalories: String = "--"
    @State private var hasLoaded = false

    private var totalWorkouts: Int { Int(userManager.currentUser?.totalWorkouts ?? 0) }
    private var currentStreak: Int { Int(userManager.currentUser?.currentStreak ?? 0) }

    var body: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: Spacing.sm),
            GridItem(.flexible(), spacing: Spacing.sm)
        ], spacing: Spacing.sm) {
            StatCell(title: "Total Workouts", value: "\(totalWorkouts)", icon: "dumbbell.fill", accentColor: .blue)
            StatCell(title: "Current Streak", value: "\(currentStreak) days", icon: "flame.fill", accentColor: .orange)
            StatCell(title: "Total Volume", value: totalVolume, icon: "scalemass.fill", accentColor: .purple)
            StatCell(title: "Avg Duration", value: avgDuration, icon: "clock.fill", accentColor: .green)
            StatCell(title: "Heaviest Lift", value: heaviestLift, icon: "trophy.fill", accentColor: .yellow)
            StatCell(title: "Calories Burned", value: totalCalories, icon: "flame.circle.fill", accentColor: .red)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Comprehensive stats overview")
        .task {
            guard !hasLoaded else { return }
            hasLoaded = true
            await computeStats()
        }
    }

    private func computeStats() async {
        let context = PersistenceController.shared.container.newBackgroundContext()
        await context.perform {
            let request: NSFetchRequest<Workout> = Workout.fetchRequest()
            request.predicate = NSPredicate(format: "isCompleted == YES")
            request.sortDescriptors = [NSSortDescriptor(keyPath: \Workout.date, ascending: false)]
            request.fetchLimit = 200

            guard let results = try? context.fetch(request) else { return }

            var vol: Double = 0
            var cal: Double = 0
            var durTotal: Int = 0
            var durCount: Int = 0
            var maxWeight: Double = 0

            for workout in results {
                vol += workout.totalVolume
                cal += workout.caloriesBurned
                if workout.duration > 0 { durTotal += Int(workout.duration); durCount += 1 }

                if let wExercises = workout.exercises?.allObjects as? [WorkoutExercise] {
                    for wEx in wExercises {
                        if let wSets = wEx.sets?.allObjects as? [WorkoutSet] {
                            for s in wSets {
                                if s.weight > maxWeight { maxWeight = s.weight }
                            }
                        }
                    }
                }
            }

            let avgDur = durCount > 0 ? durTotal / durCount / 60 : 0

            Task { @MainActor in
                self.totalVolume = formatVolume(vol)
                self.avgDuration = "\(avgDur) min"
                self.heaviestLift = "\(Int(maxWeight)) lbs"
                self.totalCalories = formatCalories(cal)
            }
        }
    }

    private func formatVolume(_ vol: Double) -> String {
        if vol >= 1_000_000 { return String(format: "%.1fM", vol / 1_000_000) }
        if vol >= 1_000 { return String(format: "%.0fK", vol / 1_000) }
        return "\(Int(vol))"
    }

    private func formatCalories(_ cal: Double) -> String {
        if cal >= 1_000 { return String(format: "%.1fK", cal / 1_000) }
        return "\(Int(cal))"
    }
}

private struct StatCell: View {
    let title: String
    let value: String
    let icon: String
    let accentColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.xxs) {
                Image(systemName: icon).font(.ds_labelSmall).foregroundColor(accentColor)
                Text(title).font(.ds_labelSmall).foregroundColor(.adaptiveSecondaryText)
            }
            Text(value).font(.ds_stat).foregroundColor(.adaptiveText).minimumScaleFactor(0.7).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.sm)
        .sleekCard(cornerRadius: CornerRadius.lg, accentColor: accentColor)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 10. Nutrition Trends

struct NutritionTrendsChartWidget: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var timeframe: StatsTimeframe = .month
    @State private var dataPoints: [NutritionDayPoint] = []
    @State private var isLoading = true
    @State private var selectedMetrics: Set<String> = ["Calories", "Protein", "Carbs", "Fat"]
    @State private var selectedMacroDate: Date?

    private let metricColors: [(name: String, color: Color)] = [
        ("Calories", .orange), ("Protein", .blue), ("Carbs", .green), ("Fat", .purple)
    ]

    private var macroPoints: [MacroLinePoint] {
        var pts: [MacroLinePoint] = []
        for dp in dataPoints {
            if selectedMetrics.contains("Calories") { pts.append(MacroLinePoint(date: dp.date, value: dp.calories, macro: "Calories")) }
            if selectedMetrics.contains("Protein") { pts.append(MacroLinePoint(date: dp.date, value: dp.protein, macro: "Protein")) }
            if selectedMetrics.contains("Carbs") { pts.append(MacroLinePoint(date: dp.date, value: dp.carbs, macro: "Carbs")) }
            if selectedMetrics.contains("Fat") { pts.append(MacroLinePoint(date: dp.date, value: dp.fat, macro: "Fat")) }
        }
        return pts
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader(title: "Nutrition Trends", icon: "fork.knife", iconColor: .teal)

            StatsTimeframePicker(selected: $timeframe)

            VStack(alignment: .leading, spacing: Spacing.sm) {
                if isLoading {
                    chartPlaceholder(height: 200)
                } else if dataPoints.isEmpty {
                    emptyChartState(message: "Log meals to see nutrition trends", height: 200)
                } else {
                    if !dataPoints.isEmpty {
                        let avgCal = dataPoints.reduce(0) { $0 + $1.calories } / max(1, Double(dataPoints.count))
                        HStack {
                            Spacer()
                            Text("Avg: \(Int(avgCal)) cal/day")
                                .font(.ds_labelSmall)
                                .foregroundColor(.orange)
                        }
                    }

                    Chart(macroPoints) { point in
                        LineMark(x: .value("Date", point.date), y: .value("Value", point.value))
                            .foregroundStyle(by: .value("Metric", point.macro))
                            .lineStyle(StrokeStyle(lineWidth: point.macro == "Calories" ? 2.5 : 2))
                            .interpolationMethod(.monotone)
                            .symbol(by: .value("Metric", point.macro))
                    }
                    .chartForegroundStyleScale(["Calories": Color.orange, "Protein": Color.blue, "Carbs": Color.green, "Fat": Color.purple])
                    .frame(height: 200)
                    .chartLegend(.hidden)
                    .chartYAxis { AxisMarks(position: .leading) { _ in AxisValueLabel().font(.ds_caption); AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3])) } }
                    .chartXAxis { AxisMarks(values: .automatic(desiredCount: 5)) { value in AxisValueLabel { if let d = value.as(Date.self) { Text(shortDateLabel(d, timeframe: timeframe)).font(.ds_caption) } } } }
                    .interactiveLineChart(dataPoints: dataPoints, dateKeyPath: \.date, valueKeyPath: \.calories, label: "Calories", formatValue: { "\(Int($0)) cal" }, accentColor: .orange, selectedDate: $selectedMacroDate)

                    ChartToggleGrid(items: metricColors, selected: $selectedMetrics)
                }
            }
            .padding(.horizontal, Spacing.md).padding(.vertical, Spacing.md)
            .sleekCard(cornerRadius: CornerRadius.xl, accentColor: .teal)
        }
        .task(id: timeframe) { await loadNutritionData() }
    }

    private func loadNutritionData() async {
        isLoading = true
        let mealService = MealService.shared
        let calendar = Calendar.current
        let days = timeframe.days
        await Task.detached {
            var points: [NutritionDayPoint] = []
            for dayOffset in (0..<days).reversed() {
                guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: Date()) else { continue }
                let meals = await MainActor.run { mealService.getMealsForDate(date) }
                guard !meals.isEmpty else { continue }
                points.append(NutritionDayPoint(
                    date: calendar.startOfDay(for: date),
                    calories: Double(meals.reduce(0) { $0 + $1.calories }),
                    protein: Double(meals.reduce(0) { $0 + $1.protein }),
                    carbs: Double(meals.reduce(0) { $0 + $1.carbs }),
                    fat: Double(meals.reduce(0) { $0 + $1.fat })
                ))
            }
            await MainActor.run { self.dataPoints = points; self.isLoading = false }
        }.value
    }
}

// MARK: - Calorie Balance (Intake vs Burned)

struct CalorieBalancePoint: Identifiable {
    let id = UUID()
    let date: Date
    let intake: Double
    let burned: Double
    var net: Double { intake - burned }
}

struct CalorieBalanceChartWidget: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var timeframe: StatsTimeframe = .month
    @State private var dataPoints: [CalorieBalancePoint] = []
    @State private var isLoading = true
    @State private var selectedDate: Date?
    @State private var rawSelection: Date?
    @State private var selectedLines: Set<String> = ["Intake", "Burned"]

    private let balanceColors: [(name: String, color: Color)] = [
        ("Intake", .orange), ("Burned", .red)
    ]

    private var netAvg: Double {
        guard !dataPoints.isEmpty else { return 0 }
        return dataPoints.reduce(0) { $0 + $1.net } / Double(dataPoints.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader(title: "Calorie Balance", icon: "arrow.left.arrow.right", iconColor: .orange)

            StatsTimeframePicker(selected: $timeframe)

            VStack(alignment: .leading, spacing: Spacing.sm) {
                if isLoading {
                    chartPlaceholder(height: 180)
                } else if dataPoints.isEmpty {
                    emptyChartState(message: "Log meals and complete workouts to see your calorie balance", height: 180)
                } else {
                    if !dataPoints.isEmpty {
                        let netColor: Color = netAvg > 0 ? .orange : .green
                        HStack {
                            Spacer()
                            Text("Net: \(netAvg > 0 ? "+" : "")\(Int(netAvg))/day")
                                .font(.ds_labelSmall).foregroundColor(netColor)
                        }
                    }

                    Chart {
                        ForEach(dataPoints) { point in
                            if selectedLines.contains("Intake") {
                                AreaMark(x: .value("Date", point.date), y: .value("Intake", point.intake))
                                    .foregroundStyle(LinearGradient(colors: [Color.orange.opacity(0.2), Color.orange.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                                    .interpolationMethod(.monotone)
                                LineMark(x: .value("Date", point.date), y: .value("Intake", point.intake))
                                    .foregroundStyle(Color.orange).lineStyle(StrokeStyle(lineWidth: 2.5)).interpolationMethod(.monotone)
                            }
                            if selectedLines.contains("Burned") {
                                LineMark(x: .value("Date", point.date), y: .value("Burned", point.burned))
                                    .foregroundStyle(Color.red).lineStyle(StrokeStyle(lineWidth: 2, dash: [4, 3])).interpolationMethod(.monotone)
                            }
                        }
                    }
                    .frame(height: 180)
                    .chartYAxis { AxisMarks(position: .leading) { _ in AxisValueLabel().font(.ds_caption); AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3])) } }
                    .chartXAxis { AxisMarks(values: .automatic(desiredCount: 5)) { value in AxisValueLabel { if let d = value.as(Date.self) { Text(shortDateLabel(d, timeframe: timeframe)).font(.ds_caption) } } } }
                    .chartXSelection(value: $rawSelection)
                    .onChange(of: rawSelection) { _, newValue in
                        guard let newValue else {
                            withAnimation(.easeOut(duration: 0.15)) { selectedDate = nil }
                            return
                        }
                        guard let nearest = dataPoints.min(by: { abs($0.date.timeIntervalSince(newValue)) < abs($1.date.timeIntervalSince(newValue)) }) else { return }
                        let shouldHaptic: Bool = {
                            guard let current = selectedDate else { return true }
                            return !Calendar.current.isDate(current, inSameDayAs: nearest.date)
                        }()
                        selectedDate = nearest.date
                        if shouldHaptic { HapticManager.impact(.light) }
                    }
                    .chartOverlay { proxy in
                        GeometryReader { geo in
                            if let sd = selectedDate,
                               let match = dataPoints.first(where: { Calendar.current.isDate($0.date, inSameDayAs: sd) }) {

                                let plotFrame = geo[proxy.plotFrame!]
                                let originX = plotFrame.origin.x
                                let originY = plotFrame.origin.y

                                if let rawX = proxy.position(forX: match.date) {
                                    let xPos = originX + rawX

                                    Rectangle().fill(Color.orange.opacity(0.4)).frame(width: 1, height: plotFrame.height)
                                        .position(x: xPos, y: originY + plotFrame.height / 2)

                                    let netVal = match.net
                                    let netColor: Color = netVal > 0 ? .orange : .green
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(shortDateLabel(match.date, timeframe: .month)).font(.ds_caption).foregroundColor(.adaptiveSecondaryText)
                                        HStack(spacing: Spacing.xxs) {
                                            Text("In: \(Int(match.intake))").font(.ds_labelSmall).foregroundColor(.orange)
                                            Text("Out: \(Int(match.burned))").font(.ds_labelSmall).foregroundColor(.red)
                                        }
                                        HStack(spacing: 3) {
                                            Image(systemName: netVal > 0 ? "arrow.up.right" : "arrow.down.right")
                                                .font(.system(size: 8, weight: .bold))
                                            Text("Net: \(netVal > 0 ? "+" : "")\(Int(netVal))")
                                                .font(.ds_labelMedium)
                                        }
                                        .foregroundColor(netColor)
                                    }
                                    .padding(.horizontal, Spacing.xs).padding(.vertical, Spacing.xxs)
                                    .background(
                                        RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous)
                                            .fill(colorScheme == .dark ? Color(white: 0.15) : Color.white)
                                            .shadow(color: .black.opacity(colorScheme == .dark ? 0.4 : 0.15), radius: 8, y: 4)
                                    )
                                    .fixedSize()
                                    .position(x: min(max(xPos, 80), geo.size.width - 80), y: max(originY - 16, 10))
                                }
                            }
                        }
                        .allowsHitTesting(false)
                    }

                    ChartToggleGrid(items: balanceColors, selected: $selectedLines)
                }
            }
            .padding(.horizontal, Spacing.md).padding(.vertical, Spacing.md)
            .sleekCard(cornerRadius: CornerRadius.xl, accentColor: .orange)
        }
        .task(id: timeframe) { await loadBalanceData() }
    }

    private func loadBalanceData() async {
        isLoading = true
        let mealService = MealService.shared
        let calendar = Calendar.current
        let days = timeframe.days
        let context = PersistenceController.shared.container.newBackgroundContext()

        await context.perform {
            let start = calendar.date(byAdding: .day, value: -days, to: Date()) ?? Date()
            let request: NSFetchRequest<Workout> = Workout.fetchRequest()
            request.predicate = NSPredicate(format: "isCompleted == YES AND date >= %@ AND caloriesBurned > 0", start as NSDate)
            request.sortDescriptors = [NSSortDescriptor(keyPath: \Workout.date, ascending: true)]
            request.fetchLimit = 500

            var burnedByDay: [Date: Double] = [:]
            if let results = try? context.fetch(request) {
                for w in results {
                    let day = calendar.startOfDay(for: w.date ?? Date())
                    burnedByDay[day, default: 0] += w.caloriesBurned
                }
            }

            Task { @MainActor in
                var points: [CalorieBalancePoint] = []
                for dayOffset in (0..<days).reversed() {
                    guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: Date()) else { continue }
                    let day = calendar.startOfDay(for: date)
                    let meals = mealService.getMealsForDate(date)
                    let intake = Double(meals.reduce(0) { $0 + $1.calories })
                    let burned = burnedByDay[day] ?? 0
                    if intake > 0 || burned > 0 {
                        points.append(CalorieBalancePoint(date: day, intake: intake, burned: burned))
                    }
                }
                self.dataPoints = points
                self.isLoading = false
            }
        }
    }
}

// MARK: - Timeframe Picker (Shared)

struct StatsTimeframePicker: View {
    @Binding var selected: StatsTimeframe
    var body: some View {
        HStack(spacing: Spacing.xxs) {
            ForEach(StatsTimeframe.allCases, id: \.self) { tf in
                Button {
                    HapticManager.impact(.light)
                    withAnimation(.easeInOut(duration: 0.2)) { selected = tf }
                } label: {
                    Text(tf.rawValue).font(.ds_labelMedium)
                        .foregroundColor(selected == tf ? .white : .adaptiveSecondaryText)
                        .padding(.horizontal, Spacing.sm).padding(.vertical, Spacing.xs)
                        .background(Capsule().fill(selected == tf ? Color.blue : Color.cardBackground))
                }
                .accessibilityLabel("\(tf.rawValue) timeframe")
                .accessibilityHint("Tap to view stats for \(tf.rawValue.lowercased())")
            }
        }
    }
}

// MARK: - 1. Volume Over Time

struct WorkoutVolumeChartWidget: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.colorScheme) private var colorScheme
    @State private var timeframe: StatsTimeframe = .month
    @State private var dataPoints: [VolumeDataPoint] = []
    @State private var previousPeriodPoints: [VolumeDataPoint] = []
    @State private var showComparison = false
    @State private var isLoading = true
    @State private var selectedDate: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                SectionHeader(title: "Volume Over Time", icon: "chart.line.uptrend.xyaxis", iconColor: .blue)
                Spacer()
                Button {
                    HapticManager.impact(.light)
                    withAnimation { showComparison.toggle() }
                } label: {
                    Image(systemName: showComparison ? "arrow.left.arrow.right.circle.fill" : "arrow.left.arrow.right.circle")
                        .font(.ds_bodyLarge).foregroundColor(.blue)
                }
                .accessibilityLabel("Toggle period comparison")
            }

            StatsTimeframePicker(selected: $timeframe)

            VStack(alignment: .leading, spacing: Spacing.sm) {
                if isLoading {
                    chartPlaceholder(height: 200)
                } else if dataPoints.isEmpty {
                    emptyChartState(message: "Complete workouts to see volume trends", height: 200)
                } else {
                    Chart {
                        ForEach(dataPoints) { point in
                            AreaMark(x: .value("Date", point.date), y: .value("Volume", point.volume))
                                .foregroundStyle(LinearGradient(colors: [Color.blue.opacity(0.3), Color.blue.opacity(0.05)], startPoint: .top, endPoint: .bottom))
                                .interpolationMethod(.monotone)
                            LineMark(x: .value("Date", point.date), y: .value("Volume", point.volume))
                                .foregroundStyle(Color.blue).lineStyle(StrokeStyle(lineWidth: 2.5)).interpolationMethod(.monotone)
                        }
                        if showComparison {
                            ForEach(previousPeriodPoints) { point in
                                LineMark(x: .value("Date", point.date), y: .value("Volume", point.volume))
                                    .foregroundStyle(Color.gray.opacity(0.5)).lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 3])).interpolationMethod(.monotone)
                            }
                        }
                    }
                    .frame(height: 200)
                    .chartYAxis { AxisMarks(position: .leading) { value in AxisValueLabel { if let v = value.as(Double.self) { Text(formatAxisVolume(v)).font(.ds_caption) } }; AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3])) } }
                    .chartXAxis { AxisMarks(values: .automatic(desiredCount: 5)) { value in AxisValueLabel { if let d = value.as(Date.self) { Text(shortDateLabel(d, timeframe: timeframe)).font(.ds_caption) } } } }
                    .interactiveLineChart(dataPoints: dataPoints, dateKeyPath: \.date, valueKeyPath: \.volume, label: "Volume", formatValue: { formatAxisVolume($0) + " lbs" }, accentColor: .blue, selectedDate: $selectedDate)
                }
            }
            .padding(.horizontal, Spacing.md).padding(.vertical, Spacing.md)
            .sleekCard(cornerRadius: CornerRadius.xl, accentColor: .blue)
        }
        .task(id: timeframe) { await loadVolumeData() }
    }

    private func loadVolumeData() async {
        isLoading = true
        let context = PersistenceController.shared.container.newBackgroundContext()
        let start = timeframe.startDate
        let prevStart = Calendar.current.date(byAdding: .day, value: -timeframe.days, to: start) ?? start
        await context.perform {
            let request: NSFetchRequest<Workout> = Workout.fetchRequest()
            request.predicate = NSPredicate(format: "isCompleted == YES AND date >= %@", start as NSDate)
            request.sortDescriptors = [NSSortDescriptor(keyPath: \Workout.date, ascending: true)]
            let prevRequest: NSFetchRequest<Workout> = Workout.fetchRequest()
            prevRequest.predicate = NSPredicate(format: "isCompleted == YES AND date >= %@ AND date < %@", prevStart as NSDate, start as NSDate)
            prevRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Workout.date, ascending: true)]
            do {
                let results = try context.fetch(request)
                let grouped = Dictionary(grouping: results) { Calendar.current.startOfDay(for: $0.date ?? Date()) }
                let points = grouped.map { VolumeDataPoint(date: $0.key, volume: $0.value.reduce(0) { $0 + $1.totalVolume }, isPreviousPeriod: false) }.sorted { $0.date < $1.date }
                let prevResults = try context.fetch(prevRequest)
                let prevGrouped = Dictionary(grouping: prevResults) { Calendar.current.startOfDay(for: $0.date ?? Date()) }
                let offset = timeframe.days
                let prevPoints = prevGrouped.map { (date, ws) in VolumeDataPoint(date: Calendar.current.date(byAdding: .day, value: offset, to: date) ?? date, volume: ws.reduce(0) { $0 + $1.totalVolume }, isPreviousPeriod: true) }.sorted { $0.date < $1.date }
                Task { @MainActor in self.dataPoints = points; self.previousPeriodPoints = prevPoints; self.isLoading = false }
            } catch {
                AppLogger.error("Failed to load volume data: \(error.localizedDescription)", category: .data)
                Task { @MainActor in self.isLoading = false }
            }
        }
    }
}

// MARK: - 2. Workout Frequency

struct WorkoutFrequencyChartWidget: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.colorScheme) private var colorScheme
    @State private var timeframe: StatsTimeframe = .month
    @State private var dataPoints: [FrequencyDataPoint] = []
    @State private var isLoading = true
    private let typeColors: [String: Color] = ["Strength": .blue, "Cardio": .cyan, "Stretch": .green, "Plyometrics": .orange, "Other": .purple]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader(title: "Workout Frequency", icon: "calendar.badge.clock", iconColor: .cyan)

            StatsTimeframePicker(selected: $timeframe)

            VStack(alignment: .leading, spacing: Spacing.sm) {
                if isLoading { chartPlaceholder(height: 180) }
                else if dataPoints.isEmpty { emptyChartState(message: "Start working out to track frequency", height: 180) }
                else {
                    Chart(dataPoints) { point in
                        BarMark(x: .value("Date", point.date, unit: timeframe == .week ? .day : .weekOfYear), y: .value("Count", point.count))
                            .foregroundStyle(by: .value("Type", point.workoutType)).cornerRadius(CornerRadius.sm / 2)
                    }
                    .chartForegroundStyleScale(["Strength": Color.blue, "Cardio": Color.cyan, "Stretch": Color.green, "Plyometrics": Color.orange, "Other": Color.purple])
                    .frame(height: 180).chartLegend(position: .bottom, spacing: Spacing.xs)
                    .chartYAxis { AxisMarks(position: .leading) { _ in AxisValueLabel().font(.ds_caption); AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3])) } }
                    .chartXAxis { AxisMarks(values: .automatic(desiredCount: 6)) { value in AxisValueLabel { if let d = value.as(Date.self) { Text(shortDateLabel(d, timeframe: timeframe)).font(.ds_caption) } } } }
                }
            }
            .padding(.horizontal, Spacing.md).padding(.vertical, Spacing.md)
            .sleekCard(cornerRadius: CornerRadius.xl, accentColor: .cyan)
        }
        .task(id: timeframe) { await loadFrequencyData() }
    }

    private func loadFrequencyData() async {
        isLoading = true
        let context = PersistenceController.shared.container.newBackgroundContext()
        let start = timeframe.startDate
        await context.perform {
            let request: NSFetchRequest<Workout> = Workout.fetchRequest()
            request.predicate = NSPredicate(format: "isCompleted == YES AND date >= %@", start as NSDate)
            request.sortDescriptors = [NSSortDescriptor(keyPath: \Workout.date, ascending: true)]
            do {
                let results = try context.fetch(request)
                let points: [FrequencyDataPoint] = results.map { workout in
                    let type = workout.workoutType ?? "Strength"
                    return FrequencyDataPoint(date: Calendar.current.startOfDay(for: workout.date ?? Date()), count: 1, workoutType: typeColors.keys.contains(type) ? type : "Other")
                }
                Task { @MainActor in self.dataPoints = points; self.isLoading = false }
            } catch {
                AppLogger.error("Failed to load frequency data: \(error.localizedDescription)", category: .data)
                Task { @MainActor in self.isLoading = false }
            }
        }
    }
}

// MARK: - 3. Strength Progress

struct StrengthProgressChartWidget: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var timeframe: StatsTimeframe = .threeMonths
    @State private var dataPoints: [StrengthDataPoint] = []
    @State private var selectedExercises: Set<String> = []
    @State private var allExercises: [String] = []
    @State private var isLoading = true
    @State private var selectedDate: Date?
    @State private var showExercisePicker = false
    @State private var searchText = ""
    private let exerciseColors: [Color] = [.blue, .purple, .green, .orange, .cyan]

    private var filteredPoints: [StrengthDataPoint] {
        dataPoints.filter { selectedExercises.contains($0.exerciseName) }
    }

    private var chartYDomain: ClosedRange<Double>? {
        let weights = filteredPoints.map(\.maxWeight)
        guard let minW = weights.min(), let maxW = weights.max() else { return nil }
        if selectedExercises.count == 1 {
            let mid = (minW + maxW) / 2
            let range = max(20, (maxW - minW) * 1.5)
            return (mid - range / 2)...(mid + range / 2)
        }
        let padding = max(10, (maxW - minW) * 0.15)
        return (minW - padding)...(maxW + padding)
    }

    private func colorFor(_ name: String) -> Color {
        guard let idx = allExercises.firstIndex(of: name) else { return .purple }
        return exerciseColors[idx % exerciseColors.count]
    }

    private var selectedLabel: String {
        if selectedExercises.count == 1, let name = selectedExercises.first {
            return shortenExerciseName(name)
        }
        return "\(selectedExercises.count) exercises"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader(title: "Strength Progress", icon: "arrow.up.right.circle.fill", iconColor: .purple)

            StatsTimeframePicker(selected: $timeframe)

            VStack(alignment: .leading, spacing: Spacing.sm) {
                if isLoading { chartPlaceholder(height: 220) }
                else if dataPoints.isEmpty { emptyChartState(message: "Track exercises to see strength trends", height: 220) }
                else {
                    Button {
                        HapticManager.impact(.light)
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { showExercisePicker.toggle() }
                    } label: {
                        HStack(spacing: Spacing.xs) {
                            HStack(spacing: Spacing.xxs) {
                                ForEach(Array(selectedExercises.prefix(3)), id: \.self) { name in
                                    Circle().fill(colorFor(name)).frame(width: 8, height: 8)
                                }
                            }
                            Text(selectedLabel)
                                .font(.ds_labelMedium)
                                .foregroundColor(.adaptiveText)
                            Spacer()
                            Image(systemName: "chevron.down")
                                .font(.ds_labelSmall)
                                .foregroundColor(.adaptiveSecondaryText)
                                .rotationEffect(.degrees(showExercisePicker ? 180 : 0))
                        }
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, Spacing.xs)
                        .background(
                            RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                                .fill(Color.cardBackground)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                                .stroke(Color.adaptiveDivider, lineWidth: 0.5)
                        )
                    }
                    .accessibilityLabel("Select exercises, \(selectedLabel)")
                    .accessibilityHint("Tap to expand exercise list")

                    if showExercisePicker {
                        VStack(spacing: 0) {
                            ForEach(allExercises, id: \.self) { name in
                                let isOn = selectedExercises.contains(name)
                                let color = colorFor(name)
                                Button {
                                    HapticManager.impact(.light)
                                    if isOn {
                                        if selectedExercises.count > 1 { selectedExercises.remove(name) }
                                    } else {
                                        if selectedExercises.count >= 5 {
                                            if let oldest = selectedExercises.first(where: { $0 != name }) {
                                                selectedExercises.remove(oldest)
                                            }
                                        }
                                        selectedExercises.insert(name)
                                    }
                                } label: {
                                    HStack(spacing: Spacing.sm) {
                                        Circle().fill(color).frame(width: 10, height: 10)
                                        Text(shortenExerciseName(name))
                                            .font(.ds_bodyMedium)
                                            .foregroundColor(.adaptiveText)
                                            .lineLimit(1)
                                        Spacer()
                                        if isOn {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.ds_bodyMedium)
                                                .foregroundColor(color)
                                        } else {
                                            Image(systemName: "circle")
                                                .font(.ds_bodyMedium)
                                                .foregroundColor(.adaptiveSecondaryText)
                                        }
                                    }
                                    .padding(.vertical, Spacing.xs)
                                    .padding(.horizontal, Spacing.sm)
                                }

                                if name != allExercises.last {
                                    Divider().padding(.leading, Spacing.xl)
                                }
                            }
                        }
                        .background(
                            RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                                .fill(Color.cardBackground)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                                .stroke(Color.adaptiveDivider, lineWidth: 0.5)
                        )
                        .transition(.opacity.combined(with: .move(edge: .top)))

                        Text("Select up to 5 exercises")
                            .font(.ds_caption)
                            .foregroundColor(.adaptiveSecondaryText)
                    }

                    Chart {
                        ForEach(filteredPoints) { point in
                            LineMark(x: .value("Date", point.date), y: .value("Weight", point.maxWeight))
                                .foregroundStyle(by: .value("Exercise", point.exerciseName))
                                .lineStyle(StrokeStyle(lineWidth: 2.5))
                                .interpolationMethod(.monotone)
                                .symbol(by: .value("Exercise", point.exerciseName))
                        }
                    }
                    .frame(height: 220)
                    .chartForegroundStyleScale(domain: allExercises, range: exerciseColors)
                    .chartLegend(.hidden)
                    .chartYScale(domain: chartYDomain ?? 0...100)
                    .chartYAxis { AxisMarks(position: .leading) { value in AxisValueLabel { if let v = value.as(Double.self) { Text("\(Int(v))").font(.ds_caption) } }; AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3])) } }
                    .chartXAxis { AxisMarks(values: .automatic(desiredCount: 5)) { value in AxisValueLabel { if let d = value.as(Date.self) { Text(shortDateLabel(d, timeframe: timeframe)).font(.ds_caption) } } } }
                    .interactiveLineChart(dataPoints: filteredPoints, dateKeyPath: \.date, valueKeyPath: \.maxWeight, label: "Weight", formatValue: { "\(Int($0)) lbs" }, accentColor: .purple, selectedDate: $selectedDate)
                }
            }
            .padding(.horizontal, Spacing.md).padding(.vertical, Spacing.md)
            .sleekCard(cornerRadius: CornerRadius.xl, accentColor: .purple)
        }
        .task(id: timeframe) { await loadStrengthData() }
    }

    private func loadStrengthData() async {
        isLoading = true
        let context = PersistenceController.shared.container.newBackgroundContext()
        let start = timeframe.startDate
        await context.perform {
            let request: NSFetchRequest<Workout> = Workout.fetchRequest()
            request.predicate = NSPredicate(format: "isCompleted == YES AND date >= %@", start as NSDate)
            request.sortDescriptors = [NSSortDescriptor(keyPath: \Workout.date, ascending: true)]
            do {
                let results = try context.fetch(request)
                var exerciseBests: [String: [(date: Date, weight: Double)]] = [:]
                for workout in results {
                    guard let wExercises = workout.exercises?.allObjects as? [WorkoutExercise], let date = workout.date else { continue }
                    for wEx in wExercises {
                        let exName = (wEx.value(forKey: "exercise") as? NSManagedObject)?.value(forKey: "name") as? String ?? ""
                        guard !exName.isEmpty, let wSets = wEx.sets?.allObjects as? [WorkoutSet] else { continue }
                        let maxW = wSets.compactMap({ $0.weight > 0 ? $0.weight : nil }).max() ?? 0
                        if maxW > 0 { exerciseBests[exName, default: []].append((date: date, weight: maxW)) }
                    }
                }
                let ranked = exerciseBests.sorted { $0.value.count > $1.value.count }
                let allNames = ranked.map { $0.key }
                var points: [StrengthDataPoint] = []
                for (name, entries) in ranked {
                    for entry in entries { points.append(StrengthDataPoint(date: entry.date, maxWeight: entry.weight, exerciseName: name)) }
                }
                let defaultSelected: Set<String> = Set(allNames.prefix(5))
                Task { @MainActor in
                    self.allExercises = allNames
                    if self.selectedExercises.isEmpty { self.selectedExercises = defaultSelected }
                    self.dataPoints = points
                    self.isLoading = false
                }
            } catch {
                AppLogger.error("Failed to load strength data: \(error.localizedDescription)", category: .data)
                Task { @MainActor in self.isLoading = false }
            }
        }
    }
    private func shortenExerciseName(_ name: String) -> String { name.components(separatedBy: "(").first?.trimmingCharacters(in: .whitespaces) ?? name }
}

// MARK: - 4. Personal Records

struct PersonalRecordsWidget: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var records: [PRCardData] = []
    @State private var isLoading = true
    @State private var currentPage = 0
    struct PRCardData: Identifiable { let id = UUID(); let exerciseName: String; let maxWeight: Double; let maxReps: Int; let estimated1RM: Double; let isRecentPR: Bool }

    private var pages: [[PRCardData]] {
        stride(from: 0, to: records.count, by: 4).map { start in Array(records[start..<min(start + 4, records.count)]) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader(title: "Personal Records", icon: "trophy.fill", iconColor: .yellow)

            if isLoading {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: Spacing.sm), GridItem(.flexible(), spacing: Spacing.sm)], spacing: Spacing.sm) {
                    ForEach(0..<4, id: \.self) { _ in RoundedRectangle(cornerRadius: CornerRadius.lg).fill(Color.cardBackground.opacity(0.5)).frame(height: 130) }
                }
            } else if records.isEmpty {
                emptyChartState(message: "Complete workouts to earn personal records", height: 280)
            } else {
                GeometryReader { geo in
                    let cardWidth = geo.size.width
                    HStack(spacing: 0) {
                        ForEach(Array(pages.enumerated()), id: \.offset) { _, page in
                            LazyVGrid(columns: [GridItem(.flexible(), spacing: Spacing.sm), GridItem(.flexible(), spacing: Spacing.sm)], spacing: Spacing.sm) {
                                ForEach(page) { record in StatsPRCard(record: record) }
                            }
                            .frame(width: cardWidth)
                        }
                    }
                    .offset(x: -CGFloat(currentPage) * cardWidth)
                    .animation(.easeOut(duration: 0.25), value: currentPage)
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 25)
                            .onEnded { value in
                                let horizontal = value.translation.width
                                let vertical = abs(value.translation.height)
                                guard abs(horizontal) > vertical * 1.5, abs(horizontal) > 30 else { return }
                                HapticManager.impact(.light)
                                if horizontal < 0, currentPage < pages.count - 1 { currentPage += 1 }
                                else if horizontal > 0, currentPage > 0 { currentPage -= 1 }
                            }
                    )
                }
                .frame(height: 280)

                HStack(spacing: Spacing.xxs) {
                    ForEach(0..<pages.count, id: \.self) { idx in
                        Circle().fill(currentPage == idx ? Color.yellow : Color.gray.opacity(0.3)).frame(width: 6, height: 6)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .task { await loadPRs() }
    }

    private func loadPRs() async {
        isLoading = true
        let context = PersistenceController.shared.container.newBackgroundContext()
        let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        await context.perform {
            let request: NSFetchRequest<Workout> = Workout.fetchRequest()
            request.predicate = NSPredicate(format: "isCompleted == YES")
            request.sortDescriptors = [NSSortDescriptor(keyPath: \Workout.date, ascending: false)]
            request.fetchLimit = 200
            do {
                let results = try context.fetch(request)
                var exercisePRs: [String: (maxWeight: Double, maxReps: Int, date: Date)] = [:]
                for workout in results {
                    guard let wExercises = workout.exercises?.allObjects as? [WorkoutExercise], let date = workout.date else { continue }
                    for wEx in wExercises {
                        let exName = (wEx.value(forKey: "exercise") as? NSManagedObject)?.value(forKey: "name") as? String ?? ""
                        guard !exName.isEmpty, let wSets = wEx.sets?.allObjects as? [WorkoutSet] else { continue }
                        let maxW = wSets.compactMap({ $0.weight > 0 ? $0.weight : nil }).max() ?? 0
                        let maxR = wSets.compactMap({ $0.reps > 0 ? Int($0.reps) : nil }).max() ?? 0
                        if let existing = exercisePRs[exName] {
                            if maxW > existing.maxWeight { exercisePRs[exName] = (maxW, max(maxR, existing.maxReps), date) }
                            else if maxR > existing.maxReps { exercisePRs[exName] = (max(maxW, existing.maxWeight), maxR, date) }
                        } else { exercisePRs[exName] = (maxW, maxR, date) }
                    }
                }
                let sorted = exercisePRs.sorted { $0.value.maxWeight > $1.value.maxWeight }.prefix(8)
                let cards = sorted.map { (name, data) in
                    let e1rm = data.maxReps > 0 ? data.maxWeight * (1 + Double(data.maxReps) / 30.0) : data.maxWeight
                    return PRCardData(exerciseName: name, maxWeight: data.maxWeight, maxReps: data.maxReps, estimated1RM: e1rm, isRecentPR: data.date >= sevenDaysAgo)
                }
                Task { @MainActor in self.records = cards; self.isLoading = false }
            } catch {
                AppLogger.error("Failed to load PRs: \(error.localizedDescription)", category: .data)
                Task { @MainActor in self.isLoading = false }
            }
        }
    }
}

private struct StatsPRCard: View {
    let record: PersonalRecordsWidget.PRCardData
    private var displayName: String { record.exerciseName.components(separatedBy: "(").first?.trimmingCharacters(in: .whitespaces) ?? record.exerciseName }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack {
                Text(displayName).font(.ds_labelMedium).foregroundColor(.adaptiveText).lineLimit(1).minimumScaleFactor(0.75)
                Spacer(minLength: Spacing.xxs)
                if record.isRecentPR { Image(systemName: "star.fill").font(.ds_labelSmall).foregroundColor(.yellow) }
            }
            Divider()
            HStack(spacing: Spacing.sm) {
                VStack(alignment: .leading, spacing: Spacing.xxxs) {
                    Text("MAX").font(.ds_caption).foregroundColor(.adaptiveSecondaryText)
                    Text("\(Int(record.maxWeight))").font(.ds_statSmall).foregroundColor(.adaptiveText)
                    Text("lbs").font(.ds_caption).foregroundColor(.adaptiveSecondaryText)
                }
                VStack(alignment: .leading, spacing: Spacing.xxxs) {
                    Text("REPS").font(.ds_caption).foregroundColor(.adaptiveSecondaryText)
                    Text("\(record.maxReps)").font(.ds_statSmall).foregroundColor(.adaptiveText)
                    Text("best").font(.ds_caption).foregroundColor(.adaptiveSecondaryText)
                }
                Spacer()
            }
            HStack(spacing: Spacing.xxs) {
                Text("1RM").font(.ds_caption).foregroundColor(.adaptiveSecondaryText)
                Text("\(Int(record.estimated1RM)) lbs").font(.ds_labelSmall).foregroundColor(.blue)
            }
        }
        .padding(Spacing.sm).frame(maxWidth: .infinity, alignment: .leading)
        .sleekCard(cornerRadius: CornerRadius.lg, accentColor: record.isRecentPR ? .yellow : .gray)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 5. Body Weight Trend

struct BodyWeightTrendWidget: View {
    @StateObject private var weightService = WeightTrackingService.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedDate: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                SectionHeader(title: "Body Weight", icon: "scalemass.fill", iconColor: .green)
                Spacer()
                if let stats = weightService.statistics {
                    let change = stats.monthlyChange
                    HStack(spacing: Spacing.xxxs) {
                        Image(systemName: change >= 0 ? "arrow.up.right" : "arrow.down.right")
                        Text(String(format: "%+.1f lbs/mo", change))
                    }
                    .font(.ds_labelSmall).foregroundColor(change > 0 ? .green : change < 0 ? .orange : .adaptiveSecondaryText)
                }
            }

            VStack(alignment: .leading, spacing: Spacing.sm) {
                if weightService.monthlyTrend.isEmpty && weightService.recentLogs.isEmpty {
                    emptyChartState(message: "Log your weight to see trends", height: 180)
                } else {
                    let trendData = weightService.monthlyTrend.isEmpty ? weightService.recentLogs.map { WeightTrendPoint(date: $0.loggedAt, weight: $0.weightLbs) } : weightService.monthlyTrend
                    Chart {
                        ForEach(trendData) { point in
                            LineMark(x: .value("Date", point.date), y: .value("Weight", point.weight)).foregroundStyle(Color.green).lineStyle(StrokeStyle(lineWidth: 2.5)).interpolationMethod(.monotone)
                            PointMark(x: .value("Date", point.date), y: .value("Weight", point.weight)).foregroundStyle(point.isProjected ? Color.green.opacity(0.4) : Color.green).symbolSize(point.isProjected ? 20 : 30)
                        }
                        if let goal = weightService.weightGoal {
                            RuleMark(y: .value("Goal", goal.targetWeight)).foregroundStyle(Color.orange).lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                                .annotation(position: .top, alignment: .trailing) { Text("Goal: \(Int(goal.targetWeight))").font(.ds_caption).foregroundColor(.orange) }
                        }
                    }
                    .frame(height: 180).chartYScale(domain: yAxisDomain(trendData))
                    .chartYAxis { AxisMarks(position: .leading) { value in AxisValueLabel { if let v = value.as(Double.self) { Text("\(Int(v))").font(.ds_caption) } }; AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3])) } }
                    .chartXAxis { AxisMarks(values: .automatic(desiredCount: 5)) { value in AxisValueLabel { if let d = value.as(Date.self) { Text(shortDateLabel(d, timeframe: .month)).font(.ds_caption) } } } }
                    .interactiveLineChart(dataPoints: trendData, dateKeyPath: \.date, valueKeyPath: \.weight, label: "Weight", formatValue: { String(format: "%.1f lbs", $0) }, accentColor: .green, selectedDate: $selectedDate)
                }
            }
            .padding(.horizontal, Spacing.md).padding(.vertical, Spacing.md)
            .sleekCard(cornerRadius: CornerRadius.xl, accentColor: .green)
        }
        .accessibilityElement(children: .contain).accessibilityLabel("Body weight trend chart")
    }

    private func yAxisDomain(_ data: [WeightTrendPoint]) -> ClosedRange<Double> {
        var allValues = data.map(\.weight)
        if let g = weightService.weightGoal?.targetWeight { allValues.append(g) }
        guard let minW = allValues.min(), let maxW = allValues.max() else { return 100...200 }
        let padding = max(5, (maxW - minW) * 0.15)
        return (minW - padding)...(maxW + padding)
    }
}

// MARK: - 7. Workout Duration

struct WorkoutDurationChartWidget: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.colorScheme) private var colorScheme
    @State private var timeframe: StatsTimeframe = .month
    @State private var dataPoints: [CalorieDurationPoint] = []
    @State private var isLoading = true

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                SectionHeader(title: "Workout Duration", icon: "timer", iconColor: .green)
                Spacer()
                if !dataPoints.isEmpty {
                    let avg = dataPoints.reduce(0) { $0 + $1.duration } / max(1, dataPoints.count)
                    Text("Avg: \(avg) min").font(.ds_labelSmall).foregroundColor(.green)
                }
            }

            StatsTimeframePicker(selected: $timeframe)

            VStack(alignment: .leading, spacing: Spacing.sm) {
                if isLoading { chartPlaceholder(height: 180) }
                else if dataPoints.isEmpty { emptyChartState(message: "Complete workouts to track duration", height: 180) }
                else {
                    let avgDur = Double(dataPoints.reduce(0) { $0 + $1.duration }) / max(1, Double(dataPoints.count))
                    Chart {
                        ForEach(dataPoints) { point in
                            BarMark(x: .value("Date", point.date, unit: .day), y: .value("Minutes", point.duration))
                                .foregroundStyle(LinearGradient(colors: [Color(red: 0.2, green: 0.7, blue: 0.3), .blue], startPoint: .top, endPoint: .bottom)).cornerRadius(CornerRadius.sm / 2)
                        }
                        RuleMark(y: .value("Average", avgDur)).foregroundStyle(Color.adaptiveSecondaryText.opacity(0.6)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                            .annotation(position: .top, alignment: .leading) { Text("Avg: \(Int(avgDur)) min").font(.ds_caption).foregroundColor(.adaptiveSecondaryText) }
                    }
                    .frame(height: 180)
                    .chartYAxis { AxisMarks(position: .leading) { _ in AxisValueLabel().font(.ds_caption); AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3])) } }
                    .chartXAxis { AxisMarks(values: .automatic(desiredCount: 6)) { value in AxisValueLabel { if let d = value.as(Date.self) { Text(shortDateLabel(d, timeframe: timeframe)).font(.ds_caption) } } } }
                }
            }
            .padding(.horizontal, Spacing.md).padding(.vertical, Spacing.md)
            .sleekCard(cornerRadius: CornerRadius.xl, accentColor: .green)
        }
        .task(id: timeframe) { await loadDurationData() }
    }

    private func loadDurationData() async {
        isLoading = true
        let context = PersistenceController.shared.container.newBackgroundContext()
        let start = timeframe.startDate
        await context.perform {
            let request: NSFetchRequest<Workout> = Workout.fetchRequest()
            request.predicate = NSPredicate(format: "isCompleted == YES AND date >= %@ AND duration > 0", start as NSDate)
            request.sortDescriptors = [NSSortDescriptor(keyPath: \Workout.date, ascending: true)]
            do {
                let results = try context.fetch(request)
                let points = results.map { CalorieDurationPoint(date: Calendar.current.startOfDay(for: $0.date ?? Date()), calories: $0.caloriesBurned, duration: Int($0.duration) / 60) }
                Task { @MainActor in self.dataPoints = points; self.isLoading = false }
            } catch {
                AppLogger.error("Failed to load duration data: \(error.localizedDescription)", category: .data)
                Task { @MainActor in self.isLoading = false }
            }
        }
    }
}

// MARK: - 8. Muscle Group Distribution

struct MuscleGroupDistributionWidget: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var slices: [MuscleGroupSlice] = []
    @State private var isLoading = true
    @State private var selectedSlice: String?
    private static let categoryColors: [String: Color] = ["Chest": .red, "Back": .blue, "Legs": .green, "Shoulders": .purple, "Arms": .orange, "Core": .yellow, "Full Body": .cyan, "Cardio": .mint, "Neck": .gray, "Hips": .pink]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader(title: "Muscle Group Focus", icon: "figure.strengthtraining.traditional", iconColor: .red)

            VStack(alignment: .leading, spacing: Spacing.sm) {
                if isLoading { chartPlaceholder(height: 160) }
                else if slices.isEmpty { emptyChartState(message: "Work out to see muscle distribution", height: 160) }
                else {
                    HStack(spacing: Spacing.md) {
                        Chart(slices) { slice in
                            SectorMark(angle: .value("Count", slice.count), innerRadius: .ratio(0.55), angularInset: 1.5)
                                .foregroundStyle(slice.color).cornerRadius(CornerRadius.sm / 2)
                                .opacity(selectedSlice == nil || selectedSlice == slice.category ? 1.0 : 0.4)
                        }
                        .frame(width: 150, height: 150)
                        .chartBackground { _ in
                            if let selected = selectedSlice, let slice = slices.first(where: { $0.category == selected }) {
                                VStack(spacing: Spacing.xxxs) { Text("\(slice.count)").font(.ds_statSmall).foregroundColor(.adaptiveText); Text(slice.category).font(.ds_caption).foregroundColor(.adaptiveSecondaryText) }
                            } else {
                                VStack(spacing: Spacing.xxxs) { Text("\(slices.reduce(0) { $0 + $1.count })").font(.ds_statSmall).foregroundColor(.adaptiveText); Text("exercises").font(.ds_caption).foregroundColor(.adaptiveSecondaryText) }
                            }
                        }

                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            ForEach(slices.prefix(6)) { slice in
                                Button {
                                    HapticManager.impact(.light)
                                    withAnimation(.easeInOut(duration: 0.2)) { selectedSlice = selectedSlice == slice.category ? nil : slice.category }
                                } label: {
                                    HStack(spacing: Spacing.xs) {
                                        Circle().fill(slice.color).frame(width: 8, height: 8)
                                        Text(slice.category).font(.ds_labelSmall).foregroundColor(.adaptiveText)
                                        Spacer()
                                        Text("\(slice.count)").font(.ds_labelSmall).foregroundColor(.adaptiveSecondaryText)
                                    }
                                }
                                .accessibilityLabel("\(slice.category): \(slice.count) exercises")
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, Spacing.md).padding(.vertical, Spacing.md)
            .sleekCard(cornerRadius: CornerRadius.xl, accentColor: .red)
        }
        .task { await loadMuscleData() }
    }

    private func loadMuscleData() async {
        isLoading = true
        let context = PersistenceController.shared.container.newBackgroundContext()
        let threeMonthsAgo = Calendar.current.date(byAdding: .month, value: -3, to: Date()) ?? Date()
        await context.perform {
            let request: NSFetchRequest<Workout> = Workout.fetchRequest()
            request.predicate = NSPredicate(format: "isCompleted == YES AND date >= %@", threeMonthsAgo as NSDate)
            request.fetchLimit = 100
            do {
                let results = try context.fetch(request)
                var categoryCounts: [String: Int] = [:]
                for workout in results {
                    guard let wExercises = workout.exercises?.allObjects as? [WorkoutExercise] else { continue }
                    for wEx in wExercises {
                        let cat = (wEx.value(forKey: "exercise") as? NSManagedObject)?.value(forKey: "category") as? String ?? "Other"
                        categoryCounts[cat, default: 0] += 1
                    }
                }
                let sorted = categoryCounts.sorted { $0.value > $1.value }.map { MuscleGroupSlice(category: $0.key, count: $0.value, color: Self.categoryColors[$0.key] ?? .gray) }
                Task { @MainActor in self.slices = sorted; self.isLoading = false }
            } catch {
                AppLogger.error("Failed to load muscle data: \(error.localizedDescription)", category: .data)
                Task { @MainActor in self.isLoading = false }
            }
        }
    }
}

// MARK: - Interactive Chart Tooltip

struct ChartTooltipData {
    let date: Date
    let label: String
    let value: String
    let previousValue: Double?
    let currentValue: Double
    let accentColor: Color
}

private struct ChartTooltipBubble: View {
    let data: ChartTooltipData
    @Environment(\.colorScheme) private var colorScheme

    private static let tooltipDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    private var trend: (icon: String, color: Color)? {
        guard let prev = data.previousValue, prev > 0 else { return nil }
        let diff = data.currentValue - prev
        if diff > 0 { return ("arrow.up.right", .green) }
        if diff < 0 { return ("arrow.down.right", .red) }
        return ("equal", .adaptiveSecondaryText)
    }

    private var changeText: String? {
        guard let prev = data.previousValue, prev > 0 else { return nil }
        let pct = ((data.currentValue - prev) / prev) * 100
        return String(format: "%+.0f%%", pct)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(Self.tooltipDateFormatter.string(from: data.date))
                .font(.ds_caption).foregroundColor(.adaptiveSecondaryText)
            HStack(spacing: 3) {
                Text(data.value).font(.ds_labelMedium).foregroundColor(.adaptiveText)
                if let trend = trend, let change = changeText {
                    Image(systemName: trend.icon).font(.system(size: 8, weight: .bold)).foregroundColor(trend.color)
                    Text(change).font(.ds_caption).foregroundColor(trend.color)
                }
            }
        }
        .padding(.horizontal, Spacing.xs).padding(.vertical, Spacing.xxs)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous)
                .fill(colorScheme == .dark ? Color(white: 0.15) : Color.white)
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.4 : 0.15), radius: 8, y: 4)
        )
        .fixedSize()
    }
}

private struct InteractiveLineChartModifier<DataPoint>: ViewModifier {
    let dataPoints: [DataPoint]
    let dateKeyPath: KeyPath<DataPoint, Date>
    let valueKeyPath: KeyPath<DataPoint, Double>
    let label: String
    let formatValue: (Double) -> String
    let accentColor: Color
    @Binding var selectedDate: Date?
    @State private var rawSelection: Date?

    func body(content: Content) -> some View {
        content
            .chartXSelection(value: $rawSelection)
            .onChange(of: rawSelection) { _, newValue in
                guard let newValue else {
                    withAnimation(.easeOut(duration: 0.15)) { selectedDate = nil }
                    return
                }
                guard let nearest = findNearest(to: newValue) else { return }
                let snapped = nearest[keyPath: dateKeyPath]
                let shouldHaptic: Bool = {
                    guard let current = selectedDate else { return true }
                    return !Calendar.current.isDate(current, inSameDayAs: snapped)
                }()
                selectedDate = snapped
                if shouldHaptic { HapticManager.impact(.light) }
            }
            .chartOverlay { proxy in
                GeometryReader { geo in
                    if let selectedDate = selectedDate,
                       let match = dataPoints.first(where: { Calendar.current.isDate($0[keyPath: dateKeyPath], inSameDayAs: selectedDate) }) {

                        let plotFrame = geo[proxy.plotFrame!]
                        let originX = plotFrame.origin.x
                        let originY = plotFrame.origin.y

                        if let rawX = proxy.position(forX: match[keyPath: dateKeyPath]),
                           let rawY = proxy.position(forY: match[keyPath: valueKeyPath]) {

                            let xPos = originX + rawX
                            let yPos = originY + rawY

                            let idx = dataPoints.firstIndex(where: { Calendar.current.isDate($0[keyPath: dateKeyPath], inSameDayAs: selectedDate) })
                            let prevValue: Double? = (idx != nil && idx! > 0) ? dataPoints[idx! - 1][keyPath: valueKeyPath] : nil

                            let tooltip = ChartTooltipData(
                                date: match[keyPath: dateKeyPath],
                                label: label,
                                value: formatValue(match[keyPath: valueKeyPath]),
                                previousValue: prevValue,
                                currentValue: match[keyPath: valueKeyPath],
                                accentColor: accentColor
                            )

                            Rectangle()
                                .fill(accentColor.opacity(0.4))
                                .frame(width: 1, height: plotFrame.height)
                                .position(x: xPos, y: originY + plotFrame.height / 2)

                            Circle()
                                .fill(accentColor)
                                .frame(width: 8, height: 8)
                                .shadow(color: accentColor.opacity(0.5), radius: 4)
                                .position(x: xPos, y: yPos)

                            ChartTooltipBubble(data: tooltip)
                                .position(
                                    x: min(max(xPos, 70), geo.size.width - 70),
                                    y: max(originY - 16, 10)
                                )
                        }
                    }
                }
                .allowsHitTesting(false)
            }
    }

    private func findNearest(to date: Date) -> DataPoint? {
        dataPoints.min(by: { abs($0[keyPath: dateKeyPath].timeIntervalSince(date)) < abs($1[keyPath: dateKeyPath].timeIntervalSince(date)) })
    }
}

extension View {
    func interactiveLineChart<T>(
        dataPoints: [T],
        dateKeyPath: KeyPath<T, Date>,
        valueKeyPath: KeyPath<T, Double>,
        label: String,
        formatValue: @escaping (Double) -> String,
        accentColor: Color,
        selectedDate: Binding<Date?>
    ) -> some View {
        modifier(InteractiveLineChartModifier(
            dataPoints: dataPoints, dateKeyPath: dateKeyPath, valueKeyPath: valueKeyPath,
            label: label, formatValue: formatValue, accentColor: accentColor, selectedDate: selectedDate
        ))
    }
}

// MARK: - Reusable Toggle Button Grid

private struct ChartToggleGrid: View {
    let items: [(name: String, color: Color)]
    @Binding var selected: Set<String>

    private let columns = [
        GridItem(.flexible(), spacing: Spacing.xs),
        GridItem(.flexible(), spacing: Spacing.xs)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: Spacing.xs) {
            ForEach(items, id: \.name) { item in
                let isOn = selected.contains(item.name)
                Button {
                    HapticManager.impact(.light)
                    if isOn && selected.count > 1 { selected.remove(item.name) }
                    else { selected.insert(item.name) }
                } label: {
                    HStack(spacing: Spacing.xs) {
                        Circle().fill(item.color).frame(width: 10, height: 10)
                        Text(item.name).font(.ds_labelMedium).foregroundColor(isOn ? .adaptiveText : .adaptiveSecondaryText)
                        Spacer()
                        if isOn {
                            Image(systemName: "checkmark").font(.ds_labelSmall).foregroundColor(item.color)
                        }
                    }
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.xs)
                    .background(
                        RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                            .fill(isOn ? item.color.opacity(0.12) : Color.cardBackground.opacity(0.5))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                            .stroke(isOn ? item.color.opacity(0.4) : Color.adaptiveDivider, lineWidth: isOn ? 1.5 : 0.5)
                    )
                }
                .scaleButtonStyle(.subtle, withHaptic: false)
                .accessibilityLabel("\(item.name), \(isOn ? "selected" : "deselected")")
            }
        }
    }
}

// MARK: - Shared Helpers

private func chartPlaceholder(height: CGFloat = 180) -> some View {
    RoundedRectangle(cornerRadius: CornerRadius.sm).fill(Color.cardBackground.opacity(0.5)).frame(height: height)
        .overlay { ProgressView().tint(.adaptiveSecondaryText) }
}

private func emptyChartState(message: String, height: CGFloat = 180) -> some View {
    VStack(spacing: Spacing.sm) {
        Image(systemName: "chart.line.downtrend.xyaxis").font(.ds_heading1).foregroundColor(.adaptiveSecondaryText)
        Text(message).font(.ds_bodyMedium).foregroundColor(.adaptiveSecondaryText).multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity).frame(height: height)
}

private func shortDateLabel(_ date: Date, timeframe: StatsTimeframe) -> String {
    let formatter = DateFormatter()
    switch timeframe {
    case .week: formatter.dateFormat = "EEE"
    case .month, .threeMonths: formatter.dateFormat = "M/d"
    case .year, .all: formatter.dateFormat = "MMM"
    }
    return formatter.string(from: date)
}

private func formatAxisVolume(_ value: Double) -> String {
    if value >= 1_000_000 { return String(format: "%.1fM", value / 1_000_000) }
    if value >= 1_000 { return String(format: "%.0fK", value / 1_000) }
    return "\(Int(value))"
}
