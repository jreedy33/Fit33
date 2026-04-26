# Fit33WatchComplications — watchOS Complication Extension

Watch UI Phase 1 (2026-04-26).

This folder contains all source files for the watchOS complication
target. The Xcode target itself is **not yet wired up in `Fit33.xcodeproj`** —
mirrors the original `Fit33Watch/README.md` setup constraint. Adding
a new target by hand-editing `project.pbxproj` is too risky (signing
entitlements, parent-app embedding, watchOS SDK selection, etc.), so
this README documents the manual one-time Xcode steps.

---

## What this complication does

Renders a **GraphicCircular** progress ring on the watch face for the
user's top active 1v1 challenge — `myTodayProgress / dailyTarget`,
with the streak count in the center. Inline + corner families are
also supported for users who prefer text-only complications.

The complication is a **passive snapshot reader** — it does NOT pull
Supabase from its own process (extensions have a tight memory budget,
~5MB for complications). Instead, the watch app's `WatchTodayStore`
writes a snapshot blob into App Group `group.com.fit33.app` after
every successful pull. The complication's `TimelineProvider` reads
that blob.

Tap → opens the watch app to the Today screen (default WidgetKit
behavior — no `AppIntent` for v1).

---

## Files

| File | Purpose |
| --- | --- |
| `Fit33WatchComplicationsBundle.swift` | `@main` `WidgetBundle` declaration. |
| `Fit33ChallengeRingComplication.swift` | The widget definition + `TimelineProvider` + SwiftUI view. Contains a private mirror of `WatchTodayStore.Snapshot` — keep in lockstep. |
| `Info.plist` | Bundle metadata (`NSExtensionPointIdentifier = com.apple.widgetkit-extension`). |
| `Fit33WatchComplications.entitlements` | App Group entitlement (`group.com.fit33.app`) so the complication can read the snapshot. |

---

## Adding the target in Xcode (one-time setup)

1. **Open** `Fit33.xcodeproj` in Xcode.
2. **File → New → Target…** → choose **`watchOS`** tab → **`Widget Extension`**.
3. **Configure:**
   - Product Name: `Fit33WatchComplications`
   - Bundle Identifier: `com.fit33.app.watchapp.complications`
   - Embed in Application: **`Fit33Watch Watch App`** (NOT the iPhone Fit33 target).
   - Language: Swift
   - Include Configuration App Intent: **No**.
4. **Activate scheme** when prompted.
5. **Delete** the auto-generated `Fit33WatchComplications.swift`,
   `Assets.xcassets`, and `Preview Content/`. We replace them with
   the files in this folder.
6. **Add files to target:** right-click the new `Fit33WatchComplications`
   group → *Add Files to "Fit33"…* → select the two `.swift` files
   in this folder + `Info.plist` + `Fit33WatchComplications.entitlements`.
   Make sure ONLY the `Fit33WatchComplications` target checkbox is ticked.
7. **Build Settings → Code Signing Entitlements:** point to
   `Fit33WatchComplications/Fit33WatchComplications.entitlements`.
8. **Build Settings → Info.plist File:** point to `Fit33WatchComplications/Info.plist`.
9. **Signing & Capabilities (Fit33WatchComplications target):**
   - Add **App Groups** capability and check `group.com.fit33.app`.
10. **Verify watch app target embeds the new extension** (Xcode usually
    does this for you in step 3): the watch app's "Embed Extensions"
    build phase should list `Fit33WatchComplications.appex`.
11. **Build & run** the watch scheme on a paired Apple Watch
    simulator (or device). After the watch app has run once and
    refreshed, long-press the watch face → Edit → add the
    Fit33 complication.

---

## Snapshot contract

The complication reads `group.com.fit33.app` UserDefaults under key
`fit33.watch.today_snapshot.v1`. The shape is owned by:

```
Fit33Watch Watch App/WatchTodayStore.swift::Snapshot
```

Mirror that struct in `Fit33ChallengeRingComplication.swift::Fit33ChallengeSnapshot`.
Add new columns to BOTH places in the same commit.

---

## Failure modes

| Symptom | Cause | Behaviour |
| --- | --- | --- |
| Complication shows 0% | Watch app never ran / never refreshed | Snapshot blob missing — provider returns a blank entry. User opens the watch app once → snapshot writes → next timeline reload populates. |
| Complication stale by hours | Watch off-wrist / no HK observer fires | Server-side state is fresh from the iPhone observer; watch app's foreground refresh is the canonical update path. |
| Tap does nothing | iOS hasn't installed the extension yet | Force-reinstall the watch app from iPhone → Watch app. |

---

## See Also
- `Fit33Watch/README.md` — sibling watch app target setup notes.
- `Fit33Watch Watch App/WatchTodayStore.swift::Snapshot` — wire format
  source of truth.
- `DEVICE_COMPATIBILITY_AGENT.md` — watch viability matrix.
