// Supabase Edge Function: analyze-quality-workout
// -----------------------------------------------------------------------------
// Migration #156 (Workout Intelligence). Turns each quality workout
// (score >= 70 — see migration 20260725_workout_intelligence.sql) into
// structured "Workout Intelligence" by sending the workout + its
// surrounding context to Claude and writing the resulting report back to
// `ai_workout_reports`. Also auto-applies any 100%-confident exercise
// catalog corrections via the `apply_exercise_correction` RPC and
// upserts pairing intelligence into `pairing_signals`.
//
// PIPELINE (per run, MAX_REPORTS_PER_RUN at a time)
//   1. Pick rows from `ai_workout_reports` where status = 'pending'
//      (oldest first). Body may pin specific workout_ids.
//   2. Mark rows status='analyzing' so concurrent cron runs skip them.
//   3. For EACH workout, sequentially:
//        a. Gather workout_history row, set-level data, swap events,
//           user_profiles, last 4 quality workouts, exercise catalog.
//        b. Run a deterministic pre-flight suspicious-pattern check.
//           If suspicious, mark status='skipped' and SKIP Claude.
//        c. Build the Claude prompt + call Anthropic API (Sonnet 4).
//        d. Parse strict JSON, write to ai_workout_reports.
//        e. For each exerciseCorrection where confidence === 1.0 AND
//           field is on the whitelist, call apply_exercise_correction.
//           Per-correction errors are logged but never fail the report.
//        f. Upsert pairing_signals for every synergistic / mistake
//           pairingFinding. exercise_a_id < exercise_b_id (lex order)
//           so (A,B) and (B,A) collapse onto a single row.
//
// INVOCATION
//   POST { workout_ids?: ["uuid", ...], source?: "cron"|"manual" }
//   - Service-role JWT (cron / admin CMS / fire-and-forget) → no per-row gate.
//   - Authenticated user JWT (iOS post-completion fire-and-forget) → ONLY
//     reports for workouts owned by auth.uid() are processed.
//
// AUTH
//   Accepts EITHER:
//     - Authorization: Bearer <service_role_key | service_role_JWT>
//     - x-cron-key: <service_role_JWT> (cron preferred path)
//     - Authorization: Bearer <user_JWT> (iOS fire-and-forget)
//
// SECRETS required
//   ANTHROPIC_API_KEY, SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
//
// Deploy: supabase functions deploy analyze-quality-workout
// Cron (FOLLOW-UP — not part of this PR): pg_cron schedule every 10 minutes.
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
const CLAUDE_MAX_TOKENS = 8192;
const MAX_REPORTS_PER_RUN = 10;
const PER_WORKOUT_TIMEOUT_MS = 30_000;

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
        const payload = JSON.parse(atob(parts[1]));
        if (payload.role !== "service_role") return false;
        if (!EXPECTED_PROJECT_REF) return false;
        return payload.ref === EXPECTED_PROJECT_REF;
    } catch {
        return false;
    }
}

// ───────────────────────────────────────────────────────────────────────────
// SYSTEM PROMPT
//   Embedded verbatim. Mirrors the structure of triage-shake-reports'
//   SYSTEM_PROMPT — single canonical role description, output schema,
//   then explicit DO / DON'T rules.
// ───────────────────────────────────────────────────────────────────────────

const SYSTEM_PROMPT = `You are the Fit33 Workout Intelligence Agent. You analyze QUALITY workouts \
(score >= 70) to extract pairings, pacing, swap behavior, progression, red flags, and \
100%-confident exercise catalog corrections. Each request gives you ONE workout plus \
all of its surrounding context (set-level data, swap events, the user's profile, the \
user's last 4 quality workouts, and the catalog metadata for every exercise that \
appears in this workout).

Your output feeds two systems:
  (1) the auto-gen + smart-pairing recommender (pairingFindings, recommenderSignals,
      progressionEvidence, pacingProfile)
  (2) the canonical exercises catalog itself (exerciseCorrections — auto-applied
      ONLY at confidence === 1.0).

Both systems are deterministic about your output. If you emit a wrong correction,
the catalog gets polluted. If you emit a wrong pairingFinding, the recommender
biases the next workout the user sees. So: be conservative. When in doubt, leave
the field out — never guess.

# FE INVARIANTS (the report MUST surface violations against these)

Paraphrased from FITNESS_EXPERT_AGENT.md. Every violation observed becomes a redFlag:

  - Compound before isolation; large muscles before small.
  - Push:pull ratio <= 2:1 within a session AND across the program.
  - Max 2 horizontal presses per session (bench, DB press, machine press, etc.).
  - Max 1 heavy hinge per session (deadlift family).
  - Unilateral required on leg days (1+ unilateral lower-body movement).
  - Balance slot enforced: rear-delt accessory on push days; core slot on leg days.
  - Beginner constraints: NO Olympic lifts, NO behind-neck movements, NO max
    singles. <= 12 working sets per muscle group per session.
  - Red recovery (.red quality_band) -> strength session is a violation;
    BLOCK from corpus and emit redFlag with severity='block'.

# OUTPUT JSON SCHEMA — return EXACTLY this shape, no prose, no code fences

{
  "schema_version": 1,
  "splitFamily": "push|pull|legs|upper|lower|full_body|chest|back|shoulders|arms|core|cardio|recovery|mixed",
  "primaryGoalInferred": "strength|hypertrophy|endurance|power|conditioning",
  "volumeBalance": {
    "pushSets": <int>, "pullSets": <int>, "hingeSets": <int>,
    "squatSets": <int>, "unilateralSets": <int>, "coreSets": <int>,
    "ratioPushPull": <float>
  },
  "pressDistribution": {
    "horizontalPresses": <int>, "verticalPresses": <int>,
    "frontDeltSets": <int>, "rearDeltSets": <int>
  },
  "orderingScore": <float 0..1>,
  "pairingQuality": <float 0..1>,
  "pairingFindings": [
    {
      "type": "synergistic|antagonist_opportunity|mistake",
      "exercises": ["<exact catalog name 1>", "<exact catalog name 2>"],
      "code": "bench_triceps_synergy|front_delt_overload|...",
      "note": "<one-line rationale>"
    }
  ],
  "pacingProfile": {
    "avgRestSec": <int>,                            // single workout-wide average (REQUIRED)
    "restPerExerciseSec": { "<exerciseName>": <int> }, // per-exercise breakdown (optional)
    "restBuckets": { "rushed": <int>, "normal": <int>, "dawdled": <int> },
    "inferredIntent": "strength|hypertrophy|endurance|circuit|mixed",
    "intentMatchesGoal": <bool>
  },
  "progressionEvidence": [
    {
      "exerciseName": "<exact catalog name>",
      "kind": "weight_up|reps_up|volume_up|amrap_push|maintained|regressed",
      "delta": {
        "topSetWeight": <float>, "topSetReps": <int>, "totalVolume": <float>
      },
      "triggerMet": <bool>,
      "progressionSafe": <bool>
    }
  ],
  "swapInsights": [
    {
      "swapEventId": "<uuid from input>",
      "swapClass": "equipment_variant|complementary|cross_muscle|out_of_pool",
      "swapIntent": "smart|diluting|escape",
      "completedReplacement": <bool>
    }
  ],
  "redFlags": [
    {
      "code": "red_recovery_violation|excessive_spinal_load|front_delt_overload|push_pull_imbalance_program|beginner_overvolume|beginner_advanced_movement|<other>",
      "severity": "info|warn|block",
      "evidence": "<short evidence string>"
    }
  ],
  "exerciseCorrections": [
    {
      "exerciseName": "<exact catalog name>",
      "field": "primary_muscles|secondary_muscles|workout_type|equipment_category|is_compound|duration_based",
      "operation": "add|set|remove",
      "newValue": <any — see types below>,
      "confidence": 1.0,
      "evidence": "<why you are 100% certain>"
    }
  ],
  "programmedVsExecuted": {
    "weightDelta": <float>,
    "repsDelta": <float>,
    "setCountDelta": <int>,
    "summary": "<one line>"
  },
  "recommenderSignals": [
    {
      "signalType": "swap_bias|pairing_negative|pairing_positive|volume_preference|rest_preference",
      "key": "<short key>",
      "value": <any>,
      "weight": <float 0..1>,
      "evidence": "<one line>"
    }
  ],
  "summaryMd": "<5-line MAX human-readable summary, plain text, no markdown>"
}

# CORRECTION POLICY (read this carefully)

Every correction enters a corroboration queue (exercise_correction_proposals).
A correction auto-applies to the canonical exercises catalog ONLY if confidence===1.0
AND a deterministic gate passes:
  - sister-exercise gate: a sibling in the same exercise_family already has the proposed value
  - name gate: the exercise name unambiguously implies the value
  - multi-report gate: the SAME correction has been proposed in >=2 distinct reports
    (>=3 for REMOVE operations)

Otherwise the proposal sits in the queue until corroborated or admin-approved.
Your job is to propose accurately; the system handles whether to auto-apply.

The whitelist of field values is exactly:

  - primary_muscles      (operation: "add" or "remove" — array of strings)
  - secondary_muscles    (operation: "add" or "remove" — array of strings)
  - workout_type         (operation: "set" — one of "Strength"|"Stretch"|"Plyometrics"|"Cardio")
  - equipment_category   (operation: "set" — short string e.g. "Cable"|"Dumbbell"|"Barbell")
  - is_compound          (operation: "set" — true|false)
  - duration_based       (operation: "set" — true|false)

Anything else — difficulty_level, priority scores, exercise_family, complementary_families,
icon, description, video_url — MUST NOT appear in this array. Ever.

OPERATIONS — choose the right one:
  - "add"    — for muscle arrays only. Adds values to the existing array. Use this
               when the exercise is MISSING a muscle that should be there.
  - "remove" — for muscle arrays only. Removes values from the existing array. Use
               this ONLY when an existing tag is FACTUALLY WRONG (e.g. a pull-up
               tagged with Triceps — triceps extend, they don't pull). Removals
               are gated harder so be judicious.
  - "set"    — for scalar fields only.

ACCEPTABLE corrections (do these):
  - "Cable Front Raise" classified workout_type='Stretch' -> {field:'workout_type',
    operation:'set', newValue:'Strength', confidence:1.0}.
  - "Cable Lateral Raise" missing 'Side Delts' that sister "DB Lateral Raise" has ->
    {field:'secondary_muscles', operation:'add', newValue:['Side Delts'], confidence:1.0}.
  - "Romanian Deadlift" has is_compound=FALSE -> {field:'is_compound', operation:'set',
    newValue:true, confidence:1.0}.
  - "Plank" has duration_based=FALSE -> {field:'duration_based', operation:'set',
    newValue:true, confidence:1.0}.
  - "Pull Up" tagged with secondary_muscles ['Triceps','Front Delts'] -> emit TWO
    rows: ADD ['Biceps','Rear Delts'] AND REMOVE ['Triceps','Front Delts'].

UNACCEPTABLE corrections (NEVER do these):
  - Anything subjective (difficulty_level, priority scores).
  - Adding muscles "in case" they might be involved — only when factually clear.
  - Renaming an exercise.
  - operation='set' on muscle arrays — use add/remove instead.
  - Anything for a sub-classification you're <100% sure about.

# PAIRING FINDINGS

Emit pairingFindings for any noteworthy pairing — synergistic OR mistake. These
upsert into pairing_signals. Use the EXACT exercise names from the input
exercise_catalog so we can resolve them to UUIDs. Examples:
  - { type: "synergistic", exercises: ["Barbell Bench Press","Triceps Pushdown"],
      code: "bench_triceps_synergy", note: "..." }
  - { type: "mistake", exercises: ["Front Raise","DB Shoulder Press"],
      code: "front_delt_overload", note: "..." }

# PROGRESSION EVIDENCE

Use the previous_quality_workouts array to compare top-set weight x top-set reps
x total volume per exercise. Mark triggerMet true if the user hit the prior
program's progression criterion (top set RIR <= 1 OR completed all sets at target
reps). Mark progressionSafe false ONLY if the increase was >5% on a hinge or
>10% on an isolation — flag risky jumps as info-level redFlags.

# RED FLAGS

These map onto the FE invariants section. Use severity:
  - info  -> noteworthy but acceptable.
  - warn  -> recommender should bias against this in next session.
  - block -> corpus exclusion. Use sparingly — only red_recovery_violation,
            true safety issue, or genuine programming error.

# OUTPUT FORMAT — STRICT

Return ONLY the JSON object. No prose before or after. No markdown code fences.
The response MUST start with { and end with }.`;

// ───────────────────────────────────────────────────────────────────────────
// Types
// ───────────────────────────────────────────────────────────────────────────

interface AiReportRow {
    id: string;
    user_id: string;
    workout_id: string;
    quality_score: number;
    quality_band: string;
    status: string;
    is_lost_session: boolean;
}

interface WorkoutHistoryRow {
    id: string;
    user_id: string;
    name: string | null;
    date: string | null;
    duration: number | null;
    exercises: unknown;
    completion_rate: number | null;
    total_sets_planned: number | null;
    total_sets_completed: number | null;
    xp_earned: number | null;
    quality_score: number | null;
    quality_band: string | null;
    quality_reasons: unknown;
    workout_type: string | null;
}

interface PerformanceRow {
    id: string;
    exercise_id: string | null;
    exercise_name: string;
}

interface SetRow {
    performance_id: string;
    set_number: number;
    weight: number | null;
    reps: number | null;
    is_completed: boolean | null;
    set_type: string | null;
    rest_time_seconds: number | null;
    completed_at: string | null;
}

interface SwapEventRow {
    id: string;
    workout_id: string;
    swap_index: number;
    original_exercise_id: string | null;
    original_exercise_name: string;
    replacement_exercise_id: string | null;
    replacement_exercise_name: string;
    picked_rank: number | null;
    swap_source: string;
    completed_replacement: boolean | null;
    created_at: string;
}

interface UserProfileRow {
    id: string;
    fitness_goal: string | null;
    experience_level: string | null;
    weight_lbs: number | null;
    height: string | null;
    date_of_birth: string | null;
    equipment: string[] | null;
}

interface PreviousWorkoutRow {
    id: string;
    name: string | null;
    exercises: unknown;
    date: string | null;
}

interface CatalogRow {
    id: string;
    name: string;
    primary_muscles: string[] | null;
    secondary_muscles: string[] | null;
    equipment: string[] | null;
    equipment_category: string | null;
    exercise_family: string | null;
    complementary_families: string[] | null;
    is_compound: boolean | null;
    duration_based: boolean | null;
    workout_type: string | null;
    difficulty_level: string | null;
}

interface WorkoutContext {
    workout: WorkoutHistoryRow;
    performances: PerformanceRow[];
    sets: SetRow[];
    swapEvents: SwapEventRow[];
    profile: UserProfileRow | null;
    previousQualityWorkouts: PreviousWorkoutRow[];
    catalog: CatalogRow[];
    distinctNamesLastHour: number;
}

interface ClaudeReport {
    schema_version?: number;
    splitFamily?: string;
    primaryGoalInferred?: string;
    volumeBalance?: Record<string, number>;
    pressDistribution?: Record<string, number>;
    orderingScore?: number;
    pairingQuality?: number;
    pairingFindings?: Array<{
        type: "synergistic" | "antagonist_opportunity" | "mistake";
        exercises: string[];
        code?: string;
        note?: string;
    }>;
    pacingProfile?: Record<string, unknown>;
    progressionEvidence?: Array<Record<string, unknown>>;
    swapInsights?: Array<Record<string, unknown>>;
    redFlags?: Array<{ code: string; severity: string; evidence: string }>;
    exerciseCorrections?: Array<{
        exerciseName: string;
        field: string;
        operation?: string;        // 'add' | 'set' | 'remove' — defaulted below
        newValue: unknown;
        confidence: number;
        evidence: string;
    }>;
    programmedVsExecuted?: Record<string, unknown>;
    recommenderSignals?: Array<Record<string, unknown>>;
    summaryMd?: string;
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

        // ── Auth: service-role OR authenticated user ───────────────────
        const auth = await resolveAuth(req, supabase, supabaseServiceKey);
        if (!auth.ok) return json(auth.error, auth.status, corsHeaders);

        let body: { source?: string; workout_ids?: string[] } = {};
        try { body = await req.json(); } catch { /* empty body ok */ }
        const source = body.source ?? "cron";
        const explicitWorkoutIds = Array.isArray(body.workout_ids)
            ? body.workout_ids.filter((x): x is string => typeof x === "string")
            : null;

        // ── 1. Pick pending ai_workout_reports rows ────────────────────
        let q = supabase
            .from("ai_workout_reports")
            .select("id, user_id, workout_id, quality_score, quality_band, status, is_lost_session")
            .eq("status", "pending")
            .order("enqueued_at", { ascending: true })
            .limit(MAX_REPORTS_PER_RUN);

        if (explicitWorkoutIds && explicitWorkoutIds.length > 0) {
            q = q.in("workout_id", explicitWorkoutIds);
        }

        const { data: reportRowsRaw, error: selErr } = await q;
        if (selErr) {
            console.error("analyze-quality-workout: select error", selErr);
            return json({ error: selErr.message }, 500, corsHeaders);
        }
        let reportRows = (reportRowsRaw ?? []) as AiReportRow[];

        // For authenticated (non-service) callers, gate to the user's own rows.
        if (!auth.isServiceRole && auth.userId) {
            reportRows = reportRows.filter((r) => r.user_id === auth.userId);
        }

        if (reportRows.length === 0) {
            return json({
                message: "No pending quality-workout reports",
                source,
                analyzed: 0,
            }, 200, corsHeaders);
        }

        // ── 2. Mark 'analyzing' so concurrent runs skip these rows. ───
        await supabase
            .from("ai_workout_reports")
            .update({ status: "analyzing", error_message: null })
            .in("id", reportRows.map((r) => r.id));

        // ── 3. Per-workout pipeline ────────────────────────────────────
        // Sequential — Anthropic per-minute rate limits trip on parallel
        // batches of 5+. Each workout takes ~10-20s so 10 workouts ≈ 2-3 min,
        // comfortably inside the function's 5min hard ceiling.
        const results: Array<PromiseSettledResult<Awaited<ReturnType<typeof processWorkout>>>> = [];
        for (const row of reportRows) {
            try {
                const v = await processWorkout(supabase, anthropicKey, row, source);
                results.push({ status: "fulfilled", value: v });
            } catch (e) {
                console.error(`analyze-quality-workout: workout ${row.workout_id} threw`, e);
                results.push({
                    status: "fulfilled",
                    value: { reportId: row.id, status: "failed" as const, reason: String(e) },
                });
            }
        }

        const summary = {
            analyzed: 0,
            skipped: 0,
            failed: 0,
            corrections_applied: 0,
            pairing_signals_upserted: 0,
        };
        for (const r of results) {
            if (r.status !== "fulfilled") { summary.failed++; continue; }
            const v = r.value;
            if (!v) { summary.failed++; continue; }
            if (v.status === "complete") summary.analyzed++;
            else if (v.status === "skipped") summary.skipped++;
            else summary.failed++;
            summary.corrections_applied += v.correctionsApplied ?? 0;
            summary.pairing_signals_upserted += v.pairingSignalsUpserted ?? 0;
        }

        return json({
            message: "Workout intelligence run complete",
            source,
            candidates: reportRows.length,
            ...summary,
        }, 200, corsHeaders);

    } catch (error) {
        console.error("analyze-quality-workout error:", error);
        return json(
            { error: error instanceof Error ? error.message : String(error) },
            500,
            buildCorsHeaders(req),
        );
    }
});

// ───────────────────────────────────────────────────────────────────────────
// Auth resolution
// ───────────────────────────────────────────────────────────────────────────

type AuthDecision =
    | { ok: true; isServiceRole: true; userId: null }
    | { ok: true; isServiceRole: false; userId: string }
    | { ok: false; status: number; error: { error: string } };

async function resolveAuth(
    req: Request,
    // deno-lint-ignore no-explicit-any
    supabase: any,
    supabaseServiceKey: string,
): Promise<AuthDecision> {
    const cronKey = req.headers.get("x-cron-key");
    if (cronKey && isServiceRoleJWT(cronKey)) {
        return { ok: true, isServiceRole: true, userId: null };
    }

    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
        return { ok: false, status: 401, error: { error: "Missing authorization" } };
    }

    const token = authHeader.replace("Bearer ", "");
    if (token === supabaseServiceKey || isServiceRoleJWT(token)) {
        return { ok: true, isServiceRole: true, userId: null };
    }

    // User JWT path — the iOS fire-and-forget call.
    const { data: { user }, error } = await supabase.auth.getUser(token);
    if (error || !user) {
        return { ok: false, status: 401, error: { error: "Unauthorized" } };
    }
    return { ok: true, isServiceRole: false, userId: user.id };
}

// ───────────────────────────────────────────────────────────────────────────
// Per-workout pipeline
// ───────────────────────────────────────────────────────────────────────────

interface ProcessResult {
    reportId: string;
    status: "complete" | "skipped" | "failed";
    correctionsApplied?: number;
    pairingSignalsUpserted?: number;
    reason?: string;
}

async function processWorkout(
    // deno-lint-ignore no-explicit-any
    supabase: any,
    anthropicKey: string,
    row: AiReportRow,
    _source: string,
): Promise<ProcessResult> {
    // 1. Gather all context.
    let ctx: WorkoutContext;
    try {
        ctx = await gatherWorkoutContext(supabase, row);
    } catch (e) {
        const msg = e instanceof Error ? e.message : String(e);
        await markFailed(supabase, row.id, `gather_context: ${msg.slice(0, 200)}`);
        return { reportId: row.id, status: "failed", reason: msg };
    }

    // 2. Pre-flight suspicious-pattern check.
    const suspicious = detectSuspicious(ctx);
    if (suspicious) {
        await supabase
            .from("ai_workout_reports")
            .update({
                status: "skipped",
                summary_md: `Pre-flight detected suspicious pattern: ${suspicious}`,
                is_suspicious: true,
                analyzed_at: new Date().toISOString(),
            })
            .eq("id", row.id);
        return { reportId: row.id, status: "skipped", reason: suspicious };
    }

    // 3. Build the user prompt and call Claude.
    const userMessage = buildUserMessage(ctx);
    let claudeText: string;
    try {
        claudeText = await callClaude(anthropicKey, userMessage);
    } catch (e) {
        const msg = e instanceof Error ? e.message : String(e);
        await markFailed(supabase, row.id, `anthropic_${msg.slice(0, 200)}`);
        return { reportId: row.id, status: "failed", reason: msg };
    }

    // 4. Parse strict JSON.
    const parsed = parseClaudeJson(claudeText);
    if (!parsed) {
        console.error(
            `analyze-quality-workout: JSON parse failed for workout ${row.workout_id}`,
            claudeText.slice(0, 500),
        );
        await markFailed(supabase, row.id, "json_parse");
        return { reportId: row.id, status: "failed", reason: "json_parse" };
    }

    // 5. Write the report.
    const reportWriteOk = await writeReport(supabase, row.id, parsed);
    if (!reportWriteOk) {
        return { reportId: row.id, status: "failed", reason: "report_write" };
    }

    // 6. Apply 100%-confident exercise corrections.
    const correctionsApplied = await applyCorrections(supabase, row.id, parsed, ctx);

    // 7. Upsert pairing signals.
    const pairingSignalsUpserted = await upsertPairingSignals(supabase, parsed, ctx);

    // 8. Refresh per-user training profile (fire-and-forget).
    //    No-op for users with <4 completed reports (the RPC guards that).
    //    A failure here MUST NOT fail the report — profile is auxiliary.
    try {
        const { data, error } = await supabase.rpc("refresh_user_training_profile", {
            p_user_id: row.user_id,
        });
        if (error) {
            console.warn(
                `analyze-quality-workout: refresh_user_training_profile error for user ${row.user_id}:`,
                error,
            );
        } else if (data && (data as { refreshed?: boolean }).refreshed) {
            console.log(
                `analyze-quality-workout: profile refreshed for user ${row.user_id} ` +
                `(intent=${(data as { inferred_intent?: string }).inferred_intent})`,
            );
        }
    } catch (e) {
        console.warn("refresh_user_training_profile threw (non-fatal)", e);
    }

    return {
        reportId: row.id,
        status: "complete",
        correctionsApplied,
        pairingSignalsUpserted,
    };
}

// ───────────────────────────────────────────────────────────────────────────
// Context gathering
//   Multiple selects rather than a single mega-RPC. Keeps the function
//   debuggable from the dashboard and lets us evolve each query
//   independently. Each query is bounded.
// ───────────────────────────────────────────────────────────────────────────

async function gatherWorkoutContext(
    // deno-lint-ignore no-explicit-any
    supabase: any,
    row: AiReportRow,
): Promise<WorkoutContext> {
    // 1. Workout history row.
    const { data: workout, error: whErr } = await supabase
        .from("workout_history")
        .select(
            "id, user_id, name, date, duration, exercises, completion_rate, " +
            "total_sets_planned, total_sets_completed, xp_earned, " +
            "quality_score, quality_band, quality_reasons, workout_type",
        )
        .eq("id", row.workout_id)
        .maybeSingle();
    if (whErr) throw new Error(`workout_history: ${whErr.message}`);
    if (!workout) throw new Error("workout_history row missing");

    // 2. Performance rows (one per exercise in the workout).
    const { data: perfRowsRaw, error: perfErr } = await supabase
        .from("exercise_performance_history")
        .select("id, exercise_id, exercise_name")
        .eq("workout_id", row.workout_id);
    if (perfErr) throw new Error(`exercise_performance_history: ${perfErr.message}`);
    const performances = (perfRowsRaw ?? []) as PerformanceRow[];

    // 3. Set rows for those performances.
    let sets: SetRow[] = [];
    if (performances.length > 0) {
        const { data: setRowsRaw, error: setErr } = await supabase
            .from("exercise_set_history")
            .select(
                "performance_id, set_number, weight, reps, is_completed, " +
                "set_type, rest_time_seconds, completed_at",
            )
            .in("performance_id", performances.map((p) => p.id));
        if (setErr) throw new Error(`exercise_set_history: ${setErr.message}`);
        sets = (setRowsRaw ?? []) as SetRow[];
    }

    // 4. Swap events for this workout.
    const { data: swapRowsRaw, error: swapErr } = await supabase
        .from("workout_swap_events")
        .select(
            "id, workout_id, swap_index, original_exercise_id, original_exercise_name, " +
            "replacement_exercise_id, replacement_exercise_name, picked_rank, " +
            "swap_source, completed_replacement, created_at",
        )
        .eq("workout_id", row.workout_id);
    if (swapErr) throw new Error(`workout_swap_events: ${swapErr.message}`);
    const swapEvents = (swapRowsRaw ?? []) as SwapEventRow[];

    // 5. User profile (defensive — fall back to nulls).
    const { data: profileRowsRaw } = await supabase
        .from("user_profiles")
        .select("id, fitness_goal, experience_level, weight_lbs, height, date_of_birth, equipment")
        .eq("id", row.user_id)
        .maybeSingle();
    const profile = (profileRowsRaw ?? null) as UserProfileRow | null;

    // 6. Last 4 quality workouts (excluding this one).
    const { data: prevRowsRaw } = await supabase
        .from("workout_history")
        .select("id, name, exercises, date")
        .eq("user_id", row.user_id)
        .neq("id", row.workout_id)
        .eq("qualifies_for_corpus", true)
        .order("date", { ascending: false })
        .limit(4);
    const previousQualityWorkouts = (prevRowsRaw ?? []) as PreviousWorkoutRow[];

    // 7. Catalog metadata for every exercise that appears in this workout.
    //    Names from BOTH performances and swap events so we can resolve
    //    swapped-out exercises too.
    const allNames = new Set<string>();
    for (const p of performances) if (p.exercise_name) allNames.add(p.exercise_name);
    for (const s of swapEvents) {
        if (s.original_exercise_name) allNames.add(s.original_exercise_name);
        if (s.replacement_exercise_name) allNames.add(s.replacement_exercise_name);
    }
    let catalog: CatalogRow[] = [];
    if (allNames.size > 0) {
        const { data: catRowsRaw, error: catErr } = await supabase
            .from("exercises")
            .select(
                "id, name, primary_muscles, secondary_muscles, equipment, " +
                "equipment_category, exercise_family, complementary_families, " +
                "is_compound, duration_based, workout_type, difficulty_level",
            )
            .in("name", Array.from(allNames));
        if (catErr) {
            console.error("analyze-quality-workout: exercises lookup error", catErr);
        } else {
            catalog = (catRowsRaw ?? []) as CatalogRow[];
        }
    }

    // 8. Distinct workout names submitted in the last 60 minutes — used by
    //    the pre-flight check for impossibly-fast cycling through workouts.
    const sinceIso = new Date(Date.now() - 60 * 60 * 1000).toISOString();
    const { data: recentRowsRaw } = await supabase
        .from("workout_history")
        .select("name")
        .eq("user_id", row.user_id)
        .gte("date", sinceIso);
    const distinctNamesLastHour = new Set(
        ((recentRowsRaw ?? []) as { name: string | null }[])
            .map((r) => r.name)
            .filter((n): n is string => !!n),
    ).size;

    return {
        workout: workout as WorkoutHistoryRow,
        performances,
        sets,
        swapEvents,
        profile,
        previousQualityWorkouts,
        catalog,
        distinctNamesLastHour,
    };
}

// ───────────────────────────────────────────────────────────────────────────
// Pre-flight suspicious-pattern check
//   Returns a string reason if suspicious, otherwise null.
// ───────────────────────────────────────────────────────────────────────────

function detectSuspicious(ctx: WorkoutContext): string | null {
    const setsByPerf = new Map<string, SetRow[]>();
    for (const s of ctx.sets) {
        const arr = setsByPerf.get(s.performance_id);
        if (arr) arr.push(s);
        else setsByPerf.set(s.performance_id, [s]);
    }

    // (1) Joke value: weight = 1.0 lb on any working set.
    for (const s of ctx.sets) {
        if (s.is_completed && s.set_type !== "Warmup" && s.weight === 1.0) {
            return "joke_weight_1lb";
        }
    }

    // (2) Per-exercise reps differ by 10x set-to-set (e.g. 1, 100, 1, 100).
    for (const [, arr] of setsByPerf) {
        const sorted = [...arr].sort((a, b) => a.set_number - b.set_number);
        for (let i = 0; i < sorted.length - 1; i++) {
            const a = sorted[i].reps, b = sorted[i + 1].reps;
            if (a == null || b == null || a <= 0 || b <= 0) continue;
            const ratio = Math.max(a, b) / Math.min(a, b);
            if (ratio >= 10) return "rep_count_oscillation_10x";
        }
    }

    // (3) >50% of completed sets have reps = 0.
    const completedSets = ctx.sets.filter((s) => s.is_completed);
    if (completedSets.length > 0) {
        const zeroReps = completedSets.filter((s) => (s.reps ?? 0) === 0).length;
        if (zeroReps / completedSets.length > 0.5) {
            return "majority_zero_rep_completed_sets";
        }
    }

    // (4) Impossibly fast: duration < 600s AND total_sets_completed >= 20.
    const dur = ctx.workout.duration ?? 0;
    const setsDone = ctx.workout.total_sets_completed ?? 0;
    if (dur > 0 && dur < 600 && setsDone >= 20) {
        return "impossibly_fast_workout";
    }

    // (5) >5 distinct workout names submitted by this user in the last 60m.
    if (ctx.distinctNamesLastHour > 5) {
        return `user_cycling_workouts_too_fast (${ctx.distinctNamesLastHour})`;
    }

    return null;
}

// ───────────────────────────────────────────────────────────────────────────
// User prompt assembly
//   We hand Claude the entire context as one structured JSON block
//   inside a text part. No images for this function.
// ───────────────────────────────────────────────────────────────────────────

function buildUserMessage(ctx: WorkoutContext): string {
    const setsByPerf = new Map<string, SetRow[]>();
    for (const s of ctx.sets) {
        const arr = setsByPerf.get(s.performance_id);
        if (arr) arr.push(s);
        else setsByPerf.set(s.performance_id, [s]);
    }
    const exercisesExecuted = ctx.performances.map((p) => ({
        exercise_id: p.exercise_id,
        exercise_name: p.exercise_name,
        sets: (setsByPerf.get(p.id) ?? [])
            .sort((a, b) => a.set_number - b.set_number)
            .map((s) => ({
                set_number: s.set_number,
                weight: s.weight,
                reps: s.reps,
                is_completed: s.is_completed,
                set_type: s.set_type,
                rest_time_seconds: s.rest_time_seconds,
                completed_at: s.completed_at,
            })),
    }));

    const userBlock = ctx.profile
        ? {
            fitness_goal: ctx.profile.fitness_goal,
            experience_level: ctx.profile.experience_level,
            weight_lbs: ctx.profile.weight_lbs,
            height: ctx.profile.height,
            date_of_birth: ctx.profile.date_of_birth,
            equipment_count: Array.isArray(ctx.profile.equipment)
                ? ctx.profile.equipment.length : null,
        }
        : null;

    const payload = {
        workout: {
            id: ctx.workout.id,
            name: ctx.workout.name,
            date: ctx.workout.date,
            duration_seconds: ctx.workout.duration,
            workout_type: ctx.workout.workout_type,
            completion_rate: ctx.workout.completion_rate,
            total_sets_planned: ctx.workout.total_sets_planned,
            total_sets_completed: ctx.workout.total_sets_completed,
            xp_earned: ctx.workout.xp_earned,
            quality_score: ctx.workout.quality_score,
            quality_band: ctx.workout.quality_band,
            quality_reasons: ctx.workout.quality_reasons,
            programmed_exercises: ctx.workout.exercises,
        },
        exercises_executed: exercisesExecuted,
        swap_events: ctx.swapEvents.map((s) => ({
            swapEventId: s.id,
            swap_index: s.swap_index,
            original_exercise_name: s.original_exercise_name,
            replacement_exercise_name: s.replacement_exercise_name,
            picked_rank: s.picked_rank,
            swap_source: s.swap_source,
            completed_replacement: s.completed_replacement,
        })),
        user: userBlock,
        previous_quality_workouts: ctx.previousQualityWorkouts.map((w) => ({
            id: w.id,
            name: w.name,
            date: w.date,
            exercises: w.exercises,
        })),
        exercise_catalog: ctx.catalog.map((c) => ({
            name: c.name,
            primary_muscles: c.primary_muscles,
            secondary_muscles: c.secondary_muscles,
            equipment: c.equipment,
            equipment_category: c.equipment_category,
            exercise_family: c.exercise_family,
            complementary_families: c.complementary_families,
            is_compound: c.is_compound,
            duration_based: c.duration_based,
            workout_type: c.workout_type,
            difficulty_level: c.difficulty_level,
        })),
    };

    return [
        "Analyze this single quality workout and return ONLY the JSON described in the system prompt.",
        "Use exact catalog names when referring to exercises (so we can resolve them to IDs).",
        "Be conservative on exerciseCorrections — anything below 100% certainty MUST be omitted.",
        "",
        "INPUT:",
        JSON.stringify(payload),
    ].join("\n");
}

// ───────────────────────────────────────────────────────────────────────────
// Anthropic call
// ───────────────────────────────────────────────────────────────────────────

async function callClaude(
    anthropicKey: string,
    userMessage: string,
): Promise<string> {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort("per-workout timeout"), PER_WORKOUT_TIMEOUT_MS);

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
                system: SYSTEM_PROMPT,
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
            usage?: { input_tokens?: number; output_tokens?: number };
        };
        const block = completion.content?.find((b) => b.type === "text");
        const text = block?.text ?? "";
        const stopReason = completion.stop_reason ?? "unknown";
        console.log(
            `analyze-quality-workout: Claude OK stop_reason=${stopReason} ` +
            `input_tokens=${completion.usage?.input_tokens ?? "?"} ` +
            `output_tokens=${completion.usage?.output_tokens ?? "?"}`,
        );
        if (stopReason === "max_tokens") {
            console.warn(
                "analyze-quality-workout: hit max_tokens — JSON may be truncated. " +
                "parseClaudeJson will salvage if possible.",
            );
        }
        return text;
    } finally {
        clearTimeout(timer);
    }
}

// ───────────────────────────────────────────────────────────────────────────
// JSON parsing
//   Mirrors parseClaudeJson from triage-shake-reports — try strict parse,
//   fall back to first balanced {...} block.
// ───────────────────────────────────────────────────────────────────────────

function parseClaudeJson(text: string): ClaudeReport | null {
    if (!text) return null;

    // Fast path — Claude obeyed and returned only JSON.
    try {
        return JSON.parse(text) as ClaudeReport;
    } catch {
        // fall through
    }

    // Salvage path — extract the first balanced {...} block.
    const firstBrace = text.indexOf("{");
    if (firstBrace < 0) return null;

    let depth = 0;
    let inString = false;
    let escape = false;
    let end = -1;
    for (let i = firstBrace; i < text.length; i++) {
        const ch = text[i];
        if (escape) { escape = false; continue; }
        if (ch === "\\") { escape = true; continue; }
        if (ch === '"') { inString = !inString; continue; }
        if (inString) continue;
        if (ch === "{") depth++;
        else if (ch === "}") {
            depth--;
            if (depth === 0) { end = i; break; }
        }
    }
    if (end < 0) return null;

    try {
        return JSON.parse(text.slice(firstBrace, end + 1)) as ClaudeReport;
    } catch {
        return null;
    }
}

// ───────────────────────────────────────────────────────────────────────────
// Report write-back
// ───────────────────────────────────────────────────────────────────────────

async function writeReport(
    // deno-lint-ignore no-explicit-any
    supabase: any,
    reportId: string,
    parsed: ClaudeReport,
): Promise<boolean> {
    const summary = typeof parsed.summaryMd === "string"
        ? parsed.summaryMd.slice(0, 4000)
        : null;

    const { error } = await supabase
        .from("ai_workout_reports")
        .update({
            status: "complete",
            report_jsonb: parsed,
            summary_md: summary,
            model_used: MODEL,
            error_message: null,
            analyzed_at: new Date().toISOString(),
        })
        .eq("id", reportId);

    if (error) {
        console.error(
            `analyze-quality-workout: report write failed for ${reportId}`,
            error,
        );
        return false;
    }
    return true;
}

async function markFailed(
    // deno-lint-ignore no-explicit-any
    supabase: any,
    reportId: string,
    errorMessage: string,
): Promise<void> {
    await supabase
        .from("ai_workout_reports")
        .update({
            status: "failed",
            error_message: errorMessage.slice(0, 500),
            analyzed_at: new Date().toISOString(),
        })
        .eq("id", reportId);
}

// ───────────────────────────────────────────────────────────────────────────
// Exercise corrections — apply via SECURITY DEFINER RPC.
//   The RPC enforces confidence === 1.0 and the field whitelist; we
//   gate on the same in-process so we never hit the RPC for invalid
//   shapes (saves a round-trip + clearer logs).
// ───────────────────────────────────────────────────────────────────────────

async function applyCorrections(
    // deno-lint-ignore no-explicit-any
    supabase: any,
    reportId: string,
    parsed: ClaudeReport,
    ctx: WorkoutContext,
): Promise<number> {
    const corrections = Array.isArray(parsed.exerciseCorrections)
        ? parsed.exerciseCorrections : [];
    if (corrections.length === 0) return 0;

    const catalogByName = new Map(ctx.catalog.map((c) => [c.name, c]));

    // Migration #157: every Claude proposal goes through propose_exercise_correction.
    // The SQL function inserts a proposal row and auto-applies only if a
    // deterministic corroboration gate passes (sister/name/multi_report).
    // We propose ALL valid-shape corrections regardless of confidence —
    // the queue is the source of truth.
    let proposed = 0;
    let autoApplied = 0;

    for (const c of corrections) {
        if (!CORRECTION_FIELD_WHITELIST.has(c.field)) {
            console.warn(
                `analyze-quality-workout: dropping non-whitelisted correction ` +
                `${c.field} for ${c.exerciseName}`,
            );
            continue;
        }
        if (typeof c.confidence !== "number" || c.confidence <= 0 || c.confidence > 1) {
            console.warn(
                `analyze-quality-workout: dropping invalid-confidence correction ` +
                `(${c.confidence}) ${c.field} for ${c.exerciseName}`,
            );
            continue;
        }

        // Default operation per field type when Claude omits it.
        const isMuscleField = c.field === "primary_muscles" || c.field === "secondary_muscles";
        const operationRaw = (c.operation ?? "").toString().toLowerCase();
        const operation = operationRaw || (isMuscleField ? "add" : "set");
        if (!["add", "set", "remove"].includes(operation)) {
            console.warn(
                `analyze-quality-workout: invalid operation '${operationRaw}' on ${c.field}`,
            );
            continue;
        }
        // Operation/field compatibility (matches SQL CHECK).
        if (isMuscleField && operation === "set") {
            console.warn(
                `analyze-quality-workout: operation=set rejected for muscle array (${c.exerciseName})`,
            );
            continue;
        }
        if (!isMuscleField && operation !== "set") {
            console.warn(
                `analyze-quality-workout: operation=${operation} rejected for scalar field ${c.field}`,
            );
            continue;
        }

        if (c.field === "workout_type" && !VALID_WORKOUT_TYPE.has(String(c.newValue))) {
            console.warn(
                `analyze-quality-workout: dropping invalid workout_type ` +
                `'${c.newValue}' for ${c.exerciseName}`,
            );
            continue;
        }

        // Resolve exercise by name. If it's not in the per-workout catalog
        // we pulled, look it up in the wider catalog.
        let exerciseId = catalogByName.get(c.exerciseName)?.id ?? null;
        if (!exerciseId) {
            const { data: lookupRowsRaw } = await supabase
                .from("exercises")
                .select("id")
                .eq("name", c.exerciseName)
                .maybeSingle();
            exerciseId = (lookupRowsRaw as { id?: string } | null)?.id ?? null;
        }
        if (!exerciseId) {
            console.warn(
                `analyze-quality-workout: exercise '${c.exerciseName}' not found for correction; skipping`,
            );
            continue;
        }

        const newValue = normalizeCorrectionValue(c.field, c.newValue);
        if (newValue === undefined) {
            console.warn(
                `analyze-quality-workout: dropping unparseable newValue for ` +
                `${c.field} on ${c.exerciseName}`,
            );
            continue;
        }

        const { data: rpcResult, error: rpcErr } = await supabase.rpc(
            "propose_exercise_correction",
            {
                p_exercise_id: exerciseId,
                p_field_name: c.field,
                p_operation: operation,
                p_new_value: newValue,
                p_confidence: c.confidence,
                p_evidence: String(c.evidence ?? "").slice(0, 1000),
                p_source_report_id: reportId,
            },
        );
        if (rpcErr) {
            // Per spec — log per-correction failures but never fail the
            // whole report on a single bad correction.
            console.error(
                `analyze-quality-workout: propose_exercise_correction failed ` +
                `for ${c.field}/${operation} on ${c.exerciseName}:`,
                rpcErr,
            );
            continue;
        }
        proposed++;
        const result = rpcResult as { auto_applied?: boolean; reason?: string } | null;
        if (result?.auto_applied) {
            autoApplied++;
        } else {
            console.log(
                `analyze-quality-workout: proposal queued (${result?.reason ?? "unknown"}) ` +
                `${c.field}/${operation} on ${c.exerciseName}`,
            );
        }
    }

    console.log(`analyze-quality-workout: proposed=${proposed} auto_applied=${autoApplied}`);
    // Returns auto-applied count (matches the existing summary JSON contract).
    return autoApplied;
}

function normalizeCorrectionValue(field: string, raw: unknown): unknown {
    switch (field) {
        case "primary_muscles":
        case "secondary_muscles": {
            if (!Array.isArray(raw)) return undefined;
            const arr = raw.map((x) => String(x)).filter((x) => x.length > 0);
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
        case "workout_type":
        case "equipment_category": {
            if (typeof raw !== "string") return undefined;
            const trimmed = raw.trim();
            return trimmed.length > 0 ? trimmed : undefined;
        }
        default:
            return undefined;
    }
}

// ───────────────────────────────────────────────────────────────────────────
// Pairing signals — upsert into pairing_signals with normalized order.
//   We map { type: 'synergistic' } -> signal_type='synergistic'
//          { type: 'mistake'      } -> signal_type='negative'
//   antagonist_opportunity is INFORMATIONAL only — not promoted to a row.
// ───────────────────────────────────────────────────────────────────────────

async function upsertPairingSignals(
    // deno-lint-ignore no-explicit-any
    supabase: any,
    parsed: ClaudeReport,
    ctx: WorkoutContext,
): Promise<number> {
    const findings = Array.isArray(parsed.pairingFindings) ? parsed.pairingFindings : [];
    if (findings.length === 0) return 0;

    const catalogByName = new Map(ctx.catalog.map((c) => [c.name, c]));
    const pairingQuality = typeof parsed.pairingQuality === "number"
        ? parsed.pairingQuality
        : null;

    let upserted = 0;

    for (const f of findings) {
        const signalType = f.type === "synergistic"
            ? "synergistic"
            : f.type === "mistake"
                ? "negative"
                : null;
        if (!signalType) continue;
        if (!Array.isArray(f.exercises) || f.exercises.length !== 2) continue;

        const a = catalogByName.get(f.exercises[0]);
        const b = catalogByName.get(f.exercises[1]);
        if (!a || !b || a.id === b.id) continue;

        // Normalize order: lex-smallest UUID first so (A,B)=(B,A).
        const [first, second] = a.id < b.id ? [a, b] : [b, a];

        const code = typeof f.code === "string" && f.code.length > 0 ? f.code : null;

        // Read existing row for the pair to compute the new running average
        // + reason_codes union.
        const { data: existing } = await supabase
            .from("pairing_signals")
            .select("co_occurrence_count, avg_pairing_quality, reason_codes")
            .eq("exercise_a_id", first.id)
            .eq("exercise_b_id", second.id)
            .eq("signal_type", signalType)
            .maybeSingle();

        let newCount = 1;
        let newAvg: number | null = pairingQuality;
        let newReasonCodes: string[] = code ? [code] : [];

        if (existing) {
            const prevCount = (existing as { co_occurrence_count?: number }).co_occurrence_count ?? 0;
            const prevAvg = (existing as { avg_pairing_quality?: number | null }).avg_pairing_quality ?? null;
            const prevCodes = ((existing as { reason_codes?: string[] }).reason_codes) ?? [];
            newCount = prevCount + 1;
            if (pairingQuality != null && prevAvg != null) {
                newAvg = (prevAvg * prevCount + pairingQuality) / newCount;
            } else if (pairingQuality != null) {
                newAvg = pairingQuality;
            } else {
                newAvg = prevAvg;
            }
            const codeSet = new Set<string>(prevCodes);
            if (code) codeSet.add(code);
            newReasonCodes = Array.from(codeSet);
        }

        const { error: upsertErr } = await supabase
            .from("pairing_signals")
            .upsert({
                exercise_a_id: first.id,
                exercise_a_name: first.name,
                exercise_b_id: second.id,
                exercise_b_name: second.name,
                signal_type: signalType,
                co_occurrence_count: newCount,
                avg_pairing_quality: newAvg,
                reason_codes: newReasonCodes,
                last_seen_at: new Date().toISOString(),
            }, { onConflict: "exercise_a_id,exercise_b_id,signal_type" });

        if (upsertErr) {
            console.error(
                `analyze-quality-workout: pairing_signals upsert failed ` +
                `for ${first.name}+${second.name}:`,
                upsertErr,
            );
            continue;
        }
        upserted++;
    }

    return upserted;
}

// ───────────────────────────────────────────────────────────────────────────
// JSON helper
// ───────────────────────────────────────────────────────────────────────────

function json(body: unknown, status: number, corsHeaders: Record<string, string>): Response {
    return new Response(JSON.stringify(body), {
        status,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
}
