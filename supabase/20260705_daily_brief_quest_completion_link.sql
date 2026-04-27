-- ============================================================================
-- Migration: daily_brief_impressions — quest completion link
-- Filename: 20260705_daily_brief_quest_completion_link.sql
-- Date: 2026-04-27 (Daily Mission Unification — Phase 6)
-- Agent: Supabase / Data & Backend
--
-- NOTE: filename uses date 20260705 because 20260704 was already taken
-- by `20260704_dedupe_exercise_performance_history.sql` (a separate
-- bug-fix migration that landed earlier on the same calendar day).
-- The migration index gives this entry its own number — see
-- `supabase/MIGRATION_INDEX.md` entry #133.
--
-- WHY:
--   Phase 1 (20260703) wired the Daily Brief's Decision into the quest RPC.
--   Phase 6 closes the measurement loop by tracking which quests on a
--   given brief impression actually got completed. Without this column,
--   `daily_brief_impressions` only knows "we showed brief X" and "user
--   tapped it Y times" — but not "did the brief actually drive a quest
--   to completion?". The latter is the gold metric for iterating the
--   `DailyBriefTemplates.swift` table.
--
-- WHAT:
--   Adds two columns to `daily_brief_impressions`:
--     * completed_quest_keys TEXT[] — quest keys (from the brief's
--       linked_quest_keys) that the user actually finished within the
--       impression's lifetime (today + tomorrow morning).
--     * completed_at TIMESTAMPTZ — when the FIRST linked quest completed
--       (NULL until the user finishes one). Lets us compute brief →
--       conversion latency per template family.
--   Plus one signature column for analytics grouping:
--     * decision_signature TEXT — short string of the form
--       `<band>|<debt>|<goal>` so analytics can group impressions by
--       Decision-shape, not just template-shape (the brief copy can
--       evolve while the underlying Decision stays stable).
--
--   iOS-side hook is `BriefTelemetry.logQuestCompletion(impressionId:
--   questKey:)`, called from `DailyQuestService` whenever a quest in
--   the latest impression's linkedQuestKeys ticks complete. Updates
--   the impression row in place via a small SECURITY DEFINER RPC.
--
-- INVARIANTS RESPECTED:
--   - Supabase 17: BEGIN/COMMIT, idempotent, IF NOT EXISTS / IF EXISTS
--   - Data 7: SECURITY DEFINER RPC pinned to auth.uid()
--   - Data 17: append-only INSERT path stays untouched (we extend the
--     table, never break the existing iOS BriefTelemetry.logImpression).
--
-- ROLLBACK:
--   ALTER TABLE daily_brief_impressions DROP COLUMN completed_quest_keys;
--   ALTER TABLE daily_brief_impressions DROP COLUMN completed_at;
--   ALTER TABLE daily_brief_impressions DROP COLUMN decision_signature;
--   DROP FUNCTION public.append_brief_completed_quest;
-- ============================================================================

BEGIN;

-- ── 1. Schema: extend `daily_brief_impressions` ─────────────────────────
ALTER TABLE public.daily_brief_impressions
    ADD COLUMN IF NOT EXISTS completed_quest_keys TEXT[],
    ADD COLUMN IF NOT EXISTS completed_at         TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS decision_signature   TEXT;

-- Partial index on impressions that have at least one completed quest —
-- speeds up the "conversion-by-template" analytics query without
-- bloating the main hot-path indexes.
CREATE INDEX IF NOT EXISTS idx_daily_brief_impressions_completed
    ON public.daily_brief_impressions (decision_signature, completed_at DESC)
    WHERE completed_at IS NOT NULL;

COMMENT ON COLUMN public.daily_brief_impressions.completed_quest_keys IS
    'Phase 6 (20260705): quest keys (subset of decision.linked_quest_keys) the user completed within this impression''s lifetime. Append-only via append_brief_completed_quest RPC; never overwritten.';
COMMENT ON COLUMN public.daily_brief_impressions.completed_at IS
    'Phase 6 (20260705): timestamp the FIRST linked quest completed. NULL until conversion. Used for brief → completion latency.';
COMMENT ON COLUMN public.daily_brief_impressions.decision_signature IS
    'Phase 6 (20260705): short hash-shaped string `<band>|<debt>|<goal>` used by analytics to group impressions by Decision-shape, not just template-shape.';

-- ── 2. RPC: append_brief_completed_quest ─────────────────────────────────
-- Appends a quest_key to `completed_quest_keys` and stamps `completed_at`
-- on first append. Idempotent via array_append-with-NOT-IN guard so
-- multiple completions of the same quest within a session don't double-
-- log. Auth-pinned (Data invariant 7) — caller must own the impression.
DROP FUNCTION IF EXISTS public.append_brief_completed_quest(UUID, TEXT);

CREATE OR REPLACE FUNCTION public.append_brief_completed_quest(
    p_impression_id UUID,
    p_quest_key     TEXT
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_caller_id   UUID := auth.uid();
    v_owner_id    UUID;
    v_already     BOOLEAN := FALSE;
BEGIN
    IF v_caller_id IS NULL THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'not_authenticated');
    END IF;
    IF p_impression_id IS NULL OR p_quest_key IS NULL OR length(p_quest_key) = 0 THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'missing_args');
    END IF;

    -- IDOR guard: only the impression's owner can append to it. The
    -- table's own RLS would also block this, but we re-check here so
    -- the SECURITY DEFINER context can return a structured rejection
    -- instead of a Postgres error.
    SELECT user_id INTO v_owner_id
    FROM daily_brief_impressions
    WHERE id = p_impression_id;

    IF v_owner_id IS NULL THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'not_found');
    END IF;

    IF v_owner_id <> v_caller_id THEN
        RAISE EXCEPTION 'append_brief_completed_quest IDOR: caller % does not own impression %',
            v_caller_id, p_impression_id
            USING ERRCODE = '42501';
    END IF;

    -- Dedup: skip if quest_key is already in the array. Append + stamp
    -- completed_at on the first ever append.
    SELECT (p_quest_key = ANY(COALESCE(completed_quest_keys, '{}'::TEXT[])))
      INTO v_already
    FROM daily_brief_impressions
    WHERE id = p_impression_id;

    IF v_already THEN
        RETURN jsonb_build_object('success', TRUE, 'already_logged', TRUE);
    END IF;

    UPDATE daily_brief_impressions
       SET completed_quest_keys = array_append(
                                      COALESCE(completed_quest_keys, '{}'::TEXT[]),
                                      p_quest_key
                                  ),
           completed_at = COALESCE(completed_at, now())
     WHERE id = p_impression_id;

    RETURN jsonb_build_object('success', TRUE);
END;
$$;

REVOKE ALL ON FUNCTION public.append_brief_completed_quest(UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.append_brief_completed_quest(UUID, TEXT) TO authenticated;

COMMENT ON FUNCTION public.append_brief_completed_quest(UUID, TEXT) IS
    'Phase 6 (Daily Mission Unification, 20260705): SECURITY DEFINER RPC that appends a quest_key to daily_brief_impressions.completed_quest_keys and stamps completed_at on first append. IDOR-guarded by checking the impression''s owner against auth.uid(). Idempotent — re-appending the same key returns already_logged=true. iOS callers wire this from DailyBriefStore''s Combine sub on DailyQuestService.$quests when a quest in linkedQuestKeys ticks complete.';

COMMIT;

-- ─── Verification ──────────────────────────────────────────────────────
-- Spot-check after iOS lands the first conversion:
--
-- SELECT id, decision_signature, completed_quest_keys, completed_at,
--        EXTRACT(EPOCH FROM (completed_at - surfaced_at)) AS latency_sec
--   FROM daily_brief_impressions
--  WHERE user_id = auth.uid()
--    AND completed_at IS NOT NULL
--  ORDER BY completed_at DESC
--  LIMIT 5;
--
-- Conversion funnel by decision signature:
--
-- SELECT decision_signature,
--        COUNT(*) AS impressions,
--        COUNT(*) FILTER (WHERE completed_at IS NOT NULL) AS converted,
--        ROUND(100.0 * COUNT(*) FILTER (WHERE completed_at IS NOT NULL) / COUNT(*), 1) AS conv_pct
--   FROM daily_brief_impressions
--  WHERE surfaced_at > NOW() - INTERVAL '14 days'
--    AND decision_signature IS NOT NULL
--  GROUP BY 1
--  ORDER BY impressions DESC;
