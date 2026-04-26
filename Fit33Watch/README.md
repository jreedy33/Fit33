# Fit33Watch — watchOS Companion App

Realtime Widget Server Pull, Phase 8 (2026-04-26).

This folder contains all source files for the watchOS companion app.
The Xcode target itself is **not yet wired up in `Fit33.xcodeproj`** —
creating a new target by hand-editing `project.pbxproj` is too risky
(scheme generation, signing entitlements, watchOS SDK selection, app-icon
asset catalog, etc. all need to be configured through Xcode's UI). Add
the target by following the steps below, then drag this folder into
the new target's group in the project navigator.

---

## What this app does

A headless-style watchOS app whose only purpose is to keep iPhone
challenge widgets fresh by writing HealthKit data to Supabase from the
wrist. The user never has to open it. We register
`HKObserverQuery + enableBackgroundDelivery(...)` so watchOS wakes us
in the background whenever new step / active-energy / exercise-minute
samples land, and we POST `log_challenge_progress` directly from the
watch process.

Optional install (PE invariant — phones-only path stays viable):
- **The phone app does not require this watch companion to function.**
  Without it, the existing iPhone HKObserverQuery path is the only
  writer; widgets just lean harder on the "stale" indicator (Phase 6).
- When the user uninstalls the watch app, the phone simply stops
  receiving WCSession config updates and falls back to its own
  observers — no broken state, no forced re-authentication.

---

## Files

The active source-of-truth for the watch target is `Fit33Watch Watch App/`
(this folder is a historical mirror; the Xcode `PBXFileSystemSynchronizedRootGroup`
points at the spaced path). Files added since the headless-only Phase 8 are
marked **(Phase 9)**.

| File | Phase | Purpose |
| --- | --- | --- |
| `Fit33WatchApp.swift` | 8a · 9 | `@main` entry. Owns `WatchLifecycle` (HK observer bootstrap), `WatchTodayStore`, `WatchLiveWorkoutStore`. `WatchAppDelegate` routes `WKApplicationRefreshBackgroundTask`. |
| `WatchContentView.swift` | 8a · 9 | Thin wrapper around `WatchTodayView` with a small last-sync footer. |
| `WatchTodayView.swift` | **9** | The glance UI: HK rings + Digital-Crown-scrollable challenge card + streak + Start Cardio button. Auto-presents `WatchLiveWorkoutView` when a strength workout is live on the iPhone. |
| `WatchTodayStore.swift` | **9** | `@MainActor ObservableObject`. HK totals + Supabase challenges + selected index + `refresh()`. Writes App Group snapshot for the complication. |
| `WatchLiveWorkoutView.swift` | **9** | Strength-workout mirror — current set summary, "Mark Done" button, rest-timer countdown ring with wrist-tap haptic on expiry. |
| `WatchLiveWorkoutStore.swift` | **9** | `@MainActor ObservableObject`. Decodes the `liveWorkout` slot pushed from iPhone, runs the local rest-timer + haptic, owns the `completeCurrentSet` send path. |
| `WatchActiveWorkoutView.swift` | **9** | Cardio HKWorkoutSession UI (Run / Walk / Other → live HR + duration → Finish saves HKWorkout). |
| `WatchWorkoutSessionManager.swift` | **9** | HKWorkoutSession + HKLiveWorkoutBuilder owner. |
| `WatchActiveChallenge.swift` | **9** | Slim Codable mirror of the `get_active_challenges` columns the watch UI consumes. |
| `ProgressFreshness.swift` | **9** | Third byte-for-byte copy of `Fit33/ProgressFreshness.swift` (PE invariant 30 — duplicate intentional, no cross-target module). |
| `WatchAppGroupSession.swift` | 8b | Reads supabase-swift session JWT from App Group `group.com.fit33.app`. Reader-only. |
| `WatchSupabaseClient.swift` | 8c · 9 | URLSession-based PostgREST client. Wraps `log_challenge_progress` (Phase 8c) and `get_active_challenges` (Phase 9). No supabase-swift SDK linkage. |
| `WatchHealthKitWriter.swift` | 8c · 9 | `HKObserverQuery` + statistics path for `stepCount` / `activeEnergyBurned` / `appleExerciseTime`. `todayTotal(for:)` is `internal` so the foreground store reuses it. |
| `WatchConnectivityBridge.swift` | 8e · 9 | `WCSession` listener — receives challenge config + the new `liveWorkout` slot, forwards live state to `WatchLiveWorkoutStore`. Adds `sendMessage(_:)` for the watch→phone "completeCurrentSet" reply. |
| `WatchBackgroundRefresh.swift` | 8d | Schedules `WKApplicationRefreshBackgroundTask` ~hourly for fallback heartbeat. |
| `Info.plist` | 8a | Bundle metadata, `WKApplication=true`, `WKRunsIndependentlyOfCompanionApp=true`, HK + background-modes. |
| `Fit33Watch.entitlements` | 8a/b | App Group + HealthKit + background-delivery. |

**Sibling complication target**: see `Fit33WatchComplications/README.md` for
the GraphicCircular complication that reads `WatchTodayStore`'s App Group
snapshot.

The iPhone-side WCSession sender lives at
`Fit33/PhoneToWatchSyncBridge.swift` and is already wired into
`Fit33App.swift::task`.

---

## Adding the target in Xcode (one-time setup)

1. **Open** `Fit33.xcodeproj` in Xcode.
2. **File → New → Target…** → choose `watchOS` tab → `App` (NOT
   "Watch App for iOS App" — that's the legacy paired template).
3. **Configure:**
   - Product Name: `Fit33Watch`
   - Bundle Identifier: `com.fit33.app.watchapp`
   - Language: Swift
   - Interface: SwiftUI
   - Include Notification Scene: **No**
   - Include Complication: **No** (can be added later)
4. **Activate scheme** when prompted.
5. **Delete** the auto-generated `ContentView.swift`,
   `Fit33WatchApp.swift`, `Assets.xcassets`, and `Preview Content/`
   that Xcode created — you'll replace them with the files in this
   folder. (Keep `Assets.xcassets` if you want the default app-icon
   slot; just clear the `AppIcon` placeholder and drag the iPhone
   app's icon set in.)
6. **Add files to target:** right-click the new `Fit33Watch` group →
   *Add Files to "Fit33"…* → select the seven `.swift` files in this
   folder + `Info.plist` + `Fit33Watch.entitlements`. Make sure ONLY
   the `Fit33Watch` target checkbox is ticked.
7. **Build Settings → Code Signing Entitlements:** point to
   `Fit33Watch/Fit33Watch.entitlements`.
8. **Signing & Capabilities (Fit33Watch target):**
   - Add **App Groups** capability and check `group.com.fit33.app`.
   - Add **HealthKit** capability and tick "Background Delivery".
9. **Info.plist target setting:** point to `Fit33Watch/Info.plist`.
10. **iPhone app target → Signing & Capabilities:** ensure the
    iPhone target's **App Groups** capability already includes
    `group.com.fit33.app` (it does — added in Phase 1). No iPhone
    capability changes needed.
11. **Build & run** the watch scheme on a paired Apple Watch
    simulator (or device). On first launch, the app prompts for
    HealthKit access; grant it.

---

## Wire-format invariants

The `applicationContext` payload between iPhone and watch must remain
in lockstep. Source of truth lives in:

- `Fit33/PhoneToWatchSyncBridge.swift::sendActiveChallenges(_:)`
- `Fit33Watch/WatchConnectivityBridge.swift::consume(applicationContext:)`

Shape:

```
{
  "v": 1,
  "challenges": [
    { "id": "<uuid>", "type": "steps" },
    { "id": "<uuid>", "type": "calories" },
    { "id": "<uuid>", "type": "active_minutes" }
  ]
}
```

Only the three families above are auto-tracked from HealthKit. Hydration,
protein, etc. are NOT synced to the watch — those are user-input on
the phone.

---

## Runtime contract

- The watch app is RLS-pinned to the iPhone-signed-in user. It never
  authenticates independently. If the iPhone app signs out, the JWT
  in App Group goes away on the next iPhone launch and the watch
  silently no-ops.
- HK observer cadence: hourly via `enableBackgroundDelivery`. Live
  observer fires (when the watch is on-wrist and user is moving) are
  unthrottled by us; we coalesce within a 30s window.
- Background refresh cadence: ~1 hour, self-rescheduled.
- Last-sync UX: surfaced in `WatchContentView` so the user can verify
  the app is doing its job without opening any debug surface.

---

## Failure modes & graceful degradation

| Symptom | Cause | Behaviour |
| --- | --- | --- |
| `notAuthenticated` from `WatchAppGroupSession` | iPhone signed out, or iPhone app build pre-Phase 1 | Watch silently no-ops; iPhone will publish session on next launch. |
| `appGroupUnavailable` | Entitlement misconfigured | Hard error in logs; verify App Groups capability on the watch target. |
| HKObserver doesn't fire | Watch off-wrist, user not active, or HK auth denied | Fallback `WKApplicationRefreshBackgroundTask` still pumps once per hour. |
| WCSession `isWatchAppInstalled == false` | User hasn't installed companion | Phone-side bridge no-ops; iPhone HK observer remains the writer. |
| Watch uninstalled | Same as above | Phone keeps working unchanged. |

---

## See also

- `PRODUCT_ENGINEER_AGENT.md` — Realtime Widget Server Pull invariants.
- `INFRA_SECURITY_AGENT.md` — App Group session storage trade-offs.
- `DEVICE_COMPATIBILITY_AGENT.md` — watchOS minimum target + paired-iPhone matrix.
- `Fit33/SupabaseAppGroupStorage.swift` — main-app side that writes the session blob.
- `RunningActivityWidget/WidgetSupabaseFetcher.swift` — sibling URLSession-based fetcher pattern this writer mirrors.
