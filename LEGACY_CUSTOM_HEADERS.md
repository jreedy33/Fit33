# Legacy custom headers (revert reference)

This documents the **pre–Liquid Glass toolbar** layout for the five main tabs. Use it if you want to hide the system navigation bar again and put titles + actions back inside scroll views or fixed stacks.

Current floating toolbar APIs live in `DesignSystem.swift` (`floatingTopBarLeading`, `floatingTopBarTrailing`, `floatingTopBarActiveWorkoutTimer`). Home-specific toolbars: `DashboardView+Header.swift` (`DashboardNavToolbar`, `DashboardNavLeadingToolbar`, `DashboardNavTrailingToolbar`).

---

## Tab-by-tab

| Tab | Where it lived | What it was |
|-----|----------------|-------------|
| **Home** | `DashboardView+Header.swift` | **`customHeaderView`** still exists in code: Fit33 logo, optional workout timer, widget `…`, profile ring + `FriendNotificationBadge`. It was the first row inside the Home `ScrollView` `LazyVStack` (before the welcome `headerView`). **Revert:** Remove `DashboardNavToolbar` from `DashboardView.swift` (`.modifier(DashboardNavToolbar(...))`), restore `.navigationBarHidden(true)`, insert `customHeaderView` at the top of the scroll stack with prior padding. |
| **Exercises** | `ExerciseLibraryView.swift` | **`customHeaderView`**: `HStack` — gradient “Exercises” (`.ds_displayLarge` italic, blue→cyan) + `Spacer` + optional timer (monospaced, `.ultraThinMaterial` rounded rect). In the **fixed** `VStack` above `compactFiltersView` (not inside the exercise list `ScrollView`). **Revert:** Remove `.navigationBarTitleDisplayMode`, `.floatingTopBarLeading`, `.floatingTopBarActiveWorkoutTimer()`; restore `.navigationBarHidden(true)`; re-add that header block above filters. Title matches **`ExerciseLibraryToolbarTitle`**; add `Spacer` + timer using `WorkoutManager.shared` or `@EnvironmentObject`. |
| **Workout** | `WorkoutTabView.swift` (`WorkoutHomeView`) | **`customWorkoutHeaderView`**: same pattern, green gradient “Workout” + optional timer. First rows inside the workout `ScrollView` `VStack`. **Revert:** Remove `.navigationBarTitleDisplayMode` and `.floatingTopBar*` from `WorkoutHomeView`; restore **`WorkoutTabView`** `.navigationBarHidden(true)` on `WorkoutHomeView`; re-insert the header above `quickActionsSection`. Reuse **`WorkoutTabToolbarTitle`** + timer UI. |
| **Nutrition** | `SimpleMealPlanView.swift` | **`customNutritionHeaderView`**: teal/mint “Nutrition” + optional timer at the top of the **`LazyVStack`** in the meals `ScrollView`. **Revert:** Remove toolbar floating modifiers; `.navigationBarHidden(true)`; prepend the header. Reuse **`NutritionTabToolbarTitle`** + timer. |
| **Friends** | `FriendsTabView.swift` | **`FriendsHeaderWrapper`**: `FriendsHeaderTitleView` + `Spacer` + **`FriendsHeaderActionsView`** in an `HStack` with `.padding(.horizontal, Spacing.xxs)`. **Option A — scroll:** First child inside the Friends `ScrollView` `VStack` (above stories). **Option B — pinned:** `.safeAreaInset(edge: .top) { FriendsHeaderWrapper(...).padding(.vertical, 8).padding(.horizontal, Spacing.md).glassHeaderBackground() }`. Remove `.navigationBarTitleDisplayMode` and `.floatingTopBarLeading` / `.floatingTopBarTrailing`; use `.navigationBarHidden(true)` if hiding the bar again. |

---

## Shared workout timer (legacy)

When a workout was active, the trailing side used:

```swift
Text(WorkoutManager.shared.formattedDuration)
    .font(.system(size: 14, weight: .medium, design: .monospaced))
    .foregroundColor(.secondary)
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
    .background(
        RoundedRectangle(cornerRadius: CornerRadius.sm)
            .fill(.ultraThinMaterial)
    )
```

---

## Modifiers to remove when reverting

- `floatingTopBarLeading`, `floatingTopBarTrailing`, `floatingTopBarActiveWorkoutTimer`
- Home: `DashboardNavToolbar` (and related toolbar-only code paths)

See also **iOS 26 Liquid Glass Readiness** in `DESIGN_AGENT.md` for the current system-bar behavior.
