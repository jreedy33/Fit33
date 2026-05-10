//
//  PerfFlags.swift
//  Fit33
//
//  Centralized feature flags for the Snappiness Overhaul (May 2026).
//  Each phase of the overhaul ships behind a flag so any individual change
//  can be rolled back in <60s via UserDefaults (or a remote-config override
//  written to UserDefaults at launch) without a rebuild/resubmit.
//
//  Default policy:
//   - DEBUG / TestFlight builds: flags default ON (so internal/beta users exercise the new path).
//   - App Store production: flags default OFF until each phase is validated 48h on TestFlight,
//     then flipped ON via remote override (or a code-default change in a follow-up build).
//
//  See also: QUALITY_PERFORMANCE_AGENT.md invariant QP-35
//  ("Every perf change MUST ship behind a PerfFlags toggle until validated 48h on TestFlight.")
//

import Foundation

/// Feature flags for the Snappiness Overhaul rollout.
///
/// Each accessor reads from UserDefaults so a remote-config write (or a manual
/// debug toggle) can flip behavior without a rebuild. The default is computed
/// once per call: cheap, but call sites should still cache the read into a
/// local `let` if they're inside a hot loop.
///
/// To override at runtime (e.g. from a debug menu or a remote-config push):
///   UserDefaults.standard.set(false, forKey: "perf_phase1_body_churn")
enum PerfFlags {

    /// Phase 1 — SwiftUI body-churn fixes: WorkoutTabView @State write moved out
    /// of view body, OlympianPathService 60s TTL with NotificationCenter
    /// invalidation, ProfileView Color.clear .task removal, dead SmartProgramWidget
    /// deletion. All correctness fixes; rollback restores today's behavior.
    static var phase1BodyChurn: Bool {
        flag("perf_phase1_body_churn", default: defaultEnabled)
    }

    /// Phase 2 — Realtime grace timer + foreground gate. RealtimeService keeps
    /// the WebSocket alive for 60s on background (deliver events live across
    /// brief blips) and the post-foreground 10-RPC fanout / HK sync respect
    /// the existing 30s gate for the audited safe-list.
    static var phase2RealtimeGate: Bool {
        flag("perf_phase2_realtime_gate", default: defaultEnabled)
    }

    /// Phase 3 — Persist UserBehaviorLearningEngine similarity map to disk
    /// keyed on a content-version hash of the static exercise catalog. Cache
    /// hits avoid the 23.8s rebuild entirely. Top-K bound is explicitly
    /// deferred to a separate PR with score-equivalence tests.
    static var phase3SimilarityCache: Bool {
        flag("perf_phase3_similarity_cache", default: defaultEnabled)
    }

    /// Phase 4 — Telemetry hygiene: StartupWaterfall thread attribution,
    /// new behavioral-parity counters (realtime.events_during_background,
    /// foreground.rpc_freshness_delta_ms, olympian.cache_hit_rate,
    /// similarity_map.disk_hit). Pure observability change.
    static var phase4Telemetry: Bool {
        flag("perf_phase4_telemetry", default: defaultEnabled)
    }

    /// Phase 5.A — Dashboard.social_fanout 5-min disk cache. Persists the
    /// 10-RPC widget fanout result to Library/Caches with a 5-min TTL so
    /// repeat dashboard visits paint instantly while a background refresh
    /// pulls fresh data.
    static var phase5DashboardCache: Bool {
        flag("perf_phase5_dashboard_cache", default: defaultEnabled)
    }

    /// Phase 5.B — SmartProgramRecommender pre-warm during scenePhase=.active
    /// on a background priority Task so the first Workout-tab visit hits a
    /// populated cache instead of running the recommender 4× during initial
    /// body re-eval.
    static var phase5RecommenderPrewarm: Bool {
        flag("perf_phase5_recommender_prewarm", default: defaultEnabled)
    }

    /// Phase 5.C — Move ExerciseLibrary.preWarmCache (~2.3s) and
    /// FilterCache.precompute (~800ms) off the main thread during cold start.
    /// Net: ~3.1s of main-thread work moved to bg-userInitiated.
    static var phase5OffMain: Bool {
        flag("perf_phase5_off_main", default: defaultEnabled)
    }

    /// Phase 5.D — Coalesce N parallel `unlock_achievement` RPC fan-outs
    /// (currently 24 cancelled per cold start) into a single batch RPC.
    /// Includes server-side `batch_check_achievements(text[])` migration.
    static var phase5BatchAchievements: Bool {
        flag("perf_phase5_batch_achievements", default: defaultEnabled)
    }

    /// Phase 5.E — `CloudSync: profile` measure-window slimming.
    ///
    /// Audit (StartupWaterfall, 2026-05-07) found `[bg-init] CloudSync:
    /// profile` taking 4800ms in the cold-start `syncAllDataFromCloud`
    /// path. The actual data work (one `SELECT user_profiles WHERE id =
    /// auth.uid()` + a `bgContext.perform` Core Data write) is ~150-300ms
    /// of network + a few ms of Core Data — wall time was inflated by
    /// TWO `MainActor.run` hops nested inside the measure block (the
    /// outer one set `isVerified` / `isGoldVerified` redundantly with
    /// the inner one inside `syncUserProfileToCoreData`'s tail) that
    /// each stalled multi-seconds waiting for the main runloop to
    /// quiesce during cold-start UI build.
    ///
    /// When ON: the redundant outer `MainActor.run` is removed and the
    /// inner side-effect cascade (`UnitSettingsManager.loadFromCloud`,
    /// `UserManager.reloadCurrentUser`, `checkAndBreakStreakIfNeeded`)
    /// is deferred to a fire-and-forget Task that runs AFTER the
    /// measure block exits — so the timeline reflects pure data work,
    /// not main-thread contention. Field-by-field Core Data write is
    /// byte-identical (the bgContext.perform body is unchanged).
    ///
    /// When OFF: byte-identical to pre-overhaul behavior (two MainActor
    /// hops inside the measure window).
    static var phase5ProfileSync: Bool {
        flag("perf_phase5_profile_sync", default: defaultEnabled)
    }

    /// Phase 6 — Realtime callback-registration order fix.
    ///
    /// Cold-start logs from app version 1.39 (70) emit:
    ///   `Cannot add "postgres_changes" callbacks for "realtime:private-challenges"
    ///    after subscribe(). Please add all your postgres change callbacks before
    ///    subscribing to the channel.`
    /// — exactly 7 times in one cold start, matching the 7 `.postgresChange(...)`
    /// registrations inside `PrivateChallengeService.subscribeToRealtimeUpdates()`.
    /// The Supabase Realtime SDK silently DROPS any callback registered after
    /// `subscribe()` on the same channel, so realtime updates for that channel
    /// never fire (which is the smoking gun behind `[REALTIME] Reconnecting —
    /// channels torn down + stale (last event never)`).
    ///
    /// Root cause is actor reentrancy, NOT source-order: `subscribeToRealtimeUpdates()`
    /// is `@MainActor`, but its `await channel.subscribe()` releases the actor
    /// isolation. Two concurrent callers (DashboardView fires a `Task { ... }`
    /// on line 764 in the inline path AND on line 930 in the SWR refresh path)
    /// both observe `realtimeChannel == nil`, both fetch the same channel via
    /// `client.realtimeV2.channel("private-challenges")` (Supabase returns the
    /// existing instance for matching names), and the second caller registers
    /// its 7 callbacks on the channel that the first caller has already
    /// `subscribe()`-d — emitting the 7 warnings and dropping all 7 bindings.
    ///
    /// When ON: a `private var isSubscribing` sentinel is set BEFORE any
    /// `await`, blocking the actor-reentry path. Additionally the
    /// `realtimeChannel = channel` assignment moves to BEFORE
    /// `await channel.subscribe()` so a re-entry that defeats the sentinel
    /// (e.g. cross-actor) still hits the `realtimeChannel != nil` guard.
    /// Source order of `.postgresChange(...)` → `Task { for await ... }` →
    /// `subscribe()` is unchanged. On first successful subscribe the service
    /// emits `perf.signpost.realtime.subscribe_order=fixed` so we can grep
    /// production logs for confirmation.
    ///
    /// When OFF: byte-identical to pre-overhaul behavior (the actor-reentry
    /// race remains, the 7-warning cold-start signature continues to fire).
    static var phase6RealtimeCallbackOrder: Bool {
        flag("perf_phase6_realtime_callback_order", default: defaultEnabled)
    }

    /// Phase 6 (Olympian) — `OlympianPathService.rebuildGoals` atomic
    /// completion gate.
    ///
    /// Cold-start race (1.39 (70) bug-intel logs):
    ///   1. `loadCurrentSeason()` returns 33 path assignments.
    ///   2. Parallel `get_user_achievements` RPC gets CANCELLED (typically
    ///      superseded when SwiftUI tears down a parent `.task` during
    ///      scenePhase transitions / dashboard navigation cascades).
    ///   3. `rebuildGoals` then runs synchronously with `assignments=33`
    ///      but `BadgeService.achievements` empty (cancellation left it so).
    ///      `compactMap` against an empty cache yields `goals=[]` → all 33
    ///      paths render as blank goal status (no progress, no checkmarks).
    ///   4. Phase 1.2's 60s TTL cache then HITS, so subsequent
    ///      `loadCurrentSeason` calls keep using the same stale empty
    ///      achievements cache for the rest of the TTL window.
    ///
    /// When ON: `loadCurrentSeason` gates `rebuildGoals` atomically on
    /// `BadgeService.achievements.isEmpty`. If the cache is empty after the
    /// resync's tail fetch, schedule exactly ONE retry after 350ms before
    /// calling `rebuildGoals`. If the retry also fails, surface
    /// `Notification.Name.olympianGoalsStale` + a single `.warning` log
    /// (instead of fake-empty progress UI). First-attempt cancellations
    /// log at `.debug` (we know retry will fire); retry-fail logs at
    /// `.warning` exactly once. Phase 1.2 invalidation observers continue
    /// to drive a full re-fetch + atomic rebuild after `workoutCompleted`
    /// / `mealLogged` / `friendAdded` / `personalRecord` /
    /// `achievementUnlocked` events (their FIXMEs land in a separate PR
    /// — the rebuild path here works for them as soon as they wire).
    ///
    /// When OFF: byte-identical to pre-Phase-6 behavior (the buggy
    /// original path stays — race can blank goals UI on cold start).
    ///
    /// Production rollout (2026-05-10): default flipped from `defaultEnabled`
    /// (DEBUG/TestFlight only) to `true` for ALL builds after the
    /// 2026-05-10 NUJ audit surfaced `knovak98@hotmail.com` hitting the
    /// legacy buggy path on 1.39+ App Store: `assignments=33 but cache lacks
    /// all keys`, blank Olympian goals UI on cold start. Phase 6 has been
    /// in TestFlight since 1.39 (70) without regressions; promoting to
    /// production-default is the right call. UserDefaults override is still
    /// honored, so a remote kill-switch via `UserDefaults.standard.set(false,
    /// forKey: "perf_phase6_olympian_goals_atomic")` (e.g. via a future
    /// remote config rollout) can roll back without a release.
    static var phase6OlympianGoalsAtomic: Bool {
        flag("perf_phase6_olympian_goals_atomic", default: true)
    }

    /// Phase 6 (Workout-tab render) — `WorkoutTabView` first-render
    /// slimming.
    ///
    /// Audit (1.39 (70) cold-start logs, 2026-05-07): Phase 5.B
    /// `SmartProgramRecommender` pre-warm landed (4× cache_hit_rate=1
    /// on first body eval, confirmed) yet the Workout tab still
    /// reports `[TAB SWITCH] Slow transition: 777.0ms`. The recommender
    /// was a symptom; the dominant remaining cost is the rest of
    /// `WorkoutHomeView.body` instantiating `WorkoutStatsSection()` —
    /// a NON-lazy `VStack` of 12 chart widgets (per the explicit
    /// `// Use VStack (not LazyVStack)` comment at
    /// `WorkoutStatsView.swift:94`) — synchronously during the
    /// tab-transition frame. Each widget evaluates its `body` (Charts +
    /// stroke + gradient render passes), kicks off a Core-Data `.task`,
    /// and — for some — initializes a `@StateObject` singleton
    /// (`WeightTrackingService.shared` etc.) for the first time on
    /// cold start. None of this content is above-the-fold; it lives
    /// below Recent Activity + Next Up.
    ///
    /// When ON: `WorkoutStatsSection` is mounted via a 500ms-deferred
    /// wrapper (mirrors the canonical 250ms `Task.sleep` pattern from
    /// QP-19 `loadCardioWorkoutsThisWeek`, doubled because the chart
    /// widgets are heavier than a single Supabase fetch — and stats
    /// is below-fold so an extra 250ms is invisible) and the first
    /// tab-transition frame ships without 12 chart-widget `body`
    /// evals. The Phase-5.B recommender pre-warm continues to hit on
    /// first body eval (cache key untouched). A `signpost`
    /// `perf.signpost.workout_tab.first_render_ms=<ms>` lands once
    /// per WorkoutHomeView lifecycle for measurement.
    ///
    /// When OFF: byte-identical to pre-Phase-6 — `WorkoutStatsSection`
    /// is mounted inline, signpost still emits (telemetry is
    /// unconditional so on/off can be compared in the same build).
    static var phase6WorkoutTabRender: Bool {
        flag("perf_phase6_workout_tab_render", default: defaultEnabled)
    }

    // MARK: - Defaults

    /// Flags default ON in DEBUG and TestFlight builds (so internal users
    /// exercise the optimized path). They default OFF in App Store production
    /// until each phase has 48h of TestFlight validation.
    private static var defaultEnabled: Bool {
        #if DEBUG
        return true
        #else
        return AppConfig.isTestFlight
        #endif
    }

    private static func flag(_ key: String, default fallback: Bool) -> Bool {
        if UserDefaults.standard.object(forKey: key) != nil {
            return UserDefaults.standard.bool(forKey: key)
        }
        return fallback
    }
}
