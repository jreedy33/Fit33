# Admin CMS Recovery Runbook

Break-glass procedures for when an admin can't log in to the Fit33 admin CMS.

If you are reading this because you (the CEO) are locked out, **DO NOT PANIC**.
Every problem on this page is recoverable from your laptop in under five minutes,
provided you have:

1. This repo checked out at `~/Desktop/Workout App/`
2. `admin-cms/.env.local` with a valid `SUPABASE_SERVICE_ROLE_KEY`
3. Node 20+ installed

The service-role key in `.env.local` is the master key — it bypasses RLS and
can do everything the Supabase dashboard can. Treat it accordingly. (If you
ever rotate the service-role key, update `.env.local` AND Vercel's env vars
in the same change, AND every admin's `admin_mfa_trust` cookie is invalidated
so everyone has to re-MFA — that is the desired behavior on key rotation.)

---

## TL;DR — start here

```bash
cd "~/Desktop/Workout App/admin-cms"
npm run admin:audit
```

The audit prints every entry in `ADMIN_EMAILS` and tells you whether each
one resolves to a valid Supabase auth user with a verified TOTP factor.

| Status        | Meaning                                                                  | Fix                                                       |
| ------------- | ------------------------------------------------------------------------ | --------------------------------------------------------- |
| `OK`          | Allowlisted, user exists, email confirmed, TOTP verified.                | Nothing to do.                                            |
| `NO_USER`     | Email is in `ADMIN_EMAILS` but no Supabase user. **Login impossible.**   | [Create the Supabase user](#create-a-new-admin-user).     |
| `NO_MFA`      | User exists but has never enrolled MFA.                                  | Sprint-9 enforcement walks them through QR on next login. |
| `UNVERIFIED`  | User started MFA enrollment but never finished.                          | Next login will reuse the half-enrolled factor.           |
| `UNCONFIRMED` | User exists but `email_confirmed_at` is null. Supabase rejects sign-in.  | [Confirm the email](#manually-confirm-an-email).          |
| `BANNED`      | User has `banned_until` set in the future.                               | [Unban the user](#unban-a-user).                          |

---

## Login route returns "Invalid credentials" — what does that actually mean?

The CMS deliberately returns a generic `Invalid credentials` for both
"email not in allowlist" AND "Supabase rejected password". This is anti
account-enumeration hygiene; do not weaken it.

To find out the real reason:

1. **Run the audit script** — `npm run admin:audit`. This catches the
   most common failure: allowlist entry with no matching Supabase user.
2. **Check Vercel logs** — `Logs` tab on the `fitapp` project, search
   for `[auth/login] reject reason=`. The server logs the actual cause
   (allowlist miss vs Supabase auth error) on every rejected login.
3. **Confirm Vercel's `ADMIN_EMAILS`** matches what you expect. Vercel
   env vars and `.env.local` are independent — a typo in one does not
   show up in the other.

---

## Create a new admin user

When `admin-audit` reports `NO_USER` for an allowlisted email, or you want
to add a new admin entirely:

1. Add the email to `ADMIN_EMAILS` in **both** `admin-cms/.env.local` AND
   Vercel → Project `fitapp` → Settings → Environment Variables. Redeploy.
2. Create the Supabase auth user via the admin REST API:

```bash
cd "~/Desktop/Workout App/admin-cms"
set -a && . ./.env.local && set +a
curl -sS -X POST \
  -H "apikey: $SUPABASE_SERVICE_ROLE_KEY" \
  -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" \
  -H "Content-Type: application/json" \
  "$NEXT_PUBLIC_SUPABASE_URL/auth/v1/admin/users" \
  -d '{
    "email": "NEW_ADMIN@doublethr33s.com",
    "password": "REPLACE_WITH_STRONG_PASSWORD",
    "email_confirm": true
  }'
```

3. The new admin logs in with the email + password you set; the Sprint-9
   flow will force MFA enrollment on first login. Have them finish the QR
   step before they walk away from the laptop.

---

## Reset a forgotten password

```bash
cd "~/Desktop/Workout App/admin-cms"
set -a && . ./.env.local && set +a

# 1. Look up the user ID
curl -sS \
  -H "apikey: $SUPABASE_SERVICE_ROLE_KEY" \
  -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" \
  "$NEXT_PUBLIC_SUPABASE_URL/auth/v1/admin/users?per_page=200" \
  | python3 -c "import json, sys; [print(u['id'], u['email']) for u in json.load(sys.stdin).get('users',[]) if 'EMAIL_HERE' in (u.get('email') or '')]"

# 2. Reset the password (replace USER_ID and NEW_PASSWORD)
curl -sS -X PUT \
  -H "apikey: $SUPABASE_SERVICE_ROLE_KEY" \
  -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" \
  -H "Content-Type: application/json" \
  "$NEXT_PUBLIC_SUPABASE_URL/auth/v1/admin/users/USER_ID" \
  -d '{"password": "NEW_PASSWORD"}'
```

---

## Lost authenticator (TOTP locked out)

If your phone with the TOTP seed died and your password manager doesn't have
a backup of the seed, you have to clear the existing factor server-side and
re-enroll on next login.

```bash
cd "~/Desktop/Workout App/admin-cms"
set -a && . ./.env.local && set +a

# 1. Find the user
curl -sS \
  -H "apikey: $SUPABASE_SERVICE_ROLE_KEY" \
  -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" \
  "$NEXT_PUBLIC_SUPABASE_URL/auth/v1/admin/users?per_page=200" \
  | python3 -c "import json, sys; [print(u['id'], u['email']) for u in json.load(sys.stdin).get('users',[]) if 'EMAIL_HERE' in (u.get('email') or '')]"

# 2. List factors for that user
curl -sS \
  -H "apikey: $SUPABASE_SERVICE_ROLE_KEY" \
  -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" \
  "$NEXT_PUBLIC_SUPABASE_URL/auth/v1/admin/users/USER_ID/factors"

# 3. Delete each factor (run for every factor.id from step 2)
curl -sS -X DELETE \
  -H "apikey: $SUPABASE_SERVICE_ROLE_KEY" \
  -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" \
  "$NEXT_PUBLIC_SUPABASE_URL/auth/v1/admin/users/USER_ID/factors/FACTOR_ID"
```

After deleting the factor, the next login will hit the Sprint-9 enrollment
branch and prompt you to scan a fresh QR code.

You also want to clear the 30-day "trust this device" cookie on your end
(quit the browser or open a private window) — the cookie is signed against
the service-role key and is bound to the user ID, but it represents a device
you may no longer trust.

---

## Manually confirm an email

If the audit reports `UNCONFIRMED`:

```bash
curl -sS -X PUT \
  -H "apikey: $SUPABASE_SERVICE_ROLE_KEY" \
  -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" \
  -H "Content-Type: application/json" \
  "$NEXT_PUBLIC_SUPABASE_URL/auth/v1/admin/users/USER_ID" \
  -d '{"email_confirm": true}'
```

---

## Unban a user

```bash
curl -sS -X PUT \
  -H "apikey: $SUPABASE_SERVICE_ROLE_KEY" \
  -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" \
  -H "Content-Type: application/json" \
  "$NEXT_PUBLIC_SUPABASE_URL/auth/v1/admin/users/USER_ID" \
  -d '{"ban_duration": "none"}'
```

---

## Rate-limited?

The login route locks an IP for 30 minutes after 5 failures in a 15-minute
window. If you locked yourself out by retrying too fast, the rate limiter
is in-memory in the Next.js process — restart the Vercel deployment (push
a noop commit, or use the Redeploy button) and the counter resets.

---

## What the in-CMS audit endpoint shows

Once you ARE logged in, `/api/admin/health` returns the same audit as JSON.
This is admin-gated so coworkers can't enumerate the allowlist:

```bash
# Logged-in admin only — uses your existing admin_access_token cookie.
curl -s 'https://YOUR-CMS-URL/api/admin/health' | python3 -m json.tool
```

Wire it into a dashboard widget if you want a permanent green-light
indicator that the CMS will actually let you log in tomorrow.
