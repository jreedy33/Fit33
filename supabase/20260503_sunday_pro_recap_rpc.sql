-- ============================================================================
-- 20260503 — Sunday Pro Recap supporting RPC + cron schedule
--
-- Owner: MONETIZATION_AGENT.md (Phase 5 cheat-code: weekly recap push).
-- Pairs with: supabase/functions/sunday-pro-recap/index.ts
--
-- Why this migration exists:
--   The `sunday-pro-recap` edge function needs ONE RPC that returns
--   every user's last 7 days of training in a single round-trip:
--     • workout count this week / last week (for "volume up" delta copy)
--     • subscription tier (so the function picks pro vs teaser copy)
--     • push token + apns env (so the function can send APNs)
--     • timezone (so the function can gate to local Sunday 10am)
--
--   Computing this client-side per-user would mean N queries × thousands
--   of users. One RPC = one query, returns batched recap data.
--
-- v1 scope (this migration): workout-count + push routing + tier.
-- v2 (follow-up sprint, paired with Phase 1a entitlement work):
--   add total_volume + pr_count once the volume/PR aggregation tables
--   are verified end-to-end (collaborative_workout_data corpus may
--   already provide this; deferred to keep v1 ship-able today).
--
-- All work is idempotent. Re-running this migration is a no-op.
-- ============================================================================

BEGIN;

-- ────────────────────────────────────────────────────────────────────────────
-- 1. RPC: get_sunday_recap_candidates
-- ────────────────────────────────────────────────────────────────────────────
-- Returns every user with an active push token + their workout-count
-- signals + Pro tier flag + push routing.
--
-- Caller can pass a non-NULL `p_user_ids` array to scope the result
-- (manual testing / re-fire); pass NULL for the full recipient set.
--
-- Pro tier detection mirrors `user_profiles.subscription_tier` when
-- the column exists (Phase 1a). Falls back to is_pro=false otherwise.
--
-- Security: SECURITY DEFINER + caller-MUST-be-service-role guard.
-- Pinned search_path per supabase-rules invariant.
-- ────────────────────────────────────────────────────────────────────────────

DROP FUNCTION IF EXISTS public.get_sunday_recap_candidates(UUID[]);

CREATE OR REPLACE FUNCTION public.get_sunday_recap_candidates(
    p_user_ids UUID[] DEFAULT NULL
)
RETURNS TABLE(
    user_id                       UUID,
    display_name                  TEXT,
    is_pro                        BOOLEAN,
    workouts_this_week            INTEGER,
    workouts_last_week            INTEGER,
    push_token                    TEXT,
    apns_environment              TEXT,
    timezone                      TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    has_subscription_tier BOOLEAN;
BEGIN
    -- Service-role-only. `auth.uid()` returns NULL when called with
    -- the service-role JWT (or pg_cron's superuser context) — that's
    -- the ONLY allowed path. Direct user calls are blocked.
    IF auth.uid() IS NOT NULL THEN
        RAISE EXCEPTION 'get_sunday_recap_candidates is service-role-only';
    END IF;

    -- Defensive branch: subscription_tier column may not be present
    -- in some environments (pre-Phase-1a). Detect once.
    SELECT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'user_profiles'
          AND column_name = 'subscription_tier'
    ) INTO has_subscription_tier;

    RETURN QUERY
    WITH wk AS (
        SELECT
            w.user_id,
            COUNT(*) FILTER (
                WHERE w.completed_at >= NOW() - INTERVAL '7 days'
            )::INTEGER AS this_wk,
            COUNT(*) FILTER (
                WHERE w.completed_at >= NOW() - INTERVAL '14 days'
                  AND w.completed_at <  NOW() - INTERVAL '7 days'
            )::INTEGER AS last_wk
        FROM workouts w
        WHERE w.completed_at >= NOW() - INTERVAL '14 days'
          AND (p_user_ids IS NULL OR w.user_id = ANY(p_user_ids))
        GROUP BY w.user_id
    ),
    push AS (
        -- Most-recently-updated VALID device per user.
        SELECT DISTINCT ON (pt.user_id)
            pt.user_id,
            pt.device_token,
            pt.apns_environment
        FROM user_push_tokens pt
        WHERE pt.is_valid = TRUE
          AND (p_user_ids IS NULL OR pt.user_id = ANY(p_user_ids))
        ORDER BY pt.user_id, pt.updated_at DESC NULLS LAST
    ),
    prefs AS (
        SELECT
            unp.user_id,
            unp.timezone
        FROM user_notification_preferences unp
        WHERE (p_user_ids IS NULL OR unp.user_id = ANY(p_user_ids))
    )
    SELECT
        up.id,
        up.display_name,
        CASE
            WHEN has_subscription_tier
                THEN COALESCE(
                    (SELECT (sub.tier IN ('pro_monthly', 'pro_yearly', 'pro_lifetime', 'comp'))
                       FROM (SELECT subscription_tier AS tier FROM user_profiles WHERE id = up.id) sub),
                    FALSE
                )
            ELSE FALSE
        END AS is_pro,
        COALESCE(wk.this_wk, 0),
        COALESCE(wk.last_wk, 0),
        push.device_token,
        push.apns_environment,
        COALESCE(prefs.timezone, 'America/New_York')
    FROM user_profiles up
    INNER JOIN push ON push.user_id = up.id  -- only users with a push token
    LEFT  JOIN wk    ON wk.user_id    = up.id
    LEFT  JOIN prefs ON prefs.user_id = up.id
    WHERE (p_user_ids IS NULL OR up.id = ANY(p_user_ids));
END;
$$;

REVOKE ALL ON FUNCTION public.get_sunday_recap_candidates(UUID[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_sunday_recap_candidates(UUID[]) TO service_role;

COMMENT ON FUNCTION public.get_sunday_recap_candidates(UUID[]) IS
'Service-role-only batch query that powers the `sunday-pro-recap` edge function. Returns workout-count signals + push routing for every user with a valid device token. Pass `p_user_ids` to scope to a manual test cohort; NULL for full audience. Pro detection uses `user_profiles.subscription_tier` when present, falls back to is_pro=false otherwise. v1 returns workouts_this_week / workouts_last_week only — total_volume + pr_count are deferred to v2 (post-corpus verification).';

-- ────────────────────────────────────────────────────────────────────────────
-- 2. pg_cron schedule (idempotent, gated on extension availability)
-- ────────────────────────────────────────────────────────────────────────────
-- Fires at :05 every hour on Sunday. The edge function gates by
-- per-user-timezone-local-Sunday-10am inside Deno, so only users for
-- whom it's currently 10:00 in their TZ get the push this hour.
--
-- pg_cron is not available in local-dev / preview envs; guard with a
-- pg_extension EXISTS check so the migration is portable.
-- ────────────────────────────────────────────────────────────────────────────

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
        -- Drop any prior version of this job so re-runs are idempotent.
        BEGIN
            PERFORM cron.unschedule('sunday-pro-recap-hourly');
        EXCEPTION WHEN OTHERS THEN
            -- Job didn't exist; carry on.
            NULL;
        END;

        PERFORM cron.schedule(
            'sunday-pro-recap-hourly',
            '5 * * * 0',  -- :05 every hour, only on Sunday (DOW=0)
            $cron$
            SELECT net.http_post(
                url     := current_setting('app.supabase_url', true) || '/functions/v1/sunday-pro-recap',
                headers := jsonb_build_object(
                    'Content-Type', 'application/json',
                    'x-cron-key',   current_setting('app.service_role_key', true)
                ),
                body    := jsonb_build_object('source', 'cron')
            ) AS request_id;
            $cron$
        );
    END IF;
END $$;

COMMIT;
