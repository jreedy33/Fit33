#!/usr/bin/env bash
#
# scripts/upload_dsym.sh — Q2-97 Phase 5.4
#
# Uploads the Fit33.app.dSYM from a freshly-archived build to the Fit33
# Supabase `dsyms` storage bucket and records a row in the `app_dsyms` table
# so the symbolicate-crashes GitHub Actions workflow (Phase 5.5) can find it
# by `binary_uuid` and use it to convert hex stack traces into real
# `file:line:function` locations for Claude triage.
#
# Two ways to invoke:
#
#   1. As an Xcode Archive post-action (recommended — see docs/DSYM_UPLOAD.md
#      for the one-time Scheme setup). Xcode exports ARCHIVE_PATH and the
#      script runs automatically every time you Product > Archive.
#
#   2. Manual CLI run: `scripts/upload_dsym.sh <path to .xcarchive>`
#
# Requirements (one-time):
#   - ~/.fit33/dsym-upload.env with:
#       SUPABASE_URL=https://<project>.supabase.co
#       SUPABASE_SERVICE_ROLE_KEY=eyJ...                (keep secret!)
#   - `jq` on PATH               (brew install jq)
#   - `zip`, `shasum`, `dwarfdump`, `/usr/libexec/PlistBuddy` (macOS stock)
#
# Exit codes:
#   0 = uploaded + DB row inserted (or idempotent no-op if already uploaded)
#   1 = misconfiguration (missing env, bad archive path, parse failure)
#   2 = network / Supabase API failure (re-runnable)

set -euo pipefail

# ─── 1. Config ────────────────────────────────────────────────────────────
CONFIG_FILE="${FIT33_DSYM_CONFIG:-$HOME/.fit33/dsym-upload.env}"
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "[upload_dsym] ERROR: missing config file at $CONFIG_FILE" >&2
    echo "             See docs/DSYM_UPLOAD.md for one-time setup." >&2
    exit 1
fi
# shellcheck disable=SC1090
source "$CONFIG_FILE"
: "${SUPABASE_URL:?SUPABASE_URL must be set in $CONFIG_FILE}"
: "${SUPABASE_SERVICE_ROLE_KEY:?SUPABASE_SERVICE_ROLE_KEY must be set in $CONFIG_FILE}"

# ─── 2. Locate the archive ────────────────────────────────────────────────
# Xcode sets ARCHIVE_PATH when run as a post-action; CLI callers pass $1.
ARCHIVE="${1:-${ARCHIVE_PATH:-}}"
if [[ -z "$ARCHIVE" || ! -d "$ARCHIVE" ]]; then
    echo "[upload_dsym] ERROR: archive path not found: '$ARCHIVE'" >&2
    echo "             Pass the .xcarchive path as \$1 or run from an Xcode Archive post-action." >&2
    exit 1
fi

DSYMS_DIR="$ARCHIVE/dSYMs"
APP_DSYM="$(find "$DSYMS_DIR" -maxdepth 2 -name 'Fit33.app.dSYM' -type d 2>/dev/null | head -n1 || true)"
if [[ -z "$APP_DSYM" ]]; then
    echo "[upload_dsym] ERROR: no Fit33.app.dSYM found under $DSYMS_DIR" >&2
    exit 1
fi

# ─── 3. Extract UUID (arm64) + version/build ──────────────────────────────
# We ship arm64-only, so we want that specific UUID. Fallback to the first
# UUID dwarfdump prints if the arch line doesn't match (shouldn't happen).
BINARY_UUID="$(dwarfdump --uuid "$APP_DSYM" 2>/dev/null | awk '/arm64/ {print $2; exit}')"
if [[ -z "$BINARY_UUID" ]]; then
    BINARY_UUID="$(dwarfdump --uuid "$APP_DSYM" 2>/dev/null | awk 'NF>=2 {print $2; exit}')"
fi
if [[ -z "$BINARY_UUID" ]]; then
    echo "[upload_dsym] ERROR: could not parse UUID from $APP_DSYM" >&2
    exit 1
fi
# PostgreSQL UUID type is case-insensitive on comparison but the storage
# path is case-sensitive. Pick lowercase once and stay consistent so the
# iOS client (which sends UUID().uuidString uppercase) still joins cleanly
# — PG casts both to canonical form at the column type level.
BINARY_UUID_LOWER="$(echo "$BINARY_UUID" | tr '[:upper:]' '[:lower:]')"

INFO_PLIST="$ARCHIVE/Products/Applications/Fit33.app/Info.plist"
if [[ ! -f "$INFO_PLIST" ]]; then
    echo "[upload_dsym] ERROR: Info.plist not found at $INFO_PLIST" >&2
    exit 1
fi
APP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO_PLIST")"

echo "[upload_dsym] archive=$ARCHIVE"
echo "[upload_dsym] uuid=$BINARY_UUID_LOWER  app=$APP_VERSION  build=$BUILD_NUMBER"

# ─── 4. Skip if already uploaded ──────────────────────────────────────────
# Idempotent: if app_dsyms already has this binary_uuid, we're done. Archive
# post-actions run every time you Archive, so avoiding a re-upload matters.
EXISTING="$(curl -sS \
    -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" \
    -H "apikey: $SUPABASE_SERVICE_ROLE_KEY" \
    "$SUPABASE_URL/rest/v1/app_dsyms?binary_uuid=eq.$BINARY_UUID_LOWER&select=binary_uuid" 2>/dev/null || echo "[]")"
if [[ "$EXISTING" != "[]" && "$EXISTING" != "" ]]; then
    echo "[upload_dsym] ✓ already uploaded — no-op"
    exit 0
fi

# ─── 5. Zip the dSYM bundle ───────────────────────────────────────────────
TMPDIR_UPLOAD="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_UPLOAD"' EXIT
ZIP_PATH="$TMPDIR_UPLOAD/$BINARY_UUID_LOWER.zip"
( cd "$(dirname "$APP_DSYM")" && zip -qry "$ZIP_PATH" "$(basename "$APP_DSYM")" )
SIZE_BYTES="$(stat -f%z "$ZIP_PATH")"
SHA256="$(shasum -a 256 "$ZIP_PATH" | awk '{print $1}')"
echo "[upload_dsym] zipped: $(du -h "$ZIP_PATH" | cut -f1)  sha256=${SHA256:0:12}…"

# ─── 6. Upload to Storage bucket ──────────────────────────────────────────
STORAGE_PATH="$BINARY_UUID_LOWER.zip"
HTTP_CODE="$(curl -sS -o "$TMPDIR_UPLOAD/upload.out" -w '%{http_code}' \
    -X POST \
    -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" \
    -H "apikey: $SUPABASE_SERVICE_ROLE_KEY" \
    -H "x-upsert: true" \
    -H "Content-Type: application/zip" \
    --data-binary "@$ZIP_PATH" \
    "$SUPABASE_URL/storage/v1/object/dsyms/$STORAGE_PATH")"
if [[ "$HTTP_CODE" != "200" && "$HTTP_CODE" != "201" ]]; then
    echo "[upload_dsym] ERROR: storage upload failed: HTTP $HTTP_CODE" >&2
    cat "$TMPDIR_UPLOAD/upload.out" >&2
    exit 2
fi
echo "[upload_dsym] ✓ uploaded to dsyms/$STORAGE_PATH"

# ─── 7. Record row in app_dsyms ───────────────────────────────────────────
PAYLOAD="$(jq -n \
    --arg uuid "$BINARY_UUID_LOWER" \
    --arg ver "$APP_VERSION" \
    --arg build "$BUILD_NUMBER" \
    --arg path "$STORAGE_PATH" \
    --argjson size "$SIZE_BYTES" \
    --arg sha "$SHA256" \
    '{binary_uuid:$uuid, app_version:$ver, build_number:$build, storage_path:$path, size_bytes:$size, sha256:$sha}')"

HTTP_CODE="$(curl -sS -o "$TMPDIR_UPLOAD/db.out" -w '%{http_code}' \
    -X POST \
    -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" \
    -H "apikey: $SUPABASE_SERVICE_ROLE_KEY" \
    -H "Content-Type: application/json" \
    -H "Prefer: resolution=merge-duplicates,return=minimal" \
    --data "$PAYLOAD" \
    "$SUPABASE_URL/rest/v1/app_dsyms")"
if [[ "$HTTP_CODE" != "201" && "$HTTP_CODE" != "204" && "$HTTP_CODE" != "200" ]]; then
    echo "[upload_dsym] ERROR: DB insert failed: HTTP $HTTP_CODE" >&2
    cat "$TMPDIR_UPLOAD/db.out" >&2
    exit 2
fi

echo "[upload_dsym] ✓ recorded app_dsyms row — symbolicate-crashes will pick this up within 15m"
