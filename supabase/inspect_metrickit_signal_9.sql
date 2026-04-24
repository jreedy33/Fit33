-- Phase 11E — 2026-04-24 MetricKit signal-9 investigation.
--
-- The 2026-04-24T11:10 Cursor bug-intel export surfaced fingerprint
-- `e955904cbca5bf71f87d18a2e89221dd` with sample_message:
--   "[METRICKIT] Crash diagnostic v1.39 (current: v1.39), signal: 9 exc: 10/0"
-- 1 occurrence, 1 user, first + last seen 2026-04-23 15:46 UTC on
-- build 1.39 (current TestFlight candidate).
--
-- Signal 9 = SIGKILL, which on iOS means the OS watchdog killed the
-- app — almost always because main-thread startup took too long
-- (>20 seconds on cold-launch). The exception code 10/0 narrows it
-- further: 10 = EXC_CRASH, 0 = generic.
--
-- This file contains four read-only queries to pull the full crash
-- context from `metrickit_payloads` + the surrounding dev_session_logs
-- so we can triage the frame stack and identify which startup
-- operation blocked main thread.
--
-- Run the queries in order. If query 1 returns 0 rows, the payload
-- has been GC'd (90-day retention) — investigate via MetricKit
-- diagnostic samples in Xcode or via the symbolicated dSYM runner.

-- ============================================================================
-- 1. Full MetricKit payload for the offending fingerprint.
-- ============================================================================

SELECT
    p.id,
    p.user_id,
    p.app_version,
    p.build_number,
    p.os_version,
    p.device_model,
    p.created_at,
    p.payload_type,
    -- The `payload` JSONB is the MXDiagnosticPayload serialised. The
    -- `callStackTree` key holds the frame stack we need to symbolicate.
    jsonb_pretty(p.payload -> 'callStackTree')        AS call_stack_tree,
    jsonb_pretty(p.payload -> 'metaData')             AS metadata,
    -- Signal + exception code.
    p.payload #>> '{signal}'                          AS signal,
    p.payload #>> '{exceptionType}'                   AS exception_type,
    p.payload #>> '{exceptionCode}'                   AS exception_code,
    -- Termination reason if iOS provided one (e.g. "Watchdog terminated").
    p.payload #>> '{terminationReason}'               AS termination_reason
  FROM metrickit_payloads p
 WHERE p.payload_type IN ('crash', 'crashDiagnostic')
   AND (p.payload #>> '{signal}')::int = 9
   AND p.created_at >= '2026-04-23'::date
   AND p.created_at <  '2026-04-24'::date
 ORDER BY p.created_at DESC
 LIMIT 5;

-- ============================================================================
-- 2. Session context — dev_session_logs around the crash time.
--    The crash struck at 2026-04-23 15:46:29 UTC, so we want the
--    ~60 seconds of activity leading up to the kill. If startup
--    operations are logging progress we'll see "last heartbeat"
--    within those 60s and can identify the stuck phase.
-- ============================================================================

SELECT
    ds.id,
    ds.user_id,
    ds.created_at,
    ds.app_version,
    ds.build_number,
    -- Only pull the last 20 entries to stay readable.
    jsonb_path_query_array(
        ds.entries,
        '$[last 20 to last].{ts: $.ts, type: $.type, category: $.category, message: $.message}'
    ) AS last_20_entries
  FROM dev_session_logs ds
 WHERE ds.user_id IN (
        SELECT DISTINCT p.user_id
          FROM metrickit_payloads p
         WHERE p.payload_type IN ('crash', 'crashDiagnostic')
           AND (p.payload #>> '{signal}')::int = 9
           AND p.created_at >= '2026-04-23'::date
     )
   AND ds.created_at BETWEEN '2026-04-23 15:45:00+00'::timestamptz
                         AND '2026-04-23 15:47:00+00'::timestamptz
 ORDER BY ds.created_at DESC;

-- ============================================================================
-- 3. All signal-9 crashes on 1.39 (widen the window in case there
--    were more since the export was generated). If this returns
--    multiple users, we have a launch regression in 1.39 that
--    needs a build-specific fix.
-- ============================================================================

SELECT
    p.app_version,
    p.build_number,
    COUNT(*)        AS sig9_count,
    COUNT(DISTINCT p.user_id) AS affected_users,
    MIN(p.created_at) AS first_seen,
    MAX(p.created_at) AS last_seen
  FROM metrickit_payloads p
 WHERE p.payload_type IN ('crash', 'crashDiagnostic')
   AND (p.payload #>> '{signal}')::int = 9
   AND p.created_at >= now() - interval '14 days'
 GROUP BY p.app_version, p.build_number
 ORDER BY sig9_count DESC;

-- ============================================================================
-- 4. If query 3 shows signal-9 only on 1.39 and nowhere else,
--    grab the top symbolicated frames across all affected users
--    to identify the common stuck call. Requires the
--    symbolicate-crashes GH Action to have populated the
--    `symbolicated_frames` column; if it hasn't, the raw
--    callStackTree JSONB from query 1 still contains the addresses.
-- ============================================================================

WITH sig9 AS (
    SELECT p.id, p.payload
      FROM metrickit_payloads p
     WHERE p.payload_type IN ('crash', 'crashDiagnostic')
       AND (p.payload #>> '{signal}')::int = 9
       AND p.app_version = '1.39'
       AND p.created_at >= now() - interval '14 days'
),
frames AS (
    SELECT
        s.id,
        frame->>'symbolName'  AS symbol,
        frame->>'binaryName'  AS binary,
        frame->>'subFrames'   AS sub_frames
      FROM sig9 s,
           jsonb_array_elements(
               COALESCE(s.payload #> '{callStackTree, callStacks, 0, callStackRootFrames}', '[]'::jsonb)
           ) frame
)
SELECT symbol, binary, COUNT(*) AS frame_hits
  FROM frames
 WHERE symbol IS NOT NULL
 GROUP BY symbol, binary
 ORDER BY frame_hits DESC
 LIMIT 25;
