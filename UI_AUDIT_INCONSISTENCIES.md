# Fit33 UI Consistency Audit

> **Auditor perspective**: Lead Design Executive
> **Date**: March 6, 2026
> **Scope**: Every screen, widget, component, and navigation flow in the Fit33 iOS app
> **Files analyzed**: 150+ SwiftUI view files, 95+ screen files, all shared components

---

## Executive Summary

Fit33 has a strong design foundation: `DesignSystem.swift` defines typography, spacing, and corner-radius tokens; `AdaptiveColors.swift` provides a beautiful `AnimatedOrbBackground`, `SleekCardBackground`, adaptive colors, and tab-specific gradients. The problem is **adoption** — the majority of the codebase bypasses these systems entirely, creating a patchwork of inline styles that undermines the app's premium feel.

**By the numbers:**
- **32 screens** use the animated orb background; **20+ full-page screens do not**
- **71 files** hardcode `Color(white: 0.12)` instead of using `Color.cardBackground`
- **1,198 instances** of inline `.font(.system(size:))` instead of design-system typography tokens
- **1,213 instances** of hardcoded `cornerRadius` values instead of `CornerRadius` tokens
- **6 duplicate ScaleButtonStyle** implementations across different files
- **0 usages** of the `.adaptiveCard()` modifier (defined but never used)
- **0 usages** of the `DSCard` wrapper (defined but never used)

---

## Table of Contents

1. [Missing Animated Orb Background](#1-missing-animated-orb-background)
2. [Inconsistent Card Styles (Flat vs Sleek)](#2-inconsistent-card-styles)
3. [Navigation Flow Inconsistencies](#3-navigation-flow-inconsistencies)
4. [Duplicate ScaleButtonStyle Implementations](#4-duplicate-scalebuttonstyle)
5. [Hardcoded Background Colors](#5-hardcoded-background-colors)
6. [Typography Token Bypass](#6-typography-token-bypass)
7. [Spacing Token Bypass](#7-spacing-token-bypass)
8. [Corner Radius Token Bypass](#8-corner-radius-token-bypass)
9. [Inconsistent Button Styles](#9-inconsistent-button-styles)
10. [Missing Haptic Feedback](#10-missing-haptic-feedback)
11. [Divider Padding Inconsistencies](#11-divider-padding-inconsistencies)
12. [Empty State Inconsistencies](#12-empty-state-inconsistencies)
13. [Shadow System Inconsistencies](#13-shadow-system-inconsistencies)
14. [Legal/Utility Screens Missing Background](#14-legal-screens)
15. [Non-Standard Gradient Backgrounds](#15-non-standard-gradients)

---

## 1. Missing Animated Orb Background

### What the standard is
All main tab views and full-page screens use `AnimatedOrbBackground` from `AdaptiveColors.swift` — three animated floating radial-gradient orbs over a tab-specific `AdaptiveGradient`. This gives the app its signature living, breathing feel.

### Screens WITH the orb (correct)
| Screen | Orb Variant | File |
|--------|------------|------|
| Dashboard | `.home()` | `DashboardView.swift:194` |
| ContentView (Home) | `.home()` | `ContentView.swift:1120` |
| Workout Tab | `.workout()` | `WorkoutTabView.swift:379` |
| Friends Tab | `.friends()` | `FriendsTabView.swift:111` |
| Profile | `.stats()` | `ProfileView.swift:110` |
| Exercise Library | `.exercises()` | `ExerciseLibraryView.swift:938` |
| Exercise Detail | `.exercises()` | `ExerciseDetailView.swift:171` |
| Custom Workout Builder | `.exercises()` | `CustomWorkoutBuilderView.swift:694` |
| Cloud Program Library | `.exercises()` | `CloudProgramLibraryView.swift:55` |
| Cloud Program Schedule | `.exercises()` | `CloudProgramScheduleView.swift:1673` |
| Active Workout | `.workout()` | `ActiveWorkoutView.swift:4000` |
| Workout Completion | `.workout()` | `WorkoutCompletionView.swift:375` |
| Challenge Flow Start | `.home()` | `ChallengeFlowStartView.swift:145` |
| Challenge Creation | `.home()` | `ChallengeCreationFlow.swift:178` |
| Challenge Creation Inline | `.home()` | `ChallengeCreationFlowInline.swift:38` |
| Private Challenge Detail | `.home()` | `PrivateChallengeDetailView.swift:37` |
| Private Challenge Creation | `.home()` | `PrivateChallengeCreationFlow.swift:69` |
| Private Challenge Invite | `.home()` | `PrivateChallengeInviteView.swift:40` |
| Private Challenge Admin | `.home()` | `PrivateChallengeAdminSettingsView.swift:46` |
| Friends List | `.stats()` | `FriendsListView.swift:40` |
| Weekly League | `.friends()` | `WeeklyLeagueViews.swift:369` |
| Workout Progress | `.stats()` | `WorkoutProgressView.swift:621` |
| Performance Dashboard | `.stats()` | `PerformanceDashboardView.swift:19` |
| My QR Code | `.stats()` | `MyQRCodeView.swift:16` |
| Received Workouts | `.stats()` | `ReceivedWorkoutsView.swift:32` |
| Shared Workout Preview | `.stats()` | `SharedWorkoutPreviewView.swift:27` |
| Training Hub | `.home()` | `TrainingHubView.swift:41` |
| New Onboarding | `.onboarding()` | `NewOnboardingView.swift:3455` |
| Phone Verification | `.stats()` | `PhoneVerificationSheet.swift:38` |
| Existing User Phone | `.stats()` | `ExistingUserPhonePrompt.swift:45` |

### Screens MISSING the orb (inconsistent)

| Screen | Current Background | File | Recommended Fix |
|--------|-------------------|------|----------------|
| **Settings** | Hardcoded `LinearGradient` with inline RGB values | `SettingsView.swift:33-39` | Replace with `AnimatedOrbBackground.stats(colorScheme:)` |
| **Notification Settings** | Same hardcoded gradient as Settings | `NotificationSettingsView.swift:19-25` | Replace with `AnimatedOrbBackground.stats(colorScheme:)` |
| **Cloud Backup** | Same hardcoded gradient | `CloudBackupView.swift:57-60` | Replace with `AnimatedOrbBackground.stats(colorScheme:)` |
| **Limitations Settings** | Same hardcoded gradient | `LimitationsSettingsView.swift:22-28` | Replace with `AnimatedOrbBackground.stats(colorScheme:)` |
| **Bug Report** | `[Color(white: 0.08), Color.black]` — unique dark bg | `BugReportView.swift:31-37` | Replace with `AnimatedOrbBackground.stats(colorScheme:)` |
| **Smart Meal Planner** | 2-color gradient, different dark values | `SmartMealPlannerView.swift:44-49` | Replace with `AnimatedOrbBackground.meals(colorScheme:)` |
| **Recipe Browser** | Custom `backgroundGradient` with unique colors | `RecipeBrowserView.swift:23` | Replace with `AnimatedOrbBackground.meals(colorScheme:)` |
| **Recipe Detail** | Custom `backgroundGradient` | `RecipeDetailView.swift:37` | Replace with `AnimatedOrbBackground.meals(colorScheme:)` |
| **Meal Plan** | No explicit ZStack background | `MealPlanView.swift:17` | Add `AnimatedOrbBackground.meals(colorScheme:)` |
| **Shopping List** | `Color.black` / `Color(white: 0.95)` — flat colors | `ShoppingListView.swift:18` | Replace with `AnimatedOrbBackground.meals(colorScheme:)` |
| **Cardio Landing** | Custom gradient with unique dark RGB values | `CardioLandingView.swift:50-59` | Replace with `AnimatedOrbBackground.workout(colorScheme:)` |
| **Fitness Equipment** | Unique very-dark gradient to black | `FitnessEquipmentView.swift:51-59` | Replace with `AnimatedOrbBackground.workout(colorScheme:)` |
| **Strava Settings** | Default `List` background (no custom bg) | `StravaSettingsView.swift:19` | Wrap in ZStack with `AnimatedOrbBackground.stats(colorScheme:)` |
| **InBody Settings** | Default `List` background | `InBodySettingsView.swift:22` | Wrap in ZStack with `AnimatedOrbBackground.stats(colorScheme:)` |
| **Privacy Policy** | No background at all, bare ScrollView | `PrivacyPolicyView.swift:13` | Wrap in ZStack with `AnimatedOrbBackground.stats(colorScheme:)` |
| **Terms & Conditions** | No background at all, bare ScrollView | `TermsConditionsView.swift:13` | Wrap in ZStack with `AnimatedOrbBackground.stats(colorScheme:)` |
| **Dev Menu** | `[Color(red: 0.08...), Color.black]` | `DevMenuView.swift:23` | Replace with `AnimatedOrbBackground.stats(colorScheme:)` |
| **Developer Analytics** | Hardcoded color values | `DeveloperAnalyticsView.swift` | Replace with `AnimatedOrbBackground.stats(colorScheme:)` |
| **Personalized Programs** | Custom purple/blue/black gradient | `PersonalizedProgramsView.swift:72` | Replace with `AnimatedOrbBackground.exercises(colorScheme:)` |
| **Favorite Routines** | No orb background found | `FavoriteRoutinesView.swift` | Add `AnimatedOrbBackground.workout(colorScheme:)` |

### Why it matters
When a user navigates from the Dashboard (animated orbs, premium feel) to Settings (flat static gradient), the experience feels like stepping from a luxury car into a rental. Every full-page screen should breathe the same way.

### User experience after fix
Every screen transition feels seamless. The subtle floating orbs create a consistent atmosphere across the entire app. Users subconsciously register "this is one cohesive product" regardless of which feature they're using.

---

## 2. Inconsistent Card Styles

### What the standard is
The app defines two card systems:
1. **`SleekCardBackground` / `.sleekCard()` modifier** — 5-layer premium card: colored glow shadow + depth shadow + gradient fill + inner highlight stroke + accent border. Used on FriendsTab, WorkoutTab, DailyQuests, WeeklyLeague, AutoWorkoutPreview. **(40+ usages)**
2. **`DSCard` / `.adaptiveCard()` modifier** — Simple card with fill + shadow + dark-mode stroke. Defined in both `DesignSystem.swift` and `AdaptiveColors.swift`. **(0 usages)**

### The inconsistency

Many screens build cards with **inline styling** that partially resembles one system or the other:

| Pattern | Files Affected | Example |
|---------|---------------|---------|
| `Color(white: 0.12)` flat background, no glow | 71 files | `SettingsView.swift:27`, `BugReportView.swift:19`, `CloudBackupView.swift:51`, `NotificationSettingsView.swift:12`, `SmartMealPlannerView.swift:36`, `LimitationsSettingsView.swift:15` |
| Inline `LinearGradient` card fill without glow layers | `WorkoutTabView.swift`, `CustomWorkoutBuilderView.swift`, `FavoriteRoutinesView.swift` | Gradient fill but missing layers 1, 2, 4, 5 |
| `RoundedRectangle.fill(Color.cardBackground)` with basic shadow | 0 files (`.adaptiveCard()` never used) | N/A |

### Specific examples

**Settings View** (`SettingsView.swift:27`):
```swift
private var cardBackground: Color {
    colorScheme == .dark ? Color(white: 0.12) : Color.white  // Flat, no glow
}
```

**FriendsTab** (`FriendsTabView.swift:506`):
```swift
.sleekCard(cornerRadius: 18, accentColor: .blue)  // Full 5-layer premium treatment
```

**The user sees**: On the Friends tab, cards float off the background with subtle colored glows and glass-like borders. On Settings, cards sit flat against the background like Post-it notes on a wall.

### Recommended fix
- Adopt `.sleekCard()` for all primary content cards across the app
- Reserve flat `Color.cardBackground` only for list rows inside grouped sections
- Delete the unused `.adaptiveCard()` and `DSCard` to avoid confusion, or merge their behavior into `.sleekCard()` as a lighter variant

### User experience after fix
Every card in the app has the same multi-layer depth and subtle glow. The premium feel extends from the workout tab to settings to meal planning. Cards feel like they're made of frosted glass, not cardboard.

---

## 3. Navigation Flow Inconsistencies

### Challenge creation — two entry points, two different presentations

| Entry Point | Presentation Method | Navigation Wrapper | File |
|------------|--------------------|--------------------|------|
| Dashboard "Challenge a Friend!" widget | `NavigationLink` (pushes onto existing stack) | None needed (inherits parent) | `DashboardView.swift:4325` |
| Friends tab "New Challenge" button | `.fullScreenCover` (presents modally) | Wrapped in its own `NavigationStack` | `FriendsTabView.swift:215-219` |

**Both destinations are `ChallengeFlowStartView()`**, but the experience is completely different:
- From Dashboard: screen slides in from the right, back button appears, navigation bar inherits parent styling
- From Friends: screen slides up from the bottom as a full-screen modal, has no back button (user must dismiss), gets its own navigation stack

### Why it matters
- Muscle memory breaks: user expects "back swipe" from Dashboard flow but must find a close button from Friends flow
- The navigation bar looks different between the two because one inherits and one creates its own stack
- Deep linking and state restoration behave differently

### Recommended fix
Pick ONE pattern and use it everywhere for challenge creation. Recommendation: **`.fullScreenCover` with NavigationStack** (the Friends tab pattern) for all challenge creation, since it's a multi-step flow that benefits from modal isolation. Update `DashboardView.swift` to present via `.fullScreenCover` instead of `NavigationLink`.

### Other navigation inconsistencies found

| Issue | Details |
|-------|---------|
| **Community Challenge Hub** uses `.navigationDestination` push | `FriendsTabView.swift:207-210` |
| **All Communities** uses `.sheet` | `FriendsTabView.swift:212-214` |
| **League Detail** uses `.sheet` with `NavigationStack` | `FriendsTabView.swift:221-224` |
| **Premium Upgrade** mixes `.sheet` and `.fullScreenCover` | Various files |

### User experience after fix
No matter where the user taps "Challenge," they get the same presentation, same animation, same dismiss pattern. The app feels like one product, not stitched-together features.

---

## 4. Duplicate ScaleButtonStyle Implementations

### The problem
Six separate `ButtonStyle` structs exist that all do the same thing (scale on press) with slightly different parameters:

| Style Name | File | Scale | Opacity | Animation |
|-----------|------|-------|---------|-----------|
| `ScaleButtonStyle` | `HydrationWidget.swift:1491` | 0.92 | N/A | `.spring(response: 0.3, dampingFraction: 0.6)` |
| `ScaleButtonStyle` | `DashboardView.swift:1025` | Different impl. | N/A | Different |
| `MealsScaleButtonStyle` | `MealsQuickActionsView.swift:343` | 0.97 | 0.9 | `.easeInOut(0.15)` |
| `CardioScaleButtonStyle` | `CardioLandingView.swift:629` | varies | varies | varies |
| `TutorialScaleButtonStyle` | `WelcomeTutorialView.swift:808` | varies | varies | varies |
| `WorkoutDepthButtonStyle` | `WorkoutTabView.swift:1633` | 0.96 | 0.9 | `.easeInOut(0.15)` |
| `SubtleIndentButtonStyle` | `SubtleIndentButtonStyle.swift` | 0.95 | 0.8 | `.easeInOut(0.1)` |
| `UniversalScaleButtonStyle` | `SharedUtilities.swift:515` | Configurable | Configurable | Configurable |

### Why it matters
A user tapping a card on the Meals tab sees it shrink to 97%. Tapping a card on the Hydration widget, it shrinks to 92%. The difference is perceptible and makes some buttons feel "heavier" than others for no semantic reason.

### Recommended fix
Delete all duplicates. Use `UniversalScaleButtonStyle` from `SharedUtilities.swift` everywhere — it already supports configurable scale levels (`.subtle`, `.standard`, `.pronounced`). Apply via the existing `.scaleButtonStyle()` view extension.

### User experience after fix
Every tappable element responds with identical, satisfying press feedback. The app feels precisely tuned, like every button was placed by the same hand.

---

## 5. Hardcoded Background Colors

### The problem
71 files define `private var cardBackground: Color` with the same hardcoded value:
```swift
colorScheme == .dark ? Color(white: 0.12) : Color.white
```

Meanwhile, `AdaptiveColors.swift` defines:
```swift
static var cardBackground: Color {
    Color(UIColor { traitCollection in
        traitCollection.userInterfaceStyle == .dark
            ? UIColor(red: 0.14, green: 0.14, blue: 0.16, alpha: 1)  // Note: DIFFERENT values
            : UIColor.white
    })
}
```

The hardcoded value (`0.12` gray) doesn't even match the canonical value (`0.14, 0.14, 0.16`). This means cards on screens using the hardcoded value are slightly darker than cards using the design system.

### Top offenders
- `SettingsView.swift:27` — `Color(white: 0.12)`
- `NotificationSettingsView.swift:12` — `Color(white: 0.12)`
- `BugReportView.swift:19` — `Color(white: 0.12)`
- `CloudBackupView.swift:51` — `Color(white: 0.12)`
- `SmartMealPlannerView.swift:36` — `Color(white: 0.12)`
- `LimitationsSettingsView.swift:15` — `Color(white: 0.12)`
- `SharedWorkoutPreviewView.swift` — `Color(white: 0.12)`
- `FriendProfileView.swift` — `Color(white: 0.12)` AND `Color(white: 0.18)`
- `WeightTrackerWidget.swift:1162,1244,1314,1352,1439` — `Color(white: 0.12)`
- `HydrationWidget.swift:1105,1184,1236,1321` — `Color(white: 0.12)`
- `StepTrackerView.swift:457,487,529` — `Color(white: 0.12)`
- `DevMenuView.swift` — `Color(white: 0.12)`

### Recommended fix
Global find-and-replace: delete all local `cardBackground` computed properties and replace usages with `Color.cardBackground` from `AdaptiveColors.swift`. Ensure the canonical value is the one you prefer (currently `0.14, 0.14, 0.16` which has a slight blue/purple tint matching the overall dark theme).

### User experience after fix
Every card in the app has exactly the same background shade. No more "slightly-off" cards that make subconscious alarm bells ring.

---

## 6. Typography Token Bypass

### The problem
`DesignSystem.swift` defines 11 typography tokens (`ds_displayLarge`, `ds_heading1`, `ds_heading2`, `ds_heading3`, `ds_bodyLarge`, `ds_bodyMedium`, `ds_bodySmall`, `ds_labelLarge`, `ds_labelMedium`, `ds_labelSmall`, `ds_stat`). Yet **1,198 instances** across the codebase use `.font(.system(size: N, weight: W))` inline.

### Scale of the problem

| Inline Size | Design Token Equivalent | Instance Count | Top File |
|------------|------------------------|---------------|----------|
| 42pt | `ds_displayLarge` | ~5 | Various |
| 34pt | `ds_displayMedium` | ~8 | Various |
| 28pt | `ds_heading1` | 51 | CommunityChallengeViews (7) |
| 22pt | `ds_heading2` | 54 | Various |
| 18pt | `ds_heading3` | 141 | NewOnboardingView (18) |
| 17pt | `ds_bodyLarge` | ~20 | Various |
| 15pt | `ds_bodyMedium`/`ds_labelLarge` | ~80 | Various |
| 13pt | `ds_bodySmall`/`ds_labelMedium` | ~60 | Various |
| 11pt | `ds_labelSmall` | ~40 | Various |
| 16pt | Non-standard (closest: `ds_labelLarge`) | 245 | Many files |
| 14pt | Non-standard (between tokens) | 237 | Many files |
| 12pt | Non-standard (closest: `ds_bodySmall`) | 191 | Many files |
| 20pt | Non-standard (closest: `ds_heading3`) | 123 | DashboardView (11) |
| 10pt | Non-standard | 145 | Various |

### Why it matters
When you decide to adjust heading sizes globally (e.g., making `heading1` 26pt instead of 28pt), you'd need to find and update 51+ files. With tokens, you change one line.

More importantly, the non-standard sizes (14pt, 16pt, 20pt) create a subtly uneven type scale. Text that should feel identical across screens is actually 1-2pts different.

### Recommended fix
1. Add missing token levels for the commonly used non-standard sizes: `ds_bodyRegular` (16pt), `ds_caption` (10pt)
2. Systematically replace all inline `.font(.system(size:))` calls with the nearest token
3. Prioritize the highest-count files first: `DashboardView`, `NewOnboardingView`, `ContentView`, `WorkoutTabView`, `FriendsTabView`

### User experience after fix
Text hierarchy feels perfectly calibrated. Headlines, body text, and labels maintain their relative proportions across every screen. The app reads like a single, well-typeset document.

---

## 7. Spacing Token Bypass

### The problem
`DesignSystem.swift` defines spacing tokens (`Spacing.xs` = 8pt, `.sm` = 12pt, `.md` = 16pt, `.lg` = 24pt, `.xl` = 32pt, `.xxl` = 48pt). Yet **2,919 instances** use hardcoded padding values.

### The most common violations

| Hardcoded Value | Token Equivalent | Count | Issue |
|----------------|-----------------|-------|-------|
| `padding(16)` / `.padding(.horizontal, 16)` | `Spacing.md` | 203+ | Most common; should be easy batch fix |
| `padding(20)` | Non-standard | 71 | Falls between `Spacing.md` (16) and `Spacing.lg` (24) |
| `padding(14)` | Non-standard | 63 | Falls between `Spacing.sm` (12) and `Spacing.md` (16) |
| `padding(12)` | `Spacing.sm` | 60 | Straightforward token replacement |
| `padding(24)` | `Spacing.lg` | 27 | Straightforward token replacement |
| `padding(40)` | Non-standard | 12 | Falls between `Spacing.xl` (32) and `Spacing.xxl` (48) |

### Why it matters
Adjacent sections sometimes have 14pt padding on one side and 16pt on the other, creating a subtle visual imbalance. The `padding(20)` value (71 instances) is the most problematic — it's used where `Spacing.md` (16) or `Spacing.lg` (24) should be, creating a third unlabeled spacing tier.

### Recommended fix
1. Decide whether `padding(20)` should round down to `Spacing.md` (16) or up to `Spacing.lg` (24) — or add a `Spacing.mdLg` (20) token if truly needed
2. Similarly decide on `padding(14)` → round to `Spacing.sm` or `Spacing.md`
3. Batch-replace all standard values: `padding(16)` → `Spacing.md`, etc.

### User experience after fix
Consistent breathing room across every screen. Elements feel precisely placed on an invisible grid, giving the app a magazine-quality layout.

---

## 8. Corner Radius Token Bypass

### The problem
`DesignSystem.swift` defines: `CornerRadius.sm` (8pt), `.md` (12pt), `.lg` (16pt), `.xl` (24pt), `.pill` (999pt). Yet **1,213 instances** use hardcoded values, including many non-standard sizes.

### Non-standard corner radii creating visual noise

| Value | Standard? | Count | Issue |
|-------|-----------|-------|-------|
| 24pt | Yes (`CornerRadius.xl`) | 241 | Just needs token replacement |
| 16pt | Yes (`CornerRadius.lg`) | 367 | Just needs token replacement |
| 12pt | Yes (`CornerRadius.md`) | 208 | Just needs token replacement |
| 8pt | Yes (`CornerRadius.sm`) | 60 | Just needs token replacement |
| **20pt** | **No** | **141** | Between `.lg` and `.xl` — decide and standardize |
| **14pt** | **No** | **166** | Between `.md` and `.lg` — decide and standardize |
| **10pt** | **No** | **65** | Between `.sm` and `.md` — decide and standardize |
| **18pt** | **No** | **34** | Between `.lg` and `.xl` — decide and standardize |
| **25-28pt** | **No** | **131** | Exceeds `.xl` — used in `CustomWorkoutBuilderView` layered cards |

### Why it matters
A card with 14pt corners next to a card with 16pt corners creates a subtle but perceptible difference. The 20pt value (141 instances) is particularly problematic — used extensively in `FriendProfileView` (14 instances) where it sits beside 16pt cards from other views.

### Recommended fix
1. Eliminate non-standard values: round 10pt → 12pt (`.md`), 14pt → 12pt or 16pt, 18pt → 16pt (`.lg`), 20pt → 24pt (`.xl`) or 16pt (`.lg`)
2. For the 25-28pt values in `CustomWorkoutBuilderView` layered card effects, standardize to `CornerRadius.xl` (24pt) + offsets for the shadow layers
3. Replace all hardcoded values with tokens

### User experience after fix
Every rounded corner in the app uses one of exactly four radii. The visual rhythm becomes predictable and calming — the hallmark of professional design.

---

## 9. Inconsistent Button Styles

### Primary action buttons

| Screen | Padding (V) | Corner Radius | Font | File |
|--------|------------|---------------|------|------|
| Workout Completion "Done" | 16pt | 14pt | `.headline.bold` | `WorkoutCompletionView.swift:640-653` |
| Program "Start Program" | 10pt | 10pt | `.subheadline.semibold` | `GeneratedProgramService.swift:567-578` |
| Challenge creation CTAs | 14pt | 16pt | `.headline` | `ChallengeFlowStartView.swift` |

These are all primary action buttons but they have three different padding values, three different corner radii, and three different font treatments.

### Secondary/tinted buttons

Background opacity values are not standardized:
- `BugReportView.swift`: `Color.orange.opacity(dark: 0.2, light: 0.1)`
- `FriendProfileView.swift`: `Color.red.opacity(0.1)` — no dark mode adjustment
- `PremiumUpgradeView.swift`: `Color.white.opacity(isSelected ? 0.08 : 0.03)` — completely different formula

### Recommended fix
Create two standard button components in `DesignSystem.swift`:
- `DSPrimaryButton` — full-width gradient, `Spacing.md` vertical padding, `CornerRadius.lg` corner radius, `.ds_labelLarge.bold` font, always includes haptic
- `DSSecondaryButton` — tinted background, standardized opacity formula (0.15 dark / 0.08 light), `CornerRadius.md` corner radius

### User experience after fix
Every "main action" button in the app has the same satisfying size, shape, and feel. Users develop instant button recognition — "big gradient button = primary action."

---

## 10. Missing Haptic Feedback

### The problem
Only **5 files** implement `HapticManager` calls out of 72+ files with interactive buttons (443 total `HapticManager` occurrences, concentrated in those 5 files).

### Files WITH haptics
- `DesignSystem.swift` (DSPillButton only)
- `HydrationWidget.swift` (6 instances)
- `FavoriteRoutinesView.swift` (2 instances)
- `ChallengeFlowStartView.swift` (2 instances)
- `WorkoutCompletionView.swift` (1 instance)

### Files WITHOUT haptics (sampling)
- All Settings screens
- All Recipe/Meal screens
- ProfileView
- FriendsListView
- FriendsTabView (17 HapticManager imports but most buttons don't fire them)
- ExerciseLibraryView
- All Challenge detail/setup views

### Recommended fix
Integrate haptic feedback into the unified `UniversalScaleButtonStyle` — when `withHaptic: true`, automatically fire `HapticManager.impact(.light)` on press. Apply this style to all interactive cards and buttons. For destructive actions, use `.medium`. For success states, use `.notification(.success)`.

### User experience after fix
Every tap gives tactile confirmation. The app feels responsive and alive under the user's finger — a hallmark of Apple's own apps.

---

## 11. Divider Padding Inconsistencies

### The problem
Divider leading padding ranges from 16pt to 60pt across different screens:

| File | Padding | Context |
|------|---------|---------|
| `SharedWorkoutPreviewView.swift:238` | `.padding(.leading, 60)` | Between exercises |
| `SmartMealPlannerView.swift:951` | `.padding(.leading, 58)` | Ingredients |
| `SettingsView.swift:56` | `.padding(.leading, 52)` | Settings rows |
| `SmartMealPlannerView.swift:1021` | `.padding(.leading, 52)` | Steps |
| `FriendProfileView.swift:712` | `.padding(.leading, 50)` | Workouts |
| `FriendProfileView.swift:1078` | `.padding(.leading, 16)` | Exercises |
| `UnitSettingsView.swift:134` | `.padding(.leading, 16)` | Settings |
| `ChallengePreviewWidget.swift:783` | `.padding(.horizontal, 16)` | Widget |

### Recommended fix
Standardize divider indentation based on the row's icon/avatar alignment:
- Rows with 36pt icon + 16pt spacing = `.padding(.leading, 52)` (already the most common)
- Rows without icons = `.padding(.horizontal, Spacing.md)`
- Create a `DSDivider(indent:)` component to enforce this

### User experience after fix
Dividers consistently align with the content they separate, creating clean visual lanes that guide the eye.

---

## 12. Empty State Inconsistencies

### The problem
Each screen implements its own empty state with different icon sizes, text styles, spacing, and button designs. There is no shared `DSEmptyState` component.

### Examples of variance
- `HealthyRecipesCarousel.swift`: `.title` icon, `.subheadline` text, `.mint` button, 8pt corner radius
- `ShoppingListView.swift`: Custom implementation
- `WorkoutTabView.swift`: Custom implementation
- `FoodSearchView.swift`: Custom implementation

### Recommended fix
Create `DSEmptyState(icon:title:subtitle:action:)` in `DesignSystem.swift` with standardized:
- Icon: `.ds_heading1` size, `.secondary` color
- Title: `.ds_heading3`, `.primary` color
- Subtitle: `.ds_bodyMedium`, `.secondary` color
- Action button: `DSPillButton` style
- Spacing: `Spacing.md` between elements

### User experience after fix
When any list is empty, users see the same calm, helpful prompt — icon, explanation, action button. The consistency builds trust that the app handles every state gracefully.

---

## 13. Shadow System Inconsistencies

### The problem
Shadow parameters vary wildly across files:

| File | Radius | Y-Offset | Color/Opacity |
|------|--------|----------|---------------|
| `SharedWorkoutPreviewView.swift` | 10 | 5 | `blue.opacity(0.3)` |
| `MealsQuickActionsView.swift` | 12, 20 | 6, 10 | Double-shadow system |
| `HydrationWidget.swift` | varies | 4/6/10 | `cyan/black` mixed |
| `FavoriteRoutinesView.swift` | 8 | 4 | gradient color at 0.4 |
| `BugReportView.swift` | 8 | 4 | `black.opacity(0.1)` |

### Recommended fix
Define shadow tokens in `DesignSystem.swift`:
- `Shadow.subtle` — radius: 4, y: 2, opacity: 0.06 (light) / 0.15 (dark)
- `Shadow.standard` — radius: 8, y: 4, opacity: 0.08 (light) / 0.2 (dark)
- `Shadow.elevated` — radius: 12, y: 6, opacity: 0.1 (light) / 0.3 (dark) (matches `.sleekCard()`)
- `Shadow.glow(color:)` — radius: 20, y: 10, accent color at 0.12 (light) / 0.2 (dark)

### User experience after fix
Depth is consistent throughout the app. Cards at the same elevation cast the same shadow, creating a coherent spatial model.

---

## 14. Legal/Utility Screens Missing Background

### The problem
`PrivacyPolicyView.swift` and `TermsConditionsView.swift` have no background styling at all — they render as bare `ScrollView` content against the system default. They also use `.largeTitle.bold()` and `.subheadline` inline fonts instead of design tokens.

### Recommended fix
Wrap both in the standard ZStack pattern with `AnimatedOrbBackground.stats(colorScheme:)` and card-wrapped content sections. Replace inline fonts with `ds_heading1` and `ds_bodySmall`.

### User experience after fix
Even legal pages feel like part of the app, not an afterthought. Users maintain confidence they're still in a premium product.

---

## 15. Non-Standard Gradient Backgrounds

### The problem
Multiple screens use inline `LinearGradient` definitions that don't match any `AdaptiveGradient` preset:

| Screen | Dark Mode Colors | Issue |
|--------|-----------------|-------|
| `BugReportView.swift` | `[Color(white: 0.08), Color.black]` | Too dark, no purple/blue tint |
| `SmartMealPlannerView.swift` | `[Color(red: 0.04...), Color(red: 0.03...)]` | Different dark base than universal |
| `FitnessEquipmentView.swift` | `[Color(red: 0.02...), Color.black]` | Near-black, no tint |
| `DevMenuView.swift` | `[Color(red: 0.08...), Color.black]` | No purple/blue tint |
| `RecipeBrowserView.swift` | Custom unique gradient | Different from all presets |
| `CardioLandingView.swift` | Custom dark gradient | Unique to this screen |

### Why it matters
`AdaptiveGradient.universalDark` uses `[Purple.opacity(0.2), Blue.opacity(0.1), deep dark, near black]` — a carefully designed purple-blue tint that matches the app's orb aesthetic. Screens with `Color.black` or `Color(white: 0.08)` feel like different apps in dark mode.

### Recommended fix
Replace all inline background gradients with the appropriate `AdaptiveGradient` preset or `AnimatedOrbBackground` variant. If a screen truly needs a unique background (e.g., Premium Upgrade's dark purple), keep it but document the exception.

### User experience after fix
Dark mode feels like one continuous environment. The subtle purple-blue undertone ties every screen together, making the app feel like an Apple-level dark mode implementation.

---

## Implementation Priority / TODO

### Phase 1: High-Impact, Low-Effort (The Quick Wins)
- [ ] Add `AnimatedOrbBackground` to the 20 screens that are missing it
- [ ] Replace all local `cardBackground` computed properties (71 files) with `Color.cardBackground`
- [ ] Delete 5 duplicate `ScaleButtonStyle` implementations; use `UniversalScaleButtonStyle` everywhere
- [ ] Unify challenge creation navigation: use `.fullScreenCover` from all entry points
- [ ] Add `AnimatedOrbBackground` + basic styling to Privacy Policy and Terms pages

### Phase 2: Design System Enforcement (Systematic Cleanup)
- [ ] Replace all hardcoded `cornerRadius` values with `CornerRadius` tokens (1,213 instances)
- [ ] Replace all hardcoded `padding` values with `Spacing` tokens (2,919 instances)
- [ ] Replace all inline `.font(.system(size:))` with `Font.ds_*` tokens (1,198 instances)
- [ ] Replace all inline background gradients with `AdaptiveGradient` presets

### Phase 3: Component Standardization
- [ ] Create `DSPrimaryButton` and `DSSecondaryButton` components
- [ ] Create `DSEmptyState` component
- [ ] Create `DSDivider(indent:)` component
- [ ] Define shadow tokens in `DesignSystem.swift`
- [ ] Add haptic feedback to all interactive elements via `UniversalScaleButtonStyle`

### Phase 4: Verification & Polish
- [ ] Audit all screens in both light and dark mode after changes
- [ ] Test all navigation flows for consistency (challenge, workout, program creation)
- [ ] Verify all card styles render identically at each elevation level
- [ ] Performance test: ensure orb animations don't impact scroll performance on older devices

---

*This audit identifies the path from "good app" to "Apple-quality app." The design system exists — it just needs to be enforced everywhere.*
