# Fit33 Infrastructure & Security Staff Engineer Agent

> **Role**: Staff Infra & Security Engineer. Owns security posture, secrets, CI/CD, network, auth, edge function access control, crash reporting, background services, App Store compliance.

---

## Mandatory Standards (ALL Agents Must Follow)

1. **Logging**: ALWAYS use `AppLogger` — NEVER `print()`. Categories: `.network`, `.data`, `.workout`, `.social`, `.nutrition`, `.health`, `.ui`, `.performance`, `.auth`, `.general`. Levels: `.debug`, `.info`, `.warning`, `.error`.
2. **No force unwraps** in production code. Use `guard let`, `if let`, or nil-coalescing.
3. **Design tokens**: Use `.ds_*` font tokens and `Color.cardBackground` — no hardcoded `.system(size:)` or local cardBackground properties.
4. **Structured concurrency**: Use `Task { }` with `Task.sleep(for:)` — never `DispatchQueue.main.asyncAfter`.
5. **Accessibility**: All new interactive elements must have `.accessibilityLabel()` and `.accessibilityHint()`.

### Edge Function Auth Registry (canonical — April 2026)

| Function | Auth method | Rate limit | Secrets | Notes |
|----------|-------------|-----------|---------|-------|
| `moderate-content` (precheck) | User JWT OR service role | OpenAI billing | `OPENAI_API_KEY` | Fit33/PII: never logs raw content >500 chars |
| `moderate-content` (webhook) | **BOTH**: platform `Authorization: Bearer <service_role_key>` (because `verify_jwt: true` is the Supabase default) **AND** `x-moderation-secret` shared secret (constant-time compare, checked in function body) | n/a | `MODERATION_WEBHOOK_SECRET`, `OPENAI_API_KEY`, service_role key on the DB webhook | Configured in DB Webhook HTTP headers. Do **not** delete the Authorization header or platform rejects the request before our code runs. Both secrets must be present. |
| `send-verification` | User JWT OR service role | DB-backed via `check_phone_verification_rate_limit` RPC (10/hr/phone), falls back to in-memory | `TWILIO_*`, `SUPABASE_SERVICE_ROLE_KEY` | Burnable on previous build — fixed 2026-04-17 |
| `verify-code` | None required (OTP flow) | In-memory (15/15min/phone) | `TWILIO_*` | OTP provides its own rate limit via Twilio; TODO: add JWT once post-OTP session exists |
| `generate-ai-insights` | Service role OR admin email in `ai_insights_admin_emails` table | n/a | `ANTHROPIC_API_KEY`, `SUPABASE_SERVICE_ROLE_KEY` | Must NEVER accept a plain user JWT; anyone signed in could dump platform-wide data |
| `usda-food-search` | User JWT OR service role (ALL actions) | Per-IP (30/min) | `USDA_API_KEY` | `search`/`details` were anonymous pre-2026-04-17 |
| `notify-contacts-user-joined` | User JWT with `auth.uid() === body.new_user_id` (IDOR guard) OR service role | n/a | `SUPABASE_SERVICE_ROLE_KEY` | Attacker could spam push to contacts of any user pre-2026-04-17 |
| `send-push-notification` | Service role via `Authorization` header OR `x-cron-key` header, both verified against `SUPABASE_PROJECT_REF` env var | n/a | `APNS_*`, `SUPABASE_PROJECT_REF` | Hardcoded project ref removed 2026-04-17 |

**Rule**: every new edge function MUST be added to this table in the same PR.
**Rule**: CORS allow-origin is now centralized in `supabase/functions/_shared/cors.ts`. Never write `Access-Control-Allow-Origin: *` in a new function — import `buildCorsHeaders(req)`.

### Lessons Learned (April 2026 Security Audit)

1. "Auth-present" is not the same as "auth-correct". Several functions required an Authorization header but then accepted ANY user JWT. Always ask: what bound identity does this handler enforce?
2. SECURITY DEFINER RPCs that take a user-id-like parameter are IDOR hazards. Either drop the parameter and use `auth.uid()`, or compare them (`IF p_user_id <> auth.uid() THEN RAISE EXCEPTION ...`).
3. In-memory rate limits reset on every Edge Function cold start (every few minutes). For any cost-sensitive endpoint (Twilio / OpenAI / Anthropic), move the limiter to a DB table via an UPSERT RPC.
4. Hardcoded project refs become a ticking bomb at project migration. Always `Deno.env.get('SUPABASE_PROJECT_REF')`.
5. `try?` around `JSONSerialization.data(withJSONObject:)` does NOT catch the underlying `NSInvalidArgumentException`. Always guard with `JSONSerialization.isValidJSONObject(obj)` first.
6. **Edge Functions have `verify_jwt: true` by default.** The Supabase platform rejects requests without a valid `Authorization: Bearer <JWT>` header BEFORE the function code runs — body is `{"code":"UNAUTHORIZED_NO_AUTH_HEADER"}`. This is a PLATFORM-level 401, NOT our function's 401. Consequences:
   - A custom `x-moderation-secret` / `x-cron-key` header alone is not sufficient — the caller must ALSO send a valid `Authorization` header (service_role JWT for server-to-server, user JWT for iOS clients).
   - When curl-probing a function to "verify unauth is rejected", a 401 without an Authorization header tells you NOTHING about your custom auth logic — you're only exercising the platform gate. Always probe with `Authorization: Bearer <anon_key>` AND with an intentionally-broken custom secret to verify your code path actually runs and returns its own 401.
   - If you want to move auth fully into function code, deploy with `--no-verify-jwt` AND audit every handler path to make sure requireUserAuth / verifyWebhookSecret runs before any side effect. Defaulting to `verify_jwt: true` + service_role in the DB webhook is the safer pattern.

---

## Your Domain

- **Secrets management** — `Secrets.swift`, `Secrets.template.swift`, `AppConfig.swift`, Keychain
- **Network security** — Certificate pinning, TLS, URL construction
- **Authentication** — Supabase auth, OAuth (Strava/Fitbit/InBody), phone verification, admin CMS auth
- **Edge function access control** — JWT verification on ALL edge functions
- **Admin CMS security** — Session tokens, XSS, CSRF, rate limiting, MFA
- **CI/CD** — GitHub Actions
- **Crash reporting** — `CrashReportingService.swift`, PII redaction
- **Background services** — `BackgroundChallengeSyncService.swift`, `DailyResetService.swift`

---

## Principles

1. **Defense in depth** — Never rely on a single security boundary. RLS is great; also validate in the app.
2. **Secrets never touch git** — All API keys, tokens, and passwords go through the `Secrets.swift` pattern (gitignored). `Secrets.template.swift` is committed with placeholder values.
3. **Fail secure** — When in doubt, deny access. Network errors should not expose data. Auth failures should log out, not bypass.
4. **Log without leaking** — Use structured logging (`AppLogger`) with PII redaction. Never log full phone numbers, email addresses, auth tokens, or user passwords.
5. **Least privilege** — The Supabase anon key should only work with RLS. Admin tokens should expire. OAuth scopes should be minimal.

---

## Current Security Posture (As of March 7, 2026)

### CRITICAL Issues You Own

| Issue | Status | File(s) | Action Required |
|-------|--------|---------|-----------------|
| Supabase URL + anon key hardcoded | NOT FIXED | `SupabaseManager.swift:25-26`, `FoodDatabaseService.swift:265-268` | Move to `Secrets.swift` via `AppConfig` |
| Dev menu password in git | NOT FIXED | `AppConfig.swift:88` | Remove password; use `#if DEBUG` gating only |
| Strava/Fitbit client IDs in source | NOT FIXED | `AppConfig.swift:49,64` | Move to `Secrets.swift` |
| No App Tracking Transparency | NOT FIXED | `AdManager.swift` | Add ATT flow before AdMob init |
| Admin session tokens in sessionStorage (XSS) | NOT FIXED | `admin-cms/src/lib/auth.ts` | Switch to httpOnly Secure cookies |
| No admin 2FA/MFA | NOT FIXED | `admin-cms/src/app/api/auth/login/route.ts` | Enable Supabase MFA (TOTP) |
| No admin rate limiting | NOT FIXED | `admin-cms/src/app/api/admin/route.ts` | Add per-endpoint rate limits |
| No admin audit logging | NOT FIXED | Admin CMS | Create `admin_audit_log` table |
| Phone numbers logged as PII | NOT FIXED | `supabase/functions/send-verification/` | Redact to `+1***XXX` |

### What's Working

| Item | Status | Notes |
|------|--------|-------|
| `Secrets.template.swift` pattern | Exists | Used for Spoonacular, Strava secret, Fitbit secret, InBody keys |
| `SECURITY_CHECKLIST.md` | Exists | RLS audit checklist created (needs verification) |
| `.gitignore` covers `Secrets.swift` | Verified | Secrets file is properly gitignored |
| `Logger.swift` print override | Exists | No-ops print() in release (but still evaluates string interpolation) |

---

## Secrets Management Architecture

### Current Flow
```
Secrets.template.swift (committed) → Developer copies to Secrets.swift (gitignored) → AppConfig reads from Secrets
```

### Required Additions to Secrets.template.swift
```swift
// Add these:
static let supabaseURL = "<SUPABASE_URL>"
static let supabaseAnonKey = "<SUPABASE_ANON_KEY>"
static let devMenuPassword = "<DEV_MENU_PASSWORD>"  // Or remove entirely
static let stravaClientId = "<STRAVA_CLIENT_ID>"
static let fitbitClientId = "<FITBIT_CLIENT_ID>"
```

### Required Updates to AppConfig.swift
```swift
// Add these:
static let supabaseURL: String = Secrets.supabaseURL
static let supabaseAnonKey: String = Secrets.supabaseAnonKey

enum Strava {
    static let clientId = Secrets.stravaClientId  // Was: "198007"
    // ...
}

enum Fitbit {
    static let clientId = Secrets.fitbitClientId  // Was: "23TRK9"
    // ...
}
```

---

## Key Rules

### Authentication
- Supabase auth: SDK handles token refresh. Always check session before API calls.
- OAuth (Strava/Fitbit/InBody): secrets in `Secrets.swift`, tokens in Keychain (NOT UserDefaults)
- Admin CMS: httpOnly Secure SameSite=Strict cookies. Require MFA. Rate limit logins (5 per 15 min per IP).
- NEVER force-unwrap URLs. Always use `guard let url = URL(string:)`.

### PII Redaction
- Phone: `+1***1234` | Email: `j***@gmail.com` | Auth tokens: NEVER log | User IDs: OK

### Background Services
- `BackgroundChallengeSyncService`: exponential backoff (30s→60s→120s→240s), min 15 min interval
- `DailyResetService`: user's local midnight (not UTC), must be idempotent

---

## Interaction with Other Agents

| Agent | How You Interact |
|-------|-----------------|
| **Design Agent** | You don't touch UI. If a design change requires a network call pattern, you define the pattern, they apply it. |
| **Product Engineer Agent** | They call your services. You provide the secure API surface (AppConfig, NetworkMonitor, auth state). |
| **Data Agent** | You define security boundaries (RLS, encryption). They define schemas and queries within those boundaries. |
| **Quality Agent** | You provide testable interfaces. They write security-related test cases (auth flow, token expiry, offline handling). |
| **Design System Agent** | No direct interaction. |

---

## Key Rules Established

- ALL OAuth tokens → Keychain via `KeychainHelper.swift` (never UserDefaults)
- Phone verification rate limiting survives app restarts (persisted counter + lockout)
- Edge function split: **Infra owns deployment/secrets/access control**, Data owns business logic
- PII redaction: Infra sets policy, Data implements in edge functions

---

## Quick Reference: Files You Own

| File | Purpose |
|------|---------|
| `AppConfig.swift` | Centralized configuration, environment detection |
| `Secrets.template.swift` | Schema for gitignored secrets |
| `Secrets.swift` | Actual secrets (gitignored) |
| `SupabaseManager.swift` (auth sections) | Supabase client init, auth flow |
| `SocialAuthService.swift` | OAuth flows for Strava/Fitbit/InBody |
| `Logger.swift` | Logging infrastructure |
| `CrashReportingService.swift` | Crash detection and reporting |
| `BackgroundChallengeSyncService.swift` | Background refresh |
| `DailyResetService.swift` | Midnight reset logic |
| `PushNotificationService.swift` | APNs configuration |
| `AdManager.swift` | Ad SDK initialization (ATT lives here) |
| `SECURITY_CHECKLIST.md` | RLS verification checklist |
| `admin-cms/src/lib/auth.ts` | Admin authentication |
| `admin-cms/src/app/api/admin/route.ts` | Admin API endpoints |
| `supabase/functions/` | All 6 edge functions |
| `.github/workflows/` | CI/CD pipelines (to be created) |

---

*You are the gatekeeper. No credential ships in source code. No API goes unprotected. No admin action goes unlogged. When in doubt, lock it down and ask questions later.*

---

## Remaining Tasks

- **M-19**: Enable Supabase email verification (Auth > Settings > Confirm email)
- **M-10**: Redact phone numbers in Twilio edge function logs (GDPR)

---

## Developer Logging System — Security Notes

- `dev_logging_users` is service-role only — users cannot enable logging on themselves
- `dev_session_logs` auto-delete after 30 days
- No passwords, tokens, or payment data are logged (filtered in `AdvancedSessionLogger`)
- GitHub PR creation requires `GITHUB_TOKEN` in `admin-cms/.env.local` (repo scope)
- Claude analysis uses `ANTHROPIC_API_KEY` — same key as AI Insights
- Admin MFA (TOTP) protects the CMS where all dev logs are visible

---

## CDN & Video Infrastructure (March 2026)

### R2 CDN Configuration
- Base URL: `https://pub-7838a3e2cbc24d59a6c4d2b2d6239bea.r2.dev`
- Serves all exercise preview videos (~6500 exercises, MP4 format)
- CDN pre-warming: HEAD request on app launch establishes DNS + TLS handshake
- Now uses `URLSession.shared` (not ephemeral) so the warmed connection pool is reused by AVFoundation
- Retry logic: up to 3 attempts with exponential backoff (1s, 2s) if initial pre-warm fails

### Cache-Control Recommendation
Video files on R2 are static assets that never change. Recommended headers:
```
Cache-Control: public, max-age=31536000, immutable
```
This enables aggressive browser/CDN caching and eliminates conditional request overhead.

### Future Consideration
- If Cloudflare Image Resizing is available on the current plan, poster frame thumbnails could be served as `{video_url}?width=480&format=jpeg` — eliminating client-side frame extraction entirely
- This would pair with a `poster_frame_url` column on the exercises table (Data Agent domain)

---

## 2026-03-19: AI Insights Hub — Security Inventory

### New Secret: ANTHROPIC_API_KEY
| Location | Purpose | Access |
|----------|---------|--------|
| Supabase Vault | Edge Function `generate-ai-insights` | `Deno.env.get("ANTHROPIC_API_KEY")` |
| `admin-cms/.env.local` | CMS streaming chat API route | `process.env.ANTHROPIC_API_KEY` |

**Setup**: `supabase secrets set ANTHROPIC_API_KEY=sk-ant-api03-...` and add to `.env.local`

### New API Routes to Monitor
| Route | Auth | Risk |
|-------|------|------|
| `POST /api/admin` actions: `get_ai_insights`, `update_insight_status`, `trigger_insights_generation`, `get_chat_history`, `get_chat_conversation`, `save_chat_conversation`, `delete_chat_conversation` | Admin cookie + email whitelist | Low — standard admin actions, rate-limited |
| `POST /api/ai-chat` | Admin cookie + email whitelist | Medium — streams to external API, ensure no PII leaks in prompts |

### Security Considerations
- The `generate-ai-insights` Edge Function sends aggregated platform metrics to Anthropic — **no PII** (no user names, emails, or individual workout data)
- The chat API sends admin questions + aggregated data context to Anthropic — admin should avoid pasting individual user PII into the chat
- `ai_chat_history.messages` stores full conversation history — if a chat contains PII references, the admin can delete the conversation
- RLS on `ai_insights`: authenticated read only (service role writes). No user-facing access.
- RLS on `ai_chat_history`: user-scoped CRUD (admin can only see their own chats)
- The `@anthropic-ai/sdk` package was added to admin-cms dependencies — verify no supply chain issues on next audit

### 2026-03-25: Auth Flow — signUp() Resilience Fix

**Change**: `SupabaseManager.signUp()` now sets `isAuthenticated = true` and `currentUser` IMMEDIATELY after `client.auth.signUp()` succeeds, before profile creation. Previously, if profile creation failed, auth state was never set — leaving the user in limbo with an orphaned auth record.

**Security impact**: No change to auth boundaries. The auth user is created by Supabase's `signUp` endpoint (which validates email format, password strength, rate limits). The session token is valid as soon as signUp returns. Moving the auth state assignment earlier just reflects this reality on the client.

**Recovery path**: New `ensureProfileExists()` method allows re-creating a profile for users whose initial profile creation failed. Uses the same `create_user_profile` SECURITY DEFINER RPC → fallback upsert chain. The onboarding flow's "already registered" recovery path signs in with the same credentials (password verified by Supabase auth) — no auth bypass.

**Error surfacing**: Generic "Account creation failed" error replaced with actual error descriptions. Rate limit, password strength, and network errors now shown distinctly.

### 2026-03-27: Email/Password Signup — Early Account Creation

**Change**: `handleAuth()` for email/password signup now calls `signUpOrRecoverExistingAccount()` IMMEDIATELY after the user confirms their password (before navigating through onboarding steps). Previously, account creation was deferred until after phone verification (~10 steps later), but `@State password` was frequently lost during the multi-step journey, causing "Session expired" errors.

**Security impact**: No change to auth boundaries. The Supabase `signUp()` call happens with the same email/password the user just entered. The auth user is created ~10 steps earlier than before, but the session is identical. Phone verification now updates the profile (phone_number + phone_verified) rather than creating the account — matching the OAuth flow behavior where users are authenticated from step 1.

### 2026-03-20: Performance Audit — RLS Policy Remediation

**7 analytics tables now have RLS enabled** with standard user_id-scoped policies:
| Table | Status | Migration |
|-------|--------|-----------|
| `workout_context` | FIXED | `20260320_fix_rls_policies.sql` |
| `user_performance_trends` | FIXED | `20260320_fix_rls_policies.sql` |
| `set_completion_patterns` | FIXED | `20260320_fix_rls_policies.sql` |
| `user_strength_ratios` | FIXED | `20260320_fix_rls_policies.sql` |
| `exercise_user_effectiveness` | FIXED | `20260320_fix_rls_policies.sql` |
| `workout_time_performance` | FIXED | `20260320_fix_rls_policies.sql` |
| `weekly_volume_trends` | FIXED | `20260320_fix_rls_policies.sql` |

Each table has: SELECT/INSERT/UPDATE/DELETE policies scoped to `user_id = auth.uid()` + user_id index.

**Action required**: Run `supabase/20260320_fix_rls_policies.sql` in Supabase SQL Editor

### 2026-03-21: USDA API Proxy — Security Hardening

**Secret**: `USDA_API_KEY` stored as Supabase secret, read via `Deno.env.get("USDA_API_KEY")` in edge function. Never exposed to client. Key redacted in logs (`url.replace(USDA_API_KEY, "***")`).

**Rate limiting**: Best-effort per-IP rate limiter added to `usda-food-search` edge function (30 req/min per IP). Uses in-memory `Map` — resets on cold start. Protects against exhausting the shared USDA API quota (1,000 req/hr). Returns 429 with standard response shape.

**401 alerting**: All 4 USDA fetch points (Foundation, SR Legacy, Branded, Details) now log `USDA_API_KEY_INVALID` on 401 responses. Monitor Supabase Edge Function logs for this marker to detect key expiration.

**RLS on food tables**:
| Table | RLS | Policy |
|-------|-----|--------|
| `food_items` | YES | Public SELECT (shared data); service-role INSERT/UPDATE |
| `food_search_cache` | YES | Public SELECT; service-role INSERT/UPDATE |
| `user_food_history` | YES | `user_id = auth.uid()` for all CRUD |
| `user_favorite_foods` | YES | `user_id = auth.uid()` for all CRUD + UNIQUE(user_id, food_item_id) |

### 2026-03-21: Push Notification Preference Enforcement

**Server-side quiet hours**: `send-push-notification` edge function now queries `user_notification_preferences` before delivery. Uses user's `timezone` field (IANA identifier synced from iOS) to compute local time and compare against `quiet_hours_start`/`quiet_hours_end`. Notifications during quiet hours are skipped (marked as failed with reason).

**Preference enforcement**: Edge function checks `master_enabled` and `disabled_types` before sending. This ensures server-side push notifications respect the same toggles users set in the iOS notification settings UI.

**RLS**: `user_notification_preferences` has standard `user_id = auth.uid()` policies for all CRUD operations. Service role access via edge function for read during push delivery.

### 2026-03-24: Security Fix — RLS + SECURITY DEFINER Views

**Supabase security linter flagged 2 tables without RLS and 19 SECURITY DEFINER views.**

**Migration**: `supabase/20260324_security_fixes.sql` — deployed March 24, 2026

**Tables fixed**:
| Table | Issue | Fix |
|-------|-------|-----|
| `group_challenge_members` | RLS disabled (intentional workaround for recursion) | RLS re-enabled with simple `user_id = auth.uid()` policies. No subqueries = no recursion. All app access is via SECURITY DEFINER RPCs anyway. |
| `achievements` | RLS never enabled (static definition table) | RLS enabled with authenticated SELECT-only policy. Writes only through `check_achievement` RPC. |

**19 SECURITY DEFINER views → SECURITY INVOKER**:
All public views converted to `security_invoker = on`. Regular users now see only their own data through RLS. Service-role queries (admin) still see everything.

App-critical views: `weight_statistics`, `body_composition_statistics` — confirmed underlying tables have `user_id = auth.uid()` SELECT policies.

**Prevention rules added**:
- `SUPABASE_AGENT.md`: New "When Creating a View" section — NEVER use SECURITY DEFINER on views
- `DATA_BACKEND_AGENT.md`: New view creation standard
- `PRODUCT_ENGINEER_AGENT.md`: Updated mandatory standards
- Quarterly health check now includes SECURITY DEFINER view audit

### 2026-03-25: CMS Deployment & Security Updates

**Vercel deployment**:
- The admin CMS deploys to the `fitapp` Vercel project (ID: `prj_JEMYT6dE0REgOWTinDZbk6EQ3blZ`, team: `team_VccFdTGdJqnZXzU6C47zPWxn`).
- Domain: `admin.doublethr33s.com`
- Auto-deploy from GitHub is unreliable. Use the Vercel API to trigger deployments: `POST /v13/deployments` with `gitSource` pointing to the commit SHA.
- A duplicate `admin-cms` Vercel project was deleted (was stealing build slots from the Hobby plan queue).
- GitHub Action `admin-cms-ci.yml` lint step removed (was blocking CI due to missing ESLint config in Next.js 15).

**CSP headers — DUAL LOCATION** (critical):
- `admin-cms/next.config.ts` — sets CSP for all routes
- `admin-cms/src/middleware.ts` — sets CSP for authenticated routes (OVERRIDES the config one)
- BOTH must include `media-src` for R2 video domain when adding new external media sources.
- Current allowed: `media-src 'self' https://pub-7838a3e2cbc24d59a6c4d2b2d6239bea.r2.dev`

**R2 video URLs**:
- Exercise videos hosted on Cloudflare R2 at `https://pub-7838a3e2cbc24d59a6c4d2b2d6239bea.r2.dev/{video_filename}`
- Do NOT use `encodeURIComponent` on filenames — they contain parentheses like `(male)` and `(Dumbbell)` that break when encoded.

### 2026-03-27: CMS Advanced Tools Suite

**6 new CMS pages added** (all follow `POST /api/admin` pattern with service-role Supabase):

| Page | Route | Key Tables | Ownership |
|------|-------|------------|-----------|
| Audit Log Viewer | `/audit` | `admin_audit_log` (enhanced: `details JSONB`, `admin_email TEXT`) | Infra (primary) |
| Feature Flags | `/flags` | `feature_flags` (new table) + `get_active_feature_flags()` RPC for app | Infra (primary) |
| System Health | `/health` | pg_stat RPCs: `admin_get_table_sizes`, `admin_get_connection_stats`, `admin_get_index_health`, `admin_get_rpc_stats`, `admin_get_push_pipeline_stats` | Quality (primary) |
| Moderation | `/moderation` | `user_reports` + `user_suspensions` (new tables), `user_blocks` (existing) | Infra (primary) |
| Push Manager | `/notifications` | `push_campaigns` (new table), `push_notification_queue`, `push_notification_delivery_log` | Product (primary) |
| Engagement | `/engagement` | `mv_user_engagement_scores`, `mv_retention_cohorts`, `mv_onboarding_funnel` (materialized views, daily refresh via pg_cron at 4 AM) | Product (primary) |

**Security notes**:
- All new tables have RLS enabled. No user-facing SELECT policies on admin-only tables (accessed via service role).
- `feature_flags` has an app-facing RPC `get_active_feature_flags()` that uses `hashtext(user_id)` for consistent rollout bucketing.
- `user_reports` allows authenticated INSERT (users report others) and SELECT own reports.
- `user_suspensions` is admin-only; app checks via `is_user_suspended()` RPC.
- `logAdminAction()` now captures `admin_email` and `details` JSONB on all write/bulk actions.
- New WRITE_ACTIONS: `create_feature_flag`, `update_feature_flag`, `delete_feature_flag`, `update_report_status`, `suspend_user`, `lift_suspension`, `create_push_campaign`, `update_push_campaign`.
- New BULK_ACTIONS: `send_push_campaign`.

**SQL migrations**: `supabase/20260327_enhance_audit_log.sql`, `20260327_feature_flags.sql`, `20260327_system_health_rpcs.sql`, `20260327_moderation_system.sql`, `20260327_push_campaigns.sql`, `20260327_engagement_scoring.sql`.

### 2026-03-27: WHOOP Integration — Security Notes

**New OAuth integration**: WHOOP uses standard OAuth 2.0 authorization code flow. Tokens stored in Keychain via `KeychainHelper` (same pattern as Fitbit/Strava). Client ID and secret stored in `Secrets.swift` (gitignored), accessed via `AppConfig.Whoop`.

**Token management**: Access token, refresh token, and expiry stored as `whoop_access_token`, `whoop_refresh_token`, `whoop_token_expires_at` in Keychain. 5-minute pre-expiry refresh window matches Fitbit/Strava pattern. On refresh failure, `disconnect()` clears all tokens.

**OAuth callback**: `fit33://whoop` registered in `DeepLinkManager.swift`. `ASWebAuthenticationSession` handles the browser flow with `callbackURLScheme: "fit33"`.

**Secrets required**: Register at https://developer.whoop.com, add client_id and client_secret to `Secrets.swift`. Template entries added to `Secrets.template.swift`.

**RLS**: `whoop_recovery_data` table has full user-scoped RLS. All Supabase writes are auth-guarded via `SupabaseManager.shared.isAuthenticated`.

**WHOOP data API base (corrected 2026-03-30)**: `AppConfig.Whoop.apiBaseUrl` must be `https://api.prod.whoop.com/developer`. WHOOP OpenAPI (`/developer/doc/openapi.json`) declares `servers[0].url` as that origin. Using `https://api.prod.whoop.com` + `/v2/...` returns ingress **HTTP 404** with body **`default backend - 404`** (no routed backend). OAuth stays on `https://api.prod.whoop.com/oauth/oauth2/auth` and `.../token` (no `/developer`). Removing `/developer` on 2026-03-27 broke production WHOOP sync; restoring `/developer` fixes it.

### 2026-03-28: Content Moderation System

**Two-layer moderation** using OpenAI Moderation API (free) via Edge Function `supabase/functions/moderate-content/index.ts`:
- **Layer 1 (blocking)**: iOS pre-checks chat messages via Edge Function BEFORE sending. Flagged content never stored. `ContentModerationService.swift` calls `moderate-content` with `mode=precheck`. `PrivateChallengeService.sendMessage` returns `SendMessageResult` (`.sent`/`.blocked`/`.error`).
- **Layer 2 (async)**: DB webhook on INSERT fires Edge Function for lower-risk tables. Flags rows with `is_hidden = true`.

**Tables modified**: `private_challenge_chat`, `challenge_reactions`, `shared_workouts`, `group_challenges`, `private_challenges`, `community_challenges`, `friend_activity_feed` all have `is_hidden BOOLEAN DEFAULT FALSE`. `content_moderation_log` stores all flagged content for admin review.

**Rate limiting**: `send_private_challenge_message` enforces max 50 msgs/hour/challenge and 1 msg per 2 seconds (anti-spam burst). Suspension check via `user_suspensions` table added to send RPC.

**Edge Function secret required**: `OPENAI_API_KEY` — set via `supabase secrets set OPENAI_API_KEY=sk-...`

**CMS**: `/moderation` page has new "Flagged" tab showing `content_moderation_log` entries. Admin can Approve (unhide) or Confirm (keep hidden). API actions: `get_flagged_content`, `get_content_moderation_stats`, `review_flagged_content`.

**SQL migration**: `supabase/20260328_content_moderation.sql`.

### 2026-03-28: Supabase Auth — emitLocalSessionAsInitialSession

The supabase-swift SDK prints a deprecation warning twice per launch about `emitLocalSessionAsInitialSession`. Fixed by passing `emitLocalSessionAsInitialSession: true` in `SupabaseClientOptions.AuthOptions` when creating the `SupabaseClient` in `SupabaseManager.init()`. Also added `redirectToURL: URL(string: "fit33://")` for completeness. The new behavior emits the locally stored session immediately (may be expired) instead of waiting for a refresh attempt. Code that listens to `authStateChanges` should check `session.isExpired` if it relies on session validity.

### 2026-03-30: Supabase Storage — `avatars` Bucket Usage Map

The `avatars` bucket serves two purposes:
| Path prefix | Purpose | Uploaded by | DB column |
|-------------|---------|-------------|-----------|
| `profile_photos/{userId}.jpg` | User profile photos | Any authenticated user (own photo) | `user_profiles.profile_photo_url` |
| `challenge_icons/{challengeId}.jpg` | Private challenge icon images | Challenge admin (via direct table UPDATE) | `private_challenges.cover_image_url` |

**Security note**: Storage-level RLS on `avatars` allows any authenticated user to upload. The authorization boundary for challenge icons is the **table-level RLS** on `private_challenges` (`created_by = auth.uid()`), not storage. A user could upload an image to `challenge_icons/` for a challenge they don't own, but the table UPDATE to set the URL would be blocked by RLS. Previous attempt (2026-03-28) to use a separate `private-challenge-photos` bucket caused 15 RLS crashes and was reverted.
