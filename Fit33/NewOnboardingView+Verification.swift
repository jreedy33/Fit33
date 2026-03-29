import SwiftUI

extension NewOnboardingView {
    // MARK: - Content-Only Step Views (for sliding)
    // These are simplified versions that just show the content portion
    // Content-only step views used in the sliding ZStack layout
    
    var phoneInputView: some View {
        let _ = AppLogger.verbose("Rendering phoneInputView - selectedCountryCode: \(selectedCountryCode.rawValue)", category: .ui)
        
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
    var countryCodePicker: some View {
        let _ = AppLogger.verbose("Rendering country picker - current: \(selectedCountryCode.name)", category: .ui)
        
        return Menu {
            ForEach(CountryCode.allCases) { country in
                Button {
                    AppLogger.debug("Country picker selected: \(country.name)", category: .ui)
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
                    .font(.ds_heading3)
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
        .accessibilityLabel("Country code selector, currently \(selectedCountryCode.name)")
        .id("countryPicker-\(selectedCountryCode.rawValue)")
    }
    
    // Extracted phone number text field
    var phoneNumberTextField: some View {
        let _ = AppLogger.verbose("Rendering phone field - phoneNumber: \(phoneNumber)", category: .ui)
        
        return HStack(spacing: 12) {
            TextField(selectedCountryCode.placeholder, text: $phoneNumber)
                .keyboardType(.phonePad)
                .textContentType(.telephoneNumber)
                .focused($focusedField, equals: .phoneNumber)
                .onChange(of: phoneNumber) { _, newValue in
                    let formatted = formatPhoneNumberForCountry(newValue)
                    if formatted != phoneNumber {
                        AppLogger.verbose("Phone field formatting: '\(newValue)' -> '\(formatted)'", category: .ui)
                        phoneNumber = formatted
                    }
                }
            
            if isPhoneNumberValid {
                Image(systemName: "checkmark.circle.fill")
                    .font(.ds_heading3)
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
    var phoneNumberStepContent: some View {
        let _ = AppLogger.verbose("Rendering phoneNumberStepContent", category: .ui)
        
        return VStack(spacing: 20) {
            // FALLBACK: Email verification (when phone was skipped after max attempts)
            if hasSkippedPhoneVerification {
                emailVerificationFallbackView
            }
            
            // STATE 1: PHONE NUMBER INPUT (before code sent)
            else if !isVerificationCodeSent && !isPhoneVerified {
                phoneInputView
                
                HStack(spacing: 10) {
                    Image(systemName: "lock.shield.fill")
                        .font(.ds_bodySmall)
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
                
                Button {
                    skipPhoneVerification()
                } label: {
                    Text("Skip for now")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .accessibilityLabel("Skip phone verification")
                .accessibilityHint("Continues without adding a phone number")
                .padding(.top, 4)
            }
            
            // STATE 2: VERIFICATION CODE INPUT (after code sent)
            if isVerificationCodeSent && !isPhoneVerified {
                let _ = AppLogger.verbose("Phone step showing STATE 2: Verification code input", category: .ui)
                VStack(spacing: 20) {
                    // Show which number code was sent to
                    HStack(spacing: 8) {
                        Image(systemName: "phone.fill")
                            .font(.ds_bodySmall)
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
                                .font(.ds_bodySmall)
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
                                    .accessibilityLabel("Verification digit \(index + 1) of 6")
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
                                .font(.ds_bodySmall)
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
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(0.3))
                        guard !Task.isCancelled else { return }
                        focusedField = .verificationCode
                    }
                }
            }
            
            // STATE 3: VERIFIED SUCCESS
            if isPhoneVerified {
                let _ = AppLogger.verbose("Phone step showing STATE 3: Verified success", category: .ui)
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
                            .font(.ds_bodySmall)
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
        .padding(.horizontal, Spacing.lg)
        .id("phoneNumberStepContent-\(selectedCountryCode.rawValue)-\(isVerificationCodeSent)-\(isPhoneVerified)")
    }
    
    // MARK: - Email Verification Fallback View
    
    var emailVerificationFallbackView: some View {
        VStack(spacing: 24) {
            // Icon
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.blue.opacity(0.15), Color.cyan.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)
                
                Image(systemName: isEmailVerified ? "checkmark.seal.fill" : "envelope.badge.fill")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: isEmailVerified ? [.green, .mint] : [.blue, .cyan],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            
            if isEmailVerified {
                // Verified state
                VStack(spacing: 8) {
                    Text("Email Verified!")
                        .font(.title3.weight(.bold))
                        .foregroundColor(.primary)
                    
                    Text("Your account is secured via email.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            } else if isEmailVerificationSent {
                // Waiting for verification
                VStack(spacing: 12) {
                    Text("Check Your Email")
                        .font(.title3.weight(.bold))
                        .foregroundColor(.primary)
                    
                    Text("We sent a verification link to:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Text(email)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.blue)
                    
                    Text("Tap the link in the email, then come back here.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                }
                
                // Check verification status button
                Button {
                    checkEmailVerificationStatus()
                } label: {
                    HStack(spacing: 8) {
                        if isCheckingEmailVerification {
                            ProgressView()
                                .scaleEffect(0.8)
                                .tint(.white)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.ds_labelMedium)
                        }
                        Text(isCheckingEmailVerification ? "Checking..." : "I've Verified My Email")
                    }
                    .font(.ds_labelLarge)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.md)
                    .background(Capsule().fill(Color.blue))
                }
                .disabled(isCheckingEmailVerification)
                .padding(.top, 8)
                
                // Resend option
                Button {
                    sendEmailVerification()
                } label: {
                    Text("Resend verification email")
                        .font(.subheadline)
                        .foregroundColor(.blue)
                }
                .padding(.top, 4)
                
                // Error
                if !emailVerificationError.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.caption)
                        Text(emailVerificationError)
                            .font(.caption)
                    }
                    .foregroundColor(.red)
                }
            } else {
                // Sending state
                VStack(spacing: 8) {
                    ProgressView()
                    Text("Sending verification email...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 20)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }
    
    // MARK: - Email Verification Functions
    
    func sendEmailVerification() {
        emailVerificationError = ""
        isEmailVerificationSent = false
        
        Task {
            do {
                try await supabaseManager.supabaseClient.auth.update(user: .init(email: email))
                await MainActor.run {
                    withAnimation {
                        isEmailVerificationSent = true
                    }
                }
                AppLogger.info("Verification email sent to \(email)", category: .auth)
            } catch {
                await MainActor.run {
                    isEmailVerificationSent = true
                    emailVerificationError = "Could not send email. Try again."
                }
                AppLogger.error("Email verify failed: \(error.localizedDescription)", category: .auth)
            }
        }
    }
    
    func checkEmailVerificationStatus() {
        isCheckingEmailVerification = true
        emailVerificationError = ""
        
        Task {
            do {
                // Refresh the session to get updated email_confirmed_at
                try await supabaseManager.supabaseClient.auth.refreshSession()
                let user = try await supabaseManager.supabaseClient.auth.session.user
                
                await MainActor.run {
                    isCheckingEmailVerification = false
                    if user.emailConfirmedAt != nil {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                            isEmailVerified = true
                        }
                        let generator = UINotificationFeedbackGenerator()
                        generator.notificationOccurred(.success)
                        AppLogger.info("Email verified!", category: .auth)
                    } else {
                        emailVerificationError = "Email not yet verified. Check your inbox and tap the link."
                        AppLogger.debug("Email not verified yet", category: .auth)
                    }
                }
            } catch {
                await MainActor.run {
                    isCheckingEmailVerification = false
                    emailVerificationError = "Could not check status. Try again."
                }
                AppLogger.error("Email verify check failed: \(error.localizedDescription)", category: .auth)
            }
        }
    }
    
    // Helper to get digit at index for verification code display
    func getDigit(at index: Int) -> String {
        guard index < verificationCode.count else { return "" }
        let idx = verificationCode.index(verificationCode.startIndex, offsetBy: index)
        return String(verificationCode[idx])
    }
    
    // Skip phone verification entirely — account creation deferred to confirmation step
    func skipPhoneVerification() {
        AppLogger.info("User chose to skip phone verification", category: .auth)
        
        isPhoneVerified = false
        isVerificationCodeSent = false
        
        goToNextStep()
    }
    
    // Send verification code
    func sendVerificationCode() {
        AppLogger.debug("sendVerificationCode() - phone: '\(phoneNumber)', full: '\(fullPhoneNumber)', country: \(selectedCountryCode.rawValue), attempts: \(phoneVerificationAttempts)", category: .auth)
        
        verificationError = ""
        
        // Increment attempt counter
        phoneVerificationAttempts += 1
        AppLogger.debug("Send code attempts incremented to: \(phoneVerificationAttempts)", category: .auth)
        
        // Immediately advance to code input screen (don't wait for send)
        AppLogger.debug("Setting isVerificationCodeSent = true with animation", category: .auth)
        withAnimation(.easeInOut(duration: 0.2)) {
            isVerificationCodeSent = true
        }
        AppLogger.debug("isVerificationCodeSent is now: \(isVerificationCodeSent)", category: .auth)
        
        startResendCountdown()
        
        // Focus the code field after a brief delay for view to build
        AppLogger.verbose("Scheduling focus change to verificationCode in 0.3s", category: .ui)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.3))
            guard !Task.isCancelled else { return }
            AppLogger.verbose("Setting focusedField to .verificationCode", category: .ui)
            self.focusedField = .verificationCode
        }
        
        // Send the code in background - by the time user sees the screen, SMS arrives
        AppLogger.debug("Starting async task to send SMS", category: .auth)
        Task {
            AppLogger.debug("Calling phoneVerificationService.sendVerificationCode", category: .auth)
            let success = await phoneVerificationService.sendVerificationCode(to: fullPhoneNumber)
            AppLogger.debug("SMS send result: \(success)", category: .auth)
            
            if !success {
                await MainActor.run {
                    let errorMsg = phoneVerificationService.error ?? "Failed to send code. Tap resend to try again."
                    AppLogger.error("Send code error: \(errorMsg)", category: .auth)
                    verificationError = errorMsg
                }
            }
        }
        AppLogger.debug("sendVerificationCode() complete (async task running in background)", category: .auth)
    }
    
    // Verify the entered code
    func verifyCode() {
        guard verificationCode.count == 6 else { return }
        
        isVerifyingCode = true
        verificationError = ""
        
        verifyCodeAsync()
    }
    
    func verifyCodeAsync() {
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
    
    func createMinimalAccountForEmailPasswordSignup() async {
        // Account is now created early in handleAuth(). If user is already authenticated,
        // just update the profile with phone number and skip account creation entirely.
        if supabaseManager.isAuthenticated {
            AppLogger.info("User already authenticated (account created in handleAuth) — updating phone/username only", category: .auth)
            await updatePhoneAndUsername()
            return
        }
        
        AppLogger.debug("Creating minimal account for email/password signup... email=\(email.prefix(5))*** password.count=\(password.count)", category: .auth)
        
        guard !password.isEmpty, password.count >= 6 else {
            AppLogger.error("Password is empty or too short (\(password.count) chars) at account creation — @State likely lost", category: .auth)
            await MainActor.run {
                verificationError = "Session expired. Please go back to the password step and re-enter your password."
                isPhoneVerified = false
            }
            return
        }
        
        // Retry account creation up to 3 times for transient rate-limit errors
        var lastError: Error?
        for attempt in 1...3 {
            do {
                try await signUpOrRecoverExistingAccount()
                AppLogger.info("Minimal account created! User ID: \(supabaseManager.currentUser?.id.uuidString ?? "nil") (attempt \(attempt))", category: .auth)
                
                await updatePhoneAndUsername()
                
                AppLogger.info("Minimal account ready - user can continue onboarding", category: .auth)
                return
                
            } catch {
                lastError = error
                let desc = error.localizedDescription.lowercased()
                let isRateLimit = desc.contains("rate") || desc.contains("limit") || desc.contains("too many")
                
                if isRateLimit && attempt < 3 {
                    let delaySeconds = attempt * 2
                    AppLogger.info("Account creation rate-limited (attempt \(attempt)/3), retrying in \(delaySeconds)s...", category: .auth)
                    try? await Task.sleep(for: .seconds(delaySeconds))
                    continue
                }
                break
            }
        }
        
        guard let error = lastError else { return }
        AppLogger.error("Failed to create account after retries: \(error)", category: .auth)
        await MainActor.run {
            let desc = error.localizedDescription.lowercased()
            if desc.contains("password") && (desc.contains("weak") || desc.contains("strength") || desc.contains("short")) {
                verificationError = "Password is too weak. Please go back and choose a stronger password."
                isPhoneVerified = false
            } else if desc.contains("rate") || desc.contains("limit") || desc.contains("too many") {
                // Phone IS verified — don't reset that. Show account-specific error.
                verificationError = "Account setup is temporarily busy. Tap Continue to retry."
                AppLogger.info("Phone verified but account creation rate-limited — keeping isPhoneVerified=true", category: .auth)
            } else {
                verificationError = "Account creation failed: \(error.localizedDescription)"
                isPhoneVerified = false
            }
        }
    }
    
    /// Attempt signUp; if the auth user already exists (from a prior partial failure), sign in instead.
    func signUpOrRecoverExistingAccount() async throws {
        do {
            try await supabaseManager.signUp(
                email: email,
                password: password,
                name: name.isEmpty ? "User" : name
            )
        } catch {
            let desc = error.localizedDescription.lowercased()
            let isAlreadyRegistered = desc.contains("already registered")
                || desc.contains("already exists")
                || desc.contains("user already")
                || desc.contains("email already")
            
            guard isAlreadyRegistered else { throw error }
            
            AppLogger.info("Auth user already exists (prior partial signup) — recovering via sign-in", category: .auth)
            try await supabaseManager.signIn(email: email, password: password)
            
            guard let userId = supabaseManager.currentUser?.id else {
                throw NSError(domain: "Onboarding", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "Sign-in succeeded but no user session. Please restart the app and try again."
                ])
            }
            
            // Ensure the profile row exists (it may have been the part that failed last time)
            AppLogger.debug("Ensuring profile exists for recovered user \(userId.uuidString.prefix(8))...", category: .auth)
            try? await supabaseManager.ensureProfileExists(
                userId: userId,
                name: name.isEmpty ? "User" : name,
                email: email
            )
        }
    }
    
    /// Update the profile with phone number and username (best-effort, non-fatal).
    func updatePhoneAndUsername() async {
        guard let userId = supabaseManager.currentUser?.id else { return }
        
        do {
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
            AppLogger.info("Phone added - contact matching enabled!", category: .auth)
        } catch {
            AppLogger.error("Failed to update phone on profile (non-fatal): \(error.localizedDescription)", category: .auth)
        }
        
        if !username.isEmpty {
            AppLogger.debug("Setting username: @\(username)", category: .auth)
            try? await supabaseManager.setUsername(username)
        }
    }
    
    // Create a minimal profile immediately after phone verification
    // This enables contact matching to work during onboarding
    func createMinimalProfileForContactMatching() async {
        guard let userId = supabaseManager.currentUser?.id else {
            AppLogger.warning("No user ID available for early profile", category: .auth)
            return
        }
        
        AppLogger.debug("Creating minimal profile for contact matching - User: \(userId.uuidString), Phone: \(fullPhoneNumber), Email: \(email)", category: .auth)
        
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
            
            AppLogger.info("Minimal profile created - contact matching now enabled!", category: .auth)
        } catch {
            AppLogger.error("Failed to create early profile: \(error)", category: .auth)
        }
    }
    
    // Resend verification code
    func resendVerificationCode() {
        verificationCode = ""
        verificationError = ""
        sendVerificationCode()
    }
    
    // Start countdown for resend
    func startResendCountdown() {
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
    func startSendCodeCountdownTimer() {
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
    func formatPhoneNumber(_ input: String) -> String {
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
    func formatPhoneNumberForCountry(_ input: String) -> String {
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
    func formatInternationalNumber() -> String {
        let digits = phoneNumber.filter { $0.isNumber }
        return "\(selectedCountryCode.dialingCode) \(digits)"
    }
}
