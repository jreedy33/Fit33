import SwiftUI

// MARK: - Admin Password Gate
struct AdminPasswordView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var isAuthenticated: Bool
    
    @State private var password = ""
    @State private var showError = false
    @State private var attempts = 0
    
    // Admin password from centralized config (only available in DEBUG builds)
    #if DEBUG
    private let adminPassword = AppConfig.devMenuPassword
    #else
    private let adminPassword = "" // Never accessible in production
    #endif
    
    var body: some View {
        ZStack {
            // Background
            LinearGradient(
                colors: [Color(red: 0.08, green: 0.10, blue: 0.15), Color.black],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            VStack(spacing: 32) {
                Spacer()
                
                // Lock icon
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 100, height: 100)
                    
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.purple, .blue],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                
                VStack(spacing: 8) {
                    Text("Developer Access")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
                    Text("Enter admin password to continue")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
                
                // Password field
                VStack(spacing: 16) {
                    SecureField("Password", text: $password)
                        .textFieldStyle(.plain)
                        .padding()
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(12)
                        .foregroundColor(.white)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(showError ? Color.red : Color.white.opacity(0.2), lineWidth: 1)
                        )
                    
                    if showError {
                        Text("Incorrect password. \(3 - attempts) attempts remaining.")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
                .padding(.horizontal, 32)
                
                // Submit button
                Button(action: validatePassword) {
                    Text("Unlock")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            LinearGradient(
                                colors: [.purple, .blue],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(12)
                }
                .padding(.horizontal, 32)
                .disabled(password.isEmpty)
                .opacity(password.isEmpty ? 0.6 : 1)
                
                Spacer()
                Spacer()
                
                // Cancel button
                Button("Cancel") {
                    dismiss()
                }
                .foregroundColor(.gray)
                .padding(.bottom, 32)
            }
        }
        .onSubmit {
            validatePassword()
        }
    }
    
    private func validatePassword() {
        if password == adminPassword {
            isAuthenticated = true
        } else {
            attempts += 1
            showError = true
            password = ""
            
            // Haptic feedback for error
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.error)
            
            // Lock out after 3 attempts
            if attempts >= 3 {
                dismiss()
            }
        }
    }
}

// MARK: - Main Dev Menu with Tabs
struct DevMenuView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedTab = 0
    
    var body: some View {
        ZStack {
            // Background
            LinearGradient(
                colors: colorScheme == .dark
                    ? [Color(white: 0.08), Color.black]
                    : [Color(red: 0.95, green: 0.96, blue: 0.98), Color.white],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Custom header
                headerView
                
                // Tab picker
                tabPicker
                
                // Content
                TabView(selection: $selectedTab) {
                    InsightsTabContent()
                        .tag(0)
                    
                    BugsTabContent()
                        .tag(1)
                    
                    #if DEBUG
                    LearningEngineDebugView()
                        .tag(2)
                    
                    QualityAuditTabContent()
                        .tag(3)
                    #else
                    Text("Learning Engine Debug (Debug builds only)")
                        .tag(2)
                    
                    Text("Quality Audit (Debug builds only)")
                        .tag(3)
                    #endif
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
        }
        .navigationBarHidden(true)
    }
    
    private var headerView: some View {
        HStack {
            Button(action: { dismiss() }) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("Back")
                }
                .foregroundColor(.blue)
            }
            
            Spacer()
            
            Text("🔧 Dev Tools")
                .font(.headline)
                .fontWeight(.semibold)
            
            Spacer()
            
            // Invisible balance
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                Text("Back")
            }
            .opacity(0)
        }
        .padding()
        .background(.ultraThinMaterial)
    }
    
    private var tabPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                tabButton(title: "Insights", icon: "chart.bar.fill", index: 0, colors: [.blue, .purple])
                tabButton(title: "Bugs", icon: "ant.fill", index: 1, colors: [.red, .orange])
                tabButton(title: "Learning", icon: "brain.head.profile", index: 2, colors: [.purple, .pink])
                tabButton(title: "QA Test", icon: "checkmark.seal.fill", index: 3, colors: [.orange, .red])
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }
    
    private func tabButton(title: String, icon: String, index: Int, colors: [Color]) -> some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedTab = index
            }
        }) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.subheadline)
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .foregroundColor(selectedTab == index ? .white : .primary)
            .padding(.vertical, 10)
            .padding(.horizontal, 20)
            .frame(minWidth: 100)
            .background(
                selectedTab == index
                    ? AnyView(
                        LinearGradient(
                            colors: colors,
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .cornerRadius(10)
                    )
                    : AnyView(Color.clear)
            )
        }
    }
}

// MARK: - Insights Tab (Existing Analytics Content)
struct InsightsTabContent: View {
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var viewModel = DeveloperAnalyticsViewModel()
    
    private var cardBackground: Color {
        colorScheme == .dark ? Color(white: 0.12) : Color.white
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
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
                
                // Force Exercise Refresh (for database updates)
                forceExerciseRefreshCard
                
                // Force Workout State Reset (for stuck workouts)
                forceWorkoutResetCard
                
                // Performance Monitor Card
                performanceMonitorCard
                
                // Refresh Button
                refreshButton
            }
            .padding()
        }
        .task {
            await viewModel.loadAnalytics()
        }
    }
    
    private var performanceMonitorCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "speedometer")
                    .font(.title2)
                    .foregroundColor(.blue)
                Text("Performance Monitor")
                    .font(.headline)
            }
            
            Text("Track FPS, memory, CPU, view load times, and navigation performance in real-time")
                .font(.caption)
                .foregroundColor(.secondary)
            
            // Status indicator
            HStack {
                Circle()
                    .fill(Color.gray)
                    .frame(width: 8, height: 8)
                Text("Not Available")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Text("Add PerformanceMonitoringSystem.swift to enable")
                .font(.caption2)
                .foregroundColor(.secondary)
                .italic()
        }
        .padding()
        .background(cardBackground)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
    }
    
    private var forceExerciseRefreshCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                    .font(.title2)
                    .foregroundColor(.orange)
                Text("Exercise Database")
                    .font(.headline)
            }
            
            Text("Force reload all exercises from Supabase (use after database updates)")
                .font(.caption)
                .foregroundColor(.secondary)
            
            NavigationLink(destination: ForceExerciseRefreshView()) {
                HStack {
                    Image(systemName: "arrow.clockwise.circle.fill")
                    Text("Reload Exercises")
                        .fontWeight(.semibold)
                }
                .font(.subheadline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(
                    LinearGradient(
                        colors: [Color.orange, Color.red],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(12)
            }
        }
        .padding()
        .background(cardBackground)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
    }
    
    @State private var showingWorkoutResetConfirmation = false
    
    private var forceWorkoutResetCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundColor(.red)
                Text("Workout State Reset")
                    .font(.headline)
            }
            
            Text("Force clear stuck workout state (use if workout won't finish or app is stuck)")
                .font(.caption)
                .foregroundColor(.secondary)
            
            // Current state indicator
            HStack {
                Circle()
                    .fill(WorkoutManager.shared.isWorkoutActive ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)
                Text(WorkoutManager.shared.isWorkoutActive ? "Active Workout Detected" : "No Active Workout")
                    .font(.caption)
                    .foregroundColor(WorkoutManager.shared.isWorkoutActive ? .green : .secondary)
            }
            
            Button(action: {
                showingWorkoutResetConfirmation = true
            }) {
                HStack {
                    Image(systemName: "trash.circle.fill")
                    Text("Force Reset Workout State")
                        .fontWeight(.semibold)
                }
                .font(.subheadline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(
                    LinearGradient(
                        colors: [Color.red, Color.orange],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(12)
            }
            .alert("Reset Workout State?", isPresented: $showingWorkoutResetConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Reset", role: .destructive) {
                    WorkoutManager.shared.forceResetWorkoutState()
                    HapticManager.notification(.success)
                }
            } message: {
                Text("This will clear all active workout data and persisted state. Use this if your workout is stuck and won't finish.")
            }
        }
        .padding()
        .background(cardBackground)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
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
        .background(cardBackground)
        .cornerRadius(16)
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.05), radius: 8, x: 0, y: 4)
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
        .background(cardBackground)
        .cornerRadius(16)
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.05), radius: 8, x: 0, y: 4)
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
        .background(cardBackground)
        .cornerRadius(16)
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.05), radius: 8, x: 0, y: 4)
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
        .background(cardBackground)
        .cornerRadius(16)
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.05), radius: 8, x: 0, y: 4)
    }
    
    private var topWorkoutsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "trophy.fill")
                    .foregroundColor(.yellow)
                Text("Top 10 Completed Workouts")
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
                        Text("\(index + 1)")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .frame(width: 24, height: 24)
                            .background(rankColor(for: index + 1))
                            .cornerRadius(12)
                        
                        Text(workout.workoutName)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        Spacer()
                        
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
        .background(cardBackground)
        .cornerRadius(16)
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.05), radius: 8, x: 0, y: 4)
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
        .background(cardBackground)
        .cornerRadius(16)
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.05), radius: 8, x: 0, y: 4)
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
        .background(cardBackground)
        .cornerRadius(16)
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.05), radius: 8, x: 0, y: 4)
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
        .background(cardBackground)
        .cornerRadius(16)
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.05), radius: 8, x: 0, y: 4)
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
    
    private func formatNumber(_ number: Int) -> String {
        let formatter = NumberFormatter()
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
}

// MARK: - Bugs Tab Content
struct BugsTabContent: View {
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var bugService = BugReportService.shared
    @State private var selectedBug: BugReport?
    @State private var showingDeleteConfirmation = false
    @State private var bugToDelete: BugReport?
    
    private var cardBackground: Color {
        colorScheme == .dark ? Color(white: 0.12) : Color.white
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Refresh button header
                refreshHeader
                
                // Error message if present
                if let error = bugService.lastError {
                    errorBanner(error)
                }
                
                // Header stats
                bugStatsHeader
                
                // Bug list
                if bugService.isLoading {
                    ProgressView("Loading bugs...")
                        .padding(40)
                } else if bugService.bugReports.isEmpty {
                    emptyBugsView
                } else {
                    ForEach(bugService.bugReports) { bug in
                        BugReportCard(bug: bug, onDelete: {
                            bugToDelete = bug
                            showingDeleteConfirmation = true
                        }, onTap: {
                            selectedBug = bug
                        })
                    }
                }
            }
            .padding()
        }
        .refreshable {
            await bugService.fetchAllBugReports()
        }
        .task {
            await bugService.fetchAllBugReports()
        }
        .sheet(item: $selectedBug) { bug in
            BugDetailView(bug: bug)
        }
        .alert("Delete Bug Report?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let bug = bugToDelete {
                    Task {
                        await bugService.deleteBugReport(id: bug.id)
                    }
                }
            }
        } message: {
            Text("This will permanently remove this bug report from the server.")
        }
    }
    
    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            
            Text(message)
                .font(.subheadline)
                .foregroundColor(.primary)
                .multilineTextAlignment(.leading)
            
            Spacer()
            
            Button(action: {
                bugService.lastError = nil
            }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.gray)
            }
        }
        .padding()
        .background(Color.orange.opacity(0.15))
        .cornerRadius(12)
    }
    
    private var refreshHeader: some View {
        HStack {
            Text("Bug Reports")
                .font(.title3)
                .fontWeight(.bold)
            
            Spacer()
            
            Button(action: {
                Task {
                    await bugService.fetchAllBugReports()
                }
            }) {
                HStack(spacing: 6) {
                    if bugService.isLoading {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                    Text("Refresh")
                }
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(20)
            }
            .disabled(bugService.isLoading)
        }
    }
    
    private var bugStatsHeader: some View {
        HStack(spacing: 16) {
            statCard(
                value: "\(bugService.bugReports.count)",
                label: "Total",
                color: .blue
            )
            
            statCard(
                value: "\(bugService.bugReports.filter { $0.status == "new" }.count)",
                label: "New",
                color: .red
            )
            
            statCard(
                value: "\(bugService.bugReports.filter { $0.status == "in_progress" }.count)",
                label: "In Progress",
                color: .orange
            )
            
            statCard(
                value: "\(bugService.bugReports.filter { $0.reproducesEveryTime }.count)",
                label: "Always",
                color: .purple
            )
        }
    }
    
    private func statCard(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(color)
            
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(cardBackground)
        .cornerRadius(12)
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.05), radius: 4, x: 0, y: 2)
    }
    
    private var emptyBugsView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 60))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.green, .mint],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            Text("No Bugs Reported!")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("When users shake their device to report bugs, they'll appear here.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
    }
}

// MARK: - Bug Report Card
struct BugReportCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let bug: BugReport
    let onDelete: () -> Void
    let onTap: () -> Void
    
    private var cardBackground: Color {
        colorScheme == .dark ? Color(white: 0.12) : Color.white
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 12) {
                // Header row
                HStack {
                    // Status badge
                    Text(bug.status.uppercased())
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(statusColor)
                        .cornerRadius(6)
                    
                    Spacer()
                    
                    // Reproduces badge
                    if bug.reproducesEveryTime {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.caption2)
                            Text("Always")
                                .font(.caption2)
                        }
                        .foregroundColor(.orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.orange.opacity(0.15))
                        .cornerRadius(4)
                    }
                    
                    // Delete button
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
                
                // Description preview
                Text(bug.description)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                
                // Meta info
                HStack(spacing: 12) {
                    // Device
                    HStack(spacing: 4) {
                        Image(systemName: "iphone")
                            .font(.caption2)
                        Text(bug.displayDeviceModel)
                            .font(.caption2)
                    }
                    .foregroundColor(.secondary)
                    
                    // Time
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.caption2)
                        Text(bug.createdAt, style: .relative)
                            .font(.caption2)
                    }
                    .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    // Screenshot indicator
                    if bug.hasScreenshot {
                        Image(systemName: "photo.fill")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                }
            }
            .padding()
            .background(cardBackground)
            .cornerRadius(12)
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.05), radius: 6, x: 0, y: 3)
        }
        .buttonStyle(.plain)
    }
    
    private var statusColor: Color {
        switch bug.status {
        case "new": return .red
        case "in_progress": return .orange
        case "resolved": return .green
        default: return .gray
        }
    }
}

// MARK: - Bug Detail View
struct BugDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    let bug: BugReport
    @StateObject private var bugService = BugReportService.shared
    @State private var showingDeleteConfirmation = false
    @State private var showingFullScreenshot = false
    
    private var cardBackground: Color {
        colorScheme == .dark ? Color(white: 0.12) : Color.white
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Status section
                    statusSection
                    
                    // Screenshot section
                    if bug.hasScreenshot {
                        screenshotSection
                    }
                    
                    // Description section
                    detailSection(
                        title: "Bug Description",
                        icon: "text.alignleft",
                        color: .purple,
                        content: bug.description
                    )
                    
                    // Expected behavior
                    if !bug.displayExpectedBehavior.isEmpty {
                        detailSection(
                            title: "Expected Behavior",
                            icon: "checkmark.circle",
                            color: .green,
                            content: bug.displayExpectedBehavior
                        )
                    }
                    
                    // Additional info
                    if let additionalInfo = bug.additionalInfo, !additionalInfo.isEmpty {
                        detailSection(
                            title: "Additional Notes",
                            icon: "note.text",
                            color: .gray,
                            content: additionalInfo
                        )
                    }
                    
                    // Device info
                    deviceInfoSection
                    
                    // Action buttons
                    actionButtons
                }
                .padding()
            }
            .background(colorScheme == .dark ? Color(white: 0.08) : Color(red: 0.95, green: 0.96, blue: 0.98))
            .navigationTitle("Bug Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .alert("Delete Bug Report?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task {
                    let success = await bugService.deleteBugReport(id: bug.id)
                    if success {
                        dismiss()
                    }
                }
            }
        } message: {
            Text("This will permanently remove this bug report.")
        }
        .fullScreenCover(isPresented: $showingFullScreenshot) {
            FullScreenScreenshotView(image: bug.decodedScreenshot)
        }
    }
    
    private var statusSection: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Status")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text(bug.status.capitalized)
                    .font(.headline)
                    .foregroundColor(statusColor)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text("Reproduces")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text(bug.reproducesEveryTime ? "Every time" : "Sometimes")
                    .font(.headline)
                    .foregroundColor(bug.reproducesEveryTime ? .orange : .green)
            }
        }
        .padding()
        .background(cardBackground)
        .cornerRadius(12)
    }
    
    private var screenshotSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "camera.viewfinder")
                    .foregroundColor(.blue)
                Text("Screenshot")
                    .font(.headline)
                Spacer()
                Text("Tap to enlarge")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if let screenshot = bug.decodedScreenshot {
                Button(action: {
                    showingFullScreenshot = true
                }) {
                    Image(uiImage: screenshot)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 300)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
                        .overlay(
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.title2)
                                .foregroundColor(.white)
                                .padding(8)
                                .background(Color.black.opacity(0.5))
                                .cornerRadius(8)
                                .padding(8),
                            alignment: .bottomTrailing
                        )
                }
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.1))
                    .frame(height: 200)
                    .overlay(
                        VStack {
                            Image(systemName: "photo")
                                .font(.largeTitle)
                                .foregroundColor(.gray)
                            Text("Screenshot attached (loading...)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    )
            }
        }
        .padding()
        .background(cardBackground)
        .cornerRadius(12)
    }
    
    private func detailSection(title: String, icon: String, color: Color, content: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Text(title)
                    .font(.headline)
            }
            
            Text(content)
                .font(.body)
                .foregroundColor(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(cardBackground)
        .cornerRadius(12)
    }
    
    private var deviceInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "iphone")
                    .foregroundColor(.blue)
                Text("Device Info")
                    .font(.headline)
            }
            
            VStack(spacing: 8) {
                infoRow(label: "Device", value: bug.displayDeviceModel)
                Divider()
                infoRow(label: "OS Version", value: bug.displayOsVersion)
                Divider()
                infoRow(label: "App Version", value: bug.displayAppVersion)
                Divider()
                infoRow(label: "Reported", value: bug.createdAt.formatted())
            }
        }
        .padding()
        .background(cardBackground)
        .cornerRadius(12)
    }
    
    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
        }
    }
    
    private var actionButtons: some View {
        VStack(spacing: 12) {
            // Mark as in progress
            if bug.status == "new" {
                Button(action: {
                    Task {
                        await bugService.updateBugStatus(id: bug.id, status: "in_progress")
                    }
                }) {
                    HStack {
                        Image(systemName: "wrench.fill")
                        Text("Mark In Progress")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.orange)
                    .cornerRadius(12)
                }
            }
            
            // Mark as resolved
            if bug.status != "resolved" {
                Button(action: {
                    Task {
                        await bugService.updateBugStatus(id: bug.id, status: "resolved")
                    }
                }) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Mark Resolved")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.green)
                    .cornerRadius(12)
                }
            }
            
            // Delete
            Button(action: {
                showingDeleteConfirmation = true
            }) {
                HStack {
                    Image(systemName: "trash.fill")
                    Text("Delete Bug Report")
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.red)
                .cornerRadius(12)
            }
        }
    }
    
    private var statusColor: Color {
        switch bug.status {
        case "new": return .red
        case "in_progress": return .orange
        case "resolved": return .green
        default: return .gray
        }
    }
}

// Helper to decode base64 screenshot
extension BugReport {
    var decodedScreenshot: UIImage? {
        guard let base64 = screenshotBase64,
              let data = Data(base64Encoded: base64) else {
            return nil
        }
        return UIImage(data: data)
    }
    
    var hasScreenshot: Bool {
        screenshotBase64 != nil || screenshotUrl != nil
    }
}

// MARK: - Full Screen Screenshot View with Zoom
struct FullScreenScreenshotView: View {
    @Environment(\.dismiss) private var dismiss
    let image: UIImage?
    
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    
    var body: some View {
        ZStack {
            // Black background
            Color.black.ignoresSafeArea()
            
            if let uiImage = image {
                // Zoomable image
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .scaleEffect(scale)
                    .offset(offset)
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                let delta = value / lastScale
                                lastScale = value
                                scale = min(max(scale * delta, 1), 5)
                            }
                            .onEnded { _ in
                                lastScale = 1.0
                                // Reset offset if zoomed out completely
                                if scale <= 1 {
                                    withAnimation(.spring()) {
                                        offset = .zero
                                    }
                                }
                            }
                    )
                    .simultaneousGesture(
                        DragGesture()
                            .onChanged { value in
                                if scale > 1 {
                                    offset = CGSize(
                                        width: lastOffset.width + value.translation.width,
                                        height: lastOffset.height + value.translation.height
                                    )
                                }
                            }
                            .onEnded { _ in
                                lastOffset = offset
                            }
                    )
                    .onTapGesture(count: 2) {
                        // Double tap to zoom in/out
                        withAnimation(.spring()) {
                            if scale > 1 {
                                scale = 1
                                offset = .zero
                                lastOffset = .zero
                            } else {
                                scale = 2.5
                            }
                        }
                    }
            } else {
                // Placeholder if no image
                VStack(spacing: 16) {
                    Image(systemName: "photo")
                        .font(.system(size: 60))
                        .foregroundColor(.gray)
                    Text("No screenshot available")
                        .foregroundColor(.gray)
                }
            }
            
            // Close button
            VStack {
                HStack {
                    Spacer()
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.5), radius: 2)
                    }
                    .padding()
                }
                Spacer()
            }
            
            // Zoom hint
            VStack {
                Spacer()
                HStack(spacing: 20) {
                    Label("Pinch to zoom", systemImage: "hand.pinch")
                    Label("Double-tap to toggle", systemImage: "hand.tap")
                }
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))
                .padding(.vertical, 8)
                .padding(.horizontal, 16)
                .background(Color.black.opacity(0.5))
                .cornerRadius(20)
                .padding(.bottom, 30)
            }
        }
    }
}

// MARK: - Quality Audit Tab
#if DEBUG
struct QualityAuditTabContent: View {
    @State private var isRunningAudit = false
    @State private var auditProgress: String = ""
    @State private var auditComplete = false
    @State private var userCount: Int = 200
    @State private var lastAuditResult: String = ""
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header Card
                VStack(spacing: 12) {
                    HStack {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.title)
                            .foregroundColor(.orange)
                        VStack(alignment: .leading) {
                            Text("Workout Quality Audit")
                                .font(.headline)
                            Text("Automated testing with diverse user profiles")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    
                    Text("Tests workout generation against a comprehensive scorecard covering equipment matching, injury safety, practicality scores, goal alignment, experience levels, and more.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.orange.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                        )
                )
                
                // User Count Selector
                VStack(alignment: .leading, spacing: 8) {
                    Text("Test Users")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    
                    HStack(spacing: 12) {
                        ForEach([50, 100, 200], id: \.self) { count in
                            Button(action: { userCount = count }) {
                                Text("\(count)")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 10)
                                    .background(
                                        userCount == count
                                            ? Color.orange
                                            : Color.gray.opacity(0.2)
                                    )
                                    .foregroundColor(userCount == count ? .white : .primary)
                                    .cornerRadius(10)
                            }
                        }
                    }
                }
                .padding()
                .background(Color(.systemBackground))
                .cornerRadius(12)
                
                // Run Audit Button
                Button(action: runAudit) {
                    HStack(spacing: 12) {
                        if isRunningAudit {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Image(systemName: "play.fill")
                        }
                        Text(isRunningAudit ? "Running Audit..." : "Run Quality Audit (\(userCount) Users)")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        LinearGradient(
                            colors: isRunningAudit ? [.gray] : [.orange, .red],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .disabled(isRunningAudit)
                
                // Progress/Status
                if !auditProgress.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Status")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        
                        Text(auditProgress)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding()
                    .background(Color(.systemBackground))
                    .cornerRadius(12)
                }
                
                // Scorecard Legend
                VStack(alignment: .leading, spacing: 12) {
                    Text("Scorecard Criteria")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    
                    scorecardRow(icon: "wrench.fill", title: "Equipment Match", desc: "All exercises use equipment user has", weight: "20%")
                    scorecardRow(icon: "shield.fill", title: "Safety Score", desc: "Exercises safe for user's limitations", weight: "20%")
                    scorecardRow(icon: "sparkles", title: "Practicality", desc: "Realistic, common exercises", weight: "15%")
                    scorecardRow(icon: "target", title: "Goal Alignment", desc: "Matches user's fitness goals", weight: "10%")
                    scorecardRow(icon: "chart.bar.fill", title: "Experience Level", desc: "Appropriate difficulty", weight: "10%")
                    scorecardRow(icon: "arrow.triangle.2.circlepath", title: "Variety", desc: "Diverse movement patterns", weight: "10%")
                    scorecardRow(icon: "mappin.circle.fill", title: "Location Match", desc: "Gym vs Home appropriate", weight: "10%")
                    scorecardRow(icon: "person.fill", title: "Profile Safety", desc: "Safe for age/weight", weight: "5%")
                }
                .padding()
                .background(Color(.systemBackground))
                .cornerRadius(12)
                
                // Instructions
                VStack(alignment: .leading, spacing: 8) {
                    Text("How It Works")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    
                    Text("""
                    1. Generates diverse test users with varied:
                       • Goals (Build Muscle, Lose Weight, etc.)
                       • Experience levels (Beginner to Advanced)
                       • Locations (Gym, Home, Outdoor)
                       • Equipment combinations
                       • Physical limitations/injuries
                       • Age and weight ranges
                    
                    2. Generates a workout for each user
                    
                    3. Grades each workout against the scorecard
                    
                    4. Reports pass/fail rates and identifies issues
                    
                    5. Suggests code fixes for common problems
                    """)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color(.systemBackground))
                .cornerRadius(12)
                
                Spacer(minLength: 100)
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
    }
    
    private func scorecardRow(icon: String, title: String, desc: String, weight: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(.orange)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                Text(desc)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text(weight)
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.gray.opacity(0.2))
                .cornerRadius(6)
        }
    }
    
    private func runAudit() {
        isRunningAudit = true
        auditProgress = "Starting audit with \(userCount) users..."
        auditComplete = false
        
        DispatchQueue.global(qos: .userInitiated).async {
            WorkoutQualityAudit.shared.runFullAudit(userCount: userCount) { report in
                DispatchQueue.main.async {
                    isRunningAudit = false
                    auditComplete = true
                    
                    let passEmoji = report.passRate >= 90 ? "🎉" : (report.passRate >= 70 ? "✅" : "⚠️")
                    
                    auditProgress = """
                    \(passEmoji) AUDIT COMPLETE
                    
                    Results:
                    • Tested: \(report.totalUsers) users
                    • Passed: \(report.passedUsers) (\(String(format: "%.1f", report.passRate))%)
                    • Failed: \(report.failedUsers)
                    • Overall Score: \(String(format: "%.1f", report.avgOverallScore))/100
                    
                    Breakdown:
                    • Equipment: \(String(format: "%.1f", report.avgEquipmentScore))%
                    • Safety: \(String(format: "%.1f", report.avgSafetyScore))%
                    • Practicality: \(String(format: "%.1f", report.avgPracticalityScore))%
                    • Goal Align: \(String(format: "%.1f", report.avgGoalScore))%
                    • Experience: \(String(format: "%.1f", report.avgExperienceScore))%
                    • Variety: \(String(format: "%.1f", report.avgVarietyScore))%
                    • Location: \(String(format: "%.1f", report.avgLocationScore))%
                    • Profile: \(String(format: "%.1f", report.avgProfileScore))%
                    
                    Time: \(String(format: "%.2f", report.totalTimeSeconds))s
                    
                    Issues Found: \(report.issueBreakdown.values.reduce(0, +))
                    Fixes Suggested: \(report.suggestedFixes.count)
                    
                    (Check Xcode console for full details)
                    """
                }
            }
        }
    }
}
#endif

#Preview("Dev Menu") {
    NavigationView {
        DevMenuView()
    }
}

#Preview("Admin Password") {
    AdminPasswordView(isAuthenticated: .constant(false))
}

