import ActivityKit
import Foundation

/// Attributes for the Running Live Activity
/// This defines the data shown on the Lock Screen and Dynamic Island during a run
struct RunningActivityAttributes: ActivityAttributes {
    
    /// Static content that doesn't change during the activity
    public struct ContentState: Codable, Hashable {
        // Dynamic content that updates
        var elapsedTime: TimeInterval
        var distance: Double // in miles
        var currentPace: String // formatted pace string
        var averagePace: String
        var calories: Double
        var isPaused: Bool
    }
    
    // Static attributes (set when activity starts)
    var startTime: Date
    var activityName: String
}

