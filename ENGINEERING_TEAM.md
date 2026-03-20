# Fit33 Engineering Team Structure

> **Lead iOS Engineer's Playbook**: This document defines the team of specialized AI agents, their roles, ownership boundaries, and how they interact to deliver a production-quality iOS app.

---

## The Team

| Agent | File | Domain | One-Line Summary |
|-------|------|--------|-----------------|
| **Lead Designer** | `DESIGN_AGENT.md` | Visual identity, UI specs, design tokens | "What it should look like" |
| **Lead Product Engineer** | `PRODUCT_ENGINEER_AGENT.md` | Features, navigation, component reuse, state management | "How it should work" |
| **Staff Infra & Security** | `INFRA_SECURITY_AGENT.md` | Secrets, auth, CI/CD, network security, admin CMS, compliance | "How it stays safe" |
| **Staff Data & Backend** | `DATA_BACKEND_AGENT.md` | Supabase schema, RLS, RPCs, Core Data, DTOs, edge functions | "How data flows correctly" |
| **Staff Quality & Performance** | `QUALITY_PERFORMANCE_AGENT.md` | Testing, memory, performance, accessibility, error handling | "How it stays stable" |
| **Staff Design System Enforcement** | `DESIGN_SYSTEM_AGENT.md` | Token migration, deduplication, metrics tracking | "How the design gets into the code" |
| **Staff Fitness Expert** | `FITNESS_EXPERT_AGENT.md` | Exercise science, program design, workout validation, training recommendations | "What the workout should actually be" |
| **Staff Device Compatibility** | `DEVICE_COMPATIBILITY_AGENT.md` | Responsive layout, cross-device sizing, iPad support, Apple Watch planning | "How it fits every screen" |

---

## Ownership Matrix

When a task comes in, route it to the right agent:

| Task Type | Primary Agent | Supporting Agent |
|-----------|--------------|-----------------|
| New UI screen | Product Engineer | Design (visual spec) |
| Fix a crash | Quality & Performance | Data (if data-related) |
| Add API endpoint | Data & Backend | Infra (security review) |
| Move secrets out of source | Infra & Security | — |
| Replace hardcoded fonts with tokens | Design System Enforcement | Design (token mapping) |
| Add RLS to a table | Data & Backend | Infra (policy review) |
| Fix memory leak | Quality & Performance | — |
| Add accessibility labels | Quality & Performance | Design (label text) |
| Create CI pipeline | Infra & Security | — |
| Add haptic feedback | Design System Enforcement | Design (haptic spec) |
| Fix navigation inconsistency | Product Engineer | Design (presentation spec) |
| Add offline support | Product Engineer | Data (queue persistence) |
| Write unit tests | Quality & Performance | Data (test fixtures) |
| Fix admin CMS vulnerability | Infra & Security | — |
| Add new database table | Data & Backend | Infra (RLS review) |
| Performance optimization | Quality & Performance | — |
| StoreKit integration | Product Engineer | Infra (receipt validation) |
| Exercise pairing/substitution logic | Fitness Expert | Product Engineer (implementation) |
| Program split recommendations | Fitness Expert | Data (user history) |
| Workout sorting/ordering | Fitness Expert | Product Engineer (UI) |
| Exercise database curation | Fitness Expert | Data (migrations) |
| Auto-gen workout validation | Fitness Expert | Quality (regression tests) |
| Rep/set/weight recommendations | Fitness Expert | Data (user strength data) |
| Fix layout on specific device | Device Compatibility | Product Engineer (implementation) |
| iPad layout adaptation | Device Compatibility | Design (visual spec), Product Engineer |
| Responsive spacing/sizing audit | Device Compatibility | Design System (token enforcement) |
| Cross-device testing matrix | Device Compatibility | Quality (test execution) |
| Apple Watch feature planning | Device Compatibility | Fitness Expert (workout logic) |
| Safe area / Dynamic Island fixes | Device Compatibility | Product Engineer (implementation) |

---

## How Agents Interact

### Communication Protocol

When one agent needs something from another:
1. **Read their agent doc first** — Don't ask what's already documented
2. **Reference specific sections** — "Per DESIGN_AGENT.md > Card System, use `.sleekCard()`"
3. **Co-own shared files explicitly** — Some files have multiple owners (see below)

### Shared File Ownership

| File | Primary Owner | Co-Owner | Notes |
|------|--------------|----------|-------|
| `DesignSystem.swift` | Design Agent | Design System Agent | Design defines tokens; DSE enforces them |
| `AdaptiveColors.swift` | Design Agent | Product Engineer | Design defines colors; PE uses them |
| `SharedUtilities.swift` | Product Engineer | Design System Agent | PE defines utilities; DSE consolidates duplicates |
| `SupabaseManager.swift` | Data Agent | Infra Agent | Data owns operations; Infra owns credentials/auth |
| `AppConfig.swift` | Infra Agent | — | Single owner for configuration |
| `SECURITY_CHECKLIST.md` | Infra Agent | Data Agent | Infra defines policy; Data implements in SQL |
| `MASTER_TODO.md` | All Agents | — | Everyone updates their section |
| `WorkoutComboRules.swift` | Fitness Expert | Product Engineer | Fitness Expert defines rules; PE implements |
| `SmartExerciseSelectionEngine.swift` | Product Engineer | Fitness Expert | PE owns selection logic; Fitness Expert validates scoring |
| `SmartExercisePairingEngine.swift` | Fitness Expert | Product Engineer | Fitness Expert defines pairings; PE implements UI |
| `DynamicProgramGenerator.swift` | Fitness Expert | Product Engineer, Data | Fitness Expert defines splits/templates |
| `ExerciseBundleEngine.swift` | Fitness Expert | Product Engineer | Fitness Expert defines bundles; PE uses for dedup |
| `ProgramTemplateLibrary.swift` | Fitness Expert | Data Agent | Fitness Expert defines periodization; Data syncs to Supabase |
| `NewOnboardingView.swift` | Product Engineer | Data Backend, Infra Security | PE owns flow; Data owns profile sync; Infra owns auth/phone |
| `OnboardingTestHelper.swift` | Quality Performance | Product Engineer | QP owns tests; PE validates flow logic |
| `PhoneVerificationSheet.swift` | Product Engineer | Infra Security | PE owns UI; Infra owns verification security |
| `ContactsService.swift` | Data Backend | Product Engineer | Data owns normalization; PE owns UI |
| `ONBOARDING_AUDIT.md` | All Agents | — | Reference doc for onboarding work |
| `OrientationManager.swift` | Device Compatibility | Product Engineer | Device detection, screen dims, DeviceTier |
| `DEVICE_COMPATIBILITY_AGENT.md` | Device Compatibility | — | Agent spec, device matrix, patterns |
| `DEVICE_COMPATIBILITY_TASKS.md` | Device Compatibility | All Agents | Retroactive fix tracker, Watch log |

---

## Workflow: Building a New Feature

```
Step 1: Product Engineer reads the feature requirements
Step 2: Product Engineer reads DESIGN_AGENT.md for visual specs
Step 3: Product Engineer selects components from the shared inventory
Step 4: If the feature touches data:
        → Data Agent defines/updates schema, DTOs, RLS
        → Infra Agent reviews security implications
Step 5: Product Engineer builds the feature using shared components
Step 6: Design System Agent audits token usage (no hardcoded values)
Step 7: Quality Agent runs through testing checklist:
        - Functional tests
        - Memory profiling
        - Accessibility audit
        - Error handling review
Step 8: Feature ships
```

---

## Workflow: Fixing a Bug

```
Step 1: Quality Agent triages the bug (crash? performance? data?)
Step 2: Route to appropriate agent:
        - UI bug → Product Engineer + Design Agent review
        - Data bug → Data Agent investigates schema/RLS/DTO
        - Security bug → Infra Agent (priority override: P0)
        - Performance bug → Quality Agent profiles and fixes
        - Workout/exercise logic bug → Fitness Expert validates against training science
Step 3: Fix implemented by owning agent
Step 4: Quality Agent verifies fix doesn't regress
```

---

## Workflow: Design System Migration Sprint

```
Step 1: Design System Agent picks a token type (e.g., typography)
Step 2: Design System Agent picks the highest-violation file
Step 3: For each inline value:
        → Map to nearest token (reference DESIGN_AGENT.md)
        → If no clean mapping, ask Design Agent for guidance
Step 4: Replace in batches of 20-50 per commit
Step 5: Quality Agent verifies no visual regressions
Step 6: Design System Agent updates metrics in MASTER_TODO.md
Step 7: Repeat until adoption = 100%
```

---

## Conflict Resolution

### Design vs Engineering
- **Performance wins over animation complexity** — If an effect drops below 60fps, simplify it
- **Consistency wins over uniqueness** — Use the standard pattern even if custom "looks better" on one screen
- **Shared components win over inline code** — Extend the shared component rather than duplicating

### Security vs Speed
- **Security always wins** — Never skip a security step to ship faster
- **If in doubt, ask Infra Agent** — They have final say on security decisions

### Token Mapping Disputes
- **Design Agent is the authority on token values** — They define what 14pt should round to
- **Design System Agent is the authority on migration order** — They decide which files to tackle first
- **Quality Agent is the authority on regressions** — They decide if a replacement looks wrong

---

## Sprint Planning Guide

### Sprint Priority Order (Current)

| Sprint | Focus | Lead Agent | Supporting Agents |
|--------|-------|-----------|-------------------|
| Sprint 1 | Security blockers | Infra & Security | Data (RLS) |
| Sprint 2 | Monetization + data integrity | Product Engineer + Data | Infra (receipt validation) |
| Sprint 3 | Reliability + quick UI wins | Quality + Design System | Product Engineer |
| Sprint 4 | Design system enforcement | Design System | Design (guidance), Quality (verification) |
| Sprint 5 | Infrastructure + testing | Infra + Quality | All (test contributions) |

---

## Key Metrics Dashboard

Track these after every sprint:

| Metric | Sprint 0 (Now) | Target |
|--------|----------------|--------|
| Security vulnerabilities | 9 critical/high | 0 |
| Design token adoption (typography) | ~0% | 100% |
| Design token adoption (spacing) | ~0% | 100% |
| Design token adoption (corner radius) | ~0% | 100% |
| Color(white: 0.12) violations | 97 | 0 |
| Duplicate components | 6 | 0 |
| AnimatedOrbBackground coverage | 100% | 100% |
| Accessibility labels | ~14 | 500+ |
| Unit test count | 0 | 100+ |
| NavigationView usages | 3 | 0 |
| Force unwraps in production | Reduced | 0 |
| CI/CD pipeline | None | Active |

---

## Agent Quick-Reference Card

When you're an agent and unsure what to do, check this:

**"Should I use a design token?"** → YES. Always. See DESIGN_AGENT.md for the mapping.

**"Should I add a new shared component?"** → Only if the pattern appears 3+ times. Add to DesignSystem.swift or SharedUtilities.swift.

**"Should I fix this bug I found while working on something else?"** → If it's in your domain and takes < 5 minutes, fix it. Otherwise, add it to MASTER_TODO.md.

**"Who do I ask about...?"**
- Visual decisions → Design Agent
- Navigation patterns → Product Engineer Agent
- Security/secrets → Infra & Security Agent
- Database/schema → Data & Backend Agent
- Testing/performance → Quality & Performance Agent
- Token migration → Design System Enforcement Agent
- Exercise/workout/program logic → Fitness Expert Agent
- Layout/spacing/device issues → Device Compatibility Agent
- iPad adaptation → Device Compatibility Agent
- Apple Watch planning → Device Compatibility Agent

---

*This team structure ensures every aspect of the app has a clear owner. No task falls through the cracks. No agent steps on another's toes. The Lead iOS Engineer (you, the human) orchestrates — the agents execute.*

---

## AI Insights Hub — Ownership (March 2026)

| Component | Primary Owner | Co-Owner | Files |
|-----------|--------------|----------|-------|
| `ai_insights` table + RLS | Data & Backend | Infra (RLS review) | `supabase/20260319_ai_insights.sql` |
| `ai_chat_history` table + RLS | Data & Backend | Infra (RLS review) | `supabase/20260319_ai_insights.sql` |
| Edge Function: `generate-ai-insights` | Data & Backend | Infra (secrets) | `supabase/functions/generate-ai-insights/index.ts` |
| Admin API: insights + chat actions | Data & Backend | Product Engineer | `admin-cms/src/app/api/admin/route.ts` |
| Chat streaming API | Product Engineer | Infra (auth review) | `admin-cms/src/app/api/ai-chat/route.ts` |
| AI Insights Hub page | Product Engineer | — | `admin-cms/src/app/insights/page.tsx` |
| ANTHROPIC_API_KEY secret | Infra & Security | — | Supabase Vault + `.env.local` |

### Workflow: Updating AI Insights
```
1. Data Agent maintains the platform data queries in the Edge Function
2. If new tables/metrics are added to the platform, Data Agent updates collectPlatformData()
3. Product Engineer maintains the CMS UI and chat experience
4. Infra Agent owns the API key rotation and security review
5. To add a new insight category: update the SQL CHECK constraint + Edge Function + CMS filter tabs
```

---

## Performance Audit Remediation (March 2026)

**Audit date**: March 20, 2026
**Overall grade**: B+ → targeting A after SQL migrations are executed

### Blocking Issues Created & Resolved
| Issue | Migration File | Status |
|-------|---------------|--------|
| `exercise_performance_history` missing columns | `20260320_fix_performance_history.sql` | Created — needs SQL execution |
| `collaborative_workout_data` missing `program_id` | `20260320_fix_performance_history.sql` | Created — needs SQL execution |
| 7 analytics tables missing RLS | `20260320_fix_rls_policies.sql` | Created — needs SQL execution |
| PR detection not implemented | `ActiveWorkoutView.swift` | FIXED in code |
| Friend search not wired | `ShareWorkoutSheet.swift` | FIXED in code |

### Remaining Items (Not Blocking)
- 3 TODO comments: AdMob production ID (external), 2x SmartProgramRecommender delegation (architecture)
- 14 duplicate SQL function definitions (cleanup task)
- Performance baseline verification (Dec 2025 vs current)
- APM monitoring not yet implemented

---

## Smart Treadmill Auto-Connect (March 2026)

| Component | Owner | File |
|-----------|-------|------|
| RSSI averaging + auto-suggest logic | Product Engineer | `BluetoothFitnessManager.swift` |
| Device memory persistence | Product Engineer | `BluetoothFitnessManager.swift` (AppStorage) |
| Auto-suggest banner + signal UI | Product Engineer + Design | `FitnessEquipmentView.swift` |
| BLE permissions review | Infra & Security | Advisory |
| Battery impact validation | Quality & Performance | Advisory |
