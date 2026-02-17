//
//  ChallengeCreationFlowInline.swift
//  Fit33
//
//  Challenge creation flow matching autogen style (with tab bar visible)
//

import SwiftUI

struct ChallengeCreationFlowInline: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    let friend: Friend
    
    @State private var currentStep: Int = 1
    @State private var selectedMode: ChallengeMode?
    @State private var selectedActivity: ChallengeActivityType?
    @State private var selectedOption: ChallengeOption?
    @State private var customTarget: Int = 10000
    @State private var hydrationUnit: HydrationUnit = .ml
    @State private var selectedDuration: Int = 7
    @State private var isCreating = false
    @State private var showingSuccess = false
    @State private var showingError = false
    @State private var isNavigatingForward = true
    
    private var slideTransition: AnyTransition {
        AnyTransition.asymmetric(
            insertion: .move(edge: isNavigatingForward ? .trailing : .leading),
            removal: .move(edge: isNavigatingForward ? .leading : .trailing)
        )
    }
    
    var body: some View {
        ZStack {
            // Blue orbs background (matching autogen)
            AnimatedOrbBackground.home(colorScheme: colorScheme)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Progress indicator at top (matching autogen style)
                progressIndicator
                    .padding(.top, 8)
                    .padding(.bottom, 8)
                
                // Header (fixed height for consistency)
                VStack(spacing: 4) {
                    Text(stepTitle)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .frame(height: 56)
                    
                    Text(stepSubtitle)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.8))
                        .frame(height: 20)
                }
                .padding(.horizontal, 20)
                
                // Content area (slides between steps)
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        ZStack {
                            if currentStep == 1 {
                                modeSelectionContent
                                    .transition(slideTransition)
                            }
                            
                            if currentStep == 2 {
                                activityTypeContent
                                    .transition(slideTransition)
                            }
                            
                            if currentStep == 3 {
                                challengeOptionsContent
                                    .transition(slideTransition)
                            }
                            
                            if currentStep == 4 {
                                durationContent
                                    .transition(slideTransition)
                            }
                            
                            if currentStep == 5 {
                                reviewContent
                                    .transition(slideTransition)
                            }
                        }
                        .animation(.easeInOut(duration: 0.35), value: currentStep)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 120)
                }
                
                Spacer(minLength: 0)
                
                // Bottom button bar (fixed at bottom)
                bottomButtonBar
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
            }
        }
        .navigationTitle("Challenge \(friend.displayName)")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Challenge Sent! 🎯", isPresented: $showingSuccess) {
            Button("Done") {
                print("✅ [CHALLENGE FLOW] Success - dismissing")
                dismiss()
            }
        } message: {
            Text("\(friend.friendName?.components(separatedBy: " ").first ?? "Your friend") will receive a notification!")
        }
        .alert("Failed to Send Challenge 😔", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text("Please try again.")
        }
        .onAppear {
            print("🏆 [CHALLENGE FLOW INLINE] View appeared for \(friend.displayName)")
        }
    }
    
    // MARK: - Progress Indicator
    
    private var progressIndicator: some View {
        HStack(spacing: 8) {
            ForEach(1...5, id: \.self) { step in
                Capsule()
                    .fill(currentStep >= step ? Color.blue : Color.gray.opacity(0.3))
                    .frame(width: currentStep == step ? 40 : 24, height: 6)
                    .animation(.easeInOut(duration: 0.3), value: currentStep)
            }
        }
    }
    
    // MARK: - Step Content
    
    private var stepTitle: String {
        switch currentStep {
        case 1: return "Choose Your Challenge Mode"
        case 2: return "What type of challenge?"
        case 3: return selectedActivity.map { "Choose Your \($0.emoji) \($0.rawValue) Goal" } ?? "Choose Goal"
        case 4: return "How long should it last?"
        case 5: return "Review Your Challenge"
        default: return ""
        }
    }
    
    private var stepSubtitle: String {
        switch currentStep {
        case 1: return "Pick the type that fits your goals"
        case 2: return "Choose the activity to track"
        case 3: return "Set a custom target or pick a preset"
        case 4: return "Choose the duration in days"
        case 5: return "Make sure everything looks good"
        default: return ""
        }
    }
    
    // Import content from ChallengeCreationFlow
    private var modeSelectionContent: some View {
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
    
    private var activityTypeContent: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
            ForEach(ChallengeActivityType.allCases, id: \.self) { activity in
                ActivityTypeCard(
                    activity: activity,
                    isSelected: selectedActivity == activity,
                    onSelect: {
                        print("✅ [CHALLENGE FLOW] Selected activity: \(activity.rawValue)")
                        HapticManager.impact(.light)
                        selectedActivity = activity
                        customTarget = getDefaultCustomTarget(activity)
                        hydrationUnit = .ml
                        selectedOption = nil
                    }
                )
            }
        }
        .padding(.top, 20)
    }
    
    private var challengeOptionsContent: some View {
        VStack(spacing: 16) {
            if let activity = selectedActivity {
                // Custom input (reuse from ChallengeCreationFlow)
                Text("Custom or preset options here")
                    .foregroundColor(.white)
            }
        }
        .padding(.top, 20)
    }
    
    private var durationContent: some View {
        VStack(spacing: 16) {
            ForEach([3, 7, 14, 30], id: \.self) { days in
                ChallengeDurationCard(
                    days: days,
                    isSelected: selectedDuration == days,
                    onSelect: {
                        print("✅ [CHALLENGE FLOW] Selected duration: \(days) days")
                        HapticManager.impact(.light)
                        selectedDuration = days
                    }
                )
            }
        }
        .padding(.top, 20)
    }
    
    private var reviewContent: some View {
        VStack(spacing: 24) {
            // Review details
            Text("Review screen here")
                .foregroundColor(.white)
        }
        .padding(.top, 20)
    }
    
    // MARK: - Bottom Button Bar
    
    private var bottomButtonBar: some View {
        HStack(spacing: 12) {
            if currentStep < 5 {
                GradientButton(
                    title: "Continue",
                    icon: "arrow.right",
                    gradientColors: [.blue, .cyan],
                    isEnabled: canContinue,
                    isLoading: false
                ) {
                    print("➡️ [CHALLENGE FLOW] Continue from step \(currentStep)")
                    isNavigatingForward = true
                    currentStep += 1
                }
            } else {
                GradientButton(
                    title: "Send Challenge",
                    icon: "paperplane.fill",
                    gradientColors: [.green, .mint],
                    isEnabled: canSendChallenge,
                    isLoading: isCreating
                ) {
                    print("📤 [CHALLENGE FLOW] Sending challenge")
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
        case 4: return true
        default: return false
        }
    }
    
    private var canSendChallenge: Bool {
        selectedMode != nil && selectedActivity != nil && selectedOption != nil
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
    
    private func sendChallenge() async {
        // Placeholder - will implement full logic
        print("📤 [CHALLENGE FLOW] Sending challenge...")
        isCreating = true
        
        // Simulate API call
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        
        isCreating = false
        showingSuccess = true
    }
}
