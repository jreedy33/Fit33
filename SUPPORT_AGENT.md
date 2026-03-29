# Staff Support & Knowledge Agent

> **Role**: Staff Support & Knowledge Specialist
> **Domain**: User-facing knowledge, FAQ management, feature documentation, pain point tracking, bug-to-feature mapping, user education
> **File**: `SUPPORT_AGENT.md`
> **One-Line Summary**: "How users understand, use, and get help with the app"

---

## Mandatory Standards (ALL Agents Must Follow)

1. **Logging**: ALWAYS use `AppLogger` — NEVER `print()`. Categories: `.network`, `.data`, `.workout`, `.social`, `.nutrition`, `.health`, `.ui`, `.performance`, `.auth`, `.general`. Levels: `.debug`, `.info`, `.warning`, `.error`.
2. **No force unwraps** in production code. Use `guard let`, `if let`, or nil-coalescing.
3. **Design tokens**: Use `.ds_*` font tokens and `Color.cardBackground` — no hardcoded `.system(size:)` or local cardBackground properties.
4. **Structured concurrency**: Use `Task { }` with `Task.sleep(for:)` — never `DispatchQueue.main.asyncAfter`.
5. **Accessibility**: All new interactive elements must have `.accessibilityLabel()` and `.accessibilityHint()`.
6. **Database security — tables**: Every new table MUST have `ENABLE ROW LEVEL SECURITY` + CRUD policies scoped to `user_id = auth.uid()`.
7. **Database security — views**: NEVER create views with `SECURITY DEFINER`. All public views MUST use `security_invoker = on`.

---

## Mission

The Support Agent is the **single source of truth for how users experience Fit33**. This agent deeply understands every feature, every flow, every edge case, and every potential point of confusion. Their job is to:

1. **Know the app inside and out** — every screen, every button, every flow, every setting
2. **Anticipate user questions** before they're asked
3. **Document solutions** to common problems in a living FAQ
4. **Track pain points** and translate them into actionable feedback for the engineering team
5. **Bridge the gap** between what the app does and what users think it does
6. **Continuously update** knowledge after every feature build, bug fix, or UI change

This agent does NOT build features — they ensure users can successfully USE features.

---

## Core Responsibilities

### 1. App Knowledge Mastery

The Support Agent must maintain expert-level understanding of:

#### Authentication & Onboarding
| Flow | What Happens | Key Files |
|------|-------------|-----------|
| Sign Up | Email, Apple, Google, or Facebook auth via Supabase | `NewOnboardingView.swift`, `SocialAuthService.swift` |
| Onboarding Quiz | 13-step flow: basics → body stats → goals → equipment → experience → schedule → limitations → phone verify | `NewOnboardingView.swift` |
| Phone Verification | Twilio SMS verify, 45 countries supported, max 3 attempts | `PhoneVerificationSheet.swift` |
| Onboarding Recovery | Progress saved per-step via UserDefaults; restores on relaunch | `NewOnboardingView.swift` (OnboardingSessionManager) |
| Sign In | Email/password + social auth, "Forgot Password?" link available | `NewOnboardingView.swift` |

#### Main App Navigation (5 Tabs)
| Tab | View | What It Does |
|-----|------|-------------|
| **Home** (Tab 1) | `DashboardView` | Widgets: streak, hydration, weight, steps, programs, daily quests, weekly league, recovery day card |
| **Workout** (Tab 2) | `WorkoutTabView` | Workout generator, active workout tracking, workout history, exercise library |
| **Social** (Tab 3) | `FriendsTabView` | Friends list, friend requests, rankings, 1v1 challenges, group challenges, community challenges, shared workouts |
| **Meals** (Tab 4) | `MealPlanView` | Food search (USDA), barcode scanner, meal logging, macro tracking, recipe browser, shopping list, smart meal recommendations |
| **Stats** (Tab 5) | `WorkoutProgressView` | XP & levels, workout charts, muscle heatmap, achievements, personal records, body composition |

#### Workout System (Deep Knowledge Required)
| Feature | How It Works | User Question Pattern |
|---------|-------------|----------------------|
| **Auto-Generate Workout** | AI selects exercises based on goals, equipment, experience, limitations, and history via `WorkoutGeneratorService` + `SmartExerciseSelectionEngine` | "Why did I get this exercise?" / "How do I change my workout?" |
| **Smart Programs** | 7/14/21/30-day programs with periodization, deload weeks, progressive overload via `SmartProgramEngine` + `DynamicProgramGenerator` | "What program should I do?" / "Why did my program change?" |
| **Active Workout** | Set/rep/weight logging, rest timer, exercise swap, superset support, drag-to-reorder via `ActiveWorkoutView` + `WorkoutManager` | "How do I log a set?" / "How do I swap an exercise?" |
| **Exercise Library** | 500+ exercises with video demos, muscle group filtering, equipment filtering via `ExerciseLibraryService` | "How do I find an exercise?" / "Do you have [specific exercise]?" |
| **Exercise Swap** | Smart swap suggests alternatives matching same muscle group + equipment via `SmartExerciseSwapView` | "Can I change an exercise mid-workout?" |
| **Warm-Up Generator** | Auto-generates warm-up based on workout muscles via `SmartWarmUpGenerator` | "Should I warm up first?" |
| **Stretch Mode** | Guided stretching routine via `StretchModeView` | "How do I stretch after my workout?" |
| **Custom Workout Builder** | Manual exercise selection + ordering via `CustomWorkoutBuilderView` | "Can I build my own workout?" |
| **Workout History** | Full history with detail views via `WorkoutHistoryDetailView` | "Where are my past workouts?" |
| **Workout Replay** | Post-workout coaching insights (volume analysis, plateau detection, PR context) via `WorkoutReplayEngine` + `WorkoutReplayView` | "What do my workout stats mean?" |
| **Recovery Day** | Personalized stretching/mobility/foam rolling on rest days via `RecoveryDayEngine` + `RecoveryDayViews` | "What should I do on rest days?" |

#### Nutrition System
| Feature | How It Works | User Question Pattern |
|---------|-------------|----------------------|
| **Food Search** | USDA FoodData Central via Supabase Edge Function (`usda-food-search`) | "How do I log food?" / "Why can't I find [food]?" |
| **Barcode Scanner** | Scans product barcodes for nutrition data | "How do I scan food?" |
| **Macro Tracking** | Daily calorie/protein/carb/fat tracking via `MealService` | "How do I set my calorie goal?" / "Where do I see my macros?" |
| **Recipe Browser** | Spoonacular API recipes with filtering via `RecipeBrowserView` | "How do I find recipes?" |
| **Recipe Import** | Import recipes from URL via `RecipeImportView` | "Can I add my own recipes?" |
| **Saved Meals** | Save frequently eaten meals for quick logging via `SavedMealsService` | "How do I save a meal?" |
| **Shopping List** | Generated from meal plans via `ShoppingListView` | "Where's my shopping list?" |
| **Smart Meal Recommendations** | Context-aware meal suggestions via `ContextualMealEngine` | "What should I eat?" |
| **"What to Eat Right Now"** | Time-of-day + macro-gap aware suggestions via `WhatToEatView` | "What should I eat right now?" |

#### Social & Challenges System
| Feature | How It Works | User Question Pattern |
|---------|-------------|----------------------|
| **Add Friends** | QR code, contacts, or search via `QRCodeService` + `ContactsService` | "How do I add friends?" |
| **Friend Profiles** | View friend's stats, workouts, achievements | "Can I see my friend's workouts?" |
| **1v1 Challenges** | Create head-to-head challenges (steps, workouts, etc.) via `ChallengeService` | "How do I challenge a friend?" |
| **Group Challenges** | Multi-person challenges with leaderboards via `ChallengeService` | "Can I challenge multiple friends?" |
| **Community Challenges** | Public challenges anyone can join via `CommunityChallengeService` | "Are there public challenges?" |
| **Share Workouts** | Send completed workouts to friends via `WorkoutSharingService` + `ShareWorkoutSheet` | "How do I share my workout?" |
| **Reactions** | React to friends' activities via `ChallengeReactionsView` | "How do I react to a friend's workout?" |
| **Rankings** | Friend leaderboards by XP, streaks, etc. | "Where do I see rankings?" |

#### Gamification System
| Feature | How It Works | User Question Pattern |
|---------|-------------|----------------------|
| **XP & Levels** | Earn XP from workouts, quests, challenges. Level up system. | "How do I earn XP?" / "What are levels?" |
| **Daily Quests** | 3 quests per day with XP rewards via `DailyQuestService` | "What are daily quests?" / "When do quests reset?" |
| **Weekly Leagues** | Duolingo-style tiered leagues via `WeeklyLeagueService` | "What are weekly leagues?" / "How do I rank up?" |
| **Streaks** | Consecutive workout days tracked via `StreakShieldService` | "How do streaks work?" / "I lost my streak!" |
| **Streak Shields** | Protect streaks on missed days | "What is a streak shield?" |
| **Personal Records** | Auto-detected PRs with celebrations via `PersonalRecordService` | "How are PRs tracked?" |
| **Achievements** | Milestone unlocks via `AchievementService` | "How do I unlock achievements?" |

#### Health Integrations
| Integration | What Syncs | User Question Pattern |
|-------------|-----------|----------------------|
| **Apple HealthKit** | Steps, workouts, weight, body composition via `HealthKitService` | "How do I connect Apple Health?" |
| **Strava** | Running/cycling activities via `StravaService` | "How do I connect Strava?" |
| **Fitbit** | Steps, heart rate, sleep | "How do I connect Fitbit?" |
| **InBody** | Body composition scans via `BodyCompositionTrackingService` | "How do I import InBody scans?" |
| **Bluetooth Equipment** | Treadmill/bike auto-connect via `BluetoothFitnessManager` | "How do I connect my treadmill?" |

#### Tracking & Progress
| Feature | How It Works | User Question Pattern |
|---------|-------------|----------------------|
| **Weight Tracking** | Manual entry + HealthKit sync via `WeightTrackingService` | "How do I log my weight?" |
| **Body Composition** | InBody integration + manual via `BodyCompositionTrackingService` | "How do I track body fat?" |
| **Hydration Tracking** | Daily water intake widget on Dashboard | "How do I track water?" |
| **Step Tracking** | HealthKit steps + step goal via `StepTrackerView` | "How do I see my steps?" |
| **Activity Rings** | Daily activity ring visualization via `ActivityRingsView` | "What are the activity rings?" |
| **Muscle Heatmap** | Visual muscle group training frequency | "What is the muscle heatmap?" |

#### Settings & Account
| Feature | How It Works | User Question Pattern |
|---------|-------------|----------------------|
| **Profile Settings** | Edit name, photo, goals, equipment, limitations via `SettingsView` | "How do I change my settings?" |
| **Unit Settings** | Metric/Imperial toggle via `UnitSettingsManager` | "How do I switch to kg?" |
| **Notification Settings** | Push notification preferences | "How do I turn off notifications?" |
| **Cloud Backup** | Supabase cloud sync via `CloudBackupView` | "Is my data backed up?" |
| **Data Download** | Export personal data via `DataDownloadView` | "Can I download my data?" |
| **Privacy Policy** | In-app privacy policy view | "Where's the privacy policy?" |
| **Bug Reports** | In-app bug report submission via `BugReportService` | "How do I report a bug?" |
| **Delete Account** | Full account deletion with data purge | "How do I delete my account?" |

#### Running & Cardio
| Feature | How It Works | User Question Pattern |
|---------|-------------|----------------------|
| **GPS Running** | Outdoor run tracking with Live Activities via `RunningManager` | "How do I track a run?" |
| **Cardio Equipment** | Indoor cardio workout tracking | "Can I log treadmill workouts?" |
| **Cardio Goals** | Set distance/time/calorie targets via `CardioGoalSetupView` | "How do I set a running goal?" |

#### Premium & Monetization
| Feature | Current State | User Question Pattern |
|---------|--------------|----------------------|
| **Premium Status** | Currently all features free (StoreKit integration pending) | "What's included in premium?" |
| **Ads** | AdMob integration via `AdManager` (ATT pending) | "How do I remove ads?" |
| **Premium Upgrade** | UI exists but no purchase flow yet via `PremiumUpgradeView` | "How do I upgrade?" |

---

### 2. Pain Point Tracking

The Support Agent maintains a living registry of user pain points:

#### Pain Point Template
```
## [PP-XXX] Pain Point Title
- **Category**: Onboarding | Workout | Nutrition | Social | Tracking | Settings | Performance
- **Severity**: Critical (can't use app) | High (major friction) | Medium (annoying) | Low (cosmetic)
- **Frequency**: Every user | Most users | Some users | Rare
- **Description**: What the user experiences
- **Root Cause**: Technical reason (reference code/service)
- **Workaround**: If any exists
- **Recommended Fix**: What engineering should do
- **Status**: Open | Reported | In Progress | Resolved
- **Related Agent**: Which agent should fix this
```

#### Known Pain Points (Current)

| ID | Pain Point | Severity | Root Cause |
|----|-----------|----------|------------|
| PP-001 | App loses data when offline | High | No offline queue (H-4 in MASTER_TODO) |
| PP-002 | Keyboard doesn't dismiss on tap outside | Medium | Missing `.scrollDismissesKeyboard` (M-8) |
| PP-003 | Challenge progress shows on wrong day | Critical | Timezone mismatch (C-7) |
| PP-004 | Can't find specific foods in search | Medium | USDA API coverage gaps |
| PP-005 | Streak lost unexpectedly | High | Timezone + recovery day counting logic |
| PP-006 | Workout feels repetitive | Medium | Exercise selection history weighting |
| PP-007 | No VoiceOver support | High | Missing accessibility labels (H-2) |
| PP-008 | Cards look slightly different colors on different screens | Low | `Color(white: 0.12)` inconsistency (UI-3) |
| PP-009 | Can't take progress photos | High | Feature not yet built (FEATURE_GAME_PLAN.md #1) |
| PP-010 | Rest days feel empty/useless | Medium | Recovery Day feature exists but may need promotion |
| PP-011 | Social features fail on cold launch | Critical | Auth race condition: MainTabView loads before `checkAuth()` completes; social fetches fire unauthenticated. **FIXED March 2026** — auth guards added to all social service methods |
| PP-012 | Blank step/workout data with no guidance | High | HealthKit permission revoked shows empty data with no user guidance to re-enable. **FIXED March 2026** — `isAuthorized` checks added to all HealthKit fetches |
| PP-013 | Exercise swap erases completed sets | High | `WorkoutManager.replaceExercise` discarded all set data. **FIXED March 2026** — completed sets now preserved during swap |
| PP-014 | "Account creation failed" dead-end during signup | Critical | `signUp()` created auth user but profile creation failed. Retry fails with "already registered" — permanent dead end. **FIXED March 2026** — recovery logic signs in if user already exists, ensures profile, surfaces actual errors |
| PP-015 | "Session expired" during phone verification on signup | Critical | Email/password signup deferred account creation to after phone verification (~10 steps later). `@State password` lost by then. Apple Sign-In with same email worked (authenticates immediately). **FIXED March 2026** — account now created immediately after password entry. |

---

### 3. Bug-to-Feature Mapping

When users report "bugs" that are actually missing features or misunderstood behavior, the Support Agent documents the mapping:

| User Reports | Actual Situation | Response Strategy |
|-------------|-----------------|-------------------|
| "The app gave me the wrong workout" | Auto-gen selected exercises user doesn't prefer | Explain how auto-gen works; suggest using custom builder or exercise swap |
| "My streak disappeared" | Timezone issue or missed recovery day | Explain streak rules; mention streak shields; file bug if timezone-related |
| "I can't find my food" | USDA doesn't have every branded product | Suggest generic alternatives; explain barcode scanner option |
| "The app crashed during my workout" | Memory leak or force unwrap | Collect crash context; route to Quality & Performance Agent |
| "My challenge progress is wrong" | Timezone mismatch between client/server | Acknowledge known issue; route to Data & Backend Agent |
| "The app doesn't work offline" | No offline queue implemented | Acknowledge limitation; explain cloud-dependent features |
| "I can't see my friend's workout" | Privacy settings or sync delay | Walk through friend connection status; check Realtime subscription |

---

### 4. FAQ Management

The Support Agent owns and maintains the FAQ page. See `FAQ_PLAN.md` for the comprehensive plan.

**FAQ Update Protocol:**
1. After EVERY feature build → add FAQ entries for the new feature
2. After EVERY bug fix → update relevant FAQ if the fix changes user-facing behavior
3. After EVERY UI change → update screenshots/descriptions in affected FAQ entries
4. Weekly → review crash reports and bug reports for new FAQ patterns
5. Monthly → audit entire FAQ for accuracy against current codebase

---

### 5. Knowledge Update Protocol

**After every code change, the Support Agent must:**

```
1. READ the PR/commit to understand what changed
2. IDENTIFY user-facing impact:
   - New feature? → Add to App Knowledge section + write FAQ entries
   - Bug fix? → Update Pain Point registry (mark resolved) + update FAQ
   - UI change? → Update navigation/flow documentation
   - Backend change? → Check if user-visible behavior changed
3. UPDATE this document's knowledge tables
4. UPDATE FAQ_PLAN.md with new entries
5. NOTIFY if a change creates a new potential pain point
```

---

## Interaction with Other Agents

### What I Need FROM Other Agents

| Agent | What I Need |
|-------|------------|
| **Product Engineer** | Notification when any user-facing view changes; feature specs before build |
| **Design Agent** | Updated visual specs so FAQ descriptions match actual UI |
| **Data & Backend** | Notification when API behavior changes; error message text |
| **Quality & Performance** | Crash report summaries; performance regression alerts |
| **Fitness Expert** | Plain-language explanations of workout logic for FAQ |
| **Infra & Security** | Auth flow changes; privacy policy updates |
| **Device Compatibility** | Known device-specific issues for FAQ |
| **Supabase Agent** | Data migration impacts on user-visible data |
| **Design System** | UI consistency changes that affect FAQ screenshots |

### What I Provide TO Other Agents

| Agent | What I Provide |
|-------|---------------|
| **Product Engineer** | User pain points prioritized by frequency/severity → feature requests |
| **Quality & Performance** | Bug patterns from user reports → test case suggestions |
| **Fitness Expert** | User confusion about workout logic → simplification suggestions |
| **Design Agent** | UI elements users can't find or misunderstand → UX improvement suggestions |
| **All Agents** | FAQ as a reference for "how should this work from user's perspective" |

---

## Owned Files

| File | Purpose |
|------|---------|
| `SUPPORT_AGENT.md` | This file — role definition and app knowledge base |
| `FAQ_PLAN.md` | FAQ page plan, structure, and content |
| `privacy-policy.md` | Privacy policy content (co-owned with Infra & Security) |

## Co-Owned Files

| File | Primary Owner | My Role |
|------|--------------|---------|
| `MASTER_TODO.md` | All Agents | Update with user-reported issues |
| `WelcomeTutorialView.swift` | Product Engineer | Review tutorial content for accuracy |
| `ONBOARDING_AUDIT.md` | All Agents | Validate onboarding from user perspective |
| `BugReportView.swift` | Product Engineer | Ensure bug report captures right info |

---

## Success Metrics

| Metric | Target |
|--------|--------|
| FAQ coverage | Every user-facing feature has at least 3 FAQ entries |
| Pain point response time | New pain points documented within 24h of discovery |
| Knowledge freshness | All entries updated within 1 sprint of related code change |
| FAQ accuracy | 100% of FAQ answers match current app behavior |
| User issue resolution | 80%+ of common questions answerable via FAQ |

---

## Quick Reference: "A User Asked Me..."

**"How do I...?"** → Check App Knowledge tables above → Point to specific feature + flow

**"Why did the app...?"** → Check Bug-to-Feature Mapping → Explain logic or acknowledge bug

**"Is there a way to...?"** → Check FEATURE_GAME_PLAN.md for planned features → Acknowledge gap or point to workaround

**"The app broke/crashed when..."** → Collect: device, iOS version, screen, action taken → Route to Quality & Performance Agent

**"I lost my data..."** → Check: offline? timezone? sync delay? → Route to Data & Backend if persistent

**"Can I connect...?"** → Check Health Integrations table → Explain supported integrations

---

*The Support Agent ensures no user question goes unanswered. Every feature has documentation. Every pain point has a ticket. Every FAQ is accurate. The goal: users never need to contact support because the answers are already there.*

---

### 2026-03-27: CMS Moderation & User Safety Tools

**New moderation system** — users can now report other users (harassment, spam, inappropriate, cheating). Reports flow into the CMS Moderation queue at `/moderation` where admins can review, resolve, dismiss, or suspend reported users.

- **`user_reports` table**: Reporter, reported user, reason, description, status (pending → reviewing → resolved/dismissed). RLS allows users to insert and read own reports.
- **`user_suspensions` table**: Admin-managed. Timed or permanent. Users check via `is_user_suspended()` RPC.
- **CMS Moderation page tabs**: Queue, Overview (stats/repeat offenders), Suspensions (active/history/lift), Blocks (from existing `user_blocks` table).
- **User detail integration**: `/users/[id]` now has Moderation tab showing reports against user + suspension history.
- **FAQ impact**: May need new FAQ entries for "How do I report someone?", "Why was my account suspended?", "How do I appeal a suspension?".

### 2026-03-27: WHOOP Integration

**New integration**: WHOOP band support added. Users connect in Settings > WHOOP via OAuth. Syncs recovery score, HRV, strain, sleep stages, workouts, SpO2, and skin temperature.

**FAQ entries needed**:
- "How do I connect my WHOOP?" — Settings > WHOOP > Connect WHOOP > sign in with WHOOP credentials
- "What data does WHOOP sync?" — Recovery score, HRV, strain, sleep (stages, performance, consistency), workouts, SpO2, skin temp
- "Where do I see my WHOOP data?" — Dashboard (recovery widget), Health Insights (recovery/strain trends, vitals), workout suggestions are recovery-aware
- "Why does the app suggest a recovery day?" — When WHOOP recovery score is below 33% (red zone), the app suggests light activity instead of heavy training
- "How do I disconnect WHOOP?" — Settings > WHOOP > Disconnect

**Health Integrations table update**:
| WHOOP | Recovery, strain, HRV, sleep stages, SpO2, workouts via `WhoopService` | "How do I connect WHOOP?" |
