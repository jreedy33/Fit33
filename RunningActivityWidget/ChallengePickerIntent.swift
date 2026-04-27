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
struct ChallengeEntity: AppEntity, Identifiable, Hashable {
    let id: String
    let opponentName: String
    let title: String
    let typeEmoji: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Active Challenge")
    }
    static var defaultQuery = ChallengeQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(typeEmoji) vs \(opponentName)",
            subtitle: "\(title)"
        )
    }
}

struct ChallengeQuery: EntityQuery {
    func entities(for identifiers: [ChallengeEntity.ID]) async throws -> [ChallengeEntity] {
        let all = await Self.readAllWithFallback()
        let wanted = Set(identifiers)
        return all
            .filter { wanted.contains($0.challengeId) }
            .map(Self.entity(from:))
    }

    func suggestedEntities() async throws -> [ChallengeEntity] {
        await Self.readAllWithFallback().map(Self.entity(from:))
    }

    func defaultResult() async -> ChallengeEntity? {
        // Default to the auto-pick (urgency-first) so users get something
        // sensible the moment they install the widget.
        if let pick = ActiveChallengeWidgetSnapshot.read() {
            return Self.entity(from: pick)
        }
        return await Self.readAllWithFallback().first.map(Self.entity(from:))
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
