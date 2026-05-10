# Workout Quality Rubric — Canonical Source of Truth

> **Mission**: Convert autogen workout grading from vibes-based 1-10 to a deterministic, mechanical rubric. Three consumers share this doc:
> 1. **Claude (audit edge fn)** — uses rule weights to compute `overall_rating` mechanically; only classifies issues, doesn't invent vibes scores.
> 2. **Swift (`WorkoutQualityTests.swift`)** — runs the same rules deterministically against harness output. Tells us per-rule violation rates in 5 sec, no LLM needed.
> 3. **Autogen algorithm** — references rule names so every fix maps to a rule. When we drop a rule's violation rate to 0%, that rating improvement is **permanently locked in**.

---

## Grand formula (Claude + Swift agree)

```
mechanical_rating = clamp(10 - Σ(rule_weight × severity_multiplier), 1, 10)
overall_rating    = clamp(mechanical_rating + subjective_adjustment, 1, 10)
```

- `severity_multiplier`: `critical = 1.0`, `major = 0.6`, `minor = 0.3`
- `subjective_adjustment ∈ [-1, +1]` — Claude only. Captures gestalt feedback the rubric misses. If `|adj| > 0.5`, Claude MUST cite a rule that's missing.
- A workout with **0 issues** earns `overall_rating = 10`. The bar for a 9 is **≤ 1 minor violation OR a subjective bonus**.

### Target trajectory
| Round | Avg issues/workout | Mechanical rating | Notes |
|---|---:|---:|---|
| R10 (baseline) | 3.67 | ~4.3 (current) | What we're improving from |
| R12 target | 2.0 | ~6.5 | Top-3 rules fixed mechanically |
| R14 target | 1.0 | ~8.0 | Top-7 rules fixed |
| R16 target | 0.5 | ~9.0 | Cheat-code achieved |

---

## The 13 rules

> Each rule has: `name` (Claude category enum), `weight`, `definition` (mechanical), `swift_check` (where Swift verifies), `algo_fix` (where the autogen enforces).

### Rule 1 · `injury_unsafe` (weight 4.0, max stakes)
- **Definition**: Exercise contains a movement on the universal-block list (good morning, upright row, behind-neck press, behind-neck pulldown, guillotine press, plyometric for age ≥ 60), OR violates a user-specific injury constraint (`User.injuries`).
- **Swift check**: `WorkoutQualityTests.testNoUniversalBlockedExercises` + `testRespectsUserInjuries`
- **Algo fix**: Hard filter in `SmartExerciseSelectionEngine.assessExercisePracticality` — must return `false`. Currently inconsistent (only some banned names caught).

### Rule 2 · `equipment_mismatch` (weight 3.0, critical when broken)
- **Definition**: Exercise requires equipment the user doesn't have. Case-insensitive comparison against `User.equipmentList`. `Bodyweight` always counts as available.
- **Swift check**: `WorkoutQualityTests.testAllExercisesHaveAvailableEquipment`
- **Algo fix**: Existing equipment filter in `WorkoutGeneratorService.generateFromCoreData`. Bug: catalog has case-inconsistent equipment strings (mostly fixed in R10 catalog cleanup pass).

### Rule 3 · `risky_for_level` (weight 3.0)
- **Definition**: Exercise on the level-block list AND user level matches the block (e.g. Olympic lifts for Beginner; max-effort singles for Beginner; certain specialty variants).
- **Swift check**: `WorkoutQualityTests.testNoOlympicLiftsForBeginners` + `testNoMaxEffortForBeginners`
- **Algo fix**: Beginner-safety filter — already exists for Olympic lifts but not max-effort singles.

### Rule 4 · `specialty_variant_for_level` (weight 2.0)
- **Definition**: An exercise from `SpecialtyVariantFilter.patterns` is present AND its severity band excludes the user's level OR the user's `completedWorkoutCount` is below the unlock threshold.
- **Swift check**: `WorkoutQualityTests.testNoSpecialtyVariantsBelowThreshold`
- **Algo fix**: `SpecialtyVariantFilter.evaluate` — extended to ~30 patterns in R10. Still surfacing 49 violations because patterns are incomplete and `userAge≥60` block was only added to specialty patterns, not all.

### Rule 5 · `beginner_complexity` (weight 2.0)
- **Definition**: User is Beginner AND workout contains an exercise where `complexity_rating ≥ 4/5` OR name matches an "advanced-only" allow-list (e.g. handstand, muscle-up, pistol squat, single-arm deadlift).
- **Swift check**: `WorkoutQualityTests.testBeginnerExerciseComplexity`
- **Algo fix**: Add `complexity_rating ≤ 3` gate in selection engine when `level == Beginner`. Not currently enforced.

### Rule 6 · `missing_balance_slot` (weight 2.0)
- **Definition**: Mandatory balance slot is missing for the workout type:
  - Push day → must contain ≥ 1 rear-delt or upper-back exercise
  - Leg day → must contain ≥ 1 core/unilateral exercise
  - Full-body → must touch ≥ 4 of {push, pull, squat, hinge, core}
- **Swift check**: `WorkoutQualityTests.testBalanceSlotPerWorkoutType`
- **Algo fix**: `WorkoutComboRules.applyBalanceSlot` — currently advisory; promote to mandatory.

### Rule 7 · `wrong_split_for_days` (weight 2.0)
- **Definition**: User's chosen split doesn't match their days/week setting (e.g. PPL on 3 days/week, or full-body on 6 days/week).
- **Swift check**: `WorkoutQualityTests.testSplitMatchesDaysPerWeek`
- **Algo fix**: `WorkoutSuggestionEngine.chooseSplit` already maps this; rule documents the constraint for catch-all.

### Rule 8 · `compound_after_isolation` (weight 1.5)
- **Definition**: At any position `i`, if exercise at `i` is isolation (`is_compound = false`) and any exercise at position `j > i` is compound (`is_compound = true`), this is a violation.
- **Swift check**: `WorkoutQualityTests.testCompoundsBeforeIsolation`
- **Algo fix**: `WorkoutGeneratorService.sortExercisesStrategically` — current `Step 4` handles unilateral; add `Step 5` for strict compound-first sort.

### Rule 9 · `obscure_exercise` (weight 1.0, high volume)
- **Definition**: Exercise's `popularity_score < 0.25` (or absent) AND a same-muscle canonical alternative exists. The "obscure_exercises" filter in `SmartExerciseSelectionEngine` already catches some; rule catches the rest.
- **Swift check**: `WorkoutQualityTests.testNoObscureWhenCanonicalExists`
- **Algo fix**: Tighten `SmartExerciseSelectionEngine.obscureExercises` + bump priority score of foundational variants in `FoundationalExerciseDatabase`.

### Rule 10 · `redundant_movement_pattern` (weight 1.0)
- **Definition**: Same primary movement pattern appears > N times: bench-pattern > 2, hinge-pattern > 1, squat-pattern > 2, row-pattern > 2, curl-pattern > 2 in a single workout.
- **Swift check**: `WorkoutQualityTests.testMovementPatternCaps`
- **Algo fix**: `SmartExercisePairingEngine.maxPerPattern` — exists; tighten enforcement.

### Rule 11 · `volume_imbalance` (weight 1.0)
- **Definition**: Within a workout, total sets per muscle group differ by > 2× between most-trained and least-trained primary muscle (excluding intentional focus muscles).
- **Swift check**: `WorkoutQualityTests.testVolumeBalancePerMuscle`
- **Algo fix**: `WorkoutComboRules.balanceVolume` — new step; not currently enforced.

### Rule 12 · `wrong_rep_range_for_goal` (weight 1.0)
- **Definition**: User's `fitnessGoal` doesn't match suggested rep range:
  - Build Muscle → 6-12 reps
  - Build Strength → 3-6 reps
  - Lose Weight / Improve Health → 8-15 reps
  - Improve Endurance → 12-20 reps
- **Swift check**: `WorkoutQualityTests.testRepRangePerGoal`
- **Algo fix**: `WorkoutGeneratorService.recommendedReps` — exists; verify goal mapping.

### Rule 13 · `other` (weight 1.0, catch-all)
- **Definition**: Anything Claude flags that doesn't fit categories 1-12. Should appear < 5% of total issues. If > 5%, we're missing a rule — add it.
- **Swift check**: N/A (Claude-only)
- **Algo fix**: When `other` count crosses 5%, audit the descriptions, define a 14th rule.

---

## Subjective adjustment (Claude only)

After computing the mechanical rating, Claude may apply `subjective_adjustment ∈ [-1.0, +1.0]`:

- **Positive** (`+0.5 to +1.0`): workout is *exceptionally* well-paired, novel within constraints, or perfectly motivating for the user's goal.
- **Negative** (`-0.5 to -1.0`): workout passes every rule but *something* feels wrong (e.g. ordering is technically valid but unintuitive). Claude MUST cite the qualitative reason.
- **Zero**: rubric captured everything (this should be the default).

If `|subjective_adjustment| > 0.5`, Claude includes the reason in `subjective_reason` field. If we see the same `subjective_reason` more than 3 times across an audit, that's evidence a 14th rule is needed.

---

## Mechanical determinism contract

If the same workout JSON is graded twice with the same Claude model + temperature 0, the mechanical rating MUST be identical (Claude's issue classification might shift slightly between calls — that's the only stochastic source). `WorkoutQualityTests.swift` is fully deterministic and serves as the regression baseline. If Claude's rating drifts > 1 point from Swift's mechanical floor on the same workout, that's a calibration bug.

---

## Owners & sync rules

- **Owner**: Quality + Fitness Expert agents jointly. Rule changes require both to sign off.
- **Source of truth**: this file. Embedded into:
  - `supabase/functions/audit-autogen-workout/index.ts` (SYSTEM_PROMPT)
  - `Fit33Tests/WorkoutQualityTests.swift` (one XCTest function per rule)
  - `FITNESS_EXPERT_AGENT.md` invariant #5 references this doc.
- **When you change a rule**: bump rule version (append `// v2: changed weight 2.0→3.0 2026-05-10`), mirror to the two consumer files in the SAME PR. CI will fail if the SYSTEM_PROMPT version drifts from this file's hash.

---

## Out of scope (NOT in the rubric)

- Subjective novelty / variety / motivation — captured only by `subjective_adjustment`.
- Long-term progression across multiple workouts — that's `MultiDayProgressionTests`, separate file.
- Catalog-data correctness — that's the `audit_exercise_catalog.py` pipeline.

Anything that becomes mechanical → promote to a rule. Anything subjective → stays in adjustment.
