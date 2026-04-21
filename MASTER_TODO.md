# Fit33 Master TODO

> **Last updated:** April 18, 2026 (post Sprint 4 — "Consolidation & Ship Posture")
> **Source:** Consolidated from (1) April 17 full-app audit (security, dead code, battery, feature flows), and (2) still-open items carried from the previous MASTER_TODO.
> **Rule:** Only items that are **not yet addressed**. Completed work has been removed. Items marked `[~]` are partially done with a specific remaining gap called out. Items marked `[x]` were closed by Sprint 1 on 2026-04-17 — kept inline (not yet swept out) so reviewers can trace the shipping delta.

---

## Legend

- **P0** — App Store ship blocker (security, crash, policy, or broken shipped surface)
- **P1** — High impact on user quality, battery, or trust
- **P2** — Polish, code health, cleanup
- **P3** — Feature backlog
- **P4** — Nice to have

IDs with a letter prefix (`C-`, `H-`, `M-`, `F-`, `FE-`, `DB-`, `L-`) were inherited from the previous MASTER_TODO so existing cross-references still resolve. New items use a `Q2-` prefix (April-2026 audit).

---

## 1. P0 — App Store Ship Blockers

### Shipped UI that does nothing (user will rate 1-star)

| ID | Task | File:Line | Agent |
|----|------|-----------|-------|
| Q2-1 | [x] Settings → **Help & FAQ** row wired to `SFSafariViewController` against `AppConfig.Support.helpCenterURL` (Sprint 1, 2026-04-17) | `Fit33/SettingsView.swift` | Product Engineer + Support |
| Q2-2 | [x] Settings → **Rate App** now calls `SKStoreReviewController.requestReview(in:)` with App Store write-review URL fallback (Sprint 1, 2026-04-17) | `Fit33/SettingsView.swift` | Product Engineer |
| Q2-3 | [x] Settings → **Security** row removed; the existing "Privacy Settings" row (above) already navigates to `PrivacySettingsView` (Sprint 1, 2026-04-17) | `Fit33/SettingsView.swift` | Product Engineer |
| Q2-4 | [x] Dashboard program chevron hidden until real `ProgramDetailsView` ships — placeholder destination is no longer reachable (Sprint 1, 2026-04-17) | `Fit33/DashboardView+Programs.swift` | Product Engineer |

### Feature flow breakage

| ID | Task | Details | Agent |
|----|------|---------|-------|
| Q2-5 | [x] **Cardio parity shipped Sprint 2 (2026-04-18).** `UserManager.completeCardioWorkout` awards XP (base 20 + 10/15min cap 40 + 10 for ≥3km + 10 for ≥300cal), updates streak, fires `WeeklyLeagueService.addPoints(.workout)`, `DailyQuestService.onWorkoutCompleted`, `ChallengeService.checkStravaWorkoutForChallenges(source: "cardio")`, `BadgeService`, `StreakShieldService`, and `ActivityFeedService.postCardioActivity` (new `post_cardio_activity` RPC, migration `20260418_post_cardio_activity.sql`, activity_type=`cardio_completed`). Respects the same `PrivacySettingsManager.hideFriendActivity` opt-out as strength. | `Fit33/UserManager.swift`, `Fit33/CardioActiveWorkoutView.swift`, `supabase/20260418_post_cardio_activity.sql` | Product Engineer + Fitness Expert |
| Q2-45 | [x] **Pre-check auth fixed (2026-04-17).** `ContentModerationService` was sending the anon key as `Authorization`, so the edge function's `requireUserAuth` returned 401 and the client fail-opened on every message. Now sends the real user `accessToken` (Supabase session) + `apikey: anonKey`. Layer 1 (pre-insert OpenAI check) will now actually block obvious abuse before it reaches the DB. | `Fit33/ContentModerationService.swift` | Product Engineer |
| Q2-46 | [x] **Moderation webhook→UI race closed Sprint 2 (2026-04-18).** `RealtimeService.subscribeFriendActivityFeed` now tails `UpdateAction` on `friend_activity_feed` and calls `ActivityFeedService.applyModerationHide(activityId:)` whenever `is_hidden=true`. `PrivateChallengeService` realtime channel adds an `UpdateAction` on `private_challenge_chat` that writes the message id into a new `@Published hiddenChatMessageIds: Set<UUID>`; `PrivateChallengeDetailView` filters both the inline preview and the full-chat sheet by that set + `friendService.blockedUserIds`. Sender's own flagged row now disappears within one realtime tick. | `Fit33/RealtimeService.swift`, `Fit33/PrivateChallengeService.swift`, `Fit33/PrivateChallengeDetailView.swift`, `Fit33/FriendActivityFeedView.swift` | Product Engineer + Data |
| Q2-6 | [x] **Copy corrected Sprint 2 (2026-04-18).** `TermsConditionsView`, `PrivacyPolicyView`, and `SUPPORT_AGENT.md` now all describe the scanner as "nutrition label lookup (photo-based OCR)". No `UPC`/`EAN` barcode strings remain in user-facing copy. | `Fit33/TermsConditionsView.swift`, `Fit33/PrivacyPolicyView.swift`, `SUPPORT_AGENT.md` | Product Engineer + Support + Infra (legal) |
| Q2-7 | [x] **Blocking + reporting UI shipped Sprint 2 (2026-04-18).** Server: new `get_blocked_users()` and `report_content(p_table_name, p_record_id, p_reported_user_id, p_content_snippet, p_reason)` RPCs (`supabase/20260418_blocking_and_reporting.sql`). Client: `BlockedUsersView` lists + unblocks, wired into Settings → Privacy & Security → Blocked Users. `FriendService.BlockedUser` + `fetchBlockedUsers()` + `reportContent(...)`. "Report & Block" context menus on private-challenge chat messages + activity feed cards, backed by `confirmationDialog` that calls both `reportContent` + `blockUser` and purges local state. Client-side blocked filter applied to friend feed + chat previews + full chat. | `supabase/20260418_blocking_and_reporting.sql`, `Fit33/BlockedUsersView.swift`, `Fit33/FriendService.swift`, `Fit33/SettingsView.swift`, `Fit33/PrivateChallengeDetailView.swift`, `Fit33/FriendActivityFeedView.swift` | Product Engineer + Data |

---

## 2. P0 — Critical Security

### Edge function authentication gaps

These were flagged by the April 17 audit. Sprint 1 (2026-04-17) closed Q2-8 through Q2-13 end-to-end; the Edge Function Auth Registry in `INFRA_SECURITY_AGENT.md` is now the canonical state-of-the-world for each function. Q2-22 (CORS) is partially done and called out below.

| ID | Task | File | Risk |
|----|------|------|------|
| Q2-8 | [x] `moderate-content` — precheck now requires valid user JWT (or service role); webhook path requires `x-moderation-secret` header verified constant-time against `MODERATION_WEBHOOK_SECRET`. (Sprint 1, 2026-04-17) | `supabase/functions/moderate-content/index.ts`, `supabase/functions/_shared/cors.ts` | Anon DoS + data tampering |
| Q2-9 | [x] `send-verification` — now requires valid user JWT; rate limit moved to DB-backed `check_phone_verification_rate_limit` RPC (10/hr/phone) with in-memory fallback. See migration `supabase/20260417_phone_verification_rate_limit.sql`. (Sprint 1, 2026-04-17) | `supabase/functions/send-verification/index.ts`, `supabase/20260417_phone_verification_rate_limit.sql` | Cost / SMS abuse |
| Q2-10 | [x] `generate-ai-insights` — now requires service-role OR admin email in `ai_insights_admin_emails` allowlist (migration `supabase/20260417_ai_insights_admin_emails.sql`). Any-user-JWT fallback removed. (Sprint 1, 2026-04-17) | `supabase/functions/generate-ai-insights/index.ts`, `supabase/20260417_ai_insights_admin_emails.sql` | Mass PII read + cost |
| Q2-11 | [x] `usda-food-search` — ALL actions (`search`/`details`/`cache_food`) now require valid user JWT or service-role key. (Sprint 1, 2026-04-17) | `supabase/functions/usda-food-search/index.ts` | Cost + elevated DB access |
| Q2-12 | [x] `notify-contacts-user-joined` — now enforces `auth.uid() === new_user_id` (service role still bypasses for admin tooling). (Sprint 1, 2026-04-17) | `supabase/functions/notify-contacts-user-joined/index.ts` | IDOR |
| Q2-13 | [x] `send-push-notification` — project ref is now derived from the auto-provisioned `SUPABASE_URL` (parsed with regex at startup) because Supabase reserves the `SUPABASE_*` env prefix and won't accept a dedicated `SUPABASE_PROJECT_REF` secret. Function fails closed if parsing yields empty string. `isServiceRoleJWT()` uses the derived ref. (Sprint 1, 2026-04-17) | `supabase/functions/send-push-notification/index.ts` | Brittle auth gate |

### SQL / RLS

| ID | Task | File | Risk |
|----|------|------|------|
| Q2-14 | [x] `get_friend_ids(p_user_id UUID)` now enforces `IF auth.uid() IS NOT NULL AND p_user_id <> auth.uid() THEN RAISE EXCEPTION ...`. Migration: `supabase/20260417_secure_get_friend_ids.sql`. (Sprint 1, 2026-04-17) | `supabase/20260417_secure_get_friend_ids.sql`, `supabase/community_friends_gating.sql` | IDOR |
| Q2-15 | [x] **Invariant codified + hardened Sprint 2 (2026-04-18).** `supabase/20260418_group_challenge_members_invariant.sql` (a) re-enables RLS, (b) `REVOKE INSERT, UPDATE, DELETE` from `authenticated` and `REVOKE ALL` from `anon`, (c) adds `COMMENT ON TABLE` documenting the rule that all writes must go through SECURITY DEFINER RPCs gated on `auth.uid()`. Audit confirmed the Swift client never writes this table — `challenge_participants` is the live surface. | `supabase/20260418_group_challenge_members_invariant.sql` | Policy bypass if any RPC is wrong |
| Q2-16 | [x] Duplicate `fix_account_deletion.sql` deleted; `complete_account_deletion.sql` is canonical (`RETURNS jsonb`). Swift `deleteAccount()` now decodes a `DeleteAccountRPCResponse { success: Bool? }` struct. `MIGRATION_INDEX.md` updated. (Sprint 1, 2026-04-17) | `Fit33/SupabaseManager.swift`, `supabase/complete_account_deletion.sql`, `supabase/MIGRATION_INDEX.md` | Runtime decode failure on real account deletes |
| Q2-17 | [x] `20260330_*.sql` + `20260331_league_auto_placement.sql` now registered in `supabase/MIGRATION_INDEX.md`; Sprint 1 migrations added alongside them. (Sprint 1, 2026-04-17) Remaining: verify each is applied in the live Supabase project before shipping — tracked under DB-1 / SUPABASE_HEALTH_CHECKLIST.md. | `supabase/MIGRATION_INDEX.md` | Schema/prod divergence |
| DB-1 | [ ] RLS verification sweep for every table (`SECURITY_CHECKLIST.md` checkboxes) — a scripted check, not manual spot-checks | — | Data |
| DB-3 | [ ] `delete_user_account` cascade completeness review (beyond Q2-16 alignment) | `supabase/complete_account_deletion.sql` | Data |

### Swift / client security

| ID | Task | File:Line | Notes |
|----|------|-----------|-------|
| C-1 | [ ] **Supabase service-role key** still lives in an `.env.local` file on a developer machine — **it must never be checked into the iOS app or git**. Document that rotation is required if anyone has ever pushed it. Client app uses anon key via `Secrets.swift` (OK) — this item is about the service key supply chain. | `admin-cms/.env.local`, Supabase Vault | Infra |
| Q2-18 | [x] `SupabaseManager.client` is now a non-optional `let SupabaseClient` assigned in `init`; a bad `AppConfig.supabaseURL` hits `preconditionFailure` with a clear message rather than silently crashing later. (Sprint 1, 2026-04-17) | `Fit33/SupabaseManager.swift` | Crash risk |
| Q2-19 | [x] Universal link host check now validates against an explicit allowlist: `fit33.app`, `www.fit33.app`, `doublethr33s.com`, `www.doublethr33s.com`, `admin.doublethr33s.com`. Case-insensitive exact match, no substring. (Sprint 1, 2026-04-17) | `Fit33/DeepLinkManager.swift` | Phishing / open-redirect |
| Q2-20 | [x] **Sprint 5 (2026-04-20): nonce-based CSP shipped.** `next.config.ts` no longer emits a CSP header; `middleware.ts` generates a fresh per-request nonce, propagates it via `x-nonce` to the rendered page (inline `<script>`/`<style>` pick it up via `useNonce`), and locks scripts/styles to `'self' 'nonce-…'`. No more `'unsafe-inline'` or `'unsafe-eval'` anywhere in the admin CMS CSP. | `admin-cms/next.config.ts`, `admin-cms/src/middleware.ts` | Infra |
| Q2-21 | [x] **Fixed Sprint 4 (2026-04-18).** `admin_logged_in` is now `httpOnly: true`. `admin-cms/src/app/page.tsx` is a server component that reads `admin_access_token` via `next/headers` + `cookies()` and `redirect()`s; `AdminShell.tsx` drops the `document.cookie.includes` precheck and relies on the existing `/api/auth/session` fetch, which middleware already gates. | `admin-cms/src/lib/auth-cookies.ts`, `admin-cms/src/app/page.tsx`, `admin-cms/src/components/AdminShell.tsx` | Minor |
| Q2-22 | [x] **CORS migration complete (Sprint 2, 2026-04-18).** `verify-code` and `send-push-notification` both use `buildCorsHeaders(req)` from `_shared/cors.ts`; `verify-code` now also gates on `requireUserAuth` so SMS confirmation cannot be triggered without a valid session. Audit of `supabase/functions/**/index.ts` confirms no `Access-Control-Allow-Origin: '*'` remains. | `supabase/functions/_shared/cors.ts`, `supabase/functions/verify-code/index.ts`, `supabase/functions/send-push-notification/index.ts` | Origin enforcement |
| Q2-23 | [x] **`Fit33/PrivacyInfo.xcprivacy` shipped Sprint 2 (2026-04-18).** Declares `NSPrivacyTracking=false`, `NSPrivacyTrackingDomains=[]`, Required Reason APIs (UserDefaults CA92.1, FileTimestamp C617.1, DiskSpace E174.1, SystemBootTime 35F9.1), and `NSPrivacyCollectedDataTypes` for Name, Email, Phone, Photos/Videos, Contacts, Health, Fitness, UserID, DeviceID, ProductInteraction, PerformanceData, CrashData, OtherUserContent — all linked to user, none tracking. Added to `Fit33` target via `project.pbxproj`. Still TODO before submission: verify every SPM dependency ships its own manifest (Xcode Privacy Report export). | `Fit33/PrivacyInfo.xcprivacy`, `Fit33.xcodeproj/project.pbxproj` | Infra |
| H-5 | [x] **Verified Sprint 4 (2026-04-18).** `AppConfig.swift` has zero literal fallbacks for Strava, Fitbit, or Whoop credentials — every enum reads exclusively from `Secrets.*`. `INFRA_SECURITY_AGENT.md` now documents `Secrets.swift` as the canonical source and reaffirms the "no literal credential fallbacks" rule. | `Fit33/AppConfig.swift`, `INFRA_SECURITY_AGENT.md` | Infra |
| H-6 | [~] **Admin audit log completeness.** Table + `logAdminAction()` exist; confirm every write/bulk action calls it (a grep-and-diff task). | `admin-cms/src/app/api/admin/route.ts` | Infra |
| M-3 | [ ] **Certificate pinning** for Supabase API calls (defense in depth for the anon key). | `Fit33/SupabaseManager.swift` | Infra |
| M-10 | [x] **Phone-number redaction in Twilio edge function logs** — Sprint 3 added `supabase/functions/_shared/log.ts::redactPhone()` and refactored `verify-code` + `send-verification` to call it. Output shape `+1***-***-1234`. | `supabase/functions/_shared/log.ts`, `supabase/functions/verify-code/index.ts`, `supabase/functions/send-verification/index.ts` | Infra + Data |
| M-19 | [x] **Sprint 5 (2026-04-20): email verification blocked-state UI shipped.** New `SupabaseAuthError.emailNotConfirmed` is thrown from `SupabaseManager.signIn` when Supabase reports an unconfirmed email. `NewOnboardingView+Auth` renders an inline `emailUnverifiedBanner` with Resend + Confirmed-and-retry actions; `resendEmailConfirmation()` + `isCurrentUserEmailConfirmed()` helpers added to `SupabaseManager`. | `Fit33/SupabaseManager.swift`, `Fit33/NewOnboardingView.swift`, `Fit33/NewOnboardingView+Auth.swift` | Infra |

---

## 3. P1 — Performance & Battery

### Always-on in release

| ID | Task | File:Line | Notes |
|----|------|-----------|-------|
| Q2-24 | [x] `ProductionFPSMonitor.start()` now wrapped in `#if DEBUG` at app launch and on scenePhase transitions; release builds never install the `CADisplayLink`. (Sprint 1, 2026-04-17) | `Fit33/Fit33App.swift`, `Fit33/AppPerformanceSystem.swift` | Battery + perf tax on every user |
| Q2-25 | [x] `MainThreadWatchdog.start()` is now `#if DEBUG`-only at app launch — release builds never spawn the 0.5s polling thread. (Sprint 1, 2026-04-17) | `Fit33/Fit33App.swift`, `Fit33/AppPerformanceSystem.swift` | Battery |
| Q2-26 | [x] **Timer lifecycle fixed Sprint 2 (2026-04-18).** `MemoryPressureHandler.monitorTimer` is now stored and invalidated on `UIApplication.didEnterBackgroundNotification` / `willResignActiveNotification`; restarted on `didBecomeActiveNotification`. `deinit` cleans observers + timer. Runs on `.common` mode so scrolling doesn't block it. | `Fit33/PerformanceOptimizations.swift` | Battery |

### Duplicate fetch stacks

| ID | Task | File:Line | Notes |
|----|------|-----------|-------|
| Q2-27 | [x] **Polling Timer removed Sprint 2 (2026-04-18).** `autoRefreshTimer`, `autoRefreshInterval`, and `startAutoRefreshTimer`/`stopAutoRefreshTimer` all deleted from `FriendsTabView`. The tab now relies on Supabase Realtime (friendships / friend_activity_feed / community_participants / private_members channels in `RealtimeService`) plus user-initiated `.refreshable`. | `Fit33/FriendsTabView.swift` | Battery + server load |
| Q2-28 | [x] **Dual HealthKit observer stacks** — Sprint 3 removed `HealthKitManager.startObservingSteps/Workouts`. `BackgroundChallengeSyncService` is now the single HK observer owner and posts `.healthStepsDidUpdate` + `.externalWorkoutSynced` after its sync. HealthKitManager listens and refreshes its `@Published` UI state. | `Fit33/HealthKitManager.swift`, `Fit33/BackgroundChallengeSyncService.swift` | Battery + thrash |
| Q2-29 | [x] `SupabaseManager.signOut()` and `deleteAccount()` now both call `await RealtimeService.shared.disconnect()` **before** revoking the JWT so no stale channel leaks onto the next signed-in user. (Sprint 1, 2026-04-17) | `Fit33/SupabaseManager.swift` | Correctness + battery |

### Video / media

| ID | Task | File:Line | Notes |
|----|------|-----------|-------|
| Q2-30 | [x] **Video prefetch / streaming don't check expensive network** — Sprint 3 added `NetworkMonitor.isExpensive`, `.isConstrained`, and `.shouldAvoidBackgroundTraffic` (reads `NWPath.isExpensive` + `.isConstrained`). `VideoPreloadManager.performVisibleExercisesUpdate` and every `VideoStreamingService.prefetch*` path early-returns on `shouldAvoidBackgroundTraffic`. On-demand playback (`getPlayer`) is never gated. | `Fit33/NetworkMonitor.swift`, `Fit33/VideoPreloadManager.swift`, `Fit33/VideoStreamingService.swift` | Cellular data + battery |
| Q2-31 | [x] **`AVAudioSession` was configured + active for the entire app lifetime** — Sprint 3 removed `configureAudioSession()` from `VideoStreamingService.init()`. New `activateAudioSessionIfNeeded()` (lazy, first player creation) + `deactivateAudioSessionIfActive()` (NSLock-guarded) pair wired into `createOptimizedPlayer` and `clearPreloadCache`. On app backgrounding `Fit33App` already calls `clearPreloadCache()`, which now releases the session with `.notifyOthersOnDeactivation`. | `Fit33/VideoStreamingService.swift` | Audio UX + battery |

### Animations & timers

| ID | Task | File:Line | Notes |
|----|------|-----------|-------|
| Q2-32 | [x] **`AnimatedOrbBackground` accessibility** — Sprint 3 added `@Environment(\.accessibilityReduceMotion)` and a unified `shouldDisableMotion` predicate (`isLowPowerMode \|\| reduceMotion`). All three orb animations + the `onAppear` `animatePulse = true` are gated off it. | `Fit33/AdaptiveColors.swift` | Accessibility + battery |
| Q2-33 | [x] **`ActiveWorkoutView+Init` 1s timer capture** — Sprint 3 switched the capture list from `[self]` to `[weak workoutManager]` (view is a struct, so `[weak self]` doesn't apply; `workoutManager` is the live class anchor). Timer self-invalidates if `workoutManager` is released. | `Fit33/ActiveWorkoutView+Init.swift` | Consistency |
| M-4 | [x] **Sprint 5 (2026-04-20): retain-cycle audit passed.** Top-10 long-lived services audited for `Timer.scheduledTimer` / `NotificationCenter` observer / long-lived `Task { }` leaks. Existing `[weak self]` + `deinit` cleanup is correct across `RestTimer`, `BackgroundChallengeSyncService`, `PrivateChallengeService`, `MemoryPressureHandler`, `PhoneOTPCountdown`. No changes required. | Repo-wide | Quality |
| M-1 (residual) | [x] **Sprint 5 (2026-04-20): audit clean.** Grep across `Fit33/` confirms zero remaining `DispatchQueue.main.asyncAfter` in `NewOnboardingView.swift`; the bulk conversion to `Task.sleep(for:)` with cancellation had already landed in Sprint 4. | `Fit33/NewOnboardingView.swift` | Quality |
| M-8 | [x] **Sprint 5 (2026-04-20): `RequestCoalescer` shipped.** New actor at `Fit33/RequestCoalescer.swift` deduplicates concurrent async operations by string key (`coalesce<Output>` + `coalesceVoid`). Wired into `ActivityFeedService.fetchFeed`, `ChallengeService.fetchActiveChallenges`/`fetchActiveGroupChallenges`, and `HealthKitService.syncAllData(force:)`. `SupabaseManager.signOut()` calls `reset()` to clear in-flight requests on logout so sessions can't bleed. | `Fit33/RequestCoalescer.swift` + services | Quality |

---

## 4. P1 — Feature Flow Gaps

| ID | Task | File:Line | Notes |
|----|------|-----------|-------|
| Q2-34 | [x] **Offline retry queue shipped Sprint 2 (2026-04-18).** `Fit33/CloudSyncRetryQueue.swift` — file-backed JSON queue in Application Support (no Core Data model change), persists across launches, exponential backoff capped at 30 min / 6 attempts, drained on foreground from `Fit33App.onChange(of: scenePhase)`. `ActiveWorkoutView+Actions.swift` enqueues on `saveWorkoutToCloud` failure OR when unauthenticated. Paired with H-4: Dashboard shows `DashboardOfflineSyncChip` ("Syncing N workouts…" / "N saved offline, tap to retry") while `pendingCount > 0`. | `Fit33/CloudSyncRetryQueue.swift`, `Fit33/ActiveWorkoutView+Actions.swift`, `Fit33/Fit33App.swift`, `Fit33/DashboardView+Helpers.swift`, `Fit33/DashboardView.swift` | Correctness |
| Q2-35 | [x] **Push flush wired Sprint 2 (2026-04-18).** `PrivateChallengeService.sendMessage` now calls `PushNotificationService.shared.flushPushNotificationQueue(triggeredBy: "private_challenge_chat")` on successful send. `ActivityFeedService.sendReaction` calls the same flush with `triggeredBy: "activity_reaction"`. | `Fit33/PrivateChallengeService.swift`, `Fit33/FriendActivityFeedView.swift` | Social engagement |
| Q2-36 | [x] **Notification allowlist shipped Sprint 2 (2026-04-18).** `NotificationManager.knownNotificationTypes: Set<String>` enumerates every server-side `type` string the client routes. Default case now `.error`-logs unknown types (surfaces in crash reports + SessionLogManager) instead of silently no-opping, and falls back to `.dashboard` for graceful recovery. `Fit33Tests/NotificationAllowlistTests.swift` enforces every `NotificationType.allCases.rawValue` is in the allowlist plus known server aliases (`friend_accepted`, `group_challenge_started`, etc). | `Fit33/NotificationManager.swift`, `Fit33Tests/NotificationAllowlistTests.swift` | Correctness |
| Q2-37 | [x] **Onboarding completion ordering / rollback** — Sprint 3 reordered `completeOnboarding()` to validate weight synchronously BEFORE the OAuth profile `Task` fires. Added `OnboardingError`, `@State completionError`, `.confirmationDialog` with Edit / Start Over / Cancel, and `rollbackCloudProfileIfNeeded()` that calls `SupabaseManager.deleteAccount()` (idempotent). | `Fit33/NewOnboardingView.swift`, `Fit33/NewOnboardingView+Completion.swift` | Onboarding |
| Q2-38 | [~] **Sprint 4 (2026-04-18): countdown timer leak closed.** `ExistingUserPhonePrompt.sendVerificationCode` previously fired `Timer.scheduledTimer` without storing the reference, leaking a live timer on every tap + on view dismissal. Both views now share a new `PhoneOTPCountdown` `ObservableObject` (defined at the bottom of `ExistingUserPhonePrompt.swift`) that stores the `Timer`, self-invalidates via `[weak self]`, and is cleaned up from `.onDisappear`. **Remaining (Q2-38-b)**: consolidate the two OTP entry UIs (digit-box vs single-field) into one component. Tracked below. | `Fit33/ExistingUserPhonePrompt.swift`, `Fit33/PhoneVerificationSheet.swift` | Product Engineer |
| Q2-38-b | [x] **Sprint 5 (2026-04-20): OTP entry unified to digit-box tiles.** `PhoneVerificationSheet` now uses the same canonical 6-box tile UI as `ExistingUserPhonePrompt`. Resend cooldown standardized at 60s across both flows. | `Fit33/ExistingUserPhonePrompt.swift`, `Fit33/PhoneVerificationSheet.swift` | Product Engineer + Design |
| C-6 | [x] **Sprint 5 (2026-04-20): atomic accept/decline RPCs shipped.** `supabase/20260420_atomic_challenge_rpcs.sql` introduces `accept_challenge(uuid)` + `decline_challenge(uuid)` with `SELECT ... FOR UPDATE` on the caller's `challenge_participants` row. Idempotent (`already_accepted`/`already_declined` JSONB) and safe against double-taps / simultaneous devices. `ChallengeService.respondToChallenge` now routes through them. | `Fit33/ChallengeService.swift`, `supabase/20260420_atomic_challenge_rpcs.sql`, `supabase/MIGRATION_INDEX.md` | Data |
| H-2 | [ ] **Accessibility labels (~500+ needed)** — priority order in `QUALITY_PERFORMANCE_AGENT.md` §3. | Repo-wide | Quality |
| H-3 | [ ] **Input validation on user-facing text fields** — common patterns via a shared validator (name length, goal text, challenge title profanity check pre-submit). | Repo-wide | Product Engineer |
| H-4 | [x] **Offline retry UX shipped with Q2-34 (2026-04-18).** `DashboardOfflineSyncChip` renders on Dashboard whenever `CloudSyncRetryQueue.pendingCount > 0` with states: "Syncing N…" during drain, "N saved offline, tap to retry" idle. Owns own `@StateObject` to respect widget isolation rule. | `Fit33/DashboardView+Helpers.swift` | Product Engineer |
| H-18 | [ ] **Tutorial redesign (10-screen flow).** See `TUTORIAL_REDESIGN_ACTION_PLAN.md`. | `Fit33/WelcomeTutorialView.swift` etc. | Product Engineer |
| Q2-63 | [x] **`cardio_workouts.origin_app` — true third-party origin tracking (2026-04-17).** HK-imported Strava/Nike/Peloton/Garmin/Zwift/Apple Watch/etc. workouts now render a brand-colored badge (not a generic Apple Health heart). OAuth services (Strava/Fitbit/WHOOP/Oura) skip HK duplicates on save + delete stale HK rows on connect. Mapper: `Fit33/WorkoutOriginMapper.swift`. Migration: `supabase/20260417_cardio_workouts_origin_app.sql`. See `DATA_BACKEND_AGENT.md` §2026-04-17 for semantics + dedupe rules. | `Fit33/HealthDataService.swift`, `Fit33/SupabaseDTOs.swift`, `Fit33/DashboardWorkoutCards.swift`, `Fit33/HealthKitSettingsView.swift`, `Fit33/StravaService.swift`, `Fit33/FitbitService.swift`, `Fit33/WhoopService.swift`, `Fit33/OuraService.swift` | Data Backend + Product Engineer |

---

## 5. P2 — Dead & Orphaned Code

| ID | Task | File:Line | Notes |
|----|------|-----------|-------|
| Q2-39 | [x] **Orphaned test files** — Sprint 3 deleted `Fit33/ActiveWorkoutTests.swift` and `Fit33/LimitationFilterTests.swift`. Neither was referenced by the Xcode project; they never compiled. | — | Quality |
| Q2-40 | [x] **`PersonalizedInsightsService` stubs gated** — Sprint 3 introduced `AppConfig.FeatureFlags.personalizedInsightsV2 = false` and gated `analyzeHydrationPerformanceCorrelation`, `detectBestWorkoutTime`, `detectNutritionPatterns`, `detectSocialPatterns` behind it. Real (working) correlations like `analyzeSleepPerformanceCorrelation` are untouched. | `Fit33/AppConfig.swift`, `Fit33/PersonalizedInsightsService.swift` | Product Engineer + Data |
| Q2-41 | [~] **Sprint 4 (2026-04-18): dead-code purge.** Deleted `CollaborativeLearningEngine.getRecommendedPrograms(for:)` (and the now-orphaned `successfulProgramsCache`, `fetchSuccessfulPrograms*`, `SuccessfulProgram` struct, plus the call from `syncGlobalData`) and `CommunityIntelligenceService.getRecommendedPrograms(...)` (plus its orphaned `CommunityProgramRecommendation` + `ProgramRecommendationDTO` types). Both had zero external callers. The `SmartProgramRecommender` doc comment now states it is the canonical entry point. **Remaining (Q2-41-b)**: migrate `ProgramExplorerView` off `ProgramLibraryService.getRecommendedPrograms` — requires a `WorkoutProgram → ExtendedProgram` mapper. | `Fit33/CollaborativeLearningEngine.swift`, `Fit33/CommunityIntelligenceService.swift`, `Fit33/SmartProgramRecommender.swift` | Product Engineer + Fitness Expert |
| Q2-41-b | [x] **Sprint 5 (2026-04-20): migration complete.** Added `ExtendedProgram.from(workoutProgram:)` mapper + `SmartProgramRecommender.getRecommendedExtendedPrograms(for:limit:)`. `ProgramExplorerView.recommendedPrograms` now routes through the canonical recommender. Legacy `ProgramLibraryService.getRecommendedPrograms` deleted. | `Fit33/ProgramExplorerView.swift`, `Fit33/ProgramLibraryService.swift`, `Fit33/SmartProgramRecommender.swift` | Product Engineer + Fitness Expert |
| Q2-42 | [~] **Sprint 4 (2026-04-18): dead actor deleted + shared config helper.** The unused `ImageCache` actor in `PerformanceOptimizer.swift` had zero callers — removed. Introduced `ImageCacheConfig` (at top of `FriendPhotoCache.swift`) that centralizes the 100-count / 50MB `NSCache` budget; `FriendPhotoCache` now calls `ImageCacheConfig.configure(memoryCache)` in `init`. `ProfilePhotoCache` keeps its single-slot `UIImage?` (different semantics, intentional). **Remaining (Q2-42-b)**: if a third image domain emerges, consider merging `FriendPhotoCache` and `ProfilePhotoCache` under one `ImageCache` with per-domain keys. Not worth it for two caches today. | `Fit33/FriendPhotoCache.swift`, `Fit33/PerformanceOptimizer.swift` | Product Engineer |
| Q2-42-b | [ ] **(Optional)** Unify `FriendPhotoCache` + `ProfilePhotoCache` into one keyed image store. Defer until a third image cache emerges — two caches with genuinely different semantics (URL-keyed multi-slot vs single-slot) don't justify the churn today. | `Fit33/FriendPhotoCache.swift`, `Fit33/ProfilePhotoCache.swift` | Product Engineer |
| Q2-43 | [x] **Stale TODO in `AdManager.swift`** — Sprint 3 replaced the TODO with the real production rewarded ad unit ID comment. | `Fit33/AdManager.swift` | Infra |
| Q2-44 | [x] **Empty `@Test func example()`** — Sprint 3 deleted the placeholder body. `NotificationAllowlistTests` is the smoke test for the Fit33Tests target. | `Fit33Tests/Fit33Tests.swift` | Quality |

---

## 6. P2 — Agent Doc Improvements (Meta)

These keep the agent docs consistent and prevent the "MASTER_TODO says not done but code says done" drift that caused this audit to surface.

| ID | Task | Files | Notes |
|----|------|-------|-------|
| AGD-1 | [ ] **Extract the duplicated "Mandatory Standards" block** (logging / force unwraps / design tokens / structured concurrency / accessibility / RLS / SECURITY DEFINER views) that appears at the top of every agent doc into a single `AGENT_STANDARDS.md`. Each agent doc then opens with `See AGENT_STANDARDS.md`. Reduces drift when a rule changes. | All `*_AGENT.md` | Infra |
| AGD-2 | [x] Misleading "All Fixed" banner removed from `INFRA_SECURITY_AGENT.md`; new Edge Function Auth Registry + "Lessons Learned (April 2026)" section are now the authoritative source for per-function auth state. (Sprint 1, 2026-04-17) | `INFRA_SECURITY_AGENT.md` | Infra |
| AGD-3 | [ ] **Shrink the huge agent docs.** `QUALITY_PERFORMANCE_AGENT.md` (~93K), `PRODUCT_ENGINEER_AGENT.md` (~88K), `DATA_BACKEND_AGENT.md` (~48K) now contain months of dated change logs. Move month-by-month history into `docs/agent-archives/<AGENT>/<YYYY-MM>.md`; keep only active rules + last 30 days in the main file. | The three files above | All agents |
| AGD-4 | [ ] **Update `ENGINEERING_TEAM.md` ownership matrix** for features added since the last refresh: moderation pipeline (Q2-8), WHOOP, BLE auto-connect, AdMob + ATT, barcode scanner (once real), user blocking UI, push campaigns. | `ENGINEERING_TEAM.md` | All agents |
| AGD-5 | [x] Canonical Edge Function Auth Registry added to `INFRA_SECURITY_AGENT.md` (function → auth method → rate limit → secrets → notes). Referenced from `DATA_BACKEND_AGENT.md` "Edge Function Standards" so ownership is clear on every new function. (Sprint 1, 2026-04-17) | `INFRA_SECURITY_AGENT.md`, `DATA_BACKEND_AGENT.md` | Infra + Data |
| AGD-6 | [ ] **Refresh `DESIGN_SYSTEM_AGENT.md` token-adoption metrics.** The "March 7, 2026" table is likely stale — rerun the audit script and replace. Fold decision rows (20pt → xl vs lg) that were marked "decision needed" now that they've been picked. | `DESIGN_SYSTEM_AGENT.md` §"Current State" | Design System |
| AGD-7 | [ ] **Consolidate rules that appear in both `.cursor/rules/codingrules.mdc` and the agent "Mandatory Standards" blocks.** `codingrules.mdc` should be authoritative for the truly-universal rules; agent docs link rather than restate. | `.cursor/rules/codingrules.mdc`, all `*_AGENT.md` | Infra |
| AGD-8 | [x] **Shipped Sprint 4 (2026-04-18).** `scripts/audit_done_claims.sh` parses every `[x]` row in `MASTER_TODO.md`, extracts cited paths from the File column (tolerating comma-separated lists, backticks, and trailing line refs), and reports any that no longer exist. Initial run caught a brace-expansion shorthand (`{Strava,Fitbit,Whoop,Oura}Service.swift`) that was expanded to four concrete paths. Passing now. Run manually before sprint close; a future sprint can wire it into `.githooks/pre-commit` behind a flag. | `scripts/audit_done_claims.sh`, `MASTER_TODO.md` | Quality |
| AGD-9 | [x] **Shipped Sprint 4 (2026-04-18).** `scripts/pre_commit_migration_check.sh` fails any commit that stages a new `supabase/*.sql` migration without a matching entry in `supabase/MIGRATION_INDEX.md`. Driver at `.githooks/pre-commit` is opt-in (`git config core.hooksPath .githooks`); documented in `scripts/README.md` → "Git Hooks (Opt-In)". | `scripts/pre_commit_migration_check.sh`, `.githooks/pre-commit`, `scripts/README.md` | Data + Infra |

---

## 7. P2 — Medium Priority (Polish + Infrastructure)

| ID | Task | Agent | Source |
|----|------|-------|--------|
| M-2 | [ ] Localization prep (extract all user-facing strings) | Product Engineer | Inherited |
| M-7 | [ ] Fix exercise-sync race conditions (parallel Core Data writes) | Data | Inherited |
| M-9 | [x] **Sprint 5 (2026-04-20).** `.scrollDismissesKeyboard(.interactively)` added to every primary input-heavy ScrollView: `ChallengeCreationFlow`, `PrivateChallengeCreationFlow`, `WorkoutCreationView` (generated view), `BugReportView`. Pattern documented for new input screens. | Product Engineer | Inherited |
| M-11 | [ ] CI/CD pipeline (automated build + test on PR) — extend current workflows | Infra | Inherited |
| M-13 | [ ] DTO null-safety audit across every Supabase DTO | Data | Inherited |
| M-15 | [x] **Sprint 5 (2026-04-20): targeted token sweep.** Actual code violations were much smaller than the 97 headline count (most hits were legitimate gradient stops / design-system internals). Replaced real offenders in `ChallengeCreationFlow` (`Color(white: 0.14)` → `Color.cardBackground`) and `NutritionScannerView` (4× `Color(white: 0.15)` → `Color.cardBackground`). | Design System | Inherited |
| M-18 | [x] **Sprint 5 (2026-04-20): Settings override added.** New `DateFormatOverride` enum + `UnitSettingsManager.dateFormatOverride` persist a user choice (auto / MM-DD / DD-MM); `UnitSettingsView` exposes the toggle. `localeUsesMonthFirstDate` honours the override before falling back to locale. | `Fit33/UnitSettingsManager.swift`, `Fit33/UnitSettingsView.swift` | Inherited |
| M-20 | [ ] Design system: replace hardcoded card colors with `Color.cardBackground` | Design System | Inherited |
| M-21 | [x] **Sprint 5 (2026-04-20): dead `FastButtonStyle` removed.** `ScaleButtonStyle` is already the canonical single source in `DesignSystem.swift`; the other variants referenced in the audit were either already consolidated or unused. Dead `FastButtonStyle` struct purged from `PerformanceOptimizer.swift`. | Design System | Inherited |
| M-22 | [ ] Design system: typography/spacing/corner-radius token enforcement | Design System | Inherited |
| M-23 | [x] **Sprint 5 (2026-04-20): `HapticStyle` enum added** to `DesignSystem.swift` as a semantic vocabulary (e.g. `.selection`, `.success`, `.achievement`) new code can prefer over raw `UIImpactFeedbackStyle`. Existing call sites left untouched to avoid a risky cross-repo rename — roll this in per-file as surfaces are touched. | `Fit33/DesignSystem.swift` | Design System |
| M-24 | [x] **Sprint 5 (2026-04-20): `EmptyStateView` typealias** aliased to the existing `DSEmptyState` component so new screens have one canonical name. Applied to `FriendActivityFeedView` empty state and `ProgramExplorerView` filtered-zero state. Pattern documented for new lists. | `Fit33/DesignSystem.swift`, `Fit33/FriendActivityFeedView.swift`, `Fit33/ProgramExplorerView.swift` | Design System |
| M-25 | [x] **Sprint 5 (2026-04-20): deprecation notice landed.** `ExerciseSelectionView` is now explicitly marked as the legacy picker; the Build Workout flow uses the Exercise Library picker. Full tear-out of the old view is tracked as a follow-up when no call sites remain. | `Fit33/ExerciseSelectionView.swift` | Inherited |
| M-26 | [x] **Sprint 5 (2026-04-20): fuzzy ranking improved.** `SmartExerciseSearchService.searchExercisesUltraFastCore` now falls back to a Levenshtein-distance match (cap = 2) when prefix + equipment + token scoring misses, preserving the "prefix > equipment > fuzzy" ordering. | `Fit33/SmartExerciseSearchService.swift` | Product Engineer |
| M-27 | [ ] Onboarding: split `NewOnboardingView.swift` into smaller components | Product Engineer | Inherited |
| M-34 | [ ] DB migration: add `equipment` column to `user_similarity_profiles` | Data | Inherited |

---

## 8. P3 — Feature Backlog

| ID | Task | Agent |
|----|------|-------|
| F-1 | [ ] Progress photos (capture, compare, timeline) | Product Engineer |
| F-2 | [x] **Sprint 5 (2026-04-20): verified.** `Workout.notes` attribute already exists in the Core Data model and is editable from `WorkoutCompletionView` via `$completionNotes`. Cloud DTO already persists it. No schema or UI changes needed. | Product Engineer |
| F-3 | [x] **Sprint 5 (2026-04-20): per-exercise notes end-to-end.** `WorkoutExercise.notes` attribute existed in Core Data; UI was missing. Added an inline editor + display to `WorkoutHistoryDetailView` (expanded `PremiumExerciseRow`). Extended `WorkoutExerciseDTO` with an optional `notes` field (tolerates historical rows via `decodeIfPresent`), and `SupabaseManager.saveWorkoutToCloud` / `syncWorkoutHistoryToCoreData` round-trip the field. Save kicked from `Task { @MainActor in }` to keep Core Data context access on the correct actor. | `Fit33/WorkoutHistoryDetailView.swift`, `Fit33/SupabaseDTOs.swift`, `Fit33/SupabaseManager.swift` | Product Engineer |
| F-4 | [ ] Body measurements tracking (beyond weight) | Product Engineer |
| F-5 | [ ] Monthly progress report | Product Engineer |
| F-6 | [x] **Sprint 5 (2026-04-20): preset chips shipped.** `RestTimerSetupView` now renders a row of canonical rest-interval chips (30s / 45s / 1m / 1:30 / 2m / 3m / 5m) matching common training protocols. Tapping a chip sets the timer instantly. | `Fit33/RestTimerViews.swift` | Product Engineer |
| F-7 | [ ] Notification phases 2–4: weekly progress, celebrations, water/weight reminders | Product Engineer |
| F-8 | [ ] Apple Watch companion app (planning phase) | Device Compatibility |
| F-9 | [ ] iPad layout adaptation (phases 1–3) | Device Compatibility |
| F-10 | [ ] In-app FAQ view (`FAQView.swift` accessible from Settings) — solves Q2-1 | Support |
| F-11 | [ ] Contextual tooltips on complex screens | Support |

---

## 9. P3 — Fitness Engine Backlog

| ID | Task | Severity | Source |
|----|------|----------|--------|
| FE-3 | [ ] Duplicate exercise-count logic between generator and validator | Critical | Inherited |
| FE-4 | [ ] Upright row classification (shoulders, not traps) | Critical | Inherited |
| FE-5 | [ ] Upper/Lower needs distinct A/B days | High | Inherited |
| FE-6 | [ ] Full-body movement coverage gaps | High | Inherited |
| FE-7 | [ ] PPL push day missing rear delts | High | Inherited |
| FE-8 | [ ] Lateral vs front raise bundle logic | High | Inherited |
| FE-9 | [ ] Fat-loss rep/rest scheme optimization | High | Inherited |
| FE-10 | [ ] Skull-crusher movement pattern classification | High | Inherited |
| FE-11 | [ ] Surprise workout shuffle algorithm | Medium | Inherited |
| FE-12 | [ ] Arnold split implementation | Medium | Inherited |
| FE-13 | [ ] Beginner rest period consistency | Medium | Inherited |

---

## 10. P3 — Database / Backend Backlog

| ID | Task | Agent |
|----|------|-------|
| DB-2 | [ ] DTO null-safety audit (pairs with M-13) | Data |
| DB-4 | [ ] Database Phase 3: strategic columns (`completion_rate`, `user_feature_usage`, etc.) | Supabase |
| DB-5 | [x] Verify hot-table indexes applied in production — replaced by `supabase/verify_query_performance.sql` (read-only audit; MIGRATION_INDEX entry 2026-04-20). Run `psql $SUPABASE_DB_URL -f supabase/verify_query_performance.sql \| grep MISSING` to gate deploys. | Data |
| DB-6 | [ ] Enable `pg_stat_statements` for query monitoring | Data |
| DB-7 | [ ] Index audit on high-traffic tables | Supabase |

---

## 11. P4 — Low Priority

| ID | Task | Agent |
|----|------|-------|
| L-1 | [ ] App Store review prompts (strategic timing) — pairs with Q2-2 | Product Engineer |
| L-2 | [ ] Image placeholders for loading states | Design System |
| L-3 | [ ] GDPR data export enhancement (baseline export already ships via `DataDownloadView`) | Infra |
| L-4 | [ ] Background app-refresh optimization | Quality |
| L-5 | [ ] Edge function error-response consistency | Data |
| L-6 | [ ] Architecture: reduce singletons where possible | Product Engineer |
| L-7 | [ ] Architecture: split large files (>1000 lines) | Product Engineer |
| L-8 | [ ] Architecture: add XCTest coverage (target 100+ tests) | Quality |
| L-9 | [x] **Sprint 5 (2026-04-20): covered by `StreakLogicTests`.** Extracted pure `Fit33StreakLogic.transition(...)` from `UserManager.updateStreak()` and added XCTest cases for eastward travel (NYC→Tokyo must increment, never break), westward travel (Tokyo→LAX must never decrement), and DST fall-back same-day clamp. | `Fit33/UserManager.swift`, `Fit33Tests/StreakLogicTests.swift` | Quality |
| L-10 | [x] **Sprint 5 (2026-04-20): covered by `StreakLogicTests`.** XCTest cases assert +1 streak when app is killed at 10 PM and reopened at 7 AM next day, +1 when reopened 4 minutes after midnight (new calendar day), and correct `.broken(previous:)` analytics event when the absence exceeds the user's per-week tolerance window. | `Fit33/UserManager.swift`, `Fit33Tests/StreakLogicTests.swift` | Quality |

---

## Cross-Reference

Detailed specs for items above live in these reference docs:

| Doc | Covers |
|-----|--------|
| `FEATURE_GAME_PLAN.md` | Feature backlog details + competitor analysis |
| `FAQ_PLAN.md` | 87 FAQ entries, website/in-app/tooltip plans |
| `SECURITY_CHECKLIST.md` | RLS verification matrix |
| `DEVICE_COMPATIBILITY_TASKS.md` | iPad/Watch/responsive layout phases |
| `ONBOARDING_AUDIT.md` | Deep onboarding spec + QA checklist |
| `FRIEND_SYSTEM_AUDIT.md` + `FRIEND_SYSTEM_BUGS.md` | Social feature gaps + 15 bugs |
| `NOTIFICATION_SYSTEM_AUDIT.md` | Notification phases 1–4 |
| `FITNESS_EXPERT_AUDIT_FINDINGS.md` | Workout engine backlog (13+ items) |
| `TUTORIAL_REDESIGN_ACTION_PLAN.md` | 10-screen tutorial redesign |
| `WORKOUT_FLOW_FIXES_PLAN.md` | Workout flow unification |
| `DATABASE_AUDIT_REPORT.md` | Schema health + Phase 3 roadmap |
| `SUPABASE_HEALTH_CHECKLIST.md` | Ops checklist (RLS, perf, monitoring) |
| `INFRA_SECURITY_AGENT.md` | Edge function inventory (once AGD-5 lands) |
