# Equipment Hierarchy Reference

> ✅ **This data is now stored in the app!**  
> See `GoFit/EquipmentHierarchyService.swift` for implementation.

## How It's Used in Recommendations

| Feature | How Equipment Hierarchy Helps |
|---------|------------------------------|
| **Beginner Progression** | Machines (95 score) → Cables (85) → Dumbbells (60) → Barbells (35) |
| **Smart Substitutions** | Same-family swaps score +25, compatible families score +12 |
| **Complexity Penalties** | Beginners get penalties for `skillBased` and `advanced` equipment |
| **Variant Rotation** | Suggests variants within same equipment family |
| **Calorie Calculation** | Different equipment affects exercise intensity scoring |

---

## 🏋️ GYM WORKOUT - Auto-Included Equipment

When user selects "Gym" as workout location, these are **AUTOMATICALLY** included:

| Equipment | Exercises | Notes |
|-----------|-----------|-------|
| Barbell | 419 | Includes Smith Machine, EZ Bar, Trap Bar, Landmine |
| Dumbbells | 649 | |
| Cables | 394 | |
| Machines | 295 | All lever machines, leg machines, etc. |
| Plates | 26 | Weight plate exercises |
| Bench | (included) | Assumed available at gym |
| Pull-Up Bar | (included) | Assumed available at gym |
| Dip Bars | (included) | Assumed available at gym |

---

## 📦 Parent → Child Equipment Relationships

### 🏋️ BARBELL CATEGORY (419 exercises)
When user selects "Barbell", they get ALL of these:

| Equipment | Exercises | 
|-----------|-----------|
| Barbell | 169 |
| Smith Machine | 57 | ✅ INCLUDED with Barbell |
| Landmine Attachment | 29 | ✅ INCLUDED with Barbell |
| EZ Bar | 23 | ✅ INCLUDED with Barbell |
| Trap Bar | 5 | ✅ INCLUDED with Barbell |
| + bench/platform combos | 136 | |

### 🪢 SUSPENSION CATEGORY (230 exercises)
When user selects "TRX/Rings", they get ALL of these:

| Equipment | Exercises |
|-----------|-----------|
| TRX | 120 | ✅ INCLUDED |
| Gymnastic Rings | 97 | ✅ INCLUDED |
| + accessory combos | 13 | |

### ⚫ PLATE CATEGORY (26 exercises) - STANDALONE
User MUST have "Plates" selected - NOT included with Barbell

| Equipment | Exercises |
|-----------|-----------|
| Weight Plate | 26 |

### 🧍 BODYWEIGHT CATEGORY (3,988 exercises)
When user selects "Bodyweight", they get ALL of these:

| Equipment | Exercises |
|-----------|-----------|
| Pure Bodyweight | 3,294 |
| Chair | 235 | ✅ INCLUDED |
| Wall | 108 | ✅ INCLUDED |
| Pull-Up Bar | 83 | ✅ INCLUDED |
| Stability Ball | 51 | ✅ INCLUDED |
| Step Platform | 45 | ✅ INCLUDED |
| Medicine Ball | 23 | ✅ INCLUDED |
| Dip Bars | 20 | ✅ INCLUDED |
| + other accessories | 129 | |

---

## 📊 Standalone Categories (No parent/child)

| Category | Exercises | Main Equipment |
|----------|-----------|----------------|
| **DUMBBELL** | 649 | Dumbbells + bench combos |
| **CABLE** | 394 | Cable Machine + bench combos |
| **MACHINE** | 295 | Lever Machine, Chest Press, Leg Press, Leg Extension, Leg Curl |
| **KETTLEBELL** | 183 | Kettlebell + bench combos |
| **BAND** | 357 | Resistance Band + anchor combos |

---

## 🏠 HOME / 🌳 OUTDOOR / 🔄 HYBRID

### HOME (User selects what they have)
**Primary options shown:**
- Bodyweight, Bands, Dumbbells, Stability Ball
- Chair, Wall, Pull-Up Bar, Dip Bars
- Kettlebell, Bench

**Secondary (Show More):**
- TRX/Rings, Medicine Ball, Barbell, Cables
- Machines, Smith Machine, Plates, etc.

### OUTDOOR (Auto-selected)
✅ Bodyweight, ✅ Bands, ✅ Pull-Up Bar, ✅ Dip Bars, ✅ Kettlebell, ✅ Medicine Ball

### HYBRID (Auto-selected)
✅ Dumbbells, ✅ Bodyweight, ✅ Bands, ✅ Cables, ✅ Machines, ✅ Bench

---

## Summary of Equipment Categories in Database

| Category | Exercises | Description |
|----------|-----------|-------------|
| bodyweight | 3,988 | No equipment or basic accessories |
| dumbbell | 649 | Dumbbell exercises |
| barbell | 419 | Barbells, Smith Machine, EZ Bar, Trap Bar, Landmine |
| cable | 394 | Cable machine exercises |
| band | 357 | Resistance band exercises |
| machine | 295 | Gym machines (lever, leg press, etc.) |
| suspension | 230 | TRX and Gymnastic Rings |
| kettlebell | 183 | Kettlebell exercises |
| plate | 26 | Weight plate exercises |

**Total: 6,541 exercises**

---

## 🔧 Implementation in App

### EquipmentHierarchyService.swift

```swift
enum EquipmentFamily: String, CaseIterable {
    case barbell      // 419 exercises, beginnerScore: 35
    case dumbbell     // 649 exercises, beginnerScore: 60
    case cable        // 394 exercises, beginnerScore: 85
    case machine      // 295 exercises, beginnerScore: 95
    case kettlebell   // 183 exercises, beginnerScore: 50
    case band         // 357 exercises, beginnerScore: 75
    case bodyweight   // 3988 exercises, beginnerScore: 80
    case suspension   // 230 exercises, beginnerScore: 45
    case plate        // 26 exercises, beginnerScore: 30
}

enum EquipmentComplexity: Int {
    case guided = 1      // Machine, Cable
    case basic = 2       // Bodyweight, Band
    case freeWeight = 3  // Dumbbell
    case skillBased = 4  // Kettlebell, TRX
    case advanced = 5    // Barbell, Plate
}
```

### Key Methods

| Method | Purpose |
|--------|---------|
| `getFamily(for:)` | Get equipment family from string |
| `areSameFamily(_:_:)` | Check if two equipment types are related |
| `getBeginnerFriendlinessBoost()` | Score boost for beginner-friendly equipment |
| `getComplexityPenalty()` | Penalty for complex equipment for beginners |
| `getSimilarFamilies(for:)` | Get compatible substitution families |
| `isReasonableSubstitution(from:to:)` | Validate equipment swap logic |
| `getEquipmentRecommendationScore()` | Combined score for recommendations |

### Integration Points

1. **SmartExerciseSelectionEngine** - Equipment variety scoring
2. **AlternativeExerciseEngine** - Smart swap suggestions
3. **WorkoutGeneratorService** - Beginner equipment priority
4. **SmartVariantRotationEngine** - Family-aware variants
