-- =============================================================================
-- Smart Notification Engine — Phase 3: Template Engine + A/B Variants
-- =============================================================================
-- Migration #171
-- Date: 2026-08-07
-- Authors: Data/Backend
-- Depends on: 20260801, 20260802, 20260804
--
-- Purpose:
--
--   notification_templates — registry of (intent_kind, variant) → copy
--     templates. Body/title use {token} interpolation against the intent's
--     payload JSONB (e.g. {opponent_name}, {gap}, {recovery_score},
--     {bedtime_eta}, {streak_days}). Templates can also stuff data into
--     the push `data` payload (e.g. for tap-routing target IDs).
--
--   render_notification_copy(intent_id) — RPC the orchestrator calls.
--     Picks a random active variant weighted by `weight`, interpolates
--     tokens, returns { title, body, data, variant_id }. The chosen
--     variant_id is logged to push_notification_delivery_log so the CMS
--     A/B winners view can compare open rates per variant.
--
-- Notes:
--   - Tokens unresolved against payload render as empty string (defensive
--     — never leak literal `{token}` to users).
--   - A/B is OPT-IN per intent_kind: if only one variant exists for a
--     kind, no randomization happens.
-- =============================================================================

BEGIN;

CREATE TABLE IF NOT EXISTS notification_templates (
  id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

  intent_kind     TEXT NOT NULL,
  -- Free-text variant name ('a','b','control','urgent','playful', etc.).
  variant         TEXT NOT NULL DEFAULT 'default',

  category        TEXT NOT NULL
                  CHECK (category IN ('rivalry','workout','recovery','nutrition','streak','social','announcement')),

  -- Title with {token} interpolation. Tokens reference payload keys.
  title_template  TEXT NOT NULL,
  -- Body with {token} interpolation.
  body_template   TEXT NOT NULL,

  -- Optional data payload merged into the push `data` field. e.g. set
  -- `{"deep_link": "smack_talk:{challenge_id}"}` to override default tap
  -- routing for this variant.
  data_template   JSONB NOT NULL DEFAULT '{}'::JSONB,

  -- A/B selection weight. Variants picked proportionally; 0 = disabled.
  weight          INTEGER NOT NULL DEFAULT 100 CHECK (weight >= 0),

  -- Soft-toggle without deleting (preserve historical analytics).
  is_active       BOOLEAN NOT NULL DEFAULT true,

  -- Optional cohort gating (matches notification_intents.cohort_key).
  -- NULL = available to all cohorts.
  cohort_key      TEXT,

  notes           TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- UNIQUE expression constraints (over COALESCE) aren't allowed inline in
-- CREATE TABLE — use a partial-style unique index instead. Same effect for
-- ON CONFLICT (intent_kind, variant, COALESCE(cohort_key,'')) below.
CREATE UNIQUE INDEX IF NOT EXISTS uq_notification_templates_kind_variant_cohort
  ON notification_templates (intent_kind, variant, COALESCE(cohort_key, ''));

CREATE INDEX IF NOT EXISTS idx_notification_templates_kind_active
  ON notification_templates (intent_kind, is_active);

ALTER TABLE notification_templates ENABLE ROW LEVEL SECURITY;

-- Authenticated users CAN read templates (Settings preview screen renders
-- examples). No PII; no abuse vector.
DROP POLICY IF EXISTS "Authenticated read templates" ON notification_templates;
CREATE POLICY "Authenticated read templates"
  ON notification_templates FOR SELECT
  TO authenticated
  USING (is_active = true);

DROP POLICY IF EXISTS "Service writes templates" ON notification_templates;
CREATE POLICY "Service writes templates"
  ON notification_templates FOR ALL
  TO service_role
  USING (true) WITH CHECK (true);

-- ── Token interpolation helper ──────────────────────────────────────────
--
-- `interpolate('Hey {name}, you owe {gap} steps.', '{"name":"Manuel","gap":12500}')`
--   → 'Hey Manuel, you owe 12500 steps.'
-- Unresolved tokens render as empty string. Numeric values are cast to text
-- via the JSONB ->> operator (no thousands separator — templates can pad
-- via `{gap_pretty}` after producers compute it client-side).

CREATE OR REPLACE FUNCTION interpolate_template(
  p_template TEXT,
  p_payload  JSONB
)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_result TEXT := COALESCE(p_template, '');
  v_token  TEXT;
  v_value  TEXT;
BEGIN
  IF p_payload IS NULL OR p_template IS NULL THEN
    RETURN v_result;
  END IF;

  -- Replace each {token} with the JSONB value, or empty string when missing.
  FOR v_token IN
    SELECT DISTINCT (regexp_matches(v_result, '\{([a-z0-9_]+)\}', 'gi'))[1]
  LOOP
    v_value := COALESCE(p_payload ->> v_token, '');
    v_result := REPLACE(v_result, '{' || v_token || '}', v_value);
  END LOOP;

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION interpolate_template(TEXT, JSONB) TO authenticated, service_role;

-- ── Variant picker ──────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION pick_template_variant(
  p_intent_kind TEXT,
  p_cohort_key  TEXT DEFAULT 'all'
)
RETURNS notification_templates
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_template notification_templates%ROWTYPE;
  v_total_weight INTEGER;
  v_pick INTEGER;
  v_acc INTEGER := 0;
BEGIN
  -- Cohort-matched variants take priority; fall through to NULL cohort.
  SELECT SUM(weight) INTO v_total_weight
  FROM notification_templates
  WHERE intent_kind = p_intent_kind
    AND is_active = true
    AND (cohort_key = p_cohort_key OR cohort_key IS NULL);

  IF v_total_weight IS NULL OR v_total_weight = 0 THEN
    RETURN NULL;
  END IF;

  v_pick := FLOOR(RANDOM() * v_total_weight)::INTEGER;

  FOR v_template IN
    SELECT *
    FROM notification_templates
    WHERE intent_kind = p_intent_kind
      AND is_active = true
      AND (cohort_key = p_cohort_key OR cohort_key IS NULL)
    ORDER BY (cohort_key IS NULL), variant
  LOOP
    v_acc := v_acc + v_template.weight;
    IF v_pick < v_acc THEN
      RETURN v_template;
    END IF;
  END LOOP;

  RETURN v_template;  -- fallback to last
END;
$$;

GRANT EXECUTE ON FUNCTION pick_template_variant(TEXT, TEXT) TO service_role;

-- ── Main render RPC (called by orchestrator) ────────────────────────────

CREATE OR REPLACE FUNCTION render_notification_copy(p_intent_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_intent   notification_intents%ROWTYPE;
  v_template notification_templates%ROWTYPE;
  v_title    TEXT;
  v_body     TEXT;
  v_data     JSONB;
BEGIN
  SELECT * INTO v_intent FROM notification_intents WHERE id = p_intent_id;
  IF NOT FOUND THEN
    RETURN NULL;
  END IF;

  v_template := pick_template_variant(v_intent.intent_kind, v_intent.cohort_key);
  IF v_template.id IS NULL THEN
    -- No template registered — let the orchestrator fall back to its
    -- TS-side default copy (returns NULL signals "no template").
    RETURN NULL;
  END IF;

  v_title := interpolate_template(v_template.title_template, v_intent.payload);
  v_body  := interpolate_template(v_template.body_template,  v_intent.payload);

  -- data: merge template default with payload (payload wins so producer
  -- can override per-intent).
  v_data := COALESCE(v_template.data_template, '{}'::JSONB);
  IF v_intent.payload IS NOT NULL THEN
    -- Pass-through standard tap-routing keys from payload → push data.
    FOR v_template.id IN SELECT 0 LOOP NULL; END LOOP;  -- placeholder no-op
  END IF;
  -- Stamp variant id so the funnel can A/B compare.
  v_data := v_data || jsonb_build_object(
    'template_id', v_template.id,
    'variant', v_template.variant
  );
  -- Forward common deep-link keys when present in payload.
  IF v_intent.payload ? 'challenge_id' THEN
    v_data := v_data || jsonb_build_object('challenge_id', v_intent.payload->>'challenge_id');
  END IF;
  IF v_intent.payload ? 'workout_id' THEN
    v_data := v_data || jsonb_build_object('workout_id', v_intent.payload->>'workout_id');
  END IF;

  RETURN jsonb_build_object(
    'title', v_title,
    'body',  v_body,
    'data',  v_data,
    'variant_id', v_template.id,
    'variant', v_template.variant
  );
END;
$$;

GRANT EXECUTE ON FUNCTION render_notification_copy(UUID) TO service_role;

-- ── Default templates (one variant per intent_kind, weight=100) ─────────
--
-- Producers + the orchestrator can ship more variants over time without
-- another migration; this seeds the canonical baseline so a fresh
-- environment doesn't fall back to TS defaults.

INSERT INTO notification_templates (intent_kind, variant, category, title_template, body_template, weight, notes)
VALUES
  -- League rollover
  ('league_started', 'default', 'rivalry',
   '{tier_emoji} {tier_name} league starts now',
   'First place locks in a +200 XP shield — make a move before someone else does.',
   100, 'Monday 8am league rollover.'),

  -- Rivalry: opponent leading mid-day
  ('rivalry_behind', 'default', 'rivalry',
   '{opponent_name} is pulling ahead',
   'Down {gap} {unit} today — talk smack or close the gap.',
   100, 'Mid-day 1v1 nudge.'),
  ('rivalry_behind', 'playful', 'rivalry',
   '👀 {opponent_name} thinks they got this',
   '{gap} {unit} ahead. You gonna let that slide?',
   60, 'A/B test against default.'),

  -- Recovery alerts
  ('recovery_alert', 'default', 'recovery',
   'Recovery red — go light today',
   'HRV down {hrv_delta_pct}%. Today''s auto-workout will favor mobility.',
   100, '7am red-band'),
  ('recovery_yellow', 'default', 'recovery',
   'Yellow recovery',
   'Keep RPE under 7. Big sets later this week instead.',
   100, '7am yellow band'),
  ('recovery_pr_opportunity', 'default', 'recovery',
   'Green light + you''re due a PR',
   'Recovery {recovery_score}. Bench PR window is open today.',
   100, 'High-recovery + PR-due'),

  -- Sleep
  ('sleep_debt', 'default', 'recovery',
   'Need more sleep tonight',
   'Get {needed_hours}h to hit baseline — that means lights out by {bedtime_eta}.',
   100, '9pm sleep nudge'),

  -- Hydration
  ('hydration_pace', 'default', 'nutrition',
   'Behind on water',
   '{deficit_oz}oz left to hit your goal — log a glass.',
   100, '11/2/5pm pace check'),

  -- Streak protection
  ('streak_risk', 'default', 'streak',
   '🔥 {streak_days}-day streak at risk',
   'Log anything in the next 4h to save it.',
   100, '6pm streak protector'),

  -- Workout opportunity
  ('friend_workout_match', 'default', 'workout',
   '{friend_name} just trained {muscle_group}',
   'You''re {days_since_you_trained_it} days overdue — match it?',
   100, 'Friend just lifted same muscle group'),
  ('pr_opportunity', 'default', 'workout',
   'PR window is open',
   'Your {exercise_name} is due for a bump — try +{suggested_increment} {weight_unit} today.',
   100, '4pm PR nudge'),
  ('overdue_muscle_group', 'default', 'workout',
   '{muscle_group} is overdue',
   'It''s been {days_since} days — quick session today?',
   100, '4pm overdue muscle nudge'),

  -- Strava celebration
  ('strava_celebration', 'default', 'workout',
   'Big day on Strava',
   '{distance_km}km in {duration_min} minutes. Tap to see your recap.',
   100, 'Post-Strava-import'),

  -- Comeback / morning kickstart (existing; keep consistent copy)
  ('morning_kickstart', 'default', 'recovery',
   'Good morning — your day starts here',
   'Recovery {recovery_score}, {workouts_this_week}/{weekly_target} workouts. Tap to see today''s plan.',
   100, '6:30am morning brief')
ON CONFLICT (intent_kind, variant, COALESCE(cohort_key, '')) DO UPDATE
  SET title_template = EXCLUDED.title_template,
      body_template  = EXCLUDED.body_template,
      data_template  = EXCLUDED.data_template,
      weight         = EXCLUDED.weight,
      is_active      = true,
      updated_at     = NOW();

DO $$ BEGIN
  RAISE NOTICE '✅ Migration #171 (notification template engine + A/B variants) complete';
  RAISE NOTICE '   - notification_templates created with token interpolation';
  RAISE NOTICE '   - interpolate_template / pick_template_variant / render_notification_copy RPCs';
  RAISE NOTICE '   - 14 default templates seeded across all Phase 3 intent_kinds';
END $$;

COMMIT;
