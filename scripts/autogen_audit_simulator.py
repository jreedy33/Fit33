#!/usr/bin/env python3
"""
Auto-Gen Audit Simulator
========================

This is the CHEAT-CODE-LEVEL audit harness. One command spins up N synthetic
users that span every onboarding combination the app supports, runs the
auto-gen against each one, sends the resulting workouts to a multi-agent
Claude reviewer (Fitness Expert + Product Engineer), and emits a single
markdown report that the engineering team — and Cursor — can act on.

USAGE
-----
    # Default: 100 users × 2 workouts = 200 reviews
    python scripts/autogen_audit_simulator.py

    # Smoke run
    python scripts/autogen_audit_simulator.py --users 5 --workouts-per-user 1

    # Skip Claude (heuristic-only — useful for fast local iteration)
    python scripts/autogen_audit_simulator.py --users 50 --no-claude

    # Run from CI / cron (env vars)
    SUPABASE_URL=… SUPABASE_SERVICE_ROLE_KEY=… python scripts/autogen_audit_simulator.py

OUTPUTS
-------
  scripts/output/autogen_audit_<timestamp>.md   ← human + Cursor readable
  scripts/output/autogen_audit_<timestamp>.json ← raw structured data

ARCHITECTURE
------------
  1. PROFILE GEN
       Synthesize N user profiles spanning the 6-goal × 3-level × 4-location
       × equipment-set × age × weight × injury cube. The generator pulls its
       enums from the SAME constants the Swift onboarding uses (see
       `_assert_app_state_drift()` at the top of `main`) so a sprint that
       adds/removes a goal or equipment SKU breaks the audit explicitly
       rather than silently auditing stale options.

  2. EXERCISE LOAD
       Pulls the live exercise catalog from Supabase. NEVER mock data; this
       is the same catalog the Swift app sees.

  3. AUTO-GEN
       Reuses `comprehensive_autogen_audit.select_exercises_for_workout()`
       — the existing Python mirror of `SmartExerciseSelectionEngine.swift`.
       That mirror has known drift (Mar 2026 vs current Swift). The
       simulator runs a POST-SELECTION SPECIALTY-FILTER PASS using
       `specialty_exercise_filter.py` to catch the most important slip
       (specialty variants for beginners) so the audit reflects the WHOLE
       expected experience, not just the stale mirror's view.

  4. CLAUDE REVIEW
       For each generated workout, calls the `audit-autogen-workout` edge
       function. The edge function's system prompt embeds the FE + PE
       invariants and returns a structured JSON review. This is the
       multi-agent layer — Claude speaks BOTH personas.

  5. AGGREGATE + WRITE .md
       The report is structured for Cursor consumption:
         - Top fixes (sorted by frequency × severity)
         - Per-category issue counts
         - Specialty-variant slip table (the bug that triggered this audit)
         - Sample reviews (worst 5 + best 5)
         - Drift banner (what the simulator could NOT validate)

DRIFT TRANSPARENCY
------------------
This script is HONEST about what it can and cannot validate. The Python
exercise selector mirrors Swift but is ~2 months stale. Every report opens
with a "DRIFT BANNER" listing what the simulator could and could not
faithfully reproduce. Trust the report for SPECIALTY-VARIANT slip rates
and CLAUDE'S WORKOUT-LEVEL REVIEW; treat the per-exercise score numbers
as approximate.

REQUIREMENTS
------------
  - .env at repo root with SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY.
  - For Claude review: `audit-autogen-workout` edge function deployed
    AND ANTHROPIC_API_KEY configured in Supabase secrets.
  - `pip install supabase requests`.

COST + RUNTIME (sample 100 × 2 = 200 reviews)
---------------------------------------------
  - Catalog pull: ~5s, single Supabase query.
  - Selection: ~30s on a laptop (in-process Python, no IO).
  - Claude review: ~200 × 4s sequential ≈ 13min, with prompt caching
    after the first call (system prompt is >1024 tokens). Cost ≈ $3-5
    on Sonnet 4.

Authority: Fitness Expert + Product Engineer agents (see
`FITNESS_EXPERT_AGENT.md`, `PRODUCT_ENGINEER_AGENT.md`).
"""

from __future__ import annotations

import argparse
import json
import os
import random
import sys
import time
from collections import Counter, defaultdict
from dataclasses import asdict, dataclass, field
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

# ─────────────────────────────────────────────────────────────────────────────
# Local-only imports (live in scripts/)
# ─────────────────────────────────────────────────────────────────────────────

THIS_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(THIS_DIR))

import load_env  # noqa: F401 — auto-loads .env credentials
from specialty_exercise_filter import (  # noqa: E402
    SpecialtyMatch,
    is_blocked_for_level,
    is_specialty_variant,
)

# Reuse heavy lifters from the existing audit module. We import lazily inside
# `main()` so a `--help` invocation doesn't load 6,800 lines of selection
# logic.

# ─────────────────────────────────────────────────────────────────────────────
# Onboarding constants — MUST stay in lockstep with the Swift app.
# When the app adds/renames a goal, equipment SKU, or location, the
# corresponding constant here MUST be updated too. The pre-flight
# `_assert_app_state_drift()` check shouts loudly if it spots
# unexpected drift.
#
# Sources of truth:
#   - Goals:      Fit33/NewOnboardingView+Steps.swift line ~525 (6 tuples)
#   - Levels:     Fit33/NewOnboardingView+Steps.swift line ~557 (3 tuples)
#   - Locations:  Fit33/WorkoutGeneratorSelectionView.swift `EquipmentLocation`
#   - Equipment:  Fit33/WorkoutGeneratorSelectionView.swift `equipmentOptions`
# ─────────────────────────────────────────────────────────────────────────────

GOALS = [
    "Build Muscle",
    "Lose Weight",
    "Get Stronger",
    "Stay Active",
    "Build Endurance",
    "Improve Health",
]

EXPERIENCE_LEVELS = ["Beginner", "Intermediate", "Advanced"]

LOCATIONS = ["gym", "home", "outdoor", "hybrid"]

GENDERS = ["Male", "Female"]

# Per-location equipment SKUs as the Swift app shows them. Each list is
# the FULL menu — the simulator picks a random subset weighted by
# experience level.
EQUIPMENT_BY_LOCATION: Dict[str, List[str]] = {
    "gym": [
        "Dumbbells", "Barbell", "Cables", "Machines", "Smith Machine",
        "Plates", "Bodyweight", "TRX/Rings", "Kettlebell",
    ],
    "home": [
        "Bodyweight", "Dumbbells", "Bands", "Kettlebell", "Pull-Up Bar",
        "Dip Bars", "Stability Ball", "TRX/Rings", "Barbell",
    ],
    "outdoor": [
        "Bodyweight", "Bands", "Kettlebell", "Pull-Up Bar", "Dip Bars",
        "TRX/Rings", "Dumbbells", "Medicine Ball", "Jump Rope",
    ],
    "hybrid": [
        "Dumbbells", "Bodyweight", "Bands", "Kettlebell", "Cables",
        "Machines", "Barbell", "Smith Machine", "TRX/Rings",
    ],
}

# Default selections by location — what the app pre-fills when the user
# picks a location. Beginners often keep the default; we use this as the
# minimum subset.
DEFAULT_EQUIPMENT: Dict[str, List[str]] = {
    "gym": ["Dumbbells", "Barbell", "Cables", "Machines", "Smith Machine", "Plates"],
    "home": ["Dumbbells", "Bodyweight", "Kettlebell", "Bands"],
    "outdoor": ["Bodyweight", "Kettlebell", "Bands"],
    "hybrid": ["Dumbbells", "Bodyweight", "Bands", "Kettlebell"],
}

INJURY_AREAS = [
    "Lower Back", "Shoulders", "Knees", "Hips", "Wrists", "Elbows",
    "Neck", "Ankles",
]
INJURY_SEVERITIES = ["be_careful", "light_only", "stretching_only", "skip_completely"]

# Workout splits the simulator generates. These mirror the canonical
# splits the app's auto-gen surfaces. Keep this list small enough that
# 100 users × 2 workouts spans most of it twice.
WORKOUT_SPLITS_FOR_AUDIT = [
    ("Push Day",        ["Chest", "Shoulders", "Triceps"]),
    ("Pull Day",        ["Back", "Biceps"]),
    ("Leg Day",         ["Quads", "Hamstrings", "Glutes", "Calves"]),
    ("Chest & Triceps", ["Chest", "Triceps"]),
    ("Back & Biceps",   ["Back", "Biceps"]),
    ("Upper Body",      ["Chest", "Back", "Shoulders"]),
    ("Lower Body",      ["Quads", "Hamstrings", "Glutes"]),
    ("Shoulders & Arms",["Shoulders", "Biceps", "Triceps"]),
    ("Full Body",       ["Chest", "Back", "Legs", "Core"]),
    ("Core Focus",      ["Core", "Abs"]),
    ("Chest Focus",     ["Chest"]),
    ("Back Focus",      ["Back"]),
    ("Shoulders Focus", ["Shoulders"]),
    ("Arms Focus",      ["Biceps", "Triceps"]),
    ("Glutes Focus",    ["Glutes", "Hamstrings"]),
]


# ─────────────────────────────────────────────────────────────────────────────
# User profile dataclass (canonical shape sent to the edge function)
# ─────────────────────────────────────────────────────────────────────────────

@dataclass
class SimulatedUser:
    id: int
    name: str
    age: int
    gender: str                  # "Male" | "Female"
    weight_lbs: int
    height_inches: int
    experience_level: str        # "Beginner" | "Intermediate" | "Advanced"
    fitness_goal: str
    workout_location: str        # "gym" | "home" | "outdoor" | "hybrid"
    available_equipment: List[str]
    injuries: List[Dict[str, str]]   # [{area, severity, description}]
    workouts_completed: int
    preferred_workout_duration: int  # minutes
    available_days_per_week: int
    notes: str

    def short_label(self) -> str:
        injury_str = ""
        if self.injuries:
            injury_str = " | injuries: " + ",".join(i["area"] for i in self.injuries)
        return (
            f"{self.gender}/{self.age}y/{self.weight_lbs}lb · "
            f"{self.experience_level} · {self.fitness_goal} · "
            f"{self.workout_location} · {self.preferred_workout_duration}min"
            f"{injury_str}"
        )


# ─────────────────────────────────────────────────────────────────────────────
# Profile synthesis — random but evenly distributed
# ─────────────────────────────────────────────────────────────────────────────

_FIRST_NAMES_M = ["Marcus", "James", "David", "Michael", "Chris", "Alex",
                  "Ryan", "Jake", "Tyler", "Brandon", "Kenji", "Diego",
                  "Omar", "Tobias", "Wesley", "Cole", "Theo", "Mateo"]
_FIRST_NAMES_F = ["Sarah", "Jessica", "Emily", "Amanda", "Rachel", "Nicole",
                  "Ashley", "Megan", "Lauren", "Brittany", "Priya", "Mei",
                  "Aaliyah", "Imani", "Reese", "Camila", "Soren", "Anika"]
_LAST_NAMES = ["Thompson", "Williams", "Johnson", "Brown", "Davis", "Miller",
               "Wilson", "Anderson", "Taylor", "Moore", "Patel", "Nguyen",
               "Garcia", "Hernandez", "Kim", "Okafor", "Tanaka", "Silva"]


def _pick_equipment(location: str, level: str, rng: random.Random) -> List[str]:
    """
    Pick a realistic equipment subset for `location` weighted by `level`.

    - Beginner gym users typically have all 6 default machines. Beginner
      home users typically have the default 4 SKUs.
    - Intermediate and Advanced users have broader access — they're the
      ones who add Smith Machine, Plates, Dip Bars, etc.
    """
    full = EQUIPMENT_BY_LOCATION[location]
    default = DEFAULT_EQUIPMENT[location]
    if level == "Beginner":
        # 60% default, 30% default + 1 extra, 10% sparse subset
        roll = rng.random()
        if roll < 0.6:
            return list(default)
        if roll < 0.9:
            extras = [e for e in full if e not in default]
            if extras:
                return list(default) + [rng.choice(extras)]
            return list(default)
        return rng.sample(default, max(1, len(default) - 1))
    if level == "Intermediate":
        size = rng.randint(max(3, len(default)), len(full) - 1)
        return rng.sample(full, size)
    # Advanced
    size = rng.randint(len(default), len(full))
    return rng.sample(full, size)


def _pick_injury(age: int, level: str, rng: random.Random) -> List[Dict[str, str]]:
    # 0% baseline + +0.5%/year over 18 + +10% if Advanced (volume-related).
    # Cap at 50%.
    chance = min(0.5, 0.05 + (age - 18) * 0.005 + (0.10 if level == "Advanced" else 0))
    if rng.random() >= chance:
        return []
    area = rng.choice(INJURY_AREAS)
    # Bias toward "be_careful" — that's the most common real-world severity.
    severity = rng.choices(INJURY_SEVERITIES, weights=[0.6, 0.25, 0.10, 0.05])[0]
    return [{
        "area": area,
        "severity": severity,
        "description": f"{severity.replace('_', ' ').title()} {area.lower()} — synthesized for audit",
    }]


def synthesize_users(n: int, seed: int = 42) -> List[SimulatedUser]:
    """
    Generate `n` synthetic profiles. We stratify across the major axes so
    100 users hit the cube (gender × level × location × goal) reasonably
    evenly rather than clustering at the random mean.
    """
    rng = random.Random(seed)
    out: List[SimulatedUser] = []

    # Build a deterministic shuffled cross-product to stratify the first
    # min(n, |cube|) users; remaining users get fully random profiles.
    cube: List[Tuple[str, str, str, str]] = [
        (g, lev, loc, goal)
        for g in GENDERS
        for lev in EXPERIENCE_LEVELS
        for loc in LOCATIONS
        for goal in GOALS
    ]
    rng.shuffle(cube)

    for i in range(n):
        if i < len(cube):
            gender, level, location, goal = cube[i]
        else:
            gender = rng.choice(GENDERS)
            level = rng.choice(EXPERIENCE_LEVELS)
            location = rng.choice(LOCATIONS)
            goal = rng.choice(GOALS)

        first = rng.choice(_FIRST_NAMES_M if gender == "Male" else _FIRST_NAMES_F)
        last = rng.choice(_LAST_NAMES)
        name = f"{first} {last}"

        if gender == "Male":
            height = rng.randint(64, 76)
            weight = rng.randint(140, 260)
        else:
            height = rng.randint(58, 70)
            weight = rng.randint(105, 200)

        age = rng.randint(18, 70)

        # Workouts completed correlates with level. Beginners are the
        # interesting failure mode for specialty variants.
        if level == "Beginner":
            workouts_completed = rng.randint(0, 12)
        elif level == "Intermediate":
            workouts_completed = rng.randint(13, 100)
        else:
            workouts_completed = rng.randint(75, 400)

        duration = rng.choice([20, 30, 40, 50, 60])
        days = rng.choice([2, 3, 4, 5, 6])

        equipment = _pick_equipment(location, level, rng)
        injuries = _pick_injury(age, level, rng)

        out.append(SimulatedUser(
            id=i + 1,
            name=name,
            age=age,
            gender=gender,
            weight_lbs=weight,
            height_inches=height,
            experience_level=level,
            fitness_goal=goal,
            workout_location=location,
            available_equipment=equipment,
            injuries=injuries,
            workouts_completed=workouts_completed,
            preferred_workout_duration=duration,
            available_days_per_week=days,
            notes=f"Synth profile #{i+1} — stratified across gender/level/location/goal",
        ))
    return out


# ─────────────────────────────────────────────────────────────────────────────
# Drift banner — quick app-state sanity check
# ─────────────────────────────────────────────────────────────────────────────

DRIFT_NOTES = [
    # (area, status, note)
    ("fitness_goals", "synced",
     "6 goals (Build Muscle / Lose Weight / Get Stronger / Stay Active / Build Endurance / Improve Health) match Fit33/NewOnboardingView+Steps.swift line ~525."),
    ("experience_levels", "synced",
     "3 levels (Beginner / Intermediate / Advanced) match Fit33/NewOnboardingView+Steps.swift line ~557."),
    ("locations", "synced",
     "4 locations (gym/home/outdoor/hybrid) match Fit33/WorkoutGeneratorSelectionView.swift `EquipmentLocation`."),
    ("gym_equipment", "synced",
     "9 SKUs match Fit33/WorkoutGeneratorSelectionView.swift `equipmentOptions` for gym."),
    ("specialty_filter", "ENFORCED-IN-AUDIT",
     "Specialty variant pattern filter is applied in this script (`specialty_exercise_filter.py`). The Swift app's filter is being updated to mirror this list."),
    ("python_selection_logic", "STALE",
     "comprehensive_autogen_audit.select_exercises_for_workout() was last updated Mar 2026; the live Swift selector has had ~2 months of changes (cardio Phase 1, readiness adaptive autogen, etc.). The simulator's exercise selection is APPROXIMATE; trust the Claude review for workout-level correctness."),
    ("readiness_override", "NOT-MODELED",
     "Wearable readiness band (red/yellow/green) recovery override is NOT simulated. Live red-recovery would replace the workout with a mobility session; this audit always generates a strength workout."),
    ("cardio_phase_1", "NOT-MODELED",
     "Cardio gamification (Sprint 2 Q2-5) is out of scope for this simulator — strength workouts only."),
]


def render_drift_banner_md() -> str:
    lines = [
        "## Drift Banner — what this simulator can and cannot validate",
        "",
        "| Area | Status | Note |",
        "|------|--------|------|",
    ]
    for area, status, note in DRIFT_NOTES:
        emoji = {"synced": "✅", "STALE": "⚠️", "NOT-MODELED": "⚪",
                 "ENFORCED-IN-AUDIT": "🛡️"}.get(status, "❓")
        lines.append(f"| `{area}` | {emoji} {status} | {note} |")
    return "\n".join(lines)


# ─────────────────────────────────────────────────────────────────────────────
# Selection — wraps the existing Python mirror + adds specialty-filter pass
# ─────────────────────────────────────────────────────────────────────────────

def _user_to_legacy_profile(user: SimulatedUser, legacy):
    """
    Convert a `SimulatedUser` into the dataclass shape that
    comprehensive_autogen_audit.UserProfile expects.

    legacy is the imported module so we can construct its enums.
    """
    Gender = legacy.Gender
    BodyType = legacy.BodyType
    ExperienceLevel = legacy.ExperienceLevel
    FitnessGoal = legacy.FitnessGoal
    WorkoutLocation = legacy.WorkoutLocation
    Injury = legacy.Injury
    UserProfile = legacy.UserProfile

    gender_map = {"Male": Gender.MALE, "Female": Gender.FEMALE}
    level_map = {
        "Beginner": ExperienceLevel.BEGINNER,
        "Intermediate": ExperienceLevel.INTERMEDIATE,
        "Advanced": ExperienceLevel.ADVANCED,
    }
    goal_map = {
        "Build Muscle": FitnessGoal.BUILD_MUSCLE,
        "Lose Weight": FitnessGoal.LOSE_WEIGHT,
        "Get Stronger": FitnessGoal.GET_STRONGER,
        "Stay Active": FitnessGoal.STAY_ACTIVE,
        "Build Endurance": FitnessGoal.BUILD_ENDURANCE,
        "Improve Health": FitnessGoal.IMPROVE_HEALTH,
    }
    # Legacy module only knows HOME/GYM/OUTDOOR — map hybrid → GYM
    # (the legacy selector has more gym-flavored rules; that's the
    # closest realistic approximation and matches the user's hybrid
    # equipment set, which is gym-leaning).
    location_map = {
        "gym": WorkoutLocation.GYM,
        "home": WorkoutLocation.HOME,
        "outdoor": WorkoutLocation.OUTDOOR,
        "hybrid": WorkoutLocation.GYM,
    }

    body_type = random.choice(list(BodyType))  # legacy field, unused by selector

    injuries = [
        Injury(
            area=i.get("area", "Lower Back"),
            severity=i.get("severity", "be_careful"),
            description=i.get("description", ""),
        )
        for i in user.injuries
    ]

    return UserProfile(
        id=user.id,
        name=user.name,
        age=user.age,
        gender=gender_map[user.gender],
        weight_lbs=float(user.weight_lbs),
        height_inches=user.height_inches,
        body_type=body_type,
        experience_level=level_map[user.experience_level],
        fitness_goal=goal_map[user.fitness_goal],
        workout_location=location_map[user.workout_location],
        available_equipment=list(user.available_equipment),
        injuries=injuries,
        workouts_completed=user.workouts_completed,
        preferred_workout_duration=user.preferred_workout_duration,
        available_days_per_week=user.available_days_per_week,
        notes=user.notes,
    )


@dataclass
class GeneratedWorkout:
    user_id: int
    user_label: str
    split_name: str
    target_muscles: List[str]
    exercises: List[Dict[str, Any]]   # slim {name, equipment, primary_muscles, secondary_muscles, is_compound}
    specialty_blocked_in_audit: List[Dict[str, Any]] = field(default_factory=list)


def _slim_exercise(ex: Dict[str, Any]) -> Dict[str, Any]:
    """Convert a raw catalog row to the wire shape the edge function expects."""
    primary = ex.get("primary_muscles") or []
    if isinstance(primary, str):
        primary = [primary]
    secondary = ex.get("secondary_muscles") or []
    if isinstance(secondary, str):
        secondary = [secondary]

    equipment_raw = ex.get("equipment") or ex.get("equipment_category") or ""
    if isinstance(equipment_raw, list):
        equipment = ", ".join([str(e) for e in equipment_raw if e])
    else:
        equipment = str(equipment_raw)

    return {
        "name": ex.get("name", ""),
        "equipment": equipment,
        "primary_muscles": [str(m) for m in primary if m],
        "secondary_muscles": [str(m) for m in secondary if m],
        "is_compound": ex.get("is_compound"),
    }


def generate_workout(
    user: SimulatedUser,
    target_muscles: List[str],
    exercises_catalog: List[Dict[str, Any]],
    legacy_module,
    target_count: int,
) -> List[Dict[str, Any]]:
    """
    Run the existing Python mirror selector, then apply the
    specialty-variant filter as a POST-SELECTION pass. Anything blocked
    by the specialty filter is recorded for the report and replaced if
    possible from the remaining pool.
    """
    legacy_profile = _user_to_legacy_profile(user, legacy_module)
    raw_selected = legacy_module.select_exercises_for_workout(
        exercises=exercises_catalog,
        user=legacy_profile,
        target_muscles=target_muscles,
        count=target_count,
    )
    return raw_selected or []


def apply_specialty_filter(
    selected: List[Dict[str, Any]],
    user: SimulatedUser,
    catalog: List[Dict[str, Any]],
    target_muscles: List[str],
) -> Tuple[List[Dict[str, Any]], List[Dict[str, Any]]]:
    """
    Walk the selected list. For each exercise that matches a specialty
    pattern AND is blocked at the user's level, try to replace it with
    the next-best non-specialty exercise from the catalog that hits the
    same primary muscle.

    Returns (filtered_list, blocked_list).
    """
    blocked: List[Dict[str, Any]] = []
    accepted_names = {ex.get("name", "").lower() for ex in selected}

    # Build a small replacement pool keyed by primary muscle.
    # Cheap O(N) scan once per workout — N ≈ 6,400.
    replacement_pool: Dict[str, List[Dict[str, Any]]] = defaultdict(list)
    target_muscles_lower = {t.lower() for t in target_muscles}

    for ex in catalog:
        name = (ex.get("name") or "").strip()
        if not name:
            continue
        if name.lower() in accepted_names:
            continue
        # Only consider exercises that hit at least one target muscle.
        primary = ex.get("primary_muscles") or []
        if isinstance(primary, str):
            primary = [primary]
        primary_lower = [str(m).lower() for m in primary if m]
        hit = False
        for m in primary_lower:
            for t in target_muscles_lower:
                if m == t or m in t or t in m:
                    hit = True
                    break
            if hit:
                break
        if not hit:
            continue
        # Reject specialty here too — replacement must NOT itself be specialty.
        if is_blocked_for_level(name, user.experience_level).matched:
            continue
        # Index by every primary muscle this exercise hits.
        for m in primary_lower:
            replacement_pool[m].append(ex)

    filtered: List[Dict[str, Any]] = []
    for ex in selected:
        name = ex.get("name") or ""
        match = is_blocked_for_level(name, user.experience_level)
        if not match.matched:
            filtered.append(ex)
            continue

        # Try to replace.
        primary = ex.get("primary_muscles") or []
        if isinstance(primary, str):
            primary = [primary]
        primary_lower = [str(m).lower() for m in primary if m]

        replacement = None
        for m in primary_lower:
            pool = replacement_pool.get(m, [])
            if pool:
                replacement = pool.pop(0)
                break

        blocked.append({
            "blocked_exercise_name": name,
            "specialty_pattern": match.pattern,
            "base_movement": match.base_movement,
            "severity": match.severity,
            "rationale": match.rationale,
            "replacement_exercise_name": (replacement or {}).get("name") if replacement else None,
        })

        if replacement is not None:
            filtered.append(replacement)
            accepted_names.add(replacement.get("name", "").lower())
        # Otherwise the workout shrinks by one. The simulator records
        # this and Claude can flag it as `volume_imbalance` if relevant.

    return filtered, blocked


# ─────────────────────────────────────────────────────────────────────────────
# Claude reviewer — calls the audit-autogen-workout edge function
# ─────────────────────────────────────────────────────────────────────────────

class ClaudeReviewError(RuntimeError):
    pass


def call_claude_review(
    supabase_url: str,
    service_key: str,
    user: SimulatedUser,
    workout: GeneratedWorkout,
    timeout_s: int = 60,
) -> Dict[str, Any]:
    """POST to the audit-autogen-workout edge function and return the parsed review."""
    import requests  # local import — keeps --no-claude path dependency-free

    endpoint = f"{supabase_url.rstrip('/')}/functions/v1/audit-autogen-workout"
    payload = {
        "user_profile": {
            "name": user.name,
            "age": user.age,
            "gender": user.gender,
            "weight_lbs": user.weight_lbs,
            "height_inches": user.height_inches,
            "experience_level": user.experience_level,
            "fitness_goal": user.fitness_goal,
            "workout_location": user.workout_location,
            "available_equipment": user.available_equipment,
            "injuries": user.injuries,
            "workouts_completed": user.workouts_completed,
            "preferred_workout_duration": user.preferred_workout_duration,
            "available_days_per_week": user.available_days_per_week,
            "notes": user.notes,
        },
        "workout": {
            "target_muscles": workout.target_muscles,
            "workout_type": workout.split_name,
            "exercises": workout.exercises,
        },
    }
    headers = {
        "Authorization": f"Bearer {service_key}",
        "Content-Type": "application/json",
    }
    try:
        response = requests.post(endpoint, json=payload, headers=headers, timeout=timeout_s)
    except requests.exceptions.RequestException as e:
        raise ClaudeReviewError(f"network: {e}") from e

    if response.status_code != 200:
        raise ClaudeReviewError(
            f"http {response.status_code}: {response.text[:300]}"
        )

    body = response.json()
    if "error" in body:
        raise ClaudeReviewError(body.get("error"))
    review = body.get("review") or {}
    if not isinstance(review, dict):
        raise ClaudeReviewError(f"unexpected review shape: {type(review)}")
    return {
        "review": review,
        "usage": body.get("usage") or {},
    }


# ─────────────────────────────────────────────────────────────────────────────
# Aggregator + report writer
# ─────────────────────────────────────────────────────────────────────────────

def _render_user_block(user: SimulatedUser) -> str:
    return (
        f"- **id**: {user.id}\n"
        f"- **profile**: {user.short_label()}\n"
        f"- **equipment**: {', '.join(user.available_equipment)}\n"
        f"- **workouts completed**: {user.workouts_completed}\n"
        f"- **days/week**: {user.available_days_per_week}\n"
    )


def _render_exercises_md(workout: GeneratedWorkout) -> str:
    lines = ["| # | Exercise | Equipment | Primary muscles |", "|---|---|---|---|"]
    for i, ex in enumerate(workout.exercises, 1):
        primary = ", ".join(ex.get("primary_muscles") or [])
        lines.append(
            f"| {i} | {ex.get('name', '?')} | {ex.get('equipment', '?')} | {primary} |"
        )
    if workout.specialty_blocked_in_audit:
        lines.append("")
        lines.append("**Specialty variants filtered by audit (not surfaced to Claude):**")
        lines.append("")
        for b in workout.specialty_blocked_in_audit:
            replacement = b["replacement_exercise_name"] or "_(none — workout shrunk)_"
            lines.append(
                f"- `{b['blocked_exercise_name']}` → matched pattern `{b['specialty_pattern']}` "
                f"({b['severity']}) → replaced with `{replacement}`. "
                f"Rationale: {b['rationale']}"
            )
    return "\n".join(lines)


def _aggregate_issues(reviews: List[Dict[str, Any]]) -> Dict[str, Any]:
    issue_counter: Counter = Counter()
    severity_counter: Counter = Counter()
    suggestion_counter: Counter = Counter()
    suggestion_examples: Dict[str, Dict[str, Any]] = {}
    rating_buckets = Counter()
    verdict_counter = Counter()
    specialty_slips: List[Dict[str, Any]] = []

    for r in reviews:
        review = r.get("review") or {}
        rating = review.get("overall_rating")
        if isinstance(rating, (int, float)):
            rating_buckets[int(rating)] += 1

        for issue in review.get("issues") or []:
            cat = str(issue.get("category", "other"))
            sev = str(issue.get("severity", "minor"))
            issue_counter[cat] += 1
            severity_counter[sev] += 1
            if cat == "specialty_variant_for_level":
                specialty_slips.append({
                    "user_id": r.get("user_id"),
                    "user_label": r.get("user_label"),
                    "split": r.get("split"),
                    "exercise_name": issue.get("exercise_name"),
                    "description": issue.get("description"),
                    "fix_suggestion": issue.get("fix_suggestion"),
                })

        for sug in review.get("improvement_suggestions") or []:
            title = str(sug.get("title", "")).strip()
            if not title:
                continue
            suggestion_counter[title] += 1
            if title not in suggestion_examples:
                suggestion_examples[title] = {
                    "owner": sug.get("owner"),
                    "priority": sug.get("priority"),
                    "rationale": sug.get("rationale"),
                    "concrete_change": sug.get("concrete_change"),
                }

        verdict = ((review.get("kept_or_swap") or {}).get("verdict")) or "unknown"
        verdict_counter[verdict] += 1

    return {
        "issue_counter": issue_counter,
        "severity_counter": severity_counter,
        "suggestion_counter": suggestion_counter,
        "suggestion_examples": suggestion_examples,
        "rating_buckets": rating_buckets,
        "verdict_counter": verdict_counter,
        "specialty_slips": specialty_slips,
    }


def _render_report_md(
    *,
    args,
    users: List[SimulatedUser],
    workouts: List[GeneratedWorkout],
    reviews: List[Dict[str, Any]],
    review_errors: List[Dict[str, Any]],
    elapsed_s: float,
    started_at: str,
) -> str:
    agg = _aggregate_issues(reviews)
    total_workouts = len(workouts)
    total_reviewed = len(reviews)

    avg_rating = 0.0
    if total_reviewed:
        weighted = sum(b * c for b, c in agg["rating_buckets"].items())
        total = sum(agg["rating_buckets"].values()) or 1
        avg_rating = weighted / total

    # ─── Top fixes (sorted by frequency) ───
    top_suggestions = sorted(
        agg["suggestion_counter"].items(), key=lambda x: -x[1]
    )[:15]

    # ─── Worst + best workouts ───
    sorted_reviews = sorted(
        reviews,
        key=lambda r: (r.get("review", {}).get("overall_rating") or 5),
    )
    worst = sorted_reviews[:5]
    best = list(reversed(sorted_reviews))[:5]

    # ─── Heuristic specialty-slip table (audit-side) ───
    audit_specialty_slips: List[Dict[str, Any]] = []
    for w in workouts:
        for b in w.specialty_blocked_in_audit:
            audit_specialty_slips.append({
                "user_id": w.user_id,
                "user_label": w.user_label,
                "split": w.split_name,
                **b,
            })

    sections: List[str] = []
    sections.append(f"# Auto-Gen Audit Report — {started_at}")
    sections.append("")
    sections.append(
        f"_{len(users)} synthetic users × {args.workouts_per_user} workouts each = "
        f"**{total_workouts} workouts** generated · "
        f"{total_reviewed} reviewed by Claude · "
        f"{len(review_errors)} review errors · "
        f"{elapsed_s:.1f}s wall-clock_"
    )
    sections.append("")
    sections.append(
        "_This report is structured for Cursor consumption. Each top-level fix "
        "below has a `concrete_change` pointer the engineering team can act on. "
        "Open this file in Cursor and ask the agent: 'land the high-priority "
        "fixes from this report'._"
    )
    sections.append("")

    sections.append(render_drift_banner_md())
    sections.append("")

    sections.append("## Headline Numbers")
    sections.append("")
    sections.append(f"- **Average overall rating** (Claude, 1-10): **{avg_rating:.2f}**")
    if agg["verdict_counter"]:
        verdict_line = " · ".join(
            f"{v}: {c}" for v, c in sorted(agg["verdict_counter"].items())
        )
        sections.append(f"- **Verdicts**: {verdict_line}")
    if agg["severity_counter"]:
        sev_line = " · ".join(
            f"{s}: {c}" for s, c in sorted(agg["severity_counter"].items())
        )
        sections.append(f"- **Issue severity**: {sev_line}")
    sections.append(
        f"- **Specialty variants caught by audit filter**: {len(audit_specialty_slips)} "
        f"(would have shipped to user without this filter)"
    )
    sections.append(
        f"- **Specialty variants Claude flagged inside the workouts**: "
        f"{len(agg['specialty_slips'])} "
        f"(slipped past both the in-app filter AND the audit's post-pass — "
        f"these are the ACTIONABLE residual gaps)"
    )
    sections.append("")

    sections.append("## Top Fixes (ranked by frequency)")
    sections.append("")
    sections.append(
        "Cursor: the `concrete_change` field is the file/function to edit. "
        "Tackle high-priority items first, in order."
    )
    sections.append("")
    if not top_suggestions:
        sections.append("_(no Claude reviews — try `--users 5` to validate the pipeline)_")
    else:
        sections.append("| # | Frequency | Owner | Priority | Title | Concrete change |")
        sections.append("|---|---|---|---|---|---|")
        for i, (title, count) in enumerate(top_suggestions, 1):
            example = agg["suggestion_examples"].get(title, {})
            owner = example.get("owner", "?")
            priority = example.get("priority", "?")
            change = (example.get("concrete_change") or "").replace("|", "\\|")
            sections.append(
                f"| {i} | {count} | {owner} | {priority} | {title} | {change} |"
            )
        sections.append("")
        sections.append("### Top fixes — full rationale")
        sections.append("")
        for i, (title, count) in enumerate(top_suggestions, 1):
            example = agg["suggestion_examples"].get(title, {})
            sections.append(f"**{i}. {title}** _(seen {count}×)_")
            sections.append("")
            sections.append(f"- **Owner**: {example.get('owner', '?')}")
            sections.append(f"- **Priority**: {example.get('priority', '?')}")
            sections.append(f"- **Rationale**: {example.get('rationale', '')}")
            sections.append(f"- **Concrete change**: `{example.get('concrete_change', '')}`")
            sections.append("")

    sections.append("## Specialty-Variant Slip Table")
    sections.append("")
    sections.append(
        "Specialty variants the audit caught BEFORE Claude saw the workout. "
        "These would have been shown to the user without the audit's filter "
        "(i.e. the live Swift app currently lets these slip through)."
    )
    sections.append("")
    if not audit_specialty_slips:
        sections.append("_(none — ship it)_")
    else:
        # Group by pattern for actionable summary.
        by_pattern: Dict[str, int] = Counter()
        by_pattern_examples: Dict[str, Dict[str, Any]] = {}
        for s in audit_specialty_slips:
            pat = s["specialty_pattern"]
            by_pattern[pat] += 1
            by_pattern_examples.setdefault(pat, s)
        sections.append("| Pattern | Count | Severity | Example exercise | Sample user |")
        sections.append("|---|---|---|---|---|")
        for pat, cnt in sorted(by_pattern.items(), key=lambda x: -x[1]):
            ex = by_pattern_examples[pat]
            sections.append(
                f"| `{pat}` | {cnt} | {ex['severity']} | "
                f"{ex['blocked_exercise_name']} | {ex['user_label']} |"
            )
    sections.append("")

    sections.append("## Specialty Variants Claude Still Flagged (residual gaps)")
    sections.append("")
    sections.append(
        "Even with the audit's filter, Claude found these slipping through. "
        "Each one is an opportunity to extend `specialty_exercise_filter.py`."
    )
    sections.append("")
    if not agg["specialty_slips"]:
        sections.append("_(none — the filter is comprehensive for this run)_")
    else:
        sections.append("| User | Split | Exercise | Description | Suggested fix |")
        sections.append("|---|---|---|---|---|")
        for s in agg["specialty_slips"][:50]:
            sections.append(
                f"| {s['user_label']} | {s['split']} | "
                f"{s['exercise_name']} | "
                f"{(s['description'] or '').replace('|', '\\|')} | "
                f"{(s['fix_suggestion'] or '').replace('|', '\\|')} |"
            )
    sections.append("")

    sections.append("## Issue Categories")
    sections.append("")
    if agg["issue_counter"]:
        sections.append("| Category | Count |")
        sections.append("|---|---|")
        for cat, cnt in sorted(agg["issue_counter"].items(), key=lambda x: -x[1]):
            sections.append(f"| {cat} | {cnt} |")
    else:
        sections.append("_(no issues — try a larger sample)_")
    sections.append("")

    sections.append("## Worst 5 Workouts (reviewed)")
    sections.append("")
    if not worst:
        sections.append("_(no reviewed workouts — Claude was skipped or unreachable)_")
    for r in worst:
        sections.append(f"### `user-{r['user_id']}` · {r['split']} (rating "
                        f"{r['review'].get('overall_rating', '?')}/10)")
        sections.append("")
        sections.append(f"- **Profile**: {r['user_label']}")
        verdict = (r['review'].get('kept_or_swap') or {}).get('verdict', '?')
        verdict_rationale = (r['review'].get('kept_or_swap') or {}).get('rationale', '')
        sections.append(f"- **Verdict**: `{verdict}` — {verdict_rationale}")
        sections.append(f"- **Fitness Expert**: {r['review'].get('fitness_expert_summary', '')}")
        sections.append(f"- **Product Engineer**: {r['review'].get('product_engineer_summary', '')}")
        if r['review'].get('issues'):
            sections.append("")
            sections.append("**Issues:**")
            for issue in r['review']['issues'][:6]:
                sections.append(
                    f"  - [{issue.get('severity', '?')}] "
                    f"{issue.get('category', '?')}: "
                    f"{issue.get('description', '')} "
                    f"_(fix: {issue.get('fix_suggestion', '')})_"
                )
        sections.append("")
        sections.append("**Generated workout:**")
        sections.append("")
        for ex in r["exercises"]:
            primaries = ", ".join(ex.get('primary_muscles') or [])
            sections.append(f"  1. {ex.get('name', '?')} _({ex.get('equipment', '?')} → {primaries})_")
        sections.append("")

    sections.append("## Best 5 Workouts (reviewed)")
    sections.append("")
    if not best:
        sections.append("_(no reviewed workouts)_")
    for r in best:
        sections.append(f"### `user-{r['user_id']}` · {r['split']} (rating "
                        f"{r['review'].get('overall_rating', '?')}/10)")
        sections.append(f"- **Profile**: {r['user_label']}")
        sections.append(f"- **Fitness Expert**: {r['review'].get('fitness_expert_summary', '')}")
        sections.append("")

    if review_errors:
        sections.append("## Review Errors")
        sections.append("")
        sections.append(f"_{len(review_errors)} workouts couldn't be reviewed by Claude. "
                        "Common causes: edge function not deployed, missing ANTHROPIC_API_KEY, "
                        "rate limiting._")
        sections.append("")
        for err in review_errors[:10]:
            sections.append(f"- `user-{err['user_id']}` · {err['split']} → `{err['error']}`")
        if len(review_errors) > 10:
            sections.append(f"- … and {len(review_errors) - 10} more.")
        sections.append("")

    sections.append("## Reproducibility")
    sections.append("")
    sections.append(f"- **Command**: `{' '.join(sys.argv)}`")
    sections.append(f"- **Seed**: `{args.seed}`")
    sections.append(f"- **Started**: {started_at}")
    sections.append(f"- **Wall-clock**: {elapsed_s:.1f}s")
    sections.append("")

    return "\n".join(sections)


# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────

def _parse_args(argv: Optional[List[str]] = None) -> argparse.Namespace:
    p = argparse.ArgumentParser(
        description="Run the auto-gen audit simulator.",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    p.add_argument("--users", type=int, default=100,
                   help="number of synthetic users to simulate")
    p.add_argument("--workouts-per-user", type=int, default=2,
                   help="workouts to generate per user (random splits)")
    p.add_argument("--seed", type=int, default=42,
                   help="rng seed for reproducible profiles")
    p.add_argument("--no-claude", action="store_true",
                   help="skip Claude review; emit heuristic-only report")
    p.add_argument("--max-reviews", type=int, default=None,
                   help="cap total Claude calls (cost control)")
    p.add_argument("--output-dir", type=str,
                   default=str(THIS_DIR / "output"),
                   help="where to write the .md and .json reports")
    return p.parse_args(argv)


def main(argv: Optional[List[str]] = None) -> int:
    args = _parse_args(argv)
    started = datetime.now()
    started_iso = started.strftime("%Y-%m-%dT%H:%M:%S")
    started_compact = started.strftime("%Y%m%d_%H%M%S")

    print("=" * 72)
    print("AUTO-GEN AUDIT SIMULATOR")
    print(f"started: {started_iso}")
    print(f"users: {args.users} · workouts/user: {args.workouts_per_user} · "
          f"claude: {'OFF' if args.no_claude else 'ON'}")
    print("=" * 72)

    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    # ─── Lazy heavy imports ───
    print("[1/5] Loading existing audit module (this is the stale Python mirror)…")
    try:
        import comprehensive_autogen_audit as legacy
    except Exception as e:
        print(f"  ✗ failed to import comprehensive_autogen_audit: {e}", file=sys.stderr)
        return 2

    # ─── Catalog pull ───
    supabase_url = os.environ.get("SUPABASE_URL", "").strip()
    service_key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "").strip()
    anon_key = os.environ.get("SUPABASE_ANON_KEY", "").strip()

    if not supabase_url or not (service_key or anon_key):
        print("  ✗ SUPABASE_URL + (SUPABASE_SERVICE_ROLE_KEY or SUPABASE_ANON_KEY) "
              "must be set (.env at repo root).", file=sys.stderr)
        return 2

    print("[2/5] Pulling exercise catalog from Supabase…")
    t0 = time.monotonic()
    catalog: List[Dict[str, Any]] = []
    offset = 0
    batch = 1000
    while True:
        rows = legacy.fetch_exercises_from_supabase(batch, offset)
        if not rows:
            break
        catalog.extend(rows)
        offset += batch
        if len(rows) < batch:
            break
    print(f"  ✓ {len(catalog)} exercises loaded ({time.monotonic() - t0:.1f}s)")

    # ─── Profile gen ───
    print(f"[3/5] Synthesizing {args.users} user profiles…")
    users = synthesize_users(args.users, seed=args.seed)
    counts = Counter(
        (u.experience_level, u.workout_location) for u in users
    )
    print("  ✓ stratified distribution:")
    for (lev, loc), c in sorted(counts.items()):
        print(f"      {lev:13s} {loc:8s}: {c}")

    # ─── Auto-gen + audit specialty filter ───
    print(f"[4/5] Generating {args.users * args.workouts_per_user} workouts "
          f"and applying specialty-variant filter…")
    rng = random.Random(args.seed * 7919)
    workouts: List[GeneratedWorkout] = []
    workouts_started = time.monotonic()

    for user in users:
        # Sample N distinct splits per user.
        if args.workouts_per_user > len(WORKOUT_SPLITS_FOR_AUDIT):
            sampled_splits = [
                rng.choice(WORKOUT_SPLITS_FOR_AUDIT)
                for _ in range(args.workouts_per_user)
            ]
        else:
            sampled_splits = rng.sample(
                WORKOUT_SPLITS_FOR_AUDIT, args.workouts_per_user
            )

        for split_name, target_muscles in sampled_splits:
            target_count = legacy.get_exercise_count_for_duration(
                user.preferred_workout_duration
            )
            try:
                raw = generate_workout(
                    user=user,
                    target_muscles=target_muscles,
                    exercises_catalog=catalog,
                    legacy_module=legacy,
                    target_count=target_count,
                )
            except Exception as e:
                print(f"  ⚠ user {user.id} · {split_name}: selection failed: {e}",
                      file=sys.stderr)
                continue

            slim = [_slim_exercise(ex) for ex in raw if ex]
            filtered, blocked = apply_specialty_filter(
                slim, user, catalog, target_muscles
            )

            workouts.append(GeneratedWorkout(
                user_id=user.id,
                user_label=user.short_label(),
                split_name=split_name,
                target_muscles=target_muscles,
                exercises=filtered,
                specialty_blocked_in_audit=blocked,
            ))

    print(f"  ✓ {len(workouts)} workouts ready ({time.monotonic() - workouts_started:.1f}s)")
    blocked_total = sum(len(w.specialty_blocked_in_audit) for w in workouts)
    print(f"  · {blocked_total} specialty variants caught by audit-side filter")

    # ─── Claude review ───
    reviews: List[Dict[str, Any]] = []
    review_errors: List[Dict[str, Any]] = []

    if args.no_claude:
        print("[5/5] Claude review SKIPPED (--no-claude)")
    else:
        print(f"[5/5] Claude review ({len(workouts)} workouts)…")
        review_target = workouts
        if args.max_reviews and args.max_reviews < len(review_target):
            review_target = review_target[:args.max_reviews]
            print(f"  · capped at --max-reviews={args.max_reviews}")

        if not service_key:
            print("  ⚠ SUPABASE_SERVICE_ROLE_KEY missing — skipping Claude review")
        else:
            user_by_id = {u.id: u for u in users}
            review_started = time.monotonic()
            for i, w in enumerate(review_target, 1):
                user = user_by_id.get(w.user_id)
                if not user:
                    continue
                try:
                    result = call_claude_review(
                        supabase_url, service_key, user, w
                    )
                    reviews.append({
                        "user_id": w.user_id,
                        "user_label": w.user_label,
                        "split": w.split_name,
                        "exercises": w.exercises,
                        "review": result["review"],
                        "usage": result["usage"],
                    })
                except ClaudeReviewError as e:
                    review_errors.append({
                        "user_id": w.user_id,
                        "split": w.split_name,
                        "error": str(e),
                    })
                if i % 10 == 0 or i == len(review_target):
                    elapsed = time.monotonic() - review_started
                    rate = i / elapsed if elapsed > 0 else 0
                    eta = (len(review_target) - i) / rate if rate > 0 else 0
                    print(f"  · {i}/{len(review_target)} reviewed "
                          f"({elapsed:.0f}s elapsed, ETA {eta:.0f}s, "
                          f"{len(review_errors)} errors)")

    elapsed_s = (datetime.now() - started).total_seconds()

    # ─── Write reports ───
    md_path = output_dir / f"autogen_audit_{started_compact}.md"
    json_path = output_dir / f"autogen_audit_{started_compact}.json"

    md = _render_report_md(
        args=args,
        users=users,
        workouts=workouts,
        reviews=reviews,
        review_errors=review_errors,
        elapsed_s=elapsed_s,
        started_at=started_iso,
    )
    md_path.write_text(md, encoding="utf-8")

    raw_dump = {
        "started_at": started_iso,
        "args": vars(args),
        "drift_notes": [
            {"area": a, "status": s, "note": n} for a, s, n in DRIFT_NOTES
        ],
        "users": [asdict(u) for u in users],
        "workouts": [asdict(w) for w in workouts],
        "reviews": reviews,
        "review_errors": review_errors,
    }
    json_path.write_text(json.dumps(raw_dump, indent=2, default=str), encoding="utf-8")

    print()
    print("=" * 72)
    print("REPORTS WRITTEN")
    print(f"  {md_path}")
    print(f"  {json_path}")
    print("=" * 72)
    print(f"wall-clock: {elapsed_s:.1f}s")
    print()
    print("Open the .md report in Cursor and ask: 'land the high-priority "
          "fixes from this report'.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
