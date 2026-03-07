//
//  BodyCompositionTrackingService.swift
//  Fit33
//
//  Service for managing body composition data and goals
//  Integrates with InBody, manual entry, and other sources
//

import Foundation
import SwiftUI
import Combine

// MARK: - Body Composition Tracking Service

/// Manages body composition data from various sources (InBody, manual, etc.)
class BodyCompositionTrackingService: ObservableObject {
    static let shared = BodyCompositionTrackingService()
    
    // MARK: - Published Properties
    @Published var currentComposition: BodyComposition?
    @Published var compositionHistory: [BodyComposition] = []
    @Published var compositionGoal: BodyCompositionGoal?
    @Published var statistics: BodyCompositionStats?
    @Published var isLoading = false
    
    // MARK: - Private Properties
    private let supabase = SupabaseManager.shared
    private var cancellables = Set<AnyCancellable>()
    
    /// Get the current user ID
    private var currentUserId: String? {
        supabase.currentUser?.id.uuidString
    }
    
    // MARK: - Init
    
    private init() {
        // Subscribe to InBody updates
        InBodyService.shared.$latestScan
            .sink { [weak self] scan in
                if let scan = scan {
                    self?.updateFromInBodyScan(scan)
                }
            }
            .store(in: &cancellables)
        
        Task {
            await loadData()
        }
    }
    
    // MARK: - Data Loading
    
    @MainActor
    func loadData() async {
        isLoading = true
        
        async let compositionsTask = loadCompositionHistory()
        async let goalTask = loadGoal()
        async let statsTask = loadStatistics()
        
        await compositionsTask
        await goalTask
        await statsTask
        
        isLoading = false
    }
    
    private func loadCompositionHistory() async {
        guard let userId = currentUserId else { return }
        
        do {
            let response = try await supabase.supabaseClient
                .from("body_composition_logs")
                .select()
                .eq("user_id", value: userId)
                .order("measured_at", ascending: false)
                .limit(100)
                .execute()
            
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            decoder.dateDecodingStrategy = .iso8601
            let compositions = try decoder.decode([BodyComposition].self, from: response.data)
            
            await MainActor.run {
                self.compositionHistory = compositions
                self.currentComposition = compositions.first
            }
            
        } catch {
            print("⚠️ [BODY COMP] Failed to load history: \(error)")
        }
    }
    
    private func loadGoal() async {
        guard let userId = currentUserId else { return }
        
        do {
            let response = try await supabase.supabaseClient
                .from("body_composition_goals")
                .select()
                .eq("user_id", value: userId)
                .single()
                .execute()
            
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let goal = try decoder.decode(BodyCompositionGoal.self, from: response.data)
            
            await MainActor.run {
                self.compositionGoal = goal
            }
            
        } catch {
            // No goal set yet, that's OK
            print("ℹ️ [BODY COMP] No goal set")
        }
    }
    
    private func loadStatistics() async {
        guard let userId = currentUserId else { return }
        
        do {
            let response = try await supabase.supabaseClient
                .from("body_composition_statistics")
                .select()
                .eq("user_id", value: userId)
                .single()
                .execute()
            
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let stats = try decoder.decode(BodyCompositionStats.self, from: response.data)
            
            await MainActor.run {
                self.statistics = stats
            }
            
        } catch {
            print("ℹ️ [BODY COMP] No statistics available")
        }
    }
    
    // MARK: - Manual Entry
    
    /// Log body composition manually (without InBody device)
    func logManualEntry(
        weightKg: Double,
        bodyFatPercentage: Double?,
        muscleMassKg: Double?,
        notes: String? = nil
    ) async throws {
        guard let userId = currentUserId else {
            throw BodyCompositionError.notAuthenticated
        }
        
        struct ManualBodyCompositionInsert: Encodable {
            let user_id: String
            let weight_kg: Double
            let weight_lbs: Double
            let body_fat_percentage: Double?
            let skeletal_muscle_mass_kg: Double?
            let source: String
            let measured_at: String
        }
        
        let entry = ManualBodyCompositionInsert(
            user_id: userId,
            weight_kg: weightKg,
            weight_lbs: weightKg * 2.20462,
            body_fat_percentage: bodyFatPercentage,
            skeletal_muscle_mass_kg: muscleMassKg,
            source: "manual",
            measured_at: Date().ISO8601Format()
        )
        
        try await supabase.supabaseClient
            .from("body_composition_logs")
            .insert(entry)
            .execute()
        
        await loadData()
        
        print("✅ [BODY COMP] Manual entry logged")
    }
    
    // MARK: - InBody Integration
    
    private func updateFromInBodyScan(_ scan: BodyCompositionScan) {
        let composition = BodyComposition(from: scan)
        
        DispatchQueue.main.async {
            self.currentComposition = composition
            
            // Add to history if not already present
            if !self.compositionHistory.contains(where: { $0.id == composition.id }) {
                self.compositionHistory.insert(composition, at: 0)
            }
        }
    }
    
    // MARK: - Goal Management
    
    /// Set body composition goal
    func setGoal(
        targetWeight: Double?,
        targetBodyFat: Double?,
        targetMuscleMass: Double?,
        primaryGoal: BodyCompositionGoalType,
        targetDate: Date?
    ) async throws {
        guard let userId = currentUserId else {
            throw BodyCompositionError.notAuthenticated
        }
        
        struct BodyCompositionGoalUpsert: Encodable {
            let user_id: String
            let target_weight_kg: Double?
            let target_weight_lbs: Double?
            let target_body_fat_percentage: Double?
            let target_muscle_mass_kg: Double?
            let primary_goal: String
            let target_date: String?
            let updated_at: String
        }
        
        let goal = BodyCompositionGoalUpsert(
            user_id: userId,
            target_weight_kg: targetWeight,
            target_weight_lbs: targetWeight.map { $0 * 2.20462 },
            target_body_fat_percentage: targetBodyFat,
            target_muscle_mass_kg: targetMuscleMass,
            primary_goal: primaryGoal.rawValue,
            target_date: targetDate?.ISO8601Format(),
            updated_at: Date().ISO8601Format()
        )
        
        try await supabase.supabaseClient
            .from("body_composition_goals")
            .upsert(goal, onConflict: "user_id")
            .execute()
        
        await loadGoal()
        
        print("✅ [BODY COMP] Goal set")
    }
    
    // MARK: - Progress Tracking
    
    /// Get progress towards goal
    func getProgressTowardsGoal() -> GoalProgress? {
        guard let current = currentComposition,
              let goal = compositionGoal else {
            return nil
        }
        
        var weightProgress: Double?
        var bodyFatProgress: Double?
        var muscleProgress: Double?
        
        // Calculate weight progress
        if let targetWeight = goal.targetWeightKg,
           let startingWeight = compositionHistory.last?.weightKg {
            let totalChange = startingWeight - targetWeight
            let currentChange = startingWeight - current.weightKg
            weightProgress = totalChange != 0 ? (currentChange / totalChange) * 100 : 100
        }
        
        // Calculate body fat progress
        if let targetBF = goal.targetBodyFatPercentage,
           let currentBF = current.bodyFatPercentage,
           let startingBF = compositionHistory.last?.bodyFatPercentage {
            let totalChange = startingBF - targetBF
            let currentChange = startingBF - currentBF
            bodyFatProgress = totalChange != 0 ? (currentChange / totalChange) * 100 : 100
        }
        
        // Calculate muscle progress
        if let targetMuscle = goal.targetMuscleMassKg,
           let currentMuscle = current.skeletalMuscleMassKg,
           let startingMuscle = compositionHistory.last?.skeletalMuscleMassKg {
            let totalChange = targetMuscle - startingMuscle
            let currentChange = currentMuscle - startingMuscle
            muscleProgress = totalChange != 0 ? (currentChange / totalChange) * 100 : 100
        }
        
        return GoalProgress(
            weightProgress: weightProgress,
            bodyFatProgress: bodyFatProgress,
            muscleProgress: muscleProgress,
            primaryGoal: goal.primaryGoal
        )
    }
    
    // MARK: - Insights & Recommendations
    
    /// Get personalized insights based on body composition trends
    func getInsights() -> [BodyCompositionInsight] {
        var insights: [BodyCompositionInsight] = []
        
        guard let current = currentComposition else {
            return [BodyCompositionInsight(
                type: .info,
                title: "Start Tracking",
                message: "Connect InBody or log your body composition to get personalized insights.",
                actionText: "Connect InBody"
            )]
        }
        
        // Body fat insights
        if let bf = current.bodyFatPercentage {
            if bf < 8 {
                insights.append(BodyCompositionInsight(
                    type: .warning,
                    title: "Very Low Body Fat",
                    message: "Body fat below 8% can affect hormone levels and recovery. Consider a maintenance phase.",
                    actionText: nil
                ))
            } else if bf >= 8 && bf < 15 {
                insights.append(BodyCompositionInsight(
                    type: .success,
                    title: "Athletic Body Fat",
                    message: "You're in the athletic range. Great for performance!",
                    actionText: nil
                ))
            } else if bf >= 25 {
                insights.append(BodyCompositionInsight(
                    type: .info,
                    title: "Fat Loss Potential",
                    message: "You have great potential for body recomposition. Focus on progressive overload while in a slight calorie deficit.",
                    actionText: "Adjust Goal"
                ))
            }
        }
        
        // Muscle mass trends
        if let stats = statistics,
           let muscleGain = stats.totalMuscleGain,
           muscleGain > 0 {
            insights.append(BodyCompositionInsight(
                type: .success,
                title: "Muscle Gains!",
                message: "You've gained \(String(format: "%.1f", muscleGain * 2.20462)) lbs of muscle. Keep up the great work!",
                actionText: nil
            ))
        }
        
        // BMR-based recommendation
        if let bmr = current.bmr {
            insights.append(BodyCompositionInsight(
                type: .info,
                title: "Your BMR: \(Int(bmr)) kcal",
                message: "This is your base calorie burn. Your total daily expenditure depends on activity level.",
                actionText: "Update Calories"
            ))
        }
        
        // Visceral fat warning
        if let vf = current.visceralFatLevel, vf > 12 {
            insights.append(BodyCompositionInsight(
                type: .warning,
                title: "Elevated Visceral Fat",
                message: "Visceral fat above 12 is associated with health risks. Prioritize cardio and whole foods.",
                actionText: nil
            ))
        }
        
        return insights
    }
    
    /// Get recommended fitness goal based on body composition
    func getRecommendedFitnessGoal() -> String {
        guard let current = currentComposition else {
            return "Build Muscle"
        }
        
        let bf = current.bodyFatPercentage ?? 20
        let muscleRatio = (current.skeletalMuscleMassKg ?? 30) / current.weightKg * 100
        
        // Decision matrix based on body composition
        switch (bf, muscleRatio) {
        case (0..<15, 0..<38):
            return "Build Muscle"  // Lean but needs muscle
        case (0..<15, 38...):
            return "Get Stronger"  // Lean and muscular - focus on strength
        case (15..<22, 0..<35):
            return "Build Muscle"  // Normal BF, low muscle
        case (15..<22, 35...):
            return "Get Stronger"  // Good composition - performance focus
        case (22..<28, _):
            return "Get Lean"  // Higher BF - prioritize fat loss
        case (28..., _):
            return "Get Lean"  // High BF - definitely fat loss
        default:
            return "Build Muscle"
        }
    }
    
    /// Calculate personalized calorie target using InBody BMR
    func getPersonalizedCalorieTarget(activityLevel: ActivityLevel, goal: CalorieGoal) -> Int? {
        guard let bmr = currentComposition?.bmr else {
            return nil
        }
        
        // Calculate TDEE
        let tdee = bmr * activityLevel.multiplier
        
        // Adjust for goal
        switch goal {
        case .lose:
            return Int(tdee * 0.80)  // 20% deficit
        case .maintain:
            return Int(tdee)
        case .gain:
            return Int(tdee * 1.15)  // 15% surplus
        case .aggressiveLose:
            return Int(tdee * 0.75)  // 25% deficit
        case .aggressiveGain:
            return Int(tdee * 1.20)  // 20% surplus
        }
    }
}

// MARK: - Data Models

struct BodyComposition: Codable, Identifiable {
    let id: UUID
    let weightKg: Double
    let weightLbs: Double
    let bodyFatPercentage: Double?
    let bodyFatMassKg: Double?
    let skeletalMuscleMassKg: Double?
    let leanBodyMassKg: Double?
    let bodyWaterKg: Double?
    let bmi: Double?
    let bmr: Double?
    let visceralFatLevel: Int?
    let inbodyScore: Int?
    let source: String
    let deviceModel: String?
    let measuredAt: Date
    
    init(from scan: BodyCompositionScan) {
        self.id = scan.id
        self.weightKg = scan.weightKg
        self.weightLbs = scan.weightLbs
        self.bodyFatPercentage = scan.bodyFatPercentage
        self.bodyFatMassKg = scan.bodyFatMassKg
        self.skeletalMuscleMassKg = scan.skeletalMuscleMassKg
        self.leanBodyMassKg = scan.leanBodyMassKg
        self.bodyWaterKg = scan.bodyWaterKg
        self.bmi = scan.bmi
        self.bmr = scan.bmr
        self.visceralFatLevel = scan.visceralFatLevel
        self.inbodyScore = scan.inbodyScore
        self.source = "inbody"
        self.deviceModel = scan.deviceModel
        self.measuredAt = scan.measuredAt
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case weightKg = "weight_kg"
        case weightLbs = "weight_lbs"
        case bodyFatPercentage = "body_fat_percentage"
        case bodyFatMassKg = "body_fat_mass_kg"
        case skeletalMuscleMassKg = "skeletal_muscle_mass_kg"
        case leanBodyMassKg = "lean_body_mass_kg"
        case bodyWaterKg = "body_water_kg"
        case bmi
        case bmr
        case visceralFatLevel = "visceral_fat_level"
        case inbodyScore = "inbody_score"
        case source
        case deviceModel = "device_model"
        case measuredAt = "measured_at"
    }
}

struct BodyCompositionGoal: Codable {
    let targetWeightKg: Double?
    let targetWeightLbs: Double?
    let targetBodyFatPercentage: Double?
    let targetMuscleMassKg: Double?
    let primaryGoal: BodyCompositionGoalType
    let targetDate: Date?
    
    enum CodingKeys: String, CodingKey {
        case targetWeightKg = "target_weight_kg"
        case targetWeightLbs = "target_weight_lbs"
        case targetBodyFatPercentage = "target_body_fat_percentage"
        case targetMuscleMassKg = "target_muscle_mass_kg"
        case primaryGoal = "primary_goal"
        case targetDate = "target_date"
    }
}

enum BodyCompositionGoalType: String, Codable, CaseIterable {
    case loseFat = "lose_fat"
    case gainMuscle = "gain_muscle"
    case recomposition = "recomposition"
    case maintain = "maintain"
    
    var displayName: String {
        switch self {
        case .loseFat: return "Lose Fat"
        case .gainMuscle: return "Gain Muscle"
        case .recomposition: return "Body Recomposition"
        case .maintain: return "Maintain"
        }
    }
    
    var description: String {
        switch self {
        case .loseFat: return "Focus on reducing body fat while preserving muscle"
        case .gainMuscle: return "Focus on building muscle mass"
        case .recomposition: return "Simultaneously lose fat and gain muscle"
        case .maintain: return "Maintain current body composition"
        }
    }
}

struct BodyCompositionStats: Codable {
    let currentBodyFat: Double?
    let currentMuscleMass: Double?
    let currentWeight: Double?
    let startingBodyFat: Double?
    let startingMuscleMass: Double?
    let totalBodyFatChange: Double?
    let totalMuscleGain: Double?
    let monthlyBodyFatChange: Double?
    let lowestBodyFat: Double?
    let highestMuscleMass: Double?
    let bestInbodyScore: Int?
    let averageBodyFat: Double?
    let averageMuscleMass: Double?
    let totalScans: Int
    let lastScanDate: String?
    
    enum CodingKeys: String, CodingKey {
        case currentBodyFat = "current_body_fat"
        case currentMuscleMass = "current_muscle_mass"
        case currentWeight = "current_weight"
        case startingBodyFat = "starting_body_fat"
        case startingMuscleMass = "starting_muscle_mass"
        case totalBodyFatChange = "total_body_fat_change"
        case totalMuscleGain = "total_muscle_gain"
        case monthlyBodyFatChange = "monthly_body_fat_change"
        case lowestBodyFat = "lowest_body_fat"
        case highestMuscleMass = "highest_muscle_mass"
        case bestInbodyScore = "best_inbody_score"
        case averageBodyFat = "average_body_fat"
        case averageMuscleMass = "average_muscle_mass"
        case totalScans = "total_scans"
        case lastScanDate = "last_scan_date"
    }
}

struct GoalProgress {
    let weightProgress: Double?
    let bodyFatProgress: Double?
    let muscleProgress: Double?
    let primaryGoal: BodyCompositionGoalType
    
    var overallProgress: Double {
        var total: Double = 0
        var count: Double = 0
        
        switch primaryGoal {
        case .loseFat:
            if let bf = bodyFatProgress {
                total += bf * 2  // Weight body fat more heavily
                count += 2
            }
            if let w = weightProgress {
                total += w
                count += 1
            }
        case .gainMuscle:
            if let m = muscleProgress {
                total += m * 2
                count += 2
            }
            if let w = weightProgress {
                total += w
                count += 1
            }
        case .recomposition:
            if let bf = bodyFatProgress { total += bf; count += 1 }
            if let m = muscleProgress { total += m; count += 1 }
        case .maintain:
            // For maintain, being close to 100% is good
            if let bf = bodyFatProgress { total += 100 - abs(bf); count += 1 }
            if let m = muscleProgress { total += 100 - abs(m); count += 1 }
        }
        
        return count > 0 ? min(max(total / count, 0), 100) : 0
    }
}

struct BodyCompositionInsight: Identifiable {
    let id = UUID()
    let type: BodyCompInsightType
    let title: String
    let message: String
    let actionText: String?
    
    enum BodyCompInsightType {
        case success
        case warning
        case info
        
        var color: Color {
            switch self {
            case .success: return .green
            case .warning: return .orange
            case .info: return .blue
            }
        }
        
        var icon: String {
            switch self {
            case .success: return "checkmark.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .info: return "info.circle.fill"
            }
        }
    }
}

// MARK: - Supporting Enums

enum ActivityLevel: String, CaseIterable {
    case sedentary = "Sedentary"
    case light = "Lightly Active"
    case moderate = "Moderately Active"
    case active = "Active"
    case veryActive = "Very Active"
    
    var multiplier: Double {
        switch self {
        case .sedentary: return 1.2
        case .light: return 1.375
        case .moderate: return 1.55
        case .active: return 1.725
        case .veryActive: return 1.9
        }
    }
    
    var description: String {
        switch self {
        case .sedentary: return "Little or no exercise, desk job"
        case .light: return "Light exercise 1-3 days/week"
        case .moderate: return "Moderate exercise 3-5 days/week"
        case .active: return "Hard exercise 6-7 days/week"
        case .veryActive: return "Very hard exercise, physical job"
        }
    }
}

enum CalorieGoal: String, CaseIterable {
    case aggressiveLose = "Aggressive Loss"
    case lose = "Fat Loss"
    case maintain = "Maintain"
    case gain = "Lean Gain"
    case aggressiveGain = "Aggressive Gain"
    
    var description: String {
        switch self {
        case .aggressiveLose: return "25% calorie deficit"
        case .lose: return "20% calorie deficit"
        case .maintain: return "Maintenance calories"
        case .gain: return "15% calorie surplus"
        case .aggressiveGain: return "20% calorie surplus"
        }
    }
}

// MARK: - Errors

enum BodyCompositionError: LocalizedError {
    case notAuthenticated
    case invalidData
    case saveFailed
    
    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "You must be logged in to track body composition"
        case .invalidData:
            return "Invalid body composition data"
        case .saveFailed:
            return "Failed to save body composition data"
        }
    }
}
