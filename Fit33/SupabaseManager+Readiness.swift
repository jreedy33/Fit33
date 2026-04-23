//
//  SupabaseManager+Readiness.swift
//  Fit33
//
//  Wearable Personalization Platform — Phase 0 (Foundation)
//
//  Data I/O for the `daily_readiness_history` table written by the
//  Phase-0 migration `supabase/20260506_daily_readiness_history.sql`.
//  Split into its own extension so the main `SupabaseManager.swift`
//  stays under its (now ~4500 line) diff ceiling and the readiness
//  surface stays greppable.
//

import Foundation

extension SupabaseManager {

    // MARK: - Upsert today's snapshot

    /// Upsert the currently-computed readiness snapshot for the signed-
    /// in user. Converts `DailyReadinessSnapshot` → `DailyReadinessRow`
    /// and hits `daily_readiness_history` with `onConflict:
    /// "user_id,date"` so day-of writes coexist with the nightly
    /// server rollup.
    ///
    /// Guards (per DATA_BACKEND_AGENT.md #26): every INSERT /
    /// UPSERT MUST check `isAuthenticated` first — `currentUser?.id`
    /// is insufficient (a user object can persist in Core Data with
    /// an expired Supabase session).
    func upsertReadinessSnapshot(_ snapshot: DailyReadinessSnapshot) async {
        guard isAuthenticated, let userId = currentUser?.id else {
            AppLogger.debug(
                "[Readiness] Skipping upsert — not authenticated",
                category: .health
            )
            return
        }

        let row = DailyReadinessRow(userId: userId, snapshot: snapshot)

        do {
            try await client
                .from("daily_readiness_history")
                .upsert(row, onConflict: "user_id,date")
                .execute()
            AppLogger.debug(
                "[Readiness] Upserted snapshot score=\(snapshot.score) band=\(snapshot.band.rawValue)",
                category: .health
            )
        } catch {
            NetworkErrorClassifier.log(
                error,
                context: "Failed to upsert readiness snapshot",
                category: .health,
                transientLevel: .debug
            )
        }
    }

    // MARK: - Fetch history

    /// Fetch the user's last `daysBack` readiness snapshots, newest-
    /// first. Uses the base table (not `v_user_readiness_30d`) so
    /// callers can request any window; the view is reserved for the
    /// Phase-2 dashboard chart which always wants 30 days.
    func fetchReadinessHistory(daysBack: Int = 30) async -> [DailyReadinessSnapshot] {
        guard isAuthenticated, let userId = currentUser?.id else {
            return []
        }

        let calendar = Calendar.current
        let since: Date = calendar.date(
            byAdding: .day,
            value: -max(0, daysBack),
            to: Date()
        ) ?? Date()

        let sinceStr: String = {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            f.timeZone = TimeZone.current
            f.locale = Locale(identifier: "en_US_POSIX")
            return f.string(from: since)
        }()

        do {
            let rows: [DailyReadinessRow] = try await client
                .from("daily_readiness_history")
                .select()
                .eq("user_id", value: userId.uuidString)
                .gte("date", value: sinceStr)
                .order("date", ascending: false)
                .limit(daysBack + 1)
                .execute()
                .value
            return rows.compactMap { $0.toSnapshot() }
        } catch {
            NetworkErrorClassifier.log(
                error,
                context: "Failed to fetch readiness history",
                category: .health,
                transientLevel: .debug
            )
            return []
        }
    }
}
