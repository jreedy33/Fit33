# Database Persistence & Learning Engine Data Flow

## Overview

The GoFit app uses a multi-layer persistence strategy to ensure workout data is saved for the learning engine to build personalized recommendations.

---

## Database Tables (Supabase)

### 1. `user_learning_profiles`
**Purpose:** Stores the computed user behavior profile for quick access.

| Field | Type | Description |
|-------|------|-------------|
| user_id | UUID | User's unique identifier |
| exercise_affinities | JSON | Score (0-1) for each exercise user has done |
| equipment_preferences | JSON | Score for equipment types (barbell, dumbbell, etc.) |
| muscle_preferences | JSON | Score for muscle groups |
| category_preferences | JSON | Score for workout categories |
| movement_patterns | JSON | Score for movement patterns (push, pull, squat, etc.) |
| exercise_completion_counts | JSON | How many times each exercise was completed |
| full_set_exercises | Array | Exercises completed with 3+ sets |
| favorited_exercises | Array | User's favorited exercises |
| preferred_duration | Int | Average workout duration in minutes |
| preferred_time | String | Morning/Afternoon/Evening preference |
| total_workouts | Int | Total workouts analyzed |
| last_updated | DateTime | Last profile update |

### 2. `user_programs`
**Purpose:** Stores active and completed training programs with full state.

| Field | Type | Description |
|-------|------|-------------|
| id | UUID | Program instance ID |
| user_id | UUID | User's unique identifier |
| template_id | String | Reference to program template |
| program_name | String | Personalized program name |
| current_day | Int | Current day in program |
| total_days | Int | Total program days |
| completed_days | Int | Number of days completed |
| is_active | Bool | Whether program is currently active |
| started_date | DateTime | When program was started |
| program_data | JSON | Full SmartActiveProgram serialization |
| last_updated | DateTime | Last update timestamp |

### 3. `program_day_completions`
**Purpose:** Records each completed program day for learning engine analysis.

| Field | Type | Description |
|-------|------|-------------|
| id | UUID | Completion record ID |
| user_id | UUID | User's unique identifier |
| program_id | UUID | Which program this day belongs to |
| program_name | String | Program name for reference |
| day_number | Int | Day number in program (1, 2, 3...) |
| day_name | String | Day name (e.g., "Push Day", "Legs A") |
| focus_muscles | Array | Target muscles for the day |
| exercises_completed | Array | List of exercise names completed |
| completed_date | DateTime | When day was completed |
| actual_duration | Int | Actual workout duration in minutes |

### 4. `completed_programs`
**Purpose:** Records which program templates user has completed.

| Field | Type | Description |
|-------|------|-------------|
| id | UUID | Record ID |
| user_id | UUID | User's unique identifier |
| template_id | String | Program template that was completed |
| completed_date | DateTime | When program was finished |

### 5. `workout_history`
**Purpose:** Stores all completed workouts (auto-gen, custom, and program days).

| Field | Type | Description |
|-------|------|-------------|
| id | UUID | Workout ID |
| user_id | UUID | User's unique identifier |
| name | String | Workout name |
| date | DateTime | When workout was done |
| duration | Int | Duration in seconds |
| is_completed | Bool | Whether workout was completed |
| xp_earned | Int | XP earned from workout |
| program_id | UUID | If from program, which program |
| program_day | Int | If from program, which day |
| exercises | JSON | Array of exercises with sets/reps |

### 6. `exercise_usage_logs`
**Purpose:** Detailed log of every exercise performed for analytics.

| Field | Type | Description |
|-------|------|-------------|
| user_id | UUID | User's unique identifier |
| exercise_id | String | Exercise identifier |
| exercise_name | String | Exercise name |
| workout_id | UUID | Which workout this was part of |
| sets_completed | Int | Number of sets done |
| total_reps | Int | Total reps across all sets |
| total_weight_kg | Double | Total weight lifted |
| workout_type | String | "auto-gen", "custom", or "program" |
| program_id | UUID | If program workout, which program |

---

## Data Flow

### 1. When User Completes a Workout

```
User completes workout
         │
         ▼
┌─────────────────────────┐
│   WorkoutManager        │
│   finishWorkout()       │
└─────────┬───────────────┘
          │
          ├──▶ Save to Core Data (local)
          │
          ├──▶ Save to Supabase `workout_history`
          │
          ├──▶ Log to `exercise_usage_logs`
          │
          └──▶ Trigger Learning Engine
               │
               ▼
┌─────────────────────────────────────┐
│   UserBehaviorLearningEngine        │
│   refreshAfterWorkout()             │
│   - Update exercise affinities      │
│   - Update equipment preferences    │
│   - Update muscle preferences       │
│   - Save to local cache             │
│   - Sync to Supabase cloud          │
└─────────────────────────────────────┘
```

### 2. When User Completes a Program Day

```
User completes program day
         │
         ▼
┌─────────────────────────┐
│   SmartProgramEngine    │
│   completeDay()         │
└─────────┬───────────────┘
          │
          ├──▶ Update program state
          │
          ├──▶ Generate next day
          │
          ├──▶ Save to UserDefaults (local)
          │
          ├──▶ Sync to Supabase `user_programs`
          │
          └──▶ Save to `program_day_completions`
               (for learning engine analysis)
```

### 3. When Generating New Workout/Program Day

```
Request new workout
         │
         ▼
┌───────────────────────────────────────┐
│   SmartExerciseSelectionEngine        │
│   selectExercisesForWorkout()         │
└─────────┬─────────────────────────────┘
          │
          ▼
┌───────────────────────────────────────┐
│   UserBehaviorLearningEngine          │
│   calculateLearnedBoostScore()        │
│                                       │
│   Pulls from:                         │
│   - user_learning_profiles (cloud)    │
│   - Local cache (UserDefaults)        │
│   - program_day_completions (cloud)   │
│                                       │
│   Returns boost/penalty scores for    │
│   each exercise based on:             │
│   - Exercise affinity (+)             │
│   - Equipment preference (+)          │
│   - Recent completion (-)             │
│   - Similar exercises (±)             │
│   - Discovery bonus (+)               │
└───────────────────────────────────────┘
```

---

## Local Caching Strategy

### UserDefaults Keys

| Key | Data | Purpose |
|-----|------|---------|
| `userBehaviorProfile` | UserBehaviorProfile JSON | Fast access to learning data |
| `smart_user_programs` | [SmartActiveProgram] JSON | Program state |
| `completed_programs_{userId}` | [String] | Completed program template IDs |

### Why Local + Cloud?

1. **Local Cache (UserDefaults):** 
   - Instant access on app launch
   - Works offline
   - Fast read/write

2. **Cloud (Supabase):**
   - Cross-device sync
   - Persistent storage
   - Backup

3. **Merge Strategy:**
   - Local loads first (fast startup)
   - Cloud syncs in background
   - Conflicts resolved by "most progress wins"

---

## Learning Engine Scoring

When selecting exercises, the learning engine applies these boosts/penalties:

| Factor | Points | Condition |
|--------|--------|-----------|
| Exercise Affinity | +80 max | Based on completion history |
| Equipment Preference | +50 max | User's equipment usage patterns |
| Muscle Affinity | +30 max | User's muscle group preferences |
| Movement Pattern | +40 max | User's movement pattern preferences |
| **Recently Done** | **-35** | Exercise done in last 14 workouts |
| **Freshness Bonus** | **+45** | Exercise never/rarely done |
| Similar Exercise Boost | +15 | User likes similar variations |
| Discovery Bonus | +25 | Fresh exercise + preferred equipment |

---

## Ensuring Consistency

### Program Generation Uses:
1. Previous day exercises (variety penalty)
2. User's completed exercise history (learning boost)
3. Equipment preferences (equipment balance)
4. Movement pattern history (pattern limits)

### Auto-Gen Uses:
1. Same learning engine as programs
2. Recent workout history (avoid repetition)
3. User preferences from all sources

### Result:
- Programs and Auto-Gen recommendations are **consistent**
- Both pull from the **same learning data**
- Both respect **variety** and **user preferences**
- Both adapt as user completes more workouts

---

## Testing the Data Flow

To verify data is being saved correctly:

1. **Complete a program day** → Check `program_day_completions` in Supabase
2. **Complete any workout** → Check `workout_history` and `exercise_usage_logs`
3. **Start app on new device** → Verify programs sync from `user_programs`
4. **Check learning profile** → Verify `user_learning_profiles` has latest data

```swift
// Debug: Print current learning state
print(UserBehaviorLearningEngine.shared.userPreferences?.totalWorkoutsAnalyzed ?? 0)
print(UserBehaviorLearningEngine.shared.userPreferences?.exerciseAffinityScores.count ?? 0)
```

