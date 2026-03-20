# Fit33 Device Compatibility — Retroactive Fix Plan & Task Tracker

> **Owner**: Device Compatibility Agent
> **Purpose**: Step-by-step plan for the new Device Compatibility Agent and the existing team to retroactively fix the app for cross-device consistency, and track ongoing work.
> **Reference**: `DEVICE_COMPATIBILITY_AGENT.md` for full agent spec, device matrix, and patterns.

---

## Table of Contents
1. [How This Agent Works With the Team](#how-this-agent-works-with-the-team)
2. [Phase 0: Foundation (Do First)](#phase-0-foundation)
3. [Phase 1: Critical Screens Audit](#phase-1-critical-screens-audit)
4. [Phase 2: iPad Adaptation](#phase-2-ipad-adaptation)
5. [Phase 3: Polish & Edge Cases](#phase-3-polish--edge-cases)
6. [Phase 4: Ongoing New Feature Protocol](#phase-4-ongoing-new-feature-protocol)
7. [Screen-by-Screen Tracker](#screen-by-screen-tracker)
8. [Apple Watch Running Log](#apple-watch-running-log)

---

## How This Agent Works With the Team

### Role in the Team

The Device Compatibility Agent is a **cross-cutting reviewer** — similar to how Quality & Performance reviews every feature for stability, this agent reviews every feature for device fit. It does not own the UI logic (that's Product Engineer) or the visual design (that's Design Agent). It owns **how layouts adapt across devices**.

### Interaction with Each Existing Agent

| Agent | How Device Compatibility Interacts |
|-------|-----------------------------------|
| **Product Engineer** | DC Agent reviews every new view PR for responsive layout. PE implements the adaptive patterns DC Agent specifies. DC Agent may request layout restructuring (e.g., "this needs a 2-column grid on iPad"). |
| **Design Agent** | DC Agent consults Design Agent when adaptive layouts need visual decisions (e.g., "should the card stack vertically or use a grid on iPad?"). Design Agent defines the visual spec; DC Agent defines the breakpoints and sizing rules. |
| **Design System Enforcement** | DC Agent flags hardcoded spacing/sizing the same way DSE flags hardcoded colors/fonts. They coordinate: DSE handles token adoption for colors/typography, DC Agent handles token adoption for spacing/frames. |
| **Quality & Performance** | DC Agent provides the device test matrix. Quality Agent runs tests across those devices. If a layout issue causes a crash (e.g., constraint conflicts), Quality triages and DC Agent fixes. |
| **Data & Backend** | Minimal direct interaction. DC Agent may flag if a data payload is too large for Watch sync (future). |
| **Infra & Security** | Minimal direct interaction. DC Agent may request CI device simulators for automated screenshot testing. |
| **Fitness Expert** | DC Agent consults Fitness Expert when adapting workout screens for Watch — "what data is essential during a set on a 2-inch screen?" |

### Communication Protocol

1. **New Feature Flow**: When Product Engineer starts a new feature, DC Agent is consulted at Step 2 (before implementation) for layout requirements and at Step 6 (after implementation) for device audit.
2. **Bug Reports**: If a user reports "X looks broken on my iPad" or "text is cut off on SE", route to DC Agent first.
3. **PR Reviews**: DC Agent has review authority on any file containing `.frame()`, `.padding()`, `GeometryReader`, or size class usage.

### Step-by-Step: How to Use This Agent on Every New Feature

```
BEFORE BUILDING:
1. Product Engineer describes the feature
2. Design Agent provides visual spec
3. DC Agent provides device adaptation spec:
   - How should this look on iPhone SE vs Pro Max?
   - Does this need a different layout on iPad?
   - What size classes apply?
   - Are there Watch implications? (log them)

DURING BUILDING:
4. Product Engineer implements using DC Agent's adaptive patterns
5. DC Agent spot-checks responsive behavior during development

AFTER BUILDING:
6. DC Agent runs the full audit checklist (from DEVICE_COMPATIBILITY_AGENT.md)
7. DC Agent logs Apple Watch notes in the Watch Running Log (below)
8. DC Agent updates the Screen-by-Screen Tracker (below)
9. Quality Agent verifies no regressions
```

---

## Phase 0: Foundation

> **Goal**: Build the adaptive infrastructure that all screen fixes depend on. Do this FIRST before touching any views.
> **Lead**: Device Compatibility Agent + Product Engineer
> **Timeline**: Sprint 1

### Task 0.1: Add DeviceTier Enum to OrientationManager.swift
- [ ] Add `DeviceTier` enum (compact/standard/large/tablet) to `OrientationManager.swift`
- [ ] Add computed property `DeviceTier.current` based on `screenWidth`
- [ ] Add `isTablet: Bool` computed property
- [ ] Add `supportsSplitView: Bool` computed property
- **File**: `Fit33/OrientationManager.swift`

### Task 0.2: Add Adaptive Spacing to DesignSystem.swift
- [ ] Add `Spacing.adaptive(_:)` method that scales by DeviceTier
- [ ] Add responsive grid helpers: `adaptiveColumns(minWidth:)` → returns column count
- [ ] Add `AdaptiveFrame` view modifier for common responsive patterns
- **File**: `Fit33/DesignSystem.swift`
- **Co-owner**: Design Agent (approve token additions)

### Task 0.3: Create Responsive Layout Utilities
- [ ] Create `ResponsiveStack` — switches between VStack (compact) and HStack (regular) based on size class
- [ ] Create `AdaptiveGrid` — adjusts column count based on DeviceTier
- [ ] Create `DeviceConditional` view modifier — show/hide content by device tier
- **File**: `Fit33/ResponsiveLayout.swift` (new file)

### Task 0.4: Audit .ignoresSafeArea() Usage (136 instances across 87 files)
- [ ] Audit all 136 `.ignoresSafeArea()` instances
- [ ] Categorize: background-only (keep) vs content-affecting (fix)
- [ ] Fix content-affecting instances to only ignore on ZStack backgrounds
- **Files**: 87 files (see Quality Agent audit data)

### Task 0.5: Create Device Preview Helpers
- [ ] Add SwiftUI preview configurations for: iPhone SE, iPhone 15 Pro, iPhone 15 Pro Max, iPad Mini, iPad Pro 13"
- [ ] Create `DevicePreviewGroup` macro/helper for easy multi-device previews
- **File**: `Fit33/DevicePreviewHelpers.swift` (new file)

---

## Phase 1: Critical Screens Audit

> **Goal**: Fix the 6 main tab screens + highest-traffic flows for cross-device compatibility.
> **Lead**: Device Compatibility Agent
> **Supporting**: Product Engineer (implementation), Design Agent (visual decisions for iPad layouts)
> **Timeline**: Sprints 2-3

### Priority Order (by user traffic)

#### 1.1 Dashboard (DashboardView.swift) — P0
- [ ] Audit hardcoded frame widths in stat cards
- [ ] Add `horizontalSizeClass` if missing
- [ ] iPad: Convert to 2-3 column grid for stat cards
- [ ] iPhone SE: Verify no horizontal overflow on progress bars
- [ ] Pro Max: Verify cards fill width proportionally
- [ ] Log Watch implications (daily summary complication)

#### 1.2 Active Workout (ActiveWorkoutView.swift — 228KB) — P0
- [ ] This is the largest file. Audit all `.frame()` calls for hardcoded widths
- [ ] Verify exercise card, timer, and rest timer scale across devices
- [ ] iPad: Side-by-side exercise info + timer panel in landscape
- [ ] iPhone SE: Ensure set logging buttons are not cramped
- [ ] Verify keyboard avoidance for weight/rep input fields
- [ ] Log Watch implications (this is the #1 Watch feature — minimal set logging UI)

#### 1.3 Exercise Library (ExerciseLibraryView.swift) — P0
- [ ] iPad: Sidebar filter panel + exercise grid (NavigationSplitView)
- [ ] iPhone: Verify search bar + filter chips don't overflow on SE
- [ ] Grid cards: Use adaptive columns (2 on iPhone, 3-4 on iPad)
- [ ] Log Watch implications (none — too complex for watch)

#### 1.4 Meal Plan (MealPlanView.swift) — P1
- [ ] iPad: Side-by-side meal list + recipe detail
- [ ] iPhone SE: Verify food cards and macro displays fit
- [ ] Verify barcode scanner modal works on all sizes
- [ ] Log Watch implications (quick meal log from recents)

#### 1.5 Profile/Stats (ProfileView.swift) — P1
- [ ] iPad: Multi-column stat layout
- [ ] iPhone SE: Verify charts and graphs don't clip
- [ ] Verify settings list items have adequate touch targets
- [ ] Log Watch implications (streak complication, daily stats)

#### 1.6 Friends/Social (FriendsTabView.swift) — P1
- [ ] iPad: Sidebar friend list + activity feed
- [ ] iPhone SE: Verify friend cards and challenge previews fit
- [ ] Log Watch implications (friend activity notifications only)

#### 1.7 Onboarding (NewOnboardingView.swift — 355KB) — P1
- [ ] This is the single largest file. Audit for device compatibility thoroughly.
- [ ] iPad: Centered content with max-width constraint (don't stretch to full iPad width)
- [ ] iPhone SE: Verify all onboarding cards, inputs, and buttons fit without scrolling issues
- [ ] Verify keyboard avoidance on all text input screens
- [ ] Log Watch implications (none — onboarding is phone-only)

---

## Phase 2: iPad Adaptation

> **Goal**: Transform the app from "works on iPad" to "designed for iPad."
> **Lead**: Device Compatibility Agent + Product Engineer
> **Supporting**: Design Agent (iPad-specific visual specs)
> **Timeline**: Sprints 4-5

### Task 2.1: Navigation Architecture
- [ ] Implement `NavigationSplitView` wrapper for iPad
- [ ] Define sidebar items (tabs become sidebar sections on iPad)
- [ ] Maintain `NavigationStack` for iPhone
- [ ] Test with Split View (1/3, 1/2, 2/3)
- [ ] Test with Slide Over

### Task 2.2: Keyboard & Pointer Support
- [ ] Add `.hoverEffect()` to all tappable elements
- [ ] Add keyboard shortcuts: Cmd+N (new workout), Cmd+F (search), Escape (dismiss)
- [ ] Verify Tab key navigation through forms

### Task 2.3: Stage Manager Support
- [ ] Test all screens in resizable windows
- [ ] Ensure minimum window size handles gracefully (no crashes, no unreadable UI)
- [ ] Test multi-window (same app, two workout views)

### Task 2.4: iPad-Optimized Workout View
- [ ] Side-by-side: Exercise details (left) + Set logging (right)
- [ ] Persistent timer visible without scrolling
- [ ] Larger touch targets for weight/rep adjustment (60pt+ on iPad)

---

## Phase 3: Polish & Edge Cases

> **Goal**: Handle the long tail of device-specific issues.
> **Lead**: Device Compatibility Agent + Quality Agent
> **Timeline**: Sprint 6+

### Task 3.1: Dynamic Type Audit
- [ ] Audit all text for `.minimumScaleFactor` on variable-length strings
- [ ] Verify layouts hold at Accessibility Large text sizes
- [ ] Add `.lineLimit()` to prevent infinite text growth

### Task 3.2: Landscape iPhone Audit
- [ ] Audit all tab screens in iPhone landscape
- [ ] Ensure no content is hidden or inaccessible
- [ ] Active workout must be fully usable in landscape

### Task 3.3: Touch Target Sweep
- [ ] Audit all buttons, toggles, and tappable areas for 44x44pt minimum
- [ ] Fix any under-sized targets (common in toolbars, dismiss buttons, filter chips)

### Task 3.4: Scroll Performance on Varied Screens
- [ ] Profile scroll performance on long lists (exercise library, meal search) on iPad Pro
- [ ] Verify lazy loading works correctly on all screen sizes
- [ ] Test with 1000+ items in lists

---

## Phase 4: Ongoing New Feature Protocol

> **Goal**: Ensure every new feature ships device-compatible from day one.

### For Every New View File Created

The developer (or Product Engineer agent) must:

1. Include `@Environment(\.horizontalSizeClass) var horizontalSizeClass`
2. Use `Spacing.*` tokens for all padding/margins
3. Use `GeometryReader` or `ResponsiveStack` for layouts that need to adapt
4. Set `.frame(maxWidth: .infinity)` instead of hardcoded widths
5. Add `.minimumScaleFactor(0.75)` to any heading or title that could be long
6. Ensure all tap targets are >= 44x44pt
7. Add multi-device previews using `DevicePreviewGroup`

### For Every PR / Feature Review

The Device Compatibility Agent must:

1. Run through the Audit Checklist (in `DEVICE_COMPATIBILITY_AGENT.md`)
2. Test mentally against: iPhone SE, iPhone 15 Pro, iPad Pro 13" (minimum)
3. Log any Apple Watch implications in the Watch Running Log below
4. Approve or request changes on layout/spacing issues

---

## Screen-by-Screen Tracker

> Update this table as screens are audited and fixed.

| Screen | File | SE OK | 15 Pro OK | Pro Max OK | iPad Mini OK | iPad Pro OK | Landscape | Watch Logged | Status |
|--------|------|-------|-----------|------------|-------------|-------------|-----------|-------------|--------|
| Dashboard | DashboardView.swift | -- | -- | -- | -- | -- | -- | -- | Not Started |
| Active Workout | ActiveWorkoutView.swift | -- | -- | -- | -- | -- | -- | -- | Not Started |
| Cardio Workout | CardioActiveWorkoutView.swift | -- | -- | -- | -- | -- | -- | -- | Not Started |
| Exercise Library | ExerciseLibraryView.swift | -- | -- | -- | -- | -- | -- | -- | Not Started |
| Meal Plan | MealPlanView.swift | -- | -- | -- | -- | -- | -- | -- | Not Started |
| Profile/Stats | ProfileView.swift | -- | -- | -- | -- | -- | -- | -- | Not Started |
| Friends | FriendsTabView.swift | -- | -- | -- | -- | -- | -- | -- | Not Started |
| Onboarding | NewOnboardingView.swift | -- | -- | -- | -- | -- | -- | -- | Not Started |
| Workout Builder | CustomWorkoutBuilderView.swift | -- | -- | -- | -- | -- | -- | -- | Not Started |
| Program Library | CloudProgramLibraryView.swift | -- | -- | -- | -- | -- | -- | -- | Not Started |
| Program Library (Local) | ProgramLibraryView.swift | -- | -- | -- | -- | -- | -- | -- | Not Started |
| Challenges | ChallengeFlowStartView.swift | -- | -- | -- | -- | -- | -- | -- | Not Started |
| Private Challenge | PrivateChallengeCreationFlow.swift | -- | -- | -- | -- | -- | -- | -- | Not Started |
| Food Search | FoodSearchView.swift | -- | -- | -- | -- | -- | -- | -- | Not Started |
| Food Details | FoodDetailsView.swift | -- | -- | -- | -- | -- | -- | -- | Not Started |
| Recipe Detail | RecipeDetailView.swift | -- | -- | -- | -- | -- | -- | -- | Not Started |
| Health Settings | HealthKitSettingsView.swift | -- | -- | -- | -- | -- | -- | -- | Not Started |
| Workout Tab | WorkoutTabView.swift | -- | -- | -- | -- | -- | -- | -- | Not Started |
| Cardio Landing | CardioLandingView.swift | -- | -- | -- | -- | -- | -- | -- | Not Started |
| Settings | SettingsView.swift | -- | -- | -- | -- | -- | -- | -- | Not Started |
| Workout Complete | WorkoutCompletionView.swift | -- | -- | -- | -- | -- | -- | -- | Not Started |
| Running Tracker | RunningTrackerView.swift | -- | -- | -- | -- | -- | -- | -- | Not Started |

**Legend**: `--` = Not tested | `PASS` = Looks correct | `FAIL` = Needs fix | `FIXED` = Issue resolved

---

## Apple Watch Running Log

> **Purpose**: As features are reviewed or built, log Apple Watch implications here. This becomes the Watch app spec when it's time to build.

### Existing Feature Watch Notes

| Date | iOS Screen/Feature | Watch Implication | Priority | Action Item |
|------|-------------------|-------------------|----------|-------------|
| 2026-03-20 | Active Workout (ActiveWorkoutView) | Core watch feature. Need: exercise name, set count, weight input, rest timer, next/complete buttons. Digital Crown for weight adjustment. | P0 | Design minimal set logging UI for 198pt width |
| 2026-03-20 | Rest Timer | Haptic pulse when rest timer completes. Show countdown on watch face. | P0 | Implement WKHapticType.notification on timer end |
| 2026-03-20 | Workout Start | "Start Workout" from watch — select from today's planned workout or recent workouts (max 5 options) | P1 | Need Watch Connectivity to sync today's plan |
| 2026-03-20 | Dashboard / Daily Progress | Complication: daily workout ring (similar to Activity app). Show streak count. | P0 | GraphicCircular complication with progress ring |
| 2026-03-20 | Streak System | Watch complication showing current streak number + flame icon | P1 | ClockKit GraphicRectangular complication |
| 2026-03-20 | Cardio / Running | Watch can provide real-time HR during runs. GPS from watch for outdoor tracking. | P1 | HealthKit workout session on watchOS |
| 2026-03-20 | Hydration Widget | Quick-tap water logging on watch. Complication showing oz/ml consumed today. | P2 | Simple tap interface, sync via Watch Connectivity |
| 2026-03-20 | Meal Quick Log | Log a recent/favorite meal from watch (tap to confirm, no food search) | P2 | Sync last 10 meals via updateApplicationContext |
| 2026-03-20 | Friend Workout Notifications | "Jordan just finished Chest Day" notification on watch | P3 | Push notification — no watch-specific code needed |
| 2026-03-20 | Challenge Progress | Complication: "2nd place — 3 workouts behind leader" | P3 | GraphicRectangular with rank + gap |
| 2026-03-20 | Workout Completion | Post-workout summary on watch: duration, volume, PRs hit | P2 | Display after workout session ends on watch |
| 2026-03-20 | Weight Tracking | Quick log morning weight from watch. Digital Crown for precise input. | P2 | Simple number input, sync to HealthKit + Supabase |

### New Feature Watch Notes
> **Append here as new features are built. Format:**
> `| YYYY-MM-DD | Feature Name | Watch Implication | Priority | Action Item |`

| Date | iOS Feature | Watch Implication | Priority | Action Item |
|------|------------|-------------------|----------|-------------|
| | | | | |

---

## Metrics to Track

| Metric | Current (Sprint 0) | Target |
|--------|-------------------|--------|
| Screens audited for device compatibility | 0 / 22 | 22 / 22 |
| Hardcoded `.frame(width:)` violations | ~5,986 frame/padding calls (needs audit) | < 50 hardcoded widths |
| `.ignoresSafeArea()` on content (not backgrounds) | Unknown (136 total) | 0 |
| Screens with `horizontalSizeClass` | ~20 | All screens with adaptive layouts |
| Screens with `verticalSizeClass` | 1 | All screens used in landscape |
| iPad-optimized screens (multi-column/sidebar) | 0 | All tab screens + key flows |
| Touch targets < 44pt | Unknown | 0 |
| Apple Watch features logged | 12 | All applicable features |
| `Spacing.*` token adoption | Unknown | 100% |
| DevicePreview coverage | 0% | All view files |

---

## Quick Reference: Who Does What

| Task | Who Does It | Who Reviews It |
|------|------------|---------------|
| Define adaptive breakpoints | Device Compatibility Agent | Product Engineer |
| Implement responsive layout code | Product Engineer | Device Compatibility Agent |
| Decide iPad visual layout (grid vs sidebar) | Design Agent | Device Compatibility Agent |
| Add spacing tokens | Design Agent | Device Compatibility + DSE Agent |
| Fix hardcoded frames | Product Engineer | Device Compatibility Agent |
| Test on device simulators | Quality Agent | Device Compatibility Agent |
| Log Watch feature ideas | Device Compatibility Agent | Fitness Expert (workout features) |
| Build Watch app (future) | Product Engineer | Device Compatibility Agent + Fitness Expert |

---

*This document is a living tracker. Update it after every screen audit, every new feature, and every Watch insight. The goal: Fit33 looks premium on every Apple device.*
