# Fit33 Codebase Audit - 2026-04-27

## Executive Summary

This audit reviewed the current workspace state after consulting the repo's agent docs: Product, Data, Supabase, Infra/Security, Quality/Performance, Fitness, Design, Design System, Device Compatibility, and Support. No implementation code was changed for this audit.

The most important result: the app currently does not build from the checked-out workspace. The simulator build fails in `Fit33/WelcomeBriefRow.swift` because `ReadinessDrillDownSheet` is not in the app target and `BriefCTA.focusQuest` is not handled in an exhaustive switch. The Xcode project also has broad duplicate Compile Sources entries, and recent Daily Brief migrations are not all represented in `supabase/MIGRATION_INDEX.md`.

Top priorities:

1. Restore a clean iOS build.
2. Clean Xcode project duplicate source references.
3. Register missing migrations and wire the migration-index guard into pre-commit.
4. Fix Daily Quest optimistic update drift for `isBriefInfluenced`.
5. Harden auth checks before quest RPC writes.
6. Audit older Supabase views that grant authenticated access without `security_invoker = on`.
7. Move admin CMS rate limits and action classification toward enforceable, shared helpers.

## Validation Performed

- Consulted root agent docs and scoped rules for Swift, Supabase, and admin CMS.
- Ran read-only repo scans across Swift, SQL, Edge Functions, admin CMS, workflows, scripts, and project files.
- Ran `python3 scripts/logic_audit_verify.py`: 24/24 passed.
- Ran `bash scripts/pre_commit_migration_check.sh`: exited 0, but only checks staged files.
- Ran `SRCROOT=... bash scripts/perf_lint.sh`: completed with warnings around `ExerciseLibraryService.shared` usage.
- Ran `xcodebuild -project Fit33.xcodeproj -scheme Fit33 -destination 'generic/platform=iOS Simulator' -skipPackagePluginValidation CODE_SIGNING_ALLOWED=NO build`: failed with Swift compile errors.

## Critical Findings

### 1. The iOS App Currently Fails to Build

Category: Build correctness, release blocker  
Affected files: `Fit33/WelcomeBriefRow.swift`, `Fit33/ReadinessDrillDownSheet.swift`, `Fit33.xcodeproj/project.pbxproj`

Evidence:

- `xcodebuild` failed with:
  - `WelcomeBriefRow.swift:79:13: error: cannot find 'ReadinessDrillDownSheet' in scope`
  - `WelcomeBriefRow.swift:229:9: error: switch must be exhaustive`
  - Missing enum case: `.focusQuest(questKey: let questKey)`
- `Fit33/ReadinessDrillDownSheet.swift` exists as an untracked file, but `rg "ReadinessDrillDownSheet" Fit33.xcodeproj/project.pbxproj` returned no project reference.
- `WelcomeBriefRow.accessibilityHint` handles many `BriefCTA` cases, but not `.focusQuest`.

Code reason:

`WelcomeBriefRow` references a new sheet view:

```swift
.sheet(isPresented: $showReadinessSheet) {
    ReadinessDrillDownSheet()
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
}
```

Because the file is not compiled into the `Fit33` target, Swift cannot resolve the symbol. Separately, adding `.focusQuest` to `BriefCTA` made the `switch` in `accessibilityHint` non-exhaustive.

Recommendation:

- Add `Fit33/ReadinessDrillDownSheet.swift` to the `Fit33` target exactly once.
- Add an accessibility hint case for `.focusQuest`, such as "Tap to focus the matching daily goal."
- Re-run the simulator build and unit tests.

Why this improves the app:

This is a hard release blocker. Fixing it restores the build, unblocks TestFlight/App Store deployment, and keeps the new Daily Brief CTA accessible to VoiceOver users.

### 2. The Xcode Project Has Duplicate Compile Sources Entries

Category: Build system, process reliability  
Affected file: `Fit33.xcodeproj/project.pbxproj`

Evidence:

`xcodebuild` emitted duplicate Compile Sources warnings for many files, including:

- `DailyBriefEngine.swift`
- `DailyBriefTemplates.swift`
- `DailyBriefStore.swift`
- `WelcomeBriefRow.swift`
- `V2Analyzer.swift`
- `DailyQuestService.swift`
- `ActiveChallengeWidgetBridge.swift`
- `PhoneToWatchSyncBridge.swift`
- `OnboardingTestHelper.swift`

The project file also shows duplicated file references for new Daily Brief files and `OnboardingTestHelper.swift`.

Code reason:

The project has multiple `PBXFileReference` / `PBXBuildFile` entries pointing to the same path. Xcode skips duplicate build files, but the warnings make real build warnings harder to see and increase merge conflict risk.

Recommendation:

- Normalize `Fit33.xcodeproj/project.pbxproj` so each source file appears once per intended target.
- Add a small project-file audit script or CI check that flags duplicate Compile Sources paths.
- Consider Xcode synchronized groups only if the project can consistently use them without duplicate manual references.

Why this improves the app:

A clean project file reduces false warnings, avoids accidental target membership drift, and makes CI failures easier to interpret.

### 3. `PhoneToWatchLiveWorkoutBridge 2.swift` Is a Duplicate Source File

Category: Project hygiene, Watch reliability  
Affected files: `Fit33/PhoneToWatchLiveWorkoutBridge.swift`, `Fit33/PhoneToWatchLiveWorkoutBridge 2.swift`, `Fit33.xcodeproj/project.pbxproj`

Evidence:

- `Fit33/PhoneToWatchLiveWorkoutBridge 2.swift` exists.
- Its contents match `PhoneToWatchLiveWorkoutBridge.swift` at the top of the file.
- The project file includes `PhoneToWatchLiveWorkoutBridge 2.swift in Sources`.

Code reason:

This looks like a Finder/Xcode copy artifact. Even if Swift currently avoids duplicate symbol errors due to target membership behavior or file-system group behavior, it creates ambiguity about which file is canonical.

Recommendation:

- Delete or remove `PhoneToWatchLiveWorkoutBridge 2.swift` from the target after confirming no unique edits exist.
- Keep only `PhoneToWatchLiveWorkoutBridge.swift`.

Why this improves the app:

The watch live-workout bridge is a state synchronization surface. Removing duplicate files prevents stale edits, merge confusion, and accidental divergence in the phone-to-watch wire contract.

## High Severity Findings

### 4. Recent Migrations Are Missing From `MIGRATION_INDEX.md`

Category: Data deploy process, server/client contract  
Affected files: `supabase/20260703_get_daily_quests_brief_signals.sql`, `supabase/20260704_daily_brief_quest_completion_link.sql`, `supabase/MIGRATION_INDEX.md`

Evidence:

`supabase/` contains five recent files:

- `20260701_daily_brief_telemetry.sql`
- `20260702_quest_category_user_toggles.sql`
- `20260703_get_daily_quests_brief_signals.sql`
- `20260704_daily_brief_quest_completion_link.sql`
- `20260704_dedupe_exercise_performance_history.sql`

`MIGRATION_INDEX.md` currently lists `20260701`, `20260702`, and `20260704_dedupe_exercise_performance_history.sql`, but not `20260703_get_daily_quests_brief_signals.sql` or `20260704_daily_brief_quest_completion_link.sql`.

Code reason:

The iOS app now decodes `is_brief_influenced` and sends brief-signal params to `get_daily_quests`. The Daily Brief telemetry code also calls `append_brief_completed_quest`, which is defined in `20260704_daily_brief_quest_completion_link.sql`. If those migrations are not deployed in order, the client and server contract splits.

Recommendation:

- Add both missing migrations to `MIGRATION_INDEX.md` with explicit order and dependencies.
- Ensure run order places `20260703_get_daily_quests_brief_signals.sql` before any client build relying on `is_brief_influenced`.
- Ensure `20260704_daily_brief_quest_completion_link.sql` is deployed before any build that calls `append_brief_completed_quest`.

Why this improves the app:

It prevents production users from seeing stale quest behavior, missing "from your brief" provenance, or telemetry RPC failures after the Daily Brief code ships.

### 5. The Migration Index Guard Script Is Not Wired Into Pre-Commit

Category: Process bug, data deploy reliability  
Affected files: `.githooks/pre-commit`, `scripts/pre_commit_migration_check.sh`, `scripts/README.md`

Evidence:

`scripts/pre_commit_migration_check.sh` says it fails commits when staged `supabase/*.sql` files are missing from `MIGRATION_INDEX.md`. `.githooks/pre-commit` currently only runs `classifier_lint.py` for staged Swift files and exits without calling the migration check.

Code reason:

The intended guard exists, but it is not executed by the configured hook. That makes index drift dependent on manual review.

Recommendation:

- Call `bash scripts/pre_commit_migration_check.sh` from `.githooks/pre-commit`.
- Add a CI job that runs a non-staged variant, comparing recent SQL files against `MIGRATION_INDEX.md`.
- Avoid relying only on local hooks, because contributors may not have `core.hooksPath` enabled.

Why this improves the app:

It catches deploy drift before merge, reducing the chance that client code ships against a migration that never reaches production.

### 6. `DailyQuestService.reportProgress` Drops `isBriefInfluenced`

Category: Product correctness, Daily Brief integration  
Affected file: `Fit33/DailyQuestService.swift`

Evidence:

`DailyQuest` now includes:

```swift
let isBriefInfluenced: Bool?
```

But the optimistic local rewrite in `reportProgress` recreates `DailyQuest` without passing `isBriefInfluenced`, so it falls back to `nil`.

Code reason:

When quest progress updates, this block copies most fields from `old` into a new `DailyQuest`, but omits the new field. Any quest that had `is_brief_influenced = true` can lose its UI provenance after progress changes locally.

Recommendation:

- Preserve `isBriefInfluenced: old.isBriefInfluenced` in the optimistic update initializer.
- Add a unit test that starts with an influenced quest, calls the local update path, and verifies the flag remains true.

Why this improves the app:

The Daily Brief and Daily Goals surfaces stay visually aligned. Users keep the "from your brief" context even as progress ticks, which reinforces the app's coaching logic instead of making it appear inconsistent.

### 7. Quest RPC Writes Use `currentUser` Without `isAuthenticated`

Category: Auth race, backend noise, reliability  
Affected file: `Fit33/DailyQuestService.swift`

Evidence:

`reportProgress` starts with:

```swift
guard let userId = SupabaseManager.shared.currentUser?.id else { return }
```

Then it calls:

```swift
.rpc("update_quest_progress", params: [
    "p_user_id": userId.uuidString,
    ...
])
```

Other quest RPC paths also guard only on `currentUser?.id != nil`.

Code reason:

The Data agent invariant says every Supabase write/RPC must check `SupabaseManager.shared.isAuthenticated` first. A persisted user object can exist while the Supabase session is expired or not yet recovered. In that case `auth.uid()` is null server-side and the app generates avoidable "not authenticated" errors.

Recommendation:

- Change quest write/RPC entry points to guard `SupabaseManager.shared.isAuthenticated` before reading `currentUser`.
- Prefer RPCs that derive the acting user from `auth.uid()` instead of accepting `p_user_id`; where legacy params remain, keep the server-side IDOR guard.
- Add a regression test or classifier-lint rule for `DailyQuestService` RPC calls.

Why this improves the app:

It reduces noisy backend errors, avoids background retry churn, and prevents quest progress from silently failing during startup auth races.

### 8. Older Public Views Grant Authenticated Access Without Explicit `security_invoker`

Category: Supabase security, RLS correctness  
Affected files include: `supabase/20260320_smart_insights_views.sql`, `supabase/challenge_type_migration.sql`, `supabase/global_food_popularity.sql`, `supabase/20260320_consolidate_food_history.sql`

Evidence:

`20260320_smart_insights_views.sql` creates views such as `v_social_retention_correlation` and grants SELECT to authenticated users, but does not use `WITH (security_invoker = on)`.

Example pattern:

```sql
CREATE OR REPLACE VIEW v_social_retention_correlation AS
SELECT up.id AS user_id, up.name, ...
FROM user_profiles up;

GRANT SELECT ON v_social_retention_correlation TO authenticated;
```

Code reason:

The Supabase agent requires public views to use `security_invoker = on`; otherwise views may bypass expected RLS behavior depending on ownership and grants. Some views also aggregate or expose cross-user data.

Recommendation:

- Run a catalog-level view audit in Supabase, not just grep.
- Recreate app-queryable views with `WITH (security_invoker = on)` and explicit `auth.uid()` filters where user-specific.
- Move admin/analytics cross-user views to a restricted schema or service-role-only access.

Why this improves the app:

It reduces the chance of cross-user data exposure and aligns legacy SQL with current Supabase security invariants.

### 9. Client-Trusted Pro Flags Are Still a Monetization Boundary

Category: Entitlement integrity, revenue protection  
Affected files: `supabase/20260607_pro_quest_monetization.sql`, `supabase/20260702_quest_category_user_toggles.sql`, `Fit33/DailyQuestService.swift`

Evidence:

Pro RPCs accept `p_is_pro BOOLEAN DEFAULT FALSE` and branch on that value. Agent docs already note this matches the older `p_is_subscriber` pattern and that canonical server-side premium checks are future work.

Code reason:

Client-provided entitlement flags are not authoritative. A modified client can call Pro RPCs with `p_is_pro = true` unless the server validates against a trusted subscription table.

Recommendation:

- Add a server-side `is_subscriber()` / `is_pro_user()` helper based on a trusted entitlement table.
- Remove `p_is_pro` from user-callable RPCs or ignore it except for logging.
- Keep client-side gating for UX only, not authorization.

Why this improves the app:

It protects paid features from trivial bypass and makes monetization behavior auditable server-side.

### 10. Admin CMS API Authorization Is Per-Route and Duplicated

Category: Admin security, maintainability  
Affected files: `admin-cms/src/middleware.ts`, `admin-cms/src/lib/verify-admin.ts`, `admin-cms/src/app/api/admin/route.ts`, `admin-cms/src/app/api/ai-chat/route.ts`

Evidence:

`middleware.ts` passes all `/api/*` requests through. That means every API route must enforce admin auth itself. A shared `verifyAdmin` helper exists, but both `api/admin/route.ts` and `api/ai-chat/route.ts` define their own local `verifyAdmin` functions.

Code reason:

Duplicated auth checks drift over time. A future API route can accidentally skip auth because middleware does not block `/api/*`.

Recommendation:

- Use the shared `verifyAdmin` helper in every admin API route.
- Add an audit test that enumerates `admin-cms/src/app/api/**/route.ts` and asserts each protected route imports the shared helper or is explicitly public.
- Consider middleware-level API protection for all non-auth routes.

Why this improves the app:

It reduces the chance of exposing privileged admin actions and makes auth policy reviewable in one place.

## Medium Severity Findings

### 11. Admin CMS Rate Limits Are In-Memory

Category: Abuse prevention, production reliability  
Affected files: `admin-cms/src/app/api/auth/login/route.ts`, `admin-cms/src/app/api/admin/route.ts`

Evidence:

Login and admin action limits are backed by process-local `Map` objects and cleaned by `setInterval`.

Code reason:

In a serverless or multi-instance deployment, in-memory rate limits are per instance and reset on cold start. That weakens brute-force protection and admin action throttling.

Recommendation:

- Move login and admin action rate limits to a DB-backed or Redis-backed store.
- Keep in-memory limits only as a local fallback.

Why this improves the app:

It gives consistent abuse protection across Vercel instances and preserves auditability for sensitive admin actions.

### 12. Admin CMS CI Builds but Does Not Run Lint

Category: CI quality gate  
Affected files: `.github/workflows/admin-cms-ci.yml`, `admin-cms/package.json`

Evidence:

`admin-cms/package.json` defines `"lint": "next lint"`, but `admin-cms-ci.yml` runs only:

```yaml
- run: npm ci
- run: npm run build
```

Code reason:

Type/build checks do not catch all security and framework lint issues. The CMS contains privileged API routes, CSP, cookie handling, and service-role calls, so static linting should be a merge gate.

Recommendation:

- Add `npm run lint` to `admin-cms-ci.yml`.
- If `next lint` is deprecated for the current Next version, replace it with the supported ESLint command and config.

Why this improves the app:

It catches broken hooks, unsafe patterns, and style regressions before admin code reaches production.

### 13. Admin Action Classification Is Manual and Easy to Miss

Category: Compliance, audit logging  
Affected file: `admin-cms/src/app/api/admin/route.ts`

Evidence:

The file notes:

```ts
// Missing actions get classified as `read` and silently skip the audit log
```

The same file contains a very large `switch (action)` with many cases.

Code reason:

Mutation classification lives in separate `WRITE_ACTIONS` / `BULK_ACTIONS` sets. Adding a new mutating case without updating those sets silently weakens rate limiting and audit logs.

Recommendation:

- Replace manual sets with a typed action registry where each action declares its tier and handler together.
- Add a test that every switch case is registered exactly once.

Why this improves the app:

Admin forensics becomes reliable and future CMS changes are less likely to bypass audit logging.

### 14. Widget Reload Budget Has a Direct Bypass

Category: Widget performance, battery, freshness reliability  
Affected file: `Fit33/HealthKitManager.swift`

Evidence:

`HealthKitManager.resetDailyCountersIfNeeded()` calls:

```swift
WidgetCenter.shared.reloadAllTimelines()
```

Agent rules require widget reloads to go through bridge-level hash and throttle gates. `ActiveChallengeWidgetBridge` and `DailyGoalsWidgetBridge` implement those gates, but this HealthKit path bypasses them.

Code reason:

Direct `reloadAllTimelines()` calls spend WidgetKit reload budget without payload hash dedupe or coalescing.

Recommendation:

- Route this reset through a bridge method that performs the same hash/throttle policy, or add a dedicated midnight-reset bridge API.
- Keep truly exceptional direct reloads documented and rare.

Why this improves the app:

It preserves WidgetKit's limited reload budget and reduces stale widget symptoms later in the day.

### 15. Timer and DisplayLink Surfaces Need a Lifecycle Pass

Category: Battery, memory, background behavior  
Affected files include: `Fit33/PerformanceMonitoringSystem.swift`, `Fit33/PerformanceOptimizations.swift`, `Fit33/BluetoothFitnessManager.swift`, `Fit33/AdvancedSessionLogger.swift`, `Fit33/RestTimerViews.swift`, `Fit33/RunningManager.swift`

Evidence:

Repo-wide scans found many `Timer.scheduledTimer`, `CADisplayLink`, and polling surfaces. Some are intentional and documented; others should be manually verified against the Quality agent lifecycle rules.

Code reason:

Service-lifetime timers must invalidate on background and restart on active. View-local timers must invalidate on disappear. Release telemetry timers must be DEBUG-gated or scenePhase paused.

Recommendation:

- Audit every repeating timer/display link for owner, invalidation point, scenePhase behavior, and DEBUG/release intent.
- Add a lightweight test or lint inventory so new timers cannot be introduced without lifecycle comments.

Why this improves the app:

It reduces background CPU wakeups, battery drain, and memory leaks during long workouts or app suspend/resume cycles.

### 16. `perf_lint.sh` Still Reports Context-Safety Warnings

Category: Performance, Core Data thread safety  
Affected files include: `Fit33/UserManager.swift`, `Fit33/TabPreloadingSystem.swift`, `Fit33/AppPerformanceSystem.swift`, `Fit33/SmartExercisePairingEngine.swift`, `Fit33/Fit33App.swift`, `Fit33/SupabaseManager.swift`

Evidence:

`perf_lint.sh` completed with warnings like:

```text
ExerciseLibraryService.shared returns viewContext objects - verify not inside bgContext.perform
```

Code reason:

The warning pattern is conservative, but the underlying invariant is important: viewContext `Exercise` objects cannot be safely used inside background Core Data contexts.

Recommendation:

- Review each warning and either refactor unsafe call sites or annotate safe false positives in the lint script.
- Prioritize `SmartExercisePairingEngine` and startup paths because they handle large exercise datasets.

Why this improves the app:

It reduces the risk of cross-context Core Data crashes and main-thread stalls during exercise search, pairing, and startup prewarm.

### 17. Design Token Debt Remains Broad

Category: UI consistency, accessibility  
Affected files: many `Fit33/*.swift`

Evidence:

Scans still show many `.font(.system(size:))` usages, hardcoded frames, and remaining design-token drift. The Design System agent's own snapshot also tracks hundreds of remaining typography violations.

Code reason:

Hardcoded fonts and sizes bypass Dynamic Type and design tokens. Fixed frames can clip on iPhone SE and under larger accessibility text sizes.

Recommendation:

- Continue the Design System migration file-by-file, one token type per batch.
- Prioritize user-facing high-traffic screens: dashboard, workout, quest, profile, challenge, and meal flows.
- Add CI metrics for new hardcoded font/spacing/radius introductions.

Why this improves the app:

It improves visual consistency, reduces clipping, and makes the app more resilient across light/dark mode and Dynamic Type.

### 18. Accessibility Coverage Is Still Incomplete

Category: Accessibility, App Store quality  
Affected files: broad SwiftUI surface

Evidence:

Agent docs track accessibility labels as a known open issue. Current scans show only targeted accessibility work in newer surfaces; older custom buttons and cards still need a systematic pass.

Code reason:

SwiftUI custom cards and icon-only buttons often do not infer useful labels/hints. Daily Brief has good accessibility intent, but the missing `.focusQuest` hint shows how enum growth can break coverage.

Recommendation:

- Audit interactive controls screen-by-screen.
- Add tests for route/CTA enums that require accessibility strings.
- Add a VoiceOver checklist to feature PRs.

Why this improves the app:

It improves usability for VoiceOver users and reduces support friction on complex flows like quests, challenges, and active workouts.

## Low Severity / Process Findings

### 19. `MIGRATION_INDEX.md` Ordering Is Not Monotonic

Category: Documentation clarity  
Affected file: `supabase/MIGRATION_INDEX.md`

Evidence:

The recent rows show `20260702`, then `20260704_dedupe`, then `20260701`. This is probably a merge artifact.

Code reason:

Non-monotonic ordering makes deployment order harder to inspect, especially when multiple files share `20260704`.

Recommendation:

- Reorder recent rows by intended run order.
- Add a run-order note for multiple migrations on the same date.

Why this improves the app:

It reduces operator error when deploying SQL manually or reviewing a release train.

### 20. `scripts/pre_commit_migration_check.sh` Uses `grep`

Category: Tooling consistency  
Affected file: `scripts/pre_commit_migration_check.sh`

Evidence:

The script uses shell `grep` internally. That is fine for a shell script, but it means agent-side audits should not assume the script follows Cursor tool preferences.

Recommendation:

- No functional change required. If the script is modified later, keep it POSIX/simple and test it in CI.

Why this improves the app:

Keeping the distinction clear avoids over-optimizing stable shell scripts while still following agent tool rules during interactive work.

## Coverage and Test Gaps

### iOS

Existing coverage is strongest around logic audit checks, DTO decoding, streak logic, notification allowlists, design system basics, screen map coverage, and Daily Quest/Daily Brief unit-style tests.

Gaps:

- No clear end-to-end test for Daily Brief -> Daily Quest -> completion telemetry.
- Watch and widget surfaces appear under-tested compared with their complexity.
- Background sync, silent push, HealthKit, and realtime flows are mostly not covered by automated integration tests.
- The Xcode build failed before unit tests could run in this audit.

Recommendation:

- Add tests around `DailyQuestService.reportProgress` preserving every `DailyQuest` field.
- Add a project-file duplicate source check.
- Add a widget/watch parity test for `ProgressFreshness` across all copies.
- Add an integration-style test for Daily Brief conversion telemetry using a mocked Supabase client or a local protocol seam.

### Supabase

Strengths:

- Most recent migrations are well-commented, idempotent, and wrapped in `BEGIN` / `COMMIT`.
- Recent RPCs show explicit IDOR guards.
- Edge functions mostly use shared CORS helpers.

Gaps:

- Missing index entries for recent migrations.
- Legacy views and broad `USING (true)` policies need catalog-level review.
- Client-trusted Pro flags remain until a server-side entitlement helper exists.
- No obvious `supabase db lint` or schema static analysis in CI.

Recommendation:

- Add a Supabase lint/advisor CI job for migrations.
- Add catalog queries to quarterly health checks for views, RLS policies, and SECURITY DEFINER functions.

### Admin CMS

Strengths:

- CSP is centralized in `middleware.ts` and no static CSP exists in `next.config.ts`.
- Admin cookies are httpOnly/Secure/SameSite according to the reviewed auth files.
- MFA enrollment appears enforced in login flow.

Gaps:

- API auth is per-route and duplicated.
- CI does not run lint.
- Rate limits are in-memory.
- `admin/route.ts` is very large and action classification is manual.

Recommendation:

- Centralize route auth.
- Add lint and a route auth coverage test.
- Move rate limits to shared durable storage.
- Split admin actions into a typed registry.

## Suggested Action Roadmap

### Immediate

1. Add `ReadinessDrillDownSheet.swift` to the `Fit33` target and handle `.focusQuest` in `WelcomeBriefRow`.
2. Clean duplicate Xcode source references, especially the new Daily Brief files and `PhoneToWatchLiveWorkoutBridge 2.swift`.
3. Add missing migration index entries for `20260703_get_daily_quests_brief_signals.sql` and `20260704_daily_brief_quest_completion_link.sql`.
4. Re-run `xcodebuild build` and `xcodebuild test`.

### This Sprint

1. Preserve `isBriefInfluenced` in `DailyQuestService.reportProgress`.
2. Add `isAuthenticated` guards before all Daily Quest RPC/write calls.
3. Wire `scripts/pre_commit_migration_check.sh` into `.githooks/pre-commit` and add CI coverage.
4. Add `npm run lint` to admin CMS CI.
5. Audit legacy Supabase views and recreate app-queryable views with `security_invoker = on`.

### Next Sprint

1. Replace client-trusted `p_is_pro` gates with server-side entitlement reads.
2. Create an admin action registry that combines handler, tier, validation, and audit policy.
3. Convert direct widget reload calls to bridge-gated APIs.
4. Triage `perf_lint.sh` warnings and annotate/resolve false positives.
5. Start a focused accessibility pass on Dashboard, Daily Goals, Active Workout, Challenge Detail, and Meals.

### Longer-Term

1. Add Supabase schema lint/advisor checks to CI.
2. Add widget and watch test targets or parity checks for duplicated code.
3. Continue design-token migration with CI checks that prevent new hardcoded token debt.
4. Break down large files like `SupabaseManager.swift`, `WorkoutProgressView.swift`, and `admin-cms/src/app/api/admin/route.ts` only when touching related behavior, to avoid risky broad refactors.

## Final Notes

This audit intentionally separates verified findings from implementation. The highest-confidence issues are the current build failure, Xcode duplicate source entries, missing migration index entries, `DailyQuestService` field loss, and process gaps around migration/admin CI gates. Those should be addressed before broader refactors or polish work.
