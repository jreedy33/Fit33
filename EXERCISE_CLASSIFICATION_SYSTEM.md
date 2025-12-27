# Exercise Database Classification System - Implementation Guide

## Current Database Schema Mapping

### ✅ Columns That ALREADY EXIST (Use these, don't recreate)

| Your Column | Status | Notes |
|-------------|--------|-------|
| `id` | ✅ Exists | UUID primary key |
| `name` | ✅ Exists | Full exercise name |
| `equipment` | ✅ Exists | Equipment string |
| `workout_type` | ✅ Exists | Maps to `exercise_type` in the prompt |
| `category` | ✅ Exists | Body part category |
| `primary_muscles` | ✅ Exists | Primary target |
| `secondary_muscles` | ✅ Exists | Secondary targets |
| `difficulty_level` | ✅ Exists | Integer 1-10 |
| `strength_rating` | ✅ Exists | Integer 1-10 |
| `hypertrophy_rating` | ✅ Exists | Integer 1-10 |
| `endurance_rating` | ✅ Exists | Integer 1-10 |
| `fat_loss_rating` | ✅ Exists | Integer 1-10 (added recently) |
| `general_fitness_rating` | ✅ Exists | Integer 1-10 (added recently) |
| `is_compound` | ✅ Exists | Boolean (added recently) |
| `supersetable` | ✅ Exists | Boolean (added recently) |
| `fatigability` | ✅ Exists | Integer 1-10 |
| `optimal_rep_range_min` | ✅ Exists | Integer |
| `optimal_rep_range_max` | ✅ Exists | Integer |
| `home_gym_friendly` | ✅ Exists | Boolean |
| `movement_pattern` | ✅ Exists | TEXT (mostly NULL - needs population) |
| `force_type` | ✅ Exists | Push/Pull |
| `movement_type` | ✅ Exists | Compound/Isolation |
| `body_position` | ✅ Exists | Standing/Seated/etc |
| `placement_in_workout` | ✅ Exists | Early/Middle/Late |

### 🆕 NEW Columns to Add

| Column | Type | Purpose |
|--------|------|---------|
| `exercise_family` | TEXT | Movement family key (e.g., `bicep_curl`, `bench_press`) |
| `base_exercise_name` | TEXT | Canonical name without equipment ("Bicep Curl") |
| `complementary_families` | TEXT | Comma-separated related families |
| `is_equipment_primary` | BOOLEAN | Gold standard variant of this family |
| `equipment_category` | TEXT | Normalized: `barbell`, `dumbbell`, `cable`, `machine`, `bodyweight`, `band`, `kettlebell`, `smith_machine` |
| `duration_based` | BOOLEAN | TRUE for cardio/stretches (time tracking vs reps) |
| `recommended_sets` | INT | Default sets (4 for compounds, 3 for isolation) |
| `rest_seconds` | INT | Rest between sets (120/90/60/30) |
| `muscles_worked_count` | INT | Number of muscle groups engaged (1-6) |
| `priority_build_muscle` | INT | Sort priority 20-95 for hypertrophy goal |
| `priority_get_lean` | INT | Sort priority 50-90 for fat loss goal |
| `priority_home` | INT | Sort priority for home training |
| `priority_gym` | INT | Sort priority for gym training |

---

## SQL Migration Script

```sql
-- ============================================================================
-- EXERCISE FAMILY & SWAP SYSTEM - New Columns
-- Run this in Supabase SQL Editor
-- ============================================================================

-- Core family identification
ALTER TABLE exercises ADD COLUMN IF NOT EXISTS exercise_family TEXT;
ALTER TABLE exercises ADD COLUMN IF NOT EXISTS base_exercise_name TEXT;
ALTER TABLE exercises ADD COLUMN IF NOT EXISTS complementary_families TEXT;
ALTER TABLE exercises ADD COLUMN IF NOT EXISTS is_equipment_primary BOOLEAN DEFAULT FALSE;

-- Equipment normalization
ALTER TABLE exercises ADD COLUMN IF NOT EXISTS equipment_category TEXT;

-- Training parameters
ALTER TABLE exercises ADD COLUMN IF NOT EXISTS duration_based BOOLEAN DEFAULT FALSE;
ALTER TABLE exercises ADD COLUMN IF NOT EXISTS recommended_sets INT DEFAULT 3;
ALTER TABLE exercises ADD COLUMN IF NOT EXISTS rest_seconds INT DEFAULT 60;
ALTER TABLE exercises ADD COLUMN IF NOT EXISTS muscles_worked_count INT DEFAULT 2;

-- Context-aware priority scores
ALTER TABLE exercises ADD COLUMN IF NOT EXISTS priority_build_muscle INT DEFAULT 70;
ALTER TABLE exercises ADD COLUMN IF NOT EXISTS priority_get_lean INT DEFAULT 70;
ALTER TABLE exercises ADD COLUMN IF NOT EXISTS priority_home INT DEFAULT 50;
ALTER TABLE exercises ADD COLUMN IF NOT EXISTS priority_gym INT DEFAULT 70;

-- Indexes for fast family-based queries
CREATE INDEX IF NOT EXISTS idx_exercises_family ON exercises(exercise_family);
CREATE INDEX IF NOT EXISTS idx_exercises_equipment_cat ON exercises(equipment_category);
CREATE INDEX IF NOT EXISTS idx_exercises_priority_muscle ON exercises(priority_build_muscle DESC);
CREATE INDEX IF NOT EXISTS idx_exercises_priority_lean ON exercises(priority_get_lean DESC);
CREATE INDEX IF NOT EXISTS idx_exercises_priority_home ON exercises(priority_home DESC);
CREATE INDEX IF NOT EXISTS idx_exercises_priority_gym ON exercises(priority_gym DESC);

-- Composite indexes for common queries
CREATE INDEX IF NOT EXISTS idx_exercises_family_priority ON exercises(exercise_family, priority_build_muscle DESC);
CREATE INDEX IF NOT EXISTS idx_exercises_family_equipment ON exercises(exercise_family, equipment_category);
```

---

## Integration with Existing Swift Code

### AlternativeExerciseEngine - Upgrade Path

Your existing `AlternativeExerciseEngine.swift` uses algorithmic matching. With the new `exercise_family` column, you can do **direct database lookups**:

```swift
// BEFORE: Algorithm-based guessing
let movementPattern = inferMovementPattern(originalName)

// AFTER: Direct family lookup
func getEquipmentVariants(for exercise: Exercise) async -> [Exercise] {
    // Get all exercises in same family, sorted by priority
    let query = supabase.from("exercises")
        .select()
        .eq("exercise_family", exercise.exerciseFamily ?? "")
        .neq("id", exercise.id?.uuidString ?? "")
        .order("priority_build_muscle", ascending: false)
        .limit(10)
    
    return try await query.execute().value
}
```

### SmartExercisePairingEngine - Direct Integration

Your `complementary_families` column directly powers the "different movement" swap:

```swift
func getComplementaryExercises(for exercise: Exercise) async -> [Exercise] {
    guard let families = exercise.complementaryFamilies?.split(separator: ",") else { return [] }
    
    // Query exercises from complementary families
    let query = supabase.from("exercises")
        .select()
        .in("exercise_family", families.map { String($0).trimmingCharacters(in: .whitespaces) })
        .order("priority_build_muscle", ascending: false)
        .limit(15)
    
    return try await query.execute().value
}
```

### Smart Swap Logic (New)

```swift
func getSwapSuggestions(
    for exercise: Exercise,
    swapCount: Int,
    userGoal: String,
    userLocation: String,  // "home" or "gym"
    userEquipment: [String]
) async -> [SwapSuggestion] {
    
    let priorityColumn = userLocation == "home" ? "priority_home" : 
                         userGoal == "Build Muscle" ? "priority_build_muscle" :
                         userGoal == "Get Lean" ? "priority_get_lean" : "priority_gym"
    
    if swapCount < 3 {
        // SWAP 1-2: Same family, different equipment
        return await getEquipmentVariants(for: exercise)
            .filter { userHasEquipment($0.equipment, userEquipment) }
            .map { SwapSuggestion(exercise: $0, reason: "Same movement, different equipment", type: .equipmentVariant) }
    } else {
        // SWAP 3+: Different movement entirely
        return await getComplementaryExercises(for: exercise)
            .filter { userHasEquipment($0.equipment, userEquipment) }
            .map { SwapSuggestion(exercise: $0, reason: "Different exercise", type: .newMovement) }
    }
}
```

---

## Core Data Model Updates

Add these attributes to your `Exercise` entity in `DataModel.xcdatamodeld`:

```xml
<attribute name="exerciseFamily" optional="YES" attributeType="String"/>
<attribute name="baseExerciseName" optional="YES" attributeType="String"/>
<attribute name="complementaryFamilies" optional="YES" attributeType="String"/>
<attribute name="isEquipmentPrimary" optional="YES" attributeType="Boolean" defaultValueString="NO" usesScalarValueType="YES"/>
<attribute name="equipmentCategory" optional="YES" attributeType="String"/>
<attribute name="durationBased" optional="YES" attributeType="Boolean" defaultValueString="NO" usesScalarValueType="YES"/>
<attribute name="recommendedSets" optional="YES" attributeType="Integer 16" defaultValueString="3" usesScalarValueType="YES"/>
<attribute name="restSeconds" optional="YES" attributeType="Integer 16" defaultValueString="60" usesScalarValueType="YES"/>
<attribute name="musclesWorkedCount" optional="YES" attributeType="Integer 16" defaultValueString="2" usesScalarValueType="YES"/>
<attribute name="priorityBuildMuscle" optional="YES" attributeType="Integer 16" defaultValueString="70" usesScalarValueType="YES"/>
<attribute name="priorityGetLean" optional="YES" attributeType="Integer 16" defaultValueString="70" usesScalarValueType="YES"/>
<attribute name="priorityHome" optional="YES" attributeType="Integer 16" defaultValueString="50" usesScalarValueType="YES"/>
<attribute name="priorityGym" optional="YES" attributeType="Integer 16" defaultValueString="70" usesScalarValueType="YES"/>
```

---

## Output CSV Format Required

The AI should output a CSV with these columns (matching your existing + new):

```csv
id,exercise_family,base_exercise_name,complementary_families,is_equipment_primary,equipment_category,duration_based,recommended_sets,rest_seconds,muscles_worked_count,priority_build_muscle,priority_get_lean,priority_home,priority_gym
```

This can then be used to UPDATE your existing exercises table.
