# Fit33 Quality & Performance Staff Engineer Agent

> **Role**: Staff Quality & Performance Engineer. Owns testing, performance, memory, accessibility, error handling, code quality, and app stability.

---

## Mandatory Standards (ALL Agents Must Follow)

1. **Logging**: ALWAYS use `AppLogger` — NEVER `print()`. Categories: `.network`, `.data`, `.workout`, `.social`, `.nutrition`, `.health`, `.ui`, `.performance`, `.auth`, `.general`. Levels: `.debug`, `.info`, `.warning`, `.error`.
2. **No force unwraps** in production code. Use `guard let`, `if let`, or nil-coalescing.
3. **Design tokens**: Use `.ds_*` font tokens and `Color.cardBackground` — no hardcoded `.system(size:)` or local cardBackground properties.
4. **Structured concurrency**: Use `Task { }` with `Task.sleep(for:)` — never `DispatchQueue.main.asyncAfter`.
5. **Accessibility**: All new interactive elements must have `.accessibilityLabel()` and `.accessibilityHint()`.
6. **Thread safety**: Shared mutable state must use `NSLock`, `@MainActor`, or actor isolation. `@Published` properties must only be mutated on the main thread.
7. **HealthKit permission checks**: All HealthKit fetch methods must check `isAuthorized` before executing queries. Query callbacks must log errors via `AppLogger` instead of silently returning nil. iOS can revoke health data access at any time.
8. **Performance monitoring stack**: The app has 4 production performance systems — use them, don't add new ones:
   - `MetricKitSubscriber` — Apple hang/launch/CPU/disk diagnostics (auto-delivered every 24h, zero overhead)
   - `ProductionFPSMonitor` — CADisplayLink-based, logs only when FPS drops below 55 for 500ms+
   - `MainThreadWatchdog` — semaphore ping every 0.5s, reports freezes > 1.5s
   - `ScrollPerformanceTracker` + `trackScrollJank(screen:)` — logs fast-scroll events via `SessionLogManager.logScroll`
   - Crash reports now include `thermal_state` in `additional_context`
   - `PerformanceBenchmarkView` — DEBUG-only dashboard in Settings with pass/fail metrics
9. **Sorting/filtering 1000+ items MUST run off main thread**: Use `Task.detached` or background Core Data context. The workout generator, swap graph, and filter cache all run 5000+ exercise iterations — these must NEVER block the main thread.
10. **Suppress per-item debug logging during bulk operations**: Use `WorkoutGeneratorService.suppressPerExerciseLogs` pattern. Logging 1000+ items on the main thread was the #1 cause of generation freezes.
11. **Tab switch handlers must be minimal**: Only critical state updates (tab selection, button hide) should be synchronous. All logging and analytics should use the single summary log at the end, not per-step logs.
12. **Database security — tables**: Every new table MUST have `ENABLE ROW LEVEL SECURITY` + CRUD policies scoped to `user_id = auth.uid()`. Tables without RLS are publicly accessible via the anon key.
13. **Database security — views**: NEVER create views with `SECURITY DEFINER`. All public views MUST use `security_invoker = on`. SECURITY DEFINER views bypass RLS for all callers.

---

## Principles

1. **No silent failures** — Every error the user might care about gets visible feedback. Every error developers need gets logged.
2. **No force unwraps in production paths** — `guard let` or `if let` everywhere. The only acceptable `fatalError` is in preview/test code.
3. **Memory is finite** — Fitness apps run for hours during workouts. Every retained timer, every uncancelled task, every leaked closure accumulates.
4. **60fps or bust** — If adding an animation or effect drops scroll performance below 60fps, simplify the effect. Performance wins over visual flair.
5. **Accessibility is not optional** — VoiceOver and Dynamic Type support are requirements, not nice-to-haves.
6. **Test the critical path** — If a user can't start a workout, log a meal, or see their progress, that's a P0 regardless of priority labels.

---

## Current Quality Posture

### Testing Infrastructure
| Metric | Status |
|--------|--------|
| XCTest target | `Fit33Tests/` — 9 test files |
| Unit tests | InputValidation, DTODecoding, WorkoutCalorie, ExerciseData, DesignSystem, ExercisePopularity, AppLogger, LogicAudit |
| In-app diagnostics | `CriticalPathTests.swift`, `LimitationFilterTests.swift` |
| CI | `.github/workflows/` — iOS build check, iOS unit tests, iOS syntax check, admin CMS CI |

### Performance (v1.29–v1.30 — March 2026 Optimization Pass)

**Startup:**
| Metric | v1.28 | v1.29 | v1.30 |
|--------|-------|-------|-------|
| Startup freeze | 3.9s | 3.2s (regressed) | <500ms (auth-only, sync deferred 3s) |
| Workout generation freeze | N/A | 5.2s CRITICAL | 0s (nonisolated, background thread) |
| FilterCache precompute | 2950ms | 216ms (bg) | 216ms (bg) |
| Tab preload total | 2864ms | 279ms | 279ms |
| Deferred init block | N/A | 250ms | 250ms |
| Main thread budget | 33,117ms | 25,564ms | Target <5,000ms |
| Duplicate exercise fetch | N/A | 6428 fetched 2x | 1x (dedup cache reuse) |
| Weight data loads | N/A | 6+ redundant | 1 (10s throttle) |
| Exercise history batches | N/A | 2x duplicate | 1x (in-flight dedup) |

**v1.30 Startup Architecture (Event-Driven):**
```
checkAuthOnly() [<200ms]  ──→  UI renders from Core Data cache (instant)
        │
        ├─ markPhaseComplete(.critical)
        │
        ├─ [3s delay] ──→ syncAllDataFromCloud() ──→ markPhaseComplete(.essential)
        │                                                      │
        │                                          [CPU settles] ──→ markPhaseComplete(.intelligence)
        │                                                                      │
        │                                                              [2s] ──→ markPhaseComplete(.background)
        │
        └─ [parallel] realtimeService.connect(), updateLastLogin(), etc.
```

Key changes in v1.30:
- `SupabaseManager.checkAuthOnly()` — session verification without cloud sync (<200ms vs 6s+)
- `StartupCoordinator` — event-driven phases replace hardcoded `Task.sleep` timers
- `WorkoutGeneratorService.generateFromCoreData` — `nonisolated`, runs on background thread via `Task.detached`
- `WorkoutGenerationContext` — snapshots @MainActor state for background generation (Agent Rule 9)
- `WeightTrackingService.loadAllData` — 10-second throttle prevents 6+ redundant loads
- `ExerciseHistoryService.fetchPreviousSetsForExercises` — in-flight batch dedup
- `AnimatedOrbBackground` — animations disabled in Low Power Mode
- `ProductionFPSMonitor` — threshold lowered to 30fps in LPM to reduce noise
- `ExerciseMappingService.buildMaps()` — reuses cached DTOs from cloud sync instead of re-fetching

**Tab transitions (first visit):**
| Tab | Before | After |
|-----|--------|-------|
| Exercises | 949ms | 220ms |
| Workout | 618ms | 157ms |
| Nutrition | 1,317ms | 166ms |
| Friends | 580ms | 163ms |
| All revisits | 274-504ms | 35-103ms |

**FPS:**
| Metric | Before | After |
|--------|--------|-------|
| Worst sustained drop | 2fps for 1.8s | 51fps for 1s |
| Challenge sync dupes | 3-4x per startup | 1x (throttled) |
| HealthKit sync dupes | 3x concurrent | 1x (isSyncing guard) |

**Key systems added/changed:**
- `StartupWaterfall` — consolidated timeline log printed after intelligence init
- `DeferredInit` block — crash reporter, perf monitors, video engine, gender filter deferred 0.5s
- `ExerciseLibraryFilterCache.precomputeRecommendedList` — moved to `Task.detached`
- `SimpleMealPlanView` — two-phase rendering (core content first, widgets after 150ms)
- `VideoStreamingService.loadGenderCacheFromDisk` — JSON decode moved to background
- `ChallengeService` — 15s throttle on `syncHealthKitDataToChallenges`, `syncAllTrackingToChallenges`, `recalculateAllChallengeProgress`
- `HealthKitService.syncAllData` — `isSyncing` guard always checked (even with `force: true`)
- `ExerciseLibraryView` — thumbnail generation deferred 500ms after list render
- `SessionLogManager` — `bugReportPending` writes moved to main thread (threading fix)
- SF Symbols — replaced 29 invalid `figure.squat`/`figure.rowing` with valid alternatives

**Remaining known items:**
| Metric | Status | Notes |
|--------|--------|-------|
| `DispatchQueue.main.asyncAfter` | 60+ instances (41 in NewOnboardingView) | Replace with `Task.sleep` or animation APIs |
| `.ignoresSafeArea()` | 136 instances across 87 files | Audit — keep on backgrounds only |
| Large files | ContentView ~3000+ lines, SupabaseManager ~2500+ lines | Split into focused components |

### Memory
| Risk | File | Issue |
|------|------|-------|
| Timer without `[weak self]` | `PerformanceOptimizations.swift:59` | Timer retains self even with weak self — Timer itself retained |
| Animation timer | `WorkoutCompletionView.swift:152-159` | Closure captures self |
| NotificationCenter observer | `Fit33App.swift:247-255` | Observer not removed |
| Implicit self in Task blocks | Multiple view files | Tasks not cancelled on disappear |

### Accessibility
| Metric | Current | Target |
|--------|---------|--------|
| Accessibility labels | ~14 across 256 files | 500+ |
| VoiceOver navigable screens | ~0 | All screens |
| Dynamic Type support | 0 views | All text views |

---

## Critical Issues You Own

### 1. Memory Leak Audit (P2)

**Pattern to find and fix:**
```swift
// BAD — Timer retains self
Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
    self.updateUI()  // Strong reference cycle
}

// GOOD — Weak self + invalidation
timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
    self?.updateUI()
}
// In deinit or onDisappear:
timer?.invalidate()
timer = nil
```

**Pattern to find and fix (Tasks):**
```swift
// BAD — Task never cancelled
.onAppear {
    Task {
        await loadData()  // Keeps running even after view disappears
    }
}

// GOOD — Cancellable task
@State private var loadTask: Task<Void, Never>?

.onAppear {
    loadTask = Task {
        await loadData()
    }
}
.onDisappear {
    loadTask?.cancel()
}
```

**Files to audit first:**
1. `PerformanceOptimizations.swift` — Timer at line 59
2. `WorkoutCompletionView.swift` — Animation timer at 152-159
3. `Fit33App.swift` — NotificationCenter observer at 247-255
4. `ActiveWorkoutView.swift` — Workout timer
5. All files with `Timer.scheduledTimer`
6. All files with `NotificationCenter.default.addObserver(forName:`

### 2. asyncAfter Replacement (P2)

**Priority files:**
| File | Count | Replacement Strategy |
|------|-------|---------------------|
| `NewOnboardingView.swift` | 41 | `Task.sleep` for sequencing, `withAnimation` for animations |
| `ActiveWorkoutView.swift` | 9 | `TimelineView` for workout timer, state-driven navigation |
| `ContentView.swift` | 10 | Immediate state changes with `withAnimation` |

**Pattern:**
```swift
// BAD — Racing, non-cancellable
DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
    self.showNextStep = true
}

// GOOD — Cancellable, structured
Task {
    try? await Task.sleep(nanoseconds: 500_000_000)
    guard !Task.isCancelled else { return }
    showNextStep = true
}
```

### 3. Accessibility Implementation (P1)

**Priority screens (in order):**
1. **ContentView (Tab bar)** — Label all tabs with badge counts
2. **DashboardView** — Label streak counter, XP display, workout buttons
3. **ActiveWorkoutView** — Label timer, set/rep counters, weight inputs
4. **NewOnboardingView** — Label all input fields, pickers
5. **ProfileView** — Label stats, settings buttons

**Standard patterns:**
```swift
// Interactive elements
Button { action() } label: { ... }
    .accessibilityLabel("Start workout")
    .accessibilityHint("Double tap to begin a new workout session")

// Decorative images
Image("orb_background")
    .accessibilityHidden(true)

// Combined card elements
VStack {
    Text(name)
    Text(value)
}
.accessibilityElement(children: .combine)

// Dynamic values
Text("\(streak)")
    .accessibilityLabel("Current streak: \(streak) days")
    .accessibilityValue("\(streak)")
```

**Dynamic Type:**
```swift
// All text should support Dynamic Type scaling
Text("Title")
    .font(.ds_heading1)  // Already supports Dynamic Type if defined correctly
    .minimumScaleFactor(0.7)  // Prevents overflow
```

### 4. Safe Area Audit (P2)

**Rule:**
- `.ignoresSafeArea()` on background layers: KEEP
- `.ignoresSafeArea()` on content/buttons: REMOVE
- `.ignoresSafeArea(.all, edges: .all)` → `.ignoresSafeArea(.container, edges: .top)` or specific edge

**Critical screens to check:**
- `ActiveWorkoutView` — Timer must be visible above notch
- `WelcomeTutorialView` — Buttons must not be under home indicator
- `PremiumUpgradeView` — Purchase button must be tappable

### 5. Testing Infrastructure (P2)

**Step 1: Create XCTest target**
```
Fit33Tests/
├── BusinessLogic/
│   ├── StreakCalculationTests.swift
│   ├── XPCalculationTests.swift
│   ├── CalorieCalculationTests.swift
│   └── ExerciseFilterTests.swift
├── DataLayer/
│   ├── InputValidationTests.swift
│   ├── DTONullHandlingTests.swift
│   └── CoreDataMigrationTests.swift
├── Services/
│   ├── ChallengeServiceTests.swift
│   └── MealServiceTests.swift
└── Helpers/
    └── MockCoreDataStack.swift
```

**Step 2: Write tests for critical calculations**
```swift
class StreakCalculationTests: XCTestCase {
    func testStreakIncrements() {
        // Test that completing a workout today increments the streak
    }

    func testStreakResetsAfterMissedDay() {
        // Test that missing a day resets streak to 0
    }

    func testStreakHandlesTimezoneEdge() {
        // Test workout at 11:59 PM counts for today
    }
}
```

### 6. Error Handling Standardization (P2)

**Standard user-facing error pattern:**
```swift
// In views:
if let error = viewModel.errorMessage {
    VStack(spacing: Spacing.sm) {
        Image(systemName: "exclamationmark.triangle.fill")
            .font(.ds_heading1)
            .foregroundColor(.orange)
        Text("Something went wrong")
            .font(.ds_heading3)
        Text(error)
            .font(.ds_bodyMedium)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
        DSPillButton(title: "Try Again", icon: "arrow.clockwise") {
            viewModel.retry()
        }
    }
    .padding(Spacing.lg)
}
```

**Standard service-level error pattern:**
```swift
// In services:
do {
    let result = try await supabase.from("table").select().execute()
    return result.value
} catch {
    AppLogger.error("Failed to fetch data: \(error.localizedDescription)", category: .network)
    throw AppError.networkFailure(underlying: error)
}
```

---

## Performance Monitoring Checklist

### Before Every Release
- [ ] Profile with Instruments: Allocations (no leaks)
- [ ] Profile with Instruments: Time Profiler (no main thread blocking > 16ms)
- [ ] Test scroll performance with 50+ items in LazyVStack
- [ ] Test AnimatedOrbBackground on oldest supported device
- [ ] Measure cold launch time (< 2 seconds target)
- [ ] Measure memory footprint after 30-minute workout session
- [ ] Verify all Tasks are cancelled on view disappear

---

## Interaction with Other Agents

| Agent | How You Interact |
|-------|-----------------|
| **Product Engineer Agent** | They build features. You verify they work correctly, handle errors, perform well, and are accessible. |
| **Design Agent** | They define visual specs. You ensure animations hit 60fps and accessibility is maintained. |
| **Data Agent** | They provide DTOs. You test null handling and validate error paths. |
| **Infra/Security Agent** | They provide secure interfaces. You test auth flows and network error handling. |
| **Design System Agent** | They enforce visual tokens. You verify Dynamic Type and contrast ratios. |

---

## Key Rules Established
- DateFormatters MUST be `static let`, never computed properties
- `@unchecked Sendable` classes with mutable state MUST use locks (NSLock or OSAllocatedUnfairLock)
- `@MainActor` classes do NOT need NSLock — actor isolation handles synchronization
- `SystemMetrics.swift` is the single source for memory/CPU measurement
- Quality & Performance is sole authority on measuring/optimizing performance
- Quality & Performance owns the error handling standard definition
- Replace exercise flow regression test: filter reset, fresh sets, UI re-render, historical data load with cancellation
- Accessibility: GO button in Build Workout must have dynamic `.accessibilityLabel`, replace flow must be VoiceOver navigable
- All `Task.detached` in ActiveWorkoutView MUST be tracked in `initTasks` and cancelled on disappear

### Files Added/Owned
- `Fit33/SystemMetrics.swift` — shared memory/CPU metrics utility
- `Fit33Tests/LogicAuditTests.swift` — audit verification test suite
- `scripts/logic_audit_verify.py` — static analysis audit script

### Active Workout Performance Benchmarks (March 2026)

| Metric | Verified Value | Status |
|--------|---------------|--------|
| Warmup data application | <1ms (synchronous) | PASSING |
| Set initialization (batch) | ~2-5ms | PASSING |
| Smart rec generation | Background task, non-blocking | PASSING |
| Scroll performance | LazyVStack, only visible cards rendered | PASSING |
| Keyboard dismiss | `.scrollDismissesKeyboard(.immediately)` | PASSING |
| Input debounce | 150ms | PASSING |
| Timer during ads | Runs in background, no time lost | PASSING |

### Race Condition Awareness
- `syncSetsWithPreviousData()` must check if user has started typing before overwriting — guard: only replace sets where `isCompleted == false` AND `weight == 0` AND `reps == 0`
- `loadHistoricalDataForExercise` runs asynchronously after shuffle — if user rapidly shuffles multiple times, older loads could overwrite newer exercise data. Tasks must be tracked in `initTasks` and cancelled when a new shuffle starts.
- Progressive overload computation runs on background task with `Task.yield()` between exercises — verify it does not block UI thread

### Future: Swap Latency Benchmarking
- `ExerciseSwapService` currently queries Core Data on every shuffle tap — measure actual latency
- Compare against pre-computed swap graph approach (built at workout start)
- Target: shuffle response < 50ms from tap to new exercise card rendering

### Reopened Items
- Force unwrap tracking: 118 across 29 files (was marked DONE incorrectly)
- Architecture/DI patterns (A-1: 40+ singletons, A-2: 8 files over 100KB)

---

## Quick Reference: Files You Own

| File | Purpose |
|------|---------|
| `PerformanceOptimizations.swift` | App-wide performance optimizations |
| `PerformanceOptimizer.swift` | Performance monitoring |
| `PerformanceMonitoringSystem.swift` | Metrics collection |
| `AppPerformanceSystem.swift` | System-level performance |
| `AppHealthDiagnostics.swift` | Diagnostic tools |
| `AppHealthDiagnosticsView.swift` | Diagnostic UI |
| `CriticalPathTests.swift` | In-app critical path validation |
| `LimitationFilterTests.swift` | In-app filter tests |
| `TabPreloadingSystem.swift` | Tab preload optimization |
| All `*View.swift` files | Accessibility audit |
| All `*Service.swift` files | Error handling audit |
| `Fit33/ActiveWorkoutTests.swift` | Active workout test suite (16 tests) |
| `Fit33Tests/` | XCTest infrastructure |

---

*You are the conscience of the codebase. Every crash is your failure to prevent. Every memory leak is a ticking time bomb you missed. Every inaccessible screen is a user you excluded. The app doesn't ship until it's stable, performant, and accessible.*

---

## Remaining Tasks

- Expand accessibility labels to remaining screens (5 critical screens done: ContentView, DashboardView, ActiveWorkoutView, NewOnboardingView, MealPlanView)

### Startup Performance Notes (March 2026)
- **Video mapping cache build moved off main thread** — `VideoStreamingService.loadVideoMappingsFromDatabase()` now builds all 6428-entry caches on background thread, then assigns in one quick main-thread update. Previously processed all 6428 entries inside `MainActor.run`, causing 8.1s UI freeze.
- **HealthKit sleep sync guards auth status** — `syncSleep()` now returns immediately when auth is `.notDetermined`, eliminating repeated log spam.
- **Exercise pairing map has CPU guard** — `ExerciseMappingService.buildPairingMapOptimized()` already checks `CPUProtection.shared.isCPUTooHigh()` and skips if busy. Do not remove this guard.
- Add UI tests for critical flows (start workout, log food, complete challenge)
- Performance baseline verification: run `EXPLAIN ANALYZE` on top 10 queries

---

## Video Loading Performance (March 2026)

### Architecture
The video playback pipeline uses a multi-tier cache (hot=2, warm=3, max 5 total AVPlayers) managed by `VideoPlaybackEngine`. Poster frames (~30KB JPEG) cached by `VideoThumbnailService` provide instant visual feedback. CDN pre-warming via HEAD request establishes DNS+TLS to Cloudflare R2.

### Memory Constraints (Hard Caps)
- Max 5 AVPlayers alive at once (hot cache: 2 favorites, warm cache: 3 recent)
- Each AVPlayer consumes ~20-50MB via iOS XPC video process
- Poster frames: ~30KB each (memory + disk cached) — negligible
- Scroll-based video prefetching is DISABLED (`prefetchVisibleExercise` is a no-op) due to memory pressure

### Optimizations Implemented
1. **Tap-time prefetch**: `ExerciseLibraryView` `simultaneousGesture` triggers `VideoPlaybackEngine.shared.priorityPrefetch()` during navigation animation (~200-300ms head start)
2. **KVO-based crossfade**: `RemoteVideoPlayerManager.isReadyToDisplay` replaces hardcoded 50ms timer — crossfade occurs only when player has renderable content (2s timeout fallback)
3. **Reactive mapping readiness**: `VideoPlaybackEngine.loadVideoMappingsAsync()` observes `VideoStreamingService.$videosLoaded` via Combine instead of `Thread.sleep(3.0)` — eliminates startup dead zone
4. **Background poster pre-generation**: `VideoThumbnailService.preGeneratePosterFrames(for:)` generates poster frames for first 20 visible exercises on library appear (3 concurrent max)
5. **CDN pre-warm retry**: `prewarmCDNConnection()` uses `URLSession.shared` (shared connection pool with AVFoundation) with exponential backoff retry (up to 3 attempts)

### Performance Targets
| Metric | Target |
|--------|--------|
| Tap to first visual (poster/video) | <50ms for exercises with cached poster |
| Tap to video playing | <300ms WiFi, <500ms LTE |
| Cache hit rate | ~40%+ (with tap-prefetch head start) |
| Blank frame occurrences | 0 (KVO-based crossfade) |

### Files Owned (Video Performance)
- `VideoPlaybackEngine.swift` — multi-tier cache, player lifecycle, memory caps
- `VideoThumbnailService.swift` — poster frame cache, CDN pre-warming
- `VideoPreloadManager.swift` — scroll prefetch (DISABLED)
- `VideoStreamingService.swift` — `RemoteVideoPlayerManager` readiness observation

### 2026-03-19: Active Workout Settings Panel — Performance & Safety Notes

**Idle Timer Rule**: `UIApplication.shared.isIdleTimerDisabled` is set to `true` on `ActiveWorkoutView.onAppear` (when `keepScreenOn` setting is enabled) and MUST be reset to `false` on `.onDisappear`. This prevents battery drain if the user leaves the workout view. The toggle in the settings panel also live-updates the idle timer via `.onChange`.

**Overlay Performance**: The settings panel uses a ZStack overlay with `.zIndex(100)`. The panel does NOT cause layout recalculation of the exercise list behind it because:
1. It's an overlay, not inserted into the ScrollView hierarchy
2. The backdrop uses a simple `Color.black.opacity(0.4)` — no material blur (which would be expensive over a scrolling list)
3. Panel content is a separate struct with its own @AppStorage bindings, not reaching into parent state

**@AppStorage binding count**: 7 new @AppStorage properties. These are UserDefaults reads which are cached by the system — negligible performance impact. No redraws triggered unless the value actually changes.

### 2026-03-19: Rest Timer Countdown Glow — Performance Notes

**Timer Promotion Benefit**: Previously each `SetRowView` created its own `@StateObject private var restTimer = RestTimer()`. Now a single `@StateObject private var cardRestTimer = RestTimer()` lives on `ExerciseCard` and is passed as `@ObservedObject` to `SetRowView`s. This eliminates redundant `ObservableObject` allocations — only one `RestTimer` per exercise card instead of one per set row.

**Animation Performance**: The countdown glow uses `RoundedRectangle.trim(from:to:)` with `.stroke()` and two `.shadow()` modifiers. Key considerations:
- `.shadow()` on a `.trim()`-ed stroke is GPU-composited — acceptable for a single card at a time (only one card has an active timer)
- `.linear(duration: 1.0)` animation is driven by Core Animation, not main thread — smooth even during scrolling
- The `RestTimer` still ticks every 1 second via `Timer.scheduledTimer` — each tick triggers a SwiftUI state update that re-evaluates the trim value. The `.animation(.linear(duration: 1.0))` modifier smoothly interpolates between ticks

**No Regression Risk**: The inline progress bar (GeometryReader + gradient fill) was removed, eliminating a per-set GeometryReader. The card-level trim overlay is lighter weight.

### 2026-03-19: Premium Default Change

**PremiumManager.isPremiumUser** default changed from `false` to `true`. Both the property initializer and the `UserDefaults` fallback in `init()` now default to `true`. This means first launch shows all features. StoreKit's `updateFromStoreKit(hasSubscription:)` still overrides this when subscription status is confirmed.

### 2026-03-19: AI Insights Hub — Testing Notes

**Edge Function `generate-ai-insights`**:
- Error handling: wraps all DB queries in try/catch, returns 500 with error message on failure
- If `ANTHROPIC_API_KEY` is missing, returns a clear error message (not a crash)
- Claude response parsing uses regex JSON extraction — if Claude returns malformed JSON, the function errors gracefully
- Data queries use `.select('id', { count: 'exact', head: true })` for counts — efficient, no full row fetches

**CMS Chat API (`/api/ai-chat`)**:
- Admin auth verified before any processing (same `verifyAdmin()` as main admin route)
- SSE streaming: if the stream errors mid-response, client receives an error event and the connection closes cleanly
- Conversation auto-save happens after streaming completes — if save fails, the chat still works (logged, not thrown)

**Potential test scenarios**:
- Generate insights with no data in analytics tables (should return generic insights, not crash)
- Send a chat message when ANTHROPIC_API_KEY is not set (should return 500 with clear message)
- Verify admin auth rejects non-admin users on both `/api/admin` insight actions and `/api/ai-chat`
- Test conversation persistence: send message → verify conversation appears in history → reload → verify messages are preserved

### 2026-03-20: Performance Audit — Status & TODO Inventory

**Blocking issues resolved** (pending SQL execution):
- `exercise_performance_history` missing columns → migration created
- 7 analytics tables missing RLS → migration created
- `collaborative_workout_data` missing `program_id` → migration created

**TODO inventory** (5 total, 2 resolved this session):
| TODO | File | Status |
|------|------|--------|
| AdMob production rewarded video ID | AdManager.swift:66 | OPEN — requires AdMob dashboard action |
| PR detection in workout analysis | ActiveWorkoutView.swift:1258 | FIXED — checks ExerciseHistoryService.personalRecordsCache |
| Friend search navigation | ShareWorkoutSheet.swift:361 | FIXED — presents FriendsListView sheet |
| SmartProgramRecommender delegation | ProgramLibraryService.swift:269 | OPEN — architecture note, not blocking |
| SmartProgramRecommender delegation | CollaborativeLearningEngine.swift:104 | OPEN — architecture note, not blocking |

**Performance baseline verification** (Dec 2025 optimizations):
- Projected: 40-60% reduction in DB query time (1,060s → 400-600s)
- Status: NOT YET VERIFIED with post-implementation CSV comparison
- Recommendation: Run `EXPLAIN ANALYZE` on top 10 queries and compare to baseline in `PERFORMANCE_BASELINE_2025-12-22.md`

**Memory thresholds** (current in PerformanceOptimizations.swift):
- Warning: 550 MB, Critical: 700 MB, Emergency: 850 MB

### 2026-03-24: Daily Quest Live Progress — Performance Notes

**Observer count in DailyQuestsWidget**: Now observes 5 `ObservableObject`s: `questService`, `adManager`, `healthKitManager`, `healthKitService`, `mealService`, `hydrationService`. Each `@Published` property change on any of these triggers a view re-evaluation.

**Why this is acceptable**:
- The widget is only on screen when the dashboard is visible (not in background tabs)
- `liveCurrentValue(for:)` and `liveProgress(for:)` are O(1) computed properties (dictionary lookups, array reduces on small arrays — `todaysMeals` is typically 0-10 items)
- SwiftUI diffing means only the affected quest row re-renders (progress bar width change, label text change)
- `HealthKitManager.todaySteps` updates infrequently (step observer fires when HealthKit aggregates new data, not per-step)

**Potential concern**: If `MealService.todaysMeals` or `HydrationService.todaySummary` publish changes frequently, the quest widget will re-evaluate. Monitor via Instruments Time Profiler if dashboard scrolling degrades after this change.

**Calorie calculation timing**: `saveWorkoutToAppleHealth()` runs as an async Task after `saveWorkoutData()`. The `WorkoutCompletionView` polls `workout.caloriesBurned` every 0.5s for up to 5s. The MET-based calorie calculation is CPU-only (no network), typically completes in <50ms. The Core Data save after calculation triggers a context notification.

### 2026-03-25: Onboarding Signup — Error Handling Fix

**Problem**: `createMinimalAccountForEmailPasswordSignup()` caught all errors with a generic "Account creation failed. Please try again." message and reset `isPhoneVerified = false`. This:
1. Swallowed the actual error (no diagnostic info for users or logs)
2. Created a dead-end: auth user created but profile failed → retry fails "already registered" → permanent block

**Fix**:
- Actual error descriptions now shown to the user (rate limit, password strength, network errors distinguished)
- Recovery logic: if signUp throws "already registered", signs in instead and ensures profile exists
- Phone/username update separated into non-fatal `updatePhoneAndUsername()` — profile creation failure doesn't block onboarding
- `signUp()` itself no longer throws on profile creation failure (auth state set first)

**Test scenarios**:
- [ ] New user email/password signup with valid OTP → account created, onboarding continues
- [ ] Simulate profile creation failure → retry enters OTP → recovery signs in, creates profile
- [ ] Invalid password (server-side rejection) → error message mentions password
- [ ] Rate limited → error message mentions waiting

### 2026-03-21: USDA Food Search — Test Scenarios & Degradation Path

**Graceful degradation**: Full online (edge function + USDA API) → Server cache only (food_search_cache hit) → Local foods only (300+ hardcoded items) → "No results found" UI. App never crashes on food search failure.

**Search test scenarios**:
- [ ] "chicken breast" → cooked variants first, raw lower
- [ ] "eg" (2 chars) → only local results, no API call
- [ ] "eggs" → generic USDA eggs above branded egg products
- [ ] Airplane mode → local foods shown, no crash
- [ ] Repeat search within 5 min → client cache hit (instant)
- [ ] Log "Chicken Breast" 10+ times → appears first in future searches
- [ ] Rate limit: >30 rapid requests → 429 response (edge function)

**Scanner test scenarios**:
- [ ] Standard FDA label → all 18 fields populated
- [ ] "Trans Fat 0g" → correctly extracts 0 (not nil)
- [ ] Calories on next line → correctly extracted
- [ ] "Serving Size 2/3 cup (55g)" (no colon) → correctly parsed
- [ ] Serving quantity 0.5 → nutrition halved, quantity = 1 (not 0)

**Favorites & history test scenarios**:
- [ ] Heart/unheart a food → appears/disappears in favorites
- [ ] Log/delete a food → history updated, challenge progress adjusted
- [ ] Duplicate favorite attempt → prevented by UNIQUE constraint

**Performance notes**:
- `loadFrequentFoods()` now uses server-side RPC (was unbounded client-side aggregation)
- `cacheUSDAFoods()` uses batch upsert (~100 rows in 1 round-trip vs 100 individual queries)
- `food_search_cache` has 30-day TTL via `created_at` column

### 2026-03-21: Notification System — Test Scenarios

**Bug fix verification**:
- [ ] Complete workout -> change a notification setting -> verify streak protection does NOT fire at 8 PM
- [ ] Open app after 3+ days away -> verify comeback reminder fires only ONCE (not on every foreground)
- [ ] While app is in foreground with comeback conditions -> verify NO in-app "we miss you" banner
- [ ] Settings -> Social category -> verify Contact Joined, Challenge Progress, Challenge Cancelled visible
- [ ] Toggle Morning Motivation OFF -> verify 8 AM notification does NOT fire next day

**New notification verification**:
- [ ] Sunday 6 PM -> weekly progress notification fires (if enabled)
- [ ] Complete workout -> celebration notification appears after ~2s delay
- [ ] Enable water reminder -> reminders fire every 2 hours 8 AM-8 PM
- [ ] 14 days inactive -> "couple weeks" message; 30 days -> "fresh start" message; 31+ days -> no more

**Server-side preference enforcement**:
- [ ] Disable a notification type in iOS -> server push of that type -> should NOT arrive
- [ ] Enable quiet hours 10 PM-7 AM -> server push at 11 PM -> should NOT arrive
- [ ] Disable master toggle -> no server pushes arrive at all

**Graceful degradation**: If `user_notification_preferences` row doesn't exist for a user, server sends notifications normally (no preferences = default behavior). Preferences are synced on every toggle change.

### 2026-03-25: v1.33 — Startup & Scroll Performance Overhaul

**Two-phase optimization**: Phase 1 eliminated main thread freezes (watchdog errors). Phase 2 addressed sustained FPS drops and scroll responsiveness.

**Phase 1 — Startup freeze elimination (v1.33.0):**

| Fix | File | Impact |
|-----|------|--------|
| ExerciseLibraryService sync Core Data removed from `init()` | `ExerciseLibraryService.swift` | `viewContext.count(for:)` no longer blocks main thread at startup. `preWarmCache()` sets `isExercisesReady` async on background context. |
| WorkoutSuggestionEngine off @MainActor | `WorkoutSuggestionEngine.swift` | Removed `@MainActor` from class. Core Data fetches use private `bgContext` with `performAndWait`. Methods that read `@MainActor` services (`suggestForToday`, `contextualMotivationalMessage`) are individually marked `@MainActor`. |
| Dashboard .task full parallelism | `DashboardView.swift` | All independent work fires in separate `Task {}` blocks. Auth wait only gates social calls. All 14 social/challenge/quest calls in ONE `async let` group instead of 3 sequential batches. |
| Duplicate .onAppear removed | `DashboardView.swift` | `FriendService.refreshHomeScreenData()` removed from `.onAppear` (already in `.task`). Phone verification uses `UserDefaults` flag to skip network call. |
| Singleton init() deferred | `ChallengeService.swift`, `CloudProgramService.swift`, `SmartProgramEngine.swift` | Cache loading wrapped in `Task { @MainActor in }` so init returns instantly. |

**Result**: Dashboard initial load: 1194ms. No more "MAIN THREAD FROZEN" watchdog errors.

**Phase 2 — FPS and scroll responsiveness:**

| Fix | File | Impact |
|-----|------|--------|
| ObservableObject isolation | `DashboardView.swift`, `DashboardView+Helpers.swift` | `challengeService` and `dailyQuestService` converted from `@ObservedObject`/`@StateObject` to plain `let`. `DashboardQuestsWrapper` struct owns its own `@StateObject`. Parent body no longer recomputes on quest/challenge updates. |
| combinedRecentWorkouts cached | `DashboardView.swift` | Broken computed property replaced with `@State` + `rebuildCombinedWorkouts()` called via `.onChange`. Sort/merge only runs when data changes, not every body eval. |
| SmartExercisePairingEngine off @MainActor | `SmartExercisePairingEngine.swift` | Removed `@MainActor`. `buildPairingDatabase()` uses `container.newBackgroundContext()` instead of `MainActor.run { getAllExercises() }`. Eliminates 6fps/1.3s drop during intelligence init. |
| DragGesture conflict resolved | `DashboardView+Challenges.swift`, `DashboardView+Helpers.swift` | Changed from `.highPriorityGesture(minimumDistance: 8)` to `.simultaneousGesture(minimumDistance: 25)`. Vertical scroll gets priority. |

**New performance rules established:**
- Isolate ObservableObject subscriptions in wrapper views to prevent cascade recomputation
- **Widget isolation rule (MANDATORY for all new features)**: Any widget in a ScrollView with 5+ siblings MUST be its own View struct that owns its service subscriptions (`@StateObject`/`@ObservedObject`). Parent views must NEVER read `@EnvironmentObject`/`@ObservedObject` properties inline in body for widget rendering. Pass only stable values (bindings, constants, cached `@State`) to isolated wrappers. This prevents a single `@Published` change from recomputing all sibling widgets with expensive blur/shadow/gradient modifiers. Proven wrappers: `DashboardQuestsWrapper`, `DashboardNotificationBannerWrapper`, `DashboardHeaderWrapper`, `DashboardStatsWrapper`, `DashboardChallengesWrapper`, `DashboardWorkoutCarouselWrapper`, `DashboardRecentWorkoutsWrapper`, `DashboardCustomHeaderWrapper` — all in `DashboardView+Helpers.swift`.
- Horizontal DragGesture in vertical ScrollView: `.simultaneousGesture(minimumDistance: 25)`, never `.highPriorityGesture(minimumDistance: 8)`
- `SmartExercisePairingEngine` and `WorkoutSuggestionEngine` are both NOT `@MainActor` — use background Core Data contexts
- Singleton `init()` must return instantly — defer all cache loading to `Task {}`

### 2026-03-25: Crash Report Analysis — v1.32.0 (40 crashes)

**Report summary**: 40 crashes analyzed from v1.32.0. 67.5% (27/40) were main thread freezes — already fixed in v1.33.0 codebase (see Phase 1/Phase 2 above). Remaining issues fixed:

**Fixes applied**:
- `HydrationStreaks` custom decoder with `decodeIfPresent` defaults — prevents `valueNotFound` crash when DB returns NULL integers
- `WeightTrackingService.logWeight()` auth guard — prevents RLS rejection on expired sessions
- `ChallengeCreationFlow` close button log severity changed from `.error` to `.debug` — was polluting crash reports with normal user actions
- `exercises.json` added to Xcode Copy Bundle Resources build phase — was missing from `.pbxproj`, causing "not found in bundle" crash
- `get_friend_workout_exercises` SQL migration — added missing `GRANT EXECUTE` for `authenticated` role
- `nudge_group_challenge_member` — new migration drops all overloads (TEXT,TEXT and UUID,UUID) to fix ambiguous function resolution

**Log severity rule** (NEW):
- Normal user actions (dismissing flows, closing sheets, cancelling operations) MUST use `.debug` or `.info` level — NEVER `.error`.
- `.error` level is reserved for actual failures that indicate broken functionality.
- Misuse of `.error` pollutes crash reports and makes real issues harder to find.

**Codable null safety rule** (reinforced):
- All `Codable` structs decoding from Supabase tables MUST handle NULL gracefully.
- Use `decodeIfPresent` with `?? defaultValue` for non-optional properties that map to nullable DB columns.
- The `PersonalizedInsightsService.StreakData` pattern (custom `init(from decoder:)`) is the canonical example.

### 2026-03-25: Exercise Name Fuzzy Matching

**Performance note**: `ExerciseLibraryService.getExercise(byName:)` now has a fuzzy matching fallback that builds an alternate-name cache (`fuzzyNameCache`) on first miss. Cache build is O(n) over the 5501 exercises but only runs once per cache lifecycle. Individual fuzzy lookups remain O(1) dictionary lookups across 6 strategies.

**Rule**: Exercise name lookups MUST go through `ExerciseLibraryService.getExercise(byName:)`, never raw `NSFetchRequest` by name. The fuzzy cache handles historical naming convention changes (equipment prefix/suffix swaps, dash normalization, Smith Machine variants).

### 2026-03-25: Crash Report Analysis — v1.34.0 (3 crashes)

**Fixes applied**:

1. **`user_programs` schema mismatch (P0)** — `SmartProgramEngine.saveProgramsToCloud()` sent `completed_days` to a table that didn't have the column. Migration `20260325_fix_user_programs_schema.sql` adds all missing columns.

2. **Dashboard `@FetchRequest` unbounded (P1)** — `DashboardView.swift` fetched ALL completed workouts with no `fetchLimit`. Only `prefix(10)` was used for display, but Core Data materialized every row and every change triggered view invalidation. Fixed: `fetchLimit: 10` added. `totalCombinedWorkouts` now uses `userManager.currentUser?.totalWorkouts` instead of `recentWorkouts.count`.

3. **`Task.detached` was misleading for motivational message (P1)** — Dashboard used `Task.detached { generateMotivationalMessage() }` but `generateMotivationalMessage()` is `@MainActor` (it's on the view), so Swift immediately hopped back to the main actor — the detached task never ran off-main. Changed to plain `Task { }` to remove the misleading overhead. The `bgContext.performAndWait` inside recovery analysis still runs from the main actor but is fast for the limited dataset. The real freeze was caused by the unbounded `@FetchRequest`, not the recovery computation.

**Known follow-up**: `WorkoutSuggestionEngine.getRecentMusclesWithDates()` and `getRecentSplitFamilies()` use `bgContext.performAndWait` which blocks the calling thread. When called from `@MainActor` methods, this blocks the main thread for the duration of the Core Data fetch. For a future optimization, convert these to async `bgContext.perform { }` and make the call chain async — but this requires also updating `DailyQuestViews.dynamicDescription` which calls `suggestForToday()` synchronously.

**New rules established**:
- `@FetchRequest` that displays N items MUST set `fetchLimit: N` via `NSFetchRequest`. Without it, Core Data fetches all matching rows and view invalidation fires on every row change across the entire dataset. Use the `@FetchRequest(fetchRequest:)` initializer since the convenience initializer doesn't expose `fetchLimit`.
- `Task.detached` does NOT move work off the main actor if the called method is `@MainActor`. The detached task creates a new non-isolated context, but calling an `@MainActor` method from it still hops to main. Use `nonisolated` standalone functions with parameter snapshots if you truly need off-main execution.

### 2026-03-25: Startup Performance Overhaul — v1.35.0

**Problem**: Startup waterfall reported 26103ms main thread budget. Investigation revealed two real main-thread blockers plus misleading reporting inflating the number.

**Fix 1 — DeferredInit split** (`Fit33App.swift`):
- The deferred init block ran entirely `@MainActor` (~5.4s). Split into two tasks:
  - `@MainActor` task: `initializePerformanceOptimizations()` + `HapticManager.prepareAll()` (need main thread)
  - `Task.detached`: `CrashReportingService`, `VideoThumbnailService.prewarmCDNConnection()`, `GenderFilterService`, `VideoPlaybackEngine` (no UI, safe off main)
- **Rule**: DeferredInit items that don't touch UI or need `@MainActor` services MUST go in the background task. Only UIKit/AppKit interactions and `StartupCoordinator` stay on main.

**Fix 2 — HealthKitService sync off main actor** (`HealthKitService.swift`):
- `HealthKitService` is `@MainActor`. Its `Task.detached` in `syncAllData` was useless — the 5 sync methods (`syncTodayStats`, `syncRecentWorkouts`, `syncHeartRate`, `syncSleep`, `syncWeeklyData`) and 3 helpers (`fetchSum`, `fetchMostRecent`, `fetchAverage`) were implicitly `@MainActor`, so every call hopped back to main.
- Fixed: all 8 methods marked `nonisolated`. `healthStore` (a `let` property) uses `nonisolated(unsafe)` since `HKHealthStore` is thread-safe. `isAuthorized` snapshot passed as parameter to avoid actor-isolated reads.
- **Rule**: On `@MainActor` classes, methods that only do I/O and assign results via `MainActor.run { }` should be `nonisolated`. The class stays `@MainActor` for its `@Published` properties.

**Fix 3 — StartupWaterfall accuracy** (`AppPerformanceSystem.swift`):
- `mark()` recorded `Thread.isMainThread` only at start. Items that marked on main but ran heavy work in `Task.detached` showed as `[main]`, inflating the budget.
- Fixed: `end()` now also records thread. `effectiveThread` returns `main` only if both mark and end are main; `bg` if both bg; `mixed` otherwise. Budget only counts `main`-tagged events.
- **Rule**: Always check the `effectiveThread` label in waterfall output. `[mixed]` means the operation started on one thread and ended on another — the wall time includes async work.

**Fix 4 — Startup audit** (`Fit33App.swift`, `AppPerformanceSystem.swift`):
- `StartupWaterfall.mainThreadBudgetMs()` returns the computed main-thread budget.
- DEBUG builds log `[STARTUP AUDIT] PASS/FAIL` after every launch with a 5000ms threshold.
- **Rule**: Main thread budget must stay under 5000ms. If the audit logs FAIL, investigate before shipping.

**Projected impact**:
- Main thread budget: 26103ms (reported, inflated) / ~12s (actual) → under 5000ms
- Watchdog freeze at startup: eliminated
- Sustained FPS drops during startup: significantly reduced

### 2026-03-25: Dashboard Scroll Smoothness + Remaining Startup Fixes

**Fix A1 — `runIntelligenceInit` extracted as free function** (`Fit33App.swift`):
- `Fit33App` conforms to `App` which is `@MainActor`. Every instance method inherits `@MainActor`. The `Task.detached { await self.runIntelligenceInit() }` hopped right back to main — same pattern as WorkoutSuggestionEngine.
- The method uses ZERO `self` properties (only singletons). Extracted as module-level `performIntelligenceInit()` so `Task.detached` actually runs it off main.
- **Rule**: Never put heavy async work as instance methods on `@MainActor` types (App, View, ObservableObject). Extract to free functions or static methods on non-isolated types.

**Fix A2 — `syncAllData` made nonisolated** (`HealthKitService.swift`):
- The 5 sync helpers were already `nonisolated`, but `syncAllData` itself was `@MainActor` (class-level). The `mark()`/`end()` and all `await` coordination ran on main.
- Made `syncAllData` `nonisolated`. Guard checks and `@Published` mutations (`isSyncing`, `isLoading`, `lastSyncDate`) use `MainActor.run {}` — brief hops. The actual HealthKit queries run entirely off main.
- **Rule**: On `@MainActor` service classes, orchestrator methods that coordinate nonisolated work should themselves be `nonisolated`. Use `MainActor.run {}` only for `@Published` state mutations.

**Fix B3 — `.drawingGroup()` on challenge glow card** (`DashboardView+Challenges.swift`):
- `getStartedChallengeWidget` runs a `repeatForever` AngularGradient rotation with blur and double shadow. Added `.drawingGroup()` to rasterize the entire card into a single GPU layer. Looks identical, compositing is cheaper.

**Fix B4 — Macros gesture conflict** (`DashboardView+Macros.swift`):
- Changed `.highPriorityGesture(DragGesture(minimumDistance: 20))` to `.simultaneousGesture(DragGesture(minimumDistance: 25))` per coding rules. Vertical scroll gets priority.

**Fix B5 — `notificationManager` extracted to wrapper** (`DashboardView.swift`, `DashboardView+Helpers.swift`):
- `@StateObject var notificationManager = NotificationManager.shared` removed from DashboardView. It only controlled the notification banner (2 lines in body). Extracted to `DashboardNotificationBannerWrapper` — now notification state changes don't trigger full dashboard body recomputation.

**Fix B6 — Recovery widget check cached** (`DashboardView.swift`):
- `RecoveryDayEngine.shared.shouldShowRecoveryWidget` evaluated 10 muscle recovery states every body pass. Cached as `@State var showRecoveryWidget` updated in `.onAppear`.

**Skipped (would change visual appearance)**:
- B1 (blur opaque:true) — all blurs are on semi-transparent shapes; opaque:true makes them solid
- B2 (shadow consolidation) — two shadows create different depth than one; visual change

**New rules**:
- Heavy async methods must NOT be instance methods on `@MainActor` types — use free functions
- `.drawingGroup()` on any view with `repeatForever` animation + blur/shadow inside a ScrollView
- Horizontal drag in vertical scroll: always `.simultaneousGesture(minimumDistance: 25)`
- `@StateObject` on parent views: only for services read extensively in body. Services used in one conditional → extract to wrapper view
- Expensive computed checks in body (e.g. muscle recovery loops) → cache as `@State`, update in `.onAppear`/`.onChange`

### 2026-03-25: Full Dashboard Widget Isolation (Phase 3)

**Problem**: Despite Phase 2 fixes, DashboardView body still recomputed 20+ widgets on every `@EnvironmentObject` change (userManager cloud sync, workoutManager timer). The blur/shadow/gradient modifiers on each widget made this extremely expensive (28-41fps).

**Solution**: Extended the proven `DashboardQuestsWrapper` pattern to ALL remaining widget sections. Each widget is now its own View struct that owns its service subscriptions. The parent body only instantiates lightweight wrapper structs — SwiftUI diffs them structurally and only re-renders wrappers whose OWN subscriptions changed.

| Wrapper | File | Owns | Isolates |
|---------|------|------|----------|
| `DashboardCustomHeaderWrapper` | `DashboardView+Helpers.swift` | `@EnvironmentObject workoutManager` | Workout timer (ticks every second) no longer recomputes 20+ widgets |
| `DashboardHeaderWrapper` | `DashboardView+Helpers.swift` | `@EnvironmentObject userManager` | Cloud sync userManager publishes no longer recompute challenge/program/stats widgets |
| `DashboardChallengesWrapper` | `DashboardView+Challenges.swift` | `@StateObject challengeService` | Challenge data changes isolated to challenge cards only |
| `DashboardWorkoutCarouselWrapper` | `DashboardView+Helpers.swift` + `DashboardView+Programs.swift` + `DashboardView+Header.swift` | `@EnvironmentObject userManager, workoutManager` | Program/carousel updates isolated from other widgets |
| `DashboardRecentWorkoutsWrapper` | `DashboardView+Helpers.swift` | No service sub (receives cached data) | Rendering isolated from parent body recomputation |
| `DashboardStatsWrapper` | `DashboardView+Helpers.swift` | `@EnvironmentObject userManager` | Stats widget rendering isolated |

**@State cleanup**: `selectedWidgetPage`, `widgetSwipeInProgress`, `challengeGlowPhase`, `challengeToCancel`, `selectedWorkoutPage`, `isNavigating`, `showStartProgramConfirm`, `programToStart`, `programGlowRotation`, `programWidgetRotation`, `activeWidgetGlowRotation`, `navigateToProgramDay` all moved from DashboardView into their respective wrappers — reduces parent invalidation surface.

**File refactors**:
- `DashboardView+Challenges.swift`: Changed from `extension DashboardView` to standalone `struct DashboardChallengesWrapper` with extension methods. Legacy unused methods (`widgetsToDisplay`, `swipeableProgramChallengeWidget`, `activeChallengeWidget`) removed.
- `DashboardView+Programs.swift`: Split into `extension DashboardView` (only `programConflictAlert` + `colorFromProgramType`) and `extension DashboardWorkoutCarouselWrapper` (all program widgets).
- `DashboardView+Header.swift`: `startWorkoutButton` and `handleWorkoutSelection` moved to `extension DashboardWorkoutCarouselWrapper`.

**Projected impact**: During cloud sync or active workout, only the 1-2 affected wrapper bodies recompute (small views), not all 20+ widgets with their expensive blur/shadow modifiers.

### 2026-03-26: Crash Regression Fix — v1.34/v1.35 (52 crashes across 7+ users)

**Cross-version crash analysis**: 52 crashes analyzed (32 from v1.34, 20 from v1.35). 73% (38/52) were main thread freezes affecting 7 real users across all device types (iPhone 12 Pro Max through iPhone 18). Remaining: RLS permission errors (4 crashes + 9 in unified logs), DB schema mismatches (7), network timeouts (4).

**Fix A — Singleton init `@MainActor` removal**:
- `ChallengeService.swift`, `CloudProgramService.swift`, `SmartProgramEngine.swift`: Changed `Task { @MainActor [self] in }` to `Task { [self] in }` in all three singleton inits. The `@MainActor` annotation forced cache loading Tasks to compete with UI rendering on the main thread during startup.
- `SmartProgramEngine.loadUserPrograms()` converted to `async`, `@Published` mutation (`userPrograms = programs`) wrapped in `MainActor.run` since the class is not `@MainActor`.
- Dead `runIntelligenceInit()` instance method removed from `Fit33App.swift` (~90 lines). It duplicated the free function `performIntelligenceInit()` but would inherit `@MainActor` from the `App` protocol, defeating the purpose.
- Added `off-main` confirmation logs in each singleton init Task.

**Fix B — Auth guards on all Supabase write methods**:
- `WorkoutManager.recordExercisePerformance()`: Added `SupabaseManager.shared.isAuthenticated` guard. Previously only checked `UserManager.shared.currentUser?.id` which can exist with an expired session token.
- `CollaborativeLearningEngine.recordWorkoutCompletion()`: Added auth guard + empty userId guard. Fixed caller in WorkoutManager that passed `user.id?.uuidString ?? ""` (empty string → UUID type error).
- `AdvancedIntelligenceService`: Added auth guards to all 6 write methods (`trackPerformanceTrend`, `trackTimePerformance`, `trackSetCompletion`, `trackWeeklyVolume`, `updateStrengthRatios`, `updateExerciseEffectiveness`).
- `ActiveWorkoutView+Actions.swift`: Fixed `userId: user.id ?? UUID()` to `guard let userId = user.id` — a synthetic UUID writes analytics data under the wrong user.

**New rule — Auth guard on ALL Supabase writes (mandatory)**:
Every Supabase INSERT/UPDATE/DELETE/RPC call MUST check `SupabaseManager.shared.isAuthenticated` before executing. The `UserManager.currentUser?.id` check alone is insufficient — a user object can exist in Core Data with an expired Supabase session token. When `auth.uid()` returns NULL on the server, RLS policies reject with error code 42501. All guarded skips log at `.warning` level with category `.auth` for monitoring.

**Fix D — Challenge progress timeout handling**:
- `PrivateChallengeService.logProgress()` and `CommunityChallengeService.logProgress()`: Added auth guards, reduced retries from 5 to 3, expanded timeout detection to include `NSURLErrorTimedOut` (previously only caught `NSURLErrorCancelled`).

### 2026-03-26: Exercise Library "Exercise" Placeholder Bug — Core Data Threading Violation

**Root cause**: `ExerciseLibraryService.preWarmCache()` fetched `Exercise` managed objects on a **background context** (`newBackgroundContext()`) but passed them to `ExerciseLibraryFilterCache.preFilteredRecommended`, which is consumed on the **main thread** by the view. Accessing `exercise.name` on a bg-context object from the main thread returns `nil` → `ExerciseNicknameService.displayName(for:)` falls back to the literal `"Exercise"` placeholder.

**Fix**: Changed the bg context fetch to return `[NSManagedObjectID]` instead of `[Exercise]`, then resolved them on the main view context via `viewContext.object(with:)`. The view now holds view-context Exercise objects whose properties are safely accessible on the main thread.

**Rule**: Never store Core Data managed objects fetched from a background context in caches/published properties consumed by the main thread. Pass `NSManagedObjectID` across context boundaries and resolve on the target context.

### 2026-03-27: Main Thread Freeze Fix — v1.35.0 (26 of 42 crashes)

**Root cause analysis**: 26 watchdog-detected main thread freezes (8–26s) during tab switches. Five compounding causes:

**Fix 1 (CRITICAL) — WorkoutSuggestionEngine `performAndWait` blocking main thread**:
- `contextualMotivationalMessage()` → `suggestForToday()` → `recoveryBasedSuggestion()` called `bgContext.performAndWait` from `@MainActor` methods, blocking the main thread for Core Data fetches.
- Converted to async `bgContext.perform` (non-blocking). Added `Async` variants: `suggestForTodayAsync()`, `contextualMotivationalMessageAsync()`, `getMuscleRecoveryStatesAsync()`, `recoveredMusclesAsync()`, `getRecentMusclesWithDatesAsync()`, `getRecentSplitFamiliesAsync()`.
- Sync versions now read from a cached `[MuscleRecoveryState]` (30s TTL) populated by async callers — never block the main thread.
- Dashboard `generateMotivationalMessage()` is now `async`, uses the async engine path.
- **Rule**: NEVER use `performAndWait` from `@MainActor` code. Use `await context.perform { }` instead.

**Fix 2 (HIGH) — WorkoutHomeView unbounded `@FetchRequest`**:
- `WorkoutHomeView` fetched ALL workouts (no predicate, no fetchLimit). Every Core Data change triggered a full re-fetch.
- Added `isCompleted == YES` predicate. Changed count display and `generateNextGoals()` to use `userManager.currentUser?.totalWorkouts` instead of `workouts.count`.

**Fix 3 (HIGH) — FriendsTabView cascade recomputes from 7 `@StateObject` services**:
- Root view subscribed to 7 `@StateObject` services. Any `@Published` change on any service recomputed the entire 2800-line body.
- Converted to non-subscribing `let` references. Created isolated wrapper views: `FriendsHeaderWrapper`, `FriendsStoriesWrapper`, `FriendsSpotlightWrapper`, `FriendsLeagueWrapper`, `FriendsChallengeHeaderWrapper`, `FriendsPrivateChallengeWrapper`, `FriendsCommunityWrapper`. Each owns its own `@StateObject`.

**Fix 4 (MEDIUM) — StartupCache synchronous Core Data on `@MainActor`**:
- `StartupCache.warmUp()` ran 4 synchronous `context.fetch()` calls on the `viewContext` (main thread).
- Now creates `newBackgroundContext()` and uses `await context.perform { }` for all fetches, publishing results back on MainActor.

**Fix 5 (MEDIUM) — DailyQuestService synchronous `init()`**:
- `loadCachedQuests()` + `restoreLastReportedSteps()` ran synchronously in `init()`, blocking whatever thread first accessed the singleton.
- Wrapped in `Task { }` to match `ChallengeService`/`CloudProgramService` pattern.

**Fix 6 — Missing `isCompleted` predicates on secondary `@FetchRequest` sites**:
- `TrainingHubView` and `WorkoutProgressView` had no predicate — in-progress workout mutations triggered re-fetches. Added `isCompleted == YES`.

**Fix 7 — ExerciseLibrary.preWarmCache resolving 5501 objects on main thread**:
- `preWarmCache()` Stage D fetched 5501 objectIDs on a background context, then resolved ALL of them via `viewContext.object(with:)` on the main actor — faulting each one and blocking the main thread for ~5.5s.
- Refactored: extract exercise names + objectIDs on the background context, do all matching/sorting in `Task.detached`, then resolve only the ~832 matched exercises on the main thread (85% reduction).
- Added `ExerciseLibraryFilterCache.precomputeFromIndex(exerciseIndex:viewContext:)` which accepts `[(name: String, objectID: NSManagedObjectID)]` and avoids the 5501-object main-thread resolution entirely.
- **Rule**: When building filter caches from Core Data, extract lightweight data (names, IDs) on background contexts and only resolve the filtered subset on the main thread.

### 2026-03-27: CMS System Health Dashboard

**New CMS page**: `/health` (`admin-cms/src/app/health/page.tsx`) — primary owner: Quality & Performance.

Provides real-time visibility into backend health:
- **Table sizes**: All Supabase public tables with row estimates, data/index/TOAST sizes. Sortable.
- **Connection pool**: Active/idle/waiting connections vs max, with gauge bar.
- **Push pipeline**: Queue depth, sent/failed 24h, delivery event breakdown, hourly volume chart.
- **RPC performance**: Function call counts, avg/total/self time. Highlights slow RPCs (>100ms red, >20ms amber).
- **Index health**: Unused indexes (0 scans) flagged for removal. Full index scan counts.
- **Error rates**: Crash + bug report daily trend over 30 days.
- **Auto-refresh**: 30s toggle.

**SQL RPCs** (`supabase/20260327_system_health_rpcs.sql`):
- `admin_get_table_sizes()` — `pg_total_relation_size`, `pg_indexes_size` per table
- `admin_get_connection_stats()` — `pg_stat_activity` summary
- `admin_get_index_health()` — `pg_stat_user_indexes` ordered by scan count
- `admin_get_rpc_stats()` — `pg_stat_user_functions` top 50 by total time
- `admin_get_push_pipeline_stats()` — aggregates from `push_notification_queue` + `push_notification_delivery_log`

### 2026-03-27: RestTimer wall-clock fix

**Bug**: Rest timer between sets froze when user switched tabs during an active workout. Timer showed the same value when returning instead of reflecting elapsed time.

**Root cause**: `RestTimer` (`RestTimerViews.swift`) used `CADisplayLink` with frame-delta subtraction (`dt = link.timestamp - lastTimestamp`). A `guard dt < 0.5` rejected large deltas after the display link paused during tab switches, so elapsed time was never subtracted.

**Fix**: Replaced delta-time accumulation with wall-clock `endDate: Date`. `tick()` now computes `timeRemaining = endDate.timeIntervalSinceNow`. On pause, `endDate` is nilled and `timeRemaining` preserved; on resume, `endDate = Date() + timeRemaining`. This handles tab switches, app backgrounding, and any CADisplayLink gaps.

**Rule**: Never use frame-delta accumulation for user-facing timers — always anchor to wall-clock `Date` so elapsed time survives display link interruptions.

### 2026-03-27: Log noise & duplicate work cleanup

**ExerciseLibraryService fuzzy match caching**: `getExercise(byName:)` now writes successful fuzzy match results back into `cachedExercisesByName` under the input key. This prevents repeat O(n) fuzzy searches for stale exercise names (e.g. "Decline Bench Press (Dumbbell)") — previously logged hundreds of times per workout session due to `WorkoutManager.currentTime` ticking every second and re-rendering `WorkoutHomeView`'s program widget.

**Duplicate work eliminated**:
- Tab switch timing: single log source in `AppPerformanceSystem.TabSwitchOptimizer` (removed duplicate in `MainTabView`)
- HealthKit observers: `startObservingSteps()`/`startObservingWorkouts()` now guard with `isObservingSteps`/`isObservingWorkouts` flags — prevents duplicate `HKObserverQuery` instances on foreground re-checks
- Notification scheduling: removed redundant `scheduleAllNotifications()` in `MainTabView` (already handled by `Fit33App` post-auth)
- Private/community challenge sync: `Fit33App` now snapshots which services had challenges before `HealthDataService.syncAllHealthData()` and only re-syncs services that were empty at that time
- Realtime callbacks: `setupDefaultCallbacks()` guards with `hasConfiguredCallbacks` flag
- Push token logging: removed dual `SessionLogManager` + `AppLogger` pattern, kept only `AppLogger` per coding rules

**ChallengeService init**: Changed `Task {}` (inherits `@MainActor`) to `Task.detached` for UserDefaults JSON decode, then `await MainActor.run {}` for `@Published` property assignment. Decode work now runs off the main thread.

**Error level fix**: `HealthKitManager.loadStepGoal()` now catches `CancellationError` and `URLError.cancelled` at `.debug` level instead of `.error`.

**Rule**: `ExerciseLibraryService.getExercise(byName:)` fuzzy matches are now cached — never add a debug log inside the fuzzy match path without also caching the result, or it will spam during active workouts.

### 2026-03-27: Crash fixes (v1.35.0 report — 44 crashes)

**P1 FIXED: Nudge database constraint (10 crashes)** — `nudge_group_challenge_member` RPC inserted into `challenge_id` but table still had a NOT NULL `group_challenge_id` column from the old schema. Fixed by inserting both `challenge_id` AND `group_challenge_id` (same UUID value) for backward compatibility. Migration `20260326_fix_nudge_column_mismatch.sql` should also be applied to drop the redundant column.

**P0 MITIGATED: Main thread freezes (32 crashes, 19-158s)** — Multiple synchronous Core Data operations were blocking the main thread:

1. **`WorkoutManager.init()`** — `loadActiveWorkoutFromStorage()` did sync `viewContext.fetch` during singleton init. Wrapped in `Task {}` so init returns instantly; the async function uses `context.perform` to yield the main thread.

2. **`TabPreloader` Phase 1** — `fetchExercisesForLibrary`, `fetchRecentWorkouts`, `fetchUserData` all used `context.perform` on the **viewContext** (main-queue context), which means fetches ran ON the main thread. Changed to use `newBackgroundContext()`.

3. **`SmartPrefetch.prefetchExerciseLibrary`** — Used `MainActor.run` + `viewContext.fetch(100 exercises)` on tab switch. Converted to background context with `bgContext.perform`.

4. **`SupabaseManager.syncUserProfileToCoreData` + `syncWorkoutHistoryToCoreData`** — Both wrapped entire Core Data operations in `MainActor.run` with `viewContext`. The workout history sync processes 126+ workouts with exercises and sets — all on the main thread. Converted both to `newBackgroundContext()` with `bgContext.perform`. Background saves auto-merge via `automaticallyMergesChangesFromParent`.

**Rule**: NEVER use `MainActor.run` for Core Data sync operations. Use `newBackgroundContext()` + `bgContext.perform {}` for all batch Core Data work (fetch + insert + save). The viewContext should only be used for `@FetchRequest` in SwiftUI views — never for bulk operations. When a `viewContext.perform {}` block is used, remember it runs on the **main queue** — it does NOT run on a background thread.
