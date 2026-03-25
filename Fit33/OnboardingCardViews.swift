import SwiftUI

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
        .accessibilityLabel("\(title), \(isSelected ? "selected" : "not selected")")
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
                .frame(width: 44, height: 44)
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
                            .font(.ds_heading2)
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
                        .font(.ds_heading1)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.ds_heading3)
                        .foregroundColor(isSelected ? .blue : .primary)
                    
                    Text(subtitle)
                        .font(.ds_bodySmall)
                        .foregroundColor(.secondary)
                    
                    Text(detail)
                        .font(.ds_bodySmall).fontWeight(.medium)
                        .foregroundColor(.blue.opacity(0.7))
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.ds_heading2)
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
                    .font(.ds_bodySmall).fontWeight(.bold)
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
                            .font(.ds_heading3)
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
                        .font(.ds_heading1)
                        .foregroundStyle(
                            AnyShapeStyle(LinearGradient(colors: [.blue, .purple.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        )
                        .frame(height: 36)
                }
                
                Text(title)
                    .font(.ds_bodySmall).fontWeight(.bold)
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
                            .font(.ds_heading3)
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
                        .font(.ds_heading1)
                }
                
                // Text content
                VStack(alignment: .leading, spacing: 4) {
                    Text(environment.displayName)
                        .font(.ds_heading3)
                        .foregroundColor(isSelected ? .blue : .primary)
                    
                    Text(subtitle)
                        .font(.ds_bodySmall)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Checkmark
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.ds_heading2)
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
                ZStack {
                    if isSelected {
                        Circle()
                            .fill(Color.blue.opacity(0.4))
                            .frame(width: 58, height: 58)
                            .blur(radius: 10)
                    }
                    
                    Circle()
                        .fill(
                            isSelected
                                ? LinearGradient(colors: [.blue, .cyan.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing)
                                : LinearGradient(colors: [colorScheme == .dark ? Color(white: 0.22) : Color(.systemGray5), colorScheme == .dark ? Color(white: 0.18) : Color(.systemGray5)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .frame(width: 52, height: 52)
                    
                    Text(emoji)
                        .font(.ds_heading2)
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.ds_labelLarge)
                        .foregroundColor(isSelected ? .blue : .primary)
                    
                    Text(subtitle)
                        .font(.ds_bodySmall)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.ds_heading2)
                        .foregroundColor(.blue)
                } else {
                    HStack(spacing: 4) {
                        ForEach(0..<5, id: \.self) { index in
                            Circle()
                                .fill(index < strengthDots ? Color.blue.opacity(0.6) : Color(.systemGray4))
                                .frame(width: 6, height: 6)
                        }
                    }
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .onboardingCardStyle(accentColor: .blue, secondaryColor: .cyan, isSelected: isSelected, cornerRadius: 20)
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
                    .font(.ds_heading3)
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
        .accessibilityLabel("\(dayName), \(isSelected ? "selected" : "not selected")")
    }
    
    private var dayName: String {
        let names = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        guard day >= 1, day <= 7 else { return "Day \(day)" }
        return names[day - 1]
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
                        .font(.ds_heading1)
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
