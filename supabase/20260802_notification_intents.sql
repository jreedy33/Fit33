-- =============================================================================
-- Smart Notification Engine — Phase 2: Intents + Orchestration Decisions
-- =============================================================================
-- Migration #169
-- Date: 2026-08-02
-- Authors: Infra/Security + Data/Backend
-- Depends on: 20260801_notification_categories_and_caps.sql (#168)
--
-- Purpose:
--
--   notification_intents — producer-side abstraction. Many SQL triggers
--     and cron jobs (Phase 3) INSERT INTO notification_intents instead of
--     pushing directly to push_notification_queue. The orchestrator picks
--     up pending intents, applies prefs/caps/timing, scores them, and
--     enqueues the winners. This decoupling lets us ship "should we send
--     this NOW?" logic in ONE place instead of duplicating it across
--     every producer.
--
--   notification_orchestration_decisions — forensic log of every
--     decision the orchestrator makes (delivered / suppressed / deferred)
--     with the reason. Drives the CMS Health & Funnel tab and gives
--     us a "why did we pick X over Y for this user" audit trail.
--
-- Idempotency: every CREATE has IF NOT EXISTS; constraints + indexes
-- DROP+CREATE-style. Safe to re-run.
-- =============================================================================

BEGIN;

-- ── notification_intents ─────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS notification_intents (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,

  -- Routing keys
  category        TEXT NOT NULL
                  CHECK (category IN ('rivalry','workout','recovery','nutrition','streak','social','announcement')),
  intent_kind     TEXT NOT NULL,  -- e.g. 'league_started','rivalry_behind','sleep_debt'

  -- Orchestrator scoring inputs
  -- 1..100; raised by urgency. Default 50 = neutral. Examples:
  --   league_started      → 70 (high — once a week)
  --   rivalry_behind      → 65 (mid-day re-engagement)
  --   recovery_alert(red) → 80 (safety / training-load)
  --   hydration_pace      → 30 (low — easy to feel naggy)
  --   streak_risk         → 75 (anti-churn)
  priority        INTEGER NOT NULL DEFAULT 50 CHECK (priority BETWEEN 1 AND 100),

  -- Template tokens used by the server-side template engine (Phase 3).
  -- Examples:
  --   { "opponent_name": "Manuel", "gap": 12500, "unit": "steps" }
  --   { "recovery_score": 38, "band": "red", "hrv_delta_pct": -18 }
  -- Schema is per-intent_kind; orchestrator passes verbatim to template.
  payload         JSONB NOT NULL DEFAULT '{}'::jsonb,

  -- Idempotency: producers compute a key like
  --   'league_started:user_id:2026-08-04'
  --   'rivalry_behind:user_id:challenge_id:2026-08-04T11:00'
  -- The unique index drops duplicate inserts (gracefully, with ON
  -- CONFLICT DO NOTHING in producer functions). Bounded to keep a
  -- mid-day rivalry intent from re-firing every 30 min.
  idempotency_key TEXT NOT NULL,

  -- Window outside which the intent is moot — orchestrator drops it.
  -- For "rivalry_behind", expires_at is end-of-day in user's tz.
  -- For "league_started", end of Monday.
  expires_at      TIMESTAMPTZ NOT NULL,

  -- Lifecycle
  status          TEXT NOT NULL DEFAULT 'pending'
                  CHECK (status IN ('pending','enqueued','suppressed','expired','failed')),
  -- The push_notification_queue.id we created (when status='enqueued').
  queue_id        UUID REFERENCES push_notification_queue(id) ON DELETE SET NULL,

  -- Provenance for forensics / Bug-Intel
  producer        TEXT NOT NULL,   -- e.g. 'enqueue_league_placement_intents'
  -- Feature-flag cohort key — orchestrator only acts on cohort users.
  -- Default 'all' for production cutover.
  cohort_key      TEXT NOT NULL DEFAULT 'all',

  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  decided_at      TIMESTAMPTZ
);

-- Idempotency: never re-insert the same kind for the same key window.
CREATE UNIQUE INDEX IF NOT EXISTS uq_notification_intents_idempotency
  ON notification_intents (idempotency_key);

-- Orchestrator scan: pending + not expired, by user.
CREATE INDEX IF NOT EXISTS idx_notification_intents_pending_user
  ON notification_intents (user_id, priority DESC, created_at)
  WHERE status = 'pending';

-- Orchestrator catch-all expirer.
CREATE INDEX IF NOT EXISTS idx_notification_intents_expires
  ON notification_intents (expires_at)
  WHERE status = 'pending';

-- CMS lookup: by intent_kind + status (drives the per-kind funnel).
CREATE INDEX IF NOT EXISTS idx_notification_intents_kind_status_created
  ON notification_intents (intent_kind, status, created_at DESC);

ALTER TABLE notification_intents ENABLE ROW LEVEL SECURITY;

-- Service role only (orchestrator + producers run as service_role).
-- No user-facing read; users see the OUTCOME via push_notification_queue
-- + push_notification_delivery_log already.
DROP POLICY IF EXISTS "service writes intents" ON notification_intents;
CREATE POLICY "service writes intents"
  ON notification_intents
  FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

-- ── notification_orchestration_decisions ────────────────────────────────
--
-- Append-only log of every decision the orchestrator makes, including
-- the runner-up scores. CMS Health & Funnel reads this to render
-- "why was X picked over Y for this user".

CREATE TABLE IF NOT EXISTS notification_orchestration_decisions (
  id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id         UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
  intent_id       UUID NOT NULL REFERENCES notification_intents(id) ON DELETE CASCADE,

  decision        TEXT NOT NULL CHECK (decision IN ('enqueued','suppressed','deferred')),
  -- Why this decision: 'top_score','prefs_blocked','category_disabled',
  -- 'snoozed','quiet_hours','daily_cap_reached','category_cap_reached',
  -- 'shadow_mode','below_runner_up','expired'.
  reason          TEXT NOT NULL,

  -- Score at decision time (for tuning the scoring function).
  score           NUMERIC,
  -- Snapshot of orchestrator inputs (predicted_engagement, hour_of_day,
  -- prefs_subset, category_caps_remaining). JSONB so we can grow.
  context         JSONB NOT NULL DEFAULT '{}'::jsonb,

  -- For shadow-mode A/B: log what we WOULD have done vs what we did.
  shadow_mode     BOOLEAN NOT NULL DEFAULT false,

  decided_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_orch_decisions_user_decided
  ON notification_orchestration_decisions (user_id, decided_at DESC);

CREATE INDEX IF NOT EXISTS idx_orch_decisions_decision_decided
  ON notification_orchestration_decisions (decision, decided_at DESC);

CREATE INDEX IF NOT EXISTS idx_orch_decisions_reason
  ON notification_orchestration_decisions (reason, decided_at DESC);

ALTER TABLE notification_orchestration_decisions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "service writes orch decisions" ON notification_orchestration_decisions;
CREATE POLICY "service writes orch decisions"
  ON notification_orchestration_decisions
  FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

-- ── Helper: enqueue an intent (idempotent) ──────────────────────────────
--
-- Producer-side helper used by every Phase 3 trigger / cron function.
-- Wraps the INSERT-ON-CONFLICT-DO-NOTHING pattern so producers don't
-- have to repeat the boilerplate. Returns the intent UUID (existing or
-- new). NULL when rejected (e.g. user_id missing, expires_at in past).

CREATE OR REPLACE FUNCTION enqueue_notification_intent(
  p_user_id          UUID,
  p_category         TEXT,
  p_intent_kind      TEXT,
  p_priority         INTEGER,
  p_payload          JSONB,
  p_idempotency_key  TEXT,
  p_expires_at       TIMESTAMPTZ,
  p_producer         TEXT,
  p_cohort_key       TEXT DEFAULT 'all'
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id UUID;
BEGIN
  IF p_user_id IS NULL OR p_intent_kind IS NULL OR p_idempotency_key IS NULL OR p_expires_at IS NULL THEN
    RETURN NULL;
  END IF;
  IF p_expires_at <= NOW() THEN
    RETURN NULL;  -- already expired; don't even insert.
  END IF;
  IF p_priority IS NULL OR p_priority < 1 OR p_priority > 100 THEN
    p_priority := 50;
  END IF;

  INSERT INTO notification_intents (
    user_id, category, intent_kind, priority, payload,
    idempotency_key, expires_at, producer, cohort_key
  )
  VALUES (
    p_user_id, p_category, p_intent_kind, p_priority, COALESCE(p_payload, '{}'::JSONB),
    p_idempotency_key, p_expires_at, p_producer, p_cohort_key
  )
  ON CONFLICT (idempotency_key) DO NOTHING
  RETURNING id INTO v_id;

  -- If conflict, fetch existing.
  IF v_id IS NULL THEN
    SELECT id INTO v_id
    FROM notification_intents
    WHERE idempotency_key = p_idempotency_key;
  END IF;

  RETURN v_id;
END;
$$;

GRANT EXECUTE ON FUNCTION enqueue_notification_intent(UUID, TEXT, TEXT, INTEGER, JSONB, TEXT, TIMESTAMPTZ, TEXT, TEXT) TO service_role;

-- ── Helper: expire stale intents (cron'd hourly) ────────────────────────

CREATE OR REPLACE FUNCTION expire_stale_notification_intents()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count INTEGER;
BEGIN
  UPDATE notification_intents
  SET status = 'expired',
      decided_at = NOW()
  WHERE status = 'pending'
    AND expires_at < NOW();

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

GRANT EXECUTE ON FUNCTION expire_stale_notification_intents() TO service_role;

-- ── Pruning ─────────────────────────────────────────────────────────────
--
-- Intents: keep 30 days of history (analytics / debugging).
-- Decisions: keep 30 days. Same retention as delivery_log.

CREATE OR REPLACE FUNCTION prune_notification_intents_and_decisions()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_intents INTEGER;
  v_decs    INTEGER;
BEGIN
  DELETE FROM notification_orchestration_decisions
  WHERE decided_at < NOW() - INTERVAL '30 days';
  GET DIAGNOSTICS v_decs = ROW_COUNT;

  DELETE FROM notification_intents
  WHERE created_at < NOW() - INTERVAL '30 days';
  GET DIAGNOSTICS v_intents = ROW_COUNT;

  IF v_intents > 0 OR v_decs > 0 THEN
    RAISE NOTICE 'Pruned % old intents, % old decisions', v_intents, v_decs;
  END IF;
END;
$$;

-- Cron: hourly expiry + daily prune
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'expire-notification-intents') THEN
    PERFORM cron.unschedule('expire-notification-intents');
  END IF;
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'prune-notification-intents-and-decisions') THEN
    PERFORM cron.unschedule('prune-notification-intents-and-decisions');
  END IF;
END $$;

SELECT cron.schedule(
  'expire-notification-intents',
  '7 * * * *',  -- 7 min past every hour (offset from queue cron)
  $$SELECT expire_stale_notification_intents();$$
);

SELECT cron.schedule(
  'prune-notification-intents-and-decisions',
  '17 3 * * *',  -- 3:17 AM UTC daily
  $$SELECT prune_notification_intents_and_decisions();$$
);

-- ── internal_config feature flag for the orchestrator cutover ───────────
--
-- Lives in `internal_config` (existing table per INFRA_SECURITY invariants).
-- Edge fn checks key 'notification_orchestrator_mode' on every run:
--   'shadow' (default) — score + log decisions, but DON'T enqueue.
--   'cohort:<key>'    — only act on intents where cohort_key = <key>.
--   'live'            — act on everything.

INSERT INTO internal_config (key, value, description)
VALUES (
  'notification_orchestrator_mode',
  'shadow',
  'Smart notification orchestrator mode: shadow (log only) | cohort:<key> | live'
)
ON CONFLICT (key) DO NOTHING;

-- ── Audit ───────────────────────────────────────────────────────────────

DO $$
DECLARE
  v_intent_jobs INTEGER;
BEGIN
  SELECT COUNT(*) INTO v_intent_jobs FROM cron.job
  WHERE jobname IN ('expire-notification-intents','prune-notification-intents-and-decisions');
  IF v_intent_jobs <> 2 THEN
    RAISE EXCEPTION 'Migration #169 audit failed: expected 2 cron jobs, found %', v_intent_jobs;
  END IF;

  RAISE NOTICE '✅ Migration #169 (notification intents + orchestration decisions) complete';
  RAISE NOTICE '   - notification_intents created with idempotency_key UNIQUE';
  RAISE NOTICE '   - notification_orchestration_decisions created (forensic log)';
  RAISE NOTICE '   - enqueue_notification_intent() + expire_stale_notification_intents() RPCs registered';
  RAISE NOTICE '   - 2 cron jobs scheduled (hourly expire + daily prune)';
  RAISE NOTICE '   - internal_config[notification_orchestrator_mode] defaulted to ''shadow''';
END $$;

COMMIT;
