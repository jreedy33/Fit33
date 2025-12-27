# Supabase Performance Optimization Plan

## Analysis Date: December 22, 2025

## 🔴 Critical Issues Found

### 1. **Exercises Table - Missing Index on `is_custom`** (HIGHEST PRIORITY)
- **Query Count**: 17,000+ calls
- **Total Time**: 443 seconds (27.6% of all query time)
- **Problem**: Filtering by `is_custom` with no index causes full table scans
- **Solution**: Add index on `is_custom` column

### 2. **Timezone Query - Excessive Execution Time**
- **Query Count**: 210 calls  
- **Average Time**: 512ms per query
- **Total Time**: 107 seconds (10.1% of all query time)
- **Problem**: `SELECT name FROM pg_timezone_names` is called repeatedly
- **Solution**: Cache timezone list in application code

### 3. **Step Tracking Upserts - High Volume**
- **Query Count**: 9,787 calls
- **Total Time**: 56 seconds (5.3% of all query time)
- **Problem**: Individual upserts instead of batching
- **Solution**: Add optimized indexes + batch upserts in app

### 4. **Video Filename Queries - No Index**
- **Query Count**: 2,500+ calls
- **Average Time**: 12-17ms per query
- **Total Time**: 34 seconds (3.2% of all query time)
- **Problem**: `WHERE video_filename IS NOT NULL` with no partial index
- **Solution**: Add partial index

## 📊 Performance Impact Summary

**Total Database Query Time Analyzed**: 1,060 seconds  
**Top 4 Issues Account For**: 640 seconds (60% of all query time)

**Expected Improvements After Migration:**
- 40-60% reduction in overall database load
- 50-90% faster exercise queries
- 60-80% faster video queries
- 30-50% faster step tracking operations

## ✅ Action Steps

### Step 1: Apply the Migration (5 minutes)

```bash
# Navigate to Supabase SQL Editor
# Copy and paste the contents of: sql_migrations/optimize_query_performance.sql
# Execute the migration
```

**What This Does:**
- ✅ Adds critical indexes on `exercises.is_custom`
- ✅ Adds partial index on `exercises.video_filename`
- ✅ Adds composite index for common queries
- ✅ Optimizes step/hydration/weight tracking indexes
- ✅ Creates materialized view for public exercises
- ✅ Sets up automatic view refresh triggers
- ✅ Optimizes query planner statistics

### Step 2: Update Application Code (10 minutes)

#### A. Cache Timezone List (Eliminates 10% of query time)

Create a new file `TimezoneCache.swift`:

```swift
class TimezoneCache {
    static let shared = TimezoneCache()
    
    private var timezones: [String]?
    private var lastFetch: Date?
    private let cacheExpiry: TimeInterval = 86400 // 24 hours
    
    func getTimezones() async throws -> [String] {
        // Return cached if valid
        if let timezones = timezones,
           let lastFetch = lastFetch,
           Date().timeIntervalSince(lastFetch) < cacheExpiry {
            return timezones
        }
        
        // Fetch from database (only once per day)
        let tzs = try await supabase.database
            .from("pg_timezone_names")
            .select("name")
            .execute()
            .value as? [[String: String]] ?? []
        
        self.timezones = tzs.compactMap { $0["name"] }
        self.lastFetch = Date()
        
        return self.timezones ?? []
    }
}
```

Or better yet, use `TimeZone.knownTimeZoneIdentifiers` directly in Swift:
```swift
// Replace any Supabase timezone queries with:
let timezones = TimeZone.knownTimeZoneIdentifiers
```

#### B. Batch Step Tracking Upserts

In `HydrationService.swift` or wherever step tracking happens:

```swift
// Instead of individual inserts, collect and batch them
func syncStepData(_ steps: [StepData]) async throws {
    // Batch into groups of 100
    let batches = steps.chunked(into: 100)
    
    for batch in batches {
        try await supabase.database
            .from("step_tracking")
            .upsert(batch)
            .execute()
        
        // Small delay between batches to avoid overwhelming DB
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
    }
}
```

#### C. Use Materialized View for Public Exercises

Update exercise queries to use the materialized view:

```swift
// OLD - Slow query
let exercises = try await supabase.database
    .from("exercises")
    .select()
    .eq("is_custom", value: false)
    .execute()

// NEW - Fast cached query (use materialized view)
let exercises = try await supabase.database
    .from("mv_public_exercises")
    .select()
    .execute()

// For custom exercises, still use original table:
let customExercises = try await supabase.database
    .from("exercises")
    .select()
    .eq("is_custom", value: true)
    .eq("user_id", value: userId)
    .execute()
```

### Step 3: Monitor Performance (24 hours)

After 24 hours, run these queries in Supabase SQL Editor:

```sql
-- Check index usage
SELECT 
    schemaname, 
    tablename, 
    indexname, 
    idx_scan as scans,
    idx_tup_read as tuples_read,
    idx_tup_fetch as tuples_fetched
FROM pg_stat_user_indexes
WHERE tablename IN ('exercises', 'step_tracking', 'hydration_tracking')
ORDER BY idx_scan DESC;

-- Check materialized view size and freshness
SELECT 
    schemaname,
    matviewname,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||matviewname)) as size,
    last_refresh
FROM pg_matviews
WHERE matviewname = 'mv_public_exercises';
```

Then re-enable the Performance Advisor in Supabase and download a new CSV to compare.

### Step 4: Optional - Schedule Maintenance Job

Add to your backend or use Supabase Edge Functions:

```sql
-- Run this weekly during off-peak hours (e.g., Sunday 3 AM)
SELECT optimize_high_traffic_tables();
```

Or create a Supabase Edge Function that runs on schedule:

```typescript
// supabase/functions/optimize-db/index.ts
import { createClient } from '@supabase/supabase-js'

Deno.serve(async (req) => {
  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
  )
  
  // Run optimization
  await supabase.rpc('optimize_high_traffic_tables')
  
  return new Response(JSON.stringify({ success: true }), {
    headers: { 'Content-Type': 'application/json' }
  })
})
```

## 🎯 Expected Results

### Before Optimization:
- Exercise queries: 20-938ms (average 44ms)
- Total database time: 1,060 seconds analyzed
- Top issue: 17,000 unindexed queries

### After Optimization:
- Exercise queries: 1-50ms (average 5ms) - **88% faster**
- Materialized view queries: < 1ms - **99% faster**
- Overall load reduction: 40-60%
- Fewer slow queries alerts

## 📝 Notes

1. **Materialized View**: The `mv_public_exercises` view updates automatically when exercises are modified. For custom exercises, continue using the `exercises` table directly.

2. **Statistics**: The migration sets higher statistics targets on frequently queried columns, helping Postgres make better query plans.

3. **Monitoring**: Enable `pg_stat_statements` extension in Supabase for ongoing performance monitoring.

4. **Rollback**: If needed, you can drop the indexes and materialized view:
   ```sql
   DROP MATERIALIZED VIEW IF EXISTS mv_public_exercises CASCADE;
   DROP INDEX IF EXISTS idx_exercises_is_custom;
   -- etc.
   ```

5. **Future Optimization**: Consider adding connection pooling (PgBouncer) if you see connection limit issues.

## 🚀 Quick Start (TL;DR)

1. ✅ Copy `/sql_migrations/optimize_query_performance.sql` to Supabase SQL Editor
2. ✅ Execute the migration
3. ✅ Update app code to use `TimeZone.knownTimeZoneIdentifiers` instead of querying DB
4. ✅ Update app code to query `mv_public_exercises` instead of filtering `exercises`
5. ✅ Wait 24 hours and check performance metrics again

**Estimated Time**: 15 minutes  
**Estimated Performance Gain**: 40-60% reduction in database load

