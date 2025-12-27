# ☁️ Cloud Food Database Setup Guide

## Overview

This guide will help you set up the complete cloud-based USDA food tracking system with:
- ✅ **Instant search** - Results cached in the cloud for sub-second response times
- ✅ **Smart ranking** - Generic items (eggs, chicken, produce) appear first, branded items last
- ✅ **History & favorites** - User food logging history and favorite foods
- ✅ **Popularity tracking** - See what foods are most commonly logged

---

## 🚀 Quick Start (5 minutes)

### Step 1: Deploy Database Schema

Run this SQL in your Supabase SQL Editor:

```bash
# Copy the contents of supabase_food_tracking_setup.sql to Supabase SQL Editor
# Or use the CLI:
supabase db push
```

**File:** `supabase_food_tracking_setup.sql`

This creates:
- `food_items` - Cached USDA foods for fast search
- `user_food_history` - User's food logging history
- `user_favorite_foods` - User's favorite foods
- `food_search_cache` - Search query cache for instant results

---

### Step 2: Deploy Edge Function

```bash
# Navigate to your project
cd "Workout App"

# Create edge function directory
mkdir -p supabase/functions/usda-food-search

# Copy the edge function
cp supabase_edge_function_usda_proxy.ts supabase/functions/usda-food-search/index.ts

# Deploy to Supabase
supabase functions deploy usda-food-search

# Set your USDA API key as a secret
supabase secrets set USDA_API_KEY=QNZnzcALuiyekVr86WpdzYfJzWWwEa3BvEcLdfkS
```

---

### Step 3: Verify Setup

Test the edge function:

```bash
curl -X POST 'https://YOUR_PROJECT.supabase.co/functions/v1/usda-food-search' \
  -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer YOUR_ANON_KEY' \
  -d '{"action": "search", "query": "egg"}'
```

You should see results with generic eggs appearing first!

---

## 🎯 How It Works

### Architecture

```
User searches "egg" in app
    ↓
Swift calls FoodDatabaseService.searchFoods()
    ↓
Calls Supabase Edge Function "usda-food-search"
    ↓
Edge function checks cache first
    ├─ Cache HIT → Returns instantly
    └─ Cache MISS → Calls USDA API → Caches results → Returns
    ↓
Results ranked server-side (generic first)
    ↓
App displays results instantly
```

### Smart Ranking Algorithm

The edge function ranks foods by:

1. **Generic vs Branded** (MOST IMPORTANT)
   - Generic foods (no brand): Score 0 ✅
   - Branded foods: Score +10000 ❌

2. **Data Type Quality**
   - Foundation/SR Legacy (USDA Standard): Best
   - Survey (FNDDS): Good
   - Branded: Lower priority

3. **Name Relevance**
   - Exact match: Big bonus
   - Starts with query: Good bonus
   - Contains query: Small bonus

4. **Category Match**
   - Searching "egg" → "Dairy and Egg Products" category gets boost

5. **Simplicity**
   - "Egg" ranked higher than "Scrambled egg with butter and cheese"

6. **Popularity** (minor factor)
   - Previously logged foods get slight boost

---

## 📊 Example: Searching "egg"

### Results Order:

```
1. ✅ Egg, whole, raw, fresh (Generic, Foundation)
2. ✅ Egg, white, raw, fresh (Generic, Foundation)  
3. ✅ Egg, yolk, raw, fresh (Generic, Foundation)
4. ✅ Scrambled egg (Generic, Survey FNDDS)
5. ✅ Eggs, scrambled, 2 eggs (Generic, Survey)
...
50. ❌ JUST Egg (Branded)
51. ❌ Tyson Scrambled Eggs (Branded)
52. ❌ McDonald's Egg McMuffin (Branded)
```

Generic foods appear first, branded items appear last - **just like your competitor app!**

---

## 🔧 Advanced Configuration

### Adjust Search Limit

In `FoodDatabaseService.swift`:

```swift
// Change from 100 to your preferred limit
let response: CloudFoodSearchResponse = try await supabase.functions
    .invoke("usda-food-search", options: FunctionInvokeOptions(
        body: [
            "action": "search",
            "query": query,
            "pageSize": 50, // Adjust this
            "pageNumber": 1
        ]
    ))
```

### Cache Expiration

By default, searches are cached forever. To add expiration:

```sql
-- Add to your SQL schema
ALTER TABLE food_search_cache ADD COLUMN expires_at TIMESTAMPTZ;

-- Update cache cleanup function
CREATE OR REPLACE FUNCTION cleanup_expired_cache()
RETURNS void AS $$
BEGIN
  DELETE FROM food_search_cache 
  WHERE expires_at < NOW();
END;
$$ LANGUAGE plpgsql;
```

---

## 🧪 Testing

### Test Generic Priority

```bash
# Search for common foods
curl -X POST 'YOUR_EDGE_FUNCTION_URL' \
  -H 'Content-Type: application/json' \
  -d '{"action": "search", "query": "chicken breast"}'

# Verify generic chicken breast appears first
# Branded items (Tyson, Perdue) should be at the end
```

### Test Categories

Good test queries:
- ✅ "egg" - Should show eggs, not egg McMuffin
- ✅ "chicken" - Raw chicken before cooked dishes  
- ✅ "apple" - Fresh apples before apple products
- ✅ "scrambled eggs" - Generic scrambled before branded
- ✅ "banana" - Fresh banana first

---

## 📈 Monitoring

### Check Cache Performance

```sql
-- See most searched queries
SELECT search_query, search_count, last_searched_at
FROM food_search_cache
ORDER BY search_count DESC
LIMIT 20;

-- See most logged foods
SELECT name, log_count, search_count
FROM food_items
WHERE log_count > 0
ORDER BY log_count DESC
LIMIT 20;
```

### View User Activity

```sql
-- Recent food logs across all users
SELECT 
  fi.name,
  COUNT(*) as times_logged,
  COUNT(DISTINCT ufh.user_id) as unique_users
FROM user_food_history ufh
JOIN food_items fi ON fi.id = ufh.food_item_id
WHERE ufh.logged_at >= NOW() - INTERVAL '7 days'
GROUP BY fi.id, fi.name
ORDER BY times_logged DESC
LIMIT 20;
```

---

## 🐛 Troubleshooting

### No results appearing

1. Check edge function is deployed:
   ```bash
   supabase functions list
   ```

2. Check logs:
   ```bash
   supabase functions logs usda-food-search
   ```

3. Verify USDA API key is set:
   ```bash
   supabase secrets list
   ```

### Branded items appearing first

- Check that the SQL ranking function was deployed
- Run the updated SQL schema again
- Clear cache: `DELETE FROM food_search_cache;`

### Slow searches

- First search is slower (calls USDA API)
- Subsequent searches use cache (instant)
- Monitor with: `SELECT source, COUNT(*) FROM (SELECT 'cache' as source FROM food_search_cache) GROUP BY source;`

---

## 🎉 You're Done!

Your food tracking system is now:
- ✅ **100% cloud-based** - All data in Supabase
- ✅ **Lightning fast** - Cached searches return instantly
- ✅ **Smart ranking** - Generic foods first, branded last
- ✅ **User-friendly** - History, favorites, and popular foods
- ✅ **Scalable** - Handles unlimited users and searches

Search for "egg", "chicken", "apple" in your app and watch generic items appear first! 🎯

---

## 📚 Files Reference

- `supabase_food_tracking_setup.sql` - Database schema
- `supabase_edge_function_usda_proxy.ts` - Edge function with ranking
- `FoodDatabaseService.swift` - Swift client for cloud database
- `USDAFoodService.swift` - Food search service
- `FoodSearchView.swift` - UI for food search

---

Need help? Check the Supabase logs:
```bash
supabase functions logs usda-food-search --tail
```

