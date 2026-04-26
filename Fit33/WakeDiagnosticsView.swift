#if DEBUG
import SwiftUI
import Supabase

// MARK: - Wake Diagnostics DTO

/// Mirrors the columns returned by `get_my_wake_diagnostics(INT, TEXT)`
/// (migrations `supabase/20260618_wake_diagnostics_rpc.sql` (#118) +
/// `supabase/20260619_wake_diagnostics_progress_drift.sql` (#119)). Date
/// columns are decoded as `String?` (ISO 8601 from PostgREST) and parsed
/// lazily on display — matches the project-wide convention used by
/// `ServerTokenInfo` and the other `*Debug` DTOs. See migration header for
/// why this RPC exists at all (Infra invariant #14 makes the underlying
/// table service-role-only).
private struct WakeDiagnosticRow: Decodable, Identifiable {
    let user_id: UUID
    let display_name: String
    let username: String?
    let profile_photo_url: String?
    let relationship: String           // "self" | "1v1_or_group" | "private"
    let last_wake_at: String?
    let last_wake_trigger: String?
    let wake_count_24h: Int
    let has_valid_token: Bool
    let token_count: Int
    let apns_environment: String?
    let token_prefix: String?
    let last_progress_at: String?
    let last_progress_value: Int?
    // Cross-table steps drift (added in migration #119). NULL for any table
    // the user has no membership / row in for today; meaningful drift is
    // captured in `progress_drift_detected` (server-side predicate).
    let steps_today_1v1: Int?
    let steps_today_private: Int?
    let steps_today_community: Int?
    let progress_drift_detected: Bool?

    var id: UUID { user_id }

    var lastWakeDate: Date? { Self.parseIso(last_wake_at) }
    var lastProgressDate: Date? { Self.parseIso(last_progress_at) }

    /// Static rule-of-thumb staleness threshold for "should this person have
    /// shown up by now?" — anything past this window without a wake event
    /// suggests their device is exhausting Apple's silent-push budget,
    /// missing the cron sweep, or has an invalid token. Lines up with the
    /// 30-min cron cadence + 15-min server throttle in
    /// `supabase/20260420_challenge_opponent_wake.sql`.
    static let wakeStaleThreshold: TimeInterval = 90 * 60

    /// Postgres `timestamptz` -> ISO8601 with optional fractional seconds.
    /// `ISO8601DateFormatter` doesn't accept fractional by default, so we
    /// try the fractional formatter first, then fall back.
    private static func parseIso(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        if let d = isoFractional.date(from: raw) { return d }
        return isoBase.date(from: raw)
    }

    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoBase: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}

// MARK: - Wake Diagnostics View

/// DEBUG-only dev tab that surfaces silent-push wake history + token state
/// for the caller and every counterpart in their active challenges.
///
/// Use this when an opponent (e.g. Abbie) shows 0 progress mid-day and you
/// need to answer: "did her phone receive a wake push?" / "is her token
/// valid?" / "when was her last `challenge_daily_progress` write?" —
/// without poking around the SQL editor for service-role-only tables.
struct WakeDiagnosticsView: View {
    @Environment(\.colorScheme) private var colorScheme

    @State private var rows: [WakeDiagnosticRow] = []
    @State private var lookbackHours: Int = 24
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var lastFetchedAt: Date?
    @State private var manualWakeStatus: String?
    @State private var isFiringWake = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                headerSection
                actionsSection
                summarySection
                rowsSection
            }
            .padding()
            .padding(.bottom, 80)
        }
        .task { await reload() }
    }

    // MARK: - Sections

    private var headerSection: some View {
        debugSection(title: "Wake Diagnostics", icon: "bell.and.waveform.fill", color: .orange) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Silent-push wake history + token state + cross-table steps drift for you and every counterpart in your active challenges. Powered by `get_my_wake_diagnostics(\(lookbackHours), <tz>)`.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let when = lastFetchedAt {
                    Text("Fetched \(when, style: .relative) ago")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                if let err = errorMessage {
                    Text(err)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
        }
    }

    private var actionsSection: some View {
        debugSection(title: "Controls", icon: "slider.horizontal.3", color: .blue) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Picker("Lookback window", selection: $lookbackHours) {
                    Text("1h").tag(1)
                    Text("6h").tag(6)
                    Text("24h").tag(24)
                    Text("7d").tag(168)
                }
                .pickerStyle(.segmented)
                .onChange(of: lookbackHours) { _, _ in
                    Task { await reload() }
                }

                HStack(spacing: Spacing.sm) {
                    Button {
                        Task { await reload() }
                    } label: {
                        Label(isLoading ? "Loading…" : "Refresh", systemImage: "arrow.clockwise")
                            .font(.ds_labelSmall)
                            .foregroundColor(.blue)
                    }
                    .disabled(isLoading)

                    Button {
                        Task { await fireManualWake() }
                    } label: {
                        Label(isFiringWake ? "Sending…" : "Fire wake now", systemImage: "paperplane.fill")
                            .font(.ds_labelSmall)
                            .foregroundColor(.orange)
                    }
                    .disabled(isFiringWake)
                }

                if let status = manualWakeStatus {
                    Text(status)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var summarySection: some View {
        debugSection(title: "Summary", icon: "chart.bar.fill", color: .purple) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                let opponents = rows.filter { $0.relationship != "self" }
                let opponentsWaked = opponents.filter { $0.lastWakeDate != nil }.count
                let opponentsWithoutToken = opponents.filter { !$0.has_valid_token }.count
                let opponentsStale = opponents.filter { isStaleWake($0) }.count
                // Cross-table drift count includes self too — caller's own
                // device can also drift if its 1v1 push errored while the
                // community push went through.
                let drifted = rows.filter { $0.progress_drift_detected == true }.count

                statusRow(label: "Counterparts tracked",
                          value: "\(opponents.count)",
                          color: .secondary)
                statusRow(label: "Waked in window",
                          value: "\(opponentsWaked) / \(opponents.count)",
                          color: opponentsWaked == opponents.count ? .green : .orange)
                statusRow(label: "Stale (no wake > 90m)",
                          value: "\(opponentsStale)",
                          color: opponentsStale == 0 ? .green : .orange)
                statusRow(label: "Missing valid token",
                          value: "\(opponentsWithoutToken)",
                          color: opponentsWithoutToken == 0 ? .green : .red)
                statusRow(label: "Cross-table drift (steps)",
                          value: "\(drifted)",
                          color: drifted == 0 ? .green : .red)
            }
        }
    }

    private var rowsSection: some View {
        debugSection(title: "Counterparts", icon: "person.2.fill", color: .cyan) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                if rows.isEmpty {
                    Text(isLoading ? "Loading…" : "No counterparts found.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(rows) { row in
                        diagnosticCard(for: row)
                    }
                }
            }
        }
    }

    // MARK: - Per-row card

    private func diagnosticCard(for row: WakeDiagnosticRow) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.sm) {
                Text(row.display_name)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                if let u = row.username, !u.isEmpty {
                    Text("@\(u)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Text(relationshipLabel(row.relationship))
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.gray.opacity(0.15))
                    .cornerRadius(4)
            }

            statusRow(label: "Last wake",
                      value: formatLastWake(row),
                      color: wakeColor(row))

            if let trigger = row.last_wake_trigger {
                statusRow(label: "Last trigger",
                          value: trigger,
                          color: .secondary)
            }

            statusRow(label: "Wakes in window",
                      value: "\(row.wake_count_24h)",
                      color: row.wake_count_24h > 0 ? .green : .orange)

            statusRow(label: "Push token",
                      value: tokenStatusLabel(row),
                      color: tokenStatusColor(row))

            if let env = row.apns_environment {
                statusRow(label: "APNs env", value: env, color: .secondary)
            }

            if let prefix = row.token_prefix {
                statusRow(label: "Token prefix",
                          value: "\(prefix)…",
                          color: .secondary)
            }

            statusRow(label: "Last progress",
                      value: formatLastProgress(row),
                      color: progressColor(row))

            // Cross-table steps view. Render only if at least one of the
            // three surfaces returned a value — keeps the card tidy for
            // users who aren't in a steps challenge today.
            if row.steps_today_1v1 != nil
                || row.steps_today_private != nil
                || row.steps_today_community != nil
            {
                let driftColor: Color = (row.progress_drift_detected == true) ? .red : .green
                statusRow(label: "Steps · 1v1/group",
                          value: stepsCellLabel(row.steps_today_1v1),
                          color: driftColor)
                statusRow(label: "Steps · private",
                          value: stepsCellLabel(row.steps_today_private),
                          color: driftColor)
                statusRow(label: "Steps · community",
                          value: stepsCellLabel(row.steps_today_community),
                          color: driftColor)
                if row.progress_drift_detected == true {
                    Text("⚠️ Cross-table drift — check fanout trigger (Data invariant #48 / migration 20260521).")
                        .font(.caption2)
                        .foregroundColor(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.md)
                .fill(Color.gray.opacity(0.08))
        )
    }

    /// "603" / "—" — `nil` rendered as em-dash so a missing row reads
    /// distinctly from a real 0.
    private func stepsCellLabel(_ v: Int?) -> String {
        guard let v else { return "—" }
        return "\(v)"
    }

    // MARK: - Formatters

    private func relationshipLabel(_ raw: String) -> String {
        switch raw {
        case "self": return "you"
        case "1v1_or_group": return "1v1/group"
        case "private": return "private"
        default: return raw
        }
    }

    private func formatLastWake(_ row: WakeDiagnosticRow) -> String {
        guard let when = row.lastWakeDate else { return "never" }
        let elapsed = Date().timeIntervalSince(when)
        return "\(formatRelative(elapsed)) ago"
    }

    private func formatLastProgress(_ row: WakeDiagnosticRow) -> String {
        guard let when = row.lastProgressDate else { return "no rows" }
        let elapsed = Date().timeIntervalSince(when)
        let valueText = row.last_progress_value.map { " · \($0)" } ?? ""
        return "\(formatRelative(elapsed)) ago\(valueText)"
    }

    private func formatRelative(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        if s < 90 { return "\(s)s" }
        let m = s / 60
        if m < 90 { return "\(m)m" }
        let h = m / 60
        if h < 48 { return "\(h)h" }
        return "\(h / 24)d"
    }

    private func wakeColor(_ row: WakeDiagnosticRow) -> Color {
        guard let when = row.lastWakeDate else { return .red }
        let elapsed = Date().timeIntervalSince(when)
        if elapsed < 30 * 60 { return .green }
        if elapsed < WakeDiagnosticRow.wakeStaleThreshold { return .yellow }
        return .orange
    }

    private func progressColor(_ row: WakeDiagnosticRow) -> Color {
        guard let when = row.lastProgressDate else { return .red }
        let elapsed = Date().timeIntervalSince(when)
        if elapsed < 60 * 60 { return .green }
        if elapsed < 6 * 60 * 60 { return .yellow }
        return .orange
    }

    private func isStaleWake(_ row: WakeDiagnosticRow) -> Bool {
        guard row.relationship != "self" else { return false }
        guard let when = row.lastWakeDate else { return true }
        return Date().timeIntervalSince(when) > WakeDiagnosticRow.wakeStaleThreshold
    }

    private func tokenStatusLabel(_ row: WakeDiagnosticRow) -> String {
        if row.token_count == 0 { return "no tokens" }
        if !row.has_valid_token { return "all invalid (\(row.token_count))" }
        return "valid (\(row.token_count))"
    }

    private func tokenStatusColor(_ row: WakeDiagnosticRow) -> Color {
        if row.token_count == 0 || !row.has_valid_token { return .red }
        return .green
    }

    // MARK: - Network

    private func reload() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        // RPC param payload. Caller tz is what `get_active_challenges` uses
        // too, so the drift columns line up with what the user actually sees
        // in their dashboard.
        struct Params: Encodable {
            let p_lookback_hours: Int
            let p_timezone: String
        }
        let params = Params(
            p_lookback_hours: lookbackHours,
            p_timezone: TimeZone.current.identifier
        )

        do {
            let response: [WakeDiagnosticRow] = try await SupabaseManager.shared.supabaseClient
                .rpc("get_my_wake_diagnostics", params: params)
                .execute()
                .value

            await MainActor.run {
                rows = response
                lastFetchedAt = Date()
            }
        } catch {
            await MainActor.run {
                errorMessage = "Failed to load diagnostics: \(error.localizedDescription)"
                AppLogger.warning("[WAKE DIAG] reload failed: \(error.localizedDescription)", category: .social)
            }
        }
    }

    private func fireManualWake() async {
        isFiringWake = true
        manualWakeStatus = nil
        defer { isFiringWake = false }

        struct WakeResponse: Decodable {
            let sent: Int?
            let throttled: Int?
            let candidates: Int?
            let eligible: Int?
            let apns_failed: Int?
        }

        do {
            // Force-bypass the device-side debounce by going around the
            // shared actor: this view is dev-only and we want a deterministic
            // probe. Server-side 15-min/recipient throttle still applies
            // (and is exactly what we're trying to observe).
            let response: WakeResponse = try await SupabaseManager.shared.supabaseClient
                .functions
                .invoke(
                    "wake-challenge-opponents",
                    options: FunctionInvokeOptions(body: ["source": "foreground"])
                )

            let summary = "sent=\(response.sent ?? 0) throttled=\(response.throttled ?? 0) candidates=\(response.candidates ?? 0) eligible=\(response.eligible ?? 0) apns_failed=\(response.apns_failed ?? 0)"
            manualWakeStatus = "✅ \(summary)"
            AppLogger.info("[WAKE DIAG] manual wake \(summary)", category: .social)

            // Re-fetch so the new wake row shows up immediately.
            try? await Task.sleep(for: .seconds(1))
            await reload()
        } catch {
            manualWakeStatus = "❌ \(error.localizedDescription)"
            AppLogger.warning("[WAKE DIAG] manual wake failed: \(error.localizedDescription)", category: .social)
        }
    }

    // MARK: - Styling helpers (lifted from PushNotificationDebugView pattern)

    private func debugSection<Content: View>(
        title: String,
        icon: String,
        color: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
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
}

#endif
