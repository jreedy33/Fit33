# Recipe Recommendation System - Analysis & Fixes

## Problems Identified

### 1. No Health Filtering in RecipePreferenceService
**Files:** `RecipePreferenceService.swift`

The core recommendation engine (`RecipePreferenceService`) had **zero health filters** on 4 out of 5 API call strategies:
- `fetchRecipesByIngredientsSmartMatch` - no `minHealthScore`, no `maxSugar`, no meal type filter
- `fetchRecipesWithPreferences` - no `minHealthScore`, no `maxSugar`, no meal type filter
- `fetchHealthyRecipesWithExclusions` - no `minHealthScore`, no `maxSugar`, no meal type filter
- `fetchVariedRecipes` - no `minHealthScore`, no `maxSugar`, no meal type filter

Only `SmartMealRecommendationService` and `SpoonacularService` had health filters. Since the carousel and browser primarily go through `RecipePreferenceService`, unhealthy recipes (desserts, sugary items, drinks) were regularly returned.

**Fix:** Added `minHealthScore=40`, `maxSugar=25`, and `type=main course,salad,soup,breakfast,side dish,snack` to ALL API strategies.

---

### 2. Random Offset Too High (Obscure Recipes)
**Files:** `RecipePreferenceService.swift`, `SmartMealRecommendationService.swift`

All API calls used `Int.random(in: 0...50)` for the offset parameter. Spoonacular sorts by healthiness descending, so offset 50 pushes results into obscure, less common recipes.

**Fix:** Reduced random offset to `0...10` or `0...15` across all methods to keep results in the common, popular range while still providing variety.

---

### 3. "See All" (RecipeBrowserView) Not Using Preferences Properly
**File:** `RecipeBrowserView.swift`

The `RecipeBrowserViewModel.searchRecipes()` method had these issues:
- When user had no search query, it defaulted to just `"dinner"` - ignoring all preferences
- Only used the **first** liked ingredient + "dinner" as query (e.g., "chicken dinner")
- Did not pass `includeIngredients` to Spoonacular for preference matching
- Had no health score or sugar filters
- Had no meal type filter (desserts could appear)
- `loadMore()` also defaulted to `"dinner"` with no preference awareness

**Fix:**
- Default query now uses top 2 liked ingredients: `"healthy chicken salmon"`
- Added `includeIngredients` parameter to boost preference-matching recipes
- Added `minHealthScore=40`, `maxSugar=25`, and meal type filters
- `loadMore()` uses the same preference-aware query logic
- Fallback (no preferences) now uses `"healthy chicken vegetables protein"`

---

### 4. Food Logging History Not Influencing Recommendations Enough
**Files:** `RecipePreferenceService.swift`, `HealthyRecipesCarousel.swift`, `RecipeBrowserView.swift`, `SmartMealRecommendationService.swift`

The `learnFromFoodHistory()` method was only called:
- Once on init
- In `getPersonalizedRecipes` only when `ingredientCounts.isEmpty || likedIngredients.isEmpty`

This meant that as users logged more food throughout the day/week, the recommendations didn't update to reflect their evolving food patterns.

**Fix:**
- `getPersonalizedRecipes()` now **always** calls `learnFromFoodHistory()` before fetching
- `HealthyRecipesCarousel.loadRecipes()` calls `learnFromFoodHistory()` before carousel refresh
- `RecipeBrowserView` calls `learnFromFoodHistory()` on task load AND when preferences sheet closes
- `SmartMealRecommendationService.getRecommendations()` calls `learnFromFoodHistory()` before each fetch

---

### 5. SmartMealRecommendationService Health Thresholds Too Low
**File:** `SmartMealRecommendationService.swift`

- `minimumHealthScore` was 40 (too low, allowed borderline unhealthy)
- `preferredHealthScore` was 60
- No `maxSugar` filter existed

**Fix:**
- Raised `minimumHealthScore` to 50
- Raised `preferredHealthScore` to 65
- Added `maxSugar=20` to API calls
- Reduced random offset from `0...50` to `0...10`

---

## Files Changed

| File | Changes |
|------|---------|
| `RecipePreferenceService.swift` | Added health filters to all 5 API strategies, reduced offsets, improved search queries, always re-learn from food history |
| `RecipeBrowserView.swift` | Added health/type filters to search and loadMore, preference-aware queries, food history re-learning |
| `HealthyRecipesCarousel.swift` | Added food history re-learning before carousel refresh |
| `SmartMealRecommendationService.swift` | Raised health thresholds, added maxSugar, reduced offset, food history re-learning |

## How It Works Now

### Carousel (Home Screen)
1. Re-learns from food history (picks up recently logged foods)
2. Uses liked ingredients (explicit + auto-detected from logs) in search queries
3. All results filtered: `minHealthScore=40`, `maxSugar=25`, real meal types only
4. Small random offset (0-15) keeps results common and recognizable

### See All (RecipeBrowserView)
1. Re-learns from food history on load
2. Uses top 2 liked ingredients in query + passes top 3 as `includeIngredients`
3. Health filters ensure only nutritious meals appear
4. Disliked ingredients are excluded
5. When preferences sheet closes, re-learns and refreshes

### Smart Meal Recommendations
1. Re-learns from food history before each recommendation fetch
2. Higher health score threshold (50 min, 65 preferred)
3. Sugar capped at 20g
4. Small offset keeps results in common territory

### Food History Learning
- Analyzes user's `frequentFoods` from `FoodDatabaseService`
- Maps logged foods to ingredient categories (chicken, salmon, eggs, etc.)
- Auto-sets top 5 as liked ingredients if user hasn't set explicit preferences
- Boosts existing preferences with food history data (3x weight for logged foods)
- Now called on every recommendation fetch, not just once on init
