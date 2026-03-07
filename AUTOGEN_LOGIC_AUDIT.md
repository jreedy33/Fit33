# Fit33 AutoGen Logic & Recommendation Engine - Comprehensive Audit

**Date:** March 7, 2026
**Scope:** Exercise filtering, workout auto-generation, program recommendation, gender video logic, equipment filters
**Files Audited:** 15+ core files across data, filtering, generation, and recommendation layers

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Equipment Filtering Audit (Dumbbell, Barbell, etc.)](#2-equipment-filtering-audit)
3. [Gender / Video Filtering Audit (Male vs Female)](#3-gender--video-filtering-audit)
4. [Workout Auto-Generation Audit](#4-workout-auto-generation-audit)
5. [Program Recommendation Audit](#5-program-recommendation-audit)
6. [User Profile / Preferences Integration Audit](#6-user-profile--preferences-integration-audit)
7. [Limitation / Injury Filtering Audit](#7-limitation--injury-filtering-audit)
8. [Exercise Data Pipeline Audit](#8-exercise-data-pipeline-audit)
9. [Critical Bugs Found](#9-critical-bugs-found)
10. [Recommendations & Action Items](#10-recommendations--action-items)

---

## 1. Architecture Overview

### Data Flow
```
User Profile (UserManager)
        |
        v
Exercise Data Sources:
  - exercises.json (ExerciseDataProvider - ~7000+ exercises)
  - Core Data (ExerciseLibraryService)
  - Supabase (ExerciseIntelligenceEngine)
        |
        v
Filtering Layer:
  - ExerciseFilterService (equipment normalization, category mapping)
  - GenderFilterService (male/female video selection)
  - LimitationFilterEngine (injury-based exercise exclusion)
  - WorkoutEnvironmentService (gym/home/outdoor scoring)
        |
        v
Generation Layer:
  - WorkoutGeneratorService (primary auto-gen path)
  - IntelligentWorkoutGenerator (legacy + intelligence engine path)
  - SmartExerciseSelectionEngine (program day exercise selection)
        |
        v
Program Layer:
  - SmartProgramEngine (10 program templates, lazy day generation)
  - SmartProgramRecommender (program scoring & recommendation)
  - WorkoutProgramEngine (program catalog)
```

### Key Files Audited

| File | Role | Lines |
|------|------|-------|
| `ExerciseFilterService.swift` | Equipment normalization, category mapping | ~1,153 |
| `GenderFilterService.swift` | Gender-based video routing | ~394 |
| `LimitationFilterEngine.swift` | Injury/limitation exercise filtering | ~662 |
| `WorkoutGeneratorService.swift` | Primary workout auto-generation | ~3,800+ |
| `IntelligentWorkoutGenerator.swift` | Secondary workout generation | ~668 |
| `SmartProgramEngine.swift` | Program templates & day generation | ~2,200+ |
| `SmartProgramRecommender.swift` | Program recommendation scoring | ~520 |
| `ExerciseIntelligenceEngine.swift` | Advanced exercise intelligence | ~500+ |
| `SmartExerciseSelectionEngine.swift` | Program day exercise selection | ~1,827 |
| `ExerciseDataProvider.swift` | JSON exercise data loader | ~137 |
| `ExerciseMappingService.swift` | Substitution/pairing maps | ~545 |
| `WorkoutEnvironmentService.swift` | Gym/home/outdoor scoring | ~270 |
| `VideoStreamingService.swift` | Video streaming + gender cache | ~950+ |
| `UserManager.swift` | User profile management | ~405+ |

---

## 2. Equipment Filtering Audit

### How Equipment Filtering Works

**Entry Point:** `ExerciseFilterService.normalizeEquipment()` (line 652)

The system normalizes raw equipment strings from the database (e.g., `"Dumbbells, Incline Bench"`) into simplified user-facing categories (`"Dumbbells"`). This normalization is used in 30+ locations across the codebase.

**Normalization Priority Order:**
1. Bodyweight / Body Weight
2. Band / TRX / Suspension
3. Cable
4. Smith Machine
5. Lever / Machine
6. EZ Bar / EZ-Bar
7. Barbell / Olympic Bar
8. Dumbbell
9. Kettlebell
10. Stability Ball / Medicine Ball / Bosu
11. Bench (standalone)
12. Resistance (bands)
13. Default: "Other"

### Equipment Bugs Found

#### BUG E-1: Keyword Collision with "row" (HIGH)
**File:** `ExerciseFilterService.swift:675`

An exercise with equipment `"dumbbell row machine"` hits the dumbbell check first and returns `"Dumbbells"`, never reaching the row machine check. The exercise is incorrectly categorized as requiring only Dumbbells.

**Impact:** Users filtering by "Dumbbells" may see exercises that actually require a row machine.

#### BUG E-2: Combined Equipment Silently Skipped (HIGH)
**File:** `ExerciseFilterService.swift` (`userHasRequiredEquipment`)

`"incline bench"` is in the `commonItems` set, causing it to be skipped during validation. An exercise requiring `"Dumbbells, Incline Bench"` passes the filter even if the user does NOT have a bench.

**Impact:** Home users without a bench could see incline bench exercises.

#### BUG E-3: "Resistance" Keyword Overlap (MEDIUM)
**File:** `ExerciseFilterService.swift:701`

Equipment like `"Resistance Machine"` returns `"Bands"` instead of `"Machines"` because `equipment.contains("resistance")` matches before the machine checks.

**Impact:** Machine exercises with "resistance" in the name get categorized as band exercises.

#### BUG E-4: Non-Deterministic Normalization (MEDIUM)
**File:** `ExerciseFilterService.swift`

`"Dumbbell, Barbell, or Bodyweight"` returns `"Dumbbells"` (first match), while `"Barbell, Dumbbell"` returns `"Barbell"`. Result depends on string order.

**Impact:** Identical exercises with different equipment string orderings get different normalized categories.

#### BUG E-5: SmartExerciseSelectionEngine Equipment False Positive (MEDIUM)
**File:** `SmartExerciseSelectionEngine.swift:202-206`

```swift
if part.contains(pattern) || pattern.contains(part) {
    return true
}
```

Bidirectional `contains` check creates false matches (e.g., pattern `"able"` matches part `"table"`).

**Impact:** Exercises could pass equipment filter when they shouldn't.

#### BUG E-6: Program Templates Missing Equipment Requirements (MEDIUM)
**File:** `SmartProgramEngine.swift:756`

Programs converted from `MasterProgramTemplate` have `equipmentRequirements: []` (empty array). Equipment matching in `calculateMatchScore()` always scores partial/no match.

**Impact:** Program recommendations don't properly account for user's available equipment.

### Equipment Filtering - What Works Correctly

- Dumbbell exercises generally return correct exercises when user selects "Dumbbells"
- Barbell exercises generally return correct exercises when user selects "Barbell"
- Bodyweight exercises correctly show for all users
- Cable/Machine exercises correctly map to gym environments
- Equipment scoring in workout generation properly prioritizes user's available equipment

---

## 3. Gender / Video Filtering Audit

### How Gender Video Filtering Works

**Flow:**
```
User Gender (UserManager.gender)
     |
     v
GenderFilterService.preferredGender (loads from UserDefaults)
     |
     v
VideoStreamingService.genderVideoCache (maps exercise -> male/female filenames)
     |
     v
Video URL selection with fallback to opposite gender
```

**Gender Preference Loading Priority:**
1. `UserDefaults["preferredVideoGender"]`
2. `UserDefaults["userGender"]`
3. `UserManager.shared.currentUser.gender`
4. Default: `.male`

### Gender Video - What Works Correctly

- `GenderFilterService` properly loads gender preference from multiple sources
- `ExerciseGenderInfo` struct correctly tracks male/female video availability per exercise
- `videoFilename(for:withFallback:)` correctly tries preferred gender first, then falls back
- Video caches are properly cleared when gender preference changes
- `NotificationCenter` correctly broadcasts gender preference changes

### Gender Bugs Found

#### BUG G-1: `shouldShowExercise()` Always Returns True (HIGH)
**File:** `GenderFilterService.swift:112-133`

```swift
func shouldShowExercise(_ exerciseName: String) -> Bool {
    // ...
    if info.isAvailable(for: preferredGender) { return true }
    if info.isAvailable(for: preferredGender.opposite) && !info.hasBothGenders { return true }
    return true  // <-- ALWAYS TRUE
}
```

Every code path returns `true`. The function never actually filters out any exercise. This means a female user will see exercises that ONLY have male videos with no fallback logic applied at the exercise-selection level.

**Impact:** No exercises are ever hidden based on gender. The function is effectively a no-op.

#### BUG G-2: `filterExercises()` and `filterGeneratedExercises()` Are No-Ops (HIGH)
**File:** `GenderFilterService.swift:272-281`

```swift
func filterExercises(_ exercises: [Exercise]) -> [Exercise] {
    return exercises  // No filtering!
}

func filterGeneratedExercises(_ exercises: [GeneratedExercise]) -> [GeneratedExercise] {
    return exercises  // No filtering!
}
```

These methods are documented as "the main filtering function used by views" but they pass through all exercises unfiltered.

**Impact:** Views that call these functions expecting gender-filtered results get ALL exercises regardless of gender.

#### BUG G-3: Gender Ignored in Exercise Selection Engines (HIGH)
**File:** `SmartExerciseSelectionEngine.swift` (entire file)

The SmartExerciseSelectionEngine has **zero references** to gender, female, male, or any gender-based filtering. All users receive identical exercise recommendations regardless of gender.

**Impact:** Program day generation doesn't consider gender at all. A female user gets identical exercise selections as a male user.

#### BUG G-4: Gender Default to Male When Nil (MEDIUM)
**File:** `SmartProgramEngine.swift:1500`

```swift
let userGender = user.gender?.lowercased() ?? "male"
```

If gender is nil (user didn't set it), the system defaults to male. This only affects weight recommendations (30% reduction for female), not exercise selection.

**Impact:** Users who skip gender selection get male-oriented weight suggestions.

#### BUG G-5: Gender Video Cache Default Boosts Exercises Without Videos (MEDIUM)
**File:** `WorkoutGeneratorService.swift:1242-1252`

```swift
var genderMatches = true // Default to true if no video info
if let genderInfo = genderVideoCache[exerciseKey] {
    genderMatches = genderInfo.filename(for: preferredVideoGender) != nil
}
if genderMatches {
    score += 200  // Massive boost
}
```

Exercises with NO video data at all get a +200 gender match bonus by default. This artificially boosts exercises that have no video instruction.

**Impact:** Exercises without videos get unfair priority over exercises with proper gender-matched videos.

#### BUG G-6: Gender Syncing Race Condition (LOW)
**File:** Multiple files

`UserManager`, `VideoStreamingService`, and `GenderFilterService` all independently store/load gender preferences from `UserDefaults` with different keys:
- `"preferredVideoGender"` (GenderFilterService)
- `"userGender"` (UserManager)

If these get out of sync, the system may show wrong-gender videos.

### Gender Summary

| Aspect | Status | Notes |
|--------|--------|-------|
| Male user sees male videos | WORKS | Via VideoStreamingService gender cache |
| Female user sees female videos | PARTIAL | Videos route correctly, but exercises aren't filtered |
| Exercise filtering by gender | BROKEN | `shouldShowExercise()` always returns true |
| Exercise selection by gender | MISSING | SmartExerciseSelectionEngine ignores gender |
| Program generation by gender | MINIMAL | Only 30% weight reduction for females |
| Gender fallback to opposite | WORKS | If preferred gender video unavailable, shows opposite |
| Gender preference persistence | WORKS | Saved to UserDefaults, synced to VideoStreamingService |

---

## 4. Workout Auto-Generation Audit

### Generation Paths (Priority Order)

1. **Primary: `generateFromCoreData()`** - Queries Core Data, applies scoring
2. **Fallback 1: `generateLocalWorkout()`** - Uses ExerciseDataProvider JSON
3. **Fallback 2: Supabase Edge Function** - Cloud-based generation

### How Exercise Scoring Works (Primary Path)

Base score starts at 100. Key scoring factors:

| Factor | Points | Direction |
|--------|--------|-----------|
| Gender video match | +200 / -150 | Boost/Penalty |
| Popularity boost | Variable | Boost |
| Favorite-based discovery | Variable | Boost |
| Skill level match | +100 to -300 | Both |
| Environment fit | Variable | Both |
| Obscure exercise penalty | -250 | Penalty |
| Movement signature duplicate | -100 | Penalty |
| Pattern balance | -20 per duplicate | Penalty |
| Primary muscle match | +30 | Boost |
| Compound early in workout | +50 | Boost |
| Randomness | 0-15 | Variety |

### Workout Generation Bugs Found

#### BUG W-1: Muscle Filtering with Empty Data (CRITICAL)
**File:** `WorkoutGeneratorService.swift:912`

```swift
let matchesMuscle = primaryMuscleMatchesTarget ||
    (categoryMatchesTarget && exercisePrimaryMuscle.isEmpty)
```

Exercises with NO primary muscle data pass the filter if the category matches. This could include wrong exercises in the workout.

**Impact:** Exercises with missing muscle metadata can appear in workouts for muscles they don't target.

#### BUG W-2: Triceps Gate "assist"/"chip" Typo (HIGH)
**File:** `WorkoutGeneratorService.swift:2043`

```swift
(n.contains("dip") && !n.contains("assist") && !n.contains("chip"))
```

- `"assist"` won't catch `"assisted dip"` (needs `"assisted"`)
- `"chip"` exclusion is nonsensical - likely a typo

**Impact:** Triceps dip exercises may leak into non-arm workouts.

#### BUG W-3: Vertical Press Cap Applied Twice (LOW)
**File:** `WorkoutGeneratorService.swift:2797-2806 AND 2858-2862`

The vertical press cap check is duplicated (copy-paste error). The second check is dead code.

#### BUG W-4: Muscle Diversity Max Calculation Off-by-One (HIGH)
**File:** `WorkoutGeneratorService.swift:2627`

```swift
let maxPerMuscle = max(2, Int(ceil(Double(count) / Double(max(1, normalizedTargetMuscles.count)))) + 1)
```

For a 6-exercise back workout with 1 target muscle: `ceil(6/1) + 1 = 7`. This allows 7 exercises for 1 muscle in a 6-exercise workout. The `+ 1` causes the cap to exceed the total exercise count.

**Impact:** Single-muscle workouts may lack exercise variety.

#### BUG W-5: Row Detection False Positive (MEDIUM)
**File:** `WorkoutGeneratorService.swift:2673`

```swift
if (nameLower.contains(" row") || nameLower.hasPrefix("row")) && !nameLower.contains("upright") { return "row" }
```

"Smith Upright Row" bypasses the upright row exclusion because `!nameLower.contains("upright")` is checked after the initial match. The logic should use `!nameLower.contains("upright row")` to check the full phrase.

### Workout Generation - What Works Correctly

- Exercise count scaling by duration (4-8 exercises for 15-60+ minutes)
- Compound-first ordering in generated workouts
- Movement pattern diversity enforcement
- Equipment matching in Core Data queries
- Fallback chain (Core Data -> JSON -> Cloud) provides resilience
- Favorite-based discovery engine adds personalization
- Obscure exercise penalty prevents weird exercises from appearing
- Skill level matching (beginner/intermediate/advanced) properly adjusts complexity

---

## 5. Program Recommendation Audit

### How Program Recommendation Works

**Entry Point:** `SmartProgramRecommender.getTopRecommendedPrograms(for:)`

**Scoring System (max ~400 points):**

| Factor | Max Points | Notes |
|--------|-----------|-------|
| Experience level match | 80 | Perfect match = 80, adjacent = 30-50, mismatch = -40 |
| Goal alignment | 100 | Maps program focus to user goal |
| Equipment compatibility | 60 | Ratio of matched equipment |
| Available days match | 40 | Perfect = 40, off by 1 = 25, off by 2 = 10 |
| Program duration preference | 20 | Based on experience level |
| Age considerations | 20 | 50+ prefers lower intensity, <30 handles more |
| Training age adjustment | 30 | Novice strongly prefers beginner programs |

### Program Templates (10 Programs)

| Program | Category | Days | Difficulty | Equipment | Goal |
|---------|----------|------|------------|-----------|------|
| Foundation Builder | Foundation | 21 | Beginner | Bodyweight | General |
| Foundation Plus | Foundation | 28 | Intermediate | Dumbbells | Build Muscle |
| Foundation Elite | Foundation | 42 | Advanced | Barbell+DB | Build Muscle |
| Classic PPL | Push/Pull/Legs | 42 | Intermediate | DB+Barbell | Build Muscle |
| Upper/Lower Power | Upper/Lower | 28 | Intermediate | Dumbbells | Build Muscle |
| Strength Foundations | Strength | 28 | Intermediate | Barbell+DB | Get Stronger |
| Strength Advanced | Strength | 42 | Advanced | BB+DB+Machines | Get Stronger |
| 30-Day Shred | Shred | 30 | Intermediate | Bodyweight+DB | Lose Weight |
| Full Body 3x | Full Body | 28 | Beginner | Bodyweight | General |
| Athletic Performance | Athletic | 35 | Intermediate | DB+Bodyweight | Get Fit |

### Program Recommendation - What Works Correctly

- Goal alignment scoring properly maps user goals to program focuses
- Experience level matching works correctly with adjacent-level allowances
- Equipment compatibility calculation properly uses set intersection
- Age-based adjustments are reasonable (50+ gets lower intensity preference)
- Training age adjustment adds proper nuance beyond just experience level
- Available days matching gives appropriate score gradients
- Fallback program prevents crashes when no programs are available
- Progressive series (Foundation 1->2->3) properly enforces prerequisites

### Program Recommendation Bugs Found

#### BUG P-1: Goal String Matching is Fragile (MEDIUM)
**File:** `SmartProgramEngine.swift:645-649`

```swift
if (userGoal == "muscle/strong/mass/size") && newTemplate.goalTrack == .gain {
    matchScore += 0.35
}
```

This compares the user's goal against slash-separated keyword strings. If the user's goal is `"Build Muscle"` (from onboarding), it won't match `"muscle/strong/mass/size"`. The matching should use `contains` or a mapping.

**Impact:** Programs may not properly align with user goals.

#### BUG P-2: No Program History Consideration (LOW)
Programs the user has already completed are not deprioritized. User could be recommended the same program repeatedly.

#### BUG P-3: Fat Loss Goal Mapping Incomplete (MEDIUM)
**File:** `SmartProgramRecommender.swift:233-240`

```swift
case .fatLoss:
    switch programFocus {
    case .endurance, .fullBody: return 80
    case .bodyweight: return 70
    default: return 20
    }
```

The `fatLoss` goal gives 80 points to `endurance` and `fullBody` but only 20 to `hypertrophy`. In practice, hypertrophy training is highly effective for fat loss (muscle burns more calories), so this scoring may not produce optimal recommendations.

---

## 6. User Profile / Preferences Integration Audit

### User Profile Properties Used in Generation

| Property | Used In | How It's Used |
|----------|---------|---------------|
| `gender` | WorkoutGeneratorService, SmartProgramEngine | Video selection, weight recommendation |
| `fitnessGoal` | SmartProgramRecommender, WorkoutGeneratorService | Program scoring, split selection |
| `experienceLevel` | SmartProgramRecommender, IntelligentWorkoutGenerator | Difficulty filtering, scoring |
| `equipment` | WorkoutGeneratorService, SmartProgramEngine | Equipment filtering |
| `availableDays` | SmartProgramRecommender | Days/week matching |
| `workoutEnvironment` | WorkoutEnvironmentService | Gym/home/outdoor scoring |
| `age` | SmartProgramRecommender | Intensity preferences |

### User Profile Bugs Found

#### BUG U-1: Equipment Stored as NSObject (MEDIUM)
**File:** `UserManager.swift:178`

```swift
equipment: equipment as NSObject
```

Storing array as NSObject is fragile. If the cast fails silently, equipment defaults to nil and the user gets bodyweight-only exercises.

#### BUG U-2: Equipment Defaults to ["Bodyweight"] When Nil (MEDIUM)
**File:** `SmartProgramEngine.swift:2135`

If no equipment is specified, falls back to `["Bodyweight"]`. Users with nil equipment always get bodyweight exercises even if they should have gym access.

#### BUG U-3: Workout Environment Not Connected to Filtering (LOW)
**File:** `UserManager.swift`

The `workoutEnvironment` property is set during onboarding but not consistently used in all generation paths. The `WorkoutEnvironmentService` provides scoring, but the `generateLocalWorkout()` fallback path doesn't apply it.

---

## 7. Limitation / Injury Filtering Audit

### How Limitation Filtering Works

**Engine:** `LimitationFilterEngine` - pure function, metadata-driven (no hardcoded exercise names)

**Supported Limitation Areas:**
Lower Back, Shoulders, Knees, Hips, Neck, Wrists, Elbows, Ankles, Upper Back, Pregnancy, Other

**Severity Levels:**
1. **Skip Completely** - Excludes high-risk exercises entirely
2. **Stretching Only** - Only allows stretch/mobility exercises
3. **Light Work Only** - Excludes heavy/compound, allows safe variations
4. **Be Careful** - Penalizes risky options, prefers safer alternatives

### Limitation Filtering - What Works Correctly

- Metadata-driven approach (no hardcoded exercise names) is excellent architecture
- Risk metadata covers all major dimensions (spinal load, axial loading, overhead work, knee flexion, etc.)
- Severity-based logic properly graduates from "be careful" to "skip completely"
- Rule tables are extensible per body area
- `FilteredExercise` provides clear exclusion reasons for UI display
- Penalty scoring system allows gradual deprioritization rather than binary include/exclude
- Pregnancy handling considers impact, spinal load, balance, and prone positions

### Limitation Filtering - Gaps

- The `ExerciseRiskMetadata` must be provided externally via `metadataProvider` closure. If exercises lack risk metadata, they default to `.safe` and bypass all limitation filtering
- No integration with `SmartExerciseSelectionEngine` (which has its own separate lower-back checks)
- The `LimitationsService.shared.filterSafeExercises()` called by SmartExerciseSelectionEngine may not use the same rules as LimitationFilterEngine

---

## 8. Exercise Data Pipeline Audit

### Data Sources

1. **exercises.json** (bundled) - ~7,000+ exercises loaded by `ExerciseDataProvider`
2. **Core Data** (local) - Populated from Supabase, queried by `ExerciseLibraryService`
3. **Supabase** (remote) - ~6,500 exercises loaded by `ExerciseIntelligenceEngine`

### Exercise Data Model (`ExerciseData`)

```swift
struct ExerciseData {
    let name: String
    let category: String          // "Chest", "Back", "Legs", etc.
    let primaryBodyRegion: String  // "Upper Body", "Lower Body", etc.
    let primaryMuscle: String      // "Pectorals", "Lats", etc.
    let secondaryMuscles: [String]
    let equipment: String          // "Barbell", "Dumbbell", etc.
    let instructions: String?
    let muscleGroups: [String]     // Additional muscle targets
}
```

### Data Pipeline Issues

#### BUG D-1: Inconsistent Equipment Naming Across Sources (MEDIUM)
- exercises.json may use `"Dumbbell"` while Supabase uses `"Dumbbells"`
- Core Data may store `"Cable Machine"` while JSON uses `"Cable"`
- `normalizeEquipment()` handles most cases but edge cases exist

#### BUG D-2: Missing Muscle Data in Some Exercises (MEDIUM)
Some exercises in the database have empty `primaryMuscle` fields. These exercises can bypass muscle-targeting filters (see Bug W-1).

#### BUG D-3: Category/Muscle Mapping Inconsistencies (LOW)
The `categoryMapping` in `generateLocalWorkout()` maps user selections to categories:
```swift
"biceps": "arms",
"triceps": "arms",
```
But the conflict check then blocks exercises with "bicep" or "tricep" in the name when "arms" isn't selected. This correctly prevents arm-specific exercises from leaking, but means selecting "Arms" gives both bicep and tricep exercises with no way to isolate one.

---

## 9. Critical Bugs Found - Priority Summary

### P0 - Must Fix (Breaks Core Functionality)

| # | Bug | File | Impact |
|---|-----|------|--------|
| G-1 | `shouldShowExercise()` always returns true | GenderFilterService:112 | Gender filtering is completely non-functional |
| G-2 | `filterExercises()` is a no-op | GenderFilterService:272 | No exercises are ever filtered by gender |
| G-3 | SmartExerciseSelectionEngine ignores gender | SmartExerciseSelectionEngine | Program exercises not gender-appropriate |
| W-1 | Empty muscle data bypasses filter | WorkoutGeneratorService:912 | Wrong exercises can appear in workouts |

### P1 - High Priority (Causes Incorrect Results)

| # | Bug | File | Impact |
|---|-----|------|--------|
| E-1 | Equipment "row" keyword collision | ExerciseFilterService:675 | Wrong equipment categorization |
| E-2 | Combined equipment skips bench | ExerciseFilterService | Users without bench see bench exercises |
| W-2 | Triceps gate typo "assist"/"chip" | WorkoutGeneratorService:2043 | Triceps leak into non-arm workouts |
| W-4 | Muscle diversity max off-by-one | WorkoutGeneratorService:2627 | Single-muscle workouts lack variety |
| G-5 | No-video exercises get gender bonus | WorkoutGeneratorService:1242 | Exercises without videos unfairly prioritized |
| P-1 | Goal string matching fragile | SmartProgramEngine:645 | Programs don't align with user goals |

### P2 - Medium Priority (Suboptimal but Functional)

| # | Bug | File | Impact |
|---|-----|------|--------|
| E-3 | "Resistance" keyword overlap | ExerciseFilterService:701 | Machine exercises miscategorized as bands |
| E-4 | Non-deterministic normalization | ExerciseFilterService | Same equipment, different categories |
| E-5 | Equipment bidirectional contains | SmartExerciseSelectionEngine:202 | False positive equipment matches |
| E-6 | Program templates missing equipment | SmartProgramEngine:756 | Program recommendations ignore equipment |
| G-4 | Gender defaults to male when nil | SmartProgramEngine:1500 | Unset users get male weight suggestions |
| G-6 | Gender syncing race condition | Multiple files | Possible wrong-gender videos |
| W-5 | Row detection false positive | WorkoutGeneratorService:2673 | Upright rows misclassified |
| P-3 | Fat loss goal mapping incomplete | SmartProgramRecommender:233 | Suboptimal fat loss recommendations |
| U-1 | Equipment stored as NSObject | UserManager:178 | Fragile type casting |
| U-2 | Equipment defaults to bodyweight | SmartProgramEngine:2135 | Nil equipment = bodyweight only |

### P3 - Low Priority (Minor Issues)

| # | Bug | File | Impact |
|---|-----|------|--------|
| W-3 | Vertical press cap duplicated | WorkoutGeneratorService:2797 | Dead code, no functional impact |
| U-3 | Environment not in all paths | UserManager | Inconsistent environment application |
| P-2 | No program history | SmartProgramRecommender | Same program recommended repeatedly |
| D-3 | Category/muscle mapping limits | WorkoutGeneratorService | Can't isolate biceps from triceps |

---

## 10. Recommendations & Action Items

### Immediate Fixes (P0)

1. **Fix Gender Filter Functions** (`GenderFilterService.swift`)
   - `shouldShowExercise()` should return `false` when the exercise only has opposite-gender video AND an alternative exists
   - `filterExercises()` should actually filter instead of passthrough
   - `filterGeneratedExercises()` should filter by gender video availability

2. **Add Gender to Exercise Selection** (`SmartExerciseSelectionEngine.swift`)
   - Pass user gender to `selectExercisesForWorkout()`
   - Add gender video match scoring (similar to IntelligentWorkoutGenerator's +150/-100)
   - Ensure female users get exercises with female video demonstrations

3. **Fix Empty Muscle Data Filter** (`WorkoutGeneratorService.swift`)
   - Change `primaryMuscleMatchesTarget || (categoryMatchesTarget && exercisePrimaryMuscle.isEmpty)` to require at least category match regardless of muscle data presence

### Short-Term Fixes (P1)

4. **Fix Equipment Normalization** (`ExerciseFilterService.swift`)
   - Reorder checks to prevent "row machine" hitting dumbbell first
   - Change `"resistance"` check to `"resistance band"` specifically
   - Remove bench variants from `commonItems` set or add special handling

5. **Fix Triceps Gate Typo** (`WorkoutGeneratorService.swift`)
   - Change `"assist"` to `"assisted"` in dip exclusion
   - Remove nonsensical `"chip"` check

6. **Fix Muscle Diversity Max** (`WorkoutGeneratorService.swift`)
   - Remove the `+ 1` from `maxPerMuscle` calculation

7. **Fix Gender Video Default** (`WorkoutGeneratorService.swift`)
   - Change `var genderMatches = true` to `var genderMatches = false`
   - Exercises with no video data should not get a gender bonus

### Medium-Term Improvements (P2)

8. **Standardize Equipment Naming** - Create a canonical equipment dictionary that all data sources map to
9. **Add Gender-Aware Program Generation** - Consider gender in exercise selection, not just weight reduction
10. **Fix Goal String Matching** - Use `contains` or a proper mapping instead of exact string comparison
11. **Add Equipment Validation** - Validate equipment arrays on save, not just on read
12. **Improve Fat Loss Recommendations** - Give hypertrophy programs higher scores for fat loss goals

### Architecture Improvements (Long-Term)

13. **Unify Gender Preference Storage** - Single source of truth instead of multiple UserDefaults keys
14. **Add Exercise Metadata Validation** - Flag exercises with missing primaryMuscle, equipment, or video data
15. **Add Program Completion History** - Track completed programs to improve recommendations
16. **Add Non-Binary Gender Support** - Currently only binary male/female with male default
17. **Integrate LimitationFilterEngine** - Use it consistently across ALL generation paths, not just some
18. **Add Integration Tests** - Test equipment filter + muscle filter + gender filter pipeline end-to-end

---

## Appendix A: Equipment Filter Test Cases

### Expected Behavior Matrix

| User Equipment | Exercise Equipment | Should Match? | Current Result | Correct? |
|---------------|-------------------|---------------|----------------|----------|
| ["Dumbbells"] | "Dumbbell" | Yes | Yes | OK |
| ["Dumbbells"] | "Dumbbells, Incline Bench" | Yes* | Yes | PARTIAL (bench not validated) |
| ["Barbell"] | "Barbell" | Yes | Yes | OK |
| ["Barbell"] | "EZ-Bar" | No | No | OK |
| ["Machines"] | "Lever Machine" | Yes | Yes | OK |
| ["Machines"] | "Resistance Machine" | Yes | No | BUG (returns "Bands") |
| ["Cables"] | "Cable" | Yes | Yes | OK |
| ["Bodyweight"] | "Bodyweight" | Yes | Yes | OK |
| ["Dumbbells"] | "Dumbbell Row Machine" | No | Yes | BUG (keyword collision) |

### Gender Video Test Cases

| User Gender | Exercise Has Male Video | Exercise Has Female Video | Expected Video | Current Result | Correct? |
|------------|----------------------|-------------------------|----------------|----------------|----------|
| Male | Yes | Yes | Male | Male | OK |
| Male | Yes | No | Male | Male | OK |
| Male | No | Yes | Female (fallback) | Female | OK |
| Female | Yes | Yes | Female | Female | OK |
| Female | No | Yes | Female | Female | OK |
| Female | Yes | No | Male (fallback) | Male | OK |
| Male | No | No | None | None | OK |
| Not Set | Yes | Yes | Male (default) | Male | OK (but not ideal) |

---

## Appendix B: Files Quick Reference

### Files That Need Immediate Changes
- `GenderFilterService.swift` - Fix no-op filter functions
- `WorkoutGeneratorService.swift` - Fix muscle filter, triceps gate, gender default
- `SmartExerciseSelectionEngine.swift` - Add gender awareness
- `ExerciseFilterService.swift` - Fix equipment normalization bugs

### Files That Work Correctly
- `LimitationFilterEngine.swift` - Clean metadata-driven design
- `ExerciseDataProvider.swift` - Simple, correct JSON loader
- `SmartProgramRecommender.swift` - Solid scoring algorithm (minor improvements needed)
- `ExerciseIntelligenceEngine.swift` - Good substitution/pairing logic

### Files That Need Minor Fixes
- `SmartProgramEngine.swift` - Goal matching, equipment requirements
- `UserManager.swift` - Equipment storage type
- `WorkoutEnvironmentService.swift` - Normalize equipment consistently
- `IntelligentWorkoutGenerator.swift` - Generally correct, well-structured
