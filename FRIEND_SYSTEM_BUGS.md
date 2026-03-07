# Fit33 Friend System - Bug Report & Quick Win Game Plans

**Date:** March 7, 2026
**Scope:** All bugs discovered during frontend audit of ~10,500 LOC across 17 files
**Platforms:** iOS (Swift/SwiftUI) + Web (Next.js/React) + Supabase Edge Functions

---

## Table of Contents

1. [Critical Bugs](#critical-bugs)
2. [High Severity Bugs](#high-severity-bugs)
3. [Medium Severity Bugs](#medium-severity-bugs)
4. [Low Severity Bugs](#low-severity-bugs)
5. [Quick Win #1: Fix Search Filter Logic](#quick-win-1-fix-search-filter-logic)
6. [Quick Win #2: Fix Push Notification Badge Counts](#quick-win-2-fix-push-notification-badge-counts)
7. [Quick Win #3: Add User-Facing Error Feedback](#quick-win-3-add-user-facing-error-feedback)

---

## Critical Bugs

### BUG-001: Push Notification Badge References Non-Existent Table

| Field | Detail |
|-------|--------|
| **Severity** | CRITICAL |
| **File** | `supabase/functions/send-push-notification/index.ts:375` |
| **Impact** | Badge count is always 0 for friend requests. Users never see pending request badges on the app icon. |

**Context:** The edge function that computes the badge number for push notifications queries a table called `friend_requests` with a column `to_user_id`. Neither exists — the actual table is `friendships` and the column is `addressee_id`.

**Code (broken):**
```typescript
// Line 375-378
const { count: friendRequests } = await supabase
  .from('friend_requests')          // ❌ Table doesn't exist
  .select('*', { count: 'exact', head: true })
  .eq('to_user_id', userId)         // ❌ Column doesn't exist
  .eq('status', 'pending')
```

**Why this happens:** The edge function was likely written against an early schema that used a separate `friend_requests` table. When the schema was consolidated into `friendships`, this function was never updated.

**Recommendation:** Change `friend_requests` → `friendships` and `to_user_id` → `addressee_id`:
```typescript
const { count: friendRequests } = await supabase
  .from('friendships')
  .select('*', { count: 'exact', head: true })
  .eq('addressee_id', userId)
  .eq('status', 'pending')
```

---

### BUG-002: Push Notification Badge Uses Wrong Column for Shared Workouts

| Field | Detail |
|-------|--------|
| **Severity** | CRITICAL |
| **File** | `supabase/functions/send-push-notification/index.ts:390-395` |
| **Impact** | Unread shared workout badge count is always 0. |

**Context:** Same edge function, different query. Uses `to_user_id` on the `shared_workouts` table, but that column is actually `recipient_id`.

**Code (broken):**
```typescript
// Line 390-395
const { count: unreadWorkouts } = await supabase
  .from('shared_workouts')
  .select('*', { count: 'exact', head: true })
  .eq('to_user_id', userId)     // ❌ Should be 'recipient_id'
  .is('viewed_at', null)
  .eq('status', 'pending')
```

**Why this happens:** Same root cause as BUG-001 — stale column references from an earlier schema version.

**Recommendation:** Change `to_user_id` → `recipient_id`.

---

### BUG-003: No Backend Unfriend Function (Feature Gap Manifesting as Bug)

| Field | Detail |
|-------|--------|
| **Severity** | CRITICAL |
| **File** | `Fit33/FriendProfileView.swift:781-790` + `Fit33/FriendService.swift:238-254` |
| **Impact** | The unfriend button exists in the UI but uses a raw `.delete()` on the `friendships` table instead of a proper RPC function. This bypasses any server-side validation. |

**Context:** `FriendProfileView.swift` shows a fully styled unfriend confirmation dialog (line 122) that calls `FriendService.shared.removeFriend()`. The service method does a direct table delete:

```swift
// FriendService.swift:238-254
func removeFriend(friendshipId: UUID) async -> Bool {
    do {
        try await SupabaseManager.shared.supabaseClient
            .from("friendships")
            .delete()
            .eq("id", value: friendshipId.uuidString)
            .execute()
        friends.removeAll { $0.friendshipId == friendshipId }
        return true
    } catch {
        print("❌ Error removing friend: \(error)")
        return false  // ← Silent failure, no user feedback
    }
}
```

**Why this is a problem:**
1. No server-side `unfriend()` RPC means no validation (e.g., checking the user owns this friendship)
2. RLS _should_ prevent unauthorized deletes, but a dedicated function would be safer and could handle cleanup (cascade shared workouts, active challenges, etc.)
3. On failure, the user sees nothing — the unfriend button just stops spinning

**Recommendation:** Create an `unfriend(friend_user_id UUID)` RPC that:
- Validates auth.uid() is part of the friendship
- Deletes the friendship row
- Optionally cancels active 1v1 challenges between the two users
- Returns success/failure with a reason

---

### BUG-004: No Blocking System (Safety Gap)

| Field | Detail |
|-------|--------|
| **Severity** | CRITICAL |
| **Files** | Entire codebase — no `user_blocks` table, no block functions, no block checks |
| **Impact** | Users cannot block harassing users. A blocked-concept doesn't exist anywhere. |

**Context:** Zero blocking infrastructure:
- No `user_blocks` table in the database
- No `block_user()` / `unblock_user()` RPC functions
- No block checking in `send_friend_request()`
- No RLS policies to hide blocked users from search results
- No UI for blocking in `FriendProfileView.swift`

**Why this matters:** This is a user safety issue. A harassing user can:
- Continuously send friend requests after being declined
- Appear in search results and PYMK suggestions indefinitely
- See the target user's profile in search

**Recommendation:** Multi-step implementation:
1. Create `user_blocks` table with `blocker_id`, `blocked_id`, `created_at`
2. Create `block_user()` and `unblock_user()` RPC functions
3. Add block checking to `send_friend_request()` (return error if blocked)
4. Add RLS policies so blocked users can't see each other in queries
5. Add block button to `FriendProfileView.swift` and search results
6. Filter blocked users from PYMK/contact suggestions in `ContactsService.swift`

---

## High Severity Bugs

### BUG-005: Search Filter Hides Users with Incoming Requests

| Field | Detail |
|-------|--------|
| **Severity** | HIGH |
| **File** | `Fit33/FriendsListView.swift:716-717` |
| **Impact** | Users who sent YOU a friend request are hidden from search results, making it impossible to find and respond to them via search. |

**Context:** When displaying search results, there's a filter applied:

```swift
// FriendsListView.swift:716-717
ForEach(friendService.searchResults.filter { user in
    return !user.isFriend && user.hasOutgoingRequest != true
}) { user in
```

This filter removes:
- Users who are already friends (`!user.isFriend`) — correct
- Users you've already sent a request to (`user.hasOutgoingRequest != true`) — correct

But it does NOT explicitly filter users with incoming requests (`hasIncomingRequest == true`). Those users pass the filter AND show a "Respond" button (`UserSearchResultCard` line 1655-1676), which just switches to the Requests tab. The real issue is that the filter only checks `hasOutgoingRequest` — if the API ever returns `nil` for these booleans, the `!= true` comparison could behave unexpectedly with Swift optionals.

**Why this happens:** The filter was designed to hide "already handled" relationships but relies on optional boolean comparisons (`!= true` on `Bool?`) which passes when the value is `nil` or `false`.

**Recommendation:**
```swift
ForEach(friendService.searchResults.filter { user in
    return !user.isFriend  // Already friends - hide
    // Show all others: pending outgoing, pending incoming, and no relationship
}) { user in
```
Remove the `hasOutgoingRequest` filter entirely — let the `UserSearchResultCard` handle the display state (it already shows "Pending" for outgoing requests). This way users can see and cancel pending requests directly from search.

---

### BUG-006: No Cancel Button for Sent Requests in Search Results

| Field | Detail |
|-------|--------|
| **Severity** | HIGH |
| **File** | `Fit33/FriendsListView.swift:1643-1654` (UserSearchResultCard) |
| **Impact** | When a user sees "Pending" on a search result, there's no way to cancel the request from that view. |

**Context:** The `UserSearchResultCard` shows a static "Pending" label for outgoing requests:

```swift
// FriendsListView.swift:1643-1654
} else if user.hasOutgoingRequest == true || requestSent {
    // I sent THEM a request - waiting for their response
    Text("Pending")
        .font(.caption)
        .fontWeight(.semibold)
        .foregroundColor(.orange)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .stroke(Color.orange, lineWidth: 1)
        )
}
```

This is a non-interactive label. Users must navigate to the Requests tab → Sent Requests section to cancel. Most users won't know to look there.

**Why this happens:** The "Pending" state was implemented as a read-only indicator, not an actionable button.

**Recommendation:** Convert the "Pending" label into a tappable button that calls `friendService.cancelSentRequest()`:
```swift
Button(action: { cancelRequest() }) {
    Text("Pending ✕")
        .font(.caption)
        .fontWeight(.semibold)
        .foregroundColor(.orange)
    // ... same styling
}
```

---

### BUG-007: Silent Failure on All Friend Operations

| Field | Detail |
|-------|--------|
| **Severity** | HIGH |
| **Files** | `Fit33/FriendService.swift` — lines 250-253, 312-329, 349-353, 371-375, 407-410, 458-461, 547-549, 567-569, 587-589, 604-606, 645-647, 666-668 |
| **Impact** | Every single friend operation (send request, accept, decline, cancel, remove, search, share workout, accept/decline workout, save workout, mark viewed/started/completed) catches errors and returns `false` or clears data silently. The user sees nothing. |

**Context:** This is a systemic pattern across all 12+ operations in `FriendService.swift`. Every catch block follows the same pattern:

```swift
} catch {
    print("❌ Error [doing thing]: \(error)")  // Only console log
    return false  // or: searchResults = []
}
```

Example — `sendFriendRequest` (line 312-329):
```swift
} catch {
    logger.log(.error, category: .social, message: "Friend request FAILED", ...)
    print("❌ [FRIEND REQUEST] Error sending friend request: \(error)")
    // Checks for "already exists" string match - fragile
    let errorString = String(describing: error)
    if errorString.contains("Friend request already exists") { ... }
    return false  // ← User sees nothing on failure
}
```

The callers (views) check the boolean but only provide haptic feedback:
```swift
// FriendRequestPreviewWidget.swift:223-225
if success {
    HapticManager.notification(.success)
} else {
    HapticManager.notification(.error)  // ← Phone buzzes differently, that's it
}
```

**Why this happens:** The service was built with a "fail silently" philosophy — likely to avoid crashing — but the UI layer never added error messaging on top.

**Recommendation:** See [Quick Win #3](#quick-win-3-add-user-facing-error-feedback) for full game plan.

---

### BUG-008: No Push Notification on Friend Request Accept

| Field | Detail |
|-------|--------|
| **Severity** | HIGH |
| **File** | `supabase/friend_request_system.sql` (accept_friend_request function) |
| **Impact** | When User B accepts User A's friend request, User A gets zero notification. They discover it only by manually checking their friends list. |

**Context:** The `accept_friend_request()` SQL function updates the friendship status to `'accepted'` but does not insert a notification into `push_notification_queue`. There's a `TODO` comment in the code indicating this was planned but never implemented.

**Why this happens:** The notification system was built for request-sending but the accept flow was left incomplete.

**Recommendation:** Add a push notification insert at the end of `accept_friend_request()`:
```sql
INSERT INTO push_notification_queue (user_id, title, body, data)
VALUES (
    v_requester_id,
    'Friend Request Accepted',
    v_accepter_name || ' accepted your friend request!',
    jsonb_build_object('type', 'friend_accepted', 'friend_id', auth.uid()::text)
);
```

---

## Medium Severity Bugs

### BUG-009: FriendSelectionSheet Has No Duplicate Participant Check

| Field | Detail |
|-------|--------|
| **Severity** | MEDIUM |
| **File** | `Fit33/FriendSelectionSheet.swift:10-175` |
| **Impact** | When creating a group challenge, the same friend could theoretically be selected twice if the sheet is used in a flow that allows re-opening it. |

**Context:** `FriendSelectionSheet` takes an `onSelect: (Friend) -> Void` callback and passes the selected friend back to the parent. The sheet itself has no knowledge of already-selected participants:

```swift
// FriendSelectionSheet.swift:15
let onSelect: (Friend) -> Void
// No `excludeIds: [UUID]` or `alreadySelected: Set<UUID>` parameter
```

**Why this happens:** The sheet was designed as a simple single-select picker. Duplicate prevention is expected to be handled by the parent view, but this is fragile.

**Recommendation:** Add an `excludeIds: Set<UUID>` parameter to filter out already-selected friends:
```swift
let excludeIds: Set<UUID>

private var filteredFriends: [Friend] {
    friendService.friends.filter { friend in
        !excludeIds.contains(friend.friendId) &&
        (searchText.isEmpty || /* existing filter logic */)
    }
}
```

---

### BUG-010: FriendRequestPreviewWidget Shows No Error State

| Field | Detail |
|-------|--------|
| **Severity** | MEDIUM |
| **File** | `Fit33/FriendRequestPreviewWidget.swift:214-243` |
| **Impact** | When accept/decline fails on the home screen widget, the user gets an error haptic buzz but the widget stays in its original state. No error message, no retry prompt. |

**Context:** Both `acceptRequest()` and `declineRequest()` in the widget follow this pattern:

```swift
// FriendRequestPreviewWidget.swift:214-228
private func acceptRequest() {
    HapticManager.impact(.medium)
    isAccepting = true
    Task {
        let success = await friendService.acceptFriendRequest(requestId: request.requestId)
        if success {
            HapticManager.notification(.success)
            onAccept()
        } else {
            HapticManager.notification(.error)  // ← Only feedback on failure
        }
        isAccepting = false  // ← Widget returns to original state silently
    }
}
```

**Why this happens:** The widget was built with optimistic UX but no error recovery path.

**Recommendation:** Add an `@State private var errorMessage: String?` that displays a brief inline error below the buttons when an operation fails, with a "Tap to retry" action.

---

### BUG-011: Stale Friendship Status in Search Results (Race Condition)

| Field | Detail |
|-------|--------|
| **Severity** | MEDIUM |
| **File** | `Fit33/FriendService.swift:438-462` |
| **Impact** | Search results contain `isFriend`, `hasOutgoingRequest`, `hasIncomingRequest` booleans computed at query time. If User B accepts User A's request while User A has search results open, the results still show "Pending" instead of "Friends" until a re-search. |

**Context:** `searchUsers()` calls the `search_users` RPC which returns friendship status flags:

```swift
// FriendService.swift:451-456
let result: [UserSearchResult] = try await SupabaseManager.shared.supabaseClient
    .rpc("search_users", params: SearchParams(search_query: query, result_limit: 20))
    .execute()
    .value
self.searchResults = result
```

These results are cached in `searchResults` with no automatic refresh. There's no Supabase Realtime subscription for friendship status changes.

**Why this happens:** The system uses polling (60s interval in `FriendsTabView`) and event-driven refresh, but search results are only refreshed on new searches.

**Recommendation:** After any friend operation (accept, send, cancel, decline, remove), invalidate/re-run the current search if `searchResults` is non-empty. Add to each operation's success path:
```swift
if !searchResults.isEmpty, let lastQuery = lastSearchQuery {
    await searchUsers(query: lastQuery)
}
```

---

### BUG-012: Error String Matching for "Already Exists" is Fragile

| Field | Detail |
|-------|--------|
| **Severity** | MEDIUM |
| **File** | `Fit33/FriendService.swift:320-327` |
| **Impact** | If the backend error message changes wording, the "already exists" detection breaks and legitimate duplicate requests show as failures. |

**Context:**
```swift
// FriendService.swift:320-327
let errorString = String(describing: error)
if errorString.contains("Friend request already exists") || errorString.contains("already exists") {
    print("ℹ️ [FRIEND REQUEST] Request already exists - treating as success")
    await fetchUnreadCount()
    await fetchSentRequests()
    return true
}
```

**Why this happens:** The `send_friend_request()` RPC raises an exception for duplicate requests. The frontend catches the error and string-matches against the message. This is a fragile pattern — any change to the error text (localization, wording change, Supabase version update) breaks the detection.

**Recommendation:** Have the backend return a structured response (e.g., `{ "status": "already_exists", "request_id": "..." }`) instead of throwing. Or use error codes instead of message string matching.

---

## Low Severity Bugs

### BUG-013: 60-Second Polling Wastes Battery When No Active Challenges

| Field | Detail |
|-------|--------|
| **Severity** | LOW |
| **File** | `Fit33/FriendsTabView.swift:44-48, 169-170` |
| **Impact** | The friends tab polls every 60 seconds regardless of whether the user has active challenges that need live updates. |

**Context:**
```swift
// FriendsTabView.swift:44-48
@State private var autoRefreshTimer: Timer?
/// How often to auto-poll for fresh opponent data (60 seconds).
/// Realtime WebSocket handles immediate updates; this is a fallback.
private let autoRefreshInterval: TimeInterval = 60
```

The timer runs whenever the Friends tab is visible, even if there are zero active challenges. The comment mentions Realtime WebSocket as the primary update mechanism, but WebSocket integration appears incomplete.

**Why this happens:** The polling was added as a "fallback" for realtime but became the de facto primary mechanism.

**Recommendation:** Conditionally poll — only start the timer when the user has active 1v1 challenges. When there are no active challenges, extend the interval to 5 minutes or disable polling entirely.

---

### BUG-014: Contacts Section Shows in Both Ranked and Alphabetical Views

| Field | Detail |
|-------|--------|
| **Severity** | LOW |
| **File** | `Fit33/FriendsListView.swift:259-262` |
| **Impact** | Minor UX issue — the "From Your Contacts" horizontal chip section always shows above the friends list, whether in Ranked or Alphabetical mode. In Ranked mode, these same contacts also appear in the ranked list below, creating visual duplication. |

**Context:**
```swift
// FriendsListView.swift:259-265
if !rankingService.friendsFromContacts.isEmpty {
    fromContactsSection  // Always shown
}

if showRankedView && !rankingService.rankedFriends.isEmpty {
    rankedFriendsSection  // Contains same friends from contacts
} else {
    // alphabetical view
}
```

**Why this happens:** The contacts section and ranked section were built independently without deduplication logic.

**Recommendation:** Either hide `fromContactsSection` when in ranked view, or filter contact friends out of `rankedFriends` to avoid duplicate display.

---

### BUG-015: Idempotent Send Returns Same UUID Without Distinction

| Field | Detail |
|-------|--------|
| **Severity** | LOW |
| **File** | Backend `send_friend_request()` RPC |
| **Impact** | When sending a request to someone you've already sent to, the RPC returns the existing request UUID (making it look like a new success) OR throws "already exists". The behavior is inconsistent. |

**Context:** The frontend handles this with string matching (BUG-012), but the root issue is the backend's inconsistent behavior.

**Recommendation:** Have the backend always return a consistent response:
```json
{ "request_id": "uuid", "status": "created" }    // new request
{ "request_id": "uuid", "status": "exists" }      // already pending
{ "request_id": "uuid", "status": "accepted" }    // already friends
```

---

## Quick Win Game Plans

---

## Quick Win #1: Fix Search Filter Logic

**Bug Reference:** BUG-005
**Estimated Effort:** 30 minutes
**Impact:** HIGH — Makes search results show all relevant users correctly
**Risk:** LOW — Only changes a filter predicate

### Problem Statement
The search results filter (`FriendsListView.swift:716-717`) uses `user.hasOutgoingRequest != true` which hides users you've already sent requests to. Combined with BUG-006 (no cancel from search), this means:
1. You send a request to someone
2. They disappear from future searches
3. You can't find them to cancel or check status

### Step-by-Step Game Plan

**Step 1: Modify the search filter (5 min)**

File: `Fit33/FriendsListView.swift`, line 716-717

Change:
```swift
ForEach(friendService.searchResults.filter { user in
    return !user.isFriend && user.hasOutgoingRequest != true
}) { user in
```

To:
```swift
ForEach(friendService.searchResults.filter { user in
    return !user.isFriend
}) { user in
```

This shows all non-friend users in search: those with no relationship, pending outgoing, and pending incoming. The `UserSearchResultCard` already handles all these states with appropriate UI (Add button, Pending label, Respond button).

**Step 2: Verify UserSearchResultCard handles all states (5 min)**

Confirm `UserSearchResultCard` (line 1631-1713) covers:
- `user.isFriend == true` → "Friends" badge (green) ✅ (line 1633)
- `user.hasOutgoingRequest == true` → "Pending" label (orange) ✅ (line 1643)
- `user.hasIncomingRequest == true` → "Respond" button (green) ✅ (line 1655)
- Default → "Add" button (blue/purple) ✅ (line 1677)

All four states are already handled. No changes needed here.

**Step 3: Test scenarios (15 min)**
1. Search for a user with no relationship → "Add" button appears
2. Send a friend request, search again → "Pending" label appears (NOT hidden)
3. Have someone send YOU a request, search for them → "Respond" button appears
4. Accept a request, search again → "Friends" badge appears
5. Verify the Respond button switches to the Requests tab (line 1657: `onRespondToRequest?()`)

**Step 4: Optional enhancement — make "Pending" tappable (10 min)**

While fixing the filter, convert the static "Pending" label to a cancel button (addresses BUG-006):

```swift
} else if user.hasOutgoingRequest == true || requestSent {
    Button(action: { cancelOutgoingRequest() }) {
        HStack(spacing: 4) {
            Text("Pending")
                .font(.caption)
                .fontWeight(.semibold)
            Image(systemName: "xmark")
                .font(.system(size: 8, weight: .bold))
        }
        .foregroundColor(.orange)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Capsule().stroke(Color.orange, lineWidth: 1))
    }
}
```

This requires adding a `cancelOutgoingRequest()` method that finds the request ID from `friendService.sentRequests` and calls `cancelSentRequest()`.

### Acceptance Criteria
- [ ] Search results show users with pending outgoing requests (with "Pending" indicator)
- [ ] Search results show users with pending incoming requests (with "Respond" button)
- [ ] Only truly "Friends" users are filtered out
- [ ] No regression in Add Friend flow

---

## Quick Win #2: Fix Push Notification Badge Counts

**Bug References:** BUG-001, BUG-002
**Estimated Effort:** 15 minutes
**Impact:** CRITICAL — Fixes the entire notification badge system
**Risk:** LOW — Two line changes in one file

### Problem Statement
The push notification edge function references a non-existent table (`friend_requests`) and wrong column names (`to_user_id`). This means **every push notification sent by the app has a badge count of 0**, regardless of actual pending items.

### Step-by-Step Game Plan

**Step 1: Fix friend request badge query (2 min)**

File: `supabase/functions/send-push-notification/index.ts`, lines 374-378

Change:
```typescript
const { count: friendRequests } = await supabase
  .from('friend_requests')
  .select('*', { count: 'exact', head: true })
  .eq('to_user_id', userId)
  .eq('status', 'pending')
```

To:
```typescript
const { count: friendRequests } = await supabase
  .from('friendships')
  .select('*', { count: 'exact', head: true })
  .eq('addressee_id', userId)
  .eq('status', 'pending')
```

**Step 2: Fix shared workout badge query (2 min)**

Same file, lines 390-395

Change:
```typescript
const { count: unreadWorkouts } = await supabase
  .from('shared_workouts')
  .select('*', { count: 'exact', head: true })
  .eq('to_user_id', userId)
  .is('viewed_at', null)
  .eq('status', 'pending')
```

To:
```typescript
const { count: unreadWorkouts } = await supabase
  .from('shared_workouts')
  .select('*', { count: 'exact', head: true })
  .eq('recipient_id', userId)
  .is('viewed_at', null)
  .eq('status', 'pending')
```

**Step 3: Verify column names against schema (5 min)**

Before deploying, confirm the correct column names:
```sql
-- Run in Supabase SQL editor
SELECT column_name FROM information_schema.columns WHERE table_name = 'friendships';
SELECT column_name FROM information_schema.columns WHERE table_name = 'shared_workouts';
```

Verify `addressee_id` exists on `friendships` and `recipient_id` exists on `shared_workouts`.

**Step 4: Deploy and test (5 min)**

```bash
# Deploy the updated edge function
supabase functions deploy send-push-notification
```

Test by:
1. Send a friend request to a test user
2. Verify the push notification arrives with badge = 1
3. Send a shared workout to the test user
4. Verify the badge increments to 2
5. Accept the friend request, verify badge decrements

**Step 5: Verify badge total computation (1 min)**

Confirm the total calculation at line 397 still works:
```typescript
const total = (friendRequests || 0) + (challengeInvites || 0) + (unreadWorkouts || 0)
```

This line handles nulls correctly with `|| 0`, so no change needed.

### Acceptance Criteria
- [ ] Push notifications show correct badge count for pending friend requests
- [ ] Push notifications show correct badge count for unread shared workouts
- [ ] Badge count decrements when items are addressed
- [ ] No errors in Supabase edge function logs

---

## Quick Win #3: Add User-Facing Error Feedback

**Bug Reference:** BUG-007
**Estimated Effort:** 2-3 hours
**Impact:** HIGH — Transforms the entire user experience from "mysterious silence" to "clear communication"
**Risk:** LOW — Additive change, doesn't modify existing logic

### Problem Statement
Every friend operation in `FriendService.swift` catches errors and returns `false` with only a console print. The user sees either:
- A haptic buzz that feels different (error vs success) but looks identical
- A button that stops spinning and returns to its original state
- Nothing at all

This affects 12+ operations across the entire friend system.

### Step-by-Step Game Plan

**Step 1: Add error state to FriendService (15 min)**

File: `Fit33/FriendService.swift`

Add a published error property near the top of the class (around line 20):

```swift
@Published var lastError: FriendServiceError?

enum FriendServiceError: Identifiable {
    case sendRequestFailed(String)
    case acceptRequestFailed
    case declineRequestFailed
    case cancelRequestFailed
    case removeFriendFailed
    case searchFailed
    case workoutOperationFailed(String)
    case networkError

    var id: String { title }

    var title: String {
        switch self {
        case .sendRequestFailed: return "Couldn't Send Request"
        case .acceptRequestFailed: return "Couldn't Accept Request"
        case .declineRequestFailed: return "Couldn't Decline Request"
        case .cancelRequestFailed: return "Couldn't Cancel Request"
        case .removeFriendFailed: return "Couldn't Remove Friend"
        case .searchFailed: return "Search Failed"
        case .workoutOperationFailed: return "Workout Error"
        case .networkError: return "Connection Error"
        }
    }

    var message: String {
        switch self {
        case .sendRequestFailed(let detail): return detail
        case .acceptRequestFailed: return "Please try again."
        case .declineRequestFailed: return "Please try again."
        case .cancelRequestFailed: return "Please try again."
        case .removeFriendFailed: return "Please try again."
        case .searchFailed: return "Check your connection and try again."
        case .workoutOperationFailed(let detail): return detail
        case .networkError: return "Please check your internet connection."
        }
    }
}
```

**Step 2: Update catch blocks to set lastError (30 min)**

For each of the 12+ catch blocks, add `lastError = .xxxFailed` before `return false`. Example for `sendFriendRequest` (line 312):

```swift
} catch {
    // ... existing logging ...

    let errorString = String(describing: error)
    if errorString.contains("already exists") {
        // ... existing handling ...
    }

    // NEW: Set user-facing error
    await MainActor.run {
        self.lastError = .sendRequestFailed("Something went wrong. Please try again.")
    }
    return false
}
```

Do this for all operations:
- `sendFriendRequest` (line 312) → `.sendRequestFailed`
- `acceptFriendRequest` (line 349) → `.acceptRequestFailed`
- `declineFriendRequest` (line 371) → `.declineRequestFailed`
- `cancelSentRequest` (line 407) → `.cancelRequestFailed`
- `removeFriend` (line 250) → `.removeFriendFailed`
- `searchUsers` (line 458) → `.searchFailed`
- `sendWorkoutToFriend` (line 547) → `.workoutOperationFailed`
- `acceptReceivedWorkout` (line 567) → `.workoutOperationFailed`
- `declineReceivedWorkout` (line 587) → `.workoutOperationFailed`

**Step 3: Add error alert to key views (30 min)**

Add an `.alert` modifier to each view that uses `FriendService`. Since `FriendService` is a shared singleton `ObservableObject`, any view observing it will see the error.

File: `Fit33/FriendsListView.swift` — add near the existing modifiers:

```swift
.alert(item: $friendService.lastError) { error in
    Alert(
        title: Text(error.title),
        message: Text(error.message),
        dismissButton: .default(Text("OK"))
    )
}
```

Add the same to:
- `FriendsTabView.swift` (main social hub)
- `FriendProfileView.swift` (unfriend errors)
- `FriendRequestPreviewWidget.swift` (accept/decline errors)

**Step 4: Auto-clear errors (10 min)**

Add auto-dismissal so errors don't persist:

```swift
@Published var lastError: FriendServiceError? {
    didSet {
        if lastError != nil {
            // Auto-clear after 5 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                self?.lastError = nil
            }
        }
    }
}
```

**Step 5: Test all error paths (30 min)**

Test each operation's failure path:
1. Turn on airplane mode → send friend request → verify error alert appears
2. Turn on airplane mode → accept request → verify error alert appears
3. Turn on airplane mode → decline request → verify error alert appears
4. Turn on airplane mode → search users → verify error alert appears
5. Turn on airplane mode → unfriend → verify error alert appears
6. Verify errors auto-dismiss after 5 seconds
7. Verify success paths are unaffected (no false error alerts)

**Step 6: Optional — Add inline error for search (15 min)**

For search specifically, show an inline error instead of an alert:

```swift
// In searchUsers() catch block:
await MainActor.run {
    searchResults = []
    self.searchErrorMessage = "Search failed. Check your connection."
}
```

Display in `FriendsListView.swift` search tab when `searchErrorMessage` is set.

### Acceptance Criteria
- [ ] All friend operations show a user-visible error alert on failure
- [ ] Error messages are clear and actionable ("Please try again", "Check your connection")
- [ ] Errors auto-dismiss after 5 seconds
- [ ] Success paths are unaffected — no false error alerts
- [ ] FriendRequestPreviewWidget shows error state on accept/decline failure
- [ ] Search shows inline error when search fails

---

## Summary Table

| Bug ID | Severity | File | Effort | Quick Win? |
|--------|----------|------|--------|------------|
| BUG-001 | CRITICAL | send-push-notification/index.ts:375 | 5 min | ✅ #2 |
| BUG-002 | CRITICAL | send-push-notification/index.ts:393 | 5 min | ✅ #2 |
| BUG-003 | CRITICAL | FriendService.swift:238 + backend | 2-3 hrs | |
| BUG-004 | CRITICAL | Entire codebase (missing) | 1-2 days | |
| BUG-005 | HIGH | FriendsListView.swift:717 | 30 min | ✅ #1 |
| BUG-006 | HIGH | FriendsListView.swift:1643 | 1 hr | ✅ #1 |
| BUG-007 | HIGH | FriendService.swift (12+ locations) | 2-3 hrs | ✅ #3 |
| BUG-008 | HIGH | friend_request_system.sql | 1 hr | |
| BUG-009 | MEDIUM | FriendSelectionSheet.swift:15 | 30 min | |
| BUG-010 | MEDIUM | FriendRequestPreviewWidget.swift:214 | 45 min | |
| BUG-011 | MEDIUM | FriendService.swift:438 | 1 hr | |
| BUG-012 | MEDIUM | FriendService.swift:320 | 1 hr | |
| BUG-013 | LOW | FriendsTabView.swift:44 | 30 min | |
| BUG-014 | LOW | FriendsListView.swift:259 | 20 min | |
| BUG-015 | LOW | Backend send_friend_request() | 1 hr | |

**Total estimated effort:** 12-18 hours for all bugs
**Quick wins alone:** ~3-4 hours for the highest impact fixes
