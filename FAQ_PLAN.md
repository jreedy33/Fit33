# FAQ Plan — Fit33

> **Owner**: Support Agent
> **Purpose**: Comprehensive FAQ content plan for in-app and web help center
> **File**: `FAQ_PLAN.md`

---

## FAQ Architecture

### Delivery Channels

| Channel | Location | Format | Status |
|---------|----------|--------|--------|
| **Website Help Center** | `Website/help-center.html` | HTML accordion FAQ | Live (8 entries) |
| **Website Help Articles** | `Website/help/*.html` | Full tutorial pages | 1 live (`getting-started.html`) |
| **In-App FAQ** | Future `FAQView.swift` | Native SwiftUI list | Not yet built |
| **In-App Tooltips** | Contextual tips on key screens | SwiftUI overlays | Not yet built |

### Priority Order
1. **Expand website FAQ** — immediate, no app release needed
2. **Build remaining help articles** — 5 category pages planned
3. **Add in-app FAQ view** — accessible from Settings
4. **Add contextual tooltips** — on complex screens (workout generator, programs, challenges)

---

## FAQ Content by Category

### Category 1: Getting Started (8 entries)

| # | Question | Answer Summary | Channel |
|---|----------|---------------|---------|
| GS-1 | How do I create an account? | Sign up with email, Apple, Google, or Facebook. Tap "Get Started" on launch screen. | Web + App |
| GS-2 | What happens during onboarding? | 13-step quiz: name, age, body stats, goals, equipment, experience, schedule, limitations, phone verify. Takes ~3 minutes. | Web + App |
| GS-3 | Can I skip the onboarding quiz? | No — the quiz personalizes your workouts, programs, and nutrition. Every answer matters. | Web + App |
| GS-4 | How do I reset my onboarding answers? | Settings → Profile → Edit any field (goals, equipment, experience, limitations). | Web + App |
| GS-5 | Why do you need my phone number? | Phone verification prevents fake accounts and enables friend discovery via contacts. You can skip it. | Web + App |
| GS-6 | What are the 5 tabs? | Home (dashboard), Workout (generator + history), Social (friends + challenges), Meals (nutrition), Stats (progress). | Web + App |
| GS-7 | Is Fit33 free? | Yes — all core features are free. Premium features coming soon. | Web + App |
| GS-8 | What devices does Fit33 support? | iPhone running iOS 17 or later. iPad support is planned. | Web + App |

### Category 2: Workouts & Exercises (12 entries)

| # | Question | Answer Summary | Channel |
|---|----------|---------------|---------|
| WK-1 | How do I start a workout? | Workout tab → "Surprise Me" (auto-generate) or "Build Custom" (manual). | Web + App |
| WK-2 | What is "Surprise Me"? | AI generates a personalized workout based on your goals, equipment, experience, history, and limitations. | Web + App |
| WK-3 | How do I build a custom workout? | Workout tab → Build Custom → search/filter 7,000+ exercises → add to workout → set reps/sets → GO! | Web + App |
| WK-4 | How do I log a set during a workout? | Tap the set row → enter weight and reps → tap checkmark. The rest timer starts automatically. | Web + App |
| WK-5 | Can I swap an exercise mid-workout? | Yes — tap the exercise name → "Swap" → choose a smart suggestion (same muscle group + equipment). | Web + App |
| WK-6 | How do I reorder exercises? | Long-press an exercise → drag to new position. | Web + App |
| WK-7 | What are supersets? | Two exercises performed back-to-back with no rest between. Tap "Superset" to pair exercises. | Web + App |
| WK-8 | How does the rest timer work? | Auto-starts after logging a set. Default rest varies by exercise type. Tap timer to adjust or skip. | Web + App |
| WK-9 | Where is my workout history? | Workout tab → History section. Tap any past workout to see full details. | Web + App |
| WK-10 | Why did I get this specific exercise? | Auto-gen considers: your goals, equipment, experience level, physical limitations, and recent workout history to avoid repeats. | Web + App |
| WK-11 | Does Fit33 have warm-ups? | Yes — a smart warm-up is auto-generated based on the muscles in your workout. Toggle it on before starting. | Web + App |
| WK-12 | Can I stretch after my workout? | Yes — tap "Stretch Mode" after finishing. Guided stretches target the muscles you just worked. | Web + App |

### Category 3: Smart Programs (6 entries)

| # | Question | Answer Summary | Channel |
|---|----------|---------------|---------|
| SP-1 | What are Smart Programs? | AI-generated multi-day training plans (7, 14, 21, or 30 days) with progressive overload and periodization. | Web + App |
| SP-2 | How do I start a program? | Workout tab → Programs → Browse → Select a program → Start. Your daily workout appears on the home screen. | Web + App |
| SP-3 | Can I customize my program? | Yes — swap exercises, adjust sets/reps, skip days. The program adapts around your changes. | Web + App |
| SP-4 | What happens if I miss a program day? | The program shifts forward. No penalty — just pick up where you left off. | Web + App |
| SP-5 | What is a deload week? | A planned easier week (reduced volume/intensity) to prevent overtraining. Built into longer programs automatically. | Web + App |
| SP-6 | How is a program different from a workout? | A workout is a single session. A program is a structured multi-day plan with progression built in. | Web + App |

### Category 4: Nutrition & Meals (10 entries)

| # | Question | Answer Summary | Channel |
|---|----------|---------------|---------|
| NM-1 | How do I log food? | Meals tab → tap a meal slot (Breakfast/Lunch/Dinner/Snack) → search or scan barcode. | Web + App |
| NM-2 | How does the barcode scanner work? | Meals tab → tap barcode icon → point camera at product barcode → nutrition data auto-fills. | Web + App |
| NM-3 | Why can't I find my food? | We use the USDA FoodData Central database. Some branded products may not be listed. Try generic terms (e.g., "chicken breast" instead of a brand name). | Web + App |
| NM-4 | How do I set my calorie/macro goals? | Settings → Nutrition Goals. Or let Fit33 calculate them based on your body stats and goals. | Web + App |
| NM-5 | Where do I see my daily macros? | Meals tab — the macro ring at the top shows calories, protein, carbs, and fat progress. | Web + App |
| NM-6 | How do I save a meal for quick logging? | After logging a meal → tap "Save Meal" → name it. Find saved meals in the "Saved" tab. | Web + App |
| NM-7 | How do I find recipes? | Meals tab → Recipes → browse by goal, cuisine, or dietary preference. Powered by Spoonacular. | Web + App |
| NM-8 | Can I import a recipe from a URL? | Yes — Meals tab → Recipes → Import → paste any recipe URL. We extract ingredients and nutrition. | Web + App |
| NM-9 | What is "What to Eat Right Now"? | A smart suggestion based on time of day, your remaining macro budget, and your preferences. | Web + App |
| NM-10 | Where is my shopping list? | Meals tab → Shopping List. Auto-generated from your meal plan. | Web + App |

### Category 5: Social & Challenges (8 entries)

| # | Question | Answer Summary | Channel |
|---|----------|---------------|---------|
| SC-1 | How do I add friends? | Social tab → Add Friends → QR code, search by name, or import from contacts. | Web + App |
| SC-2 | How do I challenge a friend? | Social tab → tap a friend → "Challenge" → choose type (steps, workouts, streaks, etc.) → set duration → send. | Web + App |
| SC-3 | Can I challenge multiple friends at once? | Yes — create a Group Challenge. Social tab → Challenges → Create → add multiple friends. | Web + App |
| SC-4 | What are Community Challenges? | Public challenges anyone can join. Social tab → Community → browse active challenges → join. | Web + App |
| SC-5 | How do I share my workout? | After finishing a workout → tap "Share" → select friends to send it to. They can view your full workout. | Web + App |
| SC-6 | Can I see my friend's workouts? | Yes — tap their profile in the Social tab to see their recent activity, stats, and shared workouts. | Web + App |
| SC-7 | Where do I see rankings? | Social tab → Rankings. Leaderboards by XP, streaks, workouts completed, and more. | Web + App |
| SC-8 | How do I react to a friend's activity? | Tap the reaction icon on any friend activity in your feed. | Web + App |

### Category 6: Gamification & Progress (9 entries)

| # | Question | Answer Summary | Channel |
|---|----------|---------------|---------|
| GP-1 | How do I earn XP? | Complete workouts, finish daily quests, win challenges, hit streaks. XP earns you levels. | Web + App |
| GP-2 | What are levels? | Your fitness rank based on total XP earned. Higher levels unlock bragging rights and future rewards. | Web + App |
| GP-3 | What are Daily Quests? | 3 new quests every day (e.g., "Log 2 meals", "Complete a workout", "Drink 8 glasses of water"). Earn bonus XP. | Web + App |
| GP-4 | When do Daily Quests reset? | Midnight in your local timezone. | Web + App |
| GP-5 | What are Weekly Leagues? | Duolingo-style tiered leagues. Compete with other users weekly. Top performers promote to higher tiers. | Web + App |
| GP-6 | How do streaks work? | Complete at least one workout per day to build your streak. Consecutive days = longer streak. | Web + App |
| GP-7 | I lost my streak! Can I get it back? | Use a Streak Shield — it protects your streak for one missed day. Shields are limited, so use them wisely. | Web + App |
| GP-8 | How are Personal Records tracked? | Automatically. When you lift more weight or do more reps than your previous best, you'll see a PR badge. View all PRs in Stats. | Web + App |
| GP-9 | How do I unlock achievements? | Hit milestones (first workout, 7-day streak, 100 workouts, etc.). View all achievements in Stats → Achievements. | Web + App |

### Category 7: Health Integrations (6 entries)

| # | Question | Answer Summary | Channel |
|---|----------|---------------|---------|
| HI-1 | How do I connect Apple Health? | Settings → Integrations → Apple Health → Allow. Steps, workouts, and weight sync automatically. | Web + App |
| HI-2 | How do I connect Strava? | Settings → Integrations → Strava → Sign In. Running and cycling activities will import. | Web + App |
| HI-3 | How do I connect Fitbit? | Settings → Integrations → Fitbit → Sign In. Steps, heart rate, and sleep data will sync. | Web + App |
| HI-4 | How do I import InBody scans? | Settings → Integrations → InBody → follow the import flow. Body composition data appears in Stats. | Web + App |
| HI-5 | How do I connect Bluetooth gym equipment? | Active workout → tap Bluetooth icon → select your treadmill, bike, or rower. Auto-detects nearby devices. | Web + App |
| HI-6 | Does step data count toward challenges? | Yes — if Apple Health or Fitbit is connected, steps auto-count toward step-based challenges. | Web + App |

### Category 8: Tracking & Body Stats (7 entries)

| # | Question | Answer Summary | Channel |
|---|----------|---------------|---------|
| TB-1 | How do I log my weight? | Home tab → Weight widget → tap to enter today's weight. Also syncs from Apple Health. | Web + App |
| TB-2 | How do I track body fat? | Stats → Body Composition. Enter manually or import from InBody scans. | Web + App |
| TB-3 | How do I track water intake? | Home tab → Hydration widget → tap glasses to log water throughout the day. | Web + App |
| TB-4 | Where do I see my steps? | Home tab → Steps widget. Pulled from Apple Health or Fitbit. | Web + App |
| TB-5 | What is the muscle heatmap? | Stats → Muscle Heatmap. Visual showing which muscles you've trained recently and how often. Darker = more trained. | Web + App |
| TB-6 | What are Activity Rings? | Visual rings showing daily movement, exercise, and stand goals — similar to Apple Watch rings. | Web + App |
| TB-7 | How do I switch between kg and lbs? | Settings → Units → toggle between Metric and Imperial. Applies everywhere instantly. | Web + App |

### Category 9: Account & Settings (7 entries)

| # | Question | Answer Summary | Channel |
|---|----------|---------------|---------|
| AS-1 | How do I change my profile? | Settings → Profile. Edit name, photo, goals, equipment, experience, and limitations. | Web + App |
| AS-2 | How do I change my fitness goals? | Settings → Profile → Goals. Your workouts and programs will adapt to your new goals. | Web + App |
| AS-3 | Is my data backed up? | Yes — all data syncs to the cloud automatically when you're signed in. | Web + App |
| AS-4 | Can I download my data? | Yes — Settings → Privacy → Download My Data. You'll receive a full export. | Web + App |
| AS-5 | How do I turn off notifications? | Settings → Notifications. Toggle individual notification types on/off. | Web + App |
| AS-6 | How do I delete my account? | Settings → Account → Delete Account. This permanently removes all your data. | Web + App |
| AS-7 | Where is the privacy policy? | Settings → Privacy Policy. Also at fit33app.com/privacy.html. | Web + App |

### Category 10: Troubleshooting (10 entries)

| # | Question | Answer Summary | Channel |
|---|----------|---------------|---------|
| TS-1 | The app crashed during my workout — is my data saved? | Yes — workout progress is saved locally every time you log a set. Reopen the app to resume. | Web + App |
| TS-2 | My workout data isn't syncing | Check internet connection. Go to Settings → Cloud Backup → Force Sync. If the issue persists, report a bug. | Web + App |
| TS-3 | I can't find a specific food | Try generic terms instead of brand names. Use the barcode scanner for packaged foods. The USDA database covers most whole foods. | Web + App |
| TS-4 | My streak disappeared | Streaks require one workout per calendar day (midnight-to-midnight in your timezone). Use Streak Shields to protect missed days. If this seems like a bug, report it. | Web + App |
| TS-5 | Challenge progress shows wrong numbers | Known issue with timezone differences. We're actively fixing this. Your data is accurate — only the display timing may be off. | Web + App |
| TS-6 | The app doesn't work offline | Some features require internet (food search, cloud sync, challenges). Workouts can be logged offline and will sync when reconnected. | Web + App |
| TS-7 | Exercise videos won't play | Check your internet connection. Videos stream on demand. Try closing and reopening the exercise. If the issue persists, report a bug. | Web + App |
| TS-8 | Push notifications aren't working | Settings (iOS) → Fit33 → Notifications → ensure enabled. Also check in-app: Settings → Notifications. | Web + App |
| TS-9 | The app feels slow or laggy | Try force-closing and reopening. Ensure you're on the latest version. If performance issues persist, report a bug with your device model and iOS version. | Web + App |
| TS-10 | How do I report a bug? | Settings → Contact Support → Report a Bug. Include what happened, what you expected, and whether it's reproducible. Attach session logs if possible. | Web + App |

### Category 11: Running & Cardio (4 entries)

| # | Question | Answer Summary | Channel |
|---|----------|---------------|---------|
| RC-1 | How do I track an outdoor run? | Workout tab → Running → Start Run. GPS tracks your route, pace, and distance with Live Activities on lock screen. | Web + App |
| RC-2 | Can I log treadmill workouts? | Yes — Workout tab → Cardio → select treadmill. Enter distance/time manually or connect via Bluetooth. | Web + App |
| RC-3 | How do I set a running goal? | Workout tab → Running → Goals → set a distance, time, or calorie target. | Web + App |
| RC-4 | Does running count toward my streak? | Yes — any completed workout (strength, cardio, running) counts toward your daily streak. | Web + App |

---

## Website Help Article Plan

Each category gets a dedicated help page with expanded tutorials:

| Page | File | Articles | Status |
|------|------|----------|--------|
| Getting Started | `help/getting-started.html` | 8 | Live |
| Workouts & Exercises | `help/workouts.html` | 12 | Planned |
| Smart Programs | `help/programs.html` | 6 | Planned |
| Progress & Stats | `help/tracking.html` | 9 | Planned |
| Account & Settings | `help/account.html` | 7 | Planned |
| Troubleshooting | `help/troubleshooting.html` | 10 | Planned |

---

## In-App FAQ Implementation Plan

### SwiftUI View: `FAQView.swift`

```
FAQView
├── SearchBar (filter questions)
├── List
│   ├── Section("Getting Started")
│   │   ├── DisclosureGroup("How do I create an account?") { answer }
│   │   ├── DisclosureGroup("What happens during onboarding?") { answer }
│   │   └── ...
│   ├── Section("Workouts & Exercises")
│   │   └── ...
│   ├── Section("Smart Programs")
│   │   └── ...
│   ├── Section("Nutrition & Meals")
│   │   └── ...
│   ├── Section("Social & Challenges")
│   │   └── ...
│   ├── Section("Gamification & Progress")
│   │   └── ...
│   ├── Section("Health Integrations")
│   │   └── ...
│   ├── Section("Tracking & Body Stats")
│   │   └── ...
│   ├── Section("Account & Settings")
│   │   └── ...
│   └── Section("Troubleshooting")
│       └── ...
└── "Still need help?" → BugReportView
```

### Data Model

```swift
struct FAQEntry: Identifiable, Codable {
    let id: String          // e.g., "WK-1"
    let category: String
    let question: String
    let answer: String
    let keywords: [String]  // for search
}
```

### Access Points
- Settings → Help & FAQ
- Onboarding completion → "Need help? Check the FAQ"
- Empty states → contextual FAQ links (e.g., no workouts → "How do I start a workout?")
- Post-workout → "Have questions about your stats?"

---

## Contextual Tooltip Plan

Inline tips on complex screens to reduce confusion before it happens:

| Screen | Tooltip | Trigger |
|--------|---------|---------|
| Workout Generator | "Tap Surprise Me for an AI workout, or Build Custom to choose your exercises" | First visit |
| Active Workout | "Tap a set row to log weight and reps" | First workout |
| Active Workout | "Long-press to reorder exercises" | First workout |
| Exercise Swap | "Suggestions match your muscle group and equipment" | First swap |
| Program View | "Your program adapts if you miss a day — no penalty" | First program |
| Macro Ring | "Tap to see your remaining calories and macros" | First meal log |
| Streak Widget | "Complete any workout to keep your streak going" | First streak |
| Challenge Create | "Choose from steps, workouts, or streaks" | First challenge |
| Muscle Heatmap | "Darker colors = more recently trained" | First view |

---

## FAQ Update Protocol

### After Every Feature Build
1. Identify which FAQ category the feature belongs to
2. Write 1-3 new FAQ entries covering: what it does, how to use it, common questions
3. Add entries to this plan with the next available ID
4. Update website `help-center.html` if the FAQ section needs new entries
5. Update in-app FAQ data if `FAQView` exists

### After Every Bug Fix
1. Check if the bug relates to any existing FAQ entry
2. If yes → update the answer to reflect the fix
3. If the bug was commonly reported → add a new Troubleshooting entry
4. Remove or update any workarounds that are no longer needed

### After Every UI Change
1. Check if any FAQ answers reference the changed UI
2. Update step-by-step instructions if navigation changed
3. Update screen names if tabs/sections were renamed

### Monthly Audit
1. Read through every FAQ entry
2. Verify each answer against current app behavior
3. Remove entries for deprecated features
4. Add entries for features that lack FAQ coverage
5. Check that all Troubleshooting entries reflect known-fixed vs still-open issues

---

## Metrics

| Metric | Target | How to Measure |
|--------|--------|----------------|
| FAQ coverage | Every feature has 1+ FAQ entries | Count features vs FAQ entries |
| Total FAQ entries | 83+ across 11 categories | Count entries in this plan |
| Website help articles | 6 category pages live | Check `Website/help/` |
| In-app FAQ | Accessible from Settings | Check `FAQView.swift` exists |
| Freshness | Updated within 1 week of any code change | Git blame on this file |

---

## Current Stats

- **Total FAQ entries planned**: 87
- **Categories**: 11
- **Website FAQ entries live**: 8
- **Help article pages live**: 1 of 6
- **In-app FAQ**: Not yet built
- **Contextual tooltips**: Not yet built

---

*This plan is maintained by the Support Agent. Every user question that can't be answered by an existing FAQ entry should result in a new entry being added here.*
