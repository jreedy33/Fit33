// Supabase Edge Function: audit-autogen-workout
// -----------------------------------------------------------------------------
// Multi-agent Claude review of an auto-generated workout. Drives the autogen
// audit simulator (`scripts/autogen_audit_simulator.py`).
//
// CONTEXT
//   Existing in-app heuristics already enforce most fitness rules
//   (`SmartExerciseSelectionEngine.swift`, `WorkoutComboRules.swift`,
//   `FoundationalExerciseDatabase.swift`). This function does a SECOND PASS:
//   a generative model with the FE + PE invariants in its system prompt
//   reads each generated workout against the full user profile and either
//   approves it or returns concrete, actionable improvement suggestions.
//
// PIPELINE (per request — ONE workout per call so we can parallelize at
// the orchestrator layer)
//   1. Receive user profile + generated workout in the body.
//   2. Build a slim Claude prompt. System prompt is intentionally
//      >1024 tokens so the prompt-cache discount applies on every
//      call after the first.
//   3. Parse strict JSON. Fields are NOT applied to any database — this
//      is a read-only audit; the orchestrator aggregates results into
//      a markdown report.
//
// INVOCATION
//   POST {
//     user_profile: { ... see UserProfile type below ... },
//     workout: { target_muscles, exercises: [{ name, equipment, primary_muscles, ... }] }
//   }
//   - Service-role auth REQUIRED. No user-JWT path — admin/orchestration only.
//
// AUTH
//   Authorization: Bearer <service_role_key | service_role_JWT>
//   x-cron-key: <service_role_JWT> (alternative)
//
// SECRETS
//   ANTHROPIC_API_KEY, SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
//
// Deploy: supabase functions deploy audit-autogen-workout
// -----------------------------------------------------------------------------

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { buildCorsHeaders } from "../_shared/cors.ts";

// ───────────────────────────────────────────────────────────────────────────
// Constants
// ───────────────────────────────────────────────────────────────────────────

const ANTHROPIC_API_URL = "https://api.anthropic.com/v1/messages";
const ANTHROPIC_VERSION = "2023-06-01";

const MODEL = "claude-sonnet-4-20250514";
const CLAUDE_MAX_TOKENS = 2048;
const CLAUDE_TIMEOUT_MS = 45_000;

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
        if (payload.ref === EXPECTED_PROJECT_REF) return true;
        if (
            typeof payload.iss === "string" &&
            payload.iss.includes(`/projects/${EXPECTED_PROJECT_REF}/`)
        ) {
            return true;
        }
        return false;
    } catch {
        return false;
    }
}

// ───────────────────────────────────────────────────────────────────────────
// SYSTEM PROMPT — multi-agent persona (Fitness Expert + Product Engineer)
//
// Intentionally >1024 tokens so prompt caching kicks in. The invariants
// list below MUST stay in lockstep with `FITNESS_EXPERT_AGENT.md` and
// `PRODUCT_ENGINEER_AGENT.md`. When you change an invariant in either
// agent doc, mirror the relevant rule here.
// ───────────────────────────────────────────────────────────────────────────

const SYSTEM_PROMPT = `You are the Fit33 Auto-Gen Reviewer — a panel of TWO agents speaking with one voice:

  • Fitness Expert  — exercise-science authority. Cares about whether the workout is SAFE, EFFECTIVE, APPROPRIATE for the user's level, BALANCED across the program, and PRACTICAL with the user's equipment.

  • Product Engineer — owner of the in-app autogen logic in Swift (\`SmartExerciseSelectionEngine\`, \`WorkoutComboRules\`, \`FoundationalExerciseDatabase\`, \`SmartExercisePairingEngine\`). Cares about whether each issue points to a CONCRETE, ACTIONABLE filter / scoring / pairing / classification fix in code.

You read ONE generated workout for ONE user profile and return a structured JSON review. The orchestrator aggregates many of your reviews into a markdown report that the engineering team uses to improve the recommender.

# THE FITNESS EXPERT INVARIANTS YOU ENFORCE

Program / workout structure:
1. Compound before isolation. Larger muscle groups before smaller. Olympic > Heavy compound > Secondary compound > Isolation > Core LAST.
2. Push:pull balance ≤ 2:1 in either direction within a workout.
3. Max 2 horizontal presses per workout. No 3× bench variations.
4. Max 1 heavy hinge per workout. Deadlift + Barbell Row + Back Extension is a TRIPLE spinal load — block.
5. Unilateral work on leg days (lunge / split squat / step-up / single-leg press).
6. Balance slot enforced — rear delt on push days, core on leg days.
7. No neglected muscle groups across a multi-day program (rear delts, hamstrings, calves, rotator cuff, forearms must all appear).

Volume + rep science:
8. Beginner = 10-12 sets/muscle/week, 8-15 reps, RIR 3-4. Intermediate = 12-18 sets, 6-12 reps, RIR 2-3. Advanced = 16-22 sets, 3-15 reps periodized, RIR 0-2.
9. 2x/week per muscle is the optimal frequency for hypertrophy (Schoenfeld 2016).

Progressive overload + set handling:
10. Minimum 3 sets per new/shuffled exercise.
11. Weight increment rule: +5lb if current ≥ 30lb, +2.5lb if < 30lb.

Beginner safety (HARD invariants):
12. NO Olympic lifts (clean, snatch, jerk, hang clean, power clean) for beginners.
13. NO behind-neck press / behind-neck pulldown for ANY level.
14. NO max-effort singles for beginners.
15. NO upright row, NO good morning, NO guillotine press for ANY level (auto-recommended).

# SPECIALTY VARIANTS (the bug we are hunting)

A SPECIALTY VARIANT is a base exercise plus a programming modifier that requires the user to already own the base movement. Common examples:

  • Bench press family: "Feet On Bench …", "Feet Up …", "Feet Elevated …", "Spoto Press", "Pin Press", "Paused Bench", "Long Pause Bench", "Board Press", "Slingshot Bench", "Guillotine Press", "JM Press", "Close Grip Incline", "Reverse Grip Bench", "Wide Grip Bench".
  • Squat family: "Deficit Squat", "Paused Squat", "Pause Squat", "Anderson Squat", "1 1/4 Squat", "1.5 Squat", "Tempo Squat", "Pin Squat", "Box Squat", "Zercher Squat", "Sissy Squat", "Heels Elevated …".
  • Deadlift family: "Deficit Deadlift", "Snatch Grip Deadlift", "Block Pull", "Paused Deadlift", "Tempo Deadlift", "Reset Deadlift", "Touch and Go", "Stiff Leg Deadlift".
  • Row family: "Yates Row", "Pendlay Row", "Meadows Row", "Paused Row", "Tempo Row", "Kroc Row".
  • Curl family: "21s", "Drag Curl", "Zottman Curl", "Waiter Curl", "Bayesian Curl".
  • OHP family: "Z Press", "Savickas Press", "Bradford Press", "Cuban Press", "Sots Press", "Viking Press", "Landmine Press".
  • Generic prescription modifiers: "Tempo …", "Paused …", "1 1/4 …", "1.5 …", "Rest Pause", "Myo-Rep", "Cluster Set", "Drop Set", "With Chains", "Banded …", "Eccentric Only", "Isometric Hold".

Severity bands:
  • block_beginner       → never recommend to a beginner; intermediate/advanced ok
  • block_intermediate   → block beginner AND intermediate; advanced only
  • block_all            → never auto-recommend regardless of level (high injury risk)

The autogen MUST NEVER show a specialty variant to a level where it's blocked, AND MUST NEVER show a specialty variant ahead of the canonical base movement (e.g. "Spoto Press" before regular Bench Press is wrong even for an advanced lifter on a hypertrophy day).

# WHAT YOU OUTPUT

You return ONE JSON object. Be specific — every "issue" must reference an exercise by index (0-based), and every "improvement_suggestion" must point at a concrete code/data location (e.g. "extend obscureExercises array in SmartExerciseSelectionEngine.swift line ~963", "add 'feet on bench' to specialty filter").

OUTPUT — RETURN ONLY THIS JSON, no prose, no code fences, no preamble:

{
  "overall_rating": <integer 1-10, where 10 = canonical perfect workout for this user>,
  "fitness_expert_summary": "<2-3 sentences: would a coach prescribe this workout for this user? What's strongest, what's weakest?>",
  "product_engineer_summary": "<2-3 sentences: where in code should we LOOK to improve this output for users like this one?>",
  "issues": [
    {
      "exercise_index": <0-based index into workout.exercises, or -1 for whole-workout issues>,
      "exercise_name": "<exact name of the offending exercise, or empty for workout-level>",
      "category": "<one of: 'specialty_variant_for_level', 'risky_for_level', 'volume_imbalance', 'redundant_movement_pattern', 'compound_after_isolation', 'missing_balance_slot', 'equipment_mismatch', 'injury_unsafe', 'beginner_complexity', 'obscure_exercise', 'wrong_split_for_days', 'wrong_rep_range_for_goal', 'other'>",
      "severity": "<'critical' | 'major' | 'minor'>",
      "description": "<one-sentence factual issue>",
      "fix_suggestion": "<one-sentence concrete fix — name the data field, code location, or rule to add/change>"
    }
  ],
  "improvement_suggestions": [
    {
      "owner": "<'fitness_expert' | 'product_engineer'>",
      "priority": "<'high' | 'medium' | 'low'>",
      "title": "<imperative — e.g. 'Block specialty variants for beginners by name pattern'>",
      "rationale": "<1-3 sentences why this fix would have prevented the issue>",
      "concrete_change": "<file path + function/section the engineer should edit, or rule the FE should add>"
    }
  ],
  "beginner_appropriateness": {
    "is_user_beginner": <bool>,
    "all_common_exercises": <bool — true if every exercise is a foundational/canonical movement, no specialty variants and no obscure picks>,
    "specialty_variants_present": [<exercise names that are specialty variants for this level — empty array if none>]
  },
  "kept_or_swap": {
    "verdict": "<'ship' | 'minor_revision' | 'significant_revision' | 'reject'>",
    "rationale": "<one sentence>"
  }
}

The response MUST start with { and end with }. No code fences, no prose.

# WORKED EXAMPLES — DO

  • A beginner gym user gets "Feet On Bench Barbell Bench Press" as their FIRST chest exercise →
    issue: { exercise_index: 0, category: 'specialty_variant_for_level', severity: 'critical',
             description: 'Specialty stability variant; beginner has not yet owned the regular flat bench press.',
             fix_suggestion: "Add 'feet on bench' to the specialty filter; require canonical base movement first for level=Beginner." }
    improvement_suggestion: { owner: 'product_engineer', priority: 'high',
             title: 'Add specialty-variant name-pattern filter for beginners',
             concrete_change: 'Fit33/SmartExerciseSelectionEngine.swift assessExercisePracticality()' }

  • Push day with Bench / Incline Bench / Decline Bench / Dumbbell Bench Press →
    issue: { exercise_index: -1, category: 'redundant_movement_pattern', severity: 'major',
             description: '4 horizontal press variations on one push day — exceeds 2-press cap.',
             fix_suggestion: 'Tighten horizontalPress.maxPerWorkout=2 enforcement in SmartExerciseSelectionEngine.' }

  • Female 65 yo gets "Box Jump" as second exercise →
    issue: { ..., category: 'risky_for_level', severity: 'critical',
             fix_suggestion: 'Add age >= 60 → block plyometrics rule.' }

# WORKED EXAMPLES — DON'T

  • DON'T penalize "Trap Bar Deadlift" for an intermediate — that's a fine first deadlift variant.
  • DON'T flag legitimate compounds (squat, bench, deadlift, OHP, row, pull-up) just because they "look hard".
  • DON'T propose changes to subjective fields (difficulty_level, popularity, priority).
  • DON'T flag missing rear delts on a Pull day — rows already train rear delts.
  • DON'T suggest the user pick different equipment — your job is to evaluate what the autogen produced for the equipment they DID pick.`;

// ───────────────────────────────────────────────────────────────────────────
// Types
// ───────────────────────────────────────────────────────────────────────────

interface UserProfile {
    name?: string;
    age?: number;
    gender?: string;
    weight_lbs?: number;
    height_inches?: number;
    experience_level?: string; // "Beginner" | "Intermediate" | "Advanced"
    fitness_goal?: string;     // one of the 6 onboarding goals
    workout_location?: string; // "gym" | "home" | "outdoor" | "hybrid"
    available_equipment?: string[];
    injuries?: Array<{ area: string; severity?: string; description?: string }>;
    workouts_completed?: number;
    preferred_workout_duration?: number;
    available_days_per_week?: number;
    notes?: string;
}

interface WorkoutExercise {
    name: string;
    equipment?: string;
    primary_muscles?: string[];
    secondary_muscles?: string[];
    is_compound?: boolean;
}

interface GeneratedWorkout {
    target_muscles: string[];
    workout_type?: string; // "Push" | "Pull" | "Legs" | "Upper" | "Lower" | "Full Body" | etc.
    exercises: WorkoutExercise[];
}

interface AuditRequestBody {
    user_profile?: UserProfile;
    workout?: GeneratedWorkout;
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
        const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
        const anthropicKey = Deno.env.get("ANTHROPIC_API_KEY");

        if (!anthropicKey) {
            return json({ error: "ANTHROPIC_API_KEY not configured" }, 500, corsHeaders);
        }

        const auth = resolveAuth(req, supabaseServiceKey);
        if (!auth.ok) return json(auth.error, auth.status, corsHeaders);

        let body: AuditRequestBody = {};
        try { body = await req.json(); } catch { /* empty */ }

        const userProfile = body.user_profile;
        const workout = body.workout;

        if (!userProfile || typeof userProfile !== "object") {
            return json({ error: "user_profile is required" }, 400, corsHeaders);
        }
        if (!workout || !Array.isArray(workout.exercises) || workout.exercises.length === 0) {
            return json({ error: "workout.exercises is required and non-empty" }, 400, corsHeaders);
        }

        const userMessage = buildUserMessage(userProfile, workout);

        let claudeText: string;
        let claudeUsage: {
            input?: number;
            output?: number;
            cache_read?: number;
            cache_write?: number;
        } = {};
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
                "audit-autogen-workout: JSON parse failed",
                claudeText.slice(0, 500),
            );
            return json({
                error: "json_parse",
                raw: claudeText.slice(0, 1500),
                usage: claudeUsage,
            }, 500, corsHeaders);
        }

        return json({
            review: parsed,
            usage: claudeUsage,
        }, 200, corsHeaders);
    } catch (error) {
        console.error("audit-autogen-workout error:", error);
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
    const cronKey = req.headers.get("x-cron-key");
    if (cronKey && isServiceRoleJWT(cronKey)) return { ok: true };

    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
        return { ok: false, status: 401, error: { error: "Missing authorization" } };
    }
    const token = authHeader.replace("Bearer ", "");
    if (token === supabaseServiceKey) return { ok: true };
    if (isServiceRoleJWT(token)) return { ok: true };
    if (token.startsWith("sb_secret_")) return { ok: true };
    return { ok: false, status: 403, error: { error: "Service-role required" } };
}

// ───────────────────────────────────────────────────────────────────────────
// Prompt assembly
// ───────────────────────────────────────────────────────────────────────────

function buildUserMessage(profile: UserProfile, workout: GeneratedWorkout): string {
    // Slim each exercise to the fields Claude actually needs.
    const slimExercises = workout.exercises.map((ex, idx) => ({
        index: idx,
        name: ex.name ?? "",
        equipment: ex.equipment ?? "",
        primary_muscles: ex.primary_muscles ?? [],
        secondary_muscles: ex.secondary_muscles ?? [],
        is_compound: typeof ex.is_compound === "boolean" ? ex.is_compound : null,
    }));

    const payload = {
        user_profile: {
            age: profile.age ?? null,
            gender: profile.gender ?? null,
            weight_lbs: profile.weight_lbs ?? null,
            height_inches: profile.height_inches ?? null,
            experience_level: profile.experience_level ?? null,
            fitness_goal: profile.fitness_goal ?? null,
            workout_location: profile.workout_location ?? null,
            available_equipment: profile.available_equipment ?? [],
            injuries: profile.injuries ?? [],
            workouts_completed: profile.workouts_completed ?? 0,
            preferred_workout_duration: profile.preferred_workout_duration ?? null,
            available_days_per_week: profile.available_days_per_week ?? null,
            notes: profile.notes ?? null,
        },
        workout: {
            target_muscles: workout.target_muscles ?? [],
            workout_type: workout.workout_type ?? null,
            exercise_count: slimExercises.length,
            exercises: slimExercises,
        },
    };

    return [
        "Audit this single auto-generated workout for this single user. Return ONLY the JSON described in the system prompt.",
        "Be specific: every issue must point at an exercise index, every improvement must point at a code/data location.",
        "If the workout is genuinely good, return overall_rating >= 8 with a short fitness_expert_summary and an empty issues array.",
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
    usage: {
        input?: number;
        output?: number;
        cache_read?: number;
        cache_write?: number;
    };
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
// Strict JSON parse with first-balanced-block salvage
// (mirrors audit-catalog-exercise / analyze-quality-workout)
// ───────────────────────────────────────────────────────────────────────────

function parseClaudeJson(text: string): Record<string, unknown> | null {
    if (!text) return null;
    try {
        return JSON.parse(text) as Record<string, unknown>;
    } catch { /* fall through */ }

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
        return JSON.parse(text.slice(firstBrace, end + 1)) as Record<string, unknown>;
    } catch {
        return null;
    }
}

function json(body: unknown, status: number, corsHeaders: Record<string, string>): Response {
    return new Response(JSON.stringify(body), {
        status,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
}
