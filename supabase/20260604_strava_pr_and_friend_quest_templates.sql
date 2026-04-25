-- ============================================================================
-- 20260604 — Smart Adaptive Daily Goals: new fun + Strava PR + friend templates
--
-- Phase 4 of the personalization upgrade. Adds three buckets of new
-- quest templates the v3 RPC will surface:
--
--   1. Strava PR / outdoor (auto, premium-XP, requires_context = 'has_strava'):
--        beat_your_5k_pr, negative_split_run, run_outside_8km,
--        cycle_outside_30km, complete_strava_segment
--
--   2. Wearable additions (auto, requires_context per device):
--        match_yesterday_strain (has_whoop)
--        walk_when_red          (has_wearable)
--
--   3. Friend-named fun quests (social, drives delight + retention):
--        do_friend_workout              (NEW key — server replaces title
--                                        with split-aware copy in v3 RPC)
--        comment_on_friends_workout     (NEW)
--        start_1v1_with_top_friend      (NEW)
--        react_to_3_workouts            (NEW companion to react_to_workout)
--
-- requires_context values used here. The v3 RPC (20260605) gates eligibility:
--   * 'has_strava'   — only when p_strava_connected = TRUE
--   * 'has_whoop'    — only when p_whoop_connected = TRUE
--   * 'has_wearable' — union OR of all 4 (kept for legacy templates)
--
-- Idempotent. ON CONFLICT preserves admin overrides on existing rows.
-- XP values are POST-rebalance (auto×1.5 / social×1.0 already applied) so
-- they do NOT get re-multiplied — migration 20260603's idempotency marker
-- ensures it doesn't re-run.
-- ============================================================================

BEGIN;

-- ── 1. Strava PR / outdoor templates (has_strava) ──────────────────────
INSERT INTO quest_templates (
    quest_key, title, description, icon, category,
    target_value, target_unit, xp_reward, league_points,
    difficulty, weight, requires_context, fun_label,
    verification_type, min_workouts
) VALUES
    ('beat_your_5k_pr',
        'Beat Your 5K PR',
        'Set a new 5K personal record',
        'flag.checkered',
        'workout', 1, 'run',
        75, 40, 'hard', 4, 'has_strava',
        '🏆 Chase the PR',
        'auto', 14),

    ('negative_split_run',
        'Negative Split',
        'Run faster on the back half today',
        'arrow.up.right',
        'workout', 1, 'run',
        60, 30, 'hard', 5, 'has_strava',
        '⚡ Strong finish',
        'auto', 10),

    ('run_outside_8km',
        'Long Run',
        'Run 8K outside today',
        'figure.run',
        'workout', 8000, 'meters',
        55, 28, 'hard', 5, 'has_strava',
        '🛣️ Time on feet',
        'auto', 10),

    ('cycle_outside_30km',
        'Big Ride',
        'Cycle 30K outside today',
        'figure.outdoor.cycle',
        'workout', 30000, 'meters',
        60, 30, 'hard', 5, 'has_strava',
        '🚴 Send the long road',
        'auto', 10),

    ('complete_strava_segment',
        'Segment Hunter',
        'Finish a Strava segment today',
        'mappin.and.ellipse',
        'workout', 1, 'segment',
        40, 20, 'medium', 6, 'has_strava',
        '📍 Bag a segment',
        'auto', 4)

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


-- ── 2. Wearable additions ──────────────────────────────────────────────
INSERT INTO quest_templates (
    quest_key, title, description, icon, category,
    target_value, target_unit, xp_reward, league_points,
    difficulty, weight, requires_context, fun_label,
    verification_type, min_workouts
) VALUES
    ('match_yesterday_strain',
        'Match the Strain',
        'Match yesterday''s WHOOP strain',
        'bolt.fill',
        'workout', 1, 'day',
        35, 20, 'medium', 5, 'has_whoop',
        '🔥 Repeat the effort',
        'auto', 7),

    ('walk_when_red',
        'Walk on Red',
        'Walk 20+ min on a red recovery day',
        'figure.walk',
        'workout', 20, 'minutes',
        25, 15, 'easy', 6, 'has_wearable',
        '🟥 Active recovery',
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


-- ── 3. Friend-named fun quests ─────────────────────────────────────────
-- The v3 RPC (20260605) rewrites these titles with friend names + split
-- recommendation when seeds are passed. Default copy below is the
-- fallback when no friend seeds are present.
INSERT INTO quest_templates (
    quest_key, title, description, icon, category,
    target_value, target_unit, xp_reward, league_points,
    difficulty, weight, requires_context, fun_label,
    verification_type, min_workouts
) VALUES
    ('do_friend_workout',
        'Do a Friend''s Workout',
        'Run a workout shared by a friend',
        'figure.2',
        'workout', 1, 'workout',
        35, 20, 'medium', 7, 'has_friends',
        '🤝 Train with the crew',
        'social', 4),

    ('comment_on_friends_workout',
        'Hype a Friend',
        'Comment on a friend''s workout',
        'bubble.left.fill',
        'social', 1, 'comment',
        15, 10, 'easy', 8, 'has_friends',
        '💬 Show some love',
        'social', 0),

    ('start_1v1_with_top_friend',
        'Start a 1v1',
        'Challenge your top friend today',
        'flag.2.crossed.fill',
        'social', 1, 'challenge',
        30, 20, 'medium', 6, 'has_friends_no_challenge',
        '⚔️ Bring the heat',
        'social', 2),

    ('react_to_3_workouts',
        'Spread the Hype',
        'React to 3 friends'' workouts',
        'hands.clap.fill',
        'social', 3, 'reactions',
        20, 12, 'easy', 7, 'has_friends',
        '👏 Hype train',
        'social', 0)

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


DO $$
DECLARE
    v_strava_count   INT;
    v_wearable_count INT;
    v_friend_count   INT;
BEGIN
    SELECT COUNT(*) INTO v_strava_count
      FROM quest_templates
     WHERE quest_key IN (
        'beat_your_5k_pr','negative_split_run','run_outside_8km',
        'cycle_outside_30km','complete_strava_segment'
     );
    SELECT COUNT(*) INTO v_wearable_count
      FROM quest_templates
     WHERE quest_key IN ('match_yesterday_strain', 'walk_when_red');
    SELECT COUNT(*) INTO v_friend_count
      FROM quest_templates
     WHERE quest_key IN (
        'do_friend_workout','comment_on_friends_workout',
        'start_1v1_with_top_friend','react_to_3_workouts'
     );
    RAISE NOTICE '✅ 20260604 templates: strava_pr=% / wearable_add=% / friend=% (gated requires_context — surfaced by v3 RPC 20260605)',
        v_strava_count, v_wearable_count, v_friend_count;
END $$;

COMMIT;

-- ─── Verification ──────────────────────────────────────────────────────
-- SELECT quest_key, requires_context, verification_type, xp_reward, difficulty
--   FROM quest_templates
--  WHERE quest_key IN (
--     'beat_your_5k_pr','negative_split_run','run_outside_8km',
--     'cycle_outside_30km','complete_strava_segment',
--     'match_yesterday_strain','walk_when_red',
--     'do_friend_workout','comment_on_friends_workout',
--     'start_1v1_with_top_friend','react_to_3_workouts'
--  )
--  ORDER BY requires_context, quest_key;
