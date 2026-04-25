# Fit33 Supabase Database Expert Agent

> **Role**: Single authority on 140+ tables, views, RPCs, migration safety, schema design, data integrity.
>
> Dated migrations, table additions, one-time cleanups, and historical schema fixes live in [`docs/history/SUPABASE_AGENT.md`](docs/history/SUPABASE_AGENT.md).

Cross-cutting rules live in `.cursor/rules/codingrules.mdc` (universal) and `.cursor/rules/supabase-rules.mdc` (auto-loads when editing `supabase/**/*.sql` or `supabase/functions/**/*.ts`).

---

## Invariants (DB-specific — will cause data loss / bypass RLS if violated)

### New table
1. Every `user_id` column MUST be `UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE`.
2. Every user-data table MUST have `ENABLE ROW LEVEL SECURITY` + SELECT/INSERT/UPDATE/DELETE policies scoped to `auth.uid() = user_id`.
3. Every new user-data table MUST be added to `delete_user_account()` RPC in the same PR.
4. Standard columns: `id UUID DEFAULT gen_random_uuid() PRIMARY KEY`, `user_id` (as above), `created_at TIMESTAMPTZ DEFAULT now()`, `updated_at TIMESTAMPTZ DEFAULT now()`.
5. Always index `user_id` (at minimum).

### New view
6. **NEVER use `SECURITY DEFINER` on views.** Always `security_invoker = on`. SECURITY DEFINER views bypass RLS for all callers — Supabase linter flags these as critical.
7. Views queried directly by the app via PostgREST filter by `auth.uid()` in the view definition.
8. Admin/analytics views that aggregate across users live in a non-`public` schema OR stay `public` with `security_invoker = on` + service-role-only access.

### New RPC
9. **`SECURITY DEFINER` RPCs MUST NOT accept a user-id-like parameter** (`p_user_id`, `user_id_to_delete`, …) — use `auth.uid()` inside. If you need to accept one, gate at the top: `IF auth.uid() IS NOT NULL AND p_user_id <> auth.uid() THEN RAISE EXCEPTION 'Forbidden' USING ERRCODE = '42501';` (the `IS NOT NULL` clause lets service role / pg_cron through).
10. Always validate inputs (non-NULL user_id, valid dates).
11. Return structured data (`JSONB` or `RETURNS TABLE`), not `void`.
12. **When deploying an RPC, `DROP FUNCTION IF EXISTS` for every possible parameter-type overload first.** Postgres treats `(TEXT,TEXT)` and `(UUID,UUID)` as separate functions; leaving overloads causes PostgREST "ambiguous function" errors.
13. **RETURNS TABLE + parameter-name collisions:** add `#variable_conflict use_column` at the top of the function body if any parameter name collides with a column name.
14. **RECORD variable init:** never `ROW(0,0,0)` (fields become nameless). Use `SELECT 0 AS field_name, ... INTO v_record`.
15. **`RETURNS jsonb` ↔ Swift `Decodable struct`.** `RETURNS boolean` ↔ `Bool`. If you change a RETURNS clause, update the Swift decoder in `SupabaseManager.swift` / `*Service.swift` in the same commit.
16. **Social column additions patched atomically.** When adding a column (e.g. `is_gold_verified`) that appears in multiple social RPCs, patch ALL affected RPCs in a single migration. Previous split migrations caused later files to overwrite earlier ones.

### Migrations
17. Always wrap in `BEGIN; ... COMMIT;`. Always idempotent (`IF NOT EXISTS`, `DROP ... IF EXISTS` before `CREATE`).
18. Naming: `YYYYMMDD_HH_description.sql` (or `YYYYMMDD_description.sql`). Add to `supabase/MIGRATION_INDEX.md` in the same PR.
19. **Never drop a table without grepping the codebase for references.** `crash_reports` was dropped when empty, but `CrashReportingService.swift` still wrote to it → crashes on every error.
20. `REFRESH MATERIALIZED VIEW CONCURRENTLY` requires a UNIQUE index on the view. Add it before scheduling refreshes.

### Realtime
21. **Realtime-broadcast tables need `REPLICA IDENTITY FULL`** + membership in `supabase_realtime` publication. `exercises` relies on both; removing either breaks live CMS sync.
22. **MVs that mirror realtime tables need a refresh RPC.** `refresh_mv_public_exercises()` is called by the CMS admin API after every `update_exercise` / `delete_exercise` so cold-start users (who read `mv_public_exercises`) see the change.

### Challenge / push
23. **Silent-push rate-limit log is service-role only.** `silent_push_wake_log` has RLS enabled with ZERO policies. Never add a client-readable policy.
24. **Silent pushes do NOT route through `push_notification_queue`.** Queue is for user-visible alerts (retry + quiet hours). Silent pushes are opportunistic fire-and-forget.
25. **`trigger_<x>` pg_cron wrapper pattern is canonical** for any server-scheduled edge-function invocation: read `internal_config` → `net.http_post` with `x-cron-key` service-role JWT. Reuse for every future cron → edge function.

### Daily quests
26. `get_daily_quests` has 16 params (current) including `p_active_step_challenge_target INT DEFAULT 0`. Old 15-arg overload is DROPped. Function respects `quest_templates.requires_context` + `min_workouts`. Hard-day fallback is `['exercise_sets_25','walk_10k_steps','hit_step_goal']` — do NOT revert to `complete_2_workouts` (retired; `is_active = FALSE`; too aggressive).

### WHOOP overlap dedup (2026-04-20)
27. `cardio_workouts` overlap dedup key is `(user_id, canonical_origin)` where `canonical_origin = COALESCE(origin_app, legacy source→origin map)`. Canonical sessionization walks rows by `started_at, id` and picks the highest-quality row per cluster (activity-type specificity +10, HR +3, distance +2, calories +1, duration +1). Client-side `HealthDataService.syncWhoopData` performs the same check pre-insert (±2h fetch window, 50% overlap via shorter-side denominator) so the problem doesn't recur.

### Bug-Intel sweep — overload collapse + fail-loud audits (2026-04-23)
28. **Function-overload collapse is a DB invariant, not a cosmetic cleanup.** `post_workout_activity` coexisted as a 7-arg + 8-arg overload in prod and generated daily `PGRST202` errors. Migration 79 (`20260513_drop_post_workout_activity_overloads.sql`) DROPs both signatures explicitly before `CREATE OR REPLACE`, and closes with a `DO $$` `RAISE EXCEPTION` sanity check that the post-migration `pg_proc` count for that name equals 1. Pattern: any time you change an RPC's arg list, append a similar `DO $$` count check — catching a missed overload in CI beats a week of `PGRST202` in bug intel.
29. **RLS-audit migrations must be fail-loud on schema regressions.** Migration 78 (`20260512_weight_logs_audit.sql`) `RAISE EXCEPTION`s if `weight_logs.user_id` / `weight_goals.user_id` is ever not `uuid` (the 42883 root cause). Migration 77 (`20260511_health_rls_audit.sql`) `RAISE WARNING`s if RLS is disabled on `cardio_workouts` / `daily_activity_summary` / `sleep_logs` (with `to_regclass` guards so missing tables are a no-op instead of a failure). New audit-style migrations SHOULD end with a `DO $$` block that either RAISE NOTICEs success or RAISE EXCEPTIONs if the audited invariant doesn't hold — silent "did nothing" migrations lose the audit signal.
30. **`performance_metrics` + baseline tables are service-role-only for writes beyond the client insert path.** Migration 80 (`20260514_performance_metrics.sql`) creates `bug_intel_baseline_snapshots` with ONE policy `auth.role() = 'service_role'` for SELECT/INSERT/UPDATE/DELETE. The `snapshot_bug_intel_baseline(TEXT)` RPC is `SECURITY DEFINER` and `RAISE EXCEPTION`s if `auth.role() <> 'service_role'`. Do not relax this — anon / authenticated users can still view `bug_intel_improvement_tracker` only because it's a view over snapshot rows the admin already seeded. The `performance_metrics_daily` view must stay `security_invoker = on` so normal users cannot read other users' timings.

### Bug-Intel Phase 12 — call-site capture, auto-resolve, severity score, migration-resolves (2026-04-25)
31. **`bug_intelligence_fingerprints` carries `last_seen_file` / `last_seen_function` / `last_seen_line` / `callsite_first_seen_at`.** Added by `supabase/20260526_bug_intel_callsite_capture.sql`. Hourly cron `bug_intel_backfill_callsites('7 days')` (SECURITY DEFINER, service-role-only — `RAISE EXCEPTION` if not service_role) extracts `x_file`/`x_line`/`x_function` keys from `dev_session_logs.entries` (JSONB) and `additional_context->>'file'/'line'/'function'` from `crash_reports`. The columns are read by the `triage-bugs` Edge Function as the `authoritative_callsite` block — Claude's `file_path` is locked to that when present. The cron is the only writer; never UPDATE these columns from app code. Initial backfill ('30 days') runs once at migration time.
32. **Single-incident transient drain: `bug_intel_resolve_single_incident_transients()` runs nightly at 04:30 UTC.** Defined in `supabase/20260527_bug_intel_single_incident_autoresolver.sql`. SECURITY DEFINER, service-role-only. Auto-resolves rows where `error_class IN ('cancelled','offline','timeout','gateway','auth_expired')` AND `occurrence_count = 1` AND `unique_user_count = 1` AND `last_seen_at < now() - interval '14 days'` AND `status NOT IN ('resolved','wont_fix','duplicate','claimed')`. Sets `auto_resolved_reason = 'transient_single_incident'` and adds an `Auto-merged: …` audit row to `bug_intelligence_reports.review_notes`. Never widen the `error_class` set to non-transient categories (e.g. `pg_constraint_violation`) — those are real bugs and must be triaged.
33. **`severity_score` column + hourly recompute.** Migration `supabase/20260528_bug_intel_severity_score.sql` adds `severity_score NUMERIC(12, 2)` + `severity_score_updated_at TIMESTAMPTZ`. `IMMUTABLE` helper `bug_intel_compute_severity_score(...)` calculates `occurrence_count × √unique_user_count × screen_visibility × build_freshness × source_severity × regression_amplifier × error_class_amplifier`. SECURITY DEFINER cron `bug_intel_recompute_severity()` (service-role-only) runs at `:10 past every hour`; it determines the current app version from recent activity. Used by the CMS list ordering, the markdown export ordering, and surfaced as a pill in the inbox + a line item in the export.
34. **Migration → fingerprint resolution linking.** Convention defined in `supabase/20260529_bug_intel_migration_resolves_link.sql`. Migrations that fix a bug-intel cluster declare `-- Resolves: <fingerprint-md5> <one-line justification>` lines in their header (multiple lines allowed). After deploy, the SECURITY DEFINER RPC `mark_fingerprints_resolved_by_migration(p_migration_id, p_fingerprints, p_pr_url)` flips matching rows to `status='resolved'` with `auto_resolved_reason = 'migration_resolved:<id>'` AND `resolution_pr_url = <migration file>` AND drops an audit row into `bug_intelligence_reports.review_notes`. The IMMUTABLE helper `bug_intel_extract_resolves_directives(migration_body)` parses the directives. Pipeline expectation: a CMS deploy hook (or manual call from a deploy script) feeds these directives to the RPC. Never UPDATE `bug_intelligence_fingerprints.status` directly — the RPC also writes the audit trail.

---

## Database Overview

**Project**: GoFit (`ehooeghabzefgoqzugrc`) · **Region**: us-east-1 · **Engine**: PostgreSQL 17

### Table Categories (abbreviated)

| Category | Tables |
|---|---|
| **User Identity** | `user_profiles`, `user_progress`, `user_push_tokens`, `phone_verifications`, `user_notification_preferences` |
| **Workouts** | `workouts`, `workout_history`, `workout_exercises`, `workout_sets`, `workout_context`, `favorite_workouts` |
| **Exercises** | `exercises` (6428 rows), `exercise_videos`, `custom_exercises`, `exercise_personal_records`, `exercise_performance_history`, `exercise_set_history` |
| **Programs** | `programs`, `program_days`, `program_day_exercises`, `user_active_programs`, `program_day_completions`, … |
| **Challenges** | `group_challenges` + `challenge_participants` + `challenge_daily_progress` + `challenge_reactions` (1v1); `community_challenges` + `community_challenge_participants` + `community_challenge_daily_progress`; `private_challenges` + `private_challenge_members` + `private_challenge_invites` + `private_challenge_daily_progress` + `private_challenge_chat` |
| **Leagues** | `league_tiers`, `league_groups`, `league_members`, `league_history`, `user_league_tier` |
| **Social** | `friendships`, `friend_activity_feed`, `activity_reactions`, `shared_workouts`, `user_blocks`, `contact_joined_notifications`, `user_synced_contacts` |
| **Nutrition** | `meal_logs`, `food_items`, `food_search_cache`, `user_food_history`, `user_favorite_foods` |
| **Health** | `step_tracking`, `sleep_logs`, `heart_rate_daily`, `hydration_*`, `body_composition_logs`, `weight_logs`, `whoop_recovery_data` |
| **Cardio** | `cardio_workouts`, `cardio_personal_records`, `cardio_streaks`, `cardio_weekly_summaries`, `cardio_goals` |
| **Intelligence** | `exercise_user_effectiveness`, `user_performance_trends`, `weekly_volume_trends`, `user_strength_ratios`, `user_learning_profiles`, `user_similarity_profiles`, `exercise_swap_analytics`, … |
| **Gamification** | `achievements`, `user_achievements`, `quest_templates`, `user_daily_quests`, `user_quest_streaks`, `user_streak_tracking` |
| **Admin/System** | `admin_audit_log`, `feature_flags`, `user_reports`, `user_suspensions`, `push_campaigns`, `push_notification_queue`, `app_notifications`, `content_moderation_log`, `silent_push_wake_log`, `ai_chat_history`, `ai_insights` |

Full table inventory lives in [`docs/history/SUPABASE_AGENT.md`](docs/history/SUPABASE_AGENT.md).

### Materialized Views (daily 4 AM via `refresh_engagement_data()` pg_cron)
- `mv_user_engagement_scores` (unique index on `user_id`)
- `mv_retention_cohorts` (unique index on `cohort_week`)
- `mv_onboarding_funnel`
- `mv_public_exercises` (refreshed on-demand after CMS writes via `refresh_mv_public_exercises()`)

---

## Canonical Relationships

- `user_profiles.id` is the central hub. Nearly every table has `user_id FK → user_profiles.id ON DELETE CASCADE`.
- Programs: `programs → program_days → program_day_exercises → program_exercise_substitutes`; runtime tracking in `user_active_programs → program_workout_history → program_day_completions`.
- Challenges split into three parallel systems (1v1 / community / private) — see category table.
- Exercises chain: `exercises → exercise_videos / exercise_personal_records / exercise_performance_history → exercise_set_history`.

### Tables still missing FK constraints (must add)
`activity_recovery_correlation`, `exercise_user_effectiveness`, `set_completion_patterns`, `user_performance_trends`, `weekly_volume_trends`, `nutrition_performance_link`, `user_strength_ratios`, `user_learning_profiles`, `workout_time_performance`, `exercise_swap_analytics`, `equipment_proficiency`.

---

## Pending Migrations

| Migration | Purpose |
|---|---|
| `20260320_sync_profiles_progress.sql` | Fix 6-field desync between `user_profiles` and `user_progress` |
| `20260320_drop_dead_tables.sql` | Drop 13 dead tables (0 rows + 0 code refs — verify before running) |
| `20260320_add_missing_fk_constraints.sql` | FK + indexes for 11 analytics tables |
| `20260320_consolidate_food_history.sql` | `user_food_history_v` view |
| `20260320_fix_rls_policies.sql` | RLS on 7 analytics tables |
| `20260320_fix_performance_history.sql` | Missing `exercise_performance_history` columns |
| `20260321_food_search_integrity.sql` | **BLOCKED** on DB1 fix |

---

## PR Review Checklist
- [ ] FK constraint on every user-data column
- [ ] RLS enabled + policies defined
- [ ] View uses `security_invoker = on` (if applicable)
- [ ] No duplicate data with existing tables
- [ ] Indexes on user_id + common query columns
- [ ] CASCADE delete behavior
- [ ] `SupabaseDTOs.swift` updated (Optional for nullable)
- [ ] `delete_user_account()` updated if new user-data table
- [ ] RPC overloads fully dropped before `CREATE OR REPLACE`
- [ ] Swift decoder updated if `RETURNS` clause changed
- [ ] `MIGRATION_INDEX.md` updated

---

## Quarterly Health Checks
1. Dead table scan (0 rows + 0 code refs).
2. Orphan-row scan (`user_id` not in `user_profiles`).
3. FK constraint audit.
4. RLS audit.
5. `SECURITY DEFINER` function audit (no `user_id`-like params).
6. **SECURITY DEFINER view audit** — all `public` views must use `security_invoker = on`.
7. Index audit (no full scans on large tables).

---

## Interaction
| Agent | How we interact |
|---|---|
| Data & Backend | I design schemas; they implement DTOs + sync in `SupabaseManager.swift` |
| Product Engineer | They describe the feature need; I design minimal schema change |
| Infra & Security | They review RLS + IDOR posture; I implement |
| Quality | They test data integrity; I provide fixtures |
| Fitness Expert | They define exercise relationships; I model in schema |

When another agent needs data work: (1) they describe the feature, not the schema; (2) I check existing tables; (3) I propose minimal schema change; (4) I write the migration with FK + RLS + indexes + cascade; (5) I update this doc + `delete_user_account()`.

---

## Key Files
| File | Purpose |
|---|---|
| `Fit33/SupabaseManager.swift` | Cloud data ops (~4,300 lines) |
| `Fit33/SupabaseDTOs.swift` | Row → Swift mappings |
| `supabase/config.toml` | Project config |
| `supabase/MIGRATION_INDEX.md` | Migration deployment order |
| `supabase/DEPLOYMENT_ORDER.md` | Canonical migration sequence |
| `SECURITY_CHECKLIST.md` | RLS audit (co-owned with Infra) |

---

## See Also
- `DATA_BACKEND_AGENT.md` — DTO + Swift-side sync patterns
- `INFRA_SECURITY_AGENT.md` — edge function auth, IDOR playbooks
- `.cursor/rules/codingrules.mdc` — cross-cutting rules
- `.cursor/rules/supabase-rules.mdc` — SQL/RPC/RLS rules (auto-loads for `supabase/**/*.sql`)
- `docs/history/SUPABASE_AGENT.md` — dated migrations, per-table history
