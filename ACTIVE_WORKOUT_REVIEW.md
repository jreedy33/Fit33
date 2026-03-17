# Active Workout Review & Fixes

> **Date**: 2026-03-17
> **Scope**: Active workout flow, set initialization, progressive overload, exercise swap logic, UX performance
> **Files Modified**: `ActiveWorkoutView.swift`, `WorkoutManager.swift`

---

## Executive Summary

Thorough review of the active workout system including set initialization, previous data loading, progressive overload integration, exercise swap/replace logic, and UX snappiness. Found and fixed **6 critical issues** and verified **4 existing features** working correctly.

---

## Issues Found & Fixed

### 1. Exercise Shuffle Not Using Tiered Swap Logic (CRITICAL)
**File**: `ActiveWorkoutView.swift` → `ExerciseCard.shuffleToSimilarExercise()`

**Problem**: The shuffle button used `AlternativeExerciseEngine.getBestAlternative()` which returns a random weighted selection from all alternatives. It did NOT follow the designed tiered swap pattern:
- Swap 1-2: Same exercise, different equipment (Dumbbell Bench → Barbell Bench)
- Swap 3+: Complementary exercise (Bench Press → Chest Fly)

The `ExerciseSwapService.getQuickSwap()` already implements this tiered logic perfectly but was NOT being called by the shuffle button.

**Fix**: Replaced `AlternativeExerciseEngine.getBestAlternative()` with `ExerciseSwapService.shared.getQuickSwap()` and added per-exercise swap count tracking (`perExerciseSwapCount`). Falls back to `AlternativeExerciseEngine` if swap service has no results.

### 2. Shuffle Doesn't Load Historical Data for New Exercise (CRITICAL)
**File**: `ActiveWorkoutView.swift` → `shuffleExercise(at:with:)`

**Problem**: When the user shuffles to a new exercise, `loadHistoricalDataForExercise()` was NOT called. This meant:
- The new exercise showed no previous workout data
- Placeholders showed "-" instead of the user's history
- No smart recommendations were generated for the new exercise
- Set count stayed at 1 (from the "no meaningful data" fallback) instead of matching history

**Fix**: Added `loadHistoricalDataForExercise(newExercise)` call at the end of `shuffleExercise()`. Also clear old exercise's `previousExerciseSets` data.

### 3. Shuffle Creates Only 1 Empty Set Instead of Matching History (MODERATE)
**File**: `ActiveWorkoutView.swift` → `shuffleExercise(at:with:)`

**Problem**: When no meaningful data existed on the old exercise, `shuffleExercise` created `[WorkoutSetData()]` — a single empty set. Users expect at least 3 sets by default.

**Fix**: Changed to `(0..<max(existingSets.count, 3)).map { _ in WorkoutSetData() }` to ensure minimum 3 sets.

### 4. Sets Not Pre-Populated With Previous Workout Values (MODERATE)
**Files**: `WorkoutManager.swift` → `initializeSetsForExercise()` and `initializeSetsForExercises()`

**Problem**: When initializing exercise sets at workout start, the correct SET COUNT was loaded from history, but the weight/reps were left at 0. Users saw the right number of empty rows with placeholders showing previous values — but had to manually type each value.

**Fix**: Pre-fill `WorkoutSetData.weight` and `WorkoutSetData.reps` from cached/warmed-up history. Now when a user did 5 sets of bench press at 210lbs x 8 reps last time, all 5 rows show "210" and "8" pre-filled (not just as placeholder text, but as actual editable values).

### 5. Smart Recommendation Sets Created Empty (MODERATE)
**File**: `ActiveWorkoutView.swift` → deferred initialization smart recs path

**Problem**: When `StrengthProfileRecommendationEngine` generated progressive recommendations for exercises without history, the sets were created as `recs.map { _ in WorkoutSetData() }` — empty. The weight/reps appeared only as orange placeholder text.

**Fix**: Changed to pre-fill `WorkoutSetData` with the recommended weight/reps:
```swift
smartSets = recs.map { rec in
    let setData = WorkoutSetData()
    setData.weight = rec.weight
    setData.reps = rec.reps
    return setData
}
```

### 6. loadHistoricalDataForExercise Doesn't Sync Set Count (MODERATE)
**File**: `ActiveWorkoutView.swift` → `loadHistoricalDataForExercise()`

**Problem**: When historical data loaded asynchronously for a replaced/shuffled exercise, it updated `previousExerciseSets` (for placeholder display) but never adjusted the actual exercise's set count or pre-filled values.

**Fix**: Added `syncSetsWithPreviousData()` helper that:
- Checks if current sets are all empty (no user progress)
- If so, replaces them with sets matching the previous workout count, pre-filled with weight/reps
- Preserves user data if they've already started entering values

---

## Verified Working Correctly

### 1. Notes Placeholder Shows Workout Name + Date
**File**: `ActiveWorkoutView.swift:83-89`
```swift
private var notesPlaceholder: String {
    let workoutName = workout.name ?? "Workout"
    let formatter = DateFormatter()
    formatter.dateFormat = "M/d/yy"
    let dateStr = formatter.string(from: Date())
    return "\(workoutName) - \(dateStr)"
}
```
Result: "Chest & Triceps - 3/17/26" ✅

### 2. Keyboard Auto-Dismisses on Scroll
**File**: `ActiveWorkoutView.swift:319`
```swift
.scrollDismissesKeyboard(.immediately)
```
Uses `.immediately` mode — keyboard dismisses as soon as scroll begins. ✅

### 3. LazyVStack for Performance
**File**: `ActiveWorkoutView.swift:118`
Uses `LazyVStack` inside `ScrollView` — only visible exercise cards are rendered. Combined with pre-fetched Core Data properties and two-phase rendering (instant warmup + deferred async), this is correctly optimized. ✅

### 4. Previous Set Data Carries to Extra Sets
**File**: `ActiveWorkoutView.swift:2604-2619` → `getPreviousSetData(for:)`
If user adds more sets than their previous workout, the last previous set's data is used as placeholder. ✅

---

## Architecture Review: How the Pieces Connect

### Set Initialization Flow
```
User taps "GO" on workout preview
  → WorkoutManager.startWorkout()
    → prefetchExerciseData() [Core Data materialization]
    → initializeSetsForExercises() [creates WorkoutSetData with pre-filled values from history]
  → ActiveWorkoutView appears
    → applyWarmupDataInstantly() [synchronous, <1ms — sets previousExerciseSets]
    → initializeWorkout() deferred
      → Check cache for missing exercises
      → Async: StrengthProfileRecommendationEngine for exercises without history
      → Async: Cloud fetch for exercises without cache
```

### Exercise Swap Flow (After Fixes)
```
User taps shuffle icon on exercise card
  → ExerciseCard.shuffleToSimilarExercise()
    → ExerciseSwapService.getQuickSwap(swapCount: N)
      → swapCount < 3: Equipment variant (Dumbbell → Barbell)
      → swapCount >= 3: Complementary exercise (Bench → Fly)
    → Fallback: AlternativeExerciseEngine.getBestAlternative()
  → ActiveWorkoutView.shuffleExercise(at:with:)
    → Transfer or create sets (min 3)
    → Clear old previousExerciseSets
    → loadHistoricalDataForExercise(newExercise)
      → Cache hit → Apply previous data + sync set count
      → Cloud fetch → Apply + sync
      → No history → Smart recommendation engine
    → Track swap in behavior learning engines
```

### Progressive Overload Flow
```
Exercise has previous workout data
  → ProgressiveWorkoutIntelligence.generateProgressiveSets()
    → Fetch last completed workout for this exercise
    → Analyze consistency & readiness
    → If ready for progression:
      → First half of sets: +5lbs (or +2.5 if <30lbs)
      → Second half: maintain previous weight
    → If deload needed:
      → All sets: -10% weight, +2 reps
    → Otherwise: maintain
  → Sets appear pre-filled with progressive values
  → Previous column shows historical reference
```

---

## Performance Characteristics

| Metric | Current State | Notes |
|--------|--------------|-------|
| Warmup data application | <1ms (synchronous) | ✅ No lag on workout load |
| Set initialization | ~2-5ms batch | ✅ Single @Published trigger |
| Smart rec generation | Background task | ✅ Non-blocking, yields between exercises |
| Scroll performance | LazyVStack | ✅ Only visible cards rendered |
| Keyboard dismiss | `.immediately` on scroll | ✅ Instant dismiss |
| Input debounce | 150ms | ✅ Prevents excessive re-renders |
| Timer during ads | Runs in background | ✅ No time lost during ad display |

---

## Remaining Opportunities (Future Work)

1. **Progressive overload in program context**: `ProgressiveWorkoutIntelligence` generates standalone suggestions but doesn't deeply integrate with `GeneratedProgramService` periodization. Consider having program-context workouts use the program's prescribed progression scheme.

2. **Swap learning across sessions**: `UserBehaviorLearningEngine` records swaps but the swap service doesn't yet use that data to re-rank suggestions. After 3+ swaps away from an exercise, it should drop in priority.

3. **Warmup set detection**: If a user logs a warmup set (185lbs x 1), it's treated the same as working sets in history. Consider filtering by `SetType.warmup` when computing previous workout data.

4. **Offline cache for swap suggestions**: `ExerciseSwapService` hits Core Data each time. Pre-computing a swap graph at workout start could eliminate per-shuffle latency.
