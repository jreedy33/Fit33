# Exercise Classification Prompt - Copy This Entire Document

---

## Task Overview

I have a fitness app database with 6,749 exercises. I need you to classify each exercise to enable:
1. **Intelligent exercise swapping** (same movement, different equipment)
2. **Movement family grouping** (all curls together, all presses together)
3. **Context-aware sorting** (different priorities for home vs gym, build muscle vs get lean)
4. **Complementary exercise suggestions** ("goes well with")

## Existing Columns (Already Populated - DO NOT Output These)

These columns already exist and are populated in my database:
- `id` - UUID (I will provide this)
- `name` - Full exercise name (I will provide this)
- `equipment` - Equipment string (I will provide this)
- `workout_type` - "Strength", "Cardio", "Plyometrics", "Stretch"
- `category` - "Chest", "Back", "Legs", "Arms", "Shoulders", "Core", etc.
- `difficulty_level` - Integer 1-10
- `is_compound` - Boolean
- `supersetable` - Boolean
- `hypertrophy_rating`, `strength_rating`, `endurance_rating`, `fat_loss_rating`, `general_fitness_rating` - Integers 1-10
- `fatigability` - Integer 1-10
- `optimal_rep_range_min`, `optimal_rep_range_max` - Integers
- `movement_pattern` - "press", "pull", "squat", "hinge", "curl", etc.
- `force_type` - "Push", "Pull"
- `home_gym_friendly` - Boolean

## NEW Columns to Classify (Output These)

For each exercise, provide values for these NEW columns:

### 1. `exercise_family` (TEXT, lowercase_with_underscores)

The fundamental movement pattern this exercise belongs to. All equipment variations of the same movement share one family.

**Examples of Families:**

Upper Body Push:
- `bench_press` - Flat bench press (all equipment)
- `incline_bench_press` - Incline press variations
- `decline_bench_press` - Decline press variations
- `shoulder_press` - Overhead/military press
- `arnold_press` - Arnold press specifically
- `push_up` - Push-up variations
- `dip` - Dip variations
- `chest_fly` - Fly movements
- `tricep_pushdown` - Cable/band pushdowns
- `tricep_extension` - Overhead extensions
- `skull_crusher` - Lying tricep work
- `tricep_kickback` - Kickback variations
- `close_grip_bench_press` - Close grip bench

Upper Body Pull:
- `lat_pulldown` - Pulldown variations
- `pull_up` - Pull-up/chin-up (bodyweight)
- `bent_over_row` - Bent over rows
- `seated_cable_row` - Seated cable/machine rows
- `single_arm_row` - Single arm dumbbell rows
- `t_bar_row` - T-bar rows
- `face_pull` - Face pulls
- `shrug` - Shrug variations
- `bicep_curl` - Standard curls
- `hammer_curl` - Hammer/neutral grip curls
- `preacher_curl` - Preacher/Scott curls
- `concentration_curl` - Concentration curls
- `spider_curl` - Spider curls
- `reverse_curl` - Reverse grip curls
- `cable_curl` - Cable-specific curls
- `incline_curl` - Incline dumbbell curls

Lower Body:
- `squat` - Back/front squat
- `goblet_squat` - Goblet squat specifically
- `split_squat` - Bulgarian/split squat
- `hack_squat` - Hack squat/machine
- `leg_press` - Leg press
- `lunge` - Walking/static lunges
- `step_up` - Step-up variations
- `deadlift` - Conventional/sumo deadlift
- `romanian_deadlift` - RDL/stiff leg
- `hip_thrust` - Hip thrust
- `glute_bridge` - Glute bridge
- `leg_extension` - Quad extension
- `leg_curl` - Hamstring curl (all types)
- `calf_raise` - Calf raise variations
- `hip_abduction` - Abductor work
- `hip_adduction` - Adductor work
- `good_morning` - Good morning

Shoulders:
- `lateral_raise` - Side/lateral raises
- `front_raise` - Front raises
- `rear_delt_fly` - Reverse fly/rear delt
- `upright_row` - Upright rows
- `external_rotation` - Rotator cuff work

Core:
- `crunch` - Crunches/sit-ups
- `leg_raise` - Hanging/lying leg raises
- `plank` - Plank variations
- `side_plank` - Side plank
- `russian_twist` - Twisting movements
- `ab_rollout` - Ab wheel/rollout
- `woodchop` - Woodchop/rotation
- `back_extension` - Hyperextension
- `dead_bug` - Dead bug
- `bird_dog` - Bird dog

Cardio:
- `running` - Running/jogging
- `cycling` - Bike/cycling
- `rowing_cardio` - Rowing machine
- `jumping_jack` - Jumping jacks
- `mountain_climber` - Mountain climbers
- `burpee` - Burpees
- `box_jump` - Box jumps
- `jump_rope` - Jump rope

Stretches: Use `stretch_[bodypart]` format
- `stretch_hamstring`, `stretch_quad`, `stretch_hip`, `stretch_chest`, `stretch_shoulder`, `stretch_back`, `stretch_calf`, `stretch_tricep`, `stretch_bicep`, `stretch_neck`, `stretch_full_body`

**Rules:**
- "Barbell Bench Press" and "Dumbbell Bench Press" = BOTH `bench_press`
- "Incline Barbell Press" and "Incline Dumbbell Press" = BOTH `incline_bench_press`
- "Preacher Curl (Barbell)" and "Preacher Curl (Dumbbell)" = BOTH `preacher_curl`
- If exercise doesn't fit a specific family, use: `chest_exercise`, `back_exercise`, `leg_exercise`, `shoulder_exercise`, `arm_exercise`, `core_exercise`

### 2. `base_exercise_name` (TEXT, Title Case)

The canonical name without equipment specification.

**Examples:**
- "Barbell Bench Press" → "Bench Press"
- "Dumbbell Bicep Curl" → "Bicep Curl"
- "Cable Lat Pulldown" → "Lat Pulldown"
- "Machine Leg Press" → "Leg Press"
- "Incline Dumbbell Press" → "Incline Press"
- "Seated Cable Row" → "Seated Row"
- "Preacher Curl (EZ Bar)" → "Preacher Curl"

### 3. `complementary_families` (TEXT, comma-separated)

2-5 exercise families that pair well with this exercise. Consider:
- Same muscle group variations
- Antagonist pairs (biceps ↔ triceps, chest ↔ back)
- Compound → isolation progressions
- Superset partners

**Standard Pairings Reference:**
```
bench_press → incline_bench_press, chest_fly, tricep_pushdown, dip
incline_bench_press → bench_press, chest_fly, shoulder_press
shoulder_press → lateral_raise, front_raise, tricep_extension
lat_pulldown → bent_over_row, pull_up, bicep_curl, face_pull
bent_over_row → lat_pulldown, face_pull, bicep_curl, rear_delt_fly
pull_up → lat_pulldown, bent_over_row, bicep_curl
bicep_curl → hammer_curl, preacher_curl, tricep_extension
hammer_curl → bicep_curl, reverse_curl, preacher_curl
tricep_pushdown → tricep_extension, skull_crusher, dip
squat → leg_press, leg_extension, lunge, leg_curl
deadlift → romanian_deadlift, bent_over_row, hip_thrust
leg_press → squat, leg_extension, leg_curl
leg_curl → romanian_deadlift, hip_thrust, glute_bridge
hip_thrust → glute_bridge, leg_curl, romanian_deadlift
lunge → squat, step_up, split_squat
lateral_raise → shoulder_press, front_raise, rear_delt_fly
chest_fly → bench_press, incline_bench_press
crunch → leg_raise, plank, russian_twist
plank → crunch, dead_bug, back_extension
```

### 4. `is_equipment_primary` (BOOLEAN)

TRUE if this is the "gold standard" version of the family. Only ONE exercise per family should be TRUE.

**Rules:**
- **Barbell** is primary for: bench_press, squat, deadlift, bent_over_row, shoulder_press, romanian_deadlift
- **Dumbbell** is primary for: bicep_curl, hammer_curl, lateral_raise, front_raise, chest_fly, incline_curl, tricep_kickback, shrug
- **Cable** is primary for: lat_pulldown, tricep_pushdown, seated_cable_row, face_pull, cable_curl
- **Machine** is primary for: leg_press, leg_extension, leg_curl, hip_abduction, hip_adduction
- **Bodyweight** is primary for: pull_up, push_up, dip, plank, crunch, burpee

### 5. `equipment_category` (TEXT, lowercase)

Normalized equipment type. Values: `barbell`, `dumbbell`, `cable`, `machine`, `bodyweight`, `band`, `kettlebell`, `smith_machine`

**Detection Rules:**
- Name contains "Barbell" or "(Barbell)" → `barbell`
- Name contains "Dumbbell" or "(Dumbbell)" → `dumbbell`
- Name contains "Cable" or "(Cable)" → `cable`
- Name contains "Band" or "Resistance Band" → `band`
- Name contains "Kettlebell" or "(Kettlebell)" → `kettlebell`
- Name contains "Smith Machine" or "Smith" → `smith_machine`
- Name contains "Machine", "Lever", "Sled", or equipment field indicates machine → `machine`
- Name contains "Bodyweight" or equipment field is empty/Bodyweight → `bodyweight`
- EZ Bar, Trap Bar → `barbell`
- TRX, Suspension → `bodyweight`

### 6. `duration_based` (BOOLEAN)

TRUE if exercise should be tracked by time rather than reps.

**Rules:**
- All stretches → TRUE
- All cardio (running, cycling, rowing machine, etc.) → TRUE
- Planks, wall sits, holds → TRUE
- Everything else → FALSE

### 7. `recommended_sets` (INT)

Default number of sets.
- Heavy compounds (squat, deadlift, bench_press) → 4
- Standard compounds → 3-4
- Isolation exercises → 3
- Stretches → 1
- Cardio → 1
- Plyometrics → 3

### 8. `rest_seconds` (INT)

Recommended rest between sets.
- Heavy compounds (squat, deadlift, cleans) → 120
- Standard compounds (bench, row, press) → 90
- Isolation exercises → 60
- Plyometrics → 60
- Stretches → 30
- Cardio → 60

### 9. `muscles_worked_count` (INT)

How many major muscle groups are engaged. 1-6 scale.
- Full body (burpee, clean, thruster) → 6
- Deadlift, squat → 5
- Bench press, rows, shoulder press → 4
- Lunges, dips → 3
- Isolation (curls, raises, extensions) → 2
- Single muscle focus (wrist curls) → 1

### 10. `priority_build_muscle` (INT, 20-95)

Sort priority for "Build Muscle" goal. Higher = suggest first.

**Equipment-Based Scoring:**
- Barbell → 95 (heaviest loading, best for strength/size)
- Dumbbell → 92 (excellent muscle activation, unilateral)
- Cable → 85 (constant tension)
- Machine → 80 (safe progressive loading)
- Kettlebell → 78
- Smith Machine → 75
- Bodyweight → 72 (limited loading)
- Band → 60 (variable/limited resistance)

**Adjustments:**
- Compound exercises: +0 to +5
- Isolation exercises: -5 to 0
- is_equipment_primary = TRUE: +3

### 11. `priority_get_lean` (INT, 50-90)

Sort priority for "Get Lean" goal. Emphasizes metabolic/circuit training.

**Equipment-Based Scoring:**
- Dumbbell → 90 (circuit-friendly, quick transitions)
- Bodyweight → 88 (always available, superset-friendly)
- Cable → 85 (sustained work)
- Band → 85 (metabolic conditioning)
- Kettlebell → 85 (great for conditioning)
- Barbell → 78 (requires more setup)
- Machine → 75
- Smith Machine → 70

### 12. `priority_home` (INT, 20-95)

Sort priority for home training. Based on equipment availability.

**Equipment-Based Scoring:**
- Bodyweight → 95 (always available)
- Dumbbell → 92 (most common home equipment)
- Band → 90 (portable, accessible)
- Kettlebell → 85
- Barbell → 65 (less common at home)
- Cable → 30 (rare at home)
- Smith Machine → 25
- Machine → 20 (uncommon at home)

### 13. `priority_gym` (INT, 50-95)

Sort priority for gym training. Maximizes gym equipment usage.

**Equipment-Based Scoring:**
- Barbell → 95 (use the rack!)
- Cable → 92 (take advantage of cable stations)
- Dumbbell → 90
- Machine → 88 (use available machines)
- Smith Machine → 82
- Kettlebell → 78
- Bodyweight → 65 (doesn't need gym)
- Band → 50 (brought from home)

---

## Output Format

Return a CSV with these columns in this exact order:

```csv
id,exercise_family,base_exercise_name,complementary_families,is_equipment_primary,equipment_category,duration_based,recommended_sets,rest_seconds,muscles_worked_count,priority_build_muscle,priority_get_lean,priority_home,priority_gym
```

**Example Output:**
```csv
abc123,bench_press,Bench Press,"incline_bench_press,chest_fly,tricep_pushdown,dip",TRUE,barbell,FALSE,4,90,4,95,78,65,95
def456,bench_press,Bench Press,"incline_bench_press,chest_fly,tricep_pushdown,dip",FALSE,dumbbell,FALSE,4,90,4,92,90,92,90
ghi789,bicep_curl,Bicep Curl,"hammer_curl,preacher_curl,tricep_extension",TRUE,dumbbell,FALSE,3,60,2,92,90,92,90
jkl012,bicep_curl,Bicep Curl,"hammer_curl,preacher_curl,tricep_extension",FALSE,barbell,FALSE,3,60,2,95,78,65,95
mno345,lat_pulldown,Lat Pulldown,"bent_over_row,pull_up,bicep_curl,face_pull",TRUE,cable,FALSE,3,60,3,85,85,30,92
pqr678,squat,Squat,"leg_press,leg_extension,lunge,leg_curl",TRUE,barbell,FALSE,4,120,5,95,78,65,95
stu901,plank,Plank,"crunch,dead_bug,back_extension",TRUE,bodyweight,TRUE,1,30,3,72,88,95,65
vwx234,stretch_hamstring,Hamstring Stretch,"stretch_hip,stretch_calf,stretch_back",TRUE,bodyweight,TRUE,1,30,1,40,60,95,50
```

---

## Edge Cases

1. **Incline/Decline variants** → Separate families (`incline_bench_press` not `bench_press`)
2. **Wide/Close grip variants** → Same family unless fundamentally different movement
3. **Single arm/leg variants** → Same family (Single Arm Row = `single_arm_row` or `bent_over_row` if similar)
4. **Pause/Tempo variants** → Same family
5. **Assisted versions** → Same family (Assisted Pull-up = `pull_up`)
6. **Weighted bodyweight** → Same family (Weighted Dip = `dip`)
7. **Stretches** → Always `stretch_[bodypart]` format
8. **Unknown exercises** → Use body part: `chest_exercise`, `back_exercise`, etc.

---

## Data I'm Providing

I will give you exercises in this format:
```
id,name,equipment
```

Process each one and return the 13 classification columns.

---

## BEGIN PROCESSING:

[PASTE YOUR EXERCISE DATA HERE - id,name,equipment columns only]
