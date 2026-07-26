# Supabase SQL Deployment Order — RETIRED

> **This document is retired (2026-07-26 production-readiness audit).**
> It only ever covered ~5 legacy friend/deletion files from the pre-`YYYYMMDD`
> era and following it would miss essentially the entire 2026 schema.

## Canonical source of truth

**`supabase/MIGRATION_INDEX.md`** is the release train:

- Migrations are numbered rows in deploy order, each with a status
  (🆕 Ready / ✅ Deployed) and rollback notes.
- To deploy: apply every 🆕 row **in numeric order** via the Supabase SQL
  Editor, then flip its status to ✅.
- New migrations follow the "Process for New Migrations" section at the
  bottom of the index (idempotent DDL, `BEGIN;/COMMIT;`, drop overloads
  before `CREATE OR REPLACE`, add an index row in the same PR —
  `scripts/pre_commit_migration_check.sh` enforces this).

## Deploy-first standing order

`20260726_delete_user_account_guard_hotfix.sql` (index #203) is a P0
security hotfix (IDOR guard restoration) — if it shows 🆕, deploy it before
anything else.
