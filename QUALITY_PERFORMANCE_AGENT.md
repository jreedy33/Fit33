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
24d. **Do NOT double-sync HealthKit on the workout-observer path.** `performChallengeSyncInBackground` already calls `HealthKitService.syncAllData(force: true)` as Step 1 — the workout-observer completion handler posts `.externalWorkoutSynced` and moves on. A previous implementation ran a SECOND `syncAllData(force: true)` right after; that was redundant and doubled main-thread HK query work on every watch workout.

### Log-level discipline (beyond HK)
25. **Normal user actions log at `.debug` or `.info`, never `.error`.** Dismissing a sheet, cancelling an operation, declining a permission prompt, empty results — all expected user choices. `.error` is reserved for actual malfunctions that need investigation.
25a. **Supabase / URL-backed catch blocks MUST use `NetworkErrorClassifier`** (`Fit33/NetworkErrorClassifier.swift`) instead of `AppLogger.error(...)`. Any `AppLogger.error` call: (a) writes a `dev_session_logs.entries[type=error]` row, (b) invokes `CrashReportingService.reportError()` — which together create a `bug_intelligence_fingerprint` that Claude triages. Logging a transient `NSURLErrorTimedOut` or cancelled task at `.error` manufactures a "bug" per occurrence. The classifier keeps transient network (timeout/cancelled/connection-lost), expected HealthKit (protected/no-data/auth-not-determined), and auth-expired/RLS-rejection failures at `.warning` (or `.debug` via `transientLevel: .debug` on retry-covered paths like dashboard fetches and offline-queue flush). Use `.error` only for a true malfunction surfaced after retries exhaust.
25b. **`MainThreadWatchdog.start()` and `ProductionFPSMonitor.start()` are defensive-`#if DEBUG` internally** (since 2026-05-02). Callers — `Fit33App.swift`, `PerformanceOptimizationsInitializer.initialize` — also gate. Never remove either gate: release builds rely on `MetricKitSubscriber` alone, and running the watchdog on a TestFlight cold start fires 20+ `.warning` freeze reports per user.

### Diagnostic context + signposts (Bug-Intel Sweep 2026-04-23)
25c. **Every Supabase catch path that already uses `NetworkErrorClassifier.log` SHOULD pass `op:` + `endpoint:` + `startedAt:` + `userId:`.** The classifier builds a `DiagnosticContext` (`Fit33/DiagnosticContext.swift`) and threads `pg_code` / `http_status` / `elapsed_ms` into both `AdvancedSessionLogger` and `CrashReportingService.additionalContext`, which is what lets the bug-intel rollup fingerprint by cluster (`C_uuid` 42883 vs `D_startup_timeout` 401) instead of collapsing everything into "Supabase error". The "caller provides `op`" convention keeps call sites self-documenting — never invent op names; pick one from `PerformanceSignposts.Op`.
25d. **New measurable operations MUST wrap in `PerformanceSignposts.measure` / `begin+end`** (`Fit33/PerformanceSignposts.swift`). The canonical op enum is the single source of truth for admin CMS Improvement Tracker perf columns and Instruments signpost filters. `end(state, slowThresholdMs:)` auto-emits a `.warning` with `DiagnosticContext` when the interval exceeds the threshold, and enqueues a `PerformanceMetric` for `PerformanceMetricsUploader` to drain into `performance_metrics` every 30s. The in-memory queue is capped at 500 (drops oldest) — do not try to persist synchronously in the hot path.
25e. **`PerformanceMetricsUploader` is auth-guarded + migration-soft-fail.** Start it once from `Fit33App.task` after `StartupCoordinator.markPhaseComplete(.critical)`. Skip uploading when `!SupabaseManager.shared.isAuthenticated`; 404 "table does not exist" (env without migration 20260514 applied) is already routed through `NetworkErrorClassifier` at `.warning` so it cannot itself generate a fingerprint. Never change the 30s interval without also updating the admin CMS `performance_metrics_daily` p50/p95 expectations.

### Structural fingerprinting + enforcement (Bug-Intel Phase 9 — 2026-04-23)
25f. **`op:` arguments MUST match a `PerformanceSignposts.Op.rawValue`.** Every `NetworkErrorClassifier.log(op:)`, `DiagnosticContext(op:)`, and `PerformanceSignposts.measure(op:)` call either passes `Op.xxx.rawValue` or a string literal that already exists in the enum. Enforced by `Fit33Tests/PerformanceSignpostsCoverageTests.testEveryOpStringLiteralMatchesRegistry`. Typoed ops splinter `bug_intelligence_fingerprints.structural_fingerprint` (introduced by migration 20260516) and break the "same root cause across N call sites" collapse. Add a new case to `PerformanceSignposts.Op` FIRST, then reference it from the call site.
25g. **Invariant 25a has automated enforcement — do not silently add exceptions.** `scripts/classifier_lint.py` scans every Supabase-touching `catch { ... }` block for `AppLogger.error` / `AppLogger.critical` without a `NetworkErrorClassifier` call and warns via `.github/workflows/classifier-lint.yml` (PR annotations, warn-only) + `.githooks/pre-commit` (local, warn-only; `STRICT_CLASSIFIER=1 git commit` to fail locally). To suppress a legitimate exception (e.g. bootstrap code that runs before `SupabaseManager.shared.isAuthenticated` is meaningful), add the exact comment `// classifier_lint:allow` inside the catch block with a one-line rationale. The lint flips from `--warn` to `--strict` (blocks merge) once the existing backlog — tracked in `BUG_INTEL_BACKLOG.md` — is cleared.
25h. **`admin-cms` bug-intel UI reads structural fields.** The CMS list pills (`error_class`, `REGRESSED`, `unclassified`) and the detail panel's "Root cause" section read from the columns added in migration 20260516. When touching `admin-cms/src/app/bug-intelligence/page.tsx`, keep the `Fingerprint` type in sync with those columns — the markdown export (`formatExportAsMarkdown`) relies on them to surface the "Classifier bypass" flag and the "REGRESSED" alert.

### Bug-intel report de-duplication + noise-filter sync (Phase 10 — 2026-04-24)
25i-bugintel. **Client denylist in `CrashReportingService.reportError` MUST mirror server-side `bug_intel_noise_filter` tier=hard rows.** The server filter runs inside `compute_daily_bug_rollup()` and strips matching `dev_session_logs` / `crash_reports` before they fingerprint. The client denylist (top of `reportError`, `Fit33/CrashReportingService.swift`) short-circuits BEFORE a `crash_reports` row gets written — which keeps realtime dashboards clean and avoids wasting the per-fingerprint quota (`Config.maxReportsPerFingerprint`) on noise. Current paired entries: `[WATCHDOG]` / `[TAB FREEZE]` / `"UI is unresponsive"` (all from `Fit33/AppPerformanceSystem.swift` instrumentation), `502 Bad Gateway` / `503 Service Unavailable` / `504 gateway` (Cloudflare flaps), `P0001 "Not authenticated"` (SECURITY DEFINER RPC transients). When you add a new row to `bug_intel_noise_filter` with `tier='hard'`, add the matching literal to `reportError` in the same commit or the filter only works from the next 5-minute rollup.
25j-bugintel. **Markdown export de-dupes by `structural_fingerprint` (Phase 10 — `admin-cms/src/app/bug-intelligence/page.tsx::formatExportAsMarkdown`).** Claude writes one `bug_reports` row per triaged sample, so a single `structural_fingerprint` like `2b8eafe6` accumulates 6+ reports with variant titles ("Main Thread Watchdog Freezes" / "Main Thread Frozen During App Initialization" / "UI Unresponsive"). The export now groups bundles by `structural_fingerprint` (fallback: raw `fingerprint`, last-resort: `orphan:<report.id>` to never silently drop data), picks the canonical bundle by `(severity, confidence, occurrence_count, created_at)` tuple, and surfaces the collapsed variant titles inline as `**Also triaged as** (N variants): "…"` so reviewers keep visibility into labeling drift. The TL;DR header gains `Collapsed: <N> duplicate triage rows merged` whenever dedupe happened, and the "brandNew / regressed / stillPending" split reads from the deduped list so a single root cause regressing doesn't show up N times. If future triage systems start emitting `structural_fingerprint = NULL`, the export falls back to raw `fingerprint` so the dedupe still works — never change the key-selection fallback order without also updating `ExplorationOrdering` in `supabase/20260516_bug_intel_structural_fingerprint.sql`.
25k-bugintel. **`auto_resolved_reason` is the only way to tell "silent fix" apart from "noise-filtered" apart from "legacy-build drain".** Migration `20260517_bug_intel_noise_filter_expand.sql` adds the column. `compute_daily_bug_rollup()` sets it when it auto-resolves; `bug_intelligence_reports.review_notes` gets a paired "Auto-merged: ..." trail. Never just flip `status = 'resolved'` without setting a reason — the export UI uses the reason to decide whether to show the resolution in the "Improvement Tracker" (silent_fix = yes, noise_filter_expanded = no because it's a taxonomy change not a fix).
25l-bugintel. **Undeployed migrations that fix bug-intel clusters are tracked in MIGRATION_INDEX §"Deployment Priority Queue".** When a cluster in a bug report traces back to "fix exists but not deployed" — don't duplicate the fix in a new migration, add the SQL file to the priority queue at the top of `supabase/MIGRATION_INDEX.md` with cluster IDs + fingerprints. The current blockers are `20260511_health_rls_audit.sql` (HealthKit RLS 42501 cluster), `20260513_drop_post_workout_activity_overloads.sql` (PGRST203 cluster `d4ca061f`), `20260514_performance_metrics.sql` (unlocks p50/p95 dashboards). This convention keeps the next agent from "re-fixing" what's already written but un-deployed.

### Exercise poster stills (cells)
25i. **`ExercisePosterRingIcon` cache reads MUST be synchronous on appear; generation MUST NOT poll on `MainActor`.** The cell calls `ExercisePosterSmartCrop.shared.cachedCrop(for:)` (disk+memory, <5ms) and shows the result or fallback immediately. Cache-miss paths use `requestBake` / `requestGenerationAndBake`, which run on serial utility-QoS queues, gate speculative video generation on `NetworkMonitor.shared.shouldAvoidBackgroundTraffic` (invariant #11), and post `.exercisePosterSmartCropReady` when done. Cells listen via `.onReceive` — never via `Task { @MainActor in … Task.sleep … }` polling, which retains one main-actor Task per visible cell and was the cause of the 2026-04-23 Exercise tab scroll slowdown. Smart-crop results persist as ~12KB JPEGs in `Caches/exercise_smart_crops/`, so subsequent launches skip Vision entirely.

### Auth session recovery (Sprint 2026-04-24 — 1.38 (54))
25k. **`SupabaseManager.checkAuthOnly()` MUST use a cached-then-refresh pattern, not `await client.auth.session`.** The Supabase Auth SDK's `session` async getter internally calls `refreshSession()` whenever the access token is expired or within 30s of expiry — that's a network round trip. On a slow / congested connection this observed 5824ms in 1.38 (53) session logs, blocking first-frame interactivity. Fast path: (1) `client.auth.currentSession` (nonisolated, sync) — if present AND `!isExpired`, set `isAuthenticated = true` immediately, no network. (2) If expired, race `refreshSession()` against a 1.5s timeout (`withTimeout` helper in `SupabaseManager.swift`); on timeout, still set auth optimistically from the cached session and retry refresh in a background `Task.detached`. (3) Only when `currentSession == nil` do we `await client.auth.session` — that path is fast on any network because there's nothing to refresh. PostgREST auto-401s on stale tokens and the SDK re-refreshes, so losing ~1s of true-token freshness is acceptable for kill-the-6s-blocker.

### Private challenge card unread dot
25j. **Unread-message indicators on private-challenge cards MUST be derived, not fetched.** `PrivateChallengeService.hasUnreadChat(for:)` compares the existing `PrivateChallenge.lastChatAt` column (already selected by `get_my_private_challenges`) against a per-challenge "last read" `Date` dict persisted in `UserDefaults` under `private_challenge_chat_last_read_v1`. There is NO new DB query, NO new realtime subscription, and NO extra RLS round-trip — the existing `chatInserts` postgres-change handler inside `subscribeToRealtimeUpdates` already refetches `myChallenges` on every message, which publishes a new `lastChatAt` and invalidates the card body. `markChatAsRead(challengeId:)` is called from `PrivateChallengeDetailView.task` on appear AND on every inbound realtime insert while the chat is visible, so the dot clears the moment the user sees a message. The dot itself (`UnreadPulsingDot`) uses a single `withAnimation(.easeOut.repeatForever)` on scale+opacity, gated by `reduceMotion || isLowPowerModeEnabled` (invariant #13). Animation cost is bounded at ≤3 concurrent instances (widget shows `challenges.prefix(3)`) and SwiftUI auto-pauses off-screen animations when scrolled out of view.

### Cross-references
26. **Exercise Library never renders a loading placeholder** — see `PRODUCT_ENGINEER_AGENT.md` invariant #22. The fix is always in the data layer (bundle-JSON pre-warm), not in a view skeleton branch.

---

### Memory pressure thresholds (`PerformanceOptimizations.swift`)
25l. **Warning threshold = 500MB (not 550MB).** Sprint 2026-04-24 lowered it after 1.38 (53) session logs showed steady 256MB → 527MB climb across 6 tab switches without tripping warning. Clearing warm caches (video engines + dedup) at 500MB is ~10ms and gives headroom before a spike crosses critical. Periodic poll also 30s → 15s — each `task_info` is a single syscall (~100µs) and 30s was too coarse given ~45MB/tab-switch growth rate. Do NOT raise this back without justifying it against a fresh session-log memory curve.

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
