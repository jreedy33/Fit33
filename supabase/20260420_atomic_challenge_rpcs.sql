-- ============================================================================
-- Atomic accept/decline challenge RPCs (C-6, Sprint 5 — 2026-04-20)
-- ============================================================================
--
-- Context
-- -------
-- The pre-existing `respond_to_challenge(p_challenge_id, p_accept)` RPC does
-- NOT lock the `challenge_participants` row before reading `status = 'pending'`,
-- so a rapid double-tap on the accept button could slip two UPDATE statements
-- past the idempotency check. Symptoms: "tapped accept twice, widget flashed
-- briefly showing `active` then went back to `pending`" / duplicate push
-- notifications to the creator / `group_challenges.status` flipping from
-- `active` back to `pending`.
--
-- This migration introduces atomic, idempotent siblings:
--   - `accept_challenge(p_challenge_id uuid)`  -> jsonb
--   - `decline_challenge(p_challenge_id uuid)` -> jsonb
--
-- Both functions:
--   1. Require `auth.uid()` (SECURITY DEFINER is only used so we can write to
--      `push_notification_queue` without the caller needing RLS grants on it).
--   2. Take the participant row lock via `SELECT ... FOR UPDATE` BEFORE any
--      conditional logic, so a double-submit serializes into one winner + one
--      idempotent "already_accepted" response.
--   3. Return a structured jsonb payload so the client can distinguish
--      "accepted just now" from "already accepted" and avoid firing a second
--      post-accept sync pass.
--   4. Leave `respond_to_challenge` in place for client backwards compatibility
--      (older app builds still installed).
--
-- The `_progress` variant is intentionally deferred (see C-6 in MASTER_TODO.md).

-- ============================================================================
-- accept_challenge
-- ============================================================================
CREATE OR REPLACE FUNCTION public.accept_challenge(
    p_challenge_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id uuid;
    v_participant RECORD;
    v_challenge RECORD;
    v_responder_name text;
    v_responder_username text;
    v_all_accepted boolean;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '28000';
    END IF;

    -- Atomic lock on the caller's participant row. Serializes concurrent
    -- accepts from the same user (e.g. double-tap) AND blocks concurrent
    -- cancellation of the challenge.
    SELECT cp.user_id, cp.challenge_id, cp.status
      INTO v_participant
      FROM challenge_participants cp
     WHERE cp.challenge_id = p_challenge_id
       AND cp.user_id = v_user_id
     FOR UPDATE;

    IF v_participant IS NULL THEN
        RETURN jsonb_build_object(
            'status', 'not_found',
            'message', 'Challenge not found or you are not a participant'
        );
    END IF;

    -- Idempotent fast path: already responded. Return the existing state
    -- instead of raising so the client can treat it as success.
    IF v_participant.status = 'accepted' THEN
        RETURN jsonb_build_object('status', 'already_accepted');
    ELSIF v_participant.status = 'declined' THEN
        RETURN jsonb_build_object('status', 'already_declined');
    END IF;

    -- Load the challenge (title for notification + created_by for routing)
    SELECT gc.id, gc.title, gc.status, gc.created_by
      INTO v_challenge
      FROM group_challenges gc
     WHERE gc.id = p_challenge_id
     FOR UPDATE;

    IF v_challenge IS NULL THEN
        RETURN jsonb_build_object(
            'status', 'not_found',
            'message', 'Parent challenge row missing'
        );
    END IF;

    IF v_challenge.status = 'cancelled' THEN
        RETURN jsonb_build_object('status', 'cancelled');
    END IF;

    -- Transition participant -> accepted. `challenge_participants` has no
    -- dedicated `responded_at` column today (see `challenge_rpc_functions.sql`
    -- for the canonical schema), so we rely on `status` alone — the realtime
    -- row change still carries a fresh `updated_at` from Postgres internals.
    UPDATE challenge_participants
       SET status = 'accepted'
     WHERE challenge_id = p_challenge_id
       AND user_id = v_user_id;

    -- If every participant has accepted, flip the parent to active.
    SELECT NOT EXISTS (
        SELECT 1 FROM challenge_participants
         WHERE challenge_id = p_challenge_id
           AND status = 'pending'
    ) INTO v_all_accepted;

    IF v_all_accepted AND v_challenge.status <> 'active' THEN
        UPDATE group_challenges
           SET status = 'active'
         WHERE id = p_challenge_id;
    END IF;

    -- Fire-and-forget creator notification. Wrapped so a failure here
    -- cannot cause the caller's accept to be rolled back.
    BEGIN
        SELECT name, username
          INTO v_responder_name, v_responder_username
          FROM user_profiles
         WHERE id = v_user_id;

        INSERT INTO push_notification_queue (
            recipient_user_id, notification_type, title, body, data, status, created_at
        ) VALUES (
            v_challenge.created_by,
            'challenge_accepted',
            'Challenge Accepted!',
            COALESCE(v_responder_name, v_responder_username, 'Your opponent')
                || ' is ready for "' || v_challenge.title || '"',
            jsonb_build_object(
                'type', 'challenge_accepted',
                'challenge_id', p_challenge_id::text,
                'from_user_id', v_user_id::text,
                'from_user_name', COALESCE(v_responder_name, v_responder_username)
            ),
            'pending',
            NOW()
        );
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'accept_challenge: failed to enqueue creator push: %', SQLERRM;
    END;

    RETURN jsonb_build_object(
        'status', 'accepted',
        'all_accepted', v_all_accepted,
        'challenge_status', CASE WHEN v_all_accepted THEN 'active' ELSE v_challenge.status END
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.accept_challenge(uuid) TO authenticated;

COMMENT ON FUNCTION public.accept_challenge(uuid) IS
'Atomic accept for a group/1v1 challenge invite. Serializes concurrent accepts
via SELECT FOR UPDATE on the caller''s participant row. Returns a structured
jsonb payload: {status: accepted|already_accepted|already_declined|not_found|cancelled,
all_accepted?, challenge_status?}. Sprint 5 (C-6).';

-- ============================================================================
-- decline_challenge
-- ============================================================================
CREATE OR REPLACE FUNCTION public.decline_challenge(
    p_challenge_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id uuid;
    v_participant RECORD;
    v_challenge RECORD;
    v_responder_name text;
    v_responder_username text;
    v_remaining_count integer;
    v_did_cancel boolean := false;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '28000';
    END IF;

    SELECT cp.user_id, cp.challenge_id, cp.status
      INTO v_participant
      FROM challenge_participants cp
     WHERE cp.challenge_id = p_challenge_id
       AND cp.user_id = v_user_id
     FOR UPDATE;

    IF v_participant IS NULL THEN
        RETURN jsonb_build_object(
            'status', 'not_found',
            'message', 'Challenge not found or you are not a participant'
        );
    END IF;

    IF v_participant.status = 'declined' THEN
        RETURN jsonb_build_object('status', 'already_declined');
    ELSIF v_participant.status = 'accepted' THEN
        RETURN jsonb_build_object('status', 'already_accepted');
    END IF;

    SELECT gc.id, gc.title, gc.status, gc.created_by
      INTO v_challenge
      FROM group_challenges gc
     WHERE gc.id = p_challenge_id
     FOR UPDATE;

    IF v_challenge IS NULL THEN
        RETURN jsonb_build_object(
            'status', 'not_found',
            'message', 'Parent challenge row missing'
        );
    END IF;

    UPDATE challenge_participants
       SET status = 'declined'
     WHERE challenge_id = p_challenge_id
       AND user_id = v_user_id;

    -- If only 2 participants and one declined, cancel the parent challenge.
    -- Matches the legacy `respond_to_challenge` behavior.
    SELECT COUNT(*)
      INTO v_remaining_count
      FROM challenge_participants
     WHERE challenge_id = p_challenge_id;

    IF v_remaining_count <= 2 AND v_challenge.status <> 'cancelled' THEN
        UPDATE group_challenges
           SET status = 'cancelled'
         WHERE id = p_challenge_id;
        v_did_cancel := true;
    END IF;

    BEGIN
        SELECT name, username
          INTO v_responder_name, v_responder_username
          FROM user_profiles
         WHERE id = v_user_id;

        INSERT INTO push_notification_queue (
            recipient_user_id, notification_type, title, body, data, status, created_at
        ) VALUES (
            v_challenge.created_by,
            'challenge_declined',
            'Challenge Declined',
            COALESCE(v_responder_name, v_responder_username, 'Your opponent')
                || ' passed on "' || v_challenge.title || '"',
            jsonb_build_object(
                'type', 'challenge_declined',
                'challenge_id', p_challenge_id::text,
                'from_user_id', v_user_id::text,
                'from_user_name', COALESCE(v_responder_name, v_responder_username)
            ),
            'pending',
            NOW()
        );
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'decline_challenge: failed to enqueue creator push: %', SQLERRM;
    END;

    RETURN jsonb_build_object(
        'status', 'declined',
        'cancelled', v_did_cancel,
        'challenge_status', CASE WHEN v_did_cancel THEN 'cancelled' ELSE v_challenge.status END
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.decline_challenge(uuid) TO authenticated;

COMMENT ON FUNCTION public.decline_challenge(uuid) IS
'Atomic decline for a group/1v1 challenge invite. Serializes via SELECT FOR UPDATE
on the caller''s participant row. Returns {status: declined|already_declined|
already_accepted|not_found, cancelled?, challenge_status?}. Sprint 5 (C-6).';
