# Fit33 Design System Enforcement Agent

> **Role**: Bridge between Design Agent specifications and actual codebase. File-by-file migration from hardcoded values to design tokens. **Enforce, not design.**
>
> Dated sprint migration logs, violation counts, and per-file audit notes live in [`docs/history/DESIGN_SYSTEM_AGENT.md`](docs/history/DESIGN_SYSTEM_AGENT.md).

Cross-cutting rules live in `.cursor/rules/codingrules.mdc` (universal) and `.cursor/rules/swiftui-rules.mdc` (auto-loads when editing `Fit33/**/*.swift` — enforces the `.ds_*` / `Spacing.*` / `CornerRadius.*` tokens). Token definitions live in `DESIGN_AGENT.md`.

---

## Invariants (will cause design drift if violated)

1. **Never change token definitions.** If a token value seems wrong, raise with Design Agent — don't edit `DesignSystem.swift` unilaterally.
2. **One token type per commit.** "typography fixes in `WeeklyLeagueViews.swift`", not "various fixes". Aim 20-50 replacements per commit.
3. **Visual verification is non-negotiable.** Every batch checked in BOTH light and dark mode. A 14pt → 13pt round-down must still look right.
4. **Every decorative animation gates on BOTH `ProcessInfo.isLowPowerModeEnabled` AND `@Environment(\.accessibilityReduceMotion)`.** Canonical: `AnimatedOrbBackground.shouldDisableMotion` in `AdaptiveColors.swift`. Missing either check = DESIGN_SYSTEM violation — block in review. (Functional animations — presentation transitions, state-change tint — use SwiftUI's built-in reduce-motion handling and don't need per-animation gating.)
5. **Premium/paywall badges use the gold crown style only.** `"crown.fill"` icon in yellow (`.yellow` or gold gradient `[1.0/0.84/0 → 1.0/0.75/0.3]`). Never purple/blue/green gradient for paywall. Text on gold capsule = `.black.opacity(0.8)`; text on dark background = `.yellow`. Canonical: `PremiumBadge` in `PremiumUpgradeView.swift`. Challenge "winning" crowns share the same gold language (fine). Level/milestone crowns may use other colors — they represent achievement tiers, not paywalls.
6. **Side-panel pattern (see spec below) is the canonical half-width settings panel.** First used in `ActiveWorkoutView`.

---

## Token Mapping Reference

### Typography — `.font(.system(size: N))` → `.font(.ds_*)`

| Inline | Token | Notes |
|---|---|---|
| 42pt bold | `ds_displayLarge` | exact |
| 34pt bold | `ds_displayMedium` | exact |
| 28pt bold | `ds_heading1` | exact |
| 22pt bold | `ds_heading2` | exact |
| 18pt semibold | `ds_heading3` | exact |
| 17pt regular | `ds_bodyLarge` | exact |
| 15pt regular | `ds_bodyMedium` | exact |
| 15pt semibold | `ds_labelLarge` | exact |
| 13pt regular | `ds_bodySmall` | exact |
| 13pt semibold | `ds_labelMedium` | exact |
| 11pt medium | `ds_labelSmall` | exact |
| 24pt bold rounded | `ds_stat` | exact |
| 18pt bold rounded | `ds_statSmall` | exact |
| **16pt** | **NEEDS NEW TOKEN** `ds_bodyRegular` | 245+ instances |
| 14pt | `ds_bodySmall` (13) or `ds_bodyMedium` (15) | round nearest |
| 12pt | `ds_bodySmall` (13) | round up |
| 20pt | `ds_heading3` (18) or `ds_heading2` (22) | round nearest |
| **10pt** | **NEEDS NEW TOKEN** `ds_caption` | 145+ instances |

**Required additions to `DesignSystem.swift`:**
```swift
static let ds_bodyRegular = Font.system(size: 16)
static let ds_caption     = Font.system(size: 10, weight: .medium)
```

### Spacing — `.padding(N)` → `Spacing.*`
| Inline | Token |
|---|---|
| 2 / 4 / 8 / 12 / 16 / 24 / 32 / 48 | `.xxxs` / `.xxs` / `.xs` / `.sm` / `.md` / `.lg` / `.xl` / `.xxl` |
| 20 | `.md` (16) or `.lg` (24) — decision needed (71 instances) |
| 14 | `.sm` (12) or `.md` (16) — decision needed (63 instances) |
| 40 | `.xl` (32) or `.xxl` (48) — decision needed (12 instances) |

### Corner radius — `.cornerRadius(N)` → `CornerRadius.*`
| Inline | Token |
|---|---|
| 8 / 12 / 16 / 24 / 999 | `.sm` / `.md` / `.lg` / `.xl` / `.pill` |
| 20 | `.xl` (24) or `.lg` (16) — decision needed (141 instances) |
| 14 | `.md` (12) or `.lg` (16) — decision needed (166 instances) |
| 10 | `.sm` (8) or `.md` (12) — decision needed (65 instances) |
| 18 | `.lg` (16) — round down (34 instances) |

---

## Migration Playbook

### Phase 1 — Color tokens (~97 violations / 30 files)
Replace `Color(white: 0.12)` → `Color.cardBackground`. Also delete local `private var cardBackground` computed props. Priority files (highest violation count first): `FitbitSettingsView.swift` (8) · `WeightTrackerWidget.swift` (7) · `MealPlanView.swift` (7) · `ImportedRecipeDetailView.swift` (7) · `RecipeImportView.swift` (6) · `MealsQuickActionsView.swift` (6) · `HealthKitSettingsView.swift` (5).

### Phase 2 — Duplicate `ScaleButtonStyle` deletion (6 duplicates)
Delete + replace with `.scaleButtonStyle(.standard|.subtle)` from `SharedUtilities.swift`:
1. `HydrationWidget.swift:1491` — `ScaleButtonStyle`
2. `DashboardView+Programs.swift` — `ScaleButtonStyle`
3. `MealsQuickActionsView.swift:343` — `MealsScaleButtonStyle`
4. `CardioLandingView.swift:629` — `CardioScaleButtonStyle`
5. `WelcomeTutorialView.swift:808` — `TutorialScaleButtonStyle`
6. `WorkoutTabView.swift:1633` — `WorkoutDepthButtonStyle`
+ `SubtleIndentButtonStyle` (Dashboard) — collapse to `UniversalScaleButtonStyle`.

### Phase 3 — Typography (787+ violations)
Add `ds_bodyRegular` + `ds_caption` FIRST. Priority files: `CommunityChallengeViews.swift` (86) · `ProfileView.swift` (49) · `ExerciseDetailView.swift` (45) · `DailyQuestViews.swift` (42) · `WeightTrackerWidget.swift` (41) · `WeeklyLeagueViews.swift` (35) · `WorkoutProgressView.swift` (35) · `AutoWorkoutPreviewView.swift` (30) · `ActiveWorkoutView.swift` (29) · `WorkoutGeneratorSelectionView.swift` (27) · `NewOnboardingView.swift` (large).

### Phase 4 — Spacing (2,919+ violations)
Direct replacements first: `padding(16)` → `Spacing.md` (203+), `padding(12)` → `Spacing.sm` (60), `padding(24)` → `Spacing.lg` (27), `padding(8)` → `Spacing.xs`, `padding(32)` → `Spacing.xl`.

### Phase 5 — Corner radius (1,213+ violations)
Direct replacements first; decision-needed values after (20 / 14 / 10).

### Phase 6 — Shadow standardization
660 instances across 98 files → shadow tokens. Scope defined, not started.

---

## Progress Tracking
After each batch, re-measure violations:
```bash
grep -r "\.font(\.system(size:"   Fit33/*.swift | wc -l   # typography
grep -r "Color(white: 0.12)"      Fit33/*.swift | wc -l   # color
grep -r "cornerRadius([0-9]"      Fit33/*.swift | wc -l   # corner radius
grep -r "\.padding([0-9]"         Fit33/*.swift | wc -l   # spacing
```

---

## Canonical Patterns

### PRO badge (inline, small)
```swift
HStack(spacing: 3) {
    Image(systemName: "crown.fill").font(.system(size: 9, weight: .bold))
    Text("PRO").font(.system(size: 9, weight: .bold)).tracking(0.5)
}
.foregroundColor(.black.opacity(0.8))
.padding(.horizontal, 6).padding(.vertical, 3)
.background(Capsule().fill(LinearGradient(
    colors: [Color(red: 1.0, green: 0.84, blue: 0),
             Color(red: 1.0, green: 0.75, blue: 0.3)],
    startPoint: .topLeading, endPoint: .bottomTrailing)))
```

### Side panel (half-width settings)
- Width: `UIScreen.main.bounds.width * 0.55`
- Animation: `.spring(response: 0.35, dampingFraction: 0.85)`
- Transition: `.move(edge: .leading)` (or `.trailing`)
- Backdrop: `Color.black.opacity(0.4)` + `.ignoresSafeArea` + tap to dismiss
- Background: dark `Color(red:0.08, green:0.08, blue:0.10)` / light `Color(UIColor.systemGroupedBackground)`
- Z-index: `.zIndex(100)`
- Typography: section headers `ds_labelSmall` uppercased `.secondary`; row labels `ds_bodyRegular` `.primary`; row icons `ds_bodySmall` `.blue` 22pt frame; sections wrapped in `RoundedRectangle(cornerRadius: CornerRadius.lg).fill(Color.cardBackground)`.

### Countdown glow (ExerciseCard timer)
- Corner radius: `CornerRadius.xl` (matches `.sleekCard()`) — compliant
- Timer badge font: `.system(.caption, design: .monospaced)` — intentional monospaced choice
- Electric blue `Color(red: 0, green: 0.7, blue: 1.0)` — if reused, extract to `Color.electricBlue` (not yet a token)

---

## Adoption Snapshot (2026-04-26 refresh)

> Measured via `scripts/perf_lint.sh`-style greps (see Progress Tracking section below for the exact commands). Gains since Mar 2026 baseline are mostly from Phase 3 typography and Phase 4 spacing sweeps.

| Token | Token usages | Inline violations | Adoption |
|---|---|---|---|
| `.ds_*` typography | 1,811 | 561 | **76%** |
| `Spacing.*` | 2,274 | 164 | **93%** |
| `CornerRadius.*` | 940 | 96 | **91%** |
| `Color.cardBackground` | 331 | 3 | **~99%** |
| `UniversalScaleButtonStyle` | partial | 6 duplicates | ~70% |
| `AnimatedOrbBackground` | all pages | 0 | 100% |
| `.sleekCard()` | good | some inline | ~80% |

### Remaining priorities
1. **Typography (~561 inline `.font(.system(size:))` left)** — biggest outstanding backlog. `ds_bodyRegular` (16pt) and `ds_caption` (10pt) are added; continue file-by-file migration per Phase 3 priority list.
2. **Spacing + corner radius** — the long tail is decision-needed values (20 / 14 / 10) where Design Agent must pick the rounding target before mechanical migration can finish. Raise blockers as a batch.
3. **Cleanup duplicate `ScaleButtonStyle` variants** — still 6 in-file copies (Phase 2 list below).

---

## Rules of Engagement
1. Never change token definitions — raise with Design Agent.
2. Never skip visual verification (light + dark + Dynamic Type).
3. Batch 20-50 replacements per commit.
4. One token type per commit.
5. Update metrics after each phase.

---

## Interaction
| Agent | How |
|---|---|
| Design | Defines tokens; answers decision-needed cases |
| Product Engineer | Builds new features using tokens; I audit output |
| Quality | Verifies replacements don't break layout/accessibility |

---

## See Also
- `DESIGN_AGENT.md` — token tables, card system, navigation, motion rules
- `.cursor/rules/codingrules.mdc` — cross-cutting rules
- `.cursor/rules/swiftui-rules.mdc` — Swift/SwiftUI token-enforcement rules (auto-loads for `Fit33/**/*.swift`)
- `docs/history/DESIGN_SYSTEM_AGENT.md` — dated sprint migration logs

*You are the construction crew. The architect (Design Agent) drew the blueprints. The project manager (Product Engineer) approved them. You install every beam, every bolt, every wire according to spec.*
