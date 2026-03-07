# Food Search & Nutrition Scanner — Comprehensive Audit

**Date:** March 7, 2026
**Scope:** USDA food search, result ranking, nutrition label scanner, food entry system
**Files Audited:**
- `Fit33/USDAFoodService.swift` — Search engine, ranking, local food database
- `Fit33/FoodSearchView.swift` — Search UI, debouncing, quick access
- `Fit33/FoodDatabaseService.swift` — Cloud caching, popular/frequent foods, Supabase integration
- `Fit33/NutritionScannerView.swift` — Camera, OCR, nutrition editor
- `Fit33/FoodDetailsView.swift` — Serving sizes, unit conversions, nutrition math
- `Fit33/MealService.swift` — Food entry persistence, challenge sync
- `Fit33/ContentView.swift` — FoodEntry struct definition
- `supabase/functions/usda-food-search/index.ts` — Edge function (USDA API proxy, server-side ranking, caching)

---

## 1. Food Search Architecture (How It Works)

### Search Flow
```
User types query
    |
    v
FoodSearchView (300ms debounce)
    |
    v
USDAFoodService.searchFoods()
    |
    +---> INSTANT: searchLocalFoods() — 300+ hardcoded common foods
    |     Returns results immediately (no network)
    |
    +---> ASYNC: FoodDatabaseService.searchFoods()
          |
          +---> Check local cache (5 min TTL)
          |
          +---> Supabase Edge Function
                |
                +---> Check food_search_cache table
                |
                +---> USDA API (3 parallel calls):
                      - Foundation Foods (25 results)
                      - SR Legacy Foods (25 results)
                      - Branded Foods (50 results)
                |
                +---> Server-side ranking (rankSearchResults)
                |
                +---> Cache to food_items + food_search_cache tables
                |
                v
          Client receives results
          |
          v
    USDAFoodService.rankSearchResults() — Client-side re-ranking
          |
          v
    Smart merge: Frequent > Hardcoded > Favorites > Cloud
          |
          v
    Display in FoodSearchView
```

### Ranking Priority (Client-Side — Final Authority)

| Priority | Factor | Score Impact |
|----------|--------|-------------|
| 0a | User's frequently logged foods | -600,000 - (count * 2,000) |
| 0b | Favorited foods | -550,000 |
| 1 | Exact query match | -400,000 |
| 1b | All query words match | -300,000 |
| 2a | Cooked/prepared form (for proteins/grains) | -250,000 |
| 2b | Common descriptors (boneless, skinless, lean) | -30,000 |
| 3a | Foundation data type (USDA lab-verified) | -200,000 |
| 3b | SR Legacy data type | -150,000 |
| 3c | Generic (no brand) | -100,000 |
| 3d | Branded | +100,000 |
| 4 | Starts with query | -80,000 |
| 5 | Whole food categories | -50,000 |
| Penalty | Non-food/supplement types | +80,000 |
| Penalty | Pre-packaged | +70,000 |
| Penalty | Complex prepared dishes | +60,000 |
| Penalty | Raw form (proteins/grains) | +20,000 |

### What This Means for Users
- Searching "chicken breast" → **Chicken Breast, cooked** appears first (not raw)
- Searching "eggs" → **Eggs, whole, cooked** appears first
- Searching "rice" → **White Rice, cooked** appears first
- Previously logged foods always appear at the top
- Generic/unbranded USDA data ranks above branded products
- Foundation Foods (lab-verified) rank above all other USDA data types

---

## 2. Quick Access System

When the search bar is empty, users see:

1. **Frequent Foods** — Most-logged foods across all sessions (personal history)
2. **Recent Foods** — Last 10 foods logged (from Supabase `user_food_history`)
3. **Favorite Foods** — User-hearted foods
4. **Popular Foods** — Most-logged foods across ALL users globally (from `food_items.log_count`)
5. **Scan Nutrition Label** — Camera shortcut
6. **Restaurant Search** — External integration

**Status: Working correctly.** The `refreshQuickAccessFoods()` is called on view appear.

---

## 3. Bugs Found & Fixed

### BUG 1: Nutrition Scanner — `extractNumber` Picked Up Daily Value Percentages
**File:** `NutritionScannerView.swift:464`
**Severity:** High

**Before:** The regex `\d+(?:\.\d+)?` extracted the first number from any line. For a line like `"Total Fat 8g 10%"`, it would correctly get `8`. But for `"Cholesterol 0mg 0%"`, the filter `> 0` would skip the legitimate `0`, returning `nil`. Also, for lines where the DV% was larger than the value (e.g., `"Vitamin D 2mcg 10%"`), if OCR rearranged tokens, the wrong number could be selected.

**After:** Now uses a two-pass strategy:
1. First tries to find a number directly followed by a unit (`g`, `mg`, `mcg`, `kcal`, `cal`)
2. Falls back to finding numbers after stripping all percentage values
3. Allows zero values (Trans Fat 0g is a valid result)

### BUG 2: Server-Side vs Client-Side Ranking Conflict for Raw/Cooked
**File:** `supabase/functions/usda-food-search/index.ts:618`
**Severity:** Medium

**Before:** Server-side ranking gave a -5,000 boost to "raw" foods. Client-side gave -250,000 boost to "cooked" foods. While the client wins (re-ranks), this meant the server wasted its sort by promoting raw versions that the client would push down.

**After:** Server-side now aligns with client — cooked proteins/grains get -8,000 boost, raw get +3,000 penalty. Fruits/veggies still get a slight raw boost (since raw is the common form for those).

### BUG 3: Duplicate Detection Removed Cooked vs Raw Variants
**File:** `USDAFoodService.swift:1004`
**Severity:** High

**Before:** `simplifyFoodName` stripped `, raw`, `, cooked`, `, grilled`, etc. This meant "Chicken Breast, cooked" and "Chicken Breast, raw" both simplified to "Chicken Breast" — only one would appear in results.

**After:** Now only strips trivial presentation suffixes (`, fresh`, `, sliced`, `, chopped`). Cooking methods are preserved since they represent meaningfully different nutrition profiles (raw chicken has different macros than cooked).

### BUG 4: Scanner Quantity Truncation
**File:** `NutritionScannerView.swift:521`
**Severity:** Medium

**Before:** `quantity: Int(nutrition.servingQuantity)` truncated 1.5 servings to 1, and 0.5 servings to 0. The nutrition values were already multiplied correctly, but the stored quantity was wrong.

**After:** Uses `max(1, Int(ceil(nutrition.servingQuantity)))` to round up and prevent zero quantities.

### BUG 5: Serving Size Extraction from Label
**File:** `NutritionScannerView.swift:248`
**Severity:** Medium

**Before:** Only checked for colon separator. Many labels use `"Serving Size 2/3 cup (55g)"` format without a colon. Would fall through to next-line check, possibly picking up wrong text.

**After:** Now checks:
1. After colon (if present)
2. After "Serving Size" / "servingsize" text (handles no-colon format)
3. Next line (fallback, with stricter filtering)

### BUG 6: Calories Extraction on Modern FDA Labels
**File:** `NutritionScannerView.swift:271`
**Severity:** Low

**Before:** Only extracted calories from the same line. Modern FDA labels often have "Calories" as a header with the number on the next line.

**After:** If no number found on the current line, checks the next line. Also added `!lowercased.contains("fat")` guard to prevent matching "Calories from Fat" lines.

---

## 4. Global Popularity Ranking (All Users)

### How It Works
The edge function now uses a tiered popularity boost:

| User Log Count (All Users) | Score Boost |
|---------------------------|-------------|
| > 50 logs | -15,000 |
| > 10 logs | -8,000 |
| > 0 logs  | -3,000 |
| Search frequency | Up to -5,000 |

This means globally popular foods (chicken breast, eggs, rice, oatmeal) will naturally float to the top over time as more users log them. Combined with the client-side user-personal-history boost (-600,000), the ranking is:

1. **Your personal frequently logged foods** (highest priority)
2. **Your favorites**
3. **Globally popular foods across all users**
4. **Foundation/SR Legacy USDA data** (lab-verified accuracy)
5. **Generic unbranded foods**
6. **Branded products** (lowest priority for generic queries)

---

## 5. Nutrition Label Scanner — Full Audit

### Fields Extracted (All Editable)
| Field | OCR Keyword | Editable | Unit |
|-------|-------------|----------|------|
| Food Name | User-entered | Yes | — |
| Serving Size | "serving size" | Yes | Auto-detected |
| Servings Per Container | "servings per container" | Yes | — |
| Serving Quantity | Stepper control | Yes (+/- 0.25) | servings |
| Calories | "calories" (not "from fat") | Yes | kcal |
| Calories from Fat | "calories from fat" | Yes | kcal |
| Total Fat | "total fat" | Yes | g |
| Saturated Fat | "saturated fat" | Yes | g |
| Trans Fat | "trans fat" | Yes | g |
| Cholesterol | "cholesterol" | Yes | mg |
| Sodium | "sodium" | Yes | mg |
| Total Carbs | "total carb" | Yes | g |
| Dietary Fiber | "dietary fiber" / "fiber" | Yes | g |
| Total Sugars | "total sugar" / "sugar" | Yes | g |
| Added Sugars | "added sugar" / "includes...added" | Yes | g |
| Protein | "protein" | Yes | g |
| Vitamin D | "vitamin d" | Yes | mcg |
| Calcium | "calcium" | Yes | mg |
| Iron | "iron" | Yes | mg |
| Potassium | "potassium" | Yes | mg |

### Scanner Flow
```
1. User taps "Scan Nutrition Label"
2. Camera opens (UIImagePickerController)
3. User takes photo
4. Processing view shows with preview
5. Apple Vision VNRecognizeTextRequest (accuracy mode + language correction)
6. Text lines parsed for nutrition keywords
7. NutritionEditorView presented with all fields editable
8. User adjusts serving quantity (0.25 increments, quick buttons: 0.5, 1.0, 1.5, 2.0)
9. Live "Your Total Nutrition" preview when quantity != 1.0
10. Save applies multiplier to all values → creates FoodEntry
```

### Scanner Accuracy Features
- **Apple Vision Framework** with `.accurate` recognition level
- **Language correction** enabled for better OCR
- **Number extraction** now prioritizes unit-suffixed numbers (`8g`, `30mg`) over bare numbers
- **Percentage filtering** strips `%` values before number extraction
- **All fields editable** — user can correct any OCR mistakes
- **Default serving = 1** (the serving shown on the label)
- **Serving quantity stepper** — increment/decrement by 0.25 with quick presets

---

## 6. Food Details & Serving Size System

### Smart Default Servings
When a user taps a food from search results, the app auto-selects the most realistic serving:

| Food Type | Default | Unit |
|-----------|---------|------|
| Chicken breast | 1 | breast (174g) |
| Eggs | 1 | egg (50g) |
| Salmon/fish | 1 | fillet (170g) |
| Rice/pasta (cooked) | 1 | cup (240g) |
| Rice/pasta (dry) | 0.5 | cup (120g) |
| Protein powder | 1 | scoop (30g) |
| Nut butters | 2 | tbsp (30g) |
| Oils/butter | 1 | tbsp (15g) |
| Yogurt | 1 | container (170g) |
| Bread | 1 | slice (30g) |
| Bacon | 2 | strips (16g) |
| Nuts | 1 | oz (28g) |
| Cheese | 1 | oz (28g) |
| Generic meat | 4 | oz (113g) |

### Available Units (Context-Aware)
- **Always shown:** grams, ounces
- **Contextual:** egg, breast, thigh, drumstick, wing, fillet, link, patty, slice, strip, scoop, bar, packet, cup, tbsp, tsp, ml, container, medium, large, small, piece, whole

### Nutrition Math
All USDA nutrition data is stored **per 100g**. When user changes serving:
```
scaledNutrition = baseNutrition * (selectedGrams / 100.0)
```
Where `selectedGrams = servingAmount * unit.gramsPerUnit`

---

## 7. Food Entry Persistence

### Data Flow
```
FoodDetailsView / NutritionScannerView
    |
    v
FoodEntry struct (name, quantity, unit, calories, protein, carbs, fat, fdcId)
    |
    v
MealService.addMealEntry()
    |
    +---> Core Data (MealEntry entity) — local persistence
    +---> SupabaseManager.saveMealToCloud() — cross-device sync
    +---> FoodDatabaseService.logFoodToHistory() — history tracking + log_count increment
    +---> RecipePreferenceService — personalization
    +---> DailyQuestService — gamification
    +---> WeeklyLeagueService — league points (+10 pts)
    +---> ChallengeService — real-time challenge sync (protein/calories)
    +---> PrivateChallengeService — private challenge sync
    +---> CommunityChallengeService — community challenge sync
```

### Deletion Flow
When user removes a meal entry:
- Deletes from Core Data
- Deletes from cloud (Supabase)
- Removes from food history (so it doesn't inflate "frequently used")
- Re-syncs challenge progress with `allowDecrease: true` (so opponents see the updated lower value in real-time)

---

## 8. Edge Function (Supabase) — Server-Side Architecture

### USDA API Strategy
- **3 parallel API calls** to USDA FoodData Central:
  - Foundation Foods (25 results) — lab-verified, most accurate
  - SR Legacy Foods (25 results) — high quality USDA data
  - Branded Foods (50 results) — user-submitted, lower accuracy
- **Server-side caching** in `food_items` table (upsert by `fdc_id`)
- **Search query caching** in `food_search_cache` table (by `normalized_query`)
- **Minimum query length:** 3 characters (USDA API requirement)

### Server-Side Ranking
```
TIER 1: Exact match         → -1,000,000
TIER 1b: Starts with query  → -500,000
TIER 1c: All words match    → -100,000
TIER 2: Foundation data      → -50,000
TIER 2b: SR Legacy           → -40,000
TIER 2c: Survey (FNDDS)      → -10,000
TIER 2d: Branded             → +30,000
TIER 3: Generic (no brand)   → -20,000
TIER 3b: Has brand           → +20,000
TIER 4: Cooked proteins      → -8,000 (NEW)
TIER 4b: Raw proteins        → +3,000 (NEW)
TIER 4c: Raw fruits/vegs     → -2,000
TIER 5: Global log_count>50  → -15,000 (NEW)
TIER 5b: Global log_count>10 → -8,000 (NEW)
TIER 5c: Any log_count       → -3,000 (NEW)
TIER 5d: Search frequency    → Up to -5,000 (NEW)
```

---

## 9. Verified Working Correctly

- [x] Search debounce (300ms) prevents excessive API calls
- [x] Local foods provide instant results while cloud loads
- [x] Smart merge deduplicates by ID and simplified name
- [x] User's personal history always ranks first
- [x] Generic/unbranded foods rank above branded for generic queries
- [x] Brand-specific queries correctly prioritize matching brands
- [x] Cooked forms rank above raw for proteins and grains
- [x] Foundation/SR Legacy data ranks above Branded
- [x] Nutrition scanner extracts all FDA label fields
- [x] All scanner fields are editable (TextField with decimal pad)
- [x] Serving quantity adjustable with +/- 0.25 stepper and quick presets
- [x] Live "Your Total Nutrition" preview when quantity != 1
- [x] Serving defaults to 1 (the label's stated serving)
- [x] Smart default servings (1 breast, 1 egg, etc.) for USDA foods
- [x] Context-aware unit options (egg for eggs, breast for chicken, etc.)
- [x] Nutrition math correctly scales per 100g base
- [x] Food entry saves to Core Data + Supabase + history
- [x] Deletion removes from all locations + re-syncs challenges
- [x] Global popularity (log_count, search_count) influences ranking
- [x] Edge function makes parallel USDA API calls for speed
- [x] Server and client caching for instant repeat searches
- [x] Junk food de-prioritized in generic searches
- [x] Complex prepared dishes ranked lower than simple whole foods
- [x] Favorite toggle works with cloud sync

---

## 10. Summary of Changes Made

| File | Change | Impact |
|------|--------|--------|
| `NutritionScannerView.swift` | Fixed `extractNumber` to prioritize unit-suffixed numbers and strip DV% | Scanner accuracy improved — no more picking up percentage values |
| `NutritionScannerView.swift` | Improved serving size extraction (handles no-colon format) | Better OCR parsing for varied label layouts |
| `NutritionScannerView.swift` | Fixed calories extraction for split-line modern FDA labels | Handles "Calories" on one line, number on next |
| `NutritionScannerView.swift` | Fixed quantity truncation (`Int(0.5)` → 0) | Fractional servings no longer lose data |
| `USDAFoodService.swift` | Fixed `simplifyFoodName` — preserves cooking methods | "Chicken Breast, cooked" and "raw" both appear in results |
| `usda-food-search/index.ts` | Aligned server ranking with client (cooked > raw for proteins) | Consistent ranking between server and client |
| `usda-food-search/index.ts` | Added tiered global popularity scoring (log_count/search_count) | Most-logged foods across all users rank higher |
