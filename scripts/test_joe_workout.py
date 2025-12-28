#!/usr/bin/env python3
"""
Test Joe User Auto-Gen Workout
Simulates exact app flow for:
- User: Joe (Beginner, Build Muscle, Gym)
- Limitation: Lower Back - "be_careful"
- Duration: 45 min
- Target: Chest > Lower Chest
- Equipment: Full gym (Machines, Cables, Dumbbells, Barbell)
"""

import sys
import os

# Add parent dir to path for imports
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from scripts.comprehensive_autogen_audit import (
    UserProfile, Injury, Gender, BodyType, ExperienceLevel, 
    FitnessGoal, WorkoutLocation, select_exercises_for_workout,
    calculate_exercise_score, is_exercise_safe_for_injury,
    apply_metadata_limitation_filter, classify_exercise_metadata,
    get_injury_exercise_penalties, LimitationSeverity,
    fetch_exercises_from_supabase
)
from typing import List, Dict
import json

def create_joe_profile() -> UserProfile:
    """Create the Joe user profile with lower back limitation"""
    return UserProfile(
        id=999,
        name="Joe",
        age=35,
        gender=Gender.MALE,
        weight_lbs=180,
        height_inches=70,
        body_type=BodyType.MESOMORPH,
        experience_level=ExperienceLevel.BEGINNER,
        fitness_goal=FitnessGoal.BUILD_MUSCLE,
        workout_location=WorkoutLocation.GYM,
        available_equipment=["Machines", "Cables", "Dumbbells", "Barbell"],
        injuries=[
            Injury("Lower Back", "be_careful", "User reported lower back sensitivity")
        ],
        workouts_completed=15,  # Some experience but still foundational
        preferred_workout_duration=45,
        available_days_per_week=4,
        notes="Gym user with lower back sensitivity - test case for limitation filtering"
    )

def generate_joe_workout():
    """Generate workout for Joe - 45min, Chest > Lower Chest"""
    
    print("=" * 70)
    print("🏋️ JOE'S AUTO-GEN WORKOUT TEST")
    print("=" * 70)
    
    # Create Joe's profile
    joe = create_joe_profile()
    
    print("\n📋 USER PROFILE:")
    print(f"   Name: {joe.name}")
    print(f"   Age: {joe.age}")
    print(f"   Experience: {joe.experience_level.value}")
    print(f"   Goal: {joe.fitness_goal.value}")
    print(f"   Location: {joe.workout_location.value}")
    print(f"   Equipment: {', '.join(joe.available_equipment)}")
    print(f"   Workouts Completed: {joe.workouts_completed}")
    print(f"   ⚠️ Limitations: {joe.injuries[0].area} - {joe.injuries[0].severity}")
    
    print("\n🎯 WORKOUT REQUEST:")
    print(f"   Duration: 45 minutes")
    print(f"   Primary Target: Chest")
    print(f"   Focus Area: Lower Chest")
    print(f"   Exercise Count: 7 (based on 45 min)")
    
    # Target muscles
    target_muscles = ["Chest", "Lower Chest"]
    exercise_count = 7  # 45 min workout
    
    # Fetch exercises from database
    print("\n📡 Fetching exercises from database...")
    all_exercises = fetch_exercises_from_supabase()
    
    if not all_exercises:
        print("❌ Failed to fetch exercises from database")
        return
    
    print(f"   Total exercises in library: {len(all_exercises)}")
    
    # Filter for chest exercises with gym equipment
    chest_exercises = []
    for ex in all_exercises:
        name = ex.get('name', '').lower()
        primary = ex.get('primary_muscles', [])
        if isinstance(primary, str):
            primary = [primary]
        primary_lower = [m.lower() for m in primary if m]
        
        equipment = ex.get('equipment', '').lower()
        
        # Check if it targets chest
        is_chest = any('chest' in m or 'pec' in m for m in primary_lower)
        
        # Check equipment match
        has_gym_equip = any(eq.lower() in equipment for eq in ['machine', 'cable', 'dumbbell', 'barbell', 'lever', 'bench'])
        
        if is_chest and has_gym_equip:
            chest_exercises.append(ex)
    
    print(f"   Chest exercises with gym equipment: {len(chest_exercises)}")
    
    # Now apply limitation filtering and scoring
    print("\n🛡️ APPLYING LIMITATION FILTERING:")
    print(f"   Limitation: {joe.injuries[0].area} - {joe.injuries[0].severity}")
    
    safe_exercises = []
    excluded_exercises = []
    
    for ex in chest_exercises:
        name = ex.get('name', '')
        equipment = ex.get('equipment', '')
        primary = ex.get('primary_muscles', [])
        if isinstance(primary, str):
            primary = [primary]
        
        # Check safety using new metadata-driven system
        should_exclude, penalty, reason = apply_metadata_limitation_filter(name, equipment, joe.injuries)
        
        if should_exclude:
            excluded_exercises.append({
                'name': name,
                'reason': reason
            })
        else:
            # Also check legacy system
            is_safe, legacy_reason = is_exercise_safe_for_injury(name, equipment, primary, joe.injuries)
            if not is_safe:
                excluded_exercises.append({
                    'name': name,
                    'reason': legacy_reason
                })
            else:
                # Get metadata for scoring
                metadata = classify_exercise_metadata(name, equipment)
                
                safe_exercises.append({
                    'exercise': ex,
                    'metadata': metadata,
                    'safety_penalty': penalty,
                    'reason': reason if reason else "Safe"
                })
    
    print(f"   Exercises excluded: {len(excluded_exercises)}")
    print(f"   Exercises available: {len(safe_exercises)}")
    
    if excluded_exercises:
        print("\n   🚫 EXCLUDED EXERCISES:")
        for ex in excluded_exercises[:5]:  # Show first 5
            print(f"      • {ex['name']}: {ex['reason']}")
        if len(excluded_exercises) > 5:
            print(f"      ... and {len(excluded_exercises) - 5} more")
    
    # Score exercises
    print("\n📊 SCORING EXERCISES:")
    scored_exercises = []
    
    for item in safe_exercises:
        ex = item['exercise']
        metadata = item['metadata']
        safety_penalty = item['safety_penalty']
        
        name = ex.get('name', '')
        equipment = ex.get('equipment', '')
        
        # Base score
        score = 100.0
        score_breakdown = {}
        
        # Safety penalty/boost from metadata system
        score -= safety_penalty  # Negative penalty = boost
        score_breakdown['safety'] = -safety_penalty
        
        # Machine/Cable boost for gym users
        if metadata.is_machine_supported:
            score += 50
            score_breakdown['machine_support'] = 50
        
        # Chest-supported boost for back issues
        if metadata.is_chest_supported:
            score += 80
            score_breakdown['chest_support'] = 80
        
        # Seated/lying boost for back safety
        if metadata.is_seated or metadata.is_lying:
            score += 30
            score_breakdown['position'] = 30
        
        # Foundational exercise boost for beginner
        foundational_keywords = ['press', 'fly', 'push', 'bench']
        if any(kw in name.lower() for kw in foundational_keywords):
            score += 50
            score_breakdown['foundational'] = 50
        
        # Lower chest focus
        if 'decline' in name.lower() or 'lower' in name.lower():
            score += 40
            score_breakdown['lower_chest'] = 40
        
        # Equipment match
        user_equip = [e.lower() for e in joe.available_equipment]
        if any(ue in equipment.lower() for ue in user_equip):
            score += 30
            score_breakdown['equipment_match'] = 30
        
        scored_exercises.append({
            'name': name,
            'equipment': equipment,
            'primary_muscles': ex.get('primary_muscles', []),
            'score': score,
            'breakdown': score_breakdown,
            'safety_reason': item['reason'],
            'metadata_summary': {
                'spinal_load': metadata.spinal_load.value,
                'is_machine': metadata.is_machine_supported,
                'is_chest_supported': metadata.is_chest_supported,
                'is_seated': metadata.is_seated,
                'is_lying': metadata.is_lying
            }
        })
    
    # Sort by score (highest first)
    scored_exercises.sort(key=lambda x: x['score'], reverse=True)
    
    # Select top exercises
    selected = scored_exercises[:exercise_count]
    
    print(f"\n✅ SELECTED EXERCISES (Top {exercise_count}):")
    print("-" * 70)
    
    for i, ex in enumerate(selected, 1):
        print(f"\n{i}. {ex['name']}")
        print(f"   Equipment: {ex['equipment']}")
        print(f"   Primary: {ex['primary_muscles']}")
        print(f"   Score: {ex['score']:.0f}")
        print(f"   Safety: {ex['safety_reason']}")
        print(f"   Score Breakdown: {ex['breakdown']}")
        print(f"   Metadata: spinal_load={ex['metadata_summary']['spinal_load']}, "
              f"machine={ex['metadata_summary']['is_machine']}, "
              f"chest_supported={ex['metadata_summary']['is_chest_supported']}")
    
    print("\n" + "=" * 70)
    print("📋 FINAL WORKOUT SUMMARY")
    print("=" * 70)
    print(f"User: {joe.name}")
    print(f"Duration: 45 minutes")
    print(f"Target: Chest > Lower Chest")
    print(f"Limitation: {joe.injuries[0].area} ({joe.injuries[0].severity})")
    print(f"\nExercises:")
    for i, ex in enumerate(selected, 1):
        print(f"  {i}. {ex['name']} [{ex['equipment']}] - Score: {ex['score']:.0f}")
    
    # Analysis
    print("\n📊 WORKOUT ANALYSIS:")
    machine_count = sum(1 for ex in selected if ex['metadata_summary']['is_machine'])
    chest_supported_count = sum(1 for ex in selected if ex['metadata_summary']['is_chest_supported'])
    safe_position_count = sum(1 for ex in selected if ex['metadata_summary']['is_seated'] or ex['metadata_summary']['is_lying'])
    
    print(f"   Machine-supported exercises: {machine_count}/{len(selected)}")
    print(f"   Chest-supported exercises: {chest_supported_count}/{len(selected)}")
    print(f"   Safe position (seated/lying): {safe_position_count}/{len(selected)}")
    
    avg_score = sum(ex['score'] for ex in selected) / len(selected)
    print(f"   Average exercise score: {avg_score:.1f}")
    
    # Check for any back-stressing exercises that made it through
    back_stress_keywords = ['bent over', 'deadlift', 'good morning', 'renegade']
    risky_included = [ex for ex in selected if any(kw in ex['name'].lower() for kw in back_stress_keywords)]
    
    if risky_included:
        print(f"\n   ⚠️ WARNING: Potentially back-stressing exercises included:")
        for ex in risky_included:
            print(f"      • {ex['name']}")
    else:
        print(f"\n   ✅ No back-stressing exercises in workout - limitation respected!")
    
    return selected

if __name__ == "__main__":
    generate_joe_workout()
