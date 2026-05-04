-- =============================================================================
-- Bug Intelligence Inbox Drain — 2026-05-04 sweep
-- =============================================================================
-- Closes the 2026-05-04 export's inbox by stamping known-resolved /
-- now-classifier-routed fingerprints with the canonical
-- `auto_resolved_reason` per `BUG_INTELLIGENCE_AGENT.md` invariant 15.
--
-- Touches ONLY `bug_intelligence_fingerprints` (status, resolved_at,
-- auto_resolved_reason) + `bug_intel_noise_filter` (insert tunable
-- suppressions). NO schema changes, NO function signature changes, NO
-- table-level realtime publication changes — purely metadata maintenance
-- on the bug-intel pipeline tables.
--
-- Resolves: ed47235aacc85ca48e62488533eccab9 record_cardio_workout RPC route_coordinates type mismatch (crash) — fixed in 20260504_record_cardio_workout_jsonb_fix.sql (companion in same deploy)
-- Resolves: dc1787c30c387f39f525a1d9ae22f4a9 Cardio recap save route_coordinates type mismatch (crash twin) — same companion fix
-- Resolves: db636b01b92ebad2fa74167ecc5213ea Cardio recap save fails with route coordinates type error (log) — same companion fix
-- Resolves: 791da679d303f736ffe558afd6222d35 Route coordinates type mismatch in RPC call (log twin) — same companion fix
-- Resolves: 8622fc3a062c9744222d8c174f7aa518 Apple Sign In authorization error — classifier_routing in this PR
-- Resolves: 9494490021466860c9a60a6f476ebf88 Password reset email rate limit exceeded — classifier_routing (rate-limit branch already shipped)
-- Resolves: e59866110c660b8de22352984d0b159f Password reset email rate limit exceeded twin — classifier_routing
-- Resolves: a22cd96f76784e01bf8f4e0c89433109 Auth password reset rate limit exceeded — classifier_routing
-- Resolves: af583196a381ef711f9cf9342e2492aa WHOOP refresh token wiped (crash) — warning_downgrade already shipped
-- Resolves: aeb3794b27cea9b4dbe64a466df116b7 WHOOP service keychain token cleanup — warning_downgrade
-- Resolves: a275f4b0dd45d4c80efb1c85d8c7cb0a WHOOP refresh token wiped (log) — warning_downgrade
-- Resolves: bb8db6c13848652a253a41efbadc871d Daily quests duplicate key constraint violation (crash) — classifier_routing in this PR + ON CONFLICT in 20260703 (in-flight)
-- Resolves: da16c5c17b9230313fe5322fcd5c04e1 Daily quest duplicate key constraint violation (log) — classifier_routing
-- Resolves: 015bf5a86d2bfcb50033edfe19825e53 Daily quest duplicate key constraint violation (log raw) — classifier_routing
-- Resolves: 84138481f406a2e4a460870e132a2717 Daily quest duplicate key constraint violation (crash raw) — classifier_routing
-- Resolves: 184e70c65630243e0e0b6f611decd0bd Unknown notification type 'activity_reaction' — already routed explicitly + warning downgrade in this PR
-- Resolves: a20d732f56696c42efb7885cd2b076ee Unknown notification type 'hydration_pace' — warning downgrade in this PR
-- Resolves: 64dc89673a5c29291273ccbf7b53303a MetricKit signal 9 crash diagnostic — warning downgrade in this PR
-- Resolves: 14b58e6ab5d2e626682ae52bddd11156 HealthKit sleep null start_time (crash) — silent_fix (HealthDataService.swift:1265 guards hours>0 + synthesizes timestamps)
-- Resolves: 9dd275520f9ae8e8dc2f8f87bf08c6a1 HealthKit sleep null start_time (log) — silent_fix
-- Resolves: 60158c57ca60b68f5fe14529c9d4e8c0 Private challenge duplicate invite (log) — classifier_routing (expectedUserState branch in this PR)
-- Resolves: de033a163a7343ef8d81292931284c6d Private challenge duplicate invite (crash) — classifier_routing
-- Resolves: 5d4f9575f3b91842e2fcb143a71b0091 Challenge logProgress last_progress_at column missing — migration_resolved:20260629
-- Resolves: 1fb4a278f13adafd8acb2e9cf77470b2 Weight Failed to load HTTPError (log) — silent_fix (already routed via NetworkErrorClassifier)
-- Resolves: 6121691fd4ebfc9ca28b56e5f919b865 Weight Failed to load HTTPError (crash) — silent_fix
-- Resolves: 97f51f027eb90d963fd22675590ad3bb Watchdog deadlock (log) — debug_only_path (MainThreadWatchdog gated #if DEBUG; never fires Release)
-- Resolves: 18ff0951f7151b55cb7bbe25d0a72d19 Watchdog deadlock (crash) — debug_only_path
-- Resolves: 9a4b5b9e58d06c908692f28684a024f1 Private challenge JWT expired log — auth race during launch, drained as transient
-- Resolves: d40dc939ebb3aa71805daccc1e134ca8 Daily quests pg:23505 single-incident — classifier_routing (will dedup as twin of bb8db6c1)
-- Resolves: b6a8bec9302467aec7f86cc83c1d2090 Push token save NSURL timeout — transient_single_incident
-- Resolves: 630c59c73777b77633850e9ff7f8bd1e Limitations fetch NSURL timeout — transient_single_incident
-- Resolves: 411d1ccd9e73bbbfe664a7c7c2c34da4 Insights fetch NSURL timeout — transient_single_incident
-- Resolves: a28bc5f83b1f6138fa52209670ce6f33 Ranking fetch NSURL timeout — transient_single_incident
-- Resolves: ce1435700937172317c9489d23d6cdd9 Water summary NSURL timeout — transient_single_incident
-- Resolves: d942b8feeb4d73dc64dc8b6b97b54de9 Weight load NSURL timeout — transient_single_incident
-- Resolves: 52d0423e83c1844095e0bd9e0531aeee Quests fetch NSURL timeout — transient_single_incident
-- Resolves: 848d373c01e05bd52b424a9bc023b1ec Quests error details NSURL timeout — transient_single_incident
-- Resolves: f324b178f92044cda6f540be2a4c3042 Reactions fetch NSURL timeout — transient_single_incident
-- Resolves: fe77032238d24fb131846bea52b3e5cd Push token save NSURL timeout twin — transient_single_incident
-- =============================================================================

BEGIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- Section 1: Migration-resolved fingerprints
--   Stamps `migration_resolved:<id>` via the canonical
--   `mark_fingerprints_resolved_by_migration` RPC. Wrapped in IF EXISTS so a
--   fresh DB without the bug-intel pipeline is safe to apply.
-- ─────────────────────────────────────────────────────────────────────────────

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public'
          AND p.proname = 'mark_fingerprints_resolved_by_migration'
    ) THEN
        RAISE NOTICE '[20260504_bug_intel_inbox_drain] mark_fingerprints_resolved_by_migration not present — skipping section 1';
        RETURN;
    END IF;

    -- Cardio route_coordinates JSONB cast — companion fix in same deploy.
    PERFORM public.mark_fingerprints_resolved_by_migration(
        '20260504_record_cardio_workout_jsonb_fix',
        ARRAY[
            'ed47235aacc85ca48e62488533eccab9',
            'dc1787c30c387f39f525a1d9ae22f4a9',
            'db636b01b92ebad2fa74167ecc5213ea',
            '791da679d303f736ffe558afd6222d35'
        ],
        'route_coordinates JSONB cast in record_cardio_workout RPC'
    );

    -- Challenge logProgress last_progress_at — drop_last_progress_at hotfix.
    PERFORM public.mark_fingerprints_resolved_by_migration(
        '20260629_fix_log_challenge_progress_drop_last_progress_at',
        ARRAY['5d4f9575f3b91842e2fcb143a71b0091'],
        'log_challenge_progress no longer writes the non-existent last_progress_at column'
    );
END $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- Section 2: code_fix:classifier_routing — now-suppressed by classifier branches
--   The PR shipping with this migration adds NetworkErrorClassifier branches
--   that route the matching errors as `.expectedUserState`, so future hits
--   never fire crash_reports / dev_session_logs entries / fingerprints.
--   Existing fingerprints on these classes are flipped resolved.
-- ─────────────────────────────────────────────────────────────────────────────

UPDATE public.bug_intelligence_fingerprints
SET status = 'resolved',
    resolved_at = COALESCE(resolved_at, NOW()),
    auto_resolved_reason = 'code_fix:classifier_routing'
WHERE fingerprint = ANY(ARRAY[
    -- Apple Sign In ASAuthorizationError — domain-typed branch added in
    -- NetworkErrorClassifier.swift + SocialAuthService routes through it.
    '8622fc3a062c9744222d8c174f7aa518',
    -- Password reset rate limit — routed via "rate limit" classifier branch;
    -- these FPs predate the SupabaseManager.requestPasswordReset rate-limit
    -- detection (build 27 / 32) and will not regress on current code.
    '9494490021466860c9a60a6f476ebf88',
    'e59866110c660b8de22352984d0b159f',
    'a22cd96f76784e01bf8f4e0c89433109',
    -- Daily quest duplicate-key (23505) — `duplicate key value violates`
    -- branch added to classifier as expectedUserState; pairs with ON
    -- CONFLICT restoration in 20260703 (in-flight). Symptom closed today,
    -- root cause closes when 20260703 deploys.
    'bb8db6c13848652a253a41efbadc871d',
    'da16c5c17b9230313fe5322fcd5c04e1',
    '015bf5a86d2bfcb50033edfe19825e53',
    '84138481f406a2e4a460870e132a2717',
    -- Daily quest 23505 single-incident twin from build 46 / 2026-04-21.
    'd40dc939ebb3aa71805daccc1e134ca8',
    -- Private-challenge duplicate-invite — `user already has a pending
    -- invite` branch added to classifier as expectedUserState.
    '60158c57ca60b68f5fe14529c9d4e8c0',
    'de033a163a7343ef8d81292931284c6d'
])
  AND status NOT IN ('resolved', 'wont_fix', 'duplicate');

-- ─────────────────────────────────────────────────────────────────────────────
-- Section 3: code_fix:warning_downgrade — `.error` → `.warning` in this PR
--   Lifts the message off the `level >= .error → CrashReportingService.reportError`
--   gate so future hits no longer fire crash_reports rows.
-- ─────────────────────────────────────────────────────────────────────────────

UPDATE public.bug_intelligence_fingerprints
SET status = 'resolved',
    resolved_at = COALESCE(resolved_at, NOW()),
    auto_resolved_reason = 'code_fix:warning_downgrade'
WHERE fingerprint = ANY(ARRAY[
    -- WHOOP rt_wiped — disconnect path is already at .warning in code; old FPs
    -- predate that downgrade and will not regress on current builds.
    'af583196a381ef711f9cf9342e2492aa',
    'aeb3794b27cea9b4dbe64a466df116b7',
    'a275f4b0dd45d4c80efb1c85d8c7cb0a',
    -- NotificationManager unknown notification type — `.error` → `.warning` in
    -- this PR (NotificationManager.swift:2344). Server drift bucket; no client
    -- side device error.
    '184e70c65630243e0e0b6f611decd0bd',
    'a20d732f56696c42efb7885cd2b076ee',
    -- MetricKit signal 9 — `.error` → `.warning` in this PR
    -- (AppPerformanceSystem.swift:90). Crashes already in MetricKit's own
    -- channel; the AppLogger.error duplicated them as `crash_reports`.
    '64dc89673a5c29291273ccbf7b53303a'
])
  AND status NOT IN ('resolved', 'wont_fix', 'duplicate');

-- ─────────────────────────────────────────────────────────────────────────────
-- Section 4: silent_fix — code already shipped a fix; FPs remain stuck open
-- ─────────────────────────────────────────────────────────────────────────────

UPDATE public.bug_intelligence_fingerprints
SET status = 'resolved',
    resolved_at = COALESCE(resolved_at, NOW()),
    auto_resolved_reason = 'silent_fix'
WHERE fingerprint = ANY(ARRAY[
    -- HealthKit sleep null start_time — fix shipped in HealthDataService.swift:
    -- guard `hours > 0`, synthesize end-time = now, start-time = now − hours,
    -- write canonical start/end to sleep_logs. Comment at lines 1265-1278
    -- references these exact fingerprints.
    '14b58e6ab5d2e626682ae52bddd11156',
    '9dd275520f9ae8e8dc2f8f87bf08c6a1',
    -- Weight HTTPError — WeightTrackingService.swift:435 already routes via
    -- NetworkErrorClassifier.log; old FPs predate the classifier conversion.
    '1fb4a278f13adafd8acb2e9cf77470b2',
    '6121691fd4ebfc9ca28b56e5f919b865'
])
  AND status NOT IN ('resolved', 'wont_fix', 'duplicate');

-- ─────────────────────────────────────────────────────────────────────────────
-- Section 5: code_fix:debug_only_path — symbol fires in DEBUG only
--   MainThreadWatchdog.start() body is `#if DEBUG` (AppPerformanceSystem.swift
--   ~line 901-915). TestFlight / App Store builds never start it. The
--   build-41 watchdog fingerprints captured DEBUG-instrumented internal
--   builds and will not regress on production.
-- ─────────────────────────────────────────────────────────────────────────────

UPDATE public.bug_intelligence_fingerprints
SET status = 'resolved',
    resolved_at = COALESCE(resolved_at, NOW()),
    auto_resolved_reason = 'code_fix:debug_only_path'
WHERE fingerprint = ANY(ARRAY[
    '97f51f027eb90d963fd22675590ad3bb',
    '18ff0951f7151b55cb7bbe25d0a72d19'
])
  AND status NOT IN ('resolved', 'wont_fix', 'duplicate');

-- ─────────────────────────────────────────────────────────────────────────────
-- Section 6: silent_fix — HealthKit cardio_workouts goal_type stale-client
--   Migration 20260814_cardio_native_columns.sql widened the goal_type CHECK
--   to canonical lowercase set ('open','time','distance','calories','pace')
--   on 2026-05-02. Same PR updated iOS writers (HealthDataService /
--   FitbitService / StravaService) to write 'open' instead of 'open_goal'.
--   Crashes from build < 65 still fire as users on older clients write the
--   pre-canonical 'open_goal' which now violates the constraint. Once those
--   users update, the fingerprints stop accruing. (BUG_INTELLIGENCE_AGENT
--   stale-fix grace pattern.)
--
--   We mark these `migration_resolved:20260814_cardio_native_columns`
--   directly (no Resolves: directive in #184's header — pre-Phase-12 flow,
--   replayed here per Phase-13 backfill convention).
-- ─────────────────────────────────────────────────────────────────────────────

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public'
          AND p.proname = 'mark_fingerprints_resolved_by_migration'
    ) THEN
        RAISE NOTICE '[20260504_bug_intel_inbox_drain] section 6 skipped (mark_fingerprints_resolved_by_migration absent)';
        RETURN;
    END IF;

    PERFORM public.mark_fingerprints_resolved_by_migration(
        '20260814_cardio_native_columns',
        ARRAY[
            -- crash-source variants by activity type
            '8d99f89bd5d97665cef6b8ec427ed519', -- Apple Watch Strength Training
            'bb953e966378dd416da024b5df8d6610', -- Apple Watch Walk
            '12b776fa0d6139fd2d0834e25de7137a', -- Apple Watch Workout
            'c07bf1f419f02c855ec7805c4b776eba', -- Apple Watch Core Training
            '54896d9fe7f2e7bbebae6749d0a8a1cf', -- Runna Run
            '5ee92c5a7446b7bf2658cdb86875e26d', -- Apple Watch HIIT
            '95c134c8c6f93c21fae8183b732bf364', -- Apple Watch Elliptical
            '6720df3aa51b081830477f94647bec12', -- Apple Watch Run
            'd25288afa5bdb8696ea654d3fcd5c83f', -- Apple Watch Cross Training
            'f77e7c684c29003371c806c42e52fce8', -- Gymverse Strength Training
            -- log-source variants
            'c24d6ce6df338fab3dd8aa8c9933ad92', -- Apple Watch Strength Training (log)
            '0af7f12234d8096caba00f74582952fd', -- Gymverse Strength Training (log)
            'a8ef65b09ad2de56a108b5befa3e5014', -- Apple Watch Walk (log)
            'a3f4c58722e74dea88b6e66cfd7754e9', -- Apple Watch HIIT (log)
            '5368fb6a1c7b9346a14c230b3b5b5d3c', -- Apple Watch Workout (log)
            'be2752276445dfbb425806407308f37a', -- Apple Watch Elliptical (log)
            'c9fc33ed3c6a21e5f469ea102e17cbe0', -- Apple Watch Run (log)
            'e34775f16d4bd506469ce22ff778afa5', -- Apple Watch Core Training (log)
            '871c7fd1e084e807ad237452cef04515', -- Apple Watch Cross Training (log)
            'fdc3cee5c7268b6c9f74b1467347397f'  -- Runna Run (log)
        ],
        'goal_type CHECK widening + iOS writers updated to canonical lowercase set'
    );

    -- Stamp `latest_resolving_migration_at` so the 48h stale-fix grace filter
    -- applies to any post-deploy stale-client repeats.
    IF EXISTS (
        SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public'
          AND p.proname = 'bug_intel_register_migration_deploy'
    ) THEN
        PERFORM public.bug_intel_register_migration_deploy(
            '20260814_cardio_native_columns',
            ARRAY[
                '8d99f89bd5d97665cef6b8ec427ed519',
                'bb953e966378dd416da024b5df8d6610',
                '12b776fa0d6139fd2d0834e25de7137a',
                'c07bf1f419f02c855ec7805c4b776eba',
                '54896d9fe7f2e7bbebae6749d0a8a1cf',
                '5ee92c5a7446b7bf2658cdb86875e26d',
                '95c134c8c6f93c21fae8183b732bf364',
                '6720df3aa51b081830477f94647bec12',
                'd25288afa5bdb8696ea654d3fcd5c83f',
                'f77e7c684c29003371c806c42e52fce8',
                'c24d6ce6df338fab3dd8aa8c9933ad92',
                '0af7f12234d8096caba00f74582952fd',
                'a8ef65b09ad2de56a108b5befa3e5014',
                'a3f4c58722e74dea88b6e66cfd7754e9',
                '5368fb6a1c7b9346a14c230b3b5b5d3c',
                'be2752276445dfbb425806407308f37a',
                'c9fc33ed3c6a21e5f469ea102e17cbe0',
                'e34775f16d4bd506469ce22ff778afa5',
                '871c7fd1e084e807ad237452cef04515',
                'fdc3cee5c7268b6c9f74b1467347397f'
            ]
        );
    END IF;
END $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- Section 7: transient_single_incident — manual drain for FPs the cron skipped
--   The 30 4 * * * cron `bug_intel_resolve_single_incident_transients` only
--   fires for `class IN ('timeout','offline','network_lost', ...)`. The
--   build-41 (2026-04-20) NSURL timeout pile passes that gate; the watchdog /
--   weight / auth / 23505 single-incidents from the same date have non-
--   transient class values and are stuck open. We stamp the canonical reason
--   so reporting bucketing stays consistent.
-- ─────────────────────────────────────────────────────────────────────────────

UPDATE public.bug_intelligence_fingerprints
SET status = 'resolved',
    resolved_at = COALESCE(resolved_at, NOW()),
    auto_resolved_reason = 'transient_single_incident'
WHERE fingerprint = ANY(ARRAY[
    -- Build-41 / 2026-04-20 NSURL timeout single-incidents (drainer-eligible
    -- by class but waiting on the 14-day silent threshold; nudge them now
    -- since we're already auditing the inbox)
    'b6a8bec9302467aec7f86cc83c1d2090',
    '630c59c73777b77633850e9ff7f8bd1e',
    '411d1ccd9e73bbbfe664a7c7c2c34da4',
    'a28bc5f83b1f6138fa52209670ce6f33',
    'ce1435700937172317c9489d23d6cdd9',
    'd942b8feeb4d73dc64dc8b6b97b54de9',
    '52d0423e83c1844095e0bd9e0531aeee',
    '848d373c01e05bd52b424a9bc023b1ec',
    'f324b178f92044cda6f540be2a4c3042',
    'fe77032238d24fb131846bea52b3e5cd'
])
  AND occurrence_count = 1
  AND unique_user_count = 1
  AND status NOT IN ('resolved', 'wont_fix', 'duplicate');

-- ─────────────────────────────────────────────────────────────────────────────
-- Section 8: auth refresh race — JWT expired during background log
--   `9a4b5b9e` is "Error logging private challenge progress: JWT expired" —
--   the 60s window between SDK token refresh and the next call. Already
--   routed as `.authExpired` (warning, not error) in the classifier. Old FP
--   predates routing.
-- ─────────────────────────────────────────────────────────────────────────────

UPDATE public.bug_intelligence_fingerprints
SET status = 'resolved',
    resolved_at = COALESCE(resolved_at, NOW()),
    auto_resolved_reason = 'code_fix:classifier_routing'
WHERE fingerprint = '9a4b5b9e58d06c908692f28684a024f1'
  AND status NOT IN ('resolved', 'wont_fix', 'duplicate');

-- ─────────────────────────────────────────────────────────────────────────────
-- Section 9: bug_intel_noise_filter — tunable suppressions
--   Adding hard-tier rows for patterns that the classifier now routes; the
--   denylist mirrors the classifier per BUG_INTELLIGENCE_AGENT invariant 3
--   (Swift-side classifier branch ↔ server-side noise filter pair). Any
--   future hit (in case a stale client still emits the message) gets
--   filtered at compute_daily_bug_rollup time before fingerprinting.
-- ─────────────────────────────────────────────────────────────────────────────

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_schema = 'public' AND table_name = 'bug_intel_noise_filter'
    ) THEN
        RAISE NOTICE '[20260504_bug_intel_inbox_drain] bug_intel_noise_filter table absent — skipping section 9';
        RETURN;
    END IF;

    -- Insert tunable rows. `message_pattern` is matched (LIKE-style) against
    -- the rolled-up `sample_message` inside compute_daily_bug_rollup.
    -- `tier='hard'` deletes events before fingerprinting AND auto-resolves
    -- matching open fingerprints; `tier='soft'` only down-weights severity.
    -- Schema (`20260516_bug_intel_structural_fingerprint.sql`):
    --   id, name (UNIQUE), op, pg_code, nsurl_code, http_status,
    --   message_pattern, tier, rationale, created_by, created_at.
    INSERT INTO public.bug_intel_noise_filter (
        name, message_pattern, pg_code, tier, rationale, created_by
    )
    VALUES
        -- Apple Sign In domain — already classifier-routed. Belt-and-suspenders.
        ('apple_signin_user_cancel',
         '%authorizationerror error 1001%',
         NULL,
         'hard',
         'ASAuthorizationError 1001 (canceled). Classifier returns expectedUserState; this filter catches log-only emissions from older clients pre-classifier-routing. (Bug-intel 8622fc3a.)',
         'migration_20260504_inbox_drain'),

        -- Password reset rate limit — classifier-routed via "rate limit" branch.
        ('auth_password_reset_rate_limit',
         '%email rate limit exceeded%',
         NULL,
         'hard',
         'GoTrue 429 over_email_send_rate_limit during password reset. Classifier returns transientNetwork (rate-limit branch). (Bug-intel 9494490 / e598661 / a22cd96f.)',
         'migration_20260504_inbox_drain'),

        -- Daily quest duplicate-key — server fix in 20260703 (in-flight).
        ('daily_quest_duplicate_key',
         '%user_daily_quests_user_id_quest_date_quest_key_key%',
         '23505',
         'hard',
         'Concurrent get_daily_quests races on slate INSERT. Server fix in 20260703 (in-flight); classifier routes as expectedUserState today. (Bug-intel bb8db6c1 / da16c5c1 / 015bf5a8 / 84138481.)',
         'migration_20260504_inbox_drain'),

        -- WHOOP refresh-token cleanup — intentional disconnect path.
        ('whoop_refresh_token_cleanup',
         '%refresh token wiped%',
         NULL,
         'hard',
         'WhoopService.disconnect on rt_wiped_keychain_readable. Already at .warning in code; this catches log emissions from clients pre-warning-downgrade. (Bug-intel af583196 / aeb3794b / a275f4b0.)',
         'migration_20260504_inbox_drain'),

        -- Notification unknown type — server drift, not a client crash.
        ('notification_unknown_type',
         '%unknown notification type received from server%',
         NULL,
         'hard',
         'NotificationManager allowlist miss. Now .warning in code; the server-side push pipeline owns coverage drift. (Bug-intel 184e70c6 / a20d732f.)',
         'migration_20260504_inbox_drain'),

        -- MetricKit duplicate-channel logs (SIGKILL, jetsam, OOM, watchdog).
        ('metrickit_duplicate_log',
         '%[METRICKIT] Crash diagnostic%',
         NULL,
         'hard',
         'MetricKit reports OS-recorded crashes via its own pipeline; the AppLogger.warning entry in AppPerformanceSystem is trace context — should not refingerprint. (Bug-intel 64dc8967.)',
         'migration_20260504_inbox_drain'),

        -- Watchdog deadlock (DEBUG-only, never Release).
        ('main_thread_watchdog_debug',
         '%[WATCHDOG] Main thread blocked%',
         NULL,
         'hard',
         'MainThreadWatchdog.start() is #if DEBUG-gated; logs only originate from internal builds, never TestFlight / App Store. (Bug-intel 97f51f02 / 18ff0951.)',
         'migration_20260504_inbox_drain'),

        -- Private challenge duplicate invite — expected idempotent outcome.
        ('private_challenge_duplicate_invite',
         '%user already has a pending invite%',
         NULL,
         'hard',
         'PrivateChallengeService.inviteUser idempotent retry. Classifier returns expectedUserState. (Bug-intel 60158c57 / de033a16.)',
         'migration_20260504_inbox_drain')
    ON CONFLICT (name) DO UPDATE
        SET message_pattern = EXCLUDED.message_pattern,
            pg_code         = EXCLUDED.pg_code,
            tier            = EXCLUDED.tier,
            rationale       = EXCLUDED.rationale;
END $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- Audit: post-state proof
-- ─────────────────────────────────────────────────────────────────────────────

DO $$
DECLARE
    v_open_before INT;
    v_open_after  INT;
    v_drained     INT;
BEGIN
    -- A rough "still-open" count post-drain. Excludes terminal statuses.
    SELECT COUNT(*) INTO v_open_after
    FROM public.bug_intelligence_fingerprints
    WHERE status NOT IN ('resolved', 'wont_fix', 'duplicate');

    RAISE NOTICE '[20260504_bug_intel_inbox_drain] post-drain open fingerprints: %', v_open_after;
END $$;

-- PostgREST schema reload — strictly redundant (no schema-shape change), but
-- the inbox tab in the CMS uses the materialized view `v_bug_intelligence_inbox`
-- joins against `bug_intelligence_fingerprints.status` which we just touched.
NOTIFY pgrst, 'reload schema';

COMMIT;
