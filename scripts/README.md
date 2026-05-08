# Scripts

Development and maintenance scripts for BuiltSimple. These are **not** part of the app runtime — they are one-time utilities, test suites, and deployment helpers.

## Python Scripts

| Script | Description |
|--------|-------------|
| `advanced_500_user_audit.py` | Production-ready launch validation with 500 simulated users |
| `alternative_exercise_test_suite.py` | Tests alternative/similar exercise recommendation logic |
| `apply_database_fixes.py` | Applies database fixes to Supabase |
| `audit_exercise_catalog.py` | Catalog-wide auditor — runs every exercise through Claude → `propose_exercise_correction` (same gates as `analyze-quality-workout`). Two phases: `--dry-run` writes proposals to CSV, `--apply <csv>` calls the RPC. See dedicated section below. |
| `audit_metrics.py` | Codebase audit metrics — before/after comparison tool |
| `autogen_test_suite.py` | Auto-generated workout test suite (v1) |
| `autogen_test_suite_v2.py` | Auto-generated workout test suite (v2) |
| `check_profiles.py` | Quick check of all user profiles in the database |
| `classify_difficulty_levels.py` | Classifies exercises by difficulty level |
| `classify_exercises.py` | Classifies exercises into families with swap priorities |
| `comprehensive_500_user_test.py` | 500-user comprehensive workout generation test |
| `comprehensive_audit.py` | 50-user workout generation audit with PDF report |
| `comprehensive_autogen_audit.py` | Full auto-gen workout audit system |
| `comprehensive_goal_audit.py` | Goal-based workout generation audit |
| `create_test_user.py` | Creates test user profiles in the database |
| `exercise_database_audit.py` | Comprehensive audit of the exercise database |
| `exercise_family_swap_test.py` | Tests the exercise family and swap system |
| `favorites_recommendation_test.py` | Tests favorites-aware recommendation engine |
| `fix_exercise_classifications.py` | Fixes exercise classification issues in the database |
| `full_user_simulation_test.py` | Full user simulation test suite |
| `generate_10_user_audit.py` | Generates workouts for 10 diverse user profiles |
| `generate_goal_updates.py` | Generates SQL UPDATEs from goal classification CSV |
| `generate_limitation_filter_report.py` | Generates limitation filter system report |
| `generate_test_report_pdf.py` | Converts auto-gen test results to PDF report |
| `progressive_exercise_test.py` | Tests the progressive exercise system |
| `recommendation_engine_test.py` | Tests the smart recommendation engine |
| `run_100_user_test.py` | 100-user workout generation test |
| `run_comprehensive_autogen_test.py` | Runs Swift test harness and converts report to PDF |
| `run_quality_audit.py` | Automated workout generation quality audit |
| `split_sql_batches.py` | Splits large SQL files into smaller batches for Supabase |
| `sync_complete_final.py` | Syncs all 36 columns from master CSV to Supabase |
| `sync_exercises_detailed.py` | Detailed exercise sync to Supabase |
| `sync_exercises_from_csv.py` | Syncs exercises table with CSV (update/delete) |
| `sync_final_correct.py` | Final corrected exercise sync to Supabase |
| `sync_final_master.py` | Master exercise sync to Supabase |
| `ten_user_autogen_audit.py` | Generates and audits workouts for 10 user profiles |
| `test_joe_autogen.py` | Tests auto-gen workout for a specific user profile |
| `test_joe_improved.py` | Tests improved auto-gen workout for a specific user |
| `test_joe_workout.py` | Tests workout generation for a specific user |
| `update_exercises_from_csv.py` | Updates Supabase exercises table from improved CSV |
| `update_goal_classifications.py` | Updates exercises with goal classification data |
| `workout_combo_rules.py` | Workout combo rules engine — prevents bad exercise combos |

## Shell Scripts

| Script | Description |
|--------|-------------|
| `bump_version.sh` | Bumps app version number (e.g. `./bump_version.sh 1.11.1 1`) |
| `deploy_cloud_food_database.sh` | Deploys cloud food database to Supabase |
| `deploy_cloud_food_tracking.sh` | Deploys cloud food tracking system |
| `extract_for_classification.sh` | Extracts exercise data in batches for AI classification |
| `increment_build.sh` | Auto-increments build number (debug builds only) |
| `increment_version.sh` | Auto-increments patch version in project.pbxproj |
| `perf_lint.sh` | Build-time lint rules (sync Core Data in init, `UserDefaults.synchronize()`, etc.) |
| `pre_commit_migration_check.sh` | Fails commits when staged `supabase/*.sql` files are missing from `supabase/MIGRATION_INDEX.md`. See "Git Hooks" below. |
| `audit_done_claims.sh` | Validates every `[x]` entry in `MASTER_TODO.md` that cites a file path — flags stale references after moves/renames. Run manually. |

## Git Hooks (Opt-In)

Sprint 4 (AGD-8, AGD-9) added a small hook bundle under `.githooks/` that prevents drift in the migration index and (optionally) catches other repo-hygiene issues before commit. Hooks are **opt-in per clone**, never forced via CI.

Enable for your clone:

```bash
git config core.hooksPath .githooks
```

What you get after enabling:

- **`pre-commit`** runs `scripts/pre_commit_migration_check.sh`, which blocks any commit that stages a new `supabase/*.sql` migration without also listing its basename in `supabase/MIGRATION_INDEX.md`.

Bypass in an emergency with `git commit --no-verify` — the hook is intentionally forgiving. To disable again: `git config --unset core.hooksPath`.

## Catalog Audit Sweep (`audit_exercise_catalog.py`)

One-time auditor that runs every exercise in the catalog (~6,300 rows) through the same `analyze-quality-workout` correction pipeline — Claude proposes per-field fixes, the existing `propose_exercise_correction` RPC decides what auto-applies (sister / name / multi-report gate) vs. what queues for admin review at `/catalog-proposals`.

**Why**: the workout-intelligence pipeline only audits an exercise when a user performs it in a quality workout. This script forces a single sweep so the long tail (rarely-used exercises) gets data-quality coverage immediately.

**Architecture**: Python orchestrator → `audit-catalog-exercise` edge function (server-side Claude call, uses `ANTHROPIC_API_KEY` from Supabase secrets, prompt-cached) → `propose_exercise_correction` RPC (in apply phase only).

**Two-phase workflow**:

```bash
# 0. Deploy the edge function once.
supabase functions deploy audit-catalog-exercise

# 1. Test batch — sanity-check Claude's quality on 100 exercises (~$1.50).
python scripts/audit_exercise_catalog.py --dry-run --limit 100

# 2. Eyeball the resulting CSV in scripts/output/. Look for absurd
#    proposals; if any, tighten the prompt before the full run.

# 3. Full dry-run (~6,300 calls, ~$60-80, ~2-3 hours wall-clock).
python scripts/audit_exercise_catalog.py --dry-run --confirm

# 4. Apply phase — calls the propose RPC for each row in the CSV.
#    NO second Claude call. Auto-applied corrections land immediately;
#    pending ones surface in the admin CMS at /catalog-proposals.
python scripts/audit_exercise_catalog.py --apply scripts/output/catalog_audit_<ts>.csv
```

**Idempotency**: the dry-run skips exercises that already have a non-rejected proposal in `exercise_correction_proposals`, AND skips exercises whose `manually_updated_at` is within the last 30 days (override with `--no-skip-existing` and `--skip-recent-days N`). Re-runs are cheap.

**Cost levers**:
- Anthropic prompt caching: the system prompt (~1.1K tokens) is cached at $0.30/MTok for every call after the first. Cuts input cost by ~90%.
- `--limit N`: cap to test batch.
- `--family <name>`: scope to one exercise_family (useful when you've added a batch of new variants).

**Auth**: edge function is service-role-only; the orchestrator uses `SUPABASE_SERVICE_ROLE_KEY` from `.env`.

## Output Files

These are generated outputs from test runs and audits — safe to delete if not needed:

| File | Description |
|------|-------------|
| `*.json` | Test result data from audit/test scripts |
| `*.pdf` | Generated audit reports |
| `sync_output.log` | Sync script output log |
| `__pycache__/` | Python bytecode cache (auto-generated) |
