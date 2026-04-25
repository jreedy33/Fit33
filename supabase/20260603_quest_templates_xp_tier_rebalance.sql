-- ============================================================================
-- 20260603 — Smart Adaptive Daily Goals: XP rebalance by verification type
--
-- Phase 3 of the personalization upgrade. The user's direction was:
--   "auto-tracked goals from all sources should have more xp points cause
--    we can prove verify. input goals should typically be less as they are
--    honor system."
--
-- One-shot UPDATE on quest_templates.xp_reward + league_points using:
--   * auto    × 1.5  (auto-verifiable: HealthKit / Strava / WHOOP / Oura /
--                    Fitbit / completed-workout flag from the app)
--   * social  × 1.0  (in-app action with server-side proof: react, comment,
--                    challenge join)
--   * manual  × 0.7  (honor-system manual logging: meals, hydration,
--                    self-reported weight)
--
-- Idempotent: tracked via internal_config row 'quest_xp_rebalance_20260603'
-- so re-running this migration is a no-op.
-- ============================================================================

BEGIN;

DO $$
DECLARE
    v_already_run TEXT;
    v_auto_rows   INT := 0;
    v_social_rows INT := 0;
    v_manual_rows INT := 0;
BEGIN
    SELECT value INTO v_already_run
      FROM internal_config
     WHERE key = 'quest_xp_rebalance_20260603';

    IF v_already_run IS NOT NULL THEN
        RAISE NOTICE 'Skipping XP rebalance — already applied at %', v_already_run;
        RETURN;
    END IF;

    -- ── auto ×1.5 ──────────────────────────────────────────────────────
    UPDATE quest_templates
       SET xp_reward     = GREATEST(5, ROUND(xp_reward     * 1.5)::INT),
           league_points = GREATEST(5, ROUND(league_points * 1.5)::INT)
     WHERE verification_type = 'auto'
       AND is_active = TRUE;
    GET DIAGNOSTICS v_auto_rows = ROW_COUNT;

    -- ── social ×1.0 (no change, but recorded for audit) ────────────────
    -- Intentionally a no-op pass — keeps XP unchanged but verifies the
    -- branch is hit. Skip if you want; recorded as 0 rows.
    SELECT 0 INTO v_social_rows;

    -- ── manual ×0.7 ────────────────────────────────────────────────────
    UPDATE quest_templates
       SET xp_reward     = GREATEST(5, ROUND(xp_reward     * 0.7)::INT),
           league_points = GREATEST(5, ROUND(league_points * 0.7)::INT)
     WHERE verification_type = 'manual'
       AND is_active = TRUE;
    GET DIAGNOSTICS v_manual_rows = ROW_COUNT;

    -- ── Idempotency marker ────────────────────────────────────────────
    -- internal_config schema is (key TEXT PRIMARY KEY, value TEXT) only
    -- (see 20260324_push_notification_cron.sql line 20). No updated_at
    -- column — the timestamp is embedded in `value` for audit.
    INSERT INTO internal_config (key, value)
    VALUES ('quest_xp_rebalance_20260603', now()::TEXT)
    ON CONFLICT (key) DO UPDATE SET
        value = EXCLUDED.value;

    RAISE NOTICE '✅ 20260603: rebalanced quest_templates XP — auto=% rows ×1.5, manual=% rows ×0.7 (social unchanged)',
        v_auto_rows, v_manual_rows;
END $$;

COMMIT;

-- ─── Verification ──────────────────────────────────────────────────────
-- SELECT verification_type, COUNT(*), AVG(xp_reward)::INT, AVG(league_points)::INT
--   FROM quest_templates
--  WHERE is_active = TRUE
--  GROUP BY verification_type
--  ORDER BY verification_type;
--
-- Expected after rebalance: auto avg ≈ 30-50, social ≈ 20, manual ≈ 15.
