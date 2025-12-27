# Performance Baseline Report
**Date**: December 22, 2025 (Before Optimization)  
**Source**: Supabase Query Performance Statements CSV

---

## 📊 TOP 10 SLOWEST QUERIES (BASELINE)

### 1. 🔴 Exercises Query (authenticated users)
- **Query**: `SELECT * FROM exercises WHERE is_custom = false`
- **Calls**: 6,626
- **Average Time**: 44.15 ms
- **Total Time**: 292,522 ms (4.9 minutes)
- **% of Total**: 27.58%
- **Status**: ❌ NO INDEX on `is_custom`

### 2. 🔴 Exercises Query (anonymous users)
- **Query**: `SELECT * FROM exercises WHERE is_custom = false`
- **Calls**: 2,882
- **Average Time**: 52.20 ms
- **Total Time**: 150,447 ms (2.5 minutes)
- **% of Total**: 14.18%
- **Status**: ❌ NO INDEX on `is_custom`

### 3. 🔴 Timezone Query (Dashboard)
- **Query**: `SELECT name FROM pg_timezone_names`
- **Calls**: 210
- **Average Time**: 512.65 ms
- **Total Time**: 107,655 ms (1.8 minutes)
- **% of Total**: 10.15%
- **Status**: ⚠️ Dashboard query (not app)

### 4. 🟡 Exercises Query (authenticated - variant)
- **Calls**: 3,391
- **Average Time**: 30.02 ms
- **Total Time**: 101,782 ms (1.7 minutes)
- **% of Total**: 9.60%

### 5. 🟡 Exercises Query (authenticated - variant)
- **Calls**: 3,020
- **Average Time**: 20.30 ms
- **Total Time**: 61,310 ms (1.0 minute)
- **% of Total**: 5.78%

### 6. 🟡 Step Tracking Upserts
- **Query**: `INSERT INTO step_tracking ... ON CONFLICT (user_id, date) DO UPDATE`
- **Calls**: 9,787
- **Average Time**: 5.72 ms
- **Total Time**: 55,986 ms (56 seconds)
- **% of Total**: 5.28%
- **Status**: ⚠️ Individual calls (not batched)

### 7. 🔴 Functions Metadata Query
- **Calls**: 502
- **Average Time**: 109.43 ms
- **Total Time**: 54,932 ms (55 seconds)
- **% of Total**: 5.18%
- **Status**: ⚠️ Dashboard query

### 8. 🟡 Exercises Query (anonymous - variant)
- **Calls**: 1,542
- **Average Time**: 32.74 ms
- **Total Time**: 50,478 ms (50 seconds)
- **% of Total**: 4.76%

### 9. 🟢 Video Filename Query
- **Query**: `SELECT name, video_filename, video_code, gender FROM exercises WHERE video_filename IS NOT NULL`
- **Calls**: 2,081
- **Average Time**: 12.63 ms
- **Total Time**: 26,287 ms (26 seconds)
- **% of Total**: 2.48%
- **Status**: ❌ NO INDEX on `video_filename`

### 10. 🟡 Exercises Query (anonymous - variant)
- **Calls**: 601
- **Average Time**: 39.25 ms
- **Total Time**: 23,590 ms (24 seconds)
- **% of Total**: 2.22%

---

## 📈 SUMMARY STATISTICS (BASELINE)

### Total Database Query Time Analyzed
- **Total Time**: 1,060,611 ms (~17.7 minutes)
- **Total Queries**: 31,245+ calls

### Exercises Table Issues
- **Total Exercise Queries**: ~17,000+ calls
- **Total Time on Exercise Queries**: ~640 seconds (10.7 minutes)
- **% of All Query Time**: ~60%
- **Primary Issue**: Missing index on `is_custom` column

### Query Time Distribution
| Category | Time (seconds) | % of Total |
|----------|---------------|------------|
| Exercise queries (no index) | 640 | 60.3% |
| Dashboard queries | 163 | 15.4% |
| Step tracking (individual) | 56 | 5.3% |
| Video queries (no index) | 26 | 2.5% |
| Other | 176 | 16.6% |

### Average Query Times (Before)
- Exercise list (is_custom filter): **20-938ms** (avg 44ms)
- Video filename queries: **2-355ms** (avg 12.6ms)
- Step tracking upserts: **0.2-388ms** (avg 5.7ms)

---

## 🎯 OPTIMIZATION APPLIED (2025-12-22)

### Database Changes
✅ Added `idx_exercises_is_custom` index  
✅ Added `idx_exercises_is_custom_name` composite index  
✅ Added `idx_exercises_video_filename` partial index  
✅ Created `mv_public_exercises` materialized view (8.2 MB cache)  
✅ Set up auto-refresh triggers  

### Swift Code Changes
✅ Added `batchSaveStepData()` function in `SupabaseManager.swift`  
✅ Updated `fetchAllExercises()` to use materialized view  
✅ Updated `syncWeeklyStepsToCloud()` to batch operations  

---

## 📊 EXPECTED IMPROVEMENTS (Target for Tomorrow)

### Exercise Queries
- **Expected Calls**: Similar (~17,000)
- **Expected Avg Time**: 1-10ms (90% improvement)
- **Expected Total Time**: 60-170 seconds (75% improvement)
- **Expected % of Total**: <10% (was 60%)

### Video Queries
- **Expected Calls**: Similar (~2,000)
- **Expected Avg Time**: 1-5ms (70% improvement)
- **Expected Total Time**: 8-10 seconds (65% improvement)

### Step Tracking
- **Expected Calls**: ~100-300 (was 9,787) (97% reduction)
- **Expected Avg Time**: Similar per batch
- **Expected Total Time**: 5-15 seconds (75% improvement)

### Overall Database
- **Expected Total Query Time**: 400-600 seconds (40-60% improvement)
- **Expected Reduction**: 400-600 seconds saved

---

## 🔍 HOW TO COMPARE TOMORROW

### Step 1: Download New CSV (After 24 Hours)
1. Go to **Supabase Dashboard** → **Database** → **Performance**
2. Click **"Enable Performance Advisor"** if needed
3. Wait until **Dec 23, 2025** (24 hours from now)
4. Click **"Download CSV"** button
5. Save as: `Supabase Query Performance Dec-23-2025.csv`

### Step 2: Compare Key Metrics

Look for these improvements in the new CSV:

#### Metric 1: Exercise Query Count
- **Before**: Look for `WHERE is_custom = false` queries
- **After**: Should see far fewer OR same count but much faster times
- **Target**: 75-95% reduction in total time

#### Metric 2: Average Query Times
- **Before (this CSV)**: 20-938ms average 44ms
- **After (tomorrow)**: Should be 1-10ms
- **Target**: 90% faster

#### Metric 3: Total Time on Exercise Queries
- **Before**: 640 seconds (10.7 minutes)
- **After**: Should be 60-130 seconds (1-2 minutes)
- **Target**: 75-90% reduction

#### Metric 4: Step Tracking Calls
- **Before**: 9,787 individual calls
- **After**: Should be ~100-300 batch calls
- **Target**: 97% reduction in call count

### Step 3: Check Index Usage
Run this query in SQL Editor:

```sql
SELECT 
    schemaname, 
    tablename, 
    indexname, 
    idx_scan as times_used,
    idx_tup_read as rows_read,
    idx_tup_fetch as rows_fetched
FROM pg_stat_user_indexes
WHERE tablename IN ('exercises', 'mv_public_exercises')
AND indexname LIKE 'idx_%'
ORDER BY idx_scan DESC;
```

**What to look for:**
- `idx_exercises_is_custom` should have **high `times_used`** (thousands)
- `idx_mv_public_exercises_id` should have **high `times_used`**
- All new indexes should show usage

### Step 4: Check Materialized View Performance
Run this query:

```sql
SELECT 
    matviewname,
    pg_size_pretty(pg_total_relation_size('public.'||matviewname)) as size,
    last_refresh
FROM pg_matviews
WHERE matviewname = 'mv_public_exercises';
```

**What to look for:**
- Size should still be ~8 MB
- `last_refresh` should show recent timestamp (auto-refreshed on changes)

---

## 📝 COMPARISON TEMPLATE (Use Tomorrow)

Copy this and fill in tomorrow's numbers:

```
PERFORMANCE COMPARISON: Dec 22 → Dec 23, 2025

Exercise Queries (is_custom filter):
  Before: 17,062 calls, 640 seconds total, 44ms avg
  After:  _____ calls, _____ seconds total, ___ms avg
  Change: ___% reduction in time

Video Queries:
  Before: 2,081 calls, 26 seconds total, 12.6ms avg
  After:  _____ calls, _____ seconds total, ___ms avg
  Change: ___% reduction in time

Step Tracking:
  Before: 9,787 calls, 56 seconds total
  After:  _____ calls, _____ seconds total
  Change: ___% reduction in calls

Overall Database Query Time:
  Before: 1,061 seconds (17.7 minutes)
  After:  _____ seconds (___ minutes)
  Change: ___% improvement

Top Query (should no longer be exercises):
  Query: _________________
  Time:  _________________
```

---

## 🎯 SUCCESS CRITERIA

Consider the optimization **successful** if tomorrow you see:

✅ Exercise queries are NO LONGER in top 3 slowest queries  
✅ Average exercise query time < 10ms  
✅ Step tracking calls reduced by >90%  
✅ Overall database query time reduced by >40%  
✅ New indexes show high usage in `pg_stat_user_indexes`  

---

## 📂 FILES TO COMPARE

**Baseline (Today)**:
- `/Users/josephreed/Downloads/Supabase Query Performance Statements (ehooeghabzefgoqzugrc).csv`
- This file: `PERFORMANCE_BASELINE_2025-12-22.md`

**Results (Tomorrow)**:
- Download new CSV from Supabase Dashboard
- Create: `PERFORMANCE_RESULTS_2025-12-23.md` with comparison

---

**Set a reminder to check tomorrow!** ⏰ 
Your baseline is documented here. Compare the new CSV to these numbers.

