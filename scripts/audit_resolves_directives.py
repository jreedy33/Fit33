#!/usr/bin/env python3
"""
audit_resolves_directives.py — Verify `Resolves: <fingerprint>` directives in
`supabase/*.sql` migrations actually drained the fingerprints they claimed.

PROBLEM
-------
Migrations frequently include `-- Resolves: <fp> ...` directives in their
header comments. The convention is informal — there's no enforcement that
the claim is true. After a migration deploys, a few categories of drift
silently appear:

  (a) The fingerprint is still `status='pending'` — the migration shipped
      but its UPDATE branch missed this row (typo, missing condition, etc.).
  (b) The fingerprint doesn't exist in the DB at all — the directive
      references a stale or mistyped fingerprint hash.
  (c) The fingerprint was resolved with an *unrelated* reason (e.g. the
      single-incident transient autoresolver fired before the migration
      ran, so the audit trail says "transient_single_incident" instead of
      the migration's intended `code_fix:*` reason). Cosmetic but
      distorts the silent-fix counter.

This audit surfaces all three categories so an operator can:
  * Fix the migration (add missed UPDATE rows)
  * Fix the directive (correct the hash)
  * Re-stamp the auto_resolved_reason if the FP was already drained for an
    unrelated reason (preserve provenance)

OUTPUT
------
Plain text by default; `--json` for machine-readable. Exit 0 when zero drift,
exit 1 when drift exists (so CI / pre-deploy can gate on it).

USAGE
-----
  # All migrations under supabase/ (default)
  python3 scripts/audit_resolves_directives.py

  # A single migration file
  python3 scripts/audit_resolves_directives.py --migration supabase/20260504_bug_intel_inbox_drain.sql

  # Only directives in the last N days
  python3 scripts/audit_resolves_directives.py --since 7

  # CI-mode: fail on any drift
  python3 scripts/audit_resolves_directives.py --strict

ENVIRONMENT
-----------
Requires SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY in env (or .env).

DESIGN NOTES
------------
The fingerprint is the canonical key on bug_intelligence_fingerprints. We
chunk the IN-clause queries to fit Supabase's URL length limits (PostgREST
has a ~6 KB query string ceiling — 50 fingerprints per batch comfortably
under).
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import urllib.parse
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Dict, List, Optional, Tuple

REPO = Path(__file__).resolve().parent.parent
MIGRATIONS_DIR = REPO / "supabase"

# Match `-- Resolves: <fingerprint> <free-text description>`. We tolerate
# leading whitespace, optional `*` (block comment), `Resolves` either as
# the first token or after a tag like `Status` / `Closes`. The fingerprint
# is canonically a 32-char hex string (md5).
DIRECTIVE_RE = re.compile(
    r"^[\s\-*/]*Resolves:\s*([a-f0-9]{32})(?:\s+(.*))?$",
    re.IGNORECASE | re.MULTILINE,
)

# Migration filename → date for the --since filter. Format is
# `YYYYMMDD_*.sql` for date-prefixed migrations.
DATE_RE = re.compile(r"^(\d{8})_")


def load_env() -> Tuple[str, str]:
    url = os.environ.get("SUPABASE_URL")
    key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY")
    if not (url and key):
        # Fall back to .env file in the repo root.
        env_path = REPO / ".env"
        if env_path.exists():
            for line in env_path.read_text().splitlines():
                if line.startswith("SUPABASE_URL=") and not url:
                    url = line.split("=", 1)[1].strip().strip('"')
                if line.startswith("SUPABASE_SERVICE_ROLE_KEY=") and not key:
                    key = line.split("=", 1)[1].strip().strip('"')
    if not (url and key):
        print(
            "audit_resolves_directives: missing SUPABASE_URL or "
            "SUPABASE_SERVICE_ROLE_KEY in env / .env",
            file=sys.stderr,
        )
        sys.exit(2)
    return url, key


def parse_directives(migration_path: Path) -> List[Dict]:
    text = migration_path.read_text(encoding="utf-8", errors="replace")
    out = []
    for m in DIRECTIVE_RE.finditer(text):
        fingerprint = m.group(1).lower()
        desc = (m.group(2) or "").strip()
        line_no = text.count("\n", 0, m.start()) + 1
        out.append(
            {
                "fingerprint": fingerprint,
                "description": desc,
                "migration": migration_path.name,
                "line": line_no,
            }
        )
    return out


def collect_directives(
    only_migration: Optional[Path] = None,
    since_days: Optional[int] = None,
) -> List[Dict]:
    files: List[Path]
    if only_migration:
        files = [only_migration]
    else:
        files = sorted(MIGRATIONS_DIR.glob("*.sql"))

    if since_days is not None:
        cutoff = datetime.now(tz=timezone.utc) - timedelta(days=since_days)
        kept: List[Path] = []
        for f in files:
            m = DATE_RE.match(f.name)
            if not m:
                continue
            try:
                dt = datetime.strptime(m.group(1), "%Y%m%d").replace(tzinfo=timezone.utc)
            except ValueError:
                continue
            if dt >= cutoff:
                kept.append(f)
        files = kept

    all_directives: List[Dict] = []
    for f in files:
        all_directives.extend(parse_directives(f))
    return all_directives


def _curl_get(url: str, key: str) -> Optional[List[Dict]]:
    """Run a curl GET against PostgREST and return parsed JSON list (or None
    on error). We use curl instead of urllib because Python's default SSL
    context fails cert verification on some macOS LibreSSL toolchains."""
    try:
        res = subprocess.run(
            [
                "curl",
                "-sS",
                "--max-time",
                "30",
                "-H",
                f"apikey: {key}",
                "-H",
                f"Authorization: Bearer {key}",
                url,
            ],
            capture_output=True,
            text=True,
            check=False,
        )
        if res.returncode != 0 or not res.stdout.strip():
            print(
                f"audit_resolves_directives: curl error: rc={res.returncode} "
                f"stderr={res.stderr.strip()}",
                file=sys.stderr,
            )
            return None
        rows = json.loads(res.stdout)
        if isinstance(rows, dict) and "code" in rows:
            print(f"audit_resolves_directives: API error: {rows}", file=sys.stderr)
            return None
        return rows
    except (subprocess.SubprocessError, json.JSONDecodeError) as e:
        print(f"audit_resolves_directives: error: {e}", file=sys.stderr)
        return None


def fetch_fingerprints(
    url: str,
    key: str,
    fingerprints: List[str],
) -> Tuple[Dict[str, Dict], Dict[str, Dict]]:
    """Bulk-fetch FP rows from BOTH `bug_intelligence_fingerprints` (live)
    and `bug_intel_resolved_history` (archive). PostgREST has a ~6 KB URL
    ceiling, so we batch 50 fingerprints per query.

    Returns (live_rows, history_rows) keyed by fingerprint. The caller
    consults live first, then falls back to history before declaring a
    fingerprint "not_found" — many directives correctly drained the FP
    but the rollup later archived it out of the live table.
    """
    if not fingerprints:
        return {}, {}

    live: Dict[str, Dict] = {}
    history: Dict[str, Dict] = {}
    BATCH = 50

    for i in range(0, len(fingerprints), BATCH):
        batch = fingerprints[i : i + BATCH]
        q = urllib.parse.quote(",".join(batch))

        live_url = (
            f"{url}/rest/v1/bug_intelligence_fingerprints"
            f"?select=fingerprint,status,auto_resolved_reason,"
            f"resolved_at,last_seen_at,occurrence_count,error_class,"
            f"sample_message"
            f"&fingerprint=in.({q})"
        )
        live_rows = _curl_get(live_url, key) or []
        for row in live_rows:
            live[row["fingerprint"]] = row

        history_url = (
            f"{url}/rest/v1/bug_intel_resolved_history"
            f"?select=fingerprint,resolved_status,auto_resolved_reason,"
            f"resolved_at,error_class,summary"
            f"&fingerprint=in.({q})"
        )
        history_rows = _curl_get(history_url, key) or []
        for row in history_rows:
            history[row["fingerprint"]] = row

    return live, history


def classify(
    directive: Dict,
    live_row: Optional[Dict],
    history_row: Optional[Dict],
) -> Tuple[str, str]:
    """Returns (drift_kind, summary). drift_kind in:
    {ok, not_found, still_open, drained_by_other_reason, archived_ok}.

    Resolution order:
      1. live_row exists + status='resolved'         → ok / drained_by_other_reason
      2. live_row exists + status not resolved       → still_open
      3. history_row exists                           → archived_ok (the rollup
         archived this FP — drainage succeeded earlier)
      4. neither                                      → not_found (typo / stale)
    """
    desc_lower = (directive.get("description") or "").lower()
    intended_family = None
    if "classifier_routing" in desc_lower:
        intended_family = "code_fix:classifier_routing"
    elif "warning_downgrade" in desc_lower:
        intended_family = "code_fix:warning_downgrade"
    elif "migration_resolved" in desc_lower:
        intended_family = "migration_resolved"
    elif "silent_fix" in desc_lower:
        intended_family = "silent_fix"
    elif "code_fix" in desc_lower:
        intended_family = "code_fix"

    if live_row is not None:
        status = live_row.get("status") or "unknown"
        reason = live_row.get("auto_resolved_reason") or ""

        if status not in ("resolved", "wont_fix", "duplicate"):
            return (
                "still_open",
                f"status={status} (claim says resolved but FP is open) "
                f"last_seen={(live_row.get('last_seen_at') or '')[:10] or 'n/a'} "
                f"occ={live_row.get('occurrence_count') or 0}",
            )

        if intended_family is None or reason.startswith(intended_family):
            return ("ok", f"resolved with reason={reason or '<unset>'}")

        return (
            "drained_by_other_reason",
            f"resolved but reason={reason or '<unset>'} "
            f"(directive expected {intended_family})",
        )

    if history_row is not None:
        reason = history_row.get("auto_resolved_reason") or ""
        # Archived: FP was drained earlier and the rollup moved it to
        # bug_intel_resolved_history. This is the happy path for older
        # directives — count as ok unless the reason families mismatch.
        if intended_family is None or reason.startswith(intended_family):
            return (
                "archived_ok",
                f"archived to bug_intel_resolved_history with reason={reason or '<unset>'}",
            )
        return (
            "drained_by_other_reason",
            f"archived but reason={reason or '<unset>'} "
            f"(directive expected {intended_family})",
        )

    return ("not_found", "fingerprint not in fingerprints OR resolved_history")


def render_text(report: Dict) -> str:
    lines = []
    lines.append(
        f"Resolves: directive audit — scanned {report['scanned_migrations']} migration(s), "
        f"{report['total_directives']} directives, {report['total_fps_unique']} unique FPs"
    )
    if report["since_days"] is not None:
        lines.append(f"  scope: last {report['since_days']} days")
    lines.append(
        f"  ok: {report['by_kind']['ok']}  "
        f"archived_ok: {report['by_kind']['archived_ok']}  "
        f"still_open: {report['by_kind']['still_open']}  "
        f"not_found: {report['by_kind']['not_found']}  "
        f"drained_by_other_reason: {report['by_kind']['drained_by_other_reason']}"
    )
    lines.append("")

    drifts = [
        d for d in report["entries"]
        if d["drift_kind"] not in ("ok", "archived_ok")
    ]
    if not drifts:
        lines.append("  ✓ no drift detected — every Resolves: directive landed.")
        return "\n".join(lines)

    by_kind: Dict[str, List[Dict]] = {}
    for d in drifts:
        by_kind.setdefault(d["drift_kind"], []).append(d)

    for kind in ("still_open", "not_found", "drained_by_other_reason"):
        bucket = by_kind.get(kind, [])
        if not bucket:
            continue
        lines.append(
            f"\n=== {kind} ({len(bucket)}) ==="
            + (
                " — operator action required: directive shipped but FP is still open"
                if kind == "still_open"
                else " — directive references a non-existent FP (typo or stale)"
                if kind == "not_found"
                else " — cosmetic: drained earlier by another resolver"
            )
        )
        for d in bucket:
            lines.append(
                f"  {d['migration']}:{d['line']}  fp={d['fingerprint'][:12]}…  "
                f"{d['summary']}\n    desc={d['description'][:120]}"
            )

    return "\n".join(lines)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument(
        "--migration",
        type=str,
        default=None,
        help="Audit a single migration file instead of all under supabase/",
    )
    ap.add_argument(
        "--since",
        type=int,
        default=None,
        help="Only audit migrations dated within the last N days",
    )
    ap.add_argument(
        "--strict",
        action="store_true",
        help="Exit 1 on any drift (CI / pre-deploy gate)",
    )
    ap.add_argument(
        "--existence-only",
        action="store_true",
        help="Only verify each FP exists in DB (typo check). Suitable for "
             "pre-commit hooks before the migration has deployed. Suppresses "
             "still_open + drained_by_other_reason classifications.",
    )
    ap.add_argument(
        "--quiet-when-clean",
        action="store_true",
        help="Print nothing when there is no drift (pre-commit ergonomics).",
    )
    ap.add_argument("--json", action="store_true", help="Emit JSON instead of text")
    args = ap.parse_args()

    only_migration = None
    if args.migration:
        only_migration = (REPO / args.migration).resolve()
        if not only_migration.exists():
            print(f"audit_resolves_directives: migration not found: {only_migration}", file=sys.stderr)
            return 2

    directives = collect_directives(only_migration=only_migration, since_days=args.since)
    if not directives:
        print("audit_resolves_directives: no Resolves: directives found in scope.")
        return 0

    url, key = load_env()
    unique_fps = sorted({d["fingerprint"] for d in directives})
    live, history = fetch_fingerprints(url, key, unique_fps)

    by_kind = {
        "ok": 0,
        "archived_ok": 0,
        "not_found": 0,
        "still_open": 0,
        "drained_by_other_reason": 0,
    }
    entries: List[Dict] = []
    for d in directives:
        live_row = live.get(d["fingerprint"])
        history_row = history.get(d["fingerprint"])
        kind, summary = classify(d, live_row, history_row)

        # In existence-only mode (pre-commit), reclassify "still_open" and
        # "drained_by_other_reason" as ok — those are valid pre-deploy
        # states. Only "not_found" remains as a meaningful signal (typo).
        if args.existence_only and kind in ("still_open", "drained_by_other_reason"):
            kind = "ok"
            summary = "exists in DB (existence-only mode skips status check)"

        by_kind[kind] += 1
        entries.append({**d, "drift_kind": kind, "summary": summary})

    scanned_migrations = len({d["migration"] for d in directives})
    report = {
        "scanned_migrations": scanned_migrations,
        "total_directives": len(directives),
        "total_fps_unique": len(unique_fps),
        "since_days": args.since,
        "by_kind": by_kind,
        "entries": entries,
    }

    has_drift = (
        by_kind["still_open"] > 0
        or by_kind["not_found"] > 0
    )

    if args.json:
        print(json.dumps(report, indent=2))
    elif args.quiet_when_clean and not has_drift:
        pass
    else:
        print(render_text(report))

    if args.strict and has_drift:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
