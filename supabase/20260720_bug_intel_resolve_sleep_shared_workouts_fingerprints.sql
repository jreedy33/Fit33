-- 20260720_bug_intel_resolve_sleep_shared_workouts_fingerprints.sql
-- Bug Intelligence — stamp terminal resolution for migrations already deployed
-- on prod: `20260718_sleep_logs_upsert_unique.sql` + `20260719_shared_workouts_status_saved.sql`.
--
-- CONTEXT
-- -------
-- Schema migrations ran successfully outside the CI hook that parses `-- Resolves:`
-- lines. This follow-up calls `mark_fingerprints_resolved_by_migration(...)`
-- so `bug_intelligence_fingerprints` + pending triage rows merge cleanly.
--
-- Fingerprints (must match headers on the fix migrations):
--   20260718 → 9e02b91ecc1f52efd70af7150a80584d, b38bcdf9b3b02089918d5beb1bd618fa
--   20260719 → 69b01dea71a762f9bad04de646cfd120, eb0415219fce90b5c4013b00abf2674a
--
-- Idempotent: RPC skips fingerprints already in terminal status.

BEGIN;

DO $$
BEGIN
    PERFORM mark_fingerprints_resolved_by_migration(
        '20260718_sleep_logs_upsert_unique',
        ARRAY[
            '9e02b91ecc1f52efd70af7150a80584d',
            'b38bcdf9b3b02089918d5beb1bd618fa'
        ]::TEXT[],
        'sleep_logs unique index deployed — PostgREST upsert ON CONFLICT matches.'
    );

    PERFORM mark_fingerprints_resolved_by_migration(
        '20260719_shared_workouts_status_saved',
        ARRAY[
            '69b01dea71a762f9bad04de646cfd120',
            'eb0415219fce90b5c4013b00abf2674a'
        ]::TEXT[],
        'shared_workouts CHECK constraint includes saved.'
    );
END $$;

COMMIT;
