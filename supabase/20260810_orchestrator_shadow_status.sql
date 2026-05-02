-- =============================================================================
-- Smart Notification Engine — Hotfix: shadow-mode infinite re-decision loop
-- =============================================================================
-- Migration #176
-- Date: 2026-05-02
-- Author: Data/Backend
-- Depends on: 20260802_notification_intents.sql (#169)
--
-- Why this exists:
--
--   Shadow mode bug: in `notification-orchestrator/index.ts` the shadow
--   branch logged "would-have-enqueued" decisions but never updated
--   `notification_intents.status`. The candidate scan at line ~178 of
--   the edge function uses `WHERE status = 'pending'`, so the same
--   intent kept reappearing on every 5-minute tick. After 48h, 123
--   real intents had generated 13,298 phantom "would-have-sent"
--   decisions, with one user racking up 354 would-be pushes/day.
--   Flipping live in that state would have burned the entire push
--   channel.
--
--   This migration:
--     1. Adds 'shadow_decided' to the status CHECK constraint.
--     2. Backfills existing stuck-pending intents to 'shadow_decided'
--        so the next orchestrator tick has a clean slate.
--
--   The paired orchestrator code change writes 'shadow_decided' on the
--   shadow path, mirroring how 'enqueued' is written on the live path.
--
-- Safe to re-run.
-- =============================================================================

BEGIN;

-- 1. Extend status CHECK to allow the new shadow terminal state.
ALTER TABLE notification_intents
  DROP CONSTRAINT IF EXISTS notification_intents_status_check;

ALTER TABLE notification_intents
  ADD CONSTRAINT notification_intents_status_check
  CHECK (status IN ('pending','enqueued','suppressed','expired','failed','shadow_decided'));

-- 2. Backfill: any intent still 'pending' that already has at least one
--    "enqueued" decision row is a victim of the bug — mark it terminal.
UPDATE notification_intents i
SET status = 'shadow_decided',
    decided_at = COALESCE(decided_at, NOW())
WHERE i.status = 'pending'
  AND EXISTS (
    SELECT 1 FROM notification_orchestration_decisions d
    WHERE d.intent_id = i.id
      AND d.decision = 'enqueued'
      AND d.shadow_mode = true
  );

-- 3. Audit
DO $$
DECLARE
  v_backfilled INTEGER;
  v_still_pending INTEGER;
BEGIN
  SELECT COUNT(*) INTO v_backfilled
  FROM notification_intents
  WHERE status = 'shadow_decided';

  SELECT COUNT(*) INTO v_still_pending
  FROM notification_intents
  WHERE status = 'pending';

  RAISE NOTICE '✅ Migration #176 (shadow-decided status) complete';
  RAISE NOTICE '   - Status CHECK extended to include ''shadow_decided''';
  RAISE NOTICE '   - Backfilled to ''shadow_decided'': %', v_backfilled;
  RAISE NOTICE '   - Remaining pending intents: %', v_still_pending;
END $$;

COMMIT;
