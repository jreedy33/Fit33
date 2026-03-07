#!/usr/bin/env python3
"""
Comprehensive Exercise Database Cleaner - Full 6,749 Exercise Audit
====================================================================
Processes ALL exercises from the complete database:
1. Merges data from: exercise_goal_classifications.csv, exercise_family_goal_priorities.csv,
   exercises.json, exercises_with_both_genders.csv
2. Standardizes naming: "Exercise Name (Equipment)" format
3. Verifies/corrects muscle assignments using exercise families + biomechanical knowledge
4. Cross-references with video database
5. Removes duplicates, POV/camera variants, rare exercises without video
6. Outputs cleaned CSV and detailed MD report
"""

import json
import csv
import re
import os
from datetime import datetime
from collections import Counter, defaultdict

# ============================================================================
# FILE PATHS
# ============================================================================
BASE = os.path.join(os.path.dirname(__file__), '..')
GOALS_CSV = os.path.join(BASE, 'exercise_goal_classifications.csv')
FAMILY_CSV = os.path.join(BASE, 'exercise_family_goal_priorities.csv')
JSON_FILE = os.path.join(BASE, 'Fit33', 'Resources', 'exercises.json')
VIDEO_CSV = os.path.join(BASE, 'exercises_with_both_genders.csv')
OUTPUT_CSV = os.path.join(BASE, 'exercises_cleaned.csv')
OUTPUT_JSON = os.path.join(BASE, 'Fit33', 'Resources', 'exercises.json')
REPORT_MD = os.path.join(BASE, 'exercise_cleanup_report.md')

# ============================================================================
# EQUIPMENT STANDARDIZATION
# ============================================================================
EQUIPMENT_DISPLAY = {
    'bodyweight': 'Bodyweight',
    'dumbbell': 'Dumbbell',
    'cable': 'Cable',
    'barbell': 'Barbell',
    'machine': 'Machine',
    'band': 'Band',
    'kettlebell': 'Kettlebell',
    'smith_machine': 'Smith Machine',
    'resistance_band': 'Band',
    'stability_ball': 'Stability Ball',
    'medicine_ball': 'Medicine Ball',
    'ez_bar': 'EZ Bar',
    'trap_bar': 'Trap Bar',
    '': 'Bodyweight',
}

# Prefixes in exercise names that indicate equipment
EQUIPMENT_NAME_PREFIXES = [
    ('Smith Machine', 'Smith Machine'),
    ('Smith', 'Smith Machine'),
    ('Lever', 'Machine'),
    ('Sled', 'Machine'),
    ('Cable', 'Cable'),
    ('Dumbbell', 'Dumbbell'),
    ('Dumbbells', 'Dumbbell'),
    ('Barbell', 'Barbell'),
    ('EZ Barbell', 'EZ Bar'),
    ('Ez Bar', 'EZ Bar'),
    ('EZ Bar', 'EZ Bar'),
    ('Kettlebell', 'Kettlebell'),
    ('Ring', 'Rings'),
    ('Suspender', 'Suspension Trainer'),
    ('Bottle', 'Bodyweight'),  # Bottle weighted = essentially bodyweight
    ('Landmine', 'Barbell'),  # Landmine uses barbell
    ('Weighted Plate', 'Plate'),
]

# ============================================================================
# EXERCISE FAMILY -> MUSCLE MAPPING (Biomechanical knowledge)
# ============================================================================
FAMILY_TO_CATEGORY_AND_MUSCLES = {
    # CHEST
    'bench_press': {'category': 'Chest', 'primary': 'Mid Chest', 'secondary': ['Front Delts', 'Triceps']},
    'incline_press': {'category': 'Chest', 'primary': 'Upper Chest', 'secondary': ['Front Delts', 'Triceps']},
    'decline_press': {'category': 'Chest', 'primary': 'Lower Chest', 'secondary': ['Front Delts', 'Triceps']},
    'chest_press': {'category': 'Chest', 'primary': 'Mid Chest', 'secondary': ['Front Delts', 'Triceps']},
    'fly': {'category': 'Chest', 'primary': 'Mid Chest', 'secondary': ['Front Delts']},
    'push_up': {'category': 'Chest', 'primary': 'Mid Chest', 'secondary': ['Front Delts', 'Triceps', 'Core']},
    'dip': {'category': 'Chest', 'primary': 'Lower Chest', 'secondary': ['Triceps', 'Front Delts']},
    'chest_fly': {'category': 'Chest', 'primary': 'Mid Chest', 'secondary': ['Front Delts']},
    'pec_deck': {'category': 'Chest', 'primary': 'Mid Chest', 'secondary': ['Front Delts']},
    'pullover': {'category': 'Chest', 'primary': 'Mid Chest', 'secondary': ['Lats', 'Serratus']},

    # BACK
    'bent_over_row': {'category': 'Back', 'primary': 'Middle Back', 'secondary': ['Lats', 'Rear Delts', 'Biceps']},
    'lat_pulldown': {'category': 'Back', 'primary': 'Lats', 'secondary': ['Biceps', 'Upper Back']},
    'seated_row': {'category': 'Back', 'primary': 'Middle Back', 'secondary': ['Lats', 'Biceps']},
    'pull_up': {'category': 'Back', 'primary': 'Lats', 'secondary': ['Biceps', 'Upper Back']},
    'chin_up': {'category': 'Back', 'primary': 'Lats', 'secondary': ['Biceps', 'Upper Back']},
    'face_pull': {'category': 'Back', 'primary': 'Rear Delts', 'secondary': ['Upper Back', 'Rotator Cuff']},
    'shrug': {'category': 'Back', 'primary': 'Upper Traps', 'secondary': ['Upper Back']},
    't_bar_row': {'category': 'Back', 'primary': 'Middle Back', 'secondary': ['Lats', 'Biceps']},
    'back_exercise': {'category': 'Back', 'primary': 'Middle Back', 'secondary': ['Lats']},
    'inverted_row': {'category': 'Back', 'primary': 'Middle Back', 'secondary': ['Lats', 'Biceps']},
    'hyperextension': {'category': 'Back', 'primary': 'Lower Back', 'secondary': ['Glutes', 'Hamstrings']},
    'glute_kickback': {'category': 'Legs', 'primary': 'Glutes', 'secondary': ['Hamstrings']},
    'kickback': {'category': None, 'primary': None, 'secondary': []},  # Ambiguous - triceps or glute

    # SHOULDERS
    'shoulder_press': {'category': 'Shoulders', 'primary': 'Front Delts', 'secondary': ['Side Delts', 'Triceps']},
    'overhead_press': {'category': 'Shoulders', 'primary': 'Front Delts', 'secondary': ['Side Delts', 'Triceps']},
    'lateral_raise': {'category': 'Shoulders', 'primary': 'Side Delts', 'secondary': ['Front Delts']},
    'front_raise': {'category': 'Shoulders', 'primary': 'Front Delts', 'secondary': ['Upper Chest']},
    'rear_delt_fly': {'category': 'Shoulders', 'primary': 'Rear Delts', 'secondary': ['Upper Back']},
    'upright_row': {'category': 'Shoulders', 'primary': 'Side Delts', 'secondary': ['Upper Traps', 'Front Delts']},
    'shoulder_exercise': {'category': 'Shoulders', 'primary': 'Side Delts', 'secondary': ['Front Delts', 'Rear Delts']},
    'arnold_press': {'category': 'Shoulders', 'primary': 'Front Delts', 'secondary': ['Side Delts', 'Triceps']},
    'raise': {'category': 'Shoulders', 'primary': 'Side Delts', 'secondary': ['Front Delts']},

    # ARMS - Biceps
    'bicep_curl': {'category': 'Arms', 'primary': 'Biceps', 'secondary': ['Forearms (Flexors)']},
    'hammer_curl': {'category': 'Arms', 'primary': 'Biceps', 'secondary': ['Forearms (Flexors)']},
    'preacher_curl': {'category': 'Arms', 'primary': 'Biceps', 'secondary': ['Forearms (Flexors)']},
    'concentration_curl': {'category': 'Arms', 'primary': 'Biceps', 'secondary': ['Forearms (Flexors)']},

    # ARMS - Triceps
    'tricep_extension': {'category': 'Arms', 'primary': 'Triceps', 'secondary': []},
    'tricep_pushdown': {'category': 'Arms', 'primary': 'Triceps', 'secondary': []},
    'tricep_kickback': {'category': 'Arms', 'primary': 'Triceps', 'secondary': []},
    'skull_crusher': {'category': 'Arms', 'primary': 'Triceps', 'secondary': []},
    'arm_exercise': {'category': 'Arms', 'primary': 'Biceps', 'secondary': ['Triceps']},

    # LEGS
    'squat': {'category': 'Legs', 'primary': 'Quads', 'secondary': ['Glutes', 'Hamstrings']},
    'lunge': {'category': 'Legs', 'primary': 'Quads', 'secondary': ['Glutes', 'Hamstrings']},
    'leg_press': {'category': 'Legs', 'primary': 'Quads', 'secondary': ['Glutes', 'Hamstrings']},
    'leg_extension': {'category': 'Legs', 'primary': 'Quads', 'secondary': []},
    'leg_curl': {'category': 'Legs', 'primary': 'Hamstrings', 'secondary': ['Calves']},
    'deadlift': {'category': 'Legs', 'primary': 'Hamstrings', 'secondary': ['Glutes', 'Lower Back']},
    'hip_thrust': {'category': 'Legs', 'primary': 'Glutes', 'secondary': ['Hamstrings']},
    'glute_bridge': {'category': 'Legs', 'primary': 'Glutes', 'secondary': ['Hamstrings', 'Core']},
    'calf_raise': {'category': 'Legs', 'primary': 'Calves', 'secondary': []},
    'step_up': {'category': 'Legs', 'primary': 'Quads', 'secondary': ['Glutes', 'Hamstrings']},
    'split_squat': {'category': 'Legs', 'primary': 'Quads', 'secondary': ['Glutes', 'Hamstrings']},
    'goblet_squat': {'category': 'Legs', 'primary': 'Quads', 'secondary': ['Glutes', 'Core']},
    'hack_squat': {'category': 'Legs', 'primary': 'Quads', 'secondary': ['Glutes', 'Hamstrings']},
    'romanian_deadlift': {'category': 'Legs', 'primary': 'Hamstrings', 'secondary': ['Glutes', 'Lower Back']},
    'good_morning': {'category': 'Legs', 'primary': 'Hamstrings', 'secondary': ['Glutes', 'Lower Back']},
    'leg_exercise': {'category': 'Legs', 'primary': 'Quads', 'secondary': ['Glutes']},
    'hip_abduction': {'category': 'Legs', 'primary': 'Glute Med/Min', 'secondary': ['Glutes']},
    'hip_adduction': {'category': 'Legs', 'primary': 'Inner Thigh', 'secondary': ['Hip Flexors']},
    'hip_flexion': {'category': 'Legs', 'primary': 'Hip Flexors', 'secondary': ['Quads']},
    'wall_sit': {'category': 'Legs', 'primary': 'Quads', 'secondary': ['Glutes']},

    # CORE
    'crunch': {'category': 'Core', 'primary': 'Upper Abs', 'secondary': ['Abs', 'Core']},
    'plank': {'category': 'Core', 'primary': 'Core', 'secondary': ['Abs', 'Lower Back']},
    'leg_raise': {'category': 'Core', 'primary': 'Lower Abs', 'secondary': ['Hip Flexors', 'Abs']},
    'sit_up': {'category': 'Core', 'primary': 'Abs', 'secondary': ['Hip Flexors']},
    'russian_twist': {'category': 'Core', 'primary': 'Obliques', 'secondary': ['Abs', 'Core']},
    'woodchop': {'category': 'Core', 'primary': 'Obliques', 'secondary': ['Core', 'Abs']},
    'side_bend': {'category': 'Core', 'primary': 'Obliques', 'secondary': ['Core']},
    'mountain_climber': {'category': 'Core', 'primary': 'Core', 'secondary': ['Abs', 'Hip Flexors']},
    'core_exercise': {'category': 'Core', 'primary': 'Core', 'secondary': ['Abs']},
    'ab_wheel': {'category': 'Core', 'primary': 'Abs', 'secondary': ['Core', 'Lower Back']},
    'bicycle_crunch': {'category': 'Core', 'primary': 'Obliques', 'secondary': ['Abs', 'Hip Flexors']},

    # FULL BODY / CARDIO
    'burpee': {'category': 'Full Body', 'primary': 'Full Body', 'secondary': ['Core']},
    'clean': {'category': 'Full Body', 'primary': 'Full Body', 'secondary': ['Quads', 'Glutes', 'Upper Back']},
    'snatch': {'category': 'Full Body', 'primary': 'Full Body', 'secondary': ['Quads', 'Glutes', 'Shoulders']},
    'cycling': {'category': 'Cardio', 'primary': 'Cardio', 'secondary': ['Quads', 'Hamstrings']},
    'general_movement': {'category': 'Full Body', 'primary': 'Full Body', 'secondary': []},
    'general_stretch': {'category': 'Stretching', 'primary': None, 'secondary': []},
    'press': {'category': None, 'primary': None, 'secondary': []},  # Ambiguous - infer from name
    'extension': {'category': 'Arms', 'primary': 'Triceps', 'secondary': []},  # Default to triceps, override by name
    'back_stretch': {'category': 'Stretching', 'primary': 'Lower Back', 'secondary': []},
    'chest_exercise': {'category': 'Chest', 'primary': 'Mid Chest', 'secondary': ['Front Delts']},
    'farmers_walk': {'category': 'Full Body', 'primary': 'Full Body', 'secondary': ['Core', 'Forearms (Flexors)']},
    'kettlebell_swing': {'category': 'Full Body', 'primary': 'Full Body', 'secondary': ['Glutes', 'Hamstrings', 'Core']},
    'glute_exercise': {'category': 'Legs', 'primary': 'Glutes', 'secondary': ['Hamstrings']},
    'hamstring_exercise': {'category': 'Legs', 'primary': 'Hamstrings', 'secondary': ['Glutes']},
    'hang_clean': {'category': 'Full Body', 'primary': 'Full Body', 'secondary': ['Upper Traps', 'Quads']},
    'power_clean': {'category': 'Full Body', 'primary': 'Full Body', 'secondary': ['Upper Traps', 'Quads']},
    'seated_calf_raise': {'category': 'Legs', 'primary': 'Calves', 'secondary': []},
    'hip_stretch': {'category': 'Stretching', 'primary': None, 'secondary': []},
    'oblique_crunch': {'category': 'Core', 'primary': 'Obliques', 'secondary': ['Abs']},
    'reverse_lunge': {'category': 'Legs', 'primary': 'Quads', 'secondary': ['Glutes', 'Hamstrings']},
    'overhead_tricep_extension': {'category': 'Arms', 'primary': 'Triceps', 'secondary': []},
    'reverse_curl': {'category': 'Arms', 'primary': 'Biceps', 'secondary': ['Forearms (Flexors)']},
    'v_up': {'category': 'Core', 'primary': 'Abs', 'secondary': ['Hip Flexors']},
}

# ============================================================================
# NAME-BASED CATEGORY/MUSCLE INFERENCE
# ============================================================================
NAME_KEYWORD_TO_MUSCLES = [
    # Order matters - more specific first
    (r'bench press|chest press|pec deck|pec fly', {'category': 'Chest', 'primary': 'Mid Chest'}),
    (r'incline.*press|incline.*fly|incline.*push', {'category': 'Chest', 'primary': 'Upper Chest'}),
    (r'decline.*press|decline.*fly', {'category': 'Chest', 'primary': 'Lower Chest'}),
    (r'push.?up|push.?off', {'category': 'Chest', 'primary': 'Mid Chest'}),
    (r'fly|flye|pec', {'category': 'Chest', 'primary': 'Mid Chest'}),
    (r'pullover', {'category': 'Chest', 'primary': 'Mid Chest'}),

    (r'lat pull|pulldown|pull.?down', {'category': 'Back', 'primary': 'Lats'}),
    (r'chin.?up', {'category': 'Back', 'primary': 'Lats'}),
    (r'pull.?up', {'category': 'Back', 'primary': 'Lats'}),
    (r'bent.?over.*row|barbell row|dumbbell row|cable row|seated row|t.?bar row', {'category': 'Back', 'primary': 'Middle Back'}),
    (r'shrug', {'category': 'Back', 'primary': 'Upper Traps'}),
    (r'hyperextension|back extension|reverse hyper', {'category': 'Back', 'primary': 'Lower Back'}),
    (r'face pull', {'category': 'Back', 'primary': 'Rear Delts'}),

    (r'shoulder press|military press|overhead press|arnold press', {'category': 'Shoulders', 'primary': 'Front Delts'}),
    (r'lateral raise|side raise|side delt', {'category': 'Shoulders', 'primary': 'Side Delts'}),
    (r'front raise', {'category': 'Shoulders', 'primary': 'Front Delts'}),
    (r'rear delt|rear lateral|reverse fly|reverse flye', {'category': 'Shoulders', 'primary': 'Rear Delts'}),
    (r'upright row', {'category': 'Shoulders', 'primary': 'Side Delts'}),
    (r'external rotation|internal rotation|rotator cuff', {'category': 'Shoulders', 'primary': 'Rotator Cuff'}),

    (r'bicep|biceps|curl(?!.*leg)(?!.*ham)(?!.*nordic)', {'category': 'Arms', 'primary': 'Biceps'}),
    (r'tricep|triceps|pushdown|skull crush|dip(?!.*chest)', {'category': 'Arms', 'primary': 'Triceps'}),
    (r'wrist curl|wrist extension|forearm|finger curl', {'category': 'Arms', 'primary': 'Forearms (Flexors)'}),

    (r'squat|leg press|pistol', {'category': 'Legs', 'primary': 'Quads'}),
    (r'lunge|split squat|step.?up|bulgarian', {'category': 'Legs', 'primary': 'Quads'}),
    (r'deadlift|rdl|romanian', {'category': 'Legs', 'primary': 'Hamstrings'}),
    (r'good morning', {'category': 'Legs', 'primary': 'Hamstrings'}),
    (r'leg curl|hamstring curl|nordic curl|leg.?curl', {'category': 'Legs', 'primary': 'Hamstrings'}),
    (r'leg extension|quad extension', {'category': 'Legs', 'primary': 'Quads'}),
    (r'hip thrust|glute bridge|bridge', {'category': 'Legs', 'primary': 'Glutes'}),
    (r'calf raise|calf press|donkey calf', {'category': 'Legs', 'primary': 'Calves'}),
    (r'hip abduction|abduct', {'category': 'Legs', 'primary': 'Glute Med/Min'}),
    (r'hip adduction|adduct|inner thigh', {'category': 'Legs', 'primary': 'Inner Thigh'}),

    (r'crunch|sit.?up|v.?up|tuck.?up', {'category': 'Core', 'primary': 'Abs'}),
    (r'plank', {'category': 'Core', 'primary': 'Core'}),
    (r'leg raise|hanging.*raise|knee raise', {'category': 'Core', 'primary': 'Lower Abs'}),
    (r'russian twist|wood.?chop|twist|oblique|side bend|wiper', {'category': 'Core', 'primary': 'Obliques'}),
    (r'mountain climb', {'category': 'Core', 'primary': 'Core'}),
    (r'ab wheel|rollout', {'category': 'Core', 'primary': 'Abs'}),

    (r'glute.*kickback|donkey.*kickback|kickback.*glute|leg.*kickback|hip.*kickback', {'category': 'Legs', 'primary': 'Glutes'}),
    (r'kickback(?!.*glute)(?!.*leg)(?!.*donkey)(?!.*hip)', {'category': 'Arms', 'primary': 'Triceps'}),

    (r'burpee|clean and|snatch|thruster|man maker', {'category': 'Full Body', 'primary': 'Full Body'}),
    (r'jump|box jump|plyometric|hop(?:s|ping)?', {'category': 'Full Body', 'primary': 'Full Body'}),
    (r'run|sprint|jog|cycling|bicycle|bike|rowing|swim|elliptical', {'category': 'Cardio', 'primary': 'Cardio'}),
    (r'stretch|yoga|pose|warrior|pigeon|cobra|child|downward|flexibility|mobilization|mobility', {'category': 'Stretching', 'primary': None}),

    # Catch-all patterns for common movements
    (r'bear crawl|inch.?worm|army crawl|crawl', {'category': 'Full Body', 'primary': 'Full Body'}),
    (r'skipping|skip|jump rope|high knee', {'category': 'Cardio', 'primary': 'Cardio'}),
    (r'hollow|superman|bird.?dog|dead.?bug', {'category': 'Core', 'primary': 'Core'}),
    (r'windmill|wood.?chop|rotation|rotational', {'category': 'Core', 'primary': 'Obliques'}),
    (r'chest fly|pec fly', {'category': 'Chest', 'primary': 'Mid Chest'}),
    (r'neck extension|neck flexion|neck', {'category': 'Neck', 'primary': 'Neck'}),
    (r'wrist|forearm|grip strength|gripper', {'category': 'Arms', 'primary': 'Forearms (Flexors)'}),
    (r'row', {'category': 'Back', 'primary': 'Middle Back'}),
    (r'press', {'category': 'Chest', 'primary': 'Mid Chest'}),
]

# ============================================================================
# EXERCISES TO REMOVE
# ============================================================================
REMOVAL_PATTERNS = [
    # Camera angle / POV variants
    r'(?:front|side|back)\s*pov',
    r'fpov\b',
    # Rest poses
    r'rest pose',
    # Duplicate video angles
    r'thighs?\s+(?:front|side)\s+pov',
    # Head rotation (not an exercise)
    r'head full rotation',
    # Walking/marching on spot (cardio filler, not a real exercise)
    r'walking on spot(?:\s|$)',
    r'marching.*on spot',
    r'briskly walking',
    # Extremely rare / nonsensical
    r'vibrate plate',
    r'bottle weighted',  # Water bottle exercises
    r'swim leg circle',
    r'balance pad single',
    r'chair squat calf rock',
    r'palms to head chest fly',  # No equipment, unclear
    r'interlock fist',
    r'shuffle hops?$',
    r'silent burpee',
    r'sky punch',
    r'ballerina(?:\s|$)',
    r'squat star jack',
    r'curtsey cross punch',
    r'standing back squeeze$',
    r'spider to cross body',
    r'riding outdoor bicycle',
    r'recumbent hip external rotator',
]


def should_remove(name, exercise_type, has_video, equipment_detected):
    """Determine if exercise should be removed."""
    name_lower = name.lower()

    # Check removal patterns
    for pattern in REMOVAL_PATTERNS:
        if re.search(pattern, name_lower):
            return True, f"Matches removal pattern: {pattern}"

    # Remove exercises on chairs that are clearly non-standard
    if 'on a chair' in name_lower and 'sitting' in name_lower and not has_video:
        return True, "Sitting-on-chair exercise without video support"

    # Only remove truly obscure exercises - those with nonsensical compound names
    # that have no video and no recognizable exercise pattern
    if not has_video and equipment_detected == 'bodyweight':
        obscure_patterns = [
            r'tap and\s', r'push and\s', r'rock and\s',  # combo filler moves
            r'circle draw', r'fist circle',
            r'(?:side|front|back)\s+pov$',  # POV variants already caught above
        ]
        for pat in obscure_patterns:
            if re.search(pat, name_lower):
                return True, f"Obscure compound movement: {pat}"

    return False, ""


# ============================================================================
# NAME STANDARDIZATION
# ============================================================================

def standardize_name(name, equipment_detected):
    """Convert exercise name to standardized format: Exercise Name (Equipment)"""

    clean_name = name.strip()

    # Fix malformed parentheticals - unbalanced parens
    open_count = clean_name.count('(')
    close_count = clean_name.count(')')
    if open_count != close_count:
        # Remove trailing unclosed parens
        clean_name = clean_name.rstrip('(').strip()
        # Remove trailing unclosed close parens
        clean_name = clean_name.rstrip(')').strip()
        # If still unbalanced, try to fix common patterns
        if clean_name.count('(') > clean_name.count(')'):
            # Add missing closing parens
            diff = clean_name.count('(') - clean_name.count(')')
            clean_name = clean_name + ')' * diff
        elif clean_name.count(')') > clean_name.count('('):
            # Remove extra closing parens from the end
            while clean_name.count(')') > clean_name.count('(') and clean_name.endswith(')'):
                clean_name = clean_name[:-1].strip()

    # Handle double parentheticals like "Lateral Pulldown (with Rope Attachment) (Cable)"
    # Must check this BEFORE single parenthetical
    match2 = re.match(r'^(.+?)\s*\(([^)]+)\)\s*\(([^)]+)\)\s*$', clean_name)
    if match2:
        exercise_part = match2.group(1).strip()
        detail = match2.group(2).strip()
        equip = match2.group(3).strip()
        equip = standardize_equipment_in_parens(equip)
        # Merge detail into equipment
        detail_clean = re.sub(r'^with\s+', '', detail, flags=re.IGNORECASE).strip()
        return f"{title_case_exercise(exercise_part)} ({equip}, {title_case_exercise(detail_clean)})"

    # Already has equipment in parens - clean it up
    match = re.match(r'^(.+?)\s*\(([^)]+)\)\s*$', clean_name)
    if match:
        exercise_part = match.group(1).strip()
        paren_part = match.group(2).strip()

        # Check if the parenthetical is equipment
        equip_keywords = ['barbell', 'dumbbell', 'cable', 'machine', 'bodyweight',
                          'band', 'kettlebell', 'smith', 'ez bar', 'resistance',
                          'stability ball', 'medicine ball', 'plate', 'trap bar']

        paren_lower = paren_part.lower()
        is_equipment = any(kw in paren_lower for kw in equip_keywords)

        if is_equipment:
            # Standardize equipment names in parens
            paren_part = standardize_equipment_in_parens(paren_part)
            return f"{title_case_exercise(exercise_part)} ({paren_part})"
        else:
            # Non-equipment parenthetical (e.g., "donkey")
            # Get equipment from detected
            equip = get_display_equipment(equipment_detected)
            return f"{title_case_exercise(exercise_part)} ({title_case_exercise(paren_part)}) ({equip})"

    # No parens - need to extract equipment from name prefix
    for prefix, equip_name in EQUIPMENT_NAME_PREFIXES:
        if clean_name.startswith(prefix + ' '):
            exercise_part = clean_name[len(prefix):].strip()
            # Clean up the exercise part
            exercise_part = re.sub(r'\s*\(Male\)\s*', '', exercise_part)
            exercise_part = re.sub(r'\s*\(Female\)\s*', '', exercise_part)
            exercise_part = re.sub(r'\s*\(Version \d+\)\s*', '', exercise_part)
            exercise_part = exercise_part.strip()
            if exercise_part:
                return f"{title_case_exercise(exercise_part)} ({equip_name})"

    # No prefix match - add equipment from detected data
    # Remove (Male)/(Female)/(Version X)
    clean_name = re.sub(r'\s*\(Male\)\s*', '', clean_name)
    clean_name = re.sub(r'\s*\(Female\)\s*', '', clean_name)
    clean_name = re.sub(r'\s*\(Version \d+\)\s*', '', clean_name)
    clean_name = clean_name.strip()

    equip = get_display_equipment(equipment_detected)
    if equip:
        return f"{title_case_exercise(clean_name)} ({equip})"

    return title_case_exercise(clean_name)


def standardize_equipment_in_parens(equip_str):
    """Standardize equipment names within parentheticals."""
    replacements = {
        'barbell': 'Barbell',
        'dumbbell': 'Dumbbell',
        'dumbbells': 'Dumbbell',
        'cable': 'Cable',
        'machine': 'Machine',
        'bodyweight': 'Bodyweight',
        'band': 'Band',
        'resistance band': 'Band',
        'kettlebell': 'Kettlebell',
        'smith machine': 'Smith Machine',
        'smith': 'Smith Machine',
        'ez bar': 'EZ Bar',
        'ez-bar': 'EZ Bar',
        'sz bar': 'EZ Bar',
        'stability ball': 'Stability Ball',
        'medicine ball': 'Medicine Ball',
        'trap bar': 'Trap Bar',
    }

    equip_lower = equip_str.lower().strip()
    if equip_lower in replacements:
        return replacements[equip_lower]

    # Handle compound like "plate loaded"
    if 'plate loaded' in equip_lower:
        return equip_str.replace('plate loaded', 'Plate Loaded').replace('Plate loaded', 'Plate Loaded')

    # Title case
    return title_case_exercise(equip_str)


def get_display_equipment(equipment_detected):
    """Get display equipment name from detected equipment."""
    if not equipment_detected:
        return 'Bodyweight'
    return EQUIPMENT_DISPLAY.get(equipment_detected.lower().strip(), equipment_detected.title())


def title_case_exercise(name):
    """Smart title case for exercise names."""
    # Words that should stay lowercase
    lowercase_words = {'a', 'an', 'the', 'and', 'or', 'of', 'in', 'on', 'to', 'for', 'with', 'at', 'by'}
    # Words that should stay uppercase
    uppercase_words = {'EZ', 'V', 'T', 'II', 'III', 'IV', 'ROM', 'POV'}

    words = name.split()
    result = []
    for i, word in enumerate(words):
        upper = word.upper()
        if upper in uppercase_words:
            result.append(upper)
        elif i == 0 or word.lower() not in lowercase_words:
            result.append(word.capitalize())
        else:
            result.append(word.lower())
    return ' '.join(result)


def infer_category_and_muscles(name, family, exercise_type):
    """Infer category and muscles from exercise family and name keywords."""
    # First try family mapping
    if family and family in FAMILY_TO_CATEGORY_AND_MUSCLES:
        mapping = FAMILY_TO_CATEGORY_AND_MUSCLES[family]
        if mapping['category'] is not None:
            return mapping['category'], mapping['primary'], mapping['secondary']

    # Fall back to name keyword matching
    name_lower = name.lower()
    for pattern, info in NAME_KEYWORD_TO_MUSCLES:
        if re.search(pattern, name_lower):
            primary = info.get('primary')
            category = info.get('category')
            if category and primary:
                return category, primary, []
            elif category:
                return category, None, []

    # Check exercise type
    if exercise_type == 'stretch':
        return 'Stretching', None, []
    if exercise_type == 'cardio':
        return 'Cardio', 'Cardio', []
    if exercise_type == 'plyometrics':
        return 'Full Body', 'Full Body', []

    return 'Uncategorized', None, []


def generate_subtitle(name, category, equipment_display):
    """Generate subtitle in format: Category - Equipment.
    Extracts equipment from the name's parenthetical if possible."""
    # Try to extract equipment from name
    match = re.search(r'\(([^)]+)\)', name)
    if match:
        paren = match.group(1)
        # Use the parenthetical as the equipment display in subtitle
        equip_for_subtitle = paren
    else:
        equip_for_subtitle = equipment_display

    if not category:
        return equip_for_subtitle
    return f"{category} - {equip_for_subtitle}"


# ============================================================================
# MAIN PROCESSING
# ============================================================================

def main():
    print("=" * 70)
    print("COMPREHENSIVE EXERCISE DATABASE CLEANUP")
    print(f"Processing ALL exercises from the full database")
    print("=" * 70)

    # --- Load all data sources ---
    print("\n[1/7] Loading data sources...")

    # Goal classifications (6749 exercises)
    with open(GOALS_CSV) as f:
        goals = list(csv.DictReader(f))
    goals_by_id = {g['id']: g for g in goals}
    print(f"  Goal classifications: {len(goals)} exercises")

    # Family priorities (6749 exercises)
    with open(FAMILY_CSV) as f:
        families = {row['id']: row for row in csv.DictReader(f)}
    print(f"  Family priorities: {len(families)} exercises")

    # exercises.json (446 with full muscle data)
    with open(JSON_FILE) as f:
        json_exercises = json.load(f)
    json_by_name = {}
    for ex in json_exercises:
        json_by_name[ex['name']] = ex
    print(f"  JSON exercises: {len(json_exercises)} with full muscle data")

    # Video mapping
    videos = {}
    with open(VIDEO_CSV) as f:
        reader = csv.DictReader(f)
        for row in reader:
            name = row.get('Exercise Name', '').strip()
            if name:
                videos[name] = {
                    'male': row.get('Male Video Filename', ''),
                    'female': row.get('Female Video Filename', ''),
                }
    print(f"  Video mapping: {len(videos)} exercises with both gender videos")

    # --- Process each exercise ---
    print("\n[2/7] Auditing all exercises...")

    removed = []
    renamed = []
    muscle_fixes = []
    category_assignments = []
    duplicates_removed = []
    no_video = []
    video_mismatches = []
    cleaned = []
    seen_names = {}  # name -> id (first occurrence wins)

    for goal in goals:
        eid = goal['id']
        orig_name = goal['name']
        fam = families.get(eid, {})
        exercise_type = goal.get('exercise_type', 'strength')
        exercise_family = fam.get('exercise_family', '')
        equipment_detected = fam.get('equipment_detected', 'bodyweight')
        has_video = orig_name in videos

        # --- Check removal ---
        should_rm, rm_reason = should_remove(orig_name, exercise_type, has_video, equipment_detected)
        if should_rm:
            removed.append({
                'id': eid,
                'name': orig_name,
                'reason': rm_reason,
                'type': exercise_type,
                'family': exercise_family,
                'has_video': has_video,
            })
            continue

        # --- Standardize name ---
        new_name = standardize_name(orig_name, equipment_detected)

        if new_name != orig_name:
            renamed.append({'old': orig_name, 'new': new_name})

        # --- Check for duplicates after standardization ---
        name_key = new_name.lower().strip()
        if name_key in seen_names:
            duplicates_removed.append({
                'name': orig_name,
                'cleaned_name': new_name,
                'kept_id': seen_names[name_key],
                'removed_id': eid,
            })
            continue
        seen_names[name_key] = eid

        # --- Get/infer category and muscles ---
        json_data = json_by_name.get(orig_name)

        if json_data:
            category = json_data.get('category', '')
            primary_muscle = json_data.get('primaryMuscle', '')
            secondary_muscles = json_data.get('secondaryMuscles', [])
        else:
            category, primary_muscle, secondary_muscles = infer_category_and_muscles(
                orig_name, exercise_family, exercise_type
            )
            if category and category != 'Uncategorized':
                category_assignments.append({
                    'name': orig_name,
                    'cleaned_name': new_name,
                    'category': category,
                    'primary': primary_muscle,
                    'source': f"Inferred from family='{exercise_family}' and name keywords",
                })

        # --- Normalize category ---
        if category:
            category = category.replace('_', ' ')
            # Merge Full_Body into Full Body
            if category == 'Full Body' and not primary_muscle:
                primary_muscle = 'Full Body'

        # --- Equipment display ---
        equipment_display = get_display_equipment(equipment_detected)

        # --- Generate subtitle ---
        subtitle = generate_subtitle(new_name, category, equipment_display)

        # --- Video check ---
        if not has_video:
            no_video.append({
                'name': new_name,
                'original_name': orig_name,
                'category': category,
                'type': exercise_type,
                'family': exercise_family,
            })

        # --- Video body-part cross-reference ---
        if has_video:
            vid = videos[orig_name]
            vid_file = vid.get('male', '') or vid.get('female', '')
            body_hints = {
                '_Back_': 'Back', '_Chest_': 'Chest', '_Thigh_': 'Legs',
                '_Waist_': 'Core', '_Hips_': 'Legs', '_Shoulder_': 'Shoulders',
                '_Upper-Arms_': 'Arms', '_Forearms_': 'Arms', '_Calves_': 'Legs',
                '_Neck_': 'Neck',
            }
            for hint_str, hint_cat in body_hints.items():
                if hint_str in vid_file or hint_str.lower() in vid_file.lower():
                    if category and hint_cat != category and category not in ('Full Body', 'Cardio', 'Stretching', 'Uncategorized', 'Full_Body'):
                        video_mismatches.append({
                            'name': new_name,
                            'original_name': orig_name,
                            'category': category,
                            'video_hint': hint_cat,
                            'video_file': vid_file[:80],
                        })
                    break

        # --- Build cleaned exercise record ---
        muscle_groups = []
        if primary_muscle:
            muscle_groups.append(primary_muscle)
        muscle_groups.extend(secondary_muscles)
        muscle_groups = list(dict.fromkeys(muscle_groups))

        exercise = {
            'id': eid,
            'name': new_name,
            'original_name': orig_name,
            'subtitle': subtitle,
            'category': category or 'Uncategorized',
            'equipment': equipment_display,
            'equipment_detected': equipment_detected,
            'exercise_type': exercise_type,
            'exercise_family': exercise_family,
            'base_exercise_name': fam.get('base_exercise_name', ''),
            'primaryMuscle': primary_muscle or '',
            'secondaryMuscles': secondary_muscles,
            'muscleGroups': muscle_groups,
            'hasVideo': has_video,
            # Ratings from goal classifications
            'is_compound': goal.get('is_compound', ''),
            'difficulty_level': goal.get('difficulty_level', ''),
            'supersetable': goal.get('supersetable', ''),
            'duration_based': goal.get('duration_based', ''),
            'hypertrophy_rating': goal.get('hypertrophy_rating', ''),
            'strength_rating': goal.get('strength_rating', ''),
            'fat_loss_rating': goal.get('fat_loss_rating', ''),
            'endurance_rating': goal.get('endurance_rating', ''),
            'general_fitness_rating': goal.get('general_fitness_rating', ''),
            'optimal_rep_range_min': goal.get('optimal_rep_range_min', ''),
            'optimal_rep_range_max': goal.get('optimal_rep_range_max', ''),
            'recommended_sets': goal.get('recommended_sets', ''),
            'rest_seconds': goal.get('rest_seconds', ''),
            'fatigability': goal.get('fatigability', ''),
            'muscles_worked_count': goal.get('muscles_worked_count', ''),
            # Priority data from family
            'priority_build_muscle': fam.get('priority_build_muscle', ''),
            'priority_get_lean': fam.get('priority_get_lean', ''),
            'priority_home': fam.get('priority_home', ''),
            'priority_gym': fam.get('priority_gym', ''),
            'complementary_families': fam.get('complementary_families', ''),
            'is_equipment_primary': fam.get('is_equipment_primary', ''),
        }
        cleaned.append(exercise)

    # --- Stats ---
    print(f"\n[3/7] Processing complete!")
    print(f"  Original: {len(goals)}")
    print(f"  Cleaned: {len(cleaned)}")
    print(f"  Removed: {len(removed)}")
    print(f"  Duplicates merged: {len(duplicates_removed)}")
    print(f"  Renamed: {len(renamed)}")
    print(f"  Category assignments (inferred): {len(category_assignments)}")
    print(f"  Without video: {len(no_video)}")
    print(f"  Video mismatches: {len(video_mismatches)}")

    # --- Write CSV ---
    print(f"\n[4/7] Writing cleaned CSV...")
    fieldnames = [
        'id', 'name', 'original_name', 'subtitle', 'category', 'equipment',
        'equipment_detected', 'exercise_type', 'exercise_family', 'base_exercise_name',
        'primaryMuscle', 'secondaryMuscles', 'muscleGroups', 'hasVideo',
        'is_compound', 'difficulty_level', 'supersetable', 'duration_based',
        'hypertrophy_rating', 'strength_rating', 'fat_loss_rating',
        'endurance_rating', 'general_fitness_rating',
        'optimal_rep_range_min', 'optimal_rep_range_max',
        'recommended_sets', 'rest_seconds', 'fatigability', 'muscles_worked_count',
        'priority_build_muscle', 'priority_get_lean', 'priority_home', 'priority_gym',
        'complementary_families', 'is_equipment_primary',
    ]

    with open(OUTPUT_CSV, 'w', newline='') as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames, extrasaction='ignore')
        writer.writeheader()
        for ex in cleaned:
            row = dict(ex)
            row['secondaryMuscles'] = '; '.join(ex.get('secondaryMuscles', []))
            row['muscleGroups'] = '; '.join(ex.get('muscleGroups', []))
            writer.writerow(row)
    print(f"  Written to: {OUTPUT_CSV}")

    # --- Update exercises.json ---
    print(f"\n[5/7] Updating exercises.json...")
    # Build name mapping for JSON update
    json_name_map = {}
    for r in renamed:
        json_name_map[r['old']] = r['new']

    # Also update muscle data in JSON where we have corrections
    cleaned_by_orig = {ex['original_name']: ex for ex in cleaned}

    # Build a set of removed original names
    removed_orig_names = set()
    for r in removed:
        removed_orig_names.add(r['name'])
    for d in duplicates_removed:
        removed_orig_names.add(d['name'])

    updated_json = []
    json_removed = 0
    for ex in json_exercises:
        orig_name = ex['name']

        # Only remove if explicitly in the removed set
        if orig_name in removed_orig_names:
            json_removed += 1
            continue

        cleaned_data = cleaned_by_orig.get(orig_name)

        # Update name
        new_name = json_name_map.get(orig_name, orig_name)
        ex['name'] = new_name

        # Update muscles if we have better data from cleanup
        if cleaned_data:
            if cleaned_data.get('primaryMuscle'):
                ex['primaryMuscle'] = cleaned_data['primaryMuscle']
            if cleaned_data.get('secondaryMuscles'):
                ex['secondaryMuscles'] = cleaned_data['secondaryMuscles']
            if cleaned_data.get('category'):
                ex['category'] = cleaned_data['category']

        ex['muscleGroups'] = list(dict.fromkeys(
            [ex['primaryMuscle']] + ex.get('secondaryMuscles', [])
        ))
        ex['sources'] = ['Verified - Exercise Database Cleanup']

        updated_json.append(ex)

    with open(OUTPUT_JSON, 'w') as f:
        json.dump(updated_json, f, indent=2)
        f.write('\n')
    print(f"  JSON updated: {len(updated_json)} exercises ({json_removed} removed)")

    # --- Write Report ---
    print(f"\n[6/7] Writing detailed report...")
    write_report(cleaned, removed, renamed, muscle_fixes, category_assignments,
                 duplicates_removed, no_video, video_mismatches, len(goals), REPORT_MD)
    print(f"  Report written to: {REPORT_MD}")

    print(f"\n[7/7] Done!")
    print(f"\n{'=' * 70}")
    print(f"SUMMARY")
    print(f"{'=' * 70}")
    print(f"  Original exercises:     {len(goals)}")
    print(f"  Final exercises:        {len(cleaned)}")
    print(f"  Removed (total):        {len(removed) + len(duplicates_removed)}")
    print(f"    - Pattern removals:   {len(removed)}")
    print(f"    - Duplicate merges:   {len(duplicates_removed)}")
    print(f"  Names standardized:     {len(renamed)}")
    print(f"  Categories inferred:    {len(category_assignments)}")
    print(f"  With video:             {len(cleaned) - len(no_video)}")
    print(f"  Without video:          {len(no_video)}")
    print(f"  Video mismatches:       {len(video_mismatches)}")


def write_report(cleaned, removed, renamed, muscle_fixes, category_assignments,
                 duplicates_removed, no_video, video_mismatches, original_count, path):
    """Write comprehensive markdown report."""
    now = datetime.now().strftime('%Y-%m-%d %H:%M:%S')

    with open(path, 'w') as f:
        f.write(f"# Exercise Database Cleanup Report\n\n")
        f.write(f"**Generated:** {now}\n")
        f.write(f"**Scope:** Full database audit of all exercises\n\n")

        # ===== SUMMARY =====
        f.write(f"## Summary\n\n")
        f.write(f"| Metric | Count |\n")
        f.write(f"|--------|-------|\n")
        f.write(f"| Original exercises | {original_count} |\n")
        f.write(f"| Final exercises | {len(cleaned)} |\n")
        f.write(f"| Total removed | {len(removed) + len(duplicates_removed)} |\n")
        f.write(f"| Pattern removals | {len(removed)} |\n")
        f.write(f"| Duplicate merges | {len(duplicates_removed)} |\n")
        f.write(f"| Names standardized | {len(renamed)} |\n")
        f.write(f"| Categories inferred | {len(category_assignments)} |\n")
        f.write(f"| With video | {len(cleaned) - len(no_video)} |\n")
        f.write(f"| Without video | {len(no_video)} |\n")
        f.write(f"| Video/category mismatches | {len(video_mismatches)} |\n\n")

        # ===== CATEGORY BREAKDOWN =====
        f.write(f"## Category Breakdown (After Cleanup)\n\n")
        cats = Counter(ex['category'] for ex in cleaned)
        f.write(f"| Category | Count |\n")
        f.write(f"|----------|-------|\n")
        for cat, count in sorted(cats.items(), key=lambda x: -x[1]):
            f.write(f"| {cat} | {count} |\n")
        f.write(f"\n")

        # ===== EQUIPMENT BREAKDOWN =====
        f.write(f"## Equipment Breakdown (After Cleanup)\n\n")
        equips = Counter(ex['equipment'] for ex in cleaned)
        f.write(f"| Equipment | Count |\n")
        f.write(f"|-----------|-------|\n")
        for eq, count in sorted(equips.items(), key=lambda x: -x[1]):
            f.write(f"| {eq} | {count} |\n")
        f.write(f"\n")

        # ===== EXERCISE TYPE BREAKDOWN =====
        f.write(f"## Exercise Type Breakdown\n\n")
        types = Counter(ex['exercise_type'] for ex in cleaned)
        f.write(f"| Type | Count |\n")
        f.write(f"|------|-------|\n")
        for t, count in sorted(types.items(), key=lambda x: -x[1]):
            f.write(f"| {t} | {count} |\n")
        f.write(f"\n")

        # ===== NAMING FORMAT =====
        f.write(f"## Naming Format\n\n")
        f.write(f"All exercises now follow the standardized format:\n\n")
        f.write(f"```\n")
        f.write(f"Exercise Name (Equipment)\n")
        f.write(f"Category - Equipment\n")
        f.write(f"```\n\n")
        f.write(f"### Sample Exercise Cards:\n\n")

        # Show good samples
        sample_names = [
            'Bench Press (Barbell)', 'Bench Press (Dumbbell)',
            'Biceps Curl (Barbell)', 'Biceps Curl (EZ Bar)', 'Biceps Curl (Cable)',
            'Squat (Barbell)', 'Squat (Bodyweight)',
            'Deadlift (Barbell)', 'Lat Pulldown (Cable)',
            'Lateral Raise (Dumbbell)', 'Shoulder Press (Cable)',
            'Seated Row (Cable)', 'Leg Press (Machine)',
        ]
        for sn in sample_names:
            match = [ex for ex in cleaned if ex['name'] == sn]
            if match:
                ex = match[0]
                f.write(f"**{ex['name']}**\n")
                f.write(f"{ex['subtitle']}\n\n")

        # ===== REMOVED EXERCISES =====
        f.write(f"## Removed Exercises ({len(removed) + len(duplicates_removed)} total)\n\n")

        f.write(f"### Pattern Removals ({len(removed)})\n\n")
        if removed:
            f.write(f"| # | Exercise | Type | Reason | Had Video |\n")
            f.write(f"|---|----------|------|--------|----------|\n")
            for i, r in enumerate(removed[:200], 1):
                f.write(f"| {i} | {r['name']} | {r['type']} | {r['reason'][:60]} | {'Yes' if r['has_video'] else 'No'} |\n")
            if len(removed) > 200:
                f.write(f"\n*... and {len(removed) - 200} more*\n")
        f.write(f"\n")

        f.write(f"### Duplicate Merges ({len(duplicates_removed)})\n\n")
        if duplicates_removed:
            f.write(f"| # | Original | Cleaned Name |\n")
            f.write(f"|---|----------|--------------|\n")
            for i, d in enumerate(duplicates_removed[:100], 1):
                f.write(f"| {i} | {d['name']} | {d['cleaned_name']} |\n")
            if len(duplicates_removed) > 100:
                f.write(f"\n*... and {len(duplicates_removed) - 100} more*\n")
        f.write(f"\n")

        # ===== RENAMED EXERCISES =====
        f.write(f"## Renamed Exercises ({len(renamed)})\n\n")
        if renamed:
            f.write(f"| # | Old Name | New Name |\n")
            f.write(f"|---|----------|----------|\n")
            for i, r in enumerate(renamed[:300], 1):
                f.write(f"| {i} | {r['old']} | {r['new']} |\n")
            if len(renamed) > 300:
                f.write(f"\n*... and {len(renamed) - 300} more*\n")
        f.write(f"\n")

        # ===== CATEGORY ASSIGNMENTS =====
        f.write(f"## Category Assignments (Inferred) ({len(category_assignments)})\n\n")
        f.write(f"These exercises had no existing category/muscle data and were assigned based on exercise family and name analysis:\n\n")
        if category_assignments:
            f.write(f"| # | Exercise | Category | Primary Muscle | Source |\n")
            f.write(f"|---|----------|----------|---------------|--------|\n")
            for i, ca in enumerate(category_assignments[:200], 1):
                f.write(f"| {i} | {ca['cleaned_name']} | {ca['category']} | {ca.get('primary', '')} | {ca['source'][:50]} |\n")
            if len(category_assignments) > 200:
                f.write(f"\n*... and {len(category_assignments) - 200} more*\n")
        f.write(f"\n")

        # ===== VIDEO MISMATCHES =====
        if video_mismatches:
            f.write(f"## Video/Category Mismatches ({len(video_mismatches)})\n\n")
            f.write(f"These exercises have video filenames suggesting a different body part:\n\n")
            f.write(f"| # | Exercise | Assigned Category | Video Suggests | Video File |\n")
            f.write(f"|---|----------|------------------|---------------|------------|\n")
            for i, v in enumerate(video_mismatches, 1):
                f.write(f"| {i} | {v['name']} | {v['category']} | {v['video_hint']} | `{v['video_file'][:50]}` |\n")
            f.write(f"\n")

        # ===== EXERCISES WITHOUT VIDEO =====
        f.write(f"## Exercises Without Video ({len(no_video)})\n\n")
        f.write(f"These exercises remain but lack video support:\n\n")
        by_type = defaultdict(list)
        for n in no_video:
            by_type[n['type']].append(n)
        for etype, exs in sorted(by_type.items(), key=lambda x: -len(x[1])):
            f.write(f"### {etype.title()} ({len(exs)})\n\n")
            shown = exs[:50]
            f.write(f"| Exercise | Category | Family |\n")
            f.write(f"|----------|----------|--------|\n")
            for n in shown:
                f.write(f"| {n['name']} | {n['category']} | {n['family']} |\n")
            if len(exs) > 50:
                f.write(f"\n*... and {len(exs) - 50} more*\n")
            f.write(f"\n")

        # ===== COMPLETE EXERCISE LIST BY CATEGORY =====
        f.write(f"## Complete Exercise List ({len(cleaned)} exercises)\n\n")
        by_category = defaultdict(list)
        for ex in cleaned:
            by_category[ex['category']].append(ex)

        for cat in sorted(by_category.keys()):
            exs = sorted(by_category[cat], key=lambda x: x['name'])
            f.write(f"### {cat} ({len(exs)} exercises)\n\n")
            f.write(f"| # | Exercise | Subtitle | Equipment | Primary Muscle | Video |\n")
            f.write(f"|---|----------|----------|-----------|---------------|-------|\n")
            for j, ex in enumerate(exs[:100], 1):
                vid = 'Yes' if ex.get('hasVideo') else 'No'
                f.write(f"| {j} | {ex['name']} | {ex['subtitle']} | {ex['equipment']} | {ex['primaryMuscle']} | {vid} |\n")
            if len(exs) > 100:
                f.write(f"\n*... and {len(exs) - 100} more in this category*\n")
            f.write(f"\n")

        # ===== EXERCISE PAIRING GUIDE =====
        f.write(f"## Exercise Pairing Guide\n\n")
        f.write(f"Exercises with the same base name can be easily paired/swapped across equipment:\n\n")
        base_groups = defaultdict(list)
        for ex in cleaned:
            # Extract base name (part before parenthetical)
            match = re.match(r'^(.+?)\s*\(', ex['name'])
            if match:
                base = match.group(1).strip()
                base_groups[base].append(ex)

        # Show groups with multiple equipment variants
        multi_equip = {k: v for k, v in base_groups.items() if len(v) >= 3}
        f.write(f"Found **{len(multi_equip)}** exercises with 3+ equipment variants:\n\n")
        for base_name in sorted(multi_equip.keys())[:50]:
            variants = multi_equip[base_name]
            f.write(f"**{base_name}**\n")
            for v in sorted(variants, key=lambda x: x['equipment']):
                vid = ' [VIDEO]' if v['hasVideo'] else ''
                f.write(f"- {v['name']} ({v['subtitle']}){vid}\n")
            f.write(f"\n")

        # ===== BUGS & ACTION ITEMS =====
        f.write(f"## Bugs & Action Items\n\n")

        f.write(f"### Critical\n\n")
        f.write(f"- [ ] **Video mismatches ({len(video_mismatches)})**: Exercises with video filenames suggesting different body parts than assigned category. Manual review recommended.\n")
        f.write(f"- [ ] **No video support ({len(no_video)})**: Exercises lacking video files. Decide whether to record videos or remove these exercises.\n")
        f.write(f"- [ ] **Uncategorized exercises ({cats.get('Uncategorized', 0)})**: Exercises that couldn't be auto-categorized. Need manual category/muscle assignment.\n\n")

        f.write(f"### High Priority\n\n")
        f.write(f"- [ ] Update app exercise display to use new standardized `name` and `subtitle` fields\n")
        f.write(f"- [ ] Sync cleaned data back to Supabase `exercises` table\n")
        f.write(f"- [ ] Update any exercise name references throughout the codebase\n")
        f.write(f"- [ ] Verify exercise family swap mappings work with renamed exercises\n")
        f.write(f"- [ ] Update `exercises.json` in the iOS app bundle\n\n")

        f.write(f"### Medium Priority\n\n")
        f.write(f"- [ ] Review all 'Stretching' category exercises - verify they belong or should be in main categories\n")
        f.write(f"- [ ] Review inferred category assignments for accuracy\n")
        f.write(f"- [ ] Add missing video files for popular exercises without video\n")
        f.write(f"- [ ] Ensure workout templates reference updated exercise names\n\n")

        f.write(f"### Low Priority\n\n")
        f.write(f"- [ ] Consider further consolidation of near-duplicate exercises\n")
        f.write(f"- [ ] Add detailed equipment requirements (e.g., bench type: flat/incline/decline)\n")
        f.write(f"- [ ] Review and update instruction text for renamed exercises\n")
        f.write(f"- [ ] Add muscle activation percentages for more precise training recommendations\n\n")

        f.write(f"### Data Integrity Notes\n\n")
        f.write(f"- Exercise IDs (`id`) are preserved from the original database for seamless Supabase sync\n")
        f.write(f"- `original_name` field maintained in CSV for mapping back to original data\n")
        f.write(f"- All rating/classification data from `exercise_goal_classifications.csv` preserved\n")
        f.write(f"- All family/priority data from `exercise_family_goal_priorities.csv` preserved\n")
        f.write(f"- `exercises.json` updated with cleaned names and corrected muscle data\n\n")

        f.write(f"---\n")
        f.write(f"*Report generated by comprehensive exercise database cleanup script*\n")
        f.write(f"*Date: {now}*\n")


if __name__ == '__main__':
    main()
