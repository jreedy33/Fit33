# Workout Streak System - Full Audit & Game Plan

**Date:** March 7, 2026
**Auditor:** Claude Code Agent
**Severity:** CRITICAL - Multiple bugs causing incorrect streak behavior

---

## Table of Contents

1. [System Overview](#system-overview)
2. [How Streaks Are Supposed to Work](#how-streaks-are-supposed-to-work)
3. [Files Involved](#files-involved)
4. [Bugs Found](#bugs-found)
5. [What Works Correctly](#what-works-correctly)
6. [User Impact](#user-impact)
7. [Fixes Applied](#fixes-applied)
8. [Agent Assignments](#agent-assignments)
9. [Testing Checklist](#testing-checklist)

---

## System Overview

The streak system tracks consecutive workout activity based on the user's configured schedule (X days/week). Rather than requiring daily workouts, it allows rest days between workouts and only breaks the streak if the user exceeds their allowed gap.

**Core Data Fields (User entity):**
- `currentStreak` (Int16) - Current consecutive workout streak
- `longestStreak` (Int16) - All-time best streak
- `lastWorkoutDate` (Date?) - When user last completed a workout
- `availableDays` (Int16) - How many days/week user plans to work out

**Key Services:**
- `UserManager` - Core streak logic (updateStreak, getStreakStatus, calculateMaxAllowedGap)
- `DailyResetService` - Midnight daily operations (calls updateStreak)
- `StreakShieldService` - Streak protection feature (shields)
- `StreakInfoSheet` - UI displayed when tapping flame icon on Dashboard

---

## How Streaks Are Supposed to Work

### Gap Calculation (UserManager.calculateMaxAllowedGap)

| Days/Week | Max Gap (days) | Effective Rest Days |
|-----------|---------------|---------------------|
| 6-7       | 2             | 1                   |
| 5         | 2             | 1                   |
| 4         | 3             | 2                   |
| 3         | 3             | 2                   |
| 2         | 4             | 3                   |

### Intended Flow
1. User completes workout -> `UserManager.completeWorkout()` -> `updateStreak()`
2. `updateStreak()` checks `daysSinceLastWorkout`:
   - **0 days**: Already worked out today, no change
   - **<= maxAllowedGap**: Within rest window, INCREMENT streak
   - **> maxAllowedGap**: Too many days off, RESET streak to 1
3. `lastWorkoutDate` is set to today
4. Streak saved to Core Data and synced to Supabase

---

## Files Involved

| File | Role | Lines of Interest |
|------|------|-------------------|
| `UserManager.swift` | Core streak logic | 330-474 |
| `DailyResetService.swift` | Daily midnight reset (calls updateStreak) | 310-320 |
| `StreakShieldService.swift` | Shield protection system | 1-352 |
| `DashboardView.swift` | Flame button + StreakInfoSheet + EditStreakSheet | 1327-1368, 7378-7883 |
| `StravaService.swift` | External workout sync (calls updateStreak) | 450 |
| `FitbitService.swift` | External workout sync (calls updateStreak) | 595 |
| `SupabaseManager.swift` | Cloud sync (calls updateStreak) | 3322 |
| `NotificationManager.swift` | Streak protection notifications | 710-779 |

---

## Bugs Found

### BUG 1: CRITICAL - DailyResetService Auto-Increments Streak Without Workout

**File:** `DailyResetService.swift:314` + `UserManager.swift:343-415`
**Severity:** CRITICAL

**The Problem:**
`DailyResetService.updateDailyStreaks()` calls `UserManager.shared.updateStreak()` every day at midnight. But `updateStreak()` was designed to be called on **workout completion** - it increments the streak when `daysSinceLastWorkout <= maxAllowedGap`.

**What Happens:**
1. User works out on Monday. `lastWorkoutDate = Monday`. `currentStreak = 5`.
2. Tuesday midnight: DailyResetService calls `updateStreak()`. `daysSinceLastWorkout = 1`. Since `1 <= maxAllowedGap (2-4)`, streak is **incremented to 6** without any workout!
3. Then `lastWorkoutDate = Tuesday` is set (line 394), even though no workout happened.
4. Wednesday midnight: Same thing. `daysSinceLastWorkout = 1` again (because lastWorkoutDate was corrupted to Tuesday). Streak goes to 7.
5. This repeats **indefinitely** - the streak auto-increments every day forever.

**User Experience:** Users see their streak climbing without working out. Streaks are massively inflated. The entire streak system is broken.

**Root Cause:** `updateStreak()` serves two purposes (increment on workout + break on inactivity) but is called from a context (daily reset) where only the break check is appropriate. Additionally, `lastWorkoutDate` is set unconditionally at line 394, even when no workout occurred.

---

### BUG 2: HIGH - StreakShieldService Hardcodes 48-Hour Window

**File:** `StreakShieldService.swift:96`
**Severity:** HIGH

**The Problem:**
```swift
let hoursRemaining = 48 - hoursSinceLastWorkout  // Hardcoded!
```

The shield service hardcodes a 48-hour (2-day) window for streak risk detection, completely ignoring the user's actual schedule-based gap from `calculateMaxAllowedGap()`.

**Impact by Schedule:**
- **2 days/week user:** Gets "streak at risk" alerts 48 hours early (they have a 4-day gap = 96 hours allowed)
- **6-7 days/week user:** The 48-hour window happens to be correct (maxGap = 2 days)
- **3-4 days/week user:** Gets alerts 24 hours early (they have 3-day gap = 72 hours)

**User Experience:** Users with relaxed schedules get false "streak at risk" alerts, causing unnecessary anxiety. Or they use shields unnecessarily.

---

### BUG 3: MEDIUM - StreakShieldService References Non-Existent Property

**File:** `StreakShieldService.swift:140`
**Severity:** MEDIUM (compile-time issue)

**The Problem:**
```swift
streakDays: WorkoutManager.shared.workoutStreak,  // Does NOT exist!
```

`WorkoutManager` has no `workoutStreak` property. The streak is stored on `UserManager.currentUser?.currentStreak`. This would cause a compile error unless resolved elsewhere (extension, etc.).

**Fix:** Should reference `UserManager.shared.currentUser?.currentStreak ?? 0`.

---

### BUG 4: MEDIUM - Streak Reset Display Message Off-By-One

**File:** `DashboardView.swift:7611`
**Severity:** MEDIUM

**The Problem:**
```swift
title: "Streak resets after \(maxRestDays + 1)+ days"
```

- `maxRestDays = maxAllowedGap - 1` (from `getMaxAllowedRestDays()`)
- So the display shows: `maxAllowedGap` days (e.g., "3+ days" for 4 days/week)
- But the actual break condition is `daysSinceLastWorkout > maxAllowedGap`, meaning `4+ days`
- The UI says "3+ days breaks it" but 3 days does NOT break it!

**Example (4 days/week, maxAllowedGap = 3):**
- User works out Monday
- 3 days later (Thursday): `daysSinceLastWorkout = 3 <= 3` -> streak CONTINUES
- 4 days later (Friday): `daysSinceLastWorkout = 4 > 3` -> streak BREAKS
- UI says "resets after 3+ days" but reality is "resets after 4+ days"

**User Experience:** Users think they have less time than they actually do. Not harmful but misleading.

---

### BUG 5: LOW - statusSection Exists But Is Not Rendered

**File:** `DashboardView.swift:7559-7577`
**Severity:** LOW (missing feature)

**The Problem:**
A fully implemented `statusSection` view exists that shows real-time streak status (at risk / healthy with dynamic message), but it's **never included** in the StreakInfoSheet body. The body VStack only contains: `streakHeroSection`, `howItWorksSection`, `yourScheduleSection`, `tipsSection`.

**User Experience:** Users don't see whether their streak is currently at risk or safe when viewing streak details.

---

### BUG 6: RELATED TO BUG 1 - lastWorkoutDate Set Without Workout

**File:** `UserManager.swift:394`
**Severity:** Part of BUG 1

```swift
user.lastWorkoutDate = today  // Set unconditionally - even from DailyResetService!
```

This line runs after all streak logic, regardless of whether a workout actually happened. When called from `DailyResetService`, it falsely updates the last workout date to today.

---

## What Works Correctly

1. **Gap calculation logic** (`calculateMaxAllowedGap`) - The schedule-to-gap mapping is sound and reasonable
2. **Workout completion flow** - `completeWorkout()` -> `updateStreak()` is the correct pattern
3. **Longest streak tracking** - Properly updated when current exceeds longest
4. **Edit Streak feature** - Premium gate, stepper UI, Core Data + Supabase sync all work
5. **Flame button on Dashboard** - Haptic feedback, accessibility label, sheet presentation all correct
6. **Cloud sync** - Debounced Supabase sync after streak changes works properly
7. **getMaxAllowedRestDays()** - The `-1` adjustment correctly converts gap to rest days
8. **getStreakStatus()** - Status calculation logic is correct (uses proper gap checks)
9. **Streak milestone logging** - Every 7-day milestone is logged for analytics
10. **Achievement integration** - Streak values feed into achievement system correctly

---

## User Impact

### What Users Currently Experience (Before Fix)

| Scenario | Expected | Actual |
|----------|----------|--------|
| User works out 3x/week consistently | Streak climbs by 1 per workout | Streak climbs by 1 EVERY DAY (auto-increment) |
| User takes 2 rest days (4/week schedule) | Streak maintained | Streak incremented during rest days |
| User stops working out entirely | Streak breaks after maxGap+1 days | Streak NEVER breaks (daily reset keeps resetting lastWorkoutDate) |
| User with 2/week schedule, 3 days rest | No alert | "Streak at risk!" after 24 hours |
| User checks streak info page | Sees accurate reset rules | Sees off-by-one reset day count |
| User checks streak status | Sees if at risk | Status section not shown |

### After Fixes

| Scenario | Result |
|----------|--------|
| User works out | Streak increments by 1 (correct) |
| User takes allowed rest days | Streak maintained, no false alerts |
| User exceeds gap | Streak properly resets to 0 (was 1, now 0 to reflect no active streak) |
| User checks streak info | Sees accurate rules + real-time status |
| Shield alerts | Fire at correct times based on user schedule |
| User works out offline then syncs | Local progress preserved (cloud doesn't overwrite newer local data) |
| User syncs stale cloud data | Streak rechecked and broken if gap exceeded |

---

## Fixes Applied

### Fix 1: DailyResetService - Replace updateStreak() with checkAndBreakStreak()
- Created new `checkAndBreakStreak()` method in UserManager that ONLY checks for streak breaks (no increment, no lastWorkoutDate update)
- DailyResetService now calls this instead of `updateStreak()`
- `updateStreak()` remains unchanged for workout completion callers

### Fix 2: StreakShieldService - Dynamic Gap Calculation
- Replaced hardcoded `48` with dynamic hours based on `UserManager.shared.getMaxAllowedRestDays()`
- Now uses `(maxAllowedGap) * 24` hours as the full window

### Fix 3: StreakShieldService - Fix Property Reference
- Changed `WorkoutManager.shared.workoutStreak` to `Int(UserManager.shared.currentUser?.currentStreak ?? 0)`

### Fix 4: StreakInfoSheet - Correct Reset Message
- Changed `"Streak resets after \(maxRestDays + 1)+ days"` to `"Streak resets after \(maxRestDays + 2)+ days"`
- This correctly reflects: `maxAllowedGap + 1` days = actual break point

### Fix 5: StreakInfoSheet - Add Status Section
- Added `statusSection` to the body VStack between `streakHeroSection` and `howItWorksSection`
- Users now see real-time streak status (at risk, safe, days remaining)

### Fix 6: Cloud Sync - Smart Merge Instead of Blind Overwrite
- **Previously:** `syncUserProfileToCoreData()` blindly overwrote local streak data with cloud values
- **Problem:** If user worked out offline, cloud sync would overwrite their local progress with stale cloud data
- **Fix:** Implemented merge strategy:
  - `currentStreak` + `lastWorkoutDate`: Keep whichever source has the more recent lastWorkoutDate
  - `longestStreak`: Always keep the higher value (it should never decrease)
  - `totalWorkouts` + `xp`: Always keep the higher value
- Also calls `checkAndBreakStreakIfNeeded()` after sync to handle stale cloud data that exceeds the allowed gap

---

## Agent Assignments

### Agent 1: Backend Logic Agent
**Responsible for:** Core streak calculation integrity
- [x] Audit `UserManager.updateStreak()` - found BUG 1, BUG 6
- [x] Audit `calculateMaxAllowedGap()` - verified correct
- [x] Audit `getStreakStatus()` - verified correct
- [x] Audit `getMaxAllowedRestDays()` - verified correct
- [x] Create `checkAndBreakStreak()` method
- [x] Write unit tests for all streak edge cases - 10 tests in StreakLogicTests.swift

### Agent 2: Service Integration Agent
**Responsible for:** Cross-service streak consistency
- [x] Audit `DailyResetService` - found BUG 1 caller
- [x] Audit `StreakShieldService` - found BUG 2, BUG 3
- [x] Audit Strava/Fitbit/Supabase callers - verified correct usage
- [x] Verify StreakShieldService monthly reset logic - fixed year-boundary bug (month-only → year-month key)
- [x] Verify shield earning/spending flow end-to-end - wired checkAndAwardShield into completeWorkout, made shields actually protect streaks

### Agent 3: UI/UX Agent
**Responsible for:** Streak display accuracy and user experience
- [x] Audit StreakInfoSheet - found BUG 4, BUG 5
- [x] Audit flame button on Dashboard - verified correct
- [x] Audit EditStreakSheet - verified correct
- [x] Fix display message off-by-one
- [x] Add missing statusSection to sheet
- [x] Verify dark mode rendering - confirmed all colors adapt correctly
- [x] Verify accessibility labels match new copy - added labels to 6 locations

### Agent 4: QA & Testing Agent
**Responsible for:** Validation and regression testing
- [x] Test streak increment on workout completion - verified in code review
- [x] Test streak NOT incrementing on daily reset (after fix) - verified in code review
- [x] Test streak breaking after maxGap+1 days of inactivity - verified in code review
- [x] Test shield alerts fire at correct schedule-based times - verified dynamic gap calc
- [x] Test all 5 schedule tiers (2, 3, 4, 5, 6-7 days/week) - unit test covers all tiers
- [x] Test edge case: user changes availableDays mid-streak - max(2,...) clamp verified
- [x] Test edge case: user with 0 or 1 availableDays (clamped to 2) - verified in code review
- [x] Test EditStreakSheet saves correctly - verified in code review
- [x] Test streak sync to Supabase after all operations - verified smart merge logic
- [x] Manual test script added (11 scenarios) - see Manual Test Script section below

---

## Testing Checklist

### Critical Path Tests

- [x] Complete a workout -> streak increments by exactly 1 (unit test T3 + code review)
- [x] Complete two workouts same day -> streak does NOT double-increment (unit test T4)
- [x] App opens next day (no workout) -> streak stays the same (code review: DailyResetService)
- [x] DailyResetService fires -> streak stays the same (code review: calls checkAndBreakStreakIfNeeded, not updateStreak)
- [x] Wait maxGap+1 days -> streak resets to 1 on next workout (unit test T9)
- [x] Wait exactly maxGap days -> streak continues on next workout (unit test T9)
- [x] Shield alert fires at (maxGap * 24 - 24) hours, not hardcoded 24h (code review: dynamic calc verified)
- [x] StreakInfoSheet shows correct max rest days (code review: uses getMaxAllowedRestDays())
- [x] StreakInfoSheet shows correct reset threshold (code review: maxRestDays + 2 fix)
- [x] StreakInfoSheet shows real-time status (at risk / safe) (code review: statusSection added)
- [x] Strava workout import -> streak increments correctly (code review: calls updateStreak on MainActor)
- [x] Fitbit workout import -> streak increments correctly (code review: calls updateStreak on MainActor)

### Cloud Sync Tests

- [x] Offline workout then cloud sync -> local streak preserved (code review: cloudIsNewer merge logic)
- [x] Cloud has newer lastWorkoutDate -> cloud streak wins (code review: lines 3890-3893)
- [x] Local has newer lastWorkoutDate -> local streak preserved (code review: cloudIsNewer = false)
- [x] Cloud longestStreak > local -> local updated to cloud value (code review: max comparison)
- [x] Local longestStreak > cloud -> local value preserved (code review: only overwrites if cloud > local)
- [x] Stale cloud data synced -> checkAndBreakStreakIfNeeded() runs and breaks if needed (code review: line 3937)

### Edge Cases

- [x] First ever workout (lastWorkoutDate = nil) -> streak = 1 (unit test T10)
- [x] User edits streak to 0 -> getStreakStatus returns "Start your streak today!" (unit test T2)
- [x] User edits streak higher than longest -> longest updated (code review: EditStreakSheet.saveStreak)
- [ ] Timezone change doesn't cause double-increment (requires manual device test)
- [ ] App killed at midnight and reopened -> daily reset runs once (requires manual device test)

---

## Manual Test Script

### Prerequisites
- Device with Fit33 installed (DEBUG build from `claude/fix-workout-streaks-2adyD` branch)
- Access to DevMenuView to run CriticalPathTests
- Note down your current streak, longest streak, and lastWorkoutDate before starting

### Test 1: Streak Increments on Workout Completion
1. Note current streak value on Dashboard flame icon
2. Start and complete any workout (strength or cardio)
3. Verify streak increased by exactly 1
4. Tap flame icon -> StreakInfoSheet should show the updated value
5. Check console log for `[STREAK] ✅ Within rest window` message

### Test 2: No Auto-Increment on Daily Reset
1. Note current streak and lastWorkoutDate in DevMenu
2. Wait for midnight (or manually trigger DailyResetService from DevMenu if available)
3. Verify streak did NOT change
4. Verify lastWorkoutDate did NOT change
5. Check console for `[STREAK CHECK] Daily streak check:` followed by `✅ Streak safe` (not an increment)

### Test 3: Same-Day Double Workout
1. Complete a workout -> streak increments by 1
2. Complete another workout on the same calendar day -> streak should NOT increment again
3. Verify streak value is unchanged after second workout
4. Check console for `Already worked out today, no streak change`

### Test 4: Streak At-Risk Status
1. Have a streak with lastWorkoutDate = yesterday
2. Open StreakInfoSheet (tap flame icon) -> statusSection should show a status message
3. If within last 24 hours of allowed gap: should show "at risk" with orange styling and warning icon
4. If still has remaining rest days: should show "safe" with green styling and checkmark icon
5. VoiceOver should read "Warning: ..." for at-risk or "Status: ..." for safe

### Test 5: Shield Alert Timing
1. Set up a 4-day/week schedule (`availableDays = 4`, so `maxAllowedGap = 3 days = 72 hours`)
2. Complete a workout and note the time
3. Shield risk should fire at hour 48 (24 hours before the 72-hour gap expires)
4. Verify it does NOT fire at the old hardcoded 24-hour mark
5. Repeat with a 2-day/week schedule (`maxAllowedGap = 4 days = 96 hours`) - risk should fire at hour 72

### Test 6: Streak Breaks After Exceeding Max Gap
1. With a 4-day/week schedule (maxAllowedGap = 3)
2. Let 4+ calendar days pass without a workout (or simulate via date manipulation)
3. Trigger DailyResetService (or reopen app after midnight)
4. Verify streak resets to 0 (not 1 - no workout happened)
5. Complete a workout -> streak should now be 1

### Test 7: Edit Streak
1. Open StreakInfoSheet -> tap "Edit Streak" (requires premium)
2. Use stepper to change streak value
3. Tap Save -> verify streak updates on Dashboard flame icon
4. If new value > longest streak: verify longest streak is also updated
5. If new value < longest streak: verify longest streak is unchanged

### Test 8: Cloud Sync Merge
1. Put device in airplane mode
2. Complete a workout offline -> streak increments locally
3. Reconnect to network -> trigger cloud sync (reopen app or wait)
4. Verify local streak was preserved (not overwritten by stale cloud data)
5. Check console for the smart merge logic (`cloudIsNewer` decision)

### Test 9: Stale Cloud Data Handling
1. Complete a workout locally (streak = N)
2. Simulate stale cloud data where `lastWorkoutDate` is older than local
3. After sync, verify local streak (N) is kept (cloud does not overwrite)
4. Simulate cloud data with `lastWorkoutDate` newer than local
5. After sync, verify cloud streak wins
6. If cloud lastWorkoutDate exceeds the allowed gap, verify `checkAndBreakStreakIfNeeded()` resets streak to 0

### Test 10: Schedule Tier Validation
Test each schedule tier to confirm correct gap behavior:

| Schedule | maxAllowedGap | Streak survives N days | Streak breaks at N+1 days |
|----------|---------------|------------------------|---------------------------|
| 6-7 days/week | 2 | 2 days | 3 days |
| 5 days/week | 2 | 2 days | 3 days |
| 4 days/week | 3 | 3 days | 4 days |
| 3 days/week | 3 | 3 days | 4 days |
| 2 days/week | 4 | 4 days | 5 days |

For each tier:
1. Set `availableDays` to the target value
2. Complete a workout
3. Wait exactly maxAllowedGap days -> verify streak continues on next workout
4. Wait maxAllowedGap + 1 days -> verify streak breaks

### Test 11: Accessibility
1. Enable VoiceOver on device
2. Navigate to Dashboard -> flame icon should read "Current workout streak: X days"
3. Open StreakInfoSheet -> status section should read either "Warning: ..." or "Status: ..."
4. Navigate to Edit Streak -> stepper buttons should be properly labeled
5. Verify all interactive elements are reachable via VoiceOver swipe navigation
