#!/usr/bin/env python3
import os
import load_env  # noqa: F401 — auto-loads .env credentials
"""
Comprehensive Exercise Database Audit
=====================================
Scans EVERY exercise in the database and identifies:
- Mislabeled primary muscles
- Incorrect categories
- Equipment mismatches
- Other data quality issues

Outputs a CSV with:
- Original row (as-is)
- Suggested fix row (corrected data)
"""

import csv
import re
from datetime import datetime
from typing import Dict, List, Tuple, Optional
from supabase import create_client

# Supabase connection
SUPABASE_URL = os.environ.get("SUPABASE_URL", "https://ehooeghabzefgoqzugrc.supabase.co")
SUPABASE_KEY = os.environ.get("SUPABASE_ANON_KEY", "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVob29lZ2hhYnplZmdvcXp1Z3JjIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjM4NDc4NjQsImV4cCI6MjA3OTQyMzg2NH0.6-QWDr5B279hybtu9MbPVhmBKlyzFq1GK9P7zlDXuY0")

# ═══════════════════════════════════════════════════════════════════════════════
# MUSCLE CLASSIFICATION RULES
# ═══════════════════════════════════════════════════════════════════════════════

# Keywords in exercise names that indicate specific muscle groups
NAME_TO_MUSCLE_MAPPING = {
    # CHEST
    "chest": ["Chest"],
    "pec": ["Chest"],
    "bench press": ["Chest"],
    "push up": ["Chest"],
    "pushup": ["Chest"],
    "fly": ["Chest"],  # Most flys are chest
    "flye": ["Chest"],
    "dip": ["Lower Chest", "Triceps"],  # Dips target lower chest and triceps
    
    # BACK
    "lat pulldown": ["Lats"],
    "pulldown": ["Lats"],
    "pull down": ["Lats"],
    "pull-down": ["Lats"],
    "row": ["Back"],  # Generic row
    "bent over row": ["Back", "Lats"],
    "cable row": ["Back", "Lats"],
    "seated row": ["Back", "Lats"],
    "t-bar row": ["Back", "Lats"],
    "lat": ["Lats"],
    "pull up": ["Lats", "Back"],
    "pullup": ["Lats", "Back"],
    "chin up": ["Lats", "Biceps"],
    "chinup": ["Lats", "Biceps"],
    "back extension": ["Lower Back"],
    "hyperextension": ["Lower Back"],
    "deadlift": ["Back", "Hamstrings", "Glutes"],
    "good morning": ["Lower Back", "Hamstrings"],
    
    # SHOULDERS
    "shoulder press": ["Shoulders"],
    "overhead press": ["Shoulders"],
    "military press": ["Shoulders"],
    "lateral raise": ["Shoulders"],
    "front raise": ["Shoulders", "Front Delts"],
    "rear delt": ["Rear Delts", "Shoulders"],
    "face pull": ["Rear Delts", "Shoulders"],
    "upright row": ["Shoulders", "Traps"],
    "shrug": ["Traps"],  # CRITICAL: Shrugs are TRAPS, not chest!
    "arnold press": ["Shoulders"],
    "delt": ["Shoulders"],
    
    # ARMS - BICEPS
    "bicep curl": ["Biceps"],
    "biceps curl": ["Biceps"],
    "curl": ["Biceps"],  # Most curls are biceps
    "preacher curl": ["Biceps"],
    "hammer curl": ["Biceps", "Forearms"],
    "concentration curl": ["Biceps"],
    "incline curl": ["Biceps"],
    "barbell curl": ["Biceps"],
    "dumbbell curl": ["Biceps"],
    "cable curl": ["Biceps"],
    "ez bar curl": ["Biceps"],
    "spider curl": ["Biceps"],
    
    # ARMS - TRICEPS
    "tricep": ["Triceps"],
    "triceps": ["Triceps"],
    "pushdown": ["Triceps"],
    "push down": ["Triceps"],
    "push-down": ["Triceps"],
    "skull crusher": ["Triceps"],
    "skullcrusher": ["Triceps"],
    "kickback": ["Triceps"],
    "close grip bench": ["Triceps", "Chest"],
    "close grip press": ["Triceps", "Chest"],
    "overhead extension": ["Triceps"],
    "french press": ["Triceps"],
    "dip": ["Triceps", "Chest"],  # Dips also hit triceps
    
    # ARMS - FOREARMS
    "wrist curl": ["Forearms"],
    "wrist extension": ["Forearms"],
    "forearm": ["Forearms"],
    "reverse curl": ["Forearms", "Biceps"],
    "farmer": ["Forearms", "Traps"],
    
    # LEGS - QUADS
    "squat": ["Quads", "Glutes"],
    "leg press": ["Quads", "Glutes"],
    "leg extension": ["Quads"],
    "lunge": ["Quads", "Glutes"],
    "step up": ["Quads", "Glutes"],
    "hack squat": ["Quads"],
    "sissy squat": ["Quads"],
    "front squat": ["Quads"],
    "goblet squat": ["Quads", "Glutes"],
    
    # LEGS - HAMSTRINGS
    "hamstring": ["Hamstrings"],
    "leg curl": ["Hamstrings"],
    "lying leg curl": ["Hamstrings"],
    "seated leg curl": ["Hamstrings"],
    "romanian deadlift": ["Hamstrings", "Glutes"],
    "rdl": ["Hamstrings", "Glutes"],
    "stiff leg": ["Hamstrings"],
    "good morning": ["Hamstrings", "Lower Back"],
    
    # LEGS - GLUTES
    "glute": ["Glutes"],
    "hip thrust": ["Glutes"],
    "glute bridge": ["Glutes"],
    "kickback": ["Glutes"],  # Glute kickbacks
    "donkey kick": ["Glutes"],
    "hip extension": ["Glutes"],
    "hip abduction": ["Glutes"],
    "hip adduction": ["Adductors"],
    
    # LEGS - CALVES
    "calf raise": ["Calves"],
    "calf press": ["Calves"],
    "standing calf": ["Calves"],
    "seated calf": ["Calves"],
    "donkey calf": ["Calves"],
    
    # CORE
    "crunch": ["Abs"],
    "sit up": ["Abs"],
    "situp": ["Abs"],
    "plank": ["Abs", "Core"],
    "ab": ["Abs"],
    "abs": ["Abs"],
    "oblique": ["Obliques"],
    "russian twist": ["Obliques"],
    "side bend": ["Obliques"],
    "woodchop": ["Obliques", "Core"],
    "wood chop": ["Obliques", "Core"],
    "leg raise": ["Abs"],
    "hanging leg raise": ["Abs"],
    "knee raise": ["Abs"],
    "mountain climber": ["Abs", "Core"],
    "bicycle": ["Abs", "Obliques"],
    "dead bug": ["Core", "Abs"],
    "bird dog": ["Core", "Lower Back"],
    "hollow": ["Abs", "Core"],
    "v-up": ["Abs"],
    "v up": ["Abs"],
    
    # NECK
    "neck": ["Neck"],
    "neck curl": ["Neck"],
    "neck extension": ["Neck"],
}

# Category to expected primary muscles
CATEGORY_TO_MUSCLES = {
    "chest": ["Chest", "Upper Chest", "Lower Chest", "Mid Chest", "Pectorals"],
    "back": ["Back", "Lats", "Upper Back", "Lower Back", "Middle Back", "Rhomboids", "Traps"],
    "shoulders": ["Shoulders", "Front Delts", "Rear Delts", "Lateral Delts", "Delts", "Deltoids"],
    "biceps": ["Biceps", "Brachialis"],
    "triceps": ["Triceps"],
    "forearms": ["Forearms", "Wrist Flexors", "Wrist Extensors"],
    "legs": ["Quads", "Hamstrings", "Glutes", "Calves", "Adductors", "Abductors", "Hip Flexors"],
    "quads": ["Quads", "Quadriceps"],
    "hamstrings": ["Hamstrings"],
    "glutes": ["Glutes", "Gluteus"],
    "calves": ["Calves", "Gastrocnemius", "Soleus"],
    "abs": ["Abs", "Abdominals", "Core", "Obliques", "Transverse Abdominis"],
    "core": ["Core", "Abs", "Obliques"],
    "traps": ["Traps", "Trapezius"],
    "neck": ["Neck"],
    "cardio": [],  # Cardio doesn't have specific muscles
    "stretching": [],  # Stretching is flexible
    "plyometrics": [],  # Can target various muscles
    "full body": [],  # Multiple muscles
}

# Equipment validation patterns
EQUIPMENT_PATTERNS = {
    "barbell": ["barbell", "bar", "olympic"],
    "dumbbell": ["dumbbell", "dumbbells", "db"],
    "cable": ["cable", "pulley"],
    "machine": ["machine", "lever", "stack", "selectorized"],
    "kettlebell": ["kettlebell", "kb"],
    "bodyweight": ["bodyweight", "body weight", "bw"],
    "resistance band": ["band", "resistance band", "tube"],
    "medicine ball": ["medicine ball", "med ball"],
    "stability ball": ["stability ball", "swiss ball", "exercise ball"],
    "trx": ["trx", "suspension"],
    "smith machine": ["smith"],
    "ez bar": ["ez bar", "ez-bar", "curl bar"],
    "bench": ["bench"],
}

# ═══════════════════════════════════════════════════════════════════════════════
# AUDIT FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════════

def fetch_all_exercises() -> List[Dict]:
    """Fetch ALL exercises from Supabase"""
    print("📥 Fetching all exercises from Supabase...")
    supabase = create_client(SUPABASE_URL, SUPABASE_KEY)
    
    all_exercises = []
    offset = 0
    batch_size = 1000
    
    while True:
        response = supabase.table("exercises").select("*").range(offset, offset + batch_size - 1).execute()
        if not response.data:
            break
        all_exercises.extend(response.data)
        print(f"   Fetched {len(all_exercises)} exercises...")
        if len(response.data) < batch_size:
            break
        offset += batch_size
    
    print(f"✅ Total exercises fetched: {len(all_exercises)}")
    return all_exercises

def get_expected_muscles_from_name(name: str) -> List[str]:
    """Analyze exercise name and return expected primary muscles"""
    name_lower = name.lower()
    expected_muscles = []
    
    # Check each pattern (longer patterns first to avoid partial matches)
    patterns_by_length = sorted(NAME_TO_MUSCLE_MAPPING.keys(), key=len, reverse=True)
    
    for pattern in patterns_by_length:
        if pattern in name_lower:
            expected_muscles.extend(NAME_TO_MUSCLE_MAPPING[pattern])
    
    # Remove duplicates while preserving order
    seen = set()
    unique_muscles = []
    for m in expected_muscles:
        if m not in seen:
            seen.add(m)
            unique_muscles.append(m)
    
    return unique_muscles

def get_expected_muscles_from_category(category: str) -> List[str]:
    """Get expected muscles based on category"""
    if not category:
        return []
    return CATEGORY_TO_MUSCLES.get(category.lower(), [])

def normalize_muscle(muscle: str) -> str:
    """Normalize muscle name for comparison"""
    if not muscle:
        return ""
    muscle = muscle.lower().strip()
    
    # Common normalizations
    normalizations = {
        "pecs": "chest",
        "pectorals": "chest",
        "pectoral": "chest",
        "upper chest": "chest",
        "lower chest": "chest",
        "mid chest": "chest",
        "latissimus dorsi": "lats",
        "latissimus": "lats",
        "trapezius": "traps",
        "deltoids": "shoulders",
        "deltoid": "shoulders",
        "delts": "shoulders",
        "front delts": "shoulders",
        "rear delts": "shoulders",
        "lateral delts": "shoulders",
        "quadriceps": "quads",
        "gluteus": "glutes",
        "gluteus maximus": "glutes",
        "abdominals": "abs",
        "rectus abdominis": "abs",
        "gastrocnemius": "calves",
        "soleus": "calves",
        "brachialis": "biceps",
    }
    
    return normalizations.get(muscle, muscle)

def check_muscle_mismatch(name: str, primary_muscles: List[str], category: str) -> Tuple[bool, str, List[str]]:
    """
    Check if primary muscles match what's expected from the exercise name.
    Returns: (is_mismatch, reason, suggested_muscles)
    """
    if not primary_muscles:
        primary_muscles = []
    
    name_lower = name.lower()
    
    # Normalize primary muscles
    primary_normalized = [normalize_muscle(m) for m in primary_muscles if m]
    
    # Get expected muscles from name
    expected_from_name = get_expected_muscles_from_name(name)
    expected_normalized = [normalize_muscle(m) for m in expected_from_name]
    
    # CRITICAL CHECKS - Obvious mismatches
    
    # 1. SHRUG exercises should be TRAPS, never CHEST
    if "shrug" in name_lower:
        if any("chest" in m.lower() for m in primary_muscles):
            return True, "Shrug exercise incorrectly labeled as Chest (should be Traps)", ["Traps"]
        if not any("trap" in m.lower() for m in primary_muscles):
            return True, "Shrug exercise missing Traps as primary muscle", ["Traps"]
    
    # 2. LATERAL RAISE should be SHOULDERS, not CHEST
    if "lateral raise" in name_lower:
        if any("chest" in m.lower() for m in primary_muscles):
            return True, "Lateral Raise incorrectly labeled as Chest (should be Shoulders)", ["Shoulders"]
    
    # 3. FRONT RAISE should be SHOULDERS
    if "front raise" in name_lower:
        if any("chest" in m.lower() for m in primary_muscles):
            return True, "Front Raise incorrectly labeled as Chest (should be Shoulders/Front Delts)", ["Front Delts", "Shoulders"]
    
    # 4. REAR DELT exercises should be REAR DELTS/SHOULDERS
    if "rear delt" in name_lower or "reverse fly" in name_lower:
        if any("chest" in m.lower() for m in primary_muscles):
            return True, "Rear Delt exercise incorrectly labeled as Chest", ["Rear Delts", "Shoulders"]
    
    # 5. ROW exercises should be BACK, not CHEST (unless it's a specific chest variation)
    if "row" in name_lower and "upright row" not in name_lower:
        if any("chest" in m.lower() for m in primary_muscles) and "chest" not in name_lower:
            return True, "Row exercise incorrectly labeled as Chest (should be Back)", ["Back", "Lats"]
    
    # 6. CURL exercises should be BICEPS (unless it's a leg/hamstring curl, wrist curl, or nordic curl)
    leg_curl_keywords = ["leg curl", "hamstring curl", "nordic", "lying curl", "seated curl", "standing curl"]
    is_leg_curl = any(kw in name_lower for kw in leg_curl_keywords) and ("hamstring" in name_lower or "leg" in name_lower or "nordic" in name_lower or "thigh" in name_lower)
    
    # Only flag as bicep curl if it's clearly a bicep exercise
    is_bicep_curl = "curl" in name_lower and not is_leg_curl and "wrist" not in name_lower
    bicep_curl_indicators = ["bicep", "biceps", "arm curl", "dumbbell curl", "barbell curl", "cable curl", "preacher", "concentration", "hammer curl", "ez bar curl", "spider curl", "incline curl"]
    is_clearly_bicep = any(ind in name_lower for ind in bicep_curl_indicators)
    
    if is_bicep_curl and is_clearly_bicep:
        if any("chest" in m.lower() for m in primary_muscles):
            return True, "Bicep Curl exercise incorrectly labeled as Chest (should be Biceps)", ["Biceps"]
        if any("shoulder" in m.lower() for m in primary_muscles):
            return True, "Bicep Curl exercise incorrectly labeled as Shoulders (should be Biceps)", ["Biceps"]
    
    # 7. TRICEP exercises
    if "tricep" in name_lower or "pushdown" in name_lower or "skull crusher" in name_lower:
        if any("chest" in m.lower() for m in primary_muscles) and "press" not in name_lower:
            return True, "Tricep exercise incorrectly labeled as Chest", ["Triceps"]
    
    # 8. LAT PULLDOWN should be LATS/BACK
    if "pulldown" in name_lower or "pull down" in name_lower or "pull-down" in name_lower:
        if any("chest" in m.lower() for m in primary_muscles):
            return True, "Pulldown exercise incorrectly labeled as Chest (should be Lats)", ["Lats", "Back"]
    
    # 9. PULL UP should be BACK/LATS
    if "pull up" in name_lower or "pullup" in name_lower or "chin up" in name_lower:
        if any("chest" in m.lower() for m in primary_muscles):
            return True, "Pull-up exercise incorrectly labeled as Chest (should be Back/Lats)", ["Lats", "Back"]
    
    # 10. DEADLIFT variations
    if "deadlift" in name_lower:
        if any("chest" in m.lower() for m in primary_muscles):
            return True, "Deadlift incorrectly labeled as Chest", ["Back", "Hamstrings", "Glutes"]
    
    # 11. SQUAT variations
    if "squat" in name_lower:
        if any("chest" in m.lower() for m in primary_muscles):
            return True, "Squat incorrectly labeled as Chest (should be Quads/Glutes)", ["Quads", "Glutes"]
        if any("back" in m.lower() for m in primary_muscles) and "lower back" not in " ".join(m.lower() for m in primary_muscles):
            return True, "Squat should primarily target Quads/Glutes, not Back", ["Quads", "Glutes"]
    
    # 12. LUNGE variations
    if "lunge" in name_lower:
        if any("chest" in m.lower() for m in primary_muscles):
            return True, "Lunge incorrectly labeled as Chest (should be Quads/Glutes)", ["Quads", "Glutes"]
    
    # 13. CALF exercises
    if "calf" in name_lower:
        if any("chest" in m.lower() for m in primary_muscles):
            return True, "Calf exercise incorrectly labeled as Chest", ["Calves"]
        if not any("calf" in m.lower() or "calves" in m.lower() for m in primary_muscles):
            return True, "Calf exercise missing Calves as primary", ["Calves"]
    
    # 14. AB/CORE exercises
    if "crunch" in name_lower or "sit up" in name_lower or "situp" in name_lower:
        if any("chest" in m.lower() for m in primary_muscles):
            return True, "Ab exercise incorrectly labeled as Chest", ["Abs"]
    
    # 15. PLANK exercises (context dependent)
    if "plank" in name_lower and "push" not in name_lower:
        if any("chest" in m.lower() for m in primary_muscles):
            return True, "Plank exercise incorrectly labeled as Chest (should be Core/Abs)", ["Core", "Abs"]
    
    # 16. HIP THRUST should be GLUTES
    if "hip thrust" in name_lower:
        if any("chest" in m.lower() for m in primary_muscles):
            return True, "Hip Thrust incorrectly labeled as Chest (should be Glutes)", ["Glutes"]
    
    # 17. GLUTE exercises
    if "glute" in name_lower:
        if any("chest" in m.lower() for m in primary_muscles):
            return True, "Glute exercise incorrectly labeled as Chest", ["Glutes"]
    
    # 18. LEG PRESS/LEG EXTENSION
    if "leg press" in name_lower or "leg extension" in name_lower:
        if any("chest" in m.lower() for m in primary_muscles):
            return True, "Leg exercise incorrectly labeled as Chest", ["Quads"]
    
    # 19. LEG CURL
    if "leg curl" in name_lower:
        if any("chest" in m.lower() for m in primary_muscles):
            return True, "Leg Curl incorrectly labeled as Chest (should be Hamstrings)", ["Hamstrings"]
    
    # 20. FACE PULL
    if "face pull" in name_lower:
        if any("chest" in m.lower() for m in primary_muscles):
            return True, "Face Pull incorrectly labeled as Chest (should be Rear Delts)", ["Rear Delts", "Shoulders"]
    
    # Check category vs muscle consistency
    if category:
        category_lower = category.lower()
        expected_from_category = get_expected_muscles_from_category(category)
        
        # If category is specific but muscles don't match
        if expected_from_category and primary_muscles:
            category_muscle_normalized = [normalize_muscle(m) for m in expected_from_category]
            has_match = any(normalize_muscle(pm) in category_muscle_normalized for pm in primary_muscles)
            
            if not has_match and category_lower not in ["cardio", "stretching", "plyometrics", "full body"]:
                # Only flag if there's a clear mismatch
                if category_lower == "chest" and not any("chest" in m.lower() for m in primary_muscles):
                    pass  # Category says chest but primary muscles don't include chest - might be intentional
                elif category_lower == "back" and any("chest" in m.lower() for m in primary_muscles):
                    return True, f"Category is Back but primary muscle is Chest", expected_from_category[:2]
    
    return False, "", []

def check_equipment_consistency(name: str, equipment: str) -> Tuple[bool, str, str]:
    """
    Check if equipment field is consistent with exercise name.
    Returns: (is_issue, reason, suggested_equipment)
    """
    if not equipment:
        # Try to infer equipment from name
        name_lower = name.lower()
        
        if "barbell" in name_lower:
            return True, "Missing equipment field (exercise name suggests Barbell)", "Barbell"
        if "dumbbell" in name_lower:
            return True, "Missing equipment field (exercise name suggests Dumbbells)", "Dumbbells"
        if "cable" in name_lower:
            return True, "Missing equipment field (exercise name suggests Cable)", "Cable Machine"
        if "machine" in name_lower or "lever" in name_lower:
            return True, "Missing equipment field (exercise name suggests Machine)", "Machine"
        if "kettlebell" in name_lower:
            return True, "Missing equipment field (exercise name suggests Kettlebell)", "Kettlebell"
        if "smith" in name_lower:
            return True, "Missing equipment field (exercise name suggests Smith Machine)", "Smith Machine"
        if "ez bar" in name_lower or "ez-bar" in name_lower:
            return True, "Missing equipment field (exercise name suggests EZ Bar)", "EZ Bar"
        if "trx" in name_lower or "suspension" in name_lower:
            return True, "Missing equipment field (exercise name suggests TRX)", "TRX"
        
        return False, "", ""
    
    name_lower = name.lower()
    equipment_lower = equipment.lower()
    
    # Check for inconsistencies
    if "barbell" in name_lower and "barbell" not in equipment_lower:
        if "dumbbell" in equipment_lower:
            return True, "Name says Barbell but equipment says Dumbbell", equipment.replace("Dumbbell", "Barbell").replace("dumbbell", "Barbell")
    
    if "dumbbell" in name_lower and "dumbbell" not in equipment_lower:
        if "barbell" in equipment_lower:
            return True, "Name says Dumbbell but equipment says Barbell", equipment.replace("Barbell", "Dumbbells").replace("barbell", "Dumbbells")
    
    if "cable" in name_lower and "cable" not in equipment_lower and "pulley" not in equipment_lower:
        if not any(x in equipment_lower for x in ["machine", "lever"]):
            return True, "Name suggests Cable but equipment doesn't include it", f"Cable Machine, {equipment}" if equipment else "Cable Machine"
    
    return False, "", ""

def check_category_consistency(name: str, category: str, primary_muscles: List[str]) -> Tuple[bool, str, str]:
    """
    Check if category is consistent with exercise name and muscles.
    Returns: (is_issue, reason, suggested_category)
    """
    if not category:
        # Try to infer category from name or muscles
        expected_muscles = get_expected_muscles_from_name(name)
        if expected_muscles:
            first_muscle = expected_muscles[0].lower()
            if "chest" in first_muscle:
                return True, "Missing category (should be Chest)", "Chest"
            elif "lat" in first_muscle or "back" in first_muscle:
                return True, "Missing category (should be Back)", "Back"
            elif "shoulder" in first_muscle or "delt" in first_muscle:
                return True, "Missing category (should be Shoulders)", "Shoulders"
            elif "bicep" in first_muscle:
                return True, "Missing category (should be Biceps)", "Biceps"
            elif "tricep" in first_muscle:
                return True, "Missing category (should be Triceps)", "Triceps"
            elif "quad" in first_muscle or "hamstring" in first_muscle or "glute" in first_muscle:
                return True, "Missing category (should be Legs)", "Legs"
            elif "ab" in first_muscle or "core" in first_muscle:
                return True, "Missing category (should be Abs)", "Abs"
        return False, "", ""
    
    name_lower = name.lower()
    category_lower = category.lower()
    
    # Check obvious mismatches
    if "shrug" in name_lower and category_lower == "chest":
        return True, "Shrug exercise in Chest category (should be Shoulders or Traps)", "Shoulders"
    
    if "lateral raise" in name_lower and category_lower == "chest":
        return True, "Lateral Raise in Chest category (should be Shoulders)", "Shoulders"
    
    # Only flag bicep curls, not leg curls / hamstring curls
    leg_curl_keywords = ["leg curl", "hamstring curl", "nordic", "hamstring"]
    is_leg_curl = any(kw in name_lower for kw in leg_curl_keywords)
    bicep_curl_indicators = ["bicep", "biceps", "arm curl", "preacher", "concentration", "hammer curl", "spider curl"]
    is_clearly_bicep = any(ind in name_lower for ind in bicep_curl_indicators)
    
    if "curl" in name_lower and not is_leg_curl and is_clearly_bicep:
        if category_lower not in ["biceps", "arms"]:
            return True, "Bicep Curl exercise should be in Biceps category", "Biceps"
    
    if "tricep" in name_lower or "pushdown" in name_lower:
        if category_lower not in ["triceps", "arms"]:
            return True, "Tricep exercise should be in Triceps category", "Triceps"
    
    if "squat" in name_lower and category_lower == "chest":
        return True, "Squat in Chest category (should be Legs)", "Legs"
    
    if "deadlift" in name_lower and category_lower == "chest":
        return True, "Deadlift in Chest category (should be Back or Legs)", "Back"
    
    return False, "", ""

def check_missing_fields(exercise: Dict) -> List[Tuple[str, str]]:
    """Check for missing or empty required fields"""
    issues = []
    
    required_fields = ["name", "category", "equipment", "primary_muscles"]
    
    for field in required_fields:
        value = exercise.get(field)
        if value is None or value == "" or value == []:
            issues.append((field, f"Missing or empty {field}"))
    
    return issues

def audit_exercise(exercise: Dict) -> Tuple[bool, List[str], Dict]:
    """
    Audit a single exercise for data quality issues.
    Returns: (has_issues, list_of_issues, suggested_fixes)
    """
    name = exercise.get("name", "")
    equipment = exercise.get("equipment", "")
    category = exercise.get("category", "")
    primary_muscles = exercise.get("primary_muscles", [])
    secondary_muscles = exercise.get("secondary_muscles", [])
    
    if isinstance(primary_muscles, str):
        primary_muscles = [primary_muscles] if primary_muscles else []
    if isinstance(secondary_muscles, str):
        secondary_muscles = [secondary_muscles] if secondary_muscles else []
    
    issues = []
    suggested_fixes = {}
    
    # 1. Check muscle mismatch
    is_mismatch, reason, suggested_muscles = check_muscle_mismatch(name, primary_muscles, category)
    if is_mismatch:
        issues.append(f"MUSCLE: {reason}")
        suggested_fixes["primary_muscles"] = suggested_muscles
    
    # 2. Check equipment consistency
    is_equip_issue, equip_reason, suggested_equip = check_equipment_consistency(name, equipment)
    if is_equip_issue:
        issues.append(f"EQUIPMENT: {equip_reason}")
        suggested_fixes["equipment"] = suggested_equip
    
    # 3. Check category consistency
    is_cat_issue, cat_reason, suggested_cat = check_category_consistency(name, category, primary_muscles)
    if is_cat_issue:
        issues.append(f"CATEGORY: {cat_reason}")
        suggested_fixes["category"] = suggested_cat
    
    # 4. Check missing fields
    missing_issues = check_missing_fields(exercise)
    for field, msg in missing_issues:
        issues.append(f"MISSING: {msg}")
    
    return len(issues) > 0, issues, suggested_fixes

def run_audit():
    """Run the full database audit"""
    print("\n" + "="*80)
    print("🔍 COMPREHENSIVE EXERCISE DATABASE AUDIT")
    print("="*80)
    
    # Fetch all exercises
    exercises = fetch_all_exercises()
    
    if not exercises:
        print("❌ No exercises found!")
        return
    
    # Audit each exercise
    print(f"\n📊 Auditing {len(exercises)} exercises...")
    
    issues_found = []
    
    for i, exercise in enumerate(exercises):
        if (i + 1) % 500 == 0:
            print(f"   Progress: {i + 1}/{len(exercises)}")
        
        has_issues, issues, suggested_fixes = audit_exercise(exercise)
        
        if has_issues:
            issues_found.append({
                "exercise": exercise,
                "issues": issues,
                "suggested_fixes": suggested_fixes
            })
    
    print(f"\n✅ Audit complete!")
    print(f"   Total exercises: {len(exercises)}")
    print(f"   Exercises with issues: {len(issues_found)}")
    print(f"   Clean exercises: {len(exercises) - len(issues_found)}")
    
    # Generate CSV
    if issues_found:
        generate_csv(issues_found, exercises)
    else:
        print("\n🎉 No issues found! Database looks clean.")
    
    # Print summary of issues by type
    print("\n" + "="*80)
    print("📊 ISSUE SUMMARY BY TYPE")
    print("="*80)
    
    issue_counts = {}
    for item in issues_found:
        for issue in item["issues"]:
            issue_type = issue.split(":")[0]
            issue_counts[issue_type] = issue_counts.get(issue_type, 0) + 1
    
    for issue_type, count in sorted(issue_counts.items(), key=lambda x: -x[1]):
        print(f"   {issue_type}: {count}")
    
    return issues_found

def generate_csv(issues_found: List[Dict], all_exercises: List[Dict]):
    """Generate CSV with original and suggested fix rows"""
    
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    filename = f"/Users/josephreed/Desktop/Workout App/exercise_audit_{timestamp}.csv"
    
    # Get all column names from first exercise
    if not all_exercises:
        return
    
    columns = list(all_exercises[0].keys())
    
    # Add audit columns
    audit_columns = ["_ROW_TYPE", "_ISSUES", "_NEEDS_REVIEW"]
    all_columns = audit_columns + columns
    
    print(f"\n📝 Generating CSV: {filename}")
    
    with open(filename, 'w', newline='', encoding='utf-8') as csvfile:
        writer = csv.DictWriter(csvfile, fieldnames=all_columns)
        writer.writeheader()
        
        for item in issues_found:
            exercise = item["exercise"]
            issues = item["issues"]
            suggested_fixes = item["suggested_fixes"]
            
            # Write original row
            original_row = {col: exercise.get(col, "") for col in columns}
            original_row["_ROW_TYPE"] = "ORIGINAL"
            original_row["_ISSUES"] = " | ".join(issues)
            original_row["_NEEDS_REVIEW"] = "YES"
            
            # Convert lists to strings for CSV
            for key, value in original_row.items():
                if isinstance(value, list):
                    original_row[key] = str(value)
            
            writer.writerow(original_row)
            
            # Write suggested fix row
            fixed_row = {col: exercise.get(col, "") for col in columns}
            
            # Apply suggested fixes
            for field, fix in suggested_fixes.items():
                fixed_row[field] = fix
            
            fixed_row["_ROW_TYPE"] = "SUGGESTED_FIX"
            fixed_row["_ISSUES"] = ""
            fixed_row["_NEEDS_REVIEW"] = ""
            
            # Convert lists to strings for CSV
            for key, value in fixed_row.items():
                if isinstance(value, list):
                    fixed_row[key] = str(value)
            
            writer.writerow(fixed_row)
    
    print(f"✅ CSV generated: {filename}")
    print(f"   Total rows: {len(issues_found) * 2} ({len(issues_found)} original + {len(issues_found)} suggested fixes)")
    
    return filename

if __name__ == "__main__":
    run_audit()
