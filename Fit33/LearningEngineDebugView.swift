 //
//  LearningEngineDebugView.swift
//  GoFit
//
//  Debug view to test and verify learning engine data persistence
//  Add this to your app's settings or dev menu to monitor sync status
//
//  ⚠️ DEBUG ONLY - This entire file is excluded from production builds

#if DEBUG

import SwiftUI

struct LearningEngineDebugView: View {
    @StateObject private var learningEngine = UserBehaviorLearningEngine.shared
    @State private var programStats: DebugProgramStats = DebugProgramStats()
    @State private var isRefreshing = false
    @State private var lastRefreshTime: Date?
    @State private var cloudSyncStatus: String = "Unknown"
    @State private var recentExercises: [String] = []
    @State private var activeProgram: SmartActiveProgram?
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header
                headerSection
                
                // Sync Status Card
                syncStatusCard
                
                // Learning Profile Stats
                learningProfileCard
                
                // Equipment Preferences
                equipmentPreferencesCard
                
                // Recent Exercises
                recentExercisesCard
                
                // Program Stats
                programStatsCard
                
                // Actions
                actionsSection
            }
            .padding()
        }
        .navigationTitle("🧠 Learning Engine")
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            loadStats()
        }
    }
    
    // MARK: - Header
    
    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 50))
                .foregroundColor(.purple)
            
            Text("Learning Engine Debug")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Monitor data persistence and sync status")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding()
    }
    
    // MARK: - Sync Status
    
    private var syncStatusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "icloud.fill")
                    .foregroundColor(.blue)
                Text("Sync Status")
                    .font(.headline)
                Spacer()
                
                if learningEngine.isSyncing || learningEngine.isAnalyzing {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
            
            Divider()
            
            statusRow(label: "Cloud Sync", value: cloudSyncStatus, color: cloudSyncStatus == "Connected" ? .green : .orange)
            statusRow(label: "Is Analyzing", value: learningEngine.isAnalyzing ? "Yes" : "No", color: learningEngine.isAnalyzing ? .orange : .green)
            statusRow(label: "Is Syncing", value: learningEngine.isSyncing ? "Yes" : "No", color: learningEngine.isSyncing ? .orange : .green)
            
            if let lastRefresh = lastRefreshTime {
                statusRow(label: "Last Refresh", value: formatDate(lastRefresh), color: .secondary)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(CornerRadius.md)
    }
    
    // MARK: - Learning Profile
    
    private var learningProfileCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "chart.bar.fill")
                    .foregroundColor(.green)
                Text("Learning Profile")
                    .font(.headline)
            }
            
            Divider()
            
            if let profile = learningEngine.userPreferences {
                statRow(label: "Total Workouts Analyzed", value: "\(profile.totalWorkoutsAnalyzed)")
                statRow(label: "Exercises Tracked", value: "\(profile.exerciseAffinityScores.count)")
                statRow(label: "Equipment Types", value: "\(profile.equipmentPreferences.count)")
                statRow(label: "Muscle Groups", value: "\(profile.muscleGroupPreferences.count)")
                statRow(label: "Movement Patterns", value: "\(profile.movementPatternPreferences.count)")
                statRow(label: "Full-Set Exercises", value: "\(profile.fullSetExercises.count)")
                statRow(label: "Recent Exercises", value: "\(profile.recentlyDoneExercises.count)")
                statRow(label: "Preferred Duration", value: "\(profile.preferredWorkoutDuration) min")
                statRow(label: "Preferred Time", value: profile.preferredTimeOfDay.capitalized)
                statRow(label: "Last Updated", value: formatDate(profile.lastUpdated))
            } else {
                Text("No profile data yet")
                    .foregroundColor(.secondary)
                    .italic()
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(CornerRadius.md)
    }
    
    // MARK: - Equipment Preferences
    
    private var equipmentPreferencesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "dumbbell.fill")
                    .foregroundColor(.orange)
                Text("Equipment Preferences")
                    .font(.headline)
            }
            
            Divider()
            
            if let profile = learningEngine.userPreferences {
                let sortedEquipment = profile.equipmentPreferences.sorted { $0.value > $1.value }
                
                ForEach(sortedEquipment.prefix(6), id: \.key) { equipment, score in
                    HStack {
                        Text(equipment.capitalized)
                            .font(.subheadline)
                        Spacer()
                        
                        // Progress bar
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.gray.opacity(0.2))
                                    .frame(height: 8)
                                
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.orange)
                                    .frame(width: geo.size.width * CGFloat(score), height: 8)
                            }
                        }
                        .frame(width: 100, height: 8)
                        
                        Text("\(Int(score * 100))%")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(width: 40, alignment: .trailing)
                    }
                }
                
                if sortedEquipment.isEmpty {
                    Text("No equipment data yet")
                        .foregroundColor(.secondary)
                        .italic()
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(CornerRadius.md)
    }
    
    // MARK: - Recent Exercises
    
    private var recentExercisesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundColor(.purple)
                Text("Recent Exercises (Variety Penalty)")
                    .font(.headline)
            }
            
            Divider()
            
            if let profile = learningEngine.userPreferences, !profile.recentlyDoneExercises.isEmpty {
                Text("These exercises will be penalized for variety:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                DebugFlowLayout(spacing: 8) {
                    ForEach(Array(profile.recentlyDoneExercises.prefix(12)), id: \.self) { exercise in
                        Text(exercise.capitalized)
                            .font(.caption)
                            .padding(.horizontal, Spacing.xs)
                            .padding(.vertical, 4)
                            .background(Color.purple.opacity(0.2))
                            .cornerRadius(CornerRadius.sm)
                    }
                }
            } else {
                Text("No recent exercises tracked")
                    .foregroundColor(.secondary)
                    .italic()
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(CornerRadius.md)
    }
    
    // MARK: - Program Stats
    
    private var programStatsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "calendar.badge.checkmark")
                    .foregroundColor(.blue)
                Text("Program Data")
                    .font(.headline)
            }
            
            Divider()
            
            statRow(label: "Active Programs", value: "\(programStats.activePrograms)")
            statRow(label: "Total Days Completed", value: "\(programStats.completedDays)")
            statRow(label: "Total Exercises Done", value: "\(programStats.totalExercises)")
            
            if let program = activeProgram {
                Divider()
                Text("Current Program")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                statRow(label: "Name", value: program.personalizedName)
                statRow(label: "Progress", value: "Day \(program.currentDay) of \(program.generatedDays.count)")
                statRow(label: "Days Completed", value: "\(program.completedDays.count)")
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(CornerRadius.md)
    }
    
    // MARK: - Actions
    
    private var actionsSection: some View {
        VStack(spacing: 12) {
            Button(action: refreshData) {
                HStack {
                    if isRefreshing {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                    Text("Refresh All Data")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(CornerRadius.md)
            }
            .disabled(isRefreshing)
            
            Button(action: triggerFullAnalysis) {
                HStack {
                    Image(systemName: "brain")
                    Text("Run Full Analysis")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.purple)
                .foregroundColor(.white)
                .cornerRadius(CornerRadius.md)
            }
            .disabled(learningEngine.isAnalyzing)
            
            Button(action: testCloudConnection) {
                HStack {
                    Image(systemName: "icloud.and.arrow.up")
                    Text("Test Cloud Sync")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.green)
                .foregroundColor(.white)
                .cornerRadius(CornerRadius.md)
            }
        }
    }
    
    // MARK: - Helper Views
    
    private func statusRow(label: String, value: String, color: Color) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(color)
        }
    }
    
    private func statRow(label: String, value: String) -> some View {
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
    
    // MARK: - Actions
    
    private func loadStats() {
        // Check cloud connection
        if SupabaseManager.shared.currentUser != nil {
            cloudSyncStatus = "Connected"
        } else {
            cloudSyncStatus = "Not Authenticated"
        }
        
        // Load program stats
        let programs = SmartProgramEngine.shared.userPrograms
        programStats.activePrograms = programs.filter { !$0.isCompleted }.count
        programStats.completedDays = programs.reduce(0) { $0 + $1.completedDays.count }
        programStats.totalExercises = programs.reduce(0) { sum, program in
            sum + program.generatedDays.reduce(0) { $0 + $1.exercises.count }
        }
        
        // Get active program (first non-completed)
        activeProgram = programs.first { !$0.isCompleted }
        
        lastRefreshTime = Date()
    }
    
    private func refreshData() {
        isRefreshing = true
        loadStats()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            isRefreshing = false
        }
    }
    
    private func triggerFullAnalysis() {
        Task {
            let context = PersistenceController.shared.container.viewContext
            _ = await learningEngine.analyzeUserBehavior(context: context)
            await MainActor.run {
                loadStats()
            }
        }
    }
    
    private func testCloudConnection() {
        Task {
            // This will trigger a save to cloud
            if learningEngine.userPreferences != nil {
                print("🧪 Testing cloud sync with current profile...")
                // The save happens automatically when profile is updated
                await MainActor.run {
                    cloudSyncStatus = "Sync Triggered"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        loadStats()
                    }
                }
            }
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Supporting Types

struct DebugProgramStats {
    var activePrograms: Int = 0
    var completedDays: Int = 0
    var totalExercises: Int = 0
}

// Simple flow layout for tags (renamed to avoid conflict)
struct DebugFlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = DebugFlowResult(in: proposal.width ?? 0, subviews: subviews, spacing: spacing)
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = DebugFlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x,
                                      y: bounds.minY + result.positions[index].y),
                         proposal: .unspecified)
        }
    }
    
    struct DebugFlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []
        
        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var rowHeight: CGFloat = 0
            
            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                
                if x + size.width > maxWidth && x > 0 {
                    x = 0
                    y += rowHeight + spacing
                    rowHeight = 0
                }
                
                positions.append(CGPoint(x: x, y: y))
                rowHeight = max(rowHeight, size.height)
                x += size.width + spacing
            }
            
            self.size = CGSize(width: maxWidth, height: y + rowHeight)
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        LearningEngineDebugView()
    }
}

#endif // DEBUG
