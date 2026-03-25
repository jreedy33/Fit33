import SwiftUI
import CoreData

struct WorkoutGeneratorSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var userManager: UserManager
    @EnvironmentObject var workoutManager: WorkoutManager
    @StateObject private var generatorService = WorkoutGeneratorService.shared
    
    @AppStorage("hasSeenAutoWorkoutOnboarding") private var hasSeenOnboarding = false
    @State private var currentStep: AutoWorkoutStep = .duration
    @State private var selectedDuration: WorkoutDuration = .fortyfive
    @State private var customDurationMinutes: Int = 45
    @State private var selectedPrimaryMuscles: Set<String> = []
    @State private var selectedSecondaryMuscles: Set<String> = []
    @State private var surpriseMeSelected: Bool = false
    @State private var selectedEquipment: Set<String> = []
    @State private var isGenerating = false
    @State private var generatedExercises: [GeneratedExercise] = []
    @State private var navigateToPreview = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var isNavigatingForward = true
    @State private var equipmentLocation: EquipmentLocation = .gym
    @State private var equipmentLocationInitialized = false
    
    // Slide transition based on navigation direction
    private var slideTransition: AnyTransition {
        AnyTransition.asymmetric(
            insertion: .move(edge: isNavigatingForward ? .trailing : .leading),
            removal: .move(edge: isNavigatingForward ? .leading : .trailing)
        )
    }
    
    // Haptic feedback generators (UX Audit)
    private let selectionFeedback = UISelectionFeedbackGenerator()
    private let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
    
    // Progress indicator data (UX Audit)
    private var stepNumber: Int {
        switch currentStep {
        case .welcome: return 0
        case .duration: return 1
        case .primary: return 2
        case .secondary: return 3
        case .equipment: return 4
        }
    }
    
    private var stepDescription: String {
        switch currentStep {
        case .welcome: return "Welcome"
        case .duration: return "Duration"
        case .primary: return "Target Muscles"
        case .secondary: return "Secondary Muscles"
        case .equipment: return "Equipment"
        }
    }
    
    private var totalSteps: Int { 4 } // Excluding welcome
    
    enum AutoWorkoutStep {
        case welcome
        case duration
        case primary
        case secondary
        case equipment
    }
    
    enum WorkoutDuration: CaseIterable {
        case thirty
        case fortyfive
        case sixty
        case ninety
        case custom
        
        var minutes: Int {
            switch self {
            case .thirty: return 30
            case .fortyfive: return 45
            case .sixty: return 60
            case .ninety: return 90
            case .custom: return 0 // Will use customDurationMinutes
            }
        }
        
        var displayName: String {
            switch self {
            case .thirty: return "30 min"
            case .fortyfive: return "45 min"
            case .sixty: return "60 min"
            case .ninety: return "1.5 hrs"
            case .custom: return "Custom"
            }
        }
        
        var icon: String {
            switch self {
            case .thirty: return "bolt.fill"
            case .fortyfive: return "flame.fill"
            case .sixty: return "figure.strengthtraining.traditional"
            case .ninety: return "trophy.fill"
            case .custom: return "slider.horizontal.3"
            }
        }
        
        var subtitle: String {
            switch self {
            case .thirty: return "Quick & efficient"
            case .fortyfive: return "Balanced session"
            case .sixty: return "Full workout"
            case .ninety: return "Extended training"
            case .custom: return "Set your own time"
            }
        }
        
        var color: Color {
            switch self {
            case .thirty: return .orange
            case .fortyfive: return .blue
            case .sixty: return .purple
            case .ninety: return .green
            case .custom: return .gray
            }
        }
        
        // Base rest time between sets (in seconds) - varies by duration
        var baseRestBetweenSets: Int {
            switch self {
            case .thirty: return 45
            case .fortyfive: return 60
            case .sixty: return 75
            case .ninety: return 90
            case .custom: return 60
            }
        }
    }
    
    // MARK: - Smart Exercise Count Calculator
    // This is the brain of the workout generation - considers duration, skill level, and workout style
    
    private var effectiveExerciseCount: Int {
        let minutes: Int
        if selectedDuration == .custom {
            minutes = customDurationMinutes
        } else {
            minutes = selectedDuration.minutes
        }
        
        let userLevel = userManager.currentUser?.experienceLevel?.lowercased() ?? "intermediate"
        
        // 🧠 SMART EXERCISE COUNT MATRIX
        // Based on real workout science: includes warm-up sets, working sets, transitions, and rest
        // Beginner: More rest, simpler exercises, fewer total exercises
        // Intermediate: Balanced approach
        // Advanced: Shorter rest, supersets possible, more volume
        
        switch userLevel {
        case "beginner":
            // Beginners need: longer rest (90-120s), more warm-up, simpler movements
            // ~8-10 min per exercise (3 sets x 12 reps + longer rest + form focus)
            switch minutes {
            case ...20: return 2      // Quick intro workout
            case 21...35: return 3    // Short beginner workout (3-4 exercises)
            case 36...50: return 4    // Standard beginner workout
            case 51...70: return 5    // Longer session
            case 71...90: return 6    // Extended session
            default: return max(6, min(8, minutes / 12))
            }
            
        case "advanced":
            // Advanced: shorter rest (30-60s), supersets, compound movements, high intensity
            // ~5-6 min per exercise (4 sets x 8-10 reps + minimal rest)
            switch minutes {
            case ...20: return 3      // Quick intense blast
            case 21...35: return 5    // Short but intense (5-6 exercises)
            case 36...50: return 6    // Standard advanced workout (6-7 exercises)
            case 51...70: return 8    // High volume session
            case 71...90: return 10   // Extended volume workout
            default: return max(8, min(14, minutes / 6))
            }
            
        default: // Intermediate
            // Intermediate: moderate rest (60-90s), balanced approach
            // ~7 min per exercise (3-4 sets x 10-12 reps + moderate rest)
            switch minutes {
            case ...20: return 3      // Quick workout
            case 21...35: return 4    // Short workout (4-5 exercises)
            case 36...50: return 5    // Standard workout (5-6 exercises)
            case 51...70: return 6    // Longer session
            case 71...90: return 8    // Extended session
            default: return max(5, min(12, minutes / 7))
            }
        }
    }
    
    // Calculate rest time based on skill level
    private var effectiveRestTime: Int {
        let userLevel = userManager.currentUser?.experienceLevel?.lowercased() ?? "intermediate"
        let baseRest: Int
        
        if selectedDuration == .custom {
            // Scale rest time: shorter workouts = shorter rests
            if customDurationMinutes <= 30 { baseRest = 45 }
            else if customDurationMinutes <= 45 { baseRest = 60 }
            else if customDurationMinutes <= 60 { baseRest = 75 }
            else { baseRest = 90 }
        } else {
            baseRest = selectedDuration.baseRestBetweenSets
        }
        
        // Adjust rest based on skill level
        switch userLevel {
        case "beginner":
            return baseRest + 30  // Beginners get +30s rest
        case "advanced":
            return max(30, baseRest - 20)  // Advanced get -20s rest (min 30s)
        default:
            return baseRest  // Intermediate uses base rest
        }
    }
    
    // Determine if we should prefer compound/technical exercises
    private var preferTechnicalExercises: Bool {
        let userLevel = userManager.currentUser?.experienceLevel?.lowercased() ?? "intermediate"
        return userLevel == "advanced"
    }
    
    // Get the minimum difficulty rating for exercise selection
    private var minimumDifficultyRating: Int {
        let userLevel = userManager.currentUser?.experienceLevel?.lowercased() ?? "intermediate"
        switch userLevel {
        case "beginner": return 1   // Allow easiest exercises
        case "advanced": return 4   // Only intermediate+ difficulty exercises
        default: return 2           // Skip the very easiest
        }
    }
    
    // MARK: - Progress Indicator (UX Audit)
    private var autoGenProgressIndicator: some View {
        // Progress bar only (no step label text)
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background track
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 6)
                
                // Progress fill
                RoundedRectangle(cornerRadius: 3)
                    .fill(
                        LinearGradient(
                            colors: [.blue, .cyan],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geometry.size.width * (Double(stepNumber) / Double(totalSteps)), height: 6)
                    .animation(.easeInOut(duration: 0.3), value: stepNumber)
            }
        }
        .frame(height: 6)
        .padding(.horizontal, Spacing.lg)
    }
    
    @ViewBuilder
    private var previewDestination: some View {
        AutoWorkoutPreviewView(
            primaryMuscles: Array(selectedPrimaryMuscles),
            secondaryMuscles: Array(selectedSecondaryMuscles),
            equipment: Array(selectedEquipment),
            initialExercises: generatedExercises,
            targetDurationMinutes: selectedDuration == .custom ? customDurationMinutes : selectedDuration.minutes,
            restBetweenSets: effectiveRestTime
        )
        .environmentObject(workoutManager)
        .environmentObject(userManager)
    }
    
    // MARK: - Shared Bottom Button Bar
    @ViewBuilder
    private var sharedBottomButtonBar: some View {
        HStack(spacing: 12) {
            // Back button (grey circular)
            Button(action: handleBackAction) {
                Image(systemName: "chevron.left")
                    .font(.ds_labelLarge)
                    .foregroundColor(.gray)
                    .frame(width: 52, height: 52)
                    .background(
                        Circle()
                            .fill(Color.darkBackground)
                    )
                    .overlay(
                        Circle()
                            .stroke(Color.gray.opacity(0.5), lineWidth: 2)
                    )
            }
            
            // Main button - hollow outline style (no icons)
            Button(action: handleMainAction) {
                HStack(spacing: 8) {
                    if isGenerating && currentStep == .equipment {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                            .scaleEffect(0.8)
                    }
                    Text(isGenerating && currentStep == .equipment ? "Generating..." : mainButtonTitle)
                }
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundStyle(
                    isMainButtonDisabled || isGenerating
                        ? AnyShapeStyle(Color.gray)
                        : AnyShapeStyle(LinearGradient(colors: mainButtonGradient, startPoint: .leading, endPoint: .trailing))
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.md)
                .background(
                    Capsule()
                        .fill(Color.darkBackground)
                )
                .overlay(
                    Capsule()
                        .stroke(
                            isMainButtonDisabled || isGenerating
                                ? AnyShapeStyle(Color.gray.opacity(0.3))
                                : AnyShapeStyle(LinearGradient(colors: mainButtonGradient, startPoint: .leading, endPoint: .trailing)),
                            lineWidth: 2
                        )
                )
            }
            .disabled(isMainButtonDisabled || isGenerating)
        }
    }
    
    private var mainButtonTitle: String {
        switch currentStep {
        case .duration: return "Continue"
        case .primary: return "Continue"
        case .secondary: return selectedSecondaryMuscles.isEmpty ? "Skip" : "Continue"
        case .equipment: return "Generate Workout"
        default: return "Continue"
        }
    }

    private var mainButtonGradient: [Color] {
        [.blue, .cyan]
    }

    private var isMainButtonDisabled: Bool {
        switch currentStep {
        case .primary: return !surpriseMeSelected && selectedPrimaryMuscles.isEmpty
        case .equipment: return selectedEquipment.isEmpty
        default: return false
        }
    }
    
    // MARK: - Step Header Text
    private var stepTitle: String {
        switch currentStep {
        case .duration: return "How long is your workout?"
        case .primary: return "What muscles do you want to target?"
        case .secondary: return "Focus on specific areas?"
        case .equipment: return "Select Your Equipment"
        default: return ""
        }
    }
    
    private var stepSubtitle: String {
        switch currentStep {
        case .duration: return "We'll auto-adjust exercises & rest times"
        case .primary: return "Select one or more muscle groups"
        case .secondary: return "Optional: Add secondary muscle focus"
        case .equipment: return "Select the equipment you'd like to use"
        default: return ""
        }
    }
    
    @ViewBuilder
    private var equipmentLocationDropdown: some View {
        Menu {
            ForEach(EquipmentLocation.allCases, id: \.self) { location in
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        equipmentLocation = location
                        selectedEquipment = location.defaultEquipment
                    }
                }) {
                    Label(location.rawValue, systemImage: location.icon)
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: equipmentLocation.icon)
                    .font(.ds_labelLarge)
                Text(equipmentLocation.rawValue)
                    .font(.headline)
                    .fontWeight(.semibold)
                Image(systemName: "chevron.down")
                    .font(.ds_labelMedium)
            }
            .foregroundColor(.blue)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.blue.opacity(0.12))
            )
        }
    }
    
    private func handleBackAction() {
        selectionFeedback.selectionChanged()
        switch currentStep {
        case .duration:
            // 🔧 If we came from Home tab redirect, just switch tabs directly
            // This matches the Home tab button behavior - no navigation clearing needed
            if workoutManager.autoGenCameFromHomeTab {
                workoutManager.autoGenCameFromHomeTab = false
                // Just switch tabs directly - same as tapping Home tab button (no flicker)
                workoutManager.shouldNavigateToHomeTabInstant = true
            } else {
                // Came from Workout tab normally, just dismiss
                dismiss()
            }
        case .primary:
            goBackToStep(.duration)
        case .secondary:
            goBackToStep(.primary)
        case .equipment:
            goBackToStep(.secondary)
        default:
            break
        }
    }
    
    private func handleMainAction() {
        AppLogger.debug("🔘 [AUTOGEN] handleMainAction called - step: \(currentStep)", category: .workout)
        impactFeedback.impactOccurred()
        switch currentStep {
        case .duration:
            advanceToStep(.primary)
        case .primary:
            if surpriseMeSelected {
                generateSurpriseWorkout()
            } else {
                advanceToStep(.secondary)
            }
        case .secondary:
            if selectedEquipment.isEmpty {
                selectedEquipment = ["Dumbbells", "Barbell", "Cables", "Machines", "Kettlebell", "Plates"]
            }
            advanceToStep(.equipment)
        case .equipment:
            AppLogger.debug("🔘 [AUTOGEN] Equipment step - calling generateCustomWorkout()", category: .workout)
            generateCustomWorkout()
        default:
            break
        }
    }
    
    var body: some View {
        ZStack {
            // Full screen gradient background — blue theme
            LinearGradient(
                gradient: Gradient(colors: colorScheme == .dark 
                    ? [
                        Color.blue.opacity(0.2),
                        Color.cyan.opacity(0.1),
                        Color(red: 0.04, green: 0.06, blue: 0.10),
                        Color(red: 0.03, green: 0.04, blue: 0.07)
                    ]
                    : [
                        Color.blue.opacity(0.3),
                        Color.cyan.opacity(0.2),
                        Color.blue.opacity(0.05),
                        Color.white
                    ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            // Welcome Step (full screen, own layout)
            if currentStep == .welcome {
                WelcomeStepView(onGetStarted: {
                    impactFeedback.impactOccurred()
                    advanceToStep(.duration)
                    hasSeenOnboarding = true
                })
            }
            
            // Main flow (progress + header + tiles + buttons all fixed except tiles)
            if currentStep != .welcome {
                VStack(spacing: 0) {
                    // FIXED: Progress indicator
                    autoGenProgressIndicator
                        .padding(.top, 8)
                        .padding(.bottom, 8)
                    
                    // FIXED: Header (fixed height so tiles always align)
                    VStack(spacing: 4) {
                        Text(stepTitle)
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.center)
                            .frame(height: 56) // Fixed height for 2 lines

                        Text(stepSubtitle)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .frame(height: 20) // Fixed height for subtitle
                    }
                    .padding(.horizontal, 20)
                    // No bottom padding - header ends right at bottom of text
                    
                    // SLIDING: Only the tiles/grid slides
                    ZStack(alignment: .top) {
                        if currentStep == .duration {
                            DurationTilesView(
                                selectedDuration: $selectedDuration,
                                customMinutes: $customDurationMinutes
                            )
                            .transition(slideTransition)
                        }
                        
                        if currentStep == .primary {
                            PrimaryMuscleTilesView(
                                selectedPrimaries: $selectedPrimaryMuscles,
                                surpriseMeSelected: $surpriseMeSelected
                            )
                            .transition(slideTransition)
                        }
                        
                        if currentStep == .secondary {
                            SecondaryMuscleTilesView(
                                primaryMuscles: selectedPrimaryMuscles,
                                selectedSecondary: $selectedSecondaryMuscles
                            )
                            .transition(slideTransition)
                        }
                        
                        if currentStep == .equipment {
                            EquipmentTilesView(
                                selectedEquipment: $selectedEquipment,
                                selectedLocation: $equipmentLocation
                            )
                            .transition(slideTransition)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .animation(.easeInOut(duration: 0.35), value: currentStep)
                    
                    // "or" divider for primary muscle step
                    if currentStep == .primary && selectedPrimaryMuscles.isEmpty {
                        HStack(spacing: 12) {
                            Rectangle().fill(Color.gray.opacity(0.3)).frame(height: 1)
                            Text("or").font(.subheadline).foregroundColor(.secondary)
                            Rectangle().fill(Color.gray.opacity(0.3)).frame(height: 1)
                        }
                        .padding(.horizontal, 40)
                        .padding(.bottom, 16)
                    }
                    
                    Spacer(minLength: 0)
                    
                    // FIXED: Bottom button bar
                    sharedBottomButtonBar
                        .padding(.horizontal, 20)
                        .padding(.bottom, 40)
                }
            }
            
            // Loading overlay            
            if isGenerating {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.white)
                    
                    Text("Generating your workout...")
                        .font(.headline)
                        .foregroundColor(.white)
                }
                .padding(30)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color.black.opacity(0.7))
                )
            }
        }
        .navigationTitle("Auto Workout")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .onAppear {
            let startTime = CFAbsoluteTimeGetCurrent()
            
            // Log screen with step info
            SessionLogManager.shared.logScreen(.workoutGenerator, metadata: [
                "step": String(describing: currentStep),
                "has_seen_onboarding": hasSeenOnboarding
            ])
            
            // 🔧 FIX: Reset navigation state when view appears
            // This ensures we can generate a new workout even if user navigated back from preview
            if navigateToPreview {
                AppLogger.debug("🔧 [AUTOGEN] Resetting navigateToPreview on appear (was stuck as true)", category: .workout)
                navigateToPreview = false
            }
            
            // 🔧 FIX: Reset isGenerating state if it got stuck
            if isGenerating {
                AppLogger.debug("🔧 [AUTOGEN] Resetting isGenerating on appear (was stuck as true)", category: .workout)
                isGenerating = false
            }
            
            // Only set initial step if not navigating to preview
            if !navigateToPreview {
                if !hasSeenOnboarding {
                    currentStep = .welcome
                } else if currentStep == .welcome {
                    // Only reset to duration if coming from welcome
                    currentStep = .duration
                }
            }
            workoutManager.isOnGeneratorScreen = true
            
            // 🎯 Initialize equipment location from user's workout environment
            if !equipmentLocationInitialized {
                equipmentLocationInitialized = true
                if let env = userManager.currentUser?.workoutEnvironment?.lowercased() {
                    if env.contains("home") { equipmentLocation = .home }
                    else if env.contains("outdoor") { equipmentLocation = .outdoor }
                    else if env.contains("hybrid") { equipmentLocation = .hybrid }
                    else { equipmentLocation = .gym }
                }
            }
            
            // 🎯 Pre-select user's equipment from settings (unless already selected)
            if selectedEquipment.isEmpty {
                if let userEquipment = userManager.currentUser?.getEquipment(), !userEquipment.isEmpty {
                    selectedEquipment = Set(userEquipment)
                } else {
                    // Fall back to location defaults
                    selectedEquipment = equipmentLocation.defaultEquipment
                }
            }
            
            let loadTime = CFAbsoluteTimeGetCurrent() - startTime
            SessionLogManager.shared.logPerformance(operation: "WorkoutGenerator_onAppear", duration: loadTime)
        }
        .onDisappear {
            // Only reset if not navigating to preview
            if !navigateToPreview {
                workoutManager.isOnGeneratorScreen = false
            }
        }
        .onChange(of: workoutManager.isWorkoutActive) { _, isActive in
            // 🔧 FIX: Reset navigation when workout starts
            // This prevents this view from reappearing after tab switch
            if isActive {
                navigateToPreview = false
            }
        }
        .onChange(of: generatedExercises) { oldValue, newValue in
            // 🔧 DEBUG: Track when exercises are generated
            AppLogger.debug("🔘 [AUTOGEN] generatedExercises changed: \(oldValue.count) → \(newValue.count)", category: .workout)
            
            // 🔧 FIX: Backup navigation trigger if exercises are generated but navigation didn't fire
            if !newValue.isEmpty && !navigateToPreview && !isGenerating && currentStep == .equipment {
                AppLogger.debug("🔧 [AUTOGEN] Backup trigger: navigating to preview", category: .workout)
                navigateToPreview = true
            }
        }
        .onChange(of: navigateToPreview) { _, shouldNavigate in
            // 🔧 DEBUG: Track navigation state changes
            AppLogger.debug("🔘 [AUTOGEN] navigateToPreview changed to: \(shouldNavigate)", category: .workout)
            if shouldNavigate {
                AppLogger.debug("   └─ generatedExercises count: \(generatedExercises.count)", category: .workout)
            }
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        // 🐛 FIX: navigationDestination MUST be on the ZStack, not on EmptyView inside it
        // EmptyView inside ZStack doesn't reliably trigger navigation
        .navigationDestination(isPresented: $navigateToPreview) {
            previewDestination
        }
    }
    
    // MARK: - Smooth Step Transitions
    
    private func advanceToStep(_ step: AutoWorkoutStep) {
        isNavigatingForward = true
        withAnimation(.easeInOut(duration: 0.35)) {
            currentStep = step
        }
    }

    private func goBackToStep(_ step: AutoWorkoutStep) {
        isNavigatingForward = false
        withAnimation(.easeInOut(duration: 0.35)) {
            currentStep = step
        }
    }
    
    private func generateSurpriseWorkout() {
        // 🔧 Guard against rapid re-generation (crash prevention)
        guard !isGenerating, !navigateToPreview, !workoutManager.isWorkoutActive else {
            AppLogger.warning("⚠️ [Generator] Blocked duplicate generation request", category: .workout)
            return
        }
        isGenerating = true

        Task {
            do {
                // Use user's profile equipment if nothing selected
                let userEquipment = (userManager.currentUser?.equipment as? [String]) ?? ["Barbell", "Dumbbells", "Bodyweight", "Cables"]
                var equipment: [String] = selectedEquipment.isEmpty ? userEquipment : Array(selectedEquipment)
                
                // Auto-include gym essentials only if user has gym-specific equipment selected
                let hasGymEquipment = equipment.contains("Cables") || 
                                      equipment.contains("Machines") || 
                                      equipment.contains("Barbell")
                
                if hasGymEquipment {
                    let gymEssentials = [
                        "Bench", "Flat Bench", "Incline Bench", "Decline Bench",
                        "Pull-Up Bar", "Hyperextension Bench", "Preacher Bench",
                        "Smith Machine"
                    ]
                    for essential in gymEssentials {
                        if !equipment.contains(essential) {
                            equipment.append(essential)
                        }
                    }
                }
                
                let exercises = try await generatorService.generateSurpriseWorkout(equipment: equipment, count: effectiveExerciseCount)

                await MainActor.run {
                    generatedExercises = exercises
                    isGenerating = false

                    if exercises.isEmpty {
                        errorMessage = "No exercises found. Please try different options."
                        showingError = true
                    } else {
                        // 🚀 PERF: Dispatch prefetch to background immediately
                        // ⚡️ MEMORY FIX: Disabled video prefetching — videos load on-demand.
                        
                        // Navigate immediately
                        navigateToPreview = true
                    }
                }
            } catch {
                await MainActor.run {
                    isGenerating = false
                    errorMessage = "Failed to generate workout: \(error.localizedDescription)"
                    showingError = true
                    AppLogger.error("❌ Failed to generate surprise workout: \(error)", category: .workout)
                }
            }
        }
    }
    
    private func generateCustomWorkout() {
        AppLogger.debug("🔘 [AUTOGEN] generateCustomWorkout() called", category: .workout)
        AppLogger.debug("   └─ isGenerating: \(isGenerating)", category: .workout)
        AppLogger.debug("   └─ navigateToPreview: \(navigateToPreview)", category: .workout)
        AppLogger.debug("   └─ isWorkoutActive: \(workoutManager.isWorkoutActive)", category: .workout)
        
        // 🔧 Safety: If navigateToPreview is somehow stuck, reset it
        if navigateToPreview && generatedExercises.isEmpty {
            AppLogger.debug("🔧 [AUTOGEN] Resetting stuck navigateToPreview (no exercises)", category: .workout)
            navigateToPreview = false
        }
        
        // 🔧 Guard against rapid re-generation (but allow if previous was stuck)
        guard !isGenerating, !navigateToPreview, !workoutManager.isWorkoutActive else {
            AppLogger.warning("⚠️ [Generator] Blocked duplicate generation request", category: .workout)
            AppLogger.error("   ❌ isGenerating=\(isGenerating), navigateToPreview=\(navigateToPreview), isWorkoutActive=\(workoutManager.isWorkoutActive)", category: .workout)
            return
        }
        isGenerating = true
        AppLogger.debug("🔘 [AUTOGEN] Starting Task for workout generation...", category: .workout)

        Task {
            do {
                AppLogger.debug("🔘 [AUTOGEN] Task started - about to call generatorService.generateWorkout", category: .workout)
                // Use user's profile equipment if nothing selected
                let userEquipment = (userManager.currentUser?.equipment as? [String]) ?? ["Barbell", "Dumbbells", "Bodyweight", "Cables"]
                var equipment: [String] = selectedEquipment.isEmpty ? userEquipment : Array(selectedEquipment)
                
                // Auto-include gym essentials only if user has gym-specific equipment selected
                // (Cables, Machines, or Barbell indicate a gym workout)
                let hasGymEquipment = equipment.contains("Cables") || 
                                      equipment.contains("Machines") || 
                                      equipment.contains("Barbell")
                
                if hasGymEquipment {
                    let gymEssentials = [
                        "Bench",
                        "Flat Bench",
                        "Smith Machine",
                        "Incline Bench",
                        "Decline Bench",
                        "Pull-Up Bar",
                        "Hyperextension Bench",
                        "Preacher Bench"
                    ]
                    for essential in gymEssentials {
                        if !equipment.contains(essential) {
                            equipment.append(essential)
                        }
                    }
                }
                
                AppLogger.debug("🔘 [AUTOGEN] Calling generatorService.generateWorkout with:", category: .workout)
                AppLogger.debug("   └─ primaryMuscles: \(Array(selectedPrimaryMuscles))", category: .workout)
                AppLogger.debug("   └─ secondaryMuscles: \(Array(selectedSecondaryMuscles))", category: .workout)
                AppLogger.debug("   └─ equipment: \(equipment)", category: .workout)
                AppLogger.debug("   └─ count: \(effectiveExerciseCount)", category: .workout)
                
                let exercises = try await generatorService.generateWorkout(
                    primaryMuscles: Array(selectedPrimaryMuscles),
                    secondaryMuscles: Array(selectedSecondaryMuscles),
                    equipment: equipment,
                    count: effectiveExerciseCount
                )
                
                AppLogger.debug("🔘 [AUTOGEN] generateWorkout returned \(exercises.count) exercises", category: .workout)

                await MainActor.run {
                    generatedExercises = exercises
                    isGenerating = false

                    if exercises.isEmpty {
                        AppLogger.warning("⚠️ [AUTOGEN] No exercises generated - showing error", category: .workout)
                        errorMessage = "No exercises found. Please try different options."
                        showingError = true
                    } else {
                        AppLogger.info("✅ [AUTOGEN] Generated \(exercises.count) exercises - navigating to preview", category: .workout)
                        // 🚀 PERF: Dispatch prefetch to background immediately
                        // ⚡️ MEMORY FIX: Disabled video prefetching — videos load on-demand.
                        
                        // Navigate immediately
                        navigateToPreview = true
                    }
                }
            } catch {
                await MainActor.run {
                    isGenerating = false
                    errorMessage = "Failed to generate workout: \(error.localizedDescription)"
                    showingError = true
                    AppLogger.error("❌ [AUTOGEN] Failed to generate custom workout: \(error)", category: .workout)
                }
            }
        }
    }
}

// MARK: - Welcome Step

struct WelcomeStepView: View {
    let onGetStarted: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            
            VStack(spacing: 32) {
                // Icon
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.blue, Color.cyan],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 100, height: 100)
                        .shadow(color: .blue.opacity(0.3), radius: 12, x: 0, y: 6)
                    
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 45, weight: .bold))
                        .foregroundColor(.white)
                }
                
                VStack(spacing: 16) {
                    Text("Auto Workout")
                        .font(.ds_displayMedium)
                        .foregroundColor(.primary)
                    
                    Text("Get a personalized workout in seconds")
                        .font(.title3)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                
                // How it works
                VStack(alignment: .leading, spacing: 20) {
                    HowItWorksRow(
                        icon: "figure.strengthtraining.traditional",
                        color: .purple,
                        title: "Choose Your Muscles",
                        description: "Select which muscles you want to target"
                    )
                    
                    HowItWorksRow(
                        icon: "dumbbell.fill",
                        color: .blue,
                        title: "Pick Equipment",
                        description: "Tell us what equipment you have available"
                    )
                    
                    HowItWorksRow(
                        icon: "sparkles",
                        color: .cyan,
                        title: "Get Your Workout",
                        description: "Receive a custom workout tailored to you"
                    )
                }
                .padding(Spacing.lg)
                .sleekCard(cornerRadius: 20, accentColor: .cyan)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .padding(.horizontal, 20)
            }
            
            Spacer()
            
            // Get Started Button
            Button(action: onGetStarted) {
                HStack(spacing: 12) {
                    Text("Get Started")
                        .font(.title3)
                        .fontWeight(.semibold)
                    Image(systemName: "arrow.right")
                        .font(.title3)
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(
                    LinearGradient(
                        colors: [Color.blue, Color.cyan],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .shadow(color: .blue.opacity(0.3), radius: 12, x: 0, y: 6)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
    }
}

struct HowItWorksRow: View {
    let icon: String
    let color: Color
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 50, height: 50)
                
                Image(systemName: icon)
                    .font(.ds_heading2)
                    .foregroundColor(color)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
    }
}

// MARK: - Duration Step

struct DurationStepView: View {
    @Binding var selectedDuration: WorkoutGeneratorSelectionView.WorkoutDuration
    @Binding var customMinutes: Int
    let onBack: () -> Void
    let onContinue: () -> Void
    
    // All duration options including custom presets
    private let customDurations = [15, 20, 25, 35, 50, 75]
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(height: 20)
            
            // Header
            VStack(spacing: 8) {
                Text("How long is your workout?")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Text("We'll auto-adjust exercises & rest times")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 20)
            
            Spacer()
                .frame(minHeight: 24, maxHeight: 40)
            
            // Main content
            VStack(spacing: 16) {
                // Quick Select - 2x2 grid
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ], spacing: 12) {
                    ForEach(WorkoutGeneratorSelectionView.WorkoutDuration.allCases.filter { $0 != .custom }, id: \.self) { duration in
                        DurationCard(
                            duration: duration,
                            isSelected: selectedDuration == duration && selectedDuration != .custom,
                            onTap: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    selectedDuration = duration
                                }
                            }
                        )
                    }
                }
                .padding(.horizontal, 20)
                
                // Divider with label
                HStack {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 1)
                    Text("or custom")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 1)
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.xs)
                
                // Custom duration tiles - 3x2 grid
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ], spacing: 10) {
                    ForEach(customDurations, id: \.self) { mins in
                        let isSelected = selectedDuration == .custom && customMinutes == mins
                        Button(action: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                selectedDuration = .custom
                                customMinutes = mins
                            }
                        }) {
                            VStack(spacing: 4) {
                                Text("\(mins)")
                                    .font(.title3)
                                    .fontWeight(.bold)
                                    .foregroundColor(isSelected ? .blue : .primary)
                                
                                Text("min")
                                    .font(.caption2)
                                    .fontWeight(.medium)
                                    .foregroundColor(isSelected ? .blue.opacity(0.8) : .secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .sleekCard(cornerRadius: 24, accentColor: isSelected ? .blue : Color(white: 0.4))
                            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 24, style: .continuous)
                                    .stroke(isSelected ? Color.purple.opacity(0.6) : Color.clear, lineWidth: 2)
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                        .scaleEffect(isSelected ? 1.03 : 1.0)
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
                    }
                }
                .padding(.horizontal, 20)
            }
            
            Spacer()
            
            // Bottom buttons - Back + Continue
            HStack(spacing: 12) {
                // Back button (circular hollow, inline height)
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.ds_labelLarge)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.purple, .blue],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: 52, height: 52)
                        .background(
                            Circle()
                                .fill(Color.darkBackground)
                        )
                        .overlay(
                            Circle()
                                .stroke(
                                    LinearGradient(
                                        colors: [.blue, .cyan],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    ),
                                    lineWidth: 2
                                )
                        )
                }
                
                // Continue button (no icon)
                Button(action: onContinue) {
                    Text("Continue")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.md)
                        .background(
                            Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [.blue, .cyan],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    )
                    .shadow(color: .blue.opacity(0.4), radius: 10, x: 0, y: 5)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
    }
}

struct DurationCard: View {
    @Environment(\.colorScheme) var colorScheme
    let duration: WorkoutGeneratorSelectionView.WorkoutDuration
    let isSelected: Bool
    let onTap: () -> Void
    
    private let selectionFeedback = UISelectionFeedbackGenerator()
    
    var body: some View {
        Button(action: {
            selectionFeedback.selectionChanged()
            onTap()
        }) {
            VStack(spacing: 6) {
                ZStack {
                    // Soft glow when selected
                    if isSelected {
                        Circle()
                            .fill(.blue.opacity(0.3))
                            .frame(width: 44, height: 44)
                            .blur(radius: 8)
                    }
                    
                    Circle()
                        .fill(
                            isSelected
                                ? LinearGradient(colors: [.blue, .blue.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)
                                : LinearGradient(colors: [Color.gray.opacity(0.15), Color.gray.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .frame(width: 40, height: 40)
                    
                    Image(systemName: duration.icon)
                        .font(.ds_labelLarge)
                        .foregroundColor(isSelected ? .white : .gray)
                }
                
                VStack(spacing: 2) {
                    Text(duration.displayName)
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(isSelected ? .blue : .primary)
                    
                    Text(duration.subtitle)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .sleekCard(cornerRadius: 24, accentColor: isSelected ? .blue : Color(white: 0.4))
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(
                        isSelected ? .blue.opacity(0.6) : Color.clear,
                        lineWidth: 2
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(isSelected ? 1.02 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        .accessibilityLabel("\(duration.displayName). \(duration.subtitle)")
        .accessibilityHint(isSelected ? "Currently selected" : "Double tap to select")
    }
}

// MARK: - Primary Muscle Step

struct PrimaryMuscleStepView: View {
    @Binding var selectedPrimaries: Set<String>
    let onBack: () -> Void
    let onSurpriseMe: () -> Void
    let onContinue: () -> Void
    
    private let primaryMuscles = [
        ("Chest", "figure.strengthtraining.traditional", Color.red),
        ("Back", "figure.strengthtraining.traditional", Color.blue),
        ("Shoulders", "figure.strengthtraining.traditional", Color.orange),
        ("Arms", "figure.strengthtraining.traditional", Color.purple),
        ("Legs", "figure.run", Color.green),
        ("Core", "figure.core.training", Color.yellow),
        ("Full Body", "figure.strengthtraining.traditional", Color.indigo),
        ("Stretching", "figure.flexibility", Color.teal),
        ("Cardio", "heart.fill", Color.pink)
    ]
    
    private var hasMusclesSelected: Bool {
        !selectedPrimaries.isEmpty
    }
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(height: 20)
            
            // Header
            VStack(spacing: 8) {
                Text("What muscles do you want to target?")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                
                Text("Select one or more muscle groups")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 20)
            
            Spacer()
                .frame(minHeight: 16, maxHeight: 24)
            
            // Primary Muscles Grid
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10)
            ], spacing: 10) {
                ForEach(primaryMuscles, id: \.0) { muscle in
                    PrimaryMuscleCard(
                        title: muscle.0,
                        icon: muscle.1,
                        color: muscle.2,
                        isSelected: selectedPrimaries.contains(muscle.0),
                        isDisabled: false,
                        customImage: muscle.0 == "Chest" ? "ChestIcon" : muscle.0 == "Back" ? "BackIcon" : muscle.0 == "Shoulders" ? "ShoulderIcon" : (muscle.0 == "Arms" || muscle.0 == "Biceps") ? "BicepIcon" : muscle.0 == "Triceps" ? "TricepIcon" : muscle.0 == "Core" ? "CoreIcon" : muscle.0 == "Glutes" ? "GlutesIcon" : muscle.0 == "Legs" ? "LegsIcon" : nil,
                        onTap: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                if selectedPrimaries.contains(muscle.0) {
                                    selectedPrimaries.remove(muscle.0)
                                } else {
                                    selectedPrimaries.insert(muscle.0)
                                }
                            }
                        }
                    )
                }
            }
            .padding(.horizontal, 20)
            
            // Centered "or" Divider (only when no muscles selected)
            if !hasMusclesSelected {
                Spacer()
                
                HStack(spacing: 12) {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 1)
                    
                    Text("or")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 1)
                }
                .padding(.horizontal, 40)
                
                Spacer()
            } else {
                Spacer()
            }
            
            // Bottom buttons - Back + Continue/Surprise Me
            HStack(spacing: 12) {
                // Back button (circular hollow, inline height)
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.ds_labelLarge)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.purple, .blue],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: 52, height: 52)
                        .background(
                            Circle()
                                .fill(Color.darkBackground)
                        )
                        .overlay(
                            Circle()
                                .stroke(
                                    LinearGradient(
                                        colors: [.blue, .cyan],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    ),
                                    lineWidth: 2
                                )
                        )
                }
                
                // Main button - Surprise Me or Continue (no icons)
                Button(action: hasMusclesSelected ? onContinue : onSurpriseMe) {
                    Text(hasMusclesSelected ? "Continue" : "Surprise Me!")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.md)
                        .background(
                            Capsule()
                            .fill(
                                LinearGradient(
                                    colors: hasMusclesSelected ? [.blue, .cyan] : [.blue, .cyan.opacity(0.6)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    )
                    .shadow(color: .blue.opacity(0.4), radius: 10, x: 0, y: 5)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
    }
}

struct PrimaryMuscleCard: View {
    @Environment(\.colorScheme) var colorScheme
    let title: String
    let icon: String
    let color: Color
    let isSelected: Bool
    var isDisabled: Bool = false
    var customImage: String? = nil  // Optional custom image from Assets
    let onTap: () -> Void
    
    private let selectionFeedback = UISelectionFeedbackGenerator()
    
    var body: some View {
        Button(action: {
            selectionFeedback.selectionChanged()
            onTap()
        }) {
            VStack(spacing: 10) {
                ZStack {
                    // Soft glow when selected
                    if isSelected {
                        Circle()
                            .fill(Color.blue.opacity(0.4))
                            .frame(width: 60, height: 60)
                            .blur(radius: 12)
                    }
                    
                    Circle()
                        .fill(
                            isSelected
                                ? LinearGradient(colors: [.blue, .blue.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)
                                : LinearGradient(colors: [Color.gray.opacity(0.15), Color.gray.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .frame(width: 54, height: 54)
                    
                    // Use custom image if provided, otherwise SF Symbol
                    if let customImage = customImage {
                        Image(customImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 54, height: 54)
                            .clipShape(Circle())
                    } else {
                        Image(systemName: icon)
                            .font(.ds_heading2)
                            .foregroundColor(isSelected ? .white : .gray)
                    }
                }
                
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(isSelected ? .blue : .primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.sm)
            .sleekCard(cornerRadius: 24, accentColor: isSelected ? .blue : Color(white: 0.4))
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(isSelected ? .blue.opacity(0.6) : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(isSelected ? 1.03 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        .accessibilityLabel("\(title) muscle target")
        .accessibilityHint(isSelected ? "Currently selected" : "Double tap to select")
    }
}

// MARK: - Secondary Muscle Step

struct SecondaryMuscleStepView: View {
    let primaryMuscles: Set<String>
    @Binding var selectedSecondary: Set<String>
    let onBack: () -> Void
    let onContinue: () -> Void
    
    // Muscle group data
    private let muscleGroupData: [String: (options: [(String, String, Color)], color: Color)] = [
        "Chest": (
            options: [
                ("Upper Chest", "arrow.up.circle.fill", .red),
                ("Lower Chest", "arrow.down.circle.fill", .red),
                ("Inner Chest", "arrow.left.and.right.circle.fill", .red),
                ("Outer Chest", "arrow.up.left.and.arrow.down.right.circle.fill", .red)
            ],
            color: .red
        ),
        "Back": (
            options: [
                ("Lats", "figure.strengthtraining.traditional", .blue),
                ("Traps", "figure.strengthtraining.traditional", .blue),
                ("Lower Back", "figure.strengthtraining.traditional", .blue)
            ],
            color: .blue
        ),
        "Shoulders": (
            options: [
                ("Front Delts", "circle.lefthalf.filled", .orange),
                ("Side Delts", "circle.fill", .orange),
                ("Rear Delts", "circle.righthalf.filled", .orange)
            ],
            color: .orange
        ),
        "Arms": (
            options: [
                ("Biceps", "figure.strengthtraining.traditional", .purple),
                ("Triceps", "figure.strengthtraining.traditional", .purple),
                ("Forearms", "figure.strengthtraining.traditional", .purple)
            ],
            color: .purple
        ),
        "Legs": (
            options: [
                ("Quadriceps", "figure.run", .green),
                ("Hamstrings", "figure.run", .green),
                ("Glutes", "figure.run", .green),
                ("Calves", "figure.run", .green),
                ("Hip Flexors", "figure.run", .green)
            ],
            color: .green
        ),
        "Core": (
            options: [
                ("Upper Abs", "figure.core.training", .yellow),
                ("Lower Abs", "figure.core.training", .yellow),
                ("Obliques", "figure.core.training", .yellow)
            ],
            color: .yellow
        ),
        "Stretching": (
            options: [
                ("Upper Body", "figure.flexibility", .teal),
                ("Lower Body", "figure.flexibility", .teal),
                ("Full Body", "figure.flexibility", .teal),
                ("Hip Openers", "figure.flexibility", .teal)
            ],
            color: .teal
        ),
        "Cardio": (
            options: [
                ("HIIT", "flame.fill", .pink),
                ("Low Impact", "heart.fill", .pink),
                ("Plyometrics", "figure.jumprope", .pink),
                ("Endurance", "bolt.heart.fill", .pink)
            ],
            color: .pink
        )
    ]
    
    // Aggregate all secondary options from selected primaries, grouped by primary
    private var groupedSecondaryOptions: [(primary: String, options: [(String, String, Color)], color: Color)] {
        primaryMuscles
            .compactMap { primary in
                guard let data = muscleGroupData[primary] else { return nil }
                return (primary: primary, options: data.options, color: data.color)
            }
            .sorted { $0.primary < $1.primary }
    }
    
    private var hasSecondaryOptions: Bool {
        !groupedSecondaryOptions.isEmpty && !groupedSecondaryOptions.allSatisfy { $0.options.isEmpty }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(height: 20)
            
            // Header
            VStack(spacing: 8) {
                Text("Focus on specific areas?")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                
                Text("Select specific muscle targets (optional)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 20)
            
            Spacer()
                .frame(minHeight: 16, maxHeight: 24)
            
            // Scrollable content
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    // Grouped Secondary Muscles
                    if hasSecondaryOptions {
                        ForEach(groupedSecondaryOptions, id: \.primary) { group in
                            VStack(alignment: .leading, spacing: 10) {
                                // Section Header
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(group.color.opacity(0.3))
                                        .frame(width: 8, height: 8)
                                    
                                    Text(group.primary)
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(group.color)
                                }
                                .padding(.horizontal, Spacing.xxs)
                                
                                // Options Grid
                                LazyVGrid(columns: [
                                    GridItem(.flexible(), spacing: 10),
                                    GridItem(.flexible(), spacing: 10),
                                    GridItem(.flexible(), spacing: 10)
                                ], spacing: 10) {
                                    ForEach(group.options, id: \.0) { option in
                                        SecondaryMuscleCard(
                                            title: option.0,
                                            icon: option.1,
                                            color: option.2,
                                            isSelected: selectedSecondary.contains(option.0),
                                            customImage: option.0 == "Biceps" ? "BicepIcon" : option.0 == "Triceps" ? "TricepIcon" : option.0 == "Glutes" ? "GlutesIcon" : option.0 == "Forearms" ? "ForearmIcon" : option.0 == "Quadriceps" ? "QuadIcon" : option.0 == "Hamstrings" ? "HamstringIcon" : option.0 == "Lower Back" ? "LowerBackIcon" : option.0 == "Upper Back" ? "UpperBackIcon" : option.0 == "Calves" ? "CalvesIcon" : option.0 == "Lats" ? "LatsIcon" : option.0 == "Traps" ? "TrapsIcon" : option.0 == "Upper Abs" ? "UpperAbsIcon" : option.0 == "Lower Abs" ? "LowerAbsIcon" : option.0 == "Obliques" ? "ObliquesIcon" : option.0 == "Front Delts" ? "FrontDeltIcon" : option.0 == "Rear Delts" ? "RearDeltIcon" : option.0 == "Hip Flexors" ? "HipFlexorsIcon" : option.0 == "Inner Chest" ? "InnerChestIcon" : option.0 == "Upper Chest" ? "UpperChestIcon" : option.0 == "Lower Chest" ? "LowerChestIcon" : option.0 == "Outer Chest" ? "OuterChestIcon" : nil,
                                            onTap: {
                                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                                    if selectedSecondary.contains(option.0) {
                                                        selectedSecondary.remove(option.0)
                                                    } else {
                                                        selectedSecondary.insert(option.0)
                                                    }
                                                }
                                            }
                                        )
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    } else {
                        VStack {
                            Spacer()
                            Text("No specific targeting available")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        .frame(minHeight: 200)
                    }
                }
                .padding(.bottom, 120)
            }
        }
        // Bottom buttons - Back + Skip/Continue
        VStack {
            Spacer()
            
            HStack(spacing: 12) {
                // Back button (circular hollow, inline height)
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.ds_labelLarge)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.purple, .blue],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: 52, height: 52)
                        .background(
                            Circle()
                                .fill(Color.darkBackground)
                        )
                        .overlay(
                            Circle()
                                .stroke(
                                    LinearGradient(
                                        colors: [.blue, .cyan],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    ),
                                    lineWidth: 2
                                )
                        )
                }
                
                // Main button - Skip or Continue (no icons)
                Button(action: onContinue) {
                    Text(selectedSecondary.isEmpty ? "Skip" : "Continue")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.md)
                        .background(
                            Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [.blue, .cyan],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    )
                    .shadow(color: .blue.opacity(0.4), radius: 10, x: 0, y: 5)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
    }
}

struct SecondaryMuscleCard: View {
    @Environment(\.colorScheme) var colorScheme
    let title: String
    let icon: String
    let color: Color
    let isSelected: Bool
    var customImage: String? = nil
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                ZStack {
                    // Soft glow when selected
                    if isSelected {
                        Circle()
                            .fill(Color.blue.opacity(0.4))
                            .frame(width: 54, height: 54)
                            .blur(radius: 10)
                    }
                    
                    Circle()
                        .fill(
                            isSelected
                                ? LinearGradient(colors: [.blue, .blue.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)
                                : LinearGradient(colors: [Color.gray.opacity(0.15), Color.gray.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .frame(width: 46, height: 46)
                    
                    // Use custom image if provided, otherwise SF Symbol
                    if let customImage = customImage {
                        Image(customImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 46, height: 46)
                            .clipShape(Circle())
                    } else {
                        Image(systemName: icon)
                            .font(.ds_heading3).fontWeight(.semibold)
                            .foregroundColor(isSelected ? .white : .gray)
                    }
                }
                
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(isSelected ? .blue : .primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(height: 28)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.sm)
            .sleekCard(cornerRadius: 24, accentColor: isSelected ? .blue : Color(white: 0.4))
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(isSelected ? .blue.opacity(0.6) : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(isSelected ? 1.03 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }
}

// MARK: - Small Secondary Muscle Card (4 per row, same size as primary)
struct SmallSecondaryMuscleCard: View {
    @Environment(\.colorScheme) var colorScheme
    let title: String
    let icon: String
    let color: Color
    let isSelected: Bool
    var customImage: String? = nil
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                ZStack {
                    // Soft glow when selected
                    if isSelected {
                        Circle()
                            .fill(Color.blue.opacity(0.4))
                            .frame(width: 50, height: 50)
                            .blur(radius: 10)
                    }

                    Circle()
                        .fill(
                            isSelected
                                ? LinearGradient(colors: [.blue, .blue.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)
                                : LinearGradient(colors: [Color.gray.opacity(0.15), Color.gray.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .frame(width: 44, height: 44)

                    // Use custom image if provided, otherwise SF Symbol
                    if let customImage = customImage {
                        Image(customImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 44, height: 44)
                            .clipShape(Circle())
                    } else {
                        Image(systemName: icon)
                            .font(.ds_heading3).fontWeight(.semibold)
                            .foregroundColor(isSelected ? .white : .gray)
                    }
                }

                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(isSelected ? .blue : .primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.sm)
            .sleekCard(cornerRadius: 24, accentColor: isSelected ? .blue : Color(white: 0.4))
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(isSelected ? .blue.opacity(0.6) : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(isSelected ? 1.03 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }
}

// MARK: - Equipment Location Enum (shared)

enum EquipmentLocation: String, CaseIterable {
    case gym = "Gym"
    case home = "Home"
    case outdoor = "Outdoor"
    case hybrid = "Hybrid"
    
    var icon: String {
        switch self {
        case .gym: return "building.2.fill"
        case .home: return "house.fill"
        case .outdoor: return "leaf.fill"
        case .hybrid: return "arrow.triangle.2.circlepath"
        }
    }
    
    var defaultEquipment: Set<String> {
        switch self {
        case .gym:
            // Bench, Pull-Up Bar, Dip Bars, Smith Machine auto-included behind the scenes
            return ["Dumbbells", "Barbell", "Cables", "Machines", "Smith Machine", "Plates"]
        case .home:
            return ["Dumbbells", "Bodyweight", "Kettlebell", "Bands"]
        case .outdoor:
            return ["Bodyweight", "Kettlebell", "Bands"]
        case .hybrid:
            return ["Dumbbells", "Bodyweight", "Bands", "Kettlebell"]
        }
    }
    
    var equipmentOptions: [(String, String, Color)] {
        switch self {
        case .gym:
            return [
                ("Dumbbells", "dumbbell.fill", .blue),
                ("Barbell", "figure.strengthtraining.traditional", .purple),
                ("Cables", "cable.connector", .orange),
                ("Machines", "gearshape.2.fill", .green),
                ("Smith Machine", "rectangle.stack.fill", .indigo),
                ("Plates", "circle.grid.2x2.fill", .gray),
                ("Bodyweight", "figure.walk", .teal),
                ("TRX/Rings", "link", .mint),
                ("Kettlebell", "scalemass.fill", .orange)
            ]
        case .home:
            return [
                ("Bodyweight", "figure.walk", .teal),
                ("Dumbbells", "dumbbell.fill", .blue),
                ("Bands", "circle.hexagongrid.fill", .pink),
                ("Kettlebell", "scalemass.fill", .orange),
                ("Pull-Up Bar", "figure.gymnastics", .purple),
                ("Dip Bars", "arrow.down.to.line", .indigo),
                ("Stability Ball", "circle.fill", .mint),
                ("TRX/Rings", "link", .mint),
                ("Barbell", "figure.strengthtraining.traditional", .purple)
            ]
        case .outdoor:
            return [
                ("Bodyweight", "figure.walk", .teal),
                ("Bands", "circle.hexagongrid.fill", .pink),
                ("Kettlebell", "scalemass.fill", .orange),
                ("Pull-Up Bar", "figure.gymnastics", .purple),
                ("Dip Bars", "arrow.down.to.line", .indigo),
                ("TRX/Rings", "link", .mint),
                ("Dumbbells", "dumbbell.fill", .blue),
                ("Medicine Ball", "basketball.fill", .brown),
                ("Jump Rope", "figure.jumprope", .red)
            ]
        case .hybrid:
            return [
                ("Dumbbells", "dumbbell.fill", .blue),
                ("Bodyweight", "figure.walk", .teal),
                ("Bands", "circle.hexagongrid.fill", .pink),
                ("Kettlebell", "scalemass.fill", .orange),
                ("Cables", "cable.connector", .orange),
                ("Machines", "gearshape.2.fill", .green),
                ("Barbell", "figure.strengthtraining.traditional", .purple),
                ("Smith Machine", "rectangle.stack.fill", .indigo),
                ("TRX/Rings", "link", .mint)
            ]
        }
    }
}

// MARK: - Equipment Step

struct EquipmentStepView: View {
    @Binding var selectedEquipment: Set<String>
    let userWorkoutEnvironment: String?
    let onBack: () -> Void
    let onGenerate: () -> Void
    
    @State private var selectedLocation: EquipmentLocation = .gym
    @State private var hasInitialized = false
    @State private var showLocationPicker = false
    
    private var equipmentOptions: [(String, String, Color)] {
        selectedLocation.equipmentOptions
    }
    
    private var isAllSelected: Bool {
        selectedEquipment.count == equipmentOptions.count
    }
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(height: 20)
            
            // Header with location dropdown
            VStack(spacing: 12) {
                Text("Select Your Equipment")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                // Location dropdown button
                Menu {
                    ForEach(EquipmentLocation.allCases, id: \.self) { location in
                        Button(action: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                selectedLocation = location
                                selectedEquipment = location.defaultEquipment
                            }
                        }) {
                            Label(location.rawValue, systemImage: location.icon)
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: selectedLocation.icon)
                            .font(.ds_labelLarge)
                        Text(selectedLocation.rawValue)
                            .font(.headline)
                            .fontWeight(.semibold)
                        Image(systemName: "chevron.down")
                            .font(.ds_labelMedium)
                    }
                    .foregroundColor(.blue)
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color.blue.opacity(0.12))
                    )
                }
            }
            .padding(.horizontal, 20)
            
            Spacer()
                .frame(height: 20)
            
            // Select All toggle row
            HStack {
                Spacer()
                
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        if isAllSelected {
                            selectedEquipment.removeAll()
                        } else {
                            selectedEquipment = Set(equipmentOptions.map { $0.0 })
                        }
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: isAllSelected ? "checkmark.square.fill" : "square")
                            .font(.ds_bodyRegular)
                        Text("Select All")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(isAllSelected ? .blue : .secondary)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
            
            // Equipment Grid
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10)
            ], spacing: 12) {
                ForEach(equipmentOptions, id: \.0) { equipment in
                    AutoWorkoutEquipmentCard(
                        title: equipment.0,
                        icon: equipment.1,
                        color: equipment.2,
                        isSelected: selectedEquipment.contains(equipment.0),
                        onTap: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                if selectedEquipment.contains(equipment.0) {
                                    selectedEquipment.remove(equipment.0)
                                } else {
                                    selectedEquipment.insert(equipment.0)
                                }
                            }
                        }
                    )
                }
            }
            .padding(.horizontal, 20)
            
            Spacer()
            
            // Bottom buttons - Back + Generate
            HStack(spacing: 12) {
                // Back button (circular hollow, inline height)
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.ds_labelLarge)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.purple, .blue],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: 52, height: 52)
                        .background(
                            Circle()
                                .fill(Color.darkBackground)
                        )
                        .overlay(
                            Circle()
                                .stroke(
                                    LinearGradient(
                                        colors: [.blue, .cyan],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    ),
                                    lineWidth: 2
                                )
                        )
                }
                
                // Generate button
                Button(action: onGenerate) {
                    HStack(spacing: 10) {
                        Image(systemName: "bolt.fill")
                            .font(.ds_heading3)
                        Text("Generate Workout")
                    }
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(selectedEquipment.isEmpty ? .gray : .white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.md)
                    .background(
                        Group {
                            if selectedEquipment.isEmpty {
                                Capsule().fill(Color.gray.opacity(0.3))
                            } else {
                                Capsule().fill(
                                    LinearGradient(colors: [.blue, .cyan], startPoint: .leading, endPoint: .trailing)
                                )
                            }
                        }
                    )
                    .shadow(color: selectedEquipment.isEmpty ? .clear : .blue.opacity(0.4), radius: 10, x: 0, y: 5)
                }
                .disabled(selectedEquipment.isEmpty)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .onAppear {
            guard !hasInitialized else { return }
            hasInitialized = true
            
            // Set initial location based on user's saved preference from onboarding
            if let env = userWorkoutEnvironment?.lowercased() {
                if env.contains("home") {
                    selectedLocation = .home
                } else if env.contains("outdoor") {
                    selectedLocation = .outdoor
                } else if env.contains("hybrid") {
                    selectedLocation = .hybrid
                } else {
                    selectedLocation = .gym
                }
            }
            
            // Apply default equipment for location
            if selectedEquipment.isEmpty {
                selectedEquipment = selectedLocation.defaultEquipment
            }
        }
    }
}

struct AutoWorkoutEquipmentCard: View {
    @Environment(\.colorScheme) var colorScheme
    let title: String
    let icon: String
    let color: Color
    let isSelected: Bool
    let onTap: () -> Void
    
    private let selectionFeedback = UISelectionFeedbackGenerator()
    
    var body: some View {
        Button(action: {
            selectionFeedback.selectionChanged()
            onTap()
        }) {
            VStack(spacing: 8) {
                ZStack {
                    // Soft glow when selected
                    if isSelected {
                        Circle()
                            .fill(Color.blue.opacity(0.4))
                            .frame(width: 54, height: 54)
                            .blur(radius: 10)
                    }
                    
                    Circle()
                        .fill(
                            isSelected
                                ? LinearGradient(colors: [.blue, .blue.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)
                                : LinearGradient(colors: [Color.gray.opacity(0.15), Color.gray.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .frame(width: 46, height: 46)
                    
                    Image(systemName: icon)
                        .font(.ds_heading3).fontWeight(.semibold)
                        .foregroundColor(isSelected ? .white : .gray)
                }
                
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(isSelected ? .blue : .primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(height: 28)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.sm)
            .sleekCard(cornerRadius: 24, accentColor: isSelected ? .blue : Color(white: 0.4))
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(isSelected ? .blue.opacity(0.6) : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(isSelected ? 1.03 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        .accessibilityLabel("\(title) equipment")
        .accessibilityHint(isSelected ? "Currently selected" : "Double tap to select")
    }
}

// MARK: - Content-Only Views (for shared button bar)

struct DurationStepContentView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var selectedDuration: WorkoutGeneratorSelectionView.WorkoutDuration
    @Binding var customMinutes: Int
    
    private let customDurations = [15, 20, 25, 35, 50, 75]
    
    private var backgroundGradient: LinearGradient {
        LinearGradient(
            gradient: Gradient(colors: colorScheme == .dark
                ? [Color.blue.opacity(0.2), Color.cyan.opacity(0.1), Color(red: 0.04, green: 0.06, blue: 0.10), Color(red: 0.03, green: 0.04, blue: 0.07)]
                : [Color.blue.opacity(0.3), Color.cyan.opacity(0.2), Color.blue.opacity(0.05), Color.white]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 20)
            
            // Header
            VStack(spacing: 8) {
                Text("How long is your workout?")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Text("We'll auto-adjust exercises & rest times")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 20)
            
            Spacer().frame(minHeight: 24, maxHeight: 40)
            
            // Main content
            VStack(spacing: 16) {
                // Quick Select - 2x2 grid
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ], spacing: 12) {
                    ForEach(WorkoutGeneratorSelectionView.WorkoutDuration.allCases.filter { $0 != .custom }, id: \.self) { duration in
                        DurationCard(
                            duration: duration,
                            isSelected: selectedDuration == duration && selectedDuration != .custom,
                            onTap: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    selectedDuration = duration
                                }
                            }
                        )
                    }
                }
                .padding(.horizontal, 20)
                
                // Divider with label
                HStack {
                    Rectangle().fill(Color.gray.opacity(0.2)).frame(height: 1)
                    Text("or custom").font(.caption).foregroundColor(.secondary)
                    Rectangle().fill(Color.gray.opacity(0.2)).frame(height: 1)
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.xs)
                
                // Custom duration tiles - 3x2 grid
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ], spacing: 10) {
                    ForEach(customDurations, id: \.self) { mins in
                        let isSelected = selectedDuration == .custom && customMinutes == mins
                        Button(action: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                selectedDuration = .custom
                                customMinutes = mins
                            }
                        }) {
                            VStack(spacing: 4) {
                                Text("\(mins)")
                                    .font(.title3)
                                    .fontWeight(.bold)
                                    .foregroundColor(isSelected ? .blue : .primary)
                                
                                Text("min")
                                    .font(.caption2)
                                    .fontWeight(.medium)
                                    .foregroundColor(isSelected ? .blue.opacity(0.8) : .secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .sleekCard(cornerRadius: 24, accentColor: isSelected ? .blue : Color(white: 0.4))
                            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 24, style: .continuous)
                                    .stroke(isSelected ? Color.purple.opacity(0.6) : Color.clear, lineWidth: 2)
                            )
                            .shadow(color: isSelected ? .blue.opacity(0.4) : .black.opacity(0.1), radius: isSelected ? 10 : 6, x: 0, y: isSelected ? 5 : 3)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .scaleEffect(isSelected ? 1.03 : 1.0)
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
                    }
                }
                .padding(.horizontal, 20)
            }
            
            Spacer()
        }
        .padding(.bottom, 100) // Space for fixed button bar
        .background(backgroundGradient)
    }
}

struct PrimaryMuscleContentView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var selectedPrimaries: Set<String>
    
    private var backgroundGradient: LinearGradient {
        LinearGradient(
            gradient: Gradient(colors: colorScheme == .dark
                ? [Color.blue.opacity(0.2), Color.cyan.opacity(0.1), Color(red: 0.04, green: 0.06, blue: 0.10), Color(red: 0.03, green: 0.04, blue: 0.07)]
                : [Color.blue.opacity(0.3), Color.cyan.opacity(0.2), Color.blue.opacity(0.05), Color.white]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    private let primaryMuscles = [
        ("Chest", "figure.strengthtraining.traditional", Color.red),
        ("Back", "figure.climbing", Color.blue),
        ("Shoulders", "figure.boxing", Color.orange),
        ("Arms", "figure.strengthtraining.traditional", Color.purple),
        ("Legs", "figure.run", Color.green),
        ("Core", "figure.core.training", Color.yellow)
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 20)
            
            // Header
            VStack(spacing: 8) {
                Text("What muscles do you want to target?")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                
                Text("Select one or more muscle groups")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 20)
            
            Spacer().frame(minHeight: 16, maxHeight: 24)
            
            // Primary Muscles Grid - 3x2 for 6 muscles
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ], spacing: 12) {
                ForEach(primaryMuscles, id: \.0) { muscle in
                    PrimaryMuscleCard(
                        title: muscle.0,
                        icon: muscle.1,
                        color: muscle.2,
                        isSelected: selectedPrimaries.contains(muscle.0),
                        customImage: muscle.0 == "Chest" ? "ChestIcon" : muscle.0 == "Back" ? "BackIcon" : muscle.0 == "Shoulders" ? "ShoulderIcon" : (muscle.0 == "Arms" || muscle.0 == "Biceps") ? "BicepIcon" : muscle.0 == "Triceps" ? "TricepIcon" : muscle.0 == "Core" ? "CoreIcon" : muscle.0 == "Glutes" ? "GlutesIcon" : muscle.0 == "Legs" ? "LegsIcon" : nil,
                        onTap: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                if selectedPrimaries.contains(muscle.0) {
                                    selectedPrimaries.remove(muscle.0)
                                } else {
                                    selectedPrimaries.insert(muscle.0)
                                }
                            }
                        }
                    )
                }
            }
            .padding(.horizontal, 20)
            
            // Show "or" divider only when no muscles selected
            if selectedPrimaries.isEmpty {
                Spacer()
                HStack(spacing: 12) {
                    Rectangle().fill(Color.gray.opacity(0.3)).frame(height: 1)
                    Text("or").font(.subheadline).foregroundColor(.secondary)
                    Rectangle().fill(Color.gray.opacity(0.3)).frame(height: 1)
                }
                .padding(.horizontal, 40)
            }
            
            Spacer()
        }
        .padding(.bottom, 100) // Space for fixed button bar
        .background(backgroundGradient)
    }
}

struct SecondaryMuscleContentView: View {
    @Environment(\.colorScheme) private var colorScheme
    let primaryMuscles: Set<String>
    @Binding var selectedSecondary: Set<String>
    
    private var backgroundGradient: LinearGradient {
        LinearGradient(
            gradient: Gradient(colors: colorScheme == .dark
                ? [Color.blue.opacity(0.2), Color.cyan.opacity(0.1), Color(red: 0.04, green: 0.06, blue: 0.10), Color(red: 0.03, green: 0.04, blue: 0.07)]
                : [Color.blue.opacity(0.3), Color.cyan.opacity(0.2), Color.blue.opacity(0.05), Color.white]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    private let secondaryMuscles: [(String, String, Color)] = [
        ("Forearms", "hand.raised.fill", .orange),
        ("Traps", "figure.stand", .indigo),
        ("Calves", "figure.walk", .mint),
        ("Lower Back", "figure.stand.line.dotted.figure.stand", .brown),
        ("Hip Flexors", "figure.flexibility", .teal),
        ("Rotator Cuff", "arrow.triangle.2.circlepath", .cyan)
    ]
    
    private var availableSecondary: [(String, String, Color)] {
        secondaryMuscles.filter { !primaryMuscles.contains($0.0) }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 20)
            
            // Header
            VStack(spacing: 8) {
                Text("Focus on specific areas?")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Text("Optional: Add secondary muscle focus")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 20)
            
            Spacer().frame(minHeight: 20, maxHeight: 32)
            
            // Secondary muscles scroll view
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 16) {
                    if availableSecondary.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 48))
                                .foregroundColor(.green)
                            Text("All muscle groups covered!")
                                .font(.headline)
                                .foregroundColor(.primary)
                            Text("Your primary selections include all areas")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        .frame(minHeight: 200)
                    } else {
                        LazyVGrid(columns: [
                            GridItem(.flexible(), spacing: 12),
                            GridItem(.flexible(), spacing: 12)
                        ], spacing: 12) {
                            ForEach(availableSecondary, id: \.0) { muscle in
                                SecondaryMuscleCard(
                                    title: muscle.0,
                                    icon: muscle.1,
                                    color: muscle.2,
                                    isSelected: selectedSecondary.contains(muscle.0),
                                    customImage: muscle.0 == "Biceps" ? "BicepIcon" : muscle.0 == "Triceps" ? "TricepIcon" : muscle.0 == "Glutes" ? "GlutesIcon" : muscle.0 == "Forearms" ? "ForearmIcon" : muscle.0 == "Quadriceps" ? "QuadIcon" : muscle.0 == "Hamstrings" ? "HamstringIcon" : muscle.0 == "Lower Back" ? "LowerBackIcon" : muscle.0 == "Upper Back" ? "UpperBackIcon" : muscle.0 == "Calves" ? "CalvesIcon" : muscle.0 == "Lats" ? "LatsIcon" : muscle.0 == "Traps" ? "TrapsIcon" : muscle.0 == "Upper Abs" ? "UpperAbsIcon" : muscle.0 == "Lower Abs" ? "LowerAbsIcon" : muscle.0 == "Obliques" ? "ObliquesIcon" : muscle.0 == "Front Delts" ? "FrontDeltIcon" : muscle.0 == "Rear Delts" ? "RearDeltIcon" : muscle.0 == "Hip Flexors" ? "HipFlexorsIcon" : muscle.0 == "Inner Chest" ? "InnerChestIcon" : muscle.0 == "Upper Chest" ? "UpperChestIcon" : muscle.0 == "Lower Chest" ? "LowerChestIcon" : muscle.0 == "Outer Chest" ? "OuterChestIcon" : nil,
                                    onTap: {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                            if selectedSecondary.contains(muscle.0) {
                                                selectedSecondary.remove(muscle.0)
                                            } else {
                                                selectedSecondary.insert(muscle.0)
                                            }
                                        }
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                }
            }
            
            Spacer()
        }
        .padding(.bottom, 100) // Space for fixed button bar
        .background(backgroundGradient)
    }
}

struct EquipmentContentView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var selectedEquipment: Set<String>
    let userWorkoutEnvironment: String?
    
    @State private var selectedLocation: EquipmentLocation = .gym
    @State private var hasInitialized = false
    
    private var backgroundGradient: LinearGradient {
        LinearGradient(
            gradient: Gradient(colors: colorScheme == .dark
                ? [Color.blue.opacity(0.2), Color.cyan.opacity(0.1), Color(red: 0.04, green: 0.06, blue: 0.10), Color(red: 0.03, green: 0.04, blue: 0.07)]
                : [Color.blue.opacity(0.3), Color.cyan.opacity(0.2), Color.blue.opacity(0.05), Color.white]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    private var equipmentOptions: [(String, String, Color)] {
        selectedLocation.equipmentOptions
    }
    
    private var isAllSelected: Bool {
        equipmentOptions.allSatisfy { selectedEquipment.contains($0.0) }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 20)
            
            // Header with location dropdown
            VStack(spacing: 12) {
                Text("Select Your Equipment")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Menu {
                    ForEach(EquipmentLocation.allCases, id: \.self) { location in
                        Button(action: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                selectedLocation = location
                                selectedEquipment = location.defaultEquipment
                            }
                        }) {
                            Label(location.rawValue, systemImage: location.icon)
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: selectedLocation.icon)
                            .font(.ds_labelLarge)
                        Text(selectedLocation.rawValue)
                            .font(.headline)
                            .fontWeight(.semibold)
                        Image(systemName: "chevron.down")
                            .font(.ds_labelMedium)
                    }
                    .foregroundColor(.blue)
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color.blue.opacity(0.12))
                    )
                }
            }
            .padding(.horizontal, 20)
            
            Spacer().frame(height: 20)
            
            // Select All toggle row
            HStack {
                Spacer()
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        if isAllSelected {
                            selectedEquipment.removeAll()
                        } else {
                            selectedEquipment = Set(equipmentOptions.map { $0.0 })
                        }
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: isAllSelected ? "checkmark.square.fill" : "square")
                            .font(.ds_bodyRegular)
                        Text("Select All")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(isAllSelected ? .blue : .secondary)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
            
            // Equipment Grid
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10)
            ], spacing: 12) {
                ForEach(equipmentOptions, id: \.0) { equipment in
                    AutoWorkoutEquipmentCard(
                        title: equipment.0,
                        icon: equipment.1,
                        color: equipment.2,
                        isSelected: selectedEquipment.contains(equipment.0),
                        onTap: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                if selectedEquipment.contains(equipment.0) {
                                    selectedEquipment.remove(equipment.0)
                                } else {
                                    selectedEquipment.insert(equipment.0)
                                }
                            }
                        }
                    )
                }
            }
            .padding(.horizontal, 20)
            
            Spacer()
        }
        .padding(.bottom, 100) // Space for fixed button bar
        .background(backgroundGradient)
        .onAppear {
            guard !hasInitialized else { return }
            hasInitialized = true
            
            if let env = userWorkoutEnvironment?.lowercased() {
                if env.contains("home") { selectedLocation = .home }
                else if env.contains("outdoor") { selectedLocation = .outdoor }
                else if env.contains("hybrid") { selectedLocation = .hybrid }
                else { selectedLocation = .gym }
            }
            
            if selectedEquipment.isEmpty {
                selectedEquipment = selectedLocation.defaultEquipment
            }
        }
    }
}

// MARK: - Tiles-Only Views (for sliding content)

struct DurationTilesView: View {
    @Binding var selectedDuration: WorkoutGeneratorSelectionView.WorkoutDuration
    @Binding var customMinutes: Int

    private let customDurations = [20, 35, 75]  // Simplified options

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 16) {
                // Quick Select - 2x2 grid (aligned with muscle tiles)
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ], spacing: 12) {
                    ForEach(WorkoutGeneratorSelectionView.WorkoutDuration.allCases.filter { $0 != .custom }, id: \.self) { duration in
                        DurationCard(
                            duration: duration,
                            isSelected: selectedDuration == duration && selectedDuration != .custom,
                            onTap: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    selectedDuration = duration
                                }
                            }
                        )
                    }
                }
                
                // Divider
                HStack {
                    Rectangle().fill(Color.gray.opacity(0.2)).frame(height: 1)
                    Text("or custom").font(.caption).foregroundColor(.secondary)
                    Rectangle().fill(Color.gray.opacity(0.2)).frame(height: 1)
                }
                .padding(.vertical, Spacing.xs)
                
                // Custom duration tiles
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ], spacing: 10) {
                    ForEach(customDurations, id: \.self) { mins in
                        let isSelected = selectedDuration == .custom && customMinutes == mins
                        Button(action: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                selectedDuration = .custom
                                customMinutes = mins
                            }
                        }) {
                            VStack(spacing: 4) {
                                Text("\(mins)").font(.title3).fontWeight(.bold)
                                    .foregroundColor(isSelected ? .blue : .primary)
                                Text("min").font(.caption2).fontWeight(.medium)
                                    .foregroundColor(isSelected ? .blue.opacity(0.8) : .secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .sleekCard(cornerRadius: 24, accentColor: isSelected ? .blue : Color(white: 0.4))
                            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 24, style: .continuous)
                                    .stroke(isSelected ? Color.purple.opacity(0.6) : Color.clear, lineWidth: 2)
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                        .scaleEffect(isSelected ? 1.03 : 1.0)
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20) // Top padding so tiles aren't too close to header
            .padding(.bottom, 120)
        }
    }
}

struct PrimaryMuscleTilesView: View {
    @Binding var selectedPrimaries: Set<String>
    @Binding var surpriseMeSelected: Bool

    private let primaryMuscles = [
        ("Chest", "figure.strengthtraining.traditional", Color.red),
        ("Back", "figure.climbing", Color.blue),
        ("Shoulders", "figure.boxing", Color.orange),
        ("Arms", "figure.strengthtraining.traditional", Color.purple),
        ("Legs", "figure.run", Color.green),
        ("Core", "figure.core.training", Color.yellow)
    ]

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 16) {
                // Surprise Me button at top - pill shaped, matches Continue style
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        surpriseMeSelected = true
                        selectedPrimaries.removeAll() // Clear muscle selections
                    }
                }) {
                    Text("Surprise Me")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundStyle(
                            surpriseMeSelected
                                ? AnyShapeStyle(LinearGradient(colors: [.blue, .cyan], startPoint: .leading, endPoint: .trailing))
                                : AnyShapeStyle(Color.gray)
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.md)
                        .background(
                            Capsule()
                                .fill(Color.darkBackground)
                        )
                        .overlay(
                            Capsule()
                                .stroke(
                                    surpriseMeSelected
                                        ? AnyShapeStyle(LinearGradient(colors: [.blue, .cyan], startPoint: .leading, endPoint: .trailing))
                                        : AnyShapeStyle(Color.gray.opacity(0.3)),
                                    lineWidth: 2
                                )
                        )
                }
                .buttonStyle(PlainButtonStyle())
                
                // "or" divider
                HStack(spacing: 12) {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 1)
                    Text("or")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 1)
                }
                .padding(.vertical, Spacing.xxs)
                
                // Muscle tiles grid - 3x2 for 6 muscles
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ], spacing: 12) {
                    ForEach(primaryMuscles, id: \.0) { muscle in
                        PrimaryMuscleCard(
                            title: muscle.0,
                            icon: muscle.1,
                            color: muscle.2,
                            isSelected: selectedPrimaries.contains(muscle.0),
                            customImage: muscle.0 == "Chest" ? "ChestIcon" : muscle.0 == "Back" ? "BackIcon" : muscle.0 == "Shoulders" ? "ShoulderIcon" : (muscle.0 == "Arms" || muscle.0 == "Biceps") ? "BicepIcon" : muscle.0 == "Triceps" ? "TricepIcon" : muscle.0 == "Core" ? "CoreIcon" : muscle.0 == "Glutes" ? "GlutesIcon" : muscle.0 == "Legs" ? "LegsIcon" : nil,
                            onTap: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    surpriseMeSelected = false // Deselect surprise me
                                    if selectedPrimaries.contains(muscle.0) {
                                        selectedPrimaries.remove(muscle.0)
                                    } else {
                                        selectedPrimaries.insert(muscle.0)
                                    }
                                }
                            }
                        )
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 120)
        }
    }
}

struct SecondaryMuscleTilesView: View {
    let primaryMuscles: Set<String>
    @Binding var selectedSecondary: Set<String>
    
    // Muscle group data - specific areas for each primary muscle
    private let muscleGroupData: [String: (options: [(String, String, Color)], color: Color)] = [
        "Chest": (
            options: [
                ("Upper Chest", "arrow.up.circle.fill", .red),
                ("Lower Chest", "arrow.down.circle.fill", .red),
                ("Inner Chest", "arrow.left.and.right.circle.fill", .red),
                ("Outer Chest", "arrow.up.left.and.arrow.down.right.circle.fill", .red)
            ],
            color: .red
        ),
        "Back": (
            options: [
                ("Lats", "figure.strengthtraining.traditional", .blue),
                ("Traps", "figure.strengthtraining.traditional", .blue),
                ("Upper Back", "arrow.up.circle.fill", .blue),
                ("Lower Back", "arrow.down.circle.fill", .blue)
            ],
            color: .blue
        ),
        "Shoulders": (
            options: [
                ("Front Delts", "circle.lefthalf.filled", .orange),
                ("Side Delts", "circle.fill", .orange),
                ("Rear Delts", "circle.righthalf.filled", .orange)
            ],
            color: .orange
        ),
        "Arms": (
            options: [
                ("Biceps", "figure.strengthtraining.traditional", .purple),
                ("Triceps", "figure.strengthtraining.traditional", .purple),
                ("Forearms", "figure.strengthtraining.traditional", .purple)
            ],
            color: .purple
        ),
        "Legs": (
            options: [
                ("Quadriceps", "figure.run", .green),
                ("Hamstrings", "figure.run", .green),
                ("Glutes", "figure.run", .green),
                ("Calves", "figure.run", .green),
                ("Hip Flexors", "figure.run", .green)
            ],
            color: .green
        ),
        "Core": (
            options: [
                ("Upper Abs", "figure.core.training", .yellow),
                ("Lower Abs", "figure.core.training", .yellow),
                ("Obliques", "figure.core.training", .yellow)
            ],
            color: .yellow
        )
    ]
    
    // Get grouped options based on selected primary muscles
    private var groupedSecondaryOptions: [(primary: String, options: [(String, String, Color)], color: Color)] {
        primaryMuscles
            .compactMap { primary in
                guard let data = muscleGroupData[primary] else { return nil }
                return (primary: primary, options: data.options, color: data.color)
            }
            .sorted { $0.primary < $1.primary }
    }
    
    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 20) {
                if groupedSecondaryOptions.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "info.circle.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.blue)
                        Text("No specific areas available")
                            .font(.headline)
                        Text("Select primary muscles to see options")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(minHeight: 200)
                } else {
                    // Show each primary muscle's specific areas
                    ForEach(groupedSecondaryOptions, id: \.primary) { group in
                        VStack(alignment: .leading, spacing: 10) {
                            // Category header
                            Text(group.primary)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(group.color)
                                .padding(.leading, 4)
                            
                            // Options grid for this category - 4 columns (matches primary)
                            LazyVGrid(columns: [
                                GridItem(.flexible(), spacing: 10),
                                GridItem(.flexible(), spacing: 10),
                                GridItem(.flexible(), spacing: 10),
                                GridItem(.flexible(), spacing: 10)
                            ], spacing: 10) {
                                ForEach(group.options, id: \.0) { option in
                                    SmallSecondaryMuscleCard(
                                        title: option.0,
                                        icon: option.1,
                                        color: option.2,
                                        isSelected: selectedSecondary.contains(option.0),
                                        customImage: option.0 == "Biceps" ? "BicepIcon" : option.0 == "Triceps" ? "TricepIcon" : option.0 == "Glutes" ? "GlutesIcon" : option.0 == "Forearms" ? "ForearmIcon" : option.0 == "Quadriceps" ? "QuadIcon" : option.0 == "Hamstrings" ? "HamstringIcon" : option.0 == "Lower Back" ? "LowerBackIcon" : option.0 == "Upper Back" ? "UpperBackIcon" : option.0 == "Calves" ? "CalvesIcon" : option.0 == "Lats" ? "LatsIcon" : option.0 == "Traps" ? "TrapsIcon" : option.0 == "Upper Abs" ? "UpperAbsIcon" : option.0 == "Lower Abs" ? "LowerAbsIcon" : option.0 == "Obliques" ? "ObliquesIcon" : option.0 == "Front Delts" ? "FrontDeltIcon" : option.0 == "Rear Delts" ? "RearDeltIcon" : option.0 == "Hip Flexors" ? "HipFlexorsIcon" : option.0 == "Inner Chest" ? "InnerChestIcon" : option.0 == "Upper Chest" ? "UpperChestIcon" : option.0 == "Lower Chest" ? "LowerChestIcon" : option.0 == "Outer Chest" ? "OuterChestIcon" : nil,
                                        onTap: {
                                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                                if selectedSecondary.contains(option.0) {
                                                    selectedSecondary.remove(option.0)
                                                } else {
                                                    selectedSecondary.insert(option.0)
                                                }
                                            }
                                        }
                                    )
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 120)
        }
    }
}

struct EquipmentTilesView: View {
    @Binding var selectedEquipment: Set<String>
    @Binding var selectedLocation: EquipmentLocation
    
    private var equipmentOptions: [(String, String, Color)] {
        selectedLocation.equipmentOptions
    }
    
    private var isAllSelected: Bool {
        equipmentOptions.allSatisfy { selectedEquipment.contains($0.0) }
    }
    
    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 12) {
                // Location dropdown + Select All on same row
                HStack {
                    // Location dropdown (left side)
                    Menu {
                        ForEach(EquipmentLocation.allCases, id: \.self) { location in
                            Button(action: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    selectedLocation = location
                                    selectedEquipment = location.defaultEquipment
                                }
                            }) {
                                Label(location.rawValue, systemImage: location.icon)
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: selectedLocation.icon)
                                .font(.ds_labelMedium)
                            Text(selectedLocation.rawValue)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Image(systemName: "chevron.down")
                                .font(.ds_caption).fontWeight(.semibold)
                        }
                        .foregroundColor(.blue)
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, Spacing.xs)
                        .background(
                            RoundedRectangle(cornerRadius: CornerRadius.sm)
                                .fill(Color.blue.opacity(0.12))
                        )
                    }
                    
                    Spacer()
                    
                    // Select All toggle (right side)
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            if isAllSelected {
                                selectedEquipment.removeAll()
                            } else {
                                selectedEquipment = Set(equipmentOptions.map { $0.0 })
                            }
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: isAllSelected ? "checkmark.square.fill" : "square")
                                .font(.ds_bodySmall)
                            Text("Select All")
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                        .foregroundColor(isAllSelected ? .blue : .secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.bottom, 8)
                
                // Equipment Grid
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ], spacing: 12) {
                    ForEach(equipmentOptions, id: \.0) { equipment in
                        AutoWorkoutEquipmentCard(
                            title: equipment.0,
                            icon: equipment.1,
                            color: equipment.2,
                            isSelected: selectedEquipment.contains(equipment.0),
                            onTap: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    if selectedEquipment.contains(equipment.0) {
                                        selectedEquipment.remove(equipment.0)
                                    } else {
                                        selectedEquipment.insert(equipment.0)
                                    }
                                }
                            }
                        )
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20) // Top padding so tiles aren't too close to header
            .padding(.bottom, 120)
        }
    }
}
