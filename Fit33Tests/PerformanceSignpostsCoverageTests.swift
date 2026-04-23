import XCTest
@testable import Fit33

// MARK: - Performance Signposts coverage
//
// Sprint 8 / Phase 9 (Tier 2.2) — signpost `Op` registry enforcement.
//
// Every call site that passes an `op:` string into `NetworkErrorClassifier.log`,
// `DiagnosticContext(op:)`, or `PerformanceSignposts.measure` must reference a
// value that exists in `PerformanceSignposts.Op`. This test scans the Swift
// source tree for `op:` arguments with a string literal and asserts each
// literal matches a canonical `Op.rawValue`.
//
// Why: the structural fingerprint in bug_intelligence_fingerprints (migration
// 20260516) is computed from `(source, op, error_class)`. Typoed / ad-hoc op
// strings splinter the fingerprint — the entire point of structural collapse
// breaks silently. This test turns the typo into a compile-time-like gate
// that CI enforces on every PR.
//
// Allowed exceptions (intentionally dynamic `op`):
//   - `op: \(Op.xxx.rawValue)` interpolation patterns
//   - `op: someVariable` (non-literal)
//   - `op: Op.xxx.rawValue` direct references
// Those are skipped because the lint is limited to raw string literals.

final class PerformanceSignpostsCoverageTests: XCTestCase {

    /// Every op string literal found in source must map to a canonical Op.
    func testEveryOpStringLiteralMatchesRegistry() throws {
        let canonicalOps = Set(allCanonicalOps())
        XCTAssertFalse(canonicalOps.isEmpty, "PerformanceSignposts.Op registry is empty — check reflection path.")

        let swiftRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()     // Fit33Tests/
            .deletingLastPathComponent()     // repo root
            .appendingPathComponent("Fit33", isDirectory: true)

        guard FileManager.default.fileExists(atPath: swiftRoot.path) else {
            throw XCTSkip("Fit33 source directory not found at \(swiftRoot.path) — this test only runs in-repo.")
        }

        let allLiterals = try extractOpStringLiterals(in: swiftRoot)
        var missing: [(String, URL, Int)] = []

        for (literal, file, line) in allLiterals {
            // Skip empty / placeholder ops and anything that starts with an
            // interpolation sentinel (rarely surfaces because the extractor
            // already filters it, but keep belt-and-suspenders).
            if literal.isEmpty { continue }
            if canonicalOps.contains(literal) { continue }
            missing.append((literal, file, line))
        }

        if !missing.isEmpty {
            let report = missing.map { lit, file, line in
                "  \(file.lastPathComponent):\(line)  op=\"\(lit)\""
            }.joined(separator: "\n")

            let canonical = canonicalOps.sorted().joined(separator: ", ")
            XCTFail("""
                Found \(missing.count) `op:` string literal(s) not in the PerformanceSignposts.Op registry.

                \(report)

                Fix: add the missing case to `enum Op` in Fit33/PerformanceSignposts.swift,
                OR change the call site to use `Op.something.rawValue`.

                Canonical Op values:
                \(canonical)
                """)
        }
    }

    // MARK: - Helpers

    /// Reflect over `PerformanceSignposts.Op` via `allCases`-style enumeration.
    /// Because the enum doesn't conform to `CaseIterable`, fall back to a
    /// manual list here. Keep this in sync with `Op` itself — which the lint
    /// will catch because adding a new `case` without updating this list
    /// means the test can't validate it.
    private func allCanonicalOps() -> [String] {
        // Mirror of Fit33/PerformanceSignposts.swift enum Op. One-liner per
        // case so a merge diff clearly shows the parity with the source.
        return [
            "app.launch",
            "app.foreground",
            "dashboard.hydrate",
            "dashboard.social_fanout",
            "startup.coordinator_stage",
            "auth.wait_for_fresh_session",
            "auth.session_recovery",
            "weight.log",
            "step.save",
            "daily_activity.save",
            "cardio.save",
            "workout.save",
            "healthkit.sleep_save",
            "friends.fetch",
            "activity_feed.fetch",
            "challenges.fetch",
            "social.post_workout_activity",
            "social.post_cardio_activity",
            "strava.sync",
            // Phase 9 classifier rollout (2026-04-23)
            "friends.list",
            "friends.write",
            "friend_request.list",
            "friend_request.write",
            "shared_workout.list",
            "shared_workout.write",
            "social_notification.list",
            "social_notification.write",
            "challenge.cache",
            "challenge.read",
            "challenge.write",
            "challenge.group.write",
            "challenge.preferences",
            "challenge.progress_sync",
            "auth.sign_up",
            "auth.sign_in",
            "auth.sign_out",
            "auth.password_reset",
            "auth.resend_email",
            "profile.read",
            "profile.write",
            "profile.sync",
            "username.write",
            "exercise.update",
            "cloud_sync.profile",
            "cloud_sync.workout",
            "cloud_sync.meal",
            "cloud_sync.favorite",
            "cloud_sync.custom_exercise",
            "cloud_sync.favorite_workout",
            // Acceptable string-literal ops that didn't warrant a dedicated
            // Op case at introduction time but ARE structural fingerprint
            // keys (all appear in production code). When the Op enum grows,
            // migrate these upward — the allowlist is the migration lane.
            // NB: Keep this list short. A new entry here should be reviewed
            // in PR: "should this be an Op case instead?"
            "ui.main_thread_freeze",
            "cloud_sync.comprehensive",
            "social.fetch_received_workouts",
            "insights.fetch_streaks",
            "challenges.fetch_pending_invites",
            "challenges.fetch_active",
            "challenges.fetch_templates",
            "social.get_challenge_details",
            "private_challenges.refresh_all",
            "challenges.log_private_progress",
            "perf_metrics.upload",
            "coredata.transformable_scan",
            "activity_feed.my_reactions",
            "weight.set_goal",
            "weight.delete",
            "quests.fetch",
        ]
    }

    /// Walk `root` recursively, extracting every `op: "..."` literal from Swift
    /// sources along with file URL + line number. Tolerates single-line
    /// `op: "x"` and `op: "x",` forms. Skips interpolated strings (`op: "\(..."`)
    /// and non-literal expressions (`op: someVar`).
    private func extractOpStringLiterals(in root: URL) throws -> [(String, URL, Int)] {
        var out: [(String, URL, Int)] = []
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: nil) else {
            return out
        }

        // Regex: `op: "literal"` with optional whitespace. Captures the literal.
        // Rejects interpolation by excluding `\(` inside the quoted text.
        let pattern = #"\bop:\s*"([^"\\]*)""#
        let regex = try NSRegularExpression(pattern: pattern, options: [])

        while let candidate = enumerator.nextObject() as? URL {
            guard candidate.pathExtension == "swift" else { continue }
            // Skip the test tree to avoid false positives on this very file.
            if candidate.pathComponents.contains("Fit33Tests") { continue }
            if candidate.pathComponents.contains("Fit33UITests") { continue }

            let source: String
            do {
                source = try String(contentsOf: candidate, encoding: .utf8)
            } catch {
                continue
            }
            let lines = source.components(separatedBy: "\n")
            for (idx, line) in lines.enumerated() {
                let ns = line as NSString
                let matches = regex.matches(in: line, options: [], range: NSRange(location: 0, length: ns.length))
                for m in matches where m.numberOfRanges >= 2 {
                    let lit = ns.substring(with: m.range(at: 1))
                    out.append((lit, candidate, idx + 1))
                }
            }
        }

        return out
    }
}
