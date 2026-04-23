-- ═══════════════════════════════════════════════════════════════════════════
-- Q2-97 Phase 5 — Server-side dSYM symbolication scaffolding
-- Date: 2026-05-01 · Paired with: docs/history/PHASE_5_SYMBOLICATION_PLAN.md
--
-- Goal: convert raw hex stack traces into `file:line:function` by uploading
-- each Archive build's .dSYM to Supabase Storage and running Apple's `atos`
-- on a scheduled macOS GitHub Actions runner. This migration ships ONLY the
-- database + storage scaffolding; the runner workflow (5.5), the iOS client
-- change (5.1), and the triage-bugs read path (5.6) are separate commits.
--
-- Design notes:
-- - We key off `binary_uuid` (the main-image UUID Apple embeds in every
--   build). TestFlight rebuilds of the same "v1.37 (47)" produce DIFFERENT
--   binary_uuids, so app_version alone is insufficient for mapping crashes
--   to dSYMs. `binary_uuid` is the authoritative join.
-- - `binary_slide` is the ASLR offset captured at crash time; `atos -l <slide>`
--   needs it to resolve addresses. Not a fingerprint — changes every run.
-- - Existing (~9,500) crashes get `symbolication_status = 'legacy'` in a
--   one-shot backfill because we don't have their dSYMs. They keep using
--   Phase 3.1's tag-based fallback.
-- - Storage bucket is PRIVATE. The macOS runner downloads dSYMs via the
--   service-role key (set as a secret in the workflow). Admins upload via
--   the Archive post-action script authenticated with their session.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

-- ─── 1. app_dsyms: one row per Archive build ──────────────────────────────
-- Populated by scripts/upload_dsym.sh (Phase 5.4). Read by the GitHub
-- Actions symbolicate-crashes workflow (Phase 5.5).
CREATE TABLE IF NOT EXISTS app_dsyms (
    binary_uuid     UUID         PRIMARY KEY,
    app_version     TEXT         NOT NULL,
    build_number    TEXT         NOT NULL,
    storage_path    TEXT         NOT NULL UNIQUE,
    size_bytes      BIGINT,
    sha256          TEXT,
    uploaded_at     TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    uploaded_by     UUID         REFERENCES user_profiles(id) ON DELETE SET NULL,
    notes           TEXT
);

CREATE INDEX IF NOT EXISTS idx_app_dsyms_version_build
    ON app_dsyms(app_version, build_number);

COMMENT ON TABLE app_dsyms IS
    'Q2-97 Phase 5 · One row per uploaded .dSYM bundle, keyed by main-image binary_uuid. Read by the symbolicate-crashes GitHub Actions workflow to locate the correct dSYM for each pending crash. admin / service_role only.';

-- ─── 2. crash_reports: new symbolication columns ──────────────────────────
ALTER TABLE crash_reports
    ADD COLUMN IF NOT EXISTS binary_uuid              UUID,
    ADD COLUMN IF NOT EXISTS binary_slide             TEXT,
    ADD COLUMN IF NOT EXISTS symbolicated_stack_trace TEXT,
    ADD COLUMN IF NOT EXISTS symbolication_status     TEXT
        NOT NULL DEFAULT 'pending',
    ADD COLUMN IF NOT EXISTS symbolicated_at          TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS symbolication_error      TEXT;

-- CHECK constraint added separately so we can drop+recreate safely if the
-- enum grows. CHECK is defined on the literal set of states the workflow
-- understands: pending, done, failed (with error), legacy (pre-Phase 5
-- crashes with no dSYM), no_dsym (Phase 5 crash but upload_dsym.sh never
-- ran for that build).
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM information_schema.table_constraints
        WHERE table_name = 'crash_reports'
          AND constraint_name = 'crash_reports_symbolication_status_check'
    ) THEN
        ALTER TABLE crash_reports
            ADD CONSTRAINT crash_reports_symbolication_status_check
            CHECK (symbolication_status IN ('pending','done','failed','legacy','no_dsym'));
    END IF;
END $$;

-- Hot-path index: the worker scans `WHERE symbolication_status = 'pending'
-- ORDER BY occurred_at ASC LIMIT 50` every 15 minutes. Partial index keeps
-- it tiny (most crashes will be `done`).
CREATE INDEX IF NOT EXISTS idx_crash_reports_symbolication_pending
    ON crash_reports(occurred_at ASC)
    WHERE symbolication_status = 'pending';

-- Join index for `crash_reports.binary_uuid → app_dsyms.binary_uuid`
CREATE INDEX IF NOT EXISTS idx_crash_reports_binary_uuid
    ON crash_reports(binary_uuid)
    WHERE binary_uuid IS NOT NULL;

COMMENT ON COLUMN crash_reports.binary_uuid IS
    'Q2-97 Phase 5 · Main-image UUID captured at crash time (dyld_image_uuid(0)). Joins to app_dsyms.binary_uuid. NULL for pre-Phase-5 crashes.';
COMMENT ON COLUMN crash_reports.binary_slide IS
    'Q2-97 Phase 5 · ASLR slide (as hex string, e.g. "0x104000000") captured at crash time. Passed to atos -l <slide>.';
COMMENT ON COLUMN crash_reports.symbolicated_stack_trace IS
    'Q2-97 Phase 5 · `atos` output for the raw stack_trace addresses, in the same line order as the source. Read by triage-bugs when non-null.';
COMMENT ON COLUMN crash_reports.symbolication_status IS
    'Q2-97 Phase 5 · Lifecycle state — pending / done / failed / legacy / no_dsym. See crash_reports_symbolication_status_check for the authoritative set.';

-- ─── 3. Backfill: mark existing crashes as `legacy` ───────────────────────
-- Per the Phase 5 plan (option A, confirmed 2026-05-01 with user), we do
-- NOT attempt to retroactively symbolicate pre-Phase-5 crashes. They stay
-- `symbolication_status = 'legacy'` forever and keep using Phase 3.1's
-- error-message-tag fallback in triage-bugs.
UPDATE crash_reports
   SET symbolication_status = 'legacy'
 WHERE binary_uuid IS NULL
   AND symbolication_status = 'pending';

-- ─── 4. RLS on app_dsyms ─────────────────────────────────────────────────
-- service_role only (dSYM uploads + worker reads). No policies — RLS +
-- no-policy = service-role-only, matching the pattern used by every
-- bug_intelligence_* table.
ALTER TABLE app_dsyms ENABLE ROW LEVEL SECURITY;

-- ─── 5. Storage bucket: `dsyms` ───────────────────────────────────────────
-- Private bucket. Each Archive produces a ~50-200MB zipped .dSYM, stored
-- at `<binary_uuid>.zip`. 6-month retention enforced out-of-band (not here
-- — storage retention isn't a migration concern).
INSERT INTO storage.buckets (id, name, public)
VALUES ('dsyms', 'dsyms', false)
ON CONFLICT (id) DO NOTHING;

-- Storage RLS — admin-only write, service-role-only read. Matches the
-- pattern for privileged buckets elsewhere in the project.
--
-- Write: authenticated admin via upload_dsym.sh. Admin is identified by a
--   `user_profiles.role = 'admin'` row (same check the admin CMS uses).
-- Read: service_role only (no public read). The macOS runner authenticates
--   with the service-role key stored as a GitHub Actions secret.
DROP POLICY IF EXISTS "dsyms_admin_write"  ON storage.objects;
DROP POLICY IF EXISTS "dsyms_admin_update" ON storage.objects;
DROP POLICY IF EXISTS "dsyms_admin_delete" ON storage.objects;

CREATE POLICY "dsyms_admin_write"
    ON storage.objects
    FOR INSERT
    TO authenticated
    WITH CHECK (
        bucket_id = 'dsyms'
        AND EXISTS (
            SELECT 1
            FROM user_profiles
            WHERE user_profiles.id = auth.uid()
              AND user_profiles.role = 'admin'
        )
    );

CREATE POLICY "dsyms_admin_update"
    ON storage.objects
    FOR UPDATE
    TO authenticated
    USING (
        bucket_id = 'dsyms'
        AND EXISTS (
            SELECT 1
            FROM user_profiles
            WHERE user_profiles.id = auth.uid()
              AND user_profiles.role = 'admin'
        )
    );

CREATE POLICY "dsyms_admin_delete"
    ON storage.objects
    FOR DELETE
    TO authenticated
    USING (
        bucket_id = 'dsyms'
        AND EXISTS (
            SELECT 1
            FROM user_profiles
            WHERE user_profiles.id = auth.uid()
              AND user_profiles.role = 'admin'
        )
    );

-- No SELECT policy on storage.objects for 'dsyms' — only service_role can
-- read (which bypasses RLS). The macOS runner uses the service-role key.

COMMIT;

-- ─── Sanity check (runs outside the txn) ─────────────────────────────────
DO $$
DECLARE
    v_total_crashes  BIGINT;
    v_legacy         BIGINT;
    v_pending        BIGINT;
    v_dsym_count     BIGINT;
BEGIN
    SELECT COUNT(*) INTO v_total_crashes FROM crash_reports;
    SELECT COUNT(*) INTO v_legacy        FROM crash_reports WHERE symbolication_status = 'legacy';
    SELECT COUNT(*) INTO v_pending       FROM crash_reports WHERE symbolication_status = 'pending';
    SELECT COUNT(*) INTO v_dsym_count    FROM app_dsyms;

    RAISE NOTICE 'Phase 5 scaffolding done:';
    RAISE NOTICE '  crash_reports total:   %', v_total_crashes;
    RAISE NOTICE '  marked legacy:         %', v_legacy;
    RAISE NOTICE '  remaining pending:     % (should be 0 until Phase 5.1 ships)', v_pending;
    RAISE NOTICE '  app_dsyms rows:        % (expected 0 — fills up as builds archive)', v_dsym_count;
    RAISE NOTICE '  next steps: 5.1 iOS populates binary_uuid; 5.4 upload_dsym.sh seeds app_dsyms; 5.5 workflow fills symbolicated_stack_trace.';
END $$;
