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
20b. **Postgres has NO `MIN(uuid)` / `MAX(uuid)` aggregate.** Audit blocks that need to surface "first N problematic IDs" MUST use `string_agg(id::text, ', ' ORDER BY created_at)` (with a `LIMIT` in a subquery if needed) or `array_agg(id ORDER BY created_at) [1:5]`. A direct `SELECT MIN(id) FROM ...` over a UUID column fails with `42883 function min(uuid) does not exist` and rolls back the entire `BEGIN;...COMMIT;` migration block. Canonical incident 2026-04-27: migration `20260709_loosen_incomplete_onboarding_cleanup.sql` had an audit block with `MIN(id)` against `user_profiles.id` — entire migration rolled back, cleanup function never deployed, cron stayed broken. Fixed by switching to `string_agg(id::text, ', ' ORDER BY created_at)` with a 5-row subquery limit. When writing a new audit / observability block: prefer `string_agg(... ORDER BY <stable_col>)` over any `MIN`/`MAX` on UUID; keep the row cap inside a subquery so the aggregate operates on the trimmed set.

### Onboarding cleanup contract (2026-04-27)
20c. **`cleanup_incomplete_onboarding_profiles()` deletes `user_profiles WHERE has_completed_onboarding = false AND created_at < NOW() - INTERVAL '1 hour'` — canonical migration `supabase/20260709_loosen_incomplete_onboarding_cleanup.sql`.** Function is `SECURITY DEFINER`, scheduled by `pg_cron` job `cleanup-incomplete-onboarding`. Window was tightened from 30min + multi-field NULL gate (the legacy criteria from `cleanup_incomplete_onboarding.sql`) to a flat 1h with NO data-completeness gate — the original criteria failed when users got partway through the photo / contacts steps before abandoning, leaving their email permanently locked because the original signup row never qualified for cleanup. Per-row `BEGIN ... EXCEPTION WHEN OTHERS THEN` block makes the function FK-block-tolerant: a single row with a non-`ON DELETE CASCADE` FK no longer aborts the entire pass. Defensive `DELETE FROM auth.users WHERE id = v_user.id` mirrors the cascade trigger — never remove this even if the trigger is in place; if the trigger silently breaks, the explicit DELETE is the safety net. **Trailing audit block** is non-optional: counts surviving incomplete profiles >1h old, emits `RAISE WARNING` with up to 5 IDs (via `string_agg`, see invariant 20b) so the next deploy notices new FK regressions. When adding a new social table that references `user_profiles.id`, the FK MUST use `ON DELETE CASCADE` OR `ON DELETE SET NULL` — anything else (`NO ACTION` / `RESTRICT`) re-introduces the locked-email failure mode this migration fixed. `private_challenge_members.invited_by` was the canonical offender; fixed to `ON DELETE SET NULL` in the same migration. NEVER widen the 1h window without fixing the matching `OnboardingSessionManager` "resume after backgrounding" contract first (PE invariant 28-sync-c) — a longer window means users who background-but-return get their session yanked out from under them.

### Realtime
21. **Realtime-broadcast tables need `REPLICA IDENTITY FULL`** + membership in `supabase_realtime` publication. `exercises` relies on both; removing either breaks live CMS sync.
21b. **Social-realtime publication audit list (canonical, 2026-04-27 — migration `supabase/20260708_realtime_social_publication_audit.sql`).** 16 tables MUST be in `supabase_realtime` with `REPLICA IDENTITY FULL`: `friendships`, `shared_workouts`, `challenge_participants`, `challenge_daily_progress`, `group_challenges`, `private_challenges`, `private_challenge_invites`, `private_challenge_members`, `private_challenge_daily_progress`, `private_challenge_chat`, `community_challenges`, `community_challenge_participants`, `community_challenge_daily_progress`, `friend_activity_feed`, `privacy_change_events`, `exercises`. Canonical incident: `friendships` and `shared_workouts` were never explicitly added in any prior migration — `RealtimeService.subscribeFriendActivity` ran without errors but received zero `postgresChange` events, so accepted friend-requests stayed silent on the recipient device until a manual pull-to-refresh, and shared workouts never appeared in the activity feed. Migration #139 is idempotent (`DO $$ ... EXCEPTION WHEN duplicate_object`) — safe to re-run for drift detection. When adding a NEW realtime-broadcast table: (1) `ALTER TABLE ... REPLICA IDENTITY FULL;`, (2) `ALTER PUBLICATION supabase_realtime ADD TABLE ...;`, (3) add the table to migration #139's audit block so future drift check catches a missed step, (4) wire the iOS subscription in `Fit33/RealtimeService.swift`. NEVER skip step (3) — silent realtime failures are nearly impossible to diagnose from client logs (channel reports `joined` with zero events).
22. **MVs that mirror realtime tables need a refresh RPC.** `refresh_mv_public_exercises()` is called by the CMS admin API after every `update_exercise` / `delete_exercise` so cold-start users (who read `mv_public_exercises`) see the change.

### Challenge / push
23. **Silent-push rate-limit log is service-role only.** `silent_push_wake_log` has RLS enabled with ZERO policies. Never add a client-readable policy.
24. **Silent pushes do NOT route through `push_notification_queue`.** Queue is for user-visible alerts (retry + quiet hours). Silent pushes are opportunistic fire-and-forget.
25. **`trigger_<x>` pg_cron wrapper pattern is canonical** for any server-scheduled edge-function invocation: read `internal_config` → `net.http_post` with `x-cron-key` service-role JWT. Reuse for every future cron → edge function.

### Daily quests
26. `get_daily_quests` has 16 params (current) including `p_active_step_challenge_target INT DEFAULT 0`. Old 15-arg overload is DROPped. Function respects `quest_templates.requires_context` + `min_workouts`. Hard-day fallback is `['exercise_sets_25','walk_10k_steps','hit_step_goal']` — do NOT revert to `complete_2_workouts` (retired; `is_active = FALSE`; too aggressive).
26b. **Daily Quests v3 (Smart Adaptive Daily Goals — migrations 20260601–20260607).** `get_daily_quests` v3 takes 9 additional params on top of the existing 16: `p_strava_connected BOOLEAN`, `p_whoop_connected BOOLEAN`, `p_oura_connected BOOLEAN`, `p_fitbit_connected BOOLEAN`, `p_activity_mix JSONB` (`{"dominant":"strength","least":"walk"}`), `p_friend_step_target INT`, `p_friend_name TEXT`, `p_friend_top_workout_id UUID`, `p_friend_top_workout_title TEXT`, `p_friend_top_workout_split TEXT`, `p_friend_top_workout_matches_recommendation BOOLEAN`, `p_quest_tier TEXT` (`'free'`/`'pro'`). All overloads dropped via the canonical `pg_proc` loop pattern (Supabase invariant 12). Six-layer body: (1) workout slot, (2) redundancy, (3) challenge override, (4) **activity-mix bias + per-user weighting** (+30% dominant, +25% top-quartile completion via `user_quest_key_stats`, +10% exploration to least-touched, −90% suppressed), (5) skip-streak floor, (6) friend-named copy + Pro 5-slot expansion. Friend copy is split-recovery-aware: `matches_recommendation=TRUE` writes "Due for chest — do Paul's", FALSE falls back to "Do Paul's <Title>". New context predicates added to the eligibility CTE: `has_strava`, `has_whoop`, `has_oura`, `has_fitbit` (existing `has_wearable` retained as union-OR — finally retires the stub from `20260509_wearable_quests.sql`).
26c. **Per-user learning tables drive the personalization (migration 20260601).** `user_quest_personalization (user_id, category, total_assigned_28d, total_completed_28d, completion_rate_28d, skip_streak, last_completed_at, suppressed_until)` PK `(user_id, category)`, RLS `auth.uid() = user_id`. `user_quest_key_stats` same shape at `quest_key` grain. `user_activity_mix (user_id, computed_at, total_sessions_28d, strength_share, cardio_share, walk_share, stretch_share, dominant_category, least_category)` one row per user. All three tables added to `delete_user_account()` (Supabase invariant 3). New column `quest_templates.tier TEXT NOT NULL DEFAULT 'free' CHECK (tier IN ('free','pro'))` gates Pro-only templates — `tier = 'pro'` rows are excluded from the eligibility pool unless `p_quest_tier = 'pro'`. Suppression contract: when `skip_streak >= 3 AND completion_rate_28d < 0.20`, `suppressed_until = today + 14d`. RPC excludes suppressed `(user_id, category)` and `(user_id, quest_key)` from the pool. **Auto-decays on a single completion** in that category — never extend the window manually.
26d. **Nightly personalization cron (migration 20260602).** `compute_user_quest_personalization()` SECURITY DEFINER, service-role-only — pg_cron at `50 3 * * *` (just after `compute-readiness-insights` at 03:30, before bug-intel sweeps at 04:15/04:30 — invariant 25 staggering). Per user: scans last 28 days of `user_daily_quests` → upserts per-category and per-key stats; computes `skip_streak` by walking `quest_date DESC` and counting consecutive un-completed days; applies suppression rule. Computes `user_activity_mix` from `workouts` (strength) + `cardio_workouts` split by `activity_type`: `walking`/`hike` → walk; `yoga`/`stretch`/`mobility` → stretch; everything else → cardio. Reuses canonical `internal_config` + `x-cron-key`. Initial backfill runs at install so day-one users have data.
26e. **XP rebalance by verification class (migration 20260603).** One-shot `UPDATE quest_templates SET xp_reward = ROUND(xp_reward * mult), league_points = ROUND(league_points * mult)` where `mult` is `auto=1.5`, `social=1.0`, `manual=0.7`. Rationale: auto-verified = provable = pays more; honor-system stays meaningful but lower. The multiplier is **already baked into `quest_templates`** — clients MUST NOT re-multiply. Idempotent via a one-shot guard row in `migration_state`.
26f. **Verification fanout RPCs (migration 20260606).** `verify_strava_quests_for_today(p_timezone)` SECURITY DEFINER, `auth.uid()`-pinned (Data invariant 7) — walks today's `user_daily_quests` for the caller, calls existing `is_strava_quest_completed(...)` per Strava key + new detectors for `beat_your_5k_pr` (queries `cardio_personal_records`), `negative_split_run` (parses `splits_json`), `complete_strava_segment` (reads `segment_efforts_json`), `weekly_mileage_+10pct` (queries `cardio_weekly_summaries`), then calls `update_quest_progress` to flip `is_completed`. `verify_wearable_quests_for_today(p_timezone)` reads today's `daily_readiness_history` row and ticks `recovery_above_67`, `sleep_8h_wearable`, `hrv_above_baseline`, `rhr_in_healthy_range`, `walk_when_red`, `respect_red_recovery`. Both are called from iOS (`StravaService.syncActivities` / `ReadinessService.recompute`) as fire-and-forget detached Tasks — never `await` from the sync return path.
26g. **Pro monetization RPCs (migration 20260607).** `reroll_daily_quest(p_quest_id, p_timezone, p_is_pro)` (Free 1/day cooldown via `user_quest_rerolls` ledger, Pro 5/day no cooldown — replaces one slot with a fresh candidate from the eligibility pool, sets `is_reroll=TRUE`). `claim_double_xp_day(p_date, p_is_pro)` (Pro 1/week via `user_double_xp_claims`, marks day's `user_daily_quests` rows `double_xp=TRUE`; `update_quest_progress` doubles XP at completion). `submit_custom_quest(p_title, p_target_value, p_target_unit, p_is_pro)` (Pro 1/day, manual verification, capped 25 XP, `is_custom=TRUE`). `unsuppress_quest_category(p_category, p_is_pro)` (Pro override — clears `suppressed_until` for one category). All Pro RPCs guard on caller-provided `p_is_pro` (matches existing `p_is_subscriber` pattern in `get_daily_quests` — server-side canonical premium check follows in a future migration). View `v_user_quest_personalization_summary` (`security_invoker = on`) joins `user_quest_personalization` + `user_activity_mix` + computed `state` (`on_fire`/`mixed`/`cold`/`suppressed`) for the Pro Insights screen (`Fit33/QuestInsightsView.swift`).
26h. **Per-category user toggles (migration 20260702 — Daily Goals Insights).** `set_quest_category_enabled(p_category TEXT, p_enabled BOOLEAN, p_is_pro BOOLEAN)` SECURITY DEFINER + `auth.uid()`-pinned (Supabase invariant 9). Pro-only. ON path clears `user_quest_personalization.suppressed_until` (mirrors `unsuppress_quest_category`); OFF path UPSERTs the row with **forever-sentinel** `suppressed_until = '2099-12-31'::DATE`. The eligibility CTE in `get_daily_quests` v3 already excludes any `(user_id, category)` where `suppressed_until > today`, so toggle-off slides into the existing filter without surgery on the 60-line CTE. Auto-suppression caps at +14d, so the +365d sentinel can never collide. Category whitelist is the canonical 5 from the diversity sweep (`workout`, `nutrition`, `steps`, `social`, `tracking`) — defense-in-depth against a malicious client setting `wildcard`/`reward`/arbitrary strings. View `v_user_quest_personalization_summary` recreated with synthetic `user_disabled BOOLEAN` (computed as `suppressed_until > CURRENT_DATE + 365d`) and a new `state` value `'disabled'` so the Pro Insights toggle row can render the correct on/off state. iOS surface: `DailyQuestService.setCategoryEnabled` (Pro-gated client-side) → `fetchDailyQuests(force: true)` on success so the slate refreshes immediately. **NEVER bypass the +365d sentinel by writing a date <14d out** — that would conflict with the adaptive system's auto-suppression window.

### WHOOP overlap dedup (2026-04-20)
27. `cardio_workouts` overlap dedup key is `(user_id, canonical_origin)` where `canonical_origin = COALESCE(origin_app, legacy source→origin map)`. Canonical sessionization walks rows by `started_at, id` and picks the highest-quality row per cluster (activity-type specificity +10, HR +3, distance +2, calories +1, duration +1). Client-side `HealthDataService.syncWhoopData` performs the same check pre-insert (±2h fetch window, 50% overlap via shorter-side denominator) so the problem doesn't recur.

### Bug-Intel sweep — overload collapse + fail-loud audits (2026-04-23)
28. **Function-overload collapse is a DB invariant, not a cosmetic cleanup.** `post_workout_activity` coexisted as a 7-arg + 8-arg overload in prod and generated daily `PGRST202` errors. Migration 79 (`20260513_drop_post_workout_activity_overloads.sql`) DROPs both signatures explicitly before `CREATE OR REPLACE`, and closes with a `DO $$` `RAISE EXCEPTION` sanity check that the post-migration `pg_proc` count for that name equals 1. Pattern: any time you change an RPC's arg list, append a similar `DO $$` count check — catching a missed overload in CI beats a week of `PGRST202` in bug intel.
29. **RLS-audit migrations must be fail-loud on schema regressions.** Migration 78 (`20260512_weight_logs_audit.sql`) `RAISE EXCEPTION`s if `weight_logs.user_id` / `weight_goals.user_id` is ever not `uuid` (the 42883 root cause). Migration 77 (`20260511_health_rls_audit.sql`) `RAISE WARNING`s if RLS is disabled on `cardio_workouts` / `daily_activity_summary` / `sleep_logs` (with `to_regclass` guards so missing tables are a no-op instead of a failure). New audit-style migrations SHOULD end with a `DO $$` block that either RAISE NOTICEs success or RAISE EXCEPTIONs if the audited invariant doesn't hold — silent "did nothing" migrations lose the audit signal.
30. **`performance_metrics` + baseline tables are service-role-only for writes beyond the client insert path.** Migration 80 (`20260514_performance_metrics.sql`) creates `bug_intel_baseline_snapshots` with ONE policy `auth.role() = 'service_role'` for SELECT/INSERT/UPDATE/DELETE. The `snapshot_bug_intel_baseline(TEXT)` RPC is `SECURITY DEFINER` and `RAISE EXCEPTION`s if `auth.role() <> 'service_role'`. Do not relax this — anon / authenticated users can still view `bug_intel_improvement_tracker` only because it's a view over snapshot rows the admin already seeded. The `performance_metrics_daily` view must stay `security_invoker = on` so normal users cannot read other users' timings.

### Strava integration upgrade (2026-04-25)
30-strava. **`cardio_workouts` Strava-detail columns + enrichment partial index.** Migration `supabase/20260530_cardio_workouts_strava_detail.sql` adds `suffer_score INT`, `kudos_count INT`, `achievement_count INT`, `polyline_summary TEXT`, `splits_json JSONB`, `segment_efforts_json JSONB`, `streams_json JSONB`, `gear_name TEXT`, `detail_synced_at TIMESTAMPTZ`. Partial index `idx_cardio_workouts_strava_pending_enrichment ON (user_id, started_at DESC) WHERE source = 'strava' AND detail_synced_at IS NULL` is the hot-path read for `Fit33/StravaActivityEnricher.swift`. The enricher writes to all four JSONB columns + the polyline summary + suffer/kudos/achievement scalars in one round-trip; never split the upsert.
30-strava-2. **Strava daily-quest detection helper.** `supabase/20260531_strava_quest_templates.sql` registers three new `quest_templates` keys (`run_outside_3km`, `run_outside_5km`, `cycle_outside_15km`) AND ships the `is_strava_quest_completed(p_user_id UUID, p_quest_key TEXT, p_timezone TEXT)` SECURITY DEFINER RPC. The RPC pins `auth.uid() = p_user_id` (Data invariant #7), filters `cardio_workouts` on `source IN ('strava')` + `activity_type` (matches `mapStravaActivityType` output: `outdoor_run` / `outdoor_cycle`) + `distance_meters >= target` + day-of in caller timezone. Treadmill / indoor_cycle are explicitly EXCLUDED — these are "outside" quests. To wire the helper into `get_daily_quests`, add the matching branch to the verification block — the templates + helper land first; verification wiring follows in a follow-up migration when we're confident in the matching pattern.
30-strava-3. **`compute-strava-insights` cron mirrors `compute-readiness-insights` exactly.** `supabase/20260532_strava_insights_cron.sql` registers `trigger_compute_strava_insights()` (SECURITY DEFINER, service-role-only) using the canonical `internal_config` + `x-cron-key` pattern (Supabase invariant #25). Schedule: `40 3 * * *` (03:40 UTC) — staggered between `compute-readiness-insights` (03:30) and the bug-intel sweeps (03:45 / 04:30) so cold-starts don't collide. Edge function reads 60d of `cardio_workouts` + `daily_readiness_history` and upserts five insight cards into `user_personalized_insights` keyed `(user_id, insight_key)` (Data invariant #36): `strava_weekly_mileage_delta`, `strava_pace_trend_4w`, `strava_hr_zone_drift`, `strava_segment_pr`, `strava_recovery_pairing`.
30-strava-4. **`user_strava_tokens` table — Phase 5 webhook + dual-write contract.** `supabase/20260533_strava_webhook_tokens.sql` creates the table, RLS (SELECT/UPDATE/DELETE pinned to `auth.uid() = user_id`; INSERT is RPC-only), and two RPCs: `upsert_strava_tokens(p_access TEXT, p_refresh TEXT, p_expires_at TIMESTAMPTZ, p_athlete_id BIGINT DEFAULT NULL)` (SECURITY DEFINER, `auth.uid()`-pinned, `GRANT EXECUTE ... TO authenticated`) AND `get_user_id_for_strava_athlete(p_athlete_id BIGINT)` (SECURITY DEFINER, service-role-only — used by the `strava-webhook` edge function to map Strava `owner_id` → app user_id). Strava rotates the refresh token on every refresh — both the iOS keychain path (`Fit33/StravaService.mirrorTokensToSupabase`) and the edge function refresh path MUST persist the new refresh token; the table's `last_rotated_at` distinguishes which side rotated last. `BEFORE UPDATE` trigger maintains `updated_at`. Add `user_strava_tokens` to `delete_user_account()` (already cascades via `ON DELETE CASCADE` FK to `user_profiles.id`).
30-strava-5. **`strava-webhook` edge function — handshake + delivery contract.** Lives in `supabase/functions/strava-webhook/index.ts`. GET handshake echoes `hub.challenge` only when `hub.verify_token === STRAVA_VERIFY_TOKEN`. POST handler ACKs ≤2s (Strava retry deadline) and processes events asynchronously: resolves `owner_id` → `user_id` via `get_user_id_for_strava_athlete`, refreshes access token if expired (5-min skew buffer), fetches `/activities/{id}?include_all_efforts=true`, upserts `cardio_workouts` keyed on `(user_id, external_id)` with the same Phase 2 column set (origin_app=strava, suffer_score, kudos_count, achievement_count, polyline_summary, splits_json, segment_efforts_json, gear_name, detail_synced_at). Sends `type='strava_activity_new'` silent push only on `aspect_type='create'` — `update` events are noisy. Deploy with `--no-verify-jwt` (Strava sends no Supabase auth header). Required secrets: `STRAVA_CLIENT_ID`, `STRAVA_CLIENT_SECRET`, `STRAVA_VERIFY_TOKEN`, plus the existing `APNS_KEY_ID`/`APNS_TEAM_ID`/`APNS_BUNDLE_ID`/`APNS_PRIVATE_KEY` set used by `wake-challenge-opponents`. Register in the Edge Function Auth Registry in `INFRA_SECURITY_AGENT.md` (Data invariant #9).

### Bug-Intel Phase 12 — call-site capture, auto-resolve, severity score, migration-resolves (2026-04-25)
31. **`bug_intelligence_fingerprints` carries `last_seen_file` / `last_seen_function` / `last_seen_line` / `callsite_first_seen_at`.** Added by `supabase/20260526_bug_intel_callsite_capture.sql`. Hourly cron `bug_intel_backfill_callsites('7 days')` (SECURITY DEFINER, service-role-only — `RAISE EXCEPTION` if not service_role) extracts `x_file`/`x_line`/`x_function` keys from `dev_session_logs.entries` (JSONB) and `additional_context->>'file'/'line'/'function'` from `crash_reports`. The columns are read by the `triage-bugs` Edge Function as the `authoritative_callsite` block — Claude's `file_path` is locked to that when present. The cron is the only writer; never UPDATE these columns from app code. Initial backfill ('30 days') runs once at migration time.
32. **Single-incident transient drain: `bug_intel_resolve_single_incident_transients()` runs nightly at 04:30 UTC.** Defined in `supabase/20260527_bug_intel_single_incident_autoresolver.sql`. SECURITY DEFINER, service-role-only. Auto-resolves rows where `error_class IN ('cancelled','offline','timeout','gateway','auth_expired')` AND `occurrence_count = 1` AND `unique_user_count = 1` AND `last_seen_at < now() - interval '14 days'` AND `status NOT IN ('resolved','wont_fix','duplicate','claimed')`. Sets `auto_resolved_reason = 'transient_single_incident'` and adds an `Auto-merged: …` audit row to `bug_intelligence_reports.review_notes`. Never widen the `error_class` set to non-transient categories (e.g. `pg_constraint_violation`) — those are real bugs and must be triaged.
33. **`severity_score` column + hourly recompute.** Migration `supabase/20260528_bug_intel_severity_score.sql` adds `severity_score NUMERIC(12, 2)` + `severity_score_updated_at TIMESTAMPTZ`. `IMMUTABLE` helper `bug_intel_compute_severity_score(...)` calculates `occurrence_count × √unique_user_count × screen_visibility × build_freshness × source_severity × regression_amplifier × error_class_amplifier`. SECURITY DEFINER cron `bug_intel_recompute_severity()` (service-role-only) runs at `:10 past every hour`; it determines the current app version from recent activity. Used by the CMS list ordering, the markdown export ordering, and surfaced as a pill in the inbox + a line item in the export.
35. **Resolved-fingerprint history table + similar-past-fixes RPC.** Migration `supabase/20260530_bug_intel_resolved_history.sql` adds the append-only `bug_intel_resolved_history` table (one row per terminal-state transition; idempotent on `(fingerprint, resolved_at)`). The trigger `trg_bug_intel_snapshot_resolution` (`AFTER UPDATE OF status`) snapshots `(structural_fingerprint, op, error_class, last_seen_file/function/line, title, summary, agent_owner, severity_score, resolution_pr_url, auto_resolved_reason)` whenever a row flips into `resolved`/`wont_fix`/`duplicate`. The companion RPC `bug_intel_find_similar_resolutions(structural_fingerprint, op, error_class, exclude_fingerprint, limit)` (STABLE, SECURITY DEFINER, service-role-only) returns top-N matches ranked by match_strength: `3` = same structural_fingerprint, `2` = same `(op, error_class)`, `1` = op-only or class-only. It excludes resolutions with `auto_resolved_reason IN ('transient_single_incident','noise_filter_expanded')` (those weren't real fixes). 90-day backfill runs at migration time. NEVER drop the trigger or the RPC — they're the cross-fingerprint memory the Edge Function + CMS markdown export depend on.
36. **Severity-score weights live in `bug_intel_severity_weights` (tunable table), not in code.** Migration `supabase/20260531_bug_intel_severity_weights.sql` moves the multipliers out of the IMMUTABLE compute function into a seeded table (`visibility_high=1.5`, `source_crash=2.0`, `regression_amplifier=3.0`, `class_amp_transient=0.5`, `class_amp_structural=1.5`, build-freshness `{1.0, 0.5, 0.2}`). The `bug_intel_compute_severity_score(...)` function is now STABLE and reads weights via the helper `bug_intel_get_severity_weight(key, default)`. RLS: service-role-only writes; `GRANT EXECUTE` on the helper to `service_role, authenticated` so views can call it. Nightly cron `bug_intel_calibrate_severity_weights(60)` (00:30 UTC, SECURITY DEFINER) writes a JSONB report into `bug_intel_calibration_report` correlating each knob's "knob ON" rows with `real_fix` vs `rejected` outcomes. Auto-tuning is NOT enabled — current report is observability-only; weights stay human-edited (`UPDATE bug_intel_severity_weights SET value = N WHERE key = '...';`) until the report has stabilized for 2+ months. NEVER inline new multipliers into `bug_intel_compute_severity_score` — add them to the seed `INSERT` and reference via `bug_intel_get_severity_weight`.
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
