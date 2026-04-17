-- =============================================================================
-- Phone Verification Rate Limit Table + RPC
-- =============================================================================
-- The send-verification Edge Function previously rate-limited via an in-memory
-- Map, which resets on every cold start (every few minutes). An attacker could
-- loop the endpoint to drain Twilio credit with a new cold start.
--
-- This migration moves the limiter to a DB row keyed on phone number, checked
-- and updated atomically by an RPC.
-- =============================================================================

-- Rate-limit counter per phone number.
CREATE TABLE IF NOT EXISTS public.phone_verification_rate_limit (
    phone_number TEXT PRIMARY KEY,
    attempt_count INT NOT NULL DEFAULT 0,
    window_started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Never readable by end-users. Only accessed via SECURITY DEFINER RPC below.
ALTER TABLE public.phone_verification_rate_limit ENABLE ROW LEVEL SECURITY;

-- No SELECT/INSERT/UPDATE policy = effectively locked down for end users.
-- The RPC below runs as SECURITY DEFINER so it can read/write the table.

CREATE INDEX IF NOT EXISTS phone_verification_rate_limit_window_idx
  ON public.phone_verification_rate_limit (window_started_at);

-- =============================================================================
-- RPC: check_phone_verification_rate_limit
-- Atomic check-and-increment. Returns TRUE if the call is allowed, FALSE if
-- the rate limit has been exceeded for the current window.
-- =============================================================================
CREATE OR REPLACE FUNCTION public.check_phone_verification_rate_limit(
    p_phone_number TEXT,
    p_max_attempts INT DEFAULT 10,
    p_window_seconds INT DEFAULT 3600
) RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_row public.phone_verification_rate_limit%ROWTYPE;
    v_window_start TIMESTAMPTZ := NOW() - (p_window_seconds || ' seconds')::INTERVAL;
BEGIN
    -- Basic input validation.
    IF p_phone_number IS NULL OR length(p_phone_number) < 4 THEN
        RETURN FALSE;
    END IF;

    -- Atomically upsert; reset the window if the existing row is stale.
    INSERT INTO public.phone_verification_rate_limit (phone_number, attempt_count, window_started_at, updated_at)
    VALUES (p_phone_number, 1, NOW(), NOW())
    ON CONFLICT (phone_number) DO UPDATE
    SET
        attempt_count = CASE
            WHEN public.phone_verification_rate_limit.window_started_at < v_window_start THEN 1
            ELSE public.phone_verification_rate_limit.attempt_count + 1
        END,
        window_started_at = CASE
            WHEN public.phone_verification_rate_limit.window_started_at < v_window_start THEN NOW()
            ELSE public.phone_verification_rate_limit.window_started_at
        END,
        updated_at = NOW()
    RETURNING * INTO v_row;

    RETURN v_row.attempt_count <= p_max_attempts;
END;
$$;

REVOKE ALL ON FUNCTION public.check_phone_verification_rate_limit(TEXT, INT, INT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.check_phone_verification_rate_limit(TEXT, INT, INT) TO service_role;

-- Optional cleanup job: purge rows older than 24h via pg_cron (set up manually
-- if/when desired). Skipped here to keep this migration idempotent.
