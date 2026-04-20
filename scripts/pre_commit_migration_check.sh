#!/bin/bash
# Sprint 4 (AGD-9) — Migration index drift guard.
#
# Fails a commit when any staged supabase/*.sql file is not listed in
# supabase/MIGRATION_INDEX.md. MIGRATION_INDEX.md is the canonical source
# of truth for schema changes; every migration MUST be registered there
# with a human-readable description so we can audit drift retroactively.
#
# Installation (opt-in):
#   git config core.hooksPath .githooks
#
# See .githooks/pre-commit for the wire-up.

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
INDEX_FILE="${REPO_ROOT}/supabase/MIGRATION_INDEX.md"

if [[ ! -f "${INDEX_FILE}" ]]; then
    echo "pre-commit: MIGRATION_INDEX.md not found at ${INDEX_FILE}; skipping check." >&2
    exit 0
fi

STAGED_MIGRATIONS=$(git diff --cached --name-only --diff-filter=A \
    | grep -E '^supabase/[^/]+\.sql$' || true)

if [[ -z "${STAGED_MIGRATIONS}" ]]; then
    exit 0
fi

MISSING=()
while IFS= read -r path; do
    [[ -z "${path}" ]] && continue
    basename="${path##*/}"
    if ! grep -qF "${basename}" "${INDEX_FILE}"; then
        MISSING+=("${basename}")
    fi
done <<< "${STAGED_MIGRATIONS}"

if (( ${#MISSING[@]} > 0 )); then
    echo "" >&2
    echo "✗ pre-commit: migration files are staged but missing from supabase/MIGRATION_INDEX.md:" >&2
    for f in "${MISSING[@]}"; do
        echo "    - ${f}" >&2
    done
    echo "" >&2
    echo "  Add each file as a new row under 'Deployed Migrations' with a" >&2
    echo "  one-line description of what it does, then re-run git commit." >&2
    echo "  (Or bypass this check with git commit --no-verify for emergency merges.)" >&2
    echo "" >&2
    exit 1
fi

exit 0
