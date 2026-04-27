//
//  AppConfig.swift
//  Fit33
//
//  Centralized app configuration - DO NOT commit secrets to git in production!
//  For production, these should come from environment variables or a secure config.
//

import Foundation

/// Centralized configuration for API keys and app settings
/// In production, consider using:
/// - Environment variables
/// - Keychain storage
/// - Server-side configuration
enum AppConfig {
    
    // MARK: - Environment Detection
    
    /// Returns true if running in DEBUG mode
    static var isDebug: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }
    
    /// Returns true if running in TestFlight
    static var isTestFlight: Bool {
        Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
    }
    
    /// Returns true if running in App Store
    static var isProduction: Bool {
        !isDebug && !isTestFlight
    }
    
    // MARK: - API Keys (Centralized)
    // Actual secret values live in Secrets.swift (gitignored).
    // See Secrets.template.swift for the schema.
    
    // MARK: - Supabase Configuration
    
    enum Supabase {
        /// Supabase project URL — used by SupabaseManager, FoodDatabaseService, SocialAuthService
        static let url = Secrets.supabaseURL
        /// Supabase anon key — safe client-side when RLS is enforced. See SECURITY_CHECKLIST.md.
        static let anonKey = Secrets.supabaseAnonKey
    }
    
    /// Spoonacular API key for recipe services
    static let spoonacularApiKey: String = Secrets.spoonacularApiKey
    
    // MARK: - Strava Configuration
    
    enum Strava {
        static let clientId = Secrets.stravaClientId
        static let clientSecret = Secrets.stravaClientSecret
        /// IMPORTANT: In Strava API settings (https://www.strava.com/settings/api),
        /// set "Authorization Callback Domain" to: localhost
        /// This allows custom URL scheme redirects to work
        static let redirectUri = "fit33://localhost/strava"
        static let authorizationUrl = "https://www.strava.com/oauth/authorize"
        static let tokenUrl = "https://www.strava.com/oauth/token"
        static let apiBaseUrl = "https://www.strava.com/api/v3"
        static let scopes = "read,activity:read_all"
    }
    
    // MARK: - Fitbit Configuration
    
    enum Fitbit {
        static let clientId = Secrets.fitbitClientId
        static let clientSecret = Secrets.fitbitClientSecret
        static let redirectUri = "fit33://fitbit"
        static let authorizationUrl = "https://www.fitbit.com/oauth2/authorize"
        static let tokenUrl = "https://api.fitbit.com/oauth2/token"
        static let apiBaseUrl = "https://api.fitbit.com"
        // Scopes: activity, heartrate, sleep, weight, nutrition, profile, settings
        static let scopes = "activity heartrate sleep weight profile"
    }
    
    // MARK: - WHOOP Configuration
    
    enum Whoop {
        static let clientId = Secrets.whoopClientId
        static let clientSecret = Secrets.whoopClientSecret
        static let redirectUri = "fit33://whoop"
        static let authorizationUrl = "https://api.prod.whoop.com/oauth/oauth2/auth"
        static let tokenUrl = "https://api.prod.whoop.com/oauth/oauth2/token"
        /// Must match OpenAPI `servers[0].url`; `https://api.prod.whoop.com` + `/v2/*` returns ingress 404 "default backend - 404".
        static let apiBaseUrl = "https://api.prod.whoop.com/developer"
        static let scopes = "read:recovery read:cycles read:workout read:sleep read:profile read:body_measurement"
    }
    
    // MARK: - Oura Ring Configuration
    
    enum Oura {
        static let clientId = Secrets.ouraClientId
        static let clientSecret = Secrets.ouraClientSecret
        static let redirectUri = "fit33://oura"
        static let authorizationUrl = "https://cloud.ouraring.com/oauth/authorize"
        static let tokenUrl = "https://api.ouraring.com/oauth/token"
        static let apiBaseUrl = "https://api.ouraring.com"
        static let scopes = "email personal daily heartrate workout spo2"
    }
    
    // MARK: - InBody Configuration
    
    enum InBody {
        static let clientId = Secrets.inbodyClientId
        static let clientSecret = Secrets.inbodyClientSecret
        static let redirectUri = "fit33://inbody"
        static let authUrl = "https://api.inbody.com/oauth/authorize"
        static let tokenUrl = "https://api.inbody.com/oauth/token"
    }
    
    // MARK: - Dev Menu (Debug Only)
    
    #if DEBUG
    /// Admin password for dev menu access - only available in debug builds.
    /// Value lives in Secrets.swift (gitignored) to keep it out of version control.
    static let devMenuPassword = Secrets.devMenuPassword
    #endif
    
    // MARK: - App Store / Distribution

    enum AppStore {
        /// Update this with your actual App Store ID after publishing
        static let appId = "6478515926"  // Update with actual App Store ID
        static let appStoreURL = "https://apps.apple.com/app/fit33/id\(appId)"
        static let appWebsiteURL = "https://fit33.app"
    }

    /// Convenience accessor for `SKStoreReviewController` fallback URL builder.
    static var appStoreAppId: String? { AppStore.appId }

    // MARK: - Support / Help Center

    enum Support {
        /// Help Center web page shown inside an `SFSafariViewController` from Settings.
        /// Must be a publicly reachable HTTPS URL.
        static let helpCenterURL = "https://fit33.app/help-center.html"
        /// Landing page for Support email, Apple-required in-app "Contact Us".
        static let supportEmail = "support@doublethr33s.com"
    }
    
    // MARK: - Feature Flags
    
    /// Enable verbose logging (only in debug/testflight)
    static var enableVerboseLogging: Bool {
        return isDebug || isTestFlight
    }
    
    /// Enable dev menu access
    static var enableDevMenu: Bool {
        return isDebug || isTestFlight
    }
    
    /// Enable crash detection UI
    static var enableCrashDetection: Bool {
        return isDebug
    }

    /// Personalized Insights V2 — wearable + cross-source correlation
    /// detectors flipped on 2026-04-27 (Daily Brief feature).
    /// Three of four detectors are now real Pearson correlations
    /// (significance-gated, see `Fit33/V2Analyzer.swift`):
    ///   * `detectBestWorkoutTime` → time-of-day x volume on Core Data
    ///   * `detectNutritionPatterns` → protein x next-day volume on
    ///     `daily_summaries`
    ///   * `detectSocialPatterns` → workout frequency uplift during
    ///     active 1v1/community challenges
    /// The fourth — `analyzeHydrationPerformanceCorrelation` — still
    /// holds a `volumeValues = []` placeholder pending a per-day
    /// volume column on `daily_summaries`; it returns r = 0 in that
    /// state and never surfaces a recommendation, so the flip is safe.
    /// Each detector requires `n >= 10`/`12`, `|r| >= 0.3`, `p <= 0.15`
    /// before writing — Data invariant 36 (`(user_id, insight_key)`
    /// upsert key) is honored via `upsertCorrelationInsight`.
    enum FeatureFlags {
        static let personalizedInsightsV2: Bool = true

        // MARK: - Wearable Personalization Platform
        //
        // Phased rollout flags (see plan: Wearable Personalization Platform).
        // Phase 0's unified `ReadinessService` is ALWAYS on — every
        // downstream system reads `ReadinessService.shared.todayReadiness`
        // and gets `.placeholder()` (yellow, no-wearable) when nothing is
        // connected. Flags below gate the BEHAVIOURAL changes that flow
        // from that score, so Phase 0 can ship dark-first without
        // re-routing any workouts.

        /// Phase 1 — Recovery-aware auto-gen. Honors the readiness band
        /// (red → recovery template, yellow → 0.9× volume, green → +10%
        /// ceiling + PR flag). No-op for users without a wearable
        /// signal — `hasWearableSignal == false` short-circuits the
        /// adjuster so unconnected users see zero behavior change.
        static let readinessAdaptiveAutoGen: Bool = true

        /// Phase 4 — XP multipliers. Green day + completed workout →
        /// +20% XP; red day + recovery workout → +15% Smart Rest XP.
        /// Additive-only (never penalizes); gated on
        /// `hasWearableSignal`.
        static let readinessXpBonus: Bool = true

        /// Phase 4 — Wearable-gated daily quests. Client passes
        /// `p_has_connected_wearable` to `get_daily_quests`. New
        /// templates with `requires_context = 'has_wearable'` start
        /// appearing after the follow-up
        /// `20260509b_get_daily_quests_has_wearable_body.sql` that
        /// extends the RPC body's context-allowed predicate. Safe to
        /// ship on before then — RPC serves the existing pool.
        static let wearableQuests: Bool = true

        /// Phase 5 — New `ChallengeType` cases (`sleep_hours`,
        /// `readiness_average`, `strain_budget`). Enum is `CaseIterable`
        /// so creation UIs pick them up. Progress-sync from
        /// `daily_readiness_history` is a follow-up in
        /// `BackgroundChallengeSyncService`.
        static let wearableChallenges: Bool = true

        /// Phase 3 — Adaptive goal proposals. Reads from
        /// `v_user_pending_goal_proposals`. No-op until the server-side
        /// job starts writing proposals; card renders nothing when the
        /// pending list is empty, so safe to ship on.
        static let adaptiveGoals: Bool = true

        /// Smart Adaptive Daily Goals (20260601–20260607). Master
        /// kill-switch for the Phase 5 personalization upgrade:
        ///   * activity-mix bias + per-user weighting in `get_daily_quests`
        ///   * Strava / WHOOP / Oura / Fitbit-context quest templates
        ///   * Friend-named copy (`Beat <Friend>: 8.4K`,
        ///     `Due for legs — do <Friend>'s`)
        ///   * Pro tier features (rerolls, double-XP day,
        ///     custom quests, Insights view). NOTE: 20260619 locked the
        ///     slot count to 3 for all tiers — Pro no longer gets +2.
        ///
        /// When OFF the client sends `false` for every new RPC param
        /// + an empty activity-mix dict; the server falls back to the
        /// pre-20260605 selection logic and zero new quests surface.
        /// Default ON — flip to false if the new layer needs to be
        /// disabled in production without re-deploying SQL.
        static let smartAdaptiveQuests: Bool = true
    }
}

// MARK: - Logging Helper
// NOTE: Production-safe logging is now in Logger.swift → AppLogger.
// The debugLog() function below is kept for backward compatibility.
// Prefer AppLogger.debug() for new code.

func debugLog(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
    #if DEBUG
    let filename = (file as NSString).lastPathComponent
    AppLogger.debug("[\(filename):\(line)] \(function) - \(message)", category: .general)
    #endif
}
