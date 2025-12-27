# ⚡ Quick Food Database Setup

## 🚀 One Command Setup

```bash
cd "/Users/josephreed/Desktop/Workout App"
./deploy_cloud_food_database.sh
```

That's it! The script will:
1. ✅ Deploy database tables
2. ✅ Deploy edge function
3. ✅ Set USDA API key
4. ✅ Test the setup

---

## 🎯 Expected Behavior

### When you search "egg" in the app:

**✅ TOP RESULTS (Generic)**
1. Egg, whole, raw, fresh
2. Egg, white, raw, fresh
3. Egg, yolk, raw, fresh
4. Scrambled egg
5. Egg, cooked

**❌ BOTTOM RESULTS (Branded)**
- JUST Egg
- Tyson Scrambled Eggs
- McDonald's Egg McMuffin

### When you search "chicken breast":

**✅ TOP RESULTS (Generic)**
1. Chicken, broiler or fryers, breast, skinless, boneless, raw
2. Chicken breast, boneless, skinless
3. Chicken breast, grilled

**❌ BOTTOM RESULTS (Branded)**
- Tyson Grilled Chicken Breast
- Perdue Chicken Breast
- Costco Chicken Breast

---

## 📱 What Changed in Your App

### Before (Direct USDA API)
```
Search "egg" → Call USDA API → 2-3 seconds → Mixed results
```

### After (Cloud-Based)
```
Search "egg" → Check Supabase cache → 0.3 seconds → Generic items first!
```

---

## ✅ Features Now Working

1. **Instant Search** 
   - First search: ~2 seconds (calls USDA API + caches)
   - Subsequent searches: ~0.3 seconds (from cache)

2. **Smart Ranking**
   - Generic foods (produce, meat, eggs) appear first
   - Branded items appear last
   - Exact matches prioritized

3. **User History**
   - Recently logged foods
   - Saved for quick access

4. **Favorites**
   - Star your favorite foods
   - Access them instantly

5. **Popular Foods**
   - See what other users are logging
   - Trending foods surface

---

## 🧪 Testing

Open your app and try these searches:

### Test 1: Generic Foods First
```
Search: "egg"
✅ Should see: Egg, whole, raw, fresh (at top)
❌ Should NOT see: JUST Egg, Tyson eggs (at top)
```

### Test 2: Produce
```
Search: "apple"
✅ Should see: Apple, raw, with skin (at top)
❌ Should NOT see: Apple juice, Apple pie (at top)
```

### Test 3: Meat
```
Search: "chicken"
✅ Should see: Chicken, broilers or fryers (at top)
❌ Should NOT see: Tyson chicken, KFC chicken (at top)
```

### Test 4: Prepared Foods
```
Search: "scrambled eggs"
✅ Should see: Scrambled egg (generic) (at top)
❌ Should NOT see: Restaurant scrambled eggs (at top)
```

---

## 🐛 Troubleshooting

### No Results Appearing

1. Check edge function is deployed:
   ```bash
   supabase functions list
   ```
   Should show: `usda-food-search`

2. Check logs:
   ```bash
   supabase functions logs usda-food-search --tail
   ```

3. Verify API key:
   ```bash
   supabase secrets list
   ```
   Should show: `USDA_API_KEY`

### Branded Items Still Appearing First

- Clear cache in Supabase:
  ```sql
  DELETE FROM food_search_cache;
  ```

- Verify SQL functions deployed:
  ```bash
  # Check Supabase Dashboard → SQL Editor → check for search_foods function
  ```

### App Not Connecting

- Check `SupabaseManager.swift` has correct URL and key
- Verify user is authenticated (cloud features need auth)
- Check Network tab in Xcode debugger

---

## 📊 Monitor Usage

### See Most Searched Foods
```sql
SELECT search_query, search_count 
FROM food_search_cache 
ORDER BY search_count DESC 
LIMIT 10;
```

### See Most Logged Foods
```sql
SELECT name, log_count 
FROM food_items 
WHERE log_count > 0 
ORDER BY log_count DESC 
LIMIT 10;
```

### See Cache Performance
```sql
SELECT 
  COUNT(*) as total_searches,
  AVG(search_count) as avg_searches_per_query
FROM food_search_cache;
```

---

## 🎉 Success Indicators

After setup, you should see:

1. **In App**
   - Search results appear in < 1 second
   - Generic items at top of results
   - Branded items at bottom of results
   - Recent foods section populated after logging

2. **In Supabase Dashboard**
   - `food_items` table has rows (cached foods)
   - `food_search_cache` table has rows (cached searches)
   - `user_food_history` table populates when logging food

3. **In Logs**
   ```bash
   supabase functions logs usda-food-search
   ```
   Should show:
   - ✅ Cache hit for "egg" - X results
   - ✅ Cached X foods
   - ✅ Found X foods from cloud

---

## 🔗 Related Files

- `FoodDatabaseService.swift` - Cloud food client
- `USDAFoodService.swift` - Food search service
- `FoodSearchView.swift` - Search UI
- `supabase_food_tracking_setup.sql` - Database schema
- `supabase_edge_function_usda_proxy.ts` - Edge function

---

## 💡 Tips

1. **First search is slower** - It calls USDA API and caches results
2. **Cache is persistent** - Same search is instant next time
3. **Works offline** - Recent/favorite foods cached locally
4. **Auto-syncs** - Food history syncs across devices
5. **Privacy first** - Only your data is visible to you

---

## 📚 Full Documentation

See `CLOUD_FOOD_DATABASE_SETUP.md` for complete details.

---

Need help? 
- Check Supabase logs: `supabase functions logs usda-food-search --tail`
- Check app console: Look for "[CLOUD]" prefixed logs
- Verify auth: User must be signed in for history/favorites

