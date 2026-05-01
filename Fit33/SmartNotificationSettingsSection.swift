// SmartNotificationSettingsSection.swift
// =============================================================================
// Smart Notification Engine — Phase 4 Settings Surface
// =============================================================================
// Server-backed user controls for the Smart Notification Engine
// (orchestrator + categories + caps). Kept in its own file so the legacy
// `NotificationSettingsView` stays untouched while the new system lights up.
//
// What this section adds on top of the existing legacy settings:
//   • Smart Timing toggle — sends `smart_timing_enabled` to the server,
//     telling the orchestrator to use per-(user, category, hour) open-rate
//     history when scoring intents.
//   • Daily Notification Cap stepper — writes `daily_cap` to
//     `user_notification_preferences`. The send-push-notification edge
//     function consults this on every dequeue and emits `cap_exceeded`
//     into `push_notification_delivery_log` when it would breach.
//   • Snooze All 24h — calls `snooze_notification_category('all', 24)`
//     RPC. The orchestrator suppresses non-critical intents while the
//     `snoozed_until` window is active.
//   • Per-category preview cards — show the user a worked example of what
//     each category's notifications look like ("Your Bronze League just
//     started!") so consent is informed, not abstract.
//
// Pre-Phase 4 the only consent surface was a list of toggles; users
// couldn't tell what they'd actually receive. This restructure is what
// the user described as "Make them really smart and intelligent and
// personal and customizable in the setting menu" — the catalog +
// preview + per-tier cap is the customizability layer.
//
// All RPCs come from migration 20260801. The server is the source of
// truth; UserDefaults is a UI cache that re-syncs via
// `NotificationManager.syncPreferencesFromCloud()` on app launch.
// =============================================================================

import SwiftUI

// MARK: - Smart Notification Frequency Tier

/// User-facing notification frequency tier. Maps onto per-category
/// caps in `notification_categories` (`quiet_cap`, `balanced_cap`,
/// `active_cap`). Server applies the cap; this is just the picker.
enum SmartNotificationFrequency: String, CaseIterable, Codable, Identifiable {
    case quiet
    case balanced
    case active

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .quiet: return "Quiet"
        case .balanced: return "Balanced"
        case .active: return "Active"
        }
    }

    var description: String {
        switch self {
        case .quiet: return "Only the highest-signal pushes (1 per category, per day)"
        case .balanced: return "Recommended — up to 3 per category, smart timing"
        case .active: return "All eligible pushes — best for users who want max engagement"
        }
    }

    var icon: String {
        switch self {
        case .quiet: return "moon.zzz.fill"
        case .balanced: return "scope"
        case .active: return "bolt.fill"
        }
    }

    var color: Color {
        switch self {
        case .quiet: return .indigo
        case .balanced: return .green
        case .active: return .orange
        }
    }
}

// MARK: - Smart Notification Settings ViewModel

@MainActor
final class SmartNotificationSettings: ObservableObject {
    static let shared = SmartNotificationSettings()

    // UserDefaults-backed mirror of server prefs. NotificationManager's
    // `syncPreferencesFromCloud()` writes the canonical keys here so this
    // VM and the existing legacy NotificationManager share state.
    @Published var smartTimingEnabled: Bool {
        didSet {
            UserDefaults.standard.set(smartTimingEnabled, forKey: "notif_smart_timing_enabled")
            scheduleServerWrite()
        }
    }

    @Published var frequencyTier: SmartNotificationFrequency {
        didSet {
            UserDefaults.standard.set(frequencyTier.rawValue, forKey: "notif_frequency_tier")
            scheduleServerWrite()
        }
    }

    @Published var dailyCap: Int {
        didSet {
            UserDefaults.standard.set(dailyCap, forKey: "notif_daily_cap")
            scheduleServerWrite()
        }
    }

    @Published var allCategoriesSnoozedUntil: Date?

    private var pendingWrite: Task<Void, Never>?

    private init() {
        let defaults = UserDefaults.standard
        smartTimingEnabled = defaults.object(forKey: "notif_smart_timing_enabled") as? Bool ?? true
        if let raw = defaults.string(forKey: "notif_frequency_tier"),
           let tier = SmartNotificationFrequency(rawValue: raw) {
            frequencyTier = tier
        } else {
            frequencyTier = .balanced
        }
        dailyCap = defaults.object(forKey: "notif_daily_cap") as? Int ?? 10
        if let raw = defaults.string(forKey: "notif_all_snoozed_until"),
           let parsed = ISO8601DateFormatter().date(from: raw),
           parsed > Date() {
            allCategoriesSnoozedUntil = parsed
        } else {
            allCategoriesSnoozedUntil = nil
        }
    }

    // MARK: - Server writes

    func snoozeAll24Hours() {
        let until = Date().addingTimeInterval(24 * 60 * 60)
        allCategoriesSnoozedUntil = until
        UserDefaults.standard.set(ISO8601DateFormatter().string(from: until),
                                  forKey: "notif_all_snoozed_until")
        Task.detached {
            await Self.snoozeAllOnServer(hours: 24)
        }
    }

    func clearSnooze() {
        allCategoriesSnoozedUntil = nil
        UserDefaults.standard.removeObject(forKey: "notif_all_snoozed_until")
        Task.detached {
            await Self.clearSnoozeOnServer()
        }
    }

    private func scheduleServerWrite() {
        pendingWrite?.cancel()
        let snapshotEnabled = smartTimingEnabled
        let snapshotCap = dailyCap
        // Coalesce rapid toggles into a single write 800ms after the last edit.
        pendingWrite = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            await Self.writePrefsToServer(smartTimingEnabled: snapshotEnabled,
                                          dailyCap: snapshotCap)
            self?.pendingWrite = nil
        }
    }

    private static func writePrefsToServer(smartTimingEnabled: Bool, dailyCap: Int) async {
        guard SupabaseManager.shared.isAuthenticated,
              let userId = SupabaseManager.shared.currentUser?.id else { return }
        struct Upsert: Encodable {
            let user_id: String
            let smart_timing_enabled: Bool
            let daily_cap: Int
            let updated_at: String
        }
        let payload = Upsert(
            user_id: userId.uuidString,
            smart_timing_enabled: smartTimingEnabled,
            daily_cap: dailyCap,
            updated_at: ISO8601DateFormatter().string(from: Date())
        )
        do {
            try await SupabaseManager.shared.supabaseClient
                .from("user_notification_preferences")
                .upsert(payload, onConflict: "user_id")
                .execute()
            AppLogger.info("Synced smart notification prefs (smart=\(smartTimingEnabled) cap=\(dailyCap))",
                           category: .general)
        } catch {
            AppLogger.error("Failed smart prefs write: \(error.localizedDescription)", category: .general)
        }
    }

    private struct SnoozeParams: Encodable {
        let p_category: String?
        let p_hours: Int
    }

    private struct ClearSnoozeParams: Encodable {
        let p_category: String?
    }

    private static func snoozeAllOnServer(hours: Int) async {
        guard SupabaseManager.shared.isAuthenticated else { return }
        do {
            try await SupabaseManager.shared.supabaseClient
                .rpc("snooze_notification_category",
                     params: SnoozeParams(p_category: nil, p_hours: hours))
                .execute()
        } catch {
            AppLogger.error("Snooze all RPC failed: \(error.localizedDescription)", category: .general)
        }
    }

    private static func clearSnoozeOnServer() async {
        guard SupabaseManager.shared.isAuthenticated else { return }
        do {
            try await SupabaseManager.shared.supabaseClient
                .rpc("clear_notification_snooze",
                     params: ClearSnoozeParams(p_category: nil))
                .execute()
        } catch {
            AppLogger.error("Clear snooze RPC failed: \(error.localizedDescription)", category: .general)
        }
    }
}

// MARK: - Settings Section View

struct SmartNotificationSettingsSection: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var settings = SmartNotificationSettings.shared

    var body: some View {
        VStack(spacing: 20) {
            smartTimingCard
            frequencyTierCard
            dailyCapCard
            snoozeCard
            previewSectionHeader
            previewCards
        }
    }

    // MARK: Cards

    private var smartTimingCard: some View {
        sectionCard(title: "Smart Timing", subtitle: "Personalized engagement-aware delivery") {
            HStack(spacing: 16) {
                iconBubble(systemName: "brain.head.profile", color: .purple)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Use my open-rate history")
                        .font(.subheadline).fontWeight(.semibold).foregroundColor(.primary)
                    Text("We'll deliver each category at the hours you actually open them.")
                        .font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Toggle("", isOn: $settings.smartTimingEnabled).labelsHidden().tint(.purple)
            }
        }
    }

    private var frequencyTierCard: some View {
        sectionCard(title: "Frequency", subtitle: "How often you'd like notifications") {
            VStack(spacing: 8) {
                ForEach(SmartNotificationFrequency.allCases) { tier in
                    Button { settings.frequencyTier = tier } label: {
                        HStack(spacing: 14) {
                            iconBubble(systemName: tier.icon, color: tier.color, size: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(tier.displayName).font(.subheadline).fontWeight(.semibold).foregroundColor(.primary)
                                Text(tier.description).font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                            if settings.frequencyTier == tier {
                                Image(systemName: "checkmark.circle.fill").font(.title3).foregroundColor(tier.color)
                            } else {
                                Image(systemName: "circle").font(.title3).foregroundColor(.secondary.opacity(0.4))
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var dailyCapCard: some View {
        sectionCard(title: "Daily Cap", subtitle: "Hard limit across all categories") {
            HStack(spacing: 16) {
                iconBubble(systemName: "speedometer", color: .blue)
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(settings.dailyCap) per day")
                        .font(.headline).foregroundColor(.primary)
                    Text("Once you hit this, anything else is held until tomorrow.")
                        .font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                Stepper("", value: $settings.dailyCap, in: 1...30, step: 1)
                    .labelsHidden().tint(.blue)
            }
        }
    }

    private var snoozeCard: some View {
        sectionCard(title: "Snooze", subtitle: "Mute everything for 24 hours") {
            if let until = settings.allCategoriesSnoozedUntil {
                HStack(spacing: 16) {
                    iconBubble(systemName: "moon.zzz.fill", color: .indigo)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Notifications muted until")
                            .font(.subheadline).fontWeight(.semibold).foregroundColor(.primary)
                        Text(until, style: .relative).font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("Resume") { settings.clearSnooze() }
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundColor(.indigo)
                }
            } else {
                Button { settings.snoozeAll24Hours() } label: {
                    HStack(spacing: 16) {
                        iconBubble(systemName: "moon.zzz.fill", color: .indigo)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Snooze for 24 Hours")
                                .font(.subheadline).fontWeight(.semibold).foregroundColor(.primary)
                            Text("Critical pushes (challenge invites) still come through.")
                                .font(.caption).foregroundColor(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var previewSectionHeader: some View {
        Text("Examples")
            .font(.subheadline).fontWeight(.semibold).foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.xxs)
            .padding(.top, 8)
    }

    private var previewCards: some View {
        VStack(spacing: 10) {
            previewRow(emoji: "🥉", title: "Your Bronze league just started!",
                       body: "Climb to silver — first workout decides Monday's matchups.",
                       color: .orange)
            previewRow(emoji: "⚔️", title: "Kc is beating you 1v1 mid-day",
                       body: "Talk smack — opens to the smack-talk thread.",
                       color: .red)
            previewRow(emoji: "💧", title: "Drink water, log it!",
                       body: "You're behind your hydration pace. Tap to log a glass.",
                       color: .blue)
            previewRow(emoji: "💤", title: "Your WHOOP sleep score is low",
                       body: "Get 6.4 hours tonight to clear today's debt.",
                       color: .purple)
        }
    }

    // MARK: Helpers

    private func previewRow(emoji: String, title: String, body: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(emoji).font(.title2).frame(width: 36, height: 36)
                .background(color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline).fontWeight(.semibold).foregroundColor(.primary)
                Text(body).font(.caption).foregroundColor(.secondary)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.md)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.06), radius: 6, x: 0, y: 2)
        )
    }

    private func sectionCard<Content: View>(title: String,
                                            subtitle: String? = nil,
                                            @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline).fontWeight(.semibold).foregroundColor(.primary)
                if let subtitle { Text(subtitle).font(.caption).foregroundColor(.secondary) }
            }
            content()
                .padding(Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: CornerRadius.lg)
                        .fill(Color.cardBackground)
                        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.05),
                                radius: 10, x: 0, y: 4)
                )
        }
    }

    private func iconBubble(systemName: String, color: Color, size: CGFloat = 40) -> some View {
        ZStack {
            Circle().fill(color.opacity(0.15)).frame(width: size, height: size)
            Image(systemName: systemName).font(.system(size: size * 0.45, weight: .semibold))
                .foregroundColor(color)
        }
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 16) {
            SmartNotificationSettingsSection()
        }
        .padding()
    }
    .background(Color(.systemGroupedBackground))
}
