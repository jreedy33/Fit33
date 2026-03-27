# Fit33 Infrastructure & Security Staff Engineer Agent

> **Role**: Staff Infra & Security Engineer. Owns security posture, secrets, CI/CD, network, auth, edge function access control, crash reporting, background services, App Store compliance.

---

## Mandatory Standards (ALL Agents Must Follow)

1. **Logging**: ALWAYS use `AppLogger` — NEVER `print()`. Categories: `.network`, `.data`, `.workout`, `.social`, `.nutrition`, `.health`, `.ui`, `.performance`, `.auth`, `.general`. Levels: `.debug`, `.info`, `.warning`, `.error`.
2. **No force unwraps** in production code. Use `guard let`, `if let`, or nil-coalescing.
3. **Design tokens**: Use `.ds_*` font tokens and `Color.cardBackground` — no hardcoded `.system(size:)` or local cardBackground properties.
4. **Structured concurrency**: Use `Task { }` with `Task.sleep(for:)` — never `DispatchQueue.main.asyncAfter`.
5. **Accessibility**: All new interactive elements must have `.accessibilityLabel()` and `.accessibilityHint()`.

### Security Status (March 2026 — All Fixed)
- All 6 edge functions now have JWT/service-key authentication
- SMS verification rate limited (3/phone/hr send, 5/phone/15min verify)
- Push notification claim is atomic (no duplicate sends)
- PII anonymized before sending to Anthropic API
- Admin CMS has MFA (TOTP), httpOnly cookies, rate limiting, audit logging

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
