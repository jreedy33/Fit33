-- ============================================================================
-- Migration: Fix nudge_group_challenge_member RPC — drop dropped-column INSERT
-- Date: 2026-04-25 (Cursor Bug-Intel new export 2026-04-25T20-34-58)
-- Agent: Supabase / Data & Backend
--
-- Resolves: d8fe113b2a14b80603ca156e2ee0c990 — group_challenge_id missing column
--
-- Why:
--   `20260326_fix_nudge_column_mismatch.sql` DROPPED the legacy
--   `group_challenge_id` column from `group_challenge_nudges` after copying its
--   contents into the canonical `challenge_id` column. That migration was
--   correct, but the RPC body in `20260325_fix_nudge_overload.sql` still does
--
--     INSERT INTO group_challenge_nudges
--       (challenge_id, group_challenge_id, sender_id, recipient_id, created_at)
--     VALUES (...)
--
--   Every nudge attempt now raises Postgres `42703` ("column
--   group_challenge_id of relation group_challenge_nudges does not exist").
--   Stack: ChallengeService.swift:1563 →
--   nudge_group_challenge_member → INSERT.
--
--   The "for backward compat with old schema" comment was true at the time
--   `20260325` shipped, but the column was deleted the day after. Nothing
--   reads `group_challenge_id` any more (verified via repo grep).
--
-- Fix: re-CREATE the RPC body with only the canonical `challenge_id` column.
-- All other behaviour (RLS-friendly SECURITY DEFINER, daily de-dup,
-- push_notification_queue insert wrapped in EXCEPTION-WHEN-OTHERS) is
-- preserved verbatim.
--
-- Idempotent: drops every existing overload via the canonical pg_proc loop
-- (Supabase invariant 12) before CREATE OR REPLACE; ends with a `DO $$`
-- audit that the post-migration `pg_proc` count for the function name equals
-- 1 (Supabase invariant 28).
-- ============================================================================

BEGIN;

-- Drop every overload (TEXT,TEXT) and (UUID,UUID) variants created over
-- the years of nudge schema churn. Canonical signature stays (TEXT,TEXT)
-- because the iOS client (ChallengeService.swift:1559–1564) sends UUIDs
-- as `.uuidString` and PostgREST passes them as TEXT.
DO $$
DECLARE
    v_sig TEXT;
BEGIN
    FOR v_sig IN
        SELECT oid::regprocedure::text
        FROM pg_proc
        WHERE proname = 'nudge_group_challenge_member'
          AND pronamespace = 'public'::regnamespace
    LOOP
        EXECUTE 'DROP FUNCTION IF EXISTS ' || v_sig || ' CASCADE';
    END LOOP;
END $$;

CREATE OR REPLACE FUNCTION nudge_group_challenge_member(
    p_challenge_id TEXT,
    p_recipient_id TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    current_user_uuid UUID;
    challenge_uuid    UUID;
    recipient_uuid    UUID;
    sender_name       TEXT;
    challenge_title   TEXT;
BEGIN
    current_user_uuid := auth.uid();
    challenge_uuid    := p_challenge_id::UUID;
    recipient_uuid    := p_recipient_id::UUID;

    -- Daily de-dup: only one nudge per (challenge, sender, recipient) per day.
    IF EXISTS (
        SELECT 1 FROM group_challenge_nudges
        WHERE challenge_id = challenge_uuid
          AND sender_id    = current_user_uuid
          AND recipient_id = recipient_uuid
          AND created_at   > CURRENT_DATE
    ) THEN
        RETURN FALSE;
    END IF;

    -- Canonical schema after 20260326_fix_nudge_column_mismatch — only
    -- challenge_id exists. The legacy group_challenge_id column was dropped.
    INSERT INTO group_challenge_nudges
        (challenge_id, sender_id, recipient_id, created_at)
    VALUES
        (challenge_uuid, current_user_uuid, recipient_uuid, NOW());

    SELECT name  INTO sender_name     FROM user_profiles    WHERE id = current_user_uuid;
    SELECT title INTO challenge_title FROM group_challenges WHERE id = challenge_uuid;

    -- Push queue is best-effort; recipient still sees the nudge in-app.
    BEGIN
        INSERT INTO push_notification_queue (
            recipient_user_id, notification_type, title, body, data, status, created_at
        ) VALUES (
            recipient_uuid,
            'challenge_nudge',
            COALESCE(sender_name, 'Someone') || ' nudged you!',
            'Don''t forget your "' || COALESCE(challenge_title, 'challenge') || '" goal today!',
            jsonb_build_object(
                'type',         'challenge_nudge',
                'challenge_id', challenge_uuid::TEXT,
                'from_user_id', current_user_uuid::TEXT
            ),
            'pending',
            NOW()
        );
    EXCEPTION WHEN OTHERS THEN
        NULL;
    END;

    RETURN TRUE;
END;
$$;

GRANT EXECUTE ON FUNCTION nudge_group_challenge_member(TEXT, TEXT) TO authenticated;

-- Supabase invariant 28 — fail-loud overload count audit.
DO $$
DECLARE
    v_count INT;
BEGIN
    SELECT COUNT(*) INTO v_count
    FROM pg_proc
    WHERE proname = 'nudge_group_challenge_member'
      AND pronamespace = 'public'::regnamespace;

    IF v_count <> 1 THEN
        RAISE EXCEPTION
            'nudge_group_challenge_member overload audit failed: expected 1 function, found %',
            v_count;
    END IF;

    RAISE NOTICE 'nudge_group_challenge_member overload audit OK — exactly 1 definition';
END $$;

COMMIT;
