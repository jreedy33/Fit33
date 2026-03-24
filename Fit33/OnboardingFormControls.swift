import SwiftUI

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
                .font(.ds_heading3)
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
                .font(.ds_heading3)
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
        .padding(.vertical, Spacing.xxs)
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
            .padding(.vertical, Spacing.xxs)
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
                .font(.ds_bodySmall)
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
                                    .font(.ds_labelMedium)
                                Text("Back")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                            }
                            .foregroundColor(.secondary)
                        }
                        .accessibilityHint("Returns to previous step")
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
                                .font(.ds_labelMedium)
                        }
                        .foregroundStyle(
                            canContinue
                                ? AnyShapeStyle(LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing))
                                : AnyShapeStyle(Color.gray.opacity(0.5))
                        )
                    }
                    .disabled(!canContinue)
                    .accessibilityHint("Proceeds to next onboarding step")
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
                                .padding(.horizontal, Spacing.xl)
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
