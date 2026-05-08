#!/usr/bin/env python3
"""
Swift Auto-Gen Harness Bridge
==============================

Drives the *real* iOS auto-gen via the Fit33Tests XCTest target
(`Fit33Tests/AutogenAuditHarnessTests.swift`). This replaces the stale
Python mirror in `comprehensive_autogen_audit.py` so the audit grades the
exact code that ships in the app.

Workflow
--------
    1. (One-time per repo state) `xcodebuild build-for-testing` → produces
       a Fit33Tests.xctest bundle + a `.xctestrun` plist.
    2. Inject `FIT33_AUDIT_INPUT_PATH` / `FIT33_AUDIT_OUTPUT_PATH` into the
       `.xctestrun` `EnvironmentVariables` dict via `plutil`. (xcodebuild
       does NOT forward shell env vars into the simulator process — this
       is the only reliable mechanism.)
    3. Write batch JSON to `FIT33_AUDIT_INPUT_PATH`.
    4. `xcodebuild test-without-building -xctestrun … -only-testing:…
       AutogenAuditHarnessTests/testRunBatchFromFile`.
    5. Read batch results from `FIT33_AUDIT_OUTPUT_PATH`.
    6. Convert each result row to the slim shape the existing audit
       pipeline / Claude reviewer expects.

The XCTest harness side is `Fit33Tests/AutogenAuditHarnessTests.swift`.
Both sides share an `InputBatch` / `OutputBatch` shape — keep them in
sync if you change either.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_DERIVED_DATA = Path("/tmp/fit33-audit-DD")
DEFAULT_DESTINATION = (
    "platform=iOS Simulator,id=A9B2B054-9ACB-4831-8CEF-3B3A216587B4"
)
TEST_TARGET = (
    "Fit33Tests/AutogenAuditHarnessTests/testRunBatchFromFile"
)


# ─────────────────────────────────────────────────────────────────────────────
# Wire-shape DTOs (mirror Fit33Tests/AutogenAuditHarnessTests.swift)
# ─────────────────────────────────────────────────────────────────────────────

@dataclass
class HarnessInputWorkout:
    primary_muscles: List[str]
    secondary_muscles: List[str]
    count: int

    def to_dict(self) -> Dict[str, Any]:
        return {
            "primaryMuscles": self.primary_muscles,
            "secondaryMuscles": self.secondary_muscles,
            "count": self.count,
        }


@dataclass
class HarnessInputUser:
    name: str
    age: int
    gender: str
    weight_lbs: float
    experience_level: str
    fitness_goal: str
    workout_environment: str
    equipment: List[str]
    completed_workout_count: int
    workouts: List[HarnessInputWorkout]

    def to_dict(self) -> Dict[str, Any]:
        return {
            "name": self.name,
            "age": int(self.age),
            "gender": self.gender,
            "weightLbs": float(self.weight_lbs),
            "experienceLevel": self.experience_level,
            "fitnessGoal": self.fitness_goal,
            "workoutEnvironment": self.workout_environment,
            "equipment": list(self.equipment),
            "completedWorkoutCount": int(self.completed_workout_count),
            "workouts": [w.to_dict() for w in self.workouts],
        }


# ─────────────────────────────────────────────────────────────────────────────
# Build / test orchestration
# ─────────────────────────────────────────────────────────────────────────────

def find_xctestrun(derived_data: Path) -> Optional[Path]:
    """Return the xctestrun plist xcodebuild emits after build-for-testing."""
    candidates = list((derived_data / "Build" / "Products").glob("*.xctestrun"))
    return candidates[0] if candidates else None


def build_for_testing(
    derived_data: Path = DEFAULT_DERIVED_DATA,
    destination: str = DEFAULT_DESTINATION,
    scheme: str = "Fit33",
    quiet: bool = False,
) -> Path:
    """
    Run `xcodebuild build-for-testing` once per repo state. Returns the
    path to the resulting `.xctestrun` plist. Subsequent test runs can use
    `test-without-building -xctestrun <path>` for ~30× speed-up over a full
    build.

    Cold build wall-clock: ~3 min. Warm (cached): ~10s.
    """
    cmd = [
        "xcodebuild",
        "build-for-testing",
        "-scheme", scheme,
        "-destination", destination,
        "-derivedDataPath", str(derived_data),
    ]
    print(f"  · xcodebuild build-for-testing (target=Fit33Tests, dest={destination[-37:]})")
    t0 = time.monotonic()
    proc = subprocess.run(
        cmd,
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
    )
    elapsed = time.monotonic() - t0
    if proc.returncode != 0:
        # Print last 80 lines of stderr/stdout for debug
        tail = "\n".join(
            (proc.stdout + proc.stderr).splitlines()[-80:]
        )
        raise RuntimeError(
            f"xcodebuild build-for-testing failed (exit {proc.returncode}, {elapsed:.1f}s):\n{tail}"
        )

    xctestrun = find_xctestrun(derived_data)
    if xctestrun is None:
        raise RuntimeError(
            f"build-for-testing succeeded but no .xctestrun found under "
            f"{derived_data / 'Build' / 'Products'}"
        )
    if not quiet:
        print(f"  ✓ xctestrun ready: {xctestrun} ({elapsed:.1f}s)")
    return xctestrun


def patch_xctestrun_env(
    xctestrun: Path,
    env: Dict[str, str],
) -> None:
    """
    Inject env vars into the xctestrun's TestConfigurations.0.TestTargets.0
    .EnvironmentVariables dict via `plutil`. Idempotent — replaces existing
    keys cleanly.
    """
    base = "TestConfigurations.0.TestTargets.0.EnvironmentVariables"
    for key, value in env.items():
        # Try `replace` first (idempotent), fall back to `insert` if the
        # key doesn't exist yet.
        path = f"{base}.{key}"
        replace = subprocess.run(
            ["plutil", "-replace", path, "-string", value, str(xctestrun)],
            capture_output=True, text=True,
        )
        if replace.returncode != 0:
            insert = subprocess.run(
                ["plutil", "-insert", path, "-string", value, str(xctestrun)],
                capture_output=True, text=True,
            )
            if insert.returncode != 0:
                raise RuntimeError(
                    f"plutil failed to set {path} on {xctestrun}:\n"
                    f"  replace stderr: {replace.stderr}\n"
                    f"  insert  stderr: {insert.stderr}"
                )


def run_harness(
    users: List[HarnessInputUser],
    xctestrun: Path,
    destination: str = DEFAULT_DESTINATION,
    input_path: Optional[Path] = None,
    output_path: Optional[Path] = None,
    timeout_s: float = 1800,
) -> Dict[str, Any]:
    """
    Execute the AutogenAuditHarnessTests test method against the given
    user batch. Returns the parsed `OutputBatch` dict.
    """
    if input_path is None:
        input_path = Path("/tmp/fit33_audit_input.json")
    if output_path is None:
        output_path = Path("/tmp/fit33_audit_output.json")

    # Write input batch.
    batch = {"users": [u.to_dict() for u in users]}
    input_path.write_text(json.dumps(batch))
    if output_path.exists():
        output_path.unlink()

    # Inject env vars into xctestrun.
    patch_xctestrun_env(
        xctestrun,
        {
            "FIT33_AUDIT_INPUT_PATH": str(input_path),
            "FIT33_AUDIT_OUTPUT_PATH": str(output_path),
        },
    )

    # Run the harness test.
    cmd = [
        "xcodebuild", "test-without-building",
        "-xctestrun", str(xctestrun),
        "-only-testing:" + TEST_TARGET,
        "-destination", destination,
    ]
    total_workouts = sum(len(u.workouts) for u in users)
    print(
        f"  · xcodebuild test-without-building "
        f"({len(users)} users · {total_workouts} workouts)"
    )
    t0 = time.monotonic()
    proc = subprocess.run(
        cmd,
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
        timeout=timeout_s,
    )
    elapsed = time.monotonic() - t0

    if proc.returncode != 0:
        tail = "\n".join(
            (proc.stdout + proc.stderr).splitlines()[-60:]
        )
        raise RuntimeError(
            f"xcodebuild test failed (exit {proc.returncode}, {elapsed:.1f}s):\n{tail}"
        )

    if not output_path.exists():
        # The harness may have skipped silently (env vars missing) — show
        # the AutogenAudit lines from the test log to help debug.
        print("\n  ⚠ Output JSON missing — harness logs:")
        for line in (proc.stdout + proc.stderr).splitlines():
            if "AutogenAudit" in line or "FIT33" in line or "Test Case" in line:
                print(f"    {line}")
        raise RuntimeError(
            f"Harness did not write output JSON to {output_path}. "
            f"Check that AutogenAuditHarnessTests/testRunBatchFromFile "
            f"actually executed (look for [AutogenAudit] log lines above)."
        )

    print(f"  ✓ harness done ({elapsed:.1f}s, {total_workouts} workouts)")
    return json.loads(output_path.read_text())


# ─────────────────────────────────────────────────────────────────────────────
# Convenience: the slim {name, equipment, primary_muscles, ...} shape
# the existing audit pipeline expects on each generated exercise
# ─────────────────────────────────────────────────────────────────────────────

def slim_exercise_from_harness_row(row: Dict[str, Any]) -> Dict[str, Any]:
    """
    The Swift `GeneratedExercise` Codable encodes with these keys:
      id, name, primary_muscle, primary_body_region, secondary_muscles,
      equipment, category, difficulty, instructions
    Convert to the slim wire-shape the audit + Claude reviewer expect.
    """
    primary_muscle = row.get("primary_muscle") or ""
    primary_muscles = [primary_muscle] if primary_muscle else []
    secondary = row.get("secondary_muscles") or []
    if isinstance(secondary, str):
        secondary = [secondary]
    return {
        "name": row.get("name", ""),
        "equipment": row.get("equipment", ""),
        "primary_muscles": primary_muscles,
        "secondary_muscles": [str(m) for m in secondary if m],
        "is_compound": None,  # not surfaced by GeneratedExercise — defer
    }


# ─────────────────────────────────────────────────────────────────────────────
# CLI entry — for ad-hoc debugging
# ─────────────────────────────────────────────────────────────────────────────

def _smoke_test() -> int:
    print("Running smoke test (1 user, 1 workout)…")
    user = HarnessInputUser(
        name="Smoke-User",
        age=30,
        gender="Male",
        weight_lbs=180.0,
        experience_level="Intermediate",
        fitness_goal="Build Muscle",
        workout_environment="Gym",
        equipment=["Dumbbells", "Barbell", "Bench", "Cable", "Machine"],
        completed_workout_count=12,
        workouts=[
            HarnessInputWorkout(
                primary_muscles=["Chest", "Triceps"],
                secondary_muscles=[],
                count=6,
            )
        ],
    )

    xctestrun = find_xctestrun(DEFAULT_DERIVED_DATA)
    if xctestrun is None:
        print("(no xctestrun found, building…)")
        xctestrun = build_for_testing(DEFAULT_DERIVED_DATA)

    result = run_harness([user], xctestrun)
    workouts = result["results"][0]["workouts"]
    print(f"\nGenerated {sum(len(w['exercises']) for w in workouts)} exercises:")
    for w in workouts:
        for ex in w["exercises"]:
            print(f"  · {ex['name']} ({ex.get('equipment', '?')})")
    return 0


if __name__ == "__main__":
    sys.exit(_smoke_test())
