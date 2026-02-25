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

// MARK: - Standard Card Wrapper

/// Consistent card container used for widgets, list items, etc.
/// Prefer this over constructing ad-hoc RoundedRectangle backgrounds.
struct DSCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    var cornerRadius: CGFloat = CornerRadius.xl
    @ViewBuilder let content: () -> Content
    
    var body: some View {
        content()
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.cardBackground)
                    .shadow(
                        color: colorScheme == .dark ? .clear : .black.opacity(0.08),
                        radius: 8, x: 0, y: 4
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(
                        colorScheme == .dark ? Color.white.opacity(0.08) : Color.clear,
                        lineWidth: 1
                    )
            )
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
