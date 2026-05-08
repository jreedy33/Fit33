# Phase 2.2 Foreground-Gate Audit (May 2026)

**Audit conducted by:** explore subagent (parent: Snappiness Overhaul)
**Audit date:** 2026-05-07
**Purpose:** classify every post-foreground fanout RPC into safe-to-skip vs. must-refresh, so Phase 2.2 can extend the 30s foreground-resync gate to the safe subset without regressing user-visible state freshness.

## Decision

**Phase 2.2 is a NO-OP for this build.** The audit revealed today's `Fit33App.shouldRunForegroundResync` gate (`Fit33/Fit33App.swift:213`) is already correctly placed: every RPC in the post-foreground fanout is already gated by the 30s debounce. Promoting the 3 Category-D items in the 10-pack to "always-run" would *increase* brief-blip work to gain correctness, which conflicts with the user's hard requirement that "everything is exactly the same just apple-level faster" for this build. The implementation is therefore deferred to a follow-up sprint where the Category-D promotion can be paired with a behavior-change announcement and parity tests proving no double-fetch regression.

The Category-A items in the 10-pack stay correctly gated; Phase 2.1's realtime grace-disconnect ensures their data freshness via the live WebSocket across brief blips, which is *strictly more reliable* than today (today's disconnect-on-background drops events that arrive during the 2-30s blip window).

## Scope

- **Primary scope:** the `async let s1…s10` parallel fanout inside `Fit33App`'s `.onChange(of: scenePhase)` → `.active` coordinated `Task`, guarded by `runFullResync = shouldRunForegroundResync(oldPhase:)` at [Fit33/Fit33App.swift:1082](../../Fit33/Fit33App.swift).
- **Secondary scope:** the additional gated work in the same `if runFullResync { … }` block (`HealthDataService.syncAllHealthData`, `CommunityChallengeService.refreshAll`, `PrivateChallengeService.refreshAll`, conditional `syncAllTrackingTo*`).
- **Out of scope:** `OlympianPathService.loadCurrentSeason` (no scenePhase call site — fired by view `.task` modifiers only; covered separately by Phase 1.2's TTL), `AchievementService.fetchAchievements` (view-driven only), `UserManager.syncCurrentUser` (auth-flow-driven only).
- **Realtime caveat:** Category-A coverage assumes `PerfFlags.phase2RealtimeGate = ON`. With the flag OFF, `RealtimeService.disconnect()` calls `actuallyDisconnectAll()` immediately and Category-A → Category-D promotion is the safer interpretation.

## Summary

- Total RPCs in post-foreground 10-RPC fanout: **10**
- Category A (realtime-covered): **7**
- Category B (user-action-refreshed): **0** (none of the ten are reliably re-fired by next-tab nav alone)
- Category C (30s-staleness-acceptable): **0** (within the ten — all feed dashboard/social surfaces)
- Category D (must refresh on every foreground): **3** (within the ten)

**Secondary gated block (not part of N=10):** `HealthDataService.syncAllHealthData` + `CommunityChallengeService.refreshAll` + `PrivateChallengeService.refreshAll` (+ conditional `syncAllTrackingTo*`) are all Category D by default.

## Phase 2.2 implementation guidance (deferred)

If Phase 2.2 is implemented in a future sprint:

### Move OUT of `runFullResync` (always-runs) — Category D inside the 10-pack

- `ChallengeService.shared.fetchActiveGroupChallenges()` — sync-triage notes: realtime/`daily_progress` chains can miss freshness for group + widget surfaces when HealthKit-driven pushes are absent.
- `FriendService.shared.checkForNewWorkouts()` — `shared_workouts-*` realtime handler refreshes `fetchReceivedWorkouts()` not this method; skipping loses new-id diff + local notification + haptic side effects.
- `ChallengeService.shared.fetchActiveChallenges()` — explicit Layer A.2 rationale in-code: home-screen + dashboard widgets cannot rely solely on opponent progress realtime when events are missed during socket-death windows.

### Keep IN `runFullResync` (gated by 30s debounce) — Category A inside the 10-pack

- `FriendService.shared.fetchPendingRequests()` — A — `friendships-{userId}` channel.
- `ChallengeService.shared.fetchPendingInvites()` — A — `challenges-{userId}` channel.
- `ChallengeService.shared.fetchPendingSentChallenges()` — A — same channel + opponent-accept handlers.
- `PrivateChallengeService.shared.fetchPendingInvites()` — A — `private-challenges` service-local channel.
- `PrivateChallengeService.shared.fetchMyChallenges()` — A — `private_members-*` + `private_challenge_progress-*`.
- `CommunityChallengeService.shared.fetchMyChallenges()` — A — `community_challenge_progress-*` + `community_challenge_participants-*`.
- `ActivityFeedService.shared.fetchFeed()` — A — `friend_activity_feed-{userId}` INSERT/UPDATE.

### Stay always-runs (already outside `runFullResync` today)

- `RealtimeService.shared.forceReconnectIfStale()` — D — Phase 2.1 grace-cancel + reconnect.
- `RealtimeService.shared.setupDefaultCallbacks()` — D — idempotent wiring.
- `SupabaseManager.shared.recoverSessionIfNeeded()` — D — auth recovery.
- `SupabaseManager.shared.recordLastActive()` — D — presence UPSERT.
- `RealtimeService.shared.ackBattleCryReceiptsIfRecipient()` — D — recipient-side reaction receipts.
- `PushNotificationService.shared.recheckAndRegister()` + token health — D — push correctness.
- `DailyResetService.shared.checkAndPerformDailyResetIfNeeded()` — D — midnight rollover.
- `UserManager.shared.syncProfileToCloud()` — C — usually invisible within 30s.
- `NotificationManager.shared.updateBadgeCount()` — C — explicit "lag tolerated" comment.
- `CloudSyncRetryQueue.shared.drainIfDue()` — D — offline write integrity.
- `ChallengeOpponentWakeService.shared.requestWake(.foreground)` — D — cross-device freshness poke.

## Detailed call-site table

### A) The 10-way parallel fanout + gated tail

| # | RPC / fetch | Source line | Category | Realtime channel | Notes |
|---|---|---|---|---|---|
| s1 | `FriendService.fetchPendingRequests` | `Fit33App.swift:~1292` | A | `friendships-{userId}` | Realtime insert/update calls this RPC directly. |
| s2 | `ChallengeService.fetchPendingInvites` | `Fit33App.swift:~1293` | A | `challenges-{userId}` | Notification handlers + dashboard `.refreshable` cover gaps. |
| s3 | `ChallengeService.fetchPendingSentChallenges` | `Fit33App.swift:~1294` | A | `challenges-{userId}` | Opponent-accept flows refresh via realtime. |
| s4 | `ChallengeService.fetchActiveGroupChallenges` | `Fit33App.swift:~1295` | **D** | Partial (`group_challenges`, `daily_progress-*`) | Documented miss paths for group + widget surfaces when HK chains lag. |
| s5 | `PrivateChallengeService.fetchPendingInvites` | `Fit33App.swift:~1296` | A | `private-challenges` (service-local) | Depends on `subscribeToRealtimeUpdates()` lifecycle. |
| s6 | `PrivateChallengeService.fetchMyChallenges` | `Fit33App.swift:~1297` | A | `private_members-*`, `private_challenge_progress-*` | Periodic timer is safety net. |
| s7 | `CommunityChallengeService.fetchMyChallenges` | `Fit33App.swift:~1298` | A | `community_challenge_progress-*`, `community_challenge_participants-*` | Optimistic patches reduce reliance on full fetch. |
| s8 | `ActivityFeedService.fetchFeed` | `Fit33App.swift:~1299` | A | `friend_activity_feed-{userId}` | INSERT triggers `fetchFeed`; UPDATE handles moderation hide. |
| s9 | `FriendService.checkForNewWorkouts` | `Fit33App.swift:~1300` | **D** | Partial (`shared_workouts-*` calls `fetchReceivedWorkouts`) | Skipping loses new-id detection + local notifications. |
| s10 | `ChallengeService.fetchActiveChallenges` | `Fit33App.swift:~1301` | **D** | Partial (`daily_progress-*`, participant updates) | Explicit Layer A.2 widget gap-fill rationale. |
| — | `HealthDataService.syncAllHealthData` | `Fit33App.swift:~1311` | **D** | n/a (HK / vendor APIs) | Drives readiness/dashboard/challenge aggregation. |
| — | `CommunityChallengeService.refreshAll` | `Fit33App.swift:~1314` | **D** | Partial (progress/events) | Full reconciliation beyond realtime deltas. |
| — | `PrivateChallengeService.refreshAll` | `Fit33App.swift:~1315` | **D** | Partial | Same as community. |
| — | `CommunityChallengeService.syncAllTrackingToCommunityChallenges` | `Fit33App.swift:~1320–1322` | **D** | n/a | Fires only on initial empty→nonempty transition. |
| — | `PrivateChallengeService.syncAllTrackingToPrivateChallenges` | `Fit33App.swift:~1323–1325` | **D** | n/a | Same. |

### B) Always-unconditional pieces in the coordinated foreground `Task`

| Call | Source line | Category | Notes |
|---|---|---|---|
| `SupabaseManager.recoverSessionIfNeeded` | `Fit33App.swift:~1179–1182` | D | Auth recovery when session flags disagree. |
| `SupabaseManager.recordLastActive` | `Fit33App.swift:~1185` | D | Presence UPSERT; correctness-sensitive. |
| `RealtimeService.ackBattleCryReceiptsIfRecipient` | `Fit33App.swift:~1186` | D | Clears recipient-side reaction receipts. |
| `RealtimeService.setupDefaultCallbacks` | `Fit33App.swift:~1208` | D | Idempotent wiring before reconnect. |
| `RealtimeService.forceReconnectIfStale` | `Fit33App.swift:~1209` | D | Socket health gate + Phase 2.1 grace-cancel fast path. |
| `PushNotificationService.recheckAndRegister` | `Fit33App.swift:~1332–1334` | D | Push correctness. |
| `DailyResetService.checkAndPerformDailyResetIfNeeded` | `Fit33App.swift:~1337` | D | Midnight rollover. |
| `UserManager.syncProfileToCloud` | `Fit33App.swift:~1339–1341` | C | Usually invisible within 30s. |
| `NotificationManager.updateBadgeCount` | `Fit33App.swift:~1343` | C | Explicit "lag tolerated" comment. |
| `CloudSyncRetryQueue.drainIfDue` | `Fit33App.swift:~1346` | D | Data integrity for queued writes. |
| `ChallengeOpponentWakeService.requestWake(.foreground)` | `Fit33App.swift:~1355` | D | Cross-device freshness poke; server throttled. |

### C) Wearable force-sync block (also gated by `runFullResync` today)

| Call | Source line | Category | Notes |
|---|---|---|---|
| `WhoopService.syncAllData(force:)` + `ReadinessService.recompute` | `Fit33App.swift:~1097–1120` | D | Dashboard readiness correctness. |
| `OuraService.syncAllData(force:)` + `ReadinessService.recompute` | `Fit33App.swift:~1123–1135` | D | Fallback readiness pipeline. |
| `StravaService.syncActivities` + inactivity probe | `Fit33App.swift:~1143–1154` | D | Cardio surfaces + token health. |

## Cross-references

- Realtime channel enumeration + post-connect canonical resync: [Fit33/RealtimeService.swift](../../Fit33/RealtimeService.swift) ~500–617 for subscribe sequence; ~527 log line lists channels; ~567–595 detached post-connect resync mirrors the ten-pack + `fetchReceivedWorkouts`.
- Grace disconnect / Phase 2.1 gate: [Fit33/RealtimeService.swift](../../Fit33/RealtimeService.swift) ~728–818 (`disconnect`, `scheduleGraceDisconnect`, `cancelGraceDisconnect`, `actuallyDisconnectAll`), [Fit33/PerfFlags.swift](../../Fit33/PerfFlags.swift) (`phase2RealtimeGate`).
- scenePhase fanout site: [Fit33/Fit33App.swift](../../Fit33/Fit33App.swift) ~993–1356, especially ~1291–1326 for `runFullResync` body.
- `disconnect()` on background: [Fit33/Fit33App.swift](../../Fit33/Fit33App.swift) ~1384–1387 calls `RealtimeService.disconnect()` — behavior ties to `PerfFlags.phase2RealtimeGate` (`RealtimeService.disconnect` ~745–750).

## Why no implementation in this build

1. **The user's hard requirement was "exactly the same just apple-level faster."** Promoting Category-D items to always-run is a *behavior change* (more correct, but adds 3 RPCs to brief-blip foregrounds where today fires zero). It buys correctness, not speed.

2. **Today's gate already correctly skips the 10-pack on brief blips.** The 30s debounce is the right knob; the 7 Category-A items get realtime-delivered freshness via Phase 2.1's grace-disconnect window without the foreground fetch.

3. **The 3 Category-D items have a real (small) staleness window today**, but it's ≤30s by definition (next foreground ≥30s from prior fires the gate). User reports of stale group-challenges or missed shared-workout notifications would be the motivation to ship Phase 2.2 in a follow-up.

4. **Phase 2.1 alone gets us 95% of the perceptible wins**: no socket teardown on every brief blip means no 800ms-1500ms reconnect latency on every foreground in the 2-30s window. The remaining gate work is correctness-flavored, not speed-flavored.

## Future work checklist (if/when Phase 2.2 is implemented)

- [ ] Refactor `runFullResync` block at `Fit33App.swift:~1291–1326` to split Category-A (stays gated) from Category-D (moves out).
- [ ] Add a fingerprint-able `AppLogger.info("perf.signpost.foreground_gate.category_d.always_runs=1")` for telemetry parity.
- [ ] Write parity test: "After 25s background→foreground, the 3 Category-D RPCs MUST fire; the 7 Category-A RPCs MUST NOT fire."
- [ ] Document in `QUALITY_PERFORMANCE_AGENT.md` invariant QP-2x: "RPCs without realtime coverage MUST refresh on every foreground regardless of debounce window."
- [ ] Validate 48h on TestFlight (group-challenge widget freshness, shared-workout notification delivery) before flipping the production flag.
