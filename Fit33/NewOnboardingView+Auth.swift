import SwiftUI
import AuthenticationServices

extension NewOnboardingView {
    func handleOAuthUserOnboarding() {
        AppLogger.debug("handleOAuthUserOnboarding called - currentStep: \(currentStep)", category: .auth)
        
        let metadata = supabaseManager.currentUser?.userMetadata ?? [:]
        AppLogger.debug("Current user metadata: \(metadata)", category: .auth)
        
        // Pre-fill FULL NAME (first + last) from OAuth provider
        // Try ALL sources to find the name - be flexible with type casting
        var foundFullName: String? = nil
        
        // 1. Try UserDefaults first (stored by SupabaseManager during sign-in)
        if let oauthName = UserDefaults.standard.string(forKey: "pending_oauth_name"), !oauthName.isEmpty {
            foundFullName = oauthName
            UserDefaults.standard.removeObject(forKey: "pending_oauth_name")
            AppLogger.debug("Got full name from UserDefaults: \(oauthName)", category: .auth)
        }
        
        // 2. Try user metadata - handle various types (String, AnyJSON, etc.)
        if foundFullName == nil {
            // Try full_name first
            if let fullNameValue = metadata["full_name"] {
                let fullNameString = String(describing: fullNameValue)
                if !fullNameString.isEmpty && fullNameString != "nil" && fullNameString != "<null>" {
                    foundFullName = fullNameString
                    AppLogger.debug("Got full name from metadata (full_name): \(fullNameString)", category: .auth)
                }
            }
            
            // Try name as fallback
            if foundFullName == nil, let nameValue = metadata["name"] {
                let nameString = String(describing: nameValue)
                if !nameString.isEmpty && nameString != "nil" && nameString != "<null>" {
                    foundFullName = nameString
                    AppLogger.debug("Got full name from metadata (name): \(nameString)", category: .auth)
                }
            }
        }
        
        // Set the full name if we found one
        if let foundFullName = foundFullName, !foundFullName.isEmpty {
            name = foundFullName
            AppLogger.info("OAuth set full name to: '\(foundFullName)'", category: .auth)
        } else {
            AppLogger.warning("OAuth could not find name in any source", category: .auth)
        }
        
        // Pre-fill email - try current user first (most reliable), then UserDefaults
        if let userEmail = supabaseManager.currentUser?.email, !userEmail.isEmpty {
            email = userEmail
            AppLogger.debug("Pre-filled email from current user: \(userEmail)", category: .auth)
        } else if let oauthEmail = UserDefaults.standard.string(forKey: "pending_oauth_email"), !oauthEmail.isEmpty {
            email = oauthEmail
            UserDefaults.standard.removeObject(forKey: "pending_oauth_email")
            AppLogger.debug("Pre-filled email from UserDefaults: \(oauthEmail)", category: .auth)
        }
        
        AppLogger.debug("OAuth final values - name: '\(name)', email: '\(email)'", category: .auth)
        AppLogger.debug("OAuth needsNameInput will be: \(needsNameInput)", category: .auth)
        
        // Navigate to username step (name pre-filled from OAuth)
        AppLogger.debug("OAuth navigating to username step...", category: .auth)
        navigateTo(.username)
        
        // Auto-focus the appropriate field based on whether name was filled
        let targetField: FocusedField = name.isEmpty ? .name : .username
        DispatchQueue.main.async {
            focusedField = targetField
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.1))
            guard !Task.isCancelled else { return }
            focusedField = targetField
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.3))
            guard !Task.isCancelled else { return }
            focusedField = targetField
        }
        AppLogger.debug("OAuth focus set to: \(targetField)", category: .auth)
    }

    // MARK: - Auth Step (Non-Standard Mode - used before user starts interacting)
    var authStep: some View {
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
                            for delay in [0.1, 0.3, 0.5] {
                                Task { @MainActor in
                                    try? await Task.sleep(for: .seconds(delay))
                                    guard !Task.isCancelled else { return }
                                    withAnimation(.easeOut(duration: 0.3)) {
                                        proxy.scrollTo("bottomSpacer", anchor: .bottom)
                                    }
                                }
                            }
                        }
                    }
                    .onChange(of: focusedField) { _, newFocus in
                        if newFocus == .confirmPassword {
                            for delay in [0.05, 0.2, 0.4] {
                                Task { @MainActor in
                                    try? await Task.sleep(for: .seconds(delay))
                                    guard !Task.isCancelled else { return }
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
                                Task { @MainActor in
                                    try? await Task.sleep(for: .seconds(0.45))
                                    guard !Task.isCancelled else { return }
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
                            .accessibilityHint("Returns to previous step")
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
                                    .font(.ds_bodySmall).fontWeight(.bold)
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
                    .accessibilityHint("Proceeds to next onboarding step")
                    }
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.bottom, keyboardObserver.keyboardHeight + 10)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                .animation(.easeOut(duration: 0.25), value: keyboardObserver.keyboardHeight)
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: hasStartedAuth)
    }
    
    // Auth toggle - unified segmented control style
    var authToggleButtons: some View {
        HStack(spacing: 8) {
            // Sign Up Button
            Button(action: { 
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { isSignUp = true }
                clearAuthMessages()
            }) {
                Text("Sign Up")
                    .font(.ds_labelMedium)
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
                    .font(.ds_labelMedium)
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
    var authFormContent: some View {
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
                            .font(.ds_bodySmall).fontWeight(.medium)
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
                            AppLogger.debug("Switching to confirm password field", category: .auth)
                            DispatchQueue.main.async {
                                focusedField = .confirmPassword
                            }
                            Task { @MainActor in
                                focusedField = .confirmPassword
                            }
                            Task { @MainActor in
                                try? await Task.sleep(for: .seconds(0.1))
                                guard !Task.isCancelled else { return }
                                focusedField = .confirmPassword
                            }
                            Task { @MainActor in
                                try? await Task.sleep(for: .seconds(0.2))
                                guard !Task.isCancelled else { return }
                                focusedField = .confirmPassword
                            }
                        } else {
                            // Switched back to first password
                            AppLogger.debug("Switching back to first password field", category: .auth)
                            DispatchQueue.main.async {
                                focusedField = .password
                            }
                            Task { @MainActor in
                                focusedField = .password
                            }
                            Task { @MainActor in
                                try? await Task.sleep(for: .seconds(0.1))
                                guard !Task.isCancelled else { return }
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
                                            .font(.ds_bodySmall).fontWeight(.bold)
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
                        .padding(.horizontal, Spacing.xxs)
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
                                        .font(.ds_bodySmall).fontWeight(.bold)
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

    // MARK: - Equipment/Location Helpers
    
    func mapWorkoutLocationToEquipmentLocation(_ location: WorkoutEnvironmentService.WorkoutEnvironment) -> EquipmentLocation {
        switch location {
        case .gym: return .gym
        case .home: return .home
        case .outdoor: return .outdoor
        case .hybrid: return .hybrid
        }
    }
    
    func returnToConfirmation() {
        currentStep = .confirmation
        isEditingFromConfirmation = false
    }
    
    // Create account (for signup) and complete onboarding
    func createAccountAndComplete() {
        showError = false
        errorMessage = ""
        emailAlreadyExists = false
        
        // Log validation state for debugging
        AppLogger.debug("createAccountAndComplete called - isSignUp: \(isSignUp), email: \(email), pwLen: \(password.count), isAuth: \(supabaseManager.isAuthenticated)", category: .auth)
        
        // If user is already authenticated (social sign-in OR email/password created after phone verification)
        if supabaseManager.isAuthenticated {
            AppLogger.info("User already authenticated - completing onboarding with full profile update", category: .auth)
            completeOnboarding()
            return
        }
        
        // Validate email format
        guard email.contains("@") && email.contains(".") else {
            AppLogger.error("Invalid email format: \(email)", category: .auth)
            SessionLogManager.shared.logAuthFailure(method: "email_signup", error: "Invalid email format")
            errorMessage = "Please enter a valid email address"
            showError = true
            return
        }
        
        // Validate password length
        guard password.count >= 6 else {
            AppLogger.error("Password too short: \(password.count) chars", category: .auth)
            SessionLogManager.shared.logAuthFailure(method: "email_signup", error: "Password too short (\(password.count) chars)")
            errorMessage = "Password must be at least 6 characters"
            showError = true
            return
        }
        
        if isSignUp {
            // Fallback: this path should rarely be reached since account is created after phone verification.
            // But if the user arrives here unauthenticated, try signUp with recovery.
            Task {
                do {
                    AppLogger.warning("Confirmation signup fallback — attempting signUp or recovery", category: .auth)
                    
                    // Try signUp; if user already exists, sign in instead
                    do {
                        try await supabaseManager.signUp(email: email, password: password, name: name.isEmpty ? "User" : name)
                    } catch {
                        let desc = error.localizedDescription.lowercased()
                        let isAlreadyRegistered = desc.contains("already registered")
                            || desc.contains("already exists")
                            || desc.contains("user already")
                            || desc.contains("email already")
                        
                        if isAlreadyRegistered {
                            AppLogger.info("Auth user already exists — recovering via sign-in", category: .auth)
                            try await supabaseManager.signIn(email: email, password: password)
                            if let userId = supabaseManager.currentUser?.id {
                                try? await supabaseManager.ensureProfileExists(
                                    userId: userId,
                                    name: name.isEmpty ? "User" : name,
                                    email: email
                                )
                            }
                        } else {
                            throw error
                        }
                    }
                    
                    AppLogger.info("Signup successful, authenticated: \(supabaseManager.isAuthenticated), userID: \(supabaseManager.currentUser?.id.uuidString ?? "nil")", category: .auth)
                    
                    if !username.isEmpty {
                        try? await supabaseManager.setUsername(username)
                    }
                    
                    await MainActor.run {
                        completeOnboarding()
                    }
                } catch {
                    AppLogger.error("Signup failed: \(error.localizedDescription)", category: .auth)
                    SessionLogManager.shared.logAuthFailure(method: "email_signup", error: error.localizedDescription)
                    
                    await MainActor.run {
                        errorMessage = error.localizedDescription
                        showError = true
                    }
                }
            }
        } else {
            // For sign in: User is already authenticated, just complete onboarding
            completeOnboarding()
        }
    }
    
    func sendPasswordReset() {
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
        
        AppLogger.debug("Sending password reset email to: \(email)", category: .auth)
        
        Task {
            do {
                try await supabaseManager.resetPassword(email: email)
                await MainActor.run {
                    passwordResetSent = true
                    HapticManager.notification(.success)
                    AppLogger.info("Password reset email sent successfully", category: .auth)
                    
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(10))
                        guard !Task.isCancelled else { return }
                        passwordResetSent = false
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to send reset email. Please check your email address and try again."
                    showError = true
                    AppLogger.error("Password reset failed: \(error.localizedDescription)", category: .auth)
                }
            }
        }
    }
    
    func clearAuthMessages() {
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

    // MARK: - Actions
    
    var isAuthValid: Bool {
        !email.isEmpty && password.count >= 6
    }
    
    func handleAuth() {
        AppLogger.debug("handleAuth() called - isSignUp: \(isSignUp), email: '\(email)', pwLen: \(password.count)", category: .auth)
        
        showError = false
        errorMessage = ""
        showAuthProviderHint = false
        
        if isSignUp {
            // Create account NOW while password @State is still available.
            // Previously, account creation was deferred until after phone verification
            // (~10 steps later), but @State password was often lost by then — causing
            // "Session expired" errors for email/password signups.
            AppLogger.debug("Sign up mode - creating account before navigating", category: .auth)
            isOnConfirmPasswordStep = false
            
            Task {
                do {
                    try await signUpOrRecoverExistingAccount()
                    
                    await MainActor.run {
                        AppLogger.info("Account created, navigating to username step", category: .auth)
                        
                        let targetField: FocusedField = name.isEmpty ? .name : .username
                        focusedField = targetField
                        navigateTo(.username)
                        
                        Task { @MainActor in
                            try? await Task.sleep(for: .seconds(0.05))
                            guard !Task.isCancelled else { return }
                            focusedField = targetField
                        }
                        Task { @MainActor in
                            try? await Task.sleep(for: .seconds(0.15))
                            guard !Task.isCancelled else { return }
                            focusedField = targetField
                        }
                    }
                } catch {
                    await MainActor.run {
                        let desc = error.localizedDescription.lowercased()
                        if desc.contains("rate") || desc.contains("limit") || desc.contains("too many") {
                            errorMessage = "Too many attempts. Please wait a moment and try again."
                        } else if desc.contains("password") && (desc.contains("weak") || desc.contains("strength")) {
                            errorMessage = "Password is too weak. Please choose a stronger password."
                        } else {
                            errorMessage = error.localizedDescription
                        }
                        showError = true
                        AppLogger.error("Account creation failed in handleAuth: \(error.localizedDescription)", category: .auth)
                    }
                }
            }
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
                            AppLogger.info("Returning user signed in - onboarding complete, switching to main app", category: .auth)
                            // Don't navigate - ContentView will handle it
                        } else {
                            // New user or incomplete onboarding - continue onboarding flow
                            AppLogger.debug("User needs onboarding - continuing to basics", category: .auth)
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

    // MARK: - Social Login Handlers
    
    func handleAppleSignIn() {
        AppLogger.debug("handleAppleSignIn called", category: .auth)
        socialAuthService.signInWithApple { result in
            AppLogger.debug("Apple auth callback received", category: .auth)
            switch result {
            case .success(let credentials):
                AppLogger.debug("Got Apple credentials, starting Supabase auth...", category: .auth)
                
                // Extract FULL NAME (first + last) from Apple credentials (only available on FIRST sign-in)
                // Apple only provides the name once, so we need to capture and persist it
                var appleProvidedFullName: String? = nil
                if let fullName = credentials.fullName {
                    let firstName = fullName.givenName ?? ""
                    let lastName = fullName.familyName ?? ""
                    AppLogger.debug("Apple raw name components - givenName: '\(fullName.givenName ?? "nil")', familyName: '\(fullName.familyName ?? "nil")'", category: .auth)
                    let fullNameStr = [firstName, lastName].filter { !$0.isEmpty }.joined(separator: " ")
                    if !fullNameStr.isEmpty {
                        appleProvidedFullName = fullNameStr
                        AppLogger.info("Got full name from Apple: \(fullNameStr)", category: .auth)
                    } else {
                        AppLogger.warning("Apple returned empty name components (this happens after first sign-in)", category: .auth)
                    }
                } else {
                    AppLogger.warning("Apple did NOT provide fullName (nil)", category: .auth)
                }
                AppLogger.debug("Apple email from credentials: \(credentials.email ?? "nil")", category: .auth)
                
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
                        AppLogger.debug("Supabase signInWithApple returned. isNewUser: \(isNewUser)", category: .auth)
                        
                        // Set the FULL NAME (first + last) in onboarding state
                        await MainActor.run {
                            AppLogger.debug("Looking for user's full name... appleProvidedFullName: \(appleProvidedFullName ?? "nil")", category: .auth)
                            
                            if let providedFullName = appleProvidedFullName, !providedFullName.isEmpty {
                                name = providedFullName
                                AppLogger.info("Apple auth using full name from credentials: '\(providedFullName)'", category: .auth)
                            } else if let userId = supabaseManager.currentUser?.id {
                                AppLogger.debug("Checking persisted names for userId: \(userId.uuidString.prefix(8))...", category: .auth)
                                
                                // Try to get persisted full name from previous Apple sign-in
                                let persistedKey = "apple_user_name_\(userId.uuidString)"
                                let persistedFullName = UserDefaults.standard.string(forKey: persistedKey)
                                AppLogger.debug("UserDefaults[\(persistedKey)]: \(persistedFullName ?? "nil")", category: .auth)
                                
                                if let persistedFullName = persistedFullName, 
                                   !persistedFullName.isEmpty, 
                                   persistedFullName != "Apple User" {
                                    name = persistedFullName
                                    AppLogger.info("Apple auth using persisted full name from UserDefaults: '\(persistedFullName)'", category: .auth)
                                } else {
                                    let pendingName = UserDefaults.standard.string(forKey: "pending_oauth_name")
                                    AppLogger.debug("UserDefaults[pending_oauth_name]: \(pendingName ?? "nil")", category: .auth)
                                    
                                    if let pendingName = pendingName,
                                       !pendingName.isEmpty,
                                       pendingName != "Apple User" {
                                        // Check pending_oauth_name (just set by SupabaseManager)
                                        name = pendingName
                                        AppLogger.info("Apple auth using pending OAuth full name: '\(pendingName)'", category: .auth)
                                    } else {
                                        AppLogger.warning("Apple auth: no valid name found in any source (Apple only provides name once, or persisted name was cleared)", category: .auth)
                                    }
                                }
                            }
                            
                            AppLogger.debug("Apple auth final full name value: '\(name)'", category: .auth)
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
                            AppLogger.info("Apple sign-in complete. isNewUser: \(isNewUser), name: \(name), hasCompletedOnboarding: \(userManager.hasCompletedOnboarding)", category: .auth)
                            
                            if isNewUser {
                                // New user - go to username step (name pre-filled from Apple)
                                AppLogger.debug("New Apple user - directing to username step", category: .auth)
                                navigateTo(.username)
                                // Auto-focus username field since name is pre-filled
                                DispatchQueue.main.async {
                                    focusedField = .username
                                }
                                Task { @MainActor in
                                    try? await Task.sleep(for: .seconds(0.1))
                                    guard !Task.isCancelled else { return }
                                    focusedField = .username
                                }
                                Task { @MainActor in
                                    try? await Task.sleep(for: .seconds(0.3))
                                    guard !Task.isCancelled else { return }
                                    focusedField = .username
                                }
                            } else {
                                // Returning user - force reload from Core Data to get latest onboarding status
                                userManager.reloadCurrentUser()
                                AppLogger.debug("Apple auth after reload - hasCompletedOnboarding: \(userManager.hasCompletedOnboarding)", category: .auth)
                                
                                if userManager.hasCompletedOnboarding {
                                    // They completed onboarding - ContentView will show main app automatically
                                    // because it observes userManager.hasCompletedOnboarding
                                    AppLogger.info("Returning Apple user signed in - onboarding complete, switching to main app", category: .auth)
                                } else {
                                    // They started but didn't finish onboarding - continue from phone number
                                    AppLogger.debug("Returning Apple user - continuing onboarding", category: .auth)
                                    navigateTo(.phoneNumber)
                                }
                            }
                        }
                    } catch {
                        AppLogger.error("Apple auth error during sign-in: \(error)", category: .auth)
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
    
    func handleGoogleSignIn() {
        AppLogger.debug("Starting Google Sign-In with ASWebAuthenticationSession", category: .auth)
        
        guard let authURL = supabaseManager.getGoogleOAuthURL() else {
            errorMessage = "Could not create Google Sign-In URL"
            showError = true
            return
        }
        
        AppLogger.debug("Google auth URL: \(authURL.absoluteString)", category: .auth)
        
        // Use ASWebAuthenticationSession for OAuth - this handles callbacks properly
        let session = ASWebAuthenticationSession(
            url: authURL,
            callbackURLScheme: "fit33"
        ) { callbackURL, error in
            if let error = error {
                // Check if user cancelled
                if (error as NSError).code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                    AppLogger.debug("Google auth user cancelled login", category: .auth)
                    return
                }
                AppLogger.error("Google auth error: \(error.localizedDescription)", category: .auth)
                DispatchQueue.main.async {
                    self.errorMessage = "Google Sign-In failed: \(error.localizedDescription)"
                    self.showError = true
                }
                return
            }
            
            guard let callbackURL = callbackURL else {
                AppLogger.error("Google auth: no callback URL received", category: .auth)
                return
            }
            
            AppLogger.info("Google auth callback URL received: \(callbackURL.absoluteString)", category: .auth)
            
            // Post notification to handle the OAuth callback
            NotificationCenter.default.post(name: Notification.Name("OAuthCallback"), object: callbackURL)
        }
        
        // Set presentation context and start
        session.presentationContextProvider = WebAuthContextProvider.shared
        session.prefersEphemeralWebBrowserSession = true // Skip the "wants to use X to sign in" dialog
        
        if !session.start() {
            AppLogger.error("Google auth: failed to start ASWebAuthenticationSession", category: .auth)
            errorMessage = "Could not start Google Sign-In"
            showError = true
        }
    }
    
    func handleFacebookSignIn() {
        AppLogger.debug("Starting Facebook Sign-In with ASWebAuthenticationSession", category: .auth)
        
        guard let authURL = supabaseManager.getFacebookOAuthURL() else {
            errorMessage = "Could not create Facebook Sign-In URL"
            showError = true
            AppLogger.error("Facebook auth: failed to create OAuth URL", category: .auth)
            return
        }
        
        AppLogger.debug("Facebook auth URL: \(authURL.absoluteString)", category: .auth)
        
        // Use ASWebAuthenticationSession for OAuth
        let session = ASWebAuthenticationSession(
            url: authURL,
            callbackURLScheme: "fit33"
        ) { callbackURL, error in
            if let error = error {
                if (error as NSError).code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                    AppLogger.debug("Facebook auth user cancelled login", category: .auth)
                    return
                }
                AppLogger.error("Facebook auth error: \(error.localizedDescription)", category: .auth)
                DispatchQueue.main.async {
                    self.errorMessage = "Facebook Sign-In failed: \(error.localizedDescription)"
                    self.showError = true
                }
                return
            }
            
            guard let callbackURL = callbackURL else {
                AppLogger.error("Facebook auth: no callback URL received", category: .auth)
                return
            }
            
            AppLogger.info("Facebook auth callback URL received: \(callbackURL.absoluteString)", category: .auth)
            
            // Post notification to handle the OAuth callback
            NotificationCenter.default.post(name: Notification.Name("OAuthCallback"), object: callbackURL)
        }
        
        session.presentationContextProvider = WebAuthContextProvider.shared
        session.prefersEphemeralWebBrowserSession = true // Skip the "wants to use X to sign in" dialog
        
        if !session.start() {
            AppLogger.error("Facebook auth: failed to start ASWebAuthenticationSession", category: .auth)
            errorMessage = "Could not start Facebook Sign-In"
            showError = true
        }
    }
}
