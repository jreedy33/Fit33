import Foundation
import SwiftUI

// MARK: - Smart Insight Engine
/// Generates personalized, data-driven insights across nutrition, workouts, hydration, and activity

class SmartInsightEngine: ObservableObject {
    static let shared = SmartInsightEngine()
    
    @Published var todaysInsights: [SmartInsight] = []
    @Published var motivationalMessage: String = ""
    
    private init() {}
    
    // MARK: - Insight Model
    
    struct SmartInsight: Identifiable {
        let id = UUID()
        let category: SmartInsightCategory
        let type: SmartInsightType
        let icon: String
        let title: String
        let message: String
        let color: Color
        let priority: Int // 1 = highest
        let actionable: Bool
        let celebratory: Bool
        
        enum SmartInsightCategory: String {
            case nutrition = "Nutrition"
            case workout = "Workout"
            case hydration = "Hydration"
            case activity = "Activity"
            case recovery = "Recovery"
            case streak = "Streak"
            case pr = "Personal Record"
            case trend = "Trend"
            case motivation = "Motivation"
        }
        
        enum SmartInsightType: String {
            case achievement   // Something accomplished
            case encouragement // Motivational
            case suggestion   // Actionable advice
            case warning      // Something to watch
            case trend        // Pattern detected
            case milestone    // Milestone reached
            case comparison   // vs. previous period
            case tip          // General tip
        }
    }
    
    // MARK: - Generate All Insights
    
    func generateDailyInsights(
        // Nutrition
        calories: Int, calorieGoal: Int,
        protein: Int, proteinGoal: Int,
        fat: Int, fatGoal: Int,
        carbs: Int, carbsGoal: Int,
        mealsLogged: Int,
        weeklyCalorieDaysMet: Int,
        weeklyProteinDaysMet: Int,
        // Hydration
        waterIntake: Int, waterGoal: Int,
        hydrationStreak: Int,
        weeklyHydrationDaysMet: Int,
        // Activity
        steps: Int, stepGoal: Int,
        weeklyAvgSteps: Int,
        // Workout
        workoutsThisWeek: Int,
        currentStreak: Int,
        lastWorkoutDate: Date?,
        recentPRs: [String],
        // Recovery
        musclesRecovering: [String],
        fullyRecoveredMuscles: [String]
    ) -> [SmartInsight] {
        
        var insights: [SmartInsight] = []
        let hour = Calendar.current.component(.hour, from: Date())
        let dayOfWeek = Calendar.current.component(.weekday, from: Date())
        let isWeekend = dayOfWeek == 1 || dayOfWeek == 7
        
        // ============================================
        // MARK: - Nutrition Insights
        // ============================================
        
        let calorieProgress = calorieGoal > 0 ? Double(calories) / Double(calorieGoal) : 0
        let proteinProgress = proteinGoal > 0 ? Double(protein) / Double(proteinGoal) : 0
        let fatProgress = fatGoal > 0 ? Double(fat) / Double(fatGoal) : 0
        
        // Perfect calorie day
        if calorieProgress >= 0.95 && calorieProgress <= 1.05 {
            insights.append(SmartInsight(
                category: .nutrition,
                type: .achievement,
                icon: "target",
                title: "Bullseye! 🎯",
                message: "You hit your calorie target perfectly today. That's precision nutrition!",
                color: .green,
                priority: 1,
                actionable: false,
                celebratory: true
            ))
        }
        
        // Protein champion
        if proteinProgress >= 1.0 {
            let overAmount = protein - proteinGoal
            if overAmount > 20 {
                insights.append(SmartInsight(
                    category: .nutrition,
                    type: .achievement,
                    icon: "bolt.fill",
                    title: "Protein Powerhouse! 💪",
                    message: "You crushed your protein goal by \(overAmount)g. Your muscles are thanking you!",
                    color: .blue,
                    priority: 2,
                    actionable: false,
                    celebratory: true
                ))
            } else {
                insights.append(SmartInsight(
                    category: .nutrition,
                    type: .achievement,
                    icon: "checkmark.seal.fill",
                    title: "Protein Goal Met!",
                    message: "Nice work hitting \(protein)g of protein. Muscle recovery: activated! 🔥",
                    color: .blue,
                    priority: 3,
                    actionable: false,
                    celebratory: true
                ))
            }
        }
        
        // Protein deficit warning with specific suggestions
        if proteinProgress < 0.6 && hour >= 15 {
            let remaining = proteinGoal - protein
            let suggestions = [
                "a chicken breast (\(remaining > 30 ? "~30g" : "covers it!"))",
                "Greek yogurt with nuts (~20g)",
                "a protein shake (~25g)",
                "salmon fillet (~25g)",
                "eggs and cottage cheese (~25g)"
            ]
            insights.append(SmartInsight(
                category: .nutrition,
                type: .suggestion,
                icon: "arrow.up.circle.fill",
                title: "Protein Check-In",
                message: "You need \(remaining)g more protein today. Try \(suggestions.randomElement()!).",
                color: .orange,
                priority: 2,
                actionable: true,
                celebratory: false
            ))
        }
        
        // Calorie pacing insight
        if hour < 14 && calorieProgress > 0.7 {
            insights.append(SmartInsight(
                category: .nutrition,
                type: .warning,
                icon: "gauge.with.dots.needle.33percent",
                title: "Front-Loading Alert",
                message: "You've eaten \(Int(calorieProgress * 100))% of calories before lunch. Save room for dinner!",
                color: .orange,
                priority: 3,
                actionable: true,
                celebratory: false
            ))
        }
        
        // Under-eating warning
        if hour >= 18 && calorieProgress < 0.5 {
            insights.append(SmartInsight(
                category: .nutrition,
                type: .warning,
                icon: "exclamationmark.triangle.fill",
                title: "Fuel Up!",
                message: "Only \(calories) calories logged today. Under-eating slows your metabolism.",
                color: .red,
                priority: 1,
                actionable: true,
                celebratory: false
            ))
        }
        
        // Weekly consistency celebration
        if weeklyCalorieDaysMet >= 5 {
            insights.append(SmartInsight(
                category: .nutrition,
                type: .milestone,
                icon: "star.fill",
                title: "Consistency Champion! 🏆",
                message: "You've hit your calorie target \(weeklyCalorieDaysMet)/7 days this week. That's how results happen!",
                color: .yellow,
                priority: 2,
                actionable: false,
                celebratory: true
            ))
        }
        
        // Weekly protein consistency
        if weeklyProteinDaysMet >= 6 {
            insights.append(SmartInsight(
                category: .nutrition,
                type: .milestone,
                icon: "medal.fill",
                title: "Protein Pro! 🥇",
                message: "You've hit protein goals \(weeklyProteinDaysMet) days this week. Gainz incoming!",
                color: .blue,
                priority: 2,
                actionable: false,
                celebratory: true
            ))
        }
        
        // Fat balance insight
        if fatProgress > 1.3 {
            insights.append(SmartInsight(
                category: .nutrition,
                type: .suggestion,
                icon: "chart.bar.xaxis.ascending",
                title: "Fat Check",
                message: "Fat intake is \(Int(fatProgress * 100))% of goal. Try leaner protein sources tomorrow.",
                color: .purple,
                priority: 4,
                actionable: true,
                celebratory: false
            ))
        } else if fatProgress >= 0.8 && fatProgress <= 1.1 {
            insights.append(SmartInsight(
                category: .nutrition,
                type: .achievement,
                icon: "heart.fill",
                title: "Heart-Healthy! ❤️",
                message: "Your fat intake is perfectly balanced for cardiovascular health.",
                color: .pink,
                priority: 4,
                actionable: false,
                celebratory: true
            ))
        }
        
        // Meal timing suggestions
        if mealsLogged == 0 && hour >= 10 {
            insights.append(SmartInsight(
                category: .nutrition,
                type: .suggestion,
                icon: "sunrise.fill",
                title: "Start Your Day Right",
                message: "No meals logged yet! Eating breakfast kickstarts your metabolism.",
                color: .orange,
                priority: 2,
                actionable: true,
                celebratory: false
            ))
        } else if mealsLogged >= 4 {
            insights.append(SmartInsight(
                category: .nutrition,
                type: .achievement,
                icon: "fork.knife.circle.fill",
                title: "Meal Master! 🍽️",
                message: "You've logged \(mealsLogged) meals today. Consistent tracking = consistent results!",
                color: .green,
                priority: 4,
                actionable: false,
                celebratory: true
            ))
        }
        
        // ============================================
        // MARK: - Hydration Insights
        // ============================================
        
        let waterProgress = waterGoal > 0 ? Double(waterIntake) / Double(waterGoal) : 0
        
        // Perfect hydration
        if waterProgress >= 1.0 {
            insights.append(SmartInsight(
                category: .hydration,
                type: .achievement,
                icon: "drop.fill",
                title: "Hydration Hero! 💧",
                message: "You crushed your water goal! Proper hydration boosts energy by up to 20%.",
                color: .cyan,
                priority: 2,
                actionable: false,
                celebratory: true
            ))
        }
        
        // Hydration streak
        if hydrationStreak >= 7 {
            insights.append(SmartInsight(
                category: .streak,
                type: .milestone,
                icon: "flame.fill",
                title: "\(hydrationStreak)-Day Hydration Streak! 🔥",
                message: "You've hit your water goal \(hydrationStreak) days in a row. Your skin and energy levels love you!",
                color: .orange,
                priority: 1,
                actionable: false,
                celebratory: true
            ))
        } else if hydrationStreak >= 3 {
            insights.append(SmartInsight(
                category: .streak,
                type: .encouragement,
                icon: "flame",
                title: "Hydration Streak: \(hydrationStreak) Days!",
                message: "Keep it going! You're building a powerful habit.",
                color: .orange,
                priority: 3,
                actionable: false,
                celebratory: true
            ))
        }
        
        // Time-based hydration reminders
        if waterProgress < 0.3 && hour >= 12 {
            let remaining = waterGoal - waterIntake
            insights.append(SmartInsight(
                category: .hydration,
                type: .warning,
                icon: "drop.triangle.fill",
                title: "Dehydration Alert! ⚠️",
                message: "Only \(Int(waterProgress * 100))% of water goal. Drink \(remaining)ml to catch up!",
                color: .red,
                priority: 1,
                actionable: true,
                celebratory: false
            ))
        } else if waterProgress >= 0.5 && waterProgress < 0.75 && hour >= 15 {
            insights.append(SmartInsight(
                category: .hydration,
                type: .encouragement,
                icon: "drop.halffull",
                title: "Halfway There!",
                message: "Good hydration progress! A few more glasses and you'll hit your goal.",
                color: .cyan,
                priority: 4,
                actionable: true,
                celebratory: false
            ))
        }
        
        // Weekly hydration consistency
        if weeklyHydrationDaysMet >= 5 {
            insights.append(SmartInsight(
                category: .hydration,
                type: .trend,
                icon: "chart.line.uptrend.xyaxis",
                title: "Hydration Trend: Excellent! 📈",
                message: "You've met water goals \(weeklyHydrationDaysMet)/7 days. Your body composition will thank you!",
                color: .cyan,
                priority: 3,
                actionable: false,
                celebratory: true
            ))
        }
        
        // ============================================
        // MARK: - Activity & Steps Insights
        // ============================================
        
        let stepProgress = stepGoal > 0 ? Double(steps) / Double(stepGoal) : 0
        
        // Step goal achievement
        if stepProgress >= 1.0 {
            let extraSteps = steps - stepGoal
            if extraSteps > 2000 {
                insights.append(SmartInsight(
                    category: .activity,
                    type: .achievement,
                    icon: "figure.walk.motion",
                    title: "Overachiever! 🚀",
                    message: "You didn't just hit your step goal—you crushed it by \(extraSteps.formatted()) steps!",
                    color: .green,
                    priority: 1,
                    actionable: false,
                    celebratory: true
                ))
            } else {
                insights.append(SmartInsight(
                    category: .activity,
                    type: .achievement,
                    icon: "figure.walk",
                    title: "Step Goal Complete! 👟",
                    message: "\(steps.formatted()) steps today! That's approximately \(steps / 1300) miles walked.",
                    color: .green,
                    priority: 2,
                    actionable: false,
                    celebratory: true
                ))
            }
        }
        
        // Step pacing
        if hour >= 12 && hour < 18 && stepProgress < 0.4 {
            let neededPace = (stepGoal - steps) / max(1, (22 - hour))
            insights.append(SmartInsight(
                category: .activity,
                type: .suggestion,
                icon: "shoeprints.fill",
                title: "Step It Up!",
                message: "To hit your goal, aim for ~\(neededPace.formatted()) steps per hour. A quick walk helps!",
                color: .teal,
                priority: 3,
                actionable: true,
                celebratory: false
            ))
        }
        
        // Above weekly average
        if weeklyAvgSteps > 0 && steps > Int(Double(weeklyAvgSteps) * 1.2) {
            insights.append(SmartInsight(
                category: .activity,
                type: .comparison,
                icon: "arrow.up.right",
                title: "Above Average Day! 📊",
                message: "You're \(Int(Double(steps - weeklyAvgSteps) / Double(weeklyAvgSteps) * 100))% above your weekly average. Keep moving!",
                color: .green,
                priority: 4,
                actionable: false,
                celebratory: true
            ))
        }
        
        // Weekend warrior
        if isWeekend && steps > stepGoal {
            insights.append(SmartInsight(
                category: .activity,
                type: .achievement,
                icon: "star.circle.fill",
                title: "Weekend Warrior! ⚔️",
                message: "Hitting step goals on weekends shows real commitment. You're built different!",
                color: .purple,
                priority: 3,
                actionable: false,
                celebratory: true
            ))
        }
        
        // ============================================
        // MARK: - Workout & Strength Insights
        // ============================================
        
        // Workout streak celebration
        if currentStreak >= 7 {
            insights.append(SmartInsight(
                category: .streak,
                type: .milestone,
                icon: "flame.fill",
                title: "\(currentStreak)-Day Workout Streak! 🔥🔥🔥",
                message: "A full week of consistency! You're in the top 10% of people who start a fitness journey.",
                color: .red,
                priority: 1,
                actionable: false,
                celebratory: true
            ))
        } else if currentStreak >= 3 {
            insights.append(SmartInsight(
                category: .streak,
                type: .encouragement,
                icon: "flame",
                title: "Streak Building: \(currentStreak) Days! 🔥",
                message: "You're creating a habit! It takes 21 days to form one—keep going!",
                color: .orange,
                priority: 2,
                actionable: false,
                celebratory: true
            ))
        }
        
        // Weekly workout target
        if workoutsThisWeek >= 5 {
            insights.append(SmartInsight(
                category: .workout,
                type: .achievement,
                icon: "trophy.fill",
                title: "Beast Week! 💪",
                message: "\(workoutsThisWeek) workouts this week! You're outworking 95% of gym-goers.",
                color: .yellow,
                priority: 1,
                actionable: false,
                celebratory: true
            ))
        } else if workoutsThisWeek >= 3 {
            insights.append(SmartInsight(
                category: .workout,
                type: .achievement,
                icon: "dumbbell.fill",
                title: "Solid Week! 💪",
                message: "\(workoutsThisWeek) workouts logged. You're building something great!",
                color: .orange,
                priority: 3,
                actionable: false,
                celebratory: true
            ))
        }
        
        // Recent PR celebrations
        if !recentPRs.isEmpty {
            let prExercise = recentPRs.first ?? "an exercise"
            insights.append(SmartInsight(
                category: .pr,
                type: .milestone,
                icon: "crown.fill",
                title: "New Personal Record! 👑",
                message: "You set a new PR on \(prExercise)! Your hard work is literally paying off.",
                color: .yellow,
                priority: 1,
                actionable: false,
                celebratory: true
            ))
        }
        
        // Rest day suggestion
        if let lastWorkout = lastWorkoutDate {
            let daysSinceWorkout = Calendar.current.dateComponents([.day], from: lastWorkout, to: Date()).day ?? 0
            if daysSinceWorkout == 0 && workoutsThisWeek >= 4 {
                insights.append(SmartInsight(
                    category: .recovery,
                    type: .suggestion,
                    icon: "bed.double.fill",
                    title: "Consider Rest Tomorrow",
                    message: "You've trained hard this week. Recovery is when muscles actually grow!",
                    color: .purple,
                    priority: 4,
                    actionable: true,
                    celebratory: false
                ))
            } else if daysSinceWorkout >= 3 {
                insights.append(SmartInsight(
                    category: .workout,
                    type: .encouragement,
                    icon: "figure.strengthtraining.traditional",
                    title: "Time to Train! 🏋️",
                    message: "It's been \(daysSinceWorkout) days since your last workout. Your body is recovered and ready!",
                    color: .green,
                    priority: 2,
                    actionable: true,
                    celebratory: false
                ))
            }
        }
        
        // ============================================
        // MARK: - Recovery Insights
        // ============================================
        
        if !musclesRecovering.isEmpty && musclesRecovering.count <= 3 {
            let muscleList = musclesRecovering.prefix(3).joined(separator: ", ")
            insights.append(SmartInsight(
                category: .recovery,
                type: .tip,
                icon: "bandage.fill",
                title: "Recovery Status",
                message: "\(muscleList) still recovering. Perfect day for \(fullyRecoveredMuscles.first ?? "other muscle groups")!",
                color: .purple,
                priority: 4,
                actionable: true,
                celebratory: false
            ))
        }
        
        if fullyRecoveredMuscles.count >= 5 {
            insights.append(SmartInsight(
                category: .recovery,
                type: .encouragement,
                icon: "bolt.heart.fill",
                title: "Fully Charged! ⚡",
                message: "Most muscle groups are recovered. You're primed for a great workout!",
                color: .green,
                priority: 3,
                actionable: true,
                celebratory: true
            ))
        }
        
        // ============================================
        // MARK: - Time-Based Motivational Insights
        // ============================================
        
        // Monday motivation
        if dayOfWeek == 2 {
            insights.append(SmartInsight(
                category: .motivation,
                type: .encouragement,
                icon: "sunrise.fill",
                title: "Monday Momentum! 🚀",
                message: "New week, new opportunities. The effort you put in today sets the tone!",
                color: .orange,
                priority: 5,
                actionable: false,
                celebratory: false
            ))
        }
        
        // Friday celebration
        if dayOfWeek == 6 && workoutsThisWeek >= 3 {
            insights.append(SmartInsight(
                category: .motivation,
                type: .encouragement,
                icon: "party.popper.fill",
                title: "Strong Week! 🎉",
                message: "You showed up \(workoutsThisWeek) times this week. Enjoy your weekend—you earned it!",
                color: .purple,
                priority: 3,
                actionable: false,
                celebratory: true
            ))
        }
        
        // Evening wind-down
        if hour >= 20 {
            insights.append(SmartInsight(
                category: .tip,
                type: .tip,
                icon: "moon.stars.fill",
                title: "Evening Tip 🌙",
                message: "Quality sleep = quality gains. Try to wind down—your muscles grow while you rest!",
                color: .indigo,
                priority: 5,
                actionable: true,
                celebratory: false
            ))
        }
        
        // Sort by priority and return top insights
        return insights.sorted { $0.priority < $1.priority }
    }
    
    // MARK: - Generate Motivational Message
    
    func generateMotivationalMessage(
        nutritionScore: Int,
        currentStreak: Int,
        workoutsThisWeek: Int,
        recentPR: Bool
    ) -> String {
        
        let hour = Calendar.current.component(.hour, from: Date())
        let dayOfWeek = Calendar.current.component(.weekday, from: Date())
        
        // Priority: Recent PR > High Score > Streak > Time-based
        
        if recentPR {
            return [
                "🏆 You just set a personal record! That's what consistent effort looks like.",
                "👑 New PR unlocked! You're literally stronger than you were before.",
                "💪 Breaking records and taking names! Keep this energy going.",
                "🔥 PR alert! Proof that hard work pays off.",
            ].randomElement()!
        }
        
        if nutritionScore >= 85 {
            return [
                "🌟 Nutrition game is ON POINT today!",
                "💯 You're nailing your macros! This is how champions eat.",
                "🎯 Elite-level nutrition tracking today. Results incoming!",
                "✨ Your discipline is showing—perfect nutrition day!",
            ].randomElement()!
        }
        
        if currentStreak >= 7 {
            return [
                "🔥 Week-long streak! You're in the top 5% of people who actually follow through.",
                "💪 \(currentStreak) days strong! Consistency beats intensity every time.",
                "🚀 Your streak is proof that motivation follows action, not the other way around.",
                "⭐ \(currentStreak)-day warrior! You've made fitness a non-negotiable.",
            ].randomElement()!
        }
        
        if currentStreak >= 3 {
            return [
                "🔥 Streak building! 3+ days means you're forming a habit.",
                "💪 Keep showing up! You're \(currentStreak) days into something special.",
                "✨ \(currentStreak) days in—momentum is on your side now!",
            ].randomElement()!
        }
        
        if workoutsThisWeek >= 4 {
            return [
                "💪 \(workoutsThisWeek) workouts this week! You're outworking most people.",
                "🏋️ Consistent weeks build extraordinary results. Keep stacking!",
                "🔥 This week's effort is next month's results!",
            ].randomElement()!
        }
        
        // Time-based defaults
        if hour < 10 {
            return [
                "☀️ Morning champions set the day's tone. Let's make it count!",
                "🌅 Early bird energy! The best time to invest in yourself is now.",
                "💪 Rise and grind! Your future self will thank you.",
            ].randomElement()!
        } else if hour < 14 {
            return [
                "🎯 Midday check-in: You're doing great. Keep the momentum!",
                "💪 Afternoon power! Stay focused on your goals.",
                "✨ Half the day down, and you're crushing it!",
            ].randomElement()!
        } else if hour < 18 {
            return [
                "⚡ Afternoon energy! Perfect time for a workout or walk.",
                "💪 The day's not over—there's still time to level up!",
                "🎯 Stay locked in. Evening wins matter too!",
            ].randomElement()!
        } else {
            return [
                "🌙 Evening reflection: Every healthy choice today is an investment.",
                "✨ Wrapping up the day? You showed up—that's what matters.",
                "💪 Another day of progress in the books. Rest well!",
            ].randomElement()!
        }
    }
    
    /// Generate workout-specific insight
    func generateWorkoutInsight(
        exerciseName: String,
        currentWeight: Double,
        previousBest: Double,
        reps: Int
    ) -> String? {
        
        if currentWeight > previousBest {
            return "🔥 New weight PR on \(exerciseName)! You just lifted \(Int(currentWeight - previousBest)) lbs more than ever!"
        }
        
        if currentWeight >= previousBest * 0.95 {
            return "💪 Working at \(Int(currentWeight / previousBest * 100))% of your best on \(exerciseName). Strong effort!"
        }
        
        if reps >= 12 {
            return "📈 \(reps) reps at this weight? Time to go heavier next time!"
        }
        
        return nil
    }
    
    /// Generate post-workout insight
    func generatePostWorkoutInsight(
        workoutDuration: Int,
        exerciseCount: Int,
        totalVolume: Double,
        prsHit: Int
    ) -> String {
        
        if prsHit > 0 {
            return "🏆 Incredible session! You hit \(prsHit) personal record\(prsHit > 1 ? "s" : "")!"
        }
        
        if workoutDuration >= 60 {
            return "💪 \(workoutDuration) minutes of pure dedication. That's elite commitment!"
        }
        
        if exerciseCount >= 8 {
            return "🔥 \(exerciseCount) exercises completed! Comprehensive workout for maximum gains."
        }
        
        if totalVolume > 10000 {
            return "📊 Over \(Int(totalVolume).formatted()) lbs of total volume! Your muscles felt that."
        }
        
        return "✅ Another workout in the books. Consistency is your superpower!"
    }
}
