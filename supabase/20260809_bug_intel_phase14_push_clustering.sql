-- =============================================================================
-- Bug Intelligence — Phase 14: APNs / Push Failure Clustering
-- =============================================================================
-- Migration #174
-- Date: 2026-08-09
-- Authors: Bug Intelligence + Infra/Security
-- Depends on: 20260427 (bug_intelligence base), 20260428 (reports),
--             20260714 (Phase 13 classifier), 20260801 (push categories),
--             20260805 (intent producers), 20260808 (admin funnel rpc)
--
-- Why this migration exists:
--
--   The bug-intel pipeline was originally built for `dev_session_logs` +
--   `crash_reports`. Push delivery failures live in a parallel table
--   (`push_notification_delivery_log`) and never surfaced in the bug-intel
--   inbox — meaning a 410 token-gone storm or a 503 APNs outage would
--   silently degrade engagement without ever showing up in the
--   `bug-intelligence` CMS tab.
--
--   This migration fixes the gap with three pieces:
--
--   (1) Extends `bug_intel_classify_error()` to recognize APNs-shaped
--       inputs. The classifier already understands `http:NNN` so we add
--       a new precedence layer: when the message contains the synthetic
--       prefix `apns-status:NNN` we route it to a stable
--       `apns:NNN` class. The orchestrator + send-push-notification
--       prepend that prefix when they call into bug-intel via the
--       upcoming integration in #2 below. (We deliberately do NOT touch
--       call-site precedence for non-push paths.)
--
--   (2) Adds `bug_intel_cluster_push_failures()` SECURITY DEFINER
--       function + hourly cron job that scans the last hour of
--       `push_notification_delivery_log` for failure clusters
--       (apns_error_*, token_invalid, notification_failed) grouped by
--       (event, category). When a cluster crosses the threshold (5+
--       failures from 3+ distinct users in 60 minutes) the function
--       upserts a `bug_intelligence_fingerprints` row with a stable
--       fingerprint of the form `push:apns:<event>:<category>` and
--       records the cluster in `bug_intelligence_daily_rollup`.
--       Routing is fixed: `assigned_agent = 'infra-security'` because
--       APNs and silent-push failures are owned by that agent per
--       INFRA_SECURITY_AGENT.md invariant 7.
--
--   (3) Documents a stable fingerprint signature so the same cluster
--       across multiple cron runs resolves to ONE row (not N daily
--       rows). Phase 14 invariant: `push:apns:<event>:<category>` is
--       reserved for synthetic push fingerprints; nothing else may
--       use the `push:` prefix.
--
-- What this does NOT do:
--   - Does NOT trigger Claude triage. The triage edge fn picks up new
--     fingerprints on its own */15 cycle. We just plant the row.
--   - Does NOT delete or modify successful pushes. Read-only on the
--     `push_notification_delivery_log` source.
--   - Does NOT classify silent pushes that succeed but produce no
--     downstream `delivered` event — that's a different signal worth
--     monitoring, but it's noise-prone and out of scope for this pass.
-- =============================================================================

BEGIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- A. Extend bug_intel_classify_error to recognize APNs-shaped messages
-- ─────────────────────────────────────────────────────────────────────────────
--
-- Precedence (NEW):
--   pg_code (passed) > pg_code (extracted) > apns-status:NNN > http > nsurl > heuristic
--
-- The `apns-status:NNN` prefix is a synthetic marker the push edge
-- functions use when emitting an error that originated from APNs (so it
-- doesn't get misclassified as a generic HTTP response). Reproduces the
-- pattern used for PostgrestError pg_code extraction in Phase 13.

CREATE OR REPLACE FUNCTION public.bug_intel_classify_error(
    p_pg_code     TEXT,
    p_http_status INT,
    p_nsurl_code  INT,
    p_message     TEXT
) RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    v_extracted     TEXT;
    v_apns_extract  TEXT;
BEGIN
    -- 1. Explicit pg_code (DiagnosticContext path) wins.
    IF p_pg_code IS NOT NULL AND p_pg_code <> '' THEN
        RETURN 'pg:' || p_pg_code;
    END IF;

    -- 2. Phase 13: regex-extract pg_code from raw message.
    v_extracted := public.bug_intel_extract_pg_code(p_message);
    IF v_extracted IS NOT NULL THEN
        RETURN 'pg:' || v_extracted;
    END IF;

    -- 3. Phase 14: APNs-shaped marker `apns-status:NNN`. Captured BEFORE
    --    generic http handling so our synthetic markers don't collide
    --    with non-push HTTP errors that legitimately surface as
    --    `http:410` or `http:503`.
    IF p_message IS NOT NULL THEN
        v_apns_extract := substring(p_message FROM 'apns-status:([0-9]{3})');
        IF v_apns_extract IS NOT NULL THEN
            RETURN 'apns:' || v_apns_extract;
        END IF;
    END IF;

    -- 4. http_status fallback.
    IF p_http_status IS NOT NULL AND p_http_status > 0 THEN
        RETURN 'http:' || p_http_status;
    END IF;

    -- 5. nsurl fallback.
    IF p_nsurl_code IS NOT NULL THEN
        RETURN 'nsurl:' || p_nsurl_code;
    END IF;

    -- 6. Message heuristics — preserved verbatim from Phase 13.
    IF p_message IS NULL OR p_message = '' THEN
        RETURN 'unknown';
    END IF;

    IF p_message ILIKE '%jwt expired%'         OR p_message ILIKE '%invalid jwt%'         THEN RETURN 'auth:expired'; END IF;
    IF p_message ILIKE '%cancelled%'           OR p_message LIKE  '%-999%'                THEN RETURN 'cancelled'; END IF;
    IF p_message ILIKE '%not connected to the internet%' OR p_message LIKE '%-1009%'      THEN RETURN 'offline'; END IF;
    IF p_message ILIKE '%network connection was lost%'   OR p_message LIKE '%-1005%'      THEN RETURN 'network_lost'; END IF;
    IF p_message ILIKE '%timeout%'             OR p_message LIKE  '%-1001%'               THEN RETURN 'timeout'; END IF;
    IF p_message ILIKE '%row-level security%'  OR p_message ILIKE '%permission denied%'   THEN RETURN 'rls'; END IF;
    IF p_message ILIKE '%duplicate key%'                                                  THEN RETURN 'pg:23505'; END IF;
    IF p_message ILIKE '%violates check constraint%'                                      THEN RETURN 'pg:23514'; END IF;
    IF p_message ILIKE '%violates not-null constraint%'                                   THEN RETURN 'pg:23502'; END IF;
    IF p_message ILIKE '%uuid = text%'         OR p_message ILIKE '%operator does not exist%' THEN RETURN 'pg:42883'; END IF;
    IF p_message ILIKE '%could not find the function%' OR p_message ILIKE '%PGRST202%'    THEN RETURN 'pgrest:202'; END IF;
    IF p_message ILIKE '%deadlock detected%'   OR p_message ILIKE '%40P01%'               THEN RETURN 'pg:40P01'; END IF;
    IF p_message ILIKE '%no unique or exclusion constraint matching the ON CONFLICT%'     THEN RETURN 'pg:42P10'; END IF;

    -- Phase 14: free-text APNs heuristics (legacy senders that didn't
    -- prepend `apns-status:`). Conservative — only matches obvious
    -- BadDeviceToken / TooManyRequests / ServiceUnavailable wording.
    IF p_message ILIKE '%BadDeviceToken%' OR p_message ILIKE '%Unregistered%'             THEN RETURN 'apns:410'; END IF;
    IF p_message ILIKE '%TooManyRequests%'                                                THEN RETURN 'apns:429'; END IF;
    IF p_message ILIKE '%ServiceUnavailable%'                                             THEN RETURN 'apns:503'; END IF;
    IF p_message ILIKE '%PayloadTooLarge%'                                                THEN RETURN 'apns:413'; END IF;

    RETURN 'unknown';
END;
$$;

COMMENT ON FUNCTION public.bug_intel_classify_error(TEXT, INT, INT, TEXT) IS
    'Phase 14 (2026-08-09) — extends Phase 13 with APNs marker `apns-status:NNN` + four free-text heuristics (BadDeviceToken→apns:410, TooManyRequests→apns:429, ServiceUnavailable→apns:503, PayloadTooLarge→apns:413). Precedence: pg_code (passed) > pg_code (extracted) > apns-status > http > nsurl > heuristic.';

-- ─────────────────────────────────────────────────────────────────────────────
-- B. Cluster detector — runs hourly, plants bug-intel rows on outage
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.bug_intel_cluster_push_failures()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_clusters_created INTEGER := 0;
  v_row RECORD;
  v_fingerprint TEXT;
  v_normalized_message TEXT;
  v_sample_message TEXT;
  v_event_class TEXT;
  v_today DATE := CURRENT_DATE;
BEGIN
  -- Defensive: bail when bug-intel tables aren't deployed yet.
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_name = 'bug_intelligence_fingerprints'
  ) THEN
    RETURN 0;
  END IF;

  -- Walk failure clusters in the last 60 min. Threshold: 5+ events from
  -- 3+ distinct users in the same (event, category). Tuned conservative
  -- to avoid noise; can be lowered once we have baseline metrics.
  FOR v_row IN
    SELECT
      l.event,
      COALESCE(l.category, 'unknown') AS category,
      COUNT(*) AS event_count,
      COUNT(DISTINCT l.user_id) AS user_count,
      MAX(l.created_at) AS last_seen,
      MIN(l.created_at) AS first_seen,
      (ARRAY_AGG(l.detail::TEXT ORDER BY l.created_at DESC))[1] AS sample_detail
    FROM push_notification_delivery_log l
    WHERE l.created_at >= NOW() - INTERVAL '60 minutes'
      AND (
        l.event LIKE 'apns_error_%'
        OR l.event LIKE 'silent_apns_error_%'
        OR l.event = 'token_invalid'
        OR l.event = 'notification_failed'
      )
    GROUP BY l.event, COALESCE(l.category, 'unknown')
    HAVING COUNT(*) >= 5 AND COUNT(DISTINCT l.user_id) >= 3
  LOOP
    -- Normalize event name to a stable bug class. apns_error_410 →
    -- apns:410. silent_apns_error_503 → apns:503 (silent variant lives
    -- in the detail blob; the carrier protocol error is the same).
    v_event_class := CASE
      WHEN v_row.event LIKE 'apns_error_%'        THEN 'apns:' || substring(v_row.event FROM 'apns_error_([0-9]+)')
      WHEN v_row.event LIKE 'silent_apns_error_%' THEN 'apns:' || substring(v_row.event FROM 'silent_apns_error_([0-9]+)')
      WHEN v_row.event = 'token_invalid'          THEN 'apns:410'  -- iOS-side classification of a 410
      WHEN v_row.event = 'notification_failed'    THEN 'push:notification_failed'
      ELSE 'push:' || v_row.event
    END;

    -- Stable fingerprint — same outage produces the same row across
    -- repeated cron runs (idempotent ON CONFLICT update below).
    v_fingerprint := 'push:' || v_event_class || ':' || v_row.category;

    v_normalized_message := format(
      'Push delivery cluster: %s in category=%s — %s events from %s users in last 60 min',
      v_event_class, v_row.category, v_row.event_count, v_row.user_count
    );

    v_sample_message := COALESCE(v_row.sample_detail, '(no detail)');

    INSERT INTO bug_intelligence_fingerprints (
      fingerprint, source, normalized_message, sample_message,
      error_domain, first_seen_at, last_seen_at,
      occurrence_count, unique_user_count,
      affected_screens, assigned_agent, status
    ) VALUES (
      v_fingerprint,
      'push',
      v_normalized_message,
      v_sample_message,
      v_event_class,
      v_row.first_seen,
      v_row.last_seen,
      v_row.event_count,
      v_row.user_count,
      ARRAY['(server-side: push delivery)'],
      'infra-security',
      'new'
    )
    ON CONFLICT (fingerprint) DO UPDATE SET
      last_seen_at        = GREATEST(bug_intelligence_fingerprints.last_seen_at, EXCLUDED.last_seen_at),
      occurrence_count    = bug_intelligence_fingerprints.occurrence_count + EXCLUDED.occurrence_count,
      unique_user_count   = GREATEST(bug_intelligence_fingerprints.unique_user_count, EXCLUDED.unique_user_count),
      normalized_message  = EXCLUDED.normalized_message,
      sample_message      = EXCLUDED.sample_message,
      updated_at          = NOW(),
      -- Re-open if it was previously resolved but is firing again.
      status              = CASE
        WHEN bug_intelligence_fingerprints.status = 'resolved' THEN 'new'
        ELSE bug_intelligence_fingerprints.status
      END;

    -- Plant a daily-rollup row so the trends view sees this cluster.
    BEGIN
      INSERT INTO bug_intelligence_daily_rollup (
        fingerprint, day, screen, app_version,
        occurrence_count, unique_user_count
      ) VALUES (
        v_fingerprint, v_today, '(server-side: push delivery)', '',
        v_row.event_count, v_row.user_count
      )
      ON CONFLICT DO NOTHING;
    EXCEPTION WHEN OTHERS THEN
      NULL;  -- rollup table column drift; cluster row already planted.
    END;

    v_clusters_created := v_clusters_created + 1;
  END LOOP;

  RETURN v_clusters_created;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'bug_intel_cluster_push_failures threw: %', SQLERRM;
  RETURN 0;
END;
$$;

COMMENT ON FUNCTION public.bug_intel_cluster_push_failures() IS
    'Phase 14 — scans push_notification_delivery_log for APNs failure clusters every hour and plants bug-intel rows. assigned_agent = ''infra-security'' (INFRA_SECURITY_AGENT.md invariant 7).';

GRANT EXECUTE ON FUNCTION public.bug_intel_cluster_push_failures() TO service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- C. Schedule — hourly, offset to :17 to avoid colliding with other crons
-- ─────────────────────────────────────────────────────────────────────────────

DO $$
DECLARE jobname TEXT;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    RAISE NOTICE 'pg_cron not installed; skip scheduling bug-intel push clustering';
    RETURN;
  END IF;

  FOR jobname IN
    SELECT j.jobname FROM cron.job j
    WHERE j.jobname = 'bug-intel-cluster-push-failures'
  LOOP
    PERFORM cron.unschedule(jobname);
  END LOOP;

  PERFORM cron.schedule(
    'bug-intel-cluster-push-failures',
    '17 * * * *',
    $cron$SELECT bug_intel_cluster_push_failures();$cron$
  );
END $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- D. AUDIT
-- ─────────────────────────────────────────────────────────────────────────────

DO $$
DECLARE
  v_classifier_signature TEXT;
  v_test_apns_marker TEXT;
  v_test_apns_text TEXT;
BEGIN
  v_classifier_signature := public.bug_intel_classify_error(NULL, NULL, NULL, NULL);
  IF v_classifier_signature <> 'unknown' THEN
    RAISE EXCEPTION '[20260809] classifier should return ''unknown'' for empty input, got %', v_classifier_signature;
  END IF;

  v_test_apns_marker := public.bug_intel_classify_error(NULL, NULL, NULL,
    'send_push_notification: error apns-status:410 BadDeviceToken');
  IF v_test_apns_marker <> 'apns:410' THEN
    RAISE EXCEPTION '[20260809] expected apns:410 for synthetic marker, got %', v_test_apns_marker;
  END IF;

  v_test_apns_text := public.bug_intel_classify_error(NULL, NULL, NULL,
    '{"reason":"BadDeviceToken"}');
  IF v_test_apns_text <> 'apns:410' THEN
    RAISE EXCEPTION '[20260809] expected apns:410 for free-text BadDeviceToken, got %', v_test_apns_text;
  END IF;

  RAISE NOTICE '✅ Migration #174 (bug-intel push clustering) complete';
  RAISE NOTICE '   - bug_intel_classify_error extended with apns:NNN class';
  RAISE NOTICE '   - bug_intel_cluster_push_failures() runs hourly @ :17';
  RAISE NOTICE '   - clusters auto-route to infra-security agent';
END $$;

COMMIT;
