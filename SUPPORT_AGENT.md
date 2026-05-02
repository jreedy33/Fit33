# Staff Support & Knowledge Agent

> **Role**: User-facing knowledge, FAQ, pain-point tracking, bug-to-feature mapping, user education. "How users understand, use, and get help with the app."
>
> Full feature inventory, dated FAQ entries, integration copy (WHOOP/Oura/Fitbit/Strava), and historical pain-point registry live in [`docs/history/SUPPORT_AGENT.md`](docs/history/SUPPORT_AGENT.md).

Cross-cutting rules live in `.cursor/rules/codingrules.mdc` (universal). Scoped rules auto-load when editing matching files: `.cursor/rules/swiftui-rules.mdc` (`Fit33/**/*.swift`), `.cursor/rules/supabase-rules.mdc` (`supabase/**/*.sql`), `.cursor/rules/admin-cms-rules.mdc` (`admin-cms/**`).

This agent does NOT build features — it ensures users can successfully USE features.

---

## Invariants (will mislead users / create support tickets if violated)

1. **Scanner is OCR, NOT barcode lookup.** The camera scanner in Meals reads the text on the nutrition-facts panel. Do NOT tell users "scan the barcode" — that feature is not shipped (tracked as Q2-6). User-facing copy must say "nutrition label lookup (photo-based OCR)" everywhere: Terms, Privacy Policy, FAQ, in-app tooltips, Support replies. Correct response to "how do I scan food?" → "Point the camera at the **nutrition facts panel** — we read the text directly. True barcode lookup is coming."
2. **Knowledge MUST update within 1 sprint of the code change.** Every user-facing PR = append to the relevant App Knowledge table + add/update FAQ entries. Stale support docs = wrong answers to users.
3. **Pain points documented within 24h of discovery.** Maintain the Pain Point registry below with `[PP-XXX]` IDs. Mark resolved when engineering ships the fix; keep the entry for future audit.
4. **FAQ after EVERY feature build, bug fix, and UI change.** Feature build → new FAQ entries. Bug fix → update if user-visible behavior changed. UI change → update screenshots/descriptions.
5. **Block + report patterns are NEVER reinvented.** Report & Block menus live on `PrivateChallengeDetailView` chat rows and `FriendActivityFeedView` cards via `.contextMenu`. `BlockedUsersView` lives in Settings → Privacy & Security. New user-generated surfaces MUST reuse these — App Review rejects otherwise. (Also in `PRODUCT_ENGINEER_AGENT.md` invariant 20.)

---

## App Knowledge — Feature Map (user-facing)

### Auth + Onboarding
| Flow | What happens | Key files |
|---|---|---|
| Sign up | Email/password OR Apple/Google/Facebook (Supabase) | `NewOnboardingView.swift`, `SocialAuthService.swift` |
| Onboarding quiz | 13 steps: basics → body stats → goals → equipment → experience → schedule → limitations → phone verify | `NewOnboardingView.swift` |
| Phone verify | Twilio SMS, 45 countries, max 3 attempts | `PhoneVerificationSheet.swift` |
| Onboarding recovery | Progress saved per-step in UserDefaults; restores on relaunch | `NewOnboardingView.swift` (`OnboardingSessionManager`) |

### 5 Main Tabs
| Tab | View | What it does |
|---|---|---|
| Home | `DashboardView` | Widgets: streak, hydration, weight, steps, programs, daily quests, weekly league, recovery card |
| Workout | `WorkoutTabView` | Generator, active workout, history, exercise library |
| Social | `FriendsTabView` | Friends, requests, rankings, 1v1 / group / community challenges, shared workouts |
| Meals | `MealPlanView` | USDA food search, nutrition-label OCR (camera), meal logging, macro tracking, recipes, shopping list |
| Stats | `WorkoutProgressView` | XP + levels, charts, muscle heatmap, achievements, PRs, body comp |

### Workout System
Auto-Generate (`WorkoutGeneratorService` + `SmartExerciseSelectionEngine`) · Smart Programs 7/14/21/30d (`SmartProgramEngine`, `DynamicProgramGenerator`) · Active Workout (`ActiveWorkoutView` + `WorkoutManager`) · Exercise Library 6428 exercises (`ExerciseLibraryService`) · Swap (`SmartExerciseSwapView`) · Warm-Up (`SmartWarmUpGenerator`) · Stretch Mode · Custom Builder (`CustomWorkoutBuilderView`) · History (`WorkoutHistoryDetailView`) · Replay (`WorkoutReplayEngine` + `WorkoutReplayView`) · Recovery Day (`RecoveryDayEngine` + `RecoveryDayViews`).

### Nutrition
Food search (USDA edge function) · **Nutrition-label OCR** (NOT barcode lookup) · Macro tracking (`MealService`) · Recipe browser (Spoonacular) · Recipe import from URL · Saved meals · Shopping list · Smart recommendations (`ContextualMealEngine`) · "What to eat right now" (`WhatToEatView`).

### Social + Challenges
Add friends (QR, contacts, search) · Friend profiles · 1v1 challenges · Group challenges · Community challenges · Shared workouts · Reactions · Rankings · **Block + Report** (Settings → Privacy & Security · Long-press context menu on chat and feed).

### Gamification
XP + Levels · Daily Quests (3/day, resets midnight local) · Weekly Leagues (Duolingo-style, placement Monday 00:15 UTC) · Streaks · Streak Shields · PRs · Achievements.

### Health Integrations
| Integration | Data | Connect |
|---|---|---|
| Apple HealthKit | Steps, workouts, weight, body comp | Settings |
| Strava | Running/cycling | Settings → Strava |
| Fitbit | Steps, HR, sleep | Settings → Fitbit |
| WHOOP | Recovery, HRV, strain, sleep stages, SpO2, skin temp, workouts | Settings → WHOOP |
| InBody | Body comp scans | Settings → InBody |
| Bluetooth equipment | Treadmill / bike auto-connect | `BluetoothFitnessManager` |

### Tracking
Weight · Body comp · Hydration · Steps · Activity rings · Muscle heatmap.

### Settings + Account
Profile / Units / Notifications / Cloud Backup / Data Download / Privacy Policy / Bug Reports / **Delete Account** / **Blocked Users**.

### Running + Cardio
GPS running with Live Activities · Indoor cardio equipment · Cardio goals.

### Premium + Monetization
Currently all features free (StoreKit integration pending). AdMob present (ATT pending). Upgrade UI exists but no purchase flow yet (`PremiumUpgradeView`).

---

## Pain Point Registry (living)

### Template
```
[PP-XXX] Title
Category / Severity / Frequency
Description (what the user experiences)
Root cause (code/service)
Workaround
Recommended fix
Status: Open | Reported | In Progress | Resolved
Related Agent
```

### Current
| ID | Pain point | Severity | Root cause | Status |
|---|---|---|---|---|
| PP-001 | App loses data when offline | High | No offline queue (H-4) | Resolved (CloudSyncRetryQueue) |
| PP-002 | Keyboard doesn't dismiss on tap outside | Medium | Missing `.scrollDismissesKeyboard` (M-8) | Open |
| PP-003 | Challenge progress shows on wrong day | Critical | Timezone mismatch (C-7) | Resolved (caller-timezone fix — `supabase/20260520_challenge_daily_reset_caller_tz.sql` + Data invariants 45–47; bug-intel fingerprint `6be18e3a` closed). New "wrong day" reports → likely a different root cause; route to Data & Backend. |
| PP-004 | Can't find specific foods in search | Medium | USDA coverage gaps | Open |
| PP-005 | Streak lost unexpectedly | High | Timezone + recovery day counting | Open |
| PP-006 | Workout feels repetitive | Medium | Exercise selection history weighting | Open |
| PP-007 | No VoiceOver support | High | Missing accessibility labels (H-2) | Open |
| PP-008 | Cards slightly different colors across screens | Low | `Color(white: 0.12)` inconsistency (UI-3) | Open |
| PP-009 | Can't take progress photos | High | Feature not built | Open |
| PP-010 | Rest days feel empty | Medium | Recovery Day exists but low discoverability | Open |
| PP-011 | Social features fail on cold launch | Critical | Auth race condition | **Resolved (Mar 2026)** |
| PP-012 | Blank health data with no guidance | High | HealthKit permission revoked, empty with no CTA | **Resolved (Mar 2026)** |
| PP-013 | Exercise swap erases completed sets | High | `WorkoutManager.replaceExercise` discarded sets | **Resolved (Mar 2026)** |
| PP-014 | "Account creation failed" dead end | Critical | `signUp()` created auth user + profile failed + retry rejected as "already registered" | **Resolved (Mar 2026)** — recovery logic + error surfacing |
| PP-015 | "Session expired" during phone verify | Critical | Email/password signup deferred account creation; `@State password` lost across 10 steps | **Resolved (Mar 2026)** — account now created immediately after password entry |
| PP-016 | "Cardio gave me 0 LP, but my friend's gave 50" | High | Old client-side `+50 cardioSession` award was bypassed on `RunCompletionView` silent-skip path AND on Strava/HK imports. Net: native Fit33 runs sometimes credited, Strava-imported runs never did. | **Resolved (May 2026)** — server-side `record_cardio_workout` RPC awards graduated LP for ALL sources (Fit33 native, Strava, HK, Watch). Client-side `+50` removed from `UserManager`. |
| PP-017 | "I started a run, app crashed, lost my GPS data" | Critical | Pre-redesign cardio used in-memory state only; cold launch = lost session. | **Resolved (May 2026)** — `CardioSessionManager` writes a `CardioSessionSnapshot` to UserDefaults under `fit33.cardioSession.snapshot.v1` while phase ∈ {.active, .paused}. Cold-launch recovery rehydrates within 4h window. |
| PP-018 | "My cardio screen has stuff stuck under the notch" | Medium | `CardioActiveWorkoutView` was missing `.ignoresSafeArea()` on the map layer. | **Resolved (May 2026)** — `.ignoresSafeArea()` applied; map fills the bezel. |
| PP-019 | "I run on Strava — why am I missing out on streaks / quests / LP?" | High | Strava activities historically routed to a separate path that didn't fan out to the cardio gamification bus. | **Resolved (May 2026)** — `record_cardio_workout` RPC widened `verify_strava_quests_for_today` to all native + Strava + HK sources; quests/streak/LP credit identically regardless of origin. |
| PP-020 | "I subscribed but the price changed at checkout" | High | `SubscriptionPlan` shipped with stale hardcoded `$3.99` / `$29.99` strings while StoreKit was already configured at canonical `$9.99` / `$59.99`. | **Resolved (May 2026)** — `PremiumUpgradeView` updated to canonical values; copy now matches StoreKit truth. |
| PP-021 | "First time I opened cardio there was nothing in my history" | Medium | App wrote forward-only — historical Apple-Watch / Strava-via-HK workouts were never imported. | **Resolved (May 2026)** — `CardioLandingView.triggerHKBackfillIfNeeded()` runs `HealthDataService.syncAllHealthData(force: true)` exactly once on first cardio-page open (UserDefaults gate `cardio_first_open_hk_backfill_done_v1`), pulling last 30d from HealthKit. Newcomers see populated feed immediately. |

---

## Bug-to-Feature Mapping (most common user reports)

| User reports | Actual situation | Response strategy |
|---|---|---|
| "Gave me the wrong workout" | Auto-gen picked exercises user doesn't prefer | Explain auto-gen; suggest Custom Builder or Swap |
| "My streak disappeared" | Timezone OR missed recovery day | Explain rules; mention streak shields; file timezone bug if applicable |
| **"I can't find my food"** | **USDA doesn't cover every branded product** | **Suggest generic alternative. DO NOT mention barcode scanning — we only OCR the label.** |
| "App crashed during workout" | Memory leak / force unwrap | Collect device+iOS+screen+action; route to Quality |
| "Challenge progress is wrong" | Timezone mismatch client/server | Acknowledge known issue; route to Data & Backend |
| "Doesn't work offline" | No offline queue for some flows (most covered by `CloudSyncRetryQueue`) | Acknowledge limitation; explain cloud-only flows |
| "Can't see friend's workout" | Privacy setting or sync delay | Check friend status; check realtime sub |
| "My run paused itself" | Auto-pause kicked in (speed dropped below threshold for N seconds) | Explain auto-pause; mention Resume button or just resume motion |
| "My Strava run isn't showing in Fit33" | Strava token expired OR sync delay (typical ≤60s) | Check `StravaService.shared.isConnected`; ask user to re-authorize if needed |
| "Why is my walk credited the same as a run?" | By design — gamification rails treat cardio uniformly; calorie counts differ | Explain Wave 7b graduated LP; confirm walks still count toward streak/quests |
| "I imported a HK workout and it's missing distance" | HK source app didn't write distance (e.g., yoga, strength) | Confirm activity type; if cardio, escalate to Data & Backend |

---

## Knowledge Update Protocol (every PR)

1. READ the PR / commit to understand what changed.
2. IDENTIFY user-facing impact:
   - New feature → add to App Knowledge + write FAQ entries.
   - Bug fix → update Pain Point registry (mark resolved) + update FAQ.
   - UI change → update navigation / flow description.
   - Backend change → check if user-visible behavior changed.
3. UPDATE this doc's knowledge tables.
4. UPDATE `FAQ_PLAN.md` with new entries.
5. NOTIFY if the change creates a new potential pain point.

---

## "A user asked me..." quick reference
- **"How do I...?"** → App Knowledge tables above.
- **"Why did the app...?"** → Bug-to-Feature Mapping.
- **"Is there a way to...?"** → `FEATURE_GAME_PLAN.md` (planned) or acknowledge gap.
- **"App crashed when..."** → device + iOS + screen + action, route to Quality.
- **"I lost my data"** → offline? timezone? sync delay? Route to Data if persistent.
- **"Can I connect...?"** → Health Integrations table.
- **"How do I block / report someone?"** → Settings → Privacy & Security → Blocked Users (unblock). Long-press chat message or feed card → Report & Block.

---

## Interaction with Other Agents

### What I need FROM
| Agent | What |
|---|---|
| Product Engineer | Heads-up on any user-facing view change; feature specs pre-build |
| Design | Visual specs so FAQ matches UI |
| Data & Backend | API behavior changes; error message text |
| Quality | Crash report summaries; performance regressions |
| Fitness Expert | Plain-language explanations of workout logic |
| Infra & Security | Auth flow changes; privacy policy updates |
| Device Compatibility | Device-specific issues |
| Supabase | Data-migration impacts on user-visible data |
| Design System | UI consistency changes affecting FAQ |

### What I provide TO
| Agent | What |
|---|---|
| Product Engineer | Pain points prioritized by freq/severity → feature requests |
| Quality | Bug patterns from user reports → test cases |
| Fitness Expert | User confusion about logic → simplification |
| Design | UI elements users can't find / misunderstand → UX suggestions |
| All | FAQ as "how should this work from the user's perspective" |

---

## Owned Files
| File | Purpose |
|---|---|
| `SUPPORT_AGENT.md` | This file |
| `FAQ_PLAN.md` | FAQ structure + content |
| `privacy-policy.md` | Privacy policy (co-owned with Infra & Security) |

### Co-owned
| File | Primary | My role |
|---|---|---|
| `MASTER_TODO.md` | All agents | User-reported issues |
| `WelcomeTutorialView.swift` | Product Engineer | Review tutorial content for accuracy |
| `ONBOARDING_AUDIT.md` | All agents | User-perspective validation |
| `BugReportView.swift` | Product Engineer | Ensure bug report captures right info |

---

## Success Metrics
| Metric | Target |
|---|---|
| FAQ coverage | Every user-facing feature has ≥ 3 FAQ entries |
| Pain-point response | New entries documented ≤ 24h of discovery |
| Knowledge freshness | All entries updated ≤ 1 sprint of related code change |
| FAQ accuracy | 100% matches current behavior |
| User issue resolution | 80%+ answerable via FAQ |

---

## See Also
- `PRODUCT_ENGINEER_AGENT.md` — navigation, block/report patterns
- `.cursor/rules/codingrules.mdc` — cross-cutting rules
- `docs/history/SUPPORT_AGENT.md` — full feature inventory, dated FAQ additions, integration copy
