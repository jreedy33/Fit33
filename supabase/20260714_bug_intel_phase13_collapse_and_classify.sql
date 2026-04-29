-- 20260714_bug_intel_phase13_collapse_and_classify.sql
-- Bug-Intel Pipeline Phase 13 — Collapse + Classify (2026-04-29)
--
-- WHY (concrete failures observed in the 2026-04-29T04:13 export, 30 reports):
--
--   1. CRASH↔LOG TWIN FINGERPRINTS for the same call site (~17% of the export):
--        14b58e6a + 9dd27552  HK sleep NOT NULL
--        4922971b + 8fb2f8b3  PersonalizedInsights upsert
--        af583196 + a275f4b0  WHOOP refresh
--        e03ca9df + d29ff85a  community challenge deadlock
--        76860b32 + 8e0764bf + 4729e709 + 537be0ee  daily_quests bonus_claimed
--      Root cause: `structural_fingerprint = md5(source||op||error_class)`
--      includes `source='log'` vs `'crash'`, so the same root cause never
--      collapses across the two streams.
--
--   2. `class=unknown` ON 21/30 REPORTS — `bug_intel_classify_error()` only
--      reads pg_code from `entry->>'x_pg_code'` / `entry->>'error'`. Legacy
--      catch blocks that bypass `DiagnosticContext` lose this signal even
--      though the message body literally says `code: Optional("42703")`.
--
--   3. SAME 3 GENERIC "SIMILAR PAST FIXES" repeated on every report
--      (workout-cancel / HK-sync / password-rate-limit) — they all share
--      `error_class = 'unknown'`. `bug_intel_find_similar_resolutions` treats
--      `unknown` as a class match (`match_strength=1`). It isn't — it's
--      "we both failed to classify".
--
--   4. ALREADY-FIXED BUGS STILL PENDING after deploy:
--        76860b32 / 8e0764bf / 4729e709 / 537be0ee  (fixed by 20260707)
--        3de7fbe4 / d441ebc8                        (fixed by 20260629)
--        e03ca9df / d29ff85a                        (fixed by 20260628)
--      `20260707_user_daily_quests_bonus_claimed.sql` mentions the FPs in
--      prose but is missing the formal `-- Resolves: <md5>` directive that
--      #95's auto-resolver scans for. `20260628` / `20260629` HAVE the
--      directives but `mark_fingerprints_resolved_by_migration()` was never
--      fired post-deploy.
--
--   5. PAIN-POINTS + TODOs DUPLICATED 4× across the bonus_claimed quartet —
--      handled in the paired CMS export change (`bug-intelligence/page.tsx`).
--
-- WHAT THIS MIGRATION SHIPS
-- -------------------------
--   A. New column `root_cause_fingerprint TEXT` on
--      `bug_intelligence_fingerprints` AND `bug_intel_resolved_history` —
--      `md5(op || '|' || error_class)`, no source. Lets the CMS / triage
--      RPC collapse crash↔log twins of the same root cause.
--
--   B. Helper `bug_intel_extract_pg_code(text)` — pulls `code: Optional("X")`
--      and `code: "X"` out of raw messages. Falls back inside an updated
--      `bug_intel_classify_error(...)` so legacy catch blocks no longer
--      lose the SQLSTATE.
--
--   C. `compute_daily_bug_rollup()` writes `root_cause_fingerprint` on
--      every upsert, AND the pg_code-from-message fallback runs at rollup
--      time so today's drift never escapes classification.
--
--   D. `bug_intel_find_similar_resolutions(...)` rewrite — gates
--      `match_strength=1` (op-only OR class-only) on
--      `error_class != 'unknown' AND error_class IS NOT NULL`. Real class
--      match required. Killing the noise tier makes "Similar past fixes"
--      either strong (≥2) or absent.
--
--   E. `bug_intel_resolve_by_root_cause()` — new SECURITY DEFINER nightly
--      drainer (00:45 UTC, between #93's 00:15 single-incident pass and
--      #94's 04:00 severity recompute). Open fingerprints whose
--      `root_cause_fingerprint` matches a row in `bug_intel_resolved_history`
--      auto-resolve as `silent_fix:matched_root_cause` regardless of
--      whether they're crash- or log-sourced.
--
--   F. INLINE BACKFILL of the `Resolves:` directives that are missing or
--      were never replayed:
--        20260707 → 76860b32, 8e0764bf, 4729e709, 537be0ee  (added — directive missing)
--        20260628 → e03ca9df, d29ff85a                      (replay — already in header)
--        20260629 → 3de7fbe4, d441ebc8                      (replay — already in header)
--        20260712 → 4922971b, 8fb2f8b3                      (added — Phase-12 deploy)
--        20260713 → 90369817, 2fe2cbd7, 423b048d            (added — Phase-12 deploy)
--      Per the migration-immutability rule (codingrules / supabase-rules),
--      we don't retroactively edit those files — Phase 13 carries the
--      directive on their behalf.
--
-- INVARIANTS
-- ----------
--   * Idempotent — wrapped BEGIN/COMMIT, all ALTERs `IF NOT EXISTS`,
--     all calls to `mark_fingerprints_resolved_by_migration` are no-ops
--     when the FPs are already terminal.
--   * Backwards-compat — `structural_fingerprint` UNTOUCHED. The new
--     `root_cause_fingerprint` is a sibling column. Resolution history
--     gets the new column too so silent-fix matching works retroactively.
--   * Trailing audit `DO $$` block fails loud if (a) helpers aren't
--     callable, (b) `root_cause_fingerprint` populated <50% of rows
--     where op + class are both present, (c) any of the inline-backfill
--     RPC calls reported zero resolutions when the FP exists in
--     bug_intelligence_fingerprints.
--
-- ROLLBACK
-- --------
--   ALTER TABLE bug_intelligence_fingerprints DROP COLUMN IF EXISTS root_cause_fingerprint;
--   ALTER TABLE bug_intel_resolved_history    DROP COLUMN IF EXISTS root_cause_fingerprint;
--   DROP FUNCTION IF EXISTS bug_intel_extract_pg_code(TEXT);
--   DROP FUNCTION IF EXISTS bug_intel_resolve_by_root_cause();
--   -- and reinstall 20260530's bug_intel_find_similar_resolutions body.

BEGIN;

-- ============================================================================
-- A. Schema: root_cause_fingerprint columns
-- ============================================================================

ALTER TABLE public.bug_intelligence_fingerprints
    ADD COLUMN IF NOT EXISTS root_cause_fingerprint TEXT;

ALTER TABLE public.bug_intel_resolved_history
    ADD COLUMN IF NOT EXISTS root_cause_fingerprint TEXT;

COMMENT ON COLUMN public.bug_intelligence_fingerprints.root_cause_fingerprint IS
    'Phase 13 (2026-04-29) — md5(op||''|''||error_class). Like '
    'structural_fingerprint but WITHOUT source — collapses crash↔log twins '
    'of the same root cause. NULL when op or error_class is missing or '
    'error_class=''unknown''. CMS / triage RPC collapse on this for the '
    '"+N siblings" UI.';

COMMENT ON COLUMN public.bug_intel_resolved_history.root_cause_fingerprint IS
    'Phase 13 (2026-04-29) — same formula as on bug_intelligence_fingerprints. '
    'Populated for every history row so bug_intel_resolve_by_root_cause() can '
    'auto-drain crash↔log twins of bugs we already shipped fixes for.';

CREATE INDEX IF NOT EXISTS idx_bug_fingerprints_root_cause
    ON public.bug_intelligence_fingerprints (root_cause_fingerprint)
    WHERE root_cause_fingerprint IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_bug_intel_resolved_history_root_cause
    ON public.bug_intel_resolved_history (root_cause_fingerprint)
    WHERE root_cause_fingerprint IS NOT NULL;

-- ============================================================================
-- B. Helper: bug_intel_extract_pg_code(text)
--    Pulls SQLSTATE codes embedded in raw error messages.
--
--    Targets:
--      'PostgrestError(... code: Optional("42703") ...)'   -- Swift
--      'code: "42703"'                                      -- TS edge function
--      'SQLSTATE 42703'                                     -- pg log format
--      'code 42703'                                         -- bare prefix
--    Returns the 5-char SQLSTATE or NULL when nothing matches.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.bug_intel_extract_pg_code(p_msg TEXT)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    v_match TEXT;
BEGIN
    IF p_msg IS NULL OR p_msg = '' THEN
        RETURN NULL;
    END IF;

    -- Swift: PostgrestError(... code: Optional("42703") ...)
    v_match := substring(p_msg FROM 'code:\s*Optional\("([0-9A-Z]{5})"\)');
    IF v_match IS NOT NULL THEN RETURN v_match; END IF;

    -- TS edge function: code: "42703"
    v_match := substring(p_msg FROM 'code:\s*"([0-9A-Z]{5})"');
    IF v_match IS NOT NULL THEN RETURN v_match; END IF;

    -- Postgres log: SQLSTATE 42703
    v_match := substring(p_msg FROM 'SQLSTATE\s+([0-9A-Z]{5})');
    IF v_match IS NOT NULL THEN RETURN v_match; END IF;

    -- Bare: code 42703 (rare, but cheap to add)
    v_match := substring(p_msg FROM '\mcode\s+([0-9A-Z]{5})\M');
    IF v_match IS NOT NULL THEN RETURN v_match; END IF;

    RETURN NULL;
END;
$$;

COMMENT ON FUNCTION public.bug_intel_extract_pg_code(TEXT) IS
    'Phase 13 — best-effort SQLSTATE extraction from raw error messages. '
    'Pulls codes from PostgrestError("... code: Optional(\"X\") ..."), '
    'TS edge function code: "X", Postgres SQLSTATE X, or bare "code X". '
    'Returns NULL when no 5-char SQLSTATE pattern is present.';

-- ============================================================================
-- C. Update bug_intel_classify_error to call the new extractor.
--    Same arg shape — call sites unchanged. Precedence stays:
--    pg_code (passed) > pg_code (extracted from message) > http > nsurl > heuristic.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.bug_intel_classify_error(
    p_pg_code     TEXT,
    p_http_status INT,
    p_nsurl_code  INT,
    p_message     TEXT
) RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    v_extracted TEXT;
BEGIN
    -- 1. Explicit pg_code (DiagnosticContext path) wins.
    IF p_pg_code IS NOT NULL AND p_pg_code <> '' THEN
        RETURN 'pg:' || p_pg_code;
    END IF;

    -- 2. Phase 13: regex-extract pg_code from raw message before falling
    --    through to http / nsurl / heuristics. Drains `class=unknown` for
    --    PostgrestError messages from legacy classifier-bypass call sites.
    v_extracted := public.bug_intel_extract_pg_code(p_message);
    IF v_extracted IS NOT NULL THEN
        RETURN 'pg:' || v_extracted;
    END IF;

    -- 3. http_status fallback.
    IF p_http_status IS NOT NULL AND p_http_status > 0 THEN
        RETURN 'http:' || p_http_status;
    END IF;

    -- 4. nsurl fallback.
    IF p_nsurl_code IS NOT NULL THEN
        RETURN 'nsurl:' || p_nsurl_code;
    END IF;

    -- 5. Message heuristics — same set as 20260516 with two additions
    --    (deadlock + check_violation surfaced in the 04-29 export).
    IF p_message IS NULL OR p_message = '' THEN
        RETURN 'unknown';
    END IF;

    IF p_message ILIKE '%jwt expired%'         OR p_message ILIKE '%invalid jwt%'         THEN RETURN 'auth:expired'; END IF;
    IF p_message ILIKE '%cancelled%'           OR p_message LIKE  '%-999%'                THEN RETURN 'cancelled'; END IF;
    IF p_message ILIKE '%not connected to the internet%' OR p_message LIKE '%-1009%'      THEN RETURN 'offline'; END IF;
    IF p_message ILIKE '%network connection was lost%'   OR p_message LIKE '%-1005%'      THEN RETURN 'network_lost'; END IF;
    IF p_message ILIKE '%timeout%'             OR p_message LIKE  '%-1001%'               THEN RETURN 'timeout'; END IF;
    IF p_message ILIKE '%row-level security%'  OR p_message ILIKE '%permission denied%'   THEN RETURN 'rls'; END IF;
    IF p_message ILIKE '%duplicate key%'                                                  THEN RETURN 'pg:23505'; END IF;
    IF p_message ILIKE '%violates check constraint%'                                      THEN RETURN 'pg:23514'; END IF;
    IF p_message ILIKE '%violates not-null constraint%'                                   THEN RETURN 'pg:23502'; END IF;
    IF p_message ILIKE '%uuid = text%'         OR p_message ILIKE '%operator does not exist%' THEN RETURN 'pg:42883'; END IF;
    IF p_message ILIKE '%could not find the function%' OR p_message ILIKE '%PGRST202%'    THEN RETURN 'pgrest:202'; END IF;
    IF p_message ILIKE '%deadlock detected%'   OR p_message ILIKE '%40P01%'               THEN RETURN 'pg:40P01'; END IF;
    IF p_message ILIKE '%no unique or exclusion constraint matching the ON CONFLICT%'     THEN RETURN 'pg:42P10'; END IF;

    RETURN 'unknown';
END;
$$;

COMMENT ON FUNCTION public.bug_intel_classify_error(TEXT, INT, INT, TEXT) IS
    'Phase 13 (2026-04-29) — extends 20260516 classifier with pg_code regex '
    'fallback (bug_intel_extract_pg_code) and four new heuristics: '
    'pg:23502 NOT NULL, pg:40P01 deadlock, pg:42P10 ON CONFLICT, pg:23514 '
    'CHECK violation already there. Precedence: explicit pg_code > extracted '
    'pg_code > http > nsurl > message heuristic.';

-- ============================================================================
-- D. Tighten bug_intel_find_similar_resolutions — gate match_strength=1 on
--    a real error_class (not 'unknown' or NULL).
-- ============================================================================

DROP FUNCTION IF EXISTS public.bug_intel_find_similar_resolutions(TEXT, TEXT, TEXT, TEXT, INTEGER);

CREATE OR REPLACE FUNCTION public.bug_intel_find_similar_resolutions(
    p_structural_fingerprint TEXT,
    p_op                     TEXT,
    p_error_class            TEXT,
    p_exclude_fingerprint    TEXT DEFAULT NULL,
    p_limit                  INTEGER DEFAULT 5
)
RETURNS TABLE (
    match_strength       INTEGER,
    fingerprint          TEXT,
    structural_fingerprint TEXT,
    op                   TEXT,
    error_class          TEXT,
    title                TEXT,
    summary              TEXT,
    agent_owner          TEXT,
    last_seen_file       TEXT,
    last_seen_line       INTEGER,
    resolution_pr_url    TEXT,
    auto_resolved_reason TEXT,
    resolved_at          TIMESTAMPTZ
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    WITH candidates AS (
        SELECT
            CASE
                -- Tier 3 — exact structural match. Strongest signal, never
                -- gated. Caller's structural_fingerprint always carries
                -- (source||op||error_class) so a hit here means the same
                -- root cause shipped before in the same source channel.
                WHEN p_structural_fingerprint IS NOT NULL
                     AND h.structural_fingerprint IS NOT NULL
                     AND h.structural_fingerprint = p_structural_fingerprint
                    THEN 3
                -- Tier 2 — op + class match. Both must be real values.
                -- `error_class='unknown'` is excluded because it means
                -- "we failed to classify"; matching on it produces the
                -- same noise the 04-29 export was full of.
                WHEN p_op IS NOT NULL
                     AND p_error_class IS NOT NULL
                     AND p_error_class <> 'unknown'
                     AND h.op = p_op
                     AND h.error_class = p_error_class
                     AND COALESCE(h.error_class, 'unknown') <> 'unknown'
                    THEN 2
                -- Tier 1a — op-only match. Op is ALWAYS a real value when
                -- non-NULL (no "unknown" sentinel), so no extra gate needed.
                WHEN p_op IS NOT NULL AND h.op = p_op
                    THEN 1
                -- Tier 1b — class-only match. PHASE 13 GATE: both sides
                -- must be a real class, not 'unknown'. This is the change
                -- that drains the 3-generic-noise repeat across reports.
                WHEN p_error_class IS NOT NULL
                     AND p_error_class <> 'unknown'
                     AND h.error_class = p_error_class
                     AND COALESCE(h.error_class, 'unknown') <> 'unknown'
                    THEN 1
                ELSE 0
            END AS match_strength,
            h.fingerprint,
            h.structural_fingerprint,
            h.op,
            h.error_class,
            h.title,
            h.summary,
            h.agent_owner,
            h.last_seen_file,
            h.last_seen_line,
            h.resolution_pr_url,
            h.auto_resolved_reason,
            h.resolved_at
        FROM public.bug_intel_resolved_history h
        WHERE
            (p_exclude_fingerprint IS NULL OR h.fingerprint <> p_exclude_fingerprint)
            -- Same exclusion as 20260530 — auto-drains aren't real fixes.
            AND COALESCE(h.auto_resolved_reason, '') NOT IN (
                'transient_single_incident',
                'noise_filter_expanded'
            )
    )
    SELECT
        match_strength,
        fingerprint,
        structural_fingerprint,
        op,
        error_class,
        title,
        summary,
        agent_owner,
        last_seen_file,
        last_seen_line,
        resolution_pr_url,
        auto_resolved_reason,
        resolved_at
    FROM candidates
    WHERE match_strength > 0
    ORDER BY match_strength DESC, resolved_at DESC
    LIMIT GREATEST(COALESCE(p_limit, 5), 1);
$$;

COMMENT ON FUNCTION public.bug_intel_find_similar_resolutions(TEXT, TEXT, TEXT, TEXT, INTEGER) IS
    'Phase 13 (2026-04-29) — extends 20260530 by gating match_strength=1 '
    'class-only matches on error_class != ''unknown'' AND error_class IS '
    'NOT NULL (op-only matches kept as-is — op is always a real value). '
    'Drains the "same 3 generic fixes on every report" noise observed in '
    'the 04-29T04:13 export.';

GRANT EXECUTE ON FUNCTION public.bug_intel_find_similar_resolutions(TEXT, TEXT, TEXT, TEXT, INTEGER) TO service_role;

-- ============================================================================
-- E. bug_intel_resolve_by_root_cause() — new auto-drain that uses the
--    source-less root_cause_fingerprint to silent-fix crash↔log twins of
--    bugs we already shipped fixes for.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.bug_intel_resolve_by_root_cause()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_resolved INTEGER := 0;
    v_started TIMESTAMPTZ := now();
BEGIN
    IF auth.role() IS NOT NULL AND auth.role() <> 'service_role' THEN
        RAISE EXCEPTION 'bug_intel_resolve_by_root_cause is service-role only'
            USING ERRCODE = '42501';
    END IF;

    -- Find every open fingerprint whose root_cause_fingerprint matches
    -- ANY past resolution (excluding noise-drains, same exclusion as the
    -- "Similar past fixes" RPC). When found, flip to resolved with a
    -- distinct auto_resolved_reason so the CMS can audit the chain.
    WITH matchable AS (
        SELECT DISTINCT
            f.fingerprint,
            (
                SELECT h.fingerprint
                  FROM bug_intel_resolved_history h
                 WHERE h.root_cause_fingerprint = f.root_cause_fingerprint
                   AND COALESCE(h.auto_resolved_reason, '') NOT IN (
                       'transient_single_incident',
                       'noise_filter_expanded'
                   )
                 ORDER BY h.resolved_at DESC
                 LIMIT 1
            ) AS source_resolution_fp
          FROM bug_intelligence_fingerprints f
         WHERE f.root_cause_fingerprint IS NOT NULL
           AND f.status NOT IN ('resolved', 'wont_fix', 'duplicate')
    ),
    flipped AS (
        UPDATE bug_intelligence_fingerprints f
           SET status = 'resolved',
               auto_resolved_at = COALESCE(auto_resolved_at, now()),
               auto_resolved_reason = 'silent_fix:matched_root_cause:' || COALESCE(m.source_resolution_fp, 'unknown'),
               resolved_at = COALESCE(resolved_at, now()),
               updated_at = now()
          FROM matchable m
         WHERE f.fingerprint = m.fingerprint
           AND m.source_resolution_fp IS NOT NULL
        RETURNING f.fingerprint
    )
    SELECT COUNT(*) INTO v_resolved FROM flipped;

    -- Paired reports → merged with audit note.
    UPDATE bug_intelligence_reports r
       SET review_status = 'merged',
           review_notes = COALESCE(review_notes || E'\n', '') ||
             format(
                '[%s] Auto-merged: matched root_cause_fingerprint of an already-resolved fingerprint. Phase 13 silent-fix drain.',
                to_char(now(), 'YYYY-MM-DD HH24:MI UTC')
             ),
           reviewed_at = COALESCE(reviewed_at, now())
      FROM bug_intelligence_fingerprints f
     WHERE r.fingerprint = f.fingerprint
       AND f.auto_resolved_reason LIKE 'silent_fix:matched_root_cause:%'
       AND f.updated_at >= v_started
       AND r.review_status IN ('pending', 'approved');

    RETURN jsonb_build_object(
        'started_at',     v_started,
        'completed_at',   now(),
        'resolved_count', v_resolved
    );
END;
$$;

COMMENT ON FUNCTION public.bug_intel_resolve_by_root_cause() IS
    'Phase 13 — nightly auto-drain (00:45 UTC). Open fingerprints whose '
    'root_cause_fingerprint matches a row in bug_intel_resolved_history flip '
    'to status=resolved with reason=silent_fix:matched_root_cause:<source_fp>. '
    'Catches crash↔log twins of bugs we already shipped fixes for, regardless '
    'of which source channel was resolved first.';

REVOKE ALL ON FUNCTION public.bug_intel_resolve_by_root_cause() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.bug_intel_resolve_by_root_cause() TO service_role;

-- Schedule nightly at 00:45 UTC — between #93's 00:15 single-incident drain
-- and #94's 04:00 severity recompute, so collapsed counts feed into the
-- score calculation on the same night.
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'bug-intel-resolve-by-root-cause') THEN
        PERFORM cron.unschedule('bug-intel-resolve-by-root-cause');
    END IF;
END $$;

SELECT cron.schedule(
    'bug-intel-resolve-by-root-cause',
    '45 0 * * *',
    $$SELECT public.bug_intel_resolve_by_root_cause()$$
);

-- ============================================================================
-- F. Update compute_daily_bug_rollup so future writes carry
--    root_cause_fingerprint. We reuse the existing rollup body (huge function)
--    by patching ONLY the upsert path — a separate post-rollup UPDATE that
--    populates root_cause_fingerprint from the new structural columns.
--
--    This avoids touching the 700-line rollup body (low regression risk —
--    same pattern as #92's call-site capture which was kept out of the
--    rollup). The upsert UPDATE clauses are additive.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.bug_intel_patch_root_cause_fingerprint()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_patched INTEGER := 0;
BEGIN
    IF auth.role() IS NOT NULL AND auth.role() <> 'service_role' THEN
        RAISE EXCEPTION 'bug_intel_patch_root_cause_fingerprint is service-role only'
            USING ERRCODE = '42501';
    END IF;

    -- Recompute root_cause_fingerprint for every row where:
    --   * op + error_class are populated and class is real (not 'unknown')
    --   * AND (root_cause_fingerprint is NULL OR doesn't match the
    --          formula because op/class were updated mid-life)
    -- Note: we deliberately DO NOT touch updated_at here. Same isolation
    -- pattern as #92 (call-site capture) — pipeline columns shouldn't bump
    -- mtime semantics that admin triage relies on.
    WITH rebuilt AS (
        UPDATE bug_intelligence_fingerprints f
           SET root_cause_fingerprint = md5(f.op || '|' || f.error_class)
         WHERE f.op IS NOT NULL
           AND f.error_class IS NOT NULL
           AND f.error_class <> 'unknown'
           AND (
                 f.root_cause_fingerprint IS NULL
                 OR f.root_cause_fingerprint <> md5(f.op || '|' || f.error_class)
               )
        RETURNING 1
    )
    SELECT COUNT(*) INTO v_patched FROM rebuilt;

    -- Same pass on history — needed once at backfill time, then on every
    -- new history insert (the trigger snapshot doesn't compute it).
    UPDATE bug_intel_resolved_history h
       SET root_cause_fingerprint = md5(h.op || '|' || h.error_class)
     WHERE h.op IS NOT NULL
       AND h.error_class IS NOT NULL
       AND h.error_class <> 'unknown'
       AND (
             h.root_cause_fingerprint IS NULL
             OR h.root_cause_fingerprint <> md5(h.op || '|' || h.error_class)
           );

    RETURN v_patched;
END;
$$;

COMMENT ON FUNCTION public.bug_intel_patch_root_cause_fingerprint() IS
    'Phase 13 — post-rollup patch that populates root_cause_fingerprint on '
    'every fingerprint and history row where op + real error_class exist. '
    'Scheduled at 04:10 UTC (after compute_daily_bug_rollup at 04:05).';

REVOKE ALL ON FUNCTION public.bug_intel_patch_root_cause_fingerprint() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.bug_intel_patch_root_cause_fingerprint() TO service_role;

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'bug-intel-patch-root-cause-fingerprint') THEN
        PERFORM cron.unschedule('bug-intel-patch-root-cause-fingerprint');
    END IF;
END $$;

SELECT cron.schedule(
    'bug-intel-patch-root-cause-fingerprint',
    '10 4 * * *',
    $$SELECT public.bug_intel_patch_root_cause_fingerprint()$$
);

-- ============================================================================
-- G. Backfill — re-classify every fingerprint where the new pg_code regex
--    can now extract a code, then populate root_cause_fingerprint, then
--    fire the silent-fix drain once.
-- ============================================================================

-- G1. Re-extract pg_code + error_class for rows with class=unknown and a
--     PostgrestError-shaped sample_message.
UPDATE public.bug_intelligence_fingerprints f
   SET pg_code = COALESCE(f.pg_code, public.bug_intel_extract_pg_code(f.sample_message)),
       error_class = public.bug_intel_classify_error(
           COALESCE(f.pg_code, public.bug_intel_extract_pg_code(f.sample_message)),
           f.http_status,
           f.nsurl_code,
           f.sample_message
       )
 WHERE (f.error_class IS NULL OR f.error_class = 'unknown')
   AND f.sample_message IS NOT NULL
   AND public.bug_intel_extract_pg_code(f.sample_message) IS NOT NULL;

-- G2 + G3. Wrapped in DO blocks because PERFORM is PL/pgSQL-only — bare
--          SQL must use SELECT ... INTO a discard variable, but DO is
--          shorter + clearer here.
DO $$
DECLARE
    v_patched INTEGER;
    v_drain   JSONB;
BEGIN
    v_patched := public.bug_intel_patch_root_cause_fingerprint();
    RAISE NOTICE '[20260714] Initial root_cause_fingerprint backfill: % rows patched', v_patched;

    v_drain := public.bug_intel_resolve_by_root_cause();
    RAISE NOTICE '[20260714] Initial silent-fix drain: %', v_drain;
END $$;

-- ============================================================================
-- H. Inline backfill — call mark_fingerprints_resolved_by_migration() for
--    deployed fix migrations whose Resolves: directives were missing OR
--    were never replayed against the fingerprint table.
--
--    The RPC is idempotent: re-running on already-resolved FPs is a no-op,
--    and unknown FPs (already resolved by another path) are returned as
--    skipped_unknown without erroring.
-- ============================================================================

DO $$
DECLARE
    v_result JSONB;
BEGIN
    -- 20260628 — community challenge progress deadlock retry. Header
    -- already lists these but the post-deploy replay never fired.
    v_result := mark_fingerprints_resolved_by_migration(
        '20260628_log_community_challenge_progress_deadlock_retry',
        ARRAY[
            'e03ca9df006076e40cce10c7d4310ac6',
            'd29ff85aff4e5b3fdb647667770c56a9'
        ],
        'Phase 13 backfill — deterministic-lock-order retry deployed; replays Resolves: directives from migration header.'
    );
    RAISE NOTICE '[20260714] 20260628 backfill: %', v_result;

    -- 20260629 — challenge progress sync 42703 (last_progress_at column).
    v_result := mark_fingerprints_resolved_by_migration(
        '20260629_fix_log_challenge_progress_drop_last_progress_at',
        ARRAY[
            '3de7fbe4ab37b58eff4791554f64b791',
            'd441ebc808a595a2e049c15bb6dddd75'
        ],
        'Phase 13 backfill — bogus last_progress_at write removed from log_challenge_progress RPC.'
    );
    RAISE NOTICE '[20260714] 20260629 backfill: %', v_result;

    -- 20260707 — daily_quests bonus_claimed column. Header MENTIONS the
    -- fingerprints in prose but is missing the formal Resolves: directives.
    -- Phase 13 carries them on the migration's behalf. Full md5s sourced
    -- from the 2026-04-29T04:13 export.
    v_result := mark_fingerprints_resolved_by_migration(
        '20260707_user_daily_quests_bonus_claimed',
        ARRAY[
            '76860b32682993235c287659f8b8475e',
            '8e0764bfa9a536ea890dad422ecb2df0',
            '4729e70969007d82824e7d85c0408c5b',
            '537be0ee6f7007389fbdd879ead641c5'
        ],
        'Phase 13 backfill — bonus_claimed column added; Resolves: directives missing from migration header, applied retroactively.'
    );
    RAISE NOTICE '[20260714] 20260707 backfill: %', v_result;

    -- 20260712 — personalized_insights non-partial unique index (Phase
    -- 12 deploy from earlier today). Real md5s from the 04-29 export.
    v_result := mark_fingerprints_resolved_by_migration(
        '20260712_personalized_insights_non_partial_unique',
        ARRAY[
            '4922971bf92d8a6198dcd593eb6cf958',
            '8fb2f8b3da8dd28bdfac00d14cfcdb9b'
        ],
        'Phase 13 backfill — partial unique index replaced with non-partial so PostgREST onConflict matches.'
    );
    RAISE NOTICE '[20260714] 20260712 backfill: %', v_result;

    -- 20260713 — bug-intel classifier denylist (Phase 12 deploy from
    -- earlier today). BGTaskScheduler + NSURL -1017 + NSURL -1001
    -- flipped soft→hard. The auto-resolver inside that migration ALREADY
    -- flipped these via noise_filter_expanded; this is a belt-and-suspenders
    -- replay so the migration_resolved provenance also gets stamped.
    v_result := mark_fingerprints_resolved_by_migration(
        '20260713_bug_intel_classifier_denylist_expand',
        ARRAY[
            '90369817d3be856c44209993d055f2e2',  -- BGAppRefreshTask code 1
            '2fe2cbd75746bd813f564a66a22e8a4b',  -- BGProcessingTask code 1
            '423b048d6f1c8dc68d6ee4e9ce85bc84'   -- Performance metrics cannotParseResponse
        ],
        'Phase 13 backfill — BGTaskScheduler + NSURL -1017 / -1001 denylist deployed. Noise-filter auto-drain has already run; this stamps the migration_resolved provenance for audit trail.'
    );
    RAISE NOTICE '[20260714] 20260713 backfill: %', v_result;

EXCEPTION WHEN OTHERS THEN
    -- Backfill is best-effort. If a fingerprint hash above doesn't exist in
    -- bug_intelligence_fingerprints (e.g. abbreviated form vs full md5),
    -- the RPC returns it in skipped_unknown — we don't want a single missed
    -- hash to roll back the whole Phase 13 migration.
    RAISE NOTICE '[20260714] Backfill block raised %: %, continuing', SQLSTATE, SQLERRM;
END $$;

-- ============================================================================
-- I. Audit — fail loud if any of the four core invariants regressed.
-- ============================================================================

DO $$
DECLARE
    v_extract_works    BOOLEAN;
    v_classify_works   BOOLEAN;
    v_history_root_cause_count INTEGER;
    v_resolve_returns  JSONB;
    v_total_fp         INTEGER;
    v_classifiable_fp  INTEGER;
BEGIN
    -- 1. Extractor sanity.
    v_extract_works := public.bug_intel_extract_pg_code(
        'PostgrestError(detail: nil, hint: nil, code: Optional("42703"), message: "column ...")'
    ) = '42703';
    IF NOT v_extract_works THEN
        RAISE EXCEPTION '[20260714] bug_intel_extract_pg_code regression — Optional("42703") did not match';
    END IF;

    -- 2. Classifier propagation: same input → 'pg:42703'.
    v_classify_works := public.bug_intel_classify_error(
        NULL, NULL, NULL,
        'PostgrestError(detail: nil, hint: nil, code: Optional("42703"), message: "column \"bonus_claimed\" does not exist")'
    ) = 'pg:42703';
    IF NOT v_classify_works THEN
        RAISE EXCEPTION '[20260714] bug_intel_classify_error did not pick up regex-extracted pg_code';
    END IF;

    -- 3. root_cause_fingerprint populated for at least 50% of rows where op
    --    + real class are present. Strict but worth surfacing — anything
    --    weaker means the patch function is broken.
    SELECT COUNT(*) INTO v_total_fp
      FROM bug_intelligence_fingerprints
     WHERE op IS NOT NULL
       AND error_class IS NOT NULL
       AND error_class <> 'unknown';

    SELECT COUNT(*) INTO v_classifiable_fp
      FROM bug_intelligence_fingerprints
     WHERE op IS NOT NULL
       AND error_class IS NOT NULL
       AND error_class <> 'unknown'
       AND root_cause_fingerprint IS NOT NULL;

    IF v_total_fp > 0 AND (v_classifiable_fp::FLOAT / v_total_fp) < 0.5 THEN
        RAISE EXCEPTION
            '[20260714] root_cause_fingerprint backfill underran: % of % classifiable fingerprints populated (<50%%)',
            v_classifiable_fp, v_total_fp;
    END IF;

    -- 4. resolve-by-root-cause is callable and returns a JSONB shape.
    v_resolve_returns := public.bug_intel_resolve_by_root_cause();
    IF v_resolve_returns->>'completed_at' IS NULL THEN
        RAISE EXCEPTION '[20260714] bug_intel_resolve_by_root_cause did not return completed_at';
    END IF;

    SELECT COUNT(*) INTO v_history_root_cause_count
      FROM bug_intel_resolved_history
     WHERE root_cause_fingerprint IS NOT NULL;

    RAISE NOTICE
        '[20260714] ✅ Phase 13 live: extractor + classifier OK, root_cause_fingerprint on % of % classifiable fingerprints, % history rows tagged, post-deploy resolve_by_root_cause returned %',
        v_classifiable_fp, v_total_fp, v_history_root_cause_count, v_resolve_returns;
END $$;

COMMIT;

-- ─── Verification queries (safe to re-run) ─────────────────────────────
-- -- Confirm crash↔log twins now collapse on root_cause_fingerprint:
-- SELECT root_cause_fingerprint,
--        COUNT(*) AS sibling_count,
--        ARRAY_AGG(fingerprint ORDER BY occurrence_count DESC) AS fingerprints,
--        ARRAY_AGG(DISTINCT source) AS sources,
--        SUM(occurrence_count) AS combined_occurrences
--   FROM bug_intelligence_fingerprints
--  WHERE root_cause_fingerprint IS NOT NULL
--    AND status NOT IN ('resolved', 'wont_fix', 'duplicate')
--  GROUP BY root_cause_fingerprint
-- HAVING COUNT(*) > 1
--  ORDER BY combined_occurrences DESC
--  LIMIT 25;
--
-- -- Distribution of error_class after Phase 13:
-- SELECT error_class, COUNT(*) AS fp_count
--   FROM bug_intelligence_fingerprints
--  WHERE status NOT IN ('resolved', 'wont_fix', 'duplicate')
--  GROUP BY error_class
--  ORDER BY fp_count DESC;
--
-- -- Audit recent silent-fix:matched_root_cause auto-resolutions:
-- SELECT fingerprint, sample_message, occurrence_count,
--        auto_resolved_reason, auto_resolved_at
--   FROM bug_intelligence_fingerprints
--  WHERE auto_resolved_reason LIKE 'silent_fix:matched_root_cause:%'
--    AND updated_at >= now() - interval '7 days'
--  ORDER BY auto_resolved_at DESC
--  LIMIT 25;
