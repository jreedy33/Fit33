//
//  RunningActivityWidgetLiveActivity.swift
//  RunningActivityWidget
//
//  Created by Joseph Reed on 12/21/25.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct RunningActivityWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RunningActivityAttributes.self) { context in
            // Lock Screen / Banner view
            RunningLockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded Dynamic Island
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(formatTime(context.state.elapsedTime))
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        Text("TIME")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.cyan)
                    }
                }
                
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(String(format: "%.2f", context.state.distance))
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        Text("MI")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.green)
                    }
                }
                
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        Image(systemName: context.state.isPaused ? "pause.fill" : "figure.run")
                            .font(.system(size: 20))
                            .foregroundColor(context.state.isPaused ? .orange : .green)
                        Text(context.state.isPaused ? "PAUSED" : "RUNNING")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
                
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 24) {
                        VStack(spacing: 2) {
                            Text(context.state.averagePace)
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundColor(.white)
                            Text("AVG PACE")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.orange)
                        }
                        
                        VStack(spacing: 2) {
                            Text(context.state.currentPace)
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundColor(.white)
                            Text("CURRENT")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.white.opacity(0.6))
                        }
                        
                        VStack(spacing: 2) {
                            Text(String(format: "%.0f", context.state.calories))
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundColor(.white)
                            Text("CAL")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.red)
                        }
                    }
                }
            } compactLeading: {
                // Compact leading (left pill)
                HStack(spacing: 4) {
                    Image(systemName: "figure.run")
                        .foregroundColor(.green)
                    Text(formatTime(context.state.elapsedTime))
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                }
            } compactTrailing: {
                // Compact trailing (right pill)
                Text(String(format: "%.2f mi", context.state.distance))
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(.green)
            } minimal: {
                // Minimal view (when other activities are present)
                Image(systemName: "figure.run")
                    .foregroundColor(.green)
            }
            .widgetURL(URL(string: "fit33://running"))
        }
    }
    
    private func formatTime(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        let seconds = Int(interval) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
}

// MARK: - Lock Screen View
struct RunningLockScreenView: View {
    let context: ActivityViewContext<RunningActivityAttributes>
    
    var body: some View {
        HStack(spacing: 16) {
            // Running icon with status
            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: context.state.isPaused ? [.orange, .yellow] : [.green, .mint],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 50, height: 50)
                    
                    Image(systemName: context.state.isPaused ? "pause.fill" : "figure.run")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(.white)
                }
                
                Text(context.state.isPaused ? "PAUSED" : "ACTIVE")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(context.state.isPaused ? .orange : .green)
            }
            
            // Main stats
            VStack(alignment: .leading, spacing: 8) {
                // Time and distance row
                HStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(formatTime(context.state.elapsedTime))
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        Text("TIME")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.cyan)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(format: "%.2f", context.state.distance))
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        Text("MILES")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.green)
                    }
                }
                
                // Pace row
                HStack(spacing: 16) {
                    HStack(spacing: 4) {
                        Image(systemName: "speedometer")
                            .font(.system(size: 12))
                            .foregroundColor(.orange)
                        Text(context.state.averagePace)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                        Text("/mi")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    
                    HStack(spacing: 4) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.red)
                        Text(String(format: "%.0f cal", context.state.calories))
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                    }
                }
            }
            
            Spacer()
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.12, blue: 0.08),
                    Color(red: 0.02, green: 0.06, blue: 0.04)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }
    
    private func formatTime(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        let seconds = Int(interval) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
}

// MARK: - Preview
#Preview("Lock Screen", as: .content, using: RunningActivityAttributes(startTime: Date(), activityName: "Outdoor Run")) {
    RunningActivityWidgetLiveActivity()
} contentStates: {
    RunningActivityAttributes.ContentState(
        elapsedTime: 1847,
        distance: 3.24,
        currentPace: "8:32",
        averagePace: "8:45",
        calories: 312,
        isPaused: false
    )
}

