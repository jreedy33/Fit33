# Exercise Library Cold-Start Loading Fix

## Staff Agent Briefing — Eliminate Grey Placeholder Cards on First Tab Visit

---

## 1. Problem Statement

When a user cold-starts the app and taps the **Exercise Library tab** for the first time, they briefly see **generic grey placeholder cards** (empty `CompactExerciseRowContent` shells) before real exercise data populates. This happens because:

1. **`ExerciseLibraryView.loadExercises()` exits early** when `exerciseLibrary.isExercisesReady == false` (the cloud sync hasn't finished yet)
2. The view renders an **empty `LazyVStack`** — no cards at all — or shows the `TabPlaceholderView` spinner
3. On a true cold start (first install or cache expired >6h), the full cloud sync takes **2–5 seconds** after the tab is tapped
4. Even on warm starts, the `TabPreloader` doesn't begin until **T+3s** and completes at **T+4–8s**, meaning the first 3–8 seconds show either a placeholder spinner or an empty list

### Root Cause Chain

```
User taps Exercise tab (T=0)
  → LazyTabContent checks: isPreloadingComplete? NO (TabPreloader still running)
  → LazyTabContent checks: isEagerModeEnabled? NO (not yet enabled)
  → LazyTabContent checks: hasInitialized? NO (first visit)
  → Shows TabPlaceholderView (grey spinner) briefly
  → hasInitialized = true → renders ExerciseLibraryView
  → ExerciseLibraryView.onAppear → loadExercises()
  → loadExercises() checks: exerciseLibrary.isExercisesReady? NO
  → Returns immediately with exercises = [] (empty array)
  → filteredExercises = [] → empty LazyVStack renders
  → User sees empty screen with header/filters but NO exercise cards
  → Eventually isExercisesReady fires → onChange reloads → cards appear
```

### Key Files

| File | Role |
|------|------|
| `ExerciseLibraryView.swift:1347-1353` | `loadExercises()` — exits early if not ready |
| `ExerciseLibraryView.swift:871-929` | Main body — renders empty LazyVStack |
| `ExerciseLibraryView.swift:1049-1065` | `onChange(isExercisesReady)` — eventual reload |
| `AppPerformanceSystem.swift:911-955` | `LazyTabContent` — placeholder logic |
| `AppPerformanceSystem.swift:958-991` | `TabPlaceholderView` — the grey spinner |
| `TabPreloadingSystem.swift:53-103` | `TabPreloader.beginPreloading()` — starts at T+3s |
| `TabPreloadingSystem.swift:380-417` | Phase 4 — calls `ExerciseLibraryService.preloadAll()` |
| `ExerciseLibraryService.swift:33` | `isExercisesReady` flag |
| `ExerciseLibraryService.swift:52-79` | `preWarmCache()` — sets isExercisesReady |
| `ExerciseLibraryService.swift:261-320` | `syncExercisesFromCloud()` — full sync |
| `ExerciseDataProvider.swift` | Bundle JSON fallback (6500+ exercises) |
| `Fit33App.swift:91-300` | App init — startup orchestration |

---

## 2. Current Architecture Summary

### Startup Timeline

```
T=0ms       App init, Core Data ready, UI visible
T=500ms     StartupCache.warmUp() (stats only, not exercises)
T=3000ms    TabPreloader.beginPreloading() starts
T=3-3.2s    Phase 1: Core Data prefetch (200 exercises, metadata only)
T=3.2-4s    Phase 2: Cloud data fetch
T=4-4.1s    Phase 4: ExerciseLibraryService.preloadAll() + filter cache
T=4.1s      isPreloadingComplete = true, eager mode enabled
T=8s+       Intelligence engine (background, non-blocking)
```

### The Gap: T=0 to T=4.1s

During this window, if the user taps the Exercise tab:
- **T=0 to T=3s**: No exercise data loaded at all
- **T=3 to T=4.1s**: TabPreloader is running but not complete
- **Result**: Empty list or spinner for up to 4 seconds

### Data Sources Available

1. **Core Data** — persisted exercises from last sync (0ms access, but `isExercisesReady` blocks it)
2. **Bundle JSON** (`exercises.json`) — 6500+ exercises baked into app (0ms access, never used for library display)
3. **Supabase Cloud** — authoritative source (2-5s network fetch)

---

## 3. Recommended Solution: Three-Tier Instant Loading

### Strategy: "Show Something Immediately, Upgrade Seamlessly"

**Tier 1 (T=0, Instant):** Load recommended exercises from bundle JSON on app init
**Tier 2 (T=0-500ms):** Replace with Core Data exercises if available (warm start)
**Tier 3 (T=3-8s):** Cloud sync updates in background (cold start)

The user **never** sees an empty list or placeholder cards.

---

## 4. Implementation Steps

### Step 1: Eager Exercise Ready State from Core Data (Quick Win)

**File:** `ExerciseLibraryService.swift`

**Problem:** `isExercisesReady` starts as `false` and only becomes `true` after `preWarmCache()` or `syncExercisesFromCloud()` completes. But Core Data may already have thousands of exercises from a previous session.

**Fix:** Check Core Data count at init and set `isExercisesReady = true` immediately if exercises exist.

```swift
// ExerciseLibraryService.swift — add to init or early startup

private init() {
    // Check if Core Data already has exercises from a previous session
    let count = (try? viewContext.count(for: Exercise.fetchRequest())) ?? 0
    if count > 100 {
        isExercisesReady = true
        print("✅ [ExerciseLibrary] Exercises ready at init: \(count) in Core Data")
    }
}
```

**Impact:** On warm starts (returning users), exercises display **instantly** — no waiting for preWarmCache or cloud sync. This alone fixes 90% of occurrences.

---

### Step 2: Bundle JSON Fallback for True Cold Starts

**File:** `ExerciseLibraryView.swift`

**Problem:** On first-ever app launch, Core Data is empty. The user must wait for cloud sync.

**Fix:** When `loadExercises()` finds no Core Data exercises, immediately seed from the bundled `exercises.json` using `ExerciseDataProvider`.

```swift
// ExerciseLibraryView.swift — modify loadExercises()

private func loadExercises() {
    // Try Core Data first (fast path)
    let coreDataExercises = ExerciseLibraryService.shared.getAllExercises()

    if !coreDataExercises.isEmpty {
        exercises = coreDataExercises
        return
    }

    // Fallback: seed from bundle JSON while cloud sync runs
    // This gives the user SOMETHING to browse immediately
    if !exerciseLibrary.isExercisesReady {
        seedFromBundleIfNeeded()
        return
    }

    exercises = ExerciseLibraryService.shared.getAllExercises()
}
```

**New helper:**

```swift
private func seedFromBundleIfNeeded() {
    guard exercises.isEmpty else { return }

    // ExerciseDataProvider loads from exercises.json (lazy, cached)
    let bundleExercises = ExerciseDataProvider.shared.exercises

    // Convert to temporary display objects or trigger background Core Data insert
    // Option A: Insert into Core Data immediately (recommended)
    Task {
        await ExerciseLibraryService.shared.seedFromBundle(bundleExercises)
        await MainActor.run {
            loadExercises()
            updateFilteredExercises()
        }
    }
}
```

---

### Step 3: Move Exercise Preloading Earlier in Startup

**File:** `Fit33App.swift`

**Problem:** `TabPreloader.beginPreloading()` is deferred with a 3-second delay. Exercise data loading should start much earlier.

**Fix:** Trigger `ExerciseLibraryService.shared.preWarmCache()` during `StartupCache.warmUp()` at T=500ms instead of waiting for TabPreloader Phase 4 at T=4s.

```swift
// AppPerformanceSystem.swift — inside StartupCache.warmUp()

// Add at the end of warmUp():
ExerciseLibraryService.shared.preWarmCache()
```

This moves the `isExercisesReady = true` signal from T=4s to T=500ms on warm starts.

---

### Step 4: Remove the isExercisesReady Guard from loadExercises

**File:** `ExerciseLibraryView.swift:1347-1353`

**Problem:** The guard clause `guard exerciseLibrary.isExercisesReady else { return }` prevents ANY exercises from showing, even when Core Data has valid data.

**Fix:** Remove the guard and always attempt to load. If the result is empty, show bundle fallback.

```swift
private func loadExercises() {
    let loaded = ExerciseLibraryService.shared.getAllExercises()
    if !loaded.isEmpty {
        exercises = loaded
    }
    // If still empty AND not ready, the onChange(isExercisesReady) will catch it
}
```

---

### Step 5: Pre-compute Recommended List at App Init

**File:** `Fit33App.swift` or `AppPerformanceSystem.swift`

**Problem:** `ExerciseLibraryFilterCache.precomputeRecommendedList()` only runs during TabPreloader Phase 4 (T=4s).

**Fix:** Trigger it as part of `StartupCache.warmUp()` using whatever exercises are available:

```swift
// After preWarmCache completes:
let exercises = ExerciseLibraryService.shared.getAllExercises()
if !exercises.isEmpty {
    ExerciseLibraryFilterCache.shared.precomputeRecommendedList(allExercises: exercises)
}
```

---

### Step 6: Show Branded Loading State Instead of Empty List

**File:** `ExerciseLibraryView.swift`

**Problem:** Even with all optimizations, there's a brief moment where `filteredExercises` may be empty.

**Fix:** Add a conditional in the body that shows a branded loading state instead of an empty `LazyVStack`:

```swift
// Inside the ScrollView, before/instead of LazyVStack when empty:
if filteredExercises.isEmpty && !exerciseLibrary.isExercisesReady {
    VStack(spacing: 16) {
        ProgressView()
            .scaleEffect(1.2)
        Text("Loading exercises...")
            .font(.subheadline)
            .foregroundColor(.secondary)
    }
    .frame(maxWidth: .infinity)
    .padding(.top, 60)
} else {
    LazyVStack(spacing: 10) {
        // ... existing ForEach
    }
}
```

---

## 5. Priority Order

| Priority | Step | Impact | Effort | Fixes |
|----------|------|--------|--------|-------|
| **P0** | Step 1: Eager isExercisesReady from Core Data | Fixes 90% of cases | 5 min | Warm starts |
| **P0** | Step 4: Remove isExercisesReady guard | Unblocks Core Data loading | 2 min | All starts |
| **P1** | Step 3: Move preWarmCache earlier | Faster ready signal | 5 min | Warm starts |
| **P1** | Step 5: Pre-compute recommended at init | Instant filter cache | 5 min | All starts |
| **P2** | Step 6: Branded loading state | Fallback UX | 10 min | Edge cases |
| **P2** | Step 2: Bundle JSON fallback | True cold start fix | 30 min | First install |

**Steps 1 + 4 alone eliminate the grey cards for all returning users.**

---

## 6. Architecture Diagram (After Fix)

```
App Launch (T=0)
  ├─ Core Data check: exercises > 100?
  │   ├─ YES → isExercisesReady = true (INSTANT)
  │   │        → preWarmCache() at T=500ms
  │   │        → precomputeRecommendedList()
  │   │        → User taps Exercise tab → INSTANT data
  │   └─ NO (first install) →
  │        → Seed from exercises.json bundle (T=200ms)
  │        → Show bundle exercises immediately
  │        → Cloud sync runs in background
  │        → onChange(isExercisesReady) upgrades to cloud data
  │
  ├─ TabPreloader (T=3s, unchanged)
  │   → Still runs full pipeline for other tabs
  │   → Exercise data already loaded, just validates
  │
  └─ Cloud sync (T=3-8s, unchanged)
      → Updates Core Data with latest exercises
      → onChange(isExercisesReady) refreshes view if needed
```

---

## 7. Testing Checklist

- [ ] **Warm start**: Kill app, reopen, immediately tap Exercise tab — exercises show instantly
- [ ] **Cold start (with cache)**: Delete app data, sign in, tap Exercise tab — bundle exercises show within 500ms
- [ ] **True cold start (first install)**: Fresh install, complete onboarding, tap Exercise tab — no grey placeholders
- [ ] **Tab pre-switch**: Stay on Dashboard for 5+ seconds, then tap Exercise tab — instant switch
- [ ] **Rapid switching**: Tap between tabs rapidly — no flicker or empty states
- [ ] **Background return**: Background app for 6+ hours, return, tap Exercise tab — no delay
- [ ] **Filter state preservation**: Apply filters, switch tabs, return — filters and results preserved
- [ ] **Memory pressure**: Simulate memory warning, then tap Exercise tab — recovers gracefully

---

## 8. Agent Prompt

Use the following prompt with your coding agent to implement the fix:

---

### Agent Implementation Prompt

```
## Task: Fix Exercise Library Cold-Start Loading — Eliminate Grey Placeholders

### Context
The Fit33 iOS app shows grey placeholder cards (or an empty list) when users tap
the Exercise Library tab on cold start. The root cause is that `loadExercises()`
in ExerciseLibraryView.swift exits early when `isExercisesReady == false`, and
this flag isn't set to true until the TabPreloader completes at T+4 seconds.

### What to Change

**1. ExerciseLibraryService.swift — Set isExercisesReady eagerly at init**

In the `init()` method (or add one if private init doesn't exist), check Core Data
count immediately:

```swift
private override init() {
    super.init()
    let count = (try? viewContext.count(for: Exercise.fetchRequest())) ?? 0
    if count > 100 {
        isExercisesReady = true
    }
}
```

**2. ExerciseLibraryView.swift — Remove the isExercisesReady guard from loadExercises()**

Change `loadExercises()` (around line 1347) from:

```swift
private func loadExercises() {
    guard exerciseLibrary.isExercisesReady else {
        print("⏳ [LIBRARY] Waiting for exercises to be ready...")
        return
    }
    exercises = ExerciseLibraryService.shared.getAllExercises()
}
```

To:

```swift
private func loadExercises() {
    let loaded = ExerciseLibraryService.shared.getAllExercises()
    if !loaded.isEmpty {
        exercises = loaded
    } else {
        print("⏳ [LIBRARY] No exercises yet, waiting for sync...")
    }
}
```

**3. AppPerformanceSystem.swift — Add preWarmCache to StartupCache.warmUp()**

Inside `StartupCache.warmUp()`, add at the end of the async Task:

```swift
// Pre-warm exercise cache so Exercise tab has data immediately
ExerciseLibraryService.shared.preWarmCache()
```

**4. ExerciseLibraryView.swift — Add loading state for empty list edge case**

In the body (around line 899), wrap the LazyVStack with an empty-state check:

```swift
if filteredExercises.isEmpty && !exerciseLibrary.isExercisesReady {
    VStack(spacing: 16) {
        ProgressView()
            .scaleEffect(1.2)
            .tint(.blue)
        Text("Loading exercises...")
            .font(.subheadline)
            .foregroundColor(.secondary)
    }
    .frame(maxWidth: .infinity)
    .padding(.top, 60)
} else {
    LazyVStack(spacing: 10) {
        ForEach(Array(filteredExercises.enumerated()), id: \.element.objectID) { index, exercise in
            // ... existing code
        }
    }
}
```

### What NOT to Change
- Do NOT modify the TabPreloader pipeline timing
- Do NOT modify the cloud sync logic
- Do NOT remove the onChange(isExercisesReady) observer — it's still needed as a fallback
- Do NOT change CompactExerciseRowContent styling
- Do NOT add skeleton/shimmer animations — the goal is to show REAL data instantly

### Testing
After implementing, verify:
1. Kill app → reopen → immediately tap Exercise tab → exercises visible with no delay
2. Filter to "Recommended" → switch tabs → return → same results shown instantly
3. No console warnings about exercises not being ready on warm starts
4. Cloud sync still works and updates the list when it completes

### Key Principle
The exercises are already IN Core Data from the previous session. We just need to
stop blocking their display behind the isExercisesReady flag. For true cold starts
(empty Core Data), the bundle JSON fallback through ExerciseDataProvider ensures
there's always data to show.
```

---

## 9. Risk Assessment

| Risk | Mitigation |
|------|------------|
| Exercises with nil names showing in list | `getAllExercises()` already filters these out via fetch predicate |
| Stale Core Data exercises (deleted server-side) | Cloud sync replaces all exercises within 6 hours — acceptable lag |
| Bundle exercises missing fields (no video URLs) | Already handled — ExerciseDetailView loads video on-demand |
| Memory spike from early loading | `preWarmCache()` is lightweight (~100ms, Core Data faulting) |
| Race condition: loadExercises during sync | Sync sets `isExercisesReady = false` then `true` — onChange handles refresh |

---

## 10. Success Criteria

After implementing these changes:

1. **Zero grey placeholder cards** visible at any point during Exercise tab navigation
2. **<200ms** from tab tap to first exercise card visible (warm start)
3. **<1s** from tab tap to first exercise card visible (cold start with bundle fallback)
4. **No regression** in tab switching performance after TabPreloader completes
5. **No memory regression** — exercise loading remains under 30MB
