-- ============================================================================
-- 20260625_opponent_progress_silent_push.sql
-- Widget Freshness Sprint — Phase 7b (2026-04-26)
--
-- Server-driven silent-push fan-out: when ANY participant in an active 1v1
-- or private challenge writes a higher progress value, fire a silent push
-- to every other participant of that challenge so their device wakes,
-- runs the lite challenge sync, and republishes a fresh widget snapshot.
--
-- Closes the worst-case "20-min wait until my widget timeline pull" gap
-- when both opponents have their main app suspended:
--
--      Opponent's phone writes challenge_daily_progress (e.g. fresh steps)
--          ↓ trigger (this migration)
--      net.http_post → wake-challenge-opponents { source: "progress_update",
--                                                  recipient_ids: [...] }
--          ↓ APNs silent push (priority 5)
--      My phone wakes → SilentPushHandler.handleChallengeWake
--          ↓ BackgroundChallengeSyncService.performLiteWakeSync()
--      log_challenge_progress + fetchActiveChallenges + bridge.publish
--          ↓ ActiveChallengeWidgetBridge.requestReloadIfNeeded
--      Home-screen widget redraws within ~5-10s of the original write.
--
-- DESIGN NOTES
--
-- 1. Recursion guard — `pg_trigger_depth() > 1` skips writes mirrored
--    by `fanout_challenge_progress()` (Data invariant #48). The fanout
--    trigger replicates a single user-pushed value across 1v1 / private /
--    community for every shared challenge type the user participates in,
--    which without the guard would multiply this trigger by 3-5× per
--    real movement and burn the silent-push budget for no net freshness.
--
-- 2. Monotonicity guard — only fires when `NEW.progress_value` is
--    STRICTLY GREATER than `OLD.progress_value` (or on INSERT with a
--    positive value). A `GREATEST(existing, new)` no-op write produces
--    an UPDATE row with identical value — pushing then would be pure
--    noise. Same posture as the engagement-nudge cron (#123).
--
-- 3. Same-day guard — only fires when `progress_date` is today (in UTC
--    server time, conservative). Late-night dawn-ghost backfills writing
--    yesterday's row would otherwise wake every participant for a stale
--    value (Data invariant #46/47). 24h grace allows for client / server
--    timezone skew.
--
-- 4. Community challenges — EXCLUDED. Communities have potentially
--    hundreds of participants; pushing every participant on every step
--    delta would saturate APNs throttle (`MAX_RECIPIENTS_PER_RUN = 500`)
--    and add noise the user can't act on. Community widgets stay on
--    the regular realtime + 20-min timeline pull path.
--
-- 5. Edge-function side handles per-source throttle:
--    `progress_update` → 60s window per recipient (NEW bucket, separate
--      from the existing 15-min `foreground` / `background_sync` / `cron`
--      buckets). 60s is short enough to feel live during a 1v1 push-flurry
--      while still capping APNs cost at ~60 wakes/recipient/hour worst case.
--
-- AUTH POSTURE
--   Trigger function is SECURITY DEFINER, lives in `public`, and reads
--   `internal_config` for the `service_role_key` (the canonical x-cron-key
--   header value, Supabase invariant #25). All writes from triggers
--   run with full row visibility — no auth.uid() context — so RLS isn't
--   relevant here.
--
-- COST POSTURE
--   `net.http_post` calls land on `supabase_functions.http_request_queue`
--   asynchronously; they DO NOT block the originating progress write.
--   Failed POSTs are logged by pg_net and don't roll back the write.
--
-- IDEMPOTENCY
--   BEGIN/COMMIT, IF NOT EXISTS / DROP IF EXISTS / DROP TRIGGER IF EXISTS.
--   Safe to re-run.
-- ============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- 0) Extend silent_push_wake_log.triggered_by CHECK constraint
-- ---------------------------------------------------------------------------
-- Original constraint (20260420_challenge_opponent_wake.sql) accepts
-- `foreground / cron / background_sync`. Phase 7b adds `progress_update`
-- as a fourth bucket so per-source throttles can distinguish it from the
-- 15-min foreground/cron lanes (the edge function reads its own
-- `THROTTLE_WINDOWS_MS_BY_SOURCE` map keyed on this column).
DO $constraint$
DECLARE
    v_conname TEXT;
BEGIN
    SELECT conname INTO v_conname
    FROM pg_constraint
    WHERE conrelid = 'silent_push_wake_log'::regclass
      AND contype = 'c'
      AND pg_get_constraintdef(oid) ILIKE '%triggered_by%';

    IF v_conname IS NOT NULL THEN
        EXECUTE format('ALTER TABLE silent_push_wake_log DROP CONSTRAINT %I', v_conname);
    END IF;

    ALTER TABLE silent_push_wake_log
        ADD CONSTRAINT silent_push_wake_log_triggered_by_check
        CHECK (triggered_by IN ('foreground', 'cron', 'background_sync', 'progress_update'));
END $constraint$;

-- Skip cleanly if pg_net isn't installed (local dev / CI without the
-- extension). The function still creates so the trigger fires, but the
-- net.http_post call is wrapped in a guard.
DO $do$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_extension WHERE extname = 'pg_net'
    ) THEN
        RAISE WARNING 'pg_net extension not installed — opponent-progress silent push will no-op until enabled';
    END IF;
END $do$;

-- ---------------------------------------------------------------------------
-- 1) Trigger function: notify_opponents_on_progress_change
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION notify_opponents_on_progress_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $func$
DECLARE
    v_table TEXT := TG_TABLE_NAME;
    v_writer_id UUID := NEW.user_id;
    v_challenge_id UUID := NEW.challenge_id;
    v_progress_date DATE := NEW.progress_date;
    v_old_value NUMERIC := COALESCE(OLD.progress_value, 0);
    v_new_value NUMERIC := COALESCE(NEW.progress_value, 0);
    v_recipient_ids UUID[];
    v_url TEXT;
    v_key TEXT;
    v_anon TEXT;
    v_pg_net_present BOOLEAN;
BEGIN
    -- Recursion guard: fanout trigger writes (Data invariant #48) bypass
    -- this — they are NOT new user motion, just cross-table mirroring.
    IF pg_trigger_depth() > 1 THEN
        RETURN NULL;
    END IF;

    -- Monotonicity guard: only push when progress STRICTLY increases.
    -- INSERT with non-positive value also skips — that's a midnight
    -- placeholder write, not a real delta.
    IF TG_OP = 'UPDATE' AND v_new_value <= v_old_value THEN
        RETURN NULL;
    END IF;
    IF TG_OP = 'INSERT' AND v_new_value <= 0 THEN
        RETURN NULL;
    END IF;

    -- Same-day guard: don't wake opponents for backfills of past days.
    -- 1-day grace allows for late writes near midnight + tz skew.
    IF v_progress_date < (NOW() AT TIME ZONE 'UTC')::DATE - 1 THEN
        RETURN NULL;
    END IF;

    -- Resolve recipient list per source table.
    IF v_table = 'challenge_daily_progress' THEN
        -- 1v1 + group: all accepted participants in this active challenge
        -- minus the writer.
        SELECT array_agg(DISTINCT cp.user_id)
        INTO v_recipient_ids
        FROM challenge_participants cp
        JOIN group_challenges gc ON gc.id = cp.challenge_id
        WHERE cp.challenge_id = v_challenge_id
          AND cp.user_id <> v_writer_id
          AND cp.status = 'accepted'
          AND gc.status = 'active';

    ELSIF v_table = 'private_challenge_daily_progress' THEN
        -- Private: members of an active private challenge minus the writer.
        SELECT array_agg(DISTINCT pcm.user_id)
        INTO v_recipient_ids
        FROM private_challenge_members pcm
        JOIN private_challenges pc ON pc.id = pcm.challenge_id
        WHERE pcm.challenge_id = v_challenge_id
          AND pcm.user_id <> v_writer_id
          AND (pc.end_date IS NULL OR pc.end_date >= (NOW() AT TIME ZONE 'UTC')::DATE);

    ELSE
        -- Community challenges (and any future tables) skip — too many
        -- participants per challenge to fan out cheaply.
        RETURN NULL;
    END IF;

    IF v_recipient_ids IS NULL OR array_length(v_recipient_ids, 1) = 0 THEN
        RETURN NULL;
    END IF;

    -- pg_net availability check — fall through silently in environments
    -- where the extension isn't installed (the migration's DO block above
    -- already RAISE WARNING'd at install time).
    SELECT EXISTS (
        SELECT 1 FROM pg_extension WHERE extname = 'pg_net'
    ) INTO v_pg_net_present;

    IF NOT v_pg_net_present THEN
        RETURN NULL;
    END IF;

    -- Read canonical edge-function invocation creds (Supabase invariant #25).
    SELECT value INTO v_url  FROM internal_config WHERE key = 'supabase_url';
    SELECT value INTO v_key  FROM internal_config WHERE key = 'service_role_key';
    SELECT value INTO v_anon FROM internal_config WHERE key = 'anon_key';

    IF v_url IS NULL OR v_key IS NULL OR v_anon IS NULL THEN
        RAISE WARNING 'notify_opponents_on_progress_change: internal_config missing required keys — skipping';
        RETURN NULL;
    END IF;

    -- Fire-and-forget HTTP POST. pg_net queues asynchronously — does not
    -- block the originating write.
    PERFORM net.http_post(
        url     := v_url || '/functions/v1/wake-challenge-opponents',
        headers := jsonb_build_object(
            'Authorization', 'Bearer ' || v_anon,
            'apikey',        v_anon,
            'x-cron-key',    v_key,
            'Content-Type',  'application/json'
        ),
        body := jsonb_build_object(
            'source',         'progress_update',
            'recipient_ids',  v_recipient_ids,
            'writer_id',      v_writer_id,
            'challenge_id',   v_challenge_id,
            'source_table',   v_table
        )
    );

    RETURN NULL;
EXCEPTION
    WHEN OTHERS THEN
        -- Never let the silent-push side-effect kill the originating
        -- write. Log + swallow.
        RAISE WARNING 'notify_opponents_on_progress_change: % — %', SQLSTATE, SQLERRM;
        RETURN NULL;
END;
$func$;

REVOKE ALL ON FUNCTION public.notify_opponents_on_progress_change() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.notify_opponents_on_progress_change() TO service_role;

-- ---------------------------------------------------------------------------
-- 2) Triggers — install on 1v1 and private daily progress tables
-- ---------------------------------------------------------------------------

DROP TRIGGER IF EXISTS trg_notify_opponents_progress_change_1v1 ON challenge_daily_progress;
CREATE TRIGGER trg_notify_opponents_progress_change_1v1
    AFTER INSERT OR UPDATE OF progress_value ON challenge_daily_progress
    FOR EACH ROW
    EXECUTE FUNCTION notify_opponents_on_progress_change();

DROP TRIGGER IF EXISTS trg_notify_opponents_progress_change_private ON private_challenge_daily_progress;
CREATE TRIGGER trg_notify_opponents_progress_change_private
    AFTER INSERT OR UPDATE OF progress_value ON private_challenge_daily_progress
    FOR EACH ROW
    EXECUTE FUNCTION notify_opponents_on_progress_change();

-- ---------------------------------------------------------------------------
-- 3) Audit: confirm triggers actually installed
-- ---------------------------------------------------------------------------

DO $audit$
DECLARE
    v_count INT;
BEGIN
    SELECT COUNT(*) INTO v_count
    FROM pg_trigger
    WHERE tgname IN (
        'trg_notify_opponents_progress_change_1v1',
        'trg_notify_opponents_progress_change_private'
    )
      AND NOT tgisinternal;

    IF v_count <> 2 THEN
        RAISE EXCEPTION
            'opponent-progress silent push: expected 2 triggers, found %', v_count;
    END IF;

    RAISE NOTICE 'opponent-progress silent push: % trigger(s) installed', v_count;
END $audit$;

COMMIT;

-- ============================================================================
-- DEPLOY NOTES
--
-- 1. After this migration applies, deploy the updated wake-challenge-opponents
--    edge function in the same window. The function rolls out a new
--    `source: "progress_update"` mode + `recipient_ids` body field; calls
--    from this trigger will return early (with a graceful error) until the
--    function update lands. This is intentional — the trigger is safe to
--    install ahead of the function deploy, and pg_net's async queue swallows
--    the early failures without affecting the originating writes.
-- 2. Verify on production with:
--      SELECT tgname FROM pg_trigger
--      WHERE tgname LIKE 'trg_notify_opponents_progress_change%';
--    Expect both trigger names returned.
-- 3. Roll back by `DROP TRIGGER IF EXISTS ...; DROP FUNCTION IF EXISTS
--    notify_opponents_on_progress_change();`. Safe — does not touch
--    progress data.
-- ============================================================================
