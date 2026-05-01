import Foundation
import Supabase

// =============================================================================
// PushEventReporter — iOS side of the push delivery funnel
// (Smart Notification Engine — Phase 2, 2026-08-02)
// =============================================================================
//
// Posts `delivered` / `opened` / `action_taken` / `dismissed` events to the
// `record-push-event` edge fn. These rows land in
// `push_notification_delivery_log` so the CMS Health & Funnel tab can render:
//
//   enqueued → apns_success → delivered → opened → action_taken
//
// CALL SITES:
//   - `NotificationManager.userNotificationCenter(_:willPresent:)` →
//     reports `delivered` (foreground delivery — the system extension
//     would do this in background; we cover the foreground case here).
//   - `NotificationManager.userNotificationCenter(_:didReceive:)` →
//     reports `opened` for default-action taps and `action_taken` for
//     custom action buttons.
//
// SERVICE EXTENSION (separate Xcode target — `Fit33/NotificationServiceExtension/`):
//   When the dedicated extension target is created in Xcode, its
//   `UNNotificationServiceExtension.didReceive(_:withContentHandler:)`
//   should also call `report(.delivered, ...)` so background-delivered
//   pushes are counted. Until the target is wired in Xcode (requires
//   capability + signing setup), only foreground-delivered + opened
//   events are tracked. The service-extension scaffold lives at
//   `supabase/functions/record-push-event/index.ts` deploy notes.
//
// IDEMPOTENCY:
//   Server dedupes on (notification_id, event) so a willPresent + extension
//   double-fire produces at most one row per notification per event type.
// =============================================================================

@MainActor
final class PushEventReporter {

    static let shared = PushEventReporter()
    private init() {}

    enum Event: String {
        case delivered, opened, actionTaken = "action_taken", dismissed
    }

    /// Fire-and-forget. Failures are logged but never block the receiver.
    /// Safe to call from the foreground completion handler before
    /// `completionHandler([.banner, .sound])` — the network call runs in
    /// a detached Task.
    func report(_ event: Event, payload: PushPayload, actionId: String? = nil) {
        // Skip if the user isn't authenticated yet (notification arrived
        // before sign-in completed; rare but possible during onboarding).
        guard SupabaseManager.shared.isAuthenticated else { return }

        Task.detached {
            await Self.send(event: event, payload: payload, actionId: actionId)
        }
    }

    /// Convenience: report from a raw `userInfo` (saves the caller a
    /// `PushPayload(from:)` ceremony at every call site).
    func report(_ event: Event, userInfo: [AnyHashable: Any], actionId: String? = nil) {
        let payload = PushPayload(from: userInfo)
        report(event, payload: payload, actionId: actionId)
    }

    // MARK: - Private

    private struct Body: Encodable {
        let event: String
        let notification_id: String?
        let intent_id: String?
        let intent_kind: String?
        let category: String?
        let action_id: String?
        let client_at: String?
    }

    private static func send(event: Event, payload: PushPayload, actionId: String?) async {
        let body = Body(
            event: event.rawValue,
            notification_id: payload.notificationId,
            intent_id: payload.intentId,
            intent_kind: payload.intentKind,
            category: payload.category?.rawValue,
            action_id: actionId,
            client_at: ISO8601DateFormatter().string(from: Date())
        )

        do {
            _ = try await SupabaseManager.shared.supabaseClient
                .functions
                .invoke(
                    "record-push-event",
                    options: FunctionInvokeOptions(body: body)
                )
            // Intentionally NO success log — this fires on every notification
            // so logs would balloon. Failure path logs at debug for triage.
        } catch {
            AppLogger.debug(
                "[PUSH-EVENT] Failed to report \(event.rawValue) (notification_id=\(payload.notificationId ?? "nil")): \(error.localizedDescription)",
                category: .network
            )
        }
    }
}
