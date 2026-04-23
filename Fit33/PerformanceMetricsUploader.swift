import Foundation
import UIKit

// MARK: - Performance Metrics Uploader
//
// Cluster I: drains the in-memory queue from `PerformanceSignposts`
// into the Supabase `performance_metrics` table on a timer.
//
// Characteristics:
//   • Throttled: uploads at most once every 30 seconds (configurable).
//   • Batched:   all queued rows ship in a single PostgREST insert.
//   • Auth-guarded: skips upload entirely if not authenticated — the
//     `performance_metrics` RLS policy accepts rows where
//     `user_id = auth.uid()` OR `user_id IS NULL`, but we only ship with
//     a known user so admin queries can bucket by device/user.
//   • Lossy under pressure: the `PerformanceSignposts` queue is capped
//     at 500 entries and drops oldest first. We don't retry forever.
//
// This uploader is started from `Fit33App.task` during the critical
// startup phase. It's a no-op until the migration `20260514_performance_metrics`
// is applied to the target environment.

@MainActor
final class PerformanceMetricsUploader {
    static let shared = PerformanceMetricsUploader()

    private var timer: Timer?
    private var isUploading = false
    private let uploadIntervalSeconds: TimeInterval = 30

    /// Set to `false` if the DB migration hasn't been applied yet to the
    /// current environment (we'll still buffer, just not ship).
    var isEnabled = true

    private init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(didEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
    }

    /// Start the periodic timer. Safe to call multiple times.
    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: uploadIntervalSeconds, repeats: true) { [weak self] _ in
            Task { await self?.drainAndUpload() }
        }
        AppLogger.debug("[PERF_METRICS] uploader started (interval=\(uploadIntervalSeconds)s)", category: .performance)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Called on backgrounding — drain once before suspend so we don't
    /// lose all in-memory metrics to app suspension.
    @objc private func didEnterBackground() {
        Task { await drainAndUpload() }
    }

    /// Single drain-and-upload pass. Safe to call from anywhere.
    func drainAndUpload() async {
        guard isEnabled, !isUploading else { return }
        guard SupabaseManager.shared.isAuthenticated,
              let userId = SupabaseManager.shared.currentUser?.id else {
            return
        }

        let batch = PerformanceSignposts.drainPendingMetrics()
        guard !batch.isEmpty else { return }

        isUploading = true
        defer { isUploading = false }

        // Build typed Encodable rows so PostgREST handles JSONB `extra`
        // + NULL-vs-missing correctly.
        let rows: [Upsert] = batch.map { metric in
            Upsert(
                user_id: userId,
                op: metric.op,
                elapsed_ms: metric.elapsedMs,
                started_at: Self.iso8601.string(from: metric.startedAt),
                endpoint: metric.endpoint,
                extra: metric.extra,
                app_version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
                os_version: UIDevice.current.systemVersion
            )
        }

        do {
            try await SupabaseManager.shared.supabaseClient
                .from("performance_metrics")
                .insert(rows)
                .execute()
            AppLogger.debug("[PERF_METRICS] uploaded \(rows.count) rows", category: .performance)
        } catch {
            // Classifier routes 404 (table missing / migration not applied)
            // + 401 + 42501 RLS at .warning so a missing migration doesn't
            // pollute bug_intelligence_fingerprints.
            _ = NetworkErrorClassifier.log(
                error,
                context: "[PERF_METRICS] upload failed",
                category: .performance,
                op: "perf_metrics.upload",
                endpoint: "performance_metrics",
                userId: userId
            )
        }
    }

    private struct Upsert: Encodable {
        let user_id: UUID
        let op: String
        let elapsed_ms: Int
        let started_at: String
        let endpoint: String?
        let extra: [String: String]?
        let app_version: String?
        let os_version: String?
    }

    private static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}
