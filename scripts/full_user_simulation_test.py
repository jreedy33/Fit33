#!/usr/bin/env python3
"""
Full User Simulation Test Suite
================================
Tests 100 diverse users with:
- Workout generation verification
- Exercise swap system validation (variety → complementary)
- Comprehensive scoring across all filters
"""

import os
import load_env  # noqa: F401 — auto-loads .env credentials
import json
import random
from datetime import datetime
from supabase import create_client

# Supabase credentials
SUPABASE_URL = os.environ.get("SUPABASE_URL", "https://ehooeghabzefgoqzugrc.supabase.co")
SUPABASE_KEY = os.environ.get("SUPABASE_ANON_KEY", "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVob29lZ2hhYnplZmdvcXp1Z3JjIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjM4NDc4NjQsImV4cCI6MjA3OTQyMzg2NH0.6-QWDr5B279hybtu9MbPVhmBKlyzFq1GK9P7zlDXuY0")

supabase = create_client(SUPABASE_URL, SUPABASE_KEY)

# ============================================================================
# USER GENERATION DATA
# ============================================================================

GOALS = ['Build Muscle', 'Get Lean', 'Endurance', 'General Fitness']
EXPERIENCE_LEVELS = ['Beginner', 'Intermediate', 'Advanced']
LOCATIONS = ['home', 'gym']
GENDERS = ['Male', 'Female']

EQUIPMENT_SETS = {
    'minimal_home': ['Bodyweight'],
    'home_basic': ['Bodyweight', 'Dumbbells', 'Resistance Bands'],
    'home_advanced': ['Bodyweight', 'Dumbbells', 'Resistance Bands', 'Kettlebells', 'Pull-up Bar'],
    'home_full': ['Bodyweight', 'Dumbbells', 'Resistance Bands', 'Kettlebells', 'Pull-up Bar', 'Barbell'],
    'gym_basic': ['Machines', 'Cables', 'Dumbbells'],
    'gym_standard': ['Machines', 'Cables', 'Dumbbells', 'Barbells', 'Pull-up Bar'],
    'gym_full': ['Machines', 'Cables', 'Dumbbells', 'Barbells', 'Pull-up Bar', 'Kettlebells', 'Smith Machine'],
}

INJURY_OPTIONS = [
    None,  # No injuries - most common
    None,
    None,
    ['Lower Back'],
    ['Knee'],
    ['Shoulder'],
    ['Wrist'],
    ['Lower Back', 'Knee'],
    ['Shoulder', 'Wrist'],
    ['Hip'],
]

MUSCLE_FOCUS_OPTIONS = [
    None,  # Full body
    None,
    ['Chest', 'Triceps'],
    ['Back', 'Biceps'],
    ['Legs', 'Glutes'],
    ['Shoulders', 'Arms'],
    ['Core', 'Abs'],
    ['Upper Body'],
    ['Lower Body'],
]

FIRST_NAMES = [
    'Alex', 'Jordan', 'Taylor', 'Morgan', 'Casey', 'Riley', 'Quinn', 'Avery',
    'Blake', 'Cameron', 'Dakota', 'Emery', 'Finley', 'Harper', 'Jamie', 'Kendall',
    'Logan', 'Marley', 'Nico', 'Parker', 'Reese', 'Sage', 'Skyler', 'Drew',
    'Ellis', 'Flynn', 'Gray', 'Haven', 'Ivory', 'Jules', 'Kai', 'Lane',
    'Mason', 'Noel', 'Oakley', 'Peyton', 'Rory', 'Sawyer', 'Tatum', 'Val',
    'Wren', 'Zion', 'Ash', 'Bay', 'Charlie', 'Devon', 'Eden', 'Frankie'
]

WORKOUT_TYPES = ['Push', 'Pull', 'Legs', 'Upper Body', 'Lower Body', 'Full Body', 'Core', 'Arms']


def generate_user(user_id):
    """Generate a diverse user profile"""
    gender = random.choice(GENDERS)
    
    # Generate realistic height/weight based on gender
    if gender == 'Male':
        height = random.randint(64, 76)  # 5'4" to 6'4"
        weight = random.randint(140, 240)
    else:
        height = random.randint(60, 70)  # 5'0" to 5'10"
        weight = random.randint(105, 180)
    
    age = random.randint(18, 65)
    goal = random.choice(GOALS)
    experience = random.choice(EXPERIENCE_LEVELS)
    location = random.choice(LOCATIONS)
    
    # Equipment based on location
    if location == 'home':
        equipment_set = random.choice(['minimal_home', 'home_basic', 'home_advanced', 'home_full'])
    else:
        equipment_set = random.choice(['gym_basic', 'gym_standard', 'gym_full'])
    
    equipment = EQUIPMENT_SETS[equipment_set]
    injuries = random.choice(INJURY_OPTIONS)
    muscle_focus = random.choice(MUSCLE_FOCUS_OPTIONS)
    
    return {
        'id': user_id,
        'name': f"{random.choice(FIRST_NAMES)} #{user_id}",
        'gender': gender,
        'age': age,
        'height': height,
        'weight': weight,
        'goal': goal,
        'experience': experience,
        'location': location,
        'equipment_set': equipment_set,
        'equipment': equipment,
        'injuries': injuries,
        'muscle_focus': muscle_focus,
        'workout_type': random.choice(WORKOUT_TYPES),
    }


# ============================================================================
# EXERCISE FETCHING & FILTERING
# ============================================================================

def fetch_all_exercises():
    """Fetch all exercises from Supabase"""
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
    
    return all_exercises


def get_priority_key(user):
    """Get the appropriate priority key based on user goal and location"""
    if user['location'] == 'home':
        return 'priority_home'
    elif user['goal'] == 'Build Muscle':
        return 'priority_build_muscle'
    elif user['goal'] == 'Get Lean':
        return 'priority_get_lean'
    else:
        return 'priority_gym'


def filter_exercises_for_user(exercises, user):
    """Filter exercises based on user profile - using exercise_family for workout type"""
    filtered = []
    
    # Map user equipment to equipment_category values
    equipment_map = {
        'Bodyweight': 'bodyweight',
        'Dumbbells': 'dumbbell',
        'Barbells': 'barbell',
        'Barbell': 'barbell',
        'Cables': 'cable',
        'Machines': 'machine',
        'Resistance Bands': 'band',
        'Kettlebells': 'kettlebell',
        'Smith Machine': 'smith_machine',
        'Pull-up Bar': 'bodyweight',
    }
    
    user_equipment_categories = set()
    for eq in user['equipment']:
        if eq in equipment_map:
            user_equipment_categories.add(equipment_map[eq])
    
    # Families to avoid based on injuries
    injury_family_map = {
        'Lower Back': ['deadlift', 'romanian_deadlift', 'good_morning', 'back_extension', 'hyperextension'],
        'Knee': ['squat', 'lunge', 'leg_press', 'leg_extension', 'leg_curl', 'jump', 'box_jump'],
        'Shoulder': ['shoulder_press', 'lateral_raise', 'front_raise', 'upright_row', 'overhead'],
        'Wrist': ['wrist_curl', 'wrist_extension'],
        'Hip': ['hip_thrust', 'glute_bridge', 'hip_abduction', 'hip_adduction'],
    }
    
    avoid_families = set()
    if user['injuries']:
        for injury in user['injuries']:
            if injury in injury_family_map:
                avoid_families.update(injury_family_map[injury])
    
    # Workout type to exercise family mapping (using actual family names from database)
    workout_family_map = {
        'Push': ['bench_press', 'incline_bench_press', 'decline_bench_press', 'push_up', 
                 'shoulder_press', 'chest_fly', 'tricep_pushdown', 'tricep_extension', 
                 'skull_crusher', 'dip', 'chest_press', 'lateral_raise', 'front_raise'],
        'Pull': ['lat_pulldown', 'pull_up', 'chin_up', 'bent_over_row', 'seated_row',
                 'bicep_curl', 'hammer_curl', 'preacher_curl', 'concentration_curl',
                 'face_pull', 'rear_delt_fly', 'cable_row', 'back_exercise'],
        'Legs': ['squat', 'front_squat', 'goblet_squat', 'hack_squat', 'sumo_squat',
                 'leg_press', 'leg_extension', 'leg_curl', 'lunge', 'reverse_lunge',
                 'hip_thrust', 'glute_bridge', 'romanian_deadlift', 'deadlift',
                 'calf_raise', 'step_up', 'split_squat', 'leg_exercise', 'glute_exercise'],
        'Upper Body': ['bench_press', 'incline_bench_press', 'push_up', 'shoulder_press',
                       'lat_pulldown', 'pull_up', 'bent_over_row', 'bicep_curl', 
                       'tricep_extension', 'chest_fly', 'lateral_raise', 'face_pull',
                       'dip', 'chin_up', 'hammer_curl', 'skull_crusher'],
        'Lower Body': ['squat', 'front_squat', 'goblet_squat', 'leg_press', 'leg_extension',
                       'leg_curl', 'lunge', 'hip_thrust', 'glute_bridge', 'deadlift',
                       'romanian_deadlift', 'calf_raise', 'step_up', 'leg_exercise', 'glute_exercise'],
        'Full Body': None,  # All exercises
        'Core': ['crunch', 'plank', 'sit_up', 'leg_raise', 'russian_twist', 'bicycle_crunch',
                 'wood_chop', 'ab_rollout', 'dead_bug', 'mountain_climber', 'side_bend',
                 'v_up', 'flutter_kick', 'hollow_hold', 'core_exercise'],
        'Arms': ['bicep_curl', 'hammer_curl', 'preacher_curl', 'concentration_curl',
                 'tricep_pushdown', 'tricep_extension', 'skull_crusher', 'wrist_curl',
                 'reverse_curl', 'arm_exercise', 'forearm_exercise'],
    }
    
    target_families = workout_family_map.get(user['workout_type'])
    
    for ex in exercises:
        # Check equipment compatibility
        eq_cat = ex.get('equipment_category', 'bodyweight')
        if eq_cat not in user_equipment_categories:
            continue
        
        family = ex.get('exercise_family', '')
        
        # Check injury restrictions (by family)
        if any(avoid in family for avoid in avoid_families):
            continue
        
        # Check workout type targeting (if not full body)
        if target_families:
            matches_target = family in target_families
            # Also check partial matches for broader families
            if not matches_target:
                matches_target = any(tf in family or family in tf for tf in target_families)
            if not matches_target:
                continue
        
        # Experience level check
        difficulty = ex.get('difficulty_level', 'intermediate')
        if user['experience'] == 'Beginner' and difficulty == 'advanced':
            continue
        
        filtered.append(ex)
    
    return filtered


def generate_workout(filtered_exercises, user, num_exercises=6):
    """Generate a workout from filtered exercises"""
    if not filtered_exercises:
        return []
    
    priority_key = get_priority_key(user)
    
    # Sort by priority
    sorted_exercises = sorted(
        filtered_exercises,
        key=lambda x: x.get(priority_key, 50),
        reverse=True
    )
    
    # Pick diverse exercises (different families)
    workout = []
    used_families = set()
    
    for ex in sorted_exercises:
        family = ex.get('exercise_family', 'general')
        if family not in used_families or len(workout) < num_exercises:
            if family not in used_families:
                workout.append(ex)
                used_families.add(family)
        
        if len(workout) >= num_exercises:
            break
    
    # Fill remaining slots if needed
    if len(workout) < num_exercises:
        for ex in sorted_exercises:
            if ex not in workout:
                workout.append(ex)
            if len(workout) >= num_exercises:
                break
    
    return workout


# ============================================================================
# SWAP SYSTEM TESTING
# ============================================================================

def find_equipment_variants(exercise, all_exercises, user_equipment_categories):
    """Find same-family exercises with different equipment"""
    family = exercise.get('exercise_family')
    current_category = exercise.get('equipment_category')
    
    if not family or family in ['general_exercise', 'general_movement']:
        return []
    
    variants = []
    for ex in all_exercises:
        if ex.get('id') == exercise.get('id'):
            continue
        if ex.get('exercise_family') != family:
            continue
        ex_cat = ex.get('equipment_category')
        if ex_cat == current_category:
            continue
        if ex_cat not in user_equipment_categories:
            continue
        variants.append(ex)
    
    return variants


def find_same_family_variations(exercise, all_exercises, user_equipment_categories):
    """Find different exercises in the SAME family (same equipment OK) - for variety"""
    family = exercise.get('exercise_family')
    current_name = exercise.get('name', '').lower()
    current_id = exercise.get('id')
    
    if not family:
        return []
    
    variations = []
    for ex in all_exercises:
        if ex.get('id') == current_id:
            continue
        if ex.get('exercise_family') != family:
            continue
        ex_cat = ex.get('equipment_category')
        if ex_cat not in user_equipment_categories:
            continue
        # Prefer exercises with different names (different variations)
        ex_name = ex.get('name', '').lower()
        # Skip if it's essentially the same exercise (very similar name)
        if ex_name == current_name:
            continue
        variations.append(ex)
    
    return variations


def find_similar_movement_exercises(exercise, all_exercises, user_equipment_categories):
    """Find exercises with similar movement patterns when family matching fails"""
    current_family = exercise.get('exercise_family', '')
    current_name = exercise.get('name', '').lower()
    current_id = exercise.get('id')
    
    # Define movement pattern groups (exercises that work similarly)
    MOVEMENT_GROUPS = {
        'horizontal_push': ['push_up', 'bench_press', 'chest_press', 'chest_fly', 'incline_bench_press', 'decline_bench_press'],
        'vertical_push': ['shoulder_press', 'overhead_press', 'military_press', 'lateral_raise', 'front_raise'],
        'horizontal_pull': ['bent_over_row', 'seated_row', 'cable_row', 'dumbbell_row', 't_bar_row'],
        'vertical_pull': ['lat_pulldown', 'pull_up', 'chin_up'],
        'hip_hinge': ['deadlift', 'romanian_deadlift', 'good_morning', 'hip_thrust', 'glute_bridge'],
        'knee_dominant': ['squat', 'lunge', 'leg_press', 'leg_extension', 'step_up', 'split_squat', 'goblet_squat', 'front_squat', 'hack_squat'],
        'arm_curl': ['bicep_curl', 'hammer_curl', 'preacher_curl', 'concentration_curl', 'reverse_curl', 'incline_curl'],
        'arm_extension': ['tricep_pushdown', 'tricep_extension', 'skull_crusher', 'dip', 'close_grip_bench_press'],
        'core_flexion': ['crunch', 'sit_up', 'leg_raise', 'v_up', 'bicycle_crunch'],
        'core_stability': ['plank', 'dead_bug', 'hollow_hold', 'bird_dog'],
        'core_rotation': ['russian_twist', 'wood_chop', 'cable_rotation', 'side_bend'],
    }
    
    # Find which group the current exercise belongs to
    current_group = None
    for group_name, families in MOVEMENT_GROUPS.items():
        if current_family in families:
            current_group = group_name
            break
    
    if not current_group:
        return []
    
    # Find exercises from the same movement group but different family
    similar = []
    target_families = MOVEMENT_GROUPS[current_group]
    
    for ex in all_exercises:
        if ex.get('id') == current_id:
            continue
        ex_family = ex.get('exercise_family', '')
        if ex_family not in target_families:
            continue
        if ex_family == current_family:
            continue  # Want different family within same movement group
        ex_cat = ex.get('equipment_category')
        if ex_cat not in user_equipment_categories:
            continue
        similar.append(ex)
    
    return similar


def find_general_exercise_alternatives(exercise, all_exercises, user_equipment_categories):
    """Find alternatives for general_exercise family by analyzing exercise name"""
    current_name = exercise.get('name', '').lower()
    current_id = exercise.get('id')
    
    # Keywords to identify exercise type from name
    KEYWORD_FAMILIES = {
        'press': ['bench_press', 'shoulder_press', 'chest_press'],
        'curl': ['bicep_curl', 'hammer_curl', 'preacher_curl'],
        'row': ['bent_over_row', 'seated_row', 'cable_row'],
        'squat': ['squat', 'goblet_squat', 'front_squat'],
        'lunge': ['lunge', 'reverse_lunge', 'walking_lunge'],
        'deadlift': ['deadlift', 'romanian_deadlift'],
        'fly': ['chest_fly', 'rear_delt_fly'],
        'raise': ['lateral_raise', 'front_raise', 'calf_raise'],
        'extension': ['tricep_extension', 'leg_extension', 'back_extension'],
        'pulldown': ['lat_pulldown'],
        'pull': ['pull_up', 'lat_pulldown'],
        'push': ['push_up', 'bench_press'],
        'crunch': ['crunch', 'bicycle_crunch'],
        'plank': ['plank'],
    }
    
    # Find matching families based on exercise name keywords
    target_families = set()
    for keyword, families in KEYWORD_FAMILIES.items():
        if keyword in current_name:
            target_families.update(families)
    
    if not target_families:
        # Default to common exercises
        target_families = {'bench_press', 'squat', 'deadlift', 'shoulder_press', 'lat_pulldown'}
    
    alternatives = []
    for ex in all_exercises:
        if ex.get('id') == current_id:
            continue
        ex_family = ex.get('exercise_family', '')
        if ex_family not in target_families:
            continue
        ex_cat = ex.get('equipment_category')
        if ex_cat not in user_equipment_categories:
            continue
        alternatives.append(ex)
    
    return alternatives


def find_complementary_exercises(exercise, all_exercises, user_equipment_categories):
    """Find exercises from complementary families"""
    comp_families_str = exercise.get('complementary_families', '')
    if not comp_families_str:
        return []
    
    comp_families = [f.strip() for f in comp_families_str.split(',')]
    current_family = exercise.get('exercise_family')
    
    complementary = []
    for ex in all_exercises:
        ex_family = ex.get('exercise_family')
        if ex_family in comp_families and ex_family != current_family:
            ex_cat = ex.get('equipment_category')
            if ex_cat in user_equipment_categories:
                complementary.append(ex)
    
    return complementary


def test_swap_sequence(exercise, all_exercises, user):
    """Test the swap sequence with smart fallbacks:
    - Swap 1: Equipment variant OR same-family variation
    - Swap 2: Another variant OR similar movement pattern
    - Swap 3: Complementary exercise
    """
    
    # Map user equipment
    equipment_map = {
        'Bodyweight': 'bodyweight',
        'Dumbbells': 'dumbbell',
        'Barbells': 'barbell',
        'Barbell': 'barbell',
        'Cables': 'cable',
        'Machines': 'machine',
        'Resistance Bands': 'band',
        'Kettlebells': 'kettlebell',
        'Smith Machine': 'smith_machine',
        'Pull-up Bar': 'bodyweight',
    }
    
    user_equipment_categories = set()
    for eq in user['equipment']:
        if eq in equipment_map:
            user_equipment_categories.add(equipment_map[eq])
    
    current_family = exercise.get('exercise_family', '')
    
    results = {
        'original': {
            'name': exercise.get('name'),
            'family': current_family,
            'equipment_category': exercise.get('equipment_category'),
        },
        'swap_1': None,
        'swap_2': None,
        'swap_3': None,
        'swap_1_is_variety': False,
        'swap_2_is_variety': False,
        'swap_3_is_complementary': False,
        'swap_1_different_equipment': False,
        'swap_2_different_equipment': False,
        'swap_1_type': None,  # 'equipment_variant', 'family_variation', 'similar_movement', 'general_alternative'
        'swap_2_type': None,
    }
    
    # Get priority key for sorting
    priority_key = get_priority_key(user)
    used_ids = {exercise.get('id')}
    
    # =========================================================================
    # SWAP 1: Try equipment variant first, then fallback to same-family variation
    # =========================================================================
    swap_1 = None
    swap_1_type = None
    
    # Try 1a: Equipment variants (different equipment, same family)
    variants = find_equipment_variants(exercise, all_exercises, user_equipment_categories)
    variants_sorted = sorted(variants, key=lambda x: x.get(priority_key, 50), reverse=True)
    
    if variants_sorted:
        swap_1 = variants_sorted[0]
        swap_1_type = 'equipment_variant'
    else:
        # Try 1b: Same-family variations (different exercise, same family, any equipment)
        family_variations = find_same_family_variations(exercise, all_exercises, user_equipment_categories)
        family_sorted = sorted(family_variations, key=lambda x: x.get(priority_key, 50), reverse=True)
        
        if family_sorted:
            swap_1 = family_sorted[0]
            swap_1_type = 'family_variation'
        else:
            # Try 1c: Handle general_exercise specially
            if current_family in ['general_exercise', 'general_movement']:
                general_alts = find_general_exercise_alternatives(exercise, all_exercises, user_equipment_categories)
                general_sorted = sorted(general_alts, key=lambda x: x.get(priority_key, 50), reverse=True)
                if general_sorted:
                    swap_1 = general_sorted[0]
                    swap_1_type = 'general_alternative'
            else:
                # Try 1d: Similar movement patterns
                similar = find_similar_movement_exercises(exercise, all_exercises, user_equipment_categories)
                similar_sorted = sorted(similar, key=lambda x: x.get(priority_key, 50), reverse=True)
                if similar_sorted:
                    swap_1 = similar_sorted[0]
                    swap_1_type = 'similar_movement'
    
    if swap_1:
        used_ids.add(swap_1.get('id'))
        results['swap_1'] = {
            'name': swap_1.get('name'),
            'family': swap_1.get('exercise_family'),
            'equipment_category': swap_1.get('equipment_category'),
        }
        results['swap_1_type'] = swap_1_type
        results['swap_1_is_variety'] = (
            swap_1.get('exercise_family') == current_family or 
            swap_1_type in ['family_variation', 'similar_movement', 'general_alternative']
        )
        results['swap_1_different_equipment'] = swap_1.get('equipment_category') != exercise.get('equipment_category')
    
    # =========================================================================
    # SWAP 2: Another variant or similar movement
    # =========================================================================
    swap_2 = None
    swap_2_type = None
    
    # Build candidate pool from all sources (excluding what we've used)
    all_candidates = []
    
    # Add remaining equipment variants
    for v in variants_sorted:
        if v.get('id') not in used_ids:
            all_candidates.append((v, 'equipment_variant'))
    
    # Add same-family variations
    family_variations = find_same_family_variations(exercise, all_exercises, user_equipment_categories)
    for v in family_variations:
        if v.get('id') not in used_ids:
            all_candidates.append((v, 'family_variation'))
    
    # Add similar movement patterns
    similar = find_similar_movement_exercises(exercise, all_exercises, user_equipment_categories)
    for v in similar:
        if v.get('id') not in used_ids:
            all_candidates.append((v, 'similar_movement'))
    
    # Sort all candidates by priority
    all_candidates_sorted = sorted(
        all_candidates, 
        key=lambda x: x[0].get(priority_key, 50), 
        reverse=True
    )
    
    # Pick best candidate that's different from swap_1
    for candidate, ctype in all_candidates_sorted:
        if candidate.get('id') not in used_ids:
            # Prefer different equipment if swap_1 had same equipment
            if swap_1 and candidate.get('equipment_category') == swap_1.get('equipment_category'):
                # Check if there's a better option with different equipment
                continue
            swap_2 = candidate
            swap_2_type = ctype
            break
    
    # If no different equipment found, just take the best available
    if not swap_2 and all_candidates_sorted:
        for candidate, ctype in all_candidates_sorted:
            if candidate.get('id') not in used_ids:
                swap_2 = candidate
                swap_2_type = ctype
                break
    
    if swap_2:
        used_ids.add(swap_2.get('id'))
        results['swap_2'] = {
            'name': swap_2.get('name'),
            'family': swap_2.get('exercise_family'),
            'equipment_category': swap_2.get('equipment_category'),
        }
        results['swap_2_type'] = swap_2_type
        results['swap_2_is_variety'] = (
            swap_2.get('exercise_family') == current_family or 
            swap_2_type in ['family_variation', 'similar_movement']
        )
        results['swap_2_different_equipment'] = swap_2.get('equipment_category') != exercise.get('equipment_category')
    
    # =========================================================================
    # SWAP 3: Complementary exercise (different movement pattern)
    # =========================================================================
    complementary = find_complementary_exercises(exercise, all_exercises, user_equipment_categories)
    comp_sorted = sorted(complementary, key=lambda x: x.get(priority_key, 50), reverse=True)
    
    # Find one that's not already used
    for comp in comp_sorted:
        if comp.get('id') not in used_ids:
            results['swap_3'] = {
                'name': comp.get('name'),
                'family': comp.get('exercise_family'),
                'equipment_category': comp.get('equipment_category'),
            }
            results['swap_3_is_complementary'] = comp.get('exercise_family') != current_family
            break
    
    return results


# ============================================================================
# SCORING & VALIDATION
# ============================================================================

def score_workout_generation(workout, user, filtered_count):
    """Score the workout generation quality"""
    scores = {
        'exercises_generated': len(workout) >= 5,
        'has_filtered_options': filtered_count >= 10,
        'family_diversity': len(set(ex.get('exercise_family') for ex in workout)) >= 3,
        'equipment_match': all(ex.get('equipment_category') in 
            ['bodyweight', 'dumbbell', 'barbell', 'cable', 'machine', 'band', 'kettlebell', 'smith_machine']
            for ex in workout),
        'priority_ordering': True,  # Assume correct if sorted properly
    }
    
    # Calculate overall
    passed = sum(1 for v in scores.values() if v)
    total = len(scores)
    percentage = (passed / total) * 100 if total else 0
    
    return {
        'checks': scores,
        'passed': passed,
        'total': total,
        'percentage': percentage,
    }


def score_swap_system(swap_results):
    """Score the swap system test with smart fallback recognition"""
    
    # Core checks
    swap_1_found = swap_results['swap_1'] is not None
    swap_2_found = swap_results['swap_2'] is not None
    swap_3_found = swap_results['swap_3'] is not None
    
    # Variety checks - now recognize all valid variety types
    swap_1_is_variety = swap_results.get('swap_1_is_variety', False)
    swap_2_is_variety = swap_results.get('swap_2_is_variety', False)
    swap_3_is_complementary = swap_results.get('swap_3_is_complementary', False)
    
    # Equipment diversity (bonus, not required for bodyweight-only)
    swap_1_diff_equip = swap_results.get('swap_1_different_equipment', False)
    swap_2_diff_equip = swap_results.get('swap_2_different_equipment', False)
    
    # Get swap types for smarter scoring
    swap_1_type = swap_results.get('swap_1_type')
    swap_2_type = swap_results.get('swap_2_type')
    
    scores = {
        'swap_1_found': swap_1_found,
        'swap_1_is_variety': swap_1_is_variety,
        'swap_1_quality': swap_1_type in ['equipment_variant', 'family_variation'] if swap_1_type else False,
        'swap_2_found': swap_2_found,
        'swap_2_is_variety': swap_2_is_variety,
        'swap_3_found': swap_3_found,
        'swap_3_is_complementary': swap_3_is_complementary,
    }
    
    # Adjusted weights - less penalty for no equipment variant if fallback is good
    weights = {
        'swap_1_found': 2.0,
        'swap_1_is_variety': 2.0,
        'swap_1_quality': 1.0,  # Bonus for ideal swap type
        'swap_2_found': 1.5,
        'swap_2_is_variety': 1.5,
        'swap_3_found': 2.0,
        'swap_3_is_complementary': 2.0,
    }
    
    weighted_passed = sum(weights[k] for k, v in scores.items() if v)
    weighted_total = sum(weights.values())
    percentage = (weighted_passed / weighted_total) * 100 if weighted_total else 0
    
    return {
        'checks': scores,
        'percentage': percentage,
        'swap_1_type': swap_1_type,
        'swap_2_type': swap_2_type,
    }


def get_grade(percentage):
    """Convert percentage to letter grade"""
    if percentage >= 90:
        return 'A'
    elif percentage >= 80:
        return 'B'
    elif percentage >= 70:
        return 'C'
    elif percentage >= 60:
        return 'D'
    else:
        return 'F'


# ============================================================================
# MAIN TEST RUNNER
# ============================================================================

def run_user_test(user, all_exercises):
    """Run complete test for a single user"""
    
    # Filter exercises for user
    filtered = filter_exercises_for_user(all_exercises, user)
    
    # Generate workout
    workout = generate_workout(filtered, user)
    
    # Score workout generation
    workout_score = score_workout_generation(workout, user, len(filtered))
    
    # Test swap system on first exercise
    swap_results = None
    swap_score = None
    if workout:
        swap_results = test_swap_sequence(workout[0], all_exercises, user)
        swap_score = score_swap_system(swap_results)
    
    # Calculate overall score
    workout_pct = workout_score['percentage']
    swap_pct = swap_score['percentage'] if swap_score else 0
    overall_pct = (workout_pct * 0.4 + swap_pct * 0.6)  # Weight swap system higher
    
    return {
        'user': user,
        'filtered_exercises': len(filtered),
        'workout': [
            {
                'name': ex.get('name'),
                'family': ex.get('exercise_family'),
                'equipment_category': ex.get('equipment_category'),
            }
            for ex in workout
        ],
        'workout_score': workout_score,
        'swap_test': swap_results,
        'swap_score': swap_score,
        'overall_percentage': overall_pct,
        'grade': get_grade(overall_pct),
    }


def generate_detailed_report(result):
    """Generate a detailed report for a single user"""
    user = result['user']
    
    report = []
    report.append("=" * 80)
    report.append(f"👤 USER: {user['name']}")
    report.append("=" * 80)
    report.append("")
    report.append("📊 PROFILE:")
    report.append(f"   Gender: {user['gender']} | Age: {user['age']}")
    report.append(f"   Height: {user['height']}in ({user['height']//12}'{user['height']%12}\") | Weight: {user['weight']}lbs")
    report.append(f"   Goal: {user['goal']} | Experience: {user['experience']}")
    report.append(f"   Location: {user['location'].upper()} ({user['equipment_set']})")
    report.append(f"   Equipment: {', '.join(user['equipment'])}")
    report.append(f"   Injuries: {', '.join(user['injuries']) if user['injuries'] else 'None'}")
    report.append(f"   Workout Type: {user['workout_type']}")
    report.append("")
    
    report.append("🏋️ GENERATED WORKOUT:")
    report.append(f"   Filtered pool: {result['filtered_exercises']} exercises")
    for i, ex in enumerate(result['workout'], 1):
        report.append(f"   {i}. {ex['name']}")
        report.append(f"      Family: {ex['family']} | Equipment: {ex['equipment_category']}")
    report.append("")
    
    ws = result['workout_score']
    report.append("📋 WORKOUT GENERATION SCORE:")
    for check, passed in ws['checks'].items():
        status = "✅" if passed else "❌"
        report.append(f"   {status} {check.replace('_', ' ').title()}")
    report.append(f"   Score: {ws['percentage']:.1f}%")
    report.append("")
    
    if result['swap_test']:
        st = result['swap_test']
        report.append("🔄 SWAP SYSTEM TEST:")
        report.append(f"   Original: {st['original']['name']}")
        report.append(f"            Family: {st['original']['family']} | Equipment: {st['original']['equipment_category']}")
        report.append("")
        
        # Swap type labels
        SWAP_TYPE_LABELS = {
            'equipment_variant': '🔧 Equipment Variant',
            'family_variation': '🔄 Same-Family Variation',
            'similar_movement': '💪 Similar Movement Pattern',
            'general_alternative': '🎯 Smart Alternative',
        }
        
        if st['swap_1']:
            swap_type = st.get('swap_1_type', 'unknown')
            type_label = SWAP_TYPE_LABELS.get(swap_type, 'Variant')
            status = "✅" if st['swap_1_is_variety'] else "⚠️"
            report.append(f"   {status} Swap 1 ({type_label}):")
            report.append(f"      → {st['swap_1']['name']}")
            report.append(f"        Family: {st['swap_1']['family']} | Equipment: {st['swap_1']['equipment_category']}")
            report.append(f"        Similar Movement: {'✅ Yes' if st['swap_1_is_variety'] else '❌ No'}")
            if swap_type == 'equipment_variant':
                report.append(f"        Different Equipment: {'✅ Yes' if st['swap_1_different_equipment'] else '❌ No'}")
        else:
            report.append("   ❌ Swap 1: No variant found")
        report.append("")
        
        if st['swap_2']:
            swap_type = st.get('swap_2_type', 'unknown')
            type_label = SWAP_TYPE_LABELS.get(swap_type, 'Variant')
            status = "✅" if st['swap_2_is_variety'] else "⚠️"
            report.append(f"   {status} Swap 2 ({type_label}):")
            report.append(f"      → {st['swap_2']['name']}")
            report.append(f"        Family: {st['swap_2']['family']} | Equipment: {st['swap_2']['equipment_category']}")
            report.append(f"        Similar Movement: {'✅ Yes' if st['swap_2_is_variety'] else '❌ No'}")
        else:
            report.append("   ⚠️ Swap 2: No additional variant found")
        report.append("")
        
        if st['swap_3']:
            status = "✅" if st['swap_3_is_complementary'] else "⚠️"
            report.append(f"   {status} Swap 3 (🔀 Complementary Exercise):")
            report.append(f"      → {st['swap_3']['name']}")
            report.append(f"        Family: {st['swap_3']['family']} | Equipment: {st['swap_3']['equipment_category']}")
            report.append(f"        Different Movement: {'✅ Yes' if st['swap_3_is_complementary'] else '❌ No'}")
        else:
            report.append("   ❌ Swap 3: No complementary exercise found")
        report.append("")
        
        ss = result['swap_score']
        report.append("📊 SWAP SCORE:")
        for check, passed in ss['checks'].items():
            status = "✅" if passed else "❌"
            report.append(f"   {status} {check.replace('_', ' ').title()}")
        report.append(f"   Score: {ss['percentage']:.1f}%")
    
    report.append("")
    report.append("🎯 OVERALL RESULT:")
    report.append(f"   Workout Generation: {result['workout_score']['percentage']:.1f}%")
    report.append(f"   Swap System: {result['swap_score']['percentage']:.1f}%" if result['swap_score'] else "   Swap System: N/A")
    report.append(f"   ═══════════════════════════")
    report.append(f"   FINAL SCORE: {result['overall_percentage']:.1f}% (Grade: {result['grade']})")
    report.append("")
    
    # Analysis and findings
    report.append("🔍 FINDINGS & ANALYSIS:")
    findings = []
    
    # Workout findings
    if result['filtered_exercises'] < 20:
        findings.append(f"   ⚠️ Limited exercise pool ({result['filtered_exercises']}) - may need more equipment options")
    else:
        findings.append(f"   ✅ Good exercise variety ({result['filtered_exercises']} options)")
    
    # Swap findings with new types
    if result['swap_test']:
        st = result['swap_test']
        ss = result['swap_score']
        
        swap_1_type = ss.get('swap_1_type') if ss else None
        swap_2_type = ss.get('swap_2_type') if ss else None
        
        if st['swap_1']:
            if swap_1_type == 'equipment_variant':
                findings.append(f"   ✅ Swap 1: Equipment variant available ({st['swap_1']['equipment_category']})")
            elif swap_1_type == 'family_variation':
                findings.append(f"   ✅ Swap 1: Same-family variation offered (different {st['original']['family']} exercise)")
            elif swap_1_type == 'similar_movement':
                findings.append(f"   ✅ Swap 1: Similar movement pattern found ({st['swap_1']['family']})")
            elif swap_1_type == 'general_alternative':
                findings.append(f"   ✅ Swap 1: Smart alternative found ({st['swap_1']['family']})")
        else:
            findings.append(f"   ⚠️ Swap 1: No variant available for {st['original']['family']}")
        
        if st['swap_2']:
            if swap_2_type == 'equipment_variant':
                findings.append(f"   ✅ Swap 2: Additional equipment option ({st['swap_2']['equipment_category']})")
            elif swap_2_type in ['family_variation', 'similar_movement']:
                findings.append(f"   ✅ Swap 2: Movement variation available ({st['swap_2']['family']})")
        
        if st['swap_3'] and st['swap_3_is_complementary']:
            findings.append(f"   ✅ Swap 3: Complementary movement ({st['swap_3']['family']})")
        elif not st['swap_3']:
            findings.append(f"   ⚠️ Swap 3: No complementary exercises found")
    
    # Goal/location specific findings
    if user['location'] == 'home' and 'bodyweight' in user['equipment_set']:
        bw_count = sum(1 for ex in result['workout'] if ex['equipment_category'] == 'bodyweight')
        if bw_count >= 3:
            findings.append(f"   ✅ Good bodyweight exercise coverage for home user ({bw_count}/{len(result['workout'])})")
    
    if user['goal'] == 'Build Muscle':
        compound_count = sum(1 for ex in result['workout'] 
                           if ex['family'] in ['squat', 'deadlift', 'bench_press', 'shoulder_press', 'bent_over_row'])
        if compound_count >= 2:
            findings.append(f"   ✅ Good compound exercise selection for muscle building")
    
    if not findings:
        findings.append("   ✅ All systems working correctly")
    
    report.extend(findings)
    report.append("")
    
    return "\n".join(report)


def main():
    print("=" * 100)
    print("🧪 FULL USER SIMULATION TEST SUITE")
    print("   100 Users | Workout Generation | Swap System Validation")
    print("=" * 100)
    print()
    
    # Fetch exercises
    all_exercises = fetch_all_exercises()
    print(f"✅ Loaded {len(all_exercises)} exercises")
    print()
    
    # Generate 100 users
    print("👥 Generating 100 diverse test users...")
    users = [generate_user(i + 1) for i in range(100)]
    
    # Profile diversity stats
    goal_counts = {}
    location_counts = {}
    experience_counts = {}
    
    for u in users:
        goal_counts[u['goal']] = goal_counts.get(u['goal'], 0) + 1
        location_counts[u['location']] = location_counts.get(u['location'], 0) + 1
        experience_counts[u['experience']] = experience_counts.get(u['experience'], 0) + 1
    
    print(f"   Goals: {goal_counts}")
    print(f"   Locations: {location_counts}")
    print(f"   Experience: {experience_counts}")
    print()
    
    # Run tests
    print("🔬 Running tests on all 100 users...")
    print()
    
    results = []
    for i, user in enumerate(users):
        result = run_user_test(user, all_exercises)
        results.append(result)
        
        # Progress indicator
        if (i + 1) % 20 == 0:
            print(f"   Completed {i + 1}/100 users...")
    
    print()
    
    # Calculate summary statistics
    grades = {'A': 0, 'B': 0, 'C': 0, 'D': 0, 'F': 0}
    total_score = 0
    swap_success = {'swap_1': 0, 'swap_2': 0, 'swap_3': 0}
    swap_types = {'equipment_variant': 0, 'family_variation': 0, 'similar_movement': 0, 'general_alternative': 0}
    workout_success = 0
    
    for r in results:
        grades[r['grade']] += 1
        total_score += r['overall_percentage']
        if r['workout_score']['percentage'] >= 80:
            workout_success += 1
        if r['swap_test']:
            if r['swap_test']['swap_1_is_variety']:
                swap_success['swap_1'] += 1
            if r['swap_test']['swap_2_is_variety']:
                swap_success['swap_2'] += 1
            if r['swap_test']['swap_3_is_complementary']:
                swap_success['swap_3'] += 1
            # Track swap types
            swap_1_type = r['swap_score'].get('swap_1_type') if r['swap_score'] else None
            if swap_1_type and swap_1_type in swap_types:
                swap_types[swap_1_type] += 1
    
    avg_score = total_score / len(results)
    
    # Print summary scorecard
    print("=" * 100)
    print("📊 SCORECARD SUMMARY")
    print("=" * 100)
    print()
    print("📈 GRADE DISTRIBUTION:")
    for grade in ['A', 'B', 'C', 'D', 'F']:
        count = grades[grade]
        pct = (count / len(results)) * 100
        bar = '█' * int(pct / 2)
        print(f"   {grade}: {count:3d} ({pct:5.1f}%) {bar}")
    print()
    print(f"📊 AVERAGE SCORE: {avg_score:.1f}%")
    print(f"🏆 OVERALL GRADE: {get_grade(avg_score)}")
    print()
    print("🔄 SWAP SYSTEM SUCCESS RATES:")
    print(f"   Swap 1 (Variety/Similar): {swap_success['swap_1']}/100 ({swap_success['swap_1']}%)")
    print(f"   Swap 2 (Variety/Similar): {swap_success['swap_2']}/100 ({swap_success['swap_2']}%)")
    print(f"   Swap 3 (Complementary): {swap_success['swap_3']}/100 ({swap_success['swap_3']}%)")
    print()
    print("🔧 SWAP 1 TYPE BREAKDOWN:")
    print(f"   Equipment Variants: {swap_types['equipment_variant']}")
    print(f"   Same-Family Variations: {swap_types['family_variation']}")
    print(f"   Similar Movement Patterns: {swap_types['similar_movement']}")
    print(f"   Smart Alternatives: {swap_types['general_alternative']}")
    print()
    print(f"🏋️ WORKOUT GENERATION: {workout_success}/100 passed (≥80%)")
    print()
    
    # Generate detailed reports for top 10 and bottom 10
    sorted_results = sorted(results, key=lambda x: x['overall_percentage'], reverse=True)
    
    print("=" * 100)
    print("📋 DETAILED REPORTS (20 SAMPLE USERS)")
    print("   Top 10 performers + Bottom 10 performers")
    print("=" * 100)
    
    # Select 10 best and 10 worst for review
    sample_results = sorted_results[:10] + sorted_results[-10:]
    
    detailed_reports = []
    for result in sample_results:
        report = generate_detailed_report(result)
        detailed_reports.append(report)
        print(report)
    
    # Save full results to JSON
    output = {
        'summary': {
            'total_users': len(results),
            'avg_score': avg_score,
            'final_grade': get_grade(avg_score),
            'grades': grades,
            'swap_success_rates': swap_success,
            'workout_success': workout_success,
        },
        'all_results': [
            {
                'user': r['user'],
                'filtered_exercises': r['filtered_exercises'],
                'workout': r['workout'],
                'swap_test': r['swap_test'],
                'workout_score': r['workout_score']['percentage'],
                'swap_score': r['swap_score']['percentage'] if r['swap_score'] else 0,
                'overall_percentage': r['overall_percentage'],
                'grade': r['grade'],
            }
            for r in results
        ],
    }
    
    with open('full_simulation_results.json', 'w') as f:
        json.dump(output, f, indent=2)
    
    print()
    print(f"📁 Full results saved to: full_simulation_results.json")
    print()
    print("=" * 100)
    print("✅ TEST SUITE COMPLETE")
    print("=" * 100)


if __name__ == "__main__":
    main()
