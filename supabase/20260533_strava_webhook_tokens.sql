-- 20260533_strava_webhook_tokens.sql
-- Phase 5 of Strava Integration Upgrade — server-side token store so the
-- Strava webhook edge function can fetch activity detail + write to
-- cardio_workouts without an iOS device being awake.
--
-- iOS still owns the keychain copy (primary) — this table is a
-- write-mirror used only by the webhook function. Refresh-token rotation
-- (Strava rotates the refresh token on every refresh) is handled by
-- whichever side refreshed last; both sides trust the latest expires_at.
--
-- Invariants:
--   * RLS on every user-data table (codingrules / SUPABASE_AGENT §2).
--   * SECURITY DEFINER RPC never accepts user_id (Data invariant #7) —
--     pinned to auth.uid().
--   * Drop all overloads before CREATE OR REPLACE (Data invariant #38).
--   * Idempotent. Wrapped BEGIN/COMMIT.

BEGIN;

-- 1. Table -----------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.user_strava_tokens (
    user_id        UUID PRIMARY KEY REFERENCES public.user_profiles(id) ON DELETE CASCADE,
    access_token   TEXT NOT NULL,
    refresh_token  TEXT NOT NULL,
    expires_at     TIMESTAMPTZ NOT NULL,
    athlete_id     BIGINT,
    last_rotated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.user_strava_tokens IS
    'Server-side mirror of Strava OAuth tokens. Written by the iOS client (dual-write with keychain) and by the strava-webhook edge function on refresh. Used by webhook function to fetch activity detail when the iOS app is offline.';

CREATE INDEX IF NOT EXISTS idx_user_strava_tokens_athlete_id
    ON public.user_strava_tokens (athlete_id)
    WHERE athlete_id IS NOT NULL;

-- 2. RLS -------------------------------------------------------------------
ALTER TABLE public.user_strava_tokens ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can read own strava tokens"   ON public.user_strava_tokens;
DROP POLICY IF EXISTS "Users can update own strava tokens" ON public.user_strava_tokens;
DROP POLICY IF EXISTS "Users can delete own strava tokens" ON public.user_strava_tokens;

-- SELECT / UPDATE / DELETE only by the owning user. INSERT goes through
-- the SECURITY DEFINER RPC below — never directly.
CREATE POLICY "Users can read own strava tokens"
    ON public.user_strava_tokens
    FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can update own strava tokens"
    ON public.user_strava_tokens
    FOR UPDATE
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can delete own strava tokens"
    ON public.user_strava_tokens
    FOR DELETE
    USING (auth.uid() = user_id);

-- 3. Upsert RPC ------------------------------------------------------------
-- Drop all overloads first per Data invariant #38.
DROP FUNCTION IF EXISTS public.upsert_strava_tokens(TEXT, TEXT, TIMESTAMPTZ, BIGINT);
DROP FUNCTION IF EXISTS public.upsert_strava_tokens(TEXT, TEXT, TIMESTAMPTZ);

CREATE OR REPLACE FUNCTION public.upsert_strava_tokens(
    p_access     TEXT,
    p_refresh    TEXT,
    p_expires_at TIMESTAMPTZ,
    p_athlete_id BIGINT DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id UUID := auth.uid();
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'upsert_strava_tokens: not authenticated';
    END IF;

    INSERT INTO public.user_strava_tokens (
        user_id, access_token, refresh_token, expires_at, athlete_id, last_rotated_at, updated_at
    ) VALUES (
        v_user_id, p_access, p_refresh, p_expires_at, p_athlete_id, now(), now()
    )
    ON CONFLICT (user_id) DO UPDATE SET
        access_token    = EXCLUDED.access_token,
        refresh_token   = EXCLUDED.refresh_token,
        expires_at      = EXCLUDED.expires_at,
        athlete_id      = COALESCE(EXCLUDED.athlete_id, public.user_strava_tokens.athlete_id),
        last_rotated_at = now(),
        updated_at      = now();
END;
$$;

REVOKE ALL ON FUNCTION public.upsert_strava_tokens(TEXT, TEXT, TIMESTAMPTZ, BIGINT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.upsert_strava_tokens(TEXT, TEXT, TIMESTAMPTZ, BIGINT) TO authenticated;

COMMENT ON FUNCTION public.upsert_strava_tokens(TEXT, TEXT, TIMESTAMPTZ, BIGINT) IS
    'SECURITY DEFINER upsert — caller user pinned to auth.uid() (Data invariant #7). Used by Fit33/StravaService.swift dual-write after OAuth exchange and after every refresh rotation.';

-- 4. Service-role helper (used by strava-webhook to find a user from
--    Strava athlete_id) ------------------------------------------------------
DROP FUNCTION IF EXISTS public.get_user_id_for_strava_athlete(BIGINT);

CREATE OR REPLACE FUNCTION public.get_user_id_for_strava_athlete(p_athlete_id BIGINT)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id UUID;
BEGIN
    SELECT user_id INTO v_user_id
    FROM public.user_strava_tokens
    WHERE athlete_id = p_athlete_id
    LIMIT 1;
    RETURN v_user_id;
END;
$$;

REVOKE ALL ON FUNCTION public.get_user_id_for_strava_athlete(BIGINT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_user_id_for_strava_athlete(BIGINT) TO service_role;

COMMENT ON FUNCTION public.get_user_id_for_strava_athlete(BIGINT) IS
    'Service-role-only lookup for the strava-webhook edge function — maps Strava owner_id → app user_id without exposing the tokens table to anon.';

-- 5. updated_at trigger ----------------------------------------------------
CREATE OR REPLACE FUNCTION public._user_strava_tokens_set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_user_strava_tokens_updated_at ON public.user_strava_tokens;
CREATE TRIGGER trg_user_strava_tokens_updated_at
BEFORE UPDATE ON public.user_strava_tokens
FOR EACH ROW
EXECUTE FUNCTION public._user_strava_tokens_set_updated_at();

DO $$ BEGIN
    RAISE NOTICE '✅ user_strava_tokens table + RLS + upsert RPC + service-role lookup created';
END $$;

COMMIT;
