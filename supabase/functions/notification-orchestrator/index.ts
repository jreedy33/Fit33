// =============================================================================
// notification-orchestrator — Smart Notification Engine (Phase 2)
// =============================================================================
//
// The "should we send this notification NOW?" brain. Picks pending intents
// from notification_intents, applies user prefs / category caps / quiet
// hours / engagement-based smart timing, scores them, picks the top-K,
// and enqueues winners into push_notification_queue with an idempotency
// key so duplicate orchestration runs can't double-send.
//
// Cron: every 5 minutes (cron expression set in 20260805_intent_producer_crons.sql).
//
// Modes (controlled by internal_config['notification_orchestrator_mode']):
//   - 'shadow' (default) — score, log decisions to
//     notification_orchestration_decisions, but DO NOT enqueue. Lets us
//     validate the scoring before turning sends on.
//   - 'cohort:<key>' — only act on intents where cohort_key = <key>.
//     Used during gradual rollout (e.g. 'cohort:beta').
//   - 'live' — act on everything.
//
// Per-user canary override (Migration #178):
//   internal_config['notification_orchestrator_canary_user_ids'] holds a
//   JSON array of UUIDs. When global mode is `shadow`, those users get
//   the LIVE path (real enqueue + APNs); every other user stays in
//   shadow. Useful for canary testing before flipping the global switch.
//
// Auth: service-role / x-cron-key only. (Edge Function Auth Registry —
// INFRA_SECURITY invariant 11.) No user JWTs accepted.
//
// Deploy: supabase functions deploy notification-orchestrator
// =============================================================================

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { buildCorsHeaders } from "../_shared/cors.ts";

// ── Config ───────────────────────────────────────────────────────────────

// Hard cap on intents processed per invocation (keeps cron runs bounded).
const MAX_INTENTS_PER_RUN = 1000;
// Max intents enqueued per user per run (defense against orchestrator bug
// flooding one user — cap is enforced in addition to per-user daily_cap).
const MAX_INTENTS_PER_USER_PER_RUN = 3;

const EXPECTED_PROJECT_REF = (() => {
  const raw = Deno.env.get("SUPABASE_URL") || "";
  const match = raw.match(/^https?:\/\/([a-z0-9]+)\.supabase\.co/i);
  return match?.[1] ?? "";
})();

function isServiceRoleJWT(token: string): boolean {
  try {
    const parts = token.split(".");
    if (parts.length !== 3) return false;
    const payload = JSON.parse(atob(parts[1]));
    if (payload.role !== "service_role") return false;
    if (!EXPECTED_PROJECT_REF) return false;
    return payload.ref === EXPECTED_PROJECT_REF;
  } catch {
    return false;
  }
}

// ── Types ────────────────────────────────────────────────────────────────

interface IntentRow {
  id: string;
  user_id: string;
  category: string;
  intent_kind: string;
  priority: number;
  payload: Record<string, unknown>;
  idempotency_key: string;
  expires_at: string;
  cohort_key: string;
  producer: string;
  created_at: string;
}

interface UserPrefs {
  master_enabled: boolean;
  disabled_types: string[];
  category_disabled: string[];
  quiet_hours_enabled: boolean;
  quiet_hours_start: string | null;
  quiet_hours_end: string | null;
  timezone: string;
  daily_cap: number;
  category_caps: Record<string, number>;
  category_quiet_hours: Record<string, { start: string; end: string }>;
  snoozed_until: Record<string, string>;
  smart_timing_enabled: boolean;
}

// ── Server ───────────────────────────────────────────────────────────────

serve(async (req) => {
  const corsHeaders = buildCorsHeaders(req);
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabase = createClient(supabaseUrl, serviceKey);

    // ── Auth ────────────────────────────────────────────────────────────
    const cronKey = req.headers.get("x-cron-key");
    const authHeader = req.headers.get("Authorization");

    let authed = false;
    if (cronKey && isServiceRoleJWT(cronKey)) {
      authed = true;
    } else if (authHeader) {
      const token = authHeader.replace("Bearer ", "");
      if (token === serviceKey || isServiceRoleJWT(token)) authed = true;
    }
    if (!authed) {
      return json({ error: "Service-role only" }, 401, corsHeaders);
    }

    // ── Load mode + run ─────────────────────────────────────────────────
    const mode = await getOrchestratorMode(supabase);
    const startedAt = Date.now();

    const result = await orchestrate(supabase, mode);

    console.log(JSON.stringify({
      event: "orchestrator_run_complete",
      mode,
      duration_ms: Date.now() - startedAt,
      ...result,
    }));

    return json({ message: "Orchestrator run complete", mode, ...result }, 200, corsHeaders);
  } catch (error) {
    console.error("notification-orchestrator error:", error);
    return json({ error: String(error) }, 500, buildCorsHeaders(req));
  }
});

// ── Mode ─────────────────────────────────────────────────────────────────

async function getOrchestratorMode(supabase: ReturnType<typeof createClient>): Promise<string> {
  const { data, error } = await supabase
    .from("internal_config")
    .select("value")
    .eq("key", "notification_orchestrator_mode")
    .maybeSingle();
  if (error || !data) return "shadow";
  return (data.value as string) ?? "shadow";
}

function modeCohortFilter(mode: string): string | null {
  if (mode.startsWith("cohort:")) return mode.slice("cohort:".length);
  return null;
}

function modeIsLive(mode: string): boolean {
  return mode === "live" || mode.startsWith("cohort:");
}

// Per-user canary override — Migration #178. Reads the JSON-array config
// row once per orchestrator tick. Best-effort: if the value is not valid
// JSON we fall back to comma-separated parsing; if anything is broken we
// return an empty set (canary just no-ops, never poisons live behavior).
async function getCanaryUserIds(
  supabase: ReturnType<typeof createClient>,
): Promise<Set<string>> {
  const { data, error } = await supabase
    .from("internal_config")
    .select("value")
    .eq("key", "notification_orchestrator_canary_user_ids")
    .maybeSingle();
  if (error || !data?.value) return new Set();
  const raw = String(data.value);
  try {
    const parsed = JSON.parse(raw);
    if (Array.isArray(parsed)) {
      return new Set(parsed.filter((x): x is string => typeof x === "string"));
    }
  } catch (_e) {
    // Fall through to comma-separated.
  }
  return new Set(
    raw.split(",").map((s) => s.trim().replace(/^["\[\]]+|["\[\]]+$/g, ""))
       .filter((s) => s.length > 0),
  );
}

// ── Core orchestration ──────────────────────────────────────────────────

interface RunResult {
  candidates: number;
  enqueued: number;
  suppressed: number;
  deferred: number;
  shadow_only: number;
  errors: number;
}

async function orchestrate(
  supabase: ReturnType<typeof createClient>,
  mode: string,
): Promise<RunResult> {
  const result: RunResult = { candidates: 0, enqueued: 0, suppressed: 0, deferred: 0, shadow_only: 0, errors: 0 };

  // Pull pending intents — most recent first within priority bucket.
  // 15-min defer cooldown: skip intents we already considered very
  // recently (decided_at advances on every defer below). Without this
  // the orchestrator re-decides the same deferred intent every 5-min
  // tick — see Migration #176 for the same-class shadow-mode bug.
  const cooldownCutoff = new Date(Date.now() - 15 * 60 * 1000).toISOString();
  const cohort = modeCohortFilter(mode);
  let query = supabase
    .from("notification_intents")
    .select("*")
    .eq("status", "pending")
    .gt("expires_at", new Date().toISOString())
    .or(`decided_at.is.null,decided_at.lt.${cooldownCutoff}`)
    .order("priority", { ascending: false })
    .order("created_at", { ascending: true })
    .limit(MAX_INTENTS_PER_RUN);

  if (cohort) {
    query = query.eq("cohort_key", cohort);
  }

  const { data: intents, error } = await query;
  if (error) {
    console.error("orchestrator: pending intents fetch failed", error);
    return result;
  }
  if (!intents || intents.length === 0) return result;

  result.candidates = intents.length;

  // Per-tick canary allowlist (Migration #178). Empty when global mode
  // is `live` (or when the config row is missing/invalid). Cached as a
  // Set so per-user lookups are O(1) below.
  const globalLive = modeIsLive(mode);
  const canarySet = globalLive ? new Set<string>() : await getCanaryUserIds(supabase);

  // Group by user so per-user caps + smart timing are decided in one pass.
  const byUser = new Map<string, IntentRow[]>();
  for (const intent of intents as IntentRow[]) {
    const list = byUser.get(intent.user_id) ?? [];
    list.push(intent);
    byUser.set(intent.user_id, list);
  }

  for (const [userId, userIntents] of byUser.entries()) {
    try {
      // Effective live flag for this user: global live OR canary
      // listed (only meaningful when global is shadow). When true,
      // every markDecision below stamps shadow_mode=false and the
      // enqueue branch hits APNs for real.
      const userIsLive = globalLive || canarySet.has(userId);
      const isCanary = !globalLive && canarySet.has(userId);
      const shadowFlag = !userIsLive;

      const prefs = await loadPrefs(supabase, userId);

      // Master kill-switch
      if (prefs && !prefs.master_enabled) {
        for (const intent of userIntents) {
          await markDecision(supabase, intent, "suppressed", "master_disabled", null, shadowFlag);
          await updateIntentStatus(supabase, intent.id, "suppressed", null);
          result.suppressed++;
        }
        continue;
      }

      // Score + filter each intent
      const scored = await Promise.all(userIntents.map(async (intent) => ({
        intent,
        score: await scoreIntent(supabase, intent, prefs),
      })));

      // Sort highest score first
      scored.sort((a, b) => b.score.score - a.score.score);

      // Pick top K (bounded by per-run cap AND remaining daily_cap).
      const todaysSends = await countTodaysSends(supabase, userId, prefs?.timezone ?? "UTC");
      const dailyRemaining = prefs ? Math.max(0, prefs.daily_cap - todaysSends) : 999;
      const room = Math.min(MAX_INTENTS_PER_USER_PER_RUN, dailyRemaining);

      let enqueuedThisUser = 0;
      for (const { intent, score } of scored) {
        if (score.skip) {
          await markDecision(supabase, intent, "suppressed", score.skipReason ?? "filter", null, shadowFlag);
          await updateIntentStatus(supabase, intent.id, "suppressed", null);
          result.suppressed++;
          continue;
        }
        if (score.defer) {
          await markDecision(supabase, intent, "deferred", score.deferReason ?? "deferred", score.score, shadowFlag);
          // Leave status='pending' so a future run picks it up after the
          // 15-min cooldown (candidate scan filter), but bump decided_at so
          // it actually reaches the cooldown gate (else: re-decide every 5min).
          await touchIntentDeferred(supabase, intent.id);
          result.deferred++;
          continue;
        }

        if (enqueuedThisUser >= room) {
          await markDecision(supabase, intent, "deferred", "below_runner_up_or_capped", score.score, shadowFlag);
          await touchIntentDeferred(supabase, intent.id);
          result.deferred++;
          continue;
        }

        // ── Enqueue (or shadow-log) ──────────────────────────────────
        if (userIsLive) {
          const queueId = await enqueueIntent(supabase, intent);
          if (queueId) {
            await updateIntentStatus(supabase, intent.id, "enqueued", queueId);
            // Canary path stamped distinctly so the funnel can split
            // canary opens vs full-live opens during the rollout window.
            const reason = isCanary ? "top_score (CANARY)" : "top_score";
            await markDecision(supabase, intent, "enqueued", reason, score.score, false);
            result.enqueued++;
            enqueuedThisUser++;
          } else {
            result.errors++;
          }
        } else {
          // Shadow mode: log the decision AND mark the intent terminal so
          // the next 5-minute tick doesn't re-decide the same intent.
          // Without this update, status stays 'pending' and the candidate
          // scan re-picks it on every tick — Migration #176 backfilled the
          // bug victims; the status update here prevents recurrence.
          await markDecision(supabase, intent, "enqueued", "top_score (SHADOW)", score.score, true);
          await updateIntentStatus(supabase, intent.id, "shadow_decided", null);
          result.shadow_only++;
        }
      }
    } catch (e) {
      console.error(`orchestrator: user ${userId} threw`, e);
      result.errors++;
    }
  }

  return result;
}

// ── Prefs ───────────────────────────────────────────────────────────────

async function loadPrefs(
  supabase: ReturnType<typeof createClient>,
  userId: string,
): Promise<UserPrefs | null> {
  const { data, error } = await supabase
    .from("user_notification_preferences")
    .select("master_enabled, disabled_types, category_disabled, quiet_hours_enabled, quiet_hours_start, quiet_hours_end, timezone, daily_cap, category_caps, category_quiet_hours, snoozed_until, smart_timing_enabled")
    .eq("user_id", userId)
    .maybeSingle();

  if (error || !data) return null;
  return {
    master_enabled: (data.master_enabled as boolean) ?? true,
    disabled_types: (data.disabled_types as string[]) ?? [],
    category_disabled: (data.category_disabled as string[]) ?? [],
    quiet_hours_enabled: (data.quiet_hours_enabled as boolean) ?? false,
    quiet_hours_start: (data.quiet_hours_start as string | null) ?? null,
    quiet_hours_end: (data.quiet_hours_end as string | null) ?? null,
    timezone: (data.timezone as string) ?? "America/New_York",
    daily_cap: (data.daily_cap as number) ?? 8,
    category_caps: (data.category_caps as Record<string, number>) ?? {},
    category_quiet_hours: (data.category_quiet_hours as Record<string, { start: string; end: string }>) ?? {},
    snoozed_until: (data.snoozed_until as Record<string, string>) ?? {},
    smart_timing_enabled: (data.smart_timing_enabled as boolean) ?? true,
  };
}

// ── Scoring ─────────────────────────────────────────────────────────────

interface ScoreResult {
  score: number;
  skip: boolean;
  skipReason?: string;
  defer: boolean;
  deferReason?: string;
}

async function scoreIntent(
  supabase: ReturnType<typeof createClient>,
  intent: IntentRow,
  prefs: UserPrefs | null,
): Promise<ScoreResult> {
  const result: ScoreResult = { score: 0, skip: false, defer: false };

  if (prefs) {
    if (prefs.disabled_types.includes(intent.intent_kind)) {
      result.skip = true; result.skipReason = "intent_kind_disabled"; return result;
    }
    if (prefs.category_disabled.includes(intent.category)) {
      result.skip = true; result.skipReason = "category_disabled"; return result;
    }

    // Snooze check
    const now = new Date();
    const globalSnooze = prefs.snoozed_until["global"];
    if (globalSnooze && new Date(globalSnooze) > now) {
      result.defer = true; result.deferReason = "snoozed_global"; return result;
    }
    const catSnooze = prefs.snoozed_until[intent.category];
    if (catSnooze && new Date(catSnooze) > now) {
      result.defer = true; result.deferReason = "snoozed_category"; return result;
    }

    // Quiet hours (defer rather than skip — it'll re-attempt later).
    if (isInQuietHours(prefs, now)) {
      result.defer = true; result.deferReason = "quiet_hours"; return result;
    }
    const catQH = prefs.category_quiet_hours[intent.category];
    if (catQH && isInRange(catQH.start, catQH.end, prefs.timezone, now)) {
      result.defer = true; result.deferReason = "category_quiet_hours"; return result;
    }
  }

  // Engagement score (0..1) for this user × category × hour-of-day.
  // Smart-timing OFF → use 0.5 (neutral, lets priority dominate).
  let engagement = 0.5;
  if (prefs?.smart_timing_enabled !== false) {
    try {
      const hour = currentHourInTz(prefs?.timezone ?? "UTC");
      const { data, error } = await supabase.rpc("get_engagement_score", {
        p_user_id: intent.user_id,
        p_category: intent.category,
        p_hour_of_day: hour,
      });
      if (!error && typeof data === "number") engagement = Math.max(0.05, Math.min(1.0, data));
    } catch {
      // Score query failure → neutral.
    }
  }

  // Final score: priority × engagement × age boost.
  // Older intents (closer to expiry) get a small boost so they don't
  // starve behind newly-arrived high-priority intents.
  const ageMs = Date.now() - new Date(intent.created_at).getTime();
  const ttlMs = new Date(intent.expires_at).getTime() - new Date(intent.created_at).getTime();
  const ageBoost = ttlMs > 0 ? 1 + 0.2 * Math.min(1, ageMs / ttlMs) : 1;

  result.score = intent.priority * engagement * ageBoost;
  return result;
}

// ── Quiet hours helpers (TZ-aware) ──────────────────────────────────────

function isInQuietHours(prefs: UserPrefs, now: Date): boolean {
  if (!prefs.quiet_hours_enabled || !prefs.quiet_hours_start || !prefs.quiet_hours_end) return false;
  return isInRange(prefs.quiet_hours_start, prefs.quiet_hours_end, prefs.timezone, now);
}

function isInRange(startHHMM: string, endHHMM: string, tz: string, now: Date): boolean {
  const fmt = new Intl.DateTimeFormat("en-US", { timeZone: tz, hour: "numeric", minute: "numeric", hour12: false });
  const parts = fmt.formatToParts(now);
  const h = parseInt(parts.find(p => p.type === "hour")?.value || "0");
  const m = parseInt(parts.find(p => p.type === "minute")?.value || "0");
  const nowMin = h * 60 + m;
  const [sh, sm] = startHHMM.split(":").map(Number);
  const [eh, em] = endHHMM.split(":").map(Number);
  const sMin = sh * 60 + sm;
  const eMin = eh * 60 + em;
  if (sMin < eMin) return nowMin >= sMin && nowMin < eMin;
  return nowMin >= sMin || nowMin < eMin;
}

function currentHourInTz(tz: string): number {
  const fmt = new Intl.DateTimeFormat("en-US", { timeZone: tz, hour: "numeric", hour12: false });
  const parts = fmt.formatToParts(new Date());
  return parseInt(parts.find(p => p.type === "hour")?.value || "0");
}

// ── Today-sent counter (mirror of send-push-notification logic) ─────────

async function countTodaysSends(
  supabase: ReturnType<typeof createClient>,
  userId: string,
  tz: string,
): Promise<number> {
  const startToday = startOfTodayInTzAsUTC(tz);
  const { count } = await supabase
    .from("push_notification_delivery_log")
    .select("*", { count: "exact", head: true })
    .eq("user_id", userId)
    .eq("event", "apns_success")
    .gte("created_at", startToday.toISOString());
  return count ?? 0;
}

function startOfTodayInTzAsUTC(tz: string): Date {
  const now = new Date();
  const dateFmt = new Intl.DateTimeFormat("en-CA", { timeZone: tz, year: "numeric", month: "2-digit", day: "2-digit" });
  const parts = dateFmt.formatToParts(now);
  const y = parseInt(parts.find(p => p.type === "year")?.value || "2026");
  const m = parseInt(parts.find(p => p.type === "month")?.value || "1");
  const d = parseInt(parts.find(p => p.type === "day")?.value || "1");
  const utcGuess = new Date(Date.UTC(y, m - 1, d, 0, 0, 0));
  const localFmt = new Intl.DateTimeFormat("en-US", { timeZone: tz, hour: "numeric", hour12: false });
  const localH = parseInt(localFmt.formatToParts(utcGuess).find(p => p.type === "hour")?.value || "0");
  return new Date(utcGuess.getTime() - localH * 60 * 60 * 1000);
}

// ── Enqueue ─────────────────────────────────────────────────────────────

async function enqueueIntent(
  supabase: ReturnType<typeof createClient>,
  intent: IntentRow,
): Promise<string | null> {
  // Render copy via the template engine (Phase 3 — `render_notification_copy`).
  // Falls back to a placeholder when the engine is missing or returns null
  // so we never enqueue an empty notification.
  const rendered = await renderCopy(supabase, intent);

  const insert = {
    recipient_user_id: intent.user_id,
    notification_type: intent.intent_kind,
    title: rendered.title,
    body: rendered.body,
    data: {
      ...rendered.data,
      type: intent.intent_kind,
      category: intent.category,
      intent_id: intent.id,
      intent_kind: intent.intent_kind,
    },
    category: intent.category,
    status: "pending",
  };

  const { data, error } = await supabase
    .from("push_notification_queue")
    .insert(insert)
    .select("id")
    .single();

  if (error) {
    console.error(`orchestrator: enqueue failed for intent ${intent.id}`, error);
    return null;
  }

  // Stamp delivery log with the producer + orchestrator decision so
  // CMS Failed Deliveries can correlate back to intent.
  await supabase.from("push_notification_delivery_log").insert({
    notification_id: (data as { id: string }).id,
    user_id: intent.user_id,
    event: "enqueued",
    detail: {
      via: "orchestrator",
      intent_id: intent.id,
      intent_kind: intent.intent_kind,
      category: intent.category,
      producer: intent.producer,
    },
    category: intent.category,
  });

  return (data as { id: string }).id;
}

// ── Template rendering (loose coupling to Phase 3 template engine) ──────

interface RenderedCopy {
  title: string;
  body: string;
  data: Record<string, unknown>;
}

async function renderCopy(
  supabase: ReturnType<typeof createClient>,
  intent: IntentRow,
): Promise<RenderedCopy> {
  // Phase 3 ships `render_notification_copy(intent_id) -> JSONB`. Until then,
  // synthesize a sensible fallback from the intent_kind so users see something
  // human if the template fails to load.
  try {
    const { data, error } = await supabase.rpc("render_notification_copy", { p_intent_id: intent.id });
    if (!error && data && typeof data === "object") {
      const obj = data as Record<string, unknown>;
      const title = typeof obj.title === "string" ? obj.title : null;
      const body = typeof obj.body === "string" ? obj.body : null;
      const extra = (obj.data && typeof obj.data === "object") ? obj.data as Record<string, unknown> : {};
      if (title && body) return { title, body, data: extra };
    }
  } catch {
    // RPC not deployed yet — fall through to default.
  }
  return defaultCopy(intent);
}

function defaultCopy(intent: IntentRow): RenderedCopy {
  // Minimal viable copy keyed off intent_kind. The Phase 3 template engine
  // overrides these once deployed.
  const p = intent.payload ?? {};
  switch (intent.intent_kind) {
    case "league_started":
      return { title: "Your league just started", body: "Check the leaderboard before someone takes first.", data: {} };
    case "rivalry_behind":
      return {
        title: `${str(p.opponent_name) ?? "Your opponent"} is pulling ahead`,
        body: `Down ${num(p.gap)?.toLocaleString() ?? "—"} ${str(p.unit) ?? ""} — talk smack or close the gap.`,
        data: { challenge_id: str(p.challenge_id) ?? "" },
      };
    case "recovery_alert":
      return {
        title: "Recovery red — go light today",
        body: `HRV down ${num(p.hrv_delta_pct)?.toFixed(0) ?? "?"}%. Today's auto-workout will favor mobility.`,
        data: {},
      };
    case "sleep_debt":
      return { title: "Need more sleep tonight", body: `Get ${num(p.needed_hours)?.toFixed(1) ?? "8"}h to hit baseline.`, data: {} };
    case "hydration_pace":
      return { title: "Behind on water", body: `${num(p.deficit_oz) ?? 32}oz left to hit your goal.`, data: {} };
    case "streak_risk":
      return { title: `🔥 ${num(p.streak_days) ?? "Your"}-day streak at risk`, body: "Log anything to save it.", data: {} };
    case "friend_workout_match":
      return {
        title: `${str(p.friend_name) ?? "A friend"} just trained ${str(p.muscle_group) ?? "today"}`,
        body: `You're ${num(p.days_since_you_trained_it) ?? "a few"} days overdue — match it?`,
        data: {},
      };
    case "strava_celebration":
      return { title: "Big day on Strava", body: "Your activity just synced — check your recap.", data: {} };
    default:
      return { title: "New activity", body: "Tap to see what's new.", data: {} };
  }
}

function str(v: unknown): string | null { return typeof v === "string" ? v : null; }
function num(v: unknown): number | null {
  if (typeof v === "number") return v;
  if (typeof v === "string" && !Number.isNaN(parseFloat(v))) return parseFloat(v);
  return null;
}

// ── Decision log ────────────────────────────────────────────────────────

async function markDecision(
  supabase: ReturnType<typeof createClient>,
  intent: IntentRow,
  decision: "enqueued" | "suppressed" | "deferred",
  reason: string,
  score: number | null,
  shadowMode: boolean,
): Promise<void> {
  await supabase.from("notification_orchestration_decisions").insert({
    user_id: intent.user_id,
    intent_id: intent.id,
    decision,
    reason,
    score,
    context: {
      intent_kind: intent.intent_kind,
      category: intent.category,
      priority: intent.priority,
      producer: intent.producer,
    },
    shadow_mode: shadowMode,
  });
}

async function updateIntentStatus(
  supabase: ReturnType<typeof createClient>,
  intentId: string,
  status: "enqueued" | "suppressed" | "expired" | "failed" | "shadow_decided",
  queueId: string | null,
): Promise<void> {
  await supabase.from("notification_intents").update({
    status,
    queue_id: queueId,
    decided_at: new Date().toISOString(),
  }).eq("id", intentId);
}

/// Bump `decided_at` for a deferred intent so the 15-min cooldown filter in
/// the candidate scan catches it and we don't re-decide every 5-min tick.
/// Status stays 'pending' so it can be re-evaluated when the cooldown lapses.
async function touchIntentDeferred(
  supabase: ReturnType<typeof createClient>,
  intentId: string,
): Promise<void> {
  await supabase.from("notification_intents").update({
    decided_at: new Date().toISOString(),
  }).eq("id", intentId);
}

// ── JSON helper ─────────────────────────────────────────────────────────

function json(body: unknown, status: number, corsHeaders: Record<string, string>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
