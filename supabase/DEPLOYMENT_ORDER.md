# Supabase SQL Deployment Order

Run these SQL files in your Supabase SQL Editor **in this exact order**:

## ✅ Already Deployed
1. ~~`fix_contact_matching_rls.sql`~~ ✓ Done
2. ~~`cascade_delete_incomplete_profiles.sql`~~ ✓ Done  
3. ~~`cleanup_incomplete_onboarding.sql`~~ ✓ Done

## 🚀 Deploy Now (New Files)

### 4. Complete Account Deletion
```sql
-- Copy/paste: complete_account_deletion.sql
```

**What it does:**
- Ensures complete data deletion when user deletes account
- Joe deletes account → removed from Abbie's friend list instantly
- No notification to Abbie
- Joe's new account starts fresh (no friends)

### 5. Friend Request System
```sql
-- Copy/paste: friend_request_system.sql
```

**What it does:**
- Friend requests sent during onboarding show up in "Sent Requests"
- Proper handling of pending/accepted/rejected states
- Prevents duplicate friend requests

## 📋 Summary of All Systems

### 1️⃣ Contact Matching (✅ Active)
- Users can find friends by phone number during onboarding
- RLS policies allow contact discovery

### 2️⃣ Incomplete Profile Cleanup (✅ Active)
- Abandoned onboarding profiles deleted after 30 minutes
- Runs every 10 minutes automatically
- Prevents duplicate account errors

### 3️⃣ Complete Account Deletion (🆕 Deploy)
**Before:** Deleting account left orphaned data
**After:** All data completely removed, friends updated instantly

### 4️⃣ Friend Request Persistence (🆕 Deploy)
**Before:** Friend requests during onboarding might not show up
**After:** Requests sent during onboarding visible in "Sent Requests" section

## 🧪 Test After Deployment

```sql
-- Test 1: Check account deletion preview
SELECT test_account_deletion('USER_ID_HERE');

-- Test 2: Check sent friend requests
SELECT * FROM get_sent_friend_requests();

-- Test 3: Check pending (incoming) requests
SELECT * FROM get_pending_friend_requests();
```

## 📊 User Flow Examples

### Example 1: Account Deletion
1. Joe and Abbie are friends
2. Joe deletes account
3. ✅ Joe removed from Abbie's friend list instantly
4. ✅ No notification sent to Abbie
5. Joe creates new account with same email
6. ✅ Joe starts fresh (no friends, must re-add Abbie)

### Example 2: Onboarding Friend Request
1. Joe signs up, goes through onboarding
2. During "Add Friends" step, Joe sends request to Abbie
3. Joe completes onboarding
4. ✅ In Joe's app, "Sent Requests" shows pending request to Abbie
5. Abbie opens app, sees Joe's friend request
6. Abbie accepts → they're now friends

### Example 3: Abandoned Onboarding
1. Joe verifies phone (creates minimal profile)
2. Joe abandons onboarding without completing
3. After 30 minutes: ✅ Joe's profile auto-deleted
4. Next day: Joe tries again
5. ✅ Clean slate, no conflicts, works perfectly

## 🔧 Maintenance

### View incomplete profiles
```sql
SELECT id, email, phone_number, created_at,
       NOW() - created_at as age
FROM user_profiles
WHERE has_completed_onboarding = false
ORDER BY created_at DESC;
```

### Manually trigger cleanup
```sql
SELECT cleanup_incomplete_onboarding_profiles();
```

### Check cascade delete constraints
```sql
SELECT 
    tc.table_name, 
    tc.constraint_name,
    kcu.column_name,
    ccu.table_name AS foreign_table_name,
    ccu.column_name AS foreign_column_name,
    rc.delete_rule
FROM information_schema.table_constraints AS tc 
JOIN information_schema.key_column_usage AS kcu
  ON tc.constraint_name = kcu.constraint_name
JOIN information_schema.constraint_column_usage AS ccu
  ON ccu.constraint_name = tc.constraint_name
JOIN information_schema.referential_constraints AS rc
  ON rc.constraint_name = tc.constraint_name
WHERE tc.constraint_type = 'FOREIGN KEY'
  AND tc.table_name = 'friendships';
```
