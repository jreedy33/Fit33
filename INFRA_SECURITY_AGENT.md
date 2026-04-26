# Fit33 Infrastructure & Security Staff Engineer Agent

> **Role**: Security posture, secrets, CI/CD, network, auth, edge function access control, crash reporting, background services, App Store compliance.
>
> Dated audits, sprint fix lists, deploy notes, and per-integration security reviews live in [`docs/history/INFRA_SECURITY_AGENT.md`](docs/history/INFRA_SECURITY_AGENT.md).

Cross-cutting rules live in `.cursor/rules/codingrules.mdc` (universal), plus scoped rules that auto-load when editing matching files: `.cursor/rules/admin-cms-rules.mdc` (CSP, cookies, R2, Vercel deploys under `admin-cms/**`) and `.cursor/rules/supabase-rules.mdc` (RLS, SECURITY DEFINER, IDOR under `supabase/**/*.sql`).

---

## Invariants (Infra/Security-specific — will leak data / break auth if violated)

### Secrets
1. **Secrets.swift is the ONLY source** for every third-party client ID, client secret, API key. `Secrets.swift` is gitignored. `Secrets.template.swift` is committed with `<PLACEHOLDER>` values and lists every expected key.
2. **No literal credential fallbacks in `AppConfig.swift`.** If `Secrets.swift` is missing, the build fails — that is the intended behavior.
3. **OAuth tokens → Keychain** via `KeychainHelper.swift`, never UserDefaults (Strava, Fitbit, WHOOP, InBody).

### Edge Function auth (MANDATORY; see Registry below)
4. Every new edge function MUST be added to the Edge Function Auth Registry below in the same PR.
5. **`verify_jwt: true` is the Supabase default.** A missing `Authorization` header is rejected by the platform BEFORE function code runs (`{"code":"UNAUTHORIZED_NO_AUTH_HEADER"}`). Custom headers (`x-cron-key`, `x-moderation-secret`) are NEVER sufficient on their own — caller must also send a valid `Authorization: Bearer <JWT>` (service-role for server-to-server, user JWT for iOS). When probing, always test BOTH with and without the custom secret to verify your code path actually runs.
6. **CORS is centralized.** Import `buildCorsHeaders(req)` from `supabase/functions/_shared/cors.ts`. Never `Access-Control-Allow-Origin: *`.
7. **PII redaction in edge logs.** Phones → `redactPhone()` in `supabase/functions/_shared/log.ts` (`+1***-***-1234`). Emails → `j***@gmail.com`. Auth tokens, passwords, payment data → never logged.
8. **"Auth-present" ≠ "auth-correct".** Always ask what bound identity the handler enforces. If the endpoint is cost-sensitive (Twilio / OpenAI / Anthropic) or privileged (`generate-ai-insights`), accepting any valid user JWT is insufficient — use service role or an allow-list table.
9. **SECURITY DEFINER RPC IDOR guard.** Either drop the user-id parameter (use `auth.uid()`), or gate at top: `IF auth.uid() IS NOT NULL AND p_user_id <> auth.uid() THEN RAISE EXCEPTION 'Forbidden' USING ERRCODE = '42501';`. The `auth.uid() IS NOT NULL` clause lets service role / pg_cron through. Smart Adaptive Daily Goals RPCs (`reroll_daily_quest`, `claim_double_xp_day`, `submit_custom_quest`, `unsuppress_quest_category`, `verify_strava_quests_for_today`, `verify_wearable_quests_for_today`, migrations 20260606–20260607) all follow this pattern — they take no `p_user_id` and resolve the caller via `auth.uid()`, returning `{success: false, reason: 'not_authenticated'}` when null. The Pro RPCs additionally require caller-provided `p_is_pro=TRUE` (matches the existing `p_is_subscriber` pattern in `get_daily_quests`); a future migration will swap this for a server-side `is_subscriber()` read once the canonical premium column lands. New per-user tables `user_quest_personalization`, `user_quest_key_stats`, `user_activity_mix`, `user_quest_rerolls`, `user_double_xp_claims` are RLS-pinned to `auth.uid() = user_id` and added to `delete_user_account()` (Supabase invariant 3).
10. **Rate limits for cost-sensitive endpoints must be DB-backed.** In-memory limiters reset on every cold start (every few minutes). Canonical: `check_phone_verification_rate_limit` RPC. In-memory is fine only for abuse-prevention on free APIs.
11. **Never hardcode project refs.** Always `Deno.env.get('SUPABASE_PROJECT_REF')`.

### Silent push + APNs
12. **Silent pushes MUST use `apns-priority: 5`.** APNs silently drops priority-10 silent pushes. Also: `apns-push-type: background`, `aps.content-available: 1`, `apns-expiration: ~+1h`.
13. **Silent pushes skip `push_notification_queue`.** That table is for user-visible alerts (retry + quiet hours). Silent pushes are opportunistic.
14. **Silent-push rate-limit records are internal.** `silent_push_wake_log` is service-role-only; never add a client-readable RLS policy.
15. **Silent-push handler time budget ~30s; per-type self-cap.** `SilentPushHandler.handle(userInfo:completion:)` runs an independent timeout `Task` per push type. Current caps: `strava_activity_new` 25s, `challenge_wake` **15s** (lite path). Exceeding the budget marks the result `.failed` and penalizes our future background-delivery allocation, so caps must be snug enough that timeouts surface real regressions instead of masking them.
15a. **`challenge_wake` runs the LITE path, not the full sync.** `SilentPushHandler.handleChallengeWake` calls `BackgroundChallengeSyncService.performLiteWakeSync()` — HealthKit `syncAllData(force: true)` (Data invariant #46) + `fetchActiveChallenges`/`fetchActiveGroupChallenges` (Data invariant #49) + `syncAllTrackingToChallenges` + private + community sync, ONLY. Strava/Fitbit/WHOOP/Oura/Readiness/meals/hydration/Quests/Intelligence cache stay on the foreground + BGAppRefresh + BGProcessing paths. Bundling them into the wake handler was the dominant timeout cause for users with multiple wearables connected, and none of them affect opponents' view of step / active-min / distance / calorie progress (those flow through HealthKit only — Strava-driven distance still updates because Strava writes to HealthKit). Lite path runs in ~3-7s in the field.
16. **Client-side silent-push calls debounce to 60s per device** (`ChallengeOpponentWakeService` actor). Guard on `(activeChallenges + activeGroupChallenges + privateChallenges).count > 0` and on `SupabaseManager.shared.isAuthenticated`.
17. **New silent-push types get their own case in `SilentPushHandler`.** Don't overload `challenge_wake`.
17a. **Wake diagnostics RPC is the only client-readable surface for `silent_push_wake_log`.** `get_my_wake_diagnostics(p_lookback_hours INT DEFAULT 24, p_timezone TEXT DEFAULT 'UTC')` (migrations `supabase/20260618_wake_diagnostics_rpc.sql` (#118) + `supabase/20260619_wake_diagnostics_progress_drift.sql` (#121)) is `SECURITY DEFINER`, pinned to `auth.uid()`, and only returns wake-log + token + cross-table progress-drift rows for the caller and counterparts in their active 1v1 / group / private challenges. Lookback clamped to [1, 168] hours. Returns first 12 chars of newest valid `device_token` for visual matching only — never the full token. **Cross-table drift columns** (`steps_today_1v1` / `steps_today_private` / `steps_today_community` / `progress_drift_detected`) surface Data invariant #48 regressions directly in the dev menu (the trigger is currently deployed and healthy — verified 2026-04-26 — so the steady state is `progress_drift_detected = FALSE`; any TRUE means the fanout trigger has regressed). Built during the 2026-04-26 "Abbie 0 vs 603" investigation, which turned out to be an upstream sync delay rather than drift — these columns served as the disconfirmation tool. The DEBUG-only `WakeDiagnosticsView` (Fit33/WakeDiagnosticsView.swift, dev menu tab "Wakes") consumes this RPC. **Never** add a client-readable RLS policy to `silent_push_wake_log` itself (invariant #14 still holds); always extend this RPC instead. When extending the drift columns to other fanout types (`active_minutes` / `calories`), repeat the steps_today_* CTE pattern — never expose raw row dumps.

### Background services
18. **`BackgroundChallengeSyncService` throttling model**: per-source last-sync throttle (`perSourceThrottleInterval = 600s` / 10 min, stored under `bg_challenge_last_sync_<source>` in UserDefaults) prevents a single noisy HK source (steps) from starving the others. Workouts flagged high-priority bypass the throttle. BGAppRefreshTask is scheduled with `earliestBeginDate = +15 min`; BGProcessingTask with `+2h`. Concurrent callers coalesce on a single `@MainActor var inFlightSyncTask: Task<Void, Never>?` per QP invariant #24c. Every BGTask expiration handler MUST call `setTaskCompleted(success: false)` AND schedule the next cycle — leaving it dead stops BG wakes until next launch.
19. **`DailyResetService`**: runs at user's local midnight (not UTC). Must be idempotent.

### Info.plist required modes
20. `UIBackgroundModes` MUST include `remote-notification` (silent push) and `fetch` (BGAppRefresh). Missing either → iOS drops our background events.
21. `BGTaskSchedulerPermittedIdentifiers` MUST include every BGTask identifier the app schedules (current: BGAppRefresh id + `com.gofit.app.challengeSyncProcessing`).

### Realtime Widget Server Pull (2026-04-26)
21a. **Supabase session JWT now lives in the App Group, not `UserDefaults.standard`.** `Fit33/SupabaseAppGroupStorage.swift` implements `AuthLocalStorage` against `UserDefaults(suiteName: "group.com.fit33.app")` so the widget extension and the watch app can read the bearer token without re-implementing OAuth. **One-time migration** at app launch in `SupabaseManager.init()` reads any legacy session from `UserDefaults.standard` + Keychain, copies it into the App Group container, then deletes the legacy copy. Trade-off accepted: the App Group `UserDefaults` is sandbox-readable by any process signed with our team ID + `group.com.fit33.app` entitlement (i.e. our widget + watch apps only — NOT third parties). This is the same posture Apple recommends for shared session storage; it is acceptable because (a) the JWT is short-lived (1h refresh), (b) refresh tokens are NOT persisted to App Group, (c) extensions never call refresh — they fail closed when the access token has expired and wait for the host app to refresh. NEVER persist refresh tokens or any other credential into the App Group container. Any extension that mutates the session (writes / deletes) is a security regression — the widget + watch are READ-ONLY consumers.
21b. **Engagement-nudge cron is service-role-only.** `enqueue_engagement_nudges_for_stale_opponents()` (migration #123, schedule `0 * * * *`) is `SECURITY DEFINER` with `GRANT EXECUTE ... TO service_role` — the anon role MUST NEVER be able to enqueue arbitrary `challenge_nudge` rows or attackers could spam any user. The function defers quiet-hours / master-enabled / disabled-type enforcement to `send-push-notification`, so user prefs still gate delivery even though enqueue is server-side. Throttle is enforced in SQL: 24h challenge warm-up, 12h staleness floor, 20h per-(recipient, challenge) — modifying these requires updating both the SQL and the QP test fixtures.

### Admin CMS
22. **Admin session tokens are httpOnly Secure SameSite=Strict cookies.** Never write a client-readable cookie for auth state. The one path middleware skips (`/`) is a server component that reads cookies via `next/headers` + `cookies()` + `redirect()`. Never add `document.cookie.includes(...)` back. Canonical implementation: `admin-cms/src/lib/auth-cookies.ts` (`COOKIE_OPTIONS`).
23. **CSP is set ONLY in `admin-cms/src/middleware.ts`.** Sprint 5 (Q2-20) moved to per-request nonce + `strict-dynamic`; `next.config.ts` intentionally omits `Content-Security-Policy`. When adding a new external media domain (e.g. an R2 bucket in `media-src`) update middleware only. Never re-introduce a static CSP header in `next.config.ts` — two sources fight and silently regress to `'unsafe-inline'`.
24. **R2 video URLs are raw filenames.** Never `encodeURIComponent` on filenames — they contain parentheses `(male)` / `(Dumbbell)` that break.

### App Store compliance (social apps)
25. **User blocking** — `get_blocked_users()` RPC + `BlockedUsersView` in Settings → Privacy & Security, reachable in ≤3 taps from any profile.
26. **Content reporting** — `report_content(p_table_name, p_record_id, p_reported_user_id, p_content_snippet, p_reason)` with `p_table_name` hard-allowlisted. Long-press "Report & Block" on any user-generated content.
27. **Two-layer moderation** — Layer 1 (client precheck via `moderate-content` with user JWT, blocking) + Layer 2 (DB webhook with service-role `Authorization` + `x-moderation-secret`, async, `is_hidden=true`).
28. **Privacy manifest** — `Fit33/PrivacyInfo.xcprivacy` declares Required Reason APIs + `NSPrivacyCollectedDataTypes`. Verify third-party SPM deps also ship manifests (Xcode → Archive → Distribute → Privacy Report).
29. **Accurate feature copy.** OCR label scanner is OCR, never "barcode lookup". Terms, Privacy Policy, Support docs must all match.

---

## Edge Function Auth Registry (canonical)

| Function | Auth method | Rate limit | Secrets | Notes |
|---|---|---|---|---|
| `moderate-content` (precheck) | User JWT OR service role | OpenAI billing | `OPENAI_API_KEY` | Never logs raw content > 500 chars |
| `moderate-content` (webhook) | **BOTH**: service-role `Authorization` (platform) **AND** `x-moderation-secret` (constant-time compare in code) | n/a | `MODERATION_WEBHOOK_SECRET`, `OPENAI_API_KEY`, service-role on DB webhook | Don't remove `Authorization` — platform rejects first |
| `send-verification` | User JWT OR service role | DB-backed `check_phone_verification_rate_limit` (10/hr/phone) + in-memory fallback | `TWILIO_*`, `SUPABASE_SERVICE_ROLE_KEY` | |
| `verify-code` | User JWT OR service role | In-memory (15/15min/phone) | `TWILIO_*` | Client sends session `accessToken`; CORS via shared `buildCorsHeaders` |
| `generate-ai-insights` | Service role OR admin email in `ai_insights_admin_emails` | n/a | `ANTHROPIC_API_KEY`, `SUPABASE_SERVICE_ROLE_KEY` | MUST NEVER accept plain user JWT |
| `usda-food-search` | User JWT OR service role (ALL actions) | Per-IP (30/min) | `USDA_API_KEY` | `search`/`details` anonymous was fixed 2026-04-17 |
| `notify-contacts-user-joined` | User JWT with `auth.uid() === body.new_user_id` (IDOR guard) OR service role | n/a | `SUPABASE_SERVICE_ROLE_KEY` | |
| `send-push-notification` | Service role via `Authorization` OR `x-cron-key` header, both verified against `SUPABASE_PROJECT_REF` env | n/a | `APNS_*`, `SUPABASE_PROJECT_REF` | Also enforces quiet hours + `master_enabled` + `disabled_types` from `user_notification_preferences` |
| `wake-challenge-opponents` | User JWT (auth.uid bound) | 15-min window per recipient via `silent_push_wake_log` | `APNS_*` | Silent push at priority 5 |
| `compute-readiness-insights` | Service role via `Authorization` OR `x-cron-key`, both verified against `SUPABASE_PROJECT_REF` | n/a | `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_PROJECT_REF` | (Wearable Personalization Phase 2a) Nightly pg_cron at 03:30 UTC via `trigger_compute_readiness_insights()`. Computes Spearman correlations per user on `daily_readiness_history` + `workouts` + `meal_logs` + `exercise_personal_records`, upserts 5 correlation types into `user_personalized_insights`. Gated by `sample_size >= 10` AND `p_value <= 0.15`. No user-facing invocation path. |

---

## Principles
1. **Defense in depth** — RLS + app validation. Never rely on one boundary.
2. **Fail secure** — Auth failures log out, never bypass.
3. **Least privilege** — Anon key + RLS. Admin tokens expire. OAuth scopes minimal.
4. **Log without leaking** — `AppLogger` with PII redaction.

---

## Open Security Follow-ups

| Issue | File(s) | Action |
|---|---|---|
| Supabase URL + anon key hardcoded | `SupabaseManager.swift:25-26`, `FoodDatabaseService.swift:265-268` | Move to `Secrets.swift` via `AppConfig` |
| Dev menu password in git | `AppConfig.swift:88` | Remove; use `#if DEBUG` gating only |
| No ATT prompt | `AdManager.swift` | Add ATT flow before AdMob init |
| Admin session in sessionStorage (XSS risk remnants) | `admin-cms/src/lib/auth.ts` | Verify httpOnly everywhere |
| Admin MFA | `admin-cms/src/app/api/auth/login/route.ts` | Enable Supabase MFA (TOTP) |
| Admin rate limits | `admin-cms/src/app/api/admin/route.ts` | Per-endpoint |
| Admin audit log | — | `admin_audit_log` table (done — keep using `logAdminAction` with `details JSONB`) |
| Supabase email verification | Auth > Settings | Enable "Confirm email" |

---

## Owned Files
| File | Purpose |
|---|---|
| `AppConfig.swift`, `Secrets.swift`, `Secrets.template.swift` | Config + secrets |
| `SupabaseManager.swift` (auth sections) | Supabase client + auth |
| `SocialAuthService.swift` | OAuth flows |
| `KeychainHelper.swift` | Secure token storage |
| `Logger.swift` | `AppLogger` |
| `CrashReportingService.swift` | Crash capture (co-owned with Quality) |
| `BackgroundChallengeSyncService.swift` | BG refresh + single HK observer (co-owned with Quality) |
| `DailyResetService.swift` | Midnight reset |
| `PushNotificationService.swift` | APNs tokens + flush |
| `ChallengeOpponentWakeService.swift` | Silent-push client trigger |
| `SilentPushHandler.swift` | Silent-push receiver |
| `AdManager.swift` | Ad SDK + ATT |
| `SECURITY_CHECKLIST.md` | RLS audit (co-owned with Data) |
| `admin-cms/src/lib/auth.ts`, `admin-cms/src/middleware.ts`, `admin-cms/next.config.ts` | Admin auth + CSP |
| `admin-cms/src/app/api/admin/route.ts` | Admin API (service-role gateway) |
| `supabase/functions/` | All edge functions |
| `.github/workflows/` | CI/CD |
| `Fit33/PrivacyInfo.xcprivacy` | Privacy manifest |

---

## Interaction
| Agent | How we interact |
|---|---|
| Design | No direct interaction |
| Product Engineer | Consumes my services (auth state, NetworkMonitor, AppConfig) |
| Data | I define security boundaries; they define schema + queries within them |
| Supabase | They design schema; I harden access control + CORS + IDOR guards |
| Quality | Tests auth/token/offline flows |

---

## See Also
- `SUPABASE_AGENT.md` — RPC contracts, RLS patterns
- `DATA_BACKEND_AGENT.md` — DTOs, migration index
- `.cursor/rules/codingrules.mdc` — cross-cutting rules
- `.cursor/rules/admin-cms-rules.mdc` — Admin CMS security rules (auto-loads for `admin-cms/**`)
- `.cursor/rules/supabase-rules.mdc` — SQL/RLS/IDOR rules (auto-loads for `supabase/**/*.sql`)
- `docs/history/INFRA_SECURITY_AGENT.md` — dated audits, per-integration security reviews

*No credential ships in source code. No API goes unprotected. No admin action goes unlogged. When in doubt, lock it down and ask questions later.*
