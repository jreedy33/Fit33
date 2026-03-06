#!/usr/bin/env python3
"""
Exercise Family & Swap System Test Suite
=========================================
Tests the new intelligent exercise swap system with:
- exercise_family relationships
- complementary_families recommendations
- equipment_category consistency
- priority scoring (build_muscle, get_lean, home, gym)

Generates 10 specialized test users to validate all relationships.
Returns full audit results for manual review.
"""

import os
import load_env  # noqa: F401 — auto-loads .env credentials
import json
import random
from datetime import datetime
from supabase import create_client
from collections import Counter, defaultdict

# Supabase credentials
SUPABASE_URL = os.environ.get("SUPABASE_URL", "https://ehooeghabzefgoqzugrc.supabase.co")
SUPABASE_KEY = os.environ.get("SUPABASE_ANON_KEY", "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVob29lZ2hhYnplZmdvcXp1Z3JjIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjM4NDc4NjQsImV4cCI6MjA3OTQyMzg2NH0.6-QWDr5B279hybtu9MbPVhmBKlyzFq1GK9P7zlDXuY0")

supabase = create_client(SUPABASE_URL, SUPABASE_KEY)

# ============================================================================
# 10 SPECIALIZED TEST USERS FOR FAMILY/SWAP VALIDATION
# ============================================================================

FAMILY_TEST_USERS = {
    # --- SWAP LOGIC TESTERS ---
    "curl_family_tester": {
        "name": "Curl Family Tester",
        "description": "Tests bicep curl family: should get barbell curl, cable curl, hammer curl as variants",
        "weight_lbs": 180,
        "age": 28,
        "gender": "male",
        "experience": "Intermediate",
        "goal": "Build Muscle",
        "equipment": ["Barbell", "Dumbbells", "Cables"],
        "location": "gym",
        "test_exercise": "bicep_curl",
        "expected_families": ["bicep_curl", "hammer_curl", "preacher_curl", "concentration_curl"],
        "expected_complementary": ["tricep_extension", "tricep_pushdown", "hammer_curl"]
    },
    
    "bench_press_swapper": {
        "name": "Bench Press Equipment Swapper",
        "description": "Tests bench_press family: barbell/dumbbell/smith machine/machine variants",
        "weight_lbs": 200,
        "age": 32,
        "gender": "male",
        "experience": "Advanced",
        "goal": "Build Muscle",
        "equipment": ["Barbell", "Dumbbells", "Machines"],
        "location": "gym",
        "test_exercise": "bench_press",
        "expected_families": ["bench_press", "incline_bench_press", "decline_bench_press"],
        "expected_complementary": ["fly", "incline_bench_press", "tricep_pushdown", "dip"]
    },
    
    "squat_family_tester": {
        "name": "Squat Family Validator",
        "description": "Tests squat variants: goblet, front, back, hack, sumo squat",
        "weight_lbs": 175,
        "age": 26,
        "gender": "female",
        "experience": "Intermediate",
        "goal": "Build Muscle",
        "equipment": ["Barbell", "Dumbbells", "Machines"],
        "location": "gym",
        "test_exercise": "squat",
        "expected_families": ["squat", "goblet_squat", "front_squat", "hack_squat", "sumo_squat"],
        "expected_complementary": ["leg_press", "leg_extension", "leg_curl", "lunge"]
    },
    
    # --- PRIORITY SCORING TESTERS ---
    "home_priority_user": {
        "name": "Home Workout Priority Tester",
        "description": "Tests priority_home scoring: bodyweight/dumbbell should rank highest",
        "weight_lbs": 160,
        "age": 35,
        "gender": "female",
        "experience": "Intermediate",
        "goal": "Get Lean",
        "equipment": ["Bodyweight", "Dumbbells", "Resistance Bands"],
        "location": "home",
        "test_exercise": "push_up",
        "expected_priority_order": ["bodyweight", "dumbbell", "band"],
        "priority_key": "priority_home"
    },
    
    "gym_muscle_priority": {
        "name": "Gym Muscle Building Priority",
        "description": "Tests priority_build_muscle: barbell should rank highest",
        "weight_lbs": 190,
        "age": 29,
        "gender": "male",
        "experience": "Advanced",
        "goal": "Build Muscle",
        "equipment": ["Barbell", "Dumbbells", "Cables", "Machines"],
        "location": "gym",
        "test_exercise": "lat_pulldown",
        "expected_priority_order": ["barbell", "dumbbell", "cable", "machine"],
        "priority_key": "priority_build_muscle"
    },
    
    "get_lean_priority": {
        "name": "Get Lean Circuit Priority",
        "description": "Tests priority_get_lean: dumbbell/cable/bodyweight for circuits",
        "weight_lbs": 155,
        "age": 27,
        "gender": "female",
        "experience": "Intermediate",
        "goal": "Get Lean",
        "equipment": ["Dumbbells", "Cables", "Bodyweight"],
        "location": "gym",
        "test_exercise": "lunge",
        "expected_priority_order": ["dumbbell", "cable", "bodyweight"],
        "priority_key": "priority_get_lean"
    },
    
    # --- COMPLEMENTARY RELATIONSHIP TESTERS ---
    "antagonist_tester": {
        "name": "Antagonist Muscle Pairing",
        "description": "Tests complementary_families for antagonist pairs (bicep/tricep, chest/back)",
        "weight_lbs": 185,
        "age": 30,
        "gender": "male",
        "experience": "Intermediate",
        "goal": "Build Muscle",
        "equipment": ["Barbell", "Dumbbells", "Cables"],
        "location": "gym",
        "test_exercise": "tricep_pushdown",
        "expected_complementary": ["bicep_curl", "tricep_extension", "dip"]
    },
    
    "compound_to_isolation": {
        "name": "Compound to Isolation Pairing",
        "description": "Tests complementary from compound to isolation (squat -> leg extension)",
        "weight_lbs": 195,
        "age": 34,
        "gender": "male",
        "experience": "Advanced",
        "goal": "Build Muscle",
        "equipment": ["Barbell", "Dumbbells", "Machines"],
        "location": "gym",
        "test_exercise": "deadlift",
        "expected_complementary": ["romanian_deadlift", "leg_curl", "back_extension", "hip_thrust"]
    },
    
    # --- EQUIPMENT CATEGORY TESTERS ---
    "equipment_category_validator": {
        "name": "Equipment Category Consistency",
        "description": "Tests equipment_category matches actual equipment field",
        "weight_lbs": 170,
        "age": 25,
        "gender": "female",
        "experience": "Beginner",
        "goal": "General Fitness",
        "equipment": ["Machines", "Cables"],
        "location": "gym",
        "test_exercise": "lat_pulldown",
        "validate_equipment_category": True
    },
    
    "bodyweight_only_tester": {
        "name": "Bodyweight Only Home User",
        "description": "Tests that bodyweight alternatives exist for major movements",
        "weight_lbs": 145,
        "age": 22,
        "gender": "female",
        "experience": "Beginner",
        "goal": "General Fitness",
        "equipment": ["Bodyweight"],
        "location": "home",
        "test_exercise": "push_up",
        "must_have_bodyweight_variants": True
    }
}

# ============================================================================
# TEST FUNCTIONS
# ============================================================================

def fetch_all_exercises():
    """Fetch all exercises with new family columns"""
    print("📥 Fetching exercises with family data...")
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
    
    return all_exercises


def get_family_stats(exercises):
    """Get statistics about exercise families"""
    family_counts = Counter()
    with_family = 0
    without_family = 0
    
    equipment_categories = Counter()
    priority_coverage = {
        'build_muscle': 0,
        'get_lean': 0,
        'home': 0,
        'gym': 0
    }
    
    for ex in exercises:
        family = ex.get('exercise_family')
        if family:
            family_counts[family] += 1
            with_family += 1
        else:
            without_family += 1
        
        eq_cat = ex.get('equipment_category')
        if eq_cat:
            equipment_categories[eq_cat] += 1
        
        # Check priority coverage
        if ex.get('priority_build_muscle'):
            priority_coverage['build_muscle'] += 1
        if ex.get('priority_get_lean'):
            priority_coverage['get_lean'] += 1
        if ex.get('priority_home'):
            priority_coverage['home'] += 1
        if ex.get('priority_gym'):
            priority_coverage['gym'] += 1
    
    return {
        'total': len(exercises),
        'with_family': with_family,
        'without_family': without_family,
        'family_coverage_pct': round((with_family / len(exercises)) * 100, 1) if exercises else 0,
        'unique_families': len(family_counts),
        'top_families': family_counts.most_common(20),
        'equipment_categories': dict(equipment_categories),
        'priority_coverage': priority_coverage
    }


def find_equipment_variants(exercises, target_family, exclude_name=None):
    """Find all equipment variants within a family"""
    variants = []
    for ex in exercises:
        if ex.get('exercise_family') == target_family:
            if exclude_name and ex.get('name') == exclude_name:
                continue
            variants.append({
                'name': ex.get('name'),
                'equipment': ex.get('equipment'),
                'equipment_category': ex.get('equipment_category'),
                'priority_build_muscle': ex.get('priority_build_muscle'),
                'priority_get_lean': ex.get('priority_get_lean'),
                'priority_home': ex.get('priority_home'),
                'priority_gym': ex.get('priority_gym'),
                'is_equipment_primary': ex.get('is_equipment_primary', False)
            })
    return variants


def find_complementary_exercises(exercises, complementary_families_str, limit=5):
    """Find exercises from complementary families"""
    if not complementary_families_str:
        return []
    
    # Parse comma-separated families
    families = [f.strip().lower() for f in complementary_families_str.split(',') if f.strip()]
    
    complementary = []
    seen_families = set()
    
    for ex in exercises:
        ex_family = (ex.get('exercise_family') or '').lower()
        if ex_family in families and ex_family not in seen_families:
            # Prefer primary equipment variants
            if ex.get('is_equipment_primary'):
                complementary.insert(0, {
                    'name': ex.get('name'),
                    'family': ex.get('exercise_family'),
                    'equipment': ex.get('equipment'),
                    'is_primary': True
                })
                seen_families.add(ex_family)
            elif len(complementary) < limit * 2:
                complementary.append({
                    'name': ex.get('name'),
                    'family': ex.get('exercise_family'),
                    'equipment': ex.get('equipment'),
                    'is_primary': False
                })
    
    return complementary[:limit]


def validate_equipment_category(exercises):
    """Check if equipment_category matches the exercise's equipment field"""
    mismatches = []
    
    equipment_keywords = {
        'barbell': ['barbell', 'ez bar', 'olympic bar'],
        'dumbbell': ['dumbbell', 'dumbell'],
        'cable': ['cable', 'pulley'],
        'machine': ['machine', 'lever', 'smith machine', 'selectorized'],
        'kettlebell': ['kettlebell', 'kb'],
        'band': ['band', 'resistance band'],
        'bodyweight': ['bodyweight', 'body weight', '']
    }
    
    for ex in exercises:
        eq_cat = (ex.get('equipment_category') or '').lower()
        equipment = (ex.get('equipment') or '').lower()
        
        if not eq_cat:
            continue
        
        # Check if equipment field contains keywords matching category
        expected_keywords = equipment_keywords.get(eq_cat, [])
        if expected_keywords:
            has_match = any(kw in equipment for kw in expected_keywords if kw)
            if not has_match and equipment and equipment != 'bodyweight':
                # Special case: bodyweight can be empty equipment
                if eq_cat != 'bodyweight':
                    mismatches.append({
                        'name': ex.get('name'),
                        'equipment': equipment,
                        'equipment_category': eq_cat,
                        'expected_keywords': expected_keywords
                    })
    
    return mismatches


def test_priority_ordering(exercises, family, priority_key, expected_order):
    """Test if exercises are correctly prioritized by equipment type"""
    # Get all exercises in family
    family_exercises = [ex for ex in exercises if ex.get('exercise_family') == family]
    
    if not family_exercises:
        return {'success': False, 'reason': f'No exercises found in family: {family}'}
    
    # Group by equipment category
    by_equipment = defaultdict(list)
    for ex in family_exercises:
        eq_cat = ex.get('equipment_category', 'unknown')
        priority = ex.get(priority_key, 50)
        by_equipment[eq_cat].append({
            'name': ex.get('name'),
            'priority': priority
        })
    
    # Calculate average priority per equipment type
    avg_priorities = {}
    for eq_cat, exs in by_equipment.items():
        avg_priorities[eq_cat] = sum(e['priority'] for e in exs) / len(exs)
    
    # Sort by average priority (descending)
    sorted_equipment = sorted(avg_priorities.items(), key=lambda x: -x[1])
    actual_order = [eq[0] for eq in sorted_equipment]
    
    # Check if order matches expected (allowing for missing categories)
    expected_present = [eq for eq in expected_order if eq in actual_order]
    actual_filtered = [eq for eq in actual_order if eq in expected_order]
    
    # Calculate order match score
    matches = sum(1 for i, eq in enumerate(expected_present) if i < len(actual_filtered) and actual_filtered[i] == eq)
    order_score = (matches / len(expected_present)) * 100 if expected_present else 0
    
    return {
        'success': order_score >= 70,
        'order_score': round(order_score, 1),
        'expected_order': expected_order,
        'actual_order': actual_order,
        'avg_priorities': avg_priorities,
        'family': family,
        'priority_key': priority_key
    }


def run_user_test(user_key, user_profile, exercises):
    """Run a comprehensive test for a single user profile"""
    result = {
        'user_key': user_key,
        'profile': {
            'name': user_profile['name'],
            'description': user_profile['description'],
            'weight': user_profile['weight_lbs'],
            'age': user_profile['age'],
            'gender': user_profile['gender'],
            'experience': user_profile['experience'],
            'goal': user_profile['goal'],
            'equipment': user_profile['equipment'],
            'location': user_profile['location']
        },
        'tests': {},
        'scores': {},
        'issues': [],
        'details': {}
    }
    
    test_family = user_profile.get('test_exercise')
    
    # TEST 1: Find exercises in the target family
    if test_family:
        family_exercises = [ex for ex in exercises if ex.get('exercise_family') == test_family]
        result['tests']['family_exercises_found'] = len(family_exercises)
        
        if family_exercises:
            # Get sample exercises with details
            result['details']['family_exercises'] = [
                {
                    'name': ex.get('name'),
                    'equipment': ex.get('equipment'),
                    'equipment_category': ex.get('equipment_category'),
                    'base_name': ex.get('base_exercise_name'),
                    'is_primary': ex.get('is_equipment_primary', False)
                }
                for ex in family_exercises[:10]
            ]
            result['scores']['family_found'] = 100
        else:
            result['issues'].append(f"No exercises found in family: {test_family}")
            result['scores']['family_found'] = 0
    
    # TEST 2: Equipment variants
    if test_family:
        variants = find_equipment_variants(exercises, test_family)
        
        # Check equipment diversity
        equipment_types = set(v.get('equipment_category') for v in variants if v.get('equipment_category'))
        
        result['tests']['equipment_variants'] = len(variants)
        result['tests']['equipment_types'] = list(equipment_types)
        result['details']['equipment_variants'] = variants[:8]
        
        # Score: Good if 3+ equipment types, excellent if 4+
        if len(equipment_types) >= 4:
            result['scores']['equipment_diversity'] = 100
        elif len(equipment_types) >= 3:
            result['scores']['equipment_diversity'] = 85
        elif len(equipment_types) >= 2:
            result['scores']['equipment_diversity'] = 70
        elif len(equipment_types) >= 1:
            result['scores']['equipment_diversity'] = 50
        else:
            result['scores']['equipment_diversity'] = 0
            result['issues'].append(f"No equipment variants for {test_family}")
    
    # TEST 3: Complementary families
    expected_complementary = user_profile.get('expected_complementary', [])
    if expected_complementary and family_exercises:
        # Get complementary_families from first exercise in family
        sample_ex = family_exercises[0]
        comp_families = sample_ex.get('complementary_families', '')
        
        if comp_families:
            # Check if expected families are in complementary
            comp_list = [f.strip().lower() for f in comp_families.split(',')]
            matches = sum(1 for exp in expected_complementary if exp.lower() in comp_list)
            match_pct = (matches / len(expected_complementary)) * 100
            
            result['tests']['complementary_match'] = matches
            result['tests']['complementary_total'] = len(expected_complementary)
            result['details']['complementary_families'] = comp_list
            result['details']['expected_complementary'] = expected_complementary
            result['scores']['complementary_accuracy'] = round(match_pct, 1)
            
            # Find actual complementary exercises
            comp_exercises = find_complementary_exercises(exercises, comp_families)
            result['details']['complementary_exercises'] = comp_exercises
            
            if match_pct < 50:
                result['issues'].append(f"Only {matches}/{len(expected_complementary)} expected complementary families found")
        else:
            result['scores']['complementary_accuracy'] = 0
            result['issues'].append("No complementary_families data found")
    
    # TEST 4: Priority ordering
    if 'priority_key' in user_profile and 'expected_priority_order' in user_profile:
        priority_result = test_priority_ordering(
            exercises,
            test_family,
            user_profile['priority_key'],
            user_profile['expected_priority_order']
        )
        
        result['tests']['priority_order_correct'] = priority_result['success']
        result['scores']['priority_ordering'] = priority_result['order_score']
        result['details']['priority_test'] = priority_result
        
        if not priority_result['success']:
            result['issues'].append(f"Priority order incorrect for {user_profile['priority_key']}")
    
    # TEST 5: Equipment category validation
    if user_profile.get('validate_equipment_category'):
        mismatches = validate_equipment_category(exercises[:500])  # Sample
        result['tests']['equipment_mismatches'] = len(mismatches)
        result['details']['equipment_mismatches'] = mismatches[:5]
        
        mismatch_rate = (len(mismatches) / 500) * 100
        result['scores']['equipment_category_accuracy'] = round(100 - mismatch_rate, 1)
        
        if len(mismatches) > 10:
            result['issues'].append(f"{len(mismatches)} equipment category mismatches found")
    
    # TEST 6: Bodyweight availability
    if user_profile.get('must_have_bodyweight_variants'):
        # Check major movement patterns have bodyweight options
        key_families = ['push_up', 'squat', 'lunge', 'plank', 'crunch']
        bw_coverage = {}
        
        for family in key_families:
            bw_exercises = [
                ex for ex in exercises 
                if ex.get('exercise_family') == family 
                and ex.get('equipment_category') == 'bodyweight'
            ]
            bw_coverage[family] = len(bw_exercises)
        
        covered = sum(1 for v in bw_coverage.values() if v > 0)
        coverage_pct = (covered / len(key_families)) * 100
        
        result['tests']['bodyweight_coverage'] = bw_coverage
        result['scores']['bodyweight_availability'] = round(coverage_pct, 1)
        result['details']['bodyweight_coverage'] = bw_coverage
    
    # CALCULATE OVERALL SCORE
    all_scores = [v for v in result['scores'].values() if isinstance(v, (int, float))]
    result['overall_score'] = round(sum(all_scores) / len(all_scores), 1) if all_scores else 0
    result['grade'] = (
        'A' if result['overall_score'] >= 90 else
        'B' if result['overall_score'] >= 80 else
        'C' if result['overall_score'] >= 70 else
        'D' if result['overall_score'] >= 60 else 'F'
    )
    
    return result


def simulate_swap_sequence(exercises, start_exercise_name, num_swaps=5):
    """Simulate the swap sequence: 2 equipment variants, then complementary"""
    swap_log = []
    
    # Find the starting exercise
    start_ex = next((ex for ex in exercises if ex.get('name') == start_exercise_name), None)
    if not start_ex:
        # Try partial match
        start_ex = next((ex for ex in exercises if start_exercise_name.lower() in (ex.get('name') or '').lower()), None)
    
    if not start_ex:
        return {'error': f"Exercise not found: {start_exercise_name}", 'swaps': []}
    
    current_family = start_ex.get('exercise_family')
    comp_families = start_ex.get('complementary_families', '')
    excluded_names = {start_ex.get('name')}
    
    swap_log.append({
        'swap_num': 0,
        'type': 'original',
        'name': start_ex.get('name'),
        'family': current_family,
        'equipment': start_ex.get('equipment'),
        'reason': 'Starting exercise'
    })
    
    # Swaps 1-2: Equipment variants (same family)
    for swap_num in range(1, 3):
        variants = [
            ex for ex in exercises
            if ex.get('exercise_family') == current_family
            and ex.get('name') not in excluded_names
        ]
        
        # Sort by priority (could be goal-specific)
        variants.sort(key=lambda x: -(x.get('priority_build_muscle') or 0))
        
        if variants:
            selected = variants[0]
            excluded_names.add(selected.get('name'))
            
            swap_log.append({
                'swap_num': swap_num,
                'type': 'equipment_variant',
                'name': selected.get('name'),
                'family': selected.get('exercise_family'),
                'equipment': selected.get('equipment'),
                'equipment_category': selected.get('equipment_category'),
                'reason': f"Same movement ({current_family}), different equipment"
            })
        else:
            swap_log.append({
                'swap_num': swap_num,
                'type': 'no_variant',
                'reason': f"No more equipment variants in {current_family}"
            })
    
    # Swaps 3+: Complementary exercises
    if comp_families:
        comp_list = [f.strip().lower() for f in comp_families.split(',') if f.strip()]
        
        for swap_num in range(3, num_swaps + 1):
            complementary = [
                ex for ex in exercises
                if (ex.get('exercise_family') or '').lower() in comp_list
                and ex.get('name') not in excluded_names
            ]
            
            # Prefer primary equipment variants
            complementary.sort(key=lambda x: (
                -(1 if x.get('is_equipment_primary') else 0),
                -(x.get('priority_build_muscle') or 0)
            ))
            
            if complementary:
                selected = complementary[0]
                excluded_names.add(selected.get('name'))
                
                swap_log.append({
                    'swap_num': swap_num,
                    'type': 'complementary',
                    'name': selected.get('name'),
                    'family': selected.get('exercise_family'),
                    'equipment': selected.get('equipment'),
                    'reason': f"Complementary exercise (user wants different movement)"
                })
            else:
                swap_log.append({
                    'swap_num': swap_num,
                    'type': 'no_complementary',
                    'reason': 'No more complementary exercises available'
                })
    
    return {
        'starting_exercise': start_exercise_name,
        'starting_family': current_family,
        'complementary_families': comp_families,
        'swaps': swap_log
    }


# ============================================================================
# MAIN TEST RUNNER
# ============================================================================

def main():
    print("=" * 100)
    print("🔄 EXERCISE FAMILY & SWAP SYSTEM TEST SUITE")
    print("   Testing: exercise_family, complementary_families, equipment_category, priority scores")
    print("=" * 100)
    print()
    
    # Fetch all exercises
    exercises = fetch_all_exercises()
    print(f"✅ Loaded {len(exercises)} exercises")
    
    # Get family statistics
    print("\n" + "=" * 100)
    print("📊 EXERCISE FAMILY STATISTICS")
    print("=" * 100)
    
    stats = get_family_stats(exercises)
    print(f"\n📈 Coverage:")
    print(f"   Total exercises: {stats['total']}")
    print(f"   With family: {stats['with_family']} ({stats['family_coverage_pct']}%)")
    print(f"   Without family: {stats['without_family']}")
    print(f"   Unique families: {stats['unique_families']}")
    
    print(f"\n📊 Top 15 Families:")
    for family, count in stats['top_families'][:15]:
        print(f"   {family:30s}: {count:4d} exercises")
    
    print(f"\n🏋️ Equipment Categories:")
    for eq_cat, count in sorted(stats['equipment_categories'].items(), key=lambda x: -x[1]):
        print(f"   {eq_cat:20s}: {count:4d}")
    
    print(f"\n🎯 Priority Score Coverage:")
    for priority, count in stats['priority_coverage'].items():
        pct = (count / stats['total']) * 100 if stats['total'] else 0
        print(f"   {priority:20s}: {count:4d} ({pct:.1f}%)")
    
    # Run user tests
    print("\n" + "=" * 100)
    print("🧪 RUNNING 10 SPECIALIZED USER TESTS")
    print("=" * 100)
    
    all_results = []
    
    for user_key, user_profile in FAMILY_TEST_USERS.items():
        print(f"\n{'─' * 80}")
        print(f"🔬 Testing: {user_profile['name']}")
        print(f"   {user_profile['description']}")
        
        result = run_user_test(user_key, user_profile, exercises)
        all_results.append(result)
        
        print(f"   Score: {result['overall_score']}% (Grade: {result['grade']})")
        
        if result['issues']:
            for issue in result['issues'][:3]:
                print(f"   ⚠️ {issue}")
    
    # Swap sequence simulations
    print("\n" + "=" * 100)
    print("🔄 SWAP SEQUENCE SIMULATIONS")
    print("=" * 100)
    
    swap_tests = [
        ("Barbell Bench Press", "bench_press"),
        ("Dumbbell Bicep Curl", "bicep_curl"),
        ("Barbell Squat", "squat"),
        ("Lat Pulldown (Cable)", "lat_pulldown"),
        ("Romanian Deadlift (Barbell)", "romanian_deadlift")
    ]
    
    swap_results = []
    for ex_name, family in swap_tests:
        # Find an exercise in this family
        sample = next((ex for ex in exercises if ex.get('exercise_family') == family), None)
        if sample:
            swap_result = simulate_swap_sequence(exercises, sample.get('name'), num_swaps=5)
            swap_results.append(swap_result)
            
            print(f"\n📍 Starting: {swap_result.get('starting_exercise', ex_name)}")
            print(f"   Family: {swap_result.get('starting_family')}")
            print(f"   Complementary: {swap_result.get('complementary_families', 'None')[:50]}...")
            
            for swap in swap_result.get('swaps', [])[1:]:  # Skip original
                icon = "🔄" if swap['type'] == 'equipment_variant' else "✨" if swap['type'] == 'complementary' else "❌"
                print(f"   {icon} Swap {swap['swap_num']}: {swap.get('name', swap.get('reason', 'N/A'))}")
                if swap.get('equipment'):
                    print(f"      Equipment: {swap['equipment']}")
    
    # Summary
    print("\n" + "=" * 100)
    print("📊 FINAL SUMMARY")
    print("=" * 100)
    
    grades = Counter(r['grade'] for r in all_results)
    print("\n📈 Grade Distribution:")
    for grade in ['A', 'B', 'C', 'D', 'F']:
        count = grades.get(grade, 0)
        pct = (count / len(all_results)) * 100
        bar = '█' * int(pct / 10)
        print(f"   {grade}: {count:2d} ({pct:5.1f}%) {bar}")
    
    avg_score = sum(r['overall_score'] for r in all_results) / len(all_results)
    print(f"\n📊 Average Score: {avg_score:.1f}%")
    
    final_grade = 'A' if avg_score >= 90 else 'B' if avg_score >= 80 else 'C' if avg_score >= 70 else 'D' if avg_score >= 60 else 'F'
    print(f"\n🏆 FINAL SYSTEM GRADE: {final_grade}")
    
    # Detailed results for manual review
    print("\n" + "=" * 100)
    print("📋 DETAILED RESULTS FOR MANUAL AUDIT")
    print("=" * 100)
    
    for result in all_results:
        print(f"\n{'═' * 80}")
        print(f"👤 USER: {result['profile']['name']}")
        print(f"{'═' * 80}")
        print(f"📝 Description: {result['profile']['description']}")
        print(f"📊 Profile:")
        print(f"   Weight: {result['profile']['weight']}lbs | Age: {result['profile']['age']}")
        print(f"   Experience: {result['profile']['experience']} | Goal: {result['profile']['goal']}")
        print(f"   Equipment: {', '.join(result['profile']['equipment'])}")
        print(f"   Location: {result['profile']['location']}")
        
        print(f"\n🧪 Test Results:")
        for test_name, test_value in result['tests'].items():
            print(f"   {test_name}: {test_value}")
        
        print(f"\n📊 Scores:")
        for score_name, score_value in result['scores'].items():
            status = "✅" if score_value >= 80 else "⚠️" if score_value >= 60 else "❌"
            print(f"   {status} {score_name}: {score_value}%")
        
        print(f"\n🎯 Overall: {result['overall_score']}% (Grade: {result['grade']})")
        
        if result['issues']:
            print(f"\n⚠️ Issues:")
            for issue in result['issues']:
                print(f"   • {issue}")
        
        # Show detailed data
        if result['details'].get('family_exercises'):
            print(f"\n📋 Family Exercises (sample):")
            for ex in result['details']['family_exercises'][:5]:
                primary = "⭐" if ex.get('is_primary') else "  "
                print(f"   {primary} {ex['name'][:50]:50s} | {ex.get('equipment_category', 'N/A'):10s}")
        
        if result['details'].get('complementary_exercises'):
            print(f"\n🔗 Complementary Exercises:")
            for ex in result['details']['complementary_exercises'][:5]:
                print(f"   • {ex['name'][:50]:50s} ({ex['family']})")
        
        if result['details'].get('priority_test'):
            pt = result['details']['priority_test']
            print(f"\n📊 Priority Test ({pt.get('priority_key', 'N/A')}):")
            print(f"   Expected: {pt.get('expected_order')}")
            print(f"   Actual: {pt.get('actual_order')}")
            if pt.get('avg_priorities'):
                print(f"   Avg Priorities: {dict(list(pt['avg_priorities'].items())[:5])}")
    
    # Save full results to JSON
    output_file = 'exercise_family_test_results.json'
    with open(output_file, 'w') as f:
        json.dump({
            'timestamp': datetime.now().isoformat(),
            'stats': stats,
            'user_tests': all_results,
            'swap_simulations': swap_results,
            'summary': {
                'total_tests': len(all_results),
                'avg_score': avg_score,
                'grades': dict(grades),
                'final_grade': final_grade
            }
        }, f, indent=2, default=str)
    
    print(f"\n📁 Full results saved to: {output_file}")
    
    print("\n" + "=" * 100)
    print("✅ TEST SUITE COMPLETE")
    print("=" * 100)


if __name__ == "__main__":
    main()
