"""
swift_rubric_grader.py — drive Fit33Tests/WorkoutQualityTests against the
already-generated harness OutputBatch and pull back per-rule violation
stats.

This is the deterministic, Claude-free arm of the audit (mirrors
WORKOUT_QUALITY_RUBRIC.md). Run AFTER swift_autogen_harness.run_harness()
to grade the workouts it produced. Per-rule pass rates surface in the
audit .md so we can see mechanical convergence round-over-round.

USAGE (from the orchestrator):
    from swift_rubric_grader import run_rubric_grader

    rubric = run_rubric_grader(
        xctestrun=xctestrun,
        input_path=harness_output_json,   # the OutputBatch from the harness
        output_path=Path("/tmp/fit33_rubric.json"),
    )

    rubric["mechanical_rating_avg"]  →  e.g. 6.42
    rubric["per_rule"]["specialty_variant_for_level"]["pass_rate"]  →  0.985
"""

from __future__ import annotations

import json
import subprocess
import time
from pathlib import Path
from typing import Any, Dict, Optional

REPO_ROOT = Path(__file__).resolve().parents[1]
TEST_METHOD = "Fit33Tests/WorkoutQualityTests/testGradeBatchAgainstRubric"


def patch_xctestrun_env(xctestrun: Path, env: Dict[str, str]) -> None:
    """Idempotently set env vars on TestConfigurations.0.TestTargets.0 via plutil."""
    base = "TestConfigurations.0.TestTargets.0.EnvironmentVariables"
    for key, value in env.items():
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


def run_rubric_grader(
    xctestrun: Path,
    input_path: Path,
    output_path: Optional[Path] = None,
    destination: str = "platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4",
    timeout_s: float = 600,
) -> Dict[str, Any]:
    """
    Execute WorkoutQualityTests against the harness OutputBatch JSON and
    return the parsed rubric report. Fully deterministic — no LLM.

    Args:
        xctestrun: same .xctestrun the harness used (re-uses build cache).
        input_path: harness OutputBatch JSON (the workouts to grade).
        output_path: where the rubric test should write its report.
        destination: same simulator the harness ran on.

    Returns:
        Parsed rubric.json dict with keys:
          - rubric_version
          - total_workouts, total_users
          - per_rule: { rule_name → { violation_count, workouts_affected,
                                       total_penalty, pass_rate } }
          - mechanical_rating_avg
          - workouts_with_zero_violations

    Raises:
        RuntimeError if xcodebuild fails or the output file is missing.
    """
    if output_path is None:
        output_path = Path("/tmp/fit33_rubric.json")
    if output_path.exists():
        output_path.unlink()

    patch_xctestrun_env(
        xctestrun,
        {
            "FIT33_RUBRIC_INPUT_PATH": str(input_path),
            "FIT33_RUBRIC_OUTPUT_PATH": str(output_path),
        },
    )

    cmd = [
        "xcodebuild", "test-without-building",
        "-xctestrun", str(xctestrun),
        "-only-testing:" + TEST_METHOD,
        "-destination", destination,
    ]
    print(f"  · rubric grader: xcodebuild → WorkoutQualityTests")
    t0 = time.monotonic()
    proc = subprocess.run(
        cmd, cwd=REPO_ROOT, capture_output=True, text=True, timeout=timeout_s
    )
    elapsed = time.monotonic() - t0

    if proc.returncode != 0:
        tail = "\n".join((proc.stdout + proc.stderr).splitlines()[-40:])
        raise RuntimeError(
            f"WorkoutQualityTests failed (exit {proc.returncode}, {elapsed:.1f}s):\n{tail}"
        )

    if not output_path.exists():
        for line in (proc.stdout + proc.stderr).splitlines():
            if "WorkoutQuality" in line or "FIT33_RUBRIC" in line:
                print(f"    {line}")
        raise RuntimeError(
            f"Rubric grader did not write output JSON to {output_path}. "
            f"Test may have skipped (env vars missing) or failed silently."
        )

    rubric = json.loads(output_path.read_text())
    print(
        f"  · rubric: mechanical_avg={rubric.get('mechanical_rating_avg')} "
        f"zero-violation={rubric.get('workouts_with_zero_violations')}/{rubric.get('total_workouts')} "
        f"({elapsed:.1f}s)"
    )
    return rubric


def render_rubric_md(rubric: Dict[str, Any]) -> str:
    """
    Render a markdown section summarising the rubric report. Drops into
    the audit .md right under the headline metrics.
    """
    if not rubric:
        return ""
    lines = []
    lines.append("## Mechanical Rubric Grader (deterministic, LLM-free)")
    lines.append("")
    lines.append(
        f"Source of truth: `WORKOUT_QUALITY_RUBRIC.md` v{rubric.get('rubric_version','?')}. "
        f"Grades the same `{rubric.get('total_workouts')}` workouts the Claude audit reviewed, "
        f"but using mechanical Swift checks only — runs in ~30s vs. Claude's ~80m, "
        f"and is fully reproducible round-over-round."
    )
    lines.append("")
    lines.append(f"**Mechanical rating avg**: `{rubric.get('mechanical_rating_avg')} / 10`  ")
    lines.append(
        f"**Zero-violation workouts**: "
        f"`{rubric.get('workouts_with_zero_violations')} / {rubric.get('total_workouts')}` "
        f"(`{(rubric.get('workouts_with_zero_violations', 0) / max(1, rubric.get('total_workouts', 1)) * 100):.1f}%`)"
    )
    lines.append("")
    lines.append("### Per-rule pass rates")
    lines.append("")
    lines.append("| Rule | Pass rate | Workouts affected | Total penalty |")
    lines.append("|---|---:|---:|---:|")
    per = rubric.get("per_rule", {}) or {}
    # Sort by total_penalty desc — biggest rating drain first
    for rule, stat in sorted(per.items(), key=lambda kv: -kv[1].get("total_penalty", 0)):
        pr = stat.get("pass_rate", 0)
        pr_pct = f"{pr * 100:.1f}%"
        pen = stat.get("total_penalty", 0)
        wf = stat.get("workouts_affected", 0)
        lines.append(f"| `{rule}` | {pr_pct} | {wf} | {pen:.1f} |")
    lines.append("")
    lines.append(
        "_Per WORKOUT_QUALITY_RUBRIC.md: each rule we drive to `pass_rate=100%` "
        "locks in a permanent rating gain. Focus fixes on highest-penalty rules first._"
    )
    lines.append("")
    return "\n".join(lines)


if __name__ == "__main__":
    # Smoke test — assumes /tmp/fit33_audit_output.json exists from a prior harness run.
    import sys
    sys.path.insert(0, str(Path(__file__).parent))
    import load_env  # noqa: F401
    from swift_autogen_harness import find_xctestrun, DEFAULT_DERIVED_DATA

    xctestrun = find_xctestrun(DEFAULT_DERIVED_DATA)
    if xctestrun is None:
        print("ERROR: no xctestrun cached. Run the harness first.")
        sys.exit(1)

    input_p = Path("/tmp/fit33_audit_output.json")
    if not input_p.exists():
        print(f"ERROR: {input_p} missing — run the harness first.")
        sys.exit(1)

    r = run_rubric_grader(xctestrun=xctestrun, input_path=input_p)
    print(json.dumps(r, indent=2))
