-- =============================================================================
-- New User Journey — `is_error` default + RPC NULL-safety hardening
-- =============================================================================
-- Wall-clock authored: 2026-05-07
--
-- ROOT CAUSE
--   Cold-start logs from production sessions show every flush of
--   `record_new_user_events_batch` failing 9+ times per session with:
--
--     null value in column "is_error" of relation "new_user_journey_events"
--     violates not-null constraint
--
--   The defining migration (`20260803_new_user_journey_tracking.sql` §8 / §9)
--   declares the column as `BOOLEAN NOT NULL DEFAULT FALSE` AND both RPCs
--   compute `v_is_error` server-side before INSERT — so the iOS payload's
--   omission of `is_error` is *not* directly the trigger. The actual bug is
--   PostgreSQL three-valued boolean logic inside the RPC:
--
--     v_is_error := p_event_type IN ('error','crash')
--                   OR p_severity IN ('error','critical');
--
--   When `p_severity` is NULL (true for ~all non-error events — `screen`,
--   `tap`, `funnel`, `state`, `api`, `workout`, `meal`, `social`, `paywall`,
--   `integration`, `permission`, `notification`, `background`, `performance`),
--   the right-hand `IN` clause evaluates to NULL — and `FALSE OR NULL = NULL`
--   in SQL. The INSERT then carries an explicit NULL value (not an omission,
--   so the column DEFAULT cannot rescue it), and the NOT NULL constraint
--   rejects the row.
--
-- THIS MIGRATION
--   1. Re-affirms `DEFAULT FALSE` on `new_user_journey_events.is_error`
--      idempotently — no-op if already present (it is, per #20260803), but
--      cheap insurance for any out-of-band ALTER that may have stripped it.
--   2. Replaces both `record_new_user_event` (single) and
--      `record_new_user_events_batch` (bulk) so that:
--        a. `v_is_error` is wrapped in `COALESCE(..., FALSE)` to neutralize
--           the three-valued NULL leak.
--        b. The RPC honors a client-supplied `is_error` boolean if present
--           in the per-event JSON / arg list. This makes the iOS-side
--           defense-in-depth fix (`Fit33/NewUserJourneyTracker.swift::recordEvent`
--           now stamps `is_error` based on `event_type` / `severity`) the
--           authoritative source while preserving server-side computation
--           as a fallback for legacy clients.
--   3. Drops every prior overload of both RPCs before CREATE OR REPLACE per
--      supabase-rules §32 (`pg_proc`-loop pattern), then asserts post-deploy
--      that exactly one definition exists per RPC name (supabase-rules §28
--      audit guard).
--
-- BEHAVIORAL EQUIVALENCE
--   For every event the iOS client has ever sent (which omits the new
--   `is_error` field), the recomputed value matches the prior intent:
--     - `event_type IN ('error','crash')` → TRUE
--     - `severity   IN ('error','critical')` → TRUE
--     - everything else → FALSE (was previously NULL → INSERT failure)
--   So legitimately-error events still flag `is_error = TRUE`, the broken
--   path now writes `is_error = FALSE`, and zero events are lost or
--   misclassified.
--
-- BUG-INTEL FINGERPRINTS
--   Skipped — the runtime flush-failure is a network-layer wrap of a
--   PostgREST 23502 (`not_null_violation`); fingerprint hash not authored
--   from the agent surface to avoid fabrication. Update the
--   `bug_intelligence_fingerprints` row out-of-band once the matching hash
--   is confirmed via the dashboard.
--
-- Idempotent / safe to re-deploy. Wrapped in BEGIN; / COMMIT;.
-- =============================================================================

BEGIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Re-affirm DEFAULT FALSE on the column (idempotent — no-op if already set).
--    Wrapped in DO so we can guard on `information_schema.columns` to skip
--    the ALTER cleanly if the table somehow doesn't exist (treat as soft no-op
--    rather than hard error so the migration is replay-safe across stages
--    where the parent #20260803 hasn't shipped yet — `__migrations` ordering
--    should prevent that, but defense in depth).
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name   = 'new_user_journey_events'
          AND column_name  = 'is_error'
    ) THEN
        EXECUTE 'ALTER TABLE public.new_user_journey_events
                 ALTER COLUMN is_error SET DEFAULT FALSE';
        RAISE NOTICE '[nuj-is-error-default] DEFAULT FALSE re-affirmed on new_user_journey_events.is_error';
    ELSE
        RAISE NOTICE '[nuj-is-error-default] new_user_journey_events.is_error not found — skipping ALTER (parent migration 20260803 not yet applied)';
    END IF;
END
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Replace `record_new_user_event` — single-event variant.
--    Drop ALL overloads first via the canonical pg_proc loop (supabase-rules §32).
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN
        SELECT format('%I.%I(%s)', n.nspname, p.proname,
                      pg_get_function_identity_arguments(p.oid)) AS sig
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public'
          AND p.proname = 'record_new_user_event'
    LOOP
        EXECUTE 'DROP FUNCTION IF EXISTS ' || r.sig || ' CASCADE';
    END LOOP;
END
$$;

CREATE OR REPLACE FUNCTION public.record_new_user_event(
    p_event_type   TEXT,
    p_session_id   TEXT  DEFAULT NULL,
    p_screen       TEXT  DEFAULT NULL,
    p_detail       TEXT  DEFAULT NULL,
    p_payload      JSONB DEFAULT '{}'::jsonb,
    p_severity     TEXT  DEFAULT NULL,
    p_is_error     BOOLEAN DEFAULT NULL  -- NEW: optional client-supplied flag
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_user_id   UUID := auth.uid();
    v_active    BOOLEAN := FALSE;
    v_event_id  UUID;
    v_is_error  BOOLEAN;
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

    -- Honor the client-supplied flag when present, otherwise compute from
    -- event_type / severity. COALESCE the final result so the three-valued
    -- `FALSE OR NULL = NULL` SQL trap can never re-emerge.
    v_is_error := COALESCE(
        p_is_error,
        COALESCE(p_event_type IN ('error','crash'), FALSE)
            OR COALESCE(p_severity   IN ('error','critical'), FALSE),
        FALSE
    );

    INSERT INTO public.new_user_journey_events (
        user_id, session_id, event_type, screen, detail, payload,
        is_error, severity
    ) VALUES (
        v_user_id, p_session_id, p_event_type, p_screen, p_detail,
        COALESCE(p_payload, '{}'::jsonb), v_is_error, p_severity
    ) RETURNING id INTO v_event_id;

    RETURN jsonb_build_object('success', TRUE, 'recorded', TRUE, 'event_id', v_event_id);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.record_new_user_event(TEXT, TEXT, TEXT, TEXT, JSONB, TEXT, BOOLEAN) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.record_new_user_event(TEXT, TEXT, TEXT, TEXT, JSONB, TEXT, BOOLEAN) TO authenticated, service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Replace `record_new_user_events_batch` — bulk variant (the one iOS hits).
--    Drop ALL overloads first.
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN
        SELECT format('%I.%I(%s)', n.nspname, p.proname,
                      pg_get_function_identity_arguments(p.oid)) AS sig
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public'
          AND p.proname = 'record_new_user_events_batch'
    LOOP
        EXECUTE 'DROP FUNCTION IF EXISTS ' || r.sig || ' CASCADE';
    END LOOP;
END
$$;

CREATE OR REPLACE FUNCTION public.record_new_user_events_batch(
    p_events JSONB
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_user_id     UUID := auth.uid();
    v_active      BOOLEAN := FALSE;
    v_inserted    INT := 0;
    v_event       JSONB;
    v_event_type  TEXT;
    v_session_id  TEXT;
    v_screen      TEXT;
    v_detail      TEXT;
    v_payload     JSONB;
    v_severity    TEXT;
    v_occurred    TIMESTAMPTZ;
    v_is_error    BOOLEAN;
    v_client_flag BOOLEAN;
BEGIN
    IF v_user_id IS NULL THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'not_authenticated');
    END IF;

    SELECT (journey_ends_at > now()) INTO v_active
    FROM public.new_user_journey_enrollment
    WHERE user_id = v_user_id;

    IF NOT COALESCE(v_active, FALSE) THEN
        RETURN jsonb_build_object('success', TRUE, 'recorded', 0, 'reason', 'not_active');
    END IF;

    IF jsonb_typeof(p_events) <> 'array' THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'payload_not_array');
    END IF;

    FOR v_event IN SELECT * FROM jsonb_array_elements(p_events) LOOP
        v_event_type := v_event->>'event_type';
        IF v_event_type IS NULL THEN CONTINUE; END IF;

        v_session_id := v_event->>'session_id';
        v_screen     := v_event->>'screen';
        v_detail     := v_event->>'detail';
        v_payload    := COALESCE(v_event->'payload', '{}'::jsonb);
        v_severity   := v_event->>'severity';

        IF v_event ? 'occurred_at_ms' THEN
            v_occurred := to_timestamp((v_event->>'occurred_at_ms')::BIGINT / 1000.0);
        ELSE
            v_occurred := now();
        END IF;

        -- Pull the optional client flag (NULL if iOS didn't send it).
        IF v_event ? 'is_error' AND jsonb_typeof(v_event->'is_error') = 'boolean' THEN
            v_client_flag := (v_event->>'is_error')::BOOLEAN;
        ELSE
            v_client_flag := NULL;
        END IF;

        -- Honor client flag first; fall back to server computation; final
        -- COALESCE against FALSE so a missing severity can never produce a
        -- NULL via three-valued OR (the original NOT-NULL violation root cause).
        v_is_error := COALESCE(
            v_client_flag,
            COALESCE(v_event_type IN ('error','crash'),    FALSE)
                OR COALESCE(v_severity IN ('error','critical'), FALSE),
            FALSE
        );

        INSERT INTO public.new_user_journey_events (
            user_id, session_id, event_type, screen, detail, payload,
            is_error, severity, occurred_at
        ) VALUES (
            v_user_id, v_session_id, v_event_type, v_screen, v_detail, v_payload,
            v_is_error, v_severity, v_occurred
        );
        v_inserted := v_inserted + 1;
    END LOOP;

    RETURN jsonb_build_object('success', TRUE, 'recorded', v_inserted);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.record_new_user_events_batch(JSONB) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.record_new_user_events_batch(JSONB) TO authenticated, service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. Audit guard — exactly one live definition per RPC name (supabase-rules §28).
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
DECLARE
    v_single INT;
    v_batch  INT;
BEGIN
    SELECT COUNT(*) INTO v_single
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'record_new_user_event';

    SELECT COUNT(*) INTO v_batch
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'record_new_user_events_batch';

    IF v_single <> 1 THEN
        RAISE EXCEPTION
            'record_new_user_event overload audit failed: expected 1 def, found %',
            v_single;
    END IF;
    IF v_batch <> 1 THEN
        RAISE EXCEPTION
            'record_new_user_events_batch overload audit failed: expected 1 def, found %',
            v_batch;
    END IF;

    RAISE NOTICE '[nuj-is-error-default] overload audit OK (single=%, batch=%)', v_single, v_batch;
END
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. Schema-cache reload so PostgREST sees the new `p_is_error` arg without
--    waiting for the periodic 5–12 min refresh (supabase-rules §44).
-- ─────────────────────────────────────────────────────────────────────────────
NOTIFY pgrst, 'reload schema';

COMMIT;
