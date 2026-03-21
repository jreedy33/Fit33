//
//  PersonalizedInsightsService.swift
//  Fit33
//
//  Advanced personalized insights engine that analyzes correlations across:
//  - Nutrition ↔ Performance (protein intake vs strength gains)
//  - Hydration ↔ Workout Quality
//  - Sleep ↔ Recovery & PRs
//  - Consistency ↔ Results (streaks vs goal progress)
//  - Social ↔ Engagement (challenges vs workout frequency)
//  - Time patterns (best workout times, nutrition timing)
//

import Foundation
import SwiftUI
import Combine
import CoreData

// MARK: - Insight Models

enum InsightType: String, Codable, CaseIterable {
    case achievement = "achievement"      // "You hit your protein goal 7 days!"
    case correlation = "correlation"      // "Your PRs increase 40% on high-protein days"
    case warning = "warning"              // "Protein intake dropped 30% this week"
    case tip = "tip"                      // "Try adding 20g protein for better recovery"
    case milestone = "milestone"          // "100 workouts completed!"
    case trend = "trend"                  // "Strength up 15% this month"
    case pattern = "pattern"              // "You perform best at 7am"
    case goalProgress = "goal_progress"   // "You're 60% to your weight goal"
}

enum InsightCategory: String, Codable, CaseIterable {
    case nutrition = "nutrition"
    case workout = "workout"
    case weight = "weight"
    case hydration = "hydration"
    case social = "social"
    case streak = "streak"
    case goal = "goal"
    case recovery = "recovery"
    case sleep = "sleep"
}

enum InsightPriority: Int, Comparable {
    case low = 1
    case medium = 5
    case high = 8
    case critical = 10
    
    static func < (lhs: InsightPriority, rhs: InsightPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct PersonalizedInsight: Identifiable, Codable {
    let id: UUID
    let userId: UUID
    let type: String
    let category: String
    let title: String
    let message: String
    let detailMessage: String?
    let dataPoints: [String: Double]?
    let relatedGoal: String?
    let timePeriod: String?
    let priority: Int
    let icon: String
    let accentColor: String
    let isRead: Bool
    let isDismissed: Bool
    let createdAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case type = "insight_type"
        case category = "insight_category"
        case title
        case message
        case detailMessage = "detail_message"
        case dataPoints = "data_points"
        case relatedGoal = "related_goal"
        case timePeriod = "time_period"
        case priority
        case icon
        case accentColor = "accent_color"
        case isRead = "is_read"
        case isDismissed = "is_dismissed"
        case createdAt = "created_at"
    }
    
    var insightType: InsightType {
        InsightType(rawValue: type) ?? .tip
    }
    
    var insightCategory: InsightCategory {
        InsightCategory(rawValue: category) ?? .workout
    }
    
    var color: Color {
        switch accentColor {
        case "orange": return .orange
        case "green": return .green
        case "blue": return .blue
        case "purple": return .purple
        case "red": return .red
        case "yellow": return .yellow
        case "cyan": return .cyan
        case "pink": return .pink
        default: return .blue
        }
    }
}

struct StreakData: Codable {
    let streakType: String
    let currentStreak: Int
    let longestStreak: Int
    let totalDaysAchieved: Int
    let lastAchievedDate: Date?
    
    enum CodingKeys: String, CodingKey {
        case streakType = "streak_type"
        case currentStreak = "current_streak"
        case longestStreak = "longest_streak"
        case totalDaysAchieved = "total_days_achieved"
        case lastAchievedDate = "last_achieved_date"
    }
    
    // BUG FIX: Server returns "2026-02-14" (yyyy-MM-dd) which isn't valid ISO8601.
    // Default Date decoding fails with "Invalid date format: 2026-02-14".
    // Custom init handles yyyy-MM-dd, ISO8601, and nil gracefully.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        streakType = try container.decode(String.self, forKey: .streakType)
        currentStreak = try container.decode(Int.self, forKey: .currentStreak)
        longestStreak = try container.decode(Int.self, forKey: .longestStreak)
        totalDaysAchieved = try container.decode(Int.self, forKey: .totalDaysAchieved)
        
        // Try decoding as string first, then parse flexibly
        if let dateString = try container.decodeIfPresent(String.self, forKey: .lastAchievedDate) {
            // Try yyyy-MM-dd first (what the server actually sends)
            let plainFormatter = DateFormatter()
            plainFormatter.dateFormat = "yyyy-MM-dd"
            plainFormatter.locale = Locale(identifier: "en_US_POSIX")
            
            if let date = plainFormatter.date(from: dateString) {
                lastAchievedDate = date
            } else {
                // Fallback: try ISO8601
                let isoFormatter = ISO8601DateFormatter()
                isoFormatter.formatOptions = [.withInternetDateTime]
                lastAchievedDate = isoFormatter.date(from: dateString)
            }
        } else {
            lastAchievedDate = nil
        }
    }
}

struct CorrelationResult {
    let metricA: String
    let metricB: String
    let coefficient: Double
    let sampleSize: Int
    let direction: String
    let strength: String
    let isActionable: Bool
    let recommendation: String?
}

struct GoalMetrics: Codable {
    let weekStart: Date
    let nutritionConsistencyScore: Double?
    let overallConsistencyScore: Double?
    let goalAlignmentScore: Double?
    let weightChangeLbs: Double?
    let personalRecordsCount: Int
    let predictedOutcome: String?
    
    enum CodingKeys: String, CodingKey {
        case weekStart = "week_start"
        case nutritionConsistencyScore = "nutrition_consistency_score"
        case overallConsistencyScore = "overall_consistency_score"
        case goalAlignmentScore = "goal_alignment_score"
        case weightChangeLbs = "weight_change_lbs"
        case personalRecordsCount = "personal_records_count"
        case predictedOutcome = "predicted_outcome"
    }
}

// MARK: - Personalized Insights Service

@MainActor
class PersonalizedInsightsService: ObservableObject {
    static let shared = PersonalizedInsightsService()
    
    // MARK: - Published Properties
    @Published var activeInsights: [PersonalizedInsight] = []
    @Published var streaks: [StreakData] = []
    @Published var isLoading = false
    @Published var lastAnalysisDate: Date?
    
    // MARK: - Private Properties
    private let supabase = SupabaseManager.shared
    private let viewContext = PersistenceController.shared.container.viewContext
    
    private let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
    
    @inline(__always) private func dateToISO(_ date: Date) -> String {
        iso8601.string(from: date)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
    
    private init() {
        AppLogger.debug("🧠 [INSIGHTS] Personalized Insights Service initialized", category: .general)
    }
    
    // MARK: - Public API
    
    /// Fetch all active insights for the current user
    func fetchActiveInsights() async {
        guard let userId = supabase.currentUser?.id else { return }
        
        isLoading = true
        defer { isLoading = false }
        
        struct FetchInsightsParams: Encodable {
            let p_user_id: String
            let p_limit: Int
        }
        
        do {
            let params = FetchInsightsParams(p_user_id: userId.uuidString, p_limit: 20)
            let insights: [PersonalizedInsight] = try await supabase.supabaseClient
                .rpc("get_active_insights", params: params)
                .execute()
                .value
            
            self.activeInsights = insights
            AppLogger.debug("🧠 [INSIGHTS] Fetched \(insights.count) active insights", category: .general)
        } catch {
            AppLogger.error("❌ [INSIGHTS] Failed to fetch insights: \(error)", category: .general)
        }
    }
    
    /// Fetch all streak data for the current user
    func fetchStreaks() async {
        guard let userId = supabase.currentUser?.id else { return }
        
        struct FetchStreaksParams: Encodable {
            let p_user_id: String
        }
        
        do {
            let params = FetchStreaksParams(p_user_id: userId.uuidString)
            let streakData: [StreakData] = try await supabase.supabaseClient
                .rpc("get_streak_summary", params: params)
                .execute()
                .value
            
            self.streaks = streakData
            AppLogger.debug("🧠 [INSIGHTS] Fetched \(streakData.count) streak types", category: .general)
        } catch {
            AppLogger.error("❌ [INSIGHTS] Failed to fetch streaks: \(error)", category: .general)
        }
    }
    
    /// Run comprehensive analysis and generate insights
    func runDailyAnalysis() async {
        guard let userId = supabase.currentUser?.id else { return }
        
        AppLogger.debug("🧠 [INSIGHTS] Running daily analysis...", category: .general)
        isLoading = true
        
        // 1. Update all streak tracking
        await updateAllStreaks(userId: userId)
        
        // 2. Analyze correlations
        await analyzeCorrelations(userId: userId)
        
        // 3. Generate goal-specific insights
        await generateGoalInsights(userId: userId)
        
        // 4. Detect behavior patterns
        await detectBehaviorPatterns(userId: userId)
        
        // 5. Calculate performance windows
        await updatePerformanceWindows(userId: userId)
        
        // 6. Cross-table correlation insights
        await generateCrossTableInsights(userId: userId)

        // 7. Generate weekly insights via RPC
        await generateWeeklyInsightsRPC(userId: userId)
        
        // 8. Fetch updated insights
        await fetchActiveInsights()
        await fetchStreaks()
        
        lastAnalysisDate = Date()
        isLoading = false
        
        AppLogger.debug("🧠 [INSIGHTS] Daily analysis complete", category: .general)
    }
    
    /// Mark an insight as read
    func markAsRead(_ insight: PersonalizedInsight) async {
        do {
            try await supabase.supabaseClient
                .from("user_personalized_insights")
                .update(["is_read": true])
                .eq("id", value: insight.id.uuidString)
                .execute()
            
            if let index = activeInsights.firstIndex(where: { $0.id == insight.id }) {
                activeInsights.remove(at: index)
            }
        } catch {
            AppLogger.error("❌ [INSIGHTS] Failed to mark as read: \(error)", category: .general)
        }
    }
    
    /// Dismiss an insight
    func dismissInsight(_ insight: PersonalizedInsight) async {
        do {
            try await supabase.supabaseClient
                .from("user_personalized_insights")
                .update(["is_dismissed": true])
                .eq("id", value: insight.id.uuidString)
                .execute()
            
            if let index = activeInsights.firstIndex(where: { $0.id == insight.id }) {
                activeInsights.remove(at: index)
            }
        } catch {
            AppLogger.error("❌ [INSIGHTS] Failed to dismiss: \(error)", category: .general)
        }
    }
    
    // MARK: - Streak Tracking
    
    private func updateAllStreaks(userId: UUID) async {
        AppLogger.debug("🔥 [INSIGHTS] Updating streak tracking...", category: .general)
        
        // Get recent daily summaries
        let recentData = await getRecentDailySummaries(userId: userId, days: 90)
        
        // Calculate protein goal streak
        await updateStreak(
            userId: userId,
            type: "protein_goal",
            achievedDates: recentData.compactMap { day in
                guard let protein = day.protein,
                      let proteinGoal = getUserProteinGoal(),
                      protein >= Int(proteinGoal * 0.9) else { return nil }
                return day.date
            }
        )
        
        // Calculate calorie goal streak
        await updateStreak(
            userId: userId,
            type: "calorie_goal",
            achievedDates: recentData.compactMap { day in
                guard let calories = day.calories,
                      let calorieGoal = getUserCalorieGoal() else { return nil }
                // Within 10% of goal
                let tolerance = Double(calorieGoal) * 0.1
                if Double(calories) >= Double(calorieGoal) - tolerance &&
                   Double(calories) <= Double(calorieGoal) + tolerance {
                    return day.date
                }
                return nil
            }
        )
        
        // Calculate hydration streak
        await updateStreak(
            userId: userId,
            type: "hydration",
            achievedDates: recentData.compactMap { day in
                guard day.hydrationGoalMet == true else { return nil }
                return day.date
            }
        )
        
        // Calculate weight logging streak
        await updateStreak(
            userId: userId,
            type: "weight_log",
            achievedDates: recentData.compactMap { day in
                guard day.weightLbs != nil else { return nil }
                return day.date
            }
        )
        
        // Calculate workout streak
        await updateStreak(
            userId: userId,
            type: "workout",
            achievedDates: recentData.compactMap { day in
                guard let workoutCount = day.workoutCount, workoutCount > 0 else { return nil }
                return day.date
            }
        )
        
        // Calculate logging streak (any activity)
        await updateStreak(
            userId: userId,
            type: "logging",
            achievedDates: recentData.compactMap { day in
                // Logged if they have any data
                if day.calories ?? 0 > 0 || day.hydration ?? 0 > 0 || day.workoutCount ?? 0 > 0 {
                    return day.date
                }
                return nil
            }
        )
    }
    
    private func updateStreak(userId: UUID, type: String, achievedDates: [Date]) async {
        guard !achievedDates.isEmpty else {
            // Update with zero streak
            await saveStreakData(userId: userId, type: type, current: 0, longest: 0, total: 0, lastDate: nil)
            return
        }
        
        let sortedDates = achievedDates.sorted(by: >)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        // Calculate current streak
        var currentStreak = 0
        var checkDate = today
        
        for date in sortedDates {
            let dayStart = calendar.startOfDay(for: date)
            if dayStart == checkDate {
                currentStreak += 1
                checkDate = calendar.date(byAdding: .day, value: -1, to: checkDate)!
            } else if dayStart < checkDate {
                // Allow one day gap for flexibility
                let daysBetween = calendar.dateComponents([.day], from: dayStart, to: checkDate).day ?? 0
                if daysBetween == 1 {
                    checkDate = dayStart
                } else {
                    break
                }
            }
        }
        
        // Calculate longest streak
        var longestStreak = 0
        var tempStreak = 0
        var previousDate: Date?
        
        for date in sortedDates {
            let dayStart = calendar.startOfDay(for: date)
            if let prev = previousDate {
                let daysBetween = calendar.dateComponents([.day], from: dayStart, to: prev).day ?? 0
                if daysBetween <= 1 {
                    tempStreak += 1
                } else {
                    longestStreak = max(longestStreak, tempStreak)
                    tempStreak = 1
                }
            } else {
                tempStreak = 1
            }
            previousDate = dayStart
        }
        longestStreak = max(longestStreak, tempStreak)
        
        await saveStreakData(
            userId: userId,
            type: type,
            current: currentStreak,
            longest: longestStreak,
            total: achievedDates.count,
            lastDate: sortedDates.first
        )
    }
    
    private func saveStreakData(userId: UUID, type: String, current: Int, longest: Int, total: Int, lastDate: Date?) async {
        struct StreakUpsert: Encodable {
            let user_id: String
            let streak_type: String
            let current_streak: Int
            let longest_streak: Int
            let total_days_achieved: Int
            let last_achieved_date: String?
            let updated_at: String
        }
        
        let data = StreakUpsert(
            user_id: userId.uuidString,
            streak_type: type,
            current_streak: current,
            longest_streak: longest,
            total_days_achieved: total,
            last_achieved_date: lastDate.map { formatDate($0) },
            updated_at: dateToISO(Date())
        )
        
        do {
            try await supabase.supabaseClient
                .from("user_streak_tracking")
                .upsert(data, onConflict: "user_id,streak_type")
                .execute()
            
            AppLogger.debug("🔥 [INSIGHTS] Updated \(type) streak: \(current) current, \(longest) longest", category: .general)
        } catch {
            AppLogger.error("❌ [INSIGHTS] Failed to save streak: \(error)", category: .general)
        }
    }
    
    // MARK: - Correlation Analysis
    
    private func analyzeCorrelations(userId: UUID) async {
        AppLogger.debug("📊 [INSIGHTS] Analyzing correlations...", category: .general)
        
        let recentData = await getRecentDailySummaries(userId: userId, days: 30)
        guard recentData.count >= 7 else {
            AppLogger.warning("⚠️ [INSIGHTS] Not enough data for correlation analysis", category: .general)
            return
        }
        
        // Protein vs Weight Change
        await analyzeProteinWeightCorrelation(userId: userId, data: recentData)
        
        // Hydration vs Workout Performance
        await analyzeHydrationPerformanceCorrelation(userId: userId, data: recentData)
        
        // Sleep vs PRs (if we have sleep data)
        await analyzeSleepPerformanceCorrelation(userId: userId, data: recentData)
        
        // Workout Frequency vs Weight Change
        await analyzeWorkoutWeightCorrelation(userId: userId, data: recentData)
    }
    
    private func analyzeProteinWeightCorrelation(userId: UUID, data: [DailySummaryLight]) async {
        // Get days with both protein and weight data
        let validDays = data.filter { $0.protein != nil && $0.weightLbs != nil }
        guard validDays.count >= 7 else { return }
        
        let proteinValues = validDays.compactMap { $0.protein.map { Double($0) } }
        let weightValues = validDays.compactMap { $0.weightLbs }
        
        let correlation = calculatePearsonCorrelation(x: proteinValues, y: weightValues)
        
        var recommendation: String?
        var isActionable = false
        
        let userGoal = getUserFitnessGoal()
        
        if userGoal == "Build Muscle" || userGoal == "Gain Strength" {
            if correlation > 0.3 {
                recommendation = "Your weight responds well to protein. Keep hitting your protein goals to support muscle growth!"
                isActionable = true
            } else if correlation < -0.2 {
                recommendation = "Consider increasing protein intake - you may be under-eating for your goals."
                isActionable = true
            }
        } else if userGoal == "Lose Weight" || userGoal == "Lose Fat" {
            if correlation < -0.3 {
                recommendation = "High protein is helping you lose weight while preserving muscle. Keep it up!"
                isActionable = true
            }
        }
        
        await saveCorrelation(
            userId: userId,
            metricA: "protein_intake",
            metricB: "weight_change",
            coefficient: correlation,
            sampleSize: validDays.count,
            recommendation: recommendation,
            isActionable: isActionable
        )
    }
    
    private func analyzeHydrationPerformanceCorrelation(userId: UUID, data: [DailySummaryLight]) async {
        let validDays = data.filter { $0.hydration != nil && $0.workoutCount ?? 0 > 0 }
        guard validDays.count >= 5 else { return }
        
        let hydrationValues = validDays.compactMap { $0.hydration.map { Double($0) } }
        let volumeValues: [Double] = [] // TODO: Connect real workout volume data when available
        
        let correlation = calculatePearsonCorrelation(x: hydrationValues, y: volumeValues)
        
        var recommendation: String?
        if correlation > 0.3 {
            recommendation = "You lift heavier when well-hydrated. Aim for your water goal before workouts!"
        }
        
        await saveCorrelation(
            userId: userId,
            metricA: "hydration",
            metricB: "workout_volume",
            coefficient: correlation,
            sampleSize: validDays.count,
            recommendation: recommendation,
            isActionable: correlation > 0.3
        )
    }
    
    private func analyzeSleepPerformanceCorrelation(userId: UUID, data: [DailySummaryLight]) async {
        let validDays = data.filter { $0.sleepHours != nil && $0.workoutCount ?? 0 > 0 }
        guard validDays.count >= 5 else { return }
        
        // This would correlate sleep with next-day PR likelihood
        // For now, we'll create a placeholder
        let sleepValues = validDays.compactMap { $0.sleepHours }
        guard !sleepValues.isEmpty else { return }
        
        let avgSleep = sleepValues.reduce(0, +) / Double(sleepValues.count)
        
        var recommendation: String?
        if avgSleep < 7 {
            recommendation = "Getting 7+ hours of sleep can boost your workout performance by up to 20%!"
        }
        
        await saveCorrelation(
            userId: userId,
            metricA: "sleep_hours",
            metricB: "workout_performance",
            coefficient: 0,
            sampleSize: validDays.count,
            recommendation: recommendation,
            isActionable: avgSleep < 7
        )
    }
    
    private func analyzeWorkoutWeightCorrelation(userId: UUID, data: [DailySummaryLight]) async {
        // Group by week and analyze
        let calendar = Calendar.current
        var weeklyWorkouts: [Date: Int] = [:]
        var weeklyWeightChange: [Date: Double] = [:]
        
        for day in data {
            let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: day.date))!
            weeklyWorkouts[weekStart, default: 0] += day.workoutCount ?? 0
            
            if let weight = day.weightLbs {
                if weeklyWeightChange[weekStart] == nil {
                    weeklyWeightChange[weekStart] = weight
                }
            }
        }
        
        // Need at least 3 weeks of data
        guard weeklyWorkouts.count >= 3 else { return }
        
        let workoutCounts = weeklyWorkouts.values.map { Double($0) }
        let avgWorkouts = workoutCounts.reduce(0, +) / Double(workoutCounts.count)
        
        var recommendation: String?
        let userGoal = getUserFitnessGoal()
        
        if userGoal == "Build Muscle" && avgWorkouts < 3 {
            recommendation = "Training 4+ times per week can accelerate muscle growth by 30%!"
        } else if userGoal == "Lose Weight" && avgWorkouts < 4 {
            recommendation = "Adding one more workout per week can boost fat loss significantly!"
        }
        
        await saveCorrelation(
            userId: userId,
            metricA: "workout_frequency",
            metricB: "goal_progress",
            coefficient: 0,
            sampleSize: weeklyWorkouts.count,
            recommendation: recommendation,
            isActionable: recommendation != nil
        )
    }
    
    private func saveCorrelation(
        userId: UUID,
        metricA: String,
        metricB: String,
        coefficient: Double,
        sampleSize: Int,
        recommendation: String?,
        isActionable: Bool
    ) async {
        let direction: String
        let strength: String
        
        if sampleSize < 5 {
            return // Not enough data
        }
        
        if abs(coefficient) < 0.1 {
            direction = "neutral"
            strength = "none"
        } else if coefficient > 0 {
            direction = "positive"
            strength = coefficient > 0.5 ? "strong" : (coefficient > 0.3 ? "moderate" : "weak")
        } else {
            direction = "negative"
            strength = coefficient < -0.5 ? "strong" : (coefficient < -0.3 ? "moderate" : "weak")
        }
        
        struct CorrelationUpsert: Encodable {
            let user_id: String
            let metric_a: String
            let metric_b: String
            let correlation_coefficient: Double
            let sample_size: Int
            let confidence_level: Double
            let time_window_days: Int
            let relationship_direction: String
            let relationship_strength: String
            let is_actionable: Bool
            let action_recommendation: String?
            let calculated_at: String
        }
        
        let data = CorrelationUpsert(
            user_id: userId.uuidString,
            metric_a: metricA,
            metric_b: metricB,
            correlation_coefficient: coefficient,
            sample_size: sampleSize,
            confidence_level: min(1.0, Double(sampleSize) / 30.0),
            time_window_days: 30,
            relationship_direction: direction,
            relationship_strength: strength,
            is_actionable: isActionable,
            action_recommendation: recommendation,
            calculated_at: dateToISO(Date())
        )
        
        do {
            try await supabase.supabaseClient
                .from("user_metric_correlations")
                .upsert(data, onConflict: "user_id,metric_a,metric_b,time_window_days")
                .execute()
            
            AppLogger.debug("📊 [INSIGHTS] Saved correlation: \(metricA) ↔ \(metricB) = \(String(format: "%.2f", coefficient))", category: .general)
        } catch {
            AppLogger.error("❌ [INSIGHTS] Failed to save correlation: \(error)", category: .general)
        }
    }
    
    // MARK: - Goal-Specific Insights
    
    private func generateGoalInsights(userId: UUID) async {
        guard let goal = getUserFitnessGoal() else { return }
        
        AppLogger.debug("🎯 [INSIGHTS] Generating goal-specific insights for: \(goal)", category: .general)
        
        let recentData = await getRecentDailySummaries(userId: userId, days: 7)
        guard !recentData.isEmpty else { return }
        
        switch goal {
        case "Build Muscle":
            await generateBuildMuscleInsights(userId: userId, data: recentData)
        case "Lose Weight", "Lose Fat":
            await generateWeightLossInsights(userId: userId, data: recentData)
        case "Gain Strength", "Get Stronger":
            await generateStrengthInsights(userId: userId, data: recentData)
        case "Improve Endurance":
            await generateEnduranceInsights(userId: userId, data: recentData)
        default:
            await generateGeneralFitnessInsights(userId: userId, data: recentData)
        }
    }
    
    private func generateBuildMuscleInsights(userId: UUID, data: [DailySummaryLight]) async {
        // Check protein consistency
        let proteinGoal = getUserProteinGoal() ?? 150
        let proteinDays = data.filter { ($0.protein ?? 0) >= Int(proteinGoal * 0.9) }
        
        // Check weight trend
        let weightsThisWeek = data.compactMap { $0.weightLbs }
        let weightChange = weightsThisWeek.count >= 2 ? (weightsThisWeek.first ?? 0) - (weightsThisWeek.last ?? 0) : 0
        
        // Check workout volume
        let workoutDays = data.filter { ($0.workoutCount ?? 0) > 0 }.count
        
        if proteinDays.count >= 5 && weightChange > 0 {
            await createInsight(
                userId: userId,
                type: .achievement,
                category: .goal,
                title: "Protein Consistency = Gains! 💪",
                message: "You hit your protein goal \(proteinDays.count) days this week and gained \(String(format: "%.1f", weightChange)) lbs. The grind matters!",
                detail: "Consistent protein intake of \(Int(proteinGoal))g+ ensures your muscles have the building blocks they need. Combined with your \(workoutDays) workouts, you're creating the perfect environment for growth.",
                dataPoints: ["protein_days": Double(proteinDays.count), "weight_gain": weightChange, "workouts": Double(workoutDays)],
                priority: .high,
                icon: "flame.fill",
                color: "orange",
                goal: "Build Muscle"
            )
        } else if proteinDays.count < 4 && workoutDays >= 3 {
            await createInsight(
                userId: userId,
                type: .tip,
                category: .nutrition,
                title: "Feed Those Muscles! 🍗",
                message: "You're training hard (\(workoutDays) workouts) but only hit protein \(proteinDays.count) days. You might be leaving gains on the table!",
                detail: "Muscle protein synthesis peaks when you consistently hit \(Int(proteinGoal))g+ protein daily. Try adding a protein shake or Greek yogurt to boost your intake.",
                dataPoints: ["protein_days": Double(proteinDays.count), "workouts": Double(workoutDays)],
                priority: .medium,
                icon: "fork.knife",
                color: "blue",
                goal: "Build Muscle"
            )
        }
    }
    
    private func generateWeightLossInsights(userId: UUID, data: [DailySummaryLight]) async {
        let calorieGoal = getUserCalorieGoal() ?? 2000
        let deficitDays = data.filter { ($0.calories ?? 0) > 0 && ($0.calories ?? 0) <= calorieGoal }
        
        let weightsThisWeek = data.compactMap { $0.weightLbs }
        let weightChange = weightsThisWeek.count >= 2 ? (weightsThisWeek.first ?? 0) - (weightsThisWeek.last ?? 0) : 0
        
        let proteinGoal = getUserProteinGoal() ?? 120
        let proteinDays = data.filter { ($0.protein ?? 0) >= Int(proteinGoal * 0.85) }
        
        if deficitDays.count >= 5 && weightChange < 0 {
            await createInsight(
                userId: userId,
                type: .achievement,
                category: .goal,
                title: "Deficit Discipline Paying Off! 🔥",
                message: "You stayed in a deficit \(deficitDays.count) days and lost \(String(format: "%.1f", abs(weightChange))) lbs. Sustainable progress!",
                detail: proteinDays.count >= 4
                    ? "Even better - you kept protein high (\(proteinDays.count) days), which helps preserve muscle during your cut."
                    : "Tip: Keeping protein high helps preserve muscle while losing fat.",
                dataPoints: ["deficit_days": Double(deficitDays.count), "weight_loss": abs(weightChange), "protein_days": Double(proteinDays.count)],
                priority: .high,
                icon: "flame.fill",
                color: "green",
                goal: "Lose Weight"
            )
        } else if deficitDays.count < 3 {
            let avgCalories = data.compactMap { $0.calories }.reduce(0, +) / max(1, data.compactMap { $0.calories }.count)
            let surplus = avgCalories - calorieGoal
            
            if surplus > 0 {
                await createInsight(
                    userId: userId,
                    type: .warning,
                    category: .nutrition,
                    title: "Calorie Creep Alert ⚠️",
                    message: "You averaged \(surplus) calories over goal this week. Small surpluses add up!",
                    detail: "That's \(surplus * 7) extra calories this week - roughly \(String(format: "%.1f", Double(surplus * 7) / 3500)) lbs worth. Try tracking more closely or planning meals ahead.",
                    dataPoints: ["avg_surplus": Double(surplus), "weekly_excess": Double(surplus * 7)],
                    priority: .medium,
                    icon: "exclamationmark.triangle.fill",
                    color: "orange",
                    goal: "Lose Weight"
                )
            }
        }
    }
    
    private func generateStrengthInsights(userId: UUID, data: [DailySummaryLight]) async {
        // Focus on workout frequency and recovery
        let workoutDays = data.filter { ($0.workoutCount ?? 0) > 0 }.count
        let avgSleep = data.compactMap { $0.sleepHours }.reduce(0, +) / max(1, Double(data.compactMap { $0.sleepHours }.count))
        
        if workoutDays >= 4 && avgSleep >= 7 {
            await createInsight(
                userId: userId,
                type: .tip,
                category: .recovery,
                title: "Recovery Game Strong 😴",
                message: "Averaging \(String(format: "%.1f", avgSleep)) hours sleep + \(workoutDays) intense sessions = strength gains!",
                detail: "Sleep is when your nervous system recovers and adapts to heavy lifting. You're doing it right!",
                dataPoints: ["workouts": Double(workoutDays), "avg_sleep": avgSleep],
                priority: .medium,
                icon: "moon.fill",
                color: "purple",
                goal: "Get Stronger"
            )
        }
    }
    
    private func generateEnduranceInsights(userId: UUID, data: [DailySummaryLight]) async {
        // Focus on hydration and step count
        let hydrationDays = data.filter { $0.hydrationGoalMet == true }.count
        let avgSteps = data.compactMap { $0.stepCount }.reduce(0, +) / max(1, data.compactMap { $0.stepCount }.count)
        
        if hydrationDays >= 5 && avgSteps >= 8000 {
            await createInsight(
                userId: userId,
                type: .achievement,
                category: .goal,
                title: "Endurance Engine Running! 🏃",
                message: "Hydration on point (\(hydrationDays) days) + \(avgSteps.formatted()) avg steps = cardio gains!",
                detail: "Proper hydration can improve endurance performance by up to 25%. Keep it up!",
                dataPoints: ["hydration_days": Double(hydrationDays), "avg_steps": Double(avgSteps)],
                priority: .high,
                icon: "heart.fill",
                color: "red",
                goal: "Improve Endurance"
            )
        }
    }
    
    private func generateGeneralFitnessInsights(userId: UUID, data: [DailySummaryLight]) async {
        // General balanced approach
        let workoutDays = data.filter { ($0.workoutCount ?? 0) > 0 }.count
        let nutritionLoggedDays = data.filter { ($0.calories ?? 0) > 0 }.count
        
        if workoutDays >= 3 && nutritionLoggedDays >= 5 {
            await createInsight(
                userId: userId,
                type: .achievement,
                category: .streak,
                title: "Consistent & Committed! ⭐",
                message: "You logged nutrition \(nutritionLoggedDays) days and trained \(workoutDays) times this week!",
                detail: "Consistency beats perfection. Small daily actions compound into big results over time.",
                dataPoints: ["workouts": Double(workoutDays), "nutrition_days": Double(nutritionLoggedDays)],
                priority: .medium,
                icon: "star.fill",
                color: "yellow",
                goal: nil
            )
        }
    }
    
    // MARK: - Pattern Detection
    
    private func detectBehaviorPatterns(userId: UUID) async {
        AppLogger.debug("🔍 [INSIGHTS] Detecting behavior patterns...", category: .general)
        
        // Detect best workout time
        await detectBestWorkoutTime(userId: userId)
        
        // Detect nutrition habits
        await detectNutritionPatterns(userId: userId)
        
        // Detect social workout booster
        await detectSocialPatterns(userId: userId)
    }
    
    private func detectBestWorkoutTime(userId: UUID) async {
        // This would analyze workout_time_performance table
        // For now, create a placeholder insight
        
        struct PatternUpsert: Encodable {
            let user_id: String
            let pattern_type: String
            let pattern_name: String
            let pattern_data: String
            let confidence_score: Double
            let data_points_used: Int
            let impact_area: String
            let leverage_recommendation: String?
        }
        
        // Query for best time slot (placeholder)
        let pattern = PatternUpsert(
            user_id: userId.uuidString,
            pattern_type: "time_preference",
            pattern_name: "morning_person",
            pattern_data: "{\"best_time_slot\": \"morning\", \"avg_volume_multiplier\": 1.2}",
            confidence_score: 0.7,
            data_points_used: 15,
            impact_area: "workout_performance",
            leverage_recommendation: "Schedule your most important lifts in the morning for 20% better performance"
        )
        
        do {
            try await supabase.supabaseClient
                .from("user_behavior_patterns")
                .upsert(pattern, onConflict: "user_id,pattern_type,pattern_name")
                .execute()
        } catch {
            AppLogger.error("❌ [INSIGHTS] Failed to save pattern: \(error)", category: .general)
        }
    }
    
    private func detectNutritionPatterns(userId: UUID) async {
        // Detect if user is consistently high/low on certain macros
        // Placeholder for now
    }
    
    private func detectSocialPatterns(userId: UUID) async {
        // Check if challenges boost workout frequency
        // Placeholder for now
    }
    
    // MARK: - Performance Windows
    
    private func updatePerformanceWindows(userId: UUID) async {
        AppLogger.debug("📈 [INSIGHTS] Updating performance windows...", category: .general)
        
        // Update 7-day, 14-day, 30-day windows
        for days in [7, 14, 30] {
            await calculatePerformanceWindow(userId: userId, days: days)
        }
    }
    
    private func calculatePerformanceWindow(userId: UUID, days: Int) async {
        let data = await getRecentDailySummaries(userId: userId, days: days)
        guard !data.isEmpty else { return }
        
        let workouts = data.compactMap { $0.workoutCount }.reduce(0, +)
        let avgCalories = data.compactMap { $0.calories }.reduce(0, +) / max(1, data.compactMap { $0.calories }.count)
        let avgProtein = data.compactMap { $0.protein }.reduce(0, +) / max(1, data.compactMap { $0.protein }.count)
        
        let weights = data.compactMap { $0.weightLbs }
        let weightChange = weights.count >= 2 ? (weights.first ?? 0) - (weights.last ?? 0) : 0
        
        struct WindowUpsert: Encodable {
            let user_id: String
            let window_type: String
            let window_end_date: String
            let workouts_completed: Int
            let avg_daily_calories: Int
            let avg_daily_protein: Int
            let weight_change_lbs: Double
            let created_at: String
        }
        
        let window = WindowUpsert(
            user_id: userId.uuidString,
            window_type: "\(days)_day",
            window_end_date: formatDate(Date()),
            workouts_completed: workouts,
            avg_daily_calories: avgCalories,
            avg_daily_protein: avgProtein,
            weight_change_lbs: weightChange,
            created_at: dateToISO(Date())
        )
        
        do {
            try await supabase.supabaseClient
                .from("user_performance_windows")
                .upsert(window, onConflict: "user_id,window_type,window_end_date")
                .execute()
        } catch {
            AppLogger.error("❌ [INSIGHTS] Failed to save window: \(error)", category: .general)
        }
    }
    
    // MARK: - Cross-Table Correlation Insights

    private func generateCrossTableInsights(userId: UUID) async {
        let intelligence = AdvancedIntelligenceService.shared

        if let nutr = await intelligence.getNutritionWorkoutCorrelation(userId: userId),
           nutr.sampleSize >= 5 {
            let diff = nutr.highProteinAvgCompletion - nutr.lowProteinAvgCompletion
            if diff > 0.1 {
                let pctBetter = Int(diff * 100)
                await createInsight(
                    userId: userId,
                    type: .correlation,
                    category: .nutrition,
                    title: "Nutrition Powers Your Workouts",
                    message: "Your workout completion is \(pctBetter)% higher on days after eating 120g+ protein.",
                    detail: "Based on \(nutr.sampleSize) workouts. High protein days: \(Int(nutr.highProteinAvgCompletion * 100))% completion vs \(Int(nutr.lowProteinAvgCompletion * 100))% on low protein days.",
                    dataPoints: ["high_protein_completion": nutr.highProteinAvgCompletion, "low_protein_completion": nutr.lowProteinAvgCompletion],
                    priority: .high,
                    icon: "fork.knife",
                    color: "green",
                    goal: nil
                )
            }
        }

        if let hyd = await intelligence.getHydrationWorkoutCorrelation(userId: userId),
           hyd.sampleSize >= 5 {
            let diff = hyd.hydratedAvgCompletion - hyd.dehydratedAvgCompletion
            if diff > 0.1 {
                let pctBetter = Int(diff * 100)
                await createInsight(
                    userId: userId,
                    type: .correlation,
                    category: .hydration,
                    title: "Hydration Boosts Performance",
                    message: "You complete \(pctBetter)% more sets when you hit your water goal.",
                    detail: "Based on \(hyd.sampleSize) workouts. Hydrated: \(Int(hyd.hydratedAvgCompletion * 100))% completion vs \(Int(hyd.dehydratedAvgCompletion * 100))% when under-hydrated.",
                    dataPoints: ["hydrated_completion": hyd.hydratedAvgCompletion, "dehydrated_completion": hyd.dehydratedAvgCompletion],
                    priority: .high,
                    icon: "drop.fill",
                    color: "blue",
                    goal: nil
                )
            }
        }

        if let comp = await intelligence.getCompletionRateInsight(userId: userId) {
            if comp.avgRate < 0.85, let lowestCat = comp.lowestCategory, let lowestRate = comp.lowestRate {
                await createInsight(
                    userId: userId,
                    type: .tip,
                    category: .workout,
                    title: "Completion Rate Insight",
                    message: "\(lowestCat) days have a \(Int(lowestRate * 100))% completion rate. Try shorter sessions.",
                    detail: "Your average completion across all workouts is \(Int(comp.avgRate * 100))%. \(lowestCat) workouts are pulling it down.",
                    dataPoints: ["avg_rate": comp.avgRate, "lowest_rate": lowestRate],
                    priority: .medium,
                    icon: "chart.bar.fill",
                    color: "orange",
                    goal: nil
                )
            }
        }

        // Social nudge for users without friends
        do {
            struct SocialRow: Decodable {
                let friend_count: Int
                let days_since_last_workout: Double?
            }
            let rows: [SocialRow] = try await supabase.supabaseClient
                .from("v_social_retention_correlation")
                .select("friend_count, days_since_last_workout")
                .eq("user_id", value: userId.uuidString)
                .limit(1)
                .execute()
                .value

            if let row = rows.first, row.friend_count == 0 {
                await createInsight(
                    userId: userId,
                    type: .tip,
                    category: .social,
                    title: "Train With Friends",
                    message: "Users with friends work out 2x more often. Add a friend to stay motivated!",
                    detail: nil,
                    dataPoints: nil,
                    priority: .medium,
                    icon: "person.2.fill",
                    color: "purple",
                    goal: nil
                )
            }
        } catch {
            AppLogger.warning("⚠️ [INSIGHTS] Social correlation query failed: \(error)", category: .general)
        }

        // Challenge boost insight
        do {
            struct ChallengeRow: Decodable {
                let total_challenges: Int
                let completed_challenges: Int
            }
            let rows: [ChallengeRow] = try await supabase.supabaseClient
                .from("v_challenge_progress_correlation")
                .select("total_challenges, completed_challenges")
                .eq("user_id", value: userId.uuidString)
                .limit(1)
                .execute()
                .value

            if let row = rows.first, row.completed_challenges >= 1 {
                await createInsight(
                    userId: userId,
                    type: .achievement,
                    category: .social,
                    title: "Challenge Champion",
                    message: "You've completed \(row.completed_challenges) challenges! Challenge participants progress faster.",
                    detail: "Join another challenge to keep the momentum going.",
                    dataPoints: ["completed_challenges": Double(row.completed_challenges)],
                    priority: .low,
                    icon: "trophy.fill",
                    color: "yellow",
                    goal: nil
                )
            }
        } catch {
            AppLogger.warning("⚠️ [INSIGHTS] Challenge correlation query failed: \(error)", category: .general)
        }

        AppLogger.debug("🧠 [INSIGHTS] Cross-table correlation insights generated", category: .general)
    }

    // MARK: - Weekly Insights RPC

    private func generateWeeklyInsightsRPC(userId: UUID) async {
        struct GenerateParams: Encodable {
            let p_user_id: String
        }
        
        do {
            let params = GenerateParams(p_user_id: userId.uuidString)
            let result: Int = try await supabase.supabaseClient
                .rpc("generate_weekly_insights", params: params)
                .execute()
                .value
            
            AppLogger.debug("🧠 [INSIGHTS] Generated \(result) weekly insights via RPC", category: .general)
        } catch {
            AppLogger.error("❌ [INSIGHTS] Failed to generate weekly insights: \(error)", category: .general)
        }
    }
    
    // MARK: - Helper Functions
    
    private func createInsight(
        userId: UUID,
        type: InsightType,
        category: InsightCategory,
        title: String,
        message: String,
        detail: String?,
        dataPoints: [String: Double]?,
        priority: InsightPriority,
        icon: String,
        color: String,
        goal: String?
    ) async {
        struct InsightInsert: Encodable {
            let user_id: String
            let insight_type: String
            let insight_category: String
            let title: String
            let message: String
            let detail_message: String?
            let data_points: String?
            let related_goal: String?
            let time_period: String
            let priority: Int
            let icon: String
            let accent_color: String
            let valid_until: String
        }
        
        let dataPointsJson: String?
        if let dp = dataPoints {
            dataPointsJson = try? String(data: JSONEncoder().encode(dp), encoding: .utf8)
        } else {
            dataPointsJson = nil
        }
        
        let validUntil = Calendar.current.date(byAdding: .day, value: 7, to: Date())!
        
        let insight = InsightInsert(
            user_id: userId.uuidString,
            insight_type: type.rawValue,
            insight_category: category.rawValue,
            title: title,
            message: message,
            detail_message: detail,
            data_points: dataPointsJson,
            related_goal: goal,
            time_period: "this_week",
            priority: priority.rawValue,
            icon: icon,
            accent_color: color,
            valid_until: dateToISO(validUntil)
        )
        
        do {
            try await supabase.supabaseClient
                .from("user_personalized_insights")
                .insert(insight)
                .execute()
            
            AppLogger.debug("💡 [INSIGHTS] Created: \(title)", category: .general)
        } catch {
            AppLogger.error("❌ [INSIGHTS] Failed to create insight: \(error)", category: .general)
        }
    }
    
    // MARK: - Data Fetching
    
    struct DailySummaryLight {
        let date: Date
        let calories: Int?
        let protein: Int?
        let carbs: Int?
        let fat: Int?
        let hydration: Int?
        let hydrationGoalMet: Bool?
        let weightLbs: Double?
        let workoutCount: Int?
        let stepCount: Int?
        let sleepHours: Double?
    }
    
    private func getRecentDailySummaries(userId: UUID, days: Int) async -> [DailySummaryLight] {
        struct DailySummaryDTO: Decodable {
            let date: String
            let calories_consumed: Int?
            let protein_g: Int?
            let carbs_g: Int?
            let fat_g: Int?
            let hydration_ml: Int?
            let hydration_goal_met: Bool?
            let weight_lbs: Double?
            let workout_count: Int?
            let step_count: Int?
            let sleep_hours: Double?
        }
        
        do {
            let startDate = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
            
            let results: [DailySummaryDTO] = try await supabase.supabaseClient
                .from("daily_summaries")
                .select()
                .eq("user_id", value: userId.uuidString)
                .gte("date", value: formatDate(startDate))
                .order("date", ascending: false)
                .execute()
                .value
            
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            
            return results.compactMap { dto in
                guard let date = formatter.date(from: dto.date) else { return nil }
                return DailySummaryLight(
                    date: date,
                    calories: dto.calories_consumed,
                    protein: dto.protein_g,
                    carbs: dto.carbs_g,
                    fat: dto.fat_g,
                    hydration: dto.hydration_ml,
                    hydrationGoalMet: dto.hydration_goal_met,
                    weightLbs: dto.weight_lbs,
                    workoutCount: dto.workout_count,
                    stepCount: dto.step_count,
                    sleepHours: dto.sleep_hours
                )
            }
        } catch {
            AppLogger.error("❌ [INSIGHTS] Failed to fetch daily summaries: \(error)", category: .general)
            return []
        }
    }
    
    private func getUserFitnessGoal() -> String? {
        let context = PersistenceController.shared.container.viewContext
        let request: NSFetchRequest<User> = User.fetchRequest()
        request.fetchLimit = 1
        
        do {
            let users = try context.fetch(request)
            return users.first?.fitnessGoal
        } catch {
            return nil
        }
    }
    
    private func getUserProteinGoal() -> Double? {
        let context = PersistenceController.shared.container.viewContext
        let request: NSFetchRequest<User> = User.fetchRequest()
        request.fetchLimit = 1
        
        do {
            let users = try context.fetch(request)
            guard let user = users.first else { return nil }
            // Calculate protein goal: ~0.8g per lb of body weight
            let weightLbs = user.weightLbs > 0 ? user.weightLbs : Double(user.weight) * 2.205
            return max(100, weightLbs * 0.8)
        } catch {
            return nil
        }
    }
    
    private func getUserCalorieGoal() -> Int? {
        let context = PersistenceController.shared.container.viewContext
        let request: NSFetchRequest<User> = User.fetchRequest()
        request.fetchLimit = 1
        
        do {
            let users = try context.fetch(request)
            guard let user = users.first else { return nil }
            // Calculate calorie goal based on weight and fitness goal
            let isMale = user.gender?.lowercased() == "male"
            let baseCalories = isMale ? 2200 : 1800
            let weightFactor = max(0.8, min(1.2, Double(user.weight) / 150.0))
            return Int(Double(baseCalories) * weightFactor)
        } catch {
            return nil
        }
    }
    
    // MARK: - Statistical Functions
    
    private func calculatePearsonCorrelation(x: [Double], y: [Double]) -> Double {
        guard x.count == y.count, x.count > 2 else { return 0 }
        
        let n = Double(x.count)
        let sumX = x.reduce(0, +)
        let sumY = y.reduce(0, +)
        let sumXY = zip(x, y).map(*).reduce(0, +)
        let sumX2 = x.map { $0 * $0 }.reduce(0, +)
        let sumY2 = y.map { $0 * $0 }.reduce(0, +)
        
        let numerator = n * sumXY - sumX * sumY
        let denominator = sqrt((n * sumX2 - sumX * sumX) * (n * sumY2 - sumY * sumY))
        
        guard denominator != 0 else { return 0 }
        
        return numerator / denominator
    }
}
