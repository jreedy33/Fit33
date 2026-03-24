import SwiftUI
import Combine

// MARK: - Scroll To Top Environment Key
struct ScrollToTopTriggerKey: EnvironmentKey {
    static let defaultValue: UUID = UUID()
}

extension EnvironmentValues {
    var scrollToTopTrigger: UUID {
        get { self[ScrollToTopTriggerKey.self] }
        set { self[ScrollToTopTriggerKey.self] = newValue }
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let goButtonVisibilityChanged = Notification.Name("goButtonVisibilityChanged")
    static let scrollToWidget = Notification.Name("scrollToWidget")
}

struct TabItem {
    let icon: String
    let selectedIcon: String
    let title: String
    let color: Color
}
