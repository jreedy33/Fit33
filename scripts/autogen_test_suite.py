#!/usr/bin/env python3
"""
Auto-Gen Workout Test Suite
Tests 40+ scenarios to grade workout generation accuracy
"""

import os
import json
import random
from datetime import datetime
from supabase import create_client
from collections import Counter, defaultdict

# Supabase credentials
SUPABASE_URL = "https://ehooeghabzefgoqzugrc.supabase.co"
SUPABASE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVob29lZ2hhYnplZmdvcXp1Z3JjIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjM4NDc4NjQsImV4cCI6MjA3OTQyMzg2NH0.6-QWDr5B279hybtu9MbPVhmBKlyzFq1GK9P7zlDXuY0"

supabase = create_client(SUPABASE_URL, SUPABASE_KEY)

# ============================================================================
# TEST CASE DEFINITIONS
# ============================================================================

USER_PROFILES = {
    "home_beginner": {
        "name": "Home Beginner",
        "equipment": ["Bodyweight"],
        "experience": "Beginner",
        "goal": "Build Muscle",
        "location": "home"
    },
    "home_intermediate": {
        "name": "Home Intermediate",
        "equipment": ["Bodyweight", "Dumbbells"],
        "experience": "Intermediate",
        "goal": "Build Muscle",
        "location": "home"
    },
    "home_advanced_dumbbells": {
        "name": "Home Advanced (Dumbbells Only)",
        "equipment": ["Dumbbells"],
        "experience": "Advanced",
        "goal": "Build Muscle",
        "location": "home"
    },
    "gym_beginner": {
        "name": "Gym Beginner",
        "equipment": ["Dumbbells", "Machines"],
        "experience": "Beginner",
        "goal": "Build Muscle",
        "location": "gym"
    },
    "gym_intermediate": {
        "name": "Gym Intermediate",
        "equipment": ["Barbell", "Dumbbells", "Cables"],
        "experience": "Intermediate",
        "goal": "Build Muscle",
        "location": "gym"
    },
    "gym_advanced": {
        "name": "Gym Advanced (Full Equipment)",
        "equipment": ["Barbell", "Dumbbells", "Cables", "Machines"],
        "experience": "Advanced",
        "goal": "Build Muscle",
        "location": "gym"
    },
    "gym_barbell_focus": {
        "name": "Gym Barbell Focus",
        "equipment": ["Barbell"],
        "experience": "Intermediate",
        "goal": "Increase Strength",
        "location": "gym"
    },
    "gym_cable_focus": {
        "name": "Gym Cable Focus",
        "equipment": ["Cables"],
        "experience": "Intermediate",
        "goal": "Build Muscle",
        "location": "gym"
    },
    "fat_loss_home": {
        "name": "Fat Loss at Home",
        "equipment": ["Bodyweight"],
        "experience": "Beginner",
        "goal": "Lose Fat",
        "location": "home"
    },
    "strength_athlete": {
        "name": "Strength Athlete",
        "equipment": ["Barbell", "Dumbbells"],
        "experience": "Advanced",
        "goal": "Increase Strength",
        "location": "gym"
    }
}

MUSCLE_SELECTIONS = [
    # Single muscle groups
    ["Chest"],
    ["Back"],
    ["Lats"],
    ["Shoulders"],
    ["Arms"],
    ["Biceps"],
    ["Triceps"],
    ["Legs"],
    ["Quads"],
    ["Hamstrings"],
    ["Glutes"],
    ["Core"],
    ["Abs"],
    ["Calves"],
    
    # Compound selections
    ["Chest", "Triceps"],
    ["Back", "Biceps"],
    ["Lats", "Biceps"],
    ["Chest", "Shoulders"],
    ["Shoulders", "Arms"],
    ["Quads", "Glutes"],
    ["Hamstrings", "Glutes"],
    ["Upper Chest"],
    ["Lower Chest"],
    ["Upper Back"],
    ["Lower Back"],
    
    # Full body / multi-muscle
    ["Chest", "Back"],
    ["Arms", "Shoulders"],
    ["Legs", "Glutes"],
]

# ============================================================================
# FILTERING LOGIC (mirrors Swift app)
# ============================================================================

def filter_exercises(exercises, target_muscles, user_equipment):
    """
    Mirrors the Swift WorkoutGeneratorService.generateFromCoreData filtering
    """
    # Muscle group expansion - PRECISE mappings, no overlaps
    # Only expand general terms to specific ones, not the reverse
    muscle_group_expansion = {
        # General -> Specific (one direction only)
        "arms": ["arms", "biceps", "triceps", "forearms"],
        "shoulders": ["shoulders", "front delts", "rear delts", "side delts", "delts"],
        "legs": ["legs", "quads", "hamstrings", "glutes", "calves", "adductors", "abductors"],
        "back": ["back", "lats", "upper back", "lower back", "traps", "rhomboids"],
        "chest": ["chest", "upper chest", "lower chest", "pecs"],
        "core": ["core", "abs", "obliques", "lower abs"],
        # Specific muscles - no expansion needed, just match exactly
        "glutes": ["glutes"],
        "quads": ["quads", "quadriceps"],
        "hamstrings": ["hamstrings"],
        "lats": ["lats"],
        "biceps": ["biceps"],
        "triceps": ["triceps"],
        "abs": ["abs", "lower abs"],
        "upper chest": ["upper chest"],
        "lower chest": ["lower chest"],
        "upper back": ["upper back"],
        "lower back": ["lower back"],
        "front delts": ["front delts"],
        "rear delts": ["rear delts"],
        "calves": ["calves"],
    }
    
    # Expand target muscles to include sub-muscles
    expanded_muscles = set(m.lower() for m in target_muscles)
    for target in target_muscles:
        target_lower = target.lower()
        if target_lower in muscle_group_expansion:
            expanded_muscles.update(muscle_group_expansion[target_lower])
    
    normalized_muscles = list(expanded_muscles)
    normalized_equipment = [e.lower() for e in user_equipment]
    
    matching = []
    equipment_fails = 0
    muscle_fails = 0
    
    for ex in exercises:
        ex_equipment = (ex.get('equipment') or '').lower()
        ex_muscles = ex.get('primary_muscles') or []
        ex_secondary = ex.get('secondary_muscles') or []
        ex_category = (ex.get('category') or '').lower()
        ex_workout_type = (ex.get('workout_type') or '').lower()
        
        # Parse equipment parts
        equipment_parts = [p.strip() for p in ex_equipment.split(',') if p.strip()]
        is_bodyweight = (not equipment_parts) or (len(equipment_parts) == 1 and equipment_parts[0] == 'bodyweight')
        
        # STRICT equipment matching
        if not normalized_equipment:
            matches_equipment = True
        elif is_bodyweight:
            # Bodyweight - only include if user explicitly selected bodyweight
            matches_equipment = any('bodyweight' in eq for eq in normalized_equipment)
        else:
            # Exercise requires equipment - check if user has at least one
            non_bodyweight_parts = [p for p in equipment_parts if p != 'bodyweight']
            matches_equipment = any(
                user_eq in req_eq or req_eq in user_eq
                for req_eq in non_bodyweight_parts
                for user_eq in normalized_equipment
            )
        
        if not matches_equipment:
            equipment_fails += 1
            continue
        
        # Muscle matching - check PRIMARY muscles only
        if isinstance(ex_muscles, str):
            ex_muscles = [ex_muscles]
            
        primary_muscles_lower = [m.lower() for m in ex_muscles if m]
        
        # STRICT muscle matching - exercise's PRIMARY muscle must match target
        matches_muscle = any(
            target == muscle or target in muscle or muscle in target
            for muscle in primary_muscles_lower
            for target in normalized_muscles
        )
        
        if not matches_muscle:
            muscle_fails += 1
            continue
        
        matching.append(ex)
    
    return matching, equipment_fails, muscle_fails


def select_workout_multi_target(matching_exercises, count=5, target_muscles=None):
    """
    Intelligent selection - prioritize exercises hitting MULTIPLE user-selected muscles.
    e.g., Close-Grip Bench hits Chest AND Triceps = higher priority
    """
    if len(matching_exercises) <= count:
        return matching_exercises
    
    # Expand target muscles - PRECISE mappings
    muscle_group_expansion = {
        "arms": ["arms", "biceps", "triceps", "forearms"],
        "shoulders": ["shoulders", "front delts", "rear delts", "side delts", "delts"],
        "legs": ["legs", "quads", "hamstrings", "glutes", "calves", "adductors", "abductors"],
        "back": ["back", "lats", "upper back", "lower back", "traps", "rhomboids"],
        "chest": ["chest", "upper chest", "lower chest", "pecs"],
        "core": ["core", "abs", "obliques", "lower abs"],
        "glutes": ["glutes"],
        "quads": ["quads", "quadriceps"],
        "hamstrings": ["hamstrings"],
        "lats": ["lats"],
        "biceps": ["biceps"],
        "triceps": ["triceps"],
        "abs": ["abs", "lower abs"],
        "upper chest": ["upper chest"],
        "lower chest": ["lower chest"],
        "upper back": ["upper back"],
        "lower back": ["lower back"],
        "calves": ["calves"],
    }
    
    # Build expanded set for each original target
    expanded_per_target = {}
    if target_muscles:
        for t in target_muscles:
            t_lower = t.lower()
            expanded = {t_lower}
            if t_lower in muscle_group_expansion:
                expanded.update(muscle_group_expansion[t_lower])
            expanded_per_target[t_lower] = expanded
    
    # Score each exercise
    scored = []
    for ex in matching_exercises:
        score = 100
        
        # Get all muscles this exercise hits
        primary = ex.get('primary_muscles', [])
        secondary = ex.get('secondary_muscles', [])
        if isinstance(primary, str):
            primary = [primary]
        if isinstance(secondary, str):
            secondary = [secondary]
        all_muscles = [m.lower() for m in (primary + secondary) if m]
        
        # Count how many USER-SELECTED targets this exercise hits
        targets_hit = 0
        for target, expanded in expanded_per_target.items():
            hits_target = any(
                muscle in exp or exp in muscle
                for muscle in all_muscles
                for exp in expanded
            )
            if hits_target:
                targets_hit += 1
        
        # Base bonus for hitting any target
        if targets_hit > 0:
            score += 300  # BIG bonus for direct match
            
            # 🔥 MULTI-TARGET BONUS - huge value for hitting multiple selections
            if targets_hit >= 2:
                score += (targets_hit - 1) * 150  # +150 for each extra target hit
        else:
            score -= 200  # BIG penalty for not hitting any target
        
        # Small randomness (shouldn't override muscle matching)
        score += random.uniform(0, 20)
        
        scored.append((score, ex, targets_hit))
    
    # Sort by score (highest first)
    scored.sort(key=lambda x: -x[0])
    
    # Select with diversity
    selected = []
    used_names = set()
    used_equipment = Counter()
    
    for score, ex, targets_hit in scored:
        if len(selected) >= count:
            break
            
        name = ex.get('name', '')
        equipment = ex.get('equipment', '')
        
        # Skip if too similar
        name_base = name.split('(')[0].strip().lower()
        if any(name_base in used for used in used_names):
            continue
        
        # Limit equipment repetition
        if used_equipment[equipment] >= 2:
            continue
            
        selected.append(ex)
        used_names.add(name_base)
        used_equipment[equipment] += 1
    
    return selected


# ============================================================================
# GRADING FUNCTIONS
# ============================================================================

def grade_equipment_accuracy(workout, user_equipment):
    """
    Grade: Do all exercises match the user's equipment selection?
    100% = all exercises use selected equipment
    """
    if not workout:
        return 0, "No exercises generated"
    
    normalized_equipment = [e.lower() for e in user_equipment]
    issues = []
    correct = 0
    
    for ex in workout:
        ex_equipment = (ex.get('equipment') or '').lower()
        equipment_parts = [p.strip() for p in ex_equipment.split(',')]
        is_bodyweight = 'bodyweight' in equipment_parts or not equipment_parts
        
        if is_bodyweight:
            if any('bodyweight' in eq for eq in normalized_equipment):
                correct += 1
            else:
                issues.append(f"❌ '{ex['name']}' is bodyweight but user didn't select it")
        else:
            matches = any(
                user_eq in part or part in user_eq
                for part in equipment_parts
                for user_eq in normalized_equipment
            )
            if matches:
                correct += 1
            else:
                issues.append(f"❌ '{ex['name']}' needs {ex_equipment} but user has {user_equipment}")
    
    score = (correct / len(workout)) * 100 if workout else 0
    return score, issues


def grade_muscle_accuracy(workout, target_muscles):
    """
    Grade: Do exercises target the requested muscles?
    Uses muscle group expansion for fair grading.
    """
    if not workout:
        return 0, "No exercises generated"
    
    # Muscle group expansion for grading - PRECISE mappings
    muscle_group_expansion = {
        "arms": ["arms", "biceps", "triceps", "forearms"],
        "shoulders": ["shoulders", "front delts", "rear delts", "side delts", "delts"],
        "legs": ["legs", "quads", "hamstrings", "glutes", "calves", "adductors", "abductors"],
        "back": ["back", "lats", "upper back", "lower back", "traps", "rhomboids"],
        "chest": ["chest", "upper chest", "lower chest", "pecs"],
        "core": ["core", "abs", "obliques", "lower abs"],
        "glutes": ["glutes"],
        "quads": ["quads", "quadriceps"],
        "hamstrings": ["hamstrings"],
        "lats": ["lats"],
        "biceps": ["biceps"],
        "triceps": ["triceps"],
        "abs": ["abs", "lower abs"],
        "upper chest": ["upper chest"],
        "lower chest": ["lower chest"],
        "upper back": ["upper back"],
        "lower back": ["lower back"],
        "calves": ["calves"],
    }
    
    # Expand target muscles
    expanded_targets = set(m.lower() for m in target_muscles)
    for target in target_muscles:
        target_lower = target.lower()
        if target_lower in muscle_group_expansion:
            expanded_targets.update(muscle_group_expansion[target_lower])
    
    issues = []
    correct = 0
    
    for ex in workout:
        muscles = ex.get('primary_muscles', [])
        if isinstance(muscles, str):
            muscles = [muscles]
        muscles_lower = [m.lower() for m in muscles if m]
        
        matches = any(
            target in muscle or muscle in target
            for muscle in muscles_lower
            for target in expanded_targets
        )
        
        if matches:
            correct += 1
        else:
            issues.append(f"⚠️ '{ex['name']}' targets {muscles} not {target_muscles}")
    
    score = (correct / len(workout)) * 100 if workout else 0
    return score, issues


def grade_variety(workout):
    """
    Grade: Are exercises varied (not repetitive)?
    Checks for similar names, same movement patterns, etc.
    """
    if not workout:
        return 0, "No exercises generated"
    
    issues = []
    
    # Check name similarity
    names = [ex.get('name', '').lower() for ex in workout]
    name_bases = [n.split('(')[0].strip() for n in names]
    
    # Count duplicates
    base_counts = Counter(name_bases)
    duplicates = {k: v for k, v in base_counts.items() if v > 1}
    
    if duplicates:
        for name, count in duplicates.items():
            issues.append(f"⚠️ Similar exercises: '{name}' appears {count} times")
    
    # Check equipment variety
    equipment = [ex.get('equipment', '') for ex in workout]
    equip_counts = Counter(equipment)
    max_same_equip = max(equip_counts.values()) if equip_counts else 0
    
    if max_same_equip > 3:
        issues.append(f"⚠️ Low equipment variety: {max_same_equip} exercises use same equipment")
    
    # Calculate score
    duplicate_penalty = len(duplicates) * 15
    variety_penalty = max(0, (max_same_equip - 2) * 10)
    score = max(0, 100 - duplicate_penalty - variety_penalty)
    
    return score, issues


def grade_workout_quality(workout, user_profile, target_muscles):
    """
    Overall workout quality grade
    """
    if not workout:
        return 0, "No exercises generated"
    
    issues = []
    
    # Check for minimum exercises
    if len(workout) < 3:
        issues.append(f"⚠️ Too few exercises: {len(workout)}")
        return 50, issues
    
    # Check for appropriate difficulty
    experience = user_profile.get('experience', 'Intermediate')
    
    # Check workout type consistency
    workout_types = [ex.get('workout_type', '') for ex in workout]
    type_counts = Counter(workout_types)
    
    # For strength goals, should mostly be strength exercises
    goal = user_profile.get('goal', '')
    if 'strength' in goal.lower() or 'muscle' in goal.lower():
        strength_count = type_counts.get('Strength', 0)
        if strength_count < len(workout) * 0.8:
            issues.append(f"⚠️ Only {strength_count}/{len(workout)} are strength exercises for {goal} goal")
    
    score = 100 - (len(issues) * 15)
    return max(0, score), issues


# ============================================================================
# TEST RUNNER
# ============================================================================

def run_test_case(exercises, test_id, user_profile, target_muscles, workout_count=5):
    """
    Run a single test case and return graded results.
    ALL user-selected muscles are targets. Exercises hitting MULTIPLE targets get bonus.
    """
    user_equipment = user_profile['equipment']
    
    # Filter exercises that hit ANY of the target muscles
    matching, equip_fails, muscle_fails = filter_exercises(
        exercises, target_muscles, user_equipment
    )
    
    # Select workout - prioritizes exercises hitting MULTIPLE targets
    workout = select_workout_multi_target(matching, workout_count, target_muscles)
    
    # Grade
    equip_score, equip_issues = grade_equipment_accuracy(workout, user_equipment)
    muscle_score, muscle_issues = grade_muscle_accuracy(workout, target_muscles)
    variety_score, variety_issues = grade_variety(workout)
    quality_score, quality_issues = grade_workout_quality(workout, user_profile, target_muscles)
    
    # Overall score (weighted average)
    overall_score = (
        equip_score * 0.35 +      # Equipment accuracy most important
        muscle_score * 0.30 +      # Muscle targeting next
        variety_score * 0.20 +     # Variety important
        quality_score * 0.15       # Overall quality
    )
    
    return {
        "test_id": test_id,
        "profile": user_profile['name'],
        "equipment": user_equipment,
        "target_muscles": target_muscles,
        "matching_pool": len(matching),
        "workout_count": len(workout),
        "workout_exercises": [
            {
                "name": ex.get('name'),
                "equipment": ex.get('equipment'),
                "muscles": ex.get('primary_muscles')
            }
            for ex in workout
        ],
        "scores": {
            "equipment_accuracy": round(equip_score, 1),
            "muscle_accuracy": round(muscle_score, 1),
            "variety": round(variety_score, 1),
            "quality": round(quality_score, 1),
            "overall": round(overall_score, 1)
        },
        "issues": equip_issues + muscle_issues + variety_issues + quality_issues,
        "grade": get_letter_grade(overall_score)
    }


def get_letter_grade(score):
    if score >= 90: return "A"
    if score >= 80: return "B"
    if score >= 70: return "C"
    if score >= 60: return "D"
    return "F"


def generate_test_cases():
    """
    Generate 40+ test cases covering various scenarios
    """
    test_cases = []
    
    # Systematic tests: each profile with various muscle selections
    profiles = list(USER_PROFILES.keys())
    muscles = MUSCLE_SELECTIONS
    
    test_id = 1
    
    # Test each profile with 4 different muscle selections
    for profile_key in profiles:
        profile = USER_PROFILES[profile_key]
        selected_muscles = random.sample(muscles, min(4, len(muscles)))
        
        for muscle_selection in selected_muscles:
            test_cases.append({
                "test_id": test_id,
                "profile": profile,
                "muscles": muscle_selection
            })
            test_id += 1
    
    return test_cases


def main():
    print("=" * 80)
    print("🏋️ AUTO-GEN WORKOUT TEST SUITE")
    print("=" * 80)
    print(f"Started: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print()
    
    # Fetch all exercises
    print("📥 Fetching exercises from database...")
    all_exercises = []
    offset = 0
    batch_size = 1000
    
    while True:
        response = supabase.table('exercises').select('*').range(offset, offset + batch_size - 1).execute()
        batch = response.data
        if not batch:
            break
        all_exercises.extend(batch)
        offset += batch_size
        if len(batch) < batch_size:
            break
    
    print(f"✅ Loaded {len(all_exercises)} exercises")
    print()
    
    # Generate and run test cases
    test_cases = generate_test_cases()
    print(f"🧪 Running {len(test_cases)} test cases...")
    print()
    
    results = []
    for tc in test_cases:
        result = run_test_case(
            all_exercises,
            tc['test_id'],
            tc['profile'],
            tc['muscles']
        )
        results.append(result)
    
    # ========================================================================
    # ANALYSIS & REPORT
    # ========================================================================
    
    print("=" * 80)
    print("📊 TEST RESULTS SUMMARY")
    print("=" * 80)
    print()
    
    # Grade distribution
    grades = Counter(r['grade'] for r in results)
    print("📈 Grade Distribution:")
    for grade in ['A', 'B', 'C', 'D', 'F']:
        count = grades.get(grade, 0)
        pct = (count / len(results)) * 100
        bar = '█' * int(pct / 5)
        print(f"   {grade}: {count:3d} ({pct:5.1f}%) {bar}")
    print()
    
    # Average scores
    avg_scores = {
        'equipment_accuracy': sum(r['scores']['equipment_accuracy'] for r in results) / len(results),
        'muscle_accuracy': sum(r['scores']['muscle_accuracy'] for r in results) / len(results),
        'variety': sum(r['scores']['variety'] for r in results) / len(results),
        'quality': sum(r['scores']['quality'] for r in results) / len(results),
        'overall': sum(r['scores']['overall'] for r in results) / len(results),
    }
    
    print("📊 Average Scores:")
    for metric, score in avg_scores.items():
        bar = '█' * int(score / 5)
        status = "✅" if score >= 80 else "⚠️" if score >= 60 else "❌"
        print(f"   {status} {metric:20s}: {score:5.1f}% {bar}")
    print()
    
    # Worst performing test cases
    print("=" * 80)
    print("❌ WORST PERFORMING TESTS (Need Investigation)")
    print("=" * 80)
    
    worst = sorted(results, key=lambda x: x['scores']['overall'])[:10]
    for r in worst:
        print(f"\n🔴 Test #{r['test_id']}: {r['profile']} | {r['target_muscles']}")
        print(f"   Equipment: {r['equipment']}")
        print(f"   Overall Score: {r['scores']['overall']}% (Grade: {r['grade']})")
        print(f"   Pool Size: {r['matching_pool']} → Selected: {r['workout_count']}")
        if r['issues']:
            print("   Issues:")
            for issue in r['issues'][:3]:
                print(f"      {issue}")
        print("   Workout:")
        for ex in r['workout_exercises'][:3]:
            print(f"      • {ex['name']} ({ex['equipment']}) - {ex['muscles']}")
    
    # Best performing
    print()
    print("=" * 80)
    print("✅ BEST PERFORMING TESTS")
    print("=" * 80)
    
    best = sorted(results, key=lambda x: x['scores']['overall'], reverse=True)[:5]
    for r in best:
        print(f"\n🟢 Test #{r['test_id']}: {r['profile']} | {r['target_muscles']}")
        print(f"   Equipment: {r['equipment']}")
        print(f"   Overall Score: {r['scores']['overall']}% (Grade: {r['grade']})")
        print(f"   Pool Size: {r['matching_pool']} exercises matched")
    
    # ========================================================================
    # PATTERN ANALYSIS
    # ========================================================================
    
    print()
    print("=" * 80)
    print("🔍 PATTERN ANALYSIS")
    print("=" * 80)
    
    # By profile type
    print("\n📊 Scores by User Profile:")
    profile_scores = defaultdict(list)
    for r in results:
        profile_scores[r['profile']].append(r['scores']['overall'])
    
    for profile, scores in sorted(profile_scores.items(), key=lambda x: sum(x[1])/len(x[1])):
        avg = sum(scores) / len(scores)
        status = "✅" if avg >= 80 else "⚠️" if avg >= 60 else "❌"
        print(f"   {status} {profile:35s}: {avg:5.1f}%")
    
    # By equipment type
    print("\n📊 Scores by Equipment Selection:")
    equip_scores = defaultdict(list)
    for r in results:
        equip_key = ", ".join(sorted(r['equipment']))
        equip_scores[equip_key].append(r['scores']['overall'])
    
    for equip, scores in sorted(equip_scores.items(), key=lambda x: sum(x[1])/len(x[1])):
        avg = sum(scores) / len(scores)
        status = "✅" if avg >= 80 else "⚠️" if avg >= 60 else "❌"
        print(f"   {status} {equip:35s}: {avg:5.1f}%")
    
    # By muscle group
    print("\n📊 Scores by Muscle Target:")
    muscle_scores = defaultdict(list)
    for r in results:
        for muscle in r['target_muscles']:
            muscle_scores[muscle].append(r['scores']['overall'])
    
    for muscle, scores in sorted(muscle_scores.items(), key=lambda x: sum(x[1])/len(x[1])):
        avg = sum(scores) / len(scores)
        count = len(scores)
        status = "✅" if avg >= 80 else "⚠️" if avg >= 60 else "❌"
        print(f"   {status} {muscle:20s}: {avg:5.1f}% (n={count})")
    
    # ========================================================================
    # COMMON ISSUES
    # ========================================================================
    
    print()
    print("=" * 80)
    print("⚠️ MOST COMMON ISSUES")
    print("=" * 80)
    
    all_issues = []
    for r in results:
        all_issues.extend(r['issues'])
    
    issue_patterns = defaultdict(int)
    for issue in all_issues:
        # Categorize issues
        if "bodyweight" in issue.lower():
            issue_patterns["Bodyweight exercises appearing with wrong equipment"] += 1
        elif "targets" in issue.lower():
            issue_patterns["Exercise doesn't target requested muscle"] += 1
        elif "similar" in issue.lower() or "appears" in issue.lower():
            issue_patterns["Repetitive/similar exercises"] += 1
        elif "variety" in issue.lower():
            issue_patterns["Low equipment variety"] += 1
        elif "strength" in issue.lower():
            issue_patterns["Wrong workout type for goal"] += 1
        else:
            issue_patterns["Other issues"] += 1
    
    for issue, count in sorted(issue_patterns.items(), key=lambda x: -x[1]):
        print(f"   {count:3d}x - {issue}")
    
    # ========================================================================
    # RECOMMENDATIONS
    # ========================================================================
    
    print()
    print("=" * 80)
    print("💡 RECOMMENDATIONS FOR IMPROVEMENT")
    print("=" * 80)
    
    recommendations = []
    
    # Equipment accuracy issues
    if avg_scores['equipment_accuracy'] < 90:
        recommendations.append({
            "priority": "HIGH",
            "issue": "Equipment Filtering",
            "finding": f"Equipment accuracy is {avg_scores['equipment_accuracy']:.1f}%",
            "suggestion": "Stricter equipment matching - bodyweight should ONLY appear if explicitly selected"
        })
    
    # Muscle accuracy issues  
    if avg_scores['muscle_accuracy'] < 85:
        recommendations.append({
            "priority": "HIGH",
            "issue": "Muscle Targeting",
            "finding": f"Muscle accuracy is {avg_scores['muscle_accuracy']:.1f}%",
            "suggestion": "Verify muscle tagging in database. Some exercises may have incorrect primary_muscles"
        })
    
    # Variety issues
    if avg_scores['variety'] < 80:
        recommendations.append({
            "priority": "MEDIUM",
            "issue": "Workout Variety",
            "finding": f"Variety score is {avg_scores['variety']:.1f}%",
            "suggestion": "Implement stricter diversity rules - limit same movement patterns, body positions"
        })
    
    # Profile-specific issues
    for profile, scores in profile_scores.items():
        avg = sum(scores) / len(scores)
        if avg < 70:
            recommendations.append({
                "priority": "MEDIUM",
                "issue": f"Profile: {profile}",
                "finding": f"Average score is only {avg:.1f}%",
                "suggestion": f"Investigate why {profile} performs poorly - may need more exercises tagged for this equipment/goal"
            })
    
    # Muscle-specific issues
    for muscle, scores in muscle_scores.items():
        avg = sum(scores) / len(scores)
        if avg < 70 and len(scores) >= 2:
            recommendations.append({
                "priority": "MEDIUM",
                "issue": f"Muscle: {muscle}",
                "finding": f"Average score is only {avg:.1f}%",
                "suggestion": f"Check if '{muscle}' exercises are properly tagged in database"
            })
    
    for i, rec in enumerate(recommendations, 1):
        print(f"\n{i}. [{rec['priority']}] {rec['issue']}")
        print(f"   Finding: {rec['finding']}")
        print(f"   → {rec['suggestion']}")
    
    # ========================================================================
    # DATA QUALITY CHECK
    # ========================================================================
    
    print()
    print("=" * 80)
    print("🔬 DATABASE QUALITY CHECK")
    print("=" * 80)
    
    # Check equipment distribution
    equip_dist = Counter(ex.get('equipment', 'Unknown') for ex in all_exercises)
    print("\n📊 Equipment Distribution (top 10):")
    for equip, count in equip_dist.most_common(10):
        print(f"   {count:5d} - {equip}")
    
    # Check muscle distribution
    muscle_dist = Counter()
    for ex in all_exercises:
        muscles = ex.get('primary_muscles', [])
        if isinstance(muscles, list):
            for m in muscles:
                muscle_dist[m] += 1
        elif muscles:
            muscle_dist[muscles] += 1
    
    print("\n📊 Primary Muscle Distribution (top 15):")
    for muscle, count in muscle_dist.most_common(15):
        print(f"   {count:5d} - {muscle}")
    
    # Check for potential issues
    print("\n⚠️ Potential Data Issues:")
    
    # Exercises with no equipment
    no_equip = sum(1 for ex in all_exercises if not ex.get('equipment'))
    if no_equip > 0:
        print(f"   • {no_equip} exercises have no equipment field")
    
    # Exercises with no muscles
    no_muscles = sum(1 for ex in all_exercises if not ex.get('primary_muscles'))
    if no_muscles > 0:
        print(f"   • {no_muscles} exercises have no primary_muscles field")
    
    # Check for specific muscle tags
    for target in ['Lats', 'Upper Chest', 'Lower Chest', 'Upper Back']:
        count = muscle_dist.get(target, 0)
        if count < 20:
            print(f"   • Only {count} exercises tagged with '{target}' - may need more")
    
    # Check barbell exercises for specific muscles
    barbell_exercises = [ex for ex in all_exercises if 'barbell' in (ex.get('equipment') or '').lower()]
    barbell_chest = sum(1 for ex in barbell_exercises if 'chest' in str(ex.get('primary_muscles', [])).lower())
    barbell_lats = sum(1 for ex in barbell_exercises if 'lats' in str(ex.get('primary_muscles', [])).lower())
    
    print(f"\n📊 Barbell Exercise Coverage:")
    print(f"   Total Barbell: {len(barbell_exercises)}")
    print(f"   Barbell + Chest: {barbell_chest}")
    print(f"   Barbell + Lats: {barbell_lats}")
    
    # Final summary
    print()
    print("=" * 80)
    print("📋 FINAL SUMMARY")
    print("=" * 80)
    overall_grade = get_letter_grade(avg_scores['overall'])
    print(f"""
    Overall System Grade: {overall_grade} ({avg_scores['overall']:.1f}%)
    
    Tests Passed (A/B): {grades.get('A', 0) + grades.get('B', 0)}/{len(results)}
    Tests Failed (D/F): {grades.get('D', 0) + grades.get('F', 0)}/{len(results)}
    
    Key Issues: {len(recommendations)}
    """)
    
    # Save detailed results
    output_file = '/Users/josephreed/Desktop/Workout App/scripts/autogen_test_results.json'
    with open(output_file, 'w') as f:
        json.dump({
            'summary': {
                'total_tests': len(results),
                'grades': dict(grades),
                'avg_scores': avg_scores,
                'overall_grade': overall_grade
            },
            'recommendations': recommendations,
            'results': results
        }, f, indent=2)
    
    print(f"📁 Detailed results saved to: {output_file}")
    print()
    print("=" * 80)


if __name__ == "__main__":
    main()

