# Phase 5 — Server-side dSYM Symbolication Plan
**Status**: Proposed · **Sprint**: Q2 follow-up to Q2-97 (Bug Intelligence) · **Date drafted**: 2026-04-29

## Why this exists
Phase 3 of the Bug Intelligence pipeline produced Claude triage reports with
`file_path + code_diff` on **0/12** crash-sourced reports in its first run.
The root cause was not prompt or model quality — it was raw data. Our
`crash_reports.stack_trace` values are unsymbolicated hex offsets:

```
0   Fit33        0x0000000104d3b0d8 Fit33 + 7418072
1   Fit33        0x0000000104d3799c Fit33 + 7403932
2   Foundation   0x000000019bbbd804 F87E3667-... + 583684
```

Claude correctly refused to hallucinate Swift file names from address
offsets. Phase 3.1 worked around this by falling back to error-message
tags and screen context (yielding 7/12 inferred `file_path` at capped
confidence 0.70), but to produce real diffs — the thing that makes the
`/bug-intelligence` page a 1-click-PR queue — we need the real source
locations.

## The one-line plan
**On every crash insert, resolve each frame address to `file:line:function`
using the matching build's `.dSYM` and Apple's `atos` tool, store the
result in `crash_reports.symbolicated_stack_trace`, and teach the
triage-bugs edge function to prefer it over the raw hex stack.**

## Architecture
```
┌─────────────────────────────────────────────────────────────┐
│  Xcode Archive (manual or CI)                               │
│    └─ Run Script phase:  scripts/upload_dsym.sh             │
│         - zips Fit33.app.dSYM                               │
│         - PUTs to Storage bucket `dsyms/<build_uuid>.zip`   │
│         - inserts into app_dsyms (uuid, app_ver, build, sha)│
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│  iOS CrashReporter.swift (existing)                         │
│    - now ALSO captures:                                     │
│        binary_uuid   = dyld_image_uuid(for: main image)     │
│        binary_slide  = _dyld_get_image_vmaddr_slide(0)      │
│    - sent up with the existing crash payload                │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│  crash_reports INSERT  (session_log_snippet trigger fires)  │
│    - symbolication_status defaults to 'pending'             │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│  GitHub Actions (macos-latest, every 15 min)                │
│    symbolicate-crashes.yml                                  │
│    1. SELECT id, binary_uuid, binary_slide, stack_trace     │
│         FROM crash_reports                                  │
│         WHERE symbolication_status = 'pending'              │
│         LIMIT 50                                            │
│    2. For each distinct binary_uuid, download dSYM from     │
│       Supabase Storage into /tmp/dsyms/<uuid>.dSYM          │
│    3. Parse hex addresses out of stack_trace               │
│    4. atos -arch arm64 -o <dSYM>/Contents/Resources/.../    │
│         -l <slide> <addr1> <addr2> ... <addrN>              │
│    5. UPDATE crash_reports SET                              │
│         symbolicated_stack_trace = <resolved>,              │
│         symbolication_status = 'done',                      │
│         symbolicated_at = now()                             │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│  triage-bugs (Phase 3 edge function)                        │
│    - selects symbolicated_stack_trace when not null         │
│    - system prompt's "SYMBOLICATED" branch activates        │
│    - Claude emits file_path + code_diff at 0.85+ confidence │
└─────────────────────────────────────────────────────────────┘
```

## Why not do it inside a Supabase Edge Function?
Edge Functions run on Deno / Linux. `atos` is macOS-only and the DWARF
parsing libraries in JS/TS are either incomplete (missing Swift name
mangling) or too slow (pure-JS DWARF walkers). Writing our own
symbolicator is a multi-week project for a solved problem. Apple's
`atos` on a scheduled macOS GitHub Actions runner is the simplest,
highest-quality option.

## Why GitHub Actions and not Xcode Cloud?
- Owned by us (not Apple's throttles), cheaper ($0.08/min macOS vs
  $14.99/mo XC base tier that only runs at build time).
- Easier to inspect and re-run failed symbolication batches.
- Can scale up by running concurrent matrix jobs across dSYM ranges.

## Deliverables (6 sub-phases, each shippable independently)

| Phase | Scope | Est. | Key files |
|---|---|---|---|
| 5.1 | iOS client captures `binary_uuid` + `binary_slide` on every crash | 1 hr | `Fit33/CrashReporter.swift` (or wherever crash is assembled) |
| 5.2 | Migration: `app_dsyms` table + new crash_reports columns + `symbolication_status` enum | 45 min | `supabase/20260501_dsym_symbolication.sql` |
| 5.3 | Storage bucket `dsyms` + RLS (admin-write, service-role-read) | 20 min | `supabase/20260501_dsym_symbolication.sql` (same file) |
| 5.4 | Xcode Archive post-action script + setup doc | 1 hr | `scripts/upload_dsym.sh`, `docs/DSYM_UPLOAD.md` |
| 5.5 | GitHub Actions workflow (`macos-latest`, `*/15 * * * *`) | 2 hrs | `.github/workflows/symbolicate-crashes.yml` |
| 5.6 | `triage-bugs` prefers `symbolicated_stack_trace` + strengthens prompt | 30 min | `supabase/functions/triage-bugs/index.ts` |

## Known risks (acknowledged up-front)

- **Legacy crashes (~9,500 currently)** — we don't have their dSYMs because
  those builds preceded the pipeline. They remain `symbolication_status =
  'legacy'` forever. Phase 3.1's unsymbolicated fallback (error-message
  tag + screen inference) is their ongoing home.
- **UUID drift** — TestFlight + App Store rebuilds of "v1.37 (41)" can
  produce DIFFERENT `binary_uuid` values. We key off `binary_uuid`
  (always unique per build), never `app_version`, so this is safe by
  design.
- **macOS runner cost** — budget estimate: 50-100 crashes/day after
  backfill × ~2 sec each × every 15 min = well under $5/month. Negligible.
- **Storage size** — one dSYM bundle zipped is 50-200MB. 10 builds/month
  × 6-month retention = 12GB. Inside Supabase's free tier.
- **3rd-party frames (UIKit, Foundation)** — `atos` cannot resolve these
  without Apple's public symbol server. Claude doesn't need them; it
  only needs the first Fit33-owned frame, which `atos` handles.

## Explicitly out-of-scope for Phase 5
- Realtime (<1-min) symbolication. 15-minute cron is fine — the
  triage-bugs cron only fires every 4 hours downstream.
- Auto-dSYM upload from Xcode Cloud or TestFlight upload. Manual
  `scripts/upload_dsym.sh` run after Archive is the v1 flow.
- Multi-architecture support. We ship arm64 only; `atos -arch arm64` is
  hard-coded.
- Symbolication of `crash_reports.breadcrumbs` stack frames. Breadcrumbs
  carry strings, not addresses — not a symbolication target.

## Success criteria
When Phase 5 is done, re-run of the 12 Phase 2 fingerprints should move:
- `file_path` populated: **7/12 → 12/12**
- `code_diff` populated: **0/12 → ≥8/12 on crash-sourced, 0 on log-only**
- Confidence on crash-sourced reports: **0.70 (capped) → 0.85-0.95**

That converts the `/bug-intelligence` page from "investigative inbox"
into a **"1-click merge queue"** for crash fixes — the original goal
of the Bug Intelligence pipeline.

## Blocking decision needed before Phase 5 starts
None — the plan is self-contained. Kick-off only requires confirmation
from the repo owner that the monthly macOS-runner cost (estimated <$5)
is acceptable.

---

**Related docs**
- `supabase/20260427_bug_intelligence.sql` — Phase 1 fingerprinting
- `supabase/20260428_bug_intelligence_reports.sql` — Phase 2 triage
- `supabase/20260429_bug_intelligence_crash_enrichment.sql` — Phase 3 enrichment
- `supabase/20260430_bug_intel_feedback_loop.sql` — Phase 4 feedback loop
- `QUALITY_PERFORMANCE_AGENT.md` — owner of the crash-fix workstream
