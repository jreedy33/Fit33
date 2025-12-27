import SwiftUI

// MARK: - Activity Rings Card
/// Beautiful triple-ring activity tracker inspired by Apple Watch
struct ActivityRingsCard: View {
    @ObservedObject var healthKitManager = HealthKitManager.shared
    @StateObject private var mealService = MealService.shared
    @EnvironmentObject var workoutManager: WorkoutManager
    @EnvironmentObject var userManager: UserManager
    
    @State private var showingDetailView = false
    @State private var isAnimating = false
    
    // Activity Ring colors - Rainbow warm spectrum (outer to inner)
    private let stepsColor = Color.red
    private let workoutColor = Color.orange
    private let macroColor = Color.yellow
    
    // Nutrition Ring colors - Rainbow cool spectrum (outer to inner)
    private let caloriesColor = Color.green
    private let proteinColor = Color.blue
    private let fatColor = Color.purple
    
    var body: some View {
        Button(action: { showingDetailView = true }) {
            VStack(spacing: 16) {
                // Header
                HStack {
                    Text("Activity")
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Text(formattedDate)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                
                // Main content - Two ring sets side by side
                HStack(spacing: 24) {
                    // Activity Rings (Steps, Workout, Macros)
                    VStack(spacing: 8) {
                        ActivityTripleRing(
                            outerProgress: stepsProgress,
                            middleProgress: workoutProgress,
                            innerProgress: macroProgress,
                            outerColor: stepsColor,
                            middleColor: workoutColor,
                            innerColor: macroColor,
                            size: 100
                        )
                        
                        Text("Activity")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                    }
                    
                    // Nutrition Rings (Calories, Protein, Fat)
                    VStack(spacing: 8) {
                        ActivityTripleRing(
                            outerProgress: caloriesProgress,
                            middleProgress: proteinProgress,
                            innerProgress: fatProgress,
                            outerColor: caloriesColor,
                            middleColor: proteinColor,
                            innerColor: fatColor,
                            size: 100
                        )
                        
                        Text("Nutrition")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 8)
                
                Divider()
                    .padding(.horizontal, 16)
                
                // Ring legends
                HStack(spacing: 0) {
                    // Activity legends
                    VStack(alignment: .leading, spacing: 6) {
                        ActivityRingLegendRow(
                            color: stepsColor,
                            label: "Steps",
                            value: "\(healthKitManager.todaySteps)",
                            goal: "\(healthKitManager.stepGoal)"
                        )
                        ActivityRingLegendRow(
                            color: workoutColor,
                            label: "Workout",
                            value: completedWorkoutToday ? "Done" : "0",
                            goal: "1"
                        )
                        ActivityRingLegendRow(
                            color: macroColor,
                            label: "Macros",
                            value: macrosMet ? "✓" : "\(macrosMetCount)/3",
                            goal: "3/3"
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    // Nutrition legends
                    VStack(alignment: .leading, spacing: 6) {
                        ActivityRingLegendRow(
                            color: caloriesColor,
                            label: "Calories",
                            value: "\(currentCalories)",
                            goal: "\(calorieGoal)"
                        )
                        ActivityRingLegendRow(
                            color: proteinColor,
                            label: "Protein",
                            value: "\(currentProtein)g",
                            goal: "\(proteinGoal)g"
                        )
                        ActivityRingLegendRow(
                            color: fatColor,
                            label: "Fat",
                            value: "\(currentFat)g",
                            goal: "\(fatGoal)g"
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
        .sheet(isPresented: $showingDetailView) {
            ActivityRingsDetailView()
                .environmentObject(userManager)
        }
    }
    
    // MARK: - Computed Properties
    
    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: Date())
    }
    
    // Activity ring progress
    private var stepsProgress: Double {
        guard healthKitManager.stepGoal > 0 else { return 0 }
        return min(Double(healthKitManager.todaySteps) / Double(healthKitManager.stepGoal), 1.0)
    }
    
    private var workoutProgress: Double {
        completedWorkoutToday ? 1.0 : 0.0
    }
    
    private var macroProgress: Double {
        macrosMet ? 1.0 : Double(macrosMetCount) / 3.0
    }
    
    private var completedWorkoutToday: Bool {
        // Check if user's last workout was today
        guard let lastWorkout = userManager.currentUser?.lastWorkoutDate else { return false }
        return Calendar.current.isDateInToday(lastWorkout)
    }
    
    // Nutrition ring progress
    private var caloriesProgress: Double {
        guard calorieGoal > 0 else { return 0 }
        return min(Double(currentCalories) / Double(calorieGoal), 1.0)
    }
    
    private var proteinProgress: Double {
        guard proteinGoal > 0 else { return 0 }
        return min(Double(currentProtein) / Double(proteinGoal), 1.0)
    }
    
    private var fatProgress: Double {
        guard fatGoal > 0 else { return 0 }
        return min(Double(currentFat) / Double(fatGoal), 1.0)
    }
    
    // Current nutrition values
    private var currentCalories: Int {
        mealService.todaysMeals.reduce(0) { $0 + $1.calories }
    }
    
    private var currentProtein: Int {
        mealService.todaysMeals.reduce(0) { $0 + $1.protein }
    }
    
    private var currentFat: Int {
        mealService.todaysMeals.reduce(0) { $0 + $1.fat }
    }
    
    // Goals calculated from user profile
    private var calorieGoal: Int {
        guard let user = userManager.currentUser else { return 2200 }
        let weight = user.weight > 0 ? Int(user.weight) : UserDefaults.standard.integer(forKey: "userWeight")
        let height = user.height > 0 ? Int(user.height) : UserDefaults.standard.integer(forKey: "userHeight")
        
        // Mifflin-St Jeor equation estimate
        if weight > 0 && height > 0 {
            let bmr = (10 * Double(weight)) + (6.25 * Double(height)) - 150
            return Int(bmr * 1.55) // Moderate activity
        }
        return 2200
    }
    
    private var proteinGoal: Int {
        // 30% of calories from protein (1g = 4 calories)
        return (calorieGoal * 30 / 100) / 4
    }
    
    private var fatGoal: Int {
        // 30% of calories from fat (1g = 9 calories)
        return (calorieGoal * 30 / 100) / 9
    }
    
    // Macro tracking with upper limits for calories and fat
    // Must hit 100% of goal, with buffer for slight overages
    private var macrosMetCount: Int {
        var count = 0
        
        // Calories: must hit 100%, max 115% (15% over-buffer)
        let calorieMax = Int(Double(calorieGoal) * 1.15)
        if calorieGoal > 0 && currentCalories >= calorieGoal && currentCalories <= calorieMax { count += 1 }
        
        // Protein: hit 100% minimum, no max (more protein is beneficial)
        if proteinGoal > 0 && currentProtein >= proteinGoal { count += 1 }
        
        // Fat: must hit 100%, max 120% (20% over-buffer)
        let fatMax = Int(Double(fatGoal) * 1.20)
        if fatGoal > 0 && currentFat >= fatGoal && currentFat <= fatMax { count += 1 }
        
        return count
    }
    
    private var macrosMet: Bool {
        macrosMetCount >= 3
    }
    
    // Check if user exceeded the buffer (for visual warning)
    private var caloriesExceeded: Bool {
        let calorieMax = Int(Double(calorieGoal) * 1.15)
        return currentCalories > calorieMax
    }
    
    private var fatExceeded: Bool {
        let fatMax = Int(Double(fatGoal) * 1.20)
        return currentFat > fatMax
    }
}

// MARK: - Triple Ring View
struct ActivityTripleRing: View {
    let outerProgress: Double
    let middleProgress: Double
    let innerProgress: Double
    let outerColor: Color
    let middleColor: Color
    let innerColor: Color
    let size: CGFloat
    
    private let ringWidth: CGFloat = 8
    private let ringSpacing: CGFloat = 4
    
    var body: some View {
        ZStack {
            // Outer ring (largest)
            RingView(
                progress: outerProgress,
                color: outerColor,
                size: size,
                lineWidth: ringWidth
            )
            
            // Middle ring
            RingView(
                progress: middleProgress,
                color: middleColor,
                size: size - (ringWidth * 2 + ringSpacing * 2),
                lineWidth: ringWidth
            )
            
            // Inner ring (smallest)
            RingView(
                progress: innerProgress,
                color: innerColor,
                size: size - (ringWidth * 4 + ringSpacing * 4),
                lineWidth: ringWidth
            )
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Nutrition Triple Ring (for Meals Tab)
/// Calories (outer), Protein (middle), Fat (inner)
struct NutritionTripleRing: View {
    let caloriesProgress: Double
    let proteinProgress: Double
    let fatProgress: Double
    let size: CGFloat
    var caloriesExceeded: Bool = false
    var fatExceeded: Bool = false
    
    // Nutrition ring colors - Rainbow cool spectrum (outer to inner)
    private let caloriesColor = Color.green
    private let proteinColor = Color.blue
    private let fatColor = Color.purple
    
    private let ringWidth: CGFloat = 8
    private let ringSpacing: CGFloat = 4
    
    var body: some View {
        ZStack {
            // Outer ring - Calories (red if exceeded)
            RingView(
                progress: min(caloriesProgress, 1.0),
                color: caloriesExceeded ? .red : caloriesColor,
                size: size,
                lineWidth: ringWidth
            )
            
            // Exceeded indicator for calories
            if caloriesExceeded {
                ExceededWarningBadge(size: size, position: .topTrailing)
            }
            
            // Middle ring - Protein (no limit, always normal color)
            RingView(
                progress: proteinProgress,
                color: proteinColor,
                size: size - (ringWidth * 2 + ringSpacing * 2),
                lineWidth: ringWidth
            )
            
            // Inner ring - Fat (red if exceeded)
            RingView(
                progress: min(fatProgress, 1.0),
                color: fatExceeded ? .red : fatColor,
                size: size - (ringWidth * 4 + ringSpacing * 4),
                lineWidth: ringWidth
            )
            
            // Exceeded indicator for fat
            if fatExceeded {
                ExceededWarningBadge(size: size * 0.6, position: .bottomTrailing)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Exceeded Warning Badge
struct ExceededWarningBadge: View {
    let size: CGFloat
    let position: Alignment
    
    var body: some View {
        Image(systemName: "exclamationmark.triangle.fill")
            .font(.system(size: size * 0.12))
            .foregroundColor(.red)
            .background(
                Circle()
                    .fill(.white)
                    .frame(width: size * 0.15, height: size * 0.15)
            )
            .frame(width: size, height: size, alignment: position)
            .offset(x: position == .topTrailing ? -2 : 2, y: position == .topTrailing ? 2 : -2)
    }
}

// MARK: - Full Activity Six Ring (for Stats Page)
/// All 6 rings: Steps, Workout, Macros, Calories, Protein, Fat
struct FullActivitySixRing: View {
    // Activity ring progress
    let stepsProgress: Double
    let workoutProgress: Double
    let macrosProgress: Double
    // Nutrition ring progress
    let caloriesProgress: Double
    let proteinProgress: Double
    let fatProgress: Double
    let size: CGFloat
    
    // Ring width scales with size for clean proportions
    private var ringWidth: CGFloat { size * 0.05 }
    private var ringSpacing: CGFloat { size * 0.015 }
    
    // Rainbow colors (outer to inner)
    private let stepsColor = Color.red
    private let workoutColor = Color.orange
    private let macrosColor = Color.yellow
    private let caloriesColor = Color.green
    private let proteinColor = Color.blue
    private let fatColor = Color.purple
    
    var body: some View {
        ZStack {
            // Ring 1 (Outer) - Steps - Red
            RingView(
                progress: stepsProgress,
                color: stepsColor,
                size: size,
                lineWidth: ringWidth
            )
            
            // Ring 2 - Workout - Orange
            RingView(
                progress: workoutProgress,
                color: workoutColor,
                size: ringSize(at: 1),
                lineWidth: ringWidth
            )
            
            // Ring 3 - Macros - Yellow
            RingView(
                progress: macrosProgress,
                color: macrosColor,
                size: ringSize(at: 2),
                lineWidth: ringWidth
            )
            
            // Ring 4 - Calories - Green
            RingView(
                progress: caloriesProgress,
                color: caloriesColor,
                size: ringSize(at: 3),
                lineWidth: ringWidth
            )
            
            // Ring 5 - Protein - Blue
            RingView(
                progress: proteinProgress,
                color: proteinColor,
                size: ringSize(at: 4),
                lineWidth: ringWidth
            )
            
            // Ring 6 (Inner) - Fat - Purple
            RingView(
                progress: fatProgress,
                color: fatColor,
                size: ringSize(at: 5),
                lineWidth: ringWidth
            )
        }
        .frame(width: size, height: size)
    }
    
    // Calculate ring size at position (0 = outer, 5 = inner)
    private func ringSize(at position: Int) -> CGFloat {
        size - (CGFloat(position) * (ringWidth * 2 + ringSpacing * 2))
    }
}

// MARK: - Single Ring View (Vibrant Gradient - matches Step Tracker style)
struct RingView: View {
    let progress: Double
    let color: Color
    let size: CGFloat
    let lineWidth: CGFloat
    
    // Simple vibrant gradients - each ring stays in its own color family
    // Activity: Red, Orange, Yellow | Nutrition: Green, Blue, Purple
    private var gradientColors: [Color] {
        switch color {
        // === ACTIVITY RINGS ===
        case .red:
            // Vibrant red gradient
            return [Color(red: 1.0, green: 0.25, blue: 0.35), Color(red: 1.0, green: 0.35, blue: 0.4), Color(red: 1.0, green: 0.3, blue: 0.38)]
        case .orange:
            // Vibrant orange gradient
            return [Color(red: 1.0, green: 0.5, blue: 0.1), Color(red: 1.0, green: 0.6, blue: 0.2), Color(red: 1.0, green: 0.55, blue: 0.15)]
        case .yellow:
            // Vibrant yellow gradient
            return [Color(red: 1.0, green: 0.8, blue: 0.1), Color(red: 1.0, green: 0.85, blue: 0.25), Color(red: 1.0, green: 0.82, blue: 0.18)]
            
        // === NUTRITION RINGS (neon vibrant to match "0/7 days" text) ===
        case .green:
            // Neon vibrant green - matches Calorie Target text
            return [Color(red: 0.2, green: 1.0, blue: 0.4), Color(red: 0.3, green: 0.95, blue: 0.5), .green]
        case .blue:
            // Neon vibrant blue - matches Protein Goals text
            return [Color(red: 0.3, green: 0.6, blue: 1.0), Color(red: 0.4, green: 0.7, blue: 1.0), .blue]
        case .purple:
            // Neon vibrant purple - matches Fat Goals text
            return [Color(red: 0.7, green: 0.4, blue: 1.0), Color(red: 0.6, green: 0.35, blue: 0.95), .purple]
        default:
            return [color, color.opacity(0.9), color]
        }
    }
    
    var body: some View {
        ZStack {
            // Background ring (static placeholder) - no glow, just colored
            Circle()
                .stroke(color.opacity(0.25), lineWidth: lineWidth)
                .frame(width: size, height: size)
            
            // Glow only on the dynamic progress ring
            if progress > 0 {
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        color.opacity(0.3),
                        style: StrokeStyle(lineWidth: lineWidth + 4, lineCap: .round)
                    )
                    .frame(width: size, height: size)
                    .rotationEffect(.degrees(-90))
                    .blur(radius: 4)
            }
            
            // Progress ring with vibrant LinearGradient (the moving bar)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    LinearGradient(
                        colors: gradientColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .frame(width: size, height: size)
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.6, dampingFraction: 0.7), value: progress)
        }
    }
}

// MARK: - Activity Ring Legend Row
struct ActivityRingLegendRow: View {
    let color: Color
    let label: String
    let value: String
    let goal: String
    
    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text(value)
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
        }
    }
}

// MARK: - Activity Rings Detail View
struct ActivityRingsDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var healthKitManager = HealthKitManager.shared
    @StateObject private var mealService = MealService.shared
    @EnvironmentObject var userManager: UserManager
    
    // Activity Ring colors - Rainbow warm spectrum
    private let stepsColor = Color.red
    private let workoutColor = Color.orange
    private let macroColor = Color.yellow
    
    // Nutrition Ring colors - Rainbow cool spectrum
    private let caloriesColor = Color.green
    private let proteinColor = Color.blue
    private let fatColor = Color.purple
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background gradient
                LinearGradient(
                    colors: [Color.blue.opacity(0.1), Color.purple.opacity(0.05), Color.white],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Large rings display
                        HStack(spacing: 40) {
                            // Activity Rings
                            VStack(spacing: 12) {
                                ActivityTripleRing(
                                    outerProgress: stepsProgress,
                                    middleProgress: workoutProgress,
                                    innerProgress: macroProgress,
                                    outerColor: stepsColor,
                                    middleColor: workoutColor,
                                    innerColor: macroColor,
                                    size: 140
                                )
                                
                                Text("Activity")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.primary)
                            }
                            
                            // Nutrition Rings
                            VStack(spacing: 12) {
                                ActivityTripleRing(
                                    outerProgress: caloriesProgress,
                                    middleProgress: proteinProgress,
                                    innerProgress: fatProgress,
                                    outerColor: caloriesColor,
                                    middleColor: proteinColor,
                                    innerColor: fatColor,
                                    size: 140
                                )
                                
                                Text("Nutrition")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.primary)
                            }
                        }
                        .padding(.top, 20)
                        
                        // Activity Details Card
                        detailCard(title: "Activity Goals", items: [
                            DetailItem(color: stepsColor, icon: "figure.walk", label: "Steps", current: "\(healthKitManager.todaySteps)", goal: "\(healthKitManager.stepGoal)", progress: stepsProgress),
                            DetailItem(color: workoutColor, icon: "flame.fill", label: "Workout", current: workoutProgress > 0 ? "Complete" : "Not yet", goal: "1 workout", progress: workoutProgress),
                            DetailItem(color: macroColor, icon: "chart.pie.fill", label: "Macros", current: "\(macrosMetCount)/3", goal: "All 3", progress: macroProgress)
                        ])
                        
                        // Nutrition Details Card
                        detailCard(title: "Nutrition Goals", items: [
                            DetailItem(color: caloriesColor, icon: "flame", label: "Calories", current: "\(currentCalories)", goal: "\(calorieGoal)", progress: caloriesProgress),
                            DetailItem(color: proteinColor, icon: "leaf.fill", label: "Protein", current: "\(currentProtein)g", goal: "\(proteinGoal)g", progress: proteinProgress),
                            DetailItem(color: fatColor, icon: "drop.fill", label: "Fat", current: "\(currentFat)g", goal: "\(fatGoal)g", progress: fatProgress)
                        ])
                        
                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 20)
                }
            }
            .navigationTitle("Today's Progress")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }
    
    // MARK: - Detail Card
    private func detailCard(title: String, items: [DetailItem]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.headline)
                .fontWeight(.bold)
            
            VStack(spacing: 12) {
                ForEach(items, id: \.label) { item in
                    HStack(spacing: 12) {
                        // Icon
                        ZStack {
                            Circle()
                                .fill(item.color.opacity(0.15))
                                .frame(width: 40, height: 40)
                            
                            Image(systemName: item.icon)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(item.color)
                        }
                        
                        // Labels
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.label)
                                .font(.subheadline)
                                .fontWeight(.medium)
                            
                            Text("Goal: \(item.goal)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        // Progress
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(item.current)
                                .font(.subheadline)
                                .fontWeight(.bold)
                                .foregroundColor(item.progress >= 1.0 ? .green : .primary)
                            
                            Text("\(Int(item.progress * 100))%")
                                .font(.caption)
                                .foregroundColor(item.progress >= 1.0 ? .green : .secondary)
                        }
                    }
                    .padding(12)
                    .background(Color.white)
                    .cornerRadius(12)
                    .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
                }
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.8))
        .cornerRadius(16)
    }
    
    // MARK: - Computed Properties (same as card)
    private var stepsProgress: Double {
        guard healthKitManager.stepGoal > 0 else { return 0 }
        return min(Double(healthKitManager.todaySteps) / Double(healthKitManager.stepGoal), 1.0)
    }
    
    private var workoutProgress: Double {
        guard let lastWorkout = userManager.currentUser?.lastWorkoutDate else { return 0 }
        return Calendar.current.isDateInToday(lastWorkout) ? 1.0 : 0.0
    }
    
    private var macroProgress: Double {
        Double(macrosMetCount) / 3.0
    }
    
    private var caloriesProgress: Double {
        guard calorieGoal > 0 else { return 0 }
        return min(Double(currentCalories) / Double(calorieGoal), 1.0)
    }
    
    private var proteinProgress: Double {
        guard proteinGoal > 0 else { return 0 }
        return min(Double(currentProtein) / Double(proteinGoal), 1.0)
    }
    
    private var fatProgress: Double {
        guard fatGoal > 0 else { return 0 }
        return min(Double(currentFat) / Double(fatGoal), 1.0)
    }
    
    private var currentCalories: Int {
        mealService.todaysMeals.reduce(0) { $0 + $1.calories }
    }
    
    private var currentProtein: Int {
        mealService.todaysMeals.reduce(0) { $0 + $1.protein }
    }
    
    private var currentFat: Int {
        mealService.todaysMeals.reduce(0) { $0 + $1.fat }
    }
    
    // Goals calculated from user profile
    private var calorieGoal: Int {
        guard let user = userManager.currentUser else { return 2200 }
        let weight = user.weight > 0 ? Int(user.weight) : UserDefaults.standard.integer(forKey: "userWeight")
        let height = user.height > 0 ? Int(user.height) : UserDefaults.standard.integer(forKey: "userHeight")
        
        if weight > 0 && height > 0 {
            let bmr = (10 * Double(weight)) + (6.25 * Double(height)) - 150
            return Int(bmr * 1.55)
        }
        return 2200
    }
    
    private var proteinGoal: Int {
        (calorieGoal * 30 / 100) / 4
    }
    
    private var fatGoal: Int {
        (calorieGoal * 30 / 100) / 9
    }
    
    private var macrosMetCount: Int {
        var count = 0
        // Calories: must hit 100%, max 115%
        let calorieMax = Int(Double(calorieGoal) * 1.15)
        if calorieGoal > 0 && currentCalories >= calorieGoal && currentCalories <= calorieMax { count += 1 }
        // Protein: hit 100% minimum, no max
        if proteinGoal > 0 && currentProtein >= proteinGoal { count += 1 }
        // Fat: must hit 100%, max 120%
        let fatMax = Int(Double(fatGoal) * 1.20)
        if fatGoal > 0 && currentFat >= fatGoal && currentFat <= fatMax { count += 1 }
        return count
    }
}

// MARK: - Detail Item Model
struct DetailItem {
    let color: Color
    let icon: String
    let label: String
    let current: String
    let goal: String
    let progress: Double
}

// MARK: - Preview
#Preview {
    ActivityRingsCard()
        .environmentObject(WorkoutManager.shared)
        .environmentObject(UserManager())
        .padding()
        .background(Color.gray.opacity(0.1))
}

// MARK: - App Icon Rings Preview
/// Use this view to generate an app icon with completed activity rings
struct AppIconRingsView: View {
    var size: CGFloat = 512
    var ringWidth: CGFloat = 36
    var ringSpacing: CGFloat = 16
    var useWhiteBackground: Bool = true
    
    var body: some View {
        ZStack {
            // Background
            if useWhiteBackground {
                Color.white
            } else {
                Color.black
            }
            
            // The three completed rings
            ZStack {
                // Outer ring (Red - Steps)
                AppIconRing(
                    progress: 1.0,
                    colors: [Color(red: 1.0, green: 0.25, blue: 0.35), Color(red: 1.0, green: 0.4, blue: 0.45)],
                    size: size * 0.75,
                    lineWidth: ringWidth,
                    backgroundOpacity: useWhiteBackground ? 0.15 : 0.2
                )
                
                // Middle ring (Orange - Workout)
                AppIconRing(
                    progress: 1.0,
                    colors: [Color(red: 1.0, green: 0.5, blue: 0.1), Color(red: 1.0, green: 0.65, blue: 0.25)],
                    size: size * 0.75 - (ringWidth * 2 + ringSpacing * 2),
                    lineWidth: ringWidth,
                    backgroundOpacity: useWhiteBackground ? 0.15 : 0.2
                )
                
                // Inner ring (Yellow - Macros)
                AppIconRing(
                    progress: 1.0,
                    colors: [Color(red: 1.0, green: 0.8, blue: 0.1), Color(red: 1.0, green: 0.9, blue: 0.3)],
                    size: size * 0.75 - (ringWidth * 4 + ringSpacing * 4),
                    lineWidth: ringWidth,
                    backgroundOpacity: useWhiteBackground ? 0.15 : 0.2
                )
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - App Icon Ring Component
struct AppIconRing: View {
    let progress: Double
    let colors: [Color]
    let size: CGFloat
    let lineWidth: CGFloat
    var backgroundOpacity: Double = 0.2
    
    var body: some View {
        ZStack {
            // Background ring
            Circle()
                .stroke(Color.gray.opacity(backgroundOpacity), lineWidth: lineWidth)
                .frame(width: size, height: size)
            
            // Progress ring with gradient
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: colors + [colors[0]]),
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(360)
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .frame(width: size, height: size)
                .rotationEffect(.degrees(-90))
                .shadow(color: colors[0].opacity(0.4), radius: 6, x: 0, y: 0)
            
            // End cap glow effect
            Circle()
                .fill(colors[0])
                .frame(width: lineWidth, height: lineWidth)
                .offset(y: -size / 2)
                .shadow(color: colors[0].opacity(0.8), radius: 4)
        }
    }
}

#Preview("App Icon - White Background") {
    AppIconRingsView(size: 512, useWhiteBackground: true)
        .clipShape(RoundedRectangle(cornerRadius: 100))
        .previewLayout(.fixed(width: 512, height: 512))
}

#Preview("App Icon - Dark Background") {
    AppIconRingsView(size: 512, useWhiteBackground: false)
        .clipShape(RoundedRectangle(cornerRadius: 100))
        .previewLayout(.fixed(width: 512, height: 512))
}

#Preview("App Icon - Small") {
    AppIconRingsView(size: 180, ringWidth: 14, ringSpacing: 6, useWhiteBackground: true)
        .clipShape(RoundedRectangle(cornerRadius: 40))
        .previewLayout(.fixed(width: 180, height: 180))
}

