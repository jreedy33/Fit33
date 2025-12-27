import Foundation
import Supabase

// MARK: - Exercise Performance Service
// Fetches performance history to enable progressive overload recommendations

@MainActor
class ExercisePerformanceService {
    static let shared = ExercisePerformanceService()
    
    private init() {}
    
    private var supabase: SupabaseClient {
        SupabaseManager.shared.supabaseClient
    }
    
    // MARK: - Data Models
    
    struct PerformanceData: Codable {
        let exerciseName: String
        let workoutDate: Date
        let bestSetWeight: Double
        let bestSetReps: Int
        let totalVolume: Double
        let oneRepMaxEstimate: Double?
        
        var suggestedNextWeight: Double {
            // Progressive overload: suggest 2.5-5 lbs more if last workout went well
            // If reps were high (10+), suggest more weight
            // If reps were low (< 5), keep same or reduce
            if bestSetReps >= 10 {
                return bestSetWeight + 5.0
            } else if bestSetReps >= 6 {
                return bestSetWeight + 2.5
            } else {
                return bestSetWeight // Keep same weight
            }
        }
    }
    
    // MARK: - Fetch Last Performance
    
    /// Get the most recent performance data for an exercise
    func getLastPerformance(for exerciseName: String) async -> PerformanceData? {
        guard let userId = SupabaseManager.shared.currentUser?.id else {
            return nil
        }
        
        do {
            struct DTO: Decodable {
                let exercise_name: String
                let workout_date: String
                let best_set_weight: Double
                let best_set_reps: Int
                let total_volume: Double
                let one_rep_max_estimate: Double?
            }
            
            let dtos: [DTO] = try await supabase
                .from("exercise_performance_history")
                .select()
                .eq("user_id", value: userId.uuidString)
                .eq("exercise_name", value: exerciseName)
                .order("workout_date", ascending: false)
                .limit(1)
                .execute()
                .value
            
            guard let dto = dtos.first else {
                return nil
            }
            
            let dateFormatter = ISO8601DateFormatter()
            guard let date = dateFormatter.date(from: dto.workout_date) else {
                return nil
            }
            
            return PerformanceData(
                exerciseName: dto.exercise_name,
                workoutDate: date,
                bestSetWeight: dto.best_set_weight,
                bestSetReps: dto.best_set_reps,
                totalVolume: dto.total_volume,
                oneRepMaxEstimate: dto.one_rep_max_estimate
            )
        } catch {
            print("❌ Error fetching performance for \(exerciseName): \(error)")
            return nil
        }
    }
    
    /// Get performance history for multiple exercises at once
    func getPerformanceHistory(for exerciseNames: [String], limit: Int = 1) async -> [String: [PerformanceData]] {
        guard let userId = SupabaseManager.shared.currentUser?.id else {
            return [:]
        }
        
        do {
            struct DTO: Decodable {
                let exercise_name: String
                let workout_date: String
                let best_set_weight: Double
                let best_set_reps: Int
                let total_volume: Double
                let one_rep_max_estimate: Double?
            }
            
            let dtos: [DTO] = try await supabase
                .from("exercise_performance_history")
                .select()
                .eq("user_id", value: userId.uuidString)
                .in("exercise_name", values: exerciseNames)
                .order("workout_date", ascending: false)
                .execute()
                .value
            
            // Group by exercise name
            var result: [String: [PerformanceData]] = [:]
            let dateFormatter = ISO8601DateFormatter()
            
            for dto in dtos {
                guard let date = dateFormatter.date(from: dto.workout_date) else {
                    continue
                }
                
                let data = PerformanceData(
                    exerciseName: dto.exercise_name,
                    workoutDate: date,
                    bestSetWeight: dto.best_set_weight,
                    bestSetReps: dto.best_set_reps,
                    totalVolume: dto.total_volume,
                    oneRepMaxEstimate: dto.one_rep_max_estimate
                )
                
                result[dto.exercise_name, default: []].append(data)
            }
            
            // Limit each exercise to specified number of entries
            for (key, value) in result {
                result[key] = Array(value.prefix(limit))
            }
            
            return result
        } catch {
            print("❌ Error fetching performance history: \(error)")
            return [:]
        }
    }
    
    /// Get equipment proficiency scores
    func getEquipmentProficiency() async -> [String: Int] {
        guard let userId = SupabaseManager.shared.currentUser?.id else {
            return [:]
        }
        
        do {
            struct DTO: Decodable {
                let equipment_type: String
                let times_used: Int
            }
            
            let dtos: [DTO] = try await supabase
                .from("equipment_proficiency")
                .select("equipment_type, times_used")
                .eq("user_id", value: userId.uuidString)
                .order("times_used", ascending: false)
                .execute()
                .value
            
            return Dictionary(uniqueKeysWithValues: dtos.map { ($0.equipment_type, $0.times_used) })
        } catch {
            print("❌ Error fetching equipment proficiency: \(error)")
            return [:]
        }
    }
    
    /// Get workout temporal patterns (best days/times)
    func getWorkoutPatterns() async -> WorkoutPatterns {
        guard let userId = SupabaseManager.shared.currentUser?.id else {
            return WorkoutPatterns(bestDays: [], bestTimeRange: nil, avgWorkoutsPerWeek: 0)
        }
        
        do {
            struct DTO: Decodable {
                let day_of_week: String
                let workout_time: String
            }
            
            let dtos: [DTO] = try await supabase
                .from("workout_context")
                .select("day_of_week, workout_time")
                .eq("user_id", value: userId.uuidString)
                .execute()
                .value
            
            // Count workouts by day
            var dayCounts: [String: Int] = [:]
            for dto in dtos {
                dayCounts[dto.day_of_week, default: 0] += 1
            }
            
            // Sort by count
            let bestDays = dayCounts.sorted { $0.value > $1.value }.prefix(3).map { $0.key }
            
            // Determine most common time range
            let hours = dtos.compactMap { dto -> Int? in
                let components = dto.workout_time.split(separator: ":")
                return Int(components.first ?? "0")
            }
            
            let avgHour = hours.isEmpty ? 0 : hours.reduce(0, +) / hours.count
            let timeRange: String
            if avgHour < 9 {
                timeRange = "Early Morning (6-9 AM)"
            } else if avgHour < 12 {
                timeRange = "Mid Morning (9-12 PM)"
            } else if avgHour < 15 {
                timeRange = "Early Afternoon (12-3 PM)"
            } else if avgHour < 18 {
                timeRange = "Late Afternoon (3-6 PM)"
            } else {
                timeRange = "Evening (6+ PM)"
            }
            
            return WorkoutPatterns(
                bestDays: Array(bestDays),
                bestTimeRange: timeRange,
                avgWorkoutsPerWeek: Double(dtos.count) / 4.0 // Rough estimate
            )
        } catch {
            print("❌ Error fetching workout patterns: \(error)")
            return WorkoutPatterns(bestDays: [], bestTimeRange: nil, avgWorkoutsPerWeek: 0)
        }
    }
    
    struct WorkoutPatterns {
        let bestDays: [String]
        let bestTimeRange: String?
        let avgWorkoutsPerWeek: Double
    }
}

