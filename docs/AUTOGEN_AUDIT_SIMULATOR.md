# Auto-Gen Audit Simulator — Runbook

The Auto-Gen Audit Simulator is the cheat-code-level harness for improving the
auto-generated workout recommender. One command synthesizes N users that span
every onboarding combination, runs the auto-gen against each, sends results
to a multi-agent Claude reviewer (Fitness Expert + Product Engineer), and
emits a single Markdown report that the engineering team — and Cursor — can
act on.

This runbook is for the agent doing the audit (you). It tells you how to:

1. Verify drift between the simulator and the live Swift app before each run.
2. Run the 100-user sample.
3. Read the Markdown report.
4. Convert top fixes into actual code changes.
5. Extend the system (new specialty patterns, new audit categories).

---

## Architecture

```
┌──────────────────────────────────────────────────────────────────────┐
│  scripts/autogen_audit_simulator.py            ← orchestrator        │
│    ├── synthesize_users(N)                     ← stratified profiles │
│    ├── fetch_exercises_from_supabase()         ← live catalog        │
│    ├── select_exercises_for_workout(...)       ← reused Python mirror│
│    │   └── check_practicality(...)             ← in-line specialty   │
│    │       └── specialty_exercise_filter.py    ← canonical patterns  │
│    ├── apply_specialty_filter(...)             ← post-process safety │
│    ├── call_claude_review(...)                 ← edge function       │
│    │   └── audit-autogen-workout/index.ts      ← FE + PE prompt      │
│    └── _render_report_md(...)                  ← .md + .json         │
│                                                                      │
│  Fit33/SmartExerciseSelectionEngine.swift                            │
│    └── enum SpecialtyVariantFilter             ← Swift mirror        │
└──────────────────────────────────────────────────────────────────────┘
```

The simulator is **honest about drift**. The Python `select_exercises_for_workout()`
is a mirror of Swift's `SmartExerciseSelectionEngine` and is ~2 months stale at
any given time. Every report opens with a "Drift Banner" listing what the
simulator could and could not faithfully reproduce. Trust:

- **Specialty-variant slip rates** — the canonical filter runs in BOTH the audit
  and the Swift app, so if the audit flags a slip, that's a real bug.
- **Claude's workout-level review** — Claude reads the actual generated exercise
  list, not the algorithm. Its rating, issues, and improvement suggestions are
  algorithm-agnostic.

Treat as approximate:

- The **per-exercise filter and scoring numbers** in the Python mirror — that's
  the part that drifts.
- **Cardio Phase 1** (out of scope — strength only).
- **Wearable readiness override** (not modeled — always generates a strength
  workout, never a recovery override).

---

## One-time setup

### 1. Python deps

```bash
pip install supabase requests
```

### 2. `.env` at repo root

Required:

```
SUPABASE_URL=https://<project>.supabase.co
SUPABASE_SERVICE_ROLE_KEY=<service-role-key>
SUPABASE_ANON_KEY=<anon-key>      # optional, used as fallback
```

The simulator's `load_env` helper auto-loads these from `.env`.

### 3. Deploy the Claude edge function

```bash
supabase functions deploy audit-autogen-workout
```

Required secret on the Supabase project:

```bash
supabase secrets set ANTHROPIC_API_KEY=<your-anthropic-key>
```

You can verify with the existing audit-catalog-exercise — both functions share
the same Anthropic key.

---

## Running the 100-user sample

```bash
python3 scripts/autogen_audit_simulator.py --users 100 --workouts-per-user 2
```

Expect:

- **Pulling the catalog**: ~5s, single Supabase query.
- **Synthesizing profiles**: <1s.
- **Auto-gen**: ~30s on a laptop (in-process Python, no IO).
- **Claude review**: ~200 calls × ~4s sequential ≈ 13 min, with prompt
  caching after the first call (system prompt is intentionally >1024
  tokens). Cost ≈ $3-5 on Sonnet 4.

Output:

- `scripts/output/autogen_audit_<timestamp>.md` — human + Cursor readable.
- `scripts/output/autogen_audit_<timestamp>.json` — raw structured data
  for downstream tooling.

### Smoke run (no Claude — fast iteration)

```bash
python3 scripts/autogen_audit_simulator.py --users 5 --workouts-per-user 1 --no-claude
```

Use this when validating the pipeline after changing the simulator itself.
Skips Claude entirely; the report is heuristic-only but still includes the
specialty-variant slip table, which is the actionable part.

### Cost-controlled run

```bash
python3 scripts/autogen_audit_simulator.py --users 200 --max-reviews 50
```

Generates 200 × 2 = 400 workouts, but only sends the first 50 to Claude. Useful
for catalog coverage validation without bursting the API budget.

---

## Reading the Markdown report

The report is structured for Cursor consumption. Sections, in order:

1. **Drift Banner** — what the simulator can and cannot validate. Read first.
2. **Headline Numbers** — average rating, verdict counts, severity counts,
   specialty-slip count.
3. **Top Fixes (ranked by frequency)** — the actionable list. Each row has:
   - Owner: `fitness_expert` or `product_engineer`.
   - Priority: `high` / `medium` / `low`.
   - Title: imperative summary.
   - **Concrete change** — file path + function/section to edit.
4. **Specialty-Variant Slip Table** — what the audit's filter caught BEFORE
   sending to Claude (i.e. variants the live Swift app currently lets through).
5. **Specialty Variants Claude Still Flagged** — residual gaps. Each row is a
   pattern to add to `scripts/specialty_exercise_filter.py`.
6. **Issue Categories** — frequency by category.
7. **Worst 5 Workouts** — full reviews of the lowest-rated workouts.
8. **Best 5 Workouts** — sanity check.
9. **Review Errors** — Claude calls that failed (network, parse, rate limit).
10. **Reproducibility** — exact command + seed.

### Cursor workflow

Open the latest report in Cursor and prompt the agent:

> Land the high-priority fixes from this report.

The agent will read the "Top Fixes" table, follow each `concrete_change`
pointer, and make the edits. Verify each change with the build (`xcodebuild`)
and re-run the audit.

---

## Extending the system

### Adding a new specialty variant pattern

You discovered "Reverse Lunge with Pause" slipping through. To block:

1. **Add to canonical Python** (`scripts/specialty_exercise_filter.py`):

   ```python
   Pattern("with pause", "generic", SEVERITY_BLOCK_BEGINNER,
       "Pause-prescribed lunge — specialty cadence")
   ```

   Add a fixture to `SAMPLE_NAMES`:

   ```python
   ("Reverse Lunge with Pause", True, SEVERITY_BLOCK_BEGINNER),
   ```

   Run `python3 scripts/specialty_exercise_filter.py` to verify the test passes.

2. **Mirror to Swift** (`Fit33/SmartExerciseSelectionEngine.swift`, `enum
   SpecialtyVariantFilter`, `static let patterns`):

   ```swift
   Pattern(substring: "with pause", baseMovement: "generic", severity: .blockBeginner,
       rationale: "Pause-prescribed exercise — specialty cadence"),
   ```

3. **Run a 5-user audit** to confirm the live app and the simulator agree:

   ```bash
   python3 scripts/autogen_audit_simulator.py --users 5 --workouts-per-user 2 --no-claude
   ```

   Open the report — the "Specialty-Variant Slip Table" should show the new
   pattern catching anything that previously slipped.

4. **Update FE invariant** (`FITNESS_EXPERT_AGENT.md` invariant 24a + mirror to
   `.cursor/agents/fitness-expert.md`).

### Adding a new audit category

You want Claude to flag workouts that exceed 30 minutes of estimated cardio
time on a strength day. To extend:

1. Edit `supabase/functions/audit-autogen-workout/index.ts` `SYSTEM_PROMPT`.
   Add a new `category` value to the `category` enum:

   ```
   - "excessive_cardio_in_strength_workout" → cardio time > 30 min on strength day
   ```

   Add a worked example to the `# WORKED EXAMPLES — DO` section.

2. Re-deploy: `supabase functions deploy audit-autogen-workout`.

3. Run a sample audit; the new category should appear in the "Issue Categories"
   table when triggered.

### Adding a new user-profile axis

The simulator stratifies across gender × level × location × goal. To add an
axis (e.g. `pregnant: yes/no`):

1. Add to `SimulatedUser` in `scripts/autogen_audit_simulator.py`.
2. Update `synthesize_users()` to randomize the axis.
3. Update the `audit-autogen-workout` system prompt to call out the new axis
   in the user profile section.
4. Update the orchestrator's payload-builder to forward the axis.

---

## Drift maintenance

Every sprint: re-run a 5-user smoke test and SCAN the drift banner. If
something flips from `synced` to `STALE`, fix it before the next sample run.

The simulator's pre-flight `_assert_app_state_drift()` will eventually grow
to verify:

- Goal list matches `Fit33/NewOnboardingView+Steps.swift` line ~525.
- Equipment SKUs match `Fit33/WorkoutGeneratorSelectionView.swift`
  `EquipmentLocation`.
- Experience levels match `Fit33/NewOnboardingView+Steps.swift` line ~557.

For now, those checks are documentary in the drift banner — when one drifts,
update the constants at the top of `autogen_audit_simulator.py`.

---

## Files

| Path | Purpose |
|------|---------|
| `scripts/specialty_exercise_filter.py` | **Canonical** specialty pattern list + 40-fixture self-test |
| `scripts/autogen_audit_simulator.py` | Orchestrator + report writer |
| `scripts/comprehensive_autogen_audit.py` | Reused Python selector mirror (stale, post-processed) |
| `supabase/functions/audit-autogen-workout/index.ts` | Multi-agent Claude reviewer |
| `Fit33/SmartExerciseSelectionEngine.swift` | Live Swift selector + `enum SpecialtyVariantFilter` mirror |
| `FITNESS_EXPERT_AGENT.md` | FE invariants (incl. specialty-variant rule) |
| `.cursor/agents/fitness-expert.md` | Short-form mirror of FE invariants |

---

## See also

- `FITNESS_EXPERT_AGENT.md` — invariant 24a (specialty variants).
- `PRODUCT_ENGINEER_AGENT.md` — autogen wiring + recommender ownership.
- `supabase/functions/audit-catalog-exercise/index.ts` — sister edge function
  whose architecture we copied (Anthropic prompt-caching, JSON salvage,
  service-role auth).
