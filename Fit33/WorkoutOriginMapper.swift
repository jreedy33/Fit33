//
//  WorkoutOriginMapper.swift
//  Fit33
//
//  Central source of truth for mapping a HealthKit workout's source
//  (bundleIdentifier + source name) to a canonical origin key plus display
//  metadata. Used by:
//    - HealthDataService.saveHealthKitWorkout  → populate `origin_app` column
//      and decide whether to skip based on the user's connected OAuth
//      integrations (Strava/Fitbit/WHOOP/Oura, today; extensible).
//    - DashboardWorkoutCards / HealthKitSettingsView → render the correct
//      third-party badge (icon + color + label) instead of a generic Apple
//      Health heart.
//    - StravaService / FitbitService / WhoopService / OuraService → on
//      OAuth connect, call `HealthDataService.removeHealthKitDuplicates`
//      keyed by the same origin to clean up any stale HealthKit-imported
//      rows so the OAuth feed is the single source of truth.
//
//  Design note: bundle identifier is the primary signal (stable across
//  localizations and app rebrands). `sourceName` is the fallback for apps
//  we haven't seen before.
//

import Foundation
import SwiftUI

/// Canonical, transport-independent identity for the app that authored a
/// workout. Stored verbatim in `cardio_workouts.origin_app`.
enum WorkoutOrigin: String, CaseIterable {
    case strava          // com.strava.stravaride
    case nikeRunClub     = "nike_run_club"   // com.nike.nikeplus-gps
    case peloton         // com.onepeloton.pelotoniphone
    case garmin          // com.garmin.connect.mobile
    case zwift           // com.zwift.zwiftapp
    case appleWatch      = "apple_watch"     // com.apple.*
    case fitbit          // com.fitbit.FitbitMobile
    case whoop           // com.whoop.iphone
    case oura            // com.ouraring.oura
    case mapMyRun        = "map_my_run"      // com.mapmyfitness.*
    case runkeeper       // com.fitnesskeeper.runkeeper
    case adidasRunning   = "adidas_running"  // com.runtastic.*
    case fit33           // this app (round-tripped via HealthKit, should be skipped)
    case unknown

    // MARK: - Mapping

    /// Map a HealthKit `(sourceName, sourceBundle)` tuple to a canonical origin.
    /// Prefers bundle ID (stable); falls back to case-insensitive name match.
    static func from(sourceName: String, sourceBundle: String?) -> WorkoutOrigin {
        let bundle = (sourceBundle ?? "").lowercased()
        let name = sourceName.lowercased()

        if bundle.contains("fit33") || name.contains("fit33") { return .fit33 }
        if bundle.contains("strava") || name.contains("strava") { return .strava }
        if bundle.contains("nike") || name.contains("nike") { return .nikeRunClub }
        if bundle.contains("peloton") || name.contains("peloton") { return .peloton }
        if bundle.contains("garmin") || name.contains("garmin") { return .garmin }
        if bundle.contains("zwift") || name.contains("zwift") { return .zwift }
        if bundle.contains("fitbit") || name.contains("fitbit") { return .fitbit }
        if bundle.contains("whoop") || name.contains("whoop") { return .whoop }
        if bundle.contains("ouraring") || bundle.contains("com.oura") || name.contains("oura") { return .oura }
        if bundle.contains("mapmyfitness") || bundle.contains("mapmyrun") || name.contains("map my") { return .mapMyRun }
        if bundle.contains("runkeeper") || name.contains("runkeeper") { return .runkeeper }
        if bundle.contains("runtastic") || name.contains("adidas running") || name.contains("runtastic") { return .adidasRunning }
        // Apple Watch / Fitness.app — bundle is "com.apple.health" on-device
        // when a workout was recorded by the watch/phone itself. Keep this
        // check LAST so it doesn't swallow third-party apps that happen to
        // write through Apple's frameworks.
        if bundle.hasPrefix("com.apple") || name == "watch" || name.contains("apple watch") || name.contains("fitness") {
            return .appleWatch
        }
        return .unknown
    }

    // MARK: - Display metadata

    /// Human-friendly label shown on the badge.
    var displayName: String {
        switch self {
        case .strava:         return "Strava"
        case .nikeRunClub:    return "Nike Run Club"
        case .peloton:        return "Peloton"
        case .garmin:         return "Garmin"
        case .zwift:          return "Zwift"
        case .appleWatch:     return "Apple Watch"
        case .fitbit:         return "Fitbit"
        case .whoop:          return "WHOOP"
        case .oura:           return "Oura"
        case .mapMyRun:       return "MapMyRun"
        case .runkeeper:      return "Runkeeper"
        case .adidasRunning:  return "adidas Running"
        case .fit33:          return "Fit33"
        case .unknown:        return "Health"
        }
    }

    /// SF Symbol used inside the badge capsule. Chosen to evoke the
    /// brand's identity when a literal logo isn't available as a system
    /// symbol (Apple only ships ~20 first-party brand glyphs).
    var badgeIcon: String {
        switch self {
        case .strava:         return "figure.run"              // running-first app
        case .nikeRunClub:    return "figure.run"
        case .peloton:        return "figure.indoor.cycle"     // bike-first brand
        case .garmin:         return "location.fill"           // GPS identity
        case .zwift:          return "figure.outdoor.cycle"    // virtual cycling
        case .appleWatch:     return "applewatch"              // native Apple glyph
        case .fitbit:         return "figure.walk"             // step tracker heritage
        case .whoop:          return "bolt.heart.fill"         // strain/recovery
        case .oura:           return "moon.stars.fill"         // sleep/readiness ring
        case .mapMyRun:       return "map.fill"
        case .runkeeper:      return "stopwatch.fill"
        case .adidasRunning:  return "figure.run"
        case .fit33:          return "dumbbell.fill"
        case .unknown:        return "heart.fill"              // generic Apple Health
        }
    }

    /// Brand-accurate gradient used by the badge capsule.
    /// Colors reference each service's published brand guidelines /
    /// official app icon palette. Keep gradients subtle (two-tone) so
    /// the badge stays readable in both light and dark mode.
    var badgeGradient: [Color] {
        switch self {
        case .strava:
            // Strava "Orange" #FC4C02 → slightly lighter highlight
            return [Color(red: 0xFC/255, green: 0x4C/255, blue: 0x02/255),
                    Color(red: 0xFF/255, green: 0x6A/255, blue: 0x1E/255)]
        case .nikeRunClub:
            // NRC uses pure black; add a faint warm highlight so the
            // gradient doesn't render as a flat rectangle.
            return [Color(white: 0.05), Color(white: 0.22)]
        case .peloton:
            // Peloton "Peloton Red" #DF2C35 on near-black.
            return [Color(red: 0x16/255, green: 0x16/255, blue: 0x16/255),
                    Color(red: 0xDF/255, green: 0x2C/255, blue: 0x35/255)]
        case .garmin:
            // Garmin corporate blue #007CC3 → lighter cyan tip.
            return [Color(red: 0x00/255, green: 0x7C/255, blue: 0xC3/255),
                    Color(red: 0x00/255, green: 0xA3/255, blue: 0xE0/255)]
        case .zwift:
            // Zwift orange #FC6719 → warm yellow-orange highlight.
            return [Color(red: 0xFC/255, green: 0x67/255, blue: 0x19/255),
                    Color(red: 0xFF/255, green: 0x95/255, blue: 0x1F/255)]
        case .appleWatch:
            // Apple space gray → silver.
            return [Color(red: 0x1D/255, green: 0x1D/255, blue: 0x1F/255),
                    Color(red: 0x86/255, green: 0x86/255, blue: 0x8B/255)]
        case .fitbit:
            // Fitbit teal #00B0B9 → slightly lighter cyan.
            return [Color(red: 0x00/255, green: 0xB0/255, blue: 0xB9/255),
                    Color(red: 0x1F/255, green: 0xD4/255, blue: 0xDC/255)]
        case .whoop:
            // WHOOP black with the signature red accent.
            return [Color(red: 0x0A/255, green: 0x0A/255, blue: 0x0A/255),
                    Color(red: 0xE1/255, green: 0x1D/255, blue: 0x48/255)]
        case .oura:
            // Oura deep plum/navy → muted silver accent.
            return [Color(red: 0x1A/255, green: 0x1A/255, blue: 0x2E/255),
                    Color(red: 0x4A/255, green: 0x3B/255, blue: 0x5E/255)]
        case .mapMyRun:
            // Under Armour red #CE0E2D.
            return [Color(red: 0xCE/255, green: 0x0E/255, blue: 0x2D/255),
                    Color(red: 0xF1/255, green: 0x3A/255, blue: 0x52/255)]
        case .runkeeper:
            // ASICS dark blue #002A5C with a warmer blue highlight.
            return [Color(red: 0x00/255, green: 0x2A/255, blue: 0x5C/255),
                    Color(red: 0x00/255, green: 0x55/255, blue: 0xA5/255)]
        case .adidasRunning:
            // adidas black + Runtastic orange #FF7100.
            return [Color(red: 0x0A/255, green: 0x0A/255, blue: 0x0A/255),
                    Color(red: 0xFF/255, green: 0x71/255, blue: 0x00/255)]
        case .fit33:
            // Fit33 brand accent gradient (orange → pink).
            return [.orange, .pink]
        case .unknown:
            // Apple Health heart — red → pink.
            return [Color(red: 0xFF/255, green: 0x2D/255, blue: 0x55/255),
                    Color(red: 0xFF/255, green: 0x5F/255, blue: 0x85/255)]
        }
    }

    /// Foreground color for text/icon inside the badge. Defaults to white;
    /// returns a dark color only for origins whose brand gradient is too
    /// light to carry white text.
    var badgeForeground: Color {
        switch self {
        default: return .white
        }
    }

    // MARK: - OAuth priority

    /// Does this origin have a first-party OAuth integration in Fit33 that
    /// writes to `cardio_workouts` directly? When the user has that OAuth
    /// connected we skip the HealthKit-imported duplicate.
    var hasFirstPartyOAuth: Bool {
        switch self {
        case .strava, .fitbit, .whoop, .oura: return true
        default: return false
        }
    }

    /// The `source` value written by the corresponding first-party OAuth
    /// integration (or `nil` if this origin has no OAuth).
    var oauthSourceKey: String? {
        switch self {
        case .strava: return "strava"
        case .fitbit: return "fitbit"
        case .whoop:  return "whoop"
        case .oura:   return "oura"
        default:      return nil
        }
    }
}

// MARK: - HealthKitWorkout sugar

extension HealthKitWorkout {
    /// Canonical origin inferred from `sourceName` / `sourceBundle`.
    var origin: WorkoutOrigin {
        WorkoutOrigin.from(sourceName: sourceName, sourceBundle: sourceBundle)
    }
}
