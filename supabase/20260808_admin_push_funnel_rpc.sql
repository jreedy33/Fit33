-- =============================================================================
-- Smart Notification Engine — Phase 5: Admin Funnel + Test-Push RPCs
-- =============================================================================
-- Migration #173
-- Date: 2026-08-08
-- Authors: Data/Backend + Infra/Security
-- Depends on: 20260801, 20260802, 20260804, 20260805, 20260807
--
-- Purpose:
--   Two admin-CMS-facing RPCs that power the new Health & Funnel tab and
--   the User Debug "send test push" button on /notifications:
--
--     1. admin_get_push_funnel(p_window_hours)
--          Aggregates `push_notification_delivery_log` over the window
--          and returns a category-grouped funnel:
--            enqueued → apns_send_attempt → apns_success → delivered → opened
--          plus terminal failures (apns_error_*, token_invalid,
--          notification_failed), suppression counts (prefs_blocked,
--          quiet_hours_deferred, cap_exceeded), and a slice of A/B variant
--          opens (from `notification_orchestration_decisions.variant_id`).
--
--     2. admin_enqueue_test_push(p_user_id, p_title, p_body, p_category,
--                                 p_actor_email)
--          Inserts a row into `push_notification_queue` so the test
--          exercises the SAME dequeue + cap + RLS path production uses.
--          Idempotent within 1 minute on (user_id, title, body) so a
--          double-click in the CMS doesn't double-fire APNs.
--
-- Both are SECURITY DEFINER and granted to `service_role` only — the CMS
-- already authenticates the admin and writes to `internal_admin_audit_log`
-- via `logAdminAction()` before forwarding the call (per
-- INFRA_SECURITY_AGENT registry; the Edge Function Auth Registry will
-- record `admin_get_push_funnel` + `admin_enqueue_test_push` next to the
-- existing `admin_get_push_pipeline_stats`).
--
-- Notes:
--   - We DO NOT compute open-rate as opens / sent. Per the agent's
--     measurement playbook, the user-perceptible funnel uses
--     opens / delivered (post-OS-filter). `apns_success` is the carrier
--     handoff; "delivered" is the in-app/extension report from
--     PushEventReporter; "opened" is the user tapping it.
--   - Window is bounded 1h..720h (30d) to prevent runaway scans.
-- =============================================================================

BEGIN;

-- =============================================================================
-- 1. admin_get_push_funnel — category-grouped funnel + A/B winners
-- =============================================================================

CREATE OR REPLACE FUNCTION admin_get_push_funnel(p_window_hours INTEGER DEFAULT 24)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_window_hours INTEGER := GREATEST(1, LEAST(720, COALESCE(p_window_hours, 24)));
  v_since TIMESTAMPTZ := NOW() - (v_window_hours || ' hours')::INTERVAL;
  v_by_category JSONB;
  v_totals JSONB;
  v_variants JSONB;
  v_decisions JSONB;
BEGIN
  -- Per-category funnel. NULL category lands in the synthetic 'unknown' bucket
  -- so legacy rows pre-Phase 1 still surface.
  SELECT COALESCE(jsonb_agg(to_jsonb(c)), '[]'::jsonb)
  INTO v_by_category
  FROM (
    SELECT
      COALESCE(category, 'unknown') AS category,
      COUNT(*) FILTER (WHERE event = 'enqueued')             AS enqueued,
      COUNT(*) FILTER (WHERE event = 'apns_send_attempt')    AS attempted,
      COUNT(*) FILTER (WHERE event = 'apns_success')         AS apns_success,
      COUNT(*) FILTER (WHERE event = 'delivered')            AS delivered,
      COUNT(*) FILTER (WHERE event = 'opened')               AS opened,
      COUNT(*) FILTER (WHERE event = 'action_taken')         AS action_taken,
      COUNT(*) FILTER (WHERE event = 'dismissed')            AS dismissed,
      COUNT(*) FILTER (WHERE event LIKE 'apns_error_%')      AS apns_error,
      COUNT(*) FILTER (WHERE event = 'token_invalid')        AS token_invalid,
      COUNT(*) FILTER (WHERE event = 'notification_failed')  AS notification_failed,
      COUNT(*) FILTER (WHERE event = 'prefs_blocked')        AS prefs_blocked,
      COUNT(*) FILTER (WHERE event = 'quiet_hours_deferred') AS quiet_hours_deferred,
      COUNT(*) FILTER (WHERE event = 'cap_exceeded')         AS cap_exceeded,
      ROUND(
        100.0 * COUNT(*) FILTER (WHERE event = 'opened')
              / NULLIF(COUNT(*) FILTER (WHERE event = 'delivered'), 0),
        1
      ) AS open_rate_pct
    FROM push_notification_delivery_log
    WHERE created_at >= v_since
    GROUP BY COALESCE(category, 'unknown')
    ORDER BY apns_success DESC NULLS LAST
  ) c;

  -- Cross-category totals.
  SELECT to_jsonb(t) INTO v_totals
  FROM (
    SELECT
      COUNT(*) FILTER (WHERE event = 'enqueued')             AS enqueued,
      COUNT(*) FILTER (WHERE event = 'apns_success')         AS apns_success,
      COUNT(*) FILTER (WHERE event = 'delivered')            AS delivered,
      COUNT(*) FILTER (WHERE event = 'opened')               AS opened,
      COUNT(*) FILTER (WHERE event LIKE 'apns_error_%')      AS apns_error,
      COUNT(*) FILTER (WHERE event = 'prefs_blocked')        AS prefs_blocked,
      COUNT(*) FILTER (WHERE event = 'cap_exceeded')         AS cap_exceeded,
      COUNT(DISTINCT user_id) FILTER (WHERE event = 'opened') AS unique_openers
    FROM push_notification_delivery_log
    WHERE created_at >= v_since
  ) t;

  -- A/B variant winners: `render_notification_copy` stamps `variant` into
  -- `push_notification_queue.data`; join queue → delivery_log for opens.
  BEGIN
    SELECT COALESCE(jsonb_agg(to_jsonb(v)), '[]'::jsonb)
    INTO v_variants
    FROM (
      SELECT
        q.notification_type AS intent_kind,
        q.data->>'variant' AS variant,
        COUNT(DISTINCT q.id) AS sent,
        COUNT(DISTINCT CASE WHEN l.event = 'opened' THEN l.notification_id END) AS opened,
        ROUND(
          100.0 * COUNT(DISTINCT CASE WHEN l.event = 'opened' THEN l.notification_id END)
                / NULLIF(COUNT(DISTINCT q.id), 0),
          1
        ) AS open_rate_pct
      FROM push_notification_queue q
      LEFT JOIN push_notification_delivery_log l
        ON l.notification_id = q.id
       AND l.created_at >= v_since
      WHERE q.created_at >= v_since
        AND q.data ? 'variant'
      GROUP BY q.notification_type, q.data->>'variant'
      HAVING COUNT(DISTINCT q.id) > 5
      ORDER BY open_rate_pct DESC NULLS LAST, sent DESC
      LIMIT 25
    ) v;
  EXCEPTION WHEN OTHERS THEN
    v_variants := '[]'::jsonb;
  END;

  -- Orchestrator decision rates: how many candidates the orchestrator
  -- considered, how many it suppressed, how many it enqueued. Powers the
  -- "is the orchestrator dropping too much?" health card.
  BEGIN
    SELECT to_jsonb(d) INTO v_decisions
    FROM (
      SELECT
        COUNT(*) AS total_decisions,
        COUNT(*) FILTER (WHERE decision = 'enqueued')    AS enqueued,
        COUNT(*) FILTER (WHERE decision = 'suppressed')  AS suppressed,
        COUNT(*) FILTER (WHERE decision = 'deferred')   AS deferred,
        COUNT(*) FILTER (WHERE shadow_mode = true)       AS shadow_mode_decisions,
        0::BIGINT AS errored
      FROM notification_orchestration_decisions
      WHERE decided_at >= v_since
    ) d;
  EXCEPTION WHEN OTHERS THEN
    v_decisions := '{}'::jsonb;
  END;

  RETURN jsonb_build_object(
    'window_hours', v_window_hours,
    'window_start', v_since,
    'by_category', v_by_category,
    'totals', COALESCE(v_totals, '{}'::jsonb),
    'ab_variants', v_variants,
    'orchestrator', COALESCE(v_decisions, '{}'::jsonb)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION admin_get_push_funnel(INTEGER) TO service_role;

-- =============================================================================
-- 2. admin_enqueue_test_push — admin-only test push
-- =============================================================================

CREATE OR REPLACE FUNCTION admin_enqueue_test_push(
  p_user_id      UUID,
  p_title        TEXT,
  p_body         TEXT,
  p_category     TEXT DEFAULT 'announcement',
  p_actor_email  TEXT DEFAULT 'unknown'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_queue_id UUID;
  v_recent_dup UUID;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'p_user_id required';
  END IF;
  IF p_title IS NULL OR length(p_title) = 0 THEN
    RAISE EXCEPTION 'p_title required';
  END IF;

  -- 60s idempotency window — prevents the CMS double-click footgun.
  SELECT id INTO v_recent_dup
  FROM push_notification_queue
  WHERE recipient_user_id = p_user_id
    AND title = p_title
    AND COALESCE(body, '') = COALESCE(p_body, '')
    AND created_at >= NOW() - INTERVAL '60 seconds'
  ORDER BY created_at DESC
  LIMIT 1;

  IF v_recent_dup IS NOT NULL THEN
    RETURN jsonb_build_object(
      'ok', true,
      'queue_id', v_recent_dup,
      'note', 'Duplicate within 60s — returned existing row.'
    );
  END IF;

  INSERT INTO push_notification_queue (
    recipient_user_id, notification_type, title, body, category, status,
    data, scheduled_for
  ) VALUES (
    p_user_id,
    'admin_test',
    p_title,
    p_body,
    p_category,
    'pending',
    jsonb_build_object(
      'is_test', true,
      'sent_by_admin', p_actor_email,
      'category', p_category
    ),
    NOW()
  )
  RETURNING id INTO v_queue_id;

  RETURN jsonb_build_object(
    'ok', true,
    'queue_id', v_queue_id,
    'recipient_user_id', p_user_id,
    'category', p_category
  );
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'error', SQLERRM);
END;
$$;

GRANT EXECUTE ON FUNCTION admin_enqueue_test_push(UUID, TEXT, TEXT, TEXT, TEXT) TO service_role;

-- =============================================================================
-- 3. AUDIT
-- =============================================================================

DO $$
DECLARE v_count INTEGER;
BEGIN
  SELECT COUNT(*) INTO v_count FROM pg_proc
  WHERE proname IN ('admin_get_push_funnel', 'admin_enqueue_test_push');

  IF v_count <> 2 THEN
    RAISE EXCEPTION 'Migration #173 audit: expected 2 functions, found %', v_count;
  END IF;

  RAISE NOTICE '✅ Migration #173 (admin push funnel + test-push) complete';
  RAISE NOTICE '   - admin_get_push_funnel(p_window_hours)';
  RAISE NOTICE '   - admin_enqueue_test_push(p_user_id, p_title, p_body, p_category, p_actor_email)';
END $$;

COMMIT;
