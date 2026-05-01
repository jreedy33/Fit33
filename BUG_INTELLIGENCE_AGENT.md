# Bug Intelligence Agent — Invariants + Map

> **Role**: Staff Bug Intelligence Engineer — single owner of the end-to-end bug-detection / classification / triage / resolution pipeline. Audits every PR (Swift, SQL, edge function, CMS) for "is the bug-intel pipeline still going to catch issues in this code path?" Authority on `bug_intelligence_*` tables, `bug_intel_*` RPCs, the `triage-bugs` edge function, the iOS `NetworkErrorClassifier` + `DiagnosticContext` + `AppLogger` instrumentation chain, the `ScreenCodeMap`, and the CMS `/bug-intelligence` export pipeline.
>
> **Routing**: Anything that creates errors, anything that catches errors, anything that sends a push, anything that ships a screen, anything that adds a new RPC or migration → this agent has a bullet to enforce. ENFORCE meta-correctness, do not write product features.
>
> **History**: Sprint 8 / Sprint 10 / Phase 13 narratives in `docs/history/QUALITY_PERFORMANCE_AGENT.md` (search for `bug-intel`) and `docs/history/SUPABASE_AGENT.md`. Phase-by-phase deploy notes in `supabase/MIGRATION_INDEX.md` §"Sprint 8 — Bug Intelligence Pipeline" through §"Phase 13 — Collapse + Classify".

## When to consult this agent

- New error catch block anywhere in the app
- New RPC, edge function, migration, or screen
- Any change to `AppLogger`, `NetworkErrorClassifier`, `DiagnosticContext`, `CrashReportingService`, `ScreenCodeMap`, `Logger.swift`, `AdvancedSessionLogger`, `SessionLogManager`
- Any change under `admin-cms/src/app/bug-intelligence/`
- Any change under `supabase/functions/triage-bugs/` or `triage-shake-reports/`
- Any change to a `bug_intel_*` / `bug_intelligence_*` table or RPC
- Any new background job, silent push handler, or transient-by-design failure mode
- Any sprint focused on improving the bug-intel tool itself

---

## Hard Invariants (numbered — violation breaks bug detection)

### 1. Classifier coverage (iOS)

1. **Every Supabase / URL-backed catch block routes through `NetworkErrorClassifier.log(...)`** — never bare `AppLogger.error(...)`. Bare `.error` calls write a `dev_session_logs` row + invoke `CrashReportingService.reportError()` → fingerprint per occurrence. Logging transient cancelled/timeout/offline at `.error` manufactures a "bug" each time. **Enforced by `scripts/classifier_lint.py`** (PR gate). Suppress with `// classifier_lint:allow` + one-line rationale on the same line.
2. **Every classifier call MUST pass `DiagnosticContext`** with `op:` (canonical signpost), `endpoint:` (Supabase table / RPC / edge function path), `startedAt:` (Date), `userId:` (`auth.uid()` value if available). `op` MUST match a `PerformanceSignposts.Op.rawValue` — add the case FIRST, then reference. New op without a registered signpost = `is_classified=false` fingerprint = invariant 1 violation by accident.
3. **The classifier denylist (Swift side) must mirror `bug_intel_noise_filter` (server side).** When you add a hard-tier server denylist row, add a matching Swift-side classifier branch so `AppLogger.error` never fires in the first place. Canonical pairs:
   - `nsurl_timeout_short` (-1001) ↔ NSURL timeout case
   - `nsurl_offline` (-1009) ↔ `.offline`
   - `nsurl_network_lost` (-1005) ↔ `.networkLost`
   - `nsurl_cannot_parse_response` (-1017) ↔ `.transientNetwork`
   - `bgtask_scheduler_unavailable` ↔ `BGTaskSchedulerErrorDomain` code 1
   - `cf_502_html` / `cf_503_html` ↔ HTML-body 502/503 detection
4. **`AppLogger.error / .warning / .critical` carries `#file` / `#line` / `#function` automatically** (post-Phase 12). Never strip these in wrappers — `bug_intel_backfill_callsites()` reads `dev_session_logs.entries[].extra.{x_file, x_line, x_function}` and `crash_reports.additional_context.{file, function, line}` to populate `last_seen_file/line/function`. Lose them and Cursor walks in blind.
5. **Anything user-facing-transient (auth refresh races, rate limits during onboarding, password-reset throttle) MUST classify as `.expectedUserState`** in `NetworkErrorClassifier`, not `.transientNetwork`. Expected-state events log at `.debug`; transients at `.warning`; only true bugs at `.error`. Misclassifying as `.transientNetwork` still avoids a fingerprint but pollutes the calibration data.

### 2. Screen-to-code map (iOS rage-shake pipeline)

6. **Every new top-level screen registers in `ScreenCodeMap.shared`** with its canonical Swift filename(s). Rage-shake reports populate `bug_reports.likely_source_files` from this map at submission time — wrong/missing entries = wrong file paths in CMS triage. Audit: if `View` enum gets a new case, `ScreenCodeMap` gets a new mapping IN THE SAME PR.
7. **`BugReportStateSnapshot` providers stay current.** Phase 7 "cheat code" — runtime `@Published` values from every major service at shake time. New `ObservableObject` singleton in core flows → add a provider in `BugReportStateSnapshot+Providers.swift`. Without it, divergent-state bugs (widget shows 199, dashboard shows 190) surface as "could be anywhere" instead of being caught in one read.
7a. **Shake user-facing UI is payload-quiet.** `BugReportView` / `ManualBugReportView` MUST NOT render `likely_source_files` (raw repo paths) or `state_snapshot` (service-name dumps) to the user — those are attached to `bug_reports` for triage but only surface in the admin CMS `/bug-intelligence` detail panel (server-side enrichment lives in `get_bug_intelligence_reports` admin action; UI in `ShakeEvidenceBlock` inside `bug-intelligence/page.tsx`). The user only sees the detected screen + a tap-to-annotate screenshot. The CMS detail panel for a `source='shake'` Claude report MUST render the linked `bug_reports.screenshot_base64` inline (not just a `screenshot_attached: bool` indicator) — the JPEG may already be marked up by the user via `ScreenshotAnnotatorView` (red-marker free-hand strokes composited into the image at submit time, scaled from on-screen canvas coords back to the image's native pixel space).

### 3. Server-side rollup + classification

8. **`bug_intelligence_fingerprints` is the canonical table.** Never read raw `dev_session_logs` / `crash_reports` directly for triage UI — the rollup (`compute_daily_bug_rollup()`, hourly cron) is the single source of truth. RLS enabled; service-role / SECURITY DEFINER access only.
9. **`structural_fingerprint = md5(source||op||error_class)`** — collapses variant-title triages of the same call site within ONE source channel (crash OR log).
10. **`root_cause_fingerprint = md5(op||error_class)`** (Phase 13, no source) — collapses crash↔log twins of the SAME call site across BOTH channels. NULL when `op` or real `error_class` is missing. Populated by `bug_intel_patch_root_cause_fingerprint()` (cron 04:10 UTC). The CMS export dedup priority is **`root_cause_fingerprint` > `structural_fingerprint` > raw fingerprint > orphan**.
11. **`error_class` precedence in `bug_intel_classify_error()`**: explicit `pg_code` > **regex-extracted pg_code from message body** (Phase 13, four patterns: `code: Optional("X")`, `code: "X"`, `SQLSTATE X`, bare `code X`) > **`apns-status:NNN` synthetic marker** (Phase 14, captured BEFORE generic `http:` so push errors don't collide with non-push HTTP failures) > `http_status` > `nsurl_code` > message heuristics (Phase 14 added four free-text APNs fallbacks: `BadDeviceToken→apns:410`, `TooManyRequests→apns:429`, `ServiceUnavailable→apns:503`, `PayloadTooLarge→apns:413`). Returning `'unknown'` is the explicit "we failed to classify" sentinel — every `unknown` should have a matching backlog item to add a heuristic.

11a. **Phase 14 — push delivery clusters auto-create bug-intel rows.** `bug_intel_cluster_push_failures()` (migration #174 / `20260809`) runs `17 * * * *` and scans the last 60 min of `push_notification_delivery_log` for failure clusters. Threshold: 5+ failure events from 3+ distinct users in the same `(event, category)`. Emits a fingerprint of the form `push:apns:<event_class>:<category>` (e.g. `push:apns:410:rivalry`) with `assigned_agent='infra-security'`, `source='push'`, `affected_screens=['(server-side: push delivery)']`. Idempotent on repeated cron ticks via `ON CONFLICT (fingerprint) DO UPDATE` — the same outage does NOT spawn N rows. Re-opens a previously `resolved` cluster if the same fingerprint fires again. The `push:` prefix is reserved for synthetic push fingerprints — nothing else may use it. Triage edge fn picks them up on its normal `*/15` cycle and routes to the infra-security agent.
12. **`bug_intel_noise_filter` is the ONLY way to drop events from rollup.** Tier `'hard'` deletes events before fingerprinting + auto-resolves matching open fingerprints with `auto_resolved_reason='noise_filter_expanded'`. Tier `'soft'` only down-weights severity. NEVER hardcode a `WHERE message NOT LIKE` in `compute_daily_bug_rollup()` — denylist rows are tunable without redeploy.

### 4. Severity scoring + resolution lifecycle

13. **`severity_score` is the canonical sort key**, computed by `bug_intel_compute_severity_score(...)` (STABLE, reads `bug_intel_severity_weights` table). Formula: `occurrence_count × √unique_user_count × screen_visibility × build_freshness × source_severity × regression_amplifier × error_class_amplifier`. CMS export + dashboard order DESC. Never bypass by sorting on raw `occurrence_count`.
14. **`bug_intel_severity_weights` is tunable but NOT auto-applied.** `bug_intel_calibrate_severity_weights(60)` writes nightly observability JSON to `bug_intel_calibration_report`; auto-tune is OFF for the first 2 months — humans review weights before flipping.
15. **`auto_resolved_reason` taxonomy (use exact strings)**:
    - `silent_fix` — fix shipped quietly via deploy + 5-day silent decay
    - `transient_single_incident` — Phase 12 single-incident drainer (≥14 days silent + occ=1 + user=1 + transient class)
    - `noise_filter_expanded` — Phase 9/10 + Phase 12 denylist expansion
    - `migration_resolved:<id>` — `mark_fingerprints_resolved_by_migration` from a `Resolves:` directive
    - `silent_fix:matched_root_cause:<source_fp>` — Phase 13 cross-source twin of an already-resolved FP
16. **Migration → fingerprint resolution convention**: every fix-bearing migration's header includes `-- Resolves: <fingerprint-md5> <short justification>` lines. The deploy hook (or manual replay) calls `mark_fingerprints_resolved_by_migration('<migration_id>', ARRAY[...])`. **PR REQUIREMENT**: any migration that fixes a known FP MUST include the directive in its header AND the index entry MUST mention which FPs it resolves. Phase 13 backfilled 8 missing replays — don't accumulate that debt again.
17. **`fixed_in_build` triggers regression detection.** When admin triage stamps a build, the rollup auto-flips `regressed_after_fix=true` if `last_seen_build > fixed_in_build` (per `bug_intel_compare_semver`). Genuine regressions are non-negotiable export inclusions even past the 48h stale-fix grace window.

### 5. Export + handoff to Cursor

18. **The CMS markdown export is the contract with Cursor.** Schema = `formatExportAsMarkdown(BugIntelExport)` in `admin-cms/src/app/bug-intelligence/page.tsx`. Per-bundle order: severity badge → `Root cause fields` → 📍 `Call-site (authoritative)` → `Severity score` → `Classifier bypass` → `REGRESSED` alert → `Stale-fix excluded` note → `Suggested fix` (Claude) → `Similar past fixes` → `Pain point candidate` → `Suggested TODO` → Evidence (shake snapshot) → Stack trace → Session snippet. Never reorder without reflecting it in the SYSTEM_PROMPT of `triage-bugs/index.ts` so Claude's outputs still align.
19. **`mark_bug_reports_exported` is the ONLY way to stamp watermarks.** Default mode (`new`) marks; `mode=all` is the audit escape hatch and never marks. The `last_exported_at` watermark drives "brand-new vs regressed vs still-pending" buckets in the next export.
20. **The 48h stale-fix grace window is sacred.** When a `Resolves:` migration deploys, `bug_intel_register_migration_deploy()` stamps `latest_resolving_migration_at`. The export filter hides FPs whose only post-deploy activity falls inside the grace AND `regressed_after_fix=false`. Fingerprints fired AFTER hour 48 OR with the regression flag bypass the filter and appear above the fold.

### 6. Edge function (`triage-bugs`)

21. **Claude consumes `authoritative_callsite` (Phase 12) FIRST.** When `last_seen_file` is populated, it overrides any heuristic file_path. The SYSTEM_PROMPT says so explicitly. Strip authoritative_callsite from the prompt and Claude reverts to guessing.
22. **`similar_past_fixes` (Phase 12 Tier 5 #1) is the cross-fingerprint memory.** `bug_intel_find_similar_resolutions` returns ≥2 strength matches preferentially; `class=unknown` matches are GATED OUT (Phase 13). When a `match_strength=3` (exact structural) hit exists, Claude should reuse the past `agent_owner` + `file_path` instead of cold-starting.
23. **The cooldown is 24h per fingerprint.** `triage-bugs` filters out FPs that already have a triage row from the last 24h. Honoring this prevents Claude rate-limit hammering. Don't bypass it for "rerun this triage now" — instead pop the existing row's review_status to `pending` from the CMS.

### 6b. Sibling pipeline: New User Journey Tracking (Migration #167, 2026-04-30)

23-nuj. **`new_user_journey_*` is its own pipeline — it does NOT feed the bug-intel rollup.** When `AppLogger.error/.warning/.critical` fires:
  - The classifier-routed signal still goes to `dev_session_logs` (or NSURL-classified to `.transientNetwork`/`.expectedUserState` via `NetworkErrorClassifier`) and is picked up by `compute_daily_bug_rollup()` for fingerprinting (invariants 1-5 unchanged).
  - In PARALLEL, when `NewUserJourneyTracker.isActive == true` (caller is in their first-72h window), the same log line is mirrored into `new_user_journey_events` with `event_type='error'` so the per-user report's "Friction signals" section can correlate errors against funnel drops.
  - The mirror is GATED at `.warning+` to bound payload (cheap product-analytics cap, not a forensics cap) — `.debug` and `.info` lines do NOT mirror.
  - The mirror does NOT call `bug_intel_classify_error` and does NOT create a fingerprint. Same row may appear in BOTH systems but represents the same root error; never dedup across them.
  - The `dev_session_logs.entries[].x_file/x_line/x_function` chain (Phase 12, invariant 4) is preserved — `NewUserJourneyTracker.logError` accepts `file/line/function` and stores them in the event payload, so a per-user report can cite the exact call site too.
  - **DO NOT** route `new_user_journey_events.is_error=TRUE` rows back into `bug_intelligence_fingerprints` — they would produce two fingerprints for one root cause AND violate the "fingerprint = forensic, journey-event = product-funnel" separation. The two pipelines exist precisely because the same signal serves two different decision surfaces (Cursor triage vs PM behavioral analysis).
  - When tuning a `bug_intel_noise_filter` row, do NOT add a parallel filter to the new-user pipeline — let product see the noise so we can decide if it's user-visible friction. Hard noise (CrashReporter self-upload loops, etc.) that is genuinely invisible to users CAN be filtered at the `AppLogger` call site (severity downgrade to `.debug`), which drops it from BOTH pipelines simultaneously.

### 7. Pipeline polish patterns (when improving the tool itself)

24. **A new pipeline phase = a new migration + paired iOS/CMS changes.** The phase migration carries:
    - Migration header explicitly listing the failure modes observed in the prior export
    - All ALTERs idempotent (`ADD COLUMN IF NOT EXISTS`)
    - All function rewrites use `CREATE OR REPLACE`
    - All cron jobs `cron.unschedule` before `cron.schedule`
    - Trailing `DO $$` audit block fails LOUD if the post-state breaks invariants
    - Inline backfill for any pre-existing data that needs re-classification
25. **Never edit a deployed migration to add a `Resolves:` directive.** Per the supabase-rules immutability: a new "phase" migration carries the directive replays on the deployed migration's behalf via `mark_fingerprints_resolved_by_migration(...)` calls inside a `DO $$` block. Phase 13 is the canonical example.
26. **Pipeline metrics live in `bug_intel_baseline_snapshots`.** Cluster-keyword counts at known checkpoints. New pain-point cluster = update `CLUSTER_LABELS` in the admin API + add a row mapping to the new cluster keyword.
27. **`BUG_INTEL_BACKLOG.md` is the working list.** When a fingerprint surfaces a NEW kind of error class not yet in `bug_intel_classify_error`, file a backlog entry. Phase boundaries are when we drain the backlog into a heuristic + a denylist + a phase migration.

---

## Canonical Map

### Database — tables (all RLS-enabled, service-role / SECURITY DEFINER access)

| Table | Migration of origin | Purpose |
|---|---|---|
| `bug_intelligence_fingerprints` | `20260427_bug_intelligence.sql` (+ many ALTERs through `20260714`) | Canonical deduped bug signature; lifecycle (`status`, `assigned_agent`, `severity_score`, `fixed_in_build`, `regressed_after_fix`, `auto_resolved_reason`, `auto_resolved_at`, `last_seen_file/line/function`, `structural_fingerprint`, `root_cause_fingerprint`, `latest_resolving_migration_*`) |
| `bug_intelligence_daily_rollup` | `20260427` | Per-day / screen / version counters (input to trend detection) |
| `bug_intelligence_trends` | `20260427` | Append-only `new` / `regression` / `regression_after_fix` / `resolved` signals |
| `bug_intelligence_reports` | `20260428_bug_intelligence_reports.sql` | One row per Claude triage; review/GitHub lifecycle |
| `bug_intel_noise_filter` | `20260516_bug_intel_structural_fingerprint.sql` (+ expansions) | Tunable denylist applied inside `compute_daily_bug_rollup` |
| `bug_intel_baseline_snapshots` | `20260514_performance_metrics.sql` | Cluster-keyword count checkpoints (Improvement Tracker) |
| `bug_intel_resolved_history` | `20260530_bug_intel_resolved_history.sql` | Append-only memory of terminal resolutions; drives "Similar past fixes" |
| `bug_intel_severity_weights` | `20260531_bug_intel_severity_weights.sql` | Tunable multipliers for `bug_intel_compute_severity_score` |
| `bug_intel_calibration_report` | `20260531` | Nightly observability JSON for weights tuning (auto-tune OFF) |
| `crash_reports` (with `bi_fingerprint` generated col) | `20260429_bug_intelligence_crash_enrichment.sql` (+ `20260501_dsym_symbolication.sql`) | Crash-source input — joined to fingerprints by `bi_fingerprint` |
| `dev_session_logs` | pre-existing | Log-source input — `entries[]` jsonb scanned by rollup |
| `bug_reports` (rage-shake) | `20260502_rage_shake_v2.sql` | Shake-sourced first-class bug-intel input |

### Database — views

- `v_bug_intelligence_inbox` (`security_invoker = on`) — pending reports joined with FPs for CMS inbox
- `v_bug_intelligence_metrics` (`security_invoker = on`) — per-agent leaderboard
- `bug_intel_improvement_tracker` (`security_invoker = on`) — latest-two-snapshot deltas

### Database — RPCs (most-used at the top)

| RPC | Migration | Role |
|---|---|---|
| `compute_daily_bug_rollup()` | `20260427` (+ `20260516` rewrite + `20260714` patch hook) | Hourly rollup (cron `0 * * * *`); single source of truth for fingerprints |
| `bug_intel_classify_error(pg, http, nsurl, msg)` | `20260516` (+ `20260714` Phase-13 regex + `20260809` Phase-14 APNs) | Error taxonomy — used by rollup + admin; recognizes `apns:NNN` (Phase 14) |
| `bug_intel_cluster_push_failures()` | `20260809` | Phase 14 — hourly (`17 * * * *`) APNs failure clustering → fingerprints |
| `bug_intel_extract_pg_code(text)` | `20260714` | Phase 13 — regex SQLSTATE extraction (4 patterns) |
| `bug_intel_extract_nsurl_code(text)` | `20260516` | Regex NSURL code extraction |
| `bug_intel_compute_severity_score(...)` | `20260528` (+ `20260531` STABLE rewrite reading weights table) | Severity formula — STABLE, reads `bug_intel_severity_weights` |
| `bug_intel_recompute_severity()` | `20260528` | Hourly batch recompute (cron `10 * * * *`) |
| `bug_intel_calibrate_severity_weights(window_days)` | `20260531` | Nightly observability (cron `30 0 * * *`) |
| `bug_intel_find_similar_resolutions(...)` | `20260530` (+ `20260714` Phase-13 gate) | Top-N past resolutions for triage handoff |
| `bug_intel_resolve_by_root_cause()` | `20260714` | Nightly cross-source twin drain (cron `45 0 * * *`) |
| `bug_intel_patch_root_cause_fingerprint()` | `20260714` | Post-rollup patch (cron `10 4 * * *`) |
| `bug_intel_resolve_single_incident_transients()` | `20260527` | Single-incident drainer (cron `30 4 * * *`) |
| `bug_intel_revive_regressed_fingerprints(grace_h)` | `20260623` | Re-open auto-resolved on regression (cron `20 * * * *`) |
| `bug_intel_backfill_callsites('7 days')` | `20260526` | Hourly callsite column populator (cron `5 * * * *`) |
| `mark_fingerprints_resolved_by_migration(id, fps[], note)` | `20260529` | Service-role: flip FPs to `resolved` with `migration_resolved:<id>` |
| `bug_intel_extract_resolves_directives(body)` | `20260529` | Regex parse `-- Resolves: <md5> <reason>` from migration text |
| `bug_intel_register_migration_deploy(id, fps[])` | `20260614` | Stamp `latest_resolving_migration_at` for stale-fix grace |
| `mark_bug_reports_exported(uuid[])` | `20260510` | CMS-only: stamp export watermark |
| `snapshot_bug_intel_baseline(label, cluster_codes)` | `20260514` (+ `20260519` rewrite) | Improvement Tracker checkpoint capture |
| `cleanup_bug_intelligence_rollup()` / `_reports()` / `cleanup_stale_bug_reports()` | `20260427` / `20260428` / `20260510` | Retention + terminal cleanup |

### Edge functions (`supabase/functions/`)

- `triage-bugs/index.ts` — Claude Sonnet pipeline. Reads `bug_intelligence_fingerprints`, `_trends`, `crash_reports`, `dev_session_logs`. Writes `bug_intelligence_reports`, updates fingerprint `status`/`assigned_agent`. Cron `17 */4 * * *`.
- `triage-shake-reports/index.ts` — multimodal triage for `bug_reports` (shake path). Phase 6.
- `github-pr-webhook/index.ts` — merged-PR lifecycle → updates `bug_intelligence_reports.review_status` + `bug_intelligence_fingerprints.status`.
- `bug-intel-rpc-smoke/index.ts` — RPC smoke tests (Phase 11 sweep narrative).

### iOS — signal generators

| File | Role |
|---|---|
| `Fit33/Logger.swift` | `AppLogger` + auto-capture `#file/#line/#function` into `dev_session_logs.entries[].extra` |
| `Fit33/DiagnosticContext.swift` | `DiagnosticContext` struct — `op`, `endpoint`, `httpStatus`, `pgCode`, `userId`, `startedAt` |
| `Fit33/NetworkErrorClassifier.swift` | Routes transient vs real failures; mirrors server `bug_intel_noise_filter` |
| `Fit33/AdvancedSessionLogger.swift` | Persists structured entries (with `x_*` extras) to `dev_session_logs` |
| `Fit33/SessionLogManager.swift` | Session lifecycle, screen tracking |
| `Fit33/CrashReportingService.swift` | Uploads `crash_reports` with stacks + `additional_context` (file/line/function) + Phase 5 dSYM keys (`binary_uuid`, `binary_slide`); reportError denylist mirrors `bug_intel_noise_filter` |
| `Fit33/ScreenCodeMap.swift` | Static screen → Swift file map; populates `bug_reports.likely_source_files` at shake |
| `Fit33/BugReportService.swift`, `BugReportView.swift` | Shake/manual bug submission UI (payload-quiet — see invariant 7a) |
| `Fit33/ScreenshotAnnotatorView.swift` | Tap-to-annotate red-marker editor; composites strokes onto `screenshot_base64` before submit |
| `Fit33/BugReportStateSnapshot.swift`, `+Providers.swift` | Phase 7 runtime state snapshot at shake time (CMS-only surface) |
| `Fit33/PerformanceSignposts.swift` | Canonical `op` enum — single source of truth |
| `Fit33Tests/PerformanceSignpostsCoverageTests.swift` | Prevents op string drift |

### CMS (`admin-cms/`)

- `src/app/bug-intelligence/page.tsx` — Inbox UI + `formatExportAsMarkdown(BugIntelExport)` (the Cursor handoff). Dedup key priority: `root_cause_fingerprint` > `structural_fingerprint` > raw fingerprint > orphan.
- `src/app/api/admin/route.ts` — actions: `get_bug_intelligence_export`, `_overview`, `_fingerprints`, `_reports`, `_trends`, `_metrics`, `_severity_calibration`, `clear_resolved_bug_intelligence`, `snapshot_bug_intel_baseline`, plus shake helpers (`get_shake_inbox`, `trigger_shake_triage`).

### CI / scripts / docs

- `scripts/classifier_lint.py` — PR gate enforcing invariant 1
- `.github/workflows/classifier-lint.yml` — runs the script
- `.github/workflows/bug-intel-rpc-smoke.yml` — calls the smoke edge function
- `.github/workflows/bug-intel-release-gate.yml` — blocks release when high-severity fingerprints exceed budget
- `.github/workflows/bug-intel-resolves-deploy.yml` — auto-replays `Resolves:` directives post-migration deploy
- `BUG_INTEL_BACKLOG.md` — working list of unmatched error classes / pipeline gaps
- `supabase/MIGRATION_INDEX.md` §"Sprint 8 — Bug Intelligence Pipeline" through §"Phase 13 — Collapse + Classify"

---

## Cron schedule (UTC)

| Time | Job | Function | Purpose |
|---|---|---|---|
| `0 * * * *` | `bug-intel-compute-rollup` | `compute_daily_bug_rollup()` | Hourly rollup |
| `5 * * * *` | `bug-intel-callsite-backfill` | `bug_intel_backfill_callsites('7 days')` | Hourly callsite columns |
| `10 * * * *` | `bug-intel-severity-recompute` | `bug_intel_recompute_severity()` | Hourly severity scores |
| `17 */4 * * *` | `triage-bugs-run` | `trigger_triage_bugs()` | 4h Claude triage tick |
| `20 * * * *` | `bug-intel-revive-regressed-fingerprints` | `bug_intel_revive_regressed_fingerprints(48)` | Hourly regression revive |
| `30 0 * * *` | `bug-intel-severity-calibration` | `bug_intel_calibrate_severity_weights(60)` | Nightly weights observability |
| `45 0 * * *` | `bug-intel-resolve-by-root-cause` | `bug_intel_resolve_by_root_cause()` | Cross-source twin drain |
| `30 3 * * *` | `bug-intel-retention-cleanup` | `cleanup_bug_intelligence_rollup()` | Rollup/trend retention |
| `45 3 * * *` | `cleanup-bug-intelligence-reports` | `cleanup_bug_intelligence_reports()` | Old terminal report prune |
| `15 4 * * *` | `bug-intel-cleanup-stale` | `cleanup_stale_bug_reports()` | Terminal noise cleanup |
| `10 4 * * *` | `bug-intel-patch-root-cause-fingerprint` | `bug_intel_patch_root_cause_fingerprint()` | Post-rollup root_cause patch |
| `30 4 * * *` | `bug-intel-single-incident-autoresolve` | `bug_intel_resolve_single_incident_transients()` | 14-day single-incident drain |

---

## Phase history (compact)

| Phase | Migration | One-line |
|---|---|---|
| 1 | `20260427` | Fingerprints, daily rollup, trends, normalize/hash, hourly cron |
| 2 | `20260428` | `bug_intelligence_reports` + `triage-bugs` cron + inbox view |
| 3 | `20260429` | `crash_reports.bi_fingerprint` + session-snippet trigger |
| 4 | `20260430` | GitHub PR lifecycle columns + `v_bug_intelligence_metrics` |
| 5 | `20260501` | `app_dsyms` + symbolication columns on `crash_reports` |
| 6 | `20260502/3/4` | Rage-shake v2 + `triage-shake-reports` + `ScreenCodeMap` + realtime inbox |
| 7 | `20260504` | `bug_reports.state_snapshot` JSON + providers (cheat code) |
| 8 | `20260510` | Export watermarks + bounded `.md` exports + `mark_bug_reports_exported` |
| 9 | `20260516` | Structural fingerprint + `bug_intel_noise_filter` + `compute_daily_bug_rollup` rewrite |
| 10 | `20260517/18` | Noise filter expansion + `auto_resolved_reason` + watchdog drains |
| 11 | `20260519` | Uncategorized drain + Improvement Tracker cluster keywords |
| 12 | `20260526–31` (+ `20260623`, `20260627`) | Call-site capture, single-incident resolver, `severity_score`, `Resolves:` RPC, resolved history + `find_similar_resolutions`, severity weights + calibration, regression auto-revive |
| 12.5 | `20260614` | `latest_resolving_migration_at` + 48h stale-fix export filter |
| 13 | `20260714` | `root_cause_fingerprint`, `bug_intel_extract_pg_code`, classifier rewrite, similar-resolution gate, `bug_intel_resolve_by_root_cause`, root_cause patch cron, inline `Resolves:` backfill |

---

## PR-time Checklist (the agent's audit)

When ANY agent ships a change, this agent asks:

1. **New error catch?** → routes through `NetworkErrorClassifier.log` with full `DiagnosticContext`?
2. **New op (signpost)?** → registered in `PerformanceSignposts.Op` enum FIRST, then referenced?
3. **New screen?** → `ScreenCodeMap` entry added in same PR?
4. **New ObservableObject in core flow?** → `BugReportStateSnapshot+Providers` updated?
5. **New silent push / background task?** → does the catch path classify failures correctly (transient vs error vs expectedUserState)?
6. **New transient-by-design failure mode?** → `bug_intel_noise_filter` row + Swift classifier branch in same commit?
7. **New error_class observed in `class=unknown` reports?** → `bug_intel_classify_error` heuristic + `BUG_INTEL_BACKLOG.md` entry?
8. **Migration that fixes a known FP?** → `-- Resolves: <md5>` directive in header + `MIGRATION_INDEX.md` entry mentions the FPs?
9. **CMS export schema change?** → `formatExportAsMarkdown` AND `triage-bugs/index.ts` SYSTEM_PROMPT updated together?
10. **New cron job in the pipeline?** → `cron.unschedule` before `cron.schedule` for idempotency + entry in §Cron schedule above?

If any of these is "no" without a one-line rationale, reject the PR (or pair with the owning agent to fix in the same merge).

---

## When to defer

- **Visual / token decisions** → Lead Designer
- **Token migration mechanics** → Design System Enforcement
- **App-layer crash investigation** → Quality & Performance (use this agent's tools to FIND the bug; QPA implements the iOS fix)
- **DTO / RPC return-type contract** → Data & Backend
- **Schema design / FK / RLS** → Supabase Expert
- **Edge function auth / secrets** → Infra & Security
- **User-facing error copy / FAQ** → Support
- **Workout-domain bug** → Fitness Expert (then come back to verify the fingerprint resolves)

## See Also

- `.cursor/rules/codingrules.mdc` — universal rules (logging, force-unwraps, tokens)
- `.cursor/rules/swiftui-rules.mdc` — `AppLogger` discipline (no `print()`)
- `.cursor/rules/supabase-rules.mdc` — migration immutability + RLS + `Resolves:` convention
- `.cursor/rules/admin-cms-rules.mdc` — CMS deploy + cookie posture (export route lives here)
- `QUALITY_PERFORMANCE_AGENT.md` — invariants 1–24c (perf, memory, jank); bug-intel was extracted from QPA into THIS file
- `DATA_BACKEND_AGENT.md` — DTO/RPC contracts for `get_bug_intelligence_export`, `mark_bug_reports_exported`
- `SUPABASE_AGENT.md` — table/RPC ownership at the schema level (this agent owns the *content*; Supabase agent owns the *form*)
- `SUPPORT_AGENT.md` — pain-point taxonomy (the `pain_point_candidate` field on triage rows)
- `INFRA_SECURITY_AGENT.md` — Edge Function Auth Registry (`triage-bugs`, `triage-shake-reports`, `github-pr-webhook`)
- `docs/history/QUALITY_PERFORMANCE_AGENT.md` — Phase 1–12 sprint narratives (search `bug-intel`)
- `docs/history/SUPABASE_AGENT.md` — auto-revive cron, `bug-intel-resolves-deploy.yml`, CMS overview filter changes
- `BUG_INTEL_BACKLOG.md` — open classifier gaps + new error-class candidates
- `supabase/MIGRATION_INDEX.md` §"Sprint 8 — Bug Intelligence Pipeline" through §"Phase 13"
