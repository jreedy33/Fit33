-- ============================================================================
-- 20260702 — Daily Goals Insights: per-category user toggles
--
-- Pro-only follow-up to 20260607 (Smart Adaptive Daily Goals — Pro
-- monetization). Adds an explicit user-controlled "include this category
-- in my Daily Goals" lever, surfaced from `Fit33/QuestInsightsView.swift`
-- as a Toggle row per category.
--
-- DESIGN — reuse `suppressed_until`, don't add a new column.
--   The 20260601 personalization engine already excludes a user's
--   `(user_id, category)` pool when `suppressed_until > today`. Auto-
--   suppression sets `today + 14d` (decays after one completion). User
--   toggle-off MUST persist forever (never auto-decay) but MUST also
--   stay in the SAME column the eligibility CTE already reads — so no
--   surgery on `get_daily_quests` v3 or its 60-line CTE is required.
--
--   We use the SENTINEL `'2099-12-31'::DATE` for "user-disabled forever"
--   and surface a synthetic `user_disabled` boolean from the Pro Insights
--   view so the iOS toggle reads the right state. `unsuppress_quest_category`
--   already clears the column to NULL — that double-duties as the "toggle
--   on" path; we add a dedicated `set_quest_category_enabled` RPC so the
--   client surface stays clean and the DEFINER block can also UPSERT a
--   missing personalization row (existing function only UPDATEs, which
--   no-ops for users who've never had a row in that category yet).
--
-- INVARIANTS RESPECTED:
--   - Supabase 9: SECURITY DEFINER RPC takes no user_id param; uses auth.uid().
--   - Supabase 6 / Data 6: view stays `security_invoker = on`.
--   - Supabase 12: drop overloads explicitly before CREATE OR REPLACE.
--   - Supabase 17: BEGIN/COMMIT, idempotent, IF NOT EXISTS guards.
--   - PE 19: client `defaultGoals()` fallback already covers the "user
--     disabled every category → server returns empty slate" case.
-- ============================================================================

BEGIN;

-- ── 1. Sentinel-aware view (adds `user_disabled` synthetic column) ───────
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
    -- "User toggled this category off" iff suppressed_until is the
    -- forever-sentinel (or anything > 1 year out — defensive). Auto-
    -- suppression caps at +14d so this can never collide with the
    -- adaptive system's suppression window.
    (p.suppressed_until IS NOT NULL
        AND p.suppressed_until > CURRENT_DATE + INTERVAL '365 days')
        AS user_disabled,
    -- Effective state for the UI: green / yellow / red / suppressed /
    -- disabled. `disabled` is shown as the on/off pill state in the
    -- toggles row; `suppressed` retains the auto-paused copy.
    CASE
        WHEN p.suppressed_until IS NOT NULL
            AND p.suppressed_until > CURRENT_DATE + INTERVAL '365 days' THEN 'disabled'
        WHEN p.suppressed_until IS NOT NULL
            AND p.suppressed_until > CURRENT_DATE THEN 'suppressed'
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
    'Smart Adaptive Daily Goals: Pro Insights screen feed. security_invoker = on. `user_disabled` distinguishes user-toggle-off (forever sentinel) from auto-suppression (≤14d). Used by Fit33/QuestInsightsView.swift.';


-- ── 2. set_quest_category_enabled — Pro toggle ──────────────────────────
-- Pro-only. Replaces the unsuppress-only path with an explicit
-- enable/disable lever. Disabling sets the forever sentinel; the
-- eligibility CTE in get_daily_quests v3 already excludes any
-- (user_id, category) pair with `suppressed_until > today`, so the
-- next slate will skip the disabled categories.
DROP FUNCTION IF EXISTS public.set_quest_category_enabled(TEXT, BOOLEAN, BOOLEAN);

CREATE OR REPLACE FUNCTION public.set_quest_category_enabled(
    p_category TEXT,
    p_enabled  BOOLEAN,
    p_is_pro   BOOLEAN DEFAULT FALSE
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_caller_id  UUID := auth.uid();
    v_sentinel   DATE := '2099-12-31'::DATE;
    v_rows       INT;
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

    -- The whitelist mirrors the CATEGORY DIVERSITY sweep in
    -- get_daily_quests v3 (Data invariant #30). Reject anything else
    -- so a malicious client can't poke at `wildcard` / `reward` /
    -- arbitrary strings and silently corrupt the personalization row.
    IF p_category NOT IN ('workout','nutrition','steps','social','tracking') THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'unsupported_category');
    END IF;

    IF p_enabled THEN
        -- Toggle ON: clear suppression (mirrors unsuppress_quest_category).
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
    ELSE
        -- Toggle OFF: write the forever-sentinel. UPSERT covers users
        -- who haven't yet built up a personalization row in this
        -- category (otherwise the bare UPDATE no-ops and the toggle
        -- silently doesn't take). The (user_id, category) PK is
        -- enforced by 20260601_user_quest_personalization.sql.
        INSERT INTO user_quest_personalization (
            user_id, category, suppressed_until, updated_at
        ) VALUES (
            v_caller_id, p_category, v_sentinel, now()
        )
        ON CONFLICT (user_id, category) DO UPDATE SET
            suppressed_until = v_sentinel,
            updated_at       = now();
        GET DIAGNOSTICS v_rows = ROW_COUNT;
    END IF;

    RETURN jsonb_build_object(
        'success',   TRUE,
        'category',  p_category,
        'enabled',   p_enabled,
        'rows',      v_rows
    );
END;
$$;

REVOKE ALL ON FUNCTION public.set_quest_category_enabled(TEXT, BOOLEAN, BOOLEAN) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.set_quest_category_enabled(TEXT, BOOLEAN, BOOLEAN) TO authenticated;

COMMENT ON FUNCTION public.set_quest_category_enabled(TEXT, BOOLEAN, BOOLEAN) IS
    'Daily Goals Insights (20260702): Pro toggle to include/exclude a category from the user''s daily slate. ON clears suppressed_until (matches unsuppress_quest_category). OFF writes the 2099-12-31 forever-sentinel so get_daily_quests v3 keeps the category out of the eligibility pool indefinitely. Caller MUST be authenticated AND p_is_pro=TRUE; allowed categories are the canonical 5 from the diversity sweep.';

COMMIT;

-- ─── Verification ──────────────────────────────────────────────────────
-- SELECT proname FROM pg_proc WHERE proname = 'set_quest_category_enabled';
-- SELECT user_id, category, suppressed_until, user_disabled, state
--   FROM v_user_quest_personalization_summary
--  WHERE user_id = auth.uid();
