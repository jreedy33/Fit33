# Scripts

Development and maintenance scripts for BuiltSimple. These are **not** part of the app runtime — they are one-time utilities, test suites, and deployment helpers.

## Python Scripts

| Script | Description |
|--------|-------------|
| `advanced_500_user_audit.py` | Production-ready launch validation with 500 simulated users |
| `alternative_exercise_test_suite.py` | Tests alternative/similar exercise recommendation logic |
| `apply_database_fixes.py` | Applies database fixes to Supabase |
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

## Output Files

These are generated outputs from test runs and audits — safe to delete if not needed:

| File | Description |
|------|-------------|
| `*.json` | Test result data from audit/test scripts |
| `*.pdf` | Generated audit reports |
| `sync_output.log` | Sync script output log |
| `__pycache__/` | Python bytecode cache (auto-generated) |
