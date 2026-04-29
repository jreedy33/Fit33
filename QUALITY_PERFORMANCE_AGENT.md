# Fit33 Quality & Performance Staff Engineer Agent

> **Role**: Testing, performance, memory, accessibility, error handling, app stability.
>
> Dated crash-analysis reports, sprint fix logs, and benchmarks live in [`docs/history/QUALITY_PERFORMANCE_AGENT.md`](docs/history/QUALITY_PERFORMANCE_AGENT.md).

Cross-cutting rules (logging, force unwraps, `@Published` thread safety, RLS, Core Data context safety, `Task { }` vs `Task.detached`, etc.) live in `.cursor/rules/codingrules.mdc` (universal) and `.cursor/rules/swiftui-rules.mdc` (auto-loads when editing `Fit33/**/*.swift`).

---

## Invariants (QP-specific — will cause crashes / perf regressions if violated)

### Timers & observers
1. **Service-lifetime repeating `Timer`s MUST have a lifecycle.** Store the handle, invalidate on `willResignActive`/`didEnterBackground`, restart on `didBecomeActive`, release observers in `deinit`. Leaking timers wake the CPU while the app is suspended.
2. **View-local `Timer`s MUST store + invalidate.** Store in `@State Timer?` (one-off) or an `@StateObject` wrapper (shared pattern). Invalidate any prior timer in the start function (rapid-tap protection) and from `.onDisappear`. Canonical shared helper: `PhoneOTPCountdown` in `Fit33/ExistingUserPhonePrompt.swift`.
3. **Never poll a Timer alongside a Realtime subscription for the same domain.** Pick one. `FriendsTabView` = Realtime + `.refreshable`, no polling.
4. **Single HK observer owner.** `BackgroundChallengeSyncService` is the ONLY owner of `HKObserverQuery`. `HealthKitManager` and others listen to `.healthStepsDidUpdate` / `.externalWorkoutSynced` notifications. To add a new HK sample type, add it to `BackgroundChallengeSyncService.hkSampleTypesToObserve` and post the right notification from `handleBackgroundHealthUpdate`.

### Instrumentation + monitoring
5. **Instrumentation gate rule.** Any `CADisplayLink` / `Thread.sleep` / repeating `Timer` / `DispatchSourceTimer` used for telemetry MUST be either `#if DEBUG` gated OR paused on `.background` scenePhase and resumed on `.active`. A 60Hz CADisplayLink in release burns battery for no user benefit. Canonical: `ProductionFPSMonitor.start()` and `MainThreadWatchdog.start()` are both DEBUG-gated + scenePhase-paused.
6. **Canonical performance stack (use these, don't add new ones):**
   - `MetricKitSubscriber` — Apple hang/launch/CPU/disk (release-active, zero overhead; canonical crash telemetry)
   - `ProductionFPSMonitor` — DEBUG-only, logs FPS < 55 for 500ms+
   - `MainThreadWatchdog` — DEBUG-only, freezes > 1.5s
   - `ScrollPerformanceTracker` + `.trackScrollJank(screen:)` — via `SessionLogManager.logScroll`
   - `PerformanceBenchmarkView` — DEBUG dashboard in Settings

### JSON + offline
7. **JSONSerialization safety.** ALWAYS call `JSONSerialization.isValidJSONObject(obj)` before `.data(withJSONObject:)`. `try?` does NOT catch Objective-C `NSInvalidArgumentException` — it causes SIGABRT. Critical for `MXMetricPayload.jsonRepresentation()`.
8. **Offline writes must queue, not log-and-drop.** Network writes from user actions (`saveWorkoutToCloud`, social posts) persist failures to `CloudSyncRetryQueue.shared` (file-backed JSON in Application Support). The queue drains from `Fit33App.onChange(of: scenePhase)` on foreground.
9. **Notification type allowlist = single source of truth.** `NotificationManager.knownNotificationTypes` is authoritative. Every new server-side push or in-app notification adds its `type` to both the enum and the allowlist in the same PR. `NotificationAllowlistTests` enforces the contract.

### Audio + video
10. **AVAudioSession is refcounted, not kept alive.** Never call `setActive(true)` at service init. Use `VideoStreamingService.activateAudioSessionIfNeeded()` (lazy, NSLock-guarded) on first player creation and `deactivateAudioSessionIfActive()` (`.notifyOthersOnDeactivation`) when the cache drains or app backgrounds. Keeping it active silently interrupts the user's music every launch.
11. **Video prefetch consults NetworkMonitor.** Every speculative `VideoPreloadManager`/`VideoStreamingService.prefetch*` path early-returns on `NetworkMonitor.shared.shouldAvoidBackgroundTraffic` (`isExpensive || isConstrained`). On-demand playback the user initiated is never gated. New entry points go through `VideoStreamingService.shouldSkipBackgroundPrefetch(reason:)`.
12. **AVFoundation object creation OFF main thread.** `AVURLAsset`, `AVPlayerItem`, `AVQueuePlayer`, `AVPlayerLooper` construction uses `Task.detached`. Only the final `@Published` assignment hops to `MainActor.run`.

### Motion + accessibility
13. **Decorative animations gate on BOTH `isLowPowerMode` AND `accessibilityReduceMotion`.** Canonical helper: `AnimatedOrbBackground.shouldDisableMotion`. Never ship a decorative animation without both checks. **Sprint 2026-04-24 audit wire-up** — `PulsingRedDot.onAppear`, `FriendsTabView.featuredChallengeCard` rotating glow (`challengeGlowPhase`), `HealthyRecipesCarousel` locked-card rotating glow + shimmer loader, and `RecipeBrowserView` locked-card rotating glow all now gate on `ProcessInfo.processInfo.isLowPowerModeEnabled || UIAccessibility.isReduceMotionEnabled`. If you add a new `.repeatForever`, gate it the same way — observed 10-21fps sustained scroll drops in 1.38 (53) Low Power Mode logs from ungated ambient animations.
14. **Orbs are single-fire, not `.repeatForever`.** Drift to end over 3-5s and stop. Continuous rendering was regressing FPS on all tabs.

### HealthKit
15. **HealthKit error classification.** Errors whose `localizedDescription.lowercased()` contains `"protected health data"`, `"no data available"`, or `"authorization not determined"` are EXPECTED (device locked / no samples / not-yet-granted). Log at `.debug`, never `.error`. Wording changes across iOS versions — use `.contains` matching.
16. **All HK fetch methods check `isAuthorized` before executing queries.** Query callbacks log via `AppLogger`, never silently return nil. iOS can revoke at any time.

### Bulk work on main thread
17. **Sorting/filtering 1000+ items MUST run off main thread.** Workout generator, swap graph, filter cache all iterate 5000+ exercises — never block main. Use `Task.detached` or background Core Data context.
18. **Suppress per-item debug logging during bulk operations.** Pattern: `WorkoutGeneratorService.suppressPerExerciseLogs`. Logging 1000+ items on main was the #1 cause of generation freezes.
19. **Tab switch handlers are minimal.** Only critical sync state updates (tab selection, button hide). Per-step logs/analytics use the single summary log at the end. **Non-critical network fetches in a tab's `.task` MUST `Task.sleep(~250ms)` past the tab-transition animation frame** — otherwise the decode + `@Published` publish lands on the same frame as the animation commit, producing the 1352ms slow transitions observed in 1.38 (53) logs. Canonical: `WorkoutTabView.loadCardioWorkoutsThisWeek` wrapped in `try? await Task.sleep(nanoseconds: 250_000_000)` before fetch.
19b. **Independent network calls in a tab's `.task` MUST use `async let` groups, not sequential `await`.** Same rule as PE invariant #2, repeated here because it shows up in perf logs as "tab slow to show data". Canonical fix this sprint: `DashboardView+Helpers.loadRecentCardioWorkouts` and `PrivateChallengeDetailView.task` both parallelized — the private-challenge view's 6712ms render in 1.38 (53) logs was two sequential fetches on slow network.
19c. **Pull-to-refresh closures MUST split visible-widget work from background-sync work.** Sprint 2026-04-24 Phase 3: `DashboardView.refreshable` awaits ONLY the 4 widgets visible on the dashboard body (`fetchDailyQuests`, `loadTodayData`, `loadRecentCardioWorkouts`, `loadPersonalizedRecommendation`), raced against a 5s hard cap. Heavy syncs (HealthKit multi-source, community + private challenge full refresh, challenge invite + active + group + sent, friend home refresh) fire-and-forget via standalone `Task { ... }` — their `@Published` updates push to the UI as they land. Without this split, one slow provider (WHOOP auth hang, Strava 5xx, etc.) held the spinner visible until eternity in 1.38 (54) logs. Fire-and-forget is SAFE here because `HealthDataService.syncAllHealthData` coalesces (invariant #24c-foreground) — stacking these calls doesn't spawn parallel syncs.
19d. **Dashboard `.task` social fanout: realtime-subscribe + PYMK are fire-and-forget.** `PrivateChallengeService.subscribeToRealtimeUpdates()` blocks until the websocket is subscribed (2-4s on cold connection) and no visible dashboard widget depends on the subscription having returned; realtime updates push through `@Published` as they land. `ContactsService.refreshSuggestions()` populates the Friends-tab PYMK card, not the dashboard. Both now kick off via standalone `Task { }`. 1.38 (55) logs: `dashboard.social_fanout took 4511ms` dominated by those two. Awaited group of 12 is still parallel via `async let`; slowest-in-group now bounded by actual dashboard-critical fetches.
19e. **App-foreground pipeline: only the user-visible critical path blocks.** `Fit33App.onChange(of: scenePhase) → .active` separates the blocking critical path (auth recover → realtime reconnect → social fanout → health sync → challenge refresh) from fire-and-forget housekeeping (push re-registration, daily-reset check, profile sync, badge count, retry-queue drain, opponent wake). 1.38 (55) logs showed 6035ms because the tail 7 tasks were serialized when none of them gate any visible UI update. Rewrote all of them as standalone `Task { ... }` inside the main foreground task. `app.foreground` signpost now tracks only the blocking segment.

### Shared mutable state + formatters
20. **`DateFormatter` / `NumberFormatter` / `ISO8601DateFormatter` MUST be `static let`** (or `@StateObject`-owned) — never computed properties. Construction is expensive (~1ms each) and allocating one per row during scroll guarantees jank.
21. **`@unchecked Sendable` classes with mutable state MUST use a lock** (`NSLock` or `OSAllocatedUnfairLock`) around every read and write. The `@unchecked` tells the compiler to skip checks; the lock is what actually prevents data races.

### Timers (user-facing)
22. **Never frame-delta accumulate for user-facing countdowns.** Always anchor to wall-clock `Date` (`elapsed = Date().timeIntervalSince(startedAt)`) so time survives display-link pauses during tab switches or backgrounding. The `RestTimer` regression in `RestTimerViews.swift` was caused by `CADisplayLink` delta subtraction guarding out large deltas.
23. **`isIdleTimerDisabled` MUST be reset to `false` on `.onDisappear`.** `ActiveWorkoutView` sets `UIApplication.shared.isIdleTimerDisabled = true` on `.onAppear` (gated by `keepScreenOn`) and resets it on `.onDisappear`. Forgetting the reset drains battery if the user leaves the workout view mid-session.

### HealthKit save reliability
24. **HealthKit save methods MUST retry with exponential backoff** on timeout errors — 3 attempts, 2s / 4s spacing. User-facing "Save failed" never fires for a transient timeout.
24b. **HealthKit→Supabase workout imports retry once on transient failure.** `HealthDataService.upsertCardioWorkoutWithRetry` wraps the `cardio_workouts` upsert with a 2s single retry on timeout / network / 5xx. Duplicate / conflict errors short-circuit before the retry. Without this, a single network blip silently drops the import — and with `WorkoutWearableMerger` depending on that row to render the WHOOP / Apple Watch / Oura insights card on the matching Fit33 workout, a dropped import = no wearable card.

### Background sync coalescing
24c. **`BackgroundChallengeSyncService.performChallengeSyncInBackground()` MUST coalesce concurrent invocations.** HealthKit wakes the app with multiple `HKObserverQuery` types at once (workout + steps + active_energy → three observer callbacks in the same millisecond). Every service it calls is `@MainActor` (`HealthKitService`, `ChallengeService`, `StravaService`, `FitbitService`, `PrivateChallengeService`, `CommunityChallengeService`), so three stacked invocations serialize on the main actor and produce a multi-second main-thread hang (2.4s observed in dev-session 1121BD51). Canonical pattern: a `@MainActor private var inFlightSyncTask: Task<Void, Never>?` — if non-nil, new callers `await existing.value` and return; the task clears itself on completion. Never spawn per-observer work without coalescing.
24c-foreground. **`HealthDataService.syncAllHealthData(force:)` ALSO coalesces.** Same pattern, different service. Without the gate, `force: true` callers (pull-to-refresh + scenePhase foreground + realtime callbacks) stack on top of each other — Sprint 2026-04-24 Phase 3 observed 9× `HealthKit.syncAll` in a single startup waterfall (first one 3.2s, the rest throttled to ≤140ms each) because the `isSyncing` flag alone bypassed on `force`. Now `syncAllHealthData` holds an `inFlightSyncTask`; concurrent callers `await existing.value` regardless of `force`. `force` still skips the 5-minute throttle, but NEVER the single-flight guarantee.
24d. **Do NOT double-sync HealthKit on the workout-observer path.** `performChallengeSyncInBackground` already calls `HealthKitService.syncAllData(force: true)` as Step 1 — the workout-observer completion handler posts `.externalWorkoutSynced` and moves on. A previous implementation ran a SECOND `syncAllData(force: true)` right after; that was redundant and doubled main-thread HK query work on every watch workout.

### Log-level discipline (beyond HK)
25. **Normal user actions log at `.debug` or `.info`, never `.error`.** Dismissing a sheet, cancelling an operation, declining a permission prompt, empty results — all expected user choices. `.error` is reserved for actual malfunctions that need investigation.
25a. **Supabase / URL-backed catch blocks MUST use `NetworkErrorClassifier`** (`Fit33/NetworkErrorClassifier.swift`) instead of `AppLogger.error(...)`. Any `AppLogger.error` call: (a) writes a `dev_session_logs.entries[type=error]` row, (b) invokes `CrashReportingService.reportError()` — which together create a `bug_intelligence_fingerprint` that Claude triages. Logging a transient `NSURLErrorTimedOut` or cancelled task at `.error` manufactures a "bug" per occurrence. The classifier keeps transient network (timeout/cancelled/connection-lost), expected HealthKit (protected/no-data/auth-not-determined), and auth-expired/RLS-rejection failures at `.warning` (or `.debug` via `transientLevel: .debug` on retry-covered paths like dashboard fetches and offline-queue flush). Use `.error` only for a true malfunction surfaced after retries exhaust.
25b. **`MainThreadWatchdog.start()` and `ProductionFPSMonitor.start()` are defensive-`#if DEBUG` internally** (since 2026-05-02). Callers — `Fit33App.swift`, `PerformanceOptimizationsInitializer.initialize` — also gate. Never remove either gate: release builds rely on `MetricKitSubscriber` alone, and running the watchdog on a TestFlight cold start fires 20+ `.warning` freeze reports per user.

### Bug-Intel pipeline ownership (extracted to Bug Intelligence Agent — 2026-04-29)

> The Phase 9 / 10 / 12 / 13 invariants that used to live here as `25c–25h` and `25i-bugintel`–`25s-bugintel` (DiagnosticContext + signposts, structural fingerprinting, classifier_lint enforcement, noise-filter denylist sync, `auto_resolved_reason` taxonomy, `severity_score` ordering, migration→fingerprint `Resolves:` convention, `bug_intel_resolved_history` + `find_similar_resolutions`, severity weights table, `triage-bugs` SYSTEM_PROMPT contract, Phase 13 `root_cause_fingerprint` + `bug_intel_extract_pg_code`) all moved into **`BUG_INTELLIGENCE_AGENT.md`** in Sprint 2026-04-29. That agent is now the single owner of the bug-intel pipeline end-to-end.
>
> Quality & Performance still owns invariant **25a** (the rule "every Supabase / URL-backed catch routes through `NetworkErrorClassifier`") because it's a Swift code-shape rule that surfaces on every PR — but the *why* (it prevents fingerprint spam in the bug-intel pipeline) and the implementation details (DiagnosticContext, op registry, classifier_lint, denylist, severity scoring, Phase 13 collapse) live in the Bug Intelligence agent. When you see a bug-intel-related question, defer there.

### Exercise poster stills (cells)
25i. **`ExercisePosterRingIcon` cache reads MUST be synchronous on appear; generation MUST NOT poll on `MainActor`.** The cell calls `ExercisePosterSmartCrop.shared.cachedCrop(for:)` (disk+memory, <5ms) and shows the result or fallback immediately. Cache-miss paths use `requestBake` / `requestGenerationAndBake`, which run on serial utility-QoS queues, gate speculative video generation on `NetworkMonitor.shared.shouldAvoidBackgroundTraffic` (invariant #11), and post `.exercisePosterSmartCropReady` when done. Cells listen via `.onReceive` — never via `Task { @MainActor in … Task.sleep … }` polling, which retains one main-actor Task per visible cell and was the cause of the 2026-04-23 Exercise tab scroll slowdown. Smart-crop results persist as ~12KB JPEGs in `Caches/exercise_smart_crops/`, so subsequent launches skip Vision entirely.

### User focus gating (Sprint 2026-04-24 Phase 4)
25n. **Detail views that hit the network on `.task` MUST signal `UserFocusSentinel.beginFocus / endFocus`.** The sentinel is polled by `CPUProtection.waitForUIIdle`, which intelligence phases call before starting each heavy step. Before this signal existed, 1.38 (55) logs showed 15079ms to render `PrivateChallengeDetailView` when the user tapped it during the 10-30s post-startup window — `Intel: buildMaps` + `PAIRING ENGINE` + `COLLABORATIVE` + `LEARNING ENGINE behavior` + similarity-map build were all hammering the CPU while the detail view tried to network-fetch + render. Now the intelligence phases pause the moment the user navigates into a detail view and resume when they navigate back. Canonical wire-ups: `PrivateChallengeDetailView.task` + `.onDisappear`, `ChallengeDetailView.onAppear` + `.onDisappear`, `GroupChallengeDetailView.task` + `.onDisappear`, `FriendProfileView.onAppear` + `.onDisappear`. Each call uses a unique string id — the sentinel is a counter keyed by id (supports stacked pushed views). NEVER forget the `.onDisappear` — a leaked focus permanently pauses all intelligence work for the session.

### Auth session recovery (Sprint 2026-04-24 — 1.38 (54))
25k. **`SupabaseManager.checkAuthOnly()` MUST use a cached-then-refresh pattern, not `await client.auth.session`.** The Supabase Auth SDK's `session` async getter internally calls `refreshSession()` whenever the access token is expired or within 30s of expiry — that's a network round trip. On a slow / congested connection this observed 5824ms in 1.38 (53) session logs, blocking first-frame interactivity. Fast path: (1) `client.auth.currentSession` (nonisolated, sync) — if present AND `!isExpired`, set `isAuthenticated = true` immediately, no network. (2) If expired, race `refreshSession()` against a 1.5s timeout (`withTimeout` helper in `SupabaseManager.swift`); on timeout, still set auth optimistically from the cached session and retry refresh in a background `Task.detached`. (3) Only when `currentSession == nil` do we `await client.auth.session` — that path is fast on any network because there's nothing to refresh. PostgREST auto-401s on stale tokens and the SDK re-refreshes, so losing ~1s of true-token freshness is acceptable for kill-the-6s-blocker.

### Private challenge card unread dot
25j. **Unread-message indicators on private-challenge cards MUST be derived, not fetched.** `PrivateChallengeService.hasUnreadChat(for:)` compares the existing `PrivateChallenge.lastChatAt` column (already selected by `get_my_private_challenges`) against a per-challenge "last read" `Date` dict persisted in `UserDefaults` under `private_challenge_chat_last_read_v1`. There is NO new DB query, NO new realtime subscription, and NO extra RLS round-trip — the existing `chatInserts` postgres-change handler inside `subscribeToRealtimeUpdates` already refetches `myChallenges` on every message, which publishes a new `lastChatAt` and invalidates the card body. `markChatAsRead(challengeId:)` is called from `PrivateChallengeDetailView.task` on appear AND on every inbound realtime insert while the chat is visible, so the dot clears the moment the user sees a message. The dot itself (`UnreadPulsingDot`) uses a single `withAnimation(.easeOut.repeatForever)` on scale+opacity, gated by `reduceMotion || isLowPowerModeEnabled` (invariant #13). Animation cost is bounded at ≤3 concurrent instances (widget shows `challenges.prefix(3)`) and SwiftUI auto-pauses off-screen animations when scrolled out of view.

### Widget reload budget (Sprint 2026-04-26)
25t. **Every `WidgetCenter.shared.reloadAllTimelines()` call MUST go through a bridge with hash-gate + 8s coalescing.** Canonical: `Fit33/ActiveChallengeWidgetBridge.swift::requestReloadIfNeeded(payloadHash:reason:)` and `Fit33/DailyGoalsWidgetBridge.swift::requestReloadIfNeeded(payloadHash:)`. iOS gives every widget extension a finite per-day reload budget (~40-70 reloads/day on most devices); foreground activity + HK observers + Supabase realtime + scenePhase + silent push can each independently trigger 5-10 reloads/min during active use, which silently exhausts the budget and produces the "stale widget" symptom we're trying to avoid. The gate has two stages: (1) hash the encoded payload — if it matches the previous publish, skip the reload entirely (data didn't change); (2) inside an 8-second window since the last successful reload, schedule a single trailing reload via `Task { @MainActor in ... }` instead of firing immediately — bursts coalesce to one. The App Group bytes are written every publish regardless, so the widget's next scheduled timeline tick always picks up the freshest data. NEVER call `WidgetCenter.shared.reloadAllTimelines()` directly from a service — always route through a bridge.
25u. **HK-observer optimistic widget updates MUST go through `ActiveChallengeWidgetBridge.publishOptimisticLocalProgress()`.** Sprint 2026-04-26 Phase 1: HealthKit observer events now patch the widget snapshot in <1s using `ChallengeProgressResolver.resolveProgress(...)` (which already knows how to map every `ChallengeType` to the right local source — `HealthKitService.todaySteps` / `todayActiveMinutes` / `todayDistance`, `HydrationService.todayTotal`, `MealService.todaysMeals`, `ReadinessService.todayReadiness`), instead of waiting 5-30s for the full `BackgroundChallengeSyncService.performChallengeSyncInBackground` Supabase round-trip. Wired from BOTH `HealthKitService.syncTodayStats` (`MainActor.run` after `todaySteps`/`todayCalories`/`todayDistance` commit) AND `HealthKitService.syncRecentWorkouts` (after `todayActiveMinutes` commit) AND `HealthKitManager.fetchTodaySteps` (after `todaySteps` commit — resolver reads manager first). Optimistic patches MAY ONLY raise displayed progress (`max(stored.myTodayProgress, live)`) — never regress, otherwise a transient HK read at midnight rollover or after permission revoke would flicker the widget downward. Server-truth always lands a few seconds later via the regular `cacheActiveChallenges` → `publish` path and overrides if the server saw something the local read didn't. The hash-gate (invariant 25t) makes this safe to call on every HK refresh — if nothing changed, the call is free.
25v. **Widget timeline `policy: .after(...)` MUST be ≤ 20min for any widget showing live progress.** `RunningActivityWidget/ActiveChallengeWidget.swift::ChallengeTimelineProvider.timeline` and `RunningActivityWidget/RunningActivityWidget.swift::DailyGoalsProvider.getTimeline` both refresh every 20-30 min. The bridge-driven reload (invariants 25t + 25u) handles the live-progress case; the timeline policy is the safety net for users who haven't opened the app in hours. 1hr was too slow — a user who hasn't opened the app since morning sees their own steps from the previous tick. Don't go lower than 15min — iOS aggressively coalesces same-extension timeline ticks and you'll burn budget for diminishing returns.

### Realtime Widget Server Pull (Sprint 2026-04-26)
25w. **Widget extension MUST use raw `URLSession`, not the supabase-swift SDK.** `RunningActivityWidget/WidgetSupabaseFetcher.swift` is the only network surface in the widget process. iOS gives extensions a hard ~30 MB memory ceiling; the supabase-swift SDK pulls in Auth + PostgREST + Realtime + Storage + GoTrue and trips the ceiling on every cold timeline tick (observed `widgetkit-extension(SIGKILL Jetsam)` reports during Phase 2 spike). The `URLSession` path uses the shared App Group JWT (read-only — see `INFRA_SECURITY_AGENT.md` 21a) and a 3s timeout — if the network is slow, fall back to the App Group cache and let the next 20-min timeline tick try again. NEVER add the supabase-swift SPM product to the widget target. Same rule for `Fit33Watch/WatchSupabaseClient.swift`.
25x. **`URLSession` Supabase calls in extensions MUST set `URLSessionConfiguration.waitsForConnectivity = false` and `timeoutIntervalForRequest = 3.0`.** Widget timelines and `WKApplicationRefreshBackgroundTask` have a finite system-imposed budget (typically 5-30s); a hung TCP connect on cellular eats the entire budget and the system kills us before the cache fallback runs. Both `WidgetSupabaseFetcher` and `WatchSupabaseClient` enforce this — when adding a new extension network call, match the pattern.
25y. **`ProgressFreshnessKit` is duplicated between main app and widget extension on purpose.** `Fit33/Shared/ProgressFreshness.swift` and `RunningActivityWidget/ProgressFreshness.swift` MUST stay byte-for-byte identical (thresholds, label format, `shouldShowRawValue`). We do NOT extract this into a shared SPM package because the cost of an additional SPM target build + Codable bridge is higher than the cost of touching two files when thresholds change. When you change one, change the other in the same commit. A unit test (`ProgressFreshnessParityTests`) hashes both files and fails the suite if they drift.

### Widget Freshness Sprint Phase 7 (2026-04-26)
25z. **HealthKit observer throttle is per-source, not global.** `BackgroundChallengeSyncService.throttleInterval(for:)` returns 120s for `steps` and 600s for everything else (`active_energy`, `distance`, `exercise_time`). Steps are the highest-frequency widget number and need to land on the server inside ~2 min in the worst case so opponents see fresh counts via the realtime + progress_update fast paths. Other sources (energy / distance / exercise time) accumulate over longer windows and don't justify the wake budget — keep them at 10 min. Workouts (`isHighPriority`) ignore the throttle entirely. NEVER reintroduce a single global `perSourceThrottleInterval` — it caused widgets to lag by up to 10 minutes.
25aa. **Low-priority HK observer wakes use the LITE path; workout completions use the FULL path.** `BackgroundChallengeSyncService.usesLiteWakePath(for:)` returns `true` for `steps` / `active_energy` / `distance` / `exercise_time`, `false` for `workout`. Low-priority observers fire often, and on the 2-min steps cadence (invariant 25z) the FULL pipeline (Strava + Fitbit + WHOOP + Oura + ReadinessService + meals + hydration + Quests + Intelligence cache + recursive opponent wake) would burn an enormous wake budget for data that doesn't affect a step delta. The LITE path (`performLiteWakeSync`) does HK refresh + active-challenge fetch + per-service push only. Workout completions stay on the FULL path because they need Strava enrichment + `cardio_workouts` persistence + readiness recompute. The FULL pipeline still runs on the regular `BGAppRefresh` / `BGProcessing` / `scenePhase=active` / silent-push (`challenge_wake`) paths, so nothing is lost — the lite-routed observers just don't trigger it on every step batch. Pairs with Infra invariant 15a (`challenge_wake` runs LITE) — the routing convention is symmetric.
25cc. **Widget-side write-back to `log_challenge_progress` is debounced + value-deduped per challenge.** Phase 7d (2026-04-26): `RunningActivityWidget/ActiveChallengeWidget.swift::pushFreshStepProgressIfNeeded` writes today's HK step count to the server when it exceeds `myTodayProgress`, fire-and-forget via `Task.detached`. Per-challenge throttle 120s (matches main-app `BackgroundChallengeSyncService` steps cadence — invariant 25z) AND per-challenge value-dedupe (skip when `lastValue >= hkSteps`). State persisted in App Group `UserDefaults` so it survives widget process restarts. 401 (expired JWT) is the dominant failure mode and is treated as terminal-for-this-tick — bump the throttle so we don't re-fire the same dead-token call every 20 min and bail out of the loop. Other failures (transport / 5xx) are logged at debug and let the next tick retry. The push uses `p_source: "widget"` so server-side audits + the kill switch (`internal_config.widget_writes_enabled`, migration `20260626`) can identify and disable it independently. The fanout trigger (Data invariant #48) AND the new opponent-notify trigger (Data invariant #50) both fire on this write the same as any other client push — so opponents see the fresh number within ~5–10s end-to-end even when the writer's main app is force-killed.

25bb. **Widget extension reads HealthKit directly via `HKStatisticsQuery`, never `HKObserverQuery`.** `RunningActivityWidget/WidgetHealthKitReader.swift::todayStepsIfAuthorized()` runs a single cumulative-sum stats query for `stepCount` over today's local-day window during each timeline tick, races a 1.5s timeout, and returns nil on auth failure / no samples / unavailable HK. The result is overlaid on `myTodayProgress` for step-typed challenges (`challengeType == "steps"` OR `targetUnit == "steps"`) via `max(server, hk)` — monotonic, never regresses below the server-confirmed value (mirrors invariant 25u). Authorization fast-path: `authorizationStatus(for:) == .notDetermined` → bail before the query (Apple lies about READ status as a privacy feature, but `notDetermined` is reliable). The `com.apple.developer.healthkit` entitlement is set on `RunningActivityWidget.entitlements`; Xcode capability flag must also be enabled on the target so `HealthKit.framework` is linked. The widget extension MUST stay read-only — never call `enableBackgroundDelivery` or `HKObserverQuery` from the extension (observers are not delivered to widget processes; HK in extensions is single-shot stats queries only). The main app's `NSHealthShareUsageDescription` covers the extension via bundle inheritance — no widget Info.plist change.

### Cross-references
26. **Exercise Library never renders a loading placeholder** — see `PRODUCT_ENGINEER_AGENT.md` invariant #22. The fix is always in the data layer (bundle-JSON pre-warm), not in a view skeleton branch.

---

### Memory pressure thresholds (`PerformanceOptimizations.swift`)
25l. **Warning threshold = 650MB (Sprint 2026-04-24 Phase 3), NOT 500MB.** Phase 1 lowered it to 500MB to catch bursts earlier. Problem: the app's healthy working set after a full session (5 tabs loaded + intelligence maps + services) is 620+ MB — the warning fired on EVERY session and `clearWarmCaches` freed 0 entries because the baseline already had no warm caches to clear (1.38 (54) logs: `Cleared 1 warm cache entries` or 0). Pure log noise. Phase 3 raised to 650MB — above the healthy ceiling but well under critical (800MB) and emergency (950MB). 15s poll interval retained. Do NOT lower this back below 620MB without also restructuring the working set (tab services live for the session lifetime).

### Contact / PYMK refresh gating (`ContactsService.swift`)
25m. **`refreshSuggestionsIfNeeded` MUST have BOTH an in-session flag AND a persistent TTL.** The heavy path hashes 2000+ phone numbers, runs an RPC match, and upserts contacts to the server — observed 10fps sustained scroll drop for 2403ms in 1.38 (53) logs (the first Friends-tab visit per cold start). Contact membership doesn't change hour-to-hour, so a cross-session TTL (currently 6h, keyed by `contacts.last_suggestions_refresh_v1` in `UserDefaults`) skips the heavy path even on cold start when we refreshed recently. PYMK (friends-of-friends RPC) is lightweight and still runs every session. Pull-to-refresh bypasses both gates via `refreshSuggestions(force: true)`. When you add a new gate, extend `ContactsService.suggestionsRefreshTTL`.

## Performance Monitoring — Pre-Release Checklist
- [ ] Cold start < 500ms to first interactive frame (auth-only path, sync deferred 3s).
- [ ] Tab transitions (first visit) < 300ms; revisits < 150ms.
- [ ] No sustained FPS drop < 55 for > 500ms on Dashboard scroll, Exercise Library scroll, Active Workout scroll.
- [ ] No main-thread freeze > 1.5s under `MainThreadWatchdog`.
- [ ] Memory stable over a 60-minute active workout (no upward drift).
- [ ] Workout generator runs off-main (`nonisolated` + `Task.detached`).
- [ ] `@FetchRequest`s have `fetchLimit`.

---

## Testing Infrastructure
- `Fit33Tests/` — XCTest target (9 files): InputValidation, DTODecoding, WorkoutCalorie, ExerciseData, DesignSystem, ExercisePopularity, AppLogger, LogicAudit, NotificationAllowlist.
- `CriticalPathTests.swift`, `LimitationFilterTests.swift` — in-app diagnostics.
- `ActiveWorkoutTests.swift` — 16 tests (set init, progressive overload, swap tiers, historical data, UX). Run from `DevMenuView` test runner.
- CI: `.github/workflows/` — iOS build check, unit tests, syntax check, admin CMS CI.

---

## Key Owned Files
| File | Purpose |
|---|---|
| `NetworkErrorClassifier.swift` | Shared helper — classifies network/HK/auth errors into log levels + routes via `AppLogger`. Called from every Supabase/URLSession catch block across HealthKit/CrashReporter paths. Prevents transient-error fingerprint spam. Accepts `op/endpoint/startedAt/userId/retryAttempt` to synthesize a `DiagnosticContext` for bug-intel fingerprinting. |
| `DiagnosticContext.swift` | Structured metadata (`op`, `endpoint`, `elapsedMs`, `pgCode`, `httpStatus`, `userIdShort`, `retryAttempt`) attached to `AppLogger.log(context:)`. `PgErrorExtractor` inside pulls PostgREST error codes out of Supabase/Postgrest errors. |
| `PerformanceSignposts.swift` | Canonical `Op` enum + `OSSignposter` wrapper. `measure` / `begin+end` helpers log to Instruments and enqueue `PerformanceMetric` rows for `performance_metrics` upload. Slow-threshold warnings are auto-emitted with `DiagnosticContext`. |
| `PerformanceMetricsUploader.swift` | 30s timer + background-flush uploader that drains `PerformanceSignposts.pendingMetrics` into Supabase `performance_metrics`. Auth-guarded; 404 fails soft so the uploader is safe to ship ahead of migration 20260514 rollout. |
| `MetricKitSubscriber.swift` | Apple diagnostics telemetry. `didReceive([MXDiagnosticPayload])` forwards hang / crash / CPU-exception `callStackTree` + `metaData` JSON to `AdvancedSessionLogger.log(extra:)` (truncated to 16KB) so bug-intel can fingerprint freezes and SIGSEGVs by stack. |
| `ProductionFPSMonitor.swift` | DEBUG FPS monitor |
| `MainThreadWatchdog.swift` | DEBUG freeze detector |
| `ScrollPerformanceTracker.swift` | Scroll jank logging |
| `PerformanceBenchmarkView.swift` | DEBUG dashboard |
| `SessionLogManager.swift` | Structured session logs |
| `CloudSyncRetryQueue.swift` | Offline-write retry queue |
| `NetworkMonitor.swift` | Connection class detection |
| `BackgroundChallengeSyncService.swift` | Single HK observer owner |
| `CrashReportingService.swift` | Crash capture (co-owned with Infra) |
| `Fit33Tests/` | All XCTest files |

---

## Reopened / Tracked Issues
| Item | Status | Notes |
|---|---|---|
| 60+ `DispatchQueue.main.asyncAfter` (41 in `NewOnboardingView`) | Open | Replace with `Task.sleep` or animation APIs |
| 136 `.ignoresSafeArea()` across 87 files | Audit | Keep on backgrounds only |
| Large files (ContentView ~3k, SupabaseManager ~2.5k lines) | Open | Split into focused components |
| Memory leaks: Timer in `PerformanceOptimizations.swift:59`, animation timer in `WorkoutCompletionView.swift:152`, observer in `Fit33App.swift:247` | Open | Fix per invariant #1 + weak-self pattern |
| Accessibility labels: 14/500+ | Open | Dynamic Type + VoiceOver pass per screen |

---

## Accessibility Minimums
- All interactive elements: `.accessibilityLabel()` + `.accessibilityHint()`.
- Decorative elements: `.accessibilityHidden(true)`.
- Dynamic Type: no fixed heights that clip text; prefer `.minimumScaleFactor(0.8)` + `.lineLimit(nil)` for critical content.
- Color contrast: secondary text uses `.adaptiveSecondaryText` (verified readable both modes).

---

## Error Handling Standard
```swift
if let error = errorMessage {
    VStack(spacing: Spacing.sm) {
        Image(systemName: "exclamationmark.triangle.fill")
            .font(.ds_heading1).foregroundColor(.orange)
        Text("Something went wrong").font(.ds_heading3)
        Text(error).font(.ds_bodyMedium).foregroundColor(.secondary)
            .multilineTextAlignment(.center)
        DSPillButton(title: "Try Again", icon: "arrow.clockwise") { retryAction() }
    }.padding(Spacing.lg)
}
```
Every user-visible failure has: (1) icon, (2) plain-language message, (3) retry action when applicable.

---

## See Also
- `.cursor/rules/codingrules.mdc` — cross-cutting MUST/NEVER rules
- `.cursor/rules/swiftui-rules.mdc` — Swift/SwiftUI perf + quality rules (auto-loads for `Fit33/**/*.swift`)
- `PRODUCT_ENGINEER_AGENT.md` — widget isolation, parallel `.task` loading
- `DATA_BACKEND_AGENT.md` — Core Data context safety, UUID fallback rule
- `INFRA_SECURITY_AGENT.md` — crash reporting, background service patterns
- `docs/history/QUALITY_PERFORMANCE_AGENT.md` — dated crash reports, benchmarks, audit details
