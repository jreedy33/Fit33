import SwiftUI

// MARK: - Subtle Indent Button Style
/// Adds a subtle press effect to indicate buttons are tappable
/// Used for set number/type indicators (1, 2, 3, W, A, F) in ActiveWorkoutView
struct SubtleIndentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}
