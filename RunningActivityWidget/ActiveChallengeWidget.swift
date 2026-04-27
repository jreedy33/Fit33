//
//  ActiveChallengeWidget.swift
//  RunningActivityWidget
//
//  Home-screen widget that mirrors the in-app `activeChallengeDetailWidget`
//  card. Pulls the top 1v1 challenge snapshot from the App Group store
//  (written by the main app's `ActiveChallengeWidgetBridge` whenever
//  `ChallengeService.activeChallenges` updates).
//

import AppIntents
import WidgetKit
import SwiftUI
import OSLog

// MARK: - Timeline Provider

struct ActiveChallengeProvider: AppIntentTimelineProvider {
    typealias Intent = ChallengePickerIntent
    typealias Entry = ActiveChallengeEntry

    private static let log = Logger(subsystem: "com.fit33.app.RunningActivityWidget", category: "challenge-timeline")

    func placeholder(in context: Context) -> ActiveChallengeEntry {
        ActiveChallengeEntry(date: Date(), challenge: ActiveChallengeWidgetSnapshot.placeholder, userPhoto: nil, opponentPhoto: nil, style: .color)
    }

    func snapshot(for configuration: ChallengePickerIntent, in context: Context) async -> ActiveChallengeEntry {
        // `snapshot` is invoked by iOS for the widget gallery + Add-Widget
        // preview. iOS gives this path a hard ~5s budget AND retries
        // aggressively if it stalls — so we deliberately keep it
        // sync/cache-only (no Supabase call) and let the timeline path
        // do the network pull on the user's home screen instead.
        Self.entry(for: configuration)
    }

    func timeline(for configuration: ChallengePickerIntent, in context: Context) async -> Timeline<ActiveChallengeEntry> {
        // Realtime Widget Server Pull, Phase 3 (2026-04-26):
        //
        // Each timeline tick now races a 3s direct Supabase pull against
        // the App Group cache. Whatever lands first writes the entry; if
        // the pull beats the deadline AND its hash differs from the
        // cache, we also write the fresh payload back to the App Group
        // so the main app picks it up via the Phase-5 Darwin notification.
        //
        // Why 3s (not the fetcher's 8s default):
        //   • Timeline policies can fire while the user is actively
        //     scrolling — a long-tailed call would visibly hang the
        //     widget render pipeline.
        //   • Beyond 3s, iOS may already be tearing down the extension.
        //   • If the pull misses the deadline we still render — just
        //     from cache — so the budget loss is "no fresh data this
        //     tick" not "blank widget".
        await Self.pullAndMergeIfPossible(timeoutSeconds: 3.0)
        let nowEntry = Self.entry(for: configuration)

        // Bug-intel 80234a6b (2026-04-27): widget should reflect 0 progress
        // immediately at the local-day rollover instead of holding yesterday's
        // value until the next 20-min tick. Build a synthetic midnight entry
        // with today's progress reset to 0; iOS automatically picks whichever
        // entry's `date` is closest-but-not-after `now()`, so this entry only
        // becomes the rendered one at exactly local midnight.
        let now = Date()
        let cal = Calendar.current
        let nextMidnight = cal.nextDate(
            after: now,
            matching: DateComponents(hour: 0, minute: 0, second: 0),
            matchingPolicy: .nextTime
        ) ?? now.addingTimeInterval(24 * 3600)

        let midnightEntry = Self.midnightResetEntry(from: nowEntry, at: nextMidnight)

        // Refresh policy: whichever comes sooner — 20 min from now, OR
        // 5 min after midnight (so we pull fresh server data shortly
        // after the rollover and replace the synthetic reset entry with
        // a real one). 20 min keeps us well under iOS's per-widget
        // reload budget (40-70/day) for users with stable timelines.
        let twentyMinFromNow = now.addingTimeInterval(20 * 60)
        let fiveMinAfterMidnight = nextMidnight.addingTimeInterval(5 * 60)
        let nextRefresh = min(twentyMinFromNow, fiveMinAfterMidnight)

        return Timeline(entries: [nowEntry, midnightEntry], policy: .after(nextRefresh))
    }

    /// Construct a "midnight reset" timeline entry by cloning the current
    /// entry but zeroing both participants' today-progress. iOS displays
    /// this entry starting at exactly `midnight` until the next refresh
    /// fires (~5 min later). The Phase 7c live-HK overlay re-evaluates at
    /// render time, so step-typed challenges also pick up any literal
    /// post-midnight steps if the user is walking right at the rollover.
    private static func midnightResetEntry(
        from base: ActiveChallengeEntry,
        at midnight: Date
    ) -> ActiveChallengeEntry {
        guard let baseChallenge = base.challenge else {
            // No active challenge — empty state at midnight is identical
            // to empty state now; just stamp the future date.
            return ActiveChallengeEntry(
                date: midnight,
                challenge: nil,
                userPhoto: base.userPhoto,
                opponentPhoto: base.opponentPhoto,
                style: base.style
            )
        }

        let resetChallenge = ActiveChallengeWidgetSnapshot.WidgetActiveChallenge(
            challengeId: baseChallenge.challengeId,
            challengeType: baseChallenge.challengeType,
            displayTitle: baseChallenge.displayTitle,
            mode: baseChallenge.mode,
            targetUnit: baseChallenge.targetUnit,
            dailyTarget: baseChallenge.dailyTarget,
            // daysRemaining decrements at midnight — but only by 1, and
            // the client-rendered countdown can derive it. Pass through
            // the existing value; the post-midnight refresh tick fires
            // 5 min later and will pull the authoritative value.
            daysRemaining: max(0, baseChallenge.daysRemaining - 1),
            durationDays: baseChallenge.durationDays,
            myTodayProgress: 0,
            opponentTodayProgress: 0,
            opponentId: baseChallenge.opponentId,
            opponentName: baseChallenge.opponentName,
            opponentPhotoUrl: baseChallenge.opponentPhotoUrl,
            opponentIsVerified: baseChallenge.opponentIsVerified,
            opponentIsGoldVerified: baseChallenge.opponentIsGoldVerified,
            myCurrentStreak: baseChallenge.myCurrentStreak,
            // amWinningToday at 0–0 → tied, neither is "winning"; render
            // accordingly. The 5-min post-midnight refresh corrects this
            // once real progress arrives.
            amWinningToday: false,
            myDisplayName: baseChallenge.myDisplayName,
            hasUserPhoto: baseChallenge.hasUserPhoto,
            hasOpponentPhoto: baseChallenge.hasOpponentPhoto,
            // Clear last-progress-at so the freshness pill reads
            // "— · just now" (Phase 6 unknown==fresh contract) at
            // midnight rather than "— · 8h ago" from yesterday's row.
            myLastProgressAt: nil,
            opponentLastProgressAt: nil
        )

        return ActiveChallengeEntry(
            date: midnight,
            challenge: resetChallenge,
            userPhoto: base.userPhoto,
            opponentPhoto: base.opponentPhoto,
            style: base.style
        )
    }

    private static func entry(for configuration: ChallengePickerIntent) -> ActiveChallengeEntry {
        let resolved = ActiveChallengeWidgetSnapshot.resolve(challengeId: configuration.challenge?.id)
        let opponentPhoto: UIImage? = resolved.flatMap {
            ActiveChallengeWidgetSnapshot.opponentPhoto(opponentId: $0.opponentId)
        }
        return ActiveChallengeEntry(
            date: Date(),
            challenge: resolved,
            userPhoto: ActiveChallengeWidgetSnapshot.userPhoto(),
            opponentPhoto: opponentPhoto,
            style: configuration.style
        )
    }

    // MARK: - Supabase pull (Phase 3)
    //
    // Pulls the freshest active-challenges payload from Postgres,
    // merges it with whatever the main app last wrote to the App Group,
    // and persists the result. Errors are swallowed by design — the
    // worst case is "render from cache this tick", which is what would
    // have happened pre-Phase-3 anyway.
    static func pullAndMergeIfPossible(timeoutSeconds: TimeInterval) async {
        // Cache-the-cache so we keep main-app-written photo flags +
        // display name when the pull supersedes the row contents.
        let cached = ActiveChallengeWidgetSnapshot.readAll()
        let cachedById = Dictionary(uniqueKeysWithValues: cached.map { ($0.challengeId, $0) })
        let cachedDisplayName = cached.first?.myDisplayName

        let fresh: [ActiveChallengeWidgetSnapshot.WidgetActiveChallenge]
        do {
            fresh = try await WidgetSupabaseFetcher.fetchActiveChallenges(
                timeout: timeoutSeconds,
                userDisplayName: cachedDisplayName
            )
        } catch let error as WidgetSupabaseFetcherError {
            // notAuthenticated and appGroupUnavailable are config
            // states — log at debug so they don't spam Console for
            // users who simply don't have widgets configured yet.
            // Network/decode errors get info-level so we can spot
            // genuine RPC drift in the field.
            switch error {
            case .notAuthenticated, .appGroupUnavailable:
                log.debug("Widget pull skipped: \(String(describing: error), privacy: .public)")
            default:
                log.info("Widget pull failed: \(String(describing: error), privacy: .public)")
            }
            return
        } catch {
            log.info("Widget pull failed: \(String(describing: error), privacy: .public)")
            return
        }

        // Hash-gate the App Group write — most ticks the data is
        // identical to last time (same hour, neither user logged
        // anything new), and re-writing the same bytes on every tick
        // would still trigger Darwin observers in the main app
        // (Phase 5) and waste their reload budget.
        var merged = mergeFreshWithCache(fresh: fresh, cachedById: cachedById, cachedDisplayName: cachedDisplayName)

        // Phase 7c (2026-04-26): widget-side HealthKit overlay. For
        // step-typed challenges, READ today's cumulative step count
        // directly from HealthKit and overlay it on top of the server
        // value via `max(server, hk)` so the displayed number tracks
        // live walking even when the main app is force-killed and
        // hasn't been able to push to Supabase. Monotonic — never
        // regresses below the server-confirmed value (mirrors QP
        // invariant 25u).
        let hkSteps = await WidgetHealthKitReader.todayStepsIfAuthorized()
        merged = applyHealthKitStepOverlay(merged, hkSteps: hkSteps)

        writeIfChanged(merged: merged)

        // Phase 7d (2026-04-26): widget-side WRITE-back. After the
        // overlay, push fresh HK step counts to the server so opponents
        // see them via the Phase 7b silent-push trigger — even when the
        // user hasn't opened the main Fit33 app in hours. Fire-and-
        // forget (`Task.detached`) so a slow `log_challenge_progress`
        // round trip never holds up the timeline render.
        if let hkSteps {
            Task.detached(priority: .background) {
                await pushFreshStepProgressIfNeeded(merged: merged, hkSteps: hkSteps)
            }
        }
    }

    /// Overlays today's cumulative step count from HealthKit on every
    /// step-typed challenge in the merged list. Returns the input
    /// unchanged when HealthKit is unavailable / unauthorized — the
    /// caller can't tell the difference, which is the right "fail
    /// closed to server data" posture. The HK read is hoisted into
    /// the caller (`pullAndMergeIfPossible`) so Phase 7d can reuse
    /// the same value for the write-back path without a second HK
    /// query.
    private static func applyHealthKitStepOverlay(
        _ rows: [ActiveChallengeWidgetSnapshot.WidgetActiveChallenge],
        hkSteps: Int?
    ) -> [ActiveChallengeWidgetSnapshot.WidgetActiveChallenge] {
        // Cheap fast-path: skip the merge work when no rendered
        // challenge actually consumes step data, OR when HK is
        // unavailable / unauthorized.
        let needsSteps = rows.contains(where: { isStepTypedChallenge($0) })
        guard needsSteps, let hkSteps else { return rows }

        return rows.map { row in
            guard isStepTypedChallenge(row) else { return row }
            let next = max(row.myTodayProgress, hkSteps)
            guard next != row.myTodayProgress else { return row }
            return ActiveChallengeWidgetSnapshot.WidgetActiveChallenge(
                challengeId: row.challengeId,
                challengeType: row.challengeType,
                displayTitle: row.displayTitle,
                mode: row.mode,
                targetUnit: row.targetUnit,
                dailyTarget: row.dailyTarget,
                daysRemaining: row.daysRemaining,
                durationDays: row.durationDays,
                myTodayProgress: next,
                opponentTodayProgress: row.opponentTodayProgress,
                opponentId: row.opponentId,
                opponentName: row.opponentName,
                opponentPhotoUrl: row.opponentPhotoUrl,
                opponentIsVerified: row.opponentIsVerified,
                opponentIsGoldVerified: row.opponentIsGoldVerified,
                myCurrentStreak: row.myCurrentStreak,
                amWinningToday: next > row.opponentTodayProgress,
                myDisplayName: row.myDisplayName,
                hasUserPhoto: row.hasUserPhoto,
                hasOpponentPhoto: row.hasOpponentPhoto,
                // HK overlay is by definition a "now" datapoint —
                // stamp `myLastProgressAt` to now so the freshness
                // pill (`ProgressFreshness.fresh`) reflects the live
                // local read instead of the older server timestamp.
                myLastProgressAt: Date(),
                opponentLastProgressAt: row.opponentLastProgressAt
            )
        }
    }

    /// True when this challenge's `myTodayProgress` is a step count
    /// that HealthKit's `stepCount` total can sensibly overlay. Walk /
    /// run distance challenges track meters, not steps — they need a
    /// different HK query (`distanceWalkingRunning`) and are out of
    /// scope for Phase 7c. Daily-target unit is the canonical signal
    /// (matches the same check `ChallengeProgressResolver` uses on the
    /// main-app side for the optimistic patch).
    private static func isStepTypedChallenge(
        _ row: ActiveChallengeWidgetSnapshot.WidgetActiveChallenge
    ) -> Bool {
        let type = row.challengeType.lowercased()
        let unit = row.targetUnit.lowercased()
        return type == "steps" || unit == "steps"
    }

    // MARK: - Phase 7d: Widget-side write-back
    //
    // Per-challenge debounce so we don't hammer `log_challenge_progress`
    // every time the timeline ticks (one tick = ~20 min, but small + medium
    // widgets each get their own ticks, and iOS may schedule extras).
    // 120s matches the main-app `BackgroundChallengeSyncService` steps
    // throttle (QP invariant 25z) so the cumulative push cadence stays
    // consistent across widget + main-app paths.
    //
    // State is stored in App Group `UserDefaults` so it survives across
    // widget process restarts. Keys are scoped per-challenge.
    private static let widgetPushThrottle: TimeInterval = 120
    private static let widgetPushKeyPrefix = "fit33.widget.lastStepPush.v1."
    private static let widgetPushValueKeyPrefix = "fit33.widget.lastStepValue.v1."

    /// Pushes today's HK step count to `log_challenge_progress` for every
    /// step-typed challenge where HK exceeds the server-confirmed value.
    /// Per-challenge debounced (120s) and value-deduped (skip the push
    /// when the count hasn't changed since the previous push). 401s are
    /// expected ("main app hasn't refreshed JWT in N hours") and silently
    /// drop; the next 20-min tick will retry, and the user opening the
    /// app rotates the JWT so the widget can resume pushing.
    private static func pushFreshStepProgressIfNeeded(
        merged: [ActiveChallengeWidgetSnapshot.WidgetActiveChallenge],
        hkSteps: Int
    ) async {
        guard hkSteps > 0 else { return }
        guard let defaults = UserDefaults(suiteName: ActiveChallengeWidgetSnapshot.appGroupID) else {
            return
        }

        // Find the rows we actually need to push. Skip when the server
        // already knows >= our HK count (server saw a more recent push
        // from elsewhere — the main app, BGAppRefresh, or another widget
        // tick that beat us).
        let candidates = merged.filter { row in
            isStepTypedChallenge(row) && hkSteps > row.myTodayProgress
        }
        guard !candidates.isEmpty else { return }

        let now = Date()
        for row in candidates {
            let throttleKey = widgetPushKeyPrefix + row.challengeId
            let valueKey = widgetPushValueKeyPrefix + row.challengeId

            // Per-challenge time + value debounce.
            let lastPushAt = defaults.object(forKey: throttleKey) as? Date
            if let lastPushAt, now.timeIntervalSince(lastPushAt) < widgetPushThrottle {
                continue
            }
            let lastValue = defaults.integer(forKey: valueKey)
            if lastValue >= hkSteps {
                continue
            }

            do {
                try await WidgetSupabaseFetcher.logChallengeStepProgress(
                    challengeId: row.challengeId,
                    stepCount: hkSteps
                )
                defaults.set(now, forKey: throttleKey)
                defaults.set(hkSteps, forKey: valueKey)
                log.info("Widget pushed steps=\(hkSteps) to challenge=\(row.challengeId.prefix(8), privacy: .public)")
            } catch let error as WidgetSupabaseFetcherError {
                switch error {
                case .http(status: 401, _):
                    // JWT expired — main app hasn't refreshed in
                    // a while. Silent drop; bump the throttle so we
                    // don't spin on 401 every tick.
                    defaults.set(now, forKey: throttleKey)
                    return
                case .notAuthenticated, .appGroupUnavailable, .malformedSession:
                    // Config / signed-out states. Stop trying — every
                    // candidate would hit the same wall.
                    return
                default:
                    // Transport / 5xx / decode — let the next tick retry.
                    log.debug("Widget push failed (non-fatal): \(String(describing: error), privacy: .public)")
                }
            } catch {
                log.debug("Widget push failed (non-fatal): \(String(describing: error), privacy: .public)")
            }
        }
    }

    /// Combines the fresh server-side rows with cached photo flags +
    /// display name (which the widget process can't compute from the
    /// RPC alone). Returns the merged list ready to encode into the
    /// App Group.
    private static func mergeFreshWithCache(
        fresh: [ActiveChallengeWidgetSnapshot.WidgetActiveChallenge],
        cachedById: [String: ActiveChallengeWidgetSnapshot.WidgetActiveChallenge],
        cachedDisplayName: String?
    ) -> [ActiveChallengeWidgetSnapshot.WidgetActiveChallenge] {
        fresh.map { freshRow in
            guard let cached = cachedById[freshRow.challengeId] else { return freshRow }
            return ActiveChallengeWidgetSnapshot.WidgetActiveChallenge(
                challengeId: freshRow.challengeId,
                challengeType: freshRow.challengeType,
                displayTitle: freshRow.displayTitle,
                mode: freshRow.mode,
                targetUnit: freshRow.targetUnit,
                dailyTarget: freshRow.dailyTarget,
                daysRemaining: freshRow.daysRemaining,
                durationDays: freshRow.durationDays,
                myTodayProgress: freshRow.myTodayProgress,
                opponentTodayProgress: freshRow.opponentTodayProgress,
                opponentId: freshRow.opponentId,
                opponentName: freshRow.opponentName,
                opponentPhotoUrl: freshRow.opponentPhotoUrl,
                opponentIsVerified: freshRow.opponentIsVerified,
                opponentIsGoldVerified: freshRow.opponentIsGoldVerified,
                myCurrentStreak: freshRow.myCurrentStreak,
                amWinningToday: freshRow.amWinningToday,
                // Photos + display name come from the main-app process
                // (it has UserManager / ProfilePhotoCache). Carry them
                // forward verbatim — pulling fresh challenge data
                // shouldn't blow away cached avatars.
                myDisplayName: cached.myDisplayName ?? cachedDisplayName,
                hasUserPhoto: cached.hasUserPhoto,
                hasOpponentPhoto: cached.hasOpponentPhoto,
                myLastProgressAt: freshRow.myLastProgressAt,
                opponentLastProgressAt: freshRow.opponentLastProgressAt
            )
        }
    }

    /// Persists the merged list + chosen "best pick" into the App Group
    /// when the encoded payload differs from what's already on disk.
    /// Uses the same keys + sort order as the main app's
    /// `ActiveChallengeWidgetBridge.publish` so consumers (the widget
    /// itself + the in-app surfaces wired up in Phase 5) see one
    /// canonical view of the world.
    private static func writeIfChanged(merged: [ActiveChallengeWidgetSnapshot.WidgetActiveChallenge]) {
        guard let defaults = UserDefaults(suiteName: ActiveChallengeWidgetSnapshot.appGroupID) else {
            log.error("Widget pull: App Group unavailable — cannot persist fresh payload")
            return
        }

        let chosen = merged.first
        let encoder = JSONEncoder()
        do {
            let listData = try encoder.encode(merged)
            let chosenData: Data? = try chosen.map { try encoder.encode($0) }
            // Compare against the bytes already on disk. If they match,
            // skip the write entirely — UserDefaults `set` with
            // identical bytes still bumps the change generation that
            // CFNotificationCenter (Phase 5) reads, which would burn
            // the main app's wake budget for no UI delta.
            let existingList = defaults.data(forKey: ActiveChallengeWidgetSnapshot.challengesListKey)
            let existingChosen = defaults.data(forKey: ActiveChallengeWidgetSnapshot.challengeKey)
            if existingList == listData && existingChosen == chosenData {
                log.debug("Widget pull: payload unchanged, skipping App Group write")
                return
            }

            if let chosenData {
                defaults.set(chosenData, forKey: ActiveChallengeWidgetSnapshot.challengeKey)
            } else {
                defaults.removeObject(forKey: ActiveChallengeWidgetSnapshot.challengeKey)
            }
            defaults.set(listData, forKey: ActiveChallengeWidgetSnapshot.challengesListKey)
            defaults.set(Date(), forKey: ActiveChallengeWidgetSnapshot.updatedAtKey)
            log.info("Widget pull: wrote \(merged.count) challenge(s) to App Group")

            // Phase 5 (2026-04-26): kick the main-app process so its
            // in-app challenge UI re-fetches and stays in lockstep
            // with what the widget just rendered. The Darwin
            // notification is fire-and-forget — if the main app
            // isn't running, iOS drops it silently and the next
            // foreground tick will pick up the App Group payload
            // anyway. Constant matches
            // `ActiveChallengeWidgetBridge.widgetPullNotificationName`.
            let center = CFNotificationCenterGetDarwinNotifyCenter()
            let name = "com.fit33.app.widgetActiveChallengePayloadChanged" as CFString
            CFNotificationCenterPostNotification(
                center,
                CFNotificationName(name),
                nil,
                nil,
                true
            )
        } catch {
            log.error("Widget pull: encode failed: \(String(describing: error), privacy: .public)")
        }
    }
}

struct ActiveChallengeEntry: TimelineEntry {
    let date: Date
    /// `nil` means the user has no active 1v1 challenges right now.
    let challenge: ActiveChallengeWidgetSnapshot.WidgetActiveChallenge?
    let userPhoto: UIImage?
    let opponentPhoto: UIImage?
    let style: WidgetBackgroundStyle
}

// MARK: - Entry View

struct ActiveChallengeWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    var entry: ActiveChallengeProvider.Entry

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                if let challenge = entry.challenge {
                    CompactChallengeCard(challenge: challenge, userPhoto: entry.userPhoto, opponentPhoto: entry.opponentPhoto, style: entry.style)
                } else {
                    ChallengeEmptyState(compact: true)
                }
            default:
                // Only systemSmall + systemMedium are supported (see
                // `supportedFamilies` below). Everything that isn't small
                // falls back to the medium card layout.
                if let challenge = entry.challenge {
                    MediumChallengeCard(challenge: challenge, userPhoto: entry.userPhoto, opponentPhoto: entry.opponentPhoto, style: entry.style)
                } else {
                    ChallengeEmptyState(compact: false)
                }
            }
        }
        .padding(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(for: .widget) {
            ChallengeWidgetBackground(typeKey: entry.challenge?.challengeType, style: entry.style)
        }
        // Force the SwiftUI color scheme so .primary / .secondary text
        // renders the right tone for the chosen background — dark for
        // color & dark styles, light for the grey style.
        .environment(\.colorScheme, entry.style == .light ? .light : .dark)
    }
}

/// Edge-to-edge background that fills the entire widget container.
/// Three styles selectable from the widget edit sheet:
///   • `.color` — dark base with a strong, clean diagonal wash of the
///     challenge type color
///   • `.dark`  — near-black with a subtle soft glow of the challenge color
///   • `.light` — clean off-white with the same subtle colored glow
private struct ChallengeWidgetBackground: View {
    let typeKey: String?
    let style: WidgetBackgroundStyle

    private var typeColor: Color {
        ChallengeWidgetPalette.color(for: typeKey ?? "")
    }

    var body: some View {
        switch style {
        case .color:
            ZStack {
                Color(white: 0.06)
                LinearGradient(
                    colors: [typeColor.opacity(0.55), typeColor.opacity(0.18)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        case .dark:
            // Pure black with a subtle top-down sheen (à la Apple's native
            // Stocks widget) — barely-visible white lift at the top fading
            // into deep black at the bottom for a touch of dimensionality.
            ZStack {
                Color.black
                LinearGradient(
                    colors: [Color.white.opacity(0.06), .clear],
                    startPoint: .top,
                    endPoint: .center
                )
                RadialGradient(
                    colors: [Color.white.opacity(0.05), .clear],
                    center: .topLeading,
                    startRadius: 0,
                    endRadius: 280
                )
            }
        case .light:
            // Crisp paper-white base with a watercolor wash of the type color
            // pooling in the top-left corner and fading to clean white in the
            // bottom-right. Two stacked radial gradients give the wash some
            // depth instead of looking like a flat translucent sheet.
            ZStack {
                Color.white
                RadialGradient(
                    colors: [typeColor.opacity(0.55), typeColor.opacity(0.22), .clear],
                    center: .topLeading,
                    startRadius: 0,
                    endRadius: 360
                )
                LinearGradient(
                    colors: [typeColor.opacity(0.10), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                RadialGradient(
                    colors: [Color.white.opacity(0.6), .clear],
                    center: .bottomTrailing,
                    startRadius: 0,
                    endRadius: 200
                )
            }
        }
    }
}

// MARK: - Medium card (mirrors the in-app `activeChallengeDetailWidget`)

private struct MediumChallengeCard: View {
    let challenge: ActiveChallengeWidgetSnapshot.WidgetActiveChallenge
    let userPhoto: UIImage?
    let opponentPhoto: UIImage?
    let style: WidgetBackgroundStyle

    private var typeColor: Color { ChallengeWidgetPalette.color(for: challenge.challengeType) }
    private var typeGradient: [Color] { ChallengeWidgetPalette.gradient(for: challenge.challengeType) }

    var body: some View {
        VStack(spacing: 6) {
            header
            bottom
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 11) {
            ZStack {
                Circle()
                    .stroke(LinearGradient(colors: typeGradient, startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 2.5)
                    .frame(width: 38, height: 38)
                    // Darken the ring in light mode so it doesn't blend into
                    // the matching color wash behind it.
                    .brightness(style == .light ? -0.20 : 0)
                    .saturation(style == .light ? 1.15 : 1)
                Text(ChallengeWidgetPalette.emoji(for: challenge.challengeType))
                    .font(.system(size: 19))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(challenge.displayTitle)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                HStack(spacing: 5) {
                    Text(challenge.isAccountability ? "with \(challenge.opponentFirstName)" : "vs \(challenge.opponentFirstName)")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Text("•")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Text("\(challenge.daysRemaining)d left")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(typeColor)
                        // In light mode the type color matches the background
                        // wash, so darken the accent text to keep contrast.
                        .brightness(style == .light ? -0.25 : 0)
                        .saturation(style == .light ? 1.2 : 1)
                }
            }

            Spacer()

            // Realtime Widget Server Pull, Phase 4b (2026-04-26):
            // Replaces the previous mode-indicator emoji (🤝 / ⚔️) with
            // a tappable refresh control. Mode is already
            // unambiguous from the row layout below ("vs Abbie" vs
            // "with Abbie" + competition vs accountability row),
            // so losing the emoji costs no information. Tap fires
            // RefreshChallengeIntent inside the widget extension —
            // pulls fresh server data + reloads this widget kind.
            ChallengeRefreshButton(style: style, typeColor: typeColor)
        }
    }

    private var bottom: some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2)
                .fill(LinearGradient(colors: typeGradient, startPoint: .top, endPoint: .bottom))
                .frame(width: 4)
                .padding(.vertical, 4)

            if challenge.isAccountability {
                AccountabilityRow(challenge: challenge, userPhoto: userPhoto, opponentPhoto: opponentPhoto, typeColor: typeColor, typeGradient: typeGradient)
            } else {
                CompetitionRow(challenge: challenge, userPhoto: userPhoto, opponentPhoto: opponentPhoto, typeColor: typeColor, typeGradient: typeGradient)
            }
        }
        .padding(.vertical, 6)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(WidgetSurfacePalette.innerPill(for: style))
                if style == .light {
                    // Subtle hairline + soft shadow so the white pill reads as
                    // an elevated card on the green wash instead of a sticker.
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5)
                }
            }
            .shadow(color: style == .light ? Color.black.opacity(0.08) : .clear, radius: 6, x: 0, y: 2)
        )
    }
}

/// Solid-ish inner-card colors per background style. Solid (vs translucent
/// `Color.primary.opacity`) so the underlying colored glow doesn't bleed
/// through and tint the pill green/orange/etc.
enum WidgetSurfacePalette {
    static func innerPill(for style: WidgetBackgroundStyle) -> Color {
        switch style {
        case .color: return Color.black.opacity(0.22)
        case .dark:  return Color.white.opacity(0.09)
        case .light: return Color.white
        }
    }
}

// MARK: - Competition Row (vs)

private struct CompetitionRow: View {
    let challenge: ActiveChallengeWidgetSnapshot.WidgetActiveChallenge
    let userPhoto: UIImage?
    let opponentPhoto: UIImage?
    let typeColor: Color
    let typeGradient: [Color]

    var body: some View {
        HStack(spacing: 8) {
            // Me
            HStack(spacing: 8) {
                ZStack(alignment: .top) {
                    WidgetAvatar(image: userPhoto, name: challenge.myFirstName, gradient: typeGradient, done: challenge.amWinningToday, size: 34)
                    if challenge.amWinningToday {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.yellow)
                            .offset(y: -9)
                    }
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text("You")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(ChallengeWidgetPalette.formattedValue(challenge.myTodayProgress))
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(challenge.amWinningToday ? .green : .primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(ChallengeWidgetPalette.formattedUnit(challenge.targetUnit))
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            VStack(spacing: 1) {
                Text("⚔️")
                    .font(.system(size: 11))
                // Only render the +/- diff when both sides have
                // recent enough numbers to compare honestly. If
                // we're falling back to "—" for the opponent, a
                // bold "+8,000" would imply we're winning by that
                // much when in reality we just don't know what the
                // opponent did today.
                let canCompare = ProgressFreshnessKit.shouldShowRawValue(for: challenge.opponentLastProgressAt)
                if canCompare && challenge.myTodayProgress != challenge.opponentTodayProgress {
                    let diff = abs(challenge.myTodayProgress - challenge.opponentTodayProgress)
                    let prefix = challenge.amWinningToday ? "+" : "-"
                    Text("\(prefix)\(ChallengeWidgetPalette.formattedValue(diff))")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(challenge.amWinningToday ? .green : .red)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(ChallengeWidgetPalette.formattedUnit(challenge.targetUnit))
                        .font(.system(size: 7, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(width: 44)

            // Opponent — Phase 6b (2026-04-26): when the server reports
            // we haven't seen this opponent's progress in a while
            // (`opponent_last_progress_at` >2h or null), suppress the
            // raw value (which would lie as "0 steps" for someone in
            // a step challenge) and replace it with an em-dash plus
            // a relative-age label like "4h ago".
            HStack(spacing: 8) {
                let oppShowsRaw = ProgressFreshnessKit.shouldShowRawValue(for: challenge.opponentLastProgressAt)
                let oppAge = ProgressFreshnessKit.ageLabel(for: challenge.opponentLastProgressAt)
                let oppFreshness = ProgressFreshnessKit.freshness(for: challenge.opponentLastProgressAt)
                let oppShowsCrown = oppShowsRaw && !challenge.amWinningToday && challenge.opponentTodayProgress > 0
                VStack(alignment: .trailing, spacing: 0) {
                    Text(challenge.opponentFirstName)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(oppShowsRaw ? ChallengeWidgetPalette.formattedValue(challenge.opponentTodayProgress) : "—")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(oppShowsCrown ? .green : (oppShowsRaw ? .primary : .secondary))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    // Show the unit when we have a real number, and the
                    // age otherwise. For any non-`.fresh` reading inside
                    // today (`.recent` 30m–2h or `.stale` 2h–24h) we
                    // stack the age on its own line beneath the unit
                    // ("steps" / "44m ago") so the user knows it's a
                    // trailing-but-real number. Only `.unknown`
                    // (≥24h or never logged) hides the value.
                    if oppShowsRaw {
                        Text(ChallengeWidgetPalette.formattedUnit(challenge.targetUnit))
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        if (oppFreshness == .recent || oppFreshness == .stale), let oppAge {
                            Text(oppAge)
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundStyle(.secondary.opacity(0.75))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                    } else {
                        Text(oppAge ?? "no data")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                ZStack(alignment: .top) {
                    WidgetAvatar(image: opponentPhoto, name: challenge.opponentName ?? "Friend", gradient: [.orange, .red], done: oppShowsCrown, size: 34)
                    if oppShowsCrown {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.yellow)
                            .offset(y: -9)
                    }
                }
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, 12)
    }
}

// MARK: - Accountability Row (with)

private struct AccountabilityRow: View {
    let challenge: ActiveChallengeWidgetSnapshot.WidgetActiveChallenge
    let userPhoto: UIImage?
    let opponentPhoto: UIImage?
    let typeColor: Color
    let typeGradient: [Color]

    private var myDone: Bool {
        guard let target = challenge.dailyTarget, target > 0 else { return false }
        return challenge.myTodayProgress >= target
    }
    private var oppDone: Bool {
        guard let target = challenge.dailyTarget, target > 0 else { return false }
        return challenge.opponentTodayProgress >= target
    }

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: -8) {
                WidgetAvatar(image: userPhoto, name: challenge.myFirstName, gradient: typeGradient, done: myDone, size: 30)
                WidgetAvatar(image: opponentPhoto, name: challenge.opponentName ?? "Friend", gradient: typeGradient, done: oppDone, size: 30)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(myDone ? "✅" : "⬜")
                        .font(.system(size: 11))
                    Text(ChallengeWidgetPalette.formattedProgress(challenge.myTodayProgress, unit: challenge.targetUnit))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(myDone ? .green : typeColor)
                    Text("·")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text(oppDone ? "✅" : "⬜")
                        .font(.system(size: 11))
                    Text(challenge.opponentFirstName)
                        .font(.system(size: 11))
                        .foregroundStyle(oppDone ? .green : .secondary)
                        .lineLimit(1)
                }

                if challenge.myCurrentStreak > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.orange)
                        Text("\(challenge.myCurrentStreak)-day streak together")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(LinearGradient(colors: [.orange, .yellow], startPoint: .leading, endPoint: .trailing))
                    }
                } else {
                    Text("Check in together today")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 4)

            ProgressRing(
                progress: max(challenge.myDailyProgress, challenge.opponentDailyProgress),
                gradient: typeGradient,
                bothDone: challenge.bothDoneToday,
                size: 30
            )
        }
        .padding(.leading, 10)
        .padding(.trailing, 12)
    }
}

// MARK: - Compact (small) card

private struct CompactChallengeCard: View {
    let challenge: ActiveChallengeWidgetSnapshot.WidgetActiveChallenge
    let userPhoto: UIImage?
    let opponentPhoto: UIImage?
    let style: WidgetBackgroundStyle

    private var typeColor: Color { ChallengeWidgetPalette.color(for: challenge.challengeType) }
    private var typeGradient: [Color] { ChallengeWidgetPalette.gradient(for: challenge.challengeType) }

    private var iAmAhead: Bool { challenge.amWinningToday }
    /// True when the opponent's value is fresh enough to trust AND
    /// represents an actual lead. When the server-side timestamp is
    /// stale we suppress the "ahead" treatment (green tint + crown)
    /// because the underlying number is unreliable — the opponent
    /// might be at 12k steps right now but we just haven't seen it.
    private var oppAhead: Bool {
        !iAmAhead
        && challenge.opponentTodayProgress > 0
        && ProgressFreshnessKit.shouldShowRawValue(for: challenge.opponentLastProgressAt)
    }

    var body: some View {
        // Two-column "you vs them" layout. Each side is a self-contained
        // mini-card stack — avatar → name → number → unit — so the photo
        // visually anchors its own score instead of both photos clumping
        // together in a single overlapping row above the numbers (which
        // disconnected each face from the column it represented).
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(ChallengeWidgetPalette.emoji(for: challenge.challengeType))
                    .font(.system(size: 17))
                Text("\(challenge.daysRemaining)d left")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(typeColor)
                    // Match the medium-card contrast tweak — the green
                    // accent gets too washy on the .light background.
                    .brightness(style == .light ? -0.25 : 0)
                    .saturation(style == .light ? 1.2 : 1)
                Spacer()
                // Phase 4b (2026-04-26): refresh button in place of
                // the mode-indicator emoji. Sized down to match the
                // small-widget header rhythm.
                ChallengeRefreshButton(style: style, typeColor: typeColor, compact: true)
            }

            Text(challenge.displayTitle)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.85)

            Spacer(minLength: 0)

            HStack(alignment: .top, spacing: 4) {
                CompactSideColumn(
                    photo: userPhoto,
                    label: "You",
                    avatarFallbackName: challenge.myFirstName,
                    value: challenge.myTodayProgress,
                    unit: challenge.targetUnit,
                    isAhead: iAmAhead,
                    gradient: typeGradient,
                    side: .leading
                )

                // Tiny "vs" sits centered with the avatars, not the
                // numbers, so the divider feels like part of the avatar
                // row rather than a label hovering over the value.
                Text("vs")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 10)

                CompactSideColumn(
                    photo: opponentPhoto,
                    label: challenge.opponentFirstName,
                    avatarFallbackName: challenge.opponentName ?? "Friend",
                    value: challenge.opponentTodayProgress,
                    unit: challenge.targetUnit,
                    isAhead: oppAhead,
                    gradient: [.orange, .red],
                    side: .trailing,
                    // Phase 6b: feed the opponent's last-progress
                    // timestamp in so the column can render
                    // "— · 4h ago" instead of a misleading "0".
                    lastProgressAt: challenge.opponentLastProgressAt
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// One side of the small-widget head-to-head: avatar at the top, then
/// label / value / unit stacked below it. `side` controls outer alignment
/// — `.leading` for the user's column (everything flush left) and
/// `.trailing` for the opponent (everything flush right) so the two
/// columns mirror each other across the central "vs" separator.
private struct CompactSideColumn: View {
    enum Side { case leading, trailing }

    let photo: UIImage?
    let label: String           // shown under the avatar — "You" or first name
    let avatarFallbackName: String
    let value: Int
    let unit: String
    let isAhead: Bool
    let gradient: [Color]
    let side: Side
    /// `nil` for the "You" column — we never suppress the user's own
    /// number because they always know how much they walked today,
    /// and the main app's publish path keeps their slot live. Set
    /// for the opponent column so we can substitute "— · 4h ago"
    /// when the server-side timestamp is stale.
    var lastProgressAt: Date? = nil

    private var hAlign: HorizontalAlignment { side == .leading ? .leading : .trailing }
    private var frameAlign: Alignment { side == .leading ? .leading : .trailing }

    /// `true` when the value text should display the actual number.
    /// Always true for the user (no `lastProgressAt` provided); for
    /// the opponent, defers to `ProgressFreshnessKit`.
    private var showsRawValue: Bool {
        guard lastProgressAt != nil else { return true }
        return ProgressFreshnessKit.shouldShowRawValue(for: lastProgressAt)
    }

    private var ageLabel: String? {
        ProgressFreshnessKit.ageLabel(for: lastProgressAt)
    }

    /// What to render in the single slot under the value. Order of
    /// preference (small-widget budget = one short line):
    ///   1. `.unknown`/no data — show age or "no data"
    ///   2. `.recent`/`.stale` (today, trailing) — show age suffix,
    ///      since the avatar already implies the unit
    ///   3. `.fresh` or no `lastProgressAt` (the user's own column)
    ///      — show the unit
    private var unitOrAgeLabel: String {
        if !showsRawValue {
            return ageLabel ?? "no data"
        }
        let freshness = ProgressFreshnessKit.freshness(for: lastProgressAt)
        if (freshness == .recent || freshness == .stale), let age = ageLabel {
            return age
        }
        return ChallengeWidgetPalette.formattedUnit(unit)
    }

    var body: some View {
        VStack(alignment: hAlign, spacing: 1) {
            ZStack(alignment: .top) {
                WidgetAvatar(
                    image: photo,
                    name: avatarFallbackName,
                    gradient: gradient,
                    done: isAhead,
                    size: 28
                )
                // Yellow crown floats just above the avatar when this side
                // is currently ahead — mirrors the medium-card treatment so
                // a glance at the small widget tells you who's winning
                // without parsing numbers.
                if isAhead {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.yellow)
                        .offset(y: -8)
                }
            }
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            // Phase 6b (rev 2026-04-26): when the opponent timestamp
            // is `.unknown` (≥24h or never logged), render an em-dash
            // so "0 steps" stops misrepresenting an unsynced device.
            // For `.recent`/`.stale` (today's data, just trailing) we
            // show the actual value with the age in the unit slot.
            Text(showsRawValue ? ChallengeWidgetPalette.formattedValue(value) : "—")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(isAhead ? .green : (showsRawValue ? .primary : .secondary))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            // The single slot under the value is shared between the
            // unit ("steps") and the age suffix ("47m ago"). When we
            // have an age and it's not fresh, the age is more useful
            // than repeating the unit implied by the avatar context.
            Text(unitOrAgeLabel)
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: frameAlign)
    }
}

// MARK: - Empty state

private struct ChallengeEmptyState: View {
    let compact: Bool

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "flag.checkered")
                .font(.system(size: compact ? 22 : 28, weight: .semibold))
                .foregroundStyle(LinearGradient(colors: [.purple, .pink], startPoint: .topLeading, endPoint: .bottomTrailing))
            Text("No active challenges")
                .font(.system(size: compact ? 11 : 13, weight: .semibold))
                .foregroundStyle(.primary)
            Text("Start one with a friend in the app")
                .font(.system(size: compact ? 9 : 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Reusable bits

/// Tap target wired to `RefreshChallengeIntent`. Renders an SF Symbol
/// arrow that visually echoes a "pull-to-refresh" affordance — the user
/// taps and the widget reloads with whatever the latest server pull
/// produced. Sized to slot into the existing header where the mode
/// emoji used to live so the rest of the layout doesn't shift.
///
/// Style awareness:
///   • `.color` / `.dark` — translucent white pill on dark bg.
///   • `.light`           — soft typeColor tint on white card.
private struct ChallengeRefreshButton: View {
    let style: WidgetBackgroundStyle
    let typeColor: Color
    var compact: Bool = false

    private var iconSize: CGFloat { compact ? 11 : 14 }
    private var pillSize: CGFloat { compact ? 22 : 28 }

    private var fillColor: Color {
        switch style {
        case .color, .dark: return Color.white.opacity(0.14)
        case .light:        return typeColor.opacity(0.16)
        }
    }
    private var strokeColor: Color {
        switch style {
        case .color, .dark: return Color.white.opacity(0.22)
        case .light:        return typeColor.opacity(0.32)
        }
    }
    private var iconColor: Color {
        switch style {
        case .color, .dark: return .white
        case .light:        return typeColor
        }
    }

    var body: some View {
        Button(intent: RefreshChallengeIntent()) {
            ZStack {
                Circle()
                    .fill(fillColor)
                Circle()
                    .strokeBorder(strokeColor, lineWidth: 0.75)
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: iconSize, weight: .semibold))
                    .foregroundStyle(iconColor)
                    // The light-mode type color often matches the
                    // colored wash behind the button — drop saturation
                    // and brightness so the arrow stays legible.
                    .brightness(style == .light ? -0.20 : 0)
                    .saturation(style == .light ? 1.15 : 1)
            }
            .frame(width: pillSize, height: pillSize)
        }
        .buttonStyle(.plain)
        // VoiceOver reads "Refresh challenge" — matches the intent's
        // localized title so the action is self-describing for users
        // who can't see the affordance.
        .accessibilityLabel("Refresh challenge")
    }
}

/// Circular avatar that prefers a real photo when one is available in the
/// App Group container, falling back to a tinted initials bubble (matches
/// the in-app `CachedFriendPhoto` look).
private struct WidgetAvatar: View {
    let image: UIImage?
    let name: String
    let gradient: [Color]
    let done: Bool
    let size: CGFloat

    private var initials: String {
        let parts = name.split(separator: " ")
        let first = parts.first.map { String($0.prefix(1)) } ?? ""
        let last = parts.dropFirst().first.map { String($0.prefix(1)) } ?? ""
        let combined = (first + last).uppercased()
        return combined.isEmpty ? "?" : combined
    }

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                Text(initials)
                    .font(.system(size: size * 0.4, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .overlay(
            Circle().stroke(done ? Color.green : Color.gray.opacity(0.3), lineWidth: 1.5)
        )
    }
}

private struct ProgressRing: View {
    let progress: Double
    let gradient: [Color]
    let bothDone: Bool
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.gray.opacity(0.15), lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: max(0, min(1, progress)))
                .stroke(
                    LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing),
                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            if bothDone {
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.4, weight: .bold))
                    .foregroundStyle(.green)
            } else {
                Text("\(Int(progress * 100))%")
                    .font(.system(size: size * 0.32, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Widget Configuration

struct ActiveChallengeWidget: Widget {
    let kind: String = "ActiveChallengeWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: ChallengePickerIntent.self,
            provider: ActiveChallengeProvider()
        ) { entry in
            ActiveChallengeWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Active Challenge")
        .description("Track an active 1v1 challenge with a friend.")
        // Large variant intentionally excluded — its progress-bar layout
        // didn't earn its real-estate vs. just running two mediums or a
        // small + medium pair, and head-to-head data is best read at a
        // glance, not as bars.
        .supportedFamilies([.systemSmall, .systemMedium])
        // Run the gradient background and content all the way to the
        // widget's rounded edge instead of leaving Apple's default
        // ~16pt inset which made the card look like a card-within-a-card.
        .contentMarginsDisabled()
    }
}

// MARK: - Previews

#Preview(as: .systemMedium) {
    ActiveChallengeWidget()
} timeline: {
    ActiveChallengeEntry(date: .now, challenge: ActiveChallengeWidgetSnapshot.placeholder, userPhoto: nil, opponentPhoto: nil, style: .color)
    ActiveChallengeEntry(date: .now, challenge: ActiveChallengeWidgetSnapshot.placeholder, userPhoto: nil, opponentPhoto: nil, style: .dark)
    ActiveChallengeEntry(date: .now, challenge: ActiveChallengeWidgetSnapshot.placeholder, userPhoto: nil, opponentPhoto: nil, style: .light)
    ActiveChallengeEntry(date: .now, challenge: nil, userPhoto: nil, opponentPhoto: nil, style: .color)
}

#Preview(as: .systemSmall) {
    ActiveChallengeWidget()
} timeline: {
    ActiveChallengeEntry(date: .now, challenge: ActiveChallengeWidgetSnapshot.placeholder, userPhoto: nil, opponentPhoto: nil, style: .color)
}
