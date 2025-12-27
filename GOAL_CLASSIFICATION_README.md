# Goal Classification System - Implementation Summary

## Overview

This update adds **4 key columns** for intelligent goal-based exercise recommendations. We intentionally kept this minimal - only adding data that provides genuine new signal.

## New Columns (4 Total)

| Column | Type | Default | Description |
|--------|------|---------|-------------|
| `fat_loss_rating` | Int (1-10) | 5 | How good for "Get Lean" goal. Different from endurance - measures metabolic demand (burpees, thrusters). |
| `general_fitness_rating` | Int (1-10) | 5 | How good for balanced/variety workouts. |
| `is_compound` | Boolean | false | True for multi-joint movements (squats, presses, rows). Explicit flag is cleaner than name-based detection. |
| `supersetable` | Boolean | true | Can be done back-to-back without major fatigue. Key for "Get Lean" circuits. |

## Why Only 4 Columns?

**We intentionally excluded:**
- `recommended_sets`, `rest_seconds` - These should vary by **goal**, not be exercise-static
- `buildMuscleReps`, `getLeanReps`, etc. - Static strings are inflexible; better to calculate dynamically
- `musclesWorkedCount` - Derivable from existing `muscleGroups` array
- `durationBased` - Already have `workoutType` = "Cardio" or "Stretching"

**You already have:**
- `hypertrophyRating` → Build Muscle scoring
- `strengthRating` → Strength scoring  
- `enduranceRating` → Endurance scoring
- `fatigability` → How taxing an exercise is
- `optimalRepRangeMin/Max` → Rep range guidance

---

## Files Modified

### 1. Core Data Model
**File:** `GoFit/DataModel.xcdatamodeld/DataModel.xcdatamodel/contents`

Added 4 new attributes to Exercise entity.

### 2. SupabaseManager.swift
Added new fields to `CloudExercise` struct for cloud sync.

### 3. ExerciseLibraryService.swift  
Updated `syncExercisesFromCloud()` to populate new fields.

### 4. WorkoutGeneratorService.swift
Updated goal-based scoring:
- **Build Muscle:** Uses `hypertrophyRating × 4` + `isCompound` bonus (+15)
- **Get Lean:** Uses `fatLossRating × 4` + `supersetable` bonus (+10) + low-fatigue bonus (+8)
- **Endurance:** Uses `enduranceRating × 4` + cardio/stretching bonus (+15)
- **General Fitness:** Uses `generalFitnessRating × 4`
- **Strength:** Uses `strengthRating × 4` + `isCompound` bonus (+20)

---

## SQL Scripts

### Step 1: Add New Columns
**File:** `GOAL_CLASSIFICATION_UPDATE.sql` (40 lines)

```sql
-- Run in Supabase SQL Editor
ALTER TABLE exercises ADD COLUMN IF NOT EXISTS fat_loss_rating INTEGER DEFAULT 5;
ALTER TABLE exercises ADD COLUMN IF NOT EXISTS general_fitness_rating INTEGER DEFAULT 5;
ALTER TABLE exercises ADD COLUMN IF NOT EXISTS is_compound BOOLEAN DEFAULT FALSE;
ALTER TABLE exercises ADD COLUMN IF NOT EXISTS supersetable BOOLEAN DEFAULT TRUE;
```

### Step 2: Update Data  
**File:** `UPDATE_GOAL_CLASSIFICATIONS.sql` (~6,800 lines)

Run after Step 1 to populate 6,749 exercises.

### Step 3: Verify
```sql
SELECT 
    COUNT(*) as total,
    COUNT(CASE WHEN fat_loss_rating != 5 THEN 1 END) as fat_loss_customized,
    COUNT(CASE WHEN is_compound = true THEN 1 END) as compound_count,
    COUNT(CASE WHEN supersetable = false THEN 1 END) as non_supersetable
FROM exercises;
```

---

## Data Distribution

From the CSV classification:

| Metric | Count |
|--------|-------|
| **Compound exercises** | 1,918 |
| **Isolation exercises** | 4,831 |
| **Non-supersetable** (heavy compounds like deadlifts) | 788 |
| **Fat Loss Rating = 10** (burpees, jumping jacks) | 105 |
| **Fat Loss Rating ≥ 7** | 2,246 |

---

## How It Works in the App

```swift
// WorkoutGeneratorService.swift scoring:

// GET LEAN goal
if goalLower.contains("get lean") {
    score += Double(exercise.fatLossRating) * 4   // 0-40 points
    if exercise.supersetable { score += 10 }       // Circuit-friendly bonus
    if exercise.fatigability < 6 { score += 8 }    // Can do more volume
}

// BUILD MUSCLE goal  
if goalLower.contains("build muscle") {
    score += Double(exercise.hypertrophyRating) * 4
    if exercise.isCompound { score += 15 }         // Compound movements first
}
```

---

## CSV Source
**File:** `exercise_goal_classifications.csv` (6,749 exercises)
