import SwiftUI

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
                    .font(.ds_bodySmall).fontWeight(.medium)
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
                            .font(.ds_bodySmall)
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
            .padding(.horizontal, Spacing.xxs)
            
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
    @State private var cursorTimer: Timer? = nil
    
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
                .font(.ds_heading3)
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
            cursorTimer?.invalidate()
            cursorTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
                showCursor.toggle()
            }
        }
        .onDisappear {
            cursorTimer?.invalidate()
            cursorTimer = nil
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
