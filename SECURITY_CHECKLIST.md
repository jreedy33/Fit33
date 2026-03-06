# Security Checklist

## Row Level Security (RLS) Audit

All tables that store or expose user data **must** have RLS enabled with appropriate policies.
The Supabase anon key is included in the client app, so RLS is the **only** barrier preventing
unauthorized data access. If RLS is disabled on any table, that table is publicly readable/writable.

### How to Verify RLS

1. Go to the [Supabase Dashboard](https://supabase.com/dashboard) → your project → **Table Editor**
2. For each table below, click the table name → **Policies** tab
3. Confirm **"Enable RLS"** is toggled ON
4. Confirm appropriate SELECT / INSERT / UPDATE / DELETE policies exist
5. Policies should use `auth.uid()` to scope access to the authenticated user's own rows

### Tables Requiring RLS

| Table | RLS Enabled | Policies Verified | Notes |
|-------|:-----------:|:-----------------:|-------|
| `user_profiles` | ☐ | ☐ | Core user data — must restrict to own profile |
| `workout_history` | ☐ | ☐ | Personal workout logs |
| `meal_logs` | ☐ | ☐ | Nutrition tracking data |
| `user_favorites` | ☐ | ☐ | Saved exercises / items |
| `custom_exercises` | ☐ | ☐ | User-created exercises |
| `bug_reports` | ☐ | ☐ | User-submitted reports — insert-only for users |
| `step_tracking` | ☐ | ☐ | HealthKit step data |
| `food_logs` | ☐ | ☐ | Detailed food tracking entries |

### Additional Tables to Audit

As new tables are added, they should be listed here and verified before deploying.

| Table | RLS Enabled | Policies Verified | Notes |
|-------|:-----------:|:-----------------:|-------|
| *(add new tables here)* | ☐ | ☐ | |

### Periodic Review

- **Frequency:** Review RLS status before every production release
- **Responsibility:** Any developer adding or modifying tables must update this checklist
- **Reference:** See `SupabaseManager.swift` comment block for why this matters
