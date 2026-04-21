# Fit33 Device Compatibility & Adaptive Layout Agent

> **Role**: Responsive layout, cross-device sizing, safe areas, iPad support, orientation handling, Apple Watch planning. Every screen must look intentional on iPhone SE through iPad Pro 13".
>
> Dated audit logs, per-screen compatibility fixes, and extended Apple Watch planning notes live in [`docs/history/DEVICE_COMPATIBILITY_AGENT.md`](docs/history/DEVICE_COMPATIBILITY_AGENT.md).

Cross-cutting rules live once in `.cursor/rules/codingrules.mdc`. Token definitions live in `DESIGN_AGENT.md`.

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

### Apple Watch (future — logging only)
SE 44mm (184×224) · Series 10 46mm (198×242) · Ultra 2 (205×251).

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
| iOS feature | Watch viability | Priority |
|---|---|---|
| Active workout tracking (timer, set log, rest) | HIGH | P0 |
| Workout / rest timer with haptics + Digital Crown | HIGH | P0 |
| Daily progress / streaks complication | HIGH | P0 |
| Quick set log (tap + Digital Crown for weight/reps) | HIGH | P1 |
| Heart rate integration (watch HR → iOS) | HIGH | P1 |
| Workout start/stop from wrist | HIGH | P1 |
| Meal quick-log from recent/favorites | MEDIUM | P2 |
| Water / hydration tap-to-log | MEDIUM | P2 |
| Post-workout summary card | MEDIUM | P2 |
| Friend activity notification | LOW | P3 |
| Challenge progress complication | LOW | P3 |
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
8. File in `DEVICE_COMPATIBILITY_TASKS.md`.

### Building a new feature
1. Plan `DeviceTier` behavior at all breakpoints BEFORE writing view code.
2. `Spacing.*` tokens only.
3. `GeometryReader` or size classes for adaptive layouts.
4. `@Environment(\.horizontalSizeClass)` on any screen with cards / grids / lists.
5. iPad: `NavigationSplitView` or multi-column when appropriate.
6. Test SE + iPad Pro (minimum).
7. Log Watch implications.
8. Update `DEVICE_COMPATIBILITY_TASKS.md`.

---

## Owned Files
| File | Ownership | Notes |
|---|---|---|
| `OrientationManager.swift` | **Primary** (co-owned with Product Engineer) | Device detection, dims, orientation |
| `DesignSystem.swift` (Spacing) | Co-owner (Design Agent primary) | Adaptive-spacing extensions |
| `DEVICE_COMPATIBILITY_TASKS.md` | **Primary** | Retroactive fix tracker |
| All view files | Reviewer | Layout/spacing review authority |

---

## See Also
- `DESIGN_AGENT.md` — token tables, card system
- `DESIGN_SYSTEM_AGENT.md` — token migration playbook
- `.cursor/rules/codingrules.mdc` — cross-cutting rules
- `docs/history/DEVICE_COMPATIBILITY_AGENT.md` — dated per-screen audits, extended Watch planning

*No screen left behind — iPhone SE through iPad Pro 13".*
