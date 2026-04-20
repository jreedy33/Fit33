#!/bin/bash
# Sprint 4 (AGD-8) — Stale DONE-claim auditor.
#
# Parses MASTER_TODO.md and validates every row marked `[x]` (done) that
# cites file paths in its "File" column. Any path that no longer exists in
# the working tree is reported so we can fix drift after moves/renames.
#
# Usage:
#   ./scripts/audit_done_claims.sh                  # report against HEAD
#   ./scripts/audit_done_claims.sh --fail-on-drift  # exit 1 if any missing

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
TODO_FILE="${REPO_ROOT}/MASTER_TODO.md"
FAIL_ON_DRIFT=0

for arg in "$@"; do
    case "$arg" in
        --fail-on-drift) FAIL_ON_DRIFT=1 ;;
        *) echo "unknown flag: $arg" >&2; exit 2 ;;
    esac
done

if [[ ! -f "${TODO_FILE}" ]]; then
    echo "audit_done_claims: MASTER_TODO.md not found at ${TODO_FILE}" >&2
    exit 2
fi

# Read MASTER_TODO.md with python for robust parsing. The alternative (awk) is
# fragile because file paths may contain hyphens, slashes, line ranges, and
# multiple comma-separated values per cell.
python3 - "${TODO_FILE}" "${REPO_ROOT}" "${FAIL_ON_DRIFT}" <<'PY'
import os
import re
import sys

todo_path, repo_root, fail_on_drift = sys.argv[1], sys.argv[2], sys.argv[3] == "1"

# Path cell tokens we ignore — descriptive shorthands, not real files.
SKIP_TOKENS = {
    "n/a", "na", "—", "-", "", "tbd", "various", "multiple",
    "throughout", "codebase-wide", "widespread",
}

# A token is a "candidate path" only if it looks like one. Must contain a
# slash or a known file extension suffix.
PATH_HINT = re.compile(r"(/|\.(swift|sql|ts|tsx|js|jsx|md|py|sh|plist|xcscheme|pbxproj|json|xcconfig))$", re.IGNORECASE)

# Strip trailing `:123`, `:123-456`, `#Lxxx` line references.
LINE_REF = re.compile(r"[:#][0-9]+(?:-[0-9]+)?$")

missing = []   # (row_id, path)
checked = 0
done_rows = 0

with open(todo_path, "r", encoding="utf-8") as fh:
    for line in fh:
        if "[x]" not in line:
            continue
        if not line.lstrip().startswith("|"):
            continue
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cells) < 3:
            continue
        if "[x]" not in cells[1]:
            continue
        done_rows += 1
        row_id = cells[0]
        path_cell = cells[2]

        # Split file cell by commas and by backticks; tolerate either.
        candidates = re.split(r"[,]", path_cell)
        for tok in candidates:
            tok = tok.strip().strip("`").strip("*").strip()
            # Strip surrounding brackets/parens left over from markdown.
            tok = tok.strip("[](){}")
            # Drop line references.
            tok = LINE_REF.sub("", tok)
            if tok.lower() in SKIP_TOKENS:
                continue
            if not tok:
                continue
            if not PATH_HINT.search(tok):
                continue
            checked += 1
            abs_path = os.path.join(repo_root, tok)
            if not os.path.exists(abs_path):
                missing.append((row_id, tok))

print(f"Scanned {done_rows} done ([x]) rows; checked {checked} cited paths.")
if missing:
    print(f"\nFound {len(missing)} stale path reference(s):")
    for row_id, path in missing:
        print(f"  - row {row_id}: {path}")
    print("\nFix each row by updating the File column to the current location,")
    print("or mark the row with a follow-up note if the file was intentionally removed.")
    if fail_on_drift:
        sys.exit(1)
else:
    print("No stale path references found.")
PY
