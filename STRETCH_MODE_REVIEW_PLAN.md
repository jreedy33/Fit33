# Stretch Mode Feature Review & Improvement Plan

## Multi-Agent Comprehensive Review

**Date**: March 24, 2026
**Scope**: Full review of `StretchModeView.swift` (779 lines) + integration points
**Status**: Review complete — no code changes made

---

## 1. Current State Summary

### What Exists
- **StretchModeView.swift**: Single file containing all stretch UI (splash, timer, video, area cards)
- **Presentation**: `.sheet()` modal from `WorkoutTabView` (line 544)
- **Flow**: Splash (area selection) → Active timer (circular video + countdown)
- **Data Source**: Supabase `exercises` table filtered by `workoutType`, `category`, or `name` containing "stretch"
- **Video**: Cloudflare R2 CDN, looped via `AVQueuePlayer` + `AVPlayerLooper`, clipped to circle
- **Muscle Mapping**: String-based keyword matching against 8 body area categories

### What Works Well
- Circular video player with clip mask and progress ring is visually strong
- AVPlayerLooper for seamless video looping (no gaps)
- Breathing glow animation adds polish
- Progress dots for multi-stretch queue
- Duration selector (30/60/90/120s) is intuitive
- Auto-advance on timer completion

---

## 2. Identified Gaps & Issues

### 2.1 Presentation: Sheet Instead of Full Screen (CRITICAL)

**Problem**: Stretch mode is presented as a `.sheet()` — a draggable card that can be dismissed with a swipe. Every other immersive experience in the app uses either `fullScreenCover` or a ZStack overlay (like `ActiveWorkoutView` which uses `.zIndex(10)`).

**Impact**: Users can accidentally dismiss mid-stretch. Inconsistent with the app's pattern for "active" experiences.

**Agent Owner**: PRODUCT_ENGINEER_AGENT

**Recommendation**: Convert to `fullScreenCover` or a ZStack overlay matching the `ActiveWorkoutView` pattern. The active workout overlay approach is ideal because:
- No swipe-to-dismiss risk
- Consistent with how the app handles "in-progress" sessions
- Allows the workout tab to remain in its navigation state underneath

---

### 2.2 Visual Inconsistency: Background (HIGH)

**Problem**: StretchModeView uses a fully custom hardcoded `LinearGradient` with raw RGB values:
```swift
// Line 193-199
Color(red: 0.05, green: 0.1, blue: 0.15)
Color(red: 0.1, green: 0.15, blue: 0.2)
Color(red: 0.05, green: 0.12, blue: 0.18)
```

The app's design system provides `AnimatedOrbBackground` with tab-specific variants (e.g., `AnimatedOrbBackground.workout(colorScheme:)`), used by `CardioLandingView`. The `ActiveWorkoutView` also uses a hardcoded gradient but at least shares the same color family.

**Agent Owner**: DESIGN_AGENT + DESIGN_SYSTEM_AGENT

**Recommendation**: Replace with `AnimatedOrbBackground` variant (e.g., a `.stretch` or `.recovery` variant with calming teal/mint tones). This provides:
- Animated orbs for visual depth
- Automatic dark/light mode support
- Consistency with other sections

---

### 2.3 Visual Inconsistency: Typography Tokens (HIGH)

**Problem**: StretchModeView hardcodes all fonts instead of using design tokens:

| Current (Hardcoded) | Should Be (Token) |
|---|---|
| `.font(.system(size: 56, weight: .bold, design: .rounded))` | `.font(.ds_displayLarge)` or new `.ds_timer` token |
| `.font(.caption)` | `.font(.ds_labelSmall)` or `.ds_caption` |
| `.font(.caption2)` | `.font(.ds_caption)` |
| `.font(.title3)` | `.font(.ds_heading2)` |
| `.font(.subheadline)` | `.font(.ds_bodyMedium)` |
| `.font(.headline)` | `.font(.ds_heading3)` |

**Exception**: `StretchSplashView` correctly uses `.font(.ds_displayMedium)` on line 633 — proving the developer knows about the tokens but didn't apply them consistently.

**Agent Owner**: DESIGN_SYSTEM_AGENT

---

### 2.4 Visual Inconsistency: Spacing & Corner Radius (MEDIUM)

**Problem**: Most spacing values are hardcoded magic numbers:
- `spacing: 12`, `spacing: 8`, `spacing: 32`, `spacing: 40`
- `.padding(.horizontal, 20)`, `.padding(.bottom, 50)`, `.padding(.vertical, 18)`
- `.frame(height: 24)`

**Should use**: `Spacing.sm` (12), `Spacing.xs` (8), `Spacing.xl` (32), `Spacing.lg` (24), etc.

**Agent Owner**: DESIGN_SYSTEM_AGENT

---

### 2.5 Muscle Mapping Accuracy (HIGH)

**Problem**: The muscle matching uses loose keyword-based string matching against concatenated text (`name + category + primaryMuscles + secondaryMuscles`). Several issues:

1. **"Upper Body" overlaps with "Back", "Shoulders"**: Keywords like `"back"`, `"shoulder"`, `"lat"`, `"delt"`, `"trapezius"` appear in Upper Body AND in Back/Shoulders categories, causing the same stretches to appear in multiple areas.

2. **"Lower Body" overlaps with "Hips" and "Legs"**: Keywords like `"hip"`, `"glute"`, `"thigh"` overlap between Lower Body and Hips. The Legs category explicitly excludes hips (`!allText.contains("hip")`), but Lower Body does not.

3. **False positives from name matching**: Concatenating all text means a stretch named "Back Stretch" with primary muscle "Hamstrings" would match BOTH "Back" and "Lower Body" areas because `"back"` is in the name.

4. **Keyword "upper" and "lower" are too broad**: "upper" matches Upper Body, "lower" matches Lower Body — but "upper abs" is a core exercise, and "lower back" is a back exercise.

5. **No neck stretches likely exist**: The filter looks for "sternocleidomastoid" and "levator scapulae" — highly specific medical terms unlikely to appear in exercise names or muscle fields.

6. **The `exerciseFamily` field is not used**: The ExerciseDTO has an `exerciseFamily` field (e.g., "back_stretch", "stretch_hip", "stretch_shoulder") that would provide much more accurate matching than keyword search.

**Agent Owner**: FITNESS_EXPERT_AGENT + DATA_BACKEND_AGENT

**Recommendations**:
- Use `exerciseFamily` field for primary categorization
- Match against `primaryMusclesArray` separately from `name` to avoid false positives
- Create explicit muscle-to-area mapping table instead of keyword lists
- Add priority/exclusion logic so a "Hip Stretch" doesn't show in "Lower Body" AND "Hips"

---

### 2.6 No Local Stretch Data Fallback (MEDIUM)

**Problem**: Stretches are fetched exclusively from Supabase via `fetchAllExercisesRaw()`. The local `exercises.json` (446 exercises) contains ZERO stretch exercises — `workoutType` field doesn't even exist in the JSON schema. If the network call fails, the user gets an empty stretch queue with only an error log.

**Agent Owner**: DATA_BACKEND_AGENT + QUALITY_PERFORMANCE_AGENT

**Recommendation**:
- Add stretch exercises to the local `exercises.json` as offline fallback
- Show a user-visible error message when fetches fail (currently only logs with `AppLogger.error`)
- Consider caching last-fetched stretches for offline use

---

### 2.7 `isLoadingVideo` Set Prematurely (BUG)

**Problem** (line 556): `isLoadingVideo = false` is set immediately after calling `setupPlayer(with:)`, before the video has actually loaded. The video is still buffering from the CDN when the loading spinner disappears.

```swift
// Line 536-557
private func loadCurrentStretch() {
    isLoadingVideo = true
    // ...
    setupPlayer(with: url)  // Async network fetch starts
    isLoadingVideo = false   // ← Immediately false, video still buffering
}
```

**Agent Owner**: QUALITY_PERFORMANCE_AGENT

**Recommendation**: Observe `AVPlayerItem.status` or use `AVPlayer.timeControlStatus` to detect when the video is actually ready to play, then set `isLoadingVideo = false`.

---

### 2.8 Timer Uses Legacy `Timer.scheduledTimer` (MEDIUM)

**Problem** (line 374): Uses `Timer.scheduledTimer` callback pattern instead of structured concurrency. The QUALITY_PERFORMANCE_AGENT has flagged 60+ `asyncAfter` instances app-wide for replacement.

**Agent Owner**: QUALITY_PERFORMANCE_AGENT

**Recommendation**: Replace with `Task { }` and `Task.sleep(for:)` pattern, or use SwiftUI's `TimelineView` for timer display.

---

### 2.9 No Accessibility Support (HIGH)

**Problem**: Zero `accessibilityLabel` or `accessibilityHint` modifiers anywhere in the 779-line file. This violates the mandatory standard shared by ALL agents.

Missing accessibility:
- Play/Pause button
- Previous/Next buttons
- Duration selection buttons
- Area selection cards
- Timer display
- Progress dots
- Close/back buttons

**Agent Owner**: QUALITY_PERFORMANCE_AGENT + DEVICE_COMPATIBILITY_AGENT

---

### 2.10 No Haptic Feedback (LOW)

**Problem**: The stretch mode has no haptic feedback on any interaction (play/pause, next/prev, area selection, timer complete). The rest of the app uses `HapticManager` extensively.

**Agent Owner**: DESIGN_AGENT + PRODUCT_ENGINEER_AGENT

**Recommendation**: Add haptics for:
- Area card selection: `.selection`
- Start stretching: `.impact(.medium)`
- Play/Pause: `.impact(.light)`
- Next/Previous stretch: `.impact(.light)`
- Timer complete / auto-advance: `.notification(.success)`

---

### 2.11 No Completion State (MEDIUM)

**Problem**: When all stretches complete, the timer loops back to the first stretch silently (line 382-384). There's no completion screen, summary, or celebration. The active workout has a full completion flow with stats.

**Agent Owner**: PRODUCT_ENGINEER_AGENT + SUPPORT_AGENT

**Recommendation**: Add a completion overlay showing:
- Number of stretches completed
- Total time stretched
- "Great stretch session!" message
- Option to restart or dismiss
- XP/streak credit (per FEATURE_GAME_PLAN.md recovery day integration)

---

### 2.12 No Gender-Aware Video Selection (LOW)

**Problem**: The video URLs include gender variants (e.g., `(male)` / `(female)` in filename), but StretchModeView doesn't filter by the user's gender preference. It takes whatever `videoFilename` comes back from the database.

**Agent Owner**: DATA_BACKEND_AGENT

**Recommendation**: Filter based on user's profile gender setting, with fallback to either gender if preferred isn't available.

---

### 2.13 Fetches ALL Exercises Then Filters Client-Side (PERFORMANCE)

**Problem** (line 426): `fetchAllExercisesRaw()` fetches the ENTIRE exercises table (potentially 1000+ rows paginated in batches of 1000) just to filter down to 5-8 stretches. This is wasteful for bandwidth, memory, and battery.

**Agent Owner**: DATA_BACKEND_AGENT + SUPABASE_AGENT

**Recommendation**: Create a Supabase RPC function or filtered query:
```sql
SELECT * FROM exercises
WHERE workout_type = 'Stretch'
AND video_filename IS NOT NULL
AND primary_muscles && ARRAY['target_muscles']
ORDER BY RANDOM()
LIMIT 8;
```

---

## 3. Agent Task Assignments

### PRODUCT_ENGINEER_AGENT
| # | Task | Priority | Effort |
|---|------|----------|--------|
| 1 | Convert `.sheet()` to `fullScreenCover` or ZStack overlay pattern | Critical | Small |
| 2 | Add stretch completion screen with summary stats | Medium | Medium |
| 3 | Wire up haptic feedback via `HapticManager` | Low | Small |
| 4 | Ensure dismiss cleanup matches ActiveWorkoutView patterns | Medium | Small |

### DESIGN_AGENT
| # | Task | Priority | Effort |
|---|------|----------|--------|
| 1 | Define `AnimatedOrbBackground.stretch` or `.recovery` variant spec | High | Small |
| 2 | Specify completion screen visual design | Medium | Small |
| 3 | Define haptic feedback spec for stretch interactions | Low | Small |
| 4 | Review and approve active timer screen visual elements (circle, ring, glow) — these are good, ensure they remain | Info | — |

### DESIGN_SYSTEM_AGENT
| # | Task | Priority | Effort |
|---|------|----------|--------|
| 1 | Replace all hardcoded fonts with `ds_*` tokens (12 violations) | High | Small |
| 2 | Replace all hardcoded spacing with `Spacing.*` tokens (~15 violations) | Medium | Small |
| 3 | Replace hardcoded colors with semantic color tokens where applicable | Medium | Small |
| 4 | Consider adding `ds_timer` token for large countdown display | Low | Small |

### FITNESS_EXPERT_AGENT
| # | Task | Priority | Effort |
|---|------|----------|--------|
| 1 | Validate and fix muscle-to-area mapping (eliminate overlaps) | High | Medium |
| 2 | Define correct stretch-muscle associations for each of 8 areas | High | Medium |
| 3 | Recommend stretch order within a session (e.g., large-to-small muscle groups) | Medium | Small |
| 4 | Validate 30/60/90/120s durations against exercise science guidelines | Low | Small |

### DATA_BACKEND_AGENT
| # | Task | Priority | Effort |
|---|------|----------|--------|
| 1 | Create server-side filtered query for stretches (replace `fetchAllExercisesRaw`) | High | Medium |
| 2 | Use `exerciseFamily` field for area categorization | High | Small |
| 3 | Add stretch exercises to local `exercises.json` as offline fallback | Medium | Medium |
| 4 | Filter video by user gender preference | Low | Small |

### SUPABASE_AGENT
| # | Task | Priority | Effort |
|---|------|----------|--------|
| 1 | Create `fetch_stretches_for_area` RPC function | High | Medium |
| 2 | Verify all stretch exercises have correct `workout_type`, `primary_muscles`, `exercise_family` | High | Medium |
| 3 | Add index on `workout_type` + `video_filename` for stretch queries | Low | Small |

### QUALITY_PERFORMANCE_AGENT
| # | Task | Priority | Effort |
|---|------|----------|--------|
| 1 | Fix `isLoadingVideo` bug — observe `AVPlayerItem.status` for ready state | High | Small |
| 2 | Replace `Timer.scheduledTimer` with structured concurrency | Medium | Small |
| 3 | Add comprehensive accessibility labels to all interactive elements | High | Medium |
| 4 | Add error state UI when stretch fetch fails (not just log) | Medium | Small |

### DEVICE_COMPATIBILITY_AGENT
| # | Task | Priority | Effort |
|---|------|----------|--------|
| 1 | Audit `circleSize = 280` — may overflow on iPhone SE (320pt width) | High | Small |
| 2 | Test area selection grid on iPad (currently 2-column, may need 3-4) | Medium | Small |
| 3 | Verify safe area handling with `.ignoresSafeArea()` on background | Medium | Small |

### INFRA_SECURITY_AGENT
| # | Task | Priority | Effort |
|---|------|----------|--------|
| 1 | Verify R2 CDN URL is not hardcoded (should be in config/secrets) | Low | Small |

### SUPPORT_AGENT
| # | Task | Priority | Effort |
|---|------|----------|--------|
| 1 | Update FAQ: "How do I stretch after my workout?" with improved flow | Low | Small |
| 2 | Track user pain points: accidental sheet dismissal, empty stretch results | Medium | Small |
| 3 | Document the new completion screen in knowledge base | Low | Small |

---

## 4. User Experience Flow (Current vs. Improved)

### Current Flow
```
Workout Tab → Tap "Stretch" button
  → Sheet slides up (can swipe down to dismiss)
    → Splash: Select area from 8 cards
    → Tap "Start Stretching"
    → Loading spinner (fetches ALL exercises from Supabase)
    → Active timer: circle video + countdown
    → Timer hits 0 → auto-advance to next stretch
    → After last stretch → silently loops to first
    → X button to dismiss sheet
```

### Improved Flow
```
Workout Tab → Tap "Stretch" button
  → Full-screen cover (no accidental dismiss)
    → Splash: Select area from 8 cards
      - Cards use exerciseFamily-based accurate muscle mapping
      - Haptic feedback on selection
    → Tap "Start Stretching"
      - Haptic: medium impact
    → Loading (server-side filtered query, fast)
      - Fallback to cached/local data if offline
    → Active timer: circle video + countdown (UNCHANGED — this is good)
      - Video loading spinner shows until video actually ready
      - Accessibility labels on all controls
      - Haptic on play/pause, next/prev
      - Background uses AnimatedOrbBackground.stretch variant
      - All fonts use design system tokens
    → Timer hits 0 → haptic notification → auto-advance
    → After last stretch → Completion screen:
      - "Session Complete" with stats
      - Total stretches, total time
      - XP earned (future: recovery day integration)
      - "Done" or "Restart" buttons
    → Dismiss returns to Workout Tab cleanly
```

---

## 5. What to KEEP (Already Good)

These elements of the active stretch timer screen should remain as-is:

1. **Circular video player** with `clipShape(Circle())` — distinctive and visually appealing
2. **Progress ring** with angular gradient (green → mint → teal) — clear visual feedback
3. **Breathing glow animation** — adds calm, meditative feel appropriate for stretching
4. **AVPlayerLooper** for seamless video — technically correct implementation
5. **Progress dots** — clean way to show position in queue
6. **Duration selector** (30/60/90/120s) — intuitive and well-placed
7. **Prev/Next/Play-Pause controls** — familiar media player pattern
8. **Auto-advance on timer complete** — smooth hands-free experience
9. **Muted video by default** — correct for a stretch timer context

---

## 6. Implementation Priority Order

### Phase 1: Critical Fixes (Do First)
1. Change `.sheet()` to full-screen presentation
2. Fix `isLoadingVideo` bug
3. Add error state UI for failed fetches

### Phase 2: Consistency Pass
4. Replace hardcoded fonts with design tokens
5. Replace hardcoded spacing with tokens
6. Switch background to `AnimatedOrbBackground` variant
7. Add accessibility labels

### Phase 3: Data & Logic Improvements
8. Create server-side stretch query (replace `fetchAllExercisesRaw`)
9. Fix muscle mapping using `exerciseFamily` field
10. Add local data fallback

### Phase 4: UX Polish
11. Add completion screen
12. Add haptic feedback
13. Gender-aware video selection
14. Device compatibility audit (SE, iPad)

### Phase 5: Future Integration (per FEATURE_GAME_PLAN.md)
15. Recovery Day integration — stretches count toward daily quests
16. XP reward for completing stretch sessions
17. Streak maintenance credit for stretch sessions on rest days

---

## 7. Estimated Scope

| Phase | Tasks | Estimated Files Changed |
|-------|-------|------------------------|
| Phase 1 | 3 tasks | 2 files (StretchModeView.swift, WorkoutTabView.swift) |
| Phase 2 | 4 tasks | 2 files (StretchModeView.swift, AdaptiveColors.swift) |
| Phase 3 | 3 tasks | 3 files (StretchModeView.swift, SupabaseManager.swift, exercises.json) |
| Phase 4 | 4 tasks | 2 files (StretchModeView.swift, SupabaseDTOs.swift) |
| Phase 5 | 3 tasks | 4+ files (new + existing services) |

---

*This plan was generated by reviewing StretchModeView.swift, WorkoutTabView.swift, DesignSystem.swift, AdaptiveColors.swift, SupabaseDTOs.swift, SupabaseManager.swift, exercises.json, and all 10 agent definition files.*
