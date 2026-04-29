-- ═══════════════════════════════════════════════════════════════════════════
-- 20260721_orphan_auth_user_purge_and_trigger.sql
--
-- Bug — "previously deleted email is permanently locked, signup says
--       'User already registered' but the row doesn't appear in the dashboard"
--       (Joe / `joereedis@icloud.com`, 2026-04-29).
--
-- ROOT CAUSE
-- ----------
-- The "delete account" flow (`delete_user_account` RPC + the matching iOS
-- `SupabaseManager.deleteAccount`) was supposed to cascade-delete the
-- `auth.users` row via a `BEFORE DELETE` trigger on `user_profiles`
-- (`delete_auth_user_on_profile_delete` — see `complete_account_deletion.sql`).
-- For the historical accounts deleted before this trigger was reliably
-- installed, the `user_profiles` row is gone but the `auth.users` row
-- still exists. GoTrue sees the orphan and rejects re-signup with
-- "User already registered" — but admins looking at the dashboard's
-- Users tab don't see it because the row has no `last_sign_in_at`,
-- no email_confirmed_at, etc. and is filtered out of the default view.
--
-- The iOS recovery path
-- (`NewOnboardingView+Verification.swift::signUpOrRecoverExistingAccount`)
-- assumed "auth user exists → it's a recoverable partial signup, sign in
-- with the typed password" — which silently fails with `Invalid login
-- credentials` for the zombie case because the typed password belongs
-- to the NEW account the user is trying to create, not the orphan.
-- (Companion fix in this PR widens that recovery path's error handling
-- so the user gets actionable copy.)
--
-- FIX
-- ---
-- Three things, in order:
--   1. Reinstall the `BEFORE DELETE` trigger on `user_profiles` so going
--      forward, `DELETE FROM user_profiles` always cascades to
--      `auth.users`. Idempotent — drops the existing trigger first.
--   2. One-shot purge of all orphaned `auth.users` rows (rows that
--      have NO corresponding `user_profiles` row AND were created
--      more than 7 days ago). The 7-day grace window is critical:
--      between `auth.signUp` returning and the iOS app's
--      `createUserProfile` write completing, there's a small window
--      where `auth.users` exists with no profile — we MUST NOT purge
--      those (they're in-flight signups). Reports how many rows were
--      purged via RAISE NOTICE.
--   3. Trailing audit block — fails loud if the trigger is somehow
--      still missing OR if any orphaned auth.users rows older than
--      7 days survive the purge.
--
-- INVARIANT TO CARRY FORWARD (DATA_BACKEND_AGENT.md, paired commit):
--   #49 (proposed). `user_profiles` MUST have a `BEFORE DELETE` trigger
--   `trigger_delete_auth_user_on_profile_delete` that calls
--   `delete_auth_user_on_profile_delete()` to cascade the delete to
--   `auth.users`. Without it, every "delete account" flow leaves a
--   zombie `auth.users` row that permanently locks that email from
--   re-signup with the cryptic "User already registered" error.
--   The trigger MUST be reinstalled by any future migration that
--   touches `user_profiles` schema (CREATE OR REPLACE on the function
--   doesn't drop the trigger, but DROP TABLE / RECREATE does).
--
-- Resolves: <bug-intel cluster id TBD — assigned in next audit pass>
-- Companion iOS fix: `NewOnboardingView+Verification.swift` — sign-up
-- recovery path now distinguishes "wrong password on existing account"
-- from "recoverable partial signup" so users get useful copy when this
-- happens before the trigger has been deployed.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

-- ──────────────────────────────────────────────────────────────────────────
-- 1. Reinstall the `BEFORE DELETE` trigger function + trigger.
--
-- This block is identical to the one in `complete_account_deletion.sql`
-- (the canonical source) — duplicated here so this migration is
-- self-contained and idempotent. If `complete_account_deletion.sql` was
-- never run on prod (which the existence of `joereedis@icloud.com`'s
-- zombie strongly suggests), this is what installs the trigger for the
-- first time. If it WAS run, this is a harmless re-install.
-- ──────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION delete_auth_user_on_profile_delete()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
BEGIN
    -- Cascade-delete the auth.users row + dependent identities/sessions.
    -- We delete from auth.identities FIRST because in older GoTrue
    -- schemas there is no FK from identities → users (and even where
    -- there is, ON DELETE CASCADE was added in a later GoTrue version
    -- — being explicit is cheap insurance).
    DELETE FROM auth.identities WHERE user_id = OLD.id;
    DELETE FROM auth.users      WHERE id      = OLD.id;
    RETURN OLD;
END;
$$;

-- Drop and recreate so re-runs of this migration replace prior versions
-- cleanly. Safe — `BEFORE DELETE` triggers don't fire when the trigger
-- itself is dropped/replaced.
DROP TRIGGER IF EXISTS trigger_delete_auth_user_on_profile_delete ON user_profiles;
CREATE TRIGGER trigger_delete_auth_user_on_profile_delete
    BEFORE DELETE ON user_profiles
    FOR EACH ROW
    EXECUTE FUNCTION delete_auth_user_on_profile_delete();

COMMENT ON TRIGGER trigger_delete_auth_user_on_profile_delete
    ON user_profiles IS
'Cascade-deletes the matching auth.users + auth.identities rows whenever
a user_profiles row is deleted. Without this, every "delete account"
flow leaves a zombie auth.users row that permanently locks the email
from re-signup with the cryptic "User already registered" error.
Canonical incident: joereedis@icloud.com, 2026-04-29.';

-- ──────────────────────────────────────────────────────────────────────────
-- 2. One-shot purge of pre-existing orphans.
--
-- Criteria: an auth.users row is an "orphan" if and only if:
--   (a) there is no corresponding user_profiles row (LEFT JOIN ... IS NULL), AND
--   (b) it was created more than 7 days ago (so we never purge an
--       in-flight signup mid-onboarding).
--
-- This is run with the trigger already installed (above), but the
-- trigger only fires on `DELETE FROM user_profiles` — these orphans
-- have no profile to delete, so we delete from auth.users + auth.identities
-- directly here. Subsequent deletes will go through the trigger.
-- ──────────────────────────────────────────────────────────────────────────

DO $$
DECLARE
    orphan_user_count    INTEGER := 0;
    orphan_identity_count INTEGER := 0;
BEGIN
    -- Snapshot count for the audit notice (do this first so the count
    -- reflects what we're ABOUT to delete, not what's left after).
    SELECT COUNT(*) INTO orphan_user_count
    FROM auth.users u
    LEFT JOIN public.user_profiles p ON p.id = u.id
    WHERE p.id IS NULL
      AND u.created_at < NOW() - INTERVAL '7 days';

    -- Same predicate, but for the identity rows we're about to drop.
    SELECT COUNT(*) INTO orphan_identity_count
    FROM auth.identities i
    JOIN auth.users u            ON u.id = i.user_id
    LEFT JOIN public.user_profiles p ON p.id = u.id
    WHERE p.id IS NULL
      AND u.created_at < NOW() - INTERVAL '7 days';

    -- Identities first (defensive — see comment in trigger function above).
    DELETE FROM auth.identities i
    USING auth.users u
    WHERE i.user_id = u.id
      AND u.id NOT IN (SELECT id FROM public.user_profiles)
      AND u.created_at < NOW() - INTERVAL '7 days';

    -- Then the user rows themselves.
    DELETE FROM auth.users u
    WHERE u.id NOT IN (SELECT id FROM public.user_profiles)
      AND u.created_at < NOW() - INTERVAL '7 days';

    RAISE NOTICE
        '✅ [orphan-purge] Removed % auth.users orphan(s) + % auth.identities row(s) (created > 7d ago, no user_profiles).',
        orphan_user_count, orphan_identity_count;
END $$;

-- ──────────────────────────────────────────────────────────────────────────
-- 3. Trailing audit — fail loud if the fix didn't take.
-- ──────────────────────────────────────────────────────────────────────────

DO $$
DECLARE
    trig_count        INTEGER;
    surviving_orphans INTEGER;
BEGIN
    -- 3a. Trigger must exist + be enabled.
    SELECT COUNT(*) INTO trig_count
    FROM pg_trigger
    WHERE tgrelid = 'public.user_profiles'::regclass
      AND tgname  = 'trigger_delete_auth_user_on_profile_delete'
      AND tgenabled = 'O';   -- 'O' = enabled (origin). 'D' = disabled.

    IF trig_count <> 1 THEN
        RAISE EXCEPTION
            '[20260721 audit] FAILED — trigger trigger_delete_auth_user_on_profile_delete is missing or disabled on user_profiles (found % matching, expected 1)',
            trig_count;
    END IF;

    -- 3b. No orphans older than 7d should survive.
    SELECT COUNT(*) INTO surviving_orphans
    FROM auth.users u
    LEFT JOIN public.user_profiles p ON p.id = u.id
    WHERE p.id IS NULL
      AND u.created_at < NOW() - INTERVAL '7 days';

    IF surviving_orphans > 0 THEN
        RAISE EXCEPTION
            '[20260721 audit] FAILED — % auth.users orphan(s) older than 7d survived the purge. Investigate manually.',
            surviving_orphans;
    END IF;

    RAISE NOTICE '✅ [20260721 audit] Trigger installed + 0 surviving orphans.';
END $$;

COMMIT;
