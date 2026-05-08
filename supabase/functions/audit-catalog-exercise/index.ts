// Supabase Edge Function: audit-catalog-exercise
// -----------------------------------------------------------------------------
// Per-exercise catalog auditor. Mirrors the Claude → propose_exercise_correction
// flow used by `analyze-quality-workout`, but driven by the catalog itself
// rather than completed quality workouts. Built as a one-pass auditor so we
// don't have to wait for users to perform every exercise before we surface
// data-quality issues.
//
// PIPELINE (per request — ONE exercise per call so we can parallelize at
// the orchestrator level without compounding 5min cold-start budget on big
// loops)
//   1. Load the exercise row + up to 4 sister exercises from the same
//      exercise_family.
//   2. Build a slim Claude prompt (system prompt is intentionally >1024
//      tokens so prompt caching kicks in — see SYSTEM_PROMPT below).
//   3. Parse strict JSON. Each "proposal" is normalized + whitelisted in
//      the same way the analyze-quality-workout edge function does.
//   4. If body.apply === true: call `propose_exercise_correction` for each
//      proposal. Same RPC, same gates (sister/name/multi-report), same
//      core-exercise lockout. Auto-apply happens automatically when a gate
//      passes — no separate code path.
//      If apply=false: return the proposals JSON without writing.
//
// INVOCATION
//   POST { exercise_id: string, apply?: boolean }
//   - Service-role auth REQUIRED. No user-JWT path — admin/orchestration only.
//
// AUTH
//   Authorization: Bearer <service_role_key | service_role_JWT>
//   x-cron-key: <service_role_JWT> (alternative)
//
// SECRETS
//   ANTHROPIC_API_KEY, SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
//
// Deploy: supabase functions deploy audit-catalog-exercise
// -----------------------------------------------------------------------------

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { buildCorsHeaders } from "../_shared/cors.ts";

// ───────────────────────────────────────────────────────────────────────────
// Constants
// ───────────────────────────────────────────────────────────────────────────

const ANTHROPIC_API_URL = "https://api.anthropic.com/v1/messages";
const ANTHROPIC_VERSION = "2023-06-01";

const MODEL = "claude-sonnet-4-20250514";
const CLAUDE_MAX_TOKENS = 1024;
const CLAUDE_TIMEOUT_MS = 30_000;
const SISTERS_TO_INCLUDE = 4;

const CORRECTION_FIELD_WHITELIST = new Set<string>([
    "primary_muscles",
    "secondary_muscles",
    "workout_type",
    "equipment_category",
    "is_compound",
    "duration_based",
]);

const VALID_WORKOUT_TYPE = new Set<string>([
    "Strength", "Stretch", "Plyometrics", "Cardio",
]);

const EXPECTED_PROJECT_REF = (() => {
    const raw = Deno.env.get("SUPABASE_URL") || "";
    const match = raw.match(/^https?:\/\/([a-z0-9]+)\.supabase\.co/i);
    return match?.[1] ?? "";
})();

function isServiceRoleJWT(token: string): boolean {
    try {
        const parts = token.split(".");
        if (parts.length !== 3) return false;
        const payload = JSON.parse(
            atob(parts[1].replace(/-/g, "+").replace(/_/g, "/")),
        );
        if (payload.role !== "service_role") return false;
        if (!EXPECTED_PROJECT_REF) return false;
        // Legacy keys carry `ref` directly. New-format keys (the
        // Supabase 2026 `sb_secret_…` rollout) come through translated
        // by the gateway with the project ref embedded in `iss`, e.g.
        // `https://api.supabase.co/v1/projects/<ref>/api-keys-jwt-issuer`.
        if (payload.ref === EXPECTED_PROJECT_REF) return true;
        if (typeof payload.iss === "string" &&
            payload.iss.includes(`/projects/${EXPECTED_PROJECT_REF}/`)) {
            return true;
        }
        return false;
    } catch {
        return false;
    }
}

// ───────────────────────────────────────────────────────────────────────────
// SYSTEM PROMPT
//   ~1.1K tokens — sized JUST over the 1,024-token Anthropic prompt-cache
//   minimum so every call after the first reads the system prompt at the
//   $0.30/MTok cached-read rate instead of $3/MTok. Examples are included
//   both because they push us over the threshold AND because they
//   materially improve correction quality.
// ───────────────────────────────────────────────────────────────────────────

const SYSTEM_PROMPT = `You are the Fit33 Catalog Auditor. Given a single exercise from the canonical catalog \
(plus up to 4 sister exercises in the same family for reference), you propose 100%-confident \
corrections to data fields where the existing value is FACTUALLY WRONG.

Every correction enters a corroboration queue (exercise_correction_proposals). It auto-applies
to the catalog ONLY if confidence===1.0 AND a deterministic gate passes:
  - sister gate: a sibling in the same exercise_family already has the proposed value.
  - name gate: the exercise name unambiguously implies the value.
  - multi-report gate: the same correction is proposed in >=2 distinct reports (>=3 for REMOVE).
Anything else sits in the queue for human review. Your job is to propose accurately; the
system handles whether to auto-apply.

# WHITELISTED FIELDS — only these may appear in your output

  - primary_muscles      (operation: "add" or "remove" — array of strings)
  - secondary_muscles    (operation: "add" or "remove" — array of strings)
  - workout_type         (operation: "set" — one of "Strength"|"Stretch"|"Plyometrics"|"Cardio")
  - equipment_category   (operation: "set" — short string e.g. "Cable"|"Dumbbell"|"Barbell"|"Machine"|"Bodyweight")
  - is_compound          (operation: "set" — true|false)
  - duration_based       (operation: "set" — true|false)

Anything else (difficulty_level, ratings, family, description, video) MUST NOT appear.

# OPERATION RULES

  - "add"    — muscle arrays only. Use when the exercise is MISSING a muscle that should be there.
  - "remove" — muscle arrays only. Use ONLY when an existing tag is FACTUALLY WRONG (e.g. a
               pull-up tagged with Triceps — triceps extend, they don't pull). Removals are gated
               harder so be judicious.
  - "set"    — scalar fields only. Never on muscle arrays.

# CANONICAL MUSCLE NAMES — use these short forms ONLY

Lats (NOT 'Latissimus Dorsi'), Chest (NOT 'Pectorals'), Quads (NOT 'Quadriceps'),
Traps (NOT 'Trapezius'). Other accepted: Abs, Back, Biceps, Calves, Core, Forearms,
Front Delts, Full Body, Glutes, Hamstrings, Hip Flexors, Hips, Inner Thighs,
Lower Abs, Lower Back, Lower Chest, Neck, Obliques, Rear Delts, Rotator Cuff,
Shoulders, Side Delts, Triceps, Upper Back.

If you see a long-form name in the catalog (e.g. 'Latissimus Dorsi'), DO NOT propose a
remove for it — that's a taxonomy normalization issue handled by a different pipeline. Skip it.

# OUTPUT — RETURN ONLY THIS JSON, no prose, no code fences

{
  "proposals": [
    {
      "field": "primary_muscles|secondary_muscles|workout_type|equipment_category|is_compound|duration_based",
      "operation": "add|set|remove",
      "newValue": <array of strings | string | boolean — see field spec above>,
      "confidence": 1.0,
      "evidence": "<one-line factual reason>"
    }
  ]
}

If the exercise looks correct as-is, return {"proposals": []}. The response MUST start with { and end with }.

# WORKED EXAMPLES — DO

  - "Cable Front Raise" classified workout_type='Stretch' →
    {"field":"workout_type","operation":"set","newValue":"Strength","confidence":1.0,
     "evidence":"front raises against cable resistance are a strength movement, not a stretch"}.
  - "Cable Lateral Raise" missing 'Side Delts' that sister "DB Lateral Raise" has →
    {"field":"secondary_muscles","operation":"add","newValue":["Side Delts"],"confidence":1.0,
     "evidence":"sister DB Lateral Raise lists Side Delts; same biomechanics"}.
  - "Romanian Deadlift" has is_compound=FALSE →
    {"field":"is_compound","operation":"set","newValue":true,"confidence":1.0,
     "evidence":"hip + knee + spine extension is multi-joint"}.
  - "Plank" has duration_based=FALSE →
    {"field":"duration_based","operation":"set","newValue":true,"confidence":1.0,
     "evidence":"isometric hold — no rep count"}.
  - "Pull Up" tagged with secondary_muscles ['Triceps','Front Delts'] → emit TWO rows:
    add ['Biceps','Rear Delts'] AND remove ['Triceps','Front Delts'].

# WORKED EXAMPLES — DON'T

  - DON'T propose anything subjective (difficulty_level, popularity, priority).
  - DON'T add muscles "in case" they might be involved — only when factually clear.
  - DON'T rename an exercise.
  - DON'T use operation='set' on muscle arrays — use add/remove.
  - DON'T propose if you're <100% sure. The cost of a wrong correction polluting the
    catalog is much higher than the cost of leaving a sub-optimal value alone.`;

// ───────────────────────────────────────────────────────────────────────────
// Types
// ───────────────────────────────────────────────────────────────────────────

interface ExerciseRow {
    id: string;
    name: string;
    primary_muscles: string[] | null;
    secondary_muscles: string[] | null;
    equipment: string[] | string | null;
    equipment_category: string | null;
    exercise_family: string | null;
    is_compound: boolean | null;
    duration_based: boolean | null;
    workout_type: string | null;
    movement_pattern: string | null;
}

interface RawProposal {
    field?: string;
    operation?: string;
    newValue?: unknown;
    confidence?: number;
    evidence?: string;
}

interface ClaudeResponse {
    proposals?: RawProposal[];
}

interface NormalizedProposal {
    field: string;
    operation: "add" | "set" | "remove";
    newValue: unknown;
    confidence: number;
    evidence: string;
}

// ───────────────────────────────────────────────────────────────────────────
// Entry point
// ───────────────────────────────────────────────────────────────────────────

serve(async (req) => {
    const corsHeaders = buildCorsHeaders(req);
    if (req.method === "OPTIONS") {
        return new Response("ok", { headers: corsHeaders });
    }

    try {
        const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
        const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
        const anthropicKey = Deno.env.get("ANTHROPIC_API_KEY");

        if (!anthropicKey) {
            return json({ error: "ANTHROPIC_API_KEY not configured" }, 500, corsHeaders);
        }

        const supabase = createClient(supabaseUrl, supabaseServiceKey);

        const auth = resolveAuth(req, supabaseServiceKey);
        if (!auth.ok) return json(auth.error, auth.status, corsHeaders);

        let body: { exercise_id?: string; apply?: boolean } = {};
        try { body = await req.json(); } catch { /* empty body */ }
        const exerciseId = body.exercise_id;
        const apply = body.apply === true;
        if (!exerciseId || typeof exerciseId !== "string") {
            return json({ error: "exercise_id is required" }, 400, corsHeaders);
        }

        const { data: exerciseRaw, error: exErr } = await supabase
            .from("exercises")
            .select(
                "id, name, primary_muscles, secondary_muscles, equipment, " +
                "equipment_category, exercise_family, is_compound, duration_based, " +
                "workout_type, movement_pattern",
            )
            .eq("id", exerciseId)
            .maybeSingle();
        if (exErr) {
            return json({ error: `exercise lookup failed: ${exErr.message}` }, 500, corsHeaders);
        }
        if (!exerciseRaw) {
            return json({ error: "exercise not found" }, 404, corsHeaders);
        }
        const exercise = exerciseRaw as ExerciseRow;

        let sisters: ExerciseRow[] = [];
        if (exercise.exercise_family) {
            const { data: sisterRaw } = await supabase
                .from("exercises")
                .select(
                    "id, name, primary_muscles, secondary_muscles, equipment, " +
                    "equipment_category, exercise_family, is_compound, duration_based, " +
                    "workout_type, movement_pattern",
                )
                .eq("exercise_family", exercise.exercise_family)
                .neq("id", exercise.id)
                .limit(SISTERS_TO_INCLUDE);
            sisters = (sisterRaw ?? []) as ExerciseRow[];
        }

        const userMessage = buildUserMessage(exercise, sisters);

        let claudeText: string;
        let claudeUsage: { input?: number; output?: number; cache_read?: number; cache_write?: number } = {};
        try {
            const r = await callClaude(anthropicKey, userMessage);
            claudeText = r.text;
            claudeUsage = r.usage;
        } catch (e) {
            const msg = e instanceof Error ? e.message : String(e);
            return json({ error: `anthropic_${msg.slice(0, 200)}` }, 502, corsHeaders);
        }

        const parsed = parseClaudeJson(claudeText);
        if (!parsed) {
            console.error(
                `audit-catalog-exercise: JSON parse failed for ${exercise.name}`,
                claudeText.slice(0, 500),
            );
            return json({
                error: "json_parse",
                raw: claudeText.slice(0, 1000),
                usage: claudeUsage,
            }, 500, corsHeaders);
        }

        const normalized = normalizeProposals(parsed.proposals ?? []);

        if (!apply) {
            return json({
                exercise_id: exercise.id,
                exercise_name: exercise.name,
                proposals: normalized,
                usage: claudeUsage,
                applied: false,
            }, 200, corsHeaders);
        }

        const applyResults: Array<{
            field: string;
            operation: string;
            newValue: unknown;
            confidence: number;
            proposal_id?: string | null;
            auto_applied?: boolean;
            reason?: string;
            error?: string;
        }> = [];

        for (const p of normalized) {
            const { data: rpcResult, error: rpcErr } = await supabase.rpc(
                "propose_exercise_correction",
                {
                    p_exercise_id: exercise.id,
                    p_field_name: p.field,
                    p_operation: p.operation,
                    p_new_value: p.newValue,
                    p_confidence: p.confidence,
                    p_evidence: p.evidence,
                    p_source_report_id: null,
                },
            );
            if (rpcErr) {
                applyResults.push({
                    field: p.field,
                    operation: p.operation,
                    newValue: p.newValue,
                    confidence: p.confidence,
                    error: rpcErr.message,
                });
                continue;
            }
            const r = (rpcResult ?? {}) as {
                proposal_id?: string;
                auto_applied?: boolean;
                reason?: string;
            };
            applyResults.push({
                field: p.field,
                operation: p.operation,
                newValue: p.newValue,
                confidence: p.confidence,
                proposal_id: r.proposal_id ?? null,
                auto_applied: r.auto_applied ?? false,
                reason: r.reason,
            });
        }

        return json({
            exercise_id: exercise.id,
            exercise_name: exercise.name,
            proposals: normalized,
            apply_results: applyResults,
            usage: claudeUsage,
            applied: true,
        }, 200, corsHeaders);
    } catch (error) {
        console.error("audit-catalog-exercise error:", error);
        return json(
            { error: error instanceof Error ? error.message : String(error) },
            500,
            buildCorsHeaders(req),
        );
    }
});

// ───────────────────────────────────────────────────────────────────────────
// Auth — service-role only
// ───────────────────────────────────────────────────────────────────────────

type AuthDecision =
    | { ok: true }
    | { ok: false; status: number; error: { error: string } };

function resolveAuth(req: Request, supabaseServiceKey: string): AuthDecision {
    // Accept either the legacy service-role JWT (matches env directly OR
    // verifies as a service_role JWT for our project) OR the new
    // `sb_secret_…` opaque secret format that Supabase rolled out 2026.
    // The platform's `verify_jwt: true` already gates the request before
    // it reaches us, so by the time we run we know SOME credential was
    // accepted. We just need to confirm it's service-role-level (NOT a
    // user JWT — that would let any authenticated user mass-audit the
    // catalog).
    const cronKey = req.headers.get("x-cron-key");
    if (cronKey && isServiceRoleJWT(cronKey)) {
        return { ok: true };
    }

    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
        return { ok: false, status: 401, error: { error: "Missing authorization" } };
    }

    const token = authHeader.replace("Bearer ", "");

    // 1. Direct match against env-injected legacy service-role JWT.
    if (token === supabaseServiceKey) return { ok: true };

    // 2. Token IS a valid service-role JWT for our project (handles the
    //    case where the key was rotated and env hasn't refreshed).
    if (isServiceRoleJWT(token)) return { ok: true };

    // 3. New-format opaque secret. These are not JWTs — they look like
    //    `sb_secret_<base62>`. The platform itself only lets these through
    //    when the value is genuinely a secret-tier key, so prefix-match is
    //    a sufficient gate at this layer.
    if (token.startsWith("sb_secret_")) return { ok: true };

    return { ok: false, status: 403, error: { error: "Service-role required" } };
}

// ───────────────────────────────────────────────────────────────────────────
// Prompt assembly
// ───────────────────────────────────────────────────────────────────────────

function buildUserMessage(target: ExerciseRow, sisters: ExerciseRow[]): string {
    const slim = (e: ExerciseRow) => ({
        name: e.name,
        primary_muscles: e.primary_muscles,
        secondary_muscles: e.secondary_muscles,
        equipment: e.equipment,
        equipment_category: e.equipment_category,
        exercise_family: e.exercise_family,
        is_compound: e.is_compound,
        duration_based: e.duration_based,
        workout_type: e.workout_type,
        movement_pattern: e.movement_pattern,
    });

    const payload = {
        target: slim(target),
        sisters: sisters.map(slim),
    };

    return [
        "Audit this single catalog exercise. Return ONLY the JSON described in the system prompt.",
        "Be conservative — anything below 100% certainty MUST be omitted.",
        "Use sister exercises as a reference for what fields SHOULD look like, but do not blindly mirror them.",
        "",
        "INPUT:",
        JSON.stringify(payload),
    ].join("\n");
}

// ───────────────────────────────────────────────────────────────────────────
// Anthropic call (with prompt caching on the system prompt)
// ───────────────────────────────────────────────────────────────────────────

async function callClaude(
    anthropicKey: string,
    userMessage: string,
): Promise<{
    text: string;
    usage: { input?: number; output?: number; cache_read?: number; cache_write?: number };
}> {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort("claude timeout"), CLAUDE_TIMEOUT_MS);

    try {
        const response = await fetch(ANTHROPIC_API_URL, {
            method: "POST",
            headers: {
                "content-type": "application/json",
                "x-api-key": anthropicKey,
                "anthropic-version": ANTHROPIC_VERSION,
            },
            signal: controller.signal,
            body: JSON.stringify({
                model: MODEL,
                max_tokens: CLAUDE_MAX_TOKENS,
                system: [
                    {
                        type: "text",
                        text: SYSTEM_PROMPT,
                        cache_control: { type: "ephemeral" },
                    },
                ],
                messages: [{ role: "user", content: userMessage }],
            }),
        });

        if (!response.ok) {
            const errBody = await response.text().catch(() => "<no body>");
            throw new Error(`${response.status}_${errBody.slice(0, 200)}`);
        }

        const completion = await response.json() as {
            content?: Array<{ type: string; text?: string }>;
            stop_reason?: string;
            usage?: {
                input_tokens?: number;
                output_tokens?: number;
                cache_read_input_tokens?: number;
                cache_creation_input_tokens?: number;
            };
        };
        const block = completion.content?.find((b) => b.type === "text");
        const text = block?.text ?? "";
        return {
            text,
            usage: {
                input: completion.usage?.input_tokens,
                output: completion.usage?.output_tokens,
                cache_read: completion.usage?.cache_read_input_tokens,
                cache_write: completion.usage?.cache_creation_input_tokens,
            },
        };
    } finally {
        clearTimeout(timer);
    }
}

// ───────────────────────────────────────────────────────────────────────────
// Strict JSON parse with first-balanced-block salvage (mirrors
// analyze-quality-workout)
// ───────────────────────────────────────────────────────────────────────────

function parseClaudeJson(text: string): ClaudeResponse | null {
    if (!text) return null;
    try {
        return JSON.parse(text) as ClaudeResponse;
    } catch {
        // fall through
    }

    const firstBrace = text.indexOf("{");
    if (firstBrace < 0) return null;

    let depth = 0, inString = false, escape = false, end = -1;
    for (let i = firstBrace; i < text.length; i++) {
        const ch = text[i];
        if (escape) { escape = false; continue; }
        if (ch === "\\") { escape = true; continue; }
        if (ch === '"') { inString = !inString; continue; }
        if (inString) continue;
        if (ch === "{") depth++;
        else if (ch === "}") { depth--; if (depth === 0) { end = i; break; } }
    }
    if (end < 0) return null;
    try {
        return JSON.parse(text.slice(firstBrace, end + 1)) as ClaudeResponse;
    } catch {
        return null;
    }
}

// ───────────────────────────────────────────────────────────────────────────
// Proposal normalization (mirrors analyze-quality-workout's applyCorrections
// pre-filter so the propose RPC never gets bad shapes)
// ───────────────────────────────────────────────────────────────────────────

function normalizeProposals(raw: RawProposal[]): NormalizedProposal[] {
    const out: NormalizedProposal[] = [];
    for (const p of raw) {
        if (!p || typeof p !== "object") continue;

        const field = String(p.field ?? "");
        if (!CORRECTION_FIELD_WHITELIST.has(field)) continue;

        const confidence = typeof p.confidence === "number" ? p.confidence : 0;
        if (confidence <= 0 || confidence > 1) continue;

        const isMuscleField = field === "primary_muscles" || field === "secondary_muscles";
        const operationRaw = String(p.operation ?? "").toLowerCase();
        const operation = (operationRaw || (isMuscleField ? "add" : "set")) as
            "add" | "set" | "remove";
        if (!["add", "set", "remove"].includes(operation)) continue;
        if (isMuscleField && operation === "set") continue;
        if (!isMuscleField && operation !== "set") continue;

        const newValue = normalizeValue(field, p.newValue);
        if (newValue === undefined) continue;

        const evidence = String(p.evidence ?? "").trim().slice(0, 1000);
        if (!evidence) continue;

        out.push({ field, operation, newValue, confidence, evidence });
    }
    return out;
}

function normalizeValue(field: string, raw: unknown): unknown {
    switch (field) {
        case "primary_muscles":
        case "secondary_muscles": {
            if (!Array.isArray(raw)) return undefined;
            const arr = raw.map((x) => String(x).trim()).filter((x) => x.length > 0);
            if (arr.length === 0) return undefined;
            return arr;
        }
        case "is_compound":
        case "duration_based": {
            if (typeof raw === "boolean") return raw;
            if (raw === "true") return true;
            if (raw === "false") return false;
            return undefined;
        }
        case "workout_type": {
            if (typeof raw !== "string") return undefined;
            const v = raw.trim();
            return VALID_WORKOUT_TYPE.has(v) ? v : undefined;
        }
        case "equipment_category": {
            if (typeof raw !== "string") return undefined;
            const v = raw.trim();
            return v.length > 0 ? v : undefined;
        }
        default:
            return undefined;
    }
}

function json(body: unknown, status: number, corsHeaders: Record<string, string>): Response {
    return new Response(JSON.stringify(body), {
        status,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
}
