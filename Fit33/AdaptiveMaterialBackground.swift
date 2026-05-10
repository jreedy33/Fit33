//
//  AdaptiveMaterialBackground.swift
//  Fit33
//
//  Canonical wrapper for `.ultraThinMaterial` backgrounds that honors the
//  user's "Reduce Transparency" accessibility setting.
//

import SwiftUI

/// Background that honors the user's "Reduce Transparency" accessibility setting.
/// When enabled, falls back to an opaque color instead of `.ultraThinMaterial`.
struct AdaptiveMaterialBackground: ViewModifier {
    let cornerRadius: CGFloat
    let fallback: Color

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content.background(
            Group {
                if reduceTransparency {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(fallback)
                } else {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                }
            }
        )
    }
}

extension View {
    /// Applies a `.ultraThinMaterial` background that automatically falls back to
    /// `Color.cardBackground` (or a custom opaque color) when the user has
    /// "Reduce Transparency" enabled in iOS Settings → Accessibility → Display & Text Size.
    ///
    /// New surfaces using `.ultraThinMaterial` MUST go through this wrapper instead of
    /// applying `.background(.ultraThinMaterial)` directly — raw `.ultraThinMaterial`
    /// ignores Reduce Transparency and produces unreadable UI for those users.
    func adaptiveMaterialBackground(
        cornerRadius: CGFloat = CornerRadius.lg,
        fallback: Color = Color.cardBackground
    ) -> some View {
        modifier(AdaptiveMaterialBackground(cornerRadius: cornerRadius, fallback: fallback))
    }
}
