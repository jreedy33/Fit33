# Onboarding Flow — Agent Handoff Context

> **Last updated**: March 24, 2026
> **Status**: Stack overflow crash fixed — `currentStepContent` now uses `AnyView` type erasure (Group splitting alone was insufficient)

---

## Architecture

`NewOnboardingView` is a 5,485-line SwiftUI view split across 8 files:

| File | Lines | Purpose |
|------|-------|---------|
| `NewOnboardingView.swift` | 744 | Main struct — all `@State`/`@FocusState` properties + `body` |
| `NewOnboardingView+Chrome.swift` | 353 | Header, button bar, progress indicator, background, **step content ZStack** |
| `NewOnboardingView+Steps.swift` | 859 | Content views for each onboarding step (username, basics, body, goals, experience, strength, location, equipment, schedule, photo, contacts, friends) |
| `NewOnboardingView+Auth.swift` | 1216 | Auth handling — email/password, OAuth (Apple/Google), auth form content |
| `NewOnboardingView+Verification.swift` | 837 | Phone verification + email verification fallback |
| `NewOnboardingView+Navigation.swift` | 213 | Step navigation, checkpoint persistence, forward/back logic |
| `NewOnboardingView+Completion.swift` | 667 | Account creation, Supabase upsert, onboarding completion |
| `NewOnboardingView+Social.swift` | 596 | Social auth helpers, Apple/Google sign-in |
| `OnboardingCardViews.swift` | ~690 | Reusable card components (GenderButton, OnboardingGoalCard, OnboardingExperienceCard, StrengthLevelCard, etc.) |

### Step Flow (OnboardingStep enum)

```
auth(0) → username(1) → phoneNumber(2) → basics(3) → body(4) → goal(5) →
experience(6) → strengthAssessment(7) → workoutLocation(8) → equipment(9) →
limitations(10) → schedule(11) → profilePhoto(12) → contacts(13) →
addFriends(14) → confirmation(15) → complete(16)
```

### Body Structure (Critical)

The `body` in `NewOnboardingView.swift` has 4 top-level branches:

1. **Welcome screen**: `currentStep == .auth && !hasStartedAuth` → shows `authStep` (big buttons, no keyboard)
2. **Complete screen**: `currentStep == .complete` → celebration view
3. **Main flow**: `currentStep != .limitations && currentStep != .confirmation` → unified layout with header + content + floating button bar. This branch handles auth (when `hasStartedAuth`), phone, username, basics, body, goals, experience, strength, location, equipment, schedule, photo, contacts, and friends.
4. **Limitations**: separate layout with bounded scroll + button bar
5. **Confirmation**: separate layout with review rows + button bar

The main flow (branch 3) was **intentionally unified** so that `@FocusState` can transfer keyboard focus seamlessly between text-input steps (e.g., password → username) without the keyboard dismissing/reappearing ("bobbing").

### Step Content Extraction (Critical Fix)

The step views use a **hybrid** approach in `currentStepContent` (in `NewOnboardingView+Chrome.swift`):

- **Text-input steps** (auth, phone, username, basics, body) use simultaneous `if` conditionals inside a ZStack so all text fields coexist and `@FocusState` can transfer keyboard focus seamlessly between them.
- **Non-text steps** (goal, experience, strength, etc.) use an `AnyView` switch via `nonTextStepContent`.
- The entire ZStack is wrapped in an outer `AnyView` to prevent the stack overflow.

```swift
var currentStepContent: AnyView {
    return AnyView(
        ZStack {
            // Text-input steps: simultaneous conditionals for @FocusState
            if currentStep == .auth && hasStartedAuth { authScrollView }
            if currentStep == .phoneNumber { phoneNumberStepContent }
            if currentStep == .username { usernameStepContent }
            if currentStep == .basics { basicsStepContent }
            if currentStep == .body { bodyStepContent }
            nonTextStepContent  // AnyView switch for non-text steps
        }
    )
}
```

**Critical constraints**:
- A pure `AnyView` switch (one case per step) prevents keyboard bounce but breaks `@FocusState` transfer — the old text field is destroyed before the new one exists.
- A pure `@ViewBuilder` with all 14 conditional views causes `EXC_BAD_ACCESS (code=2)` stack overflow from 80+ frames of generic type nesting.
- The hybrid approach (5 conditionals + 1 AnyView = 6 items) stays well within the stack limit while preserving focus transfer.
- `handleAuth()` must NOT set `hasStartedAuth = false` — that would remove the auth form from the ZStack before the username form appears, breaking focus transfer. The `onChange(of: currentStep)` handler manages `hasStartedAuth` when navigating back.

---

## Social System (v1.32+)

- **ProfileUser** (`FriendProfileView.swift`): Universal model for any user profile. Inits from `Friend`, `UserSearchResult`, `SuggestedFriend`, `LeagueEntry`, `CommunityLeaderboardEntry`, `FriendActivity`. Use `ProfileUser` for all profile sheet bindings (`@State private var showingProfile: ProfileUser?`).
- **FriendProfileView**: Accepts `ProfileUser`. Friends see full profile (stats, challenges, create workout, shared history, unfriend/block). Non-friends see compact card (photo, name, goal/level, add friend/pending/accept, block). Wired up in: `FriendsTabView`, `FriendsListView`, `FriendActivityFeedView`, `WeeklyLeagueViews`, `CommunityChallengeViews`.
- **Daily Goals**: `DailyQuestService.defaultGoals()` returns fallback goals (Add Friend, Start Workout, Explore Program). Every code path that could leave `quests` empty now falls back to these. The generic placeholder view was deleted from `DailyQuestViews.swift`.

---

## Recent Changes & Pending Issues

### Applied (needs device testing)

1. **Stack overflow + keyboard bounce fix**: `currentStepContent` uses hybrid approach — text-input steps as simultaneous `if` conditionals (for `@FocusState` transfer), non-text steps via `AnyView` switch, outer `AnyView` wrapper (for stack overflow prevention). `handleAuth()` no longer resets `hasStartedAuth`.
2. **Skip phone verification**: Added "Skip for now" button in `NewOnboardingView+Verification.swift` — calls `goToNextStep()` (account creation is deferred to confirmation step)
3. **Height auto-advance fix**: In `NewOnboardingView+Steps.swift`, the `onChange(of: heightFeetInchesDigits)` now waits 1.0s for 2-digit input and 0.3s for 3-digit. No auto-advance for 1 digit.
4. **3D gradient cards**: Goal and Experience steps now use `OnboardingGoalCard` and `OnboardingExperienceCard` from `OnboardingCardViews.swift`
5. **Removed "Other" from injuries**: `LimitationsService.swift` → `commonAreas` no longer includes `.other`
6. **Supabase security**: `supabase/20260324_security_fixes.sql` — RLS enabled on `group_challenge_members` + `achievements`, 19 views converted from SECURITY DEFINER to SECURITY INVOKER

### Completed (March 24, 2026)

- **Strength step**: Now uses `StrengthLevelCard` from `OnboardingCardViews.swift` (was inline)
- **Location step**: Now uses `.onboardingCardStyle` modifier with per-location accent colors
- **Schedule step**: Now uses `DaySelectorButtonLarge` component
- **Limitations step**: Both area rows and accommodation options now use `.onboardingCardStyle` modifier

### Known AttributeGraph Cycle Warnings

The console shows `AttributeGraph: cycle detected through attribute XXXXX` warnings. These are SwiftUI internal warnings that may appear even with valid code. The critical issue was the stack overflow (EXC_BAD_ACCESS code=2), not the cycle warnings themselves. The cycle warnings may persist but are usually non-fatal — the extraction fix addresses the stack depth that was causing the crash.

If cycles persist after the extraction fix, investigate:
- `let keyboardUp = keyboardObserver.keyboardHeight > 0` inside the conditional body (line ~351) — creates a dependency that re-evaluates the entire branch on every keyboard height change
- The `.animation(.easeInOut(duration: 0.25), value: currentStep)` on the content + `.animation(.easeOut(duration: 0.25), value: keyboardObserver.keyboardHeight)` on the button bar — these can conflict
- `onboardingSharedHeader(compact: keyboardUp)` — the `compact` parameter is **declared but never used** in the implementation. Consider removing it.

---

## Key Conventions

### Design System
- Font tokens: `.ds_heading1`, `.ds_heading2`, `.ds_heading3`, `.ds_labelLarge`, `.ds_labelMedium`, `.ds_labelSmall`, `.ds_body`, `.ds_bodySmall`, `.ds_caption`
- Spacing: `Spacing.xs`, `.sm`, `.md`, `.lg`, `.xl`, `.xxl`
- Corner radii: `CornerRadius.sm`, `.md`, `.lg`, `.xl`
- Card backgrounds: `Color.cardBackground`
- **Never** hardcode `.font(.system(size:))` or define local `cardBackground` properties

### Onboarding Card Components (in OnboardingCardViews.swift)
- `OnboardingGoalCard(title:emoji:subtitle:isSelected:action:)` — 2-column grid
- `OnboardingExperienceCard(title:emoji:subtitle:isSelected:action:)` — full-width stacked
- `StrengthLevelCard(level:isSelected:action:)` — strength assessment
- `GenderButton(title:isSelected:action:)` — gender selection
- `.onboardingCardStyle(isSelected:color:)` — generic modifier for any selectable card
- All use the same 3D gradient visual style with floating shadows

### Logging
- **Always** `AppLogger.info/debug/warning/error(message, category:)` — **never** `print()`
- Categories: `.network`, `.data`, `.workout`, `.social`, `.nutrition`, `.health`, `.ui`, `.performance`, `.auth`, `.general`

### SwiftUI Patterns
- `@FocusState var focusedField: FocusedField?` — drives keyboard focus across all text fields
- `@StateObject var keyboardObserver = KeyboardObserver()` — publishes keyboard height
- Step transitions use `.transition(.opacity)` + `.animation(.easeInOut(duration: 0.25), value: currentStep)`
- All stored properties live in the main `NewOnboardingView` struct; extensions only add computed properties and methods

### Supabase Security (Mandatory)
- Every new table: `ENABLE ROW LEVEL SECURITY` + policies scoped to `user_id = auth.uid()`
- Every new view: `security_invoker = on` — **never** SECURITY DEFINER
- SECURITY DEFINER RPCs: use `auth.uid()` internally, never accept `user_id` as parameter

---

## Debugging Tips

1. **Stack overflow in body**: If you see `EXC_BAD_ACCESS (code=2)` in `body.getter` or `currentStepContent.getter`, the SwiftUI generic type is too deeply nested. Use the hybrid approach in `currentStepContent`: text-input steps as simultaneous `if` conditionals (max 5), non-text steps via `AnyView` switch, outer `AnyView` wrapper. Do NOT put all 14 steps as conditionals — that exceeds the stack. Do NOT use a pure `AnyView` switch — that breaks `@FocusState` keyboard transfer.
2. **Keyboard bobbing**: Auth, phone, username, basics, and body steps MUST be simultaneous `if` conditionals in the same ZStack (inside `currentStepContent`). If they use an `AnyView` switch, `@FocusState` can't transfer focus and the keyboard dismisses/reappears. Also: `handleAuth()` must NOT set `hasStartedAuth = false` — that removes the auth form before the username form appears.
3. **Auto-advance**: Height and weight fields use `onChange(of:)` with delayed `Task` to auto-advance. Changes to validation computed properties (`isHeightValid`, `isWeightValid`) should NOT directly trigger auto-advance — only digit count changes should.
4. **Account creation**: Happens in the **confirmation** step (`handleConfirmation()` in `NewOnboardingView+Completion.swift`), NOT during phone verification or any earlier step. Skipping phone verification just calls `goToNextStep()`.
5. **Social auth**: OAuth users (Apple/Google) skip auth form entirely. The `OAuthNewUserNeedsOnboarding` notification triggers `handleOAuthUserOnboarding()` which pre-fills name and navigates to username step.
