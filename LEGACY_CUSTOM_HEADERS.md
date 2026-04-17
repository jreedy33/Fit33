# Main tab custom headers (reference)

**Current app state:** all five main tabs use this pattern (hidden `NavigationBar`, titles inside content).

Use the sections below if you need to **move to the system navigation bar + floating toolbar titles** (`DesignSystem.swift`: `floatingTopBarLeading`, `floatingTopBarTrailing`, `floatingTopBarActiveWorkoutTimer`) or to restore a tab after a bad edit.

**Removed (was Liquid Glass experiment only):** `DashboardNavToolbar` and related toolbar structs from `DashboardView+Header.swift` — reintroduce via git history if needed.

---

## Tab-by-tab (current layout)

| Tab | File / symbol | Placement |
|-----|----------------|-----------|
| **Home** | `DashboardView+Header.swift` → `customHeaderView` | First row in Home `ScrollView` `LazyVStack`, before notification banner / welcome `headerView`. `DashboardView`: `.navigationBarHidden(true)`. |
| **Exercises** | `ExerciseLibraryView` → `customHeaderView` | Fixed `VStack` above `compactFiltersView` (above exercise `ScrollView`). `.navigationBarHidden(true)`. |
| **Workout** | `WorkoutTabView` → `WorkoutHomeView` → `customWorkoutHeaderView` | Top of workout `ScrollView` `VStack`, above quick actions. `WorkoutTabView`: `.navigationBarHidden(true)` on `WorkoutHomeView`. |
| **Nutrition** | `SimpleMealPlanView` → `customNutritionHeaderView` | Top of `LazyVStack` inside meals `ScrollView`. `.navigationBarHidden(true)`. |
| **Friends** | `FriendsHeaderWrapper` (`FriendsHeaderTitleView` + `FriendsHeaderActionsView`) | First row in Friends `ScrollView` `VStack`, above `FriendsStoriesWrapper`. `.navigationBarHidden(true)`. |

**Optional pinned glass header (Friends only):** wrap `FriendsHeaderWrapper` in `.safeAreaInset(edge: .top) { ... .glassHeaderBackground() }` and remove it from the scroll `VStack` if you want the old inset look.

---

## Shared workout timer (in custom headers)

When a workout is active, Exercises / Workout / Nutrition use:

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

## Switching *to* system toolbar + floating titles

1. Remove the custom header row from each tab’s layout (or keep title-only views and move them into `.toolbar`).
2. Remove `.navigationBarHidden(true)` on that tab’s root.
3. Apply `.navigationBarTitleDisplayMode(.inline)`, `.floatingTopBarLeading { … }`, and (where needed) `.floatingTopBarActiveWorkoutTimer()` — see `DesignSystem.swift`. Home previously used a dedicated toolbar modifier (removed); recover from git if you need the exact Home liquid-glass toolbar again.

See **iOS 26 Liquid Glass Readiness** in `DESIGN_AGENT.md`.
