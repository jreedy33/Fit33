import SwiftUI

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
                            .font(.ds_heading3).fontWeight(.semibold)
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
                                    .font(.ds_bodySmall).fontWeight(.bold)
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
                                .font(.ds_bodySmall)
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
                                        .font(.ds_heading3)
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
                            .font(.ds_heading3).fontWeight(.semibold)
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
                                .font(.ds_bodySmall)
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
                .padding(.horizontal, Spacing.xxs)
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
                    .font(.ds_bodySmall)
                    .foregroundColor(isSelected ? .white : level.color)
                    .frame(width: 24, height: 24)
                    .background(
                        Circle()
                            .fill(isSelected ? level.color : level.color.opacity(0.15))
                    )
                
                // Text
                VStack(alignment: .leading, spacing: 1) {
                    Text(level.displayName)
                        .font(.ds_labelMedium)
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
