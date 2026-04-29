# Fit33 Engineering Team Structure

> **Lead iOS Engineer's Playbook**: Team of specialized AI agents, their roles, ownership boundaries, and how they interact.

---

## Doc Architecture (read this first)

We follow a **three-layer** pattern (rules → current-agent → history):

1. **`.cursor/rules/*.mdc`** — auto-loaded rules.
   - `codingrules.mdc` (`alwaysApply: true`) — universal, cross-cutting rules that apply to every agent (logging, force-unwraps, design tokens, structured concurrency, accessibility, migration layout, etc.).
   - `swiftui-rules.mdc` (globs `Fit33/**/*.swift`) — Swift / SwiftUI invariants.
   - `supabase-rules.mdc` (globs `supabase/**/*.sql`, `supabase/functions/**/*.ts`) — RLS / RPC / migration invariants.
   - `admin-cms-rules.mdc` (globs `admin-cms/**`) — CSP / cookie / deploy invariants.
   - When you edit a file in a matching glob, that scoped rule file loads automatically. Don't duplicate these rules in agent docs.
2. **`*_AGENT.md`** (this directory) — short, rule-shaped "Invariants + Map" per agent. Each file opens with numbered invariants ("what will cause bugs if violated"), then canonical tokens / map / files, then a "See Also" footer. Typical length: 100–250 lines.
3. **`docs/history/*_AGENT.md`** — original long-form history (sprint changelogs, dated decisions, migration notes, audit logs). Referenced by each current agent doc. Read these ONLY when you need dated context — they are not loaded into every turn.

**Consult-the-agents workflow:**
1. Before making a change in an agent's domain, read their `*_AGENT.md` (fast — it's short).
2. Apply the invariants in that file PLUS whichever scoped rule auto-loaded for the file type you're editing PLUS the universal rules in `codingrules.mdc`.
3. If you need historical context (why was this decision made? what migration shipped when?), open `docs/history/`.
4. After shipping a change, update docs at the right layer:
   - New rule-shaped invariant for ONE file type (Swift / SQL / CMS) → the matching scoped rule file.
   - Cross-cutting invariant → `codingrules.mdc`.
   - Agent-specific need-to-know (new canonical model / service ownership) → the current `*_AGENT.md`.
   - Dated narrative / audit / migration notes → append to `docs/history/*_AGENT.md`.

---

## The Team

| Agent | File | Domain | One-line |
|---|---|---|---|
| Lead Designer | `DESIGN_AGENT.md` | Visual identity, UI specs, design tokens | "What it should look like" |
| Lead Product Engineer | `PRODUCT_ENGINEER_AGENT.md` | Features, navigation, component reuse, state | "How it should work" |
| Staff Infra & Security | `INFRA_SECURITY_AGENT.md` | Secrets, auth, CI/CD, edge function access, compliance | "How it stays safe" |
| Staff Data & Backend | `DATA_BACKEND_AGENT.md` | Supabase schema, RLS, RPCs, Core Data, DTOs | "How data flows correctly" |
| Staff Quality & Performance | `QUALITY_PERFORMANCE_AGENT.md` | Testing, memory, performance, accessibility, stability | "How it stays stable" |
| Staff Bug Intelligence | `BUG_INTELLIGENCE_AGENT.md` | Bug-detection / classification / triage / resolution pipeline (`bug_intelligence_*` + `bug_intel_*` + `triage-bugs` + iOS classifier chain + CMS export) | "How we'll know when something breaks" |
| Staff Design System Enforcement | `DESIGN_SYSTEM_AGENT.md` | Token migration, dedup, metrics | "How the design gets into the code" |
| Staff Fitness Expert | `FITNESS_EXPERT_AGENT.md` | Exercise science, program design, workout validation | "What the workout should actually be" |
| Staff Device Compatibility | `DEVICE_COMPATIBILITY_AGENT.md` | Responsive layout, iPad, Apple Watch planning | "How it fits every screen" |
| Staff Supabase Database Expert | `SUPABASE_AGENT.md` | Table relationships, migration safety, data integrity | "How the database stays clean" |
| Staff Support & Knowledge | `SUPPORT_AGENT.md` | User-facing knowledge, FAQ, pain points | "How users understand the app" |
| Staff Monetization & Finance | `MONETIZATION_AGENT.md` | Revenue strategy, premium conversion, IAP plumbing, ad inventory, CMS `/revenue` tab | "How the app makes money — sustainably" |

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
| StoreKit integration | Monetization | Product Engineer (Swift impl), Infra (receipt validation) |
| Pricing decision (monthly / yearly / lifetime / intro / promo) | Monetization | — |
| Paywall placement / copy / surface | Monetization | Lead Designer (visual), Support (copy) |
| Free vs Premium-gate vs Ad-gate decision on a feature | Monetization | Owning agent (feature-specific) |
| Ad cadence / placement / surface | Monetization | Quality & Performance (perf impact) |
| App Store Server Notifications v2 webhook | Monetization | Infra & Security (auth + crypto), Supabase Expert (schema) |
| `subscriptions` / `iap_receipts` / `subscription_grants` schema | Monetization | Supabase Expert (writes SQL), Data Backend (DTOs) |
| Refund / chargeback / comp-grant flow | Monetization | Support (user comms) |
| Churn-save / win-back offer (Apple Promotional Offer JWS) | Monetization | Infra (JWS signing key) |
| Paywall A/B experiment | Monetization | Quality & Performance (rollout safety), Data Backend (cohort math) |
| AdMob account config / mediation | Monetization | — |
| ATT prompt timing | Monetization | Product Engineer (call-site placement) |
| App Store Review 3.1.x rejection | Monetization | Infra (if 3.1.3+ multiplatform) |
| COPPA / GDPR-K (under-13 ad policy) | Monetization | Infra & Security |
| Competitor pricing matrix refresh | Monetization | — |
| `iapPurchase` op + classifier wiring in StoreKitManager | Monetization | Bug Intelligence (op registration) |
| CMS `/revenue` Overview / Subscribers / Transactions / Grants / Experiments | Monetization | Infra (audit log + role gating) |
| Per-user grant / revoke / extend / refund-ack action | Monetization | Infra (admin role check) |
| Privacy manifest ad-tracking domains | Monetization | Infra & Security |
| EU DMA / US Epic web payment link disclosure | Monetization | Infra & Security (legal review) |
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
| New error catch block / classifier coverage | Bug Intelligence | Quality & Performance |
| New screen → ScreenCodeMap entry | Bug Intelligence | Product Engineer |
| `bug_intelligence_*` schema change | Bug Intelligence | Supabase Expert, Data |
| `bug_intel_*` RPC change | Bug Intelligence | Supabase Expert |
| `triage-bugs` / `triage-shake-reports` edge function | Bug Intelligence | Infra (auth), Data (DTOs) |
| `bug_intel_noise_filter` denylist tuning | Bug Intelligence | Quality & Performance |
| `NetworkErrorClassifier` / `DiagnosticContext` / `AppLogger` | Bug Intelligence | Quality & Performance |
| `CrashReportingService` / `BugReportStateSnapshot` | Bug Intelligence | Quality & Performance |
| Migration `Resolves:` directive replay | Bug Intelligence | Supabase Expert |
| CMS `/bug-intelligence` export schema | Bug Intelligence | Data |
| New transient-by-design failure mode | Bug Intelligence | Quality & Performance |
| `class=unknown` heuristic gap | Bug Intelligence | Data |
| Pipeline phase migration (collapse/classify/score/resolve) | Bug Intelligence | Supabase Expert |

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
| `StoreKitManager.swift` | Monetization | Product Engineer | StoreKit 2 wrapper + entitlement refresh |
| `PremiumUpgradeView.swift` | Monetization | Lead Designer | Paywall sheet + 14-feature gates |
| `AdManager.swift` | Monetization | Quality & Performance | AdMob lifecycle + cadence + ATT |
| `PremiumManager` (in `UserManager.swift`) | Monetization | Product Engineer | Gate-check API surface |
| `admin-cms/src/app/revenue/**` | Monetization | Infra (audit + role gating) | CMS Revenue tab |

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
- Bug-intel pipeline (`bug_intelligence_*`, `triage-bugs`, classifier, ScreenCodeMap, CMS export) → Bug Intelligence
- Token migration → Design System Enforcement
- Exercise / workout / program logic → Fitness Expert
- Layout / device / iPad / Watch planning → Device Compatibility
- User questions / FAQ / pain points → Support & Knowledge
- Pricing / paywall / IAP / ads / refunds / `/revenue` CMS tab → Monetization & Finance

---

## Top-Level Invariants (reminder — all covered in `.cursor/rules/*.mdc`)

> These duplicate-by-reference only. The rule files are the source of truth.
> `codingrules.mdc` is universal; `swiftui-rules.mdc`, `supabase-rules.mdc`,
> and `admin-cms-rules.mdc` auto-load when matching globs are edited.

1. `AppLogger` only — never `print()`. *(swiftui-rules.mdc)*
2. No force unwraps in production. *(swiftui-rules.mdc)*
3. Design tokens only — no `.system(size:)` inline, no hardcoded padding/radius. Local `cardBackground` view-builders are fine as long as they use `Color.cardBackground` as their underlying fill. *(swiftui-rules.mdc)*
4. Structured concurrency — `Task { }` with `Task.sleep(for:)`, never `DispatchQueue.main.asyncAfter`. *(swiftui-rules.mdc)*
5. Accessibility on every interactive element. *(swiftui-rules.mdc)*
6. RLS on every user-data table. Views use `security_invoker = on`. SECURITY DEFINER RPCs derive the acting user from `auth.uid()` and IDOR-guard any `user_id` parameter (see Sprint 6 / Sprint 7 migrations). *(supabase-rules.mdc)*
7. Widget isolation in ScrollViews with 5+ siblings. *(swiftui-rules.mdc)*
8. No sync Core Data in `init()` or `.task`. *(swiftui-rules.mdc)*
9. JSONSerialization safety — always `isValidJSONObject` first. *(swiftui-rules.mdc)*
10. AVFoundation + GenderFilterService off the main thread. *(swiftui-rules.mdc)*
11. Realtime tables must have `REPLICA IDENTITY FULL` AND be registered in the `supabase_realtime` publication. *(supabase-rules.mdc)*
12. Admin CMS: CSP **only in `middleware.ts`** (per-request nonce + `strict-dynamic`); `next.config.ts` intentionally omits it (Sprint 5 / Q2-20 — two sources fight and silently regress to `'unsafe-inline'`). httpOnly Secure SameSite=Strict cookies. *(admin-cms-rules.mdc + INFRA_SECURITY_AGENT.md #23)*

---

*This structure ensures every aspect of the app has a clear owner. No task falls through the cracks. The Lead iOS Engineer orchestrates — the agents execute.*
