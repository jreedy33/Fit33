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
    
    /// Spoonacular API key for recipe services
    static let spoonacularApiKey: String = {
        // In production, retrieve from secure storage
        return "69f4b06727ac448d88841e2ce717a228"
    }()
    
    // MARK: - Strava Configuration
    
    enum Strava {
        static let clientId = "198007"
        /// Note: Client secret should ideally be server-side only
        static let clientSecret = "fa5151258db944c5878d653c3166e7f08e2b92f3"
        static let redirectUri = "fit33://strava"
        static let authorizationUrl = "https://www.strava.com/oauth/authorize"
        static let tokenUrl = "https://www.strava.com/oauth/token"
        static let apiBaseUrl = "https://www.strava.com/api/v3"
        static let scopes = "read,activity:read_all"
    }
    
    // MARK: - InBody Configuration
    
    enum InBody {
        static let clientId = "YOUR_INBODY_CLIENT_ID"
        /// Note: Client secret should ideally be server-side only
        static let clientSecret = "YOUR_INBODY_CLIENT_SECRET"
        static let redirectUri = "fit33://inbody"
        static let authUrl = "https://api.inbody.com/oauth/authorize"
        static let tokenUrl = "https://api.inbody.com/oauth/token"
    }
    
    // MARK: - Dev Menu (Debug Only)
    
    #if DEBUG
    /// Admin password for dev menu access - only available in debug builds
    static let devMenuPassword = "WhatsApp26!"
    #endif
    
    // MARK: - App Store / Distribution
    
    enum AppStore {
        /// Update this with your actual App Store ID after publishing
        static let appId = "6478515926"  // Update with actual App Store ID
        static let appStoreURL = "https://apps.apple.com/app/fit33/id\(appId)"
        static let appWebsiteURL = "https://fit33.app"
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

/// Production-safe logging that only outputs in debug/testflight builds
func debugLog(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
    #if DEBUG
    let filename = (file as NSString).lastPathComponent
    print("[\(filename):\(line)] \(function) - \(message)")
    #endif
}
