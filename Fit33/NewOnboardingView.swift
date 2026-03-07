import SwiftUI
import Combine
import PhotosUI
import AuthenticationServices
import Contacts

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

// MARK: - Onboarding Session Manager
// Tracks onboarding session for debugging
class OnboardingSessionManager: ObservableObject {
    static let shared = OnboardingSessionManager()
    
    @Published var currentSessionId: String?
    @Published var sessionStartTime: Date?
    
    private init() {}
    
    func startNewSession() {
        currentSessionId = UUID().uuidString
        sessionStartTime = Date()
        print("📱 [ONBOARDING] New session started: \(currentSessionId ?? "nil")")
    }
    
    func endSession() {
        if let startTime = sessionStartTime {
            let duration = Date().timeIntervalSince(startTime)
            print("📱 [ONBOARDING] Session ended. Duration: \(Int(duration))s")
        }
        currentSessionId = nil
        sessionStartTime = nil
    }
    
    var sessionDuration: TimeInterval {
        guard let startTime = sessionStartTime else { return 0 }
        return Date().timeIntervalSince(startTime)
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
    @State private var isOnConfirmPasswordStep = false  // Track if user is on confirm password step
    @State private var hasStartedAuth = false  // Track if user has started interacting with auth
    @State private var name = ""
    @State private var errorMessage = ""
    @State private var showError = false
    @State private var emailAlreadyExists = false
    @State private var acceptedTerms = false
    @State private var showTermsSheet = false
    @State private var passwordResetSent = false
    
    // Phone number (for 2FA / account security)
    @State private var phoneNumber = ""
    @State private var phoneNumberError = ""
    @State private var selectedCountryCode: CountryCode = CountryCode.fromLocale()  // Auto-detect from device locale
    @State private var verificationCode = ""
    @State private var isVerificationCodeSent = false
    @State private var isPhoneVerified = false
    @State private var verificationError = ""
    @State private var isVerifyingCode = false
    @State private var canResendCode = false
    @State private var resendCountdown = 0
    @State private var sendCodeCountdown = 0  // Countdown before user can send again
    @State private var sendCodeTimer: Timer? = nil
    @State private var phoneVerificationAttempts = 0  // Track send code attempts
    @State private var hasSkippedPhoneVerification = false  // Track if user skipped after max attempts
    @StateObject private var phoneVerificationService = PhoneVerificationService.shared
    
    // Constants for phone verification limits
    private let maxPhoneVerificationAttempts = 3
    
    // Username fields
    @State private var username = ""
    @State private var isCheckingUsername = false
    @State private var usernameError = ""
    @State private var isUsernameAvailable = false
    
    // Social auth
    @StateObject private var socialAuthService = SocialAuthService.shared
    @State private var showGoogleSignIn = false
    @State private var detectedAuthProvider = ""  // "apple", "google", "email", "none"
    @State private var showAuthProviderHint = false
    @State private var authProviderHintMessage = ""
    
    // Profile fields
    @State private var birthday = ""  // Formatted with slashes: MM/DD/YYYY
    
    // Format birthday string with auto-inserted slashes (locale-aware: MM/DD/YYYY or DD/MM/YYYY)
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
    
    // Returns true if locale uses MM/DD/YYYY, false for DD/MM/YYYY
    private var usesMonthFirstDate: Bool {
        UnitSettingsManager.localeUsesMonthFirstDate
    }
    
    // Placeholder text based on locale
    private var birthdayPlaceholder: String {
        usesMonthFirstDate ? "MM/DD/YYYY" : "DD/MM/YYYY"
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
    @State private var confirmedAccommodations: Set<AffectedArea> = []  // Track which have been explicitly confirmed
    
    // Profile photo (optional onboarding step)
    @State private var profilePhotoImage: UIImage? = nil
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var showingPhotoOptions = false
    @State private var showingPhotoPicker = false
    @State private var showingCamera = false
    @State private var isUploadingPhoto = false
    
    // Contacts permission (optional onboarding step)
    @State private var contactsPermissionGranted = false
    @State private var contactsPermissionRequested = false
    @StateObject private var contactsService = ContactsService.shared
    
    // Add friends from contacts (onboarding step)
    @State private var friendSearchText = ""
    @State private var sentFriendRequests: Set<UUID> = []  // Track requests sent during onboarding
    @State private var loadingFriendRequests: Set<UUID> = []  // Track which buttons are currently loading
    @State private var failedFriendRequests: Set<UUID> = []  // Track failed requests for retry UI
    @State private var isLoadingFriends = false
    
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
        case email, password, confirmPassword, name, phoneNumber, verificationCode, username, birthday, height, weight
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
        case .username: return "Profile"
        case .phoneNumber: return "Security"
        case .basics: return "About You"
        case .body: return "Measurements"
        case .goal: return "Goals"
        case .experience: return "Experience"
        case .strengthAssessment: return "Strength"
        case .workoutLocation: return "Location"
        case .equipment: return "Equipment"
        case .limitations: return "Health"
        case .schedule: return "Schedule"
        case .profilePhoto: return "Photo"
        case .contacts: return "Contacts"
        case .addFriends: return "Friends"
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
        case username = 1    // Choose username (sign up only) - comes first to reduce spam feel
        case phoneNumber = 2  // Phone number for 2FA/account security (sign up only)
        case basics = 3      // Birthday + Gender
        case body = 4        // Height + Weight
        case goal = 5
        case experience = 6
        case strengthAssessment = 7  // How heavy can you lift?
        case workoutLocation = 8     // Where do you workout?
        case equipment = 9
        case limitations = 10  // Injuries/limitations
        case schedule = 11
        case profilePhoto = 12  // Optional profile photo upload
        case contacts = 13   // Contacts permission for friend features
        case addFriends = 14 // Add friends from contacts who have accounts
        case confirmation = 15  // Review all selections before creating account
        case complete = 16
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
            if isOnConfirmPasswordStep {
                // On confirm password step: require passwords match and terms accepted
                return !email.isEmpty && email.contains("@") && isPasswordValid && passwordsMatch && acceptedTerms
            } else {
                // On first password step: only require valid email and password
                return !email.isEmpty && email.contains("@") && isPasswordValid
            }
        } else {
            return !email.isEmpty && email.contains("@") && !password.isEmpty
        }
    }
    
    // Username validation
    private var isUsernameValid: Bool {
        let cleanUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanUsername.count >= 3 && cleanUsername.count <= 30 else { return false }
        let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
        return cleanUsername.unicodeScalars.allSatisfy { allowedCharacters.contains($0) }
    }
    
    // Check if user needs to manually enter their name (social auth didn't provide it)
    private var needsNameInput: Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        // Need input if name is empty
        if trimmedName.isEmpty { return true }
        // Need input if name is a generic fallback (Apple, Google, or other OAuth)
        if trimmedName == "Apple User" { return true }
        if trimmedName == "User" { return true }
        if trimmedName == "Google User" { return true }
        if trimmedName == "Facebook User" { return true }
        
        // If name contains a space, it's likely a full name from OAuth (e.g., "Joseph Reed") - accept it
        if trimmedName.contains(" ") {
            return false
        }
        
        // Check if name looks like an email prefix (e.g., "joe123" or "joereed")
        // But NOT if it starts with a capital letter (like a proper first name "Joseph")
        let firstChar = trimmedName.first
        let startsWithCapital = firstChar?.isUppercase == true
        
        // If name starts with capital letter, it's likely a proper name from OAuth - accept it
        if startsWithCapital {
            return false
        }
        
        // If all lowercase and contains numbers, likely an email prefix
        if trimmedName == trimmedName.lowercased() && trimmedName.rangeOfCharacter(from: .decimalDigits) != nil {
            return true
        }
        
        // If all lowercase and more than 8 chars without spaces, might be email prefix
        if trimmedName.count > 8 && trimmedName == trimmedName.lowercased() {
            return true
        }
        
        return false
    }
        
    // Navigate to step and set appropriate focus
    private func navigateTo(_ step: OnboardingStep, animated: Bool = true) {
        print("🔄 [NAV] navigateTo(\(step)) called, animated: \(animated), isEditingFromConfirmation: \(isEditingFromConfirmation)")
        print("   └─ Previous step: \(currentStep)")
        let previousStep = currentStep
        
        // Map onboarding step to screen ID
        let screenMap: [OnboardingStep: SessionLogManager.Screen] = [
            .auth: .authScreen,
            .phoneNumber: .authScreen, // Use auth screen for logging
            .username: .authScreen, // Use auth screen for logging
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
        
        // Log step completion to cloud (for debugging UK user issue)
        Task {
            // Log the previous step as completed
            if previousStep != step {
                await supabaseManager.logOnboardingEvent(
                    eventType: "step_completed",
                    stepName: "\(previousStep)",
                    eventData: [
                        "step_number": previousStep.rawValue,
                        "next_step": "\(step)",
                        "session_duration": OnboardingSessionManager.shared.sessionDuration
                    ]
                )
            }
            
            // Log the new step as started
            await supabaseManager.logOnboardingEvent(
                eventType: "step_started",
                stepName: "\(step)",
                eventData: [
                    "step_number": step.rawValue,
                    "previous_step": "\(previousStep)",
                    "is_editing": isEditingFromConfirmation
                ]
            )
        }
        
        // Change step - let view-level animations handle transitions
        print("🔄 [NAV] navigateTo(\(step)) called, animated: \(animated), isEditingFromConfirmation: \(isEditingFromConfirmation)")
        currentStep = step
        print("🔄 [NAV] currentStep now: \(currentStep)")
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
            
            // Auth step has its own layout when NOT in standard mode
            if currentStep == .auth && !hasStartedAuth {
                authStep
            }
            
            // Auth step in standard mode (with shared header and button bar)
            else if currentStep == .auth && hasStartedAuth {
                let keyboardUp = keyboardObserver.keyboardHeight > 0
                
                ZStack(alignment: .bottom) {
                    // Main content
                    VStack(spacing: 0) {
                        // Header
                        onboardingSharedHeader(compact: keyboardUp)
                        
                        // Content
                        ScrollView(showsIndicators: false) {
                            VStack(spacing: 0) {
                                authFormContent
                                    .padding(.top, 8)
                            }
                        }
                        .scrollDismissesKeyboard(.interactively)
                        
                        Spacer()
                    }
                    
                    // Shared button bar
                    VStack(spacing: 0) {
                        HStack(spacing: 12) {
                            // Back button logic for auth step
                            if isSignUp && isOnConfirmPasswordStep {
                                // If on confirm password, go back to first password
                                Button(action: {
                                    isOnConfirmPasswordStep = false
                                    confirmPassword = ""  // Clear only confirm password, keep first password
                                    // First password stays valid with all indicators lit
                                    // onChange handler will manage focus to keep keyboard up
                                }) {
                                    Image(systemName: "chevron.left")
                                        .font(.ds_labelLarge)
                                        .foregroundColor(.gray)
                                        .frame(width: 52, height: 52)
                                        .background(Circle().fill(Color(.systemGray6)))
                                        .overlay(Circle().stroke(Color.gray.opacity(0.3), lineWidth: 1.5))
                                }
                            } else {
                                // If on first password/email, go back to welcome screen
                                Button(action: {
                                    withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                                        hasStartedAuth = false
                                        focusedField = nil  // Dismiss keyboard
                                    }
                                }) {
                                    Image(systemName: "chevron.left")
                                        .font(.ds_labelLarge)
                                        .foregroundColor(.gray)
                                        .frame(width: 52, height: 52)
                                        .background(Circle().fill(Color(.systemGray6)))
                                        .overlay(Circle().stroke(Color.gray.opacity(0.3), lineWidth: 1.5))
                                }
                            }
                            
                            // Continue button
                            Button(action: { 
                                if isSignUp && !isOnConfirmPasswordStep && isPasswordValid {
                                    // Advance to confirm password step
                                    isOnConfirmPasswordStep = true
                                } else {
                                    handleAuth()
                                }
                            }) {
                                HStack(spacing: 8) {
                                    if supabaseManager.isLoading {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: isAuthFormValid ? .blue : .gray))
                                            .scaleEffect(0.9)
                                    }
                                    Text(isSignUp ? "Continue" : "Sign In")
                                        .font(.headline)
                                        .fontWeight(.semibold)
                                }
                                .foregroundStyle(
                                    isAuthFormValid
                                        ? AnyShapeStyle(LinearGradient(colors: [.blue, .blue, .cyan.opacity(0.8)], startPoint: .leading, endPoint: .trailing))
                                        : AnyShapeStyle(Color.gray)
                                )
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, Spacing.md)
                                .background(Capsule().fill(Color(.systemGray6)))
                                .overlay(
                                    Capsule()
                                        .stroke(
                                            isAuthFormValid
                                                ? AnyShapeStyle(LinearGradient(colors: [.blue, .blue, .cyan.opacity(0.8)], startPoint: .leading, endPoint: .trailing))
                                                : AnyShapeStyle(Color.gray.opacity(0.3)),
                                            lineWidth: 2
                                        )
                                )
                            }
                            .disabled(!isAuthFormValid || supabaseManager.isLoading)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, keyboardUp ? keyboardObserver.keyboardHeight + 10 : 50)
                    .animation(.easeOut(duration: 0.25), value: keyboardObserver.keyboardHeight)
                    .animation(nil, value: isOnConfirmPasswordStep)  // No animation on button bar for password step changes
                }
            }
            
            // Complete step has its own layout (celebration)
            else if currentStep == .complete {
                completeStep
            }
            
            // Main onboarding flow (shared header + sliding content + floating button)
            else if currentStep != .limitations && currentStep != .confirmation {
                let keyboardUp = keyboardObserver.keyboardHeight > 0
                
                ZStack(alignment: .bottom) {
                    // Main content
                    VStack(spacing: 0) {
                        // Header
                        onboardingSharedHeader(compact: keyboardUp)
                            .animation(nil, value: currentStep)  // Don't animate header on step changes
                        
                        // Content - use opacity transitions to avoid layout bouncing
                        ZStack {
                            if currentStep == .phoneNumber {
                                let _ = print("🎯 [ZSTACK] Rendering phoneNumberStepContent for currentStep: \(currentStep)")
                                phoneNumberStepContent
                                    .transition(.opacity)
                            }
                            if currentStep == .username { usernameStepContent.transition(.opacity) }
                            if currentStep == .basics { basicsStepContent.transition(.opacity) }
                            if currentStep == .body { bodyStepContent.transition(.opacity) }
                            if currentStep == .goal { goalStepContent.transition(.opacity) }
                            if currentStep == .experience { experienceStepContent.transition(.opacity) }
                            if currentStep == .strengthAssessment { strengthStepContent.transition(.opacity) }
                            if currentStep == .workoutLocation { locationStepContent.transition(.opacity) }
                            if currentStep == .equipment { equipmentStepContent.transition(.opacity) }
                            if currentStep == .schedule { scheduleStepContent.transition(.opacity) }
                            if currentStep == .profilePhoto { profilePhotoStepContent.transition(.opacity) }
                            if currentStep == .contacts { contactsStepContent.transition(.opacity) }
                            if currentStep == .addFriends { addFriendsStepContent.transition(.opacity) }
                        }
                        .animation(.easeInOut(duration: 0.25), value: currentStep)  // Smooth fade for content
                        
                        Spacer()
                    }
                    
                    // Floating Continue button - IDENTICAL to auth step positioning
                    onboardingSharedButtonBar
                        .padding(.horizontal, 24)
                        .padding(.bottom, keyboardUp ? keyboardObserver.keyboardHeight + 10 : 50)
                        .animation(.easeOut(duration: 0.25), value: keyboardObserver.keyboardHeight)
                        .animation(nil, value: currentStep)  // Don't animate button bar on step changes
                        .animation(nil, value: isCheckingUsername)  // Don't animate during username verification
                }
            }
            
            // Limitations step - separate layout with bounded scroll area
            else if currentStep == .limitations {
                VStack(spacing: 0) {
                    // Header
                    onboardingSharedHeader(compact: false)
                    
                    // Scrollable list container - fills remaining space above buttons
                    ScrollView(showsIndicators: true) {
                        VStack(spacing: 16) {
                            // "No limitations" option at top for easy access
                            Button(action: { 
                                selectionFeedback.selectionChanged()
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    selectedLimitations.removeAll()
                                    limitationAccommodations.removeAll()
                                }
                            }) {
                                HStack(spacing: 10) {
                                    Image(systemName: selectedLimitations.isEmpty ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 20))
                                    Text("No injuries or limitations")
                                        .font(.subheadline.weight(.semibold))
                                    Spacer()
                                }
                                .foregroundStyle(
                                    selectedLimitations.isEmpty
                                        ? AnyShapeStyle(LinearGradient(colors: [.green, .mint], startPoint: .leading, endPoint: .trailing))
                                        : AnyShapeStyle(Color.secondary)
                                )
                                .padding(.vertical, 14)
                                .padding(.horizontal, Spacing.md)
                                .background(
                                    RoundedRectangle(cornerRadius: CornerRadius.md)
                                        .fill(selectedLimitations.isEmpty 
                                            ? AnyShapeStyle(Color.green.opacity(0.1))
                                            : AnyShapeStyle(LinearGradient(
                                                colors: colorScheme == .dark 
                                                    ? [Color(white: 0.14), Color(white: 0.10)]
                                                    : [Color.white, Color(red: 0.97, green: 0.98, blue: 1.0)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ))
                                        )
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: CornerRadius.md)
                                        .stroke(selectedLimitations.isEmpty ? Color.green.opacity(0.3) : Color.clear, lineWidth: 1.5)
                                )
                            }
                            .padding(.bottom, 12)
                            
                            // Limitation options
                            VStack(spacing: 10) {
                                ForEach(AffectedArea.commonAreas, id: \.self) { area in
                                    limitationRowWithDropdown(for: area)
                                }
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
            else if currentStep == .confirmation {
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
                                                .padding(.horizontal, Spacing.md)
                                                .padding(.vertical, Spacing.xs)
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
                            
                            confirmationRowSimple(title: "Name", value: name.isEmpty ? "-" : name, editStep: .auth, focusField: .name)
                            confirmationRowSimple(title: "Email", value: email.isEmpty ? "-" : email, editStep: .auth, focusField: .email)
                            confirmationRowSimple(title: "Username", value: username.isEmpty ? "-" : "@\(username)", editStep: .username, focusField: .username)
                            confirmationRowSimple(title: "Birthday", value: birthday, editStep: .basics, focusField: .birthday)
                            confirmationRowSimple(title: "Gender", value: selectedGender ?? "Not specified", editStep: .basics)
                            confirmationRowSimple(title: "Height", value: formatHeightDisplay(), editStep: .body, focusField: .height)
                            confirmationRowSimple(title: "Weight", value: "\(weight) \(weightUnit == .lbs ? "lbs" : "kg")", editStep: .body, focusField: .weight)
                            confirmationRowSimple(title: "Goals", value: selectedGoals.joined(separator: ", "), editStep: .goal)
                            confirmationRowSimple(title: "Experience", value: selectedExperience, editStep: .experience)
                            confirmationRowSimple(title: "Location", value: selectedWorkoutLocation.rawValue.capitalized, editStep: .workoutLocation)
                            confirmationRowSimple(title: "Equipment", value: selectedEquipment.isEmpty ? "None" : Array(selectedEquipment).sorted().joined(separator: ", "), editStep: .equipment)
                            confirmationRowSimple(title: "Limitations", value: selectedLimitations.isEmpty ? "None" : "\(selectedLimitations.count) selected", editStep: .limitations)
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
        .onChange(of: focusedField) { oldField, newField in
            // When user focuses on auth fields, show the onboarding header
            if currentStep == .auth && !hasStartedAuth {
                if newField == .email || newField == .password || newField == .confirmPassword {
                    let fieldToFocus = newField  // Capture the field
                    // Trigger layout change
                    hasStartedAuth = true
                    // Re-establish focus immediately and after animations
                    DispatchQueue.main.async {
                        focusedField = fieldToFocus
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        focusedField = fieldToFocus
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        focusedField = fieldToFocus
                    }
                }
            }
        }
        .onChange(of: currentStep) { oldStep, newStep in
            // Set focus based on the new step
            switch newStep {
            case .auth:
                // Keep hasStartedAuth true when going back from username (user wants to see their filled form)
                // Only reset to welcome screen when coming from far away steps
                if oldStep == .username || oldStep == .phoneNumber {
                    hasStartedAuth = true  // Keep in standard mode to show filled form
                    // Check if we need to restore confirm password step
                    // If confirm password has content, user was on that step
                    if !confirmPassword.isEmpty && passwordsMatch {
                        isOnConfirmPasswordStep = true
                        DispatchQueue.main.async {
                            focusedField = .confirmPassword
                        }
                    } else {
                        // Focus on password field (or email if password empty)
                        DispatchQueue.main.async {
                            focusedField = password.isEmpty ? .email : .password
                        }
                    }
                } else if oldStep != .auth {
                    hasStartedAuth = false  // Reset to welcome screen
                }
            case .phoneNumber:
                focusedField = .phoneNumber
            case .username:
                // Check if there's a pending social username to pre-fill (from Facebook/Instagram)
                if let socialUsername = UserDefaults.standard.string(forKey: "pending_social_username"), username.isEmpty {
                    username = socialUsername
                    UserDefaults.standard.removeObject(forKey: "pending_social_username")
                    print("📘 Pre-filled username from social login: @\(socialUsername)")
                }
                // Note: Focus is now handled in:
                // - handleAuth() for email signup (keeps keyboard open)
                // - handleAppleSignIn() for Apple auth
                // - handleOAuthUserOnboarding() for Google auth
                // Only set focus here if coming from non-auth steps (like phone or basics)
                if oldStep != .auth && oldStep != .phoneNumber {
                    let targetField: FocusedField = name.isEmpty ? .name : .username
                    DispatchQueue.main.async {
                        focusedField = targetField
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        focusedField = targetField
                    }
                }
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
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("OAuthNewUserNeedsOnboarding"))) { _ in
            // Handle new Google/OAuth user - navigate to username selection
            // This notification is ONLY posted from a fresh OAuth callback, not session restore
            print("👤 [OAUTH] Received new user notification - navigating to username step")
            handleOAuthUserOnboarding()
        }
        // NOTE: Removed the onChange(of: supabaseManager.isAuthenticated) handler
        // because it was incorrectly triggering on session restore at app launch.
        // The OAuthNewUserNeedsOnboarding notification is the correct and only trigger.
        .onAppear {
            // Start a new onboarding session for logging
            OnboardingSessionManager.shared.startNewSession()
            
            // Log session start to cloud
            Task {
                await supabaseManager.logOnboardingEvent(
                    eventType: "session_started",
                    stepName: "auth",
                    eventData: [
                        "initial_step": "\(currentStep)",
                        "is_authenticated": supabaseManager.isAuthenticated
                    ]
                )
            }
        }
        .onDisappear {
            // End the session when view disappears
            OnboardingSessionManager.shared.endSession()
            // Clean up timers to prevent leaks
            sendCodeTimer?.invalidate()
            sendCodeTimer = nil
        }
    }
    
    /// Handle OAuth user onboarding - pre-fill data and navigate to username step
    private func handleOAuthUserOnboarding() {
        print("🔐 [OAUTH] handleOAuthUserOnboarding called - currentStep: \(currentStep)")
        
        let metadata = supabaseManager.currentUser?.userMetadata ?? [:]
        print("🔐 [OAUTH] Current user metadata: \(metadata)")
        
        // Pre-fill FULL NAME (first + last) from OAuth provider
        // Try ALL sources to find the name - be flexible with type casting
        var foundFullName: String? = nil
        
        // 1. Try UserDefaults first (stored by SupabaseManager during sign-in)
        if let oauthName = UserDefaults.standard.string(forKey: "pending_oauth_name"), !oauthName.isEmpty {
            foundFullName = oauthName
            UserDefaults.standard.removeObject(forKey: "pending_oauth_name")
            print("🔐 [OAUTH] Got full name from UserDefaults: \(oauthName)")
        }
        
        // 2. Try user metadata - handle various types (String, AnyJSON, etc.)
        if foundFullName == nil {
            // Try full_name first
            if let fullNameValue = metadata["full_name"] {
                let fullNameString = String(describing: fullNameValue)
                if !fullNameString.isEmpty && fullNameString != "nil" && fullNameString != "<null>" {
                    foundFullName = fullNameString
                    print("🔐 [OAUTH] Got full name from metadata (full_name): \(fullNameString)")
                }
            }
            
            // Try name as fallback
            if foundFullName == nil, let nameValue = metadata["name"] {
                let nameString = String(describing: nameValue)
                if !nameString.isEmpty && nameString != "nil" && nameString != "<null>" {
                    foundFullName = nameString
                    print("🔐 [OAUTH] Got full name from metadata (name): \(nameString)")
                }
            }
        }
        
        // Set the full name if we found one
        if let foundFullName = foundFullName, !foundFullName.isEmpty {
            name = foundFullName
            print("🔐 [OAUTH] ✅ Set full name to: '\(foundFullName)'")
        } else {
            print("🔐 [OAUTH] ⚠️ Could not find name in any source")
        }
        
        // Pre-fill email - try current user first (most reliable), then UserDefaults
        if let userEmail = supabaseManager.currentUser?.email, !userEmail.isEmpty {
            email = userEmail
            print("🔐 [OAUTH] Pre-filled email from current user: \(userEmail)")
        } else if let oauthEmail = UserDefaults.standard.string(forKey: "pending_oauth_email"), !oauthEmail.isEmpty {
            email = oauthEmail
            UserDefaults.standard.removeObject(forKey: "pending_oauth_email")
            print("🔐 [OAUTH] Pre-filled email from UserDefaults: \(oauthEmail)")
        }
        
        print("🔐 [OAUTH] Final values - name: '\(name)', email: '\(email)'")
        print("🔐 [OAUTH] needsNameInput will be: \(needsNameInput)")
        
        // Navigate to username step (name pre-filled from OAuth)
        print("🔐 [OAUTH] Navigating to username step...")
        navigateTo(.username)
        
        // Auto-focus the appropriate field based on whether name was filled
        let targetField: FocusedField = name.isEmpty ? .name : .username
        DispatchQueue.main.async {
            focusedField = targetField
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            focusedField = targetField
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            focusedField = targetField
        }
        print("🔐 [OAUTH] Focus set to: \(targetField)")
    }
    
    // MARK: - Shared Header (Simple, fixed layout)
    @ViewBuilder
    private func onboardingSharedHeader(compact: Bool = false) -> some View {
        VStack(spacing: currentStep == .auth ? 12 : 16) {
            // Logo
            Image("fit33-logo")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 110, height: 44)
                .clipped()
            
            // Progress bar
            progressIndicator
            
            // Title + subtitle (always show)
            VStack(spacing: currentStep == .auth ? 6 : 8) {
                Text(onboardingStepTitle)
                    .font(.title3.weight(.bold))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                
                Text(onboardingStepSubtitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 20)
            }
        }
        .padding(.top, UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.safeAreaInsets.top.map { max($0 + 10, 50) } ?? 70) // Dynamic safe area clearance
        .padding(.bottom, currentStep == .auth ? 12 : 24)
    }

    // MARK: - Step Titles
    private var onboardingStepTitle: String {
        switch currentStep {
        case .auth: return isSignUp ? "Create Account" : "Welcome Back"
        case .phoneNumber: return "Secure Your Account"
        case .username: return "Your Profile"
        case .basics: return "About You"
        case .body: return "Your Measurements"
        case .goal: return "Your Goals"
        case .experience: return "Experience Level"
        case .strengthAssessment: return "Strength Level"
        case .workoutLocation: return "Where do you typically workout?"
        case .equipment: return "What equipment do you have?"
        case .limitations: return "Any Limitations?"
        case .schedule: return "Your Schedule"
        case .profilePhoto: return "Add a Photo"
        case .contacts: return "Connect Your Contacts"
        case .addFriends: return "Add Your Friends"
        case .confirmation: return "Review & Confirm"
        case .complete: return "You're All Set!"
        }
    }
    
    private var onboardingStepSubtitle: String {
        switch currentStep {
        case .auth: return isSignUp ? "Join the club" : "Continue your journey"
        case .phoneNumber: return "Set up two-factor authentication"
        case .username: return "Tell us about yourself and how friends will find you"
        case .basics: return "Help us personalize your experience"
        case .body: return "For accurate recommendations"
        case .goal: return "What do you want to achieve?"
        case .experience: return "How long have you been training?"
        case .strengthAssessment: return "Helps us suggest the right starting weights"
        case .workoutLocation: return "This can be updated at any time"
        case .equipment: return "What equipment do you have access to and prefer to use. This can be updated anytime"
        case .limitations: return "Anything we should know about?"
        case .schedule: return "How often do you want to train?"
        case .profilePhoto: return "Help friends recognize you"
        case .contacts: return "Find friends who are already on Fit33"
        case .addFriends: return "People from your contacts using Fit33"
        case .confirmation: return "Make sure everything looks right"
        case .complete: return "Let's start your first workout"
        }
    }
    
    private var onboardingStepExplanation: String {
        switch currentStep {
        case .auth: return ""
        case .phoneNumber: return "Your phone number is private and will never be displayed publicly or shared with others"
        case .username: return "Friends can find and add you using your unique username"
        case .basics: return "We use your age to calculate calorie needs and tailor workout intensity"
        case .body: return "Height and weight help us recommend appropriate exercise loads"
        case .goal: return "Your goals shape the type of workouts we'll recommend"
        case .experience: return "This helps us match exercises to your skill level"
        case .strengthAssessment: return "We'll suggest starting weights that match your current strength"
        case .workoutLocation: return "You can change this anytime in settings"
        case .equipment: return "Select what you typically use - you can change this anytime"
        case .limitations: return "We'll avoid exercises that could aggravate injuries or issues"
        case .schedule: return "We'll build a program that fits your weekly availability"
        case .profilePhoto: return "Your photo appears on shared workouts and friend lists"
        case .contacts: return "We'll never message your contacts without your permission"
        case .addFriends: return "Send friend requests to start training together"
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
                goToPreviousStep()
            }) {
                Image(systemName: "chevron.left")
                    .font(.ds_labelLarge)
                    .foregroundColor(.gray)
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(Color(.systemGray6)))
                    .overlay(Circle().stroke(Color.gray.opacity(0.3), lineWidth: 1.5))
            }
            
            // Continue button
            Button(action: {
                isNavigatingForward = true
                if currentStep == .username && !isUsernameAvailable {
                    // Verify username first
                    checkUsernameAvailability()
                } else if currentStep == .phoneNumber && !isVerificationCodeSent && sendCodeCountdown == 0 {
                    // Send verification code first
                    sendVerificationCode()
                } else {
                    goToNextStep()
                }
            }) {
                HStack(spacing: 8) {
                    if currentStep == .username && isCheckingUsername {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: isCurrentStepValid ? .blue : .gray))
                            .scaleEffect(0.9)
                    }
                    if currentStep == .phoneNumber && !isVerificationCodeSent && sendCodeCountdown == 0 {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    if currentStep == .phoneNumber && sendCodeCountdown > 0 {
                        Image(systemName: "clock.fill")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    Text(continueButtonText)
                        .font(.headline)
                        .fontWeight(.semibold)
                }
                .foregroundStyle(
                    isCurrentStepValid
                        ? AnyShapeStyle(LinearGradient(colors: [.blue, .blue, .cyan.opacity(0.8)], startPoint: .leading, endPoint: .trailing))
                        : AnyShapeStyle(Color.gray)
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.md)
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
    
    // MARK: - Continue Button Text
    private var continueButtonText: String {
        switch currentStep {
        case .username:
            if isCheckingUsername {
                return "Verifying..."
            } else if !isUsernameAvailable && isUsernameValid {
                return "Verify Username"
            } else {
                return "Continue"
            }
        case .phoneNumber:
            if !isVerificationCodeSent {
                if sendCodeCountdown > 0 {
                    return "Retry in \(sendCodeCountdown)s"
                } else {
                    return "Send Code"
                }
            } else {
                return "Continue"
            }
        case .confirmation:
            return "Create Account"
        case .profilePhoto:
            return profilePhotoImage != nil ? "Continue" : "Skip"
        case .contacts:
            return contactsPermissionGranted ? "Continue" : "Skip"
        case .addFriends:
            return sentFriendRequests.isEmpty ? "Skip" : "Continue"
        default:
            return "Continue"
        }
    }
    
    // MARK: - Step Validation
    private var isCurrentStepValid: Bool {
        switch currentStep {
        case .auth: return isAuthFormValid
        case .phoneNumber: 
            // Enable button when:
            // 1. Phone valid and can send (sendCodeCountdown == 0)
            // 2. Code already sent and verified
            if !isVerificationCodeSent {
                return isPhoneNumberValid && sendCodeCountdown == 0
            } else {
                return isPhoneVerified
            }
        case .username: 
            // Always require name to be filled and username to be valid format
            // Username doesn't need to be verified yet - button will trigger verification
            let nameValid = !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            return isUsernameValid && nameValid
        case .basics: return isBirthdayValid && calculatedAge >= 13 && calculatedAge <= 120
        case .body: return isHeightValid && isWeightValid
        case .goal: return !selectedGoals.isEmpty
        case .experience: return !selectedExperience.isEmpty
        case .strengthAssessment: return true
        case .workoutLocation: return true
        case .equipment: return !selectedEquipment.isEmpty
        case .limitations: return true
        case .schedule: return selectedDays > 0
        case .profilePhoto: return true  // Optional step, always valid
        case .contacts: return true  // Optional step, always valid
        case .addFriends: return true  // Optional step, always valid
        case .confirmation: return true
        case .complete: return true
        }
    }
    
    // Phone number validation - at least 10 digits for US numbers
    private var isPhoneNumberValid: Bool {
        let digits = phoneNumber.filter { $0.isNumber }
        return digits.count >= selectedCountryCode.minDigits && digits.count <= selectedCountryCode.maxDigits
    }
    
    // Get full E.164 formatted phone number for sending to Twilio
    private var fullPhoneNumber: String {
        let digits = phoneNumber.filter { $0.isNumber }
        return "\(selectedCountryCode.dialingCode)\(digits)"
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
        
        // Special case: if contacts permission not granted, skip addFriends step
        if currentStep == .contacts && !contactsPermissionGranted {
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
        
        // Special case: if on phone step with code sent, go back to phone input (not previous step)
        // Start 30s countdown so user can't spam send code
        if currentStep == .phoneNumber && isVerificationCodeSent {
            
            isVerificationCodeSent = false
            verificationCode = ""
            verificationError = ""
            
            // Start 30s cooldown before they can send again
            sendCodeCountdown = 30
            startSendCodeCountdownTimer()
            
            focusedField = .phoneNumber
            return
        }
        
        // Special case: if on confirmation and contacts weren't granted, skip addFriends when going back
        if currentStep == .confirmation && !contactsPermissionGranted {
            navigateTo(.contacts)
            return
        }
        
        guard let prevStep = OnboardingStep(rawValue: currentStep.rawValue - 1) else { return }
        navigateTo(prevStep)
    }
    
    // MARK: - Content-Only Step Views (for sliding)
    // These are simplified versions that just show the content portion
    // The existing full step views (basicsStep, bodyStep, etc.) are kept for reference
    
    private var phoneInputView: some View {
        let _ = print("📱 [PHONE INPUT] Rendering phoneInputView - selectedCountryCode: \(selectedCountryCode.rawValue)")
        
        return VStack(alignment: .leading, spacing: 12) {
            Text("Phone Number")
                .font(.subheadline.weight(.medium))
                .foregroundColor(.secondary)
            
            HStack(spacing: 12) {
                // Country code picker - using Picker instead of Menu to avoid SwiftUI rendering issues
                countryCodePicker
                
                // Phone number input
                phoneNumberTextField
            }
        }
        .id("phoneInputView-\(selectedCountryCode.rawValue)")
    }
    
    // Extracted country code picker to simplify view hierarchy
    private var countryCodePicker: some View {
        let _ = print("🌍 [COUNTRY PICKER] Rendering - current: \(selectedCountryCode.name)")
        
        return Menu {
            ForEach(CountryCode.allCases) { country in
                Button {
                    print("🌍 [COUNTRY PICKER] Selected: \(country.name)")
                    selectedCountryCode = country
                    phoneNumber = ""
                } label: {
                    // Dropdown shows: Flag + Country Name
                    Text("\(country.flag) \(country.name)")
                }
            }
        } label: {
            // Selected state shows: Flag + Country Code
            HStack(spacing: 6) {
                Text(selectedCountryCode.flag)
                    .font(.system(size: 18))
                Text(selectedCountryCode.dialingCode)
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundColor(.primary)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.md)
                    .fill(colorScheme == .dark ? Color(white: 0.22) : Color(white: 0.95))
            )
        }
        .id("countryPicker-\(selectedCountryCode.rawValue)")
    }
    
    // Extracted phone number text field
    private var phoneNumberTextField: some View {
        let _ = print("📞 [PHONE FIELD] Rendering - phoneNumber: \(phoneNumber)")
        
        return HStack(spacing: 12) {
            TextField(selectedCountryCode.placeholder, text: $phoneNumber)
                .keyboardType(.phonePad)
                .textContentType(.telephoneNumber)
                .focused($focusedField, equals: .phoneNumber)
                .onChange(of: phoneNumber) { _, newValue in
                    let formatted = formatPhoneNumberForCountry(newValue)
                    if formatted != phoneNumber {
                        print("📞 [PHONE FIELD] Formatting: '\(newValue)' -> '\(formatted)'")
                        phoneNumber = formatted
                    }
                }
            
            if isPhoneNumberValid {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.blue)
            }
        }
        .font(.ds_bodyRegular)
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.md)
                .fill(colorScheme == .dark ? Color(white: 0.18) : Color.white)
                .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.md)
                .stroke(isPhoneNumberValid ? Color.blue.opacity(0.4) : Color.clear, lineWidth: 1.5)
        )
        .id("phoneTextField-\(selectedCountryCode.rawValue)")
    }
    
    // MARK: - Phone Number Step Content (2FA / Account Security)
    private var phoneNumberStepContent: some View {
        let _ = print("📱 [PHONE STEP] Rendering phoneNumberStepContent")
        let _ = print("   └─ isVerificationCodeSent: \(isVerificationCodeSent)")
        let _ = print("   └─ isPhoneVerified: \(isPhoneVerified)")
        let _ = print("   └─ phoneNumber: '\(phoneNumber)'")
        let _ = print("   └─ selectedCountryCode: \(selectedCountryCode.rawValue)")
        
        return VStack(spacing: 20) {
            // STATE 1: PHONE NUMBER INPUT (before code sent)
            if !isVerificationCodeSent && !isPhoneVerified {
                let _ = print("📱 [PHONE STEP] Showing STATE 1: Phone input")
                phoneInputView
                
                // Privacy message
                HStack(spacing: 10) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.blue.opacity(0.8))
                    
                    Text("Your number is private and will never be shared.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.blue.opacity(0.08))
                )
            }
            
            // STATE 2: VERIFICATION CODE INPUT (after code sent)
            if isVerificationCodeSent && !isPhoneVerified {
                let _ = print("📱 [PHONE STEP] Showing STATE 2: Verification code input")
                VStack(spacing: 20) {
                    // Show which number code was sent to
                    HStack(spacing: 8) {
                        Image(systemName: "phone.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.blue)
                        Text("Code sent to \(formatInternationalNumber())")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.primary)
                    }
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.blue.opacity(0.1))
                    )
                    
                    // Warning if this is the last attempt
                    if phoneVerificationAttempts >= maxPhoneVerificationAttempts {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 12))
                            Text("Last attempt - going back will skip this step")
                                .font(.caption)
                        }
                        .foregroundColor(.orange)
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, Spacing.xs)
                        .background(
                            RoundedRectangle(cornerRadius: CornerRadius.sm)
                                .fill(Color.orange.opacity(0.1))
                        )
                    }
                    
                    // 6-digit code input with individual tiles
                    ZStack {
                        // Hidden text field for iOS auto-fill support
                        TextField("", text: $verificationCode)
                            .keyboardType(.numberPad)
                            .textContentType(.oneTimeCode)
                            .focused($focusedField, equals: .verificationCode)
                            .opacity(0)
                            .onChange(of: verificationCode) { _, newValue in
                                let digits = newValue.filter { $0.isNumber }
                                if digits != verificationCode {
                                    verificationCode = String(digits.prefix(6))
                                }
                                if verificationCode.count == 6 {
                                    verifyCode()
                                }
                            }
                        
                        // Visual digit tiles - responsive width for all screen sizes
                        GeometryReader { geo in
                            let tileWidth = min(50, (geo.size.width - 50) / 6) // 50pt spacing total, 6 tiles
                            let tileHeight = tileWidth * 1.2
                            HStack(spacing: max(6, (geo.size.width - tileWidth * 6) / 5)) {
                                ForEach(0..<6, id: \.self) { index in
                                    ZStack {
                                        RoundedRectangle(cornerRadius: CornerRadius.md)
                                            .fill(colorScheme == .dark ? Color(white: 0.18) : Color(white: 0.95))

                                        RoundedRectangle(cornerRadius: CornerRadius.md)
                                            .stroke(
                                                index == verificationCode.count ? Color.blue : Color.clear,
                                                lineWidth: 2
                                            )

                                        Text(getDigit(at: index))
                                            .font(.system(size: min(28, tileWidth * 0.56), weight: .bold, design: .rounded))
                                            .foregroundColor(.primary)
                                    }
                                    .frame(width: tileWidth, height: tileHeight)
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .frame(height: 72) // Fixed height container
                        .onTapGesture {
                            focusedField = .verificationCode
                        }
                    }
                    
                    // Hint for auto-fill
                    Text("Tap the code above the keyboard to auto-fill")
                        .font(.caption)
                        .foregroundColor(.secondary.opacity(0.7))
                    
                    // Error message
                    if !verificationError.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .font(.system(size: 12))
                            Text(verificationError)
                                .font(.caption)
                        }
                        .foregroundColor(.red)
                    }
                    
                    // Loading state
                    if isVerifyingCode {
                        HStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Verifying...")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    // Resend option
                    if resendCountdown > 0 {
                        Text("Resend code in \(resendCountdown)s")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Button("Resend Code") {
                            resendVerificationCode()
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.blue)
                    }
                }
                .onAppear {
                    // Focus the code field to enable iOS auto-fill
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        focusedField = .verificationCode
                    }
                }
            }
            
            // STATE 3: VERIFIED SUCCESS
            if isPhoneVerified {
                let _ = print("📱 [PHONE STEP] Showing STATE 3: Verified success")
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 50))
                        .foregroundStyle(LinearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing))
                    
                    Text("Phone Verified!")
                        .font(.title2.weight(.bold))
                        .foregroundColor(.blue)
                    
                    Text(formatInternationalNumber())
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.primary)
                    
                    Text("Two-factor authentication is now enabled.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    // Privacy reminder
                    HStack(spacing: 8) {
                        Image(systemName: "eye.slash.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.blue.opacity(0.7))
                        Text("Your number is private and will never be displayed or shared.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.blue.opacity(0.08))
                    )
                    .padding(.top, 8)
                }
                .padding(.vertical, 20)
                .transition(.scale.combined(with: .opacity))
            }
            
            Spacer()
        }
        .padding(.horizontal, 24)
        .id("phoneNumberStepContent-\(selectedCountryCode.rawValue)-\(isVerificationCodeSent)-\(isPhoneVerified)")
    }
    
    // Helper to get digit at index for verification code display
    private func getDigit(at index: Int) -> String {
        guard index < verificationCode.count else { return "" }
        let idx = verificationCode.index(verificationCode.startIndex, offsetBy: index)
        return String(verificationCode[idx])
    }
    
    // Send verification code
    private func sendVerificationCode() {
        print("📤 [SEND CODE] Starting sendVerificationCode()")
        print("   └─ phoneNumber: '\(phoneNumber)'")
        print("   └─ fullPhoneNumber: '\(fullPhoneNumber)'")
        print("   └─ selectedCountryCode: \(selectedCountryCode.rawValue)")
        print("   └─ phoneVerificationAttempts: \(phoneVerificationAttempts)")
        
        verificationError = ""
        
        // Increment attempt counter
        phoneVerificationAttempts += 1
        print("📤 [SEND CODE] Incremented attempts to: \(phoneVerificationAttempts)")
        
        // Immediately advance to code input screen (don't wait for send)
        print("📤 [SEND CODE] Setting isVerificationCodeSent = true with animation")
        withAnimation(.easeInOut(duration: 0.2)) {
            isVerificationCodeSent = true
        }
        print("📤 [SEND CODE] isVerificationCodeSent is now: \(isVerificationCodeSent)")
        
        startResendCountdown()
        
        // Focus the code field after a brief delay for view to build
        print("📤 [SEND CODE] Scheduling focus change in 0.3s")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            print("📤 [SEND CODE] Setting focusedField to .verificationCode")
            self.focusedField = .verificationCode
        }
        
        // Send the code in background - by the time user sees the screen, SMS arrives
        print("📤 [SEND CODE] Starting async task to send SMS")
        Task {
            print("📤 [SEND CODE] Calling phoneVerificationService.sendVerificationCode")
            let success = await phoneVerificationService.sendVerificationCode(to: fullPhoneNumber)
            print("📤 [SEND CODE] SMS send result: \(success)")
            
            if !success {
                await MainActor.run {
                    let errorMsg = phoneVerificationService.error ?? "Failed to send code. Tap resend to try again."
                    print("📤 [SEND CODE] ERROR: \(errorMsg)")
                    verificationError = errorMsg
                }
            }
        }
        print("📤 [SEND CODE] Function complete (async task running in background)")
    }
    
    // Verify the entered code
    private func verifyCode() {
        guard verificationCode.count == 6 else { return }
        
        isVerifyingCode = true
        verificationError = ""
        
        verifyCodeAsync()
    }
    
    private func verifyCodeAsync() {
        Task {
            let success = await phoneVerificationService.verifyCode(verificationCode, for: fullPhoneNumber)
            
            isVerifyingCode = false
            if success {
                isPhoneVerified = true
                selectionFeedback.selectionChanged()
                
                // ✨ For EMAIL/PASSWORD signups: Create MINIMAL account NOW (after phone verification)
                // This matches the Google/Apple login flow where user is authenticated early
                if isSignUp && !supabaseManager.isAuthenticated {
                    await createMinimalAccountForEmailPasswordSignup()
                } else {
                    // OAuth users are already authenticated - just update profile
                    await createMinimalProfileForContactMatching()
                }
            } else {
                verificationError = phoneVerificationService.error ?? "Invalid code"
                verificationCode = ""
            }
        }
    }
    
    private func createMinimalAccountForEmailPasswordSignup() async {
        print("📝 [PHONE VERIFIED] Creating minimal account for email/password signup...")
        
        do {
            // Create account with minimal info (just like OAuth flow)
            try await supabaseManager.signUp(
                email: email,
                password: password,
                name: name.isEmpty ? "User" : name
            )
            print("✅ [PHONE VERIFIED] Minimal account created! User ID: \(supabaseManager.currentUser?.id.uuidString ?? "nil")")
            
            // Update profile with phone number for contact matching
            if let userId = supabaseManager.currentUser?.id {
                struct PhoneUpdate: Encodable {
                    let phone_number: String
                    let phone_verified: Bool
                }
                
                let update = PhoneUpdate(
                    phone_number: fullPhoneNumber,
                    phone_verified: true
                )
                
                try await supabaseManager.supabaseClient
                    .from("user_profiles")
                    .update(update)
                    .eq("id", value: userId.uuidString)
                    .execute()
                print("✅ [PHONE VERIFIED] Phone added - contact matching enabled!")
            }
            
            // Set username if provided
            if !username.isEmpty {
                print("📝 [PHONE VERIFIED] Setting username: @\(username)")
                try? await supabaseManager.setUsername(username)
            }
            
            print("✅ [PHONE VERIFIED] Minimal account ready - user can continue onboarding")
            
        } catch {
            print("❌ [PHONE VERIFIED] Failed to create account: \(error)")
            await MainActor.run {
                verificationError = "Account creation failed. Please try again."
                isPhoneVerified = false
            }
        }
    }
    
    // Create a minimal profile immediately after phone verification
    // This enables contact matching to work during onboarding
    private func createMinimalProfileForContactMatching() async {
        guard let userId = supabaseManager.currentUser?.id else {
            print("⚠️ [EARLY PROFILE] No user ID available")
            return
        }
        
        print("📝 [EARLY PROFILE] Creating minimal profile for contact matching...")
        print("   └─ User ID: \(userId.uuidString)")
        print("   └─ Phone: \(fullPhoneNumber)")
        print("   └─ Email: \(email)")
        
        do {
            // Create or update minimal profile with just phone + email
            struct MinimalProfile: Encodable {
                let id: String
                let email: String
                let phone_number: String
                let phone_verified: Bool
                let name: String?
                let has_completed_onboarding: Bool
            }
            
            let profile = MinimalProfile(
                id: userId.uuidString,
                email: email,
                phone_number: fullPhoneNumber,
                phone_verified: true,
                name: name.isEmpty ? nil : name,
                has_completed_onboarding: false
            )
            
            try await supabaseManager.supabaseClient
                .from("user_profiles")
                .upsert(profile)
                .execute()
            
            print("✅ [EARLY PROFILE] Minimal profile created - contact matching now enabled!")
        } catch {
            print("❌ [EARLY PROFILE] Failed to create profile: \(error)")
        }
    }
    
    // Resend verification code
    private func resendVerificationCode() {
        verificationCode = ""
        verificationError = ""
        sendVerificationCode()
    }
    
    // Start countdown for resend
    private func startResendCountdown() {
        resendCountdown = 30
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
            if resendCountdown > 0 {
                resendCountdown -= 1
            } else {
                timer.invalidate()
            }
        }
    }
    
    // Start countdown timer for send code button (when user goes back from code entry)
    private func startSendCodeCountdownTimer() {
        sendCodeTimer?.invalidate()
        sendCodeTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [self] timer in
            if sendCodeCountdown > 0 {
                sendCodeCountdown -= 1
            } else {
                timer.invalidate()
                sendCodeTimer = nil
            }
        }
    }
    
    // Format phone number with parentheses and dashes
    // Format phone number for US display (used in code sent message)
    private func formatPhoneNumber(_ input: String) -> String {
        let digits = input.filter { $0.isNumber }
        let limited = String(digits.prefix(10))
        
        var result = ""
        for (index, char) in limited.enumerated() {
            if index == 0 {
                result += "("
            }
            if index == 3 {
                result += ") "
            }
            if index == 6 {
                result += "-"
            }
            result += String(char)
        }
        return result
    }
    
    // Format phone number based on selected country
    private func formatPhoneNumberForCountry(_ input: String) -> String {
        let digits = input.filter { $0.isNumber }
        let limited = String(digits.prefix(selectedCountryCode.maxDigits))

        // US/Canada: (XXX) XXX-XXXX
        if selectedCountryCode == .us || selectedCountryCode == .canada {
            var result = ""
            for (index, char) in limited.enumerated() {
                if index == 0 { result += "(" }
                if index == 3 { result += ") " }
                if index == 6 { result += "-" }
                result += String(char)
            }
            return result
        }

        // UK: XXXX XXXXXX
        if selectedCountryCode == .uk {
            var result = ""
            for (index, char) in limited.enumerated() {
                if index == 4 { result += " " }
                result += String(char)
            }
            return result
        }

        // India: XXXXX XXXXX
        if selectedCountryCode == .india {
            var result = ""
            for (index, char) in limited.enumerated() {
                if index == 5 { result += " " }
                result += String(char)
            }
            return result
        }

        // Brazil: XX XXXXX XXXX
        if selectedCountryCode == .brazil {
            var result = ""
            for (index, char) in limited.enumerated() {
                if index == 2 || index == 7 { result += " " }
                result += String(char)
            }
            return result
        }

        // Japan/Korea: XX XXXX XXXX
        if selectedCountryCode == .japan || selectedCountryCode == .southKorea {
            var result = ""
            for (index, char) in limited.enumerated() {
                if index == 2 || index == 6 { result += " " }
                result += String(char)
            }
            return result
        }

        // Australia: XXX XXX XXX
        if selectedCountryCode == .australia {
            var result = ""
            for (index, char) in limited.enumerated() {
                if index == 3 || index == 6 { result += " " }
                result += String(char)
            }
            return result
        }

        // Singapore/Hong Kong: XXXX XXXX
        if selectedCountryCode == .singapore || selectedCountryCode == .hongKong {
            var result = ""
            for (index, char) in limited.enumerated() {
                if index == 4 { result += " " }
                result += String(char)
            }
            return result
        }

        // Default: space every 3 digits for readability
        var result = ""
        for (index, char) in limited.enumerated() {
            if index > 0 && index % 3 == 0 { result += " " }
            result += String(char)
        }
        return result
    }
    
    // Format full international number for display
    private func formatInternationalNumber() -> String {
        let digits = phoneNumber.filter { $0.isNumber }
        return "\(selectedCountryCode.dialingCode) \(digits)"
    }
    
    // MARK: - Username Step Content
    private var usernameStepContent: some View {
        VStack(spacing: 28) {
            // Name field - always show for all users (email, Apple, Google auth)
            // For email signup: user enters manually
            // For Apple/Google: autofills from OAuth but is editable
            VStack(alignment: .leading, spacing: 8) {
                Text("Your Name")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.secondary)
                
                HStack(spacing: 16) {
                    Image(systemName: "person.fill")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(
                            LinearGradient(
                                colors: !name.isEmpty ? [Color.blue, Color.cyan] : [Color.gray.opacity(0.6), Color.gray.opacity(0.5)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 26)
                    
                    TextField("What should we call you?", text: $name)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .name)
                }
                .font(.ds_bodyRegular)
                .padding(.horizontal, 22)
                .padding(.vertical, 18)
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: CornerRadius.lg)
                            .fill(
                                LinearGradient(
                                    colors: colorScheme == .dark 
                                        ? [Color(white: 0.14), Color(white: 0.10)]
                                        : [Color.white, Color(red: 0.97, green: 0.98, blue: 1.0)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        
                        RoundedRectangle(cornerRadius: CornerRadius.lg)
                            .fill(Color.clear)
                            .shadow(
                                color: colorScheme == .dark ? Color.black.opacity(0.4) : Color.black.opacity(0.08),
                                radius: focusedField == .name ? 12 : 8,
                                x: 0,
                                y: focusedField == .name ? 6 : 3
                            )
                    }
                )
            }
            
            // Username - matching Birthday field style exactly
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Username")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.secondary)
                    Spacer()
                    // Status indicator in top right
                    if isCheckingUsername {
                        HStack(spacing: 4) {
                            ProgressView()
                                .scaleEffect(0.6)
                            Text("Checking...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } else if isUsernameAvailable && isUsernameValid {
                        Text("Available ✓")
                            .font(.caption)
                            .foregroundColor(.blue)
                    } else if !usernameError.isEmpty {
                        Text(usernameError)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
                
                // Username field - same style as OnboardingTextField (no checkmark inside)
                HStack(spacing: 16) {
                    // @ symbol instead of icon
                    Text("@")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(
                            LinearGradient(
                                colors: isUsernameValid ? [Color.blue, Color.cyan] : [Color.gray.opacity(0.6), Color.gray.opacity(0.5)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 26)
                    
                    TextField("username", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .username)
                        .onChange(of: username) { _, newValue in
                            // Clean the username - remove spaces and special chars (allow uppercase and lowercase)
                            let cleaned = newValue
                                .filter { $0.isLetter || $0.isNumber || $0 == "_" }
                            if cleaned != newValue {
                                username = cleaned
                            }
                            // Reset availability when typing
                            isUsernameAvailable = false
                            usernameError = ""
                        }
                }
                .font(.ds_bodyRegular)
                .padding(.horizontal, 22)
                .padding(.vertical, 18)
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: CornerRadius.lg)
                            .fill(
                                LinearGradient(
                                    colors: colorScheme == .dark 
                                        ? [Color(white: 0.14), Color(white: 0.10)]
                                        : [Color.white, Color(red: 0.97, green: 0.98, blue: 1.0)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        
                        RoundedRectangle(cornerRadius: CornerRadius.lg)
                            .fill(Color.clear)
                            .shadow(
                                color: colorScheme == .dark ? Color.black.opacity(0.4) : Color.black.opacity(0.08),
                                radius: focusedField == .username ? 12 : 8,
                                x: 0,
                                y: focusedField == .username ? 6 : 3
                            )
                    }
                )
            }
        }
        .padding(.horizontal, 24)
    }
    
    // Check username availability
    private func checkUsernameAvailability() {
        guard isUsernameValid else { return }
        
        isCheckingUsername = true
        usernameError = ""
        
        Task {
            do {
                let available = try await supabaseManager.isUsernameAvailable(username)
                
                await MainActor.run {
                    isUsernameAvailable = available
                    if !available {
                        usernameError = "This username is already taken"
                        isCheckingUsername = false
                    } else {
                        // Username is available! Auto-advance to next step
                        isCheckingUsername = false
                        // Small delay for smooth UX (show checkmark briefly)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            withAnimation {
                                goToNextStep()
                            }
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    usernameError = "Error checking username: \(error.localizedDescription)"
                    isCheckingUsername = false
                }
            }
        }
    }
    
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
                    placeholder: birthdayPlaceholder,
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
                    isValid: isHeightValid,
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
                    if isComplete && isHeightValid {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            focusedField = .weight
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            focusedField = .weight
                        }
                    }
                }
                .onChange(of: heightCm) { oldValue, newValue in
                    guard heightUnit == .cm else { return }
                    
                    // Auto-advance to weight when cm height is complete (3 digits like 175)
                    let digits = newValue.filter { $0.isNumber }
                    if digits.count == 3 && isHeightValid {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            focusedField = .weight
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            focusedField = .weight
                        }
                    }
                }
                .onChange(of: isHeightValid) { oldValue, newValue in
                    // Auto-advance when height becomes valid
                    if newValue && !oldValue && focusedField == .height {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
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
                    isValid: isWeightValid,
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
                    .font(.ds_heading3)
                    .foregroundColor(.blue)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .font(.ds_bodyRegular)
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: CornerRadius.lg)
                    .fill(Color.cardBackground)
                
                RoundedRectangle(cornerRadius: CornerRadius.lg)
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
            // Store as digits only (e.g., "510" for 5'10") - parsedHeightFeetInches expects this format
            if inches < 10 {
                heightFeetInchesDigits = "\(feet)0\(inches)"
            } else {
                heightFeetInchesDigits = "\(feet)\(inches)"
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
                        .padding(.vertical, Spacing.md)
                        .background(
                            RoundedRectangle(cornerRadius: CornerRadius.lg)
                                .fill(selectedGoals.contains(goal.0) 
                                    ? AnyShapeStyle(goal.3.opacity(0.2))
                                    : AnyShapeStyle(LinearGradient(
                                        colors: colorScheme == .dark 
                                            ? [Color(white: 0.14), Color(white: 0.10)]
                                            : [Color.white, Color(red: 0.97, green: 0.98, blue: 1.0)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ))
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: CornerRadius.lg)
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
                            RoundedRectangle(cornerRadius: CornerRadius.md)
                                .fill(selectedExperience == level.0 
                                    ? AnyShapeStyle(Color.blue.opacity(0.1))
                                    : AnyShapeStyle(LinearGradient(
                                        colors: colorScheme == .dark 
                                            ? [Color(white: 0.14), Color(white: 0.10)]
                                            : [Color.white, Color(red: 0.97, green: 0.98, blue: 1.0)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ))
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: CornerRadius.md)
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
                            RoundedRectangle(cornerRadius: CornerRadius.md)
                                .fill(selectedStrengthLevel == level 
                                    ? AnyShapeStyle(Color.orange.opacity(0.15))
                                    : AnyShapeStyle(LinearGradient(
                                        colors: colorScheme == .dark 
                                            ? [Color(white: 0.14), Color(white: 0.10)]
                                            : [Color.white, Color(red: 0.97, green: 0.98, blue: 1.0)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ))
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: CornerRadius.md)
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
                            RoundedRectangle(cornerRadius: CornerRadius.lg)
                                .fill(selectedWorkoutLocation == loc.0 
                                    ? AnyShapeStyle(loc.3.opacity(0.2))
                                    : AnyShapeStyle(LinearGradient(
                                        colors: colorScheme == .dark 
                                            ? [Color(white: 0.14), Color(white: 0.10)]
                                            : [Color.white, Color(red: 0.97, green: 0.98, blue: 1.0)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ))
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: CornerRadius.lg)
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
        let needsSelection = isSelected && !confirmedAccommodations.contains(area)
        
        VStack(alignment: .leading, spacing: 0) {
            // Main selection button
            Button(action: {
                if isSelected {
                    selectedLimitations.remove(area)
                    limitationAccommodations.removeValue(forKey: area)
                    confirmedAccommodations.remove(area)
                } else {
                    selectedLimitations.insert(area)
                    // Default to "Be Careful" but mark as needing explicit selection
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
                    
                    // Show status indicator
                    if needsSelection {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundColor(.orange)
                    } else {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(isSelected ? .blue : .gray.opacity(0.3))
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: CornerRadius.md)
                        .fill(isSelected 
                            ? AnyShapeStyle(needsSelection ? Color.orange.opacity(0.08) : Color.blue.opacity(0.1))
                            : AnyShapeStyle(LinearGradient(
                                colors: colorScheme == .dark 
                                    ? [Color(white: 0.14), Color(white: 0.10)]
                                    : [Color.white, Color(red: 0.97, green: 0.98, blue: 1.0)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.md)
                        .stroke(isSelected ? (needsSelection ? Color.orange : Color.blue) : Color.clear, lineWidth: 1.5)
                )
            }
            .foregroundColor(.primary)
            
            // Auto-expanded options when selected
            if isSelected {
                VStack(spacing: 6) {
                    // Helper text
                    if needsSelection {
                        HStack(spacing: 6) {
                            Image(systemName: "hand.point.down.fill")
                                .font(.system(size: 12))
                            Text("Select an accommodation level")
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        .foregroundColor(.orange)
                        .padding(.top, 12)
                        .padding(.bottom, 4)
                        .padding(.leading, 12)
                    }
                    
                    // Options as buttons (not dropdown)
                    ForEach(AccommodationLevel.allCases, id: \.self) { level in
                        Button(action: {
                            limitationAccommodations[area] = level
                            confirmedAccommodations.insert(area)
                        }) {
                            HStack(spacing: 10) {
                                Image(systemName: level.icon)
                                    .font(.ds_bodyMedium)
                                    .foregroundColor(level.color)
                                    .frame(width: 22)
                                
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(level.displayName)
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                    Text(level.description)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                                
                                Spacer()
                                
                                if limitationAccommodations[area] == level {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 18))
                                        .foregroundColor(level.color)
                                }
                            }
                            .padding(.horizontal, Spacing.sm)
                            .padding(.vertical, 9)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(limitationAccommodations[area] == level 
                                        ? AnyShapeStyle(level.color.opacity(0.12))
                                        : AnyShapeStyle(LinearGradient(
                                            colors: colorScheme == .dark 
                                                ? [Color(white: 0.14), Color(white: 0.10)]
                                                : [Color.white, Color(red: 0.97, green: 0.98, blue: 1.0)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ))
                                    )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(limitationAccommodations[area] == level ? level.color.opacity(0.5) : Color.clear, lineWidth: 1.5)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 4)
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
                                        .fill(selectedDays == day 
                                            ? AnyShapeStyle(Color.blue)
                                            : AnyShapeStyle(LinearGradient(
                                                colors: colorScheme == .dark 
                                                    ? [Color(white: 0.14), Color(white: 0.10)]
                                                    : [Color.white, Color(red: 0.97, green: 0.98, blue: 1.0)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ))
                                        )
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
    
    // MARK: - Profile Photo Step (Optional)
    private var profilePhotoStepContent: some View {
        VStack(spacing: 32) {
            // Large avatar circle with add button
            Button(action: {
                HapticManager.impact(.light)
                showingPhotoOptions = true
            }) {
                ZStack {
                    // Outer ring
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: profilePhotoImage != nil 
                                    ? [Color.green.opacity(0.6), Color.green.opacity(0.3)]
                                    : [Color.blue.opacity(0.4), Color.purple.opacity(0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 4
                        )
                        .frame(width: 180, height: 180)
                    
                    // Avatar circle
                    if let image = profilePhotoImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 160, height: 160)
                            .clipShape(Circle())
                    } else {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.blue.opacity(0.2), Color.purple.opacity(0.15)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 160, height: 160)
                            .overlay(
                                VStack(spacing: 8) {
                                    Image(systemName: "camera.fill")
                                        .font(.system(size: 40))
                                        .foregroundColor(.blue.opacity(0.7))
                                    Text("Add Photo")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundColor(.blue.opacity(0.8))
                                }
                            )
                    }
                    
                    // Edit badge when photo exists
                    if profilePhotoImage != nil {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 44, height: 44)
                            .overlay(
                                Image(systemName: "pencil")
                                    .font(.ds_heading3)
                                    .foregroundColor(.white)
                            )
                            .offset(x: 60, y: 60)
                    }
                }
            }
            .buttonStyle(PlainButtonStyle())
            
            // Instructions
            VStack(spacing: 8) {
                Text(profilePhotoImage != nil ? "Looking great! 👍" : "Tap to add a profile photo")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text("Your photo helps friends recognize you when sharing workouts")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            
            // Skip button (only show if no photo)
            if profilePhotoImage == nil {
                Button(action: {
                    navigateTo(.contacts)
                }) {
                    Text("Skip for now")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .underline()
                }
                .padding(.top, 8)
            }
            
            // Loading indicator
            if isUploadingPhoto {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Processing...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 32)
        .confirmationDialog("Profile Photo", isPresented: $showingPhotoOptions) {
            Button("Take Photo") {
                showingCamera = true
            }
            Button("Choose from Library") {
                showingPhotoPicker = true
            }
            if profilePhotoImage != nil {
                Button("Remove Photo", role: .destructive) {
                    profilePhotoImage = nil
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showingPhotoPicker) {
            OnboardingPhotoPicker(image: $profilePhotoImage)
        }
        .fullScreenCover(isPresented: $showingCamera) {
            OnboardingCameraPicker { image in
                processOnboardingPhoto(image)
            }
        }
    }
    
    /// Process and resize the photo for onboarding
    private func processOnboardingPhoto(_ image: UIImage) {
        // Resize to reasonable dimensions (300x300 max) for profile photos
        let maxDimension: CGFloat = 300
        let scaledImage = resizeImageForOnboarding(image, maxDimension: maxDimension)
        profilePhotoImage = scaledImage
    }
    
    /// Resize image maintaining aspect ratio
    private func resizeImageForOnboarding(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let aspectRatio = size.width / size.height
        
        var newSize: CGSize
        if size.width > size.height {
            newSize = CGSize(width: maxDimension, height: maxDimension / aspectRatio)
        } else {
            newSize = CGSize(width: maxDimension * aspectRatio, height: maxDimension)
        }
        
        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        image.draw(in: CGRect(origin: .zero, size: newSize))
        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return newImage ?? image
    }
    
    // MARK: - Contacts Permission Step (Optional)
    private var contactsStepContent: some View {
        VStack(spacing: 16) {
            // Icon
            if contactsPermissionGranted {
                // Success state
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [Color.green.opacity(0.2), Color.green.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 70, height: 70)
                    
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.green)
                }
            } else {
                // Contacts icon
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [Color.blue.opacity(0.2), Color.purple.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 70, height: 70)
                    
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(
                            LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                }
            }
            
            // Title and description
            VStack(spacing: 6) {
                Text(contactsPermissionGranted ? "You're Connected! 🎉" : "Train with Friends")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Text(contactsPermissionGranted 
                    ? "We'll notify you when your contacts join Fit33"
                    : "Allow contacts access to find friends who are already on Fit33")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.md)
            }
            
            // Benefits list - compact
            if !contactsPermissionGranted {
                VStack(alignment: .leading, spacing: 10) {
                    compactBenefitRow(
                        icon: "trophy.fill",
                        color: .orange,
                        title: "Challenge Friends",
                        subtitle: "Compete with step challenges, workout streaks & more"
                    )
                    
                    compactBenefitRow(
                        icon: "paperplane.fill",
                        color: .blue,
                        title: "Share Workouts",
                        subtitle: "Send workouts you create to friends who need motivation"
                    )
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }
            
            // Permission button
            if !contactsPermissionGranted {
                VStack(spacing: 6) {
                    Button(action: {
                        HapticManager.impact(.medium)
                        print("📇 [CONTACTS FLOW] ════════════════════════════════════════════════")
                        print("📇 [CONTACTS FLOW] 👆 Allow Contacts button tapped")
                        print("📇 [CONTACTS FLOW] Current authorization: \(contactsService.authorizationStatus.rawValue)")
                        print("📇 [CONTACTS FLOW] User's verified phone: \(phoneNumber.isEmpty ? "(none)" : fullPhoneNumber)")
                        print("📇 [CONTACTS FLOW] isPhoneVerified: \(isPhoneVerified)")
                        
                        // Check if already denied - need to go to settings
                        if contactsService.permissionDenied {
                            print("📇 [CONTACTS FLOW] ⚠️ Permission previously denied, opening Settings...")
                            if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(settingsUrl)
                            }
                            return
                        }
                        
                        Task {
                            contactsPermissionRequested = true
                            print("📇 [CONTACTS FLOW] 🔄 Requesting contact access from iOS...")
                            
                            let granted = await contactsService.requestAccess()
                            // Note: requestAccess() already calls fetchContactsAndFindFriends() if granted
                            
                            print("📇 [CONTACTS FLOW] ════════════════════════════════════════════════")
                            print("📇 [CONTACTS FLOW] Permission result: \(granted ? "✅ GRANTED" : "❌ DENIED")")
                            
                            if granted {
                                print("📇 [CONTACTS FLOW] 📊 Contact scan results:")
                                print("   └─ Phone numbers found: \(contactsService.contactPhoneNumbers.count)")
                                print("   └─ Emails found: \(contactsService.contactEmails.count)")
                                print("   └─ Fit33 users matched: \(contactsService.suggestedFriends.count)")
                                
                                if !contactsService.suggestedFriends.isEmpty {
                                    print("📇 [CONTACTS FLOW] 🎉 Friends found on Fit33:")
                                    for (i, friend) in contactsService.suggestedFriends.prefix(5).enumerated() {
                                        print("   \(i + 1). \(friend.name ?? "Unknown") (@\(friend.username ?? "no-username"))")
                                    }
                                    if contactsService.suggestedFriends.count > 5 {
                                        print("   ... and \(contactsService.suggestedFriends.count - 5) more")
                                    }
                                } else {
                                    print("📇 [CONTACTS FLOW] 📭 No contacts found on Fit33 yet")
                                }
                            }
                            print("📇 [CONTACTS FLOW] ════════════════════════════════════════════════")
                            
                            await MainActor.run {
                                contactsPermissionGranted = granted
                                if granted {
                                    print("📇 [CONTACTS FLOW] ➡️ Auto-navigating to Add Friends step...")
                                    HapticManager.notification(.success)
                                    
                                    // Small delay for UI feedback, then navigate
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                        navigateTo(.addFriends)
                                    }
                                }
                            }
                        }
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: contactsService.permissionDenied ? "gear" : "person.crop.circle.badge.plus")
                                .font(.ds_labelLarge)
                            Text(contactsService.permissionDenied ? "Open Settings" : "Allow Contacts Access")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.sm)
                        .background(
                            LinearGradient(
                                colors: [.blue, .blue.opacity(0.8), .purple.opacity(0.7)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(CornerRadius.md)
                    }
                    .padding(.horizontal, 20)
                    
                    // Privacy note
                    HStack(spacing: 4) {
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 9))
                            .foregroundColor(.green.opacity(0.8))
                        Text("Your contacts are never shared or stored on our servers")
                            .font(.ds_caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.top, 8)
        .onAppear {
            // Refresh and check current status on appear
            contactsService.checkAuthorizationStatus()
            contactsPermissionGranted = contactsService.canAccessContacts
            print("📇 [ONBOARDING] Contacts step appeared - status: \(contactsService.authorizationStatus.rawValue), canAccess: \(contactsService.canAccessContacts)")
        }
    }
    
    private func compactBenefitRow(icon: String, color: Color, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 32, height: 32)
                
                Image(systemName: icon)
                    .font(.ds_labelMedium)
                    .foregroundColor(color)
            }
            
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Text(subtitle)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            
            Spacer()
        }
    }
    
    
    
    
    // MARK: - Add Friends Step (after contacts permission)
    private var addFriendsStepContent: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.ds_bodyRegular)
                
                TextField("Search by name", text: $friendSearchText)
                    .font(.body)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                
                if !friendSearchText.isEmpty {
                    Button(action: { friendSearchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(Color(.systemGray6))
            .cornerRadius(CornerRadius.md)
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 16)
            
            // Friends list
            if contactsService.isLoading || isLoadingFriends {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("Finding your friends...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 60)
            } else if filteredSuggestedFriends.isEmpty {
                // Empty state
                VStack(spacing: 20) {
                    Image(systemName: contactsPermissionGranted ? "person.2.slash" : "person.crop.circle.badge.questionmark")
                        .font(.system(size: 50))
                        .foregroundColor(.secondary.opacity(0.5))
                    
                    Text(contactsPermissionGranted 
                        ? (friendSearchText.isEmpty ? "No contacts on Fit33 yet" : "No results for \"\(friendSearchText)\"")
                        : "Enable contacts to find friends")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    Text(contactsPermissionGranted
                        ? "When your contacts join, you'll be notified!"
                        : "Go back and allow contacts access")
                        .font(.subheadline)
                        .foregroundColor(.secondary.opacity(0.8))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 60)
                .padding(.horizontal, 32)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(filteredSuggestedFriends) { friend in
                            onboardingFriendRow(friend: friend)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 100) // Space for continue button
                }
            }
            
            Spacer()
        }
        .onAppear {
            print("👥 [ADD FRIENDS] Step appeared")
            print("   └─ contactsPermissionGranted: \(contactsPermissionGranted)")
            print("   └─ contactsService.canAccessContacts: \(contactsService.canAccessContacts)")
            print("   └─ contactsService.isLoading: \(contactsService.isLoading)")
            print("   └─ contactsService.hasCheckedContacts: \(contactsService.hasCheckedContacts)")
            print("   └─ suggestedFriends.count: \(contactsService.suggestedFriends.count)")
            print("   └─ contactEmails.count: \(contactsService.contactEmails.count)")
            print("   └─ contactPhoneNumbers.count: \(contactsService.contactPhoneNumbers.count)")
            
            // Refresh contacts and find friends if we have permission but haven't checked yet
            // or if the suggested friends list is empty (might need refresh)
            if contactsService.canAccessContacts {
                if !contactsService.hasCheckedContacts || contactsService.suggestedFriends.isEmpty {
                    print("👥 [ADD FRIENDS] Fetching/refreshing contacts and friends...")
                    Task {
                        isLoadingFriends = true
                        await contactsService.fetchContactsAndFindFriends()
                        isLoadingFriends = false
                        print("👥 [ADD FRIENDS] Fetch complete - found \(contactsService.suggestedFriends.count) friends")
                    }
                } else {
                    print("👥 [ADD FRIENDS] Already have \(contactsService.suggestedFriends.count) suggested friends - no refresh needed")
                }
            }
        }
    }
    
    // Filtered list based on search
    private var filteredSuggestedFriends: [SuggestedFriend] {
        let friends = contactsService.suggestedFriends.filter { !$0.isFriend }
        
        if friendSearchText.isEmpty {
            return friends
        }
        
        let searchLower = friendSearchText.lowercased()
        return friends.filter { friend in
            if let name = friend.name, name.lowercased().contains(searchLower) {
                return true
            }
            if let username = friend.username, username.lowercased().contains(searchLower) {
                return true
            }
            return false
        }
    }
    
    private func onboardingFriendRow(friend: SuggestedFriend) -> some View {
        let isRequestSent = sentFriendRequests.contains(friend.userId) || friend.hasOutgoingRequest
        let isLoading = loadingFriendRequests.contains(friend.userId)
        let hasFailed = failedFriendRequests.contains(friend.userId)
        
        return HStack(spacing: 14) {
            // Avatar (cached)
            CachedFriendPhoto(
                friendId: friend.userId.uuidString,
                photoUrl: friend.profilePhotoUrl,
                name: friend.name ?? friend.username ?? "?",
                size: 50,
                showGradientRing: false,
                gradientColors: [.blue, .purple]
            )
            
            // Name & username
            VStack(alignment: .leading, spacing: 2) {
                Text(friend.name ?? "Unknown")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                if let username = friend.username, !username.isEmpty {
                    Text("@\(username)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Add button with loading and error states
            Button(action: {
                guard !isRequestSent && !isLoading else { return }
                
                // Clear any previous failure
                failedFriendRequests.remove(friend.userId)
                
                // Set loading state
                loadingFriendRequests.insert(friend.userId)
                HapticManager.impact(.medium)
                
                print("👆 [ADD FRIEND] Tapped Add for \(friend.name ?? "Unknown") (ID: \(friend.userId))")
                
                Task {
                    let success = await FriendService.shared.sendFriendRequest(toUserId: friend.userId)
                    
                    await MainActor.run {
                        loadingFriendRequests.remove(friend.userId)
                        
                        if success {
                            print("✅ [ADD FRIEND] Request sent successfully to \(friend.name ?? "Unknown")")
                            sentFriendRequests.insert(friend.userId)
                            HapticManager.notification(.success)
                        } else {
                            print("❌ [ADD FRIEND] Failed to send request to \(friend.name ?? "Unknown")")
                            failedFriendRequests.insert(friend.userId)
                            HapticManager.notification(.error)
                        }
                    }
                }
            }) {
                HStack(spacing: 6) {
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.8)
                            .tint(.white)
                    } else {
                        Image(systemName: isRequestSent ? "checkmark" : (hasFailed ? "exclamationmark.triangle" : "plus"))
                            .font(.system(size: 12, weight: .bold))
                    }
                    Text(isRequestSent ? "Sent" : (hasFailed ? "Retry" : (isLoading ? "" : "Add")))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                .foregroundColor(isRequestSent ? .green : (hasFailed ? .orange : .white))
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.xs)
                .background(
                    Group {
                        if isRequestSent {
                            Color.green.opacity(0.15)
                        } else if hasFailed {
                            Color.orange.opacity(0.15)
                        } else {
                            LinearGradient(colors: [.blue, .blue.opacity(0.8)], startPoint: .leading, endPoint: .trailing)
                        }
                    }
                )
                .cornerRadius(20)
            }
            .disabled(isRequestSent || isLoading)
        }
        .padding(.vertical, Spacing.sm)
        .padding(.horizontal, Spacing.md)
        .background(Color(.systemGray6).opacity(0.5))
        .cornerRadius(14)
    }
    
    private func friendInitialsCircle(friend: SuggestedFriend) -> some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [.blue.opacity(0.6), .purple.opacity(0.4)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 50, height: 50)
            .overlay(
                Text(friend.initials)
                    .font(.ds_heading3)
                    .foregroundColor(.white)
            )
    }
    
    private func confirmationRowSimple(title: String, value: String, editStep: OnboardingStep? = nil, focusField: FocusedField? = nil) -> some View {
        Button(action: {
            if let step = editStep {
                isEditingFromConfirmation = true
                navigateTo(step)
                
                // Auto-focus the field after a short delay
                if let field = focusField {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        focusedField = field
                    }
                }
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
        let inches = String(digits.dropFirst().prefix(2))
        if inches.isEmpty {
            return "\(feet)'0\""
        }
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
    
    // MARK: - Background with Animated Orbs
    private var backgroundGradient: some View {
        AnimatedOrbBackground.onboarding(colorScheme: colorScheme)
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
    
    
    // MARK: - Auth Step (Non-Standard Mode - used before user starts interacting)
    private var authStep: some View {
        let keyboardUp = keyboardObserver.keyboardHeight > 0
        let showingConfirmPassword = isSignUp && isOnConfirmPasswordStep
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
                                    .frame(height: 60)
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
            
            // Floating Continue Button - only show when keyboard is open and NOT in standard mode
            if keyboardUp && !hasStartedAuth {
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        // Back button - show when on confirm password step
                        if isSignUp && isOnConfirmPasswordStep {
                            Button(action: {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                    isOnConfirmPasswordStep = false
                                    confirmPassword = ""  // Clear confirm password
                                }
                                // Focus back on first password after animation
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                                    focusedField = .password
                                }
                            }) {
                                Image(systemName: "chevron.left")
                                    .font(.ds_labelLarge)
                                    .foregroundColor(.gray)
                                    .frame(width: 52, height: 52)
                                    .background(Circle().fill(Color(.systemGray6)))
                                    .overlay(Circle().stroke(Color.gray.opacity(0.3), lineWidth: 1.5))
                            }
                        }
                        
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
                                    .font(.ds_heading2)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 14, weight: .bold))
                            }
                        }
                        .foregroundColor(isAuthFormValid && !supabaseManager.isLoading ? .white : .gray)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.md)
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
                }
                .padding(.horizontal, 24)
                .padding(.bottom, keyboardObserver.keyboardHeight + 10)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                .animation(.easeOut(duration: 0.25), value: keyboardObserver.keyboardHeight)
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: hasStartedAuth)
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
                    .padding(.vertical, hasStartedAuth ? 10 : 11)
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
                    .padding(.vertical, hasStartedAuth ? 10 : 11)
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
            // Fit33 Logo - Large and centered (only show when NOT in standard header mode)
            if !keyboardUp && !hasStartedAuth {
                Image("fit33-logo")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 240, height: 95)
                    .clipped()
                    .padding(.bottom, 20)
            }
            
            // Header - only show when NOT in standard header mode
            if !hasStartedAuth {
                VStack(spacing: keyboardUp ? 4 : 6) {
                    Text(isSignUp ? "Create Account" : "Welcome Back")
                        .font(.system(size: keyboardUp ? 22 : 26, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    
                    if !keyboardUp {
                        Text(isSignUp ? "Join the club" : "Continue your journey")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                    .frame(height: keyboardUp ? 12 : 20)
            }
                
            // Auth Toggle - always visible
            authToggleButtons
                .padding(.bottom, hasStartedAuth ? 16 : (keyboardUp ? 12 : 20))
                
                // Form fields - compact spacing when in standard mode
                VStack(spacing: hasStartedAuth ? 12 : (keyboardUp ? 10 : 14)) {
                    OnboardingTextField(
                        icon: "envelope.fill",
                        placeholder: "Email",
                        text: $email,
                        keyboardType: .emailAddress,
                        focusedField: $focusedField,
                        fieldValue: .email,
                        isValid: !email.isEmpty && email.contains("@")
                    )
                    .id("emailField")
                    
                    // Unified password field - no flickering when toggling Sign Up/Sign In
                    PasswordTextField(
                        placeholder: isSignUp && isOnConfirmPasswordStep ? "Re-enter Password" : "Password",
                        text: isSignUp && isOnConfirmPasswordStep ? $confirmPassword : $password,
                        isVisible: isSignUp && isOnConfirmPasswordStep ? $showConfirmPassword : $showPassword,
                        focusedField: $focusedField,
                        fieldValue: isSignUp && isOnConfirmPasswordStep ? .confirmPassword : .password,
                        showMatchIndicator: isSignUp && isOnConfirmPasswordStep,
                        passwordsMatch: passwordsMatch,
                        isValid: isSignUp && isOnConfirmPasswordStep ? (passwordsMatch && !confirmPassword.isEmpty) : (isSignUp ? isPasswordValid : !password.isEmpty)
                    )
                    .id("unifiedPassword")
                    .onChange(of: isOnConfirmPasswordStep) { _, newValue in
                        // Maintain focus during password step transitions with aggressive restoration
                        if newValue {
                            // Switched to confirm password - set focus multiple times
                            print("🔐 Switching to confirm password field")
                            DispatchQueue.main.async {
                                focusedField = .confirmPassword
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                focusedField = .confirmPassword
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                focusedField = .confirmPassword
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                focusedField = .confirmPassword
                            }
                        } else {
                            // Switched back to first password
                            print("🔐 Switching back to first password field")
                            DispatchQueue.main.async {
                                focusedField = .password
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                focusedField = .password
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                focusedField = .password
                            }
                        }
                    }
                    
                    // Password requirements (show once user starts typing, stay visible even when met)
                    if isSignUp && !isOnConfirmPasswordStep && !password.isEmpty {
                        PasswordRequirementsView(
                            hasMinLength: hasMinLength,
                            hasUppercase: hasUppercase,
                            hasLowercase: hasLowercase,
                            hasNumber: hasNumber,
                            hasSpecialChar: hasSpecialChar
                        )
                        .padding(.top, hasStartedAuth ? -4 : 0)
                    }
                    
                    // Show message if passwords don't match
                    if isSignUp && isOnConfirmPasswordStep && !confirmPassword.isEmpty && !passwordsMatch {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundColor(.orange)
                            Text("Passwords don't match")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.top, hasStartedAuth ? 2 : 4)
                    }
                    
                    // Terms and Services checkbox (only for sign up, show after passwords match on confirm step)
                    if isSignUp && isOnConfirmPasswordStep && passwordsMatch {
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
                        .padding(.top, hasStartedAuth ? 8 : 12)
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
                                        .padding(.horizontal, Spacing.md)
                                        .padding(.vertical, Spacing.xs)
                                        .background(Color.blue)
                                        .cornerRadius(CornerRadius.sm)
                                }
                                
            Button(action: {
                                    sendPasswordReset()
                                }) {
                                    Text("Reset Password")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.blue)
                                        .padding(.horizontal, Spacing.md)
                                        .padding(.vertical, Spacing.xs)
                                        .background(Color.blue.opacity(0.1))
                                        .cornerRadius(CornerRadius.sm)
                                }
                            }
                        }
                        .padding(hasStartedAuth ? 10 : 12)
                .background(
                            RoundedRectangle(cornerRadius: CornerRadius.md)
                                .fill(Color.orange.opacity(0.1))
                                .overlay(
                                    RoundedRectangle(cornerRadius: CornerRadius.md)
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
                        .padding(hasStartedAuth ? 10 : 12)
                        .background(
                            RoundedRectangle(cornerRadius: CornerRadius.md)
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
                                    .font(.ds_heading3)
                                    .foregroundColor(.blue)
                                
                                Text(authProviderHintMessage)
                                    .font(.subheadline)
                                    .foregroundColor(.primary)
                                    .multilineTextAlignment(.leading)
                            }
                            .padding(hasStartedAuth ? 12 : 16)
                            .frame(maxWidth: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: CornerRadius.md)
                                    .fill(Color.blue.opacity(0.1))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: CornerRadius.md)
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
                                    .font(.ds_labelLarge)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, Spacing.md)
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
                            if email.isEmpty || !email.contains("@") {
                                // Show helpful message
                                errorMessage = "Please enter your email address above first"
                                showError = true
                            } else {
                                sendPasswordReset()
                            }
                        }) {
                            Text("Forgot Password?")
                                .font(.subheadline)
                                .foregroundColor(.blue)
                        }
                        .padding(.top, hasStartedAuth ? 2 : 4)
                    }
                    
                    // MARK: - Primary Sign In/Continue Button (only shows when NOT in standard mode)
                    // Hidden by default - appears when user has entered email and password
                    if keyboardObserver.keyboardHeight == 0 && !email.isEmpty && !password.isEmpty && !hasStartedAuth {
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
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .scaleEffect(0.8)
                                } else {
                                    Text(isEditingFromConfirmation ? "Save" : (isSignUp ? "Create Account" : "Sign In"))
                                        .font(.ds_heading2)
                                    Image(systemName: "arrow.right")
                                        .font(.system(size: 14, weight: .bold))
                                }
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Spacing.md)
                            .background(
                                Group {
                                    if isAuthFormValid && !supabaseManager.isLoading {
                                        Capsule()
                                            .fill(
                                                LinearGradient(
                                                    colors: [Color.blue, Color.blue.opacity(0.9), Color.cyan.opacity(0.8)],
                                                    startPoint: .leading,
                                                    endPoint: .trailing
                                                )
                                            )
                                            .shadow(color: Color.blue.opacity(0.4), radius: 8, x: 0, y: 4)
                                    } else {
                                        Capsule()
                                            .fill(Color.gray.opacity(0.3))
                                    }
                                }
                            )
                        }
                        .disabled(supabaseManager.isLoading || !isAuthFormValid)
                        .opacity(supabaseManager.isLoading || !isAuthFormValid ? 0.6 : 1.0)
                        .animation(.easeInOut(duration: 0.2), value: isAuthFormValid)
                        .padding(.top, hasStartedAuth ? 12 : 16)
                    }
                    
                    // MARK: - Social Login Section (hidden when keyboard is up or in standard mode)
                    if keyboardObserver.keyboardHeight == 0 && !hasStartedAuth {
                        VStack(spacing: 16) {
                            SocialLoginDivider()
                                .padding(.top, 8)
                            
                            // Apple Sign-In Button
                            SignInWithAppleButton {
                                handleAppleSignIn()
                            }
                            
                            // Google Sign-In Button
                            SignInWithGoogleButton {
                                handleGoogleSignIn()
                            }
                        }
                        .padding(.top, 20)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
            .padding(.horizontal, hasStartedAuth ? 24 : 28)
            .animation(.spring(response: 0.5, dampingFraction: 0.85), value: hasStartedAuth)
        }
    }
    
    // MARK: - Basics Step (Birthday + Gender)
    // Parse birthday from MM/DD/YYYY or DD/MM/YYYY format based on locale
    private var birthdayDate: Date? {
        let parts = birthday.split(separator: "/")
        guard parts.count == 3 else { return nil }
        
        let month: Int
        let day: Int
        let year: Int
        
        if usesMonthFirstDate {
            // MM/DD/YYYY format (US)
            guard let m = Int(parts[0]), let d = Int(parts[1]), let y = Int(parts[2]) else { return nil }
            month = m
            day = d
            year = y
        } else {
            // DD/MM/YYYY format (UK, most of world)
            guard let d = Int(parts[0]), let m = Int(parts[1]), let y = Int(parts[2]) else { return nil }
            day = d
            month = m
            year = y
        }
        
        guard month >= 1 && month <= 12,
              day >= 1 && day <= 31,
              year >= 1900 && year <= Calendar.current.component(.year, from: Date())
        else { return nil }

        var components = DateComponents()
        components.month = month
        components.day = day
        components.year = year

        // Validate actual calendar date (catches Feb 30, Apr 31, etc.)
        guard let date = Calendar.current.date(from: components),
              Calendar.current.component(.month, from: date) == month,
              Calendar.current.component(.day, from: date) == day,
              Calendar.current.component(.year, from: date) == year
        else { return nil }

        return date
    }
    
    private var isBirthdayValid: Bool {
        birthdayDate != nil
    }
    
    private var calculatedAge: Int {
        guard let date = birthdayDate else { return 0 }
        return Calendar.current.dateComponents([.year], from: date, to: Date()).year ?? 0
    }
    
    /// Birthday in ISO format (YYYY-MM-DD) for database storage
    /// Converts from locale-specific format (MM/DD/YYYY or DD/MM/YYYY) to ISO
    private var birthdayISO: String? {
        guard let date = birthdayDate else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
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
                        placeholder: usesMonthFirstDate ? "11/16/1994" : "16/11/1994",
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
            let trimmed = heightCm.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return false }
            // Try parsing as Int (handles "175") or Double then Int (handles "175.0")
            let cm: Int?
            if let intValue = Int(trimmed) {
                cm = intValue
            } else if let doubleValue = Double(trimmed) {
                cm = Int(doubleValue)
            } else {
                cm = nil
            }
            guard let validCm = cm else { return false }
            return validCm >= 90 && validCm <= 270  // Valid height range in cm
        } else {
            return parsedHeightFeetInches != nil
        }
    }
    
    private var isWeightValid: Bool {
        let trimmed = weight.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        
        // Handle both "." and "," as decimal separators for international support
        let normalized = trimmed.replacingOccurrences(of: ",", with: ".")
        guard let w = Double(normalized), w > 0 else { return false }
        
        // Valid range: 50-700 lbs or 23-320 kg (covers reasonable human weights)
        if weightUnit == .lbs {
            return w >= 50 && w <= 700
        } else {
            return w >= 23 && w <= 320
        }
    }
    
    // Convert height to cm for storage
    private var heightInCm: Int {
        if heightUnit == .cm {
            let trimmed = heightCm.trimmingCharacters(in: .whitespaces)
            if let intValue = Int(trimmed) {
                return intValue
            } else if let doubleValue = Double(trimmed) {
                return Int(doubleValue)
            }
            return 0
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
                                    .font(.ds_bodyMedium)
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
                    .padding(Spacing.md)
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
                                .font(.ds_bodyMedium)
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
                    .padding(Spacing.md)
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
        // Locale-aware weight descriptions
        let strengthLevels: [(StrengthProfileRecommendationEngine.StrengthLevel, String, String, String, Color)] = [
            (.veryLight, "📱", "Light Items", weightUnit == .lbs ? "Books, phones (~2 lbs)" : "Books, phones (~1 kg)", .gray),
            (.light, "🥛", "Milk Jug", weightUnit == .lbs ? "Lift easily (~8 lbs)" : "Lift easily (~4 kg)", .green),
            (.moderate, "🎳", "Bowling Ball", weightUnit == .lbs ? "Comfortable (~14 lbs)" : "Comfortable (~6 kg)", .blue),
            (.strong, "🧳", "Heavy Suitcase", weightUnit == .lbs ? "Handle heavy (~40 lbs)" : "Handle heavy (~18 kg)", .orange),
            (.veryStrong, "🏋️", "Heavy Weights", weightUnit == .lbs ? "Gym weights (~60+ lbs)" : "Gym weights (~27+ kg)", .red)
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
            question: "Where do you typically workout?",
            subtitle: "You can change this anytime"
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
            question: "What equipment do you have access to?",
            subtitle: "Select what you typically use (you can change this anytime)"
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
                                .font(.ds_bodyRegular)
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
                        .padding(.vertical, Spacing.sm)
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
                        .padding(Spacing.md)
                        .background(Color(.systemGray6))
                        .cornerRadius(CornerRadius.md)
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
                .padding(.vertical, Spacing.sm)
                .padding(.horizontal, 20)
                .background(
                    RoundedRectangle(cornerRadius: CornerRadius.md)
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
                            needsSelection: selectedLimitations.contains(area) && !confirmedAccommodations.contains(area),
                            action: {
                                selectionFeedback.selectionChanged()
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    if selectedLimitations.contains(area) {
                                        selectedLimitations.remove(area)
                                        limitationAccommodations.removeValue(forKey: area)
                                        confirmedAccommodations.remove(area)
                                    } else {
                                        selectedLimitations.insert(area)
                                        limitationAccommodations[area] = .beCareful
                                        // Don't add to confirmed yet - they need to explicitly choose
                                    }
                                }
                            },
                            onAccommodationChange: { newLevel in
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    limitationAccommodations[area] = newLevel
                                    confirmedAccommodations.insert(area)
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
            onContinue: { isEditingFromConfirmation ? returnToConfirmation() : navigateTo(.profilePhoto) },
            continueEnabled: true,
            continueLabel: isEditingFromConfirmation ? "Save" : "Continue",
            currentStep: 9,
            totalSteps: 10,
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
                .padding(.horizontal, Spacing.md)
                
                // Recommendation badge
                Text(recommendationText)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.blue)
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.xs)
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
                                navigateTo(.username)
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                    focusedField = .name
                                }
                            }
                            ConfirmationListRow(icon: "envelope.fill", label: "Email", value: email) {
                                isEditingFromConfirmation = true
                                navigateTo(.auth)
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                    focusedField = .email
                                }
                            }
                            ConfirmationListRow(icon: "at", label: "Username", value: username.isEmpty ? "Not set" : "@\(username)") {
                                isEditingFromConfirmation = true
                                navigateTo(.username)
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                    focusedField = .username
                                }
                            }
                        }
                        
                        // Personal Section
                        ConfirmationListSection(title: "PERSONAL") {
                            ConfirmationListRow(icon: "calendar", label: "Birthday", value: birthday) {
                                isEditingFromConfirmation = true
                                navigateTo(.basics)
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                    focusedField = .birthday
                                }
                            }
                            ConfirmationListRow(icon: "person.2.fill", label: "Gender", value: selectedGender ?? "Not set") {
                                isEditingFromConfirmation = true
                                navigateTo(.basics)
                            }
                            ConfirmationListRow(icon: "ruler", label: "Height", value: formattedHeight) {
                                isEditingFromConfirmation = true
                                navigateTo(.body)
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                    focusedField = .height
                                }
                            }
                            ConfirmationListRow(icon: "scalemass", label: "Weight", value: formattedWeight) {
                                isEditingFromConfirmation = true
                                navigateTo(.body)
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                    focusedField = .weight
                                }
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
                            // Show limitations with their accommodation levels
                            if !selectedLimitations.isEmpty {
                                ForEach(Array(selectedLimitations).sorted(by: { $0.rawValue < $1.rawValue }), id: \.self) { limitation in
                                    let accommodationLevel = limitationAccommodations[limitation] ?? .beCareful
                                    ConfirmationListRow(
                                        icon: "bandage.fill", 
                                        label: limitation.rawValue, 
                                        value: accommodationLevel.displayName
                                    ) {
                                        isEditingFromConfirmation = true
                                        navigateTo(.limitations)
                                    }
                                }
                            } else {
                                ConfirmationListRow(icon: "checkmark.circle.fill", label: "Limitations", value: "None") {
                                    isEditingFromConfirmation = true
                                    navigateTo(.limitations)
                                }
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
                Button(action: { navigateTo(.profilePhoto) }) {
                    Image(systemName: "chevron.left")
                        .font(.ds_labelLarge)
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
                    .frame(maxWidth: .infinity).padding(.vertical, Spacing.md)
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
        
        // Log validation state for debugging
        print("📝 [ONBOARDING] createAccountAndComplete called")
        print("📝 [ONBOARDING] isSignUp: \(isSignUp)")
        print("📝 [ONBOARDING] Email: \(email)")
        print("📝 [ONBOARDING] Password length: \(password.count)")
        print("📝 [ONBOARDING] isAuthenticated: \(supabaseManager.isAuthenticated)")
        
        // If user is already authenticated (social sign-in OR email/password created after phone verification)
        if supabaseManager.isAuthenticated {
            print("✅ User already authenticated - completing onboarding with full profile update")
            completeOnboarding()
            return
        }
        
        // Validate email format
        guard email.contains("@") && email.contains(".") else {
            print("❌ [ONBOARDING] Invalid email format: \(email)")
            SessionLogManager.shared.logAuthFailure(method: "email_signup", error: "Invalid email format")
            errorMessage = "Please enter a valid email address"
            showError = true
            return
        }
        
        // Validate password length
        guard password.count >= 6 else {
            print("❌ [ONBOARDING] Password too short: \(password.count) chars")
            SessionLogManager.shared.logAuthFailure(method: "email_signup", error: "Password too short (\(password.count) chars)")
            errorMessage = "Password must be at least 6 characters"
            showError = true
            return
        }
        
        if isSignUp {
            // For sign up: Create the Supabase account first
            Task {
                do {
                    // This code path should NOT be reached for email/password signups anymore
                    // Account is now created after phone verification (earlier in the flow)
                    print("⚠️ [ONBOARDING] This signup path should not be reached - account should already exist!")
                    print("🔐 [ONBOARDING] Starting signup for: \(email)")
                    try await supabaseManager.signUp(email: email, password: password, name: name.isEmpty ? "User" : name)
                    print("✅ [ONBOARDING] Signup successful, user authenticated: \(supabaseManager.isAuthenticated)")
                    print("👤 [ONBOARDING] Current user ID: \(supabaseManager.currentUser?.id.uuidString ?? "nil")")
                    
                    // Set the username after account creation
                    if !username.isEmpty {
                        print("📝 [ONBOARDING] Attempting to set username: @\(username)")
                        
                        // Small delay to ensure profile is created
                        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 second
                        
                        do {
                            try await supabaseManager.setUsername(username)
                            print("✅ [ONBOARDING] Username saved successfully: @\(username)")
                        } catch {
                            print("❌ [ONBOARDING] Failed to set username: \(error)")
                            print("❌ [ONBOARDING] Error details: \(error.localizedDescription)")
                        }
                    } else {
                        print("⚠️ [ONBOARDING] Username is empty, skipping")
                    }
                    
                    await MainActor.run {
                        // Account created successfully, now complete onboarding
                        print("🎉 [ONBOARDING] Completing onboarding flow...")
                        completeOnboarding()
                    }
                } catch {
                    // Log the auth failure for debugging
                    print("❌ [ONBOARDING] Signup failed: \(error)")
                    print("❌ [ONBOARDING] Error details: \(error.localizedDescription)")
                    SessionLogManager.shared.logAuthFailure(method: "email_signup", error: error.localizedDescription)
                    
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
        guard !email.isEmpty && email.contains("@") else {
            errorMessage = "Please enter a valid email address"
            showError = true
            return
        }
        
        // Clear previous states
        passwordResetSent = false
        showError = false
        errorMessage = ""
        emailAlreadyExists = false
        
        print("📧 [PASSWORD RESET] Sending reset email to: \(email)")
        
        Task {
            do {
                try await supabaseManager.resetPassword(email: email)
                await MainActor.run {
                    passwordResetSent = true
                    HapticManager.notification(.success)
                    print("✅ [PASSWORD RESET] Email sent successfully")
                    
                    // Auto-hide success message after 10 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                        passwordResetSent = false
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to send reset email. Please check your email address and try again."
                    showError = true
                    print("❌ [PASSWORD RESET] Failed: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func clearAuthMessages() {
        showError = false
        errorMessage = ""
        emailAlreadyExists = false
        passwordResetSent = false
        acceptedTerms = false  // Uncheck terms when switching modes
        // Reset password step and clear all password fields when switching auth modes
        let currentFocus = focusedField
        isOnConfirmPasswordStep = false
        password = ""  // Clear password
        confirmPassword = ""  // Clear confirm password
        // Maintain focus to keep keyboard up
        DispatchQueue.main.async {
            // Keep focus on email or password depending on what was focused
            if currentFocus == .email {
                focusedField = .email
            } else if currentFocus == .password || currentFocus == .confirmPassword {
                focusedField = .password
            } else {
                focusedField = currentFocus
            }
        }
        // Keep hasStartedAuth true so header stays visible when switching between Sign Up/Sign In
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
                        .font(.ds_bodyMedium)
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
                .padding(Spacing.md)
                .background(
                    RoundedRectangle(cornerRadius: CornerRadius.lg)
                        .fill(Color(.systemBackground))
                        .shadow(color: Color.blue.opacity(0.08), radius: 8, x: 0, y: 4)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.lg)
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
                    .padding(.vertical, Spacing.md)
                    .background(
                        LinearGradient(
                            colors: [Color.green, Color.mint],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(CornerRadius.lg)
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
        print("🔐 [AUTH] handleAuth() called")
        print("   └─ isSignUp: \(isSignUp)")
        print("   └─ email: '\(email)'")
        print("   └─ password length: \(password.count)")
        
        showError = false
        errorMessage = ""
        showAuthProviderHint = false
        
        if isSignUp {
            // For sign up: Just validate and proceed to username step
            // Account will be created on the confirmation screen
            print("🔐 [AUTH] Sign up mode - navigating to username step")
            // Clean up auth states
            hasStartedAuth = false
            isOnConfirmPasswordStep = false
            
            // Determine which field should be focused based on name state
            let targetField: FocusedField = name.isEmpty ? .name : .username
            print("🔐 [AUTH] Target field will be: \(targetField)")
            
            // Navigate
            navigateTo(.username)
            
            // Aggressively maintain keyboard by setting focus multiple times
            DispatchQueue.main.async {
                focusedField = targetField
                print("🔐 [AUTH] Focus set immediately: \(targetField)")
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                focusedField = targetField
                print("🔐 [AUTH] Focus reinforced at 50ms: \(targetField)")
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                focusedField = targetField
                print("🔐 [AUTH] Focus reinforced at 150ms: \(targetField)")
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                focusedField = targetField
                print("🔐 [AUTH] Focus reinforced at 300ms: \(targetField)")
            }
            print("🔐 [AUTH] Navigation initiated with focus on \(targetField)")
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
                    
                    // After sign-in, syncAllDataFromCloud() runs which updates hasCompletedOnboarding
                    // Give it a moment to complete, then check if user already completed onboarding
                    try? await Task.sleep(nanoseconds: 300_000_000) // 300ms for sync to complete
                    
                    await MainActor.run {
                        // Reload to get latest onboarding status from cloud sync
                        userManager.reloadCurrentUser()
                        
                        if userManager.hasCompletedOnboarding {
                            // Returning user - ContentView will show main app automatically
                            // because it observes userManager.hasCompletedOnboarding
                            print("✅ [EMAIL AUTH] Returning user signed in - onboarding complete, switching to main app")
                            // Don't navigate - ContentView will handle it
                        } else {
                            // New user or incomplete onboarding - continue onboarding flow
                            print("👤 [EMAIL AUTH] User needs onboarding - continuing to basics")
                            navigateTo(.basics)
                        }
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
    
    /// Upload the profile photo selected during onboarding to Supabase
    private func uploadOnboardingProfilePhoto(_ image: UIImage) async {
        guard SupabaseManager.shared.currentUser?.id != nil else {
            print("⚠️ [ONBOARDING] No user ID available for profile photo")
            return
        }
        
        // Compress to JPEG with good quality but small file size
        guard let imageData = image.jpegData(compressionQuality: 0.7) else {
            print("❌ [ONBOARDING] Failed to convert image to JPEG")
            return
        }
        
        do {
            let photoUrl = try await SupabaseManager.shared.uploadProfilePhoto(imageData: imageData)
            print("✅ [ONBOARDING] Profile photo uploaded: \(photoUrl)")
            
            // Cache the image locally for immediate display
            await MainActor.run {
                ProfilePhotoCache.shared.cacheImage(image)
            }
        } catch {
            print("❌ [ONBOARDING] Failed to upload profile photo: \(error)")
            // Don't block onboarding completion - photo upload is optional
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
        
        // Collect all onboarding data for logging
        let heightCmValue = Double(heightInCm)
        var weightKgValue: Double = 0
        if let w = Double(weight) {
            weightKgValue = weightUnit == .lbs ? w / 2.20462 : w
        }
        let ageValue = calculatedAge > 0 ? calculatedAge : nil
        
        let onboardingData: [String: Any] = [
            "name": name,
            "email": email.isEmpty ? (supabaseManager.currentUser?.email ?? "none") : email,
            "username": username.isEmpty ? "none" : username,
            "age": ageValue ?? 0,
            "gender": selectedGender ?? "not_specified",
            "height_cm": heightCmValue,
            "weight_kg": weightKgValue,
            "fitness_goals": selectedGoals.sorted().joined(separator: ", "),
            "experience_level": selectedExperience,
            "equipment": Array(selectedEquipment),
            "available_days": selectedDays,
            "workout_environment": selectedWorkoutLocation.rawValue,
            "limitations_count": selectedLimitations.count,
            "has_profile_photo": profilePhotoImage != nil,
            "is_authenticated": supabaseManager.isAuthenticated,
            "auth_provider": detectedAuthProvider,
            "session_duration_seconds": OnboardingSessionManager.shared.sessionDuration
        ]
        
        // Log the completion attempt
        Task {
            await supabaseManager.logOnboardingEvent(
                eventType: "onboarding_completed",
                stepName: "complete",
                eventData: onboardingData
            )
            
            // ═══════════════════════════════════════════════════════════════════
            // FIELD-LEVEL LOGGING: Log each field at "collected" stage
            // This captures exactly what was entered in the UI
            // ═══════════════════════════════════════════════════════════════════
            print("📊 [FIELD LOG] Logging all collected field values...")
            
            await supabaseManager.logOnboardingField(fieldName: "name", stage: "collected", value: name)
            await supabaseManager.logOnboardingField(fieldName: "email", stage: "collected", value: email.isEmpty ? supabaseManager.currentUser?.email : email)
            await supabaseManager.logOnboardingField(fieldName: "username", stage: "collected", value: username.isEmpty ? nil : username)
            await supabaseManager.logOnboardingField(fieldName: "birthday", stage: "collected", value: birthday, rawInput: birthday)
            await supabaseManager.logOnboardingField(fieldName: "age", stage: "collected", value: ageValue, rawInput: birthday, convertedValue: ageValue != nil ? "\(ageValue!) years" : nil)
            await supabaseManager.logOnboardingField(fieldName: "gender", stage: "collected", value: selectedGender)
            await supabaseManager.logOnboardingField(fieldName: "height_cm", stage: "collected", value: heightCmValue > 0 ? heightCmValue : nil, rawInput: heightUnit == .ftIn ? heightFeetInchesDigits : "\(heightCm) cm", convertedValue: "\(heightCmValue) cm")
            await supabaseManager.logOnboardingField(fieldName: "weight_kg", stage: "collected", value: weightKgValue > 0 ? weightKgValue : nil, rawInput: "\(weight) \(weightUnit.rawValue)", convertedValue: "\(weightKgValue) kg")
            await supabaseManager.logOnboardingField(fieldName: "fitness_goal", stage: "collected", value: selectedGoals.isEmpty ? nil : selectedGoals.sorted().joined(separator: ", "))
            await supabaseManager.logOnboardingField(fieldName: "experience_level", stage: "collected", value: selectedExperience.isEmpty ? nil : selectedExperience)
            await supabaseManager.logOnboardingField(fieldName: "equipment", stage: "collected", value: selectedEquipment.isEmpty ? nil : Array(selectedEquipment))
            await supabaseManager.logOnboardingField(fieldName: "available_days", stage: "collected", value: selectedDays > 0 ? selectedDays : nil)
            await supabaseManager.logOnboardingField(fieldName: "workout_environment", stage: "collected", value: selectedWorkoutLocation.rawValue)
        }
        
        // For OAuth users (Apple/Google/Facebook), create the profile NOW at the end of onboarding
        // This ensures we don't create "zombie" accounts if user abandons onboarding
        if supabaseManager.isAuthenticated {
            Task {
                // Log profile creation start
                await supabaseManager.logOnboardingEvent(
                    eventType: "profile_create_started",
                    stepName: "complete",
                    eventData: onboardingData
                )
                
                do {
                    // ═══════════════════════════════════════════════════════════════════
                    // FIELD-LEVEL LOGGING: Log each field at "sent_to_db" stage
                    // This captures exactly what we're sending to Supabase
                    // ═══════════════════════════════════════════════════════════════════
                    print("📊 [FIELD LOG] Logging values being sent to database...")
                    
                    let emailToSend = email.isEmpty ? (supabaseManager.currentUser?.email ?? "") : email
                    let heightToSend = heightCmValue > 0 ? heightCmValue : nil
                    let weightToSend = weightKgValue > 0 ? weightKgValue : nil
                    let goalsToSend = selectedGoals.isEmpty ? nil : selectedGoals.sorted().joined(separator: ", ")
                    let experienceToSend = selectedExperience.isEmpty ? nil : selectedExperience
                    let equipmentToSend = selectedEquipment.isEmpty ? nil : Array(selectedEquipment)
                    let daysToSend = selectedDays > 0 ? selectedDays : nil
                    
                    await supabaseManager.logOnboardingField(fieldName: "name", stage: "sent_to_db", value: name)
                    await supabaseManager.logOnboardingField(fieldName: "email", stage: "sent_to_db", value: emailToSend)
                    await supabaseManager.logOnboardingField(fieldName: "username", stage: "sent_to_db", value: username.isEmpty ? nil : username)
                    await supabaseManager.logOnboardingField(fieldName: "birthday", stage: "sent_to_db", value: birthdayISO, rawInput: birthday, convertedValue: birthdayISO)
                    await supabaseManager.logOnboardingField(fieldName: "age", stage: "sent_to_db", value: ageValue)
                    await supabaseManager.logOnboardingField(fieldName: "gender", stage: "sent_to_db", value: selectedGender)
                    await supabaseManager.logOnboardingField(fieldName: "height_cm", stage: "sent_to_db", value: heightToSend)
                    await supabaseManager.logOnboardingField(fieldName: "weight_kg", stage: "sent_to_db", value: weightToSend)
                    await supabaseManager.logOnboardingField(fieldName: "fitness_goal", stage: "sent_to_db", value: goalsToSend)
                    await supabaseManager.logOnboardingField(fieldName: "experience_level", stage: "sent_to_db", value: experienceToSend)
                    await supabaseManager.logOnboardingField(fieldName: "equipment", stage: "sent_to_db", value: equipmentToSend)
                    await supabaseManager.logOnboardingField(fieldName: "available_days", stage: "sent_to_db", value: daysToSend)
                    await supabaseManager.logOnboardingField(fieldName: "workout_environment", stage: "sent_to_db", value: selectedWorkoutLocation.rawValue)
                    
                    // Use full international phone number (with country code) if verified
                    let phoneForOAuth = isPhoneVerified ? fullPhoneNumber : nil
                    
                    print("🔐 [ONBOARDING] Creating profile for OAuth user...")
                    print("🔐 [ONBOARDING] Birthday: display='\(birthday)' -> ISO='\(birthdayISO ?? "nil")'")
                    try await supabaseManager.createProfileForOAuthUser(
                        name: name,
                        email: emailToSend,
                        username: username.isEmpty ? nil : username,
                        birthday: birthdayISO,  // Birthday in ISO format (YYYY-MM-DD) for database
                        age: ageValue,
                        gender: selectedGender,
                        heightCm: heightToSend,
                        weightKg: weightToSend,
                        fitnessGoal: goalsToSend,
                        experienceLevel: experienceToSend,
                        equipment: equipmentToSend,
                        availableDays: daysToSend,
                        workoutEnvironment: selectedWorkoutLocation.rawValue,
                        phoneNumber: phoneForOAuth  // 2FA phone number with country code (private)
                    )
                    print("✅ [ONBOARDING] OAuth user profile created successfully!")
                    
                    // Log success
                    await supabaseManager.logOnboardingEvent(
                        eventType: "profile_create_success",
                        stepName: "complete",
                        eventData: ["user_id": supabaseManager.currentUser?.id.uuidString ?? "unknown"]
                    )
                    
                    // ═══════════════════════════════════════════════════════════════════
                    // VERIFY: Read back what was actually saved to the database
                    // This will log each field at "verified_in_db" stage
                    // ═══════════════════════════════════════════════════════════════════
                    print("📊 [FIELD LOG] Verifying what was actually saved to database...")
                    await supabaseManager.verifyAndLogSavedProfile()
                    
                    // 📬 NOTIFY EXISTING USERS: If phone is verified and contacts synced, notify contacts
                    // This sends push notifications to existing Fit33 users who have this new user in their contacts
                    if isPhoneVerified && ContactsService.shared.hasCheckedContacts {
                        print("📬 [ONBOARDING] Phone verified + contacts synced → notifying existing users...")
                        await ContactsService.shared.notifyExistingUsersOfNewJoin()
                    } else {
                        print("⚠️ [ONBOARDING] Skipping contact notifications (phone verified: \(isPhoneVerified), contacts synced: \(ContactsService.shared.hasCheckedContacts))")
                    }
                    
                } catch {
                    print("❌ [ONBOARDING] Failed to create OAuth profile: \(error.localizedDescription)")
                    
                    // Log the error with full details
                    await supabaseManager.logOnboardingEvent(
                        eventType: "profile_create_error",
                        stepName: "complete",
                        eventData: onboardingData,
                        errorMessage: error.localizedDescription
                    )
                    
                    // Continue with local setup even if cloud fails
                }
            }
        }
        
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
        
        // Use full international phone number (with country code) if verified
        let phoneForUser = isPhoneVerified ? fullPhoneNumber : nil
        
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
            heightInches: heightInches,
            phoneNumber: phoneForUser  // 2FA phone number with country code (private)
        )
        
        // Save user limitations to cloud
        if !selectedLimitations.isEmpty {
            Task {
                await saveLimitationsToCloud()
            }
        }
        
        // Upload profile photo if provided
        if let photo = profilePhotoImage {
            Task {
                await uploadOnboardingProfilePhoto(photo)
            }
        }
        
        // Sync video gender preference based on user's gender selection
        VideoStreamingService.shared.syncGenderFromUserProfile()
        
        // 👤 Set centralized gender preference
        if let gender = selectedGender {
            let genderPref: GenderFilterService.Gender = gender.lowercased().contains("female") ? .female : .male
            GenderFilterService.shared.setPreferredGender(genderPref)
        }
        
        // 📬 NOTIFY EXISTING USERS: For email/password signup users
        // This sends push notifications to existing Fit33 users who have this new user in their contacts
        // (OAuth users are handled in the Task block above)
        if !supabaseManager.isAuthenticated {
            // This shouldn't happen, but log it
            print("⚠️ [ONBOARDING] User not authenticated after profile creation - skipping contact notifications")
        } else {
            Task {
                // Check if phone is verified and contacts are synced
                if isPhoneVerified && ContactsService.shared.hasCheckedContacts {
                    print("📬 [ONBOARDING] Phone verified + contacts synced → notifying existing users...")
                    await ContactsService.shared.notifyExistingUsersOfNewJoin()
                } else {
                    print("⚠️ [ONBOARDING] Skipping contact notifications (phone verified: \(isPhoneVerified), contacts synced: \(ContactsService.shared.hasCheckedContacts))")
                }
            }
        }
        
        // Show completion screen
        navigateTo(.complete)
    }
    
    private func finishOnboarding() {
        // UserManager.createUser already sets hasCompletedOnboarding = true
        // The view will automatically transition via ContentView
        print("✅ [ONBOARDING] Complete! Transitioning to main app...")
        
        // 🔔 REQUEST NOTIFICATION PERMISSIONS IMMEDIATELY
        // This triggers the native iOS permission prompt right as they complete onboarding
        // All notification types are defaulted ON in NotificationManager for maximum engagement
        Task {
            // Request notification permission - this shows native iOS prompt
            let granted = await NotificationManager.shared.requestAuthorization()
            if granted {
                print("✅ [NOTIFICATIONS] Permissions granted during onboarding - scheduling all notifications")
                // Schedule all default notifications immediately
                await MainActor.run {
                    NotificationManager.shared.scheduleAllNotifications()
                }
            } else {
                print("⚠️ [NOTIFICATIONS] User declined notification permission")
                // We'll show them a banner on the Dashboard to reconsider
            }
        }
        
        // Generate personalized programs based on user profile
        if let user = userManager.currentUser {
            Task {
                print("🎯 Generating personalized workout programs...")
                _ = await GeneratedProgramService.shared.generateProgramsForUser(user)
                print("✅ Programs generated!")
            }
        }
    }
    
    // MARK: - Social Login Handlers
    
    private func handleAppleSignIn() {
        print("🍎 [APPLE AUTH] handleAppleSignIn called")
        socialAuthService.signInWithApple { result in
            print("🍎 [APPLE AUTH] socialAuthService callback received")
            switch result {
            case .success(let credentials):
                print("🍎 [APPLE AUTH] Got Apple credentials, starting Supabase auth...")
                
                // Extract FULL NAME (first + last) from Apple credentials (only available on FIRST sign-in)
                // Apple only provides the name once, so we need to capture and persist it
                var appleProvidedFullName: String? = nil
                if let fullName = credentials.fullName {
                    let firstName = fullName.givenName ?? ""
                    let lastName = fullName.familyName ?? ""
                    print("🍎 [APPLE AUTH] Raw name components - givenName: '\(fullName.givenName ?? "nil")', familyName: '\(fullName.familyName ?? "nil")'")
                    let fullNameStr = [firstName, lastName].filter { !$0.isEmpty }.joined(separator: " ")
                    if !fullNameStr.isEmpty {
                        appleProvidedFullName = fullNameStr
                        print("🍎 [APPLE AUTH] Got FULL NAME from Apple: \(fullNameStr)")
                    } else {
                        print("🍎 [APPLE AUTH] ⚠️ Apple returned empty name components (this happens after first sign-in)")
                    }
                } else {
                    print("🍎 [APPLE AUTH] ⚠️ Apple did NOT provide fullName (nil)")
                }
                print("🍎 [APPLE AUTH] Email from credentials: \(credentials.email ?? "nil")")
                
                // Use the credentials to sign in with Supabase
                Task {
                    do {
                        // Returns true if this is a NEW user who needs onboarding
                        // Pass the Apple-provided FULL NAME (first + last) so it can be persisted
                        let isNewUser = try await supabaseManager.signInWithApple(
                            idToken: credentials.identityToken,
                            nonce: credentials.nonce,
                            appleProvidedName: appleProvidedFullName
                        )
                        print("🍎 [APPLE AUTH] Supabase signInWithApple returned. isNewUser: \(isNewUser)")
                        
                        // Set the FULL NAME (first + last) in onboarding state
                        await MainActor.run {
                            print("🍎 [APPLE AUTH] 🔍 Looking for user's full name...")
                            print("🍎 [APPLE AUTH] 🔍 appleProvidedFullName: \(appleProvidedFullName ?? "nil")")
                            
                            if let providedFullName = appleProvidedFullName, !providedFullName.isEmpty {
                                name = providedFullName
                                print("🍎 [APPLE AUTH] ✅ Using full name from credentials: '\(providedFullName)'")
                            } else if let userId = supabaseManager.currentUser?.id {
                                print("🍎 [APPLE AUTH] 🔍 Checking persisted names for userId: \(userId.uuidString.prefix(8))...")
                                
                                // Try to get persisted full name from previous Apple sign-in
                                let persistedKey = "apple_user_name_\(userId.uuidString)"
                                let persistedFullName = UserDefaults.standard.string(forKey: persistedKey)
                                print("🍎 [APPLE AUTH] 🔍 UserDefaults[\(persistedKey)]: \(persistedFullName ?? "nil")")
                                
                                if let persistedFullName = persistedFullName, 
                                   !persistedFullName.isEmpty, 
                                   persistedFullName != "Apple User" {
                                    name = persistedFullName
                                    print("🍎 [APPLE AUTH] ✅ Using persisted full name from UserDefaults: '\(persistedFullName)'")
                                } else {
                                    let pendingName = UserDefaults.standard.string(forKey: "pending_oauth_name")
                                    print("🍎 [APPLE AUTH] 🔍 UserDefaults[pending_oauth_name]: \(pendingName ?? "nil")")
                                    
                                    if let pendingName = pendingName,
                                       !pendingName.isEmpty,
                                       pendingName != "Apple User" {
                                        // Check pending_oauth_name (just set by SupabaseManager)
                                        name = pendingName
                                        print("🍎 [APPLE AUTH] ✅ Using pending OAuth full name: '\(pendingName)'")
                                    } else {
                                        print("🍎 [APPLE AUTH] ⚠️ No valid name found in any source")
                                        print("🍎 [APPLE AUTH] ℹ️ This happens when:")
                                        print("🍎 [APPLE AUTH] ℹ️  1. Apple has already provided name (only does it once)")
                                        print("🍎 [APPLE AUTH] ℹ️  2. Persisted name was cleared (e.g., account deleted)")
                                        print("🍎 [APPLE AUTH] ℹ️  3. User is using private relay email")
                                    }
                                }
                            }
                            
                            print("🍎 [APPLE AUTH] 📝 Final full name value: '\(name)'")
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
                                // If name is still empty, try to derive from email (but not if private relay)
                                if name.isEmpty || name == "Apple User" {
                                    if !sessionEmail.contains("privaterelay") {
                                        name = sessionEmail.components(separatedBy: "@").first?.capitalized ?? ""
                                    }
                                }
                            }
                        }
                        
                        await MainActor.run {
                            print("🍎 [APPLE AUTH] Sign-in complete. isNewUser: \(isNewUser), name: \(name), hasCompletedOnboarding: \(userManager.hasCompletedOnboarding)")
                            
                            if isNewUser {
                                // New user - go to username step (name pre-filled from Apple)
                                print("👤 [SOCIAL AUTH] New Apple user - directing to username step")
                                navigateTo(.username)
                                // Auto-focus username field since name is pre-filled
                                DispatchQueue.main.async {
                                    focusedField = .username
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    focusedField = .username
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    focusedField = .username
                                }
                            } else {
                                // Returning user - force reload from Core Data to get latest onboarding status
                                userManager.reloadCurrentUser()
                                print("🍎 [APPLE AUTH] After reload - hasCompletedOnboarding: \(userManager.hasCompletedOnboarding)")
                                
                                if userManager.hasCompletedOnboarding {
                                    // They completed onboarding - ContentView will show main app automatically
                                    // because it observes userManager.hasCompletedOnboarding
                                    print("✅ [SOCIAL AUTH] Returning Apple user signed in - onboarding complete, switching to main app")
                                } else {
                                    // They started but didn't finish onboarding - continue from phone number
                                    print("👤 [SOCIAL AUTH] Returning Apple user - continuing onboarding")
                                    navigateTo(.phoneNumber)
                                }
                            }
                        }
                    } catch {
                        print("❌ [APPLE AUTH] Error during sign-in: \(error)")
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
        print("🔐 [GOOGLE AUTH] Starting Google Sign-In with ASWebAuthenticationSession")
        
        guard let authURL = supabaseManager.getGoogleOAuthURL() else {
            errorMessage = "Could not create Google Sign-In URL"
            showError = true
            return
        }
        
        print("🔐 [GOOGLE AUTH] Auth URL: \(authURL.absoluteString)")
        
        // Use ASWebAuthenticationSession for OAuth - this handles callbacks properly
        let session = ASWebAuthenticationSession(
            url: authURL,
            callbackURLScheme: "fit33"
        ) { callbackURL, error in
            if let error = error {
                // Check if user cancelled
                if (error as NSError).code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                    print("🔐 [GOOGLE AUTH] User cancelled login")
                    return
                }
                print("❌ [GOOGLE AUTH] Error: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.errorMessage = "Google Sign-In failed: \(error.localizedDescription)"
                    self.showError = true
                }
                return
            }
            
            guard let callbackURL = callbackURL else {
                print("❌ [GOOGLE AUTH] No callback URL received")
                return
            }
            
            print("✅ [GOOGLE AUTH] Callback URL received: \(callbackURL.absoluteString)")
            
            // Post notification to handle the OAuth callback
            NotificationCenter.default.post(name: Notification.Name("OAuthCallback"), object: callbackURL)
        }
        
        // Set presentation context and start
        session.presentationContextProvider = WebAuthContextProvider.shared
        session.prefersEphemeralWebBrowserSession = true // Skip the "wants to use X to sign in" dialog
        
        if !session.start() {
            print("❌ [GOOGLE AUTH] Failed to start ASWebAuthenticationSession")
            errorMessage = "Could not start Google Sign-In"
            showError = true
        }
    }
    
    private func handleFacebookSignIn() {
        print("📘 [FACEBOOK AUTH] Starting Facebook Sign-In with ASWebAuthenticationSession")
        
        guard let authURL = supabaseManager.getFacebookOAuthURL() else {
            errorMessage = "Could not create Facebook Sign-In URL"
            showError = true
            print("❌ [FACEBOOK AUTH] Failed to create OAuth URL")
            return
        }
        
        print("📘 [FACEBOOK AUTH] Auth URL: \(authURL.absoluteString)")
        
        // Use ASWebAuthenticationSession for OAuth
        let session = ASWebAuthenticationSession(
            url: authURL,
            callbackURLScheme: "fit33"
        ) { callbackURL, error in
            if let error = error {
                if (error as NSError).code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                    print("📘 [FACEBOOK AUTH] User cancelled login")
                    return
                }
                print("❌ [FACEBOOK AUTH] Error: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.errorMessage = "Facebook Sign-In failed: \(error.localizedDescription)"
                    self.showError = true
                }
                return
            }
            
            guard let callbackURL = callbackURL else {
                print("❌ [FACEBOOK AUTH] No callback URL received")
                return
            }
            
            print("✅ [FACEBOOK AUTH] Callback URL received: \(callbackURL.absoluteString)")
            
            // Post notification to handle the OAuth callback
            NotificationCenter.default.post(name: Notification.Name("OAuthCallback"), object: callbackURL)
        }
        
        session.presentationContextProvider = WebAuthContextProvider.shared
        session.prefersEphemeralWebBrowserSession = true // Skip the "wants to use X to sign in" dialog
        
        if !session.start() {
            print("❌ [FACEBOOK AUTH] Failed to start ASWebAuthenticationSession")
            errorMessage = "Could not start Facebook Sign-In"
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
                    .font(.ds_heading3)
                    .foregroundColor(.blue)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .font(.ds_bodyRegular)
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
        .contentShape(RoundedRectangle(cornerRadius: CornerRadius.lg)) // Rounded rectangle hit area
        .background(
            // Modern floating card effect with gradient
            ZStack {
                RoundedRectangle(cornerRadius: CornerRadius.lg)
                    .fill(
                        LinearGradient(
                            colors: colorScheme == .dark 
                                ? [Color(white: 0.14), Color(white: 0.10)]
                                : [Color.white, Color(red: 0.97, green: 0.98, blue: 1.0)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                // Enhanced shadow for floating effect
                RoundedRectangle(cornerRadius: CornerRadius.lg)
                    .fill(Color.clear)
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
            RoundedRectangle(cornerRadius: CornerRadius.lg)
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
            
            // Eye button (show/hide password)
            Button(action: { isVisible.toggle() }) {
                Image(systemName: isVisible ? "eye.slash.fill" : "eye.fill")
                    .font(.ds_bodyRegular)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain) // Prevent keyboard dismissal
            
            // Match indicator (for confirm password) - only show when valid
            if showMatchIndicator && !text.isEmpty && passwordsMatch {
                Image(systemName: "checkmark.circle.fill")
                    .font(.ds_bodyRegular)
                    .foregroundColor(.blue)
                    .allowsHitTesting(false)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, Spacing.md)
        .contentShape(RoundedRectangle(cornerRadius: CornerRadius.lg)) // Match OnboardingTextField shape
        .background(
            // Modern floating card effect with gradient - matching OnboardingTextField
            ZStack {
                RoundedRectangle(cornerRadius: CornerRadius.lg)
                    .fill(
                        LinearGradient(
                            colors: colorScheme == .dark 
                                ? [Color(white: 0.14), Color(white: 0.10)]
                                : [Color.white, Color(red: 0.97, green: 0.98, blue: 1.0)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                RoundedRectangle(cornerRadius: CornerRadius.lg)
                    .fill(Color.clear)
                    .shadow(
                        color: colorScheme == .dark ? Color.black.opacity(0.4) : Color.black.opacity(0.08),
                        radius: 8,
                        x: 0,
                        y: 3
                    )
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.lg)
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

// MARK: - Verification Code Box
struct VerificationCodeBox: View {
    let digit: String
    let isFocused: Bool
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: CornerRadius.md)
                .fill(
                    LinearGradient(
                        colors: colorScheme == .dark 
                            ? [Color(white: 0.14), Color(white: 0.10)]
                            : [Color.white, Color(red: 0.97, green: 0.98, blue: 1.0)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(
                    color: colorScheme == .dark ? Color.black.opacity(0.4) : Color.black.opacity(0.08),
                    radius: isFocused ? 8 : 4,
                    x: 0,
                    y: isFocused ? 4 : 2
                )
            
            RoundedRectangle(cornerRadius: CornerRadius.md)
                .stroke(
                    isFocused
                        ? LinearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing)
                        : LinearGradient(colors: [Color.gray.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: isFocused ? 2 : 1
                )
            
            Text(digit)
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .foregroundColor(.primary)
        }
        .frame(width: 48, height: 56)
        .animation(.easeInOut(duration: 0.15), value: isFocused)
        .animation(.easeInOut(duration: 0.1), value: digit)
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
        NavigationStack {
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
            .padding(.horizontal, Spacing.xs)
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
                .padding(.vertical, Spacing.sm)
                
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
        return .blue
    }
    
    var body: some View {
        Button(action: {
            selectionFeedback.selectionChanged()
            action()
        }) {
            Text(title)
                .font(.ds_labelLarge)
                .foregroundColor(isSelected ? .white : .primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.md)
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: CornerRadius.lg)
                            .fill(isSelected 
                                ? LinearGradient(
                                    colors: [color, color.opacity(0.8)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                                : LinearGradient(
                                    colors: colorScheme == .dark 
                                        ? [Color(white: 0.14), Color(white: 0.10)]
                                        : [Color.white, Color(red: 0.97, green: 0.98, blue: 1.0)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        
                        // Enhanced shadow for floating effect
                        RoundedRectangle(cornerRadius: CornerRadius.lg)
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
                    RoundedRectangle(cornerRadius: CornerRadius.lg)
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
                .font(.ds_heading2)
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
    @Environment(\.colorScheme) var colorScheme
    let title: String
    let emoji: String
    let subtitle: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                // Emoji with glow
                ZStack {
                    if isSelected {
                        Circle()
                            .fill(Color.blue.opacity(0.35))
                            .frame(width: 60, height: 60)
                            .blur(radius: 14)
                    }
                    Text(emoji)
                        .font(.system(size: 44))
                }
                
                Text(title)
                    .font(.ds_heading2)
                    .foregroundColor(isSelected ? .blue : .primary)
                    .lineLimit(1)
                
                Text(subtitle)
                    .font(.ds_bodySmall)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 130)
            .onboardingCardStyle(accentColor: .blue, secondaryColor: .purple, isSelected: isSelected, cornerRadius: 24)
            .overlay(
                Group {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundColor(.blue)
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
    @Environment(\.colorScheme) var colorScheme
    let title: String
    let emoji: String
    let subtitle: String
    let detail: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                // Emoji with background circle and glow
                ZStack {
                    if isSelected {
                        Circle()
                            .fill(Color.blue.opacity(0.4))
                            .frame(width: 62, height: 62)
                            .blur(radius: 10)
                    }
                    
                    Circle()
                        .fill(
                            isSelected
                                ? LinearGradient(colors: [.blue, .blue.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)
                                : LinearGradient(colors: [colorScheme == .dark ? Color(white: 0.22) : Color.blue.opacity(0.08), colorScheme == .dark ? Color(white: 0.18) : Color.blue.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .frame(width: 56, height: 56)
                    
                    Text(emoji)
                        .font(.system(size: 28))
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(isSelected ? .blue : .primary)
                    
                    Text(subtitle)
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                    
                    Text(detail)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.blue.opacity(0.7))
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 26))
                        .foregroundColor(.blue)
                }
            }
            .padding(Spacing.md)
            .frame(height: 90)
            .onboardingCardStyle(accentColor: .blue, secondaryColor: .cyan, isSelected: isSelected, cornerRadius: 24)
        }
        .scaleEffect(isSelected ? 1.01 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }
}

// MARK: - Large Equipment Card
struct EquipmentCardLarge: View {
    @Environment(\.colorScheme) var colorScheme
    let title: String
    let emoji: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                // Emoji with glow
                ZStack {
                    if isSelected {
                        Circle()
                            .fill(Color.blue.opacity(0.35))
                            .frame(width: 50, height: 50)
                            .blur(radius: 12)
                    }
                    Text(emoji)
                        .font(.system(size: 36))
                }
                
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(isSelected ? .blue : .primary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 100)
            .onboardingCardStyle(accentColor: .blue, secondaryColor: .purple, isSelected: isSelected, cornerRadius: 22)
            .overlay(
                Group {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.blue)
                            .padding(Spacing.xs)
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
    @Environment(\.colorScheme) var colorScheme
    let title: String
    let iconName: String
    let subtitle: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                // Icon with glow
                ZStack {
                    if isSelected {
                        Circle()
                            .fill(Color.blue.opacity(0.35))
                            .frame(width: 48, height: 48)
                            .blur(radius: 10)
                    }
                    Image(systemName: iconName)
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(
                            AnyShapeStyle(LinearGradient(colors: [.blue, .purple.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        )
                        .frame(height: 36)
                }
                
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(isSelected ? .blue : .primary)
                    .lineLimit(1)
                
                Text(subtitle)
                    .font(.ds_caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 110)
            .onboardingCardStyle(accentColor: .blue, secondaryColor: .purple, isSelected: isSelected, cornerRadius: 22)
            .overlay(
                Group {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.blue)
                            .padding(Spacing.xs)
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
    @Environment(\.colorScheme) var colorScheme
    let environment: WorkoutEnvironmentService.WorkoutEnvironment
    let emoji: String
    let subtitle: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                // Emoji icon with glow
                ZStack {
                    if isSelected {
                        Circle()
                            .fill(Color.blue.opacity(0.4))
                            .frame(width: 62, height: 62)
                            .blur(radius: 10)
                    }
                    
                    Circle()
                        .fill(
                            isSelected
                                ? LinearGradient(colors: [.blue, .purple.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing)
                                : LinearGradient(colors: [colorScheme == .dark ? Color(white: 0.22) : Color(.systemGray5), colorScheme == .dark ? Color(white: 0.18) : Color(.systemGray5)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .frame(width: 56, height: 56)
                    
                    Text(emoji)
                        .font(.system(size: 32))
                }
                
                // Text content
                VStack(alignment: .leading, spacing: 4) {
                    Text(environment.displayName)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(isSelected ? .blue : .primary)
                    
                    Text(subtitle)
                        .font(.ds_bodySmall)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Checkmark
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.blue)
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, 14)
            .onboardingCardStyle(accentColor: .blue, secondaryColor: .cyan, isSelected: isSelected, cornerRadius: 22)
        }
        .scaleEffect(isSelected ? 1.02 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isSelected)
    }
}

// MARK: - Strength Level Card
struct StrengthLevelCard: View {
    @Environment(\.colorScheme) var colorScheme
    let level: StrengthProfileRecommendationEngine.StrengthLevel
    let emoji: String
    let title: String
    let subtitle: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                // Emoji icon with gradient background and glow
                ZStack {
                    if isSelected {
                        Circle()
                            .fill(Color.orange.opacity(0.4))
                            .frame(width: 58, height: 58)
                            .blur(radius: 10)
                    }
                    
                    Circle()
                        .fill(
                            isSelected
                                ? LinearGradient(colors: [.orange, .red.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing)
                                : LinearGradient(colors: [colorScheme == .dark ? Color(white: 0.22) : Color(.systemGray5), colorScheme == .dark ? Color(white: 0.18) : Color(.systemGray5)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .frame(width: 52, height: 52)
                    
                    Text(emoji)
                        .font(.system(size: 26))
                }
                
                // Text content
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(isSelected ? .orange : .primary)
                    
                    Text(subtitle)
                        .font(.ds_bodySmall)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Checkmark or strength indicator
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.orange)
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
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .onboardingCardStyle(accentColor: .orange, secondaryColor: .red, isSelected: isSelected, cornerRadius: 20)
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
                                    : LinearGradient(colors: [colorScheme == .dark ? Color(white: 0.18) : Color.white, colorScheme == .dark ? Color(white: 0.18) : Color.white], startPoint: .topLeading, endPoint: .bottomTrailing)
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
    @Environment(\.colorScheme) var colorScheme
    let title: String
    let emoji: String
    let subtitle: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                // Emoji with glow
                ZStack {
                    if isSelected {
                        Circle()
                            .fill(Color.blue.opacity(0.35))
                            .frame(width: 40, height: 40)
                            .blur(radius: 10)
                    }
                    Text(emoji)
                        .font(.system(size: 28))
                }
                
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(isSelected ? .blue : .primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                
                Text(subtitle)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .padding(.horizontal, Spacing.xs)
            .onboardingCardStyle(accentColor: .blue, secondaryColor: .purple, isSelected: isSelected, cornerRadius: 18)
        }
        .scaleEffect(isSelected ? 1.02 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }
}

struct OnboardingExperienceCard: View {
    @Environment(\.colorScheme) var colorScheme
    let title: String
    let emoji: String
    let subtitle: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // Emoji with glow
                ZStack {
                    if isSelected {
                        Circle()
                            .fill(Color.blue.opacity(0.35))
                            .frame(width: 36, height: 36)
                            .blur(radius: 8)
                    }
                    Text(emoji)
                        .font(.title2)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(isSelected ? .blue : .primary)
                    
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.blue)
                }
            }
            .padding(Spacing.sm)
            .onboardingCardStyle(accentColor: .blue, secondaryColor: .purple, isSelected: isSelected, cornerRadius: 18)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }
}

struct OnboardingEquipmentChip: View {
    @Environment(\.colorScheme) var colorScheme
    let title: String
    let emoji: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                // Emoji with glow
                ZStack {
                    if isSelected {
                        Circle()
                            .fill(Color.blue.opacity(0.35))
                            .frame(width: 30, height: 30)
                            .blur(radius: 8)
                    }
                    Text(emoji)
                        .font(.title3)
                }
                
                Text(title)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(isSelected ? .blue : .primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.sm)
            .onboardingCardStyle(accentColor: .blue, secondaryColor: .purple, isSelected: isSelected, cornerRadius: CornerRadius.lg)
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.md)
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
    @Environment(\.colorScheme) var colorScheme
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
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .onboardingCardStyle(accentColor: .blue, secondaryColor: .cyan, isSelected: false, cornerRadius: 18)
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
                    .font(.ds_bodyMedium)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Text(value)
                    .font(.ds_bodyMedium)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                
                Image(systemName: "chevron.right")
                    .font(.ds_labelMedium)
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
    @Environment(\.colorScheme) var colorScheme
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
            .padding(Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onboardingCardStyle(accentColor: .blue, secondaryColor: .purple, isSelected: false, cornerRadius: CornerRadius.lg)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Confirmation Section
struct ConfirmationSection<Content: View>: View {
    @Environment(\.colorScheme) var colorScheme
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
            
            // Content box - tappable with exercise library style
            Button(action: onEdit) {
                VStack(spacing: 0) {
                    content
                }
                .onboardingCardStyle(accentColor: .blue, secondaryColor: .cyan, isSelected: false, cornerRadius: 20)
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
                .font(.ds_bodyRegular)
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
        .padding(.horizontal, Spacing.md)
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
                    .font(.ds_heading3)
                    .foregroundColor(.blue)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .font(.ds_bodyRegular)
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
        .contentShape(RoundedRectangle(cornerRadius: CornerRadius.lg))
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: CornerRadius.lg)
                    .fill(colorScheme == .dark ? Color(white: 0.18) : Color.white)
                
                RoundedRectangle(cornerRadius: CornerRadius.lg)
                    .fill(colorScheme == .dark ? Color(white: 0.18) : Color.white)
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
            RoundedRectangle(cornerRadius: CornerRadius.lg)
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
    let needsSelection: Bool  // True if selected but user hasn't explicitly chosen a level
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
                                    : LinearGradient(colors: [colorScheme == .dark ? Color(white: 0.22) : Color.gray.opacity(0.08), colorScheme == .dark ? Color(white: 0.18) : Color.gray.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing)
                            )
                            .frame(width: 44, height: 44)
                        
                        Image(systemName: area.icon)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(isSelected ? .white : (colorScheme == .dark ? .gray : .gray.opacity(0.8)))
                    }
                    
                    // Title and status
                    VStack(alignment: .leading, spacing: 4) {
                        Text(area.rawValue)
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundColor(isSelected ? area.color : .primary)
                        
                        if isSelected {
                            if needsSelection {
                                HStack(spacing: 4) {
                                    Image(systemName: "checkmark.circle")
                                        .font(.ds_labelSmall)
                                    Text("Choose accommodation level")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                }
                                .foregroundColor(.orange)
                            } else {
                                HStack(spacing: 4) {
                                    Image(systemName: accommodation.icon)
                                        .font(.ds_labelSmall)
                                    Text(accommodation.displayName)
                                        .font(.caption)
                                        .fontWeight(.medium)
                                }
                                .foregroundColor(accommodation.color)
                            }
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
                            .stroke(isSelected ? (needsSelection ? Color.orange : area.color) : Color.gray.opacity(0.3), lineWidth: 2)
                            .frame(width: 24, height: 24)
                        
                        if isSelected {
                            if needsSelection {
                                Image(systemName: "exclamationmark")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.orange)
                            } else {
                                Circle()
                                    .fill(area.color)
                                    .frame(width: 16, height: 16)
                            }
                        }
                    }
                }
                .padding(Spacing.md)
                .onboardingCardStyle(accentColor: area.color, secondaryColor: area.color.opacity(0.7), isSelected: isSelected, cornerRadius: 20)
            }
            .buttonStyle(.plain)
            
            // Expanded accommodation options
            if isSelected {
                VStack(spacing: 6) {
                    // Helper text when no explicit selection made
                    if needsSelection {
                        HStack(spacing: 6) {
                            Image(systemName: "hand.point.down.fill")
                                .font(.system(size: 12))
                            Text("Choose how you want us to handle this")
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        .foregroundColor(.orange)
                        .padding(.top, 8)
                        .padding(.bottom, 2)
                    }
                    
                    ForEach(AccommodationLevel.allCases) { level in
                        Button(action: {
                            selectionFeedback.selectionChanged()
                            onAccommodationChange(level)
                        }) {
                            HStack(spacing: 10) {
                                Image(systemName: level.icon)
                                    .font(.ds_bodyMedium)
                                    .foregroundColor(level.color)
                                    .frame(width: 22)
                                
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(level.displayName)
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(accommodation == level ? level.color : .primary)
                                    
                                    Text(level.description)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                                
                                Spacer()
                                
                                if accommodation == level {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 18))
                                        .foregroundColor(level.color)
                                }
                            }
                            .padding(.horizontal, Spacing.sm)
                            .padding(.vertical, 9)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(accommodation == level ? level.color.opacity(0.12) : Color(.systemGray6))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(accommodation == level ? level.color.opacity(0.5) : Color.clear, lineWidth: 1.5)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 4)
            }
        }
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
                    // Icon with glow effect (matching exercise library style)
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
                                    : LinearGradient(colors: [colorScheme == .dark ? Color(white: 0.22) : Color.gray.opacity(0.08), colorScheme == .dark ? Color(white: 0.18) : Color.gray.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing)
                            )
                            .frame(width: 44, height: 44)
                        
                        Image(systemName: area.icon)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(isSelected ? .white : (colorScheme == .dark ? .gray : .gray.opacity(0.8)))
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
                .onboardingCardStyle(accentColor: area.color, secondaryColor: area.color.opacity(0.7), isSelected: isSelected, cornerRadius: 20)
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
                        .font(.ds_bodyRegular)
                        .foregroundColor(level.color)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, Spacing.xs)
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

// MARK: - Onboarding Photo Picker
struct OnboardingPhotoPicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .photoLibrary
        picker.allowsEditing = true
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: OnboardingPhotoPicker
        
        init(_ parent: OnboardingPhotoPicker) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            // Prefer edited image (cropped circle), fallback to original
            if let editedImage = info[.editedImage] as? UIImage {
                parent.image = editedImage
            } else if let originalImage = info[.originalImage] as? UIImage {
                parent.image = originalImage
            }
            parent.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

// MARK: - Onboarding Camera Picker
struct OnboardingCameraPicker: UIViewControllerRepresentable {
    let onImagePicked: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .camera
        picker.cameraDevice = .front
        picker.allowsEditing = true
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: OnboardingCameraPicker
        
        init(_ parent: OnboardingCameraPicker) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let editedImage = info[.editedImage] as? UIImage {
                parent.onImagePicked(editedImage)
            } else if let originalImage = info[.originalImage] as? UIImage {
                parent.onImagePicked(originalImage)
            }
            parent.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

// MARK: - Country Code for Phone Verification
enum CountryCode: String, CaseIterable, Identifiable {
    // North America
    case us = "+1"
    // Europe
    case uk = "+44"
    case ireland = "+353"
    case france = "+33"
    case germany = "+49"
    case spain = "+34"
    case italy = "+39"
    case netherlands = "+31"
    case belgium = "+32"
    case portugal = "+351"
    case austria = "+43"
    case switzerland = "+41"
    case sweden = "+46"
    case norway = "+47"
    case denmark = "+45"
    case poland = "+48"
    case finland = "+358"
    case greece = "+30"
    case czechRepublic = "+420"
    case romania = "+40"
    case hungary = "+36"
    // Asia-Pacific
    case australia = "+61"
    case newZealand = "+64"
    case india = "+91"
    case japan = "+81"
    case southKorea = "+82"
    case singapore = "+65"
    case hongKong = "+852"
    case philippines = "+63"
    case thailand = "+66"
    case malaysia = "+60"
    case indonesia = "+62"
    // Americas
    case canada = "+1CA"  // Same code as US, differentiated by case
    case mexico = "+52"
    case brazil = "+55"
    case argentina = "+54"
    case colombia = "+57"
    case chile = "+56"
    // Middle East & Africa
    case uae = "+971"
    case saudiArabia = "+966"
    case southAfrica = "+27"
    case israel = "+972"
    case turkey = "+90"
    case nigeria = "+234"
    case egypt = "+20"

    var id: String { self == .canada ? "+1CA" : rawValue }

    /// The actual dialing code to send to Twilio (strips any suffix)
    var dialingCode: String {
        switch self {
        case .canada: return "+1"
        default: return rawValue
        }
    }

    var flag: String {
        switch self {
        case .us: return "🇺🇸"
        case .uk: return "🇬🇧"
        case .ireland: return "🇮🇪"
        case .france: return "🇫🇷"
        case .germany: return "🇩🇪"
        case .spain: return "🇪🇸"
        case .italy: return "🇮🇹"
        case .netherlands: return "🇳🇱"
        case .belgium: return "🇧🇪"
        case .portugal: return "🇵🇹"
        case .austria: return "🇦🇹"
        case .switzerland: return "🇨🇭"
        case .sweden: return "🇸🇪"
        case .norway: return "🇳🇴"
        case .denmark: return "🇩🇰"
        case .poland: return "🇵🇱"
        case .finland: return "🇫🇮"
        case .greece: return "🇬🇷"
        case .czechRepublic: return "🇨🇿"
        case .romania: return "🇷🇴"
        case .hungary: return "🇭🇺"
        case .australia: return "🇦🇺"
        case .newZealand: return "🇳🇿"
        case .india: return "🇮🇳"
        case .japan: return "🇯🇵"
        case .southKorea: return "🇰🇷"
        case .singapore: return "🇸🇬"
        case .hongKong: return "🇭🇰"
        case .philippines: return "🇵🇭"
        case .thailand: return "🇹🇭"
        case .malaysia: return "🇲🇾"
        case .indonesia: return "🇮🇩"
        case .canada: return "🇨🇦"
        case .mexico: return "🇲🇽"
        case .brazil: return "🇧🇷"
        case .argentina: return "🇦🇷"
        case .colombia: return "🇨🇴"
        case .chile: return "🇨🇱"
        case .uae: return "🇦🇪"
        case .saudiArabia: return "🇸🇦"
        case .southAfrica: return "🇿🇦"
        case .israel: return "🇮🇱"
        case .turkey: return "🇹🇷"
        case .nigeria: return "🇳🇬"
        case .egypt: return "🇪🇬"
        }
    }

    var name: String {
        switch self {
        case .us: return "United States"
        case .uk: return "United Kingdom"
        case .ireland: return "Ireland"
        case .france: return "France"
        case .germany: return "Germany"
        case .spain: return "Spain"
        case .italy: return "Italy"
        case .netherlands: return "Netherlands"
        case .belgium: return "Belgium"
        case .portugal: return "Portugal"
        case .austria: return "Austria"
        case .switzerland: return "Switzerland"
        case .sweden: return "Sweden"
        case .norway: return "Norway"
        case .denmark: return "Denmark"
        case .poland: return "Poland"
        case .finland: return "Finland"
        case .greece: return "Greece"
        case .czechRepublic: return "Czech Republic"
        case .romania: return "Romania"
        case .hungary: return "Hungary"
        case .australia: return "Australia"
        case .newZealand: return "New Zealand"
        case .india: return "India"
        case .japan: return "Japan"
        case .southKorea: return "South Korea"
        case .singapore: return "Singapore"
        case .hongKong: return "Hong Kong"
        case .philippines: return "Philippines"
        case .thailand: return "Thailand"
        case .malaysia: return "Malaysia"
        case .indonesia: return "Indonesia"
        case .canada: return "Canada"
        case .mexico: return "Mexico"
        case .brazil: return "Brazil"
        case .argentina: return "Argentina"
        case .colombia: return "Colombia"
        case .chile: return "Chile"
        case .uae: return "UAE"
        case .saudiArabia: return "Saudi Arabia"
        case .southAfrica: return "South Africa"
        case .israel: return "Israel"
        case .turkey: return "Turkey"
        case .nigeria: return "Nigeria"
        case .egypt: return "Egypt"
        }
    }

    var displayText: String {
        "\(flag) \(dialingCode)"
    }

    // Minimum digits for phone number (without country code)
    var minDigits: Int {
        switch self {
        case .us, .canada: return 10
        case .uk, .germany, .austria: return 10
        case .india: return 10
        case .australia: return 9
        case .japan, .southKorea: return 10
        case .brazil, .mexico, .argentina: return 10
        case .norway, .denmark: return 8
        case .singapore, .hongKong: return 8
        case .uae: return 9
        case .southAfrica, .nigeria: return 9
        case .turkey: return 10
        case .egypt: return 10
        case .israel: return 9
        default: return 9
        }
    }

    var maxDigits: Int {
        switch self {
        case .us, .canada: return 10
        case .uk: return 10
        case .germany: return 11
        case .italy: return 10
        case .india: return 10
        case .australia: return 9
        case .japan: return 11
        case .southKorea: return 11
        case .brazil: return 11
        case .mexico, .argentina: return 10
        case .norway, .denmark: return 8
        case .singapore, .hongKong: return 8
        case .indonesia: return 12
        case .philippines: return 10
        case .uae: return 9
        case .turkey: return 10
        case .egypt: return 10
        case .nigeria: return 10
        default: return 10
        }
    }

    var placeholder: String {
        switch self {
        case .us: return "(555) 123-4567"
        case .uk: return "7911 123456"
        case .ireland: return "85 123 4567"
        case .france: return "6 12 34 56 78"
        case .germany: return "151 12345678"
        case .spain: return "612 345 678"
        case .italy: return "312 345 6789"
        case .netherlands: return "6 12345678"
        case .belgium: return "470 12 34 56"
        case .portugal: return "912 345 678"
        case .austria: return "664 1234567"
        case .switzerland: return "78 123 45 67"
        case .sweden: return "70 123 45 67"
        case .norway: return "412 34 567"
        case .denmark: return "20 12 34 56"
        case .poland: return "512 345 678"
        case .finland: return "40 123 4567"
        case .greece: return "691 234 5678"
        case .czechRepublic: return "601 234 567"
        case .romania: return "721 234 567"
        case .hungary: return "20 123 4567"
        case .australia: return "412 345 678"
        case .newZealand: return "21 123 4567"
        case .india: return "98765 43210"
        case .japan: return "90 1234 5678"
        case .southKorea: return "10 1234 5678"
        case .singapore: return "9123 4567"
        case .hongKong: return "9123 4567"
        case .philippines: return "917 123 4567"
        case .thailand: return "81 234 5678"
        case .malaysia: return "12 345 6789"
        case .indonesia: return "812 345 6789"
        case .canada: return "(555) 123-4567"
        case .mexico: return "55 1234 5678"
        case .brazil: return "11 91234 5678"
        case .argentina: return "11 1234 5678"
        case .colombia: return "301 234 5678"
        case .chile: return "9 1234 5678"
        case .uae: return "50 123 4567"
        case .saudiArabia: return "50 123 4567"
        case .southAfrica: return "71 123 4567"
        case .israel: return "50 123 4567"
        case .turkey: return "532 123 4567"
        case .nigeria: return "802 345 6789"
        case .egypt: return "10 1234 5678"
        }
    }

    /// Auto-detect user's country from device locale
    static func fromLocale() -> CountryCode {
        let regionCode = Locale.current.region?.identifier ?? "US"
        switch regionCode.uppercased() {
        case "US": return .us
        case "GB": return .uk
        case "IE": return .ireland
        case "FR": return .france
        case "DE": return .germany
        case "ES": return .spain
        case "IT": return .italy
        case "NL": return .netherlands
        case "BE": return .belgium
        case "PT": return .portugal
        case "AT": return .austria
        case "CH": return .switzerland
        case "SE": return .sweden
        case "NO": return .norway
        case "DK": return .denmark
        case "PL": return .poland
        case "FI": return .finland
        case "GR": return .greece
        case "CZ": return .czechRepublic
        case "RO": return .romania
        case "HU": return .hungary
        case "AU": return .australia
        case "NZ": return .newZealand
        case "IN": return .india
        case "JP": return .japan
        case "KR": return .southKorea
        case "SG": return .singapore
        case "HK": return .hongKong
        case "PH": return .philippines
        case "TH": return .thailand
        case "MY": return .malaysia
        case "ID": return .indonesia
        case "CA": return .canada
        case "MX": return .mexico
        case "BR": return .brazil
        case "AR": return .argentina
        case "CO": return .colombia
        case "CL": return .chile
        case "AE": return .uae
        case "SA": return .saudiArabia
        case "ZA": return .southAfrica
        case "IL": return .israel
        case "TR": return .turkey
        case "NG": return .nigeria
        case "EG": return .egypt
        default: return .us
        }
    }
}

#Preview {
    NewOnboardingView()
        .environmentObject(UserManager())
}

