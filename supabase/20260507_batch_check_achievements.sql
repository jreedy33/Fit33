-- Migration: Batch achievement check / unlock — single round-trip RPC
-- Date: 2026-05-07
-- Sprint: Snappiness Overhaul Phase 5.D (PerfFlags.phase5BatchAchievements)
--
-- Why:
--   `BadgeService` today fans out 15-24+ serial `unlock_achievement` RPCs
--   per call site. The cold-start `resyncOlympianProgressFromLocalTotals`
--   plus `onWorkoutCompleted` / `onMealLogged` / `onStreakUpdated` etc.
--   each issue one RPC per achievement key, then `await fetchAchievements()`
--   inside the depth=0 path. Cold-start logs show 24 cancelled
--   `unlock_achievement` RPCs per launch (cancelled when the user navigates
--   before the chain finishes). Net: ~3.6s of wasted network bandwidth
--   per cold start AND per workout-finish flow.
--
--   This RPC accepts an array of (key, progress) pairs and returns one row
--   per requested key with full unlock state, replacing N round-trips with
--   one. The iOS Phase 5.D integration in `Fit33/AchievementService.swift`
--   keeps the per-key fan-out as the off-flag fallback.
--
-- Side-effect parity contract (vs `unlock_achievement` from
-- `20260504_olympian_path.sql` §6 — REPLICATED inside the per-key LOOP):
--   1. Upsert into `user_achievements` with GREATEST() progress semantics
--      (never regresses progress; matches single-RPC behavior).
--   2. On threshold-met-and-not-yet-unlocked: stamp `unlocked_at = NOW()`
--      via a follow-up UPDATE so the returned row reflects the timestamp.
--   3. Award `xp_reward` to `user_profiles.xp` on the unlock transition.
--   4. Tail-call `complete_olympian_season_if_done(season_year)` only when
--      a row newly unlocked AND has `season_year IS NOT NULL`.
--
-- IDOR posture (SUPABASE invariant 9):
--   SECURITY DEFINER + `auth.uid()`-pinned. NEVER accepts a `p_user_id`
--   parameter. Service-role / pg_cron callers fail-closed (caller must
--   have a valid `auth.uid()`).
--
-- Partial-failure tolerance (per the parity-test contract):
--   Each per-key iteration is wrapped in `BEGIN ... EXCEPTION WHEN OTHERS`
--   so a single bad key (constraint violation, retired achievement, race
--   on the unique upsert) returns a defensive row with `is_unlocked=FALSE`
--   instead of tanking the entire batch. Unknown keys (no row in
--   `achievements`) emit a row with `is_unlocked=FALSE` exactly like the
--   single-RPC equivalent (`NOT FOUND` branch in the original).
--
-- Related fingerprints (already drained by Phase C's NetworkErrorClassifier
-- routing in `20260504_bug_intel_inbox_drain.sql` row #191 — listed here
-- for traceability only, NOT as `Resolves:` directives because they're
-- already in `resolved` status):
--   `40779673`, `5c5d0f3c`, `43add712`, `a7b890fd`, `3840b05d`, `a5e13a94`,
--   `dfb5892d`, `8a3fbd08`, `878468de` — the cancelled-`unlock_achievement`
--   `.warning` cluster (357+ occ × 4 users on build 1.39 (68)). This
--   migration ELIMINATES the underlying fan-out so the warnings stop
--   manufacturing noise rather than just being downgraded to warnings.
--
-- Idempotency: full overload-collapse via the canonical `pg_proc` loop
-- before `CREATE FUNCTION`, idempotent `BEGIN; ... COMMIT;`, audit block
-- that fails loud on count drift, ends with `NOTIFY pgrst, 'reload schema'`
-- (SUPABASE invariant 19b) so iOS can call the new RPC the moment commit
-- lands.

BEGIN;

-- ============================================================================
-- 1. DROP all overloads (canonical pg_proc loop — supabase-rules §12)
-- ============================================================================

DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN (
        SELECT n.nspname, p.proname, oidvectortypes(p.proargtypes) AS args
          FROM pg_proc p
          JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname = 'public'
           AND p.proname = 'batch_check_achievements'
    ) LOOP
        EXECUTE format('DROP FUNCTION IF EXISTS %I.%I(%s)', r.nspname, r.proname, r.args);
    END LOOP;
END$$;

-- ============================================================================
-- 2. CREATE batch_check_achievements
-- ============================================================================
--
-- Signature notes:
--   • `p_progress_values` is OPTIONAL (defaults to NULL). When NULL, every
--     key uses progress=1 (matches the `checkAndUnlock(key:)` default in
--     `BadgeService`). When supplied, length MUST equal `p_achievement_keys`
--     length; mismatch raises 22023 invalid_parameter_value.
--   • The 200-key cap is defense-in-depth — the largest legitimate caller
--     (`resyncOlympianProgressFromLocalTotals`) emits ~50 keys total
--     across its 5 fan-outs; 200 is an order-of-magnitude safety margin
--     against a runaway client batch.

CREATE FUNCTION batch_check_achievements(
    p_achievement_keys TEXT[],
    p_progress_values  INT[] DEFAULT NULL
) RETURNS TABLE (
    achievement_key    TEXT,
    progress_value     INT,
    is_unlocked        BOOLEAN,
    unlocked_at        TIMESTAMPTZ,
    just_unlocked      BOOLEAN,
    achievement_title  TEXT,
    achievement_icon   TEXT,
    achievement_rarity TEXT,
    xp_reward          INT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    current_user_uuid UUID;
    v_keys_count      INT;
    v_progress_count  INT;
    v_idx             INT;
    v_key             TEXT;
    v_input_progress  INT;
    v_achievement     RECORD;
    v_user_achv       RECORD;
    v_just_unlocked   BOOLEAN;
BEGIN
    -- IDOR gate (SUPABASE invariant 9). Mirrors `unlock_achievement`'s
    -- top-of-function check exactly. Service-role callers without a
    -- session JWT fail closed here.
    current_user_uuid := auth.uid();
    IF current_user_uuid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '42501';
    END IF;

    IF p_achievement_keys IS NULL THEN
        RETURN;
    END IF;

    v_keys_count := array_length(p_achievement_keys, 1);
    IF COALESCE(v_keys_count, 0) = 0 THEN
        RETURN;
    END IF;

    IF v_keys_count > 200 THEN
        RAISE EXCEPTION 'p_achievement_keys length % exceeds limit 200', v_keys_count
            USING ERRCODE = '22023';
    END IF;

    v_progress_count := COALESCE(array_length(p_progress_values, 1), 0);
    IF p_progress_values IS NOT NULL AND v_progress_count <> v_keys_count THEN
        RAISE EXCEPTION
            'p_progress_values length (%) must match p_achievement_keys length (%)',
            v_progress_count, v_keys_count
            USING ERRCODE = '22023';
    END IF;

    FOR v_idx IN 1..v_keys_count LOOP
        v_key            := p_achievement_keys[v_idx];
        v_input_progress := COALESCE(p_progress_values[v_idx], 1);
        v_just_unlocked  := FALSE;

        IF v_key IS NULL OR length(trim(v_key)) = 0 THEN
            -- Defensive: empty / null keys are silently skipped (no row
            -- emitted) so a malformed batch row doesn't pollute the
            -- iOS-side reconciliation map.
            CONTINUE;
        END IF;

        IF v_input_progress < 0 THEN
            -- Negative progress is meaningless under GREATEST() semantics.
            -- Clamp to 0 rather than raise, since the iOS caller may
            -- have sent a stale Core Data total that briefly underflowed.
            v_input_progress := 0;
        END IF;

        BEGIN
            SELECT * INTO v_achievement
              FROM achievements
             WHERE key = v_key;

            IF NOT FOUND THEN
                -- Mirrors the `unlock_achievement` `NOT FOUND` branch:
                -- emit a "no-such-key" row so the iOS caller can log /
                -- skip per-key without all-or-nothing failure semantics.
                achievement_key    := v_key;
                progress_value     := 0;
                is_unlocked        := FALSE;
                unlocked_at        := NULL;
                just_unlocked      := FALSE;
                achievement_title  := NULL;
                achievement_icon   := NULL;
                achievement_rarity := NULL;
                xp_reward          := 0;
                RETURN NEXT;
                CONTINUE;
            END IF;

            -- Side effect 1: GREATEST upsert into user_achievements.
            -- IDENTICAL semantics to `unlock_achievement` so callers
            -- get the exact same stored progress regardless of which
            -- RPC variant they used.
            INSERT INTO user_achievements (user_id, achievement_id, progress)
            VALUES (current_user_uuid, v_achievement.id, v_input_progress)
            ON CONFLICT (user_id, achievement_id) DO UPDATE
                SET progress = GREATEST(user_achievements.progress, EXCLUDED.progress)
            RETURNING * INTO v_user_achv;

            -- Side effects 2 + 3: stamp `unlocked_at` and award XP on the
            -- threshold-crossing transition. Re-fetch via UPDATE...RETURNING
            -- so the emitted row reflects the new timestamp instead of
            -- the pre-update NULL.
            IF v_user_achv.progress >= v_achievement.threshold
               AND v_user_achv.unlocked_at IS NULL THEN
                UPDATE user_achievements
                   SET unlocked_at = NOW()
                 WHERE id = v_user_achv.id
             RETURNING * INTO v_user_achv;

                IF v_achievement.xp_reward > 0 THEN
                    UPDATE user_profiles
                       SET xp = COALESCE(xp, 0) + v_achievement.xp_reward
                     WHERE id = current_user_uuid;
                END IF;

                v_just_unlocked := TRUE;
            END IF;

            -- Side effect 4: tail-call to mint the Olympian season badge
            -- when all 33 goals are now unlocked. Mirrors
            -- `unlock_achievement` exactly — only fires on the
            -- newly-unlocked transition AND only for rows tagged with a
            -- `season_year`.
            IF v_just_unlocked AND v_achievement.season_year IS NOT NULL THEN
                PERFORM complete_olympian_season_if_done(v_achievement.season_year);
            END IF;

            achievement_key    := v_key;
            progress_value     := v_user_achv.progress;
            is_unlocked        := v_user_achv.unlocked_at IS NOT NULL;
            unlocked_at        := v_user_achv.unlocked_at;
            just_unlocked      := v_just_unlocked;
            achievement_title  := v_achievement.title;
            achievement_icon   := v_achievement.icon;
            achievement_rarity := v_achievement.rarity;
            -- Match `unlock_achievement`: xp_reward is only > 0 when this
            -- call performed the unlock transition.
            xp_reward          := CASE
                                    WHEN v_just_unlocked THEN v_achievement.xp_reward
                                    ELSE 0
                                  END;
            RETURN NEXT;

        EXCEPTION
            WHEN OTHERS THEN
                -- Per-key isolation: a single bad row (constraint
                -- violation, race, etc.) MUST NOT abort the loop.
                -- Emit a defensive row + WARNING so the iOS caller
                -- still gets one row per requested key and the server
                -- log captures the failure for bug-intel triage.
                RAISE WARNING 'batch_check_achievements: key % failed: %',
                    v_key, SQLERRM;
                achievement_key    := v_key;
                progress_value     := 0;
                is_unlocked        := FALSE;
                unlocked_at        := NULL;
                just_unlocked      := FALSE;
                achievement_title  := NULL;
                achievement_icon   := NULL;
                achievement_rarity := NULL;
                xp_reward          := 0;
                RETURN NEXT;
        END;
    END LOOP;

    RETURN;
END;
$$;

GRANT EXECUTE ON FUNCTION batch_check_achievements(TEXT[], INT[]) TO authenticated;

-- ============================================================================
-- 3. AUDIT — exactly one definition deployed (supabase-rules §12 + §28)
-- ============================================================================

DO $$
DECLARE
    v_count INT;
BEGIN
    SELECT COUNT(*) INTO v_count
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public'
       AND p.proname = 'batch_check_achievements';

    IF v_count <> 1 THEN
        RAISE EXCEPTION
            'batch_check_achievements overload-collapse failed: expected 1 def, found %',
            v_count;
    END IF;

    RAISE NOTICE 'batch_check_achievements: 1 definition deployed (overload-collapse OK)';
END$$;

-- ============================================================================
-- 4. SCHEMA-CACHE RELOAD (SUPABASE invariant 19b)
-- ============================================================================
--
-- New function → PostgREST schema cache MUST be invalidated immediately,
-- otherwise the iOS client hits PGRST202 ("Could not find the function")
-- for the 5-12min until the next periodic refresh, manufacturing per-launch
-- bug-intel fingerprints. NOTIFY is a no-op when cache is already current.

NOTIFY pgrst, 'reload schema';

COMMIT;
