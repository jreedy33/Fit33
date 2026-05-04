-- Hotfix: assign_olympian_path — ambiguous column `goal_tier`
-- Date: 2026-05-04
--
-- Symptom (Postgres): column reference "goal_tier" is ambiguous
-- Cause: `assign_olympian_path` JOINs `user_olympian_assignments uoa` to
--        `achievements a`; both tables define `goal_tier`. Bare identifiers in
--        `jsonb_build_object(...)` must use `uoa.goal_number`, `uoa.goal_tier`,
--        etc.
--
-- Apply after `20260504_olympian_path.sql` if that migration shipped with the
-- unqualified columns. Idempotent — replaces the RPC body only.

BEGIN;

DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN (
        SELECT n.nspname, p.proname, oidvectortypes(p.proargtypes) AS args
          FROM pg_proc p
          JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname = 'public'
           AND p.proname = 'assign_olympian_path'
    ) LOOP
        EXECUTE format('DROP FUNCTION IF EXISTS %I.%I(%s)', r.nspname, r.proname, r.args);
    END LOOP;
END$$;

CREATE FUNCTION assign_olympian_path(p_year INT, p_archetype TEXT)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    current_user_uuid UUID;
    v_archetype TEXT;
    v_existing_count INT;
    v_assignments jsonb;
    v_meta_id UUID;
    v_goal_number SMALLINT;
    v_tier SMALLINT;
    v_universal_per_tier INT[5] := ARRAY[4, 3, 3, 2, 3]; -- T1..T5
    v_archetype_per_tier INT[5] := ARRAY[3, 4, 4, 5, 1]; -- T1..T5
    v_tier_offsets INT[5]      := ARRAY[0, 7, 14, 21, 28]; -- starting goal_number for each tier
BEGIN
    current_user_uuid := auth.uid();
    IF current_user_uuid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    -- Validate archetype (reject unknown values but never crash; default to general)
    v_archetype := CASE
        WHEN p_archetype IN ('strength', 'endurance', 'weightLoss', 'general', 'athletic')
        THEN p_archetype
        ELSE 'general'
    END;

    -- Idempotency: if 33 assignments already exist for this user/year, return them as-is
    SELECT COUNT(*) INTO v_existing_count
    FROM user_olympian_assignments
    WHERE user_id = current_user_uuid AND season_year = p_year;

    IF v_existing_count = 33 THEN
        -- Qualify uoa.* — `achievements` also has `goal_tier`, so bare
        -- `goal_tier` in a JOIN is ambiguous in PostgreSQL.
        SELECT jsonb_agg(jsonb_build_object(
            'goal_number', uoa.goal_number,
            'goal_tier', uoa.goal_tier,
            'achievement_id', uoa.achievement_id,
            'achievement_key', a.key,
            'archetype', uoa.archetype
        ) ORDER BY uoa.goal_number)
        INTO v_assignments
        FROM user_olympian_assignments uoa
        JOIN achievements a ON a.id = uoa.achievement_id
        WHERE uoa.user_id = current_user_uuid AND uoa.season_year = p_year;

        RETURN jsonb_build_object(
            'created', false,
            'archetype', (SELECT archetype FROM user_olympian_assignments
                          WHERE user_id = current_user_uuid AND season_year = p_year LIMIT 1),
            'assignments', COALESCE(v_assignments, '[]'::jsonb)
        );
    END IF;

    -- If a partial assignment exists (e.g. failed mid-flight), wipe and re-assign
    -- to keep the 33 invariant intact.
    IF v_existing_count > 0 AND v_existing_count < 33 THEN
        DELETE FROM user_olympian_assignments
        WHERE user_id = current_user_uuid AND season_year = p_year;
    END IF;

    -- Locate the meta goal (key olympian_<year>_complete_path) — always #33
    SELECT id INTO v_meta_id
    FROM achievements
    WHERE key = 'olympian_' || p_year || '_complete_path' AND season_year = p_year
    LIMIT 1;

    IF v_meta_id IS NULL THEN
        RAISE EXCEPTION 'Olympian meta goal not seeded for year %', p_year;
    END IF;

    -- Per-tier slot fill: top N universal + top M archetype-specific, ordered
    -- deterministically by (threshold ASC, key ASC).
    FOR v_tier IN 1..5 LOOP
        DECLARE
            v_universal_count INT := v_universal_per_tier[v_tier];
            v_archetype_count INT := v_archetype_per_tier[v_tier];
            v_tier_offset INT := v_tier_offsets[v_tier];
            v_slot INT := 0;
            r RECORD;
        BEGIN
            -- Universal slots first
            FOR r IN (
                SELECT id
                FROM achievements
                WHERE category = 'olympian_path'
                  AND season_year = p_year
                  AND goal_tier = v_tier
                  AND 'universal' = ANY(applicable_archetypes)
                  AND id <> v_meta_id
                ORDER BY threshold ASC, key ASC
                LIMIT v_universal_count
            ) LOOP
                v_slot := v_slot + 1;
                v_goal_number := v_tier_offset + v_slot;
                INSERT INTO user_olympian_assignments
                    (user_id, season_year, achievement_id, goal_number, goal_tier, archetype)
                VALUES
                    (current_user_uuid, p_year, r.id, v_goal_number, v_tier, v_archetype)
                ON CONFLICT (user_id, season_year, achievement_id) DO NOTHING;
            END LOOP;

            -- Archetype-specific slots
            FOR r IN (
                SELECT id
                FROM achievements
                WHERE category = 'olympian_path'
                  AND season_year = p_year
                  AND goal_tier = v_tier
                  AND v_archetype = ANY(applicable_archetypes)
                  AND NOT ('universal' = ANY(applicable_archetypes))
                  AND id <> v_meta_id
                  AND id NOT IN (
                      SELECT achievement_id FROM user_olympian_assignments
                      WHERE user_id = current_user_uuid AND season_year = p_year
                  )
                ORDER BY threshold ASC, key ASC
                LIMIT v_archetype_count
            ) LOOP
                v_slot := v_slot + 1;
                v_goal_number := v_tier_offset + v_slot;
                IF v_goal_number > v_tier_offset + v_universal_count + v_archetype_count THEN
                    EXIT;
                END IF;
                INSERT INTO user_olympian_assignments
                    (user_id, season_year, achievement_id, goal_number, goal_tier, archetype)
                VALUES
                    (current_user_uuid, p_year, r.id, v_goal_number, v_tier, v_archetype)
                ON CONFLICT (user_id, season_year, achievement_id) DO NOTHING;
            END LOOP;

            -- Backfill any tier 5 universal-eligible if archetype pool came up short
            IF v_tier = 5 THEN
                DECLARE
                    v_have INT;
                    v_need INT;
                BEGIN
                    SELECT COUNT(*) INTO v_have FROM user_olympian_assignments
                    WHERE user_id = current_user_uuid AND season_year = p_year AND goal_tier = 5;
                    -- Tier 5 holds 4 stretch slots + meta = 5 total; we'll insert meta separately.
                    v_need := 4 - v_have;
                    IF v_need > 0 THEN
                        FOR r IN (
                            SELECT id
                            FROM achievements
                            WHERE category = 'olympian_path'
                              AND season_year = p_year
                              AND goal_tier = 5
                              AND id <> v_meta_id
                              AND id NOT IN (
                                  SELECT achievement_id FROM user_olympian_assignments
                                  WHERE user_id = current_user_uuid AND season_year = p_year
                              )
                            ORDER BY threshold ASC, key ASC
                            LIMIT v_need
                        ) LOOP
                            v_have := v_have + 1;
                            INSERT INTO user_olympian_assignments
                                (user_id, season_year, achievement_id, goal_number, goal_tier, archetype)
                            VALUES
                                (current_user_uuid, p_year, r.id, 28 + v_have, 5, v_archetype)
                            ON CONFLICT (user_id, season_year, achievement_id) DO NOTHING;
                        END LOOP;
                    END IF;
                END;
            END IF;
        END;
    END LOOP;

    -- Always assign meta as #33
    INSERT INTO user_olympian_assignments
        (user_id, season_year, achievement_id, goal_number, goal_tier, archetype)
    VALUES
        (current_user_uuid, p_year, v_meta_id, 33, 5, v_archetype)
    ON CONFLICT (user_id, season_year, achievement_id) DO NOTHING;

    -- Final shape check — fail loud if anything came up short
    SELECT COUNT(*) INTO v_existing_count
    FROM user_olympian_assignments
    WHERE user_id = current_user_uuid AND season_year = p_year;

    IF v_existing_count <> 33 THEN
        RAISE EXCEPTION 'Olympian assignment short: got % rows, expected 33 (archetype=%, year=%)',
            v_existing_count, v_archetype, p_year;
    END IF;

    SELECT jsonb_agg(jsonb_build_object(
        'goal_number', uoa.goal_number,
        'goal_tier', uoa.goal_tier,
        'achievement_id', uoa.achievement_id,
        'achievement_key', a.key,
        'archetype', uoa.archetype
    ) ORDER BY uoa.goal_number)
    INTO v_assignments
    FROM user_olympian_assignments uoa
    JOIN achievements a ON a.id = uoa.achievement_id
    WHERE uoa.user_id = current_user_uuid AND uoa.season_year = p_year;

    RETURN jsonb_build_object(
        'created', true,
        'archetype', v_archetype,
        'assignments', v_assignments
    );
END;
$$;

GRANT EXECUTE ON FUNCTION assign_olympian_path(INT, TEXT) TO authenticated;

NOTIFY pgrst, 'reload schema';

COMMIT;
