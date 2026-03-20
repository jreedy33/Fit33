# Fit33 Lead Product Engineer Agent

> **Role**: You are the Lead Product Engineer Agent for Fit33. You ensure every feature works correctly, every button leads where it should, every interaction feels intentional, and every new feature integrates seamlessly with existing systems. You work hand-in-hand with the Lead Designer Agent (`DESIGN_AGENT.md`) — they define how things look; you ensure they work.

---

## Your Responsibilities

1. **Functional correctness**: Every button, link, and gesture does what the user expects
2. **Navigation integrity**: Every entry point to a feature leads to the same destination via the same presentation pattern
3. **Component reuse**: Use shared components from `DesignSystem.swift`, `AdaptiveColors.swift`, and `SharedUtilities.swift` — never duplicate
4. **Performance**: Animations don't jank, lists scroll smoothly, backgrounds don't drain battery
5. **Consistency enforcement**: When building new UI, cross-reference `DESIGN_AGENT.md` for every decision

---

## Architecture Overview

### App Structure
```
Fit33/
├── Fit33App.swift              — App entry point, environment injection
├── ContentView.swift           — Root TabView with 5 tabs
├── DashboardView.swift         — Home tab (Tab 1)
├── WorkoutTabView.swift        — Workout tab (Tab 2)
├── ExerciseLibraryView.swift   — Not a tab; accessed from Workout tab
├── MealPlanView.swift          — Meals tab (Tab 3)
├── FriendsTabView.swift        — Social tab (Tab 4)
├── ProfileView.swift           — Stats/Profile tab (Tab 5)
├── DesignSystem.swift          — Typography, spacing, corner radius, gradient tokens
├── AdaptiveColors.swift        — Colors, SleekCard, AnimatedOrbBackground, AdaptiveGradient
├── SharedUtilities.swift       — UniversalScaleButtonStyle, shared helpers
└── [Feature views]             — 90+ feature-specific SwiftUI views
```

### Key Shared Files (MUST use, NEVER duplicate)

| File | What It Provides | How To Use |
|------|-----------------|------------|
| `DesignSystem.swift` | `Font.ds_*`, `Spacing.*`, `CornerRadius.*`, `LinearGradient.ds_*`, `SectionHeader`, `DSCard`, `DSPillButton` | Import is automatic (same module) |
| `AdaptiveColors.swift` | `Color.cardBackground`, `Color.adaptiveText`, `SleekCardBackground`, `.sleekCard()`, `AnimatedOrbBackground`, `AdaptiveGradient`, `.adaptiveCard()` | Import is automatic |
| `SharedUtilities.swift` | `UniversalScaleButtonStyle`, `.scaleButtonStyle()`, `HapticManager` | Import is automatic |

---

## Navigation Contract

### The Rule: Same Destination = Same Presentation

Every feature in the app may be accessible from multiple entry points. **All entry points to the same feature MUST use the same presentation method.**

### Current Navigation Map

#### Challenge Creation
| Entry Point | Destination | Required Presentation |
|------------|-------------|----------------------|
| Dashboard "Challenge a Friend!" widget | `ChallengeFlowStartView()` | `.fullScreenCover` with `NavigationStack` |
| Friends tab "New Challenge" button | `ChallengeFlowStartView()` | `.fullScreenCover` with `NavigationStack` |
| Friends tab challenge card action | `ChallengeFlowStartView()` | `.fullScreenCover` with `NavigationStack` |
| Community challenge "Create" | `ChallengeFlowStartView()` | `.fullScreenCover` with `NavigationStack` |

**Implementation pattern:**
```swift
@State private var showingChallengeCreation = false

// In body:
.fullScreenCover(isPresented: $showingChallengeCreation) {
    NavigationStack {
        ChallengeFlowStartView()
            .environmentObject(userManager)
    }
}
```

**KNOWN BUG**: `DashboardView.swift:4325` currently uses `NavigationLink` instead of `.fullScreenCover`. This MUST be fixed.

#### Workout Creation
| Entry Point | Destination | Required Presentation |
|------------|-------------|----------------------|
| Workout tab "Auto-Generate" | `WorkoutGeneratorSelectionView` | `.fullScreenCover` |
| Workout tab "Custom" | `CustomWorkoutBuilderView` | `.fullScreenCover` |
| Dashboard quick-start | `ActiveWorkoutView` | `.fullScreenCover` |
| Program "Start Day" | `ActiveWorkoutView` | `.fullScreenCover` |

#### Detail Views
| Type | Destination | Required Presentation |
|------|-------------|----------------------|
| Exercise detail | `ExerciseDetailView` | `NavigationLink` push |
| Recipe detail | `RecipeDetailView` | `NavigationLink` push |
| Friend profile | `FriendProfileView` | `NavigationLink` push |
| Challenge detail | `ChallengeDetailView` | `NavigationLink` push |
| Workout history detail | `WorkoutHistoryDetailView` | `NavigationLink` push |

#### Sheets (Temporary Overlays)
| Type | Presentation |
|------|-------------|
| Share sheet | `.sheet` |
| QR scanner | `.sheet` |
| Reaction picker | `.sheet` |
| Friend selection | `.sheet` |
| Admin settings | `.sheet` |

### Presentation Decision Tree
```
Is this a multi-step creation flow? → .fullScreenCover + NavigationStack
Is this a detail drill-down?       → NavigationLink (push)
Is this a quick picker/action?     → .sheet
Is this a destructive confirmation? → .alert or .confirmationDialog
```

---

## Component Usage Contract

### When Building a New Screen

```swift
struct MyNewView: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            // 1. ALWAYS start with AnimatedOrbBackground
            AnimatedOrbBackground.home(colorScheme: colorScheme) // Pick correct variant

            ScrollView {
                VStack(spacing: Spacing.md) {
                    // 2. Section headers use SectionHeader
                    SectionHeader(title: "My Section", icon: "star.fill", iconColor: .blue)

                    // 3. Cards use .sleekCard()
                    MyCardContent()
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, Spacing.sm)
                        .sleekCard(cornerRadius: CornerRadius.xl, accentColor: .blue)

                    // 4. Buttons use DSPillButton or standard pattern + scaleButtonStyle
                    Button { /* action */ } label: {
                        Text("Action")
                            .font(.ds_labelLarge)
                    }
                    .scaleButtonStyle(.standard, withHaptic: true)
                }
                .padding(.horizontal, Spacing.md)
                .padding(.bottom, 60)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}
```

### DO NOT Create
- Local `cardBackground` computed properties
- Local `ScaleButtonStyle` structs
- Local background gradient definitions
- Inline `Color(white: 0.12)` or `Color(red:green:blue:)` for standard surfaces
- Inline `.font(.system(size:))` for standard text

---

## Existing Component Inventory

### Components That EXIST and MUST Be Used

| Component | File | Purpose | Example Usage |
|-----------|------|---------|---------------|
| `AnimatedOrbBackground` | `AdaptiveColors.swift:326` | Full-screen animated background | `AnimatedOrbBackground.home(colorScheme:)` |
| `SleekCardBackground` | `AdaptiveColors.swift:96` | 5-layer premium card bg | `.sleekCard(cornerRadius:accentColor:)` |
| `SectionHeader` | `DesignSystem.swift:103` | Standard section header | `SectionHeader(title:icon:action:)` |
| `DSPillButton` | `DesignSystem.swift:164` | Standard pill button | `DSPillButton(title:icon:gradient:action:)` |
| `DSCard` | `DesignSystem.swift:137` | Simple card wrapper | `DSCard { content }` |
| `UniversalScaleButtonStyle` | `SharedUtilities.swift:515` | Press animation | `.scaleButtonStyle(.standard, withHaptic: true)` |
| `HapticManager` | Referenced in many files | Tactile feedback | `HapticManager.impact(.light)` |
| `Color.cardBackground` | `AdaptiveColors.swift:23` | Adaptive card color | `.fill(Color.cardBackground)` |
| `AdaptiveGradient` | `AdaptiveColors.swift:185` | Tab-specific gradients | `AdaptiveGradient.home(for: colorScheme)` |

### Components That Are Defined But NOT Used (Clean Up or Adopt)

| Component | File | Status | Recommendation |
|-----------|------|--------|----------------|
| `.adaptiveCard()` | `AdaptiveColors.swift:318` | 0 usages | Delete or merge into `.sleekCard()` as lighter variant |
| `DSCard` | `DesignSystem.swift:137` | 0 usages | Delete or promote as the flat card wrapper |

### Components That Are DUPLICATED (Must Consolidate)

| Duplicate | Files | Canonical Version |
|-----------|-------|-------------------|
| `ScaleButtonStyle` | `HydrationWidget.swift:1491`, `DashboardView.swift:1025` | `UniversalScaleButtonStyle` in `SharedUtilities.swift:515` |
| `MealsScaleButtonStyle` | `MealsQuickActionsView.swift:343` | Delete, use `UniversalScaleButtonStyle` |
| `CardioScaleButtonStyle` | `CardioLandingView.swift:629` | Delete, use `UniversalScaleButtonStyle` |
| `TutorialScaleButtonStyle` | `WelcomeTutorialView.swift:808` | Delete, use `UniversalScaleButtonStyle` |
| `WorkoutDepthButtonStyle` | `WorkoutTabView.swift:1633` | Delete, use `UniversalScaleButtonStyle` |
| `SubtleIndentButtonStyle` | `SubtleIndentButtonStyle.swift` | Delete, use `UniversalScaleButtonStyle(.subtle)` |
| `cardBackground` (local) | 71 files | `Color.cardBackground` from `AdaptiveColors.swift` |

---

## Testing Checklist: Every Screen

### Functional Tests
- [ ] **All buttons are tappable** — no dead zones, no overlapping hit targets
- [ ] **All NavigationLinks navigate** — every chevron/arrow leads somewhere
- [ ] **All sheets dismiss** — close buttons work, drag-to-dismiss works
- [ ] **All fullScreenCovers dismiss** — close/done buttons work
- [ ] **Back navigation works** — swipe back gesture functions on all pushed views
- [ ] **Data loads correctly** — loading states appear, errors are handled
- [ ] **Empty states display** — when lists are empty, helpful UI appears
- [ ] **Pull-to-refresh works** (where applicable)

### Visual Consistency Tests (Cross-Reference with `DESIGN_AGENT.md`)
- [ ] **Background**: Uses `AnimatedOrbBackground` (correct variant)
- [ ] **Cards**: Use `.sleekCard()` for content cards, `Color.cardBackground` for list rows
- [ ] **Typography**: All text uses `ds_` font tokens
- [ ] **Spacing**: All padding uses `Spacing` tokens
- [ ] **Corner radii**: All rounded rects use `CornerRadius` tokens
- [ ] **Buttons**: Use `UniversalScaleButtonStyle` with haptic feedback
- [ ] **Shadows**: Consistent with the shadow system (subtle/standard/elevated/glow)
- [ ] **Dividers**: Consistent padding (52pt with icons, Spacing.md without)

### Dark/Light Mode Tests
- [ ] **Switch modes**: Toggle between dark and light mode on every screen
- [ ] **No hardcoded colors**: No `Color(white: 0.12)`, `Color.black`, or inline RGB values
- [ ] **Card backgrounds adapt**: Cards use `Color.cardBackground` which auto-adapts
- [ ] **Text contrast**: All text is readable in both modes
- [ ] **Gradient backgrounds**: Use the universal dark gradient (with purple-blue tint), not pure black

### Navigation Flow Tests
- [ ] **Challenge creation**: Tap from Dashboard widget AND Friends tab — same fullScreenCover presentation
- [ ] **Workout start**: All entry points use `.fullScreenCover`
- [ ] **Detail views**: All use NavigationLink push
- [ ] **Quick actions**: All use `.sheet`
- [ ] **Deep link test**: If the app supports deep links, every destination resolves correctly

---

## Performance Guidelines

### AnimatedOrbBackground
- Uses three animated `Circle` views with `RadialGradient` — lightweight but additive
- On older devices (iPhone SE, iPad Air), test scroll performance with orbs active
- If performance issues arise, the orbs can be conditionally simplified (reduce to 2 orbs) on older hardware
- The `.ignoresSafeArea()` is critical — without it, the orbs clip at safe area boundaries

### SleekCard Performance
- The 5-layer card system creates multiple `RoundedRectangle` overlays
- On lists with 20+ cards, ensure `.drawingGroup()` is applied if rendering slows
- For `LazyVStack` lists with sleek cards, test smooth scrolling at 60fps

### Image Loading
- Always use `LazyVStack` (not `VStack`) for scrollable lists with images
- Use `VideoThumbnailService` for exercise thumbnails (already implemented)
- Implement `.task {}` for async loading, not `.onAppear` with `DispatchQueue`

---

## State Management Rules

### Environment Objects
The app passes these via `@EnvironmentObject`:
- `UserManager` — user profile, authentication state
- `SupabaseManager` — backend connection
- `WorkoutManager` — active workout state

**Rule**: Never create new instances of these — always receive them from the environment.

### Singletons (Shared Services)
Many services use the singleton pattern:
- `ChallengeService.shared`
- `PrivateChallengeService.shared`
- `PremiumManager.shared`
- `HapticManager` (static methods)
- `AppearanceManager.shared`

**Rule**: Access via `.shared`, observe with `@StateObject` or `@ObservedObject` as appropriate. `@StateObject` for views that own the lifecycle; `@ObservedObject` for views that receive it.

---

## Error Handling Pattern

### Standard error display:
```swift
if let error = errorMessage {
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
            retryAction()
        }
    }
    .padding(Spacing.lg)
}
```

---

## Integration Contract: Designer + Engineer

### How These Two Agents Work Together

1. **Designer Agent decides**: What it should look like (colors, typography, spacing, card style, animation)
2. **Engineer Agent decides**: How it should work (navigation pattern, state management, component selection, performance)
3. **Both agree on**: Component reuse — if a shared component exists, use it; if not, create one in the shared files

### Workflow for Building a New Feature

```
1. Engineer reads DESIGN_AGENT.md for visual specs
2. Engineer selects existing components from the inventory
3. If no suitable component exists:
   a. Engineer proposes a new shared component
   b. Designer Agent validates it matches the design system
   c. Component is added to DesignSystem.swift or AdaptiveColors.swift
4. Engineer builds the feature using only shared components + tokens
5. Engineer runs the Testing Checklist
6. Designer Agent reviews for visual consistency
```

### Conflict Resolution
If a design decision conflicts with an engineering constraint:
- **Performance wins over animation complexity** — simplify animations before sacrificing frame rate
- **Consistency wins over uniqueness** — use the standard pattern even if a custom one "looks better" on that one screen
- **Shared components win over inline code** — even if the shared component needs a minor tweak, extend it rather than duplicating

---

## Logic Audit Learnings

### Ownership from Logic Audit (March 2026)
- BUG-01: CollaborativeLearningEngine type safety (FIXED)
- BUG-03: SmartExercisePairingEngine operator precedence (FIXED)
- BUG-06: Challenge progress guard - pending status (FIXED)
- BUG-07: ChallengeProgressResolver consistency (FIXED)
- BUG-09: ForceExerciseRefresh delegation (FIXED)
- BUG-12: ContextualMealEngine dynamic targets (FIXED)
- GAP-01 through GAP-14: All logic gaps (FIXED)
- DUP-01, DUP-02, DUP-04, DUP-05, DUP-06: Consolidation (FIXED)
- DEAD-04 through DEAD-10: Dead code cleanup (FIXED)

### Key Rules Established
- "pending" challenges must NEVER receive progress updates — only "active"
- Operator precedence: always use explicit parentheses in compound boolean conditions
- Challenge progress must use `max(localValue, serverValue)` consistently
- `ExerciseFilterService.normalizeEquipment()` is the single source of truth for equipment normalization
- `ChallengeTypeResolvable` protocol is the canonical pattern for challenge type resolution
- `ExerciseTypes.swift` contains the shared `MovementPattern` enum (30 cases)
- `ExerciseCardRow` is the single shared exercise card component — used by both `CustomWorkoutBuilderView` and `ExerciseLibraryView`
- Replace mode (`.replace`, `.addToWorkout`) must always reset filter state on appear via `mode.isSingleSelect`
- Exercise replacement must show visual feedback: green border glow + toast message "Replaced with [Name]"
- `loadHistoricalDataForExercise` tasks must be tracked in `initTasks` for cancellation on view disappear

### Additional Domains Owned
- `GenderFilterService.swift` — gender-related exercise filtering
- `ExerciseTypes.swift` — shared exercise type enums
- `ExerciseCardRow.swift` — shared exercise card component
- `ActiveWorkoutView.swift` — active workout flow (set init, shuffle, progressive overload)
- `ExerciseSwapService.swift` — tiered exercise swap logic (co-owned with Fitness Expert)
- `ProgressiveWorkoutIntelligence` — progressive overload set generation
- `ActiveWorkoutTests.swift` — active workout test suite (16 tests)
- Localization/i18n (M-2: hardcoded strings)
- iPad/device form factor implementation (with Design Agent for specs)

---

## Quick Reference: File Locations

| Need | File | Line |
|------|------|------|
| Typography tokens | `DesignSystem.swift` | 18-41 |
| Spacing tokens | `DesignSystem.swift` | 45-54 |
| Corner radius tokens | `DesignSystem.swift` | 58-64 |
| Gradient presets | `DesignSystem.swift` | 70-98 |
| SectionHeader | `DesignSystem.swift` | 103-131 |
| DSCard | `DesignSystem.swift` | 137-160 |
| DSPillButton | `DesignSystem.swift` | 164-189 |
| Adaptive colors | `AdaptiveColors.swift` | 1-90 |
| SleekCardBackground | `AdaptiveColors.swift` | 96-160 |
| .sleekCard() modifier | `AdaptiveColors.swift` | 163-182 |
| AdaptiveGradient | `AdaptiveColors.swift` | 185-290 |
| AnimatedOrbBackground | `AdaptiveColors.swift` | 326-458 |
| UniversalScaleButtonStyle | `SharedUtilities.swift` | 515-553 |
| .scaleButtonStyle() | `SharedUtilities.swift` | 552-553 |

---

*This document is your engineering bible. When the Designer Agent says "make it blue," you know exactly which blue (`LinearGradient.ds_primaryAccent`), which card style (`.sleekCard(accentColor: .blue)`), and which animation (`UniversalScaleButtonStyle(.standard, withHaptic: true)`) to use. No guessing, no improvising, no duplicating.*

---

## Onboarding Responsibilities

**Primary owner** of `NewOnboardingView.swift` and `PhoneVerificationSheet.swift`.

### Completed
- **H-12**: Removed 1,327 lines of dead code (duplicate PageTemplate step views)
- **H-13**: Added progress checkpoint persistence via UserDefaults
- **H-14**: Synced PhoneVerificationSheet to 45 countries, dialingCode, fromLocale(), maxAttempts=3
- **M-20**: Verified forgot-password link is accessible from sign-in form

### Remaining
- **M-18**: Add birthday date format toggle (MM/DD vs DD/MM override)
- Reduce file size further (7,541 lines → consider per-step file extraction)

### Reference
- `ONBOARDING_AUDIT.md` — Sections 3 (flow detail), 13 (components), 17 (validation checklist)

---

## Knowledge Updates Log

> **Rule**: When agents learn new patterns, fix bugs, or discover new UX requirements, append them here so knowledge persists across sessions.

### 2026-03-17: Active Workout Flow Fixes

**Set Initialization Contract**:
- `WorkoutManager.initializeSetsForExercise()` now PRE-FILLS `WorkoutSetData.weight` and `.reps` from cached history
- Previously: correct set count but empty values (weight=0, reps=0) — user had to retype
- Now: sets load with previous workout values ready to accept or edit

**Exercise Shuffle Contract**:
- Shuffle button uses `ExerciseSwapService.getQuickSwap()` for tiered swap logic
- Each `ExerciseCard` tracks its own `perExerciseSwapCount` for correct tier selection
- `shuffleExercise()` now calls `loadHistoricalDataForExercise()` to populate placeholders
- Minimum 3 sets created on shuffle (was 1)

**Historical Data Loading on Swap**:
- `loadHistoricalDataForExercise()` now also calls `syncSetsWithPreviousData()` to adjust set count and pre-fill values
- Will NOT overwrite sets where user has already entered data (`isCompleted` or non-zero weight/reps)

**UX Performance (verified working)**:
- `.scrollDismissesKeyboard(.immediately)` on the workout ScrollView
- Notes placeholder: `"Workout Name - M/d/yy"` format
- LazyVStack + debounced inputs (150ms) + pre-fetched Core Data properties

**Test Coverage**:
- `ActiveWorkoutTests.swift` added with 16 tests covering set init, progressive overload, swap tiers, historical data, and UX
- Run from DevMenuView test runner

### Architecture Flows (Active Workout)

**Set Initialization Flow**:
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

**Exercise Swap Flow**:
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

**Progressive Overload Flow**:
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

### Remaining Opportunities
- Progressive overload does not yet integrate with `GeneratedProgramService` periodization for program-context workouts
- `UserBehaviorLearningEngine` records swaps but `ExerciseSwapService` doesn't re-rank based on swap history yet (3+ swaps away should deprioritize)
- Warmup sets (e.g., 185lbs x 1) treated same as working sets in history calculations — filter by `SetType.warmup` needed
- `ExerciseSwapService` hits Core Data per shuffle — pre-computing swap graph at workout start would eliminate per-shuffle latency

### 2026-03-17: Video Loading Optimization

**Tap-Time Prefetch**:
- `ExerciseLibraryView.swift` `simultaneousGesture(TapGesture())` (~line 703) now calls `VideoPlaybackEngine.shared.priorityPrefetch(exerciseName:)` alongside popularity tracking
- This gives ~200-300ms head start during the NavigationLink push animation
- Only applies to ExerciseLibraryView (NavigationLink push); other entry points to ExerciseDetailView use `.sheet` or `.fullScreenCover` with shorter animation windows

**ExerciseDetailView Entry Points** (11+ total — prefetch is triggered in `ExerciseDetailView.onAppear` for all):
- `ExerciseLibraryView` — NavigationLink push (also gets tap-time prefetch)
- `ActiveWorkoutView` — `.sheet`
- `WorkoutHistoryDetailView` — `.sheet`
- `ProgramScheduleFullView` — `.sheet`
- `ExerciseSelectionView` — `.sheet`
- `CustomWorkoutBuilderView` — `.fullScreenCover`
- `ReceivedWorkoutsView` — `.sheet`
- `AutoWorkoutPreviewView` — `.sheet`
- `ProgramDayPreviewView` — `.sheet`
- `ProgramScheduleView` — via `ExerciseDetailWrapper`

**Crossfade Change**:
- `RemoteVideoPlayerView` no longer uses a hardcoded 50ms `DispatchQueue.main.asyncAfter` timer
- Now observes `playerManager.$isReadyToDisplay` (Combine publisher) — crossfade only when player has renderable content
- 2-second timeout fallback prevents infinite waiting on network failure

**Poster Frame Pre-Generation**:
- `ExerciseDetailView.onAppear` now triggers `VideoThumbnailService.shared.generatePosterFrame()` for exercises without cached posters
- `ExerciseLibraryView.onAppear` triggers batch `preGeneratePosterFrames(for:)` for first 20 visible exercises
- Ensures repeat visits have instant poster frames (~0ms visual)

### 2026-03-18: Weight Input Per-Side Toggle & Plate Calculator

**Per-Side Toggle** (on `SetRowView`):
- Small "total" / "/side" label below the weight field — tap to toggle mode
- In per-side mode, user types weight on one side; `setData.weight` stores total = (typed × 2) + barWeight
- Toggle is per-exercise (`ExerciseCard.isPerSideMode`), not per-set — all sets share the mode
- When toggling, the displayed value auto-converts (135 total ↔ 45/side with 45lb bar)
- Placeholders also convert: if previous was 135 total, per-side shows "45"

**Plate Calculator** (long press weight field):
- `PlateCalculatorView` presented as `.sheet` with `.presentationDetents([.medium])`
- Plate grid: 45, 35, 25, 10, 5, 2.5 — tap to add, shows count badges
- Bar weight picker: 45/35/25 — persisted via `@AppStorage("defaultBarWeight")`
- Live total display: per-side breakdown + grand total
- "Apply" fills `setData.weight` with the grand total and dismisses

**Data Rule**: Weight is ALWAYS stored as total. Per-side mode and plate calculator are input-only conveniences. No Core Data or Supabase changes.

### 2026-03-19: Exercise Search Unification

**Architecture**: All exercise search is now routed through `SmartExerciseSearchService.shared.searchExercisesUltraFast()` as the single source of truth. Both `ExerciseSelectionView` and `ExerciseLibraryView` call this method — no more duplicated inline search logic.

**Search Flow**:
```
User Types → onChange(of: searchText)
                ↓
         [100ms micro-debounce]
                ↓
         updateFilteredExercises()
                ↓
         Check view-level searchCache[key]
            ↓ (miss)
         SmartExerciseSearchService.shared.searchExercisesUltraFast()
                ↓
         [Per-word typo correction UPFRONT]
         [Per-word variation generation]
         [Priority bucket sort: exact > startsWith > contains > allWords > secondary]
         [Secondary: category + muscles + equipment + nickname]
         [Personalization boost from UserBehaviorProfile]
         [Prefix-aware cache reuse for incremental typing]
                ↓
         Cache result → update UI
```

**Key Files**:
- `SmartExerciseSearchService.swift` — sole search implementation (typos, variations, scoring, caching)
- `ExerciseFilterService.swift` — shared `exerciseMatchesEquipment()` and `isExerciseForMuscleGroup()` (filter logic)
- `ExerciseSelectionView.swift` — workout exercise picker (delegates search to service)
- `ExerciseLibraryView.swift` — library tab (delegates search to service)

**Rules for new search features**:
- NEVER add search/typo/variation logic inline in a view — add it to `SmartExerciseSearchService`
- NEVER add equipment/muscle matching logic inline in a view — add it to `ExerciseFilterService`
- Both views share a 100ms debounce on `searchText` changes (clear = instant, typing = debounced)
- Call `SmartExerciseSearchService.shared.invalidateCache()` whenever the pre-filtered exercise set changes

### 2026-03-19: Active Workout Settings Side Panel

**Architecture**: Gear icon in top-left of `ActiveWorkoutView` opens a half-width settings panel from the left edge. Panel is a ZStack overlay with dimmed backdrop + `WorkoutSettingsPanel` struct.

**Side Panel Pattern**:
- Width: 55% of screen
- Animation: `.spring(response: 0.35, dampingFraction: 0.85)` with `.transition(.move(edge: .leading))`
- Backdrop: `Color.black.opacity(0.4)`, tappable to dismiss
- Panel background: `Color(red: 0.08, green: 0.08, blue: 0.10)` dark / `systemGroupedBackground` light

**@AppStorage Keys** (all persist across workouts):
| Key | Type | Default | Purpose |
|-----|------|---------|---------|
| `workoutWeightUnit` | Bool | false | lb (false) / kg (true) |
| `workoutPerSideMode` | Bool | false | Total (false) / Per-Side (true) |
| `defaultBarWeight` | Double | 45 | Bar weight for plate calculator |
| `defaultRestSeconds` | Int | 90 | Default rest timer in seconds |
| `autoStartRestTimer` | Bool | true | Auto-start timer between sets |
| `keepScreenOnDuringWorkout` | Bool | true | Prevents screen dimming |
| `workoutSoundEffects` | Bool | true | Sound effects during workout |

**Keep Screen On**: Sets `UIApplication.shared.isIdleTimerDisabled = true` on appear, resets to `false` on disappear. Also reacts to toggle changes in the panel.

**Remove Ads**: Free users see a "Remove Ads" row with gold crown that opens `PremiumUpgradeView` sheet.

**Minimize Workout**: Bottom of panel has "Minimize Workout" button calling `workoutManager.navigateToHomeTab()` -- preserves the old back-chevron behavior.

### 2026-03-19: Rest Timer — Countdown Glow Architecture

**Timer Promotion**: `RestTimer` was promoted from `SetRowView` (per-set `@StateObject`) to `ExerciseCard` level (`@StateObject private var cardRestTimer`). Only one timer per card can be active at a time (enforced by `activeTimerSetNumber`), so a single shared instance is correct. `SetRowView` now receives the timer as `@ObservedObject var restTimer: RestTimer`.

**Countdown Glow Overlay**: Replaced the inline progress bar below completed set rows with an electric blue glow that traces the `ExerciseCard` border. Uses `RoundedRectangle.trim(from: 0, to: visualRemainingProgress)` with `.stroke()` and double `.shadow()` for the glow effect. Animation: `.linear(duration: 1.0)` synced to `timeRemaining`. When the timer is inactive and the card is active, falls back to the existing blue-purple gradient stroke.

**Timer Settings Wiring Fixes**:
- `getRestDuration(for:)` now returns `TimeInterval(defaultRestSeconds)` from `@AppStorage` instead of hardcoded category-based values
- `autoStartRestTimer` now gates the `startWithAdOffset()` call in the checkmark action — when `false`, completing a set does not start the rest timer
- `restDuration == 0` means timer is off (user set Default Rest to 0s in settings)

**Data Flow**: `ActiveWorkoutView` → `autoStartRestTimer` (Bool) → `ExerciseCard.autoStartTimer` → `SetRowView.autoStartTimer` → gates `restTimer.startWithAdOffset()` in checkmark action.

### 2026-03-19: Premium Default Change

**PremiumManager.isPremiumUser** now defaults to `true` (was `false`). This means all features are available by default. StoreKit still updates the status when subscription info is confirmed. The music player (`NowPlayingBar`) and other premium-gated features are now visible by default.

### 2026-03-19: Workout Completion & Share Redesign

**Completion Screen Restructure** (`WorkoutCompletionView.swift`):
- New layout order: Celebration header → Inline Replay Insights → Expandable Workout Card → Notes → Progress Photo → Reopen
- Replay insights are now shown inline (staggered animation), no longer behind a button/sheet
- `WorkoutReplayView.swift` kept for potential standalone use but not presented from completion screen
- Removed: `showingReplay` state, `.sheet(isPresented: $showingReplay)`, `replayButton`

**Expandable Sleek Workout Card Pattern**:
- `@State private var isCardExpanded = false` controls collapsed/expanded state
- Collapsed: gradient ring + checkmark, workout name, date, stats row, muscle tags, chevron.down
- Expanded: reveals `CompletionExerciseRow` cards for each exercise below the stats
- Uses `.sleekCard(cornerRadius: CornerRadius.xl, accentColor: workoutGradient[0])` — replaces old hardcoded `Color(white: 0.18)` background
- Same expandable card pattern reused in `ShareWorkoutSheet`

**Notes Section**:
- Placeholder updated to "Anything you'd like to add?"
- Notes carry over from active session via `workout.notes` on appear
- Notes persist back to Core Data on "Done" tap

**Share Sheet Redesign** (`ShareWorkoutSheet.swift`):
- Background: `AnimatedOrbBackground.workout()` replaces flat `Color(white: 0.08)`
- Card: Same expandable sleek card as completion screen
- Friend picker: Horizontal `ScrollView` with search icon + up to 5 `CachedFriendPhoto` circles (56pt)
- Layout: Card → "Send to Friend" header + horizontal picker → "Share Via" header + system share button
- Removed: Old `friendPickerView` list, old `showingFriendPicker` toggle, old `cardBackground` local property
- Compose view still shows when a friend is tapped from the horizontal picker

**Token Compliance**:
- All `Color(white: 0.18)`, `Color(white: 0.08)`, `Color(white: 0.15)` replaced with `Color.cardBackground` or `.sleekCard()`
- All font/spacing/cornerRadius use `ds_` / `Spacing.*` / `CornerRadius.*` tokens
