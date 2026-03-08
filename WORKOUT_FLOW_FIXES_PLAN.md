# Workout Flow UI Fixes & Improvements Plan

> **Date:** March 8, 2026
> **Scope:** Build Custom Workout, Active Workout, Replace Exercise flows
> **Status:** Ready for agent implementation

---

## Agent Assignment Overview

| Agent | Role in This Plan |
|-------|-------------------|
| **Product Engineer** | Primary owner — implements all UI changes, refactors components, wires up replace flow |
| **Design System** | Enforces token usage in all new/changed code (spacing, typography, corner radii, colors) |
| **Design Agent** | Consulted for any ambiguous visual decisions (card styles, button specs) |
| **Quality & Performance** | Validates replace exercise logic, tests edge cases, checks memory/performance |
| **Fitness Expert** | No changes needed — exercise data/logic is unaffected |
| **Data & Backend** | No changes needed — `WorkoutManager.replaceExercise()` logic is sound |

---

## Issue 1: Build Custom Workout UI Does Not Match Exercise Library

### Synopsis
The `CustomWorkoutBuilderView` and `ExerciseLibraryView` both display exercise cards and filters but use completely different styling, card components, icon sizes, filter behaviors, and corner radii. Users see two visually different UIs for what is conceptually the same content.

### Why It's an Issue
- **User confusion:** Two screens showing the same exercises look and behave differently
- **Inconsistent filter behavior:** Build Workout uses single-select dropdowns (`selectedCategory = "All"`) while Exercise Library uses multi-select Sets (`selectedCategories: Set<String>`)
- **Visual mismatch:** Icon sizes (36x36 vs 40x40), card corner radii (25pt vs 16pt), card styling (custom multi-layer shadows vs `.sleekCardSubtle()`), and color treatment (solid circles vs vibrant gradients) all differ
- **Missing tappable filter chips:** Build Workout filter chips don't match Library's interactive chip behavior

### Detailed Discrepancies

| Element | Build Workout (`CustomWorkoutBuilderView`) | Exercise Library (`ExerciseLibraryView`) | Target |
|---------|---------------------------------------------|------------------------------------------|--------|
| Icon size | 36x36 solid color circles | 40x40 vibrant gradient circles | Match Library (40x40 gradient) |
| Card style | Custom 3-layer shadow + gradient background | `.sleekCardSubtle(cornerRadius: 16)` | Match Library (`.sleekCardSubtle()`) |
| Corner radius | 25pt custom `RoundedRectangle` | 16pt via `.sleekCardSubtle()` | Match Library (16pt) |
| Filter type | Single-select strings (`selectedCategory = "All"`) | Multi-select Sets (`selectedCategories: Set<String>`) | Match Library (multi-select) |
| Filter chips | `CompactFilterChip` with single-select highlight | `CompactFilterChip` with multi-select + tappable toggle | Match Library (tappable multi-select) |
| Favorite indicator | None | Yellow star badge | Add to Build Workout cards |
| Metadata layout | Name + category + equipment | Name + category + equipment + star | Match Library |

### Recommendation

Unify the exercise card component. Ideally extract a single shared `ExerciseCardRow` component used by both views, with a `selectable` mode parameter for the checkbox behavior in Build Workout.

### How It Improves UX
- Consistent visual language — users recognize exercise cards instantly regardless of context
- Multi-select filters give users more power to narrow down exercises
- Tappable filter chips are more intuitive on mobile than dropdown menus

### Recommended Steps in Code

**Owner: Product Engineer Agent** | **Reviewer: Design System Agent**

1. **Create a shared `ExerciseCardRow` component** (new file or in `SharedComponents`)
   - Extract the card layout from `ExerciseLibraryView.CompactExerciseRowContent` (lines 1391-1645)
   - Add a `showCheckbox: Bool` parameter for Build Workout selection mode
   - Use 40x40 gradient circle icons (match Library's `categoryGradient`)
   - Use `.sleekCardSubtle(cornerRadius: 16)` for card background
   - Include optional favorite star indicator

2. **Replace `CustomWorkoutExerciseRowWithNav`** (lines 1966-2152 of `CustomWorkoutBuilderView.swift`)
   - Swap to the new shared `ExerciseCardRow` component
   - Preserve the checkbox/selection behavior (28x28 circle with checkmark)
   - Keep the info button → full-screen detail navigation
   - Keep the selection animation (scale + blue border)

3. **Migrate filters to multi-select** in `CustomWorkoutBuilderView`
   - Change `@State private var selectedCategory = "All"` → `@State private var selectedCategories: Set<String> = []`
   - Change `@State private var selectedEquipment = "All"` → `@State private var selectedEquipmentItems: Set<String> = []`
   - Change `@State private var selectedMuscleGroup = "All"` → `@State private var selectedMuscleGroups: Set<String> = []`
   - Update `cachedFilteredExercises` computation to use Set-based filtering (match Library logic)
   - Update `CompactFilterChip` usage to toggle items in/out of Sets (tappable toggle behavior)

4. **Unify filter chip styling**
   - Ensure `CompactFilterChip` in Build Workout uses same selected/unselected gradient treatment as Library
   - Tapping a chip toggles it in/out of the selected set (not a dropdown replacement)

5. **Design System enforcement** — all new/changed code must use:
   - `Spacing.*` tokens (not hardcoded padding values)
   - `CornerRadius.*` tokens (not hardcoded `16` or `25`)
   - `.ds_*` font tokens (not `.font(.system(size:))`)
   - Semantic color tokens from `AdaptiveColors`

---

## Issue 2: Custom Back (`<`) and Add (`+`) Buttons Are Not Native iOS

### Synopsis
The Build Custom Workout header (lines 889-956 of `CustomWorkoutBuilderView.swift`) uses custom "liquid glass" circular buttons for back (`chevron.left`) and add (`plus`). These are 44x44 circles with `.ultraThinMaterial` fill, blue-purple gradient icons, and white stroke overlays. This is inconsistent with standard iOS navigation patterns.

### Why It's an Issue
- **Platform inconsistency:** iOS users expect the standard back chevron in the navigation bar (left-aligned, no circle background, system blue tint)
- **Accessibility:** Custom buttons may not respond to Dynamic Type or VoiceOver as well as standard `toolbar` items
- **Visual weight:** The liquid glass circles draw excessive attention to navigation chrome instead of content
- **Inconsistency with other screens:** Other views in the app use standard `.toolbar { ToolbarItem(...) }` patterns

### Recommendation

Replace the custom header buttons with standard SwiftUI `.toolbar` items inside a `NavigationStack`. Use `ToolbarItem(placement: .navigationBarLeading)` for back and `ToolbarItem(placement: .navigationBarTrailing)` for the add button.

### How It Improves UX
- Familiar iOS navigation pattern — users know exactly where back/add buttons are
- Automatic support for Dynamic Type, VoiceOver, and system-level back gestures
- Reduces visual clutter in the header area
- Consistent with the rest of the app's toolbar usage (e.g., `CreateExerciseView` at line 1626)

### Recommended Steps in Code

**Owner: Product Engineer Agent** | **Reviewer: Design System Agent**

1. **Wrap the view body in a `NavigationStack`** (if not already)
   - Use `.navigationTitle(mode.title)` for the dynamic title
   - Use `.navigationBarTitleDisplayMode(.inline)` or `.large` based on Design Agent preference

2. **Replace the custom header HStack** (lines 887-973) with `.toolbar`:
   ```swift
   .toolbar {
       ToolbarItem(placement: .navigationBarLeading) {
           Button(action: { dismiss() }) {
               Image(systemName: "chevron.left")
           }
       }
       ToolbarItem(placement: .navigationBarTrailing) {
           Button(action: { showingAddExercise = true }) {
               Image(systemName: "plus")
           }
       }
   }
   ```

3. **Remove the custom `headerView` computed property** (lines 885-974)
   - Delete the entire `GeometryReader`-based header
   - The title, back button, and add button are now handled by the navigation bar

4. **Preserve safe area handling**
   - The current header uses `geometry.safeAreaInsets.top + 4` — the native toolbar handles this automatically
   - Remove `.navigationBarHidden(true)` (line 857) so the toolbar appears

5. **Test the edge swipe back gesture** — native `NavigationStack` provides this for free

---

## Issue 3: Replace Exercise Sheet Is Not a Replica of Build Workout

### Synopsis
When a user taps `... > Replace Exercise` on an exercise card in `ActiveWorkoutView`, a `.sheet` opens presenting `CustomWorkoutBuilderView` in `.replace` mode (lines 2162-2174 of `ActiveWorkoutView.swift`). While the correct view is being reused, there are functional and presentation concerns.

### Why It's an Issue
- **Sheet presentation lacks polish:** The sheet opens `CustomWorkoutBuilderView` but the custom header with liquid glass buttons looks awkward inside a sheet (the back button is redundant — sheets have a drag-to-dismiss gesture)
- **No dismiss button in sheet context:** When presented as a sheet, users need an explicit "Cancel" or "X" button since the `chevron.left` back button is confusing in a modal context
- **Filter state not reset:** If the user previously used Build Workout with filters applied, those filter states may persist (depending on `@State` lifecycle)
- **Replace callback needs verification:** The `onReplaceExercise(newExercise)` callback updates `ActiveWorkoutView`'s local `exercises` array, but the view may not re-render correctly if the exercise at the replaced index doesn't trigger a proper SwiftUI identity change
- **Historical data loading race condition:** After replacing, `loadHistoricalDataForExercise` runs async — if the user interacts with the new exercise before data loads, they see empty previous sets
- **Sets data transfer:** `WorkoutManager.replaceExercise` copies existing sets data to the new exercise (lines 1104-1108), which may not make sense (e.g., replacing bench press with squats shouldn't carry over bench press weights)

### Recommendation

1. Adapt `CustomWorkoutBuilderView` to detect when it's presented as a sheet (`.replace` or `.addToWorkout` mode) and show a proper sheet header with "Cancel" / "X" dismiss button instead of the back chevron.
2. Verify the replace flow end-to-end: exercise swap, UI update, historical data load, and sets data behavior.
3. Ensure filters reset to defaults when the view appears in replace mode.

### How It Improves UX
- Clean modal presentation with proper dismiss affordance
- Reliable exercise replacement — user sees the swap happen immediately
- Fresh filter state every time the replace sheet opens
- No confusing inherited weight/rep data from the old exercise

### Recommended Steps in Code

**Owner: Product Engineer Agent** | **Reviewer: Quality & Performance Agent**

1. **Add sheet-aware header logic** in `CustomWorkoutBuilderView`:
   ```swift
   // In the toolbar/header section:
   if mode.isSingleSelect {
       // Show "Cancel" or X button for sheet dismiss
       ToolbarItem(placement: .navigationBarLeading) {
           Button("Cancel") { dismiss() }
       }
   } else {
       // Show standard back button for navigation push
       ToolbarItem(placement: .navigationBarLeading) {
           Button(action: { dismiss() }) {
               Image(systemName: "chevron.left")
           }
       }
   }
   ```

2. **Reset filters on appear** for replace/add modes:
   ```swift
   .onAppear {
       if mode.isSingleSelect {
           selectedCategories = []
           selectedEquipmentItems = []
           selectedMuscleGroups = []
           searchText = ""
       }
   }
   ```

3. **Fix sets data transfer logic** in `WorkoutManager.replaceExercise()` (line 1104):
   - When replacing, do NOT copy the old exercise's weight/rep data to the new exercise
   - Instead, initialize fresh default sets for the new exercise
   - Rationale: Replacing bench press (225 lbs) with lateral raises shouldn't pre-fill 225 lbs
   ```swift
   // Replace lines 1104-1112 with:
   // Remove old exercise sets data
   exerciseSetsData.removeValue(forKey: oldExerciseId)
   // Initialize fresh default sets for new exercise
   initializeSetsForExercise(id: newExerciseId)
   ```

4. **Verify UI re-render after replacement**:
   - In `ActiveWorkoutView.ExerciseCard`, the `onReplaceExercise` callback should update the parent's `exercises` array
   - Confirm that `exercises[index] = newExercise` triggers a SwiftUI re-render (it should, since `exercises` is `@State`)
   - Test: Replace exercise A with B → card should immediately show B's name, category, and icon

5. **Add loading state for historical data**:
   - While `loadHistoricalDataForExercise` is running async, show a subtle loading indicator on the "Previous" column
   - Prevents user confusion when previous sets are momentarily empty

6. **Wrap the sheet presentation** with proper environment objects:
   - Current code passes `.environmentObject(WorkoutManager.shared)` and `.environmentObject(UserManager.shared)` — verify `managedObjectContext` is also passed (it should inherit from the parent)

---

## Issue 4: Additional Improvements Identified

### 4A: Duplicate `isExerciseForMuscleGroup()` Logic

**Synopsis:** Both `CustomWorkoutBuilderView` and `ExerciseLibraryView` contain identical ~300-line `isExerciseForMuscleGroup()` methods with hardcoded exercise-to-muscle mappings.

**Why it's an issue:** Duplicated logic means bugs fixed in one place won't be fixed in the other. Any new exercises added need updating in two locations.

**Recommendation:** Move `isExerciseForMuscleGroup()` into `ExerciseFilterService` as a shared static method. Both views call the centralized version.

**Owner:** Product Engineer Agent

**Steps:**
1. Add `static func isExerciseForMuscleGroup(_ exercise: Exercise, muscleGroup: String) -> Bool` to `ExerciseFilterService`
2. Copy the full implementation from `ExerciseLibraryView` (canonical version)
3. Replace both inline implementations with calls to `ExerciseFilterService.isExerciseForMuscleGroup()`
4. Delete the duplicate code from both views

---

### 4B: Active Workout Exercise Card Menu Uses `confirmationDialog` Instead of Context Menu

**Synopsis:** The "..." button on exercise cards in `ActiveWorkoutView` opens a `confirmationDialog` (action sheet) with options: Remove, Replace, Rename, Add Rest Timer. This requires two taps (tap "..." → tap option) and presents as a full-width action sheet.

**Why it's an issue:** Action sheets are typically for destructive confirmations, not feature menus. A `.contextMenu` or custom dropdown would be more appropriate and reduce tap count for non-destructive actions.

**Recommendation:** Keep `confirmationDialog` for now (it works and is familiar), but consider migrating to a `.menu` modifier on the "..." button for a more native feel:
```swift
Menu {
    Button("Replace Exercise") { ... }
    Button("Rename Exercise") { ... }
    Button("Add Rest Timer") { ... }
    Divider()
    Button("Remove Exercise", role: .destructive) { ... }
} label: {
    Image(systemName: "ellipsis")
}
```

**Owner:** Product Engineer Agent

**Steps:**
1. Replace `.confirmationDialog` with `Menu { }` on the ellipsis button
2. Group destructive actions below a `Divider()`
3. Test that all menu actions still trigger their respective sheets/callbacks

---

### 4C: No Visual Feedback After Exercise Replacement

**Synopsis:** After a user replaces an exercise, the sheet dismisses and the new exercise appears — but there's no visual confirmation that the swap happened successfully.

**Why it's an issue:** Users may wonder if the replacement actually worked, especially if the new exercise name is similar to the old one.

**Recommendation:** Add a brief toast/banner or highlight animation on the replaced card.

**Owner:** Product Engineer Agent

**Steps:**
1. After `onReplaceExercise(newExercise)` fires, set the replaced card's `activeExerciseId` to the new exercise
2. Apply a brief green glow or pulse animation (2 seconds) to indicate successful replacement
3. Optionally show a small toast: "Replaced with [Exercise Name]"

---

### 4D: Build Workout "GO" Button Accessibility

**Synopsis:** The floating "GO" button in Build Workout appears when exercises are selected but may not have proper accessibility labels or Dynamic Type support.

**Why it's an issue:** VoiceOver users may not know the button exists or what it does.

**Recommendation:** Add `.accessibilityLabel("Start workout with \(selectedExercises.count) exercises")` and ensure the button scales with Dynamic Type.

**Owner:** Quality & Performance Agent

---

### 4E: Exercise Count Badge in Active Workout Header

**Synopsis:** During an active workout, there's no persistent indicator of how many exercises remain vs completed.

**Why it's an issue:** Users lose context on workout progress, especially in longer sessions.

**Recommendation:** Add a subtle progress indicator (e.g., "3/8 exercises") near the workout timer.

**Owner:** Product Engineer Agent

---

## Implementation Priority Order

| Priority | Issue | Effort | Impact |
|----------|-------|--------|--------|
| **P0** | Issue 1 — Unify card UI between Build Workout and Exercise Library | High | High — core visual consistency |
| **P0** | Issue 3 — Fix Replace Exercise sheet (header, filters, sets data) | Medium | High — broken/confusing UX flow |
| **P1** | Issue 2 — Native iOS buttons on Build Workout | Low | Medium — platform consistency |
| **P1** | Issue 4A — Deduplicate `isExerciseForMuscleGroup` | Low | Medium — code health |
| **P2** | Issue 4B — Menu instead of confirmationDialog | Low | Low — minor UX polish |
| **P2** | Issue 4C — Visual feedback after replacement | Low | Medium — user confidence |
| **P3** | Issue 4D — GO button accessibility | Low | Low — accessibility |
| **P3** | Issue 4E — Exercise progress indicator | Low | Low — nice-to-have |

---

## Testing Checklist (Quality & Performance Agent)

- [ ] Build Workout cards visually match Exercise Library cards (icon size, gradients, corner radius, card background)
- [ ] Filter chips in Build Workout are tappable multi-select (same as Library)
- [ ] Selecting/deselecting filters correctly narrows exercise list
- [ ] Back and Add buttons use native iOS toolbar pattern
- [ ] Edge swipe back gesture works on Build Workout screen
- [ ] Replace Exercise sheet opens with clean filter state (no carried-over filters)
- [ ] Replace Exercise sheet shows "Cancel" button (not back chevron)
- [ ] Selecting a replacement exercise dismisses the sheet
- [ ] Replaced exercise immediately appears in the active workout card
- [ ] Previous exercise's weight/rep data is NOT copied to the replacement
- [ ] Historical data loads for the new exercise (check "Previous" column)
- [ ] Replace flow works when workout has 1 exercise, multiple exercises, and at exercise boundaries (first/last)
- [ ] No memory leaks introduced (check for retained closures in replace callbacks)
- [ ] Dark mode renders correctly for all changed components
- [ ] Light mode renders correctly for all changed components
- [ ] VoiceOver can navigate the replace exercise flow

---

## Files to Modify

| File | Changes |
|------|---------|
| `CustomWorkoutBuilderView.swift` | Replace card component, migrate to multi-select filters, replace custom header with toolbar, add sheet-mode header logic, remove duplicate `isExerciseForMuscleGroup` |
| `ExerciseLibraryView.swift` | Remove inline `isExerciseForMuscleGroup` (move to service), extract shared card component |
| `ActiveWorkoutView.swift` | Verify replace callback, consider Menu over confirmationDialog, add replacement feedback animation |
| `WorkoutManager.swift` | Fix `replaceExercise()` sets data transfer (don't copy old weights) |
| `ExerciseFilterService.swift` | Add shared `isExerciseForMuscleGroup()` method |
| New: `ExerciseCardRow.swift` (optional) | Shared card component used by both views |
