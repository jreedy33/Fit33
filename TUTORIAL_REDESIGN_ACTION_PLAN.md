# Tutorial Walkthrough Redesign — Action Plan

**Project:** Fit33 iOS App
**Scope:** Post-onboarding tutorial walkthrough (`WelcomeTutorialView.swift`)
**Date:** March 7, 2026
**Status:** In Progress

---

## Executive Summary

Redesign the 9-screen post-onboarding tutorial into a polished, app-contextual walkthrough that introduces users to Fit33's core features using real UI widgets, informative copy, and a free trial CTA on the final screen. The tutorial should feel like a premium app experience (Nike Training Club, Strava, MyFitnessPal quality).

---

## Current State Analysis

### What Exists
- **9 tutorial screens** in `WelcomeTutorialView.swift` (~1,400 lines)
- Screens: Welcome → Auto-Generate → Custom Workouts → Programs → Streaks → Nutrition → Hydration → Community → Let's Go
- Uses `TabView` with `.page` style, skip button, custom page indicators
- Has widget previews for: Programs, Meals, Water, Streaks, and generic icon/button views
- Animated gradient backgrounds with pulsing orbs per page
- Haptic feedback on navigation

### What's Missing / Needs Improvement
1. **No Challenges screen** — Challenges (private + community) are a core feature
2. **No Add Friends screen** — Social features are central to engagement
3. **Community screen is generic** — Just shows a default icon, no real widget preview
4. **No free trial CTA** — Final screen says "Get Started" but doesn't offer the free trial
5. **Copy is vague** — Descriptions like "Share workouts with friends" don't sell the features
6. **No contextual feature previews** on Community screen — other screens have great widgets

---

## Redesigned Tutorial Flow (10 Screens)

### Screen 1: Welcome
- **Visual:** Fit33 logo with animated glow (KEEP AS-IS — already polished)
- **Title:** "Welcome to" + logo
- **Subtitle:** "Your intelligent fitness companion"
- **Copy:** "Build the perfect workout every time.\nLet's see what you can do."

### Screen 2: Auto-Generate Workouts
- **Visual:** Feature button card with sparkles icon (KEEP — already has widget)
- **Title:** "Auto-Generate"
- **Subtitle:** "Smart workouts in seconds"
- **Copy:** "Pick your time, muscles, and equipment.\nOur AI builds your perfect session."
- **Widget:** App button card showing "Auto Workout" with AI sparkle icon

### Screen 3: Custom Workouts & Exercise Library
- **Visual:** Feature button card (KEEP — already has widget)
- **Title:** "Build Custom"
- **Subtitle:** "Complete creative control"
- **Copy:** "5,000+ exercises with video demos.\nCreate your perfect routine from scratch."

### Screen 4: Programs
- **Visual:** Program progress widget (KEEP — already has rich widget)
- **Title:** "Programs"
- **Subtitle:** "Your 30-day transformation"
- **Copy:** "Progressive training programs tailored to your goals.\nTrack every day with built-in scheduling."

### Screen 5: Challenges (NEW)
- **Visual:** NEW challenge preview widget showing:
  - Challenge card with emoji (e.g., 🏋️), title, progress bar
  - Mini leaderboard snippet (3 entries with rank, name, progress)
  - "Join Challenge" button
- **Title:** "Challenges"
- **Subtitle:** "Compete & stay accountable"
- **Copy:** "Create private challenges with friends or join\ncommunity-wide competitions with leaderboards."
- **Gradient:** Orange → Red (competitive energy)
- **Animation:** bounce

### Screen 6: Add Friends & Social (NEW — replaces old Community)
- **Visual:** NEW friends widget showing:
  - Mini friend avatars in a horizontal stack
  - "Share Workout" card preview
  - QR code icon hint
- **Title:** "Connect"
- **Subtitle:** "Train with your crew"
- **Copy:** "Add friends, share workouts, and see what\nyour crew is training. QR codes make it instant."
- **Gradient:** Indigo → Purple (social/community)
- **Animation:** float

### Screen 7: Streaks
- **Visual:** Streak flame widget (KEEP — already polished)
- **Title:** "Streaks"
- **Subtitle:** "Consistency builds champions"
- **Copy:** "Work out daily to build your streak.\nThe longer your streak, the stronger your habit."

### Screen 8: Nutrition & Meals
- **Visual:** Meal tracking widget (KEEP — already has rich widget)
- **Title:** "Nutrition"
- **Subtitle:** "Fuel your progress"
- **Copy:** "Track meals, calories, and macros.\nStay on top of your nutrition goals."

### Screen 9: Hydration
- **Visual:** Water tracking widget (KEEP — already has rich widget)
- **Title:** "Hydration"
- **Subtitle:** "Stay optimally hydrated"
- **Copy:** "Track daily water intake with one tap.\nReach your hydration goals effortlessly."

### Screen 10: Free Trial CTA (REDESIGNED)
- **Visual:** Gradient crown/star icon with celebration particles
- **Title:** "Unlock Everything"
- **Subtitle:** "Start your free trial"
- **Copy:** "Get unlimited AI workouts, advanced analytics,\ncustom meal plans, and more."
- **Widget:** NEW trial CTA section:
  - Feature bullets (3-4 premium perks with checkmark icons)
  - "Start Free 3-Day Trial" gradient button (matches PremiumUpgradeView style)
  - "Cancel anytime • No commitment" reassurance text
  - "Maybe Later" secondary button that just completes the tutorial
- **Gradient:** Purple → Blue (premium feel)
- **Animation:** celebrate

---

## Implementation Plan

### Phase 1: Data Model Updates
**File:** `WelcomeTutorialView.swift`

1. Add new properties to `TutorialPage` model:
   - `useChallengeWidget: Bool` — for the challenges preview
   - `useFriendsWidget: Bool` — for the social/friends preview
   - `useTrialCTA: Bool` — for the final trial screen
   - `isLastPage: Bool` — computed, for trial screen logic

2. Update `tutorialPages` array:
   - Insert Challenges screen at index 4
   - Replace Community screen with Connect/Friends screen at index 5
   - Redesign final screen with trial CTA data

### Phase 2: New Widget Components
**File:** `WelcomeTutorialView.swift`

1. **`TutorialChallengeWidget`** — New struct
   - Challenge card with emoji, title, daily target
   - Mini 3-person leaderboard with rank badges
   - Progress bar showing daily progress
   - "Join Challenge" capsule button
   - Matches existing card styling pattern (shadows, borders, dark/light mode)

2. **`TutorialFriendsWidget`** — New struct
   - Overlapping avatar circles (using initials, like the app's friend list)
   - "Share Workout" card with exercise count preview
   - QR code icon badge
   - Activity feed hint ("Sarah completed Push Day")

3. **`TutorialTrialCTA`** — New struct
   - Premium feature checklist (4 items with gradient checkmarks)
   - Primary CTA: "Start Free 3-Day Trial" button
   - Secondary: "Maybe Later" text button
   - Trust badges: "Cancel anytime" + shield icon
   - Integrates with `StoreKitManager` for actual purchase
   - Passes `isPresented` binding to dismiss tutorial after purchase/skip

### Phase 3: Tutorial Page View Updates
**File:** `WelcomeTutorialView.swift`

1. Update `TutorialPageView.body` to handle new widget types:
   - Add `useChallengeWidget` branch in visual element ZStack
   - Add `useFriendsWidget` branch
   - Add `useTrialCTA` branch (this changes the entire page layout)

2. Update navigation for trial screen:
   - Final screen shows "Start Free 3-Day Trial" instead of "Get Started"
   - "Maybe Later" button completes tutorial without purchase
   - Successful purchase also completes tutorial

### Phase 4: Navigation & Integration Updates
**File:** `WelcomeTutorialView.swift`

1. Update page indicator count (9 → 10 pages)
2. Update skip button visibility (hide on last page — already handled)
3. Final page button changes:
   - Remove default "Get Started" button on last page
   - Trial CTA widget handles its own buttons
4. Pass `StoreKitManager` environment object for purchases

### Phase 5: ContentView Integration
**File:** `ContentView.swift`

1. Ensure `StoreKitManager` is available in environment when tutorial is shown
2. No changes needed to trigger logic (already works correctly)

---

## Design Specifications

### Color Palette by Screen
| Screen | Primary | Secondary | Gradient Direction |
|--------|---------|-----------|-------------------|
| Welcome | Blue | Cyan | Leading → Trailing |
| Auto-Generate | Purple | Pink | Leading → Trailing |
| Custom Workouts | Blue | Cyan | Leading → Trailing |
| Programs | Green | Mint | Leading → Trailing |
| **Challenges** | **Orange** | **Red** | **Leading → Trailing** |
| **Connect** | **Indigo** | **Purple** | **Leading → Trailing** |
| Streaks | Orange | Red | Leading → Trailing |
| Nutrition | Pink | Purple | Leading → Trailing |
| Hydration | Cyan | Blue | Leading → Trailing |
| **Free Trial** | **Purple** | **Blue** | **Leading → Trailing** |

### Typography (Existing Design System)
- Page title: `.system(size: 32, weight: .bold, design: .rounded)`
- Subtitle: `.system(size: 17, weight: .bold)`, `.secondary` color
- Description: `.ds_bodyRegular`, 65% opacity, 5pt line spacing
- Widget labels: `.headline`, `.caption`, `.subheadline` per context

### Animation Types
- Welcome: `.pulse`
- Auto-Generate: `.sparkle`
- Custom: `.bounce`
- Programs: `.wave`
- **Challenges: `.bounce`**
- **Connect: `.float`**
- Streaks: `.pulse`
- Nutrition: `.float`
- Hydration: `.wave`
- **Free Trial: `.celebrate`**

### Widget Styling Pattern (Must Match Existing)
All tutorial widgets follow a consistent 5-layer card pattern:
1. Depth shadow (offset y:8, blur 4) — colored tint
2. Secondary shadow (offset y:4) — black opacity
3. Main card fill — dark: `rgb(0.11, 0.11, 0.12)`, light: white
4. Inner highlight stroke — white gradient top-to-bottom
5. Accent border stroke — gradient matching page colors

---

## Technical Architecture

### Files Modified
| File | Changes |
|------|---------|
| `WelcomeTutorialView.swift` | Add 3 new widgets, update tutorial pages array, add trial CTA logic |
| `ContentView.swift` | Minimal — ensure StoreKitManager availability (likely already present) |

### Files NOT Modified
- `NewOnboardingView.swift` — Onboarding flow is separate and untouched
- `OnboardingComponents.swift` — Not used by tutorial
- `StoreKitManager.swift` — Already has purchase/trial infrastructure
- `PremiumUpgradeView.swift` — Reference only, not modified

### Dependencies
- `StoreKitManager` — For trial purchase on final screen
- Existing design tokens (`Spacing`, `Color.cardBackground`, `.ds_bodyRegular`, etc.)
- SF Symbols for all icons (no custom assets needed)

---

## Quality Checklist

- [ ] All 10 screens render correctly in dark mode
- [ ] All 10 screens render correctly in light mode
- [ ] Page indicators show correct count (10 dots)
- [ ] Skip button hidden on final (trial) screen
- [ ] Challenge widget matches app's card styling
- [ ] Friends widget matches app's card styling
- [ ] Trial CTA button triggers StoreKit purchase flow
- [ ] "Maybe Later" correctly dismisses tutorial
- [ ] Haptic feedback on all navigation actions
- [ ] Animations play correctly when switching pages
- [ ] Background gradient orbs change color per page
- [ ] Works on iPhone SE (375pt) through iPhone Pro Max (430pt)
- [ ] Tutorial still triggered correctly after onboarding completion
- [ ] Tutorial still triggered correctly after sign-back-in
- [ ] No memory leaks from animation timers

---

## Agent Roles

### Lead Designer
- Define visual hierarchy for new Challenges and Friends widgets
- Ensure new screens match existing tutorial polish level
- Color palette selection for new screens
- Widget layout proportions for different screen sizes

### Product Engineer
- Implement `TutorialChallengeWidget`, `TutorialFriendsWidget`, `TutorialTrialCTA`
- Integrate `StoreKitManager` for trial purchase on final screen
- Update `tutorialPages` array with new screen configurations
- Handle "Maybe Later" dismissal flow

### QA/Validation
- Test all 10 screens across device sizes
- Verify dark/light mode rendering
- Confirm trial purchase flow works end-to-end
- Regression test: existing onboarding flow unaffected
