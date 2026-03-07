//
//  StravaSettingsView.swift
//  Fit33
//
//  UI for connecting and managing Strava integration
//

import SwiftUI
import AuthenticationServices

// MARK: - Strava Settings View

struct StravaSettingsView: View {
    @StateObject private var strava = StravaService.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var showingDisconnectAlert = false
    @State private var showingAuthSheet = false
    
    var body: some View {
        ZStack {
            // Animated orb background (consistent with Profile/Stats screens)
            AnimatedOrbBackground.stats(colorScheme: colorScheme)
                .ignoresSafeArea(.all, edges: .all)
            
            List {
                // Connection Status Section
                Section {
                    if strava.isConnected {
                        connectedView
                    } else {
                        disconnectedView
                    }
                } header: {
                    Label("Connection", systemImage: "link")
                }
            
            // Activities Section (only show if connected)
            if strava.isConnected {
                Section {
                    weeklyStatsView
                } header: {
                    Label("This Week", systemImage: "chart.bar.fill")
                }
                
                Section {
                    if strava.isLoading {
                        HStack {
                            ProgressView()
                            Text("Syncing activities...")
                                .foregroundColor(.secondary)
                        }
                    } else if strava.recentActivities.isEmpty {
                        Text("No recent activities")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(strava.recentActivities.prefix(10)) { activity in
                            activityRow(activity)
                        }
                    }
                } header: {
                    HStack {
                        Label("Recent Activities", systemImage: "figure.run")
                        Spacer()
                        if let lastSync = strava.lastSyncDate {
                            Text("Synced \(lastSync.timeAgoDisplay())")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                } footer: {
                    if !strava.recentActivities.isEmpty {
                        Text("Showing last 10 activities from the past 30 days")
                    }
                }
                
                Section {
                    Button(action: {
                        Task { await strava.syncActivities() }
                    }) {
                        HStack {
                            Image(systemName: "arrow.triangle.2.circlepath")
                            Text("Sync Now")
                        }
                    }
                    .disabled(strava.isLoading)
                }
            }
            
            // About Strava Integration
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("What syncs from Strava?")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        integrationBullet("Runs, rides, walks, hikes, swims")
                        integrationBullet("Distance and duration")
                        integrationBullet("Heart rate data")
                        integrationBullet("Calories burned")
                        integrationBullet("Elevation gain")
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Label("About", systemImage: "info.circle")
            }
        }
        .scrollContentBackground(.hidden)
        }
        .navigationTitle("Strava")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Disconnect Strava?", isPresented: $showingDisconnectAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Disconnect", role: .destructive) {
                strava.disconnect()
            }
        } message: {
            Text("Your synced activities will remain in Fit33, but new activities won't sync until you reconnect.")
        }
        .sheet(isPresented: $showingAuthSheet) {
            StravaAuthSheet()
        }
    }
    
    // MARK: - Connected View
    
    private var connectedView: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                // Profile Picture
                if let profileUrl = strava.athleteProfile?.profile,
                   let url = URL(string: profileUrl) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: 50, height: 50)
                                .clipShape(Circle())
                        default:
                            stravaPlaceholderAvatar
                        }
                    }
                } else {
                    stravaPlaceholderAvatar
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.system(size: 14))
                        Text("Connected")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.green)
                    }
                    
                    if let athlete = strava.athleteProfile {
                        Text(athlete.fullName)
                            .font(.headline)
                    }
                }
                
                Spacer()
                
                // Strava Logo
                Image("strava-logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 80)
                    .opacity(0.8)
            }
            
            Divider()
            
            Button(action: { showingDisconnectAlert = true }) {
                HStack {
                    Image(systemName: "xmark.circle")
                    Text("Disconnect")
                }
                .font(.subheadline)
                .foregroundColor(.red)
            }
        }
        .padding(.vertical, 4)
    }
    
    private var stravaPlaceholderAvatar: some View {
        Circle()
            .fill(Color.orange.opacity(0.2))
            .frame(width: 50, height: 50)
            .overlay(
                Image(systemName: "figure.run")
                    .foregroundColor(.orange)
            )
    }
    
    // MARK: - Disconnected View
    
    private var disconnectedView: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Connect Strava")
                        .font(.headline)
                    Text("Sync your cardio activities")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Strava colors: Orange #FC4C02
                Image(systemName: "link.badge.plus")
                    .font(.title2)
                    .foregroundColor(Color(red: 252/255, green: 76/255, blue: 2/255))
            }
            
            Button(action: { showingAuthSheet = true }) {
                HStack {
                    Image(systemName: "figure.run")
                    Text("Connect with Strava")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.sm)
                .background(
                    LinearGradient(
                        colors: [Color(red: 252/255, green: 76/255, blue: 2/255), Color(red: 252/255, green: 100/255, blue: 30/255)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .foregroundColor(.white)
                .cornerRadius(10)
            }
        }
        .padding(.vertical, 4)
    }
    
    // MARK: - Weekly Stats View
    
    private var weeklyStatsView: some View {
        HStack(spacing: 16) {
            statCard(
                icon: "clock.fill",
                value: "\(strava.weeklyCardioMinutes)",
                unit: "min",
                label: "Cardio"
            )
            
            statCard(
                icon: "figure.walk",
                value: String(format: "%.1f", strava.weeklyDistanceKm),
                unit: "km",
                label: "Distance"
            )
            
            statCard(
                icon: "flame.fill",
                value: "\(strava.weeklyCaloriesBurned)",
                unit: "cal",
                label: "Burned"
            )
        }
        .padding(.vertical, Spacing.xs)
    }
    
    private func statCard(icon: String, value: String, unit: String, label: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .foregroundColor(.orange)
                .font(.system(size: 16))
            
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.title3)
                    .fontWeight(.bold)
                Text(unit)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Activity Row
    
    private func activityRow(_ activity: StravaActivity) -> some View {
        HStack(spacing: 12) {
            Image(systemName: activity.activityIcon)
                .font(.system(size: 18))
                .foregroundColor(.orange)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(activity.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                
                HStack(spacing: 8) {
                    Text(activity.distanceFormatted)
                    Text("•")
                        .foregroundColor(.secondary)
                    Text(activity.durationFormatted)
                    if let pace = activity.paceFormatted {
                        Text("•")
                            .foregroundColor(.secondary)
                        Text(pace)
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text(activity.startDate, style: .date)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
    
    // MARK: - Helper Views
    
    private func integrationBullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark")
                .font(.caption)
                .foregroundColor(.green)
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Strava Auth Sheet

struct StravaAuthSheet: View {
    @StateObject private var strava = StravaService.shared
    @Environment(\.dismiss) private var dismiss
    @State private var isAuthenticating = false
    @State private var errorMessage: String?
    @State private var webAuthSession: ASWebAuthenticationSession?
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                
                // Strava Logo & Description
                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(Color(red: 252/255, green: 76/255, blue: 2/255).opacity(0.1))
                            .frame(width: 100, height: 100)
                        
                        Image(systemName: "figure.run")
                            .font(.system(size: 44))
                            .foregroundColor(Color(red: 252/255, green: 76/255, blue: 2/255))
                    }
                    
                    Text("Connect to Strava")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("Sync your runs, rides, and other cardio activities to get a complete picture of your fitness.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                
                // Permissions
                VStack(alignment: .leading, spacing: 12) {
                    Text("Fit33 will be able to:")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    
                    permissionRow(icon: "figure.run", text: "Read your activities")
                    permissionRow(icon: "heart.fill", text: "Access heart rate data")
                    permissionRow(icon: "flame.fill", text: "View calories burned")
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: CornerRadius.md).fill(Color(.systemGray6)))
                .padding(.horizontal)
                
                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.horizontal)
                }
                
                Spacer()
                
                // Connect Button
                Button(action: startAuth) {
                    HStack {
                        if isAuthenticating {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "link")
                            Text("Connect with Strava")
                                .fontWeight(.semibold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.md)
                    .background(
                        LinearGradient(
                            colors: [Color(red: 252/255, green: 76/255, blue: 2/255), Color(red: 252/255, green: 100/255, blue: 30/255)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .foregroundColor(.white)
                    .cornerRadius(CornerRadius.md)
                }
                .disabled(isAuthenticating)
                .padding(.horizontal)
                .padding(.bottom, 16)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onChange(of: strava.isConnected) { _, isConnected in
                if isConnected {
                    dismiss()
                }
            }
            .onOpenURL { url in
                Task { await handleCallback(url) }
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("StravaCallback"))) { notification in
                if let url = notification.object as? URL {
                    Task { await handleCallback(url) }
                }
            }
        }
    }
    
    private func permissionRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.orange)
                .frame(width: 20)
            Text(text)
                .font(.subheadline)
        }
    }
    
    private func startAuth() {
        guard let authURL = strava.getAuthorizationURL() else {
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
                        print("🔐 [STRAVA] User cancelled login")
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
            try await strava.handleCallback(url: url)
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
}

// MARK: - Compact Strava Card (for Dashboard)

struct StravaCompactCard: View {
    @StateObject private var strava = StravaService.shared
    
    var body: some View {
        if strava.isConnected && !strava.recentActivities.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "figure.run")
                        .foregroundColor(.orange)
                    Text("Strava Activity")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Spacer()
                    Text("\(strava.weeklyCardioMinutes) min this week")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if let latest = strava.recentActivities.first {
                    HStack {
                        Image(systemName: latest.activityIcon)
                            .foregroundColor(.orange)
                            .frame(width: 24)
                        
                        VStack(alignment: .leading) {
                            Text(latest.name)
                                .font(.caption)
                                .fontWeight(.medium)
                                .lineLimit(1)
                            Text("\(latest.distanceFormatted) • \(latest.durationFormatted)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Text(latest.startDate, style: .relative)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: CornerRadius.md).fill(Color(.systemBackground)))
            .shadow(color: .black.opacity(0.05), radius: 5, y: 2)
        }
    }
}

// MARK: - Date Extension

extension Date {
    func timeAgoDisplay() -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        StravaSettingsView()
    }
}
