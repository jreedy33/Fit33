#!/usr/bin/env python3
"""
Comprehensive Workout Generation Audit
Tests 50 users with diverse scenarios against all filter logic
Generates PDF report with findings
"""

import csv
import random
from datetime import datetime
from collections import Counter, defaultdict
from typing import Dict, List, Set, Tuple, Any

random.seed(42)  # Reproducibility

# ============================================================================
# SMART BENCH HANDLING LOGIC (mirrors Swift code)
# ============================================================================

BENCH_BASE_SCORES = {
    "flat bench": 1,
    "adjustable bench": 1,
    "incline bench": 2,
    "decline bench": 3,
    "preacher bench": 4,
    "hyperextension bench": 3,
    "roman chair": 4,
    "glute ham bench": 4,
    "ab bench": 3,
}

def infer_bench_types(target_muscles: List[str]) -> Set[str]:
    """Infer bench types from muscle selection context."""
    inferred = {"flat bench", "adjustable bench"}
    muscles_lower = [m.lower() for m in target_muscles]
    
    if any("upper chest" in m or "upper pec" in m for m in muscles_lower):
        inferred.add("incline bench")
    if any("lower chest" in m or "lower pec" in m for m in muscles_lower):
        inferred.add("decline bench")
    if any("glute" in m or "hip" in m for m in muscles_lower):
        inferred.add("hyperextension bench")
        inferred.add("flat bench")
    if any("lower back" in m or "erector" in m for m in muscles_lower):
        inferred.add("hyperextension bench")
    if any("bicep" in m for m in muscles_lower):
        inferred.add("preacher bench")
    if any("abs" in m or "core" in m or "abdominal" in m for m in muscles_lower):
        inferred.add("ab bench")
        inferred.add("decline bench")
    if any("chest" in m and "upper" not in m and "lower" not in m for m in muscles_lower):
        inferred.add("incline bench")
    
    return inferred

def get_required_bench_type(equipment: str) -> str:
    """Detect which bench type an exercise requires."""
    equip = equipment.lower()
    if "incline" in equip: return "incline bench"
    if "decline" in equip: return "decline bench"
    if "preacher" in equip: return "preacher bench"
    if "hyperextension" in equip or "hyper extension" in equip: return "hyperextension bench"
    if "roman" in equip: return "roman chair"
    if "glute ham" in equip or "ghd" in equip: return "glute ham bench"
    if "ab bench" in equip: return "ab bench"
    if "flat" in equip: return "flat bench"
    if "adjustable" in equip: return "adjustable bench"
    if "bench" in equip: return "flat bench"
    return None

def get_bench_context_score(equipment: str, target_muscles: List[str]) -> int:
    """Get context-aware bench compatibility score."""
    if "bench" not in equipment.lower():
        return 100
    
    inferred = infer_bench_types(target_muscles)
    required = get_required_bench_type(equipment)
    
    if required and required in inferred:
        return 95
    
    base_score = BENCH_BASE_SCORES.get(required, 2) if required else 1
    if base_score == 1: return 90
    if base_score == 2: return 70
    if base_score == 3: return 40
    if base_score == 4: return 20
    return 50

# ============================================================================
# EQUIPMENT MATCHING LOGIC
# ============================================================================

EQUIPMENT_CATEGORY_MAP = {
    "dumbbells": "Dumbbells", "dumbbell": "Dumbbells",
    "barbell": "Barbell", "ez bar": "Barbell", "trap bar": "Barbell",
    "cables": "Cables", "cable": "Cables", "cable machine": "Cables",
    "machines": "Machines", "machine": "Machines", "lever machine": "Machines",
    "smith machine": "Smith Machine", "smith": "Smith Machine",
    "kettlebell": "Kettlebell",
    "bands": "Bands", "band": "Bands", "resistance band": "Bands",
    "bench": "Bench", "flat bench": "Bench", "incline bench": "Bench", "decline bench": "Bench",
    "bodyweight": "Bodyweight", "body weight": "Bodyweight",
    "trx": "TRX/Rings", "rings": "TRX/Rings",
    "stability ball": "Stability Ball",
    "medicine ball": "Medicine Ball",
    "landmine": "Landmine",
    "sled": "Sled",
}

def normalize_equipment(raw_equipment: str) -> str:
    """Normalize equipment to user category."""
    if not raw_equipment:
        return "Bodyweight"
    
    equip = raw_equipment.lower().strip()
    if not equip or equip == "bodyweight":
        return "Bodyweight"
    
    # Check direct mapping
    if equip in EQUIPMENT_CATEGORY_MAP:
        return EQUIPMENT_CATEGORY_MAP[equip]
    
    # Handle combined equipment - get first part
    first_part = equip.split(",")[0].strip()
    if first_part in EQUIPMENT_CATEGORY_MAP:
        return EQUIPMENT_CATEGORY_MAP[first_part]
    
    # Keyword matching
    if "dumbbell" in equip: return "Dumbbells"
    if "barbell" in equip or "ez bar" in equip: return "Barbell"
    if "cable" in equip: return "Cables"
    if "lever" in equip or ("machine" in equip and "smith" not in equip): return "Machines"
    if "smith" in equip: return "Smith Machine"
    if "kettlebell" in equip: return "Kettlebell"
    if "band" in equip or "resistance" in equip: return "Bands"
    if "bench" in equip: return "Bench"
    if "pull-up" in equip or "pullup" in equip: return "Bodyweight"
    
    return "Bodyweight"

def user_has_equipment(exercise_equipment: str, user_equipment: List[str]) -> bool:
    """Check if user has required equipment for exercise - STRICT VERSION."""
    if not exercise_equipment or exercise_equipment.lower() in ["bodyweight", ""]:
        return any("body" in e.lower() for e in user_equipment)
    
    ex_equip_lower = exercise_equipment.lower()
    
    # Specialized equipment that bodyweight-only users CANNOT use
    specialized = ["stability ball", "swiss ball", "medicine ball", "foam roller",
                   "kettlebell", "trx", "rings", "suspension", "landmine", "sled",
                   "pull-up bar", "pullup bar", "dip bars", "plyo box"]
    
    is_specialized = any(spec in ex_equip_lower for spec in specialized)
    
    # Check if user only has bodyweight
    user_lower = [u.lower() for u in user_equipment]
    user_only_bodyweight = all("body" in u or u == "bodyweight" for u in user_lower)
    
    # Bodyweight-only users cannot use specialized equipment
    if user_only_bodyweight and is_specialized:
        return False
    
    user_categories = set()
    for ue in user_equipment:
        ue_lower = ue.lower()
        if "dumbbell" in ue_lower: user_categories.add("dumbbells")
        if "barbell" in ue_lower: user_categories.add("barbell")
        if "cable" in ue_lower: user_categories.add("cables")
        if "machine" in ue_lower and "smith" not in ue_lower: user_categories.add("machines")
        if "smith" in ue_lower: user_categories.add("smith machine")
        if "kettlebell" in ue_lower: user_categories.add("kettlebell")
        if "band" in ue_lower: user_categories.add("bands")
        if "bench" in ue_lower: user_categories.add("bench")
        if "body" in ue_lower: user_categories.add("bodyweight")
        if "trx" in ue_lower or "ring" in ue_lower: user_categories.add("trx")
        if "stability" in ue_lower: user_categories.add("stability ball")
        if "medicine" in ue_lower: user_categories.add("medicine ball")
        if "landmine" in ue_lower: user_categories.add("landmine")
        if "foam" in ue_lower: user_categories.add("foam roller")
    
    # Parse required equipment parts
    required_parts = [p.strip().lower() for p in exercise_equipment.split(",") if p.strip()]
    
    for required_part in required_parts:
        # Skip truly common items (floor, mat only)
        if required_part in {"floor", "mat"}:
            continue
        
        # Check if user has this category
        required_category = normalize_equipment(required_part).lower()
        
        found = False
        for user_cat in user_categories:
            if user_cat == required_category:
                found = True
                break
            # Special bench handling
            if "bench" in required_part and "bench" in user_cat:
                found = True
                break
            # Special stability ball handling
            if "stability" in required_part and "stability" in user_cat:
                found = True
                break
        
        if not found:
            return False
    
    return True

# ============================================================================
# MUSCLE MATCHING LOGIC
# ============================================================================

MUSCLE_CATEGORY_MAP = {
    "chest": ["chest", "pec", "pectoral"],
    "back": ["back", "lat", "rhomboid", "trap", "erector"],
    "legs": ["leg", "quad", "hamstring", "glute", "calf", "thigh"],
    "shoulders": ["shoulder", "delt", "deltoid"],
    "arms": ["arm", "bicep", "tricep", "forearm"],
    "core": ["core", "abs", "abdominal", "oblique"],
}

def exercise_matches_muscles(exercise_category: str, exercise_muscles: List[str], target_muscles: List[str]) -> bool:
    """Check if exercise targets the user's selected muscles."""
    target_lower = [m.lower() for m in target_muscles]
    ex_cat_lower = exercise_category.lower() if exercise_category else ""
    ex_muscles_lower = [m.lower() for m in (exercise_muscles or [])]
    
    # Check category match
    for target in target_lower:
        if target in ex_cat_lower:
            return True
        # Check if target muscle appears in exercise's muscle list
        for ex_muscle in ex_muscles_lower:
            if target in ex_muscle or ex_muscle in target:
                return True
        # Check muscle category mappings
        for cat, keywords in MUSCLE_CATEGORY_MAP.items():
            if any(kw in target for kw in keywords):
                if any(kw in ex_cat_lower for kw in keywords):
                    return True
                if any(kw in em for em in ex_muscles_lower for kw in keywords):
                    return True
    
    return False

# ============================================================================
# TEST USER GENERATION
# ============================================================================

def generate_test_users() -> List[Dict]:
    """Generate 50 diverse test users covering all filter scenarios."""
    users = []
    
    # === STRAIGHTFORWARD CASES (Users 1-15) ===
    
    # 1. Full gym access - all equipment
    users.append({
        "id": 1, "name": "Full Gym Alex",
        "equipment": ["Dumbbells", "Barbell", "Cables", "Machines", "Bench", "Smith Machine"],
        "muscles": ["Chest", "Triceps"],
        "experience": "intermediate", "goal": "build muscle",
        "limitations": [], "age": 28, "scenario": "Full gym access - standard push day"
    })
    
    # 2. Home gym minimal
    users.append({
        "id": 2, "name": "Home Gym Jordan",
        "equipment": ["Dumbbells", "Bands"],
        "muscles": ["Back", "Biceps"],
        "experience": "beginner", "goal": "get stronger",
        "limitations": [], "age": 35, "scenario": "Home gym with minimal equipment"
    })
    
    # 3. Bodyweight only
    users.append({
        "id": 3, "name": "Bodyweight Taylor",
        "equipment": ["Bodyweight"],
        "muscles": ["Core", "Legs"],
        "experience": "beginner", "goal": "lose weight",
        "limitations": [], "age": 42, "scenario": "No equipment - bodyweight only"
    })
    
    # 4. Cable/Machine specialist
    users.append({
        "id": 4, "name": "Machine Morgan",
        "equipment": ["Cables", "Machines"],
        "muscles": ["Shoulders", "Back"],
        "experience": "intermediate", "goal": "build muscle",
        "limitations": [], "age": 31, "scenario": "Prefers machines/cables"
    })
    
    # 5. Barbell purist
    users.append({
        "id": 5, "name": "Barbell Casey",
        "equipment": ["Barbell", "Bench"],
        "muscles": ["Chest", "Back", "Legs"],
        "experience": "advanced", "goal": "get stronger",
        "limitations": [], "age": 26, "scenario": "Powerlifter - barbell focus"
    })
    
    # 6. Kettlebell enthusiast
    users.append({
        "id": 6, "name": "Kettlebell Riley",
        "equipment": ["Kettlebell", "Bodyweight"],
        "muscles": ["Full Body"],
        "experience": "intermediate", "goal": "lose weight",
        "limitations": [], "age": 33, "scenario": "Kettlebell focused training"
    })
    
    # 7. Smith Machine only (Planet Fitness user)
    users.append({
        "id": 7, "name": "Smith Quinn",
        "equipment": ["Smith Machine", "Cables", "Machines"],
        "muscles": ["Legs", "Glutes"],
        "experience": "beginner", "goal": "build muscle",
        "limitations": [], "age": 24, "scenario": "Planet Fitness style gym"
    })
    
    # 8. Dumbbell only home
    users.append({
        "id": 8, "name": "Dumbbell Avery",
        "equipment": ["Dumbbells"],
        "muscles": ["Arms", "Shoulders"],
        "experience": "beginner", "goal": "build muscle",
        "limitations": [], "age": 29, "scenario": "Only owns dumbbells"
    })
    
    # 9. Resistance bands travel
    users.append({
        "id": 9, "name": "Travel Parker",
        "equipment": ["Bands", "Bodyweight"],
        "muscles": ["Chest", "Back"],
        "experience": "intermediate", "goal": "maintain",
        "limitations": [], "age": 38, "scenario": "Traveling - bands only"
    })
    
    # 10. Full gym beginner
    users.append({
        "id": 10, "name": "Beginner Dakota",
        "equipment": ["Dumbbells", "Barbell", "Cables", "Machines", "Bench"],
        "muscles": ["Chest"],
        "experience": "beginner", "goal": "build muscle",
        "limitations": [], "age": 22, "scenario": "New to gym - needs simple exercises"
    })
    
    # === SMART BENCH CONTEXT TESTS (Users 11-20) ===
    
    # 11. Upper Chest + Bench = should get incline exercises
    users.append({
        "id": 11, "name": "Upper Chest Sam",
        "equipment": ["Dumbbells", "Bench"],
        "muscles": ["Upper Chest"],
        "experience": "intermediate", "goal": "build muscle",
        "limitations": [], "age": 27,
        "scenario": "BENCH CONTEXT: Upper Chest should infer incline bench"
    })
    
    # 12. Lower Chest + Bench = should get decline exercises
    users.append({
        "id": 12, "name": "Lower Chest Jamie",
        "equipment": ["Dumbbells", "Barbell", "Bench"],
        "muscles": ["Lower Chest"],
        "experience": "intermediate", "goal": "build muscle",
        "limitations": [], "age": 30,
        "scenario": "BENCH CONTEXT: Lower Chest should infer decline bench"
    })
    
    # 13. Biceps + Bench = should allow preacher curl
    users.append({
        "id": 13, "name": "Bicep Focus Drew",
        "equipment": ["Dumbbells", "Barbell", "Bench"],
        "muscles": ["Biceps"],
        "experience": "intermediate", "goal": "build muscle",
        "limitations": [], "age": 25,
        "scenario": "BENCH CONTEXT: Biceps should infer preacher bench"
    })
    
    # 14. Glutes + Bench = should allow hyperextension
    users.append({
        "id": 14, "name": "Glute Focus Charlie",
        "equipment": ["Barbell", "Bench", "Machines"],
        "muscles": ["Glutes"],
        "experience": "intermediate", "goal": "build muscle",
        "limitations": [], "age": 28,
        "scenario": "BENCH CONTEXT: Glutes should infer hyperextension bench"
    })
    
    # 15. Abs + Bench = should allow decline for crunches
    users.append({
        "id": 15, "name": "Abs Focus Ellis",
        "equipment": ["Bodyweight", "Bench"],
        "muscles": ["Abs", "Core"],
        "experience": "beginner", "goal": "lose weight",
        "limitations": [], "age": 32,
        "scenario": "BENCH CONTEXT: Abs should infer decline bench for crunches"
    })
    
    # 16. Generic Chest + Bench = flat and incline, avoid decline
    users.append({
        "id": 16, "name": "Chest Generic Frankie",
        "equipment": ["Dumbbells", "Barbell", "Bench"],
        "muscles": ["Chest"],
        "experience": "intermediate", "goal": "build muscle",
        "limitations": [], "age": 29,
        "scenario": "BENCH CONTEXT: Generic Chest should prefer flat/incline over decline"
    })
    
    # 17. Lower Back + Bench = hyperextension
    users.append({
        "id": 17, "name": "Lower Back Gale",
        "equipment": ["Bodyweight", "Bench"],
        "muscles": ["Lower Back"],
        "experience": "beginner", "goal": "get stronger",
        "limitations": [], "age": 45,
        "scenario": "BENCH CONTEXT: Lower Back should infer hyperextension bench"
    })
    
    # 18. No bench selected - should not get bench exercises
    users.append({
        "id": 18, "name": "No Bench Harper",
        "equipment": ["Dumbbells", "Cables"],
        "muscles": ["Chest", "Triceps"],
        "experience": "intermediate", "goal": "build muscle",
        "limitations": [], "age": 27,
        "scenario": "NO BENCH: Should only get floor/standing chest exercises"
    })
    
    # 19. Bench + many muscle groups
    users.append({
        "id": 19, "name": "Full Upper Indigo",
        "equipment": ["Dumbbells", "Barbell", "Bench"],
        "muscles": ["Chest", "Back", "Shoulders"],
        "experience": "intermediate", "goal": "build muscle",
        "limitations": [], "age": 31,
        "scenario": "BENCH CONTEXT: Multiple upper body - varied bench usage"
    })
    
    # 20. Specialized bench test - preacher without biceps
    users.append({
        "id": 20, "name": "Tricep Only Jules",
        "equipment": ["Dumbbells", "Barbell", "Bench"],
        "muscles": ["Triceps"],
        "experience": "intermediate", "goal": "build muscle",
        "limitations": [], "age": 26,
        "scenario": "BENCH CONTEXT: Triceps should NOT infer preacher bench"
    })
    
    # === EQUIPMENT DIVERSITY TESTS (Users 21-30) ===
    
    # 21. All equipment - should use variety
    users.append({
        "id": 21, "name": "Variety Kerry",
        "equipment": ["Dumbbells", "Barbell", "Cables", "Machines", "Bench", "Smith Machine", "Kettlebell"],
        "muscles": ["Chest", "Back"],
        "experience": "advanced", "goal": "build muscle",
        "limitations": [], "age": 30,
        "scenario": "DIVERSITY: Should use multiple equipment types"
    })
    
    # 22. Dumbbell + Cable - equal distribution
    users.append({
        "id": 22, "name": "DB Cable Lane",
        "equipment": ["Dumbbells", "Cables"],
        "muscles": ["Chest", "Triceps"],
        "experience": "intermediate", "goal": "build muscle",
        "limitations": [], "age": 28,
        "scenario": "DIVERSITY: Should balance dumbbells and cables"
    })
    
    # 23. Machine + Cable heavy
    users.append({
        "id": 23, "name": "Machine Cable Morgan",
        "equipment": ["Cables", "Machines"],
        "muscles": ["Back", "Biceps"],
        "experience": "intermediate", "goal": "build muscle",
        "limitations": [], "age": 34,
        "scenario": "DIVERSITY: Should use both cables and machines"
    })
    
    # 24. Barbell + Dumbbell + Bench
    users.append({
        "id": 24, "name": "Free Weight Noel",
        "equipment": ["Barbell", "Dumbbells", "Bench"],
        "muscles": ["Legs", "Glutes"],
        "experience": "intermediate", "goal": "get stronger",
        "limitations": [], "age": 29,
        "scenario": "DIVERSITY: Should balance barbell and dumbbell leg work"
    })
    
    # 25. Single equipment - no diversity needed
    users.append({
        "id": 25, "name": "Single Equip Oakley",
        "equipment": ["Cables"],
        "muscles": ["Chest", "Back", "Arms"],
        "experience": "intermediate", "goal": "build muscle",
        "limitations": [], "age": 27,
        "scenario": "DIVERSITY: Single equipment - all cable exercises expected"
    })
    
    # === LIMITATION/INJURY TESTS (Users 26-35) ===
    
    # 26. Back injury - no deadlifts/rows
    users.append({
        "id": 26, "name": "Back Injury Peyton",
        "equipment": ["Dumbbells", "Cables", "Machines"],
        "muscles": ["Back"],
        "experience": "intermediate", "goal": "build muscle",
        "limitations": ["lower back injury", "no heavy spinal loading"],
        "age": 40,
        "scenario": "LIMITATION: Back injury - should avoid deadlifts"
    })
    
    # 27. Shoulder injury - no overhead
    users.append({
        "id": 27, "name": "Shoulder Issue Quinn",
        "equipment": ["Dumbbells", "Cables", "Machines"],
        "muscles": ["Shoulders"],
        "experience": "intermediate", "goal": "build muscle",
        "limitations": ["shoulder impingement", "avoid overhead pressing"],
        "age": 35,
        "scenario": "LIMITATION: Shoulder injury - limited overhead work"
    })
    
    # 28. Knee injury - leg work restricted
    users.append({
        "id": 28, "name": "Knee Issue Reed",
        "equipment": ["Machines", "Cables"],
        "muscles": ["Legs"],
        "experience": "beginner", "goal": "maintain",
        "limitations": ["knee pain", "no deep squats"],
        "age": 50,
        "scenario": "LIMITATION: Knee issues - should prefer leg press/machines"
    })
    
    # 29. Wrist injury - grip issues
    users.append({
        "id": 29, "name": "Wrist Issue Sage",
        "equipment": ["Machines", "Cables"],
        "muscles": ["Chest", "Back"],
        "experience": "intermediate", "goal": "build muscle",
        "limitations": ["wrist injury", "limited grip strength"],
        "age": 33,
        "scenario": "LIMITATION: Wrist injury - prefer machines over free weights"
    })
    
    # 30. Senior user - lower impact
    users.append({
        "id": 30, "name": "Senior Terry",
        "equipment": ["Machines", "Cables", "Bands"],
        "muscles": ["Full Body"],
        "experience": "beginner", "goal": "maintain",
        "limitations": ["elderly", "joint sensitivity"],
        "age": 68,
        "scenario": "LIMITATION: Senior - lower impact, machine-based"
    })
    
    # 31. Post-surgery recovery
    users.append({
        "id": 31, "name": "Recovery Uma",
        "equipment": ["Bands", "Bodyweight"],
        "muscles": ["Core", "Legs"],
        "experience": "beginner", "goal": "maintain",
        "limitations": ["post surgery", "light weights only"],
        "age": 45,
        "scenario": "LIMITATION: Post-surgery - very light exercises"
    })
    
    # 32. Pregnancy modifications
    users.append({
        "id": 32, "name": "Prenatal Val",
        "equipment": ["Dumbbells", "Bands", "Bodyweight"],
        "muscles": ["Arms", "Back"],
        "experience": "intermediate", "goal": "maintain",
        "limitations": ["pregnant", "no lying flat"],
        "age": 32,
        "scenario": "LIMITATION: Pregnancy - avoid lying flat, core restrictions"
    })
    
    # === EXPERIENCE LEVEL TESTS (Users 33-38) ===
    
    # 33. Complete beginner - simple exercises
    users.append({
        "id": 33, "name": "Total Newbie Wren",
        "equipment": ["Dumbbells", "Machines"],
        "muscles": ["Chest", "Back"],
        "experience": "beginner", "goal": "build muscle",
        "limitations": [], "age": 19,
        "scenario": "EXPERIENCE: Complete beginner - needs simple exercises"
    })
    
    # 34. Advanced lifter - complex movements OK
    users.append({
        "id": 34, "name": "Advanced Xavier",
        "equipment": ["Barbell", "Dumbbells", "Cables", "Bench"],
        "muscles": ["Chest", "Back", "Legs"],
        "experience": "advanced", "goal": "get stronger",
        "limitations": [], "age": 28,
        "scenario": "EXPERIENCE: Advanced - can handle complex movements"
    })
    
    # 35. Intermediate rebuilding
    users.append({
        "id": 35, "name": "Returning Yara",
        "equipment": ["Dumbbells", "Cables", "Machines", "Bench"],
        "muscles": ["Full Body"],
        "experience": "intermediate", "goal": "build muscle",
        "limitations": [], "age": 36,
        "scenario": "EXPERIENCE: Intermediate returning after break"
    })
    
    # === GOAL-SPECIFIC TESTS (Users 36-42) ===
    
    # 36. Fat loss - cardio/metabolic focus
    users.append({
        "id": 36, "name": "Fat Loss Zion",
        "equipment": ["Bodyweight", "Kettlebell"],
        "muscles": ["Full Body"],
        "experience": "beginner", "goal": "lose weight",
        "limitations": [], "age": 40,
        "scenario": "GOAL: Fat loss - should include metabolic movements"
    })
    
    # 37. Strength focus - compound heavy
    users.append({
        "id": 37, "name": "Strength Ash",
        "equipment": ["Barbell", "Dumbbells", "Bench"],
        "muscles": ["Chest", "Back", "Legs"],
        "experience": "intermediate", "goal": "get stronger",
        "limitations": [], "age": 27,
        "scenario": "GOAL: Strength - should prioritize compound movements"
    })
    
    # 38. Hypertrophy - isolation focus
    users.append({
        "id": 38, "name": "Hypertrophy Blake",
        "equipment": ["Dumbbells", "Cables", "Machines"],
        "muscles": ["Arms"],
        "experience": "intermediate", "goal": "build muscle",
        "limitations": [], "age": 25,
        "scenario": "GOAL: Hypertrophy - include isolation exercises"
    })
    
    # 39. Maintenance - balanced
    users.append({
        "id": 39, "name": "Maintain Cameron",
        "equipment": ["Dumbbells", "Cables", "Bodyweight"],
        "muscles": ["Full Body"],
        "experience": "intermediate", "goal": "maintain",
        "limitations": [], "age": 45,
        "scenario": "GOAL: Maintenance - balanced approach"
    })
    
    # === EDGE CASES (Users 40-50) ===
    
    # 40. Single muscle, single equipment
    users.append({
        "id": 40, "name": "Minimal Dylan",
        "equipment": ["Dumbbells"],
        "muscles": ["Biceps"],
        "experience": "beginner", "goal": "build muscle",
        "limitations": [], "age": 23,
        "scenario": "EDGE: Very narrow selection - biceps + dumbbells only"
    })
    
    # 41. All muscles selected
    users.append({
        "id": 41, "name": "Everything Emery",
        "equipment": ["Dumbbells", "Barbell", "Cables", "Machines", "Bench"],
        "muscles": ["Chest", "Back", "Legs", "Shoulders", "Arms", "Core"],
        "experience": "intermediate", "goal": "build muscle",
        "limitations": [], "age": 30,
        "scenario": "EDGE: All muscles selected - should focus on major compound"
    })
    
    # 42. Unusual combo - legs + cables only
    users.append({
        "id": 42, "name": "Cable Legs Finley",
        "equipment": ["Cables"],
        "muscles": ["Legs", "Glutes"],
        "experience": "intermediate", "goal": "build muscle",
        "limitations": [], "age": 29,
        "scenario": "EDGE: Legs with only cables - limited but valid"
    })
    
    # 43. Shoulders with bodyweight only
    users.append({
        "id": 43, "name": "BW Shoulders Gray",
        "equipment": ["Bodyweight"],
        "muscles": ["Shoulders"],
        "experience": "intermediate", "goal": "build muscle",
        "limitations": [], "age": 26,
        "scenario": "EDGE: Shoulders with bodyweight - pike pushups etc"
    })
    
    # 44. Core with barbell
    users.append({
        "id": 44, "name": "Barbell Core Haven",
        "equipment": ["Barbell"],
        "muscles": ["Core"],
        "experience": "advanced", "goal": "get stronger",
        "limitations": [], "age": 28,
        "scenario": "EDGE: Core with barbell - ab rollout, landmine etc"
    })
    
    # 45. Back with bands only
    users.append({
        "id": 45, "name": "Band Back Indie",
        "equipment": ["Bands"],
        "muscles": ["Back"],
        "experience": "beginner", "goal": "build muscle",
        "limitations": [], "age": 35,
        "scenario": "EDGE: Back with bands only - rows, pulldowns"
    })
    
    # 46. Very young user
    users.append({
        "id": 46, "name": "Young Jules",
        "equipment": ["Bodyweight", "Bands"],
        "muscles": ["Full Body"],
        "experience": "beginner", "goal": "build muscle",
        "limitations": ["teenage"], "age": 16,
        "scenario": "EDGE: Young user - appropriate exercises"
    })
    
    # 47. Chest without bench or machines
    users.append({
        "id": 47, "name": "Floor Chest Kit",
        "equipment": ["Dumbbells", "Bands"],
        "muscles": ["Chest"],
        "experience": "intermediate", "goal": "build muscle",
        "limitations": [], "age": 30,
        "scenario": "EDGE: Chest without bench - floor press, pushups"
    })
    
    # 48. Maximum equipment diversity test
    users.append({
        "id": 48, "name": "Max Diversity Lane",
        "equipment": ["Dumbbells", "Barbell", "Cables", "Machines", "Bench", "Smith Machine", "Kettlebell", "Bands"],
        "muscles": ["Chest"],
        "experience": "advanced", "goal": "build muscle",
        "limitations": [], "age": 27,
        "scenario": "EDGE: Max equipment - should show good diversity"
    })
    
    # 49. Triceps focus - various equipment
    users.append({
        "id": 49, "name": "Tricep Master Moss",
        "equipment": ["Dumbbells", "Cables", "Bench"],
        "muscles": ["Triceps"],
        "experience": "intermediate", "goal": "build muscle",
        "limitations": [], "age": 26,
        "scenario": "EDGE: Triceps only - pushdowns, extensions, dips"
    })
    
    # 50. Hamstring focus
    users.append({
        "id": 50, "name": "Hamstring Nico",
        "equipment": ["Barbell", "Dumbbells", "Machines"],
        "muscles": ["Hamstrings"],
        "experience": "intermediate", "goal": "build muscle",
        "limitations": [], "age": 29,
        "scenario": "EDGE: Hamstrings specific - curls, RDLs, etc"
    })
    
    return users

# ============================================================================
# WORKOUT GENERATION SIMULATION
# ============================================================================

def load_exercises() -> List[Dict]:
    """Load exercises from CSV."""
    exercises = []
    try:
        with open('Final Master Correct.csv', 'r', encoding='utf-8') as f:
            reader = csv.DictReader(f)
            for row in reader:
                exercises.append({
                    'id': row.get('id', ''),
                    'name': row.get('name', ''),
                    'equipment': row.get('equipment', ''),
                    'category': row.get('category', ''),
                    'difficulty': row.get('difficulty', '3'),
                    'is_compound': row.get('is_compound', 'false').lower() == 'true',
                    'primary_muscles': row.get('primary_muscles', ''),
                })
    except Exception as e:
        print(f"Error loading exercises: {e}")
    return exercises

def generate_workout_for_user(user: Dict, all_exercises: List[Dict], num_exercises: int = 6) -> List[Dict]:
    """Simulate workout generation for a user."""
    matching = []
    
    for ex in all_exercises:
        # Equipment filter
        if not user_has_equipment(ex['equipment'], user['equipment']):
            continue
        
        # Muscle filter
        ex_muscles = [m.strip() for m in ex.get('primary_muscles', '').split(',') if m.strip()]
        if not exercise_matches_muscles(ex['category'], ex_muscles, user['muscles']):
            continue
        
        # Calculate score
        score = 100.0
        
        # Bench context scoring
        if "bench" in " ".join(user['equipment']).lower():
            bench_score = get_bench_context_score(ex['equipment'], user['muscles'])
            score += (bench_score - 60) * 0.7
        
        # Experience scoring
        try:
            diff = int(ex.get('difficulty', 3))
        except:
            diff = 3
            
        if user['experience'] == 'beginner' and diff > 5:
            score -= 30
        elif user['experience'] == 'advanced' and diff < 3:
            score -= 10
        
        # Goal scoring
        if user['goal'] == 'get stronger' and ex.get('is_compound'):
            score += 20
        elif user['goal'] == 'build muscle':
            score += 10
        
        # Add some randomness
        score += random.random() * 20
        
        matching.append({'exercise': ex, 'score': score})
    
    # Sort and select
    matching.sort(key=lambda x: x['score'], reverse=True)
    
    # Equipment diversity: try to use different equipment types
    selected = []
    equipment_used = Counter()
    equipment_types = set()
    
    for eq in user['equipment']:
        eq_lower = eq.lower()
        if "dumbbell" in eq_lower: equipment_types.add("dumbbells")
        elif "barbell" in eq_lower: equipment_types.add("barbell")
        elif "cable" in eq_lower: equipment_types.add("cables")
        elif "machine" in eq_lower and "smith" not in eq_lower: equipment_types.add("machines")
        elif "smith" in eq_lower: equipment_types.add("smith")
        elif "kettlebell" in eq_lower: equipment_types.add("kettlebell")
        elif "band" in eq_lower: equipment_types.add("bands")
        elif "body" in eq_lower: equipment_types.add("bodyweight")
        elif "bench" in eq_lower: equipment_types.add("bench")
    
    # Round-robin through equipment types first
    if len(equipment_types) > 1:
        for eq_type in equipment_types:
            for item in matching:
                ex = item['exercise']
                ex_equip = normalize_equipment(ex['equipment']).lower()
                if eq_type in ex_equip or ex_equip in eq_type:
                    if ex not in [s['exercise'] for s in selected]:
                        selected.append(item)
                        equipment_used[eq_type] += 1
                        break
            if len(selected) >= num_exercises:
                break
    
    # Fill remaining slots
    for item in matching:
        if len(selected) >= num_exercises:
            break
        if item not in selected:
            selected.append(item)
    
    return [s['exercise'] for s in selected[:num_exercises]]

# ============================================================================
# GRADING AND SCORING
# ============================================================================

def grade_workout(user: Dict, workout: List[Dict]) -> Dict:
    """Grade a workout against multiple criteria."""
    grades = {
        'equipment_match': {'score': 0, 'max': 100, 'details': []},
        'muscle_match': {'score': 0, 'max': 100, 'details': []},
        'bench_context': {'score': 0, 'max': 100, 'details': []},
        'equipment_diversity': {'score': 0, 'max': 100, 'details': []},
        'experience_appropriate': {'score': 0, 'max': 100, 'details': []},
        'overall': {'score': 0, 'max': 100, 'grade': ''},
    }
    
    if not workout:
        grades['overall']['grade'] = 'F'
        grades['overall']['details'] = ['No exercises generated']
        return grades
    
    # === EQUIPMENT MATCH ===
    equip_matches = 0
    for ex in workout:
        if user_has_equipment(ex['equipment'], user['equipment']):
            equip_matches += 1
        else:
            grades['equipment_match']['details'].append(
                f"❌ '{ex['name']}' requires {ex['equipment']} - user doesn't have"
            )
    grades['equipment_match']['score'] = int((equip_matches / len(workout)) * 100)
    
    # === MUSCLE MATCH ===
    muscle_matches = 0
    for ex in workout:
        ex_muscles = [m.strip() for m in ex.get('primary_muscles', '').split(',') if m.strip()]
        if exercise_matches_muscles(ex['category'], ex_muscles, user['muscles']):
            muscle_matches += 1
        else:
            grades['muscle_match']['details'].append(
                f"❌ '{ex['name']}' ({ex['category']}) doesn't match target muscles {user['muscles']}"
            )
    grades['muscle_match']['score'] = int((muscle_matches / len(workout)) * 100)
    
    # === BENCH CONTEXT ===
    user_has_bench = any("bench" in e.lower() for e in user['equipment'])
    if user_has_bench:
        bench_appropriate = 0
        total_bench_exercises = 0
        for ex in workout:
            if "bench" in ex['equipment'].lower():
                total_bench_exercises += 1
                score = get_bench_context_score(ex['equipment'], user['muscles'])
                if score >= 70:  # Good context match
                    bench_appropriate += 1
                elif score < 50:
                    grades['bench_context']['details'].append(
                        f"⚠️ '{ex['name']}' uses {get_required_bench_type(ex['equipment'])} without context support"
                    )
        
        if total_bench_exercises > 0:
            grades['bench_context']['score'] = int((bench_appropriate / total_bench_exercises) * 100)
        else:
            grades['bench_context']['score'] = 100  # No bench exercises = no penalty
    else:
        # User doesn't have bench - check no bench exercises assigned
        bench_exercises = [ex for ex in workout if "bench" in ex['equipment'].lower()]
        if bench_exercises:
            grades['bench_context']['score'] = 0
            grades['bench_context']['details'].append(
                f"❌ User has no bench but got bench exercises: {[e['name'] for e in bench_exercises]}"
            )
        else:
            grades['bench_context']['score'] = 100
    
    # === EQUIPMENT DIVERSITY ===
    equipment_types_used = set()
    for ex in workout:
        equip = normalize_equipment(ex['equipment'])
        equipment_types_used.add(equip)
    
    user_equip_types = set()
    for eq in user['equipment']:
        user_equip_types.add(normalize_equipment(eq))
    
    # Calculate diversity ratio
    possible_diversity = min(len(user_equip_types), len(workout))
    actual_diversity = len(equipment_types_used)
    
    if possible_diversity > 1:
        diversity_ratio = actual_diversity / possible_diversity
        grades['equipment_diversity']['score'] = int(diversity_ratio * 100)
        if diversity_ratio < 0.5:
            grades['equipment_diversity']['details'].append(
                f"⚠️ Low diversity: only using {equipment_types_used} from {user_equip_types}"
            )
    else:
        grades['equipment_diversity']['score'] = 100  # Single equipment = perfect diversity
    
    # === EXPERIENCE APPROPRIATE ===
    appropriate = 0
    for ex in workout:
        try:
            diff = int(ex.get('difficulty', 3))
        except:
            diff = 3
        
        if user['experience'] == 'beginner':
            if diff <= 5:
                appropriate += 1
            else:
                grades['experience_appropriate']['details'].append(
                    f"⚠️ '{ex['name']}' (difficulty {diff}) may be too hard for beginner"
                )
        elif user['experience'] == 'advanced':
            if diff >= 2:
                appropriate += 1
            else:
                grades['experience_appropriate']['details'].append(
                    f"⚠️ '{ex['name']}' (difficulty {diff}) may be too easy for advanced"
                )
        else:  # intermediate
            appropriate += 1
    
    grades['experience_appropriate']['score'] = int((appropriate / len(workout)) * 100)
    
    # === OVERALL SCORE ===
    weights = {
        'equipment_match': 0.30,
        'muscle_match': 0.25,
        'bench_context': 0.20,
        'equipment_diversity': 0.15,
        'experience_appropriate': 0.10,
    }
    
    overall = sum(grades[k]['score'] * weights[k] for k in weights)
    grades['overall']['score'] = int(overall)
    
    if overall >= 90: grades['overall']['grade'] = 'A'
    elif overall >= 80: grades['overall']['grade'] = 'B'
    elif overall >= 70: grades['overall']['grade'] = 'C'
    elif overall >= 60: grades['overall']['grade'] = 'D'
    else: grades['overall']['grade'] = 'F'
    
    return grades

# ============================================================================
# REPORT GENERATION
# ============================================================================

def generate_report(users: List[Dict], all_exercises: List[Dict]) -> str:
    """Generate comprehensive audit report."""
    report = []
    all_results = []
    
    report.append("=" * 100)
    report.append("              COMPREHENSIVE WORKOUT GENERATION AUDIT REPORT")
    report.append(f"              Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    report.append("=" * 100)
    report.append("")
    
    # Generate workouts and grade them
    for user in users:
        workout = generate_workout_for_user(user, all_exercises)
        grades = grade_workout(user, workout)
        all_results.append({
            'user': user,
            'workout': workout,
            'grades': grades
        })
    
    # === EXECUTIVE SUMMARY ===
    report.append("╔" + "═" * 98 + "╗")
    report.append("║" + "EXECUTIVE SUMMARY".center(98) + "║")
    report.append("╚" + "═" * 98 + "╝")
    report.append("")
    
    overall_scores = [r['grades']['overall']['score'] for r in all_results]
    avg_score = sum(overall_scores) / len(overall_scores)
    
    grade_dist = Counter(r['grades']['overall']['grade'] for r in all_results)
    
    report.append(f"  Total Users Tested: {len(users)}")
    report.append(f"  Average Overall Score: {avg_score:.1f}/100")
    report.append(f"  Grade Distribution:")
    for grade in ['A', 'B', 'C', 'D', 'F']:
        count = grade_dist.get(grade, 0)
        bar = '█' * (count * 2)
        report.append(f"    {grade}: {bar} {count}")
    report.append("")
    
    # Category averages
    report.append("  Category Averages:")
    categories = ['equipment_match', 'muscle_match', 'bench_context', 'equipment_diversity', 'experience_appropriate']
    for cat in categories:
        avg = sum(r['grades'][cat]['score'] for r in all_results) / len(all_results)
        bar = '█' * int(avg / 5)
        report.append(f"    {cat.replace('_', ' ').title()}: {bar} {avg:.1f}%")
    report.append("")
    
    # === ISSUES FOUND ===
    report.append("╔" + "═" * 98 + "╗")
    report.append("║" + "ISSUES IDENTIFIED".center(98) + "║")
    report.append("╚" + "═" * 98 + "╝")
    report.append("")
    
    issues_by_category = defaultdict(list)
    for result in all_results:
        for cat, data in result['grades'].items():
            if cat != 'overall' and data.get('details'):
                for detail in data['details']:
                    issues_by_category[cat].append({
                        'user': result['user']['name'],
                        'issue': detail
                    })
    
    for cat, issues in issues_by_category.items():
        if issues:
            report.append(f"  📌 {cat.replace('_', ' ').upper()} ({len(issues)} issues)")
            for issue in issues[:5]:  # Show first 5
                report.append(f"     • [{issue['user']}] {issue['issue']}")
            if len(issues) > 5:
                report.append(f"     ... and {len(issues) - 5} more")
            report.append("")
    
    # === DETAILED USER REPORTS (First 20) ===
    report.append("")
    report.append("╔" + "═" * 98 + "╗")
    report.append("║" + "DETAILED USER REPORTS (20 USERS)".center(98) + "║")
    report.append("╚" + "═" * 98 + "╝")
    
    for result in all_results[:20]:
        user = result['user']
        workout = result['workout']
        grades = result['grades']
        
        report.append("")
        report.append("─" * 100)
        report.append(f"USER #{user['id']}: {user['name']}")
        report.append(f"Scenario: {user['scenario']}")
        report.append("─" * 100)
        report.append("")
        
        report.append("  📋 USER PROFILE:")
        report.append(f"     Equipment: {', '.join(user['equipment'])}")
        report.append(f"     Target Muscles: {', '.join(user['muscles'])}")
        report.append(f"     Experience: {user['experience'].title()}")
        report.append(f"     Goal: {user['goal'].title()}")
        if user['limitations']:
            report.append(f"     Limitations: {', '.join(user['limitations'])}")
        report.append("")
        
        # Bench context inference (if applicable)
        if any("bench" in e.lower() for e in user['equipment']):
            inferred = infer_bench_types(user['muscles'])
            report.append(f"  🪑 BENCH CONTEXT INFERENCE:")
            report.append(f"     Based on muscles [{', '.join(user['muscles'])}], inferred bench types:")
            report.append(f"     → {', '.join(sorted(inferred))}")
            report.append("")
        
        report.append("  🏋️ EXERCISES ASSIGNED:")
        for i, ex in enumerate(workout, 1):
            equip_type = normalize_equipment(ex['equipment'])
            bench_score = get_bench_context_score(ex['equipment'], user['muscles']) if "bench" in ex['equipment'].lower() else "-"
            report.append(f"     {i}. {ex['name']}")
            report.append(f"        Equipment: {ex['equipment']} → [{equip_type}]")
            report.append(f"        Category: {ex['category']}")
            if bench_score != "-":
                report.append(f"        Bench Context Score: {bench_score}/100")
        report.append("")
        
        report.append("  📊 SCORECARD:")
        report.append(f"     ┌{'─' * 40}┬{'─' * 10}┐")
        report.append(f"     │ {'Category':<38} │ {'Score':^8} │")
        report.append(f"     ├{'─' * 40}┼{'─' * 10}┤")
        
        for cat in categories:
            score = grades[cat]['score']
            emoji = "✅" if score >= 80 else "⚠️" if score >= 60 else "❌"
            report.append(f"     │ {emoji} {cat.replace('_', ' ').title():<35} │ {score:>6}% │")
        
        report.append(f"     ├{'─' * 40}┼{'─' * 10}┤")
        overall = grades['overall']
        grade_emoji = "🌟" if overall['grade'] == 'A' else "✅" if overall['grade'] == 'B' else "⚠️" if overall['grade'] == 'C' else "❌"
        report.append(f"     │ {grade_emoji} {'OVERALL':<35} │ {overall['score']:>5}% {overall['grade']} │")
        report.append(f"     └{'─' * 40}┴{'─' * 10}┘")
        
        # Show issues if any
        all_issues = []
        for cat, data in grades.items():
            if cat != 'overall' and data.get('details'):
                all_issues.extend(data['details'])
        
        if all_issues:
            report.append("")
            report.append("  ⚠️ ISSUES:")
            for issue in all_issues[:3]:
                report.append(f"     {issue}")
    
    # === RECOMMENDATIONS ===
    report.append("")
    report.append("╔" + "═" * 98 + "╗")
    report.append("║" + "RECOMMENDATIONS".center(98) + "║")
    report.append("╚" + "═" * 98 + "╝")
    report.append("")
    
    # Analyze patterns
    low_scores = [r for r in all_results if r['grades']['overall']['score'] < 70]
    if low_scores:
        report.append("  🔧 USERS WITH LOW SCORES (< 70%):")
        for r in low_scores[:5]:
            report.append(f"     • {r['user']['name']} (Score: {r['grades']['overall']['score']})")
            report.append(f"       Scenario: {r['user']['scenario']}")
        report.append("")
    
    # Equipment diversity issues
    div_issues = [r for r in all_results if r['grades']['equipment_diversity']['score'] < 60]
    if div_issues:
        report.append("  🔧 EQUIPMENT DIVERSITY ISSUES:")
        for r in div_issues[:3]:
            report.append(f"     • {r['user']['name']}: Only using limited equipment types")
        report.append("")
    
    # Bench context issues
    bench_issues = [r for r in all_results if r['grades']['bench_context']['score'] < 60]
    if bench_issues:
        report.append("  🔧 BENCH CONTEXT ISSUES:")
        for r in bench_issues[:3]:
            report.append(f"     • {r['user']['name']}: Bench exercises not matching muscle context")
        report.append("")
    
    if avg_score >= 80:
        report.append("  ✅ OVERALL: System is performing well! Average score is above 80%.")
    elif avg_score >= 70:
        report.append("  ⚠️ OVERALL: System needs minor improvements. See issues above.")
    else:
        report.append("  ❌ OVERALL: System needs significant improvements. Review issues carefully.")
    
    report.append("")
    report.append("=" * 100)
    report.append("END OF AUDIT REPORT")
    report.append("=" * 100)
    
    return "\n".join(report), all_results

# ============================================================================
# MAIN EXECUTION
# ============================================================================

if __name__ == "__main__":
    print("🔄 Loading exercises...")
    exercises = load_exercises()
    print(f"   Loaded {len(exercises)} exercises")
    
    print("🔄 Generating test users...")
    users = generate_test_users()
    print(f"   Generated {len(users)} test users")
    
    print("🔄 Running audit...")
    report_text, results = generate_report(users, exercises)
    
    # Save text report
    timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
    report_filename = f"audit_report_{timestamp}.txt"
    with open(report_filename, 'w') as f:
        f.write(report_text)
    print(f"   Saved text report: {report_filename}")
    
    # Print summary
    print("\n" + "=" * 60)
    print("AUDIT COMPLETE")
    print("=" * 60)
    
    overall_scores = [r['grades']['overall']['score'] for r in results]
    avg = sum(overall_scores) / len(overall_scores)
    
    print(f"\n📊 SUMMARY:")
    print(f"   Total Users: {len(users)}")
    print(f"   Average Score: {avg:.1f}%")
    
    grade_dist = Counter(r['grades']['overall']['grade'] for r in results)
    print(f"\n   Grade Distribution:")
    for grade in ['A', 'B', 'C', 'D', 'F']:
        count = grade_dist.get(grade, 0)
        print(f"   {grade}: {'█' * count} {count}")
    
    # Show worst performers
    worst = sorted(results, key=lambda x: x['grades']['overall']['score'])[:5]
    print(f"\n   ⚠️ Lowest Scoring Users:")
    for r in worst:
        print(f"      • {r['user']['name']}: {r['grades']['overall']['score']}% ({r['grades']['overall']['grade']})")
        print(f"        Scenario: {r['user']['scenario']}")
    
    print(f"\n📄 Full report saved to: {report_filename}")
    print("\n" + report_text[:5000])  # Print first part

