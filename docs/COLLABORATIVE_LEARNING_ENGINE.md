# Collaborative Learning Engine

## Overview

The **Collaborative Learning Engine** aggregates workout data across ALL users to make the recommendation system smarter over time. It learns from the collective intelligence of the user base to recommend exercises, pairings, and programs that work well for users with similar profiles.

---

## How It Works

### 1. User Similarity Matching

When Sarah completes a workout, the system:
1. Records her profile (goal, equipment, experience, demographics)
2. Finds other users with similar profiles (70%+ similarity)
3. Uses what worked for those users to improve Sarah's recommendations

**Similarity Factors:**
| Factor | Weight | Example |
|--------|--------|---------|
| Goal | 40% | "Build Muscle" matches "Build Muscle" |
| Experience | 30% | "Beginner" matches "Beginner" |
| Equipment | 30% | ["Barbell", "Dumbbells"] overlap |

### 2. Exercise Pairing Analysis

Every time exercises are done together in a workout, the system records the **co-occurrence**:

```
Sarah's Workout:
├── Barbell Bench Press
├── Incline Dumbbell Press
├── Cable Fly
└── Tricep Pushdown

Pairings Recorded:
├── Bench Press + Incline Press ✓
├── Bench Press + Cable Fly ✓
├── Bench Press + Tricep Pushdown ✓
├── Incline Press + Cable Fly ✓
├── Incline Press + Tricep Pushdown ✓
└── Cable Fly + Tricep Pushdown ✓
```

Over time, the system learns which exercises are commonly done together and have high success rates.

### 3. Success Tracking

A workout is considered **successful** if:
- User completed 3+ exercises
- User returned for the next workout
- Program completion rate stays high

This data is used to:
- Boost exercises with high success rates
- Recommend programs that users actually finish
- Identify exercise combinations that lead to retention

---

## Data Flow

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     USER COMPLETES WORKOUT                               │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                         RECORD TO DATABASE                               │
│                                                                          │
│  1. collaborative_workout_data   - Full workout details                  │
│  2. exercise_pairings            - Which exercises were together         │
│  3. user_similarity_profiles     - User's profile for matching           │
│  4. collaborative_program_completions - If program day                   │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                    AGGREGATION (Hourly Refresh)                          │
│                                                                          │
│  → exercise_global_stats         - Popularity & success per exercise     │
│  → exercise_pairing_stats        - Co-occurrence scores                  │
│  → program_success_stats         - Which programs work best              │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                    RECOMMENDATION BOOST                                  │
│                                                                          │
│  When selecting exercises:                                               │
│  +15 points: Popular among all users                                     │
│  +10 points: High success rate globally                                  │
│  +30 points: Popular among SIMILAR users                                 │
│  +15 points: Pairs well with target muscles                              │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Example Scenario

### Sarah and Jane

**Sarah's Profile:**
- Goal: Build Muscle
- Experience: Intermediate
- Equipment: Barbell, Dumbbells, Cables
- Weight: 140 lbs
- Age: 28

**Jane's Profile:**
- Goal: Build Muscle
- Experience: Beginner
- Equipment: Dumbbells, Cables, Machines
- Weight: 145 lbs
- Age: 30

**Similarity Score: 85%** (Same goal, similar stats, overlapping equipment)

**What Happens:**

1. Sarah completes a Push workout with great results:
   - Dumbbell Bench Press ✓
   - Cable Fly ✓
   - Overhead Tricep Extension ✓

2. System records Sarah's success

3. When Jane requests a Push workout:
   - System sees Sarah (similar user) had success
   - **Dumbbell Bench Press** gets +25 boost (popular among similar users)
   - **Cable Fly** gets +20 boost (pairs well, high success)
   - Jane sees these exercises recommended higher

4. If 10 similar users also completed this combination:
   - The pairing gets even stronger
   - **"Cable Fly after Bench Press"** becomes a proven combination
   - Future users with similar profiles get this recommendation

---

## Database Tables

| Table | Purpose |
|-------|---------|
| `user_similarity_profiles` | Store user attributes for matching |
| `collaborative_workout_data` | Every completed workout (anonymized) |
| `exercise_pairings` | Raw co-occurrence data |
| `exercise_pairing_stats` | Aggregated: which pairs work together |
| `exercise_global_stats` | Overall popularity + success rates |
| `collaborative_program_completions` | Which programs users finish |
| `program_success_stats` | Which programs have best completion rates |

---

## Scoring Breakdown

When recommending an exercise, the final score includes:

| Source | Points | Description |
|--------|--------|-------------|
| **Base** | 100 | Starting score |
| **Individual Learning** | ±80 | User's personal preferences |
| **Collaborative Popularity** | +15 | How popular globally |
| **Collaborative Success** | +10 | Success rate globally |
| **Similar User Boost** | +30 | What similar users like |
| **Equipment Priority** | +60 | Matches user's equipment |
| **Variety Penalty** | -60 | Recently done exercise |
| **Compound Boost** | +25 | Compound > isolation |

**Total possible: ~320 points** (best case for a perfect match)

---

## Privacy & Security

- **Anonymized Data**: User IDs are hashed, no personal info stored
- **Row Level Security**: Users can only insert their own data
- **Aggregated Stats**: Individual workouts not exposed, only aggregates
- **Opt-out Ready**: Can disable collaborative features per user

---

## Maintenance

### Refresh Schedule
```sql
-- Runs hourly via Supabase cron
SELECT refresh_collaborative_stats();
```

### Monitor Health
```sql
-- Check data collection
SELECT 
    COUNT(*) as total_workouts,
    COUNT(DISTINCT user_id) as unique_users,
    AVG(jsonb_array_length(exercises)) as avg_exercises_per_workout
FROM collaborative_workout_data
WHERE completed_at > NOW() - INTERVAL '7 days';
```

---

## Integration Points

### 1. WorkoutManager.finishWorkout()
Records workout to collaborative engine after completion.

### 2. SmartProgramEngine.completeDay()
Records program completion when program is finished.

### 3. SmartExerciseSelectionEngine.selectExercisesForWorkout()
Uses collaborative scores when selecting exercises.

### 4. App Launch (BuiltSimpleApp.swift)
Syncs global trends data on startup.

---

## Future Enhancements

1. **Real-time Recommendations**: "Users like you are doing..."
2. **Workout Templates**: Share successful workouts anonymously
3. **Exercise Discovery**: "Try this - 89% of similar users loved it"
4. **Program Matching**: "This program worked for 120 users like you"
5. **A/B Testing**: Test different recommendation strategies

