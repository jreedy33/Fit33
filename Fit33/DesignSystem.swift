//
//  DesignSystem.swift
//  Fit33
//
//  Canonical design tokens and reusable UI components.
//  Use these instead of inline Color(red:), .font(.system(size:)), etc.
//  to keep visual consistency across all tabs and views.
//
//  Existing style files (AdaptiveColors.swift, OnboardingComponents.swift)
//  are still in use — this file adds the missing standard tokens.
//

import SwiftUI

// MARK: - Typography Tokens
/// Use these instead of .font(.system(size:…)) to ensure consistent typography.

extension Font {
    // Display
    static let ds_displayLarge  = Font.system(size: 42, weight: .bold)
    static let ds_displayMedium = Font.system(size: 34, weight: .bold)
    
    // Headings
    static let ds_heading1 = Font.system(size: 28, weight: .bold)
    static let ds_heading2 = Font.system(size: 22, weight: .bold)
    static let ds_heading3 = Font.system(size: 18, weight: .semibold)
    
    // Body
    static let ds_bodyLarge   = Font.system(size: 17, weight: .regular)
    static let ds_bodyMedium  = Font.system(size: 15, weight: .regular)
    static let ds_bodySmall   = Font.system(size: 13, weight: .regular)
    
    // Labels
    static let ds_labelLarge  = Font.system(size: 15, weight: .semibold)
    static let ds_labelMedium = Font.system(size: 13, weight: .semibold)
    static let ds_labelSmall  = Font.system(size: 11, weight: .medium)
    
    // Body extended
    static let ds_bodyRegular = Font.system(size: 16, weight: .regular)
    
    // Caption
    static let ds_caption = Font.system(size: 10, weight: .medium)
    
    // Mono / Stats
    static let ds_stat = Font.system(size: 24, weight: .bold, design: .rounded)
    static let ds_statSmall = Font.system(size: 18, weight: .bold, design: .rounded)
}

// MARK: - Spacing Tokens

enum Spacing {
    static let xxxs: CGFloat = 2
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
    static let xxl: CGFloat = 48
}

// MARK: - Corner Radius Tokens

enum CornerRadius {
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
    static let pill: CGFloat = 999
}

// MARK: - Gradient Presets
/// Canonical accent gradients used throughout the app.
/// Use these instead of constructing inline LinearGradient(colors:…).

extension LinearGradient {
    /// Primary blue-purple accent (buttons, headers)
    static let ds_primaryAccent = LinearGradient(
        colors: [.blue, Color(red: 0.5, green: 0.3, blue: 0.95)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    /// Cyan-blue social accent (friends tab, challenges)
    static let ds_socialAccent = LinearGradient(
        colors: [.cyan, .blue],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    /// Green success accent (completed workouts, streaks)
    static let ds_successAccent = LinearGradient(
        colors: [Color(red: 0.2, green: 0.7, blue: 0.3), Color(red: 0.15, green: 0.55, blue: 0.85)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    /// Orange-red energy accent (calories, challenges)
    static let ds_energyAccent = LinearGradient(
        colors: [.orange, .red],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

// MARK: - Reusable Section Header

/// Standard section header used across Dashboard, Meals, Friends, etc.
struct SectionHeader: View {
    let title: String
    var icon: String? = nil
    var iconColor: Color = .blue
    var action: (() -> Void)? = nil
    var actionLabel: String = "See All"
    
    var body: some View {
        HStack {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(iconColor)
            }
            Text(title)
                .font(.ds_heading3)
            
            Spacer()
            
            if let action = action {
                Button(action: action) {
                    Text(actionLabel)
                        .font(.ds_labelSmall)
                        .foregroundColor(.blue)
                }
            }
        }
    }
}

// MARK: - Standard Pill Button

struct DSPillButton: View {
    let title: String
    var icon: String? = nil
    var gradient: LinearGradient = .ds_primaryAccent
    let action: () -> Void
    
    var body: some View {
        Button(action: {
            HapticManager.impact(.light)
            action()
        }) {
            HStack(spacing: Spacing.xs) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                }
                Text(title)
                    .font(.ds_labelMedium)
            }
            .foregroundColor(.white)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.xs)
            .background(Capsule().fill(gradient))
        }
    }
}

// MARK: - Primary CTA Button

/// Full-width gradient CTA button for primary actions.
struct DSPrimaryButton: View {
    let title: String
    var icon: String? = nil
    var gradient: LinearGradient = .ds_primaryAccent
    let action: () -> Void
    
    var body: some View {
        Button(action: {
            HapticManager.impact(.light)
            action()
        }) {
            HStack(spacing: Spacing.xs) {
                Text(title)
                    .font(.ds_labelLarge)
                    .fontWeight(.bold)
                if let icon {
                    Image(systemName: icon)
                        .font(.ds_labelMedium)
                }
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                    .fill(gradient)
            )
        }
        .scaleButtonStyle(.standard, withHaptic: false)
    }
}

// MARK: - Secondary / Outline Button

/// Bordered outline button for secondary actions.
struct DSSecondaryButton: View {
    let title: String
    var icon: String? = nil
    let action: () -> Void
    
    var body: some View {
        Button(action: {
            HapticManager.impact(.light)
            action()
        }) {
            HStack(spacing: Spacing.xs) {
                if let icon {
                    Image(systemName: icon)
                        .font(.ds_labelMedium)
                }
                Text(title)
                    .font(.ds_labelMedium)
            }
            .foregroundColor(.primary)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                    .stroke(Color.primary.opacity(0.2), lineWidth: 1)
            )
        }
        .scaleButtonStyle(.standard, withHaptic: false)
    }
}

// MARK: - Empty State

/// Reusable empty state view with optional CTA.
struct DSEmptyState: View {
    let icon: String
    let title: String
    let subtitle: String
    var actionTitle: String? = nil
    var actionIcon: String? = nil
    var action: (() -> Void)? = nil
    
    var body: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: icon)
                .font(.ds_heading1)
                .foregroundColor(.secondary)
            
            Text(title)
                .font(.ds_heading3)
                .foregroundColor(.primary)
            
            Text(subtitle)
                .font(.ds_bodyMedium)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            if let actionTitle, let action {
                DSPillButton(
                    title: actionTitle,
                    icon: actionIcon ?? "arrow.right",
                    gradient: .ds_primaryAccent,
                    action: action
                )
            }
        }
        .padding(Spacing.lg)
    }
}
