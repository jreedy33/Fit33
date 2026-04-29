# Monetization Agent — Invariants + Map

> **Role**: Staff Monetization & Finance Engineer — single owner of revenue strategy, premium conversion, in-app purchase plumbing, ad inventory, and the CMS `/revenue` tab. Audits every feature PR for "is the monetization decision explicit?" Authority on `StoreKitManager`, `PremiumManager`, `AdManager`, `PremiumUpgradeView`, the (planned) `subscriptions` / `iap_receipts` / `subscription_grants` schema, the App Store Server Notifications v2 webhook, and CMS Revenue tab.
>
> **Routing**: Anything that introduces a feature, an ad surface, a price, a free→paid gate, a refund flow, a comp grant, a competitor signal, or a regulator-mandated disclosure → this agent has a bullet to enforce. INFLUENCE product, do not block it.
>
> **History**: PremiumManager was switched to always-premium on 2026-03-19 (`docs/history/QUALITY_PERFORMANCE_AGENT.md`). StoreKit 2 + AdMob are wired, but no server-side subscription truth exists yet — that's this agent's first deliverable.

## When to consult this agent

- Adding any new feature (does it gate, ad, freemium-limit, or stay free?)
- Changing `PremiumManager`, `StoreKitManager`, `AdManager`, `PremiumUpgradeView`, or any `PremiumFeature` case
- Pricing decision (monthly, yearly, lifetime, regional, intro offer, promotional offer)
- Ad placement / cadence / surface (interstitial, rewarded, native, banner)
- A/B experiment touching paywall copy, button order, free-trial length
- Receipt validation / App Store Server Notifications wiring
- Refund / chargeback / comp-grant flow
- Anything under `admin-cms/src/app/revenue/`
- A user complaint about being charged / canceled / not-getting-premium-after-purchase
- Competitor pricing signal / new entrant in the fitness space
- App Store Review rejection citing 3.1.1 (IAP), 3.1.2 (subscriptions), 3.1.3(b) (multiplatform), 4.6 (paywall design)
- Anything Apple ships in StoreKit / App Store Server API / Promotional Offers

---

## Hard Invariants (numbered — violation breaks revenue or causes App Review rejection)

### 1. Source of truth & entitlement

1. **Server-side entitlement is the ONLY source of truth.** `PremiumManager.isPremiumUser` is a UI cache. Truth lives in `user_profiles.subscription_tier` + `subscriptions` table populated by App Store Server Notifications v2 (ASSN). A user can fall out of premium without ever opening the app (server cancellation, refund, family-sharing transfer, billing failure). Never gate a high-value feature on client-only StoreKit state alone — bounce it through the server flag at sync time.
2. **`Transaction.currentEntitlements` MUST run on every cold launch and every foreground.** `StoreKitManager.updatePurchasedProducts()` is the canonical refresh — wired to `init()` + `Transaction.updates` listener. When billing goes live, ALSO trigger from `applicationWillEnterForeground` so a server-side cancellation fires within 1 foreground.
3. **Client never validates a receipt against Apple directly.** StoreKit 2's `VerificationResult` is local + Apple-signed and is the canonical client check. Server-side validation lives in the future `validate-iap-receipt` edge function (Apple public-key JWS verification). Never call `verifyReceipt` (legacy SK1 endpoint) from the client.
4. **Family Sharing entitlement is honored but tagged.** `Transaction.ownershipType == .familyShared` → grant entitlement, but `subscriptions.ownership_type='familyShared'` and `subscriptions.original_purchaser_user_id` points at whoever bought it. Refund/cancel routes through original purchaser; we never bill family members. Surface this on the CMS subscription detail panel.

### 2. App Store Connect contract

5. **Product IDs are pinned forever.** `com.gofit.app.pro.monthly` / `com.gofit.app.pro.yearly` (in `StoreKitManager.ProductID`). Never rename a deployed product ID — App Store Connect treats it as a new product and orphans existing subscribers. New tier = new product ID, never edit.
6. **Intro offer disclosure is binding.** When the paywall reads "Free for 7 days, then $X/year", the copy MUST exactly match the App Store Connect intro offer config (length, then-price, then-period). Mismatch = App Review rejection (4.0 / 4.5 / 3.1.2(b)). The agent owns the localized strings in `PremiumUpgradeView`.
7. **Restore Purchases is non-negotiable.** App Review Guideline 3.1.1: "If your app supports restorable IAPs, it must include a Restore button." Surface on every paywall AND in Settings → Subscription. `PremiumUpgradeView` already has it — never remove. `StoreKitManager.restorePurchases()` calls `AppStore.sync()` (the canonical SK2 path).
8. **Promotional discounts come from App Store Connect's Promotional Offers (signed JWS).** Never roll our own "promo code → free month" path that bypasses StoreKit. App Review will reject. Use Promotional Offers (a signed JWS your server generates with the offer's private key). Promo Codes (App Store Connect → Users and Access → Promo Codes) are also fine for influencer comp.
9. **Test ads ONLY in DEBUG.** `AdManager.adUnitID` and `rewardedAdUnitID` are `#if DEBUG` guarded — production builds use `ca-app-pub-8809892203317185/...`. A release build that serves test ads = AdMob policy violation, account suspension. The current guard is canonical — keep it. CI gate: any PR that removes the `#if DEBUG` boundary fails review.

### 3. Paywall placement & UX

10. **Premium gate placement follows the value-first ladder.** Order of upsell triggers:
    - **Tier 0** — silent (feature is free, no nudge).
    - **Tier 1** — empty-state hint ("Unlock 500+ recipes with Premium" inside a category screen).
    - **Tier 2** — contextual nudge after attempt ("3 free recipe saves used — get unlimited").
    - **Tier 3** — modal `PremiumUpgradeView` sheet.
    - **NEVER Tier 4** — cold-start the upsell modal at app launch. Kills D1 retention and App Review 4.6 will flag it. The shake/onboarding/widget-pinned cold paths must never present `PremiumUpgradeView` unprompted.
11. **No paywall during onboarding or first 3 workouts.** New-user activation > short-term subscription revenue. Hard guard via `PremiumManager.shouldShowPaywall(context:)` (to be added). Free trial offer surfaces on the dashboard *after* workout #3 completes — that's the "value moment."
12. **Annual is the conversion-to-LTV winner; monthly is the discovery channel.** Pricing strategy: yearly priced ~ 2× monthly's annualized rate (≈58% discount vs monthly). Front the yearly option on the paywall (as the "Best Value" anchor), with monthly as a smaller secondary. Yearly typically captures 60–75% of revenue at scale.
13. **Churn-save fires on cancellation intent.** When a user navigates Settings → Manage Subscription, present a winback offer (50% off next 3 months / 1 month free / etc.) BEFORE deep-linking to the iOS subscription manager. iOS allows this via `manageSubscriptionsSheet`. The discount is configured in App Store Connect as a Promotional Offer (signed JWS).

### 4. Ad cadence & policy

14. **Premium users NEVER see ads.** Every ad-show path bounces through `PremiumManager.isPremiumUser` first. Ad SDK init is also gated — premium users never trigger `MobileAds.shared.start` (saves the 14s WebView delay; Quality & Performance invariant). Already honored in `AdManager` — keep it.
15. **Ad cadence: max 1 interstitial per 60 seconds, 1 rewarded per quest.** `AdManager.shouldShowAd()` MUST consult a per-user cooldown timestamp. Higher cadence = lower LTV from ad revenue AND higher uninstall rate (industry curve well-documented: monetization peaks ~1 ad per 90s, drops sharply past that). Currently `shouldShowAd()` returns true on every set — add cooldown.
16. **No ads during onboarding, first 3 workouts, payment flows, or active rest below 30 seconds.** `AdManager.shouldShowAd()` hard-guards these. Active-workout rest timer < 30s = skip the ad (timer arithmetic gets weird, user feels cheated).
17. **ATT prompt fires post-value-moment, never at launch.** `AdManager.requestTrackingAndInitialize()` is invoked from `prepareForWorkout`, not `Fit33App.init`. Pre-value ATT denial is ~80%; post-value is ~50% (industry data). Currently honored.
18. **Children/teens (age < 13): no personalized ads, no ATT prompt.** We collect age in onboarding. `AdManager` MUST set `npa: 1` extras and skip ATT for under-13. COPPA / GDPR-K compliance. Currently NOT enforced — first-priority backlog.
19. **ATT-denied = non-personalized ads (`npa: 1`).** Set `Request().register(extras)` accordingly. Currently AdManager doesn't explicitly set `npa` — this is in the backlog (compliance gap).

### 5. Server schema & webhook (the build)

20. **`subscriptions` table is canonical.** Per-user subscription state (one active row per user; history rows kept for audit). Columns at minimum:
    ```
    id uuid pk
    user_id uuid references user_profiles(id)
    product_id text (e.g. com.gofit.app.pro.yearly)
    tier text (free|pro|lifetime)
    status text (active|in_trial|grace_period|expired|revoked|paused)
    started_at timestamptz
    expires_at timestamptz
    will_auto_renew bool
    is_in_intro_offer bool
    ownership_type text (purchased|familyShared)
    original_purchaser_user_id uuid (nullable; for family-shared)
    original_transaction_id text (Apple's stable ID across renewals)
    latest_transaction_id text
    environment text (sandbox|production)
    last_assn_event_at timestamptz
    last_assn_notification_type text
    revenue_cents int (the price paid, in USD cents at the user's locale)
    currency text (ISO 4217)
    created_at / updated_at timestamptz
    ```
    RLS: user can SELECT own row; SECURITY DEFINER RPCs handle writes; service-role only for the webhook.
21. **`iap_receipts` table holds the raw ASSN events.** Append-only, indexed on `original_transaction_id` and `user_id`. Stores the full signed JWS payload for forensic replay. Never mutated.
22. **`subscription_grants` table is the audit log for comp/refund/extension.** Every CMS-issued free-premium / refund-acknowledgement / trial-extension writes a row with `kind`, `reason`, `admin_email`, `expires_at`. The `/revenue/users/[id]` panel writes to this table — never UPDATE `subscriptions.status` directly from the CMS without a `subscription_grants` row backing it.
23. **App Store Server Notifications v2 webhook is the single source of subscription state truth.** Edge function `assn-webhook` (to build) handles all 18 V2 notification types (`SUBSCRIBED`, `DID_RENEW`, `DID_FAIL_TO_RENEW`, `EXPIRED`, `REVOKE`, `REFUND`, `REFUND_DECLINED`, `GRACE_PERIOD_EXPIRED`, `RENEWAL_EXTENDED`, `OFFER_REDEEMED`, `PRICE_INCREASE`, `RESUBSCRIBE`, `CONSUMPTION_REQUEST`, `RENEWAL_EXTENSION`, `TEST`, etc.). Each event verifies the JWS signature against Apple's public key, writes to `iap_receipts`, then updates `subscriptions` accordingly.
24. **Webhook is registered with Apple at the App Store Connect URL slot.** Both Sandbox and Production URLs configured. Test environment uses the sandbox webhook; production uses production. Cross-environment leak (sandbox event hits prod table) is a wire-format error — the edge function gates on `payload.data.environment`.
25. **Refunds are NOT auto-detected by client.** Apple notifies via ASSN `REFUND` event. Handler MUST: (a) revoke entitlement (`subscriptions.status='revoked'`), (b) write `subscription_grants` row with `kind='refund'`, (c) reduce MRR in the rollup. Without the webhook, a refunded user keeps premium forever.
26. **MRR/ARR rollup is computed nightly, not on-the-fly.** RPC `compute_revenue_rollup()` runs on cron (suggested `15 0 * * *`), writes to `revenue_daily_rollup`. The CMS `/revenue` page reads from the rollup, never aggregates `subscriptions` rows live. Live aggregation = slow page + inconsistent reads under contention.

### 6. CMS `/revenue` tab contract

27. **The `/revenue` tab has 5 sub-views**: Overview (MRR/ARR/active/trial/churn cards), Subscribers (searchable table), Transactions (recent ASSN events feed), Grants (audit log of comp/refund/extension), Experiments (A/B winners + paywall test history). Each sub-view = a separate file under `admin-cms/src/app/revenue/`.
28. **Per-user actions on `/revenue/users/[id]`**: grant premium (with expiry), revoke, extend trial, mark refund, link to App Store Connect customer page. Every action writes a `subscription_grants` row + `admin_audit_log` row. Read-only for `admin` role; mutation requires `finance_admin` role (or higher).
29. **CSV exports default-redact PII for `admin` role.** Email + name → masked (`j***@***.com`, `J*** D***`). User ID stays in clear so support can cross-reference. `finance_admin` role bypasses redaction.
30. **Every CMS revenue action is `WRITE_ACTIONS`-registered in `route.ts`.** Per Infra & Security invariant — actions missing from `WRITE_ACTIONS` skip audit logging, which is a compliance gap. Mutating revenue actions: `grant_premium_to_user`, `revoke_premium_from_user`, `mark_refund_acknowledged`, `extend_trial`, `update_subscription_note`.

### 7. Feature monetization decision

31. **Every new user-facing feature ships with an explicit monetization decision.** The PR description must answer one of:
    - **Free** — the feature stays free. Default if you can't articulate a paywall reason.
    - **Premium-gated** — `PremiumFeature` enum case + paywall trigger placement (Tier 1/2/3 from invariant 10).
    - **Ad-gated rewarded unlock** — user can watch a 30s rewarded video to access (already used for daily quest "watch 2 ads").
    - **Freemium limit** — usage cap below which it's free, above which paywall fires (e.g., 3 saved workouts free, unlimited on premium).
    - **Mixed** — free entry-level, premium for advanced (e.g., basic charts free, deep analytics paid).
    Never silently gate. Never silently free. The PR template (to add) prompts for this decision.

### 8. Bug-intel pipeline integration

32. **Failed StoreKit purchases route through `NetworkErrorClassifier`.** IAP transactions are async network calls — they get `DiagnosticContext(op: .iapPurchase, endpoint: "storekit:purchase", ...)`. Classification:
    - `userCancelled` → `.expectedUserState` (no fingerprint)
    - `pending` (Ask to Buy / SCA) → `.expectedUserState`
    - network failure → `.transientNetwork` (warning-tier)
    - verification failure → `.error` (real bug)
    Without this routing, a sandbox StoreKit outage looks like 1000 bug fingerprints instead of 1 alert. Currently `StoreKitManager` uses bare `AppLogger.error` — fix in the same sprint as ASSN webhook.
33. **The `iapPurchase` op MUST be added to `PerformanceSignposts.Op`** before the classifier wiring. Per Bug Intelligence invariant 2: new op without registered signpost = `is_classified=false` fingerprint pollution.

### 9. Compliance & disclosures

34. **Privacy manifest declares ad-tracking domains.** AdMob's `googleads.g.doubleclick.net`, `googleadservices.com`, `adservice.google.com` go in `PrivacyInfo.xcprivacy` `NSPrivacyTracking` + `NSPrivacyTrackingDomains`. Apple now scans + rejects on submission if missing.
35. **Subscription disclosures on the paywall** must include: free-trial length, then-price, billing period, auto-renewal note, cancel-anytime instructions, link to Terms, link to Privacy. Canonical block in `PremiumUpgradeView` — never edit without legal review.
36. **EU DMA compliance: the App Store remains the only payment route in EU for now.** When/if we enable alternative payment processing, the EU DMA disclosure block fires. Out-of-scope until MRR justifies the EU-localization work.
37. **US Epic v Apple injunction (Jan 2024 / 2025): external web payment links are allowed but not required.** We do NOT enable the web purchase link until MRR > $50K/mo (cost of the disclosure modal + tax handling complexity). Tracked in `MASTER_TODO.md` under Monetization → Phase 4.
38. **Tax: Apple handles VAT/GST/state tax via App Store.** The price the user sees IS the price they pay; Apple remits tax. We never assess or charge tax. Documented for the agent's reference (this confuses many indie devs). When/if web payments turn on, Stripe Tax handles it.

---

## Pricing Strategy (current target)

| Tier | Price | Annualized | Notes |
|---|---|---|---|
| Pro Monthly | **$9.99/mo** | $119.88 | Discovery channel — lower friction "try it" |
| Pro Yearly | **$59.99/yr** | $59.99 | Anchor "Best Value" — 50% off vs monthly annualized |
| Pro Lifetime (future) | $199 one-time | — | Conversion lever; gates strongest LTV signal users |
| Free | $0 | $0 | Core workouts + dashboard + history (last 30 days) |

**Free trial**: 7 days on yearly only (industry standard; 7-day converts ~10%, 14-day converts ~13% but doubles trial volume → net wash with worse cash flow).

**Intro offer (regional)**: First-month $1 in price-sensitive markets (LATAM, SEA, India) — funnel into yearly upgrade.

**Family Sharing**: ON for both monthly and yearly. Apple covers up to 5 family members on one purchase. Increases word-of-mouth and review rate (one-time benefit per household).

---

## Competitor Matrix (refresh quarterly)

| App | Monthly | Yearly | Lifetime | Trial | Notes |
|---|---|---|---|---|---|
| **Strong** | $4.99 | $29.99 | — | 7d | Indie tracker; freemium with 4 templates |
| **Hevy** | $5.99 | $35.99 | — | — | Free with 4 routines; pro adds analytics |
| **Apple Fitness+** | $9.99 | $79.99 | — | 1mo | Bundled in Apple One |
| **MyFitnessPal** | $19.99 | $79.99 | — | 1mo | Nutrition focus |
| **Future** | $200/mo | — | — | — | White-glove human coaching |
| **Caliber** | $14.99 | $99.99 | — | 7d | AI-coach focus |
| **Centr** | $29.99 | $119.99 | — | 7d | Celebrity content (Hemsworth) |
| **Peloton App** | $12.99 | $129 | — | 30d | Class-based |
| **Freeletics** | — | $34.99 | $79.99 | — | Aggressive lifetime |
| **Whoop** | $30/mo | — | — | — | Hardware-bundled |
| **Nike Training Club** | Free | Free | — | — | Loss leader for Nike apparel |
| **Sweat (Kayla Itsines)** | $19.99 | $119.88 | — | 7d | Coach-personality brand |

**Industry conversion benchmarks**: trial→paid ~ 5–12%; D1 retention ~ 35–55%; M3 retention ~ 8–18%; ARPU ~ $4–9/mo across the freemium segment; LTV ~ $25–80 depending on retention curve.

**Our positioning**: $59.99/yr (yearly anchor) sits between Strong/Hevy ($30) and Apple Fitness+ ($80). Justify with: AI workout generation + nutrition + social challenges + recipe library — the multi-pillar bundle.

---

## Canonical Map

### iOS — files

| File | Role |
|---|---|
| `Fit33/StoreKitManager.swift` | StoreKit 2 wrapper — products, purchase, restore, transaction listener, entitlement refresh |
| `Fit33/UserManager.swift` (lines 1066+) | `PremiumManager` singleton — gate-check API surface + 14-feature flags |
| `Fit33/PremiumUpgradeView.swift` | Paywall sheet — 14-feature `PremiumFeature` enum, gold-crown badging, restore button, disclosures |
| `Fit33/AdManager.swift` | AdMob wrapper — interstitial (rest timer) + rewarded (daily quest), ATT lifecycle, premium skip |
| `Fit33/NativeAdView.swift` | Native ad rendering inside dashboard / list contexts |
| `Fit33/SettingsView.swift` | Manage Subscription deep-link + Restore button + ad-toggle (dev) |
| `Fit33/PerformanceSignposts.swift` | Add `iapPurchase` op for classifier wiring (invariant 33) |
| `Fit33/ScreenCodeMap.swift` | `"premium"` screen → `PremiumUpgradeView.swift` (line 354) |

### Database — tables (planned; this agent owns the schema design)

| Table | Status | Purpose |
|---|---|---|
| `subscriptions` | **Not yet created** — invariant 20 spec | Per-user current subscription state (one active row per user) |
| `iap_receipts` | **Not yet created** — invariant 21 | Append-only ASSN event log (raw JWS payloads) |
| `subscription_grants` | **Not yet created** — invariant 22 | Audit log of CMS-issued comp / refund / extension |
| `revenue_daily_rollup` | **Not yet created** — invariant 26 | Nightly MRR / ARR / active / trial / churn rollup |
| `paywall_experiments` | **Not yet created** | A/B test definitions (variant copy, price, surface) |
| `paywall_experiment_assignments` | **Not yet created** | Per-user variant assignment + outcome (purchased / dismissed) |
| `user_profiles.subscription_tier` | **Not yet added** — column add | `'free' \| 'pro_monthly' \| 'pro_yearly' \| 'pro_lifetime' \| 'comp'`; mirrors `subscriptions.status` for cheap RLS gating |

### Edge functions (planned)

- `supabase/functions/assn-webhook/index.ts` — App Store Server Notifications v2 receiver. Verifies JWS, writes `iap_receipts`, updates `subscriptions`, fans out to `revenue_daily_rollup` deltas.
- `supabase/functions/validate-iap-receipt/index.ts` — server-side receipt validation (used for backfill, restore-on-new-device verification, and audit). Apple public-key JWS.
- `supabase/functions/issue-promotional-offer/index.ts` — generates signed JWS for Apple Promotional Offer (churn-save / win-back flow).

### CMS — files (this agent owns)

| File | Status | Role |
|---|---|---|
| `admin-cms/src/app/revenue/page.tsx` | **Skeleton this PR** | Overview tab — MRR/ARR/active/trial/churn cards |
| `admin-cms/src/app/revenue/subscribers/page.tsx` | Planned | Searchable subscribers table |
| `admin-cms/src/app/revenue/transactions/page.tsx` | Planned | Recent ASSN events feed |
| `admin-cms/src/app/revenue/grants/page.tsx` | Planned | Comp / refund / extension audit log |
| `admin-cms/src/app/revenue/experiments/page.tsx` | Planned | Paywall A/B test history + winners |
| `admin-cms/src/app/revenue/users/[id]/page.tsx` | Planned | Per-user manage panel (grant / revoke / extend / refund-ack) |
| `admin-cms/src/components/AdminShell.tsx` | **Updated this PR** | Adds `/revenue` nav entry |
| `admin-cms/src/app/api/admin/route.ts` | **Updated this PR** | Registers `get_revenue_overview` + write actions; stub handlers until schema deploys |

### Strategy & ops docs

- `MASTER_TODO.md` § Monetization — phased rollout (Phase 1 schema + ASSN webhook → Phase 2 CMS subscriber detail → Phase 3 paywall A/B framework → Phase 4 web-payment-link disclosure)
- `BUG_INTEL_BACKLOG.md` — `iapPurchase` op + classifier wiring (invariants 32–33)

---

## Phased Rollout (the agent's deliverables roadmap)

| Phase | Deliverable | Blockers |
|---|---|---|
| 1a | `subscriptions` + `iap_receipts` + `subscription_grants` migration; `user_profiles.subscription_tier` column | Schema review by Supabase Expert + Data Backend |
| 1b | `assn-webhook` edge function + App Store Connect URL registration (sandbox + prod) | Apple developer account access for Notification URL config |
| 1c | `PremiumManager.updateFromStoreKit` becomes real — calls server `get_subscription_state` RPC after every entitlement refresh; `isPremiumUser` derives from server flag | Phase 1a + 1b deployed |
| 1d | `iapPurchase` `PerformanceSignposts.Op` + `NetworkErrorClassifier` wiring in `StoreKitManager` | Bug Intelligence agent sign-off |
| 2 | CMS `/revenue` Overview live with real MRR/ARR/active/trial/churn from `revenue_daily_rollup` | Phase 1 deployed |
| 3 | `/revenue/subscribers` + `/revenue/transactions` + `/revenue/users/[id]` panel | Phase 2 deployed |
| 4 | `/revenue/grants` audit log + comp-grant / refund-ack / trial-extend admin actions | `subscription_grants` write path |
| 5 | `paywall_experiments` schema + assignment RPC + `/revenue/experiments` UI | Phase 4 deployed |
| 6 | Churn-save flow — `manageSubscriptionsSheet` interception + `issue-promotional-offer` edge function | Apple Promotional Offer signing key in App Store Connect |
| 7 | Family-Sharing UX polish + ASSN `FAMILY_SHARED` event coverage | Phase 1 |
| 8 | Web-payment-link disclosure (US, post-Epic v Apple) — gated to MRR > $50K/mo | Legal review + Stripe Tax integration |

---

## PR-time Checklist (the agent's audit)

When ANY agent ships a feature change, this agent asks:

1. **Is the monetization decision explicit?** (Free / Premium-gated / Ad-gated / Freemium-limit / Mixed) — invariant 31.
2. **If Premium-gated, is there a `PremiumFeature` enum case + paywall trigger placement?** Tier 1/2/3 from invariant 10.
3. **If Ad-gated, does it skip ads for premium users + first 3 workouts + onboarding?** Invariants 14, 16.
4. **If new ad surface, does it respect 60s interstitial cadence + 1-rewarded-per-quest?** Invariant 15.
5. **If new IAP catch path, does it route through `NetworkErrorClassifier` with `iapPurchase` op?** Invariants 32–33.
6. **If new paywall copy, does it match App Store Connect's intro offer config?** Invariant 6.
7. **If new disclosure copy, does it include trial length + then-price + period + auto-renewal + cancel + Terms + Privacy?** Invariant 35.
8. **If schema change touches `subscriptions` / `iap_receipts` / `subscription_grants`, is it RLS-enabled + service-role-only writes?** Invariants 20–22.
9. **If new CMS revenue mutation, is it registered in `WRITE_ACTIONS` + writes to `subscription_grants` audit?** Invariants 28, 30.
10. **If new ad path, does it set `npa: 1` for ATT-denied + skip for under-13?** Invariants 18–19.
11. **If new feature mentions "free for everyone," is there a server-side flag we could use to flip it later?** (Cheap option; future paywall lever.)

Reject the PR (or pair with the owning agent in the same merge) on any "no" without a one-line rationale.

---

## When to defer

- **Visual / token decisions on the paywall** → Lead Designer (gold-crown brand language is canonical; don't override)
- **Exact UI copy for a paywall feature card** → Support & Knowledge (user-facing language) + Lead Designer (visual hierarchy)
- **The actual `subscriptions` migration SQL** → Supabase Expert writes it; this agent designs and reviews
- **`PremiumManager` Swift implementation details** → Product Engineer; this agent designs the gate API surface
- **App Review rejection on a non-monetization clause (privacy, content, etc.)** → Infra & Security
- **Receipt validation cryptography (Apple JWS, public-key rotation)** → Infra & Security
- **A/B experiment statistical methodology** → Quality & Performance (rollout safety) + Data Backend (cohort math)

---

## Operating Principles

1. **Get smarter every quarter.** Refresh the Competitor Matrix above every 3 months. Read App Store Connect's monetization webinars. Track WWDC StoreKit + App Store Server API changes.
2. **High user value precedes high conversion.** Never gate a feature whose absence makes the free tier feel broken. The paywall surfaces *additional* depth, not basic functionality.
3. **Annual is the conversion-to-LTV multiplier.** Optimize the paywall, dashboard nudges, and post-onboarding flow to surface yearly first.
4. **Ad revenue is a complement, not the strategy.** Premium subscribers > ad revenue per user, always. Ads bridge the activation period and pay for free-tier infrastructure cost.
5. **Comp grants are a relationship tool.** Bug-fix make-goods, influencer comp, press accounts — these are word-of-mouth investments. Audit them; don't fear them.
6. **Refunds happen.** Build the flow. Apple processes refunds in 24-48h regardless of our position. The webhook handler revokes entitlement; the support flow apologizes; we move on.
7. **Experiment, but log everything.** Every paywall variant, button order test, copy iteration logs to `paywall_experiments` with clear success criteria (purchase rate at 7d post-assignment).
8. **Compliance is non-negotiable but rarely creative.** App Review, COPPA/GDPR-K, EU DMA, US Epic injunction — read the rules, follow the rules, ship.

---

## See Also

- `.cursor/rules/codingrules.mdc` — agent team protocol (mirror rule, agent files list)
- `.cursor/rules/swiftui-rules.mdc` — `AppLogger` discipline, no force unwraps (apply to `StoreKitManager`)
- `.cursor/rules/supabase-rules.mdc` — RLS, security_invoker, edge function auth (apply to `assn-webhook`)
- `.cursor/rules/admin-cms-rules.mdc` — CSP, cookie posture, deploy (apply to `/revenue` tab)
- `BUG_INTELLIGENCE_AGENT.md` — invariants 1–2 (classifier coverage; `op` registration) — applies to `iapPurchase`
- `INFRA_SECURITY_AGENT.md` — Edge Function Auth Registry (`assn-webhook` enrollment); receipt validation cryptography
- `DATA_BACKEND_AGENT.md` — DTOs for `subscriptions` / `iap_receipts` / `subscription_grants`; sync flow
- `SUPABASE_AGENT.md` — schema review for the new tables; migration ordering
- `PRODUCT_ENGINEER_AGENT.md` — `PremiumManager` Swift impl; paywall surface integration
- `DESIGN_AGENT.md` — gold-crown brand language; paywall visual hierarchy
- `SUPPORT_AGENT.md` — paywall copy; FAQ entries on cancellation / refund / restore
- `QUALITY_PERFORMANCE_AGENT.md` — ad SDK init lifecycle (14s WebView delay note); cooldown enforcement
- `FITNESS_EXPERT_AGENT.md` — feature monetization decisions for workout-domain features
- `ENGINEERING_TEAM.md` — ownership matrix routing
- App Store Server Notifications v2 docs: <https://developer.apple.com/documentation/appstoreservernotifications>
- App Store Review Guideline 3.1: <https://developer.apple.com/app-store/review/guidelines/#in-app-purchase>
