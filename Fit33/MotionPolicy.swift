//
//  MotionPolicy.swift
//  Fit33
//
//  Canonical gate for decorative animations.
//

import SwiftUI
import UIKit

/// Canonical gate for decorative animations.
///
/// Decorative animations (pulsing glows, floating orbs, particle effects, streak
/// flames, confetti) MUST be suppressed when the user has Reduce Motion enabled
/// or is in Low Power Mode. Functional animations (state transitions, sheet
/// presentations, button feedback) are EXEMPT — keep those running so the UI
/// still feels responsive.
///
/// Two callable styles:
/// 1. `MotionPolicy.shouldDisableDecorative` — main-actor static accessor that
///    reads `UIAccessibility` directly. Use from non-SwiftUI contexts (managers,
///    services, `@MainActor` view models) where you don't have access to
///    `@Environment(\.accessibilityReduceMotion)`.
/// 2. `MotionPolicy.shouldDisableDecorative(reduceMotion:)` — pure function for
///    SwiftUI view code that already reads `@Environment(\.accessibilityReduceMotion)`.
///    Prefer this in views — the environment value participates in invalidation
///    so the view re-renders when the user toggles Reduce Motion in Settings.
enum MotionPolicy {
    @MainActor
    static var shouldDisableDecorative: Bool {
        UIAccessibility.isReduceMotionEnabled || ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    static func shouldDisableDecorative(reduceMotion: Bool) -> Bool {
        reduceMotion || ProcessInfo.processInfo.isLowPowerModeEnabled
    }
}
