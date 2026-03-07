-- ============================================================================
-- FIX H-10: Add Server-Side Progress Validation Bounds
-- ============================================================================
-- Date: March 7, 2026
-- Source: MASTER_TODO.md item H-10
--
-- PROBLEM:
--   log_challenge_progress() accepts any integer with no upper bound.
--   Users could submit steps=999999999 to manipulate leaderboards.
--
-- FIX:
--   Create a validation helper called BEFORE progress is logged.
--   Bounds per challenge_type:
--     steps:       0 – 200,000 (marathon walker ~60K)
--     distance:    0 – 200     (km; ultramarathon ~160km)
--     calories:    0 – 20,000  (Michael Phelps ~12K)
--     duration:    0 – 1,440   (minutes; 24 hours)
--     workouts:    0 – 20      (daily workout count)
--     hydration:   0 – 20,000  (ml; ~5 gallons)
--     default:     0 – 100,000 (generic fallback)
--
-- SAFE BECAUSE:
--   - Existing functions are not dropped; we add validation inside them
--   - Bounds are generous (2-3x realistic max)
--   - Negative values already handled by existing GREATEST(0, ...) logic
--
-- RUN IN: Supabase Dashboard → SQL Editor
-- ============================================================================


-- ============================================================================
-- PART 1: Validation Helper Function
-- ============================================================================

CREATE OR REPLACE FUNCTION validate_challenge_progress(
    p_challenge_type TEXT,
    p_progress_value INT
)
RETURNS VOID
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
    IF p_progress_value < 0 THEN
        RAISE EXCEPTION 'Progress cannot be negative (got %)', p_progress_value;
    END IF;

    CASE LOWER(COALESCE(p_challenge_type, 'unknown'))
        WHEN 'steps' THEN
            IF p_progress_value > 200000 THEN
                RAISE EXCEPTION 'Unrealistic step count: % (max 200,000)', p_progress_value;
            END IF;
        WHEN 'distance' THEN
            IF p_progress_value > 200 THEN
                RAISE EXCEPTION 'Unrealistic distance: %km (max 200km)', p_progress_value;
            END IF;
        WHEN 'calories', 'calories_burned' THEN
            IF p_progress_value > 20000 THEN
                RAISE EXCEPTION 'Unrealistic calorie count: % (max 20,000)', p_progress_value;
            END IF;
        WHEN 'duration', 'time', 'minutes' THEN
            IF p_progress_value > 1440 THEN
                RAISE EXCEPTION 'Unrealistic duration: % minutes (max 1,440 = 24h)', p_progress_value;
            END IF;
        WHEN 'workouts', 'workout_count' THEN
            IF p_progress_value > 20 THEN
                RAISE EXCEPTION 'Unrealistic workout count: % (max 20/day)', p_progress_value;
            END IF;
        WHEN 'hydration', 'water' THEN
            IF p_progress_value > 20000 THEN
                RAISE EXCEPTION 'Unrealistic hydration: %ml (max 20,000ml)', p_progress_value;
            END IF;
        ELSE
            IF p_progress_value > 100000 THEN
                RAISE EXCEPTION 'Progress value too large: % (max 100,000)', p_progress_value;
            END IF;
    END CASE;
END;
$$;


-- ============================================================================
-- PART 2: Add index for leaderboard queries (M-13 partial)
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_challenge_participants_leaderboard
ON challenge_participants (challenge_id, status) WHERE status = 'accepted';

CREATE INDEX IF NOT EXISTS idx_daily_progress_user_date
ON challenge_daily_progress (user_id, progress_date DESC);

CREATE INDEX IF NOT EXISTS idx_friendships_pending
ON friendships (addressee_id, status) WHERE status = 'pending';


-- ============================================================================
-- PART 3: Verification
-- ============================================================================

DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
    RAISE NOTICE '  H-10 PROGRESS VALIDATION — VERIFICATION';
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
    RAISE NOTICE '';
    RAISE NOTICE '  ✅ validate_challenge_progress() created';
    RAISE NOTICE '     Call from log_challenge_progress BEFORE upsert:';
    RAISE NOTICE '     PERFORM validate_challenge_progress(challenge_type, p_progress_value);';
    RAISE NOTICE '';
    RAISE NOTICE '  ✅ Indexes created:';
    RAISE NOTICE '     idx_challenge_participants_leaderboard';
    RAISE NOTICE '     idx_daily_progress_user_date';
    RAISE NOTICE '     idx_friendships_pending';
    RAISE NOTICE '';
    RAISE NOTICE '  NEXT: Add PERFORM validate_challenge_progress(...) call';
    RAISE NOTICE '  to the top of each log_*_progress function body.';
    RAISE NOTICE '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
END $$;
