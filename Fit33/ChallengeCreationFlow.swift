//
//  ChallengeCreationFlow.swift
//  Fit33
//
//  Multi-screen challenge creation flow with blue orbs background
//

import SwiftUI

// MARK: - Challenge Mode
enum ChallengeMode: String, CaseIterable {
    case accountability = "Accountability"
    case competition = "Competition"
    
    var title: String {
        switch self {
        case .accountability: return "Accountability Buddy"
        case .competition: return "Head-to-Head Battle"
        }
    }
    
    var subtitle: String {
        switch self {
        case .accountability: return "We're in this together"
        case .competition: return "Only one can win"
        }
    }
    
    var description: String {
        switch self {
        case .accountability:
            return "Same goal. Same grind. You both commit to hitting the target every day — and keep each other honest. No scores, no losers. Just a shared streak you build together."
        case .competition:
            return "Go head-to-head. Every step, rep, and drop counts. One scoreboard, one winner, and permanent bragging rights."
        }
    }
    
    var emoji: String {
        switch self {
        case .accountability: return "🤝"
        case .competition: return "⚔️"
        }
    }
    
    /// Prefix embedded in challenge title so the widget can detect mode
    var titlePrefix: String {
        switch self {
        case .accountability: return "🤝"
        case .competition: return "⚔️"
        }
    }
    
    var gradientColors: [Color] {
        switch self {
        case .accountability: return [.blue, .cyan]
        case .competition: return [.orange, .red]
        }
    }
    
    var accentColor: Color {
        switch self {
        case .accountability: return .cyan
        case .competition: return .orange
        }
    }
    
    /// Detect mode from a challenge title prefix
    static func from(title: String) -> ChallengeMode {
        if title.hasPrefix("🤝") { return .accountability }
        if title.hasPrefix("⚔️") { return .competition }
        // Legacy challenges default to competition (original behavior)
        return .competition
    }
}

// MARK: - Challenge Activity Type
enum ChallengeActivityType: String, CaseIterable {
    case walk = "Walk"
    case run = "Run"
    case lift = "Lift"
    case hydrate = "Hydrate"
    case steps = "Steps"
    case calories = "Calories"
    case protein = "Protein"
    case activeMinutes = "Active Minutes"
    case workoutStreak = "Workout Streak"
    case sleep = "Sleep"
    
    var emoji: String {
        switch self {
        case .walk: return "🚶"
        case .run: return "🏃"
        case .lift: return "💪"
        case .hydrate: return "💧"
        case .steps: return "👣"
        case .calories: return "🔥"
        case .protein: return "🥩"
        case .activeMinutes: return "⏱️"
        case .workoutStreak: return "🔥"
        case .sleep: return "😴"
        }
    }
    
    var gradientColors: [Color] {
        switch self {
        case .walk: return [.green, .mint]
        case .run: return [.orange, .yellow]
        case .lift: return [.red, .pink]
        case .hydrate: return [.blue, .cyan]
        case .steps: return [.purple, .blue]
        case .calories: return [.orange, .red]
        case .protein: return [.pink, .purple]
        case .activeMinutes: return [.cyan, .blue]
        case .workoutStreak: return [.red, .orange]
        case .sleep: return [.indigo, .purple]
        }
    }
}

// MARK: - Challenge Option
struct ChallengeOption: Identifiable {
    var id: String { "\(title)-\(dailyTarget)-\(unit)-\(isCustom)" }
    let title: String
    let description: String
    let dailyTarget: Int
    let unit: String
    let isPreset: Bool
    let isCustom: Bool
}

// MARK: - Hydration Unit
enum HydrationUnit: String, CaseIterable {
    case ml = "ml"
    case oz = "oz"
    
    var displayName: String {
        switch self {
        case .ml: return "Milliliters (ml)"
        case .oz: return "Ounces (oz)"
        }
    }
    
    func convert(value: Int, to targetUnit: HydrationUnit) -> Int {
        if self == targetUnit { return value }
        
        switch (self, targetUnit) {
        case (.ml, .oz): return Int(Double(value) / 29.5735) // ml to oz
        case (.oz, .ml): return Int(Double(value) * 29.5735) // oz to ml
        default: return value
        }
    }
}

// MARK: - Main Challenge Creation Flow
struct ChallengeCreationFlow: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    let friend: Friend
    
    @State private var currentStep: Int = 1
    @State private var selectedMode: ChallengeMode?
    @State private var selectedActivity: ChallengeActivityType?
    @State private var selectedOption: ChallengeOption?
    @State private var customTarget: Int = 10000 // Default custom target
    @State private var hydrationUnit: HydrationUnit = .ml
    @State private var selectedDuration: Int = 7
    @State private var isCreating = false
    @State private var showingSuccess = false
    @State private var showingError = false
    @State private var isCustomDuration = false
    @State private var customDurationText = ""
    @FocusState private var durationFieldFocused: Bool
    
    var body: some View {
        ZStack {
            // Blue orbs background (matching auto-gen)
            AnimatedOrbBackground.home(colorScheme: colorScheme)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                header
                
                // Content based on current step
                ScrollView {
                    VStack(spacing: 24) {
                        switch currentStep {
                        case 1:
                            modeSelectionScreen
                        case 2:
                            activityTypeScreen
                        case 3:
                            challengeOptionsScreen
                        case 4:
                            durationScreen
                        case 5:
                            reviewScreen
                        default:
                            EmptyView()
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 160)
                }
                .scrollIndicators(.hidden)
            }
            .onAppear {
                print("🏆 [CHALLENGE FLOW] View appeared - challenging \(friend.displayName)")
                print("🏆 [CHALLENGE FLOW] Current step: \(currentStep)")
            }
            .onChange(of: currentStep) { oldValue, newValue in
                print("🏆 [CHALLENGE FLOW] Step changed: \(oldValue) → \(newValue)")
                switch newValue {
                case 1: print("📍 [CHALLENGE FLOW] Screen 1: Mode Selection")
                case 2: print("📍 [CHALLENGE FLOW] Screen 2: Activity Type (selected mode: \(selectedMode?.title ?? "none"))")
                case 3: print("📍 [CHALLENGE FLOW] Screen 3: Challenge Options (selected activity: \(selectedActivity?.rawValue ?? "none"))")
                case 4: print("📍 [CHALLENGE FLOW] Screen 4: Duration (selected option: \(selectedOption?.title ?? "none"))")
                case 5: print("📍 [CHALLENGE FLOW] Screen 5: Review (duration: \(selectedDuration) days)")
                default: break
                }
            }
            
            // Bottom navigation
            VStack {
                Spacer()
                navigationButtons
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
            }
        }
        .navigationBarBackButtonHidden(true)
        .alert("Challenge Sent! 🎯", isPresented: $showingSuccess) {
            Button("Done") {
                print("✅ [CHALLENGE FLOW] Success alert dismissed - closing flow")
                dismiss()
            }
        } message: {
            Text("\(friend.friendName?.components(separatedBy: " ").first ?? "Your friend") will receive a notification to accept your challenge!")
        }
        .alert("Failed to Send Challenge 😔", isPresented: $showingError) {
            Button("OK") {
                print("❌ [CHALLENGE FLOW] Error alert dismissed")
            }
        } message: {
            Text("There was an issue sending your challenge. Please try again.")
        }
        .onDisappear {
            print("👋 [CHALLENGE FLOW] View disappeared")
        }
    }
    
    // MARK: - Header
    
    private var header: some View {
        HStack {
            Button(action: {
                if currentStep > 1 {
                    print("⬅️ [CHALLENGE FLOW] Back button tapped - going from step \(currentStep) to \(currentStep - 1)")
                    withAnimation(.spring(response: 0.3)) {
                        currentStep -= 1
                    }
                } else {
                    print("❌ [CHALLENGE FLOW] Close button tapped - dismissing flow")
                    dismiss()
                }
            }) {
                Image(systemName: currentStep > 1 ? "chevron.left" : "xmark")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
            }
            
            Spacer()
            
            Text("Challenge \(friend.displayName)")
                .font(.headline)
                .foregroundColor(.white)
            
            Spacer()
            
            // Progress indicator
            Text("\(Int(Double(currentStep) / 5.0 * 100))%")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .frame(width: 44)
        }
        .padding(.horizontal, 20)
        .padding(.top, 60)
        .padding(.bottom, 20)
    }
    
    // MARK: - Screen 1: Mode Selection
    
    private var modeSelectionScreen: some View {
        VStack(spacing: 24) {
            Text("Choose Your Challenge Mode")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
            
            Text("Pick the type of challenge that fits your goals")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.8))
                .multilineTextAlignment(.center)
            
            VStack(spacing: 16) {
                ForEach(ChallengeMode.allCases, id: \.self) { mode in
                    ModeSelectionCard(
                        mode: mode,
                        isSelected: selectedMode == mode,
                        onSelect: {
                            print("✅ [CHALLENGE FLOW] Selected mode: \(mode.title)")
                            HapticManager.impact(.light)
                            selectedMode = mode
                        }
                    )
                }
            }
            .padding(.top, 20)
        }
    }
    
    // MARK: - Screen 2: Activity Type
    
    private var activityTypeScreen: some View {
        VStack(spacing: 24) {
            Text("What type of challenge?")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
            
            Text("Choose the activity you want to track")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.8))
                .multilineTextAlignment(.center)
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(ChallengeActivityType.allCases, id: \.self) { activity in
                    ActivityTypeCard(
                        activity: activity,
                        isSelected: selectedActivity == activity,
                        onSelect: {
                            print("✅ [CHALLENGE FLOW] Selected activity: \(activity.rawValue)")
                            HapticManager.impact(.light)
                            selectedActivity = activity
                            // Reset custom target to default for new activity
                            customTarget = getDefaultCustomTarget(activity)
                            print("🔢 [CHALLENGE FLOW] Reset custom target to: \(customTarget)")
                            // Reset hydration unit to ml
                            hydrationUnit = .ml
                            // Reset selected option when changing activity
                            selectedOption = nil
                        }
                    )
                }
            }
            .padding(.top, 20)
        }
    }
    
    // MARK: - Screen 3: Challenge Options
    
    private var challengeOptionsScreen: some View {
        VStack(spacing: 24) {
            if let activity = selectedActivity {
                Text("Choose Your \(activity.emoji) \(activity.rawValue) Goal")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                
                Text(customGoalSubtitle(for: activity))
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                
                ScrollView {
                    VStack(spacing: 16) {
                        // Custom Input Card (always first)
                        CustomTargetCard(
                            activity: activity,
                            customTarget: $customTarget,
                            hydrationUnit: $hydrationUnit,
                            isSelected: selectedOption?.isCustom == true,
                            gradientColors: activity.gradientColors,
                            onSelect: {
                                print("✅ [CHALLENGE FLOW] Selected custom option: \(customTarget) \(activity == .hydrate ? hydrationUnit.rawValue : getUnitForActivity(activity))")
                                HapticManager.impact(.medium)
                                let unit = activity == .hydrate ? hydrationUnit.rawValue : getUnitForActivity(activity)
                                withAnimation(.spring(response: 0.3)) {
                                    selectedOption = ChallengeOption(
                                        title: "Custom \(activity.rawValue) Challenge",
                                        description: "Daily target: \(customTarget) \(unit)",
                                        dailyTarget: customTarget,
                                        unit: unit,
                                        isPreset: false,
                                        isCustom: true
                                    )
                                }
                                print("📊 [CHALLENGE FLOW] Custom option set - isCustom: true")
                            }
                        )
                        
                        // Divider with "OR" text
                        HStack(spacing: 12) {
                            Rectangle()
                                .fill(Color.white.opacity(0.3))
                                .frame(height: 1)
                            
                            Text("OR")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.white.opacity(0.6))
                            
                            Rectangle()
                                .fill(Color.white.opacity(0.3))
                                .frame(height: 1)
                        }
                        .padding(.vertical, 8)
                        
                        // Preset Options
                        ForEach(getOptionsForActivity(activity)) { option in
                            ChallengeOptionCard(
                                option: option,
                                isSelected: selectedOption?.id == option.id && selectedOption?.isCustom == false,
                                gradientColors: activity.gradientColors,
                                onSelect: {
                                    print("✅ [CHALLENGE FLOW] Selected preset: \(option.title) (ID: \(option.id))")
                                    print("📊 [CHALLENGE FLOW] Current selectedOption ID: \(selectedOption?.id ?? "nil")")
                                    HapticManager.impact(.medium)
                                    withAnimation(.spring(response: 0.3)) {
                                        selectedOption = option
                                    }
                                    print("📊 [CHALLENGE FLOW] New selectedOption ID: \(selectedOption?.id ?? "nil"), isCustom: false")
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 40)
                }
                .frame(maxHeight: .infinity)
            }
        }
    }
    
    // MARK: - Screen 4: Duration
    
    private var durationScreen: some View {
        VStack(spacing: 16) {
            Text("How long should the challenge last?")
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
            
            Text("Set a custom duration or pick a preset")
                .font(.caption)
                .foregroundColor(.white.opacity(0.8))
                .multilineTextAlignment(.center)
            
            VStack(spacing: 10) {
                // Custom duration input
                Button(action: {
                    HapticManager.impact(.medium)
                    isCustomDuration = true
                    customDurationText = "\(selectedDuration)"
                    durationFieldFocused = true
                }) {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(LinearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 46, height: 46)
                                .shadow(color: isCustomDuration ? Color.blue.opacity(0.3) : .clear, radius: 6, x: 0, y: 3)
                            
                            Text("✏️")
                                .font(.system(size: 22))
                        }
                        
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Custom Duration")
                                .font(.body)
                                .fontWeight(isCustomDuration ? .bold : .semibold)
                                .foregroundColor(.white)
                            
                            Text("Set your own number of days")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.6))
                        }
                        
                        Spacer()
                        
                        if isCustomDuration {
                            HStack(spacing: 6) {
                                TextField("", text: $customDurationText)
                                    .font(.system(size: 20, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                                    .keyboardType(.numberPad)
                                    .multilineTextAlignment(.center)
                                    .frame(width: 50)
                                    .focused($durationFieldFocused)
                                    .onChange(of: durationFieldFocused) { _, focused in
                                        if !focused, let val = Int(customDurationText), val >= 1, val <= 365 {
                                            selectedDuration = val
                                        }
                                    }
                                
                                Text("days")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.7))
                            }
                            
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 22))
                                .foregroundStyle(LinearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color(white: 0.14))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(
                                isCustomDuration
                                    ? AnyShapeStyle(LinearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing))
                                    : AnyShapeStyle(Color.white.opacity(0.06)),
                                lineWidth: isCustomDuration ? 2 : 1
                            )
                    )
                    .shadow(color: isCustomDuration ? Color.blue.opacity(0.3) : .clear, radius: 12, x: 0, y: 6)
                }
                .buttonStyle(.plain)
                
                // ---- or ---- divider
                HStack(spacing: 12) {
                    Rectangle()
                        .fill(Color.white.opacity(0.3))
                        .frame(height: 1)
                    Text("OR")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.white.opacity(0.6))
                    Rectangle()
                        .fill(Color.white.opacity(0.3))
                        .frame(height: 1)
                }
                .padding(.vertical, 2)
                
                // Preset duration options
                ForEach([3, 7, 14, 30], id: \.self) { days in
                    ChallengeDurationCard(
                        days: days,
                        isSelected: selectedDuration == days && !isCustomDuration,
                        onSelect: {
                            isCustomDuration = false
                            durationFieldFocused = false
                            print("✅ [CHALLENGE FLOW] Selected duration: \(days) days")
                            HapticManager.impact(.light)
                            selectedDuration = days
                        }
                    )
                }
            }
        }
    }
    
    // MARK: - Screen 5: Review
    
    private var reviewScreen: some View {
        VStack(spacing: 24) {
            Text("Review Your Challenge")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
            
            Text("Make sure everything looks good before sending")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.8))
                .multilineTextAlignment(.center)
            
            VStack(spacing: 16) {
                // VS Display
                HStack(spacing: 12) {
                    // Your photo
                    if let cachedImage = ProfilePhotoCache.shared.cachedImage {
                        Image(uiImage: cachedImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 60, height: 60)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.blue, lineWidth: 3))
                    } else {
                        Circle()
                            .fill(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 60, height: 60)
                    }
                    
                    Text("VS")
                        .font(.title3)
                        .fontWeight(.black)
                        .foregroundColor(.white)
                    
                    // Friend photo
                    CachedFriendPhoto(
                        friendId: friend.friendId.uuidString,
                        photoUrl: friend.profilePhotoUrl,
                        name: friend.friendName ?? "Friend",
                        size: 60,
                        showGradientRing: true,
                        gradientColors: [.orange, .red]
                    )
                }
                .padding(.top, 20)
                
                // Challenge details
                VStack(spacing: 12) {
                    if let mode = selectedMode {
                        ReviewRow(title: "Mode", value: "\(mode.emoji) \(mode.title)")
                    }
                    
                    if let activity = selectedActivity {
                        ReviewRow(title: "Activity", value: "\(activity.emoji) \(activity.rawValue)")
                    }
                    
                    if let option = selectedOption {
                        ReviewRow(title: "Goal", value: option.title)
                        ReviewRow(title: "Daily Target", value: "\(option.dailyTarget) \(option.unit)")
                    }
                    
                    ReviewRow(title: "Duration", value: "\(selectedDuration) days")
                }
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.white.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )
                )
            }
            .padding(.top, 20)
        }
    }
    
    // MARK: - Navigation Buttons
    
    private var navigationButtons: some View {
        HStack(spacing: 12) {
            if currentStep < 5 {
                GradientButton(
                    title: "Continue",
                    icon: "arrow.right",
                    gradientColors: [.blue, .cyan],
                    isEnabled: canContinue,
                    isLoading: false
                ) {
                    print("➡️ [CHALLENGE FLOW] Continue button tapped from step \(currentStep)")
                    withAnimation(.spring(response: 0.3)) {
                        currentStep += 1
                    }
                    HapticManager.impact(.medium)
                }
            } else {
                GradientButton(
                    title: "Send Challenge",
                    icon: "paperplane.fill",
                    gradientColors: [.green, .mint],
                    isEnabled: canSendChallenge,
                    isLoading: isCreating
                ) {
                    print("📤 [CHALLENGE FLOW] Send Challenge button tapped")
                    Task {
                        await sendChallenge()
                    }
                }
            }
        }
    }
    
    // MARK: - Helpers
    
    private var canContinue: Bool {
        switch currentStep {
        case 1: return selectedMode != nil
        case 2: return selectedActivity != nil
        case 3: return selectedOption != nil
        case 4: return true // Duration always has a default
        default: return false
        }
    }
    
    private var canSendChallenge: Bool {
        selectedMode != nil && selectedActivity != nil && selectedOption != nil
    }
    
    private func getUnitForActivity(_ activity: ChallengeActivityType) -> String {
        switch activity {
        case .walk, .run: return "minutes"
        case .lift: return "workouts"
        case .hydrate: return "ml"
        case .steps: return "steps"
        case .calories: return "calories"
        case .protein: return "grams"
        case .activeMinutes: return "minutes"
        case .workoutStreak: return "workouts"
        case .sleep: return "hours"
        }
    }
    
    private func getDefaultCustomTarget(_ activity: ChallengeActivityType) -> Int {
        switch activity {
        case .walk: return 30
        case .run: return 20
        case .lift: return 5
        case .hydrate: return 2000
        case .steps: return 10000
        case .calories: return 500
        case .protein: return 150
        case .activeMinutes: return 30
        case .workoutStreak: return 1
        case .sleep: return 7
        }
    }
    
    private func customGoalSubtitle(for activity: ChallengeActivityType) -> String {
        switch activity {
        case .steps: return "Set your daily step target or pick a preset below"
        case .walk: return "Choose how many minutes you'll walk each day"
        case .run: return "Set your daily running goal in minutes"
        case .lift: return "How many workouts per week can you commit to?"
        case .hydrate: return "Track your daily water intake goal"
        case .calories: return "Set your daily active calorie burn target"
        case .protein: return "Hit your daily protein intake goal"
        case .activeMinutes: return "Total active minutes from any workout"
        case .workoutStreak: return "Complete at least one workout per day"
        case .sleep: return "Get enough sleep every night"
        }
    }
    
    private func getOptionsForActivity(_ activity: ChallengeActivityType) -> [ChallengeOption] {
        switch activity {
        case .steps:
            return [
                ChallengeOption(title: "🌤️ Morning Walker", description: "Get moving with a light daily goal", dailyTarget: 5000, unit: "steps", isPreset: true, isCustom: false),
                ChallengeOption(title: "🏆 10K Club", description: "The classic daily step goal", dailyTarget: 10000, unit: "steps", isPreset: true, isCustom: false),
                ChallengeOption(title: "🔥 Step Machine", description: "Push your limits every day", dailyTarget: 15000, unit: "steps", isPreset: true, isCustom: false)
            ]
        case .walk:
            return [
                ChallengeOption(title: "☕ Coffee Walk", description: "A quick 15-min stroll daily", dailyTarget: 15, unit: "minutes", isPreset: true, isCustom: false),
                ChallengeOption(title: "🎧 Podcast Walk", description: "30 minutes of fresh air", dailyTarget: 30, unit: "minutes", isPreset: true, isCustom: false),
                ChallengeOption(title: "🌅 Golden Hour", description: "A full 60-min walk each day", dailyTarget: 60, unit: "minutes", isPreset: true, isCustom: false)
            ]
        case .run:
            return [
                ChallengeOption(title: "🐣 Easy Jog", description: "Start with 15 mins daily", dailyTarget: 15, unit: "minutes", isPreset: true, isCustom: false),
                ChallengeOption(title: "🏃 Steady Runner", description: "Build up to 30 mins daily", dailyTarget: 30, unit: "minutes", isPreset: true, isCustom: false),
                ChallengeOption(title: "⚡ Speed Demon", description: "45 mins of running every day", dailyTarget: 45, unit: "minutes", isPreset: true, isCustom: false)
            ]
        case .lift:
            return [
                ChallengeOption(title: "💪 Starter Strength", description: "3 sessions per week", dailyTarget: 3, unit: "workouts", isPreset: true, isCustom: false),
                ChallengeOption(title: "🏋️ Gym Rat", description: "5 sessions per week", dailyTarget: 5, unit: "workouts", isPreset: true, isCustom: false),
                ChallengeOption(title: "🦾 Iron Addict", description: "6 sessions — rest only once", dailyTarget: 6, unit: "workouts", isPreset: true, isCustom: false)
            ]
        case .hydrate:
            return [
                ChallengeOption(title: "💦 Stay Sipping", description: "6 cups — build the habit", dailyTarget: 1500, unit: "ml", isPreset: true, isCustom: false),
                ChallengeOption(title: "🥤 Hydro Homie", description: "8 cups — the gold standard", dailyTarget: 2000, unit: "ml", isPreset: true, isCustom: false),
                ChallengeOption(title: "🌊 Water Warrior", description: "3 liters — max hydration", dailyTarget: 3000, unit: "ml", isPreset: true, isCustom: false)
            ]
        case .calories:
            return [
                ChallengeOption(title: "🕯️ Slow Burn", description: "300 active calories daily", dailyTarget: 300, unit: "calories", isPreset: true, isCustom: false),
                ChallengeOption(title: "🔥 Torch Mode", description: "500 active calories daily", dailyTarget: 500, unit: "calories", isPreset: true, isCustom: false),
                ChallengeOption(title: "☄️ Inferno", description: "1000 active calories daily", dailyTarget: 1000, unit: "calories", isPreset: true, isCustom: false)
            ]
        case .protein:
            return [
                ChallengeOption(title: "🥚 Protein Basics", description: "100g daily — maintenance mode", dailyTarget: 100, unit: "grams", isPreset: true, isCustom: false),
                ChallengeOption(title: "🍗 Muscle Fuel", description: "150g daily — building phase", dailyTarget: 150, unit: "grams", isPreset: true, isCustom: false),
                ChallengeOption(title: "🥩 Gains Machine", description: "200g daily — max protein", dailyTarget: 200, unit: "grams", isPreset: true, isCustom: false)
            ]
        case .activeMinutes:
            return [
                ChallengeOption(title: "🧘 Gentle Movement", description: "15 active minutes daily", dailyTarget: 15, unit: "minutes", isPreset: true, isCustom: false),
                ChallengeOption(title: "⏱️ WHO Standard", description: "30 active minutes daily", dailyTarget: 30, unit: "minutes", isPreset: true, isCustom: false),
                ChallengeOption(title: "🔋 Power Hour", description: "60 active minutes daily", dailyTarget: 60, unit: "minutes", isPreset: true, isCustom: false)
            ]
        case .workoutStreak:
            return [
                ChallengeOption(title: "🎯 Daily Grinder", description: "1 workout every day — no excuses", dailyTarget: 1, unit: "workouts", isPreset: true, isCustom: false),
                ChallengeOption(title: "💪 Double Down", description: "2 sessions a day — morning & evening", dailyTarget: 2, unit: "workouts", isPreset: true, isCustom: false)
            ]
        case .sleep:
            return [
                ChallengeOption(title: "💤 Early Bird", description: "Get at least 6 hours of sleep", dailyTarget: 6, unit: "hours", isPreset: true, isCustom: false),
                ChallengeOption(title: "😴 Sleep Well", description: "7 hours — the science-backed sweet spot", dailyTarget: 7, unit: "hours", isPreset: true, isCustom: false),
                ChallengeOption(title: "🛏️ Recovery King", description: "8+ hours for peak performance", dailyTarget: 8, unit: "hours", isPreset: true, isCustom: false)
            ]
        }
    }
    
    private func sendChallenge() async {
        print("🚀 [CHALLENGE FLOW] sendChallenge() called")
        
        guard let mode = selectedMode,
              let activity = selectedActivity,
              let option = selectedOption else {
            print("❌ [CHALLENGE FLOW] Missing selections - mode:\(selectedMode?.title ?? "nil") activity:\(selectedActivity?.rawValue ?? "nil") option:\(selectedOption?.title ?? "nil")")
            return
        }
        
        print("📋 [CHALLENGE FLOW] Challenge details:")
        print("   Mode: \(mode.title)")
        print("   Activity: \(activity.rawValue)")
        print("   Option: \(option.title)")
        print("   Daily Target: \(option.dailyTarget) \(option.unit)")
        print("   Duration: \(selectedDuration) days")
        print("   Opponent: \(friend.displayName)")
        
        isCreating = true
        HapticManager.impact(.heavy)
        
        // Map to ChallengeType
        let challengeType: ChallengeType
        switch activity {
        case .walk: challengeType = .walk
        case .run: challengeType = .run
        case .lift: challengeType = .lift
        case .hydrate: challengeType = .hydrate
        case .steps: challengeType = .steps
        case .calories: challengeType = .calories
        case .protein: challengeType = .protein
        case .activeMinutes: challengeType = .activeMinutes
        case .workoutStreak: challengeType = .workoutStreak
        case .sleep: challengeType = .steps // Sleep stored as custom type, resolved by unit
        }
        
        print("🔄 [CHALLENGE FLOW] Mapped to ChallengeType: \(challengeType.rawValue)")
        
        let title = "\(mode.titlePrefix) \(activity.emoji) \(option.title)"
        print("📝 [CHALLENGE FLOW] Challenge title: \(title) (mode: \(mode.title))")
        
        // Convert hydration to ml if needed (always store in ml)
        var finalDailyTarget = option.dailyTarget
        var finalUnit = option.unit
        
        if activity == .hydrate && option.unit == "oz" {
            finalDailyTarget = HydrationUnit.oz.convert(value: option.dailyTarget, to: .ml)
            finalUnit = "ml"
            print("💧 [CHALLENGE FLOW] Converted hydration: \(option.dailyTarget)oz → \(finalDailyTarget)ml")
        }
        
        print("📤 [CHALLENGE FLOW] Calling ChallengeService.createChallenge()...")
        
        let challengeId = await ChallengeService.shared.createChallenge(
            opponentId: friend.friendId,
            type: challengeType,
            title: title,
            description: option.description,
            dailyTarget: finalDailyTarget,
            totalTarget: finalDailyTarget * selectedDuration,
            targetUnit: finalUnit,
            durationDays: selectedDuration
        )
        
        isCreating = false
        
        if let id = challengeId {
            print("✅ [CHALLENGE FLOW] Challenge created successfully! ID: \(id)")
            HapticManager.notification(.success)
            showingSuccess = true
        } else {
            print("❌ [CHALLENGE FLOW] Challenge creation failed - no ID returned")
            HapticManager.notification(.error)
            showingError = true
        }
    }
}

// MARK: - Supporting Views

struct ModeSelectionCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let mode: ChallengeMode
    let isSelected: Bool
    let onSelect: () -> Void
    
    private var bulletPoints: [String] {
        switch mode {
        case .accountability:
            return [
                "Both commit to the same daily goal",
                "Build a shared streak together 🔥",
                "No scores — just consistency",
                "Get nudged if your buddy misses a day"
            ]
        case .competition:
            return [
                "Real-time scoreboard tracks everything",
                "Crown 👑 goes to whoever's ahead",
                "Daily winner & overall winner",
                "Bragging rights on the line"
            ]
        }
    }
    
    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(mode.emoji)
                            .font(.system(size: 36))
                        
                        Text(mode.title)
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        
                        Text(mode.subtitle)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(LinearGradient(colors: mode.gradientColors, startPoint: .leading, endPoint: .trailing))
                    }
                    
                    Spacer()
                    
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(LinearGradient(colors: mode.gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing))
                    }
                }
                
                // Bullet points
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(bulletPoints, id: \.self) { point in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(LinearGradient(colors: mode.gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 5, height: 5)
                            Text(point)
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.75))
                        }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                ZStack {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(mode.gradientColors[0].opacity(colorScheme == .dark ? 0.15 : 0.08))
                            .offset(y: 8)
                            .blur(radius: 4)
                    }
                    
                    RoundedRectangle(cornerRadius: 21, style: .continuous)
                        .fill(Color.black.opacity(colorScheme == .dark ? 0.2 : 0.04))
                        .offset(y: 4)
                    
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: colorScheme == .dark
                                    ? [Color(white: 0.18), Color(white: 0.12)]
                                    : [Color.white, Color.white.opacity(0.95)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
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
                    
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: isSelected ? mode.gradientColors : [mode.gradientColors[0].opacity(0.3), mode.gradientColors[1].opacity(0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: isSelected ? 2 : 1
                        )
                }
            )
            .shadow(color: isSelected ? mode.gradientColors[0].opacity(0.3) : .clear, radius: 12, x: 0, y: 6)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct ActivityTypeCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let activity: ChallengeActivityType
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 8) {
                Text(activity.emoji)
                    .font(.system(size: 36))
                
                Text(activity.rawValue)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .bold : .semibold)
                    .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 95)
            .background(
                ZStack {
                    // Bottom shadow layer (deepest) - colored glow for selected
                    if isSelected {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(activity.gradientColors[0].opacity(colorScheme == .dark ? 0.15 : 0.08))
                            .offset(y: 8)
                            .blur(radius: 4)
                    }
                    
                    // Middle shadow layer
                    RoundedRectangle(cornerRadius: 21, style: .continuous)
                        .fill(Color.black.opacity(colorScheme == .dark ? 0.2 : 0.04))
                        .offset(y: 4)
                    
                    // Main card background
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: colorScheme == .dark
                                    ? [Color(white: 0.18), Color(white: 0.12)]
                                    : [Color.white, Color.white.opacity(0.95)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    
                    // Inner highlight (top edge glow)
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
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
                    
                    // Colored accent border (subtle when unselected, bold when selected)
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: isSelected ? activity.gradientColors : [activity.gradientColors[0].opacity(0.3), activity.gradientColors[1].opacity(0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: isSelected ? 2 : 1
                        )
                }
            )
            .scaleEffect(isSelected ? 1.03 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct CustomTargetCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let activity: ChallengeActivityType
    @Binding var customTarget: Int
    @Binding var hydrationUnit: HydrationUnit
    let isSelected: Bool
    let gradientColors: [Color]
    let onSelect: () -> Void
    
    @State private var editText: String = ""
    @State private var isEditingText: Bool = false
    @FocusState private var textFieldFocused: Bool
    
    private var stepAmount: Int {
        switch activity {
        case .walk, .run: return 5 // minutes
        case .lift: return 1 // workouts
        case .hydrate: return 250 // ml or oz
        case .steps: return 500 // steps
        case .calories: return 50 // calories
        case .protein: return 10 // grams
        case .activeMinutes: return 5 // minutes
        case .workoutStreak: return 1 // workouts
        case .sleep: return 1 // hours
        }
    }
    
    private var minValue: Int {
        switch activity {
        case .walk, .run: return 5
        case .lift: return 1
        case .hydrate: return 250
        case .steps: return 1000
        case .calories: return 100
        case .protein: return 50
        case .activeMinutes: return 5
        case .workoutStreak: return 1
        case .sleep: return 4
        }
    }
    
    private var maxValue: Int {
        switch activity {
        case .walk, .run: return 120
        case .lift: return 7
        case .hydrate: return 5000
        case .steps: return 30000
        case .calories: return 2000
        case .protein: return 400
        case .activeMinutes: return 180
        case .workoutStreak: return 5
        case .sleep: return 12
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            Button(action: {
                print("🎯 [CUSTOM TARGET] Card tapped - selecting custom option")
                onSelect()
            }) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("✏️ Custom Goal")
                            .font(.headline)
                            .fontWeight(isSelected ? .bold : .semibold)
                            .foregroundColor(.white)
                        
                        Spacer()
                        
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 24))
                                .foregroundStyle(LinearGradient(colors: gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing))
                        }
                    }
                    
                    Text("Set your own daily target")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                
                // Stepper / Counter
                HStack(spacing: 16) {
                    // Minus button
                    Button(action: {
                        if customTarget > minValue {
                            print("➖ [CUSTOM TARGET] Decreased to \(customTarget - stepAmount)")
                            HapticManager.impact(.light)
                            customTarget -= stepAmount
                        }
                    }) {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(customTarget > minValue ? .white : .white.opacity(0.3))
                    }
                    .disabled(customTarget <= minValue)
                    .buttonStyle(.plain)
                    
                    // Value display — tappable to type
                    VStack(spacing: 4) {
                        if isEditingText {
                            TextField("", text: $editText)
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .multilineTextAlignment(.center)
                                .keyboardType(.numberPad)
                                .focused($textFieldFocused)
                                .onSubmit { commitEdit() }
                                .onChange(of: textFieldFocused) { _, focused in
                                    if !focused { commitEdit() }
                                }
                        } else {
                            Text("\(customTarget)")
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    editText = "\(customTarget)"
                                    isEditingText = true
                                    textFieldFocused = true
                                    onSelect()
                                }
                        }
                        
                        if activity == .hydrate {
                            // Unit picker for hydration
                            HStack(spacing: 4) {
                                ForEach(HydrationUnit.allCases, id: \.self) { unit in
                                    Button(action: {
                                        HapticManager.impact(.light)
                                        hydrationUnit = unit
                                    }) {
                                        Text(unit.rawValue)
                                            .font(.caption)
                                            .fontWeight(hydrationUnit == unit ? .bold : .regular)
                                            .foregroundColor(hydrationUnit == unit ? .white : .white.opacity(0.5))
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(
                                                Capsule()
                                                    .fill(hydrationUnit == unit ? Color.white.opacity(0.2) : Color.clear)
                                            )
                                    }
                                }
                            }
                        } else {
                            Text(getUnitText())
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                    .frame(minWidth: 120)
                    
                    // Plus button
                    Button(action: {
                        if customTarget < maxValue {
                            print("➕ [CUSTOM TARGET] Increased to \(customTarget + stepAmount)")
                            HapticManager.impact(.light)
                            customTarget += stepAmount
                        }
                    }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(customTarget < maxValue ? .white : .white.opacity(0.3))
                    }
                    .disabled(customTarget >= maxValue)
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(16)
            .background(
                ZStack {
                    // Bottom shadow layer (deepest) - colored glow for selected
                    if isSelected {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(gradientColors[0].opacity(0.15))
                            .offset(y: 8)
                            .blur(radius: 4)
                    }
                    
                    // Middle shadow layer
                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                        .fill(Color.black.opacity(colorScheme == .dark ? 0.2 : 0.04))
                        .offset(y: 4)
                    
                    // Main card background
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: colorScheme == .dark
                                    ? [Color(white: 0.18), Color(white: 0.12)]
                                    : [Color.white, Color.white.opacity(0.95)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    
                    // Inner highlight (top edge glow)
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
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
                    
                    // Colored accent border (subtle when unselected, bold when selected)
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: isSelected ? gradientColors : [gradientColors[0].opacity(0.3), gradientColors[1].opacity(0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: isSelected ? 2 : 1
                        )
                }
            )
            .scaleEffect(isSelected ? 1.02 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
            }
            .buttonStyle(PlainButtonStyle())
        }
    }
    
    private func commitEdit() {
        isEditingText = false
        if let value = Int(editText) {
            customTarget = min(maxValue, max(minValue, value))
        }
        editText = ""
    }
    
    private func getUnitText() -> String {
        switch activity {
        case .walk, .run: return "minutes per day"
        case .lift: return "workouts per week"
        case .hydrate: return hydrationUnit.rawValue + " per day"
        case .steps: return "steps per day"
        case .calories: return "calories per day"
        case .protein: return "grams per day"
        case .activeMinutes: return "minutes per day"
        case .workoutStreak: return "workouts per day"
        case .sleep: return "hours per night"
        }
    }
    
    private func getUnitForActivity(_ activity: ChallengeActivityType) -> String {
        switch activity {
        case .walk, .run: return "minutes"
        case .lift: return "workouts"
        case .hydrate: return "ml"
        case .steps: return "steps"
        case .calories: return "calories"
        case .protein: return "grams"
        case .activeMinutes: return "minutes"
        case .workoutStreak: return "workouts"
        case .sleep: return "hours"
        }
    }
}

struct ChallengeOptionCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let option: ChallengeOption
    let isSelected: Bool
    let gradientColors: [Color]
    let onSelect: () -> Void
    
    /// Extract the leading emoji from the title (if any)
    private var titleEmoji: String {
        let title = option.title
        if let first = title.unicodeScalars.first, first.properties.isEmoji && first.value > 0x238C {
            // Find where the emoji ends
            let idx = title.index(after: title.startIndex)
            // Skip any variation selectors or joiners
            var end = idx
            while end < title.endIndex {
                let scalar = title.unicodeScalars[title.unicodeScalars.index(title.unicodeScalars.startIndex, offsetBy: title.distance(from: title.startIndex, to: end))]
                if scalar.properties.isEmoji || scalar.value == 0xFE0F || scalar.value == 0x200D {
                    end = title.index(after: end)
                } else {
                    break
                }
            }
            return String(title[title.startIndex..<end]).trimmingCharacters(in: .whitespaces)
        }
        return ""
    }
    
    private var titleText: String {
        let emoji = titleEmoji
        if emoji.isEmpty { return option.title }
        return option.title.dropFirst(emoji.count).trimmingCharacters(in: .whitespaces)
    }
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 14) {
                // Gradient emoji circle (exercise library style)
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: gradientColors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 46, height: 46)
                        .shadow(color: isSelected ? gradientColors[0].opacity(0.3) : .clear, radius: 6, x: 0, y: 3)
                    
                    Text(titleEmoji.isEmpty ? "🎯" : titleEmoji)
                        .font(.system(size: 22))
                }
                
                // Title + description
                VStack(alignment: .leading, spacing: 4) {
                    Text(titleText)
                        .font(.body)
                        .fontWeight(isSelected ? .bold : .semibold)
                        .foregroundColor(.white)
                        .lineLimit(1)
                    
                    HStack(spacing: 6) {
                        Text(option.description)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.6))
                            .lineLimit(1)
                        
                        Text("•")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.4))
                        
                        Text("\(option.dailyTarget) \(option.unit)")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(isSelected ? gradientColors[0] : .white.opacity(0.8))
                    }
                }
                
                Spacer(minLength: 4)
                
                // Checkmark
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(LinearGradient(colors: gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                ZStack {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(gradientColors[0].opacity(colorScheme == .dark ? 0.15 : 0.08))
                            .offset(y: 8)
                            .blur(radius: 4)
                    }
                    
                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                        .fill(Color.black.opacity(colorScheme == .dark ? 0.2 : 0.04))
                        .offset(y: 4)
                    
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: colorScheme == .dark
                                    ? [Color(white: 0.18), Color(white: 0.12)]
                                    : [Color.white, Color.white.opacity(0.95)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
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
                    
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: isSelected ? gradientColors : [gradientColors[0].opacity(0.3), gradientColors[1].opacity(0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: isSelected ? 2 : 1
                        )
                }
            )
            .shadow(color: isSelected ? gradientColors[0].opacity(0.3) : .clear, radius: 12, x: 0, y: 6)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct ChallengeDurationCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let days: Int
    let isSelected: Bool
    let onSelect: () -> Void
    
    var durationText: String {
        switch days {
        case 3: return "3 Days\nQuick Sprint"
        case 7: return "1 Week\nStandard"
        case 14: return "2 Weeks\nCommitment"
        case 30: return "1 Month\nLong Term"
        default: return "\(days) Days"
        }
    }
    
    var body: some View {
        Button(action: onSelect) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(durationText.components(separatedBy: "\n").first ?? "")
                        .font(.title3)
                        .fontWeight(isSelected ? .bold : .semibold)
                        .foregroundColor(.white)
                    
                    Text(durationText.components(separatedBy: "\n").last ?? "")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.7))
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(LinearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing))
                }
            }
            .padding(20)
            .background(
                ZStack {
                    // Bottom shadow layer (deepest) - colored glow for selected
                    if isSelected {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.blue.opacity(0.15))
                            .offset(y: 8)
                            .blur(radius: 4)
                    }
                    
                    // Middle shadow layer
                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                        .fill(Color.black.opacity(colorScheme == .dark ? 0.2 : 0.04))
                        .offset(y: 4)
                    
                    // Main card background
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: colorScheme == .dark
                                    ? [Color(white: 0.18), Color(white: 0.12)]
                                    : [Color.white, Color.white.opacity(0.95)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    
                    // Inner highlight (top edge glow)
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
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
                    
                    // Colored accent border (subtle when unselected, bold when selected)
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: isSelected ? [.blue, .cyan] : [Color.blue.opacity(0.3), Color.cyan.opacity(0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: isSelected ? 2 : 1
                        )
                }
            )
            .scaleEffect(isSelected ? 1.02 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct ReviewRow: View {
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.7))
            Spacer()
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.white)
        }
    }
}

struct GradientButton: View {
    let title: String
    let icon: String
    let gradientColors: [Color]
    let isEnabled: Bool
    let isLoading: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: gradientColors[0]))
                        .scaleEffect(0.9)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                    
                    Text(title)
                        .font(.headline)
                        .fontWeight(.semibold)
                }
            }
            .foregroundStyle(
                isEnabled ?
                LinearGradient(colors: gradientColors, startPoint: .leading, endPoint: .trailing)
                :
                LinearGradient(colors: [.gray], startPoint: .leading, endPoint: .trailing)
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .overlay(
                Capsule()
                    .stroke(
                        isEnabled ?
                        LinearGradient(colors: gradientColors, startPoint: .leading, endPoint: .trailing)
                        :
                        LinearGradient(colors: [.gray.opacity(0.3)], startPoint: .leading, endPoint: .trailing),
                        lineWidth: 2
                    )
            )
            .shadow(color: isEnabled ? gradientColors[0].opacity(0.4) : .clear, radius: 12, x: 0, y: 6)
            .shadow(color: isEnabled ? gradientColors[1].opacity(0.3) : .clear, radius: 16, x: 0, y: 8)
            .opacity(isEnabled ? 1 : 0.6)
        }
        .disabled(!isEnabled || isLoading)
        .buttonStyle(PlainButtonStyle())
    }
}
