import Foundation
import SwiftUI

/// Manages deep link navigation throughout the app
@MainActor
class DeepLinkManager: ObservableObject {
    static let shared = DeepLinkManager()
    
    enum Destination {
        case running
        case workout
        case dashboard
    }
    
    @Published var pendingDestination: Destination?
    
    private init() {}
    
    /// Consume and clear the pending destination
    func consumeDestination() -> Destination? {
        let destination = pendingDestination
        pendingDestination = nil
        return destination
    }
}

