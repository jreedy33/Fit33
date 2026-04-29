//
//  ChallengePickerIntent.swift
//  RunningActivityWidget
//
//  Powers the "Edit Widget" picker on the home screen so the user can
//  choose which 1v1 challenge to display (e.g. show Abbie's matchup
//  instead of Paul's). The `EntityQuery` reads the list of active
//  challenges that the main app's `ActiveChallengeWidgetBridge` writes
//  into the App Group every time `ChallengeService` updates.
//

import AppIntents
import WidgetKit

/// One row in the widget configuration's "Challenge" dropdown.
///
/// Equality is keyed to `id` ONLY (not the synthesized all-fields hash).
/// Bug-intel 2026-04-28 — auto-Hashable hashed `opponentName + title +
/// typeEmoji` too, so a tiny `displayTitle` change between cache snapshots
/// (e.g. server tweaked the challenge title, or a fresh pull stamped a
/// slightly different formatting) made iOS treat the same entity as
/// "different" for picker selection-tracking, causing the dropdown to
/// visibly drop the user's selection mid-edit.
struct ChallengeEntity: AppEntity, Identifiable, Hashable {
    /// Stable sentinel ID used by the "Auto-pick" picker option. When
    /// the widget configuration carries this ID (or `nil`), the timeline
    /// resolves to whatever the bridge most recently wrote as the
    /// urgency-sorted "best pick". Identity NEVER changes regardless of
    /// what's in the App Group cache — this is what fixes the picker
    /// visibly flipping between Paul and Manuel as the auto-pick rotated
    /// underneath the user's selection.
    static let autoPickID = "fit33.widget.challenge.autopick.v1"

    /// Single shared sentinel entity surfaced as the first option in the
    /// dropdown AND returned from `defaultResult()` so iOS's "Reset"
    /// button reverts to a stable Auto value instead of snapping back
    /// to whatever specific challenge happens to be the current
    /// auto-pick.
    static let autoPick = ChallengeEntity(
        id: autoPickID,
        opponentName: "Auto-pick",
        title: "Most urgent challenge",
        typeEmoji: "🏆"
    )

    let id: String
    let opponentName: String
    let title: String
    let typeEmoji: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Active Challenge")
    }
    static var defaultQuery = ChallengeQuery()

    var displayRepresentation: DisplayRepresentation {
        if id == ChallengeEntity.autoPickID {
            return DisplayRepresentation(
                title: "🏆 Auto-pick",
                subtitle: "Most urgent challenge"
            )
        }
        return DisplayRepresentation(
            title: "\(typeEmoji) vs \(opponentName)",
            subtitle: "\(title)"
        )
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: ChallengeEntity, rhs: ChallengeEntity) -> Bool {
        lhs.id == rhs.id
    }
}

struct ChallengeQuery: EntityQuery {
    func entities(for identifiers: [ChallengeEntity.ID]) async throws -> [ChallengeEntity] {
        var results: [ChallengeEntity] = []
        let wanted = Set(identifiers)
        // The Auto-pick sentinel never appears in the App Group cache —
        // it's a virtual entity. Materialize it directly when iOS asks
        // for it so the picker can render the user's "Auto" selection
        // instead of falling back to defaultResult() (which would also
        // return Auto, but iOS's selection-tracking gets confused when
        // entities(for:) returns empty for a known-selected ID).
        if wanted.contains(ChallengeEntity.autoPickID) {
            results.append(.autoPick)
        }
        let all = await Self.readAllWithFallback()
        results.append(contentsOf:
            all.filter { wanted.contains($0.challengeId) }
                .map(Self.entity(from:))
        )
        return results
    }

    func suggestedEntities() async throws -> [ChallengeEntity] {
        // Auto-pick lives at the top of the dropdown so users always
        // have a "let the widget choose" option that's stable across
        // cache rotations. The specific challenges follow in the order
        // the bridge published them (urgency-first).
        let challenges = await Self.readAllWithFallback().map(Self.entity(from:))
        return [.autoPick] + challenges
    }

    func defaultResult() async -> ChallengeEntity? {
        // Always return the Auto-pick sentinel. Its identity is FIXED
        // across timeline ticks, so iOS's "Reset" button reverts to a
        // stable "auto" value instead of flipping between specific
        // challenges as the bridge's urgency-sorted "best pick" rotates.
        // The actual challenge resolution happens at render time in
        // `ActiveChallengeProvider.entry(for:)` via
        // `ActiveChallengeWidgetSnapshot.resolve(challengeId:)`, which
        // already falls back to `read()` (the auto-pick) for any
        // unknown ID — so the sentinel "just works" without further
        // changes to the timeline path.
        .autoPick
    }

    /// Cache-first read with a direct-Supabase fallback when the App Group
    /// is empty. Bug-intel 2026-04-27 (Manuel — widget edit sheet
    /// "Challenge" picker stuck on "Loading…" then snaps back):
    ///   The picker query path used to be cache-only, which meant an
    ///   empty App Group blob (e.g. user installed the widget before
    ///   ever foregrounding the main app, OR the main app got force-
    ///   killed before its first publish, OR realtime fired before
    ///   Bridge.publish landed) showed `[]` and iOS rendered "Loading…"
    ///   followed by an empty dropdown.
    ///
    ///   The timeline path (`ActiveChallengeProvider.pullAndMergeIfPossible`)
    ///   already does a direct Supabase pull from inside the widget
    ///   process and writes the result to the App Group — so the home-
    ///   screen tile rendered fine while the picker was broken. We
    ///   reuse that exact code path here so there's only ONE pull
    ///   implementation, ONE App Group write, and ONE Phase-5 Darwin
    ///   notification on success (which keeps the main app in sync).
    ///
    ///   Timeout: 3.0s mirrors the timeline budget. iOS's
    ///   AppIntent picker query has a soft ~5s wall-clock budget before
    ///   it falls back to the placeholder, so 3s leaves headroom for
    ///   JSON decode + entity mapping. If the pull misses the deadline
    ///   OR errors (notAuthenticated, transport, 401, etc.), we fall
    ///   back to whatever's still in the cache — usually `[]`, which
    ///   renders an empty dropdown rather than hanging.
    private static func readAllWithFallback() async -> [ActiveChallengeWidgetSnapshot.WidgetActiveChallenge] {
        let cached = ActiveChallengeWidgetSnapshot.readAll()
        if !cached.isEmpty { return cached }
        await ActiveChallengeProvider.pullAndMergeIfPossible(timeoutSeconds: 3.0)
        return ActiveChallengeWidgetSnapshot.readAll()
    }

    private static func entity(from challenge: ActiveChallengeWidgetSnapshot.WidgetActiveChallenge) -> ChallengeEntity {
        ChallengeEntity(
            id: challenge.challengeId,
            opponentName: challenge.opponentFirstName,
            title: challenge.displayTitle,
            typeEmoji: ChallengeWidgetPalette.emoji(for: challenge.challengeType)
        )
    }
}

/// Background treatment for the active challenge widget. Surfaced as a
/// dropdown in the widget edit sheet so the user can match their home
/// screen vibe.
enum WidgetBackgroundStyle: String, AppEnum {
    /// Dark base heavily tinted by the challenge type color (default —
    /// matches the in-app challenge card).
    case color
    /// Near-black background with a soft glow of the challenge color.
    case dark
    /// Light grey background with a soft glow of the challenge color.
    case light

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Background Style")
    }

    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .color: DisplayRepresentation(title: "Color", subtitle: "Tinted by challenge color"),
        .dark:  DisplayRepresentation(title: "Dark",  subtitle: "Black with colored glow"),
        .light: DisplayRepresentation(title: "Light", subtitle: "Grey with colored glow")
    ]
}

/// Intent the widget configuration UI uses to capture the user's choice.
struct ChallengePickerIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Active Challenge"
    static var description = IntentDescription("Pick which 1v1 challenge the widget displays.")

    @Parameter(title: "Challenge")
    var challenge: ChallengeEntity?

    @Parameter(title: "Background", default: .color)
    var style: WidgetBackgroundStyle
}
