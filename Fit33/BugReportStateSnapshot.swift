import Foundation

// MARK: - Bug Report State Snapshot — Phase 7 / Cheat Code
//
// The "cheat code" for high-accuracy bug triage: capture the runtime
// state of key `ObservableObject` singletons at the exact moment the
// user shakes to report a bug. Feed it to Claude as a structured
// evidence block alongside the screenshot + session log.
//
// Most iOS silent-logic bugs (Dashboard widget shows 199 / Nutrition
// widget shows 190) are state-sync bugs whose smoking gun is two
// divergent published values. Claude is mediocre at reasoning over
// Swift source files blind, but world-class at diffing structured
// state. This file wires that up.
//
// Contract:
//   - Every service that wants to contribute to the snapshot conforms
//     to `SnapshotProvider` and registers itself via
//     `BugReportSnapshotter.shared.register(...)`.
//   - Providers return a FLAT `[String: SnapshotValue]` of short,
//     PII-safe, JSON-serializable fields. Nested arrays collapse to
//     `{count, first, last}`.
//   - `BugReportSnapshotter.buildSnapshot()` aggregates them into a
//     `[String: [String: Any]]` keyed by `snapshotKey`, ready for
//     encoding into `bug_reports.state_snapshot JSONB`.
//   - The `guardMainActor` wrapper runs every provider on the main
//     actor because most of our @Published singletons are MainActor-
//     isolated. `buildSnapshot()` itself must therefore be called from
//     an @MainActor context.
//
// PII rules (enforced per-provider, audited here):
//   - NEVER include email, phone number, auth tokens, real names of
//     contacts/friends, raw device IDs, or message content. Server-
//     side triage already gets user email/name via user_profiles
//     enrichment — we don't need to double-ship it.
//   - IDs like UUIDs of local logs/weight records ARE OK (they're
//     ephemeral, scoped to one user, and invaluable for spotting
//     divergence like "todayLog.id ≠ recentLogs.first.id").
//
// Ordering / dependency note:
//   Registration happens lazily the first time a provider's
//   `contributeSnapshot()` is called (via
//   `BugReportSnapshotter.shared.register(_:)` from each service's
//   init). The snapshotter is a plain Swift struct of closures — no
//   protocol witness tables to mis-type across modules.

// MARK: - SnapshotValue

/// A lightweight envelope for the scalar/short types allowed in a
/// snapshot. Keeping the type closed means we can audit PII at call
/// sites AND cheaply encode to JSON at snapshot-build time.
enum SnapshotValue: Encodable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case strings([String])
    case doubles([Double])

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let v): try c.encode(v)
        case .int(let v): try c.encode(v)
        case .double(let v):
            // JSONEncoder encodes NaN/Inf as error by default; coerce
            // to null so a single bad field can't break the whole
            // payload (shake already a stressful moment, don't fail).
            if v.isFinite { try c.encode(v) } else { try c.encodeNil() }
        case .string(let v): try c.encode(v)
        case .strings(let v): try c.encode(v)
        case .doubles(let v):
            try c.encode(v.map { $0.isFinite ? $0 : .nan }.filter { $0.isFinite })
        }
    }
}

// MARK: - SnapshotProvider

/// Conformance is tiny on purpose. A service exposes a stable
/// `snapshotKey` (e.g. "WeightTrackingService") and returns a flat
/// dict of published values that would reveal a divergence if
/// something's wrong.
protocol SnapshotProvider: AnyObject {
    /// Stable identifier shown in Claude prompts and CMS viewer.
    /// Must match `String(describing: Self.self)` in most cases.
    var snapshotKey: String { get }

    /// Return the values that would help a triage agent diagnose a
    /// silent-logic bug in this service. Keep it to ~5–15 fields.
    /// Called on the MainActor — safe to read `@Published` properties
    /// directly.
    @MainActor
    func contributeSnapshot() -> [String: SnapshotValue]
}

// MARK: - Snapshotter

/// Collects registered providers, builds a single JSON-serializable
/// payload at shake time.
@MainActor
final class BugReportSnapshotter {
    static let shared = BugReportSnapshotter()

    // We hold providers as weak to avoid leaking singletons via this
    // registry — though every current provider IS a true singleton
    // (static shared) so leak risk is moot. Keeping `weak` makes it
    // safe to use for non-singleton providers in the future without
    // a rethink.
    private struct Box {
        weak var provider: SnapshotProvider?
    }
    private var registry: [Box] = []

    private init() {}

    /// Call from a service's init (or lazily on first use). Safe to
    /// call multiple times — re-registers silently.
    func register(_ provider: SnapshotProvider) {
        // Dedupe by key + identity. We can have two different objects
        // claiming the same key (bad) — log a warning but overwrite.
        let key = provider.snapshotKey
        if let existing = registry.firstIndex(where: {
            $0.provider?.snapshotKey == key
        }) {
            if registry[existing].provider === provider { return }
            registry[existing] = Box(provider: provider)
            AppLogger.warning(
                "[Snapshot] Overwrote existing provider for key '\(key)'",
                category: .general
            )
            return
        }
        registry.append(Box(provider: provider))
    }

    /// Build the aggregate snapshot. Safe to call from ANY bug-report
    /// submission path (shake / manual / settings). Returns `nil` if
    /// no providers are registered (shouldn't happen in a booted app,
    /// but the edge function tolerates missing state_snapshot anyway).
    func buildSnapshot() -> [String: Any]? {
        // Lazy bootstrap — cheap to call repeatedly (register() dedupes
        // by key). Keeping it here means services don't need to edit
        // their init() to participate; the snapshotter knows the list.
        registerAll()

        // Prune dead weak refs.
        registry.removeAll { $0.provider == nil }
        if registry.isEmpty { return nil }

        var result: [String: Any] = [:]
        // Capture a shake-time wall clock so Claude can reason about
        // age of values (e.g. "recentLogs.lastLoad was 45s ago").
        result["__captured_at"] = ISO8601DateFormatter().string(from: Date())

        for box in registry {
            guard let p = box.provider else { continue }
            let key = p.snapshotKey
            let values = p.contributeSnapshot()
            if values.isEmpty { continue }

            // Encode each SnapshotValue to a JSON-compatible primitive
            // so the whole thing fits into JSONEncoder / PostgREST
            // JSONB without further massage.
            var dict: [String: Any] = [:]
            for (k, v) in values {
                dict[k] = jsonPrimitive(v)
            }
            result[key] = dict
        }
        return result
    }

    /// Convert a `SnapshotValue` to a JSON-compatible primitive.
    private func jsonPrimitive(_ v: SnapshotValue) -> Any {
        switch v {
        case .null: return NSNull()
        case .bool(let b): return b
        case .int(let i): return i
        case .double(let d): return d.isFinite ? d : NSNull()
        case .string(let s): return s
        case .strings(let arr): return arr
        case .doubles(let arr): return arr.filter { $0.isFinite }
        }
    }

    // MARK: - Helpers for providers

    /// Collapse a long array to a triage-useful shape (count + first +
    /// last) to avoid bloating the snapshot with N-item raw arrays.
    static func arrayShape<T>(
        _ array: [T],
        firstKey: String,
        lastKey: String,
        countKey: String,
        map: (T) -> SnapshotValue
    ) -> [String: SnapshotValue] {
        var out: [String: SnapshotValue] = [
            countKey: .int(array.count)
        ]
        if let f = array.first { out[firstKey] = map(f) }
        if let l = array.last, array.count > 1 { out[lastKey] = map(l) }
        return out
    }
}
