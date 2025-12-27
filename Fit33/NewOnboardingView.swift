import SwiftUI
import Combine

// MARK: - Keyboard Height Observer
class KeyboardObserver: ObservableObject {
    @Published var keyboardHeight: CGFloat = 0
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)
            .compactMap { ($0.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect)?.height }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] height in
                withAnimation(.easeOut(duration: 0.25)) {
                    self?.keyboardHeight = height
                }
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                withAnimation(.easeOut(duration: 0.25)) {
                    self?.keyboardHeight = 0
                }
            }
            .store(in: &cancellables)
    }
}

// MARK: - New Onboarding Flow
// Clean, professional onboarding with auth + profile setup

struct NewOnboardingView: View {
    @EnvironmentObject var userManager: UserManager
    @StateObject private var supabaseManager = SupabaseManager.shared
    @StateObject private var keyboardObserver = KeyboardObserver()
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var currentStep: OnboardingStep = .auth
    @State private var animateTransition = false
    
    // Auth fields
    @State private var isSignUp = true  // Default to Sign Up
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var showPassword = false
    @State private var showConfirmPassword = false
    @State private var name = ""
    @State private var errorMessage = ""
    @State private var showError = false
    @State private var emailAlreadyExists = false
    @State private var acceptedTerms = false
    @State private var showTermsSheet = false
    @State private var passwordResetSent = false
    
    // Social auth
    @StateObject private var socialAuthService = SocialAuthService.shared
    @State private var showGoogleSignIn = false
    @State private var detectedAuthProvider = ""  // "apple", "google", "email", "none"
    @State private var showAuthProviderHint = false
    @State private var authProviderHintMessage = ""
    
    // Profile fields
    @State private var birthday = ""  // Formatted with slashes: MM/DD/YYYY
    
    // Format birthday string with auto-inserted slashes
    private func formatBirthday(_ input: String) -> String {
        let digits = input.filter { $0.isNumber }
        let limited = String(digits.prefix(8))
        
        var result = ""
        for (index, char) in limited.enumerated() {
            if index == 2 || index == 4 {
                result += "/"
            }
            result += String(char)
        }
        return result
    }
    @State private var selectedGender: String? = nil
    @State private var heightFeetInchesDigits = ""  // Just digits: e.g., "510" for 5'10"
    @State private var heightCm = ""
    @State private var weight = ""
    
    
    // Height digits are now stored directly (no need to extract)
    private var heightDigits: String {
        heightFeetInchesDigits
    }
    @State private var selectedGoals: Set<String> = []
    @State private var selectedExperience = ""
    @State private var selectedStrengthLevel: StrengthProfileRecommendationEngine.StrengthLevel = .moderate
    @State private var selectedWorkoutLocation: WorkoutEnvironmentService.WorkoutEnvironment = .gym
    @State private var selectedEquipment: Set<String> = []
    @State private var selectedEquipmentLocation: EquipmentLocation = .gym
    @State private var selectedDays = 4
    @State private var selectedLimitations: Set<AffectedArea> = []  // Injury/limitation tracking
    @State private var limitationAccommodations: [AffectedArea: AccommodationLevel] = [:]  // Accommodation level per area
    
    // Unit preferences - default based on user's locale
    @State private var heightUnit: HeightUnit = UnitSettingsManager.localeUsesImperial ? .ftIn : .cm
    @State private var weightUnit: WeightUnit = UnitSettingsManager.localeUsesImperial ? .lbs : .kg
    
    enum HeightUnit: String, CaseIterable {
        case ftIn = "ft"
        case cm = "cm"
    }
    
    enum WeightUnit: String, CaseIterable {
        case lbs = "lbs"
        case kg = "kg"
    }
    
    // Focus states for keeping keyboard up
    enum FocusedField: Hashable {
        case email, password, confirmPassword, name, birthday, height, weight
    }
    @FocusState private var focusedField: FocusedField?
    
    // Track if we're editing from confirmation screen (to return there after edit)
    @State private var isEditingFromConfirmation = false
    
    // MARK: - Validation Error Messages (UX Audit Fix #1)
    private var birthdayValidationError: String? {
        guard birthday.count == 10 else { return nil } // Only validate complete dates
        if birthdayDate == nil {
            return "Please enter a valid date"
        }
        if calculatedAge < 13 {
            return "You must be at least 13 years old"
        }
        if calculatedAge > 120 {
            return "Please enter a valid birth year"
        }
        return nil
    }
    
    private var heightValidationError: String? {
        if heightUnit == .ftIn && heightFeetInchesDigits.count >= 2 && !isHeightValid {
            return "Please enter a valid height (3'0\" - 8'11\")"
        }
        if heightUnit == .cm && heightCm.count >= 2 && !isHeightValid {
            return "Please enter a valid height (90-270 cm)"
        }
        return nil
    }
    
    private var weightValidationError: String? {
        if weight.count >= 2 && !isWeightValid {
            return "Please enter a valid weight"
        }
        return nil
    }
    
    // MARK: - Progress Indicator (UX Audit Fix #2)
    private var progressValue: Double {
        Double(currentStep.rawValue) / Double(OnboardingStep.allCases.count - 1)
    }
    
    private var stepDescription: String {
        switch currentStep {
        case .auth: return "Account"
        case .basics: return "About You"
        case .body: return "Measurements"
        case .goal: return "Goals"
        case .experience: return "Experience"
        case .strengthAssessment: return "Strength"
        case .workoutLocation: return "Location"
        case .equipment: return "Equipment"
        case .limitations: return "Health"
        case .schedule: return "Schedule"
        case .confirmation: return "Review"
        case .complete: return "Done!"
        }
    }
    
    // MARK: - Height Preview (UX Audit Fix #3)
    private var heightPreviewText: String? {
        guard heightUnit == .ftIn, let parsed = parsedHeightFeetInches else { return nil }
        return "\(parsed.feet)' \(parsed.inches)\""
    }
    
    // Haptic feedback generator (UX Audit Fix #6)
    private let selectionFeedback = UISelectionFeedbackGenerator()
    private let impactFeedback = UIImpactFeedbackGenerator(style: .light)
    
    enum OnboardingStep: Int, CaseIterable {
        case auth = 0
        case basics = 1      // Birthday + Gender
        case body = 2        // Height + Weight
        case goal = 3
        case experience = 4
        case strengthAssessment = 5  // How heavy can you lift?
        case workoutLocation = 6     // Where do you workout?
        case equipment = 7
        case limitations = 8  // NEW: Injuries/limitations
        case schedule = 9
        case confirmation = 10  // Review all selections before creating account
        case complete = 11
    }
    
    // Validation for auth step
    // Password validation requirements
    private var hasMinLength: Bool { password.count >= 8 }
    private var hasUppercase: Bool { password.contains(where: { $0.isUppercase }) }
    private var hasLowercase: Bool { password.contains(where: { $0.isLowercase }) }
    private var hasNumber: Bool { password.contains(where: { $0.isNumber }) }
    private var hasSpecialChar: Bool { password.contains(where: { "!@#$%^&*()_+-=[]{}|;':\",./<>?".contains($0) }) }
    private var passwordsMatch: Bool { password == confirmPassword && !confirmPassword.isEmpty }
    
    private var isPasswordValid: Bool {
        hasMinLength && hasUppercase && hasLowercase && hasNumber && hasSpecialChar
    }
    
    private var isAuthFormValid: Bool {
        if isSignUp {
            return !email.isEmpty && email.contains("@") && !name.isEmpty && isPasswordValid && passwordsMatch && acceptedTerms
        } else {
            return !email.isEmpty && email.contains("@") && !password.isEmpty
        }
        }
        
    // Navigate to step and set appropriate focus
    private func navigateTo(_ step: OnboardingStep, animated: Bool = true) {
        // Map onboarding step to screen ID
        let screenMap: [OnboardingStep: SessionLogManager.Screen] = [
            .auth: .authScreen,
            .basics: .onboardingBasics,
            .body: .onboardingBody,
            .goal: .onboardingGoal,
            .experience: .onboardingExperience,
            .strengthAssessment: .onboardingStrength,
            .workoutLocation: .onboardingLocation,
            .equipment: .onboardingEquipment,
            .limitations: .onboardingLimitations,
            .schedule: .onboardingSchedule,
            .confirmation: .onboardingConfirmation,
            .complete: .onboardingComplete
        ]
        
        // Log with screen ID
        if let screen = screenMap[step] {
            SessionLogManager.shared.logScreen(screen, metadata: [
                "step_number": step.rawValue,
                "editing_from_confirmation": isEditingFromConfirmation
            ])
        }
        
        // Log onboarding step transition
        SessionLogManager.shared.logOnboardingStep(
            step: step.rawValue,
            stepName: "\(step)",
            action: "navigated"
        )
        
        // Change step - with or without animation
        if animated && !isEditingFromConfirmation {
        withAnimation(.easeInOut(duration: 0.25)) {
            currentStep = step
        }
        } else {
            // No animation when editing from confirmation
            currentStep = step
        }
    }
    
    // Navigation direction for slide animation
    @State private var isNavigatingForward = true
    
    private var slideTransition: AnyTransition {
        AnyTransition.asymmetric(
            insertion: .move(edge: isNavigatingForward ? .trailing : .leading),
            removal: .move(edge: isNavigatingForward ? .leading : .trailing)
        )
    }
    
    var body: some View {
        ZStack {
            // Animated gradient background
            backgroundGradient
            
            // Auth step has its own layout (with keyboard handling)
            if currentStep == .auth {
                authStep
            }
            
            // Complete step has its own layout (celebration)
            if currentStep == .complete {
                completeStep
            }
            
            // Main onboarding flow (shared header + sliding content + floating button)
            if currentStep != .auth && currentStep != .complete && currentStep != .confirmation && currentStep != .limitations {
                let keyboardUp = keyboardObserver.keyboardHeight > 0
                
                ZStack(alignment: .bottom) {
                    // Main content
                    VStack(spacing: 0) {
                        // Header
                        onboardingSharedHeader(compact: keyboardUp)
                        
                        // Content
                        ZStack {
                            if currentStep == .basics { basicsStepContent.transition(slideTransition) }
                            if currentStep == .body { bodyStepContent.transition(slideTransition) }
                            if currentStep == .goal { goalStepContent.transition(slideTransition) }
                            if currentStep == .experience { experienceStepContent.transition(slideTransition) }
                            if currentStep == .strengthAssessment { strengthStepContent.transition(slideTransition) }
                            if currentStep == .workoutLocation { locationStepContent.transition(slideTransition) }
                            if currentStep == .equipment { equipmentStepContent.transition(slideTransition) }
                            if currentStep == .schedule { scheduleStepContent.transition(slideTransition) }
                        }
                        .animation(.easeInOut(duration: 0.3), value: currentStep)
                        
                        Spacer()
                    }
                    
                    // Floating Continue button - IDENTICAL to auth step positioning
                    onboardingSharedButtonBar
                        .padding(.horizontal, 24)
                        .padding(.bottom, keyboardUp ? keyboardObserver.keyboardHeight + 10 : 50)
                        .animation(.easeOut(duration: 0.25), value: keyboardObserver.keyboardHeight)
                }
            }
            
            // Limitations step - separate layout with bounded scroll area
            if currentStep == .limitations {
                VStack(spacing: 0) {
                    // Header
                    onboardingSharedHeader(compact: false)
                    
                    // Scrollable list container - fills remaining space above buttons
                    ScrollView(showsIndicators: true) {
                        VStack(spacing: 16) {
                            ForEach(AffectedArea.commonAreas, id: \.self) { area in
                                limitationRowWithDropdown(for: area)
                            }
                            
                            // None option
                            Button(action: { 
                                selectedLimitations.removeAll()
                                limitationAccommodations.removeAll()
                            }) {
                                Text("No limitations")
                                    .font(.subheadline)
                                    .foregroundColor(selectedLimitations.isEmpty ? .blue : .secondary)
                                    .padding(.top, 8)
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 8)
                        .padding(.bottom, 16)
                    }
                    .clipped() // Hard clip at the scroll boundary
                    
                    // Fixed button bar at bottom
                    onboardingSharedButtonBar
                        .padding(.horizontal, 24)
                        .padding(.top, 16)
                        .padding(.bottom, 50)
                }
            }
            
            // Confirmation step - separate layout with bounded scroll area
            if currentStep == .confirmation {
                VStack(spacing: 0) {
                    // Header
                    onboardingSharedHeader(compact: false)
                    
                    // Scrollable list container - fills remaining space above buttons
                    ScrollView(showsIndicators: true) {
                        VStack(spacing: 12) {
                            // Show error message if signup failed
                            if showError && !errorMessage.isEmpty {
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack(spacing: 10) {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundColor(.red)
                                        Text("Account Creation Failed")
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                            .foregroundColor(.red)
                                    }
                                    Text(errorMessage)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                    
                                    if errorMessage.contains("weak") || errorMessage.contains("password") {
                                        Text("💡 Tip: Use at least 8 characters with letters, numbers, and symbols")
                                            .font(.caption2)
                                            .foregroundColor(.blue)
                                            .padding(.top, 4)
                                        
                                        Button(action: {
                                            showError = false
                                            errorMessage = ""
                                            navigateTo(.auth)
                                        }) {
                                            Text("Change Password")
                                                .font(.caption)
                                                .fontWeight(.semibold)
                                                .foregroundColor(.white)
                                                .padding(.horizontal, 16)
                                                .padding(.vertical, 8)
                                                .background(Capsule().fill(Color.blue))
                                        }
                                        .padding(.top, 4)
                                    }
                                }
                                .padding()
                                .background(RoundedRectangle(cornerRadius: 10).fill(Color.red.opacity(0.1)))
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.red.opacity(0.3), lineWidth: 1))
                                .padding(.bottom, 8)
                            }
                            
                            confirmationRowSimple(title: "Name", value: name.isEmpty ? "-" : name, editStep: .auth)
                            confirmationRowSimple(title: "Email", value: email.isEmpty ? "-" : email, editStep: .auth)
                            confirmationRowSimple(title: "Birthday", value: birthday, editStep: .basics)
                            confirmationRowSimple(title: "Gender", value: selectedGender ?? "Not specified", editStep: .basics)
                            confirmationRowSimple(title: "Height", value: formatHeightDisplay(), editStep: .body)
                            confirmationRowSimple(title: "Weight", value: "\(weight) \(weightUnit == .lbs ? "lbs" : "kg")", editStep: .body)
                            confirmationRowSimple(title: "Goals", value: selectedGoals.joined(separator: ", "), editStep: .goal)
                            confirmationRowSimple(title: "Experience", value: selectedExperience, editStep: .experience)
                            confirmationRowSimple(title: "Location", value: selectedWorkoutLocation.rawValue.capitalized, editStep: .workoutLocation)
                            confirmationRowSimple(title: "Days/Week", value: "\(selectedDays)", editStep: .schedule)
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 8)
                        .padding(.bottom, 16)
                    }
                    .clipped() // Hard clip at the scroll boundary
                    
                    // Fixed button bar at bottom
                    onboardingSharedButtonBar
                        .padding(.horizontal, 24)
                        .padding(.top, 16)
                        .padding(.bottom, 50)
                }
            }
        }
        .preferredColorScheme(.light)
        .sheet(isPresented: $showTermsSheet) {
            TermsAndConditionsSheet()
        }
        .onChange(of: currentStep) { oldStep, newStep in
            // Set focus based on the new step
            switch newStep {
            case .auth:
                break
            case .basics:
                focusedField = .birthday
            case .body:
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    focusedField = .height
                }
            case .equipment:
                // Sync equipment location with workout location
                selectedEquipmentLocation = mapWorkoutLocationToEquipmentLocation(selectedWorkoutLocation)
                // Pre-select default equipment based on location
                selectedEquipment = selectedEquipmentLocation.defaultEquipment
            default:
                focusedField = nil
            }
        }
        .onChange(of: selectedWorkoutLocation) { _, newLocation in
            // When workout location changes, update equipment location
            selectedEquipmentLocation = mapWorkoutLocationToEquipmentLocation(newLocation)
        }
    }
    
    // MARK: - Shared Header (Simple, fixed layout)
    @ViewBuilder
    private func onboardingSharedHeader(compact: Bool = false) -> some View {
        VStack(spacing: 16) {
            // Logo
            Image("fit33-logo")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 110, height: 44)
                .clipped()
            
            // Progress bar
            progressIndicator
            
            // Title + subtitle (always show)
            VStack(spacing: 6) {
                Text(onboardingStepTitle)
                    .font(.title3.weight(.bold))
                    .foregroundColor(.primary)
                
                Text(onboardingStepSubtitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.top, 70) // Safe area clearance
        .padding(.bottom, 24)
    }

    // MARK: - Step Titles
    private var onboardingStepTitle: String {
        switch currentStep {
        case .auth: return "Create Account"
        case .basics: return "About You"
        case .body: return "Your Measurements"
        case .goal: return "Your Goals"
        case .experience: return "Experience Level"
        case .strengthAssessment: return "Strength Level"
        case .workoutLocation: return "Where You Train"
        case .equipment: return "Your Equipment"
        case .limitations: return "Any Limitations?"
        case .schedule: return "Your Schedule"
        case .confirmation: return "Review & Confirm"
        case .complete: return "You're All Set!"
        }
    }
    
    private var onboardingStepSubtitle: String {
        switch currentStep {
        case .auth: return "Start your fitness journey"
        case .basics: return "Help us personalize your experience"
        case .body: return "For accurate recommendations"
        case .goal: return "What do you want to achieve?"
        case .experience: return "How long have you been training?"
        case .strengthAssessment: return "Helps us pick the right weights"
        case .workoutLocation: return "Where will you workout?"
        case .equipment: return "What do you have access to?"
        case .limitations: return "Anything we should know about?"
        case .schedule: return "How often do you want to train?"
        case .confirmation: return "Make sure everything looks right"
        case .complete: return "Let's start your first workout"
        }
    }
    
    private var onboardingStepExplanation: String {
        switch currentStep {
        case .auth: return ""
        case .basics: return "We use your age to calculate calorie needs and tailor workout intensity"
        case .body: return "Height and weight help us recommend appropriate exercise loads"
        case .goal: return "Your goals shape the type of workouts we'll recommend"
        case .experience: return "This helps us match exercises to your skill level"
        case .strengthAssessment: return "We'll suggest starting weights that match your current strength"
        case .workoutLocation: return "Different locations have different equipment available"
        case .equipment: return "We'll only recommend exercises you can actually do"
        case .limitations: return "We'll avoid exercises that could aggravate injuries or issues"
        case .schedule: return "We'll build a program that fits your weekly availability"
        case .confirmation: return ""
        case .complete: return ""
        }
    }
    
    // MARK: - Shared Button Bar
    private var onboardingSharedButtonBar: some View {
        HStack(spacing: 12) {
            // Back button - always show (goes to auth from basics, or previous step)
            Button(action: {
                isNavigatingForward = false
                withAnimation { goToPreviousStep() }
            }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.gray)
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(Color(.systemGray6)))
                    .overlay(Circle().stroke(Color.gray.opacity(0.3), lineWidth: 1.5))
            }
            
            // Continue button
            Button(action: {
                isNavigatingForward = true
                withAnimation { goToNextStep() }
            }) {
                Text(currentStep == .confirmation ? "Create Account" : "Continue")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundStyle(
                        isCurrentStepValid
                            ? AnyShapeStyle(LinearGradient(colors: [.blue, .blue, .cyan.opacity(0.8)], startPoint: .leading, endPoint: .trailing))
                            : AnyShapeStyle(Color.gray)
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Capsule().fill(Color(.systemGray6)))
                    .overlay(
                        Capsule()
                            .stroke(
                                isCurrentStepValid
                                    ? AnyShapeStyle(LinearGradient(colors: [.blue, .blue, .cyan.opacity(0.8)], startPoint: .leading, endPoint: .trailing))
                                    : AnyShapeStyle(Color.gray.opacity(0.3)),
                                lineWidth: 2
                            )
                    )
            }
            .disabled(!isCurrentStepValid)
        }
    }
    
    // MARK: - Step Validation
    private var isCurrentStepValid: Bool {
        switch currentStep {
        case .auth: return isAuthFormValid
        case .basics: return selectedGender != nil && !birthday.isEmpty
        case .body: return !heightFeetInchesDigits.isEmpty && !weight.isEmpty
        case .goal: return !selectedGoals.isEmpty
        case .experience: return !selectedExperience.isEmpty
        case .strengthAssessment: return true
        case .workoutLocation: return true
        case .equipment: return !selectedEquipment.isEmpty
        case .limitations: return true
        case .schedule: return selectedDays > 0
        case .confirmation: return true
        case .complete: return true
        }
    }
    
    // MARK: - Navigation Helpers
    private func goToNextStep() {
        if currentStep == .confirmation {
            // Handle account creation
            handleConfirmation()
            return
        }
        
        // If editing from confirmation, return to confirmation screen
        if isEditingFromConfirmation {
            isEditingFromConfirmation = false
            navigateTo(.confirmation)
            return
        }
        
        guard let nextStep = OnboardingStep(rawValue: currentStep.rawValue + 1) else { return }
        navigateTo(nextStep)
    }
    
    private func goToPreviousStep() {
        // If editing from confirmation, go back to confirmation
        if isEditingFromConfirmation {
            isEditingFromConfirmation = false
            navigateTo(.confirmation)
            return
        }
        
        guard let prevStep = OnboardingStep(rawValue: currentStep.rawValue - 1) else { return }
        navigateTo(prevStep)
    }
    
    // MARK: - Content-Only Step Views (for sliding)
    // These are simplified versions that just show the content portion
    // The existing full step views (basicsStep, bodyStep, etc.) are kept for reference
    
    private var basicsStepContent: some View {
        VStack(spacing: 28) {
            // Birthday
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Birthday")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.secondary)
                    Spacer()
                    if isBirthdayValid && calculatedAge >= 13 && calculatedAge <= 120 {
                        Text("\(calculatedAge) years old ✓")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                }
                
                OnboardingTextField(
                    icon: "calendar",
                    placeholder: "MM/DD/YYYY",
                    text: $birthday,
                    keyboardType: .numberPad,
                    focusedField: $focusedField,
                    fieldValue: .birthday,
                    isValid: isBirthdayValid
                )
                .onChange(of: birthday) { _, newValue in
                    birthday = formatBirthday(newValue)
                }
            }
            
            // Gender
            VStack(alignment: .leading, spacing: 10) {
                Text("Gender (optional)")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.secondary)
                
                HStack(spacing: 10) {
                    ForEach(["Male", "Female", "Other"], id: \.self) { gender in
                        GenderButton(
                            title: gender,
                            isSelected: selectedGender == gender,
                            action: { selectedGender = selectedGender == gender ? nil : gender }
                        )
                    }
                }
            }
        }
        .padding(.horizontal, 24)
    }
    
    private var bodyStepContent: some View {
        let keyboardUp = keyboardObserver.keyboardHeight > 0
        
        return VStack(alignment: .leading, spacing: keyboardUp ? 16 : 24) {
            // Height with unit toggle
            VStack(alignment: .leading, spacing: 8) {
                Text("Height")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                
                measurementInputField(
                    icon: "ruler",
                    placeholder: heightUnit == .ftIn ? "5'10\"" : "175",
                    text: heightUnit == .ftIn ? $heightFeetInchesDigits : $heightCm,
                    keyboardType: .numberPad,
                    field: .height,
                    isValid: heightUnit == .ftIn ? !heightFeetInchesDigits.isEmpty : !heightCm.isEmpty,
                    unitOptions: ["ft", "cm"],
                    selectedUnit: heightUnit.rawValue,
                    onUnitChange: { newUnit in
                        convertHeight(to: HeightUnit(rawValue: newUnit) ?? .ftIn)
                    }
                )
                .onChange(of: heightFeetInchesDigits) { oldValue, newValue in
                    guard heightUnit == .ftIn else { return }
                    
                    let oldDigits = oldValue.filter { $0.isNumber }
                    let newDigits = newValue.filter { $0.isNumber }
                    
                    // Detect backspace on the closing quote " - delete last digit instead
                    if oldValue.hasSuffix("\"") && !newValue.hasSuffix("\"") && newDigits == oldDigits && !oldDigits.isEmpty {
                        let reducedDigits = String(oldDigits.dropLast())
                        if reducedDigits.isEmpty {
                            heightFeetInchesDigits = ""
                            return
                        }
                        let feet = String(reducedDigits.prefix(1))
                        let inches = String(reducedDigits.dropFirst().prefix(2))
                        if inches.isEmpty {
                            heightFeetInchesDigits = "\(feet)'"
                        } else {
                            heightFeetInchesDigits = "\(feet)'\(inches)\""
                        }
                        return
                    }
                    
                    // Detect backspace on the ' - delete the feet digit (clear field)
                    if oldValue.hasSuffix("'") && !newValue.hasSuffix("'") && newDigits == oldDigits && oldDigits.count == 1 {
                        heightFeetInchesDigits = ""
                        return
                    }
                    
                    // If empty, clear
                    guard !newDigits.isEmpty else {
                        if heightFeetInchesDigits != "" {
                            heightFeetInchesDigits = ""
                        }
                        return
                    }
                    
                    // Limit to 3 digits max (1 feet + 2 inches)
                    let limitedDigits = String(newDigits.prefix(3))
                    
                    // Format as X'XX"
                    let feet = String(limitedDigits.prefix(1))
                    let inches = String(limitedDigits.dropFirst().prefix(2))
                    
                    let formatted: String
                    if inches.isEmpty {
                        formatted = "\(feet)'"
                    } else {
                        formatted = "\(feet)'\(inches)\""
                    }
                    
                    // Only update if different to avoid infinite loop
                    if heightFeetInchesDigits != formatted {
                        heightFeetInchesDigits = formatted
                    }
                    
                    // Auto-advance to weight when height is complete
                    // 3 digits: always complete (e.g., 5'10")
                    // 2 digits: complete if inches is 2-9 (can't be 10, 11, etc.)
                    let inchValue = Int(inches) ?? 0
                    let isComplete = limitedDigits.count == 3 || 
                        (limitedDigits.count == 2 && !inches.isEmpty && inchValue >= 2)
                    if isComplete {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            focusedField = .weight
                        }
                    }
                }
                .onChange(of: heightCm) { oldValue, newValue in
                    guard heightUnit == .cm else { return }
                    
                    // Auto-advance to weight when cm height is complete (3 digits like 175)
                    let digits = newValue.filter { $0.isNumber }
                    if digits.count == 3 {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            focusedField = .weight
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // Weight with unit toggle
            VStack(alignment: .leading, spacing: 8) {
                Text("Weight")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                
                measurementInputField(
                    icon: "scalemass",
                    placeholder: weightUnit == .lbs ? "150" : "68",
                    text: $weight,
                    keyboardType: .numberPad,
                    field: .weight,
                    isValid: !weight.isEmpty,
                    unitOptions: ["lbs", "kg"],
                    selectedUnit: weightUnit.rawValue,
                    onUnitChange: { newUnit in
                        convertWeight(to: WeightUnit(rawValue: newUnit) ?? .lbs)
                    }
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
    }
    
    // Custom measurement input field with unit toggle
    @ViewBuilder
    private func measurementInputField(
        icon: String,
        placeholder: String,
        text: Binding<String>,
        keyboardType: UIKeyboardType,
        field: FocusedField,
        isValid: Bool,
        unitOptions: [String],
        selectedUnit: String,
        onUnitChange: @escaping (String) -> Void
    ) -> some View {
        let isFocused = focusedField == field
        
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(
                    LinearGradient(
                        colors: isValid ? [Color.blue, Color.cyan] : [Color.gray.opacity(0.6), Color.gray.opacity(0.5)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 26)
            
            TextField(placeholder, text: text)
                .keyboardType(keyboardType)
                .focused($focusedField, equals: field)
            
            // Unit toggle pill
            HStack(spacing: 0) {
                ForEach(unitOptions, id: \.self) { unit in
                    Button(action: {
                        if unit != selectedUnit {
                            onUnitChange(unit)
                        }
                    }) {
                        Text(unit)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(unit == selectedUnit ? .white : .secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(unit == selectedUnit ? Color.blue : Color.clear)
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .background(Capsule().fill(Color(.systemGray5)))
            
            // Checkmark when valid
            if isValid {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.blue)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .font(.system(size: 16, weight: .medium))
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(white: 0.12))
                
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        isFocused || isValid
                            ? LinearGradient(colors: [Color.blue, Color.cyan.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)
                            : LinearGradient(colors: [Color.gray.opacity(0.3), Color.gray.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: isFocused ? 2 : 1.5
                    )
            }
        )
        .animation(.easeInOut(duration: 0.2), value: isValid)
        .animation(.easeInOut(duration: 0.2), value: isFocused)
    }
    
    // Convert height between ft/in and cm
    private func convertHeight(to newUnit: HeightUnit) {
        let oldUnit = heightUnit
        guard newUnit != oldUnit else { return }
        
        if newUnit == .cm && oldUnit == .ftIn {
            // Convert ft/in to cm
            let digits = heightFeetInchesDigits.filter { $0.isNumber }
            guard !digits.isEmpty else {
                heightUnit = newUnit
                return
            }
            let feet = Int(String(digits.prefix(1))) ?? 0
            let inches = Int(String(digits.dropFirst().prefix(2))) ?? 0
            let totalInches = (feet * 12) + inches
            // Use rounding instead of truncation
            let cm = Int((Double(totalInches) * 2.54).rounded())
            heightCm = "\(cm)"
        } else if newUnit == .ftIn && oldUnit == .cm {
            // Convert cm to ft/in
            guard let cm = Int(heightCm), cm > 0 else {
                heightUnit = newUnit
                return
            }
            // Use rounding instead of truncation
            let totalInches = Int((Double(cm) / 2.54).rounded())
            let feet = totalInches / 12
            let inches = totalInches % 12
            if inches == 0 {
                heightFeetInchesDigits = "\(feet)'"
            } else {
                heightFeetInchesDigits = "\(feet)'\(inches)\""
            }
        }
        heightUnit = newUnit
    }
    
    // Convert weight between lbs and kg
    private func convertWeight(to newUnit: WeightUnit) {
        let oldUnit = weightUnit
        guard newUnit != oldUnit else { return }
        
        guard let currentWeight = Double(weight), currentWeight > 0 else {
            weightUnit = newUnit
            return
        }
        
        if newUnit == .kg && oldUnit == .lbs {
            // Convert lbs to kg
            let kg = currentWeight / 2.20462
            weight = "\(Int(kg.rounded()))"
        } else if newUnit == .lbs && oldUnit == .kg {
            // Convert kg to lbs
            let lbs = currentWeight * 2.20462
            weight = "\(Int(lbs.rounded()))"
        }
        weightUnit = newUnit
    }
    
    private var goalStepContent: some View {
        let goals: [(String, String, String, Color)] = [
            ("Build Muscle", "💪", "Gain size & strength", .blue),
            ("Lose Weight", "🔥", "Burn fat & get lean", .orange),
            ("Get Stronger", "🏋️", "Increase max lifts", .purple),
            ("Stay Active", "⚡", "General fitness", .green),
            ("Build Endurance", "🏃", "Improve stamina", .cyan),
            ("Improve Health", "❤️", "Overall wellness", .red)
        ]
        
        return ScrollView(showsIndicators: false) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(goals, id: \.0) { goal in
                    Button(action: {
                        if selectedGoals.contains(goal.0) {
                            selectedGoals.remove(goal.0)
                        } else {
                            selectedGoals.insert(goal.0)
                        }
                    }) {
                        VStack(spacing: 8) {
                            Text(goal.1)
                                .font(.system(size: 28))
                            Text(goal.0)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Text(goal.2)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(selectedGoals.contains(goal.0) ? goal.3.opacity(0.2) : Color(.systemGray6))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(selectedGoals.contains(goal.0) ? goal.3 : Color.clear, lineWidth: 2)
                        )
                    }
                    .foregroundColor(.primary)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
        }
    }
    
    private var experienceStepContent: some View {
        let levels = [
            ("Beginner", "🌱", "New to fitness or returning after a long break"),
            ("Intermediate", "💪", "1-3 years of consistent training"),
            ("Advanced", "🏆", "3+ years of dedicated training")
        ]
        
        return ScrollView(showsIndicators: false) {
            VStack(spacing: 12) {
                ForEach(levels, id: \.0) { level in
                    Button(action: { selectedExperience = level.0 }) {
                        HStack {
                            Text(level.1)
                                .font(.title)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(level.0)
                                    .font(.headline)
                                Text(level.2)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            if selectedExperience == level.0 {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.blue)
                            }
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(selectedExperience == level.0 ? Color.blue.opacity(0.1) : Color(.systemGray6))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(selectedExperience == level.0 ? Color.blue : Color.clear, lineWidth: 2)
                        )
                    }
                    .foregroundColor(.primary)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
        }
    }
    
    private var strengthStepContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 12) {
                ForEach(StrengthProfileRecommendationEngine.StrengthLevel.allCases, id: \.self) { level in
                    Button(action: { selectedStrengthLevel = level }) {
                        HStack(spacing: 12) {
                            Text(level.emoji)
                                .font(.title2)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(level.displayName)
                                    .font(.headline)
                                Text(level.description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            if selectedStrengthLevel == level {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.orange)
                            }
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(selectedStrengthLevel == level ? Color.orange.opacity(0.15) : Color(.systemGray6))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(selectedStrengthLevel == level ? Color.orange : Color.clear, lineWidth: 2)
                        )
                    }
                    .foregroundColor(.primary)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
        }
    }
    
    private var locationStepContent: some View {
        let locations: [(WorkoutEnvironmentService.WorkoutEnvironment, String, String, Color)] = [
            (.gym, "🏋️", "Full Gym", .blue),
            (.home, "🏠", "Home", .green),
            (.outdoor, "🌳", "Outdoor", .orange),
            (.hybrid, "🔄", "Hybrid", .purple)
        ]
        
        return ScrollView(showsIndicators: false) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(locations, id: \.0) { loc in
                    Button(action: { 
                        selectionFeedback.selectionChanged()
                        selectedWorkoutLocation = loc.0 
                    }) {
                        VStack(spacing: 8) {
                            Text(loc.1)
                                .font(.system(size: 32))
                            Text(loc.2)
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(selectedWorkoutLocation == loc.0 ? loc.3.opacity(0.2) : Color(.systemGray6))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(selectedWorkoutLocation == loc.0 ? loc.3 : Color.clear, lineWidth: 2)
                        )
                    }
                    .foregroundColor(.primary)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
        }
    }
    
    private var equipmentStepContent: some View {
        EquipmentTilesView(
            selectedEquipment: $selectedEquipment,
            selectedLocation: $selectedEquipmentLocation
        )
    }
    
    @ViewBuilder
    private func limitationRowWithDropdown(for area: AffectedArea) -> some View {
        let isSelected = selectedLimitations.contains(area)
        
        VStack(alignment: .leading, spacing: 8) {
            // Main selection button
            Button(action: {
                if isSelected {
                    selectedLimitations.remove(area)
                    limitationAccommodations.removeValue(forKey: area)
                } else {
                    selectedLimitations.insert(area)
                    // Default to "Be Careful"
                    limitationAccommodations[area] = .beCareful
                }
            }) {
                HStack {
                    Image(systemName: area.icon)
                        .font(.title2)
                        .foregroundColor(area.color)
                        .frame(width: 30)
                    Text(area.rawValue)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Spacer()
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(isSelected ? .blue : .gray.opacity(0.3))
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isSelected ? Color.blue.opacity(0.1) : Color(.systemGray6))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 1.5)
                )
            }
            .foregroundColor(.primary)
            
            // Dropdown menu when selected
            if isSelected {
                Menu {
                    ForEach(AccommodationLevel.allCases, id: \.self) { level in
                        Button(action: {
                            limitationAccommodations[area] = level
                        }) {
                            Label(level.displayName, systemImage: level.icon)
                        }
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: limitationAccommodations[area]?.icon ?? AccommodationLevel.beCareful.icon)
                            .font(.system(size: 16))
                            .foregroundColor(limitationAccommodations[area]?.color ?? AccommodationLevel.beCareful.color)
                            .frame(width: 24)
                        Text(limitationAccommodations[area]?.displayName ?? AccommodationLevel.beCareful.displayName)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.black)
                    )
                }
                .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
                .animation(.easeInOut(duration: 0.2), value: isSelected)
            }
        }
    }
    
    private var scheduleStepContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                Text("How many days per week can you workout?")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                HStack(spacing: 12) {
                    ForEach(2...6, id: \.self) { day in
                        Button(action: { selectedDays = day }) {
                            Text("\(day)")
                                .font(.title2)
                                .fontWeight(.bold)
                                .frame(width: 50, height: 50)
                                .background(
                                    Circle()
                                        .fill(selectedDays == day ? Color.blue : Color(.systemGray6))
                                )
                                .foregroundColor(selectedDays == day ? .white : .primary)
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 32)
        }
    }
    
    private func confirmationRowSimple(title: String, value: String, editStep: OnboardingStep? = nil) -> some View {
        Button(action: {
            if let step = editStep {
                isEditingFromConfirmation = true
                navigateTo(step)
            }
        }) {
            HStack {
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                Text(value)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                if editStep != nil {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                        .padding(.leading, 8)
                }
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(.systemGray6)))
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func formatHeightDisplay() -> String {
        let digits = heightFeetInchesDigits.filter { $0.isNumber }
        guard !digits.isEmpty else { return "-" }
        let feet = String(digits.prefix(1))
        let inchesRaw = String(digits.dropFirst().prefix(2))
        // Pad inches to 2 digits (5'8" → 5'08")
        let inches = inchesRaw.count == 1 ? "0\(inchesRaw)" : inchesRaw
        return "\(feet)'\(inches)\""
    }
    
    private func handleConfirmation() {
        // Use existing auth/account creation logic from the confirmation step
        Task {
            await completeOnboardingFlow()
        }
    }
    
    private func completeOnboardingFlow() async {
        // Create Supabase account first, then complete onboarding
        await MainActor.run {
            createAccountAndComplete()
        }
    }
    
    // MARK: - Background
    private var backgroundGradient: some View {
        AdaptiveGradient.universal(for: colorScheme)
        .ignoresSafeArea()
    }
    
    // MARK: - Progress Indicator (UX Audit Fix #2)
    private var progressIndicator: some View {
        VStack(spacing: 6) {
            // Progress bar
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
                                colors: [.blue, .blue, .cyan.opacity(0.7)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geometry.size.width * progressValue, height: 6)
                        .animation(.easeInOut(duration: 0.3), value: progressValue)
                }
            }
            .frame(height: 6)
        }
        .padding(.horizontal, 24)
    }
    
    
    // MARK: - Auth Step
    private var authStep: some View {
        let keyboardUp = keyboardObserver.keyboardHeight > 0
        let showingConfirmPassword = isSignUp && isPasswordValid
        let keyboardHeight = keyboardObserver.keyboardHeight
        
        return ZStack(alignment: .bottom) {
            // Content area
            GeometryReader { geometry in
                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 0) {
                            // Top spacing - account for safe area when keyboard is up
                            if keyboardUp {
                                Spacer()
                                    .frame(height: 60) // Safe area + some padding
                            } else {
                                Spacer()
                                    .frame(height: max(20, (geometry.size.height - 620) / 2.5))
                            }
                            
                            authFormContent
                            
                            // Bottom padding for keyboard
                            Spacer()
                                .frame(height: keyboardUp ? (keyboardHeight + 80) : 60)
                                .id("bottomSpacer")
                        }
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: showingConfirmPassword) { _, isShowing in
                        if isShowing {
                            // Multiple scroll attempts for reliability
                            for delay in [0.1, 0.3, 0.5] {
                                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                                    withAnimation(.easeOut(duration: 0.3)) {
                                        proxy.scrollTo("bottomSpacer", anchor: .bottom)
                                    }
                                }
                            }
                        }
                    }
                    .onChange(of: focusedField) { _, newFocus in
                        if newFocus == .confirmPassword {
                            // Multiple scroll attempts for reliability
                            for delay in [0.05, 0.2, 0.4] {
                                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                                    withAnimation(.easeOut(duration: 0.25)) {
                                        proxy.scrollTo("bottomSpacer", anchor: .bottom)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            
            // Floating Continue Button - only show when keyboard is open
            if keyboardUp {
                VStack(spacing: 0) {
                    // Continue/Sign In button - full width, hollow when incomplete
                    Button(action: {
                        if isEditingFromConfirmation {
                            returnToConfirmation()
                        } else {
                            handleAuth()
                        }
                    }) {
                        HStack(spacing: 8) {
                            if supabaseManager.isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: isAuthFormValid ? .white : .gray))
                                    .scaleEffect(0.8)
                            } else {
                                Text(isEditingFromConfirmation ? "Save" : (isSignUp ? "Continue" : "Sign In"))
                                    .font(.system(size: 16, weight: .bold))
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 14, weight: .bold))
                            }
                        }
                        .foregroundColor(isAuthFormValid && !supabaseManager.isLoading ? .white : .gray)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                    .background(
                        Group {
                            if isAuthFormValid && !supabaseManager.isLoading {
                                // Illuminated hollow state - glowing outline
                                Capsule()
                                    .stroke(
                                        LinearGradient(colors: [.blue, .cyan.opacity(0.8)], startPoint: .leading, endPoint: .trailing),
                                        lineWidth: 2.5
                                    )
                                    .shadow(color: Color.blue.opacity(0.5), radius: 8, x: 0, y: 0)
                            } else {
                                // Hollow outline state - dim
                                Capsule()
                                    .stroke(
                                        LinearGradient(colors: [.gray.opacity(0.4), .gray.opacity(0.3)], startPoint: .leading, endPoint: .trailing),
                                        lineWidth: 2
                                    )
                            }
                        }
                    )
                    }
                    .disabled(supabaseManager.isLoading || !isAuthFormValid)
                    .animation(.easeInOut(duration: 0.3), value: isAuthFormValid)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, keyboardObserver.keyboardHeight + 10)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                .animation(.easeOut(duration: 0.25), value: keyboardObserver.keyboardHeight)
            }
        }
    }
    
    // Auth toggle - unified segmented control style
    private var authToggleButtons: some View {
        HStack(spacing: 8) {
            // Sign Up Button
            Button(action: { 
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { isSignUp = true }
                clearAuthMessages()
            }) {
                Text("Sign Up")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(isSignUp ? .white : .secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(
                        Group {
                            if isSignUp {
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [Color.blue, Color.blue, Color.cyan.opacity(0.8)],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .shadow(color: Color.blue.opacity(0.25), radius: 6, x: 0, y: 3)
                            }
                        }
                    )
            }
            
            // Sign In Button
            Button(action: { 
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { isSignUp = false }
                clearAuthMessages()
            }) {
                Text("Sign In")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(!isSignUp ? .white : .secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(
                        Group {
                            if !isSignUp {
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [Color.blue, Color.blue, Color.cyan.opacity(0.8)],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .shadow(color: Color.blue.opacity(0.25), radius: 6, x: 0, y: 3)
                            }
                        }
                    )
            }
        }
        .padding(5)
        .background(
            Capsule()
                .fill(Color(.systemGray6))
        )
        .padding(.horizontal, 40)
    }
    
    // Auth form content extracted for reuse
    private var authFormContent: some View {
        let keyboardUp = keyboardObserver.keyboardHeight > 0
        
        return VStack(spacing: 0) {
            // Fit33 Logo - Large and centered (hides when keyboard up)
            if !keyboardUp {
                Image("fit33-logo")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 240, height: 95)
                    .clipped()
                    .padding(.bottom, 20)
            }
            
            // Header - compact version when keyboard up, full version when not
            VStack(spacing: keyboardUp ? 4 : 6) {
                Text(isSignUp ? "Create Account" : "Welcome Back")
                    .font(.system(size: keyboardUp ? 22 : 26, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                
                if !keyboardUp {
                    Text(isSignUp ? "Start your fitness journey" : "Continue your journey")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
                .frame(height: keyboardUp ? 12 : 20)
                
                // Auth Toggle - always visible at top for easy switching
                authToggleButtons
                
                Spacer()
                    .frame(height: keyboardUp ? 12 : 20)
                
                // Form fields - slightly compact spacing when keyboard is up
                VStack(spacing: keyboardUp ? 10 : 14) {
                    // Name field (only for sign up)
                    if isSignUp {
                        OnboardingTextField(
                            icon: "person.fill",
                            placeholder: "Name",
                            text: $name,
                            focusedField: $focusedField,
                            fieldValue: .name,
                            isValid: !name.isEmpty
                        )
                    }
                    
                    OnboardingTextField(
                        icon: "envelope.fill",
                        placeholder: "Email",
                        text: $email,
                        keyboardType: .emailAddress,
                        focusedField: $focusedField,
                        fieldValue: .email,
                        isValid: !email.isEmpty && email.contains("@")
                    )
                    
                    // Password field with show/hide toggle
                    PasswordTextField(
                        placeholder: "Password",
                        text: $password,
                        isVisible: $showPassword,
                        focusedField: $focusedField,
                        fieldValue: .password,
                        isValid: isPasswordValid
                    )
                    
                    // Password requirements (only for sign up, show when focused, hide once all met)
                    if isSignUp && focusedField == .password && !isPasswordValid {
                        PasswordRequirementsView(
                            hasMinLength: hasMinLength,
                            hasUppercase: hasUppercase,
                            hasLowercase: hasLowercase,
                            hasNumber: hasNumber,
                            hasSpecialChar: hasSpecialChar
                        )
                    }
                    
                    // Confirm password (only show after password is valid)
                    if isSignUp && isPasswordValid {
                        PasswordTextField(
                            placeholder: "Confirm Password",
                            text: $confirmPassword,
                            isVisible: $showConfirmPassword,
                            focusedField: $focusedField,
                            fieldValue: .confirmPassword,
                            showMatchIndicator: true,
                            passwordsMatch: passwordsMatch,
                            isValid: passwordsMatch && !confirmPassword.isEmpty
                        )
                        .id("confirmPassword")
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    
                    // Terms and Services checkbox (only for sign up, show after passwords match)
                    if isSignUp && isPasswordValid && passwordsMatch {
                        HStack(spacing: 10) {
                            Button(action: { acceptedTerms.toggle() }) {
                                ZStack {
                                    Circle()
                                        .fill(acceptedTerms ? Color.blue : Color.clear)
                                        .frame(width: 24, height: 24)
                                    
                                    Circle()
                                        .stroke(acceptedTerms ? Color.blue : Color.gray.opacity(0.4), lineWidth: 2)
                                        .frame(width: 24, height: 24)
                                    
                                    if acceptedTerms {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundColor(.white)
                                    }
                                }
                            }
                            
                            HStack(spacing: 4) {
                                Text("I accept the")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                
                                Button(action: { showTermsSheet = true }) {
                                    Text("Terms & Conditions")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundColor(.blue)
                                }
                            }
                            
                            Spacer()
                        }
                        .padding(.top, 12)
                        .padding(.horizontal, 4)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    
                    // Email already exists message
                    if emailAlreadyExists {
                        VStack(spacing: 8) {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                Text("This email is already registered")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.primary)
                            }
                            
                            HStack(spacing: 16) {
                                Button(action: {
                                    emailAlreadyExists = false
                                    isSignUp = false
                                }) {
                                    Text("Sign In Instead")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 8)
                                        .background(Color.blue)
                                        .cornerRadius(8)
                                }
                                
            Button(action: {
                                    sendPasswordReset()
                                }) {
                                    Text("Reset Password")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.blue)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 8)
                                        .background(Color.blue.opacity(0.1))
                                        .cornerRadius(8)
                                }
                            }
                        }
                        .padding(12)
                .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.orange.opacity(0.1))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                                )
                        )
                    }
                    
                    // Password reset sent message
                    if passwordResetSent {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Password reset email sent! Check your inbox.")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.green.opacity(0.1))
                        )
                    }
                    
                    if showError && !emailAlreadyExists {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                    }
                    
                    // Auth Provider Hint (when user tries email login but has Apple/Google account)
                    if showAuthProviderHint {
                        VStack(spacing: 12) {
                            HStack(spacing: 8) {
                                Image(systemName: detectedAuthProvider.contains("apple") ? "apple.logo" : "person.badge.key.fill")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(.blue)
                                
                                Text(authProviderHintMessage)
                                    .font(.subheadline)
                                    .foregroundColor(.primary)
                                    .multilineTextAlignment(.leading)
                            }
                            .padding(16)
                            .frame(maxWidth: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.blue.opacity(0.1))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                                    )
                            )
                            
                            // Quick action button to use the correct provider
                            if detectedAuthProvider.contains("apple") {
                                Button(action: {
                                    showAuthProviderHint = false
                                    handleAppleSignIn()
                                }) {
                                    HStack {
                                        Image(systemName: "apple.logo")
                                        Text("Continue with Apple")
                                    }
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                                    .background(
                                        Capsule()
                                            .fill(Color.black)
                                    )
                                }
                            }
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                        .animation(.easeInOut(duration: 0.3), value: showAuthProviderHint)
                    }
                    
                    // Forgot Password (only for login)
                    if !isSignUp {
                        Button(action: {
                            sendPasswordReset()
                        }) {
                            Text("Forgot Password?")
                                .font(.subheadline)
                                .foregroundColor(.blue)
                        }
                        .disabled(email.isEmpty || !email.contains("@"))
                        .opacity(email.isEmpty || !email.contains("@") ? 0.5 : 1.0)
                        .padding(.top, 4)
                    }
                    
                    // MARK: - Social Login Section (hidden when keyboard is up)
                    if keyboardObserver.keyboardHeight == 0 {
                        VStack(spacing: 16) {
                            SocialLoginDivider()
                                .padding(.top, 8)
                            
                            // Apple Sign-In Button
                            SignInWithAppleButton {
                                handleAppleSignIn()
                            }
                        }
                        .padding(.top, 20)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
            .padding(.horizontal, 28)
            .animation(.easeInOut(duration: 0.2), value: keyboardObserver.keyboardHeight)
            .onChange(of: isPasswordValid) { _, isValid in
                // Auto-focus confirm password when all requirements are met
                if isValid && isSignUp && focusedField == .password {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        withAnimation(.easeOut(duration: 0.25)) {
                            focusedField = .confirmPassword
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Basics Step (Birthday + Gender)
    // Parse birthday from MM/DD/YYYY format
    private var birthdayDate: Date? {
        let parts = birthday.split(separator: "/")
        guard parts.count == 3,
              let month = Int(parts[0]),
              let day = Int(parts[1]),
              let year = Int(parts[2]),
              month >= 1 && month <= 12,
              day >= 1 && day <= 31,
              year >= 1900 && year <= Calendar.current.component(.year, from: Date())
        else { return nil }
        
        var components = DateComponents()
        components.month = month
        components.day = day
        components.year = year
        return Calendar.current.date(from: components)
    }
    
    private var isBirthdayValid: Bool {
        birthdayDate != nil
    }
    
    private var calculatedAge: Int {
        guard let date = birthdayDate else { return 0 }
        return Calendar.current.dateComponents([.year], from: date, to: Date()).year ?? 0
    }
    
    private var basicsStep: some View {
        OnboardingPageTemplate(
            title: "Tell us about yourself",
            subtitle: "A few quick details",
            helpText: "Birthday helps us recommend appropriate intensity. Gender is optional.",
            canContinue: isBirthdayValid && calculatedAge >= 13 && calculatedAge <= 120,
            onBack: { isEditingFromConfirmation ? navigateTo(.confirmation) : navigateTo(.auth) },
            onContinue: { 
                impactFeedback.impactOccurred()
                isEditingFromConfirmation ? returnToConfirmation() : navigateTo(.body) 
            },
            showBackButton: !isEditingFromConfirmation,
            currentStep: 1,
            totalSteps: 9,
            keyboardObserver: keyboardObserver
        ) {
            VStack(spacing: 32) {
                // Birthday - simple text input
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Birthday")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        // Show calculated age (UX improvement)
                        if isBirthdayValid && calculatedAge >= 13 && calculatedAge <= 120 {
                            Text("\(calculatedAge) years old ✓")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.green)
                        }
                    }
                    
                    OnboardingTextField(
                        icon: "calendar",
                        placeholder: "11/16/1994",
                        text: $birthday,
                        keyboardType: .numberPad,
                        focusedField: $focusedField,
                        fieldValue: .birthday,
                        isValid: isBirthdayValid && calculatedAge >= 13 && calculatedAge <= 120
                    )
                    .onChange(of: birthday) { _, newValue in
                        let formatted = formatBirthday(newValue)
                        if formatted != newValue {
                            birthday = formatted
                        }
                    }
                    
                    // Validation error (UX Audit Fix #1)
                    if let error = birthdayValidationError {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .font(.caption)
                            Text(error)
                                .font(.caption)
                        }
                        .foregroundColor(.orange)
                        .padding(.top, 4)
                    }
                }
                
                // Gender
                VStack(alignment: .leading, spacing: 12) {
                    Text("Gender (optional)")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 12) {
                        ForEach(["Male", "Female", "Other"], id: \.self) { gender in
                            GenderButton(
                                title: gender,
                                isSelected: selectedGender == gender,
                                action: { 
                                    selectionFeedback.selectionChanged() // Haptic feedback (Fix #6)
                                    // Toggle selection - tap again to unselect
                                    if selectedGender == gender {
                                        selectedGender = nil
                                    } else {
                                        selectedGender = gender
                                    }
                                    // (Fix #4) Allow keyboard to dismiss naturally - don't force it to stay
                                    // User can tap birthday field again if they want keyboard back
                                }
                            )
                            .accessibilityLabel("\(gender) gender option") // Accessibility (Fix #8)
                        }
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 20)
        }
    }
    
    // MARK: - Body Step (Height + Weight)
    // Parse height from digits (format: "510" = 5'10", "61" = 6'1", "600" = 6'0")
    private var parsedHeightFeetInches: (feet: Int, inches: Int)? {
        let digits = heightDigits
        guard !digits.isEmpty else { return nil }
        
        // First digit is always feet
        let feet = Int(String(digits.prefix(1))) ?? 0
        
        // Remaining digits are inches
        let inchDigits = String(digits.dropFirst())
        let inches: Int
        
        if inchDigits.isEmpty {
            inches = 0
        } else if inchDigits.count == 1 {
            // Single digit: could be 1-9
            inches = Int(inchDigits) ?? 0
        } else {
            // Two digits: 00-11 (we'll validate below)
            inches = Int(inchDigits.prefix(2)) ?? 0
        }
        
        if feet >= 3 && feet <= 8 && inches >= 0 && inches <= 11 {
            return (feet, inches)
        }
        return nil
    }
    
    private var isHeightValid: Bool {
        if heightUnit == .cm {
            return !heightCm.isEmpty && Int(heightCm) != nil
        } else {
            return parsedHeightFeetInches != nil
        }
    }
    
    private var isWeightValid: Bool {
        return !weight.isEmpty && Double(weight) != nil
    }
    
    // Convert height to cm for storage
    private var heightInCm: Int {
        if heightUnit == .cm {
            return Int(heightCm) ?? 0
        } else if let parsed = parsedHeightFeetInches {
            let totalInches = (parsed.feet * 12) + parsed.inches
            return Int(Double(totalInches) * 2.54)
        }
        return 0
    }
    
    private var bodyStep: some View {
        OnboardingPageTemplate(
            title: "Your measurements",
            subtitle: "Let's crunch some numbers",
            helpText: "Calculate your BMR and personalized targets. Adjust later as needed.",
            canContinue: isHeightValid && isWeightValid,
            onBack: { isEditingFromConfirmation ? navigateTo(.confirmation) : navigateTo(.basics) },
            onContinue: { 
                impactFeedback.impactOccurred()
                isEditingFromConfirmation ? returnToConfirmation() : navigateTo(.goal) 
            },
            showBackButton: !isEditingFromConfirmation,
            currentStep: 2,
            totalSteps: 9,
            keyboardObserver: keyboardObserver
        ) {
            VStack(spacing: 28) {
                // Height Field with toggle INSIDE
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Height")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        // Height preview (UX Audit Fix #3)
                        if let preview = heightPreviewText {
                            Text("→ \(preview) ✓")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                    }
                    
                    // Text field with toggle inside
                    HStack(spacing: 12) {
                        Image(systemName: "ruler")
                            .font(.system(size: 18))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: isHeightValid ? [Color.blue, Color.purple] : [Color.gray.opacity(0.5), Color.gray.opacity(0.4)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 24)
                        
                        // Input + unit tightly together
                        HStack(spacing: 2) {
                            if heightUnit == .ftIn {
                                HeightInputField(
                                    heightDigits: $heightFeetInchesDigits,
                                    focusedField: $focusedField
                                )
                                .onChange(of: heightFeetInchesDigits) { _, newValue in
                                    // Auto-advance to weight when height is complete (faster timing - Fix #8)
                                    let digits = newValue.filter { $0.isNumber }
                                    if digits.count >= 2 {
                                        let inchDigit = digits.dropFirst().first
                                        if let inch = inchDigit, inch >= "2" && inch <= "9" {
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                                focusedField = .weight
                                            }
                                        } else if digits.count >= 3 {
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                                focusedField = .weight
                                            }
                                        }
                                    }
                                }
                            } else {
                                TextField("175", text: $heightCm)
                                    .keyboardType(.numberPad)
                                    .focused($focusedField, equals: .height)
                                    .fixedSize()
                                    .onChange(of: heightCm) { _, newValue in
                                        if newValue.count >= 3 {
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                                focusedField = .weight
                                            }
                                        }
                                    }
                                
                                Text("cm")
                                    .foregroundColor(.secondary)
                                    .font(.system(size: 15, weight: .medium))
                            }
                        }
                        
                        Spacer()
                        
                        // Unit toggle at end
                        InlineUnitToggle(
                            options: HeightUnit.allCases.map { $0.rawValue },
                            selected: heightUnit.rawValue,
                            onSelect: { unit in
                                let newUnit = HeightUnit(rawValue: unit) ?? .ftIn
                                if newUnit == .cm && heightUnit == .ftIn && isHeightValid {
                                    // Use round() to avoid truncation errors
                                    let totalInches = Double(parsedHeightFeetInches?.feet ?? 0) * 12 + Double(parsedHeightFeetInches?.inches ?? 0)
                                    heightCm = "\(Int(round(totalInches * 2.54)))"
                                } else if newUnit == .ftIn && heightUnit == .cm, let cm = Int(heightCm) {
                                    // Use round() to avoid truncation errors
                                    let totalInches = Int(round(Double(cm) / 2.54))
                                    let feet = totalInches / 12
                                    let inches = totalInches % 12
                                    heightFeetInchesDigits = "\(feet)\(inches < 10 ? "0" : "")\(inches)"
                                }
                                heightUnit = newUnit
                                // Re-focus height field to keep keyboard up (same as weight toggle)
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                    focusedField = .height
                                }
                            }
                        )
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color(.systemBackground))
                            .shadow(color: Color.black.opacity(0.08), radius: 2, x: 0, y: 1)
                            .shadow(color: isHeightValid ? Color.blue.opacity(0.25) : Color.black.opacity(0.05), radius: isHeightValid ? 16 : 8, x: 0, y: isHeightValid ? 4 : 2)
                            .shadow(color: isHeightValid ? Color.purple.opacity(0.15) : .clear, radius: 24, x: 0, y: 8)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(
                                LinearGradient(
                                    colors: isHeightValid 
                                        ? [Color.blue.opacity(0.6), Color.purple.opacity(0.5)]
                                        : [Color.gray.opacity(0.2), Color.gray.opacity(0.15)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: isHeightValid ? 1.5 : 1
                            )
                    )
                    .animation(.easeInOut(duration: 0.3), value: isHeightValid)
                    
                    // Height validation error (UX Audit Fix #1)
                    if let error = heightValidationError {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .font(.caption)
                            Text(error)
                                .font(.caption)
                        }
                        .foregroundColor(.orange)
                        .padding(.top, 4)
                    }
                }
                
                // Weight Field with toggle INSIDE
                VStack(alignment: .leading, spacing: 10) {
                    Text("Weight")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                    
                    // Text field with toggle inside
                    HStack(spacing: 12) {
                        Image(systemName: "scalemass")
                            .font(.system(size: 18))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: isWeightValid ? [Color.blue, Color.purple] : [Color.gray.opacity(0.5), Color.gray.opacity(0.4)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 24)
                        
                        // Input + unit tightly together
                        HStack(spacing: 2) {
                            TextField(weightUnit == .lbs ? "160" : "73", text: $weight)
                                .keyboardType(.decimalPad)
                                .focused($focusedField, equals: .weight)
                                .fixedSize()
                            
                            Text(weightUnit == .lbs ? "lbs" : "kg")
                                .foregroundColor(.secondary)
                                .font(.system(size: 15, weight: .medium))
                        }
                        
                        Spacer()
                        
                        // Unit toggle at end
                        InlineUnitToggle(
                            options: WeightUnit.allCases.map { $0.rawValue },
                            selected: weightUnit.rawValue,
                            onSelect: { unit in
                                let oldUnit = weightUnit
                                weightUnit = WeightUnit(rawValue: unit) ?? .lbs
                                if let currentWeight = Double(weight) {
                                    if oldUnit == .kg && weightUnit == .lbs {
                                        // Use round() for accurate conversion
                                        weight = String(Int(round(currentWeight * 2.20462)))
                                    } else if oldUnit == .lbs && weightUnit == .kg {
                                        // Use round() for accurate conversion
                                        weight = String(Int(round(currentWeight / 2.20462)))
                                    }
                                }
                                // Re-focus weight field to keep keyboard up
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                    focusedField = .weight
                                }
                            }
                        )
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color(.systemBackground))
                            .shadow(color: Color.black.opacity(0.08), radius: 2, x: 0, y: 1)
                            .shadow(color: isWeightValid ? Color.blue.opacity(0.25) : Color.black.opacity(0.05), radius: isWeightValid ? 16 : 8, x: 0, y: isWeightValid ? 4 : 2)
                            .shadow(color: isWeightValid ? Color.purple.opacity(0.15) : .clear, radius: 24, x: 0, y: 8)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(
                                LinearGradient(
                                    colors: isWeightValid 
                                        ? [Color.blue.opacity(0.6), Color.purple.opacity(0.5)]
                                        : [Color.gray.opacity(0.2), Color.gray.opacity(0.15)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: isWeightValid ? 1.5 : 1
                            )
                    )
                    .animation(.easeInOut(duration: 0.3), value: isWeightValid)
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 20)
        }
    }
    
    // MARK: - Goal Step
    private var goalStep: some View {
        let goals: [(String, String, String, Color)] = [
            ("Build Muscle", "💪", "Gain size & strength", .blue),
            ("Get Lean", "🔥", "Burn fat, stay toned", .orange),
            ("Endurance", "🏃", "Better stamina", .green),
            ("General Fitness", "🌟", "Stay healthy", .purple)
        ]
        
        return OnboardingStepContainer(
            canGoBack: !isEditingFromConfirmation,
            onBack: { isEditingFromConfirmation ? navigateTo(.confirmation) : navigateTo(.body) },
            onContinue: { isEditingFromConfirmation ? returnToConfirmation() : navigateTo(.experience) },
            continueEnabled: !selectedGoals.isEmpty,
            continueLabel: isEditingFromConfirmation ? "Save" : "Continue",
            currentStep: 3,
            totalSteps: 9,
            question: "What's your goal?",
            subtitle: "Select one or more"
        ) {
            VStack(spacing: 24) {
                // Goal cards - 2x2 grid with new styling
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                    ForEach(goals, id: \.0) { goal in
                        OnboardingLargeCard(
                            title: goal.0,
                            emoji: goal.1,
                            subtitle: goal.2,
                            color: goal.3,
                            isSelected: selectedGoals.contains(goal.0),
                            onTap: {
                                selectionFeedback.selectionChanged()
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    if selectedGoals.contains(goal.0) {
                                        selectedGoals.remove(goal.0)
                                    } else {
                                        selectedGoals.insert(goal.0)
                                    }
                                }
                            }
                        )
                        .accessibilityLabel("\(goal.0). \(goal.2)")
                    }
                }
                .padding(.horizontal, 20)
                
                // Help text
                Text("This helps us prioritize exercises and rep ranges for you")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
    }
    
    
    // MARK: - Experience Step
    private var experienceStep: some View {
        let levels: [(String, String, String, Color)] = [
            ("Beginner", "🌱", "New to working out", .green),
            ("Intermediate", "🌿", "Some gym experience", .blue),
            ("Advanced", "🌳", "Years of training", .purple)
        ]
        
        return OnboardingStepContainer(
            canGoBack: !isEditingFromConfirmation,
            onBack: { isEditingFromConfirmation ? navigateTo(.confirmation) : navigateTo(.goal) },
            onContinue: { isEditingFromConfirmation ? returnToConfirmation() : navigateTo(.strengthAssessment) },
            continueEnabled: !selectedExperience.isEmpty,
            continueLabel: isEditingFromConfirmation ? "Save" : "Continue",
            currentStep: 4,
            totalSteps: 9,
            question: "Experience level?",
            subtitle: "Be honest — no judgment here!"
        ) {
            VStack(spacing: 12) {
                ForEach(levels, id: \.0) { level in
                    OnboardingWideCard(
                        title: level.0,
                        subtitle: level.2,
                        icon: level.0 == "Beginner" ? "leaf.fill" : level.0 == "Intermediate" ? "flame.fill" : "bolt.fill",
                        color: level.3,
                        isSelected: selectedExperience == level.0,
                        onTap: {
                            selectionFeedback.selectionChanged()
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                selectedExperience = level.0
                            }
                        }
                    )
                }
            }
            .padding(.horizontal, 20)
        }
    }
    
    // MARK: - Strength Assessment Step
    private var strengthAssessmentStep: some View {
        let strengthLevels: [(StrengthProfileRecommendationEngine.StrengthLevel, String, String, String, Color)] = [
            (.veryLight, "📱", "Light Items", "Books, phones (~2 lbs)", .gray),
            (.light, "🥛", "Gallon of Milk", "Lift easily (~8 lbs)", .green),
            (.moderate, "🎳", "Bowling Ball", "Comfortable (~14 lbs)", .blue),
            (.strong, "🧳", "Heavy Suitcase", "Handle heavy (~40 lbs)", .orange),
            (.veryStrong, "🏋️", "Heavy Weights", "Gym weights (~60+ lbs)", .red)
        ]
        
        return OnboardingStepContainer(
            canGoBack: !isEditingFromConfirmation,
            onBack: { isEditingFromConfirmation ? navigateTo(.confirmation) : navigateTo(.experience) },
            onContinue: { isEditingFromConfirmation ? returnToConfirmation() : navigateTo(.workoutLocation) },
            continueEnabled: selectedStrengthLevel != nil,
            continueLabel: isEditingFromConfirmation ? "Save" : "Continue",
            currentStep: 5,
            totalSteps: 9,
            question: "How heavy can you lift?",
            subtitle: "Pick the heaviest everyday item"
        ) {
            VStack(spacing: 12) {
                ForEach(strengthLevels, id: \.0.rawValue) { level in
                    OnboardingWideCard(
                        title: level.2,
                        subtitle: level.3,
                        icon: level.0 == .veryLight ? "iphone" : level.0 == .light ? "drop.fill" : level.0 == .moderate ? "circle.fill" : level.0 == .strong ? "bag.fill" : "dumbbell.fill",
                        color: level.4,
                        isSelected: selectedStrengthLevel == level.0,
                        onTap: {
                            selectionFeedback.selectionChanged()
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                selectedStrengthLevel = level.0
                            }
                        }
                    )
                    .accessibilityLabel("\(level.2). \(level.3)")
                }
                
                // Info tip
                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 14))
                        .foregroundColor(.orange)
                    
                    Text("Helps suggest starting weights for workouts")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 8)
            }
            .padding(.horizontal, 20)
        }
    }
    
    // MARK: - Workout Location Step
    private var workoutLocationStep: some View {
        let locations: [(WorkoutEnvironmentService.WorkoutEnvironment, String, String, String, Color)] = [
            (.gym, "🏋️", "Gym", "Full gym equipment access", .purple),
            (.home, "🏠", "Home", "Bodyweight & home equipment", .green),
            (.outdoor, "🌳", "Outdoor", "Parks & outdoor spaces", .teal),
            (.hybrid, "🔄", "Hybrid", "Mix of locations", .orange)
        ]
        
        return OnboardingStepContainer(
            canGoBack: !isEditingFromConfirmation,
            onBack: { isEditingFromConfirmation ? navigateTo(.confirmation) : navigateTo(.strengthAssessment) },
            onContinue: {
                updateSuggestedEquipment()
                isEditingFromConfirmation ? returnToConfirmation() : navigateTo(.equipment)
            },
            continueEnabled: selectedWorkoutLocation != nil,
            continueLabel: isEditingFromConfirmation ? "Save" : "Continue",
            currentStep: 6,
            totalSteps: 9,
            question: "Where do you workout?",
            subtitle: "We'll recommend the right exercises"
        ) {
            VStack(spacing: 12) {
                // Location grid - 2x2
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                    ForEach(locations, id: \.0.rawValue) { item in
                        OnboardingLargeCard(
                            title: item.2,
                            emoji: item.1,
                            subtitle: item.3,
                            color: item.4,
                            isSelected: selectedWorkoutLocation == item.0,
                            onTap: {
                                selectionFeedback.selectionChanged()
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    selectedWorkoutLocation = item.0
                                }
                            }
                        )
                        .accessibilityLabel("\(item.0.displayName). \(item.3)")
                    }
                }
                
                // Info text
                if selectedWorkoutLocation != nil {
                    Text(workoutLocationInfoText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                }
            }
            .padding(.horizontal, 20)
        }
    }
    
    private var workoutLocationInfoText: String {
        switch selectedWorkoutLocation {
        case .gym:
            return "We'll prioritize exercises using machines, racks, cables and gym equipment"
        case .home:
            return "We'll focus on dumbbells, bands, bodyweight and minimal equipment exercises"
        case .outdoor:
            return "We'll suggest bodyweight, pull-up bar, and outdoor-friendly exercises"
        case .hybrid:
            return "We'll mix gym and home exercises based on your equipment"
        }
    }
    
    private func mapWorkoutLocationToEquipmentLocation(_ location: WorkoutEnvironmentService.WorkoutEnvironment) -> EquipmentLocation {
        switch location {
        case .gym: return .gym
        case .home: return .home
        case .outdoor: return .outdoor
        case .hybrid: return .hybrid
        }
    }
    
    private func updateSuggestedEquipment() {
        // If equipment is empty, suggest based on location (smart defaults)
        if selectedEquipment.isEmpty {
            switch selectedWorkoutLocation {
            case .gym:
                // Gym: Auto-select core gym equipment + Bench, Pull-Up Bar, Dip Bars, Smith Machine (always included for gym)
                selectedEquipment = ["Barbell", "Dumbbells", "Cables", "Machines", "Smith Machine", "Plates", "Bench", "Pull-Up Bar", "Dip Bars"]
            case .home:
                // Home: Bodyweight, bands, dumbbells + kettlebell, chair, wall
                selectedEquipment = ["Bodyweight", "Bands", "Dumbbells", "Kettlebell", "Chair", "Wall"]
            case .outdoor:
                // Outdoor: Bodyweight + portable equipment (first 6 auto-selected)
                selectedEquipment = ["Bodyweight", "Bands", "Pull-Up Bar", "Dip Bars", "Kettlebell", "Medicine Ball"]
            case .hybrid:
                // Hybrid: Mix of home and gym equipment (first 6 auto-selected)
                selectedEquipment = ["Dumbbells", "Bodyweight", "Bands", "Cables", "Machines", "Bench"]
            }
        } else if selectedWorkoutLocation == .gym {
            // Always ensure Bench, Pull-Up Bar, and Dip Bars are included for gym workouts
            if !selectedEquipment.contains("Bench") { selectedEquipment.insert("Bench") }
            if !selectedEquipment.contains("Pull-Up Bar") { selectedEquipment.insert("Pull-Up Bar") }
            if !selectedEquipment.contains("Dip Bars") { selectedEquipment.insert("Dip Bars") }
        }
        // Save to environment service
        WorkoutEnvironmentService.shared.userEnvironment = selectedWorkoutLocation
    }
    
    // MARK: - Equipment Step (Location-Based)
    @State private var showMoreEquipment = false
    
    private var equipmentStep: some View {
        // Primary equipment based on workout location
        // Note: Bench is auto-included for gym (not shown but added to selection)
        let primaryEquipment: [(String, String, Color)] = {
            switch selectedWorkoutLocation {
            case .gym:
                return [
                    ("Barbell", "figure.strengthtraining.traditional", .purple),
                    ("Dumbbells", "dumbbell.fill", .blue),
                    ("Cables", "cable.connector", .orange),
                    ("Machines", "gearshape.2.fill", .green),
                    ("Smith Machine", "square.stack.3d.up.fill", .cyan),
                    ("Plates", "circle.grid.2x2.fill", .gray),
                    ("Kettlebell", "scalemass.fill", .orange),
                    ("TRX/Rings", "link", .mint),
                    ("Medicine Ball", "basketball.fill", .brown),
                ]
            case .home:
                return [
                    ("Bodyweight", "figure.walk", .teal),
                    ("Bands", "circle.hexagongrid.fill", .pink),
                    ("Dumbbells", "dumbbell.fill", .blue),
                    ("Stability Ball", "circle.fill", .mint),
                    ("Chair", "chair.fill", .brown),
                    ("Wall", "rectangle.portrait.fill", .gray),
                    ("Pull-Up Bar", "figure.gymnastics", .purple),
                    ("Dip Bars", "arrow.down.to.line", .indigo),
                    ("Kettlebell", "scalemass.fill", .orange),
                    ("Bench", "rectangle.fill", .indigo),
                ]
            case .outdoor:
                return [
                    // Auto-selected (first 6)
                    ("Bodyweight", "figure.walk", .teal),
                    ("Bands", "circle.hexagongrid.fill", .pink),
                    ("Pull-Up Bar", "figure.gymnastics", .purple),
                    ("Dip Bars", "arrow.down.to.line", .indigo),
                    ("Kettlebell", "scalemass.fill", .orange),
                    ("Medicine Ball", "basketball.fill", .brown),
                    // Not auto-selected (next 3)
                    ("Box", "square.fill", .indigo),
                    ("Dumbbells", "dumbbell.fill", .blue),
                    ("TRX/Rings", "link", .mint),
                    ("Bench", "rectangle.fill", .gray),
                ]
            case .hybrid:
                return [
                    // Auto-selected (first 6)
                    ("Dumbbells", "dumbbell.fill", .blue),
                    ("Bodyweight", "figure.walk", .teal),
                    ("Bands", "circle.hexagongrid.fill", .pink),
                    ("Cables", "cable.connector", .orange),
                    ("Machines", "gearshape.2.fill", .green),
                    ("Bench", "rectangle.fill", .indigo),
                    // Not auto-selected (next 4)
                    ("Barbell", "figure.strengthtraining.traditional", .purple),
                    ("Kettlebell", "scalemass.fill", .orange),
                    ("Pull-Up Bar", "figure.gymnastics", .purple),
                    ("Dip Bars", "arrow.down.to.line", .indigo),
                ]
            }
        }()
        
        // Secondary equipment (Show More) - ordered by likelihood of use
        let secondaryEquipment: [(String, String, Color)] = {
            switch selectedWorkoutLocation {
            case .gym:
                // Ordered from most to least likely in a gym
                // Note: Pull-Up Bar and Dip Bars are auto-included but shown here for visibility
                return [
                    ("TRX/Rings", "link", .mint),
                    ("Pull-Up Bar", "figure.gymnastics", .purple),
                    ("Dip Bars", "arrow.down.to.line", .indigo),
                    ("Landmine", "arrow.up.forward", .gray),
                    ("Battle Ropes", "waveform", .red),
                    ("Sled", "arrow.forward.square", .brown),
                    ("Foam Roller", "cylinder.fill", .pink),
                    ("Bands", "circle.hexagongrid.fill", .pink),
                    ("Stability Ball", "circle.fill", .mint),
                    ("Bodyweight", "figure.walk", .teal),
                    ("Bench", "rectangle.fill", .indigo),  // Hidden but available if they want to see it
                    ("Step Platform", "stairs", .gray),
                    ("Chair", "chair.fill", .secondary),
                    ("Wall", "rectangle.portrait.fill", .secondary),
                    ("Towel", "rectangle.compress.vertical", .secondary),
                ]
            case .home:
                // All other equipment in the app for home users
                return [
                    ("TRX/Rings", "link", .mint),
                    ("Medicine Ball", "basketball.fill", .brown),
                    ("Barbell", "figure.strengthtraining.traditional", .purple),
                    ("Cables", "cable.connector", .orange),
                    ("Machines", "gearshape.2.fill", .green),
                    ("Smith Machine", "square.stack.3d.up.fill", .cyan),
                    ("Plates", "circle.grid.2x2.fill", .gray),
                    ("Box", "square.fill", .indigo),
                    ("Landmine", "arrow.up.forward", .gray),
                    ("Battle Ropes", "waveform", .red),
                    ("Sled", "arrow.forward.square", .brown),
                    ("Foam Roller", "cylinder.fill", .pink),
                    ("Step Platform", "stairs", .gray),
                    ("Towel", "rectangle.compress.vertical", .secondary),
                ]
            case .outdoor:
                // All other equipment from most to least likely outdoors
                return [
                    ("Stability Ball", "circle.fill", .mint),
                    ("Battle Ropes", "waveform", .red),
                    ("Sled", "arrow.forward.square", .brown),
                    ("Foam Roller", "cylinder.fill", .pink),
                    ("Plates", "circle.grid.2x2.fill", .gray),
                    ("Barbell", "figure.strengthtraining.traditional", .purple),
                    ("Step Platform", "stairs", .gray),
                    ("Landmine", "arrow.up.forward", .gray),
                    ("Chair", "chair.fill", .secondary),
                    ("Wall", "rectangle.portrait.fill", .secondary),
                    ("Towel", "rectangle.compress.vertical", .secondary),
                    ("Smith Machine", "square.stack.3d.up.fill", .secondary),
                    ("Cables", "cable.connector", .secondary),
                    ("Machines", "gearshape.2.fill", .secondary),
                ]
            case .hybrid:
                // All other equipment from most to least likely for hybrid users
                return [
                    ("Smith Machine", "square.stack.3d.up.fill", .cyan),
                    ("TRX/Rings", "link", .mint),
                    ("Stability Ball", "circle.fill", .mint),
                    ("Medicine Ball", "basketball.fill", .brown),
                    ("Plates", "circle.grid.2x2.fill", .gray),
                    ("Box", "square.fill", .indigo),
                    ("Landmine", "arrow.up.forward", .gray),
                    ("Battle Ropes", "waveform", .red),
                    ("Sled", "arrow.forward.square", .brown),
                    ("Foam Roller", "cylinder.fill", .pink),
                    ("Chair", "chair.fill", .secondary),
                    ("Wall", "rectangle.portrait.fill", .secondary),
                    ("Step Platform", "stairs", .gray),
                    ("Towel", "rectangle.compress.vertical", .secondary),
                ]
            }
        }()
        
        let primaryNames = Set(primaryEquipment.map { $0.0 })
        let allPrimarySelected = primaryNames.isSubset(of: selectedEquipment)
        
        return OnboardingStepContainer(
            canGoBack: !isEditingFromConfirmation,
            onBack: { isEditingFromConfirmation ? navigateTo(.confirmation) : navigateTo(.workoutLocation) },
            onContinue: { isEditingFromConfirmation ? returnToConfirmation() : navigateTo(.limitations) },
            continueEnabled: !selectedEquipment.isEmpty,
            continueLabel: isEditingFromConfirmation ? "Save" : "Continue",
            currentStep: 7,
            totalSteps: 9,
            question: equipmentQuestionText,
            subtitle: "Tap all that you have access to"
        ) {
            ScrollView {
                VStack(spacing: 16) {
                    // Select All Primary button
                    Button(action: {
                        selectionFeedback.selectionChanged()
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            if allPrimarySelected {
                                for name in primaryNames {
                                    selectedEquipment.remove(name)
                                }
                            } else {
                                selectedEquipment.formUnion(primaryNames)
                            }
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: allPrimarySelected ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 16))
                            Text(allPrimarySelected ? "Deselect All" : "Select All")
                                .font(.subheadline.weight(.semibold))
                        }
                        .foregroundStyle(LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing))
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.horizontal, 20)
                    
                    // Primary Equipment grid - 3 columns
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        ForEach(primaryEquipment, id: \.0) { item in
                            OnboardingSelectionCard(
                                title: item.0,
                                subtitle: nil,
                                icon: item.1,
                                color: item.2,
                                isSelected: selectedEquipment.contains(item.0),
                                onTap: {
                                    selectionFeedback.selectionChanged()
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        if selectedEquipment.contains(item.0) {
                                            selectedEquipment.remove(item.0)
                                        } else {
                                            selectedEquipment.insert(item.0)
                                        }
                                    }
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    
                    // Show More Button
                    Button(action: {
                        withAnimation(.spring(response: 0.3)) {
                            showMoreEquipment.toggle()
                        }
                    }) {
                        HStack {
                            Text(showMoreEquipment ? "Show Less" : "Show More Equipment")
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            Image(systemName: showMoreEquipment ? "chevron.up" : "chevron.down")
                                .font(.caption)
                        }
                        .foregroundColor(.blue)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                    }
                    
                    // Secondary Equipment (collapsed by default)
                    if showMoreEquipment {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Additional equipment options:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 4)
                            
                            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                                ForEach(secondaryEquipment, id: \.0) { item in
                                    OnboardingSelectionCard(
                                        title: item.0,
                                        subtitle: nil,
                                        icon: item.1,
                                        color: item.2.opacity(0.8),
                                        isSelected: selectedEquipment.contains(item.0),
                                        onTap: {
                                            selectionFeedback.selectionChanged()
                                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                                if selectedEquipment.contains(item.0) {
                                                    selectedEquipment.remove(item.0)
                                                } else {
                                                    selectedEquipment.insert(item.0)
                                                }
                                            }
                                        }
                                    )
                                }
                            }
                        }
                        .padding(16)
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                        .padding(.horizontal, 20)
                    }
                    
                    // Help text
                    Text("You can change this anytime in settings")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 8)
                }
                .padding(.bottom, 20)
            }
        }
    }
    
    private var equipmentQuestionText: String {
        switch selectedWorkoutLocation {
        case .gym: return "Gym equipment?"
        case .home: return "Home equipment?"
        case .outdoor: return "Outdoor equipment?"
        case .hybrid: return "Available equipment?"
        }
    }
    
    private var locationIcon: String {
        switch selectedWorkoutLocation {
        case .gym: return "building.2.fill"
        case .home: return "house.fill"
        case .outdoor: return "sun.max.fill"
        case .hybrid: return "arrow.triangle.2.circlepath"
        }
    }
    
    // MARK: - Limitations Step (Injury/Pain Tracking)
    private var limitationsStep: some View {
        let commonAreas = AffectedArea.commonAreas
        
        return VStack(spacing: 0) {
            // Top Navigation Bar
            OnboardingNavBar(
                canGoBack: !isEditingFromConfirmation,
                onBack: { isEditingFromConfirmation ? navigateTo(.confirmation) : navigateTo(.equipment) },
                onContinue: { isEditingFromConfirmation ? returnToConfirmation() : navigateTo(.schedule) },
                continueEnabled: true,
                continueLabel: isEditingFromConfirmation ? "Save" : "Continue"
            )
            
            // Progress Bar
            OnboardingProgressBar(
                currentStep: 8,
                totalSteps: 9,
                stepName: ""
            )
            .padding(.top, 4)
            
            // Question header
            OnboardingQuestionHeader(
                question: "Any limitations?",
                subtitle: "Help us keep you safe"
            )
            .padding(.top, 24)
            .padding(.bottom, 16)
            
            // Skip button
            Button(action: {
                selectionFeedback.selectionChanged()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    selectedLimitations.removeAll()
                    limitationAccommodations.removeAll()
                }
            }) {
                HStack(spacing: 8) {
                    Image(systemName: selectedLimitations.isEmpty ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 18))
                    Text("No injuries or limitations")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(
                    selectedLimitations.isEmpty
                        ? AnyShapeStyle(LinearGradient(colors: [.green, .mint], startPoint: .leading, endPoint: .trailing))
                        : AnyShapeStyle(Color.secondary)
                )
                .padding(.vertical, 12)
                .padding(.horizontal, 20)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(selectedLimitations.isEmpty ? Color.green.opacity(0.1) : Color.clear)
                )
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
            
            // Limitation cards - full screen scroll
            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    ForEach(commonAreas) { area in
                        LimitationCardOnboardingWide(
                            area: area,
                            isSelected: selectedLimitations.contains(area),
                            accommodation: limitationAccommodations[area] ?? .beCareful,
                            action: {
                                selectionFeedback.selectionChanged()
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    if selectedLimitations.contains(area) {
                                        selectedLimitations.remove(area)
                                        limitationAccommodations.removeValue(forKey: area)
                                    } else {
                                        selectedLimitations.insert(area)
                                        limitationAccommodations[area] = .beCareful
                                    }
                                }
                            },
                            onAccommodationChange: { newLevel in
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    limitationAccommodations[area] = newLevel
                                }
                            }
                        )
                        .accessibilityLabel("\(area.rawValue). \(selectedLimitations.contains(area) ? "Selected" : "Not selected")")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
    }
    
    // MARK: - Schedule Step
    private var scheduleStep: some View {
        OnboardingStepContainer(
            canGoBack: !isEditingFromConfirmation,
            onBack: { isEditingFromConfirmation ? navigateTo(.confirmation) : navigateTo(.limitations) },
            onContinue: { returnToConfirmation() },
            continueEnabled: true,
            continueLabel: isEditingFromConfirmation ? "Save" : "Review & Finish",
            currentStep: 9,
            totalSteps: 9,
            question: "Weekly workouts?",
            subtitle: "Pick what's realistic for you"
        ) {
            VStack(spacing: 24) {
                // Large number display
                VStack(spacing: 4) {
                    Text("\(selectedDays)")
                        .font(.system(size: 80, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing)
                        )
                    
                    Text(selectedDays == 1 ? "day per week" : "days per week")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.secondary)
                }
                
                // Day selector - larger buttons
                HStack(spacing: 8) {
                    ForEach(1...7, id: \.self) { day in
                        DaySelectorButtonLarge(day: day, isSelected: selectedDays == day) {
                            selectionFeedback.selectionChanged()
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                selectedDays = day
                            }
                        }
                        .accessibilityLabel("\(day) days per week")
                        .accessibilityHint(selectedDays == day ? "Currently selected" : "Double tap to select")
                    }
                }
                .padding(.horizontal, 16)
                
                // Recommendation badge
                Text(recommendationText)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.blue)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.blue.opacity(0.1)))
                
                // Help text
                Text("Better to commit to 3 days than plan 6 and burn out")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
    }
    
    private var recommendationText: String {
        switch selectedDays {
        case 1...2: return "Great for beginners. Focus on full-body workouts."
        case 3...4: return "Perfect balance for most goals. You'll see great results!"
        case 5...6: return "Dedicated training. Make sure to include rest days."
        case 7: return "Every day? Remember, recovery is when muscles grow!"
        default: return ""
        }
    }
    
    // Helper to return to confirmation and reset editing flag
    private func returnToConfirmation() {
        // Navigate first without animation, then reset the flag
        currentStep = .confirmation
        isEditingFromConfirmation = false
    }
    
    // MARK: - Confirmation Step (Review before creating account)
    private var confirmationStep: some View {
        VStack(spacing: 0) {
            // Header - fixed at top
            VStack(spacing: 4) {
                Text("Review Your Profile")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.primary)
                
                Text("Tap any row to make changes")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
            .padding(.top, 24)
            .padding(.bottom, 8)
            
            // Scrollable content
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    
                    // Clean list view
                    VStack(spacing: 0) {
                        // Account Section
                        ConfirmationListSection(title: "ACCOUNT") {
                            ConfirmationListRow(icon: "person.fill", label: "Name", value: name) {
                                isEditingFromConfirmation = true
                                navigateTo(.auth)
                            }
                            ConfirmationListRow(icon: "envelope.fill", label: "Email", value: email) {
                                isEditingFromConfirmation = true
                                navigateTo(.auth)
                            }
                        }
                        
                        // Personal Section
                        ConfirmationListSection(title: "PERSONAL") {
                            ConfirmationListRow(icon: "calendar", label: "Birthday", value: birthday) {
                                isEditingFromConfirmation = true
                                navigateTo(.basics)
                            }
                            ConfirmationListRow(icon: "person.2.fill", label: "Gender", value: selectedGender ?? "Not set") {
                                isEditingFromConfirmation = true
                                navigateTo(.basics)
                            }
                            ConfirmationListRow(icon: "ruler", label: "Height", value: formattedHeight) {
                                isEditingFromConfirmation = true
                                navigateTo(.body)
                            }
                            ConfirmationListRow(icon: "scalemass", label: "Weight", value: formattedWeight) {
                                isEditingFromConfirmation = true
                                navigateTo(.body)
                            }
                        }
                        
                        // Fitness Section
                        ConfirmationListSection(title: "FITNESS") {
                            ConfirmationListRow(icon: "target", label: "Goal", value: selectedGoals.isEmpty ? "Not set" : selectedGoals.sorted().joined(separator: ", ")) {
                                isEditingFromConfirmation = true
                                navigateTo(.goal)
                            }
                            ConfirmationListRow(icon: "chart.bar.fill", label: "Experience", value: selectedExperience) {
                                isEditingFromConfirmation = true
                                navigateTo(.experience)
                            }
                            ConfirmationListRow(icon: "dumbbell.fill", label: "Equipment", value: selectedEquipment.isEmpty ? "None" : Array(selectedEquipment).joined(separator: ", ")) {
                                isEditingFromConfirmation = true
                                navigateTo(.equipment)
                            }
                            ConfirmationListRow(icon: "bandage.fill", label: "Limitations", value: selectedLimitations.isEmpty ? "None" : selectedLimitations.map { $0.rawValue }.sorted().joined(separator: ", ")) {
                                isEditingFromConfirmation = true
                                navigateTo(.limitations)
                            }
                            ConfirmationListRow(icon: "calendar.badge.clock", label: "Schedule", value: "\(selectedDays) days/week") {
                                isEditingFromConfirmation = true
                                navigateTo(.schedule)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    
                    // Error message if account creation fails
                    if showError {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                            .padding(.top, 8)
                    }
                    
                    Spacer().frame(height: 20)
                }
            }
            
            // Navigation buttons - fixed at bottom
            HStack(spacing: 16) {
                Button(action: { navigateTo(.schedule) }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(LinearGradient(colors: [.blue, .purple.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 52, height: 52)
                        .background(Circle().fill(Color(.systemBackground)).shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4))
                        .overlay(Circle().stroke(LinearGradient(colors: [.blue.opacity(0.3), .purple.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.5))
                }
                
                Button(action: { createAccountAndComplete() }) {
                    HStack {
                        if supabaseManager.isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Text(isSignUp ? "Create Account" : "Finish Setup")
                                .font(.headline).fontWeight(.bold)
                        }
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 16)
                    .background(
                        Capsule()
                            .fill(LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing))
                            .shadow(color: .purple.opacity(0.4), radius: 12, x: 0, y: 6)
                    )
                }
                .disabled(supabaseManager.isLoading)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 30)
        }
    }
    
    // Formatted height for display
    private var formattedHeight: String {
        if heightUnit == .cm {
            return "\(heightCm) cm"
        } else if let parsed = parsedHeightFeetInches {
            return "\(parsed.feet)'\(parsed.inches)\""
        }
        return heightFeetInchesDigits
    }
    
    // Formatted weight for display
    private var formattedWeight: String {
        if weightUnit == .lbs {
            return "\(weight) lbs"
        } else {
            return "\(weight) kg"
        }
    }
    
    // Create account (for signup) and complete onboarding
    private func createAccountAndComplete() {
        showError = false
        errorMessage = ""
        emailAlreadyExists = false
        
        // If user is already authenticated (e.g., via Apple/Google Sign-In), skip account creation
        if supabaseManager.isAuthenticated {
            print("✅ User already authenticated (social sign-in) - completing onboarding")
            completeOnboarding()
            return
        }
        
        if isSignUp {
            // For sign up: Create the Supabase account first
            Task {
                do {
                    try await supabaseManager.signUp(email: email, password: password, name: name.isEmpty ? "User" : name)
                    
                    await MainActor.run {
                        // Account created successfully, now complete onboarding
                        completeOnboarding()
                    }
                } catch {
                    await MainActor.run {
                        let errorString = error.localizedDescription.lowercased()
                        // Check if error indicates email already exists
                        if errorString.contains("already registered") || 
                           errorString.contains("already exists") ||
                           errorString.contains("email already") ||
                           errorString.contains("user already") {
                            emailAlreadyExists = true
                            // Navigate back to auth step to show the message
                            currentStep = .auth
                        } else {
                            errorMessage = error.localizedDescription
                            showError = true
                        }
                    }
                }
            }
        } else {
            // For sign in: User is already authenticated, just complete onboarding
            completeOnboarding()
        }
    }
    
    private func sendPasswordReset() {
        guard !email.isEmpty && email.contains("@") else { return }
        
        passwordResetSent = false
        showError = false
        emailAlreadyExists = false
        
        Task {
            do {
                try await supabaseManager.resetPassword(email: email)
                await MainActor.run {
                    passwordResetSent = true
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to send reset email. Please try again."
                    showError = true
                }
            }
        }
    }
    
    private func clearAuthMessages() {
        showError = false
        errorMessage = ""
        emailAlreadyExists = false
        passwordResetSent = false
    }
    
    // MARK: - Complete Step
    private var completeStep: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                Spacer()
                
                // Success animation
                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.1))
                        .frame(width: 110, height: 110)
                    
                    Circle()
                        .fill(Color.green.opacity(0.2))
                        .frame(width: 80, height: 80)
                    
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.green)
                }
                
                Spacer()
                    .frame(height: 24)
                
                VStack(spacing: 8) {
                    Text("You're all set!")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(.primary)
                    
                    Text("Let's start building a stronger you")
                        .font(.system(size: 15))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                    .frame(height: 28)
                
                // Summary
                VStack(spacing: 12) {
                    SummaryRow(icon: "target", label: "Goal", value: selectedGoals.sorted().joined(separator: ", "))
                    SummaryRow(icon: "figure.walk", label: "Level", value: selectedExperience)
                    SummaryRow(icon: "hand.raised.fill", label: "Strength", value: selectedStrengthLevel.displayName)
                    SummaryRow(icon: "calendar", label: "Schedule", value: "\(selectedDays) days/week")
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(.systemBackground))
                        .shadow(color: Color.blue.opacity(0.08), radius: 8, x: 0, y: 4)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            LinearGradient(
                                colors: [Color.blue.opacity(0.2), Color.purple.opacity(0.15)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .padding(.horizontal, 24)
                
                Spacer()
            }
            .padding(.bottom, 100)
            
            // Start button - floating at bottom
            Button(action: finishOnboarding) {
                Text("Start Training 💪")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        LinearGradient(
                            colors: [Color.green, Color.mint],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(16)
                    .shadow(color: Color.green.opacity(0.4), radius: 10, x: 0, y: 5)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 30)
        }
    }
    
    // MARK: - Actions
    
    private var isAuthValid: Bool {
        !email.isEmpty && password.count >= 6
    }
    
    private func handleAuth() {
        showError = false
        errorMessage = ""
        showAuthProviderHint = false
        
        if isSignUp {
            // For sign up: Just validate and proceed to next step
            // Account will be created on the confirmation screen
            navigateTo(.basics)
        } else {
            // For sign in: First check if email is linked to Apple/Google
            Task {
                // Check what auth provider this email uses
                let provider = await supabaseManager.checkAuthProvider(for: email)
                
                if let providerInfo = supabaseManager.getAuthProviderMessage(for: provider) {
                    // Email is linked to Apple/Google - show helpful message
                    await MainActor.run {
                        detectedAuthProvider = provider
                        authProviderHintMessage = providerInfo.message
                        showAuthProviderHint = true
                        showError = false
                    }
                    return
                }
                
                // Normal email/password login
                do {
                    try await supabaseManager.signIn(email: email, password: password)
                    
                    await MainActor.run {
                        navigateTo(.basics)
                    }
                } catch {
                    await MainActor.run {
                        // Check if it's a credential error and they might have used social login
                        if error.localizedDescription.contains("Invalid login credentials") {
                            // Double-check provider (in case RPC wasn't available)
                            errorMessage = "Invalid email or password. If you signed up with Apple, please use that button below."
                        } else {
                            errorMessage = error.localizedDescription
                        }
                        showError = true
                    }
                }
            }
        }
    }
    
    private func saveLimitationsToCloud() async {
        guard let userId = SupabaseManager.shared.currentUser?.id else {
            print("⚠️ [ONBOARDING] No user ID available for limitations")
            return
        }
        
        let limitations = selectedLimitations.map { area in
            UserLimitation(
                id: UUID(),
                userId: userId,
                limitationType: .injury,
                affectedArea: area,
                severity: limitationAccommodations[area] ?? .beCareful,
                exercisesToAvoid: [],  // Will be populated from mappings
                movementPatternsToAvoid: [],
                equipmentToAvoid: [],
                notes: nil,
                startedDate: Date(),
                expectedRecoveryDate: nil,
                resolvedDate: nil,
                isActive: true,
                createdAt: Date(),
                updatedAt: Date()
            )
        }
        
        do {
            try await LimitationsService.shared.addLimitations(limitations)
            print("✅ [ONBOARDING] Saved \(limitations.count) limitations to cloud")
        } catch {
            print("❌ [ONBOARDING] Failed to save limitations: \(error)")
        }
    }
    
    private func completeOnboarding() {
        // Log onboarding completion
        SessionLogManager.shared.logOnboardingComplete(
            totalSteps: OnboardingStep.allCases.count,
            duration: 0 // We don't track duration yet
        )
        
        // Calculate age from birthday
        let ageInt = Int16(calculatedAge)
        
        // Get height in cm
        let heightInt = Int16(heightInCm)
        
        // Get weight in kg
        let weightInt: Int16
        if let w = Double(weight) {
            if weightUnit == .lbs {
                weightInt = Int16(w / 2.20462) // Convert lbs to kg
            } else {
                weightInt = Int16(w)
            }
        } else {
            print("❌ Invalid weight")
            return
        }
        
        print("╔══════════════════════════════════════════════════════════════╗")
        print("║            🎯 ONBOARDING DATA COLLECTION COMPLETE            ║")
        print("╠══════════════════════════════════════════════════════════════╣")
        print("║ BASIC INFO:")
        print("║   Name: \(name)")
        print("║   Email: \(email.isEmpty ? "Not provided" : email)")
        print("║   Age: \(ageInt) years")
        print("║   Gender: \(selectedGender ?? "Not specified")")
        print("╠══════════════════════════════════════════════════════════════╣")
        print("║ BODY METRICS:")
        print("║   Height: \(heightInt) cm")
        print("║   Weight: \(weightInt) kg")
        print("╠══════════════════════════════════════════════════════════════╣")
        print("║ FITNESS PROFILE:")
        print("║   Goals: \(selectedGoals.sorted().joined(separator: ", "))")
        print("║   Experience: \(selectedExperience)")
        print("║   Strength Level: \(selectedStrengthLevel.rawValue)")
        print("╠══════════════════════════════════════════════════════════════╣")
        print("║ WORKOUT PREFERENCES:")
        print("║   Environment: \(selectedWorkoutLocation.rawValue)")
        print("║   Equipment: \(selectedEquipment.sorted().joined(separator: ", "))")
        print("║   Days/Week: \(selectedDays)")
        print("╠══════════════════════════════════════════════════════════════╣")
        print("║ LIMITATIONS:")
        if selectedLimitations.isEmpty {
            print("║   None reported")
        } else {
            for area in selectedLimitations {
                let level = limitationAccommodations[area] ?? .beCareful
                print("║   • \(area.rawValue): \(level.displayName)")
            }
        }
        print("╚══════════════════════════════════════════════════════════════╝")
        
        // Get original height in total inches for storage
        let heightInches: Int16
        if heightUnit == .ftIn, let parsed = parsedHeightFeetInches {
            heightInches = Int16(parsed.feet * 12 + parsed.inches)
        } else {
            // Convert from cm to inches if user used metric
            heightInches = Int16(Double(heightInCm) / 2.54)
        }
        
        // Get original weight in lbs for storage
        let weightLbs: Double
        if weightUnit == .lbs {
            weightLbs = Double(weight) ?? 0
        } else {
            // Convert from kg to lbs
            weightLbs = (Double(weight) ?? 0) * 2.20462
        }
        
        userManager.createUser(
            name: name,
            age: ageInt,
            gender: selectedGender,
            email: email.isEmpty ? nil : email,
            height: heightInt,
            weight: weightInt,
            fitnessGoal: selectedGoals.sorted().joined(separator: ", "),
            experienceLevel: selectedExperience,
            equipment: Array(selectedEquipment),
            availableDays: Int16(selectedDays),
            strengthLevel: selectedStrengthLevel.rawValue,
            workoutEnvironment: selectedWorkoutLocation.rawValue,
            birthday: birthday.isEmpty ? nil : birthday,
            weightLbs: weightLbs,
            heightInches: heightInches
        )
        
        // Save user limitations to cloud
        if !selectedLimitations.isEmpty {
            Task {
                await saveLimitationsToCloud()
            }
        }
        
        // Sync video gender preference based on user's gender selection
        VideoStreamingService.shared.syncGenderFromUserProfile()
        
        // Show completion screen
        navigateTo(.complete)
    }
    
    private func finishOnboarding() {
        // UserManager.createUser already sets hasCompletedOnboarding = true
        // The view will automatically transition via ContentView
        print("✅ [ONBOARDING] Complete! Transitioning to main app...")
        
        // Generate personalized programs based on user profile
        if let user = userManager.currentUser {
            Task {
                print("🎯 Generating personalized workout programs...")
                _ = await GeneratedProgramService.shared.generateProgramsForUser(user)
                print("✅ Programs generated!")
            }
        }
        
        // Request notification permissions (on by default for new users)
        Task {
            let granted = await NotificationManager.shared.requestAuthorization()
            if granted {
                print("✅ [NOTIFICATIONS] Permissions granted during onboarding")
            }
        }
    }
    
    // MARK: - Social Login Handlers
    
    private func handleAppleSignIn() {
        socialAuthService.signInWithApple { result in
            switch result {
            case .success(let credentials):
                // Use the credentials to sign in with Supabase
                Task {
                    do {
                        // Returns true if this is a NEW user who needs onboarding
                        let isNewUser = try await supabaseManager.signInWithApple(
                            idToken: credentials.identityToken,
                            nonce: credentials.nonce
                        )
                        
                        // Set name from Apple credentials if available
                        if let fullName = credentials.fullName {
                            let firstName = fullName.givenName ?? ""
                            let lastName = fullName.familyName ?? ""
                            let fullNameStr = [firstName, lastName].filter { !$0.isEmpty }.joined(separator: " ")
                            await MainActor.run {
                                if !fullNameStr.isEmpty {
                                    name = fullNameStr
                                }
                            }
                        }
                        
                        // Get email - try Apple credentials first, then Supabase session
                        if let appleEmail = credentials.email, !appleEmail.isEmpty {
                            await MainActor.run {
                                email = appleEmail
                            }
                        } else if let sessionEmail = supabaseManager.currentUser?.email, !sessionEmail.isEmpty {
                            // Apple didn't send email, but Supabase has it from the auth
                            await MainActor.run {
                                email = sessionEmail
                                // If name is still empty, try to derive from email
                                if name.isEmpty || name == "Apple User" {
                                    if !sessionEmail.contains("privaterelay") {
                                        name = sessionEmail.components(separatedBy: "@").first ?? ""
                                    }
                                }
                            }
                        }
                        
                        await MainActor.run {
                            if isNewUser {
                                // New user - go to profile setup
                                print("👤 [SOCIAL AUTH] New Apple user - directing to onboarding")
                                navigateTo(.basics)
                            } else {
                                // Returning user - they'll be redirected to main app via ContentView
                                print("✅ [SOCIAL AUTH] Returning Apple user signed in")
                            }
                        }
                    } catch {
                        await MainActor.run {
                            errorMessage = "Apple Sign-In failed: \(error.localizedDescription)"
                            showError = true
                        }
                    }
                }
                
            case .failure(let error):
                DispatchQueue.main.async {
                    // Don't show error for user cancellation
                    if (error as NSError).code != 1001 { // ASAuthorizationError.canceled
                        errorMessage = "Apple Sign-In failed: \(error.localizedDescription)"
                        showError = true
                    }
                }
            }
        }
    }
    
    private func handleGoogleSignIn() {
        // Open Google OAuth in Safari
        if let url = supabaseManager.getGoogleOAuthURL() {
            UIApplication.shared.open(url)
        } else {
            errorMessage = "Could not create Google Sign-In URL"
            showError = true
        }
    }
    
}

// MARK: - Supporting Views

struct OnboardingTextField<F: Hashable>: View {
    @Environment(\.colorScheme) private var colorScheme
    let icon: String
    let placeholder: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default
    var isSecure: Bool = false
    var focusedField: FocusState<F?>.Binding?
    var fieldValue: F?
    var isValid: Bool = false // Whether field is completed/valid
    
    private var isFocused: Bool {
        if let focusedField = focusedField, let fieldValue = fieldValue {
            return focusedField.wrappedValue == fieldValue
        }
        return false
    }
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(
                    LinearGradient(
                        colors: isValid ? [Color.blue, Color.cyan] : [Color.gray.opacity(0.6), Color.gray.opacity(0.5)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 26)
                .allowsHitTesting(false) // Don't capture taps on icon
            
            if isSecure {
                if let focusedField = focusedField, let fieldValue = fieldValue {
                    SecureField(placeholder, text: $text)
                        .textInputAutocapitalization(.never)
                        .focused(focusedField, equals: fieldValue)
                } else {
                    SecureField(placeholder, text: $text)
                        .textInputAutocapitalization(.never)
                }
            } else {
                if let focusedField = focusedField, let fieldValue = fieldValue {
                    TextField(placeholder, text: $text)
                        .keyboardType(keyboardType)
                        .textInputAutocapitalization(keyboardType == .emailAddress ? .never : .words)
                        .focused(focusedField, equals: fieldValue)
                } else {
                    TextField(placeholder, text: $text)
                        .keyboardType(keyboardType)
                        .textInputAutocapitalization(keyboardType == .emailAddress ? .never : .words)
                }
            }
            
            // Checkmark when valid
            if isValid {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.blue)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .font(.system(size: 16, weight: .medium))
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
        .contentShape(RoundedRectangle(cornerRadius: 16)) // Rounded rectangle hit area
        .background(
            // Modern floating card effect
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(colorScheme == .dark ? Color(white: 0.12) : Color.white)
                
                // Enhanced shadow for floating effect
                RoundedRectangle(cornerRadius: 16)
                    .fill(colorScheme == .dark ? Color(white: 0.12) : Color.white)
                    .shadow(
                        color: colorScheme == .dark ? Color.black.opacity(0.4) : Color.black.opacity(0.08),
                        radius: isFocused ? 12 : 8,
                        x: 0,
                        y: isFocused ? 6 : 3
                    )
                    .shadow(
                        color: isValid ? Color.blue.opacity(0.2) : Color.clear,
                        radius: 15,
                        x: 0,
                        y: 4
                    )
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    LinearGradient(
                        colors: isValid 
                            ? [Color.blue.opacity(0.6), Color.cyan.opacity(0.5)]
                            : isFocused
                            ? [Color.blue.opacity(0.4), Color.cyan.opacity(0.3)]
                            : colorScheme == .dark
                            ? [Color.white.opacity(0.1), Color.clear]
                            : [Color.gray.opacity(0.15), Color.clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: isFocused || isValid ? 2 : 1
                )
        )
        .animation(.easeInOut(duration: 0.25), value: isValid)
        .animation(.easeInOut(duration: 0.2), value: isFocused)
    }
}

// MARK: - Password Text Field with Show/Hide Toggle
struct PasswordTextField<F: Hashable>: View {
    @Environment(\.colorScheme) private var colorScheme
    let placeholder: String
    @Binding var text: String
    @Binding var isVisible: Bool
    var focusedField: FocusState<F?>.Binding?
    var fieldValue: F?
    var showMatchIndicator: Bool = false
    var passwordsMatch: Bool = false
    var isValid: Bool = false // Whether field is completed/valid
    
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "lock.fill")
                .font(.system(size: 18))
                .foregroundStyle(
                    LinearGradient(
                        colors: isValid ? [Color.blue, Color.cyan.opacity(0.8)] : [Color.gray.opacity(0.5), Color.gray.opacity(0.4)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 24)
                .allowsHitTesting(false) // Don't capture taps on icon
            
            ZStack {
                if let focusedField = focusedField, let fieldValue = fieldValue {
                    TextField(placeholder, text: $text)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused(focusedField, equals: fieldValue)
                        .opacity(isVisible ? 1 : 0)
                    
                    SecureField(placeholder, text: $text)
                        .textInputAutocapitalization(.never)
                        .focused(focusedField, equals: fieldValue)
                        .opacity(isVisible ? 0 : 1)
                } else {
                    TextField(placeholder, text: $text)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .opacity(isVisible ? 1 : 0)
                    
                    SecureField(placeholder, text: $text)
                        .textInputAutocapitalization(.never)
                        .opacity(isVisible ? 0 : 1)
                }
            }
            
            // Match indicator (for confirm password) - only show when valid
            if showMatchIndicator && !text.isEmpty && passwordsMatch {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.blue)
                    .allowsHitTesting(false)
                    .transition(.scale.combined(with: .opacity))
            }
            
            Button(action: { isVisible.toggle() }) {
                Image(systemName: isVisible ? "eye.slash.fill" : "eye.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain) // Prevent keyboard dismissal
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .contentShape(RoundedRectangle(cornerRadius: 16)) // Match OnboardingTextField shape
        .background(
            // Modern floating card effect - matching OnboardingTextField
            RoundedRectangle(cornerRadius: 16)
                .fill(colorScheme == .dark ? Color(white: 0.12) : Color.white)
                .shadow(color: colorScheme == .dark ? Color.black.opacity(0.4) : Color.black.opacity(0.08), radius: 8, x: 0, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    LinearGradient(
                        colors: isValid 
                            ? [Color.blue.opacity(0.5), Color.cyan.opacity(0.4)]
                            : [Color.gray.opacity(0.2), Color.gray.opacity(0.15)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: isValid ? 1.5 : 1
                )
        )
        .animation(.easeInOut(duration: 0.3), value: isValid)
    }
}

// MARK: - Password Requirements View
struct PasswordRequirementsView: View {
    let hasMinLength: Bool
    let hasUppercase: Bool
    let hasLowercase: Bool
    let hasNumber: Bool
    let hasSpecialChar: Bool
    
    var body: some View {
        // Clean single-row compact pills
        HStack(spacing: 6) {
            RequirementPillCompact(met: hasMinLength, label: "8+")
            RequirementPillCompact(met: hasUppercase, label: "ABC")
            RequirementPillCompact(met: hasLowercase, label: "abc")
            RequirementPillCompact(met: hasNumber, label: "123")
            RequirementPillCompact(met: hasSpecialChar, label: "!@#")
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Terms and Conditions Sheet
struct TermsAndConditionsSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            TermsConditionsView()
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") {
                            dismiss()
                        }
                        .fontWeight(.semibold)
                    }
                }
        }
    }
}

struct RequirementPillCompact: View {
    let met: Bool
    let label: String
    
    var body: some View {
        Text(label)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundColor(met ? .white : .secondary.opacity(0.5))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .stroke(
                        met ? LinearGradient(colors: [.blue, .cyan.opacity(0.8)], startPoint: .leading, endPoint: .trailing)
                            : LinearGradient(colors: [Color.gray.opacity(0.3), Color.gray.opacity(0.3)], startPoint: .leading, endPoint: .trailing),
                        lineWidth: met ? 2 : 1.5
                    )
                    .shadow(color: met ? Color.blue.opacity(0.5) : .clear, radius: 6, x: 0, y: 0)
                    .shadow(color: met ? Color.cyan.opacity(0.3) : .clear, radius: 10, x: 0, y: 0)
            )
            .animation(.easeInOut(duration: 0.2), value: met)
    }
}

struct RequirementPill: View {
    let met: Bool
    let text: String
    
    var body: some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.medium)
            .foregroundColor(met ? .green : .secondary.opacity(0.6))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(met ? Color.green.opacity(0.15) : Color.secondary.opacity(0.1))
            )
            .overlay(
                Capsule()
                    .stroke(met ? Color.green.opacity(0.3) : Color.clear, lineWidth: 1)
            )
    }
}

struct RequirementRow: View {
    let met: Bool
    let text: String
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: met ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 12))
                .foregroundColor(met ? .green : .secondary.opacity(0.5))
            Text(text)
                .font(.caption)
                .foregroundColor(met ? .primary : .secondary.opacity(0.7))
        }
    }
}

struct OnboardingPageTemplate<Content: View>: View {
    let title: String
    let subtitle: String
    var helpText: String? = nil
    let canContinue: Bool
    let onBack: () -> Void
    let onContinue: () -> Void
    var continueText: String = "Continue"
    var showBackButton: Bool = true
    var currentStep: Int = 1
    var totalSteps: Int = 9
    @ObservedObject var keyboardObserver: KeyboardObserver
    @ViewBuilder let content: Content
    
    private var keyboardUp: Bool {
        keyboardObserver.keyboardHeight > 0
    }
    
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Top Navigation Bar (floating style) - FIXED at top, never moves
                HStack {
                    // Back button
                    if showBackButton {
                        Button(action: onBack) {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 14, weight: .semibold))
                                Text("Back")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                            }
                            .foregroundColor(.secondary)
                        }
                    } else {
                        Spacer().frame(width: 60)
                    }
                    
                    Spacer()
                    
                    // Continue button
                    Button(action: onContinue) {
                        HStack(spacing: 4) {
                            Text(continueText)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundStyle(
                            canContinue
                                ? AnyShapeStyle(LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing))
                                : AnyShapeStyle(Color.gray.opacity(0.5))
                        )
                    }
                    .disabled(!canContinue)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                
                // Progress Bar
                OnboardingProgressBar(
                    currentStep: currentStep,
                    totalSteps: totalSteps,
                    stepName: ""
                )
                .padding(.top, 4)
                
                // Scrollable content area - adjusts for keyboard
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        // Question header
                        OnboardingQuestionHeader(
                            question: title,
                            subtitle: subtitle
                        )
                        .padding(.top, 24)
                        .padding(.bottom, 20)
                        
                        // Main content
                        content
                        
                        // Help text if provided
                        if let helpText = helpText, !keyboardUp {
                            Text(helpText)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                                .padding(.top, 16)
                        }
                        
                        // Bottom padding - extra space for keyboard
                        Spacer().frame(height: keyboardUp ? keyboardObserver.keyboardHeight + 20 : 40)
                    }
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
    }
}


struct GenderButton: View {
    @Environment(\.colorScheme) var colorScheme
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    private let selectionFeedback = UISelectionFeedbackGenerator()
    
    var color: Color {
        switch title {
        case "Male": return .blue
        case "Female": return .pink
        default: return .purple
        }
    }
    
    var body: some View {
        Button(action: {
            selectionFeedback.selectionChanged()
            action()
        }) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(isSelected ? .white : .primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(isSelected 
                                ? LinearGradient(
                                    colors: [color, color.opacity(0.8)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                                : LinearGradient(
                                    colors: colorScheme == .dark 
                                        ? [Color(white: 0.12), Color(white: 0.12)]
                                        : [Color.white, Color.white],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        
                        // Enhanced shadow for floating effect
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.clear)
                            .shadow(
                                color: colorScheme == .dark ? Color.black.opacity(0.4) : Color.black.opacity(0.08),
                                radius: isSelected ? 12 : 8,
                                x: 0,
                                y: isSelected ? 6 : 3
                            )
                            .shadow(
                                color: isSelected ? color.opacity(0.3) : Color.clear,
                                radius: 15,
                                x: 0,
                                y: 4
                            )
                    }
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            LinearGradient(
                                colors: isSelected 
                                    ? [Color.white.opacity(0.3), Color.clear]
                                    : colorScheme == .dark
                                    ? [Color.white.opacity(0.1), Color.clear]
                                    : [Color.gray.opacity(0.15), Color.clear],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(.plain)
        .scaleEffect(isSelected ? 1.03 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }
}


struct DaySelectorButton: View {
    let day: Int
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text("\(day)")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(isSelected ? .white : .primary)
                .frame(width: 40, height: 40)
                .background(
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: isSelected ? [.blue, .purple.opacity(0.8)] : [Color(.systemBackground), Color(.systemBackground)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: isSelected ? Color.blue.opacity(0.3) : Color.black.opacity(0.05), radius: isSelected ? 4 : 2, x: 0, y: isSelected ? 2 : 1)
                )
                .overlay(
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: isSelected ? [Color.clear, Color.clear] : [Color.blue.opacity(0.2), Color.purple.opacity(0.15)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: isSelected ? 0 : 1
                        )
                )
        }
        .scaleEffect(isSelected ? 1.1 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }
}

// MARK: - Large Goal Card
struct GoalCardLarge: View {
    let title: String
    let emoji: String
    let subtitle: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Text(emoji)
                    .font(.system(size: 44))
                
                Text(title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(isSelected ? .white : .primary)
                    .lineLimit(1)
                
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundColor(isSelected ? .white.opacity(0.85) : .secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 130)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(isSelected ?
                          LinearGradient(colors: [.blue, .purple.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing) :
                          LinearGradient(colors: [Color(.systemBackground), Color(.systemBackground)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .shadow(color: isSelected ? .blue.opacity(0.35) : .black.opacity(0.06), radius: isSelected ? 12 : 6, x: 0, y: isSelected ? 6 : 3)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(isSelected ? Color.clear : Color(.systemGray4), lineWidth: 1)
            )
            .overlay(
                Group {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundColor(.white)
                            .padding(10)
                    }
                },
                alignment: .topTrailing
            )
        }
        .scaleEffect(isSelected ? 1.02 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }
}

// MARK: - Large Experience Card
struct ExperienceCardLarge: View {
    let title: String
    let emoji: String
    let subtitle: String
    let detail: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                // Emoji with background circle
                ZStack {
                    Circle()
                        .fill(isSelected ? Color.white.opacity(0.2) : Color.blue.opacity(0.1))
                        .frame(width: 56, height: 56)
                    
                    Text(emoji)
                        .font(.system(size: 28))
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(isSelected ? .white : .primary)
                    
                    Text(subtitle)
                        .font(.system(size: 14))
                        .foregroundColor(isSelected ? .white.opacity(0.85) : .secondary)
                    
                    Text(detail)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(isSelected ? .white.opacity(0.7) : .blue.opacity(0.7))
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 26))
                        .foregroundColor(.white)
                }
            }
            .padding(16)
            .frame(height: 90)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(isSelected ?
                          LinearGradient(colors: [.blue, .purple.opacity(0.8)], startPoint: .leading, endPoint: .trailing) :
                          LinearGradient(colors: [Color(.systemBackground), Color(.systemBackground)], startPoint: .leading, endPoint: .trailing)
                    )
                    .shadow(color: isSelected ? .blue.opacity(0.35) : .black.opacity(0.06), radius: isSelected ? 12 : 6, x: 0, y: isSelected ? 6 : 3)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(isSelected ? Color.clear : Color(.systemGray4), lineWidth: 1)
            )
        }
        .scaleEffect(isSelected ? 1.01 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }
}

// MARK: - Large Equipment Card
struct EquipmentCardLarge: View {
    let title: String
    let emoji: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Text(emoji)
                    .font(.system(size: 36))
                
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(isSelected ? .white : .primary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 100)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(
                        LinearGradient(
                            colors: isSelected ? [Color.blue, Color.purple.opacity(0.8)] : [Color(.systemBackground), Color(.systemBackground)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: isSelected ? Color.blue.opacity(0.35) : Color.black.opacity(0.06), radius: isSelected ? 12 : 6, x: 0, y: isSelected ? 6 : 3)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(isSelected ? Color.clear : Color(.systemGray4), lineWidth: 1)
            )
            .overlay(
                Group {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.white)
                            .padding(8)
                    }
                },
                alignment: .topTrailing
            )
        }
        .scaleEffect(isSelected ? 1.03 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isSelected)
    }
}

// MARK: - Equipment Card with SF Symbol (UX Audit Fix #5)
struct EquipmentCardWithIcon: View {
    let title: String
    let iconName: String
    let subtitle: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: iconName)
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(
                        isSelected ? 
                        AnyShapeStyle(Color.white) : 
                        AnyShapeStyle(LinearGradient(colors: [.blue, .purple.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    )
                    .frame(height: 36)
                
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(isSelected ? .white : .primary)
                    .lineLimit(1)
                
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 110)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(
                        LinearGradient(
                            colors: isSelected ? [Color.blue, Color.purple.opacity(0.8)] : [Color(.systemBackground), Color(.systemBackground)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: isSelected ? Color.blue.opacity(0.35) : Color.black.opacity(0.06), radius: isSelected ? 12 : 6, x: 0, y: isSelected ? 6 : 3)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(isSelected ? Color.clear : Color(.systemGray4), lineWidth: 1)
            )
            .overlay(
                Group {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.white)
                            .padding(8)
                    }
                },
                alignment: .topTrailing
            )
        }
        .scaleEffect(isSelected ? 1.03 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isSelected)
    }
}

// MARK: - Workout Location Card
struct WorkoutLocationCard: View {
    let environment: WorkoutEnvironmentService.WorkoutEnvironment
    let emoji: String
    let subtitle: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                // Emoji icon
                Text(emoji)
                    .font(.system(size: 32))
                    .frame(width: 56, height: 56)
                    .background(
                        Circle()
                            .fill(isSelected ? 
                                  LinearGradient(colors: [.blue, .purple.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing) :
                                  LinearGradient(colors: [Color(.systemGray5), Color(.systemGray5)], startPoint: .topLeading, endPoint: .bottomTrailing)
                            )
                    )
                
                // Text content
                VStack(alignment: .leading, spacing: 4) {
                    Text(environment.displayName)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(isSelected ? .white : .primary)
                    
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                }
                
                Spacer()
                
                // Checkmark
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.white)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            colors: isSelected ? [Color.blue, Color.purple.opacity(0.8)] : [Color(.systemBackground), Color(.systemBackground)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: isSelected ? Color.blue.opacity(0.35) : Color.black.opacity(0.06), radius: isSelected ? 12 : 6, x: 0, y: isSelected ? 6 : 3)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? Color.clear : Color(.systemGray4), lineWidth: 1)
            )
        }
        .scaleEffect(isSelected ? 1.02 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isSelected)
    }
}

// MARK: - Strength Level Card
struct StrengthLevelCard: View {
    let level: StrengthProfileRecommendationEngine.StrengthLevel
    let emoji: String
    let title: String
    let subtitle: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                // Emoji icon with gradient background
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: isSelected ? [.orange, .red.opacity(0.8)] : [Color(.systemGray5), Color(.systemGray5)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 52, height: 52)
                    
                    Text(emoji)
                        .font(.system(size: 26))
                }
                
                // Text content
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(isSelected ? .white : .primary)
                    
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                }
                
                Spacer()
                
                // Checkmark or strength indicator
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.white)
                } else {
                    // Strength dots indicator
                    HStack(spacing: 4) {
                        ForEach(0..<5, id: \.self) { index in
                            Circle()
                                .fill(index < strengthDots ? Color.orange.opacity(0.6) : Color(.systemGray4))
                                .frame(width: 6, height: 6)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            colors: isSelected ? [Color.orange, Color.red.opacity(0.85)] : [Color(.systemBackground), Color(.systemBackground)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: isSelected ? Color.orange.opacity(0.4) : Color.black.opacity(0.05), radius: isSelected ? 10 : 4, x: 0, y: isSelected ? 4 : 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? Color.clear : Color(.systemGray4), lineWidth: 1)
            )
        }
        .scaleEffect(isSelected ? 1.02 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isSelected)
    }
    
    private var strengthDots: Int {
        switch level {
        case .veryLight: return 1
        case .light: return 2
        case .moderate: return 3
        case .strong: return 4
        case .veryStrong: return 5
        }
    }
}

// MARK: - Large Day Selector Button
struct DaySelectorButtonLarge: View {
    @Environment(\.colorScheme) var colorScheme
    let day: Int
    let isSelected: Bool
    let action: () -> Void
    
    private let selectionFeedback = UISelectionFeedbackGenerator()
    
    var body: some View {
        Button(action: {
            selectionFeedback.selectionChanged()
            action()
        }) {
            ZStack {
                // Soft glow when selected
                if isSelected {
                    Circle()
                        .fill(Color.blue.opacity(0.4))
                        .frame(width: 52, height: 52)
                        .blur(radius: 10)
                }
                
                Text("\(day)")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(isSelected ? .white : .primary)
                    .frame(width: 44, height: 44)
                    .background(
                        Circle()
                            .fill(
                                isSelected
                                    ? LinearGradient(colors: [.blue, .purple.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing)
                                    : LinearGradient(colors: [colorScheme == .dark ? Color(red: 0.12, green: 0.12, blue: 0.14) : Color.white, colorScheme == .dark ? Color(red: 0.12, green: 0.12, blue: 0.14) : Color.white], startPoint: .topLeading, endPoint: .bottomTrailing)
                            )
                    )
                    .overlay(
                        Circle()
                            .stroke(isSelected ? Color.clear : Color.gray.opacity(0.3), lineWidth: 1)
                    )
                    .shadow(color: isSelected ? Color.blue.opacity(0.4) : .black.opacity(colorScheme == .dark ? 0.3 : 0.08), radius: isSelected ? 10 : 4, x: 0, y: isSelected ? 5 : 2)
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isSelected ? 1.15 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }
}

struct OnboardingGoalCard: View {
    let title: String
    let emoji: String
    let subtitle: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(emoji)
                    .font(.system(size: 28))
                
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(isSelected ? .white : .primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                
                Text(subtitle)
                    .font(.caption2)
                    .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isSelected ?
                          LinearGradient(colors: [.blue, .purple.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing) :
                          LinearGradient(colors: [Color(.systemBackground), Color(.systemBackground)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .shadow(color: isSelected ? .blue.opacity(0.3) : .black.opacity(0.05), radius: isSelected ? 6 : 3, x: 0, y: isSelected ? 3 : 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? Color.clear : Color(.systemGray4), lineWidth: 1)
            )
        }
        .scaleEffect(isSelected ? 1.02 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }
}

struct OnboardingExperienceCard: View {
    let title: String
    let emoji: String
    let subtitle: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(emoji)
                    .font(.title2)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(isSelected ? .white : .primary)
                    
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.white)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isSelected ?
                          LinearGradient(colors: [.blue, .purple.opacity(0.8)], startPoint: .leading, endPoint: .trailing) :
                          LinearGradient(colors: [Color(.systemBackground), Color(.systemBackground)], startPoint: .leading, endPoint: .trailing)
                    )
                    .shadow(color: isSelected ? .blue.opacity(0.3) : .black.opacity(0.05), radius: isSelected ? 6 : 3, x: 0, y: isSelected ? 3 : 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? Color.clear : Color(.systemGray4), lineWidth: 1)
            )
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }
}

struct OnboardingEquipmentChip: View {
    let title: String
    let emoji: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(emoji)
                    .font(.title3)
                
                Text(title)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(isSelected ? .white : .primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        LinearGradient(
                            colors: isSelected ? [Color.blue, Color.purple.opacity(0.8)] : [Color(.systemBackground), Color(.systemBackground)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: isSelected ? Color.blue.opacity(0.3) : Color.black.opacity(0.05), radius: isSelected ? 6 : 3, x: 0, y: isSelected ? 3 : 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        LinearGradient(
                            colors: isSelected ? [Color.clear, Color.clear] : [Color.blue.opacity(0.2), Color.purple.opacity(0.15)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: isSelected ? 0 : 1
                    )
            )
        }
        .scaleEffect(isSelected ? 1.03 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isSelected)
    }
}

struct SummaryRow: View {
    let icon: String
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.blue, Color.purple.opacity(0.8)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 24)
            
            Text(label)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text(value)
                .fontWeight(.semibold)
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.blue, Color.purple.opacity(0.8)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
        }
    }
}

// MARK: - Confirmation List Section
struct ConfirmationListSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .padding(.leading, 16)
                .padding(.bottom, 6)
                .padding(.top, 18)
            
            VStack(spacing: 0) {
                content
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(.systemBackground))
                    .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color(.systemGray5), lineWidth: 0.5)
            )
        }
    }
}

// MARK: - Confirmation List Row
struct ConfirmationListRow: View {
    let icon: String
    let label: String
    let value: String
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.blue, Color.purple.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 22)
                
                Text(label)
                    .font(.system(size: 15))
                    .foregroundColor(.primary)
                
                Spacer()
                
                Text(value)
                    .font(.system(size: 15))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary.opacity(0.5))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(Color(.systemBackground))
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Compact Confirmation Card
struct CompactConfirmationCard: View {
    let title: String
    let items: [(icon: String, value: String)]
    let onEdit: () -> Void
    
    var body: some View {
        Button(action: onEdit) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(title)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("Edit")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(.blue)
                }
                
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(spacing: 8) {
                        Image(systemName: item.icon)
                            .font(.system(size: 12))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color.blue, Color.purple.opacity(0.8)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 16)
                        
                        Text(item.value)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemBackground))
                    .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.blue.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Confirmation Section
struct ConfirmationSection<Content: View>: View {
    let title: String
    let onEdit: () -> Void
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Title row with Edit button
            HStack {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button(action: onEdit) {
                    Text("Edit")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.blue)
                }
            }
            .padding(.horizontal, 4)
            
            // Content box - tappable
            Button(action: onEdit) {
                VStack(spacing: 0) {
                    content
                }
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(.systemBackground))
                        .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 4)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.blue.opacity(0.1), lineWidth: 1)
                )
            }
            .buttonStyle(PlainButtonStyle())
        }
    }
}

// MARK: - Confirmation Row (non-editable display)
struct ConfirmationRow: View {
    let icon: String
    let label: String
    let value: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.blue, Color.purple.opacity(0.8)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 28)
            
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

// MARK: - Height Input Field (shows clean format like 6'8")
struct HeightInputField: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var heightDigits: String
    var focusedField: FocusState<NewOnboardingView.FocusedField?>.Binding
    @State private var showCursor = true
    
    private var isFocused: Bool {
        focusedField.wrappedValue == .height
    }
    
    private var isValid: Bool {
        !heightDigits.isEmpty
    }
    
    // Format display string from digits - clean format
    private var displayText: String {
        let digits = heightDigits.filter { $0.isNumber }
        
        if digits.isEmpty {
            return ""  // Show placeholder instead
        }
        
        let feet = String(digits.prefix(1))
        let inchDigits = String(digits.dropFirst().prefix(2))
        
        if inchDigits.isEmpty {
            return "\(feet)'"
        } else {
            return "\(feet)'\(inchDigits)\""
        }
    }
    
    private var placeholder: String {
        return "5'10\""
    }
    
    var body: some View {
        // EXACTLY matching OnboardingTextField structure
        HStack(spacing: 16) {
            // Icon - same as OnboardingTextField
            Image(systemName: "ruler")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(
                    LinearGradient(
                        colors: isValid ? [Color.blue, Color.cyan] : [Color.gray.opacity(0.6), Color.gray.opacity(0.5)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 26)
                .allowsHitTesting(false)
            
            // TextField - exactly like OnboardingTextField
            TextField(placeholder, text: $heightDigits)
                .keyboardType(.numberPad)
                .focused(focusedField, equals: .height)
            
            // Checkmark when valid - same as OnboardingTextField
            if isValid {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.blue)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .font(.system(size: 16, weight: .medium))
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(colorScheme == .dark ? Color(white: 0.12) : Color.white)
                
                RoundedRectangle(cornerRadius: 16)
                    .fill(colorScheme == .dark ? Color(white: 0.12) : Color.white)
                    .shadow(
                        color: colorScheme == .dark ? Color.black.opacity(0.4) : Color.black.opacity(0.08),
                        radius: isFocused ? 12 : 8,
                        x: 0,
                        y: isFocused ? 6 : 3
                    )
                    .shadow(
                        color: isValid ? Color.blue.opacity(0.2) : Color.clear,
                        radius: 15,
                        x: 0,
                        y: 4
                    )
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    LinearGradient(
                        colors: isValid 
                            ? [Color.blue.opacity(0.6), Color.cyan.opacity(0.5)]
                            : isFocused
                            ? [Color.blue.opacity(0.4), Color.cyan.opacity(0.3)]
                            : colorScheme == .dark
                            ? [Color.white.opacity(0.1), Color.clear]
                            : [Color.gray.opacity(0.15), Color.clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: isFocused || isValid ? 2 : 1
                )
        )
        .animation(.easeInOut(duration: 0.25), value: isValid)
        .animation(.easeInOut(duration: 0.2), value: isFocused)
        .onTapGesture {
            focusedField.wrappedValue = .height
        }
        .onAppear {
            Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
                showCursor.toggle()
            }
        }
        .onChange(of: heightDigits) { _, newValue in
            // Only keep digits, max 3 (1 for feet, 2 for inches)
            let digits = newValue.filter { $0.isNumber }
            
            // Smart limiting based on inch value
            if digits.count > 1 {
                let firstInch = digits.dropFirst().first
                if let first = firstInch, first != "0" && first != "1" {
                    // For inches 2-9, only allow 2 total digits
                    if digits.count > 2 {
                        heightDigits = String(digits.prefix(2))
                        return
                    }
                } else {
                    // For inches starting with 0 or 1, allow 3 digits but cap at 11
                    if digits.count >= 3 {
                        let inchValue = Int(String(digits.dropFirst().prefix(2))) ?? 0
                        if inchValue > 11 {
                            // Cap at 11
                            heightDigits = String(digits.prefix(1)) + "11"
                            return
                        }
                    }
                }
            }
            
            // Limit to 3 digits max
            if digits.count > 3 {
                heightDigits = String(digits.prefix(3))
            } else if digits != newValue {
                heightDigits = digits
            }
        }
        .fixedSize()
    }
}

// MARK: - Inline Unit Toggle (smaller, for inside fields)
struct InlineUnitToggle: View {
    let options: [String]
    let selected: String
    let onSelect: (String) -> Void
    
    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { option in
                Text(option)
                    .font(.caption2)
                    .fontWeight(selected == option ? .bold : .medium)
                    .foregroundColor(selected == option ? .white : .secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(selected == option ?
                                  LinearGradient(colors: [.blue, .purple.opacity(0.8)], startPoint: .leading, endPoint: .trailing) :
                                  LinearGradient(colors: [Color.clear, Color.clear], startPoint: .leading, endPoint: .trailing)
                            )
                    )
                    .contentShape(Capsule())
                    .onTapGesture {
                        onSelect(option)
                    }
            }
        }
        .background(
            Capsule()
                .fill(Color(.systemGray6))
        )
    }
}

// MARK: - Limitation Card Wide (Full Width) for Onboarding
struct LimitationCardOnboardingWide: View {
    @Environment(\.colorScheme) var colorScheme
    let area: AffectedArea
    let isSelected: Bool
    let accommodation: AccommodationLevel
    let action: () -> Void
    let onAccommodationChange: (AccommodationLevel) -> Void
    
    private let selectionFeedback = UISelectionFeedbackGenerator()
    
    var body: some View {
        VStack(spacing: 0) {
            // Main card - horizontal layout
            Button(action: {
                selectionFeedback.selectionChanged()
                action()
            }) {
                HStack(spacing: 14) {
                    // Icon with glow
                    ZStack {
                        if isSelected {
                            Circle()
                                .fill(area.color.opacity(0.4))
                                .frame(width: 52, height: 52)
                                .blur(radius: 10)
                        }
                        
                        Circle()
                            .fill(
                                isSelected
                                    ? LinearGradient(colors: [area.color, area.color.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)
                                    : LinearGradient(colors: [Color.gray.opacity(0.15), Color.gray.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing)
                            )
                            .frame(width: 44, height: 44)
                        
                        Image(systemName: area.icon)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(isSelected ? .white : .gray)
                    }
                    
                    // Title and status
                    VStack(alignment: .leading, spacing: 4) {
                        Text(area.rawValue)
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundColor(isSelected ? area.color : .primary)
                        
                        if isSelected {
                            HStack(spacing: 4) {
                                Image(systemName: accommodation.icon)
                                    .font(.system(size: 11))
                                Text(accommodation.displayName)
                                    .font(.caption)
                                    .fontWeight(.medium)
                            }
                            .foregroundColor(accommodation.color)
                        } else {
                            Text("Tap to select")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    // Selection indicator
                    ZStack {
                        Circle()
                            .stroke(isSelected ? area.color : Color.gray.opacity(0.3), lineWidth: 2)
                            .frame(width: 24, height: 24)
                        
                        if isSelected {
                            Circle()
                                .fill(area.color)
                                .frame(width: 16, height: 16)
                        }
                    }
                }
                .padding(16)
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(colorScheme == .dark ? Color(red: 0.12, green: 0.12, blue: 0.14) : Color.white)
                        
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(
                                LinearGradient(
                                    colors: colorScheme == .dark
                                        ? [Color.white.opacity(0.1), Color.clear]
                                        : [Color.white.opacity(0.8), Color.clear],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 1
                            )
                    }
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(isSelected ? area.color.opacity(0.6) : Color.clear, lineWidth: 2)
                )
                .shadow(color: isSelected ? area.color.opacity(0.3) : .black.opacity(colorScheme == .dark ? 0.3 : 0.08), radius: isSelected ? 12 : 6, x: 0, y: isSelected ? 6 : 3)
            }
            .buttonStyle(.plain)
            
            // Expanded accommodation options
            if isSelected {
                VStack(spacing: 8) {
                    ForEach(AccommodationLevel.allCases) { level in
                        Button(action: {
                            selectionFeedback.selectionChanged()
                            onAccommodationChange(level)
                        }) {
                            HStack(spacing: 12) {
                                Image(systemName: level.icon)
                                    .font(.system(size: 16))
                                    .foregroundColor(level.color)
                                    .frame(width: 24)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(level.displayName)
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(accommodation == level ? level.color : .primary)
                                    
                                    Text(level.description)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                                
                                Spacer()
                                
                                if accommodation == level {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 20))
                                        .foregroundColor(level.color)
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(accommodation == level ? level.color.opacity(0.15) : Color.clear)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(accommodation == level ? level.color.opacity(0.4) : Color.gray.opacity(0.2), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 12)
                .padding(.horizontal, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }
}

// MARK: - Limitation Card for Onboarding (Grid Layout - Legacy)
struct LimitationCardOnboarding: View {
    @Environment(\.colorScheme) var colorScheme
    let area: AffectedArea
    let isSelected: Bool
    let accommodation: AccommodationLevel
    let action: () -> Void
    let onAccommodationChange: (AccommodationLevel) -> Void
    
    @State private var showingOptions = false
    private let selectionFeedback = UISelectionFeedbackGenerator()
    
    var body: some View {
        VStack(spacing: 0) {
            // Main card button
            Button(action: {
                selectionFeedback.selectionChanged()
                if isSelected {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        showingOptions.toggle()
                    }
                } else {
                    action()
                    showingOptions = true
                }
            }) {
                VStack(spacing: 6) {
                    // Icon with glow effect (matching auto-gen style)
                    ZStack {
                        // Soft glow when selected
                        if isSelected {
                            Circle()
                                .fill(area.color.opacity(0.4))
                                .frame(width: 50, height: 50)
                                .blur(radius: 10)
                        }
                        
                        Circle()
                            .fill(
                                isSelected
                                    ? LinearGradient(colors: [area.color, area.color.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)
                                    : LinearGradient(colors: [Color.gray.opacity(0.15), Color.gray.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing)
                            )
                            .frame(width: 44, height: 44)
                        
                        Image(systemName: area.icon)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(isSelected ? .white : .gray)
                    }
                    
                    Text(area.rawValue)
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(isSelected ? area.color : .primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    
                    // Show selected accommodation level
                    if isSelected {
                        HStack(spacing: 4) {
                            Image(systemName: accommodation.icon)
                                .font(.system(size: 9))
                            Text(accommodation.displayName)
                                .font(.system(size: 9, weight: .medium))
                        }
                        .foregroundColor(accommodation.color)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(accommodation.color.opacity(0.15))
                        )
                    } else {
                        Color.clear.frame(height: 18)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 110)
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(colorScheme == .dark ? Color(red: 0.12, green: 0.12, blue: 0.14) : Color.white)
                        
                        // Inner highlight for depth
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(
                                LinearGradient(
                                    colors: colorScheme == .dark
                                        ? [Color.white.opacity(0.1), Color.clear]
                                        : [Color.white.opacity(0.8), Color.clear],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 1
                            )
                    }
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(isSelected ? area.color.opacity(0.6) : Color.clear, lineWidth: 2)
                )
                // Floating shadow with color glow when selected
                .shadow(color: isSelected ? area.color.opacity(0.4) : .black.opacity(colorScheme == .dark ? 0.3 : 0.08), radius: isSelected ? 12 : 6, x: 0, y: isSelected ? 6 : 3)
                .overlay(
                    Group {
                        if isSelected {
                            Image(systemName: showingOptions ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                                .font(.system(size: 14))
                                .foregroundColor(area.color)
                                .padding(6)
                        }
                    },
                    alignment: .topTrailing
                )
            }
            .buttonStyle(.plain)
            .scaleEffect(isSelected ? 1.03 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
            
            // Expandable accommodation options
            if isSelected && showingOptions {
                VStack(spacing: 6) {
                    ForEach(AccommodationLevel.allCases) { level in
                        AccommodationOptionRow(
                            level: level,
                            isSelected: accommodation == level,
                            onSelect: {
                                onAccommodationChange(level)
                                withAnimation {
                                    showingOptions = false
                                }
                            }
                        )
                    }
                }
                .padding(.top, 8)
                .padding(.horizontal, 4)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
    }
}

// MARK: - Accommodation Option Row
struct AccommodationOptionRow: View {
    let level: AccommodationLevel
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                // Icon
                Image(systemName: level.icon)
                    .font(.system(size: 14))
                    .foregroundColor(isSelected ? .white : level.color)
                    .frame(width: 24, height: 24)
                    .background(
                        Circle()
                            .fill(isSelected ? level.color : level.color.opacity(0.15))
                    )
                
                // Text
                VStack(alignment: .leading, spacing: 1) {
                    Text(level.displayName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(isSelected ? level.color : .primary)
                    
                    Text(level.description)
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                // Checkmark
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(level.color)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? level.color.opacity(0.1) : Color(.systemGray6).opacity(0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? level.color.opacity(0.5) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NewOnboardingView()
        .environmentObject(UserManager())
}

