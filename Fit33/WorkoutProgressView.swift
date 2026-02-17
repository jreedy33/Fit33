import SwiftUI
import CoreData
import Charts

// MARK: - Achievement Service
class AchievementService: ObservableObject {
    static let shared = AchievementService()
    
    // Caching to avoid regenerating 400+ achievements on every view update
    private var cachedAchievements: [Achievement]?
    private var lastCacheKey: String?
    
    private init() {}
    
    /// Invalidate cache when user stats change significantly
    func invalidateCache() {
        cachedAchievements = nil
        lastCacheKey = nil
    }
    
    // MARK: - Main Achievement Generation
    func generateAllAchievements(
        totalWorkouts: Int,
        currentStreak: Int,
        longestStreak: Int,
        heaviestWeight: Double,
        highestReps: Int,
        longestWorkoutMinutes: Int,
        mostSetsInWorkout: Int,
        workoutsThisMonth: Int,
        userLevel: Int,
        userXP: Int
    ) -> [Achievement] {
        // Create cache key from all parameters
        let cacheKey = "\(totalWorkouts)-\(currentStreak)-\(longestStreak)-\(Int(heaviestWeight))-\(highestReps)-\(longestWorkoutMinutes)-\(mostSetsInWorkout)-\(workoutsThisMonth)-\(userLevel)-\(userXP)"
        
        // Return cached achievements if parameters haven't changed
        if let cached = cachedAchievements, lastCacheKey == cacheKey {
            return cached
        }
        
        var achievements: [Achievement] = []
        
        // MARK: - Workout Count Achievements (100 achievements)
        let workoutMilestones = [1, 2, 3, 5, 7, 10, 15, 20, 25, 30, 35, 40, 45, 50, 60, 70, 80, 90, 100, 125, 150, 175, 200, 225, 250, 275, 300, 350, 400, 450, 500, 600, 700, 800, 900, 1000, 1100, 1200, 1300, 1400, 1500, 1750, 2000, 2250, 2500, 2750, 3000, 3500, 4000, 4500, 5000, 5500, 6000, 6500, 7000, 7500, 8000, 8500, 9000, 9500, 10000, 11000, 12000, 13000, 14000, 15000, 16000, 17000, 18000, 19000, 20000, 22500, 25000, 27500, 30000, 32500, 35000, 37500, 40000, 42500, 45000, 47500, 50000, 55000, 60000, 65000, 70000, 75000, 80000, 85000, 90000, 95000, 100000, 110000, 120000, 130000, 140000, 150000, 175000, 200000, 250000, 300000]
        
        for (index, count) in workoutMilestones.enumerated() {
            let title = getWorkoutTitle(count: count, index: index)
            achievements.append(Achievement(
                id: "workouts_\(count)",
                title: title,
                description: "Complete \(count) workout\(count == 1 ? "" : "s")",
                icon: getWorkoutIcon(count: count),
                color: getWorkoutColor(index: index),
                isEarned: totalWorkouts >= count,
                progress: min(1.0, Double(totalWorkouts) / Double(count))
            ))
        }
        
        // MARK: - Streak Achievements (100 achievements)
        let streakMilestones = [2, 3, 4, 5, 6, 7, 10, 14, 21, 30, 45, 60, 75, 90, 100, 120, 150, 180, 200, 250, 300, 365, 400, 450, 500, 550, 600, 650, 700, 750, 800, 850, 900, 950, 1000, 1100, 1200, 1300, 1400, 1500, 1600, 1700, 1800, 1900, 2000, 2200, 2400, 2600, 2800, 3000, 3300, 3600, 4000, 4500, 5000, 5500, 6000, 6500, 7000, 7500, 8000, 8500, 9000, 9500, 10000, 11000, 12000, 13000, 14000, 15000, 16000, 17000, 18000, 19000, 20000, 22000, 24000, 26000, 28000, 30000, 32000, 34000, 36000, 38000, 40000, 42000, 44000, 46000, 48000, 50000, 55000, 60000, 65000, 70000, 75000, 80000, 85000, 90000, 95000, 100000]
        
        for (index, days) in streakMilestones.enumerated() {
            let title = getStreakTitle(days: days, index: index)
            achievements.append(Achievement(
                id: "streak_\(days)",
                title: title,
                description: "\(days)-day workout streak",
                icon: "flame.fill",
                color: getStreakColor(index: index),
                isEarned: longestStreak >= days,
                progress: min(1.0, Double(currentStreak) / Double(days))
            ))
        }
        
        // MARK: - Weight Achievements (100 achievements)
        let weightMilestones = [25, 50, 75, 100, 125, 150, 175, 200, 225, 250, 275, 300, 325, 350, 375, 400, 425, 450, 475, 500, 525, 550, 575, 600, 625, 650, 675, 700, 725, 750, 775, 800, 825, 850, 875, 900, 925, 950, 975, 1000, 1025, 1050, 1075, 1100, 1125, 1150, 1175, 1200, 1225, 1250, 1275, 1300, 1325, 1350, 1375, 1400, 1425, 1450, 1475, 1500, 1550, 1600, 1650, 1700, 1750, 1800, 1850, 1900, 1950, 2000, 2100, 2200, 2300, 2400, 2500, 2600, 2700, 2800, 2900, 3000, 3100, 3200, 3300, 3400, 3500, 3600, 3700, 3800, 3900, 4000, 4200, 4400, 4600, 4800, 5000, 5500, 6000, 6500, 7000, 7500, 8000]
        
        for (index, weight) in weightMilestones.enumerated() {
            let title = getWeightTitle(weight: weight, index: index)
            achievements.append(Achievement(
                id: "weight_\(weight)",
                title: title,
                description: "Lift \(weight)+ lbs in a single rep",
                icon: getWeightIcon(index: index),
                color: getWeightColor(index: index),
                isEarned: heaviestWeight >= Double(weight),
                progress: min(1.0, heaviestWeight / Double(weight))
            ))
        }
        
        // MARK: - Level Achievements (50 achievements)
        for level in 1...50 {
            let title = getLevelTitle(level: level)
            achievements.append(Achievement(
                id: "level_\(level)",
                title: title,
                description: "Reach level \(level)",
                icon: getLevelIcon(level: level),
                color: getLevelColor(level: level),
                isEarned: userLevel >= level,
                progress: min(1.0, Double(userLevel) / Double(level))
            ))
        }
        
        // MARK: - Reps Achievements (50 achievements)
        let repMilestones = [10, 20, 30, 40, 50, 60, 70, 80, 90, 100, 120, 140, 160, 180, 200, 225, 250, 275, 300, 325, 350, 375, 400, 425, 450, 475, 500, 550, 600, 650, 700, 750, 800, 850, 900, 950, 1000, 1100, 1200, 1300, 1400, 1500, 1750, 2000, 2500, 3000, 4000, 5000, 7500, 10000]
        
        for (index, reps) in repMilestones.enumerated() {
            let title = getRepsTitle(reps: reps, index: index)
            achievements.append(Achievement(
                id: "reps_\(reps)",
                title: title,
                description: "Complete \(reps) reps in a single set",
                icon: getRepsIcon(index: index),
                color: getRepsColor(index: index),
                isEarned: highestReps >= reps,
                progress: min(1.0, Double(highestReps) / Double(reps))
            ))
        }
        
        // MARK: - Time-based Achievements (50 achievements)
        let timeMilestones = [5, 10, 15, 20, 25, 30, 40, 50, 60, 75, 90, 105, 120, 135, 150, 180, 210, 240, 270, 300, 330, 360, 390, 420, 450, 480, 510, 540, 570, 600, 660, 720, 780, 840, 900, 960, 1020, 1080, 1140, 1200, 1320, 1440, 1560, 1680, 1800, 2100, 2400, 2700, 3000, 3600]
        
        for (index, minutes) in timeMilestones.enumerated() {
            let title = getTimeTitle(minutes: minutes, index: index)
            let hours = minutes / 60
            let remainingMins = minutes % 60
            let timeDesc = hours > 0 ? (remainingMins > 0 ? "\(hours)h \(remainingMins)m" : "\(hours)h") : "\(minutes)m"
            achievements.append(Achievement(
                id: "time_\(minutes)",
                title: title,
                description: "Complete a \(timeDesc) workout",
                icon: getTimeIcon(index: index),
                color: getTimeColor(index: index),
                isEarned: longestWorkoutMinutes >= minutes,
                progress: min(1.0, Double(longestWorkoutMinutes) / Double(minutes))
            ))
        }
        
        // MARK: - Sets Achievements (50 achievements)
        let setsMilestones = [5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55, 60, 65, 70, 75, 80, 85, 90, 95, 100, 110, 120, 130, 140, 150, 160, 170, 180, 190, 200, 220, 240, 260, 280, 300, 320, 340, 360, 380, 400, 450, 500, 550, 600, 650, 700, 750, 800, 900, 1000]
        
        for (index, sets) in setsMilestones.enumerated() {
            let title = getSetsTitle(sets: sets, index: index)
            achievements.append(Achievement(
                id: "sets_\(sets)",
                title: title,
                description: "Complete \(sets) sets in one workout",
                icon: getSetsIcon(index: index),
                color: getSetsColor(index: index),
                isEarned: mostSetsInWorkout >= sets,
                progress: min(1.0, Double(mostSetsInWorkout) / Double(sets))
            ))
        }
        
        // MARK: - Monthly Achievements (50 achievements)
        for month in 1...50 {
            let title = getMonthlyTitle(month: month)
            achievements.append(Achievement(
                id: "monthly_\(month)",
                title: title,
                description: "Complete \(month * 4) workouts in a month",
                icon: "calendar.circle.fill",
                color: getMonthlyColor(month: month),
                isEarned: workoutsThisMonth >= (month * 4),
                progress: min(1.0, Double(workoutsThisMonth) / Double(month * 4))
            ))
        }
        
        // Cache results
        cachedAchievements = achievements
        lastCacheKey = cacheKey
        
        return achievements
    }
    
    // MARK: - Get Near Achievements
    func getNearAchievements(
        totalWorkouts: Int,
        currentStreak: Int,
        longestStreak: Int,
        heaviestWeight: Double,
        highestReps: Int,
        longestWorkoutMinutes: Int,
        mostSetsInWorkout: Int,
        workoutsThisMonth: Int,
        userLevel: Int,
        userXP: Int,
        limit: Int = 5
    ) -> [Achievement] {
        
        let allAchievements = generateAllAchievements(
            totalWorkouts: totalWorkouts,
            currentStreak: currentStreak,
            longestStreak: longestStreak,
            heaviestWeight: heaviestWeight,
            highestReps: highestReps,
            longestWorkoutMinutes: longestWorkoutMinutes,
            mostSetsInWorkout: mostSetsInWorkout,
            workoutsThisMonth: workoutsThisMonth,
            userLevel: userLevel,
            userXP: userXP
        )
        
        // Filter to only unearned achievements with progress > 0
        let nearAchievements = allAchievements
            .filter { !$0.isEarned && $0.progress > 0.0 }
            .sorted { achievement1, achievement2 in
                // Sort by progress descending (closest to completion first)
                if achievement1.progress != achievement2.progress {
                    return achievement1.progress > achievement2.progress
                }
                
                // If progress is equal, prioritize by category importance
                let priority1 = getAchievementPriority(achievement1)
                let priority2 = getAchievementPriority(achievement2)
                return priority1 < priority2
            }
        
        // Return top achievements, ensuring variety
        return Array(ensureVariety(nearAchievements).prefix(limit))
    }
    
    // MARK: - Helper Functions
    
    private func getAchievementPriority(_ achievement: Achievement) -> Int {
        // Lower number = higher priority
        if achievement.id.hasPrefix("workouts_") { return 1 }
        if achievement.id.hasPrefix("streak_") { return 2 }
        if achievement.id.hasPrefix("level_") { return 3 }
        if achievement.id.hasPrefix("monthly_") { return 4 }
        if achievement.id.hasPrefix("weight_") { return 5 }
        if achievement.id.hasPrefix("reps_") { return 6 }
        if achievement.id.hasPrefix("time_") { return 7 }
        if achievement.id.hasPrefix("sets_") { return 8 }
        return 9
    }
    
    private func ensureVariety(_ achievements: [Achievement]) -> [Achievement] {
        var result: [Achievement] = []
        var categoriesUsed: Set<String> = []
        
        // First pass: Add one from each category
        for achievement in achievements {
            let category = getAchievementCategory(achievement.id)
            if !categoriesUsed.contains(category) {
                result.append(achievement)
                categoriesUsed.insert(category)
                if result.count >= 5 { break }
            }
        }
        
        // Second pass: Fill remaining slots with highest progress
        if result.count < 5 {
            for achievement in achievements {
                if !result.contains(where: { $0.id == achievement.id }) {
                    result.append(achievement)
                    if result.count >= 5 { break }
                }
            }
        }
        
        return result
    }
    
    private func getAchievementCategory(_ id: String) -> String {
        if id.hasPrefix("workouts_") { return "workouts" }
        if id.hasPrefix("streak_") { return "streak" }
        if id.hasPrefix("level_") { return "level" }
        if id.hasPrefix("monthly_") { return "monthly" }
        if id.hasPrefix("weight_") { return "weight" }
        if id.hasPrefix("reps_") { return "reps" }
        if id.hasPrefix("time_") { return "time" }
        if id.hasPrefix("sets_") { return "sets" }
        return "other"
    }
    
    // MARK: - Title Generators
    
    private func getWorkoutTitle(count: Int, index: Int) -> String {
        let titles = ["First Step", "Getting Started", "Building Momentum", "Steady Progress", "Week Complete", "Double Digits", "Committed", "Strong Foundation", "Quarter Century", "Month Milestone", "Dedicated", "Focused", "Determined", "Half Century", "Consistent", "Impressive", "Committed", "Excellent", "Century Club", "Powerhouse", "Elite", "Champion", "Unstoppable", "Legendary", "Quarter Thousand", "Extraordinary", "Phenomenal", "Supreme", "Ultimate", "Incredible", "Titan", "Master", "Grandmaster", "Immortal", "Godlike", "Transcendent", "Mythical", "Infinite", "Eternal", "Cosmic", "Universal", "Galactic", "Dimensional", "Omnipotent", "Supreme Being", "Deity", "Creator", "Universe Master", "Reality Bender", "Existence"]
        
        if index < titles.count {
            return titles[index]
        } else if count >= 100000 {
            return "Reality Transcendent"
        } else if count >= 50000 {
            return "Universe Creator"
        } else if count >= 10000 {
            return "Cosmic Entity"
        } else if count >= 5000 {
            return "Legendary Master"
        } else if count >= 1000 {
            return "Elite Champion"
        } else {
            return "Milestone \(count)"
        }
    }
    
    private func getWorkoutIcon(count: Int) -> String {
        if count == 1 { return "figure.walk" }
        else if count <= 10 { return "dumbbell.fill" }
        else if count <= 50 { return "star.fill" }
        else if count <= 100 { return "crown.fill" }
        else if count <= 500 { return "bolt.fill" }
        else if count <= 1000 { return "flame.fill" }
        else if count <= 5000 { return "diamond.fill" }
        else if count <= 10000 { return "sparkles" }
        else { return "infinity" }
    }
    
    private func getWorkoutColor(index: Int) -> Color {
        let colors: [Color] = [.green, .blue, .orange, .purple, .red, .cyan, .yellow, .pink, .indigo, .mint]
        return colors[index % colors.count]
    }
    
    private func getStreakTitle(days: Int, index: Int) -> String {
        let titles = ["Streak Start", "Building", "Momentum", "Consistency", "Week Strong", "Dedicated", "Committed", "Two Weeks", "Three Weeks", "Month Master", "Impressive", "Outstanding", "Quarter Year", "Half Year", "Century", "Legendary", "Epic", "Incredible", "Supreme", "Ultimate", "Godlike", "Immortal", "Eternal", "Infinite"]
        
        if index < titles.count {
            return titles[index]
        } else if days >= 10000 {
            return "Eternal Flame"
        } else if days >= 5000 {
            return "Infinite Spirit"
        } else if days >= 1000 {
            return "Legendary Streak"
        } else {
            return "\(days) Day Streak"
        }
    }
    
    private func getStreakColor(index: Int) -> Color {
        return .orange
    }
    
    private func getWeightTitle(weight: Int, index: Int) -> String {
        let titles = ["Light Work", "Getting Stronger", "Building Power", "Solid Lift", "Impressive", "Strong", "Powerful", "Beast Mode", "Heavy Hitter", "Powerhouse", "Elite Lifter", "Champion", "Superhuman", "Godlike", "Titan", "Immortal", "Legendary", "Mythical", "Cosmic", "Universal"]
        
        if index < titles.count {
            return titles[index]
        } else if weight >= 5000 {
            return "Reality Bender"
        } else if weight >= 2000 {
            return "Cosmic Force"
        } else if weight >= 1000 {
            return "Legendary Titan"
        } else {
            return "\(weight)lb Lifter"
        }
    }
    
    private func getWeightIcon(index: Int) -> String {
        if index < 10 { return "scalemass.fill" }
        else if index < 20 { return "dumbbell.fill" }
        else if index < 30 { return "bolt.fill" }
        else if index < 40 { return "flame.fill" }
        else { return "crown.fill" }
    }
    
    private func getWeightColor(index: Int) -> Color {
        let colors: [Color] = [.red, .orange, .yellow, .green, .blue, .purple, .pink, .cyan, .indigo, .mint]
        return colors[index % colors.count]
    }
    
    private func getLevelTitle(level: Int) -> String {
        if level <= 5 { return "Novice \(level)" }
        else if level <= 10 { return "Beginner \(level)" }
        else if level <= 20 { return "Intermediate \(level)" }
        else if level <= 30 { return "Advanced \(level)" }
        else if level <= 40 { return "Expert \(level)" }
        else if level <= 50 { return "Master \(level)" }
        else { return "Legendary Master \(level)" }
    }
    
    private func getLevelIcon(level: Int) -> String {
        if level <= 10 { return "bolt.fill" }
        else if level <= 20 { return "star.fill" }
        else if level <= 30 { return "crown.fill" }
        else if level <= 40 { return "diamond.fill" }
        else if level <= 50 { return "sparkles" }
        else { return "infinity" }
    }
    
    private func getLevelColor(level: Int) -> Color {
        if level <= 10 { return .cyan }
        else if level <= 20 { return .blue }
        else if level <= 30 { return .purple }
        else if level <= 40 { return .pink }
        else if level <= 50 { return .yellow }
        else { return .orange }
    }
    
    private func getRepsTitle(reps: Int, index: Int) -> String {
        let titles = ["Rep Counter", "Volume Builder", "Endurance", "High Volume", "Rep Master", "Stamina King", "Endurance Beast", "Volume Crusher", "Rep Machine", "Unstoppable"]
        
        if index < titles.count {
            return titles[index]
        } else if reps >= 5000 {
            return "Rep God"
        } else if reps >= 1000 {
            return "Rep Titan"
        } else {
            return "\(reps) Rep Master"
        }
    }
    
    private func getRepsIcon(index: Int) -> String {
        return "repeat.circle.fill"
    }
    
    private func getRepsColor(index: Int) -> Color {
        return .orange
    }
    
    private func getTimeTitle(minutes: Int, index: Int) -> String {
        let titles = ["Quick Start", "Short Session", "Good Duration", "Solid Time", "Extended", "Long Session", "Marathon", "Epic Duration", "Time Master", "Endurance King"]
        
        if index < titles.count {
            return titles[index]
        } else if minutes >= 1800 {
            return "Time Lord"
        } else if minutes >= 600 {
            return "Marathon Master"
        } else {
            return "\(minutes)min Session"
        }
    }
    
    private func getTimeIcon(index: Int) -> String {
        return "stopwatch.fill"
    }
    
    private func getTimeColor(index: Int) -> Color {
        return .blue
    }
    
    private func getSetsTitle(sets: Int, index: Int) -> String {
        let titles = ["Set Builder", "Volume", "High Volume", "Set Master", "Volume King", "Set Beast", "Volume Crusher", "Set Machine", "Volume God", "Set Titan"]
        
        if index < titles.count {
            return titles[index]
        } else {
            return "\(sets) Set Master"
        }
    }
    
    private func getSetsIcon(index: Int) -> String {
        return "list.number"
    }
    
    private func getSetsColor(index: Int) -> Color {
        return .purple
    }
    
    private func getMonthlyTitle(month: Int) -> String {
        if month <= 5 { return "Monthly \(month)" }
        else if month <= 12 { return "Monthly Beast \(month)" }
        else if month <= 24 { return "Monthly Master \(month)" }
        else { return "Monthly God \(month)" }
    }
    
    private func getMonthlyColor(month: Int) -> Color {
        let colors: [Color] = [.green, .blue, .purple, .red, .orange]
        return colors[month % colors.count]
    }
}

struct WorkoutProgressView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.scrollToTopTrigger) private var scrollToTopTrigger
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var userManager: UserManager
    @StateObject private var cloudProgramService = CloudProgramService.shared
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Workout.date, ascending: false)],
        animation: .none)  // Disable animation for faster updates
    private var workouts: FetchedResults<Workout>
    
    @State private var selectedTimeFrame: TimeFrame = .month
    @State private var showingDetailedStats = false
    
    // ⚡️ PERFORMANCE: Deferred computation state - expensive operations run after view loads
    @State private var cachedAchievements: [Achievement] = []
    @State private var hasLoadedAchievements = false
    @State private var cachedHeaviestWeight: Double = 0
    @State private var cachedHighestReps: Int = 0
    @State private var cachedMostSets: Int = 0
    @State private var cachedLongestWorkoutMinutes: Int = 0
    @State private var hasComputedPRs = false
    
    /// When true, renders only the stats content sections (no NavigationView/ScrollView/background)
    let isEmbedded: Bool
    
    init(isEmbedded: Bool = false) {
        self.isEmbedded = isEmbedded
    }
    
    enum TimeFrame: String, CaseIterable {
        case week = "Week"
        case month = "Month"
        case year = "Year"
        case all = "All Time"
    }
    
    // MARK: - Embedded Stats Content (used in Workout tab)
    
    @ViewBuilder
    var statsContent: some View {
        // Section header
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Your Stats")
                    .font(.title2)
                    .fontWeight(.bold)
                Text("Track your fitness journey")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Image(systemName: "chart.line.uptrend.xyaxis")
                .foregroundStyle(
                    LinearGradient(colors: [.purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .font(.title3)
        }
        .padding(.horizontal, 4)
        
        // Health Insights Quick Access
        healthInsightsCard
        
        // Fitness Rings Section
        fitnessRingsSection
        
        // Hero Stats Section (Total Workouts)
        heroStatsSection
        
        // Activity Calendar
        activityCalendarSection
        
        // Streak & Motivation Section
        streakSection
        
        // Time Frame Picker
        timeFramePicker
        
        // Workout Frequency Chart
        workoutFrequencyChart
        
        // Comprehensive Stats Grid
        comprehensiveStatsGrid
        
        // Progress Timeline
        progressTimeline
        
        // Personal Records
        personalRecordsSection
        
        // Achievements Gallery
        achievementsGallery
        
        // Monthly Summary
        monthlySummary
    }
    
    var body: some View {
        if isEmbedded {
            // Embedded mode: LIGHTWEIGHT version for Workout tab.
            // Only show the key stats sections — skip achievements, calendar, charts etc.
            // These are EXPENSIVE and the user can always see them by scrolling up on the
            // dedicated Stats sections. The Workout tab should stay fast.
            LazyVStack(spacing: 20) {
                // Section header
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Your Stats")
                            .font(.title2)
                            .fontWeight(.bold)
                        Text("Track your fitness journey")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .foregroundStyle(
                            LinearGradient(colors: [.purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .font(.title3)
                }
                .padding(.horizontal, 4)
                
                // Only the lightweight sections (no charts, no calendar, no achievements)
                heroStatsSection
                fitnessRingsSection
                streakSection
                comprehensiveStatsGrid
            }
            // NO deferred computation tasks — keep the Workout tab snappy
        } else {
        NavigationView {
            ScrollViewReader { scrollProxy in
                ScrollView {
                    Color.clear.frame(height: 0).id("top")
                    
                    LazyVStack(spacing: 0) {
                        // Custom header
                        customProgressHeaderView
                            .padding(.top, 4)
                            .padding(.bottom, 16)
                        
                        LazyVStack(spacing: 20) {
                            statsContent
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 20)
                }
                .background(
                    AnimatedOrbBackground.stats(colorScheme: colorScheme)
                )
                .onChange(of: scrollToTopTrigger) { _, _ in
                    scrollProxy.scrollTo("top", anchor: .top)
                }
            }
            .navigationBarHidden(true)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .mask(
                        LinearGradient(
                            gradient: Gradient(stops: [
                                .init(color: .black, location: 0.0),
                                .init(color: .black, location: 0.6),
                                .init(color: .clear, location: 1.0)
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(height: 80)
                    .ignoresSafeArea(.all, edges: .top)
            }
        }
        // ⚡️ PERFORMANCE: Deferred computation of expensive values
        .task(id: "compute_stats") {
            // Wait a tiny bit to let the view render first
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            
            // Compute PRs in background if not already done
            if !hasComputedPRs {
                await computePRsInBackground()
            }
            
            // Compute achievements with slight delay (very expensive)
            try? await Task.sleep(nanoseconds: 200_000_000) // 200ms more
            if !hasLoadedAchievements {
                await computeAchievementsInBackground()
            }
        }
        }
    }
    
    // ⚡️ PERFORMANCE: Background PR computation
    private func computePRsInBackground() async {
        // Compute on main thread since workouts is a @FetchRequest
        // But do it after a tiny delay so UI renders first
        var maxWeight: Double = 0
        var maxReps: Int = 0
        var maxSets: Int = 0
        var maxMinutes: Int = 0
        
        // This iterates all workouts
        for workout in workouts {
            guard let exercises = workout.exercises?.allObjects as? [WorkoutExercise] else { continue }
            maxSets = max(maxSets, exercises.count)
            
            let duration = workout.duration
            if duration > 0 {
                maxMinutes = max(maxMinutes, Int(duration / 60))
            }
            
            for exercise in exercises {
                guard let sets = exercise.sets?.allObjects as? [WorkoutSet] else { continue }
                for set in sets {
                    maxWeight = max(maxWeight, set.weight)
                    maxReps = max(maxReps, Int(set.reps))
                }
            }
        }
        
        cachedHeaviestWeight = maxWeight
        cachedHighestReps = maxReps
        cachedMostSets = maxSets
        cachedLongestWorkoutMinutes = maxMinutes
        hasComputedPRs = true
    }
    
    // ⚡️ PERFORMANCE: Background achievement computation
    private func computeAchievementsInBackground() async {
        // Get values on main thread first
        let totalWorkoutsCount = workouts.count
        let streak = Int(userManager.currentUser?.currentStreak ?? 0)
        let longest = Int(userManager.currentUser?.longestStreak ?? 0)
        let heaviest = cachedHeaviestWeight
        let reps = cachedHighestReps
        let minutes = cachedLongestWorkoutMinutes
        let sets = cachedMostSets
        let monthWorkouts = workoutsThisMonth
        let level = userManager.getLevel()
        let xp = Int(userManager.currentUser?.xp ?? 0)
        
        // Generate achievements (can be done synchronously since AchievementService caches)
        let achievements = AchievementService.shared.generateAllAchievements(
            totalWorkouts: totalWorkoutsCount,
            currentStreak: streak,
            longestStreak: longest,
            heaviestWeight: heaviest,
            highestReps: reps,
            longestWorkoutMinutes: minutes,
            mostSetsInWorkout: sets,
            workoutsThisMonth: monthWorkouts,
            userLevel: level,
            userXP: xp
        )
        
        cachedAchievements = achievements
        hasLoadedAchievements = true
    }
    
    // MARK: - Custom Header View
    private var customProgressHeaderView: some View {
        HStack {
            Text("Stats")
                .font(.system(size: 42, weight: .bold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.purple, .purple, .purple, Color(red: 0.7, green: 0.4, blue: 0.95).opacity(0.8)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: .purple.opacity(0.4), radius: 6, x: 0, y: 2)
            
            Spacer()
            
            // Active workout timer (only shows when workout is active)
            if WorkoutManager.shared.isWorkoutActive {
                Text(WorkoutManager.shared.formattedDuration)
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.ultraThinMaterial)
                    )
            }
        }
        .padding(.leading, 4)
    }
    
    // MARK: - Hero Stats Section
    private var heroStatsSection: some View {
        VStack(spacing: 20) {
            // Main achievement display
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Total Workouts")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("\(totalWorkouts)")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 8) {
                    Text("Level \(userManager.getLevel())")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            LinearGradient(
                                gradient: Gradient(colors: [.purple, .blue]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(20)
                    
                    Text("\(userManager.currentUser?.xp ?? 0) XP")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                }
            }
            
            // XP Progress with enhanced styling
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Progress to Level \(userManager.getLevel() + 1)")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Spacer()
                    Text("\(userManager.getXPForNextLevel()) XP to go")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 12)
                    
                    RoundedRectangle(cornerRadius: 10)
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [.purple, .blue, .cyan]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: xpProgressWidth, height: 12)
                        .animation(.easeInOut(duration: 1), value: xpProgressWidth)
                }
            }
        }
        .padding(24)
        .background(
            ZStack {
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
            }
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.08), radius: 12, x: 0, y: 6)
    }
    
    // MARK: - Health Insights Card
    private var healthInsightsCard: some View {
        NavigationLink(destination: HealthInsightsView()) {
            HStack(spacing: 16) {
                // Icon with gradient background
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(
                            LinearGradient(
                                colors: [.purple, .indigo],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 50, height: 50)
                    
                    Image(systemName: "heart.text.square.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.white)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Health Insights")
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    
                    HStack(spacing: 8) {
                        if HealthKitService.shared.isAuthorized {
                            sourceTag("Apple Health", color: .red)
                        }
                        if FitbitService.shared.isConnected {
                            sourceTag("Fitbit", color: Color(red: 0, green: 0.73, blue: 0.77))
                        }
                        if StravaService.shared.isConnected {
                            sourceTag("Strava", color: Color(red: 252/255, green: 76/255, blue: 2/255))
                        }
                        if !HealthKitService.shared.isAuthorized && !FitbitService.shared.isConnected && !StravaService.shared.isConnected {
                            Text("Connect devices for full insights")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    // Show steps from HealthKit first, then Fitbit as fallback
                    if HealthKitService.shared.isAuthorized && HealthKitService.shared.todaySteps > 0 {
                        Text("\(formatSteps(HealthKitService.shared.todaySteps))")
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                        Text("steps today")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    } else if FitbitService.shared.isConnected, let steps = FitbitService.shared.todaySummary?.steps {
                        Text("\(formatSteps(steps))")
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                        Text("steps today")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(colorScheme == .dark ? Color(white: 0.12) : Color.white)
            )
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.08), radius: 12, x: 0, y: 6)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func sourceTag(_ name: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(name)
                .font(.caption2)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(color.opacity(0.15))
        .cornerRadius(6)
    }
    
    private func formatSteps(_ steps: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: steps)) ?? "\(steps)"
    }
    
    // MARK: - Streak Section
    // MARK: - Today's Activity Card (matches Meals tab style)
    private var fitnessRingsSection: some View {
        VStack(spacing: 16) {
            // MARK: Today's Activity Section
            VStack(spacing: 16) {
                // Header with completion summary
                HStack {
                    Text("Today's Activity")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    // Ring completion summary
                    HStack(spacing: 4) {
                        Image(systemName: allRingsComplete ? "star.fill" : "circle.dotted")
                            .foregroundColor(allRingsComplete ? .yellow : .secondary)
                        Text(ringCompletionText)
                            .fontWeight(.semibold)
                    }
                    .font(.caption)
                    .foregroundColor(allRingsComplete ? .yellow : .secondary)
                }
                
                // Rings with Legend
                HStack(spacing: 20) {
                    // 3 Activity Rings
                    ActivityTripleRing(
                        outerProgress: stepsRingProgress,
                        middleProgress: moveRingProgress,
                        innerProgress: macrosRingProgress,
                        outerColor: .red,
                        middleColor: .orange,
                        innerColor: .yellow,
                        size: 100
                    )
                    
                    VStack(alignment: .leading, spacing: 10) {
                        ActivityLegendRow(name: "Steps", current: todaySteps, goal: stepGoal, color: .red)
                        ActivityLegendRow(name: "Workout", current: didWorkoutToday ? 1 : 0, goal: 1, color: .orange)
                        ActivityLegendRow(name: "Macros", current: macrosMetCount, goal: 3, color: .yellow)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            
            // Thin grey divider
            Rectangle()
                .fill(Color(.systemGray4))
                .frame(height: 1)
            
            // MARK: Weekly Progress Section
            VStack(spacing: 12) {
                HStack {
                    Text("Weekly Progress")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    Spacer()
                }
                
                VStack(spacing: 10) {
                    WeeklyActivityProgressRow(title: "Steps Goal", daysCompleted: weeklyStepsDaysMet, totalDays: 7, color: .red)
                    WeeklyActivityProgressRow(title: workoutProgressLabel, daysCompleted: weeklyWorkoutDaysMet, totalDays: weeklyWorkoutGoal, color: .orange)
                    WeeklyActivityProgressRow(title: "Macros Hit", daysCompleted: weeklyMacrosDaysMet, totalDays: 7, color: .yellow)
                }
            }
        }
        .padding(20)
        .background(
            ZStack {
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
            }
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.08), radius: 12, x: 0, y: 6)
    }
    
    // Weekly activity calculations
    private var weeklyStepsDaysMet: Int {
        // For now, check if today's steps met goal and estimate
        // In production, this would query HealthKit for weekly data
        stepsRingProgress >= 1.0 ? 1 : 0
    }
    
    private var weeklyWorkoutDaysMet: Int {
        // Count unique days with completed workouts this week (Sunday as start)
        let calendar = Calendar.current
        
        // Get the start of the current week (Sunday)
        var startOfWeek = Date()
        var interval: TimeInterval = 0
        _ = calendar.dateInterval(of: .weekOfYear, start: &startOfWeek, interval: &interval, for: Date())
        
        // Get unique days with workouts this week
        let workoutDates = workouts.filter { workout in
            guard let date = workout.date else { return false }
            return date >= startOfWeek && workout.isCompleted
        }.compactMap { workout -> Date? in
            guard let date = workout.date else { return nil }
            return calendar.startOfDay(for: date)
        }
        
        // Count unique days
        let uniqueDays = Set(workoutDates).count
        
        // Cap at the goal (can't exceed 100%)
        return min(uniqueDays, weeklyWorkoutGoal)
    }
    
    // MARK: - Smart Workout Goal Calculation
    
    /// Returns the weekly workout goal based on active program or user's declared available days
    private var weeklyWorkoutGoal: Int {
        // If user has an active program, use the program's workouts per week
        if let programDetails = cloudProgramService.activeProgramDetails {
            let workoutsPerWeek = programDetails.program.workoutsPerWeek
            return max(1, workoutsPerWeek) // Ensure at least 1 day
        }
        
        // Otherwise, use the user's declared available days from onboarding
        if let user = userManager.currentUser {
            let availableDays = Int(user.availableDays)
            if availableDays > 0 {
                return min(availableDays, 7) // Cap at 7 days
            }
        }
        
        // Default to 3 days per week if nothing is set
        return 3
    }
    
    /// Returns the label for the workout progress row
    private var workoutProgressLabel: String {
        // If user has an active program, show "Program Workout"
        if cloudProgramService.activeProgram != nil {
            return "Program Workout"
        }
        return "Workouts"
    }
    
    private var weeklyMacrosDaysMet: Int {
        // For now, check if today's macros met
        // In production, this would track daily macro achievements
        macrosComplete ? 1 : 0
    }
    
    // MARK: - Ring Calculations
    private var moveRingProgress: Double {
        didWorkoutToday ? 1.0 : 0.0
    }
    
    private var stepsRingProgress: Double {
        guard stepGoal > 0 else { return 0 }
        return min(1.0, Double(todaySteps) / Double(stepGoal))
    }
    
    private var macrosRingProgress: Double {
        macrosComplete ? 1.0 : Double(macrosMetCount) / 3.0
    }
    
    private var todaySteps: Int {
        HealthKitManager.shared.todaySteps
    }
    
    private var stepGoal: Int {
        HealthKitManager.shared.stepGoal
    }
    
    private var macrosMetCount: Int {
        var count = 0
        
        // Calories: must hit 100%, max 115% (15% over-buffer)
        let calorieMax = Int(Double(calorieGoal) * 1.15)
        if calorieGoal > 0 && consumedCaloriesToday >= calorieGoal && consumedCaloriesToday <= calorieMax { count += 1 }
        
        // Protein: hit 100% minimum, no max (more protein is beneficial)
        if proteinGoal > 0 && consumedProteinToday >= proteinGoal { count += 1 }
        
        // Fat: must hit 100%, max 120% (20% over-buffer)
        let fatMax = Int(Double(fatGoal) * 1.20)
        if fatGoal > 0 && consumedFatToday >= fatGoal && consumedFatToday <= fatMax { count += 1 }
        
        return count
    }
    
    // Check if user exceeded the buffer (for visual warning)
    private var caloriesExceeded: Bool {
        let calorieMax = Int(Double(calorieGoal) * 1.15)
        return consumedCaloriesToday > calorieMax
    }
    
    private var fatExceeded: Bool {
        let fatMax = Int(Double(fatGoal) * 1.20)
        return consumedFatToday > fatMax
    }
    
    private var macrosComplete: Bool {
        macrosMetCount >= 3
    }
    
    // Nutrition ring progress values
    private var caloriesRingProgress: Double {
        guard calorieGoal > 0 else { return 0 }
        return min(1.0, Double(consumedCaloriesToday) / Double(calorieGoal))
    }
    
    private var proteinRingProgress: Double {
        guard proteinGoal > 0 else { return 0 }
        return min(1.0, Double(consumedProteinToday) / Double(proteinGoal))
    }
    
    private var fatRingProgress: Double {
        guard fatGoal > 0 else { return 0 }
        return min(1.0, Double(consumedFatToday) / Double(fatGoal))
    }
    
    private var fuelRingProgress: Double {
        guard proteinGoal > 0 else { return 0 }
        return min(1.0, Double(consumedProteinToday) / Double(proteinGoal))
    }
    
    private var streakRingProgress: Double {
        guard nextStreakMilestone > 0 else { return 0 }
        return min(1.0, Double(currentStreak) / Double(nextStreakMilestone))
    }
    
    private var didWorkoutToday: Bool {
        let calendar = Calendar.current
        return workouts.contains { workout in
            guard let date = workout.date else { return false }
            return calendar.isDateInToday(date) && workout.isCompleted
        }
    }
    
    private var consumedProteinToday: Int {
        MealService.shared.todaysMeals.reduce(0) { $0 + $1.protein }
    }
    
    private var proteinGoal: Int {
        // Calculate based on user weight (0.8g per lb is a common baseline)
        guard let user = userManager.currentUser else { return 150 }
        let weightLbs = Int(user.weight)
        return max(100, Int(Double(weightLbs) * 0.8))
    }
    
    private var consumedCaloriesToday: Int {
        MealService.shared.todaysMeals.reduce(0) { $0 + $1.calories }
    }
    
    private var consumedFatToday: Int {
        MealService.shared.todaysMeals.reduce(0) { $0 + $1.fat }
    }
    
    private var calorieGoal: Int {
        guard let user = userManager.currentUser else { return 2200 }
        let weight = user.weight > 0 ? Int(user.weight) : 150
        let height = user.height > 0 ? Int(user.height) : 170
        
        if weight > 0 && height > 0 {
            let bmr = (10 * Double(weight)) + (6.25 * Double(height)) - 150
            return Int(bmr * 1.55)
        }
        return 2200
    }
    
    private var fatGoal: Int {
        // 30% of calories from fat (1g = 9 calories)
        return (calorieGoal * 30 / 100) / 9
    }
    
    private var nextStreakMilestone: Int {
        let milestones = [7, 14, 21, 30, 60, 90, 100, 150, 200, 365, 500, 1000]
        return milestones.first { $0 > currentStreak } ?? (currentStreak + 100)
    }
    
    private var allRingsComplete: Bool {
        stepsRingProgress >= 1.0 && moveRingProgress >= 1.0 && macrosComplete
    }
    
    private var ringCompletionText: String {
        let completed = [
            stepsRingProgress >= 1.0,
            moveRingProgress >= 1.0,
            macrosComplete
        ].filter { $0 }.count
        return "\(completed)/3 Complete"
    }
    
    private var formattedToday: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: Date())
    }
    
    // MARK: - Activity Calendar Section (Swipeable Cards)
    @State private var calendarCardIndex = 0
    
    private var activityCalendarSection: some View {
        VStack(spacing: 8) {
            TabView(selection: $calendarCardIndex) {
                // Card 1: Activity Calendar (GitHub-style)
                activityGridCard
                    .tag(0)
                
                // Card 2: Ring Stamp Calendar
                ringStampCalendarCard
                    .tag(1)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 440)
            
            // Page indicator dots
            HStack(spacing: 6) {
                ForEach(0..<2, id: \.self) { index in
                    Circle()
                        .fill(calendarCardIndex == index ? Color.purple : Color.gray.opacity(0.3))
                        .frame(width: 6, height: 6)
                        .scaleEffect(calendarCardIndex == index ? 1.0 : 0.8)
                        .animation(.easeInOut(duration: 0.2), value: calendarCardIndex)
                }
            }
        }
    }
    
    // MARK: - Activity Grid Card (Original)
    private var activityGridCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Activity Calendar")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                Spacer()
                
                Text("Last 12 weeks")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // GitHub-style contribution grid
            VStack(spacing: 4) {
                // Day labels
                HStack(spacing: 4) {
                    Text("")
                        .frame(width: 20)
                    ForEach(["S", "M", "T", "W", "T", "F", "S"], id: \.self) { day in
                        Text(day)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
                
                // Weeks grid
                ForEach(0..<12, id: \.self) { weekOffset in
                    HStack(spacing: 4) {
                        // Week number or month label
                        Text(weekLabel(for: weekOffset))
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)
                            .frame(width: 20, alignment: .trailing)
                        
                        ForEach(0..<7, id: \.self) { dayOffset in
                            let date = dateFor(week: weekOffset, day: dayOffset)
                            let intensity = workoutIntensity(for: date)
                            
                            RoundedRectangle(cornerRadius: 5)
                                .fill(activityColor(for: intensity, date: date))
                                .frame(height: 20)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            
            // Legend
            HStack {
                Text("Less")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                
                ForEach([0.0, 0.25, 0.5, 0.75, 1.0], id: \.self) { intensity in
                    RoundedRectangle(cornerRadius: 4)
                        .fill(activityColor(for: intensity, date: Date()))
                        .frame(width: 14, height: 14)
                }
                
                Text("More")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text("\(workoutsInLast12Weeks) workouts")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.purple)
            }
            
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: colorScheme == .dark
                                ? [Color(white: 0.15), Color(white: 0.10)]
                                : [Color.white, Color.white.opacity(0.95)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                RoundedRectangle(cornerRadius: 28, style: .continuous)
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
            }
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.12), radius: 16, x: 0, y: 8)
        .padding(.horizontal, 8)
    }
    
    // MARK: - Ring Stamp Calendar Card
    private var ringStampCalendarCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text("Ring History")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                Spacer()
                
                Text(currentMonthYear)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.purple)
            }
            
            // Day of week headers
            HStack(spacing: 0) {
                ForEach(["S", "M", "T", "W", "T", "F", "S"], id: \.self) { day in
                    Text(day)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.bottom, 4)
            
            // Calendar grid with mini rings - evenly spaced
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 7), spacing: 12) {
                // Add empty cells for days before the first of month
                ForEach(0..<firstDayOfMonthOffset, id: \.self) { _ in
                    Color.clear
                        .frame(height: 36)
                }
                
                // Days of the month
                ForEach(1...daysInCurrentMonth, id: \.self) { day in
                    let date = dateForDay(day)
                    let dayData = ringDataForDate(date)
                    
                    // Mini triple ring only - no day numbers for cleaner look
                    MiniDayRing(
                        stepsProgress: dayData.steps,
                        workoutProgress: dayData.workout,
                        macrosProgress: dayData.macros,
                        isToday: Calendar.current.isDateInToday(date),
                        isFuture: date > Date()
                    )
                    .frame(width: 36, height: 36)
                }
            }
            
            Spacer()
            
            // Stats Section
            VStack(spacing: 12) {
                // Ring Legend
                HStack(spacing: 16) {
                    HStack(spacing: 4) {
                        Circle().fill(Color.red).frame(width: 8, height: 8)
                        Text("Steps").font(.caption2).foregroundColor(.secondary)
                    }
                    HStack(spacing: 4) {
                        Circle().fill(Color.orange).frame(width: 8, height: 8)
                        Text("Workout").font(.caption2).foregroundColor(.secondary)
                    }
                    HStack(spacing: 4) {
                        Circle().fill(Color.yellow).frame(width: 8, height: 8)
                        Text("Macros").font(.caption2).foregroundColor(.secondary)
                    }
                    Spacer()
                }
                
                // Interesting Stats Row
                HStack(spacing: 0) {
                    // Perfect Days This Month
                    VStack(spacing: 4) {
                        Text("\(perfectRingDaysThisMonth)")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.purple, .pink],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                        Text("Perfect Days")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    
                    // Divider
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 1, height: 36)
                    
                    // Best Ring Streak
                    VStack(spacing: 4) {
                        HStack(spacing: 2) {
                            Text("\(bestRingStreak)")
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.orange, .red],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                            if bestRingStreak > 0 {
                                Image(systemName: "flame.fill")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                        }
                        Text("Best Streak")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    
                    // Divider
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 1, height: 36)
                    
                    // Current Streak
                    VStack(spacing: 4) {
                        HStack(spacing: 2) {
                            Text("\(currentRingStreak)")
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.green, .teal],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                            if currentRingStreak > 0 {
                                Image(systemName: "bolt.fill")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            }
                        }
                        Text("Current")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(
                            LinearGradient(
                                colors: [Color.purple.opacity(0.05), Color.orange.opacity(0.03)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .shadow(color: .purple.opacity(0.08), radius: 4, x: 0, y: 2)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.purple.opacity(0.1), lineWidth: 1)
                )
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.white)
                .shadow(color: .purple.opacity(0.12), radius: 20, x: 0, y: 10)
                .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
        )
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.8), lineWidth: 1)
        )
        .padding(.horizontal, 8)
    }
    
    // MARK: - Ring Calendar Helpers
    private var currentMonthYear: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: Date())
    }
    
    private var firstDayOfMonthOffset: Int {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month], from: Date())
        guard let firstOfMonth = calendar.date(from: components) else { return 0 }
        return calendar.component(.weekday, from: firstOfMonth) - 1
    }
    
    private var daysInCurrentMonth: Int {
        let calendar = Calendar.current
        let range = calendar.range(of: .day, in: .month, for: Date())
        return range?.count ?? 30
    }
    
    private func dateForDay(_ day: Int) -> Date {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month], from: Date())
        components.day = day
        return calendar.date(from: components) ?? Date()
    }
    
    private func ringDataForDate(_ date: Date) -> (steps: Double, workout: Double, macros: Double) {
        // For future dates, return 0
        if date > Date() {
            return (0, 0, 0)
        }
        
        // Check if there was a workout on this date
        let calendar = Calendar.current
        let hasWorkout = workouts.contains { workout in
            guard let workoutDate = workout.date else { return false }
            return calendar.isDate(workoutDate, inSameDayAs: date) && workout.isCompleted
        }
        
        // For demonstration, generate some sample data
        // In production, this would pull from HealthKit and meal tracking
        if calendar.isDateInToday(date) {
            return (stepsRingProgress, hasWorkout ? 1.0 : 0.0, macrosRingProgress)
        } else if hasWorkout {
            // Days with workouts tend to have better rings
            return (Double.random(in: 0.7...1.0), 1.0, Double.random(in: 0.5...1.0))
        } else {
            // Random data for past days (would be real data in production)
            let daysSinceDate = calendar.dateComponents([.day], from: date, to: Date()).day ?? 0
            if daysSinceDate < 7 {
                return (Double.random(in: 0.3...0.9), 0.0, Double.random(in: 0.2...0.8))
            } else {
                return (Double.random(in: 0.1...0.7), Double.random(in: 0...1) > 0.6 ? 1.0 : 0.0, Double.random(in: 0.1...0.6))
            }
        }
    }
    
    // MARK: - Ring Streak Stats
    private var perfectRingDaysThisMonth: Int {
        let calendar = Calendar.current
        var count = 0
        for day in 1...min(calendar.component(.day, from: Date()), daysInCurrentMonth) {
            let date = dateForDay(day)
            if date <= Date() {
                let data = ringDataForDate(date)
                // A "perfect" day is when all three rings are at least 80% complete
                if data.steps >= 0.8 && data.workout >= 0.8 && data.macros >= 0.8 {
                    count += 1
                }
            }
        }
        return count
    }
    
    private var bestRingStreak: Int {
        // Calculate best streak of consecutive days with at least one ring complete
        let calendar = Calendar.current
        var bestStreak = 0
        var currentStreak = 0
        
        // Look back 90 days
        for daysAgo in (0..<90).reversed() {
            guard let date = calendar.date(byAdding: .day, value: -daysAgo, to: Date()) else { continue }
            let data = ringDataForDate(date)
            
            // Consider it a "ring day" if workout ring is complete (most meaningful)
            if data.workout >= 1.0 {
                currentStreak += 1
                bestStreak = max(bestStreak, currentStreak)
            } else {
                currentStreak = 0
            }
        }
        
        return bestStreak
    }
    
    private var currentRingStreak: Int {
        // Calculate current streak (consecutive days ending today/yesterday with workout ring complete)
        let calendar = Calendar.current
        var streak = 0
        
        for daysAgo in 0..<90 {
            guard let date = calendar.date(byAdding: .day, value: -daysAgo, to: Date()) else { break }
            let data = ringDataForDate(date)
            
            // Skip today if it's early in the day (give them a chance)
            if daysAgo == 0 && calendar.component(.hour, from: Date()) < 12 {
                continue
            }
            
            if data.workout >= 1.0 {
                streak += 1
            } else {
                break
            }
        }
        
        return streak
    }
    
    // MARK: - Calendar Helper Functions
    private func weekLabel(for weekOffset: Int) -> String {
        let calendar = Calendar.current
        guard let date = calendar.date(byAdding: .weekOfYear, value: -(11 - weekOffset), to: Date()) else { return "" }
        
        // Show month abbreviation for first week of each month
        let day = calendar.component(.day, from: date)
        if day <= 7 {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM"
            return formatter.string(from: date)
        }
        return ""
    }
    
    private func dateFor(week weekOffset: Int, day dayOffset: Int) -> Date {
        let calendar = Calendar.current
        let today = Date()
        
        // Start from 12 weeks ago
        guard let startOfPeriod = calendar.date(byAdding: .weekOfYear, value: -11, to: today) else { return today }
        
        // Get to start of that week (Sunday)
        let weekday = calendar.component(.weekday, from: startOfPeriod)
        guard let startOfWeek = calendar.date(byAdding: .day, value: -(weekday - 1), to: startOfPeriod) else { return today }
        
        // Add weeks and days
        guard let targetWeek = calendar.date(byAdding: .weekOfYear, value: weekOffset, to: startOfWeek),
              let targetDate = calendar.date(byAdding: .day, value: dayOffset, to: targetWeek) else { return today }
        
        return targetDate
    }
    
    private func workoutIntensity(for date: Date) -> Double {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else { return 0 }
        
        let dayWorkouts = workouts.filter { workout in
            guard let workoutDate = workout.date else { return false }
            return workoutDate >= startOfDay && workoutDate < endOfDay && workout.isCompleted
        }
        
        if dayWorkouts.isEmpty { return 0 }
        
        // Calculate intensity based on duration
        let totalDuration = dayWorkouts.reduce(0) { $0 + Int($1.duration) }
        let durationMinutes = totalDuration / 60
        
        // Scale: 0-30 min = 0.25, 30-60 = 0.5, 60-90 = 0.75, 90+ = 1.0
        if durationMinutes >= 90 { return 1.0 }
        if durationMinutes >= 60 { return 0.75 }
        if durationMinutes >= 30 { return 0.5 }
        return 0.25
    }
    
    private func activityColor(for intensity: Double, date: Date) -> Color {
        // Future dates are very light
        if date > Date() {
            return colorScheme == .dark 
                ? Color.white.opacity(0.05) 
                : Color(.systemGray6)
        }
        
        // No activity - slightly visible
        if intensity == 0 {
            return colorScheme == .dark 
                ? Color.white.opacity(0.1) 
                : Color(.systemGray5)
        }
        
        // Activity gradient from light to vibrant purple
        let baseOpacity = colorScheme == .dark ? 0.4 : 0.3
        return Color.purple.opacity(baseOpacity + (intensity * 0.6))
    }
    
    private var workoutsInLast12Weeks: Int {
        let calendar = Calendar.current
        guard let startDate = calendar.date(byAdding: .weekOfYear, value: -12, to: Date()) else { return 0 }
        
        return workouts.filter { workout in
            guard let date = workout.date else { return false }
            return date >= startDate && workout.isCompleted
        }.count
    }
    
    private var streakSection: some View {
        HStack(spacing: 16) {
            // Current Streak
            VStack(spacing: 12) {
                HStack {
                    Image(systemName: "flame.fill")
                        .font(.title2)
                        .foregroundColor(.orange)
                    Text("Current Streak")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .minimumScaleFactor(0.8)
                        .lineLimit(1)
                }
                
                Text("\(currentStreak)")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundColor(.orange)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                
                Text(currentStreak == 1 ? "day" : "days")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                // Streak motivation
                Text(streakMotivationMessage)
                    .font(.caption)
                    .foregroundColor(.orange)
                    .multilineTextAlignment(.center)
                    .fontWeight(.medium)
                    .minimumScaleFactor(0.9)
                    .lineLimit(2)
                
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 160, maxHeight: 160)
            .padding(20)
            .background(
                ZStack {
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
                }
            )
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.08), radius: 12, x: 0, y: 6)
            
            // Longest Streak
            VStack(spacing: 12) {
                HStack {
                    Image(systemName: "trophy.fill")
                        .font(.title2)
                        .foregroundColor(.yellow)
                    Text("Best Streak")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .minimumScaleFactor(0.8)
                        .lineLimit(1)
                }
                
                Text("\(longestStreak)")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundColor(.yellow)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                
                Text(longestStreak == 1 ? "day" : "days")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                // Achievement indicator
                Group {
                    if currentStreak == longestStreak && currentStreak > 0 {
                        Text("Personal Best! 🎉")
                            .foregroundColor(.yellow)
                    } else {
                        Text("Keep going!")
                            .foregroundColor(.secondary)
                    }
                }
                .font(.caption)
                .fontWeight(.bold)
                .minimumScaleFactor(0.9)
                .lineLimit(2)
                
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 160, maxHeight: 160)
            .padding(20)
            .background(
                ZStack {
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
                }
            )
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.08), radius: 12, x: 0, y: 6)
        }
    }
    
    private var timeFramePicker: some View {
        Picker("Time Frame", selection: $selectedTimeFrame) {
            ForEach(TimeFrame.allCases, id: \.self) { timeFrame in
                Text(timeFrame.rawValue).tag(timeFrame)
            }
        }
        .pickerStyle(SegmentedPickerStyle())
    }
    
    private var workoutFrequencyChart: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Workout Activity")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("Your consistency over time")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
                
                // Activity indicator
                HStack(spacing: 8) {
                    Circle()
                        .fill(activityColor)
                        .frame(width: 8, height: 8)
                    Text(activityLevel)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(activityColor)
                }
            }
            
            if #available(iOS 16.0, *) {
                Chart(workoutDataForTimeFrame) { item in
                    BarMark(
                        x: .value("Date", item.date),
                        y: .value("Workouts", item.count)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            gradient: Gradient(colors: [.blue, .cyan]),
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .cornerRadius(4)
                }
                .frame(height: 220)
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: selectedTimeFrame == .week ? .day : selectedTimeFrame == .month ? .weekOfYear : .month)) { _ in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel(format: selectedTimeFrame == .week ? .dateTime.weekday(.abbreviated) : selectedTimeFrame == .month ? .dateTime.day() : .dateTime.month(.abbreviated))
                    }
                }
            } else {
                // Enhanced fallback for iOS 15
                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(workoutDataForTimeFrame, id: \.date) { item in
                        VStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(
                                    LinearGradient(
                                        gradient: Gradient(colors: [.blue, .cyan]),
                                        startPoint: .bottom,
                                        endPoint: .top
                                    )
                                )
                                .frame(width: 12, height: max(CGFloat(item.count * 30), 4))
                            
                            Text("\(item.count)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .frame(height: 180)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(20)
        .background(
            ZStack {
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
            }
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.08), radius: 12, x: 0, y: 6)
    }
    
    // MARK: - Comprehensive Stats Grid
    private var comprehensiveStatsGrid: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Your Stats")
                .font(.title2)
                .fontWeight(.bold)
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2), spacing: 12) {
                EnhancedStatCard(
                    title: "Total Time",
                    value: formatWorkoutTime(totalWorkoutMinutes),
                    icon: "clock.fill",
                    color: .blue,
                    trend: .neutral,
                    subtitle: "Time invested"
                )
                
                EnhancedStatCard(
                    title: "This Week",
                    value: "\(workoutsThisWeek)",
                    icon: "calendar.badge.clock",
                    color: .green,
                    trend: workoutTrendThisWeek,
                    subtitle: "\(workoutsThisWeek) workouts"
                )
                
                EnhancedStatCard(
                    title: "Average/Week",
                    value: String(format: "%.1f", averageWorkoutsPerWeek),
                    icon: "chart.line.uptrend.xyaxis",
                    color: .purple,
                    trend: .neutral,
                    subtitle: "Consistency"
                )
                
                EnhancedStatCard(
                    title: "Best Month",
                    value: "\(bestMonthWorkouts)",
                    icon: "trophy.fill",
                    color: .yellow,
                    trend: .neutral,
                    subtitle: bestMonthName
                )
                
                EnhancedStatCard(
                    title: "Total Sets",
                    value: "\(totalSets)",
                    icon: "repeat.circle.fill",
                    color: .orange,
                    trend: .neutral,
                    subtitle: "Sets completed"
                )
                
                EnhancedStatCard(
                    title: "Total Reps",
                    value: formatLargeNumber(totalReps),
                    icon: "arrow.up.circle.fill",
                    color: .red,
                    trend: .neutral,
                    subtitle: "Reps performed"
                )
            }
        }
        .padding(24)
        .background(
            ZStack {
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
            }
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.08), radius: 12, x: 0, y: 6)
    }
    
    // MARK: - Muscle Group Analytics
    private var muscleGroupAnalytics: some View {
        VStack(spacing: 16) {
            // Photorealistic Muscle Map
            MuscleMapView(muscleData: convertToMuscleMapData(enhancedMuscleGroupData))
            
            // Additional muscle group insights below the map
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Training Insights")
                        .font(.title3)
                        .fontWeight(.semibold)
                    Spacer()
                    Text("Top: \(topMuscleGroup)")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.blue)
                }
                
                if let recommendation = muscleGroupRecommendation {
                    HStack {
                        Image(systemName: "lightbulb.fill")
                            .foregroundColor(.yellow)
                        Text(recommendation)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(.systemGray6))
                    )
                }
                
                // Quick stats grid
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    ForEach(enhancedMuscleGroupData.prefix(6), id: \.name) { muscle in
                        VStack(spacing: 4) {
                            Text("\(muscle.count)")
                                .font(.headline)
                                .fontWeight(.bold)
                                .foregroundColor(muscle.color)
                            Text(muscle.name)
                                .font(.caption2)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(muscle.color.opacity(0.1))
                        )
                    }
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 1)
            )
        }
    }
    
    // MARK: - Progress Timeline
    private var progressTimeline: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Progress Timeline")
                .font(.title2)
                .fontWeight(.bold)
            
            VStack(spacing: 12) {
                ForEach(progressMilestones, id: \.date) { milestone in
                    HStack(spacing: 12) {
                        // Timeline dot
                        Circle()
                            .fill(milestone.color)
                            .frame(width: 12, height: 12)
                            .overlay(
                                Circle()
                                    .stroke(milestone.color.opacity(0.3), lineWidth: 4)
                            )
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(milestone.title)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Text(milestone.description)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Text(formatTimeAgo(milestone.date))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(20)
        .background(
            ZStack {
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
            }
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.08), radius: 12, x: 0, y: 6)
    }
    
    // MARK: - Personal Records
    private var personalRecordsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Personal Records")
                .font(.title2)
                .fontWeight(.bold)
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2), spacing: 12) {
                PRCard(
                    title: "Heaviest Lift",
                    value: heaviestWeight > 0 ? "\(Int(heaviestWeight)) lbs" : "No data",
                    exercise: heaviestWeightExercise,
                    icon: "dumbbell.fill",
                    color: .red
                )
                
                PRCard(
                    title: "Most Reps",
                    value: "\(highestReps)",
                    exercise: highestRepsExercise,
                    icon: "repeat.circle.fill",
                    color: .orange
                )
                
                PRCard(
                    title: "Longest Workout",
                    value: formatWorkoutTime(longestWorkoutMinutes),
                    exercise: "Single session",
                    icon: "stopwatch.fill",
                    color: .blue
                )
                
                PRCard(
                    title: "Most Sets",
                    value: "\(mostSetsInWorkout)",
                    exercise: "In one workout",
                    icon: "list.number",
                    color: .purple
                )
            }
        }
        .padding(20)
        .background(
            ZStack {
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
            }
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.08), radius: 12, x: 0, y: 6)
    }
    
    // MARK: - Achievements Gallery
    private var achievementsGallery: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Achievement Gallery")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                NavigationLink(destination: AllAchievementsView(achievements: allAchievements)) {
                    Text("View All")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.blue)
                }
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(allAchievements, id: \.id) { achievement in
                        AchievementBadge(
                            title: achievement.title,
                            description: achievement.description,
                            icon: achievement.icon,
                            color: achievement.color,
                            isEarned: achievement.isEarned,
                            progress: achievement.progress
                        )
                    }
                }
                .padding(.horizontal, 4)
            }
        }
        .padding(20)
        .background(
            ZStack {
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
            }
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.08), radius: 12, x: 0, y: 6)
    }
    
    // MARK: - Monthly Summary
    private var monthlySummary: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("This Month's Summary")
                .font(.title2)
                .fontWeight(.bold)
            
            VStack(spacing: 16) {
                // Monthly goal progress
                HStack {
                    VStack(alignment: .leading) {
                        Text("Monthly Goal")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("\(workoutsThisMonth)/\(monthlyGoal) workouts")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    CircularProgressView(
                        progress: Double(workoutsThisMonth) / Double(monthlyGoal),
                        color: workoutsThisMonth >= monthlyGoal ? .green : .blue
                    )
                }
                
                // Monthly stats
                HStack(spacing: 20) {
                    MonthlyStatView(
                        title: "Workouts",
                        value: "\(workoutsThisMonth)",
                        change: monthlyWorkoutChange,
                        color: .blue
                    )
                    
                    MonthlyStatView(
                        title: "Hours",
                        value: String(format: "%.1f", Double(totalWorkoutMinutesThisMonth) / 60.0),
                        change: monthlyTimeChange,
                        color: .green
                    )
                    
                    MonthlyStatView(
                        title: "Streak",
                        value: "\(currentStreak)",
                        change: monthlyStreakChange,
                        color: .orange
                    )
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [Color.blue.opacity(0.05), Color.purple.opacity(0.05)]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.blue.opacity(0.1), lineWidth: 1)
                )
        )
    }
    
    
    // MARK: - Computed Properties
    
    private var totalWorkouts: Int {
        workouts.count
    }
    
    private var xpProgressWidth: CGFloat {
        let currentXP = Double(userManager.currentUser?.xp ?? 0)
        let levelXP = Double(userManager.getLevel() * 100)
        let progress = levelXP > 0 ? currentXP / levelXP : 0
        return CGFloat(progress) * 280 // Approximate width of progress bar
    }
    
    private var currentStreak: Int {
        Int(userManager.currentUser?.currentStreak ?? 0)
    }
    
    private var longestStreak: Int {
        Int(userManager.currentUser?.longestStreak ?? 0)
    }
    
    private var streakMotivationMessage: String {
        let messages: [String]
        switch currentStreak {
        case 0:
            messages = ["Start your journey!", "Day 1 awaits! 💪", "Begin today! 🌟"]
        case 1:
            messages = ["Great start! 🚀", "Day 1 done! 💪", "Momentum begins! ⚡"]
        case 2...3:
            messages = ["Building habits! 💪", "Consistency loading... 🔄", "Keep stacking! 📈"]
        case 4...6:
            messages = ["Almost a week! 🔥", "Crushing it! 💪", "Unstoppable energy! ⚡"]
        case 7...13:
            messages = ["On fire! 🔥", "Week warrior! 💪", "Top 20% now! 🌟"]
        case 14...20:
            messages = ["2 weeks strong! ⚡", "Elite dedication! 🏆", "Habit formed! 💎"]
        case 21...29:
            messages = ["3 weeks! 🔥", "Unstoppable! ⚡", "True champion! 🏆"]
        case 30...49:
            messages = ["Legendary! 🏆", "30+ days! 👑", "Month master! 💎"]
        case 50...99:
            messages = ["50+ days! 👑", "Absolute beast! 🦁", "Elite 1%! 💎"]
        default:
            messages = ["\(currentStreak) days! 👑", "Living legend! 🏆", "Unstoppable! 💎"]
        }
        return messages.randomElement() ?? "Keep going! 💪"
    }
    
    private var activityLevel: String {
        let weeklyAverage = averageWorkoutsPerWeek
        switch weeklyAverage {
        case 0..<1: return "Getting Started"
        case 1..<3: return "Building Habits"
        case 3..<5: return "Very Active"
        case 5..<7: return "Highly Active"
        default: return "Elite Level"
        }
    }
    
    private var activityColor: Color {
        let weeklyAverage = averageWorkoutsPerWeek
        switch weeklyAverage {
        case 0..<1: return .gray
        case 1..<3: return .blue
        case 3..<5: return .green
        case 5..<7: return .orange
        default: return .red
        }
    }
    
    private var workoutDataForTimeFrame: [WorkoutDataPoint] {
        let calendar = Calendar.current
        let now = Date()
        var data: [WorkoutDataPoint] = []
        
        let dateRange: [Date]
        switch selectedTimeFrame {
        case .week:
            dateRange = (0..<7).compactMap { calendar.date(byAdding: .day, value: -$0, to: now) }
        case .month:
            dateRange = (0..<30).compactMap { calendar.date(byAdding: .day, value: -$0, to: now) }
        case .year:
            dateRange = (0..<12).compactMap { calendar.date(byAdding: .month, value: -$0, to: now) }
        case .all:
            // For all time, group by months from first workout
            guard let firstWorkout = workouts.last?.date else { return [] }
            let monthsBetween = calendar.dateComponents([.month], from: firstWorkout, to: now).month ?? 0
            dateRange = (0...monthsBetween).compactMap { calendar.date(byAdding: .month, value: -$0, to: now) }
        }
        
        for date in dateRange {
            let startOfPeriod = calendar.startOfDay(for: date)
            let endOfPeriod: Date
            
            switch selectedTimeFrame {
            case .week, .month:
                endOfPeriod = calendar.date(byAdding: .day, value: 1, to: startOfPeriod) ?? startOfPeriod
            case .year, .all:
                endOfPeriod = calendar.date(byAdding: .month, value: 1, to: startOfPeriod) ?? startOfPeriod
            }
            
            let workoutsInPeriod = workouts.filter { workout in
                guard let workoutDate = workout.date else { return false }
                return workoutDate >= startOfPeriod && workoutDate < endOfPeriod
            }
            
            data.append(WorkoutDataPoint(date: startOfPeriod, count: workoutsInPeriod.count))
        }
        
        return data.reversed()
    }
    
    private var totalWorkoutMinutes: Int {
        workouts.reduce(0) { $0 + Int($1.duration / 60) }
    }
    
    private var workoutsThisWeek: Int {
        let calendar = Calendar.current
        let now = Date()
        let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        
        return workouts.filter { workout in
            guard let date = workout.date else { return false }
            return date >= startOfWeek
        }.count
    }
    
    private var workoutTrendThisWeek: StatTrend {
        let lastWeekCount = getWorkoutCount(weeksAgo: 1)
        if workoutsThisWeek > lastWeekCount { return .up }
        if workoutsThisWeek < lastWeekCount { return .down }
        return .neutral
    }
    
    private var workoutsThisMonth: Int {
        let calendar = Calendar.current
        let now = Date()
        let startOfMonth = calendar.dateInterval(of: .month, for: now)?.start ?? now
        
        return workouts.filter { workout in
            guard let date = workout.date else { return false }
            return date >= startOfMonth
        }.count
    }
    
    private var averageWorkoutsPerWeek: Double {
        let calendar = Calendar.current
        let now = Date()
        guard let startDate = calendar.date(byAdding: .month, value: -3, to: now) else { return 0 }
        
        let recentWorkouts = workouts.filter { workout in
            guard let date = workout.date else { return false }
            return date >= startDate
        }
        
        let weeks = calendar.dateComponents([.weekOfYear], from: startDate, to: now).weekOfYear ?? 1
        return weeks > 0 ? Double(recentWorkouts.count) / Double(weeks) : 0
    }
    
    private var bestMonthWorkouts: Int {
        let calendar = Calendar.current
        let now = Date()
        var maxWorkouts = 0
        
        for i in 0..<12 {
            guard let monthStart = calendar.date(byAdding: .month, value: -i, to: now),
                  let monthInterval = calendar.dateInterval(of: .month, for: monthStart) else { continue }
            
            let monthWorkouts = workouts.filter { workout in
                guard let date = workout.date else { return false }
                return monthInterval.contains(date)
            }.count
            
            maxWorkouts = max(maxWorkouts, monthWorkouts)
        }
        
        return maxWorkouts
    }
    
    private var bestMonthName: String {
        let calendar = Calendar.current
        let now = Date()
        var maxWorkouts = 0
        var bestMonth = now
        
        for i in 0..<12 {
            guard let monthStart = calendar.date(byAdding: .month, value: -i, to: now),
                  let monthInterval = calendar.dateInterval(of: .month, for: monthStart) else { continue }
            
            let monthWorkouts = workouts.filter { workout in
                guard let date = workout.date else { return false }
                return monthInterval.contains(date)
            }.count
            
            if monthWorkouts > maxWorkouts {
                maxWorkouts = monthWorkouts
                bestMonth = monthStart
            }
        }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yyyy"
        return formatter.string(from: bestMonth)
    }
    
    private var totalSets: Int {
        workouts.reduce(0) { total, workout in
            guard let exercises = workout.exercises?.allObjects as? [WorkoutExercise] else { return total }
            return total + exercises.reduce(0) { exerciseTotal, exercise in
                guard let sets = exercise.sets?.allObjects as? [WorkoutSet] else { return exerciseTotal }
                return exerciseTotal + sets.count
            }
        }
    }
    
    private var totalReps: Int {
        workouts.reduce(0) { total, workout in
            guard let exercises = workout.exercises?.allObjects as? [WorkoutExercise] else { return total }
            return total + exercises.reduce(0) { exerciseTotal, exercise in
                guard let sets = exercise.sets?.allObjects as? [WorkoutSet] else { return exerciseTotal }
                return exerciseTotal + sets.reduce(0) { setTotal, set in
                    setTotal + Int(set.reps)
                }
            }
        }
    }
    
    private var enhancedMuscleGroupData: [EnhancedMuscleGroupData] {
        let muscleGroups = [
            ("Chest", Color.red),
            ("Back", Color.blue),
            ("Legs", Color.green),
            ("Shoulders", Color.orange),
            ("Arms", Color.purple),
            ("Core", Color.cyan)
        ]
        
        var data: [EnhancedMuscleGroupData] = []
        
        for (muscle, color) in muscleGroups {
            let count = workouts.reduce(0) { total, workout in
                guard let exercises = workout.exercises?.allObjects as? [WorkoutExercise] else { return total }
                return total + exercises.filter { exercise in
                    (exercise.exercise?.muscleGroups as? [String])?.contains(muscle) ?? false
                }.reduce(0) { exerciseTotal, exercise in
                    guard let sets = exercise.sets?.allObjects as? [WorkoutSet] else { return exerciseTotal }
                    return exerciseTotal + sets.count
                }
            }
            
            data.append(EnhancedMuscleGroupData(name: muscle, count: count, color: color, intensity: 0))
        }
        
        // Calculate intensities
        let maxCount = data.map { $0.count }.max() ?? 1
        data = data.map { item in
            EnhancedMuscleGroupData(
                name: item.name,
                count: item.count,
                color: item.color,
                intensity: maxCount > 0 ? Double(item.count) / Double(maxCount) : 0.0
            )
        }
        
        return data.sorted { $0.count > $1.count }
    }
    
    private var topMuscleGroup: String {
        enhancedMuscleGroupData.first?.name ?? "None"
    }
    
    private var muscleGroupRecommendation: String? {
        let sortedMuscles = enhancedMuscleGroupData.sorted { $0.count < $1.count }
        if let leastWorked = sortedMuscles.first, leastWorked.count < (enhancedMuscleGroupData.first?.count ?? 0) / 3 {
            return "Consider adding more \(leastWorked.name.lowercased()) exercises for better balance"
        }
        return nil
    }
    
    // Convert EnhancedMuscleGroupData to MuscleMapView format
    private func convertToMuscleMapData(_ enhancedData: [EnhancedMuscleGroupData]) -> [MuscleGroupData] {
        // Map the general categories to specific muscle groups for the body map
        var muscleMapData: [MuscleGroupData] = []
        
        for item in enhancedData {
            switch item.name {
            case "Chest":
                muscleMapData.append(MuscleGroupData(name: "Chest", count: item.count, color: item.color, intensity: item.intensity))
            case "Back":
                muscleMapData.append(MuscleGroupData(name: "Back", count: item.count, color: item.color, intensity: item.intensity))
            case "Legs":
                // Split legs into specific muscle groups
                let legCount = item.count / 3 // Distribute across quad, hamstring, calves
                muscleMapData.append(MuscleGroupData(name: "Quadriceps", count: legCount, color: item.color, intensity: item.intensity))
                muscleMapData.append(MuscleGroupData(name: "Hamstrings", count: legCount, color: item.color.opacity(0.8), intensity: item.intensity * 0.8))
                muscleMapData.append(MuscleGroupData(name: "Calves", count: legCount, color: item.color.opacity(0.6), intensity: item.intensity * 0.6))
                muscleMapData.append(MuscleGroupData(name: "Glutes", count: legCount, color: item.color.opacity(0.9), intensity: item.intensity * 0.9))
            case "Shoulders":
                muscleMapData.append(MuscleGroupData(name: "Shoulders", count: item.count, color: item.color, intensity: item.intensity))
            case "Arms":
                // Split arms into biceps and triceps
                let armCount = item.count / 2
                muscleMapData.append(MuscleGroupData(name: "Biceps", count: armCount, color: item.color, intensity: item.intensity))
                muscleMapData.append(MuscleGroupData(name: "Triceps", count: armCount, color: item.color.opacity(0.8), intensity: item.intensity * 0.8))
            case "Core":
                muscleMapData.append(MuscleGroupData(name: "Abs", count: item.count, color: item.color, intensity: item.intensity))
            default:
                muscleMapData.append(MuscleGroupData(name: item.name, count: item.count, color: item.color, intensity: item.intensity))
            }
        }
        
        return muscleMapData
    }
    
    // Additional computed properties for new features
    private var progressMilestones: [ProgressMilestone] {
        var milestones: [ProgressMilestone] = []
        
        // Add workout milestones
        let workoutMilestones = [1, 5, 10, 25, 50, 100, 200]
        for milestone in workoutMilestones {
            if totalWorkouts >= milestone {
                let date = workouts.dropLast(totalWorkouts - milestone).last?.date ?? Date()
                milestones.append(ProgressMilestone(
                    date: date,
                    title: "\(milestone) Workouts",
                    description: "Reached \(milestone) total workouts",
                    color: .blue
                ))
            }
        }
        
        // Add streak milestones
        if longestStreak >= 7 {
            milestones.append(ProgressMilestone(
                date: Date(), // Approximate
                title: "Week Streak",
                description: "Achieved 7-day streak",
                color: .orange
            ))
        }
        
        if longestStreak >= 30 {
            milestones.append(ProgressMilestone(
                date: Date(), // Approximate
                title: "Month Streak",
                description: "Achieved 30-day streak",
                color: .red
            ))
        }
        
        return milestones.sorted { $0.date > $1.date }.prefix(5).map { $0 }
    }
    
    // ⚡️ PERFORMANCE: Use cached value (computed in background task)
    private var heaviestWeight: Double {
        if hasComputedPRs {
            return cachedHeaviestWeight
        }
        // Quick fallback for initial render
        return 0
    }
    
    private var heaviestWeightExercise: String {
        var maxWeight: Double = 0
        var exerciseName = "None"
        
        for workout in workouts {
            guard let exercises = workout.exercises?.allObjects as? [WorkoutExercise] else { continue }
            for exercise in exercises {
                guard let sets = exercise.sets?.allObjects as? [WorkoutSet] else { continue }
                if let maxSetWeight = sets.map({ $0.weight }).max(), maxSetWeight > maxWeight {
                    maxWeight = maxSetWeight
                    exerciseName = exercise.exercise?.name ?? "Unknown"
                }
            }
        }
        
        return exerciseName
    }
    
    // ⚡️ PERFORMANCE: Use cached value (computed in background task)
    private var highestReps: Int {
        if hasComputedPRs {
            return cachedHighestReps
        }
        return 0
    }
    
    private var highestRepsExercise: String {
        var maxReps: Int = 0
        var exerciseName = "None"
        
        for workout in workouts {
            guard let exercises = workout.exercises?.allObjects as? [WorkoutExercise] else { continue }
            for exercise in exercises {
                guard let sets = exercise.sets?.allObjects as? [WorkoutSet] else { continue }
                if let maxSetReps = sets.map({ Int($0.reps) }).max(), maxSetReps > maxReps {
                    maxReps = maxSetReps
                    exerciseName = exercise.exercise?.name ?? "Unknown"
                }
            }
        }
        
        return exerciseName
    }
    
    // ⚡️ PERFORMANCE: Use cached value (computed in background task)
    private var longestWorkoutMinutes: Int {
        if hasComputedPRs {
            return cachedLongestWorkoutMinutes
        }
        return 0
    }
    
    // ⚡️ PERFORMANCE: Use cached value (computed in background task)
    private var mostSetsInWorkout: Int {
        if hasComputedPRs {
            return cachedMostSets
        }
        return 0
    }
    
    // ⚡️ PERFORMANCE: Use cached achievements instead of recomputing on every render
    private var allAchievements: [Achievement] {
        // Return cached if available
        if hasLoadedAchievements && !cachedAchievements.isEmpty {
            return cachedAchievements
        }
        
        // Return a minimal placeholder while loading
        return []
    }
    
    
    private var monthlyGoal: Int { 12 } // Default monthly goal
    
    private var totalWorkoutMinutesThisMonth: Int {
        let calendar = Calendar.current
        let now = Date()
        let startOfMonth = calendar.dateInterval(of: .month, for: now)?.start ?? now
        
        return workouts.filter { workout in
            guard let date = workout.date else { return false }
            return date >= startOfMonth
        }.reduce(0) { $0 + Int($1.duration / 60) }
    }
    
    private var monthlyWorkoutChange: StatChange {
        let lastMonthCount = getWorkoutCount(monthsAgo: 1)
        let change = workoutsThisMonth - lastMonthCount
        return StatChange(value: change, isPositive: change >= 0)
    }
    
    private var monthlyTimeChange: StatChange {
        let lastMonthMinutes = getWorkoutMinutes(monthsAgo: 1)
        let change = totalWorkoutMinutesThisMonth - lastMonthMinutes
        return StatChange(value: change, isPositive: change >= 0)
    }
    
    private var monthlyStreakChange: StatChange {
        // Simplified - in reality you'd track historical streak data
        return StatChange(value: 0, isPositive: currentStreak > 0)
    }
    
    // MARK: - Helper Functions
    
    private func formatWorkoutTime(_ minutes: Int) -> String {
        if minutes < 60 {
            return "\(minutes)m"
        } else {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            return remainingMinutes > 0 ? "\(hours)h \(remainingMinutes)m" : "\(hours)h"
        }
    }
    
    private func formatLargeNumber(_ number: Int) -> String {
        if number >= 1000 {
            return String(format: "%.1fK", Double(number) / 1000.0)
        }
        return "\(number)"
    }
    
    private func formatTimeAgo(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
    
    private func getWorkoutCount(weeksAgo: Int) -> Int {
        let calendar = Calendar.current
        let now = Date()
        guard let startDate = calendar.date(byAdding: .weekOfYear, value: -weeksAgo, to: now),
              let endDate = calendar.date(byAdding: .weekOfYear, value: -(weeksAgo - 1), to: now) else { return 0 }
        
        return workouts.filter { workout in
            guard let date = workout.date else { return false }
            return date >= startDate && date < endDate
        }.count
    }
    
    private func getWorkoutCount(monthsAgo: Int) -> Int {
        let calendar = Calendar.current
        let now = Date()
        guard let targetMonth = calendar.date(byAdding: .month, value: -monthsAgo, to: now),
              let monthInterval = calendar.dateInterval(of: .month, for: targetMonth) else { return 0 }
        
        return workouts.filter { workout in
            guard let date = workout.date else { return false }
            return monthInterval.contains(date)
        }.count
    }
    
    private func getWorkoutMinutes(monthsAgo: Int) -> Int {
        let calendar = Calendar.current
        let now = Date()
        guard let targetMonth = calendar.date(byAdding: .month, value: -monthsAgo, to: now),
              let monthInterval = calendar.dateInterval(of: .month, for: targetMonth) else { return 0 }
        
        return workouts.filter { workout in
            guard let date = workout.date else { return false }
            return monthInterval.contains(date)
        }.reduce(0) { $0 + Int($1.duration / 60) }
    }
}

// MARK: - Data Models

struct WorkoutDataPoint: Identifiable {
    let id = UUID()
    let date: Date
    let count: Int
}


struct EnhancedMuscleGroupData {
    let name: String
    let count: Int
    let color: Color
    let intensity: Double
}

// Supporting data structure for muscle map
struct MuscleGroupData {
    let name: String
    let count: Int
    let color: Color
    let intensity: Double // 0.0 to 1.0
}

struct ProgressMilestone {
    let date: Date
    let title: String
    let description: String
    let color: Color
}

struct Achievement {
    let id: String
    let title: String
    let description: String
    let icon: String
    let color: Color
    let isEarned: Bool
    let progress: Double
}

enum StatTrend {
    case up, down, neutral
}

struct StatChange {
    let value: Int
    let isPositive: Bool
}

// MARK: - Supporting Views

struct EnhancedStatCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let value: String
    let icon: String
    let color: Color
    let trend: StatTrend
    let subtitle: String
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                Spacer()
                if trend != .neutral {
                    Image(systemName: trend == .up ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                        .font(.caption)
                        .foregroundColor(trend == .up ? .green : .red)
                }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(value)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .minimumScaleFactor(0.8)
                    .lineLimit(1)
                
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .minimumScaleFactor(0.9)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Spacer(minLength: 0)
        }
        .frame(height: 120)
        .padding(16)
        .background(
            ZStack {
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
            }
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.08), radius: 12, x: 0, y: 6)
    }
}

struct PRCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let value: String
    let exercise: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                Spacer()
                Image(systemName: "star.fill")
                    .font(.caption)
                    .foregroundColor(.yellow)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(value)
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .minimumScaleFactor(0.8)
                    .lineLimit(1)
                
                Text(exercise)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .minimumScaleFactor(0.9)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Spacer(minLength: 0)
        }
        .frame(height: 120)
        .padding(16)
        .background(
            ZStack {
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
            }
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.08), radius: 12, x: 0, y: 6)
    }
}

struct AchievementBadge: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let description: String
    let icon: String
    let color: Color
    let isEarned: Bool
    let progress: Double
    
    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(isEarned ? color : Color.gray.opacity(0.3))
                    .frame(width: 60, height: 60)
                
                if !isEarned {
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(color, lineWidth: 4)
                        .frame(width: 60, height: 60)
                        .rotationEffect(.degrees(-90))
                }
                
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(isEarned ? .white : color)
            }
            
            VStack(spacing: 4) {
                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                
                if !isEarned {
                    Text("\(Int(progress * 100))%")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(color)
                }
            }
        }
        .frame(width: 120)
        .padding(16)
        .background(
            ZStack {
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
            }
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.08), radius: 12, x: 0, y: 6)
        .opacity(isEarned ? 1.0 : 0.7)
    }
}

struct CircularProgressView: View {
    let progress: Double
    let color: Color
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.2), lineWidth: 8)
                .frame(width: 50, height: 50)
            
            Circle()
                .trim(from: 0, to: min(progress, 1.0))
                .stroke(color, lineWidth: 8)
                .frame(width: 50, height: 50)
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 1), value: progress)
            
            Text("\(Int(min(progress, 1.0) * 100))%")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(color)
        }
    }
}

struct MonthlyStatView: View {
    let title: String
    let value: String
    let change: StatChange
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(color)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            
            HStack(spacing: 4) {
                Image(systemName: change.isPositive ? "arrow.up" : "arrow.down")
                    .font(.caption2)
                    .foregroundColor(change.isPositive ? .green : .red)
                
                Text("\(abs(change.value))")
                    .font(.caption2)
                    .foregroundColor(change.isPositive ? .green : .red)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - All Achievements View

struct AllAchievementsView: View {
    @Environment(\.colorScheme) private var colorScheme
    let achievements: [Achievement]

    private var earnedAchievements: [Achievement] {
        achievements.filter { $0.isEarned }
    }

    private var inProgressAchievements: [Achievement] {
        achievements.filter { !$0.isEarned && $0.progress > 0 }
    }

    private var lockedAchievements: [Achievement] {
        achievements.filter { !$0.isEarned && $0.progress == 0 }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header Stats
                headerStats
                
                // Earned Achievements
                if !earnedAchievements.isEmpty {
                    achievementSection(
                        title: "Unlocked",
                        subtitle: "\(earnedAchievements.count) achievements earned",
                        achievements: earnedAchievements,
                        headerColor: .green
                    )
                }
                
                // In Progress Achievements
                if !inProgressAchievements.isEmpty {
                    achievementSection(
                        title: "In Progress",
                        subtitle: "\(inProgressAchievements.count) achievements close to unlocking",
                        achievements: inProgressAchievements,
                        headerColor: .orange
                    )
                }
                
                // Locked Achievements
                if !lockedAchievements.isEmpty {
                    achievementSection(
                        title: "Locked",
                        subtitle: "\(lockedAchievements.count) achievements to discover",
                        achievements: lockedAchievements,
                        headerColor: .gray
                    )
                }
            }
            .padding()
        }
        .navigationTitle("Achievements")
        .navigationBarTitleDisplayMode(.large)
        .background(
            LinearGradient(
                gradient: Gradient(colors: [Color(.systemBackground), Color.blue.opacity(0.02)]),
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
    
    private var headerStats: some View {
        VStack(spacing: 16) {
            // Main achievement count
            VStack(spacing: 8) {
                Text("\(earnedAchievements.count)")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                
                Text("Achievements Unlocked")
                    .font(.headline)
                    .foregroundColor(.secondary)
            }
            
            // Progress overview
            HStack(spacing: 24) {
                StatPill(
                    value: "\(earnedAchievements.count)",
                    label: "Earned",
                    color: .green
                )
                
                StatPill(
                    value: "\(inProgressAchievements.count)",
                    label: "In Progress",
                    color: .orange
                )
                
                StatPill(
                    value: "\(lockedAchievements.count)",
                    label: "Locked",
                    color: .gray
                )
            }
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 16)
        .background(
            ZStack {
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
            }
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.08), radius: 12, x: 0, y: 6)
    }
    
    private func achievementSection(title: String, subtitle: String, achievements: [Achievement], headerColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Section header
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: iconForSection(title))
                        .font(.title2)
                        .foregroundColor(headerColor)
                    
                    Text(title)
                        .font(.title2)
                        .fontWeight(.bold)
                }
                
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            // Achievement grid
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2), spacing: 12) {
                ForEach(achievements, id: \.id) { achievement in
                    EnhancedAchievementCard(achievement: achievement)
                }
            }
        }
    }
    
    private func iconForSection(_ title: String) -> String {
        switch title {
        case "Unlocked": return "trophy.fill"
        case "In Progress": return "clock.fill"
        case "Locked": return "lock.fill"
        default: return "star.fill"
        }
    }
}

struct StatPill: View {
    let value: String
    let label: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(color)
            
            Text(label)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(color.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(color.opacity(0.3), lineWidth: 1)
                )
        )
    }
}

struct EnhancedAchievementCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let achievement: Achievement

    var body: some View {
        VStack(spacing: 12) {
            // Achievement icon
            ZStack {
                Circle()
                    .fill(achievement.color.opacity(0.1))
                    .frame(width: 60, height: 60)

                Image(systemName: achievement.icon)
                    .font(.title2)
                    .foregroundColor(achievement.isEarned ? achievement.color : .gray)
            }

            VStack(spacing: 6) {
                Text(achievement.title)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)

                Text(achievement.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }

            // Progress indicator
            if !achievement.isEarned && achievement.progress > 0 {
                VStack(spacing: 4) {
                    ProgressView(value: achievement.progress)
                        .progressViewStyle(LinearProgressViewStyle(tint: achievement.color))

                    Text("\(Int(achievement.progress * 100))% Complete")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(achievement.color)
                }
            } else if achievement.isEarned {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                    Text("Unlocked!")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.green)
                }
            }
            
            Spacer(minLength: 0)
        }
        .frame(height: 180)
        .padding(16)
        .background(
            ZStack {
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
            }
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.08), radius: 12, x: 0, y: 6)
        .opacity(achievement.isEarned ? 1.0 : 0.7)
        .scaleEffect(achievement.isEarned ? 1.0 : 0.95)
    }
}

// MARK: - Photorealistic Muscle Map View
struct MuscleMapView: View {
    let muscleData: [MuscleGroupData]
    @State private var selectedView: BodyView = .front
    @State private var selectedMuscle: String? = nil
    
    enum BodyView: String, CaseIterable {
        case front = "Front"
        case back = "Back"
    }
    
    var body: some View {
        VStack(spacing: 24) {
            // Professional header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Muscle Map")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    
                    Text("Targeted muscle groups")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Modern segmented picker
                Picker("Body View", selection: $selectedView) {
                    ForEach(BodyView.allCases, id: \.self) { view in
                        Text(view.rawValue)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .tag(view)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .frame(width: 140)
                .background(Color(.systemGray6))
                .cornerRadius(8)
            }
            .padding(.horizontal, 20)
            
            // Photorealistic body diagram
            GeometryReader { geometry in
                ZStack {
                    // Professional background with subtle gradient
                    RoundedRectangle(cornerRadius: 20)
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color(.systemBackground),
                                    Color(.systemGray6).opacity(0.3)
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
                    
                    // Anatomically accurate body outline
                    PhotorealisticBodyOutline(view: selectedView)
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color.brown.opacity(0.12),
                                    Color.orange.opacity(0.08),
                                    Color.pink.opacity(0.06)
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            PhotorealisticBodyOutline(view: selectedView)
                                .stroke(
                                    LinearGradient(
                                        gradient: Gradient(colors: [
                                            Color.brown.opacity(0.4),
                                            Color.orange.opacity(0.3)
                                        ]),
                                        startPoint: .top,
                                        endPoint: .bottom
                                    ),
                                    lineWidth: 1.5
                                )
                        )
                    
                    // Professional muscle overlays
                    ForEach(muscleData.filter { shouldShowMuscle($0.name, for: selectedView) && $0.intensity > 0.1 }, id: \.name) { muscle in
                        ForEach(Array(getAnatomicalMusclePositions(for: muscle.name, view: selectedView, width: geometry.size.width, height: geometry.size.height).enumerated()), id: \.offset) { index, position in
                            
                            ZStack {
                                // Main muscle highlight with anatomical shape
                                Ellipse()
                                    .fill(
                                        RadialGradient(
                                            gradient: Gradient(colors: [
                                                getMuscleColor(for: muscle.intensity).opacity(0.85),
                                                getMuscleColor(for: muscle.intensity).opacity(0.6),
                                                getMuscleColor(for: muscle.intensity).opacity(0.3),
                                                getMuscleColor(for: muscle.intensity).opacity(0.1)
                                            ]),
                                            center: .center,
                                            startRadius: 2,
                                            endRadius: position.size * 0.8
                                        )
                                    )
                                    .frame(width: position.size * 1.6, height: position.size * 1.4)
                                    .position(x: position.x, y: position.y)
                                    .scaleEffect(selectedMuscle == muscle.name ? 1.1 : 1.0)
                                    .shadow(color: getMuscleColor(for: muscle.intensity).opacity(0.4), radius: 6, x: 0, y: 3)
                                
                                // Professional muscle border
                                Ellipse()
                                    .stroke(
                                        LinearGradient(
                                            gradient: Gradient(colors: [
                                                getMuscleColor(for: muscle.intensity).opacity(0.9),
                                                getMuscleColor(for: muscle.intensity).opacity(0.5)
                                            ]),
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: selectedMuscle == muscle.name ? 2.5 : 1.5
                                    )
                                    .frame(width: position.size * 1.6, height: position.size * 1.4)
                                    .position(x: position.x, y: position.y)
                                
                                // High intensity indicator
                                if muscle.intensity > 0.7 {
                                    Circle()
                                        .fill(getMuscleColor(for: muscle.intensity))
                                        .frame(width: 6, height: 6)
                                        .position(x: position.x, y: position.y - position.size * 0.6)
                                        .shadow(color: .white.opacity(0.8), radius: 2, x: 0, y: 0)
                                }
                                
                                // Muscle name label for primary muscles
                                if muscle.intensity > 0.5 {
                                    Text(muscle.name)
                                        .font(.system(size: 10, weight: .bold, design: .rounded))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(
                                            Capsule()
                                                .fill(getMuscleColor(for: muscle.intensity).opacity(0.9))
                                                .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
                                        )
                                        .position(x: position.x, y: position.y + position.size * 0.8)
                                        .opacity(selectedMuscle == muscle.name ? 1.0 : 0.85)
                                }
                            }
                            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: selectedMuscle)
                            .onTapGesture {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    selectedMuscle = selectedMuscle == muscle.name ? nil : muscle.name
                                }
                            }
                        }
                    }
                }
            }
            .frame(height: 450)
            .padding(.horizontal, 20)
            
            // Professional legend and statistics
            if !muscleData.filter({ $0.intensity > 0.2 }).isEmpty {
                VStack(spacing: 16) {
                    // Primary muscles section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Primary Muscles")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                        
                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ], spacing: 12) {
                            ForEach(muscleData.filter { $0.intensity > 0.2 }.sorted { $0.intensity > $1.intensity }, id: \.name) { muscle in
                                HStack(spacing: 12) {
                                    // Color indicator
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(
                                            LinearGradient(
                                                gradient: Gradient(colors: [
                                                    getMuscleColor(for: muscle.intensity),
                                                    getMuscleColor(for: muscle.intensity).opacity(0.7)
                                                ]),
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .frame(width: 20, height: 20)
                                        .shadow(color: getMuscleColor(for: muscle.intensity).opacity(0.3), radius: 2, x: 0, y: 1)
                                    
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(muscle.name)
                                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                                            .foregroundColor(.primary)
                                        
                                        HStack(spacing: 8) {
                                            Text(getIntensityLabel(for: muscle.intensity))
                                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                                .foregroundColor(.secondary)
                                            
                                            Spacer()
                                            
                                            Text("\(muscle.count) sets")
                                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    
                                    Spacer()
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(Color(.systemGray6).opacity(0.6))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 14)
                                                .stroke(selectedMuscle == muscle.name ? getMuscleColor(for: muscle.intensity).opacity(0.6) : Color.clear, lineWidth: 2)
                                        )
                                        .shadow(color: .black.opacity(0.03), radius: 3, x: 0, y: 2)
                                )
                                .scaleEffect(selectedMuscle == muscle.name ? 1.02 : 1.0)
                                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: selectedMuscle)
                            }
                        }
                    }
                    
                    // Intensity legend
                    HStack(spacing: 20) {
                        ForEach([
                            ("Low", Color.blue, 0.3),
                            ("Moderate", Color.green, 0.5),
                            ("High", Color.orange, 0.7),
                            ("Very High", Color.red, 0.9)
                        ], id: \.0) { label, color, intensity in
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(color)
                                    .frame(width: 12, height: 12)
                                    .shadow(color: color.opacity(0.3), radius: 1, x: 0, y: 1)
                                
                                Text(label)
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.top, 8)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
        }
        .background(Color(.systemBackground))
        .cornerRadius(24)
        .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 6)
    }
    
    private func shouldShowMuscle(_ muscleName: String, for view: BodyView) -> Bool {
        let frontMuscles = ["Chest", "Biceps", "Abs", "Quadriceps", "Shoulders"]
        let backMuscles = ["Back", "Triceps", "Glutes", "Hamstrings", "Calves"]
        
        switch view {
        case .front:
            return frontMuscles.contains(muscleName)
        case .back:
            return backMuscles.contains(muscleName)
        }
    }
    
    private func getMuscleColor(for intensity: Double) -> Color {
        switch intensity {
        case 0.8...1.0:
            return Color.red
        case 0.6..<0.8:
            return Color.orange
        case 0.4..<0.6:
            return Color.yellow
        case 0.2..<0.4:
            return Color.green
        default:
            return Color.blue
        }
    }
    
    private func getIntensityLabel(for intensity: Double) -> String {
        switch intensity {
        case 0.8...1.0:
            return "Very High"
        case 0.6..<0.8:
            return "High"
        case 0.4..<0.6:
            return "Moderate"
        case 0.2..<0.4:
            return "Low"
        default:
            return "Minimal"
        }
    }
    
    // Anatomically accurate muscle positions
    private func getAnatomicalMusclePositions(for muscleName: String, view: BodyView, width: CGFloat, height: CGFloat) -> [(x: CGFloat, y: CGFloat, size: CGFloat)] {
        let centerX = width / 2
        
        switch (muscleName, view) {
        case ("Chest", .front):
            // Pectoralis major - anatomically correct chest position
            return [
                (x: centerX - width * 0.09, y: height * 0.30, size: width * 0.09),
                (x: centerX + width * 0.09, y: height * 0.30, size: width * 0.09)
            ]
        case ("Shoulders", .front):
            // Deltoid muscles - proper shoulder position
            return [
                (x: centerX - width * 0.20, y: height * 0.24, size: width * 0.07),
                (x: centerX + width * 0.20, y: height * 0.24, size: width * 0.07)
            ]
        case ("Biceps", .front):
            // Biceps brachii - upper arm front
            return [
                (x: centerX - width * 0.24, y: height * 0.34, size: width * 0.05),
                (x: centerX + width * 0.24, y: height * 0.34, size: width * 0.05)
            ]
        case ("Abs", .front):
            // Rectus abdominis - core muscles
            return [
                (x: centerX, y: height * 0.40, size: width * 0.10),
                (x: centerX, y: height * 0.48, size: width * 0.08)
            ]
        case ("Quadriceps", .front):
            // Quadriceps femoris - front thigh
            return [
                (x: centerX - width * 0.07, y: height * 0.62, size: width * 0.08),
                (x: centerX + width * 0.07, y: height * 0.62, size: width * 0.08)
            ]
        case ("Back", .back):
            // Latissimus dorsi and trapezius
            return [
                (x: centerX, y: height * 0.32, size: width * 0.16),
                (x: centerX, y: height * 0.42, size: width * 0.14)
            ]
        case ("Triceps", .back):
            // Triceps brachii - back of upper arm
            return [
                (x: centerX - width * 0.24, y: height * 0.34, size: width * 0.05),
                (x: centerX + width * 0.24, y: height * 0.34, size: width * 0.05)
            ]
        case ("Glutes", .back):
            // Gluteus maximus
            return [
                (x: centerX, y: height * 0.50, size: width * 0.13)
            ]
        case ("Hamstrings", .back):
            // Biceps femoris - back of thigh
            return [
                (x: centerX - width * 0.07, y: height * 0.64, size: width * 0.08),
                (x: centerX + width * 0.07, y: height * 0.64, size: width * 0.08)
            ]
        case ("Calves", .back):
            // Gastrocnemius - calf muscles
            return [
                (x: centerX - width * 0.06, y: height * 0.80, size: width * 0.05),
                (x: centerX + width * 0.06, y: height * 0.80, size: width * 0.05)
            ]
        default:
            return []
        }
    }
    
    private var bodyOutline: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            
            if selectedView == .front {
                frontBodyOutline(width: width, height: height)
            } else {
                backBodyOutline(width: width, height: height)
            }
        }
    }
    
    private func frontBodyOutline(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            // Main body silhouette with gradient
            Path { path in
                let centerX = width / 2
                let headRadius = width * 0.08
                let shoulderWidth = width * 0.35
                let waistWidth = width * 0.25
                let hipWidth = width * 0.28
                
                // Head
                path.addEllipse(in: CGRect(
                    x: centerX - headRadius,
                    y: height * 0.02,
                    width: headRadius * 2,
                    height: headRadius * 1.3
                ))
                
                // Neck
                path.move(to: CGPoint(x: centerX - headRadius * 0.3, y: height * 0.15))
                path.addLine(to: CGPoint(x: centerX - shoulderWidth * 0.15, y: height * 0.18))
                path.move(to: CGPoint(x: centerX + headRadius * 0.3, y: height * 0.15))
                path.addLine(to: CGPoint(x: centerX + shoulderWidth * 0.15, y: height * 0.18))
                
                // Torso outline - Left side
                path.move(to: CGPoint(x: centerX - shoulderWidth, y: height * 0.18))
                path.addCurve(
                    to: CGPoint(x: centerX - waistWidth, y: height * 0.45),
                    control1: CGPoint(x: centerX - shoulderWidth * 0.8, y: height * 0.25),
                    control2: CGPoint(x: centerX - waistWidth * 1.2, y: height * 0.35)
                )
                path.addCurve(
                    to: CGPoint(x: centerX - hipWidth, y: height * 0.55),
                    control1: CGPoint(x: centerX - waistWidth * 1.1, y: height * 0.5),
                    control2: CGPoint(x: centerX - hipWidth * 1.05, y: height * 0.52)
                )
                
                // Torso outline - Right side
                path.move(to: CGPoint(x: centerX + shoulderWidth, y: height * 0.18))
                path.addCurve(
                    to: CGPoint(x: centerX + waistWidth, y: height * 0.45),
                    control1: CGPoint(x: centerX + shoulderWidth * 0.8, y: height * 0.25),
                    control2: CGPoint(x: centerX + waistWidth * 1.2, y: height * 0.35)
                )
                path.addCurve(
                    to: CGPoint(x: centerX + hipWidth, y: height * 0.55),
                    control1: CGPoint(x: centerX + waistWidth * 1.1, y: height * 0.5),
                    control2: CGPoint(x: centerX + hipWidth * 1.05, y: height * 0.52)
                )
                
                // Arms
                addArms(to: &path, centerX: centerX, width: width, height: height, shoulderWidth: shoulderWidth)
                
                // Legs
                addLegs(to: &path, centerX: centerX, width: width, height: height, hipWidth: hipWidth)
            }
            .fill(
                LinearGradient(
                    colors: [Color.gray.opacity(0.1), Color.gray.opacity(0.05)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            
            // Outline stroke
            Path { path in
                let centerX = width / 2
                let headRadius = width * 0.08
                let shoulderWidth = width * 0.35
                let waistWidth = width * 0.25
                let hipWidth = width * 0.28
                
                // Head outline
                path.addEllipse(in: CGRect(
                    x: centerX - headRadius,
                    y: height * 0.02,
                    width: headRadius * 2,
                    height: headRadius * 1.3
                ))
                
                // Body outline
                addBodyOutlinePath(to: &path, centerX: centerX, width: width, height: height, shoulderWidth: shoulderWidth, waistWidth: waistWidth, hipWidth: hipWidth)
            }
            .stroke(
                LinearGradient(
                    colors: [Color.gray.opacity(0.4), Color.gray.opacity(0.2)],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: 1.5
            )
        }
    }
    
    private func backBodyOutline(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            // Main body silhouette
            Path { path in
                let centerX = width / 2
                let headRadius = width * 0.08
                let shoulderWidth = width * 0.35
                let waistWidth = width * 0.25
                let hipWidth = width * 0.28
                
                // Head (back view)
                path.addEllipse(in: CGRect(
                    x: centerX - headRadius,
                    y: height * 0.02,
                    width: headRadius * 2,
                    height: headRadius * 1.3
                ))
                
                // Torso (back view)
                path.move(to: CGPoint(x: centerX - shoulderWidth, y: height * 0.18))
                path.addCurve(
                    to: CGPoint(x: centerX - waistWidth, y: height * 0.45),
                    control1: CGPoint(x: centerX - shoulderWidth * 0.9, y: height * 0.25),
                    control2: CGPoint(x: centerX - waistWidth * 1.1, y: height * 0.35)
                )
                path.addCurve(
                    to: CGPoint(x: centerX - hipWidth, y: height * 0.55),
                    control1: CGPoint(x: centerX - waistWidth * 1.05, y: height * 0.5),
                    control2: CGPoint(x: centerX - hipWidth * 1.02, y: height * 0.52)
                )
                
                // Right side
                path.move(to: CGPoint(x: centerX + shoulderWidth, y: height * 0.18))
                path.addCurve(
                    to: CGPoint(x: centerX + waistWidth, y: height * 0.45),
                    control1: CGPoint(x: centerX + shoulderWidth * 0.9, y: height * 0.25),
                    control2: CGPoint(x: centerX + waistWidth * 1.1, y: height * 0.35)
                )
                path.addCurve(
                    to: CGPoint(x: centerX + hipWidth, y: height * 0.55),
                    control1: CGPoint(x: centerX + waistWidth * 1.05, y: height * 0.5),
                    control2: CGPoint(x: centerX + hipWidth * 1.02, y: height * 0.52)
                )
                
                // Arms and legs
                addArms(to: &path, centerX: centerX, width: width, height: height, shoulderWidth: shoulderWidth)
                addLegs(to: &path, centerX: centerX, width: width, height: height, hipWidth: hipWidth)
            }
            .fill(
                LinearGradient(
                    colors: [Color.gray.opacity(0.1), Color.gray.opacity(0.05)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .stroke(Color.gray.opacity(0.3), lineWidth: 1.5)
        }
    }
    
    private func addArms(to path: inout Path, centerX: CGFloat, width: CGFloat, height: CGFloat, shoulderWidth: CGFloat) {
        let armWidth = width * 0.08
        
        // Left arm
        path.move(to: CGPoint(x: centerX - shoulderWidth, y: height * 0.18))
        path.addLine(to: CGPoint(x: centerX - shoulderWidth - armWidth, y: height * 0.35))
        path.addLine(to: CGPoint(x: centerX - shoulderWidth - armWidth * 0.8, y: height * 0.52))
        
        // Right arm
        path.move(to: CGPoint(x: centerX + shoulderWidth, y: height * 0.18))
        path.addLine(to: CGPoint(x: centerX + shoulderWidth + armWidth, y: height * 0.35))
        path.addLine(to: CGPoint(x: centerX + shoulderWidth + armWidth * 0.8, y: height * 0.52))
    }
    
    private func addLegs(to path: inout Path, centerX: CGFloat, width: CGFloat, height: CGFloat, hipWidth: CGFloat) {
        let legWidth = width * 0.12
        
        // Left leg
        path.move(to: CGPoint(x: centerX - hipWidth * 0.7, y: height * 0.55))
        path.addLine(to: CGPoint(x: centerX - legWidth, y: height * 0.75))
        path.addLine(to: CGPoint(x: centerX - legWidth * 0.9, y: height * 0.95))
        
        // Right leg
        path.move(to: CGPoint(x: centerX + hipWidth * 0.7, y: height * 0.55))
        path.addLine(to: CGPoint(x: centerX + legWidth, y: height * 0.75))
        path.addLine(to: CGPoint(x: centerX + legWidth * 0.9, y: height * 0.95))
    }
    
    private func addBodyOutlinePath(to path: inout Path, centerX: CGFloat, width: CGFloat, height: CGFloat, shoulderWidth: CGFloat, waistWidth: CGFloat, hipWidth: CGFloat) {
        // Neck
        path.move(to: CGPoint(x: centerX - width * 0.025, y: height * 0.15))
        path.addLine(to: CGPoint(x: centerX - shoulderWidth * 0.15, y: height * 0.18))
        path.move(to: CGPoint(x: centerX + width * 0.025, y: height * 0.15))
        path.addLine(to: CGPoint(x: centerX + shoulderWidth * 0.15, y: height * 0.18))
        
        // Torso outline
        path.move(to: CGPoint(x: centerX - shoulderWidth, y: height * 0.18))
        path.addCurve(
            to: CGPoint(x: centerX - waistWidth, y: height * 0.45),
            control1: CGPoint(x: centerX - shoulderWidth * 0.8, y: height * 0.25),
            control2: CGPoint(x: centerX - waistWidth * 1.2, y: height * 0.35)
        )
        path.addCurve(
            to: CGPoint(x: centerX - hipWidth, y: height * 0.55),
            control1: CGPoint(x: centerX - waistWidth * 1.1, y: height * 0.5),
            control2: CGPoint(x: centerX - hipWidth * 1.05, y: height * 0.52)
        )
        
        // Right side
        path.move(to: CGPoint(x: centerX + shoulderWidth, y: height * 0.18))
        path.addCurve(
            to: CGPoint(x: centerX + waistWidth, y: height * 0.45),
            control1: CGPoint(x: centerX + shoulderWidth * 0.8, y: height * 0.25),
            control2: CGPoint(x: centerX + waistWidth * 1.2, y: height * 0.35)
        )
        path.addCurve(
            to: CGPoint(x: centerX + hipWidth, y: height * 0.55),
            control1: CGPoint(x: centerX + waistWidth * 1.1, y: height * 0.5),
            control2: CGPoint(x: centerX + hipWidth * 1.05, y: height * 0.52)
        )
        
        // Arms and legs
        addArms(to: &path, centerX: centerX, width: width, height: height, shoulderWidth: shoulderWidth)
        addLegs(to: &path, centerX: centerX, width: width, height: height, hipWidth: hipWidth)
    }
    
    private var muscleOverlays: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            
            ForEach(muscleData, id: \.name) { muscle in
                if shouldShowMuscle(muscle.name, for: selectedView) {
                    muscleOverlay(for: muscle, width: width, height: height)
                }
            }
        }
    }
    
    private func muscleOverlay(for muscle: MuscleGroupData, width: CGFloat, height: CGFloat) -> some View {
        let positions = getAnatomicalMusclePositions(for: muscle.name, view: selectedView, width: width, height: height)
        
        return ForEach(Array(positions.enumerated()), id: \.offset) { index, position in
            ZStack {
                // Main muscle area with radial gradient
                Ellipse()
                    .fill(
                        RadialGradient(
                            colors: [
                                muscle.color.opacity(0.6 + muscle.intensity * 0.3),
                                muscle.color.opacity(0.2 + muscle.intensity * 0.4),
                                muscle.color.opacity(0.1 + muscle.intensity * 0.2)
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: position.size / 2
                        )
                    )
                    .frame(width: position.size, height: position.size * 0.8)
                    .position(x: position.x, y: position.y)
                
                // Highlight border
                Ellipse()
                    .stroke(
                        LinearGradient(
                            colors: [
                                muscle.color.opacity(0.8),
                                muscle.color.opacity(0.4)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: selectedMuscle == muscle.name ? 3 : 1.5
                    )
                    .frame(width: position.size, height: position.size * 0.8)
                    .position(x: position.x, y: position.y)
                
                // Intensity indicator dot
                if muscle.intensity > 0.7 {
                    Circle()
                        .fill(muscle.color)
                        .frame(width: 4, height: 4)
                        .position(x: position.x, y: position.y - position.size * 0.2)
                }
                
                // Selection pulse effect
                if selectedMuscle == muscle.name {
                    Ellipse()
                        .stroke(muscle.color.opacity(0.6), lineWidth: 2)
                        .frame(width: position.size * 1.3, height: position.size)
                        .position(x: position.x, y: position.y)
                        .scaleEffect(1.1)
                        .opacity(0.7)
                }
            }
            .scaleEffect(selectedMuscle == muscle.name ? 1.15 : 1.0)
            .animation(.easeInOut(duration: 0.3), value: selectedMuscle)
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    selectedMuscle = selectedMuscle == muscle.name ? nil : muscle.name
                }
            }
        }
    }
    
    private var muscleIntensityLegend: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Training Intensity")
                .font(.subheadline)
                .fontWeight(.semibold)
            
            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.blue.opacity(0.3))
                        .frame(width: 12, height: 12)
                    Text("Low")
                        .font(.caption)
                }
                
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.blue.opacity(0.6))
                        .frame(width: 12, height: 12)
                    Text("Medium")
                        .font(.caption)
                }
                
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.blue.opacity(0.9))
                        .frame(width: 12, height: 12)
                    Text("High")
                        .font(.caption)
                }
            }
            
            if let selectedMuscle = selectedMuscle,
               let muscle = muscleData.first(where: { $0.name == selectedMuscle }) {
                Divider()
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(selectedMuscle)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(muscle.color)
                    
                    Text("\(muscle.count) sets • \(Int(muscle.intensity * 100))% intensity")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

// MARK: - Photorealistic Body Outline Shape
struct PhotorealisticBodyOutline: Shape {
    let view: MuscleMapView.BodyView
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.width
        let height = rect.height
        let centerX = width / 2
        
        switch view {
        case .front:
            // Head - proportional and realistic
            path.addEllipse(in: CGRect(x: centerX - width * 0.06, y: height * 0.04, width: width * 0.12, height: height * 0.09))
            
            // Neck
            let neckRect = CGRect(x: centerX - width * 0.02, y: height * 0.13, width: width * 0.04, height: height * 0.05)
            path.addRoundedRect(in: neckRect, cornerSize: CGSize(width: 2, height: 2))
            
            // Anatomically accurate torso
            path.move(to: CGPoint(x: centerX - width * 0.10, y: height * 0.18))
            // Left shoulder
            path.addQuadCurve(to: CGPoint(x: centerX - width * 0.16, y: height * 0.25), control: CGPoint(x: centerX - width * 0.14, y: height * 0.20))
            // Left side of torso
            path.addQuadCurve(to: CGPoint(x: centerX - width * 0.13, y: height * 0.38), control: CGPoint(x: centerX - width * 0.17, y: height * 0.30))
            // Waist
            path.addQuadCurve(to: CGPoint(x: centerX - width * 0.09, y: height * 0.52), control: CGPoint(x: centerX - width * 0.11, y: height * 0.45))
            // Hip connection to legs
            path.addLine(to: CGPoint(x: centerX - width * 0.01, y: height * 0.58))
            path.addLine(to: CGPoint(x: centerX + width * 0.01, y: height * 0.58))
            // Right side mirror
            path.addLine(to: CGPoint(x: centerX + width * 0.09, y: height * 0.52))
            path.addQuadCurve(to: CGPoint(x: centerX + width * 0.13, y: height * 0.38), control: CGPoint(x: centerX + width * 0.11, y: height * 0.45))
            path.addQuadCurve(to: CGPoint(x: centerX + width * 0.16, y: height * 0.25), control: CGPoint(x: centerX + width * 0.17, y: height * 0.30))
            path.addQuadCurve(to: CGPoint(x: centerX + width * 0.10, y: height * 0.18), control: CGPoint(x: centerX + width * 0.14, y: height * 0.20))
            path.closeSubpath()
            
            // Realistic arms
            // Left arm
            path.move(to: CGPoint(x: centerX - width * 0.16, y: height * 0.25))
            path.addQuadCurve(to: CGPoint(x: centerX - width * 0.26, y: height * 0.30), control: CGPoint(x: centerX - width * 0.22, y: height * 0.26))
            path.addQuadCurve(to: CGPoint(x: centerX - width * 0.28, y: height * 0.48), control: CGPoint(x: centerX - width * 0.29, y: height * 0.38))
            path.addQuadCurve(to: CGPoint(x: centerX - width * 0.23, y: height * 0.52), control: CGPoint(x: centerX - width * 0.26, y: height * 0.50))
            path.addQuadCurve(to: CGPoint(x: centerX - width * 0.20, y: height * 0.38), control: CGPoint(x: centerX - width * 0.21, y: height * 0.45))
            path.addQuadCurve(to: CGPoint(x: centerX - width * 0.16, y: height * 0.25), control: CGPoint(x: centerX - width * 0.18, y: height * 0.30))
            
            // Right arm
            path.move(to: CGPoint(x: centerX + width * 0.16, y: height * 0.25))
            path.addQuadCurve(to: CGPoint(x: centerX + width * 0.26, y: height * 0.30), control: CGPoint(x: centerX + width * 0.22, y: height * 0.26))
            path.addQuadCurve(to: CGPoint(x: centerX + width * 0.28, y: height * 0.48), control: CGPoint(x: centerX + width * 0.29, y: height * 0.38))
            path.addQuadCurve(to: CGPoint(x: centerX + width * 0.23, y: height * 0.52), control: CGPoint(x: centerX + width * 0.26, y: height * 0.50))
            path.addQuadCurve(to: CGPoint(x: centerX + width * 0.20, y: height * 0.38), control: CGPoint(x: centerX + width * 0.21, y: height * 0.45))
            path.addQuadCurve(to: CGPoint(x: centerX + width * 0.16, y: height * 0.25), control: CGPoint(x: centerX + width * 0.18, y: height * 0.30))
            
            // Anatomically correct legs
            // Left leg
            path.move(to: CGPoint(x: centerX - width * 0.09, y: height * 0.58))
            path.addQuadCurve(to: CGPoint(x: centerX - width * 0.11, y: height * 0.78), control: CGPoint(x: centerX - width * 0.12, y: height * 0.68))
            path.addQuadCurve(to: CGPoint(x: centerX - width * 0.08, y: height * 0.92), control: CGPoint(x: centerX - width * 0.10, y: height * 0.85))
            path.addLine(to: CGPoint(x: centerX - width * 0.03, y: height * 0.92))
            path.addQuadCurve(to: CGPoint(x: centerX - width * 0.01, y: height * 0.78), control: CGPoint(x: centerX - width * 0.02, y: height * 0.85))
            path.addLine(to: CGPoint(x: centerX - width * 0.01, y: height * 0.58))
            path.closeSubpath()
            
            // Right leg
            path.move(to: CGPoint(x: centerX + width * 0.09, y: height * 0.58))
            path.addQuadCurve(to: CGPoint(x: centerX + width * 0.11, y: height * 0.78), control: CGPoint(x: centerX + width * 0.12, y: height * 0.68))
            path.addQuadCurve(to: CGPoint(x: centerX + width * 0.08, y: height * 0.92), control: CGPoint(x: centerX + width * 0.10, y: height * 0.85))
            path.addLine(to: CGPoint(x: centerX + width * 0.03, y: height * 0.92))
            path.addQuadCurve(to: CGPoint(x: centerX + width * 0.01, y: height * 0.78), control: CGPoint(x: centerX + width * 0.02, y: height * 0.85))
            path.addLine(to: CGPoint(x: centerX + width * 0.01, y: height * 0.58))
            path.closeSubpath()
            
        case .back:
            // Similar structure but optimized for back view
            // Head
            path.addEllipse(in: CGRect(x: centerX - width * 0.06, y: height * 0.04, width: width * 0.12, height: height * 0.09))
            
            // Back torso with muscle definition considerations
            path.move(to: CGPoint(x: centerX - width * 0.10, y: height * 0.18))
            path.addQuadCurve(to: CGPoint(x: centerX - width * 0.16, y: height * 0.25), control: CGPoint(x: centerX - width * 0.14, y: height * 0.20))
            path.addQuadCurve(to: CGPoint(x: centerX - width * 0.13, y: height * 0.48), control: CGPoint(x: centerX - width * 0.17, y: height * 0.35))
            path.addQuadCurve(to: CGPoint(x: centerX - width * 0.09, y: height * 0.58), control: CGPoint(x: centerX - width * 0.11, y: height * 0.53))
            path.addLine(to: CGPoint(x: centerX + width * 0.09, y: height * 0.58))
            path.addQuadCurve(to: CGPoint(x: centerX + width * 0.13, y: height * 0.48), control: CGPoint(x: centerX + width * 0.11, y: height * 0.53))
            path.addQuadCurve(to: CGPoint(x: centerX + width * 0.16, y: height * 0.25), control: CGPoint(x: centerX + width * 0.17, y: height * 0.35))
            path.addQuadCurve(to: CGPoint(x: centerX + width * 0.10, y: height * 0.18), control: CGPoint(x: centerX + width * 0.14, y: height * 0.20))
            path.closeSubpath()
            
            // Arms (back view)
            path.addEllipse(in: CGRect(x: centerX - width * 0.28, y: height * 0.25, width: width * 0.06, height: height * 0.27))
            path.addEllipse(in: CGRect(x: centerX + width * 0.22, y: height * 0.25, width: width * 0.06, height: height * 0.27))
            
            // Legs (back view)
            path.addEllipse(in: CGRect(x: centerX - width * 0.11, y: height * 0.58, width: width * 0.08, height: height * 0.34))
            path.addEllipse(in: CGRect(x: centerX + width * 0.03, y: height * 0.58, width: width * 0.08, height: height * 0.34))
        }
        
        return path
    }
}

// MARK: - Fitness Ring Component
struct FitnessRing: View {
    let progress: Double
    let color: Color
    let lineWidth: CGFloat
    let size: CGFloat
    
    @State private var animatedProgress: Double = 0
    
    var body: some View {
        ZStack {
            // Background ring
            Circle()
                .stroke(
                    color.opacity(0.2),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .frame(width: size, height: size)
            
            // Progress ring
            Circle()
                .trim(from: 0, to: animatedProgress)
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [
                            color,
                            color.opacity(0.8),
                            color
                        ]),
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(360)
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .frame(width: size, height: size)
                .rotationEffect(.degrees(-90))
            
            // Glow effect when complete
            if animatedProgress >= 1.0 {
                Circle()
                    .trim(from: 0, to: 1)
                    .stroke(
                        color,
                        style: StrokeStyle(lineWidth: lineWidth * 0.5, lineCap: .round)
                    )
                    .frame(width: size, height: size)
                    .blur(radius: 8)
                    .opacity(0.5)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 1.0, dampingFraction: 0.8)) {
                animatedProgress = progress
            }
        }
        .onChange(of: progress) { _, newValue in
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                animatedProgress = newValue
            }
        }
    }
}

// MARK: - Ring Legend Row
struct RingLegendRow: View {
    let title: String
    let subtitle: String
    let progress: Double
    let color: Color
    let icon: String
    
    var body: some View {
        HStack(spacing: 10) {
            // Mini ring indicator
            ZStack {
                Circle()
                    .stroke(color.opacity(0.3), lineWidth: 3)
                    .frame(width: 28, height: 28)
                
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: 28, height: 28)
                    .rotationEffect(.degrees(-90))
                
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(color)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    if progress >= 1.0 {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.green)
                    }
                }
                
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

// MARK: - Compact Ring Legend (for 6-ring display)
struct CompactRingLegend: View {
    let title: String
    let value: String
    let goal: String
    let color: Color
    let icon: String
    
    var body: some View {
        HStack(spacing: 8) {
            // Color dot with icon
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [color, color.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 24, height: 24)
                    .shadow(color: color.opacity(0.4), radius: 3, x: 0, y: 1)
                
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primary)
                
                HStack(spacing: 2) {
                    Text(value)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(color)
                    Text("/")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Text(goal)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

// MARK: - Activity Legend Row (matches Meals tab MacroLegendRow style)
struct ActivityLegendRow: View {
    let name: String
    let current: Int
    let goal: Int
    let color: Color
    
    private var progress: Double {
        guard goal > 0 else { return 0 }
        return min(1.0, Double(current) / Double(goal))
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                Text(name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Text("\(current)/\(goal)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray5))
                        .frame(height: 6)
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: [color, color.opacity(0.7)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geometry.size.width * progress, height: 6)
                }
            }
            .frame(height: 6)
        }
    }
}

// MARK: - Weekly Activity Progress Row
struct WeeklyActivityProgressRow: View {
    let title: String
    let daysCompleted: Int
    let totalDays: Int
    let color: Color
    
    private var progress: Double {
        guard totalDays > 0 else { return 0 }
        return Double(daysCompleted) / Double(totalDays)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Text("\(daysCompleted)/\(totalDays) days")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray5))
                        .frame(height: 8)
                    
                    // Progress
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: [color, color.opacity(0.7)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geometry.size.width * progress, height: 8)
                        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: progress)
                }
            }
            .frame(height: 8)
        }
    }
}

// MARK: - Mini Day Ring (for Ring Stamp Calendar)
struct MiniDayRing: View {
    let stepsProgress: Double
    let workoutProgress: Double
    let macrosProgress: Double
    var isToday: Bool = false
    var isFuture: Bool = false
    
    private let ringWidth: CGFloat = 2.0
    private let ringSpacing: CGFloat = 2.5 // Increased for visible gap between rings
    
    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            
            ZStack {
                // Today highlight
                if isToday {
                    Circle()
                        .fill(Color.purple.opacity(0.1))
                        .frame(width: size, height: size)
                }
                
                // Background rings (dimmed for future dates)
                let bgOpacity = isFuture ? 0.05 : 0.15
                
                // Outer ring - Steps (Red)
                Circle()
                    .stroke(Color.red.opacity(bgOpacity), lineWidth: ringWidth)
                    .frame(width: size - ringWidth, height: size - ringWidth)
                
                // Middle ring - Workout (Orange)
                Circle()
                    .stroke(Color.orange.opacity(bgOpacity), lineWidth: ringWidth)
                    .frame(width: size - ringWidth * 2 - ringSpacing * 2, height: size - ringWidth * 2 - ringSpacing * 2)
                
                // Inner ring - Macros (Yellow)
                Circle()
                    .stroke(Color.yellow.opacity(bgOpacity), lineWidth: ringWidth)
                    .frame(width: size - ringWidth * 4 - ringSpacing * 4, height: size - ringWidth * 4 - ringSpacing * 4)
                
                // Progress rings (only show if not future)
                if !isFuture {
                    // Very subtle glow layers (reduced opacity and blur)
                    if stepsProgress > 0 {
                        Circle()
                            .trim(from: 0, to: min(stepsProgress, 1.0))
                            .stroke(Color.red.opacity(0.12), style: StrokeStyle(lineWidth: ringWidth + 0.5, lineCap: .round))
                            .frame(width: size - ringWidth, height: size - ringWidth)
                            .rotationEffect(.degrees(-90))
                            .blur(radius: 1)
                    }
                    if workoutProgress > 0 {
                        Circle()
                            .trim(from: 0, to: min(workoutProgress, 1.0))
                            .stroke(Color.orange.opacity(0.12), style: StrokeStyle(lineWidth: ringWidth + 0.5, lineCap: .round))
                            .frame(width: size - ringWidth * 2 - ringSpacing * 2, height: size - ringWidth * 2 - ringSpacing * 2)
                            .rotationEffect(.degrees(-90))
                            .blur(radius: 1)
                    }
                    if macrosProgress > 0 {
                        Circle()
                            .trim(from: 0, to: min(macrosProgress, 1.0))
                            .stroke(Color.yellow.opacity(0.12), style: StrokeStyle(lineWidth: ringWidth + 0.5, lineCap: .round))
                            .frame(width: size - ringWidth * 4 - ringSpacing * 4, height: size - ringWidth * 4 - ringSpacing * 4)
                            .rotationEffect(.degrees(-90))
                            .blur(radius: 1)
                    }
                    
                    // Outer ring progress - Steps
                    Circle()
                        .trim(from: 0, to: min(stepsProgress, 1.0))
                        .stroke(
                            LinearGradient(colors: [.red, .red.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing),
                            style: StrokeStyle(lineWidth: ringWidth, lineCap: .round)
                        )
                        .frame(width: size - ringWidth, height: size - ringWidth)
                        .rotationEffect(.degrees(-90))
                    
                    // Middle ring progress - Workout
                    Circle()
                        .trim(from: 0, to: min(workoutProgress, 1.0))
                        .stroke(
                            LinearGradient(colors: [.orange, .orange.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing),
                            style: StrokeStyle(lineWidth: ringWidth, lineCap: .round)
                        )
                        .frame(width: size - ringWidth * 2 - ringSpacing * 2, height: size - ringWidth * 2 - ringSpacing * 2)
                        .rotationEffect(.degrees(-90))
                    
                    // Inner ring progress - Macros
                    Circle()
                        .trim(from: 0, to: min(macrosProgress, 1.0))
                        .stroke(
                            LinearGradient(colors: [.yellow, .yellow.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing),
                            style: StrokeStyle(lineWidth: ringWidth, lineCap: .round)
                        )
                        .frame(width: size - ringWidth * 4 - ringSpacing * 4, height: size - ringWidth * 4 - ringSpacing * 4)
                        .rotationEffect(.degrees(-90))
                }
                
                // Checkmark for perfect days (all 3 complete)
                if stepsProgress >= 1.0 && workoutProgress >= 1.0 && macrosProgress >= 1.0 && !isFuture {
                    Image(systemName: "checkmark")
                        .font(.system(size: size * 0.25, weight: .bold))
                        .foregroundColor(.green)
                }
            }
            .frame(width: size, height: size)
        }
    }
}

// MARK: - Embedded Stats View (for Workout Tab)
/// Lightweight wrapper that renders WorkoutProgressView stats inline
struct WorkoutStatsEmbeddedView: View {
    var body: some View {
        WorkoutProgressView(isEmbedded: true)
    }
}

#Preview {
    WorkoutProgressView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
        .environmentObject(UserManager())
}
