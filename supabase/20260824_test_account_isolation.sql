-- ───────────────────────────────────────────────────────────────────────────
-- 20260824 — TEST-ACCOUNT ISOLATION FOR NEW-USER-JOURNEY PIPELINE
-- ───────────────────────────────────────────────────────────────────────────
-- Why: NUJ pipeline (#162) was deployed without any way to distinguish
--   developer / QA test accounts from real new users. Result: of the first 15
--   enrollments captured, the majority were @test.com / personal-dev emails,
--   inflating funnel-drop, error-rate, and "completed onboarding" denominators
--   to the point that downstream reports (Claude analyses, admin CMS cohort
--   summary) were misleading.
--
-- This migration:
--   1. Adds `is_test_account BOOLEAN NOT NULL DEFAULT FALSE` to
--      `new_user_journey_enrollment` (the choke point — every other NUJ
--       table joins through here).
--   2. Seeds canonical test-email-pattern list into `internal_config` so the
--      iOS client + server-side cleanup share one source of truth.
--   3. New helper `is_test_account_email(TEXT)` — pattern match against the
--      seeded patterns. SECURITY DEFINER, fast, deterministic.
--   4. Replaces `enroll_new_user_journey` to:
--        a. Accept `p_is_test_account BOOLEAN DEFAULT NULL` (iOS heuristic:
--           simulator, DEBUG build, dev-menu toggle).
--        b. Auto-detect via email pattern at enrollment time as a safety net
--           even if the client doesn't pass the flag.
--        c. Persist the flag (logical OR of both inputs).
--   5. Replaces `trigger_generate_new_user_reports()` to skip rows where
--      `is_test_account = TRUE` — the edge function never sees them, the
--      report cron never fires for them, no Claude credits burned on test data.
--   6. Adds `cleanup_test_journey_data()` — drains events / sessions /
--      enrollment / reports for any test account whose enrollment is older
--      than 24h. Cron runs hourly. AUTO-DELETE is the canonical answer
--      (per product owner directive, 2026-05-10).
--   7. Replaces `record_new_user_session_start()` to gate the
--      `total_sessions++` bump on whether the INSERT actually happened —
--      previously every silent-push wake that sent the same session_id
--      double-counted the session. Closes the "1 user shows 100+ sessions
--      in 24h" anomaly seen on 2026-05-09.
--   8. Backfills the existing 15 enrollments based on email pattern.
--
-- Idempotency:
--   - All ALTERs gated by `IF NOT EXISTS` / `ADD COLUMN IF NOT EXISTS`.
--   - All RPCs use `DROP FUNCTION IF EXISTS` then `CREATE OR REPLACE`.
--   - `internal_config` seeding uses `ON CONFLICT DO NOTHING` so re-running
--     this migration won't overwrite a manually-tuned pattern list.
--
-- Bug-intel hygiene:
--   - This migration touches NUJ-only surface; bug_intelligence_*
--     tables are unaffected. Test-account events that already landed in
--     dev_session_logs / crash_reports stay there (different pipeline,
--     different consumer).
--
-- ───────────────────────────────────────────────────────────────────────────

BEGIN;

-- ═══════════════════════════════════════════════════════════════════════════
-- 1. SEED TEST-ACCOUNT EMAIL PATTERNS
-- ═══════════════════════════════════════════════════════════════════════════
-- Comma-separated patterns, matched case-insensitively. Patterns starting
-- with `@` match any local-part on that domain (suffix match). Otherwise
-- patterns match the whole email exactly. iOS reads this list on every
-- cold start (cached for the session) and auto-flags new sign-ups before
-- the first journey event lands.

INSERT INTO public.internal_config (key, value)
VALUES (
    'nuj_test_account_email_patterns',
    '@test.com,@example.com,@e2e.local,joereedis@icloud.com,joe.r.reedis@gmail.com'
)
ON CONFLICT (key) DO NOTHING;

-- ═══════════════════════════════════════════════════════════════════════════
-- 2. SCHEMA: is_test_account FLAG ON ENROLLMENT
-- ═══════════════════════════════════════════════════════════════════════════

ALTER TABLE public.new_user_journey_enrollment
    ADD COLUMN IF NOT EXISTS is_test_account BOOLEAN NOT NULL DEFAULT FALSE;

-- Partial index — most queries (cohort summary, report cron) want to
-- EXCLUDE test accounts, so we index the FALSE-side. The reverse query
-- (cleanup cron) is small enough to seq-scan.
CREATE INDEX IF NOT EXISTS idx_nuj_enrollment_real_users
    ON public.new_user_journey_enrollment (enrolled_at)
    WHERE is_test_account = FALSE;

-- ═══════════════════════════════════════════════════════════════════════════
-- 3. HELPER: is_test_account_email(TEXT) — pattern matcher
-- ═══════════════════════════════════════════════════════════════════════════

DROP FUNCTION IF EXISTS public.is_test_account_email(TEXT);
CREATE OR REPLACE FUNCTION public.is_test_account_email(p_email TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_patterns TEXT;
    v_pattern  TEXT;
    v_email_lc TEXT;
BEGIN
    IF p_email IS NULL OR p_email = '' THEN
        RETURN FALSE;
    END IF;

    SELECT value INTO v_patterns
    FROM public.internal_config
    WHERE key = 'nuj_test_account_email_patterns';

    IF v_patterns IS NULL OR v_patterns = '' THEN
        RETURN FALSE;
    END IF;

    v_email_lc := lower(p_email);

    FOREACH v_pattern IN ARRAY string_to_array(v_patterns, ',')
    LOOP
        v_pattern := lower(trim(v_pattern));
        IF v_pattern = '' THEN
            CONTINUE;
        END IF;

        -- `@domain.tld` patterns match any email on that domain.
        IF left(v_pattern, 1) = '@' THEN
            IF v_email_lc LIKE '%' || v_pattern THEN
                RETURN TRUE;
            END IF;
        ELSE
            -- Otherwise exact match against the full email address.
            IF v_email_lc = v_pattern THEN
                RETURN TRUE;
            END IF;
        END IF;
    END LOOP;

    RETURN FALSE;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.is_test_account_email(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_test_account_email(TEXT) TO authenticated, service_role;

-- ═══════════════════════════════════════════════════════════════════════════
-- 4. REPLACE enroll_new_user_journey() — accept + auto-detect test flag
-- ═══════════════════════════════════════════════════════════════════════════
-- Add a 9th parameter `p_is_test_account` after the existing 8. The flag
-- captured here is the OR of the iOS heuristic and the server-side email
-- pattern check, so a real user typing into a debug build won't be
-- mis-flagged unless the email also matches.

DROP FUNCTION IF EXISTS public.enroll_new_user_journey(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT);
DROP FUNCTION IF EXISTS public.enroll_new_user_journey(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, BOOLEAN);
CREATE OR REPLACE FUNCTION public.enroll_new_user_journey(
    p_auth_provider        TEXT DEFAULT NULL,
    p_install_app_version  TEXT DEFAULT NULL,
    p_install_build_number TEXT DEFAULT NULL,
    p_install_device_model TEXT DEFAULT NULL,
    p_install_ios_version  TEXT DEFAULT NULL,
    p_install_locale       TEXT DEFAULT NULL,
    p_install_timezone     TEXT DEFAULT NULL,
    p_referral_source      TEXT DEFAULT NULL,
    p_is_test_account      BOOLEAN DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_email   TEXT;
    v_email_test BOOLEAN := FALSE;
    v_final_test BOOLEAN := FALSE;
    v_row     public.new_user_journey_enrollment%ROWTYPE;
BEGIN
    IF v_user_id IS NULL THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'not_authenticated');
    END IF;

    -- Pull the auth-side email so the server can backstop the iOS heuristic.
    -- (auth.users is owned by the auth schema; SECURITY DEFINER here gives
    -- the function the auth-admin role under the hood, which is allowed to
    -- read the email column.)
    SELECT email INTO v_email FROM auth.users WHERE id = v_user_id;
    v_email_test := public.is_test_account_email(v_email);

    -- Logical OR — flag wins if EITHER side says "test".
    v_final_test := COALESCE(p_is_test_account, FALSE) OR v_email_test;

    SELECT * INTO v_row
    FROM public.new_user_journey_enrollment
    WHERE user_id = v_user_id;

    IF NOT FOUND THEN
        INSERT INTO public.new_user_journey_enrollment (
            user_id,
            auth_provider, install_app_version, install_build_number,
            install_device_model, install_ios_version, install_locale,
            install_timezone, referral_source, is_test_account
        ) VALUES (
            v_user_id,
            p_auth_provider, p_install_app_version, p_install_build_number,
            p_install_device_model, p_install_ios_version, p_install_locale,
            p_install_timezone, p_referral_source, v_final_test
        )
        RETURNING * INTO v_row;
    ELSE
        -- Already enrolled. Don't reset the journey window, but DO let an
        -- iOS update flip the test-account flag (e.g. user toggled the dev
        -- menu after enrollment) — only flip TRUE-ward; never demote a
        -- flagged-true row back to false (would trigger surprise recapture).
        IF v_final_test AND NOT v_row.is_test_account THEN
            UPDATE public.new_user_journey_enrollment
            SET is_test_account = TRUE
            WHERE user_id = v_user_id;
            v_row.is_test_account := TRUE;
        END IF;
    END IF;

    RETURN jsonb_build_object(
        'success',            TRUE,
        'newly_enrolled',     v_row.enrolled_at >= now() - INTERVAL '1 minute',
        'journey_started_at', to_char(v_row.journey_started_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
        'journey_ends_at',    to_char(v_row.journey_ends_at    AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
        'is_active',          v_row.journey_ends_at > now(),
        'is_test_account',    v_row.is_test_account,
        'email_test_match',   v_email_test
    );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.enroll_new_user_journey(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, BOOLEAN) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.enroll_new_user_journey(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, BOOLEAN) TO authenticated, service_role;

-- ═══════════════════════════════════════════════════════════════════════════
-- 5. REPLACE record_new_user_session_start() — gate counter on actual INSERT
-- ═══════════════════════════════════════════════════════════════════════════
-- Old version unconditionally bumped `total_sessions` after an
-- `INSERT … ON CONFLICT DO NOTHING`. Effect: silent push wakes that re-sent
-- the same session_id double-counted (the row stays unique, but the counter
-- climbs). Now we use a CTE with RETURNING so the counter only bumps on a
-- net-new insert.

DROP FUNCTION IF EXISTS public.record_new_user_session_start(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT);
CREATE OR REPLACE FUNCTION public.record_new_user_session_start(
    p_session_id    TEXT,
    p_app_version   TEXT DEFAULT NULL,
    p_build_number  TEXT DEFAULT NULL,
    p_device_model  TEXT DEFAULT NULL,
    p_ios_version   TEXT DEFAULT NULL,
    p_network_type  TEXT DEFAULT NULL,
    p_entry_screen  TEXT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_user_id      UUID := auth.uid();
    v_active       BOOLEAN := FALSE;
    v_inserted_id  UUID;
BEGIN
    IF v_user_id IS NULL THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'not_authenticated');
    END IF;

    SELECT (journey_ends_at > now()) INTO v_active
    FROM public.new_user_journey_enrollment
    WHERE user_id = v_user_id;

    IF NOT COALESCE(v_active, FALSE) THEN
        RETURN jsonb_build_object('success', TRUE, 'recorded', FALSE, 'reason', 'not_active');
    END IF;

    -- CTE returns the inserted row's id ONLY if the conflict path didn't
    -- fire. NULL-coalesce afterwards drives the conditional counter bump.
    WITH inserted AS (
        INSERT INTO public.new_user_journey_sessions (
            user_id, session_id, app_version, build_number,
            device_model, ios_version, network_type, entry_screen
        ) VALUES (
            v_user_id, p_session_id, p_app_version, p_build_number,
            p_device_model, p_ios_version, p_network_type, p_entry_screen
        )
        ON CONFLICT (user_id, session_id) DO NOTHING
        RETURNING id
    )
    SELECT id INTO v_inserted_id FROM inserted;

    IF v_inserted_id IS NOT NULL THEN
        UPDATE public.new_user_journey_enrollment
        SET total_sessions = total_sessions + 1
        WHERE user_id = v_user_id;
    END IF;

    RETURN jsonb_build_object(
        'success',  TRUE,
        'recorded', v_inserted_id IS NOT NULL,
        'reason',   CASE WHEN v_inserted_id IS NULL THEN 'duplicate_session_id' ELSE NULL END
    );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.record_new_user_session_start(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.record_new_user_session_start(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) TO authenticated, service_role;

-- ═══════════════════════════════════════════════════════════════════════════
-- 6. REPLACE trigger_generate_new_user_reports() — skip test accounts
-- ═══════════════════════════════════════════════════════════════════════════
-- Same shape as the original (counts pending checkpoint rows, fast-path
-- skips on empty queue, otherwise fires net.http_post → edge function),
-- but with `AND is_test_account = FALSE` baked into the pending-count.
-- Test enrollments simply never enter the queue.

DROP FUNCTION IF EXISTS public.trigger_generate_new_user_reports();
CREATE OR REPLACE FUNCTION public.trigger_generate_new_user_reports()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_pending     INT;
    v_supabase_url TEXT;
    v_service_key  TEXT;
    v_cron_key     TEXT;
    v_request_id   BIGINT;
BEGIN
    SELECT COUNT(*) INTO v_pending
    FROM public.new_user_journey_enrollment
    WHERE is_test_account = FALSE
      AND (
            (d1_report_due_at    <= now() AND d1_report_generated    = FALSE)
         OR (d2_report_due_at    <= now() AND d2_report_generated    = FALSE)
         OR (d3_report_due_at    <= now() AND d3_report_generated    = FALSE)
         OR (final_report_due_at <= now() AND final_report_generated = FALSE)
      );

    IF v_pending = 0 THEN
        RETURN jsonb_build_object('skipped', TRUE, 'pending', 0);
    END IF;

    SELECT value INTO v_supabase_url FROM public.internal_config WHERE key = 'supabase_url';
    SELECT value INTO v_service_key  FROM public.internal_config WHERE key = 'service_role_key';
    SELECT value INTO v_cron_key     FROM public.internal_config WHERE key = 'cron_key';

    IF v_supabase_url IS NULL OR v_service_key IS NULL OR v_cron_key IS NULL THEN
        RAISE WARNING 'trigger_generate_new_user_reports: internal_config missing required keys — skipping';
        RETURN jsonb_build_object('skipped', TRUE, 'reason', 'missing_config');
    END IF;

    SELECT net.http_post(
        url     := v_supabase_url || '/functions/v1/generate-new-user-report',
        headers := jsonb_build_object(
                       'Content-Type',  'application/json',
                       'Authorization', 'Bearer ' || v_service_key,
                       'x-cron-key',    v_cron_key
                   ),
        body    := jsonb_build_object('source', 'pg_cron', 'pending', v_pending)
    ) INTO v_request_id;

    RETURN jsonb_build_object('triggered', TRUE, 'pending', v_pending, 'request_id', v_request_id);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.trigger_generate_new_user_reports() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.trigger_generate_new_user_reports() TO service_role;

-- ═══════════════════════════════════════════════════════════════════════════
-- 7. cleanup_test_journey_data() — auto-delete test data after 24h
-- ═══════════════════════════════════════════════════════════════════════════
-- AUTO-DELETE policy (per product owner directive 2026-05-10): once a test
-- enrollment is older than 24 hours, drop everything — events, sessions,
-- generated reports, and the enrollment row itself. Cron runs hourly.
--
-- Why 24h instead of immediate? Gives the developer a full day to inspect
-- their own test session in the admin CMS before it disappears. Anything
-- shorter and a multi-hour debug session loses its history mid-stream.

DROP FUNCTION IF EXISTS public.cleanup_test_journey_data();
CREATE OR REPLACE FUNCTION public.cleanup_test_journey_data()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_users_deleted    INT := 0;
    v_events_deleted   INT := 0;
    v_sessions_deleted INT := 0;
    v_reports_deleted  INT := 0;
BEGIN
    -- Snapshot the test users to delete (older than 24h) once, then cascade
    -- through children. Doing it in one pass via FK CASCADE would lose the
    -- per-table counts we want for the admin audit trail.
    WITH targets AS (
        SELECT user_id
        FROM public.new_user_journey_enrollment
        WHERE is_test_account = TRUE
          AND enrolled_at < now() - INTERVAL '24 hours'
    ),
    del_events AS (
        DELETE FROM public.new_user_journey_events
        WHERE user_id IN (SELECT user_id FROM targets)
        RETURNING 1
    ),
    del_sessions AS (
        DELETE FROM public.new_user_journey_sessions
        WHERE user_id IN (SELECT user_id FROM targets)
        RETURNING 1
    ),
    del_reports AS (
        DELETE FROM public.new_user_journey_reports
        WHERE user_id IN (SELECT user_id FROM targets)
        RETURNING 1
    ),
    del_enrollment AS (
        DELETE FROM public.new_user_journey_enrollment
        WHERE user_id IN (SELECT user_id FROM targets)
        RETURNING 1
    )
    SELECT
        (SELECT COUNT(*) FROM del_enrollment),
        (SELECT COUNT(*) FROM del_events),
        (SELECT COUNT(*) FROM del_sessions),
        (SELECT COUNT(*) FROM del_reports)
    INTO v_users_deleted, v_events_deleted, v_sessions_deleted, v_reports_deleted;

    RETURN jsonb_build_object(
        'success',          TRUE,
        'users_deleted',    v_users_deleted,
        'events_deleted',   v_events_deleted,
        'sessions_deleted', v_sessions_deleted,
        'reports_deleted',  v_reports_deleted
    );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.cleanup_test_journey_data() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.cleanup_test_journey_data() TO service_role;

-- ═══════════════════════════════════════════════════════════════════════════
-- 8. CRON: register the new cleanup job (hourly)
-- ═══════════════════════════════════════════════════════════════════════════
-- Mirrors the pattern used by 20260803 (extension check, conditional
-- schedule). The hourly cadence is cheap (one COUNT-with-WHERE on a
-- typically-empty set) and matches the immediacy product wants.

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
        -- Idempotent: pg_cron rejects duplicate jobnames, so unschedule first.
        PERFORM cron.unschedule('cleanup-test-journey-hourly')
        WHERE EXISTS (
            SELECT 1 FROM cron.job WHERE jobname = 'cleanup-test-journey-hourly'
        );

        PERFORM cron.schedule(
            'cleanup-test-journey-hourly',
            '7 * * * *',
            'SELECT public.cleanup_test_journey_data();'
        );

        RAISE NOTICE '✅ pg_cron schedule registered: cleanup-test-journey-hourly (7 * * * *)';
    ELSE
        RAISE NOTICE '⚠️ pg_cron not installed — schedule manually after extension enable.';
    END IF;
END$$;

-- ═══════════════════════════════════════════════════════════════════════════
-- 9. BACKFILL: flag existing 15 enrollments based on email pattern
-- ═══════════════════════════════════════════════════════════════════════════
-- Run once at deploy time. After this, the `is_test_account` column is
-- self-maintained by `enroll_new_user_journey` going forward.

DO $$
DECLARE
    v_flagged INT;
BEGIN
    UPDATE public.new_user_journey_enrollment e
    SET is_test_account = TRUE
    FROM auth.users u
    WHERE e.user_id = u.id
      AND e.is_test_account = FALSE
      AND public.is_test_account_email(u.email) = TRUE;

    GET DIAGNOSTICS v_flagged = ROW_COUNT;
    RAISE NOTICE '✅ Backfilled % existing enrollment(s) as test accounts', v_flagged;
END$$;

-- ═══════════════════════════════════════════════════════════════════════════
-- 10. TRAILING FAIL-LOUD AUDIT
-- ═══════════════════════════════════════════════════════════════════════════

DO $$
BEGIN
    -- Column present
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name   = 'new_user_journey_enrollment'
          AND column_name  = 'is_test_account'
    ) THEN
        RAISE EXCEPTION 'AUDIT FAIL — new_user_journey_enrollment.is_test_account missing';
    END IF;

    -- Functions present (overload-stable lookup)
    IF NOT EXISTS (
        SELECT 1 FROM pg_proc p JOIN pg_namespace n ON p.pronamespace = n.oid
        WHERE n.nspname = 'public' AND p.proname = 'is_test_account_email'
    ) THEN
        RAISE EXCEPTION 'AUDIT FAIL — is_test_account_email() missing';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_proc p JOIN pg_namespace n ON p.pronamespace = n.oid
        WHERE n.nspname = 'public' AND p.proname = 'cleanup_test_journey_data'
    ) THEN
        RAISE EXCEPTION 'AUDIT FAIL — cleanup_test_journey_data() missing';
    END IF;

    -- internal_config seed present
    IF NOT EXISTS (
        SELECT 1 FROM public.internal_config
        WHERE key = 'nuj_test_account_email_patterns'
    ) THEN
        RAISE EXCEPTION 'AUDIT FAIL — nuj_test_account_email_patterns missing in internal_config';
    END IF;

    RAISE NOTICE '✅ TEST-ACCOUNT ISOLATION (#175) DEPLOYED';
END$$;

COMMIT;
