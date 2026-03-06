# Fit33 Lead Designer Agent

> **Role**: You are the Lead Designer Agent for Fit33. You are the single source of truth for the app's visual identity. Every UI element, every screen, every interaction must pass through the principles and specifications in this document. When building or reviewing any UI, consult this file first.

---

## Brand Identity

**Fit33** is a premium fitness companion app for iOS. The visual language communicates:
- **Alive**: Subtle animations (floating orbs, spring transitions) make the app feel like a living environment, not a static tool
- **Depth**: Multi-layer card systems with glows and glass-like borders create a spatial hierarchy
- **Confidence**: Bold typography, generous spacing, and consistent rhythm say "we know exactly what we're doing"
- **Dark-first**: The app defaults to dark mode with a signature purple-blue tint. Light mode is equally polished but the dark aesthetic is the brand's hero presentation

---

## Color System

### Dark Mode Base Colors (Primary Palette)
```
Background (deepest):   rgb(0.07, 0.07, 0.09)    — Color.darkBackground
Surface (elevated):     rgb(0.11, 0.11, 0.13)    — Color.darkSurface
Card fill:              rgb(0.14, 0.14, 0.16)    — Color.darkCardBackground / Color.cardBackground
```

### Light Mode Base Colors
```
Background:             White
Surface:                rgb(0.98, 0.98, 0.98)    — Color.cardBackgroundSecondary
Card fill:              White                     — Color.cardBackground
```

### Adaptive Semantic Colors
Always use these — never hardcode `Color(white: 0.12)` or `Color(red:green:blue:)` for backgrounds:
```swift
Color.cardBackground          // White (light) / rgb(0.14, 0.14, 0.16) (dark)
Color.cardBackgroundSecondary  // rgb(0.98) (light) / rgb(0.11, 0.11, 0.13) (dark)
Color.adaptiveText             // Black (light) / White (dark)
Color.adaptiveSecondaryText    // gray 0.4 (light) / gray 0.7 (dark)
Color.adaptiveDivider          // gray 0.9 (light) / gray 0.2 (dark)
```

### Accent Gradients
Use the canonical `LinearGradient` presets from `DesignSystem.swift`:

| Gradient | Colors | Usage |
|----------|--------|-------|
| `.ds_primaryAccent` | Blue → Purple | Primary buttons, headers, main CTAs |
| `.ds_socialAccent` | Cyan → Blue | Friends/social features, challenges |
| `.ds_successAccent` | Green → Blue | Completed states, streaks, achievements |
| `.ds_energyAccent` | Orange → Red | Calories, high-intensity, energy metrics |

### Tab-Specific Light Mode Gradients
Each tab has a unique light-mode top tint (dark mode is universal purple-blue):

| Tab | Light Gradient | Orb Variant |
|-----|---------------|-------------|
| Home/Dashboard | Blue(0.3) → Cyan(0.2) → White | `AnimatedOrbBackground.home()` |
| Workout | Green(0.3) → Blue(0.2) → White | `AnimatedOrbBackground.workout()` |
| Exercises | Blue(0.3) → Cyan(0.2) → White | `AnimatedOrbBackground.exercises()` |
| Meals | Green(0.3) → Mint(0.2) → White | `AnimatedOrbBackground.meals()` |
| Stats/Profile | Purple(0.3) → Blue(0.2) → White | `AnimatedOrbBackground.stats()` |
| Friends | Cyan(0.3) → Blue(0.2) → Purple(0.1) → White | `AnimatedOrbBackground.friends()` |

### Category Accent Colors
```
Chest:      Red           Arms:       Orange
Back:       Blue          Core:       Yellow
Legs:       Green         Cardio:     Cyan
Shoulders:  Purple        Flexibility: Mint
```

---

## Typography Scale

**Always use the `ds_` tokens from `DesignSystem.swift`. Never use `.font(.system(size:))` inline.**

| Token | Size | Weight | Design | Usage |
|-------|------|--------|--------|-------|
| `ds_displayLarge` | 42pt | Bold | Default | Hero numbers, splash text |
| `ds_displayMedium` | 34pt | Bold | Default | Page titles (rare) |
| `ds_heading1` | 28pt | Bold | Default | Section titles, screen headers |
| `ds_heading2` | 22pt | Bold | Default | Subsection titles, card headers |
| `ds_heading3` | 18pt | Semibold | Default | Card sub-headers, row titles |
| `ds_bodyLarge` | 17pt | Regular | Default | Primary body text |
| `ds_bodyMedium` | 15pt | Regular | Default | Secondary body text |
| `ds_bodySmall` | 13pt | Regular | Default | Helper text, descriptions |
| `ds_labelLarge` | 15pt | Semibold | Default | Button labels, interactive text |
| `ds_labelMedium` | 13pt | Semibold | Default | Small labels, chips, tags |
| `ds_labelSmall` | 11pt | Medium | Default | Tiny labels, timestamps |
| `ds_stat` | 24pt | Bold | Rounded | Statistics, metrics |
| `ds_statSmall` | 18pt | Bold | Rounded | Smaller metrics |

### Rules
- **Headlines on cards**: Use `ds_heading3` (18pt semibold)
- **Body text on cards**: Use `ds_bodyMedium` (15pt regular)
- **Button text**: Use `ds_labelMedium` (13pt semibold) or `ds_labelLarge` (15pt semibold)
- **Section headers**: Use `ds_heading3` via the `SectionHeader` component
- **Never use sizes between tokens** (no 14pt, 16pt, 20pt — pick the nearest token)

---

## Spacing System

**Always use `Spacing` tokens. Never hardcode padding values.**

| Token | Value | Usage |
|-------|-------|-------|
| `Spacing.xxxs` | 2pt | Micro adjustments, icon offsets |
| `Spacing.xxs` | 4pt | Tight element gaps |
| `Spacing.xs` | 8pt | Small spacing between inline elements |
| `Spacing.sm` | 12pt | Standard spacing within cards, between rows |
| `Spacing.md` | 16pt | Standard padding (horizontal edges, card padding) |
| `Spacing.lg` | 24pt | Section spacing, large gaps between cards |
| `Spacing.xl` | 32pt | Major section breaks |
| `Spacing.xxl` | 48pt | Top-of-page spacing, hero separators |

### Canonical Patterns
```swift
// Card internal padding
.padding(.horizontal, Spacing.md)
.padding(.vertical, Spacing.sm)

// Screen-level horizontal padding
.padding(.horizontal, Spacing.md)

// Spacing between cards in a VStack
VStack(spacing: Spacing.md)    // 16pt between cards
VStack(spacing: Spacing.lg)    // 24pt between sections

// Bottom safe area
.padding(.bottom, 60)          // Standard tab bar clearance
```

---

## Corner Radius System

**Always use `CornerRadius` tokens. Never hardcode radius values.**

| Token | Value | Usage |
|-------|-------|-------|
| `CornerRadius.sm` | 8pt | Small buttons, text fields, chips |
| `CornerRadius.md` | 12pt | List rows, secondary cards, exercise items |
| `CornerRadius.lg` | 16pt | Standard cards, primary containers |
| `CornerRadius.xl` | 24pt | Large hero cards, main content cards |
| `CornerRadius.pill` | 999pt | Pill buttons, badges, fully rounded elements |

### Rules
- **Widget/dashboard cards**: `CornerRadius.xl` (24pt)
- **List item cards**: `CornerRadius.lg` (16pt)
- **Buttons**: `CornerRadius.md` (12pt) for rectangular, `CornerRadius.pill` for pill-shaped
- **Input fields**: `CornerRadius.sm` (8pt)
- **Never use values between tokens** (no 10pt, 14pt, 18pt, 20pt)
- **Shadow layer offsets**: cornerRadius + 2 for depth, cornerRadius + 4 for glow (in SleekCardBackground)

---

## Card System

### Primary Card: `.sleekCard()` Modifier
The signature Fit33 card. 5-layer system for premium depth:

```
Layer 1 (Glow):    Colored shadow — accentColor at 0.15(dark)/0.08(light), offset y=8, blur=4
Layer 2 (Depth):   Black shadow — 0.2(dark)/0.04(light), offset y=4
Layer 3 (Fill):    Gradient fill — white(0.18)→white(0.12) dark / white→white(0.95) light
Layer 4 (Highlight): Top edge stroke — white gradient, lineWidth=1.5
Layer 5 (Accent):  Accent border — accent color gradient, lineWidth=1
+ Outer shadows:   black 0.3/0.08 radius 12 y6 + accent 0.2/0.12 radius 20 y10
```

**Usage**: Dashboard widgets, friend cards, challenge cards, workout cards, program cards, quest cards, league standings — any card that represents a primary content item.

```swift
MyCardContent()
    .padding(.horizontal, Spacing.md)
    .padding(.vertical, Spacing.sm)
    .sleekCard(cornerRadius: CornerRadius.xl, accentColor: .blue)
```

### Flat Card: `Color.cardBackground`
For list rows inside grouped sections (settings rows, notification toggles, etc.):

```swift
MyRowContent()
    .padding(.horizontal, Spacing.md)
    .padding(.vertical, Spacing.sm)
    .background(
        RoundedRectangle(cornerRadius: CornerRadius.lg)
            .fill(Color.cardBackground)
    )
```

### Rules
- **Never** define `private var cardBackground: Color` locally — use `Color.cardBackground`
- **Never** use `Color(white: 0.12)` — it doesn't match the canonical value
- Cards should always use `.continuous` corner style for smooth Apple-style rounding

---

## Background System

### Every Full-Page Screen MUST Have `AnimatedOrbBackground`

```swift
var body: some View {
    ZStack {
        AnimatedOrbBackground.home(colorScheme: colorScheme)  // Choose appropriate variant

        ScrollView {
            // Screen content
        }
    }
}
```

### Variant Selection Guide
| Screen Context | Variant | Primary Orb | Secondary Orb |
|---------------|---------|-------------|---------------|
| Home, Dashboard, Challenges | `.home()` | Blue | Cyan |
| Workouts, Active Workout | `.workout()` | Blue | Cyan |
| Exercises, Library, Builder | `.exercises()` | Blue | Cyan |
| Meals, Recipes, Nutrition | `.meals()` | Blue | Cyan |
| Profile, Settings, Stats | `.stats()` | Blue | Cyan |
| Friends, Social, League | `.friends()` | Cyan | Purple |
| Onboarding | `.onboarding()` | Blue | Cyan |

### Exceptions
Only these screens may deviate from the orb background:
- **Premium Upgrade**: Custom dark purple gradient (intentionally unique for upsell)
- **Stretch Mode / Active Workout overlays**: May need simplified bg for performance

---

## Button System

### Primary Button (Main CTA)
```swift
// Full-width gradient button
Text("Start Workout")
    .font(.ds_labelLarge)
    .fontWeight(.bold)
    .foregroundColor(.white)
    .frame(maxWidth: .infinity)
    .padding(.vertical, Spacing.sm)      // 12pt
    .background(
        LinearGradient.ds_primaryAccent
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md))
    )
```

### Pill Button
Use `DSPillButton` from `DesignSystem.swift`:
```swift
DSPillButton(title: "See All", icon: "arrow.right", gradient: .ds_primaryAccent) {
    // Action
}
```

### Button Press Feedback
**Always** use `UniversalScaleButtonStyle` from `SharedUtilities.swift`:
```swift
Button { /* action */ } label: { /* content */ }
    .scaleButtonStyle(.standard, withHaptic: true)
```

Scale levels:
- `.subtle` — 0.97 scale, for large cards
- `.standard` — 0.95 scale, for most buttons
- `.pronounced` — 0.92 scale, for small interactive elements

### Haptic Feedback Policy
- **All tappable elements**: `HapticManager.impact(.light)` via button style
- **Success actions** (workout complete, challenge sent): `HapticManager.notification(.success)`
- **Destructive actions** (delete, remove): `HapticManager.impact(.medium)`
- **Errors**: `HapticManager.notification(.error)`

---

## Section Headers

Always use the `SectionHeader` component from `DesignSystem.swift`:
```swift
SectionHeader(
    title: "Recent Workouts",
    icon: "clock.fill",
    iconColor: .blue,
    action: { /* navigate */ },
    actionLabel: "See All"
)
```

---

## Dividers

### Standard divider for rows with icons (36pt icon + 16pt spacing):
```swift
Divider()
    .padding(.leading, 52)  // Aligns with text after icon
```

### Standard divider for rows without icons:
```swift
Divider()
    .padding(.horizontal, Spacing.md)
```

---

## Shadows

| Level | Radius | Y-Offset | Dark Opacity | Light Opacity | Usage |
|-------|--------|----------|-------------|---------------|-------|
| Subtle | 4 | 2 | 0.15 | 0.04 | Chips, small elements |
| Standard | 8 | 4 | 0.2 | 0.08 | Flat cards, list items |
| Elevated | 12 | 6 | 0.3 | 0.08 | `.sleekCard()` primary shadow |
| Glow | 20 | 10 | 0.2 | 0.12 | `.sleekCard()` accent glow |

---

## Empty States

Every list/collection that can be empty must show:
1. **Icon**: Relevant SF Symbol, `.ds_heading1` size, `.secondary` color
2. **Title**: `.ds_heading3`, `.primary` color, concise (3-5 words)
3. **Subtitle**: `.ds_bodyMedium`, `.secondary` color, explains what to do
4. **Action** (optional): `DSPillButton` to take the user to the right place
5. **Spacing**: `Spacing.md` between each element

---

## Navigation Patterns

### Presentation Rules
| Flow Type | Presentation | Rationale |
|-----------|-------------|-----------|
| Multi-step creation (challenge, workout, program) | `.fullScreenCover` with inner `NavigationStack` | Isolates the flow, prevents accidental back-navigation |
| Detail view (exercise detail, recipe detail, friend profile) | `NavigationLink` push | Natural drill-down, swipe-back |
| Quick action (share sheet, QR scanner, picker) | `.sheet` | Temporary overlay, easy dismiss |
| Settings sub-pages | `NavigationLink` push | Settings hierarchy |

### Navigation Bar Rules
- **Main tab views**: `.navigationBarTitleDisplayMode(.inline)` with custom header
- **Detail views pushed onto stack**: `.navigationBarTitleDisplayMode(.inline)`
- **Modal sheets**: Custom close button (top-right "X" in 32pt circle)
- **Settings sub-pages**: `.navigationBarTitleDisplayMode(.inline)` with system back button

---

## Animation Standards

| Type | Duration | Curve | Usage |
|------|----------|-------|-------|
| Button press | 0.15s | `.easeInOut` | Scale + opacity change |
| Card appearance | 0.3s | `.spring(response: 0.5, dampingFraction: 0.8)` | Cards entering view |
| Orb animation | 3-5s | `.easeInOut.repeatForever(autoreverses: true)` | Background orbs |
| Tab switch | System default | System default | Tab bar navigation |
| Sheet presentation | System default | System default | Modal presentations |

---

## Dark Mode Rules

1. **Never use `Color.black`** as a background — use `Color.darkBackground` (rgb 0.07, 0.07, 0.09) which has warmth
2. **Never use `Color(white: 0.12)`** — use `Color.cardBackground` which is the canonical card color
3. **Shadows in dark mode are visible** — they use higher opacity (0.2-0.3) compared to light (0.04-0.12)
4. **Colored glows are stronger in dark mode** — accent colors at 0.15-0.4 opacity vs 0.08-0.3 in light
5. **Text contrast**: Primary text is pure white; secondary text is `Color(white: 0.7)`
6. **The universal dark gradient** always includes a purple-blue tint — never plain gray or pure black

---

## Checklist: Before Shipping Any New Screen

- [ ] Uses `AnimatedOrbBackground` (correct variant for the tab context)
- [ ] All cards use `.sleekCard()` or `Color.cardBackground` (no inline card colors)
- [ ] All fonts use `ds_` tokens (no inline `.system(size:)`)
- [ ] All padding uses `Spacing` tokens (no hardcoded values)
- [ ] All corner radii use `CornerRadius` tokens (no hardcoded values)
- [ ] All buttons use `UniversalScaleButtonStyle` with haptic feedback
- [ ] Primary CTA uses the standard gradient button pattern
- [ ] Section headers use `SectionHeader` component
- [ ] Empty states follow the standard pattern (icon + title + subtitle + action)
- [ ] Dividers use standardized padding (52pt with icons, Spacing.md without)
- [ ] Navigation presentation matches the flow type (push, sheet, or fullScreenCover)
- [ ] Tested in both light and dark mode
- [ ] Tested with Dynamic Type (accessibility)

---

*This document is the law. When in doubt, match the Dashboard — it's the most polished screen and the north star for the rest of the app.*
