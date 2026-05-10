#!/usr/bin/env python3
"""
extract_audit_rejections.py
===========================

Parse an autogen audit .md report (`scripts/output/autogen_audit_*.md`) and
emit a deduplicated, sorted list of exercise NAMES that warrant a targeted
catalog re-audit.

INTENT
------
The autogen audit (`scripts/autogen_audit_simulator.py`) walks 100-200
synthetic users through the real Swift autogen and asks Claude to rate each
workout 1-10 + classify issues. The resulting `.md` is a curated map of
which exercises Claude considers wrong/obscure/mislabeled FOR THE SPECIFIC
SLOT THEY WERE SERVED IN. That signal is much higher than a blind sweep of
the whole catalog.

This script extracts every exercise name that appeared in a workout matching
the selected severity filter, deduplicates, and emits one name per line on
stdout (or `--output FILE`). The output file plugs straight into:

    python scripts/audit_exercise_catalog.py --dry-run --names-file <FILE>

ACCURACY CHECKPOINTS
--------------------
- The .md uses a consistent format for the workout list:
      **Generated workout:**

        1. <Name> _(Equipment → Muscle)_
        1. <Name> _(Equipment → Muscle)_
  We strip ` _(...)_` and any leading numeric+dot+space.
- The .md also lists exercise names inside `### `user-X` · <Workout> (rating
  N/10)` headers — we read `(rating N/10)` to determine which severity
  bucket the workout falls into.
- Verdict comes from `**Verdict**: `<verdict>` — used by `--rejected-only`.
- We never rely on Claude's prose to pull a name (too noisy + paraphrased).
  Names come exclusively from the structured "Generated workout:" block.

The default mode is `--low-rated` (workouts rated < 5/10). That mirrors
the signal we trust most — high-rated workouts may still have minor catalog
issues but they're not load-bearing.

USAGE
-----
    # 1. Dry-run mode (writes to stdout, no file).
    python scripts/extract_audit_rejections.py \\
        scripts/output/autogen_audit_<TS>.md

    # 2. Write to a suspects.txt file the catalog auditor can ingest.
    python scripts/extract_audit_rejections.py \\
        scripts/output/autogen_audit_<TS>.md \\
        --output scripts/output/suspects_<TS>.txt

    # 3. Pull ALL named exercises in the report (every workout, not just
    #    low-rated). Maximally permissive — use only for full sweeps.
    python scripts/extract_audit_rejections.py \\
        scripts/output/autogen_audit_<TS>.md --all

    # 4. Tightest filter: only exercises from workouts whose verdict is
    #    'reject'. Highest-signal subset for emergency cleanup.
    python scripts/extract_audit_rejections.py \\
        scripts/output/autogen_audit_<TS>.md --rejected-only
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

# ─── parsing primitives ─────────────────────────────────────────────────────

# `### `user-1` · Push Day (rating 4/10)` or any variant with the trailing
# `(rating N/10)`. The block before is the workout-section header.
RATING_HEADER_RE = re.compile(
    r"^###\s+`?[^`\n]*`?[^()]*\(rating\s+(\d+)/10\)\s*$"
)

# `**Verdict**: `reject` — ...` — pulls the bare verdict word.
VERDICT_LINE_RE = re.compile(
    r"\*\*Verdict\*\*:\s*`?(\w+)`?"
)

# `  1. Side Step Pushdown _(Bodyweight → Triceps)_`. The leading number is
# always "1." because the report uses markdown's auto-numbering — same
# numeral repeats for every item.
GENERATED_LINE_RE = re.compile(
    r"^\s*\d+\.\s+(?P<name>.+?)\s+_\("
)

# `**Generated workout:**` is the section anchor.
GENERATED_HEADER_RE = re.compile(r"^\s*\*\*Generated workout:?\*\*\s*$", re.IGNORECASE)


def _normalize(name: str) -> str:
    """Trim + collapse whitespace. Preserves capitalization (the catalog
    is case-significant for some equipment_category values, but we match
    case-insensitively in the catalog auditor's --names-file path so we
    don't lowercase here).
    """
    return " ".join(name.split()).strip()


def _section_iter(text: str):
    """Yield (rating: int | None, verdict: str | None, workout_lines: list[str])
    for every workout section in the report.

    A "section" is the block between two `### ` rating headers. We need the
    rating to filter by severity AND the workout's exercise list to actually
    extract names.
    """
    lines = text.splitlines()
    current_rating: int | None = None
    current_verdict: str | None = None
    in_generated_block = False
    workout_lines: list[str] = []

    def flush():
        nonlocal current_rating, current_verdict, workout_lines, in_generated_block
        if workout_lines or current_rating is not None:
            yield_payload = (current_rating, current_verdict, list(workout_lines))
            workout_lines.clear()
            in_generated_block = False
            return yield_payload
        return None

    out: list[tuple[int | None, str | None, list[str]]] = []
    for raw in lines:
        rating_match = RATING_HEADER_RE.match(raw)
        if rating_match:
            # Start of a new section — flush the previous one.
            flushed = flush()
            if flushed is not None:
                out.append(flushed)
            current_rating = int(rating_match.group(1))
            current_verdict = None
            in_generated_block = False
            continue

        verdict_match = VERDICT_LINE_RE.search(raw)
        if verdict_match and current_verdict is None and current_rating is not None:
            current_verdict = verdict_match.group(1).lower()
            continue

        if GENERATED_HEADER_RE.match(raw):
            in_generated_block = True
            continue

        # Once inside the generated block, any non-list-shaped line ends it.
        if in_generated_block:
            ex_match = GENERATED_LINE_RE.match(raw)
            if ex_match:
                workout_lines.append(_normalize(ex_match.group("name")))
            elif raw.strip() == "":
                # Blank lines stay inside the block.
                continue
            elif raw.startswith("##") or raw.startswith("###"):
                in_generated_block = False

    # Flush the trailing section.
    if current_rating is not None or workout_lines:
        out.append((current_rating, current_verdict, list(workout_lines)))
    return out


# ─── filters ────────────────────────────────────────────────────────────────

def _passes_filter(
    rating: int | None,
    verdict: str | None,
    mode: str,
    rating_threshold: int,
) -> bool:
    if mode == "all":
        return True
    if mode == "rejected-only":
        return (verdict or "").lower() == "reject"
    # mode == "low-rated" (default)
    if rating is None:
        return False
    return rating < rating_threshold


# ─── main ───────────────────────────────────────────────────────────────────

def _build_arg_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        description="Extract exercise-name suspects from an autogen audit .md.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    p.add_argument("md_path", help="Path to autogen_audit_<TS>.md")
    group = p.add_mutually_exclusive_group()
    group.add_argument(
        "--low-rated", action="store_const", const="low-rated", dest="mode",
        help="(default) Exercises from workouts rated < --rating-threshold.",
    )
    group.add_argument(
        "--rejected-only", action="store_const", const="rejected-only", dest="mode",
        help="Exercises only from workouts with verdict='reject'.",
    )
    group.add_argument(
        "--all", action="store_const", const="all", dest="mode",
        help="Every exercise mentioned in any 'Generated workout:' block.",
    )
    p.add_argument(
        "--rating-threshold", type=int, default=5,
        help="(--low-rated only) Workouts rated strictly below this are kept. Default: 5.",
    )
    p.add_argument(
        "--output", default=None, metavar="PATH",
        help="Write suspects to this file (one name per line). Default: stdout.",
    )
    p.add_argument(
        "--stats", action="store_true",
        help="Print per-section stats to stderr alongside the suspect list.",
    )
    return p


def main(argv: list[str] | None = None) -> int:
    ap = _build_arg_parser()
    args = ap.parse_args(argv)
    mode = args.mode or "low-rated"

    md_path = Path(args.md_path)
    if not md_path.exists():
        print(f"ERROR: file not found: {md_path}", file=sys.stderr)
        return 2

    text = md_path.read_text(encoding="utf-8")
    sections = _section_iter(text)

    sections_kept = 0
    sections_total = 0
    suspects: set[str] = set()
    samples: list[tuple[int | None, str | None, int]] = []

    for rating, verdict, exercises in sections:
        sections_total += 1
        if _passes_filter(rating, verdict, mode, args.rating_threshold):
            sections_kept += 1
            for name in exercises:
                suspects.add(name)
            samples.append((rating, verdict, len(exercises)))

    if args.stats:
        print(
            f"[stats] mode={mode} sections_total={sections_total} "
            f"sections_kept={sections_kept} suspects_unique={len(suspects)}",
            file=sys.stderr,
        )
        if samples and sections_kept <= 12:
            for rating, verdict, n in samples:
                print(f"  · rating={rating} verdict={verdict} exercises={n}", file=sys.stderr)

    sorted_suspects = sorted(suspects, key=lambda s: s.lower())
    if args.output:
        out_path = Path(args.output)
        out_path.parent.mkdir(parents=True, exist_ok=True)
        with out_path.open("w", encoding="utf-8") as fh:
            fh.write(
                f"# Suspects extracted from {md_path.name}\n"
                f"# mode={mode} sections_total={sections_total} sections_kept={sections_kept}\n"
                f"# count={len(sorted_suspects)}\n"
            )
            for name in sorted_suspects:
                fh.write(name + "\n")
        print(f"[wrote] {out_path} ({len(sorted_suspects)} suspects)", file=sys.stderr)
    else:
        for name in sorted_suspects:
            print(name)
    return 0


if __name__ == "__main__":
    sys.exit(main())
