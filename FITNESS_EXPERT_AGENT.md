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
18. **Do NOT prescribe two full workouts in a single day.** `complete_2_workouts` is permanently retired (`is_active = FALSE`). Hard-day fallback = `['hit_step_goal','log_water_8','hit_protein_goal']` (canonical `v_pool_hard` fallback in `get_daily_quests` — used to be `exercise_sets_25` but that's now retired, see 20a-stuck). Multi-session rewards (if ever added) are gated behind `min_workouts ≥ 100` AND `current_streak ≥ 14`, framed as activity combos (strength + cardio), never two strength sessions.

18b. **Binary "Hit your X goal" quests (`target_value=1, target_unit='goal'`) MUST be reported to the server only when the real-world threshold is crossed — never with raw counter values.** Canonical pattern (matches `hit_step_goal` line 1820 of `Fit33/DailyQuestService.swift`):
```swift
if liveValue >= realThreshold && previousLiveValue < realThreshold {
    await reportProgress(questKey: .hitXGoal)  // increment defaults to 1
}
```
The shared `quest_templates` row carries `target_value = 1` as a binary completion STAMP, not a counter. Reporting raw counter deltas (steps, grams, etc.) via `reportProgress(questKey:, increment: rawDelta)` against a binary target instantly overshoots `target_value` on the very first signal and silently auto-completes the quest — turning a `difficulty='hard'` "Hit daily protein goal" quest into "Log any meal with any protein at all." Canonical incident: 2026-04-27, `MealService.swift::onProteinProgress(totalGrams:)` was reporting raw gram counts to `hit_protein_goal` (target_value=1), so a 20g eggs breakfast finished the user's hard quest at 7 AM. The user's dashboard surfaced "Eat 1g protein today" because `dynamicDescription` interpolated the binary template's targetValue into the copy string. Three-part fix: (a) `DailyQuestService.computeUserProteinGoal()` is the canonical local gram threshold (`max(100, weightLbs × 0.8)`, mirrors `DashboardView+Macros`); (b) `onProteinProgress(totalGrams:)` only fires `onProteinGoalHit()` when `totalGrams >= goal`; (c) `dynamicDescription` and `liveCurrentValue` for `.hitProteinGoal` both read from the canonical helper. When designing a new "Hit your X goal" quest, ALWAYS provide a paired `computeUserXGoal()` helper, ALWAYS gate the `report` call on the real threshold, ALWAYS interpolate the helper's value into copy (never `quest.targetValue`).
19. **Quest difficulty tracks experience.** `quest_templates.min_workouts` is the skill gate. Current thresholds: 10 workouts for `hit_protein_goal` / `perfect_day`; 15 for `beat_personal_record` / `beat_volume_pr` / `league_3_workouts`. (`exercise_sets_15` was 0, `exercise_sets_25` was 10, `top_3_league` was 50 — all retired; see 20a-relative + 20a-stuck.) New hard quests MUST set `min_workouts` appropriately — only low-stakes "move + log" quests use 0.
20. **`requires_context` mandatory on state-dependent quests.** Valid: `has_program`, `has_friends`, `has_challenge`, `no_friends`, `no_challenge`, `free_user`, `has_wearable`, `has_strava`, `has_whoop`, `has_oura`, `has_fitbit`, or NULL. Missing tag → handed out to users who can't complete it.
20a-anchor. **When anchoring a quest on a specific friend/opponent, prefer the engaged user — never the dormant one** (2026-04-27, paired with PE invariant 25e). Same product principle as 20a-relative ("never gated on another user"), applied to copy/anchor selection rather than completion mechanics: when the user has multiple step-challenge opponents, friend-workout candidates, or active 1v1s, the slate / brief copy MUST anchor on whichever friend is engaged with Fit33 — today's signals first, long-term engagement (`FriendRankingService.relationshipScore`) as the no-data fallback. The "Beat <Friend>" / "Do <Friend>'s workout" / "your 1v1 with <Friend>" copy only motivates when `<Friend>` is a live rival; pinning it on a dormant opponent (Abbie at 0 with no app opens this week vs Manuel at 877 right now) creates a ghost-rival anti-narrative — the user reads the goal as "the system doesn't know what's actually happening." Canonical ranker: `FriendRankingService.opponentEngagementScore`. Call sites: `DailyQuestService.friendStepChallengeSeed`, `DailyQuestService.friendWorkoutSeed`, `DailyBriefEngine.competitionFacet`. New social-anchored surfaces MUST route through this helper — never sort by `dailyTarget` / `createdAt` / `relationshipScore` in isolation.

20a-stuck. **Daily quests must have a user-takeable path to completion AFTER slot 1 (the workout) is done — never lock in pass/fail when the day's one safe workout finishes, AND never be mutually exclusive with slot 1's outcome** (2026-04-27 → 2026-04-28, migrations `20260706_retire_locked_in_set_count_quests.sql` + `20260710_retire_respect_red_recovery_quest.sql`). Same anti-pattern family as 20a (overnight-sensor passive quests) and 20a-relative (gated on another user): the user has zero deterministic levers post-slot-1, and the only "fix" violates FE invariant 18 (no two full workouts/day). Three retired examples: `exercise_sets_15` "Set Machine" (Hit 15 sets in a single workout) and `exercise_sets_25` "Volume King" (Crush 25+ sets in one session) — both are STRUCTURALLY redundant with `complete_workout` slot 1 (you cannot hit 15/25 sets without a workout) and pin at "0/N — Not yet" any time the user's actual program prescribes < N working sets (a 4-exercise legs day with 12 sets is a perfectly good workout); AND `respect_red_recovery` "Smart Rest" (Chose mobility on a red recovery day) — the verifier `verify_wearable_quests_for_today` requires `NOT EXISTS (SELECT 1 FROM workouts WHERE date = today)`, making it MUTUALLY EXCLUSIVE with `complete_workout` by construction. The first two arbitrary thresholds made the slate punish good training; the third made the slate literally contradict itself ("Crush a Workout" + "Chose mobility instead of a workout" on the same red day). `complete_workout` already captures the "did you train?" question, and `active_recovery_logged` (no band gate, no exclusion of strength workouts — universally compatible) is the canonical "did you also do something restorative?" companion that can complete on the SAME day as a strength session. When designing a new quest, ask TWO questions: "if the user's only workout today finishes at 12pm with average effort, can THIS quest still progress this afternoon by an action under the user's sole control?" AND "is the user able to complete this quest in the same day they complete slot 1, by an action under their own control?" Two nos → reject the design. Coordination check: `Fit33/DailyBriefEngine.swift::matchQuests` `.muscleGroup` / `.noWorkoutYet` / `.streakRisk` debt → workout-class quests still resolve to `complete_workout` / `complete_program_day` / `do_friend_workout` / `workout_30_min` after the retirement (the retired keys stay in the target arrays as never-fires fallback for backwards-compat); `.recoveryNeeded` debt resolves to `active_recovery_logged` / `walk_when_red` / `evening_wind_down` / `stretch_session` (Layer 7 `v_recovery_pool` in `get_daily_quests` v4 — `respect_red_recovery` was never in this pool). Server-side Layer 7 `v_pr_pool` for green-day PR elevation: `beat_volume_pr` + `beat_personal_record` remain (both are user-bar-relative and acceptable; `exercise_sets_25` removed by `is_active = FALSE`). `Lift` challenge override (DATA invariant 31) gracefully falls through via the existing `EXISTS (... AND is_active)` guard — slot 1 = `complete_workout` already covers lift-challenge participants.

20a-relative. **Daily quests must be 100% under the USER's own control today — never gated on another user's behavior** (2026-04-27, migration `20260630_retire_relative_to_others_quests.sql`). Same anti-pattern family as 20a (passive sensor-state quests): the user has no deterministic lever today, they just hope the other person under-performs. Two retired examples: `top_3_league` "Podium Finish" (verifies via `WeeklyLeagueService.standing.myRank` — a function of every other league participant's XP) and `beat_friend_steps` "Step Showdown" (verifies by comparing user's step count to a friend's via the active steps challenge — user can blow past their own step goal and still "fail" because the friend walked more). Competition belongs on the challenge / league surfaces themselves; the Daily Goals slate is for fixed user-controlled targets (`walk_*_steps`, `hit_step_goal`, `complete_workout`, etc., where the bar is a number under the user's sole control). When designing a new quest, ask: "if every other user dropped offline today, can THIS user still complete it by their own actions?" If no → reject the design. Retire by `is_active = FALSE` (keep the row for historical `user_daily_quests` resolution); never `DELETE` the template. iOS `QuestKey` enum cases stay (PE invariant 19d backwards-compat).

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

### Quality workout corpus (auto-gen training data)
27. **The auto-gen recommender only learns from "quality" workouts (score ≥ 70).** Junk 7-min / 2-exercise tap-throughs MUST never enter `collaborative_workout_data`. Canonical rubric (`Fit33/WorkoutQualityScorer.swift` mirrors `score_workout_quality` SQL RPC, migration #154 — must stay in sync if either changes — total 100 pts):
    * Duration ≥ 25 min — 20 pts
    * `completion_rate` ≥ 0.80 — 25 pts
    * ≥ 3 distinct catalog exercises — 15 pts
    * ≥ 12 working sets (warmups excluded) — 15 pts
    * ≥ 50% of weight-eligible sets have non-zero weight — 10 pts
    * Avg time-between-set-completions ≥ 20s (proxy: `duration / completedSets`) — 10 pts
    * FE invariants pass (push:pull ≤ 2:1, ≤ 2 horizontal presses) — 5 pts (lenient bonus)

    Bands: `high` (≥70 — qualifies for corpus), `medium` (40–69), `low` (<40). The first four checks sum to 75 by design — a workout MUST clear Duration + Completion + ExerciseCount + Sets to qualify; the remaining 30 pts are nuance and never carry a poor workout over the bar by themselves. New "what makes a good workout?" PRs MUST update both `WorkoutQualityScorer.swift` AND `score_workout_quality` in the SAME commit. Bodyweight + duration-based exercises auto-pass the weight-distribution check (no weight expected).

### Reversible completion (Delete Workout)
28. **The Delete Workout button on the completion screen is the one place where every server-side workout side-effect is reversed atomically.** `WorkoutManager.deleteCompletedWorkout(_:)` calls the `delete_workout_and_revert_stats` RPC (migration #155) which reverses XP, league points (+ Peak Day multiplier already baked into `awarded_points`), daily quest progress (`complete_workout` / `complete_program_day` / `do_friend_workout` / `workout_30_min` slots), `user_progress.total_xp` + `total_workouts`, AND the corpus row (FK CASCADE via #154). iOS owns conditional streak revert — only roll the streak back if THIS was the only completed workout for the calendar day (server can't decide without joining `cardio_workouts`). HKWorkout deletion is best-effort (`HealthKitManager.deleteWorkoutInWindow`) — only deletes workouts written by THIS app, identified by source bundle id. **Guard**: the Delete button is disabled when the workout has been shared with a friend (`didSendToFriend == true`) — the friend already received the data and we have no "un-share" path. New eager writes from the completion path MUST be reversed by both sides: the server-side step is added to `delete_workout_and_revert_stats` and the iOS-side counterpart is added to `WorkoutManager.deleteCompletedWorkout`.

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
