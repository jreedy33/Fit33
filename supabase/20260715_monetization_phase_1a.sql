-- ============================================================================
-- 20260715 — Monetization Phase 1a: subscriptions schema + RPCs + revenue rollup
--
-- Owner: MONETIZATION_AGENT.md (invariants 1, 20–26, 28–30).
-- Pairs with: supabase/functions/assn-webhook/index.ts (Phase 1b — App Store
-- Server Notifications v2 webhook, deployed in same PR).
--
-- Why this migration exists:
--   The app currently has StoreKit 2 wired (StoreKitManager.swift) and a
--   `PremiumManager` that's hardcoded to `isPremiumUser = true` because we
--   have no server-side subscription truth. Without that truth:
--     • a user who refunds via Apple keeps premium forever (Apple processes
--       refunds asynchronously; the client never re-reads),
--     • a server-side cancellation never reaches the device,
--     • family-sharing entitlement transfers can't be tracked,
--     • revenue analytics (MRR, ARR, churn, trial conversion) are impossible,
--     • comp grants / refund acknowledgements have no audit trail.
--
--   This migration creates the canonical data model for subscription state
--   (`subscriptions` + `iap_receipts` + `subscription_grants`), nightly
--   revenue rollup (`revenue_daily_rollup`), the paywall A/B framework
--   (`paywall_experiments` + `paywall_experiment_assignments`), and adds
--   `user_profiles.subscription_tier` as the cheap RLS-gating column other
--   RPCs can read without joining `subscriptions`.
--
-- What this migration does NOT do:
--   - Flip `PremiumManager.isPremiumUser` to server-driven (Phase 1c, paired
--     iOS commit).
--   - Run a backfill for existing accounts (everyone stays `tier='free'`
--     until App Store Server Notifications fire for real purchases).
--
-- All work is idempotent: re-running this migration is a no-op.
--
-- Deploy order: standalone — only depends on `user_profiles` table.
--   Pairs with `assn-webhook` edge function (deployed via
--   `supabase functions deploy assn-webhook --no-verify-jwt`) and the
--   App Store Connect Notification URL configuration (sandbox + prod).
-- ============================================================================

BEGIN;

-- ────────────────────────────────────────────────────────────────────────────
-- 1. Column add: user_profiles.subscription_tier
-- ────────────────────────────────────────────────────────────────────────────
-- Cheap RLS-gating flag mirrored from `subscriptions.status` by the
-- `assn-webhook` handler. Other RPCs (`get_daily_quests`, etc.) can read
-- this without joining `subscriptions`, which keeps hot paths fast.
-- Allowed values:
--   'free'         — no active subscription (default; everyone today)
--   'pro_monthly'  — active monthly subscription
--   'pro_yearly'   — active yearly subscription
--   'pro_lifetime' — one-time purchase (future tier; not yet sold)
--   'comp'         — admin-issued comp grant (subscription_grants)
-- ────────────────────────────────────────────────────────────────────────────

ALTER TABLE public.user_profiles
    ADD COLUMN IF NOT EXISTS subscription_tier TEXT NOT NULL DEFAULT 'free'
        CHECK (subscription_tier IN ('free', 'pro_monthly', 'pro_yearly', 'pro_lifetime', 'comp'));

-- Indexable for "find all premium users" admin queries.
CREATE INDEX IF NOT EXISTS idx_user_profiles_subscription_tier
    ON public.user_profiles (subscription_tier)
    WHERE subscription_tier <> 'free';

-- ────────────────────────────────────────────────────────────────────────────
-- 2. Table: subscriptions
-- ────────────────────────────────────────────────────────────────────────────
-- Per-user current subscription state. One row per user (active row);
-- terminal-state rows kept for audit. Updated by the `assn-webhook` edge
-- function on every App Store Server Notification v2 event.
-- Per MONETIZATION_AGENT invariant 20.
-- ────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.subscriptions (
    id                          UUID         DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id                     UUID         NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
    product_id                  TEXT         NOT NULL,
    tier                        TEXT         NOT NULL CHECK (tier IN ('free', 'pro_monthly', 'pro_yearly', 'pro_lifetime', 'comp')),
    status                      TEXT         NOT NULL CHECK (status IN ('active', 'in_trial', 'grace_period', 'expired', 'revoked', 'paused', 'pending')),
    started_at                  TIMESTAMPTZ  NOT NULL,
    expires_at                  TIMESTAMPTZ,
    will_auto_renew             BOOLEAN      NOT NULL DEFAULT TRUE,
    is_in_intro_offer           BOOLEAN      NOT NULL DEFAULT FALSE,
    -- 'purchased' = bought directly; 'familyShared' = via Family Sharing.
    -- Per MONETIZATION_AGENT invariant 4: Family-shared entitlement is
    -- granted but billing/cancel routes through original purchaser.
    ownership_type              TEXT         NOT NULL DEFAULT 'purchased' CHECK (ownership_type IN ('purchased', 'familyShared')),
    original_purchaser_user_id  UUID         REFERENCES public.user_profiles(id) ON DELETE SET NULL,
    -- Apple's stable ID across renewals. Same `original_transaction_id`
    -- ties together every renewal, refund, and resubscription.
    original_transaction_id     TEXT,
    latest_transaction_id       TEXT,
    environment                 TEXT         NOT NULL DEFAULT 'production' CHECK (environment IN ('sandbox', 'production')),
    -- Last App Store Server Notification event that updated this row.
    last_assn_event_at          TIMESTAMPTZ,
    last_assn_notification_type TEXT,
    -- Price the user paid (locale-dependent; Apple converts and remits).
    revenue_cents               INT,
    currency                    TEXT         CHECK (currency IS NULL OR length(currency) = 3),
    created_at                  TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at                  TIMESTAMPTZ  NOT NULL DEFAULT now()
);

-- Active row uniqueness — one active subscription per user. We allow
-- multiple historical rows so refunds + resubscribes don't lose history.
CREATE UNIQUE INDEX IF NOT EXISTS uq_subscriptions_user_active
    ON public.subscriptions (user_id)
    WHERE status IN ('active', 'in_trial', 'grace_period', 'pending');

CREATE INDEX IF NOT EXISTS idx_subscriptions_user_id           ON public.subscriptions (user_id);
CREATE INDEX IF NOT EXISTS idx_subscriptions_status            ON public.subscriptions (status);
CREATE INDEX IF NOT EXISTS idx_subscriptions_expires_at        ON public.subscriptions (expires_at) WHERE status IN ('active', 'in_trial', 'grace_period');
CREATE INDEX IF NOT EXISTS idx_subscriptions_orig_txid         ON public.subscriptions (original_transaction_id) WHERE original_transaction_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_subscriptions_orig_purchaser    ON public.subscriptions (original_purchaser_user_id) WHERE original_purchaser_user_id IS NOT NULL;

ALTER TABLE public.subscriptions ENABLE ROW LEVEL SECURITY;

-- Users can SELECT their own subscription row(s) (current + historical).
-- Webhook + admin writes go through service role, never client RLS.
DROP POLICY IF EXISTS subscriptions_select_own ON public.subscriptions;
CREATE POLICY subscriptions_select_own ON public.subscriptions
    FOR SELECT
    USING (auth.uid() = user_id);

-- INSERT/UPDATE/DELETE: service-role only (no client policy = no client write).
-- Per Supabase invariant 2 we still document the absence: client RLS = read-only.

CREATE OR REPLACE FUNCTION public.touch_subscriptions_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_subscriptions_touch_updated_at ON public.subscriptions;
CREATE TRIGGER trg_subscriptions_touch_updated_at
    BEFORE UPDATE ON public.subscriptions
    FOR EACH ROW EXECUTE FUNCTION public.touch_subscriptions_updated_at();

COMMENT ON TABLE public.subscriptions IS
'Per-user subscription state. Updated by assn-webhook on every ASSN v2 event. RLS: read-own; writes via service-role / SECURITY DEFINER RPCs only. MONETIZATION_AGENT invariant 20.';

-- ────────────────────────────────────────────────────────────────────────────
-- 3. Table: iap_receipts
-- ────────────────────────────────────────────────────────────────────────────
-- Append-only event log. Stores the raw signed JWS payload from every
-- App Store Server Notification v2 event so we can replay forensically.
-- Per MONETIZATION_AGENT invariant 21.
-- ────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.iap_receipts (
    id                       UUID         DEFAULT gen_random_uuid() PRIMARY KEY,
    -- Nullable until the webhook resolves the event to a user (some events
    -- can fire before the user record exists in pathological cases).
    user_id                  UUID         REFERENCES public.user_profiles(id) ON DELETE CASCADE,
    -- Apple's stable identifier across the subscription lifetime.
    original_transaction_id  TEXT         NOT NULL,
    transaction_id           TEXT         NOT NULL,
    -- ASSN notification type: SUBSCRIBED / DID_RENEW / DID_FAIL_TO_RENEW /
    -- EXPIRED / REVOKE / REFUND / GRACE_PERIOD_EXPIRED / OFFER_REDEEMED /
    -- PRICE_INCREASE / RESUBSCRIBE / etc.
    notification_type        TEXT         NOT NULL,
    notification_subtype     TEXT,
    product_id               TEXT,
    environment              TEXT         NOT NULL CHECK (environment IN ('sandbox', 'production')),
    -- Raw signed JWS payload (the X-Apple-* headers + signedPayload).
    -- Verified server-side; persisted for audit + forensic replay.
    signed_payload           JSONB        NOT NULL,
    -- Decoded transactionInfo + renewalInfo for fast querying without re-verifying.
    decoded_transaction_info JSONB,
    decoded_renewal_info     JSONB,
    -- Whether the JWS verified against Apple's public key. If FALSE,
    -- the row is logged but never trusted to mutate `subscriptions`.
    is_signature_valid       BOOLEAN      NOT NULL DEFAULT FALSE,
    received_at              TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_iap_receipts_user_id         ON public.iap_receipts (user_id) WHERE user_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_iap_receipts_orig_txid       ON public.iap_receipts (original_transaction_id);
CREATE INDEX IF NOT EXISTS idx_iap_receipts_received_at     ON public.iap_receipts (received_at DESC);
CREATE INDEX IF NOT EXISTS idx_iap_receipts_notification    ON public.iap_receipts (notification_type, received_at DESC);

ALTER TABLE public.iap_receipts ENABLE ROW LEVEL SECURITY;

-- Service-role only — no client policies. Users see their subscription
-- state via `subscriptions` (and `get_my_subscription_state` RPC), not the
-- raw event log. Pattern mirrors `silent_push_wake_log` (Infra invariant 14).
-- (No CREATE POLICY needed — RLS-enabled with zero policies = no client access.)

COMMENT ON TABLE public.iap_receipts IS
'Append-only ASSN v2 event log. Service-role only access. MONETIZATION_AGENT invariant 21.';

-- ────────────────────────────────────────────────────────────────────────────
-- 4. Table: subscription_grants
-- ────────────────────────────────────────────────────────────────────────────
-- Audit log for CMS-issued comp grants, refund acknowledgements, trial
-- extensions. Every CMS revenue mutation writes a row here.
-- Per MONETIZATION_AGENT invariant 22.
-- ────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.subscription_grants (
    id                  UUID         DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id             UUID         NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
    -- 'comp_grant'         — admin-issued free premium (influencer / press / bug-fix make-good)
    -- 'comp_revoke'        — revoke a prior comp
    -- 'trial_extension'    — extend trial by N days
    -- 'refund'             — Apple refund processed; entitlement revoked
    -- 'refund_ack'         — admin acknowledged a refund (CS workflow)
    -- 'note'               — admin note on the user's revenue history
    kind                TEXT         NOT NULL CHECK (kind IN ('comp_grant', 'comp_revoke', 'trial_extension', 'refund', 'refund_ack', 'note')),
    reason              TEXT,
    -- For comp grants: when the grant expires (NULL = lifetime).
    expires_at          TIMESTAMPTZ,
    -- For trial extensions: how many days were added.
    trial_extra_days    INT,
    -- For refunds: link to the iap_receipts event that triggered this grant row.
    iap_receipt_id      UUID         REFERENCES public.iap_receipts(id) ON DELETE SET NULL,
    -- Admin who issued the grant. NULL when written by the webhook (refund auto-flow).
    admin_user_id       UUID,
    admin_email         TEXT,
    created_at          TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_subscription_grants_user_id     ON public.subscription_grants (user_id);
CREATE INDEX IF NOT EXISTS idx_subscription_grants_kind        ON public.subscription_grants (kind);
CREATE INDEX IF NOT EXISTS idx_subscription_grants_expires     ON public.subscription_grants (expires_at) WHERE expires_at IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_subscription_grants_created     ON public.subscription_grants (created_at DESC);

ALTER TABLE public.subscription_grants ENABLE ROW LEVEL SECURITY;

-- Users can SELECT their own grant rows (so the iOS app can show
-- "you have a comp grant valid until X" if we ever surface that).
DROP POLICY IF EXISTS subscription_grants_select_own ON public.subscription_grants;
CREATE POLICY subscription_grants_select_own ON public.subscription_grants
    FOR SELECT USING (auth.uid() = user_id);

-- Writes are service-role / SECURITY DEFINER RPC only.
COMMENT ON TABLE public.subscription_grants IS
'Audit log of CMS-issued comp grants, trial extensions, refund acks. RLS: read-own; writes via service-role / SECURITY DEFINER RPCs only. MONETIZATION_AGENT invariant 22.';

-- ────────────────────────────────────────────────────────────────────────────
-- 5. Table: revenue_daily_rollup
-- ────────────────────────────────────────────────────────────────────────────
-- Pre-aggregated revenue metrics for the CMS /revenue tab. Computed
-- nightly at 00:15 UTC by `compute_revenue_rollup()`. Never aggregated
-- live (page would slow down as `subscriptions` grows + reads would race
-- with webhook writes).
-- Per MONETIZATION_AGENT invariant 26.
-- ────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.revenue_daily_rollup (
    snapshot_date         DATE        PRIMARY KEY,
    -- Counts at end-of-day (UTC).
    active_subscribers    INT         NOT NULL DEFAULT 0,
    trial_active          INT         NOT NULL DEFAULT 0,
    -- Day-deltas (counted within the snapshot day).
    new_subscribers       INT         NOT NULL DEFAULT 0,
    churned_subscribers   INT         NOT NULL DEFAULT 0,
    trial_started         INT         NOT NULL DEFAULT 0,
    trial_converted       INT         NOT NULL DEFAULT 0,
    refunds_count         INT         NOT NULL DEFAULT 0,
    refunds_cents         BIGINT      NOT NULL DEFAULT 0,
    -- Revenue metrics in cents (USD-equivalent; locale conversion done at
    -- snapshot time using the price the user paid).
    mrr_cents             BIGINT      NOT NULL DEFAULT 0,
    arr_cents             BIGINT      NOT NULL DEFAULT 0,
    -- For drill-down: how many of the active subscribers are on each tier.
    pro_monthly_count     INT         NOT NULL DEFAULT 0,
    pro_yearly_count      INT         NOT NULL DEFAULT 0,
    pro_lifetime_count    INT         NOT NULL DEFAULT 0,
    comp_count            INT         NOT NULL DEFAULT 0,
    computed_at           TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.revenue_daily_rollup ENABLE ROW LEVEL SECURITY;
-- Service-role only — admin CMS reads via `get_revenue_overview` RPC.
COMMENT ON TABLE public.revenue_daily_rollup IS
'Pre-aggregated daily revenue metrics. Service-role only. Read via get_revenue_overview() RPC. MONETIZATION_AGENT invariant 26.';

-- ────────────────────────────────────────────────────────────────────────────
-- 6. Tables: paywall_experiments + paywall_experiment_assignments
-- ────────────────────────────────────────────────────────────────────────────
-- A/B framework for paywall variants. `paywall_experiments` defines the
-- experiment + variants; `paywall_experiment_assignments` records each
-- user's assignment + outcome (purchased / dismissed / time-to-convert).
-- The CMS `/revenue/experiments` tab consumes these.
-- ────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.paywall_experiments (
    id                   UUID         DEFAULT gen_random_uuid() PRIMARY KEY,
    name                 TEXT         NOT NULL UNIQUE,
    description          TEXT,
    -- Variants is a JSONB array: [{"id":"control","copy":"...","price":"..."}, ...]
    variants             JSONB        NOT NULL,
    -- 'draft' / 'running' / 'paused' / 'completed'
    status               TEXT         NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'running', 'paused', 'completed')),
    started_at           TIMESTAMPTZ,
    ended_at             TIMESTAMPTZ,
    -- The variant that won (set when an admin closes the experiment).
    winning_variant_id   TEXT,
    created_at           TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at           TIMESTAMPTZ  NOT NULL DEFAULT now()
);

ALTER TABLE public.paywall_experiments ENABLE ROW LEVEL SECURITY;
-- Service-role only (admin-managed).
COMMENT ON TABLE public.paywall_experiments IS
'Paywall A/B experiments — definitions + variants. Service-role only. MONETIZATION_AGENT invariant 27.';

CREATE TABLE IF NOT EXISTS public.paywall_experiment_assignments (
    id                  UUID         DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id             UUID         NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
    experiment_id       UUID         NOT NULL REFERENCES public.paywall_experiments(id) ON DELETE CASCADE,
    variant_id          TEXT         NOT NULL,
    assigned_at         TIMESTAMPTZ  NOT NULL DEFAULT now(),
    -- Outcome (set when the user purchases or dismisses past N days).
    outcome             TEXT         CHECK (outcome IS NULL OR outcome IN ('purchased', 'dismissed', 'pending')),
    outcome_at          TIMESTAMPTZ,
    purchased_product   TEXT,
    UNIQUE (user_id, experiment_id)
);

CREATE INDEX IF NOT EXISTS idx_paywall_assignments_user_id    ON public.paywall_experiment_assignments (user_id);
CREATE INDEX IF NOT EXISTS idx_paywall_assignments_experiment ON public.paywall_experiment_assignments (experiment_id);
CREATE INDEX IF NOT EXISTS idx_paywall_assignments_outcome    ON public.paywall_experiment_assignments (experiment_id, outcome);

ALTER TABLE public.paywall_experiment_assignments ENABLE ROW LEVEL SECURITY;
-- Users can read their own assignment so client-side paywall code can render
-- the assigned variant.
DROP POLICY IF EXISTS paywall_assignments_select_own ON public.paywall_experiment_assignments;
CREATE POLICY paywall_assignments_select_own ON public.paywall_experiment_assignments
    FOR SELECT USING (auth.uid() = user_id);

-- Writes via SECURITY DEFINER `assign_paywall_variant()` RPC only.
COMMENT ON TABLE public.paywall_experiment_assignments IS
'Per-user paywall variant assignment + outcome. RLS: read-own; writes via SECURITY DEFINER. MONETIZATION_AGENT invariant 27.';

-- ────────────────────────────────────────────────────────────────────────────
-- 7. RPCs (drop overloads first per Supabase invariant 12)
-- ────────────────────────────────────────────────────────────────────────────

-- 7.1 — get_my_subscription_state — iOS reads on cold launch / foreground
DROP FUNCTION IF EXISTS public.get_my_subscription_state();
CREATE OR REPLACE FUNCTION public.get_my_subscription_state()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
AS $$
DECLARE
    v_caller        UUID := auth.uid();
    v_subscription  RECORD;
    v_grant         RECORD;
    v_result        JSONB;
BEGIN
    IF v_caller IS NULL THEN
        RETURN jsonb_build_object('success', FALSE, 'reason', 'not_authenticated');
    END IF;

    -- Active subscription if any (most-recent active row by `started_at`).
    SELECT * INTO v_subscription
    FROM public.subscriptions
    WHERE user_id = v_caller
      AND status IN ('active', 'in_trial', 'grace_period', 'pending')
    ORDER BY started_at DESC
    LIMIT 1;

    -- Active comp grant if any (still-valid expiry).
    SELECT * INTO v_grant
    FROM public.subscription_grants
    WHERE user_id = v_caller
      AND kind = 'comp_grant'
      AND (expires_at IS NULL OR expires_at > now())
      AND NOT EXISTS (
          SELECT 1 FROM public.subscription_grants g2
          WHERE g2.user_id = v_caller
            AND g2.kind = 'comp_revoke'
            AND g2.created_at > public.subscription_grants.created_at
      )
    ORDER BY created_at DESC
    LIMIT 1;

    -- Resolve the entitlement: subscription wins, then comp grant, else free.
    IF v_subscription.id IS NOT NULL THEN
        v_result := jsonb_build_object(
            'success', TRUE,
            'is_premium', TRUE,
            'tier', v_subscription.tier,
            'source', 'subscription',
            'product_id', v_subscription.product_id,
            'status', v_subscription.status,
            'started_at', v_subscription.started_at,
            'expires_at', v_subscription.expires_at,
            'will_auto_renew', v_subscription.will_auto_renew,
            'is_in_intro_offer', v_subscription.is_in_intro_offer,
            'ownership_type', v_subscription.ownership_type,
            'environment', v_subscription.environment
        );
    ELSIF v_grant.id IS NOT NULL THEN
        v_result := jsonb_build_object(
            'success', TRUE,
            'is_premium', TRUE,
            'tier', 'comp',
            'source', 'comp_grant',
            'expires_at', v_grant.expires_at,
            'reason', v_grant.reason
        );
    ELSE
        v_result := jsonb_build_object(
            'success', TRUE,
            'is_premium', FALSE,
            'tier', 'free',
            'source', 'none'
        );
    END IF;

    RETURN v_result;
END $$;

GRANT EXECUTE ON FUNCTION public.get_my_subscription_state() TO authenticated;

COMMENT ON FUNCTION public.get_my_subscription_state() IS
'iOS-facing entitlement read. Resolves subscription > comp grant > free. SECURITY DEFINER + auth.uid()-pinned. MONETIZATION_AGENT invariants 1, 20, 22.';

-- 7.2 — is_subscriber — convenience helper for other RPCs (e.g. get_daily_quests)
DROP FUNCTION IF EXISTS public.is_subscriber();
DROP FUNCTION IF EXISTS public.is_subscriber(UUID);
CREATE OR REPLACE FUNCTION public.is_subscriber()
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
STABLE
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.subscriptions
        WHERE user_id = auth.uid()
          AND status IN ('active', 'in_trial', 'grace_period')
    ) OR EXISTS (
        SELECT 1
        FROM public.subscription_grants g
        WHERE g.user_id = auth.uid()
          AND g.kind = 'comp_grant'
          AND (g.expires_at IS NULL OR g.expires_at > now())
          AND NOT EXISTS (
              SELECT 1 FROM public.subscription_grants r
              WHERE r.user_id = auth.uid() AND r.kind = 'comp_revoke' AND r.created_at > g.created_at
          )
    );
$$;

GRANT EXECUTE ON FUNCTION public.is_subscriber() TO authenticated;

COMMENT ON FUNCTION public.is_subscriber() IS
'Cheap boolean check for premium entitlement. Used by other RPCs (get_daily_quests pro-tier gate, etc.). MONETIZATION_AGENT invariant 1.';

-- 7.3 — record_iap_event — service-role write path used by assn-webhook
-- This is the ONE function the assn-webhook edge function calls. It does
-- the `iap_receipts` insert + the `subscriptions` upsert + the
-- `user_profiles.subscription_tier` mirror in one transaction so the
-- three views can never drift.
DROP FUNCTION IF EXISTS public.record_iap_event(UUID, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, JSONB, JSONB, JSONB, BOOLEAN);
CREATE OR REPLACE FUNCTION public.record_iap_event(
    p_user_id                  UUID,
    p_original_transaction_id  TEXT,
    p_transaction_id           TEXT,
    p_notification_type        TEXT,
    p_notification_subtype     TEXT,
    p_product_id               TEXT,
    p_environment              TEXT,
    p_signed_payload           JSONB,
    p_decoded_transaction_info JSONB,
    p_decoded_renewal_info     JSONB,
    p_is_signature_valid       BOOLEAN
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_receipt_id          UUID;
    v_tier                TEXT;
    v_status              TEXT;
    v_expires_at          TIMESTAMPTZ;
    v_will_auto_renew     BOOLEAN;
    v_is_intro            BOOLEAN;
    v_started_at          TIMESTAMPTZ;
    v_revenue_cents       INT;
    v_currency            TEXT;
    v_grant_kind          TEXT;
BEGIN
    -- Always log the receipt, even when signature is invalid (for forensics).
    INSERT INTO public.iap_receipts (
        user_id, original_transaction_id, transaction_id,
        notification_type, notification_subtype, product_id,
        environment, signed_payload, decoded_transaction_info,
        decoded_renewal_info, is_signature_valid
    ) VALUES (
        p_user_id, p_original_transaction_id, p_transaction_id,
        p_notification_type, p_notification_subtype, p_product_id,
        p_environment, p_signed_payload, p_decoded_transaction_info,
        p_decoded_renewal_info, p_is_signature_valid
    )
    RETURNING id INTO v_receipt_id;

    -- If signature didn't verify, we logged it but never mutate `subscriptions`.
    -- Per MONETIZATION_AGENT invariant 23.
    IF NOT p_is_signature_valid THEN
        RETURN jsonb_build_object('success', TRUE, 'receipt_id', v_receipt_id, 'mutated_subscription', FALSE, 'reason', 'invalid_signature');
    END IF;

    -- Resolve product → tier.
    v_tier := CASE p_product_id
        WHEN 'com.gofit.app.pro.monthly'  THEN 'pro_monthly'
        WHEN 'com.gofit.app.pro.yearly'   THEN 'pro_yearly'
        WHEN 'com.gofit.app.pro.lifetime' THEN 'pro_lifetime'
        ELSE 'free'
    END;

    -- Resolve notification → status.
    -- Apple's full taxonomy:
    --   SUBSCRIBED / RESUBSCRIBE                    → in_trial OR active
    --   DID_RENEW                                   → active
    --   DID_FAIL_TO_RENEW                           → grace_period
    --   GRACE_PERIOD_EXPIRED                        → expired
    --   EXPIRED                                     → expired
    --   REVOKE                                      → revoked
    --   REFUND                                      → revoked + grant row
    --   REFUND_DECLINED                             → no change
    --   PRICE_INCREASE (subtype CONSENT_PENDING)    → unchanged
    --   OFFER_REDEEMED                              → in_trial OR active
    --   RENEWAL_EXTENDED                            → active (with new expires_at)
    --   TEST                                        → no change (sandbox heartbeat)
    v_status := CASE p_notification_type
        WHEN 'SUBSCRIBED'             THEN CASE WHEN p_notification_subtype = 'INITIAL_BUY' AND COALESCE((p_decoded_transaction_info->>'offerType')::INT, 0) = 1 THEN 'in_trial' ELSE 'active' END
        WHEN 'RESUBSCRIBE'            THEN 'active'
        WHEN 'DID_RENEW'              THEN 'active'
        WHEN 'OFFER_REDEEMED'         THEN 'active'
        WHEN 'DID_FAIL_TO_RENEW'      THEN 'grace_period'
        WHEN 'GRACE_PERIOD_EXPIRED'   THEN 'expired'
        WHEN 'EXPIRED'                THEN 'expired'
        WHEN 'REVOKE'                 THEN 'revoked'
        WHEN 'REFUND'                 THEN 'revoked'
        WHEN 'RENEWAL_EXTENDED'       THEN 'active'
        ELSE NULL
    END;

    v_expires_at := COALESCE(
        NULLIF(p_decoded_transaction_info->>'expiresDate', '')::TIMESTAMPTZ,
        NULLIF(p_decoded_renewal_info->>'recentSubscriptionStartDate', '')::TIMESTAMPTZ
    );
    v_will_auto_renew := COALESCE((p_decoded_renewal_info->>'autoRenewStatus')::INT, 1) = 1;
    v_is_intro := COALESCE((p_decoded_transaction_info->>'offerType')::INT, 0) = 1;
    v_started_at := COALESCE(NULLIF(p_decoded_transaction_info->>'purchaseDate', '')::TIMESTAMPTZ, now());
    v_revenue_cents := NULLIF(p_decoded_transaction_info->>'price', '')::INT;
    v_currency := NULLIF(p_decoded_transaction_info->>'currency', '');

    -- If we couldn't map the notification to a status, log and return.
    IF v_status IS NULL THEN
        RETURN jsonb_build_object('success', TRUE, 'receipt_id', v_receipt_id, 'mutated_subscription', FALSE, 'reason', 'no_status_mapping_for_' || p_notification_type);
    END IF;

    -- Upsert the subscription. The unique partial index
    -- `uq_subscriptions_user_active` ensures one active row per user.
    -- For terminal-state events (expired / revoked) we UPDATE the
    -- existing active row; for new starts we INSERT. We use the
    -- original_transaction_id as the natural key for matching.
    IF EXISTS (
        SELECT 1 FROM public.subscriptions
        WHERE user_id = p_user_id
          AND original_transaction_id = p_original_transaction_id
    ) THEN
        UPDATE public.subscriptions
        SET tier                         = COALESCE(v_tier, tier),
            status                       = v_status,
            expires_at                   = COALESCE(v_expires_at, expires_at),
            will_auto_renew              = v_will_auto_renew,
            is_in_intro_offer            = v_is_intro,
            latest_transaction_id        = p_transaction_id,
            last_assn_event_at           = now(),
            last_assn_notification_type  = p_notification_type,
            updated_at                   = now()
        WHERE user_id = p_user_id
          AND original_transaction_id = p_original_transaction_id;
    ELSE
        INSERT INTO public.subscriptions (
            user_id, product_id, tier, status, started_at, expires_at,
            will_auto_renew, is_in_intro_offer,
            original_transaction_id, latest_transaction_id,
            environment, last_assn_event_at, last_assn_notification_type,
            revenue_cents, currency
        ) VALUES (
            p_user_id, p_product_id, v_tier, v_status, v_started_at, v_expires_at,
            v_will_auto_renew, v_is_intro,
            p_original_transaction_id, p_transaction_id,
            p_environment, now(), p_notification_type,
            v_revenue_cents, v_currency
        );
    END IF;

    -- Mirror the tier to user_profiles for cheap RLS-gating.
    UPDATE public.user_profiles
    SET subscription_tier = CASE
            WHEN v_status IN ('active', 'in_trial', 'grace_period') THEN v_tier
            ELSE 'free'
        END,
        updated_at = now()
    WHERE id = p_user_id;

    -- Refund / Revoke → write a subscription_grants audit row so the CMS
    -- /revenue/grants tab surfaces it. Per MONETIZATION_AGENT invariant 25.
    IF p_notification_type IN ('REFUND', 'REVOKE') THEN
        v_grant_kind := CASE p_notification_type
            WHEN 'REFUND' THEN 'refund'
            WHEN 'REVOKE' THEN 'comp_revoke'
        END;
        INSERT INTO public.subscription_grants (
            user_id, kind, reason, iap_receipt_id, admin_user_id, admin_email
        ) VALUES (
            p_user_id, v_grant_kind,
            'Auto-recorded by assn-webhook from ' || p_notification_type,
            v_receipt_id, NULL, NULL
        );
    END IF;

    RETURN jsonb_build_object(
        'success', TRUE,
        'receipt_id', v_receipt_id,
        'mutated_subscription', TRUE,
        'tier', v_tier,
        'status', v_status
    );
END $$;

-- Service-role only — never grant to authenticated.
REVOKE ALL ON FUNCTION public.record_iap_event(UUID, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, JSONB, JSONB, JSONB, BOOLEAN) FROM PUBLIC;

COMMENT ON FUNCTION public.record_iap_event(UUID, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, JSONB, JSONB, JSONB, BOOLEAN) IS
'Single ASSN write path. Logs iap_receipts + upserts subscriptions + mirrors user_profiles.subscription_tier + writes subscription_grants for refunds. Service-role only. MONETIZATION_AGENT invariants 20–25.';

-- 7.4 — grant_premium_to_user — CMS comp grant action
DROP FUNCTION IF EXISTS public.grant_premium_to_user(UUID, TEXT, TIMESTAMPTZ, UUID, TEXT);
CREATE OR REPLACE FUNCTION public.grant_premium_to_user(
    p_user_id        UUID,
    p_reason         TEXT,
    p_expires_at     TIMESTAMPTZ,
    p_admin_user_id  UUID,
    p_admin_email    TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_grant_id UUID;
BEGIN
    INSERT INTO public.subscription_grants (
        user_id, kind, reason, expires_at, admin_user_id, admin_email
    ) VALUES (
        p_user_id, 'comp_grant', p_reason, p_expires_at, p_admin_user_id, p_admin_email
    )
    RETURNING id INTO v_grant_id;

    UPDATE public.user_profiles
    SET subscription_tier = 'comp', updated_at = now()
    WHERE id = p_user_id;

    RETURN jsonb_build_object('success', TRUE, 'grant_id', v_grant_id);
END $$;

REVOKE ALL ON FUNCTION public.grant_premium_to_user(UUID, TEXT, TIMESTAMPTZ, UUID, TEXT) FROM PUBLIC;

-- 7.5 — revoke_premium_from_user — CMS comp revoke action
DROP FUNCTION IF EXISTS public.revoke_premium_from_user(UUID, TEXT, UUID, TEXT);
CREATE OR REPLACE FUNCTION public.revoke_premium_from_user(
    p_user_id        UUID,
    p_reason         TEXT,
    p_admin_user_id  UUID,
    p_admin_email    TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_grant_id UUID;
    v_has_active_sub BOOLEAN;
BEGIN
    INSERT INTO public.subscription_grants (
        user_id, kind, reason, admin_user_id, admin_email
    ) VALUES (
        p_user_id, 'comp_revoke', p_reason, p_admin_user_id, p_admin_email
    )
    RETURNING id INTO v_grant_id;

    -- Only flip user_profiles.subscription_tier if there's no active
    -- paid subscription overriding the comp grant.
    SELECT EXISTS (
        SELECT 1 FROM public.subscriptions
        WHERE user_id = p_user_id
          AND status IN ('active', 'in_trial', 'grace_period')
    ) INTO v_has_active_sub;

    IF NOT v_has_active_sub THEN
        UPDATE public.user_profiles
        SET subscription_tier = 'free', updated_at = now()
        WHERE id = p_user_id;
    END IF;

    RETURN jsonb_build_object('success', TRUE, 'grant_id', v_grant_id, 'flipped_to_free', NOT v_has_active_sub);
END $$;

REVOKE ALL ON FUNCTION public.revoke_premium_from_user(UUID, TEXT, UUID, TEXT) FROM PUBLIC;

-- 7.6 — extend_trial — CMS trial-extension action
DROP FUNCTION IF EXISTS public.extend_trial(UUID, INT, TEXT, UUID, TEXT);
CREATE OR REPLACE FUNCTION public.extend_trial(
    p_user_id        UUID,
    p_extra_days     INT,
    p_reason         TEXT,
    p_admin_user_id  UUID,
    p_admin_email    TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_grant_id UUID;
BEGIN
    IF p_extra_days IS NULL OR p_extra_days < 1 OR p_extra_days > 90 THEN
        RAISE EXCEPTION 'Invalid trial extension days (must be 1..90, got %)', p_extra_days
            USING ERRCODE = '22023';
    END IF;

    INSERT INTO public.subscription_grants (
        user_id, kind, reason, trial_extra_days, admin_user_id, admin_email
    ) VALUES (
        p_user_id, 'trial_extension', p_reason, p_extra_days, p_admin_user_id, p_admin_email
    )
    RETURNING id INTO v_grant_id;

    -- Push the active subscription's expires_at out by p_extra_days.
    -- Apple's RENEWAL_EXTENDED ASSN event is the canonical mechanism for
    -- this in production; in dev / for legacy users we mutate locally.
    UPDATE public.subscriptions
    SET expires_at = COALESCE(expires_at, now()) + make_interval(days => p_extra_days),
        updated_at = now()
    WHERE user_id = p_user_id
      AND status IN ('active', 'in_trial', 'grace_period');

    RETURN jsonb_build_object('success', TRUE, 'grant_id', v_grant_id, 'extra_days', p_extra_days);
END $$;

REVOKE ALL ON FUNCTION public.extend_trial(UUID, INT, TEXT, UUID, TEXT) FROM PUBLIC;

-- 7.7 — mark_refund_acknowledged — CMS support action when CS team acks a refund
DROP FUNCTION IF EXISTS public.mark_refund_acknowledged(UUID, TEXT, TEXT, UUID, TEXT);
CREATE OR REPLACE FUNCTION public.mark_refund_acknowledged(
    p_user_id        UUID,
    p_transaction_id TEXT,
    p_reason         TEXT,
    p_admin_user_id  UUID,
    p_admin_email    TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_grant_id UUID;
BEGIN
    INSERT INTO public.subscription_grants (
        user_id, kind, reason, admin_user_id, admin_email
    ) VALUES (
        p_user_id, 'refund_ack', COALESCE(p_reason, '') || COALESCE(' [tx ' || p_transaction_id || ']', ''),
        p_admin_user_id, p_admin_email
    )
    RETURNING id INTO v_grant_id;

    RETURN jsonb_build_object('success', TRUE, 'grant_id', v_grant_id);
END $$;

REVOKE ALL ON FUNCTION public.mark_refund_acknowledged(UUID, TEXT, TEXT, UUID, TEXT) FROM PUBLIC;

-- 7.8 — get_revenue_overview — admin CMS read for /revenue dashboard
DROP FUNCTION IF EXISTS public.get_revenue_overview(INT);
CREATE OR REPLACE FUNCTION public.get_revenue_overview(p_lookback_days INT DEFAULT 30)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
AS $$
DECLARE
    v_lookback INT := GREATEST(LEAST(COALESCE(p_lookback_days, 30), 365), 7);
    v_rollup   JSONB;
BEGIN
    SELECT jsonb_agg(to_jsonb(r) ORDER BY r.snapshot_date DESC)
    INTO v_rollup
    FROM (
        SELECT *
        FROM public.revenue_daily_rollup
        WHERE snapshot_date > CURRENT_DATE - v_lookback
        ORDER BY snapshot_date DESC
    ) r;

    RETURN jsonb_build_object(
        'success', TRUE,
        'lookback_days', v_lookback,
        'today_iso', to_char(CURRENT_DATE, 'YYYY-MM-DD'),
        'rollup', COALESCE(v_rollup, '[]'::JSONB)
    );
END $$;

REVOKE ALL ON FUNCTION public.get_revenue_overview(INT) FROM PUBLIC;

COMMENT ON FUNCTION public.get_revenue_overview(INT) IS
'Admin CMS read for /revenue dashboard. Reads revenue_daily_rollup; never aggregates live. MONETIZATION_AGENT invariant 26.';

-- 7.9 — compute_revenue_rollup — nightly cron
DROP FUNCTION IF EXISTS public.compute_revenue_rollup();
CREATE OR REPLACE FUNCTION public.compute_revenue_rollup()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_snapshot_date    DATE := CURRENT_DATE - 1;  -- "Yesterday's" rollup
    v_active           INT;
    v_trial_active     INT;
    v_new              INT;
    v_churned          INT;
    v_trial_started    INT;
    v_trial_converted  INT;
    v_refunds_count    INT;
    v_refunds_cents    BIGINT;
    v_mrr_cents        BIGINT;
    v_arr_cents        BIGINT;
    v_pro_monthly      INT;
    v_pro_yearly       INT;
    v_pro_lifetime     INT;
    v_comp             INT;
BEGIN
    -- End-of-day counts.
    SELECT
        COUNT(*) FILTER (WHERE status IN ('active', 'in_trial', 'grace_period')),
        COUNT(*) FILTER (WHERE status = 'in_trial'),
        COUNT(*) FILTER (WHERE tier = 'pro_monthly' AND status IN ('active','in_trial','grace_period')),
        COUNT(*) FILTER (WHERE tier = 'pro_yearly' AND status IN ('active','in_trial','grace_period')),
        COUNT(*) FILTER (WHERE tier = 'pro_lifetime' AND status IN ('active','in_trial','grace_period'))
    INTO v_active, v_trial_active, v_pro_monthly, v_pro_yearly, v_pro_lifetime
    FROM public.subscriptions
    WHERE started_at <= (v_snapshot_date + INTERVAL '1 day');

    SELECT COUNT(*) INTO v_comp
    FROM public.subscription_grants g
    WHERE g.kind = 'comp_grant'
      AND (g.expires_at IS NULL OR g.expires_at > v_snapshot_date)
      AND NOT EXISTS (
          SELECT 1 FROM public.subscription_grants r
          WHERE r.user_id = g.user_id AND r.kind = 'comp_revoke' AND r.created_at > g.created_at
      );

    -- Day-deltas.
    SELECT
        COUNT(*) FILTER (WHERE last_assn_notification_type IN ('SUBSCRIBED', 'RESUBSCRIBE') AND last_assn_event_at::DATE = v_snapshot_date),
        COUNT(*) FILTER (WHERE last_assn_notification_type IN ('EXPIRED', 'REVOKE') AND last_assn_event_at::DATE = v_snapshot_date),
        COUNT(*) FILTER (WHERE is_in_intro_offer = TRUE AND last_assn_notification_type = 'SUBSCRIBED' AND last_assn_event_at::DATE = v_snapshot_date),
        COUNT(*) FILTER (WHERE last_assn_notification_type = 'DID_RENEW' AND is_in_intro_offer = FALSE AND last_assn_event_at::DATE = v_snapshot_date)
    INTO v_new, v_churned, v_trial_started, v_trial_converted
    FROM public.subscriptions;

    SELECT
        COUNT(*),
        COALESCE(SUM(s.revenue_cents), 0)
    INTO v_refunds_count, v_refunds_cents
    FROM public.iap_receipts r
    LEFT JOIN public.subscriptions s ON s.original_transaction_id = r.original_transaction_id
    WHERE r.notification_type = 'REFUND'
      AND r.received_at::DATE = v_snapshot_date;

    -- MRR: monthly subs revenue + (yearly subs revenue / 12).
    SELECT
        COALESCE(SUM(CASE WHEN tier = 'pro_monthly' THEN revenue_cents ELSE 0 END), 0)
        + COALESCE(SUM(CASE WHEN tier = 'pro_yearly' THEN (revenue_cents / 12) ELSE 0 END), 0)
    INTO v_mrr_cents
    FROM public.subscriptions
    WHERE status IN ('active', 'in_trial', 'grace_period');

    v_arr_cents := v_mrr_cents * 12;

    -- Upsert the rollup row.
    INSERT INTO public.revenue_daily_rollup (
        snapshot_date, active_subscribers, trial_active,
        new_subscribers, churned_subscribers,
        trial_started, trial_converted,
        refunds_count, refunds_cents,
        mrr_cents, arr_cents,
        pro_monthly_count, pro_yearly_count, pro_lifetime_count, comp_count,
        computed_at
    ) VALUES (
        v_snapshot_date, v_active, v_trial_active,
        v_new, v_churned,
        v_trial_started, v_trial_converted,
        v_refunds_count, v_refunds_cents,
        v_mrr_cents, v_arr_cents,
        v_pro_monthly, v_pro_yearly, v_pro_lifetime, v_comp,
        now()
    )
    ON CONFLICT (snapshot_date) DO UPDATE SET
        active_subscribers   = EXCLUDED.active_subscribers,
        trial_active         = EXCLUDED.trial_active,
        new_subscribers      = EXCLUDED.new_subscribers,
        churned_subscribers  = EXCLUDED.churned_subscribers,
        trial_started        = EXCLUDED.trial_started,
        trial_converted      = EXCLUDED.trial_converted,
        refunds_count        = EXCLUDED.refunds_count,
        refunds_cents        = EXCLUDED.refunds_cents,
        mrr_cents            = EXCLUDED.mrr_cents,
        arr_cents            = EXCLUDED.arr_cents,
        pro_monthly_count    = EXCLUDED.pro_monthly_count,
        pro_yearly_count     = EXCLUDED.pro_yearly_count,
        pro_lifetime_count   = EXCLUDED.pro_lifetime_count,
        comp_count           = EXCLUDED.comp_count,
        computed_at          = EXCLUDED.computed_at;

    RETURN jsonb_build_object(
        'success', TRUE,
        'snapshot_date', v_snapshot_date,
        'active_subscribers', v_active,
        'mrr_cents', v_mrr_cents
    );
END $$;

REVOKE ALL ON FUNCTION public.compute_revenue_rollup() FROM PUBLIC;
COMMENT ON FUNCTION public.compute_revenue_rollup() IS
'Nightly cron-scheduled rollup. Service-role only. MONETIZATION_AGENT invariant 26.';

-- 7.10 — trigger_compute_revenue_rollup — pg_cron wrapper
-- Mirrors the canonical `internal_config` + `x-cron-key` pattern (Supabase
-- invariant 25), but since `compute_revenue_rollup()` is plain SQL we
-- can call it directly from cron without a round-trip through edge functions.
-- pg_cron's `SECURITY DEFINER` invocation pins `auth.uid()` to NULL which
-- our IDOR guard pattern explicitly allows ("AND auth.uid() IS NOT NULL").

-- ────────────────────────────────────────────────────────────────────────────
-- 8. Cron schedule — nightly revenue rollup
-- ────────────────────────────────────────────────────────────────────────────
-- Run at 00:15 UTC — between the daily-quest reset (00:05) and the
-- bug-intel rollup (01:00). Per MONETIZATION_AGENT invariant 26.
-- ────────────────────────────────────────────────────────────────────────────

DO $$
BEGIN
    -- Unschedule any prior version (idempotent guard).
    PERFORM cron.unschedule(jobid)
    FROM cron.job
    WHERE jobname = 'revenue-daily-rollup';
EXCEPTION
    WHEN undefined_table THEN NULL;  -- pg_cron not installed in this env
    WHEN OTHERS THEN NULL;
END $$;

DO $$
BEGIN
    PERFORM cron.schedule(
        'revenue-daily-rollup',
        '15 0 * * *',
        $cron$ SELECT public.compute_revenue_rollup(); $cron$
    );
EXCEPTION
    WHEN undefined_table THEN NULL;  -- pg_cron not installed; skip
END $$;

-- ────────────────────────────────────────────────────────────────────────────
-- 9. Update delete_user_account() — Supabase invariant 3
-- ────────────────────────────────────────────────────────────────────────────
-- Add the new user-data tables to the cascade-delete RPC. We use the
-- same `IF EXISTS information_schema.tables` guard pattern the existing
-- function uses so the function stays compatible with environments where
-- the migration hasn't yet deployed.
-- ────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.delete_user_account(user_id_to_delete UUID)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    friendships_deleted        INTEGER := 0;
    friend_requests_deleted    INTEGER := 0;
    contacts_deleted           INTEGER := 0;
    workouts_deleted           INTEGER := 0;
    push_tokens_deleted        INTEGER := 0;
    notifications_deleted      INTEGER := 0;
    subscriptions_deleted      INTEGER := 0;
    iap_receipts_deleted       INTEGER := 0;
    grants_deleted             INTEGER := 0;
    paywall_assignments_deleted INTEGER := 0;
    result jsonb;
BEGIN
    DELETE FROM friendships
    WHERE requester_id = user_id_to_delete OR addressee_id = user_id_to_delete;
    GET DIAGNOSTICS friendships_deleted = ROW_COUNT;

    IF EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'friend_requests') THEN
        DELETE FROM friend_requests
        WHERE from_user_id = user_id_to_delete OR to_user_id = user_id_to_delete;
        GET DIAGNOSTICS friend_requests_deleted = ROW_COUNT;
    END IF;

    IF EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'user_contacts') THEN
        DELETE FROM user_contacts WHERE user_id = user_id_to_delete;
        GET DIAGNOSTICS contacts_deleted = ROW_COUNT;
    END IF;

    IF EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'workouts') THEN
        DELETE FROM workouts WHERE user_id = user_id_to_delete;
        GET DIAGNOSTICS workouts_deleted = ROW_COUNT;
    END IF;

    IF EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'user_push_tokens') THEN
        DELETE FROM user_push_tokens WHERE user_id = user_id_to_delete;
        GET DIAGNOSTICS push_tokens_deleted = ROW_COUNT;
    END IF;

    IF EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'push_notification_queue') THEN
        DELETE FROM push_notification_queue WHERE recipient_user_id = user_id_to_delete;
        GET DIAGNOSTICS notifications_deleted = ROW_COUNT;
    END IF;

    -- Monetization tables (Phase 1a).
    IF EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'subscriptions') THEN
        DELETE FROM public.subscriptions WHERE user_id = user_id_to_delete;
        GET DIAGNOSTICS subscriptions_deleted = ROW_COUNT;
    END IF;

    IF EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'iap_receipts') THEN
        DELETE FROM public.iap_receipts WHERE user_id = user_id_to_delete;
        GET DIAGNOSTICS iap_receipts_deleted = ROW_COUNT;
    END IF;

    IF EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'subscription_grants') THEN
        DELETE FROM public.subscription_grants WHERE user_id = user_id_to_delete;
        GET DIAGNOSTICS grants_deleted = ROW_COUNT;
    END IF;

    IF EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'paywall_experiment_assignments') THEN
        DELETE FROM public.paywall_experiment_assignments WHERE user_id = user_id_to_delete;
        GET DIAGNOSTICS paywall_assignments_deleted = ROW_COUNT;
    END IF;

    DELETE FROM user_profiles WHERE id = user_id_to_delete;
    DELETE FROM auth.users WHERE id = user_id_to_delete;

    result := jsonb_build_object(
        'success', true,
        'user_id', user_id_to_delete,
        'deleted', jsonb_build_object(
            'friendships', friendships_deleted,
            'friend_requests', friend_requests_deleted,
            'contacts', contacts_deleted,
            'workouts', workouts_deleted,
            'push_tokens', push_tokens_deleted,
            'notifications', notifications_deleted,
            'subscriptions', subscriptions_deleted,
            'iap_receipts', iap_receipts_deleted,
            'subscription_grants', grants_deleted,
            'paywall_assignments', paywall_assignments_deleted
        )
    );

    RAISE NOTICE 'Account deleted: %', result;
    RETURN result;
END $$;

-- ────────────────────────────────────────────────────────────────────────────
-- 10. Trailing audit — fail loud if invariants regress
-- ────────────────────────────────────────────────────────────────────────────

DO $$
DECLARE
    v_table_count INT;
    v_rls_disabled_count INT;
    v_rpc_count INT;
BEGIN
    -- (a) All five tables exist + RLS enabled.
    SELECT COUNT(*) INTO v_table_count
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relname IN ('subscriptions', 'iap_receipts', 'subscription_grants', 'revenue_daily_rollup', 'paywall_experiments', 'paywall_experiment_assignments')
      AND c.relkind = 'r';

    IF v_table_count <> 6 THEN
        RAISE EXCEPTION 'Phase 1a audit FAIL: expected 6 monetization tables, found %', v_table_count;
    END IF;

    SELECT COUNT(*) INTO v_rls_disabled_count
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relname IN ('subscriptions', 'iap_receipts', 'subscription_grants', 'revenue_daily_rollup', 'paywall_experiments', 'paywall_experiment_assignments')
      AND c.relrowsecurity = FALSE;

    IF v_rls_disabled_count > 0 THEN
        RAISE EXCEPTION 'Phase 1a audit FAIL: % monetization tables have RLS DISABLED', v_rls_disabled_count;
    END IF;

    -- (b) All canonical RPCs exist.
    SELECT COUNT(*) INTO v_rpc_count
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname IN (
          'get_my_subscription_state', 'is_subscriber', 'record_iap_event',
          'grant_premium_to_user', 'revoke_premium_from_user', 'extend_trial',
          'mark_refund_acknowledged', 'get_revenue_overview', 'compute_revenue_rollup'
      );

    IF v_rpc_count < 9 THEN
        RAISE EXCEPTION 'Phase 1a audit FAIL: expected >= 9 monetization RPCs, found %', v_rpc_count;
    END IF;

    -- (c) user_profiles.subscription_tier column exists with check constraint.
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'user_profiles'
          AND column_name = 'subscription_tier'
    ) THEN
        RAISE EXCEPTION 'Phase 1a audit FAIL: user_profiles.subscription_tier column missing';
    END IF;

    RAISE NOTICE 'Phase 1a audit OK: 6 tables, 9 RPCs, user_profiles.subscription_tier present, RLS enabled everywhere.';
END $$;

COMMIT;
