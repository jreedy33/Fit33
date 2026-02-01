import SwiftUI

struct SettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var notificationManager = NotificationManager.shared
    @StateObject private var stravaService = StravaService.shared
    @StateObject private var fitbitService = FitbitService.shared
    @StateObject private var healthKitService = HealthKitService.shared
    
    @State private var versionTapCount = 0
    @State private var showDevMenu = false
    @State private var showAdminPassword = false
    @State private var isAdminAuthenticated = false
    
    @State private var showBugReportSheet = false
    @State private var isSyncingProfile = false
    @State private var syncProfileStatus = ""
    @State private var showTutorialTest = false
    @StateObject private var appearanceManager = AppearanceManager.shared
    @StateObject private var adManager = AdManager.shared
    @StateObject private var premiumManager = PremiumManager.shared
    
    // Clean gradient card background matching app style
    private var cardBackground: Color {
        colorScheme == .dark ? Color(white: 0.12) : Color.white
    }
    
    var body: some View {
        ZStack {
                // Background gradient
                LinearGradient(
                    gradient: Gradient(colors: colorScheme == .dark
                        ? [Color(red: 0.08, green: 0.10, blue: 0.18), Color(red: 0.05, green: 0.06, blue: 0.10), Color(red: 0.04, green: 0.04, blue: 0.06)]
                        : [Color(red: 0.85, green: 0.92, blue: 1.0), Color(red: 0.95, green: 0.97, blue: 1.0), Color.white]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        // Notifications Section
                        settingsSection(title: "Notifications") {
                            VStack(spacing: 0) {
                                notificationsRow()
                            }
                        }
                        
                        // App Preferences Section
                        settingsSection(title: "App Preferences") {
                            VStack(spacing: 0) {
                                appearanceRow()
                                
                                Divider().padding(.leading, 52)
                                
                                videoGenderRow()
                            }
                        }
                        
                        // Developer/Testing Section
                        settingsSection(title: "Developer Testing") {
                            VStack(spacing: 0) {
                                // Widget / Training Hub
                                NavigationLink(destination: TrainingHubView()) {
                                    HStack(spacing: 16) {
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(
                                                    LinearGradient(
                                                        colors: [Color.blue.opacity(0.15), Color.cyan.opacity(0.15)],
                                                        startPoint: .topLeading,
                                                        endPoint: .bottomTrailing
                                                    )
                                                )
                                                .frame(width: 36, height: 36)
                                            Image(systemName: "square.grid.2x2.fill")
                                                .font(.system(size: 16))
                                                .foregroundStyle(
                                                    LinearGradient(
                                                        colors: [Color.blue, Color.cyan],
                                                        startPoint: .topLeading,
                                                        endPoint: .bottomTrailing
                                                    )
                                                )
                                        }
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Widget")
                                                .font(.body)
                                                .foregroundColor(.primary)
                                            Text("iOS home screen widget")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        
                                        Spacer()
                                        
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(.vertical, 12)
                                    .padding(.horizontal, 16)
                                }
                                .buttonStyle(.plain)
                                
                                Divider().padding(.leading, 52)
                                
                                // Test Tutorial Flow
                                Button(action: { showTutorialTest = true }) {
                                    HStack(spacing: 16) {
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(
                                                    LinearGradient(
                                                        colors: [Color.purple.opacity(0.15), Color.pink.opacity(0.15)],
                                                        startPoint: .topLeading,
                                                        endPoint: .bottomTrailing
                                                    )
                                                )
                                                .frame(width: 36, height: 36)
                                            Image(systemName: "play.rectangle.fill")
                                                .font(.system(size: 16))
                                                .foregroundStyle(
                                                    LinearGradient(
                                                        colors: [Color.purple, Color.pink],
                                                        startPoint: .topLeading,
                                                        endPoint: .bottomTrailing
                                                    )
                                                )
                                        }
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Test Tutorial")
                                                .font(.body)
                                                .foregroundColor(.primary)
                                            Text("Preview the welcome tutorial flow")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        
                                        Spacer()
                                        
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(.vertical, 12)
                                    .padding(.horizontal, 16)
                                }
                                .buttonStyle(.plain)
                                
                                #if DEBUG
                                Divider().padding(.leading, 52)
                                
                                // Session Logs (Developer only)
                                NavigationLink(destination: DevSessionLogsView()) {
                                    HStack(spacing: 16) {
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(
                                                    LinearGradient(
                                                        colors: [Color.orange.opacity(0.15), Color.red.opacity(0.15)],
                                                        startPoint: .topLeading,
                                                        endPoint: .bottomTrailing
                                                    )
                                                )
                                                .frame(width: 36, height: 36)
                                            Image(systemName: "doc.text.magnifyingglass")
                                                .font(.system(size: 16))
                                                .foregroundStyle(
                                                    LinearGradient(
                                                        colors: [Color.orange, Color.red],
                                                        startPoint: .topLeading,
                                                        endPoint: .bottomTrailing
                                                    )
                                                )
                                        }
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Session Logs")
                                                .font(.body)
                                                .foregroundColor(.primary)
                                            Text("View current & previous logs")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        
                                        Spacer()
                                        
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(.vertical, 12)
                                    .padding(.horizontal, 16)
                                }
                                .buttonStyle(.plain)
                                
                                Divider().padding(.leading, 52)
                                
                                // Onboarding Test
                                onboardingTestRow()
                                #endif
                                
                                Divider().padding(.leading, 52)
                                
                                adsToggleRow()
                                
                                Divider().padding(.leading, 52)
                                
                                freeUserToggleRow()
                                
                                Divider().padding(.leading, 52)
                                
                                resetAppStateRow()
                            }
                        }
                        
                        // Privacy & Security Section
                        settingsSection(title: "Privacy & Security") {
                            VStack(spacing: 0) {
                                navigationRow(
                                    icon: "lock.fill",
                                    title: "Privacy Settings",
                                    subtitle: "Control your data",
                                    color: .blue
                                ) {
                                    // Navigate to privacy settings
                                }
                                
                                Divider().padding(.leading, 52)
                                
                                navigationRow(
                                    icon: "shield.fill",
                                    title: "Security",
                                    subtitle: "Password and authentication",
                                    color: .green
                                ) {
                                    // Navigate to security settings
                                }
                            }
                        }
                        
                        // Data & Backup Section
                        settingsSection(title: "Data & Backup") {
                            VStack(spacing: 0) {
                                NavigationLink(destination: CloudBackupView()) {
                                    HStack(spacing: 16) {
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(
                                                    LinearGradient(
                                                        colors: [Color.blue.opacity(0.15), Color.cyan.opacity(0.15)],
                                                        startPoint: .topLeading,
                                                        endPoint: .bottomTrailing
                                                    )
                                                )
                                                .frame(width: 36, height: 36)
                                            Image(systemName: "icloud.and.arrow.up")
                                                .font(.system(size: 16))
                                                .foregroundStyle(
                                                    LinearGradient(
                                                        colors: [Color.blue, Color.cyan],
                                                        startPoint: .topLeading,
                                                        endPoint: .bottomTrailing
                                                    )
                                                )
                                        }
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Cloud Backup")
                                                .font(.body)
                                                .foregroundColor(.primary)
                                            Text("Sync & restore your data")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        
                                        Spacer()
                                        
                                        Image(systemName: "chevron.right")
                                            .font(.caption)
                                            .fontWeight(.semibold)
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(16)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                
                                Divider().padding(.leading, 68)
                                
                                // Sync Profile Button - for users experiencing sync issues
                                Button(action: { syncProfileToCloud() }) {
                                    HStack(spacing: 16) {
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(
                                                    LinearGradient(
                                                        colors: [Color.orange.opacity(0.15), Color.yellow.opacity(0.15)],
                                                        startPoint: .topLeading,
                                                        endPoint: .bottomTrailing
                                                    )
                                                )
                                                .frame(width: 36, height: 36)
                                            if isSyncingProfile {
                                                ProgressView()
                                                    .scaleEffect(0.8)
                                            } else {
                                                Image(systemName: "arrow.triangle.2.circlepath")
                                                    .font(.system(size: 16))
                                                    .foregroundStyle(
                                                        LinearGradient(
                                                            colors: [Color.orange, Color.yellow],
                                                            startPoint: .topLeading,
                                                            endPoint: .bottomTrailing
                                                        )
                                                    )
                                            }
                                        }
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Sync Profile")
                                                .font(.body)
                                                .foregroundColor(.primary)
                                            Text(syncProfileStatus.isEmpty ? "Push local data to cloud" : syncProfileStatus)
                                                .font(.caption)
                                                .foregroundColor(syncProfileStatus.contains("✓") ? .green : .secondary)
                                        }
                                        
                                        Spacer()
                                    }
                                    .padding(16)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .disabled(isSyncingProfile)
                                
                                Divider().padding(.leading, 68)
                                
                                NavigationLink(destination: DataDownloadView()) {
                                    HStack(spacing: 16) {
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(
                                                    LinearGradient(
                                                        colors: [Color.green.opacity(0.15), Color.mint.opacity(0.15)],
                                                        startPoint: .topLeading,
                                                        endPoint: .bottomTrailing
                                                    )
                                                )
                                                .frame(width: 36, height: 36)
                                            Image(systemName: "arrow.down.doc.fill")
                                                .font(.system(size: 16))
                                                .foregroundStyle(
                                                    LinearGradient(
                                                        colors: [Color.green, Color.mint],
                                                        startPoint: .topLeading,
                                                        endPoint: .bottomTrailing
                                                    )
                                                )
                                        }
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Download Data")
                                                .font(.body)
                                                .foregroundColor(.primary)
                                            Text("Export your fitness data")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        
                                        Spacer()
                                        
                                        Image(systemName: "chevron.right")
                                            .font(.caption)
                                            .fontWeight(.semibold)
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(16)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        
                        // Integrations Section
                        settingsSection(title: "Integrations") {
                            VStack(spacing: 0) {
                                // InBody Integration
                                NavigationLink(destination: InBodySettingsView()) {
                                    HStack(spacing: 16) {
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(
                                                    LinearGradient(
                                                        colors: [Color(red: 0, green: 0.48, blue: 0.8).opacity(0.15), Color.cyan.opacity(0.15)],
                                                        startPoint: .topLeading,
                                                        endPoint: .bottomTrailing
                                                    )
                                                )
                                                .frame(width: 36, height: 36)
                                            Image(systemName: "figure.stand")
                                                .font(.system(size: 16))
                                                .foregroundStyle(
                                                    LinearGradient(
                                                        colors: [Color(red: 0, green: 0.48, blue: 0.8), Color.cyan],
                                                        startPoint: .topLeading,
                                                        endPoint: .bottomTrailing
                                                    )
                                                )
                                        }
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("InBody")
                                                .font(.body)
                                                .foregroundColor(.primary)
                                            Text(InBodyService.shared.isConnected ? "Connected • Body composition synced" : "Sync body composition data")
                                                .font(.caption)
                                                .foregroundColor(InBodyService.shared.isConnected ? .green : .secondary)
                                        }
                                        
                                        Spacer()
                                        
                                        if InBodyService.shared.isConnected {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundColor(.green)
                                                .font(.system(size: 14))
                                        }
                                        
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(.vertical, 12)
                                    .padding(.horizontal, 16)
                                }
                                .buttonStyle(.plain)
                                
                                Divider().padding(.leading, 52)
                                
                                // Strava Integration
                                NavigationLink(destination: StravaSettingsView()) {
                                    HStack(spacing: 16) {
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(
                                                    LinearGradient(
                                                        colors: [Color(red: 252/255, green: 76/255, blue: 2/255).opacity(0.15), Color.orange.opacity(0.15)],
                                                        startPoint: .topLeading,
                                                        endPoint: .bottomTrailing
                                                    )
                                                )
                                                .frame(width: 36, height: 36)
                                            Image(systemName: "figure.run")
                                                .font(.system(size: 16))
                                                .foregroundStyle(
                                                    LinearGradient(
                                                        colors: [Color(red: 252/255, green: 76/255, blue: 2/255), Color.orange],
                                                        startPoint: .topLeading,
                                                        endPoint: .bottomTrailing
                                                    )
                                                )
                                        }
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Strava")
                                                .font(.body)
                                                .foregroundColor(.primary)
                                            Text(stravaService.isConnected ? "Connected • Cardio synced" : "Sync cardio activities")
                                                .font(.caption)
                                                .foregroundColor(stravaService.isConnected ? .green : .secondary)
                                        }
                                        
                                        Spacer()
                                        
                                        if stravaService.isConnected {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundColor(.green)
                                                .font(.system(size: 20))
                                        } else {
                                            Image(systemName: "chevron.right")
                                                .font(.system(size: 14, weight: .medium))
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    .padding(.vertical, 12)
                                    .padding(.horizontal, 16)
                                }
                                .buttonStyle(.plain)
                                
                                Divider().padding(.leading, 52)
                                
                                // Fitbit Integration
                                NavigationLink(destination: FitbitSettingsView()) {
                                    HStack(spacing: 16) {
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(
                                                    LinearGradient(
                                                        colors: [Color(red: 0, green: 0.73, blue: 0.77).opacity(0.15), Color(red: 0, green: 0.55, blue: 0.58).opacity(0.15)],
                                                        startPoint: .topLeading,
                                                        endPoint: .bottomTrailing
                                                    )
                                                )
                                                .frame(width: 36, height: 36)
                                            Image(systemName: "heart.circle.fill")
                                                .font(.system(size: 16))
                                                .foregroundStyle(
                                                    LinearGradient(
                                                        colors: [Color(red: 0, green: 0.73, blue: 0.77), Color(red: 0, green: 0.55, blue: 0.58)],
                                                        startPoint: .topLeading,
                                                        endPoint: .bottomTrailing
                                                    )
                                                )
                                        }
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Fitbit")
                                                .font(.body)
                                                .foregroundColor(.primary)
                                            Text(fitbitService.isConnected ? "Connected • Steps & workouts synced" : "Sync steps, workouts & sleep")
                                                .font(.caption)
                                                .foregroundColor(fitbitService.isConnected ? .green : .secondary)
                                        }
                                        
                                        Spacer()
                                        
                                        if fitbitService.isConnected {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundColor(.green)
                                                .font(.system(size: 20))
                                        } else {
                                            Image(systemName: "chevron.right")
                                                .font(.system(size: 14, weight: .medium))
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    .padding(.vertical, 12)
                                    .padding(.horizontal, 16)
                                }
                                .buttonStyle(.plain)
                                
                                Divider().padding(.leading, 52)
                                
                                // Apple Health Integration (Nike Run Club, Apple Watch, etc.)
                                NavigationLink(destination: HealthKitSettingsView()) {
                                    HStack(spacing: 16) {
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(
                                                    LinearGradient(
                                                        colors: [Color.red.opacity(0.15), Color.pink.opacity(0.15)],
                                                        startPoint: .topLeading,
                                                        endPoint: .bottomTrailing
                                                    )
                                                )
                                                .frame(width: 36, height: 36)
                                            Image(systemName: "heart.fill")
                                                .font(.system(size: 16))
                                                .foregroundStyle(
                                                    LinearGradient(
                                                        colors: [Color.red, Color.pink],
                                                        startPoint: .topLeading,
                                                        endPoint: .bottomTrailing
                                                    )
                                                )
                                        }
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Apple Health")
                                                .font(.body)
                                                .foregroundColor(.primary)
                                            Text(healthKitService.isAuthorized ? "Connected • Nike Run Club & more" : "Nike Run Club, Apple Watch & more")
                                                .font(.caption)
                                                .foregroundColor(healthKitService.isAuthorized ? .green : .secondary)
                                        }
                                        
                                        Spacer()
                                        
                                        if healthKitService.isAuthorized {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundColor(.green)
                                                .font(.system(size: 20))
                                        } else {
                                            Image(systemName: "chevron.right")
                                                .font(.system(size: 14, weight: .medium))
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    .padding(.vertical, 12)
                                    .padding(.horizontal, 16)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        
                        // Units & Localization Section
                        settingsSection(title: "Units & Localization") {
                            UnitsLocalizationSettingsSection()
                        }
                        
                        // Support Section
                        settingsSection(title: "Support") {
                            VStack(spacing: 0) {
                                navigationRow(
                                    icon: "questionmark.circle.fill",
                                    title: "Help & FAQ",
                                    subtitle: "Get answers to common questions",
                                    color: .purple
                                ) {
                                    // Navigate to help
                                }
                                
                                Divider().padding(.leading, 52)
                                
                                navigationRow(
                                    icon: "envelope.fill",
                                    title: "Contact Support",
                                    subtitle: "Reach out to our team",
                                    color: .cyan
                                ) {
                                    openSupportEmail()
                                }
                                
                                Divider().padding(.leading, 52)
                                
                                // Report a Bug
                                Button(action: {
                                    HapticManager.impact(.light)
                                    showBugReportSheet = true
                                }) {
                                    HStack(spacing: 16) {
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(Color.red.opacity(0.15))
                                                .frame(width: 36, height: 36)
                                            Image(systemName: "ant.fill")
                                                .font(.system(size: 16))
                                                .foregroundColor(.red)
                                        }
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Report a Bug")
                                                .font(.body)
                                                .foregroundColor(.primary)
                                            Text("Help us improve the app")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        
                                        Spacer()
                                        
                                        Image(systemName: "chevron.right")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(.vertical, 10)
                                    .padding(.horizontal, 16)
                                }
                                .buttonStyle(.plain)
                                
                                Divider().padding(.leading, 52)
                                
                                navigationRow(
                                    icon: "star.fill",
                                    title: "Rate App",
                                    subtitle: "Share your feedback",
                                    color: .yellow
                                ) {
                                    // Open app store rating
                                }
                            }
                        }
                        
                        // About Section
                        settingsSection(title: "About") {
                            VStack(spacing: 0) {
                                // Tappable version row (5 taps for dev menu - only in debug/testflight)
                                Button(action: {
                                    #if DEBUG
                                    versionTapCount += 1
                                    
                                    // Haptic feedback
                                    let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                                    impactFeedback.impactOccurred()
                                    
                                    if versionTapCount >= 5 {
                                        // Success haptic
                                        let successFeedback = UINotificationFeedbackGenerator()
                                        successFeedback.notificationOccurred(.success)
                                        
                                        // Show admin password prompt
                                        showAdminPassword = true
                                        versionTapCount = 0
                                    }
                                    #endif
                                }) {
                                    infoRow(
                                        icon: "info.circle.fill",
                                        title: "Version",
                                        value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0",
                                        color: .gray
                                    )
                                }
                                .buttonStyle(.plain)
                                
                                // Hidden NavigationLink to dev menu (after password authentication)
                                NavigationLink(destination: DevMenuView(), isActive: $showDevMenu) {
                                    EmptyView()
                                }
                                .hidden()
                                
                                Divider().padding(.leading, 52)
                                
                                NavigationLink(destination: TermsConditionsView()) {
                                    HStack(spacing: 16) {
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(Color.gray.opacity(0.15))
                                                .frame(width: 36, height: 36)
                                            Image(systemName: "doc.text.fill")
                                                .font(.system(size: 16))
                                                .foregroundColor(.gray)
                                        }
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Terms & Conditions")
                                                .font(.body)
                                                .foregroundColor(.primary)
                                            Text("Legal information")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        
                                        Spacer()
                                        
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(.vertical, 12)
                                    .padding(.horizontal, 16)
                                }
                                .buttonStyle(.plain)
                                
                                Divider().padding(.leading, 52)
                                
                                NavigationLink(destination: PrivacyPolicyView()) {
                                    HStack(spacing: 16) {
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(Color.gray.opacity(0.15))
                                                .frame(width: 36, height: 36)
                                            Image(systemName: "hand.raised.fill")
                                                .font(.system(size: 16))
                                                .foregroundColor(.gray)
                                        }
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Privacy Policy")
                                                .font(.body)
                                                .foregroundColor(.primary)
                                            Text("How we handle your data")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        
                                        Spacer()
                                        
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(.vertical, 12)
                                    .padding(.horizontal, 16)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding()
                    .padding(.bottom, 60)
                }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            SessionLogManager.shared.logScreen(.settings)
        }
        .sheet(isPresented: $showAdminPassword) {
            AdminPasswordView(isAuthenticated: $isAdminAuthenticated)
        }
        .onChange(of: isAdminAuthenticated) { authenticated in
            if authenticated {
                showAdminPassword = false
                // Small delay to let sheet dismiss before navigating
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    showDevMenu = true
                }
            }
        }
        .sheet(isPresented: $showBugReportSheet) {
            ManualBugReportView()
        }
        .fullScreenCover(isPresented: $showTutorialTest) {
            WelcomeTutorialView(isPresented: $showTutorialTest)
        }
    }
    
    // MARK: - Section Container
    
    private func settingsSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)
            
            content()
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(cardBackground)
                        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.05), radius: 10, x: 0, y: 4)
                )
        }
    }
    
    // MARK: - Row Components
    
    private func navigationRow(icon: String, title: String, subtitle: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: { HapticManager.impact(.light); action() }) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(color)
                    .frame(width: 28)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
            }
            .padding(16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    private func infoRow(icon: String, title: String, value: String, color: Color) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
                .frame(width: 28)
            
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.primary)
            
            Spacer()
            
            Text(value)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(16)
    }
    
    // MARK: - Ads Toggle Row
    private func adsToggleRow() -> some View {
        HStack(spacing: 16) {
            Image(systemName: "play.rectangle.fill")
                .font(.title3)
                .foregroundColor(.red)
                .frame(width: 28)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Test Ads")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                Text(adManager.adsEnabled ? "Ads will play between sets" : "Ads are disabled")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Toggle("", isOn: $adManager.adsEnabled)
                .labelsHidden()
        }
        .padding(16)
    }
    
    private func freeUserToggleRow() -> some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        LinearGradient(
                            colors: premiumManager.isPremiumUser 
                                ? [Color.green.opacity(0.15), Color.mint.opacity(0.15)]
                                : [Color.orange.opacity(0.15), Color.yellow.opacity(0.15)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 36, height: 36)
                Image(systemName: premiumManager.isPremiumUser ? "crown.fill" : "person.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(
                        LinearGradient(
                            colors: premiumManager.isPremiumUser 
                                ? [Color.green, Color.mint]
                                : [Color.orange, Color.yellow],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Free User Mode")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                Text(premiumManager.isPremiumUser ? "Premium features unlocked" : "Testing as free user")
                    .font(.caption)
                    .foregroundColor(premiumManager.isPremiumUser ? .green : .orange)
            }
            
            Spacer()
            
            // Toggle is inverted: ON = Free user (not premium), OFF = Premium user
            Toggle("", isOn: Binding(
                get: { !premiumManager.isPremiumUser },
                set: { premiumManager.setPremiumStatus(!$0) }
            ))
            .labelsHidden()
            .tint(.orange)
        }
        .padding(16)
    }
    
    // MARK: - Reset App State Row
    @State private var showingResetConfirmation = false
    @State private var resetComplete = false
    
    #if DEBUG
    @State private var showOnboardingTest = false
    @State private var onboardingTestRunning = false
    @State private var onboardingTestResult: String = ""
    
    private func onboardingTestRow() -> some View {
        Button(action: {
            HapticManager.impact(.light)
            showOnboardingTest = true
        }) {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(
                            LinearGradient(
                                colors: [Color.purple.opacity(0.15), Color.pink.opacity(0.15)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 36, height: 36)
                    Image(systemName: "testtube.2")
                        .font(.system(size: 16))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.purple, Color.pink],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Onboarding Test")
                        .font(.body)
                        .foregroundColor(.primary)
                    Text("Test username saving flow")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if onboardingTestRunning {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
        }
        .buttonStyle(.plain)
        .alert("Run Onboarding Test?", isPresented: $showOnboardingTest) {
            Button("Cancel", role: .cancel) { }
            Button("Run Test") {
                runOnboardingTest()
            }
        } message: {
            Text("This will create a REAL test user in the database. The username saving flow will be tested and logged to console.")
        }
        .alert("Test Complete", isPresented: .constant(!onboardingTestResult.isEmpty)) {
            Button("OK") {
                onboardingTestResult = ""
            }
        } message: {
            Text(onboardingTestResult)
        }
    }
    
    private func runOnboardingTest() {
        onboardingTestRunning = true
        Task {
            let result = await OnboardingTestHelper.shared.runFullOnboardingTest()
            await MainActor.run {
                onboardingTestRunning = false
                if result.isSuccess {
                    onboardingTestResult = "✅ All tests passed!\n\nEmail: \(result.testEmail)\nUsername: @\(result.testUsername)"
                } else {
                    onboardingTestResult = "❌ Test failed!\n\nErrors:\n" + result.errors.joined(separator: "\n")
                }
            }
        }
    }
    #endif
    
    private func resetAppStateRow() -> some View {
        Button(action: {
            HapticManager.impact(.light)
            showingResetConfirmation = true
        }) {
            HStack(spacing: 16) {
                Image(systemName: "arrow.counterclockwise.circle.fill")
                    .font(.title3)
                    .foregroundColor(.orange)
                    .frame(width: 28)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Reset App State")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    Text("Simulate fresh app boot (keeps login)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if resetComplete {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(16)
        }
        .buttonStyle(.plain)
        .alert("Reset App State?", isPresented: $showingResetConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                performAppStateReset()
            }
        } message: {
            Text("This will clear all cached data, active programs, and navigation state. You'll stay logged in and won't need to redo onboarding.")
        }
    }
    
    private func performAppStateReset() {
        print("🔄 [DEV] Performing app state reset...")
        
        // Reset WorkoutManager state
        WorkoutManager.shared.resetForSignOut()
        print("   ✓ WorkoutManager reset")
        
        // Clear any cached UserDefaults for programs (but keep user auth)
        let programKeys = [
            "cached_active_program",
            "cached_active_program_active"
        ]
        for key in programKeys {
            UserDefaults.standard.removeObject(forKey: key)
        }
        print("   ✓ Program cache cleared")
        
        // Force refresh cloud program service
        Task {
            await CloudProgramService.shared.forceRefreshAllData()
            print("   ✓ CloudProgramService refreshed")
        }
        
        // Show success feedback
        resetComplete = true
        
        // Hide checkmark after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            resetComplete = false
        }
        
        print("🔄 [DEV] App state reset complete!")
        
        // Trigger haptic feedback
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }
    
    // MARK: - Appearance Row
    private func appearanceRow() -> some View {
        HStack(spacing: 16) {
            Image(systemName: appearanceManager.appearanceMode.icon)
                .font(.title3)
                .foregroundColor(.indigo)
                .frame(width: 28)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Appearance")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                Text(appearanceManager.appearanceMode.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Menu {
                ForEach(AppearanceManager.AppearanceMode.allCases, id: \.self) { mode in
                    Button(action: {
                        withAnimation {
                            appearanceManager.appearanceMode = mode
                        }
                    }) {
                        HStack {
                            Image(systemName: mode.icon)
                            Text(mode.rawValue)
                            if appearanceManager.appearanceMode == mode {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(appearanceManager.appearanceMode.rawValue)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                }
                .foregroundColor(.indigo)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.indigo.opacity(0.1))
                )
            }
        }
        .padding(16)
    }
    
    // MARK: - Video Gender Row
    @ViewBuilder
    private func videoGenderRow() -> some View {
        let currentGender = GenderFilterService.shared.getPreferredGender()
        
        HStack(spacing: 16) {
            Image(systemName: currentGender == .male ? "figure.stand" : "figure.stand.dress")
                .font(.title3)
                .foregroundColor(.cyan)
                .frame(width: 28)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Video Model")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                Text("Show \(currentGender.rawValue.lowercased()) exercise demonstrations")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Menu {
                ForEach(GenderFilterService.Gender.allCases, id: \.self) { gender in
                    Button(action: {
                        withAnimation {
                            GenderFilterService.shared.setPreferredGender(gender)
                        }
                    }) {
                        HStack {
                            Image(systemName: gender == .male ? "figure.stand" : "figure.stand.dress")
                            Text(gender.rawValue)
                            if currentGender == gender {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(currentGender.rawValue)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                }
                .foregroundColor(.cyan)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.cyan.opacity(0.1))
                )
            }
        }
        .padding(16)
    }
    
    // MARK: - Notifications Row
    private func notificationsRow() -> some View {
        NavigationLink(destination: NotificationSettingsView()) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.orange, Color.red],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 36, height: 36)
                    
                    Image(systemName: "bell.badge.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Smart Notifications")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    HStack(spacing: 6) {
                        Circle()
                            .fill(notificationManager.masterNotificationsEnabled && notificationManager.isAuthorized ? Color.green : Color.gray)
                            .frame(width: 8, height: 8)
                        
                        Text(notificationStatusText)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
            }
            .padding(16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    private var notificationStatusText: String {
        if !notificationManager.isAuthorized {
            return "Disabled in system settings"
        } else if notificationManager.masterNotificationsEnabled {
            return "Active • Customize alerts"
        } else {
            return "Paused"
        }
    }
    
    // MARK: - Support Email
    private func openSupportEmail() {
        let email = "info@doublethr33s.com"
        let subject = "Fit33 Support Request"
        let body = """
        
        
        ---
        App Version: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown")
        iOS Version: \(UIDevice.current.systemVersion)
        Device: \(UIDevice.current.model)
        """
        
        // URL encode the subject and body
        let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let encodedBody = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        
        if let url = URL(string: "mailto:\(email)?subject=\(encodedSubject)&body=\(encodedBody)") {
            UIApplication.shared.open(url)
        }
    }
    
    // MARK: - Profile Sync
    private func syncProfileToCloud() {
        guard !isSyncingProfile else { return }
        
        isSyncingProfile = true
        syncProfileStatus = "Syncing..."
        HapticManager.impact(.light)
        
        Task {
            do {
                try await SupabaseManager.shared.forceSyncProfileToCloud()
                await MainActor.run {
                    syncProfileStatus = "✓ Synced successfully"
                    HapticManager.notification(.success)
                    isSyncingProfile = false
                }
                
                // Clear status after delay
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                await MainActor.run {
                    syncProfileStatus = ""
                }
            } catch {
                await MainActor.run {
                    syncProfileStatus = "Failed: \(error.localizedDescription)"
                    HapticManager.notification(.error)
                    isSyncingProfile = false
                }
                
                // Clear error after delay
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                await MainActor.run {
                    syncProfileStatus = ""
                }
            }
        }
    }
}

#Preview {
    SettingsView()
}
