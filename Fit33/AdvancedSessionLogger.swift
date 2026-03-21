import Foundation
import UIKit
import Supabase

/// Deep session logger for developer dogfooding.
/// Activated per-user via CMS toggle in `dev_logging_users` table.
/// Captures every screen view, tap, API call, error, and state change,
/// then batch-uploads to Supabase every 5 seconds.
@MainActor
final class AdvancedSessionLogger: ObservableObject {
    static let shared = AdvancedSessionLogger()
    
    /// Thread-safe flag readable from any context (avoids actor isolation for hot path checks)
    nonisolated(unsafe) static var isActive = false
    
    @Published private(set) var isEnabled = false
    @Published private(set) var entryCount = 0
    
    private var sessionId = ""
    private var batchIndex = 0
    private var pendingEntries: [[String: Any]] = []
    private var flushTimer: Timer?
    private var memoryTimer: Timer?
    private let maxEntriesPerBatch = 200
    private var deviceInfo: [String: Any] = [:]
    
    private init() {}
    
    // MARK: - Activation
    
    /// Called after login. Checks Supabase to see if this user has advanced logging enabled.
    func checkIfEnabled() async {
        guard SupabaseManager.shared.isAuthenticated else { return }
        
        do {
            let enabled: Bool = try await SupabaseManager.shared.supabaseClient
                .rpc("is_dev_logging_enabled")
                .execute()
                .value
            
            if enabled {
                activate()
            }
        } catch {
            AppLogger.debug("Dev logging check failed (expected if not enrolled): \(error.localizedDescription)", category: .general)
        }
    }
    
    private func activate() {
        guard !isEnabled else { return }
        isEnabled = true
        Self.isActive = true
        sessionId = "\(UUID().uuidString.prefix(8))-\(Int(Date().timeIntervalSince1970))"
        batchIndex = 0
        pendingEntries = []
        
        deviceInfo = [
            "model": UIDevice.current.model,
            "name": UIDevice.current.name,
            "systemVersion": UIDevice.current.systemVersion,
            "appVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            "buildNumber": Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown",
            "screenScale": UIScreen.main.scale,
            "screenBounds": "\(Int(UIScreen.main.bounds.width))x\(Int(UIScreen.main.bounds.height))"
        ]
        
        flushTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.flush()
            }
        }
        
        memoryTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.logMemorySnapshot()
            }
        }
        
        log(type: "system", detail: "Advanced logging activated", screen: "App")
        AppLogger.info("Advanced session logging ACTIVE for this user (session: \(sessionId))", category: .general)
    }
    
    func deactivate() {
        guard isEnabled else { return }
        Self.isActive = false
        log(type: "system", detail: "Session ending", screen: "App")
        
        Task { await flush() }
        
        flushTimer?.invalidate()
        flushTimer = nil
        memoryTimer?.invalidate()
        memoryTimer = nil
        isEnabled = false
    }
    
    // MARK: - Log Entry
    
    func log(
        type: String,
        detail: String,
        screen: String? = nil,
        apiEndpoint: String? = nil,
        apiStatus: Int? = nil,
        durationMs: Int? = nil,
        error: String? = nil,
        extra: [String: Any]? = nil
    ) {
        guard isEnabled else { return }
        
        var entry: [String: Any] = [
            "ts": Int(Date().timeIntervalSince1970 * 1000),
            "type": type,
            "detail": detail
        ]
        
        if let screen = screen { entry["screen"] = screen }
        if let apiEndpoint = apiEndpoint { entry["api_endpoint"] = apiEndpoint }
        if let apiStatus = apiStatus { entry["api_status"] = apiStatus }
        if let durationMs = durationMs { entry["duration_ms"] = durationMs }
        if let error = error { entry["error"] = error }
        
        let memoryMB = Int(ProcessInfo.processInfo.physicalMemory > 0
            ? Double(os_proc_available_memory()) / 1_048_576
            : 0)
        entry["memory_available_mb"] = memoryMB
        
        if let extra = extra {
            for (key, value) in extra {
                entry["x_\(key)"] = "\(value)"
            }
        }
        
        pendingEntries.append(entry)
        entryCount += 1
        
        if pendingEntries.count >= maxEntriesPerBatch {
            Task { await flush() }
        }
    }
    
    // MARK: - Convenience Methods
    
    func logScreenView(_ screenName: String) {
        log(type: "screen", detail: screenName, screen: screenName)
    }
    
    func logTap(_ description: String, screen: String? = nil) {
        log(type: "tap", detail: description, screen: screen)
    }
    
    func logAPICall(endpoint: String, status: Int, durationMs: Int, screen: String? = nil) {
        log(type: "api", detail: "\(status) \(endpoint)", screen: screen,
            apiEndpoint: endpoint, apiStatus: status, durationMs: durationMs)
    }
    
    func logError(_ message: String, screen: String? = nil) {
        log(type: "error", detail: message, screen: screen, error: message)
    }
    
    func logStateChange(_ description: String, screen: String? = nil) {
        log(type: "state", detail: description, screen: screen)
    }
    
    func logPerformance(_ operation: String, durationMs: Int, screen: String? = nil) {
        log(type: "perf", detail: operation, screen: screen, durationMs: durationMs)
    }
    
    // MARK: - Memory Snapshot
    
    private func logMemorySnapshot() {
        let availableMB = Double(os_proc_available_memory()) / 1_048_576
        log(type: "perf", detail: "memory_snapshot", extra: [
            "available_mb": Int(availableMB),
            "thermal_state": ProcessInfo.processInfo.thermalState.rawValue
        ])
    }
    
    // MARK: - Batch Flush
    
    private func flush() async {
        guard !pendingEntries.isEmpty, SupabaseManager.shared.isAuthenticated else { return }
        guard let userId = SupabaseManager.shared.currentUser?.id else { return }
        
        let batch = pendingEntries
        pendingEntries = []
        let currentBatchIndex = batchIndex
        batchIndex += 1
        
        do {
            let entriesData = try JSONSerialization.data(withJSONObject: batch)
            let entriesString = String(data: entriesData, encoding: .utf8) ?? "[]"
            
            let deviceData = try JSONSerialization.data(withJSONObject: deviceInfo)
            let deviceString = String(data: deviceData, encoding: .utf8) ?? "{}"
            
            struct DevLogInsert: Codable {
                let user_id: String
                let session_id: String
                let batch_index: Int
                let entries: String
                let device_info: String
            }
            
            // Use raw SQL via rpc or direct insert
            try await SupabaseManager.shared.supabaseClient
                .from("dev_session_logs")
                .insert([
                    "user_id": userId.uuidString,
                    "session_id": sessionId,
                    "batch_index": "\(currentBatchIndex)",
                    "entries": entriesString,
                    "device_info": deviceString
                ] as [String: String])
                .execute()
            
        } catch {
            AppLogger.debug("Dev log flush failed: \(error.localizedDescription)", category: .network)
            pendingEntries.insert(contentsOf: batch, at: 0)
            if pendingEntries.count > maxEntriesPerBatch * 3 {
                pendingEntries = Array(pendingEntries.suffix(maxEntriesPerBatch * 2))
            }
        }
    }
}
