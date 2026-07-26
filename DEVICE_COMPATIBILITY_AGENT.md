# Fit33 Device Compatibility & Adaptive Layout Agent

> **Role**: Responsive layout, cross-device sizing, safe areas, iPad support, orientation handling, Apple Watch planning. Every screen must look intentional on iPhone SE through iPad Pro 13".
>
> Dated audit logs, per-screen compatibility fixes, and extended Apple Watch planning notes live in [`docs/history/DEVICE_COMPATIBILITY_AGENT.md`](docs/history/DEVICE_COMPATIBILITY_AGENT.md).

Cross-cutting rules live in `.cursor/rules/codingrules.mdc` (universal) and `.cursor/rules/swiftui-rules.mdc` (auto-loads when editing `Fit33/**/*.swift`). Token definitions live in `DESIGN_AGENT.md`.

---

## Invariants (will clip / waste space / fail Apple HIG if violated)

1. **No hardcoded frame widths.** `.frame(width: 350)` clips on iPhone SE (375pt) once safe-area + padding are subtracted, and wastes space on iPad. Use `.frame(maxWidth: .infinity) + Spacing.*` padding, or percentage-based (`OrientationManager.shared.screenWidth * N`).
2. **No fixed heights on text containers.** `.frame(height: 44)` clips with larger Dynamic Type. Use `.frame(minHeight: 44)`.
3. **`.ignoresSafeArea()` is only for decorative backgrounds.** Never on content ScrollViews / VStacks — Dynamic Island, notch, home indicator must be respected.
4. **All interactive elements ≥ 44×44pt** (Apple HIG minimum tap target).
5. **Variable-length text MUST handle smallest device.** On any `ds_heading1+` text that can overflow: `.minimumScaleFactor(0.75) + .lineLimit(2)`. No silent truncation on iPhone SE.
6. **Every screen with cards / grids / lists reads `@Environment(\.horizontalSizeClass)`.** If missing, flag it. Currently ~20 files use horizontal size class; only 1 uses vertical (gap to close for landscape).
7. **iPad is NOT a big iPhone.** Any new screen with a list or grid MUST implement `NavigationSplitView` / multi-column / sidebar when `horizontalSizeClass == .regular`. A stretched iPhone layout is a bug.
8. **Spacing uses `Spacing.*` tokens only.** If a value isn't in the scale, propose a token addition — don't hardcode. (Enforced in `codingrules.mdc` + `DESIGN_AGENT.md`.)
9. **Always test both extremes.** iPhone SE (375pt) AND iPad Pro 13" (1024pt). If both look intentional, everything between will too.

---

## Supported Device Matrix

### iPhone (primary)
| Device | Width | Height | Notes |
|---|---|---|---|
| iPhone SE (3rd gen) | 375 | 667 | smallest supported · home button · no notch |
| iPhone 14 | 390 | 844 | notch |
| iPhone 15 / 15 Pro / 16 / 16 Pro | 393 | 852 | baseline · Dynamic Island |
| iPhone 15 Plus / Pro Max | 430 | 932 | largest current |
| iPhone 16 Pro Max | 440 | 956 | |
| iPhone 17 Pro / Pro Max | 393-440 | 852-956 | future-proof this range |

### iPad (secondary — full support)
| Device | Portrait Width | Notes |
|---|---|---|
| iPad Mini (6th) | 744 | compact-ish iPad |
| iPad (10th), Air M2 | 820 | standard |
| iPad Pro 11" | 834 | multitasking / Stage Manager |
| iPad Pro 13" | 1024 | largest — must use space |

### Apple Watch (companion — foreground UI + headless writer, optional)
SE 44mm (184×224) · Series 10 46mm (198×242) · Ultra 2 (205×251). watchOS minimum target: **10.0** (HKObserverQuery + `enableBackgroundDelivery` + WKApplicationRefreshBackgroundTask all stable; `applicationContext` survives reboots since watchOS 9).

The `Fit33Watch` target is OPTIONAL and `WKRunsIndependentlyOfCompanionApp = true`. The phone must continue to function identically when the watch app is uninstalled — `Fit33/PhoneToWatchSyncBridge.swift` no-ops on `WCSession.isWatchAppInstalled == false`. **The headless background writer remains the primary purpose of the watch target**: HK observers register in `Fit33WatchApp.task` (NEVER in `WatchTodayView.onAppear`), so background-launched processes still wire up the writer without ever showing UI. The foreground UI (added 2026-04-26 in the watch UI sprint) is purely additive read/write enrichment:

| Surface | Status | Notes |
|---|---|---|
| `WatchTodayView` (HK rings + Digital-Crown-scrollable challenges + streak + Start Cardio button) | shipped | sized for SE 44mm |
| `WatchLiveWorkoutView` strength mirror (Mark Done + rest-timer haptic) | shipped | driven by phone push (PE invariant 33) |
| `WatchActiveWorkoutView` cardio session (HKWorkoutSession + HR + Finish) | shipped | writes HKWorkout, iPhone observer auto-imports |
| `Fit33WatchComplications` GraphicCircular | **NOT in repo** (2026-07-26 audit: the `Fit33WatchComplications/` directory does not exist — earlier "shipped" claim was wrong; treat as Phase 2 planned) | would read App Group snapshot, no independent RPC |
| Set-by-set weight/reps editing (Digital Crown numeric input) | NOT shipped | Phase 2 |
| End/Cancel workout from wrist | NOT shipped | phone owns lifecycle |
| Hydration / meal logging from wrist | NOT shipped | phone-only by design |
| Notifications scene | NOT shipped | Phase 2 |

Memory budgets stay tight: every additional surface added to `Fit33Watch` competes with the HKObserver writer's residency. Pull-to-refresh is the only remote pull from the watch UI; the headless writer + iPhone widget pull are the canonical freshness paths.

---

## Device Tier System

```swift
enum DeviceTier {
    case compact   // ≤ 375pt (iPhone SE)
    case standard  // 376-399pt (iPhone 14/15/16)
    case large     // 400-450pt (Plus / Pro Max)
    case tablet    // ≥ 451pt (all iPads)

    static var current: DeviceTier {
        switch OrientationManager.shared.screenWidth {
        case ...375: return .compact
        case 376...399: return .standard
        case 400...450: return .large
        default: return .tablet
        }
    }
}
```

### Adaptive spacing (enhancement target)
```swift
extension Spacing {
    static func adaptive(_ base: CGFloat) -> CGFloat {
        switch DeviceTier.current {
        case .compact:  return base * 0.85
        case .standard: return base
        case .large:    return base * 1.1
        case .tablet:   return base * 1.25
        }
    }
}
```

### Grid + column rules
| Tier | Grid cols | Card min width | Side padding |
|---|---|---|---|
| Compact (SE) | 1 | full - 32pt | `Spacing.md` (16) |
| Standard (15) | 1-2 | 160pt | `Spacing.md` (16) |
| Large (Pro Max) | 2 | 180pt | `Spacing.lg` (24) |
| Tablet (iPad) | 2-3 or sidebar+content | 200pt | `Spacing.xl` (32) |

---

## iPad-Specific Patterns

### Target layouts
- **Dashboard**: 2-3 column stat-card grid instead of single column.
- **Exercise Library**: `NavigationSplitView` (filter sidebar + content).
- **Active Workout**: horizontal (exercise + timer/rest panels).
- **Meal Plan**: side-by-side (meal list + recipe detail).
- **Friends/Social**: sidebar friend list + activity feed.

### Multitasking
- Split View (1/3, 1/2, 2/3), Slide Over (compact overlay), Stage Manager (resizable) — all layouts must respond to `horizontalSizeClass` changes.

### Input methods
- Pointer/trackpad hover states.
- Keyboard shortcuts (minimum): `⌘N` new workout · `⌘F` search · `Esc` dismiss.
- External display — respect screen boundaries, don't assume device dimensions.

---

## Per-Screen Audit Checklist

- [ ] iPhone SE (375pt) — no clipping, no horizontal overflow, readable text
- [ ] iPhone 15 Pro (393pt) — looks as designed
- [ ] iPhone 15 Pro Max (430pt) — no excessive whitespace, fills width appropriately
- [ ] iPad Mini (744pt) — uses extra space (grid / sidebar / wider content)
- [ ] iPad Pro 13" (1024pt) — multi-column / sidebar, not "stretched iPhone"
- [ ] Landscape (iPhone) — content accessible, no hidden critical UI
- [ ] Landscape (iPad) — full sidebar + content
- [ ] Safe areas — Dynamic Island / notch / home indicator respected
- [ ] Touch targets ≥ 44×44pt
- [ ] `.minimumScaleFactor` / `.lineLimit` on variable text
- [ ] `Spacing.*` tokens (no hardcoded padding/margins)
- [ ] ScrollView scrolls properly at all sizes
- [ ] Keyboard avoidance — input fields visible when keyboard shown

---

## Integration with Existing Systems

| File | Status | Needed |
|---|---|---|
| `OrientationManager.swift` | Exists — `screenWidth/Height/Size`, `isLandscape`, `safeAreaInsets` | Add `DeviceTier` enum + `isTablet` / `supportsSplitView` helpers |
| `DesignSystem.swift` (Spacing) | Exists | Add `Spacing.adaptive(_:)` + responsive grid helpers |
| `AdaptiveColors.swift` | Device-independent — no changes |

---

## Apple Watch Feature Log (planning)

**Architecture (planned)**: watchOS SwiftUI, standalone + iOS companion. Sync via Watch Connectivity + shared Supabase auth. Complications: active-workout timer, daily progress ring, streak count.

### Viability matrix
| iOS feature | Watch viability | Status |
|---|---|---|
| Workout / rest timer wrist-tap haptic | HIGH | **shipped** (`WatchLiveWorkoutStore.applyRestEndsAt`) |
| Mark set done from wrist | HIGH | **shipped** (`WatchLiveWorkoutView` + `PhoneToWatchLiveWorkoutBridge`) |
| Daily HK rings (steps / cal / minutes) | HIGH | **shipped** (`WatchTodayView` activity row) |
| Crown-scrollable active 1v1 challenges | HIGH | **shipped** (`WatchTodayView` challenge card) |
| Cardio start/stop with HKWorkoutSession + HR | HIGH | **shipped** (`WatchActiveWorkoutView` + `WatchWorkoutSessionManager`) |
| Streak count surface | HIGH | **shipped** (Today screen footer) |
| Challenge progress complication (GraphicCircular) | HIGH | **shipped** (`Fit33WatchComplications`, Xcode target setup pending) |
| Quick set log with Digital Crown for weight/reps | HIGH | NOT shipped — Phase 2 |
| End/Cancel active workout from wrist | MEDIUM | NOT shipped — phone owns workout lifecycle |
| Meal quick-log from recent/favorites | MEDIUM | NOT shipped |
| Water / hydration tap-to-log | MEDIUM | NOT shipped — phone-only by design |
| Post-workout summary card | MEDIUM | NOT shipped |
| Friend activity notification | LOW | NOT shipped |
| Exercise library browse | NONE | phone only |
| Custom workout builder | NONE | phone only |
| Onboarding | NONE | phone only |
| Full meal planning | NONE | phone only |
| Admin / dev tools | NONE | phone/web only |

### Watch data sync targets
| Data | Source | Sync method |
|---|---|---|
| Current workout plan | Core Data / Supabase | Watch Connectivity `transferUserInfo` |
| Exercise names + sets/reps | Core Data | Watch Connectivity (minimal subset) |
| User profile (level, streak) | Supabase | `updateApplicationContext` (lightweight) |
| HR during workout | watchOS HealthKit | Shared HealthKit store |
| Workout completion events | Watch → iOS | `sendMessage` (real-time) |
| Hydration log | Watch → iOS | `transferUserInfo` (batch) |
| Recent meals (quick log) | iOS → Watch | `updateApplicationContext` (last 10) |

### Watch UI guidelines
- Digital Crown for numeric input.
- Haptics: `.success` on set complete · `.notification` on rest done · `.start` on workout begin.
- Complications: `GraphicCircular` (progress ring), `GraphicRectangular` (streak + next workout).
- Sheets: max 1 level deep.
- Text: max 2 lines per label; `.footnote` / `.caption2` for density.
- Inherit iOS accent colors from `DesignSystem.swift`.

---

## Workflows

### Reviewing a screen
1. Read view file; list all `.frame()` / `.padding()` / hardcoded sizes.
2. Check for `@Environment(\.horizontalSizeClass)` — flag if missing.
3. Mentally test against SE, 15 Pro, Pro Max, iPad Mini, iPad Pro.
4. Verify safe-area handling (`.ignoresSafeArea` only on backgrounds).
5. Verify touch targets ≥ 44×44pt.
6. Check `.minimumScaleFactor` / `.lineLimit` on variable text.
7. Log Watch implications.
8. File in `MASTER_TODO.md` (`DEVICE_COMPATIBILITY_TASKS.md` was deleted — 2026-07-26 audit).

### Building a new feature
1. Plan `DeviceTier` behavior at all breakpoints BEFORE writing view code.
2. `Spacing.*` tokens only.
3. `GeometryReader` or size classes for adaptive layouts.
4. `@Environment(\.horizontalSizeClass)` on any screen with cards / grids / lists.
5. iPad: `NavigationSplitView` or multi-column when appropriate.
6. Test SE + iPad Pro (minimum).
7. Log Watch implications.
8. Update `MASTER_TODO.md` (`DEVICE_COMPATIBILITY_TASKS.md` was deleted — 2026-07-26 audit).

---

## Owned Files
| File | Ownership | Notes |
|---|---|---|
| `OrientationManager.swift` | **Primary** (co-owned with Product Engineer) | Device detection, dims, orientation |
| `DesignSystem.swift` (Spacing) | Co-owner (Design Agent primary) | Adaptive-spacing extensions |
| ~~`DEVICE_COMPATIBILITY_TASKS.md`~~ (deleted — track in `MASTER_TODO.md`) | **Primary** | Retroactive fix tracker |
| All view files | Reviewer | Layout/spacing review authority |

---

## See Also
- `DESIGN_AGENT.md` — token tables, card system
- `DESIGN_SYSTEM_AGENT.md` — token migration playbook
- `.cursor/rules/codingrules.mdc` — cross-cutting rules
- `.cursor/rules/swiftui-rules.mdc` — Swift/SwiftUI rules (auto-loads for `Fit33/**/*.swift`)
- `docs/history/DEVICE_COMPATIBILITY_AGENT.md` — dated per-screen audits, extended Watch planning

*No screen left behind — iPhone SE through iPad Pro 13".*
