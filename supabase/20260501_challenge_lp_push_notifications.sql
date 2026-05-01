-- =============================================================================
-- 20260501_challenge_lp_push_notifications.sql
--
-- Challenge League Points Expansion — Push Notification Wiring (Part 4 of 3).
-- "You just won the Final Bell" pushes.
--
-- DELIVERS:
--   • CHECK-constraint hotfix on `challenge_league_awards` so the
--     `wave_final_bell` path (which carries the wave end date in
--     challenge_day for per-wave uniqueness) no longer trips the
--     `day_kind_consistency` check. First Sunday 23:59 UTC run would have
--     raised check_violation without this.
--   • `notification_templates` rows for the `challenge_lp_awarded` intent
--     kind (2 variants: default + playful, weighted 100/60 for A/B).
--   • `render_notification_copy` patch — forwards `challenge_kind`,
--     `points`, `primary_award_kind`, `reason`, and `day` from payload
--     → push `data` so the iOS `ChallengeLpAwardedPayload` decodes every
--     field end-to-end.
--   • `_push_challenge_lp_awarded_on_insert()` + AFTER-INSERT trigger on
--     `challenge_league_awards` — fires ONE push intent per Final Bell /
--     wave Final Bell row where `final_points >= 10`. Piggybacks the
--     ledger's UNIQUE constraint for natural dedup (trigger only fires on
--     successful INSERT; re-runs that ON CONFLICT DO NOTHING produce no
--     duplicate push).
--
-- INVARIANTS:
--   • Trigger NEVER runs for daily award kinds (`hit_target`,
--     `day_winner`, `intensity`, `early_bird`, `unbroken_chain`). Users
--     get daily LP silently; the battle-log LP chips surface them in-app.
--     Rationale: pushing every daily award would burn through the
--     `rivalry` category daily_cap (4) in one active challenge. Final
--     Bell is the high-signal moment worth interrupting for.
--   • Push routing honors the Smart Notification Engine pipeline —
--     `enqueue_notification_intent` → orchestrator filters
--     (master/category/quiet-hours/daily-cap/smart-timing) → queue →
--     `send-push-notification`. No direct writes to
--     `push_notification_queue`.
--   • `idempotency_key` = ledger row id (UUID) — guarantees one push per
--     award row even if the ledger shrinks/recreates across DB restores.
--   • expires_at = 48h after award so stale "you won" copy never fires.
--
-- PAIRS WITH:
--   • `20260430_challenge_league_awards_schema.sql` (Part 1 — ledger).
--   • `20260430b_league_tier_promotion_floors.sql` (Part 2 — tier floors).
--   • `20260430c_challenge_league_scoring_rpcs.sql` (Part 3 — scoring).
-- =============================================================================

BEGIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. CHECK-constraint hotfix: allow wave_final_bell to carry challenge_day
--
-- The part-1 schema forbade any challenge_day on `final_bell` OR
-- `wave_final_bell` rows. The community-wave scoring RPC writes
-- challenge_day = wave_end_date to dedup per wave (otherwise re-running
-- the weekly cron would ON CONFLICT DO NOTHING forever). We split the
-- check into three branches so each award_kind has the right shape.
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE challenge_league_awards
    DROP CONSTRAINT IF EXISTS challenge_league_awards_day_kind_consistency;

ALTER TABLE challenge_league_awards
    ADD CONSTRAINT challenge_league_awards_day_kind_consistency CHECK (
        -- 1v1/group/private Final Bell: single row per user/challenge, no day.
        (award_kind = 'final_bell' AND challenge_day IS NULL)
        -- Community wave Final Bell: one row per (user, challenge, wave_end).
        OR (award_kind = 'wave_final_bell' AND challenge_day IS NOT NULL)
        -- Daily awards: day is mandatory.
        OR (award_kind NOT IN ('final_bell','wave_final_bell') AND challenge_day IS NOT NULL)
    );

COMMENT ON CONSTRAINT challenge_league_awards_day_kind_consistency ON challenge_league_awards IS
    'final_bell rows have NULL day (one per challenge); wave_final_bell rows carry the wave end date; daily awards require a day. Replaced 2026-05-01 to accommodate wave_final_bell per-wave uniqueness.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. render_notification_copy — extend payload → data passthrough
--
-- The Phase-3 version only forwarded `challenge_id` + `workout_id`. The
-- `challenge_lp_awarded` push needs five more keys (kind/points/reason/
-- primary_award_kind/day) for the iOS `ChallengeLpAwardedPayload`
-- decoder. We add each key guardedly (only when present in payload) so
-- existing intent kinds are untouched.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION render_notification_copy(p_intent_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_intent   notification_intents%ROWTYPE;
    v_template notification_templates%ROWTYPE;
    v_title    TEXT;
    v_body     TEXT;
    v_data     JSONB;
BEGIN
    SELECT * INTO v_intent FROM notification_intents WHERE id = p_intent_id;
    IF NOT FOUND THEN
        RETURN NULL;
    END IF;

    v_template := pick_template_variant(v_intent.intent_kind, v_intent.cohort_key);
    IF v_template.id IS NULL THEN
        RETURN NULL;
    END IF;

    v_title := interpolate_template(v_template.title_template, v_intent.payload);
    v_body  := interpolate_template(v_template.body_template,  v_intent.payload);

    v_data := COALESCE(v_template.data_template, '{}'::JSONB);

    -- Variant accounting for CMS A/B funnel.
    v_data := v_data || jsonb_build_object(
        'template_id', v_template.id,
        'variant', v_template.variant
    );

    -- Pass-through deep-link + domain-specific keys. Guarded with `?`
    -- so absent keys don't stamp NULL into the push data.
    IF v_intent.payload ? 'challenge_id' THEN
        v_data := v_data || jsonb_build_object('challenge_id', v_intent.payload->>'challenge_id');
    END IF;
    IF v_intent.payload ? 'workout_id' THEN
        v_data := v_data || jsonb_build_object('workout_id', v_intent.payload->>'workout_id');
    END IF;
    -- 2026-05-01 — Challenge LP Expansion: forward LP-specific fields so
    -- `ChallengeLpAwardedPayload.from(userInfo:)` can decode the full
    -- shape (points, reason, primary_award_kind, etc.).
    IF v_intent.payload ? 'challenge_kind' THEN
        v_data := v_data || jsonb_build_object('challenge_kind', v_intent.payload->>'challenge_kind');
    END IF;
    IF v_intent.payload ? 'points' THEN
        v_data := v_data || jsonb_build_object('points', (v_intent.payload->>'points')::INTEGER);
    END IF;
    IF v_intent.payload ? 'primary_award_kind' THEN
        v_data := v_data || jsonb_build_object('primary_award_kind', v_intent.payload->>'primary_award_kind');
    END IF;
    IF v_intent.payload ? 'reason' THEN
        v_data := v_data || jsonb_build_object('reason', v_intent.payload->>'reason');
    END IF;
    IF v_intent.payload ? 'day' THEN
        v_data := v_data || jsonb_build_object('day', v_intent.payload->>'day');
    END IF;

    RETURN jsonb_build_object(
        'title', v_title,
        'body',  v_body,
        'data',  v_data,
        'variant_id', v_template.id,
        'variant', v_template.variant
    );
END;
$$;

COMMENT ON FUNCTION render_notification_copy(UUID) IS
    'Renders push copy for a pending notification intent. Picks a weighted template variant, interpolates {token}s against payload, and forwards deep-link + domain-specific keys to push data. 2026-05-01: added challenge_kind/points/primary_award_kind/reason/day for Challenge LP Expansion.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Notification templates for challenge_lp_awarded
--
-- Two variants (default + playful). Weighted 100/60 so default wins ~62%
-- of the time. `{reason}` carries the server-rendered phrase from the
-- ledger `note` column ("Winner — full pot + Unbroken Chain 1.5x",
-- "Top 5% — full pot", etc.) which covers both Final Bell + wave Final
-- Bell cases without needing separate templates.
-- ─────────────────────────────────────────────────────────────────────────────

INSERT INTO notification_templates
    (intent_kind, variant, category, title_template, body_template, weight, notes)
VALUES
    ('challenge_lp_awarded', 'default', 'rivalry',
     '🏁 Final Bell',
     '+{points} LP — {reason}',
     100,
     'Final Bell (1v1/group/private/community wave) payout. Fired per-award via AFTER-INSERT trigger on challenge_league_awards.'),
    ('challenge_lp_awarded', 'playful', 'rivalry',
     '🔔 You just cashed in',
     '+{points} LP banked — {reason}',
     60,
     'Playful variant for Final Bell. Same semantics as default.')
ON CONFLICT (intent_kind, variant, COALESCE(cohort_key, '')) DO UPDATE
    SET title_template = EXCLUDED.title_template,
        body_template  = EXCLUDED.body_template,
        weight         = EXCLUDED.weight,
        notes          = EXCLUDED.notes,
        updated_at     = NOW();

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. AFTER-INSERT trigger: push on Final Bell / wave_final_bell rows
--
-- Fires ONCE per award row (the UNIQUE indexes on the ledger guarantee
-- at most one insert per (user, challenge, final_bell) or (user,
-- challenge, wave_end, wave_final_bell)). The `final_points >= 10` gate
-- filters trivial awards (a 5-LP participation sliver isn't worth a
-- push interrupt).
--
-- The trigger is SECURITY DEFINER so the orchestrator helper
-- (`enqueue_notification_intent`) can INSERT into `notification_intents`
-- regardless of the calling session role (the compute_* RPCs run as
-- service_role anyway but keep it explicit for safety).
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION _push_challenge_lp_awarded_on_insert()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_payload JSONB;
    v_idempotency_key TEXT;
    v_expires_at TIMESTAMPTZ := NOW() + INTERVAL '48 hours';
    v_priority INTEGER;
BEGIN
    -- Only fire for Final Bell classes. Silently no-op for every other
    -- award kind (daily awards, unbroken_chain accounting rows).
    IF NEW.award_kind NOT IN ('final_bell','wave_final_bell') THEN
        RETURN NEW;
    END IF;

    -- Gate: trivial awards don't warrant a push interrupt.
    IF NEW.final_points < 10 THEN
        RETURN NEW;
    END IF;

    -- Priority: 1v1/group/private Final Bell = big moment (75).
    -- Wave Final Bell (community) = lower-signal (55) — mass fanout,
    -- most users at mid-percentile tiers.
    v_priority := CASE NEW.award_kind
        WHEN 'final_bell'      THEN 75
        WHEN 'wave_final_bell' THEN 55
        ELSE 50
    END;

    v_payload := jsonb_build_object(
        'challenge_id',       NEW.challenge_id::TEXT,
        'challenge_kind',     NEW.challenge_kind,
        'points',             NEW.final_points,
        'primary_award_kind', NEW.award_kind,
        'reason',             COALESCE(NEW.note, 'League Points awarded')
    );

    -- Wave Final Bell carries the wave end day; pass through for display.
    IF NEW.challenge_day IS NOT NULL THEN
        v_payload := v_payload || jsonb_build_object('day', NEW.challenge_day::TEXT);
    END IF;

    -- Idempotency: ledger row UUID. One push per award row, forever.
    v_idempotency_key := 'challenge_lp_awarded:' || NEW.id::TEXT;

    PERFORM enqueue_notification_intent(
        NEW.user_id,
        'rivalry',
        'challenge_lp_awarded',
        v_priority,
        v_payload,
        v_idempotency_key,
        v_expires_at,
        'challenge_league_awards_trigger',
        'all'
    );

    RETURN NEW;
EXCEPTION WHEN OTHERS THEN
    -- Never block the ledger write. If the push helper blows up for any
    -- reason (missing orchestrator function, preferences RLS glitch,
    -- etc.) log and continue. The award still lands; the user just
    -- misses this one push.
    RAISE WARNING '[challenge_lp_awarded trigger] failed for award %: %', NEW.id, SQLERRM;
    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION _push_challenge_lp_awarded_on_insert() IS
    'AFTER-INSERT trigger on challenge_league_awards. Enqueues a "challenge_lp_awarded" intent for Final Bell / wave_final_bell rows >= 10 LP. Silently no-ops on daily awards. SECURITY DEFINER so it works from service-role RPC callers. Failures are logged and swallowed — never blocks the award insert.';

DROP TRIGGER IF EXISTS trg_push_challenge_lp_awarded ON challenge_league_awards;

CREATE TRIGGER trg_push_challenge_lp_awarded
    AFTER INSERT ON challenge_league_awards
    FOR EACH ROW
    EXECUTE FUNCTION _push_challenge_lp_awarded_on_insert();

COMMENT ON TRIGGER trg_push_challenge_lp_awarded ON challenge_league_awards IS
    'Fires challenge_lp_awarded push via the Smart Notification Engine on every successful Final Bell / wave_final_bell insert. Natural dedup via the ledger UNIQUE indexes — ON CONFLICT DO NOTHING inserts do NOT fire the trigger, so re-running scoring RPCs is safe.';

COMMIT;

-- =============================================================================
-- Post-deploy verification (run after COMMIT):
--
--   -- Confirm the constraint allows wave_final_bell with a day:
--   SELECT pg_get_constraintdef(oid)
--     FROM pg_constraint
--    WHERE conname = 'challenge_league_awards_day_kind_consistency';
--
--   -- Confirm templates landed:
--   SELECT intent_kind, variant, weight, is_active
--     FROM notification_templates
--    WHERE intent_kind = 'challenge_lp_awarded';
--
--   -- Confirm trigger is attached:
--   SELECT tgname, tgenabled
--     FROM pg_trigger
--    WHERE tgrelid = 'challenge_league_awards'::regclass
--      AND tgname = 'trg_push_challenge_lp_awarded';
--
--   -- Smoke test: insert a fake final_bell row for yourself (rollback after).
--   -- Should produce exactly ONE notification_intents row.
--   BEGIN;
--     INSERT INTO challenge_league_awards (
--       user_id, challenge_kind, challenge_id, challenge_day, award_kind,
--       base_points, multiplier_applied, final_points, week_start, note
--     ) VALUES (
--       auth.uid(), '1v1', gen_random_uuid(), NULL, 'final_bell',
--       50, 1.0, 50, get_current_week_monday(), 'Winner — full pot (smoke test)'
--     );
--     SELECT COUNT(*) FROM notification_intents
--      WHERE producer = 'challenge_league_awards_trigger'
--        AND created_at > NOW() - INTERVAL '1 minute';
--   ROLLBACK;
-- =============================================================================
