#!/usr/bin/env python3
"""
classifier_lint.py — Enforce QUALITY_PERFORMANCE_AGENT.md invariant 25a.

INVARIANT
---------
Every Supabase-touching `catch` block in `Fit33/**/*.swift` MUST route the error
through `NetworkErrorClassifier.log(...)` instead of calling `AppLogger.error`
directly. Skipping the classifier means transient NSURLError / cancelled / auth
errors land at `.error` level, which fingerprint into bug intelligence reports
and produce false signal (Clusters D / E / F / G in the 2026-04-23 bug-intel
report were all caused by this).

WHAT THIS LINT CATCHES
----------------------
For each Swift file that touches Supabase (imports `Supabase`, references
`SupabaseManager`, or calls `.rpc(`), it:
  1. Walks every `catch { ... }` block top-to-bottom by counting braces.
  2. If the block body contains `AppLogger.error` or `AppLogger.critical`
     but does NOT contain `NetworkErrorClassifier` anywhere, reports a
     violation with the file:line of the catch.
  3. Skips `catch` blocks that explicitly suppress via the inline marker
     `// classifier_lint:allow` (for the rare legit case — e.g. logging
     before a classifier is even available, like bootstrap code).

OUTPUT
------
Clang-style diagnostic lines on stdout (one per violation). Exit 0 always when
invoked with `--warn` (default); exit 1 when invoked with `--strict` (CI).

USAGE
-----
  python3 scripts/classifier_lint.py            # warn mode (default)
  python3 scripts/classifier_lint.py --strict   # fail on any violation (CI)
  python3 scripts/classifier_lint.py --json     # machine-readable output

The GitHub Actions job at .github/workflows/classifier-lint.yml runs this in
--warn mode on PRs touching Fit33/**/*.swift and surfaces violations as PR
comments via reviewdog or a simple `echo`-based annotation block.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from pathlib import Path
from typing import List, Tuple

REPO = Path(__file__).resolve().parent.parent
FIT33_DIR = REPO / "Fit33"

# Heuristic: a file "touches Supabase" if it contains any of these markers.
SUPABASE_MARKERS = (
    "import Supabase",
    "SupabaseManager",
    ".rpc(",
    "PostgrestError",
    "supabaseClient",
)

# AppLogger.error / .critical inside the catch block is the violation pattern.
# The classifier name we require is NetworkErrorClassifier.
VIOLATION_RE = re.compile(r"\bAppLogger\.(error|critical)\b")
CLASSIFIER_RE = re.compile(r"\bNetworkErrorClassifier\b")
CATCH_RE = re.compile(r"\bcatch\b[^{]*\{")
ALLOW_MARKER = "classifier_lint:allow"


def find_matching_brace(source: str, start: int) -> int:
    """Given an index at `{`, return the index of the matching `}` (or -1)."""
    depth = 0
    i = start
    in_str = False
    str_char = ""
    in_line_comment = False
    in_block_comment = False
    while i < len(source):
        c = source[i]
        nxt = source[i + 1] if i + 1 < len(source) else ""
        # Comment + string handling so braces inside them don't count.
        if in_line_comment:
            if c == "\n":
                in_line_comment = False
            i += 1
            continue
        if in_block_comment:
            if c == "*" and nxt == "/":
                in_block_comment = False
                i += 2
                continue
            i += 1
            continue
        if in_str:
            if c == "\\":
                i += 2
                continue
            if c == str_char:
                in_str = False
            i += 1
            continue
        if c == "/" and nxt == "/":
            in_line_comment = True
            i += 2
            continue
        if c == "/" and nxt == "*":
            in_block_comment = True
            i += 2
            continue
        if c in ('"', "'"):
            in_str = True
            str_char = c
            i += 1
            continue

        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                return i
        i += 1
    return -1


def line_of(source: str, index: int) -> int:
    return source.count("\n", 0, index) + 1


def lint_file(path: Path) -> List[Tuple[int, str]]:
    text = path.read_text(encoding="utf-8", errors="replace")
    if not any(marker in text for marker in SUPABASE_MARKERS):
        return []

    violations: List[Tuple[int, str]] = []
    for m in CATCH_RE.finditer(text):
        brace_idx = m.end() - 1  # index of the `{`
        end_idx = find_matching_brace(text, brace_idx)
        if end_idx == -1:
            continue
        block = text[brace_idx + 1 : end_idx]
        if ALLOW_MARKER in block:
            continue
        if VIOLATION_RE.search(block) and not CLASSIFIER_RE.search(block):
            violations.append(
                (
                    line_of(text, brace_idx),
                    "`AppLogger.error` / `AppLogger.critical` in a Supabase-touching "
                    "catch block without `NetworkErrorClassifier.log(...)`. "
                    "This violates QUALITY_PERFORMANCE_AGENT invariant 25a — "
                    "route the error through the classifier so transient "
                    "NSURLError / cancelled / auth errors don't create bug "
                    "intelligence fingerprints. See Fit33/NetworkErrorClassifier.swift. "
                    "Suppress with `// classifier_lint:allow` ONLY when the classifier "
                    "is provably unavailable (e.g. bootstrap code before auth).",
                )
            )
    return violations


def iter_swift_files(root: Path):
    for dirpath, dirnames, filenames in os.walk(root):
        # Respect common skip dirs.
        dirnames[:] = [d for d in dirnames if d not in (".build", "DerivedData", "Pods")]
        for name in filenames:
            if name.endswith(".swift"):
                yield Path(dirpath) / name


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--strict", action="store_true", help="Exit 1 on any violation")
    ap.add_argument("--json", action="store_true", help="Emit JSON instead of diagnostics")
    ap.add_argument("--root", default=str(FIT33_DIR), help="Swift source root to scan")
    args = ap.parse_args()

    root = Path(args.root)
    if not root.exists():
        print(f"classifier_lint: source root not found: {root}", file=sys.stderr)
        return 0

    all_violations: List[dict] = []
    for f in sorted(iter_swift_files(root)):
        for line, msg in lint_file(f):
            all_violations.append({"file": str(f.relative_to(REPO)), "line": line, "message": msg})

    if args.json:
        print(json.dumps({"count": len(all_violations), "violations": all_violations}, indent=2))
    else:
        for v in all_violations:
            # Clang-style so Xcode / GH Actions problem-matchers pick it up.
            print(f"{v['file']}:{v['line']}: warning: [CLASSIFIER LINT] {v['message']}")
        print(
            f"[CLASSIFIER LINT] {len(all_violations)} violation"
            f"{'' if len(all_violations) == 1 else 's'} "
            f"in {root.relative_to(REPO)}.",
            file=sys.stderr,
        )

    if args.strict and all_violations:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
