import SwiftUI


// MARK: - Smart Daily Summary Widget
struct SmartDailySummaryWidget: View {
    @Environment(\.colorScheme) private var colorScheme
    
    let consumedCalories: Int
    let calorieGoal: Int
    let consumedProtein: Int
    let proteinGoal: Int
    let consumedFat: Int
    let fatGoal: Int
    let mealsLogged: Int
    let waterIntake: Int
    let waterGoal: Int
    
    // Computed insights
    private var calorieProgress: Double {
        guard calorieGoal > 0 else { return 0 }
        return Double(consumedCalories) / Double(calorieGoal)
    }
    
    private var proteinProgress: Double {
        guard proteinGoal > 0 else { return 0 }
        return Double(consumedProtein) / Double(proteinGoal)
    }
    
    private var fatProgress: Double {
        guard fatGoal > 0 else { return 0 }
        return Double(consumedFat) / Double(fatGoal)
    }
    
    private var waterProgress: Double {
        guard waterGoal > 0 else { return 0 }
        return Double(waterIntake) / Double(waterGoal)
    }
    
    private var nutritionScore: Int {
        var score = 0
        
        // Calorie accuracy (max 30 points) - best if within 10% of goal
        let calorieDiff = abs(calorieProgress - 1.0)
        if calorieDiff < 0.1 {
            score += 30
        } else if calorieDiff < 0.2 {
            score += 20
        } else if calorieDiff < 0.3 {
            score += 10
        }
        
        // Protein (max 25 points)
        if proteinProgress >= 1.0 {
            score += 25
        } else if proteinProgress >= 0.8 {
            score += 20
        } else if proteinProgress >= 0.5 {
            score += 10
        }
        
        // Fat balance (max 20 points) - best if not exceeding
        if fatProgress <= 1.0 && fatProgress >= 0.7 {
            score += 20
        } else if fatProgress <= 1.1 {
            score += 15
        } else if fatProgress <= 1.2 {
            score += 5
        }
        
        // Meal consistency (max 15 points)
        if mealsLogged >= 4 {
            score += 15
        } else if mealsLogged >= 3 {
            score += 10
        } else if mealsLogged >= 2 {
            score += 5
        }
        
        // Hydration (max 10 points)
        if waterProgress >= 1.0 {
            score += 10
        } else if waterProgress >= 0.75 {
            score += 7
        } else if waterProgress >= 0.5 {
            score += 4
        }
        
        return score
    }
    
    private var scoreColor: Color {
        if nutritionScore >= 80 { return .green }
        else if nutritionScore >= 60 { return .yellow }
        else if nutritionScore >= 40 { return .orange }
        else { return .red }
    }
    
    // Smart insights - Enhanced with more variety and personality
    private var positiveInsights: [DailyInsight] {
        var insights: [DailyInsight] = []
        let hour = Calendar.current.component(.hour, from: Date())
        
        // Protein achievements with varied messages
        if proteinProgress >= 1.2 {
            let extraProtein = consumedProtein - proteinGoal
            insights.append(DailyInsight(
                icon: "bolt.fill",
                text: "Protein powerhouse! +\(extraProtein)g over goal. 💪 Your muscles are loving this!",
                color: .blue
            ))
        } else if proteinProgress >= 1.0 {
            let messages = [
                "Protein goal crushed! Your body has the building blocks it needs. 🏗️",
                "Perfect protein intake! Muscle recovery: activated. 💪",
                "\(consumedProtein)g protein logged – your gains thank you! 🎯"
            ]
            insights.append(DailyInsight(
                icon: "checkmark.seal.fill",
                text: messages.randomElement() ?? messages[0],
                color: .green
            ))
        }
        
        // Perfect calorie balance
        if calorieProgress >= 0.95 && calorieProgress <= 1.05 {
            insights.append(DailyInsight(
                icon: "target",
                text: "Bullseye! 🎯 Calories within 5% of goal. That's precision nutrition!",
                color: .green
            ))
        } else if calorieProgress >= 0.9 && calorieProgress <= 1.1 {
            insights.append(DailyInsight(
                icon: "checkmark.circle.fill",
                text: "Calories on target – sustainable eating at its finest!",
                color: .green
            ))
        }
        
        // Hydration celebration
        if waterProgress >= 1.0 {
            let messages = [
                "Hydration hero! 💧 Your cells are swimming in happiness.",
                "Water goal smashed! Proper hydration boosts energy by 20%.",
                "Fully hydrated! Your skin, brain, and muscles thank you. 💧"
            ]
            insights.append(DailyInsight(
                icon: "drop.fill",
                text: messages.randomElement() ?? messages[0],
                color: .cyan
            ))
        }
        
        // Meal consistency
        if mealsLogged >= 4 {
            insights.append(DailyInsight(
                icon: "fork.knife.circle.fill",
                text: "Meal master! 🍽️ \(mealsLogged) meals tracked. Consistency = results!",
                color: .green
            ))
        } else if mealsLogged >= 3 {
            insights.append(DailyInsight(
                icon: "fork.knife",
                text: "Great tracking today! Knowing what you eat is half the battle. 📊",
                color: .green
            ))
        }
        
        // Balanced macros
        if fatProgress <= 1.0 && fatProgress >= 0.7 && proteinProgress >= 0.8 {
            insights.append(DailyInsight(
                icon: "heart.fill",
                text: "Macro balance on point! ❤️ Heart-healthy eating today.",
                color: .pink
            ))
        }
        
        // Early morning wins
        if hour < 10 && mealsLogged >= 1 && waterProgress >= 0.2 {
            insights.append(DailyInsight(
                icon: "sunrise.fill",
                text: "Strong start! Morning nutrition sets the tone for the day. ☀️",
                color: .orange
            ))
        }
        
        // Evening accomplishment
        if hour >= 18 && nutritionScore >= 70 {
            insights.append(DailyInsight(
                icon: "star.fill",
                text: "Solid nutrition day! You showed up for yourself. 🌟",
                color: .yellow
            ))
        }
        
        return insights.prefix(2).map { $0 }
    }
    
    private var improvementSuggestions: [DailyInsight] {
        var suggestions: [DailyInsight] = []
        let hour = Calendar.current.component(.hour, from: Date())
        
        // Protein suggestions with specific food ideas
        if proteinProgress < 0.6 && hour >= 14 {
            let remaining = proteinGoal - consumedProtein
            let quickFixes = ["Greek yogurt (20g)", "chicken breast (30g)", "protein shake (25g)", "3 eggs (18g)", "cottage cheese (14g)"]
            suggestions.append(DailyInsight(
                icon: "arrow.up.circle.fill",
                text: "Need \(remaining)g protein still! Quick fix: \(quickFixes.randomElement() ?? "Greek yogurt (20g)")",
                color: .blue
            ))
        } else if proteinProgress < 0.8 {
            let remaining = proteinGoal - consumedProtein
            suggestions.append(DailyInsight(
                icon: "arrow.up.circle",
                text: "Add \(remaining)g more protein – your muscles are waiting! 💪",
                color: .blue
            ))
        }
        
        // Calorie warnings with context
        if calorieProgress < 0.5 && hour >= 14 {
            suggestions.append(DailyInsight(
                icon: "exclamationmark.triangle.fill",
                text: "Only \(consumedCalories) cal by afternoon! Under-eating slows metabolism. 🍽️",
                color: .red
            ))
        } else if calorieProgress < 0.7 && hour >= 12 {
            suggestions.append(DailyInsight(
                icon: "exclamationmark.triangle",
                text: "Calorie intake low – your body needs fuel to perform! Don't skip meals.",
                color: .orange
            ))
        } else if calorieProgress > 1.2 {
            let over = consumedCalories - calorieGoal
            suggestions.append(DailyInsight(
                icon: "chart.bar.xaxis.ascending",
                text: "\(over) cal over budget. Consider a lighter dinner or evening walk! 🚶",
                color: .orange
            ))
        } else if calorieProgress > 1.1 {
            suggestions.append(DailyInsight(
                icon: "gauge.with.dots.needle.67percent",
                text: "Slightly over goal – no stress! A short walk burns it off. 🚶‍♂️",
                color: .orange
            ))
        }
        
        // Hydration with urgency based on time
        if waterProgress < 0.3 && hour >= 14 {
            let remainingMl = waterGoal - waterIntake
            suggestions.append(DailyInsight(
                icon: "drop.triangle.fill",
                text: "Dehydration alert! ⚠️ Drink \(remainingMl)ml to catch up – your brain needs it!",
                color: .red
            ))
        } else if waterProgress < 0.5 {
            let remainingMl = waterGoal - waterIntake
            suggestions.append(DailyInsight(
                icon: "drop",
                text: "\(remainingMl)ml to go! Keep a water bottle nearby. 💧",
                color: .cyan
            ))
        }
        
        // Fat intake
        if fatProgress > 1.3 {
            let overFat = consumedFat - fatGoal
            suggestions.append(DailyInsight(
                icon: "chart.bar.xaxis",
                text: "\(overFat)g over fat goal. Try grilled over fried tomorrow! 🥗",
                color: .purple
            ))
        } else if fatProgress > 1.15 {
            suggestions.append(DailyInsight(
                icon: "leaf.fill",
                text: "Fat intake elevated – balance with lean proteins at dinner. 🥬",
                color: .purple
            ))
        }
        
        // Meal logging encouragement
        if mealsLogged == 0 && hour >= 11 {
            suggestions.append(DailyInsight(
                icon: "pencil.and.list.clipboard",
                text: "No meals logged yet! Even a quick entry helps you stay aware. 📝",
                color: .gray
            ))
        } else if mealsLogged == 1 && hour >= 15 {
            suggestions.append(DailyInsight(
                icon: "clock.fill",
                text: "Only 1 meal tracked. Logging helps identify patterns! 📊",
                color: .gray
            ))
        }
        
        // Time-specific suggestions
        if hour >= 20 && calorieProgress < 0.85 {
            let remaining = calorieGoal - consumedCalories
            suggestions.append(DailyInsight(
                icon: "moon.fill",
                text: "Room for \(remaining) cal snack! Greek yogurt + berries = perfect evening fuel. 🍇",
                color: .indigo
            ))
        }
        
        return suggestions.prefix(2).map { $0 }
    }
    
    private var dailyTip: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let dayOfWeek = Calendar.current.component(.weekday, from: Date())
        let isWeekend = dayOfWeek == 1 || dayOfWeek == 7
        
        if hour < 10 {
            // Morning tips
            let tips = [
                "💡 Protein at breakfast = less hunger all day. Science says so!",
                "💡 A glass of water before coffee boosts metabolism by 24%.",
                "💡 Morning sunshine + breakfast = better sleep tonight.",
                "💡 Front-loading calories in the AM helps with evening cravings.",
                "💡 Breakfast skippers often overeat 40% more at dinner!"
            ]
            return tips.randomElement()!
        } else if hour < 14 {
            // Midday tips
            let tips = [
                "💡 A 10-min walk after lunch stabilizes blood sugar for hours.",
                "💡 Afternoon protein keeps energy steady – no 3pm crash!",
                "💡 Hydration dips around noon. Time for a water check! 💧",
                "💡 Midday meals with fiber = sustained focus all afternoon.",
                isWeekend ? "💡 Weekend lunches count too! Stay mindful. 🍽️" : "💡 Meal prep saves 6+ hours per week. Future you will thank you!"
            ]
            return tips.randomElement()!
        } else if hour < 18 {
            // Afternoon tips
            let tips = [
                "💡 Afternoon snacks prevent the 'I'm starving' dinner binges.",
                "💡 30g protein snack now = better gym performance later. 💪",
                "💡 Green tea at 3pm: caffeine + antioxidants, minus the jitters.",
                "💡 Stretch break! 5 minutes improves focus and posture.",
                "💡 Planning dinner now? Protein + veggies + complex carbs = 🔥"
            ]
            return tips.randomElement()!
        } else {
            // Evening tips
            let tips = [
                "💡 Stop eating 2-3 hours before bed = better sleep + recovery.",
                "💡 Evening protein (casein) works while you sleep! 🌙",
                "💡 Tomorrow's success starts with tonight's meal prep.",
                "💡 Reflect: What went well today? Build on wins!",
                "💡 Quality sleep = better gains. Your muscles grow at rest! 😴",
                "💡 Herbal tea before bed aids digestion and relaxation. 🍵"
            ]
            return tips.randomElement()!
        }
    }
    
    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let dayOfWeek = Calendar.current.component(.weekday, from: Date())
        
        if nutritionScore >= 85 {
            return ["Crushing it today! 🌟", "Elite nutrition mode! 💯", "You're on fire! 🔥"].randomElement()!
        } else if nutritionScore >= 70 {
            return ["Solid progress! Keep pushing! 💪", "Good work today! 👏", "On the right track! 🎯"].randomElement()!
        } else if nutritionScore >= 50 {
            return ["Room to grow – you've got this! 💪", "Every meal is a chance to level up! 🚀", "Progress over perfection! ✨"].randomElement()!
        }
        
        // Time-based greetings
        if hour < 10 {
            return ["New day, new opportunities! ☀️", "Let's own this day! 🌅", "Morning fuel time! ⚡"].randomElement()!
        } else if hour < 14 {
            return ["Midday momentum! 🎯", "Keep the energy up! 💪", "Stay focused! 🧠"].randomElement()!
        } else if hour < 18 {
            // Day-specific afternoon messages
            if dayOfWeek == 6 { return "Friday vibes – finish strong! 🎉" }
            return ["Afternoon push! 💪", "Home stretch! 🏁", "You're doing great! ✨"].randomElement()!
        } else {
            return ["Evening reflection time 🌙", "Finish strong tonight! 🌟", "Wind down well! 😌"].randomElement()!
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with Score
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: "brain.head.profile")
                            .font(.title3)
                            .foregroundColor(.purple)
                        Text("Daily Insights")
                            .font(.title2)
                            .fontWeight(.bold)
                    }
                    
                    Text(greeting)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Nutrition Score Badge
                VStack(spacing: 2) {
                    Text("\(nutritionScore)")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(scoreColor)
                    Text("Score")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(width: 60, height: 60)
                .background(
                    Circle()
                        .fill(scoreColor.opacity(0.15))
                )
            }
            .padding(.horizontal, Spacing.md)
            .padding(.top, 16)
            .padding(.bottom, 12)
            
            Divider()
                .padding(.horizontal, Spacing.md)
            
            // What's Going Well
            if !positiveInsights.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: "hand.thumbsup.fill")
                            .font(.caption)
                            .foregroundColor(.green)
                        Text("What's Going Well")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.green)
                    }
                    
                    ForEach(positiveInsights) { insight in
                        InsightRow(insight: insight)
                    }
                }
                .padding(Spacing.md)
            }
            
            // Opportunities
            if !improvementSuggestions.isEmpty {
                if !positiveInsights.isEmpty {
                    Divider()
                        .padding(.horizontal, Spacing.md)
                }
                
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: "lightbulb.fill")
                            .font(.caption)
                            .foregroundColor(.orange)
                        Text("Opportunities")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.orange)
                    }
                    
                    ForEach(improvementSuggestions) { insight in
                        InsightRow(insight: insight)
                    }
                }
                .padding(Spacing.md)
            }
            
            // Quick Stats Row
            Divider()
                .padding(.horizontal, Spacing.md)
            
            HStack(spacing: 0) {
                QuickInsightStat(
                    value: "\(mealsLogged)",
                    label: "Meals",
                    icon: "fork.knife",
                    color: mealsLogged >= 3 ? .green : .gray
                )
                
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 1, height: 40)
                
                QuickInsightStat(
                    value: "\(Int(calorieProgress * 100))%",
                    label: "Calories",
                    icon: "flame.fill",
                    color: calorieProgress >= 0.9 && calorieProgress <= 1.1 ? .green : (calorieProgress > 1.15 ? .orange : .gray)
                )
                
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 1, height: 40)
                
                QuickInsightStat(
                    value: "\(Int(proteinProgress * 100))%",
                    label: "Protein",
                    icon: "bolt.fill",
                    color: proteinProgress >= 1.0 ? .green : (proteinProgress >= 0.8 ? .yellow : .gray)
                )
                
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 1, height: 40)
                
                QuickInsightStat(
                    value: "\(Int(waterProgress * 100))%",
                    label: "Water",
                    icon: "drop.fill",
                    color: waterProgress >= 1.0 ? .cyan : (waterProgress >= 0.5 ? .blue : .gray)
                )
            }
            .padding(.vertical, 14)
            
            // Daily Tip
            Divider()
                .padding(.horizontal, Spacing.md)
            
            Text(dailyTip)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
        }
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(
                    LinearGradient(
                        colors: [scoreColor.opacity(0.3), scoreColor.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: colorScheme == .dark ? .clear : .black.opacity(0.08), radius: 12, x: 0, y: 6)
    }
}

// MARK: - Daily Insight Model
struct DailyInsight: Identifiable {
    let id = UUID()
    let icon: String
    let text: String
    let color: Color
}

// MARK: - Insight Row
struct InsightRow: View {
    let insight: DailyInsight
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: insight.icon)
                .font(.ds_bodySmall)
                .foregroundColor(insight.color)
                .frame(width: 20)
            
            Text(insight.text)
                .font(.subheadline)
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Quick Insight Stat
struct QuickInsightStat: View {
    let value: String
    let label: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.ds_caption)
                    .foregroundColor(color)
                Text(value)
                    .font(.ds_bodySmall).fontWeight(.bold).fontDesign(.rounded)
                    .foregroundColor(.primary)
            }
            Text(label)
                .font(.ds_caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct SimpleNutritionCard: View {
    let title: String
    let current: Int
    let goal: Int
    let unit: String
    let color: Color
    
    private var progress: Double {
        guard goal > 0 else { return 0 }
        return min(Double(current) / Double(goal), 1.0)
    }
    
    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
                .fontWeight(.medium)
            
            Text("\(current)\(unit)")
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(color)
            
            Text("of \(goal)\(unit)")
                .font(.caption2)
                .foregroundColor(.secondary)
            
            ProgressView(value: progress)
                .progressViewStyle(LinearProgressViewStyle(tint: color))
                .scaleEffect(x: 1, y: 0.5)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.sm)
        .padding(.horizontal, Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.md)
                .fill(color.opacity(0.05))
        )
    }
}

struct SimpleMealSection: View {
    let title: String
    let icon: String
    let color: Color
    let onTap: () -> Void
    
    var body: some View {
        Button(action: { HapticManager.selectionChanged(); onTap() }) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                    .frame(width: 30)
                
                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Text("Add Food")
                    .font(.subheadline)
                    .foregroundColor(.blue)
                
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                    .foregroundColor(.blue)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(Color(.systemBackground))
            .cornerRadius(CornerRadius.md)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Swipeable Meal Card (Large carousel card like Challenge/Program widget)
struct SwipeableMealCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let mealType: MealType
    let meals: [MealEntryData]
    let isCurrentMealTime: Bool
    let onAddFood: () -> Void
    let onDelete: (MealEntryData) -> Void
    
    @State private var showingMealDetail = false
    
    private var totalCalories: Int {
        meals.reduce(0) { $0 + $1.calories }
    }
    
    private var totalProtein: Int {
        meals.reduce(0) { $0 + $1.protein }
    }
    
    private var totalCarbs: Int {
        meals.reduce(0) { $0 + $1.carbs }
    }
    
    private var totalFat: Int {
        meals.reduce(0) { $0 + $1.fat }
    }
    
    private var gradientColors: [Color] {
        [mealType.gradientColors.0, mealType.gradientColors.1]
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header - Meal type info
            HStack(alignment: .center, spacing: 12) {
                // Meal icon with gradient background
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [gradientColors[0].opacity(0.2), gradientColors[0].opacity(0.05)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 48, height: 48)
                    
                    Image(systemName: mealType.icon)
                        .font(.ds_heading2)
                        .foregroundStyle(
                            LinearGradient(
                                colors: gradientColors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                
                // Meal info
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(mealType.displayName)
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                        
                        if isCurrentMealTime {
                            Text("NOW")
                                .font(.caption2)
                                .fontWeight(.heavy)
                                .foregroundColor(.white)
                                .padding(.horizontal, Spacing.xs)
                                .padding(.vertical, 3)
                                .background(
                                    Capsule()
                                        .fill(
                                            LinearGradient(
                                                colors: gradientColors,
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                )
                        }
                    }
                    
                    Text(mealType.timeDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Calories badge (if has items)
                if !meals.isEmpty {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(totalCalories)")
                            .font(.ds_stat)
                            .foregroundStyle(
                                LinearGradient(
                                    colors: gradientColors,
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                        Text("calories")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.top, 16)
            .padding(.bottom, 12)
            
            // Divider with accent
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [gradientColors[0].opacity(0.3), gradientColors[1].opacity(0.1)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1)
                .padding(.horizontal, Spacing.md)
            
            // Content area - either items summary or add prompt
            HStack(spacing: 16) {
                // Left accent bar
                RoundedRectangle(cornerRadius: 2)
                    .fill(
                        LinearGradient(
                            colors: gradientColors,
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 4)
                    .padding(.vertical, Spacing.xs)
                
                if meals.isEmpty {
                    // Empty state - prompt to add
                    VStack(alignment: .leading, spacing: 8) {
                        Text("No food logged yet")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Text("Tap + to add your \(mealType.displayName.lowercased())")
                            .font(.caption)
                            .foregroundColor(.secondary.opacity(0.7))
                    }
                    
                    Spacer()
                    
                    // Add button
                    Button(action: onAddFood) {
                        HStack(spacing: 6) {
                            Image(systemName: "plus")
                                .font(.ds_bodySmall).fontWeight(.bold)
                            Text("Add Food")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, 10)
                        .background(
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: gradientColors,
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                        )
                        .shadow(color: gradientColors[0].opacity(0.3), radius: 8, x: 0, y: 4)
                    }
                    .buttonStyle(PlainButtonStyle())
                } else {
                    // Has items - show summary
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(meals.count) item\(meals.count == 1 ? "" : "s") logged")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                        
                        // Macro summary
                        HStack(spacing: 12) {
                            MacroPill(value: totalProtein, label: "P", color: .blue)
                            MacroPill(value: totalCarbs, label: "C", color: .green)
                            MacroPill(value: totalFat, label: "F", color: .orange)
                        }
                    }
                    
                    Spacer()
                    
                    // Add more button
                    Button(action: onAddFood) {
                        Image(systemName: "plus.circle.fill")
                            .font(.ds_heading1)
                            .foregroundStyle(
                                LinearGradient(
                                    colors: gradientColors,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
        }
        .background(
            ZStack {
                // Bottom shadow layer (deepest) - meal colored
                RoundedRectangle(cornerRadius: 28)
                    .fill(gradientColors[0].opacity(colorScheme == .dark ? 0.08 : 0.04))
                    .offset(y: 6)
                    .blur(radius: 3)
                
                // Middle shadow layer
                RoundedRectangle(cornerRadius: 26)
                    .fill(Color.black.opacity(colorScheme == .dark ? 0.12 : 0.03))
                    .offset(y: 3)
                
                // Main card background
                RoundedRectangle(cornerRadius: CornerRadius.xl)
                    .fill(
                        LinearGradient(
                            colors: Color.cardGradientStops(for: colorScheme),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                
                // Inner highlight (top edge glow)
                RoundedRectangle(cornerRadius: CornerRadius.xl)
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
                
                // Accent border
                RoundedRectangle(cornerRadius: CornerRadius.xl)
                    .stroke(
                        LinearGradient(
                            colors: [
                                gradientColors[0].opacity(colorScheme == .dark ? 0.4 : 0.25),
                                gradientColors[1].opacity(colorScheme == .dark ? 0.25 : 0.15)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.5
                    )
            }
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.25 : 0.1), radius: 12, x: 0, y: 6)
    }
}

// MARK: - Macro Pill (for meal card summary)
struct MacroPill: View {
    let value: Int
    let label: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 4) {
            Text("\(value)")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(color)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, Spacing.xs)
        .padding(.vertical, Spacing.xxs)
        .background(
            Capsule()
                .fill(color.opacity(0.12))
        )
    }
}

// MARK: - Meal Row Card (Matching Exercise Library Card Style)
struct MealRowCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let mealType: MealType
    let meals: [MealEntryData]
    let isMostRecent: Bool
    let onAddFood: () -> Void
    let onDelete: (MealEntryData) -> Void
    
    @State private var isExpanded = false
    @State private var glowRotation: Double = 0
    
    private var totalCalories: Int {
        meals.reduce(0) { $0 + $1.calories }
    }
    
    private var totalProtein: Int {
        meals.reduce(0) { $0 + $1.protein }
    }
    
    private var totalCarbs: Int {
        meals.reduce(0) { $0 + $1.carbs }
    }
    
    private var totalFat: Int {
        meals.reduce(0) { $0 + $1.fat }
    }
    
    private var mealIcon: String {
        switch mealType {
        case .breakfast: return "sunrise.fill"
        case .lunch: return "sun.max.fill"
        case .dinner: return "moon.stars.fill"
        case .snacks: return "leaf.fill"
        }
    }
    
    private var mealColor: Color {
        switch mealType {
        case .breakfast: return .orange
        case .lunch: return .green
        case .dinner: return .blue
        case .snacks: return .purple
        }
    }
    
    private var gradientColors: [Color] {
        switch mealType {
        case .breakfast: return [.orange, .yellow]
        case .lunch: return [.green, .teal]
        case .dinner: return [.blue, .cyan]
        case .snacks: return [.purple, .pink]
        }
    }
    
    // Check if this meal corresponds to the current time of day
    private var isCurrentMealTime: Bool {
        let hour = Calendar.current.component(.hour, from: Date())
        switch mealType {
        case .breakfast:
            return hour >= 5 && hour < 10  // 5 AM - 9:59 AM
        case .lunch:
            return hour >= 12 && hour < 14  // 12 PM - 1:59 PM
        case .dinner:
            return hour >= 18 || hour < 5  // 6 PM onward & late night until 5 AM
        case .snacks:
            // Snacks fills the gaps: 10-12 (morning snack) and 14-18 (afternoon snack)
            return (hour >= 10 && hour < 12) || (hour >= 14 && hour < 18)
        }
    }
    
    // Use time-based glow instead of most recent
    private var shouldGlow: Bool {
        isCurrentMealTime
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Main row card
            Button(action: {
                if meals.isEmpty {
                    onAddFood()
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        isExpanded.toggle()
                    }
                }
            }) {
                HStack(spacing: 12) {
                    // Circular gradient icon (matching exercise card style)
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: gradientColors,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 40, height: 40)
                            .shadow(color: gradientColors[0].opacity(0.25), radius: 4, x: 0, y: 2)
                        
                        Image(systemName: mealIcon)
                            .font(.ds_labelLarge)
                            .foregroundColor(.white)
                    }
                    
                    // Meal info
                    VStack(alignment: .leading, spacing: 2) {
                        Text(mealType.displayName)
                            .font(.body)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        
                        HStack(spacing: 8) {
                            if meals.isEmpty {
                                Text("Tap to add food")
                                    .font(.caption)
                                    .foregroundColor(mealColor)
                                    .fontWeight(.medium)
                            } else {
                                Text("\(meals.count) item\(meals.count == 1 ? "" : "s")")
                                    .font(.caption)
                                    .foregroundColor(mealColor)
                                    .fontWeight(.medium)
                                
                                Text("•")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                
                                Text("\(totalCalories) cal")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                        }
                    }
                    
                    Spacer()
                    
                    // Right side - Add button or Calorie display + Chevron
                    if meals.isEmpty {
                        // Add button (solid color)
                        Image(systemName: "plus.circle.fill")
                            .font(.ds_heading3)
                            .foregroundColor(mealColor)
                    } else {
                        // Calorie badge
                        HStack(spacing: 6) {
                            Text("\(totalCalories)")
                                .font(.subheadline)
                                .fontWeight(.bold)
                                .foregroundColor(mealColor)
                            Text("cal")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    // Chevron (always visible, matching exercise cards)
                    Image(systemName: "chevron.right")
                        .font(.ds_bodySmall).fontWeight(.medium)
                        .foregroundColor(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                .background(
                    ZStack {
                        // Bottom shadow layer (deepest) - meal colored (subtle)
                        RoundedRectangle(cornerRadius: 28)
                            .fill(gradientColors[0].opacity(colorScheme == .dark ? 0.06 : 0.03))
                            .offset(y: 4)
                            .blur(radius: 2)
                        
                        // Middle shadow layer (subtle)
                        RoundedRectangle(cornerRadius: 26)
                            .fill(Color.black.opacity(colorScheme == .dark ? 0.08 : 0.02))
                            .offset(y: 2)
                        
                        // Main card background
                        RoundedRectangle(cornerRadius: 25)
                            .fill(
                                LinearGradient(
                                    colors: colorScheme == .dark 
                                        ? [Color(white: 0.15), Color.cardBackground]
                                        : [Color.white, Color.white.opacity(0.98)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                        
                        // Inner highlight (top edge glow)
                        RoundedRectangle(cornerRadius: 25)
                            .stroke(
                                LinearGradient(
                                    colors: colorScheme == .dark 
                                        ? [Color.white.opacity(0.08), Color.clear]
                                        : [Color.white, Color.white.opacity(0.3), Color.clear],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 1
                            )
                        
                        // Subtle accent border (when not glowing)
                        if !shouldGlow {
                            RoundedRectangle(cornerRadius: 25)
                                .stroke(
                                    LinearGradient(
                                        colors: [
                                            gradientColors[0].opacity(colorScheme == .dark ? 0.2 : 0.12),
                                            gradientColors[1].opacity(colorScheme == .dark ? 0.1 : 0.06)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        }
                    }
                )
                .overlay(
                    Group {
                        if shouldGlow {
                            // Seamless animated glowing border for current meal time
                            RoundedRectangle(cornerRadius: 25)
                                .strokeBorder(
                                    AngularGradient(
                                        gradient: Gradient(colors: [
                                            gradientColors[0].opacity(0.7),
                                            gradientColors[1].opacity(0.5),
                                            gradientColors[0].opacity(0.3),
                                            gradientColors[1].opacity(0.5),
                                            gradientColors[0].opacity(0.7)
                                        ]),
                                        center: .center,
                                        startAngle: .degrees(glowRotation),
                                        endAngle: .degrees(glowRotation + 360)
                                    ),
                                    lineWidth: 2
                                )

                            // Subtle outer glow layer
                            RoundedRectangle(cornerRadius: 25)
                                .strokeBorder(
                                    AngularGradient(
                                        gradient: Gradient(colors: [
                                            gradientColors[0].opacity(0.25),
                                            gradientColors[1].opacity(0.15),
                                            gradientColors[0].opacity(0.25)
                                        ]),
                                        center: .center,
                                        startAngle: .degrees(glowRotation),
                                        endAngle: .degrees(glowRotation + 360)
                                    ),
                                    lineWidth: 4
                                )
                                .blur(radius: 4)
                        }
                    }
                )
                .shadow(color: shouldGlow ? mealColor.opacity(0.15) : .black.opacity(colorScheme == .dark ? 0.12 : 0.06), radius: 8, x: 0, y: 4)
            }
            .buttonStyle(PlainButtonStyle())
            
            // Expanded content with all food items
            if isExpanded && !meals.isEmpty {
                VStack(spacing: 0) {
                    // Divider
                    Rectangle()
                        .fill(mealColor.opacity(0.2))
                        .frame(height: 1)
                        .padding(.horizontal, Spacing.md)
                    
                    // Food items list - NO TRUNCATION
                    VStack(spacing: 0) {
                        ForEach(meals, id: \.id) { meal in
                            ExpandedMealItemRow(meal: meal, color: mealColor) {
                                onDelete(meal)
                            }
                            
                            // Separator between items
                            if meal.id != meals.last?.id {
                                Rectangle()
                                    .fill(Color.gray.opacity(0.1))
                                    .frame(height: 1)
                                    .padding(.horizontal, Spacing.md)
                            }
                        }
                    }
                    .padding(.vertical, Spacing.xs)
                    
                    // Macros summary row
                    HStack(spacing: 12) {
                        MacroBadge(label: "P", value: totalProtein, color: .blue)
                        MacroBadge(label: "C", value: totalCarbs, color: .orange)
                        MacroBadge(label: "F", value: totalFat, color: .purple)
                        
                        Spacer()
                        
                        // Add more button
                        Button(action: onAddFood) {
                            HStack(spacing: 5) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.ds_bodySmall)
                                Text("Add more")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                            }
                            .foregroundColor(mealColor)
                            .padding(.vertical, 6)
                            .padding(.horizontal, 10)
                            .background(mealColor.opacity(0.1))
                            .clipShape(Capsule())
                            .contentShape(Capsule())
                        }
                        .buttonStyle(BorderlessButtonStyle())
                    }
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, 10)
                    .background(gradientColors[0].opacity(0.05))
                }
                .background(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 0,
                        bottomLeadingRadius: 25,
                        bottomTrailingRadius: 25,
                        topTrailingRadius: 0
                    )
                    .fill(
                        LinearGradient(
                            colors: colorScheme == .dark 
                                ? [Color(white: 0.15), Color.cardBackground]
                                : [Color.white, Color.white.opacity(0.98)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 3)
                )
                .contentShape(Rectangle()) // Ensure proper hit testing
                .overlay(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 0,
                        bottomLeadingRadius: 25,
                        bottomTrailingRadius: 25,
                        topTrailingRadius: 0
                    )
                    .stroke(
                        LinearGradient(
                            colors: [
                                gradientColors[0].opacity(colorScheme == .dark ? 0.3 : 0.2),
                                gradientColors[1].opacity(colorScheme == .dark ? 0.2 : 0.1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
                    .allowsHitTesting(false) // Don't block button taps
                    .mask(
                        VStack(spacing: 0) {
                            Rectangle()
                                .fill(Color.clear)
                                .frame(height: 1)
                            Rectangle()
                                .fill(Color.black)
                        }
                    )
                )
                .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
            }
        }
    }
}

// MARK: - Expanded Meal Item Row (Full Display)
struct ExpandedMealItemRow: View {
    let meal: MealEntryData
    let color: Color
    let onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Food info - NO LINE LIMIT, shows full text
            VStack(alignment: .leading, spacing: 4) {
                Text(meal.foodName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true) // Allows text to wrap
                
                HStack(spacing: 8) {
                    Text("\(meal.displayQuantity) \(meal.unit)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("•")
                        .font(.caption)
                        .foregroundColor(.secondary.opacity(0.5))
                    
                    Text("\(meal.protein)p · \(meal.carbs)c · \(meal.fat)f")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Calories
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(meal.calories)")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(color)
                Text("cal")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            // Delete button
            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .font(.ds_heading3)
                    .foregroundColor(.red.opacity(0.6))
                    .frame(width: 32, height: 32) // Larger hit area
                    .contentShape(Rectangle())
            }
            .buttonStyle(BorderlessButtonStyle())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle()) // Ensure row doesn't steal taps
    }
}

// MARK: - Macro Badge
struct MacroBadge: View {
    let label: String
    let value: Int
    let color: Color
    
    var body: some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(color)
            Text("\(value)g")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.primary)
        }
        .padding(.horizontal, Spacing.xs)
        .padding(.vertical, Spacing.xxs)
        .background(color.opacity(0.1))
        .clipShape(Capsule())
    }
}
