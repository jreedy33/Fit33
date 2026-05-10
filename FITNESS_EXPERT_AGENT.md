# Staff Fitness Expert Agent

> **Role**: Exercise-science authority. Every auto-generated workout, program, pairing, and sort decision must align with evidence-based programming principles. "What the workout should actually be."
>
> Deep references, research citations, knowledge-update logs, and dated engine-threading/XP notes live in `[docs/history/FITNESS_EXPERT_AGENT.md](docs/history/FITNESS_EXPERT_AGENT.md)`.

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

1. **Beginner**: 10-12 sets · 8-15 reps · RIR 3-4. **Intermediate**: 12-18 sets · 6-12 reps · RIR 2-3. **Advanced**: 16-22 sets · 3-15 periodized · RIR 0-2.
2. **Rep range matches goal.** Strength 1-5 reps / 3-5 min rest / 85-100% 1RM. Hypertrophy 6-12 / 60-90s / 65-85%. Endurance 15-25 / 30-60s / 50-65%. Power 1-5 explosive / 3-5min / 70-90%.
3. **Optimal muscle frequency is 2x+/week** for hypertrophy (Schoenfeld 2016 meta). Bro split = suboptimal for natural trainees.
4. **Minimum recovery windows**: Quads/Hamstrings/Back/Chest = 48-72h. Shoulders/Biceps/Triceps = 48h. Calves/Abs/Forearms = 24-48h.

### Progressive overload + set handling

1. **Weight increment rule**: +5lb if current ≥ 30lb, +2.5lb if < 30lb. Progression trigger: consistent reps across ≥ 3 sets, 6+ reps/set, low variance.
2. **Set pre-fill uses working sets only.** Warmup sets (tagged `.warmup` OR weight < 60% of top set AND reps ≤ 5) are EXCLUDED from history calculations. Warmup sets do NOT count toward weekly volume.
3. **Weight is ALWAYS stored as total** in `WorkoutSetData.weight`. Per-side mode is input convenience only; conversion at input/display time, never in the data layer.
4. **Minimum 3 sets** for any new/shuffled exercise (never a single empty set).

### Daily quests (hard-won 2026-04-20)

1. **Do NOT prescribe two full workouts in a single day.** `complete_2_workouts` is permanently retired (`is_active = FALSE`). Hard-day fallback = `['hit_step_goal','log_water_8','hit_protein_goal']` (canonical `v_pool_hard` fallback in `get_daily_quests` — used to be `exercise_sets_25` but that's now retired, see 20a-stuck). Multi-session rewards (if ever added) are gated behind `min_workouts ≥ 100` AND `current_streak ≥ 14`, framed as activity combos (strength + cardio), never two strength sessions.

18b. **Binary "Hit your X goal" quests (`target_value=1, target_unit='goal'`) MUST be reported to the server only when the real-world threshold is crossed — never with raw counter values.** Canonical pattern (matches `hit_step_goal` line 1820 of `Fit33/DailyQuestService.swift`):

```swift
if liveValue >= realThreshold && previousLiveValue < realThreshold {
    await reportProgress(questKey: .hitXGoal)  // increment defaults to 1
}
```

The shared `quest_templates` row carries `target_value = 1` as a binary completion STAMP, not a counter. Reporting raw counter deltas (steps, grams, etc.) via `reportProgress(questKey:, increment: rawDelta)` against a binary target instantly overshoots `target_value` on the very first signal and silently auto-completes the quest — turning a `difficulty='hard'` "Hit daily protein goal" quest into "Log any meal with any protein at all." Canonical incident: 2026-04-27, `MealService.swift::onProteinProgress(totalGrams:)` was reporting raw gram counts to `hit_protein_goal` (target_value=1), so a 20g eggs breakfast finished the user's hard quest at 7 AM. The user's dashboard surfaced "Eat 1g protein today" because `dynamicDescription` interpolated the binary template's targetValue into the copy string. Three-part fix: (a) `DailyQuestService.computeUserProteinGoal()` is the canonical local gram threshold (`max(100, weightLbs × 0.8)`, mirrors `DashboardView+Macros`); (b) `onProteinProgress(totalGrams:)` only fires `onProteinGoalHit()` when `totalGrams >= goal`; (c) `dynamicDescription` and `liveCurrentValue` for `.hitProteinGoal` both read from the canonical helper. When designing a new "Hit your X goal" quest, ALWAYS provide a paired `computeUserXGoal()` helper, ALWAYS gate the `report` call on the real threshold, ALWAYS interpolate the helper's value into copy (never `quest.targetValue`).
19. **Quest difficulty tracks experience.** `quest_templates.min_workouts` is the skill gate. Current thresholds: 10 workouts for `hit_protein_goal` / `perfect_day`; 15 for `beat_personal_record` / `beat_volume_pr` / `league_3_workouts`. (`exercise_sets_15` was 0, `exercise_sets_25` was 10, `top_3_league` was 50 — all retired; see 20a-relative + 20a-stuck.) New hard quests MUST set `min_workouts` appropriately — only low-stakes "move + log" quests use 0.
20. `**requires_context` mandatory on state-dependent quests.** Valid: `has_program`, `has_friends`, `has_challenge`, `no_friends`, `no_challenge`, `free_user`, `has_wearable`, `has_strava`, `has_whoop`, `has_oura`, `has_fitbit`, or NULL. Missing tag → handed out to users who can't complete it.
20a-anchor. **When anchoring a quest on a specific friend/opponent, prefer the engaged user — never the dormant one** (2026-04-27, paired with PE invariant 25e). Same product principle as 20a-relative ("never gated on another user"), applied to copy/anchor selection rather than completion mechanics: when the user has multiple step-challenge opponents, friend-workout candidates, or active 1v1s, the slate / brief copy MUST anchor on whichever friend is engaged with Fit33 — today's signals first, long-term engagement (`FriendRankingService.relationshipScore`) as the no-data fallback. The "Beat " / "Do 's workout" / "your 1v1 with " copy only motivates when `<Friend>` is a live rival; pinning it on a dormant opponent (Abbie at 0 with no app opens this week vs Manuel at 877 right now) creates a ghost-rival anti-narrative — the user reads the goal as "the system doesn't know what's actually happening." Canonical ranker: `FriendRankingService.opponentEngagementScore`. Call sites: `DailyQuestService.friendStepChallengeSeed`, `DailyQuestService.friendWorkoutSeed`, `DailyBriefEngine.competitionFacet`. New social-anchored surfaces MUST route through this helper — never sort by `dailyTarget` / `createdAt` / `relationshipScore` in isolation.

20a-stuck. **Daily quests must have a user-takeable path to completion AFTER slot 1 (the workout) is done — never lock in pass/fail when the day's one safe workout finishes, AND never be mutually exclusive with slot 1's outcome** (2026-04-27 → 2026-04-28, migrations `20260706_retire_locked_in_set_count_quests.sql` + `20260710_retire_respect_red_recovery_quest.sql`). Same anti-pattern family as 20a (overnight-sensor passive quests) and 20a-relative (gated on another user): the user has zero deterministic levers post-slot-1, and the only "fix" violates FE invariant 18 (no two full workouts/day). Three retired examples: `exercise_sets_15` "Set Machine" (Hit 15 sets in a single workout) and `exercise_sets_25` "Volume King" (Crush 25+ sets in one session) — both are STRUCTURALLY redundant with `complete_workout` slot 1 (you cannot hit 15/25 sets without a workout) and pin at "0/N — Not yet" any time the user's actual program prescribes < N working sets (a 4-exercise legs day with 12 sets is a perfectly good workout); AND `respect_red_recovery` "Smart Rest" (Chose mobility on a red recovery day) — the verifier `verify_wearable_quests_for_today` requires `NOT EXISTS (SELECT 1 FROM workouts WHERE date = today)`, making it MUTUALLY EXCLUSIVE with `complete_workout` by construction. The first two arbitrary thresholds made the slate punish good training; the third made the slate literally contradict itself ("Crush a Workout" + "Chose mobility instead of a workout" on the same red day). `complete_workout` already captures the "did you train?" question, and `active_recovery_logged` (no band gate, no exclusion of strength workouts — universally compatible) is the canonical "did you also do something restorative?" companion that can complete on the SAME day as a strength session. When designing a new quest, ask TWO questions: "if the user's only workout today finishes at 12pm with average effort, can THIS quest still progress this afternoon by an action under the user's sole control?" AND "is the user able to complete this quest in the same day they complete slot 1, by an action under their own control?" Two nos → reject the design. Coordination check: `Fit33/DailyBriefEngine.swift::matchQuests` `.muscleGroup` / `.noWorkoutYet` / `.streakRisk` debt → workout-class quests still resolve to `complete_workout` / `complete_program_day` / `do_friend_workout` / `workout_30_min` after the retirement (the retired keys stay in the target arrays as never-fires fallback for backwards-compat); `.recoveryNeeded` debt resolves to `active_recovery_logged` / `walk_when_red` / `evening_wind_down` / `stretch_session` (Layer 7 `v_recovery_pool` in `get_daily_quests` v4 — `respect_red_recovery` was never in this pool). Server-side Layer 7 `v_pr_pool` for green-day PR elevation: `beat_volume_pr` + `beat_personal_record` remain (both are user-bar-relative and acceptable; `exercise_sets_25` removed by `is_active = FALSE`). `Lift` challenge override (DATA invariant 31) gracefully falls through via the existing `EXISTS (... AND is_active)` guard — slot 1 = `complete_workout` already covers lift-challenge participants.

20a-relative. **Daily quests must be 100% under the USER's own control today — never gated on another user's behavior** (2026-04-27, migration `20260630_retire_relative_to_others_quests.sql`). Same anti-pattern family as 20a (passive sensor-state quests): the user has no deterministic lever today, they just hope the other person under-performs. Two retired examples: `top_3_league` "Podium Finish" (verifies via `WeeklyLeagueService.standing.myRank` — a function of every other league participant's XP) and `beat_friend_steps` "Step Showdown" (verifies by comparing user's step count to a friend's via the active steps challenge — user can blow past their own step goal and still "fail" because the friend walked more). Competition belongs on the challenge / league surfaces themselves; the Daily Goals slate is for fixed user-controlled targets (`walk_*_steps`, `hit_step_goal`, `complete_workout`, etc., where the bar is a number under the user's sole control). When designing a new quest, ask: "if every other user dropped offline today, can THIS user still complete it by their own actions?" If no → reject the design. Retire by `is_active = FALSE` (keep the row for historical `user_daily_quests` resolution); never `DELETE` the template. iOS `QuestKey` enum cases stay (PE invariant 19d backwards-compat).

20a. **Wearable quests must reward today's behavior, not last night's biometrics** (2026-04-25, migrations `20260610_actionable_recovery_quests.sql` + `20260611_retire_passive_sleep_engagement_quests.sql`). Recovery / HRV / RHR / sleep-duration scores are diagnostic *inputs* for the day's prescription (see invariant 23 — red recovery → mobility day), they are NOT goals the user can hit. Six retired anti-pattern templates: `recovery_above_67`, `hrv_above_baseline`, `rhr_in_healthy_range`, `sleep_8h_wearable`, `sleep_7_hours`, `log_readiness_am`. Wearable quests must instead detect a same-day cardio/recovery action — `cardio_workouts.activity_type` + `elapsed_seconds` + `average_heart_rate` + `started_at AT TIME ZONE` are the canonical signals (see `verify_wearable_quests_for_today` ELSIF branches). Zone 2 is defined as average HR ∈ [110, 150] bpm — age-agnostic so it ships without `user_profiles.date_of_birth`. Recovery activity types: `('walk','hike','yoga','stretch','mobility','foam_rolling')` — that's the canonical set; reuse it rather than inventing variants. Time-of-day gates use `EXTRACT(HOUR FROM (started_at AT TIME ZONE p_timezone))` (canonical example: `evening_wind_down` requires hour ≥ 18 for "after 6pm"). New wearable templates that gate on overnight sensor state (sleep, HRV, RHR, recovery score, sleep performance, sleep consistency) MUST be paired with a user-takeable action — e.g. "wind down before [target]" auto-completing on tonight's recovery cardio, not "wake up with [score] above [threshold]".
20b. **Activity-mix bias never violates the "no two full workouts/day" invariant** (Smart Adaptive Daily Goals, 2026-04-25, migrations 20260601–20260607). Layer 4 of `get_daily_quests` v3 biases the slate toward the user's dominant 28-day bucket (strength / cardio / walk / stretch via `user_activity_mix`) and adds a +10% exploration bump to the least-touched bucket — the "sneak in the opposite" rule. The "sneak" candidates are ALWAYS lower-difficulty activity quests (steps, walk, hydration, mobility, log meal) NEVER a second prescribed full workout. `complete_2_workouts` stays permanently retired regardless of activity mix. The friend-named `do_friend_workout` quest replaces the existing `complete_workout` slot 1 — it does not add a second one. Recovery-aware copy ("Due for chest — do Paul's") leverages `WorkoutSuggestionEngine` split-family detection so the friend workout aligns with the user's recommended split, never overriding a red-recovery override (invariant 23).

### Cardio gamification (Sprint 2, Q2-5)

1. **Every cardio completion calls `UserManager.completeCardioWorkout(...)`** — wires XP + streak + league points (`+50`, parity with strength) + daily quests + challenges + badges + feed post. Never post a cardio workout silently.
2. **Cardio XP curve (approved)**: Base 20 + 10/15min capped at +40 + 10 if distance ≥ 3km + 10 if calories ≥ 300. Typical: 30-min jog → 40 XP; 60-min hike 8km/500cal → 80 XP. Weighted below strength so XP-per-minute is balanced.
3. **Cardio LP graduated bonus is server-side ONLY (Cardio Redesign Phase 1, 2026-05-02).** The `+50 .workout` parity LP stays in `UserManager.completeCardioWorkout`; the `+ cardio_bonus` graduated chunk (base + intensity_multiplier × km, capped +50/day) is awarded by the `record_cardio_workout` RPC (migration #185). The legacy client-side `+50 .cardioSession` was REMOVED — re-introducing it double-counts. Same-origin overlap dedup + cross-origin Strava merge happen inside the RPC; never replicate that logic on the client.
4. **Smart Goal Auto-Suggest = +7% above 7-day median, gated on ≥3 sessions (Cardio Redesign Phase 1).** Lives in `CardioGoalSetupView.applySmartSuggestion()`. The +7% is gentle progressive overload — never aggressive. <3 sessions → leave the static `recommendations` alone (small-sample noise becomes tomorrow's bad prescription). The bias ladder by `User.fitnessGoal` lives in SQL (`cardio_goal_bias_score(quest_key, fitness_goal)`, migration #187, returns -50…+30) — used by the next-sprint `get_daily_quests` v5 patch in slot-selection ORDER BY ONLY. Never hard-gate cardio quest assignment on fitness goal — produces silent slate failures.
5. **MET-by-pace calorie estimation (Cardio Redesign Phase 1).** `RunningManager.updateCalories()` reads `activityType.metForCurrentPace(currentPace)` — pace-aware MET tables for walk/run/hike/cycle. Replaces the old "constant MET per activity type" approximation that under-counted hill walks (8 MET when cresting 6%) and over-counted slow recovery jogs (10 MET regardless of pace). Tables anchored in ACSM compendium values; never hand-tune individual rows without citing a source.

### WHOOP recovery override

1. **Red recovery (0-33%) = override to recovery day.** Stretching / mobility / walking / yoga. Skip heavy compounds even if muscles are fresh — nervous-system recovery wins over muscle recovery. Yellow (34-66%) = normal programming with listen-to-body note. Green (67-100%) = encourage PRs / add volume.
  **IMPLEMENTATION (2026-05-06, Wearable Personalization Platform Phase 0-1).** Invariant is now wearable-agnostic — band thresholds live on `ReadinessBand` (0-33/34-66/67-100, same values). `ReadinessService.shared.todayReadiness` blends WHOOP recovery → Oura readiness → Fitbit-derived → HealthKit-derived into one unified score. Auto-gen honors the band via `ReadinessWorkoutAdjuster`:
  - `.red` → `buildRecoveryDayExercises(count:)` pulls stretches from the library (workoutType contains "stretch" OR name contains "yoga"/"mobility"/"foam roll"), bucketed by muscle region for whole-body variety (3-4 exercises).
  - `.yellow` → `adjustedCount = max(3, ceil(requested × 0.9))`.
  - `.green` → `allowsPrAttempt = true`; count unchanged; the +10% volume ceiling is applied per-exercise inside selection.
    Gated by `AppConfig.FeatureFlags.readinessAdaptiveAutoGen` (dark-ship) — off until red/yellow/green fixture tests validate the generator end-to-end. `WorkoutGenerationContext.readiness: DailyReadinessSnapshot?` snapshots on @MainActor BEFORE `Task.detached` (threading rules). Call sites: `WorkoutGeneratorService.generateWorkout()` short-circuits to recovery day when `adjustment.replaceWithRecoveryDay` AND stretches are available (falls through to normal generation when library is cold). `ActiveWorkoutView` shows `ReadinessAdjustmentBanner(snapshot:adjustment:)` when a wearable is connected + flag is on.

### Beginner safety

1. No Olympic lifts, no behind-neck press, no max-effort singles for beginners. Weight recommendations start conservative.

### Specialty variants only after the base movement is established

1. **A specialty variant must NEVER be auto-recommended ahead of its canonical base movement, and must NEVER be shown to a level/progression bucket that blocks it.** A "specialty variant" is a base exercise + programming modifier that requires the lifter to already own the canonical version. Severity bands (audit Round 3 introduced `block_until_established`):
   - **`block_beginner`** — block Beginner only.
   - **`block_intermediate`** — block Beginner + Intermediate (Advanced unlocks immediately).
   - **`block_until_established`** — block at EVERY level until the user has completed `workoutCountThresholds[level]` workouts (Beginner=12, Intermediate=8, Advanced=4). This tier is for **grip / unilateral / stability progression variants** that should never be a user's first autogen pick of the base movement, regardless of level. Audit synthetic users always pass count=0 → blocked across the board; live-app users earn the unlock with progression. The Swift caller threads `ProgressiveUnlockCache.shared.workoutCount` through `assessExercisePracticality(completedWorkoutCount:)` → `SpecialtyVariantFilter.evaluate(completedWorkoutCount:)`.
   - **`block_all`** — never auto-recommend at any level (catalog corruption / dangerous / mobility-flow).

   **Pattern coverage by family** (canonical: `scripts/specialty_exercise_filter.py`):
   - bench-press: `feet on bench`, `paused bench`, `spoto press`, `pin press`, `slingshot`, `guillotine` — BLOCK_ALL, `jm press`; **grip-progression (BLOCK_UNTIL_ESTABLISHED)**: `close grip incline`, `reverse grip`, `wide grip bench`, `wide bench press`, `close grip bench press`, `bench press - close grip`, `decline bench press - wide grip`, `3 point bench`, `reverse close grip`.
   - squat: `paused squat`, `tempo squat`, `box squat`, `1 1/4 squat`, `heels elevated`, `sissy squat`, `anderson squat`, `zercher`, `jefferson`; `deep squat turn`, `lunge with internal rotation`, `reverse lunge forward lunge` — BLOCK_ALL mobility-flow / catalog corruption; **grip-progression / unilateral (BLOCK_UNTIL_ESTABLISHED)**: `clean grip`, `elevated goblet`, `front foot elevated`, `single leg press`, `split squat front foot elevated`.
   - kettlebell combo (BLOCK_ALL — listed FIRST in pattern array so multi-modifier names like "Swing Clean Grip Front Squat" match the combo first instead of fragments): `swing clean grip`, `swing to ` (KB flow combos blur swing + landed exercise — never autogen).
   - deadlift: `stiff leg`, `trap bar`, `deficit deadlift`, `snatch grip deadlift`, `block pull`, `paused deadlift`, `tempo deadlift`, `reset deadlift`, `touch and go`, `rack pull`.
   - row: **technique-progression (BLOCK_UNTIL_ESTABLISHED)** — `pendlay row`, `yates row`, `meadows row`, `kroc row`. Tempo/pause: `paused row`, `tempo row`.
   - pull-up: `dip cage` (BLOCK_BEGINNER); **grip-progression**: `hammer grip pull up` (BLOCK_UNTIL_ESTABLISHED).
   - curl: `21s`, `drag curl`, `zottman`, `waiter curl`, `bayesian curl`.
   - OHP: `z press`, `savickas`, `bradford`, `cuban press`, `sots press`, `viking press`, `landmine press`.
   - core/oblique: `pallof press twist`, `pallof twist` — BLOCK_ALL (rotation contradicts the anti-rotation cue); `half kneeling pallof` (BLOCK_BEGINNER).
   - plank: `reverse plank march`, `leg extension plank` — BLOCK_ALL mobility-flow; `side bend plank`, `elbow to knee side plank` (BLOCK_BEGINNER).
   - generic prescription modifiers: `tempo`, `paused`, `1 1/4`, `1.5`, `rest pause`, `myo-rep`, `cluster set`, `drop set`, `with chains`, `eccentric only`, `isometric hold`.

   **CANONICAL SOURCE**: `scripts/specialty_exercise_filter.py` (83 self-test fixtures including workout-count gating regression). Swift mirror lives in `Fit33/SmartExerciseSelectionEngine.swift` `enum SpecialtyVariantFilter`. The Swift filter is now applied as an **early hard-block** (line ~390 in `selectExercisesForWorkout`) BEFORE the database practicality-score check — the previous bug was that exercises with high DB scores bypassed the specialty filter (Round 3 audit found 43 specialty variants slipping past). When you add/remove a pattern, update BOTH places in the same commit and re-run `python3 scripts/specialty_exercise_filter.py` (self-test) plus `python3 scripts/autogen_audit_simulator.py --users 50` to confirm the live app and the audit agree.

### Equipment matching (single canonical filter)

1. **A bench is implied only by EXPLICIT bench selection OR by heavy gym indicators (barbell / machine / cable / smith / rack) — bare dumbbells DO NOT imply a bench.** (2026-05-08 audit fix.) Outdoor users with a dumbbell pair were getting "Glute Bridge Skull Crusher (Dumbbells, Flat Bench)" because the previous heuristic granted bench access to anyone with dumbbell/barbell/machine. Real-world: a barbell setup almost always lives in a rack-bench combo (kept), but a dumbbell-only outdoor user has no bench. Authority: `ExerciseFilterService.userHasRequiredEquipment` `userHasBenchAccess` predicate (Swift) + `comprehensive_autogen_audit.user_has_required_equipment` `bench_implied` flag (Python). When you see a "Flat Bench / Incline Bench / Decline Bench" requirement on an exercise and the user is `outdoor` location with bare dumbbells, the exercise MUST be filtered out.

2. **All autogen / program / smart-selection paths must call `ExerciseFilterService.userHasRequiredEquipment(exerciseEquipment:exerciseName:userEquipment:)` for equipment match decisions — NEVER write a local substring matcher.** The 2026-05-08 audit found 79 `equipment_mismatch` issues in 20 users, all coming from a duplicated buggy matcher inside `SmartExerciseSelectionEngine.doesEquipmentMatch()` (since deleted). Common bug patterns the canonical filter blocks: empty-string `""` in bodyweight patterns (matched everything), bare `"bar"` in barbell patterns (false-positived on "Pull-Up Bar"), `"olympic"` (too broad), substring-only checks that ignored explicit equipment in the exercise NAME (e.g. "Banded Bench Press" with empty equipment field). The canonical filter performs name-based absence checks for: `barbell`, `dumbbell`, `cable`, `machine`, `smith`, `pull-up bar`, `dip bars`, `bench`. Pattern dictionary is `ExerciseFilterService.normalizeEquipmentForMatching()`. The Python audit mirror lives in `scripts/comprehensive_autogen_audit.py` (`_normalize_equipment_for_matching` + `check_equipment_match`) and MUST stay in sync. **Bench-access rule**: bench-name exercises (`bench press`, `incline bench`, `decline bench`, `flat bench`) pass IFF the user explicitly selected "Bench" OR has dumbbell/barbell/machine (gym SKUs imply bench access). Outdoor + bodyweight users never get bench-dependent exercises.

### Catalog hybrid-name filter (catches database-corruption entries)

1. **Multi-stage hybrid exercise NAMES are blocked at ALL levels — Advanced is NOT exempt.** (2026-05-08 audit found Advanced users getting "Romanian Deadlift Bicep Curl Kickback", "Curl Press Extension", "Lying Pressdown - Skull Crusher - Reverse Grip" — these are catalog corruption / non-real movements, not legitimate flow work.) Authority: `SmartExerciseSelectionEngine.assessExercisePracticality()` "Complex multi-stage hybrid name" branch. An exercise NAME is multi-stage hybrid if ANY of: (a) `>= 2` " to " connectors ("Squat to Press to Curl"), (b) `>= 2` " and " connectors ("Lunge and Twist and Reach"), (c) `>= 3` hyphens for non-Advanced / `>= 4` for Advanced ("Side-Lying-Hip-Drop-with-Leg-Lift"), (d) `>= 3` distinct movement-noun tokens (set: `deadlift, squat, lunge, press, curl, row, fly, raise, kickback, extension, crunch, twist, swing, snatch, clean, jerk, pulldown, pressdown, thrust`). The movement-noun rule is the only one that catches no-separator hybrids like "Romanian Deadlift Bicep Curl Kickback" (deadlift + curl + kickback = 3 hits → block).

### Movement-pattern diversity within a workout

1. **Max 2 exercises of the same granular movement pattern per workout.** The canonical cap is `SmartExercisePairingEngine.movementPatternRepeatCap` (= 2). The 2026-05-08 audit caught workouts with 3 pull-up variations slipping past the coarse `SelectionMovementPattern.maxPerWorkout` enum because the variants mapped to different coarse patterns. The granular `MovementPattern` enum from `ExerciseTypes.swift` (used by `SmartExercisePairingEngine`) is the backstop classifier — `wouldExceedDiversityCap(adding:to:)` is consulted in the selection loop AFTER the coarse check. Soft tiebreaker: `ScoringHints.redundancyPenaltyPerExtraVariant` = -120 (was -50 — the older value let 3rd variants slip through on score). When the catalog says compound but `FoundationalExerciseDatabase.isSingleJointIsolation(name:)` returns true, the final compound→isolation sort treats the exercise as isolation (skull crushers / kickbacks / lateral raises must come AFTER bench / squat / deadlift even when the catalog mis-labels them).

### Angle-stacking cap (decline / incline / flat / vertical / horizontal)

1. **Max 2 exercises per angle bucket per workout.** Authority: `WorkoutComboRules.maxPerAngle` (= 2) + `WorkoutComboRules.wouldExceedAngleStackingCap(candidateName:selectedNames:)`. The Round 3 audit (2026-05-08) flagged `redundant_movement_pattern` 100 times — the worst offenders had 4× decline chest movements in a single workout (user-15, user-26 both got 4 decline chest exercises). The cap blocks: chest angles `decline` / `incline` / `flat` (max 2 each); back vertical pulls (`pulldown` / `pull up` / `chin`) (max 2); back horizontal pulls (`row` / `bent over` / `seated row`) (max 2). The score-side counterpart `ScoringHints.angleStackingPenalty` (= -300) is applied when the count `>= 3` so even if the cap is bypassed by a higher-priority pick, the penalty deters stacking. Caller: `SmartExerciseSelectionEngine.selectExercisesForWorkout` line ~932 (named-loop `angle-cap-skip:` re-checks the cap before appending each candidate).

### Compound-before-isolation final-pass sort

1. **The selection engine's LAST step is a stable compound-first partition.** Authority: `SmartExerciseSelectionEngine.sortCompoundFirst(_:)` called at the end of `selectExercisesForWorkout`. The Round 3 audit flagged `compound_after_isolation` 42 times (top-fix #1 / #4 / #5 / #9 / #12 — all variations of "isolation appearing before compound"). The previous reorder used `Array.sort` with a score tiebreaker — Swift's `Array.sort` is NOT stable, so it shuffled within-bucket order. The new helper is an explicit two-pass partition: compounds in original picked order, then isolations in original picked order. **Catalog mis-label override**: when `ex.exerciseType == .compound` BUT `FoundationalExerciseDatabase.isSingleJointIsolation(name:)` returns true, the exercise is treated as isolation (catches skull crushers / kickbacks / lateral raises that the catalog mis-labels as compound). Don't manually reorder the array after this final pass — the sort IS the contract.

### Target-muscle coverage with foundational fallback

1. **A workout that promises a target muscle MUST deliver an exercise hitting it (primary OR secondary).** Authority: `SmartExerciseSelectionEngine.validateTargetMuscleCoverage(selected:targetMuscles:)` returns the subset of `targetMuscles` that NO selected exercise covers. The Round 3 audit caught 4 workouts that promised "calves" but delivered no calf exercises (top-fix #3 / #10). Coverage is matched via case-insensitive substring against `getMuscleGroups()` + `secondaryMuscles` + `category`, expanded by the synonym set in `synonymsForMuscle(_:)` (so "calves" also accepts "lower legs"; "back" also accepts "lats" / "upper back" / "traps"). When a gap is detected, `attemptCoverageSwap(...)` swaps in a foundational fallback exercise from the user's available equipment BEFORE the compound-first sort runs (so the swap-in still gets ordered correctly). If no foundational candidate is available, an `AppLogger.warning` fires for Bug-Intel pickup — silent gaps are not allowed. "Full body" / "upper body" / "lower body" target descriptors are skipped (coverage is implicit).

### Age-gated decline block (65+)

1. **Users 65+ MUST NEVER receive decline-angle chest exercises.** Decline position places the head below the heart, elevating intracranial pressure and systolic BP — cardiovascular / stroke risk outweighs the chest-development upside at this age. The Round 3 audit caught user-26 (68y, female, Build Muscle, 20min) getting 4× decline chest in one workout — Claude verdict: `reject`. The block is applied as TWO layers: (a) early hard-block at `selectExercisesForWorkout` line ~372 (`if userAgeForFilter >= 65 && nameLower.contains("decline") { continue }`) so the database-score path can't bypass it; (b) `assessExercisePracticality()` `userAge >= 65` check as backstop. Canonical replacement is a flat or low-incline press at the same loading. User age is read from `UserManager.shared.currentUser?.age`.

### Gender-aware video selection (strength = strict, stretch = fallback)

1. **Strength workouts MUST NEVER serve an opposite-gender-only demonstration video** (Audit 2026-05-08 user request — "very rarely should a male see female and vice versa in strength workouts"). The catalog has both-gender clips for the top ~200 common strength exercises, so when an exercise IS gender-tagged in `VideoStreamingService.genderVideoCache` but missing the user's gender, an equivalent same-gender alternative exists in the catalog. Both `WorkoutGeneratorService` (legacy autogen) and `SmartExerciseSelectionEngine` (program/smart-selection) hard-FILTER opposite-gender-only strength exercises before scoring (not just penalize them). Stretch / cardio / plyometrics / specialty: catalog is smaller and dual-gender clips are sparse — keep the existing soft fallback (`filenameWithFallback(preferred:)`) so the user always sees SOMETHING. Untagged exercises (no entry in `genderVideoCache`) are gender-neutral by definition — always shown. Per-exercise type classification uses `ExerciseFilterService.classifyExerciseType(name:category:equipment:)` so a single workout can mix strength (strict) + cardio finisher (lenient). User gender is read from `UserManager.shared.currentUser?.gender` (Core Data `Profile.gender`).

### Goal-aware exercise selection

1. **`Build Endurance` boosts circuit-friendly + light-load + bodyweight basics; penalizes 1RM-style heavy compound lifts.** Authority: `FoundationalExerciseDatabase.goalMultiplier(exerciseName:equipment:category:goal:)`. Multipliers: 1.30 for circuit movements (kettlebell swing, jump rope, mountain climber, burpee, battle rope, rowing); 1.20 for high-rep bodyweight basics (push-up + squat + lunge + plank + sit-up); 1.15 for kettlebell/band/medicine ball SKUs; 0.85 for heavy barbell compounds in non-Endurance phrasing; 0.75 for "1RM"/"max effort"/"powerlifting" naming and heavy barbell deadlift specifically. Other goals → multiplier = 1.0 (existing scoring stays canonical). Helper is wired into `SmartExerciseSelectionEngine`'s scoring loop just before exercises are appended to `scoredExercises`.

2. **Advanced + Build Muscle + ≥50min sessions get +1 exercise.** Canonical sizing function: `getExerciseCountForDuration(_ durationMinutes:Int, equipmentIsMostlyMachines:Bool=false, experienceLevel:String="", goal:String="")`. The bump caps at 9 exercises total — past 9, programming becomes counterproductive (rest periods compress, fatigue accumulates). Default args keep all existing callers backwards-compatible.

### Exercise swap tiering

1. **Swaps 1-2** → equipment variant (same movement pattern, different equipment) via `ExerciseSwapService.getQuickSwap()`. **Swap 3+** → complementary exercise from `complementaryFamilies`. Fallback → algorithmic scoring by muscle overlap + movement pattern + equipment + difficulty.

### Rest timer defaults

1. Default rest **90s**, range 0-300s in 15s increments. `0 = Off`. `defaultRestSeconds` is read by `getRestDuration(for:)` directly — no category-based hardcoded values. `autoStartRestTimer` gates `RestTimer.startWithAdOffset()` — when `false`, completing a set does not start the countdown (supersets / circuits / drop sets).

### Quality workout corpus (auto-gen training data)

1. **The auto-gen recommender only learns from "quality" workouts (score ≥ 70).** Junk 7-min / 2-exercise tap-throughs MUST never enter `collaborative_workout_data`. Canonical rubric (`Fit33/WorkoutQualityScorer.swift` mirrors `score_workout_quality` SQL RPC, migration #154 — must stay in sync if either changes — total 100 pts):
  - Duration ≥ 25 min — 20 pts
    - `completion_rate` ≥ 0.80 — 25 pts
    - ≥ 3 distinct catalog exercises — 15 pts
    - ≥ 12 working sets (warmups excluded) — 15 pts
    - ≥ 50% of weight-eligible sets have non-zero weight — 10 pts
    - Avg time-between-set-completions ≥ 20s (proxy: `duration / completedSets`) — 10 pts
    - FE invariants pass (push:pull ≤ 2:1, ≤ 2 horizontal presses) — 5 pts (lenient bonus)
    Bands: `high` (≥70 — qualifies for corpus), `medium` (40–69), `low` (<40). The first four checks sum to 75 by design — a workout MUST clear Duration + Completion + ExerciseCount + Sets to qualify; the remaining 30 pts are nuance and never carry a poor workout over the bar by themselves. New "what makes a good workout?" PRs MUST update both `WorkoutQualityScorer.swift` AND `score_workout_quality` in the SAME commit. Bodyweight + duration-based exercises auto-pass the weight-distribution check (no weight expected).

### Workout Intelligence pipeline (per-quality-workout Claude analysis)

1. **Every quality workout (score ≥ 70) AND every "lost session" (score 60-69) generates a Claude analysis report stored in `ai_workout_reports.report_jsonb`.** The pipeline (migrations #156-#159, edge function `analyze-quality-workout`, system prompt mirrors FE invariants 1-28) extracts: split family / inferred goal / volumeBalance / pressDistribution / orderingScore / pairingQuality / pairingFindings / pacingProfile / progressionEvidence / swapInsights / redFlags / **exerciseCorrections (gated through corroboration ladder — see #2)** / programmedVsExecuted / recommenderSignals / summaryMd. **Pre-flight suspicious-pattern detector** (1-lb working sets, 1-rep→100-rep jumps, >50% zero-rep "completed" sets, <10min with >=20 sets, >5 distinct workouts in 60min) flips `is_suspicious=TRUE` and skips Claude — those workouts are excluded from corpus regardless of quality score. **Lost-session flag** (`is_lost_session=TRUE` for score 60-69) is the recovery hatch: surfaced in CMS for manual promote/discard. Pairing intelligence (`pairing_signals`) auto-discovers synergistic + negative pairings from the same reports — `SmartExercisePairingEngine` reads from this table to bias future auto-gen toward pairings real users complete well together. Pipeline runs every 10 minutes via pg_cron (`analyze-quality-workout-run`, migration #159).

2. **Catalog corrections require BOTH confidence === 1.0 AND a deterministic gate (#157).** The `apply_exercise_correction` v1 policy of "Claude says 1.0 → write directly to catalog" was insufficient — Claude's self-asserted confidence is unverifiable, and append-only union prevents data LOSS but creates a one-way ratchet (every wrong tag accumulates forever). The v2 corroboration ladder routes every Claude proposal through `propose_exercise_correction` → `exercise_correction_proposals`. Auto-apply requires confidence=1.0 AND ≥1 of three gates passing: **(a) sister-exercise gate** — for muscle add: ≥1 sister in the same `exercise_family` already has the value; for muscle remove: ≥2 sisters do NOT have the value. **(b) name-based determinism** — the exercise name contains an unambiguous keyword (regex maintained in `_correction_name_gate`, conservative TRUE/Strength/Stretch/Plyometrics/Cardio/equipment direction; FALSE direction for is_compound only after a compound-disambiguator filter). **(c) multi-report agreement** — same correction proposed by ≥2 distinct reports in last 30 days (≥3 for REMOVE — destructive op gets a higher bar). Whitelist unchanged: `primary_muscles` (add/remove), `secondary_muscles` (add/remove), `workout_type` (set), `equipment_category` (set), `is_compound` (set), `duration_based` (set). Anything else is rejected with `23514` server-side. Subjective fields (difficulty_level, priority scores, exercise_family, complementary_families, description) are NEVER touched.

3. **Removals require a stricter path AND a core-exercise lockout (#157).** `operation='remove'` against muscle arrays auto-applies only when confidence=1.0 AND multi-report ≥3 (or sister-disagreement) AND the exercise name does NOT match `catalog_core_exercises.name_pattern` (bench, squat, deadlift, pull-up, OHP, row, clean, snatch, jerk family). Removal proposals against canonical core exercises are NEVER auto-applied regardless of corroboration count — they always queue for explicit human approval (status `blocked_core_exercise`). This is defense-in-depth against systemic bugs that could propose "remove Pec from Bench Press" or "remove Lats from Bent Over Row". Even 3 corroborating reports for those should be human-reviewed — a wrong systemic prompt could propose them all simultaneously.

4. **Proposals queue is the source of truth — every Claude proposal lands here, gated or not.** `exercise_correction_proposals` is append-only, surfaced in CMS at `/catalog-proposals`. Statuses: `pending` (waiting for a corroborating signal — auto-promotes via nightly cron `promote-corroborated-proposals-nightly` at 03:45 UTC, migration #159), `applied` (auto-applied via gate, audit row in `exercise_corrections`), `blocked_core_exercise` (held for human review per #3), `rejected` (apply RPC threw — usually a stale exercise name), `superseded` (a later proposal made this one moot). `_correction_name_gate` regex updates (a new "obvious" keyword gets added to the strength/isolation/compound list) automatically promote any pending proposals that newly qualify on the next nightly cron. Subjective fields are still never on the whitelist — name-gate widening only un-stalls deterministic cases.

5. **Catalog audit sweep is a parallel feeder, not a bypass.** `audit-catalog-exercise` edge function + `scripts/audit_exercise_catalog.py` orchestrator run a one-pass audit of every catalog row through the same `propose_exercise_correction` RPC — catalog-driven rather than workout-driven. The script defaults to skipping any exercise that already has a non-rejected proposal (so re-runs are cheap) and skipping rows manually edited within the last 30 days. The edge function uses prompt caching ($0.30/MTok cached read on the system prompt) and is service-role-only. **It writes through the same RPC → same gates → same core-exercise lockout — there is NO catalog-write path that bypasses corroboration.** Use this when a new field is added to the audit whitelist or when a systemic data-quality issue needs a single sweep across the whole catalog.

6. **Autogen-audit-driven catalog cleanup is the high-signal loop (2026-05-08).** The autogen audit (`scripts/autogen_audit_simulator.py` — 100-200 synthetic users × the real Swift autogen via the XCTest harness) produces a `.md` that names the EXACT exercises Claude flagged as obscure / mislabeled / stretch-in-strength / equipment-mismatched IN THE SPECIFIC SLOTS THEY WERE SERVED. This signal is much higher than a blind catalog sweep — the autogen has already filtered the catalog through level/equipment/specialty gates, so anything still flagged is by definition a row whose CATALOG METADATA is wrong (right exercise, wrong tags). The canonical cleanup loop:
   1. Run the autogen audit → `scripts/output/autogen_audit_<TS>.md`.
   2. Extract the suspect names: `python scripts/extract_audit_rejections.py scripts/output/autogen_audit_<TS>.md --output scripts/output/suspects_<TS>.txt`. Default mode `--low-rated` keeps only exercises from workouts rated `< 5/10`; `--rejected-only` is tighter (verdict=`reject` only); `--all` is the full superset.
   3. Targeted dry-run through the corroboration ladder: `python scripts/audit_exercise_catalog.py --dry-run --names-file scripts/output/suspects_<TS>.txt`. The `--names-file` flag BYPASSES `--skip-recent-days` and the existing-proposal skip — the operator explicitly asked for these names, so they get re-audited regardless of recent edits or pending proposals. Output: `scripts/output/catalog_audit_<TS>.csv` with one row per Claude-proposed correction.
   4. Stage the apply (caps → sister → rest) per the existing `--stage` flag. Every write still flows through `propose_exercise_correction` → corroboration gates → core-exercise lockout (#3 above) — the targeted seed only changes WHICH rows we ask Claude about, never how the gates evaluate his proposals.
   5. Re-run the autogen audit. **Compute the delta mechanically** via `python scripts/diff_audit_reports.py BASELINE.md CANDIDATE.md` — emits headline rating Δ, verdict mix Δ, issue-category top movers, and the set-diff of "new top-fixes" vs "dropped top-fixes" (the dropped set is the strong signal: those are areas the round actually IMPROVED). If the average rating moves up, the cleanup landed real value. If it didn't move OR regressed, mark the latest batch of proposals as `rejected` via the CMS at `/catalog-proposals` (this preserves the historical signal — proposals are append-only per #4) and re-investigate. NEVER add a "rollback applied correction" shortcut — the `manually_updated_at` audit trail + `exercise_corrections` log is the only undo path, and it stays human-gated. **Caveat**: the diff tool compares absolute counts, so two rounds being diffed MUST have the same `--workouts-per-user × --users` product (e.g. 100×2 vs 100×2) — diffing a 100-workout round against a 200-workout round inflates every category by 2× regardless of fix impact.
  
  **What we DO NOT add (rejected approach):** a "shadow catalog" table (`exercises_proposed`) that the Swift autogen reads from when `FIT33_AUDIT_USE_SHADOW_TABLE=1` — that would be a catalog-write path that bypasses corroboration (writes land in a parallel table, never in `exercises`). The proposals queue + corroboration ladder is already the canonical "validated catalog change" pipeline. Adding a shadow surface would split the source of truth and violate #5 above.

### Reversible completion (Delete Workout)

1. **The Delete Workout button on the completion screen is the one place where every server-side workout side-effect is reversed atomically.** `WorkoutManager.deleteCompletedWorkout(_:)` calls the `delete_workout_and_revert_stats` RPC (migration #155) which reverses XP, league points (+ Peak Day multiplier already baked into `awarded_points`), daily quest progress (`complete_workout` / `complete_program_day` / `do_friend_workout` / `workout_30_min` slots), `user_progress.total_xp` + `total_workouts`, AND the corpus row (FK CASCADE via #154). iOS owns conditional streak revert — only roll the streak back if THIS was the only completed workout for the calendar day (server can't decide without joining `cardio_workouts`). HKWorkout deletion is best-effort (`HealthKitManager.deleteWorkoutInWindow`) — only deletes workouts written by THIS app, identified by source bundle id. **Guard**: the Delete button is disabled when the workout has been shared with a friend (`didSendToFriend == true`) — the friend already received the data and we have no "un-share" path. New eager writes from the completion path MUST be reversed by both sides: the server-side step is added to `delete_workout_and_revert_stats` and the iOS-side counterpart is added to `WorkoutManager.deleteCompletedWorkout`.

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


| File                                                                                                     | What to check                          |
| -------------------------------------------------------------------------------------------------------- | -------------------------------------- |
| `WorkoutComboRules.swift`                                                                                | Combo rules; avoid lists               |
| `SmartExerciseSelectionEngine.swift`                                                                     | Movement-pattern caps; scoring weights |
| `SmartExercisePairingEngine.swift`                                                                       | Pairing scores; biomechanics           |
| `SmartProgramEngine.swift`, `DynamicProgramGenerator.swift`, `SmartDayGenerator.swift`                   | Split selection; muscle groupings      |
| `ExerciseBundleEngine.swift`                                                                             | Bundle groupings                       |
| `ProgramTemplateLibrary.swift`                                                                           | Periodization loading                  |
| `IntelligentWorkoutGenerator.swift`, `ExerciseIntelligenceEngine.swift`, `WorkoutGeneratorService.swift` | Balance; ordering                      |
| `SmartProgramRecommender.swift`                                                                          | Split ↔ user profile                   |
| `FoundationalExerciseDatabase.swift`                                                                     | Beginner-safe                          |
| `StrengthProfileRecommendationEngine.swift`                                                              | Weight recs safe + progressive         |
| `ExerciseSwapService.swift`                                                                              | Swap tiering                           |
| `ProgressiveWorkoutIntelligence`                                                                         | Overload values evidence-based         |
| `ActiveWorkoutView.swift` (+ helpers)                                                                    | Set init / shuffle / overload          |
| `SmartExerciseSearchService.swift`                                                                       | Typo dict; muscle names                |
| `ExerciseFilterService.swift`                                                                            | Equipment categories; muscle coverage  |


---

## Engine Threading Rules (hard-won)

- `**SmartExercisePairingEngine` is NOT `@MainActor`.** Uses `container.newBackgroundContext()` + `context.perform { }` in `buildPairingDatabase()`. Prior `@MainActor.run { getAllExercises() }` dropped FPS to 6 and froze for 1.3s while loading 5500 exercises.
- `**WorkoutSuggestionEngine` is NOT `@MainActor`.** Uses private `bgContext` with `performAndWait` for `getRecentMusclesWithDates()` / `getRecentSplitFamilies()`. Methods that read `@MainActor` program services are individually `@MainActor`.
- `**WorkoutGeneratorService.generateFromCoreData` remains `nonisolated`**, runs via `Task.detached`. `WorkoutGenerationContext` snapshots `@MainActor` state for background generation.

---

## Validation Checklist (pre-ship)

- Compound before isolation
- Push:pull ratio ≤ 2:1
- No neglected muscle groups
- Volume matches experience
- Split matches days/week
- No redundant movement patterns (≤ 2 horizontal presses)
- Progressive overload in multi-week programs
- Deload included > 4 weeks
- Equipment matches user inventory
- Balance slot enforced
- Rep range matches stated goal
- Rest period matches goal
- Beginner safe (no Olympic / behind-neck)
- Unilateral work on leg days
- Spinal loading ≤ 1 heavy hinge
- Set pre-fill uses working sets only
- Swap tiers follow pattern
- Minimum 3 sets

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

