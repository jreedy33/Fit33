# Fit33 Master TODO

> **Last updated:** March 22, 2026
> **Source:** Consolidated from 20+ audit/plan files. This is the single source of truth for all remaining work.
> **Status legend:** `[ ]` = Not started | `[~]` = Partial/In Progress | `[x]` = Done

---

## 1. Critical (Ship Blockers)

| ID | Task | Agent | Source |
|----|------|-------|--------|
| C-1 | [ ] Move Supabase credentials to Vault/Secrets (service role key still in `.env.local`) | Infra & Security | MASTER_TODO |
| C-2 | [ ] Remove dev menu password from source code (hardcoded string) | Infra & Security | MASTER_TODO |
| C-3 | [ ] StoreKit/IAP integration (premium upgrade flow exists but no purchase logic) | Product Engineer | MASTER_TODO |
| C-4 | [ ] ATT consent prompt for AdMob (AdManager exists but no ATT) | Product Engineer | MASTER_TODO |
| C-5 | [ ] Verify challenge RLS policies cover all edge cases | Data & Backend | MASTER_TODO |
| C-6 | [ ] Atomic challenge RPCs (accept/decline/progress) to prevent race conditions | Data & Backend | MASTER_TODO |
| C-7 | [ ] Timezone consistency for challenge progress (client vs server mismatch) | Data & Backend | MASTER_TODO |
| C-8 | [ ] Fix admin CMS session token storage (potential XSS via cookie handling) | Infra & Security | MASTER_TODO |

---

## 2. High Priority (User-Facing Quality)

| ID | Task | Agent | Source |
|----|------|-------|--------|
| H-1 | [ ] Migrate remaining `print()` calls to `AppLogger` | Quality & Performance | MASTER_TODO |
| H-2 | [ ] Add accessibility labels to all interactive elements (~500+ needed) | Quality & Performance | MASTER_TODO |
| H-3 | [ ] Input validation on all user-facing text fields | Product Engineer | MASTER_TODO |
| H-4 | [ ] Offline retry UX (queue failed requests, show pending state) | Product Engineer | MASTER_TODO |
| H-5 | [ ] Move Strava/Fitbit client IDs to Secrets/Vault | Infra & Security | MASTER_TODO |
| H-6 | [ ] Admin audit log (track admin actions in CMS) | Infra & Security | MASTER_TODO |
| H-7 | [ ] Admin rate limiting on sensitive endpoints | Infra & Security | MASTER_TODO |
| H-8 | [ ] Admin MFA enforcement | Infra & Security | MASTER_TODO |
| H-9 | [ ] Verify `REPLICA IDENTITY FULL` on realtime-subscribed tables | Data & Backend | MASTER_TODO |
| H-10 | [ ] Server-side bounds checking on challenge progress values | Data & Backend | MASTER_TODO |
| H-11 | [~] Replace last 3 `NavigationView` usages with `NavigationStack` | Product Engineer | MASTER_TODO |
| H-12 | [ ] Friend system: fix push badge queries (wrong table/columns) | Product Engineer | FRIEND_SYSTEM_AUDIT |
| H-13 | [ ] Friend system: add unfriend RPC with cleanup | Product Engineer | FRIEND_SYSTEM_AUDIT |
| H-14 | [ ] Friend system: implement user blocking (`user_blocks` table, RPCs, RLS, UI) | Product Engineer | FRIEND_SYSTEM_AUDIT |
| H-15 | [ ] Friend system: verify `search_users` RPC works in production | Data & Backend | FRIEND_SYSTEM_AUDIT |
| H-16 | [ ] Notifications: fix streak/daily reminder reschedule (checks workout before rescheduling) | Product Engineer | NOTIFICATION_SYSTEM_AUDIT |
| H-17 | [ ] Notifications: fix duplicate "comeback" logic | Product Engineer | NOTIFICATION_SYSTEM_AUDIT |
| H-18 | [ ] Tutorial redesign: 10-screen flow (challenges, connect, trial CTA, widgets) | Product Engineer | TUTORIAL_REDESIGN_ACTION_PLAN |

---

## 3. Medium Priority (Polish + Infrastructure)

| ID | Task | Agent | Source |
|----|------|-------|--------|
| M-1 | [ ] Replace `DispatchQueue.main.asyncAfter` with `Task.sleep(for:)` | Quality & Performance | MASTER_TODO |
| M-2 | [ ] Localization prep (extract all user-facing strings) | Product Engineer | MASTER_TODO |
| M-3 | [ ] Certificate pinning for Supabase API calls | Infra & Security | MASTER_TODO |
| M-4 | [ ] Memory/closure retain cycle audit | Quality & Performance | MASTER_TODO |
| M-7 | [ ] Fix exercise sync race conditions (parallel Core Data writes) | Data & Backend | MASTER_TODO |
| M-8 | [ ] API rate limits on client-side (debounce rapid calls) | Quality & Performance | MASTER_TODO |
| M-9 | [ ] Keyboard dismiss + safe area fixes across all input screens | Product Engineer | MASTER_TODO |
| M-10 | [ ] Phone number redaction in session logs | Infra & Security | MASTER_TODO |
| M-11 | [ ] CI/CD pipeline (automated build + test on PR) | Infra & Security | MASTER_TODO |
| M-13 | [ ] DTO null safety audit (handle missing fields gracefully) | Data & Backend | MASTER_TODO |
| M-15 | [~] Dark mode token adoption (replace `Color(white: 0.12)` violations) | Design System | MASTER_TODO |
| M-18 | [ ] Birthday format toggle (MM/DD vs DD/MM) in onboarding | Product Engineer | ONBOARDING_AUDIT |
| M-19 | [ ] Email verification flow | Infra & Security | ONBOARDING_AUDIT |
| M-20 | [ ] Design system: replace hardcoded card colors with `Color.cardBackground` | Design System | UI_AUDIT |
| M-21 | [ ] Design system: deduplicate `ScaleButtonStyle` variants | Design System | UI_AUDIT |
| M-22 | [ ] Design system: typography/spacing/corner radius token enforcement | Design System | UI_AUDIT |
| M-23 | [ ] Design system: standardize haptic feedback patterns | Design System | UI_AUDIT |
| M-24 | [ ] Design system: standardize empty states across all screens | Design System | UI_AUDIT |
| M-25 | [ ] Workout flow: unify Build Workout with Exercise Library | Product Engineer | WORKOUT_FLOW_FIXES_PLAN |
| M-26 | [ ] Exercise search: result ranking improvements | Product Engineer | EXERCISE_SEARCH_IMPROVEMENT_PLAN |
| M-27 | [ ] Onboarding: split large `NewOnboardingView.swift` into smaller components | Product Engineer | ONBOARDING_AUDIT |

---

## 4. Feature Backlog

| ID | Task | Agent | Source |
|----|------|-------|--------|
| F-1 | [ ] Progress photos (capture, compare, timeline) | Product Engineer | FEATURE_GAME_PLAN |
| F-2 | [ ] Workout notes (per-workout text field) | Product Engineer | FEATURE_GAME_PLAN |
| F-3 | [ ] Exercise notes (per-exercise annotations) | Product Engineer | FEATURE_GAME_PLAN |
| F-4 | [ ] Body measurements tracking (beyond weight) | Product Engineer | FEATURE_GAME_PLAN |
| F-5 | [ ] Monthly progress report | Product Engineer | FEATURE_GAME_PLAN |
| F-6 | [ ] Rest timer presets (quick select common durations) | Product Engineer | FEATURE_GAME_PLAN |
| F-7 | [ ] Notification phases 2-4: weekly progress, celebrations, water/weight reminders | Product Engineer | NOTIFICATION_SYSTEM_AUDIT |
| F-8 | [ ] Apple Watch companion app (planning phase) | Device Compatibility | DEVICE_COMPATIBILITY_TASKS |
| F-9 | [ ] iPad layout adaptation (Phases 1-3) | Device Compatibility | DEVICE_COMPATIBILITY_TASKS |
| F-10 | [ ] In-app FAQ view (`FAQView.swift` accessible from Settings) | Support & Knowledge | FAQ_PLAN |
| F-11 | [ ] Contextual tooltips on complex screens | Support & Knowledge | FAQ_PLAN |

---

## 5. Fitness Engine Backlog

| ID | Task | Agent | Severity | Source |
|----|------|-------|----------|--------|
| FE-1 | [ ] Push/Pull split missing leg exercises | Fitness Expert | Critical | FITNESS_EXPERT_AUDIT |
| FE-2 | [ ] Bro split generating 7-day plans (should cap at 5-6) | Fitness Expert | Critical | FITNESS_EXPERT_AUDIT |
| FE-3 | [ ] Duplicate exercise-count logic between generator and validator | Fitness Expert | Critical | FITNESS_EXPERT_AUDIT |
| FE-4 | [ ] Upright row classification (should be shoulders, not traps) | Fitness Expert | Critical | FITNESS_EXPERT_AUDIT |
| FE-5 | [ ] Upper/Lower A-B variation (needs distinct A/B days) | Fitness Expert | High | FITNESS_EXPERT_AUDIT |
| FE-6 | [ ] Full-body movement coverage gaps | Fitness Expert | High | FITNESS_EXPERT_AUDIT |
| FE-7 | [ ] PPL push day missing rear delts | Fitness Expert | High | FITNESS_EXPERT_AUDIT |
| FE-8 | [ ] Lateral vs front raise bundle logic | Fitness Expert | High | FITNESS_EXPERT_AUDIT |
| FE-9 | [ ] Fat-loss rep/rest scheme optimization | Fitness Expert | High | FITNESS_EXPERT_AUDIT |
| FE-10 | [ ] Skull crusher movement pattern classification | Fitness Expert | High | FITNESS_EXPERT_AUDIT |
| FE-11 | [ ] Surprise workout shuffle algorithm | Fitness Expert | Medium | FITNESS_EXPERT_AUDIT |
| FE-12 | [ ] Arnold split implementation | Fitness Expert | Medium | FITNESS_EXPERT_AUDIT |
| FE-13 | [ ] Beginner rest period consistency | Fitness Expert | Medium | FITNESS_EXPERT_AUDIT |

---

## 6. Database / Backend Backlog

| ID | Task | Agent | Source |
|----|------|-------|--------|
| DB-1 | [ ] RLS verification for all tables (complete SECURITY_CHECKLIST checkboxes) | Data & Backend | SECURITY_CHECKLIST |
| DB-2 | [ ] DTO null safety audit across all Supabase DTOs | Data & Backend | MASTER_TODO |
| DB-3 | [ ] Cascade deletion review (`delete_user_account` completeness) | Data & Backend | DATABASE_AUDIT_REPORT |
| DB-4 | [ ] Database Phase 3: strategic columns (`completion_rate`, `user_feature_usage`, etc.) | Supabase Expert | DATABASE_AUDIT_REPORT |
| DB-5 | [ ] Verify `optimize_query_performance.sql` applied in production | Data & Backend | PERFORMANCE_OPTIMIZATION_PLAN |
| DB-6 | [ ] Enable `pg_stat_statements` for query monitoring | Data & Backend | SUPABASE_HEALTH_CHECKLIST |
| DB-7 | [ ] Index audit on high-traffic tables | Supabase Expert | MASTER_TODO |

---

## 7. Low Priority

| ID | Task | Agent | Source |
|----|------|-------|--------|
| L-1 | [ ] App Store review prompts (strategic timing) | Product Engineer | MASTER_TODO |
| L-2 | [ ] Image placeholders for loading states | Design System | MASTER_TODO |
| L-3 | [ ] GDPR data export enhancement | Infra & Security | MASTER_TODO |
| L-4 | [ ] Background app refresh optimization | Quality & Performance | MASTER_TODO |
| L-5 | [ ] Edge function error response consistency | Data & Backend | MASTER_TODO |
| L-6 | [ ] Architecture: reduce singletons where possible | Product Engineer | MASTER_TODO |
| L-7 | [ ] Architecture: split large files (>1000 lines) | Product Engineer | MASTER_TODO |
| L-8 | [ ] Architecture: add XCTest coverage (target 100+ tests) | Quality & Performance | MASTER_TODO |
| L-9 | [ ] Streak audit: manual timezone-change test | Quality & Performance | STREAK_AUDIT_GAMEPLAN |
| L-10 | [ ] Streak audit: midnight app-kill daily-reset test | Quality & Performance | STREAK_AUDIT_GAMEPLAN |

---

## Recently Completed (March 22, 2026)

For reference, these were resolved today:

- [x] Auth race condition: guards on 12 social fetch methods (70% crash reduction)
- [x] HealthKit permission crashes: `isAuthorized` checks on all queries
- [x] UUID type mismatch: empty string passed as UUID to Postgres
- [x] Exercise swap: preserve completed sets during replacement
- [x] Stats Tab 54s freeze: PR computation moved to background Core Data context
- [x] CancellationError noise filtered from crash reports (~30% reduction)
- [x] Insights `updated_at` schema fix applied
- [x] Contact matching RPC deployed (`match_contacts_by_phone`)
- [x] HealthKit activity types expanded (17+ types, no more "Other")
- [x] Strava deduplication: skip Strava-sourced HK workouts
- [x] FAQ system: 87 entries, admin CMS page, public API, GitHub Action auto-update
- [x] Support Agent integrated as 10th engineering team member
- [x] Crash analysis with Claude + .md export in admin CMS
- [x] AI Insights Claude given access to crash/bug/session data
- [x] Dev logs: user profile + device details in sessions
- [x] Dashboard: Recent Activity header aligned with Friends tab style
- [x] Agent docs updated with auth guard, UUID safety, HealthKit rules

---

## Cross-Reference

Detailed specs for items above live in these reference docs:

| Doc | Covers |
|-----|--------|
| `FEATURE_GAME_PLAN.md` | Feature backlog details + competitor analysis |
| `FAQ_PLAN.md` | 87 FAQ entries, website/in-app/tooltip plans |
| `SECURITY_CHECKLIST.md` | RLS verification matrix |
| `DEVICE_COMPATIBILITY_TASKS.md` | iPad/Watch/responsive layout phases |
| `ONBOARDING_AUDIT.md` | Deep onboarding spec + QA checklist |
| `FRIEND_SYSTEM_AUDIT.md` + `FRIEND_SYSTEM_BUGS.md` | Social feature gaps + 15 bugs |
| `NOTIFICATION_SYSTEM_AUDIT.md` | Notification phases 1-4 |
| `FITNESS_EXPERT_AUDIT_FINDINGS.md` | Workout engine backlog (13+ items) |
| `TUTORIAL_REDESIGN_ACTION_PLAN.md` | 10-screen tutorial redesign |
| `WORKOUT_FLOW_FIXES_PLAN.md` | Workout flow unification |
| `DATABASE_AUDIT_REPORT.md` | Schema health + Phase 3 roadmap |
| `SUPABASE_HEALTH_CHECKLIST.md` | Ops checklist (RLS, perf, monitoring) |
