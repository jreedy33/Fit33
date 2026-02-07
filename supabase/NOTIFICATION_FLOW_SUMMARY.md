# Notification Flow Summary
## Contact Sync + Friend Requests + Account Deletion

This document explains how notifications work when Joe creates/recreates an account and adds friends during onboarding.

---

## 📱 Scenario 1: Joe Creates Account & Sends Friend Requests During Onboarding

### What Happens:
1. **Joe sends friend request to Abbie during onboarding**
2. **When Joe completes onboarding (account fully created):**
   - ✅ Abbie receives **friend request notification** (from `send_friend_request`)
   - ❌ Abbie does NOT receive "Joe joined Fit33!" notification
3. **Other contacts who didn't receive a friend request:**
   - ✅ They receive "Joe joined Fit33! Send him a request!" notification

### Technical Flow:
```
Joe completes onboarding
    ↓
notify-contacts-user-joined edge function triggered
    ↓
Finds all contacts who have Joe in their phone contacts
    ↓
CHECKS: Did Joe send them a friend request?
    ↓
YES (Abbie) → Skip "contact joined" notification (friend request serves as notification)
NO (other contacts) → Send "contact joined" notification
```

---

## 📱 Scenario 2: Joe Creates Account & Sends NO Friend Requests

### What Happens:
1. **Joe completes onboarding without adding anyone**
2. **All contacts (including Abbie):**
   - ✅ Receive "Joe joined Fit33! Send him a request!" notification

### Technical Flow:
```
Joe completes onboarding
    ↓
notify-contacts-user-joined edge function triggered
    ↓
Finds all contacts (including Abbie)
    ↓
No friend requests sent → ALL contacts get "contact joined" notification
```

---

## 🔄 Scenario 3: Joe Deletes Account & Recreates

### What Happens:
1. **Joe deletes his account**
   - All friendships with Abbie are deleted (CASCADE)
   - All friend requests are deleted (CASCADE)
   - All notifications are deleted (CASCADE)
   - Auth user is deleted (AFTER trigger)

2. **Joe creates new account**
   - Treated as completely new user
   - No previous friendship history with Abbie
   - Joe must re-add Abbie as friend (or Abbie adds Joe)

3. **If Joe sends Abbie a friend request during new onboarding:**
   - ✅ Abbie receives friend request notification
   - ❌ Abbie does NOT receive "contact joined" notification

4. **If Joe doesn't send Abbie a friend request:**
   - ✅ Abbie receives "Joe joined Fit33!" notification

---

## 🔧 Technical Implementation

### Files Modified:

#### 1. `supabase/friend_request_notifications.sql`
- Updated `send_friend_request()` function
- Now queues push notifications when friend requests are sent
- Notification includes requester name and message

#### 2. `supabase/functions/notify-contacts-user-joined/index.ts`
- Added logic to check for friend requests sent by new user
- Excludes friend request recipients from "contact joined" notifications
- Prevents duplicate notifications

#### 3. `supabase/fix_trigger_conflicts.sql`
- Fixed BEFORE/AFTER trigger conflicts
- Ensures proper cascade deletion
- Auth user cleanup happens AFTER all cascade deletes

---

## 📊 Notification Priority Logic

```typescript
if (user_sent_friend_request_to_contact) {
  // Friend request notification only
  // Contact joined notification = SKIPPED
} else if (contact_has_user_in_phone_contacts) {
  // Contact joined notification sent
}
```

---

## ✅ Benefits

1. **No Duplicate Notifications**: Friend request recipients don't get redundant "contact joined" notifications
2. **Cleaner UX**: The friend request itself serves as the notification
3. **Works with Account Deletion**: Fresh start when accounts are recreated
4. **Proper Cascade**: All related data is cleaned up when accounts are deleted

---

## 🚀 Deployment Steps

1. **Run SQL migrations:**
   ```sql
   -- First, fix trigger conflicts
   \i supabase/fix_trigger_conflicts.sql
   
   -- Then, enable friend request notifications
   \i supabase/friend_request_notifications.sql
   ```

2. **Deploy edge function:**
   ```bash
   supabase functions deploy notify-contacts-user-joined
   ```

3. **Test the flow:**
   - Create test account
   - Send friend requests during onboarding
   - Verify notifications are sent correctly
   - Delete account and verify cascade deletion
   - Recreate account and verify notifications work again

---

## 📝 Notes

- Friend requests sent during onboarding are queued and sent when account is fully created
- Contact joined notifications are sent only to users who didn't receive a friend request
- Account deletion removes ALL user data via CASCADE constraints
- New accounts start completely fresh with no previous relationships
