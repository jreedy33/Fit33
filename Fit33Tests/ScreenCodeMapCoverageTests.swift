import XCTest
@testable import Fit33

// MARK: - ScreenCodeMap coverage
//
// Phase 12b / 2026-04-24 — enforce the rage-shake screen → code file
// map invariant at test time. Without this, a developer can add a
// new `SessionLogManager.Screen` case, wire a `.trackScreen(.xxx)`
// into their view, and forget to add the matching `ScreenCodeMap`
// entry — resulting in a rage-shake that routes Claude to an empty
// file list (only the foundational context). The test fails the
// build in that case with a clear list of missing entries.
//
// Three invariants enforced:
//
//   1. Every non-`.unknown` `Screen.displayName` must resolve to at
//      least one non-empty primary file list in `ScreenCodeMap`.
//      (Exact match or substring fallback, same logic the runtime
//      uses.)
//
//   2. Every file referenced in `ScreenCodeMap.table` or
//      `foundationalFiles` must exist on disk. A typo'd path or a
//      file that was renamed/deleted shows up as a 0-file match at
//      rage-shake time — this test catches it at CI time instead.
//
//   3. Every `Screen` case with a `.trackScreen(.xxx)` call site MUST
//      have a map entry. (Verified indirectly via #1 above.)
//
// Test category: LogicAudit (same tier as the signpost registry test).
// Runs in every CI pass via `ios-unit-tests.yml`.

final class ScreenCodeMapCoverageTests: XCTestCase {

    // MARK: - Invariant 1: every Screen case resolves to primary files

    func testEveryScreenCaseHasAMapEntry() throws {
        // `.unknown` is intentionally unmapped — it's the fallback that
        // returns only foundational files.
        let cases = SessionLogManager.Screen.allCases.filter { $0 != .unknown }

        var missing: [String] = []
        for screen in cases {
            let primary = ScreenCodeMap.screenSpecificFiles(screen.displayName)
            if primary.isEmpty {
                missing.append("\(screen)  (\"\(screen.displayName)\")")
            }
        }

        if !missing.isEmpty {
            XCTFail("""
                ScreenCodeMap is missing entries for \(missing.count) Screen case(s):

                \(missing.joined(separator: "\n"))

                Each case must have a matching `ScreenCodeMap.table` key
                (display name, case-insensitive). Example:

                    "private challenge detail": [
                        "Fit33/PrivateChallengeDetailView.swift",
                        "Fit33/PrivateChallengeService.swift",
                    ],

                See Fit33/ScreenCodeMap.swift for the full map + invariant
                docs. Phase 12b (2026-04-24) required every enum case to
                have a map entry so rage-shake always routes Claude to
                relevant files.
                """
            )
        }
    }

    // MARK: - Invariant 2: every referenced file exists on disk

    func testEveryMappedFileExistsOnDisk() throws {
        let projectRoot = findProjectRoot()
        guard let root = projectRoot else {
            throw XCTSkip("Could not locate project root (Fit33.xcodeproj)")
        }

        var allPaths = Set<String>()
        for key in ScreenCodeMap.mappedDisplayNameKeys {
            let files = ScreenCodeMap.screenSpecificFiles(key)
            allPaths.formUnion(files)
        }
        allPaths.formUnion(ScreenCodeMap.foundationalFilesList)

        var missing: [String] = []
        for p in allPaths.sorted() {
            let absolute = root.appendingPathComponent(p).path
            if !FileManager.default.fileExists(atPath: absolute) {
                missing.append(p)
            }
        }

        if !missing.isEmpty {
            XCTFail("""
                ScreenCodeMap references \(missing.count) file(s) that do
                not exist on disk:

                \(missing.joined(separator: "\n"))

                Either the file was renamed/deleted and the map is stale,
                OR there is a typo in the entry. Update
                Fit33/ScreenCodeMap.swift accordingly. This invariant
                prevents silent context-drop at rage-shake time —
                Claude would see fewer files than expected without this
                guard catching the typo at PR time.
                """
            )
        }
    }

    // MARK: - Invariant 3: filesForScreen always includes foundational

    func testFilesForScreenAlwaysIncludesFoundational() throws {
        // Pick a mid-complexity screen — Private Challenge Detail has
        // 4 primary files, foundational adds 5, combined 9 — well
        // under the 12-file cap so nothing gets trimmed.
        let files = ScreenCodeMap.filesForScreen("Private Challenge Detail")
        XCTAssertFalse(files.isEmpty, "Private Challenge Detail should resolve to a non-empty list")
        for f in ScreenCodeMap.foundationalFilesList {
            XCTAssertTrue(files.contains(f), "Expected foundational file \(f) in rage-shake context, got \(files)")
        }
    }

    /// Edge case: unmapped screen name still returns foundational-only
    /// so Claude never gets a totally empty context.
    func testUnmappedScreenStillReturnsFoundational() throws {
        let files = ScreenCodeMap.filesForScreen("Completely Made Up Screen Name Xyz123")
        XCTAssertEqual(Set(files), Set(ScreenCodeMap.foundationalFilesList),
                       "Unmapped screens should fall back to foundational files only.")
    }

    // MARK: - Helpers

    /// Walk up from the test binary's bundle until we find
    /// `Fit33.xcodeproj` — that's the project root used to resolve
    /// relative `Fit33/…` paths in the map.
    private func findProjectRoot() -> URL? {
        var url = URL(fileURLWithPath: #file)  // this test file
        for _ in 0..<10 {
            let candidate = url.appendingPathComponent("Fit33.xcodeproj")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return url
            }
            let parent = url.deletingLastPathComponent()
            if parent == url { break }
            url = parent
        }
        return nil
    }
}
