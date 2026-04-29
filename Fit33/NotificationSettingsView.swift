import SwiftUI
import UserNotifications

struct NotificationSettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var notificationManager = NotificationManager.shared
    @State private var showingPermissionAlert = false
    @State private var expandedCategories: Set<String> = []
    @State private var hasAppeared = false
    
    // Clean gradient card background matching app style
    
    var body: some View {
        ZStack {
            // Animated orb background (consistent with Profile/Stats screens)
            AnimatedOrbBackground.stats(colorScheme: colorScheme)
                .ignoresSafeArea(.all, edges: .all)
            
            ScrollView {
                VStack(spacing: 20) {
                    // Header Card
                    headerCard
                    
                    // Permission Warning (if not authorized)
                    if !notificationManager.isAuthorized {
                        permissionWarningCard
                    }
                    
                    // Master Toggle Section
                    masterToggleSection
                    
                    // Quick Settings
                    if notificationManager.masterNotificationsEnabled && notificationManager.isAuthorized {
                        quickSettingsSection
                        
                        // Notification Categories
                        ForEach(NotificationCategory.allCases) { category in
                            categorySection(category)
                        }
                        
                        // Quiet Hours Section
                        quietHoursSection
                        
                        // Test Notifications (Debug)
                        #if DEBUG
                        testNotificationsSection
                        #endif
                    }
                }
                .padding()
                .padding(.bottom, 60)
            }
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // Only check once to prevent state changes causing navigation flicker
            guard !hasAppeared else { return }
            hasAppeared = true
            
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.1))
                notificationManager.checkAuthorizationStatus()
            }
        }
        .alert("Notifications Disabled", isPresented: $showingPermissionAlert) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Enable notifications in Settings to receive workout reminders and updates.")
        }
    }
    
    // MARK: - Header Card
    
    private var headerCard: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.orange, Color.red],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 70, height: 70)
                    .shadow(color: .orange.opacity(0.3), radius: 8, x: 0, y: 4)
                
                Image(systemName: "bell.badge.fill")
                    .font(.ds_heading1)
                    .foregroundColor(.white)
            }
            
            VStack(spacing: 8) {
                Text("Smart Notifications")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Text("Get personalized reminders, celebrate achievements, and stay motivated on your fitness journey.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.cardBackground)
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.08), radius: 10, x: 0, y: 4)
        )
    }
    
    // MARK: - Permission Warning
    
    private var permissionWarningCard: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.red.opacity(0.1))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.title3)
                        .foregroundColor(.red)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Notifications Disabled")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    Text("Enable notifications to receive reminders and updates")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            
            Button(action: {
                Task {
                    let granted = await notificationManager.requestAuthorization()
                    if !granted {
                        showingPermissionAlert = true
                    }
                }
            }) {
                HStack {
                    Image(systemName: "bell.badge.fill")
                        .font(.ds_labelMedium)
                    Text("Enable Notifications")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.sm)
                .background(
                    LinearGradient(
                        colors: [Color.orange, Color.red],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(CornerRadius.md)
            }
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.lg)
                .fill(Color.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.lg)
                        .stroke(Color.red.opacity(0.3), lineWidth: 1)
                )
        )
    }
    
    // MARK: - Master Toggle
    
    private var masterToggleSection: some View {
        settingsSection(title: "General") {
            VStack(spacing: 0) {
                HStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: notificationManager.masterNotificationsEnabled
                                        ? [Color.green, Color.mint]
                                        : [Color.gray, Color.gray.opacity(0.7)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 40, height: 40)
                        
                        Image(systemName: notificationManager.masterNotificationsEnabled ? "bell.fill" : "bell.slash.fill")
                            .font(.ds_heading3)
                            .foregroundColor(.white)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("All Notifications")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                        
                        Text(notificationManager.masterNotificationsEnabled ? "Notifications are active" : "All notifications are paused")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Toggle("", isOn: $notificationManager.masterNotificationsEnabled)
                        .labelsHidden()
                        .tint(.green)
                }
                .padding(Spacing.md)
            }
        }
    }
    
    // MARK: - Quick Settings
    
    private var quickSettingsSection: some View {
        settingsSection(title: "Workout Reminder") {
            VStack(spacing: 0) {
                // Daily Reminder Toggle
                HStack(spacing: 16) {
                    Image(systemName: "clock.fill")
                        .font(.title3)
                        .foregroundColor(.blue)
                        .frame(width: 28)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Daily Reminder")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                        
                        Text("Get reminded to work out")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Toggle("", isOn: Binding(
                        get: { notificationManager.isNotificationEnabled(.dailyWorkoutReminder) },
                        set: { notificationManager.toggleNotification(.dailyWorkoutReminder, enabled: $0) }
                    ))
                    .labelsHidden()
                    .tint(.blue)
                }
                .padding(Spacing.md)
                
                // Time Picker (only show if daily reminder is enabled)
                if notificationManager.isNotificationEnabled(.dailyWorkoutReminder) {
                    Divider()
                        .padding(.leading, 52)
                    
                    HStack(spacing: 16) {
                        Image(systemName: "alarm.fill")
                            .font(.title3)
                            .foregroundColor(.orange)
                            .frame(width: 28)
                        
                        Text("Reminder Time")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                        
                        Spacer()
                        
                        DatePicker(
                            "",
                            selection: $notificationManager.dailyReminderTime,
                            displayedComponents: .hourAndMinute
                        )
                        .labelsHidden()
                        .tint(.orange)
                    }
                    .padding(Spacing.md)
                }
            }
        }
    }
    
    // MARK: - Category Section
    
    private func categorySection(_ category: NotificationCategory) -> some View {
        let isExpanded = expandedCategories.contains(category.id)
        
        return settingsSection(title: category.rawValue) {
            VStack(spacing: 0) {
                // Category Header with expand/collapse
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        if isExpanded {
                            expandedCategories.remove(category.id)
                        } else {
                            expandedCategories.insert(category.id)
                        }
                    }
                }) {
                    HStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(category.color.opacity(0.15))
                                .frame(width: 40, height: 40)
                            
                            Image(systemName: category.icon)
                                .font(.ds_heading3)
                                .foregroundColor(category.color)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(enabledCount(for: category)) of \(category.notifications.count) enabled")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.primary)
                            
                            Text("Tap to customize")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    }
                    .padding(Spacing.md)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                
                // Expanded notification list
                if isExpanded {
                    ForEach(category.notifications) { type in
                        Divider()
                            .padding(.leading, 52)
                        
                        notificationToggleRow(type)
                    }
                }
            }
        }
    }
    
    private func enabledCount(for category: NotificationCategory) -> Int {
        category.notifications.filter { notificationManager.isNotificationEnabled($0) }.count
    }
    
    private func notificationToggleRow(_ type: NotificationType) -> some View {
        HStack(spacing: 16) {
            Image(systemName: type.icon)
                .font(.ds_bodyRegular)
                .foregroundColor(type.color)
                .frame(width: 28)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(type.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                Text(type.description)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            
            Spacer()
            
            Toggle("", isOn: Binding(
                get: { notificationManager.isNotificationEnabled(type) },
                set: { notificationManager.toggleNotification(type, enabled: $0) }
            ))
            .labelsHidden()
            .tint(type.color)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
    }
    
    // MARK: - Quiet Hours
    
    private var quietHoursSection: some View {
        settingsSection(title: "Quiet Hours") {
            VStack(spacing: 0) {
                // Toggle
                HStack(spacing: 16) {
                    Image(systemName: "moon.fill")
                        .font(.title3)
                        .foregroundColor(.purple)
                        .frame(width: 28)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Do Not Disturb")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                        
                        Text("Pause notifications during sleep hours")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Toggle("", isOn: $notificationManager.quietHoursEnabled)
                        .labelsHidden()
                        .tint(.purple)
                }
                .padding(Spacing.md)
                
                if notificationManager.quietHoursEnabled {
                    Divider()
                        .padding(.leading, 52)
                    
                    // Start time
                    HStack(spacing: 16) {
                        Image(systemName: "bed.double.fill")
                            .font(.ds_bodyRegular)
                            .foregroundColor(.indigo)
                            .frame(width: 28)
                        
                        Text("From")
                            .font(.subheadline)
                            .foregroundColor(.primary)
                        
                        Spacer()
                        
                        DatePicker(
                            "",
                            selection: $notificationManager.quietHoursStart,
                            displayedComponents: .hourAndMinute
                        )
                        .labelsHidden()
                    }
                    .padding(Spacing.md)
                    
                    Divider()
                        .padding(.leading, 52)
                    
                    // End time
                    HStack(spacing: 16) {
                        Image(systemName: "sunrise.fill")
                            .font(.ds_bodyRegular)
                            .foregroundColor(.yellow)
                            .frame(width: 28)
                        
                        Text("Until")
                            .font(.subheadline)
                            .foregroundColor(.primary)
                        
                        Spacer()
                        
                        DatePicker(
                            "",
                            selection: $notificationManager.quietHoursEnd,
                            displayedComponents: .hourAndMinute
                        )
                        .labelsHidden()
                    }
                    .padding(Spacing.md)
                }
            }
        }
    }
    
    // MARK: - Test Notifications (Debug)
    
    #if DEBUG
    private var testNotificationsSection: some View {
        settingsSection(title: "🧪 Test Notifications") {
            VStack(spacing: 12) {
                testButton(
                    title: "Test Streak Celebration",
                    icon: "flame.fill",
                    color: .orange
                ) {
                    notificationManager.sendStreakCelebration(streakCount: 7)
                }
                
                testButton(
                    title: "Test Comeback Reminder",
                    icon: "arrow.counterclockwise",
                    color: .blue
                ) {
                    notificationManager.sendComebackReminder(daysAway: 5)
                }
                
                testButton(
                    title: "Test Personal Record",
                    icon: "trophy.fill",
                    color: .yellow
                ) {
                    notificationManager.sendPersonalRecordNotification(
                        exercise: "Bench Press",
                        weight: 185,
                        previousBest: 175
                    )
                }
                
                testButton(
                    title: "Test Tier Promotion",
                    icon: "trophy.fill",
                    color: .yellow
                ) {
                    notificationManager.sendTierPromotionNotification(newTierName: "Silver", newTierRank: 2)
                }
                
                testButton(
                    title: "Test Steps Goal",
                    icon: "figure.walk",
                    color: .green
                ) {
                    notificationManager.sendStepsGoalAchieved(steps: 10000)
                }
            }
            .padding(Spacing.md)
        }
    }
    
    private func testButton(title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.ds_labelMedium)
                    .foregroundColor(color)
                    .frame(width: 24)
                
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Image(systemName: "paperplane.fill")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(color.opacity(0.1))
            )
        }
        .buttonStyle(.plain)
    }
    #endif
    
    // MARK: - Section Container
    
    private func settingsSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .padding(.horizontal, Spacing.xxs)
            
            content()
                .background(
                    RoundedRectangle(cornerRadius: CornerRadius.lg)
                        .fill(Color.cardBackground)
                        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.05), radius: 10, x: 0, y: 4)
                )
        }
    }
}

// MARK: - Notification Preview Card
struct NotificationPreviewCard: View {
    let type: NotificationType
    let title: String
    let message: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: CornerRadius.sm)
                        .fill(type.color.opacity(0.15))
                        .frame(width: 36, height: 36)
                    
                    Image(systemName: type.icon)
                        .font(.ds_labelLarge)
                        .foregroundColor(type.color)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("BUILTSIMPLE")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Text("now")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                }
            }
            
            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)
        }
        .padding(Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.lg)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
        )
    }
}

#Preview {
    NavigationStack {
        NotificationSettingsView()
    }
}

