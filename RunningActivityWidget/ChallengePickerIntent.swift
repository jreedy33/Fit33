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
        let all = ActiveChallengeWidgetSnapshot.readAll()
        let wanted = Set(identifiers)
        return all
            .filter { wanted.contains($0.challengeId) }
            .map(Self.entity(from:))
    }

    func suggestedEntities() async throws -> [ChallengeEntity] {
        ActiveChallengeWidgetSnapshot.readAll().map(Self.entity(from:))
    }

    func defaultResult() async -> ChallengeEntity? {
        // Default to the auto-pick (urgency-first) so users get something
        // sensible the moment they install the widget.
        if let pick = ActiveChallengeWidgetSnapshot.read() {
            return Self.entity(from: pick)
        }
        return ActiveChallengeWidgetSnapshot.readAll().first.map(Self.entity(from:))
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
