//
//  CloudSyncRetryQueue.swift
//  Fit33
//
//  Sprint 2 Q2-34 — Persistent retry queue for cloud writes that fail at save
//  time (e.g. finishWorkout → saveWorkoutToCloud throws because the network
//  blipped). Enqueue entries survive app restarts; a foreground drain re-fires
//  them with exponential backoff until they succeed or exceed `maxAttempts`.
//
//  Scope: keeps the queue file-backed (JSON in Application Support) to avoid
//  touching the Core Data model. The only payload we currently queue is the
//  Core Data object URI of a completed Workout — the drain worker loads the
//  Workout from the viewContext and re-runs `SupabaseManager.saveWorkoutToCloud`.
//

import Foundation
import CoreData
import Combine

@MainActor
final class CloudSyncRetryQueue: ObservableObject {
    static let shared = CloudSyncRetryQueue()

    /// Number of entries currently waiting to be flushed. Surfaced in the
    /// Dashboard "offline sync" chip.
    @Published private(set) var pendingCount: Int = 0

    /// Exposed so UI can render a "Syncing N…" state when we're actively
    /// draining rather than just idling with a backlog.
    @Published private(set) var isDraining: Bool = false

    enum Kind: String, Codable {
        case workoutCloudSync
        /// PR-22 residual (2026-07-30): failed `record_cardio_workout` RPC
        /// calls. The payload is a JSON-encoded `CardioWorkoutData`; the RPC
        /// is idempotent on the stable external_id derived from
        /// (started_at, completed_at, activity_type), so retries are safe.
        case cardioCloudSync
    }

    struct Entry: Codable, Identifiable {
        let id: UUID
        let kind: Kind
        /// Core Data NSManagedObjectID URI for workoutCloudSync entries.
        /// Empty string for cardioCloudSync entries.
        let objectURI: String
        /// JSON-encoded `CardioWorkoutData` for cardioCloudSync entries.
        /// Optional so queue files written before 2026-07-30 still decode.
        var payloadJSON: String?
        /// Cardio entries only (2026-07-31): `false`/`nil` means the
        /// XP/streak/league/quest fanout (`UserManager.completeCardioWorkout`
        /// + quest verify) never ran because the save failed — the drain
        /// worker owes it after the first successful retry. Optional so
        /// older queue files still decode.
        var fanoutCompleted: Bool?
        var attempts: Int
        var nextAttemptAt: Date
        let enqueuedAt: Date
    }

    private let fileURL: URL
    private let maxAttempts: Int = 6
    private var entries: [Entry] = []
    private var drainTask: Task<Void, Never>?

    private init() {
        let fm = FileManager.default
        let base = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        self.fileURL = base.appendingPathComponent("cloud_sync_retry_queue.json")
        load()
    }

    // MARK: - Public API

    /// Enqueue a workout cloud-sync retry. Safe to call from the catch block
    /// of `saveWorkoutToCloud`.
    func enqueueWorkoutCloudSync(_ workout: Workout) {
        let uri = workout.objectID.uriRepresentation().absoluteString
        guard !entries.contains(where: { $0.kind == .workoutCloudSync && $0.objectURI == uri }) else { return }
        let entry = Entry(
            id: UUID(),
            kind: .workoutCloudSync,
            objectURI: uri,
            payloadJSON: nil,
            fanoutCompleted: nil,
            attempts: 0,
            nextAttemptAt: Date(),
            enqueuedAt: Date()
        )
        entries.append(entry)
        persist()
        pendingCount = entries.count
        AppLogger.warning("Cloud sync queued for retry (\(entries.count) pending)", category: .network)
    }

    /// Enqueue a cardio cloud-sync retry (PR-22 residual). Safe to call from
    /// the catch block of any `saveCardioWorkout` caller — the RPC's
    /// external_id idempotency means a retry of the same payload returns the
    /// original row instead of duplicating it.
    func enqueueCardioCloudSync(_ payload: CardioWorkoutData) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(payload),
              let json = String(data: data, encoding: .utf8) else {
            AppLogger.error("Failed to encode cardio payload for retry queue", category: .network)
            return
        }
        guard !entries.contains(where: { $0.kind == .cardioCloudSync && $0.payloadJSON == json }) else { return }
        let entry = Entry(
            id: UUID(),
            kind: .cardioCloudSync,
            objectURI: "",
            payloadJSON: json,
            // Both cardio enqueue sites (indoor completion + outdoor recap)
            // only enqueue when the save failed, i.e. BEFORE any fanout ran.
            fanoutCompleted: false,
            attempts: 0,
            nextAttemptAt: Date(),
            enqueuedAt: Date()
        )
        entries.append(entry)
        persist()
        pendingCount = entries.count
        AppLogger.warning("Cardio cloud sync queued for retry (\(entries.count) pending)", category: .network)
    }

    /// Cancel any pending workout-cloud-sync entry for the given workout
    /// id. Called from `WorkoutManager.deleteCompletedWorkout` so the queue
    /// doesn't try to re-create the row we just deleted from Supabase.
    /// Matches by Core Data object URI containing the workout id (the
    /// `Workout` is already gone by the time the drain fires, but the URI
    /// is opaque, so we resolve via the on-disk entries directly).
    func cancelWorkoutCloudSync(workoutId: UUID) {
        let ctx = PersistenceController.shared.container.viewContext
        let beforeCount = entries.count
        entries.removeAll { entry in
            guard entry.kind == .workoutCloudSync,
                  let url = URL(string: entry.objectURI),
                  let objectId = ctx.persistentStoreCoordinator?.managedObjectID(forURIRepresentation: url),
                  let workout = try? ctx.existingObject(with: objectId) as? Workout else {
                return false
            }
            return workout.id == workoutId
        }
        if entries.count != beforeCount {
            persist()
            pendingCount = entries.count
            AppLogger.info("Cancelled \(beforeCount - entries.count) queued cloud sync entry for deleted workout", category: .network)
        }
    }

    /// Drains anything whose `nextAttemptAt ≤ now`. Called on:
    ///   • scenePhase == .active
    ///   • after `recoverSessionIfNeeded` / successful auth restore
    func drainIfDue() {
        guard drainTask == nil else { return }
        guard !entries.isEmpty else { return }
        drainTask = Task { [weak self] in
            await self?.runDrain()
            await MainActor.run { self?.drainTask = nil }
        }
    }

    // MARK: - Drain worker

    private func runDrain() async {
        isDraining = true
        defer { isDraining = false }

        guard SupabaseManager.shared.isAuthenticated else {
            AppLogger.debug("Cloud sync drain skipped — not authenticated", category: .network)
            return
        }

        let due = entries.filter { $0.nextAttemptAt <= Date() }
        guard !due.isEmpty else { return }

        AppLogger.info("Draining \(due.count) queued cloud writes…", category: .network)

        for entry in due {
            let succeeded = await attempt(entry)
            if succeeded {
                remove(id: entry.id)
            } else {
                bumpAttempt(id: entry.id)
            }
        }

        pendingCount = entries.count
        if pendingCount == 0 {
            AppLogger.info("Cloud sync retry queue empty", category: .network)
        }
    }

    private func attempt(_ entry: Entry) async -> Bool {
        switch entry.kind {
        case .workoutCloudSync:
            return await attemptWorkoutSync(uri: entry.objectURI)
        case .cardioCloudSync:
            return await attemptCardioSync(entry)
        }
    }

    private func attemptCardioSync(_ entry: Entry) async -> Bool {
        guard let json = entry.payloadJSON, let data = json.data(using: .utf8) else {
            AppLogger.warning("Dropping queued cardio sync — payload missing", category: .network)
            return true // drop: nothing we can do.
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let payload = try? decoder.decode(CardioWorkoutData.self, from: data) else {
            AppLogger.warning("Dropping queued cardio sync — payload undecodable", category: .network)
            return true
        }
        do {
            let workoutId = try await SupabaseManager.shared.saveCardioWorkout(payload)
            AppLogger.info("✅ Retried cardio cloud sync (\(payload.activityType))", category: .network)
            // 2026-07-31: cardio flows are "fanout after durable save" —
            // entries enqueued from a failed save still owe the
            // XP/streak/league/quest credit. Run it exactly once per entry:
            // mark the flag (persisted) BEFORE the fanout so a crash
            // mid-fanout can't double-award on the next drain.
            if entry.fanoutCompleted != true, let id = workoutId {
                markCardioFanoutCompleted(id: entry.id)
                UserManager.shared.completeCardioWorkout(
                    workoutId: id,
                    activityType: payload.activityType,
                    durationSeconds: payload.durationSeconds,
                    distanceMeters: payload.distanceMeters,
                    caloriesBurned: Int(payload.caloriesBurned),
                    averageHeartRate: payload.averageHeartRate,
                    savedViaRPC: true,
                    goalAchieved: payload.goalAchieved
                )
                await DailyQuestService.shared.onCardioActivityImported(source: "fit33")
            }
            return true
        } catch {
            AppLogger.error("Retry cardio cloud sync failed: \(error.localizedDescription)", category: .network)
            return false
        }
    }

    private func markCardioFanoutCompleted(id: UUID) {
        guard let idx = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[idx].fanoutCompleted = true
        persist()
    }

    private func attemptWorkoutSync(uri: String) async -> Bool {
        let ctx = PersistenceController.shared.container.viewContext
        guard let url = URL(string: uri),
              let objectId = ctx.persistentStoreCoordinator?.managedObjectID(forURIRepresentation: url) else {
            AppLogger.warning("Dropping queued cloud write — object URI no longer resolvable", category: .network)
            return true // drop: nothing we can do.
        }
        guard let workout = try? ctx.existingObject(with: objectId) as? Workout else {
            AppLogger.warning("Dropping queued cloud write — Workout was deleted", category: .network)
            return true
        }
        do {
            try await SupabaseManager.shared.saveWorkoutToCloud(workout: workout)
            AppLogger.info("✅ Retried workout cloud sync (\(uri.suffix(12)))", category: .network)
            return true
        } catch {
            AppLogger.error("Retry workout cloud sync failed: \(error.localizedDescription)", category: .network)
            return false
        }
    }

    // MARK: - Mutation helpers

    private func remove(id: UUID) {
        entries.removeAll { $0.id == id }
        persist()
    }

    private func bumpAttempt(id: UUID) {
        guard let idx = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[idx].attempts += 1
        if entries[idx].attempts >= maxAttempts {
            AppLogger.error("Dropping cloud write after \(maxAttempts) attempts (id=\(id.uuidString.prefix(8)))", category: .network)
            entries.remove(at: idx)
            persist()
            return
        }
        // Exponential backoff capped at 30 min: 30s, 1m, 2m, 4m, 8m, 16m, 30m.
        let delaySeconds: TimeInterval = min(30 * 60, pow(2.0, Double(entries[idx].attempts)) * 15)
        entries[idx].nextAttemptAt = Date().addingTimeInterval(delaySeconds)
        persist()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else {
            pendingCount = 0
            return
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decoded = try? decoder.decode([Entry].self, from: data) {
            entries = decoded
            pendingCount = decoded.count
        }
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
