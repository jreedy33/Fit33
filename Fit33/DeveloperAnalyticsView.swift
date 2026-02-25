import SwiftUI

/// Developer-only view to see exercise popularity analytics
/// Access: Settings → Developer Tools (hidden at bottom)
struct DeveloperAnalyticsView: View {
    @StateObject private var viewModel = DeveloperAnalyticsViewModel()
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [Color(red: 0.95, green: 0.96, blue: 0.98), Color.white],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    headerView
                    
                    // Last Refresh Time
                    if let lastRefresh = viewModel.lastRefreshTime {
                        Text("Last updated: \(lastRefresh, style: .relative) ago")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    // Stats Overview
                    statsOverviewCard
                    
                    // User Statistics
                    userStatsSection
                    
                    // Workout Analytics
                    workoutAnalyticsSection
                    
                    // Step Tracking Analytics
                    stepAnalyticsSection
                    
                    // Top 10 Workouts
                    topWorkoutsSection
                    
                    // Top Popular Exercises
                    popularExercisesSection
                    
                    // Trending Exercises
                    trendingExercisesSection
                    
                    // Most Favorited Exercises
                    mostFavoritedSection
                    
                    // Refresh Button
                    refreshButton
                }
                .padding()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadAnalytics()
        }
    }
    
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("📊 Admin Dashboard")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("All Users • Real-time Analytics")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
    }
    
    private var statsOverviewCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Platform Overview")
                .font(.headline)
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                StatBubble(
                    icon: "person.2.fill",
                    value: "\(viewModel.totalUsers)",
                    label: "Total Users"
                )
                
                StatBubble(
                    icon: "figure.run",
                    value: "\(viewModel.activeUsers)",
                    label: "Active (30d)"
                )
                
                StatBubble(
                    icon: "dumbbell.fill",
                    value: "\(viewModel.totalWorkouts)",
                    label: "Workouts"
                )
                
                StatBubble(
                    icon: "chart.bar.fill",
                    value: "\(viewModel.totalExercisesTracked)",
                    label: "Exercises"
                )
                
                StatBubble(
                    icon: "flame.fill",
                    value: "\(viewModel.totalUsageCount)",
                    label: "Exercise Uses"
                )
                
                if let stepAnalytics = viewModel.stepAnalytics {
                    StatBubble(
                        icon: "figure.walk",
                        value: "\(formatNumber(stepAnalytics.totalStepsAllUsers))",
                        label: "Total Steps"
                    )
                }
            }
        }
        .padding()
        .background(.white)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
    }
    
    private var userStatsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "person.3.fill")
                    .foregroundColor(.purple)
                Text("User Statistics")
                    .font(.headline)
                Spacer()
            }
            
            if let stats = viewModel.userStats {
                VStack(spacing: 8) {
                    AnalyticsStatRow(label: "Total Users", value: "\(stats.totalUsers)")
                    Divider()
                    AnalyticsStatRow(label: "Active (Last 30 Days)", value: "\(stats.activeUsersLast30Days)")
                    Divider()
                    AnalyticsStatRow(label: "Avg Streak Length", value: "\(stats.avgStreakLength) days")
                    Divider()
                    AnalyticsStatRow(label: "Avg Workouts/User", value: "\(stats.avgTotalWorkouts)")
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding()
            }
        }
        .padding()
        .background(.white)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
    }
    
    private var workoutAnalyticsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "chart.bar.doc.horizontal.fill")
                    .foregroundColor(.green)
                Text("Workout Analytics")
                    .font(.headline)
                Spacer()
            }
            
            if let analytics = viewModel.workoutAnalytics {
                VStack(spacing: 8) {
                    AnalyticsStatRow(label: "Total Workouts Completed", value: "\(analytics.totalWorkouts)")
                    Divider()
                    AnalyticsStatRow(label: "Unique Users Working Out", value: "\(analytics.uniqueUsers)")
                    Divider()
                    AnalyticsStatRow(label: "Workouts (Last 7 Days)", value: "\(analytics.workoutsLast7Days)")
                    Divider()
                    AnalyticsStatRow(label: "Avg Workouts/User", value: String(format: "%.1f", analytics.avgWorkoutsPerUser))
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding()
            }
        }
        .padding()
        .background(.white)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
    }
    
    private var stepAnalyticsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "figure.walk.circle.fill")
                    .foregroundColor(.orange)
                Text("Step Tracking Analytics")
                    .font(.headline)
                Spacer()
            }
            
            if let analytics = viewModel.stepAnalytics {
                VStack(spacing: 8) {
                    AnalyticsStatRow(label: "Users Tracking Steps", value: "\(analytics.usersTrackingSteps)")
                    Divider()
                    AnalyticsStatRow(label: "Total Steps (7 Days)", value: formatNumber(analytics.totalStepsAllUsers))
                    Divider()
                    AnalyticsStatRow(label: "Avg Steps/Day", value: formatNumber(analytics.avgStepsPerDay))
                    Divider()
                    AnalyticsStatRow(label: "Goal Completion Rate", value: String(format: "%.1f%%", analytics.goalCompletionRate * 100))
                    Divider()
                    AnalyticsStatRow(label: "Days Tracked", value: "\(analytics.daysTracked)")
                }
            } else {
                Text("No step tracking data yet")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
        }
        .padding()
        .background(.white)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
    }
    
    private var topWorkoutsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "trophy.fill")
                    .foregroundColor(.yellow)
                Text("Top 10 Completed Workouts (All Users)")
                    .font(.headline)
                Spacer()
            }
            
            if viewModel.isLoading && viewModel.topWorkouts.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding()
            } else if viewModel.topWorkouts.isEmpty {
                Text("No workout data yet")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
            } else {
                ForEach(Array(viewModel.topWorkouts.enumerated()), id: \.element.workoutName) { index, workout in
                    HStack(spacing: 12) {
                        // Rank badge
                        Text("\(index + 1)")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .frame(width: 24, height: 24)
                            .background(rankColor(for: index + 1))
                            .cornerRadius(12)
                        
                        // Workout name
                        Text(workout.workoutName)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        Spacer()
                        
                        // Completion count
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(workout.completionCount)")
                                .font(.headline)
                                .foregroundColor(.blue)
                            
                            Text("completions")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .padding()
        .background(.white)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
    }
    
    private func formatNumber(_ number: Int) -> String {
        let formatter = Foundation.NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: number)) ?? "\(number)"
    }
    
    private func rankColor(for rank: Int) -> Color {
        switch rank {
        case 1: return .yellow
        case 2: return .gray
        case 3: return .orange
        default: return .blue
        }
    }
    
    private var popularExercisesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "star.fill")
                    .foregroundColor(.yellow)
                Text("Top 20 Most Popular")
                    .font(.headline)
                Spacer()
            }
            
            if viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding()
            } else if viewModel.popularExercises.isEmpty {
                Text("No data yet")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
            } else {
                ForEach(Array(viewModel.popularExercises.prefix(20).enumerated()), id: \.element.exerciseId) { index, exercise in
                    ExerciseAnalyticsRow(
                        rank: index + 1,
                        exercise: exercise,
                        displayType: .popular
                    )
                }
            }
        }
        .padding()
        .background(.white)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
    }
    
    private var trendingExercisesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .foregroundColor(.blue)
                Text("Top 10 Trending (7 Days)")
                    .font(.headline)
                Spacer()
            }
            
            if viewModel.trendingExercises.isEmpty {
                Text("No trending data yet")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
            } else {
                ForEach(Array(viewModel.trendingExercises.prefix(10).enumerated()), id: \.element.exerciseId) { index, exercise in
                    ExerciseAnalyticsRow(
                        rank: index + 1,
                        exercise: exercise,
                        displayType: .trending
                    )
                }
            }
        }
        .padding()
        .background(.white)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
    }
    
    private var mostFavoritedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "star.fill")
                    .foregroundColor(.pink)
                Text("Top 15 Most Favorited")
                    .font(.headline)
                Spacer()
            }
            
            if viewModel.favoritedExercises.isEmpty {
                Text("No favorite data yet")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
            } else {
                ForEach(Array(viewModel.favoritedExercises.prefix(15).enumerated()), id: \.element.exerciseId) { index, exercise in
                    ExerciseAnalyticsRow(
                        rank: index + 1,
                        exercise: exercise,
                        displayType: .favorited
                    )
                }
            }
        }
        .padding()
        .background(.white)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
    }
    
    private var refreshButton: some View {
        Button(action: {
            Task {
                await viewModel.loadAnalytics()
            }
        }) {
            HStack {
                Image(systemName: "arrow.clockwise")
                Text("Refresh Data")
            }
            .font(.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding()
            .background(
                LinearGradient(
                    colors: [Color.blue, Color.blue.opacity(0.8)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .cornerRadius(12)
        }
        .disabled(viewModel.isLoading)
        .opacity(viewModel.isLoading ? 0.6 : 1.0)
    }
}

struct StatBubble: View {
    let icon: String
    let value: String
    let label: String
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.blue)
            
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(red: 0.95, green: 0.96, blue: 0.98))
        .cornerRadius(12)
    }
}

struct AnalyticsStatRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
        }
        .padding(.vertical, 4)
    }
}

enum ExerciseDisplayType {
    case popular
    case trending
    case favorited
}

struct ExerciseAnalyticsRow: View {
    let rank: Int
    let exercise: PopularExerciseDTO
    let displayType: ExerciseDisplayType
    
    var body: some View {
        HStack(spacing: 12) {
            // Rank badge
            Text("\(rank)")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .frame(width: 24, height: 24)
                .background(rankColor)
                .cornerRadius(12)
            
            // Exercise info
            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.exerciseName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                HStack(spacing: 8) {
                    if displayType == .favorited {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundColor(.yellow)
                        Text("\(exercise.favoriteCount) favorites")
                    } else {
                        Text("\(exercise.totalUses) uses")
                        Text("•")
                        Text("\(exercise.uniqueUsers) users")
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Score badge
            VStack(alignment: .trailing, spacing: 2) {
                Text(displayValue)
                    .font(.headline)
                    .foregroundColor(displayColor)
                
                Text(displayLabel)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 8)
    }
    
    private var displayValue: String {
        switch displayType {
        case .popular:
            return String(format: "%.1f", exercise.popularityScore)
        case .trending:
            return String(format: "%.1f", exercise.trendingScore)
        case .favorited:
            return "\(exercise.favoriteCount)"
        }
    }
    
    private var displayLabel: String {
        switch displayType {
        case .popular: return "score"
        case .trending: return "trend"
        case .favorited: return "favs"
        }
    }
    
    private var displayColor: Color {
        switch displayType {
        case .popular: return .blue
        case .trending: return .green
        case .favorited: return .pink
        }
    }
    
    private var rankColor: Color {
        switch rank {
        case 1: return .yellow
        case 2: return .gray
        case 3: return Color.orange
        default: return .blue
        }
    }
}

@MainActor
class DeveloperAnalyticsViewModel: ObservableObject {
    @Published var popularExercises: [PopularExerciseDTO] = []
    @Published var trendingExercises: [PopularExerciseDTO] = []
    @Published var favoritedExercises: [PopularExerciseDTO] = []
    @Published var topWorkouts: [TopWorkoutDTO] = []
    @Published var workoutAnalytics: WorkoutAnalyticsDTO?
    @Published var userStats: UserStatisticsDTO?
    @Published var stepAnalytics: StepAnalyticsDTO?
    @Published var isLoading = false
    @Published var lastRefreshTime: Date?
    
    var totalExercisesTracked: Int {
        popularExercises.count
    }
    
    var totalUsers: Int {
        userStats?.totalUsers ?? 0
    }
    
    var totalUsageCount: Int {
        popularExercises.reduce(0) { $0 + $1.totalUses }
    }
    
    var totalWorkouts: Int {
        workoutAnalytics?.totalWorkouts ?? 0
    }
    
    var activeUsers: Int {
        userStats?.activeUsersLast30Days ?? 0
    }
    
    func loadAnalytics() async {
        isLoading = true
        defer { 
            isLoading = false
            lastRefreshTime = Date()
        }
        
        do {
            // Load all analytics in parallel
            async let popular = SupabaseManager.shared.fetchPopularExercises(limit: 50)
            async let trending = SupabaseManager.shared.fetchTrendingExercises(limit: 50)
            async let favorited = SupabaseManager.shared.fetchMostFavoritedExercises(limit: 50)
            async let topWorkoutsData = SupabaseManager.shared.fetchTopWorkouts(limit: 10)
            async let workoutStats = SupabaseManager.shared.fetchWorkoutAnalytics()
            async let userStatistics = SupabaseManager.shared.fetchUserStatistics()
            async let stepStats = SupabaseManager.shared.fetchStepStatisticsAllUsers()
            
            let results = try await (popular, trending, favorited, topWorkoutsData, workoutStats, userStatistics, stepStats)
            
            popularExercises = results.0
            trendingExercises = results.1
            favoritedExercises = results.2
            topWorkouts = results.3
            workoutAnalytics = results.4
            userStats = results.5
            stepAnalytics = results.6
            
            print("📊 Loaded comprehensive analytics:")
            print("  - \(popularExercises.count) popular exercises")
            print("  - \(trendingExercises.count) trending exercises")
            print("  - \(favoritedExercises.count) favorited exercises")
            print("  - \(topWorkouts.count) top workouts")
            print("  - \(totalUsers) total users")
            print("  - \(totalWorkouts) total workouts")
        } catch {
            print("❌ Error loading analytics: \(error)")
        }
    }
}

#Preview {
    NavigationStack {
        DeveloperAnalyticsView()
    }
}

