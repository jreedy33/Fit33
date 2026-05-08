-- 20260508_bug_intel_classifier_pgrst202_friend_p0001.sql
-- Resolves: 840673f1d385c2b5c4e97da82fcb75ee — batch_check_achievements PGRST202
-- Resolves: d1d2767ae18e618b22d6d89cbf09a487 — accept_friend_request P0001 already-processed
--
-- Two transient classes were each manufacturing a one-shot bug-intel
-- fingerprint despite both being known not-bugs:
--
-- (1) PGRST202 "Could not find the function in the schema cache" — fired
--     during the 5-12min PostgREST schema-cache propagation window after a
--     migration that creates a new function (canonical case: the
--     20260507_batch_check_achievements migration shipped the
--     `batch_check_achievements` RPC; one user opened the app DURING the
--     schema-cache reload window and got the PGRST202 once, never again).
--     Per BUG_INTEL_AGENT invariant 19b the migration ends with
--     `NOTIFY pgrst, 'reload schema'` to collapse this window — the
--     remaining one-shot occurrences are unavoidable physics. Bucket as
--     transient on both sides of the chain.
--
-- (2) P0001 "Friend request not found or already processed" — server-side
--     idempotency guard fires when a previous accept call already won
--     (network flap right before the user's accept — see the d1d2767a
--     evidence: NSURLErrorNetworkConnectionLost -1005 to
--     `get_pending_sent_challenges` 5ms before the accept call). Local
--     `pendingRequests.removeAll` already dropped the row from the UI on
--     the first successful run; the user's intent is satisfied. Treat
--     as expectedUserState (the canonical bucket for "server idempotency
--     fired and that's the desired outcome" per
--     `bb8db6c1`/`da16c5c1`/`015bf5a8`/`84138481` daily-quest seed cluster).
--
-- iOS classifier branches paired with these noise-filter rows live in
-- `Fit33/NetworkErrorClassifier.swift` (PGRST202 → .transientNetwork;
-- P0001 friend-already-processed → .expectedUserState). Per BUG_INTEL_AGENT
-- invariant 3, the Swift branch + the server denylist row MUST land in the
-- same commit so future occurrences never re-fingerprint regardless of
-- which side catches them first.
--
-- Idempotency: ON CONFLICT DO UPDATE on the `name` column so re-running
-- the migration just keeps the row current. No schema changes, no DDL
-- against `bug_intelligence_*` tables.

BEGIN;

-- ─── 1. Server-side noise filter: PGRST202 schema cache miss ────────────
INSERT INTO public.bug_intel_noise_filter (
    name, message_pattern, tier, rationale, created_by
) VALUES (
    'pgrst_schema_cache_miss',
    '%Could not find the function%',
    'hard',
    'PGRST202 fired during the 5-12min PostgREST schema-cache propagation '
    || 'window after a migration that adds a new function. Migrations end '
    || 'with NOTIFY pgrst, ''reload schema'' (SUPABASE invariant 19b) to '
    || 'collapse this window — but a user who opens the app DURING '
    || 'propagation hits PGRST202 once. Classifier branch in '
    || 'NetworkErrorClassifier.swift treats as transientNetwork. '
    || 'Bug-intel 840673f1 — batch_check_achievements PGRST202, single '
    || 'occurrence on 2026-05-08 deploy.',
    'migration_20260508_bug_intel_classifier_pgrst202_friend_p0001'
)
ON CONFLICT (name) DO UPDATE SET
    message_pattern = EXCLUDED.message_pattern,
    tier            = EXCLUDED.tier,
    rationale       = EXCLUDED.rationale;

-- ─── 2. Server-side noise filter: friend request idempotency ────────────
INSERT INTO public.bug_intel_noise_filter (
    name, message_pattern, tier, rationale, created_by
) VALUES (
    'friend_request_already_processed',
    '%Friend request not found or already processed%',
    'hard',
    'Server-side idempotency guard fires when a previous accept_friend_request '
    || 'RPC call already succeeded (network flap before the second call, '
    || 'double-tap, or multi-device race). Local pendingRequests.removeAll '
    || 'already dropped the row from the UI; user intent satisfied. '
    || 'Classifier branch returns expectedUserState. '
    || 'Bug-intel d1d2767a — single occurrence after -1005 network-lost.',
    'migration_20260508_bug_intel_classifier_pgrst202_friend_p0001'
)
ON CONFLICT (name) DO UPDATE SET
    message_pattern = EXCLUDED.message_pattern,
    tier            = EXCLUDED.tier,
    rationale       = EXCLUDED.rationale;

-- ─── 3. Mark the two source fingerprints resolved (silent_fix) ──────────
-- Per the `Resolves:` directive convention (BUG_INTEL_AGENT invariant 16),
-- we explicitly mark these resolved AND inline a denylist auto-drain so
-- any latent twin fingerprints (root_cause / structural twins) get
-- collapsed in the next nightly drain cycle.

DO $$
DECLARE
    v_resolved_count INT;
BEGIN
    -- Use the canonical resolution helper if present.
    IF EXISTS (
        SELECT 1 FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public'
          AND p.proname = 'mark_fingerprints_resolved_by_migration'
    ) THEN
        PERFORM public.mark_fingerprints_resolved_by_migration(
            p_migration_id := '20260508_bug_intel_classifier_pgrst202_friend_p0001',
            p_fingerprints := ARRAY[
                '840673f1d385c2b5c4e97da82fcb75ee',
                'd1d2767ae18e618b22d6d89cbf09a487'
            ],
            p_resolution_note := 'noise_filter_expanded — PGRST202 schema-cache + P0001 friend-already-processed; iOS classifier branches added'
        );
        GET DIAGNOSTICS v_resolved_count = ROW_COUNT;
        RAISE NOTICE 'mark_fingerprints_resolved_by_migration: % rows touched', v_resolved_count;
    ELSE
        RAISE NOTICE 'mark_fingerprints_resolved_by_migration not deployed yet — skipping inline replay';
    END IF;
END$$;

-- ─── 4. Audit: both noise-filter rows present ──────────────────────────
DO $$
DECLARE
    v_count INT;
BEGIN
    SELECT COUNT(*) INTO v_count
      FROM public.bug_intel_noise_filter
     WHERE name IN (
         'pgrst_schema_cache_miss',
         'friend_request_already_processed'
     );

    IF v_count <> 2 THEN
        RAISE EXCEPTION
            'bug_intel_noise_filter audit failed: expected 2 rows, found %',
            v_count;
    END IF;

    RAISE NOTICE 'bug_intel_noise_filter: 2 transient denylist rows present (audit OK)';
END$$;

COMMIT;
