"""
Specialty / Variant Exercise Filter — Canonical Patterns
=========================================================

The user-visible bug: an unmodified beginner sees "Feet On Bench Bench Press"
or "Pause Squat" recommended before the regular Bench Press / Squat. Those are
SPECIALTY VARIANTS — exercises that use a base movement plus a modifier
(tempo / pause / deficit / feet up / paused / 21s / etc.). They are valid for
intermediate/advanced lifters who already own the base movement, but they
must NEVER be auto-recommended to a beginner ahead of the canonical version.

This file is the SINGLE SOURCE OF TRUTH for "what counts as a specialty
variant?". Both:

  - the Python audit simulator (`autogen_audit_simulator.py`)
  - the Swift on-device autogen (`SmartExerciseSelectionEngine.swift`)

read these patterns. When you add a pattern here, also add the equivalent
keyword/phrase to `assessExercisePracticality()` in
`Fit33/SmartExerciseSelectionEngine.swift` (look for the
"SPECIALTY VARIANT FILTER" section).

USAGE
-----
    from specialty_exercise_filter import (
        is_specialty_variant,
        specialty_severity,
        SpecialtyMatch,
    )

    match = is_specialty_variant("Feet On Bench Barbell Bench Press")
    # SpecialtyMatch(matched=True, pattern='feet on bench',
    #                base_movement='bench_press', severity='block_beginner')

CONVENTIONS
-----------
- All patterns are lowercased substrings — we test
  `pattern in exercise_name.lower()`.
- `severity` decides what the autogen does when it sees the match:
    - `block_beginner`   → never show to a beginner; allow intermediate/advanced
    - `block_intermediate` → block beginner AND intermediate; allow advanced only
    - `block_all`        → never auto-recommend regardless of level (still
                            available via search/manual add)
- `base_movement` is the canonical movement family the variant modifies.
  We use it to verify the canonical version IS available before promoting
  the specialty variant — never feature a specialty when the base is
  missing from the user's catalog.

EXTENSION CHECKLIST (when adding a new pattern)
-----------------------------------------------
1. Add the lowercased substring to `SPECIALTY_PATTERNS` below with the
   right base_movement + severity.
2. Mirror the keyword to `Fit33/SmartExerciseSelectionEngine.swift`
   `assessExercisePracticality()` — search "SPECIALTY VARIANT FILTER"
   for the corresponding switch.
3. Add a sample name to the `SAMPLE_NAMES` test fixture at the bottom
   so a regression run flags drift.
4. If the new pattern ENABLES a previously-blocked exercise for a
   given level, also update `FITNESS_EXPERT_AGENT.md` invariant 2x
   ("Specialty variants only after the base movement is established").

Authority: Fitness Expert + Product Engineer agents. See
`FITNESS_EXPERT_AGENT.md` invariant on specialty variants.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Optional, List, Set


# ─────────────────────────────────────────────────────────────────────────────
# Severity tiers — what the autogen does when a match is found
# ─────────────────────────────────────────────────────────────────────────────

SEVERITY_BLOCK_BEGINNER = "block_beginner"
SEVERITY_BLOCK_INTERMEDIATE = "block_intermediate"
SEVERITY_BLOCK_UNTIL_ESTABLISHED = "block_until_established"
SEVERITY_BLOCK_ALL = "block_all"

# When None or unmatched, the exercise is treated as a regular movement —
# autogen scoring proceeds normally.

# block_until_established — progression-aware tier (audit 2026-05-08)
# ---------------------------------------------------------------------
# Some specialty modifiers (close grip, wide grip, hammer grip, pendlay,
# clean grip, single-leg press, etc.) are appropriate AFTER the lifter has
# established the canonical movement — but should NOT appear in their first
# few workouts at any level. The audit users have no history, so all of
# them are blocked. In the live app, the SwiftUI caller passes the user's
# completed workout count and the filter unlocks at the level-specific
# threshold.
#
# Thresholds (calendar weeks @ 3 workouts / week):
#   Beginner     → 12 workouts (~4 weeks)
#   Intermediate →  8 workouts (~3 weeks)
#   Advanced     →  4 workouts (~1.5 weeks)
#
# After the threshold, the variant is allowed (autogen-scoring proceeds
# normally). Before the threshold, it is blocked at any level — because
# even an Advanced lifter joining the app should see the canonical bench
# press / row / squat first before grip variants slip in.

WORKOUT_COUNT_THRESHOLDS = {
    # Audit 2026-05-08 (Round 6): bumped 3× across the board.
    # Round 6 showed Advanced synthetic users at workouts_completed=5+
    # already unlocked grip / unilateral specialties on their FIRST
    # autogen workout (Pin Press, Rack Pull, Wide Grip, Pistol, etc.).
    # User feedback: "advanced types come later when progression feels
    # correct, not premature." MUST stay in lock-step with
    # `Fit33/SmartExerciseSelectionEngine.swift` `workoutCountThresholds`.
    "beginner":     25,    # ~8 weeks @ 3x/week (was 12)
    "intermediate": 18,    # ~6 weeks (was 8)
    "advanced":     12,    # ~4 weeks (was 4 — too easy to bypass in audit)
}


# ─────────────────────────────────────────────────────────────────────────────
# Pattern registry
# ─────────────────────────────────────────────────────────────────────────────
#
# Patterns are evaluated in order — first match wins, so longer / more
# specific patterns should appear before shorter ones. We test
# `pattern in exercise_name.lower()` (substring match), so word-boundaries
# are encoded by adding leading/trailing spaces where needed (e.g. ' 21s ').
#
# The list is grouped by base movement family for readability. Patterns
# within a family must be alphabetized by specificity.

@dataclass(frozen=True)
class SpecialtyPattern:
    pattern: str                # lowercased substring
    base_movement: str          # canonical movement family
    severity: str               # one of SEVERITY_BLOCK_*
    rationale: str              # WHY this is specialty (for audit transparency)


# ─── Bench Press family ──────────────────────────────────────────────────────
# Foot-position and tempo variants of the bench press. ALL of these require
# the lifter to own the regular flat bench press first.

BENCH_PRESS_VARIANTS: List[SpecialtyPattern] = [
    SpecialtyPattern("feet on bench", "bench_press", SEVERITY_BLOCK_BEGINNER,
        "Feet-elevated bench is a specialty stability variant — should never be the first bench press shown to a beginner"),
    SpecialtyPattern("feet up", "bench_press", SEVERITY_BLOCK_BEGINNER,
        "Feet-up bench removes leg drive — specialty variant"),
    SpecialtyPattern("feet elevated", "bench_press", SEVERITY_BLOCK_BEGINNER,
        "Feet-elevated bench — specialty stability variant"),
    SpecialtyPattern("legs raised", "bench_press", SEVERITY_BLOCK_BEGINNER,
        "Legs-raised bench — specialty stability variant"),
    SpecialtyPattern("spoto press", "bench_press", SEVERITY_BLOCK_INTERMEDIATE,
        "Spoto press = pause 1-2\" off chest — competition powerlifting specialty"),
    SpecialtyPattern("pin press", "bench_press", SEVERITY_BLOCK_UNTIL_ESTABLISHED,
        "Pin press = bottom-position deadstop — specialty / programming context; show regular bench first regardless of level (audit Round 4: Intermediate user got 'Pin Bench Press Conventional Grip')"),
    SpecialtyPattern("pin bench press", "bench_press", SEVERITY_BLOCK_UNTIL_ESTABLISHED,
        "Pin bench press is a specialty deadstop variant — show regular bench first regardless of level"),
    SpecialtyPattern("squeeze press", "bench_press", SEVERITY_BLOCK_UNTIL_ESTABLISHED,
        "Squeeze press = chest-squeeze isometric DB press — specialty technique requiring mind-muscle mastery; show regular DB bench first (audit Round 4: 3 instances flagged)"),
    SpecialtyPattern("squeeze bench", "bench_press", SEVERITY_BLOCK_UNTIL_ESTABLISHED,
        "Squeeze bench press — specialty technique variant"),
    SpecialtyPattern("dead stop bench", "bench_press", SEVERITY_BLOCK_INTERMEDIATE,
        "Dead-stop bench — specialty pause variant"),
    SpecialtyPattern("paused bench", "bench_press", SEVERITY_BLOCK_BEGINNER,
        "Paused bench is a powerlifting specialty"),
    SpecialtyPattern("long pause", "bench_press", SEVERITY_BLOCK_INTERMEDIATE,
        "Long-pause bench — specialty"),
    SpecialtyPattern("board press", "bench_press", SEVERITY_BLOCK_INTERMEDIATE,
        "Board press = partial range, requires equipment — specialty"),
    SpecialtyPattern("slingshot", "bench_press", SEVERITY_BLOCK_INTERMEDIATE,
        "Slingshot bench requires the slingshot tool — specialty"),
    SpecialtyPattern("guillotine", "bench_press", SEVERITY_BLOCK_ALL,
        "Guillotine press = bar to neck — high shoulder injury risk, never auto-recommend"),
    SpecialtyPattern("jm press", "bench_press", SEVERITY_BLOCK_INTERMEDIATE,
        "JM press is a specialty triceps-bench hybrid"),
    # ── Grip-progression variants (BLOCK_UNTIL_ESTABLISHED) ──
    # These are valid bench movements but should never be the FIRST bench
    # press an autogen system recommends, regardless of level. Once the user
    # has completed N workouts (level-based), the filter releases. Audit users
    # always count=0 → blocked; live-app users earn them with progression.
    SpecialtyPattern("close grip incline", "bench_press", SEVERITY_BLOCK_UNTIL_ESTABLISHED,
        "Close-grip incline — grip-progression variant; show regular incline first"),
    SpecialtyPattern("reverse grip", "bench_press", SEVERITY_BLOCK_UNTIL_ESTABLISHED,
        "Reverse-grip bench requires wrist mobility — grip-progression variant"),
    SpecialtyPattern("wide grip bench", "bench_press", SEVERITY_BLOCK_UNTIL_ESTABLISHED,
        "Wide-grip bench — grip-progression variant; show regular grip first"),
    SpecialtyPattern("wide bench press", "bench_press", SEVERITY_BLOCK_UNTIL_ESTABLISHED,
        "Wide bench press (no 'grip' in name) — grip-progression variant; show regular bench press first"),
    SpecialtyPattern("close grip bench press", "bench_press", SEVERITY_BLOCK_UNTIL_ESTABLISHED,
        "Close-grip bench shifts emphasis to triceps — grip-progression variant; show regular bench first"),
    SpecialtyPattern("bench press - close grip", "bench_press", SEVERITY_BLOCK_UNTIL_ESTABLISHED,
        "Close-grip bench (DB/SM/BB variant) — grip-progression variant; show regular bench first"),
    SpecialtyPattern("decline bench press - wide grip", "bench_press", SEVERITY_BLOCK_UNTIL_ESTABLISHED,
        "Wide-grip decline — multi-modifier specialty; show regular decline + wide-grip flat bench first"),
    SpecialtyPattern("3 point bench", "bench_press", SEVERITY_BLOCK_UNTIL_ESTABLISHED,
        "3-Point bench is an unstable specialty variant — show regular bench press first"),
    SpecialtyPattern("reverse close grip", "bench_press", SEVERITY_BLOCK_UNTIL_ESTABLISHED,
        "Reverse close-grip bench is a multi-modifier specialty — show regular bench first"),
]

# ─── Squat family ────────────────────────────────────────────────────────────
# Tempo / depth / pause variants of the squat. Same rule: own the squat first.

SQUAT_VARIANTS: List[SpecialtyPattern] = [
    SpecialtyPattern("deficit squat", "squat", SEVERITY_BLOCK_BEGINNER,
        "Deficit squat = standing on a plate — specialty range-extension variant"),
    SpecialtyPattern("paused squat", "squat", SEVERITY_BLOCK_BEGINNER,
        "Paused squat = bottom-position pause — specialty"),
    SpecialtyPattern("pause squat", "squat", SEVERITY_BLOCK_BEGINNER,
        "Pause squat — specialty"),
    SpecialtyPattern("anderson squat", "squat", SEVERITY_BLOCK_INTERMEDIATE,
        "Anderson squat = bottom-up from pins — specialty"),
    SpecialtyPattern("1 1/4 squat", "squat", SEVERITY_BLOCK_BEGINNER,
        "1 1/4 rep squat — specialty tempo variant"),
    SpecialtyPattern("1.5 squat", "squat", SEVERITY_BLOCK_BEGINNER,
        "1.5-rep squat — specialty"),
    SpecialtyPattern("tempo squat", "squat", SEVERITY_BLOCK_BEGINNER,
        "Tempo-prescribed squat — specialty"),
    SpecialtyPattern("pin squat", "squat", SEVERITY_BLOCK_INTERMEDIATE,
        "Pin squat — specialty"),
    SpecialtyPattern("box squat", "squat", SEVERITY_BLOCK_BEGINNER,
        "Box squat is a specialty depth-controlled variant — show regular squat first"),
    SpecialtyPattern("zercher", "squat", SEVERITY_BLOCK_INTERMEDIATE,
        "Zercher squat — specialty / advanced"),
    SpecialtyPattern("jefferson", "squat", SEVERITY_BLOCK_INTERMEDIATE,
        "Jefferson squat / deadlift — specialty / unusual"),
    SpecialtyPattern("sissy squat", "squat", SEVERITY_BLOCK_BEGINNER,
        "Sissy squat = knee-extension under load — specialty / knee stress"),
    SpecialtyPattern("heels elevated", "squat", SEVERITY_BLOCK_BEGINNER,
        "Heels-elevated squat — specialty quad emphasis variant"),
    SpecialtyPattern("deep squat turn", "squat", SEVERITY_BLOCK_ALL,
        "Deep squat with rotation = mobility-flow hybrid; never a strength autogen pick at any level (audit 2026-05-08: Advanced user got this in Build-Muscle workout, rejected)"),
    SpecialtyPattern("lunge with internal rotation", "squat", SEVERITY_BLOCK_ALL,
        "Lunge + internal hip rotation = mobility-flow specialty; never appropriate for autogen strength workouts at any level"),
    # ── Olympic / grip / stability progression variants (BLOCK_UNTIL_ESTABLISHED) ──
    SpecialtyPattern("clean grip", "squat", SEVERITY_BLOCK_UNTIL_ESTABLISHED,
        "Clean-grip front squat is an Olympic-lifting technique variant — grip progression; show regular front squat first"),
    # 2026-05-08 audit Round 4 addition — Olympic-derivative WITHOUT the word "Grip"
    # (catalog name is "Front Squat - Clean (Barbell)" which the `clean grip` pattern misses).
    SpecialtyPattern("squat - clean", "squat", SEVERITY_BLOCK_UNTIL_ESTABLISHED,
        "Olympic-derivative '<Squat> - Clean' is a technique variant requiring Olympic coaching; show regular squat first regardless of level"),
    SpecialtyPattern("front squat clean", "squat", SEVERITY_BLOCK_UNTIL_ESTABLISHED,
        "Front-squat-clean (no separator) — Olympic-derivative technique variant"),
    SpecialtyPattern("elevated goblet", "squat", SEVERITY_BLOCK_UNTIL_ESTABLISHED,
        "Elevated goblet squat is a stability/depth specialty — show regular goblet squat first"),
    SpecialtyPattern("front foot elevated", "squat", SEVERITY_BLOCK_UNTIL_ESTABLISHED,
        "Front-foot-elevated split squat is a deficit specialty — show regular split squat first"),
    SpecialtyPattern("single leg press", "squat", SEVERITY_BLOCK_UNTIL_ESTABLISHED,
        "Single-leg press is a unilateral stability specialty — show bilateral leg press first"),
    SpecialtyPattern("split squat front foot elevated", "squat", SEVERITY_BLOCK_UNTIL_ESTABLISHED,
        "Front-foot-elevated split squat is a stability/deficit specialty — show regular split squat first"),
    # ── Round 6 audit additions: unilateral squat / lunge specialties ──
    SpecialtyPattern("pistol squat", "squat", SEVERITY_BLOCK_UNTIL_ESTABLISHED,
        "Pistol squat = full single-leg-only squat — advanced unilateral specialty (audit Round 6: appeared as exercise #1 for multiple users)"),
    SpecialtyPattern("single leg squat", "squat", SEVERITY_BLOCK_UNTIL_ESTABLISHED,
        "Single-leg squat / pistol is an advanced unilateral specialty — show bilateral squat first regardless of level"),
    SpecialtyPattern("bulgarian split squat", "squat", SEVERITY_BLOCK_UNTIL_ESTABLISHED,
        "Bulgarian split squat = rear-foot-elevated single-leg specialty — show standard split squat / lunge first regardless of level"),
    SpecialtyPattern("supported squat", "squat", SEVERITY_BLOCK_BEGINNER,
        "Supported squat (with band/TRX/wall) is a regression/rehab variant — not a strength autogen pick"),
    SpecialtyPattern("front rack lunge", "lunge", SEVERITY_BLOCK_UNTIL_ESTABLISHED,
        "Front-rack lunge requires Olympic-level wrist mobility — advanced loading specialty; show standard lunge first regardless of level"),
    SpecialtyPattern("front rack squat", "squat", SEVERITY_BLOCK_UNTIL_ESTABLISHED,
        "Front-rack squat hold position requires Olympic-level wrist mobility — advanced loading specialty"),
    SpecialtyPattern("split stance rdl", "deadlift", SEVERITY_BLOCK_UNTIL_ESTABLISHED,
        "Split-stance RDL = single-leg-biased Romanian deadlift — unilateral specialty"),
    SpecialtyPattern("from deficit", "lunge", SEVERITY_BLOCK_BEGINNER,
        "Lunge / step-up from a deficit (standing on a plate) is a range-extension specialty — not for beginners"),
    SpecialtyPattern("half kneeling", "core_stability", SEVERITY_BLOCK_BEGINNER,
        "Half-kneeling stance is a core-stability progression — show bilateral standing variants first for beginners (audit Round 6: 'Half Kneeling Side Lunge' served to a 41yo Beginner)"),
    # ── Catalog-corrupted combo movements (BLOCK_ALL — never autogen) ──
    SpecialtyPattern("reverse lunge forward lunge", "lunge", SEVERITY_BLOCK_ALL,
        "Reverse-lunge-forward-lunge is a catalog-corrupted combo movement — never autogen at any level"),
    SpecialtyPattern("swing clean grip", "squat", SEVERITY_BLOCK_ALL,
        "Swing-clean-grip kettlebell flow combines swing + Olympic grip + squat — catalog corruption; never autogen"),
    SpecialtyPattern("swing to goblet", "squat", SEVERITY_BLOCK_ALL,
        "Swing-to-goblet kettlebell flow combines two distinct movements — catalog corruption; never autogen"),
    SpecialtyPattern("swing to ", "squat", SEVERITY_BLOCK_ALL,
        "Kettlebell 'swing to X' combo movements blur swing + landed exercise — catalog corruption; never autogen"),
]

# ─── Deadlift family ─────────────────────────────────────────────────────────

DEADLIFT_VARIANTS: List[SpecialtyPattern] = [
    SpecialtyPattern("deficit deadlift", "deadlift", SEVERITY_BLOCK_INTERMEDIATE,
        "Deficit deadlift — specialty range-extension"),
    SpecialtyPattern("snatch grip deadlift", "deadlift", SEVERITY_BLOCK_INTERMEDIATE,
        "Snatch-grip deadlift — specialty grip variant"),
    SpecialtyPattern("block pull", "deadlift", SEVERITY_BLOCK_INTERMEDIATE,
        "Block pulls = elevated deadlift from blocks — specialty"),
    SpecialtyPattern("paused deadlift", "deadlift", SEVERITY_BLOCK_INTERMEDIATE,
        "Paused deadlift — specialty"),
    SpecialtyPattern("tempo deadlift", "deadlift", SEVERITY_BLOCK_INTERMEDIATE,
        "Tempo deadlift — specialty"),
    SpecialtyPattern("reset deadlift", "deadlift", SEVERITY_BLOCK_INTERMEDIATE,
        "Reset every rep — specialty"),
    SpecialtyPattern("touch and go", "deadlift", SEVERITY_BLOCK_INTERMEDIATE,
        "Touch-and-go deadlift — specialty cadence"),
    SpecialtyPattern("stiff leg", "deadlift", SEVERITY_BLOCK_BEGINNER,
        "Stiff-leg deadlift — high low-back stress, specialty for beginners"),
    SpecialtyPattern("trap bar", "deadlift", SEVERITY_BLOCK_BEGINNER,
        "Trap-bar deadlift is great but show regular deadlift FIRST when introducing the pattern"),
    SpecialtyPattern("rack pull", "deadlift", SEVERITY_BLOCK_UNTIL_ESTABLISHED,
        "Rack pull = elevated partial deadlift — specialty range / accessory; show full deadlift first regardless of level (audit Round 4: Intermediate user got 'Rack Pull (Smith Machine)')"),
]

# ─── Row family ──────────────────────────────────────────────────────────────

ROW_VARIANTS: List[SpecialtyPattern] = [
    # ── Technique-progression row variants (BLOCK_UNTIL_ESTABLISHED) ──
    SpecialtyPattern("yates row", "row", SEVERITY_BLOCK_UNTIL_ESTABLISHED,
        "Yates row = supinated bent row — technique-progression variant"),
    SpecialtyPattern("pendlay row", "row", SEVERITY_BLOCK_UNTIL_ESTABLISHED,
        "Pendlay row = strict dead-stop row — technique-progression variant; show standard bent row first"),
    SpecialtyPattern("meadows row", "row", SEVERITY_BLOCK_UNTIL_ESTABLISHED,
        "Meadows row = unilateral landmine variant — technique-progression variant"),
    SpecialtyPattern("kroc row", "row", SEVERITY_BLOCK_UNTIL_ESTABLISHED,
        "Kroc row = ultra-high-rep heavy DB row — technique-progression variant"),
    # ── Tempo / pause prescription variants (BLOCK_BEGINNER — keeps standard cadence default) ──
    SpecialtyPattern("paused row", "row", SEVERITY_BLOCK_BEGINNER,
        "Paused row — specialty tempo"),
    SpecialtyPattern("tempo row", "row", SEVERITY_BLOCK_BEGINNER,
        "Tempo row — specialty"),
    # ── Round 6 audit additions: row / pulldown grip-progression variants ──
    SpecialtyPattern("row - underhand grip", "row", SEVERITY_BLOCK_UNTIL_ESTABLISHED,
        "Underhand-grip row is a grip-progression variant; show standard pronated row first"),
    SpecialtyPattern("row - reverse grip", "row", SEVERITY_BLOCK_UNTIL_ESTABLISHED,
        "Reverse-grip row is a grip-progression variant; show standard row first"),
    SpecialtyPattern("row - close grip", "row", SEVERITY_BLOCK_UNTIL_ESTABLISHED,
        "Close-grip row is a grip-progression variant; show standard row first"),
    SpecialtyPattern("row - wide grip", "row", SEVERITY_BLOCK_UNTIL_ESTABLISHED,
        "Wide-grip row is a grip-progression variant; show standard row first"),
    SpecialtyPattern("pulldown - reverse grip", "pulldown", SEVERITY_BLOCK_UNTIL_ESTABLISHED,
        "Reverse-grip lat pulldown is a grip-progression variant; show standard pulldown first"),
    SpecialtyPattern("pulldown - close grip", "pulldown", SEVERITY_BLOCK_UNTIL_ESTABLISHED,
        "Close-grip lat pulldown is a grip-progression variant; show standard pulldown first"),
    SpecialtyPattern("pulldown - wide grip", "pulldown", SEVERITY_BLOCK_UNTIL_ESTABLISHED,
        "Wide-grip lat pulldown is a grip-progression variant; show standard pulldown first"),
    SpecialtyPattern("pulldown - underhand grip", "pulldown", SEVERITY_BLOCK_UNTIL_ESTABLISHED,
        "Underhand-grip lat pulldown is a grip-progression variant; show standard pulldown first"),
]

# ─── Curl family ─────────────────────────────────────────────────────────────

CURL_VARIANTS: List[SpecialtyPattern] = [
    SpecialtyPattern(" 21s", "curl", SEVERITY_BLOCK_BEGINNER,
        "21s = partial-rep set scheme — specialty programming"),
    SpecialtyPattern("21s curl", "curl", SEVERITY_BLOCK_BEGINNER,
        "21s curl — specialty"),
    SpecialtyPattern("drag curl", "curl", SEVERITY_BLOCK_BEGINNER,
        "Drag curl — specialty (elbow path is unintuitive for beginners)"),
    SpecialtyPattern("zottman", "curl", SEVERITY_BLOCK_BEGINNER,
        "Zottman curl = curl + reverse-curl combo — specialty"),
    SpecialtyPattern("waiter curl", "curl", SEVERITY_BLOCK_INTERMEDIATE,
        "Waiter curl — specialty"),
    # ── Round 6 audit additions ──
    SpecialtyPattern("olympic", "curl", SEVERITY_BLOCK_UNTIL_ESTABLISHED,
        "Olympic-bar/grip curls (e.g. 'Olympic (Barbell) Hammer Curl') are loading-progression variants; show standard curl first regardless of level"),
    SpecialtyPattern("concentration curl - close grip", "curl", SEVERITY_BLOCK_BEGINNER,
        "Close-grip concentration curl combines two specialty modifiers — show standard curl first"),
    SpecialtyPattern("concentration curl - wide grip", "curl", SEVERITY_BLOCK_BEGINNER,
        "Wide-grip concentration curl combines two specialty modifiers — show standard curl first"),
    SpecialtyPattern("skull crusher - reverse grip", "triceps", SEVERITY_BLOCK_UNTIL_ESTABLISHED,
        "Reverse-grip skull crusher is a grip-progression variant — show standard skull crusher first"),
    SpecialtyPattern("skull crusher - wide grip", "triceps", SEVERITY_BLOCK_UNTIL_ESTABLISHED,
        "Wide-grip skull crusher is a grip-progression variant — show standard skull crusher first"),
    SpecialtyPattern("skull crusher - close grip", "triceps", SEVERITY_BLOCK_UNTIL_ESTABLISHED,
        "Close-grip skull crusher is a grip-progression variant — show standard skull crusher first"),
    SpecialtyPattern("bayesian curl", "curl", SEVERITY_BLOCK_INTERMEDIATE,
        "Bayesian curl = behind-body cable curl — specialty"),
]

# ─── Press family (overhead) ─────────────────────────────────────────────────

OHP_VARIANTS: List[SpecialtyPattern] = [
    SpecialtyPattern("z press", "ohp", SEVERITY_BLOCK_INTERMEDIATE,
        "Z-press = floor-seated press — specialty"),
    SpecialtyPattern("savickas press", "ohp", SEVERITY_BLOCK_INTERMEDIATE,
        "Savickas press — specialty"),
    SpecialtyPattern("bradford press", "ohp", SEVERITY_BLOCK_INTERMEDIATE,
        "Bradford press = front-to-back press — specialty"),
    SpecialtyPattern("cuban press", "ohp", SEVERITY_BLOCK_INTERMEDIATE,
        "Cuban press — specialty rotator cuff sequence"),
    SpecialtyPattern("sots press", "ohp", SEVERITY_BLOCK_INTERMEDIATE,
        "Sots press = press from bottom of squat — specialty"),
    SpecialtyPattern("viking press", "ohp", SEVERITY_BLOCK_INTERMEDIATE,
        "Viking press requires landmine attachment — specialty"),
    SpecialtyPattern("landmine press", "ohp", SEVERITY_BLOCK_BEGINNER,
        "Landmine press is fine but show regular OHP variants first"),
]

# ─── Core / oblique family ───────────────────────────────────────────────────
# Anti-rotation / rotation core variants. The Pallof press is a canonical
# anti-rotation drill — adding "twist" turns it into a specialty progression
# that loses the anti-rotation cue.

CORE_OBLIQUE_VARIANTS: List[SpecialtyPattern] = [
    SpecialtyPattern("pallof press twist", "core_oblique", SEVERITY_BLOCK_ALL,
        "Pallof press WITH rotation contradicts the anti-rotation cue that defines the pallof press — never autogen"),
    SpecialtyPattern("pallof twist", "core_oblique", SEVERITY_BLOCK_ALL,
        "Pallof press WITH rotation contradicts the anti-rotation cue that defines the pallof press — never autogen"),
    # 2026-05-08 audit Round 3 addition — half-kneeling stance is an anti-rotation progression
    # Listed AFTER the pallof-twist patterns above so any future "Half Kneeling Pallof Press Twist"
    # gets caught by the more-dangerous BLOCK_ALL pattern first.
    SpecialtyPattern("half kneeling pallof", "core_oblique", SEVERITY_BLOCK_BEGINNER,
        "Half-kneeling pallof press requires anti-rotation core stability — show standing pallof first for beginners"),
]

# ─── Plank family ────────────────────────────────────────────────────────────
# Hybrid / obscure plank variants. The standard plank is the canonical core
# hold — these add limb movement that turns the drill into a stability
# specialty rather than foundational core work.

PLANK_VARIANTS: List[SpecialtyPattern] = [
    SpecialtyPattern("reverse plank march", "plank", SEVERITY_BLOCK_ALL,
        "Reverse-plank-with-marching is an obscure mobility-flow hybrid; never an autogen pick (audit 2026-05-08: Advanced user got this)"),
    SpecialtyPattern("leg extension plank", "plank", SEVERITY_BLOCK_ALL,
        "Leg-extension-plank is a mobility-flow hybrid, not a strength movement; never autogen at any level"),
    # 2026-05-08 audit Round 3 additions — complex plank progressions
    SpecialtyPattern("side bend plank", "plank", SEVERITY_BLOCK_BEGINNER,
        "Side-bend plank is a complex plank progression — beginners should master standard plank first"),
    SpecialtyPattern("elbow to knee side plank", "plank", SEVERITY_BLOCK_BEGINNER,
        "Elbow-to-knee side plank is an advanced plank progression — beginners should master standard side plank first"),
    # 2026-05-08 audit Round 4 additions — elbow-modified plank variants.
    # Bumped to BLOCK_UNTIL_ESTABLISHED so Advanced users at count=0 don't
    # get them either (user feedback: "advanced types come later when
    # progression feels correct, not premature").
    SpecialtyPattern("reverse plank on elbows", "plank", SEVERITY_BLOCK_UNTIL_ESTABLISHED,
        "Reverse-plank-on-elbows is a forearm-supported variant — show standard reverse plank first regardless of level"),
    SpecialtyPattern("plank on elbows", "plank", SEVERITY_BLOCK_UNTIL_ESTABLISHED,
        "Plank-on-elbows variants are scapular/forearm progressions — show standard plank first regardless of level"),
]

# ─── Dip / Shrug families (2026-05-08 audit Round 4 additions) ──────────────
# Modifier variants of the canonical dip and shrug movements.

DIP_VARIANTS: List[SpecialtyPattern] = [
    SpecialtyPattern("deep dip", "dip", SEVERITY_BLOCK_UNTIL_ESTABLISHED,
        "Deep dip = below-parallel range — specialty depth variant; show standard dip first regardless of level"),
]

STABILITY_VARIANTS: List[SpecialtyPattern] = [
    # Round 6 audit additions: head-support / stability accessory variants
    SpecialtyPattern("support head", "stability", SEVERITY_BLOCK_BEGINNER,
        "Head-supported variants (e.g. 'Rear Lateral Raise Support Head') are stability-regression specialties — not standard autogen picks"),
    SpecialtyPattern("head supported", "stability", SEVERITY_BLOCK_BEGINNER,
        "Head-supported lateral raise / row is a stability-regression specialty"),
    SpecialtyPattern("feet flat bench press", "bench_press", SEVERITY_BLOCK_UNTIL_ESTABLISHED,
        "Feet-flat bench press is a leg-drive technique modifier — show standard bench first regardless of level"),
    SpecialtyPattern("twisting crunch", "core", SEVERITY_BLOCK_BEGINNER,
        "Twisting/rotational crunch combines flexion + rotation under load — not a standard autogen pick for beginners"),
    SpecialtyPattern("weighted twisting", "core", SEVERITY_BLOCK_BEGINNER,
        "Weighted twisting core movement places shear load on lumbar spine — specialty"),
    SpecialtyPattern("(trx) - alternating", "trx_combo", SEVERITY_BLOCK_BEGINNER,
        "TRX alternating-limb variants (e.g. 'Superman TRX - Alternating') are stability-progression specialties — show standard variant first"),
    SpecialtyPattern("trx alternating", "trx_combo", SEVERITY_BLOCK_BEGINNER,
        "TRX alternating-limb variants are stability-progression specialties"),
]

SHRUG_VARIANTS: List[SpecialtyPattern] = [
    SpecialtyPattern("decline shrug", "shrug", SEVERITY_BLOCK_UNTIL_ESTABLISHED,
        "Decline shrug = lying decline trap shrug — specialty variant; show standard barbell/DB shrug first regardless of level"),
]

# ─── Kettlebell combo family (2026-05-08 audit Round 3 additions) ───────────
# Multi-movement KB hybrids (swing-to-X, swing-clean-grip-X). The base swing
# and the target movement should be programmed separately — never as a single
# auto-generated pick at any level. Listed FIRST in SPECIALTY_PATTERNS so
# "Swing Clean Grip Front Squat" matches the BLOCK_ALL combo here before any
# fragment match like the squat-family "clean grip" (BLOCK_UNTIL_ESTABLISHED).
# (Note: SQUAT_VARIANTS also contains BLOCK_ALL copies of these patterns —
# either path produces the correct decision; this family makes the intent
# explicit at the top of the registry.)

KETTLEBELL_COMBO_VARIANTS: List[SpecialtyPattern] = [
    SpecialtyPattern("swing clean grip", "kb_combo", SEVERITY_BLOCK_ALL,
        "Swing-clean-grip-X (e.g. Swing Clean Grip Front Squat) is a multi-movement KB hybrid — never autogen at any level"),
    SpecialtyPattern("swing to ", "kb_combo", SEVERITY_BLOCK_ALL,
        "KB swing-to-X (e.g. Swing To Goblet Squat) is a mobility-flow combo — base swing and target movement should be separate"),
]


# ─── 🚨 CRITICAL SAFETY (.block_all) ─────────────────────────────────────────
# Audit 2026-05-08 Round 6: 6 `injury_unsafe` flags including a 32yo female
# user with NECK INJURIES being recommended "Standing Behind Head Military
# Press" as exercise #1 (verdict: REJECT). These patterns block at every
# level — the database practicality score must NEVER override safety.

SAFETY_VARIANTS: List[SpecialtyPattern] = [
    SpecialtyPattern("behind head", "safety", SEVERITY_BLOCK_ALL,
        "🚨 SAFETY: Behind-the-head pressing creates shoulder impingement risk and rotator cuff stress; never auto-recommend regardless of level"),
    SpecialtyPattern("behind neck", "safety", SEVERITY_BLOCK_ALL,
        "🚨 SAFETY: Behind-the-neck pressing is contraindicated for all users — shoulder impingement risk"),
    SpecialtyPattern("behind the neck", "safety", SEVERITY_BLOCK_ALL,
        "🚨 SAFETY: Behind-the-neck pressing is contraindicated for all users — shoulder impingement risk"),
]


# ─── Catalog-hybrid combos (.block_all) ──────────────────────────────────────
# Multi-movement chains that combine a base lift with another exercise.
# These are catalog-corruption hybrids — never the right autogen pick.
HYBRID_COMBO_VARIANTS: List[SpecialtyPattern] = [
    SpecialtyPattern(" with high pull", "combo", SEVERITY_BLOCK_ALL,
        "X-with-high-pull combines a base lift with an Olympic-derivative — never autogen"),
    SpecialtyPattern(" with calf raise", "combo", SEVERITY_BLOCK_ALL,
        "X-with-calf-raise combines a primary lift with calf isolation — never autogen the combo"),
    SpecialtyPattern("russian twist with", "combo", SEVERITY_BLOCK_ALL,
        "X-with-russian-twist combines a primary lift with a core/rotation movement — never autogen"),
    SpecialtyPattern("press russian twist", "combo", SEVERITY_BLOCK_ALL,
        "Military-Press-Russian-Twist is a catalog-corruption hybrid (audit Round 6: served to a 64yo Beginner) — never autogen"),
    SpecialtyPattern("pressdown - skull crusher", "triceps", SEVERITY_BLOCK_ALL,
        "Pressdown-skull-crusher is a catalog-hybrid combining two distinct triceps movements — never autogen"),
]

# ─── Pull-up family (2026-05-08 audit Round 3 additions) ────────────────────
# Grip / equipment-context variants of the pull-up. Beginners should own the
# standard pull-up / chin-up progression first.

PULLUP_VARIANTS: List[SpecialtyPattern] = [
    SpecialtyPattern("hammer grip pull up", "pullup", SEVERITY_BLOCK_UNTIL_ESTABLISHED,
        "Hammer-grip pull-up — grip-progression variant; show standard pull-up/chin-up first regardless of level"),
    SpecialtyPattern("dip cage", "pullup", SEVERITY_BLOCK_BEGINNER,
        "Dip-cage exercises are a specialty equipment context — beginners should master standard pull-up first"),
]

# ─── Generic prescription modifiers ──────────────────────────────────────────
# These modifiers can appear on ANY exercise. They indicate a tempo /
# rep-scheme prescription (1 1/4, 21s, drop set, cluster, rest pause) that
# is a specialty programming choice — never the right "default" exercise
# for a beginner regardless of base movement.

GENERIC_MODIFIERS: List[SpecialtyPattern] = [
    SpecialtyPattern(" tempo ", "generic", SEVERITY_BLOCK_BEGINNER,
        "Tempo-prescribed exercise — specialty rep cadence"),
    SpecialtyPattern(" paused ", "generic", SEVERITY_BLOCK_BEGINNER,
        "Paused variant — specialty"),
    SpecialtyPattern("1 1/4 ", "generic", SEVERITY_BLOCK_BEGINNER,
        "1 1/4 rep — specialty rep scheme"),
    SpecialtyPattern("1.25 ", "generic", SEVERITY_BLOCK_BEGINNER,
        "1.25 rep — specialty rep scheme"),
    SpecialtyPattern("1.5 ", "generic", SEVERITY_BLOCK_BEGINNER,
        "1.5 rep — specialty rep scheme"),
    SpecialtyPattern("rest pause", "generic", SEVERITY_BLOCK_BEGINNER,
        "Rest-pause set — specialty intensity technique"),
    SpecialtyPattern("myo-rep", "generic", SEVERITY_BLOCK_BEGINNER,
        "Myo-rep set — specialty intensity technique"),
    SpecialtyPattern("myo rep", "generic", SEVERITY_BLOCK_BEGINNER,
        "Myo-rep set — specialty intensity technique"),
    SpecialtyPattern("cluster set", "generic", SEVERITY_BLOCK_BEGINNER,
        "Cluster set — specialty intensity technique"),
    SpecialtyPattern("drop set", "generic", SEVERITY_BLOCK_BEGINNER,
        "Drop-set prescribed in name — specialty technique"),
    SpecialtyPattern("with chains", "generic", SEVERITY_BLOCK_INTERMEDIATE,
        "Chain-loaded — specialty equipment"),
    SpecialtyPattern("banded ", "generic", SEVERITY_BLOCK_INTERMEDIATE,
        "Band-loaded — specialty (unless it's the canonical exercise like band pull-apart)"),
    SpecialtyPattern("eccentric only", "generic", SEVERITY_BLOCK_BEGINNER,
        "Eccentric-only — specialty programming"),
    SpecialtyPattern("isometric hold", "generic", SEVERITY_BLOCK_UNTIL_ESTABLISHED,
        "Isometric-hold prescribed — specialty technique requiring mind-muscle mastery; never the first autogen variant of a movement (audit Round 4: Advanced user got 'Isometric Hold Push Up')"),
]


# ─── Round 9 audit additions (2026-05-10) ───────────────────────────────────
# Source: scripts/output/autogen_audit_20260510_145119.md residual slip table.
# 31% of workouts had a specialty-variant flag despite Round 8's filter wire-in.
# Mirrors the equivalent block in `Fit33/SmartExerciseSelectionEngine.swift`
# `SpecialtyVariantFilter.patterns`. Order matters within this list: catalog
# combos (BLOCK_ALL) and sumo / family-specific patterns first, generic
# alternating / single-arm / isometric / twisting modifiers last.

ROUND_9_VARIANTS: List[SpecialtyPattern] = [
    # Catalog-corruption combos (BLOCK_ALL — never autogen at any level)
    SpecialtyPattern("pullover with bench", "combo", SEVERITY_BLOCK_ALL,
        "Pullover-with-bench-press is a catalog-corruption combo combining two distinct movements — never autogen"),
    SpecialtyPattern("bench press pullover", "combo", SEVERITY_BLOCK_ALL,
        "Bench-press-pullover is a catalog-corruption combo — never autogen"),
    SpecialtyPattern("squat hold calf raise", "combo", SEVERITY_BLOCK_ALL,
        "Squat-hold-with-calf-raise is a catalog-corruption combo combining two distinct movements"),
    SpecialtyPattern("reverse lunge front kick", "combo", SEVERITY_BLOCK_ALL,
        "Reverse-lunge-front-kick is a martial-arts-derived combo — never autogen for strength workouts"),

    # Sumo / SLDL deadlift family additions (specific before generic stiff-leg patterns)
    SpecialtyPattern("sumo romanian", "deadlift", SEVERITY_BLOCK_UNTIL_ESTABLISHED,
        "Sumo-stance Romanian deadlift = sumo stance + RDL technique — show conventional RDL first regardless of level"),
    SpecialtyPattern("sumo deadlift", "deadlift", SEVERITY_BLOCK_UNTIL_ESTABLISHED,
        "Sumo deadlift requires different hip mobility / technique than conventional — show conventional first regardless of level (audit Round 9: 3× hits)"),
    SpecialtyPattern("stiff legged", "deadlift", SEVERITY_BLOCK_BEGINNER,
        "Stiff-legged deadlift (catalog spelling) — high low-back stress, specialty for beginners (complement to existing 'stiff leg')"),
    SpecialtyPattern("straight back stiff", "deadlift", SEVERITY_BLOCK_UNTIL_ESTABLISHED,
        "'Straight Back Stiff Leg Deadlift' combines two postural-cue modifiers — show standard SLDL/RDL first regardless of level"),

    # Squat / lunge family additions
    SpecialtyPattern("low bar", "squat", SEVERITY_BLOCK_UNTIL_ESTABLISHED,
        "Low-bar squat is an advanced powerlifting bar position requiring extensive shoulder/wrist mobility — show high-bar / standard back squat first regardless of level"),
    SpecialtyPattern("wide squat", "squat", SEVERITY_BLOCK_BEGINNER,
        "Wide-stance squat is a stance modifier — beginners should master standard back squat positioning first"),
    SpecialtyPattern("narrow squat", "squat", SEVERITY_BLOCK_BEGINNER,
        "Narrow-stance squat is a stance modifier — beginners should master standard squat positioning first"),
    SpecialtyPattern("pulse ", "squat", SEVERITY_BLOCK_BEGINNER,
        "Pulse-rep squat / pulse goblet squat is a tempo-variant specialty — beginners should master full-range first"),
    SpecialtyPattern("sumo quarter", "squat", SEVERITY_BLOCK_ALL,
        "Sumo-quarter-squat / tip-toe entries are catalog-corruption multi-modifier combos — never autogen at any level"),
    SpecialtyPattern("tip toe", "squat", SEVERITY_BLOCK_BEGINNER,
        "Tip-toe / toe-elevated squat is a balance-progression specialty — not appropriate for beginner squat patterning"),
    SpecialtyPattern("high knee squat", "squat", SEVERITY_BLOCK_BEGINNER,
        "High-knee squat is a coordination/balance variant — beginners should master basic bodyweight squat first"),
    SpecialtyPattern("elevated heel", "squat", SEVERITY_BLOCK_BEGINNER,
        "Heels-elevated squat (catalog phrasing) is a quad-emphasis specialty (complement to existing 'heels elevated')"),
    SpecialtyPattern("opposite reverse lunge", "lunge", SEVERITY_BLOCK_BEGINNER,
        "Opposite-reverse-lunge (contralateral loading) is a specialty unilateral variant — show standard reverse lunge first for beginners"),
    SpecialtyPattern("opposite lunge", "lunge", SEVERITY_BLOCK_BEGINNER,
        "Opposite-loaded lunge is a contralateral-loading specialty — show standard lunge first"),

    # Plank / core / pallof family additions
    SpecialtyPattern("plank arm lift", "plank", SEVERITY_BLOCK_BEGINNER,
        "Plank-with-arm-lift requires single-arm stability — beginners should master basic plank first"),
    SpecialtyPattern("side plank raise", "plank", SEVERITY_BLOCK_BEGINNER,
        "Side-plank-with-raise is a complex unilateral plank progression — beginners should master standard side plank first"),
    SpecialtyPattern("front plank arm leg", "plank", SEVERITY_BLOCK_BEGINNER,
        "Front plank with arm/leg raise is a complex stability progression — beginners should master basic front plank first"),
    SpecialtyPattern("horizontal pallof", "pallof", SEVERITY_BLOCK_BEGINNER,
        "Horizontal pallof press is an anti-rotation progression — beginners should master standing pallof first"),

    # Pull-up additions
    SpecialtyPattern("commando", "pullup", SEVERITY_BLOCK_UNTIL_ESTABLISHED,
        "Commando pull-up = alternating-grip pull-up — specialty grip variant; show standard pull-up first regardless of level"),

    # Equipment / triceps / OHP specialty
    SpecialtyPattern("weighted chains", "bench_press", SEVERITY_BLOCK_INTERMEDIATE,
        "Weighted-chains bench press requires accommodating-resistance equipment most users don't have — specialty equipment context"),
    SpecialtyPattern("tate press", "triceps", SEVERITY_BLOCK_UNTIL_ESTABLISHED,
        "Tate press is a specialty triceps variant — show standard triceps extension/skull crusher first regardless of level"),
    SpecialtyPattern("seesaw press", "ohp", SEVERITY_BLOCK_BEGINNER,
        "Seesaw press = alternating overhead press — unilateral stability progression; beginners should master bilateral overhead press first"),
    SpecialtyPattern("side press", "ohp", SEVERITY_BLOCK_BEGINNER,
        "Side press is a kettlebell-windmill-derived overhead variant — show standard OHP first for beginners"),

    # Generic unilateral / alternating / isometric / twisting modifiers
    # (place near end so family-specific patterns above match first)
    SpecialtyPattern("alternating", "generic", SEVERITY_BLOCK_BEGINNER,
        "Alternating-limb variants (e.g. '(Dumbbell) - Alternating') are unilateral stability progressions — beginners should master bilateral first (audit Round 9: 4× hits)"),
    SpecialtyPattern("single weight", "generic", SEVERITY_BLOCK_BEGINNER,
        "Single-weight variants (e.g. 'Bench Press - Single Weight') are unilateral asymmetric loading — beginners should master bilateral first"),
    SpecialtyPattern("single leg push", "generic", SEVERITY_BLOCK_BEGINNER,
        "Single-leg push-up (incl. 'Raise Single Leg Push Up') is a unilateral stability progression — beginners should master standard push-up first"),
    SpecialtyPattern("single leg chest", "generic", SEVERITY_BLOCK_BEGINNER,
        "Single-leg chest press (TRX) is a unilateral stability progression — beginners should master bilateral first"),
    SpecialtyPattern("single leg bridge", "generic", SEVERITY_BLOCK_BEGINNER,
        "Single-leg bridge / hip thrust is a unilateral progression — beginners should master bilateral hip thrust first"),
    SpecialtyPattern("single arm lateral", "generic", SEVERITY_BLOCK_BEGINNER,
        "Single-arm lateral raise is a unilateral specialty — beginners should master bilateral lateral raise first"),
    SpecialtyPattern("single arm twisting", "generic", SEVERITY_BLOCK_BEGINNER,
        "Single-arm twisting row is a rotational unilateral specialty — beginners should master bilateral standard row first"),
    SpecialtyPattern("raise single leg", "generic", SEVERITY_BLOCK_BEGINNER,
        "Raise-single-leg variants are unilateral stability progressions — beginners should master bilateral first"),
    SpecialtyPattern("staggered stance", "generic", SEVERITY_BLOCK_BEGINNER,
        "Staggered-stance variants are unilateral asymmetric specialties — beginners should master bilateral foundation first"),
    SpecialtyPattern(" isometric", "generic", SEVERITY_BLOCK_UNTIL_ESTABLISHED,
        "Isometric-hold programming (e.g. 'Bicep Hold - Isometric (Band)') is a specialty technique — show standard cadence first regardless of level (complement to existing 'isometric hold')"),
    SpecialtyPattern("twisting ", "generic", SEVERITY_BLOCK_UNTIL_ESTABLISHED,
        "Twisting / rotational variants combine flexion + rotation — rotational specialty; show standard movement first regardless of level"),
]


# All patterns assembled. Order matters — specific (longer) families come
# before generic modifiers so a name like "Paused Squat" matches
# `paused squat` (specific) before ` paused ` (generic).

SPECIALTY_PATTERNS: List[SpecialtyPattern] = (
    # 🚨 SAFETY MUST come absolutely first — behind-head/neck pressing must
    # never be auto-recommended even if the database score is high.
    SAFETY_VARIANTS
    # Hybrid catalog-corruption combos next (before family fragments can match)
    + HYBRID_COMBO_VARIANTS
    # KB combo: "swing clean grip" / "swing to " (BLOCK_ALL) must pre-empt
    # any fragment match (e.g. squat-family "clean grip" BLOCK_UNTIL_ESTABLISHED)
    # on names like "Swing Clean Grip Front Squat".
    + KETTLEBELL_COMBO_VARIANTS
    # Round 9 catalog combos + sumo deadlift specifics need to match BEFORE
    # the generic family lists so e.g. "Sumo Romanian Deadlift" hits the
    # specific Round 9 pattern instead of falling through to family generic
    # patterns.
    + ROUND_9_VARIANTS
    + BENCH_PRESS_VARIANTS
    + SQUAT_VARIANTS
    + DEADLIFT_VARIANTS
    + ROW_VARIANTS
    + CURL_VARIANTS
    + OHP_VARIANTS
    + CORE_OBLIQUE_VARIANTS
    + PLANK_VARIANTS
    + DIP_VARIANTS
    + SHRUG_VARIANTS
    + STABILITY_VARIANTS
    + PULLUP_VARIANTS
    + GENERIC_MODIFIERS
)


# ─────────────────────────────────────────────────────────────────────────────
# Public API
# ─────────────────────────────────────────────────────────────────────────────

@dataclass(frozen=True)
class SpecialtyMatch:
    matched: bool
    pattern: Optional[str] = None
    base_movement: Optional[str] = None
    severity: Optional[str] = None
    rationale: Optional[str] = None


_NO_MATCH = SpecialtyMatch(matched=False)


def is_specialty_variant(exercise_name: str) -> SpecialtyMatch:
    """
    Return the first matching specialty pattern, or `SpecialtyMatch(matched=False)`.

    Match is substring-based and case-insensitive.
    """
    if not exercise_name:
        return _NO_MATCH

    haystack = " " + exercise_name.lower() + " "  # pad for word-boundary patterns
    for sp in SPECIALTY_PATTERNS:
        if sp.pattern in haystack:
            return SpecialtyMatch(
                matched=True,
                pattern=sp.pattern,
                base_movement=sp.base_movement,
                severity=sp.severity,
                rationale=sp.rationale,
            )
    return _NO_MATCH


def is_blocked_for_level(
    exercise_name: str,
    experience_level: str,
    completed_workout_count: int = 0,
    user_age: int = 0,
) -> SpecialtyMatch:
    """
    Return a SpecialtyMatch with `matched=True` ONLY if the exercise is a
    specialty variant AND the user's experience level (and workout history,
    for `block_until_established` patterns) puts it out of bounds.

    `experience_level` is the canonical Swift string: "Beginner",
    "Intermediate", "Advanced". Case-insensitive.

    `completed_workout_count` is the user's lifetime completed-workout count
    (defaults to 0 for synthetic audit users — they always trigger the
    block_until_established gate). The live Swift caller passes the user's
    real workout count from `WorkoutManager`.

    `user_age` was added in Round 9 (2026-05-10) — when `user_age >= 60`,
    EVERY specialty pattern is treated as `block_all` regardless of severity.
    Older adults should never see specialty variants via autogen even if their
    experience level says "Advanced". Default 0 keeps legacy callers
    compatible (the age check no-ops at 0).

    Mapping:
      - block_beginner             → blocks Beginner only
      - block_intermediate         → blocks Beginner + Intermediate
      - block_until_established    → blocks at every level UNTIL the user
                                     has completed at least
                                     `WORKOUT_COUNT_THRESHOLDS[level]` workouts
      - block_all                  → blocks every level always
      - any severity + age >= 60   → blocked
    """
    match = is_specialty_variant(exercise_name)
    if not match.matched:
        return _NO_MATCH

    # Age >= 60 hard-block (Round 9) — applies regardless of pattern severity.
    if user_age >= 60:
        return match

    level = (experience_level or "").strip().lower()

    if match.severity == SEVERITY_BLOCK_ALL:
        return match
    if match.severity == SEVERITY_BLOCK_INTERMEDIATE and level in {"beginner", "intermediate"}:
        return match
    if match.severity == SEVERITY_BLOCK_BEGINNER and level == "beginner":
        return match
    if match.severity == SEVERITY_BLOCK_UNTIL_ESTABLISHED:
        # Threshold default = beginner threshold (most conservative) when
        # level isn't a known string.
        threshold = WORKOUT_COUNT_THRESHOLDS.get(
            level, WORKOUT_COUNT_THRESHOLDS["beginner"]
        )
        if completed_workout_count < threshold:
            return match

    # Specialty matched but the level / progression is high enough to allow it.
    return _NO_MATCH


def specialty_severity(exercise_name: str) -> Optional[str]:
    """
    Convenience: return the severity string for a name, or None if not a
    specialty variant.
    """
    match = is_specialty_variant(exercise_name)
    return match.severity if match.matched else None


# ─────────────────────────────────────────────────────────────────────────────
# Complex / catalog-corrupted hybrid name detection (audit Round 4 fix)
# ─────────────────────────────────────────────────────────────────────────────
# The specialty filter above blocks NAMED variants ("close grip", "rack pull",
# etc.) but our exercise catalog also contains UNNAMED catalog corruption:
# multi-movement compounds like "Romanian Deadlift Bicep Curl Kickback" or
# "Push up - Tricep Extension" that aren't a recognized specialty modifier of
# a single base movement — they're just two-or-more exercises mashed together.
# Claude consistently flags these as `obscure_exercise` (108 instances in
# Round 4). They are never appropriate for autogen at any level.
#
# Heuristic — block a name when ANY of the following are true:
#   (a) Two or more " to " connectors  (e.g. "Squat to Press to Curl")
#   (b) Two or more " and " connectors (e.g. "Lunge and Twist and Reach")
#   (c) Three or more distinct MOVEMENT_NOUNS in the tokenized name
#       (e.g. "Romanian Deadlift Bicep Curl Kickback" → deadlift+curl+kickback)
#   (d) " - " separator (or " – ") with a movement noun on BOTH sides
#       (e.g. "Push up - Tricep Extension" → push|extension)
#   (e) 4 or more hyphens — usually an over-described mobility variant
#
# Heuristic intentionally does NOT trigger on hyphenated qualifier words
# (e.g. "Single-Arm" / "T-Bar"); those don't satisfy the "movement noun on both
# sides of the separator" rule.

MOVEMENT_NOUNS: Set[str] = {
    "deadlift", "squat", "lunge", "press", "curl", "row", "fly", "flye",
    "raise", "kickback", "extension", "crunch", "twist", "swing", "snatch",
    "clean", "jerk", "pulldown", "pressdown", "thrust", "pushdown",
    "shrug", "tuck", "march", "carry", "throw", "drag", "fold", "reach",
    # Bigram / compound movements collapsed to single tokens during normalization
    "pushup", "pullup", "chinup", "situp", "stepup", "burpee", "thruster",
    "snatch", "kickback", "kickup", "kneeup",
}

# Bigram → single-token rewrites applied BEFORE tokenization. Handles names
# like "Push Up - Tricep Extension" (collapses "push up" → "pushup" so the
# left side of the separator has a movement noun).
_BIGRAM_REWRITES: List[tuple] = [
    (" push up", " pushup"),
    (" push-up", " pushup"),
    (" pull up", " pullup"),
    (" pull-up", " pullup"),
    (" chin up", " chinup"),
    (" chin-up", " chinup"),
    (" sit up", " situp"),
    (" sit-up", " situp"),
    (" step up", " stepup"),
    (" step-up", " stepup"),
    (" knee up", " kneeup"),
    (" knee tuck", " tuck"),  # so "knee tuck" registers as a movement noun
]

# These tokens read like movement names but appear as setup/equipment/grip
# qualifiers. They should NOT add to the movement-noun count.
NOT_REAL_MOVEMENT_TOKENS: Set[str] = {
    "press",  # caveat: "press" IS a movement, but in setups like "Bench Press
              # (Barbell)" or "Leg Press (Plate Loaded Machine)" it's the
              # primary movement — we keep it. Listed here as a reminder; not
              # actually filtered.
}


def is_complex_hybrid_name(exercise_name: str) -> Optional[str]:
    """
    Return a reason string if `exercise_name` looks like a multi-movement
    catalog-corrupted hybrid, or None if the name is clean.

    Used by the audit + Swift autogen to hard-block these at every level.
    """
    if not exercise_name:
        return None

    name = exercise_name.lower()
    # Strip parenthetical equipment qualifiers like "(Barbell)" / "(Dumbbell)"
    # so they don't perturb the token analysis (they're not movement nouns,
    # but a paren is treated as a token boundary anyway).
    bare = name
    while "(" in bare and ")" in bare:
        i = bare.index("(")
        j = bare.index(")", i)
        bare = (bare[:i] + bare[j + 1:]).strip()

    # Collapse bigram movements ("push up" → "pushup") so they register as a
    # single movement noun in token analysis below.
    padded = " " + bare + " "
    for src, dst in _BIGRAM_REWRITES:
        padded = padded.replace(src, dst)
    bare = padded.strip()

    to_count = bare.count(" to ")
    if to_count >= 2:
        return "Multi-stage hybrid (>=2 ' to ' connectors)"
    and_count = bare.count(" and ")
    if and_count >= 2:
        return "Multi-stage hybrid (>=2 ' and ' connectors)"
    hyphen_count = bare.count("-")
    if hyphen_count >= 4:
        return "Multi-stage hybrid (>=4 hyphens)"

    # Token-based movement-noun count
    tokens = [t for t in bare.replace("-", " ").replace("/", " ").split() if t]
    movement_hits = [t for t in tokens if t in MOVEMENT_NOUNS]
    if len(set(movement_hits)) >= 3:
        return f"Multi-stage hybrid (>=3 distinct movement nouns: {sorted(set(movement_hits))})"

    # " - " (or " – ") separator with movement noun on both sides
    for sep in (" - ", " – ", " — "):
        if sep in bare:
            left, right = bare.split(sep, 1)
            left_movements = [t for t in left.split() if t in MOVEMENT_NOUNS]
            right_movements = [t for t in right.split() if t in MOVEMENT_NOUNS]
            if left_movements and right_movements:
                return (
                    f"Catalog-corrupted hybrid '<{left_movements[0]}>"
                    f" - <{right_movements[0]}>'"
                )

    return None


# ─────────────────────────────────────────────────────────────────────────────
# Test fixture — `python specialty_exercise_filter.py` runs these.
# Add a sample name when you add a new pattern.
# ─────────────────────────────────────────────────────────────────────────────

# (name, expected_match, expected_severity_or_None)
SAMPLE_NAMES: List[tuple] = [
    # ─ blocked for beginner only ─
    ("Feet On Bench Barbell Bench Press", True, SEVERITY_BLOCK_BEGINNER),
    ("Feet Up Dumbbell Bench Press", True, SEVERITY_BLOCK_BEGINNER),
    ("Feet Elevated Push Up", True, SEVERITY_BLOCK_BEGINNER),
    ("Paused Back Squat", True, SEVERITY_BLOCK_BEGINNER),
    ("Pause Squat", True, SEVERITY_BLOCK_BEGINNER),
    ("Tempo Squat", True, SEVERITY_BLOCK_BEGINNER),
    ("1 1/4 Squat", True, SEVERITY_BLOCK_BEGINNER),
    ("Box Squat", True, SEVERITY_BLOCK_BEGINNER),
    ("Heels Elevated Goblet Squat", True, SEVERITY_BLOCK_BEGINNER),
    ("Sissy Squat", True, SEVERITY_BLOCK_BEGINNER),
    ("Stiff Leg Deadlift", True, SEVERITY_BLOCK_BEGINNER),
    ("Trap Bar Deadlift", True, SEVERITY_BLOCK_BEGINNER),
    ("Drag Curl", True, SEVERITY_BLOCK_BEGINNER),
    ("Zottman Curl", True, SEVERITY_BLOCK_BEGINNER),
    ("Bicep Curl 21s", True, SEVERITY_BLOCK_BEGINNER),
    ("Landmine Press", True, SEVERITY_BLOCK_BEGINNER),
    ("Tempo Romanian Deadlift", True, SEVERITY_BLOCK_BEGINNER),
    # NOTE: Rack Pull, Pin Press, Isometric Hold were promoted from BLOCK_BEGINNER
    # to BLOCK_UNTIL_ESTABLISHED in audit Round 4 (Intermediate users were getting
    # these). See BLOCK_UNTIL_ESTABLISHED section below for canonical fixtures.
    # 2026-05-08 audit Round 3 additions — beginner-only specialty progressions
    # (NOT grip variants — those are BLOCK_UNTIL_ESTABLISHED, see below)
    ("Pull Up (Dip Cage)", True, SEVERITY_BLOCK_BEGINNER),
    ("Side Bend Plank", True, SEVERITY_BLOCK_BEGINNER),
    ("Elbow To Knee Side Plank Crunch", True, SEVERITY_BLOCK_BEGINNER),
    ("Half Kneeling Pallof Press (Cable)", True, SEVERITY_BLOCK_BEGINNER),
    # 2026-05-08 audit Round 4 additions — modifier variants now BLOCK_UNTIL_ESTABLISHED
    # (see fixtures in BLOCK_UNTIL_ESTABLISHED block below)
    # ─ blocked-until-established (grip / unilateral / stability progression
    #   variants that should never be the FIRST autogen pick at any level —
    #   user must complete N workouts to unlock; audit users always count=0) ─
    ("3 Point Bench Press", True, SEVERITY_BLOCK_UNTIL_ESTABLISHED),
    ("Wide Bench Press (Barbell)", True, SEVERITY_BLOCK_UNTIL_ESTABLISHED),
    ("Bench Press - Close Grip (Dumbbell)", True, SEVERITY_BLOCK_UNTIL_ESTABLISHED),
    ("Close Grip Bench Press (Barbell)", True, SEVERITY_BLOCK_UNTIL_ESTABLISHED),
    ("Reverse Close Grip Bench Press", True, SEVERITY_BLOCK_UNTIL_ESTABLISHED),
    ("Decline Bench Press - Wide Grip (Barbell)", True, SEVERITY_BLOCK_UNTIL_ESTABLISHED),
    ("Elevated Goblet Squat", True, SEVERITY_BLOCK_UNTIL_ESTABLISHED),
    ("Split Squat Front Foot Elevated (Dumbbell)", True, SEVERITY_BLOCK_UNTIL_ESTABLISHED),
    ("Single Leg Press (Plate Loaded Machine)", True, SEVERITY_BLOCK_UNTIL_ESTABLISHED),
    ("Front Squat - Clean Grip (Barbell)", True, SEVERITY_BLOCK_UNTIL_ESTABLISHED),
    ("Reverse Lunge - Clean Grip (Kettlebell)", True, SEVERITY_BLOCK_UNTIL_ESTABLISHED),
    ("Pendlay Row (Cable)", True, SEVERITY_BLOCK_UNTIL_ESTABLISHED),
    ("Yates Row", True, SEVERITY_BLOCK_UNTIL_ESTABLISHED),
    ("Meadows Row (Landmine)", True, SEVERITY_BLOCK_UNTIL_ESTABLISHED),
    ("Hammer Grip Pull Up On Dip Cage (Pull-Up Bar)", True, SEVERITY_BLOCK_UNTIL_ESTABLISHED),
    # 2026-05-08 audit Round 4 additions — promoted from BLOCK_BEGINNER to
    # BLOCK_UNTIL_ESTABLISHED + new patterns
    ("Barbell Rack Pull", True, SEVERITY_BLOCK_UNTIL_ESTABLISHED),
    ("Rack Pull (Smith Machine)", True, SEVERITY_BLOCK_UNTIL_ESTABLISHED),
    ("Pin Bench Press Conventional Grip (Barbell)", True, SEVERITY_BLOCK_UNTIL_ESTABLISHED),
    ("Pin Press (Barbell)", True, SEVERITY_BLOCK_UNTIL_ESTABLISHED),
    ("Squeeze Bench Press (Dumbbell)", True, SEVERITY_BLOCK_UNTIL_ESTABLISHED),
    ("Squeeze Press", True, SEVERITY_BLOCK_UNTIL_ESTABLISHED),
    ("Isometric Hold Push Up", True, SEVERITY_BLOCK_UNTIL_ESTABLISHED),
    ("Front Squat - Clean (Barbell)", True, SEVERITY_BLOCK_UNTIL_ESTABLISHED),
    ("Front Squat Clean", True, SEVERITY_BLOCK_UNTIL_ESTABLISHED),
    ("Deep Dip", True, SEVERITY_BLOCK_UNTIL_ESTABLISHED),
    ("Decline Shrug (Dumbbell)", True, SEVERITY_BLOCK_UNTIL_ESTABLISHED),
    ("Reverse Plank On Elbows", True, SEVERITY_BLOCK_UNTIL_ESTABLISHED),
    ("Plank On Elbows", True, SEVERITY_BLOCK_UNTIL_ESTABLISHED),
    # 2026-05-08 audit fix — these are mobility-flow hybrids (not "specialty
    # progressions of a base movement"). Bumped to BLOCK_ALL after Advanced
    # users got them in Build-Muscle workouts and Claude rejected the workout.
    ("Pallof Press Twist", True, SEVERITY_BLOCK_ALL),
    ("Cable Pallof Twist", True, SEVERITY_BLOCK_ALL),
    ("Deep Squat Turn", True, SEVERITY_BLOCK_ALL),
    ("Reverse Plank March", True, SEVERITY_BLOCK_ALL),
    ("Leg Extension Plank", True, SEVERITY_BLOCK_ALL),
    ("Lunge With Internal Rotation", True, SEVERITY_BLOCK_ALL),
    # 2026-05-08 audit Round 3 additions — catalog-corrupted combo movements
    ("Reverse Lunge Forward Lunge", True, SEVERITY_BLOCK_ALL),
    ("Swing To Goblet Squat (Kettlebell)", True, SEVERITY_BLOCK_ALL),
    ("Swing Clean Grip Front Squat (Kettlebell)", True, SEVERITY_BLOCK_ALL),
    # ─ blocked for beginner + intermediate ─
    ("Spoto Press", True, SEVERITY_BLOCK_INTERMEDIATE),
    ("Anderson Squat", True, SEVERITY_BLOCK_INTERMEDIATE),
    ("Zercher Squat", True, SEVERITY_BLOCK_INTERMEDIATE),
    ("Snatch Grip Deadlift", True, SEVERITY_BLOCK_INTERMEDIATE),
    ("Z Press", True, SEVERITY_BLOCK_INTERMEDIATE),
    ("Sots Press", True, SEVERITY_BLOCK_INTERMEDIATE),
    ("Viking Press", True, SEVERITY_BLOCK_INTERMEDIATE),
    ("Bayesian Curl", True, SEVERITY_BLOCK_INTERMEDIATE),
    ("Banded Bench Press", True, SEVERITY_BLOCK_INTERMEDIATE),
    # ─ blocked for everyone (high-risk) ─
    ("Guillotine Press", True, SEVERITY_BLOCK_ALL),
    # ─ NOT blocked (canonical exercises) ─
    ("Barbell Bench Press", False, None),
    ("Dumbbell Bench Press", False, None),
    ("Back Squat", False, None),
    ("Goblet Squat", False, None),
    ("Conventional Deadlift", False, None),
    ("Romanian Deadlift", False, None),
    ("Seated Cable Row", False, None),
    ("Lat Pulldown", False, None),
    ("Bicep Curl", False, None),
    ("Hammer Curl", False, None),
    ("Overhead Press", False, None),
    ("Lateral Raise", False, None),
]


def _self_test() -> int:
    """Returns 0 on pass, non-zero on first failure (for CI)."""
    failures = 0
    print(f"Running self-test on {len(SAMPLE_NAMES)} fixtures…")
    for name, expected_matched, expected_severity in SAMPLE_NAMES:
        match = is_specialty_variant(name)
        ok = match.matched == expected_matched and match.severity == expected_severity
        marker = "✓" if ok else "✗"
        print(f"  {marker} {name!r:55s} → matched={match.matched} severity={match.severity}")
        if not ok:
            print(f"    expected matched={expected_matched} severity={expected_severity}")
            failures += 1

    # Workout-count gating regression — block_until_established patterns
    # must block at count=0 for every level, then unlock once the user crosses
    # the level-specific threshold.
    print("\nWorkout-count gating regression…")
    gating_cases = [
        # (name, level, count, expected_blocked)
        # Round 6 (2026-05-08) bumped thresholds to 25 / 18 / 12 — fixtures
        # follow that. Round 9 (2026-05-10) kept the same thresholds.
        ("Wide Bench Press (Barbell)", "Beginner",     0,  True),
        ("Wide Bench Press (Barbell)", "Beginner",    24,  True),
        ("Wide Bench Press (Barbell)", "Beginner",    25, False),
        ("Wide Bench Press (Barbell)", "Intermediate", 0,  True),
        ("Wide Bench Press (Barbell)", "Intermediate",17,  True),
        ("Wide Bench Press (Barbell)", "Intermediate",18, False),
        ("Wide Bench Press (Barbell)", "Advanced",     0,  True),
        ("Wide Bench Press (Barbell)", "Advanced",    11,  True),
        ("Wide Bench Press (Barbell)", "Advanced",    12, False),
        ("Pendlay Row (Cable)",        "Advanced",     0,  True),
        ("Pendlay Row (Cable)",        "Advanced",    12, False),
        # block_all should never unlock with workout count
        ("Swing To Goblet Squat (Kettlebell)", "Advanced", 100, True),
        ("Pallof Press Twist",                 "Advanced", 100, True),
        # block_beginner unblocks for Intermediate even at count=0
        ("Tempo Squat", "Beginner",     0,  True),
        ("Tempo Squat", "Intermediate", 0, False),
    ]
    for name, level, count, expected in gating_cases:
        m = is_blocked_for_level(name, level, completed_workout_count=count)
        ok = m.matched == expected
        marker = "✓" if ok else "✗"
        print(f"  {marker} {name!r:50s} level={level:12s} count={count:3d} → blocked={m.matched}")
        if not ok:
            print(f"    expected blocked={expected}")
            failures += 1

    # Complex-hybrid name detection regression — block multi-movement
    # catalog-corrupted hybrids at every level (audit Round 4 fix).
    print("\nComplex-hybrid name detection regression…")
    hybrid_cases = [
        # (name, expected_blocked)
        ("Push Up - Tricep Extension", True),                # " - " sep + 2 movement nouns
        ("Push Up - Knee Tuck", True),                       # " - " sep + 2 movement nouns
        ("Romanian Deadlift Bicep Curl Kickback", True),     # 3 distinct movement nouns
        ("Curl Press Extension", True),                      # 3 distinct movement nouns
        ("Squat to Press to Curl", True),                    # 2x " to "
        ("Lunge and Twist and Reach", True),                 # 2x " and "
        ("Side-Lying-Hip-Drop-with-Leg-Lift", True),         # >=4 hyphens
        # canonical / clean names should NOT trigger
        ("Barbell Bench Press", False),
        ("Single-Arm Dumbbell Row", False),                  # 1 hyphen, qualifier
        ("T-Bar Row", False),                                # 1 hyphen, equipment
        ("Front Squat", False),
        ("Romanian Deadlift", False),
        ("Bicep Curl 21s", False),                           # 1 movement noun (curl)
        ("Kettlebell Swing", False),                         # 1 movement noun (swing)
    ]
    hybrid_failures = 0
    for name, expected in hybrid_cases:
        reason = is_complex_hybrid_name(name)
        blocked = reason is not None
        ok = blocked == expected
        marker = "✓" if ok else "✗"
        suffix = f" → {reason}" if reason else ""
        print(f"  {marker} {name!r:55s} blocked={blocked}{suffix}")
        if not ok:
            print(f"    expected blocked={expected}")
            hybrid_failures += 1
    failures += hybrid_failures

    total = len(SAMPLE_NAMES) + len(gating_cases) + len(hybrid_cases)
    if failures:
        print(f"\nFAILED: {failures}/{total} fixtures")
        return 1
    print(f"\nPASSED: {total}/{total} fixtures")
    return 0


if __name__ == "__main__":
    import sys
    sys.exit(_self_test())
