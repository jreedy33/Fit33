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

### Performance
| Metric | Status | Target |
|--------|--------|--------|
| `DispatchQueue.main.asyncAfter` | 60+ instances (41 in NewOnboardingView alone) | Replace with `Task.sleep` or proper animation APIs |
| `.ignoresSafeArea()` | 136 instances across 87 files | Audit — keep on backgrounds only |
| Large files | ContentView ~3000+ lines, SupabaseManager ~2500+ lines | Split into focused components |
| `print()` statements | 3000+ | Migrate to `AppLogger` |

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
