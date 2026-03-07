//
//  Secrets.template.swift
//  Fit33
//
//  🔐 TEMPLATE — Copy this file to Secrets.swift and fill in real values.
//  Secrets.swift is gitignored; this template IS committed so new
//  developers know the required schema.
//
//  Steps:
//    1. cp Fit33/Secrets.template.swift Fit33/Secrets.swift
//    2. Fill in values from your secure vault / 1Password
//    3. Build — AppConfig reads from Secrets automatically
//

import Foundation

enum Secrets {
    
    // MARK: - Supabase
    static let supabaseURL = "<SUPABASE_PROJECT_URL>"       // e.g. https://xxxxx.supabase.co
    static let supabaseAnonKey = "<SUPABASE_ANON_KEY>"       // JWT anon key from Supabase dashboard
    
    // MARK: - Recipe / Nutrition API
    static let spoonacularApiKey = "<SPOONACULAR_API_KEY>"
    
    // MARK: - Strava OAuth
    static let stravaClientId = "<STRAVA_CLIENT_ID>"
    static let stravaClientSecret = "<STRAVA_CLIENT_SECRET>"
    
    // MARK: - Fitbit OAuth
    static let fitbitClientId = "<FITBIT_CLIENT_ID>"
    static let fitbitClientSecret = "<FITBIT_CLIENT_SECRET>"
    
    // MARK: - InBody OAuth
    static let inbodyClientId = "<INBODY_CLIENT_ID>"
    static let inbodyClientSecret = "<INBODY_CLIENT_SECRET>"
    
    // MARK: - Dev Menu (Debug Only)
    static let devMenuPassword = "<DEV_MENU_PASSWORD>"
}
