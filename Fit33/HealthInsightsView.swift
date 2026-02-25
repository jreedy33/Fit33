//
//  HealthInsightsView.swift
//  Fit33
//
//  Comprehensive health insights aggregating Fitbit, Strava, and app data
//  Beautiful charts and trends for sleep, heart rate, activity, and more
//

import SwiftUI
import Charts

// MARK: - Health Insights View

struct HealthInsightsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var healthService = HealthDataService.shared
    @StateObject private var fitbit = FitbitService.shared
    @StateObject private var strava = StravaService.shared
    
    @State private var selectedTimeRange: TimeRange = .week
    
    enum TimeRange: String, CaseIterable {
        case week = "7D"
        case twoWeeks = "14D"
        case month = "30D"
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header with connected sources
                headerSection
                
                // Time range picker
                timeRangePicker
                
                // Today's Summary Card
                todaySummaryCard
                
                // Activity Trends (Steps + Calories)
                activityTrendsCard
                
                // Heart Rate Section
                if !healthService.weeklyHeartRateData.isEmpty || fitbit.isConnected {
                    heartRateCard
                }
                
                // Sleep Section
                if !healthService.recentSleepLogs.isEmpty || fitbit.isConnected {
                    sleepCard
                }
                
                // Weekly Workout Summary
                workoutSummaryCard
                
                // Heart Rate Zones
                if healthService.todayHeartRate != nil {
                    heartRateZonesCard
                }
                
                // Data Sources Footer
                dataSourcesFooter
            }
            .padding()
        }
        .background(
            LinearGradient(
                colors: colorScheme == .dark
                    ? [Color(red: 0.08, green: 0.08, blue: 0.12), Color(red: 0.05, green: 0.05, blue: 0.08)]
                    : [Color(red: 0.95, green: 0.97, blue: 1.0), Color.white],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .navigationTitle("Health Insights")
        .navigationBarTitleDisplayMode(.large)
        .refreshable {
            // Force sync when user pulls to refresh
            await healthService.syncAllHealthData(force: true)
        }
        .onAppear {
            // Only sync on appear if we have no data (throttling prevents repeated syncs)
            if healthService.todaySummary == nil {
                Task {
                    await healthService.syncAllHealthData()
                }
            }
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Your Health")
                    .font(.title2)
                    .fontWeight(.bold)
                
                if let lastSync = healthService.lastSyncDate {
                    Text("Updated \(lastSync.formatted(.relative(presentation: .named)))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Connected sources badges
            HStack(spacing: 8) {
                if fitbit.isConnected {
                    sourceBadge(name: "Fitbit", color: Color(red: 0, green: 0.73, blue: 0.77))
                }
                if strava.isConnected {
                    sourceBadge(name: "Strava", color: Color(red: 252/255, green: 76/255, blue: 2/255))
                }
            }
        }
        .padding()
        .background(cardBackground)
        .cornerRadius(16)
    }
    
    private func sourceBadge(name: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(name)
                .font(.caption2)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.15))
        .cornerRadius(8)
    }
    
    // MARK: - Time Range Picker
    
    private var timeRangePicker: some View {
        HStack(spacing: 0) {
            ForEach(TimeRange.allCases, id: \.self) { range in
                Button(action: { selectedTimeRange = range }) {
                    Text(range.rawValue)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(selectedTimeRange == range ? Color.accentColor : Color.clear)
                        .foregroundColor(selectedTimeRange == range ? .white : .secondary)
                }
            }
        }
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(10)
    }
    
    // MARK: - Today's Summary Card
    
    private var todaySummaryCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Today")
                .font(.headline)
                .fontWeight(.semibold)
            
            HStack(spacing: 16) {
                // Steps
                summaryMetric(
                    icon: "figure.walk",
                    value: formatNumber(healthService.todaySummary?.steps ?? fitbit.todaySteps),
                    label: "Steps",
                    goal: 10000,
                    current: healthService.todaySummary?.steps ?? fitbit.todaySteps,
                    color: .blue
                )
                
                // Calories
                summaryMetric(
                    icon: "flame.fill",
                    value: formatNumber(healthService.todaySummary?.caloriesBurned ?? fitbit.todayCalories),
                    label: "Calories",
                    goal: nil,
                    current: nil,
                    color: .orange
                )
                
                // Active Minutes
                summaryMetric(
                    icon: "bolt.fill",
                    value: "\(healthService.totalActiveMinutesToday)",
                    label: "Active Min",
                    goal: 30,
                    current: healthService.totalActiveMinutesToday,
                    color: .green
                )
            }
        }
        .padding()
        .background(cardBackground)
        .cornerRadius(16)
    }
    
    private func summaryMetric(icon: String, value: String, label: String, goal: Int?, current: Int?, color: Color) -> some View {
        VStack(spacing: 8) {
            ZStack {
                // Progress ring if goal exists
                if let goal = goal, let current = current {
                    Circle()
                        .stroke(color.opacity(0.2), lineWidth: 4)
                        .frame(width: 50, height: 50)
                    
                    Circle()
                        .trim(from: 0, to: min(CGFloat(current) / CGFloat(goal), 1.0))
                        .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .frame(width: 50, height: 50)
                        .rotationEffect(.degrees(-90))
                }
                
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(color)
            }
            .frame(width: 50, height: 50)
            
            Text(value)
                .font(.headline)
                .fontWeight(.bold)
            
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Activity Trends Card
    
    private var activityTrendsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Activity Trends")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Text("Avg: \(formatNumber(healthService.weeklyStepsAverage)) steps")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if healthService.weeklyActivityData.isEmpty {
                emptyStateView(message: "Connect Fitbit or Strava to see activity trends")
            } else {
                // Steps Chart
                Chart {
                    ForEach(healthService.weeklyActivityData.reversed()) { day in
                        BarMark(
                            x: .value("Day", formatDate(day.date)),
                            y: .value("Steps", day.steps)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.blue, .cyan],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                        .cornerRadius(4)
                    }
                    
                    // Goal line
                    RuleMark(y: .value("Goal", 10000))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5]))
                        .foregroundStyle(.green.opacity(0.7))
                }
                .frame(height: 180)
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisValueLabel {
                            if let intValue = value.as(Int.self) {
                                Text("\(intValue / 1000)k")
                                    .font(.caption2)
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .background(cardBackground)
        .cornerRadius(16)
    }
    
    // MARK: - Heart Rate Card
    
    private var heartRateCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "heart.fill")
                    .foregroundColor(.red)
                Text("Heart Rate")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                if let avgHR = healthService.avgRestingHeartRate {
                    HStack(spacing: 4) {
                        Image(systemName: healthService.restingHRTrend.icon)
                            .font(.caption)
                            .foregroundColor(healthService.restingHRTrend.color)
                        Text("Avg: \(avgHR) bpm")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            if healthService.weeklyHeartRateData.isEmpty {
                emptyStateView(message: "Connect Fitbit to track heart rate")
            } else {
                // Resting HR Chart
                Chart {
                    ForEach(healthService.weeklyHeartRateData.reversed()) { day in
                        if let hr = day.restingHeartRate {
                            LineMark(
                                x: .value("Day", formatDate(day.date)),
                                y: .value("HR", hr)
                            )
                            .foregroundStyle(.red)
                            .interpolationMethod(.catmullRom)
                            
                            PointMark(
                                x: .value("Day", formatDate(day.date)),
                                y: .value("HR", hr)
                            )
                            .foregroundStyle(.red)
                            .symbolSize(30)
                        }
                    }
                }
                .frame(height: 150)
                .chartYScale(domain: 50...100)
                
                // Today's resting HR highlight
                if let todayHR = healthService.todayHeartRate?.restingHeartRate {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Today's Resting HR")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text("\(todayHR)")
                                    .font(.title)
                                    .fontWeight(.bold)
                                    .foregroundColor(.red)
                                Text("bpm")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Spacer()
                        
                        hrZoneIndicator(hr: todayHR)
                    }
                    .padding(.top, 8)
                }
            }
        }
        .padding()
        .background(cardBackground)
        .cornerRadius(16)
    }
    
    private func hrZoneIndicator(hr: Int) -> some View {
        let (zone, color) = getHRZone(hr)
        return VStack(alignment: .trailing) {
            Text(zone)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(color)
            Text("zone")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(color.opacity(0.15))
        .cornerRadius(8)
    }
    
    private func getHRZone(_ hr: Int) -> (String, Color) {
        if hr < 60 { return ("Athletic", .green) }
        if hr < 70 { return ("Excellent", .blue) }
        if hr < 80 { return ("Good", .cyan) }
        if hr < 90 { return ("Average", .yellow) }
        return ("Above Avg", .orange)
    }
    
    // MARK: - Sleep Card
    
    private var sleepCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "bed.double.fill")
                    .foregroundColor(.indigo)
                Text("Sleep")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                HStack(spacing: 4) {
                    Image(systemName: healthService.sleepTrend.icon)
                        .font(.caption)
                        .foregroundColor(healthService.sleepTrend.color)
                    Text(String(format: "Avg: %.1fh", healthService.averageSleepHours))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            if healthService.recentSleepLogs.isEmpty {
                emptyStateView(message: "Connect Fitbit to track sleep")
            } else {
                // Sleep duration chart
                Chart {
                    ForEach(healthService.recentSleepLogs.prefix(7).reversed()) { sleep in
                        BarMark(
                            x: .value("Day", formatDate(sleep.dateOfSleep)),
                            y: .value("Hours", sleep.sleepHours)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.indigo, .purple],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                        .cornerRadius(4)
                    }
                    
                    // 8 hour goal line
                    RuleMark(y: .value("Goal", 8))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5]))
                        .foregroundStyle(.green.opacity(0.7))
                }
                .frame(height: 150)
                .chartYScale(domain: 0...12)
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisValueLabel {
                            if let hours = value.as(Double.self) {
                                Text("\(Int(hours))h")
                                    .font(.caption2)
                            }
                        }
                    }
                }
                
                // Last night's sleep detail
                if let lastSleep = healthService.recentSleepLogs.first {
                    HStack(spacing: 20) {
                        sleepStat(
                            label: "Duration",
                            value: String(format: "%.1fh", lastSleep.sleepHours),
                            color: .indigo
                        )
                        
                        if let efficiency = lastSleep.efficiency {
                            sleepStat(
                                label: "Efficiency",
                                value: "\(efficiency)%",
                                color: efficiency >= 85 ? .green : .orange
                            )
                        }
                        
                        if let deep = lastSleep.deepSleepMinutes {
                            sleepStat(
                                label: "Deep Sleep",
                                value: "\(deep)m",
                                color: .purple
                            )
                        }
                    }
                    .padding(.top, 8)
                }
            }
        }
        .padding()
        .background(cardBackground)
        .cornerRadius(16)
    }
    
    private func sleepStat(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(color)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Workout Summary Card
    
    private var workoutSummaryCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "figure.run")
                    .foregroundColor(.orange)
                Text("Weekly Workouts")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Text("From all sources")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            HStack(spacing: 16) {
                workoutStatCard(
                    icon: "number",
                    value: "\(healthService.weeklyWorkoutCount)",
                    label: "Workouts",
                    color: .orange
                )
                
                workoutStatCard(
                    icon: "timer",
                    value: "\(healthService.weeklyCardioMinutes)",
                    label: "Minutes",
                    color: .green
                )
                
                workoutStatCard(
                    icon: "flame.fill",
                    value: formatNumber(healthService.weeklyCaloriesBurned),
                    label: "Calories",
                    color: .red
                )
            }
        }
        .padding()
        .background(cardBackground)
        .cornerRadius(16)
    }
    
    private func workoutStatCard(icon: String, value: String, label: String, color: Color) -> some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(color.opacity(0.15))
                    .frame(width: 44, height: 44)
                
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(color)
            }
            
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
            
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Heart Rate Zones Card
    
    private var heartRateZonesCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Heart Rate Zones")
                .font(.headline)
                .fontWeight(.semibold)
            
            if let hr = healthService.todayHeartRate {
                VStack(spacing: 12) {
                    hrZoneRow(name: "Peak", minutes: hr.peakMinutes, color: .red, icon: "bolt.fill")
                    hrZoneRow(name: "Cardio", minutes: hr.cardioMinutes, color: .orange, icon: "heart.fill")
                    hrZoneRow(name: "Fat Burn", minutes: hr.fatBurnMinutes, color: .yellow, icon: "flame.fill")
                    hrZoneRow(name: "Out of Range", minutes: hr.outOfRangeMinutes, color: .gray, icon: "figure.stand")
                }
            }
        }
        .padding()
        .background(cardBackground)
        .cornerRadius(16)
    }
    
    private func hrZoneRow(name: String, minutes: Int, color: Color, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 20)
            
            Text(name)
                .font(.subheadline)
            
            Spacer()
            
            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color.opacity(0.2))
                        .frame(height: 8)
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color)
                        .frame(width: min(CGFloat(minutes) / 60.0 * geo.size.width, geo.size.width), height: 8)
                }
            }
            .frame(width: 80, height: 8)
            
            Text("\(minutes)m")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 40, alignment: .trailing)
        }
    }
    
    // MARK: - Data Sources Footer
    
    private var dataSourcesFooter: some View {
        VStack(spacing: 12) {
            Text("Data Sources")
                .font(.caption)
                .foregroundColor(.secondary)
            
            HStack(spacing: 20) {
                if fitbit.isConnected {
                    dataSourceItem(name: "Fitbit", icon: "heart.circle.fill", color: Color(red: 0, green: 0.73, blue: 0.77))
                }
                if strava.isConnected {
                    dataSourceItem(name: "Strava", icon: "figure.run", color: Color(red: 252/255, green: 76/255, blue: 2/255))
                }
                dataSourceItem(name: "Fit33", icon: "dumbbell.fill", color: .blue)
            }
            
            if !fitbit.isConnected && !strava.isConnected {
                Text("Connect Fitbit or Strava in Settings for more insights")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
    }
    
    private func dataSourceItem(name: String, icon: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
            Text(name)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - Helpers
    
    private var cardBackground: Color {
        colorScheme == .dark ? Color(white: 0.12) : Color.white
    }
    
    private func emptyStateView(message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.title)
                .foregroundColor(.secondary)
            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }
    
    private func formatNumber(_ number: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: number)) ?? "\(number)"
    }
    
    private func formatDate(_ dateString: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        
        if let date = formatter.date(from: dateString) {
            let dayFormatter = DateFormatter()
            dayFormatter.dateFormat = "E"
            return dayFormatter.string(from: date)
        }
        return dateString
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        HealthInsightsView()
    }
}
