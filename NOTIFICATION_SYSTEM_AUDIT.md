# Fit33 Notification System Audit & Remediation Plan

**Date:** March 21, 2026
**Scope:** Full audit of push/local notification logic, preferences UI, Supabase backend, and user experience
**Status:** Plan ready for implementation

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Critical Bugs Found](#critical-bugs-found)
3. [Missing Notification Instances](#missing-notification-instances)
4. [Notification Settings UI Issues](#notification-settings-ui-issues)
5. [Server-Side (Supabase) Issues](#server-side-supabase-issues)
6. [Anti-Spam & Smart Delivery Recommendations](#anti-spam--smart-delivery-recommendations)
7. [Remediation Plan](#remediation-plan)
8. [Roles & Responsibilities](#roles--responsibilities)
9. [Files Affected](#files-affected)
10. [Testing Checklist](#testing-checklist)

---

## Executive Summary

The Fit33 notification system has a solid architecture with 25 notification types across 5 categories, a Supabase push notification queue, APNs integration, quiet hours, and granular user preferences. However, **4 critical bugs** are causing false-positive notifications (e.g., "you haven't worked out today" when the user has, and "we miss you" while the user is actively in the app). Additionally, **3 notification types are missing from the settings UI**, several notification instances are unimplemented, and server-side push notifications bypass user preferences entirely.

---

## Critical Bugs Found

### BUG 1: "You Haven't Worked Out Today" When User HAS Worked Out

**Severity:** HIGH — Users report this as the #1 annoyance
**File:** `NotificationManager.swift` — `scheduleAllNotifications()` and `scheduleStreakProtection()`

**Root Cause:**
`scheduleAllNotifications()` removes ALL pending notifications and re-schedules everything, including streak protection — but it **never checks if the user already worked out today**. This means:

1. User completes workout → `workoutCompleted()` cancels streak protection notification
2. User changes any notification setting (or master toggle) → `scheduleAllNotifications()` fires
3. Streak protection is re-scheduled at 8 PM **even though user already worked out**
4. At 8 PM user gets "You haven't worked out today" — false positive

The same issue affects the daily workout reminder.

**Fix:**
In `scheduleAllNotifications()`, check `UserDefaults "last_workout_date"` before scheduling streak protection or daily workout reminder. Also add the same guard inside `scheduleStreakProtection()` itself:
```swift
// In scheduleAllNotifications():
let workedOutToday: Bool = {
    if let lastWorkout = UserDefaults.standard.object(forKey: "last_workout_date") as? Date {
        return Calendar.current.isDateInToday(lastWorkout)
    }
    return false
}()

if isNotificationEnabled(.dailyWorkoutReminder) && !workedOutToday {
    scheduleWorkoutReminder()
}
if isNotificationEnabled(.streakProtection) && !workedOutToday {
    scheduleStreakProtection()
}
```

**User Impact:** Eliminates the most-reported false positive notification.

---

### BUG 2: "We Miss You" While User is Actively In The App

**Severity:** HIGH — Confusing and breaks trust in the app
**Files:** `NotificationManager.swift` — `performSmartCheck()`, `Fit33App.swift` — `checkForComebackReminder()`

**Root Cause — Two issues:**

**Issue A: Duplicate comeback logic with different dedup rules**
- `performSmartCheck()` (line ~1145 in NotificationManager) sends a comeback reminder with **NO deduplication** — fires every single foreground event
- `checkForComebackReminder()` (line ~723 in Fit33App) has proper daily dedup via `last_comeback_reminder` UserDefaults key
- Both run on app foreground, creating **duplicate "we miss you" notifications**

**Issue B: Immediate notifications show in-app banners**
- `sendComebackReminder()` calls `sendImmediateNotification()` which uses `trigger: nil` (fires immediately)
- The `willPresent` delegate returns `[.banner, .sound]`, so the notification **shows as a banner even while the user is actively using the app**
- This is why users see "we miss you" while they're literally inside Fit33

**Fix:**
1. Remove the comeback reminder logic from `performSmartCheck()` entirely — let `Fit33App.checkForComebackReminder()` handle it (it already has proper dedup)
2. Add a comment explaining the separation of concerns
3. Consider suppressing comeback reminders in `willPresent` when the app is in foreground (or don't show them as banners)

```swift
// In performSmartCheck() — REMOVE this block:
// if let lastWorkout = UserDefaults.standard.object(forKey: "last_workout_date") as? Date,
//    !Calendar.current.isDateInToday(lastWorkout) {
//     let daysSince = ...
//     if daysSince >= 3 && daysSince <= 7 {
//         sendComebackReminder(daysAway: daysSince)
//     }
// }
// Replace with a comment noting Fit33App handles this with dedup
```

**User Impact:** Eliminates the most confusing false positive. Users will no longer be told "we miss you" while actively using the app.

---

### BUG 3: Three Notification Types Missing From Settings UI

**Severity:** MEDIUM — Users cannot control these notification types
**File:** `NotificationManager.swift` — `NotificationCategory.social.notifications`

**Root Cause:**
The `NotificationCategory.social` case returns:
```swift
[.sharedWorkout, .friendRequest, .challengeInvite, .groupChallengeInvite, .challengeUpdate,
 .challengeReaction, .communityFriendJoined, .privateChallengeInvite, .privateChallengeUpdate,
 .privateChallengeMessage]
```

**Missing from the list:**
- `.contactJoined` — Users can't toggle "Contact Joined" notifications
- `.challengeProgress` — Users can't toggle challenge progress notifications
- `.challengeCancelled` — Users can't toggle challenge cancelled notifications

These types exist in the `NotificationType` enum with `defaultEnabled: true`, but are **invisible in the settings UI** and **always enabled with no user control**.

**Fix:**
Update the social category to include all 3 missing types:
```swift
case .social:
    return [.sharedWorkout, .friendRequest, .contactJoined, .challengeInvite,
            .groupChallengeInvite, .challengeUpdate, .challengeProgress,
            .challengeReaction, .challengeCancelled, .communityFriendJoined,
            .privateChallengeInvite, .privateChallengeUpdate, .privateChallengeMessage]
```

**User Impact:** Users gain control over 3 additional notification types they previously couldn't manage.

---

### BUG 4: Morning Motivation Toggle Doesn't Cancel Pending Notification

**Severity:** LOW — Notification continues until next full reschedule
**File:** `NotificationManager.swift` — `toggleNotification()`

**Root Cause:**
When user toggles a notification type, `toggleNotification()` calls a reschedule function for that type. But `morningMotivation` has **no reschedule case** in the switch statement:

```swift
switch type {
case .dailyWorkoutReminder: rescheduleWorkoutReminder()
case .nutritionReminder: rescheduleNutritionReminders()
case .streakProtection: rescheduleStreakProtection()
default: break  // ← morningMotivation falls through here!
}
```

**Fix:**
Add a `rescheduleMorningMotivation()` method and case:
```swift
case .morningMotivation: rescheduleMorningMotivation()
```

**User Impact:** Toggling morning motivation off will take effect immediately instead of next app restart.

---

## Missing Notification Instances

These are notification types that exist in the system but are **never triggered** or lack scheduling logic:

| Notification Type | Status | Issue | Recommendation |
|---|---|---|---|
| `weeklyProgress` | **Not scheduled** | Enum exists, default ON, but no scheduling logic anywhere | Add a weekly scheduled notification (e.g., Sunday 6 PM) summarizing workout count, streak, and progress |
| `waterReminder` | **Not scheduled** | Enum exists, default OFF, but no scheduling logic | Add configurable reminders (e.g., every 2 hours from 8 AM–8 PM) when opted in |
| `weightReminder` | **Not scheduled** | Enum exists, default OFF, but no scheduling logic | Add a daily morning reminder (e.g., 7:30 AM) when opted in |
| `workoutComplete` | **Never sent** | Enum exists, `workoutCompleted()` cancels reminders but never sends a celebration notification | Add a "Great workout!" notification in `workoutCompleted()` |
| `friendRequestAccepted` | **Missing type** | Uses `.friendRequest` type for both receiving and acceptance — no separate toggle | Consider adding a distinct type, or document that `.friendRequest` covers both |
| `challengeDeclined` | **Missing type** | Server queues `challenge_declined` notifications but there's no matching enum case | Add handling in foreground delegate (already covered by `challenge_accepted, challenge_declined` case) — acceptable as-is |
| Inactivity escalation | **Missing** | Comeback reminder only fires for 3–7 days away. After 7 days, user gets NO re-engagement | Add a 14-day and 30-day "long absence" notification with softer tone |
| Rest day encouragement | **Missing** | No positive notification on intentional rest days | Consider a "Rest day? Recovery is gains too!" notification if user has a 3+ day streak and hasn't worked out by evening |

---

## Notification Settings UI Issues

### Current State (NotificationSettingsView.swift)
The settings UI is well-designed with expandable categories, master toggle, quiet hours, and time picker. Issues:

| Issue | Severity | Fix |
|---|---|---|
| 3 notification types missing from category lists (see Bug 3) | MEDIUM | Add to `NotificationCategory.social.notifications` |
| No visual feedback when toggling a notification type | LOW | Consider a brief haptic or toast |
| Quiet hours don't affect server-side push notifications | MEDIUM | See Server-Side Issues below |
| No "Reset to Defaults" button | LOW | Add a button to reset all toggles to `defaultEnabled` values |
| Category shows "X of Y enabled" but Y count is wrong due to missing types | LOW | Fixed by adding missing types to category |

### Default Settings Audit

**Correctly defaulted ON (21 types):**
All high-engagement notifications (workout, social, achievements, motivation) are ON by default. This is correct.

**Correctly defaulted OFF (4 types):**
- `proteinGoal` — Can feel nagging, good as opt-in
- `stepsGoal` — Better handled by Apple Health, good as opt-in
- `waterReminder` — Very frequent if enabled, good as opt-in
- `weightReminder` — Daily weight check, good as opt-in

**Recommendation:** No changes to defaults needed. The current split is appropriate.

---

## Server-Side (Supabase) Issues

### Issue 1: Push Notifications Don't Respect User Preferences

**Severity:** MEDIUM
**Files:** `supabase/functions/send-push-notification/index.ts`, all RPC functions that queue notifications

**Problem:**
When the server queues a push notification (e.g., `send_friend_request()` inserts into `push_notification_queue`), it **never checks if the recipient has that notification type enabled**. User preferences are stored only in `UserDefaults` on the device — the server has no access to them.

This means:
- User disables "Friend Requests" in settings
- Someone sends them a friend request
- Server queues and sends the push notification anyway
- User receives a notification they explicitly disabled

**Recommended Fix (two options):**

**Option A: Server-side preference table (recommended)**
1. Create a `user_notification_preferences` table in Supabase
2. Sync UserDefaults preferences to this table on change
3. Check preferences before inserting into `push_notification_queue`
4. Migration SQL:
```sql
CREATE TABLE user_notification_preferences (
    user_id UUID PRIMARY KEY REFERENCES user_profiles(id) ON DELETE CASCADE,
    enabled_types TEXT[] NOT NULL DEFAULT '{}',
    quiet_hours_enabled BOOLEAN NOT NULL DEFAULT false,
    quiet_hours_start TIME,
    quiet_hours_end TIME,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

**Option B: Client-side filtering (simpler, interim)**
- In `willPresent` delegate, check if the notification type is enabled before showing
- Already partially done for local notifications but NOT for push notifications
- Drawback: push notification still wakes the device/increments badge

### Issue 2: No Quiet Hours Enforcement for Push Notifications

**Severity:** LOW-MEDIUM
**Problem:** Quiet hours only apply to local immediate notifications (`sendImmediateNotification()` checks `isInQuietHours()`). Server-sent push notifications arrive regardless of quiet hours.

**Fix:** Include quiet hours in the server-side preference table (Option A above) and check before sending in the edge function.

### Issue 3: Badge Count Includes Items User May Have Disabled

**Severity:** LOW
**Problem:** `computeBadgeCount()` in the edge function counts pending friend requests, challenge invites, etc. regardless of whether the user has those notification types enabled.

**Fix:** If implementing Option A above, filter badge count by enabled types.

---

## Anti-Spam & Smart Delivery Recommendations

### Current Anti-Spam Measures (Good)
- Challenge progress: 5-minute debounce per opponent per challenge
- Contact joined: Deduplication with friend request notifications
- Comeback reminder (Fit33App): Once per day max
- Quiet hours: Local notifications suppressed during sleep
- Friend request: SQL-level duplicate prevention

### Recommended Improvements

| Improvement | Priority | Description |
|---|---|---|
| **Daily notification cap** | HIGH | Limit total notifications per user to ~8/day. After cap, only show critical ones (friend request, challenge invite). Prevents notification fatigue on active days. |
| **Comeback reminder dedup fix** | HIGH | Remove duplicate comeback logic from `performSmartCheck()` (Bug 2). |
| **Cooldown for achievement notifications** | MEDIUM | If user hits PR, level up, AND streak milestone in same workout, batch into one notification instead of 3 separate ones. Add a 30-second batch window. |
| **Smart workout reminder cancellation** | MEDIUM | If user opened the app and browsed workouts but didn't start one, don't send "you haven't worked out" — they're clearly aware. Track `last_app_open_date`. |
| **Graduated re-engagement** | MEDIUM | Current comeback reminder is 3–7 days only. Add: 14 days ("It's been a while!"), 30 days ("Ready for a fresh start?"), then stop. Don't nag after 30 days — respect the user's choice. |
| **Thread grouping** | LOW | Group challenge notifications by challenge using `threadIdentifier`. Already done for private challenge messages — extend to regular challenges. |
| **Notification summary** | LOW | For iOS 15+, register for scheduled notification summary so non-urgent notifications don't interrupt. |

---

## Remediation Plan

### Phase 1: Critical Bug Fixes (Immediate — 1-2 days)

| # | Task | Owner | File(s) | Priority |
|---|---|---|---|---|
| 1.1 | Fix streak protection false positive (check `last_workout_date` before scheduling) | iOS Dev | `NotificationManager.swift` | P0 |
| 1.2 | Fix comeback reminder duplication (remove from `performSmartCheck()`, keep in `Fit33App`) | iOS Dev | `NotificationManager.swift` | P0 |
| 1.3 | Add 3 missing types to `NotificationCategory.social.notifications` | iOS Dev | `NotificationManager.swift` | P0 |
| 1.4 | Add `rescheduleMorningMotivation()` handler in `toggleNotification()` | iOS Dev | `NotificationManager.swift` | P1 |

### Phase 2: Missing Notifications (3-5 days)

| # | Task | Owner | File(s) | Priority |
|---|---|---|---|---|
| 2.1 | Implement `weeklyProgress` scheduled notification (Sunday 6 PM) | iOS Dev | `NotificationManager.swift` | P1 |
| 2.2 | Add workout completion celebration notification | iOS Dev | `NotificationManager.swift` | P1 |
| 2.3 | Add graduated re-engagement (14-day, 30-day comeback messages) | iOS Dev | `NotificationManager.swift`, `Fit33App.swift` | P2 |
| 2.4 | Implement `waterReminder` scheduling (when opted in) | iOS Dev | `NotificationManager.swift` | P2 |
| 2.5 | Implement `weightReminder` scheduling (when opted in) | iOS Dev | `NotificationManager.swift` | P2 |

### Phase 3: Server-Side Preference Sync (5-7 days)

| # | Task | Owner | File(s) | Priority |
|---|---|---|---|---|
| 3.1 | Create `user_notification_preferences` table migration | Supabase/Backend | New SQL migration | P1 |
| 3.2 | Add preference sync from iOS → Supabase on toggle change | iOS Dev | `NotificationManager.swift` | P1 |
| 3.3 | Update `send-push-notification` edge function to check preferences | Supabase/Backend | `send-push-notification/index.ts` | P1 |
| 3.4 | Add quiet hours enforcement for push notifications | Supabase/Backend | `send-push-notification/index.ts` | P2 |
| 3.5 | Filter badge count by enabled notification types | Supabase/Backend | `send-push-notification/index.ts` | P2 |

### Phase 4: Anti-Spam & Polish (Ongoing)

| # | Task | Owner | File(s) | Priority |
|---|---|---|---|---|
| 4.1 | Add daily notification cap (8/day) | iOS Dev + Backend | Both | P2 |
| 4.2 | Batch concurrent achievement notifications (30s window) | iOS Dev | `NotificationManager.swift` | P2 |
| 4.3 | Add thread grouping for regular challenge notifications | iOS Dev | `NotificationManager.swift` | P3 |
| 4.4 | Add "Reset to Defaults" button in settings UI | iOS Dev | `NotificationSettingsView.swift` | P3 |
| 4.5 | Register for iOS notification summary (non-urgent types) | iOS Dev | `NotificationManager.swift` | P3 |

---

## Roles & Responsibilities

| Role | Responsibility | Key Files |
|---|---|---|
| **iOS Developer** | All client-side notification logic, scheduling, preferences UI, deep linking | `NotificationManager.swift`, `NotificationSettingsView.swift`, `PushNotificationService.swift`, `Fit33App.swift` |
| **Supabase/Backend Developer** | Push notification queue processing, RPC functions, edge functions, migrations | `send-push-notification/index.ts`, `notify-contacts-user-joined/index.ts`, all `.sql` files |
| **QA/Testing** | Verify all notification flows end-to-end, test quiet hours, test preference toggles | All files |
| **Product/Design** | Approve notification copy, frequency caps, and new notification types | N/A |

### Cross-Team Coordination Points
- **iOS ↔ Supabase:** Preference sync protocol (Phase 3) — agree on table schema and sync frequency
- **iOS ↔ Supabase:** Quiet hours enforcement — decide if server-side or client-side filtering
- **iOS ↔ Product:** New notification copy for weekly progress, graduated re-engagement, rest day encouragement
- **Supabase ↔ QA:** Verify push notification queue processing respects new preference checks

---

## Files Affected

### iOS (Client)

| File | Changes Needed |
|---|---|
| `Fit33/NotificationManager.swift` | Bug fixes 1-4, missing notification scheduling, preference sync, anti-spam |
| `Fit33/NotificationSettingsView.swift` | "Reset to Defaults" button (Phase 4) |
| `Fit33/PushNotificationService.swift` | No changes needed (working correctly) |
| `Fit33/Fit33App.swift` | Graduated re-engagement logic (Phase 2) |

### Supabase (Backend)

| File | Changes Needed |
|---|---|
| `supabase/functions/send-push-notification/index.ts` | Preference check before sending, quiet hours, badge filtering |
| `supabase/functions/notify-contacts-user-joined/index.ts` | No changes needed (working correctly) |
| New: `supabase/migrations/YYYYMMDD_user_notification_preferences.sql` | New table for synced preferences |
| `supabase/challenge_rpc_functions.sql` | Consider preference check before queueing (optional) |
| `supabase/friend_request_notifications.sql` | Consider preference check before queueing (optional) |

---

## Testing Checklist

### Phase 1 Bug Fix Verification

- [ ] Complete a workout → verify streak protection does NOT fire at 8 PM
- [ ] Complete a workout → change a notification setting → verify streak protection still does NOT fire
- [ ] Open app after 3+ days away → verify comeback reminder fires only ONCE (not on every foreground)
- [ ] Open app while comeback conditions met → verify NO in-app "we miss you" banner
- [ ] Open Notification Settings → expand Social category → verify `Contact Joined`, `Challenge Progress`, and `Challenge Cancelled` are all visible and toggleable
- [ ] Toggle Morning Motivation OFF → verify 8 AM notification does NOT fire next day
- [ ] Toggle Morning Motivation ON → verify it schedules correctly

### General Notification Flow Testing

- [ ] Fresh install → verify all 21 default-ON types are enabled
- [ ] Disable master toggle → verify ALL pending notifications cleared
- [ ] Re-enable master toggle → verify notifications re-schedule correctly
- [ ] Set quiet hours 10 PM - 7 AM → verify no local notifications during that window
- [ ] Send a friend request to test user → verify push notification arrives
- [ ] Create a challenge → verify invite notification arrives for opponent
- [ ] Accept a challenge → verify acceptance notification arrives for creator
- [ ] Tap each notification type → verify deep link goes to correct screen
- [ ] Workout reminder with "Snooze 1 Hour" action → verify re-fires 1 hour later
- [ ] Verify badge count matches actual pending items

### Regression Testing

- [ ] App launch → no crashes in notification initialization
- [ ] Push notification received while in foreground → data refreshes correctly
- [ ] Push notification tapped from lock screen → correct deep link
- [ ] Logout → verify device token removed from Supabase
- [ ] Login on new device → verify new token saved
- [ ] Account deletion → verify all notification data cascade-deleted

---

## Summary of Changes by Priority

| Priority | Count | Description |
|---|---|---|
| **P0 (Critical)** | 3 | Streak protection false positive, comeback reminder duplication, missing settings types |
| **P1 (High)** | 5 | Morning motivation toggle, weekly progress scheduling, workout celebration, preference sync table + edge function |
| **P2 (Medium)** | 6 | Graduated re-engagement, water/weight reminders, daily cap, quiet hours for push, badge filtering, achievement batching |
| **P3 (Low)** | 3 | Thread grouping, reset button, iOS notification summary |

**Total estimated effort:** ~3-4 weeks across iOS and Backend teams

---

*This document should be reviewed by iOS, Backend, and QA teams before implementation begins. Phase 1 (critical bug fixes) should be prioritized for the next release.*
