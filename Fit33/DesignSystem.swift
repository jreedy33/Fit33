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
import UIKit

// MARK: - Typography Tokens
/// Use these instead of .font(.system(size:…)) to ensure consistent typography.
///
/// Every `ds_*` token now scales with Dynamic Type via `UIFontMetrics`. At the
/// default content size category each token renders at the exact pixel size
/// declared below (no visual regression for users at default Dynamic Type),
/// but at larger sizes the font scales proportionally relative to the chosen
/// `UIFont.TextStyle`. Consumers never need to add their own scaling — reach
/// for a `ds_*` token and the scaling is automatic.

private extension Font {
    /// Returns a system font that scales with Dynamic Type relative to the given text style.
    /// Uses `UIFontMetrics` to honor the user's preferred content size category while
    /// preserving the design intent of the original pixel size at default scale.
    static func dsScaled(
        _ size: CGFloat,
        weight: Font.Weight,
        design: Font.Design = .default,
        relativeTo style: UIFont.TextStyle
    ) -> Font {
        let scaled = UIFontMetrics(forTextStyle: style).scaledValue(for: size)
        return .system(size: scaled, weight: weight, design: design)
    }
}

extension Font {
    // Display
    static var ds_displayLarge: Font  { .dsScaled(42, weight: .bold, relativeTo: .largeTitle) }
    static var ds_displayMedium: Font { .dsScaled(34, weight: .bold, relativeTo: .largeTitle) }

    // Headings
    static var ds_heading1: Font { .dsScaled(28, weight: .bold, relativeTo: .title1) }
    static var ds_heading2: Font { .dsScaled(22, weight: .bold, relativeTo: .title2) }
    static var ds_heading3: Font { .dsScaled(18, weight: .semibold, relativeTo: .title3) }

    // Body
    static var ds_bodyLarge: Font  { .dsScaled(17, weight: .regular, relativeTo: .body) }
    static var ds_bodyMedium: Font { .dsScaled(15, weight: .regular, relativeTo: .subheadline) }
    static var ds_bodySmall: Font  { .dsScaled(13, weight: .regular, relativeTo: .footnote) }

    // Labels
    static var ds_labelLarge: Font  { .dsScaled(15, weight: .semibold, relativeTo: .subheadline) }
    static var ds_labelMedium: Font { .dsScaled(13, weight: .semibold, relativeTo: .footnote) }
    static var ds_labelSmall: Font  { .dsScaled(11, weight: .medium, relativeTo: .caption2) }

    // Body extended
    static var ds_bodyRegular: Font { .dsScaled(16, weight: .regular, relativeTo: .body) }

    // Caption
    static var ds_caption: Font { .dsScaled(10, weight: .medium, relativeTo: .caption2) }

    // Mono / Stats
    static var ds_stat: Font      { .dsScaled(24, weight: .bold, design: .rounded, relativeTo: .title2) }
    static var ds_statSmall: Font { .dsScaled(18, weight: .bold, design: .rounded, relativeTo: .title3) }

    // Timer
    static var ds_timer: Font { .dsScaled(56, weight: .bold, design: .rounded, relativeTo: .largeTitle) }
}

#if DEBUG
#Preview("Typography — default Dynamic Type") {
    VStack(alignment: .leading, spacing: Spacing.sm) {
        Text("ds_heading1 — The quick brown fox").font(.ds_heading1)
        Text("ds_bodyMedium — The quick brown fox").font(.ds_bodyMedium)
        Text("ds_labelSmall — THE QUICK BROWN FOX").font(.ds_labelSmall)
    }
    .padding(Spacing.md)
}

#Preview("Typography — accessibility3 Dynamic Type") {
    VStack(alignment: .leading, spacing: Spacing.sm) {
        Text("ds_heading1 — The quick brown fox").font(.ds_heading1)
        Text("ds_bodyMedium — The quick brown fox").font(.ds_bodyMedium)
        Text("ds_labelSmall — THE QUICK BROWN FOX").font(.ds_labelSmall)
    }
    .padding(Spacing.md)
    .environment(\.dynamicTypeSize, .accessibility3)
}
#endif

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

    /// Returns a spacing value scaled for the current device tier
    static func adaptive(_ base: CGFloat) -> CGFloat {
        base * DeviceTier.current.spacingScale
    }

    /// Returns ideal column count for a grid given item min width and available width
    static func adaptiveColumns(minWidth: CGFloat = 160, availableWidth: CGFloat? = nil) -> Int {
        let width = availableWidth ?? OrientationManager.shared.screenWidth
        let padded = width - (Spacing.md * 2)
        return max(1, Int(padded / minWidth))
    }
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

    /// Logo blue accent — matches the vertical blue gradient on the "33" in
    /// the Fit33 wordmark. Use this when UI on a page needs to visually pair
    /// with the logo itself (e.g. the Welcome onboarding page CTA + border).
    static let ds_logoBlueAccent = LinearGradient(
        colors: [
            Color(red: 0.20, green: 0.55, blue: 0.95),
            Color(red: 0.55, green: 0.80, blue: 0.98)
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    /// Phase-shifted logo blue gradient. Same color palette as
    /// `ds_logoBlueAccent` but rotates the gradient angle as `phase` advances
    /// from 0...1 (full 360° sweep). Used by the onboarding tutorial's
    /// navigation chrome (page indicator + Continue / Get Started buttons)
    /// so as the user swipes step-by-step the gradient appears to "move".
    /// At `phase = 0` the gradient is vertical (top→bottom) and matches the
    /// static `ds_logoBlueAccent` exactly, so the welcome page's CTA looks
    /// identical to the page-0 hero gradient.
    static func ds_logoBlueAccent(phase: Double) -> LinearGradient {
        // 0 phase = .top→.bottom (90° on the unit circle).
        // Sweep a full revolution across phase 0...1.
        let angle = .pi / 2 + phase * 2 * .pi
        let dx = 0.5 * cos(angle)
        let dy = 0.5 * sin(angle)
        return LinearGradient(
            colors: [
                Color(red: 0.20, green: 0.55, blue: 0.95),
                Color(red: 0.55, green: 0.80, blue: 0.98)
            ],
            startPoint: UnitPoint(x: 0.5 - dx, y: 0.5 - dy),
            endPoint:   UnitPoint(x: 0.5 + dx, y: 0.5 + dy)
        )
    }
}

// MARK: - Reusable Section Header

/// Standard section header used across Dashboard, Meals, Friends, etc.
struct SectionHeader: View {
    let title: String
    var icon: String? = nil
    var iconColor: Color = .blue
    var secondaryIconColor: Color? = nil
    var action: (() -> Void)? = nil
    var actionLabel: String = "See All"
    
    var body: some View {
        HStack(spacing: 10) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [iconColor, secondaryIconColor ?? iconColor.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            Text(title)
                .font(.title3)
                .fontWeight(.bold)
            
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
                        .font(.ds_bodyMedium)
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

/// Sprint 5 M-24 name alias. New call sites should prefer `EmptyStateView`
/// since the prefix-less name reads better inside screens. Existing
/// `DSEmptyState` references continue to work.
typealias EmptyStateView = DSEmptyState

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

// MARK: - Haptic Tokens (Sprint 5 M-23)
//
// Semantic haptic vocabulary so call sites read like product intent
// (`HapticStyle.select.fire()`) rather than hardware primitives
// (`UIImpactFeedbackGenerator(style: .light).impactOccurred()`). Forwards to
// the pre-warmed generators in `HapticManager` to keep latency at zero.
//
// Why not just call `HapticManager` directly? Designers think in
// **categories** (selection, confirm, warning, success) while UIKit exposes
// **physical intensities** (light/medium/heavy impact, success/warning/error
// notification). Giving product code the category vocabulary makes it
// obvious when a new screen uses the wrong tone — e.g. `.warning` for a
// confirmation is clearly wrong, `.heavy` is just an opinion.

enum HapticStyle {
    /// Subtle light tap — toggling a filter chip, tab switch, quick select.
    case select
    /// Medium impact — committing an intentional user action (save, start).
    case confirm
    /// Heavy tap — a deliberate "this changes state" moment (delete button
    /// pressed, not the confirm itself).
    case impactHeavy
    /// `UINotificationFeedbackGenerator.success` — async work finished OK.
    case success
    /// `UINotificationFeedbackGenerator.warning` — caution (e.g. invalid
    /// input but not fatal).
    case warning
    /// `UINotificationFeedbackGenerator.error` — destructive path, hard fail.
    case error

    /// Trigger the haptic immediately. Safe to call from any thread (the
    /// underlying `HapticManager` is main-actor friendly via UIKit).
    @inline(__always)
    func fire() {
        switch self {
        case .select:      HapticManager.selectionChanged()
        case .confirm:     HapticManager.tap()
        case .impactHeavy: HapticManager.heavyTap()
        case .success:     HapticManager.success()
        case .warning:     HapticManager.warning()
        case .error:       HapticManager.error()
        }
    }
}

// MARK: - Liquid Glass Helpers (iOS 26+)

extension View {
    /// On iOS 26+ lets the system Liquid Glass show through on toolbars.
    /// On older versions falls back to the hidden/transparent toolbar style.
    @ViewBuilder
    func adaptiveToolbarBackground(for bars: ToolbarPlacement = .navigationBar) -> some View {
        if #available(iOS 26, *) {
            self
        } else {
            self
                .toolbarBackground(.hidden, for: bars)
                .toolbarColorScheme(.dark, for: bars)
        }
    }
    
    /// Applies a translucent glass background for pinned headers.
    /// iOS 26+: Liquid Glass with lensing/refraction.
    /// Pre-iOS 26: Ultra-thin material blur.
    @ViewBuilder
    func glassHeaderBackground() -> some View {
        if #available(iOS 26, *) {
            self
                .glassEffect(.regular, in: .rect)
        } else {
            self
                .background(.ultraThinMaterial)
        }
    }
    
    /// Tab title on the system top bar without its own Liquid Glass pill (iOS 26+).
    func floatingTopBarLeading<L: View>(@ViewBuilder content: @escaping () -> L) -> some View {
        modifier(FloatingTopBarLeadingToolbar(leading: content))
    }
    
    /// Trailing control (e.g. workout timer) without a separate pill (iOS 26+).
    func floatingTopBarTrailing<T: View>(@ViewBuilder content: @escaping () -> T) -> some View {
        modifier(FloatingTopBarTrailingToolbar(trailing: content))
    }
    
    /// Compact monospaced timer when a workout is active; no toolbar item when inactive.
    func floatingTopBarActiveWorkoutTimer() -> some View {
        modifier(ActiveWorkoutTimerFloatingToolbarModifier())
    }
}

// MARK: - Floating top bar toolbars (Liquid Glass–friendly)

private struct FloatingTopBarLeadingToolbar<L: View>: ViewModifier {
    @ViewBuilder var leading: () -> L
    
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        leading()
                    }
                    .sharedBackgroundVisibility(.hidden)
                }
        } else {
            content
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        leading()
                    }
                }
        }
    }
}

private struct FloatingTopBarTrailingToolbar<T: View>: ViewModifier {
    @ViewBuilder var trailing: () -> T
    
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        trailing()
                    }
                    .sharedBackgroundVisibility(.hidden)
                }
        } else {
            content
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        trailing()
                    }
                }
        }
    }
}

private struct ActiveWorkoutTimerFloatingToolbarModifier: ViewModifier {
    @EnvironmentObject private var workoutManager: WorkoutManager
    
    func body(content: Content) -> some View {
        if workoutManager.isWorkoutActive {
            content
                .floatingTopBarTrailing {
                    Text(workoutManager.formattedDuration)
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                }
        } else {
            content
        }
    }
}

