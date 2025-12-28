#!/usr/bin/env python3
"""
Test Joe User Auto-Gen Workout - With New Improvements
Shows what exercises would be recommended with the updated scoring rules.
"""

import sys
import os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from scripts.comprehensive_autogen_audit import (
    UserProfile, Injury, Gender, BodyType, ExperienceLevel, 
    FitnessGoal, WorkoutLocation, fetch_exercises_from_supabase,
    calculate_exercise_score, is_exercise_safe_for_injury,
    is_foundational_exercise, is_risky_exercise, expand_target_muscles
)

def create_joe_profile():
    return UserProfile(
        id=999,
        name="Joe Test",
        age=31,
        gender=Gender.MALE,
        weight_lbs=178,
        height_inches=71,
        body_type=BodyType.MESOMORPH,
        experience_level=ExperienceLevel.ADVANCED,
        fitness_goal=FitnessGoal.BUILD_MUSCLE,
        workout_location=WorkoutLocation.GYM,
        available_equipment=["Barbell", "Dumbbells", "Smith Machine", "Plates", "Cables", "Machines"],
        injuries=[
            Injury("Lower Back", "be_careful", "Lower back sensitivity")
        ],
        workouts_completed=1,  # Foundational mode
        preferred_workout_duration=48,
        available_days_per_week=4,
        notes="Gym user with lower back sensitivity"
    )

def test_improved_workout():
    joe = create_joe_profile()
    
    print("=" * 70)
    print("🏋️ JOE'S IMPROVED WORKOUT RECOMMENDATION")
    print("=" * 70)
    
    print("\n📋 USER PROFILE:")
    print(f"   Name: {joe.name}")
    print(f"   Experience: {joe.experience_level.value}")
    print(f"   Workouts Completed: {joe.workouts_completed} (FOUNDATIONAL MODE)")
    print(f"   Goal: {joe.fitness_goal.value}")
    print(f"   Equipment: {', '.join(joe.available_equipment)}")
    print(f"   ⚠️ Limitation: {joe.injuries[0].area} - {joe.injuries[0].severity}")
    
    print("\n🎯 WORKOUT REQUEST:")
    print(f"   Primary Muscles: Shoulders, Chest")
    print(f"   Focus: Upper Chest")
    print(f"   Duration: ~48 minutes (6 exercises)")
    
    # Target muscles (from the logs)
    target_muscles = ["Shoulders", "Chest", "Front Delts", "Upper Chest"]
    
    # Fetch exercises
    print("\n📡 Fetching exercises...")
    all_exercises = fetch_exercises_from_supabase()
    print(f"   Total in library: {len(all_exercises)}")
    
    # Filter for relevant exercises with gym equipment
    gym_equip_keywords = ['machine', 'cable', 'dumbbell', 'barbell', 'lever', 'bench', 'smith']
    expanded_targets = expand_target_muscles(target_muscles)
    
    relevant_exercises = []
    for ex in all_exercises:
        name = ex.get('name', '').lower()
        primary = ex.get('primary_muscles', [])
        if isinstance(primary, str):
            primary = [primary]
        primary_lower = [m.lower() for m in primary if m]
        equipment = ex.get('equipment', '').lower()
        workout_type = ex.get('workout_type', '').lower()
        
        # Skip stretches
        if workout_type == 'stretch' or 'stretch' in name:
            continue
        
        # Check muscle match
        muscle_match = any(
            any(t in pm or pm in t for t in expanded_targets)
            for pm in primary_lower
        )
        
        # Check equipment match
        equip_match = any(eq in equipment for eq in gym_equip_keywords)
        
        if muscle_match and equip_match:
            # Safety check
            is_safe, _ = is_exercise_safe_for_injury(name, equipment, primary, joe.injuries)
            if is_safe:
                relevant_exercises.append(ex)
    
    print(f"   Relevant exercises (gym, chest/shoulders, safe): {len(relevant_exercises)}")
    
    # Score all exercises
    scored = []
    for ex in relevant_exercises:
        score = calculate_exercise_score(ex, joe, target_muscles, [])
        scored.append((score, ex))
    
    # Sort by score
    scored.sort(key=lambda x: -x[0])
    
    # Get top exercises
    print("\n" + "=" * 70)
    print("✅ TOP 6 RECOMMENDED EXERCISES (After Improvements)")
    print("=" * 70)
    
    selected = []
    used_families = set()
    
    for score, ex in scored:
        if len(selected) >= 6:
            break
            
        name = ex.get('name', '')
        name_lower = name.lower()
        equipment = ex.get('equipment', '')
        primary = ex.get('primary_muscles', [])
        
        # Simple family detection to avoid duplicates
        family = "other"
        if "incline" in name_lower and "press" in name_lower:
            family = "incline_press"
        elif "bench press" in name_lower:
            family = "bench_press"
        elif "shoulder press" in name_lower or "overhead press" in name_lower:
            family = "shoulder_press"
        elif "lateral raise" in name_lower or "side raise" in name_lower:
            family = "lateral_raise"
        elif "face pull" in name_lower:
            family = "face_pull"
        elif "rear delt" in name_lower or "reverse fly" in name_lower:
            family = "rear_delt"
        elif "fly" in name_lower:
            family = "fly"
        elif "dip" in name_lower:
            family = "dip"
        elif "push" in name_lower:
            family = "pushup"
        
        # Allow max 1 per family for variety
        if family != "other" and family in used_families:
            continue
        
        used_families.add(family)
        selected.append((score, ex))
    
    # Print results
    for i, (score, ex) in enumerate(selected, 1):
        name = ex.get('name', '')
        equipment = ex.get('equipment', '')
        primary = ex.get('primary_muscles', [])
        if isinstance(primary, str):
            primary = [primary]
        
        # Determine why this was selected
        reasons = []
        name_lower = name.lower()
        
        if 'incline' in name_lower:
            reasons.append("✅ Upper Chest Focus")
        if 'lateral raise' in name_lower or 'side raise' in name_lower:
            reasons.append("✅ Lateral Delt (better ROI)")
        if 'face pull' in name_lower or 'rear delt' in name_lower or 'reverse fly' in name_lower:
            reasons.append("✅ Shoulder Balance")
        if 'seated' in name_lower or 'machine' in equipment.lower() or 'lever' in equipment.lower():
            reasons.append("✅ Back-Safe")
        if is_foundational_exercise(name):
            reasons.append("✅ Foundational")
        
        print(f"\n{i}. {name}")
        print(f"   Equipment: {equipment}")
        print(f"   Primary: {', '.join(primary)}")
        print(f"   Score: {score:.0f}")
        if reasons:
            print(f"   Why: {' | '.join(reasons)}")
    
    # Show what was avoided
    print("\n" + "=" * 70)
    print("🚫 EXERCISES CORRECTLY AVOIDED")
    print("=" * 70)
    
    avoided = []
    for score, ex in scored:
        name = ex.get('name', '').lower()
        if score < -100:
            reason = []
            if 'bench dip' in name:
                reason.append("Shoulder impingement risk")
            if 'twisting' in name or 'rotating' in name:
                reason.append("Rotation under load (back risk)")
            if 'front raise' in name:
                reason.append("Redundant front delt work")
            if 'decline' in name:
                reason.append("Lower chest (not upper)")
            if is_risky_exercise(name):
                reason.append("Risky/complex exercise")
            
            if reason:
                avoided.append((ex.get('name', ''), reason))
    
    for name, reasons in avoided[:8]:
        print(f"   ❌ {name}")
        print(f"      Reason: {', '.join(reasons)}")
    
    print("\n" + "=" * 70)
    print("📊 WORKOUT ANALYSIS")
    print("=" * 70)
    
    incline_count = sum(1 for _, ex in selected if 'incline' in ex.get('name', '').lower())
    lateral_count = sum(1 for _, ex in selected if 'lateral' in ex.get('name', '').lower() or 'side raise' in ex.get('name', '').lower())
    rear_delt_count = sum(1 for _, ex in selected if 'rear delt' in ex.get('name', '').lower() or 'face pull' in ex.get('name', '').lower() or 'reverse fly' in ex.get('name', '').lower())
    seated_count = sum(1 for _, ex in selected if 'seated' in ex.get('name', '').lower() or 'machine' in ex.get('equipment', '').lower() or 'lever' in ex.get('equipment', '').lower())
    
    print(f"   Incline exercises (upper chest): {incline_count}")
    print(f"   Lateral raises (side delts): {lateral_count}")
    print(f"   Rear delt/Face pulls (balance): {rear_delt_count}")
    print(f"   Seated/Machine (back-safe): {seated_count}")
    
    front_raise_count = sum(1 for _, ex in selected if 'front raise' in ex.get('name', '').lower())
    bench_dip_count = sum(1 for _, ex in selected if 'bench dip' in ex.get('name', '').lower())
    decline_count = sum(1 for _, ex in selected if 'decline' in ex.get('name', '').lower())
    
    if front_raise_count == 0 and bench_dip_count == 0 and decline_count == 0:
        print("\n   ✅ No front raises (redundant)")
        print("   ✅ No bench dips (shoulder risk)")  
        print("   ✅ No decline exercises (upper chest focus)")

if __name__ == "__main__":
    test_improved_workout()
