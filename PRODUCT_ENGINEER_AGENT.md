# Fit33 Lead Product Engineer Agent

> **Role**: Functional correctness, navigation, component reuse, feature integration, UI logic.
>
> Deep history, sprint changelogs, and feature-by-feature notes (AI insights, WHOOP, Oura, push reliability, etc.) live in [`docs/history/PRODUCT_ENGINEER_AGENT.md`](docs/history/PRODUCT_ENGINEER_AGENT.md). This file is **rules-shaped**.

Cross-cutting rules (logging, force unwraps, design tokens, structured concurrency, accessibility, RLS, security-definer views, Core Data threading, widget isolation, etc.) live in `.cursor/rules/codingrules.mdc` (universal) and `.cursor/rules/swiftui-rules.mdc` (auto-loads when editing `Fit33/**/*.swift`). Don't duplicate them here.

---

## Invariants (PE-specific — will cause bugs if violated)

### Auth + data loading
1. **Auth guard on every social fetch.** Every async fetch in social/challenge/friend services starts with `guard SupabaseManager.shared.isAuthenticated else { return }`. `MainTabView` appears on `hasCompletedOnboarding`, NOT `isAuthenticated` — `.task` fires before auth completes.
2. **Network calls in parallel.** All independent network calls in `.task`/`.onAppear` use `async let` groups, never sequential `await`. Dashboard runs all 14 fetches in one group.
3. **`@FetchRequest` MUST set `fetchLimit`** when displaying a bounded list (e.g. `prefix(10)` → `fetchLimit: 10`). Dashboard uses 10.
4. **No duplicate fetches across `.task` and `.onAppear`.** `.onAppear` fires on every tab return. Foreground refresh is centralized in `Fit33App.swift` scenePhase.

### Navigation
5. **Same destination = same presentation.** Multi-step creation = `.fullScreenCover` + inner `NavigationStack`. Detail push = `NavigationLink`. Quick picker = `.sheet`.
6. **Never nest `NavigationStack` inside a pushed detail view.** Pushed settings views (`HealthKitSettingsView`, `StravaSettingsView`, etc.) must NOT wrap themselves in `NavigationStack` — only sheet/fullScreenCover entry points host one. Nesting breaks `.navigationDestination` and bounces to root on `dismiss()`.
7. **No placeholder destinations in shipped `Destination` enums.** If a real view isn't ready, remove the entry point (chevron/card). "Coming Soon" screens = App Review rejection. Canonical example: `DashboardRoute.programDetailsPlaceholder` (entry removed 2026-04-17).
8. **Every Settings row must do something.** Empty `// Navigate to X` closures are ship blockers. "Help / Rate / Support" → `SFSafariViewController` on `AppConfig.Support.helpCenterURL` or `SKStoreReviewController`.

### Widgets + dashboard
9. **Widget isolation in ScrollViews (mandatory).** Any widget in a ScrollView with 5+ siblings MUST be its own `View` struct that owns its service subscriptions (`@StateObject`/`@ObservedObject`). Parent views pass only stable values to wrappers. Canonical: `DashboardQuestsWrapper`, `DashboardHeaderWrapper`, `DashboardChallengesWrapper`, `DashboardWorkoutCarouselWrapper`, `DashboardQuestCelebrationWrapper`. Parent `DashboardView` keeps services as plain `let`, not `@StateObject`.
10. **Celebration overlays MUST live in a wrapper.** Overlays that read service `@Published` state (`showQuestCompletionCelebration`, toasts, banners) must be in a dedicated wrapper with `@StateObject`. Reading from a plain `let` in the parent body = overlay never fires.
11. **Horizontal drag in vertical ScrollView:** `.simultaneousGesture(DragGesture(minimumDistance: 25))` — never `.highPriorityGesture` with low minimum. High priority + 8pt steals vertical scroll touches. *Exception*: carousel that hosts tappable buttons uses `.highPriorityGesture(DragGesture(minimumDistance: 25))` to prevent button taps during swipes.
12. **Dashboard notification cards = one carousel.** All notification types (friend requests, received workouts, 1v1/group/private invites) live in `DashboardNotificationCarousel` (in `DashboardModels.swift`). Add new types to the `NotificationItem` enum, never a sibling container. Sort: friend requests first, then oldest-first.

### Social writes
13. **Every successful social write ends with a push flush.** `FriendService`, `ChallengeService`, `CommunityChallengeService`, `PrivateChallengeService`, `ActivityFeedService`, `CardioActiveWorkoutView.saveWorkout` all call `PushNotificationService.shared.flushPushNotificationQueue(triggeredBy:)` after the write succeeds.
14. **Every workout-type completion calls its `UserManager.complete*Workout(...)`.** Strength via `completeWorkout`, cardio via `completeCardioWorkout`. Skipping breaks XP, streak, feed, quests, challenges, and badges silently.

### Active workout state integrity
14b. **Every mutation of `ActiveWorkoutView.exercises` MUST call `syncExercisesToWorkoutManager()`.** `exercises` is local `@State`; `WorkoutManager.currentExercises` is the ground truth that `saveActiveWorkoutToStorage()` serializes to UserDefaults. Any add / remove / shuffle / drag-reorder that skips the sync gets silently dropped when iOS suspends or kills the app — the user returns to only the original `startWorkout()` list. Canonical call sites: `removeExercise(at:)`, `shuffleExercise(at:with:)`, `onDragEnded` (+Layout), and the `onAddExercise` callback in the fullScreenCover (+Layout).
14d. **ExerciseCard "last 3 sessions" tile row reads through `ExerciseHistoryService.shared.fetchRecentSessions(for:limit:)` — never subscribe `ExerciseHistoryService` as `@ObservedObject` from inside `ExerciseCard`.** The tile row sits above `columnHeaders` and shows up to 3 condensed tiles (avg weight + short date) sourced from the `exercise_performance_history` table. Storage rules: `ExerciseHistoryService` owns a `recentSessionsCache: [String: [ExerciseSessionSummary]]` keyed by exercise name + an `inFlightSessionTasks` map for dedupe; results (including empty arrays) are cached. Cache is cleared by `clearCache()` and per-exercise inside `saveExercisePerformance` so a freshly-finished workout shows up in the tile row on the next open. ExerciseCard holds `@State private var recentSessions: [ExerciseSessionSummary]` + `didLoadRecentSessions: Bool` — fetched lazily once on `.onAppear`, reset + refetched on `.onChange(of: exercise.id)` (shuffle/replace path), name-stale-guard before assigning. **Do NOT** add `@ObservedObject var historyService = ExerciseHistoryService.shared` to ExerciseCard — that re-renders every card on every cache mutation and violates Widget Isolation (Invariant 9). The tile row uses `Color.cardBackgroundSecondary` + `CornerRadius.sm` + `ds_labelMedium` / `ds_labelSmall` (NOT `.sleekCard` — these are subtle list-row chips, not primary cards) and respects `useKg` for unit conversion (`* 0.453592`).
14c. **`ActiveWorkoutView.workoutBackground` MUST layer an opaque `Color` BEHIND `AnimatedOrbBackground.workoutStatic`.** ActiveWorkoutView is rendered as a `zIndex(10)` overlay on top of `WorkoutTabView` (see `WorkoutTabView.swift` Layer 3), which has its own orb background, "Workout" header, exercise list, and tab bar. `AnimatedOrbBackground.workoutStatic` uses `AdaptiveGradient.universalDark` in dark mode, which begins with `purple.opacity(0.2)` + `blue.opacity(0.1)` — translucent. Without an opaque base (`Color(red: 0.04, green: 0.04, blue: 0.06)` dark / `Color(.systemGroupedBackground)` light), the underlying tab bleeds visibly through the active workout, producing a stacked / "ghosted" UI. Active workout is the only full-screen overlay using a `zIndex` push (not a system fullScreenCover/sheet, which iOS opaques automatically) — never strip the opaque base when refactoring this background. Also use `workoutStatic` not `workout` here: every CPU cycle goes to rest timers + screen-stays-on, no decorative animation can compete.

### Onboarding
15. **For email/password signup, create the Supabase auth user in the SAME step where the password is entered.** `@State password` does NOT survive 5+ onboarding step transitions. `handleAuth()` now calls `signUpOrRecoverExistingAccount()` early (before OTP step). OAuth flows are fine as-is.
16. **Validate sync input before any cloud-write `Task`.** `completeOnboarding()` parses `weight` at the top, guards on failure, surfaces `OnboardingError.invalidWeight` via `@State completionError` + `.confirmationDialog` with Edit / Start Over / Cancel. Start Over → `rollbackCloudProfileIfNeeded()` → idempotent `SupabaseManager.deleteAccount()`. Orphan cloud profiles are a P0 support trap.
17. **Feature-flag unfinished insights.** `AppConfig.FeatureFlags.personalizedInsightsV2` gates `detectBestWorkoutTime`, `analyzeHydrationPerformanceCorrelation`, `detectNutritionPatterns`, `detectSocialPatterns`. Never surface coaching copy backed by stub logic without a flag.

### Profile
18. **`ProfileUser`** (in `FriendProfileView.swift`) is the universal model for displaying any user profile. Convenience inits: `Friend`, `UserSearchResult`, `SuggestedFriend`, `LeagueEntry`, `CommunityLeaderboardEntry`, `FriendActivity`. **`FriendProfileView`** accepts a `ProfileUser` — friends show full profile, non-friends show streamlined card. Never create a separate profile view.
19. **Daily Goals never return empty.** Every `DailyQuestService` code path (no auth, server error, empty response) falls back to `defaultGoals()`. Experienced users (`totalWorkouts > 0`) get generic real quests; beginners get onboarding quests. Never ship the "Daily Quests" placeholder.
19b. **Daily Goals v3 (Smart Adaptive — migrations 20260601–20260607).** `get_daily_quests` v3 is the canonical entry; old overloads were dropped via the `pg_proc` loop pattern (Supabase invariant 12). New required client surface: `DailyQuestService.gatherUserContext()` populates split wearable bools (`stravaConnected` / `whoopConnected` / `ouraConnected` / `fitbitConnected`), `activityMix28d` (computed from Core Data `Workout` + `cardio_workouts` last-28d, exposes `dominant`/`least`/`rpcHint`), and friend seeds (`friendStepTarget`, `friendName`, `friendTopWorkoutId/Title/Split`, `friendTopWorkoutMatchesRecommendation` — split-recovery-aware via `WorkoutSuggestionEngine`). XP rewards in `quest_templates` are pre-multiplied by verification type (`auto×1.5`, `social×1.0`, `manual×0.7`) — never re-multiply on the client; surface the asymmetry via `DailyQuest.verificationXpMultiplierLabel` ("1.5× XP — auto-tracked" / "1.0× XP — social" / "0.7× XP — honor system"). New columns on `user_daily_quests`: `tier`, `double_xp`, `is_custom`, `is_reroll` — drift in the Codable mapping silently strips the badges off Pro quests. Suppression is server-driven: when a user's `(user_id, category)` row in `user_quest_personalization` has `skip_streak >= 3 AND completion_rate_28d < 0.20`, `suppressed_until` is set to `today + 14d` and the RPC excludes that pool. A single completion auto-clears it. Pro-only override is `unsuppress_quest_category(p_category, p_is_pro)`; surface from `Fit33/QuestInsightsView.swift` (28-day completion bars + suppressed-list with one-tap "Resume"). Master kill-switch: `AppConfig.FeatureFlags.smartAdaptiveQuests`.
19c. **Integration verification fanout is fire-and-forget detached.** `Fit33/StravaService.syncActivities` ends with `Task.detached(priority: .background) { await DailyQuestService.shared.onStravaActivityImported() }` (calls `verify_strava_quests_for_today`); `Fit33/ReadinessService.recompute` ends with the symmetric `onReadinessRecomputed()` (calls `verify_wearable_quests_for_today`). Never `await` these in the sync return path — they must not block the dashboard refresh. The verify RPCs are `auth.uid()`-pinned and short-circuit cheaply when no eligible quests are assigned today.
19d. **Daily quests must be actionable TODAY, not pre-determined by overnight sensor state.** A quest whose pass/fail is locked-in before the user opens the app (e.g. "wake up with HRV above baseline") is an automatic-loss for any user whose night was off — design anti-pattern. Six retired examples (migrations `20260610_actionable_recovery_quests.sql` + `20260611_retire_passive_sleep_engagement_quests.sql`): wearable-recovery (`recovery_above_67` "Green Recovery", `hrv_above_baseline` "HRV Warrior", `rhr_in_healthy_range` "Steady Heart") + sleep (`sleep_8h_wearable` "Sleep 8 Hours", `sleep_7_hours` "Sleep Champion") + engagement (`log_readiness_am` "Morning Check-In" — also had zero verification logic anywhere, was a phantom quest). Replacements MUST require an action the user can take during the day — e.g. `active_recovery_logged` (15+ min walk/yoga/stretch any band), `zone_2_minutes_20` (HR 110–150 cardio session), `cardio_minutes_20` (logged cardio session), `evening_wind_down` (recovery cardio after 6pm local). Retire passive sensor-state quests by `is_active = FALSE` (keep the row so historical `user_daily_quests` resolve to a template) — never `DELETE` the template. Phantom quests (templates with NO verifier anywhere) ARE eligible for an in-flight cleanup `DELETE FROM user_daily_quests WHERE quest_key = '...' AND quest_date = current_date AND is_completed = FALSE` so users don't stare at a permanently-stuck 0/1 quest until daily reset; only do this for templates whose Swift + SQL verifier surface is genuinely empty (grep `Fit33/**/*.swift` and `supabase/**/*.sql`). Verification logic for soft-disabled functional passive quests stays behind `IF v_readiness IS NOT NULL` guards inside `verify_wearable_quests_for_today` so in-flight assignments still complete. The iOS `DailyQuestService.onSleepLogged(hours:)` hook is now a no-op but kept as a future attach point — don't delete it; if a future actionable sleep quest lands (e.g. "wind down by [target]" detected from tonight's bedtime), it attaches there.

### Exercise Library + search
22. **Exercise Library never renders a loading / grey placeholder.** `ExerciseLibraryService.preWarmCache()` runs in `Task.detached` and, if Core Data has <100 exercise rows, inline-seeds the bundle JSON in the same `bgContext.perform` transaction BEFORE flipping `isExercisesReady`. `Fit33App.init()` touches `ExerciseLibraryService.shared` on its very first line so pre-warm fires ASAP. `ExerciseLibraryView` filters empty-name rows out of its `ForEach`. Never re-add a `ProgressView`/skeleton branch — fix the data layer if rows are missing.
23. **Exercise name lookups MUST use `ExerciseLibraryService.getExercise(byName:)`.** Never use raw `NSFetchRequest` / `NSPredicate(format: "name == %@")` in services or views. The service's fuzzy match handles historical naming-convention changes (equipment prefix/suffix swaps, dash normalization, Smith Machine variants). Results are cached — don't add debug logs inside the fuzzy path without caching, or it spams during active workouts.
24. **Search / typo / variation / equipment-matching logic lives in services, never inline in a view.** Add to `SmartExerciseSearchService` or `ExerciseFilterService.normalizeEquipment()`. Views consume results.
24b. **"Complements Your Workout" suggestions auto-hide during active search and support shuffle.** In `CustomWorkoutBuilderView` (add-to-workout mode), the complementary-suggestions block hides whenever `isSearchFocused || !searchText.isEmpty` so it never covers intentional search results. Replace-mode suggestions stay visible (they ARE the primary UI). Candidates are pre-partitioned into up to 3 pages of 3 via `complementaryPages` in `loadComplementarySuggestions`; the Shuffle pill cycles `complementaryPageIndex` locally — do NOT re-query `ExerciseSwapService` on every shuffle tap.

### Quests — live value source
25. **Every `liveCurrentValue` switch case MUST use `max(localValue, quest.currentValue)`** so progress never regresses below the last server sync when HealthKit/services haven't repopulated local state. Exceptions: binary quests where the local check is authoritative (e.g., `logBreakfast` reads `todaysMeals` directly).
25b. **Welcome card recommendation is quest-state-aware.** `AdvancedIntelligenceService.getPersonalizedRecommendation` MUST (a) fire the "close the gap" priority (Priority 1.5, `getNearlyCompleteQuestNudge`) before any workout-suggestion priority when ≥1 quest is already complete and another open quest is ≥60% live-progress, and (b) suppress the workout-suggestion priority via `hasCompletedWorkoutQuestToday()` so a user who already trained today isn't told to go do legs again. `liveQuestValue(for:)` MUST stay in sync with `DailyQuestsWidget.liveCurrentValue` — when adding a new live-backed quest key, update both. Dashboard re-runs `loadPersonalizedRecommendation()` on `dailyQuestService.completedCount` change so the card flips the moment a quest ticks complete.

### Performance hooks (see `QUALITY_PERFORMANCE_AGENT.md` for the full list)
26. **Apply `.trackScrollJank(screen: "ScreenName")` to new scrollable content.** Heavy computation inside scroll cell bodies must run off main thread (background Core Data context or `Task.detached`).

### Realtime Widget Server Pull (2026-04-26 sprint)
29. **Widget extension is a server-pull client, not a snapshot reader.** `RunningActivityWidget/ActiveChallengeWidget.swift::ActiveChallengeProvider.timeline` MUST attempt a 3-second-timeout direct Supabase pull via `WidgetSupabaseFetcher.fetchActiveChallenges()` BEFORE falling back to the App Group cache. The fetch path uses raw `URLSession` (not the supabase-swift SDK — extensions have a ~30MB memory ceiling and the SDK pulls in Auth + PostgREST + Realtime + Storage). Successful pulls land in App Group `UserDefaults` only via `writeIfChanged()` (hash-gated to avoid unnecessary `WidgetCenter.reloadAllTimelines()` storms). After every successful write, the widget posts Darwin notification `com.fit33.app.widgetActiveChallengePayloadChanged` so the main app can re-fetch its own copy and stay in lockstep. The main app subscribes via `ActiveChallengeWidgetBridge.startWidgetPullListener()` (registered in `Fit33App.swift::task` after `supabaseManager.isAuthenticated`).
30. **Stale opponent data MUST render `—` + age label, not a confident `0`.** `Shared/ProgressFreshness.swift::ProgressFreshnessKit` is the single source of truth for `.fresh` / `.recent` / `.stale` / `.unknown` classification (thresholds: 30m / 2h / 24h). The widget mirror at `RunningActivityWidget/ProgressFreshness.swift` MUST be byte-for-byte identical — duplication is intentional (no cross-target module dependency). Any `Text` rendering opponent progress in widget surfaces (`CompetitionRow`, `CompactSideColumn`) AND in-app surfaces (`DashboardView+Challenges.swift::competitionProgressSection`) MUST gate the raw value through `ProgressFreshnessKit.shouldShowRawValue(for: opponentLastProgressAt)`. Crown / "you're winning" / progress-tint logic must ALSO require `oppShowsRaw` — claiming victory based on stale data is the original "0 steps for someone in a step challenge" bug.
31. **Widget refresh button is an `AppIntent`, never a deep link.** `RunningActivityWidget/RefreshChallengeIntent.swift` is the only interactive control on the home-screen widget. It MUST set `static let openAppWhenRun = false` (runs in-extension, no UI launch) and `static let isDiscoverable = false` (hidden from Shortcuts). Throttle min 5s between fires; the `perform()` call drives the same `pullAndMergeIfPossible()` + `WidgetCenter.shared.reloadTimelines(ofKind:)` path the timeline uses. Never replace the swords / handshake mode emojis with anything that opens the app — that's a deeplink, not a refresh.
32. **Engagement nudge type `challenge_nudge` is server-fired, hourly cron.** `enqueue_engagement_nudges_for_stale_opponents()` (Supabase migration #123 / 20260621) runs `0 * * * *` UTC and enqueues into `push_notification_queue` for any 1v1 participant who has been silent ≥12h while their opponent has logged inside the same window. iOS routing lives in `NotificationManager.swift` — `case "challenge_nudge"` in BOTH the foreground `willPresent` switch (refresh + HK sync) AND the deep-link tap router (refresh + HK sync + deep-link to `.challengeDetail(challengeId:)`). The `NotificationType.challengeNudge` enum case + `knownNotificationTypes` allowlist + `NotificationCategory.social.notifications` parity are enforced by `NotificationAllowlistTests` — a missing entry breaks tests. Throttle is per-(recipient, challenge) over 20h, NOT per-recipient — a user in three stale challenges should get up to three nudges per cycle, each individually actionable.
33. **Apple Watch companion is OPTIONAL — phones-only path stays viable.** `Fit33Watch Watch App/` (added 2026-04-26) is a watchOS app whose **primary purpose remains the headless background writer** (HealthKit step / active-energy / exercise-minute totals → Supabase via `HKObserverQuery + enableBackgroundDelivery`). The phone app MUST NOT depend on the watch being installed: `Fit33/PhoneToWatchSyncBridge.swift::refreshContext` no-ops when `WCSession.isWatchAppInstalled == false`, and the iPhone HK observer path remains the writer of last resort. Watch reads the supabase-swift session JWT from App Group `group.com.fit33.app` (read-only — never refreshes tokens, never authenticates). When the user uninstalls the watch app, no broken state, no forced re-auth.

    **Foreground UI is purely additive enrichment** (shipped 2026-04-26 watch UI sprint) and MUST NOT regress the headless writer:
    - HK observer registration stays in `Fit33WatchApp.task` → `WatchLifecycle.bootstrap()` (NEVER in `WatchTodayView.onAppear`) so background-launched processes still wire up the writer without showing UI.
    - `WatchHealthKitWriter.todayTotal(for:)` is `internal` so the foreground `WatchTodayStore` reuses the same aggregation path the writer uses (no duplicate HK plumbing).
    - Stale opponent data MUST gate through `ProgressFreshnessKit.shouldShowRawValue(for:)` — third byte-for-byte copy of `Fit33/ProgressFreshness.swift` lives at `Fit33Watch Watch App/ProgressFreshness.swift` (PE invariant 30 applies).

    **Wire-format invariant** for WCSession `applicationContext` (KEEP IN LOCKSTEP — `Fit33/PhoneToWatchSyncBridge.swift::refreshContext` ↔ `Fit33Watch Watch App/WatchConnectivityBridge.swift::consume`):
    ```
    {
      v: 1,
      challenges: [{ id: <uuid>, type: "steps"|"calories"|"active_minutes" }],
      liveWorkout: {
        active: <bool>,
        exerciseId: <uuid>, exerciseName: <string>,
        setIndex: <int 0-based>, totalSets: <int>,
        targetWeight: <Double?>, targetReps: <int>,
        restEndsAt: <ISO8601 | nil>
      }   // optional — present only during a live strength workout
    }
    ```
    The merged context is rebuilt + sent by `PhoneToWatchSyncBridge.shared.refreshContext()` from BOTH sides — `sendActiveChallenges(_:)` updates the challenges slot, and `PhoneToWatchLiveWorkoutBridge.shared.pushExercise / pushRestEndsAt / clearLive` updates the liveWorkout slot. Each push triggers `refreshContext()` which is idempotent (skips when the merged payload is byte-identical to the last send).

    **Watch → iPhone messages**: only `{ action: "completeCurrentSet", exerciseId, setIndex }` is supported (sent from `WatchLiveWorkoutStore.completeCurrentSet()`, received by `PhoneToWatchSyncBridge.session(_:didReceiveMessage:)` and routed to `PhoneToWatchLiveWorkoutBridge.applyCompleteCurrentSet`). The phone applies the action through `WorkoutManager.addSetToExercise(id:set:)` — the same path the manual tap takes — so PE invariant 14b is automatically respected (we never touch `ActiveWorkoutView.exercises` from the watch path). New action types must be added to the `didReceiveMessage` switch AND documented here.

    **Hydration / protein / nutrition** NEVER sync to the watch (those are user-input on the phone).

    **Complication target** (`Fit33WatchComplications/`) reads an App Group snapshot blob (`fit33.watch.today_snapshot.v1`) that `WatchTodayStore.writeSnapshot()` writes after every successful refresh. Complications NEVER make their own RPC — extension memory budget is too tight (~5MB).

### Readiness override transparency (FE invariant 23 surface contract)
27. **Whenever auto-gen replaces the user's request with a recovery day, the surface that displays the replaced workout MUST render `ReadinessAdjustmentBanner` above the exercise list.** FITNESS_EXPERT_AGENT invariant 23 (red WHOOP/Oura recovery → mobility/stretch/yoga override) is intentionally invisible to the generator's call site, so the user-facing rationale is the responsibility of the previewing view. Canonical call sites: `ActiveWorkoutView` (already wired) AND `AutoWorkoutPreviewView.exerciseListView` (added 2026-04-25 for Bug-Intel `164c76d8`). The banner is a no-op when `snapshot.hasWearableSignal == false` OR `AppConfig.FeatureFlags.readinessAdaptiveAutoGen == false`, so dropping it on a non-wearable screen is a silent zero-impact ship — but on a wearable screen, the user gets stretches with no explanation, files a "AutoGen is broken" bug, and we lose trust. Pass the same `ReadinessWorkoutAdjuster.adjustment(for:requestedCount:)` the generator used so the banner copy matches the actual swap. Future surfaces that show generated workouts (e.g. SmartWorkoutPreviewView) inherit this invariant.

### Wearable sync recompute chaining (launch-race contract)
28. **Every fire-and-forget wearable force-sync MUST chain `await ReadinessService.shared.recompute(force: true)` after the sync completes.** `Fit33App.swift` `scenePhase == .active` runs `WhoopService.syncAllData(force: true)` and `OuraService.syncAllData(force: true)` in their own `Task` to refresh dashboard widgets, AND in parallel kicks off the coordinated foreground Task that calls `HealthDataService.syncAllHealthData → ReadinessService.recompute`. Inside that pipeline, `syncWhoopData(force: false)` hits the `WhoopService.isSyncing` guard set by the line-707 force-sync and short-circuits, so `recompute` runs against the OLD `@Published` WHOOP state and writes a stale band/score to the dashboard (and persists it to `daily_readiness_history`). User-visible symptom: WHOOP icon connected, score shown is yesterday's. Fix: chain `recompute(force: true)` directly inside the wearable's force-sync Task — the recompute path is read-only (does NOT trigger any wearable sync per ReadinessService invariant #33), so chaining cannot recurse. If a new wearable is added (Garmin / Apple Watch direct), apply the same pattern. Bug-Intel `c1bf13fe` was the canonical bug; runtime snapshot confirmed `whoopLastSyncAgeSec=29s` but `lastComputedAgeSec=38s` — readiness computed BEFORE WHOOP's fresh data arrived. (See migration #116 / 2026-04-25.)

### Blocking + reporting (App Store compliance)
20. `BlockedUsersView` lives in Settings → Privacy & Security. Long-press "Report & Block" `.contextMenu` on private-challenge chat (`PrivateChallengeDetailView`) and activity feed cards (`FriendActivityFeedView`). Both call `FriendService.reportContent(...)` + `FriendService.blockUser(userId:)` and purge local state. Never build a new reporting UI — extend this pattern.
21. **Moderation hide propagates via realtime.** Sender's own flagged row disappears via `RealtimeService.subscribeFriendActivityFeed` (UPDATE → `ActivityFeedService.applyModerationHide`) and `PrivateChallengeService` UPDATE sub (→ `hiddenChatMessageIds: Set<UUID>`). Any new social surface the moderation webhook can hide MUST register a realtime UPDATE handler.

---

## Architecture Map (trimmed)

### Tab shell
- `Fit33App.swift` — entry + environment injection (lightweight init; heavy work deferred via `DeferredInit` block on background)
- `ContentView.swift` — onboarding gate (~113 lines)
- `MainTabView.swift` — tab bar + deep link handling

### Tabs
- **Dashboard**: `DashboardView.swift` + `DashboardView+{Header,Challenges,Programs,Macros,Activity,Helpers}.swift` + `DashboardModels.swift`, `DashboardNavigationDestinations.swift`, wrapper widgets in `DashboardView+Helpers.swift`.
- **Workout**: `WorkoutTabView.swift`, `ActiveWorkoutView.swift` + `+{Layout,Init,Actions,Persistence}.swift`, `ExerciseCard.swift`, `WorkoutSetViews.swift`, `WorkoutDataModels.swift`, `RestTimerViews.swift`.
- **Meals**: `SimpleMealPlanView.swift`, `MealPlanComponents.swift`, `NutritionModels.swift`, `USDAFoodSearch.swift`.
- **Social**: `FriendsTabView.swift`, `FriendsListView.swift`, `FriendProfileView.swift`.
- **Profile**: `ProfileView.swift`.

### Onboarding
- `NewOnboardingView.swift` + `+{Chrome,Navigation,Auth,Verification,Steps,Social,Completion}.swift`
- `OnboardingInfrastructure.swift`, `OnboardingFormControls.swift`, `OnboardingCardViews.swift`, `OnboardingConfirmationViews.swift`, `OnboardingLimitationViews.swift`, `OnboardingPhotoPickers.swift`

### Shared (use, never duplicate)
| File | Provides |
|---|---|
| `DesignSystem.swift` | `Font.ds_*`, `Spacing.*`, `CornerRadius.*`, `LinearGradient.ds_*`, `SectionHeader`, `DSCard`, `DSPillButton` |
| `AdaptiveColors.swift` | `Color.cardBackground`, `Color.adaptiveText`, `SleekCardBackground`, `.sleekCard()`, `AnimatedOrbBackground`, `AdaptiveGradient` |
| `SharedUtilities.swift` | `UniversalScaleButtonStyle`, `.scaleButtonStyle()`, `HapticManager` |

### Canonical components to REUSE (never duplicate)
- `AnimatedOrbBackground.{home,workout,exercises,meals,stats,friends,onboarding}()`
- `.sleekCard(cornerRadius:accentColor:)`
- `SectionHeader(title:icon:iconColor:action:actionLabel:)`
- `DSPillButton(title:icon:gradient:action:)`
- `UniversalScaleButtonStyle` (`.subtle` / `.standard` / `.pronounced`)
- `HapticManager.impact(.light)`, `.notification(.success|.error)`

Known duplicates to collapse (not urgent refactors — do opportunistically):
`ScaleButtonStyle` (HydrationWidget, DashboardView+Programs), `MealsScaleButtonStyle`, `CardioScaleButtonStyle`, `TutorialScaleButtonStyle`, `WorkoutDepthButtonStyle`, `SubtleIndentButtonStyle` → all `UniversalScaleButtonStyle`. Local `cardBackground` (71 files) → `Color.cardBackground`.

---

## Additional Owned Domains

- `GenderFilterService.swift`, `ExerciseTypes.swift`, `ExerciseCardRow.swift`
- `ActiveWorkoutView.swift` + `ActiveWorkoutTests.swift` (16 tests)
- `ExerciseSwapService.swift` (co-owned with Fitness Expert)
- `ProgressiveWorkoutIntelligence` — progressive overload
- Localization / iPad form factor (with Device Compatibility Agent)

---

## Key Established Rules
- "pending" challenges never receive progress updates — only "active".
- Challenge progress uses `max(localValue, serverValue)` consistently.
- `ExerciseFilterService.normalizeEquipment()` is the single equipment-normalization source.
- `ChallengeTypeResolvable` is the canonical challenge-type resolution protocol.
- `ExerciseTypes.swift` owns the shared `MovementPattern` enum (30 cases).
- `ExerciseCardRow` is the single shared exercise card (used by `CustomWorkoutBuilderView` and `ExerciseLibraryView`).
- Replace mode (`.replace`, `.addToWorkout`) resets filter state on appear via `mode.isSingleSelect`.
- Exercise replacement shows green border glow + toast "Replaced with [Name]".
- `loadHistoricalDataForExercise` tasks tracked in `initTasks` for cancellation.

---

## See Also
- `DESIGN_AGENT.md` — visual tokens + card system
- `QUALITY_PERFORMANCE_AGENT.md` — performance invariants, widget isolation details, tab-transition budgets
- `DATA_BACKEND_AGENT.md` — DTOs, RPC contracts, repeat-exercise placeholder contract
- `.cursor/rules/codingrules.mdc` — cross-cutting MUST/NEVER rules for all agents
- `.cursor/rules/swiftui-rules.mdc` — Swift/SwiftUI-specific rules (auto-loads for `Fit33/**/*.swift`)
- `docs/history/PRODUCT_ENGINEER_AGENT.md` — dated decisions, feature integration deep-dives
