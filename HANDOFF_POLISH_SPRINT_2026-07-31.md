# HANDOFF PROMPT — Fit33 "Ship-Tomorrow" Polish Sprint (2026-07-31)

> Paste this file's contents as the opening prompt for a fresh agent, or point the
> agent at this file. It contains everything needed to continue: session state,
> constraints, and the full consolidated worklist from five specialist reviews.

---

## Who you are and what you're doing

You are a senior staff engineer finishing a product-quality overhaul of **Fit33**,
a SwiftUI iOS fitness app (Supabase backend, Core Data local store) at
`/Users/joe/Desktop/Fit33-audit`. The goal: **keep every feature and behavior
exactly the same, but fix everything below** so the app feels like a
ready-to-ship native iPhone app. This is behavior-preserving polish + bug fixing —
no new features, no refactors beyond what a fix requires.

## Session state you inherit (already done — do NOT redo)

- A full-stack production-readiness audit was completed and DEPLOYED on
  2026-07-30/31: migrations #203–#206 are live in prod, edge functions
  `send-push-notification` + `bug-intel-rpc-smoke` redeployed, CMS deployed via
  Vercel. See MASTER_TODO.md §PR status blocks (2026-07-26 and 2026-07-30).
- Local branch `cursor/production-readiness-audit-09e7` == `origin/main`
  (last commit `c381e58`). Working tree clean except an untracked
  `Fit33.xcodeproj/project.xcworkspace/` (harmless, CLI-generated).
- The build is GREEN at this commit. Verify any change with:
  `xcodebuild build -project Fit33.xcodeproj -scheme Fit33 -destination 'generic/platform=iOS Simulator' -derivedDataPath build/DerivedData`
  (iOS 26.5 + watchOS 26.5 simulator runtimes are installed; incremental builds ~1 min).
- Supabase CLI is at `~/bin/supabase` (project ref `ehooeghabzefgoqzugrc`); you
  should not need it — nothing below touches the backend.
- Five specialist review agents produced the findings below (product journeys,
  fitness/training flow, design system, performance, device compatibility).
  Findings were NOT yet implemented. That is your job.

## Hard constraints

1. Load `.cursor/rules/swiftui-rules.mdc` before editing Swift (AppLogger not
   print, no force unwraps, `.ds_*` tokens, `Task {}` not DispatchQueue delays,
   `@MainActor` discipline, fetchLimit on @FetchRequest).
2. **Verify each finding in code before fixing** — line numbers may have
   drifted; a few findings may be intentional (check the owning `*_AGENT.md`
   if in doubt, per ENGINEERING_TEAM.md's ownership matrix).
3. Behavior-preserving: same features, same flows. UX-affordance additions
   explicitly listed below (discard buttons, error toasts, confirmations) are
   in scope; anything else new is not.
4. Don't re-fix items already tracked in MASTER_TODO.md §PR unless listed below.
5. Rebuild and get a green build after each phase. Commit per phase with a
   descriptive message (repo convention: `PR-xx: ...` style). Do NOT push
   without the user's approval (push to main auto-deploys the CMS via Vercel).
6. After finishing: update MASTER_TODO.md (new dated status block), fix the
   navigation rule file honestly (see P1-J), add any new invariants to the
   right scoped rule file, and apply the MIRROR RULE for any `*_AGENT.md`
   edits (`codingrules.mdc` explains the mapping).

---

## PHASE 1 — P0 data-integrity bugs (fix first, in this order)

**A. Set completion bypasses unit conversion — kg/per-side users log corrupted weights.**
`Fit33/WorkoutSetViews.swift` ~424–493 (checkmark handler) vs. the correct path
in `applyWeight` ~648–658. `WorkoutSetData.weight` is canonically TOTAL LBS; the
checkmark writes the raw display-unit text (kg or per-side) straight in, and
echoes stored lbs back into `weightText` unconverted. Route the parsed text
through the same conversion `applyWeight` uses (per-side ×2, kg→lbs) before
assigning; format echoed text via the display-side inverse (same math as
`weightPlaceholder`); delete the redundant second write at ~488–493.

**B. "Replace Exercise" copies the old lift's completed weights onto the new exercise.**
`Fit33/WorkoutManager.swift` ~1506–1552 (`replaceExercise`). The comment says
"clear the weight/rep data" but lines ~1530–1538 copy completed reps/weights
into the new exercise's sets — poisoning history, ghosts, and PR detection
under the new exercise's id. Keep `preservedSetCount` rows but zero
weight/reps (match the shuffle path's semantics in
`ActiveWorkoutView+Actions.swift` ~449–461).

**C. Shuffle can pick an exercise already in the workout — wipes its logged sets, duplicates ForEach ids.**
`Fit33/ExerciseCard.swift` ~343–359 (exclusion set) + shuffle handler in
`ActiveWorkoutView+Actions.swift` ~449–464. Seed `excludeIds` with ALL exercise
ids currently in the workout (pass from ActiveWorkoutView which owns
`exercises`); belt-and-braces: no-op in the handler if `newExercise.id` already
exists in `exercises`.

**D. 4-hour auto-end silently destroys the workout; its alert has no observer.**
`Fit33/WorkoutManager.swift` ~857–868. On timeout it calls `cancelWorkout()`
(wipes persisted sets) and posts `"WorkoutAutoEnded"` which NOTHING observes
(grep confirms). Fix: salvage instead of cancel — persist completed sets via the
same save path finish uses (cap stored duration sanely), and add an observer in
`MainTabView`/`ContentView` presenting the explanatory alert.

**E. "Reopen" on the completion screen re-arms FINISH — double XP/league/HealthKit fanout (repeatable exploit).**
`Fit33/ActiveWorkoutView+Init.swift` ~419–425 (`handleCompletionDismiss`) resets
both re-entry guards so Reopen works; the full fanout lives in the view's
`finishWorkout()` (`ActiveWorkoutView+Actions.swift` ~206–247). Add a
session-scoped `didRunCompletionFanout` flag on `WorkoutManager` (not view
@State); second finish re-runs only `saveWorkoutData()` + the idempotent cloud
upsert, skipping XP/streak/league/quests/HealthKit/program-day.

**F. Indoor cardio: failed save permanently drops all XP/quest credit; failure state renders nothing.**
`Fit33/CardioActiveWorkoutView.swift` ~1059–1071 (catch enqueues retry but
fanout is gated on `workoutId != nil` at ~1020; status row at ~760–777 renders
nothing for the failure state). `CloudSyncRetryQueue.attemptCardioSync`
(`CloudSyncRetryQueue.swift` ~195–214) only re-saves, never completes the
fanout. Fix: (a) show "Saved offline — will sync automatically" in the
`!isSaving && !savedSuccessfully` state; (b) after a successful retry, call
`UserManager.completeCardioWorkout(..., savedViaRPC: true)` guarded by a
`fanoutCompleted` flag on the queue entry. Also align the OUTDOOR recap
(`CardioRecapView.swift` ~383–392), which currently runs fanout even on failure —
both flows should be "fanout after durable save."

## PHASE 2 — P0 performance (felt in every session)

**G. Phantom `currentTime` publishes 1 Hz app-wide; nothing reads it.**
`Fit33/WorkoutManager.swift` L45 + ~882–892. ~35 views observe WorkoutManager
(incl. ContentView/MainTabView/DashboardView) → whole-app invalidation every
second for 60–90 min. Stop writing `currentTime`; retime the timer to 15 s
(its only remaining job is the periodic save via `saveCounter`).

**H. RestTimer publishes at display refresh rate (60–120 Hz).**
`Fit33/RestTimerViews.swift` ~198–207. Publish only when the whole second
changes (`if Int(remaining) != Int(timeRemaining)`), and/or set
`displayLink.preferredFrameRateRange = CAFrameRateRange(minimum: 1, maximum: 4)`.
Each ExerciseCard body currently re-evaluates per frame during every rest.

**I. Per-second `elapsedTime` invalidates the entire active-workout layout; DateFormatter allocated per tick.**
`Fit33/ActiveWorkoutView+Init.swift` ~448–455; `Fit33/ActiveWorkoutView.swift`
~152–157 (`notesPlaceholder`). Extract the duration text into a tiny child view
driven by `TimelineView(.periodic(from: startTime, by: 1))`; delete the root
tick. Make the formatter `static let`; cache `notesPlaceholder`/
`liveWorkoutName` in @State refreshed on `.onChange(of: exercises.count)`.
Also add `timer?.invalidate()` (or `stopTimer()`) as the first line of
`startTimer()` (~427) — QP invariant 2.

**J. Run map rebuilds the whole route on every GPS fix + heading spam.**
`Fit33/RunningWorkoutView.swift` ~1071–1091 (`updateUIView` removes all
overlays/annotations and re-adds an O(n) polyline); `Fit33/RunningManager.swift`
~1084 publishes every ~1° heading change (no `headingFilter`), ~1006–1024
publishes the full growing `routeCoordinates` array per fix and grows
`gpsAccuracySamples` unbounded. Fix: append-only segment overlays keyed off a
stored count; move the current-position annotation by mutating `coordinate`;
`headingFilter = 5`; make the canonical route array non-published (publish a
`routeVersion: Int`); replace accuracy samples with running sum + count.

**K. Goal-achieved haptic fires EVERY SECOND for the rest of the cardio session.**
`Fit33/CardioActiveWorkoutView.swift` ~531–534. Add
`@State didFireGoalHaptic = false`; fire once; reset in `startWorkout()`.

**L. Cardio clock loses time when backgrounded (tick accumulation).**
`Fit33/CardioActiveWorkoutView.swift` ~458–462 (`elapsedTime += 1`). Anchor to a
start date + accumulated pause intervals, compute per tick, resync on
foreground (same pattern as RunningManager / `RestTimer.syncToWallClock()`).

## PHASE 3 — P1 functional/UX (verify each, then fix)

- **M. No discard path for strength workouts; FINISH fires instantly with 0 sets.**
  View-level `cancelWorkout()` (`ActiveWorkoutView+Actions.swift` ~371–379) has
  zero callers. Add "Discard Workout" (destructive confirmation) to
  `WorkoutSettingsPanel`; on FINISH with 0 completed sets show "Nothing logged
  yet — discard instead?" (`UserManager.completeWorkout` has no set-count guard).
- **N. Every start-workout entry point silently no-ops when a workout is active** and
  history paths leak orphan `Workout` rows created before the guard
  (`WorkoutManager.swift` ~925–930; call sites: `WorkoutHistoryDetailView.swift`
  ~927/~1777, `AutoWorkoutPreviewView.swift` ~502, `ReceivedWorkoutsView.swift`
  ~914, `SharedWorkoutView.swift` ~353, `FriendWorkoutPreviewView.swift` ~331).
  Present "Workout in progress — Resume / Discard & start new?"; create the Core
  Data row only after the guard passes.
- **O. Legacy program-day completion never records.** `ProgramScheduleFullView.swift`
  ~614–617 sets `currentProgramDayNumber` BEFORE `startWorkout`, which overwrites
  it with its nil default (`WorkoutManager.swift` ~978). Pass
  `programDay:`/`programDayFocus:` through the call like
  `CloudProgramScheduleView.swift` ~942 does; delete the pre-call assignments.
- **P. Meal logging silently swallows validation failures while the UI celebrates.**
  `MealService.addMealEntry` (`MealService.swift` ~62–65) log-only early returns;
  7 call sites treat it as infallible (FoodDetailsView ~1710, RecipeImportView
  ~966, MealPlanView ~1448, ImportedRecipeDetailView ~673, SmartMealPlannerView
  ~1039…). Return `Bool`, alert on failure instead of dismissing.
- **Q. Swap-tier state resets every shuffle (tier 2 unreachable).**
  `ExerciseCard.swift` L48/~341–393: `perExerciseSwapCount` + `shuffledExerciseIds`
  are @State on a view whose ForEach identity changes each swap. Hoist into
  ActiveWorkoutView/WorkoutManager keyed by slot index; use the same counter for
  the logged `swapIndex` (currently uses the global ad counter).
- **R. Next-exercise cleanup silently deletes planned set rows beyond 3.**
  `ActiveWorkoutView+Actions.swift` ~63–103: trim threshold is a hardcoded 3;
  use `max(3, previousExerciseSets[id]?.count ?? 0, defaultSetCount)`.
- **S. Program prescriptions (incl. deload) never reach the live screen.**
  `CloudProgramScheduleView.swift` ~920–945 drops per-exercise sets/reps +
  `programWeek`; `ProgramDayPreviewView.swift` ~332–343 passes week but not reps;
  `StrengthProfileRecommendationEngine.swift` ~249–263 never forwards
  `prescribedReps`. Thread slot prescription (sets → row count, reps → placeholder
  target, week) through `startWorkout` → `initializeSetsForExercise`.
- **T. "+5 lb ready to progress" cue unreachable for users WITH history.**
  `ActiveWorkoutView+Init.swift` ~84–110/~219–263: suggestions only generated
  when the cloud history fetch returns EMPTY. Run the progression analysis after
  cloud sets load too; render the sparkle row alongside previous-set placeholders.
- **U. Watch never advances past "Set 1 of N".** `handleSetCompletion`
  (`ActiveWorkoutView+Actions.swift` ~17–29) has no call sites. Invoke it (or
  `pushLiveWorkoutStateToWatch`) from the card's `onSetCompleted` path.
- **V. No-history default mismatch: ghost shows 135, checkmark logs 45.**
  `WorkoutSetViews.swift` ~442 vs ~642 — derive the completion default from the
  same source as `weightPlaceholder`, converted to total lbs.
- **W. Battle-cry sends fire-and-forget on two dashboard surfaces.**
  `ChallengePreviewWidget.swift` ~452–460 + `ActiveChallengeHeaderRow.swift`
  ~83–91 ignore `result.success` (detail view rolls back with error haptic —
  ~781–795). Check success; error haptic + brief toast on failure.
- **X. Multi-friend challenge retry duplicates invites.**
  `ChallengeFlowStartView.swift` ~2057–2072: track per-friend results; retry
  failures only; word the error accordingly.
- **Y. Dashboard quest service not observed.** `DashboardView` holds
  `let dailyQuestService` but has `.onChange(of: dailyQuestService.completedCount)`
  (~845) — works today only because of finding G's per-second churn. Make it
  `@ObservedObject` BEFORE/with fixing G, or the recommendation refresh breaks.
- **Z. Dashboard duplicates the app-level foreground social refresh ungated.**
  `DashboardView.swift` ~859–873: delete `refreshHomeScreenData()` from the
  dashboard foreground handler (Fit33App's gated fanout + pull-to-refresh cover it).
- **AA. Cardio GPS: no distance filter at Best accuracy for hours.**
  `CardioActiveWorkoutView.swift` ~673–677 (`CardioLocationManager`): set
  `distanceFilter = 10`, `activityType = .fitness` (mirror RunningManager
  ~500–504); consider `kCLLocationAccuracyNearestTenMeters` if no live map.
- **AB. Set-save JSON encode on main in the tap path.** `WorkoutManager.swift`
  ~560–600: snapshot state on main, encode + UserDefaults.set in
  `Task.detached(priority: .utility)` with ordering preserved.
- **AC. Device P1s:** cardio goal-ring timer overflows its 200pt ring after 60 min
  (`CardioActiveWorkoutView.swift` ~207–232 — add `.minimumScaleFactor(0.6)` +
  `.lineLimit(1)`, mirror `CardioRecapView.swift` ~135–139); active-run VStack
  overflows landscape (enabled in Info.plist) and SE portrait
  (`RunningWorkoutView.swift` ~82–168 — read `verticalSizeClass`, collapse hero
  grid / wrap middle in ScrollView).
- **AD. Cardio recap palette breaks lockstep mid-session.**
  `CardioRecapView.swift` ~309–316 returns walk=.mint/run=.green; canonical is
  walk=.teal/run=.blue (`OutdoorCardioActiveView.swift` ~568–571,
  `CardioLandingView.swift` ~45). Propagates into the share card. Mirror the
  canonical mapping.
- **AE. Ungated `.repeatForever` animations (motion-policy violations):**
  `PremiumUpgradeView.swift` ~950–956 (8s infinite glow rotation + 2s button
  pulse) and `CardioActiveWorkoutView.swift` ~471–473 (goal-ring pulse). Gate
  through the sanctioned reduce-motion/Low Power check (`MotionPolicy` /
  `AnimatedOrbBackground.shouldDisableMotion` — find the canonical symbol).

## PHASE 4 — P2/P3 polish batches (verify, batch by type)

**Dead code / correctness quickies:**
- Rest-timer transfer read-after-remove (always nil): capture before
  `removeValue` — `ActiveWorkoutView+Actions.swift` ~464–471.
- Progression comparison includes warmups on the current side only:
  add `setType != "Warmup"` filter at `ActiveWorkoutView+Persistence.swift` ~367
  (previous side at ~427 already filters).
- `logExerciseUsage(totalWeightKg:)` receives summed LBS
  (`ActiveWorkoutView+Persistence.swift` ~506–514): sum `weightKg`.
- `ExerciseDetailView.swift` ~520–544 hardcodes "lbs" for kg users; PR query
  ~686–694 includes warmups.
- GenderFilter normalized-key collisions make variant videos nondeterministic
  (`GenderFilterService.swift` ~269–272, ~380–386): don't overwrite existing
  normalized keys; keep equipment markers distinct.
- Cardio share card claims success on failed Photos write
  (`CardioShareCardSheet.swift` ~248–253): use the completion selector.
- Friend-request failures are haptic-only (`FriendsListView.swift` ~1284, ~1833):
  add the file's existing toast pattern.
- "Corrupted data" recovery wording + unconfirmed destructive clear
  (`WorkoutTabView.swift` ~48–79): soften copy, add confirmation.
- Indoor cardio: add "Discard" to the End alert; align finish CTA copy
  (strength "FINISH" unconfirmed / cardio "End" confirmed / recaps "Done").

**Navigation debt (P1-J for the rule file):**
- 14 multi-line legacy `isActive:`/`NavigationLink(destination:` links remain in:
  `ProgramExplorerView.swift` (90/600/606/1210), `FoodSearchView.swift` (92),
  `NutritionScannerView.swift` (84), `SmartWorkoutPreviewView.swift` (73),
  `ReceivedWorkoutsView.swift` (137), `ReceivedWorkoutPreviewWidget.swift` (492),
  `RecipeBrowserView.swift` (136), `HealthyRecipesCarousel.swift` (105/113),
  `DashboardModels.swift` (279), `ProgramLibraryView.swift` (480).
  Convert them (multi-line — grep with `-U`), THEN update
  `.cursor/rules/navigation-migration-phase3.mdc` honestly (it currently claims
  COMPLETE; correct it immediately if you don't finish the conversion).

**Design tokens (one token type per commit, per design-system rules):**
- Paywall consistency: identical "Start 7-Day Free Trial" CTA rendered
  differently in `PaywallFirstScreenView.swift` (~388–413, yellow/orange rect,
  no haptic) vs `PremiumUpgradeView.swift` (~802–840, blue/purple capsule +
  haptic); yearly badge yellow vs green; selection stroke yellow vs blue.
  Gold is the sanctioned paywall language (DESIGN_AGENT invariant 5) — align
  PremiumUpgradeView to it. Also: `PaywallFirstScreenView` has 24 inline
  `Font.system` calls (map: 28→ds_heading1, 17→ds_bodyLarge, 16→ds_bodyRegular,
  13→ds_labelMedium, 12/10→ds_caption, 11→ds_labelSmall, 20→ds_heading2);
  plan cards/free-version button need pressed states + a dimmed disabled CTA.
- Bare `.ultraThinMaterial` → adaptive wrapper batch: `CardioRecapView` (~149,
  187, 254, 270), `PremiumLockOverlay` (`PremiumUpgradeView.swift` ~992–1015 —
  also purple crown circle → gold), `DashboardView+Header.swift` ~126,
  `ActiveWorkoutView+Layout.swift` ~160.
- Sub-10pt text floor violations: 8–9pt in `DashboardView+Challenges.swift`
  (~822/937/1111/1184/1196), `DashboardView+Programs.swift` (~330/1511),
  `MealPlanView.swift` (~866–878), `ActiveWorkoutView+Layout.swift` ~636–645 →
  `ds_caption` (10pt) minimum.
- One-off grays → card tokens: `ProfileView.swift` ~1241–1254 (third card
  treatment) + ~2256, `NewOnboardingView+Verification.swift` (~58/93/208),
  `BattleCryComposer.swift` ~512; near-miss `cardGradientStops` forks in
  `NewOnboardingView.swift` ~806, `NewOnboardingView+Steps.swift` ~41/126,
  `FriendsListView.swift` ~1343.
- `CardioRecapView` button row: unify to `.ds_labelLarge`, one height,
  `CornerRadius.lg`, shared pressed state (~261–305); radii 18→`CornerRadius.lg`.

**Tap targets & device polish (one batch):**
- 44pt minimums: set checkmark (`WorkoutSetViews.swift` ~532–539 + header
  spacer `ExerciseCard.swift` ~686), active-workout header gear/info/star/FINISH
  (`ActiveWorkoutView+Layout.swift` ~546–617), shuffle 36→44
  (`ExerciseCard.swift` ~472–481), `BattleCryQuickOpenButton`
  (`BattleCryComposer.swift` ~241–280), weight/reps fields 38→44
  (`WorkoutSetViews.swift` ~326/336/398).
- Stale `.padding(.top, 60)` compensation: `CardioActiveWorkoutView.swift` ~180,
  `CardioCompletionView` ~796, `RunningWorkoutView.swift` ~117–121 (also grow the
  220pt scrim ~L102 or reduce pad); hero metrics need `minimumScaleFactor(0.7)`
  (~212–242).
- Paywall benefit tiles truncate on SE (`PremiumUpgradeView.swift` ~579–616):
  `.minimumScaleFactor(0.75)`, `.frame(minHeight: 110)`.
- iPad minimum viability: `.frame(maxWidth: 640)` centering on Settings/Profile/
  paywall/onboarding; `UIScreen.main.bounds` → geometry width in
  `ActiveWorkoutView+Layout.swift` ~680; onboarding magic `620` constant
  (`NewOnboardingView+Auth.swift` ~104) → capped spacer.
- Dashboard carousel fixed 160pt height + 6pt page dots
  (`DashboardView+Helpers.swift` ~502–560).
- Streak stat one-off `.black`-weight font (`DashboardView+Header.swift` ~397);
  cardio stat sizes → `ds_stat` family (`CardioActiveWorkoutView.swift`
  ~167/211/595); sibling program-card numbers 22 vs 20pt
  (`DashboardView+Programs.swift` ~62/277).
- Delete unused `RestTimerIndicator` (`RestTimerViews.swift` ~3–65).

## Verification & wrap-up

1. Full build green after each phase; final full build + fix any lints on files
   you touched (ReadLints).
2. Update `MASTER_TODO.md` with a "2026-07-31 polish sprint" status block
   (follow the existing status-block style); correct
   `navigation-migration-phase3.mdc`; add genuinely new invariants to the
   matching scoped rule file; MIRROR RULE for any `*_AGENT.md` changes.
3. Commit in logical phase-sized commits. Ask the user before pushing
   (push to main deploys the CMS — harmless for Swift-only commits, but get
   approval anyway).
4. Report: what was fixed per phase, anything you verified and rejected as
   already-correct/intentional (say why), and what remains.

## Known open items that are NOT your job (user/product decisions)

- PR-5 APNs key rotation (Apple portal), PR-11/12/13 monetization cutover
  decision, PR-30 prod RPC export, publishing `Website/` legal pages to
  fit33.app (currently a Squarespace "Coming Soon" page — App Review blocker),
  PR-6/19/24/25/27/31/36/39/45 residuals per MASTER_TODO.
