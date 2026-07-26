# Fit33 — iOS Fitness App

**Your workout, your way.**

A smart, social workout tracker for iOS — personalized workout generation, real-time challenges with friends, nutrition tracking, health integrations, and gamified progress.

---

## Tech Stack

| Layer | Technology |
|-------|-----------|
| UI | SwiftUI (iOS 17+) |
| Local Data | Core Data |
| Cloud Backend | Supabase (Postgres + Auth + Realtime + Edge Functions) |
| Notifications | APNs via Supabase Edge Function |
| Phone Verify | Twilio Verify |
| Nutrition API | USDA FoodData Central (proxied via Edge Function) |
| Recipes | Spoonacular API |
| Health | Apple HealthKit, Strava, Fitbit, InBody |
| Ads | Google AdMob |
| Payments | StoreKit 2 |

---

## App Architecture

```
Fit33App.swift                    ← Entry point, lifecycle, staged startup pipeline
  └─ ContentView.swift            ← Root: onboarding vs main app
       ├─ NewOnboardingView       ← Auth + profile setup (13 steps)
       └─ MainTabView             ← 5 tabs: Home, Workout, Friends, Meals, Stats
            ├─ DashboardView      ← Widgets: streak, hydration, weight, steps, programs
            ├─ WorkoutTabView     ← Workout generator, active workout, history
            ├─ FriendsTabView     ← Social hub: friends, rankings, challenges
            ├─ MealPlanView       ← Nutrition tracking, food search, recipes
            └─ WorkoutProgressView← XP, charts, muscle heatmap, achievements
```

### Key Services (Singletons)

| Service | Responsibility |
|---------|---------------|
| `SupabaseManager` | Auth, cloud sync, profile, workout history |
| `UserManager` | Local user state (Core Data), onboarding status |
| `WorkoutManager` | Active workout state, persistence, timer |
| `WorkoutGeneratorService` | AI workout generation with smart exercise selection |
| `SmartProgramEngine` | Multi-day program generation |
| `FriendService` | Friends list, sent/received workouts |
| `ChallengeService` | 1v1 and group challenge lifecycle |
| `RealtimeService` | Supabase Realtime subscriptions |
| `MealService` | Daily meal tracking (Core Data) |
| `FoodDatabaseService` | USDA food search via Edge Function |
| `HealthKitService` | Apple Health integration |
| `HealthDataService` | Aggregated health sync (HK + Strava + Fitbit) |
| `PushNotificationService` | APNs token registration + delivery |
| `DeepLinkManager` | URL scheme + universal link routing |
| `ExerciseLibraryService` | Exercise DB sync + caching |

### Backend (Supabase)

```
supabase/
  ├── functions/                     24 edge functions — push delivery,
  │                                  Twilio verify, USDA proxy, moderation,
  │                                  Strava/ASSN/GitHub webhooks, bug-intel
  │                                  triage, notification orchestrator, AI
  │                                  insights/audits, cron recaps
  │                                  (auth per function: see the Edge Function
  │                                  Auth Registry in INFRA_SECURITY_AGENT.md)
  └── *.sql                          Schema migrations & RPC functions
                                     (deploy order: supabase/MIGRATION_INDEX.md)
```

---

## Getting Started

### Prerequisites
- Xcode 15.0+
- iOS 17.0+
- macOS 14.0+
- Supabase project (URL + anon key configured)

### Setup
1. Clone the repo.
2. Copy `Fit33/Secrets.template.swift` → `Fit33/Secrets.swift` and fill in API keys.
3. Open `Fit33.xcodeproj` in Xcode.
4. Build and run (⌘+R).

### First Launch
1. Sign up or sign in (email, Apple, Google, Facebook).
2. Complete onboarding quiz (goals, equipment, experience, schedule).
3. Explore Dashboard, generate a workout, or start a challenge.

---

## Key Features

- **Smart Workout Generation** — AI selects exercises based on goals, equipment, history, and limitations.
- **Multi-Day Programs** — Personalized 7/14/30-day strength programs.
- **Active Workout Tracking** — Set/rep/weight logging with timer, rest periods, exercise swaps.
- **Social & Challenges** — Friend system, 1v1/group challenges, community challenges, shared workouts.
- **Nutrition Tracking** — USDA-backed food search, macro tracking, recipe recommendations.
- **Health Integrations** — HealthKit, Strava, Fitbit, InBody body composition.
- **Gamification** — XP, levels, streaks, streak shields, achievements, personal records.
- **Running & Cardio** — GPS-tracked outdoor runs, cardio equipment workouts.

---

## Development

### Secrets Management
API secrets are stored in `Fit33/Secrets.swift` which is **gitignored**.
See `Fit33/Secrets.template.swift` for the required schema.

### Logging
- All `print()` calls are automatically silenced in production builds via `Logger.swift`.
- Use `AppLogger.error()` / `AppLogger.warning()` for production-important logs (routed to `os_log`).
- Use `print()` freely in debug — it's a no-op in release.

### Design System
- Colors: `AdaptiveColors.swift` — adaptive dark/light colors.
- Components: `DesignSystem.swift` — typography tokens, spacing, card components, gradients.
- Cards: `SleekCardBackground`, `AdaptiveCardStyle`, `DSCard`.

### SQL Migrations
SQL files in `supabase/` are run manually via Supabase SQL Editor.
See `supabase/MIGRATION_INDEX.md` for the numbered release train and
per-migration status (`DEPLOYMENT_ORDER.md` is retired).

---

## License

All rights reserved.
