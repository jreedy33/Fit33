#!/usr/bin/env python3
"""
Logic Audit Verification Script
Verifies that all fixes from the March 2026 Logic Audit are in place.
Run from project root: python3 scripts/logic_audit_verify.py
"""

import os
import re
import sys

SWIFT_DIR = "Fit33"
PASS = 0
FAIL = 0


def check(name, passed, detail=""):
    global PASS, FAIL
    status = "PASS" if passed else "FAIL"
    if not passed:
        FAIL += 1
    else:
        PASS += 1
    print(f"  [{status}] {name}" + (f" -- {detail}" if detail else ""))


def read_file(path):
    try:
        with open(path, "r") as f:
            return f.read()
    except Exception:
        return None


def file_exists(path):
    return os.path.exists(path)


def count_pattern_in_file(filepath, pattern):
    content = read_file(filepath)
    if content is None:
        return -1
    return len(re.findall(pattern, content))


def main():
    global PASS, FAIL

    print("\n=== Logic Audit Verification ===\n")

    # --- Critical Bugs ---
    print("Critical Bugs:")

    # BUG-01: No "profile2: Any" in CollaborativeLearningEngine
    f = os.path.join(SWIFT_DIR, "CollaborativeLearningEngine.swift")
    content = read_file(f)
    check(
        "BUG-01: No 'Any' parameter in calculateSimilarity",
        content is not None and "profile2: Any" not in content,
        f,
    )

    # BUG-03: Parentheses around calf/raise OR
    f = os.path.join(SWIFT_DIR, "SmartExercisePairingEngine.swift")
    content = read_file(f)
    if content:
        has_parens = (
            '(nameLower.contains("calf") || nameLower.contains("raise"))' in content
        )
        check("BUG-03: Operator precedence parentheses present", has_parens, f)

    # BUG-04: No duplicate PerformanceMonitor (should be DebugPerformanceMonitor)
    f = os.path.join(SWIFT_DIR, "PerformanceOptimizer.swift")
    content = read_file(f)
    check(
        "BUG-04: PerformanceMonitor renamed to DebugPerformanceMonitor",
        content is not None
        and "class DebugPerformanceMonitor" in content
        and "class PerformanceMonitor" not in content,
        f,
    )

    # BUG-06: No "pending" in challenge progress guard
    f = os.path.join(SWIFT_DIR, "ChallengeService.swift")
    content = read_file(f)
    bug06_pass = False
    if content and "logProgressFromSource" in content:
        after_func = content.split("logProgressFromSource", 1)[1]
        func_body = after_func.split("func ")[0] if "func " in after_func else after_func
        bug06_pass = 'status == "pending"' not in func_body
    check("BUG-06: No pending status in progress guard", bug06_pass, f)

    # BUG-09: ForceExerciseRefresh delegates to ExerciseLibraryService
    f = os.path.join(SWIFT_DIR, "ForceExerciseRefresh.swift")
    content = read_file(f)
    check(
        "BUG-09: ForceExerciseRefresh uses ExerciseLibraryService",
        content is not None and "ExerciseLibraryService" in content,
        f,
    )
    check(
        "BUG-09: ForceExerciseRefresh no direct SupabaseManager.shared.fetchAllExercises",
        content is not None and "fetchAllExercises" not in content,
        f,
    )

    # BUG-11: No hardcoded willAutoRenew: true (check it reads renewalInfo)
    f = os.path.join(SWIFT_DIR, "StoreKitManager.swift")
    content = read_file(f)
    check(
        "BUG-11: StoreKit reads renewalInfo",
        content is not None and "renewalinfo" in content.lower() if content else False,
        f,
    )

    # --- Security ---
    print("\nSecurity:")

    # SEC-01: KeychainHelper exists
    check(
        "SEC-01: KeychainHelper.swift exists",
        file_exists(os.path.join(SWIFT_DIR, "KeychainHelper.swift")),
    )

    # SEC-01: No UserDefaults tokens in Fitbit/Strava
    for service in ["FitbitService.swift", "FitbitSettingsView.swift"]:
        f = os.path.join(SWIFT_DIR, service)
        content = read_file(f)
        if content:
            has_ud_token = bool(
                re.search(
                    r"UserDefaults.*fitbit_access_token|UserDefaults.*fitbit_refresh_token",
                    content,
                )
            )
            check(f"SEC-01: No UserDefaults tokens in {service}", not has_ud_token, f)

    for service in ["StravaService.swift", "StravaSettingsView.swift"]:
        f = os.path.join(SWIFT_DIR, service)
        content = read_file(f)
        if content:
            has_ud_token = bool(
                re.search(
                    r"UserDefaults.*strava_access_token|UserDefaults.*strava_refresh_token",
                    content,
                )
            )
            check(f"SEC-01: No UserDefaults tokens in {service}", not has_ud_token, f)

    # SEC-02: ContactsService uses RPC, not full table fetch
    f = os.path.join(SWIFT_DIR, "ContactsService.swift")
    content = read_file(f)
    check(
        "SEC-02: ContactsService uses RPC for matching",
        content is not None and "match_contacts_by_phone" in content,
        f,
    )

    # --- Dead Code ---
    print("\nDead Code Removal:")

    # DEAD-04: No findMatchingUsersByEmailOnly
    f = os.path.join(SWIFT_DIR, "ContactsService.swift")
    content = read_file(f)
    check(
        "DEAD-04: findMatchingUsersByEmailOnly removed",
        content is not None and "findMatchingUsersByEmailOnly" not in content,
        f,
    )

    # DEAD-09: No debug area codes 716/585
    check(
        "DEAD-09: No debug area codes",
        content is not None and "716" not in content and "585" not in content,
        f,
    )

    # --- Duplicate Logic ---
    print("\nDuplicate Logic Consolidation:")

    # DUP-04: ExerciseTypes.swift exists
    check(
        "DUP-04: ExerciseTypes.swift exists",
        file_exists(os.path.join(SWIFT_DIR, "ExerciseTypes.swift")),
    )

    # DUP-06: AlternativeExerciseEngine deleted
    check(
        "DUP-06: AlternativeExerciseEngine.swift deleted",
        not file_exists(os.path.join(SWIFT_DIR, "AlternativeExerciseEngine.swift")),
    )

    # DUP-10: No getGoogleSignInURL in SocialAuthService
    f = os.path.join(SWIFT_DIR, "SocialAuthService.swift")
    content = read_file(f)
    check(
        "DUP-10: getGoogleSignInURL removed from SocialAuthService",
        content is not None and "getGoogleSignInURL" not in content,
        f,
    )

    # DUP-14: SystemMetrics.swift exists
    check(
        "DUP-14: SystemMetrics.swift exists",
        file_exists(os.path.join(SWIFT_DIR, "SystemMetrics.swift")),
    )

    # DUP-01: ChallengeTypeResolvable protocol exists
    f = os.path.join(SWIFT_DIR, "ChallengeService.swift")
    content = read_file(f)
    check(
        "DUP-01: ChallengeTypeResolvable protocol exists",
        content is not None and "protocol ChallengeTypeResolvable" in content,
        f,
    )

    # --- Performance ---
    print("\nPerformance:")

    # PERF-01: No computed DateFormatter properties
    for service in ["HydrationService.swift", "WeightTrackingService.swift"]:
        f = os.path.join(SWIFT_DIR, service)
        content = read_file(f)
        if content:
            has_computed = "var dateFormatter: DateFormatter {" in content
            check(
                f"PERF-01: No computed DateFormatter in {service}",
                not has_computed,
                f,
            )

    # PERF-07: No NSLock in RequestDeduplicationService
    f = os.path.join(SWIFT_DIR, "PerformanceOptimizations.swift")
    content = read_file(f)
    if content:
        check(
            "PERF-07: No NSLock in RequestDeduplicationService",
            "requestLock" not in content,
            f,
        )

    # --- Brand Consistency ---
    print("\nBrand Consistency:")
    f = os.path.join(SWIFT_DIR, "HealthKitManager.swift")
    content = read_file(f)
    check(
        "GAP-09: No 'GoFit' brand in HealthKitManager",
        content is not None and '"GoFit"' not in content,
        f,
    )

    # --- Summary ---
    total = PASS + FAIL
    print(f"\n{'=' * 40}")
    print(f"Results: {PASS}/{total} passed, {FAIL} failed")
    print(f"{'=' * 40}\n")

    return 0 if FAIL == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
