#!/usr/bin/env python3
"""
Comprehensive 100-User Workout Generation Test
Tests all filters: Equipment Diversity, Movement Diversity, Body Position, 
Goal-Based Scoring, Compound First, Experience Adjustments
"""

from supabase import create_client
from collections import Counter
import random
import math
import json
from datetime import datetime

SUPABASE_URL = "https://ehooeghabzefgoqzugrc.supabase.co"
SUPABASE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVob29lZ2hhYnplZmdvcXp1Z3JjIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjM4NDc4NjQsImV4cCI6MjA3OTQyMzg2NH0.6-QWDr5B279hybtu9MbPVhmBKlyzFq1GK9P7zlDXuY0"

supabase = create_client(SUPABASE_URL, SUPABASE_KEY)

# ============================================================================
# CONFIGURATION
# ============================================================================

EQUIPMENT_SETS = {
    'gym_standard': ['barbell', 'dumbbell', 'cable', 'machine'],
    'gym_basic': ['machine', 'cable', 'dumbbell'],
    'gym_full': ['barbell', 'dumbbell', 'cable', 'machine', 'kettlebell'],
    'home_full': ['dumbbell', 'barbell', 'kettlebell', 'band', 'bodyweight'],
    'home_minimal': ['bodyweight', 'band'],
    'home_dumbbells': ['dumbbell', 'bodyweight'],
    'bodyweight_only': ['bodyweight'],
}

WORKOUT_TYPES = {
    'Push': {
        'families': ['bench_press', 'incline_bench_press', 'decline_bench_press', 'chest_fly',
                    'shoulder_press', 'arnold_press', 'lateral_raise', 'front_raise',
                    'tricep_pushdown', 'tricep_extension', 'skull_crusher', 'dip', 'push_up', 'chest_press'],
        'muscles': ['Chest', 'Shoulders', 'Triceps', 'Front Delts', 'Side Delts']
    },
    'Pull': {
        'families': ['lat_pulldown', 'pull_up', 'chin_up', 'bent_over_row', 'seated_row',
                    'face_pull', 'bicep_curl', 'hammer_curl', 'preacher_curl', 'reverse_curl'],
        'muscles': ['Back', 'Lats', 'Biceps', 'Rear Delts', 'Traps']
    },
    'Legs': {
        'families': ['squat', 'leg_press', 'lunge', 'leg_curl', 'leg_extension',
                    'hip_thrust', 'glute_bridge', 'calf_raise', 'romanian_deadlift', 'deadlift'],
        'muscles': ['Quads', 'Hamstrings', 'Glutes', 'Calves']
    },
    'Upper': {
        'families': ['bench_press', 'shoulder_press', 'lat_pulldown', 'bent_over_row',
                    'bicep_curl', 'tricep_extension', 'lateral_raise', 'face_pull'],
        'muscles': ['Chest', 'Back', 'Shoulders', 'Biceps', 'Triceps']
    },
    'Lower': {
        'families': ['squat', 'deadlift', 'leg_press', 'lunge', 'leg_curl',
                    'leg_extension', 'hip_thrust', 'calf_raise'],
        'muscles': ['Quads', 'Hamstrings', 'Glutes', 'Calves']
    },
    'Full Body': {
        'families': ['squat', 'deadlift', 'bench_press', 'bent_over_row', 'shoulder_press'],
        'muscles': ['Chest', 'Back', 'Legs', 'Shoulders', 'Arms']
    },
    'Arms': {
        'families': ['bicep_curl', 'hammer_curl', 'preacher_curl', 'tricep_pushdown',
                    'tricep_extension', 'skull_crusher', 'wrist_curl', 'tricep_kickback'],
        'muscles': ['Biceps', 'Triceps', 'Forearms']
    },
    'Core': {
        'families': ['crunch', 'plank', 'leg_raise', 'russian_twist', 'sit_up',
                    'ab_rollout', 'side_bend', 'bicycle_crunch'],
        'muscles': ['Abs', 'Obliques', 'Core', 'Lower Abs']
    },
    'Back': {
        'families': ['lat_pulldown', 'pull_up', 'bent_over_row', 'seated_row',
                    'face_pull', 'back_extension', 'shrug'],
        'muscles': ['Back', 'Lats', 'Traps', 'Rear Delts', 'Rhomboids']
    },
    'Chest': {
        'families': ['bench_press', 'incline_bench_press', 'decline_bench_press',
                    'chest_fly', 'chest_press', 'push_up', 'dip'],
        'muscles': ['Chest', 'Upper Chest', 'Lower Chest']
    }
}

INJURIES = {
    None: {'avoid_families': [], 'avoid_muscles': []},
    'shoulder': {'avoid_families': ['shoulder_press', 'overhead_press', 'lateral_raise', 'arnold_press'], 
                 'avoid_muscles': ['Shoulders', 'Front Delts', 'Side Delts']},
    'back': {'avoid_families': ['deadlift', 'bent_over_row', 'good_morning', 'back_extension'],
             'avoid_muscles': ['Lower Back']},
    'knee': {'avoid_families': ['squat', 'lunge', 'leg_press', 'leg_extension'],
             'avoid_muscles': ['Quads']},
    'wrist': {'avoid_families': ['wrist_curl', 'push_up'],
              'avoid_muscles': ['Forearms']},
}

GOALS = ['Build Muscle', 'Get Lean', 'Build Strength', 'General Fitness', 'Endurance']
EXPERIENCE_LEVELS = ['Beginner', 'Intermediate', 'Advanced']
LOCATIONS = ['gym', 'home']
GENDERS = ['Male', 'Female']

NAMES = ['Alex', 'Jordan', 'Taylor', 'Casey', 'Morgan', 'Riley', 'Quinn', 'Avery', 
         'Cameron', 'Drew', 'Sage', 'Reese', 'Blake', 'Harper', 'Emery', 'Finley',
         'Hayden', 'Jamie', 'Kai', 'Logan', 'Marley', 'Nico', 'Parker', 'River',
         'Sawyer', 'Skyler', 'Spencer', 'Sydney', 'Tatum', 'Wren']

def generate_user(user_id):
    """Generate a diverse user profile"""
    gender = random.choice(GENDERS)
    goal = random.choice(GOALS)
    experience = random.choice(EXPERIENCE_LEVELS)
    location = random.choice(LOCATIONS)
    
    if location == 'home':
        equipment_options = ['home_full', 'home_minimal', 'home_dumbbells', 'bodyweight_only']
    else:
        equipment_options = ['gym_standard', 'gym_basic', 'gym_full']
    equipment_set = random.choice(equipment_options)
    
    injury = random.choice([None, None, None, 'shoulder', 'back', 'knee', 'wrist'])
    workout_type = random.choice(list(WORKOUT_TYPES.keys()))
    
    if gender == 'Male':
        height = f"{random.randint(5, 6)}'{random.randint(0, 11)}\""
        weight = random.randint(140, 250)
    else:
        height = f"{random.randint(4, 5)}'{random.randint(0, 11)}\""
        weight = random.randint(100, 180)
    
    age = random.randint(18, 65)
    
    return {
        'id': user_id,
        'name': f"{random.choice(NAMES)} #{user_id}",
        'gender': gender,
        'age': age,
        'height': height,
        'weight': weight,
        'goal': goal,
        'experience': experience,
        'location': location,
        'equipment_set': equipment_set,
        'injury': injury,
        'workout_type': workout_type
    }

def get_priority_key(user):
    goal = user.get('goal', '').lower()
    if 'build muscle' in goal or 'muscle' in goal:
        return 'priority_build_muscle'
    elif 'get lean' in goal or 'lean' in goal:
        return 'priority_get_lean'
    return 'priority_build_muscle'

def filter_exercises(all_exercises, user):
    """Filter exercises based on user profile"""
    equipment_categories = EQUIPMENT_SETS.get(user['equipment_set'], ['bodyweight'])
    workout_config = WORKOUT_TYPES.get(user['workout_type'], WORKOUT_TYPES['Full Body'])
    injury_config = INJURIES.get(user['injury'], INJURIES[None])
    
    max_difficulty = {'Beginner': 2, 'Intermediate': 4, 'Advanced': 5}.get(user['experience'], 4)
    
    filtered = []
    for ex in all_exercises:
        equip = ex.get('equipment_category', 'bodyweight')
        if equip not in equipment_categories:
            continue
        
        difficulty = ex.get('difficulty_level', 3) or 3
        if difficulty > max_difficulty:
            continue
        
        family = ex.get('exercise_family', '')
        muscles = ex.get('primary_muscles', [])
        if isinstance(muscles, str):
            import ast
            try:
                muscles = ast.literal_eval(muscles)
            except:
                muscles = []
        
        if any(avoid in family for avoid in injury_config['avoid_families']):
            continue
        if any(m in muscles for m in injury_config['avoid_muscles']):
            continue
        
        family_match = any(f in family for f in workout_config['families'])
        muscle_match = any(m in muscles for m in workout_config['muscles'])
        
        if family_match or muscle_match:
            filtered.append(ex)
    
    return filtered

def generate_workout(filtered_exercises, user, num_exercises=6):
    """Generate workout with full diversity logic (mirrors Swift)"""
    if not filtered_exercises:
        return []
    
    priority_key = get_priority_key(user)
    location_key = 'priority_home' if user.get('location') == 'home' else 'priority_gym'
    
    def score_exercise(ex):
        score = 100.0
        name = (ex.get('name') or '').lower()
        
        goal_priority = ex.get(priority_key, 50) or 50
        score += goal_priority * 0.5
        
        location_priority = ex.get(location_key, 50) or 50
        score += location_priority * 0.3
        
        compound_keywords = ['squat', 'deadlift', 'press', 'bench', 'row', 'pull-up', 'pullup',
                           'chin-up', 'chinup', 'lunge', 'dip', 'clean', 'snatch', 'thruster']
        is_compound = any(kw in name for kw in compound_keywords)
        if is_compound:
            score += 40
        
        goal = user.get('goal', '').lower()
        if 'build muscle' in goal:
            if is_compound: score += 25
            if ex.get('equipment_category') in ['barbell', 'dumbbell']: score += 15
        elif 'get lean' in goal:
            if 'jump' in name or 'burpee' in name: score += 20
        elif 'strength' in goal:
            if is_compound: score += 35
            if ex.get('equipment_category') == 'barbell': score += 25
        
        experience = user.get('experience', 'intermediate').lower()
        difficulty = ex.get('difficulty_level', 3) or 3
        
        if experience == 'beginner':
            if difficulty <= 2: score += 50
            elif difficulty >= 4: score -= 50
            if ex.get('equipment_category') == 'machine': score += 30
        elif experience == 'advanced':
            if difficulty >= 4: score += 30
            if ex.get('equipment_category') in ['barbell', 'dumbbell']: score += 20
        
        score += random.uniform(0, 30)
        return score
    
    scored_exercises = [(ex, score_exercise(ex)) for ex in filtered_exercises]
    scored_exercises.sort(key=lambda x: x[1], reverse=True)
    sorted_exercises = [ex for ex, score in scored_exercises]
    
    workout = []
    used_names = set()
    used_families = set()
    used_equipment = {}
    used_positions = {}
    used_movements = {}
    
    equipment_set = user.get('equipment_set', 'gym_standard')
    user_equipment = EQUIPMENT_SETS.get(equipment_set, ['bodyweight'])
    
    def get_body_position(name):
        name = name.lower()
        if 'lying' in name or 'floor' in name or 'prone' in name: return 'lying'
        if 'seated' in name or 'sitting' in name: return 'seated'
        if 'standing' in name: return 'standing'
        if 'kneeling' in name: return 'kneeling'
        return 'other'
    
    def get_movement_type(name):
        name = name.lower()
        if 'press' in name: return 'press'
        if 'fly' in name: return 'fly'
        if 'row' in name: return 'row'
        if 'curl' in name: return 'curl'
        if 'extension' in name: return 'extension'
        if 'raise' in name: return 'raise'
        if 'pulldown' in name: return 'pulldown'
        if 'squat' in name: return 'squat'
        if 'lunge' in name: return 'lunge'
        return 'other'
    
    def can_add_exercise(ex):
        name = (ex.get('name') or '').lower()
        equipment = ex.get('equipment_category', 'bodyweight')
        
        if name in used_names: return False
        
        family = ex.get('exercise_family', 'general')
        if family in used_families and len(workout) < num_exercises - 2: return False
        
        max_per_equipment = max(2, int(math.ceil(num_exercises * 0.6)))
        if used_equipment.get(equipment, 0) >= max_per_equipment: return False
        
        position = get_body_position(ex.get('name', ''))
        if used_positions.get(position, 0) >= 2: return False
        
        movement = get_movement_type(ex.get('name', ''))
        if movement != 'other' and used_movements.get(movement, 0) >= 2: return False
        
        return True
    
    def add_exercise(ex):
        name = (ex.get('name') or '').lower()
        equipment = ex.get('equipment_category', 'bodyweight')
        family = ex.get('exercise_family', 'general')
        
        workout.append(ex)
        used_names.add(name)
        used_families.add(family)
        used_equipment[equipment] = used_equipment.get(equipment, 0) + 1
        
        position = get_body_position(ex.get('name', ''))
        used_positions[position] = used_positions.get(position, 0) + 1
        
        movement = get_movement_type(ex.get('name', ''))
        used_movements[movement] = used_movements.get(movement, 0) + 1
    
    # PHASE 1: Round-robin equipment diversity
    if len(user_equipment) > 1:
        slots_per_type = max(1, num_exercises // len(user_equipment))
        taken_per_type = {eq: 0 for eq in user_equipment}
        
        exercises_by_equip = {eq: [] for eq in user_equipment}
        for ex in sorted_exercises:
            equip = ex.get('equipment_category', 'bodyweight')
            if equip in exercises_by_equip:
                exercises_by_equip[equip].append(ex)
        
        round_num = 0
        while len(workout) < num_exercises and round_num < num_exercises * 2:
            added_this_round = False
            for equip in user_equipment:
                if len(workout) >= num_exercises: break
                if taken_per_type[equip] >= slots_per_type: continue
                for ex in exercises_by_equip[equip]:
                    if can_add_exercise(ex):
                        add_exercise(ex)
                        taken_per_type[equip] += 1
                        added_this_round = True
                        break
            round_num += 1
            if not added_this_round: break
    
    # PHASE 2: Fill remaining
    for ex in sorted_exercises:
        if len(workout) >= num_exercises: break
        if can_add_exercise(ex):
            add_exercise(ex)
    
    # PHASE 3: Relaxed fill
    if len(workout) < num_exercises:
        for ex in sorted_exercises:
            if len(workout) >= num_exercises: break
            name = (ex.get('name') or '').lower()
            if name not in used_names:
                workout.append(ex)
                used_names.add(name)
    
    # Order: Compound first
    compound_keywords = ['squat', 'deadlift', 'press', 'bench', 'row', 'lunge', 'dip']
    def is_compound(ex):
        name = (ex.get('name') or '').lower()
        return any(kw in name for kw in compound_keywords)
    workout.sort(key=lambda ex: (0 if is_compound(ex) else 1))
    
    return workout

def validate_workout(workout, user, all_filtered):
    """Validate workout against all criteria"""
    results = {
        'equipment_match': {'score': 0, 'max': 100, 'details': []},
        'equipment_diversity': {'score': 0, 'max': 100, 'details': []},
        'difficulty_appropriate': {'score': 0, 'max': 100, 'details': []},
        'injury_safe': {'score': 0, 'max': 100, 'details': []},
        'workout_type_match': {'score': 0, 'max': 100, 'details': []},
        'movement_diversity': {'score': 0, 'max': 100, 'details': []},
        'position_diversity': {'score': 0, 'max': 100, 'details': []},
        'compound_ordering': {'score': 0, 'max': 100, 'details': []},
        'family_diversity': {'score': 0, 'max': 100, 'details': []},
    }
    
    if not workout:
        return results
    
    equipment_categories = EQUIPMENT_SETS.get(user['equipment_set'], ['bodyweight'])
    injury_config = INJURIES.get(user['injury'], INJURIES[None])
    workout_config = WORKOUT_TYPES.get(user['workout_type'], WORKOUT_TYPES['Full Body'])
    max_difficulty = {'Beginner': 2, 'Intermediate': 4, 'Advanced': 5}.get(user['experience'], 4)
    
    # 1. Equipment Match
    equip_match = sum(1 for ex in workout if ex.get('equipment_category') in equipment_categories)
    results['equipment_match']['score'] = int(equip_match / len(workout) * 100)
    results['equipment_match']['details'] = [f"{equip_match}/{len(workout)} exercises match user equipment"]
    
    # 2. Equipment Diversity
    equip_counts = Counter(ex.get('equipment_category') for ex in workout)
    unique_equip = len(equip_counts)
    max_possible = min(len(equipment_categories), len(workout))
    results['equipment_diversity']['score'] = int(unique_equip / max_possible * 100) if max_possible > 0 else 100
    results['equipment_diversity']['details'] = [f"{unique_equip} equipment types: {dict(equip_counts)}"]
    
    # 3. Difficulty Appropriate
    diff_ok = sum(1 for ex in workout if (ex.get('difficulty_level') or 3) <= max_difficulty)
    results['difficulty_appropriate']['score'] = int(diff_ok / len(workout) * 100)
    results['difficulty_appropriate']['details'] = [f"{diff_ok}/{len(workout)} at appropriate difficulty (max {max_difficulty})"]
    
    # 4. Injury Safe
    injury_violations = 0
    for ex in workout:
        family = ex.get('exercise_family', '')
        muscles = ex.get('primary_muscles', [])
        if isinstance(muscles, str):
            import ast
            try: muscles = ast.literal_eval(muscles)
            except: muscles = []
        
        if any(avoid in family for avoid in injury_config['avoid_families']):
            injury_violations += 1
        if any(m in muscles for m in injury_config['avoid_muscles']):
            injury_violations += 1
    
    results['injury_safe']['score'] = int((len(workout) - injury_violations) / len(workout) * 100)
    results['injury_safe']['details'] = [f"{injury_violations} injury violations" if injury_violations else "No injury violations"]
    
    # 5. Workout Type Match
    type_match = 0
    for ex in workout:
        family = ex.get('exercise_family', '')
        muscles = ex.get('primary_muscles', [])
        if isinstance(muscles, str):
            import ast
            try: muscles = ast.literal_eval(muscles)
            except: muscles = []
        
        if any(f in family for f in workout_config['families']) or any(m in muscles for m in workout_config['muscles']):
            type_match += 1
    
    results['workout_type_match']['score'] = int(type_match / len(workout) * 100)
    results['workout_type_match']['details'] = [f"{type_match}/{len(workout)} match {user['workout_type']} workout"]
    
    # 6. Movement Diversity
    def get_movement(name):
        name = name.lower()
        if 'press' in name: return 'press'
        if 'fly' in name: return 'fly'
        if 'row' in name: return 'row'
        if 'curl' in name: return 'curl'
        if 'extension' in name: return 'extension'
        if 'raise' in name: return 'raise'
        return 'other'
    
    movement_counts = Counter(get_movement(ex.get('name', '')) for ex in workout)
    max_same_movement = max(movement_counts.values()) if movement_counts else 0
    movement_score = 100 if max_same_movement <= 2 else max(0, 100 - (max_same_movement - 2) * 30)
    results['movement_diversity']['score'] = movement_score
    results['movement_diversity']['details'] = [f"Movement types: {dict(movement_counts)}"]
    
    # 7. Position Diversity
    def get_position(name):
        name = name.lower()
        if 'lying' in name or 'floor' in name: return 'lying'
        if 'seated' in name or 'sitting' in name: return 'seated'
        if 'standing' in name: return 'standing'
        return 'other'
    
    position_counts = Counter(get_position(ex.get('name', '')) for ex in workout)
    max_same_position = max(position_counts.values()) if position_counts else 0
    position_score = 100 if max_same_position <= 2 else max(0, 100 - (max_same_position - 2) * 25)
    results['position_diversity']['score'] = position_score
    results['position_diversity']['details'] = [f"Positions: {dict(position_counts)}"]
    
    # 8. Compound Ordering
    compound_keywords = ['squat', 'deadlift', 'press', 'bench', 'row', 'lunge', 'dip']
    def is_compound(name):
        return any(kw in name.lower() for kw in compound_keywords)
    
    compounds_first = True
    found_isolation = False
    for ex in workout:
        if is_compound(ex.get('name', '')):
            if found_isolation:
                compounds_first = False
                break
        else:
            found_isolation = True
    
    results['compound_ordering']['score'] = 100 if compounds_first else 50
    results['compound_ordering']['details'] = ["Compounds before isolation" if compounds_first else "Mixed ordering"]
    
    # 9. Family Diversity
    families = [ex.get('exercise_family', 'unknown') for ex in workout]
    unique_families = len(set(families))
    results['family_diversity']['score'] = int(unique_families / len(workout) * 100)
    results['family_diversity']['details'] = [f"{unique_families} unique families"]
    
    return results

def calculate_overall_score(validations):
    """Calculate weighted overall score"""
    weights = {
        'equipment_match': 15,
        'equipment_diversity': 15,
        'difficulty_appropriate': 15,
        'injury_safe': 15,
        'workout_type_match': 15,
        'movement_diversity': 10,
        'position_diversity': 5,
        'compound_ordering': 5,
        'family_diversity': 5,
    }
    
    total_weight = sum(weights.values())
    weighted_score = sum(validations[k]['score'] * weights[k] for k in weights)
    return int(weighted_score / total_weight)

def get_grade(score):
    if score >= 95: return 'A+'
    if score >= 90: return 'A'
    if score >= 85: return 'B+'
    if score >= 80: return 'B'
    if score >= 75: return 'C+'
    if score >= 70: return 'C'
    if score >= 60: return 'D'
    return 'F'

def generate_html_report(results, all_exercises, sample_users, grades, avg_score):
    """Generate HTML report"""
    categories = ['equipment_match', 'equipment_diversity', 'difficulty_appropriate', 
                  'injury_safe', 'workout_type_match', 'movement_diversity', 
                  'position_diversity', 'compound_ordering', 'family_diversity']
    
    html = f"""<!DOCTYPE html>
<html>
<head>
    <title>100-User Workout Generation Audit Report</title>
    <style>
        body {{ font-family: 'Segoe UI', Arial, sans-serif; margin: 40px; background: #f5f5f5; }}
        .container {{ max-width: 1200px; margin: 0 auto; background: white; padding: 40px; border-radius: 10px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }}
        h1 {{ color: #2c3e50; border-bottom: 3px solid #3498db; padding-bottom: 15px; }}
        h2 {{ color: #34495e; margin-top: 40px; }}
        .summary {{ background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 30px; border-radius: 10px; margin: 20px 0; }}
        .summary h2 {{ color: white; border: none; margin-top: 0; }}
        .grade-dist {{ display: flex; gap: 10px; flex-wrap: wrap; margin: 15px 0; }}
        .grade-box {{ padding: 10px 20px; border-radius: 5px; font-weight: bold; }}
        .grade-A {{ background: #27ae60; color: white; }}
        .grade-B {{ background: #f39c12; color: white; }}
        .grade-C {{ background: #e67e22; color: white; }}
        .grade-D {{ background: #e74c3c; color: white; }}
        .grade-F {{ background: #c0392b; color: white; }}
        .user-card {{ border: 1px solid #ddd; border-radius: 10px; padding: 20px; margin: 20px 0; background: #fafafa; page-break-inside: avoid; }}
        .user-header {{ display: flex; justify-content: space-between; align-items: center; margin-bottom: 15px; }}
        .user-grade {{ font-size: 24px; font-weight: bold; padding: 10px 20px; border-radius: 5px; }}
        .profile-grid {{ display: grid; grid-template-columns: repeat(3, 1fr); gap: 10px; margin: 15px 0; }}
        .profile-item {{ background: white; padding: 10px; border-radius: 5px; border-left: 3px solid #3498db; }}
        .profile-label {{ font-size: 12px; color: #7f8c8d; }}
        .profile-value {{ font-weight: bold; color: #2c3e50; }}
        .workout-table {{ width: 100%; border-collapse: collapse; margin: 15px 0; }}
        .workout-table th {{ background: #3498db; color: white; padding: 10px; text-align: left; }}
        .workout-table td {{ padding: 10px; border-bottom: 1px solid #ddd; }}
        .validation-grid {{ display: grid; grid-template-columns: repeat(3, 1fr); gap: 10px; margin: 15px 0; }}
        .validation-item {{ background: white; padding: 15px; border-radius: 5px; }}
        .validation-score {{ font-size: 24px; font-weight: bold; }}
        .score-good {{ color: #27ae60; }}
        .score-ok {{ color: #f39c12; }}
        .score-bad {{ color: #e74c3c; }}
        .timestamp {{ color: #95a5a6; font-size: 12px; margin-top: 30px; }}
    </style>
</head>
<body>
<div class="container">
    <h1>🏋️ 100-User Workout Generation Audit Report</h1>
    
    <div class="summary">
        <h2>Executive Summary</h2>
        <p><strong>Average Score:</strong> {avg_score:.1f}%</p>
        <p><strong>Total Users Tested:</strong> 100</p>
        <p><strong>Exercise Database:</strong> {len(all_exercises)} exercises</p>
        
        <h3>Grade Distribution</h3>
        <div class="grade-dist">
"""
    
    for grade in ['A+', 'A', 'B+', 'B', 'C+', 'C', 'D', 'F']:
        count = grades.get(grade, 0)
        grade_class = 'grade-A' if 'A' in grade else ('grade-B' if 'B' in grade else ('grade-C' if 'C' in grade else ('grade-D' if grade == 'D' else 'grade-F')))
        html += f'<div class="grade-box {grade_class}">{grade}: {count}</div>\n'
    
    html += """
        </div>
    </div>
    
    <h2>Validation Categories (Averages)</h2>
    <div class="validation-grid">
"""
    
    for cat in categories:
        avg = sum(r['validations'][cat]['score'] for r in results) / len(results)
        score_class = 'score-good' if avg >= 85 else ('score-ok' if avg >= 70 else 'score-bad')
        html += f"""
        <div class="validation-item">
            <div class="validation-score {score_class}">{avg:.0f}%</div>
            <div>{cat.replace('_', ' ').title()}</div>
        </div>
"""
    
    html += """
    </div>
    
    <h2>Detailed User Reports (20 Sample Users)</h2>
"""
    
    for result in sample_users:
        user = result['user']
        workout = result['workout']
        validations = result['validations']
        
        grade_class = 'grade-A' if 'A' in result['grade'] else ('grade-B' if 'B' in result['grade'] else ('grade-C' if 'C' in result['grade'] else ('grade-D' if result['grade'] == 'D' else 'grade-F')))
        
        html += f"""
    <div class="user-card">
        <div class="user-header">
            <h3>User #{user['id']}: {user['name']}</h3>
            <div class="user-grade {grade_class}">{result['grade']} ({result['overall_score']}%)</div>
        </div>
        
        <div class="profile-grid">
            <div class="profile-item"><div class="profile-label">Gender / Age</div><div class="profile-value">{user['gender']}, {user['age']}yo</div></div>
            <div class="profile-item"><div class="profile-label">Height / Weight</div><div class="profile-value">{user['height']} / {user['weight']}lbs</div></div>
            <div class="profile-item"><div class="profile-label">Goal</div><div class="profile-value">{user['goal']}</div></div>
            <div class="profile-item"><div class="profile-label">Experience</div><div class="profile-value">{user['experience']}</div></div>
            <div class="profile-item"><div class="profile-label">Location</div><div class="profile-value">{user['location'].upper()}</div></div>
            <div class="profile-item"><div class="profile-label">Injury</div><div class="profile-value">{user['injury'] or 'None'}</div></div>
            <div class="profile-item"><div class="profile-label">Equipment</div><div class="profile-value">{', '.join(EQUIPMENT_SETS.get(user['equipment_set'], ['bodyweight'])).title()}</div></div>
            <div class="profile-item"><div class="profile-label">Workout Type</div><div class="profile-value">{user['workout_type']}</div></div>
            <div class="profile-item"><div class="profile-label">Exercises Available</div><div class="profile-value">{result['filtered_count']}</div></div>
        </div>
        
        <h4>Generated Workout ({len(workout)} exercises)</h4>
        <table class="workout-table">
            <tr><th>#</th><th>Exercise</th><th>Family</th><th>Equipment</th><th>Difficulty</th><th>Muscles</th></tr>
"""
        
        for idx, ex in enumerate(workout, 1):
            muscles = ex.get('primary_muscles', [])
            if isinstance(muscles, str):
                import ast
                try: muscles = ast.literal_eval(muscles)
                except: muscles = []
            muscles_str = ', '.join(muscles) if muscles else 'N/A'
            
            html += f"""
            <tr>
                <td>{idx}</td>
                <td>{ex.get('name', 'Unknown')}</td>
                <td>{ex.get('exercise_family', 'N/A')}</td>
                <td>{ex.get('equipment_category', 'N/A')}</td>
                <td>Level {ex.get('difficulty_level', '?')}</td>
                <td>{muscles_str}</td>
            </tr>
"""
        
        html += """
        </table>
        
        <h4>Validation Scores</h4>
        <div class="validation-grid">
"""
        
        for cat in categories:
            score = validations[cat]['score']
            score_class = 'score-good' if score >= 85 else ('score-ok' if score >= 70 else 'score-bad')
            detail = validations[cat]['details'][0] if validations[cat]['details'] else ''
            html += f"""
            <div class="validation-item">
                <div class="validation-score {score_class}">{score}%</div>
                <div>{cat.replace('_', ' ').title()}</div>
                <div style="font-size: 11px; color: #7f8c8d;">{detail}</div>
            </div>
"""
        
        html += """
        </div>
    </div>
"""
    
    html += f"""
    <div class="timestamp">Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}</div>
</div>
</body>
</html>
"""
    
    return html

# ============================================================================
# MAIN
# ============================================================================

if __name__ == '__main__':
    print("=" * 70)
    print("🏋️ COMPREHENSIVE 100-USER WORKOUT GENERATION TEST")
    print("=" * 70)
    print()
    
    print("📥 Fetching exercises from database...")
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
    
    print("🔄 Generating 100 test users and workouts...")
    results = []
    
    for i in range(1, 101):
        user = generate_user(i)
        filtered = filter_exercises(all_exercises, user)
        workout = generate_workout(filtered, user, 6)
        validations = validate_workout(workout, user, filtered)
        overall_score = calculate_overall_score(validations)
        grade = get_grade(overall_score)
        
        results.append({
            'user': user,
            'filtered_count': len(filtered),
            'workout': workout,
            'validations': validations,
            'overall_score': overall_score,
            'grade': grade
        })
        
        if i % 20 == 0:
            print(f"   Processed {i}/100 users...")
    
    print("✅ All users processed!")
    print()
    
    grades = Counter(r['grade'] for r in results)
    avg_score = sum(r['overall_score'] for r in results) / len(results)
    
    print("=" * 70)
    print("📊 SUMMARY STATISTICS")
    print("=" * 70)
    print(f"Average Score: {avg_score:.1f}%")
    print(f"Grade Distribution:")
    for grade in ['A+', 'A', 'B+', 'B', 'C+', 'C', 'D', 'F']:
        count = grades.get(grade, 0)
        bar = '█' * count
        print(f"   {grade}: {count:3d} {bar}")
    
    categories = ['equipment_match', 'equipment_diversity', 'difficulty_appropriate', 
                  'injury_safe', 'workout_type_match', 'movement_diversity', 
                  'position_diversity', 'compound_ordering', 'family_diversity']
    
    print()
    print("Validation Category Averages:")
    for cat in categories:
        avg = sum(r['validations'][cat]['score'] for r in results) / len(results)
        print(f"   {cat.replace('_', ' ').title()}: {avg:.1f}%")
    
    # Select sample users
    sample_users = []
    sample_users.extend(sorted(results, key=lambda x: -x['overall_score'])[:5])
    sample_users.extend(sorted(results, key=lambda x: x['overall_score'])[:5])
    middle = [r for r in results if r not in sample_users]
    random.shuffle(middle)
    sample_users.extend(middle[:10])
    
    # Generate reports
    print()
    print("=" * 70)
    print("📝 GENERATING REPORTS")
    print("=" * 70)
    
    html_content = generate_html_report(results, all_exercises, sample_users, grades, avg_score)
    
    report_path = '/Users/josephreed/Desktop/Workout App/100_user_audit_report.html'
    with open(report_path, 'w') as f:
        f.write(html_content)
    print(f"✅ HTML Report saved: {report_path}")
    
    json_path = '/Users/josephreed/Desktop/Workout App/100_user_audit_results.json'
    json_results = {
        'summary': {
            'total_users': 100,
            'average_score': avg_score,
            'grade_distribution': dict(grades),
            'validation_averages': {cat: sum(r['validations'][cat]['score'] for r in results) / len(results) for cat in categories}
        },
        'sample_users': [{
            'user': r['user'],
            'filtered_count': r['filtered_count'],
            'workout': [{'name': ex.get('name'), 'family': ex.get('exercise_family'), 
                        'equipment': ex.get('equipment_category'), 'difficulty': ex.get('difficulty_level'),
                        'muscles': ex.get('primary_muscles')} for ex in r['workout']],
            'validations': r['validations'],
            'overall_score': r['overall_score'],
            'grade': r['grade']
        } for r in sample_users]
    }
    
    with open(json_path, 'w') as f:
        json.dump(json_results, f, indent=2)
    print(f"✅ JSON Results saved: {json_path}")
    
    print()
    print("=" * 70)
    print("✅ AUDIT COMPLETE!")
    print("=" * 70)
    print(f"""
📊 Results Summary:
   • Average Score: {avg_score:.1f}%
   • A+ grades: {grades.get('A+', 0)}
   • A grades: {grades.get('A', 0)}
   • B+ grades: {grades.get('B+', 0)}
   • B grades: {grades.get('B', 0)}
   • C or below: {grades.get('C+', 0) + grades.get('C', 0) + grades.get('D', 0) + grades.get('F', 0)}

📁 Reports Generated:
   • HTML: {report_path}
   • JSON: {json_path}
   
💡 To convert HTML to PDF:
   Open the HTML file in Chrome/Safari and use Print > Save as PDF
""")
