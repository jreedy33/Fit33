import SwiftUI
import Combine
import PhotosUI
import AuthenticationServices
import Contacts

// MARK: - New Onboarding Flow
// Clean, professional onboarding with auth + profile setup


struct NewOnboardingView: View {
    @EnvironmentObject var userManager: UserManager
    @StateObject var supabaseManager = SupabaseManager.shared
    @StateObject var keyboardObserver = KeyboardObserver()
    @Environment(\.colorScheme) var colorScheme
    
    @State var currentStep: OnboardingStep = .auth
    @State var animateTransition = false
    
    // Auth fields
    @State var isSignUp = true  // Default to Sign Up
    @State var email = ""
    @State var password = ""
    @State var confirmPassword = ""
    @State var showPassword = false
    @State var showConfirmPassword = false
    @State var isOnConfirmPasswordStep = false  // Track if user is on confirm password step
    @State var hasStartedAuth = false  // Track if user has started interacting with auth
    @State var name = ""
    @State var errorMessage = ""
    @State var showError = false
    @State var emailAlreadyExists = false
    @State var acceptedTerms = false
    @State var showTermsSheet = false
    @State var passwordResetSent = false
    
    // Phone number (for 2FA / account security)
    @State var phoneNumber = ""
    @State var phoneNumberError = ""
    @State var selectedCountryCode: CountryCode = CountryCode.fromLocale()  // Auto-detect from device locale
    @State var verificationCode = ""
    @State var isVerificationCodeSent = false
    @State var isPhoneVerified = false
    @State var verificationError = ""
    @State var isVerifyingCode = false
    @State var canResendCode = false
    @State var resendCountdown = 0
    @State var sendCodeCountdown = 0  // Countdown before user can send again
    @State var sendCodeTimer: Timer? = nil
    @State var phoneVerificationAttempts = 0  // Track send code attempts
    @State var hasSkippedPhoneVerification = false  // Track if user skipped after max attempts
    @StateObject var phoneVerificationService = PhoneVerificationService.shared
    
    // Email verification (required fallback when phone is skipped)
    @State var isEmailVerificationSent = false
    @State var isEmailVerified = false
    @State var emailVerificationError = ""
    @State var isCheckingEmailVerification = false
    
    // Constants for phone verification limits
    let maxPhoneVerificationAttempts = 3
    
    // Username fields
    @State var username = ""
    @State var isCheckingUsername = false
    @State var usernameError = ""
    @State var isUsernameAvailable = false
    
    // Social auth
    @StateObject var socialAuthService = SocialAuthService.shared
    @State var showGoogleSignIn = false
    @State var detectedAuthProvider = ""  // "apple", "google", "email", "none"
    @State var showAuthProviderHint = false
    @State var authProviderHintMessage = ""
    
    // Profile fields
    @State var birthday = ""  // Formatted with slashes: MM/DD/YYYY
    
    // Format birthday string with auto-inserted slashes (locale-aware: MM/DD/YYYY or DD/MM/YYYY)
    func formatBirthday(_ input: String) -> String {
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
    var usesMonthFirstDate: Bool {
        UnitSettingsManager.localeUsesMonthFirstDate
    }
    
    // Placeholder text based on locale
    var birthdayPlaceholder: String {
        usesMonthFirstDate ? "MM/DD/YYYY" : "DD/MM/YYYY"
    }
    @State var selectedGender: String? = nil
    @State var heightFeetInchesDigits = ""  // Just digits: e.g., "510" for 5'10"
    @State var heightCm = ""
    @State var weight = ""
    
    
    // Height digits are now stored directly (no need to extract)
    var heightDigits: String {
        heightFeetInchesDigits
    }
    @State var selectedGoals: Set<String> = []
    @State var selectedExperience = ""
    @State var selectedStrengthLevel: StrengthProfileRecommendationEngine.StrengthLevel = .moderate
    @State var selectedWorkoutLocation: WorkoutEnvironmentService.WorkoutEnvironment = .gym
    @State var selectedEquipment: Set<String> = []
    @State var selectedEquipmentLocation: EquipmentLocation = .gym
    @State var selectedDays = 4
    @State var selectedLimitations: Set<AffectedArea> = []  // Injury/limitation tracking
    @State var limitationAccommodations: [AffectedArea: AccommodationLevel] = [:]  // Accommodation level per area
    @State var confirmedAccommodations: Set<AffectedArea> = []  // Track which have been explicitly confirmed
    
    // Profile photo (optional onboarding step)
    @State var profilePhotoImage: UIImage? = nil
    @State var selectedPhotoItem: PhotosPickerItem? = nil
    @State var showingPhotoOptions = false
    @State var showingPhotoPicker = false
    @State var showingCamera = false
    @State var isUploadingPhoto = false
    
    // Contacts permission (optional onboarding step)
    @State var contactsPermissionGranted = false
    @State var contactsPermissionRequested = false
    @StateObject var contactsService = ContactsService.shared
    
    // Add friends from contacts (onboarding step)
    @State var friendSearchText = ""
    @State var sentFriendRequests: Set<UUID> = []  // Track requests sent during onboarding
    @State var loadingFriendRequests: Set<UUID> = []  // Track which buttons are currently loading
    @State var failedFriendRequests: Set<UUID> = []  // Track failed requests for retry UI
    @State var isLoadingFriends = false
    
    // Unit preferences - default based on user's locale
    @State var heightUnit: HeightUnit = UnitSettingsManager.localeUsesImperial ? .ftIn : .cm
    @State var weightUnit: WeightUnit = UnitSettingsManager.localeUsesImperial ? .lbs : .kg
    
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
    @FocusState var focusedField: FocusedField?
    
    // Track if we're editing from confirmation screen (to return there after edit)
    @State var isEditingFromConfirmation = false
    
    // MARK: - Validation Error Messages (UX Audit Fix #1)
    var birthdayValidationError: String? {
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
    
    var heightValidationError: String? {
        if heightUnit == .ftIn && heightFeetInchesDigits.count >= 2 && !isHeightValid {
            return "Please enter a valid height (3'0\" - 8'11\")"
        }
        if heightUnit == .cm && heightCm.count >= 2 && !isHeightValid {
            return "Please enter a valid height (90-270 cm)"
        }
        return nil
    }
    
    var weightValidationError: String? {
        if weight.count >= 2 && !isWeightValid {
            return "Please enter a valid weight"
        }
        return nil
    }
    
    // MARK: - Progress Indicator (UX Audit Fix #2)
    var progressValue: Double {
        Double(currentStep.rawValue) / Double(OnboardingStep.allCases.count - 1)
    }
    
    var stepDescription: String {
        switch currentStep {
        case .auth: return "Account"
        case .username: return "Profile"
        case .phoneNumber: return hasSkippedPhoneVerification ? "Email Verification" : "Security"
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
    var heightPreviewText: String? {
        guard heightUnit == .ftIn, let parsed = parsedHeightFeetInches else { return nil }
        return "\(parsed.feet)' \(parsed.inches)\""
    }
    
    // Haptic feedback generator (UX Audit Fix #6)
    let selectionFeedback = UISelectionFeedbackGenerator()
    let impactFeedback = UIImpactFeedbackGenerator(style: .light)
    
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
    var hasMinLength: Bool { password.count >= 8 }
    var hasUppercase: Bool { password.contains(where: { $0.isUppercase }) }
    var hasLowercase: Bool { password.contains(where: { $0.isLowercase }) }
    var hasNumber: Bool { password.contains(where: { $0.isNumber }) }
    var hasSpecialChar: Bool { password.contains(where: { "!@#$%^&*()_+-=[]{}|;':\",./<>?".contains($0) }) }
    var passwordsMatch: Bool { password == confirmPassword && !confirmPassword.isEmpty }
    
    var isPasswordValid: Bool {
        hasMinLength && hasUppercase && hasLowercase && hasNumber && hasSpecialChar
    }
    
    var isAuthFormValid: Bool {
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
    var isUsernameValid: Bool {
        let cleanUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanUsername.count >= 3 && cleanUsername.count <= 30 else { return false }
        let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
        return cleanUsername.unicodeScalars.allSatisfy { allowedCharacters.contains($0) }
    }
    
    // Check if user needs to manually enter their name (social auth didn't provide it)
    var needsNameInput: Bool {
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

    // Relocated from extensions
    @State var isNavigatingForward = true

    var body: some View {
        ZStack {
            // Animated gradient background
            backgroundGradient
            
            // Auth step has its own layout when NOT in standard mode
            if currentStep == .auth && !hasStartedAuth {
                authStep
            }
            
            // Complete step has its own layout (celebration)
            else if currentStep == .complete {
                completeStep
            }
            
            // Main onboarding flow (auth standard mode + all other steps share the same layout
            // so keyboard stays up seamlessly when transitioning between text-input steps)
            else if currentStep != .limitations && currentStep != .confirmation {
                let keyboardUp = keyboardObserver.keyboardHeight > 0
                
                ZStack(alignment: .bottom) {
                    // Main content
                    VStack(spacing: 0) {
                        // Header
                        onboardingSharedHeader(compact: keyboardUp)
                            .animation(nil, value: currentStep)  // Don't animate header on step changes
                        
                        // Content (type-erased AnyView — NO .id() here, it would break @FocusState keyboard transfer)
                        currentStepContent
                            .animation(.easeInOut(duration: 0.25), value: currentStep)
                        
                        Spacer()
                    }
                    
                    // Floating button bar (auth step has custom buttons, others use shared bar)
                    if currentStep == .auth && hasStartedAuth {
                        VStack(spacing: 0) {
                            HStack(spacing: 12) {
                                if isSignUp && isOnConfirmPasswordStep {
                                    Button(action: {
                                        isOnConfirmPasswordStep = false
                                        confirmPassword = ""
                                    }) {
                                        Image(systemName: "chevron.left")
                                            .font(.ds_labelLarge)
                                            .foregroundColor(.gray)
                                            .frame(width: 52, height: 52)
                                            .background(Circle().fill(Color(.systemGray6)))
                                            .overlay(Circle().stroke(Color.gray.opacity(0.3), lineWidth: 1.5))
                                    }
                                    .accessibilityLabel("Go back")
                                    .accessibilityHint("Returns to previous step")
                                } else {
                                    Button(action: {
                                        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                                            hasStartedAuth = false
                                            focusedField = nil
                                        }
                                    }) {
                                        Image(systemName: "chevron.left")
                                            .font(.ds_labelLarge)
                                            .foregroundColor(.gray)
                                            .frame(width: 52, height: 52)
                                            .background(Circle().fill(Color(.systemGray6)))
                                            .overlay(Circle().stroke(Color.gray.opacity(0.3), lineWidth: 1.5))
                                    }
                                    .accessibilityLabel("Go back")
                                    .accessibilityHint("Returns to previous step")
                                }
                                
                                Button(action: { 
                                    if isSignUp && !isOnConfirmPasswordStep && isPasswordValid {
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
                                .accessibilityLabel(isSignUp ? "Continue" : "Sign In")
                                .accessibilityHint("Proceeds to next onboarding step")
                            }
                        }
                        .padding(.horizontal, Spacing.lg)
                        .padding(.bottom, keyboardUp ? keyboardObserver.keyboardHeight + 10 : 50)
                        .animation(.easeOut(duration: 0.25), value: keyboardObserver.keyboardHeight)
                        .animation(nil, value: isOnConfirmPasswordStep)
                    } else {
                        onboardingSharedButtonBar
                            .padding(.horizontal, Spacing.lg)
                            .padding(.bottom, keyboardUp ? keyboardObserver.keyboardHeight + 10 : 50)
                            .animation(.easeOut(duration: 0.25), value: keyboardObserver.keyboardHeight)
                            .animation(nil, value: currentStep)
                            .animation(nil, value: isCheckingUsername)
                    }
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
                                        .font(.ds_heading3)
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
                        .padding(.horizontal, Spacing.lg)
                        .padding(.top, 8)
                        .padding(.bottom, 16)
                    }
                    .clipped() // Hard clip at the scroll boundary
                    
                    // Fixed button bar at bottom
                    onboardingSharedButtonBar
                        .padding(.horizontal, Spacing.lg)
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
                        .padding(.horizontal, Spacing.lg)
                        .padding(.top, 8)
                        .padding(.bottom, 16)
                    }
                    .clipped() // Hard clip at the scroll boundary
                    
                    // Fixed button bar at bottom
                    onboardingSharedButtonBar
                        .padding(.horizontal, Spacing.lg)
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
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(0.1))
                        guard !Task.isCancelled else { return }
                        focusedField = fieldToFocus
                    }
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(0.3))
                        guard !Task.isCancelled else { return }
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
                    AppLogger.debug("Pre-filled username from social login: @\(socialUsername)", category: .auth)
                }
                // Transfer focus immediately so keyboard stays up when coming from auth/phone
                let targetField: FocusedField = name.isEmpty ? .name : .username
                focusedField = targetField
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(0.1))
                    guard !Task.isCancelled else { return }
                    focusedField = targetField
                }
            case .basics:
                focusedField = .birthday
            case .body:
                focusedField = .height
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(0.1))
                    guard !Task.isCancelled else { return }
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
            AppLogger.debug("Received new user notification - navigating to username step", category: .auth)
            handleOAuthUserOnboarding()
        }
        // NOTE: Removed the onChange(of: supabaseManager.isAuthenticated) handler
        // because it was incorrectly triggering on session restore at app launch.
        // The OAuthNewUserNeedsOnboarding notification is the correct and only trigger.
        .onAppear {
            OnboardingSessionManager.shared.startNewSession()
            
            // Restore progress from a prior interrupted session
            if !supabaseManager.isAuthenticated {
                restoreFromCheckpoint()
            }
            
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
}

#Preview {
    NewOnboardingView()
        .environmentObject(UserManager())
}
