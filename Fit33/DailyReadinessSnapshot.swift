//
//  DailyReadinessSnapshot.swift
//  Fit33
//
//  Wearable Personalization Platform — Phase 0 (Foundation)
//
//  Value type for the unified "Daily Readiness Score" computed by
//  `ReadinessService` on-device from whichever wearable the user has
//  connected. Wearable-agnostic: every downstream system reads this
//  (auto-gen, adaptive goals, XP multipliers, quests, challenges,
//  insights) and never touches raw WHOOP / Oura / Fitbit DTOs.
//
//  Score / band contract (matches FITNESS_EXPERT_AGENT.md invariant
//  #23 and the SQL CHECK in `supabase/20260506_daily_readiness_history.sql`):
//      0-33   → .red    → recovery-day override, skip heavy compounds
//      34-66  → .yellow → normal programming, volume cap 0.9× target
//      67-100 → .green  → encourage PR / +10% volume ceiling
//

import Foundation
import SwiftUI

// MARK: - ReadinessBand

/// Three-way band that maps a numeric score to a programming rule.
/// Kept small + stable so SQL `band` CHECK, Swift decoder, and UI
/// color mapping all stay in lock-step.
enum ReadinessBand: String, Codable, CaseIterable {
    case red
    case yellow
    case green

    /// Canonical threshold lookup. `Int` score → band. Matches SQL
    /// CHECK (`band IN ('red','yellow','green')`) and Fitness Expert
    /// invariant #23.
    init(score: Int) {
        switch score {
        case ..<0: self = .red
        case 0...33: self = .red
        case 34...66: self = .yellow
        case 67...100: self = .green
        default: self = .green
        }
    }

    /// Human-readable headline for banners + cards. Deliberately short
    /// so it fits a one-line `SectionHeader`.
    var title: String {
        switch self {
        case .red: return "Recovery Day"
        case .yellow: return "Listen To Your Body"
        case .green: return "Primed For Training"
        }
    }

    /// Coaching copy for the Active-Workout banner + Dashboard card.
    /// Short enough to fit Data invariant #32 (≤35 char quest strings
    /// inherit this style).
    var coachingCopy: String {
        switch self {
        case .red:
            return "Mobility, walk, or yoga today. Skip heavy compounds."
        case .yellow:
            return "Train, but keep the last rep in the tank."
        case .green:
            return "PR attempt day — you're primed."
        }
    }

    /// SF Symbol used in the readiness pill + banner. Semantic, not
    /// decorative — `heart.text.square.fill` says "recovery", the
    /// up-arrow variants say "green light".
    var sfSymbol: String {
        switch self {
        case .red: return "moon.zzz.fill"
        case .yellow: return "equal.circle.fill"
        case .green: return "bolt.heart.fill"
        }
    }

    /// Band → tinted accent color. Deliberately uses SwiftUI's semantic
    /// colors (not a design-token gradient) so the readiness pill reads
    /// identically in Light/Dark mode without an `AdaptiveColor` hop.
    var accentColor: Color {
        switch self {
        case .red: return .red
        case .yellow: return .yellow
        case .green: return .green
        }
    }

    /// Auto-gen volume multiplier (applied in `WorkoutGenerationContext`
    /// in Phase 1). Red forces the day to a `RecoveryDayTemplate` so we
    /// never apply this multiplier there — guarded upstream.
    var volumeMultiplier: Double {
        switch self {
        case .red: return 0.0           // recovery template overrides entirely
        case .yellow: return 0.9        // cap at 90% of target sets
        case .green: return 1.1         // allow +10% ceiling
        }
    }
}

// MARK: - ReadinessSource

/// Wearable that supplied the winning signal. `.none` means no
/// wearable connected — the service still publishes a `.yellow` band
/// with `score = 50` so downstream UI never shows a blank state.
enum ReadinessSource: String, Codable, CaseIterable {
    case whoop
    case oura
    case fitbit
    case healthkit
    case none

    /// Short display label for the readiness-pill caption
    /// ("from WHOOP" / "from Oura" / "from Apple Health").
    var displayName: String {
        switch self {
        case .whoop: return "WHOOP"
        case .oura: return "Oura"
        case .fitbit: return "Fitbit"
        case .healthkit: return "Apple Health"
        case .none: return "No wearable"
        }
    }
}

// MARK: - ReadinessSignal

/// Individual breakdown signal rendered in the "why is today red?"
/// drill-down sheet. Kept flat + JSON-friendly so it round-trips
/// through the `signals` JSONB column verbatim.
struct ReadinessSignal: Codable, Equatable, Hashable {
    /// Stable machine key (e.g. "hrv_delta", "sleep_hours", "rhr_trend")
    /// so UI can switch on it for icon / color.
    let kind: String
    /// Human label ("HRV below baseline", "Short sleep"). Kept short.
    let label: String
    /// Signed numeric value — the actual delta / hours / bpm. UI
    /// formats the unit from `kind`.
    let value: Double
    /// Severity drives color in the drill-down list:
    /// `.positive` = green chip, `.neutral` = gray, `.warning`
    /// = amber, `.negative` = red.
    let severity: Severity

    enum Severity: String, Codable, CaseIterable {
        case positive
        case neutral
        case warning
        case negative
    }
}

// MARK: - DailyReadinessSnapshot

/// Single immutable value representing "today's readiness" for one
/// user. Encoded into `daily_readiness_history` via
/// `SupabaseManager.upsertReadinessSnapshot(...)`.
///
/// Why a value type and not an @Published class: services mutate
/// their current snapshot by re-assigning, not by mutating in place,
/// so `@Published var todayReadiness: DailyReadinessSnapshot?` gets
/// cheap change-detection without an `ObservableObject` per row.
struct DailyReadinessSnapshot: Codable, Equatable, Hashable, Identifiable {
    /// Day this snapshot represents (user's local date at compute
    /// time — NOT UTC). Stored as `yyyy-MM-dd` in Supabase via the
    /// `date` column.
    let date: Date

    /// 0-100 unified score. `score = 50` + `.yellow` + `.none` is the
    /// sentinel "no wearable connected yet" state.
    let score: Int

    /// Derived from `score` via `ReadinessBand(score:)`. Stored
    /// explicitly so SQL `.eq("band","green")` queries don't need to
    /// compute from `score`.
    let band: ReadinessBand

    /// Which wearable supplied the winning signal.
    let primarySource: ReadinessSource

    /// HRV delta vs the user's personal 28-day baseline, in percent.
    /// `nil` when the winning wearable didn't supply HRV (Fitbit daily
    /// summary doesn't; Apple Health only has HRV from the Watch).
    let hrvDeltaPct: Double?

    /// Sleep last night in hours (total sleep time, not time in bed).
    /// `nil` when no sleep data available.
    let sleepHours: Double?

    /// Sleep debt in minutes vs the user's personal 7h target, floored
    /// at 0. `nil` when no sleep data.
    let sleepDebtMin: Int?

    /// Today's RHR minus the user's personal 28-day baseline RHR.
    /// Positive = higher than usual (concerning). `nil` when no RHR.
    let rhrTrendBpm: Double?

    /// WHOOP strain from the *previous* day cycle. `nil` for non-WHOOP
    /// users. Used by Phase 5 `strain_budget` challenge + Phase 2
    /// overtraining early-warning insight.
    let strainPrev: Double?

    /// Free-form breakdown for the UI drill-down.
    let signals: [ReadinessSignal]

    /// Whether this snapshot came from a real wearable (Whoop/Oura/
    /// Fitbit/HealthKit) vs the placeholder "no wearable" sentinel.
    /// Phase 4 XP multipliers read this to skip rewards for users who
    /// haven't connected anything — otherwise everyone would get the
    /// green-day +20% because the sentinel is `.yellow` (fair) but
    /// could be gamed if we said all yellow days got a note.
    var hasWearableSignal: Bool { primarySource != ReadinessSource.none }

    /// Stable id per day (ISO date string). `daily_readiness_history`
    /// has a real UUID PK on the server — this id is for
    /// `ForEach(snapshot.id)` in SwiftUI and never shipped to Supabase.
    var id: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone.current
        return f.string(from: date)
    }

    // MARK: - Sentinel

    /// Empty placeholder snapshot for cold-start / no-wearable state.
    /// `.yellow` + `.none` so:
    ///   - UI never shows "Red" for a user with no wearable
    ///   - Auto-gen applies no multiplier (yellow × `hasWearableSignal`
    ///     guard → pass-through)
    ///   - XP multipliers skip (guard on `hasWearableSignal`)
    static func placeholder(on date: Date = Date()) -> DailyReadinessSnapshot {
        DailyReadinessSnapshot(
            date: date,
            score: 50,
            band: .yellow,
            primarySource: .none,
            hrvDeltaPct: nil,
            sleepHours: nil,
            sleepDebtMin: nil,
            rhrTrendBpm: nil,
            strainPrev: nil,
            signals: []
        )
    }
}

// MARK: - Codable (Supabase row)

/// Supabase row shape — snake_case, string `date`, string `band`,
/// string `primary_source`. Insert/upsert payload and row decoder
/// share this struct to avoid DTO drift.
///
/// NOTE: The Swift `DailyReadinessSnapshot` uses `Date` + enum cases
/// for ergonomics; this intermediate struct handles the conversion
/// at the Supabase boundary. `SupabaseManager.upsertReadinessSnapshot`
/// builds one of these from a `DailyReadinessSnapshot` before calling
/// `.upsert(... , onConflict: "user_id,date")`.
struct DailyReadinessRow: Codable {
    let userId: String
    let date: String
    let score: Int
    let band: String
    let primarySource: String
    let hrvDeltaPct: Double?
    let sleepHours: Double?
    let sleepDebtMin: Int?
    let rhrTrendBpm: Double?
    let strainPrev: Double?
    let signals: [ReadinessSignal]

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case date
        case score
        case band
        case primarySource = "primary_source"
        case hrvDeltaPct = "hrv_delta_pct"
        case sleepHours = "sleep_hours"
        case sleepDebtMin = "sleep_debt_min"
        case rhrTrendBpm = "rhr_trend_bpm"
        case strainPrev = "strain_prev"
        case signals
    }

    private static let isoDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone.current
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    /// Build a row payload ready for `.upsert(...)`.
    init(userId: UUID, snapshot: DailyReadinessSnapshot) {
        self.userId = userId.uuidString
        self.date = Self.isoDayFormatter.string(from: snapshot.date)
        self.score = snapshot.score
        self.band = snapshot.band.rawValue
        self.primarySource = snapshot.primarySource.rawValue
        self.hrvDeltaPct = snapshot.hrvDeltaPct
        self.sleepHours = snapshot.sleepHours
        self.sleepDebtMin = snapshot.sleepDebtMin
        self.rhrTrendBpm = snapshot.rhrTrendBpm
        self.strainPrev = snapshot.strainPrev
        self.signals = snapshot.signals
    }

    /// Decode back into a snapshot after `SELECT`. Returns nil when
    /// `date` isn't a valid `yyyy-MM-dd` string (should never happen
    /// because the SQL CHECK keeps bands sane, but safe-default).
    func toSnapshot() -> DailyReadinessSnapshot? {
        guard let parsedDate = Self.isoDayFormatter.date(from: date) else {
            return nil
        }
        let parsedBand = ReadinessBand(rawValue: band) ?? ReadinessBand(score: score)
        let parsedSource = ReadinessSource(rawValue: primarySource) ?? .none
        return DailyReadinessSnapshot(
            date: parsedDate,
            score: score,
            band: parsedBand,
            primarySource: parsedSource,
            hrvDeltaPct: hrvDeltaPct,
            sleepHours: sleepHours,
            sleepDebtMin: sleepDebtMin,
            rhrTrendBpm: rhrTrendBpm,
            strainPrev: strainPrev,
            signals: signals
        )
    }
}
