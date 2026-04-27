-- ============================================================================
-- 20260707 — Add user_daily_quests.bonus_claimed (latent schema bug since
--            2026-03-24)
--
-- WHY (2026-04-27 — bug-intel fingerprints 76860b32, 8e0764bf, 4729e709,
-- 537be0ee — 22 occurrences, 1 user, build 1.38(59), all on 2026-04-27):
--
--   Sample message:
--     `[QUESTS] Failed to fetch: column "bonus_claimed" does not exist`
--     `PostgrestError(... code: "42703", message: "column \"bonus_claimed\"
--      does not exist")`
--
--   The original `daily_quests_migration.sql` `CREATE TABLE
--   user_daily_quests` (lines 32–52) defines columns:
--     id, user_id, quest_date, quest_key, title, description, icon,
--     category, target_value, current_value, target_unit, xp_reward,
--     league_points, difficulty, is_completed, completed_at, created_at
--   It does NOT include `bonus_claimed`.
--
--   Every `get_daily_quests` overload from `20260324_adaptive_quest_selection.sql`
--   forward (current head: `20260703_get_daily_quests_brief_signals.sql` v4)
--   declares `v_bonus_claimed BOOLEAN := FALSE` and runs:
--
--       IF v_all_complete THEN
--           SELECT bonus_claimed INTO v_bonus_claimed
--           FROM user_daily_quests
--           WHERE user_id = v_user_id AND quest_date = v_today
--           LIMIT 1;
--       END IF;
--
--   …gated on `v_all_complete`. Because of the gate, the function works fine
--   for any user who hasn't yet finished all 3 quests today — the SELECT is
--   skipped, no error. The instant a user completes their last quest of the
--   day, every subsequent `get_daily_quests` fetch (foreground refresh,
--   pull-to-refresh, scenePhase wake, brief recompute, quest insights view)
--   raises 42703 and the dashboard slate falls back to the empty
--   `defaultGoals()` placeholder. The user effectively loses their quest UI
--   for the rest of the day. Cluster shape: 5+ tight occurrences right after
--   completing the last quest, then the user closes the app.
--
--   The "claim" half of the contract was also never wired: nothing UPDATEs
--   `bonus_claimed = TRUE`. The companion analytics column `bonus_xp` in the
--   JSON return value is computed as
--     `CASE WHEN v_all_complete AND NOT COALESCE(v_bonus_claimed, FALSE)
--           THEN 50 ELSE 0 END`
--   so once we add the column with `DEFAULT FALSE` it will always read FALSE,
--   and the bonus payload remains 50/30 every fetch. That's the same effective
--   behavior the Swift client has been compiled against for ≥1 year — the
--   client side reads `response.bonusXp` and surfaces it as a one-time UI
--   reward; XP is awarded by `update_quest_progress` on the per-quest
--   completion path, not from this bonus value, so there is no
--   double-award risk from the FALSE default. A future migration can layer
--   on a `claim_quest_bonus(p_date)` RPC that flips the flag once the
--   client books the bonus toast.
--
-- WHAT THIS MIGRATION DOES:
--
--   1. Adds `bonus_claimed BOOLEAN NOT NULL DEFAULT FALSE` to
--      `user_daily_quests` (idempotent — `ADD COLUMN IF NOT EXISTS`).
--      Existing rows backfill to FALSE; the RPC's
--      `NOT COALESCE(v_bonus_claimed, FALSE)` already handles the FALSE
--      case correctly.
--
--   2. NO `get_daily_quests` body change — this column has been read
--      by every overload of the function since 2026-03-24, so adding the
--      column closes the bug at the schema layer without touching any of
--      the 14+ deployed RPC versions.
--
-- ROLLBACK:
--   `ALTER TABLE user_daily_quests DROP COLUMN bonus_claimed;`
--   Safe — no foreign keys depend on it, no index references it. Only
--   undoes the schema fix; the RPC error returns.
--
-- DATA-INVARIANT TRAINING (added to DATA_BACKEND_AGENT.md in this PR):
--   "Every column referenced inside a `SECURITY DEFINER` RPC body MUST
--   exist on the target table from the SAME migration that introduces
--   the read. Conditional-branch reads (`IF v_x THEN SELECT col INTO v
--   …`) are especially dangerous because they hide the bug for as long
--   as the gate stays FALSE — `bonus_claimed` survived 8 months of CI
--   because no test fixture completed all daily quests."
-- ============================================================================

BEGIN;

-- ── 1. Schema: add the column ───────────────────────────────────────────────
ALTER TABLE user_daily_quests
    ADD COLUMN IF NOT EXISTS bonus_claimed BOOLEAN NOT NULL DEFAULT FALSE;

COMMENT ON COLUMN user_daily_quests.bonus_claimed IS
    'TRUE once the all-quests-complete bonus_xp/bonus_league_points payload has been booked by the client. Read by every get_daily_quests overload (gated on v_all_complete). Currently UPSERT side is unwired — claim_quest_bonus(p_date) RPC pending. Default FALSE is intentional: matches existing Swift client behavior where bonus_xp is surfaced to UI but XP is awarded via update_quest_progress, not from this column.';

-- ── 2. Sanity check (no-op for prod, useful for staging verification) ───────
-- Verify the column landed and every RPC overload that reads it can do so
-- without 42703. We just probe a known-no-op SELECT shape; real RPC bodies
-- gate the read behind v_all_complete so this is more documentation than
-- enforcement.
DO $$
DECLARE
    v_test BOOLEAN;
BEGIN
    SELECT bonus_claimed INTO v_test
    FROM user_daily_quests
    WHERE FALSE
    LIMIT 1;
    -- v_test stays NULL; we only care that the SELECT parses + executes.
    RAISE NOTICE 'bonus_claimed column readable on user_daily_quests';
END $$;

COMMIT;
