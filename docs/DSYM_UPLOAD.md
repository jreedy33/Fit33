# dSYM Upload — One-Time Setup

> Q2-97 Phase 5.4 · paired with `scripts/upload_dsym.sh`
> Last verified: 2026-05-01

Every Archive of Fit33 produces a `Fit33.app.dSYM` bundle. Without that dSYM on the server side, the symbolicate-crashes workflow can't turn raw stack addresses into `file:line:function`, and Claude triage falls back to the capped-confidence Phase 3.1 path (error-message-tag inference).

This doc gets you from "just archived" to "dSYM uploaded and indexed" in about five minutes, one time. After that, every future Archive runs the upload automatically.

---

## 1. Create the secrets file (~30 sec)

The upload script reads Supabase credentials from a private file in your home directory — never commit these anywhere.

```bash
mkdir -p ~/.fit33
cat > ~/.fit33/dsym-upload.env <<'EOF'
SUPABASE_URL=https://<your-project>.supabase.co
SUPABASE_SERVICE_ROLE_KEY=eyJhbGciOiJI...<your service role key>
EOF
chmod 600 ~/.fit33/dsym-upload.env
```

Where to find these:
- **URL**: Supabase dashboard → Project Settings → API → Project URL
- **Service role key**: same page, under "Project API Keys" → `service_role` (the `secret` one, not `anon`). Treat this as a password — it bypasses RLS.

## 2. Install `jq` if you don't have it (one-time)

```bash
brew install jq
```

Everything else (`zip`, `shasum`, `dwarfdump`, `PlistBuddy`) ships with macOS.

## 3. Wire the script into Xcode Archive post-actions (2 min)

This makes the upload run automatically every time you Product > Archive.

1. Xcode → **Product** menu → **Scheme** → **Edit Scheme…** (or `⌘<`)
2. In the left column, click **Archive**
3. Expand the **Post-actions** section (it's below "Build Configuration")
4. Click the **+** at the bottom → **New Run Script Action**
5. In the new row:
   - **Shell**: `/bin/bash`
   - **Provide build settings from**: `Fit33` (so `ARCHIVE_PATH` is in scope)
   - **Script field**: paste exactly this
     ```bash
     "${SRCROOT}/scripts/upload_dsym.sh" "${ARCHIVE_PATH}"
     ```
6. **Close** (Xcode persists the change)

## 4. Smoke test

Archive any version (Product > Archive). When it finishes, the Organizer window will appear **and** the post-action log prints at the bottom of the build log. You should see:

```
[upload_dsym] uuid=6a1…  app=1.38  build=48
[upload_dsym] zipped: 124M  sha256=7f3…
[upload_dsym] ✓ uploaded to dsyms/6a1….zip
[upload_dsym] ✓ recorded app_dsyms row — symbolicate-crashes will pick this up within 15m
```

Verify in Supabase:

```sql
select binary_uuid, app_version, build_number, uploaded_at
from app_dsyms
order by uploaded_at desc
limit 5;
```

You should see the row you just uploaded. Any crash that lands for this build will get `symbolication_status = 'pending'` → `'done'` after the next scheduled workflow run (every 15 min).

---

## CLI fallback

If Xcode's post-action didn't fire (it happens — turn off "Show in Organizer" in the post-action modifies the scope), you can always run it manually:

```bash
scripts/upload_dsym.sh ~/Library/Developer/Xcode/Archives/2026-05-01/Fit33\ 5-1-26\,\ 10.30\ AM.xcarchive
```

Idempotent — re-running on an already-uploaded UUID is a no-op.

## What happens to old builds

Builds archived before Phase 5 shipped don't have their dSYMs in the bucket (we don't have them). Crashes from those builds stay `symbolication_status = 'legacy'` forever and use Phase 3.1's error-message-tag fallback in triage-bugs. That's fine — they're mostly old, mostly resolved, and not worth backfilling.

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `missing config file at …/dsym-upload.env` | Step 1 skipped | Create the file per §1 |
| `SUPABASE_SERVICE_ROLE_KEY must be set` | Wrong env var name in config | Double-check key name (case-sensitive) |
| `could not parse UUID from …` | Non-Fit33 archive selected | Make sure you archived the `Fit33` scheme, not a sub-target |
| `storage upload failed: HTTP 403` | Wrong service-role key (anon key won't work) | Re-copy from Supabase Project Settings → API |
| `storage upload failed: HTTP 413` | dSYM is >5GB (shouldn't happen) | Open a task — we'll switch to multipart upload |
| `DB insert failed: HTTP 409` | `binary_uuid` already in `app_dsyms` | Shouldn't happen — the script pre-checks. If it does, re-run (idempotent). |
| Post-action log shows "command not found" | `jq` not installed or not on Xcode's PATH | `brew install jq`; restart Xcode so it inherits the new PATH |

## Security notes

- `~/.fit33/dsym-upload.env` holds the **service-role key**. That key bypasses RLS. Keep `chmod 600` and never commit it or share the file. If it leaks, rotate in Supabase Dashboard → Project Settings → API → Reset service role key.
- `scripts/upload_dsym.sh` is in the repo and safe to share — it only reads the env file, never writes it.
- The `dsyms` bucket is private. Storage RLS prevents any non-admin authenticated user from writing to it; the service-role key is the only write path. Reads are service-role-only too (the GitHub Actions runner).
- dSYM files contain no user data — only Swift symbol tables. Leak severity: low (they're what you'd get from reverse-engineering a public App Store binary). Still, treat the bucket as private by default.

## When to come back to this doc

- You get a new Mac / fresh clone → redo steps 1–3
- Service-role key rotated in Supabase → update step 1
- The script fails in a way not covered in Troubleshooting → open a task
- You want to add auto-upload from Xcode Cloud or TestFlight Connect → that's a future Phase 5.x enhancement, not in today's scope
