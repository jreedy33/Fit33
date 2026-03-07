# Fit33 Master TODO - Consolidated Improvement Tracker
## Updated: March 7, 2026
**Source:** Merged from `IMPROVEMENT.md` (54 items) + `UI_AUDIT_INCONSISTENCIES.md` (15 sections) + deep codebase scan of 256 Swift files (253,399 total lines of code)

---

## Status Legend
- **DONE** - Verified complete in codebase
- **PARTIAL** - Some progress made, more work needed
- **NOT STARTED** - No evidence of progress
- **BLOCKED** - Depends on another item

---

## What Has Been Improved (Verified Done)

| # | Item | Evidence |
|---|------|----------|
| 1.5 | Force unwraps fixed | Marked Done in IMPROVEMENT.md |
| 1.6 | Core Data error recovery improved | Marked Done in IMPROVEMENT.md |
| 2.2 | NavigationView → NavigationStack migration | Only 3 residual `NavigationView` usages remain (WorkoutProgressView, CriticalPathTests, ProfileView) — down from dozens |
| UI-1 | AnimatedOrbBackground added to missing screens | Settings, BugReport, SmartMealPlanner, PrivacyPolicy, NotificationSettings, CloudBackup, LimitationsSettings, RecipeBrowser, RecipeDetail, MealPlan, ShoppingList, CardioLanding, FitnessEquipment, StravaSettings, InBodySettings, TermsConditions, DevMenu, DeveloperAnalytics, PersonalizedPrograms, FavoriteRoutines all now have orb backgrounds |
| UI-2 | Card style consistency (sleekCard adoption) | Marked Done — `.sleekCard()` adoption expanded |
| -- | DESIGN_AGENT.md created | Comprehensive design system spec exists |
| -- | PRODUCT_ENGINEER_AGENT.md created | Engineering patterns documented |
| -- | SECURITY_CHECKLIST.md created | RLS audit checklist exists |
| -- | Secrets.template.swift pattern established | Template exists with Spoonacular, Strava, Fitbit, InBody secrets |

---

## CRITICAL - Must Fix Before ANY Release

### C-1: Supabase Credentials Still Hardcoded
- **Status:** NOT STARTED
- **Priority:** P0 CRITICAL
- **Context:** `SupabaseManager.swift:25-26` still has the full Supabase URL and anon key as string literals. `FoodDatabaseService.swift` also has raw URL + JWT token in URLRequest headers. The `Secrets.template.swift` exists but does NOT include Supabase credentials.
- **Why It Matters:** Anyone decompiling the IPA or reading git history gets your backend URL and key. While the anon key alone is protected by RLS, combined with the URL it exposes your entire API surface. Note: the comment in SupabaseManager says "this is standard for Supabase projects" — this is true for the anon key, but best practice is still to use a config file pattern, not inline strings, for easier rotation.
- **User Impact Before:** N/A (invisible to user)
- **User Impact After:** No change for user; prevents credential exposure if repo leaks or IPA is decompiled
- **Recommendation:**
  1. Add `static let supabaseURL` and `static let supabaseAnonKey` to `Secrets.template.swift`
  2. Update `AppConfig.swift` to expose them via `Secrets`
  3. Update `SupabaseManager.swift` and `FoodDatabaseService.swift` to reference `AppConfig`
- **Files:** `SupabaseManager.swift:25-26`, `FoodDatabaseService.swift:265-268`, `Secrets.template.swift`, `AppConfig.swift`

---

### C-2: Dev Menu Password in Source Code
- **Status:** NOT STARTED
- **Priority:** P0 CRITICAL
- **Context:** `AppConfig.swift:88` has `static let devMenuPassword = "WhatsApp26!"` inside `#if DEBUG`. The password is committed to git.
- **Why It Matters:** Even in DEBUG, passwords in source control are a leak. If this password is reused elsewhere, it's a security vulnerability.
- **Recommendation:** Move to `Secrets.swift` or remove password requirement entirely (just use `#if DEBUG` gating for dev menu access)
- **Files:** `AppConfig.swift:88`

---

### C-3: No StoreKit / In-App Purchase Integration
- **Status:** NOT STARTED
- **Priority:** P0 CRITICAL
- **Context:** `PremiumManager` in `UserManager.swift` defaults `isPremiumUser = true`. Zero StoreKit code exists. `PremiumUpgradeView.swift` has UI but no purchase capability.
- **Why It Matters:** Apple WILL reject the app if it advertises premium features without working IAP. Currently every user gets everything free — no monetization path.
- **User Impact Before:** All features free (no revenue)
- **User Impact After:** Proper subscription tiers, restore purchases, receipt validation
- **Recommendation:** Implement StoreKit 2 with monthly/yearly subscriptions, server-side receipt validation via Supabase Edge Function
- **Files:** `UserManager.swift:637-737`, `PremiumUpgradeView.swift`

---

### C-4: No App Tracking Transparency (ATT)
- **Status:** NOT STARTED
- **Priority:** P0 CRITICAL
- **Context:** `AdManager.swift` uses Google AdMob but no `ATTrackingManager.requestTrackingAuthorization()` call exists anywhere.
- **Why It Matters:** Apple requires ATT before any ad tracking since iOS 14.5. App WILL be rejected.
- **Recommendation:** Add `NSUserTrackingUsageDescription` to Info.plist, request ATT before AdMob init, handle all authorization states
- **Files:** `AdManager.swift`, `Fit33App.swift`, `Info.plist`

---

### C-5: Missing/Incomplete RLS on Challenge Tables
- **Status:** NOT STARTED (checklist created but not verified)
- **Priority:** P0 CRITICAL
- **Context:** Challenge tables (`challenge_daily_progress`, `challenge_participants`, `group_challenges`) may lack DELETE policies. `community_challenge_participants` lacks comprehensive RLS.
- **Why It Matters:** Any authenticated user could read/modify/delete other users' challenge data via direct API calls.
- **Recommendation:** Run RLS verification SQL, add comprehensive policies for all challenge/social tables
- **Files:** Supabase SQL migrations, `SECURITY_CHECKLIST.md`

---

### C-6: Race Condition in Challenge Creation (Non-Atomic)
- **Status:** NOT STARTED
- **Priority:** P0 CRITICAL
- **Context:** Challenge RPCs perform multi-step INSERT operations without transaction wrapping. Connection drops create orphaned records.
- **Why It Matters:** Users see phantom challenges, app crashes loading challenge details with missing parent rows
- **Recommendation:** Wrap all multi-step RPCs in BEGIN...EXCEPTION...END blocks, add orphan cleanup cron
- **Files:** `supabase/challenge_rpc_functions.sql`

---

### C-7: Timezone Inconsistency in Challenge Progress
- **Status:** NOT STARTED
- **Priority:** P0 CRITICAL
- **Context:** Server uses `NOW() AT TIME ZONE p_timezone` but iOS client sends dates in local time without timezone context. 11 PM PST logs can appear as next day in UTC.
- **Why It Matters:** Challenge progress logged on wrong day, daily streaks break unexpectedly
- **Recommendation:** Always pass `TimeZone.current.identifier` with progress logging, validate on server
- **Files:** `ChallengeService.swift`, Supabase RPCs

---

### C-8: Admin Session Tokens XSS-Vulnerable
- **Status:** NOT STARTED
- **Priority:** P0 CRITICAL
- **Context:** Admin CMS stores Supabase session tokens in `sessionStorage`, accessible via JavaScript.
- **Why It Matters:** XSS attack via crafted bug report/crash report content could steal admin tokens = full database access
- **Recommendation:** Switch to httpOnly Secure cookies or Supabase SSR auth helpers
- **Files:** `admin-cms/src/lib/auth.ts`

---

## HIGH - Must Fix Before Production

### H-1: Excessive print() Statements (3000+)
- **Status:** NOT STARTED
- **Priority:** P1 HIGH
- **Context:** Thousands of emoji-heavy `print()` statements. `Logger.swift` overrides `print()` to no-op in release, but string interpolation still evaluates.
- **Why It Matters:** CPU waste from string interpolation even in no-op mode; no structured logging for production diagnostics
- **User Impact Before:** Potential battery drain from unnecessary string construction
- **User Impact After:** Zero overhead in release builds, structured logging for diagnostics
- **Recommendation:** Migrate top 10 service files to `AppLogger` with proper level-gating and `@autoclosure`
- **Files:** `SupabaseManager.swift`, `WorkoutManager.swift`, `UserManager.swift`, `ExerciseLibraryService.swift`, and ~100+ other files

---

### H-2: No Accessibility Support
- **Status:** NOT STARTED
- **Priority:** P1 HIGH
- **Context:** Only ~14 accessibility label occurrences across 256 files. No VoiceOver support, no Dynamic Type.
- **Why It Matters:** Apple may reject; ~15% of users rely on accessibility features; potential legal liability
- **User Impact Before:** VoiceOver users can't navigate; Dynamic Type users see cut-off text
- **User Impact After:** Full VoiceOver navigation, proper Dynamic Type scaling
- **Recommendation:** Add accessibility labels/hints to top 5 critical flows (Dashboard, Active Workout, Onboarding, Profile, Tab Bar)
- **Files:** All view files

---

### H-3: Missing Input Validation
- **Status:** NOT STARTED
- **Priority:** P1 HIGH
- **Context:** MealService accepts negative calories; UserManager.createUser() has no bounds on age/height/weight; birthday parsing accepts years 1900-2100
- **Why It Matters:** Corrupted data in Supabase, division-by-zero crashes in calorie calculations, bad analytics
- **Recommendation:** Add validation at service layer for all user inputs with clear error messages
- **Files:** `MealService.swift`, `UserManager.swift`, `SupabaseManager.swift`, `WorkoutManager.swift`

---

### H-4: No Offline Mode / Network Error Handling
- **Status:** NOT STARTED
- **Priority:** P1 HIGH
- **Context:** App relies heavily on Supabase with no offline queue. Operations fail silently when offline.
- **Why It Matters:** Mobile users frequently lose connectivity (gym basements, subways). Silent failures = data loss.
- **User Impact Before:** Exercises, meals, progress silently lost when offline
- **User Impact After:** Operations queued, synced on reconnection, "offline" banner visible
- **Recommendation:** Implement `NWPathMonitor`-based `NetworkMonitor` + `OfflineQueue` with auto-retry
- **Files:** New files needed: `NetworkMonitor.swift`, `OfflineQueue.swift`

---

### H-5: Strava/Fitbit Client IDs in Source Code
- **Status:** NOT STARTED
- **Priority:** P1 HIGH
- **Context:** `AppConfig.swift:49` has Strava clientId `"198007"`, line 64 has Fitbit clientId `"23TRK9"`
- **Why It Matters:** Enables OAuth phishing impersonation
- **Recommendation:** Move to Secrets.swift pattern
- **Files:** `AppConfig.swift:49,64`, `Secrets.template.swift`

---

### H-6: No Admin Audit Logging
- **Status:** NOT STARTED
- **Priority:** P1 HIGH
- **Context:** Admin CMS can view/edit all user data with no audit trail.
- **Why It Matters:** GDPR Article 30 compliance; compromise detection; accountability
- **Recommendation:** Create `admin_audit_log` table, log all admin actions
- **Files:** Admin CMS, Supabase migrations

---

### H-7: No Admin Rate Limiting
- **Status:** NOT STARTED
- **Priority:** P1 HIGH
- **Context:** Admin API only verifies Bearer token. Compromised token = unlimited data exfiltration.
- **Recommendation:** Add per-endpoint rate limits (100 reads/min, 30 edits/min, 5 bulk ops/min)
- **Files:** `admin-cms/src/app/api/admin/route.ts`

---

### H-8: No Admin 2FA/MFA
- **Status:** NOT STARTED
- **Priority:** P1 HIGH
- **Context:** Admin login is email + password only. Admins have access to ALL user data.
- **Recommendation:** Enable Supabase MFA (TOTP), require 2FA before issuing session tokens
- **Files:** `admin-cms/src/app/api/auth/login/route.ts`

---

### H-9: REPLICA IDENTITY Not Verified
- **Status:** NOT STARTED
- **Priority:** P1 HIGH
- **Context:** Realtime tables may not have REPLICA IDENTITY FULL, causing incomplete event payloads and defensive refresh workarounds
- **Recommendation:** Verify via SQL query, apply REPLICA IDENTITY FULL to all realtime tables
- **Files:** Supabase SQL, `RealtimeService.swift`

---

### H-10: No Challenge Progress Validation
- **Status:** NOT STARTED
- **Priority:** P1 HIGH
- **Context:** `log_challenge_progress()` RPC accepts any integer. No upper bounds, negative values possible.
- **Why It Matters:** Leaderboard manipulation, corrupted aggregates
- **Recommendation:** Add server-side validation bounds (steps < 200K, distance < 200km, etc.)
- **Files:** Supabase RPCs

---

### H-11: NavigationView Residual Cleanup
- **Status:** PARTIAL
- **Priority:** P1 HIGH
- **Context:** 3 `NavigationView` usages remain: `WorkoutProgressView.swift:1`, `CriticalPathTests.swift:1`, `ProfileView.swift:1`
- **Why It Matters:** Deprecated API causes navigation corruption and Xcode warnings
- **Recommendation:** Replace remaining 3 instances with `NavigationStack`
- **Files:** `WorkoutProgressView.swift`, `CriticalPathTests.swift`, `ProfileView.swift`

---

### H-12: Onboarding Dead Code
- **Status:** DONE
- **Priority:** P1 HIGH
- **Context:** Duplicate `basicsStep`/`bodyStep`/`goalStep` etc. (PageTemplate versions) were dead code — 1,327 lines removed.
- **Files:** `NewOnboardingView.swift`

---

### H-13: Onboarding Progress Not Saved
- **Status:** DONE
- **Priority:** P1 HIGH
- **Context:** App close during onboarding lost all progress. Added UserDefaults checkpoint per step with restore on relaunch.
- **Files:** `NewOnboardingView.swift` (OnboardingSessionManager)

---

### H-14: PhoneVerificationSheet Country Mismatch
- **Status:** DONE
- **Priority:** P1 HIGH
- **Context:** Settings phone verification sheet had 16 countries and maxAttempts=2 while onboarding had 45 countries and maxAttempts=3. Synced to use dialingCode, fromLocale(), all 45 countries, and country-specific formatting. Fixed timer memory leaks.
- **Files:** `PhoneVerificationSheet.swift`

---

### H-15: Test Account Cleanup
- **Status:** DONE
- **Priority:** P1 HIGH
- **Context:** OnboardingTestHelper only signed out test accounts — never deleted them from database. Now calls delete_user_account RPC and verifies zero residue.
- **Files:** `OnboardingTestHelper.swift`, `supabase/cleanup_test_accounts.sql`

---

## MEDIUM - Should Fix Before Production

### M-1: DispatchQueue.main.asyncAfter Overuse
- **Status:** NOT STARTED
- **Priority:** P2 MEDIUM
- **Context:** `NewOnboardingView.swift` has 41 instances, `ActiveWorkoutView.swift` has 9, `ContentView.swift` has 10
- **Why It Matters:** Race conditions on slow devices, untestable timing-dependent code
- **Recommendation:** Replace with `Task.sleep`, `withAnimation` completion handlers, state machines
- **Files:** `NewOnboardingView.swift`, `ActiveWorkoutView.swift`, `ContentView.swift`

---

### M-2: No Localization / Hardcoded Strings
- **Status:** NOT STARTED
- **Priority:** P2 MEDIUM
- **Context:** All strings hardcoded in English. Date/number formats don't respect locale.
- **Recommendation:** Create `.xcstrings` file, extract strings from top 5 views, use locale-aware formatters
- **Files:** All view files

---

### M-3: No SSL Certificate Pinning
- **Status:** NOT STARTED
- **Priority:** P2 MEDIUM
- **Context:** All network requests use `URLSession.shared` without certificate pinning. Gym WiFi = MITM risk.
- **Recommendation:** Pin Supabase domain's public key at minimum
- **Files:** New `CertificatePinning.swift`

---

### M-4: Memory Leak Risks in Closures
- **Status:** NOT STARTED
- **Priority:** P2 MEDIUM
- **Context:** Multiple closures without `[weak self]`: Timer callbacks, NotificationCenter observers, DispatchQueue closures
- **Why It Matters:** Fitness apps run for extended workout sessions — memory accumulates
- **Recommendation:** Audit all `Timer.scheduledTimer`, `NotificationCenter.addObserver`, `asyncAfter` for `[weak self]`
- **Files:** `PerformanceOptimizations.swift`, `WorkoutCompletionView.swift`, `Fit33App.swift`, `ActiveWorkoutView.swift`

---

### M-5: iPad Support Missing
- **Status:** NOT STARTED
- **Priority:** P2 MEDIUM
- **Context:** No `@Environment(\.horizontalSizeClass)` checks. All layouts iPhone-only.
- **Recommendation:** Quick fix: set Targeted Device Family to "iPhone" only for launch
- **Files:** `Fit33.xcodeproj` settings

---

### M-6: Race Conditions in Exercise Library Sync
- **Status:** NOT STARTED
- **Priority:** P2 MEDIUM
- **Context:** `isSyncing` flag and `syncLock` don't cover all code paths. Concurrent calls create duplicates.
- **Recommendation:** Convert to Swift actor or serial DispatchQueue; add Core Data uniqueness constraint
- **Files:** `ExerciseLibraryService.swift`

---

### M-7: No Rate Limiting on API Calls
- **Status:** NOT STARTED
- **Priority:** P2 MEDIUM
- **Context:** Every search keystroke triggers Spoonacular API. Foreground handler fires 7+ parallel calls.
- **Recommendation:** Add 300ms debouncing for search, rate limiter (5 req/sec), cache with TTL
- **Files:** `SpoonacularService.swift`, `SpoonacularAdvancedService.swift`, `Fit33App.swift`

---

### M-8: Keyboard Handling Issues
- **Status:** NOT STARTED
- **Priority:** P2 MEDIUM
- **Context:** Keyboard doesn't dismiss on tap outside text fields on most screens.
- **Recommendation:** Add `.scrollDismissesKeyboard(.interactively)`, global tap gesture, `@FocusState` management
- **Files:** `ContentView.swift`, `NewOnboardingView.swift`, `ProfileView.swift`, `MealPlanView.swift`

---

### M-9: Unsafe Safe Area Handling
- **Status:** NOT STARTED
- **Priority:** P2 MEDIUM
- **Context:** 136 `.ignoresSafeArea()` across 87 files. Content hidden behind notch/Dynamic Island.
- **Recommendation:** Audit — keep on backgrounds, remove on content/buttons
- **Files:** 87 files

---

### M-10: Phone Numbers Logged as PII
- **Status:** NOT STARTED
- **Priority:** P2 MEDIUM
- **Context:** Twilio edge functions log full phone numbers. GDPR/CCPA violation risk.
- **Recommendation:** Redact to `+1***XXX` in logs, hash in storage
- **Files:** `supabase/functions/send-verification/`, `supabase/functions/verify-code/`

---

### M-11: No CI/CD Pipeline
- **Status:** NOT STARTED
- **Priority:** P2 MEDIUM
- **Context:** No GitHub Actions, no automated testing, no deployment pipeline
- **Recommendation:** Create `.github/workflows/` for admin CMS build, iOS syntax check, edge function deploy
- **Files:** New `.github/workflows/` directory

---

### M-12: Crash Reports No Auto-Cleanup
- **Status:** NOT STARTED
- **Priority:** P2 MEDIUM
- **Context:** `crash_reports` table grows indefinitely
- **Recommendation:** pg_cron job to delete resolved reports older than 90 days
- **Files:** Supabase migration

---

### M-13: Missing Database Indexes
- **Status:** NOT STARTED
- **Priority:** P2 MEDIUM
- **Context:** Common query patterns (leaderboards, friend lookups, daily progress) lack optimized indexes
- **Recommendation:** Add 5-6 targeted composite indexes per audit findings
- **Files:** Supabase migration

---

### M-14: Null Handling in Swift DTOs
- **Status:** NOT STARTED
- **Priority:** P2 MEDIUM
- **Context:** `SupabaseDTOs.swift` optional fields force-unwrapped in views. Deleted opponent = crash.
- **Recommendation:** Add COALESCE in SQL, safe unwrapping with defaults in DTOs
- **Files:** `SupabaseDTOs.swift`, `ChallengeService.swift`

---

### M-15: Dark Mode Color Inconsistencies
- **Status:** PARTIAL (orb backgrounds added but hardcoded colors remain)
- **Priority:** P2 MEDIUM
- **Context:** Many views still use hardcoded RGB values instead of semantic `DesignSystem.swift` tokens.
- **Recommendation:** Migrate to `Color.cardBackground`, `Color.adaptiveText`, etc.
- **Files:** 30+ view files

---

### M-16: Contact Phone Normalization
- **Status:** DONE
- **Priority:** P2 MEDIUM
- **Context:** ContactsService used US-only last-10-digits strategy. Replaced with E.164-aware normalization that preserves country codes.
- **Files:** `ContactsService.swift`

---

### M-17: Onboarding Analytics Drop-Off Tracking
- **Status:** DONE
- **Priority:** P2 MEDIUM
- **Context:** OnboardingSessionManager now tracks per-step timing. Created onboarding_analytics table.
- **Files:** `NewOnboardingView.swift`, `supabase/20260307_onboarding_analytics.sql`

---

### M-18: Birthday Date Format Toggle
- **Status:** NOT STARTED
- **Priority:** P2 MEDIUM
- **Context:** Birthday format auto-detected from locale but no manual MM/DD vs DD/MM override.
- **Files:** `NewOnboardingView.swift`

---

### M-19: No Email Verification During Signup
- **Status:** NOT STARTED
- **Priority:** P2 MEDIUM
- **Context:** Supabase supports email confirmation but it needs to be enabled in Dashboard settings.
- **Recommendation:** Enable Supabase "Confirm email" setting and show interstitial after signup.

---

### M-20: Forgot Password Visibility in Onboarding
- **Status:** DONE (already existed)
- **Priority:** P2 MEDIUM
- **Context:** "Forgot Password?" link already visible when user switches to sign-in mode. Verified accessible.
- **Files:** `NewOnboardingView.swift`

---

### M-21: Orphan Test Account Cleanup SQL
- **Status:** DONE
- **Priority:** P2 MEDIUM
- **Context:** Created cleanup_test_accounts() Supabase function to find and delete all *@fit33test.com accounts.
- **Files:** `supabase/cleanup_test_accounts.sql`

---

## UI DESIGN SYSTEM - Token Adoption (from UI_AUDIT_INCONSISTENCIES.md)

### UI-3: Hardcoded Background Colors (`Color(white: 0.12)`)
- **Status:** NOT STARTED
- **Priority:** P2 HIGH
- **Context:** **97 instances across 30 files** still use `Color(white: 0.12)` instead of `Color.cardBackground`. The hardcoded value (0.12 gray) doesn't even match the canonical value (0.14, 0.14, 0.16 with slight blue tint).
- **Top Offenders:** `WeightTrackerWidget.swift` (7), `RecipeImportView.swift` (6), `MealsQuickActionsView.swift` (6), `HealthKitSettingsView.swift` (5), `MealPlanView.swift` (7), `FitbitSettingsView.swift` (8), `ImportedRecipeDetailView.swift` (7)
- **User Impact Before:** Cards on some screens are slightly darker than others — subconsciously registers as "off"
- **User Impact After:** Every card has exactly the same background shade across the entire app
- **Recommendation:** Delete all local `cardBackground` computed properties, use `Color.cardBackground` from AdaptiveColors.swift
- **Files:** 30 files listed above

---

### UI-4: Duplicate ScaleButtonStyle Implementations
- **Status:** NOT STARTED
- **Priority:** P2 HIGH
- **Context:** **7 files** still have duplicate ButtonStyle implementations: `WeightTrackerWidget.swift`, `DashboardView.swift`, `CardioLandingView.swift`, `HydrationWidget.swift`, `MealsQuickActionsView.swift`, `WelcomeTutorialView.swift`, `SharedUtilities.swift` (canonical)
- **Why:** User tapping a card on Meals tab sees 97% shrink; Hydration widget sees 92% shrink — perceptible difference
- **User Impact Before:** Inconsistent tap feedback across screens
- **User Impact After:** Every tappable element has identical, satisfying press feedback
- **Recommendation:** Delete all duplicates, use `UniversalScaleButtonStyle` from `SharedUtilities.swift` everywhere

---

### UI-5: Typography Token Bypass
- **Status:** NOT STARTED
- **Priority:** P2 MEDIUM (Systematic cleanup)
- **Context:** **787+ instances** across 55+ files use `.font(.system(size:))` inline. Only **8 usages** of `.ds_` tokens exist (in `DesignSystem.swift` definitions + `CriticalPathTests.swift`). The design system tokens are defined but have ZERO adoption in actual views.
- **Scale:** This is the single largest design system violation.
- **Top Offenders:** `CommunityChallengeViews.swift` (86), `ProfileView.swift` (49), `ExerciseDetailView.swift` (45), `DailyQuestViews.swift` (42), `WeightTrackerWidget.swift` (41), `WeeklyLeagueViews.swift` (35), `WorkoutProgressView.swift` (35)
- **User Impact Before:** Text hierarchy is subtly uneven — sizes are 1-2pt different between screens
- **User Impact After:** Perfectly calibrated text hierarchy. Headlines, body, labels maintain proportions everywhere.
- **Recommendation:** Add missing token levels (`ds_bodyRegular` 16pt, `ds_caption` 10pt), then batch-replace starting with highest-count files

---

### UI-6: Spacing Token Bypass
- **Status:** NOT STARTED
- **Priority:** P2 MEDIUM (Systematic cleanup)
- **Context:** `Spacing.*` tokens have only **4 usages** across 2 files (both in DesignSystem definitions). ~2,919 instances of hardcoded padding values per original audit. Zero adoption in views.
- **User Impact Before:** Adjacent sections have 14pt on one side, 16pt on the other — subtle visual imbalance
- **User Impact After:** Consistent breathing room everywhere. Elements feel placed on an invisible grid.
- **Recommendation:** Decide on `padding(20)` → `Spacing.md` or `Spacing.lg`; batch-replace standard values

---

### UI-7: Corner Radius Token Bypass
- **Status:** NOT STARTED
- **Priority:** P2 MEDIUM (Systematic cleanup)
- **Context:** `CornerRadius.*` tokens have only **1 usage** (in CriticalPathTests). ~1,213 instances of hardcoded cornerRadius values per original audit.
- **User Impact Before:** Cards with 14pt corners next to 16pt cards — perceptible difference
- **User Impact After:** Every rounded corner uses one of exactly four radii. Predictable, calming visual rhythm.
- **Recommendation:** Eliminate non-standard values (10pt, 14pt, 18pt, 20pt), replace all with tokens

---

### UI-8: Navigation Flow Inconsistencies
- **Status:** PARTIAL
- **Priority:** P2 HIGH
- **Context:** Challenge creation still has two entry points with different presentations. `DashboardView.swift` likely still uses `NavigationLink` for challenge creation while `FriendsTabView.swift` uses `.fullScreenCover`.
- **Why It Matters:** Muscle memory breaks — user expects "back swipe" from one path but must find close button from other
- **User Impact Before:** Same feature feels different depending on where you tap
- **User Impact After:** No matter where user taps "Challenge," same presentation, same animation, same dismiss pattern
- **Recommendation:** Unify to `.fullScreenCover` with NavigationStack for all challenge creation entry points

---

### UI-9: Missing Haptic Feedback
- **Status:** NOT STARTED
- **Priority:** P3 MEDIUM
- **Context:** Only 5 files implement HapticManager calls out of 72+ files with interactive buttons
- **User Impact Before:** Most taps give no tactile feedback — app feels "dead" compared to Apple's apps
- **User Impact After:** Every tap gives tactile confirmation. App feels responsive and alive.
- **Recommendation:** Integrate haptics into `UniversalScaleButtonStyle` with `withHaptic: true` default

---

### UI-10: Inconsistent Button Styles
- **Status:** NOT STARTED
- **Priority:** P3 MEDIUM
- **Context:** Primary action buttons have 3 different paddings, 3 different corner radii, 3 different fonts. Secondary button opacity values not standardized.
- **Recommendation:** Create `DSPrimaryButton` and `DSSecondaryButton` in DesignSystem.swift with standard specs

---

### UI-11: Empty State Inconsistencies
- **Status:** NOT STARTED
- **Priority:** P3 MEDIUM
- **Context:** Each screen has its own empty state with different icon sizes, text styles, spacing. No shared component.
- **Recommendation:** Create `DSEmptyState(icon:title:subtitle:action:)` component

---

### UI-12: Shadow System Inconsistencies
- **Status:** NOT STARTED
- **Priority:** P3 LOW
- **Context:** Shadow parameters vary wildly (radius 4-20, y-offset 2-10, mixed color/opacity schemes)
- **Recommendation:** Define shadow tokens in DesignSystem.swift: `.subtle`, `.standard`, `.elevated`, `.glow`

---

### UI-13: Divider Padding Inconsistencies
- **Status:** NOT STARTED
- **Priority:** P3 LOW
- **Context:** Divider leading padding ranges from 16pt to 60pt
- **Recommendation:** Standardize: 52pt with icons, Spacing.md without

---

### UI-14: Non-Standard Gradient Backgrounds
- **Status:** PARTIAL
- **Priority:** P2 MEDIUM
- **Context:** Orb backgrounds were added (fixing the primary issue), but some views may still have inline gradient definitions in sub-components
- **Recommendation:** Audit remaining inline `LinearGradient` definitions and replace with `AdaptiveGradient` presets

---

## LOW - Post-Launch

### L-1: App Store Review Request Timing
- **Status:** NOT STARTED
- **Priority:** P4 LOW
- **Recommendation:** Implement review prompts after positive moments with proper rate limiting

---

### L-2: Image Loading Without Placeholders
- **Status:** NOT STARTED
- **Priority:** P4 LOW
- **Recommendation:** Add shimmer/skeleton loading states for async images

---

### L-3: No Data Export / Backup Feature (GDPR)
- **Status:** NOT STARTED
- **Priority:** P4 LOW (but GDPR may make it P2)
- **Recommendation:** Implement CSV/JSON export in existing `DataDownloadView.swift`

---

### L-4: Background App Refresh Reliability
- **Status:** NOT STARTED
- **Priority:** P4 LOW
- **Recommendation:** Fix force cast in `BackgroundChallengeSyncService.swift`, add exponential backoff

---

### L-5: Edge Function Error Handling
- **Status:** NOT STARTED
- **Priority:** P4 LOW
- **Recommendation:** Create shared error handler, standardize across 6 edge functions

---

### L-6: Cascade Deletion Removes Historical Data
- **Status:** NOT STARTED
- **Priority:** P4 LOW
- **Recommendation:** Archive before deletion, show "[Deleted User]" in leaderboards

---

## ARCHITECTURE & TECH DEBT

### A-1: Singleton Overuse (40+)
- **Status:** NOT STARTED (Long-term)
- **Context:** 40+ `.shared` singletons. Can't mock for tests, tight coupling, implicit initialization order.
- **Recommendation:** Document all singletons first, then gradually migrate to DI

---

### A-2: File Size Issues
- **Status:** NOT STARTED (Long-term)
- **Context:** `ContentView.swift` ~3000+ lines, `SupabaseManager.swift` ~2500+ lines, `DashboardView.swift` very large with 60+ @State properties
- **Recommendation:** Split into focused components (ContentView → tab containers, SupabaseManager → Auth/Profile/Sync services)

---

### A-3: No Unit Tests
- **Status:** NOT STARTED (Long-term)
- **Context:** No XCTest target. "Test" files are in-app diagnostics, not actual unit tests.
- **Recommendation:** Create test target, write tests for critical business logic (streak calc, XP, calorie math)

---

## CODEBASE PATTERNS & TRENDS OBSERVED

### Positive Patterns
1. **Strong design system foundation** — `DesignSystem.swift`, `AdaptiveColors.swift`, `SharedUtilities.swift` define comprehensive tokens
2. **Consistent singleton pattern** — Services follow `ClassName.shared` convention
3. **AnimatedOrbBackground** — Now adopted across all full-page screens (great improvement)
4. **SleekCard system** — Premium 5-layer card system is well-architected
5. **Secrets template pattern** — Established for 3rd-party API keys

### Concerning Patterns
1. **Design system exists but isn't used** — 0 usages of `Spacing.*`, 1 usage of `CornerRadius.*`, 8 usages of `.ds_` tokens vs 787+ inline font styles. The system was built but never adopted.
2. **Massive files** — Multiple files exceed 1000+ lines suggesting responsibility sprawl
3. **Hardcoded values everywhere** — 97 `Color(white: 0.12)`, 787+ inline fonts, 2919+ hardcoded padding, 1213+ hardcoded corner radii
4. **No testing infrastructure** — Zero XCTest, no CI/CD, no automated validation
5. **Security credentials in source** — Supabase URL+key and dev password still in committed code
6. **Silent failures** — Network operations fail without user feedback
7. **Duplicate implementations** — 7 different ScaleButtonStyle implementations for the same behavior

### Key Metrics Summary

| Metric | Current | Target | Gap |
|--------|---------|--------|-----|
| `.ds_` font token adoption | 8 usages (0.4%) | 100% | **1,821 inline fonts to fix** |
| `Spacing.*` adoption | 4 usages (0.8%) | 100% | **519+ hardcoded paddings to fix** |
| `CornerRadius.*` adoption | 1 usage (0.3%) | 100% | **338 hardcoded radii to fix** |
| `Color(white: 0.12)` violations | **141 in 46 files** | 0 | 141 to fix |
| `.shadow()` without tokens | **660 in 98 files** | Tokenized | 660 to standardize |
| Duplicate ScaleButtonStyles | 6 duplicates | 0 | 6 to delete |
| `.sleekCard()` adoption | 52 usages in 17 files | All content cards | Expand |
| AnimatedOrbBackground | 51 of 97 view files (52.6%) | All full-page screens | DONE for main screens |
| NavigationView usages | 3 | 0 | 3 to fix |
| Accessibility labels | ~14 | 500+ | ~486 to add |
| XCTest unit tests | 0 | 100+ | 100+ to write |
| `[weak self]` usage | 5 instances | All async closures | **Critical gap** |
| Force unwraps (`!`) | 118 across 29 files | 0 in production paths | 118 to fix |
| Empty state components | 0 unified | 1 `DSEmptyState` | 928+ empty checks to standardize |
| Total codebase | 253,399 lines / 256 files | — | — |

---

## IMPLEMENTATION PRIORITY ORDER

### Sprint 1: Security & App Store Blockers (Week 1)
1. C-1: Move Supabase credentials to Secrets pattern
2. C-2: Remove dev menu password from source
3. H-5: Move Strava/Fitbit client IDs to Secrets
4. C-4: Implement App Tracking Transparency
5. C-8: Fix admin XSS-vulnerable session storage
6. H-11: Fix 3 remaining NavigationView usages

### Sprint 2: Monetization & Data Integrity (Week 2)
7. C-3: StoreKit 2 integration
8. C-5: RLS policies for challenge tables
9. C-6: Atomic challenge creation RPCs
10. C-7: Timezone consistency
11. H-10: Challenge progress validation

### Sprint 3: Reliability & Polish (Week 3)
12. H-3: Input validation
13. H-4: Offline mode / network error handling
14. UI-3: Replace all `Color(white: 0.12)` with tokens
15. UI-4: Delete duplicate ScaleButtonStyles
16. UI-8: Unify navigation flow patterns
17. H-12 (DONE), H-14 (DONE), H-15 (DONE)

### Sprint 4: Design System Enforcement (Week 4+)
17. UI-5: Typography token adoption (787+ replacements)
18. UI-6: Spacing token adoption (2919+ replacements)
19. UI-7: Corner radius token adoption (1213+ replacements)
20. UI-9: Haptic feedback integration
21. UI-10: Button component standardization

### Sprint 5: Infrastructure (Ongoing)
22. H-1: print() → AppLogger migration
23. H-2: Accessibility support
24. M-11: CI/CD pipeline
25. A-3: Unit test infrastructure
26. H-13 (DONE), M-16 (DONE), M-17 (DONE), M-19 (NOT STARTED), M-21 (DONE)

---

*This document consolidates ALL findings from IMPROVEMENT.md, UI_AUDIT_INCONSISTENCIES.md, and a fresh codebase scan. It is the single source of truth for what needs to be done.*
