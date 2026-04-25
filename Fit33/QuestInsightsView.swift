//
//  QuestInsightsView.swift
//  Fit33
//
//  Smart Adaptive Daily Goals — Pro Insights screen.
//
//  Reads `v_user_quest_personalization_summary` (security_invoker view,
//  20260607 migration) and renders:
//    • the user's 28-day per-category completion bars
//    • the user's dominant / least-touched activity buckets
//    • currently-suppressed categories with a Pro "un-suppress" override
//      (calls `unsuppress_quest_category` RPC).
//
//  Pro-gated by PremiumManager. Free users see a paywall stub. The view
//  is presented as a sheet from DailyQuestsWidget so it can render on any
//  surface without depending on a NavigationStack contract.
//

import SwiftUI

@MainActor
struct QuestInsightsView: View {
    @ObservedObject var questService: DailyQuestService
    @Environment(\.dismiss) private var dismiss

    @State private var rows: [PersonalizationRow] = []
    @State private var dominantCategory: String? = nil
    @State private var leastCategory: String? = nil
    @State private var totalSessions28d: Int = 0
    @State private var isLoading: Bool = true
    @State private var loadError: String? = nil
    @State private var unsuppressing: Set<String> = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if !PremiumManager.shared.isPremiumUser {
                    proGate
                } else if isLoading {
                    loadingState
                } else if let err = loadError {
                    errorState(err)
                } else {
                    headerSummary
                    completionBarsSection
                    suppressedSection
                    legendFooter
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .navigationTitle("Quest Insights")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            }
        }
        .task {
            await loadInsights()
        }
        .refreshable {
            await loadInsights()
        }
    }

    // MARK: - Sections

    private var headerSummary: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("28-Day Activity Mix")
                .font(.ds_heading3)
            HStack(spacing: 10) {
                Image(systemName: "flame.fill")
                    .foregroundColor(.orange)
                Text("\(totalSessions28d) sessions logged")
                    .font(.ds_bodyMedium)
            }
            if let dom = dominantCategory {
                HStack(spacing: 8) {
                    Text("Dominant").font(.ds_labelSmall).foregroundColor(.secondary)
                    Text(humanLabel(dom))
                        .font(.ds_labelMedium)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(Color.green.opacity(0.18)))
                        .foregroundColor(.green)
                }
            }
            if let least = leastCategory, least != dominantCategory {
                HStack(spacing: 8) {
                    Text("Least touched").font(.ds_labelSmall).foregroundColor(.secondary)
                    Text(humanLabel(least))
                        .font(.ds_labelMedium)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(Color.orange.opacity(0.18)))
                        .foregroundColor(.orange)
                }
            }
            Text("Goals are tuned to bias toward what you actually do, with gentle nudges into your least-touched area.")
                .font(.ds_bodySmall)
                .foregroundColor(.secondary)
                .padding(.top, 4)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.secondary.opacity(0.08))
        )
    }

    private var completionBarsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Completion by Category")
                .font(.ds_heading3)
            if rows.isEmpty {
                Text("No data yet — complete a few daily goals to populate.")
                    .font(.ds_bodySmall)
                    .foregroundColor(.secondary)
            } else {
                ForEach(rows.sorted(by: { $0.completionRate28d > $1.completionRate28d })) { row in
                    completionBar(row)
                }
            }
        }
    }

    private func completionBar(_ row: PersonalizationRow) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(humanLabel(row.category))
                    .font(.ds_labelMedium)
                Spacer()
                Text(percentLabel(row.completionRate28d))
                    .font(.ds_labelSmall)
                    .foregroundColor(.secondary)
                stateBadge(row.state)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.18))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(barColor(for: row))
                        .frame(width: geo.size.width * CGFloat(min(max(row.completionRate28d, 0), 1)))
                }
            }
            .frame(height: 8)
            HStack(spacing: 10) {
                Text("\(row.totalCompleted28d)/\(row.totalAssigned28d) completed")
                    .font(.ds_labelSmall).foregroundColor(.secondary)
                if row.skipStreak >= 2 {
                    Text("Skip streak: \(row.skipStreak)")
                        .font(.ds_labelSmall)
                        .foregroundColor(.red.opacity(0.85))
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var suppressedSection: some View {
        let suppressed = rows.filter { $0.state == "suppressed" }
        return Group {
            if !suppressed.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Currently Paused")
                        .font(.ds_heading3)
                    Text("These categories are temporarily paused because you've been skipping them. They'll auto-resume after 14 days, or you can re-engage them now.")
                        .font(.ds_bodySmall)
                        .foregroundColor(.secondary)
                    ForEach(suppressed) { row in
                        suppressedRow(row)
                    }
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.orange.opacity(0.07))
                )
            }
        }
    }

    private func suppressedRow(_ row: PersonalizationRow) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "pause.circle.fill")
                .foregroundColor(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(humanLabel(row.category))
                    .font(.ds_labelMedium)
                if let until = row.suppressedUntil {
                    Text("Auto-resumes \(formattedDate(until))")
                        .font(.ds_labelSmall)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            Button {
                Task { await unsuppress(row.category) }
            } label: {
                if unsuppressing.contains(row.category) {
                    ProgressView().scaleEffect(0.7)
                } else {
                    Text("Resume")
                        .font(.ds_labelSmall)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Capsule().fill(Color.orange))
                        .foregroundColor(.white)
                }
            }
            .disabled(unsuppressing.contains(row.category))
            .buttonStyle(.plain)
        }
        .padding(.vertical, 6)
    }

    private var legendFooter: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("How this feeds your daily goals")
                .font(.ds_labelMedium)
            Text("Auto-tracked goals (HealthKit, Strava, WHOOP, Oura, Fitbit) earn +50% XP. Honor-system inputs earn 0.7×. The system suppresses categories you skip 3+ days in a row at <20% completion, and auto-clears the moment you complete one.")
                .font(.ds_bodySmall)
                .foregroundColor(.secondary)
        }
        .padding(.top, 6)
    }

    private var loadingState: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text("Loading your insights…")
                .font(.ds_bodySmall)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 40)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundColor(.orange)
            Text("Couldn't load insights")
                .font(.ds_labelMedium)
            Text(message)
                .font(.ds_bodySmall)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry") {
                Task { await loadInsights() }
            }
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }

    private var proGate: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.fill")
                .font(.system(size: 32))
                .foregroundStyle(LinearGradient(colors: [.yellow, .orange],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing))
            Text("Quest Insights is a Pro feature")
                .font(.ds_heading3)
                .multilineTextAlignment(.center)
            Text("See per-category 28-day completion, what's currently paused, and re-engage suppressed categories on demand.")
                .font(.ds_bodySmall)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Helpers

    private func stateBadge(_ state: String) -> some View {
        let (label, color): (String, Color) = {
            switch state {
            case "on_fire":    return ("On fire", .green)
            case "mixed":      return ("Steady", .yellow)
            case "cold":       return ("Cold", .secondary)
            case "suppressed": return ("Paused", .orange)
            default:           return (state.capitalized, .secondary)
            }
        }()
        return Text(label)
            .font(.ds_labelSmall)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.18)))
            .foregroundColor(color)
    }

    private func barColor(for row: PersonalizationRow) -> Color {
        switch row.state {
        case "on_fire":    return .green
        case "mixed":      return .yellow
        case "cold":       return .secondary
        case "suppressed": return .orange
        default:           return .blue
        }
    }

    private func percentLabel(_ rate: Double) -> String {
        let pct = Int((rate * 100).rounded())
        return "\(pct)%"
    }

    private func humanLabel(_ category: String) -> String {
        category
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    private func formattedDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: d)
    }

    // MARK: - Network

    private func loadInsights() async {
        guard let userId = SupabaseManager.shared.currentUser?.id else {
            loadError = "Not signed in"
            isLoading = false
            return
        }
        isLoading = true
        loadError = nil
        do {
            let response: [PersonalizationRow] = try await SupabaseManager.shared.supabaseClient
                .from("v_user_quest_personalization_summary")
                .select("category, total_assigned_28d, total_completed_28d, completion_rate_28d, skip_streak, last_completed_at, suppressed_until, state, user_dominant_category, user_least_category, user_sessions_28d")
                .eq("user_id", value: userId.uuidString)
                .execute()
                .value

            self.rows = response
            self.dominantCategory = response.first?.userDominantCategory
            self.leastCategory = response.first?.userLeastCategory
            self.totalSessions28d = response.first?.userSessions28d ?? 0
            self.isLoading = false
            AppLogger.debug("[QuestInsights] Loaded \(response.count) rows", category: .general)
        } catch {
            self.loadError = error.localizedDescription
            self.isLoading = false
            AppLogger.error("[QuestInsights] Load failed: \(error.localizedDescription)", category: .general)
        }
    }

    private func unsuppress(_ category: String) async {
        unsuppressing.insert(category)
        defer { unsuppressing.remove(category) }
        let ok = await questService.unsuppressCategory(category)
        if ok {
            await loadInsights()
        }
    }
}

// MARK: - Decodable row matching v_user_quest_personalization_summary

private struct PersonalizationRow: Identifiable, Decodable {
    var id: String { category }
    let category: String
    let totalAssigned28d: Int
    let totalCompleted28d: Int
    let completionRate28d: Double
    let skipStreak: Int
    let lastCompletedAt: Date?
    let suppressedUntil: Date?
    let state: String
    let userDominantCategory: String?
    let userLeastCategory: String?
    let userSessions28d: Int?

    enum CodingKeys: String, CodingKey {
        case category
        case totalAssigned28d        = "total_assigned_28d"
        case totalCompleted28d       = "total_completed_28d"
        case completionRate28d       = "completion_rate_28d"
        case skipStreak              = "skip_streak"
        case lastCompletedAt         = "last_completed_at"
        case suppressedUntil         = "suppressed_until"
        case state
        case userDominantCategory    = "user_dominant_category"
        case userLeastCategory       = "user_least_category"
        case userSessions28d         = "user_sessions_28d"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.category = try c.decode(String.self, forKey: .category)
        self.totalAssigned28d = try c.decodeIfPresent(Int.self, forKey: .totalAssigned28d) ?? 0
        self.totalCompleted28d = try c.decodeIfPresent(Int.self, forKey: .totalCompleted28d) ?? 0
        self.completionRate28d = try c.decodeIfPresent(Double.self, forKey: .completionRate28d) ?? 0
        self.skipStreak = try c.decodeIfPresent(Int.self, forKey: .skipStreak) ?? 0
        self.state = try c.decodeIfPresent(String.self, forKey: .state) ?? "cold"
        self.userDominantCategory = try c.decodeIfPresent(String.self, forKey: .userDominantCategory)
        self.userLeastCategory = try c.decodeIfPresent(String.self, forKey: .userLeastCategory)
        self.userSessions28d = try c.decodeIfPresent(Int.self, forKey: .userSessions28d)
        self.lastCompletedAt = Self.decodeDate(c, key: .lastCompletedAt)
        self.suppressedUntil = Self.decodeDate(c, key: .suppressedUntil)
    }

    private static func decodeDate(_ c: KeyedDecodingContainer<CodingKeys>, key: CodingKeys) -> Date? {
        if let s = try? c.decodeIfPresent(String.self, forKey: key), !s.isEmpty {
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = iso.date(from: s) { return d }
            iso.formatOptions = [.withInternetDateTime]
            if let d = iso.date(from: s) { return d }
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd"
            df.timeZone = TimeZone(identifier: "UTC")
            return df.date(from: s)
        }
        return nil
    }
}
