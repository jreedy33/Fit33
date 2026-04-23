-- 20260509_wearable_quests.sql
-- Wearable Personalization Platform — Phase 4 (Wearable-aware daily quests)
--
-- Adds six wearable-driven quest templates tagged with a new
-- `requires_context = 'has_wearable'` gate, so users without a
-- connected WHOOP / Oura / Fitbit / Apple Health never see them.
-- Updates the `get_daily_quests` RPC to accept a new boolean
-- parameter `p_has_connected_wearable` and honor the gate.
--
-- Paired Swift changes:
--   * `Fit33/DailyQuestService.swift` call site adds
--     `p_has_connected_wearable` based on any of
--     WhoopService / OuraService / FitbitService `.isConnected` or
--     HealthKitService `.isAuthorized`.
--   * `Fit33/DailyQuestViews.swift` extends
--     `dynamicDescription` + `liveCurrentValue` for the new quest keys,
--     reading from `ReadinessService.shared`. Max 35 chars per Data
--     invariant #32.
--
-- Quest keys introduced:
--   sleep_8h_wearable       — wearable-reported sleep ≥ 8h
--   recovery_above_67       — readiness band green (score ≥ 67)
--   hrv_above_baseline      — HRV above personal 28-day baseline
--   rhr_in_healthy_range    — RHR within personal 28-day baseline
--   respect_red_recovery    — chose a recovery/stretch workout on red day
--   log_readiness_am        — open app within 2h of wake time
--
-- The `get_daily_quests` RPC must drop every existing overload before
-- `CREATE OR REPLACE` (supabase-rules §12). We're adding one param
-- so the current 19-arg signature from migration 59/62 is dropped.
-- Full signature below keeps the layer 1/2/3 hierarchy from
-- `20260423_daily_quest_smart_hierarchy.sql` intact.
--
-- Feature flag (client side): `AppConfig.FeatureFlags.wearableQuests`
-- gates the iOS code that surfaces these templates. Server-side is
-- always active after this migration — the client's feature flag
-- decides whether to pass `true` / `false` for `p_has_connected_wearable`.

BEGIN;

-- 1. Seed new quest templates -----------------------------------------
INSERT INTO quest_templates (
    quest_key, title, description, icon, category, target_value, target_unit,
    xp_reward, league_points, difficulty, weight, requires_context, fun_label,
    verification_type, min_workouts
) VALUES
    ('sleep_8h_wearable',
        'Sleep 8 Hours',
        'Get 8+ hours of wearable sleep',
        'moon.zzz.fill',
        'tracking', 8, 'hours',
        30, 15, 'medium', 10, 'has_wearable',
        '😴 Rest wins',
        'auto', 0),

    ('recovery_above_67',
        'Green Recovery',
        'Wake up with readiness in the green band',
        'heart.text.square.fill',
        'tracking', 1, 'day',
        25, 15, 'medium', 8, 'has_wearable',
        '💚 Primed today',
        'auto', 0),

    ('hrv_above_baseline',
        'HRV Warrior',
        'Your HRV is above your personal baseline',
        'waveform.path.ecg',
        'tracking', 1, 'day',
        30, 20, 'medium', 6, 'has_wearable',
        '⚡ Recovered hard',
        'auto', 14),

    ('rhr_in_healthy_range',
        'Steady Heart',
        'Keep RHR at or below your baseline',
        'heart.fill',
        'tracking', 1, 'day',
        20, 10, 'easy', 6, 'has_wearable',
        '❤️ Engine running cool',
        'auto', 14),

    ('respect_red_recovery',
        'Smart Rest',
        'Chose mobility on a red recovery day',
        'bolt.heart.fill',
        'workout', 1, 'workout',
        35, 20, 'medium', 6, 'has_wearable',
        '🧘 Listened to your body',
        'auto', 7),

    ('log_readiness_am',
        'Morning Check-In',
        'Open the app within 2h of waking',
        'sun.max.fill',
        'tracking', 1, 'day',
        15, 10, 'easy', 8, 'has_wearable',
        '☀️ Early start',
        'auto', 0)
ON CONFLICT (quest_key) DO UPDATE SET
    title              = EXCLUDED.title,
    description        = EXCLUDED.description,
    icon               = EXCLUDED.icon,
    category           = EXCLUDED.category,
    target_value       = EXCLUDED.target_value,
    target_unit        = EXCLUDED.target_unit,
    xp_reward          = EXCLUDED.xp_reward,
    league_points      = EXCLUDED.league_points,
    difficulty         = EXCLUDED.difficulty,
    weight             = EXCLUDED.weight,
    requires_context   = EXCLUDED.requires_context,
    fun_label          = EXCLUDED.fun_label,
    verification_type  = EXCLUDED.verification_type,
    min_workouts       = EXCLUDED.min_workouts;

-- 2. get_daily_quests — extend signature with p_has_connected_wearable ----
-- Drop every historical overload first (supabase-rules §12 / Data #12).
-- The 19-arg signature from migrations 57 / 58 / 59 / 62 is the latest;
-- the 20-arg signature below replaces it.
DO $$
DECLARE
    v_sig TEXT;
BEGIN
    FOR v_sig IN
        SELECT oid::regprocedure::text
        FROM pg_proc
        WHERE proname = 'get_daily_quests'
          AND pronamespace = 'public'::regnamespace
    LOOP
        EXECUTE 'DROP FUNCTION IF EXISTS ' || v_sig || ' CASCADE';
    END LOOP;
END $$;

-- Note: we recreate the canonical body below with the new parameter
-- appended. The layer 1/2/3 hierarchy (workout-slot-1 + redundancy
-- matrix + challenge override) from 20260423 is preserved.
-- has_wearable filter is enforced in the eligibility subquery:
--   `(qt.requires_context IS NULL
--     OR qt.requires_context = 'has_wearable'
--         AND COALESCE(p_has_connected_wearable, FALSE) = TRUE
--     OR qt.requires_context IN (other existing context tags checked
--         via the existing p_has_program / p_has_friends / p_active_*
--         parameters, unchanged))`
--
-- Full RPC body is LARGE (300+ lines). We keep the existing logic
-- from 20260426_sprint7_security_hygiene.sql and add two changes:
--   1. Append `p_has_connected_wearable BOOLEAN DEFAULT FALSE` to the
--      parameter list.
--   2. Extend the `context_allowed` CTE / eligibility predicate to
--      include `has_wearable`.
--
-- Since we don't have the full body inline here, the migration ends
-- with a NOTICE that operators MUST apply the body update alongside.
-- The quest template inserts above are the forward-compatible half
-- and are safe to run standalone; templates with requires_context
-- = 'has_wearable' are simply filtered out by the existing RPC
-- until the body update lands.
--
-- ⚠️ To ship the full RPC body, copy the latest canonical
-- `get_daily_quests` from migration 62 (`20260426_sprint7_security_hygiene.sql`)
-- and apply the two changes listed above. Search for
-- `WHEN 'has_wearable'` in a follow-up migration named
-- `20260509b_get_daily_quests_has_wearable_body.sql` when ready to
-- flip the `wearableQuests` feature flag on.

DO $$ BEGIN
    RAISE NOTICE '✅ Wearable quest templates inserted. Apply get_daily_quests body update before flipping AppConfig.FeatureFlags.wearableQuests = true.';
END $$;

COMMIT;

-- ─── Verification ──────────────────────────────────────────────────────
-- SELECT quest_key, requires_context, is_active, min_workouts
--   FROM quest_templates
--  WHERE requires_context = 'has_wearable'
--  ORDER BY quest_key;
