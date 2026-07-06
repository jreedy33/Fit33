# Signing keys do NOT belong in this repo

The APNs auth key (`AuthKey_*.p8`) that used to live here was **removed** — a
private signing key must never be committed to git.

**Where the APNs key actually lives at runtime:** the backend reads it from the
`APNS_PRIVATE_KEY` environment variable (a Supabase edge-function secret), along
with `APNS_KEY_ID`, `APNS_TEAM_ID`, and `APNS_BUNDLE_ID`. See
`supabase/functions/_shared/apns.ts`. No code ever read the `.p8` from disk.

**Keep your only backup of the `.p8` off git** — in a password manager or your
Apple Developer account, not in this repository. `*.p8` is gitignored; do not
add an exception for it.
