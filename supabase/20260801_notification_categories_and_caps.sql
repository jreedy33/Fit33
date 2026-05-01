-- =============================================================================
-- Smart Notification Engine — Phase 1: Categories + Per-Category Caps
-- =============================================================================
-- Migration #168
-- Date: 2026-08-01
-- Authors: Infra/Security + Data/Backend
--
-- Purpose:
--   1. Add `category` column to push_notification_queue so the orchestrator
--      and CMS Health & Funnel tab can group, filter, and rate-limit by
--      category instead of the free-form `notification_type` string.
--   2. Add per-category cap + per-category quiet-hours + per-category
--      master-disable to user_notification_preferences. Existing
--      `daily_cap` continues to act as the global ceiling.
--   3. Backfill the `category` column on existing queue rows by mapping
--      the historical `notification_type` enum into the new 7-category
--      taxonomy (rivalry / workout / recovery / nutrition / streak / social
--      / announcement). `notification_type` stays — it's the fine-grained
--      iOS routing key. `category` is the orchestration / billing key.
--   4. Idempotent: every column/index/policy uses IF [NOT] EXISTS or
--      DROP+CREATE. Safe to re-run.
--
-- Cross-references:
--   - INFRA_SECURITY_AGENT.md invariants 13 + 14 (queue separation; silent
--     pushes never enter this table — they're internal to wake-* functions).
--   - send-push-notification edge fn (2026-08-01 rewrite) reads
--     category_caps, category_disabled, daily_cap from this table.
--   - CMS /notifications Push Manager surfaces category in Queue Monitor +
--     Health & Funnel tabs (Phase 5).
-- =============================================================================

BEGIN;

-- ── 1. Categorize push_notification_queue ────────────────────────────────

ALTER TABLE push_notification_queue
  ADD COLUMN IF NOT EXISTS category TEXT;

-- Backfill existing rows by mapping notification_type → category.
-- Lazy categorization: anything not on the explicit map falls into 'social'
-- because legacy types are dominated by friend / challenge / community
-- triggers. Wrong defaults are detectable in the CMS funnel and tunable.
UPDATE push_notification_queue
SET category = CASE
  -- Rivalry / leagues / smack
  WHEN notification_type IN (
    'challenge_invite', 'challenge_accepted', 'challenge_declined',
    'challenge_completed', 'challenge_update', 'challenge_reaction',
    'challenge_nudge', 'group_challenge_invite', 'private_challenge_invite',
    'private_challenge_member_joined', 'league_started', 'league_promoted',
    'league_demoted', 'rivalry_behind', 'rivalry_lead', 'comeback_window'
  ) THEN 'rivalry'

  -- Workouts
  WHEN notification_type IN (
    'daily_workout_reminder', 'workout_pr', 'pr_opportunity',
    'overdue_muscle_group', 'friend_workout_match', 'shared_workout_received'
  ) THEN 'workout'

  -- Recovery & health (WHOOP / Oura / sleep)
  WHEN notification_type IN (
    'recovery_alert', 'recovery_yellow', 'recovery_pr_opportunity',
    'sleep_debt', 'sleep_low', 'morning_kickstart'
  ) THEN 'recovery'

  -- Nutrition + hydration
  WHEN notification_type IN (
    'meal_reminder', 'protein_deficit', 'hydration_pace', 'hydration_reminder',
    'breakfast_reminder', 'water_reminder'
  ) THEN 'nutrition'

  -- Streak protection / milestones
  WHEN notification_type IN (
    'streak_risk', 'streak_milestone', 'streak_protection'
  ) THEN 'streak'

  -- Social
  WHEN notification_type IN (
    'friend_request', 'friend_accepted', 'contact_joined',
    'friend_activity', 'friend_active'
  ) THEN 'social'

  -- Announcements / marketing
  WHEN notification_type IN (
    'app_update', 'feature_announcement', 'marketing'
  ) THEN 'announcement'

  -- Smart nudges decay into 'rivalry' since the existing morning_kickstart +
  -- engagement variants are challenge-anchored. Re-categorize at the point
  -- of generation in Phase 2 once the orchestrator owns the producer.
  WHEN notification_type LIKE 'smart_nudge%' THEN 'rivalry'
  WHEN notification_type LIKE 'engagement_%' THEN 'rivalry'

  -- Anything we don't recognize → social (the "default" surface).
  ELSE 'social'
END
WHERE category IS NULL;

-- After backfill, lock the column NOT NULL so future writers must categorize.
-- (Senders that don't set it will be caught by the constraint, not silently
-- enqueued as 'unknown'.)
ALTER TABLE push_notification_queue
  ALTER COLUMN category SET DEFAULT 'social';

ALTER TABLE push_notification_queue
  ALTER COLUMN category SET NOT NULL;

-- Constraint enforces the canonical 7-category enum. Adding a new category
-- is a one-line migration here; the orchestrator + CMS pull the same list
-- from `notification_categories()`.
ALTER TABLE push_notification_queue
  DROP CONSTRAINT IF EXISTS push_notification_queue_category_check;

ALTER TABLE push_notification_queue
  ADD CONSTRAINT push_notification_queue_category_check
  CHECK (category IN ('rivalry', 'workout', 'recovery', 'nutrition', 'streak', 'social', 'announcement'));

-- Index for the CMS funnel + cap-counting queries.
CREATE INDEX IF NOT EXISTS idx_push_queue_category_status
  ON push_notification_queue (category, status, created_at DESC);

-- ── 2. Per-category prefs on user_notification_preferences ──────────────

ALTER TABLE user_notification_preferences
  ADD COLUMN IF NOT EXISTS category_caps JSONB NOT NULL DEFAULT '{}'::jsonb;

ALTER TABLE user_notification_preferences
  ADD COLUMN IF NOT EXISTS category_disabled TEXT[] NOT NULL DEFAULT '{}';

-- Per-category quiet hours: { category: { start: "HH:MM", end: "HH:MM", tz: "..." } }
-- Empty object = inherit top-level quiet_hours_start/end. Used by the
-- orchestrator to allow a Recovery user to opt their alerts into 6-9am
-- only without affecting Rivalry pushes.
ALTER TABLE user_notification_preferences
  ADD COLUMN IF NOT EXISTS category_quiet_hours JSONB NOT NULL DEFAULT '{}'::jsonb;

-- Snooze: { category_or_global: until_iso8601 }
-- The "snooze 24h" quick action writes here; orchestrator + send-push
-- check `snoozed_until[category] > now()` before delivering.
ALTER TABLE user_notification_preferences
  ADD COLUMN IF NOT EXISTS snoozed_until JSONB NOT NULL DEFAULT '{}'::jsonb;

-- "Smart timing": when true, the orchestrator picks the best send hour
-- per (user, category) from notification_engagement_history. When false,
-- triggers fire on their own schedule.
ALTER TABLE user_notification_preferences
  ADD COLUMN IF NOT EXISTS smart_timing_enabled BOOLEAN NOT NULL DEFAULT true;

-- Per-category frequency tier UI control (Quiet / Balanced / Active).
-- The orchestrator translates these into category_caps under the hood,
-- but storing the tier preserves the user's original intent across
-- rebalancing iterations.
ALTER TABLE user_notification_preferences
  ADD COLUMN IF NOT EXISTS category_frequency JSONB NOT NULL DEFAULT '{}'::jsonb;

-- ── 3. Server-readable category catalogue ───────────────────────────────
--
-- Single source of truth for the 7 categories so iOS, CMS, and orchestrator
-- can fetch the same list. Keys match the constraint above.

CREATE TABLE IF NOT EXISTS notification_categories (
  category TEXT PRIMARY KEY,
  display_name TEXT NOT NULL,
  emoji TEXT NOT NULL,
  description TEXT NOT NULL,
  -- Default cap when user hasn't set one. NULL = uncapped.
  default_daily_cap INTEGER,
  -- "Quiet" tier cap (1/day standard).
  quiet_cap INTEGER NOT NULL DEFAULT 1,
  -- "Balanced" tier cap (3/day standard).
  balanced_cap INTEGER NOT NULL DEFAULT 3,
  -- "Active" tier cap (NULL = uncapped).
  active_cap INTEGER,
  -- Display order in settings UI.
  display_order INTEGER NOT NULL DEFAULT 99,
  is_user_configurable BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO notification_categories
  (category, display_name, emoji, description, default_daily_cap, quiet_cap, balanced_cap, active_cap, display_order)
VALUES
  ('rivalry',     'Rivalries & Leagues',      '⚔️', 'Leaderboard movement, smack talk, league placement, opponents leading.', 4, 1, 4, NULL, 1),
  ('workout',     'Workouts',                 '💪', 'Daily workout reminder, friend just worked out, PR opportunity, overdue muscle group.', 3, 1, 3, 6, 2),
  ('recovery',    'Recovery & Health',        '❤️', 'WHOOP / Oura recovery alerts, sleep debt, morning kickstart.', 2, 1, 2, 4, 3),
  ('nutrition',   'Nutrition & Hydration',    '🥗', 'Meal reminders, water nudges, protein deficit, breakfast reminder.', 3, 1, 3, 6, 4),
  ('streak',      'Streaks',                  '🔥', 'Streak risk after 6pm, streak milestone celebrations.', 2, 1, 2, 3, 5),
  ('social',      'Social',                   '👋', 'Friend requests, friend joined, contact joined, shared workouts.', 5, 2, 5, NULL, 6),
  ('announcement','Announcements',            '📣', 'App updates, feature announcements, occasional marketing.', 1, 0, 1, 2, 7)
ON CONFLICT (category) DO UPDATE
  SET display_name = EXCLUDED.display_name,
      emoji = EXCLUDED.emoji,
      description = EXCLUDED.description,
      default_daily_cap = EXCLUDED.default_daily_cap,
      quiet_cap = EXCLUDED.quiet_cap,
      balanced_cap = EXCLUDED.balanced_cap,
      active_cap = EXCLUDED.active_cap,
      display_order = EXCLUDED.display_order;

ALTER TABLE notification_categories ENABLE ROW LEVEL SECURITY;

-- Anyone authenticated can read the catalogue (no PII).
DROP POLICY IF EXISTS "Authenticated users can read categories" ON notification_categories;
CREATE POLICY "Authenticated users can read categories"
  ON notification_categories FOR SELECT
  TO authenticated
  USING (true);

-- ── 4. RPCs the iOS settings UI consumes ────────────────────────────────

-- Hydrate notification preferences from server (two-way sync).
-- Called from iOS NotificationManager.syncPreferencesFromCloud() on
-- launch + when the settings sheet appears. SECURITY DEFINER + auth.uid()
-- pattern; no user_id parameter (Infra/Security invariant 9).
CREATE OR REPLACE FUNCTION get_my_notification_preferences()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_prefs   JSONB;
  v_cats    JSONB;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('error', 'not_authenticated');
  END IF;

  SELECT jsonb_build_object(
    'master_enabled',        COALESCE(master_enabled, true),
    'disabled_types',        COALESCE(disabled_types, '{}'::TEXT[]),
    'quiet_hours_enabled',   COALESCE(quiet_hours_enabled, false),
    'quiet_hours_start',     quiet_hours_start,
    'quiet_hours_end',       quiet_hours_end,
    'timezone',              COALESCE(timezone, 'America/New_York'),
    'daily_cap',             COALESCE(daily_cap, 8),
    'category_caps',         COALESCE(category_caps, '{}'::JSONB),
    'category_disabled',     COALESCE(category_disabled, '{}'::TEXT[]),
    'category_quiet_hours',  COALESCE(category_quiet_hours, '{}'::JSONB),
    'snoozed_until',         COALESCE(snoozed_until, '{}'::JSONB),
    'smart_timing_enabled',  COALESCE(smart_timing_enabled, true),
    'category_frequency',    COALESCE(category_frequency, '{}'::JSONB),
    'updated_at',            updated_at
  )
  INTO v_prefs
  FROM user_notification_preferences
  WHERE user_id = v_user_id;

  IF v_prefs IS NULL THEN
    -- No row yet — synthesize defaults so the iOS UI has something to render.
    v_prefs := jsonb_build_object(
      'master_enabled', true,
      'disabled_types', '[]'::JSONB,
      'quiet_hours_enabled', false,
      'quiet_hours_start', NULL,
      'quiet_hours_end', NULL,
      'timezone', 'America/New_York',
      'daily_cap', 8,
      'category_caps', '{}'::JSONB,
      'category_disabled', '[]'::JSONB,
      'category_quiet_hours', '{}'::JSONB,
      'snoozed_until', '{}'::JSONB,
      'smart_timing_enabled', true,
      'category_frequency', '{}'::JSONB,
      'updated_at', NULL,
      'is_default', true
    );
  END IF;

  -- Bundle the category catalogue so the UI doesn't need a second round-trip.
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'category', category,
    'display_name', display_name,
    'emoji', emoji,
    'description', description,
    'default_daily_cap', default_daily_cap,
    'quiet_cap', quiet_cap,
    'balanced_cap', balanced_cap,
    'active_cap', active_cap,
    'display_order', display_order,
    'is_user_configurable', is_user_configurable
  ) ORDER BY display_order), '[]'::JSONB)
  INTO v_cats
  FROM notification_categories;

  RETURN jsonb_build_object(
    'preferences', v_prefs,
    'categories', v_cats,
    'fetched_at', NOW()
  );
END;
$$;

GRANT EXECUTE ON FUNCTION get_my_notification_preferences() TO authenticated;

-- Snooze helper. Pass category = NULL to snooze ALL pushes.
CREATE OR REPLACE FUNCTION snooze_notification_category(
  p_category TEXT,    -- NULL = snooze everything (writes 'global' key)
  p_hours INTEGER     -- 1..168 (1h to 7d)
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_until TIMESTAMPTZ;
  v_key TEXT;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'reason', 'not_authenticated');
  END IF;
  IF p_hours IS NULL OR p_hours < 1 OR p_hours > 168 THEN
    RETURN jsonb_build_object('success', false, 'reason', 'invalid_hours');
  END IF;
  IF p_category IS NOT NULL AND p_category NOT IN
     ('rivalry','workout','recovery','nutrition','streak','social','announcement') THEN
    RETURN jsonb_build_object('success', false, 'reason', 'invalid_category');
  END IF;

  v_until := NOW() + (p_hours || ' hours')::INTERVAL;
  v_key := COALESCE(p_category, 'global');

  -- Upsert in case row doesn't exist yet.
  INSERT INTO user_notification_preferences (user_id, snoozed_until, updated_at)
  VALUES (v_user_id, jsonb_build_object(v_key, v_until), NOW())
  ON CONFLICT (user_id) DO UPDATE
    SET snoozed_until = COALESCE(user_notification_preferences.snoozed_until, '{}'::JSONB)
                        || jsonb_build_object(v_key, v_until),
        updated_at = NOW();

  RETURN jsonb_build_object(
    'success', true,
    'category', v_key,
    'snoozed_until', v_until
  );
END;
$$;

GRANT EXECUTE ON FUNCTION snooze_notification_category(TEXT, INTEGER) TO authenticated;

-- Quick "clear snooze" RPC.
CREATE OR REPLACE FUNCTION clear_notification_snooze(p_category TEXT)  -- NULL = clear all snoozes
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_key TEXT;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'reason', 'not_authenticated');
  END IF;

  IF p_category IS NULL THEN
    UPDATE user_notification_preferences
    SET snoozed_until = '{}'::JSONB, updated_at = NOW()
    WHERE user_id = v_user_id;
  ELSE
    v_key := p_category;
    UPDATE user_notification_preferences
    SET snoozed_until = COALESCE(snoozed_until, '{}'::JSONB) - v_key,
        updated_at = NOW()
    WHERE user_id = v_user_id;
  END IF;

  RETURN jsonb_build_object('success', true);
END;
$$;

GRANT EXECUTE ON FUNCTION clear_notification_snooze(TEXT) TO authenticated;

-- ── 5. Add `category` to delivery log so funnel queries are O(1) ────────
--
-- The CMS Health & Funnel tab joins delivery_log → queue today, which is
-- expensive. Stamping the category onto delivery_log itself lets the
-- per-category funnel queries scan a single index. Backfill from queue.

ALTER TABLE push_notification_delivery_log
  ADD COLUMN IF NOT EXISTS category TEXT;

UPDATE push_notification_delivery_log dl
SET category = q.category
FROM push_notification_queue q
WHERE dl.notification_id = q.id
  AND dl.category IS NULL;

-- For silent push delivery rows (notification_id IS NULL), category is set
-- by the writer via the `detail` JSONB; backfill where present.
UPDATE push_notification_delivery_log
SET category = detail->>'category'
WHERE category IS NULL
  AND detail ? 'category';

CREATE INDEX IF NOT EXISTS idx_delivery_log_category_event_created
  ON push_notification_delivery_log (category, event, created_at DESC)
  WHERE category IS NOT NULL;

-- ── 6. Audit block: confirm post-state ──────────────────────────────────

DO $$
DECLARE
  v_uncategorized_queue INTEGER;
  v_category_count INTEGER;
BEGIN
  SELECT COUNT(*) INTO v_uncategorized_queue
  FROM push_notification_queue WHERE category IS NULL;
  IF v_uncategorized_queue > 0 THEN
    RAISE EXCEPTION 'Migration #168 audit failed: % queue rows still uncategorized', v_uncategorized_queue;
  END IF;

  SELECT COUNT(*) INTO v_category_count FROM notification_categories;
  IF v_category_count <> 7 THEN
    RAISE EXCEPTION 'Migration #168 audit failed: notification_categories should have 7 rows, found %', v_category_count;
  END IF;

  RAISE NOTICE '✅ Migration #168 (notification categories + caps) complete';
  RAISE NOTICE '   - 7 categories registered: rivalry, workout, recovery, nutrition, streak, social, announcement';
  RAISE NOTICE '   - push_notification_queue.category NOT NULL (default ''social'')';
  RAISE NOTICE '   - user_notification_preferences gained 5 columns (category_caps, category_disabled, category_quiet_hours, snoozed_until, smart_timing_enabled, category_frequency)';
  RAISE NOTICE '   - delivery log gains category column for O(1) funnel queries';
END $$;

COMMIT;
