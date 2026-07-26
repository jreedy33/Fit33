import Foundation

// MARK: - Legal URLs
//
// Canonical destinations for the App Review 3.1.2-mandated paywall
// disclosures (Privacy Policy + Terms of Use). Every paywall surface
// — `PremiumUpgradeView`, `PaywallFirstScreenView`, and any future
// paywall — MUST link to both via these constants. Centralized so a
// URL change is a one-file diff and never drifts between surfaces.
//
// NOTE (2026-05-10): Placeholder URLs match the existing Fit33 web
// domain (`https://fit33.app/...`). If the canonical pages live at a
// different path, swap them here and every paywall picks it up.
enum LegalURLs {
    // Audit PR-36: no force unwraps in production code — these literals are
    // valid by construction, but route through a checked helper anyway so
    // a future typo fails loudly in DEBUG instead of crashing in release.
    static let privacy = makeURL("https://fit33.app/privacy")
    static let terms   = makeURL("https://fit33.app/terms")

    private static func makeURL(_ string: String) -> URL {
        guard let url = URL(string: string) else {
            assertionFailure("LegalURLs: invalid URL literal \(string)")
            return URL(fileURLWithPath: "/")
        }
        return url
    }
}
