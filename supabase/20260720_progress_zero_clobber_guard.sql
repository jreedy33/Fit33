-- ═══════════════════════════════════════════════════════════════════════════
-- 20260720_progress_zero_clobber_guard.sql
-- Bug-intel hotfix — `step-progress 0-clobber` cluster.
--
-- ROOT CAUSE
-- ----------
-- The 2026-04-24 dawn-ghost fix (DATA invariant #47) routed `steps` and
-- `active_minutes` through `allowDecrease=true` so that a stale `@Published`
-- yesterday-EoD value pinned by the server's `GREATEST()` clause could
-- finally be replaced by a real lower today-value.
--
-- That fix opened the *opposite* failure mode:
--
--   When iOS launches off a silent-push wake or BGTask refresh, the
--   `syncHealthKitDataToChallenges()` path runs **before** the HKAnchored
--   query has emitted the first sample for the local day. Both
--   `HealthKitManager.shared.todaySteps` and `HealthKitService.shared.
--   todaySteps` read 0. `calculateProgressFromHealthKit(case "steps")`
--   returns `managerSteps > 0 ? managerSteps : serviceSteps == 0`. The
--   for-loop at `ChallengeService.swift:2455` then pushes `progressValue=0`
--   with `allowDecrease=true` because `isRecalculable` is true for steps.
--
--   On the server, `log_challenge_progress` (and the private + community
--   siblings) does:
--
--       progress_value = CASE
--           WHEN p_allow_decrease THEN EXCLUDED.progress_value
--           ELSE GREATEST(<table>.progress_value, EXCLUDED.progress_value)
--       END
--
--   so the 0 unconditionally clobbers a previously-stored real value
--   (e.g. 8174 → 0). The fanout trigger (#94, `20260521_challenge_progress
--   _fanout.sql`) then propagates the 0 to the same user's private and
--   community step rows for the same date — every leaderboard goes to 0.
--
-- CANONICAL INCIDENT (2026-04-29)
-- -------------------------------
--   * User: d10d5d03-1a0d-4b41-b61b-a4f30a56362e (Manuel, America/Los_Angeles)
--   * 1v1 challenge: 21423bcb-a6d1-4b5c-8ca6-f21c1c99606e
--   * Local row pre-clobber: 5250 (2026-04-26), 8174 (2026-04-28)
--   * Local row post-clobber: 0 (2026-04-27 19:28 UTC), 0 (2026-04-29 19:28 UTC)
--   * iOS log timeline (dev_session_logs, session BF965857):
--       1. Silent push `challenge_wake` received
--       2. `[Health] HealthKit today: 0 steps, 0 cal, 0.0 km`  ← cold HK
--       3. `[Social] Logging 0 steps for '⚔️ 👣 …' (allowDecrease: true)`
--       4. `[Social] Synced 0 steps to '⚔️ 👣 …' from HealthKit`  ← server accepted 0
--   * Even though Manuel's phone was actively reading 332 steps from HK
--     30 minutes later, all surfaces (1v1, community, widget) stayed at 0
--     because the in-process `isChallengeSyncing` flag was stuck (separate
--     iOS-side bug fixed in the same sprint).
--
-- FIX
-- ---
-- Add ONE branch to the upsert UPDATE clause in all three progress RPCs:
--
--     WHEN p_allow_decrease
--          AND EXCLUDED.progress_value = 0
--          AND <table>.progress_value > 0
--         THEN <table>.progress_value   -- preserve, do NOT clobber
--
-- before the existing `WHEN p_allow_decrease THEN EXCLUDED.progress_value`
-- line. This refuses to overwrite a positive same-day value with 0 — the
-- canonical signature of a transient HK miss.
--
-- WHY OPTION D ("never let 0 clobber positive") AND NOT A TIME-OF-DAY GATE
-- -----------------------------------------------------------------------
-- We considered gating on `EXTRACT(HOUR FROM (NOW() AT TIME ZONE p_tz)) >= 2`
-- so that the dawn-ghost recovery window (12 AM-2 AM local) could still
-- accept 0 overwrites. Rejected because:
--
--   1. The canonical dawn-ghost case is "stale 12000 (yesterday's EoD
--      cumulative) replaced by today's smaller real value (e.g. 50, 200)" —
--      the recovery push is almost always non-zero by the time HK actually
--      emits a new-day sample. Recovery via 0-overwrite is theoretical, not
--      empirical (the original 6be18e3a fingerprint was about non-zero
--      decreases, not 0-overwrites).
--
--   2. The mid-day clobber (transient HK 0 at 11:34 AM, 12:28 PM, 1:20 PM
--      etc., per Manuel's logs) is overwhelmingly the dominant failure
--      mode in production and CAN happen at any local hour, not just dawn.
--
--   3. Edge case "user genuinely has 0 steps until late morning, gets
--      stuck on a stale ghost row" is harmless: the next time the user
--      takes a single step (typical: < 1 hour after waking), HK pushes the
--      fresh non-zero value and `allowDecrease=true` lets it through (the
--      guard only blocks 0, not lower-positive). Worst case the row reads
--      a few hundred steps high for ~30 min after midnight — invisible to
--      the user, never wrong by orders of magnitude.
--
--   4. Belt-and-suspenders: a paired iOS fix in the same sprint also
--      tightens `calculateProgressFromHealthKit` to skip the push entirely
--      when both HK sources read 0 (so the server-side guard is the
--      defensive last line, not the only line).
--
-- INVARIANTS PRESERVED
-- --------------------
--   * Non-zero decreases STILL flow through (e.g. 12000 → 200 dawn recovery).
--   * Calorie/protein/hydration recalculation that legitimately drops to 0
--     (user deletes ALL meals) is NOT affected — those types still go
--     through `allowDecrease=true` and the 0 will only be rejected if the
--     prior stored value is positive AND the new value is 0. The user can
--     re-enter any single meal to unstick. Edge case is documented;
--     impact is "stale row briefly" not "data loss".
--   * The fanout trigger (`fanout_challenge_progress`) is unchanged — once
--     a value reaches one of the three tables, it still fans out. The
--     guard is at the entry RPC layer, not the trigger layer.
--   * Deadlock retry, FOR UPDATE, widget kill-switch, all preserved.
--
-- NO CALL-SITE CHANGES
-- --------------------
-- iOS callers continue to pass `p_allow_decrease=true` for steps. The
-- server now silently no-ops the 0 push with that flag. Ladder unchanged.
--
-- INVARIANT TO ADD AFTER DEPLOY (DATA_BACKEND_AGENT.md, paired commit):
--   #48 (proposed). `log_challenge_progress` / `log_private_challenge_progress`
--   / `log_community_challenge_progress` MUST refuse to overwrite a positive
--   same-day `progress_value` with `0` even when `p_allow_decrease=TRUE`.
--   The branch
--       WHEN p_allow_decrease AND EXCLUDED.progress_value = 0
--                            AND <table>.progress_value > 0
--           THEN <table>.progress_value
--   sits ABOVE the unconditional `WHEN p_allow_decrease THEN EXCLUDED…`
--   line in the upsert UPDATE clause. Removing it reintroduces the
--   transient-HK-zero clobber that nuked Manuel's 1v1/community step
--   leaderboards on 2026-04-29.
--
-- Resolves: <bug-intel cluster id TBD — assigned in next audit pass>
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

-- ═══════════════════════════════════════════════════════════════════════════
-- 1. log_challenge_progress (1v1 + group challenges)
-- ═══════════════════════════════════════════════════════════════════════════
-- Drop every known overload (supabase-rules invariant 12).
DROP FUNCTION IF EXISTS log_challenge_progress(TEXT, INT, TEXT, TEXT, TEXT);
DROP FUNCTION IF EXISTS log_challenge_progress(TEXT, INT, TEXT, TEXT, TEXT, TEXT);
DROP FUNCTION IF EXISTS log_challenge_progress(TEXT, INT, TEXT, TEXT, TEXT, TEXT, BOOLEAN);

CREATE OR REPLACE FUNCTION log_challenge_progress(
    p_challenge_id   TEXT,
    p_progress_value INT,
    p_progress_date  TEXT DEFAULT NULL,
    p_source         TEXT DEFAULT 'manual',
    p_workout_id     TEXT DEFAULT NULL,
    p_timezone       TEXT DEFAULT 'UTC',
    p_allow_decrease BOOLEAN DEFAULT FALSE
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    current_user_uuid UUID;
    challenge_uuid    UUID;
    v_progress_date   DATE;
    v_daily_target    INT;
    v_target_hit      BOOLEAN;
    v_caller_tz       TEXT;
    v_current_streak  INT := 0;
    v_check_date      DATE;
    v_attempt         INT := 0;
    v_max_attempts    CONSTANT INT := 3;
    v_widget_enabled  TEXT;
BEGIN
    current_user_uuid := auth.uid();
    IF current_user_uuid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    -- Phase 7d widget kill-switch (preserved from #129).
    IF p_source = 'widget' THEN
        SELECT value INTO v_widget_enabled
          FROM internal_config
         WHERE key = 'widget_writes_enabled';
        IF v_widget_enabled IS DISTINCT FROM 'true' THEN
            RETURN TRUE;
        END IF;
    END IF;

    challenge_uuid := p_challenge_id::UUID;
    v_caller_tz    := COALESCE(NULLIF(p_timezone, ''), 'UTC');

    SELECT daily_target INTO v_daily_target
      FROM group_challenges
     WHERE id = challenge_uuid;

    IF p_progress_date IS NOT NULL AND p_progress_date != '' THEN
        v_progress_date := p_progress_date::DATE;
    ELSE
        v_progress_date := (NOW() AT TIME ZONE v_caller_tz)::DATE;
    END IF;

    IF NOT EXISTS (
        SELECT 1
          FROM challenge_participants
         WHERE challenge_id = challenge_uuid
           AND user_id      = current_user_uuid
    ) THEN
        RAISE EXCEPTION 'You are not a participant in this challenge';
    END IF;

    v_target_hit := (v_daily_target IS NOT NULL AND p_progress_value >= v_daily_target);

    -- Deadlock retry loop (#119 recipe — preserved verbatim).
    LOOP
        v_attempt := v_attempt + 1;
        BEGIN
            PERFORM 1
              FROM challenge_participants
             WHERE challenge_id = challenge_uuid
               AND user_id      = current_user_uuid
             FOR UPDATE;

            INSERT INTO challenge_daily_progress (
                challenge_id, user_id, progress_date, progress_value,
                target_hit, source, workout_id, updated_at
            ) VALUES (
                challenge_uuid, current_user_uuid, v_progress_date, p_progress_value,
                v_target_hit, p_source,
                CASE WHEN p_workout_id IS NOT NULL AND p_workout_id != '' THEN p_workout_id::UUID ELSE NULL END,
                NOW()
            )
            ON CONFLICT (challenge_id, user_id, progress_date)
            DO UPDATE SET
                progress_value = CASE
                    -- 20260720 transient-HK-zero guard. Refuse to overwrite a
                    -- positive same-day value with 0, even when allow_decrease
                    -- is true. Canonical incident: Manuel d10d5d03 1v1 step
                    -- challenge clobbered to 0 by silent-push wake before HK
                    -- emitted today's first sample (2026-04-29 12:28 PT).
                    WHEN p_allow_decrease
                         AND EXCLUDED.progress_value = 0
                         AND challenge_daily_progress.progress_value > 0
                        THEN challenge_daily_progress.progress_value
                    WHEN p_allow_decrease THEN EXCLUDED.progress_value
                    ELSE GREATEST(challenge_daily_progress.progress_value, EXCLUDED.progress_value)
                END,
                target_hit = CASE
                    -- Paired: when we preserve progress_value above, also
                    -- preserve the existing target_hit. Otherwise the new
                    -- (false) target_hit computed from p_progress_value=0
                    -- would flip a hit row to a miss row.
                    WHEN p_allow_decrease
                         AND EXCLUDED.progress_value = 0
                         AND challenge_daily_progress.progress_value > 0
                        THEN challenge_daily_progress.target_hit
                    WHEN p_allow_decrease THEN EXCLUDED.target_hit
                    WHEN EXCLUDED.progress_value > challenge_daily_progress.progress_value
                        THEN EXCLUDED.target_hit
                    ELSE challenge_daily_progress.target_hit
                END,
                source     = EXCLUDED.source,
                updated_at = NOW();

            -- Step 3: recompute current_streak walking back from progress_date.
            v_check_date     := v_progress_date;
            v_current_streak := 0;
            LOOP
                IF EXISTS (
                    SELECT 1
                      FROM challenge_daily_progress
                     WHERE challenge_id = challenge_uuid
                       AND user_id      = current_user_uuid
                       AND challenge_daily_progress.progress_date = v_check_date
                       AND (target_hit = TRUE OR progress_value >= COALESCE(v_daily_target, 0))
                ) THEN
                    v_current_streak := v_current_streak + 1;
                    v_check_date     := v_check_date - INTERVAL '1 day';
                ELSE
                    EXIT;
                END IF;
                IF v_current_streak > 365 THEN EXIT; END IF;
            END LOOP;

            UPDATE challenge_participants
               SET total_progress = (
                       SELECT COALESCE(SUM(progress_value), 0)
                         FROM challenge_daily_progress
                        WHERE challenge_id = challenge_uuid
                          AND user_id      = current_user_uuid
                   ),
                   days_completed = (
                       SELECT COUNT(*)
                         FROM challenge_daily_progress cdp
                         JOIN group_challenges gc ON gc.id = cdp.challenge_id
                        WHERE cdp.challenge_id = challenge_uuid
                          AND cdp.user_id      = current_user_uuid
                          AND (cdp.target_hit = TRUE OR cdp.progress_value >= COALESCE(gc.daily_target, 0))
                   ),
                   current_streak = v_current_streak,
                   best_streak    = GREATEST(COALESCE(best_streak, 0), v_current_streak)
             WHERE challenge_id = challenge_uuid
               AND user_id      = current_user_uuid;

            RETURN TRUE;
        EXCEPTION
            WHEN deadlock_detected THEN
                IF v_attempt >= v_max_attempts THEN
                    RAISE;
                END IF;
                PERFORM pg_sleep(0.05 + (random() * 0.1));
        END;
    END LOOP;
END;
$$;

GRANT EXECUTE ON FUNCTION log_challenge_progress(TEXT, INT, TEXT, TEXT, TEXT, TEXT, BOOLEAN) TO authenticated;

COMMENT ON FUNCTION log_challenge_progress(TEXT, INT, TEXT, TEXT, TEXT, TEXT, BOOLEAN) IS
'1v1/group challenge progress writer. Caller-tz progress_date.
Phase 7d widget kill-switch + deterministic lock order + 40P01 retry.
Hardened 2026-04-29 with transient-HK-zero guard: refuses to overwrite a
positive same-day progress_value with 0 even when allow_decrease=true.
Resolves Manuel d10d5d03 1v1 step 0-clobber (20260720).';

-- ═══════════════════════════════════════════════════════════════════════════
-- 2. log_private_challenge_progress
-- ═══════════════════════════════════════════════════════════════════════════
DROP FUNCTION IF EXISTS log_private_challenge_progress(TEXT, INT, TEXT);
DROP FUNCTION IF EXISTS log_private_challenge_progress(TEXT, INT, TEXT, BOOLEAN);

CREATE OR REPLACE FUNCTION log_private_challenge_progress(
    p_challenge_id   TEXT,
    p_progress       INT,
    p_timezone       TEXT DEFAULT 'UTC',
    p_allow_decrease BOOLEAN DEFAULT FALSE
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    current_user_uuid UUID;
    v_challenge_id    UUID;
    today_date        DATE;
    v_daily_target    INT;
    v_target_hit      BOOLEAN;
    v_prev_target_hit BOOLEAN;
    v_attempt         INT := 0;
    v_max_attempts    CONSTANT INT := 3;
BEGIN
    current_user_uuid := auth.uid();
    IF current_user_uuid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated' USING ERRCODE = 'P0001';
    END IF;

    v_challenge_id := p_challenge_id::UUID;
    today_date     := (NOW() AT TIME ZONE COALESCE(NULLIF(p_timezone, ''), 'UTC'))::DATE;

    LOOP
        v_attempt := v_attempt + 1;
        BEGIN
            SELECT daily_target
              INTO v_daily_target
              FROM private_challenges
             WHERE id = v_challenge_id;

            v_target_hit := (v_daily_target IS NOT NULL AND p_progress >= v_daily_target);

            PERFORM 1
              FROM private_challenge_members
             WHERE challenge_id = v_challenge_id
               AND user_id      = current_user_uuid
             FOR UPDATE;

            SELECT target_hit
              INTO v_prev_target_hit
              FROM private_challenge_daily_progress
             WHERE challenge_id  = v_challenge_id
               AND user_id       = current_user_uuid
               AND progress_date = today_date;

            INSERT INTO private_challenge_daily_progress (
                challenge_id, user_id, progress_date, progress_value, target_hit, source, updated_at
            ) VALUES (
                v_challenge_id, current_user_uuid, today_date, p_progress, v_target_hit, 'auto_sync', NOW()
            )
            ON CONFLICT (challenge_id, user_id, progress_date)
            DO UPDATE SET
                progress_value = CASE
                    -- 20260720 transient-HK-zero guard (mirror of 1v1 path).
                    WHEN p_allow_decrease
                         AND EXCLUDED.progress_value = 0
                         AND private_challenge_daily_progress.progress_value > 0
                        THEN private_challenge_daily_progress.progress_value
                    WHEN p_allow_decrease THEN EXCLUDED.progress_value
                    ELSE GREATEST(private_challenge_daily_progress.progress_value, EXCLUDED.progress_value)
                END,
                target_hit = CASE
                    WHEN p_allow_decrease
                         AND EXCLUDED.progress_value = 0
                         AND private_challenge_daily_progress.progress_value > 0
                        THEN private_challenge_daily_progress.target_hit
                    WHEN p_allow_decrease THEN EXCLUDED.target_hit
                    WHEN EXCLUDED.progress_value > private_challenge_daily_progress.progress_value
                        THEN EXCLUDED.target_hit
                    ELSE private_challenge_daily_progress.target_hit
                END,
                source     = EXCLUDED.source,
                updated_at = NOW();

            UPDATE private_challenge_members
               SET days_completed = CASE
                        WHEN v_target_hit AND (v_prev_target_hit IS NULL OR NOT v_prev_target_hit)
                            THEN COALESCE(days_completed, 0) + 1
                        ELSE days_completed
                    END,
                   today_progress = p_progress,
                   last_active_at = NOW()
             WHERE challenge_id = v_challenge_id
               AND user_id      = current_user_uuid;

            RETURN TRUE;
        EXCEPTION
            WHEN deadlock_detected THEN
                IF v_attempt >= v_max_attempts THEN
                    RAISE;
                END IF;
                PERFORM pg_sleep(0.05 + (random() * 0.1));
        END;
    END LOOP;
END;
$$;

GRANT EXECUTE ON FUNCTION log_private_challenge_progress(TEXT, INT, TEXT, BOOLEAN) TO authenticated;

COMMENT ON FUNCTION log_private_challenge_progress(TEXT, INT, TEXT, BOOLEAN) IS
'Private group challenge progress writer. Hardened 2026-04-29 with
transient-HK-zero guard (mirror of 1v1 path). Refuses to overwrite a
positive same-day progress_value with 0 even when allow_decrease=true.';

-- ═══════════════════════════════════════════════════════════════════════════
-- 3. log_community_challenge_progress
-- ═══════════════════════════════════════════════════════════════════════════
DROP FUNCTION IF EXISTS log_community_challenge_progress(TEXT, INT, TEXT);
DROP FUNCTION IF EXISTS log_community_challenge_progress(TEXT, INT, TEXT, BOOLEAN);

CREATE OR REPLACE FUNCTION log_community_challenge_progress(
    p_challenge_id   TEXT,
    p_progress       INT,
    p_timezone       TEXT DEFAULT 'UTC',
    p_allow_decrease BOOLEAN DEFAULT FALSE
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    current_user_uuid UUID;
    v_challenge_id    UUID;
    today_date        DATE;
    v_daily_target    INT;
    v_target_hit      BOOLEAN;
    v_prev_target_hit BOOLEAN;
    v_attempt         INT := 0;
    v_max_attempts    CONSTANT INT := 3;
BEGIN
    current_user_uuid := auth.uid();
    IF current_user_uuid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    v_challenge_id := p_challenge_id::UUID;
    today_date     := (NOW() AT TIME ZONE COALESCE(NULLIF(p_timezone, ''), 'UTC'))::DATE;

    SELECT daily_target INTO v_daily_target
      FROM community_challenges
     WHERE id = v_challenge_id;

    v_target_hit := (v_daily_target IS NOT NULL AND p_progress >= v_daily_target);

    LOOP
        v_attempt := v_attempt + 1;
        BEGIN
            PERFORM 1
              FROM community_challenge_participants
             WHERE challenge_id = v_challenge_id
               AND user_id      = current_user_uuid
             FOR UPDATE;

            SELECT target_hit INTO v_prev_target_hit
              FROM community_challenge_daily_progress
             WHERE challenge_id  = v_challenge_id
               AND user_id       = current_user_uuid
               AND progress_date = today_date;

            INSERT INTO community_challenge_daily_progress (
                challenge_id, user_id, progress_date, progress_value,
                target_hit, source, updated_at
            ) VALUES (
                v_challenge_id, current_user_uuid, today_date, p_progress,
                v_target_hit, 'auto_sync', NOW()
            )
            ON CONFLICT (challenge_id, user_id, progress_date)
            DO UPDATE SET
                progress_value = CASE
                    -- 20260720 transient-HK-zero guard (mirror of 1v1 path).
                    WHEN p_allow_decrease
                         AND EXCLUDED.progress_value = 0
                         AND community_challenge_daily_progress.progress_value > 0
                        THEN community_challenge_daily_progress.progress_value
                    WHEN p_allow_decrease THEN EXCLUDED.progress_value
                    ELSE GREATEST(community_challenge_daily_progress.progress_value, EXCLUDED.progress_value)
                END,
                target_hit = CASE
                    WHEN p_allow_decrease
                         AND EXCLUDED.progress_value = 0
                         AND community_challenge_daily_progress.progress_value > 0
                        THEN community_challenge_daily_progress.target_hit
                    WHEN p_allow_decrease THEN EXCLUDED.target_hit
                    WHEN EXCLUDED.progress_value > community_challenge_daily_progress.progress_value
                        THEN EXCLUDED.target_hit
                    ELSE community_challenge_daily_progress.target_hit
                END,
                source     = EXCLUDED.source,
                updated_at = NOW();

            UPDATE community_challenge_participants
               SET days_completed = CASE
                       WHEN v_target_hit AND (v_prev_target_hit IS NULL OR NOT v_prev_target_hit)
                            THEN COALESCE(days_completed, 0) + 1
                       ELSE days_completed
                   END,
                   today_progress = p_progress,
                   last_active_at = NOW()
             WHERE challenge_id = v_challenge_id
               AND user_id      = current_user_uuid;

            RETURN TRUE;
        EXCEPTION
            WHEN deadlock_detected THEN
                IF v_attempt >= v_max_attempts THEN
                    RAISE;
                END IF;
                PERFORM pg_sleep(0.05 + (random() * 0.1));
        END;
    END LOOP;
END;
$$;

GRANT EXECUTE ON FUNCTION log_community_challenge_progress(TEXT, INT, TEXT, BOOLEAN) TO authenticated;

COMMENT ON FUNCTION log_community_challenge_progress(TEXT, INT, TEXT, BOOLEAN) IS
'Community challenge progress writer. Hardened 2026-04-29 with
transient-HK-zero guard (mirror of 1v1 path). Refuses to overwrite a
positive same-day progress_value with 0 even when allow_decrease=true.';

-- ═══════════════════════════════════════════════════════════════════════════
-- 4. Surgical data repair — Manuel's clobbered rows
--    Without this, the 0 sticks until his next non-zero push (which is
--    blocked by the iOS-side stuck-flag bug fixed in the paired commit).
--    We don't have ground truth for the right value to backfill, so we
--    NULL the source row by SETTING progress_value = NULL is impossible
--    (NOT NULL column). Best we can do is leave the rows as-is and let
--    the iOS fix re-push the real value once deployed.
--
--    DELETING the clobbered row would be a worse outcome: the next
--    `get_active_challenges` read would show "—" instead of "0" briefly,
--    and the row would be re-created on the next push. Leaving it at 0
--    means the next non-zero push UPSERTs through the new guard
--    correctly (332 > 0, allow_decrease=true, no 0-clobber-of-positive
--    branch hit, value updated to 332).
--
--    Audit row only — no data mutation.
-- ═══════════════════════════════════════════════════════════════════════════

DO $$
DECLARE
    v_clobbered INT;
BEGIN
    SELECT COUNT(*)
      INTO v_clobbered
      FROM challenge_daily_progress cdp
      JOIN group_challenges gc ON gc.id = cdp.challenge_id
     WHERE cdp.user_id = 'd10d5d03-1a0d-4b41-b61b-a4f30a56362e'::uuid
       AND gc.challenge_type = 'steps'
       AND cdp.progress_value = 0
       AND cdp.progress_date >= (NOW() - INTERVAL '7 days')::date;

    RAISE NOTICE
        '[20260720] Manuel d10d5d03 has % zero-rows in step challenges (last 7d). Will self-heal once iOS fix lands and HK pushes a non-zero value.',
        v_clobbered;
END $$;

-- ═══════════════════════════════════════════════════════════════════════════
-- 5. Audit — fail-loud verification of the new guard in all three RPCs
-- ═══════════════════════════════════════════════════════════════════════════

DO $$
DECLARE
    v_count    INT;
    v_src      TEXT;
    v_fn       TEXT;
    v_funcs    TEXT[] := ARRAY[
        'log_challenge_progress',
        'log_private_challenge_progress',
        'log_community_challenge_progress'
    ];
BEGIN
    FOREACH v_fn IN ARRAY v_funcs LOOP
        SELECT COUNT(*), MAX(prosrc) INTO v_count, v_src
          FROM pg_proc p
          JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname = 'public'
           AND p.proname = v_fn;

        IF v_count <> 1 THEN
            RAISE EXCEPTION '[20260720 audit] expected exactly 1 % overload, got %', v_fn, v_count;
        END IF;

        -- The new guard MUST appear in the upsert SET clause. We look for
        -- the canonical phrase
        --   `EXCLUDED.progress_value = 0`
        -- inside the function body — present in both progress_value AND
        -- target_hit branches.
        IF v_src !~ 'EXCLUDED\.progress_value\s*=\s*0' THEN
            RAISE EXCEPTION
                '[20260720 audit] %: zero-clobber guard is missing — function did not get re-created with the new branch',
                v_fn;
        END IF;

        -- Verify the matching `progress_value > 0` reference is also there
        -- (so the guard checks BOTH sides — new=0 AND stored>0).
        IF v_src !~ 'progress_value\s*>\s*0' THEN
            RAISE EXCEPTION
                '[20260720 audit] %: zero-clobber guard half-applied — has new=0 check but missing stored>0 check',
                v_fn;
        END IF;
    END LOOP;

    RAISE NOTICE
        '[20260720] ✅ All three progress RPCs now refuse 0-overwrite of positive same-day values when allow_decrease=true.';
END $$;

COMMIT;

-- ───────────────────────────────────────────────────────────────────────
-- Resolves directives — feed bug-intel-resolves-deploy.yml on next push:
-- ───────────────────────────────────────────────────────────────────────
-- (Cluster id will be assigned in the next bug-intel audit pass; this
-- migration eliminates the upstream "step progress 0-clobber" failure
-- mode for steps + active_minutes via allow_decrease=true.)
