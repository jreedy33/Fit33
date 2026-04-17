# Fit33 Lead Product Engineer Agent

> **Role**: Lead Product Engineer. Owns functional correctness, navigation, component reuse, feature integration, and UI logic.

---

## Mandatory Standards (ALL Agents Must Follow)

1. **Logging**: ALWAYS use `AppLogger` — NEVER `print()`. Categories: `.network`, `.data`, `.workout`, `.social`, `.nutrition`, `.health`, `.ui`, `.performance`, `.auth`, `.general`. Levels: `.debug`, `.info`, `.warning`, `.error`.
2. **No force unwraps** in production code. Use `guard let`, `if let`, or nil-coalescing.
3. **Design tokens**: Use `.ds_*` font tokens and `Color.cardBackground` — no hardcoded `.system(size:)` or local cardBackground properties.
4. **Structured concurrency**: Use `Task { }` with `Task.sleep(for:)` — never `DispatchQueue.main.asyncAfter`.
5. **Accessibility**: All new interactive elements must have `.accessibilityLabel()` and `.accessibilityHint()`.
6. **Auth guards on all social fetches**: Every async fetch method in social/challenge/friend services MUST start with `guard SupabaseManager.shared.isAuthenticated else { return }`. MainTabView appears based on `hasCompletedOnboarding`, NOT `isAuthenticated` -- `.task` modifiers fire before auth completes, causing "Not authenticated" crashes if unguarded.
7. **Performance tracking on scrollable views**: Apply `.trackScrollJank(screen: "ScreenName")` to all new scrollable content. Heavy computation MUST run off the main thread (use background Core Data context or `Task.detached`). Never iterate `@FetchRequest` results in nested loops on the main thread.
7b. **Widget isolation in ScrollViews**: Any widget in a ScrollView with 5+ siblings MUST be its own View struct that owns its service subscriptions (`@StateObject`/`@ObservedObject`). Parent views must NEVER read `@EnvironmentObject`/`@ObservedObject` properties inline in body for widget rendering — pass only stable values (bindings, constants, cached `@State`) to isolated wrappers. Pattern: `DashboardQuestsWrapper`, `DashboardHeaderWrapper`, etc. in `DashboardView+Helpers.swift`.
8. **Network calls MUST be parallel**: All independent network calls in `.task` or `.onAppear` MUST use `async let` groups, NEVER sequential `await`. Dashboard network calls went from 20 sequential to 3 parallel batches.
9. **FetchRequests MUST have limits**: All `@FetchRequest` displaying limited items MUST include `fetchLimit`. Never load entire history when only showing 10 items.
10. **Cloud sync MUST be paginated**: `fetchWorkoutHistory()` and `fetchMealLogs()` use `.limit()` -- never fetch unbounded history.
11. **Database security — tables**: Every new table MUST have `ENABLE ROW LEVEL SECURITY` + CRUD policies scoped to `user_id = auth.uid()`. Tables without RLS are publicly accessible via the anon key — a critical vulnerability.
12. **Database security — views**: NEVER create views with `SECURITY DEFINER`. All public views MUST use `security_invoker = on`. SECURITY DEFINER views bypass RLS for all users. See `SUPABASE_AGENT.md` "When Creating a View".
13. **No placeholder navigation destinations in shipped `Destination` enums**. If the real view is not ready, HIDE the entry point (e.g. remove the chevron / card) rather than ship a `Text("Coming Soon")` destination. App Review flags "Coming Soon" screens as broken flows. Canonical example: `DashboardRoute.programDetailsPlaceholder` — the chevron was removed in `DashboardView+Programs.swift` on 2026-04-17 and the real `ProgramDetailsView` will re-enable the entry point when it lands.
14. **Every Settings / in-app control must do something.** Before merging any new row/button, verify the action closure is non-empty AND reaches a visible destination. `// Navigate to X` placeholder closures are a ship blocker. For "Help / Rate / Support" style controls, wire to `SFSafariViewController` against `AppConfig.Support.helpCenterURL` or `SKStoreReviewController` rather than leaving the closure blank.

---

## Architecture Overview

### App Structure
```
Fit33/
├── Fit33App.swift                       — App entry point, environment injection
│
│ ── Content / Tab Shell ──
├── ContentView.swift                    — Root onboarding gate (~113 lines)
├── ContentViewModels.swift              — ScrollToTopTrigger, Notification.Name, TabItem
├── MainTabView.swift                    — Tab bar + deep link handling (~630 lines)
├── GoButton.swift                       — GoButtonState, GoButtonOverlay, HomeBadgeCounter
│
│ ── Dashboard (Tab 1) ──
├── DashboardView.swift                  — Home tab core (properties + body, ~695 lines)
├── DashboardView+Header.swift           — Header, notification banner, start workout buttons
├── DashboardView+Challenges.swift       — Challenge cards and widgets (1v1, group, pending)
├── DashboardView+Programs.swift         — Program widgets and recommendations
├── DashboardView+Macros.swift           — Macros/nutrition dashboard widget
├── DashboardView+Activity.swift         — Recent workouts section, stats overview
├── DashboardView+Helpers.swift          — Data loading, motivational messages, utilities
├── DashboardModels.swift                — DashboardRoute, enums, DashboardNotificationCarousel (unified swipeable notification cards)
├── DashboardNavigationDestinations.swift — Navigation destination ViewModifier
├── DashboardWorkoutCards.swift          — RecentWorkoutCard, RecentCardioWorkoutCard, StatCard
├── DashboardWorkoutHistory.swift        — WorkoutHistoryFullView, day section views
├── DashboardStreakViews.swift           — StreakInfoSheet, EditStreakSheet
├── DashboardWeightWidget.swift          — Weight tracking widget + input sheet
├── DashboardHydrationWidget.swift       — Hydration widget + quick add sheet
├── DashboardWidgetSettings.swift        — Widget settings sheet
├── SmartProgramMiniCard.swift           — Program mini card component
│
│ ── Workout (Tab 2) ──
├── WorkoutTabView.swift                 — Workout tab
├── ActiveWorkoutView.swift              — Active workout core (properties + body, ~161 lines)
├── ActiveWorkoutView+Layout.swift       — Workout background, header bar, geometry content
├── ActiveWorkoutView+Init.swift         — Initialization, warmup, history loading
├── ActiveWorkoutView+Actions.swift      — Set completion, finish, cancel, shuffle, ads
├── ActiveWorkoutView+Persistence.swift  — Save, sync, Apple Health, analytics
├── ExerciseCard.swift                   — Exercise card component (~600 lines)
├── WorkoutSetViews.swift                — SwipeableSetRow, SetRowView
├── WorkoutDataModels.swift              — PreviousSetData, SetType, WorkoutSetData
├── RestTimerViews.swift                 — RestTimer, RestTimerView, TimerBorderShape
├── AddExerciseDuringWorkoutView.swift   — Add exercise sheet
├── PlateCalculatorView.swift            — Plate calculator
├── WorkoutSettingsPanel.swift           — Workout settings side panel
├── NowPlayingBar.swift                  — Music now-playing bar
├── ExerciseReplacementView.swift        — Exercise swap UI
├── RenameExerciseView.swift             — Rename exercise sheet
├── SelectAllTextField.swift             — UIKit text field wrapper
├── WorkoutUIHelpers.swift               — RoundedCorner, MarqueeText
├── ExerciseLibraryView.swift            — Not a tab; accessed from Workout tab
│
│ ── Meals (Tab 3) ──
├── SimpleMealPlanView.swift             — Meal plan main view (~1,543 lines)
├── MealPlanComponents.swift             — SmartDailySummary, MealRowCard, SwipeableMealCard
├── MealPlanSetup.swift                  — Profile setup, timer indicator
├── NutritionModels.swift                — MealType, FoodEntry, MacronutrientData
├── NutritionDetailViews.swift           — Nutrition charts, macro views, explainers
├── USDAFoodSearch.swift                 — USDA food search + result rows
│
│ ── Social (Tab 4) ──
├── FriendsTabView.swift                 — Social tab
│
│ ── Profile (Tab 5) ──
├── ProfileView.swift                    — Stats/Profile tab
│
│ ── Onboarding ──
├── NewOnboardingView.swift              — Onboarding core (properties + body, ~798 lines)
├── NewOnboardingView+Chrome.swift       — Shared header, button bar, progress, transitions
├── NewOnboardingView+Navigation.swift   — Step navigation, checkpoints
├── NewOnboardingView+Auth.swift         — Auth forms, social login, OAuth
├── NewOnboardingView+Verification.swift — Phone/email verification UI and logic
├── NewOnboardingView+Steps.swift        — All onboarding step content views
├── NewOnboardingView+Social.swift       — Profile photo, contacts, friend suggestions
├── NewOnboardingView+Completion.swift   — Confirmation, account creation, finish flow
├── OnboardingInfrastructure.swift       — KeyboardObserver, OnboardingSessionManager
├── OnboardingFormControls.swift         — Text fields, password fields, code boxes
├── OnboardingCardViews.swift            — Goal, experience, equipment, gender cards
├── OnboardingConfirmationViews.swift    — Summary rows, confirmation sections
├── OnboardingLimitationViews.swift      — Limitation cards, accommodation options
├── OnboardingPhotoPickers.swift         — Photo/camera pickers with coordinators
├── CountryCode.swift                    — Country code enum for phone input
│
│ ── Shared ──
├── DesignSystem.swift                   — Typography, spacing, corner radius, gradient tokens
├── AdaptiveColors.swift                 — Colors, SleekCard, AnimatedOrbBackground, AdaptiveGradient
├── SharedUtilities.swift                — UniversalScaleButtonStyle, shared helpers
└── [Feature views]                      — 90+ feature-specific SwiftUI views
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

**KNOWN BUG**: Dashboard challenge creation currently uses `NavigationLink` instead of `.fullScreenCover`. Check `DashboardView+Challenges.swift`. This MUST be fixed.

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
| `ScaleButtonStyle` | `HydrationWidget.swift:1491`, `DashboardView+Programs.swift` | `UniversalScaleButtonStyle` in `SharedUtilities.swift:515` |
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

### v1.30 Startup Architecture (Event-Driven)
`Fit33App.init()` is split into critical and deferred blocks:
- **Critical (synchronous)**: Core Data, BGTaskScheduler, session logging, UI appearance
- **Deferred (0.5s delay)**: Crash reporter, perf monitors, video engine, gender filter, haptics
- **Auth-only fast path**: `checkAuthOnly()` verifies session in <200ms, UI renders from Core Data cache
- **Deferred sync (3s delay)**: `syncAllDataFromCloud()` refreshes data after UI is interactive
- **Event-driven phases**: `StartupCoordinator` phases fire on actual completion events, not hardcoded timers
- `StartupWaterfall` logs a consolidated timeline after intelligence init completes
- **Workout generation**: Runs on background thread via `nonisolated` + `Task.detached` (was 5.2s main thread freeze)

### Tab Transition Rules
- Nutrition tab uses **two-phase rendering**: core content first, heavy widgets (recipes, hydration, weight tracker, orb background) after 150ms via `showSecondaryWidgets` flag
- Exercise tab defers `VideoThumbnailService.preGeneratePosterFrames` by 500ms
- `ExerciseLibraryFilterCache.precomputeRecommendedList` runs on `Task.detached` (NOT MainActor)
- Challenge syncs are throttled to 15s cooldown across `syncHealthKitDataToChallenges`, `syncAllTrackingToChallenges`, and `recalculateAllChallengeProgress`

### AnimatedOrbBackground
- Uses three animated `Circle` views with `RadialGradient` — lightweight but additive
- On Nutrition tab, deferred behind `showSecondaryWidgets` to avoid blocking first render
- On older devices (iPhone SE, iPad Air), test scroll performance with orbs active
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

## Key Rules Established
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

## Remaining Tasks

- **M-18**: Add birthday date format toggle (MM/DD vs DD/MM override) in `NewOnboardingView.swift`
- Consider splitting `NewOnboardingView.swift` (7,541 lines) into per-step files

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

### 2026-03-19: AI Insights Hub — CMS UI

**New page**: `admin-cms/src/app/insights/page.tsx` — AI Insights Hub with two tabs:
1. **Chat with Claude** (default tab): Streaming chat interface with live platform data context. Features: SSE streaming, conversation persistence, quick-ask buttons, conversation history sidebar.
2. **Saved Insights**: Card list of AI-generated insights with category/priority badges, expandable detail view, filter tabs (all/high priority/by category), "Generate New Insights" button.

**New API route**: `admin-cms/src/app/api/ai-chat/route.ts` — Streaming SSE endpoint that:
- Validates admin auth (same pattern as `/api/admin`)
- Fetches live platform data via the Edge Function's `get_data_context` action
- Streams Claude responses via `@anthropic-ai/sdk` `messages.stream()`
- Auto-saves conversations to `ai_chat_history` after streaming completes

**Nav**: Added "AI Insights" (brain icon) to `AdminShell.tsx` sidebar between Metrics and Crashes.

**CMS Patterns Established**:
- SSE streaming in Next.js: `ReadableStream` + `text/event-stream` content type
- Chat UI: message bubbles with `pre-wrap`, auto-scroll via `messagesEndRef`, Shift+Enter for newlines
- Quick-ask buttons: array of pre-built prompts that call `sendMessage(text)` directly

### 2026-03-27: Audit Log Viewer — CMS

**Page**: `admin-cms/src/app/audit/page.tsx` — Timeline (filters, paginated table, row expand for JSON `details`, CSV export using `export_audit_logs` + client filter to match applied filters) and Stats (`get_audit_stats`: totals, actions-by-type bars, admins, daily bars). **API**: `get_audit_logs`, `get_audit_stats`, `export_audit_logs` in `admin-cms/src/app/api/admin/route.ts`. **Nav**: `AdminShell` sidebar "Audit Log" (📋).

### 2026-03-20: Performance Audit — Code Fixes

**PR Detection** (`ActiveWorkoutView.swift`):
- `analyzeWorkoutWithAdvancedIntelligence()` now detects personal records before calling `AdvancedIntelligenceService`
- Iterates completed exercises, compares best weight against `ExerciseHistoryService.shared.personalRecordsCache[exerciseName].maxWeight`
- If any exercise exceeded its cached PR, passes `hadPR: true` to the intelligence service

**Friend Search Navigation** (`ShareWorkoutSheet.swift`):
- Search button in horizontal friend picker now presents `FriendsListView()` via `.sheet(isPresented: $showingFriendSearch)`
- Same component used by `FriendsTabView` for "Add Friend" — consistent UX

### 2026-03-20: Smart Treadmill Auto-Connect

**Problem**: At gyms with multiple identical treadmills, all broadcasting cryptic BLE names, users couldn't identify which device was theirs.

**Solution — Three-layer smart connect**:
1. **RSSI Proximity Auto-Suggest**: 5-sample rolling average stabilizes signal strength. If the strongest device is 15+ dBm above the next, auto-suggest it with a prominent green "Treadmill Detected" banner.
2. **Visual Signal Ranking**: Each device card shows signal bars (1-4), proximity label ("Very close" / "Nearby" / "Far"), and a "CLOSEST" badge on the strongest device. Green accent border highlights the closest.
3. **Device Memory**: `@AppStorage("lastConnectedBLEDeviceId")` remembers the last connected device. On next scan, if it reappears, shows a "Reconnect" banner. If remembered device is also the closest by RSSI, `shouldAutoConnect` returns true.

**Files modified**:
- `BluetoothFitnessManager.swift` — RSSI averaging (`rssiHistory`), `suggestedDevice`, `rememberedDevice`, `shouldAutoConnect`, device memory on connect
- `FitnessEquipmentView.swift` — `autoSuggestBanner()`, `reconnectBanner()`, updated `DiscoveredDeviceCard` with `isClosest`/`isLastUsed` badges, proximity labels

**RSSI reference ranges**: >= -50 dBm = "Very close" (4 bars), -50 to -65 = "Nearby" (2-3 bars), < -65 = "Far" (1 bar)

### 2026-03-24: Calories Burned on All Workout Cards

**Architecture**: Calories burned now display on every workout in Recent Activity — strength, cardio, and third-party (Apple Watch, Strava, Nike).

**Core Data change**: Added `caloriesBurned` (Double, default 0.0) to `Workout` entity. Existing workouts show "--" until completed again.

**Calorie calculation flow** (strength workouts):
```
User finishes workout → finishWorkout()
  → saveWorkoutData() [Core Data, no calories yet]
  → saveWorkoutToAppleHealth() [ASYNC TASK]
    → buildExerciseCalorieData() [exercise MET values]
    → HealthKitManager.calculateDetailedCalories() [MET * weight * duration]
    → workout.caloriesBurned = result [Core Data save]
    → saveWorkoutToCloud() [re-upsert with calories to Supabase]
    → HealthKit save [if authorized]
```

**Key design decision**: Calories are ALWAYS calculated and saved locally, even if HealthKit sync is disabled. The Apple Health save is optional but calorie persistence is not.

**UI changes**:
- `RecentWorkoutCard` (strength): Replaced XP column with Calories (flame icon, orange)
- `RecentCardioWorkoutCard` (cardio): Already showed calories — no change
- `WorkoutCompletionView`: Stats row shows Calories instead of XP, polls for async value
- `WorkoutHistoryDetailView`: Replaced Volume column with Calories
- `WorkoutHistoryFullView`: Stats header shows total Calories across all workout types

**Cloud sync**: `WorkoutHistoryDTO` now includes `caloriesBurned` field (maps to `calories_burned` column). Supabase migration: `20260324_workout_history_calories.sql`.

**Third-party workouts**: Already synced with calories from HealthKit via `HealthDataService.saveHealthKitWorkout()` → `CardioWorkoutDTO.caloriesBurned`. No changes needed.

### 2026-03-24: Real-Time Daily Quest Progress Bars

**Problem**: Quest progress bars showed stale server-side `currentValue` because:
1. Step quests: `onStepsUpdated()` existed but was NEVER called from HealthKit
2. Step reporting gated on threshold (wouldn't show 700/3000 until hitting 3000)
3. Protein quests were binary (hit/not hit), no gradual progress
4. No live client-side progress overlay

**Solution — Two Layers**:

**Layer 1: Instant visual feedback (client-side)**
`DailyQuestsWidget` now observes `HealthKitManager`, `HealthKitService`, `MealService`, and `HydrationService` via `@ObservedObject`. A `liveCurrentValue(for:)` function returns real-time progress:

| Quest Type | Live Data Source |
|---|---|
| Walk 3K/5K/7.5K/10K steps | `HealthKitManager.todaySteps` |
| Hit step goal | `HealthKitManager.todaySteps >= stepGoal` |
| Eat Xg protein | `MealService.todaysMeals` protein sum |
| Log 3 meals | `MealService.todaysMeals.count` |
| Log 3/8 waters | `HydrationService.todaySummary.entryCount` |
| Burn 300 calories | `HealthKitService.todayCalories` |
| 30 active minutes | `HealthKitService.todayActiveMinutes` |

Progress ring, bar, and label all use `liveProgress(for:)` — instant response without server round-trip.

**Layer 2: Server persistence (background sync)**
- `HealthKitManager.fetchTodaySteps()` → `DailyQuestService.onStepsUpdated()`
- `HealthKitService.syncTodayStats()` → `DailyQuestService.onCaloriesBurned()`
- `MealService.addMealEntry()` → `DailyQuestService.onProteinProgress(totalGrams:)`
- `onStepsUpdated()` fixed: reports ALL step quests regardless of threshold (server caps at target_value)
- `onActiveMinutesUpdated()` and `onCaloriesBurned()` fixed: no longer gate on thresholds

**Files changed**: `DailyQuestViews.swift`, `DailyQuestService.swift`, `HealthKitManager.swift`, `HealthKitService.swift`, `MealService.swift`

### 2026-03-27: Daily Quest Live Progress — Server Fallback + Expanded Coverage

**Bug fixed**: Step quest progress bars showed 0% on app launch when HealthKit hadn't loaded yet, even though the server had the correct step count. Root cause: `liveCurrentValue` for step quests did `min(liveSteps, targetValue)` without `max(liveSteps, quest.currentValue)`.

**Fix**: All `liveCurrentValue` cases now use `max(localValue, quest.currentValue)` as the baseline, so progress never appears lower than the last server sync.

**Expanded live tracking** (new quest types in `liveCurrentValue`):

| Quest Type | Live Data Source |
|---|---|
| Log breakfast/lunch/dinner/snack | `MealService.todaysMeals` filtered by meal type |
| Log a meal | `MealService.todaysMeals.count` |
| High protein meal | `MealService.todaysMeals.contains { protein >= 30 }` |
| Log all macros | Checks protein/carbs/fat > 0 in `todaysMeals` |
| Hydration before noon | `HydrationService.todaySummary.entryCount` |
| Sleep 7 hours | `HealthKitService.lastNightSleep` |

**Rule**: Every `liveCurrentValue` switch case MUST include `max(localValue, quest.currentValue)` unless the local check is authoritative for binary quests. Never return a bare local value that could be 0 when HealthKit/services haven't loaded.

### 2026-03-24: Push Notification Delivery Fix

**Root cause**: SQL RPCs (`accept_friend_request`, `create_challenge`, etc.) correctly INSERT into `push_notification_queue`, but nothing invoked the `send-push-notification` edge function to process the queue. Only `notify-contacts-user-joined` had a working caller.

**Fix — two layers**:
1. **iOS app triggers**: `PushNotificationService.flushPushNotificationQueue(triggeredBy:)` calls the `send-push-notification` edge function via `.functions.invoke()`. Wired into:
   - `FriendService.sendFriendRequest()`, `acceptFriendRequest()`
   - `ChallengeService.postChallengeCreation()`, `respondToChallenge()`, `createGroupChallenge()`
   - `CommunityChallengeService.joinChallenge()`, `joinChallengeFriendGated()`
2. **pg_cron fallback**: `process_push_notification_queue()` runs every 30s via `pg_cron` + `pg_net`, catches any missed notifications (e.g., challenge progress from DB triggers)

**pg_cron auth fix (2026-03-24)**: Three issues resolved for pg_net → edge function auth:
- Gateway JWT verification must be **OFF** in dashboard (Edge Functions > send-push-notification > Settings)
- `SUPABASE_SERVICE_ROLE_KEY` env var in edge functions is now short-format (`sb_secret_...`, 41 chars), NOT the JWT (219 chars). String `===` comparison fails.
- Fix: `isServiceRoleJWT(token)` decodes JWT payload and verifies `role === 'service_role'` + `ref` match — format-agnostic
- The `x-cron-key` custom header carries the JWT-format service role key from `internal_config`, bypassing gateway header mangling

**Additional fixes**:
- `PushNotificationService.removeDeviceToken()` now called in `SupabaseManager.signOut()` — logged-out users stop receiving pushes
- `sendImmediateNotification()` logs to `SessionLogManager` (category `.pushNotification`) for all send/block/fail events
- `didReceive` delegate logs notification taps with type and action context

**Key files**: `PushNotificationService.swift`, `FriendService.swift`, `ChallengeService.swift`, `CommunityChallengeService.swift`, `SupabaseManager.swift`, `NotificationManager.swift`
**Migration**: `supabase/20260324_push_notification_cron.sql` (pg_cron + test RPC)

**Push notification delivery flow (after fix)**:
```
SQL RPC (e.g. accept_friend_request)
  └─ INSERT INTO push_notification_queue (status: pending)
       ├─ iOS app: flushPushNotificationQueue() ──→ send-push-notification edge function ──→ APNs
       └─ pg_cron (30s fallback): process_push_notification_queue() ──→ same edge function ──→ APNs
```

### 2026-03-24: Push Notification Debug Tool

**Location**: Dev Menu → "Push" tab (`PushNotificationDebugView.swift`, DEBUG-only)

**Sections**:
1. **Token Status** — device token, APNs environment, server `is_valid`, re-register button
2. **Send Test Push** — 6 notification types (friend_request, friend_accepted, challenge_invite, challenge_accepted, challenge_progress, challenge_completed) through full pipeline via `insert_test_push_notification` RPC + flush
3. **Queue Status** — recent `push_notification_queue` rows (type, status, timestamps, errors), manual flush button
4. **Delivery Log** — `SessionLogManager` entries filtered to `.pushNotification` category
5. **Notification Preferences** — server-side `user_notification_preferences` row (master toggle, disabled types, quiet hours)

**Test RPC**: `insert_test_push_notification(p_notification_type, p_title, p_body)` — inserts into queue targeting `auth.uid()` for self-testing

### 2026-03-26: Verification Flow — "Too many attempts" on Correct Code (CRITICAL)

**Problem**: Users entering a correct OTP code during onboarding saw "Too many attempts. Please wait a minute and try again." — the code was verified by Twilio, but the error came from the **account creation** step that runs immediately after.

**Root cause**: `createMinimalAccountForEmailPasswordSignup()` called `signUp()` which hit Supabase auth rate limits. The catch block matched "rate"/"limit"/"too many" in the error and showed a misleading message on the verification screen. Worse, it reset `isPhoneVerified = false`, making users re-enter a code that was already consumed by Twilio — a dead end.

**Fix**:
1. **Retry with backoff**: Account creation now retries up to 3 times (2s, 4s delays) for rate-limit errors before giving up.
2. **Don't reset phone verification on rate limit**: `isPhoneVerified` stays `true` because the phone IS verified. User proceeds through onboarding normally. Account creation is retried at the confirmation step (`createAccountAndComplete()` fallback).
3. **Clearer error message**: Changed from "Too many attempts" to "Account setup is temporarily busy" — though in practice the user sees STATE 3 (success) since `isPhoneVerified` remains true.

**Key insight**: The phone verification and account creation are separate concerns. A Supabase auth rate limit should never invalidate a successful Twilio phone verification.

### 2026-03-25: Onboarding Signup Flow — Dead-End Recovery Fix (CRITICAL)

**Problem**: Two beta testers hit a permanent dead-end during email/password signup. After OTP phone verification, `createMinimalAccountForEmailPasswordSignup()` would:
1. Call `signUp()` which created the auth user in Supabase
2. `createUserProfile()` failed (timing/session issue before auth state was set)
3. Generic "Account creation failed" error shown, `isPhoneVerified` reset to false
4. On retry: `signUp()` fails with "already registered" — **permanent dead end, user can never proceed**

**Root cause**: `signUp()` in `SupabaseManager` set auth state (`isAuthenticated = true`) AFTER profile creation. If profile creation failed, the whole call threw, leaving an orphaned auth user with no profile and no session.

**Fix — three layers**:

1. **`SupabaseManager.signUp()`** — Auth state is now set IMMEDIATELY after `client.auth.signUp()` succeeds, BEFORE profile creation. Profile creation failure is no longer fatal (logged but not thrown). New public `ensureProfileExists()` method for recovery.

2. **`createMinimalAccountForEmailPasswordSignup()`** — Rewritten with recovery logic. If `signUp()` fails with "already registered" (from prior partial failure), it signs in with the same credentials and ensures the profile exists. Error messages now show the actual error instead of a generic string.

3. **`createAccountAndComplete()`** (confirmation screen fallback) — Same recovery pattern applied for users reaching confirmation unauthenticated.

**Architecture flow (after fix)**:
```
OTP verified → createMinimalAccountForEmailPasswordSignup()
  └─ signUpOrRecoverExistingAccount()
       ├─ Try signUp() → set auth state → profile creation (best-effort)
       └─ If "already registered" → signIn() → ensureProfileExists()
  └─ updatePhoneAndUsername() (best-effort, non-fatal)
```

**Key files**: `NewOnboardingView+Verification.swift`, `NewOnboardingView+Auth.swift`, `SupabaseManager.swift`

### 2026-03-21: Notification System Audit — Bug Fixes & Enhancements

**Architecture**: 25+ notification types across 5 categories (Workout, Social, Achievements, Health, Motivation). Local scheduling via `UNUserNotificationCenter` + server push via `push_notification_queue` → APNs.

**Key files**: `NotificationManager.swift` (scheduling, toggling, smart check), `NotificationSettingsView.swift` (settings UI), `PushNotificationService.swift` (token registration + queue flush), `Fit33App.swift` (comeback reminder with dedup)

**Critical fixes applied**:
- `scheduleAllNotifications()` now checks `last_workout_date` before scheduling streak protection / workout reminder — prevents false "you haven't worked out" notifications
- Comeback reminder logic removed from `performSmartCheck()` — only `Fit33App.checkForComebackReminder()` handles it (proper daily dedup via `last_comeback_reminder`)
- 3 missing types added to `NotificationCategory.social`: `.contactJoined`, `.challengeProgress`, `.challengeCancelled`
- `toggleNotification()` now has cases for `.morningMotivation`, `.weeklyProgress`, `.waterReminder`

**New features**:
- Weekly progress notification (Sunday 6 PM), water reminders (2h intervals 8AM-8PM), workout celebration (2s delay after completion)
- Graduated re-engagement: 3-7 days daily, 14-day milestone, 30-day milestone, then stop
- Achievement batching: 30-second window combines rapid-fire PR/level-up/streak into one notification
- Daily notification cap: 8/day, critical types (friend request, challenge invite) bypass
- `syncPreferencesToCloud()` upserts preferences to `user_notification_preferences` for server-side enforcement

### 2026-03-25: v1.33 — Dashboard Architecture & Feature Updates

**Dashboard wrapper view pattern (performance)**:
- `challengeService` and `dailyQuestService` are now plain `let` references in `DashboardView` — NOT `@ObservedObject`/`@StateObject`. This prevents challenge/quest updates from recomputing the entire Dashboard body.
- `DashboardQuestsWrapper` is a separate `View` struct that owns `@StateObject questService`. Quest updates only recompute the quest widget.
- `combinedRecentWorkouts` is a `@State` array updated via `rebuildCombinedWorkouts()` + `.onChange`, NOT a computed property.
- Horizontal carousels use `.simultaneousGesture(DragGesture(minimumDistance: 25))` — NOT `.highPriorityGesture(minimumDistance: 8)`.

**Daily Quest / Challenge sync**:
- When a user has an active step challenge, daily quests match the challenge target. The `get_daily_quests` RPC receives `p_active_step_challenge_target` from the app (extracted from `ChallengeService.shared.activeChallenges` and `activeGroupChallenges`, types: "steps", "walk").
- `DailyQuestService.gatherUserContext()` now includes `activeStepChallengeTarget`.

**Friend request accepted notification**:
- `accept_friend_request` RPC now inserts into BOTH `push_notification_queue` (type: `friend_accepted`) AND `app_notifications` (type: `friend_request_accepted`).
- `NotificationManager.handleNotificationType` handles both `friend_accepted` and `friend_request_accepted` for the tap handler.
- `app_notifications` schema uses `reference_id` (UUID) and `from_user_id` (UUID), NOT a `data` JSONB column.

**CMS Exercise Library Hub**:
- New `/exercises` page with filterable list (workout type, category, equipment, search).
- Exercise detail page with video autoplay, editable fields, autocomplete from DB values, delete with confirmation.
- Prev/next navigation between exercises.

**Key files changed**: `DashboardView.swift`, `DashboardView+Helpers.swift`, `DashboardView+Challenges.swift`, `DailyQuestService.swift`, `NotificationManager.swift`

### 2026-03-25: v1.35 — Dashboard Widget Isolation + Bug Fixes

**Full widget isolation (Phase 3 performance)**:
- ALL dashboard widget sections now wrapped in isolated View structs: `DashboardCustomHeaderWrapper`, `DashboardHeaderWrapper`, `DashboardChallengesWrapper`, `DashboardWorkoutCarouselWrapper`, `DashboardRecentWorkoutsWrapper`, `DashboardStatsWrapper`. Each owns its own service subscriptions. Parent body only instantiates lightweight structs.
- `DashboardView+Challenges.swift` is now a standalone `struct DashboardChallengesWrapper` (not `extension DashboardView`).
- `DashboardView+Programs.swift` split: `extension DashboardView` keeps `programConflictAlert`/`colorFromProgramType`; everything else is `extension DashboardWorkoutCarouselWrapper`.
- `startWorkoutButton` and `handleWorkoutSelection` moved from `DashboardView+Header.swift` to `extension DashboardWorkoutCarouselWrapper`.
- `AnimatedOrbBackground` orb animations changed from `repeatForever` to single-fire (drift to end position over 3-5s then stop). Eliminates continuous GPU rendering on all tabs.

**Duplicate workout save fix**:
- `saveWorkoutToAppleHealth()` was calling `saveWorkoutToCloud(workout:)` to update calories, which re-saved the entire workout creating a duplicate row. Replaced with targeted `updateWorkoutCalories(workoutId:calories:)` that only patches the `calories_burned` field.
- New method `SupabaseManager.updateWorkoutCalories()` does `.update(["calories_burned": calories])` on the existing `workout_history` row.

**League widget UI**: Subheader text ("You know X people here" + promotion status) and tier badge moved inside the card box.

**Startup performance fixes**:
- `DeferredInit` block in `Fit33App.swift` split: singleton inits (`MemoryPressureHandler`, `TaskThrottler`, `CPUProtection`, `HeavyWorkSentinel`) moved to `Task.detached`; only UIKit work (watchdog, FPS monitor, haptics) stays on main. DeferredInit dropped from 2800ms to 3ms.
- `ExerciseLibraryService.preWarmCache()`: removed `getAllExercises()` + `precomputeRecommendedList()` from inside `MainActor.run` block. Exercise fetch now happens on background context; filter cache kickoff deferred to after waterfall mark ends. FilterCache.precompute dropped from 6000ms to 139ms.

**Carousel swipe fix**: Workout carousel uses `.highPriorityGesture(DragGesture(minimumDistance: 25))` instead of `.simultaneousGesture` to prevent inner Button taps from firing during swipes. Custom/Auto buttons changed to `.frame(maxHeight: .infinity)` to match program widget height.

**Key files changed**: `DashboardView.swift`, `DashboardView+Helpers.swift`, `DashboardView+Challenges.swift`, `DashboardView+Programs.swift`, `DashboardView+Header.swift`, `DashboardView+Activity.swift`, `AdaptiveColors.swift`, `ActiveWorkoutView+Persistence.swift`, `SupabaseManager.swift`, `WeeklyLeagueViews.swift`, `Fit33App.swift`, `ExerciseLibraryService.swift`

### 2026-03-26: Crash Regression Fix — v1.34/v1.35 Stability Pass

**Challenge progress timeout handling**:
- `PrivateChallengeService.logProgress()` and `CommunityChallengeService.logProgress()` now check `SupabaseManager.shared.isAuthenticated` before the retry loop. Retries reduced from 5 to 3. Timeout detection expanded to catch both `NSURLErrorTimedOut` and `NSURLErrorCancelled`.

**Workout save auth safety**:
- `ActiveWorkoutView+Actions`: Changed `userId: user.id ?? UUID()` to `guard let userId = user.id` — prevents writing analytics data under a synthetic UUID when user.id is nil.
- `WorkoutManager`: Changed `userId: user.id?.uuidString ?? ""` to proper `guard let userId = user.id` pattern for the CollaborativeLearningEngine call.

**SQL migrations required (deploy before v1.36)**:
- `20260326_fix_user_programs_program_id.sql` — makes `program_id` nullable
- `20260326_fix_nudge_table.sql` — creates `group_challenge_nudges` table/columns
- `20260326_fix_friend_workout_uuid_cast.sql` — fixes UUID=text type mismatch in RPC

**Friend suggestions instant-load fix**:
- `ContactsService`: `suggestedFriends` and `peopleYouMayKnow` now persist to UserDefaults (`cached_suggested_friends_v1`, `cached_pymk_v1`). Loaded in `init()` so suggestions are always available instantly on app launch — blue "add friend" rings never show empty.
- Error in `findMatchingUsersDirect` no longer clears `suggestedFriends` — keeps cached data on network failure.
- New `refreshSuggestionsIfNeeded()` runs contacts + PYMK once per app session, independently from the Batch 1+2 pipeline. This prevents suggestions from being blocked behind slow challenge/league fetches.
- `FriendsTabView.task` calls `refreshSuggestionsIfNeeded()` directly (not gated behind `refreshAllFriendsData` Batch 3). Batch 3 now only runs on explicit pull-to-refresh (`force == true`).
- Net effect: suggestions always present on tab tap (from UserDefaults cache), refresh once per app open in background.

### 2026-03-26: Push Notification Reliability Overhaul

**Root causes fixed** (7 bugs causing intermittent delivery):

1. APNs `expiration: 0` discarded notifications for offline devices → changed to 24h TTL
2. `.single()` token query failed for multi-device users → now sends to all valid tokens
3. Quiet hours permanently killed notifications → now defers to after quiet hours end
4. Edge function crashes left rows stuck in `processing` → auto-recovery after 5 min
5. `BadDeviceToken` invalidated ALL user tokens → now scoped to specific bad token
6. Local notification daily cap of 4 silently dropped social notifications → raised to 15, social types bypass cap
7. No structured logging → JSON logs in edge function, elapsed-time tracking in Swift

**New diagnostics**:
- `diagnose_push_notifications()` RPC returns full health report (tokens, prefs, queue stats, delivery logs)
- `PushNotificationDebugView` now has "Run Full Diagnostics" button that calls this RPC
- `PushNotificationService.performTokenHealthCheck()` logs a warning if no device token exists 10s after app foreground
- `PushNotificationService._flushQueue()` now logs elapsed milliseconds and full error chain on failure

**New table**: `push_notification_delivery_log` — tracks each step of the pipeline (14-day retention, auto-pruned)

**Key files**: `PushNotificationService.swift`, `NotificationManager.swift`, `PushNotificationDebugView.swift`, `supabase/functions/send-push-notification/index.ts`
**Migration**: `supabase/20260326_push_notification_reliability.sql`

**Onboarding PYMK fallback**:
- When contacts sync finds no matches during onboarding, `fetchPeopleYouMayKnow()` now fires as a fallback (from the contacts grant handler + `.onAppear` of the addFriends step).
- New `filteredPYMK` computed property in `NewOnboardingView+Social.swift` filters friends-of-friends by friend/request status and search text.
- The addFriends step now has 4 branches: loading → contact matches → PYMK fallback ("Already part of the club!") → truly empty state. PYMK section uses the same `onboardingFriendRow` component.
- Previously, PYMK was only fetched from `FriendsTabView` after onboarding. Now it's also available during onboarding when contacts yield nothing.

### 2026-03-27: CMS Advanced Tools Suite — 6 New Pages

**New CMS pages** (all at `admin-cms/src/app/[feature]/page.tsx`, API actions in `route.ts`):

1. **Audit Log** (`/audit`) — Timeline + stats of all admin actions. Filters: date range, action type, admin email, target ID. CSV export. Uses `admin_audit_log` table (now enhanced with `details` JSONB and `admin_email`).

2. **Feature Flags** (`/flags`) — CRUD for `feature_flags` table. Inline toggle switches, rollout % slider, platform/version targeting, metadata JSON editor. Change history from audit log. App-facing RPC: `get_active_feature_flags()`.

3. **System Health** (`/health`) — DB table sizes, connection pool, push pipeline stats, RPC performance, index health, error rates. Auto-refresh toggle. Uses pg_stat RPCs.

4. **Moderation** (`/moderation`) — Report queue (pending/reviewing/resolved), stats by reason, suspension management, block relationship analysis. User detail page has new Moderation tab.

5. **Push Manager** (`/notifications`) — Campaign CRUD with segment targeting (all/at_risk/inactive_7d/inactive_30d/new_users/power_users), queue monitoring, per-user debug, delivery stats. `execute_push_campaign()` RPC resolves segments.

6. **Engagement** (`/engagement`) — Score distribution (power_user/engaged/casual/at_risk/churned), at-risk user list, power user leaderboard, weekly retention cohort heatmap, onboarding funnel, **geo heatmap** from timezone data. User detail page has new Engagement tab.

**AdminShell nav** now has 14 items (was 9). New: Engagement, System Health, Push Manager, Feature Flags, Moderation, Audit Log.

**User detail page** (`/users/[id]`) gained two new tabs: Engagement (score + breakdown) and Moderation (reports + suspensions).

### 2026-03-27: WHOOP Integration

**New files created**:
- `WhoopService.swift` — `@MainActor final class WhoopService: ObservableObject` singleton. OAuth 2.0 flow, token management (Keychain), API client for recovery/cycles/sleep/workouts/body/profile, sync orchestration with throttling. DTOs for all WHOOP API responses defined in same file.
- `WhoopSettingsView.swift` — Connect/disconnect/sync UI with recovery preview card. Uses `ASWebAuthenticationSession` for OAuth. Added to `SettingsView.swift` alongside Fitbit/Strava.
- `DashboardWhoopWidget.swift` — Isolated `DashboardWhoopWrapper` (widget isolation pattern). Shows recovery score, HRV, strain, RHR, and sleep performance. Only renders when WHOOP is connected.

**Modified files**:
- `AppConfig.swift` — `enum Whoop` with clientId, clientSecret, redirectUri, URLs, scopes. **Data** `apiBaseUrl` is `https://api.prod.whoop.com/developer` (OpenAPI `servers`); OAuth URLs use root `api.prod.whoop.com/oauth/...`. Bare host + `/v2/...` returns 404 `default backend - 404`.
- `DeepLinkManager.swift` — `case "whoop"` handles `fit33://whoop?code=...` callback.
- `HealthDataService.swift` — `syncWhoopData()` added to parallel `withTaskGroup`. Saves recovery to `whoop_recovery_data`, sleep to `sleep_logs` (enhanced), workouts to `cardio_workouts`. `updateConnectedSources()` includes "whoop".
- `SettingsView.swift` — `@StateObject whoopService` + NavigationLink to `WhoopSettingsView`.
- `DashboardView.swift` — `DashboardWhoopWrapper()` added after step tracker card.
- `WorkoutSuggestionEngine.swift` — `buildRecoverySuggestion()` checks WHOOP recovery level. Red zone overrides to recovery day suggestion. Yellow/green adds contextual message. New `whoopRecoveryOverride` field on `TodaySuggestion`.
- `AdvancedIntelligenceService.swift` — `trackActivityForRecovery()` uses WHOOP recovery level (red/yellow/green) for `activity_level` when connected, falling back to step-based heuristic when not.
- `HealthInsightsView.swift` — Three new WHOOP cards: recovery trend (7-day bar chart), strain trend (7-day bars), vitals (SpO2, skin temp, RHR, HRV grid).

**Navigation**: Settings > WHOOP (connect/disconnect/sync/preview) and Dashboard (recovery widget).

**Recovery-aware workout suggestions**: `WorkoutSuggestionEngine` now has a `whoopRecoveryLevel()` check. Red zone (0-33%) suggests recovery day with override message. Yellow zone (34-66%) appends a "listen to your body" note. Green zone (67-100%) encourages pushing harder. The override only applies when not in a program (programs take priority).

### 2026-03-27: Daily Quest Widget Fixes (3 bugs)

**Bug 1 — Celebration overlay never appeared**: The quest completion and bonus celebration overlays in `DashboardView` read from `dailyQuestService` (a plain `let`, per widget isolation rules). Since `let` references don't trigger re-renders, the overlays never showed when `showQuestCompletionCelebration`/`showBonusCelebration` changed. Fixed: extracted to `DashboardQuestCelebrationWrapper` (own `@StateObject`) in `DashboardView+Helpers.swift`, following the same pattern as `DashboardQuestsWrapper`.

**Bug 2 — Experienced users saw beginner fallback quests**: When the `get_daily_quests` RPC failed (network error, auth expiry, SQL mismatch), `defaultGoals()` always returned beginner quests ("Sync Contacts", "Start First Workout", "Explore Program") regardless of user experience. For users with workout history, this looked completely broken. Fixed: `defaultGoals()` now checks `UserManager.shared.currentUser?.totalWorkouts` — experienced users get real generic quests (Complete Workout, Walk 5K Steps, Log Breakfast) while beginners still get onboarding quests.

**Bug 3 — RPC parameter compatibility**: `GetDailyQuestsParams` always sent `p_active_step_challenge_target` even when 0. If the deployed SQL had only the 15-param version (before the challenge sync migration), PostgREST would fail to match the function signature. Fixed: custom `encode(to:)` omits the parameter when the value is 0, so the call works with both 15-param and 16-param SQL versions.

**Rule — Celebration overlays with isolated services**: Any overlay that reads from a service singleton (celebrations, toasts, banners) MUST be wrapped in its own View struct with `@StateObject` — never read from a plain `let` reference in the parent. Pattern: `DashboardQuestCelebrationWrapper`.

### 2026-03-27: Email/Password Signup — Account Creation Timing Fix (CRITICAL)

**Problem**: Email/password signups failed at phone verification with "Session expired. Please go back to the password step and re-enter your password." The `@State var password` was being lost across the ~10 navigation steps between entering the password and the phone verification step where the account was actually created. Two separate users hit this exact bug.

**Root cause**: Account creation was deferred until after phone verification (`createMinimalAccountForEmailPasswordSignup()`), which checked `password.isEmpty`. But `@State password` was cleared/lost during the multi-step onboarding journey (SwiftUI view recreation or state reconciliation failure). The `restoreFromCheckpoint()` function deliberately does NOT restore passwords for security, so any view recreation left `password` empty.

**Fix**: Account creation now happens EARLY in `handleAuth()` — immediately after the user confirms their password and accepts terms. `signUpOrRecoverExistingAccount()` is called while `@State password` is still fresh. By the time the user reaches phone verification, `supabaseManager.isAuthenticated` is already true (matching OAuth flow behavior), so `createMinimalAccountForEmailPasswordSignup()` short-circuits to just updating the phone number.

**Files changed**: `NewOnboardingView+Auth.swift` (handleAuth creates account early), `NewOnboardingView+Verification.swift` (signUpOrRecoverExistingAccount + updatePhoneAndUsername made internal, createMinimalAccountForEmailPasswordSignup has auth guard).

**Rule — Never defer account creation past navigation**: For email/password signup, the Supabase auth user MUST be created in the same step where the password is entered. `@State` properties cannot be relied upon to survive 5+ onboarding step transitions. OAuth flows don't have this problem because they authenticate immediately via token.

### 2026-03-28: Oura Ring Integration

**New files created**:
- `OuraService.swift` — `@MainActor final class OuraService: ObservableObject` singleton. OAuth 2.0 flow (same pattern as WHOOP), Keychain token storage, API client for readiness/activity/sleep/SpO2/workouts/personal info, sync with 300s throttle. All Oura API V2 DTOs defined in same file.
- `OuraSettingsView.swift` — Connect/disconnect/sync UI with readiness preview card. Uses `ASWebAuthenticationSession` with `callbackURLScheme: "fit33"`. Teal accent color. Auto-starts auth onAppear when not connected.
- `DashboardOuraWidget.swift` — Isolated `DashboardOuraWrapper` (widget isolation pattern). Shows readiness score, HRV, activity score, RHR, and sleep efficiency. Only renders when Oura is connected.

**Modified files**:
- `AppConfig.swift` — `enum Oura` with clientId, clientSecret, redirectUri, URLs, scopes.
- `Secrets.template.swift` / `Secrets.swift` — `ouraClientId` and `ouraClientSecret` placeholders.
- `DeepLinkManager.swift` — `case "oura"` handles `fit33://oura?code=...` callback.
- `HealthDataService.swift` — `syncOuraData()` added to parallel `withTaskGroup`. Saves readiness/activity to `oura_readiness_data`, sleep to `sleep_logs` (source: "oura"), workouts to `cardio_workouts` (source: "oura"). `updateConnectedSources()` includes "oura".
- `SupabaseManager.swift` — `updateIntegrationStatus` handles "oura" case. `syncAllIntegrationStatuses` includes `OuraService.shared.isConnected`.
- `SettingsView.swift` — `@StateObject ouraService` + NavigationLink to `OuraSettingsView` after WHOOP row.
- `DashboardView.swift` — `DashboardOuraWrapper()` added after WHOOP widget. `@AppStorage("showOuraWidget")` toggle.
- `DashboardWidgetSettings.swift` — Added `showOura` binding + Oura widget option row.

**Navigation**: Settings > Oura Ring (connect/disconnect/sync/preview) and Dashboard (readiness widget).

**Oura readiness levels**: Optimal (85-100, green), Good (70-84, yellow), Pay Attention (0-69, red). Different thresholds than WHOOP recovery (67/34 split).

### 2026-03-28: WHOOP Error Handling Pattern

**Rule**: WHOOP fetch methods (`fetchRecovery`, `fetchSleep`, `fetchCycles`, `fetchWorkouts`) catch `WhoopError.isConnectionError` (`.notConnected`, `.tokenRefreshFailed`) at `.debug` level. Only actual API failures use `.error`. The `fetchBodyMeasurements` method was already correct. All consumers (Dashboard widget, Health Insights) already guard on `whoopService.isConnected` before rendering — so `notConnected` errors only occur via race conditions or stale state, not user-facing failures. Pattern established: `} catch let error as WhoopError where error.isConnectionError { AppLogger.debug(...) }`.

**User-facing sync errors (2026-03-30)**: `WhoopService.setSyncError` maps raw API text through `userFacingSyncErrorMessage` — ingress `default backend - 404` and generic `HTTP 404` show short “update app / try Sync again” copy in `WhoopSettingsView` instead of the raw server body. Logs still use the full error.

### 2026-03-28: Workout Tab — My Stats Dashboard

**New file**: `WorkoutStatsView.swift` — personal fitness metrics dashboard below the active program widget on the Workout tab.

**Architecture**: `WorkoutStatsSection` container with 9 isolated widget structs, all following the mandatory widget isolation rule (each owns its own data subscriptions):

| Widget | Chart Type | Data Source |
|--------|-----------|-------------|
| `ComprehensiveStatsGridWidget` | 2-column grid | Core Data Workout + UserManager |
| `WorkoutVolumeChartWidget` | LineMark + AreaMark | Core Data Workout.totalVolume |
| `WorkoutFrequencyChartWidget` | Stacked BarMark | Core Data Workout.date by type |
| `StrengthProgressChartWidget` | Multi-line LineMark | Core Data WorkoutExercise/WorkoutSet |
| `PersonalRecordsWidget` | Horizontal scroll cards | Core Data exercise max weights |
| `BodyWeightTrendWidget` | LineMark + RuleMark | WeightTrackingService trends |
| `CaloriesBurnedChartWidget` | BarMark + RuleMark avg | Core Data Workout.caloriesBurned |
| `WorkoutDurationChartWidget` | BarMark + RuleMark avg | Core Data Workout.duration |
| `MuscleGroupDistributionWidget` | SectorMark donut | Core Data WorkoutExercise categories |

**Shared `StatsTimeframe` enum**: Week/Month/3M/Year/All with `StatsTimeframePicker` segmented control. Charts reload via `.task(id: timeframe)`.

**Performance**: All Core Data aggregations run on `newBackgroundContext()` via `context.perform {}`. Results published to `@MainActor` via `Task { @MainActor in }`. Charts use `LazyVStack` for deferred rendering. No `@FetchRequest` without purpose-bounded predicates.

**Design compliance**: `.sleekCard()` on every widget, `.ds_*` typography tokens, `Spacing.*` tokens, `CornerRadius.*` tokens, `SectionHeader` component. All personal data only — no social metrics.

**Integration point**: `WorkoutTabView.swift` `WorkoutHomeView.body` — `WorkoutStatsSection()` added after `workoutTabProgramWidget` in the content VStack.

**Key files**: `WorkoutStatsView.swift` (all 9 widgets + container + helpers), `WorkoutTabView.swift` (integration).

### 2026-03-28: FriendsListView — Top Friends Grid + Smart Search

**Top Friends layout change**: The `topFriendsHighlight` in `FriendsListView` was a swipeable 2-page carousel (3 most engaged + 3 newest added, with GeometryReader + DragGesture). Replaced with a static 3×2 grid — two `HStack(spacing: Spacing.sm)` rows stacked vertically in a `VStack(spacing: Spacing.sm)`. All 6 friends are now visible at once without scrolling or swiping.

**Smart friend search bar**: Added `friendSearchBar` below the top friends grid in both ranked and alphabetical views. Filters the full friends list by name or username in real-time (`friendFilterText` @State). Uses `Color.cardBackground` with `CornerRadius.md` styling, `ds_bodyMedium` font. Includes clear button with haptic feedback. Empty-state message shows when filter matches nothing.

**State removed**: `topFriendsPage` and `friendSwipeDragOffset` are no longer used for the top friends section (kept as @State but the swipe gesture and page indicator are removed).

**Key file**: `FriendsListView.swift` — `topFriendsHighlight`, `rankedFriendsSection`, `friendsListContent`, `friendSearchBar`, `filteredFriends`.

### 2026-03-28: Private Challenge Cover Photos — REMOVED (2026-03-29), Replaced with Icon Upload (2026-03-30)

**Original cover photo feature removed** due to 15 RLS crashes in v1.37 (bucket misconfiguration).

**Replaced (2026-03-30)**: Challenge icon upload feature. Users can upload a photo as the challenge icon (circular, replaces emoji). NOT a cover photo — this is the small circular icon shown in list rows and detail headers.

**Storage**: Uses `avatars` bucket at path `challenge_icons/{challengeId}.jpg` (upsert). Public URL stored in `cover_image_url` column on `private_challenges` table. Direct table update (not RPC) to set/clear the URL.

**Service methods**: `PrivateChallengeService.uploadChallengeIcon(challengeId:imageData:)` and `removeChallengeIcon(challengeId:)`.

**UI locations**:
- **Creation flow** (`PrivateChallengeCreationFlow`): `PhotosPicker` on the naming step alongside emoji options. Photo takes priority over emoji. After challenge creation, icon is uploaded with the new challenge ID. Flow remains 6 steps.
- **Admin settings** (`PrivateChallengeAdminSettingsView`): "Challenge Icon" section with upload/change/remove. Shows current icon (AsyncImage) or emoji fallback.
- **Display**: `PrivateChallengeDetailView.challengeIconView` shows `AsyncImage` when `coverImageUrl` is set. `FriendsTabView.privateChallengeRow` and `FriendsPrivateChallengeRow` already had conditional `AsyncImage` for `coverImageUrl`.

**Backend requirements (all deployed 2026-03-30)**:
- `private_challenges` table has `cover_image_url TEXT` column.
- RLS policy "Admin can update their challenges" allows `created_by = auth.uid()` to UPDATE directly.
- RPCs `get_my_private_challenges` and `get_private_challenge_detail` both return `cover_image_url` (added via `20260330_add_cover_image_to_rpcs.sql`). The field is positioned after `emoji` in both RETURNS TABLE definitions and SELECT lists. **Do NOT remove this column from these RPCs** — it powers the challenge icon display everywhere.
- `avatars` storage bucket allows authenticated uploads to `challenge_icons/{challengeId}.jpg`.
- The `coverImageUrl` field on `PrivateChallenge`, `PrivateChallengePreview`, and `PrivateChallengeDetail` Swift models maps to `cover_image_url`. It is nullable — nil means emoji-only display.

### 2026-03-30: v1.37 Crash Fixes (172 crashes)

**Social fetch retry** — `FriendService.fetchPendingRequests()`, `PrivateChallengeService.fetchPendingInvites()`, `FriendRankingService.fetchRankedFriends()`, `ActivityFeedService.fetchFeed()` now have 3-attempt retry with exponential backoff for `NSURLErrorTimedOut`. Exhausted retries log `.warning` (not `.error`). Non-timeout errors remain `.error`. Pattern matches existing `fetchMyChallenges()` / `fetchReceivedWorkouts()`.

**PushNotificationService UUID fix** — `DeviceTokenRecord.user_id` changed from `String` to `UUID`. Added 2-attempt retry for timeout.

**LimitationsService UUID fix** — `fetchUserLimitations()` filter `.eq("user_id", value: userId.uuidString)` changed to pass `userId` (UUID) directly. Added 2-attempt retry for timeout.

### 2026-03-30: Privacy Settings Feature

**Service**: `PrivacySettingsManager.swift` — singleton `ObservableObject` with 6 `@Published` Bool toggles: `hideProfilePhoto`, `hideFriendActivity`, `hideFromWeeklyLeague`, `hideFromContactSync`, `hideFromSearch`, `hideActiveStatus`. UserDefaults-first with debounced Supabase cloud sync (mirrors `UnitSettingsManager` pattern). `loadFromCloud()` accepts optionals for login sync.

**UI**: `PrivacySettingsView.swift` — full settings screen with `AnimatedOrbBackground`, card sections (Profile Photo, Social Features, Discoverability, Activity Status), per-toggle descriptions. Navigated from Settings > Privacy & Security > Privacy Settings.

**Client guards**:
- `UserManager.swift`: `postWorkoutActivity` skipped when `hideFriendActivity` is on (badges/streaks still awarded)
- `WeeklyLeagueService.swift`: `fetchOrJoinLeague` skipped when `hideFromWeeklyLeague` is on
- `ContactsService.swift`: `syncContactsToDatabase` skipped when `hideFromContactSync` is on
- `FriendPhotoCache.swift`: `CachedFriendPhoto`/`LargeCachedFriendPhoto` enforce photo privacy with TWO checks:
  1. **Local (current user)**: `@ObservedObject privacyManager` makes `isPhotoHiddenByPrivacy` reactive — toggling `hideProfilePhoto` immediately hides the current user's photo across all views without re-fetch.
  2. **Server-driven (all users)**: `isPhotoUrlEmpty` check prevents showing a cached image when `photoUrl` is nil/empty. When a user hides their photo, the server RPCs return `NULL` for `profile_photo_url`, and the client respects this by showing initials even if `FriendPhotoCache` has a stale cached image. This means friends/other clients see the change on their next data fetch (tab switch, pull-to-refresh, app foreground).

**Backend**: 6 new columns on `user_profiles` (see `DATA_BACKEND_AGENT.md`). Server-side RPC filtering in:
- `20260330_privacy_rpc_enforcement.sql`: search, friend activity feed, contact matching, people you may know, league leaderboard, league join
- `20260330_privacy_photo_all_rpcs.sql`: 1v1 challenges, group challenges, community challenges (leaderboard, detail, my challenges, friends-in), private challenges (detail, my challenges), received workouts, friend requests (pending + sent), get_friends (inner circle)

**Realtime privacy propagation**: When User A toggles `hideFromWeeklyLeague` or `hideFriendActivity`, other users see the change **instantly** (no tab switch needed). Architecture: Postgres trigger on `user_profiles` inserts signal rows into `privacy_change_events` table (change_type: 'league' or 'activity'). `RealtimeService.subscribePrivacyChanges()` listens via WebSocket and routes events — league changes refresh `WeeklyLeagueService.fetchFullLeaderboard()`, activity changes refresh `ActivityFeedService.fetchFeed()`. Client-side: `WeeklyLeagueService` also observes `PrivacySettingsManager.$hideFromWeeklyLeague` directly via Combine to clear the current user's own cached league standing immediately on toggle.
