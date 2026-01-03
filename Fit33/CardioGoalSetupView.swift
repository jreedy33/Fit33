import SwiftUI

// MARK: - Goal Type
enum CardioGoalType: String, CaseIterable {
    case openGoal = "Open Goal"
    case time = "Time"
    case distance = "Distance"
    case calories = "Calories"
    
    var icon: String {
        switch self {
        case .openGoal: return "infinity"
        case .time: return "clock.fill"
        case .distance: return "point.topleft.down.to.point.bottomright.curvepath.fill"
        case .calories: return "flame.fill"
        }
    }
    
    var description: String {
        switch self {
        case .openGoal: return "No specific target"
        case .time: return "Set a duration"
        case .distance: return "Set a distance"
        case .calories: return "Set a calorie burn"
        }
    }
}

// MARK: - Cardio Goal Setup View
struct CardioGoalSetupView: View {
    let activityType: CardioActivityType
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var userManager: UserManager
    @StateObject private var bluetoothManager = BluetoothFitnessManager.shared
    @ObservedObject private var workoutManager = WorkoutManager.shared
    
    @State private var selectedGoalType: CardioGoalType = .time
    @State private var timeGoal: Int = 30 // minutes
    @State private var distanceGoal: Double = 5.0 // km
    @State private var calorieGoal: Int = 300
    @State private var showingBluetoothSheet = false
    @State private var startWorkout = false
    
    // Smart recommendations based on user profile
    private var recommendations: (time: Int, distance: Double, calories: Int) {
        let user = userManager.currentUser
        let experience = user?.experienceLevel?.lowercased() ?? "beginner"
        let goal = user?.fitnessGoal?.lowercased() ?? ""
        
        // Base values from activity type
        var time = activityType.defaultDuration
        var distance = activityType.defaultDistance
        var calories = activityType.defaultCalories
        
        // Adjust based on experience
        switch experience {
        case "beginner":
            time = Int(Double(time) * 0.7)
            distance = distance * 0.6
            calories = Int(Double(calories) * 0.7)
        case "advanced":
            time = Int(Double(time) * 1.3)
            distance = distance * 1.4
            calories = Int(Double(calories) * 1.3)
        default:
            break // intermediate stays at default
        }
        
        // Adjust based on goal
        if goal.contains("lose") || goal.contains("lean") || goal.contains("fat") {
            calories = Int(Double(calories) * 1.2)
            time = Int(Double(time) * 1.1)
        } else if goal.contains("endurance") {
            time = Int(Double(time) * 1.3)
            distance = distance * 1.3
        }
        
        return (time, distance, calories)
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background with activity color accent
                backgroundGradient
                
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 28) {
                        // Activity Header
                        activityHeader
                        
                        // Goal Type Selection
                        goalTypeSelector
                        
                        // Goal Input Based on Selected Type
                        goalInputSection
                        
                        // Smart Recommendation
                        smartRecommendationCard
                        
                        // Bluetooth Equipment Section
                        if activityType.supportsBluetooth {
                            bluetoothSection
                        }
                        
                        Spacer(minLength: 100)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                }
                
                // GO Button
                VStack {
                    Spacer()
                    goButton
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.primary)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(Color(.systemGray5)))
                    }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingBluetoothSheet) {
                FitnessEquipmentView()
            }
            .fullScreenCover(isPresented: $startWorkout) {
                CardioActiveWorkoutView(
                    activityType: activityType,
                    goalType: selectedGoalType,
                    timeGoal: timeGoal,
                    distanceGoal: distanceGoal,
                    calorieGoal: calorieGoal
                )
                .environmentObject(userManager)
            }
            .onChange(of: workoutManager.shouldDismissCardioFlow) { _, shouldDismiss in
                if shouldDismiss {
                    startWorkout = false
                    dismiss()
                }
            }
        }
        .onAppear {
            // Set initial values to recommendations
            timeGoal = recommendations.time
            distanceGoal = recommendations.distance
            calorieGoal = recommendations.calories
        }
    }
    
    // MARK: - Background
    private var backgroundGradient: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: colorScheme == .dark
                    ? [Color(red: 0.05, green: 0.08, blue: 0.12), Color.black]
                    : [Color(red: 0.95, green: 0.97, blue: 1.0), Color.white]),
                startPoint: .top,
                endPoint: .bottom
            )
            
            // Activity color accent at top
            activityType.color.opacity(0.1)
                .blur(radius: 100)
                .offset(y: -200)
        }
        .ignoresSafeArea()
    }
    
    // MARK: - Activity Header
    private var activityHeader: some View {
        VStack(spacing: 16) {
            // Large icon
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [activityType.color.opacity(0.3), activityType.color.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 100, height: 100)
                
                Image(systemName: activityType.icon)
                    .font(.system(size: 44))
                    .foregroundColor(activityType.color)
            }
            
            VStack(spacing: 4) {
                Text(activityType.rawValue)
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Text(activityType.description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.top, 20)
    }
    
    // MARK: - Goal Type Selector
    private var goalTypeSelector: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("GOAL TYPE")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.secondary)
                .tracking(1)
            
            HStack(spacing: 10) {
                ForEach(CardioGoalType.allCases, id: \.self) { goalType in
                    GoalTypeButton(
                        goalType: goalType,
                        isSelected: selectedGoalType == goalType,
                        color: activityType.color
                    ) {
                        HapticManager.selectionChanged()
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedGoalType = goalType
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Goal Input Section
    @ViewBuilder
    private var goalInputSection: some View {
        if selectedGoalType != .openGoal {
            VStack(alignment: .leading, spacing: 16) {
                Text("SET YOUR GOAL")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)
                    .tracking(1)
                
                switch selectedGoalType {
                case .time:
                    TimeGoalPicker(minutes: $timeGoal, color: activityType.color)
                case .distance:
                    DistanceGoalPicker(distance: $distanceGoal, color: activityType.color)
                case .calories:
                    CalorieGoalPicker(calories: $calorieGoal, color: activityType.color)
                case .openGoal:
                    EmptyView()
                }
            }
        }
    }
    
    // MARK: - Smart Recommendation Card
    private var smartRecommendationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundColor(.orange)
                Text("RECOMMENDED FOR YOU")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)
                    .tracking(1)
            }
            
            HStack(spacing: 16) {
                RecommendationBubble(
                    icon: "clock.fill",
                    value: "\(recommendations.time)",
                    unit: "min",
                    color: .blue
                ) {
                    selectedGoalType = .time
                    timeGoal = recommendations.time
                }
                
                if activityType.defaultDistance > 0 {
                    RecommendationBubble(
                        icon: "point.topleft.down.to.point.bottomright.curvepath.fill",
                        value: String(format: "%.1f", recommendations.distance),
                        unit: "km",
                        color: .green
                    ) {
                        selectedGoalType = .distance
                        distanceGoal = recommendations.distance
                    }
                }
                
                RecommendationBubble(
                    icon: "flame.fill",
                    value: "\(recommendations.calories)",
                    unit: "cal",
                    color: .orange
                ) {
                    selectedGoalType = .calories
                    calorieGoal = recommendations.calories
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color(.systemGray6))
        )
    }
    
    // MARK: - Bluetooth Section
    private var bluetoothSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("EQUIPMENT")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.secondary)
                .tracking(1)
            
            Button(action: {
                showingBluetoothSheet = true
            }) {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(bluetoothManager.connectionState == .connected ? Color.green.opacity(0.2) : Color.cyan.opacity(0.2))
                            .frame(width: 48, height: 48)
                        
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 20))
                            .foregroundColor(bluetoothManager.connectionState == .connected ? .green : .cyan)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(bluetoothManager.connectionState == .connected
                             ? (bluetoothManager.connectedDevice?.name ?? "Connected")
                             : "Connect Equipment")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                        
                        Text(bluetoothManager.connectionState == .connected
                             ? "Tap to manage"
                             : "Sync your \(activityType.rawValue.lowercased()) data")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    if bluetoothManager.connectionState == .connected {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 10, height: 10)
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color(.systemGray6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(
                                    bluetoothManager.connectionState == .connected
                                        ? Color.green.opacity(0.3)
                                        : Color.cyan.opacity(0.2),
                                    lineWidth: 1
                                )
                        )
                )
            }
            .buttonStyle(PlainButtonStyle())
        }
    }
    
    // MARK: - GO Button
    private var goButton: some View {
        Button(action: {
            HapticManager.impact(.heavy)
            startWorkout = true
        }) {
            HStack {
                Image(systemName: "play.fill")
                    .font(.system(size: 20, weight: .bold))
                
                Text("GO")
                    .font(.title2)
                    .fontWeight(.bold)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(
                LinearGradient(
                    colors: [activityType.color, activityType.color.opacity(0.8)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .cornerRadius(16)
            .shadow(color: activityType.color.opacity(0.4), radius: 12, y: 6)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 40)
    }
}

// MARK: - Goal Type Button
struct GoalTypeButton: View {
    let goalType: CardioGoalType
    let isSelected: Bool
    let color: Color
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                Image(systemName: goalType.icon)
                    .font(.system(size: 18))
                
                Text(goalType.rawValue)
                    .font(.caption2)
                    .fontWeight(.medium)
            }
            .foregroundColor(isSelected ? .white : .primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? color : Color(.systemGray5))
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Time Goal Picker
struct TimeGoalPicker: View {
    @Binding var minutes: Int
    let color: Color
    
    private let timeOptions = [10, 15, 20, 25, 30, 45, 60, 90]
    
    var body: some View {
        VStack(spacing: 16) {
            // Large display
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text("\(minutes)")
                    .font(.system(size: 64, weight: .bold, design: .rounded))
                    .foregroundColor(color)
                
                Text("min")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
            
            // Quick select buttons
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(timeOptions, id: \.self) { time in
                        Button(action: {
                            HapticManager.selectionChanged()
                            minutes = time
                        }) {
                            Text("\(time)")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(minutes == time ? .white : .primary)
                                .frame(width: 50, height: 40)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(minutes == time ? color : Color(.systemGray5))
                                )
                        }
                    }
                }
            }
            
            // Slider for fine control
            Slider(value: Binding(
                get: { Double(minutes) },
                set: { minutes = Int($0) }
            ), in: 5...120, step: 5)
            .tint(color)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6).opacity(0.5))
        )
    }
}

// MARK: - Distance Goal Picker
struct DistanceGoalPicker: View {
    @Binding var distance: Double
    let color: Color
    
    private let distanceOptions: [Double] = [1.0, 2.0, 3.0, 5.0, 10.0, 15.0, 21.1, 42.2]
    
    var body: some View {
        VStack(spacing: 16) {
            // Large display
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(String(format: "%.1f", distance))
                    .font(.system(size: 64, weight: .bold, design: .rounded))
                    .foregroundColor(color)
                
                Text("km")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
            
            // Quick select buttons
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(distanceOptions, id: \.self) { dist in
                        Button(action: {
                            HapticManager.selectionChanged()
                            distance = dist
                        }) {
                            Text(dist == 21.1 ? "Half" : dist == 42.2 ? "Full" : String(format: "%.0f", dist))
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(distance == dist ? .white : .primary)
                                .frame(width: 45, height: 40)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(distance == dist ? color : Color(.systemGray5))
                                )
                        }
                    }
                }
            }
            
            // Slider for fine control
            Slider(value: $distance, in: 0.5...50, step: 0.5)
                .tint(color)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6).opacity(0.5))
        )
    }
}

// MARK: - Calorie Goal Picker
struct CalorieGoalPicker: View {
    @Binding var calories: Int
    let color: Color
    
    private let calorieOptions = [100, 200, 300, 400, 500, 750, 1000]
    
    var body: some View {
        VStack(spacing: 16) {
            // Large display
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text("\(calories)")
                    .font(.system(size: 64, weight: .bold, design: .rounded))
                    .foregroundColor(color)
                
                Text("cal")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
            
            // Quick select buttons
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(calorieOptions, id: \.self) { cal in
                        Button(action: {
                            HapticManager.selectionChanged()
                            calories = cal
                        }) {
                            Text("\(cal)")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(calories == cal ? .white : .primary)
                                .frame(width: 50, height: 40)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(calories == cal ? color : Color(.systemGray5))
                                )
                        }
                    }
                }
            }
            
            // Slider for fine control
            Slider(value: Binding(
                get: { Double(calories) },
                set: { calories = Int($0) }
            ), in: 50...1500, step: 50)
            .tint(color)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6).opacity(0.5))
        )
    }
}

// MARK: - Recommendation Bubble
struct RecommendationBubble: View {
    let icon: String
    let value: String
    let unit: String
    let color: Color
    let onTap: () -> Void
    
    var body: some View {
        Button(action: {
            HapticManager.selectionChanged()
            onTap()
        }) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(color)
                
                HStack(alignment: .lastTextBaseline, spacing: 2) {
                    Text(value)
                        .font(.headline)
                        .fontWeight(.bold)
                    Text(unit)
                        .font(.caption2)
                }
                .foregroundColor(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(color.opacity(0.1))
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    CardioGoalSetupView(activityType: .treadmill)
        .environmentObject(UserManager.shared)
}
