# Fit33 Data & Backend Staff Engineer Agent

> **Role**: Supabase schema, RLS, RPCs, Core Data, DTOs, edge functions, data sync.
>
> Dated migration notes, crash-response schema fixes, and feature-by-feature data work live in [`docs/history/DATA_BACKEND_AGENT.md`](docs/history/DATA_BACKEND_AGENT.md).

Cross-cutting rules live once in `.cursor/rules/codingrules.mdc`.

---

## Invariants (DB-specific — will cause data bugs / IDOR / crashes if violated)

### Type safety
1. **UUID type safety.** NEVER use `?? ""` as a fallback for `currentUser?.id.uuidString` in Supabase queries. Always `guard let userId = currentUser?.id else { return }`. Passing empty string to a UUID column causes Postgres `operator does not exist: uuid = text`.
2. **DTO null safety.** Every nullable DB column → Swift `Optional` in the DTO. Safe accessors with defaults (`opponentDisplayName: String { opponent_name ?? "Unknown User" }`).

### Pagination + duplicate fetches
3. **All Supabase fetch queries MUST include `.limit()`.** `fetchWorkoutHistory()` caps at 200; `fetchMealLogs()` caps at 100. Unbounded fetches cause memory spikes proportional to user history.
4. **No duplicate foreground fetches.** Centralized in `Fit33App.swift` scenePhase handler. `DashboardView` only handles dashboard-specific work (meals, hydration, quests). Never duplicate social/challenge/health fetches between App and Dashboard.

### Security (RPCs + views + edge functions)
5. **RLS on every user-data table** — `ALTER TABLE ... ENABLE ROW LEVEL SECURITY` + CRUD policies scoped to `user_id = auth.uid()`. (Also in `codingrules.mdc`.)
6. **Views use `security_invoker = on`.** Never `SECURITY DEFINER` on views in `public`. (Also in `codingrules.mdc`.)
7. **RPC IDOR prevention (MANDATORY).** Every `SECURITY DEFINER` RPC taking a user-id-like parameter (`p_user_id`, `user_id_to_delete`, …) MUST either:
   1. Drop the parameter entirely and use `auth.uid()` (preferred), OR
   2. Guard at the top:
      ```sql
      IF auth.uid() IS NOT NULL AND p_user_id <> auth.uid() THEN
          RAISE EXCEPTION 'Forbidden' USING ERRCODE = '42501';
      END IF;
      ```
   `auth.uid() IS NOT NULL` lets service-role / pg_cron callers through. Canonical: `supabase/20260417_secure_get_friend_ids.sql`.
8. **Edge function CORS.** Import `buildCorsHeaders(req)` from `supabase/functions/_shared/cors.ts`. Never ship `Access-Control-Allow-Origin: *`.
9. **Every new edge function goes into the Edge Function Auth Registry in `INFRA_SECURITY_AGENT.md` in the same PR.**
10. **Edge function input validation at entry point.** Zod or manual. Standard error response: `{ error: string, code: string }`. Never log full phone numbers, auth tokens, or PII.

### Contracts with Swift
11. **Return-type contract with Swift.** SQL `RETURNS jsonb` → Swift decodes a `Decodable struct`, never `Bool`. SQL `RETURNS boolean` → `Bool`. If you change a RETURNS clause, grep the RPC name in `Fit33/SupabaseManager.swift` and all `*Service.swift` and update decoders in the same commit.
12. **SQL `RETURNS TABLE` functions:** set `#variable_conflict use_column` at the top if any parameter name collides with a column name (hard-won 2026-03-29).
13. **SQL RECORD types** — never use anonymous `ROW(0,0,0)` to init a `RECORD`; the fields have no names. Use `SELECT 0 AS field_name, ... INTO v_record` instead.

### Social + moderation
14. **Moderation flip propagates via realtime.** The moderation webhook sets `is_hidden = true` after insert. Any client UI that persists the sender's own row (chat, activity feed) MUST subscribe to `UpdateAction` on that table and drop rows where `is_hidden` flipped true. Canonical: `RealtimeService.subscribeFriendActivityFeed` + `PrivateChallengeService` UPDATE sub. Server RPCs filter hidden rows, but local caches don't refresh without this.
15. **Legacy `group_challenge_members` is revoke-hardened.** RLS enabled; `INSERT/UPDATE/DELETE` revoked from `authenticated`, `ALL` revoked from `anon`. Only `service_role` + SECURITY DEFINER RPCs may write. Use `challenge_participants` for the live challenge system. See `supabase/20260418_group_challenge_members_invariant.sql`.
16. **Social compliance RPCs.** `get_blocked_users()` and `report_content(p_table_name, p_record_id, p_reported_user_id, p_content_snippet, p_reason)` are the canonical App Review compliance surfaces. `report_content` hard-filters `p_table_name` against an allowlist: `private_challenge_chat`, `challenge_reactions`, `shared_workouts`, `group_challenges`, `private_challenges`, `community_challenges`, `friend_activity_feed`, `user_profiles`. Writes to `content_moderation_log` with `flagged_categories=["user_report"]`.

### Realtime
17. **CMS exercise edits flow through realtime.** Saving an exercise in `admin.doublethr33s.com` fires `public.exercises` Realtime → `RealtimeService.subscribeExercises()` → `ExerciseLibraryService.upsertExerciseFromCloud(dto)`. **NEVER** call `forceSyncExercises()` in response (1000× more expensive; wipes Core Data). CMS also fires `rpc('refresh_mv_public_exercises')` so cold starts (which read `mv_public_exercises`) pick up the change. Requires `exercises` in `supabase_realtime` publication with `REPLICA IDENTITY FULL` (`supabase/20260420_exercises_realtime.sql`).

### Repeat-exercise placeholder contract (2026-04-20 — hard-won)
18. `WorkoutManager.initializeSetsForExercise()` / `initializeSetsForExercises()` create **empty** `WorkoutSetData` rows only — never copy previous `weight`/`reps` into `setData`. Previous values render as grey TextField placeholders in `SetRowView` via `previousSet: PreviousSetData?` (sourced from `previousExerciseSets[exerciseId]`). Row count = `max(previousSetCount, userDefaultSetCount)` via `WorkoutManager.previousSetCount(forExerciseId:exerciseName:)`. Same rule in `ActiveWorkoutView+Init.swift` smart-rec path and `loadHistoricalDataForExercise` fallback. `syncSetsWithPreviousData()` ONLY resizes row count (and only when existing rows are empty + not completed). Completion fallback (`SetRowView` checkmark) still resolves missing input from `previousSet`, so tapping ✓ without typing uses last workout's value.
19. **Previous-set data source order:** (1) `PreviewWarmupService.getPreviousSets` pre-warmed cache → (2) `ExerciseHistoryService.shared.previousSetsCache` → (3) Supabase fetch (`exercise_performance_history` + `exercise_set_history`, warmups excluded).
20. **First-time-exercise similar-lift fallback (2026-04-20).** `StrengthProfileRecommendationEngine.getRecommendationsForSets()` has a 3-tier fallback: (1) `ProgressiveWorkoutIntelligence.generateProgressiveSets` (exact-name history); (2) `fetchSimilarExercisePerformance` — uses `SmartExercisePairingEngine.findSubstitutes(for: exercise, limit: 15, userEquipment: nil)` and walks the ranked list returning the first candidate with Core Data history via `fetchLastPerformance(exerciseName:context:)`; (3) generic `generateSmartRecommendation` profile defaults. Tier 2 emits `adjustmentNote: "Based on your <Exercise Name>"` and `confidenceLevel: 0.75`. Positive lookups cached in `similarExerciseCache` (name-keyed, lowercased) and cleared on workout end via `WorkoutManager.clearAllSetsData()` → `clearSimilarExerciseCache()`. Weights between variants can differ (per-hand dumbbell vs. barbell total); pairing score weights equipment overlap so high-ranked candidates are usually same `EquipmentGroup`, but UI always renders this tier as "SUGGESTED" (orange sparkles), never a hard value.

### Migrations
20. **Migration naming:** `YYYYMMDD_HH_description.sql` (or `YYYYMMDD_description.sql`). Always wrap in `BEGIN; ... COMMIT;`. Always idempotent (`IF NOT EXISTS`, `DROP ... IF EXISTS` before `CREATE`). Add every migration to `supabase/MIGRATION_INDEX.md` in the same PR.

### Schema lessons
21. **Never drop tables with active writers.** `crash_reports` was dropped (0 rows at audit) but `CrashReportingService.swift` writes on every error. Always grep the codebase for table references before dropping.
22. `user_push_tokens` requires `UNIQUE(user_id, device_token)` — `onConflict` in `PushNotificationService.swift` depends on it.
23. `collaborative_workout_data` has `user_equipment JSONB` (`20260321_schema_fixes.sql`).

### Supabase Swift client — UUID handling
24. **Pass Swift `UUID` directly to `uuid` columns — NEVER `uuidString` / `String`.** Applies to `.insert()`/`.upsert()` struct fields AND `.eq()` filter values. The Supabase Swift client's `Encodable` conformance serializes `UUID` correctly; passing a `String` causes a type mismatch at the PostgREST boundary. Same-bug repeat offenders: `WeightTrackingService.setWeightGoal`, `logWeight()` — both fixed; don't regress.

### DTO null-safety (reinforces #2)
25. **Integer columns without `NOT NULL DEFAULT` → `decodeIfPresent` + safe default in Swift.** Never assume a DB integer is non-null. Pattern:
    ```swift
    self.reps = try container.decodeIfPresent(Int.self, forKey: .reps) ?? 0
    ```
    Missing a default produces silent decoder failures that drop the entire row.

### Auth-guarded writes
26. **Every Supabase INSERT / UPDATE / DELETE / UPSERT / RPC call MUST check `SupabaseManager.shared.isAuthenticated` first.** `currentUser?.id` is insufficient — a user object can persist in Core Data with an expired Supabase session. Missing this guard caused 9 errors across 7 analytics tables during a single workout save (v1.34). Log guarded skips at `.warning` with category `.auth`.

### Workout save idempotency (calorie patch path)
27. **Never re-save the full workout from the calorie write path.** `ActiveWorkoutView+Persistence.saveWorkoutToAppleHealth()` patches the single `calories_burned` column via `SupabaseManager.updateWorkoutCalories(workoutId:calories:)` — a targeted `.update(["calories_burned"])`. Calling `saveWorkoutToCloud(workout:)` from here (as in v1.34) creates duplicate rows because the primary sync path in `saveWorkoutData()` already saved the workout.

### HealthKit / Strava dedup
28. **NEVER re-introduce `if workout.isFromStrava { continue }` in `HealthDataService`.** The skip was added during a dedup experiment and permanently dropped Strava-via-HealthKit runs for users who don't have Strava OAuth connected. Dedup must happen via the cardio overlap key (`canonical_origin`, see `SUPABASE_AGENT.md` WHOOP/cardio dedup rules), not by skipping a source wholesale.

### Silent-push routing
29. **Silent-push handler time budget is ~30s; self-cap at 25s.** `SilentPushHandler.handle(userInfo:completion:)` MUST call `completion(_:)` within ~30s or iOS penalizes our future background-delivery allocation. Implementation runs a timeout `Task` that calls `completion(.noData)` at 25s. New silent-push `type` strings add a new `case` in `SilentPushHandler.handle` — never overload `challenge_wake`.

---

## Core Data Model
- Stack: `PersistenceController.swift`. Migration failure handler deletes + recreates store (with backup).
- Extensions: `CoreDataExtensions.swift`.
- Views use `@Environment(\.managedObjectContext)` — never `PersistenceController.shared.container.viewContext` directly.
- Context-safety rules (singleton caches, `Task { }` vs `Task.detached`, `bgContext.mergePolicy`, DEBUG `assertContext` guard) live in `.cursor/rules/codingrules.mdc`.

---

## Key Established Rules
- **Strava sync:** `max(stored, incoming)`, never add.
- **Exercise performance table:** columns are `max_weight` / `max_reps` (NOT `best_set_*`).
- **`WeightTrackingService`** is the single source of truth for user weight.
- **Phone matching MUST be server-side** via RPC.

---

## Owned Files
| File | Purpose |
|---|---|
| `SupabaseDTOs.swift` | All Codable structs mapping DB rows |
| `SupabaseManager.swift` (data methods) | Supabase CRUD |
| `PersistenceController.swift`, `CoreDataExtensions.swift` | Core Data stack |
| `ChallengeService.swift`, `FriendService.swift`, `PrivateChallengeService.swift`, `CommunityChallengeService.swift`, `ActivityFeedService.swift` | Social/challenge data ops |
| `MealService.swift`, `FoodDatabaseService.swift` | Nutrition |
| `WorkoutManager.swift` (persistence + set init) | Workout storage |
| `RealtimeService.swift` | Supabase realtime subs |
| `supabase/` | Edge functions + migrations |
| `sql/` | Legacy SQL migrations |
| `SECURITY_CHECKLIST.md` | RLS audit (co-owned with Infra) |
| `supabase/MIGRATION_INDEX.md` | Canonical migration order |

---

## Interaction
| Agent | How we interact |
|---|---|
| Supabase Agent | They design schema, I implement sync + DTOs |
| Infra Agent | They own secrets + edge function access control; I own business logic |
| Product Engineer | They call my services, consume my DTOs |
| Quality Agent | They test data flows; I supply test fixtures |

---

## See Also
- `SUPABASE_AGENT.md` — schema, table relationships, FK/RLS playbooks, 200+ RPCs
- `INFRA_SECURITY_AGENT.md` — Edge Function Auth Registry, secrets
- `.cursor/rules/codingrules.mdc` — cross-cutting rules (Core Data threading, UUID fallback, `UserDefaults.synchronize`, etc.)
- `docs/history/DATA_BACKEND_AGENT.md` — dated migration/schema work
