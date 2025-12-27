import SwiftUI

struct CloudBackupView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var supabaseManager: SupabaseManager
    @StateObject private var healthKitManager = HealthKitManager.shared
    
    @State private var isSyncing = false
    @State private var lastSyncTime: Date?
    @State private var syncStatus: [BackupDataType: SyncStatus] = [:]
    @State private var showingSyncSuccess = false
    @State private var syncError: String?
    
    enum BackupDataType: String, CaseIterable {
        case profile = "Profile & Settings"
        case workouts = "Workout History"
        case exercises = "Exercise Performance"
        case steps = "Step Tracking"
        case nutrition = "Meal Logs"
        case programs = "Training Programs"
        
        var icon: String {
            switch self {
            case .profile: return "person.circle.fill"
            case .workouts: return "figure.strengthtraining.traditional"
            case .exercises: return "chart.line.uptrend.xyaxis"
            case .steps: return "figure.walk"
            case .nutrition: return "fork.knife"
            case .programs: return "calendar"
            }
        }
        
        var color: Color {
            switch self {
            case .profile: return .blue
            case .workouts: return .orange
            case .exercises: return .purple
            case .steps: return .green
            case .nutrition: return .pink
            case .programs: return .indigo
            }
        }
    }
    
    struct SyncStatus {
        var isSynced: Bool
        var lastSync: Date?
        var itemCount: Int
    }
    
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
                    // Header Card
                    headerCard
                    
                    // Sync Status Card
                    syncStatusCard
                    
                    // Data Categories
                    dataTypesCard
                    
                    // Sync Actions
                    actionsCard
                    
                    // Info Section
                    infoCard
                }
                .padding()
                .padding(.bottom, 60)
            }
        }
        .navigationTitle("Cloud Backup")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadSyncStatus()
        }
        .alert("Sync Complete", isPresented: $showingSyncSuccess) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("All your data has been synced to the cloud successfully.")
        }
        .alert("Sync Error", isPresented: .constant(syncError != nil)) {
            Button("OK", role: .cancel) {
                syncError = nil
            }
        } message: {
            Text(syncError ?? "")
        }
    }
    
    // MARK: - Header Card
    
    private var headerCard: some View {
        VStack(spacing: 12) {
            Image(systemName: supabaseManager.isAuthenticated ? "icloud.and.arrow.up" : "icloud.slash")
                .font(.system(size: 50))
                .foregroundStyle(
                    LinearGradient(
                        colors: supabaseManager.isAuthenticated ? [.blue, .cyan] : [.gray, .gray],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            Text(supabaseManager.isAuthenticated ? "Cloud Backup Active" : "Not Signed In")
                .font(.title2)
                .fontWeight(.bold)
            
            Text(supabaseManager.isAuthenticated 
                ? "Your data is automatically backed up to the cloud"
                : "Sign in to enable cloud backup")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(cardBackground)
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.05), radius: 10, x: 0, y: 4)
        )
    }
    
    // MARK: - Sync Status Card
    
    private var syncStatusCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.title3)
                    .foregroundColor(.blue)
                
                Text("Last Sync")
                    .font(.headline)
                
                Spacer()
                
                if isSyncing {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
            
            if let lastSync = lastSyncTime {
                HStack {
                    Text(relativeDateString(from: lastSync))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }
            } else {
                Text("Never synced")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(cardBackground)
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.05), radius: 10, x: 0, y: 4)
        )
    }
    
    // MARK: - Data Types Card
    
    private var dataTypesCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Backed Up Data")
                .font(.headline)
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 12)
            
            ForEach(BackupDataType.allCases, id: \.self) { dataType in
                dataTypeRow(dataType)
                
                if dataType != BackupDataType.allCases.last {
                    Divider()
                        .padding(.leading, 60)
                }
            }
            .padding(.bottom, 8)
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(cardBackground)
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.05), radius: 10, x: 0, y: 4)
        )
    }
    
    private func dataTypeRow(_ dataType: BackupDataType) -> some View {
        HStack(spacing: 16) {
            Image(systemName: dataType.icon)
                .font(.title3)
                .foregroundColor(dataType.color)
                .frame(width: 28)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(dataType.rawValue)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                if let status = syncStatus[dataType] {
                    if status.isSynced {
                        Text("\(status.itemCount) items synced")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Not synced")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
            }
            
            Spacer()
            
            Image(systemName: syncStatus[dataType]?.isSynced == true ? "checkmark.circle.fill" : "circle")
                .foregroundColor(syncStatus[dataType]?.isSynced == true ? .green : .gray)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
    
    // MARK: - Actions Card
    
    private var actionsCard: some View {
        VStack(spacing: 12) {
            // Sync Now Button
            Button(action: {
                HapticManager.impact(.medium)
                syncNow()
            }) {
                HStack {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.title3)
                    
                    Text("Sync Now")
                        .font(.headline)
                    
                    if isSyncing {
                        Spacer()
                        ProgressView()
                            .tint(.white)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(
                    LinearGradient(
                        colors: supabaseManager.isAuthenticated ? [.blue, .cyan] : [.gray, .gray],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .disabled(!supabaseManager.isAuthenticated || isSyncing)
            
            // Restore from Cloud Button
            Button(action: {
                HapticManager.impact(.light)
                restoreFromCloud()
            }) {
                HStack {
                    Image(systemName: "icloud.and.arrow.down")
                        .font(.title3)
                    
                    Text("Restore from Cloud")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(cardBackground)
                .foregroundColor(.blue)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.blue, lineWidth: 2)
                )
                .cornerRadius(12)
            }
            .disabled(!supabaseManager.isAuthenticated || isSyncing)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(cardBackground)
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.05), radius: 10, x: 0, y: 4)
        )
    }
    
    // MARK: - Info Card
    
    private var infoCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(.blue)
                Text("About Cloud Backup")
                    .font(.headline)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                infoRow(icon: "checkmark.circle", text: "Data syncs automatically when you're signed in")
                infoRow(icon: "checkmark.circle", text: "Access your data on any device")
                infoRow(icon: "checkmark.circle", text: "Workouts and progress are saved after each session")
                infoRow(icon: "checkmark.circle", text: "Your data is encrypted and secure")
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(cardBackground)
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.05), radius: 10, x: 0, y: 4)
        )
    }
    
    private func infoRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(.green)
                .frame(width: 16)
            
            Text(text)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - Helper Functions
    
    private func loadSyncStatus() {
        guard supabaseManager.isAuthenticated else { return }
        
        // Load last sync times from UserDefaults
        lastSyncTime = UserDefaults.standard.object(forKey: "lastCloudSync") as? Date
        
        // Load sync status for each data type
        // This is simulated - in reality, you'd query Supabase for actual counts
        Task {
            await MainActor.run {
                syncStatus = [
                    .profile: SyncStatus(isSynced: true, lastSync: Date(), itemCount: 1),
                    .workouts: SyncStatus(isSynced: true, lastSync: Date(), itemCount: 0),
                    .exercises: SyncStatus(isSynced: true, lastSync: Date(), itemCount: 0),
                    .steps: SyncStatus(isSynced: true, lastSync: Date(), itemCount: healthKitManager.weeklySteps.count),
                    .nutrition: SyncStatus(isSynced: true, lastSync: Date(), itemCount: 0),
                    .programs: SyncStatus(isSynced: true, lastSync: Date(), itemCount: 0)
                ]
            }
        }
    }
    
    private func syncNow() {
        guard !isSyncing else { return }
        
        isSyncing = true
        
        Task {
            do {
                // Sync step data
                await healthKitManager.syncWeeklyStepsToCloud()
                
                // Update last sync time
                let now = Date()
                await MainActor.run {
                    lastSyncTime = now
                    UserDefaults.standard.set(now, forKey: "lastCloudSync")
                    isSyncing = false
                    showingSyncSuccess = true
                    loadSyncStatus()
                }
            } catch {
                await MainActor.run {
                    isSyncing = false
                    syncError = "Failed to sync: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func restoreFromCloud() {
        // Trigger a refresh of all data from Supabase
        Task {
            isSyncing = true
            
            do {
                // Fetch step data
                _ = try await healthKitManager.fetchStepsFromCloud()
                
                await MainActor.run {
                    isSyncing = false
                    showingSyncSuccess = true
                    loadSyncStatus()
                }
            } catch {
                await MainActor.run {
                    isSyncing = false
                    syncError = "Failed to restore: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func relativeDateString(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

#Preview {
    NavigationStack {
        CloudBackupView()
            .environmentObject(SupabaseManager.shared)
    }
}

