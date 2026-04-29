-- ============================================================================
-- 20260709_loosen_incomplete_onboarding_cleanup.sql
--
-- Sync Triage 2026-04-28 — Onboarding Cleanup
--
-- WHAT THIS MIGRATION DOES
-- ------------------------
-- (1) Fixes the `private_challenge_members.invited_by` FK to
--     `ON DELETE SET NULL` so deleting a user no longer raises
--     `23503` when that user invited anyone to a private challenge
--     (we hit this twice manually on 2026-04-28).
--
-- (2) Replaces `cleanup_incomplete_onboarding_profiles()` with a
--     simpler 1-hour cleanup that no longer requires the profile
--     to be "barely-started" (no AND-chain on `username IS NULL AND
--     birthday IS NULL AND height_cm IS NULL AND weight_kg IS NULL`).
--     Any profile that has not completed onboarding within 1 hour
--     of creation is now reaped, regardless of how far through the
--     flow the user got.
--
-- (3) Reschedules the existing `cleanup-incomplete-onboarding` cron
--     entry (every 10 min) so the new function takes effect.
--
-- (4) Runs a one-time backfill so any pre-existing incomplete
--     profiles older than 1 hour are deleted immediately at deploy
--     time (instead of waiting up to 10 min for the next cron tick).
--
-- WHY
-- ---
-- User reported: "I deleted the app before completing onboarding —
-- the temp account creation should disappear — this was working
-- before". The cleanup function in production is byte-identical to
-- the one in v1.36 (verified via git history), so nothing
-- regressed; the user was just abandoning at a later step than
-- before, past the AND-chain's "barely-started" threshold (the
-- `body` step populates height/weight, the `basics` step populates
-- birthday, the `username` step populates username — once any one
-- of those is set, the old gate excluded the row from cleanup).
--
-- Stated requirement matrix:
--   "Leave the app and come back is fine"        → iOS UserDefaults
--                                                  checkpoint already
--                                                  handles this (with
--                                                  the auth-gate fix
--                                                  shipped earlier in
--                                                  the same session).
--   "Don't complete in one go" → start over      → THIS MIGRATION:
--                                                  1h server cleanup.
--   "Force quit or delete the app" → start over  → Same — cleanup
--                                                  reaps the cloud row;
--                                                  iOS UserDefaults is
--                                                  wiped on uninstall
--                                                  anyway, so the
--                                                  email becomes
--                                                  re-registerable.
--
-- WINDOW DECISION
-- ---------------
-- 1 hour. Real users who genuinely take >1h to fill 14 onboarding
-- steps are rare; if it becomes a support issue we can lengthen.
--
-- IDEMPOTENCY
-- -----------
-- All operations are idempotent (DROP CONSTRAINT IF EXISTS,
-- CREATE OR REPLACE, conditional unschedule before schedule).
-- Wrapped in BEGIN/COMMIT per `.cursor/rules/supabase-rules.mdc`.
-- ============================================================================

BEGIN;

-- ─── 1. Fix blocking FK on private_challenge_members.invited_by ────
-- Without ON DELETE SET NULL, deleting a user who ever invited
-- anyone to a private challenge raises 23503. We hit this twice
-- on 2026-04-28 doing manual cleanups in the Supabase Table Editor.
-- Setting it to NULL preserves the membership history of the
-- invitees while letting the inviter row be deleted cleanly.
DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'private_challenge_members_invited_by_fkey'
    ) THEN
        ALTER TABLE private_challenge_members
            DROP CONSTRAINT private_challenge_members_invited_by_fkey;
        RAISE NOTICE 'Dropped existing private_challenge_members_invited_by_fkey';
    END IF;
END $$;

ALTER TABLE private_challenge_members
    ADD CONSTRAINT private_challenge_members_invited_by_fkey
    FOREIGN KEY (invited_by)
    REFERENCES user_profiles(id)
    ON DELETE SET NULL;

-- ─── 2. New cleanup function ───────────────────────────────────────
-- Replaces the 30-min, AND-chain "barely-started" gate with a 1h
-- "no-data-completeness-gate" deletion. Per-row try/except so one
-- bad row (e.g. blocked by a FK we haven't fixed yet) doesn't
-- abort the whole cron run — the bad row just logs a WARNING and
-- the rest proceed.
CREATE OR REPLACE FUNCTION cleanup_incomplete_onboarding_profiles()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_count INT := 0;
    v_skipped INT := 0;
    v_user RECORD;
BEGIN
    FOR v_user IN (
        SELECT id, email
        FROM user_profiles
        WHERE has_completed_onboarding = false
          AND created_at < NOW() - INTERVAL '1 hour'
    ) LOOP
        BEGIN
            -- DELETE FROM user_profiles fires the existing
            -- `trigger_delete_auth_user_on_profile_delete` trigger
            -- (from supabase/complete_account_deletion.sql) which
            -- in turn deletes the auth.users row, freeing the email
            -- for re-registration. CASCADEs to user-data tables
            -- with ON DELETE CASCADE; SET NULL fires for the FK we
            -- just fixed above and any others configured similarly.
            DELETE FROM user_profiles WHERE id = v_user.id;

            -- Defensive: if the trigger isn't deployed on this
            -- environment for some reason, ensure auth.users is
            -- removed so the email becomes re-registerable. No-op
            -- when the trigger already cascaded the auth.users row.
            DELETE FROM auth.users WHERE id = v_user.id;

            v_count := v_count + 1;
            RAISE NOTICE 'cleanup_incomplete_onboarding_profiles: deleted profile % (email: %)',
                v_user.id, COALESCE(v_user.email, '<no email>');
        EXCEPTION WHEN OTHERS THEN
            v_skipped := v_skipped + 1;
            RAISE WARNING 'cleanup_incomplete_onboarding_profiles: skipped % — %',
                v_user.id, SQLERRM;
        END;
    END LOOP;

    IF v_count > 0 OR v_skipped > 0 THEN
        RAISE NOTICE '✅ cleanup_incomplete_onboarding_profiles done — deleted: %, skipped (FK blocks): %',
            v_count, v_skipped;
    END IF;
END;
$$;

COMMENT ON FUNCTION cleanup_incomplete_onboarding_profiles() IS
    'Auto-deletes user_profiles + matching auth.users rows for users who started but did not complete onboarding within 1 hour. Cron runs every 10 minutes. Per-row try/except so one bad row does not abort the batch.';

GRANT EXECUTE ON FUNCTION cleanup_incomplete_onboarding_profiles() TO service_role;

-- ─── 3. Reschedule cron (idempotent) ───────────────────────────────
-- The job name is the same as the original (`cleanup-incomplete-onboarding`)
-- so we unschedule + reschedule rather than risking a duplicate.
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'cleanup-incomplete-onboarding') THEN
        PERFORM cron.unschedule('cleanup-incomplete-onboarding');
        RAISE NOTICE 'Unscheduled existing cleanup-incomplete-onboarding cron job';
    END IF;
END $$;

SELECT cron.schedule(
    'cleanup-incomplete-onboarding',
    '*/10 * * * *',
    $$SELECT cleanup_incomplete_onboarding_profiles();$$
);

-- ─── 4. One-time backfill ─────────────────────────────────────────
-- Run the new cleanup once at deploy time so the existing
-- "joereedis@icloud.com" orphan and any other ≥1h-old incomplete
-- profiles are reaped immediately, instead of waiting up to 10
-- min for the next cron tick.
SELECT cleanup_incomplete_onboarding_profiles();

-- ─── 5. Validation: fail-loud audit ────────────────────────────────
-- If any incomplete profiles older than 1 hour remain after the
-- backfill, it means a FK we haven't audited is blocking the
-- delete. Raise a NOTICE (not EXCEPTION — partial cleanup is
-- still useful) listing the surviving rows so we can drop their
-- ON DELETE NO ACTION constraints in a follow-up migration.
DO $$
DECLARE
    v_remaining INT;
    v_first_ids TEXT;
BEGIN
    SELECT COUNT(*) INTO v_remaining
    FROM user_profiles
    WHERE has_completed_onboarding = false
      AND created_at < NOW() - INTERVAL '1 hour';

    IF v_remaining > 0 THEN
        -- Postgres has no `MIN(uuid)` aggregate (UUIDs aren't ordered as a
        -- min/max-friendly type), so we hand-pick the first few via
        -- `array_agg(... ORDER BY created_at)` and cast to text for the
        -- log line. Caller can grep for them in user_profiles.
        SELECT string_agg(id::text, ', ' ORDER BY created_at)
        INTO v_first_ids
        FROM (
            SELECT id, created_at
            FROM user_profiles
            WHERE has_completed_onboarding = false
              AND created_at < NOW() - INTERVAL '1 hour'
            ORDER BY created_at
            LIMIT 5
        ) sample;

        RAISE WARNING '⚠️  % incomplete profile(s) older than 1h survived cleanup. First blocked ids (up to 5): %. Inspect FKs without ON DELETE handling and add a follow-up migration.',
            v_remaining, COALESCE(v_first_ids, '<none>');
    ELSE
        RAISE NOTICE '✅ Audit clean — no incomplete profiles older than 1h remain.';
    END IF;
END $$;

COMMIT;

-- ─── Post-deploy verification (run manually in SQL Editor) ─────────
--
-- Confirm the cron is scheduled and pointing at the new function:
-- SELECT jobname, schedule, command
-- FROM cron.job
-- WHERE jobname = 'cleanup-incomplete-onboarding';
--
-- Confirm the FK constraint was updated:
-- SELECT conname, confdeltype  -- 'n' = SET NULL, 'a' = NO ACTION
-- FROM pg_constraint
-- WHERE conname = 'private_challenge_members_invited_by_fkey';
--
-- Confirm cleanup function shape:
-- SELECT pg_get_functiondef(oid)
-- FROM pg_proc
-- WHERE proname = 'cleanup_incomplete_onboarding_profiles';
--
-- Spot-check: count incomplete profiles by age band
-- SELECT
--   COUNT(*) FILTER (WHERE created_at >= NOW() - INTERVAL '1 hour') AS under_1h,
--   COUNT(*) FILTER (WHERE created_at <  NOW() - INTERVAL '1 hour') AS over_1h_should_be_zero
-- FROM user_profiles
-- WHERE has_completed_onboarding = false;
