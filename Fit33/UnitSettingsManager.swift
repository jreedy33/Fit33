//
//  UnitSettingsManager.swift
//  GoFit
//
//  Created on 12/22/24.
//

import SwiftUI
import Foundation

/// Manages user's unit preferences with locale-aware defaults
class UnitSettingsManager: ObservableObject {
    static let shared = UnitSettingsManager()
    
    // MARK: - Published Properties
    
    @Published var weightUnit: WeightUnit {
        didSet {
            UserDefaults.standard.set(weightUnit.rawValue, forKey: "weightUnit")
            syncToCloud()
        }
    }
    
    @Published var distanceUnit: DistanceUnit {
        didSet {
            UserDefaults.standard.set(distanceUnit.rawValue, forKey: "distanceUnit")
            syncToCloud()
        }
    }
    
    @Published var heightUnit: HeightUnit {
        didSet {
            UserDefaults.standard.set(heightUnit.rawValue, forKey: "heightUnit")
            syncToCloud()
        }
    }
    
    @Published var startWeekOn: WeekStart {
        didSet {
            UserDefaults.standard.set(startWeekOn.rawValue, forKey: "startWeekOn")
            syncToCloud()
        }
    }
    
    /// Flag to prevent sync loops when loading from cloud
    private var isSyncingFromCloud = false
    
    // MARK: - Enums
    
    enum WeightUnit: String, CaseIterable, Identifiable {
        case imperial = "lbs"
        case metric = "kg"
        
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .imperial: return "US/Imperial (lbs)"
            case .metric: return "Metric (kg)"
            }
        }
        var shortName: String { rawValue }
    }
    
    enum DistanceUnit: String, CaseIterable, Identifiable {
        case imperial = "miles"
        case metric = "km"
        
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .imperial: return "US/Imperial (ft/miles)"
            case .metric: return "Metric (m/km)"
            }
        }
        var shortName: String { rawValue }
    }
    
    enum HeightUnit: String, CaseIterable, Identifiable {
        case imperial = "in"
        case metric = "cm"
        
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .imperial: return "US/Imperial (ft/in)"
            case .metric: return "Metric (cm)"
            }
        }
        var shortName: String { rawValue }
    }
    
    enum WeekStart: String, CaseIterable, Identifiable {
        case sunday = "Sunday"
        case monday = "Monday"
        case saturday = "Saturday"
        
        var id: String { rawValue }
        var displayName: String { rawValue }
    }
    
    // MARK: - Locale Detection
    
    /// Countries that use imperial system
    private static let imperialCountries = ["US", "LR", "MM"] // USA, Liberia, Myanmar
    
    /// Countries that start week on Sunday
    private static let sundayStartCountries = ["US", "CA", "JP", "TW", "KR", "IL", "SA", "AE", "PH", "IN", "BR"]
    
    /// Countries that start week on Saturday
    private static let saturdayStartCountries = ["AF", "DZ", "BH", "BD", "EG", "IR", "IQ", "JO", "KW", "LY", "OM", "QA", "SD", "SY", "YE"]
    
    static var localeUsesImperial: Bool {
        let countryCode = Locale.current.region?.identifier ?? "US"
        return imperialCountries.contains(countryCode)
    }
    
    /// Countries that use MM/DD/YYYY date format (most use DD/MM/YYYY)
    private static let monthFirstDateCountries = ["US", "FM", "MH", "PW"]
    
    /// Returns true if the user's locale uses MM/DD/YYYY format, false for DD/MM/YYYY
    static var localeUsesMonthFirstDate: Bool {
        let countryCode = Locale.current.region?.identifier ?? "US"
        return monthFirstDateCountries.contains(countryCode)
    }
    
    /// Returns the appropriate date format string based on locale
    static var localeDateFormat: String {
        return localeUsesMonthFirstDate ? "MM/DD/YYYY" : "DD/MM/YYYY"
    }
    
    /// Returns the placeholder example based on locale
    static var localeDatePlaceholder: String {
        return localeUsesMonthFirstDate ? "MM/DD/YYYY" : "DD/MM/YYYY"
    }
    
    static var localeWeekStart: WeekStart {
        let countryCode = Locale.current.region?.identifier ?? "US"
        if saturdayStartCountries.contains(countryCode) {
            return .saturday
        } else if sundayStartCountries.contains(countryCode) {
            return .sunday
        }
        return .monday
    }
    
    // MARK: - Initialization
    
    private init() {
        // Load saved preferences or use locale defaults
        let usesImperial = UnitSettingsManager.localeUsesImperial
        
        if let saved = UserDefaults.standard.string(forKey: "weightUnit"),
           let unit = WeightUnit(rawValue: saved) {
            self.weightUnit = unit
        } else {
            self.weightUnit = usesImperial ? .imperial : .metric
        }
        
        if let saved = UserDefaults.standard.string(forKey: "distanceUnit"),
           let unit = DistanceUnit(rawValue: saved) {
            self.distanceUnit = unit
        } else {
            self.distanceUnit = usesImperial ? .imperial : .metric
        }
        
        if let saved = UserDefaults.standard.string(forKey: "heightUnit"),
           let unit = HeightUnit(rawValue: saved) {
            self.heightUnit = unit
        } else {
            self.heightUnit = usesImperial ? .imperial : .metric
        }
        
        if let saved = UserDefaults.standard.string(forKey: "startWeekOn"),
           let start = WeekStart(rawValue: saved) {
            self.startWeekOn = start
        } else {
            self.startWeekOn = UnitSettingsManager.localeWeekStart
        }
    }
    
    // MARK: - Conversion Helpers
    
    // Weight conversions
    func convertWeight(_ value: Double, from: WeightUnit, to: WeightUnit) -> Double {
        if from == to { return value }
        switch (from, to) {
        case (.imperial, .metric): return value * 0.453592  // lbs to kg
        case (.metric, .imperial): return value * 2.20462   // kg to lbs
        default: return value
        }
    }
    
    func formatWeight(_ lbs: Double) -> String {
        switch weightUnit {
        case .imperial:
            return "\(Int(lbs)) lbs"
        case .metric:
            let kg = lbs * 0.453592
            return "\(String(format: "%.1f", kg)) kg"
        }
    }
    
    func weightValue(_ lbs: Double) -> Double {
        switch weightUnit {
        case .imperial: return lbs
        case .metric: return lbs * 0.453592
        }
    }
    
    // Height conversions
    func formatHeight(inches: Double) -> String {
        switch heightUnit {
        case .imperial:
            let feet = Int(inches) / 12
            let remainingInches = Int(inches) % 12
            return "\(feet)'\(remainingInches)\""
        case .metric:
            let cm = inches * 2.54
            return "\(Int(cm)) cm"
        }
    }
    
    func heightValue(inches: Double) -> Double {
        switch heightUnit {
        case .imperial: return inches
        case .metric: return inches * 2.54
        }
    }
    
    // Distance conversions
    func formatDistance(miles: Double) -> String {
        switch distanceUnit {
        case .imperial:
            if miles < 0.1 {
                let feet = miles * 5280
                return "\(Int(feet)) ft"
            }
            return "\(String(format: "%.2f", miles)) mi"
        case .metric:
            let km = miles * 1.60934
            if km < 1 {
                return "\(Int(km * 1000)) m"
            }
            return "\(String(format: "%.2f", km)) km"
        }
    }
    
    func distanceValue(miles: Double) -> Double {
        switch distanceUnit {
        case .imperial: return miles
        case .metric: return miles * 1.60934
        }
    }
    
    // MARK: - Reset to Locale Defaults
    
    func resetToLocaleDefaults() {
        let usesImperial = UnitSettingsManager.localeUsesImperial
        weightUnit = usesImperial ? .imperial : .metric
        distanceUnit = usesImperial ? .imperial : .metric
        heightUnit = usesImperial ? .imperial : .metric
        startWeekOn = UnitSettingsManager.localeWeekStart
    }
    
    // MARK: - Cloud Sync
    
    /// Syncs unit preferences to Supabase (debounced)
    private func syncToCloud() {
        guard !isSyncingFromCloud else { return }
        
        // Debounce: Only sync after user stops making changes
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 second delay
            await performCloudSync()
        }
    }
    
    private func performCloudSync() async {
        guard SupabaseManager.shared.isAuthenticated,
              let userId = SupabaseManager.shared.currentUser?.id else { return }
        
        struct UnitPreferencesUpdate: Encodable {
            let weight_unit: String
            let height_unit: String
            let distance_unit: String
            let week_start_day: String
            let updated_at: String
        }
        
        let update = UnitPreferencesUpdate(
            weight_unit: weightUnit.rawValue,
            height_unit: heightUnit.rawValue,
            distance_unit: distanceUnit.rawValue,
            week_start_day: startWeekOn.rawValue,
            updated_at: ISO8601DateFormatter().string(from: Date())
        )
        
        do {
            try await SupabaseManager.shared.supabaseClient
                .from("user_profiles")
                .update(update)
                .eq("id", value: userId.uuidString)
                .execute()
            print("☁️ [UNITS] Synced preferences to cloud")
        } catch {
            print("⚠️ [UNITS] Failed to sync to cloud: \(error.localizedDescription)")
        }
    }
    
    /// Load unit preferences from cloud profile (called during login sync)
    func loadFromCloud(weightUnit: String?, heightUnit: String?, distanceUnit: String?, weekStartDay: String?) {
        isSyncingFromCloud = true
        defer { isSyncingFromCloud = false }
        
        if let raw = weightUnit, let unit = WeightUnit(rawValue: raw) {
            self.weightUnit = unit
            UserDefaults.standard.set(raw, forKey: "weightUnit")
        }
        if let raw = heightUnit, let unit = HeightUnit(rawValue: raw) {
            self.heightUnit = unit
            UserDefaults.standard.set(raw, forKey: "heightUnit")
        }
        if let raw = distanceUnit, let unit = DistanceUnit(rawValue: raw) {
            self.distanceUnit = unit
            UserDefaults.standard.set(raw, forKey: "distanceUnit")
        }
        if let raw = weekStartDay, let day = WeekStart(rawValue: raw) {
            self.startWeekOn = day
            UserDefaults.standard.set(raw, forKey: "startWeekOn")
        }
    }
    
    // MARK: - Current Locale Info
    
    var currentLocaleDescription: String {
        let locale = Locale.current
        let country = locale.localizedString(forRegionCode: locale.region?.identifier ?? "") ?? "Unknown"
        let language = locale.localizedString(forLanguageCode: locale.language.languageCode?.identifier ?? "") ?? "Unknown"
        return "\(language) (\(country))"
    }
}

// MARK: - SwiftUI Environment

struct UnitSettingsKey: EnvironmentKey {
    static let defaultValue = UnitSettingsManager.shared
}

extension EnvironmentValues {
    var unitSettings: UnitSettingsManager {
        get { self[UnitSettingsKey.self] }
        set { self[UnitSettingsKey.self] = newValue }
    }
}

