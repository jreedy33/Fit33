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
