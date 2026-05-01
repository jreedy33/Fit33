import SwiftUI

// MARK: - Tab pinned chrome — vertical tightening under status bar

/// Applied to the outer `VStack { pinned header ; ScrollView }` on the main
/// tabs so the whole surface (not just the logo) shifts slightly toward the
/// status bar — removes the awkward gap between the clock and the first row.
enum TabPinnedChrome {
    static let rootTopPullUp: CGFloat = -12
}

// MARK: - Shared pinned tab header chrome (fully transparent)
//
// Wraps tab-specific header content with consistent horizontal inset + a small
// gap above the ScrollView. Intentionally NO divider and NO background —
// the caller must paint `AnimatedOrbBackground` behind the entire tab root
// `ZStack` so the pinned strip stays 100% see-through to the orb gradient.
//
// Layout (top → bottom):
//   [ status bar ]
//   [ tab-specific header content ]   ← `content` slot
//   [ ScrollView ]                     ← caller renders below this wrapper
struct PinnedTabHeader<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(.horizontal, Spacing.md)
            .padding(.bottom, Spacing.xs)
    }
}
