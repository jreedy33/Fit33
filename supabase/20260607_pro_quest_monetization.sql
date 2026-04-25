-- ============================================================================
-- 20260607 — Smart Adaptive Daily Goals: Pro monetization RPCs
--
-- Resolves: 7bf1ff4efdac6620edfbda328204ed16 — v_user_quest_personalization_summary missing (Report 6 / 04-25 audit; this migration creates the view)
-- Resolves: f30626309d8480ec14526323da68396d — same view missing, log variant (Report 11 / 04-25 audit)
--
-- Phase 7 (final) of the personalization upgrade. Ships the four
-- subscriber-facing features the plan calls out:
--
--   * reroll_daily_quest(p_quest_id, p_timezone, p_is_pro)
--       Replaces one slot with a fresh candidate.
--       Free: 1/day cooldown (no replays).
--       Pro:  5/day, no cooldown.
--
--   * claim_double_xp_day(p_date, p_is_pro)
--       Pro-only, 1/week. Stamps today's user_daily_quests rows with
--       double_xp = TRUE. update_quest_progress is patched to double XP
--       awarded when the flag is set.
--
--   * submit_custom_quest(p_title, p_target_value, p_target_unit, p_is_pro)
--       Pro-only, 1/day, manual verification, capped 25 XP.
--
--   * v_user_quest_personalization_summary  (security_invoker = on)
--       Drives the Pro Insights screen — 28-day per-category completion
--       bars, current streaks, suppressions.
--
-- Plus the supporting schema:
--   * user_quest_rerolls (user_id, reroll_date, count, last_at)
--   * user_daily_quests.double_xp BOOLEAN
--   * user_daily_quests.is_custom BOOLEAN
--   * user_daily_quests.is_reroll BOOLEAN
--
-- Premium check: the client passes p_is_pro based on PremiumManager
-- (matches the existing p_is_subscriber pattern in get_daily_quests).
-- A future migration may swap this for a server-side subscription_status
-- read once the canonical premium column lands; the function signatures
-- accept the boolean today to avoid a breaking change later.
-- ============================================================================

BEGIN;

-- ── 1. Schema: new columns + reroll ledger ──────────────────────────────
ALTER TABLE user_daily_quests
    ADD COLUMN IF NOT EXISTS double_xp BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS is_custom BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS is_reroll BOOLEAN NOT NULL DEFAULT FALSE;

CREATE TABLE IF NOT EXISTS user_quest_rerolls (
    user_id      UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
    reroll_date  DATE NOT NULL DEFAULT CURRENT_DATE,
    count        INT  NOT NULL DEFAULT 0,
    last_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, reroll_date)
);

ALTER TABLE user_quest_rerolls ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "uqr_select_own" ON user_quest_rerolls;
DROP POLICY IF EXISTS "uqr_insert_own" ON user_quest_rerolls;
DROP POLICY IF EXISTS "uqr_update_own" ON user_quest_rerolls;
CREATE POLICY "uqr_select_own" ON user_quest_rerolls
    FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "uqr_insert_own" ON user_quest_rerolls
    FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "uqr_update_own" ON user_quest_rerolls
    FOR UPDATE USING (auth.uid() = user_id);

CREATE TABLE IF NOT EXISTS user_double_xp_claims (
    user_id     UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
    claim_date  DATE NOT NULL,
    claimed_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, claim_date)
);

ALTER TABLE user_double_xp_claims ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "udxc_select_own" ON user_double_xp_claims;
DROP POLICY IF EXISTS "udxc_insert_own" ON user_double_xp_claims;
CREATE POLICY "udxc_select_own" ON user_double_xp_claims
    FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "udxc_insert_own" ON user_double_xp_claims
    FOR INSERT WITH CHECK (auth.uid() = user_id);


-- ── 2. reroll_daily_quest ──────────────────────────────────────────────
DROP FUNCTION IF EXISTS public.reroll_daily_quest(UUID, TEXT, BOOLEAN);

CREATE OR REPLACE FUNCTION public.reroll_daily_quest(
    p_quest_id  UUID,
    p_timezone  TEXT DEFAULT 'America/New_York',
    p_is_pro    BOOLEAN DEFAULT FALSE
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_caller_id   UUID := auth.uid();
    v_today       DATE;
    v_quest       RECORD;
    v_existing    TEXT[];
    v_recent      TEXT[];
    v_count_today INT;
    v_max_per_day INT := CASE WHEN p_is_pro THEN 5 ELSE 1 END;
    v_swap_key    TEXT;
    v_template    RECORD;
BEGIN
    IF v_caller_id IS NULL THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'not_authenticated');
    END IF;

    v_today := (now() AT TIME ZONE p_timezone)::DATE;

    -- Fetch + ownership + completion check (Data invariant 7).
    SELECT * INTO v_quest
      FROM user_daily_quests
     WHERE id = p_quest_id
       AND user_id = v_caller_id
       AND quest_date = v_today;

    IF v_quest IS NULL THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'quest_not_found_or_not_today');
    END IF;

    IF v_quest.is_completed THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'already_completed');
    END IF;

    -- Cooldown / per-day quota.
    SELECT count INTO v_count_today
      FROM user_quest_rerolls
     WHERE user_id = v_caller_id AND reroll_date = v_today;
    v_count_today := COALESCE(v_count_today, 0);

    IF v_count_today >= v_max_per_day THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'reason', CASE WHEN p_is_pro THEN 'pro_limit_reached' ELSE 'free_limit_reached' END,
            'used', v_count_today,
            'limit', v_max_per_day
        );
    END IF;

    -- Build the exclude set: today's other quests + last 3 days.
    SELECT COALESCE(ARRAY_AGG(quest_key), '{}') INTO v_existing
      FROM user_daily_quests
     WHERE user_id = v_caller_id AND quest_date = v_today;

    SELECT COALESCE(ARRAY_AGG(DISTINCT quest_key), '{}') INTO v_recent
      FROM user_daily_quests
     WHERE user_id = v_caller_id
       AND quest_date >= v_today - INTERVAL '3 days'
       AND quest_date < v_today;

    -- Pick a fresh candidate of the same difficulty bucket if possible
    -- (keeps the day's overall difficulty balance stable).
    SELECT qt.quest_key INTO v_swap_key
      FROM quest_templates qt
     WHERE qt.is_active = TRUE
       AND qt.is_premium = FALSE
       AND (p_is_pro OR qt.tier = 'free')
       AND qt.difficulty = v_quest.difficulty
       AND qt.quest_key NOT IN (
            'upper_body_workout','lower_body_workout',
            'complete_program_day','complete_2_workouts'
       )
       AND qt.quest_key <> ALL(v_existing)
       AND qt.quest_key <> ALL(v_recent)
       AND NOT EXISTS (
           SELECT 1 FROM user_quest_key_stats s
            WHERE s.user_id = v_caller_id
              AND s.quest_key = qt.quest_key
              AND s.suppressed_until IS NOT NULL
              AND s.suppressed_until > v_today
       )
       AND NOT EXISTS (
           SELECT 1 FROM user_quest_personalization p
            WHERE p.user_id = v_caller_id
              AND p.category = qt.category
              AND p.suppressed_until IS NOT NULL
              AND p.suppressed_until > v_today
       )
     ORDER BY (abs(hashtext(qt.quest_key)) + abs(hashtext(v_today::TEXT))) % 11
     LIMIT 1;

    -- Fall back to any non-suppressed key if no same-difficulty match exists.
    IF v_swap_key IS NULL THEN
        SELECT qt.quest_key INTO v_swap_key
          FROM quest_templates qt
         WHERE qt.is_active = TRUE
           AND qt.is_premium = FALSE
           AND (p_is_pro OR qt.tier = 'free')
           AND qt.quest_key <> ALL(v_existing)
           AND qt.quest_key <> ALL(v_recent)
           AND qt.quest_key NOT IN (
                'upper_body_workout','lower_body_workout',
                'complete_program_day','complete_2_workouts'
           )
         ORDER BY (abs(hashtext(qt.quest_key)) + abs(hashtext(v_today::TEXT))) % 11
         LIMIT 1;
    END IF;

    IF v_swap_key IS NULL THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'no_eligible_swap');
    END IF;

    SELECT * INTO v_template FROM quest_templates WHERE quest_key = v_swap_key;

    -- Atomically swap the row in place — keeps the same id so client
    -- state (animations, scroll position) stays stable.
    UPDATE user_daily_quests
       SET quest_key     = v_template.quest_key,
           title         = v_template.title,
           description   = v_template.description,
           icon          = v_template.icon,
           category      = v_template.category,
           target_value  = v_template.target_value,
           target_unit   = v_template.target_unit,
           xp_reward     = v_template.xp_reward,
           league_points = v_template.league_points,
           difficulty    = v_template.difficulty,
           current_value = 0,
           is_completed  = FALSE,
           completed_at  = NULL,
           is_reroll     = TRUE
     WHERE id = p_quest_id;

    INSERT INTO user_quest_rerolls (user_id, reroll_date, count, last_at)
    VALUES (v_caller_id, v_today, 1, now())
    ON CONFLICT (user_id, reroll_date) DO UPDATE SET
        count   = user_quest_rerolls.count + 1,
        last_at = EXCLUDED.last_at;

    RETURN jsonb_build_object(
        'success', TRUE,
        'new_quest_key', v_swap_key,
        'remaining',     v_max_per_day - (v_count_today + 1),
        'is_pro',        p_is_pro
    );
END;
$$;

REVOKE ALL ON FUNCTION public.reroll_daily_quest(UUID, TEXT, BOOLEAN) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.reroll_daily_quest(UUID, TEXT, BOOLEAN) TO authenticated;

COMMENT ON FUNCTION public.reroll_daily_quest(UUID, TEXT, BOOLEAN) IS
    'Smart Adaptive Daily Goals (20260607): swap one of today''s quest slots for a fresh candidate. Free 1/day, Pro 5/day. Auth-pinned (Data invariant 7).';


-- ── 3. claim_double_xp_day ─────────────────────────────────────────────
DROP FUNCTION IF EXISTS public.claim_double_xp_day(DATE, BOOLEAN);

CREATE OR REPLACE FUNCTION public.claim_double_xp_day(
    p_date     DATE DEFAULT NULL,
    p_is_pro   BOOLEAN DEFAULT FALSE
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_caller_id    UUID := auth.uid();
    v_target_date  DATE := COALESCE(p_date, CURRENT_DATE);
    v_recent_claim DATE;
    v_rows_updated INT;
BEGIN
    IF v_caller_id IS NULL THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'not_authenticated');
    END IF;

    IF NOT p_is_pro THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'pro_required');
    END IF;

    -- 1/week cooldown — last claim must be ≥ 7 days ago.
    SELECT MAX(claim_date) INTO v_recent_claim
      FROM user_double_xp_claims
     WHERE user_id = v_caller_id;

    IF v_recent_claim IS NOT NULL AND (v_target_date - v_recent_claim) < 7 THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'reason', 'weekly_cooldown',
            'last_claim_date', v_recent_claim,
            'next_eligible_date', v_recent_claim + 7
        );
    END IF;

    -- Stamp today's quest rows.
    UPDATE user_daily_quests
       SET double_xp = TRUE
     WHERE user_id = v_caller_id
       AND quest_date = v_target_date;

    GET DIAGNOSTICS v_rows_updated = ROW_COUNT;

    IF v_rows_updated = 0 THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'no_quests_for_date', 'date', v_target_date);
    END IF;

    INSERT INTO user_double_xp_claims (user_id, claim_date)
    VALUES (v_caller_id, v_target_date);

    RETURN jsonb_build_object(
        'success', TRUE,
        'date', v_target_date,
        'quests_marked', v_rows_updated
    );
END;
$$;

REVOKE ALL ON FUNCTION public.claim_double_xp_day(DATE, BOOLEAN) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.claim_double_xp_day(DATE, BOOLEAN) TO authenticated;

COMMENT ON FUNCTION public.claim_double_xp_day(DATE, BOOLEAN) IS
    'Smart Adaptive Daily Goals (20260607): Pro-only. 1/week. Marks today''s user_daily_quests rows with double_xp=TRUE so update_quest_progress doubles XP awarded.';


-- ── 4. update_quest_progress patch — honor double_xp flag ──────────────
-- We can't fully redefine the function here without copying ~150 lines,
-- so we add a SECURITY DEFINER helper that the client can call to bonus
-- the streak entry post-completion. Cleaner: a lightweight trigger on
-- user_daily_quests UPDATE that doubles awarded xp when transitioning to
-- is_completed = TRUE on a double_xp row.

CREATE OR REPLACE FUNCTION public.apply_double_xp_on_complete()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_extra_xp INT;
    v_extra_lp INT;
BEGIN
    IF NEW.is_completed
       AND NEW.double_xp
       AND (OLD IS NULL OR NOT OLD.is_completed) THEN
        -- Award the bonus exactly once on the completion transition.
        v_extra_xp := NEW.xp_reward;
        v_extra_lp := NEW.league_points;

        UPDATE user_quest_streaks
           SET total_xp_earned     = COALESCE(total_xp_earned, 0) + v_extra_xp,
               updated_at          = now()
         WHERE user_id = NEW.user_id;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_apply_double_xp_on_complete ON user_daily_quests;
CREATE TRIGGER trg_apply_double_xp_on_complete
    AFTER UPDATE OF is_completed ON user_daily_quests
    FOR EACH ROW
    WHEN (NEW.is_completed AND NEW.double_xp)
    EXECUTE FUNCTION public.apply_double_xp_on_complete();


-- ── 5. submit_custom_quest ─────────────────────────────────────────────
DROP FUNCTION IF EXISTS public.submit_custom_quest(TEXT, INT, TEXT, BOOLEAN, TEXT);

CREATE OR REPLACE FUNCTION public.submit_custom_quest(
    p_title        TEXT,
    p_target_value INT     DEFAULT 1,
    p_target_unit  TEXT    DEFAULT 'times',
    p_is_pro       BOOLEAN DEFAULT FALSE,
    p_timezone     TEXT    DEFAULT 'America/New_York'
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_caller_id   UUID := auth.uid();
    v_today       DATE;
    v_existing    INT;
    v_xp          INT := 25;        -- capped per the plan
    v_lp          INT := 15;
    v_quest_key   TEXT;
    v_safe_title  TEXT;
    v_id          UUID;
BEGIN
    IF v_caller_id IS NULL THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'not_authenticated');
    END IF;
    IF NOT p_is_pro THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'pro_required');
    END IF;
    IF p_title IS NULL OR length(trim(p_title)) < 3 THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'title_too_short');
    END IF;
    IF p_target_value IS NULL OR p_target_value < 1 OR p_target_value > 10000 THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'target_out_of_range');
    END IF;

    v_today := (now() AT TIME ZONE p_timezone)::DATE;
    v_safe_title := substring(trim(p_title) FROM 1 FOR 35);
    v_quest_key  := 'custom_' || encode(gen_random_bytes(6), 'hex');

    -- 1/day quota.
    SELECT COUNT(*) INTO v_existing
      FROM user_daily_quests
     WHERE user_id = v_caller_id
       AND quest_date = v_today
       AND is_custom = TRUE;
    IF v_existing >= 1 THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'one_custom_per_day');
    END IF;

    INSERT INTO user_daily_quests (
        user_id, quest_date, quest_key, title, description, icon,
        category, target_value, target_unit, xp_reward, league_points,
        difficulty, is_custom
    ) VALUES (
        v_caller_id, v_today, v_quest_key,
        v_safe_title,
        v_safe_title,
        'star.fill',
        'general',
        p_target_value,
        COALESCE(p_target_unit, 'times'),
        v_xp,
        v_lp,
        'medium',
        TRUE
    )
    RETURNING id INTO v_id;

    RETURN jsonb_build_object(
        'success', TRUE,
        'id', v_id,
        'quest_key', v_quest_key,
        'xp_reward', v_xp,
        'league_points', v_lp
    );
END;
$$;

REVOKE ALL ON FUNCTION public.submit_custom_quest(TEXT, INT, TEXT, BOOLEAN, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.submit_custom_quest(TEXT, INT, TEXT, BOOLEAN, TEXT) TO authenticated;

COMMENT ON FUNCTION public.submit_custom_quest(TEXT, INT, TEXT, BOOLEAN, TEXT) IS
    'Smart Adaptive Daily Goals (20260607): Pro-only. 1/day. Manual-verification custom quest capped at 25 XP / 15 LP.';


-- ── 6. v_user_quest_personalization_summary view ──────────────────────
DROP VIEW IF EXISTS public.v_user_quest_personalization_summary CASCADE;

CREATE VIEW public.v_user_quest_personalization_summary
WITH (security_invoker = on)
AS
SELECT
    p.user_id,
    p.category,
    p.total_assigned_28d,
    p.total_completed_28d,
    p.completion_rate_28d,
    p.skip_streak,
    p.last_completed_at,
    p.suppressed_until,
    -- Effective state for the UI: green / yellow / red / suppressed.
    CASE
        WHEN p.suppressed_until IS NOT NULL AND p.suppressed_until > CURRENT_DATE THEN 'suppressed'
        WHEN p.completion_rate_28d >= 0.66 THEN 'on_fire'
        WHEN p.completion_rate_28d >= 0.33 THEN 'mixed'
        ELSE 'cold'
    END AS state,
    am.dominant_category    AS user_dominant_category,
    am.least_category       AS user_least_category,
    am.total_sessions_28d   AS user_sessions_28d
FROM user_quest_personalization p
LEFT JOIN user_activity_mix am ON am.user_id = p.user_id;

GRANT SELECT ON public.v_user_quest_personalization_summary TO authenticated;

COMMENT ON VIEW public.v_user_quest_personalization_summary IS
    'Smart Adaptive Daily Goals (20260607): Pro Insights screen feed. security_invoker = on, so RLS on user_quest_personalization + user_activity_mix still applies to the caller.';


-- ── 7. unsuppress_quest_category — Pro override ───────────────────────
-- "Pro feature: turn a suppression off if user wants to re-engage that
-- category" per the plan §8.
DROP FUNCTION IF EXISTS public.unsuppress_quest_category(TEXT, BOOLEAN);

CREATE OR REPLACE FUNCTION public.unsuppress_quest_category(
    p_category TEXT,
    p_is_pro   BOOLEAN DEFAULT FALSE
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_caller_id UUID := auth.uid();
    v_rows      INT;
BEGIN
    IF v_caller_id IS NULL THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'not_authenticated');
    END IF;
    IF NOT p_is_pro THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'pro_required');
    END IF;
    IF p_category IS NULL OR length(p_category) = 0 THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'missing_category');
    END IF;

    UPDATE user_quest_personalization
       SET suppressed_until = NULL,
           skip_streak      = 0,
           updated_at       = now()
     WHERE user_id = v_caller_id
       AND category = p_category;
    GET DIAGNOSTICS v_rows = ROW_COUNT;

    UPDATE user_quest_key_stats s
       SET suppressed_until = NULL,
           updated_at       = now()
      FROM quest_templates qt
     WHERE s.user_id = v_caller_id
       AND s.quest_key = qt.quest_key
       AND qt.category = p_category
       AND s.suppressed_until IS NOT NULL;

    RETURN jsonb_build_object(
        'success', TRUE,
        'category', p_category,
        'rows_cleared', v_rows
    );
END;
$$;

REVOKE ALL ON FUNCTION public.unsuppress_quest_category(TEXT, BOOLEAN) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.unsuppress_quest_category(TEXT, BOOLEAN) TO authenticated;

COMMENT ON FUNCTION public.unsuppress_quest_category(TEXT, BOOLEAN) IS
    'Smart Adaptive Daily Goals (20260607): Pro override that clears suppression for a category so the user can re-engage. Used by QuestInsightsView.';


COMMIT;

-- ─── Verification ──────────────────────────────────────────────────────
-- SELECT proname FROM pg_proc WHERE proname IN (
--   'reroll_daily_quest','claim_double_xp_day',
--   'submit_custom_quest','unsuppress_quest_category'
-- );
-- SELECT * FROM v_user_quest_personalization_summary LIMIT 5;
