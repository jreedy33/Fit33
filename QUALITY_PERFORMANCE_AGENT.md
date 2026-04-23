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
13. **Decorative animations gate on BOTH `isLowPowerMode` AND `accessibilityReduceMotion`.** Canonical helper: `AnimatedOrbBackground.shouldDisableMotion`. Never ship a decorative animation without both checks.
14. **Orbs are single-fire, not `.repeatForever`.** Drift to end over 3-5s and stop. Continuous rendering was regressing FPS on all tabs.

### HealthKit
15. **HealthKit error classification.** Errors whose `localizedDescription.lowercased()` contains `"protected health data"`, `"no data available"`, or `"authorization not determined"` are EXPECTED (device locked / no samples / not-yet-granted). Log at `.debug`, never `.error`. Wording changes across iOS versions — use `.contains` matching.
16. **All HK fetch methods check `isAuthorized` before executing queries.** Query callbacks log via `AppLogger`, never silently return nil. iOS can revoke at any time.

### Bulk work on main thread
17. **Sorting/filtering 1000+ items MUST run off main thread.** Workout generator, swap graph, filter cache all iterate 5000+ exercises — never block main. Use `Task.detached` or background Core Data context.
18. **Suppress per-item debug logging during bulk operations.** Pattern: `WorkoutGeneratorService.suppressPerExerciseLogs`. Logging 1000+ items on main was the #1 cause of generation freezes.
19. **Tab switch handlers are minimal.** Only critical sync state updates (tab selection, button hide). Per-step logs/analytics use the single summary log at the end.

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

### Cross-references
26. **Exercise Library never renders a loading placeholder** — see `PRODUCT_ENGINEER_AGENT.md` invariant #22. The fix is always in the data layer (bundle-JSON pre-warm), not in a view skeleton branch.

---

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
