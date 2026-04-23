# Fit33 Data & Backend Staff Engineer Agent

> **Role**: Supabase schema, RLS, RPCs, Core Data, DTOs, edge functions, data sync.
>
> Dated migration notes, crash-response schema fixes, and feature-by-feature data work live in [`docs/history/DATA_BACKEND_AGENT.md`](docs/history/DATA_BACKEND_AGENT.md).

Cross-cutting rules live in `.cursor/rules/codingrules.mdc` (universal), plus scoped rules that auto-load when editing matching files: `.cursor/rules/swiftui-rules.mdc` (Swift — DTOs, Core Data, sync code) and `.cursor/rules/supabase-rules.mdc` (SQL — migrations, RPCs, RLS).

---

## Invariants (DB-specific — will cause data bugs / IDOR / crashes if violated)

### Type safety
1. **UUID type safety.** NEVER use `?? ""` as a fallback for `currentUser?.id.uuidString` in Supabase queries. Always `guard let userId = currentUser?.id else { return }`. Passing empty string to a UUID column causes Postgres `operator does not exist: uuid = text`.
2. **DTO null safety.** Every nullable DB column → Swift `Optional` in the DTO. Safe accessors with defaults (`opponentDisplayName: String { opponent_name ?? "Unknown User" }`).

### Pagination + duplicate fetches
3. **All Supabase fetch queries MUST include `.limit()`.** `fetchWorkoutHistory()` caps at 200; `fetchMealLogs()` caps at 100. Unbounded fetches cause memory spikes proportional to user history.
4. **No duplicate foreground fetches.** Centralized in `Fit33App.swift` scenePhase handler. `DashboardView` only handles dashboard-specific work (meals, hydration, quests). Never duplicate social/challenge/health fetches between App and Dashboard.
4a. **Wearable `force` flag MUST propagate through `HealthDataService.syncAllHealthData(force:)` to per-source methods** (`syncWhoopData(force:)`, `syncOuraData(force:)`, `syncFitbitData(force:)`). Each wearable service has its own 5-min `syncThrottleInterval`, so a top-level force that stops at HDS silently no-ops downstream — pull-to-refresh and scenePhase force syncs appear to do nothing. Fixed 2026-04-22.
4b. **Wearable widget staleness on tab return** is handled in `MainTabView.onChange(of: selectedTab)`: when returning to Dashboard (tab 0), if `WhoopService.shared.lastSyncDate` / `OuraService.shared.lastSyncDate` is >60s old, trigger a fire-and-forget force sync. Service-level `isSyncing` guard coalesces with any in-flight foreground sync. Never move this into `DashboardView.onAppear` — violates invariant #4.

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
18. **`WorkoutManager.initializeSetsForExercise(s)` creates empty `WorkoutSetData` rows only — never copy previous `weight`/`reps` into `setData`.** Previous values render as grey TextField placeholders in `SetRowView` via `previousSet: PreviousSetData?` (sourced from `previousExerciseSets[exerciseId]`). Row count = `max(previousSetCount, userDefaultSetCount)`. Same rule in `ActiveWorkoutView+Init.swift` smart-rec path + `loadHistoricalDataForExercise` fallback. `syncSetsWithPreviousData()` resizes row count only (when existing rows are empty + not completed). Completion fallback (`SetRowView` ✓) resolves missing input from `previousSet`.
19. **Previous-set data source order:** (1) `PreviewWarmupService.getPreviousSets` pre-warmed cache → (2) `ExerciseHistoryService.shared.previousSetsCache` → (3) Supabase fetch (`exercise_performance_history` + `exercise_set_history`, warmups excluded).
20. **First-time-exercise similar-lift fallback (2026-04-20).** `StrengthProfileRecommendationEngine.getRecommendationsForSets()` walks a 3-tier fallback: (1) `ProgressiveWorkoutIntelligence.generateProgressiveSets` exact-name; (2) `fetchSimilarExercisePerformance` (via `SmartExercisePairingEngine.findSubstitutes`, 15-wide ranked list; first candidate with Core Data history wins via `fetchLastPerformance`); (3) generic `generateSmartRecommendation` profile defaults. Tier 2 emits `adjustmentNote: "Based on your <Exercise Name>"`, `confidenceLevel: 0.75`, cached in `similarExerciseCache` and cleared via `clearAllSetsData()`. UI renders tier 2 as "SUGGESTED" (orange sparkles), never a hard value.

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

### Fit33 ↔ wearable strength dedup (cross-source UI merger)
28b. **Wearable strength duplicates merge in the UI, never stored-side.** Wearable strength HKWorkouts land in `cardio_workouts`; the Fit33 session itself stays in Core Data `Workout`. `WorkoutWearableMerger` (≥50% overlap) drops the cardio row from history lists and exposes enrichment via `enrichmentByWorkoutID`. Call sites that MUST use the merger: `WorkoutHistoryFullView.groupedItems`/`total*`, `DashboardView.rebuildCombinedWorkouts`, `WorkoutHistoryDetailView.loadWearableEnrichment`. Never dedup in the DB — wearable rows are still source of truth for WHOOP widgets, strain analytics, and the Activity tab. Wearable origins: `whoop, oura, fitbit, appleWatch, garmin`. Full rationale + dated hardening history: `docs/history/DATA_BACKEND_AGENT.md`.
28c. **Wearable calories override the MET formula at display time, never in storage.** When merger matches a wearable cardio row to a Fit33 strength `Workout`, every UI call site MUST display `WorkoutWearableMerger.effectiveCalories(workout:wearable:)` — not `workout.caloriesBurned` directly. NEVER overwrite the stored `Workout.caloriesBurned` (cloud sync + historical analytics expect stability; device may be offline when the wearable row arrives later). Canonical call sites: `RecentWorkoutCard.formattedCalories`, `WorkoutHistoryDetailView` stats grid, `WorkoutHistoryFullView.totalCalories`. Header totals + card totals MUST agree (mixing produces "card 420 / total 320" drift). Surface brand next to the overridden value (`<brand> · Calories`).

### Daily Quests — smart hierarchy (2026-04-23)
30. **`get_daily_quests` = single source of truth for slot selection; three layers, don't short-circuit.** Canonical: `supabase/20260423_daily_quest_smart_hierarchy.sql` (19-arg). Layers: (1) slot 1 = `complete_program_day` for program users, `complete_workout` otherwise (never region-specific — 20260422 invariant); (2) REDUNDANCY MATRIX filters `v_redundant_with_workout` from slots 2/3 when slot 1 is a workout quest, unless the CHALLENGE OVERRIDE re-admits it; (3) CATEGORY DIVERSITY sweep forces slot 3 to a distinct category from `{workout, nutrition, steps, tracking, social}`. Every new workout-domain quest template MUST be added to `v_redundant_with_workout`.
31. **Challenge-type → quest-key map is the contract.** `p_active_challenge_types TEXT[]` carries the user's active 1v1 + group `challenge_type` set. Mapping (must stay in sync with `ChallengeType` in `ChallengeService.swift`): `steps/walk/run` → step quest via `p_active_step_challenge_target`; `active_minutes` → `active_minutes_30`; `calories` → `burn_300_calories`; `hydrate` → `log_water_8`; `protein` → `hit_protein_goal`; `workout_streak` → `maintain_streak`; `lift` → `exercise_sets_15`. A new `ChallengeType` case requires (a) a new branch in the migration's challenge-override block, (b) a matching `firstActiveChallenge(matching:)` case in `DailyQuestViews.dynamicDescription`.
32. **Quest description copy ≤35 chars — strict single-line contract.** `DailyQuestViews.compactQuestRow` renders description + progress on one line with `lineLimit(1)`. Applies to BOTH `quest_templates.description` AND `DailyQuestViews.dynamicDescription` rewrites. Helpers: `challengeDeficitCopy(...)` (≤32), `shortOpponentName(...)` (first word, 10-char cap). Never concatenate raw opponent display names into descriptions.

### Silent-push routing
29. **Silent-push handler time budget is ~30s; self-cap at 25s.** `SilentPushHandler.handle(userInfo:completion:)` MUST call `completion(_:)` within ~30s or iOS penalizes our future background-delivery allocation. Implementation runs a timeout `Task` that calls `completion(.noData)` at 25s. New silent-push `type` strings add a new `case` in `SilentPushHandler.handle` — never overload `challenge_wake`.

### Wearable Personalization Platform — Readiness (2026-05-06)
33. **`ReadinessService.shared.recompute(force:)` MUST be called at the tail of `HealthDataService.syncAllHealthData(force:)`.** Wearable signals already updated, blend order deterministic (WHOOP → Oura → Fitbit → HealthKit). Calling it anywhere earlier reads stale `@Published` wearable state. `force` propagates (Data invariant #4a) — pull-to-refresh triggers a real re-blend + Supabase upsert. `recompute()` MUST NOT trigger additional wearable syncs (would recurse).
34. **`daily_readiness_history` upserts use `onConflict: "user_id,date"`.** Client day-of writes and the nightly server rollup (edge fn `compute-readiness-insights`) converge on the same row. DTO contract: Swift `DailyReadinessRow.date` is `yyyy-MM-dd` string (local tz), `band` is `"red"/"yellow"/"green"`, `primary_source` is `"whoop"/"oura"/"fitbit"/"healthkit"/"none"`. SQL CHECK constraints match — changing either side requires the other.
35. **Placeholder readiness snapshots are NEVER written to Supabase.** `SupabaseManager.upsertReadinessSnapshot(_:)` guards on `snapshot.hasWearableSignal`. Writing the `.placeholder()` (yellow, no-wearable) sentinel would pollute the nightly correlation pipeline with noise. Downstream consumers (auto-gen, XP multipliers, quests, challenges) check `hasWearableSignal` before applying any behaviour change — prevents yellow-placeholder from silently capping volume / rewarding XP / advancing wearable quests for users without a connected wearable.
36. **`user_personalized_insights` upserts key on `(user_id, insight_key)`.** Unique index from migration 72 (`20260507_personalized_insights_wearable.sql`). Nightly edge-function reruns MUST upsert (never insert + hope) or users accumulate duplicate cards. `correlation_type` + `r_squared` + `p_value` + `sample_size` fill the significance gate in `v_user_wearable_insights` (p ≤ 0.15, n ≥ 10); legacy rule-based insights with `correlation_type IS NULL` pass through unchanged.
37. **ReadinessService SnapshotProvider is registered in `registerAll()`.** Bug reports surface `todayScore/todayBand/todaySource`, `hasWearableSignal`, per-wearable `isConnected` + `lastSyncAgeSec`. When adding a new wearable vendor, extend `ReadinessService.contributeSnapshot()` with the new connection flag + sync age — "my pill is stuck on yellow" triage depends on it.

### Bug Intelligence export watermark (2026-04-23 — Phase 8)
38. **The Cursor-handoff `.md` export is a WRITE action, not a read.** `get_bug_intelligence_export` in `admin-cms/src/app/api/admin/route.ts` lives in `WRITE_ACTIONS` because its default `mode='new'` path calls `mark_bug_reports_exported(UUID[])` after assembling the bundle. Every export is audit-logged and rate-limited. If you add a read-only variant, pass `mark_as_exported: false` — do not move the action out of `WRITE_ACTIONS`.
39. **"NEW" = unexported OR regressed since the last export.** Filter: `last_exported_at IS NULL OR fingerprint.last_seen_at > last_exported_at`. Terminal fingerprints (`status IN ('resolved', 'wont_fix', 'duplicate')`) are excluded regardless of mode. The partial index `idx_bug_reports_unexported` assumes `review_status IN ('pending', 'approved')` — if you add a new non-terminal `review_status`, extend the partial-index predicate in a new migration; don't just drop the partial clause (wipes the hot-path win).
40. **`mark_bug_reports_exported(UUID[])` is service-role only, and stamps both tables in one call.** Updates `bug_intelligence_reports.last_exported_at` + increments `export_count`, then `UPDATE bug_intelligence_fingerprints.last_exported_at` for the distinct parent fingerprints returned from the first update. Never call it from the client — it bypasses RLS by design.
41. **Terminal cleanup is non-destructive — GitHub is the archive.** `cleanup_stale_bug_reports()` (nightly pg_cron at 04:15 UTC) deletes `bug_intelligence_reports` in `('merged', 'rejected', 'stale')` >14 days old, then drops orphaned terminal fingerprints. The report's `pr_url` / fingerprint's `resolution_pr_url` preserve the fix history in GitHub PRs, so deleted rows remain traceable. Do NOT raise the 14-day window without confirming the PR links are archived on every terminal row (grep the migration's triage output).

### Bug-Intel sweep measurement (2026-04-23 — Cluster I)
42. **`performance_metrics` rows ship from the client, never from triggers.** `Fit33/PerformanceMetricsUploader.swift` drains `PerformanceSignposts.pendingMetrics` every 30s (plus a forced drain on `didEnterBackground`). Writes go through the normal PostgREST path; the RLS policy `user_id = auth.uid() OR user_id IS NULL` allows a shim NULL insert for service-role backfills but production code always sets `user_id` from `SupabaseManager.currentUser?.id`. Do not add a DB trigger that derives `user_id` from `auth.uid()` — the uploader already does that deterministically, and a trigger would double-write on service-role backfills.
43. **`snapshot_bug_intel_baseline(label)` is service-role only and additive.** Each call INSERTs one row per cluster into `bug_intel_baseline_snapshots` — never UPDATEs. The admin CMS `get_bug_intel_improvement_tracker` endpoint reads the latest two snapshots per `cluster_code` via window function. Keep at least 2 snapshots per cluster in prod; deleting rows corrupts the delta. Labels are free-form (`before_sweep_2026_04_23`, `checkpoint_YYYY-MM-DD`) — do not rely on label format in SQL.
44. **Cluster classification keywords are pinned in the RPC.** The `CASE` ladder in `snapshot_bug_intel_baseline()` maps fingerprint titles to cluster codes `A_main_thread / B_rls / C_uuid / D_startup_timeout / E_crashes / F_overloads / G_social / uncategorized` — if you add a new cluster code, you MUST also update `CLUSTER_LABELS` + `CLUSTER_OPS` in `admin-cms/src/app/bug-intelligence/page.tsx` or it will render as its raw code.

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
- `.cursor/rules/swiftui-rules.mdc` — Swift/SwiftUI rules (auto-loads for `Fit33/**/*.swift`)
- `.cursor/rules/supabase-rules.mdc` — SQL/RPC rules (auto-loads for `supabase/**/*.sql`)
- `docs/history/DATA_BACKEND_AGENT.md` — dated migration/schema work
