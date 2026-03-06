#!/usr/bin/env python3
"""
Exercise Difficulty Level Classification Script
================================================
Automatically classifies all exercises with difficulty levels 1-5 based on:
- Exercise name patterns
- Equipment category
- Exercise family
- Is compound flag
- Movement complexity indicators
"""

import os
import load_env  # noqa: F401 — auto-loads .env credentials
import re
import json
from datetime import datetime
from supabase import create_client

# Supabase credentials
SUPABASE_URL = os.environ.get("SUPABASE_URL", "https://ehooeghabzefgoqzugrc.supabase.co")
SUPABASE_KEY = os.environ.get("SUPABASE_ANON_KEY", "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVob29lZ2hhYnplZmdvcXp1Z3JjIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjM4NDc4NjQsImV4cCI6MjA3OTQyMzg2NH0.6-QWDr5B279hybtu9MbPVhmBKlyzFq1GK9P7zlDXuY0")

supabase = create_client(SUPABASE_URL, SUPABASE_KEY)

# ============================================================================
# CLASSIFICATION RULES
# ============================================================================

# Level 5: Elite/Expert exercises (Olympic lifts, gymnastics)
LEVEL_5_PATTERNS = [
    r'\bsnatch\b', r'\bclean\s*(and|&)?\s*jerk\b', r'\bpower\s*clean\b', 
    r'\bhang\s*clean\b', r'\bclean\s*pull\b', r'\bclean\s*deadlift\b',
    r'\bmuscle[\s-]*up\b', r'\bhandstand\s*push[\s-]*up\b', r'\bhandstand\b',
    r'\bplanche\b', r'\biron\s*cross\b', r'\bmaltese\b', r'\bfront\s*lever\b',
    r'\bback\s*lever\b', r'\bl[\s-]*sit\b', r'\bv[\s-]*sit\b',
    r'\bone[\s-]*arm\s*pull[\s-]*up\b', r'\bsingle[\s-]*arm\s*pull[\s-]*up\b',
    r'\bolympic\b', r'\bjerk\b',
]

LEVEL_5_FAMILIES = [
    'snatch', 'clean', 'clean_and_jerk', 'power_clean', 'hang_clean',
    'muscle_up', 'handstand_push_up', 'handstand', 'planche', 'front_lever',
    'back_lever', 'l_sit', 'iron_cross',
]

# Level 4: Advanced exercises
LEVEL_4_PATTERNS = [
    r'\bdeficit\b', r'\bpause\b', r'\btempo\b', r'\bweighted\s*(pull|dip|push)\b',
    r'\bpistol\s*squat\b', r'\bnordic\b', r'\bturk(ish)?\s*get[\s-]*up\b',
    r'\bzercher\b', r'\bjefferson\b', r'\bfront\s*squat\b', r'\bsumo\s*deadlift\b',
    r'\bsingle[\s-]*leg\s*(romanian|rdl|deadlift)\b', r'\bsissy\s*squat\b',
    r'\bring\s*(push|dip|row|fly)\b', r'\bexplosive\b', r'\bplyometric\b',
    r'\bbox\s*jump\b', r'\bdepth\s*jump\b', r'\bbroad\s*jump\b',
    r'\bweighted\s*vest\b', r'\bweighted\s*chain\b',
]

LEVEL_4_FAMILIES = [
    'front_squat', 'sumo_deadlift', 'deficit_deadlift', 'pistol_squat',
    'nordic_curl', 'turkish_get_up', 'zercher_squat', 'jefferson_deadlift',
    'ring_dip', 'ring_push_up', 'ring_row', 'box_jump', 'depth_jump',
    'single_leg_deadlift', 'sissy_squat',
]

# Level 1: Beginner exercises (machines, assisted, stretches)
LEVEL_1_PATTERNS = [
    r'\bmachine\b', r'\blever\b', r'\bassisted\b', r'\bsmith\s*machine\b',
    r'\bleg\s*press\b', r'\bleg\s*extension\b', r'\bleg\s*curl\b',
    r'\bchest\s*press\s*machine\b', r'\bshoulder\s*press\s*machine\b',
    r'\blat\s*pulldown\s*machine\b', r'\bcable\s*crossover\s*machine\b',
    r'\bpec\s*deck\b', r'\bpec\s*fly\s*machine\b',
    r'\bstretch\b', r'\byoga\b', r'\bpose\b', r'\bstatic\s*hold\b',
    r'\bwall\s*push[\s-]*up\b', r'\bincline\s*push[\s-]*up\b',
    r'\bknee\s*push[\s-]*up\b', r'\bchair\b',
]

LEVEL_1_FAMILIES = [
    'stretch_shoulder', 'stretch_chest', 'stretch_back', 'stretch_hip',
    'stretch_leg', 'stretch_arm', 'stretch_general', 'stretch_neck',
    'yoga_pose', 'static_hold',
]

# Level 2: Beginner-Intermediate
LEVEL_2_PATTERNS = [
    r'\bseated\s*(dumbbell|db)\b', r'\bseated\s*curl\b', r'\bseated\s*press\b',
    r'\bcable\s*(curl|fly|press|row|extension|pushdown)\b',
    r'\bdumbbell\s*curl\b', r'\bdb\s*curl\b',
    r'\blateral\s*raise\b', r'\bfront\s*raise\b', r'\brear\s*delt\b',
    r'\bgoblet\s*squat\b', r'\bbodyweight\s*squat\b',
    r'\bstandard\s*push[\s-]*up\b', r'\bregular\s*push[\s-]*up\b',
    r'\bplank\b', r'\bcrunch\b', r'\bsit[\s-]*up\b',
]

LEVEL_2_FAMILIES = [
    'bicep_curl', 'hammer_curl', 'concentration_curl', 'preacher_curl',
    'tricep_pushdown', 'tricep_extension', 'lateral_raise', 'front_raise',
    'rear_delt_fly', 'cable_fly', 'goblet_squat', 'plank', 'crunch',
    'sit_up', 'leg_raise', 'russian_twist', 'face_pull',
]

# Equipment category base levels
EQUIPMENT_BASE_LEVELS = {
    'machine': 1,
    'smith_machine': 2,
    'band': 2,
    'cable': 2,
    'dumbbell': 2,
    'kettlebell': 3,
    'barbell': 3,
    'bodyweight': 2,  # Default, adjusted by complexity
}

# Exercise family base levels (overrides equipment when specified)
FAMILY_BASE_LEVELS = {
    # Level 1 families
    'stretch_shoulder': 1, 'stretch_chest': 1, 'stretch_back': 1, 
    'stretch_hip': 1, 'stretch_leg': 1, 'stretch_arm': 1,
    'stretch_general': 1, 'stretch_neck': 1, 'yoga_pose': 1,
    'lat_pulldown': 2, 'leg_extension': 1, 'leg_curl': 1,
    'leg_press': 1, 'chest_press': 2, 'pec_fly': 2,
    
    # Level 2 families
    'bicep_curl': 2, 'hammer_curl': 2, 'concentration_curl': 2,
    'preacher_curl': 2, 'tricep_pushdown': 2, 'tricep_extension': 2,
    'lateral_raise': 2, 'front_raise': 2, 'rear_delt_fly': 2,
    'cable_row': 2, 'face_pull': 2, 'shrug': 2,
    'crunch': 2, 'sit_up': 2, 'plank': 2, 'leg_raise': 2,
    'russian_twist': 2, 'bicycle_crunch': 2, 'dead_bug': 2,
    'goblet_squat': 2, 'push_up': 2, 'dip': 3,
    'glute_bridge': 2, 'hip_thrust': 3, 'calf_raise': 2,
    
    # Level 3 families
    'bench_press': 3, 'incline_bench_press': 3, 'decline_bench_press': 3,
    'shoulder_press': 3, 'overhead_press': 3, 'military_press': 3,
    'squat': 3, 'back_squat': 3, 'deadlift': 3, 'conventional_deadlift': 3,
    'romanian_deadlift': 3, 'bent_over_row': 3, 'barbell_row': 3,
    'pull_up': 3, 'chin_up': 3, 'lunge': 3, 'walking_lunge': 3,
    'skull_crusher': 3, 'close_grip_bench': 3, 'pendlay_row': 3,
    'good_morning': 3, 't_bar_row': 3, 'landmine_press': 3,
    'hack_squat': 3, 'step_up': 3, 'bulgarian_split_squat': 3,
    
    # Level 4 families
    'front_squat': 4, 'sumo_deadlift': 4, 'deficit_deadlift': 4,
    'pistol_squat': 4, 'single_leg_deadlift': 4, 'zercher_squat': 4,
    'pause_squat': 4, 'box_jump': 4, 'turkish_get_up': 4,
    'nordic_curl': 4, 'sissy_squat': 4,
    
    # Level 5 families
    'snatch': 5, 'power_snatch': 5, 'hang_snatch': 5,
    'clean': 5, 'power_clean': 5, 'hang_clean': 5,
    'clean_and_jerk': 5, 'jerk': 5, 'push_jerk': 5, 'split_jerk': 5,
    'muscle_up': 5, 'bar_muscle_up': 5, 'ring_muscle_up': 5,
    'handstand_push_up': 5, 'planche': 5, 'front_lever': 5,
    'back_lever': 5, 'l_sit': 5, 'v_sit': 5,
}


def classify_exercise(exercise):
    """
    Classify a single exercise and return its difficulty level (1-5)
    Returns: (level, reason)
    """
    name = (exercise.get('name') or '').lower()
    family = exercise.get('exercise_family') or ''
    equipment = exercise.get('equipment_category') or 'bodyweight'
    is_compound = exercise.get('is_compound', False)
    category = (exercise.get('category') or '').lower()
    
    reasons = []
    
    # Step 1: Check for Level 5 patterns (Olympic lifts, gymnastics)
    for pattern in LEVEL_5_PATTERNS:
        if re.search(pattern, name, re.IGNORECASE):
            return 5, f"Olympic/Elite pattern: {pattern}"
    
    if family in LEVEL_5_FAMILIES:
        return 5, f"Elite family: {family}"
    
    # Step 2: Check for Level 1 patterns (machines, stretches)
    for pattern in LEVEL_1_PATTERNS:
        if re.search(pattern, name, re.IGNORECASE):
            # Check if it's explicitly a machine
            if 'machine' in name.lower() or 'lever' in name.lower():
                return 1, f"Machine exercise: {pattern}"
            if 'stretch' in name.lower() or 'yoga' in name.lower() or 'pose' in name.lower():
                return 1, f"Stretch/Yoga: {pattern}"
    
    if family in LEVEL_1_FAMILIES:
        return 1, f"Beginner family: {family}"
    
    # Step 3: Check for Level 4 patterns (advanced variations)
    for pattern in LEVEL_4_PATTERNS:
        if re.search(pattern, name, re.IGNORECASE):
            return 4, f"Advanced pattern: {pattern}"
    
    if family in LEVEL_4_FAMILIES:
        return 4, f"Advanced family: {family}"
    
    # Step 4: Start with equipment base level
    base_level = EQUIPMENT_BASE_LEVELS.get(equipment, 2)
    reasons.append(f"Equipment base ({equipment}): {base_level}")
    
    # Step 5: Check family-specific level
    if family in FAMILY_BASE_LEVELS:
        base_level = FAMILY_BASE_LEVELS[family]
        reasons.append(f"Family override ({family}): {base_level}")
    
    # Step 6: Apply modifiers based on name patterns
    modifiers = 0
    
    # Complexity increasers
    if re.search(r'\bsingle[\s-]*(leg|arm)\b', name, re.IGNORECASE):
        modifiers += 1
        reasons.append("+1 single limb")
    
    if re.search(r'\bone[\s-]*(leg|arm)\b', name, re.IGNORECASE):
        modifiers += 1
        reasons.append("+1 one limb")
    
    if re.search(r'\bweighted\b', name, re.IGNORECASE) and equipment == 'bodyweight':
        modifiers += 1
        reasons.append("+1 weighted bodyweight")
    
    if re.search(r'\bexplosive\b|\bjump\b|\bplyo\b', name, re.IGNORECASE):
        modifiers += 1
        reasons.append("+1 explosive/jump")
    
    if re.search(r'\bdeficit\b|\bpause\b|\btempo\b', name, re.IGNORECASE):
        modifiers += 1
        reasons.append("+1 advanced variation")
    
    if re.search(r'\bring\b', name, re.IGNORECASE):
        modifiers += 1
        reasons.append("+1 ring exercise")
    
    if re.search(r'\bhanging\b', name, re.IGNORECASE) and 'leg raise' in name.lower():
        modifiers += 1
        reasons.append("+1 hanging")
    
    # Complexity decreasers
    if re.search(r'\bassisted\b', name, re.IGNORECASE):
        modifiers -= 1
        reasons.append("-1 assisted")
    
    if re.search(r'\bseated\b', name, re.IGNORECASE) and equipment in ['machine', 'cable']:
        modifiers -= 1
        reasons.append("-1 seated machine/cable")
    
    if re.search(r'\bon\s*knees?\b|\bkneeling\b', name, re.IGNORECASE):
        modifiers -= 1
        reasons.append("-1 kneeling variation")
    
    if re.search(r'\bincline\s*push[\s-]*up\b|\bwall\s*push[\s-]*up\b', name, re.IGNORECASE):
        modifiers -= 1
        reasons.append("-1 easier push-up variation")
    
    # Step 7: Compound vs isolation adjustment
    if is_compound and equipment == 'barbell' and base_level < 3:
        base_level = 3
        reasons.append("Barbell compound minimum: 3")
    
    if not is_compound and base_level > 3:
        base_level = 3
        reasons.append("Isolation max: 3")
    
    # Step 8: Calculate final level
    final_level = base_level + modifiers
    
    # Clamp to 1-5 range
    final_level = max(1, min(5, final_level))
    
    return final_level, " | ".join(reasons)


def fetch_all_exercises():
    """Fetch all exercises from Supabase"""
    print("📥 Fetching all exercises...")
    all_exercises = []
    offset = 0
    
    while True:
        response = supabase.table('exercises').select(
            'id, name, exercise_family, equipment_category, is_compound, category, difficulty_level'
        ).range(offset, offset + 999).execute()
        
        if not response.data:
            break
        all_exercises.extend(response.data)
        offset += 1000
        if len(response.data) < 1000:
            break
    
    return all_exercises


def classify_all_exercises(exercises):
    """Classify all exercises and return results"""
    results = []
    
    for ex in exercises:
        level, reason = classify_exercise(ex)
        results.append({
            'id': ex['id'],
            'name': ex['name'],
            'current_level': ex.get('difficulty_level'),
            'new_level': level,
            'reason': reason,
        })
    
    return results


def apply_updates(results):
    """Apply difficulty level updates to database"""
    print("\n📝 Applying updates to database...")
    
    # Group by level for batch updates
    by_level = {1: [], 2: [], 3: [], 4: [], 5: []}
    for r in results:
        by_level[r['new_level']].append(r['id'])
    
    updated = 0
    errors = 0
    
    for level, ids in by_level.items():
        if not ids:
            continue
        
        print(f"   Updating {len(ids)} exercises to Level {level}...")
        
        # Batch update in chunks of 100
        for i in range(0, len(ids), 100):
            chunk = ids[i:i+100]
            try:
                for ex_id in chunk:
                    supabase.table('exercises').update({
                        'difficulty_level': level
                    }).eq('id', ex_id).execute()
                    updated += 1
            except Exception as e:
                print(f"   ❌ Error updating chunk: {e}")
                errors += len(chunk)
    
    return updated, errors


def main():
    print("=" * 80)
    print("🎯 EXERCISE DIFFICULTY LEVEL CLASSIFICATION")
    print("=" * 80)
    print()
    
    # Fetch exercises
    exercises = fetch_all_exercises()
    print(f"✅ Loaded {len(exercises)} exercises")
    
    # Check current state
    has_level = sum(1 for ex in exercises if ex.get('difficulty_level') is not None)
    print(f"   Currently classified: {has_level}/{len(exercises)}")
    print()
    
    # Classify all exercises
    print("🔬 Classifying exercises...")
    results = classify_all_exercises(exercises)
    
    # Distribution summary
    distribution = {1: 0, 2: 0, 3: 0, 4: 0, 5: 0}
    for r in results:
        distribution[r['new_level']] += 1
    
    print("\n" + "=" * 80)
    print("📊 CLASSIFICATION RESULTS")
    print("=" * 80)
    print()
    print("📈 Distribution:")
    for level in range(1, 6):
        count = distribution[level]
        pct = (count / len(results)) * 100
        bar = '█' * int(pct / 2)
        labels = {1: 'Beginner', 2: 'Beginner-Int', 3: 'Intermediate', 4: 'Advanced', 5: 'Elite'}
        print(f"   Level {level} ({labels[level]:15}): {count:4d} ({pct:5.1f}%) {bar}")
    
    # Show samples from each level
    print("\n" + "=" * 80)
    print("📋 SAMPLE EXERCISES BY LEVEL")
    print("=" * 80)
    
    for level in range(1, 6):
        samples = [r for r in results if r['new_level'] == level][:5]
        labels = {1: 'BEGINNER', 2: 'BEGINNER-INT', 3: 'INTERMEDIATE', 4: 'ADVANCED', 5: 'ELITE'}
        print(f"\n🏷️ Level {level}: {labels[level]}")
        for s in samples:
            print(f"   • {s['name'][:50]}")
            print(f"     Reason: {s['reason'][:60]}...")
    
    # Apply updates
    print("\n" + "=" * 80)
    print("💾 APPLYING UPDATES")
    print("=" * 80)
    
    updated, errors = apply_updates(results)
    
    print(f"\n✅ Updated: {updated} exercises")
    if errors:
        print(f"❌ Errors: {errors}")
    
    # Save results to JSON for review
    output_file = 'difficulty_classification_results.json'
    with open(output_file, 'w') as f:
        json.dump({
            'summary': {
                'total': len(results),
                'distribution': distribution,
                'updated': updated,
                'errors': errors,
            },
            'results': results[:500],  # First 500 for review
        }, f, indent=2)
    
    print(f"\n📁 Results saved to: {output_file}")
    print()
    print("=" * 80)
    print("✅ CLASSIFICATION COMPLETE")
    print("=" * 80)


if __name__ == "__main__":
    main()
