-- ═══════════════════════════════════════════════════════════════════════════
-- 20260508_user_profiles_after_delete_triggers.sql
--
-- Bug — "Failed to delete table row: ERROR: 27000: tuple to be deleted was
--       already modified by an operation triggered by the current command.
--       HINT: Consider using an AFTER trigger instead of a BEFORE trigger
--       to propagate changes to other rows."
--       (Joe attempting bulk delete of 12 test users from Studio, 2026-05-08).
--
-- ROOT CAUSE
-- ----------
-- `public.user_profiles` has TWO `BEFORE DELETE` row triggers that mutate
-- rows in tables which themselves have `ON DELETE CASCADE` foreign keys
-- back into the same delete chain:
--
--   1. `trigger_delete_auth_user_on_profile_delete`
--        → DELETE FROM auth.identities WHERE user_id = OLD.id
--        → DELETE FROM auth.users      WHERE id      = OLD.id
--      (installed by `complete_account_deletion.sql` and reinstalled by
--      migration #152 `20260721_orphan_auth_user_purge_and_trigger.sql`).
--
--   2. `trg_cleanup_user_quest_personalization`
--        → DELETE FROM user_quest_personalization WHERE user_id = OLD.id
--        → DELETE FROM user_quest_key_stats        WHERE user_id = OLD.id
--        → DELETE FROM user_activity_mix           WHERE user_id = OLD.id
--      (installed by `20260601_user_quest_personalization_schema.sql`).
--
-- The conflict path on `DELETE FROM user_profiles WHERE id = X`:
--   • BEFORE-trigger #2 fires first → deletes user_quest_* rows directly.
--   • BEFORE-trigger #1 fires next → deletes auth.users row.
--   • The auth.users delete cascades to ALL tables whose `user_id` references
--     `auth.users(id) ON DELETE CASCADE` — including user_quest_personalization
--     etc. Those rows were JUST deleted by trigger #2 → "tuple to be deleted
--     was already modified" → SQLSTATE 27000.
--   • Equivalently, the FK from `public.user_profiles.id → auth.users(id)
--     ON DELETE CASCADE` causes the cascade to attempt to re-delete the
--     user_profiles row that's currently being deleted → also 27000.
--
-- The Postgres error message itself recommends the fix: "Consider using an
-- AFTER trigger instead of a BEFORE trigger." With AFTER triggers the row
-- is physically deleted before the trigger runs, so cascades into
-- already-gone rows are no-ops instead of conflicts.
--
-- FIX
-- ---
--   1. Drop both BEFORE DELETE triggers.
--   2. Recreate identical triggers as AFTER DELETE.
--      Trigger function bodies are unchanged — they reference OLD.id, which
--      AFTER triggers see exactly as BEFORE triggers do. RETURN OLD is still
--      legal for AFTER triggers (return value is ignored, but harmless).
--   3. Trailing audit block fails loud if either trigger is somehow still
--      installed as BEFORE.
--
-- Trigger firing order (alphabetical by name):
--   • `trg_cleanup_user_quest_personalization` (alphabetically first)
--       → fires first AFTER user_profiles row is gone, deletes user_quest_*.
--   • `trigger_delete_auth_user_on_profile_delete` (alphabetically second)
--       → fires second, deletes auth.identities + auth.users.
--   • Cascade from auth.users → user_quest_* and → user_profiles fires last;
--     all targets are already gone → no-op cascades, NO error 27000.
--
-- INVARIANT TO CARRY FORWARD (DATA_BACKEND_AGENT.md):
--   `user_profiles` row triggers MUST be `AFTER DELETE`, never `BEFORE
--   DELETE`. Any future migration that reinstalls these triggers (or adds
--   new ones for cleanup of new tables) MUST use AFTER. If a migration
--   needs to mutate the OLD row before deletion, it MUST use a column
--   default / generated column / explicit pre-delete UPDATE — never a
--   BEFORE DELETE trigger that fans out to FK-cascaded child tables.
--
-- Resolves: Studio bulk delete error 27000 (Joe, 2026-05-08).
--           Also pre-emptively unblocks `delete_user_account(uuid)` RPC
--           (used by iOS account self-delete flow + admin CMS) which has
--           the same latent failure mode any time a user has a non-zero
--           number of `user_quest_*` rows.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

-- ──────────────────────────────────────────────────────────────────────────
-- 1. Drop the two BEFORE DELETE triggers.
--
-- Idempotent — drops only if present. Trigger functions themselves are
-- left intact; they're unchanged and the new AFTER triggers reuse them.
-- ──────────────────────────────────────────────────────────────────────────

DROP TRIGGER IF EXISTS trigger_delete_auth_user_on_profile_delete ON public.user_profiles;
DROP TRIGGER IF EXISTS trg_cleanup_user_quest_personalization     ON public.user_profiles;

-- ──────────────────────────────────────────────────────────────────────────
-- 2. Recreate both as AFTER DELETE.
--
-- Same FOR EACH ROW semantics, same EXECUTE FUNCTION targets, same OLD
-- row visibility — just AFTER instead of BEFORE so cascades don't race
-- with trigger-driven deletes.
-- ──────────────────────────────────────────────────────────────────────────

CREATE TRIGGER trigger_delete_auth_user_on_profile_delete
    AFTER DELETE ON public.user_profiles
    FOR EACH ROW
    EXECUTE FUNCTION delete_auth_user_on_profile_delete();

COMMENT ON TRIGGER trigger_delete_auth_user_on_profile_delete
    ON public.user_profiles IS
'AFTER DELETE: cascade-deletes auth.users + auth.identities once the
public.user_profiles row is physically gone. MUST stay AFTER — see
20260508_user_profiles_after_delete_triggers.sql for the BEFORE-trigger
SQLSTATE 27000 incident (Joe, 2026-05-08).';

CREATE TRIGGER trg_cleanup_user_quest_personalization
    AFTER DELETE ON public.user_profiles
    FOR EACH ROW
    EXECUTE FUNCTION cleanup_user_quest_personalization();

COMMENT ON TRIGGER trg_cleanup_user_quest_personalization
    ON public.user_profiles IS
'AFTER DELETE: defense-in-depth cleanup of user_quest_personalization /
user_quest_key_stats / user_activity_mix once the public.user_profiles
row is physically gone. FK CASCADE from auth.users covers these tables
already; this trigger fires even if the FK is later relaxed. MUST stay
AFTER — see 20260508_user_profiles_after_delete_triggers.sql.';

-- ──────────────────────────────────────────────────────────────────────────
-- 3. Trailing audit — fail loud if either trigger is somehow still BEFORE
--    or missing. tgtype bit 0x02 = BEFORE; absence of that bit = AFTER.
-- ──────────────────────────────────────────────────────────────────────────

DO $$
DECLARE
    tg RECORD;
    bad_count INTEGER := 0;
BEGIN
    FOR tg IN
        SELECT tgname, tgtype, tgenabled
        FROM pg_trigger
        WHERE tgrelid = 'public.user_profiles'::regclass
          AND tgname IN (
              'trigger_delete_auth_user_on_profile_delete',
              'trg_cleanup_user_quest_personalization'
          )
    LOOP
        IF (tg.tgtype & 2) <> 0 THEN
            -- bit 0x02 set => BEFORE timing, which is exactly what we just
            -- migrated away from. Fail loud.
            RAISE WARNING
                '[20260508 audit] Trigger % is still BEFORE timing (tgtype=%)',
                tg.tgname, tg.tgtype;
            bad_count := bad_count + 1;
        END IF;
        IF tg.tgenabled <> 'O' THEN
            RAISE WARNING
                '[20260508 audit] Trigger % is not enabled (tgenabled=%)',
                tg.tgname, tg.tgenabled;
            bad_count := bad_count + 1;
        END IF;
    END LOOP;

    -- Both triggers MUST exist post-migration.
    PERFORM 1
    FROM pg_trigger
    WHERE tgrelid = 'public.user_profiles'::regclass
      AND tgname  = 'trigger_delete_auth_user_on_profile_delete';
    IF NOT FOUND THEN
        RAISE EXCEPTION
            '[20260508 audit] FAILED — trigger_delete_auth_user_on_profile_delete is missing on user_profiles after migration';
    END IF;

    PERFORM 1
    FROM pg_trigger
    WHERE tgrelid = 'public.user_profiles'::regclass
      AND tgname  = 'trg_cleanup_user_quest_personalization';
    IF NOT FOUND THEN
        RAISE EXCEPTION
            '[20260508 audit] FAILED — trg_cleanup_user_quest_personalization is missing on user_profiles after migration';
    END IF;

    IF bad_count > 0 THEN
        RAISE EXCEPTION
            '[20260508 audit] FAILED — % trigger(s) still BEFORE or disabled. Investigate manually.',
            bad_count;
    END IF;

    RAISE NOTICE '✅ [20260508 audit] Both user_profiles delete triggers are AFTER + enabled.';
END $$;

COMMIT;
