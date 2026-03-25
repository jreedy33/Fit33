import SwiftUI

extension NewOnboardingView {
    // Navigation direction for slide animation
    
    var slideTransition: AnyTransition {
        AnyTransition.asymmetric(
            insertion: .move(edge: isNavigatingForward ? .trailing : .leading),
            removal: .move(edge: isNavigatingForward ? .leading : .trailing)
        )
    }

    // MARK: - Shared Header (Simple, fixed layout)
    @ViewBuilder
    func onboardingSharedHeader(compact: Bool = false) -> some View {
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
        .padding(.top, {
            let scenes = UIApplication.shared.connectedScenes
            if let windowScene = scenes.first(where: { $0 is UIWindowScene }) as? UIWindowScene,
               let topInset = windowScene.windows.first?.safeAreaInsets.top, topInset > 0 {
                return max(topInset + 10, 50)
            }
            return 70
        }())
        .padding(.bottom, currentStep == .auth ? 12 : 24)
    }

    // MARK: - Step Titles
    var onboardingStepTitle: String {
        switch currentStep {
        case .auth: return isSignUp ? "Create Account" : "Welcome Back"
        case .phoneNumber: return hasSkippedPhoneVerification ? "Verify Your Email" : "Secure Your Account"
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
    
    var onboardingStepSubtitle: String {
        switch currentStep {
        case .auth: return isSignUp ? "Join the club" : "Continue your journey"
        case .phoneNumber: return hasSkippedPhoneVerification ? "Confirm your email address to secure your account" : "Set up two-factor authentication"
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
    
    var onboardingStepExplanation: String {
        switch currentStep {
        case .auth: return ""
        case .phoneNumber: return hasSkippedPhoneVerification ? "A verification link has been sent to your email" : "Your phone number is private and will never be displayed publicly or shared with others"
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
    var onboardingSharedButtonBar: some View {
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
            .accessibilityLabel("Go back")
            .accessibilityHint("Returns to previous step")
            
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
                            .font(.ds_labelMedium)
                    }
                    if currentStep == .phoneNumber && sendCodeCountdown > 0 {
                        Image(systemName: "clock.fill")
                            .font(.ds_labelMedium)
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
            .accessibilityLabel("Continue to next step")
            .accessibilityHint("Proceeds to next onboarding step")
        }
    }
    
    // MARK: - Continue Button Text
    var continueButtonText: String {
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
            if hasSkippedPhoneVerification {
                return isEmailVerified ? "Continue" : "Waiting for Verification..."
            }
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
    var isCurrentStepValid: Bool {
        switch currentStep {
        case .auth: return isAuthFormValid
        case .phoneNumber: 
            // If phone was skipped, require email verification
            if hasSkippedPhoneVerification {
                return isEmailVerified
            }
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
    var isPhoneNumberValid: Bool {
        let digits = phoneNumber.filter { $0.isNumber }
        return digits.count >= selectedCountryCode.minDigits && digits.count <= selectedCountryCode.maxDigits
    }
    
    // Get full E.164 formatted phone number for sending to Twilio
    var fullPhoneNumber: String {
        let digits = phoneNumber.filter { $0.isNumber }
        return "\(selectedCountryCode.dialingCode)\(digits)"
    }

    // MARK: - Step Content
    // Hybrid approach: text-input steps use simultaneous conditionals in a ZStack
    // so @FocusState can transfer keyboard seamlessly between them. Non-text steps
    // use an AnyView switch. Outer AnyView prevents stack overflow in the body.
    var currentStepContent: AnyView {
        return AnyView(
            ZStack {
                if currentStep == .auth && hasStartedAuth {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 0) {
                            authFormContent
                                .padding(.top, 8)
                        }
                    }
                    .scrollDismissesKeyboard(.interactively)
                }
                if currentStep == .phoneNumber { phoneNumberStepContent }
                if currentStep == .username { usernameStepContent }
                if currentStep == .basics { basicsStepContent }
                if currentStep == .body { bodyStepContent }

                nonTextStepContent
            }
        )
    }

    private var nonTextStepContent: AnyView {
        switch currentStep {
        case .goal: return AnyView(goalStepContent)
        case .experience: return AnyView(experienceStepContent)
        case .strengthAssessment: return AnyView(strengthStepContent)
        case .workoutLocation: return AnyView(locationStepContent)
        case .equipment: return AnyView(equipmentStepContent)
        case .schedule: return AnyView(scheduleStepContent)
        case .profilePhoto: return AnyView(profilePhotoStepContent)
        case .contacts: return AnyView(contactsStepContent)
        case .addFriends: return AnyView(addFriendsStepContent)
        default: return AnyView(EmptyView())
        }
    }

    // MARK: - Background with Animated Orbs
    var backgroundGradient: some View {
        AnimatedOrbBackground.onboarding(colorScheme: colorScheme)
            .accessibilityHidden(true)
    }
    
    // MARK: - Progress Indicator (UX Audit Fix #2)
    var progressIndicator: some View {
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
        .padding(.horizontal, Spacing.lg)
    }
    
}
