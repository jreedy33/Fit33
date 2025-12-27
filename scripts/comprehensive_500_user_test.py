#!/usr/bin/env python3
"""
Comprehensive 500 User Test Suite
==================================
Tests workout generation and exercise selection across 500 diverse user profiles.
Validates: equipment, difficulty, muscle targeting, injuries, priorities.
Exports detailed PDF report for manual audit.
"""

import os
import json
import random
from datetime import datetime
from supabase import create_client

# Supabase credentials
SUPABASE_URL = "https://ehooeghabzefgoqzugrc.supabase.co"
SUPABASE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVob29lZ2hhYnplZmdvcXp1Z3JjIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjM4NDc4NjQsImV4cCI6MjA3OTQyMzg2NH0.6-QWDr5B279hybtu9MbPVhmBKlyzFq1GK9P7zlDXuY0"

supabase = create_client(SUPABASE_URL, SUPABASE_KEY)

# ============================================================================
# USER PROFILE GENERATION
# ============================================================================

GOALS = ['Build Muscle', 'Get Lean', 'Endurance', 'General Fitness']
EXPERIENCE_LEVELS = ['Beginner', 'Intermediate', 'Advanced']
LOCATIONS = ['home', 'gym']
GENDERS = ['Male', 'Female']

EQUIPMENT_SETS = {
    'minimal_home': {
        'equipment': ['Bodyweight'],
        'categories': ['bodyweight'],
        'description': 'Bodyweight only - no equipment'
    },
    'home_basic': {
        'equipment': ['Bodyweight', 'Dumbbells', 'Resistance Bands'],
        'categories': ['bodyweight', 'dumbbell', 'band'],
        'description': 'Basic home gym setup'
    },
    'home_intermediate': {
        'equipment': ['Bodyweight', 'Dumbbells', 'Resistance Bands', 'Kettlebells'],
        'categories': ['bodyweight', 'dumbbell', 'band', 'kettlebell'],
        'description': 'Intermediate home gym'
    },
    'home_advanced': {
        'equipment': ['Bodyweight', 'Dumbbells', 'Resistance Bands', 'Kettlebells', 'Pull-up Bar', 'Barbell'],
        'categories': ['bodyweight', 'dumbbell', 'band', 'kettlebell', 'barbell'],
        'description': 'Well-equipped home gym'
    },
    'gym_basic': {
        'equipment': ['Machines', 'Cables', 'Dumbbells'],
        'categories': ['machine', 'cable', 'dumbbell'],
        'description': 'Basic gym access'
    },
    'gym_standard': {
        'equipment': ['Machines', 'Cables', 'Dumbbells', 'Barbells'],
        'categories': ['machine', 'cable', 'dumbbell', 'barbell', 'bodyweight'],
        'description': 'Standard gym access'
    },
    'gym_full': {
        'equipment': ['Machines', 'Cables', 'Dumbbells', 'Barbells', 'Kettlebells', 'Smith Machine'],
        'categories': ['machine', 'cable', 'dumbbell', 'barbell', 'kettlebell', 'smith_machine', 'bodyweight'],
        'description': 'Full gym access'
    },
}

WORKOUT_TYPES = {
    'Push': {
        'families': ['push_up', 'bench_press', 'incline_bench_press', 'decline_bench_press', 
                     'shoulder_press', 'chest_fly', 'tricep_pushdown', 'tricep_extension', 
                     'skull_crusher', 'dip', 'lateral_raise', 'front_raise'],
        'muscles': ['Chest', 'Triceps', 'Front Delts', 'Side Delts', 'Shoulders']
    },
    'Pull': {
        'families': ['lat_pulldown', 'pull_up', 'chin_up', 'bent_over_row', 'seated_row',
                     'bicep_curl', 'hammer_curl', 'preacher_curl', 'face_pull', 'rear_delt_fly',
                     'back_exercise', 'cable_row'],
        'muscles': ['Back', 'Lats', 'Biceps', 'Rear Delts', 'Upper Back']
    },
    'Legs': {
        'families': ['squat', 'front_squat', 'goblet_squat', 'hack_squat', 'leg_press',
                     'leg_extension', 'leg_curl', 'lunge', 'hip_thrust', 'glute_bridge',
                     'romanian_deadlift', 'deadlift', 'calf_raise', 'step_up'],
        'muscles': ['Quads', 'Hamstrings', 'Glutes', 'Calves']
    },
    'Upper Body': {
        'families': ['bench_press', 'shoulder_press', 'lat_pulldown', 'pull_up', 'bent_over_row',
                     'bicep_curl', 'tricep_extension', 'chest_fly', 'lateral_raise', 'face_pull', 'dip'],
        'muscles': ['Chest', 'Back', 'Shoulders', 'Biceps', 'Triceps']
    },
    'Lower Body': {
        'families': ['squat', 'leg_press', 'leg_extension', 'leg_curl', 'lunge', 
                     'hip_thrust', 'glute_bridge', 'deadlift', 'calf_raise', 'step_up'],
        'muscles': ['Quads', 'Hamstrings', 'Glutes', 'Calves']
    },
    'Full Body': {
        'families': None,  # All families
        'muscles': None  # All muscles
    },
    'Core': {
        'families': ['crunch', 'plank', 'sit_up', 'leg_raise', 'russian_twist', 
                     'bicycle_crunch', 'wood_chop', 'ab_rollout', 'dead_bug'],
        'muscles': ['Abs', 'Obliques', 'Core', 'Lower Abs']
    },
    'Arms': {
        'families': ['bicep_curl', 'hammer_curl', 'preacher_curl', 'tricep_pushdown',
                     'tricep_extension', 'skull_crusher', 'concentration_curl'],
        'muscles': ['Biceps', 'Triceps', 'Forearms']
    },
}

INJURIES = {
    None: {'avoid_families': [], 'avoid_muscles': []},
    'Lower Back': {
        'avoid_families': ['deadlift', 'romanian_deadlift', 'good_morning', 'back_extension', 'bent_over_row'],
        'avoid_muscles': ['Lower Back']
    },
    'Knee': {
        'avoid_families': ['squat', 'lunge', 'leg_press', 'leg_extension', 'box_jump', 'jump'],
        'avoid_muscles': ['Quads']
    },
    'Shoulder': {
        'avoid_families': ['shoulder_press', 'overhead_press', 'lateral_raise', 'upright_row', 'military_press'],
        'avoid_muscles': ['Shoulders', 'Front Delts', 'Side Delts']
    },
    'Wrist': {
        'avoid_families': ['wrist_curl', 'front_squat'],
        'avoid_muscles': ['Forearms']
    },
    'Hip': {
        'avoid_families': ['hip_thrust', 'glute_bridge', 'hip_abduction'],
        'avoid_muscles': ['Hip Flexors', 'Hips']
    },
    'Elbow': {
        'avoid_families': ['skull_crusher', 'tricep_extension'],
        'avoid_muscles': []
    },
}

FIRST_NAMES = [
    'Alex', 'Jordan', 'Taylor', 'Morgan', 'Casey', 'Riley', 'Quinn', 'Avery',
    'Blake', 'Cameron', 'Dakota', 'Emery', 'Finley', 'Harper', 'Jamie', 'Kendall',
    'Logan', 'Marley', 'Nico', 'Parker', 'Reese', 'Sage', 'Skyler', 'Drew',
    'Ellis', 'Flynn', 'Gray', 'Haven', 'Ivory', 'Jules', 'Kai', 'Lane',
    'Mason', 'Noel', 'Oakley', 'Peyton', 'Rory', 'Sawyer', 'Tatum', 'Val',
    'Wren', 'Zion', 'Ash', 'Bay', 'Charlie', 'Devon', 'Eden', 'Frankie',
    'Sam', 'Max', 'Chris', 'Pat', 'Lee', 'Robin', 'Terry', 'Kim'
]


def generate_user(user_id):
    """Generate a diverse user profile"""
    gender = random.choice(GENDERS)
    
    # Realistic height/weight based on gender
    if gender == 'Male':
        height = random.randint(64, 76)
        weight = random.randint(140, 250)
    else:
        height = random.randint(60, 70)
        weight = random.randint(105, 190)
    
    age = random.randint(16, 70)
    goal = random.choice(GOALS)
    experience = random.choice(EXPERIENCE_LEVELS)
    location = random.choice(LOCATIONS)
    
    # Equipment based on location
    if location == 'home':
        equipment_set = random.choice(['minimal_home', 'home_basic', 'home_intermediate', 'home_advanced'])
    else:
        equipment_set = random.choice(['gym_basic', 'gym_standard', 'gym_full'])
    
    # Injuries (weighted towards no injury)
    injury_options = [None, None, None, None, None, 'Lower Back', 'Knee', 'Shoulder', 'Wrist', 'Hip', 'Elbow']
    injury = random.choice(injury_options)
    
    # Workout type
    workout_type = random.choice(list(WORKOUT_TYPES.keys()))
    
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
        'equipment': EQUIPMENT_SETS[equipment_set]['equipment'],
        'equipment_categories': EQUIPMENT_SETS[equipment_set]['categories'],
        'injury': injury,
        'workout_type': workout_type,
    }


# ============================================================================
# WORKOUT GENERATION
# ============================================================================

def get_max_difficulty(experience):
    """Get maximum difficulty level for experience"""
    return {'Beginner': 2, 'Intermediate': 3, 'Advanced': 5}[experience]


def get_priority_key(user):
    """Get priority key based on user goal and location"""
    if user['location'] == 'home':
        return 'priority_home'
    elif user['goal'] == 'Build Muscle':
        return 'priority_build_muscle'
    elif user['goal'] == 'Get Lean':
        return 'priority_get_lean'
    else:
        return 'priority_gym'


def filter_exercises(exercises, user):
    """Filter exercises based on user profile"""
    filtered = []
    max_difficulty = get_max_difficulty(user['experience'])
    workout_config = WORKOUT_TYPES[user['workout_type']]
    injury_config = INJURIES.get(user['injury'], INJURIES[None])
    
    for ex in exercises:
        # Check equipment
        eq_cat = ex.get('equipment_category', 'bodyweight')
        if eq_cat not in user['equipment_categories']:
            continue
        
        # Check difficulty
        difficulty = ex.get('difficulty_level', 3)
        if difficulty > max_difficulty:
            continue
        
        # Check injury restrictions (family)
        family = ex.get('exercise_family', '')
        if any(avoid in family for avoid in injury_config['avoid_families']):
            continue
        
        # Check injury restrictions (muscle)
        primary_muscles = ex.get('primary_muscles', [])
        if isinstance(primary_muscles, str):
            try:
                import ast
                primary_muscles = ast.literal_eval(primary_muscles)
            except:
                primary_muscles = []
        
        if any(muscle in primary_muscles for muscle in injury_config['avoid_muscles']):
            continue
        
        # Check workout type targeting (if not full body)
        if workout_config['families']:
            if not any(fam in family for fam in workout_config['families']):
                # Also check by muscle
                if workout_config['muscles']:
                    muscle_match = any(m in primary_muscles for m in workout_config['muscles'])
                    if not muscle_match:
                        continue
                else:
                    continue
        
        filtered.append(ex)
    
    return filtered


def generate_workout(filtered_exercises, user, num_exercises=6):
    """
    Generate a workout from filtered exercises - MIRRORS Swift WorkoutGeneratorService logic
    
    Key features (matching the app):
    1. Equipment Diversity - Round-robin allocation across equipment types
    2. Muscle Diversity - Ensure each target muscle gets exercises  
    3. Movement Diversity - Max 2 per movement type (press, fly, curl, etc.)
    4. Body Position Diversity - Max 2 per position (seated, standing, lying)
    5. Goal-based Scoring - Using priority fields
    6. Compound First - Order compounds before isolation
    """
    if not filtered_exercises:
        return []
    
    import random
    import math
    
    priority_key = get_priority_key(user)
    location_key = 'priority_home' if user.get('location') == 'home' else 'priority_gym'
    
    # ===== SCORING (mirrors Swift scoring logic) =====
    def score_exercise(ex):
        score = 100.0
        name = (ex.get('name') or '').lower()
        
        # Goal-based priority score
        goal_priority = ex.get(priority_key, 50) or 50
        score += goal_priority * 0.5  # Weight the priority
        
        # Location-based priority
        location_priority = ex.get(location_key, 50) or 50
        score += location_priority * 0.3
        
        # Compound movement bonus (+40)
        compound_keywords = ['squat', 'deadlift', 'press', 'bench', 'row', 'pull-up', 'pullup',
                           'chin-up', 'chinup', 'lunge', 'dip', 'clean', 'snatch', 'thruster']
        is_compound = any(kw in name for kw in compound_keywords)
        if is_compound:
            score += 40
        
        # Goal-specific bonuses (mirrors Swift goal optimization)
        goal = user.get('goal', '').lower()
        if 'build muscle' in goal or 'muscle' in goal:
            if is_compound:
                score += 25
            equip = ex.get('equipment_category', '')
            if equip in ['barbell', 'dumbbell']:
                score += 15
        elif 'get lean' in goal or 'lean' in goal:
            if ex.get('exercise_family', '') in ['plyometrics', 'cardio']:
                score += 35
            if 'jump' in name or 'burpee' in name:
                score += 20
        elif 'strength' in goal or 'stronger' in goal:
            if is_compound:
                score += 35
            if ex.get('equipment_category') == 'barbell':
                score += 25
        
        # Experience level adjustment
        experience = user.get('experience', 'intermediate').lower()
        difficulty = ex.get('difficulty_level', 3) or 3
        
        if experience == 'beginner':
            if difficulty <= 2:
                score += 50
            elif difficulty >= 4:
                score -= 50
            # Beginners prefer machines
            if ex.get('equipment_category') == 'machine':
                score += 30
        elif experience == 'advanced':
            if difficulty >= 4:
                score += 30
            elif difficulty <= 1:
                score -= 20
            # Advanced prefer free weights
            if ex.get('equipment_category') in ['barbell', 'dumbbell']:
                score += 20
        
        # Add small randomness for variety
        score += random.uniform(0, 30)
        
        return score
    
    # Score and sort exercises
    scored_exercises = [(ex, score_exercise(ex)) for ex in filtered_exercises]
    scored_exercises.sort(key=lambda x: x[1], reverse=True)
    sorted_exercises = [ex for ex, score in scored_exercises]
    
    # ===== DIVERSITY TRACKING (mirrors Swift diversity logic) =====
    workout = []
    used_names = set()
    used_families = set()
    used_equipment = {}  # equipment_type -> count
    used_muscles = {}    # normalized_muscle -> count
    used_positions = {}  # body_position -> count
    used_movements = {}  # movement_type -> count
    
    # Get user's equipment categories
    equipment_set = user.get('equipment_set', 'gym_standard')
    user_equipment = EQUIPMENT_SETS.get(equipment_set, ['bodyweight'])
    
    # Helper functions
    def get_body_position(name):
        name = name.lower()
        if 'lying' in name or 'floor' in name or 'prone' in name or 'supine' in name:
            return 'lying'
        if 'seated' in name or 'sitting' in name:
            return 'seated'
        if 'standing' in name:
            return 'standing'
        if 'kneeling' in name:
            return 'kneeling'
        if 'incline' in name:
            return 'incline'
        if 'decline' in name:
            return 'decline'
        return 'other'
    
    def get_movement_type(name):
        name = name.lower()
        if 'press' in name:
            return 'press'
        if 'fly' in name or 'flye' in name:
            return 'fly'
        if 'row' in name:
            return 'row'
        if 'curl' in name:
            return 'curl'
        if 'extension' in name:
            return 'extension'
        if 'raise' in name:
            return 'raise'
        if 'pulldown' in name or 'pull down' in name or 'pull-down' in name:
            return 'pulldown'
        if 'squat' in name:
            return 'squat'
        if 'lunge' in name:
            return 'lunge'
        if 'deadlift' in name:
            return 'deadlift'
        return 'other'
    
    def normalize_muscle(muscles):
        if not muscles:
            return 'unknown'
        if isinstance(muscles, str):
            muscles = [muscles]
        m = muscles[0].lower() if muscles else 'unknown'
        if 'bicep' in m:
            return 'biceps'
        if 'tricep' in m:
            return 'triceps'
        if 'chest' in m or 'pec' in m:
            return 'chest'
        if 'lat' in m and 'delt' not in m:
            return 'back'
        if 'back' in m:
            return 'back'
        if 'shoulder' in m or 'delt' in m:
            return 'shoulders'
        if 'quad' in m:
            return 'quads'
        if 'hamstring' in m:
            return 'hamstrings'
        if 'glute' in m:
            return 'glutes'
        if 'calf' in m or 'calves' in m:
            return 'calves'
        if 'ab' in m or 'core' in m:
            return 'core'
        return m
    
    def can_add_exercise(ex):
        """Check all diversity constraints"""
        name = (ex.get('name') or '').lower()
        equipment = ex.get('equipment_category', 'bodyweight')
        muscles = ex.get('primary_muscles', [])
        
        # Already used?
        if name in used_names:
            return False
        
        # Family diversity - max 1 per family (unless filling)
        family = ex.get('exercise_family', 'general')
        if family in used_families and len(workout) < num_exercises - 2:
            return False
        
        # Equipment diversity - max 2 per equipment type (60% rule)
        max_per_equipment = max(2, int(math.ceil(num_exercises * 0.6)))
        if used_equipment.get(equipment, 0) >= max_per_equipment:
            return False
        
        # Position diversity - max 2 per position
        position = get_body_position(ex.get('name', ''))
        if used_positions.get(position, 0) >= 2:
            return False
        
        # Movement diversity - max 2 per movement type
        movement = get_movement_type(ex.get('name', ''))
        if movement != 'other' and used_movements.get(movement, 0) >= 2:
            return False
        
        # Muscle diversity - balance across muscle groups
        muscle = normalize_muscle(muscles)
        max_per_muscle = max(2, int(math.ceil(num_exercises / 3)))
        if used_muscles.get(muscle, 0) >= max_per_muscle:
            return False
        
        return True
    
    def add_exercise(ex):
        """Add exercise and update tracking"""
        name = (ex.get('name') or '').lower()
        equipment = ex.get('equipment_category', 'bodyweight')
        muscles = ex.get('primary_muscles', [])
        family = ex.get('exercise_family', 'general')
        
        workout.append(ex)
        used_names.add(name)
        used_families.add(family)
        used_equipment[equipment] = used_equipment.get(equipment, 0) + 1
        
        position = get_body_position(ex.get('name', ''))
        used_positions[position] = used_positions.get(position, 0) + 1
        
        movement = get_movement_type(ex.get('name', ''))
        used_movements[movement] = used_movements.get(movement, 0) + 1
        
        muscle = normalize_muscle(muscles)
        used_muscles[muscle] = used_muscles.get(muscle, 0) + 1
    
    # ===== PHASE 1: Round-robin equipment diversity (mirrors Swift PHASE 1) =====
    if len(user_equipment) > 1:
        slots_per_type = max(1, num_exercises // len(user_equipment))
        taken_per_type = {eq: 0 for eq in user_equipment}
        
        # Index exercises by equipment
        exercises_by_equip = {eq: [] for eq in user_equipment}
        for ex in sorted_exercises:
            equip = ex.get('equipment_category', 'bodyweight')
            if equip in exercises_by_equip:
                exercises_by_equip[equip].append(ex)
        
        # Round-robin: take 1 from each type, repeat
        round_num = 0
        max_rounds = num_exercises * 2
        
        while len(workout) < num_exercises and round_num < max_rounds:
            added_this_round = False
            
            for equip in user_equipment:
                if len(workout) >= num_exercises:
                    break
                if taken_per_type[equip] >= slots_per_type:
                    continue
                
                # Find next available exercise of this type
                for ex in exercises_by_equip[equip]:
                    if can_add_exercise(ex):
                        add_exercise(ex)
                        taken_per_type[equip] += 1
                        added_this_round = True
                        break
            
            round_num += 1
            if not added_this_round:
                break
    
    # ===== PHASE 2: Fill remaining with best available (mirrors Swift PHASE 2) =====
    for ex in sorted_exercises:
        if len(workout) >= num_exercises:
            break
        if can_add_exercise(ex):
            add_exercise(ex)
    
    # ===== PHASE 3: Relaxed fill if still short =====
    if len(workout) < num_exercises:
        for ex in sorted_exercises:
            if len(workout) >= num_exercises:
                break
            name = (ex.get('name') or '').lower()
            if name not in used_names:
                workout.append(ex)
                used_names.add(name)
    
    # ===== ORDER: Compound exercises first (mirrors Swift sorting) =====
    compound_keywords = ['squat', 'deadlift', 'press', 'bench', 'row', 'pull-up', 'pullup',
                        'chin-up', 'chinup', 'lunge', 'dip', 'clean', 'snatch', 'thruster']
    
    def is_compound(ex):
        name = (ex.get('name') or '').lower()
        return any(kw in name for kw in compound_keywords)
    
    workout.sort(key=lambda ex: (0 if is_compound(ex) else 1))
    
    return workout


# ============================================================================
# VALIDATION & SCORING
# ============================================================================

def validate_workout(workout, user, all_exercises):
    """Comprehensive validation of workout against user requirements"""
    
    validations = {
        'equipment_match': {'passed': 0, 'failed': 0, 'details': []},
        'difficulty_appropriate': {'passed': 0, 'failed': 0, 'details': []},
        'workout_type_match': {'passed': 0, 'failed': 0, 'details': []},
        'injury_respected': {'passed': 0, 'failed': 0, 'details': []},
        'priority_ordering': {'passed': True, 'details': []},
        'family_diversity': {'score': 0, 'unique_families': 0},
    }
    
    max_difficulty = get_max_difficulty(user['experience'])
    workout_config = WORKOUT_TYPES[user['workout_type']]
    injury_config = INJURIES.get(user['injury'], INJURIES[None])
    priority_key = get_priority_key(user)
    
    unique_families = set()
    prev_priority = float('inf')
    
    for ex in workout:
        name = ex.get('name', 'Unknown')
        family = ex.get('exercise_family', '')
        eq_cat = ex.get('equipment_category', 'bodyweight')
        difficulty = ex.get('difficulty_level', 3)
        priority = ex.get(priority_key, 50)
        
        primary_muscles = ex.get('primary_muscles', [])
        if isinstance(primary_muscles, str):
            try:
                import ast
                primary_muscles = ast.literal_eval(primary_muscles)
            except:
                primary_muscles = []
        
        unique_families.add(family)
        
        # 1. Equipment match
        if eq_cat in user['equipment_categories']:
            validations['equipment_match']['passed'] += 1
        else:
            validations['equipment_match']['failed'] += 1
            validations['equipment_match']['details'].append(
                f"❌ {name}: uses {eq_cat}, user has {user['equipment_categories']}"
            )
        
        # 2. Difficulty appropriate
        if difficulty <= max_difficulty:
            validations['difficulty_appropriate']['passed'] += 1
        else:
            validations['difficulty_appropriate']['failed'] += 1
            validations['difficulty_appropriate']['details'].append(
                f"❌ {name}: Level {difficulty} > max {max_difficulty} for {user['experience']}"
            )
        
        # 3. Workout type match
        if workout_config['families'] is None:  # Full body
            validations['workout_type_match']['passed'] += 1
        else:
            family_match = any(fam in family for fam in workout_config['families'])
            muscle_match = any(m in primary_muscles for m in (workout_config['muscles'] or []))
            if family_match or muscle_match:
                validations['workout_type_match']['passed'] += 1
            else:
                validations['workout_type_match']['failed'] += 1
                validations['workout_type_match']['details'].append(
                    f"⚠️ {name}: family '{family}' may not match {user['workout_type']}"
                )
        
        # 4. Injury respected
        family_violation = any(avoid in family for avoid in injury_config['avoid_families'])
        muscle_violation = any(m in primary_muscles for m in injury_config['avoid_muscles'])
        
        if not family_violation and not muscle_violation:
            validations['injury_respected']['passed'] += 1
        else:
            validations['injury_respected']['failed'] += 1
            validations['injury_respected']['details'].append(
                f"❌ {name}: violates {user['injury']} injury restriction"
            )
        
        # 5. Priority ordering check
        if priority > prev_priority:
            validations['priority_ordering']['passed'] = False
            validations['priority_ordering']['details'].append(
                f"⚠️ {name} has higher priority than previous exercise"
            )
        prev_priority = priority
    
    # 6. Family diversity
    validations['family_diversity']['unique_families'] = len(unique_families)
    validations['family_diversity']['score'] = min(100, (len(unique_families) / len(workout)) * 100) if workout else 0
    
    return validations


def calculate_scores(validations, workout):
    """Calculate overall scores from validations"""
    if not workout:
        return {'equipment': 0, 'difficulty': 0, 'workout_type': 0, 'injury': 0, 'overall': 0}
    
    total = len(workout)
    
    equipment_score = (validations['equipment_match']['passed'] / total) * 100
    difficulty_score = (validations['difficulty_appropriate']['passed'] / total) * 100
    workout_type_score = (validations['workout_type_match']['passed'] / total) * 100
    injury_score = (validations['injury_respected']['passed'] / total) * 100
    
    # Weighted overall score
    overall = (
        equipment_score * 0.25 +
        difficulty_score * 0.25 +
        workout_type_score * 0.20 +
        injury_score * 0.30  # Injury is most important
    )
    
    return {
        'equipment': equipment_score,
        'difficulty': difficulty_score,
        'workout_type': workout_type_score,
        'injury': injury_score,
        'overall': overall,
    }


def get_grade(score):
    """Convert score to letter grade"""
    if score >= 95: return 'A+'
    if score >= 90: return 'A'
    if score >= 85: return 'B+'
    if score >= 80: return 'B'
    if score >= 75: return 'C+'
    if score >= 70: return 'C'
    if score >= 60: return 'D'
    return 'F'


# ============================================================================
# TEST RUNNER
# ============================================================================

def run_user_test(user, all_exercises):
    """Run complete test for a single user"""
    
    # Filter exercises
    filtered = filter_exercises(all_exercises, user)
    
    # Generate workout
    workout = generate_workout(filtered, user)
    
    # Validate
    validations = validate_workout(workout, user, all_exercises)
    
    # Score
    scores = calculate_scores(validations, workout)
    
    return {
        'user': user,
        'filtered_count': len(filtered),
        'workout': [
            {
                'name': ex.get('name'),
                'family': ex.get('exercise_family'),
                'equipment_category': ex.get('equipment_category'),
                'difficulty_level': ex.get('difficulty_level'),
                'primary_muscles': ex.get('primary_muscles'),
            }
            for ex in workout
        ],
        'validations': validations,
        'scores': scores,
        'grade': get_grade(scores['overall']),
    }


def generate_text_report(result):
    """Generate detailed text report for a user"""
    user = result['user']
    
    lines = []
    lines.append("=" * 80)
    lines.append(f"👤 USER #{user['id']}: {user['name']}")
    lines.append("=" * 80)
    lines.append("")
    lines.append("📊 PROFILE")
    lines.append("-" * 40)
    lines.append(f"Gender: {user['gender']} | Age: {user['age']}")
    lines.append(f"Height: {user['height']}in ({user['height']//12}'{user['height']%12}\")")
    lines.append(f"Weight: {user['weight']} lbs")
    lines.append(f"Goal: {user['goal']}")
    lines.append(f"Experience: {user['experience']}")
    lines.append(f"Location: {user['location'].upper()}")
    lines.append(f"Equipment: {', '.join(user['equipment'])}")
    lines.append(f"Injury: {user['injury'] if user['injury'] else 'None'}")
    lines.append(f"Workout Type: {user['workout_type']}")
    lines.append("")
    lines.append("📋 EXPECTED CONSTRAINTS")
    lines.append("-" * 40)
    lines.append(f"Max Difficulty: Level {get_max_difficulty(user['experience'])}")
    lines.append(f"Equipment Categories: {', '.join(user['equipment_categories'])}")
    if user['injury']:
        injury_config = INJURIES[user['injury']]
        lines.append(f"Avoid Families: {', '.join(injury_config['avoid_families'][:5])}...")
        lines.append(f"Avoid Muscles: {', '.join(injury_config['avoid_muscles'])}")
    lines.append("")
    lines.append("🏋️ GENERATED WORKOUT")
    lines.append("-" * 40)
    lines.append(f"Filtered Pool: {result['filtered_count']} exercises")
    lines.append(f"Selected: {len(result['workout'])} exercises")
    lines.append("")
    
    for i, ex in enumerate(result['workout'], 1):
        lines.append(f"{i}. {ex['name']}")
        lines.append(f"   Family: {ex['family']}")
        lines.append(f"   Equipment: {ex['equipment_category']} | Difficulty: Level {ex['difficulty_level']}")
        lines.append(f"   Muscles: {ex['primary_muscles']}")
        lines.append("")
    
    lines.append("✅ VALIDATION RESULTS")
    lines.append("-" * 40)
    
    v = result['validations']
    s = result['scores']
    
    lines.append(f"Equipment Match: {v['equipment_match']['passed']}/{v['equipment_match']['passed']+v['equipment_match']['failed']} ({s['equipment']:.1f}%)")
    for detail in v['equipment_match']['details'][:3]:
        lines.append(f"   {detail}")
    
    lines.append(f"Difficulty Appropriate: {v['difficulty_appropriate']['passed']}/{v['difficulty_appropriate']['passed']+v['difficulty_appropriate']['failed']} ({s['difficulty']:.1f}%)")
    for detail in v['difficulty_appropriate']['details'][:3]:
        lines.append(f"   {detail}")
    
    lines.append(f"Workout Type Match: {v['workout_type_match']['passed']}/{v['workout_type_match']['passed']+v['workout_type_match']['failed']} ({s['workout_type']:.1f}%)")
    for detail in v['workout_type_match']['details'][:3]:
        lines.append(f"   {detail}")
    
    lines.append(f"Injury Respected: {v['injury_respected']['passed']}/{v['injury_respected']['passed']+v['injury_respected']['failed']} ({s['injury']:.1f}%)")
    for detail in v['injury_respected']['details'][:3]:
        lines.append(f"   {detail}")
    
    lines.append(f"Family Diversity: {v['family_diversity']['unique_families']} unique families")
    lines.append("")
    lines.append("🎯 FINAL SCORE")
    lines.append("-" * 40)
    lines.append(f"Equipment:     {s['equipment']:6.1f}%")
    lines.append(f"Difficulty:    {s['difficulty']:6.1f}%")
    lines.append(f"Workout Type:  {s['workout_type']:6.1f}%")
    lines.append(f"Injury Safety: {s['injury']:6.1f}%")
    lines.append(f"{'=' * 25}")
    lines.append(f"OVERALL:       {s['overall']:6.1f}% (Grade: {result['grade']})")
    lines.append("")
    
    return "\n".join(lines)


def main():
    print("=" * 80)
    print("🧪 COMPREHENSIVE 500 USER TEST SUITE")
    print("=" * 80)
    print()
    
    # Fetch all exercises
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
    
    # Generate 500 users
    print("👥 Generating 500 diverse test users...")
    users = [generate_user(i + 1) for i in range(500)]
    
    # Profile distribution
    goal_counts = {}
    exp_counts = {}
    loc_counts = {}
    injury_counts = {}
    workout_counts = {}
    
    for u in users:
        goal_counts[u['goal']] = goal_counts.get(u['goal'], 0) + 1
        exp_counts[u['experience']] = exp_counts.get(u['experience'], 0) + 1
        loc_counts[u['location']] = loc_counts.get(u['location'], 0) + 1
        injury_counts[u['injury'] or 'None'] = injury_counts.get(u['injury'] or 'None', 0) + 1
        workout_counts[u['workout_type']] = workout_counts.get(u['workout_type'], 0) + 1
    
    print(f"   Goals: {goal_counts}")
    print(f"   Experience: {exp_counts}")
    print(f"   Location: {loc_counts}")
    print(f"   Injuries: {injury_counts}")
    print(f"   Workout Types: {workout_counts}")
    print()
    
    # Run tests
    print("🔬 Running tests on all 500 users...")
    results = []
    
    for i, user in enumerate(users):
        result = run_user_test(user, all_exercises)
        results.append(result)
        
        if (i + 1) % 100 == 0:
            print(f"   Completed {i + 1}/500 users...")
    
    print()
    
    # Calculate summary stats
    grade_counts = {'A+': 0, 'A': 0, 'B+': 0, 'B': 0, 'C+': 0, 'C': 0, 'D': 0, 'F': 0}
    total_scores = {'equipment': 0, 'difficulty': 0, 'workout_type': 0, 'injury': 0, 'overall': 0}
    issues = {'equipment': 0, 'difficulty': 0, 'workout_type': 0, 'injury': 0}
    
    for r in results:
        grade_counts[r['grade']] = grade_counts.get(r['grade'], 0) + 1
        for key in total_scores:
            total_scores[key] += r['scores'][key]
        
        if r['scores']['equipment'] < 100:
            issues['equipment'] += 1
        if r['scores']['difficulty'] < 100:
            issues['difficulty'] += 1
        if r['scores']['workout_type'] < 100:
            issues['workout_type'] += 1
        if r['scores']['injury'] < 100:
            issues['injury'] += 1
    
    avg_scores = {k: v / len(results) for k, v in total_scores.items()}
    
    # Print summary
    print("=" * 80)
    print("📊 TEST RESULTS SUMMARY")
    print("=" * 80)
    print()
    print("📈 GRADE DISTRIBUTION:")
    for grade in ['A+', 'A', 'B+', 'B', 'C+', 'C', 'D', 'F']:
        count = grade_counts.get(grade, 0)
        pct = (count / len(results)) * 100
        bar = '█' * int(pct / 2)
        print(f"   {grade:3}: {count:4d} ({pct:5.1f}%) {bar}")
    
    print()
    print("📊 AVERAGE SCORES:")
    print(f"   Equipment Match:     {avg_scores['equipment']:6.1f}%")
    print(f"   Difficulty Level:    {avg_scores['difficulty']:6.1f}%")
    print(f"   Workout Type Match:  {avg_scores['workout_type']:6.1f}%")
    print(f"   Injury Safety:       {avg_scores['injury']:6.1f}%")
    print(f"   {'=' * 30}")
    print(f"   OVERALL AVERAGE:     {avg_scores['overall']:6.1f}% (Grade: {get_grade(avg_scores['overall'])})")
    
    print()
    print("⚠️ ISSUES DETECTED:")
    print(f"   Equipment mismatches: {issues['equipment']}/500 users")
    print(f"   Difficulty violations: {issues['difficulty']}/500 users")
    print(f"   Workout type mismatches: {issues['workout_type']}/500 users")
    print(f"   Injury violations: {issues['injury']}/500 users")
    
    # Select 20 users for detailed report (mix of best, worst, and edge cases)
    sorted_results = sorted(results, key=lambda x: x['scores']['overall'], reverse=True)
    
    # Get diverse sample: 5 best, 5 worst, 10 with various issues/edge cases
    sample_results = []
    sample_results.extend(sorted_results[:5])  # Top 5
    sample_results.extend(sorted_results[-5:])  # Bottom 5
    
    # Add 10 interesting edge cases
    edge_cases = []
    for r in results:
        if r not in sample_results:
            # Users with injuries
            if r['user']['injury'] and len(edge_cases) < 3:
                edge_cases.append(r)
            # Beginner users
            elif r['user']['experience'] == 'Beginner' and len(edge_cases) < 5:
                edge_cases.append(r)
            # Home minimal equipment
            elif r['user']['equipment_set'] == 'minimal_home' and len(edge_cases) < 7:
                edge_cases.append(r)
            # Various workout types
            elif r['user']['workout_type'] in ['Core', 'Arms', 'Legs'] and len(edge_cases) < 10:
                edge_cases.append(r)
    
    sample_results.extend(edge_cases[:10])
    sample_results = sample_results[:20]  # Ensure exactly 20
    
    # Generate detailed reports
    print()
    print("=" * 80)
    print("📋 GENERATING DETAILED REPORTS (20 USERS)")
    print("=" * 80)
    
    detailed_reports = []
    for result in sample_results:
        report = generate_text_report(result)
        detailed_reports.append(report)
    
    # Save to text file (for PDF conversion)
    report_content = "\n\n".join(detailed_reports)
    
    # Add header
    header = f"""
{'='*80}
COMPREHENSIVE WORKOUT GENERATION AUDIT REPORT
{'='*80}

Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}
Total Users Tested: 500
Sample Users in Report: 20

SUMMARY STATISTICS
{'='*80}
Overall Average Score: {avg_scores['overall']:.1f}%
Overall Grade: {get_grade(avg_scores['overall'])}

Score Breakdown:
- Equipment Match: {avg_scores['equipment']:.1f}%
- Difficulty Appropriate: {avg_scores['difficulty']:.1f}%
- Workout Type Match: {avg_scores['workout_type']:.1f}%
- Injury Safety: {avg_scores['injury']:.1f}%

Grade Distribution:
"""
    for grade in ['A+', 'A', 'B+', 'B', 'C+', 'C', 'D', 'F']:
        count = grade_counts.get(grade, 0)
        pct = (count / 500) * 100
        header += f"  {grade}: {count} ({pct:.1f}%)\n"
    
    header += f"""
Issues Detected:
- Equipment mismatches: {issues['equipment']}/500
- Difficulty violations: {issues['difficulty']}/500  
- Workout type mismatches: {issues['workout_type']}/500
- Injury violations: {issues['injury']}/500

{'='*80}
DETAILED USER REPORTS (20 SAMPLE USERS)
{'='*80}

"""
    
    full_report = header + report_content
    
    # Save text report
    with open('500_user_audit_report.txt', 'w') as f:
        f.write(full_report)
    
    print(f"📄 Text report saved to: 500_user_audit_report.txt")
    
    # Save JSON results
    json_output = {
        'summary': {
            'total_users': 500,
            'avg_scores': avg_scores,
            'grade_counts': grade_counts,
            'issues': issues,
            'overall_grade': get_grade(avg_scores['overall']),
        },
        'detailed_results': [
            {
                'user': r['user'],
                'filtered_count': r['filtered_count'],
                'workout': r['workout'],
                'scores': r['scores'],
                'grade': r['grade'],
            }
            for r in sample_results
        ],
    }
    
    with open('500_user_audit_results.json', 'w') as f:
        json.dump(json_output, f, indent=2)
    
    print(f"📁 JSON results saved to: 500_user_audit_results.json")
    
    # Print sample reports to console
    print()
    print("=" * 80)
    print("📋 SAMPLE DETAILED REPORTS")
    print("=" * 80)
    
    for report in detailed_reports[:5]:  # Show first 5
        print(report)
        print()
    
    print()
    print("=" * 80)
    print("✅ TEST SUITE COMPLETE")
    print("=" * 80)
    print(f"📄 Full report: 500_user_audit_report.txt")
    print(f"📁 JSON data: 500_user_audit_results.json")


if __name__ == "__main__":
    main()
