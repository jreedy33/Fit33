# Exercise Popularity Tracking System

## 🎯 What This Does

Your app now invisibly tracks which exercises users love most! This data helps:
- **Improve auto-generated workouts** - Prioritize popular exercises
- **Better program creation** - Focus on exercises users actually complete
- **Data-driven decisions** - See what resonates with your users

## ✅ Setup Instructions

### Step 1: Create Database Tables in Supabase

1. Go to your **Supabase Dashboard** → **SQL Editor**
2. Click **New Query**
3. Open the file `exercise_popularity_tracking.sql`
4. Copy and paste ALL the contents into Supabase
5. Click **Run** (▶️)

You should see: `SELECT 1` (means it worked!)

### Step 2: Verify Tables Were Created

Run this query in SQL Editor:

```sql
SELECT table_name FROM information_schema.tables 
WHERE table_name IN ('exercise_usage_logs', 'exercise_popularity_stats');
```

You should see both tables listed!

### Step 3: Test It Out

1. **Run your app**
2. Complete a workout (any workout - custom, auto-generated, or program)
3. Go back to **Supabase SQL Editor**
4. Run this query:

```sql
SELECT COUNT(*) FROM exercise_usage_logs;
```

You should see a number > 0! This means exercises are being tracked! 📊

## 📱 How to Access Analytics (Developer Only)

The analytics dashboard is **hidden from users** but accessible to you:

1. Open the app
2. Go to **Profile** → **Settings** (gear icon)
3. Scroll to the bottom
4. **Tap "Built. Simple. v1.0.0" five times quickly**
5. A new "DEVELOPER TOOLS" section appears!
6. Tap **"Exercise Analytics" 📊**

You'll see:
- **Top 20 Most Popular Exercises** (all-time)
- **Top 10 Trending Exercises** (last 7 days)
- Total uses, unique users, popularity scores
- Real-time data from all your users!

## 🔄 How It Works (Behind the Scenes)

### What Gets Tracked (Invisible to Users):
- Every time a user completes an exercise in a workout
- Number of sets completed
- Total reps performed
- Total weight lifted
- Workout type (custom/auto-generated/program)
- Timestamp of completion

### What Gets Calculated:
- **Popularity Score (0-100)**: Weighted combination of:
  - Recent usage (50%)
  - User diversity (20%)
  - Historical usage (10%)
  - Completion rate (20%)
  
- **Trending Score**: Recent usage vs. historical average
- **Completion Rate**: % of times exercise was actually completed
- **Average sets/reps per use**

## 📊 Using the Data to Improve Workouts

### Current State
✅ **Tracking is active** - Data flows into Supabase automatically
✅ **Analytics dashboard works** - You can see popularity in real-time
✅ **Popularity stats update** - Run `SELECT update_exercise_popularity_stats();` in Supabase

### Next Step: Integrate into Algorithms

To use this data in workout generation, add this to `IntelligentWorkoutGenerator.swift`:

```swift
// Fetch popular exercises
let popularExercises = try await SupabaseManager.shared.fetchPopularExercises(limit: 100)

// Boost popular exercises in selection
let popularExerciseNames = Set(popularExercises.map { $0.exerciseName })

// When selecting exercises, prioritize popular ones:
let sortedExercises = availableExercises.sorted { exercise1, exercise2 in
    let score1 = popularExerciseNames.contains(exercise1.name) ? 10 : 0
    let score2 = popularExerciseNames.contains(exercise2.name) ? 10 : 0
    return score1 > score2
}
```

## 🔧 Maintenance

### Update Stats (Run Daily/Weekly)

In **Supabase SQL Editor**, run:

```sql
SELECT update_exercise_popularity_stats();
```

This recalculates all popularity scores based on latest usage data.

### View Top Exercises Directly

```sql
SELECT * FROM top_popular_exercises LIMIT 10;
```

### View Trending Exercises

```sql
SELECT * FROM trending_exercises LIMIT 10;
```

### See Usage by Category

```sql
SELECT * FROM exercise_usage_by_category;
```

## 🎉 Benefits

1. **Data-Driven**: Know exactly what users love
2. **Invisible**: Users never see the tracking
3. **Real-Time**: Updates as workouts are completed
4. **Scalable**: Works across thousands of users
5. **Actionable**: Use data to improve algorithms

## 🔐 Privacy Note

- All data is anonymized in analytics views
- Individual user IDs are stored but not exposed in dashboards
- Only aggregated stats are used for workout generation
- Complies with user data privacy best practices

---

**You're all set!** 🚀 

Complete a few workouts and check the Developer Analytics dashboard to see the magic happen!

