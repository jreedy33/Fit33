import SwiftUI
import CoreData

// MARK: - Cardio Activity Type
enum CardioActivityType: String, CaseIterable, Identifiable {
    case outdoorRun = "Outdoor Run"
    case treadmill = "Treadmill"
    case walk = "Walk"
    case indoorCycle = "Indoor Cycle"
    case outdoorCycle = "Outdoor Cycle"
    case rowing = "Rowing"
    case elliptical = "Elliptical"
    case stairClimber = "Stair Climber"
    case hiit = "HIIT"
    case swimming = "Swimming"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .outdoorRun: return "figure.run"
        case .treadmill: return "figure.run.treadmill"
        case .walk: return "figure.walk"
        case .indoorCycle: return "figure.indoor.cycle"
        case .outdoorCycle: return "figure.outdoor.cycle"
        case .rowing: return "figure.rower"
        case .elliptical: return "figure.elliptical"
        case .stairClimber: return "figure.stair.stepper"
        case .hiit: return "bolt.heart.fill"
        case .swimming: return "figure.pool.swim"
        }
    }
    
    var color: Color {
        switch self {
        case .outdoorRun: return .green
        case .treadmill: return .orange
        case .walk: return .mint
        case .indoorCycle: return .yellow
        case .outdoorCycle: return .cyan
        case .rowing: return .blue
        case .elliptical: return .purple
        case .stairClimber: return .red
        case .hiit: return .pink
        case .swimming: return .teal
        }
    }
    
    var description: String {
        switch self {
        case .outdoorRun: return "GPS • Pace • Route"
        case .treadmill: return "Speed • Incline • Distance"
        case .walk: return "Steps • Distance • Pace"
        case .indoorCycle: return "Cadence • Power • Distance"
        case .outdoorCycle: return "GPS • Speed • Elevation"
        case .rowing: return "Strokes • Power • Split"
        case .elliptical: return "Strides • Resistance • Calories"
        case .stairClimber: return "Floors • Steps • Calories"
        case .hiit: return "Intervals • Heart Rate • Burn"
        case .swimming: return "Laps • Stroke • Pace"
        }
    }
    
    var requiresGPS: Bool {
        switch self {
        case .outdoorRun, .walk, .outdoorCycle: return true
        default: return false
        }
    }
    
    var supportsBluetooth: Bool {
        switch self {
        case .treadmill, .indoorCycle, .rowing, .elliptical, .stairClimber: return true
        default: return false
        }
    }
    
    // Default goal values based on activity
    var defaultDuration: Int { // minutes
        switch self {
        case .hiit: return 20
        case .walk: return 30
        case .outdoorRun, .treadmill: return 30
        case .indoorCycle, .outdoorCycle: return 45
        case .rowing: return 20
        case .elliptical, .stairClimber: return 30
        case .swimming: return 30
        }
    }
    
    var defaultCalories: Int {
        switch self {
        case .hiit: return 300
        case .walk: return 150
        case .outdoorRun, .treadmill: return 350
        case .indoorCycle, .outdoorCycle: return 400
        case .rowing: return 250
        case .elliptical, .stairClimber: return 300
        case .swimming: return 350
        }
    }
    
    var defaultDistance: Double { // km
        switch self {
        case .walk: return 3.0
        case .outdoorRun, .treadmill: return 5.0
        case .outdoorCycle: return 15.0
        case .indoorCycle: return 10.0
        case .rowing: return 2.0
        default: return 0
        }
    }
}

// MARK: - Cardio Landing View
struct CardioLandingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject var userManager: UserManager
    @ObservedObject private var workoutManager = WorkoutManager.shared
    
    @State private var selectedActivity: CardioActivityType?
    @State private var showingGoalSetup = false
    @State private var searchText = ""
    @State private var selectedFilter: CardioFilter = .all
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Exercise.name, ascending: true)],
        predicate: NSPredicate(format: "category CONTAINS[cd] %@ OR workoutType CONTAINS[cd] %@", "cardio", "cardio"),
        animation: .default
    )
    private var cardioExercises: FetchedResults<Exercise>
    
    enum CardioFilter: String, CaseIterable {
        case all = "All"
        case machines = "Machines"
        case outdoor = "Outdoor"
        case bodyweight = "Bodyweight"
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                backgroundGradient
                
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 24) {
                        // Header
                        headerSection
                        
                        // Quick Start Activities
                        quickStartSection
                        
                        // Cardio Machines Section
                        cardioMachinesSection
                        
                        // Browse All Cardio Exercises
                        if !filteredExercises.isEmpty {
                            cardioExercisesSection
                        }
                        
                        Spacer(minLength: 100)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.primary)
                    }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingGoalSetup) {
                if let activity = selectedActivity {
                    CardioGoalSetupView(activityType: activity)
                        .environmentObject(userManager)
                }
            }
            .onChange(of: workoutManager.shouldDismissCardioFlow) { _, shouldDismiss in
                if shouldDismiss {
                    showingGoalSetup = false
                    dismiss()
                    // Reset the flag after a short delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        WorkoutManager.shared.shouldDismissCardioFlow = false
                    }
                }
            }
        }
    }
    
    // MARK: - Background
    private var backgroundGradient: some View {
        LinearGradient(
            gradient: Gradient(colors: colorScheme == .dark
                ? [Color(red: 0.05, green: 0.08, blue: 0.12), Color.black]
                : [Color(red: 0.95, green: 0.97, blue: 1.0), Color.white]),
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
    
    // MARK: - Header
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Cardio")
                .font(.system(size: 38, weight: .bold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.green, .mint],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            Text("Choose your activity and set your goals")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    // MARK: - Quick Start Section
    private var quickStartSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("QUICK START")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.secondary)
                .tracking(1)
            
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ], spacing: 12) {
                ForEach(CardioActivityType.allCases.prefix(6)) { activity in
                    QuickStartCard(activity: activity) {
                        HapticManager.impact(.medium)
                        selectedActivity = activity
                        showingGoalSetup = true
                    }
                }
            }
            
            // Show more button if needed
            if CardioActivityType.allCases.count > 6 {
                DisclosureGroup {
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12)
                    ], spacing: 12) {
                        ForEach(CardioActivityType.allCases.dropFirst(6)) { activity in
                            QuickStartCard(activity: activity) {
                                HapticManager.impact(.medium)
                                selectedActivity = activity
                                showingGoalSetup = true
                            }
                        }
                    }
                    .padding(.top, 12)
                } label: {
                    HStack {
                        Text("More Activities")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Spacer()
                    }
                    .foregroundColor(.green)
                }
            }
        }
    }
    
    // MARK: - Cardio Machines Section
    private var cardioMachinesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("EQUIPMENT")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)
                    .tracking(1)
                
                Spacer()
                
                // Bluetooth indicator
                HStack(spacing: 4) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.caption)
                    Text("Pair")
                        .font(.caption)
                }
                .foregroundColor(.cyan)
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(CardioActivityType.allCases.filter { $0.supportsBluetooth }) { activity in
                        EquipmentCard(activity: activity) {
                            HapticManager.impact(.medium)
                            selectedActivity = activity
                            showingGoalSetup = true
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Cardio Exercises Section
    private var cardioExercisesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("CARDIO EXERCISES")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)
                    .tracking(1)
                
                Spacer()
                
                Text("\(filteredExercises.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Search bar
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                
                TextField("Search exercises...", text: $searchText)
                    .font(.subheadline)
                
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color(.systemGray6))
            )
            
            // Filter chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(CardioFilter.allCases, id: \.self) { filter in
                        CardioFilterChip(
                            title: filter.rawValue,
                            isSelected: selectedFilter == filter
                        ) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedFilter = filter
                            }
                        }
                    }
                }
            }
            
            // Exercise list
            LazyVStack(spacing: 8) {
                ForEach(filteredExercises.prefix(20), id: \.id) { exercise in
                    CardioExerciseRow(exercise: exercise) {
                        // Navigate to exercise detail or start cardio with this exercise
                        HapticManager.selectionChanged()
                    }
                }
            }
        }
    }
    
    // MARK: - Filtered Exercises
    private var filteredExercises: [Exercise] {
        var exercises = Array(cardioExercises)
        
        // Apply search
        if !searchText.isEmpty {
            exercises = exercises.filter {
                $0.name?.localizedCaseInsensitiveContains(searchText) ?? false
            }
        }
        
        // Apply filter
        switch selectedFilter {
        case .all:
            break
        case .machines:
            exercises = exercises.filter {
                let equipment = $0.equipment?.lowercased() ?? ""
                return equipment.contains("machine") || equipment.contains("treadmill") ||
                       equipment.contains("bike") || equipment.contains("rower") ||
                       equipment.contains("elliptical")
            }
        case .outdoor:
            exercises = exercises.filter {
                let name = $0.name?.lowercased() ?? ""
                return name.contains("outdoor") || name.contains("run") || name.contains("walk") ||
                       name.contains("jog") || name.contains("sprint")
            }
        case .bodyweight:
            exercises = exercises.filter {
                let equipment = $0.equipment?.lowercased() ?? ""
                return equipment.contains("bodyweight") || equipment.isEmpty
            }
        }
        
        return exercises
    }
}

// MARK: - Quick Start Card
struct QuickStartCard: View {
    let activity: CardioActivityType
    let onTap: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 12) {
                // Icon
                ZStack {
                    Circle()
                        .fill(activity.color.opacity(0.2))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: activity.icon)
                        .font(.system(size: 20))
                        .foregroundColor(activity.color)
                }
                
                // Text
                VStack(alignment: .leading, spacing: 2) {
                    Text(activity.rawValue)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    Text(activity.description)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.white)
                    .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.06), radius: 8, x: 0, y: 4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(activity.color.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(CardioScaleButtonStyle())
    }
}

// MARK: - Equipment Card
struct EquipmentCard: View {
    let activity: CardioActivityType
    let onTap: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(
                            LinearGradient(
                                colors: [activity.color.opacity(0.3), activity.color.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 80, height: 80)
                    
                    Image(systemName: activity.icon)
                        .font(.system(size: 32))
                        .foregroundColor(activity.color)
                }
                
                Text(activity.rawValue)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                // Bluetooth indicator
                HStack(spacing: 2) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 8))
                    Text("BT")
                        .font(.system(size: 9, weight: .medium))
                }
                .foregroundColor(.cyan)
            }
            .frame(width: 100)
        }
        .buttonStyle(CardioScaleButtonStyle())
    }
}

// MARK: - Cardio Exercise Row
struct CardioExerciseRow: View {
    let exercise: Exercise
    let onTap: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                // Icon
                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.15))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: "figure.run")
                        .font(.system(size: 18))
                        .foregroundColor(.green)
                }
                
                // Text
                VStack(alignment: .leading, spacing: 2) {
                    Text(exercise.name ?? "Exercise")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    if let equipment = exercise.equipment {
                        Text(equipment)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.04) : Color(.systemGray6).opacity(0.5))
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Cardio Filter Chip
struct CardioFilterChip: View {
    let title: String
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            Text(title)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(isSelected ? .white : .primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.green : Color(.systemGray5))
                )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Cardio Scale Button Style
struct CardioScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

#Preview {
    CardioLandingView()
        .environmentObject(UserManager.shared)
}
