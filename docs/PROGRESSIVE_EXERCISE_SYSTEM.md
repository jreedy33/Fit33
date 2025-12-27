# Progressive Exercise Foundation System

## 🎯 Problem Solved

New users were getting obscure or advanced exercises on their first workout (e.g., "Behind the Back Tricep Extension Cable Pull Down"). This created a confusing and potentially intimidating experience for beginners.

## 🌟 Solution Overview

A progressive exercise recommendation system that:

1. **Starts Simple**: New users only see foundational, well-known exercises
2. **Learns from Behavior**: Tracks completions, favorites, and swaps to understand user preferences
3. **Gradually Unlocks Variety**: As users demonstrate proficiency, more exercise variety is introduced

---

## 📦 New Files Created

### 1. `FoundationalExerciseDatabase.swift`

A curated database of ~90 foundational exercises across all equipment types:

| Equipment | Essential | Fundamental | Standard | Variety | Total |
|-----------|-----------|-------------|----------|---------|-------|
| Barbell | 4 | 4 | 4 | 3 | 15 |
| Dumbbell | 5 | 6 | 4 | 5 | 20 |
| Cable | 4 | 4 | 3 | 4 | 15 |
| Machine | 4 | 4 | 4 | 3 | 15 |
| Bodyweight | 4 | 4 | 4 | 3 | 15 |
| Kettlebell | 2 | 3 | 2 | 3 | 10 |

**Selection Criteria:**
- Well-known and commonly performed
- Easy to learn proper form
- Effective for target muscle group
- Low injury risk
- Video demonstrations available

### 2. `ProgressiveExerciseUnlockService.swift`

Tracks user maturity and determines exercise variety level:

**Metrics Tracked:**
- Total workouts completed
- Total exercises completed with full sets
- Unique exercises done
- Favorited exercises (engagement signal)
- Frequently swapped exercises (negative signal)
- Mastered equipment types
- Days since first workout

**Unlock Tiers:**

| Tier | Requirements | Variety % | Description |
|------|-------------|-----------|-------------|
| Essential | 0-2 workouts | 0% | Only essential exercises |
| Fundamental | 3-5 workouts | 10% | Core exercises added |
| Standard | 6-11 workouts | 30% | Common exercises added |
| Variety | 12+ workouts | 100% | Full library access |

---

## 🔗 Integration Points

### SmartExerciseSelectionEngine.swift

Added foundational boost scoring:

```swift
// 🌟 FOUNDATIONAL EXERCISE BOOST (For New Users)
let foundationalBoost = ProgressiveExerciseUnlockService.shared.getFoundationalBoostScore(for: exerciseName)
score += foundationalBoost

// Check if user should be restricted to foundational exercises only
if shouldRestrictToFoundational && foundationalBoost < 0 {
    continue  // Skip non-foundational for new users
}
```

### WorkoutGeneratorService.swift

Added foundational scoring to auto-gen workouts:

```swift
// 🌟 FOUNDATIONAL EXERCISE BOOST - CRITICAL FOR NEW USERS
let foundationalBoost = FoundationalExerciseDatabase.shared.getFoundationalBoostScore(
    exerciseName: name,
    userWorkoutCount: userWorkoutCount
)
score += foundationalBoost

// Heavy penalty for non-foundational when user is restricted
if restrictToFoundational && foundationalBoost < 0 {
    score -= 500
}
```

### UserBehaviorLearningEngine.swift

Added hooks to update progressive unlock service:

- After workout completion → `recordWorkoutCompletion()`
- After exercise swap → `recordSwap()`
- After behavior analysis → `analyzeUserMaturity()`

---

## 📊 Scoring System

### Foundational Exercise Scores

| Tier | Base Boost | Description |
|------|-----------|-------------|
| Essential | +200 | Massive boost for core exercises |
| Fundamental | +100 | Large boost |
| Standard | +50 | Moderate boost |
| Variety | +25 | Small boost |
| Non-Foundational | -80 to 0 | Penalty based on user experience |

### Experience-Based Scaling

| User Workouts | Boost Multiplier |
|---------------|-----------------|
| 0-4 | 100% (full boost) |
| 5-9 | 80% |
| 10-19 | 50% |
| 20-49 | 30% |
| 50+ | 15% |

---

## 🔄 User Journey Example

### First Workout (0 workouts completed)
- **Tier**: Essential
- **Variety**: 0%
- **Exercises**: Bench Press, Squat, Row, Overhead Press, Bicep Curl
- **Behavior**: Only shows exercises everyone recognizes

### After 5 Workouts
- **Tier**: Fundamental  
- **Variety**: 10%
- **New Exercises**: Incline Press, RDL, Lateral Raise, Cable Fly
- **Behavior**: Introduces more variations of known movements

### After 12 Workouts
- **Tier**: Standard
- **Variety**: 30%
- **New Exercises**: Hack Squat, Close Grip Bench, Cable Woodchop
- **Behavior**: Opens up equipment-specific exercises

### After 25+ Workouts
- **Tier**: Variety
- **Variety**: 100%
- **Behavior**: Full access, but foundational exercises still get small boost

---

## 🎛️ Debug Information

The system logs detailed information:

```
╔══════════════════════════════════════════════════════════════╗
║         🧠 SMART EXERCISE SELECTION ENGINE                   ║
╠══════════════════════════════════════════════════════════════╣
║ 🌟 PROGRESSIVE UNLOCK STATUS:
║   • Total Workouts Completed: 3
║   • Current Unlock Tier: Fundamental
║   • Restrict to Foundational: NO
║   • Variety Percentage: 10%
╠══════════════════════════════════════════════════════════════╣
```

---

---

## 🔄 Smart Variant Rotation Engine

### `SmartVariantRotationEngine.swift` (NEW)

A **lightweight** engine that adds variant rotation logic **on top of existing data**.

### ✅ Uses Existing Data (No Duplication)

| Data | Source | Already Stored |
|------|--------|---------------|
| Swap history | `UserBehaviorLearningEngine` | ✅ |
| Favorites | `UserBehaviorLearningEngine` | ✅ |
| Recently done | `UserBehaviorLearningEngine` | ✅ |
| Full set completions | `UserBehaviorLearningEngine` | ✅ |
| Exercise families | Core Data (`exerciseFamily`) | ✅ |

### 🆕 Only Stores New Data

| Data | Purpose |
|------|---------|
| `familyVariantRotations` | Which variant of a favorite family to show next |

### Key Principles

1. **Favorites → Show VARIANTS next time**
   - If user favorites "Dumbbell Bench Press"
   - Next chest day shows "Incline Dumbbell Press" or "Dumbbell Fly"
   - Keeps the experience fresh while respecting preferences

2. **3+ Sets Completed = Strong Engagement**
   - User fully engaged with this exercise
   - Boost the exercise FAMILY, show progression/variants
   - Track as "building proficiency"

3. **Swap FROM = Gradual Negative Signal**
   - 1-2 swaps: **NO PENALTY** (equipment might be busy/broken)
   - 3+ swaps: Start penalizing (-15 per swap after 2nd)
   - Learn what they swapped TO (always positive!)

4. **Replace = Stronger Negative Signal**
   - 1 replace: No penalty (might be wrong workout)
   - 2+ replaces: Start penalizing
   - Combined with 0 "swapped TO" = avoid entirely

### Data Structures

```swift
// ONLY new data - variant rotation tracking
struct FamilyVariantRotation: Codable {
    var familyName: String
    var variantsShown: [String]  // Which variants we've shown
    var nextIndex: Int           // Which to show next
}

// EXISTING (from UserBehaviorLearningEngine - not duplicated)
// - swapHistory: [String: ExerciseSwapData]
// - favoritedExerciseNames: Set<String>
// - recentlyDoneExercises: Set<String>
// - fullSetExercises: Set<String>
// - exerciseCompletionCounts: [String: Int]
```

### Scoring Impact

| Signal | Score Impact | Notes |
|--------|-------------|-------|
| Swapped FROM 1-2 times | **0** | No penalty - equipment might be busy! |
| Swapped FROM 3+ times | -15 to -60 | Gradual penalty after clear pattern |
| Swapped FROM 3+ & never chosen | **-100** | Major penalty, avoid entirely |
| Swapped TO (preferred) | +15 to +50 | User actively chose this |
| Favorite family, used recently | -50 | Show variant instead |
| Favorite family, fresh variant | +60 | User will love this |
| High engagement (3+ sets) | +30 | User likes this pattern |
| Used in last 5 days | -35 | Keep things fresh |
| Building on recent engagement | +20 | Cohesive progression |

### Example Flow

```
Day 1: User does "Dumbbell Bench Press", completes 4 sets, favorites it
       → Engine records: family=bench_press, engagement=high, favorite=true

Day 3: User trains chest again
       → "Dumbbell Bench Press" gets -50 (used recently, show variant)
       → "Incline Dumbbell Press" gets +60 (fresh variant of favorite family)
       → Result: User sees Incline Dumbbell Press ✨

Day 5: User swaps "Cable Fly" → "Pec Deck" (machine was busy)
       → Cable Fly swap count = 1 → NO PENALTY (could be equipment issue)
       → Pec Deck swapped-to count = 1 → +15 boost

Day 7: User swaps "Cable Fly" → "Pec Deck" again (someone was using it)
       → Cable Fly swap count = 2 → STILL NO PENALTY (benefit of doubt)
       → Pec Deck swapped-to count = 2 → +30 boost

Day 10: User swaps "Cable Fly" a 3rd time
       → Cable Fly swap count = 3 → NOW we penalize (-15)
       → "Okay, they clearly don't like this exercise"

Day 14: User swaps "Cable Fly" a 4th time
       → Cable Fly swap count = 4 → Stronger penalty (-30)
       → Future workouts strongly deprioritize Cable Fly
```

---

## 🔮 Future Enhancements

1. **Equipment-Specific Progression**: Track mastery per equipment type
2. **Muscle Group Progression**: Unlock advanced exercises per muscle
3. **Social Learning**: See what exercises similar users did at this stage
4. **Achievement System**: Unlock badges for mastering exercise tiers

---

## 📝 Summary

This system ensures:
- ✅ New users get familiar, effective exercises
- ✅ Users build confidence with proven movements
- ✅ Variety is introduced gradually based on demonstrated proficiency
- ✅ Frequently swapped exercises are deprioritized
- ✅ Favorites show VARIANTS next time (not same exercise)
- ✅ 3+ set completions signal engagement, boost that family
- ✅ Swaps/replaces are learned and avoided
- ✅ Workouts build cohesively on previous sessions
- ✅ The "weird exercise" problem is solved for beginners
