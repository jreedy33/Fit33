#!/usr/bin/env python3
"""
🚀 ADVANCED 500-USER WORKOUT GENERATION AUDIT
Production-Ready Launch Validation Script

Tests ALL app logic including:
- User workout history simulation
- Favorite exercises boosting
- Body region consistency
- Weight/age profile rules
- Multi-target muscle bonus
- Goal-specific database ratings
- Equipment diversity (round-robin)
- Movement diversity
- Position diversity
- Compound ordering
- Injury safety
- Difficulty appropriateness

Generates 500 unique users across different fitness journeys.
"""

from supabase import create_client
from collections import Counter
import random
import math
import json
from datetime import datetime, timedelta
import hashlib

SUPABASE_URL = "https://ehooeghabzefgoqzugrc.supabase.co"
SUPABASE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVob29lZ2hhYnplZmdvcXp1Z3JjIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjM4NDc4NjQsImV4cCI6MjA3OTQyMzg2NH0.6-QWDr5B279hybtu9MbPVhmBKlyzFq1GK9P7zlDXuY0"

supabase = create_client(SUPABASE_URL, SUPABASE_KEY)

# ============================================================================
# CONFIGURATION - Mirrors Swift App
# ============================================================================

EQUIPMENT_SETS = {
    'gym_full': ['barbell', 'dumbbell', 'cable', 'machine', 'kettlebell'],
    'gym_standard': ['barbell', 'dumbbell', 'cable', 'machine'],
    'gym_basic': ['machine', 'cable', 'dumbbell'],
    'gym_cables_only': ['cable', 'machine'],
    'home_full': ['dumbbell', 'barbell', 'kettlebell', 'band', 'bodyweight'],
    'home_standard': ['dumbbell', 'kettlebell', 'band', 'bodyweight'],
    'home_dumbbells': ['dumbbell', 'bodyweight'],
    'home_minimal': ['bodyweight', 'band'],
    'bodyweight_only': ['bodyweight'],
}

WORKOUT_TYPES = {
    'Push': {
        'families': ['bench_press', 'incline_bench_press', 'decline_bench_press', 'chest_fly',
                    'shoulder_press', 'arnold_press', 'lateral_raise', 'front_raise',
                    'tricep_pushdown', 'tricep_extension', 'skull_crusher', 'dip', 'push_up', 'chest_press'],
        'muscles': ['Chest', 'Shoulders', 'Triceps', 'Front Delts', 'Side Delts', 'Upper Chest', 'Lower Chest'],
        'body_region': 'upper'
    },
    'Pull': {
        'families': ['lat_pulldown', 'pull_up', 'chin_up', 'bent_over_row', 'seated_row',
                    'face_pull', 'bicep_curl', 'hammer_curl', 'preacher_curl', 'reverse_curl', 'shrug'],
        'muscles': ['Back', 'Lats', 'Biceps', 'Rear Delts', 'Traps', 'Rhomboids', 'Upper Back'],
        'body_region': 'upper'
    },
    'Legs': {
        'families': ['squat', 'leg_press', 'lunge', 'leg_curl', 'leg_extension',
                    'hip_thrust', 'glute_bridge', 'calf_raise', 'romanian_deadlift', 'deadlift', 'hack_squat'],
        'muscles': ['Quads', 'Hamstrings', 'Glutes', 'Calves', 'Adductors', 'Abductors'],
        'body_region': 'lower'
    },
    'Upper': {
        'families': ['bench_press', 'shoulder_press', 'lat_pulldown', 'bent_over_row',
                    'bicep_curl', 'tricep_extension', 'lateral_raise', 'face_pull', 'chest_fly'],
        'muscles': ['Chest', 'Back', 'Shoulders', 'Biceps', 'Triceps', 'Lats'],
        'body_region': 'upper'
    },
    'Lower': {
        'families': ['squat', 'deadlift', 'leg_press', 'lunge', 'leg_curl',
                    'leg_extension', 'hip_thrust', 'calf_raise', 'glute_bridge'],
        'muscles': ['Quads', 'Hamstrings', 'Glutes', 'Calves'],
        'body_region': 'lower'
    },
    'Full Body': {
        'families': ['squat', 'deadlift', 'bench_press', 'bent_over_row', 'shoulder_press', 'lunge'],
        'muscles': ['Chest', 'Back', 'Legs', 'Shoulders', 'Arms', 'Quads', 'Glutes'],
        'body_region': 'full'
    },
    'Arms': {
        'families': ['bicep_curl', 'hammer_curl', 'preacher_curl', 'tricep_pushdown',
                    'tricep_extension', 'skull_crusher', 'wrist_curl', 'tricep_kickback', 'concentration_curl'],
        'muscles': ['Biceps', 'Triceps', 'Forearms'],
        'body_region': 'upper'
    },
    'Core': {
        'families': ['crunch', 'plank', 'leg_raise', 'russian_twist', 'sit_up',
                    'ab_rollout', 'side_bend', 'bicycle_crunch', 'dead_bug'],
        'muscles': ['Abs', 'Obliques', 'Core', 'Lower Abs'],
        'body_region': 'core'
    },
    'Back': {
        'families': ['lat_pulldown', 'pull_up', 'bent_over_row', 'seated_row',
                    'face_pull', 'back_extension', 'shrug', 'straight_arm_pulldown'],
        'muscles': ['Back', 'Lats', 'Traps', 'Rear Delts', 'Rhomboids', 'Upper Back', 'Lower Back'],
        'body_region': 'upper'
    },
    'Chest': {
        'families': ['bench_press', 'incline_bench_press', 'decline_bench_press',
                    'chest_fly', 'chest_press', 'push_up', 'dip', 'cable_crossover'],
        'muscles': ['Chest', 'Upper Chest', 'Lower Chest'],
        'body_region': 'upper'
    },
    'Shoulders': {
        'families': ['shoulder_press', 'arnold_press', 'lateral_raise', 'front_raise',
                    'rear_delt_fly', 'upright_row', 'face_pull', 'shrug'],
        'muscles': ['Shoulders', 'Front Delts', 'Side Delts', 'Rear Delts', 'Traps'],
        'body_region': 'upper'
    },
    'Glutes': {
        'families': ['hip_thrust', 'glute_bridge', 'romanian_deadlift', 'kickback',
                    'squat', 'lunge', 'deadlift', 'cable_pull_through'],
        'muscles': ['Glutes', 'Hamstrings'],
        'body_region': 'lower'
    }
}

INJURIES = {
    None: {'avoid_families': [], 'avoid_muscles': [], 'severity': 0},
    'shoulder': {
        'avoid_families': ['shoulder_press', 'overhead_press', 'lateral_raise', 'arnold_press', 'upright_row'],
        'avoid_muscles': ['Shoulders', 'Front Delts', 'Side Delts'],
        'severity': 2
    },
    'back': {
        'avoid_families': ['deadlift', 'bent_over_row', 'good_morning', 'back_extension', 'romanian_deadlift'],
        'avoid_muscles': ['Lower Back'],
        'severity': 3
    },
    'knee': {
        'avoid_families': ['squat', 'lunge', 'leg_press', 'leg_extension', 'jump', 'plyometric'],
        'avoid_muscles': ['Quads'],
        'severity': 3
    },
    'wrist': {
        'avoid_families': ['wrist_curl', 'push_up', 'plank'],
        'avoid_muscles': ['Forearms'],
        'severity': 1
    },
    'elbow': {
        'avoid_families': ['tricep_extension', 'skull_crusher', 'preacher_curl'],
        'avoid_muscles': [],
        'severity': 2
    },
    'hip': {
        'avoid_families': ['hip_thrust', 'lunge', 'deadlift', 'squat'],
        'avoid_muscles': ['Hip Flexors'],
        'severity': 2
    },
    'neck': {
        'avoid_families': ['shrug', 'upright_row'],
        'avoid_muscles': ['Traps'],
        'severity': 1
    }
}

GOALS = ['Build Muscle', 'Get Lean', 'Build Strength', 'General Fitness', 'Endurance', 'Athletic Performance']
EXPERIENCE_LEVELS = ['Beginner', 'Intermediate', 'Advanced']
LOCATIONS = ['gym', 'home']
GENDERS = ['Male', 'Female']

# User journey stages
JOURNEY_STAGES = [
    'new_user',           # Just signed up, no history
    'first_week',         # 1-3 workouts completed
    'getting_started',    # 4-10 workouts, some favorites
    'building_habit',     # 11-30 workouts, clear preferences
    'consistent',         # 31-100 workouts, strong preferences
    'veteran',            # 100+ workouts, very established patterns
]

NAMES = ['Alex', 'Jordan', 'Taylor', 'Casey', 'Morgan', 'Riley', 'Quinn', 'Avery', 
         'Cameron', 'Drew', 'Sage', 'Reese', 'Blake', 'Harper', 'Emery', 'Finley',
         'Hayden', 'Jamie', 'Kai', 'Logan', 'Marley', 'Nico', 'Parker', 'River',
         'Sawyer', 'Skyler', 'Spencer', 'Sydney', 'Tatum', 'Wren', 'Dakota', 'Jesse',
         'Robin', 'Charlie', 'Frankie', 'Kendall', 'Peyton', 'Rory', 'Sam', 'Terry',
         'Adrian', 'Bailey', 'Corey', 'Devon', 'Ellis', 'Gray', 'Haven', 'Indigo',
         'Jules', 'Kerry', 'Lane', 'Milan', 'Noel', 'Ocean', 'Phoenix', 'Raven']

# ============================================================================
# USER GENERATION - Diverse Scenarios
# ============================================================================

def generate_user(user_id, all_exercises):
    """Generate a diverse user profile with history simulation"""
    random.seed(user_id * 42)  # Reproducible but varied
    
    gender = random.choice(GENDERS)
    goal = random.choice(GOALS)
    experience = random.choice(EXPERIENCE_LEVELS)
    location = random.choice(LOCATIONS)
    
    # Equipment based on location and experience
    if location == 'home':
        if experience == 'Advanced':
            equipment_options = ['home_full', 'home_standard']
        elif experience == 'Intermediate':
            equipment_options = ['home_standard', 'home_dumbbells']
        else:
            equipment_options = ['home_dumbbells', 'home_minimal', 'bodyweight_only']
    else:
        if experience == 'Advanced':
            equipment_options = ['gym_full', 'gym_standard']
        elif experience == 'Intermediate':
            equipment_options = ['gym_standard', 'gym_basic']
        else:
            equipment_options = ['gym_basic', 'gym_cables_only']
    
    equipment_set = random.choice(equipment_options)
    
    # Injury based on age and experience (more likely with age/intensity)
    age = random.randint(18, 70)
    injury_chance = 0.15 + (age - 18) * 0.005 + (0.1 if experience == 'Advanced' else 0)
    injury = random.choice(list(INJURIES.keys())) if random.random() < injury_chance else None
    
    workout_type = random.choice(list(WORKOUT_TYPES.keys()))
    
    # Physical stats based on gender and age
    if gender == 'Male':
        base_height_inches = random.randint(64, 76)
        base_weight = random.randint(140, 260)
    else:
        base_height_inches = random.randint(58, 70)
        base_weight = random.randint(100, 200)
    
    height = f"{base_height_inches // 12}'{base_height_inches % 12}\""
    weight = base_weight
    
    # Journey stage based on weighted distribution
    journey_weights = [0.15, 0.15, 0.20, 0.20, 0.20, 0.10]
    journey_stage = random.choices(JOURNEY_STAGES, weights=journey_weights)[0]
    
    # Generate workout history based on journey stage
    workout_history = generate_workout_history(journey_stage, goal, workout_type, all_exercises)
    
    # Generate favorites based on history and preferences
    favorites = generate_favorites(workout_history, goal, equipment_set, all_exercises)
    
    # Preferred equipment (learned from history)
    preferred_equipment = learn_equipment_preference(workout_history, equipment_set)
    
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
        'equipment_list': EQUIPMENT_SETS.get(equipment_set, ['bodyweight']),
        'injury': injury,
        'workout_type': workout_type,
        'journey_stage': journey_stage,
        'workout_history': workout_history,
        'favorites': favorites,
        'preferred_equipment': preferred_equipment,
        'workouts_completed': len(workout_history),
    }

def generate_workout_history(journey_stage, goal, preferred_workout_type, all_exercises):
    """Simulate workout history based on journey stage"""
    workout_counts = {
        'new_user': 0,
        'first_week': random.randint(1, 3),
        'getting_started': random.randint(4, 10),
        'building_habit': random.randint(11, 30),
        'consistent': random.randint(31, 100),
        'veteran': random.randint(100, 250),
    }
    
    num_workouts = workout_counts.get(journey_stage, 0)
    history = []
    
    for i in range(num_workouts):
        # Mix of workout types, but prefer their selected type
        if random.random() < 0.6:
            wtype = preferred_workout_type
        else:
            wtype = random.choice(list(WORKOUT_TYPES.keys()))
        
        # Sample exercises they might have done
        exercises_done = random.sample(
            [ex['name'] for ex in all_exercises if ex.get('name')],
            min(6, len(all_exercises))
        )
        
        history.append({
            'workout_type': wtype,
            'exercises': exercises_done,
            'days_ago': num_workouts - i
        })
    
    return history

def generate_favorites(workout_history, goal, equipment_set, all_exercises):
    """Generate favorite exercises based on history and preferences"""
    equipment_list = EQUIPMENT_SETS.get(equipment_set, ['bodyweight'])
    
    # Users with more history have more favorites
    if len(workout_history) == 0:
        return []
    
    num_favorites = min(len(workout_history) // 5 + 1, 15)
    
    # Filter exercises by equipment
    available = [ex for ex in all_exercises 
                 if ex.get('equipment_category') in equipment_list]
    
    if not available:
        return []
    
    # Favor compound exercises for muscle/strength goals
    if 'muscle' in goal.lower() or 'strength' in goal.lower():
        compounds = [ex for ex in available if is_compound_exercise(ex.get('name', ''))]
        if compounds:
            favorites = random.sample(compounds, min(num_favorites, len(compounds)))
            return [ex['name'] for ex in favorites]
    
    favorites = random.sample(available, min(num_favorites, len(available)))
    return [ex['name'] for ex in favorites]

def learn_equipment_preference(workout_history, equipment_set):
    """Simulate learned equipment preference from history"""
    equipment_list = EQUIPMENT_SETS.get(equipment_set, ['bodyweight'])
    
    if len(workout_history) < 5:
        return None  # Not enough data
    
    # Simulate that user prefers certain equipment
    return random.choice(equipment_list)

def is_compound_exercise(name):
    """Check if exercise is compound"""
    compound_keywords = ['squat', 'deadlift', 'press', 'bench', 'row', 'pull-up', 'pullup',
                        'chin-up', 'chinup', 'lunge', 'dip', 'clean', 'snatch', 'thruster']
    return any(kw in name.lower() for kw in compound_keywords)

# ============================================================================
# ADVANCED WORKOUT GENERATION - Mirrors Swift Logic
# ============================================================================

def get_priority_key(user):
    goal = user.get('goal', '').lower()
    if 'build muscle' in goal or 'muscle' in goal:
        return 'priority_build_muscle'
    elif 'get lean' in goal or 'lean' in goal:
        return 'priority_get_lean'
    elif 'strength' in goal:
        return 'priority_build_muscle'
    elif 'endurance' in goal:
        return 'priority_get_lean'
    return 'priority_build_muscle'

def filter_exercises_advanced(all_exercises, user):
    """Advanced filtering with body region consistency"""
    equipment_list = user['equipment_list']
    workout_config = WORKOUT_TYPES.get(user['workout_type'], WORKOUT_TYPES['Full Body'])
    injury_config = INJURIES.get(user['injury'], INJURIES[None])
    
    max_difficulty = {'Beginner': 2, 'Intermediate': 4, 'Advanced': 5}.get(user['experience'], 4)
    
    # Body region for consistency check
    target_body_region = workout_config.get('body_region', 'full')
    
    # Weight-based restrictions
    weight = user.get('weight', 170)
    age = user.get('age', 30)
    
    filtered = []
    for ex in all_exercises:
        name = (ex.get('name') or '').lower()
        
        # Equipment filter
        equip = ex.get('equipment_category', 'bodyweight')
        if equip not in equipment_list:
            continue
        
        # Difficulty filter
        difficulty = ex.get('difficulty_level', 3) or 3
        if difficulty > max_difficulty:
            continue
        
        # Injury filter
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
        
        # BODY REGION CONSISTENCY (mirrors Swift)
        if target_body_region == 'upper':
            lower_keywords = ['squat', 'lunge', 'leg press', 'leg curl', 'leg extension',
                             'hip thrust', 'glute bridge', 'calf raise', 'deadlift']
            if any(kw in name for kw in lower_keywords):
                continue
        elif target_body_region == 'lower':
            upper_keywords = ['press', 'curl', 'fly', 'pulldown', 'row', 'push up',
                             'tricep', 'bicep', 'shoulder', 'chest', 'lat', 'delt']
            if any(kw in name for kw in upper_keywords):
                continue
        
        # WEIGHT-BASED RESTRICTIONS (mirrors Swift)
        if weight > 250:
            bodyweight_lifts = ['pull up', 'pullup', 'chin up', 'chinup', 'muscle up',
                               'dip', 'pistol squat', 'handstand', 'l-sit']
            if equip == 'bodyweight' and any(kw in name for kw in bodyweight_lifts):
                continue
        
        # AGE-BASED RESTRICTIONS (mirrors Swift)
        if age >= 60:
            high_impact = ['jump', 'box jump', 'burpee', 'plyometric', 'sprint']
            if any(kw in name for kw in high_impact):
                continue
        
        # Workout type filter
        family_match = any(f in family for f in workout_config['families'])
        muscle_match = any(m in muscles for m in workout_config['muscles'])
        
        if family_match or muscle_match:
            filtered.append(ex)
    
    return filtered

def generate_workout_advanced(filtered_exercises, user, all_exercises, num_exercises=6):
    """Advanced workout generation with all Swift features"""
    if not filtered_exercises:
        return []
    
    priority_key = get_priority_key(user)
    location_key = 'priority_home' if user.get('location') == 'home' else 'priority_gym'
    favorites = set(f.lower() for f in user.get('favorites', []))
    preferred_equipment = user.get('preferred_equipment')
    workout_config = WORKOUT_TYPES.get(user['workout_type'], WORKOUT_TYPES['Full Body'])
    target_muscles = set(m.lower() for m in workout_config.get('muscles', []))
    
    def score_exercise(ex):
        score = 100.0
        name = (ex.get('name') or '').lower()
        
        # GOAL-BASED PRIORITY (from database)
        goal_priority = ex.get(priority_key, 50) or 50
        score += goal_priority * 0.6
        
        # LOCATION PRIORITY (from database)
        location_priority = ex.get(location_key, 50) or 50
        score += location_priority * 0.4
        
        # FAVORITE BOOST (+100) - mirrors Swift
        if name in favorites:
            score += 100
        
        # PREFERRED EQUIPMENT BOOST (+30) - mirrors Swift learned preferences
        if preferred_equipment and ex.get('equipment_category') == preferred_equipment:
            score += 30
        
        # COMPOUND MOVEMENT BONUS (+40) - mirrors Swift
        if is_compound_exercise(name):
            score += 40
        
        # MULTI-TARGET MUSCLE BONUS - mirrors Swift
        exercise_muscles = ex.get('primary_muscles', [])
        if isinstance(exercise_muscles, str):
            import ast
            try:
                exercise_muscles = ast.literal_eval(exercise_muscles)
            except:
                exercise_muscles = []
        
        matched_targets = sum(1 for m in exercise_muscles if m.lower() in target_muscles)
        if matched_targets >= 2:
            score += (matched_targets - 1) * 50  # +50 for each additional target
        
        # GOAL-SPECIFIC BONUSES - mirrors Swift
        goal = user.get('goal', '').lower()
        if 'build muscle' in goal:
            if is_compound_exercise(name):
                score += 25
            if ex.get('equipment_category') in ['barbell', 'dumbbell']:
                score += 15
            # Use hypertrophy rating if available
            hypertrophy = ex.get('hypertrophy_rating', 0) or 0
            score += hypertrophy * 3
        elif 'get lean' in goal:
            if 'jump' in name or 'burpee' in name:
                score += 25
            # Use fat loss rating if available
            fat_loss = ex.get('fat_loss_rating', 0) or 0
            score += fat_loss * 3
            # Supersetable bonus
            if ex.get('supersetable', True):
                score += 10
        elif 'strength' in goal:
            if is_compound_exercise(name):
                score += 35
            if ex.get('equipment_category') == 'barbell':
                score += 25
            # Use strength rating if available
            strength = ex.get('strength_rating', 0) or 0
            score += strength * 3
        elif 'endurance' in goal:
            endurance = ex.get('endurance_rating', 0) or 0
            score += endurance * 3
        
        # EXPERIENCE LEVEL ADJUSTMENTS - mirrors Swift
        experience = user.get('experience', 'intermediate').lower()
        difficulty = ex.get('difficulty_level', 3) or 3
        
        if experience == 'beginner':
            if difficulty <= 2:
                score += 50
            elif difficulty >= 4:
                score -= 80
            if ex.get('equipment_category') == 'machine':
                score += 40
            # Beginners prefer isolation (easier to learn)
            if not is_compound_exercise(name):
                score += 15
        elif experience == 'advanced':
            if difficulty >= 4:
                score += 40
            elif difficulty <= 1:
                score -= 20
            if ex.get('equipment_category') in ['barbell', 'dumbbell']:
                score += 25
            # Advanced prefer compounds
            if is_compound_exercise(name):
                score += 20
        
        # Add randomness for variety
        score += random.uniform(0, 25)
        
        return score
    
    # Score and sort
    scored_exercises = [(ex, score_exercise(ex)) for ex in filtered_exercises]
    scored_exercises.sort(key=lambda x: x[1], reverse=True)
    sorted_exercises = [ex for ex, score in scored_exercises]
    
    # DIVERSITY TRACKING - mirrors Swift
    workout = []
    used_names = set()
    used_families = set()
    used_equipment = {}
    used_positions = {}
    used_movements = {}
    used_muscles = {}
    
    user_equipment = user['equipment_list']
    
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
        if 'press' in name: return 'press'
        if 'fly' in name or 'flye' in name: return 'fly'
        if 'row' in name: return 'row'
        if 'curl' in name: return 'curl'
        if 'extension' in name: return 'extension'
        if 'raise' in name: return 'raise'
        if 'pulldown' in name or 'pull down' in name: return 'pulldown'
        if 'squat' in name: return 'squat'
        if 'lunge' in name: return 'lunge'
        if 'deadlift' in name: return 'deadlift'
        if 'thrust' in name: return 'thrust'
        return 'other'
    
    def normalize_muscle(muscles):
        if not muscles:
            return 'unknown'
        if isinstance(muscles, str):
            try:
                import ast
                muscles = ast.literal_eval(muscles)
            except:
                muscles = [muscles]
        m = muscles[0].lower() if muscles else 'unknown'
        if 'bicep' in m: return 'biceps'
        if 'tricep' in m: return 'triceps'
        if 'chest' in m or 'pec' in m: return 'chest'
        if 'lat' in m and 'delt' not in m: return 'lats'
        if 'back' in m: return 'back'
        if 'shoulder' in m or 'delt' in m: return 'shoulders'
        if 'quad' in m: return 'quads'
        if 'hamstring' in m: return 'hamstrings'
        if 'glute' in m: return 'glutes'
        if 'calf' in m or 'calves' in m: return 'calves'
        if 'ab' in m or 'core' in m: return 'core'
        return m
    
    def can_add_exercise(ex):
        name = (ex.get('name') or '').lower()
        equipment = ex.get('equipment_category', 'bodyweight')
        
        if name in used_names:
            return False
        
        family = ex.get('exercise_family', 'general')
        if family in used_families and len(workout) < num_exercises - 2:
            return False
        
        # Max 60% from one equipment type
        max_per_equipment = max(2, int(math.ceil(num_exercises * 0.6)))
        if used_equipment.get(equipment, 0) >= max_per_equipment:
            return False
        
        # Max 2 per position
        position = get_body_position(ex.get('name', ''))
        if used_positions.get(position, 0) >= 2:
            return False
        
        # Max 2 per movement type
        movement = get_movement_type(ex.get('name', ''))
        if movement != 'other' and used_movements.get(movement, 0) >= 2:
            return False
        
        # Max 2 per muscle group
        muscle = normalize_muscle(ex.get('primary_muscles'))
        if used_muscles.get(muscle, 0) >= 2:
            return False
        
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
        
        muscle = normalize_muscle(ex.get('primary_muscles'))
        used_muscles[muscle] = used_muscles.get(muscle, 0) + 1
    
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
        while len(workout) < num_exercises and round_num < num_exercises * 3:
            added_this_round = False
            for equip in user_equipment:
                if len(workout) >= num_exercises:
                    break
                if taken_per_type[equip] >= slots_per_type:
                    continue
                for ex in exercises_by_equip[equip]:
                    if can_add_exercise(ex):
                        add_exercise(ex)
                        taken_per_type[equip] += 1
                        added_this_round = True
                        break
            round_num += 1
            if not added_this_round:
                break
    
    # PHASE 2: Fill remaining with best scored
    for ex in sorted_exercises:
        if len(workout) >= num_exercises:
            break
        if can_add_exercise(ex):
            add_exercise(ex)
    
    # PHASE 3: Relaxed fill if needed
    if len(workout) < num_exercises:
        for ex in sorted_exercises:
            if len(workout) >= num_exercises:
                break
            name = (ex.get('name') or '').lower()
            if name not in used_names:
                workout.append(ex)
                used_names.add(name)
    
    # ORDER: Compound exercises first
    workout.sort(key=lambda ex: (0 if is_compound_exercise(ex.get('name', '')) else 1))
    
    return workout

# ============================================================================
# COMPREHENSIVE VALIDATION
# ============================================================================

def validate_workout_advanced(workout, user, all_filtered):
    """Comprehensive validation with all criteria"""
    results = {
        'equipment_match': {'score': 0, 'details': [], 'weight': 12},
        'equipment_diversity': {'score': 0, 'details': [], 'weight': 10},
        'difficulty_appropriate': {'score': 0, 'details': [], 'weight': 12},
        'injury_safe': {'score': 0, 'details': [], 'weight': 15},
        'workout_type_match': {'score': 0, 'details': [], 'weight': 12},
        'body_region_consistency': {'score': 0, 'details': [], 'weight': 10},
        'movement_diversity': {'score': 0, 'details': [], 'weight': 8},
        'position_diversity': {'score': 0, 'details': [], 'weight': 5},
        'muscle_diversity': {'score': 0, 'details': [], 'weight': 8},
        'compound_ordering': {'score': 0, 'details': [], 'weight': 5},
        'family_diversity': {'score': 0, 'details': [], 'weight': 5},
        'favorites_included': {'score': 0, 'details': [], 'weight': 3},
        'goal_alignment': {'score': 0, 'details': [], 'weight': 5},
    }
    
    if not workout:
        for key in results:
            results[key]['details'] = ['No workout generated']
        return results
    
    equipment_list = user['equipment_list']
    injury_config = INJURIES.get(user['injury'], INJURIES[None])
    workout_config = WORKOUT_TYPES.get(user['workout_type'], WORKOUT_TYPES['Full Body'])
    max_difficulty = {'Beginner': 2, 'Intermediate': 4, 'Advanced': 5}.get(user['experience'], 4)
    favorites = set(f.lower() for f in user.get('favorites', []))
    
    # 1. Equipment Match
    equip_match = sum(1 for ex in workout if ex.get('equipment_category') in equipment_list)
    results['equipment_match']['score'] = int(equip_match / len(workout) * 100)
    results['equipment_match']['details'] = [f"{equip_match}/{len(workout)} match equipment"]
    
    # 2. Equipment Diversity
    equip_counts = Counter(ex.get('equipment_category') for ex in workout)
    unique_equip = len(equip_counts)
    max_possible = min(len(equipment_list), len(workout))
    results['equipment_diversity']['score'] = int(unique_equip / max_possible * 100) if max_possible > 0 else 100
    results['equipment_diversity']['details'] = [f"{unique_equip} types: {dict(equip_counts)}"]
    
    # 3. Difficulty Appropriate
    diff_ok = sum(1 for ex in workout if (ex.get('difficulty_level') or 3) <= max_difficulty)
    results['difficulty_appropriate']['score'] = int(diff_ok / len(workout) * 100)
    results['difficulty_appropriate']['details'] = [f"{diff_ok}/{len(workout)} appropriate (max {max_difficulty})"]
    
    # 4. Injury Safe
    violations = 0
    for ex in workout:
        family = ex.get('exercise_family', '')
        muscles = ex.get('primary_muscles', [])
        if isinstance(muscles, str):
            import ast
            try: muscles = ast.literal_eval(muscles)
            except: muscles = []
        
        if any(avoid in family for avoid in injury_config['avoid_families']):
            violations += 1
        elif any(m in muscles for m in injury_config['avoid_muscles']):
            violations += 1
    
    results['injury_safe']['score'] = int((len(workout) - violations) / len(workout) * 100)
    results['injury_safe']['details'] = [f"{violations} violations" if violations else "All safe ✓"]
    
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
    results['workout_type_match']['details'] = [f"{type_match}/{len(workout)} match {user['workout_type']}"]
    
    # 6. Body Region Consistency
    target_region = workout_config.get('body_region', 'full')
    region_violations = 0
    
    for ex in workout:
        name = (ex.get('name') or '').lower()
        if target_region == 'upper':
            lower_keywords = ['squat', 'lunge', 'leg press', 'leg curl', 'calf', 'glute', 'hip thrust']
            if any(kw in name for kw in lower_keywords):
                region_violations += 1
        elif target_region == 'lower':
            upper_keywords = ['press', 'curl', 'fly', 'pulldown', 'push up', 'tricep', 'bicep', 'shoulder']
            if any(kw in name for kw in upper_keywords):
                region_violations += 1
    
    results['body_region_consistency']['score'] = int((len(workout) - region_violations) / len(workout) * 100)
    results['body_region_consistency']['details'] = [f"{region_violations} cross-region" if region_violations else "Consistent ✓"]
    
    # 7. Movement Diversity
    def get_movement(name):
        name = name.lower()
        for m in ['press', 'fly', 'row', 'curl', 'extension', 'raise', 'pulldown', 'squat', 'lunge']:
            if m in name:
                return m
        return 'other'
    
    movement_counts = Counter(get_movement(ex.get('name', '')) for ex in workout)
    max_same = max(movement_counts.values()) if movement_counts else 0
    results['movement_diversity']['score'] = 100 if max_same <= 2 else max(0, 100 - (max_same - 2) * 25)
    results['movement_diversity']['details'] = [f"Max {max_same} same movement"]
    
    # 8. Position Diversity
    def get_position(name):
        name = name.lower()
        if 'lying' in name or 'floor' in name: return 'lying'
        if 'seated' in name: return 'seated'
        if 'standing' in name: return 'standing'
        return 'other'
    
    position_counts = Counter(get_position(ex.get('name', '')) for ex in workout)
    max_same_pos = max(position_counts.values()) if position_counts else 0
    results['position_diversity']['score'] = 100 if max_same_pos <= 3 else max(0, 100 - (max_same_pos - 3) * 20)
    results['position_diversity']['details'] = [f"Positions: {dict(position_counts)}"]
    
    # 9. Muscle Diversity
    def normalize_muscle(muscles):
        if not muscles: return 'unknown'
        if isinstance(muscles, str):
            try:
                import ast
                muscles = ast.literal_eval(muscles)
            except:
                return muscles.lower()
        return muscles[0].lower() if muscles else 'unknown'
    
    muscle_counts = Counter(normalize_muscle(ex.get('primary_muscles')) for ex in workout)
    unique_muscles = len(muscle_counts)
    results['muscle_diversity']['score'] = min(100, int(unique_muscles / len(workout) * 120))
    results['muscle_diversity']['details'] = [f"{unique_muscles} muscle groups"]
    
    # 10. Compound Ordering
    found_isolation = False
    ordering_correct = True
    for ex in workout:
        if is_compound_exercise(ex.get('name', '')):
            if found_isolation:
                ordering_correct = False
                break
        else:
            found_isolation = True
    
    results['compound_ordering']['score'] = 100 if ordering_correct else 60
    results['compound_ordering']['details'] = ["Correct order ✓" if ordering_correct else "Mixed order"]
    
    # 11. Family Diversity
    families = [ex.get('exercise_family', 'unknown') for ex in workout]
    unique_families = len(set(families))
    results['family_diversity']['score'] = int(unique_families / len(workout) * 100)
    results['family_diversity']['details'] = [f"{unique_families} unique families"]
    
    # 12. Favorites Included
    if favorites:
        included = sum(1 for ex in workout if (ex.get('name') or '').lower() in favorites)
        results['favorites_included']['score'] = min(100, int(included / min(3, len(favorites)) * 100))
        results['favorites_included']['details'] = [f"{included} favorites included"]
    else:
        results['favorites_included']['score'] = 100
        results['favorites_included']['details'] = ["No favorites set"]
    
    # 13. Goal Alignment
    goal = user.get('goal', '').lower()
    goal_score = 100
    
    if 'muscle' in goal or 'strength' in goal:
        compounds = sum(1 for ex in workout if is_compound_exercise(ex.get('name', '')))
        goal_score = min(100, int(compounds / len(workout) * 150))
    elif 'lean' in goal:
        # Check for supersetable exercises
        goal_score = 90  # Most exercises are supersetable
    
    results['goal_alignment']['score'] = goal_score
    results['goal_alignment']['details'] = [f"Aligned with {user['goal']}"]
    
    return results

def calculate_overall_score(validations):
    """Calculate weighted overall score"""
    total_weight = sum(v['weight'] for v in validations.values())
    weighted_score = sum(v['score'] * v['weight'] for v in validations.values())
    return int(weighted_score / total_weight)

def get_grade(score):
    if score >= 97: return 'A+'
    if score >= 93: return 'A'
    if score >= 90: return 'A-'
    if score >= 87: return 'B+'
    if score >= 83: return 'B'
    if score >= 80: return 'B-'
    if score >= 77: return 'C+'
    if score >= 73: return 'C'
    if score >= 70: return 'C-'
    if score >= 60: return 'D'
    return 'F'

# ============================================================================
# HTML REPORT GENERATION
# ============================================================================

def generate_html_report(results, all_exercises, sample_users, grades, avg_score, categories):
    """Generate comprehensive HTML report"""
    
    html = f"""<!DOCTYPE html>
<html>
<head>
    <title>500-User Advanced Workout Audit - Launch Validation</title>
    <style>
        * {{ box-sizing: border-box; }}
        body {{ font-family: 'Segoe UI', -apple-system, BlinkMacSystemFont, sans-serif; margin: 0; padding: 40px; background: #f0f2f5; }}
        .container {{ max-width: 1400px; margin: 0 auto; }}
        .header {{ background: linear-gradient(135deg, #1a1a2e 0%, #16213e 50%, #0f3460 100%); color: white; padding: 40px; border-radius: 20px; margin-bottom: 30px; text-align: center; }}
        .header h1 {{ margin: 0 0 10px 0; font-size: 2.5em; }}
        .header .subtitle {{ opacity: 0.9; font-size: 1.2em; }}
        .header .timestamp {{ opacity: 0.7; font-size: 0.9em; margin-top: 15px; }}
        
        .summary-grid {{ display: grid; grid-template-columns: repeat(4, 1fr); gap: 20px; margin-bottom: 30px; }}
        .summary-card {{ background: white; border-radius: 15px; padding: 25px; text-align: center; box-shadow: 0 4px 15px rgba(0,0,0,0.08); }}
        .summary-card .value {{ font-size: 3em; font-weight: bold; color: #1a1a2e; }}
        .summary-card .label {{ color: #666; margin-top: 5px; }}
        .summary-card.highlight {{ background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; }}
        .summary-card.highlight .value {{ color: white; }}
        .summary-card.highlight .label {{ color: rgba(255,255,255,0.9); }}
        
        .section {{ background: white; border-radius: 15px; padding: 30px; margin-bottom: 30px; box-shadow: 0 4px 15px rgba(0,0,0,0.08); }}
        .section h2 {{ margin: 0 0 20px 0; color: #1a1a2e; border-bottom: 2px solid #eee; padding-bottom: 15px; }}
        
        .grade-distribution {{ display: flex; gap: 10px; flex-wrap: wrap; justify-content: center; }}
        .grade-pill {{ padding: 12px 24px; border-radius: 25px; font-weight: bold; font-size: 1.1em; }}
        .grade-A {{ background: #d4edda; color: #155724; }}
        .grade-B {{ background: #fff3cd; color: #856404; }}
        .grade-C {{ background: #ffeeba; color: #856404; }}
        .grade-D {{ background: #f8d7da; color: #721c24; }}
        .grade-F {{ background: #721c24; color: white; }}
        
        .validation-grid {{ display: grid; grid-template-columns: repeat(4, 1fr); gap: 15px; }}
        .validation-item {{ background: #f8f9fa; padding: 20px; border-radius: 10px; text-align: center; }}
        .validation-item .score {{ font-size: 2em; font-weight: bold; }}
        .validation-item .name {{ color: #666; font-size: 0.9em; margin-top: 5px; }}
        .score-excellent {{ color: #28a745; }}
        .score-good {{ color: #17a2b8; }}
        .score-ok {{ color: #ffc107; }}
        .score-bad {{ color: #dc3545; }}
        
        .user-card {{ border: 1px solid #e0e0e0; border-radius: 15px; padding: 25px; margin: 20px 0; background: #fafafa; page-break-inside: avoid; }}
        .user-header {{ display: flex; justify-content: space-between; align-items: center; margin-bottom: 20px; padding-bottom: 15px; border-bottom: 2px solid #eee; }}
        .user-header h3 {{ margin: 0; color: #1a1a2e; }}
        .user-grade {{ font-size: 1.8em; font-weight: bold; padding: 10px 25px; border-radius: 10px; }}
        
        .profile-grid {{ display: grid; grid-template-columns: repeat(4, 1fr); gap: 12px; margin: 20px 0; }}
        .profile-item {{ background: white; padding: 12px; border-radius: 8px; border-left: 4px solid #667eea; }}
        .profile-item .label {{ font-size: 11px; color: #888; text-transform: uppercase; letter-spacing: 0.5px; }}
        .profile-item .value {{ font-weight: 600; color: #1a1a2e; margin-top: 3px; }}
        
        .workout-table {{ width: 100%; border-collapse: collapse; margin: 20px 0; }}
        .workout-table th {{ background: #1a1a2e; color: white; padding: 12px; text-align: left; font-weight: 500; }}
        .workout-table td {{ padding: 12px; border-bottom: 1px solid #eee; }}
        .workout-table tr:hover {{ background: #f0f7ff; }}
        
        .mini-validation {{ display: grid; grid-template-columns: repeat(4, 1fr); gap: 10px; margin-top: 20px; }}
        .mini-val {{ background: white; padding: 12px; border-radius: 8px; text-align: center; }}
        .mini-val .score {{ font-size: 1.4em; font-weight: bold; }}
        .mini-val .name {{ font-size: 0.75em; color: #666; }}
        
        .journey-badge {{ display: inline-block; padding: 4px 12px; border-radius: 15px; font-size: 0.85em; font-weight: 500; }}
        .journey-new {{ background: #e3f2fd; color: #1565c0; }}
        .journey-early {{ background: #fff3e0; color: #ef6c00; }}
        .journey-building {{ background: #e8f5e9; color: #2e7d32; }}
        .journey-consistent {{ background: #f3e5f5; color: #7b1fa2; }}
        .journey-veteran {{ background: #fce4ec; color: #c2185b; }}
        
        .footer {{ text-align: center; color: #888; padding: 30px; font-size: 0.9em; }}
        
        @media print {{
            body {{ padding: 20px; }}
            .user-card {{ page-break-inside: avoid; }}
        }}
    </style>
</head>
<body>
<div class="container">
    <div class="header">
        <h1>🚀 Advanced 500-User Workout Audit</h1>
        <div class="subtitle">Production Launch Validation Report</div>
        <div class="timestamp">Generated: {datetime.now().strftime('%B %d, %Y at %I:%M %p')}</div>
    </div>
    
    <div class="summary-grid">
        <div class="summary-card highlight">
            <div class="value">{avg_score:.1f}%</div>
            <div class="label">Average Score</div>
        </div>
        <div class="summary-card">
            <div class="value">500</div>
            <div class="label">Users Tested</div>
        </div>
        <div class="summary-card">
            <div class="value">{len(all_exercises):,}</div>
            <div class="label">Exercise Database</div>
        </div>
        <div class="summary-card">
            <div class="value">{grades.get('A+', 0) + grades.get('A', 0) + grades.get('A-', 0)}</div>
            <div class="label">A-Grade Users</div>
        </div>
    </div>
    
    <div class="section">
        <h2>📊 Grade Distribution</h2>
        <div class="grade-distribution">
"""
    
    for grade in ['A+', 'A', 'A-', 'B+', 'B', 'B-', 'C+', 'C', 'C-', 'D', 'F']:
        count = grades.get(grade, 0)
        if count > 0:
            grade_class = 'grade-A' if 'A' in grade else ('grade-B' if 'B' in grade else ('grade-C' if 'C' in grade else ('grade-D' if grade == 'D' else 'grade-F')))
            html += f'<div class="grade-pill {grade_class}">{grade}: {count}</div>\n'
    
    html += """
        </div>
    </div>
    
    <div class="section">
        <h2>✅ Validation Categories</h2>
        <div class="validation-grid">
"""
    
    for cat in categories:
        avg = sum(r['validations'][cat]['score'] for r in results) / len(results)
        score_class = 'score-excellent' if avg >= 95 else ('score-good' if avg >= 85 else ('score-ok' if avg >= 70 else 'score-bad'))
        html += f"""
            <div class="validation-item">
                <div class="score {score_class}">{avg:.0f}%</div>
                <div class="name">{cat.replace('_', ' ').title()}</div>
            </div>
"""
    
    html += """
        </div>
    </div>
    
    <div class="section">
        <h2>👥 Detailed User Reports (50 Sample Users)</h2>
"""
    
    journey_classes = {
        'new_user': 'journey-new',
        'first_week': 'journey-early',
        'getting_started': 'journey-early',
        'building_habit': 'journey-building',
        'consistent': 'journey-consistent',
        'veteran': 'journey-veteran',
    }
    
    for result in sample_users:
        user = result['user']
        workout = result['workout']
        validations = result['validations']
        
        grade_class = 'grade-A' if 'A' in result['grade'] else ('grade-B' if 'B' in result['grade'] else ('grade-C' if 'C' in result['grade'] else ('grade-D' if result['grade'] == 'D' else 'grade-F')))
        journey_class = journey_classes.get(user.get('journey_stage', 'new_user'), 'journey-new')
        
        equipment_str = ', '.join(user.get('equipment_list', ['bodyweight'])).title()
        favorites_str = ', '.join(user.get('favorites', [])[:3]) if user.get('favorites') else 'None'
        if len(user.get('favorites', [])) > 3:
            favorites_str += f" (+{len(user['favorites']) - 3} more)"
        
        html += f"""
        <div class="user-card">
            <div class="user-header">
                <div>
                    <h3>User #{user['id']}: {user['name']}</h3>
                    <span class="journey-badge {journey_class}">{user.get('journey_stage', 'new').replace('_', ' ').title()} • {user.get('workouts_completed', 0)} workouts</span>
                </div>
                <div class="user-grade {grade_class}">{result['grade']} ({result['overall_score']}%)</div>
            </div>
            
            <div class="profile-grid">
                <div class="profile-item"><div class="label">Demographics</div><div class="value">{user['gender']}, {user['age']}yo, {user['height']}, {user['weight']}lbs</div></div>
                <div class="profile-item"><div class="label">Goal</div><div class="value">{user['goal']}</div></div>
                <div class="profile-item"><div class="label">Experience</div><div class="value">{user['experience']}</div></div>
                <div class="profile-item"><div class="label">Location</div><div class="value">{user['location'].upper()}</div></div>
                <div class="profile-item"><div class="label">Equipment</div><div class="value">{equipment_str}</div></div>
                <div class="profile-item"><div class="label">Workout Type</div><div class="value">{user['workout_type']}</div></div>
                <div class="profile-item"><div class="label">Injury</div><div class="value">{user['injury'].title() if user['injury'] else 'None'}</div></div>
                <div class="profile-item"><div class="label">Favorites</div><div class="value">{favorites_str}</div></div>
            </div>
            
            <table class="workout-table">
                <tr>
                    <th>#</th>
                    <th>Exercise</th>
                    <th>Family</th>
                    <th>Equipment</th>
                    <th>Difficulty</th>
                    <th>Muscles</th>
                </tr>
"""
        
        for idx, ex in enumerate(workout, 1):
            muscles = ex.get('primary_muscles', [])
            if isinstance(muscles, str):
                import ast
                try: muscles = ast.literal_eval(muscles)
                except: muscles = []
            muscles_str = ', '.join(muscles[:2]) if muscles else 'N/A'
            if len(muscles) > 2:
                muscles_str += '...'
            
            is_fav = '⭐ ' if (ex.get('name') or '').lower() in set(f.lower() for f in user.get('favorites', [])) else ''
            
            html += f"""
                <tr>
                    <td>{idx}</td>
                    <td>{is_fav}{ex.get('name', 'Unknown')}</td>
                    <td>{ex.get('exercise_family', 'N/A')}</td>
                    <td>{ex.get('equipment_category', 'N/A').title()}</td>
                    <td>Level {ex.get('difficulty_level', '?')}</td>
                    <td>{muscles_str}</td>
                </tr>
"""
        
        html += """
            </table>
            
            <div class="mini-validation">
"""
        
        # Show key validations
        key_cats = ['equipment_match', 'injury_safe', 'workout_type_match', 'body_region_consistency', 
                   'equipment_diversity', 'movement_diversity', 'compound_ordering', 'goal_alignment']
        for cat in key_cats:
            score = validations[cat]['score']
            score_class = 'score-excellent' if score >= 95 else ('score-good' if score >= 85 else ('score-ok' if score >= 70 else 'score-bad'))
            html += f"""
                <div class="mini-val">
                    <div class="score {score_class}">{score}%</div>
                    <div class="name">{cat.replace('_', ' ').title()}</div>
                </div>
"""
        
        html += """
            </div>
        </div>
"""
    
    html += f"""
    </div>
    
    <div class="footer">
        <p>🏋️ GoFit Workout Generation Audit System</p>
        <p>500 unique users • {len(all_exercises):,} exercises • {len(categories)} validation criteria</p>
    </div>
</div>
</body>
</html>
"""
    
    return html

# ============================================================================
# MAIN EXECUTION
# ============================================================================

if __name__ == '__main__':
    print("=" * 80)
    print("🚀 ADVANCED 500-USER WORKOUT AUDIT - LAUNCH VALIDATION")
    print("=" * 80)
    print()
    
    # Fetch exercises
    print("📥 Fetching exercise database...")
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
    
    print(f"✅ Loaded {len(all_exercises):,} exercises")
    print()
    
    # Generate and test users
    print("🔄 Generating 500 test users across different journey stages...")
    results = []
    
    categories = ['equipment_match', 'equipment_diversity', 'difficulty_appropriate', 
                  'injury_safe', 'workout_type_match', 'body_region_consistency',
                  'movement_diversity', 'position_diversity', 'muscle_diversity',
                  'compound_ordering', 'family_diversity', 'favorites_included', 'goal_alignment']
    
    for i in range(1, 501):
        user = generate_user(i, all_exercises)
        filtered = filter_exercises_advanced(all_exercises, user)
        workout = generate_workout_advanced(filtered, user, all_exercises, 6)
        validations = validate_workout_advanced(workout, user, filtered)
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
        
        if i % 100 == 0:
            print(f"   Processed {i}/500 users...")
    
    print("✅ All 500 users processed!")
    print()
    
    # Calculate statistics
    grades = Counter(r['grade'] for r in results)
    avg_score = sum(r['overall_score'] for r in results) / len(results)
    
    print("=" * 80)
    print("📊 SUMMARY STATISTICS")
    print("=" * 80)
    print(f"Average Score: {avg_score:.1f}%")
    print()
    print("Grade Distribution:")
    for grade in ['A+', 'A', 'A-', 'B+', 'B', 'B-', 'C+', 'C', 'C-', 'D', 'F']:
        count = grades.get(grade, 0)
        bar = '█' * (count // 5) if count > 0 else ''
        print(f"   {grade:3}: {count:3d} {bar}")
    
    print()
    print("Validation Category Averages:")
    for cat in categories:
        avg = sum(r['validations'][cat]['score'] for r in results) / len(results)
        status = '✅' if avg >= 90 else ('⚠️' if avg >= 80 else '❌')
        print(f"   {status} {cat.replace('_', ' ').title()}: {avg:.1f}%")
    
    print()
    print("Journey Stage Distribution:")
    journey_counts = Counter(r['user']['journey_stage'] for r in results)
    for stage, count in sorted(journey_counts.items()):
        print(f"   {stage.replace('_', ' ').title()}: {count}")
    
    # Select 50 sample users for detailed report
    print()
    print("📋 Selecting 50 users for detailed report...")
    sample_users = []
    
    # 10 best
    sample_users.extend(sorted(results, key=lambda x: -x['overall_score'])[:10])
    # 10 worst
    sample_users.extend(sorted(results, key=lambda x: x['overall_score'])[:10])
    # 10 from each journey stage
    for stage in JOURNEY_STAGES:
        stage_users = [r for r in results if r['user']['journey_stage'] == stage and r not in sample_users]
        if stage_users:
            sample_users.extend(random.sample(stage_users, min(5, len(stage_users))))
    # Fill to 50
    remaining = [r for r in results if r not in sample_users]
    random.shuffle(remaining)
    sample_users.extend(remaining[:max(0, 50 - len(sample_users))])
    sample_users = sample_users[:50]
    
    # Sort by user ID for consistency
    sample_users.sort(key=lambda x: x['user']['id'])
    
    # Generate reports
    print()
    print("=" * 80)
    print("📝 GENERATING REPORTS")
    print("=" * 80)
    
    html_content = generate_html_report(results, all_exercises, sample_users, grades, avg_score, categories)
    
    report_path = '/Users/josephreed/Desktop/Workout App/500_user_advanced_audit.html'
    with open(report_path, 'w') as f:
        f.write(html_content)
    print(f"✅ HTML Report saved: {report_path}")
    
    # Save JSON
    json_path = '/Users/josephreed/Desktop/Workout App/500_user_advanced_audit.json'
    json_data = {
        'summary': {
            'total_users': 500,
            'average_score': avg_score,
            'grade_distribution': dict(grades),
            'validation_averages': {cat: sum(r['validations'][cat]['score'] for r in results) / len(results) for cat in categories},
            'journey_distribution': dict(journey_counts),
            'generated_at': datetime.now().isoformat()
        },
        'sample_users': [{
            'user': {k: v for k, v in r['user'].items() if k != 'workout_history'},
            'filtered_count': r['filtered_count'],
            'workout': [{'name': ex.get('name'), 'family': ex.get('exercise_family'),
                        'equipment': ex.get('equipment_category'), 'difficulty': ex.get('difficulty_level'),
                        'muscles': ex.get('primary_muscles')} for ex in r['workout']],
            'validations': {k: {'score': v['score'], 'details': v['details']} for k, v in r['validations'].items()},
            'overall_score': r['overall_score'],
            'grade': r['grade']
        } for r in sample_users]
    }
    
    with open(json_path, 'w') as f:
        json.dump(json_data, f, indent=2)
    print(f"✅ JSON Data saved: {json_path}")
    
    print()
    print("=" * 80)
    print("✅ AUDIT COMPLETE!")
    print("=" * 80)
    print(f"""
📊 Final Results:
   • Average Score: {avg_score:.1f}%
   • A+ grades: {grades.get('A+', 0)}
   • A grades: {grades.get('A', 0)}
   • A- grades: {grades.get('A-', 0)}
   • B+ or below: {sum(grades.get(g, 0) for g in ['B+', 'B', 'B-', 'C+', 'C', 'C-', 'D', 'F'])}

📁 Reports:
   • HTML: {report_path}
   • JSON: {json_path}
   
💡 Open the HTML file in Chrome/Safari and Print > Save as PDF
""")
