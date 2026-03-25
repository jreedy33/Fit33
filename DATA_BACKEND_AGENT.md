# Fit33 Data & Backend Staff Engineer Agent

> **Role**: Staff Data & Backend Engineer. Owns Supabase schema, RLS, RPC functions, Core Data, DTOs, data validation, migrations, edge functions.

---

## Mandatory Standards (ALL Agents Must Follow)

1. **Logging**: ALWAYS use `AppLogger` — NEVER `print()`. Categories: `.network`, `.data`, `.workout`, `.social`, `.nutrition`, `.health`, `.ui`, `.performance`, `.auth`, `.general`. Levels: `.debug`, `.info`, `.warning`, `.error`.
2. **No force unwraps** in production code. Use `guard let`, `if let`, or nil-coalescing.
3. **Design tokens**: Use `.ds_*` font tokens and `Color.cardBackground` — no hardcoded `.system(size:)` or local cardBackground properties.
4. **Structured concurrency**: Use `Task { }` with `Task.sleep(for:)` — never `DispatchQueue.main.asyncAfter`.
5. **Accessibility**: All new interactive elements must have `.accessibilityLabel()` and `.accessibilityHint()`.
6. **UUID type safety**: NEVER use `?? ""` as a fallback for `currentUser?.id.uuidString` in Supabase queries. Always use `guard let userId = currentUser?.id else { return }`. Passing an empty string to a UUID column causes Postgres `operator does not exist: uuid = text`.
7. **Cloud sync pagination**: All Supabase fetch queries MUST include `.limit()`. `fetchWorkoutHistory()` caps at 200, `fetchMealLogs()` caps at 100. Never fetch unbounded result sets -- causes memory spikes and slow syncs proportional to user history size.
8. **No duplicate foreground fetches**: Foreground refresh is centralized in `Fit33App.swift` scenePhase handler. DashboardView only handles dashboard-specific work (meals, hydration, quests). NEVER duplicate social/challenge/health fetches between App and Dashboard.

---

## Your Domain

- **Supabase schema** — All tables, columns, indexes, constraints, and relationships
- **RLS** — Every policy on every table
- **RPC functions** — All stored procedures
- **Edge functions** — `send-verification`, `verify-code`, `send-push-notification`, `usda-food-search`, `notify-contacts-user-joined`, `generate-ai-insights`
- **Core Data model** — `Fit33.xcdatamodeld`, `PersistenceController.swift`, `CoreDataExtensions.swift`
- **DTOs** — `SupabaseDTOs.swift`
- **Data sync** — `SupabaseManager.swift` (data methods)
- **SQL migrations** — `sql/` and `supabase/` directories

---

## Principles

1. **Schema is the contract** — If the database allows it, the app must handle it.
2. **RLS is mandatory** — Every user-data table MUST have RLS enabled.
3. **Transactions are atomic** — Multi-step DB ops MUST use BEGIN...EXCEPTION...END.
4. **Nulls are expected** — NULL columns → Swift Optional. COALESCE in SQL.
5. **Validate at the boundary** — Server-side validation is the last line.
6. **Timezone-aware** — All dates UTC `timestamptz`. User-facing dates use user's timezone.

---

## Core Data Model
- `PersistenceController.swift` manages the stack
- Migration failure handler deletes store and recreates (with backup)
- `CoreDataExtensions.swift` provides convenience methods
- **RULE**: Always use `@Environment(\.managedObjectContext)` in views, not `PersistenceController.shared.container.viewContext` directly

---

## Key Standards

### DTO Null Safety
- Every nullable DB column → Swift Optional in DTO
- Always provide safe accessors with defaults (e.g., `opponentDisplayName: String { opponent_name ?? "Unknown User" }`)

### Edge Function Standards
- Every function MUST validate input at entry point (Zod or manual)
- Standard error response: `{ error: string, code: string }`
- NEVER log full phone numbers, auth tokens, or PII

### Migration Rules
- Naming: `YYYYMMDD_HH_description.sql`
- Always wrap in `BEGIN; ... COMMIT;`
- Always include rollback instructions
- Every new migration must be added to `MIGRATION_INDEX.md`

---

## Interaction with Other Agents

| Agent | How You Interact |
|-------|-----------------|
| **Infra/Security Agent** | They define security boundaries (RLS requirements, encryption). You implement them in the schema. |
| **Product Engineer Agent** | They call your services and consume your DTOs. You provide type-safe, null-safe data interfaces. |
| **Quality Agent** | They test your data flows. You provide test fixtures and mock data patterns. |
| **Design Agent** | No direct interaction. |
| **Design System Agent** | No direct interaction. |

---

## Key Rules (Established)

- Strava sync: ALWAYS `max(stored, incoming)`, never add
- Exercise performance table: `max_weight`/`max_reps` column names (not `best_set_*`)
- `WeightTrackingService` is single source of truth for user weight
- Phone matching MUST be server-side via RPC
- `WorkoutManager.initializeSetsForExercise()` must PRE-FILL weight/reps from cached history
- `syncSetsWithPreviousData()` must preserve user-entered data (only overwrite where `isCompleted == false` AND weight/reps == 0)
- Data source order: (1) pre-warmed cache → (2) ExerciseHistoryService → (3) Supabase cloud fetch

---

## Quick Reference: Files You Own

| File | Purpose |
|------|---------|
| `SupabaseDTOs.swift` | All Codable structs mapping to DB rows |
| `SupabaseManager.swift` (data methods) | Supabase CRUD operations |
| `PersistenceController.swift` | Core Data stack management |
| `CoreDataExtensions.swift` | Core Data convenience methods |
| `ChallengeService.swift` | Challenge data operations |
| `FriendService.swift` | Friendship data operations |
| `MealService.swift` | Meal/nutrition data |
| `WorkoutManager.swift` (persistence + set init) | Workout data storage, set pre-fill from history |
| `RealtimeService.swift` | Supabase realtime subscriptions |
| `FoodDatabaseService.swift` | Food search API |
| `supabase/` | Edge functions and migrations |
| `sql/` | SQL migration files |
| `SECURITY_CHECKLIST.md` | RLS audit (co-owned with Infra) |

---

*You are the guardian of data integrity. Every row is correct. Every policy is enforced. Every NULL is handled. Every transaction is atomic. When a view shows the wrong number, the trail leads back to you.*

---

## Remaining Tasks

- Phone number redaction in Twilio edge function logs (M-10, co-owned with Infra)
- Connect real workout volume data to hydration-performance correlation in `PersonalizedInsightsService`

### Schema Rules Learned (March 2026 Session Log Analysis)
- **Never drop tables with active writers** — `crash_reports` was dropped (0 rows at audit) but `CrashReportingService.swift` writes to it on every error. Always grep the codebase for table references before dropping.
- **`user_push_tokens` requires UNIQUE(user_id, device_token)** — the `onConflict` in `PushNotificationService.swift` depends on this constraint.
- **`collaborative_workout_data` has `user_equipment JSONB`** — added via `20260321_schema_fixes.sql`
- **`PersonalizedInsight.userId` is optional** — the RPC may return rows without `user_id` in some edge cases

---

## Developer Logging System (March 2026)

**Tables owned**: `dev_logging_users`, `dev_session_logs`, `dev_log_suggestions`
**Migration**: `supabase/20260321_dev_logging.sql`

**Architecture**:
- Admins toggle logging per-user via CMS → writes to `dev_logging_users`
- iOS checks `is_dev_logging_enabled()` RPC on login → activates `AdvancedSessionLogger`
- Logger batches entries every 5s → inserts to `dev_session_logs` (JSONB entries array)
- Claude analyzes sessions via `/api/dev-log-analysis` → stores suggestions in `dev_log_suggestions`
- CMS can create draft GitHub PRs from suggestions via `/api/github-pr`

**Key rule**: `dev_session_logs` RLS is service-role only. iOS writes via authenticated Supabase client but the table policies allow all operations (the RPC `is_dev_logging_enabled` gates activation). Logs auto-delete after 30 days.

---

## Video Mapping Pipeline (March 2026)

### Authoritative Signal for Video Readiness
- `VideoStreamingService.shared.$videosLoaded` (`@Published private(set) var videosLoaded = false`) is the authoritative signal that video filename mappings are loaded
- `VideoPlaybackEngine` observes this via Combine to set its own `mappingsLoaded` flag — replaces a previous `Thread.sleep(3.0)` approach
- Do NOT introduce alternative readiness signals — always observe `videosLoaded`

### Video Mapping Data Flow
```
App Launch
  → VideoStreamingService.loadVideoMappingsFromDatabase()
    → fetchVideoFilenamesFromServer() (async)
      → Supabase: paginated SELECT on exercises table (batches of 1000, ~6500 rows)
      → Cached for 12 hours (UserDefaults timestamp check)
      → Populates: videoFilenameCache, genderVideoCache, videoURLCache
      → Sets videosLoaded = true
  → VideoPlaybackEngine observes $videosLoaded
    → Sets mappingsLoaded = true
    → Pre-warms favorite exercise videos
```

### Future Consideration
- A `poster_frame_url` column on the `exercises` table could serve CDN-hosted poster thumbnails, eliminating client-side frame extraction for first-view experience
- This would be the highest-impact long-term improvement for instant visual feedback on exercises never viewed before

---

## 2026-03-19: AI Insights Hub

### New Tables Owned
| Table | Purpose | RLS |
|-------|---------|-----|
| `ai_insights` | AI-generated product insights (weekly summaries, trend alerts, recommendations) | Service role write, authenticated read |
| `ai_chat_history` | Admin chat threads with Claude | User-scoped CRUD |

**Migration file**: `supabase/20260319_ai_insights.sql`

### New Edge Function: `generate-ai-insights`
**Path**: `supabase/functions/generate-ai-insights/index.ts`
**Actions**:
- `generate_weekly` — Collects platform data snapshot (users, workouts, exercises, onboarding, social, retention) and sends to Claude for analysis. Stores 4-8 structured insights in `ai_insights`.
- `generate_single` — Same data collection, filtered to a single category.
- `get_data_context` — Returns raw platform data snapshot as JSON (used by CMS chat API to give Claude live data).

**Data queries performed** (all run against Supabase before Claude call):
1. `user_profiles` — total, new 7d/30d
2. `workout_history` — total, 7d/30d counts
3. `exercise_usage_logs` — top 20 popular exercises
4. `onboarding_analytics` — per-step completion/drop-off rates
5. `friendships`, `shared_workouts`, `group_challenges` — social activity 30d
6. `workout_history` — week-over-week retention proxy (users active this week vs last week)

**Secret**: `ANTHROPIC_API_KEY` stored in Supabase Vault. Set via `supabase secrets set ANTHROPIC_API_KEY=sk-ant-...`

### Admin API Actions Added
| Action | Type | Purpose |
|--------|------|---------|
| `get_ai_insights` | read | Fetch insights with optional category/status/priority filters |
| `update_insight_status` | write | Mark insight as read/archived |
| `trigger_insights_generation` | write | Invoke Edge Function to generate new insights |
| `get_chat_history` | read | List admin's chat conversations |
| `get_chat_conversation` | read | Load a specific conversation with messages |
| `save_chat_conversation` | write | Create or update a chat thread |
| `delete_chat_conversation` | write | Delete a chat thread |

### Key Patterns
- Edge Function uses direct `fetch()` to Anthropic API (not an SDK — Deno environment)
- CMS chat route uses `@anthropic-ai/sdk` with streaming via `messages.stream()`
- Claude response is parsed by extracting JSON from the text block (regex `\{[\s\S]*\}`)
- Data snapshots are stored alongside each insight for auditability

### 2026-03-20: Performance Audit — Schema Fixes

**Migration**: `supabase/20260320_fix_performance_history.sql`
- Added `best_set_reps INTEGER` to `exercise_performance_history` (written by WorkoutManager.swift:1361)
- Added `best_set_weight DOUBLE PRECISION` to `exercise_performance_history` (written by WorkoutManager.swift:1360)
- Added `one_rep_max_estimate DOUBLE PRECISION` to `exercise_performance_history` (written by WorkoutManager.swift:1364)
- Added `equipment_used TEXT` to `exercise_performance_history` (written by WorkoutManager.swift:1365)
- Added `program_id TEXT` to `collaborative_workout_data` (written by CollaborativeLearningEngine.swift:144)

**Migration**: `supabase/20260320_fix_rls_policies.sql`
- Added RLS + standard 4-policy CRUD (user_id = auth.uid()) to 7 analytics tables:
  `workout_context`, `user_performance_trends`, `set_completion_patterns`, `user_strength_ratios`, `exercise_user_effectiveness`, `workout_time_performance`, `weekly_volume_trends`
- Added `user_id` indexes on all 7 tables
- All 7 are written by AdvancedIntelligenceService.swift and WorkoutManager.swift

**Status**: Both migrations deployed March 2026

### 2026-03-21: USDA Food Search Integration — Architecture & Audit Fixes

**Audit source**: `USDA_INTEGRATION_AUDIT.md` (branch `claude/audit-usda-integration-fT7My`)

**Edge Function**: `supabase/functions/usda-food-search/index.ts`
- Actions: `search` (USDA API proxy + caching), `details` (single food lookup), `cache_food` (manual cache)
- Makes 3 parallel USDA API calls: Foundation (25), SR Legacy (25), Branded (50)
- Server-side ranking via `calculateFoodScore()` — Foundation > SR Legacy > Branded, cooked > raw for proteins
- Caches results in `food_items` (by fdc_id) + `food_search_cache` (by normalized_query)
- Uses `USDA_API_KEY` from Supabase secrets (never exposed to client)

**3-Layer Caching Strategy**:
| Layer | Location | TTL | Scope |
|-------|----------|-----|-------|
| L1 | iOS `searchCache` dictionary | 5 min | Per-session |
| L2 | `food_search_cache` table | 30 days (via `created_at`) | Global |
| L3 | `food_items` table | Permanent (upsert on re-fetch) | Global |

**Nutrition Data Chain** (per-100g base maintained end-to-end):
USDA API → Edge Function extracts nutrientNumber → `food_items` flat columns → `transformToApiFormat()` → iOS `ProcessedFoodItem` → `FoodDetailsView` scales by `selectedGrams / 100.0`

**Key decisions**:
- `food_items.nutrition_data` JSONB column is actively used as fallback decoder in `FoodDatabaseService.swift` — do NOT drop it
- `loadFrequentFoods()` now uses server-side `get_user_frequent_foods()` RPC (was client-side aggregation)
- Batch upsert in `cacheUSDAFoods()` with per-item fallback on failure
- Best-effort per-IP rate limiting (30 req/min) on edge function
- 401 responses from USDA API logged as `USDA_API_KEY_INVALID` for monitoring

**Migration**: `supabase/20260321_food_search_integrity.sql` — deployed March 2026

### 2026-03-24: Calories Burned — Schema & Sync Changes

**Core Data**: Added `caloriesBurned` (Double, default 0.0) to `Workout` entity in `DataModel.xcdatamodel`. Lightweight migration — no versioning required (new optional attribute with default).

**Supabase**: Migration `20260324_workout_history_calories.sql` adds `calories_burned DOUBLE PRECISION DEFAULT NULL` to `workout_history` table with partial index on non-null values.

**DTO change**: `WorkoutHistoryDTO` in `SupabaseDTOs.swift` now includes `caloriesBurned: Double?` (CodingKey: `calories_burned`). The `saveWorkoutToCloud()` method in `SupabaseManager.swift` passes `workout.caloriesBurned > 0 ? workout.caloriesBurned : nil`.

**Calorie write path**: `ActiveWorkoutView+Persistence.saveWorkoutToAppleHealth()` calculates calories via `HealthKitManager.calculateDetailedCalories()`, saves to `workout.caloriesBurned` on Core Data, then re-upserts to Supabase with the calorie value. This runs as an async Task after `saveWorkoutData()`.

**Third-party workouts**: Calories for HealthKit-sourced workouts already stored via `HealthDataService.saveHealthKitWorkout()` → `cardio_workouts.calories_burned` (from `HKWorkout.totalEnergyBurned`). No changes needed.

### 2026-03-24: Daily Quest Progress — New Server Hooks

**New method**: `DailyQuestService.onProteinProgress(totalGrams:)` — computes the delta between server-side `currentValue` and today's total protein from meals, then calls `reportProgress` with the difference.

**Fixed methods**:
- `onStepsUpdated()`: No longer gates on step threshold — always reports delta for all step quest keys. Server RPC `update_quest_progress` handles capping at `target_value`.
- `onActiveMinutesUpdated()`: Removed `>= 30` gate — always reports.
- `onCaloriesBurned()`: Removed `>= 300` gate — always reports.

**New call sites**:
- `HealthKitManager.fetchTodaySteps()` → `DailyQuestService.shared.onStepsUpdated(todaySteps:)`
- `HealthKitService.syncTodayStats()` → `DailyQuestService.shared.onCaloriesBurned(kcal:)`
- `MealService.addMealEntry()` → `DailyQuestService.shared.onProteinProgress(totalGrams:)`

### 2026-03-21: Notification System — Server-Side Preference Enforcement

**Edge Function**: `supabase/functions/send-push-notification/index.ts`
- Now queries `user_notification_preferences` before sending each push notification
- Skips if `master_enabled = false`, notification type is in `disabled_types`, or user is in quiet hours
- Quiet hours use user's `timezone` (synced from iOS `TimeZone.current.identifier`) to compute local time
- Preference results are cached per-invocation to avoid repeated queries within a batch
- Notifications blocked by preferences are marked as failed with descriptive reasons

**Migration**: `supabase/20260321_notification_preferences.sql` — deployed March 2026

### 2026-03-25: signUp() Resilience Fix (CRITICAL)

**Problem**: `SupabaseManager.signUp()` set `isAuthenticated = true` AFTER both `client.auth.signUp()` AND `createUserProfile()` succeeded. If auth succeeded but profile creation failed, the error propagated up, leaving an orphaned auth user (no session, no profile). On retry, signUp failed with "already registered" — permanent dead end.

**Fix**:
- `signUp()` now sets `currentUser` and `isAuthenticated = true` IMMEDIATELY after `client.auth.signUp()` returns, BEFORE profile creation
- Profile creation failure is caught and logged but no longer throws — the auth user exists and is authenticated
- New public method `ensureProfileExists(userId:name:email:)` wraps `createUserProfile()` for external recovery use
- `createUserProfile()` already uses upsert internally, so calling it again is idempotent

**Impact on data layer**:
- `signUp()` always returns successfully if auth succeeds (profile failure is non-fatal)
- Callers that need the profile can call `ensureProfileExists()` as a repair step
- The `createUserProfile` → `create_user_profile` RPC → fallback direct insert chain is unchanged

**Key file**: `SupabaseManager.swift` (signUp method + new ensureProfileExists)

### 2026-03-24: Security Fix — RLS + SECURITY DEFINER Views

**Migration**: `supabase/20260324_security_fixes.sql`

**What changed**:
- `group_challenge_members`: RLS re-enabled with simple `user_id = auth.uid()` CRUD policies (no recursive subqueries). All app access remains via SECURITY DEFINER RPCs.
- `achievements`: RLS enabled with authenticated SELECT-only (static definition table).
- 19 views converted from SECURITY DEFINER to SECURITY INVOKER (`security_invoker = on`).

**Impact on data layer**:
- `weight_statistics` and `body_composition_statistics` (queried by app) still work — underlying tables (`weight_logs`, `body_composition_logs`) have `user_id = auth.uid()` SELECT policies.
- Admin/analytics views return empty for regular users (correct behavior). Service-role queries unchanged.

**NEW MANDATORY RULE — Views**:
When creating views, NEVER use `SECURITY DEFINER`. All views in the `public` schema MUST use `security_invoker = on`. Views that aggregate across users should be in a non-public schema or accessed only via service-role. See `SUPABASE_AGENT.md` "When Creating a View" for full rules.

### 2026-03-25: v1.33 — Notification & Quest Data Layer Updates

**`app_notifications` table schema** (critical — no `data` JSONB column):
- Columns: `id` (UUID), `user_id` (UUID), `notification_type` (TEXT), `reference_id` (UUID), `from_user_id` (UUID), `title` (TEXT), `body` (TEXT), `is_read` (BOOLEAN), `created_at` (TIMESTAMPTZ)
- When inserting notifications, use `reference_id` and `from_user_id` — NOT a `data` JSONB column (it doesn't exist).

**`accept_friend_request` RPC update**:
- Now inserts into BOTH `push_notification_queue` (type: `friend_accepted`) AND `app_notifications` (type: `friend_request_accepted`).
- Push uses `friend_accepted`; in-app uses `friend_request_accepted`. Both must be handled by iOS `NotificationManager`.

**`get_daily_quests` RPC update** (16 params now, was 15):
- New parameter: `p_active_step_challenge_target INT DEFAULT 0`
- When > 0 and a step quest is selected, the quest target_value is overridden to match the challenge daily target.
- Title/description dynamically generated (e.g. "10K Challenge Steps").
- Old 15-arg function signature was DROPped.

**Core Data threading rules** (reinforced):
- `ExerciseLibraryService.init()` no longer calls `viewContext.count(for:)` synchronously — uses `preWarmCache()` on background context.
- `WorkoutSuggestionEngine` uses a private `bgContext` with `performAndWait` — NOT `viewContext`.
- `SmartExercisePairingEngine.buildPairingDatabase()` uses `container.newBackgroundContext()` — NOT `MainActor.run { getAllExercises() }`.

### 2026-03-25: Crash Report Analysis — Data Layer Fixes

**Hydration streak null safety** (`HydrationService.swift`):
- `HydrationStreaks` struct now has a custom `init(from decoder:)` using `decodeIfPresent` with `?? 0` defaults for `currentStreak`, `totalDaysLogged`, `totalDaysGoalMet`.
- Root cause: `hydration_streaks` table can return NULL for integer columns on newly-created rows. Default `Codable` crashes with `valueNotFound`.
- **RULE**: All Codable DTOs fetching from Supabase tables where integer columns lack `NOT NULL DEFAULT 0` constraints MUST use `decodeIfPresent` with safe defaults. Never assume DB integer columns are non-null.

**Auth guard on data write methods**:
- `WeightTrackingService.logWeight()` now checks `SupabaseManager.shared.isAuthenticated` before the Supabase insert.
- Root cause: expired auth sessions cause RLS rejections on INSERT (`auth.uid()` returns NULL).
- **RULE**: All Supabase INSERT/UPDATE/DELETE calls in service methods (not just RPCs) MUST check `isAuthenticated` first. The existing `currentUser?.id` guard is insufficient — a user object can exist with an expired session token.

**`get_friend_workout_exercises` RPC**:
- Migration `20260325_friend_workout_exercises_rpc.sql` was missing `GRANT EXECUTE ... TO authenticated` — added.
- The function must be deployed to the live database before the social friend workout preview works.
