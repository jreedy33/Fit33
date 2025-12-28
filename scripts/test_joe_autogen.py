#!/usr/bin/env python3
"""
Test Joe's Auto-Gen Workout
Simulates the exact auto-gen mechanism that would run in the app.

Joe's Profile:
- Lower Back: "be_careful" 
- Goal: Build Muscle
- Foundational mode (newer user)
- Gym equipment

Test Parameters:
- Duration: 45 minutes
- Target: Chest > Lower Chest
- Equipment: Joe's gym equipment
"""

import sys
import os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from scripts.comprehensive_autogen_audit import (
    UserProfile, Injury, Gender, BodyType, ExperienceLevel, 
    FitnessGoal, WorkoutLocation, 
    classify_exercise_metadata, apply_metadata_limitation_filter,
    get_injury_exercise_penalties, is_exercise_safe_for_injury,
    is_foundational_exercise, is_risky_exercise, is_lower_back_stress_exercise,
    is_lower_back_safe_exercise, expand_target_muscles,
    MUSCLE_GROUP_EXPANSION, ALL_FOUNDATIONAL_EXERCISES
)
from supabase import create_client

# Supabase connection
SUPABASE_URL = "https://ehooeghabzefgoqzugrc.supabase.co"
SUPABASE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVob29lZ2hhYnplZmdvcXp1Z3JjIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjM4NDc4NjQsImV4cCI6MjA3OTQyMzg2NH0.6-QWDr5B279hybtu9MbPVhmBKlyzFq1GK9P7zlDXuY0"

# Joe's Profile - matches the logs from earlier
JOE_PROFILE = UserProfile(
    id=99,
    name="Joe",
    age=35,
    gender=Gender.MALE,
    weight_lbs=180,
    height_inches=70,
    body_type=BodyType.MESOMORPH,
    experience_level=ExperienceLevel.BEGINNER,
    fitness_goal=FitnessGoal.BUILD_MUSCLE,
    workout_location=WorkoutLocation.GYM,
    available_equipment=["Machines", "Cables", "Dumbbells", "Barbell", "Bench"],
    injuries=[
        Injury("Lower Back", "be_careful", "Need to be careful with lower back")
    ],
    workouts_completed=15,  # Intermediate foundational - not total beginner
    preferred_workout_duration=45,
    available_days_per_week=4,
    notes="Test user - Build Muscle goal, Lower Back be_careful"
)

def fetch_exercises_from_supabase():
    """Fetch exercises from Supabase (same as app)"""
    try:
        supabase = create_client(SUPABASE_URL, SUPABASE_KEY)
        response = supabase.table("exercises").select("*").execute()
        return response.data
    except Exception as e:
        print(f"❌ Error fetching exercises: {e}")
        return []

def normalize_equipment(equipment: str) -> str:
    """Normalize equipment names"""
    if not equipment:
        return "Bodyweight"
    eq = equipment.lower()
    if "dumbbell" in eq: return "Dumbbells"
    if "barbell" in eq or "ez bar" in eq: return "Barbell"
    if "cable" in eq: return "Cables"
    if "machine" in eq or "lever" in eq: return "Machines"
    if "bench" in eq: return "Bench"
    if "body" in eq or eq == "": return "Bodyweight"
    return equipment

def generate_joe_workout(duration_minutes: int = 45, 
                         primary_muscles: list = ["Chest"],
                         focus_areas: list = ["Lower Chest"]):
    """
    Generate a workout for Joe using the same logic as the app.
    This mirrors WorkoutGeneratorService.generateFromCoreData()
    """
    print("\n" + "🔥"*35)
    print("\n╔══════════════════════════════════════════════════════════════╗")
    print("║            🎯 JOE'S AUTO-GEN WORKOUT TEST                    ║")
    print("╠══════════════════════════════════════════════════════════════╣")
    print(f"║ USER PROFILE:")
    print(f"║   • Name: {JOE_PROFILE.name}")
    print(f"║   • Goal: {JOE_PROFILE.fitness_goal.value}")
    print(f"║   • Experience: {JOE_PROFILE.experience_level.value}")
    print(f"║   • Workouts Completed: {JOE_PROFILE.workouts_completed}")
    print(f"║   • Equipment: {', '.join(JOE_PROFILE.available_equipment)}")
    print(f"║   • Injuries: {[(i.area, i.severity) for i in JOE_PROFILE.injuries]}")
    print("╠══════════════════════════════════════════════════════════════╣")
    print(f"║ WORKOUT REQUEST:")
    print(f"║   • Duration: {duration_minutes} minutes")
    print(f"║   • Primary Muscles: {primary_muscles}")
    print(f"║   • Focus Areas: {focus_areas}")
    print("╠══════════════════════════════════════════════════════════════╣")
    
    # Calculate exercise count based on duration (same as app)
    if duration_minutes <= 20:
        exercise_count = 4
    elif duration_minutes <= 35:
        exercise_count = 5
    elif duration_minutes <= 40:
        exercise_count = 6
    elif duration_minutes <= 50:
        exercise_count = 7
    else:
        exercise_count = 8
    
    print(f"║ Target exercise count: {exercise_count}")
    print("╚══════════════════════════════════════════════════════════════╝")
    
    # Fetch exercises from Supabase
    print("\n📥 Fetching exercises from Supabase...")
    all_exercises = fetch_exercises_from_supabase()
    print(f"   Total exercises in database: {len(all_exercises)}")
    
    if not all_exercises:
        print("❌ No exercises found!")
        return []
    
    # Expand target muscles
    target_muscles = primary_muscles + focus_areas
    expanded_muscles = expand_target_muscles(target_muscles)
    print(f"\n🎯 Target muscles expanded: {expanded_muscles}")
    
    # User equipment normalized
    user_equipment = set(normalize_equipment(eq) for eq in JOE_PROFILE.available_equipment)
    print(f"🔧 User equipment: {user_equipment}")
    
    # Determine if foundational mode is active
    restrict_to_foundational = JOE_PROFILE.workouts_completed < 30
    print(f"\n🌟 Foundational mode: {'ACTIVE' if restrict_to_foundational else 'OFF'}")
    
    # ═══════════════════════════════════════════════════════════════════════════════
    # STEP 1: FILTER EXERCISES (same as app)
    # ═══════════════════════════════════════════════════════════════════════════════
    print("\n" + "="*70)
    print("STEP 1: FILTERING EXERCISES")
    print("="*70)
    
    filtered_exercises = []
    filter_reasons = {
        "muscle_mismatch": 0,
        "equipment_mismatch": 0,
        "injury_unsafe": 0,
        "risky_exercise": 0,
        "lower_back_stress": 0,
        "stretching": 0
    }
    
    for ex in all_exercises:
        name = ex.get('name', '')
        equipment = ex.get('equipment', '')
        category = ex.get('category', '').lower()
        
        # Database uses primary_muscles (array) and secondary_muscles (array)
        primary_muscles_ex = ex.get('primary_muscles', [])
        secondary_muscles_ex = ex.get('secondary_muscles', [])
        if isinstance(primary_muscles_ex, str):
            primary_muscles_ex = [primary_muscles_ex]
        if isinstance(secondary_muscles_ex, str):
            secondary_muscles_ex = [secondary_muscles_ex]
        
        all_muscles_lower = [m.lower() for m in (primary_muscles_ex or []) + (secondary_muscles_ex or []) if m]
        
        # Skip stretching exercises
        if 'stretch' in category or 'stretch' in name.lower():
            filter_reasons["stretching"] += 1
            continue
        
        # Check muscle match - include category in the check
        muscle_match = False
        # Check category match (e.g., "chest" category)
        if category in expanded_muscles:
            muscle_match = True
        # Check direct muscle match
        for muscle in all_muscles_lower:
            for target in expanded_muscles:
                if target in muscle or muscle in target:
                    muscle_match = True
                    break
        
        if not muscle_match:
            filter_reasons["muscle_mismatch"] += 1
            continue
        
        # Check equipment match
        exercise_equip = normalize_equipment(equipment)
        if exercise_equip not in user_equipment and exercise_equip != "Bodyweight":
            filter_reasons["equipment_mismatch"] += 1
            continue
        
        # Check injury safety using new metadata system
        safe, reason = is_exercise_safe_for_injury(name, equipment, primary_muscles_ex or [], JOE_PROFILE.injuries)
        if not safe:
            filter_reasons["injury_unsafe"] += 1
            print(f"   🚫 [INJURY] Excluding '{name}': {reason}")
            continue
        
        # Check risky exercises for foundational users
        if restrict_to_foundational and is_risky_exercise(name):
            filter_reasons["risky_exercise"] += 1
            print(f"   🚫 [RISKY] Excluding '{name}': risky for foundational user")
            continue
        
        # Check lower back stress exercises (Joe has lower back issue)
        if is_lower_back_stress_exercise(name):
            filter_reasons["lower_back_stress"] += 1
            print(f"   🚫 [BACK] Excluding '{name}': stresses lower back")
            continue
        
        filtered_exercises.append(ex)
    
    print(f"\n📊 Filter Results:")
    print(f"   Total exercises: {len(all_exercises)}")
    print(f"   After filtering: {len(filtered_exercises)}")
    print(f"   Filter breakdown: {filter_reasons}")
    
    # ═══════════════════════════════════════════════════════════════════════════════
    # STEP 2: SCORE EXERCISES (same as app)
    # ═══════════════════════════════════════════════════════════════════════════════
    print("\n" + "="*70)
    print("STEP 2: SCORING EXERCISES")
    print("="*70)
    
    scored_exercises = []
    
    for ex in filtered_exercises:
        name = ex.get('name', '')
        equipment = ex.get('equipment', '')
        category = ex.get('category', '')
        primary_muscles_ex = ex.get('primary_muscles', [])
        secondary_muscles_ex = ex.get('secondary_muscles', [])
        
        score = 100.0
        score_breakdown = {}
        
        # 1. Muscle match bonus
        primary_lower = [m.lower() for m in (primary_muscles_ex or []) if m]
        for muscle in primary_lower:
            if "lower chest" in muscle:
                score += 50  # Exact focus match
                score_breakdown["focus_match"] = 50
            elif "chest" in muscle:
                score += 30
                score_breakdown["primary_match"] = 30
        
        # 2. Foundational exercise bonus
        is_foundational = is_foundational_exercise(name)
        if is_foundational:
            foundational_boost = 100 if JOE_PROFILE.workouts_completed < 10 else 50
            score += foundational_boost
            score_breakdown["foundational_boost"] = foundational_boost
        
        # 3. Metadata-driven injury safety scoring (NEW SYSTEM)
        should_exclude, injury_penalty, injury_reason = apply_metadata_limitation_filter(
            name, equipment, JOE_PROFILE.injuries
        )
        if injury_penalty != 0:
            score -= injury_penalty  # Positive penalty = bad
            score_breakdown["injury_safety"] = -injury_penalty
        
        # 4. Lower back safe alternative boost
        if is_lower_back_safe_exercise(name):
            score += 100
            score_breakdown["back_safe_boost"] = 100
        
        # 5. Equipment preference for safety
        equip_lower = (equipment or '').lower()
        if "machine" in equip_lower or "cable" in equip_lower:
            score += 30
            score_breakdown["safe_equipment"] = 30
        
        # 6. Machine preference for beginners
        if JOE_PROFILE.experience_level == ExperienceLevel.BEGINNER:
            if "machine" in equip_lower or "cable" in equip_lower:
                score += 50
                score_breakdown["beginner_machine_boost"] = 50
        
        # 7. Compound exercise bonus for muscle building
        compound_keywords = ["press", "row", "squat", "deadlift", "lunge", "dip", "pull"]
        is_compound = any(kw in name.lower() for kw in compound_keywords)
        if is_compound and JOE_PROFILE.fitness_goal == FitnessGoal.BUILD_MUSCLE:
            score += 40
            score_breakdown["compound_bonus"] = 40
        
        scored_exercises.append({
            "exercise": ex,
            "score": score,
            "breakdown": score_breakdown
        })
    
    # Sort by score descending
    scored_exercises.sort(key=lambda x: x["score"], reverse=True)
    
    # ═══════════════════════════════════════════════════════════════════════════════
    # STEP 3: SELECT TOP EXERCISES (same as app)
    # ═══════════════════════════════════════════════════════════════════════════════
    print("\n" + "="*70)
    print("STEP 3: SELECTING TOP EXERCISES")
    print("="*70)
    
    selected = []
    used_names = set()
    used_equipment = {}
    used_patterns = set()
    
    # Movement pattern detection
    def get_pattern(name):
        name_lower = name.lower()
        if "press" in name_lower and "bench" in name_lower: return "bench_press"
        if "incline" in name_lower and "press" in name_lower: return "incline_press"
        if "decline" in name_lower and "press" in name_lower: return "decline_press"
        if "fly" in name_lower or "flye" in name_lower: return "fly"
        if "dip" in name_lower: return "dip"
        if "push" in name_lower and "up" in name_lower: return "pushup"
        if "crossover" in name_lower: return "crossover"
        if "pullover" in name_lower: return "pullover"
        return "other"
    
    for scored in scored_exercises:
        if len(selected) >= exercise_count:
            break
        
        ex = scored["exercise"]
        name = ex.get('name', '')
        equipment = ex.get('equipment', '')
        
        # Skip duplicates
        if name.lower() in used_names:
            continue
        
        # Equipment diversity (allow max 3 of same equipment type)
        equip_normalized = normalize_equipment(equipment)
        if used_equipment.get(equip_normalized, 0) >= 3:
            continue
        
        # Pattern diversity (allow max 2 of same pattern)
        pattern = get_pattern(name)
        if used_patterns.get(pattern, 0) >= 2 if isinstance(used_patterns, dict) else pattern in used_patterns:
            pass  # Allow but track
        
        selected.append(scored)
        used_names.add(name.lower())
        used_equipment[equip_normalized] = used_equipment.get(equip_normalized, 0) + 1
        if pattern not in ["other"]:
            used_patterns.add(pattern)
    
    # ═══════════════════════════════════════════════════════════════════════════════
    # PRINT FINAL WORKOUT
    # ═══════════════════════════════════════════════════════════════════════════════
    print("\n" + "="*70)
    print(f"🏋️ FINAL WORKOUT FOR JOE ({duration_minutes} min, Chest > Lower Chest)")
    print("="*70)
    
    for i, scored in enumerate(selected, 1):
        ex = scored["exercise"]
        name = ex.get('name', '')
        equipment = ex.get('equipment', 'Bodyweight')
        primary = ex.get('primary_muscles', [])
        secondary = ex.get('secondary_muscles', [])
        score = scored["score"]
        breakdown = scored["breakdown"]
        
        # Get metadata
        metadata = classify_exercise_metadata(name, equipment)
        
        print(f"\n{i}. {name}")
        print(f"   Equipment: {equipment}")
        print(f"   Primary: {primary}")
        if secondary:
            print(f"   Secondary: {secondary}")
        print(f"   Score: {score:.0f}")
        print(f"   Breakdown: {breakdown}")
        
        # Show safety status
        if metadata.spinal_load.value != 'none':
            status = "⚠️" if metadata.spinal_load.value in ['moderate', 'high'] else "✅"
            print(f"   {status} Spinal Load: {metadata.spinal_load.value}")
        if metadata.is_machine_supported:
            print(f"   ✅ Machine Supported")
        if metadata.is_chest_supported:
            print(f"   ✅ Chest Supported")
        if metadata.is_lying or metadata.is_seated:
            print(f"   ✅ Stable Position (seated/lying)")
    
    # Summary
    print("\n" + "="*70)
    print("📊 WORKOUT SUMMARY")
    print("="*70)
    print(f"Total exercises: {len(selected)}")
    print(f"Equipment used: {used_equipment}")
    print(f"Movement patterns: {used_patterns}")
    
    # Check for any back-stressing exercises that snuck through
    back_issues = []
    for scored in selected:
        name = scored["exercise"].get('name', '')
        if is_lower_back_stress_exercise(name):
            back_issues.append(name)
    
    if back_issues:
        print(f"\n⚠️ Warning: Found back-stressing exercises: {back_issues}")
    else:
        print(f"\n✅ No back-stressing exercises in workout - limitation respected!")
    
    print("\n" + "🔥"*35)
    
    return selected

def test_specific_exercises():
    """Test the metadata filtering on specific exercises"""
    print("\n" + "="*70)
    print("🧪 TESTING METADATA FILTERING ON SPECIFIC EXERCISES:")
    print("="*70)
    
    test_exercises = [
        ("Barbell Deadlift", "Barbell"),
        ("Bent Over Barbell Row", "Barbell"),
        ("Renegade Row", "Dumbbells"),
        ("Machine Chest Press", "Machine"),
        ("Cable Fly", "Cable Machine"),
        ("Chest Supported Row", "Dumbbells"),
        ("Guillotine Press", "Barbell"),
        ("Incline Dumbbell Press", "Dumbbells"),
        ("Decline Bench Press", "Barbell"),
    ]
    
    print(f"\nUser Limitation: {[(i.area, i.severity) for i in JOE_PROFILE.injuries]}")
    
    for name, equipment in test_exercises:
        should_exclude, penalty, reason = apply_metadata_limitation_filter(
            name, equipment, JOE_PROFILE.injuries
        )
        metadata = classify_exercise_metadata(name, equipment)
        
        if should_exclude:
            status = "🚫 EXCLUDED"
        elif penalty > 50:
            status = "⚠️ HIGH PENALTY"
        elif penalty > 0:
            status = "⚡ PENALIZED"
        elif penalty < 0:
            status = "✅ BOOSTED"
        else:
            status = "➡️ NEUTRAL"
        
        print(f"\n{name} ({equipment}):")
        print(f"   Status: {status} (penalty: {penalty:+d})")
        if reason:
            print(f"   Reason: {reason}")
        print(f"   Metadata: spinal={metadata.spinal_load.value}, "
              f"unsupported={metadata.unsupported_torso}, "
              f"hinge={metadata.hip_hinge_demand}, "
              f"machine={metadata.is_machine_supported}")

if __name__ == "__main__":
    # Generate workout
    generate_joe_workout(
        duration_minutes=45,
        primary_muscles=["Chest"],
        focus_areas=["Lower Chest"]
    )
    
    # Test specific exercises
    test_specific_exercises()
