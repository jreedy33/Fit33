#!/usr/bin/env python3
"""
Catalog-wide exercise auditor.
==============================

Runs every exercise in the canonical catalog through the same Claude →
propose_exercise_correction pipeline used by `analyze-quality-workout`,
without waiting for users to perform every exercise as a quality workout.

WHY
---
The workout-intelligence pipeline only audits an exercise the moment a user
completes it in a quality workout. That's slow (months to cover the catalog)
and biased (rarely-performed exercises never get audited). This script
forces a single sweep across all 6,000+ rows so we surface the long tail
of muscle-mislabels, wrong is_compound flags, etc. immediately.

PIPELINE
--------
Two phases. Run dry-run first, eyeball the CSV, then apply.

  Phase 1 — `--dry-run` (default if no --apply):
    1. Pull every exercise id from the catalog.
    2. For each, hit the `audit-catalog-exercise` edge function with
       apply=false (Claude call, no DB writes).
    3. Append every returned proposal to scripts/output/catalog_audit_<ts>.csv.
    4. Skip exercises with an existing non-rejected proposal so re-runs
       are cheap (idempotent).

  Phase 2 — `--apply scripts/output/catalog_audit_<ts>.csv`:
    1. Read the CSV.
    2. For each row, call propose_exercise_correction RPC directly via
       service-role supabase-py. NO second Claude call.
    3. Write apply_status / proposal_id / auto_applied / reason back to
       a sibling _applied.csv next to the input CSV.

The propose RPC handles the corroboration ladder (sister/name/multi-report)
and core-exercise lockout. Auto-applied corrections land in `exercises`
immediately; everything else sits in `/catalog-proposals` for admin review.

USAGE
-----
  # 1. Test 100-exercise dry-run first to sanity-check Claude's quality:
  python scripts/audit_exercise_catalog.py --dry-run --limit 100

  # 2. Open the resulting CSV in scripts/output/, eyeball ~10 rows.

  # 3. If quality looks good, run the full dry-run sweep:
  python scripts/audit_exercise_catalog.py --dry-run
    # ~6,352 exercises, ~$60-80, ~2-3 hours wall-clock

  # 4. Inspect what the apply phase will do, bucket-by-bucket (no writes):
  python scripts/audit_exercise_catalog.py --apply scripts/output/catalog_audit_<ts>.csv --stage-stats

  # 5. Land safest stage first (equipment_category capitalization fixes).
  #    Sister-gate auto-applies almost all of these; the rest queue for review.
  python scripts/audit_exercise_catalog.py --apply scripts/output/catalog_audit_<ts>.csv --stage caps

  # 6. Then sister-likely (proposals whose evidence cites a sibling exercise):
  python scripts/audit_exercise_catalog.py --apply scripts/output/catalog_audit_<ts>.csv --stage sister

  # 7. Then everything else (name-gate / multi-report / human review):
  python scripts/audit_exercise_catalog.py --apply scripts/output/catalog_audit_<ts>.csv --stage rest

  # OR — single-shot for full firehose (skips staging):
  python scripts/audit_exercise_catalog.py --apply scripts/output/catalog_audit_<ts>.csv

  # Cap the count for a tiny canary run:
  python scripts/audit_exercise_catalog.py --apply scripts/output/catalog_audit_<ts>.csv --stage caps --max-apply 50

REQUIREMENTS
------------
  - SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY in .env (already set up).
  - ANTHROPIC_API_KEY in Supabase secrets (already set up — used by
    analyze-quality-workout). The edge function reads it; this script
    never touches it directly.
  - `audit-catalog-exercise` edge function deployed:
      supabase functions deploy audit-catalog-exercise
"""
from __future__ import annotations

import argparse
import csv
import json
import os
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any

# Local relative imports (we live in scripts/, alongside load_env.py).
sys.path.insert(0, str(Path(__file__).resolve().parent))
import load_env  # noqa: F401 — auto-loads .env

import requests  # noqa: E402 — bundled with supabase-py; ships its own CA bundle so
                 # avoids the python.org framework "no local issuer cert" issue on macOS.
from supabase import create_client  # noqa: E402

# ─── config ─────────────────────────────────────────────────────────────────

SUPABASE_URL = os.environ.get("SUPABASE_URL", "").rstrip("/")
SUPABASE_SERVICE_ROLE_KEY = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")

if not SUPABASE_URL or not SUPABASE_SERVICE_ROLE_KEY:
    print("ERROR: SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY must be set in .env", file=sys.stderr)
    sys.exit(2)

EDGE_FN_URL = f"{SUPABASE_URL}/functions/v1/audit-catalog-exercise"
EDGE_FN_TIMEOUT_SEC = 90  # Claude call inside has its own 30s; allow slack.

# Defaults — tuned to stay well under Anthropic Tier 1 limits (50 RPM Sonnet 4)
# while still finishing 6K exercises in ~2-3 hours.
DEFAULT_CONCURRENCY = 3
DEFAULT_SKIP_RECENT_DAYS = 30

OUTPUT_DIR = Path(__file__).resolve().parent / "output"
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

CSV_FIELDS = [
    "exercise_id",
    "exercise_name",
    "exercise_family",
    "field",
    "operation",
    "proposed_value",
    "confidence",
    "evidence",
    "input_tokens",
    "output_tokens",
    "cache_read_tokens",
    "cache_write_tokens",
    "claude_called_at",
]

APPLIED_CSV_FIELDS = CSV_FIELDS + [
    "proposal_id",
    "auto_applied",
    "apply_reason",
    "apply_error",
    "applied_at",
]

# Apply-phase staging. The dry-run CSV gets segmented into rough buckets
# so the operator can land safe stuff first, then escalate. We classify by
# the `evidence` text Claude wrote (it's heavily templated by the system
# prompt's worked examples — "sister X also has...", "should be capitalized
# as ...", etc.) plus the `field` column.
STAGE_CHOICES = ("caps", "sister", "rest", "all")
STAGE_DESCRIPTIONS = {
    "caps": "equipment_category capitalization/case fixes only — safest, sister-gate lands ~all",
    "sister": "proposals whose evidence references a sister exercise — sister-gate likely",
    "rest": "everything not in caps or sister — name-gate / multi-report or human review",
    "all": "no stage filter (default behaviour)",
}


def classify_stage(row: dict[str, str]) -> str:
    """Map a CSV proposal row to one of {caps, sister, rest}.

    Heuristic — we only have what's in the CSV. The dry-run does NOT record
    the prior catalog value, so we can't compute exactly "is this a pure
    case-only change?". We approximate via the evidence string Claude
    produced (which mirrors the system prompt's worked examples).
    """
    evidence = (row.get("evidence") or "").lower()
    field = row.get("field", "")

    is_caps = (
        field == "equipment_category"
        and any(kw in evidence for kw in ("capital", "lowercase", "case", "title-case"))
    )
    if is_caps:
        return "caps"
    if "sister" in evidence:
        return "sister"
    return "rest"


def filter_rows_by_stage(rows: list[dict[str, str]], stage: str) -> list[dict[str, str]]:
    if stage == "all":
        return list(rows)
    return [r for r in rows if classify_stage(r) == stage]


# ─── helpers ────────────────────────────────────────────────────────────────


def now_iso() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def call_edge_function(exercise_id: str) -> dict[str, Any]:
    """Hit the audit-catalog-exercise edge function. Returns parsed JSON."""
    try:
        resp = requests.post(
            EDGE_FN_URL,
            json={"exercise_id": exercise_id, "apply": False},
            headers={
                "Authorization": f"Bearer {SUPABASE_SERVICE_ROLE_KEY}",
                "Content-Type": "application/json",
            },
            timeout=EDGE_FN_TIMEOUT_SEC,
        )
        if resp.status_code != 200:
            return {"error": f"http_{resp.status_code}", "body": resp.text[:500]}
        return resp.json()
    except requests.exceptions.RequestException as e:
        return {"error": f"network_{type(e).__name__}", "body": str(e)[:200]}
    except json.JSONDecodeError as e:
        return {"error": f"bad_json_{e.msg}"}


def load_existing_proposal_keys(supabase) -> set[tuple[str, str, str, str]]:
    """Pull every (exercise_id, field_name, operation, proposed_value-as-text)
    for proposals NOT in 'rejected' state. We use this to skip exercises
    that already have a live proposal — rejected proposals can be re-asked
    (admin may have rejected it for a stale reason).

    NOTE: We dedupe at the (exercise_id) granularity for the dry-run skip
    list — we only want to skip if there's at least one live proposal.
    The (field, operation, proposed_value) key is preserved so the apply
    phase can do per-row dedup later.
    """
    keys: set[tuple[str, str, str, str]] = set()
    page = 0
    page_size = 1000
    while True:
        res = (
            supabase.table("exercise_correction_proposals")
            .select("exercise_id, field_name, operation, proposed_value, status")
            .neq("status", "rejected")
            .range(page * page_size, (page + 1) * page_size - 1)
            .execute()
        )
        rows = res.data or []
        for r in rows:
            keys.add((
                str(r["exercise_id"]),
                str(r["field_name"]),
                str(r["operation"]),
                json.dumps(r["proposed_value"], sort_keys=True),
            ))
        if len(rows) < page_size:
            break
        page += 1
    return keys


def fetch_exercise_ids(
    supabase,
    skip_recent_days: int,
    skip_existing_proposals: bool,
    family_filter: str | None,
    limit: int | None,
) -> list[dict[str, Any]]:
    """Pull all exercise rows we want to audit. Filters applied:
      - skip exercises edited manually within `skip_recent_days`
      - skip exercises that already have a non-rejected proposal
      - optional --family filter
    Returns list of {id, name, exercise_family, manually_updated_at}.
    """
    page = 0
    page_size = 1000
    all_rows: list[dict[str, Any]] = []
    while True:
        q = (
            supabase.table("exercises")
            .select("id, name, exercise_family, manually_updated_at")
            .order("name")
            .range(page * page_size, (page + 1) * page_size - 1)
        )
        if family_filter:
            q = q.eq("exercise_family", family_filter)
        res = q.execute()
        rows = res.data or []
        all_rows.extend(rows)
        if len(rows) < page_size:
            break
        page += 1

    # Manual-edit skip. `skip_recent_days <= 0` means "audit everything, no
    # matter how recently it was hand-edited" — useful when the operator
    # wants a fully clean sweep across the whole catalog (the user already
    # asked for that explicitly on 2026-05-07).
    if skip_recent_days <= 0:
        fresh = list(all_rows)
        skipped_manual = 0
    else:
        cutoff = datetime.now(timezone.utc) - timedelta(days=skip_recent_days)
        cutoff_iso = cutoff.isoformat()
        fresh = [
            r for r in all_rows
            if not r.get("manually_updated_at") or str(r["manually_updated_at"]) < cutoff_iso
        ]
        skipped_manual = len(all_rows) - len(fresh)

    # Existing-proposal skip.
    skipped_existing = 0
    if skip_existing_proposals:
        existing_ids = {
            k[0] for k in load_existing_proposal_keys(supabase)
        }
        before = len(fresh)
        fresh = [r for r in fresh if str(r["id"]) not in existing_ids]
        skipped_existing = before - len(fresh)

    if limit:
        fresh = fresh[:limit]

    print(
        f"[scope] catalog={len(all_rows)} "
        f"skipped_manual_recent={skipped_manual} "
        f"skipped_existing_proposal={skipped_existing} "
        f"to_audit={len(fresh)}"
    )
    return fresh


# ─── dry-run phase ──────────────────────────────────────────────────────────


def run_dry_run(args) -> int:
    print(f"[init] connecting to {SUPABASE_URL}")
    supabase = create_client(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY)

    rows = fetch_exercise_ids(
        supabase,
        skip_recent_days=args.skip_recent_days,
        skip_existing_proposals=not args.no_skip_existing,
        family_filter=args.family,
        limit=args.limit,
    )
    if not rows:
        print("[done] nothing to audit.")
        return 0

    ts = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%SZ")
    out_path = OUTPUT_DIR / f"catalog_audit_{ts}.csv"
    print(f"[output] {out_path}")

    # Estimate cost so the operator has a number to compare against budget.
    est_calls = len(rows)
    est_cost_low = round(est_calls * 0.005, 2)
    est_cost_high = round(est_calls * 0.012, 2)
    print(f"[budget] estimated Anthropic cost: ${est_cost_low}-${est_cost_high} for {est_calls} calls")

    if args.confirm:
        ok = input(f"[confirm] Proceed with {est_calls} Claude calls? [y/N] ")
        if ok.strip().lower() not in ("y", "yes"):
            print("[abort] user declined")
            return 1

    started = time.time()
    proposals_total = 0
    exercises_with_proposals = 0
    exercises_done = 0
    exercises_failed = 0
    last_progress_at = time.time()

    with open(out_path, "w", newline="", encoding="utf-8") as fh:
        writer = csv.DictWriter(fh, fieldnames=CSV_FIELDS)
        writer.writeheader()
        fh.flush()

        # Concurrent edge function calls. ThreadPoolExecutor is fine here —
        # each call is I/O bound.
        with ThreadPoolExecutor(max_workers=args.concurrency) as pool:
            futures = {
                pool.submit(call_edge_function, str(r["id"])): r
                for r in rows
            }
            for fut in as_completed(futures):
                r = futures[fut]
                exercises_done += 1
                try:
                    result = fut.result()
                except Exception as e:  # noqa: BLE001
                    exercises_failed += 1
                    print(f"[err] {r['name']}: {e}")
                    continue

                if "error" in result:
                    exercises_failed += 1
                    print(f"[err] {r['name']}: {result.get('error')} :: {result.get('body','')[:200]}")
                    continue

                proposals = result.get("proposals", []) or []
                if proposals:
                    exercises_with_proposals += 1
                proposals_total += len(proposals)
                usage = result.get("usage", {}) or {}
                ts_call = now_iso()
                for p in proposals:
                    writer.writerow({
                        "exercise_id": r["id"],
                        "exercise_name": r["name"],
                        "exercise_family": r.get("exercise_family") or "",
                        "field": p.get("field", ""),
                        "operation": p.get("operation", ""),
                        "proposed_value": json.dumps(p.get("newValue")),
                        "confidence": p.get("confidence", ""),
                        "evidence": p.get("evidence", ""),
                        "input_tokens": usage.get("input", ""),
                        "output_tokens": usage.get("output", ""),
                        "cache_read_tokens": usage.get("cache_read", ""),
                        "cache_write_tokens": usage.get("cache_write", ""),
                        "claude_called_at": ts_call,
                    })
                fh.flush()

                # Progress report every ~25 exercises or every 30s.
                if exercises_done % 25 == 0 or time.time() - last_progress_at > 30:
                    elapsed = time.time() - started
                    rate = exercises_done / elapsed if elapsed > 0 else 0
                    eta_sec = (len(rows) - exercises_done) / rate if rate > 0 else 0
                    eta_min = int(eta_sec / 60)
                    print(
                        f"[progress] {exercises_done}/{len(rows)} "
                        f"({100*exercises_done/len(rows):.1f}%) | "
                        f"failed={exercises_failed} | "
                        f"proposals={proposals_total} | "
                        f"rate={rate:.2f}/s | "
                        f"eta={eta_min}m"
                    )
                    last_progress_at = time.time()

    elapsed = time.time() - started
    print()
    print("─" * 60)
    print(f"[done] elapsed: {elapsed/60:.1f} min")
    print(f"[done] exercises audited: {exercises_done}")
    print(f"[done] exercises with proposals: {exercises_with_proposals}")
    print(f"[done] failures: {exercises_failed}")
    print(f"[done] total proposals: {proposals_total}")
    print(f"[done] CSV: {out_path}")
    print()
    print("Next step: review the CSV, then run:")
    print(f"  python {Path(__file__).name} --apply {out_path}")
    return 0 if exercises_failed == 0 else 1


# ─── apply phase ────────────────────────────────────────────────────────────


def run_apply(args) -> int:
    csv_path = Path(args.apply)
    if not csv_path.exists():
        print(f"ERROR: CSV not found: {csv_path}", file=sys.stderr)
        return 2

    print(f"[init] connecting to {SUPABASE_URL}")
    supabase = create_client(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY)

    rows: list[dict[str, str]] = []
    with open(csv_path, "r", encoding="utf-8") as fh:
        reader = csv.DictReader(fh)
        rows = [r for r in reader]
    if not rows:
        print("[done] CSV has no proposals to apply")
        return 0

    # Per-stage census. Always print so the operator sees the lay of the land.
    stage_counts: dict[str, int] = {"caps": 0, "sister": 0, "rest": 0}
    for r in rows:
        stage_counts[classify_stage(r)] += 1
    print(f"[stages] total proposals: {len(rows)}")
    for s in ("caps", "sister", "rest"):
        pct = (100 * stage_counts[s] / len(rows)) if rows else 0
        print(f"[stages]   {s:<6} = {stage_counts[s]:>5} ({pct:>5.1f}%) — {STAGE_DESCRIPTIONS[s]}")

    if args.stage_stats:
        print("[stage-stats] preview only — no DB writes. Re-run with `--apply <csv> --stage <name>` to land a stage.")
        return 0

    stage = args.stage or "all"
    if stage not in STAGE_CHOICES:
        print(f"ERROR: --stage must be one of {STAGE_CHOICES}", file=sys.stderr)
        return 2

    if stage != "all":
        before = len(rows)
        rows = filter_rows_by_stage(rows, stage)
        print(f"[stage] filter='{stage}' kept {len(rows)} of {before} proposals")
        if not rows:
            print("[done] nothing to apply for this stage.")
            return 0

    if args.max_apply is not None and args.max_apply > 0 and len(rows) > args.max_apply:
        print(f"[max-apply] capping at first {args.max_apply} of {len(rows)} proposals")
        rows = rows[: args.max_apply]

    print(f"[scope] {len(rows)} proposals to call propose_exercise_correction for")

    if args.confirm:
        ok = input(f"[confirm] Proceed? [y/N] ")
        if ok.strip().lower() not in ("y", "yes"):
            print("[abort] user declined")
            return 1

    # Stamp the apply CSV with the stage so successive runs don't clobber each other.
    suffix = "_applied" if stage == "all" else f"_applied_{stage}"
    out_path = csv_path.with_name(csv_path.stem + suffix + ".csv")
    print(f"[output] {out_path}")

    auto_applied = 0
    queued_pending = 0
    blocked = 0
    errored = 0
    started = time.time()

    # De-dupe: same (exercise_id, field, operation, proposed_value) appearing
    # twice in the CSV (shouldn't happen but defensive). Also dedup against
    # existing proposals.
    existing_keys = load_existing_proposal_keys(supabase)
    seen_in_csv: set[tuple[str, str, str, str]] = set()

    with open(out_path, "w", newline="", encoding="utf-8") as fh:
        writer = csv.DictWriter(fh, fieldnames=APPLIED_CSV_FIELDS)
        writer.writeheader()
        fh.flush()

        for i, r in enumerate(rows, start=1):
            key = (
                r["exercise_id"],
                r["field"],
                r["operation"],
                # proposed_value column was dumped via json.dumps so it's
                # already canonical JSON; load+redump to canonicalize key sort.
                json.dumps(json.loads(r["proposed_value"]), sort_keys=True),
            )

            out_row = {**r}
            if key in seen_in_csv:
                out_row.update({
                    "proposal_id": "",
                    "auto_applied": "",
                    "apply_reason": "duplicate_in_csv",
                    "apply_error": "",
                    "applied_at": now_iso(),
                })
                writer.writerow(out_row)
                continue
            seen_in_csv.add(key)

            if key in existing_keys:
                out_row.update({
                    "proposal_id": "",
                    "auto_applied": "",
                    "apply_reason": "existing_proposal_skipped",
                    "apply_error": "",
                    "applied_at": now_iso(),
                })
                writer.writerow(out_row)
                continue

            try:
                proposed_value = json.loads(r["proposed_value"])
                confidence = float(r["confidence"])
                resp = supabase.rpc(
                    "propose_exercise_correction",
                    {
                        "p_exercise_id": r["exercise_id"],
                        "p_field_name": r["field"],
                        "p_operation": r["operation"],
                        "p_new_value": proposed_value,
                        "p_confidence": confidence,
                        "p_evidence": r["evidence"],
                        "p_source_report_id": None,
                    },
                ).execute()
                data = resp.data or {}
                proposal_id = data.get("proposal_id") or ""
                applied = bool(data.get("auto_applied"))
                reason = data.get("reason") or ("auto_applied" if applied else "queued")

                if applied:
                    auto_applied += 1
                elif "blocked" in str(reason):
                    blocked += 1
                else:
                    queued_pending += 1

                out_row.update({
                    "proposal_id": str(proposal_id),
                    "auto_applied": "true" if applied else "false",
                    "apply_reason": str(reason),
                    "apply_error": "",
                    "applied_at": now_iso(),
                })
                writer.writerow(out_row)
                fh.flush()
            except Exception as e:  # noqa: BLE001
                errored += 1
                out_row.update({
                    "proposal_id": "",
                    "auto_applied": "",
                    "apply_reason": "",
                    "apply_error": str(e)[:500],
                    "applied_at": now_iso(),
                })
                writer.writerow(out_row)
                fh.flush()
                print(f"[err] {r['exercise_name']} {r['field']}/{r['operation']}: {e}")

            if i % 50 == 0:
                elapsed = time.time() - started
                rate = i / elapsed if elapsed > 0 else 0
                print(
                    f"[progress] {i}/{len(rows)} "
                    f"applied={auto_applied} pending={queued_pending} "
                    f"blocked={blocked} err={errored} "
                    f"rate={rate:.1f}/s"
                )

    print()
    print("─" * 60)
    print(f"[done] auto-applied:   {auto_applied}")
    print(f"[done] queued/pending: {queued_pending}")
    print(f"[done] blocked:        {blocked}")
    print(f"[done] errors:         {errored}")
    print(f"[done] output:         {out_path}")
    print()
    print("Review pending proposals at:  https://admin.doublethr33s.com/catalog-proposals")
    return 0 if errored == 0 else 1


# ─── main ───────────────────────────────────────────────────────────────────


def main() -> int:
    ap = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    ap.add_argument("--dry-run", action="store_true",
                    help="Phase 1: call Claude per exercise, write CSV, NO DB writes.")
    ap.add_argument("--apply", metavar="CSV_PATH",
                    help="Phase 2: read CSV, call propose_exercise_correction RPC for each row.")
    ap.add_argument("--limit", type=int, default=None,
                    help="(dry-run only) Cap the number of exercises audited. Use for test batches.")
    ap.add_argument("--family", default=None,
                    help="(dry-run only) Filter to a single exercise_family.")
    ap.add_argument("--skip-recent-days", type=int, default=DEFAULT_SKIP_RECENT_DAYS,
                    help="(dry-run only) Skip exercises with manually_updated_at within N days. "
                         f"Default: {DEFAULT_SKIP_RECENT_DAYS}.")
    ap.add_argument("--no-skip-existing", action="store_true",
                    help="(dry-run only) Don't skip exercises that already have a non-rejected "
                         "proposal in the queue. Default behaviour skips them so re-runs are cheap.")
    ap.add_argument("--concurrency", type=int, default=DEFAULT_CONCURRENCY,
                    help=f"(dry-run only) Concurrent edge fn calls. Default: {DEFAULT_CONCURRENCY}.")
    ap.add_argument("--confirm", action="store_true",
                    help="Prompt for y/N confirmation before starting (recommended for full sweeps).")

    # Apply-phase staging — lets the operator land safe corrections first.
    ap.add_argument(
        "--stage", choices=STAGE_CHOICES, default="all",
        help="(apply only) Restrict to one bucket of proposals. "
             "caps=equipment_category capitalization (safest); "
             "sister=evidence references a sister exercise (sister-gate likely); "
             "rest=everything else (name-gate / multi-report / human review); "
             "all=no filter. Default: all.",
    )
    ap.add_argument(
        "--stage-stats", action="store_true",
        help="(apply only) Print per-stage proposal counts and exit WITHOUT writing. "
             "Useful for sizing each stage before committing.",
    )
    ap.add_argument(
        "--max-apply", type=int, default=None,
        help="(apply only) Cap the total proposals applied this run. Combine with --stage "
             "to land a small test batch before going wider.",
    )
    args = ap.parse_args()

    if args.apply and args.dry_run:
        ap.error("--dry-run and --apply are mutually exclusive")
    if not args.apply and not args.dry_run:
        # Default to dry-run for safety.
        args.dry_run = True

    if args.dry_run:
        return run_dry_run(args)
    return run_apply(args)


if __name__ == "__main__":
    sys.exit(main())
