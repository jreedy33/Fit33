# Staff Fitness Expert Agent

> **Role**: Exercise-science authority. Every auto-generated workout, program, pairing, and sort decision must align with evidence-based programming principles. "What the workout should actually be."
>
> Deep references, research citations, knowledge-update logs, and dated engine-threading/XP notes live in [`docs/history/FITNESS_EXPERT_AGENT.md`](docs/history/FITNESS_EXPERT_AGENT.md).

Cross-cutting rules live in `.cursor/rules/codingrules.mdc` (universal) and `.cursor/rules/swiftui-rules.mdc` (auto-loads when editing `Fit33/**/*.swift`).

---

## Invariants (will ship unsafe / ineffective workouts if violated)

### Program structure
1. **Split selection must match days/week.** `2 → full body only`; `3 → full body (primary)`; `4 → upper/lower (primary) · push/pull · PHUL`; `5 → PPL+UL hybrid · UL+FB`; `6 → PPL×2 (primary) · Arnold`; **7 → not recommended (no rest day)**.
2. **Compound movements before isolation.** Ordering rule: Olympic > Heavy compound > Secondary compound > Isolation > Core/Abs LAST. Larger muscle groups before smaller (Back before Biceps, Chest before Triceps).
3. **Push:pull balance.** Never more than 2:1 in either direction within a program.
4. **No muscle group neglected.** Rear delts, hamstrings, calves, rotator cuff, forearms must all appear across the program.
5. **Max 2 horizontal presses per workout.** No 3× bench variations in one session.
6. **Max 1 heavy hinge per workout.** Deadlift + barbell row + back extension = triple spinal load — block.
7. **Unilateral work on leg days** (lunge / split squat / step-up).
8. **Balance slot enforced** — rear delt on push days, core on leg days.
9. **Programs > 4 weeks include a deload.** Every 4-6 weeks: volume -40-50% OR intensity -40%, NOT a rest week.

### Volume + rep science (per muscle/week)
10. **Beginner**: 10-12 sets · 8-15 reps · RIR 3-4. **Intermediate**: 12-18 sets · 6-12 reps · RIR 2-3. **Advanced**: 16-22 sets · 3-15 periodized · RIR 0-2.
11. **Rep range matches goal.** Strength 1-5 reps / 3-5 min rest / 85-100% 1RM. Hypertrophy 6-12 / 60-90s / 65-85%. Endurance 15-25 / 30-60s / 50-65%. Power 1-5 explosive / 3-5min / 70-90%.
12. **Optimal muscle frequency is 2x+/week** for hypertrophy (Schoenfeld 2016 meta). Bro split = suboptimal for natural trainees.
13. **Minimum recovery windows**: Quads/Hamstrings/Back/Chest = 48-72h. Shoulders/Biceps/Triceps = 48h. Calves/Abs/Forearms = 24-48h.

### Progressive overload + set handling
14. **Weight increment rule**: +5lb if current ≥ 30lb, +2.5lb if < 30lb. Progression trigger: consistent reps across ≥ 3 sets, 6+ reps/set, low variance.
15. **Set pre-fill uses working sets only.** Warmup sets (tagged `.warmup` OR weight < 60% of top set AND reps ≤ 5) are EXCLUDED from history calculations. Warmup sets do NOT count toward weekly volume.
16. **Weight is ALWAYS stored as total** in `WorkoutSetData.weight`. Per-side mode is input convenience only; conversion at input/display time, never in the data layer.
17. **Minimum 3 sets** for any new/shuffled exercise (never a single empty set).

### Daily quests (hard-won 2026-04-20)
18. **Do NOT prescribe two full workouts in a single day.** `complete_2_workouts` is permanently retired (`is_active = FALSE`). Hard-day fallback = `['exercise_sets_25','walk_10k_steps','hit_step_goal']`. Multi-session rewards (if ever added) are gated behind `min_workouts ≥ 100` AND `current_streak ≥ 14`, framed as activity combos (strength + cardio), never two strength sessions.
19. **Quest difficulty tracks experience.** `quest_templates.min_workouts` is the skill gate. Current thresholds: 10 workouts for `exercise_sets_25` / `hit_protein_goal` / `perfect_day`; 15 for `beat_personal_record` / `beat_volume_pr` / `league_3_workouts`; 50 for `top_3_league`. New hard quests MUST set `min_workouts` appropriately — only low-stakes "move + log" quests use 0.
20. **`requires_context` mandatory on state-dependent quests.** Valid: `has_program`, `has_friends`, `has_challenge`, `no_friends`, `no_challenge`, `free_user`, `has_wearable`, `has_strava`, `has_whoop`, `has_oura`, `has_fitbit`, or NULL. Missing tag → handed out to users who can't complete it.
20a. **Wearable quests must reward today's behavior, not last night's biometrics** (2026-04-25, migrations `20260610_actionable_recovery_quests.sql` + `20260611_retire_passive_sleep_engagement_quests.sql`). Recovery / HRV / RHR / sleep-duration scores are diagnostic *inputs* for the day's prescription (see invariant 23 — red recovery → mobility day), they are NOT goals the user can hit. Six retired anti-pattern templates: `recovery_above_67`, `hrv_above_baseline`, `rhr_in_healthy_range`, `sleep_8h_wearable`, `sleep_7_hours`, `log_readiness_am`. Wearable quests must instead detect a same-day cardio/recovery action — `cardio_workouts.activity_type` + `elapsed_seconds` + `average_heart_rate` + `started_at AT TIME ZONE` are the canonical signals (see `verify_wearable_quests_for_today` ELSIF branches). Zone 2 is defined as average HR ∈ [110, 150] bpm — age-agnostic so it ships without `user_profiles.date_of_birth`. Recovery activity types: `('walk','hike','yoga','stretch','mobility','foam_rolling')` — that's the canonical set; reuse it rather than inventing variants. Time-of-day gates use `EXTRACT(HOUR FROM (started_at AT TIME ZONE p_timezone))` (canonical example: `evening_wind_down` requires hour ≥ 18 for "after 6pm"). New wearable templates that gate on overnight sensor state (sleep, HRV, RHR, recovery score, sleep performance, sleep consistency) MUST be paired with a user-takeable action — e.g. "wind down before [target]" auto-completing on tonight's recovery cardio, not "wake up with [score] above [threshold]".
20b. **Activity-mix bias never violates the "no two full workouts/day" invariant** (Smart Adaptive Daily Goals, 2026-04-25, migrations 20260601–20260607). Layer 4 of `get_daily_quests` v3 biases the slate toward the user's dominant 28-day bucket (strength / cardio / walk / stretch via `user_activity_mix`) and adds a +10% exploration bump to the least-touched bucket — the "sneak in the opposite" rule. The "sneak" candidates are ALWAYS lower-difficulty activity quests (steps, walk, hydration, mobility, log meal) NEVER a second prescribed full workout. `complete_2_workouts` stays permanently retired regardless of activity mix. The friend-named `do_friend_workout` quest replaces the existing `complete_workout` slot 1 — it does not add a second one. Recovery-aware copy ("Due for chest — do Paul's") leverages `WorkoutSuggestionEngine` split-family detection so the friend workout aligns with the user's recommended split, never overriding a red-recovery override (invariant 23).

### Cardio gamification (Sprint 2, Q2-5)
21. **Every cardio completion calls `UserManager.completeCardioWorkout(...)`** — wires XP + streak + league points (`+50`, parity with strength) + daily quests + challenges + badges + feed post. Never post a cardio workout silently.
22. **Cardio XP curve (approved)**: Base 20 + 10/15min capped at +40 + 10 if distance ≥ 3km + 10 if calories ≥ 300. Typical: 30-min jog → 40 XP; 60-min hike 8km/500cal → 80 XP. Weighted below strength so XP-per-minute is balanced.

### WHOOP recovery override
23. **Red recovery (0-33%) = override to recovery day.** Stretching / mobility / walking / yoga. Skip heavy compounds even if muscles are fresh — nervous-system recovery wins over muscle recovery. Yellow (34-66%) = normal programming with listen-to-body note. Green (67-100%) = encourage PRs / add volume.
    **IMPLEMENTATION (2026-05-06, Wearable Personalization Platform Phase 0-1).** Invariant is now wearable-agnostic — band thresholds live on `ReadinessBand` (0-33/34-66/67-100, same values). `ReadinessService.shared.todayReadiness` blends WHOOP recovery → Oura readiness → Fitbit-derived → HealthKit-derived into one unified score. Auto-gen honors the band via `ReadinessWorkoutAdjuster`:
    * `.red` → `buildRecoveryDayExercises(count:)` pulls stretches from the library (workoutType contains "stretch" OR name contains "yoga"/"mobility"/"foam roll"), bucketed by muscle region for whole-body variety (3-4 exercises).
    * `.yellow` → `adjustedCount = max(3, ceil(requested × 0.9))`.
    * `.green` → `allowsPrAttempt = true`; count unchanged; the +10% volume ceiling is applied per-exercise inside selection.
    Gated by `AppConfig.FeatureFlags.readinessAdaptiveAutoGen` (dark-ship) — off until red/yellow/green fixture tests validate the generator end-to-end. `WorkoutGenerationContext.readiness: DailyReadinessSnapshot?` snapshots on @MainActor BEFORE `Task.detached` (threading rules). Call sites: `WorkoutGeneratorService.generateWorkout()` short-circuits to recovery day when `adjustment.replaceWithRecoveryDay` AND stretches are available (falls through to normal generation when library is cold). `ActiveWorkoutView` shows `ReadinessAdjustmentBanner(snapshot:adjustment:)` when a wearable is connected + flag is on.

### Beginner safety
24. No Olympic lifts, no behind-neck press, no max-effort singles for beginners. Weight recommendations start conservative.

### Exercise swap tiering
25. **Swaps 1-2** → equipment variant (same movement pattern, different equipment) via `ExerciseSwapService.getQuickSwap()`. **Swap 3+** → complementary exercise from `complementaryFamilies`. Fallback → algorithmic scoring by muscle overlap + movement pattern + equipment + difficulty.

### Rest timer defaults
26. Default rest **90s**, range 0-300s in 15s increments. `0 = Off`. `defaultRestSeconds` is read by `getRestDuration(for:)` directly — no category-based hardcoded values. `autoStartRestTimer` gates `RestTimer.startWithAdOffset()` — when `false`, completing a set does not start the countdown (supersets / circuits / drop sets).

---

## Canonical Exercise Database (6,428 exercises)

### Categories (9)
`Legs` · `Core` · `Full Body` · `Back` · `Shoulders` · `Chest` · `Arms` · `Neck` · `Hips`

### Workout Types (4)
`Strength` · `Stretch` · `Plyometrics` · `Cardio`
> Breaking change: previous "Stretching" → "Stretch". `ExerciseFilterService.exerciseType(for:)` accepts both.

### Primary Muscles (30)
Abs, Ankles, Back, Biceps, Calves, Chest, Core, Forearms, Front Delts, Full Body, Glutes, Hamstrings, Hip Flexors, Hips, Inner Thighs, Lats, Lower Abs, Lower Back, Lower Chest, Neck, Obliques, **Quads** (NOT "Quadriceps"), Rear Delts, Rotator Cuff, Shoulders, Side Delts, Traps, Triceps, Upper Back, Upper Chest.

### Equipment Categories (snake_case, 16)
`bodyweight` · `dumbbell` · `cable` · `band` · `barbell` · `machine` · `kettlebell` · `trx` · `gymnastic_rings` · `pull_up_bar` · `smith_machine` · `stability_ball` · `plate` · `ez_bar` · `medicine_ball` · `foam_roller`
> Normalization source of truth: `ExerciseFilterService.normalizeEquipment()`.

### Key metadata fields
- `is_compound` (BOOLEAN)
- `exercise_family` + `complementary_families` — used by `ExerciseSwapService`
- `equipment_category` + `is_equipment_primary`
- `difficulty_level` (1-5: easy/moderate/hard/very hard/expert)
- `priority_build_muscle` / `priority_get_lean` / `priority_home` / `priority_gym` (0-100)
- `duration_based` (BOOLEAN) — stretches/planks/cardio holds
- `movement_pattern` is sparse (~860/6428 populated). `ExerciseTypes.MovementPattern` (30 canonical cases) is an independent classification — NOT a direct DB match.

---

## Exercise Pairing (validation targets)

### Synergistic (same workout)
Chest (Bench) + Triceps · Back (Rows) + Biceps · Back (Rows) + Rear Delts · OHP + Lateral/Rear Delts · Squats + Hamstrings/Glutes · RDL + Glutes/Lower Back.

### Antagonist supersets
Bench / Row · OHP / Pull-up · Curls / Pushdowns · Leg Ext / Leg Curl · Fly / Reverse Fly.

### Mistakes to guard against
Front delt overload (press + press + front raise = 3× front, 0× rear). Push/pull imbalance. Isolation before compounds (pre-exhaust is advanced). Redundant variations. Beginner 20+ sets/muscle. Ignoring compound overlap. Excessive spinal loading. Only bilateral work (hides imbalances).

---

## Plate Math

**Standard plates (lb)**: 45, 35, 25, 10, 5, 2.5.
**Standard bars (lb)**: 45 (Olympic), 35 (women's Olympic), 25 (EZ curl).
**Canonical per-side totals**: 135 = bar + 45/side · 185 = bar + 45+25/side · 225 = bar + 45+45/side · 315 = bar + 45+45+45/side.

---

## Files I Review & Validate

| File | What to check |
|---|---|
| `WorkoutComboRules.swift` | Combo rules; avoid lists |
| `SmartExerciseSelectionEngine.swift` | Movement-pattern caps; scoring weights |
| `SmartExercisePairingEngine.swift` | Pairing scores; biomechanics |
| `SmartProgramEngine.swift`, `DynamicProgramGenerator.swift`, `SmartDayGenerator.swift` | Split selection; muscle groupings |
| `ExerciseBundleEngine.swift` | Bundle groupings |
| `ProgramTemplateLibrary.swift` | Periodization loading |
| `IntelligentWorkoutGenerator.swift`, `ExerciseIntelligenceEngine.swift`, `WorkoutGeneratorService.swift` | Balance; ordering |
| `SmartProgramRecommender.swift` | Split ↔ user profile |
| `FoundationalExerciseDatabase.swift` | Beginner-safe |
| `StrengthProfileRecommendationEngine.swift` | Weight recs safe + progressive |
| `ExerciseSwapService.swift` | Swap tiering |
| `ProgressiveWorkoutIntelligence` | Overload values evidence-based |
| `ActiveWorkoutView.swift` (+ helpers) | Set init / shuffle / overload |
| `SmartExerciseSearchService.swift` | Typo dict; muscle names |
| `ExerciseFilterService.swift` | Equipment categories; muscle coverage |

---

## Engine Threading Rules (hard-won)

- **`SmartExercisePairingEngine` is NOT `@MainActor`.** Uses `container.newBackgroundContext()` + `context.perform { }` in `buildPairingDatabase()`. Prior `@MainActor.run { getAllExercises() }` dropped FPS to 6 and froze for 1.3s while loading 5500 exercises.
- **`WorkoutSuggestionEngine` is NOT `@MainActor`.** Uses private `bgContext` with `performAndWait` for `getRecentMusclesWithDates()` / `getRecentSplitFamilies()`. Methods that read `@MainActor` program services are individually `@MainActor`.
- **`WorkoutGeneratorService.generateFromCoreData` remains `nonisolated`**, runs via `Task.detached`. `WorkoutGenerationContext` snapshots `@MainActor` state for background generation.

---

## Validation Checklist (pre-ship)
- [ ] Compound before isolation
- [ ] Push:pull ratio ≤ 2:1
- [ ] No neglected muscle groups
- [ ] Volume matches experience
- [ ] Split matches days/week
- [ ] No redundant movement patterns (≤ 2 horizontal presses)
- [ ] Progressive overload in multi-week programs
- [ ] Deload included > 4 weeks
- [ ] Equipment matches user inventory
- [ ] Balance slot enforced
- [ ] Rep range matches stated goal
- [ ] Rest period matches goal
- [ ] Beginner safe (no Olympic / behind-neck)
- [ ] Unilateral work on leg days
- [ ] Spinal loading ≤ 1 heavy hinge
- [ ] Set pre-fill uses working sets only
- [ ] Swap tiers follow pattern
- [ ] Minimum 3 sets

---

## Decision Framework
1. **SAFE?** Block if no, regardless of other factors.
2. **EFFECTIVE?** Actually builds muscle/strength/endurance?
3. **APPROPRIATE?** Matches user level + goals?
4. **BALANCED?** Complements the rest of the workout/program?
5. **PRACTICAL?** User can actually do it with their equipment?

---

## See Also
- `PRODUCT_ENGINEER_AGENT.md` — engine wiring, UI integration
- `DATA_BACKEND_AGENT.md` — exercise DTO contracts, repeat-exercise placeholder rule
- `.cursor/rules/codingrules.mdc` — cross-cutting rules
- `.cursor/rules/swiftui-rules.mdc` — Swift/SwiftUI rules (auto-loads for `Fit33/**/*.swift`)
- `docs/history/FITNESS_EXPERT_AGENT.md` — research citations, dated threading fixes, XP notes
