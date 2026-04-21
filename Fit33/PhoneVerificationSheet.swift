import SwiftUI

/// Sheet for setting up two-factor authentication via phone verification
/// Used in Profile Settings for users who skipped during onboarding
struct PhoneVerificationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    @Binding var isVerified: Bool
    @Binding var phoneNumber: String
    var onComplete: (String) -> Void
    
    // Local state
    @State private var localPhoneNumber = ""
    @State private var selectedCountryCode: CountryCode = CountryCode.fromLocale()
    @State private var verificationCode = ""
    @State private var isVerificationCodeSent = false
    @State private var isVerifyingCode = false
    @State private var verificationError = ""
    // Sprint 4 (Q2-38): countdowns unified behind `PhoneOTPCountdown`
    // (defined in `ExistingUserPhonePrompt.swift`). Each owns its own
    // `Timer` with store + invalidate; `.onDisappear` releases both.
    @StateObject private var resendCountdown = PhoneOTPCountdown()
    @StateObject private var sendCodeCountdown = PhoneOTPCountdown()
    @State private var attempts = 0
    
    @FocusState private var focusedField: Field?
    
    @StateObject private var phoneVerificationService = PhoneVerificationService.shared
    
    private let maxAttempts = 3
    
    enum Field {
        case phoneNumber, verificationCode
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Animated orb background
                AnimatedOrbBackground.stats(colorScheme: colorScheme)
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Header Icon
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
                            
                            Image(systemName: "lock.shield.fill")
                                .font(.system(size: 36, weight: .medium))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [Color.blue, Color.cyan],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        }
                        .padding(.top, 20)
                    
                    // Title & Subtitle
                    VStack(spacing: 8) {
                        Text("Two-Factor Authentication")
                            .font(.title2.weight(.bold))
                            .foregroundColor(.primary)
                        
                        Text("Add an extra layer of security to your account")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    
                    // Content based on state
                    if !isVerificationCodeSent {
                        phoneInputView
                    } else {
                        codeInputView
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, Spacing.lg)
            }
            } // Close ZStack
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.secondary)
                }
            }
        }
        .onAppear {
            if isVerified && !phoneNumber.isEmpty {
                localPhoneNumber = formatMaskedPhone(phoneNumber)
            } else {
                localPhoneNumber = phoneNumber
            }
            focusedField = .phoneNumber
        }
        .onDisappear {
            cleanupTimers()
        }
    }
    
    // MARK: - Phone Input View
    
    private var phoneInputView: some View {
        let _ = AppLogger.debug("📱 [PHONE SHEET] Rendering phoneInputView", category: .auth)
        
        return VStack(spacing: 20) {
            // Phone Number Input
            VStack(alignment: .leading, spacing: 12) {
                Text("Phone Number")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.secondary)
                
                HStack(spacing: 12) {
                    // Country code picker
                    Menu {
                        ForEach(CountryCode.allCases) { country in
                            Button {
                                AppLogger.debug("🌍 [PHONE SHEET] Selected country: \(country.name)", category: .auth)
                                selectedCountryCode = country
                                localPhoneNumber = ""
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
                    .id("countryPicker-\(selectedCountryCode.id)")
                    
                    // Phone number input
                    HStack(spacing: 12) {
                        TextField(selectedCountryCode.placeholder, text: $localPhoneNumber)
                            .keyboardType(.phonePad)
                            .textContentType(.telephoneNumber)
                            .focused($focusedField, equals: .phoneNumber)
                            .onChange(of: localPhoneNumber) { _, newValue in
                                let formatted = formatPhoneNumberForCountry(newValue)
                                if formatted != localPhoneNumber {
                                    localPhoneNumber = formatted
                                }
                            }
                        
                        if isPhoneNumberValid {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.ds_heading3)
                                .foregroundColor(.blue)
                        }
                    }
                    .font(.ds_bodyRegular).fontWeight(.medium)
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
                }
            }
            
            // Send Code Button
            if isPhoneNumberValid {
                let canSend = !sendCodeCountdown.isRunning

                Button(action: sendVerificationCode) {
                    HStack(spacing: 10) {
                        if sendCodeCountdown.secondsRemaining > 0 {
                            Image(systemName: "clock.fill")
                                .font(.ds_labelMedium)
                            Text("Retry in \(sendCodeCountdown.secondsRemaining)s")
                        } else {
                            Image(systemName: "paperplane.fill")
                                .font(.ds_labelMedium)
                            Text("Send Verification Code")
                        }
                    }
                    .font(.ds_labelLarge)
                    .foregroundColor(canSend ? .white : .gray)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.md)
                    .background(
                        Capsule()
                            .fill(canSend ? Color.blue : Color.gray.opacity(0.3))
                    )
                }
                .disabled(!canSend)
            }
            
            // Privacy Message
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
        }
    }
    
    // MARK: - Code Input View
    
    private var codeInputView: some View {
        VStack(spacing: 20) {
            // Phone number badge
            HStack(spacing: 8) {
                Image(systemName: "phone.fill")
                    .font(.ds_bodySmall)
                    .foregroundColor(.blue)
                Text("Code sent to \(formatInternationalNumber())")
                    .font(.subheadline.weight(.medium))
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.blue.opacity(0.1))
            )
            
            // Warning if last attempt
            if attempts >= maxAttempts {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.ds_bodySmall)
                    Text("Last attempt - going back will lock this feature")
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
            
            // Sprint 5 (Q2-38-b): digit-box OTP entry — canonical across
            // `ExistingUserPhonePrompt`, onboarding, and this 2FA sheet so
            // users see the same verification UX regardless of entry point.
            // Hidden TextField captures input + enables iOS SMS auto-fill;
            // visible tiles render one digit each with the active slot
            // highlighted.
            ZStack {
                TextField("", text: $verificationCode)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .autocorrectionDisabled()
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

                GeometryReader { geo in
                    let tileWidth = min(50, (geo.size.width - 50) / 6)
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
                .frame(height: 72)
                .onTapGesture {
                    focusedField = .verificationCode
                }
            }
            
            // Sprint 5 (Q2-38-b): copy aligned with onboarding's hint so users
            // see the same message wherever they land.
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
            
            // Resend / Back options
            HStack(spacing: 20) {
                Button(action: goBack) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                            .font(.ds_labelMedium)
                        Text("Change Number")
                    }
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                }
                
                if resendCountdown.secondsRemaining > 0 {
                    Text("Resend in \(resendCountdown.secondsRemaining)s")
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
        }
        .onAppear {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.3))
                guard !Task.isCancelled else { return }
                focusedField = .verificationCode
            }
        }
    }
    
    // MARK: - Helper Properties
    
    private var isPhoneNumberValid: Bool {
        let digits = localPhoneNumber.filter { $0.isNumber }
        return digits.count >= selectedCountryCode.minDigits && digits.count <= selectedCountryCode.maxDigits
    }
    
    private var fullPhoneNumber: String {
        let digits = localPhoneNumber.filter { $0.isNumber }
        return "\(selectedCountryCode.dialingCode)\(digits)"
    }
    
    
    // MARK: - Helper Functions
    
    private func getDigit(at index: Int) -> String {
        guard index < verificationCode.count else { return "" }
        let stringIndex = verificationCode.index(verificationCode.startIndex, offsetBy: index)
        return String(verificationCode[stringIndex])
    }
    
    private func formatPhoneNumber(_ input: String) -> String {
        let digits = input.filter { $0.isNumber }
        let limited = String(digits.prefix(10))
        
        var result = ""
        for (index, char) in limited.enumerated() {
            if index == 0 { result += "(" }
            if index == 3 { result += ") " }
            if index == 6 { result += "-" }
            result += String(char)
        }
        return result
    }
    
    private func formatPhoneNumberForCountry(_ input: String) -> String {
        let digits = input.filter { $0.isNumber }
        let limited = String(digits.prefix(selectedCountryCode.maxDigits))

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

        if selectedCountryCode == .uk {
            var result = ""
            for (index, char) in limited.enumerated() {
                if index == 4 { result += " " }
                result += String(char)
            }
            return result
        }

        if selectedCountryCode == .india {
            var result = ""
            for (index, char) in limited.enumerated() {
                if index == 5 { result += " " }
                result += String(char)
            }
            return result
        }

        if selectedCountryCode == .brazil {
            var result = ""
            for (index, char) in limited.enumerated() {
                if index == 2 || index == 7 { result += " " }
                result += String(char)
            }
            return result
        }

        if selectedCountryCode == .japan || selectedCountryCode == .southKorea {
            var result = ""
            for (index, char) in limited.enumerated() {
                if index == 2 || index == 6 { result += " " }
                result += String(char)
            }
            return result
        }

        if selectedCountryCode == .australia {
            var result = ""
            for (index, char) in limited.enumerated() {
                if index == 3 || index == 6 { result += " " }
                result += String(char)
            }
            return result
        }

        if selectedCountryCode == .singapore || selectedCountryCode == .hongKong {
            var result = ""
            for (index, char) in limited.enumerated() {
                if index == 4 { result += " " }
                result += String(char)
            }
            return result
        }

        var result = ""
        for (index, char) in limited.enumerated() {
            if index > 0 && index % 3 == 0 { result += " " }
            result += String(char)
        }
        return result
    }
    
    private func formatInternationalNumber() -> String {
        let digits = localPhoneNumber.filter { $0.isNumber }
        return "\(selectedCountryCode.dialingCode) \(digits)"
    }
    
    /// Format phone number with masking for privacy display
    /// Shows: +1 (•••) ••• - ••90 (only last 2 digits visible)
    private func formatMaskedPhone(_ phone: String) -> String {
        let digits = phone.filter { $0.isNumber }
        if digits.count >= 10 {
            let lastTwo = String(digits.suffix(2))
            // Extract country code if present (digits beyond 10)
            if digits.count > 10 {
                return "+\(String(digits.prefix(digits.count - 10))) (•••) ••• - ••\(lastTwo)"
            }
            return "(•••) ••• - ••\(lastTwo)"
        }
        return phone
    }
    
    private func sendVerificationCode() {
        verificationError = ""
        attempts += 1
        
        // Immediately advance to code input screen (don't wait for send)
        withAnimation(.easeInOut(duration: 0.2)) {
            isVerificationCodeSent = true
        }
        // Sprint 5 (Q2-38-b): 60s resend canonical — matches onboarding +
        // `ExistingUserPhonePrompt` so users see the same cooldown everywhere.
        resendCountdown.start(duration: 60)
        
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.3))
            guard !Task.isCancelled else { return }
            focusedField = .verificationCode
        }
        
        // Send the code in background - by the time user sees the screen, SMS arrives
        Task {
            let success = await phoneVerificationService.sendVerificationCode(to: fullPhoneNumber)
            
            if !success {
                await MainActor.run {
                    verificationError = phoneVerificationService.error ?? "Failed to send code. Tap resend to try again."
                }
            }
        }
    }
    
    private func verifyCode() {
        guard verificationCode.count == 6 else { return }
        
        isVerifyingCode = true
        verificationError = ""
        
        Task {
            let success = await phoneVerificationService.verifyCode(verificationCode, for: fullPhoneNumber)
            
            await MainActor.run {
                isVerifyingCode = false
                if success {
                    // Success! Call completion handler with full international number
                    onComplete(fullPhoneNumber)
                } else {
                    verificationError = phoneVerificationService.error ?? "Invalid code"
                    verificationCode = ""
                }
            }
        }
    }
    
    private func resendVerificationCode() {
        verificationCode = ""
        verificationError = ""
        sendVerificationCode()
    }
    
    private func goBack() {
        isVerificationCodeSent = false
        verificationCode = ""
        verificationError = ""
        
        // Start 30s cooldown before another send is allowed
        sendCodeCountdown.start(duration: 30)

        focusedField = .phoneNumber
    }

    private func cleanupTimers() {
        resendCountdown.invalidate()
        sendCodeCountdown.invalidate()
    }
}

#Preview {
    PhoneVerificationSheet(
        isVerified: .constant(false),
        phoneNumber: .constant(""),
        onComplete: { _ in }
    )
}
