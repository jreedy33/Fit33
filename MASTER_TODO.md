# Fit33 Master TODO

> **Last updated:** April 18, 2026 (post Sprint 2 — "Submit-Ready")
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
| Q2-20 | [ ] **Admin-CMS CSP allows `'unsafe-inline'` and `'unsafe-eval'` on scripts** — weakens XSS hardening for an admin panel with MFA + full DB access. Move to nonce-based inline scripts or strict CSP. | `admin-cms/next.config.ts:28-42`, `admin-cms/src/middleware.ts:33-35` | XSS amplification |
| Q2-21 | [ ] **`admin_logged_in` cookie is `httpOnly: false`** (the JWT cookie is httpOnly, this one is a public boolean). Low-severity fingerprinting surface — either remove or make httpOnly. | `admin-cms/src/lib/auth-cookies.ts:30-36` | Minor |
| Q2-22 | [x] **CORS migration complete (Sprint 2, 2026-04-18).** `verify-code` and `send-push-notification` both use `buildCorsHeaders(req)` from `_shared/cors.ts`; `verify-code` now also gates on `requireUserAuth` so SMS confirmation cannot be triggered without a valid session. Audit of `supabase/functions/**/index.ts` confirms no `Access-Control-Allow-Origin: '*'` remains. | `supabase/functions/_shared/cors.ts`, `supabase/functions/verify-code/index.ts`, `supabase/functions/send-push-notification/index.ts` | Origin enforcement |
| Q2-23 | [x] **`Fit33/PrivacyInfo.xcprivacy` shipped Sprint 2 (2026-04-18).** Declares `NSPrivacyTracking=false`, `NSPrivacyTrackingDomains=[]`, Required Reason APIs (UserDefaults CA92.1, FileTimestamp C617.1, DiskSpace E174.1, SystemBootTime 35F9.1), and `NSPrivacyCollectedDataTypes` for Name, Email, Phone, Photos/Videos, Contacts, Health, Fitness, UserID, DeviceID, ProductInteraction, PerformanceData, CrashData, OtherUserContent — all linked to user, none tracking. Added to `Fit33` target via `project.pbxproj`. Still TODO before submission: verify every SPM dependency ships its own manifest (Xcode Privacy Report export). | `Fit33/PrivacyInfo.xcprivacy`, `Fit33.xcodeproj/project.pbxproj` | Infra |
| H-5 | [ ] Move **Strava/Fitbit client IDs** fully off committed defaults (`Secrets.swift` is gitignored; verify no fallback literal remains in `AppConfig.swift`). Spot-check after Q2-18 fix. | `Fit33/AppConfig.swift` | Infra |
| H-6 | [~] **Admin audit log completeness.** Table + `logAdminAction()` exist; confirm every write/bulk action calls it (a grep-and-diff task). | `admin-cms/src/app/api/admin/route.ts` | Infra |
| M-3 | [ ] **Certificate pinning** for Supabase API calls (defense in depth for the anon key). | `Fit33/SupabaseManager.swift` | Infra |
| M-10 | [ ] **Phone-number redaction in Twilio edge function logs** — `send-verification` redacts (good); audit `verify-code` and any downstream logger for raw phone leaks. | `supabase/functions/send-verification/index.ts`, `supabase/functions/verify-code/index.ts` | Infra + Data |
| M-19 | [ ] **Email verification flow** — enable Supabase "Confirm email" and surface an in-app resend + blocked state. | `Fit33/SupabaseManager.swift`, `Fit33/NewOnboardingView+Auth.swift` | Infra |

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
| Q2-28 | [ ] **Dual HealthKit observer stacks.** `HealthKitManager` registers foreground observers at `isAuthorized` and `BackgroundChallengeSyncService` registers a separate set of `HKObserverQuery` instances with immediate background delivery. They both fire in the foreground, driving duplicate `fetchTodaySteps` / `syncAllData` work. Consolidate into a single observer coordinator. | `Fit33/HealthKitManager.swift:377-454`, `Fit33/BackgroundChallengeSyncService.swift:72-175` | Battery + thrash |
| Q2-29 | [x] `SupabaseManager.signOut()` and `deleteAccount()` now both call `await RealtimeService.shared.disconnect()` **before** revoking the JWT so no stale channel leaks onto the next signed-in user. (Sprint 1, 2026-04-17) | `Fit33/SupabaseManager.swift` | Correctness + battery |

### Video / media

| ID | Task | File:Line | Notes |
|----|------|-----------|-------|
| Q2-30 | [ ] **Video prefetch / streaming don't check expensive network.** `VideoPreloadManager` and `VideoStreamingService` don't gate on `NetworkMonitor.isExpensive` / cellular. iOS 17+ App Review can reject aggressive cellular prefetch. Gate prefetch on Wi-Fi or `!isExpensive`, and respect iOS "Low Data Mode". | `Fit33/VideoPreloadManager.swift`, `Fit33/VideoStreamingService.swift` | Cellular data + battery |
| Q2-31 | [ ] **`AVAudioSession` is configured `.playback` + `.mixWithOthers` at `VideoStreamingService.init` and never deactivated.** When no video is playing, audio session can still interrupt user's background audio. Activate on first play, deactivate after last player destructs. | `Fit33/VideoStreamingService.swift:122, 414-417` | Audio UX + battery |

### Animations & timers

| ID | Task | File:Line | Notes |
|----|------|-----------|-------|
| Q2-32 | [ ] **`AnimatedOrbBackground` respects Low Power Mode but not `accessibilityReduceMotion`.** Add a `@Environment(\.accessibilityReduceMotion)` check that short-circuits the animation. | `Fit33/AdaptiveColors.swift:357-509` | Accessibility + battery |
| Q2-33 | [ ] **`ActiveWorkoutView+Init` 1s timer captures `[self]` (strong), not `[weak self]`.** Unlikely to leak because it invalidates on disappear, but the rule in `QUALITY_PERFORMANCE_AGENT.md` is `[weak self]` for every scheduled timer. | `Fit33/ActiveWorkoutView+Init.swift:429-444` | Consistency |
| M-4 | [ ] **Full memory / closure retain cycle audit** across `Timer.scheduledTimer`, `NotificationCenter` observers, and long-lived `Task { }` blocks on view disappear. | Repo-wide | Quality |
| M-1 (residual) | [ ] **60+ remaining `DispatchQueue.main.asyncAfter`** (per QP doc, mostly `NewOnboardingView.swift` = 41, `ActiveWorkoutView.swift` = 9, `ContentView.swift` = 10). Convert to `Task.sleep(for:)` with cancellation. | See QUALITY_PERFORMANCE_AGENT.md | Quality |
| M-8 | [ ] Client-side API rate limits (debounce rapid identical requests) — a `RequestCoalescer` for social/challenge/health fetches. | `Fit33/PerformanceOptimizations.swift` + services | Quality |

---

## 4. P1 — Feature Flow Gaps

| ID | Task | File:Line | Notes |
|----|------|-----------|-------|
| Q2-34 | [x] **Offline retry queue shipped Sprint 2 (2026-04-18).** `Fit33/CloudSyncRetryQueue.swift` — file-backed JSON queue in Application Support (no Core Data model change), persists across launches, exponential backoff capped at 30 min / 6 attempts, drained on foreground from `Fit33App.onChange(of: scenePhase)`. `ActiveWorkoutView+Actions.swift` enqueues on `saveWorkoutToCloud` failure OR when unauthenticated. Paired with H-4: Dashboard shows `DashboardOfflineSyncChip` ("Syncing N workouts…" / "N saved offline, tap to retry") while `pendingCount > 0`. | `Fit33/CloudSyncRetryQueue.swift`, `Fit33/ActiveWorkoutView+Actions.swift`, `Fit33/Fit33App.swift`, `Fit33/DashboardView+Helpers.swift`, `Fit33/DashboardView.swift` | Correctness |
| Q2-35 | [x] **Push flush wired Sprint 2 (2026-04-18).** `PrivateChallengeService.sendMessage` now calls `PushNotificationService.shared.flushPushNotificationQueue(triggeredBy: "private_challenge_chat")` on successful send. `ActivityFeedService.sendReaction` calls the same flush with `triggeredBy: "activity_reaction"`. | `Fit33/PrivateChallengeService.swift`, `Fit33/FriendActivityFeedView.swift` | Social engagement |
| Q2-36 | [x] **Notification allowlist shipped Sprint 2 (2026-04-18).** `NotificationManager.knownNotificationTypes: Set<String>` enumerates every server-side `type` string the client routes. Default case now `.error`-logs unknown types (surfaces in crash reports + SessionLogManager) instead of silently no-opping, and falls back to `.dashboard` for graceful recovery. `Fit33Tests/NotificationAllowlistTests.swift` enforces every `NotificationType.allCases.rawValue` is in the allowlist plus known server aliases (`friend_accepted`, `group_challenge_started`, etc). | `Fit33/NotificationManager.swift`, `Fit33Tests/NotificationAllowlistTests.swift` | Correctness |
| Q2-37 | [ ] **Onboarding completion has an early-return path if weight parsing fails** *after* the OAuth profile `Task { }` has already started — risk of cloud profile existing without a local `User` row. Add a single terminal error state with rollback. | `Fit33/NewOnboardingView+Completion.swift:542-545, 427-525` | Onboarding |
| Q2-38 | [ ] **`ExistingUserPhonePrompt` and `PhoneVerificationSheet` overlap.** Dashboard uses the former; onboarding uses the latter. Pick one component. | `Fit33/ExistingUserPhonePrompt.swift:364-418`, `Fit33/PhoneVerificationSheet.swift`, `Fit33/DashboardView+Helpers.swift:524-533` | Product Engineer |
| C-6 | [ ] **Atomic challenge RPCs** (accept/decline/progress) to prevent race conditions. Still missing `sim_accept_challenge_for_user`-style atomic variants for production paths. | `Fit33/ChallengeService.swift`, `Fit33/PrivateChallengeService.swift`, new SQL migration | Data |
| H-2 | [ ] **Accessibility labels (~500+ needed)** — priority order in `QUALITY_PERFORMANCE_AGENT.md` §3. | Repo-wide | Quality |
| H-3 | [ ] **Input validation on user-facing text fields** — common patterns via a shared validator (name length, goal text, challenge title profanity check pre-submit). | Repo-wide | Product Engineer |
| H-4 | [x] **Offline retry UX shipped with Q2-34 (2026-04-18).** `DashboardOfflineSyncChip` renders on Dashboard whenever `CloudSyncRetryQueue.pendingCount > 0` with states: "Syncing N…" during drain, "N saved offline, tap to retry" idle. Owns own `@StateObject` to respect widget isolation rule. | `Fit33/DashboardView+Helpers.swift` | Product Engineer |
| H-18 | [ ] **Tutorial redesign (10-screen flow).** See `TUTORIAL_REDESIGN_ACTION_PLAN.md`. | `Fit33/WelcomeTutorialView.swift` etc. | Product Engineer |
| Q2-63 | [x] **`cardio_workouts.origin_app` — true third-party origin tracking (2026-04-17).** HK-imported Strava/Nike/Peloton/Garmin/Zwift/Apple Watch/etc. workouts now render a brand-colored badge (not a generic Apple Health heart). OAuth services (Strava/Fitbit/WHOOP/Oura) skip HK duplicates on save + delete stale HK rows on connect. Mapper: `Fit33/WorkoutOriginMapper.swift`. Migration: `supabase/20260417_cardio_workouts_origin_app.sql`. See `DATA_BACKEND_AGENT.md` §2026-04-17 for semantics + dedupe rules. | `Fit33/HealthDataService.swift`, `Fit33/SupabaseDTOs.swift`, `Fit33/DashboardWorkoutCards.swift`, `Fit33/HealthKitSettingsView.swift`, `Fit33/{Strava,Fitbit,Whoop,Oura}Service.swift` | Data Backend + Product Engineer |

---

## 5. P2 — Dead & Orphaned Code

| ID | Task | File:Line | Notes |
|----|------|-----------|-------|
| Q2-39 | [ ] **Orphaned test files not in the Xcode project.** `Fit33/ActiveWorkoutTests.swift` and `Fit33/LimitationFilterTests.swift` are on disk but have no `PBXFileReference` in `Fit33.xcodeproj/project.pbxproj`. Either add them to the `Fit33Tests` target or delete. | `Fit33/ActiveWorkoutTests.swift`, `Fit33/LimitationFilterTests.swift` | Quality |
| Q2-40 | [ ] **`PersonalizedInsightsService` has placeholder logic shipping to users.** `detectBestWorkoutTime()` hardcodes `"morning_person"`; `detectNutritionPatterns` / `detectSocialPatterns` are empty; volume correlation uses an empty `volumeValues` array. Either finish the implementation or disable the feature flag. | `Fit33/PersonalizedInsightsService.swift:620-642, 980-1025` | Product Engineer + Data |
| Q2-41 | [ ] **Duplicate recommendation engines.** `SmartProgramRecommender` is used by `WorkoutTabView`, while `CollaborativeLearningEngine.swift:104` and `ProgramLibraryService.swift:269` still carry TODOs to delegate. Complete the delegation and delete the old code paths. | `Fit33/CollaborativeLearningEngine.swift:104`, `Fit33/ProgramLibraryService.swift:269`, `Fit33/SmartProgramRecommender.swift` | Product Engineer + Fitness Expert |
| Q2-42 | [ ] **Duplicate image caches.** `FriendPhotoCache`, `ProfilePhotoCache`, and the `ImageCache` actor in `PerformanceOptimizer.swift` — consolidate into one `ImageCache` with per-domain keys. | `Fit33/FriendPhotoCache.swift`, `Fit33/ProfilePhotoCache.swift`, `Fit33/PerformanceOptimizations.swift` | Product Engineer |
| Q2-43 | [ ] **Stale TODO comment in `AdManager.swift:66`** about creating a rewarded unit while the production ID already exists at `:70`. Remove the comment. | `Fit33/AdManager.swift:66-70` | Infra |
| Q2-44 | [ ] **`Fit33Tests/Fit33Tests.swift:12-14`** is an empty `@Test func example()` placeholder. Delete or replace with a real smoke test. | `Fit33Tests/Fit33Tests.swift:12-14` | Quality |

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
| AGD-8 | [ ] **Audit for "stale done" claims.** This audit found C-3 (StoreKit) and C-4 (ATT) marked not done in MASTER_TODO while code was actually complete. Add a quarterly "agent claim verification" script that greps each claimed-done marker against repo evidence. | `scripts/` (new), all `*_AGENT.md` | Quality |
| AGD-9 | [ ] **Wire `supabase/MIGRATION_INDEX.md` updates into the commit hook.** Q2-17 shows migrations land untracked. A pre-commit hook that refuses a `supabase/*.sql` add without a corresponding `MIGRATION_INDEX.md` entry will prevent this. | `scripts/pre_commit_migration_check.sh` (new), `.githooks` | Data + Infra |

---

## 7. P2 — Medium Priority (Polish + Infrastructure)

| ID | Task | Agent | Source |
|----|------|-------|--------|
| M-2 | [ ] Localization prep (extract all user-facing strings) | Product Engineer | Inherited |
| M-7 | [ ] Fix exercise-sync race conditions (parallel Core Data writes) | Data | Inherited |
| M-9 | [ ] Keyboard dismiss + safe-area fixes across all input screens | Product Engineer | Inherited |
| M-11 | [ ] CI/CD pipeline (automated build + test on PR) — extend current workflows | Infra | Inherited |
| M-13 | [ ] DTO null-safety audit across every Supabase DTO | Data | Inherited |
| M-15 | [~] Dark-mode token adoption — remaining `Color(white: 0.12)` violations (~97 in 30 files per DSE metrics) | Design System | Inherited |
| M-18 | [ ] Birthday format toggle (MM/DD vs DD/MM) in onboarding | Product Engineer | Inherited |
| M-20 | [ ] Design system: replace hardcoded card colors with `Color.cardBackground` | Design System | Inherited |
| M-21 | [ ] Design system: deduplicate `ScaleButtonStyle` variants | Design System | Inherited |
| M-22 | [ ] Design system: typography/spacing/corner-radius token enforcement | Design System | Inherited |
| M-23 | [ ] Design system: standardize haptic feedback patterns | Design System | Inherited |
| M-24 | [ ] Design system: standardize empty states across all screens | Design System | Inherited |
| M-25 | [ ] Workout flow: unify Build Workout with Exercise Library | Product Engineer | Inherited |
| M-26 | [ ] Exercise search: result-ranking improvements | Product Engineer | Inherited |
| M-27 | [ ] Onboarding: split `NewOnboardingView.swift` into smaller components | Product Engineer | Inherited |
| M-34 | [ ] DB migration: add `equipment` column to `user_similarity_profiles` | Data | Inherited |

---

## 8. P3 — Feature Backlog

| ID | Task | Agent |
|----|------|-------|
| F-1 | [ ] Progress photos (capture, compare, timeline) | Product Engineer |
| F-2 | [ ] Workout notes (per-workout text field) | Product Engineer |
| F-3 | [ ] Exercise notes (per-exercise annotations) | Product Engineer |
| F-4 | [ ] Body measurements tracking (beyond weight) | Product Engineer |
| F-5 | [ ] Monthly progress report | Product Engineer |
| F-6 | [ ] Rest timer presets (quick-select common durations) | Product Engineer |
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
| DB-5 | [ ] Verify `optimize_query_performance.sql` applied in production | Data |
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
| L-9 | [ ] Streak audit: manual timezone-change test | Quality |
| L-10 | [ ] Streak audit: midnight app-kill daily-reset test | Quality |

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
