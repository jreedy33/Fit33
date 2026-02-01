//
//  HealthKitSettingsView.swift
//  Fit33
//
//  Apple Health connection settings - syncs workouts from Nike Run Club,
//  Apple Watch, Strava, Fitbit, and any other HealthKit-connected apps
//

import SwiftUI
import HealthKit

// MARK: - HealthKit Settings View

struct HealthKitSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var healthKit = HealthKitService.shared
    @State private var showDisconnectAlert = false
    @State private var isConnecting = false
    @State private var errorMessage: String?
    
    // Teal color for Apple Health branding
    private let healthColor = Color(red: 1.0, green: 0.23, blue: 0.19) // Apple Health red
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background
                (colorScheme == .dark ? Color.black : Color(white: 0.95))
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Header
                        healthKitHeader
                        
                        if healthKit.isAuthorized {
                            // Connected State
                            connectedContent
                        } else {
                            // Not Connected State
                            notConnectedContent
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Apple Health")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Disconnect Apple Health?", isPresented: $showDisconnectAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Disconnect", role: .destructive) {
                    healthKit.disconnect()
                }
            } message: {
                Text("Your workouts from Nike Run Club, Apple Watch, and other apps will no longer sync. You can reconnect anytime.")
            }
        }
    }
    
    // MARK: - Header
    
    private var healthKitHeader: some View {
        VStack(spacing: 16) {
            // Apple Health Icon
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.red, Color.pink],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)
                
                Image(systemName: "heart.fill")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundColor(.white)
            }
            
            Text("Apple Health")
                .font(.title2)
                .fontWeight(.bold)
            
            Text(healthKit.isAuthorized ? "Connected" : "Connect to sync your workouts")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 20)
    }
    
    // MARK: - Connected Content
    
    private var connectedContent: some View {
        VStack(spacing: 16) {
            // Sync Status Header
            syncStatusHeader
            
            // Today's Summary
            todaySummaryCard
            
            // Connected Apps Info
            connectedAppsCard
            
            // Recent Workouts
            if !healthKit.recentWorkouts.isEmpty {
                recentWorkoutsSection
            }
            
            // Action Buttons
            VStack(spacing: 12) {
                syncButton
                disconnectButton
            }
            .padding(.top, 8)
        }
    }
    
    private var syncStatusHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.green)
                    Text("Connected")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.green)
                }
                
                if let lastSync = healthKit.lastSyncDate {
                    Text("Last synced \(lastSync.formatted(.relative(presentation: .named)))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Quick sync button
            Button(action: {
                Task { await healthKit.syncAllData(force: true) }
            }) {
                if healthKit.isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .red))
                } else {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.red)
                }
            }
            .frame(width: 40, height: 40)
            .background(Color.red.opacity(0.15))
            .cornerRadius(10)
            .disabled(healthKit.isLoading)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(colorScheme == .dark ? Color(white: 0.12) : Color.white)
        )
    }
    
    private var todaySummaryCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Today's Summary")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Text(Date().formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            HStack(spacing: 0) {
                statItem(
                    icon: "figure.walk",
                    value: formatNumber(healthKit.todaySteps),
                    label: "Steps",
                    color: .blue
                )
                
                Divider().frame(height: 60)
                
                statItem(
                    icon: "flame.fill",
                    value: formatNumber(healthKit.todayCalories),
                    label: "Calories",
                    color: .orange
                )
                
                Divider().frame(height: 60)
                
                statItem(
                    icon: "figure.run",
                    value: String(format: "%.1f km", healthKit.todayDistance / 1000),
                    label: "Distance",
                    color: .green
                )
            }
            
            // Additional stats
            if healthKit.restingHeartRate != nil || healthKit.lastNightSleep != nil {
                Divider()
                
                HStack(spacing: 20) {
                    if let rhr = healthKit.restingHeartRate {
                        HStack(spacing: 6) {
                            Image(systemName: "heart.fill")
                                .foregroundColor(.red)
                                .font(.caption)
                            Text("\(rhr) bpm")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("resting")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    if let sleep = healthKit.lastNightSleep {
                        HStack(spacing: 6) {
                            Image(systemName: "bed.double.fill")
                                .foregroundColor(.indigo)
                                .font(.caption)
                            Text(String(format: "%.1fh", sleep))
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("sleep")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(colorScheme == .dark ? Color(white: 0.12) : Color.white)
        )
    }
    
    private func statItem(icon: String, value: String, label: String, color: Color) -> some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 44, height: 44)
                
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(color)
            }
            
            Text(value)
                .font(.headline)
                .fontWeight(.bold)
            
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
    
    private var connectedAppsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Data Sources")
                .font(.headline)
                .fontWeight(.semibold)
            
            Text("Workouts from these apps automatically sync:")
                .font(.caption)
                .foregroundColor(.secondary)
            
            HStack(spacing: 12) {
                appBadge(name: "Nike Run Club", icon: "figure.run", color: .black)
                appBadge(name: "Apple Watch", icon: "applewatch", color: .gray)
                appBadge(name: "Other Apps", icon: "app.badge", color: .blue)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(colorScheme == .dark ? Color(white: 0.12) : Color.white)
        )
    }
    
    private func appBadge(name: String, icon: String, color: Color) -> some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(color.opacity(0.15))
                    .frame(width: 44, height: 44)
                
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundColor(color)
            }
            
            Text(name)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
    
    private var recentWorkoutsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "figure.mixed.cardio")
                    .foregroundColor(.red)
                Text("Recent Workouts")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Text("\(healthKit.recentWorkouts.count) synced")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            ForEach(healthKit.recentWorkouts.prefix(5)) { workout in
                workoutRow(workout)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(colorScheme == .dark ? Color(white: 0.12) : Color.white)
        )
    }
    
    private func workoutRow(_ workout: HealthKitWorkout) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(workoutColor(for: workout).opacity(0.15))
                    .frame(width: 40, height: 40)
                
                Image(systemName: workout.workoutIcon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(workoutColor(for: workout))
            }
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(workout.workoutName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    // Source badge
                    if workout.isFromNikeRunClub {
                        sourceBadge("Nike", color: .black)
                    } else if workout.isFromStrava {
                        sourceBadge("Strava", color: .orange)
                    } else if workout.isFromApple {
                        sourceBadge("Watch", color: .gray)
                    }
                }
                
                HStack(spacing: 8) {
                    Text("\(workout.durationMinutes) min")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if let calories = workout.calories, calories > 0 {
                        Text("•")
                            .foregroundColor(.secondary)
                        Text("\(Int(calories)) cal")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    if let distance = workout.distance, distance > 0 {
                        Text("•")
                            .foregroundColor(.secondary)
                        Text(String(format: "%.1f km", distance / 1000))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
            
            Text(workout.startDate.formatted(date: .abbreviated, time: .omitted))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 6)
    }
    
    private func sourceBadge(_ name: String, color: Color) -> some View {
        Text(name)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundColor(color)
            .cornerRadius(4)
    }
    
    private func workoutColor(for workout: HealthKitWorkout) -> Color {
        if workout.isFromNikeRunClub { return .black }
        if workout.isFromStrava { return .orange }
        
        switch workout.workoutType {
        case .running: return .green
        case .cycling: return .blue
        case .swimming: return .cyan
        case .walking: return .mint
        default: return .red
        }
    }
    
    private var syncButton: some View {
        Button(action: {
            Task { await healthKit.syncAllData(force: true) }
        }) {
            HStack(spacing: 10) {
                if healthKit.isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 16, weight: .semibold))
                }
                Text(healthKit.isLoading ? "Syncing..." : "Sync Now")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                LinearGradient(
                    colors: [Color.red, Color.pink],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .foregroundColor(.white)
            .cornerRadius(12)
        }
        .disabled(healthKit.isLoading)
    }
    
    private var disconnectButton: some View {
        Button(action: { showDisconnectAlert = true }) {
            HStack(spacing: 8) {
                Image(systemName: "xmark.circle.fill")
                Text("Disconnect Apple Health")
                    .fontWeight(.medium)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.red.opacity(0.1))
            .foregroundColor(.red)
            .cornerRadius(12)
        }
    }
    
    // MARK: - Not Connected Content
    
    private var notConnectedContent: some View {
        VStack(spacing: 24) {
            // Benefits
            benefitsCard
            
            // Connect Button
            connectButton
            
            // Privacy note
            Text("Your health data stays on your device. Fit33 only reads workout and activity data to show your progress.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
    }
    
    private var benefitsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("What you'll get:")
                .font(.subheadline)
                .fontWeight(.semibold)
            
            benefitRow(icon: "figure.run", text: "Nike Run Club runs sync automatically")
            benefitRow(icon: "applewatch", text: "Apple Watch workouts included")
            benefitRow(icon: "figure.walk", text: "Daily steps from your iPhone")
            benefitRow(icon: "heart.fill", text: "Heart rate and sleep data")
            benefitRow(icon: "chart.line.uptrend.xyaxis", text: "All activity in one place")
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(colorScheme == .dark ? Color(white: 0.12) : Color.white)
        )
    }
    
    private func benefitRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.red)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
        }
    }
    
    private var connectButton: some View {
        Button(action: connect) {
            HStack {
                if isConnecting {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    Image(systemName: "heart.fill")
                    Text("Connect Apple Health")
                        .fontWeight(.semibold)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                LinearGradient(
                    colors: [Color.red, Color.pink],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .foregroundColor(.white)
            .cornerRadius(12)
        }
        .disabled(isConnecting)
    }
    
    // MARK: - Actions
    
    private func connect() {
        guard healthKit.isHealthKitAvailable else {
            errorMessage = "HealthKit is not available on this device"
            return
        }
        
        isConnecting = true
        errorMessage = nil
        
        Task {
            do {
                try await healthKit.requestAuthorization()
                await MainActor.run {
                    isConnecting = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isConnecting = false
                }
            }
        }
    }
    
    // MARK: - Helpers
    
    private func formatNumber(_ number: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: number)) ?? "\(number)"
    }
}

// MARK: - Preview

#Preview {
    HealthKitSettingsView()
}
