#!/usr/bin/env python3
"""
diff_audit_reports.py
=====================

Diff two autogen audit reports (`scripts/output/autogen_audit_*.md`) and
print a structured markdown delta. Useful for confirming "did the latest
sprint of autogen fixes actually move the needle?" without eyeballing two
3000-line reports side by side.

The diff is purely additive — no DB writes, no edits. Reads BASELINE and
CANDIDATE .md, parses the same headline / category / verdict tables the
audit emits, and prints:

  - Average overall rating Δ
  - Verdicts mix Δ (counts + percent)
  - Issue severity Δ (critical / major / minor)
  - Issue category Δ — top movers (largest absolute change first)
  - Verdict transitions (workouts that moved up / down brackets) — best
    available given the .md isn't keyed by user-id; we approximate via
    the top-fixes table.

USAGE
-----
    # baseline-first, candidate-second
    python scripts/diff_audit_reports.py \\
        scripts/output/autogen_audit_<R9_TS>.md \\
        scripts/output/autogen_audit_<R10_TS>.md

    # write to a file for committing alongside the candidate report
    python scripts/diff_audit_reports.py BASELINE.md CANDIDATE.md \\
        --output scripts/output/audit_delta_<TS>.md

The intent is "30-second triage": did the round shift the average up
by enough to keep iterating, did it regress in any category, and are
there issue categories the latest fix-batch did NOT touch that are now
the top issue (i.e. the next thing to fix).
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path
from typing import Iterable

# ─── parse primitives ───────────────────────────────────────────────────────

RATING_RE = re.compile(r"\*\*Average overall rating\*\*[^*:]*:\s*\*\*([\d.]+)\*\*")
VERDICTS_RE = re.compile(r"\*\*Verdicts\*\*:\s*(.+?)$", re.MULTILINE)
SEVERITY_RE = re.compile(r"\*\*Issue severity\*\*:\s*(.+?)$", re.MULTILINE)
WORKOUTS_GEN_RE = re.compile(r"=\s+\*\*(\d+)\s+workouts\*\*")
WALL_CLOCK_RE = re.compile(r"·\s*([\d.]+)s\s+wall-clock")
CAT_TABLE_HEADER_RE = re.compile(r"^##\s+Issue Categories\s*$")
CAT_ROW_RE = re.compile(r"^\|\s*([a-z_]+)\s*\|\s*(\d+)\s*\|\s*$")

# Top fixes table — first column is rank, second is frequency, fourth is
# priority, fifth is title.
FIXES_HEADER_RE = re.compile(r"^##\s+Top Fixes")
FIXES_ROW_RE = re.compile(
    r"^\|\s*(\d+)\s*\|\s*(\d+)\s*\|\s*([a-z_]+)\s*\|\s*(\w+)\s*\|\s*([^|]+?)\s*\|"
)


def _parse_pairs(line: str) -> dict[str, int]:
    """Parse 'minor_revision: 26 · reject: 17 · ship: 1 · significant_revision: 56'.
    Returns {key: int}.
    """
    out: dict[str, int] = {}
    parts = [p.strip() for p in line.split("·")]
    for p in parts:
        if ":" not in p:
            continue
        k, _, v = p.partition(":")
        try:
            out[k.strip()] = int(v.strip())
        except ValueError:
            continue
    return out


def _parse_issue_categories(lines: list[str]) -> dict[str, int]:
    out: dict[str, int] = {}
    in_table = False
    for line in lines:
        if CAT_TABLE_HEADER_RE.match(line):
            in_table = True
            continue
        if in_table:
            m = CAT_ROW_RE.match(line)
            if m:
                out[m.group(1)] = int(m.group(2))
            elif line.startswith("##"):
                break
    return out


def _parse_top_fixes(lines: list[str]) -> dict[str, int]:
    """Returns {title: frequency}. Title-keyed because the table has the
    title verbatim — same fix in two rounds gives us a stable join key.
    """
    out: dict[str, int] = {}
    in_table = False
    for line in lines:
        if FIXES_HEADER_RE.match(line):
            in_table = True
            continue
        if in_table:
            m = FIXES_ROW_RE.match(line)
            if m:
                title = m.group(5).strip().rstrip(" |")
                try:
                    out[title] = int(m.group(2))
                except ValueError:
                    continue
            elif line.startswith("##") and "Top Fixes" not in line:
                break
    return out


def parse_report(path: Path) -> dict:
    """Pull all the headline metrics from a single audit report."""
    text = path.read_text(encoding="utf-8")
    lines = text.splitlines()
    rating_m = RATING_RE.search(text)
    verdicts_m = VERDICTS_RE.search(text)
    severity_m = SEVERITY_RE.search(text)
    workouts_m = WORKOUTS_GEN_RE.search(text)
    wallclock_m = WALL_CLOCK_RE.search(text)
    return {
        "path": str(path),
        "rating": float(rating_m.group(1)) if rating_m else None,
        "verdicts": _parse_pairs(verdicts_m.group(1)) if verdicts_m else {},
        "severity": _parse_pairs(severity_m.group(1)) if severity_m else {},
        "workouts": int(workouts_m.group(1)) if workouts_m else None,
        "wallclock_s": float(wallclock_m.group(1)) if wallclock_m else None,
        "categories": _parse_issue_categories(lines),
        "top_fixes": _parse_top_fixes(lines),
    }


# ─── delta rendering ────────────────────────────────────────────────────────

def _fmt_int_delta(a: int, b: int) -> str:
    delta = b - a
    if delta == 0:
        return f"{a}→{b}  (= )"
    arrow = "↑" if delta > 0 else "↓"
    return f"{a}→{b}  ({arrow}{abs(delta)})"


def _fmt_rate_delta(a: float | None, b: float | None) -> str:
    if a is None or b is None:
        return f"{a}→{b}"
    delta = b - a
    arrow = "↑" if delta > 0 else ("↓" if delta < 0 else "=")
    return f"{a:.2f} → {b:.2f}  ({arrow}{abs(delta):.2f})"


def _key_union(*dicts: dict[str, int]) -> list[str]:
    s: set[str] = set()
    for d in dicts:
        s.update(d.keys())
    return sorted(s)


def render_diff(baseline: dict, candidate: dict, max_movers: int = 12) -> str:
    out: list[str] = []
    out.append(
        f"# Audit delta — {Path(baseline['path']).name} → {Path(candidate['path']).name}\n"
    )

    # ── Headline ──
    out.append("## Headline\n")
    out.append(
        f"- **Average rating**: {_fmt_rate_delta(baseline['rating'], candidate['rating'])}"
    )
    out.append(
        f"- **Workouts**: baseline={baseline['workouts']} candidate={candidate['workouts']}"
    )
    if baseline["wallclock_s"] and candidate["wallclock_s"]:
        out.append(
            f"- **Wall-clock**: baseline={baseline['wallclock_s']:.0f}s "
            f"candidate={candidate['wallclock_s']:.0f}s"
        )
    out.append("")

    # ── Verdicts ──
    out.append("## Verdicts\n")
    out.append("| Verdict | Baseline | Candidate | Δ |")
    out.append("|---|---|---|---|")
    for k in _key_union(baseline["verdicts"], candidate["verdicts"]):
        a = baseline["verdicts"].get(k, 0)
        b = candidate["verdicts"].get(k, 0)
        out.append(f"| {k} | {a} | {b} | {_fmt_int_delta(a, b)} |")
    out.append("")

    # ── Issue severity ──
    out.append("## Issue severity\n")
    out.append("| Severity | Baseline | Candidate | Δ |")
    out.append("|---|---|---|---|")
    for k in ("critical", "major", "minor"):
        a = baseline["severity"].get(k, 0)
        b = candidate["severity"].get(k, 0)
        out.append(f"| {k} | {a} | {b} | {_fmt_int_delta(a, b)} |")
    out.append("")

    # ── Issue categories (movers) ──
    out.append("## Issue categories — biggest movers (by |Δ|)\n")
    rows: list[tuple[str, int, int, int]] = []
    for k in _key_union(baseline["categories"], candidate["categories"]):
        a = baseline["categories"].get(k, 0)
        b = candidate["categories"].get(k, 0)
        rows.append((k, a, b, b - a))
    rows.sort(key=lambda r: abs(r[3]), reverse=True)
    out.append("| Category | Baseline | Candidate | Δ |")
    out.append("|---|---|---|---|")
    for k, a, b, d in rows[:max_movers]:
        arrow = "↑" if d > 0 else ("↓" if d < 0 else "=")
        out.append(f"| {k} | {a} | {b} | {arrow}{abs(d)} |")
    out.append("")

    # ── Top fixes — newly appearing / dropping off ──
    out.append("## Top fixes — set diff\n")
    base_titles = set(baseline["top_fixes"].keys())
    cand_titles = set(candidate["top_fixes"].keys())
    new_in_cand = sorted(cand_titles - base_titles)
    dropped = sorted(base_titles - cand_titles)
    out.append(
        f"- **New top-fix titles in candidate** ({len(new_in_cand)}): the "
        "fixes the candidate round is asking for but baseline didn't"
    )
    if new_in_cand:
        for t in new_in_cand:
            out.append(f"  - {t}  (freq={candidate['top_fixes'][t]})")
    else:
        out.append("  - (none)")
    out.append("")
    out.append(
        f"- **Dropped top-fix titles** ({len(dropped)}): the fixes baseline "
        "was asking for that the candidate round no longer surfaces — "
        "(strong signal: these areas IMPROVED)"
    )
    if dropped:
        for t in dropped:
            out.append(f"  - {t}  (freq={baseline['top_fixes'][t]})")
    else:
        out.append("  - (none)")
    out.append("")

    # ── Triage hint ──
    rating_delta = (
        (candidate["rating"] or 0.0) - (baseline["rating"] or 0.0)
        if baseline["rating"] is not None and candidate["rating"] is not None
        else 0.0
    )
    out.append("## 30-second triage\n")
    if rating_delta > 0.25:
        verdict = "✅ Material improvement — keep iterating this direction."
    elif rating_delta > 0.05:
        verdict = "🟡 Small improvement — confirm with a follow-up round before assuming signal."
    elif rating_delta > -0.05:
        verdict = "⚪ Flat — fixes didn't move headline rating; check category diffs for hidden wins."
    elif rating_delta > -0.25:
        verdict = "🟠 Small regression — investigate which fix introduced new flagging."
    else:
        verdict = "🔴 Material regression — revert the latest sprint."
    out.append(f"**Rating Δ = {rating_delta:+.2f}** → {verdict}")
    out.append("")
    out.append(
        "Next action: pull the top mover-up category, cross-reference against this "
        "round's `Top fixes` table to find the concrete change, and decide whether "
        "to address it via (a) a Swift autogen-engine change OR (b) a targeted "
        "`scripts/audit_exercise_catalog.py --names-file` catalog cleanup."
    )

    return "\n".join(out) + "\n"


# ─── main ───────────────────────────────────────────────────────────────────

def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(
        description="Diff two autogen audit .md reports.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    ap.add_argument("baseline", help="Older / pre-fix audit report .md")
    ap.add_argument("candidate", help="Newer / post-fix audit report .md")
    ap.add_argument(
        "--output", default=None, metavar="PATH",
        help="Write delta markdown to this file. Default: stdout.",
    )
    ap.add_argument(
        "--max-movers", type=int, default=12,
        help="How many issue-category rows to print, ordered by |Δ|. Default: 12.",
    )
    args = ap.parse_args(argv)

    baseline_path = Path(args.baseline)
    candidate_path = Path(args.candidate)
    for p in (baseline_path, candidate_path):
        if not p.exists():
            print(f"ERROR: not found: {p}", file=sys.stderr)
            return 2

    baseline = parse_report(baseline_path)
    candidate = parse_report(candidate_path)
    delta_md = render_diff(baseline, candidate, max_movers=args.max_movers)

    if args.output:
        out_path = Path(args.output)
        out_path.parent.mkdir(parents=True, exist_ok=True)
        out_path.write_text(delta_md, encoding="utf-8")
        print(f"[wrote] {out_path}", file=sys.stderr)
    else:
        sys.stdout.write(delta_md)
    return 0


if __name__ == "__main__":
    sys.exit(main())
