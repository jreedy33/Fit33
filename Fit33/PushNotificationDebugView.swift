#if DEBUG
import SwiftUI
import Supabase

// MARK: - Push Notification Debug View

struct PushNotificationDebugView: View {
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var pushService = PushNotificationService.shared
    
    @State private var queueItems: [QueueItem] = []
    @State private var preferences: NotificationPrefs?
    @State private var serverTokenInfo: ServerTokenInfo?
    @State private var isLoadingQueue = false
    @State private var isLoadingPrefs = false
    @State private var isLoadingToken = false
    @State private var lastTestResult: String?
    @State private var deliveryLogs: [DeliveryLogEntry] = []
    @State private var diagnosticReport: DiagnosticReportUI?
    @State private var isRunningDiagnostics = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                diagnosticsSection
                tokenStatusSection
                sendTestSection
                queueStatusSection
                deliveryLogSection
                preferencesSection
            }
            .padding()
            .padding(.bottom, 80)
        }
        .task {
            await loadAll()
        }
    }
    
    // MARK: - Token Status
    
    private var tokenStatusSection: some View {
        debugSection(title: "Token Status", icon: "key.fill", color: .green) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                statusRow(label: "Registered", value: pushService.isRegistered ? "Yes" : "No",
                          color: pushService.isRegistered ? .green : .red)
                
                statusRow(label: "Device Token",
                          value: pushService.deviceToken.map { truncateToken($0) } ?? "None",
                          color: pushService.deviceToken != nil ? .green : .orange)
                
                statusRow(label: "APNs Environment",
                          value: UserDefaults.standard.string(forKey: "apns_environment") ?? "Unknown",
                          color: .blue)
                
                if let info = serverTokenInfo {
                    statusRow(label: "Server Valid", value: info.isValid ? "Yes" : "No",
                              color: info.isValid ? .green : .red)
                    statusRow(label: "Last Updated", value: info.updatedAt, color: .secondary)
                } else if isLoadingToken {
                    HStack {
                        ProgressView().scaleEffect(0.8)
                        Text("Loading server status...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Button {
                    Task { await pushService.recheckAndRegister() }
                } label: {
                    Label("Re-register Token", systemImage: "arrow.clockwise")
                        .font(.ds_labelSmall)
                        .foregroundColor(.blue)
                }
                .padding(.top, Spacing.xxs)
            }
        }
    }
    
    // MARK: - Send Test Push
    
    private var sendTestSection: some View {
        debugSection(title: "Send Test Push", icon: "paperplane.fill", color: .orange) {
            VStack(spacing: Spacing.sm) {
                Text("Tests the full pipeline: DB insert -> edge function -> APNs -> device")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                ForEach(TestNotificationType.allCases, id: \.rawValue) { type in
                    testButton(type: type)
                }
                
                if let result = lastTestResult {
                    Text(result)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, Spacing.xxs)
                }
            }
        }
    }
    
    // MARK: - Queue Status
    
    private var queueStatusSection: some View {
        debugSection(title: "Queue Status", icon: "tray.full.fill", color: .purple) {
            VStack(spacing: Spacing.sm) {
                HStack {
                    Button {
                        Task { await loadQueue() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                            .font(.ds_labelSmall)
                    }
                    
                    Spacer()
                    
                    Button {
                        PushNotificationService.shared.flushPushNotificationQueue(triggeredBy: "debug_manual")
                        lastTestResult = "Queue flush triggered"
                    } label: {
                        Label("Flush Now", systemImage: "bolt.fill")
                            .font(.ds_labelSmall)
                            .foregroundColor(.orange)
                    }
                }
                
                if isLoadingQueue {
                    ProgressView()
                } else if queueItems.isEmpty {
                    Text("No recent notifications in queue")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.md)
                } else {
                    ForEach(queueItems) { item in
                        queueItemRow(item)
                    }
                }
            }
        }
    }
    
    // MARK: - Delivery Log
    
    private var deliveryLogSection: some View {
        debugSection(title: "Delivery Log", icon: "list.bullet.rectangle.portrait", color: .cyan) {
            VStack(spacing: Spacing.xs) {
                HStack {
                    Button {
                        loadDeliveryLogs()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                            .font(.ds_labelSmall)
                    }
                    Spacer()
                    Text("\(deliveryLogs.count) events")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if deliveryLogs.isEmpty {
                    Text("No push notification log entries yet")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.md)
                } else {
                    ForEach(deliveryLogs) { entry in
                        logEntryRow(entry)
                    }
                }
            }
        }
    }
    
    // MARK: - Preferences
    
    private var preferencesSection: some View {
        debugSection(title: "Server Preferences", icon: "gearshape.fill", color: .indigo) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                if isLoadingPrefs {
                    ProgressView()
                } else if let prefs = preferences {
                    statusRow(label: "Master Enabled", value: prefs.masterEnabled ? "Yes" : "No",
                              color: prefs.masterEnabled ? .green : .red)
                    statusRow(label: "Quiet Hours", value: prefs.quietHoursEnabled ? "On" : "Off",
                              color: prefs.quietHoursEnabled ? .orange : .secondary)
                    if prefs.quietHoursEnabled {
                        statusRow(label: "Quiet Window",
                                  value: "\(prefs.quietHoursStart ?? "?") - \(prefs.quietHoursEnd ?? "?")",
                                  color: .secondary)
                    }
                    statusRow(label: "Timezone", value: prefs.timezone ?? "Not set", color: .secondary)
                    
                    if !prefs.disabledTypes.isEmpty {
                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            Text("Disabled Types:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            ForEach(prefs.disabledTypes, id: \.self) { type in
                                Text("  - \(type)")
                                    .font(.caption2)
                                    .foregroundColor(.red)
                            }
                        }
                    } else {
                        statusRow(label: "Disabled Types", value: "None", color: .green)
                    }
                } else {
                    Text("No preferences found (defaults apply)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Button {
                    Task { await loadPreferences() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .font(.ds_labelSmall)
                }
            }
        }
    }
    
    // MARK: - Server Diagnostics
    
    private var diagnosticsSection: some View {
        debugSection(title: "Server Diagnostics", icon: "stethoscope", color: .red) {
            VStack(spacing: Spacing.sm) {
                Button {
                    Task { await runServerDiagnostics() }
                } label: {
                    HStack {
                        if isRunningDiagnostics {
                            ProgressView().scaleEffect(0.8)
                        } else {
                            Image(systemName: "play.circle.fill")
                        }
                        Text("Run Full Diagnostics")
                            .font(.ds_labelSmall)
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.red))
                }
                .buttonStyle(.plain)
                .disabled(isRunningDiagnostics)
                
                if let report = diagnosticReport {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Queue Stats")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                        
                        statusRow(label: "Total", value: "\(report.totalQueue)", color: .primary)
                        statusRow(label: "Pending", value: "\(report.pendingCount)", color: report.pendingCount > 0 ? .orange : .green)
                        statusRow(label: "Processing", value: "\(report.processingCount)", color: report.processingCount > 0 ? .blue : .secondary)
                        statusRow(label: "Sent (24h)", value: "\(report.sentLast24h)", color: .green)
                        statusRow(label: "Failed (24h)", value: "\(report.failedLast24h)", color: report.failedLast24h > 0 ? .red : .green)
                        statusRow(label: "Tokens", value: "\(report.tokenCount) (\(report.validTokenCount) valid)", color: report.validTokenCount > 0 ? .green : .red)
                        
                        if !report.issues.isEmpty {
                            Text("Issues Found")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.red)
                                .padding(.top, Spacing.xxs)
                            
                            ForEach(report.issues, id: \.self) { issue in
                                HStack(alignment: .top, spacing: Spacing.xxs) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.system(size: 9))
                                        .foregroundColor(.red)
                                    Text(issue)
                                        .font(.caption2)
                                        .foregroundColor(.red)
                                }
                            }
                        } else {
                            HStack(spacing: Spacing.xxs) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(.green)
                                Text("No issues detected")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            }
                            .padding(.top, Spacing.xxs)
                        }
                    }
                }
            }
        }
    }
    
    private func runServerDiagnostics() async {
        isRunningDiagnostics = true
        defer { isRunningDiagnostics = false }
        
        guard let report = await PushNotificationService.shared.runDiagnostics() else {
            diagnosticReport = DiagnosticReportUI(
                totalQueue: 0, pendingCount: 0, processingCount: 0,
                sentLast24h: 0, failedLast24h: 0,
                tokenCount: 0, validTokenCount: 0,
                issues: ["Failed to fetch diagnostics from server"]
            )
            return
        }
        
        var issues: [String] = []
        
        let tokenCount = (report.tokens?.count) ?? 0
        let validTokenCount = report.tokens?.filter { ($0["is_valid"]?.value as? Bool) == true }.count ?? 0
        
        if tokenCount == 0 {
            issues.append("No device tokens registered on server")
        } else if validTokenCount == 0 {
            issues.append("All \(tokenCount) tokens are marked invalid")
        }
        
        let masterEnabled = report.preferences?["master_enabled"]?.value as? Bool ?? true
        if !masterEnabled {
            issues.append("Master notifications toggle is OFF on server")
        }
        
        let stats = report.queue_stats ?? [:]
        let processing = (stats["processing"]?.value as? Int) ?? 0
        if processing > 0 {
            issues.append("\(processing) notifications stuck in 'processing' state")
        }
        
        let failed24h = (stats["failed_last_24h"]?.value as? Int) ?? 0
        let sent24h = (stats["sent_last_24h"]?.value as? Int) ?? 0
        if failed24h > 0 && sent24h == 0 {
            issues.append("All \(failed24h) notifications in last 24h failed (0 sent)")
        }
        
        diagnosticReport = DiagnosticReportUI(
            totalQueue: (stats["total"]?.value as? Int) ?? 0,
            pendingCount: (stats["pending"]?.value as? Int) ?? 0,
            processingCount: processing,
            sentLast24h: sent24h,
            failedLast24h: failed24h,
            tokenCount: tokenCount,
            validTokenCount: validTokenCount,
            issues: issues
        )
    }
    
    // MARK: - Helpers
    
    private func loadAll() async {
        loadDeliveryLogs()
        async let q: () = loadQueue()
        async let p: () = loadPreferences()
        async let t: () = loadServerTokenInfo()
        _ = await (q, p, t)
    }
    
    private func loadQueue() async {
        guard let userId = SupabaseManager.shared.currentUser?.id else { return }
        isLoadingQueue = true
        defer { isLoadingQueue = false }
        
        do {
            let items: [QueueItem] = try await SupabaseManager.shared.supabaseClient
                .from("push_notification_queue")
                .select("id, notification_type, title, status, created_at, sent_at, error_message")
                .eq("recipient_user_id", value: userId.uuidString)
                .order("created_at", ascending: false)
                .limit(20)
                .execute()
                .value
            
            await MainActor.run { queueItems = items }
        } catch {
            AppLogger.error("[PUSH DEBUG] Failed to load queue: \(error)", category: .network)
        }
    }
    
    private func loadPreferences() async {
        guard let userId = SupabaseManager.shared.currentUser?.id else { return }
        isLoadingPrefs = true
        defer { isLoadingPrefs = false }
        
        do {
            let prefs: NotificationPrefs = try await SupabaseManager.shared.supabaseClient
                .from("user_notification_preferences")
                .select("master_enabled, disabled_types, quiet_hours_enabled, quiet_hours_start, quiet_hours_end, timezone")
                .eq("user_id", value: userId.uuidString)
                .single()
                .execute()
                .value
            
            await MainActor.run { preferences = prefs }
        } catch {
            AppLogger.debug("[PUSH DEBUG] No preferences row found (defaults apply)", category: .network)
        }
    }
    
    private func loadServerTokenInfo() async {
        guard let userId = SupabaseManager.shared.currentUser?.id else { return }
        isLoadingToken = true
        defer { isLoadingToken = false }
        
        do {
            let info: ServerTokenInfo = try await SupabaseManager.shared.supabaseClient
                .from("user_push_tokens")
                .select("is_valid, updated_at, apns_environment")
                .eq("user_id", value: userId.uuidString)
                .limit(1)
                .single()
                .execute()
                .value
            
            await MainActor.run { serverTokenInfo = info }
        } catch {
            AppLogger.debug("[PUSH DEBUG] No token row found on server", category: .network)
        }
    }
    
    private func loadDeliveryLogs() {
        let allLogs = SessionLogManager.shared.getRecentLogs()
        deliveryLogs = allLogs
            .filter { $0.category == .pushNotification }
            .suffix(30)
            .reversed()
            .map { DeliveryLogEntry(id: UUID(), timestamp: $0.timestamp, level: $0.level, message: $0.message) }
    }
    
    private func sendTestNotification(type: TestNotificationType) async {
        lastTestResult = "Sending \(type.displayName)..."
        
        do {
            struct TestParams: Encodable {
                let p_notification_type: String
                let p_title: String
                let p_body: String
            }
            
            let _: UUID = try await SupabaseManager.shared.supabaseClient
                .rpc("insert_test_push_notification", params: TestParams(
                    p_notification_type: type.rawValue,
                    p_title: type.testTitle,
                    p_body: type.testBody
                ))
                .execute()
                .value
            
            SessionLogManager.shared.log(.info, category: .pushNotification, message: "Test push queued: \(type.rawValue)")
            
            await PushNotificationService.shared._flushQueue(source: "debug_test_\(type.rawValue)")
            
            lastTestResult = "\(type.displayName) sent! Check your device."
            await loadQueue()
        } catch {
            lastTestResult = "Failed: \(error.localizedDescription)"
            SessionLogManager.shared.log(.error, category: .pushNotification, message: "Test push failed: \(type.rawValue)", metadata: ["error": error.localizedDescription])
        }
    }
    
    private func truncateToken(_ token: String) -> String {
        if token.count > 16 {
            return "\(token.prefix(8))...\(token.suffix(8))"
        }
        return token
    }
    
    // MARK: - UI Components
    
    private func debugSection<Content: View>(title: String, icon: String, color: Color, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.ds_labelMedium)
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
            }
            
            content()
                .padding(Spacing.md)
                .background(
                    RoundedRectangle(cornerRadius: CornerRadius.lg)
                        .fill(Color.cardBackground)
                        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.05), radius: 10, x: 0, y: 4)
                )
        }
    }
    
    private func statusRow(label: String, value: String, color: Color) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(color)
        }
    }
    
    private func testButton(type: TestNotificationType) -> some View {
        Button {
            Task { await sendTestNotification(type: type) }
        } label: {
            HStack(spacing: Spacing.sm) {
                Image(systemName: type.icon)
                    .font(.ds_labelMedium)
                    .foregroundColor(type.color)
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(type.displayName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    Text(type.rawValue)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "paperplane.fill")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(type.color.opacity(0.1))
            )
        }
        .buttonStyle(.plain)
    }
    
    private func queueItemRow(_ item: QueueItem) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            HStack {
                Text(item.notificationType)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                Spacer()
                queueStatusBadge(item.status)
            }
            
            if let title = item.title {
                Text(title)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            HStack {
                Text(formatDate(item.createdAt))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                if let sentAt = item.sentAt {
                    Text("-> \(formatDate(sentAt))")
                        .font(.caption2)
                        .foregroundColor(.green)
                }
                
                Spacer()
                
                if let error = item.errorMessage {
                    Text(error)
                        .font(.caption2)
                        .foregroundColor(.red)
                        .lineLimit(1)
                }
            }
        }
        .padding(Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.sm)
                .fill(Color(.systemGray6).opacity(0.5))
        )
    }
    
    private func queueStatusBadge(_ status: String) -> some View {
        Text(status.uppercased())
            .font(.system(size: 9, weight: .bold))
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule().fill(statusColor(status))
            )
    }
    
    private func statusColor(_ status: String) -> Color {
        switch status {
        case "sent": return .green
        case "pending": return .orange
        case "processing": return .blue
        case "failed": return .red
        default: return .gray
        }
    }
    
    private func logEntryRow(_ entry: DeliveryLogEntry) -> some View {
        HStack(alignment: .top, spacing: Spacing.xs) {
            Circle()
                .fill(logLevelColor(entry.level))
                .frame(width: 6, height: 6)
                .padding(.top, 5)
            
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.message)
                    .font(.caption2)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                Text(formatDate(entry.timestamp))
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private func logLevelColor(_ level: LogLevel) -> Color {
        switch level {
        case .debug: return .gray
        case .info: return .blue
        case .warning: return .orange
        case .error: return .red
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: date)
    }
    
    private func formatDate(_ iso: String) -> String {
        let f = ISO8601DateFormatter()
        if let date = f.date(from: iso) {
            return formatDate(date)
        }
        return iso.suffix(8).description
    }
}

// MARK: - Models

private enum TestNotificationType: String, CaseIterable {
    case friendRequest = "friend_request"
    case friendAccepted = "friend_accepted"
    case challengeInvite = "challenge_invite"
    case challengeAccepted = "challenge_accepted"
    case challengeProgress = "challenge_progress"
    case challengeCompleted = "challenge_completed"
    
    var displayName: String {
        switch self {
        case .friendRequest: return "Friend Request"
        case .friendAccepted: return "Friend Accepted"
        case .challengeInvite: return "Challenge Invite"
        case .challengeAccepted: return "Challenge Accepted"
        case .challengeProgress: return "Challenge Progress"
        case .challengeCompleted: return "Challenge Completed"
        }
    }
    
    var icon: String {
        switch self {
        case .friendRequest: return "person.badge.plus"
        case .friendAccepted: return "person.2.fill"
        case .challengeInvite: return "envelope.fill"
        case .challengeAccepted: return "checkmark.circle.fill"
        case .challengeProgress: return "flame.fill"
        case .challengeCompleted: return "trophy.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .friendRequest: return .blue
        case .friendAccepted: return .green
        case .challengeInvite: return .purple
        case .challengeAccepted: return .cyan
        case .challengeProgress: return .orange
        case .challengeCompleted: return .yellow
        }
    }
    
    var testTitle: String {
        switch self {
        case .friendRequest: return "New Friend Request"
        case .friendAccepted: return "Friend Request Accepted"
        case .challengeInvite: return "Challenge Invite"
        case .challengeAccepted: return "Challenge Accepted"
        case .challengeProgress: return "Challenge Update"
        case .challengeCompleted: return "Challenge Complete!"
        }
    }
    
    var testBody: String {
        switch self {
        case .friendRequest: return "Test User wants to be your friend!"
        case .friendAccepted: return "Test User accepted your friend request!"
        case .challengeInvite: return "Test User challenged you to a 7-Day Steps Challenge!"
        case .challengeAccepted: return "Test User accepted your challenge! Game on!"
        case .challengeProgress: return "Test User just logged 5,000 steps. You're falling behind!"
        case .challengeCompleted: return "The Steps Challenge has ended. Check your results!"
        }
    }
}

private struct QueueItem: Decodable, Identifiable {
    let id: UUID
    let notificationType: String
    let title: String?
    let status: String
    let createdAt: String
    let sentAt: String?
    let errorMessage: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case notificationType = "notification_type"
        case title
        case status
        case createdAt = "created_at"
        case sentAt = "sent_at"
        case errorMessage = "error_message"
    }
}

private struct NotificationPrefs: Decodable {
    let masterEnabled: Bool
    let disabledTypes: [String]
    let quietHoursEnabled: Bool
    let quietHoursStart: String?
    let quietHoursEnd: String?
    let timezone: String?
    
    enum CodingKeys: String, CodingKey {
        case masterEnabled = "master_enabled"
        case disabledTypes = "disabled_types"
        case quietHoursEnabled = "quiet_hours_enabled"
        case quietHoursStart = "quiet_hours_start"
        case quietHoursEnd = "quiet_hours_end"
        case timezone
    }
}

private struct ServerTokenInfo: Decodable {
    let isValid: Bool
    let updatedAt: String
    let apnsEnvironment: String
    
    enum CodingKeys: String, CodingKey {
        case isValid = "is_valid"
        case updatedAt = "updated_at"
        case apnsEnvironment = "apns_environment"
    }
}

private struct DeliveryLogEntry: Identifiable {
    let id: UUID
    let timestamp: Date
    let level: LogLevel
    let message: String
}

private struct DiagnosticReportUI {
    let totalQueue: Int
    let pendingCount: Int
    let processingCount: Int
    let sentLast24h: Int
    let failedLast24h: Int
    let tokenCount: Int
    let validTokenCount: Int
    let issues: [String]
}

#endif
