-- =============================================================================
-- Migration #178 — Per-user orchestrator canary allowlist
-- =============================================================================
-- Date:    2026-05-02
-- Author:  Smart Notification Engine — controlled-rollout helper.
--
-- WHAT THIS DOES
-- --------------
-- Adds a new `internal_config` key:
--   `notification_orchestrator_canary_user_ids`
--     value: JSON array of user UUIDs (e.g. '["uuid1","uuid2"]')
--
-- The notification-orchestrator edge function reads this list every tick.
-- When the global mode is `shadow` BUT an intent's user_id appears in the
-- canary list, the orchestrator behaves LIVE for that one user — enqueues
-- the row into push_notification_queue + APNs delivery happens. Every
-- other user stays in shadow (decision logged, no push fired).
--
-- WHY
-- ---
-- Existing `cohort:<key>` mode requires producers to tag intents with
-- cohort_key, which is a coordinated change across 7+ producer crons.
-- The canary list is per-user instead — zero producer changes, zero
-- schema changes, only adds one config row. Lets us validate end-to-end
-- delivery on a couple of internal accounts before flipping the global
-- switch.
--
-- HOW TO USE
-- ----------
-- - Add a UUID:    UPDATE internal_config
--                  SET value = '["uuid1","uuid2"]'
--                  WHERE key = 'notification_orchestrator_canary_user_ids';
-- - Disable list:  UPDATE internal_config
--                  SET value = '[]'
--                  WHERE key = 'notification_orchestrator_canary_user_ids';
-- - The list is IGNORED entirely once global mode flips to `live` —
--   every user is live at that point so the canary distinction is moot
--   (but the row stays so we can flip back to shadow + canary if needed).
--
-- INITIAL VALUE
-- -------------
-- Three canary slots (Joe + 2 dogfood accounts), requested 2026-05-02
-- once the post-fix shadow data confirmed the engine was healthy
-- (max 1 push / user / 2h).
-- =============================================================================

BEGIN;

INSERT INTO internal_config (key, value)
VALUES (
  'notification_orchestrator_canary_user_ids',
  '["a94823b5-43db-4581-b3cf-95f6ed57c5ef","e342aa15-2aea-4084-b1a5-cdc552163f58","d10d5d03-1a0d-4b41-b61b-a4f30a56362e"]'
)
ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;

-- Reload the PostgREST cache so the orchestrator's next read is fresh.
NOTIFY pgrst, 'reload schema';

DO $audit$
DECLARE
  v_value TEXT;
BEGIN
  SELECT value INTO v_value
  FROM internal_config
  WHERE key = 'notification_orchestrator_canary_user_ids';

  IF v_value IS NULL THEN
    RAISE EXCEPTION '[#178] canary list config row missing — INSERT failed';
  END IF;

  RAISE NOTICE '[#178] ✅ canary list = %', v_value;
END
$audit$;

COMMIT;
