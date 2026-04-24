# Bug-Intelligence Cheat-Code Sweep — Backlog

> **Sprint**: Q2-97 Phase 9 (2026-04-23)
> **Owner**: QUALITY_PERFORMANCE_AGENT (primary) · DATA_BACKEND_AGENT (migration) · INFRA_SECURITY_AGENT (CI)
> **Scope**: Systemic upgrades to the bug-intel pipeline so it fingerprints by root cause, suppresses known transient noise at the DB, auto-resolves stale fixes, detects regressions, and prevents future noise at the call-site via lint + test enforcement.

This file is the running ledger for the bug-intel "cheat code" plan. It is the single source of truth for what has already shipped, what was intentionally scaffolded-but-deferred, and what is explicitly parked until later. Every item is tagged with owner + exit criteria so a future sweep can pick it up without re-deriving the context.

---

## Tier 1 — Ship now (impact > effort)

### 1.1–1.4 · `supabase/20260516_bug_intel_structural_fingerprint.sql` — SHIPPED
- Added 11 columns to `bug_intelligence_fingerprints`: `op`, `error_class`, `pg_code`, `http_status`, `nsurl_code`, `endpoint`, `is_classified`, `structural_fingerprint`, `fixed_in_build`, `regressed_after_fix`, `auto_resolved_at`.
- New table `bug_intel_noise_filter` + seed rows for NSURLError `-999 / -1005 / -1009 / -1001`. Hard-tier rules drop events before fingerprinting; soft-tier reserved for a future "count but don't alert" pass.
- Helper functions: `bug_intel_extract_nsurl_code`, `bug_intel_classify_error`, `bug_intel_compare_semver`.
- Rewrote `compute_daily_bug_rollup()` to project structural fields from `dev_session_logs.extra` + `crash_reports.metadata`, apply noise filter, compute `structural_fingerprint`, detect regressions (`last_seen_build > fixed_in_build`), emit a `regression_after_fix` trend, and auto-resolve fingerprints that have `fixed_in_build` set and no activity for 5+ days.
- One-shot backfill of existing fingerprints + final `DO $$` verify block for noise-filter seed presence.

### 1.3 · Admin CMS export v2 — SHIPPED
- `admin-cms/src/app/bug-intelligence/page.tsx` `formatExportAsMarkdown` leads each report with a **Root cause fields** line (`op`, `class`, `pg_code`, `http`, `nsurl`, `endpoint`, `struct`), a **Classifier bypass** flag that calls out invariant 25a violations, a **REGRESSED** alert when `fixed_in_build` is set but `last_seen_build` is newer, and enriched TL;DR summary bullets.
- CMS list rows now carry structural pills (`REGRESSED`, `unclassified`, `error_class`). Detail panel exposes a dedicated "Root cause" grid.

### 1.5 · Migration index + agent docs — SHIPPED
- `supabase/MIGRATION_INDEX.md` row 82 documents migration 20260516 with the full rationale.
- `QUALITY_PERFORMANCE_AGENT.md` adds invariants 25f–25h (Op registry, classifier lint enforcement, CMS structural fields).

---

## Tier 2 — Agent smarts + guardrails

### 2.1 · `scripts/classifier_lint.py` + CI + pre-commit — SHIPPED
- Scans Supabase-touching Swift files for catch blocks that use `AppLogger.error` / `AppLogger.critical` without `NetworkErrorClassifier`. Warn-only by default; `--strict` exits non-zero.
- Suppression: `// classifier_lint:allow` inside the catch block.
- `.github/workflows/classifier-lint.yml` runs on `Fit33/**/*.swift` PRs, summarizes total + top 20 files, emits per-line PR annotations. Intentionally `|| true` so the build stays green while the backlog drains.
- `.githooks/pre-commit` runs the same lint against staged Swift files locally. `STRICT_CLASSIFIER=1 git commit` opts into local blocking.
- Documented in `.githooks/README.md`.

### 2.2 · `Fit33Tests/PerformanceSignpostsCoverageTests.swift` — SHIPPED
- Greps every `op: "literal"` occurrence in non-test Swift sources and asserts each literal either matches a `PerformanceSignposts.Op.rawValue` or appears in the intentional-allowlist for pass-through string keys (e.g. `app.startup`, `cardio.post_activity`).
- Prevents typos that would splinter `structural_fingerprint`.

### 2.3 · `supabase/functions/bug-intel-rpc-smoke/` — SCAFFOLDED (deferred execution)
- **Status**: `index.ts` skeleton committed; `FIXTURES` array is empty.
- **Why deferred**: populating fixtures requires a dedicated service-role user with deterministic test data, an env-scoped secret (`SMOKE_TEST_USER_ID`), and a CI schedule. Each of those is a separate small sprint:
  1. Provision `bug-intel-smoke@fit33.internal` service identity with the minimum row set needed for each RPC to run successfully (seed weight_log, daily_quest, cardio_workout, etc.).
  2. Register the fixtures — one per RPC critical path — including expected PG code for negative cases (e.g. `post_cardio_activity` with an out-of-range duration should return `23514`).
  3. Schedule via `pg_cron` (5-minute interval) and wire failures into `bug_intelligence_trends` with `trend_type='smoke_failure'` so the existing CMS trend UI surfaces them.
  4. Add a "Smoke test health" card to `/bug-intelligence` that reads from the trend table.
- **Exit criteria**: at least the top 10 user-facing RPCs (weight log, daily quest fetch, workout log, challenge join/decline, social post workout/cardio, hydration log, friend request, follow accept) have fixtures and pass on every 5-minute run. One red smoke emits a Slack/webhook alert and creates a bug-intel fingerprint.

### 2.4 · Auto-resolve — SHIPPED (part of migration 20260516)
- Auto-resolve threshold is "5 days since last_seen_at, has fixed_in_build, not regressed". Tunable in `compute_daily_bug_rollup()`.

### 2.5 · `.cursor/rules/swiftui-rules.mdc` — SHIPPED
- Added sub-sections documenting the classifier lint and the signpost Op registry contract so agents editing `Fit33/**/*.swift` see the rule without having to grep `QUALITY_PERFORMANCE_AGENT.md`.

---

## Tier 3 — Admin CMS upgrades

### 3.1 · Structural columns on fingerprint list — PARTIAL SHIPPED
- Shipped: list-row pills (`error_class`, `REGRESSED`, `unclassified`), Detail panel "Root cause" section with classifier-bypass + regression warnings.
- Deferred: dedicated filter UI (currently these are just visible on the row; no way to filter "show me all `pg:42883` fingerprints" or "show me all fingerprints with `is_classified = false`"). Needs a `FilterBar` addition in `admin-cms/src/app/bug-intelligence/page.tsx` + a matching `get_bug_intelligence_list` action parameter.
- **Exit criteria**: filter chips for `error_class`, `op`, `is_classified`, `regressed_after_fix`. Count badges reflect the filtered set.

### 3.2 · "Related call sites" cross-link — DEFERRED
- **Idea**: when two fingerprints share the same `structural_fingerprint`, show a "Related fingerprints (N)" card in the detail panel so a triager can see "this root cause fires from `weight.log` AND `weight.goal_set` AND `dashboard.weight_widget` — the fix is probably in the shared WeightTrackingService helper, not any single caller".
- **Why deferred**: requires a new SQL function `get_related_fingerprints(structural_fingerprint TEXT)` + CMS API action + UI card. Not blocked; just lower ROI than the smoke-test work.
- **Exit criteria**: opening any fingerprint with `structural_fingerprint IS NOT NULL` shows a list of sibling fingerprints with occurrence counts.

### 3.3 · "Since-last-export" diff dashboard — DEFERRED
- **Idea**: a top-of-page banner that tells the operator "7 new since your last export, 2 regressed" with a one-click "Copy delta markdown" button. Today's export already shows the delta in the .md body; this would surface it before you click export.
- **Why deferred**: trivial UI, but needs a new `get_bug_intelligence_export_preview` action (same query as export but without the `mark_bug_reports_exported` side-effect) so clicking the banner count doesn't stamp `last_exported_at`.
- **Exit criteria**: banner visible when `unexported_count > 0` or `regressed_since_last_export > 0`; click reveals a preview modal.

### 3.4 · Agent leaderboard surfaces structural metrics — DEFERRED
- **Idea**: extend `v_bug_intelligence_metrics` (migration 66) with `unclassified_fingerprint_rate` and `regressed_fix_rate` per agent so the leaderboard makes the "fix held vs regressed" and "logging discipline" stats visible alongside fix-rate.
- **Why deferred**: v_bug_intelligence_metrics is consumed by the `AgentLeaderboard` component; both the view and the component need coordinated updates. Scheduled after Tier 3.1 lands.

---

## Tier 4 — Moonshots (explicitly parked)

### 4.1 · Claude-authored noise-filter rule suggestions
- **Idea**: when Claude triages a fingerprint and classifies it as `severity=low` + `confidence >= 0.8` + `error_class` is transient, it can append a proposed `bug_intel_noise_filter` row as part of its report. An admin approves with one click. This converts the noise-filter table into a learning system.
- **Why parked**: requires a new `bug_intel_noise_filter_suggestions` staging table, an approval UI, and a rollback path (soft-delete rather than hard delete — so we can audit "did that rule hide a real bug?"). Non-trivial product surface.

### 4.2 · `DiagnosticContext` auto-derivation from call site
- **Idea**: a SwiftSyntax-driven preprocessor that inspects every call to `NetworkErrorClassifier.log(...)` and fills in `op:` / `endpoint:` from the enclosing function name + nearby `rpc("...")` / URL literal, so call sites don't have to repeat themselves.
- **Why parked**: tooling cost is high; the manual explicit convention is more valuable as a "grep target" than auto-magic. Revisit only if the `classifier_lint.py` backlog reveals a large cluster of call sites that have everything except `op:`.

### 4.3 · Real-time fingerprint dashboard (replace 30s / hourly polling)
- **Idea**: wire `bug_intelligence_fingerprints` + `bug_intelligence_trends` into the Supabase realtime publication so the CMS page live-updates as new fingerprints arrive (instead of the current polling refresh).
- **Why parked**: marginal UX win; the pipeline is inherently batch (hourly rollup). A live row arriving without a matching rollup row is confusing. Only worth doing after we add a "streaming fingerprint preview" (un-rolled-up events grouped by `structural_fingerprint` as they land).

### 4.4 · Bug-intel-driven release-gate bot
- **Idea**: a GitHub action that reads the latest `bug_intelligence_export` and blocks a release tag if there are any `severity=critical` fingerprints with `fixed_in_build IS NULL` and `regressed_after_fix = FALSE`.
- **Why parked**: release gating is risky to automate without a bypass protocol + on-call owner. Document first, automate later.

---

---

## Phase 10 — 2026-04-24 report-quality sweep (SHIPPED)

Triggered by the 2026-04-24T11:10 Cursor export (74 reports / 6813-line .md).
The headline signal: the SAME 6 structural fingerprints appeared 15 times at
CRITICAL/HIGH because the main-thread watchdog instrumentation
(`Fit33/AppPerformanceSystem.swift` lines 881 + 1105 + 1112) emits
`AppLogger.warning("🚨🚨🚨 [WATCHDOG] MAIN THREAD FROZEN!")` on every freeze,
and Phase 9's `compute_daily_bug_rollup()` now fingerprints `type=warning`
`dev_session_logs` entries. A performance *signal* (we instrumented these on
purpose to know freezes happen) became a fake "bug" every 5-minute rollup.
Same story — at different scale — for 502 Bad Gateway Cloudflare flaps, P0001
"Not authenticated" transients during tab-switch auth propagation, and legacy
PGRST203 overload errors from build 1.37 users who hadn't updated to the
already-deployed fix.

### Report format fix — CMS markdown export de-dupes by structural_fingerprint
- `admin-cms/src/app/bug-intelligence/page.tsx::formatExportAsMarkdown`
  groups bundles by `structural_fingerprint` (fallback `fingerprint` hash,
  last-resort `orphan:<report.id>`), picks the canonical bundle by
  `(severity, confidence, occurrence_count, created_at)`, and inlines the
  collapsed variant titles as `**Also triaged as** (N variants): "…"`. The
  TL;DR header gains `Collapsed: <N> duplicate triage rows merged`. The
  brand-new / regressed / still-pending split reads the deduped list so a
  single root cause can't inflate the counts.

### Server-side noise filter expansion — `20260517_bug_intel_noise_filter_expand.sql`
- Adds 9 new `bug_intel_noise_filter` rows (tier=hard) for the patterns
  above. Runs regex against `sample_message` inside
  `compute_daily_bug_rollup()` — matching events are dropped BEFORE
  fingerprinting.
- Adds `bug_intelligence_fingerprints.auto_resolved_reason` enum column
  (`silent_fix` / `noise_filter_expanded` / `legacy_build_drained` / NULL).
  Distinguishes "fix shipped and the fingerprint went quiet" from "we
  filtered the signal" without spelunking into `bug_intel_noise_filter`
  joins.
- Backfill: existing fingerprints whose `sample_message` now matches the new
  patterns are flipped to `status='resolved'` with
  `auto_resolved_reason='noise_filter_expanded'`, and their pending
  `bug_intelligence_reports` are merged with a paper-trail note.
- Hunts for residual `uuid = text` comparison triggers on `weight_logs` /
  `weight_goals` — any trigger whose function body contains
  `auth.jwt()->>'sub'` / `::text` / `current_setting('request.jwt.claims')`
  emits `RAISE WARNING` with its qualified name. Respects "don't DROP
  triggers we didn't author" rule; the operator decides.

### Client-side denylist sync — `Fit33/CrashReportingService.swift::reportError`
- Added literal `message.contains(...)` short-circuits for `[WATCHDOG]` /
  `[TAB FREEZE]` / `"UI is unresponsive"` / `"502 bad gateway"` /
  `"503 service unavailable"` / `"504 gateway"` / `P0001 "Not authenticated"`.
- Paired with the server filter — keeps the realtime `crash_reports` table
  clean AND avoids burning the `Config.maxReportsPerFingerprint` quota on
  noise during the session a freeze happens in.

### MIGRATION_INDEX Deployment Priority Queue
- Added §"Deployment Priority Queue (2026-04-24)" at the top of
  `supabase/MIGRATION_INDEX.md` calling out the three migrations that fix
  CRITICAL/HIGH clusters in the export but are not yet deployed:
  20260511 (HealthKit RLS — cluster B), 20260513 (PGRST203 overload —
  cluster F), 20260514 (performance_metrics unlock — cluster I), plus the
  new 20260517. Deploy order: 77 → 79 → 80 → 83.

### Invariants added — QUALITY_PERFORMANCE_AGENT.md
- 25i-bugintel: client denylist in `CrashReportingService.reportError` MUST
  mirror server-side `bug_intel_noise_filter` tier='hard' rows.
- 25j-bugintel: markdown export de-dupes by `structural_fingerprint` with
  documented key-selection fallback order.
- 25k-bugintel: `auto_resolved_reason` is the only way to tell silent_fix
  from noise_filter_expanded from legacy_build_drained.
- 25l-bugintel: undeployed migrations that fix bug-intel clusters go in
  MIGRATION_INDEX §"Deployment Priority Queue" rather than being re-fixed.

### Weight-logs 42883 root-cause DROP — SHIPPED (`20260518`)

Phase 10's trigger hunt immediately flagged `public.sync_profile_weight()`
(AFTER INSERT on `weight_logs`) with `WHERE id = NEW.user_id::text`. Both
sides are `uuid`, so the cast forced `uuid = text` which PostgreSQL
rejects as SQLSTATE 42883 — every single `INSERT INTO weight_logs` from
the iOS client hit this after-insert and failed. `20260518_fix_sync_profile_weight_uuid_cast.sql`
uses `CREATE OR REPLACE FUNCTION` to drop the cast (keeps the existing
`pg_trigger` row, avoiding a mid-transaction bypass window), adds a
plan-phase dry-run against a synthetic uuid to fail-closed if the
predicate still mistypes, verifies the trigger is still wired to the
fixed function, and auto-resolves the matching C_uuid fingerprints
(`ff6ae8d5` / `222e0fc1` / `95b0b27b`) with `auto_resolved_reason='silent_fix'`.
No Swift changes — the client has been sending uuid-typed `user_id`
values the whole time; the bug was server-only.

---

## Phase 11 — 2026-04-24 "fix everything" uncategorized drain (SHIPPED)

Triggered by the post-Phase-10 baseline: 163 fingerprints / 575 occurrences
in `cluster_code='uncategorized'`. The goal of Phase 11 was to make every
production fingerprint belong to a named cluster so we can track drain
per domain, and to ship the long-deferred smoke-test + release-gate
infrastructure so future regressions never reach TestFlight.

### Shipped in one commit (2026-04-24)

1. **`supabase/20260519_bug_intel_phase11_sweep.sql`** — 7 new
   `bug_intel_noise_filter` rows for CrashReporter self-upload +
   generic NSURL transients + Swift-side P0001. Auto-stale clause
   (triaged + 7-day-silent → resolved with `auto_resolved_reason =
   'triaged_stale'`). Classifier expanded with
   `H_crashreporter_self` / `I_widget` / `J_wearable_sync` /
   `K_launch_crash`. After-sweep baseline snapshot.
2. **`Fit33/CrashReportingService.swift`** — upload-failed catch passes
   `transientLevel: .debug` (kills new additions to the self-upload
   loop at the source). Denylist extended with watchdog / tab-freeze /
   UI-unresponsive / 502/503/504 / P0001 / `[CrashReporter] Upload
   failed` / Social transient patterns.
3. **`Fit33/AppPerformanceSystem.swift`** — watchdog freeze log at
   line 1105 + UI-unresponsive sub-log at line 1112 + tab-freeze
   detection at line 881 downgraded to `.debug` on release via
   `#if DEBUG / #else`. DEBUG builds keep `.warning` / `.error` for
   dev console visibility. `MainThreadWatchdog.start()` remains
   `#if DEBUG` gated per QP invariant #5 — these three log sites
   were the only stragglers shipping watchdog text to release
   dev_session_logs.
4. **`admin-cms/src/app/bug-intelligence/page.tsx`** — three new
   filter chips: `error_class` (unknown / network_lost / cancelled /
   rls / uuid_mismatch / overload / auth_flap), `regressed` (all /
   REGRESSED-only), `classifier` (all / classified / unclassified).
   Client-side derivation via `useMemo` — no new server RPC, no
   schema change.
5. **`supabase/functions/bug-intel-rpc-smoke/index.ts`** — populated
   `FIXTURES[]` with 11 signature-smoke tests that probe every
   user-facing RPC (get_daily_quests_body, post_workout_activity,
   post_cardio_activity, get_friends, get_received_workouts,
   get_sent_workouts, log_private_challenge_progress,
   get_my_private_challenges, increment_hydration,
   compute_daily_bug_rollup). Signature-only strategy: intentionally
   zeroed uuids + neutral primitives; asserts against a `SIGNATURE_ERRORS`
   set (PGRST202 / PGRST203 / PGRST100 / PGRST102 / 42883 / 42P01 /
   42703 / 42P18) that represents real schema drift. Data-correctness
   tests deferred until a dedicated seeded service account is
   provisioned (Tier 2.3 exit criteria).
6. **`.github/workflows/bug-intel-rpc-smoke.yml`** — runs the smoke
   function every 15 minutes + on every push to main under
   `supabase/`. Fails the job with a GitHub Step Summary table if
   any fixture returns a `SIGNATURE_ERROR` code.
7. **`.github/workflows/bug-intel-release-gate.yml`** — blocks release
   tag pushes (`v*.*.*` / `v*.*`) if any open CRITICAL
   `bug_intelligence_fingerprint` has (a) `status NOT IN ('resolved',
   'wont_fix', 'duplicate')` OR (b) `regressed_after_fix = true`.
   Override paths: `[skip-bug-gate]` commit-message trailer OR
   `workflow_dispatch` with non-empty `override_reason`. Both paths
   write an audit trail via the job Step Summary.

### Invariants added — QUALITY_PERFORMANCE_AGENT.md
- 25m-bugintel: `CrashReportingService` failure paths MUST never log at
  `.error` / `.warning` — the reporter is self-referential, so every
  error written here risks becoming its own fingerprint.
- 25n-bugintel: Watchdog + tab-freeze logs in `AppPerformanceSystem.swift`
  MUST be DEBUG-gated at the log-call level (not just at the timer
  level). Release builds downgrade `.warning` / `.error` → `.debug`.
- 25o-bugintel: The Phase 11 classifier LIKE pattern order in
  `snapshot_bug_intel_baseline()` is not commutative — most-specific
  patterns first (H/I/J/K before A/B/C/…) or fingerprints that match
  multiple buckets get miscategorized.
- 25p-bugintel: Every newly-added `bug_intel_noise_filter` row MUST
  pass a 10-second eyeball review against the false-positive risk
  list — these are regex patterns that run against every
  `sample_message` on every rollup, and a too-loose regex will hide
  real bugs.

### Deferred to next sweep
- **Apple Watch workout save timeouts** (soft-tier filter in 20260517):
  device-to-phone sync latency, out of our control. Consider
  surfacing a subtle "Apple Watch sync is slow" banner only after
  the threshold is exceeded for N consecutive saves.
- **SIGSEGV / CFString crashes** (cluster E, fingerprints
  `e955904c` + 3 others): need full stack traces via MetricKit
  `metrickit_payloads` query — see investigation SQL below.
- **Seeded smoke-test service account** (Tier 2.3 full exit
  criteria): unblocks data-correctness smoke tests (actual
  write-then-read-back against a fixture). Separate sprint.
- **Noise-filter "soft" tier tracking**: the `healthkit_apple_watch_save_timeout`
  filter is tier='soft' (kept for admin visibility, excluded from default
  trends). The CMS bug-intel UI currently renders soft-filtered rows the
  same as hard-filtered. A follow-up can add a "soft" pill so operators can
  distinguish.

---

## How to work this backlog

1. **Pick an item whose exit criteria you can meet in one PR.** The Tier 2.3 smoke tests, for example, should not be partially fixtured — ship all 10 or none.
2. **Update this file in the same PR** — move the item from its tier into a new "## Shipped log" subsection with the date, the migration / PR link, and a one-line outcome.
3. **If new rules are discovered** (e.g. "never filter on `error_class` without also filtering `status`"), add them as invariants to `QUALITY_PERFORMANCE_AGENT.md` and cross-link here.
4. **Avoid introducing new tables**. Prefer columns on existing bug-intel tables, views, or structured `JSONB` fields — the pipeline is already complex enough.

---

## See also
- `supabase/20260516_bug_intel_structural_fingerprint.sql` — the core structural-fingerprint migration.
- `QUALITY_PERFORMANCE_AGENT.md` invariants 25a, 25c–25h — end-to-end logging discipline.
- `supabase/MIGRATION_INDEX.md` rows 63–70 — the original bug-intel pipeline (Phase 1 → Phase 7).
- `scripts/classifier_lint.py` + `.github/workflows/classifier-lint.yml` + `.githooks/pre-commit` — the enforcement layer.
- `Fit33Tests/PerformanceSignpostsCoverageTests.swift` — Op registry consistency.
- `supabase/functions/bug-intel-rpc-smoke/index.ts` — scaffolded synthetic RPC runner (Tier 2.3).
