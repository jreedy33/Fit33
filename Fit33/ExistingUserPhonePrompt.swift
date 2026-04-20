import SwiftUI

/// One-time phone verification prompt for existing users (v1.14.3+)
/// Shows on first app launch after update to capture phone numbers for contact matching
struct ExistingUserPhonePrompt: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    var onComplete: (String) -> Void
    var onSkip: () -> Void
    
    // Local state
    @State private var phoneNumber = ""
    @State private var selectedCountryCode: CountryCode = .us
    @State private var verificationCode = ""
    @State private var isVerificationCodeSent = false
    @State private var isVerifyingCode = false
    @State private var isPhoneVerified = false
    @State private var verificationError = ""

    // Sprint 4 (Q2-38): countdowns are owned by `PhoneOTPCountdown` which
    // stores + invalidates its `Timer`. The previous implementation fired
    // `Timer.scheduledTimer` without storing a reference, leaking a live
    // timer on every tap and on `.onDisappear`.
    @StateObject private var resendCountdown = PhoneOTPCountdown()
    @StateObject private var sendCodeCountdown = PhoneOTPCountdown()
    
    @FocusState private var focusedField: Field?
    
    @StateObject private var phoneVerificationService = PhoneVerificationService.shared
    
    enum Field {
        case phoneNumber, verificationCode
    }
    
    private var fullPhoneNumber: String {
        let digits = phoneNumber.filter { $0.isNumber }
        return selectedCountryCode.rawValue + digits
    }
    
    private var isPhoneNumberValid: Bool {
        let digits = phoneNumber.filter { $0.isNumber }
        return digits.count >= 10
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
                                        colors: [Color.orange.opacity(0.2), Color.red.opacity(0.1)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 90, height: 90)
                            
                            Text("📱")
                                .font(.system(size: 44))
                        }
                        .padding(.top, 20)
                        
                        // Title & Subtitle
                        VStack(spacing: 12) {
                            Text("Connect with Friends!")
                                .font(.title2.weight(.bold))
                                .foregroundColor(.primary)
                            
                            Text("Add your phone number so friends in your contacts can find you on Fit33")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 20)
                        }
                        
                        // Content based on state
                        if isPhoneVerified {
                            verifiedView
                        } else if !isVerificationCodeSent {
                            phoneInputView
                        } else {
                            codeInputView
                        }
                        
                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, Spacing.lg)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !isPhoneVerified {
                        Button("Skip") {
                            onSkip()
                            dismiss()
                        }
                        .foregroundColor(.secondary)
                    }
                }
            }
            .onDisappear {
                resendCountdown.invalidate()
                sendCodeCountdown.invalidate()
            }
        }
    }
    
    // MARK: - Phone Input View
    
    private var phoneInputView: some View {
        VStack(spacing: 20) {
            // Phone input
            HStack(spacing: 8) {
                // Country code picker
                Menu {
                    ForEach(CountryCode.allCases) { country in
                        Button(action: {
                            selectedCountryCode = country
                            phoneNumber = ""
                        }) {
                            Text("\(country.flag) \(country.name)")
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(selectedCountryCode.flag)
                            .font(.ds_heading3)
                        Text(selectedCountryCode.rawValue)
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
                
                // Phone number field
                TextField("(555) 123-4567", text: $phoneNumber)
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
                    .font(.ds_bodyRegular).fontWeight(.medium)
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: CornerRadius.md)
                            .fill(colorScheme == .dark ? Color(white: 0.22) : Color(white: 0.95))
                    )
                    .focused($focusedField, equals: .phoneNumber)
                    .onChange(of: phoneNumber) { _, newValue in
                        phoneNumber = formatPhoneNumberForCountry(newValue, countryCode: selectedCountryCode)
                    }
            }
            
            // Privacy note
            HStack(spacing: 8) {
                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundColor(.green)
                Text("Your number is private and only used to help friends find you")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, Spacing.xs)
            
            // Send Code Button
            Button(action: sendVerificationCode) {
                HStack {
                    if sendCodeCountdown.secondsRemaining > 0 {
                        Text("Retry in \(sendCodeCountdown.secondsRemaining)s")
                    } else {
                        Text("Send Verification Code")
                    }
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.md)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(
                            isPhoneNumberValid && !sendCodeCountdown.isRunning
                                ? LinearGradient(colors: [.orange, .red], startPoint: .leading, endPoint: .trailing)
                                : LinearGradient(colors: [.gray, .gray], startPoint: .leading, endPoint: .trailing)
                        )
                )
            }
            .disabled(!isPhoneNumberValid || sendCodeCountdown.isRunning)
            
            if !verificationError.isEmpty {
                Text(verificationError)
                    .font(.caption)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
            }
        }
    }
    
    // MARK: - Code Input View
    
    private var codeInputView: some View {
        VStack(spacing: 20) {
            Text("Enter the 6-digit code sent to")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Text(fullPhoneNumber)
                .font(.headline)
                .foregroundColor(.primary)
            
            // Code input tiles
            HStack(spacing: 8) {
                ForEach(0..<6, id: \.self) { index in
                    ZStack {
                        Text(getDigit(at: index))
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .frame(width: 45, height: 55)
                            .background(
                                RoundedRectangle(cornerRadius: CornerRadius.md)
                                    .fill(colorScheme == .dark ? Color(white: 0.18) : Color.white)
                                    .shadow(color: colorScheme == .dark ? Color.black.opacity(0.4) : Color.black.opacity(0.08), radius: 6, x: 0, y: 2)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: CornerRadius.md)
                                    .stroke(focusedField == .verificationCode && verificationCode.count == index ? Color.orange : Color.clear, lineWidth: 2)
                            )
                    }
                }
            }
            .onTapGesture {
                focusedField = .verificationCode
            }
            
            // Hidden TextField for input
            TextField("", text: $verificationCode)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .autocorrectionDisabled()
                .opacity(0)
                .frame(width: 0, height: 0)
                .focused($focusedField, equals: .verificationCode)
                .onChange(of: verificationCode) { _, newValue in
                    let digits = newValue.filter { $0.isNumber }
                    verificationCode = String(digits.prefix(6))
                    if verificationCode.count == 6 {
                        verifyCode()
                    }
                }
            
            // Change number / Resend
            HStack(spacing: 20) {
                Button("Change Number") {
                    isVerificationCodeSent = false
                    verificationCode = ""
                    verificationError = ""
                }
                .font(.subheadline)
                .foregroundColor(.secondary)
                
                if resendCountdown.secondsRemaining > 0 {
                    Text("Resend in \(resendCountdown.secondsRemaining)s")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                } else {
                    Button("Resend Code") {
                        sendVerificationCode()
                    }
                    .font(.subheadline)
                    .foregroundColor(.orange)
                }
            }
            
            if isVerifyingCode {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle())
            }
            
            if !verificationError.isEmpty {
                Text(verificationError)
                    .font(.caption)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
            }
        }
        .onAppear {
            focusedField = .verificationCode
        }
    }
    
    // MARK: - Verified View
    
    private var verifiedView: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.15))
                    .frame(width: 80, height: 80)
                
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 44))
                    .foregroundColor(.green)
            }
            
            VStack(spacing: 8) {
                Text("Phone Verified!")
                    .font(.title3.weight(.bold))
                    .foregroundColor(.primary)
                
                Text("Friends can now find you on Fit33")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Button(action: {
                onComplete(fullPhoneNumber)
                dismiss()
            }) {
                Text("Continue")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.md)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(LinearGradient(colors: [.green, .mint], startPoint: .leading, endPoint: .trailing))
                    )
            }
        }
    }
    
    // MARK: - Helper Functions
    
    private func getDigit(at index: Int) -> String {
        if index < verificationCode.count {
            let idx = verificationCode.index(verificationCode.startIndex, offsetBy: index)
            return String(verificationCode[idx])
        }
        return ""
    }
    
    private func formatPhoneNumberForCountry(_ input: String, countryCode: CountryCode) -> String {
        let digits = input.filter { $0.isNumber }
        
        // US format: (XXX) XXX-XXXX (also works for Canada +1)
        if countryCode == .us {
            var result = ""
            for (index, digit) in digits.enumerated() {
                if index == 0 { result += "(" }
                if index == 3 { result += ") " }
                if index == 6 { result += "-" }
                if index < 10 { result += String(digit) }
            }
            return result
        } else {
            return String(digits.prefix(15))
        }
    }
    
    private func sendVerificationCode() {
        verificationError = ""
        sendCodeCountdown.start(duration: 30)

        Task {
            let cleanNumber = fullPhoneNumber.replacingOccurrences(of: "+", with: "")
            let success = await phoneVerificationService.sendVerificationCode(to: cleanNumber)
            
            await MainActor.run {
                if success {
                    withAnimation {
                        isVerificationCodeSent = true
                    }
                    resendCountdown.start(duration: 60)
                } else {
                    verificationError = "Failed to send code. Please try again."
                }
            }
        }
    }
    
    private func verifyCode() {
        isVerifyingCode = true
        verificationError = ""
        
        Task {
            let cleanNumber = fullPhoneNumber.replacingOccurrences(of: "+", with: "")
            let success = await phoneVerificationService.verifyCode(verificationCode, for: cleanNumber)
            
            await MainActor.run {
                isVerifyingCode = false
                if success {
                    withAnimation {
                        isPhoneVerified = true
                    }
                } else {
                    verificationError = "Invalid code. Please try again."
                    verificationCode = ""
                }
            }
        }
    }
}

#Preview {
    ExistingUserPhonePrompt(
        onComplete: { phone in AppLogger.debug("Completed: \(phone)", category: .auth) },
        onSkip: { AppLogger.debug("Skipped", category: .auth) }
    )
}

// MARK: - PhoneOTPCountdown (Sprint 4 Q2-38)
/// Owns one `Timer` and publishes the seconds remaining. Shared by
/// `ExistingUserPhonePrompt` and `PhoneVerificationSheet` so every OTP flow
/// in the app uses the same store+invalidate lifecycle — the prior inline
/// `Timer.scheduledTimer` pattern in `ExistingUserPhonePrompt` never stored
/// its reference, so every send leaked a timer.
///
/// Contract:
/// - Host view must call `invalidate()` from `.onDisappear` (cheap + idempotent).
/// - `start(duration:)` is self-protecting: it invalidates any prior timer
///   before scheduling a new one, so rapid-tap loops cannot stack timers.
/// - Closure uses `[weak self]` and self-invalidates if the instance is
///   released without `.onDisappear` firing (e.g. app background tear-down).
final class PhoneOTPCountdown: ObservableObject {
    @Published private(set) var secondsRemaining: Int = 0
    private var timer: Timer?

    var isRunning: Bool { secondsRemaining > 0 }

    func start(duration: Int) {
        invalidate()
        guard duration > 0 else { return }
        secondsRemaining = duration
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] t in
            guard let self else {
                t.invalidate()
                return
            }
            if self.secondsRemaining > 0 {
                self.secondsRemaining -= 1
            }
            if self.secondsRemaining == 0 {
                t.invalidate()
                self.timer = nil
            }
        }
    }

    func invalidate() {
        timer?.invalidate()
        timer = nil
        if secondsRemaining != 0 { secondsRemaining = 0 }
    }
}
