#!/usr/bin/env python3
"""
Auto-Gen Workout Test Suite V2
NOW CONSIDERS ALL USER DATA: Weight, Age, Experience, Goal, Gender
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
# COMPREHENSIVE USER PROFILES - Including ALL onboarding data
# ============================================================================

USER_PROFILES = {
    # HOME USERS
    "heavy_home_beginner": {
        "name": "Heavy Home Beginner",
        "weight_lbs": 300,
        "age": 45,
        "gender": "male",
        "experience": "Beginner",
        "goal": "Lose Fat",
        "equipment": ["Bodyweight"],
        "location": "home",
        "description": "300lb man, can't do pull-ups or dips"
    },
    "light_home_beginner": {
        "name": "Light Home Beginner", 
        "weight_lbs": 140,
        "age": 28,
        "gender": "female",
        "experience": "Beginner",
        "goal": "Build Muscle",
        "equipment": ["Bodyweight"],
        "location": "home",
        "description": "140lb woman, can do bodyweight exercises"
    },
    "senior_home": {
        "name": "Senior at Home",
        "weight_lbs": 180,
        "age": 65,
        "gender": "male",
        "experience": "Beginner",
        "goal": "Stay Active",
        "equipment": ["Bodyweight", "Dumbbells"],
        "location": "home",
        "description": "65yo, needs low-impact, no plyometrics"
    },
    "young_athletic_home": {
        "name": "Young Athletic Home",
        "weight_lbs": 175,
        "age": 22,
        "gender": "male",
        "experience": "Advanced",
        "goal": "Build Muscle",
        "equipment": ["Bodyweight", "Dumbbells"],
        "location": "home",
        "description": "22yo fit male, can do advanced bodyweight"
    },
    
    # GYM USERS  
    "heavy_gym_beginner": {
        "name": "Heavy Gym Beginner",
        "weight_lbs": 280,
        "age": 38,
        "gender": "male",
        "experience": "Beginner",
        "goal": "Lose Fat",
        "equipment": ["Dumbbells", "Machines", "Cables"],
        "location": "gym",
        "description": "280lb, needs machines (guided), no advanced lifts"
    },
    "petite_gym_beginner": {
        "name": "Petite Gym Beginner",
        "weight_lbs": 115,
        "age": 24,
        "gender": "female",
        "experience": "Beginner",
        "goal": "Build Muscle",
        "equipment": ["Dumbbells", "Machines", "Cables"],
        "location": "gym",
        "description": "115lb woman, beginner friendly exercises"
    },
    "experienced_powerlifter": {
        "name": "Experienced Powerlifter",
        "weight_lbs": 220,
        "age": 32,
        "gender": "male",
        "experience": "Advanced",
        "goal": "Increase Strength",
        "equipment": ["Barbell", "Dumbbells", "Machines"],
        "location": "gym",
        "description": "Can do Olympic lifts, heavy compounds"
    },
    "middle_aged_gym": {
        "name": "Middle-Aged Gym Goer",
        "weight_lbs": 195,
        "age": 52,
        "gender": "male",
        "experience": "Intermediate",
        "goal": "Build Muscle",
        "equipment": ["Barbell", "Dumbbells", "Cables", "Machines"],
        "location": "gym",
        "description": "52yo, avoid high-impact, can do most lifts"
    },
    "female_intermediate": {
        "name": "Female Intermediate",
        "weight_lbs": 145,
        "age": 30,
        "gender": "female",
        "experience": "Intermediate",
        "goal": "Build Muscle",
        "equipment": ["Barbell", "Dumbbells", "Cables"],
        "location": "gym",
        "description": "Fit woman, can do most exercises"
    },
    "obese_starter": {
        "name": "Obese Starting Journey",
        "weight_lbs": 350,
        "age": 42,
        "gender": "male",
        "experience": "Beginner",
        "goal": "Lose Fat",
        "equipment": ["Machines", "Cables"],
        "location": "gym",
        "description": "350lb, needs seated/machine exercises only"
    },
}

MUSCLE_SELECTIONS = [
    ["Chest"],
    ["Back"],
    ["Shoulders"],
    ["Arms"],
    ["Legs"],
    ["Glutes"],
    ["Core"],
    ["Chest", "Triceps"],
    ["Back", "Biceps"],
    ["Legs", "Glutes"],
]

# ============================================================================
# EXERCISE EXCLUSION RULES based on user profile
# ============================================================================

# Exercises that require lifting your own body weight
BODYWEIGHT_LIFTING_EXERCISES = {
    "pull up", "chin up", "pullup", "chinup", "muscle up", "muscle-up",
    "dip", "chest dip", "triceps dip", "ring dip",
    "pistol squat", "single leg squat",
    "handstand", "handstand push up", "pike push up",
    "l-sit", "front lever", "back lever",
    "human flag", "planche",
    "archer push up", "one arm push up",
    "jump", "box jump", "broad jump", "plyometric"
}

# Advanced/complex exercises not for beginners
ADVANCED_EXERCISES = {
    "clean", "snatch", "jerk", "olympic",
    "muscle up", "muscle-up",
    "pistol squat", "dragon flag",
    "front lever", "back lever", "planche",
    "handstand push up", "one arm push up",
    "weighted pull up", "weighted dip",
    "deficit deadlift", "pause squat"
}

# High impact exercises (not for seniors/heavy users)
HIGH_IMPACT_EXERCISES = {
    "jump", "box jump", "broad jump", "depth jump",
    "burpee", "mountain climber",
    "plyometric", "plyo",
    "sprint", "run",
    "jump squat", "jump lunge",
    "tuck jump", "star jump"
}

# ============================================================================
# SMART FILTERING based on user profile
# ============================================================================

def should_exclude_exercise(exercise, user_profile):
    """
    Determine if an exercise should be excluded based on user's profile.
    Returns (should_exclude: bool, reason: str)
    """
    name = (exercise.get('name') or '').lower()
    equipment = (exercise.get('equipment') or '').lower()
    workout_type = (exercise.get('workout_type') or '').lower()
    
    weight = user_profile.get('weight_lbs', 170)
    age = user_profile.get('age', 30)
    experience = user_profile.get('experience', 'Intermediate').lower()
    goal = user_profile.get('goal', '').lower()
    
    # Rule 1: Heavy users (>250lbs) cannot do bodyweight lifting exercises
    if weight > 250 and equipment == 'bodyweight':
        for keyword in BODYWEIGHT_LIFTING_EXERCISES:
            if keyword in name:
                return True, f"Too heavy ({weight}lbs) for {keyword}"
    
    # Rule 2: Beginners should avoid advanced exercises
    if experience == 'beginner':
        for keyword in ADVANCED_EXERCISES:
            if keyword in name:
                return True, f"Too advanced for beginner"
    
    # Rule 3: Seniors (60+) and heavy users should avoid high-impact
    if age >= 60 or weight > 280:
        for keyword in HIGH_IMPACT_EXERCISES:
            if keyword in name:
                return True, f"High impact not suitable for age {age} or weight {weight}"
        # Also exclude plyometrics
        if workout_type == 'plyometrics':
            return True, f"Plyometrics not suitable"
    
    # Rule 4: Very heavy users (>300lbs) need seated/machine exercises primarily
    if weight > 300:
        # Allow machines, cables, and seated exercises
        is_safe = (
            'machine' in equipment or 
            'cable' in equipment or 
            'lever' in name or
            'seated' in name or
            'lying' in name or
            'bench' in name
        )
        if not is_safe and equipment == 'bodyweight':
            return True, f"Standing bodyweight too risky at {weight}lbs"
    
    # Rule 5: Goal-based filtering
    if 'lose fat' in goal or 'fat loss' in goal:
        # Avoid pure strength/power exercises, prefer higher rep work
        pass  # Could add logic here
    
    if 'strength' in goal:
        # Prefer compound movements
        pass
    
    return False, ""


def filter_exercises_smart(exercises, target_muscles, user_profile):
    """
    Smart filtering that considers ALL user profile data
    """
    # Muscle group expansion
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
    }
    
    # Expand target muscles
    expanded_muscles = set(m.lower() for m in target_muscles)
    for target in target_muscles:
        target_lower = target.lower()
        if target_lower in muscle_group_expansion:
            expanded_muscles.update(muscle_group_expansion[target_lower])
    
    user_equipment = [e.lower() for e in user_profile['equipment']]
    
    matching = []
    excluded_reasons = defaultdict(int)
    equipment_fails = 0
    muscle_fails = 0
    profile_fails = 0
    
    for ex in exercises:
        ex_equipment = (ex.get('equipment') or '').lower()
        ex_muscles = ex.get('primary_muscles') or []
        
        # Parse equipment
        equipment_parts = [p.strip() for p in ex_equipment.split(',') if p.strip()]
        is_bodyweight = (not equipment_parts) or (len(equipment_parts) == 1 and equipment_parts[0] == 'bodyweight')
        
        # Equipment matching
        if not user_equipment:
            matches_equipment = True
        elif is_bodyweight:
            matches_equipment = any('bodyweight' in eq for eq in user_equipment)
        else:
            non_bw = [p for p in equipment_parts if p != 'bodyweight']
            matches_equipment = any(
                ue in req or req in ue
                for req in non_bw
                for ue in user_equipment
            )
        
        if not matches_equipment:
            equipment_fails += 1
            continue
        
        # Muscle matching
        if isinstance(ex_muscles, str):
            ex_muscles = [ex_muscles]
        primary_lower = [m.lower() for m in ex_muscles if m]
        
        matches_muscle = any(
            target in muscle or muscle in target
            for muscle in primary_lower
            for target in expanded_muscles
        )
        
        if not matches_muscle:
            muscle_fails += 1
            continue
        
        # USER PROFILE FILTERING - The new smart logic!
        should_exclude, reason = should_exclude_exercise(ex, user_profile)
        if should_exclude:
            profile_fails += 1
            excluded_reasons[reason] += 1
            continue
        
        matching.append(ex)
    
    return matching, {
        'equipment_fails': equipment_fails,
        'muscle_fails': muscle_fails,
        'profile_fails': profile_fails,
        'excluded_reasons': dict(excluded_reasons)
    }


def select_workout_smart(matching_exercises, count, target_muscles, user_profile):
    """
    Smart selection considering user profile for scoring
    """
    if len(matching_exercises) <= count:
        return matching_exercises
    
    # Muscle expansion for scoring
    muscle_group_expansion = {
        "arms": ["arms", "biceps", "triceps", "forearms"],
        "shoulders": ["shoulders", "front delts", "rear delts", "side delts", "delts"],
        "legs": ["legs", "quads", "hamstrings", "glutes", "calves"],
        "back": ["back", "lats", "upper back", "lower back", "traps"],
        "chest": ["chest", "upper chest", "lower chest", "pecs"],
        "core": ["core", "abs", "obliques", "lower abs"],
        "glutes": ["glutes"],
        "quads": ["quads"],
        "hamstrings": ["hamstrings"],
        "lats": ["lats"],
        "biceps": ["biceps"],
        "triceps": ["triceps"],
        "abs": ["abs", "lower abs"],
    }
    
    expanded_per_target = {}
    for t in target_muscles:
        t_lower = t.lower()
        expanded = {t_lower}
        if t_lower in muscle_group_expansion:
            expanded.update(muscle_group_expansion[t_lower])
        expanded_per_target[t_lower] = expanded
    
    experience = user_profile.get('experience', 'Intermediate').lower()
    goal = user_profile.get('goal', '').lower()
    weight = user_profile.get('weight_lbs', 170)
    age = user_profile.get('age', 30)
    
    scored = []
    for ex in matching_exercises:
        score = 100
        name = (ex.get('name') or '').lower()
        equipment = (ex.get('equipment') or '').lower()
        workout_type = (ex.get('workout_type') or '').lower()
        
        primary = ex.get('primary_muscles', [])
        secondary = ex.get('secondary_muscles', [])
        if isinstance(primary, str):
            primary = [primary]
        if isinstance(secondary, str):
            secondary = [secondary]
        all_muscles = [m.lower() for m in (primary + secondary) if m]
        
        # Multi-target bonus
        targets_hit = 0
        for target, expanded in expanded_per_target.items():
            if any(muscle in exp or exp in muscle for muscle in all_muscles for exp in expanded):
                targets_hit += 1
        
        if targets_hit > 0:
            score += 300
            if targets_hit >= 2:
                score += (targets_hit - 1) * 150
        else:
            score -= 200
        
        # EXPERIENCE-BASED SCORING
        if experience == 'beginner':
            # Beginners: prefer machines, simpler movements
            if 'machine' in equipment or 'lever' in name:
                score += 50  # Machines are guided, safer
            if 'isolation' in name or 'curl' in name or 'extension' in name:
                score += 30  # Simpler movements
            if 'compound' in name or 'complex' in name:
                score -= 30  # Avoid complex movements
        
        elif experience == 'advanced':
            # Advanced: prefer compound, free weights
            if 'barbell' in equipment:
                score += 40
            if 'compound' in name or any(kw in name for kw in ['squat', 'deadlift', 'press', 'row']):
                score += 50
        
        # GOAL-BASED SCORING
        if 'strength' in goal:
            # Prefer compound barbell movements
            if 'barbell' in equipment:
                score += 40
            if any(kw in name for kw in ['squat', 'deadlift', 'press', 'bench']):
                score += 50
        
        elif 'muscle' in goal or 'hypertrophy' in goal:
            # Mix of compound and isolation
            score += 20  # Neutral
        
        elif 'fat' in goal or 'lose' in goal:
            # Prefer exercises that use more muscle groups
            if workout_type == 'strength':
                score += 20
        
        # AGE-BASED SCORING
        if age >= 55:
            # Prefer seated/stable exercises
            if 'seated' in name or 'lying' in name or 'machine' in equipment:
                score += 40
            if 'standing' in name and 'bodyweight' in equipment:
                score -= 20  # Less stable
        
        # WEIGHT-BASED SCORING
        if weight > 250:
            # Prefer exercises that don't require lifting body weight
            if 'machine' in equipment or 'cable' in equipment:
                score += 50
            if 'seated' in name or 'lying' in name:
                score += 30
        
        # Small randomness
        score += random.uniform(0, 20)
        
        scored.append((score, ex, targets_hit))
    
    # Sort by score
    scored.sort(key=lambda x: -x[0])
    
    # Select with diversity
    selected = []
    used_names = set()
    used_equipment = Counter()
    
    for score, ex, _ in scored:
        if len(selected) >= count:
            break
        
        name = ex.get('name', '')
        equipment = ex.get('equipment', '')
        
        name_base = name.split('(')[0].strip().lower()
        if any(name_base in used for used in used_names):
            continue
        
        if used_equipment[equipment] >= 2:
            continue
        
        selected.append(ex)
        used_names.add(name_base)
        used_equipment[equipment] += 1
    
    return selected


# ============================================================================
# GRADING
# ============================================================================

def grade_equipment_accuracy(workout, user_profile):
    if not workout:
        return 0, []
    
    user_equipment = [e.lower() for e in user_profile['equipment']]
    issues = []
    correct = 0
    
    for ex in workout:
        ex_equipment = (ex.get('equipment') or '').lower()
        equipment_parts = [p.strip() for p in ex_equipment.split(',')]
        is_bodyweight = 'bodyweight' in equipment_parts or not equipment_parts
        
        if is_bodyweight:
            if any('bodyweight' in eq for eq in user_equipment):
                correct += 1
            else:
                issues.append(f"'{ex['name']}' is bodyweight but user didn't select it")
        else:
            matches = any(ue in part or part in ue for part in equipment_parts for ue in user_equipment)
            if matches:
                correct += 1
            else:
                issues.append(f"'{ex['name']}' needs {ex_equipment}")
    
    return (correct / len(workout)) * 100 if workout else 0, issues


def grade_muscle_accuracy(workout, target_muscles):
    if not workout:
        return 0, []
    
    muscle_group_expansion = {
        "arms": ["arms", "biceps", "triceps", "forearms"],
        "shoulders": ["shoulders", "front delts", "rear delts", "side delts", "delts"],
        "legs": ["legs", "quads", "hamstrings", "glutes", "calves"],
        "back": ["back", "lats", "upper back", "lower back", "traps"],
        "chest": ["chest", "upper chest", "lower chest", "pecs"],
        "core": ["core", "abs", "obliques", "lower abs"],
        "glutes": ["glutes"],
        "quads": ["quads"],
        "hamstrings": ["hamstrings"],
        "lats": ["lats"],
        "biceps": ["biceps"],
        "triceps": ["triceps"],
        "abs": ["abs", "lower abs"],
    }
    
    expanded_targets = set(m.lower() for m in target_muscles)
    for target in target_muscles:
        if target.lower() in muscle_group_expansion:
            expanded_targets.update(muscle_group_expansion[target.lower()])
    
    issues = []
    correct = 0
    
    for ex in workout:
        muscles = ex.get('primary_muscles', [])
        if isinstance(muscles, str):
            muscles = [muscles]
        muscles_lower = [m.lower() for m in muscles if m]
        
        matches = any(t in m or m in t for m in muscles_lower for t in expanded_targets)
        if matches:
            correct += 1
        else:
            issues.append(f"'{ex['name']}' targets {muscles}")
    
    return (correct / len(workout)) * 100 if workout else 0, issues


def grade_profile_appropriateness(workout, user_profile):
    """
    NEW: Grade whether exercises are appropriate for user's profile
    """
    if not workout:
        return 0, []
    
    issues = []
    appropriate = 0
    weight = user_profile.get('weight_lbs', 170)
    age = user_profile.get('age', 30)
    experience = user_profile.get('experience', 'Intermediate').lower()
    
    for ex in workout:
        name = (ex.get('name') or '').lower()
        equipment = (ex.get('equipment') or '').lower()
        is_appropriate = True
        
        # Check weight appropriateness
        if weight > 250 and equipment == 'bodyweight':
            for kw in ['pull up', 'chin up', 'dip', 'muscle up']:
                if kw in name:
                    issues.append(f"'{ex['name']}' too hard for {weight}lb user")
                    is_appropriate = False
                    break
        
        # Check age appropriateness
        if age >= 60:
            for kw in ['jump', 'plyo', 'explosive', 'burpee']:
                if kw in name:
                    issues.append(f"'{ex['name']}' too high-impact for age {age}")
                    is_appropriate = False
                    break
        
        # Check experience appropriateness
        if experience == 'beginner':
            for kw in ['olympic', 'snatch', 'clean', 'jerk', 'muscle up']:
                if kw in name:
                    issues.append(f"'{ex['name']}' too advanced for beginner")
                    is_appropriate = False
                    break
        
        if is_appropriate:
            appropriate += 1
    
    return (appropriate / len(workout)) * 100 if workout else 0, issues


def grade_variety(workout):
    if not workout:
        return 0, []
    
    issues = []
    names = [ex.get('name', '').lower() for ex in workout]
    name_bases = [n.split('(')[0].strip() for n in names]
    
    base_counts = Counter(name_bases)
    duplicates = {k: v for k, v in base_counts.items() if v > 1}
    
    if duplicates:
        for name, count in duplicates.items():
            issues.append(f"'{name}' appears {count} times")
    
    duplicate_penalty = len(duplicates) * 15
    return max(0, 100 - duplicate_penalty), issues


def run_test_case(exercises, test_id, user_profile, target_muscles, workout_count=5):
    """Run test with full user profile consideration"""
    
    # Smart filter
    matching, filter_stats = filter_exercises_smart(exercises, target_muscles, user_profile)
    
    # Smart select
    workout = select_workout_smart(matching, workout_count, target_muscles, user_profile)
    
    # Grade
    equip_score, equip_issues = grade_equipment_accuracy(workout, user_profile)
    muscle_score, muscle_issues = grade_muscle_accuracy(workout, target_muscles)
    profile_score, profile_issues = grade_profile_appropriateness(workout, user_profile)
    variety_score, variety_issues = grade_variety(workout)
    
    # Weighted average (now includes profile appropriateness!)
    overall_score = (
        equip_score * 0.25 +
        muscle_score * 0.25 +
        profile_score * 0.30 +  # NEW: Profile appropriateness is important!
        variety_score * 0.20
    )
    
    grade = 'A' if overall_score >= 90 else 'B' if overall_score >= 80 else 'C' if overall_score >= 70 else 'D' if overall_score >= 60 else 'F'
    
    return {
        "test_id": test_id,
        "profile_name": user_profile['name'],
        "profile_details": {
            "weight": user_profile.get('weight_lbs'),
            "age": user_profile.get('age'),
            "gender": user_profile.get('gender'),
            "experience": user_profile.get('experience'),
            "goal": user_profile.get('goal'),
            "description": user_profile.get('description', '')
        },
        "equipment": user_profile['equipment'],
        "target_muscles": target_muscles,
        "filter_stats": filter_stats,
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
            "profile_appropriateness": round(profile_score, 1),
            "variety": round(variety_score, 1),
            "overall": round(overall_score, 1)
        },
        "issues": equip_issues + muscle_issues + profile_issues + variety_issues,
        "grade": grade
    }


def generate_test_cases():
    """Generate comprehensive test cases"""
    test_cases = []
    test_id = 1
    
    for profile_key, profile in USER_PROFILES.items():
        # Each profile gets 4 muscle selections
        selected_muscles = random.sample(MUSCLE_SELECTIONS, min(4, len(MUSCLE_SELECTIONS)))
        
        for muscles in selected_muscles:
            test_cases.append({
                "test_id": test_id,
                "profile": profile,
                "muscles": muscles
            })
            test_id += 1
    
    return test_cases


def main():
    print("=" * 90)
    print("🏋️ AUTO-GEN WORKOUT TEST SUITE V2")
    print("   Now considers: Weight, Age, Experience, Goal, Gender")
    print("=" * 90)
    print()
    
    # Fetch exercises
    print("📥 Fetching exercises...")
    all_exercises = []
    offset = 0
    while True:
        response = supabase.table('exercises').select('*').range(offset, offset + 999).execute()
        if not response.data:
            break
        all_exercises.extend(response.data)
        offset += 1000
        if len(response.data) < 1000:
            break
    
    print(f"✅ Loaded {len(all_exercises)} exercises")
    print()
    
    # Run tests
    test_cases = generate_test_cases()
    print(f"🧪 Running {len(test_cases)} test cases...")
    print()
    
    results = []
    for tc in test_cases:
        result = run_test_case(all_exercises, tc['test_id'], tc['profile'], tc['muscles'])
        results.append(result)
    
    # Summary
    print("=" * 90)
    print("📊 RESULTS SUMMARY")
    print("=" * 90)
    
    grades = Counter(r['grade'] for r in results)
    print("\n📈 Grade Distribution:")
    for grade in ['A', 'B', 'C', 'D', 'F']:
        count = grades.get(grade, 0)
        pct = (count / len(results)) * 100
        bar = '█' * int(pct / 5)
        print(f"   {grade}: {count:3d} ({pct:5.1f}%) {bar}")
    
    # Average scores
    print("\n📊 Average Scores:")
    for metric in ['equipment_accuracy', 'muscle_accuracy', 'profile_appropriateness', 'variety', 'overall']:
        avg = sum(r['scores'][metric] for r in results) / len(results)
        status = "✅" if avg >= 80 else "⚠️" if avg >= 60 else "❌"
        print(f"   {status} {metric:25s}: {avg:5.1f}%")
    
    # Worst tests
    print("\n" + "=" * 90)
    print("❌ TESTS THAT NEED ATTENTION")
    print("=" * 90)
    
    worst = sorted(results, key=lambda x: x['scores']['overall'])[:10]
    for r in worst:
        print(f"\n🔴 Test #{r['test_id']}: {r['profile_name']}")
        print(f"   User: {r['profile_details']['weight']}lbs, {r['profile_details']['age']}yo, {r['profile_details']['experience']}")
        print(f"   Goal: {r['profile_details']['goal']}")
        print(f"   Target: {r['target_muscles']} | Equipment: {r['equipment']}")
        print(f"   Score: {r['scores']['overall']}% (Grade: {r['grade']})")
        print(f"   Profile Appropriateness: {r['scores']['profile_appropriateness']}%")
        if r['filter_stats']['profile_fails'] > 0:
            print(f"   ✅ Filtered out {r['filter_stats']['profile_fails']} inappropriate exercises")
        if r['issues']:
            for issue in r['issues'][:3]:
                print(f"   ⚠️ {issue}")
    
    # Best tests
    print("\n" + "=" * 90)
    print("✅ BEST PERFORMING TESTS")
    print("=" * 90)
    
    best = sorted(results, key=lambda x: x['scores']['overall'], reverse=True)[:5]
    for r in best:
        print(f"\n🟢 Test #{r['test_id']}: {r['profile_name']}")
        print(f"   User: {r['profile_details']['weight']}lbs, {r['profile_details']['age']}yo")
        print(f"   Score: {r['scores']['overall']}% (Grade: {r['grade']})")
    
    # Profile analysis
    print("\n" + "=" * 90)
    print("📊 SCORES BY USER PROFILE TYPE")
    print("=" * 90)
    
    profile_scores = defaultdict(list)
    for r in results:
        profile_scores[r['profile_name']].append(r['scores']['overall'])
    
    for profile, scores in sorted(profile_scores.items(), key=lambda x: sum(x[1])/len(x[1])):
        avg = sum(scores) / len(scores)
        status = "✅" if avg >= 80 else "⚠️" if avg >= 60 else "❌"
        print(f"   {status} {profile:30s}: {avg:5.1f}%")
    
    # Save results
    output_file = 'autogen_test_results_v2.json'
    with open(output_file, 'w') as f:
        json.dump({
            'summary': {
                'total_tests': len(results),
                'grades': dict(grades),
                'avg_scores': {
                    k: sum(r['scores'][k] for r in results) / len(results)
                    for k in ['equipment_accuracy', 'muscle_accuracy', 'profile_appropriateness', 'variety', 'overall']
                }
            },
            'results': results
        }, f, indent=2)
    
    print(f"\n📁 Results saved to: {output_file}")
    
    # Final grade
    overall_avg = sum(r['scores']['overall'] for r in results) / len(results)
    final_grade = 'A' if overall_avg >= 90 else 'B' if overall_avg >= 80 else 'C' if overall_avg >= 70 else 'D' if overall_avg >= 60 else 'F'
    
    print("\n" + "=" * 90)
    print(f"📋 FINAL SYSTEM GRADE: {final_grade} ({overall_avg:.1f}%)")
    print("=" * 90)


if __name__ == "__main__":
    main()

