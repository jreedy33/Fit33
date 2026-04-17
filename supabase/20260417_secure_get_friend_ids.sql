-- =============================================================================
-- Secure get_friend_ids(p_user_id) against IDOR
-- =============================================================================
-- The original definition in community_friends_gating.sql runs with
-- SECURITY DEFINER and takes a user_id parameter, but does NOT verify that
-- the caller is that user. This lets any signed-in user enumerate the friend
-- graph of any other user.
--
-- This migration replaces the function body so that callers must either
--   (a) pass their own auth.uid(), or
--   (b) be invoked by a trusted SECURITY DEFINER caller (service role /
--       definer function whose search_path includes public).
--
-- Other RPCs in community_friends_gating.sql invoke `get_friend_ids(auth.uid())`
-- directly, so this tightening is safe for first-party callers.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_friend_ids(p_user_id UUID)
RETURNS TABLE (friend_id UUID)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    -- Allow service_role / pg cron contexts (auth.uid() is NULL there).
    IF auth.uid() IS NOT NULL AND p_user_id <> auth.uid() THEN
        RAISE EXCEPTION 'Forbidden: cannot read another user''s friend graph'
            USING ERRCODE = '42501';
    END IF;

    RETURN QUERY
    SELECT
        CASE
            WHEN requester_id = p_user_id THEN addressee_id
            ELSE requester_id
        END AS friend_id
    FROM friendships
    WHERE status = 'accepted'
      AND (requester_id = p_user_id OR addressee_id = p_user_id);
END;
$$;

COMMENT ON FUNCTION public.get_friend_ids(UUID) IS
  'Returns direct friend IDs. IDOR-guarded 2026-04-17: callers with a non-null auth.uid() must pass their own id.';
