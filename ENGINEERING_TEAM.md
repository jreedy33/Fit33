# Fit33 Engineering Team Structure

> **Lead iOS Engineer's Playbook**: Team of specialized AI agents, their roles, ownership boundaries, and how they interact.

---

## Doc Architecture (read this first)

We follow a two-layer pattern:

1. **`.cursor/rules/codingrules.mdc`** — universal rules that apply to EVERY agent (logging, force-unwraps, design tokens, structured concurrency, accessibility, RLS, SECURITY DEFINER views, Core Data threading, widget isolation, UserDefaults, video player threading, startup perf). Loaded automatically every turn. Don't duplicate these rules in agent docs.
2. **`*_AGENT.md`** (this directory) — short, rule-shaped "Invariants + Map" per agent. Each file opens with numbered invariants ("what will cause bugs if violated"), then canonical tokens / map / files, then a "See Also" footer. Typical length: 150–250 lines.
3. **`docs/history/*_AGENT.md`** — original long-form history (sprint changelogs, dated decisions, migration notes, audit logs). Referenced by each current agent doc. Read these ONLY when you need dated context — they are not loaded into every turn.

**Consult-the-agents workflow:**
1. Before making a change in an agent's domain, read their `*_AGENT.md` (fast — it's short).
2. Apply the invariants in that file PLUS the universal rules in `codingrules.mdc`.
3. If you need historical context (why was this decision made? what migration shipped when?), open `docs/history/`.
4. After shipping a change, update the relevant `*_AGENT.md` ONLY if the change introduces a new need-to-know fact. Append dated changelog entries to `docs/history/` instead.

---

## The Team

| Agent | File | Domain | One-line |
|---|---|---|---|
| Lead Designer | `DESIGN_AGENT.md` | Visual identity, UI specs, design tokens | "What it should look like" |
| Lead Product Engineer | `PRODUCT_ENGINEER_AGENT.md` | Features, navigation, component reuse, state | "How it should work" |
| Staff Infra & Security | `INFRA_SECURITY_AGENT.md` | Secrets, auth, CI/CD, edge function access, compliance | "How it stays safe" |
| Staff Data & Backend | `DATA_BACKEND_AGENT.md` | Supabase schema, RLS, RPCs, Core Data, DTOs | "How data flows correctly" |
| Staff Quality & Performance | `QUALITY_PERFORMANCE_AGENT.md` | Testing, memory, performance, accessibility, stability | "How it stays stable" |
| Staff Design System Enforcement | `DESIGN_SYSTEM_AGENT.md` | Token migration, dedup, metrics | "How the design gets into the code" |
| Staff Fitness Expert | `FITNESS_EXPERT_AGENT.md` | Exercise science, program design, workout validation | "What the workout should actually be" |
| Staff Device Compatibility | `DEVICE_COMPATIBILITY_AGENT.md` | Responsive layout, iPad, Apple Watch planning | "How it fits every screen" |
| Staff Supabase Database Expert | `SUPABASE_AGENT.md` | Table relationships, migration safety, data integrity | "How the database stays clean" |
| Staff Support & Knowledge | `SUPPORT_AGENT.md` | User-facing knowledge, FAQ, pain points | "How users understand the app" |

---

## Ownership Matrix (route tasks here)

| Task | Primary | Supporting |
|---|---|---|
| New UI screen | Product Engineer | Design |
| Fix a crash | Quality & Performance | Data (if data-related) |
| Add API endpoint | Data & Backend | Infra (security review) |
| Move secrets out of source | Infra & Security | — |
| Hardcoded fonts → tokens | Design System Enforcement | Design |
| Add RLS to a table | Data & Backend | Infra (policy review) |
| Memory leak | Quality & Performance | — |
| Accessibility labels | Quality & Performance | Design (label text) |
| CI pipeline | Infra & Security | — |
| Haptics | Design System Enforcement | Design |
| Navigation inconsistency | Product Engineer | Design |
| Offline support | Product Engineer | Data (queue persistence) |
| Unit tests | Quality & Performance | Data (fixtures) |
| Admin CMS vulnerability | Infra & Security | — |
| New database table | Supabase Expert | Data (implementation), Infra (RLS) |
| Perf optimization | Quality & Performance | — |
| StoreKit integration | Product Engineer | Infra (receipt validation) |
| Exercise pairing / substitution | Fitness Expert | Product Engineer |
| Program split recommendations | Fitness Expert | Data |
| Workout sorting / ordering | Fitness Expert | Product Engineer |
| Exercise database curation | Fitness Expert | Data |
| Auto-gen workout validation | Fitness Expert | Quality (regression tests) |
| Fix device-specific layout | Device Compatibility | Product Engineer |
| iPad layout adaptation | Device Compatibility | Design, Product Engineer |
| Responsive spacing audit | Device Compatibility | Design System |
| Cross-device testing | Device Compatibility | Quality |
| Apple Watch planning | Device Compatibility | Fitness Expert |
| FK/RLS constraint review | Supabase Expert | Infra |
| Dead-table cleanup | Supabase Expert | Data |
| FAQ content | Support | Product Engineer |
| Pain-point tracking | Support | Quality |
| Bug-to-feature mapping | Support | Product Engineer |
| Content moderation pipeline | Infra & Security | Data, Product Engineer |
| Blocking + reporting UI | Product Engineer | Data, Design |
| Offline retry queue | Product Engineer | Quality |
| Notification type allowlist | Quality & Performance | Product Engineer, Data |
| Cardio XP parity | Product Engineer | Fitness Expert, Data |
| HealthKit observer ownership | Quality & Performance | Product Engineer |
| Video prefetch gating | Quality & Performance | — |
| AVAudioSession refcounting | Quality & Performance | — |
| Reduce-motion enforcement | Quality & Performance | Design System |
| Admin CMS cookie hardening | Infra & Security | Product Engineer |

---

## Shared File Ownership

| File | Primary | Co-owner | Notes |
|---|---|---|---|
| `DesignSystem.swift` | Design | Design System | Tokens defined + enforced |
| `AdaptiveColors.swift` | Design | Product Engineer | Colors + orb + sleekCard |
| `SharedUtilities.swift` | Product Engineer | Design System | Utilities + dedup |
| `SupabaseManager.swift` | Data | Infra | Ops + auth/credentials |
| `AppConfig.swift` | Infra | — | Config |
| `SECURITY_CHECKLIST.md` | Infra | Data, Supabase | Policy + impl + validation |
| `MASTER_TODO.md` | All | — | |
| `WorkoutComboRules.swift` | Fitness Expert | Product Engineer | Rules + impl |
| `SmartExerciseSelectionEngine.swift` | Product Engineer | Fitness Expert | Logic + scoring validation |
| `SmartExercisePairingEngine.swift` | Fitness Expert | Product Engineer | Pairings + UI |
| `DynamicProgramGenerator.swift` | Fitness Expert | Product Engineer, Data | Splits + templates |
| `ExerciseBundleEngine.swift` | Fitness Expert | Product Engineer | Bundle definitions |
| `ProgramTemplateLibrary.swift` | Fitness Expert | Data | Periodization + sync |
| `NewOnboardingView.swift` | Product Engineer | Data, Infra | Flow + profile + auth |
| `PhoneVerificationSheet.swift` | Product Engineer | Infra | UI + security |
| `ContactsService.swift` | Data | Product Engineer | Normalization + UI |
| `OrientationManager.swift` | Device Compatibility | Product Engineer | Device detection |
| `FAQ_PLAN.md` | Support | All | FAQ content plan |
| `Website/help-center.html` | Support | Infra (deploy) | Public help center |

---

## Workflows

### Building a new feature
1. Product Engineer reads requirements.
2. Read `DESIGN_AGENT.md` for visual specs.
3. Select components from shared inventory.
4. If data is involved: Supabase Expert checks existing schema → designs minimal schema change → Data Agent implements DTOs + sync → Infra reviews security.
5. Product Engineer builds using shared components.
6. Design System audits token usage.
7. Quality runs functional + memory + accessibility + error-handling checklist.
8. Support updates FAQ + feature docs.
9. Ship.

### Fixing a bug
1. Quality triages (crash / perf / data / UI).
2. Route to the right agent.
3. Owning agent implements fix.
4. Quality verifies no regression.
5. Support updates FAQ if behavior changed.

### Design System migration sprint
1. Design System picks token type (e.g., typography).
2. Pick highest-violation file.
3. Map each inline → nearest token (consult Design if no clean match).
4. 20-50 replacements per commit; one token type per commit.
5. Quality verifies light + dark + Dynamic Type.
6. Update metrics.

---

## Conflict Resolution
- **Performance > animation complexity.** Drop below 60fps → simplify.
- **Consistency > uniqueness.** Use the standard pattern even if custom "looks better" on one screen.
- **Shared component > inline code.** Extend, don't duplicate.
- **Security wins over speed.** Never skip a security step to ship faster.
- **Design Agent is the authority on token values.** They decide what 14pt rounds to.
- **Design System Agent is the authority on migration order.**
- **Quality is the authority on visual regressions.**

---

## Agent Quick-Reference

- **Should I use a design token?** → YES. Always.
- **Should I add a new shared component?** → Only if the pattern appears 3+ times.
- **Should I fix an unrelated bug I noticed?** → If in your domain and < 5min, yes. Else add to `MASTER_TODO.md`.

### Who do I ask about...?
- Visual decisions → Design
- Navigation + widgets → Product Engineer
- Security / secrets / edge functions → Infra & Security
- DTOs / RPCs / realtime / Core Data contexts → Data & Backend
- Schema / table design / migrations → Supabase Expert
- Performance / crashes / accessibility → Quality & Performance
- Token migration → Design System Enforcement
- Exercise / workout / program logic → Fitness Expert
- Layout / device / iPad / Watch planning → Device Compatibility
- User questions / FAQ / pain points → Support & Knowledge

---

## Top-Level Invariants (reminder — all covered in `codingrules.mdc`)

1. `AppLogger` only — never `print()`.
2. No force unwraps in production.
3. Design tokens only — no `.system(size:)` inline, no hardcoded padding/radius, no local `cardBackground`.
4. Structured concurrency — `Task { }` with `Task.sleep(for:)`, never `DispatchQueue.main.asyncAfter`.
5. Accessibility on every interactive element.
6. RLS on every user-data table. Views use `security_invoker = on`. SECURITY DEFINER RPCs use `auth.uid()`, never `user_id` parameter.
7. Widget isolation in ScrollViews with 5+ siblings.
8. No sync Core Data in `init()` or `.task`.
9. JSONSerialization safety — always `isValidJSONObject` first.
10. AVFoundation + GenderFilterService off the main thread.

---

*This structure ensures every aspect of the app has a clear owner. No task falls through the cracks. The Lead iOS Engineer orchestrates — the agents execute.*
