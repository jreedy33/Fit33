# Supabase Health Checklist
**Date**: December 22, 2025  
**Purpose**: Ensure optimal performance, security, and reliability

---

## ✅ COMPLETED (Just Now)

- [x] **Query Performance** - Added indexes and materialized view
- [x] **Exercises table optimization** - Fixed the #1 bottleneck
- [x] **Step tracking batching** - Swift code optimized

---

## 🔒 SECURITY CHECKS

### 1. Row Level Security (RLS) - **HIGH PRIORITY**

**Status**: ⚠️ Needs Review

You have a migration ready: `sql_migrations/fix_rls_security.sql`

**Check in Supabase Dashboard:**
```
Database → Tables → Select any table → Check if RLS is enabled
```

**Or run this SQL query:**
```sql
-- Check which tables have RLS disabled but have policies
SELECT 
    schemaname, 
    tablename,
    rowsecurity as rls_enabled,
    (SELECT COUNT(*) FROM pg_policies WHERE tablename = pt.tablename) as policy_count
FROM pg_tables pt
WHERE schemaname = 'public'
AND NOT rowsecurity
AND EXISTS (SELECT 1 FROM pg_policies WHERE tablename = pt.tablename)
ORDER BY tablename;
```

**What to look for:**
- If this returns ANY rows → Run `fix_rls_security.sql` migration
- All tables with policies should have RLS enabled

**Action if needed:**
```bash
# Run this migration:
sql_migrations/fix_rls_security.sql
```

### 2. API Keys & Secrets

**Check in Supabase Dashboard:**
```
Settings → API → Check your keys
```

**Verify:**
- ✅ `anon` (public) key is in your app
- ✅ `service_role` key is NEVER in client code
- ⚠️ Service role key should only be in backend/server code
- ✅ JWT Secret is secure

**Security tip**: The `service_role` key bypasses ALL RLS policies. Never expose it!

### 3. Database Roles & Permissions

**Run this query:**
```sql
-- Check role permissions
SELECT 
    grantee, 
    table_schema, 
    table_name, 
    privilege_type
FROM information_schema.role_table_grants 
WHERE table_schema = 'public'
AND grantee IN ('authenticated', 'anon', 'service_role')
ORDER BY table_name, grantee;
```

**What to look for:**
- `authenticated` should have INSERT, UPDATE, DELETE on user tables
- `anon` should only have SELECT on public data (exercises, etc.)
- No excessive permissions

---

## 🚀 PERFORMANCE CHECKS

### 4. Performance Warnings - **MEDIUM PRIORITY**

**Status**: ⚠️ Needs Review

You have a migration ready: `sql_migrations/fix_performance_warnings.sql`

**Check in Supabase Dashboard:**
```
Database → Performance → Check for warnings
```

**Or run this SQL query:**
```sql
-- Check for duplicate indexes (waste of space)
SELECT 
    schemaname,
    tablename,
    indexname
FROM pg_indexes
WHERE schemaname = 'public'
GROUP BY schemaname, tablename, indexname
HAVING COUNT(*) > 1;
```

**Action if needed:**
```bash
# Run this migration to clean up duplicates:
sql_migrations/fix_performance_warnings.sql
```

### 5. Database Size & Storage

**Check in Supabase Dashboard:**
```
Settings → Billing → Database Usage
```

**Run this query to see table sizes:**
```sql
-- Check table sizes
SELECT 
    schemaname,
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS total_size,
    pg_size_pretty(pg_relation_size(schemaname||'.'||tablename)) AS table_size,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename) - pg_relation_size(schemaname||'.'||tablename)) AS indexes_size
FROM pg_tables
WHERE schemaname = 'public'
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC
LIMIT 20;
```

**What to look for:**
- Largest tables should be exercises, workout history, etc.
- Indexes shouldn't be bigger than the table (usually)
- Check if you're approaching storage limits

### 6. Connection Pooling

**Check in Supabase Dashboard:**
```
Settings → Database → Connection pooling
```

**Settings to verify:**
- ✅ **Pool Mode**: Should be `Transaction` for most apps
- ✅ **Max connections**: Default is usually fine
- ⚠️ If you see connection limit errors, consider increasing

**Recommended for mobile apps:**
```
Pool Mode: Transaction
Pool Size: 15 (default is usually good)
```

### 7. Vacuum & Analyze (Maintenance)

**Check when tables were last vacuumed:**
```sql
-- Check vacuum stats
SELECT 
    schemaname,
    relname,
    last_vacuum,
    last_autovacuum,
    last_analyze,
    last_autoanalyze,
    n_dead_tup as dead_tuples
FROM pg_stat_user_tables
WHERE schemaname = 'public'
ORDER BY n_dead_tup DESC
LIMIT 10;
```

**What to look for:**
- `last_autovacuum` should be recent (within days)
- `dead_tuples` should be low (< 1000)
- If dead_tuples is high → run VACUUM

**Manual vacuum if needed:**
```sql
VACUUM ANALYZE exercises;
VACUUM ANALYZE workout_exercises;
-- etc. for large tables
```

---

## 🔌 API & CONFIGURATION

### 8. API Rate Limits

**Check in Supabase Dashboard:**
```
Settings → API → Rate Limiting
```

**Verify:**
- Check if you're hitting rate limits
- Consider increasing for production

**Monitor:**
```
Settings → API → Logs → Look for 429 errors
```

### 9. Database Extensions

**Check what extensions are enabled:**
```sql
-- List installed extensions
SELECT 
    extname,
    extversion
FROM pg_extension
ORDER BY extname;
```

**Recommended extensions for your app:**
- ✅ `pg_stat_statements` - Query performance monitoring (critical!)
- ✅ `uuid-ossp` - UUID generation
- ✅ `pgcrypto` - Encryption functions
- ⚠️ `pg_cron` - For scheduled jobs (if you want automated optimization)

**To enable pg_stat_statements (important!):**
```sql
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
```

This is what powers the Performance Advisor!

### 10. Realtime Configuration (If Used)

**Check if you use Realtime:**
```
Database → Replication → Check if any tables have realtime enabled
```

**Query to check:**
```sql
-- Check realtime publications
SELECT * FROM pg_publication;
SELECT * FROM pg_publication_tables;
```

**Best practice:**
- Only enable realtime on tables that need it
- Realtime can increase database load

---

## 💾 BACKUP & RECOVERY

### 11. Backup Configuration

**Check in Supabase Dashboard:**
```
Settings → Database → Backups
```

**Verify:**
- ✅ Daily backups enabled (Free tier: 7 days, Pro: 30 days)
- ✅ Point-in-time recovery enabled (Pro only)
- ✅ Know how to restore from backup

**Test:** Try downloading a backup to ensure it works

### 12. Database Logs

**Check in Supabase Dashboard:**
```
Logs → Postgres Logs
```

**Look for:**
- ❌ Error messages
- ⚠️ Slow queries (> 1 second)
- ⚠️ Connection errors
- ⚠️ Lock timeouts

---

## 📊 MONITORING & ALERTS

### 13. Performance Metrics

**Dashboard to check daily:**
```
Database → Performance
```

**Key metrics:**
- **CPU Usage**: Should be < 50% average
- **Memory Usage**: Should be < 80%
- **Active Connections**: Should be < 50% of limit
- **Disk I/O**: Spikes are normal, but sustained high I/O is bad

### 14. Slow Query Log

**Enable pg_stat_statements (if not already):**
```sql
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
```

**Monitor slow queries:**
```sql
-- Top 10 slowest queries (by average time)
SELECT 
    LEFT(query, 100) as query_preview,
    calls,
    ROUND(mean_exec_time::numeric, 2) as avg_ms,
    ROUND(total_exec_time::numeric, 2) as total_ms,
    ROUND((100 * total_exec_time / SUM(total_exec_time) OVER ())::numeric, 2) as pct_total
FROM pg_stat_statements
ORDER BY mean_exec_time DESC
LIMIT 10;
```

### 15. Set Up Alerts (Recommended)

**In Supabase Dashboard:**
```
Settings → Alerts (if available)
```

**Or use external monitoring:**
- Sentry for error tracking
- Better Uptime for database downtime alerts
- Datadog/New Relic for advanced monitoring

---

## 🎯 QUICK ACTION ITEMS (Priority Order)

### 🔴 HIGH PRIORITY - Do Today

1. **Run fix_rls_security.sql** (if RLS check shows issues)
   ```bash
   sql_migrations/fix_rls_security.sql
   ```

2. **Enable pg_stat_statements** (if not enabled)
   ```sql
   CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
   ```

3. **Check database size** (ensure not near limits)
   ```sql
   SELECT pg_size_pretty(pg_database_size(current_database()));
   ```

### 🟡 MEDIUM PRIORITY - Do This Week

4. **Run fix_performance_warnings.sql** (clean up duplicates)
   ```bash
   sql_migrations/fix_performance_warnings.sql
   ```

5. **Review API logs** for errors
   ```
   Logs → Postgres Logs
   ```

6. **Check backup configuration**
   ```
   Settings → Database → Backups
   ```

### 🟢 LOW PRIORITY - Do When Convenient

7. **Set up monitoring/alerts**
8. **Review connection pooling settings**
9. **Document your database schema**

---

## 📋 QUICK HEALTH CHECK SQL

Run this comprehensive health check query:

```sql
-- Supabase Health Check
WITH table_stats AS (
    SELECT 
        schemaname,
        tablename,
        pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size,
        n_live_tup as rows,
        n_dead_tup as dead_rows
    FROM pg_stat_user_tables
    WHERE schemaname = 'public'
),
index_usage AS (
    SELECT 
        schemaname,
        tablename,
        COUNT(*) as index_count,
        SUM(idx_scan) as total_scans
    FROM pg_stat_user_indexes
    WHERE schemaname = 'public'
    GROUP BY schemaname, tablename
),
rls_status AS (
    SELECT 
        tablename,
        rowsecurity as rls_enabled
    FROM pg_tables
    WHERE schemaname = 'public'
)
SELECT 
    ts.tablename,
    ts.size,
    ts.rows,
    ts.dead_rows,
    COALESCE(iu.index_count, 0) as indexes,
    COALESCE(iu.total_scans, 0) as index_scans,
    r.rls_enabled
FROM table_stats ts
LEFT JOIN index_usage iu ON ts.tablename = iu.tablename
LEFT JOIN rls_status r ON ts.tablename = r.tablename
ORDER BY pg_total_relation_size('public.'||ts.tablename) DESC
LIMIT 20;
```

**What to look for in results:**
- ✅ Large tables should have multiple indexes
- ✅ `index_scans` should be > 0 (indexes being used)
- ✅ `rls_enabled` should be `true` for user data tables
- ⚠️ `dead_rows` should be low relative to `rows`

---

## 🆘 TROUBLESHOOTING COMMON ISSUES

### Issue: "Too many connections"
**Solution:**
- Enable connection pooling (Transaction mode)
- Reduce max connections in app
- Check for connection leaks in code

### Issue: "Slow queries"
**Solution:**
- Check Performance Advisor (you just did this!)
- Add missing indexes
- Use materialized views for expensive queries
- Consider query optimization

### Issue: "Out of storage"
**Solution:**
- Upgrade plan or
- Delete old data or
- Vacuum to reclaim space:
  ```sql
  VACUUM FULL;
  ```

### Issue: "RLS policy errors"
**Solution:**
- Ensure RLS is enabled: `ALTER TABLE x ENABLE ROW LEVEL SECURITY;`
- Check policies with: `SELECT * FROM pg_policies WHERE tablename = 'your_table';`
- Test policies with different roles

---

## 📝 NOTES

- **Performance optimization is DONE** ✅ (you just applied it)
- **Next check**: Run RLS security check (highest priority)
- **Then**: Run performance warnings cleanup
- **Monitor**: Download new performance CSV in 24 hours

---

## 🔗 USEFUL LINKS

**Supabase Dashboard Sections:**
- Performance: https://supabase.com/dashboard/project/YOUR_PROJECT/database/performance
- Tables: https://supabase.com/dashboard/project/YOUR_PROJECT/editor
- API Settings: https://supabase.com/dashboard/project/YOUR_PROJECT/settings/api
- Backups: https://supabase.com/dashboard/project/YOUR_PROJECT/settings/backups

**Documentation:**
- RLS: https://supabase.com/docs/guides/auth/row-level-security
- Performance: https://supabase.com/docs/guides/platform/performance
- Monitoring: https://supabase.com/docs/guides/platform/logs

---

**Last Updated**: 2025-12-22  
**Status**: Performance ✅ | Security ⚠️ Pending | Monitoring 🟡 Needs Setup

