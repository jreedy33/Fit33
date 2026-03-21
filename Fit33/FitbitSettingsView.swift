//
//  FitbitSettingsView.swift
//  Fit33
//
//  Fitbit connection settings and activity sync management
//

import SwiftUI
import AuthenticationServices

// MARK: - Fitbit Settings View

struct FitbitSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var fitbit = FitbitService.shared
    @State private var isAuthenticating = false
    @State private var errorMessage: String?
    @State private var showDisconnectAlert = false
    @State private var webAuthSession: ASWebAuthenticationSession?
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                (colorScheme == .dark ? Color.black : Color(white: 0.95))
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Fitbit Logo/Header
                        fitbitHeader
                        
                        if fitbit.isConnected {
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
            .navigationTitle("Fitbit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Disconnect Fitbit?", isPresented: $showDisconnectAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Disconnect", role: .destructive) {
                    fitbit.disconnect()
                }
            } message: {
                Text("Your Fitbit activities will no longer sync with Fit33. You can reconnect anytime.")
            }
            .onChange(of: fitbit.isConnected) { _, isConnected in
                if isConnected {
                    dismiss()
                }
            }
            .onOpenURL { url in
                Task { await handleCallback(url) }
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("FitbitCallback"))) { notification in
                if let url = notification.object as? URL {
                    Task { await handleCallback(url) }
                }
            }
        }
    }
    
    // MARK: - Header
    
    private var fitbitHeader: some View {
        VStack(spacing: 16) {
            // Fitbit Logo
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0, green: 0.73, blue: 0.77), Color(red: 0, green: 0.55, blue: 0.58)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)
                    .shadow(color: Color(red: 0, green: 0.73, blue: 0.77).opacity(0.4), radius: 10, x: 0, y: 5)
                
                // Fitbit-style icon
                Image(systemName: "heart.circle.fill")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundColor(.white)
            }
            
            Text("Fitbit")
                .font(.title2)
                .fontWeight(.bold)
            
            Text(fitbit.isConnected ? "Connected" : "Connect your Fitbit account")
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
            
            // User Profile Card
            if let user = fitbit.userProfile {
                profileCard(user: user)
            }
            
            // Today's Activity Summary
            if let summary = fitbit.todaySummary {
                todayActivityCard(summary: summary)
            }
            
            // Additional Stats (Distance, Floors, Resting HR)
            if let summary = fitbit.todaySummary {
                additionalStatsCard(summary: summary)
            }
            
            // Sleep Data
            if !fitbit.sleepData.isEmpty {
                sleepDataCard
            }
            
            // Recent Workouts/Activities
            if !fitbit.recentActivities.isEmpty {
                recentActivitiesSection
            }
            
            // Action Buttons
            VStack(spacing: 12) {
                syncButton
                disconnectButton
            }
            .padding(.top, 8)
        }
    }
    
    // MARK: - Sync Status Header
    
    private var syncStatusHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.ds_bodyRegular)
                        .foregroundColor(.green)
                    Text("Connected")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.green)
                }
                
                if let lastSync = fitbit.lastSyncDate {
                    Text("Last synced \(lastSync.formatted(.relative(presentation: .named)))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("Syncing...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Quick sync button (force: true bypasses throttle)
            Button(action: {
                Task { await fitbit.syncAllData(force: true) }
            }) {
                if fitbit.isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: Color(red: 0, green: 0.73, blue: 0.77)))
                } else {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.ds_labelLarge)
                        .foregroundColor(Color(red: 0, green: 0.73, blue: 0.77))
                }
            }
            .frame(width: 40, height: 40)
            .background(Color(red: 0, green: 0.73, blue: 0.77).opacity(0.15))
            .cornerRadius(10)
            .disabled(fitbit.isLoading)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.lg)
                .fill(colorScheme == .dark ? Color.cardBackground : Color.white)
        )
    }
    
    // MARK: - Profile Card
    
    private func profileCard(user: FitbitUser) -> some View {
        HStack(spacing: 16) {
            // Avatar
            AsyncImage(url: URL(string: user.avatar150 ?? user.avatar ?? "")) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                ZStack {
                    Circle()
                        .fill(Color(red: 0, green: 0.73, blue: 0.77).opacity(0.2))
                    Image(systemName: "person.fill")
                        .font(.ds_heading2)
                        .foregroundColor(Color(red: 0, green: 0.73, blue: 0.77))
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(Circle())
            
            VStack(alignment: .leading, spacing: 4) {
                Text(user.fullName)
                    .font(.headline)
                    .fontWeight(.semibold)
                
                if let avgSteps = user.averageDailySteps {
                    Text("Avg. \(formatNumber(avgSteps)) steps/day")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else if let since = user.memberSince {
                    Text("Member since \(since)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundColor(.green)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.lg)
                .fill(colorScheme == .dark ? Color.cardBackground : Color.white)
        )
    }
    
    // MARK: - Today's Activity Card
    
    private func todayActivityCard(summary: FitbitDailySummary) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Today's Activity")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Text(Date().formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Main stats row
            HStack(spacing: 0) {
                statItem(
                    icon: "figure.walk",
                    value: formatNumber(summary.steps),
                    label: "Steps",
                    color: .blue,
                    goal: 10000,
                    current: summary.steps
                )
                
                Divider()
                    .frame(height: 60)
                
                statItem(
                    icon: "flame.fill",
                    value: formatNumber(summary.caloriesOut),
                    label: "Calories",
                    color: .orange,
                    goal: nil,
                    current: nil
                )
                
                Divider()
                    .frame(height: 60)
                
                statItem(
                    icon: "bolt.fill",
                    value: "\(fitbit.todayActiveMinutes)",
                    label: "Active Min",
                    color: .green,
                    goal: 30,
                    current: fitbit.todayActiveMinutes
                )
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.lg)
                .fill(colorScheme == .dark ? Color.cardBackground : Color.white)
        )
    }
    
    // MARK: - Additional Stats Card
    
    private func additionalStatsCard(summary: FitbitDailySummary) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("More Stats")
                .font(.headline)
                .fontWeight(.semibold)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 16) {
                // Distance
                if let distances = summary.distances,
                   let total = distances.first(where: { $0.activity == "total" })?.distance {
                    miniStatItem(
                        icon: "figure.run",
                        value: String(format: "%.1f km", total),
                        label: "Distance",
                        color: .purple
                    )
                }
                
                // Floors
                if let floors = summary.floors, floors > 0 {
                    miniStatItem(
                        icon: "stairs",
                        value: "\(floors)",
                        label: "Floors",
                        color: .cyan
                    )
                }
                
                // Resting HR
                if let restingHR = summary.restingHeartRate {
                    miniStatItem(
                        icon: "heart.fill",
                        value: "\(restingHR) bpm",
                        label: "Resting HR",
                        color: .red
                    )
                }
                
                // Sedentary Minutes
                if let sedentary = summary.sedentaryMinutes {
                    let hours = sedentary / 60
                    miniStatItem(
                        icon: "figure.stand",
                        value: "\(hours)h",
                        label: "Sedentary",
                        color: .gray
                    )
                }
                
                // Lightly Active
                if let light = summary.lightlyActiveMinutes, light > 0 {
                    miniStatItem(
                        icon: "figure.walk.motion",
                        value: "\(light) min",
                        label: "Light Activity",
                        color: .mint
                    )
                }
                
                // Very Active
                if let very = summary.veryActiveMinutes, very > 0 {
                    miniStatItem(
                        icon: "figure.highintensity.intervaltraining",
                        value: "\(very) min",
                        label: "High Intensity",
                        color: .orange
                    )
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.lg)
                .fill(colorScheme == .dark ? Color.cardBackground : Color.white)
        )
    }
    
    private func miniStatItem(icon: String, value: String, label: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.ds_labelLarge)
                .foregroundColor(color)
            
            Text(value)
                .font(.subheadline)
                .fontWeight(.bold)
            
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.xs)
    }
    
    // MARK: - Sleep Data Card
    
    private var sleepDataCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "bed.double.fill")
                    .foregroundColor(.indigo)
                Text("Recent Sleep")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Text("Avg: \(String(format: "%.1fh", fitbit.averageSleepHours))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            ForEach(fitbit.sleepData.prefix(3)) { sleep in
                sleepRow(sleep)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.lg)
                .fill(colorScheme == .dark ? Color.cardBackground : Color.white)
        )
    }
    
    private func sleepRow(_ sleep: FitbitSleepLog) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.indigo.opacity(0.15))
                    .frame(width: 40, height: 40)
                
                Image(systemName: "moon.zzz.fill")
                    .font(.ds_bodyRegular)
                    .foregroundColor(.indigo)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(sleep.dateOfSleep)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                HStack(spacing: 8) {
                    Text(String(format: "%.1f hrs", sleep.sleepHours))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if let efficiency = sleep.efficiency {
                        Text("•")
                            .foregroundColor(.secondary)
                        Text("\(efficiency)% efficiency")
                            .font(.caption)
                            .foregroundColor(efficiency >= 85 ? .green : .orange)
                    }
                }
            }
            
            Spacer()
            
            // Sleep quality indicator
            sleepQualityBadge(hours: sleep.sleepHours)
        }
        .padding(.vertical, Spacing.xxs)
    }
    
    private func sleepQualityBadge(hours: Double) -> some View {
        let (label, color) = getSleepQuality(hours: hours)
        return Text(label)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, Spacing.xs)
            .padding(.vertical, Spacing.xxs)
            .background(color.opacity(0.15))
            .foregroundColor(color)
            .cornerRadius(6)
    }
    
    private func getSleepQuality(hours: Double) -> (String, Color) {
        if hours >= 7.5 { return ("Good", .green) }
        if hours >= 6 { return ("Fair", .yellow) }
        return ("Low", .red)
    }
    
    // MARK: - Recent Activities
    
    private var recentActivitiesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "figure.mixed.cardio")
                    .foregroundColor(Color(red: 0, green: 0.73, blue: 0.77))
                Text("Recent Workouts")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Text("\(fitbit.recentActivities.count) synced")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            ForEach(fitbit.recentActivities.prefix(5)) { activity in
                activityRow(activity)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.lg)
                .fill(colorScheme == .dark ? Color.cardBackground : Color.white)
        )
    }
    
    private func activityRow(_ activity: FitbitActivity) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color(red: 0, green: 0.73, blue: 0.77).opacity(0.15))
                    .frame(width: 40, height: 40)
                
                Image(systemName: activity.activityIcon)
                    .font(.ds_labelLarge)
                    .foregroundColor(Color(red: 0, green: 0.73, blue: 0.77))
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(activity.activityName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                HStack(spacing: 8) {
                    Text("\(activity.durationMinutes) min")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("•")
                        .foregroundColor(.secondary)
                    Text("\(activity.calories) cal")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if let distance = activity.distance, distance > 0 {
                        Text("•")
                            .foregroundColor(.secondary)
                        Text(String(format: "%.1f km", distance / 1000))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
            
            Image(systemName: "checkmark.circle.fill")
                .font(.subheadline)
                .foregroundColor(.green)
        }
        .padding(.vertical, 6)
    }
    
    // MARK: - Stat Item with Progress
    
    private func statItem(icon: String, value: String, label: String, color: Color, goal: Int?, current: Int?) -> some View {
        VStack(spacing: 8) {
            ZStack {
                // Progress ring if goal exists
                if let goal = goal, let current = current {
                    Circle()
                        .stroke(color.opacity(0.2), lineWidth: 4)
                        .frame(width: 48, height: 48)
                    
                    Circle()
                        .trim(from: 0, to: min(CGFloat(current) / CGFloat(goal), 1.0))
                        .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .frame(width: 48, height: 48)
                        .rotationEffect(.degrees(-90))
                } else {
                    Circle()
                        .fill(color.opacity(0.15))
                        .frame(width: 48, height: 48)
                }
                
                Image(systemName: icon)
                    .font(.ds_heading3)
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
    
    // MARK: - Action Buttons
    
    private var syncButton: some View {
        Button(action: {
            Task {
                await fitbit.syncAllData(force: true) // Force sync bypasses throttle
            }
        }) {
            HStack(spacing: 10) {
                if fitbit.isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.ds_labelLarge)
                }
                Text(fitbit.isLoading ? "Syncing..." : "Sync Now")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                LinearGradient(
                    colors: [Color(red: 0, green: 0.73, blue: 0.77), Color(red: 0, green: 0.55, blue: 0.58)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .foregroundColor(.white)
            .cornerRadius(CornerRadius.md)
        }
        .disabled(fitbit.isLoading)
    }
    
    private var disconnectButton: some View {
        Button(action: { showDisconnectAlert = true }) {
            HStack(spacing: 8) {
                Image(systemName: "xmark.circle.fill")
                Text("Disconnect Fitbit")
                    .fontWeight(.medium)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.red.opacity(0.1))
            .foregroundColor(.red)
            .cornerRadius(CornerRadius.md)
        }
    }
    
    // MARK: - Not Connected Content
    
    private var notConnectedContent: some View {
        VStack(spacing: 24) {
            // Benefits
            benefitsCard
            
            // Data synced
            dataSyncedCard
            
            // Connect Button
            connectButton
            
            // Error message
            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
            }
        }
    }
    
    private var benefitsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Why connect Fitbit?")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(alignment: .leading, spacing: 12) {
                benefitRow(icon: "figure.run", text: "Sync all your workouts automatically")
                benefitRow(icon: "heart.fill", text: "Track heart rate during exercise")
                benefitRow(icon: "bed.double.fill", text: "Monitor sleep quality")
                benefitRow(icon: "flame.fill", text: "Calories count towards your goals")
                benefitRow(icon: "figure.walk", text: "Steps sync with daily activity")
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.lg)
                .fill(colorScheme == .dark ? Color.cardBackground : Color.white)
        )
    }
    
    private func benefitRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(Color(red: 0, green: 0.73, blue: 0.77))
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
        }
    }
    
    private var dataSyncedCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Data that syncs:")
                .font(.subheadline)
                .fontWeight(.medium)
            
            HStack(spacing: 8) {
                dataTag("Workouts")
                dataTag("Steps")
                dataTag("Sleep")
            }
            
            HStack(spacing: 8) {
                dataTag("Heart Rate")
                dataTag("Calories")
                dataTag("Weight")
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.lg)
                .fill(colorScheme == .dark ? Color.cardBackground : Color.white)
        )
    }
    
    private func dataTag(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(red: 0, green: 0.73, blue: 0.77).opacity(0.15))
            .foregroundColor(Color(red: 0, green: 0.73, blue: 0.77))
            .cornerRadius(CornerRadius.sm)
    }
    
    private var connectButton: some View {
        Button(action: startAuth) {
            HStack {
                if isAuthenticating {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    Image(systemName: "link")
                }
                Text(isAuthenticating ? "Connecting..." : "Connect Fitbit")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(
                LinearGradient(
                    colors: [Color(red: 0, green: 0.73, blue: 0.77), Color(red: 0, green: 0.55, blue: 0.58)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .foregroundColor(.white)
            .cornerRadius(CornerRadius.md)
        }
        .disabled(isAuthenticating)
    }
    
    // MARK: - Actions
    
    private func startAuth() {
        guard let authURL = fitbit.getAuthorizationURL() else {
            errorMessage = "Could not create authorization URL"
            return
        }
        
        isAuthenticating = true
        errorMessage = nil
        
        // Use ASWebAuthenticationSession for in-app browser
        webAuthSession = ASWebAuthenticationSession(
            url: authURL,
            callbackURLScheme: "fit33"
        ) { callbackURL, error in
            Task { @MainActor in
                if let error = error {
                    // User cancelled or error occurred
                    if (error as NSError).code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                        AppLogger.debug("🔐 [FITBIT] User cancelled login", category: .health)
                    } else {
                        errorMessage = error.localizedDescription
                    }
                    isAuthenticating = false
                    return
                }
                
                guard let callbackURL = callbackURL else {
                    errorMessage = "No callback URL received"
                    isAuthenticating = false
                    return
                }
                
                // Handle the callback
                await handleCallback(callbackURL)
            }
        }
        
        // Configure the session
        webAuthSession?.presentationContextProvider = WebAuthContextProvider.shared
        webAuthSession?.prefersEphemeralWebBrowserSession = false
        
        // Start the session
        webAuthSession?.start()
    }
    
    private func handleCallback(_ url: URL) async {
        do {
            try await fitbit.handleCallback(url: url)
            await MainActor.run {
                isAuthenticating = false
                dismiss()
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isAuthenticating = false
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

// MARK: - Compact Fitbit Card (for Settings)

struct FitbitCompactCard: View {
    @StateObject private var fitbit = FitbitService.shared
    @State private var showFitbitSettings = false
    
    var body: some View {
        Button(action: { showFitbitSettings = true }) {
            HStack(spacing: 12) {
                // Fitbit Icon
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0, green: 0.73, blue: 0.77), Color(red: 0, green: 0.55, blue: 0.58)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: "heart.circle.fill")
                        .font(.ds_heading3).fontWeight(.semibold)
                        .foregroundColor(.white)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Fitbit")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    if fitbit.isConnected {
                        if let steps = fitbit.todaySummary?.steps {
                            Text("\(formatNumber(steps)) steps today")
                                .font(.caption)
                                .foregroundColor(.green)
                        } else {
                            Text("Connected")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                    } else {
                        Text("Not connected")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                if fitbit.isConnected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.md)
                    .fill(Color(UIColor.secondarySystemBackground))
            )
        }
        .buttonStyle(PlainButtonStyle())
        .sheet(isPresented: $showFitbitSettings) {
            FitbitSettingsView()
        }
    }
    
    private func formatNumber(_ number: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: number)) ?? "\(number)"
    }
}

// MARK: - Preview

#Preview {
    FitbitSettingsView()
}

