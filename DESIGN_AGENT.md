# Fit33 Lead Designer Agent

> **Role**: Single source of truth for visual identity. Every UI decision routes through these tokens and patterns.
>
> Deep history, migration notes, and dated decisions live in [`docs/history/DESIGN_AGENT.md`](docs/history/DESIGN_AGENT.md). This file is **rules-shaped**, not a changelog.

---

## Invariants (will cause visual bugs / design-system drift if violated)

1. **No hardcoded fonts.** Always use `Font.ds_*` tokens from `DesignSystem.swift`. Never `.font(.system(size:))` inline. See token table below. **`ds_*` tokens scale with Dynamic Type automatically via `UIFontMetrics`** — consumers never need a manual scaler. Hardcoded `.font(.system(size:))` is doubly broken: ignores tokens AND ignores Dynamic Type.
2. **No hardcoded padding.** Always use `Spacing.*` tokens (`xxxs` 2 / `xxs` 4 / `xs` 8 / `sm` 12 / `md` 16 / `lg` 24 / `xl` 32 / `xxl` 48).
3. **No hardcoded corner radii.** Always use `CornerRadius.*` (`sm` 8 / `md` 12 / `lg` 16 / `xl` 24 / `pill` 999).
4. **No hardcoded card colors.** Use `Color.cardBackground` (`AdaptiveColors.swift`). Never `Color(white: 0.12)`, `Color.black` as bg, or a local `private var cardBackground`.
5. **Every full-page screen gets `AnimatedOrbBackground`** (correct tab variant). Exceptions: premium upsell, active-workout overlays.
6. **Buttons use `UniversalScaleButtonStyle`** with haptic feedback. Never a local `ScaleButtonStyle`.
7. **Section headers use `SectionHeader`** from `DesignSystem.swift`. Never an ad-hoc HStack.
8. **Decorative animations must gate through `MotionPolicy.shouldDisableDecorative`** (or `MotionPolicy.shouldDisableDecorative(reduceMotion:)` for SwiftUI views that already read `@Environment(\.accessibilityReduceMotion)`). `MotionPolicy` lives in `Fit33/MotionPolicy.swift` and is the canonical base gate — it checks both `UIAccessibility.isReduceMotionEnabled` and `ProcessInfo.processInfo.isLowPowerModeEnabled`. `AnimatedOrbBackground.shouldDisableMotion` delegates here. Functional / state-transition animations (sheet presentations, button feedback, list inserts) are EXEMPT — they use SwiftUI's built-in reduce-motion handling.
9. **Primary card = `.sleekCard()`.** List-row card = `Color.cardBackground` + `RoundedRectangle(.continuous)`. Never invent a third card treatment.
10. **iOS 26 Liquid Glass**: never set opaque `backgroundColor` on `UITabBar`/`UINavigationBar` — that blocks system glass. For custom toolbar materials use `.adaptiveToolbarBackground()`.
11. **Main tab navigation pattern (current):** hidden system nav bar + custom in-layout header. See `LEGACY_CUSTOM_HEADERS.md` before changing.
12. **Translucent backgrounds must honor Reduce Transparency.** Use `.adaptiveMaterialBackground(cornerRadius:fallback:)` from `Fit33/AdaptiveMaterialBackground.swift` instead of raw `.background(.ultraThinMaterial)`. The modifier auto-swaps to `Color.cardBackground` (or a custom opaque fallback) when the user enables Reduce Transparency in iOS Settings → Accessibility → Display & Text Size.

---

## Tokens — Canonical Tables

### Typography (`DesignSystem.swift`)
| Token | Size | Weight | Use |
|---|---|---|---|
| `ds_displayLarge` | 42 | Bold | Hero numbers |
| `ds_displayMedium` | 34 | Bold | Page titles (rare) |
| `ds_heading1` | 28 | Bold | Section titles, screen headers |
| `ds_heading2` | 22 | Bold | Card headers |
| `ds_heading3` | 18 | Semibold | Card subheaders, row titles |
| `ds_bodyLarge` | 17 | Regular | Primary body |
| `ds_bodyMedium` | 15 | Regular | Secondary body, cards |
| `ds_bodySmall` | 13 | Regular | Helper text |
| `ds_labelLarge` | 15 | Semibold | Button labels |
| `ds_labelMedium` | 13 | Semibold | Chips, tags |
| `ds_labelSmall` | 11 | Medium | Timestamps |
| `ds_stat` / `ds_statSmall` | 24 / 18 | Bold rounded | Metrics |

Never use sizes between tokens (no 14/16/20pt).

All `ds_*` typography tokens are wired through `UIFontMetrics` and scale with the user's Dynamic Type setting (default-size output unchanged). New code MUST reach for a `ds_*` token — `Font.system(size:)` skips both the design system and Dynamic Type scaling.

### Color — Dark base / Adaptive
```
Color.darkBackground         rgb(0.07, 0.07, 0.09)   — never Color.black
Color.cardBackground         white (light) / rgb(0.14, 0.14, 0.16) (dark)
Color.cardBackgroundSecondary
Color.adaptiveText / .adaptiveSecondaryText / .adaptiveDivider
```
Dark gradient MUST include purple-blue tint — never plain gray.

### Accent gradients (`LinearGradient.ds_*`)
`.ds_primaryAccent` (blue→purple) · `.ds_socialAccent` (cyan→blue) · `.ds_successAccent` (green→blue) · `.ds_energyAccent` (orange→red).

### Category accents
Chest=Red · Back=Blue · Legs=Green · Shoulders=Purple · Arms=Orange · Core=Yellow · Cardio=Cyan · Flexibility=Mint.

### Orb variants
`.home()` · `.workout()` · `.exercises()` · `.meals()` · `.stats()` · `.friends()` · `.onboarding()` — see `AdaptiveColors.swift`.

---

## Card System

**`.sleekCard(cornerRadius:accentColor:)`** — 5-layer premium depth (glow / depth / gradient fill / top highlight / accent border). Use for any primary content card (dashboard widgets, challenge cards, program cards, PR cards, quest cards, league standings).

**Flat card** — `RoundedRectangle(cornerRadius: CornerRadius.lg).fill(Color.cardBackground)` for grouped-list rows (settings toggles, notification rows).

**Expandable sleek card** — chevron.down toggle, `.spring(response: 0.35, dampingFraction: 0.8)`, `.transition(.opacity.combined(with: .move(edge: .top)))`. Used in `WorkoutCompletionView`, `ShareWorkoutSheet`.

Corner radii: widgets `.xl`, list rows `.lg`, inputs `.sm`, buttons `.md` or `.pill`.

Shadows:
| Level | radius | y | darkOp | lightOp |
|---|---|---|---|---|
| Subtle | 4 | 2 | 0.15 | 0.04 |
| Standard | 8 | 4 | 0.20 | 0.08 |
| Elevated | 12 | 6 | 0.30 | 0.08 |
| Glow | 20 | 10 | 0.20 | 0.12 |

---

## Navigation Presentation
| Flow | Presentation |
|---|---|
| Multi-step creation (challenge, workout, program) | `.fullScreenCover` + inner `NavigationStack` |
| Detail drill-down (exercise, recipe, friend profile, challenge) | `NavigationLink` push |
| Quick action (share, QR scan, picker) | `.sheet` |
| Destructive confirm | `.alert` / `.confirmationDialog` |
| Settings sub-page | `NavigationLink` push |

Never nest `NavigationStack` inside a pushed detail view (breaks `.navigationDestination` + bounces on `dismiss()`).

---

## Animation Standards
| Type | Duration | Curve |
|---|---|---|
| Button press | 0.15s | `.easeInOut` |
| Card appearance | 0.3s | `.spring(response: 0.5, dampingFraction: 0.8)` |
| Orb (when motion allowed) | 3-5s | `.easeInOut` (single-fire drift, not `.repeatForever`) |
| Side-panel slide | 0.35s | `.spring(dampingFraction: 0.85)` |

Orbs changed from `.repeatForever` to single-fire (drift-and-stop) — continuous GPU rendering was regressing FPS on all tabs.

---

## Empty States
Icon (`ds_heading1`, `.secondary`) → Title (`ds_heading3`) → Subtitle (`ds_bodyMedium`, `.secondary`) → optional `DSPillButton` action. Spacing `.md` between elements.

---

## Per-Screen Ship Checklist
- [ ] `AnimatedOrbBackground` (right variant)
- [ ] Cards: `.sleekCard()` or `Color.cardBackground`
- [ ] All fonts → `ds_*`
- [ ] All padding → `Spacing.*`
- [ ] All radii → `CornerRadius.*`
- [ ] Buttons → `UniversalScaleButtonStyle` + haptic
- [ ] Section headers → `SectionHeader`
- [ ] Empty state present
- [ ] Light + dark mode verified
- [ ] Dynamic Type verified
- [ ] Navigation presentation matches flow type

---

## Shared-File Ownership
| File | Primary | Notes |
|---|---|---|
| `DesignSystem.swift` | Design | Typography, spacing, radius, gradient tokens, SectionHeader, DSCard, DSPillButton |
| `AdaptiveColors.swift` | Design | Colors, SleekCardBackground, AnimatedOrbBackground, AdaptiveGradient |
| `SharedUtilities.swift` | Product Engineer (co) | UniversalScaleButtonStyle, HapticManager |

*North star: match the Dashboard. If your screen doesn't feel like the Dashboard, it's wrong.*

---

## See Also
- `docs/history/DESIGN_AGENT.md` — dated design decisions + sprint changelog (immutable archive).
- `DESIGN_SYSTEM_AGENT.md` — token enforcement, migration order, adoption metrics.
- `.cursor/rules/swiftui-rules.mdc` — the auto-loaded rule file that enforces `.ds_*` tokens in code.
