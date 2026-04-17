import SwiftUI

struct PrivacySettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var privacyManager = PrivacySettingsManager.shared
    
    var body: some View {
        ZStack {
            AnimatedOrbBackground.stats(colorScheme: colorScheme)
                .ignoresSafeArea(.all, edges: .all)
            
            ScrollView {
                VStack(spacing: 20) {
                    headerCard
                    profilePhotoSection
                    socialFeaturesSection
                    discoverabilitySection
                    activityStatusSection
                    infoFooter
                }
                .padding()
                .padding(.bottom, 60)
            }
        }
        .navigationTitle("Privacy Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    // MARK: - Header
    
    private var headerCard: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.blue, Color.indigo],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 70, height: 70)
                    .shadow(color: .blue.opacity(0.3), radius: 8, x: 0, y: 4)
                
                Image(systemName: "lock.shield.fill")
                    .font(.ds_heading1)
                    .foregroundColor(.white)
            }
            
            VStack(spacing: 8) {
                Text("Privacy Controls")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Text("Choose what others can see about you. Changes apply immediately across all social features.")
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
    
    // MARK: - Profile Photo
    
    private var profilePhotoSection: some View {
        settingsSection(title: "Profile Photo") {
            VStack(spacing: 0) {
                privacyToggleRow(
                    icon: "person.crop.circle.fill",
                    title: "Hide Profile Photo",
                    subtitle: "Your initials will show instead of your photo in search results, friend activity, leagues, and all social features.",
                    color: .purple,
                    isOn: $privacyManager.hideProfilePhoto
                )
            }
        }
    }
    
    // MARK: - Social Features
    
    private var socialFeaturesSection: some View {
        settingsSection(title: "Social Features") {
            VStack(spacing: 0) {
                privacyToggleRow(
                    icon: "figure.run",
                    title: "Hide Friend Activity",
                    subtitle: "Your workouts will not appear in the friend activity feed. You can still see others' activity.",
                    color: .orange,
                    isOn: $privacyManager.hideFriendActivity
                )
                
                Divider().padding(.leading, 52)
                
                privacyToggleRow(
                    icon: "trophy.fill",
                    title: "Hide from Weekly League",
                    subtitle: "You will not be placed in or appear on weekly league leaderboards.",
                    color: .yellow,
                    isOn: $privacyManager.hideFromWeeklyLeague
                )
            }
        }
    }
    
    // MARK: - Discoverability
    
    private var discoverabilitySection: some View {
        settingsSection(title: "Discoverability") {
            VStack(spacing: 0) {
                privacyToggleRow(
                    icon: "person.2.slash.fill",
                    title: "Hide from Contact Sync",
                    subtitle: "People who have your number or email in their contacts will not see you as a suggested friend.",
                    color: .red,
                    isOn: $privacyManager.hideFromContactSync
                )
                
                Divider().padding(.leading, 52)
                
                privacyToggleRow(
                    icon: "magnifyingglass",
                    title: "Hide from Search",
                    subtitle: "Your profile will not appear when others search by username. Existing friends are not affected.",
                    color: .teal,
                    isOn: $privacyManager.hideFromSearch
                )
            }
        }
    }
    
    // MARK: - Activity Status
    
    private var activityStatusSection: some View {
        settingsSection(title: "Activity Status") {
            VStack(spacing: 0) {
                privacyToggleRow(
                    icon: "clock.fill",
                    title: "Hide Active Status",
                    subtitle: "Your last workout date and recent activity will not be visible to others.",
                    color: .mint,
                    isOn: $privacyManager.hideActiveStatus
                )
            }
        }
    }
    
    // MARK: - Info Footer
    
    private var infoFooter: some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle.fill")
                .font(.ds_labelMedium)
                .foregroundColor(.secondary)
            
            Text("Privacy settings are synced to your account and apply on all devices. Server-side enforcement ensures your data stays private even if someone uses a modified client.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.lg)
                .fill(Color.cardBackground.opacity(0.6))
        )
    }
    
    // MARK: - Reusable Components
    
    private func privacyToggleRow(
        icon: String,
        title: String,
        subtitle: String,
        color: Color,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 40, height: 40)
                
                Image(systemName: icon)
                    .font(.ds_heading3)
                    .foregroundColor(color)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer()
            
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(color)
        }
        .padding(Spacing.md)
        .accessibilityLabel(title)
        .accessibilityHint(subtitle)
    }
    
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

#Preview {
    NavigationStack {
        PrivacySettingsView()
    }
}
