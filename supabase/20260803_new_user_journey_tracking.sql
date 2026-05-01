-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║ Migration #167 — New User Journey Tracking (the "Zuckerberg" pipeline)   ║
-- ╚══════════════════════════════════════════════════════════════════════════╝
--
-- Single sweep of high-resolution behavioral telemetry for every new user
-- during their FIRST 72 HOURS in the app. Auto-enrolled by tenure (no
-- per-email allowlist like dev_logging_users); auto-deactivates at the
-- 72h mark; produces a Claude-ready per-user report at every checkpoint
-- (D1, D2, D3, FINAL).
--
-- Why a parallel pipeline (not just `dev_session_logs`):
--  - dev_session_logs is opt-in by email — too narrow for "every new user".
--  - We need a strict TTL window (3 days) so storage stays bounded as the
--    install base grows.
--  - The report cadence is per-user-day, not per-session — different from
--    bug-intel's per-fingerprint cadence.
--  - Storage class is conceptually different: this is product-analytics
--    grade (high churn, low long-term retention) vs bug-intel's
--    forensic-grade (long retention).
--
-- Tables (all RLS-enabled; service-role + auth.uid()-pinned RPCs only):
--  1. new_user_journey_enrollment  — one row/user, 3-day TTL window
--  2. new_user_journey_sessions    — per-launch metadata, FK enrollment
--  3. new_user_journey_events      — append-only event log, indexed by
--                                    (user_id, occurred_at)
--  4. new_user_journey_reports     — Claude-pipe Markdown reports
--
-- RPCs:
--  - enroll_new_user_journey()                  — first-auth idempotent enroll
--  - is_in_new_user_journey()                   — fast bool, drives iOS gate
--  - record_new_user_event(...)                 — append event (auth.uid()-pinned)
--  - record_new_user_session_start(...)         — start a session
--  - record_new_user_session_end(...)           — end a session
--  - get_new_user_journey_report_data(uuid)    — service-role: full data dump
--                                                 for the edge function
--  - cleanup_new_user_journey_data()            — retention drain (cron)
--
-- Cron:
--  - 5 * * * *  — generate-new-user-report wrapper (hourly checkpoints)
--  - 30 4 * * * — cleanup_new_user_journey_data() (drains expired rows)
--
-- Privacy / PII posture:
--  - No email/phone/full-name in event payloads — only user_id (UUID).
--  - User-typed strings (search queries, food names) ARE captured because
--    they're product-search terms, not PII. Free-text bug-report bodies
--    stay in `bug_reports`, not here.
--  - retention: 30 days from journey_started_at. After that the cleanup
--    cron drops events; reports retain.
--
-- Bug-intel hygiene:
--  - This is its OWN pipeline; it does NOT use bug_intel_classify_error /
--    bug_intelligence_fingerprints. Errors logged here are CLASSIFIED COPIES
--    of what bug-intel already saw via dev_session_logs / crash_reports.
--  - The new-user error rate is a product metric (drop-off correlator),
--    not a bug-detection signal — so we want it isolated.
--
-- Idempotency: every CREATE uses IF NOT EXISTS or DROP-IF-EXISTS-then-CREATE.
-- Trailing fail-loud DO $$ block enforces post-state.
--
-- ───────────────────────────────────────────────────────────────────────────

BEGIN;

-- ═══════════════════════════════════════════════════════════════════════════
-- 1. ENROLLMENT TABLE — one row per user, the canonical TTL gate
-- ═══════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.new_user_journey_enrollment (
    user_id              UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    enrolled_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    journey_started_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    journey_ends_at      TIMESTAMPTZ NOT NULL DEFAULT (now() + INTERVAL '72 hours'),
    auth_provider        TEXT,                -- 'email' | 'apple' | 'google' | 'facebook' | 'phone' | NULL
    install_app_version  TEXT,                -- e.g. "1.39"
    install_build_number TEXT,                -- e.g. "61"
    install_device_model TEXT,                -- e.g. "iPhone17,2"
    install_ios_version  TEXT,                -- e.g. "18.4.1"
    install_locale       TEXT,                -- e.g. "en_US"
    install_timezone     TEXT,                -- e.g. "America/New_York"
    referral_source      TEXT,                -- contact-import / share-link / none
    -- Report lifecycle (one row per checkpoint)
    d1_report_due_at     TIMESTAMPTZ NOT NULL DEFAULT (now() + INTERVAL '24 hours'),
    d1_report_generated  BOOLEAN NOT NULL DEFAULT FALSE,
    d2_report_due_at     TIMESTAMPTZ NOT NULL DEFAULT (now() + INTERVAL '48 hours'),
    d2_report_generated  BOOLEAN NOT NULL DEFAULT FALSE,
    d3_report_due_at     TIMESTAMPTZ NOT NULL DEFAULT (now() + INTERVAL '72 hours'),
    d3_report_generated  BOOLEAN NOT NULL DEFAULT FALSE,
    final_report_due_at  TIMESTAMPTZ NOT NULL DEFAULT (now() + INTERVAL '78 hours'),
    final_report_generated BOOLEAN NOT NULL DEFAULT FALSE,
    -- Aggregated counters (cheap rollup, updated on event insert via trigger)
    total_events         INT NOT NULL DEFAULT 0,
    total_sessions       INT NOT NULL DEFAULT 0,
    total_errors         INT NOT NULL DEFAULT 0,
    total_crashes        INT NOT NULL DEFAULT 0,
    last_event_at        TIMESTAMPTZ,
    last_screen          TEXT,
    -- Funnel state (one-shot booleans driven by event types)
    completed_onboarding BOOLEAN NOT NULL DEFAULT FALSE,
    completed_first_workout BOOLEAN NOT NULL DEFAULT FALSE,
    logged_first_meal    BOOLEAN NOT NULL DEFAULT FALSE,
    added_first_friend   BOOLEAN NOT NULL DEFAULT FALSE,
    connected_wearable   BOOLEAN NOT NULL DEFAULT FALSE,
    saw_paywall          BOOLEAN NOT NULL DEFAULT FALSE,
    converted_paywall    BOOLEAN NOT NULL DEFAULT FALSE
);

ALTER TABLE public.new_user_journey_enrollment ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS nuj_enrollment_select_own ON public.new_user_journey_enrollment;
CREATE POLICY nuj_enrollment_select_own
    ON public.new_user_journey_enrollment
    FOR SELECT TO authenticated
    USING (user_id = auth.uid());

CREATE INDEX IF NOT EXISTS idx_nuj_enrollment_d1_due
    ON public.new_user_journey_enrollment (d1_report_due_at)
    WHERE d1_report_generated = FALSE;

CREATE INDEX IF NOT EXISTS idx_nuj_enrollment_d2_due
    ON public.new_user_journey_enrollment (d2_report_due_at)
    WHERE d2_report_generated = FALSE;

CREATE INDEX IF NOT EXISTS idx_nuj_enrollment_d3_due
    ON public.new_user_journey_enrollment (d3_report_due_at)
    WHERE d3_report_generated = FALSE;

CREATE INDEX IF NOT EXISTS idx_nuj_enrollment_final_due
    ON public.new_user_journey_enrollment (final_report_due_at)
    WHERE final_report_generated = FALSE;

CREATE INDEX IF NOT EXISTS idx_nuj_enrollment_journey_ends
    ON public.new_user_journey_enrollment (journey_ends_at);

-- ═══════════════════════════════════════════════════════════════════════════
-- 2. SESSIONS TABLE — per-launch metadata
-- ═══════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.new_user_journey_sessions (
    id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id              UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    session_id           TEXT NOT NULL,            -- client-generated, NewUserJourneyTracker
    started_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
    ended_at             TIMESTAMPTZ,
    duration_seconds     INT,                       -- populated on session end
    app_version          TEXT,
    build_number         TEXT,
    device_model         TEXT,
    ios_version          TEXT,
    network_type         TEXT,                      -- 'wifi' | 'cellular' | 'offline'
    entry_screen         TEXT,                      -- which screen the user landed on
    last_screen          TEXT,                      -- which screen was active when session ended
    error_count          INT NOT NULL DEFAULT 0,
    crash_count          INT NOT NULL DEFAULT 0,
    screen_view_count    INT NOT NULL DEFAULT 0,
    tap_count            INT NOT NULL DEFAULT 0,
    UNIQUE (user_id, session_id)
);

ALTER TABLE public.new_user_journey_sessions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS nuj_sessions_select_own ON public.new_user_journey_sessions;
CREATE POLICY nuj_sessions_select_own
    ON public.new_user_journey_sessions
    FOR SELECT TO authenticated
    USING (user_id = auth.uid());

CREATE INDEX IF NOT EXISTS idx_nuj_sessions_user_started
    ON public.new_user_journey_sessions (user_id, started_at DESC);

-- ═══════════════════════════════════════════════════════════════════════════
-- 3. EVENTS TABLE — append-only structured event log
-- ═══════════════════════════════════════════════════════════════════════════
--
-- event_type taxonomy (canonical — keep in sync with NewUserJourneyTracker):
--   'screen'          — screen view (payload: { screen })
--   'tap'             — user tap on actionable element (payload: { action, screen })
--   'funnel'          — onboarding/feature funnel step (payload: { funnel, step, step_index })
--   'state'           — state machine transition (payload: { from, to })
--   'api'             — outbound API call (payload: { endpoint, status, duration_ms })
--   'error'           — non-fatal error (payload: { message, category, file, line })
--   'crash'           — captured crash signal (payload: { reason, stack_top })
--   'workout'         — workout lifecycle (payload: { phase: 'started'|'completed'|'abandoned', ... })
--   'meal'            — meal logging (payload: { phase, food_name, source })
--   'social'          — friend/follow action (payload: { action, target_user_id })
--   'paywall'         — paywall surface event (payload: { surface, action: 'view'|'dismiss'|'convert', sku? })
--   'integration'     — wearable/HK connect (payload: { provider, action: 'attempt'|'success'|'failure' })
--   'permission'      — system permission prompt (payload: { kind, granted })
--   'notification'    — push received/opened (payload: { type, action })
--   'background'      — BG sync / silent push handled (payload: { reason, duration_ms })
--   'performance'     — perf budget breach (payload: { op, value, budget })
--   'system'          — app lifecycle (payload: { phase: 'launch'|'foreground'|'background' })

CREATE TABLE IF NOT EXISTS public.new_user_journey_events (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    session_id      TEXT,                          -- nullable for server-side events
    occurred_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    event_type      TEXT NOT NULL,                 -- see taxonomy above
    screen          TEXT,                          -- canonical SessionLogManager.Screen.displayName
    detail          TEXT,                          -- short human-readable label
    payload         JSONB NOT NULL DEFAULT '{}'::jsonb,
    -- denormalized for fast filtering without joining JSONB
    is_error        BOOLEAN NOT NULL DEFAULT FALSE,
    severity        TEXT,                          -- 'info'|'warning'|'error'|'critical'
    -- bug-intel cross-link (filled when this event is also a bug-intel signal)
    bi_fingerprint  TEXT
);

ALTER TABLE public.new_user_journey_events ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS nuj_events_select_own ON public.new_user_journey_events;
CREATE POLICY nuj_events_select_own
    ON public.new_user_journey_events
    FOR SELECT TO authenticated
    USING (user_id = auth.uid());

-- Hot-path index: per-user replay in time order
CREATE INDEX IF NOT EXISTS idx_nuj_events_user_time
    ON public.new_user_journey_events (user_id, occurred_at DESC);

-- Funnel queries: per-user filter by event_type
CREATE INDEX IF NOT EXISTS idx_nuj_events_user_type
    ON public.new_user_journey_events (user_id, event_type, occurred_at DESC);

-- Cohort error rates: time-windowed error count
CREATE INDEX IF NOT EXISTS idx_nuj_events_errors_time
    ON public.new_user_journey_events (occurred_at DESC)
    WHERE is_error = TRUE;

-- ═══════════════════════════════════════════════════════════════════════════
-- 4. REPORTS TABLE — Claude-pipe Markdown per checkpoint
-- ═══════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.new_user_journey_reports (
    id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id              UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    checkpoint           TEXT NOT NULL,            -- 'D1' | 'D2' | 'D3' | 'FINAL' | 'MANUAL'
    generated_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    -- Time-window the report covers
    window_started_at    TIMESTAMPTZ NOT NULL,
    window_ended_at      TIMESTAMPTZ NOT NULL,
    -- Pre-computed structured data (the analysis surface for Claude)
    structured_data      JSONB NOT NULL DEFAULT '{}'::jsonb,
    -- The full Markdown report (Claude-ready, also human-readable in CMS)
    report_md            TEXT NOT NULL,
    -- Claude's narrative analysis (filled by edge fn second pass when enabled)
    claude_analysis_md   TEXT,
    claude_model         TEXT,                     -- e.g. 'claude-sonnet-4-20250514'
    claude_tokens_in     INT,
    claude_tokens_out    INT,
    -- Lifecycle
    review_status        TEXT NOT NULL DEFAULT 'pending'
                         CHECK (review_status IN ('pending','reviewed','actioned','archived')),
    reviewed_by          TEXT,
    reviewed_at          TIMESTAMPTZ,
    notes                TEXT,
    UNIQUE (user_id, checkpoint, window_ended_at)
);

ALTER TABLE public.new_user_journey_reports ENABLE ROW LEVEL SECURITY;
-- Reports are admin-only; no SELECT policy for `authenticated`.
-- Service-role + admin CMS gateway are the only readers.

CREATE INDEX IF NOT EXISTS idx_nuj_reports_user_checkpoint
    ON public.new_user_journey_reports (user_id, checkpoint);

CREATE INDEX IF NOT EXISTS idx_nuj_reports_generated
    ON public.new_user_journey_reports (generated_at DESC);

CREATE INDEX IF NOT EXISTS idx_nuj_reports_status
    ON public.new_user_journey_reports (review_status, generated_at DESC);

-- ═══════════════════════════════════════════════════════════════════════════
-- 5. TRIGGER — keep enrollment counters fresh on every event insert
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.update_nuj_enrollment_counters()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    UPDATE public.new_user_journey_enrollment
    SET
        total_events        = total_events + 1,
        last_event_at       = NEW.occurred_at,
        last_screen         = COALESCE(NEW.screen, last_screen),
        total_errors        = total_errors + CASE WHEN NEW.is_error THEN 1 ELSE 0 END,
        total_crashes       = total_crashes + CASE WHEN NEW.event_type = 'crash' THEN 1 ELSE 0 END,
        completed_onboarding    = COALESCE(completed_onboarding,    FALSE) OR (NEW.event_type = 'funnel'      AND (NEW.payload->>'funnel') = 'onboarding' AND (NEW.payload->>'step') = 'completed'),
        completed_first_workout = COALESCE(completed_first_workout, FALSE) OR (NEW.event_type = 'workout'     AND (NEW.payload->>'phase')  = 'completed'),
        logged_first_meal       = COALESCE(logged_first_meal,       FALSE) OR (NEW.event_type = 'meal'        AND (NEW.payload->>'phase')  = 'logged'),
        added_first_friend      = COALESCE(added_first_friend,      FALSE) OR (NEW.event_type = 'social'      AND (NEW.payload->>'action') = 'friend_added'),
        connected_wearable      = COALESCE(connected_wearable,      FALSE) OR (NEW.event_type = 'integration' AND (NEW.payload->>'action') = 'success'),
        saw_paywall             = COALESCE(saw_paywall,             FALSE) OR (NEW.event_type = 'paywall'     AND (NEW.payload->>'action') = 'view'),
        converted_paywall       = COALESCE(converted_paywall,       FALSE) OR (NEW.event_type = 'paywall'     AND (NEW.payload->>'action') = 'convert')
    WHERE user_id = NEW.user_id;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_nuj_event_counters ON public.new_user_journey_events;
CREATE TRIGGER trg_nuj_event_counters
    AFTER INSERT ON public.new_user_journey_events
    FOR EACH ROW
    EXECUTE FUNCTION public.update_nuj_enrollment_counters();

-- ═══════════════════════════════════════════════════════════════════════════
-- 6. RPC: enroll_new_user_journey()
-- ═══════════════════════════════════════════════════════════════════════════
-- Idempotent first-auth enrollment. Auth.uid()-pinned. Returns the enrollment
-- row state — iOS uses `journey_ends_at` to drive its activation gate.
-- Safe to call on every cold start.
--
-- Auto-skips re-enrollment if the user already has an enrollment row, even
-- if the journey has expired. (Re-enrolling on day 90 would corrupt the
-- "first 72h" semantics.)

DROP FUNCTION IF EXISTS public.enroll_new_user_journey(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT);
CREATE OR REPLACE FUNCTION public.enroll_new_user_journey(
    p_auth_provider        TEXT DEFAULT NULL,
    p_install_app_version  TEXT DEFAULT NULL,
    p_install_build_number TEXT DEFAULT NULL,
    p_install_device_model TEXT DEFAULT NULL,
    p_install_ios_version  TEXT DEFAULT NULL,
    p_install_locale       TEXT DEFAULT NULL,
    p_install_timezone     TEXT DEFAULT NULL,
    p_referral_source      TEXT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_row     public.new_user_journey_enrollment%ROWTYPE;
    v_inserted BOOLEAN := FALSE;
BEGIN
    IF v_user_id IS NULL THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'not_authenticated');
    END IF;

    SELECT * INTO v_row
    FROM public.new_user_journey_enrollment
    WHERE user_id = v_user_id;

    IF NOT FOUND THEN
        INSERT INTO public.new_user_journey_enrollment (
            user_id,
            auth_provider, install_app_version, install_build_number,
            install_device_model, install_ios_version,
            install_locale, install_timezone, referral_source
        ) VALUES (
            v_user_id,
            p_auth_provider, p_install_app_version, p_install_build_number,
            p_install_device_model, p_install_ios_version,
            p_install_locale, p_install_timezone, p_referral_source
        )
        ON CONFLICT (user_id) DO NOTHING
        RETURNING * INTO v_row;
        v_inserted := TRUE;
    END IF;

    -- Re-fetch in case ON CONFLICT DO NOTHING raced with another caller
    IF v_row.user_id IS NULL THEN
        SELECT * INTO v_row
        FROM public.new_user_journey_enrollment
        WHERE user_id = v_user_id;
    END IF;

    RETURN jsonb_build_object(
        'success',            TRUE,
        'newly_enrolled',     v_inserted,
        'user_id',            v_row.user_id,
        'enrolled_at',        v_row.enrolled_at,
        'journey_started_at', v_row.journey_started_at,
        'journey_ends_at',    v_row.journey_ends_at,
        'is_active',          v_row.journey_ends_at > now()
    );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.enroll_new_user_journey(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.enroll_new_user_journey(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) TO authenticated, service_role;

-- ═══════════════════════════════════════════════════════════════════════════
-- 7. RPC: is_in_new_user_journey()
-- ═══════════════════════════════════════════════════════════════════════════
-- Cheap polled call; iOS uses to gate the high-resolution tracker.

DROP FUNCTION IF EXISTS public.is_in_new_user_journey();
CREATE OR REPLACE FUNCTION public.is_in_new_user_journey()
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_active  BOOLEAN := FALSE;
BEGIN
    IF v_user_id IS NULL THEN RETURN FALSE; END IF;

    SELECT (journey_ends_at > now()) INTO v_active
    FROM public.new_user_journey_enrollment
    WHERE user_id = v_user_id;

    RETURN COALESCE(v_active, FALSE);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.is_in_new_user_journey() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_in_new_user_journey() TO authenticated, service_role;

-- ═══════════════════════════════════════════════════════════════════════════
-- 8. RPC: record_new_user_event(event_type, screen, detail, payload, severity)
-- ═══════════════════════════════════════════════════════════════════════════
-- Auth.uid()-pinned. Cheap append. NO-OP if the user is not enrolled or
-- the journey has expired (so the iOS client can fire optimistically).

DROP FUNCTION IF EXISTS public.record_new_user_event(TEXT, TEXT, TEXT, TEXT, JSONB, TEXT);
CREATE OR REPLACE FUNCTION public.record_new_user_event(
    p_event_type   TEXT,
    p_session_id   TEXT DEFAULT NULL,
    p_screen       TEXT DEFAULT NULL,
    p_detail       TEXT DEFAULT NULL,
    p_payload      JSONB DEFAULT '{}'::jsonb,
    p_severity     TEXT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_active  BOOLEAN := FALSE;
    v_event_id UUID;
    v_is_error BOOLEAN;
BEGIN
    IF v_user_id IS NULL THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'not_authenticated');
    END IF;

    -- Fast gate: drop the event if the user isn't in their first-72h window.
    -- Cheap silent no-op so the iOS client can fire optimistically without
    -- a separate is_in_new_user_journey() round-trip.
    SELECT (journey_ends_at > now()) INTO v_active
    FROM public.new_user_journey_enrollment
    WHERE user_id = v_user_id;

    IF NOT COALESCE(v_active, FALSE) THEN
        RETURN jsonb_build_object('success', TRUE, 'recorded', FALSE, 'reason', 'not_active');
    END IF;

    v_is_error := p_event_type IN ('error','crash')
                  OR p_severity IN ('error','critical');

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

REVOKE EXECUTE ON FUNCTION public.record_new_user_event(TEXT, TEXT, TEXT, TEXT, JSONB, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.record_new_user_event(TEXT, TEXT, TEXT, TEXT, JSONB, TEXT) TO authenticated, service_role;

-- Bulk variant for batched event uploads (iOS flushes every 10s / 50 events).
DROP FUNCTION IF EXISTS public.record_new_user_events_batch(JSONB);
CREATE OR REPLACE FUNCTION public.record_new_user_events_batch(
    p_events JSONB           -- array of objects: { event_type, session_id?, screen?, detail?, payload?, severity?, occurred_at_ms? }
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_active  BOOLEAN := FALSE;
    v_inserted INT := 0;
    v_event JSONB;
    v_event_type TEXT;
    v_session_id TEXT;
    v_screen TEXT;
    v_detail TEXT;
    v_payload JSONB;
    v_severity TEXT;
    v_occurred TIMESTAMPTZ;
    v_is_error BOOLEAN;
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

        v_is_error := v_event_type IN ('error','crash')
                      OR v_severity IN ('error','critical');

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
GRANT EXECUTE ON FUNCTION public.record_new_user_events_batch(JSONB) TO authenticated, service_role;

-- ═══════════════════════════════════════════════════════════════════════════
-- 9. RPCs: session start / end
-- ═══════════════════════════════════════════════════════════════════════════

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
    v_user_id UUID := auth.uid();
    v_active  BOOLEAN := FALSE;
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

    INSERT INTO public.new_user_journey_sessions (
        user_id, session_id, app_version, build_number,
        device_model, ios_version, network_type, entry_screen
    ) VALUES (
        v_user_id, p_session_id, p_app_version, p_build_number,
        p_device_model, p_ios_version, p_network_type, p_entry_screen
    )
    ON CONFLICT (user_id, session_id) DO NOTHING;

    UPDATE public.new_user_journey_enrollment
    SET total_sessions = total_sessions + 1
    WHERE user_id = v_user_id;

    RETURN jsonb_build_object('success', TRUE, 'recorded', TRUE);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.record_new_user_session_start(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.record_new_user_session_start(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) TO authenticated, service_role;

DROP FUNCTION IF EXISTS public.record_new_user_session_end(TEXT, TEXT, INT, INT, INT, INT);
CREATE OR REPLACE FUNCTION public.record_new_user_session_end(
    p_session_id        TEXT,
    p_last_screen       TEXT DEFAULT NULL,
    p_error_count       INT DEFAULT 0,
    p_crash_count       INT DEFAULT 0,
    p_screen_view_count INT DEFAULT 0,
    p_tap_count         INT DEFAULT 0
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_user_id UUID := auth.uid();
BEGIN
    IF v_user_id IS NULL THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'not_authenticated');
    END IF;

    UPDATE public.new_user_journey_sessions
    SET
        ended_at          = now(),
        duration_seconds  = EXTRACT(EPOCH FROM (now() - started_at))::INT,
        last_screen       = COALESCE(p_last_screen, last_screen),
        error_count       = error_count + COALESCE(p_error_count, 0),
        crash_count       = crash_count + COALESCE(p_crash_count, 0),
        screen_view_count = screen_view_count + COALESCE(p_screen_view_count, 0),
        tap_count         = tap_count + COALESCE(p_tap_count, 0)
    WHERE user_id = v_user_id AND session_id = p_session_id;

    RETURN jsonb_build_object('success', TRUE);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.record_new_user_session_end(TEXT, TEXT, INT, INT, INT, INT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.record_new_user_session_end(TEXT, TEXT, INT, INT, INT, INT) TO authenticated, service_role;

-- ═══════════════════════════════════════════════════════════════════════════
-- 10. RPC: get_new_user_journey_report_data(p_user_id, p_window_start, p_window_end)
-- ═══════════════════════════════════════════════════════════════════════════
-- Service-role gateway: returns the FULL data dump the edge function needs
-- to build the Markdown report. Service-role-only — IDOR-pinned via the
-- "auth.uid() IS NOT NULL implies caller=target" guard, which lets pg_cron
-- and the service-role-key path through.

DROP FUNCTION IF EXISTS public.get_new_user_journey_report_data(UUID, TIMESTAMPTZ, TIMESTAMPTZ);
CREATE OR REPLACE FUNCTION public.get_new_user_journey_report_data(
    p_user_id      UUID,
    p_window_start TIMESTAMPTZ DEFAULT NULL,
    p_window_end   TIMESTAMPTZ DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_caller UUID := auth.uid();
    v_enrollment public.new_user_journey_enrollment%ROWTYPE;
    v_window_start TIMESTAMPTZ;
    v_window_end   TIMESTAMPTZ;
    v_events JSONB;
    v_sessions JSONB;
    v_funnel  JSONB;
    v_screens JSONB;
    v_errors  JSONB;
    v_workouts INT;
    v_meals INT;
    v_friends INT;
    v_paywall_views INT;
BEGIN
    -- IDOR: when called by an authenticated user (not service role),
    -- they may only fetch their own data. Service role / cron pass auth.uid()=NULL.
    IF v_caller IS NOT NULL AND v_caller <> p_user_id THEN
        RAISE EXCEPTION 'Forbidden' USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_enrollment
    FROM public.new_user_journey_enrollment
    WHERE user_id = p_user_id;

    IF v_enrollment.user_id IS NULL THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'not_enrolled');
    END IF;

    v_window_start := COALESCE(p_window_start, v_enrollment.journey_started_at);
    v_window_end   := COALESCE(p_window_end,   LEAST(v_enrollment.journey_ends_at, now()));

    -- Tail of events (most recent 500 — enough context, bounded payload)
    SELECT COALESCE(jsonb_agg(row_to_json(e) ORDER BY e.occurred_at), '[]'::jsonb)
    INTO v_events
    FROM (
        SELECT id, session_id, occurred_at, event_type, screen, detail, payload, is_error, severity
        FROM public.new_user_journey_events
        WHERE user_id = p_user_id
          AND occurred_at BETWEEN v_window_start AND v_window_end
        ORDER BY occurred_at DESC
        LIMIT 500
    ) e;

    SELECT COALESCE(jsonb_agg(row_to_json(s) ORDER BY s.started_at), '[]'::jsonb)
    INTO v_sessions
    FROM (
        SELECT id, session_id, started_at, ended_at, duration_seconds, app_version,
               build_number, device_model, ios_version, network_type,
               entry_screen, last_screen, error_count, crash_count,
               screen_view_count, tap_count
        FROM public.new_user_journey_sessions
        WHERE user_id = p_user_id
          AND started_at BETWEEN v_window_start AND v_window_end
        ORDER BY started_at ASC
    ) s;

    -- Onboarding funnel: sequence of funnel events
    SELECT COALESCE(jsonb_agg(row_to_json(f) ORDER BY f.occurred_at), '[]'::jsonb)
    INTO v_funnel
    FROM (
        SELECT occurred_at, payload->>'funnel' AS funnel,
               payload->>'step' AS step, payload->>'step_index' AS step_index,
               payload
        FROM public.new_user_journey_events
        WHERE user_id = p_user_id
          AND event_type = 'funnel'
          AND occurred_at BETWEEN v_window_start AND v_window_end
        ORDER BY occurred_at ASC
    ) f;

    -- Screen visit histogram
    SELECT COALESCE(jsonb_object_agg(screen, cnt), '{}'::jsonb)
    INTO v_screens
    FROM (
        SELECT screen, COUNT(*)::INT AS cnt
        FROM public.new_user_journey_events
        WHERE user_id = p_user_id
          AND event_type = 'screen'
          AND screen IS NOT NULL
          AND occurred_at BETWEEN v_window_start AND v_window_end
        GROUP BY screen
        ORDER BY cnt DESC
        LIMIT 50
    ) sc;

    -- Error rollup: top 25 errors with counts
    SELECT COALESCE(jsonb_agg(row_to_json(er) ORDER BY er.cnt DESC), '[]'::jsonb)
    INTO v_errors
    FROM (
        SELECT detail, COUNT(*)::INT AS cnt, MAX(occurred_at) AS last_seen,
               MIN(occurred_at) AS first_seen,
               ARRAY_AGG(DISTINCT screen) FILTER (WHERE screen IS NOT NULL) AS screens
        FROM public.new_user_journey_events
        WHERE user_id = p_user_id
          AND is_error = TRUE
          AND occurred_at BETWEEN v_window_start AND v_window_end
        GROUP BY detail
        ORDER BY COUNT(*) DESC
        LIMIT 25
    ) er;

    -- Cross-table behavioral counters (workouts/meals/friends from canonical sources)
    SELECT COUNT(*)::INT INTO v_workouts
    FROM public.workout_history
    WHERE user_id = p_user_id
      AND created_at BETWEEN v_window_start AND v_window_end;

    SELECT COUNT(*)::INT INTO v_meals
    FROM public.meal_logs
    WHERE user_id = p_user_id
      AND created_at BETWEEN v_window_start AND v_window_end;

    BEGIN
        SELECT COUNT(*)::INT INTO v_friends
        FROM public.friendships
        WHERE (requester_id = p_user_id OR addressee_id = p_user_id)
          AND status = 'accepted'
          AND created_at BETWEEN v_window_start AND v_window_end;
    EXCEPTION WHEN OTHERS THEN
        v_friends := 0;
    END;

    SELECT COUNT(*)::INT INTO v_paywall_views
    FROM public.new_user_journey_events
    WHERE user_id = p_user_id
      AND event_type = 'paywall'
      AND payload->>'action' = 'view'
      AND occurred_at BETWEEN v_window_start AND v_window_end;

    RETURN jsonb_build_object(
        'success',         TRUE,
        'enrollment',      row_to_json(v_enrollment),
        'window_start',    v_window_start,
        'window_end',      v_window_end,
        'events',          v_events,
        'sessions',        v_sessions,
        'funnel',          v_funnel,
        'screens',         v_screens,
        'errors',          v_errors,
        'behavior',        jsonb_build_object(
            'workouts_logged',  v_workouts,
            'meals_logged',     v_meals,
            'friends_added',    v_friends,
            'paywall_views',    v_paywall_views
        )
    );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_new_user_journey_report_data(UUID, TIMESTAMPTZ, TIMESTAMPTZ) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_new_user_journey_report_data(UUID, TIMESTAMPTZ, TIMESTAMPTZ) TO service_role;

-- ═══════════════════════════════════════════════════════════════════════════
-- 11. RPC: cleanup_new_user_journey_data() — retention drain
-- ═══════════════════════════════════════════════════════════════════════════
-- Drops events older than 30 days from journey_started_at (keeps reports
-- forever — they're the deliverable).

DROP FUNCTION IF EXISTS public.cleanup_new_user_journey_data();
CREATE OR REPLACE FUNCTION public.cleanup_new_user_journey_data()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_events_deleted INT;
    v_sessions_deleted INT;
BEGIN
    DELETE FROM public.new_user_journey_events
    WHERE occurred_at < now() - INTERVAL '30 days';
    GET DIAGNOSTICS v_events_deleted = ROW_COUNT;

    DELETE FROM public.new_user_journey_sessions
    WHERE started_at < now() - INTERVAL '30 days';
    GET DIAGNOSTICS v_sessions_deleted = ROW_COUNT;

    RETURN jsonb_build_object(
        'success',          TRUE,
        'events_deleted',   v_events_deleted,
        'sessions_deleted', v_sessions_deleted
    );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.cleanup_new_user_journey_data() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.cleanup_new_user_journey_data() TO service_role;

-- ═══════════════════════════════════════════════════════════════════════════
-- 12. RPC: trigger_generate_new_user_reports() — pg_cron wrapper
-- ═══════════════════════════════════════════════════════════════════════════
-- Mirrors the canonical pattern from trigger_triage_bugs / trigger_analyze_quality_workout:
-- counts pending checkpoint rows first, fast-path-skips on empty queue,
-- otherwise fires `net.http_post` to the edge function with x-cron-key.

DROP FUNCTION IF EXISTS public.trigger_generate_new_user_reports();
CREATE OR REPLACE FUNCTION public.trigger_generate_new_user_reports()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_pending INT;
    v_supabase_url TEXT;
    v_service_key TEXT;
    v_cron_key TEXT;
    v_request_id BIGINT;
BEGIN
    SELECT COUNT(*) INTO v_pending
    FROM public.new_user_journey_enrollment
    WHERE (d1_report_due_at <= now() AND d1_report_generated = FALSE)
       OR (d2_report_due_at <= now() AND d2_report_generated = FALSE)
       OR (d3_report_due_at <= now() AND d3_report_generated = FALSE)
       OR (final_report_due_at <= now() AND final_report_generated = FALSE);

    IF v_pending = 0 THEN
        RETURN jsonb_build_object('success', TRUE, 'skipped', TRUE, 'pending', 0);
    END IF;

    -- Read internal_config for env values (if present); allow no-op if not set.
    BEGIN
        SELECT value INTO v_supabase_url FROM public.internal_config WHERE key = 'supabase_url';
        SELECT value INTO v_service_key  FROM public.internal_config WHERE key = 'service_role_key';
        SELECT value INTO v_cron_key     FROM public.internal_config WHERE key = 'cron_key';
    EXCEPTION WHEN OTHERS THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'internal_config_missing', 'pending', v_pending);
    END;

    IF v_supabase_url IS NULL OR v_service_key IS NULL THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'config_incomplete', 'pending', v_pending);
    END IF;

    SELECT net.http_post(
        url     := v_supabase_url || '/functions/v1/generate-new-user-report',
        headers := jsonb_build_object(
            'Content-Type',  'application/json',
            'Authorization', 'Bearer ' || v_service_key,
            'x-cron-key',    COALESCE(v_cron_key, '')
        ),
        body    := jsonb_build_object('source', 'cron', 'pending', v_pending)
    ) INTO v_request_id;

    RETURN jsonb_build_object('success', TRUE, 'request_id', v_request_id, 'pending', v_pending);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.trigger_generate_new_user_reports() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.trigger_generate_new_user_reports() TO service_role;

-- ═══════════════════════════════════════════════════════════════════════════
-- 13. CRON SCHEDULES
-- ═══════════════════════════════════════════════════════════════════════════

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
        -- Idempotent unschedule
        BEGIN
            PERFORM cron.unschedule('generate-new-user-reports-hourly');
        EXCEPTION WHEN OTHERS THEN NULL; END;
        BEGIN
            PERFORM cron.unschedule('cleanup-new-user-journey-nightly');
        EXCEPTION WHEN OTHERS THEN NULL; END;

        PERFORM cron.schedule(
            'generate-new-user-reports-hourly',
            '5 * * * *',
            'SELECT public.trigger_generate_new_user_reports();'
        );

        PERFORM cron.schedule(
            'cleanup-new-user-journey-nightly',
            '30 4 * * *',
            'SELECT public.cleanup_new_user_journey_data();'
        );

        RAISE NOTICE '✅ pg_cron schedules registered: generate-new-user-reports-hourly + cleanup-new-user-journey-nightly';
    ELSE
        RAISE NOTICE '⚠️ pg_cron not installed — schedule manually after extension enable.';
    END IF;
END$$;

-- ═══════════════════════════════════════════════════════════════════════════
-- 14. TRAILING FAIL-LOUD AUDIT
-- ═══════════════════════════════════════════════════════════════════════════

DO $$
DECLARE
    v_missing_table TEXT;
    v_missing_func  TEXT;
BEGIN
    -- Tables
    FOR v_missing_table IN
        SELECT t FROM (VALUES
            ('new_user_journey_enrollment'),
            ('new_user_journey_sessions'),
            ('new_user_journey_events'),
            ('new_user_journey_reports')
        ) AS x(t)
        WHERE NOT EXISTS (
            SELECT 1 FROM information_schema.tables
            WHERE table_schema = 'public' AND table_name = x.t
        )
    LOOP
        RAISE EXCEPTION 'AUDIT FAIL — table % missing', v_missing_table;
    END LOOP;

    -- RPCs
    FOR v_missing_func IN
        SELECT f FROM (VALUES
            ('enroll_new_user_journey'),
            ('is_in_new_user_journey'),
            ('record_new_user_event'),
            ('record_new_user_events_batch'),
            ('record_new_user_session_start'),
            ('record_new_user_session_end'),
            ('get_new_user_journey_report_data'),
            ('cleanup_new_user_journey_data'),
            ('trigger_generate_new_user_reports')
        ) AS x(f)
        WHERE NOT EXISTS (
            SELECT 1 FROM pg_proc p JOIN pg_namespace n ON p.pronamespace = n.oid
            WHERE n.nspname = 'public' AND p.proname = x.f
        )
    LOOP
        RAISE EXCEPTION 'AUDIT FAIL — function % missing', v_missing_func;
    END LOOP;

    -- RLS
    IF NOT EXISTS (
        SELECT 1 FROM pg_class c JOIN pg_namespace n ON c.relnamespace = n.oid
        WHERE n.nspname = 'public' AND c.relname = 'new_user_journey_enrollment' AND c.relrowsecurity = TRUE
    ) THEN
        RAISE EXCEPTION 'AUDIT FAIL — RLS not enabled on new_user_journey_enrollment';
    END IF;

    RAISE NOTICE '✅ NEW USER JOURNEY TRACKING (#162) DEPLOYED';
END$$;

COMMIT;
