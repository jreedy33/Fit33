# Testing Collaborative Learning on Your Device

## ✅ Setup Complete!

You've successfully:
1. Created 5 database tables in Supabase
2. Updated the Swift code to match the new schema
3. Configured the app to record workout data

## 🧪 How to Test

### Step 1: Build and Run
1. Build the app in Xcode
2. Run it on your device (or simulator)
3. Sign in with your account

### Step 2: Complete Some Workouts
The system needs data to learn from. Complete **10-20 workouts** of different types:

- ✅ Complete a few auto-gen workouts
- ✅ Complete some custom workouts
- ✅ Start a program and complete a few days

**Why 10-20?** The collaborative engine needs a baseline of data to identify patterns and make recommendations.

### Step 3: Check Data is Syncing

#### Option A: Using the Debug View (Easiest)
1. Open the app
2. Go to **Settings Tab**
3. Enable **Developer Mode**
4. Go to **Dev Menu** → **Learning Tab**
5. You'll see:
   - ✅ Sync status
   - ✅ Number of workouts analyzed
   - ✅ Your exercise preferences
   - ✅ Equipment usage
   - ✅ Recent exercises

#### Option B: Check Supabase Directly
1. Go to your Supabase Dashboard
2. Go to **Table Editor**
3. Check these tables:
   - `collaborative_workout_data` - should have rows for each completed workout
   - `exercise_pairings` - should have rows for exercises done together
   - `user_similarity_profiles` - should have a row for your profile
   - `user_exercise_preferences` - should show your favorite exercises

### Step 4: Test Recommendations

After completing 10+ workouts:

1. **Generate an Auto-Gen Workout**
   - Tap "Quick Start" → "Auto-Generate"
   - The exercises should reflect your preferences
   
2. **Start a New Program**
   - Go to "Training Programs"
   - Start a new program
   - The exercises should be personalized based on what you've done

3. **Check the Debug View Again**
   - Your "Recent Exercises" list should update
   - Equipment preferences should reflect what you've used
   - Learning profile should show recent sync

## 🔍 What to Look For

### Good Signs ✅
- Workouts include exercises you've done before and liked
- Equipment matches what you have available
- No excessive repetition (same exercise 3+ days in a row)
- Muscle groups are balanced across the week
- Debug view shows recent sync timestamps

### Red Flags ⚠️
- Same exercises every single day
- Wrong equipment (home user getting barbell)
- Sync errors in debug view
- Empty tables in Supabase
- No data in learning profile

## 🐛 Troubleshooting

### "No data in Supabase tables"
**Fix:** 
1. Check internet connection
2. Complete a workout end-to-end (don't cancel)
3. Wait 5-10 seconds after finishing
4. Check Supabase again

### "Debug view shows 'Never synced'"
**Fix:**
1. Tap "Refresh Data" in debug view
2. Check you're signed in (Settings → Account)
3. Check Supabase connection (Dev Menu → Test Cloud Connection)

### "Recommendations aren't personalized"
**Fix:**
1. Complete more workouts (need at least 10)
2. Make sure workouts are being saved (check Supabase tables)
3. Wait for cache to refresh (happens every hour, or force refresh in debug view)

## 📊 Expected Behavior

After completing **10 workouts**, you should see:
- 10 rows in `collaborative_workout_data`
- 30-50 rows in `exercise_pairings` (depends on exercises per workout)
- 1 row in `user_similarity_profiles`
- 20-40 rows in `user_exercise_preferences`

After completing **20 workouts**, recommendations should:
- Start favoring equipment you use most
- Reduce exercises you haven't done in a while
- Prioritize exercises with good completion rates
- Suggest smart pairings (e.g., bench press + chest fly)

## 🚀 Next Steps (Later)

Once you have **50+ completed workouts** in your database:
1. I'll give you a second SQL file to create materialized views
2. These views will make recommendations even smarter
3. They'll aggregate data across all users (when you have multiple users)

For now, the system is working with the base tables and will get smarter as you complete more workouts!

## 💡 Tips

- **Variety is good**: Complete different types of workouts (push/pull/legs, full body, etc.)
- **Finish workouts**: The system only learns from completed workouts, not canceled ones
- **Use different equipment**: If you have access to both home and gym, try both
- **Check weekly**: Look at the debug view once a week to see how your profile evolves

---

**Questions?** Check the debug view first - it shows you exactly what the system knows about you and when it last synced.

