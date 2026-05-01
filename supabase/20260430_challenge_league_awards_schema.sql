-- =============================================================================
-- 20260430_challenge_league_awards_schema.sql
--
-- Challenge League Points Expansion — "Daily Duels, Final Bell" (Part 1 of 3).
-- Schema foundation: award ledger, per-type tier config, source-cap registration.
--
-- DELIVERS (plan: challenge-league-points-expansion):
--   • `challenge_league_awards` per-award ledger (one row per user, challenge,
--     day, award_kind). UNIQUE constraint provides idempotency so the rollup
--     crons can safely re-run without double-crediting.
--   • `challenge_award_tiers` declarative per-challenge-type base value config.
--     Tuning = UPDATE, not code change.
--   • Two new rows in `league_point_source_caps` (`challenge_daily`,
--     `challenge_final_bell`) so the Sprint 3 ledger-backed cap enforcement
--     applies to the new award path.
--
-- NOTE: The scoring RPCs that WRITE to `challenge_league_awards` live in
-- `20260430c_challenge_league_scoring_rpcs.sql`. This file is pure schema
-- so it can ship safely ahead of the RPC migration.
--
-- PAIRS WITH:
--   • `20260430b_league_tier_promotion_floors.sql` — promotion LP floors +
--     Peak Day tier multiplier + widened relegation.
--   • `20260430c_challenge_league_scoring_rpcs.sql` — compute_* RPCs,
--     get_challenge_league_awards reader, Final Bell trigger.
-- =============================================================================

BEGIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. challenge_league_awards — per-award ledger
--
-- One row per (user, challenge, day, award_kind). For Final Bell awards
-- `challenge_day` is NULL and the UNIQUE constraint still dedups via the
-- (user_id, challenge_kind, challenge_id, NULL, 'final_bell') shape because
-- Postgres treats NULLs as distinct in UNIQUE by default — we use the
-- `challenge_final_bell_unique_idx` partial UNIQUE instead. For daily awards
-- the standard UNIQUE on all four cols keeps the cron idempotent.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS challenge_league_awards (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    challenge_kind      TEXT NOT NULL CHECK (challenge_kind IN ('1v1','group','private','community')),
    challenge_id        UUID NOT NULL,
    challenge_day       DATE,
    award_kind          TEXT NOT NULL CHECK (award_kind IN (
        'hit_target','day_winner','intensity','early_bird',
        'unbroken_chain','final_bell','wave_final_bell'
    )),
    base_points         INTEGER NOT NULL,
    multiplier_applied  NUMERIC(4,2) NOT NULL DEFAULT 1.0,
    final_points        INTEGER NOT NULL,
    note                TEXT,
    awarded_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    week_start          DATE NOT NULL,
    -- Sanity: final_bell awards must NOT have a challenge_day; daily awards MUST.
    CONSTRAINT challenge_league_awards_day_kind_consistency
        CHECK (
            (award_kind IN ('final_bell','wave_final_bell') AND challenge_day IS NULL)
            OR (award_kind NOT IN ('final_bell','wave_final_bell') AND challenge_day IS NOT NULL)
        )
);

-- Daily awards (hit_target / day_winner / intensity / early_bird / unbroken_chain
-- when keyed per day) dedup via the standard UNIQUE across all four cols.
CREATE UNIQUE INDEX IF NOT EXISTS challenge_league_awards_daily_unique_idx
    ON challenge_league_awards (user_id, challenge_kind, challenge_id, challenge_day, award_kind)
    WHERE challenge_day IS NOT NULL;

-- Final Bell awards (one per (user, challenge) for 1v1/group/private) dedup
-- via a partial UNIQUE on the rows where challenge_day IS NULL. The
-- `wave_final_bell` path DOES carry a day (= wave end) so it's handled by the
-- daily unique above.
CREATE UNIQUE INDEX IF NOT EXISTS challenge_league_awards_final_bell_unique_idx
    ON challenge_league_awards (user_id, challenge_kind, challenge_id, award_kind)
    WHERE challenge_day IS NULL;

-- Hot-path indexes for the battle log + breakdown panel read paths.
CREATE INDEX IF NOT EXISTS challenge_league_awards_user_challenge_idx
    ON challenge_league_awards (user_id, challenge_id, challenge_day);
CREATE INDEX IF NOT EXISTS challenge_league_awards_user_week_idx
    ON challenge_league_awards (user_id, week_start);
CREATE INDEX IF NOT EXISTS challenge_league_awards_challenge_day_idx
    ON challenge_league_awards (challenge_kind, challenge_id, challenge_day);

COMMENT ON TABLE challenge_league_awards IS
    'Per-award ledger for League Points earned inside challenges (1v1/group/private/community). One row per (user, challenge, day, award_kind). UNIQUE indexes make the rollup crons idempotent — re-running yields no new rows. Reader RPCs: get_challenge_league_awards (battle log), get_league_member_breakdown (weekly leaderboard panel). Writer RPCs: compute_challenge_daily_awards, compute_challenge_final_bell, compute_community_wave_final_bell.';
COMMENT ON COLUMN challenge_league_awards.challenge_kind IS
    '1v1 = group_challenges with exactly 2 participants; group = group_challenges with >2; private = private_challenges; community = community_challenges.';
COMMENT ON COLUMN challenge_league_awards.challenge_id IS
    'Polymorphic FK (no SQL-level REFERENCES) — the challenge_kind column disambiguates which table. Writer RPCs enforce the cross-table integrity.';
COMMENT ON COLUMN challenge_league_awards.multiplier_applied IS
    'Cumulative multiplier applied to base_points for this one award row (e.g. 2.00 for a day_winner 1v1 row). Peak Day multiplier is NOT captured here — it is applied inside add_league_points at credit time and recorded in league_point_awards.';

-- RLS — users read their own awards. Writes are SECURITY DEFINER RPC only.
ALTER TABLE challenge_league_awards ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "challenge_league_awards_select_own" ON challenge_league_awards;
CREATE POLICY "challenge_league_awards_select_own" ON challenge_league_awards
    FOR SELECT USING (auth.uid() = user_id);

-- No INSERT/UPDATE/DELETE client policies — server-side RPC is the only writer.

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. challenge_award_tiers — per-challenge-type base value lookup
--
-- Mirrors Swift `ChallengeType` (Fit33/ChallengeService.swift line 3459). Each
-- type is classified into {easy, moderate, hard, expert} effort tiers, with
-- a base "hit goal" value and a base "win the day" value. All 12 current
-- types seeded below. When adding a new ChallengeType, append an INSERT row
-- in a new migration — the scoring RPC falls back to the `easy` defaults
-- when no row exists (so shipping a new type iOS-side without a paired
-- SQL migration is graceful, not a crash).
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS challenge_award_tiers (
    challenge_type  TEXT PRIMARY KEY,
    effort_tier     TEXT NOT NULL CHECK (effort_tier IN ('easy','moderate','hard','expert')),
    base_hit        INTEGER NOT NULL CHECK (base_hit >= 0),
    base_win        INTEGER NOT NULL CHECK (base_win >= base_hit),
    notes           TEXT
);

COMMENT ON TABLE challenge_award_tiers IS
    'Per-challenge-type effort-tier configuration for League Points scoring. Mirrors Swift ChallengeType enum. Tuning = UPDATE, not code change. `base_hit` is the flat award for hitting the daily target; `base_win` is the target-met award before per-day multipliers (day-winner, intensity, early-bird, Peak Day).';

INSERT INTO challenge_award_tiers (challenge_type, effort_tier, base_hit, base_win, notes) VALUES
    ('steps',              'easy',     10, 15, 'Low bar — steps are passive-ish.'),
    ('walk',               'easy',     10, 15, 'Timed walking, low bar.'),
    ('hydrate',            'easy',     10, 15, 'Counter-based, low bar.'),
    ('active_minutes',     'moderate', 15, 20, 'Moderate — requires a real activity session.'),
    ('calories',           'moderate', 15, 20, 'Moderate — blended HK + meals.'),
    ('run',                'hard',     20, 25, 'Hard — real running session.'),
    ('protein',            'hard',     20, 25, 'Hard — consistent meal logging.'),
    ('lift',               'hard',     20, 25, 'Hard — strength workout required.'),
    ('workout_streak',     'hard',     20, 25, 'Hard — cumulative consistency.'),
    ('readiness_average',  'hard',     20, 25, 'Hard — requires wearable + recovery work.'),
    ('sleep_hours',        'expert',   25, 30, 'Expert — 8+ hours sleep is a real commitment.'),
    ('strain_budget',      'expert',   25, 30, 'Expert — high-strain training without crashing recovery.')
ON CONFLICT (challenge_type) DO UPDATE SET
    effort_tier = EXCLUDED.effort_tier,
    base_hit    = EXCLUDED.base_hit,
    base_win    = EXCLUDED.base_win,
    notes       = EXCLUDED.notes;

-- No RLS — read-only reference table, no user_id column.
GRANT SELECT ON challenge_award_tiers TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. league_point_source_caps — register the new sources
--
-- The Sprint 3 ledger-backed cap enforcement inside `add_league_points` reads
-- from this table. Adding rows here auto-applies the cap policy to new
-- sources — no RPC body change needed.
--
-- `challenge_daily` is capped at 10 awards/day/user ACROSS all active
-- challenges (a hard anti-farm). The plan's "+100 LP/challenge/day" soft
-- cap is enforced inside `compute_challenge_daily_awards` itself (summed
-- daily total before the single add_league_points call). Similarly the
-- "+500 LP/day cross-challenge" cap is a sum guard inside the daily RPC.
--
-- `challenge_final_bell` has no cap — duration is the natural cap (you
-- can only finish one challenge at a time, and longer = more rewarding).
-- ─────────────────────────────────────────────────────────────────────────────

INSERT INTO league_point_source_caps (source, daily_cap, weekly_cap, is_lifetime, notes) VALUES
    ('challenge_daily',      10,   NULL, FALSE, 'Hard ceiling on distinct award rows per day. Actual LP amount is computed by compute_challenge_daily_awards and summed before add_league_points; this ledger cap just stops absurd farming.'),
    ('challenge_final_bell', NULL, NULL, FALSE, 'Duration of the challenge is the natural cap — a 30-day challenge pays ~137 LP once at the end.')
ON CONFLICT (source) DO UPDATE
    SET daily_cap   = EXCLUDED.daily_cap,
        weekly_cap  = EXCLUDED.weekly_cap,
        is_lifetime = EXCLUDED.is_lifetime,
        notes       = EXCLUDED.notes;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. Account deletion hook — cascade is already handled via auth.users FK,
-- but we document the surface here so future delete_user_account reviewers
-- find the reference.
-- ─────────────────────────────────────────────────────────────────────────────

COMMENT ON CONSTRAINT challenge_league_awards_user_id_fkey ON challenge_league_awards IS
    'ON DELETE CASCADE — delete_user_account() does not need an explicit DELETE for this table; the auth.users FK cascade handles it.';

COMMIT;

-- =============================================================================
-- Verification (run manually after deploy):
--   SELECT count(*) FROM challenge_award_tiers;  -- expect 12
--   SELECT source FROM league_point_source_caps WHERE source LIKE 'challenge_%';  -- expect 2
-- =============================================================================
